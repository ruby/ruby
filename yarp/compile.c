#include "yarp/extension.h"

typedef enum {
    YP_ISEQ_TYPE_TOP,
    YP_ISEQ_TYPE_BLOCK
} yp_iseq_type_t;

typedef enum {
    YP_RUBY_EVENT_B_CALL,
    YP_RUBY_EVENT_B_RETURN
} yp_ruby_event_t;

typedef struct yp_iseq_compiler {
    // This is the parent compiler. It is used to communicate between ISEQs that
    // need to be able to jump back to the parent ISEQ.
    struct yp_iseq_compiler *parent;

    // This is the list of local variables that are defined on this scope.
    yp_constant_id_list_t *locals;

    // This is the instruction sequence that we are compiling. It's actually just
    // a Ruby array that maps to the output of RubyVM::InstructionSequence#to_a.
    VALUE insns;

    // This is a list of IDs coming from the instructions that are being compiled.
    // In theory they should be deterministic, but we don't have that
    // functionality yet. Fortunately you can pass -1 for all of them and
    // everything for the most part continues to work.
    VALUE node_ids;

    // This is the current size of the instruction sequence's stack.
    int stack_size;

    // This is the maximum size of the instruction sequence's stack.
    int stack_max;

    // This is the name of the instruction sequence.
    const char *name;

    // This is the type of the instruction sequence.
    yp_iseq_type_t type;

    // This is the optional argument information.
    VALUE optionals;

    // This is the number of arguments.
    int arg_size;

    // This is the current size of the instruction sequence's instructions and
    // operands.
    size_t size;

    // This is the index of the current inline storage.
    size_t inline_storage_index;
} yp_iseq_compiler_t;

static void
yp_iseq_compiler_init(yp_iseq_compiler_t *compiler, yp_iseq_compiler_t *parent, yp_constant_id_list_t *locals, const char *name, yp_iseq_type_t type) {
    *compiler = (yp_iseq_compiler_t) {
        .parent = parent,
        .locals = locals,
        .insns = rb_ary_new(),
        .node_ids = rb_ary_new(),
        .stack_size = 0,
        .stack_max = 0,
        .name = name,
        .type = type,
        .optionals = rb_hash_new(),
        .arg_size = 0,
        .size = 0,
        .inline_storage_index = 0
    };
}

/******************************************************************************/
/* Utilities                                                                  */
/******************************************************************************/

static inline int
sizet2int(size_t value) {
    if (value > INT_MAX) rb_raise(rb_eRuntimeError, "value too large");
    return (int) value;
}

static int
local_index(yp_iseq_compiler_t *compiler, yp_constant_id_t constant_id, int depth) {
    int compiler_index;
    yp_iseq_compiler_t *local_compiler = compiler;

    for (compiler_index = 0; compiler_index < depth; compiler_index++) {
        local_compiler = local_compiler->parent;
        assert(local_compiler != NULL);
    }

    size_t index;
    for (index = 0; index < local_compiler->locals->size; index++) {
        if (local_compiler->locals->ids[index] == constant_id) {
            return sizet2int(local_compiler->locals->size - index + 2);
        }
    }

    return -1;
}

/******************************************************************************/
/* Parse specific VALUEs from strings                                         */
/******************************************************************************/

static VALUE
parse_number(const char *start, const char *end) {
    size_t length = end - start;

    char *buffer = alloca(length + 1);
    memcpy(buffer, start, length);

    buffer[length] = '\0';
    return rb_cstr_to_inum(buffer, -10, Qfalse);
}

static inline VALUE
parse_string(yp_string_t *string) {
    return rb_str_new(yp_string_source(string), yp_string_length(string));
}

static inline ID
parse_symbol(const char *start, const char *end) {
    return rb_intern2(start, end - start);
}

static inline ID
parse_location_symbol(yp_location_t *location) {
    return parse_symbol(location->start, location->end);
}

static inline ID
parse_node_symbol(yp_node_t *node) {
    return parse_symbol(node->location.start, node->location.end);
}

static inline ID
parse_string_symbol(yp_string_t *string) {
    const char *start = yp_string_source(string);
    return parse_symbol(start, start + yp_string_length(string));
}

/******************************************************************************/
/* Create Ruby objects for compilation                                        */
/******************************************************************************/

static VALUE
yp_iseq_new(yp_iseq_compiler_t *compiler) {
    VALUE code_location = rb_ary_new_capa(4);
    rb_ary_push(code_location, INT2FIX(1));
    rb_ary_push(code_location, INT2FIX(0));
    rb_ary_push(code_location, INT2FIX(1));
    rb_ary_push(code_location, INT2FIX(0));

    VALUE data = rb_hash_new();
    rb_hash_aset(data, ID2SYM(rb_intern("arg_size")), INT2FIX(compiler->arg_size));
    rb_hash_aset(data, ID2SYM(rb_intern("local_size")), INT2FIX(0));
    rb_hash_aset(data, ID2SYM(rb_intern("stack_max")), INT2FIX(compiler->stack_max));
    rb_hash_aset(data, ID2SYM(rb_intern("node_id")), INT2FIX(-1));
    rb_hash_aset(data, ID2SYM(rb_intern("code_location")), code_location);
    rb_hash_aset(data, ID2SYM(rb_intern("node_ids")), compiler->node_ids);

    VALUE type = Qnil;
    switch (compiler->type) {
        case YP_ISEQ_TYPE_TOP:
            type = ID2SYM(rb_intern("top"));
            break;
        case YP_ISEQ_TYPE_BLOCK:
            type = ID2SYM(rb_intern("block"));
            break;
    }

    VALUE iseq = rb_ary_new_capa(13);
    rb_ary_push(iseq, rb_str_new_cstr("YARVInstructionSequence/SimpleDataFormat"));
    rb_ary_push(iseq, INT2FIX(3));
    rb_ary_push(iseq, INT2FIX(3));
    rb_ary_push(iseq, INT2FIX(1));
    rb_ary_push(iseq, data);
    rb_ary_push(iseq, rb_str_new_cstr(compiler->name));
    rb_ary_push(iseq, rb_str_new_cstr("<compiled>"));
    rb_ary_push(iseq, rb_str_new_cstr("<compiled>"));
    rb_ary_push(iseq, INT2FIX(1));
    rb_ary_push(iseq, type);
    rb_ary_push(iseq, rb_ary_new());
    rb_ary_push(iseq, compiler->optionals);
    rb_ary_push(iseq, rb_ary_new());
    rb_ary_push(iseq, compiler->insns);

    return iseq;
}

// static const int YP_CALLDATA_ARGS_SPLAT = 1 << 0;
// static const int YP_CALLDATA_ARGS_BLOCKARG = 1 << 1;
static const int YP_CALLDATA_FCALL = 1 << 2;
static const int YP_CALLDATA_VCALL = 1 << 3;
static const int YP_CALLDATA_ARGS_SIMPLE = 1 << 4;
// static const int YP_CALLDATA_BLOCKISEQ = 1 << 5;
// static const int YP_CALLDATA_KWARG = 1 << 6;
// static const int YP_CALLDATA_KW_SPLAT = 1 << 7;
// static const int YP_CALLDATA_TAILCALL = 1 << 8;
// static const int YP_CALLDATA_SUPER = 1 << 9;
// static const int YP_CALLDATA_ZSUPER = 1 << 10;
// static const int YP_CALLDATA_OPT_SEND = 1 << 11;
// static const int YP_CALLDATA_KW_SPLAT_MUT = 1 << 12;

static VALUE
yp_calldata_new(ID mid, int flag, size_t orig_argc) {
    VALUE calldata = rb_hash_new();

    rb_hash_aset(calldata, ID2SYM(rb_intern("mid")), ID2SYM(mid));
    rb_hash_aset(calldata, ID2SYM(rb_intern("flag")), INT2FIX(flag));
    rb_hash_aset(calldata, ID2SYM(rb_intern("orig_argc")), INT2FIX(orig_argc));

    return calldata;
}

static inline VALUE
yp_inline_storage_new(yp_iseq_compiler_t *compiler) {
    return INT2FIX(compiler->inline_storage_index++);
}

/******************************************************************************/
/* Push instructions onto a compiler                                          */
/******************************************************************************/

static VALUE
push_insn(yp_iseq_compiler_t *compiler, int stack_change, size_t size, ...) {
    va_list opnds;
    va_start(opnds, size);

    VALUE insn = rb_ary_new_capa(size);
    for (size_t index = 0; index < size; index++) {
        rb_ary_push(insn, va_arg(opnds, VALUE));
    }

    va_end(opnds);

    compiler->stack_size += stack_change;
    if (compiler->stack_size > compiler->stack_max) {
        compiler->stack_max = compiler->stack_size;
    }

    compiler->size += size;
    rb_ary_push(compiler->insns, insn);
    rb_ary_push(compiler->node_ids, INT2FIX(-1));

    return insn;
}

static VALUE
push_label(yp_iseq_compiler_t *compiler) {
    VALUE label = ID2SYM(rb_intern_str(rb_sprintf("label_%zu", compiler->size)));
    rb_ary_push(compiler->insns, label);
    return label;
}

static void
push_ruby_event(yp_iseq_compiler_t *compiler, yp_ruby_event_t event) {
    switch (event) {
        case YP_RUBY_EVENT_B_CALL:
            rb_ary_push(compiler->insns, ID2SYM(rb_intern("RUBY_EVENT_B_CALL")));
            break;
        case YP_RUBY_EVENT_B_RETURN:
            rb_ary_push(compiler->insns, ID2SYM(rb_intern("RUBY_EVENT_B_RETURN")));
            break;
    }
}

static inline VALUE
push_anytostring(yp_iseq_compiler_t *compiler) {
    return push_insn(compiler, -2 + 1, 1, ID2SYM(rb_intern("anytostring")));
}

static inline VALUE
push_branchif(yp_iseq_compiler_t *compiler, VALUE label) {
    return push_insn(compiler, -1 + 0, 2, ID2SYM(rb_intern("branchif")), label);
}

static inline VALUE
push_branchunless(yp_iseq_compiler_t *compiler, VALUE label) {
    return push_insn(compiler, -1 + 0, 2, ID2SYM(rb_intern("branchunless")), label);
}

static inline VALUE
push_concatstrings(yp_iseq_compiler_t *compiler, int count) {
    return push_insn(compiler, -count + 1, 2, ID2SYM(rb_intern("concatstrings")), INT2FIX(count));
}

static inline VALUE
push_dup(yp_iseq_compiler_t *compiler) {
    return push_insn(compiler, -1 + 2, 1, ID2SYM(rb_intern("dup")));
}

static inline VALUE
push_getclassvariable(yp_iseq_compiler_t *compiler, VALUE name, VALUE inline_storage) {
    return push_insn(compiler, -0 + 1, 3, ID2SYM(rb_intern("getclassvariable")), name, inline_storage);
}

static inline VALUE
push_getconstant(yp_iseq_compiler_t *compiler, VALUE name) {
    return push_insn(compiler, -2 + 1, 2, ID2SYM(rb_intern("getconstant")), name);
}

static inline VALUE
push_getglobal(yp_iseq_compiler_t *compiler, VALUE name) {
    return push_insn(compiler, -0 + 1, 2, ID2SYM(rb_intern("getglobal")), name);
}

static inline VALUE
push_getinstancevariable(yp_iseq_compiler_t *compiler, VALUE name, VALUE inline_storage) {
    return push_insn(compiler, -0 + 1, 3, ID2SYM(rb_intern("getinstancevariable")), name, inline_storage);
}

static inline VALUE
push_getlocal(yp_iseq_compiler_t *compiler, VALUE index, VALUE depth) {
    return push_insn(compiler, -0 + 1, 3, ID2SYM(rb_intern("getlocal")), index, depth);
}

static inline VALUE
push_leave(yp_iseq_compiler_t *compiler) {
    return push_insn(compiler, -1 + 0, 1, ID2SYM(rb_intern("leave")));
}

static inline VALUE
push_newarray(yp_iseq_compiler_t *compiler, int count) {
    return push_insn(compiler, -count + 1, 2, ID2SYM(rb_intern("newarray")), INT2FIX(count));
}

static inline VALUE
push_newhash(yp_iseq_compiler_t *compiler, int count) {
    return push_insn(compiler, -count + 1, 2, ID2SYM(rb_intern("newhash")), INT2FIX(count));
}

static inline VALUE
push_newrange(yp_iseq_compiler_t *compiler, VALUE flag) {
    return push_insn(compiler, -2 + 1, 2, ID2SYM(rb_intern("newrange")), flag);
}

static inline VALUE
push_nop(yp_iseq_compiler_t *compiler) {
    return push_insn(compiler, -2 + 1, 1, ID2SYM(rb_intern("nop")));
}

static inline VALUE
push_objtostring(yp_iseq_compiler_t *compiler, VALUE calldata) {
    return push_insn(compiler, -1 + 1, 2, ID2SYM(rb_intern("objtostring")), calldata);
}

static inline VALUE
push_pop(yp_iseq_compiler_t *compiler) {
    return push_insn(compiler, -1 + 0, 1, ID2SYM(rb_intern("pop")));
}

static inline VALUE
push_putnil(yp_iseq_compiler_t *compiler) {
    return push_insn(compiler, -0 + 1, 1, ID2SYM(rb_intern("putnil")));
}

static inline VALUE
push_putobject(yp_iseq_compiler_t *compiler, VALUE value) {
    return push_insn(compiler, -0 + 1, 2, ID2SYM(rb_intern("putobject")), value);
}

static inline VALUE
push_putself(yp_iseq_compiler_t *compiler) {
    return push_insn(compiler, -0 + 1, 1, ID2SYM(rb_intern("putself")));
}

static inline VALUE
push_setlocal(yp_iseq_compiler_t *compiler, VALUE index, VALUE depth) {
    return push_insn(compiler, -1 + 0, 3, ID2SYM(rb_intern("setlocal")), index, depth);
}

static const VALUE YP_SPECIALOBJECT_VMCORE = INT2FIX(1);
static const VALUE YP_SPECIALOBJECT_CBASE = INT2FIX(2);
// static const VALUE YP_SPECIALOBJECT_CONST_BASE = INT2FIX(3);

static inline VALUE
push_putspecialobject(yp_iseq_compiler_t *compiler, VALUE object) {
    return push_insn(compiler, -0 + 1, 2, ID2SYM(rb_intern("putspecialobject")), object);
}

static inline VALUE
push_putstring(yp_iseq_compiler_t *compiler, VALUE string) {
    return push_insn(compiler, -0 + 1, 2, ID2SYM(rb_intern("putstring")), string);
}

static inline VALUE
push_send(yp_iseq_compiler_t *compiler, int stack_change, VALUE calldata, VALUE block_iseq) {
    return push_insn(compiler, stack_change, 3, ID2SYM(rb_intern("send")), calldata, block_iseq);
}

static inline VALUE
push_setclassvariable(yp_iseq_compiler_t *compiler, VALUE name, VALUE inline_storage) {
    return push_insn(compiler, -1 + 0, 3, ID2SYM(rb_intern("setclassvariable")), name, inline_storage);
}

static inline VALUE
push_setglobal(yp_iseq_compiler_t *compiler, VALUE name) {
    return push_insn(compiler, -1 + 0, 2, ID2SYM(rb_intern("setglobal")), name);
}

static inline VALUE
push_setinstancevariable(yp_iseq_compiler_t *compiler, VALUE name, VALUE inline_storage) {
    return push_insn(compiler, -1 + 0, 3, ID2SYM(rb_intern("setinstancevariable")), name, inline_storage);
}

/******************************************************************************/
/* Compile an AST node using the given compiler                               */
/******************************************************************************/

static void
yp_compile_node(yp_iseq_compiler_t *compiler, yp_node_t *base_node) {
    switch (base_node->type) {
        case YP_NODE_ALIAS_NODE: {
            yp_alias_node_t *node = (yp_alias_node_t *) base_node;

            push_putspecialobject(compiler, YP_SPECIALOBJECT_VMCORE);
            push_putspecialobject(compiler, YP_SPECIALOBJECT_CBASE);
            yp_compile_node(compiler, node->new_name);
            yp_compile_node(compiler, node->old_name);
            push_send(compiler, -3, yp_calldata_new(rb_intern("core#set_method_alias"), YP_CALLDATA_ARGS_SIMPLE, 3), Qnil);

            return;
        }
        case YP_NODE_AND_NODE: {
            yp_and_node_t *node = (yp_and_node_t *) base_node;

            yp_compile_node(compiler, node->left);
            push_dup(compiler);
            VALUE branchunless = push_branchunless(compiler, Qnil);

            push_pop(compiler);
            yp_compile_node(compiler, node->right);

            VALUE label = push_label(compiler);
            rb_ary_store(branchunless, 1, label);

            return;
        }
        case YP_NODE_ARGUMENTS_NODE: {
            yp_arguments_node_t *node = (yp_arguments_node_t *) base_node;
            yp_node_list_t node_list = node->arguments;
            for (size_t index = 0; index < node_list.size; index++) {
                yp_compile_node(compiler, node_list.nodes[index]);
            }
            return;
        }
        case YP_NODE_ARRAY_NODE: {
            yp_array_node_t *node = (yp_array_node_t *) base_node;
            yp_node_list_t elements = node->elements;
            for (size_t index = 0; index < elements.size; index++) {
                yp_compile_node(compiler, elements.nodes[index]);
            }
            push_newarray(compiler, sizet2int(elements.size));
            return;
        }
        case YP_NODE_ASSOC_NODE: {
            yp_assoc_node_t *node = (yp_assoc_node_t *) base_node;
            yp_compile_node(compiler, node->key);
            yp_compile_node(compiler, node->value);
            return;
        }
        case YP_NODE_BLOCK_NODE: {
            yp_block_node_t *node = (yp_block_node_t *) base_node;

            VALUE optional_labels = rb_ary_new();
            if (node->parameters &&
                    node->parameters->parameters &&
                    node->parameters->parameters->optionals.size > 0) {
                compiler->arg_size += node->parameters->parameters->optionals.size;

                yp_node_list_t *optionals = &node->parameters->parameters->optionals;
                for (size_t i = 0; i < optionals->size; i++) {
                    VALUE label = push_label(compiler);
                    rb_ary_push(optional_labels, label);
                    yp_compile_node(compiler, optionals->nodes[i]);
                }
                VALUE label = push_label(compiler);
                rb_ary_push(optional_labels, label);
                rb_hash_aset(compiler->optionals, ID2SYM(rb_intern("opt")), optional_labels);

                push_ruby_event(compiler, YP_RUBY_EVENT_B_CALL);
                push_nop(compiler);
            } else {
                push_ruby_event(compiler, YP_RUBY_EVENT_B_CALL);
            }



            if (node->statements) {
                yp_compile_node(compiler, node->statements);
            } else {
                push_putnil(compiler);
            }
            push_ruby_event(compiler, YP_RUBY_EVENT_B_RETURN);
            push_leave(compiler);
            return;
        }
        case YP_NODE_CALL_NODE: {
            yp_call_node_t *node = (yp_call_node_t *) base_node;

            ID mid = parse_location_symbol(&node->message_loc);
            int flags = 0;
            size_t orig_argc;

            if (node->receiver == NULL) {
                push_putself(compiler);
            } else {
                yp_compile_node(compiler, node->receiver);
            }

            if (node->arguments == NULL) {
                if (flags & YP_CALLDATA_FCALL) flags |= YP_CALLDATA_VCALL;
                orig_argc = 0;
            } else {
                yp_arguments_node_t *arguments = node->arguments;
                yp_compile_node(compiler, (yp_node_t *) arguments);
                orig_argc = arguments->arguments.size;
            }

            VALUE block_iseq = Qnil;
            if (node->block != NULL) {
                yp_iseq_compiler_t block_compiler;
                yp_iseq_compiler_init(
                    &block_compiler,
                    compiler,
                    &node->block->locals,
                    "block in <compiled>",
                    YP_ISEQ_TYPE_BLOCK
                );

                yp_compile_node(&block_compiler, (yp_node_t *) node->block);
                block_iseq = yp_iseq_new(&block_compiler);
            }

            if (block_iseq == Qnil && flags == 0) {
                flags |= YP_CALLDATA_ARGS_SIMPLE;
            }

            if (node->receiver == NULL) {
                flags |= YP_CALLDATA_FCALL;

                if (block_iseq == Qnil && node->arguments == NULL) {
                    flags |= YP_CALLDATA_VCALL;
                }
            }

            push_send(compiler, -sizet2int(orig_argc), yp_calldata_new(mid, flags, orig_argc), block_iseq);
            return;
        }
        case YP_NODE_CLASS_VARIABLE_READ_NODE: {
            yp_class_variable_read_node_t *node = (yp_class_variable_read_node_t *) base_node;
            push_getclassvariable(compiler, ID2SYM(parse_node_symbol((yp_node_t *) node)), yp_inline_storage_new(compiler));
            return;
        }
        case YP_NODE_CLASS_VARIABLE_WRITE_NODE: {
            yp_class_variable_write_node_t *node = (yp_class_variable_write_node_t *) base_node;
            if (node->value == NULL) {
                rb_raise(rb_eNotImpError, "class variable write without value not implemented");
            }

            yp_compile_node(compiler, node->value);
            push_dup(compiler);
            push_setclassvariable(compiler, ID2SYM(parse_location_symbol(&node->name_loc)), yp_inline_storage_new(compiler));
            return;
        }
        case YP_NODE_CONSTANT_PATH_NODE: {
            yp_constant_path_node_t *node = (yp_constant_path_node_t *) base_node;
            yp_compile_node(compiler, node->parent);
            push_putobject(compiler, Qfalse);
            push_getconstant(compiler, ID2SYM(parse_node_symbol((yp_node_t *) node->child)));
            return;
        }
        case YP_NODE_CONSTANT_READ_NODE:
            push_putnil(compiler);
            push_putobject(compiler, Qtrue);
            push_getconstant(compiler, ID2SYM(parse_node_symbol((yp_node_t *) base_node)));
            return;
        case YP_NODE_EMBEDDED_STATEMENTS_NODE: {
            yp_embedded_statements_node_t *node = (yp_embedded_statements_node_t *) base_node;
            yp_compile_node(compiler, (yp_node_t *) node->statements);
            return;
        }
        case YP_NODE_FALSE_NODE:
            push_putobject(compiler, Qfalse);
            return;
        case YP_NODE_GLOBAL_VARIABLE_READ_NODE:
            push_getglobal(compiler, ID2SYM(parse_location_symbol(&base_node->location)));
            return;
        case YP_NODE_GLOBAL_VARIABLE_WRITE_NODE: {
            yp_global_variable_write_node_t *node = (yp_global_variable_write_node_t *) base_node;

            if (node->value == NULL) {
                rb_raise(rb_eNotImpError, "global variable write without value not implemented");
            }

            yp_compile_node(compiler, node->value);
            push_dup(compiler);
            push_setglobal(compiler, ID2SYM(parse_location_symbol(&node->name_loc)));
            return;
        }
        case YP_NODE_HASH_NODE: {
            yp_hash_node_t *node = (yp_hash_node_t *) base_node;
            yp_node_list_t elements = node->elements;

            for (size_t index = 0; index < elements.size; index++) {
                yp_compile_node(compiler, elements.nodes[index]);
            }

            push_newhash(compiler, sizet2int(elements.size * 2));
            return;
        }
        case YP_NODE_INSTANCE_VARIABLE_READ_NODE:
            push_getinstancevariable(compiler, ID2SYM(parse_node_symbol((yp_node_t *) base_node)), yp_inline_storage_new(compiler));
            return;
        case YP_NODE_INSTANCE_VARIABLE_WRITE_NODE: {
            yp_instance_variable_write_node_t *node = (yp_instance_variable_write_node_t *) base_node;

            if (node->value == NULL) {
                rb_raise(rb_eNotImpError, "instance variable write without value not implemented");
            }

            yp_compile_node(compiler, node->value);
            push_dup(compiler);
            push_setinstancevariable(compiler, ID2SYM(parse_location_symbol(&node->name_loc)), yp_inline_storage_new(compiler));
            return;
        }
        case YP_NODE_INTEGER_NODE:
            push_putobject(compiler, parse_number(base_node->location.start, base_node->location.end));
            return;
        case YP_NODE_INTERPOLATED_STRING_NODE: {
            yp_interpolated_string_node_t *node = (yp_interpolated_string_node_t *) base_node;

            for (size_t index = 0; index < node->parts.size; index++) {
                yp_node_t *part = node->parts.nodes[index];

                switch (part->type) {
                    case YP_NODE_STRING_NODE: {
                        yp_string_node_t *string_node = (yp_string_node_t *) part;
                        push_putobject(compiler, parse_string(&string_node->unescaped));
                        break;
                    }
                    default:
                        yp_compile_node(compiler, part);
                        push_dup(compiler);
                        push_objtostring(compiler, yp_calldata_new(rb_intern("to_s"), YP_CALLDATA_FCALL | YP_CALLDATA_ARGS_SIMPLE, 0));
                        push_anytostring(compiler);
                        break;
                }
            }

            push_concatstrings(compiler, sizet2int(node->parts.size));
            return;
        }
        case YP_NODE_KEYWORD_HASH_NODE: {
            yp_keyword_hash_node_t *node = (yp_keyword_hash_node_t *) base_node;
            yp_node_list_t elements = node->elements;

            for (size_t index = 0; index < elements.size; index++) {
                yp_compile_node(compiler, elements.nodes[index]);
            }

            push_newhash(compiler, sizet2int(elements.size * 2));
            return;
        }
        case YP_NODE_LOCAL_VARIABLE_READ_NODE: {
            yp_local_variable_read_node_t *node = (yp_local_variable_read_node_t *) base_node;
            int index = local_index(compiler, node->constant_id, node->depth);

            push_getlocal(compiler, INT2FIX(index), INT2FIX(node->depth));
            return;
        }
        case YP_NODE_LOCAL_VARIABLE_WRITE_NODE: {
            yp_local_variable_write_node_t *node = (yp_local_variable_write_node_t *) base_node;

            if (node->value == NULL) {
                rb_raise(rb_eNotImpError, "local variable write without value not implemented");
            }

            int index = local_index(compiler, node->constant_id, node->depth);

            yp_compile_node(compiler, node->value);
            push_dup(compiler);
            push_setlocal(compiler, INT2FIX(index), INT2FIX(node->depth));
            return;
        }
        case YP_NODE_NIL_NODE:
            push_putnil(compiler);
            return;
        case YP_NODE_OR_NODE: {
            yp_or_node_t *node = (yp_or_node_t *) base_node;

            yp_compile_node(compiler, node->left);
            push_dup(compiler);
            VALUE branchif = push_branchif(compiler, Qnil);

            push_pop(compiler);
            yp_compile_node(compiler, node->right);

            VALUE label = push_label(compiler);
            rb_ary_store(branchif, 1, label);

            return;
        }
        case YP_NODE_PARENTHESES_NODE: {
            yp_parentheses_node_t *node = (yp_parentheses_node_t *) base_node;

            if (node->statements == NULL) {
                push_putnil(compiler);
            } else {
                yp_compile_node(compiler, node->statements);
            }

            return;
        }
        case YP_NODE_PROGRAM_NODE: {
            yp_program_node_t *node = (yp_program_node_t *) base_node;

            if (node->statements->body.size == 0) {
                push_putnil(compiler);
            } else {
                yp_compile_node(compiler, (yp_node_t *) node->statements);
            }

            push_leave(compiler);
            return;
        }
        case YP_NODE_RANGE_NODE: {
            yp_range_node_t *node = (yp_range_node_t *) base_node;

            if (node->left == NULL) {
                push_putnil(compiler);
            } else {
                yp_compile_node(compiler, node->left);
            }

            if (node->right == NULL) {
                push_putnil(compiler);
            } else {
                yp_compile_node(compiler, node->right);
            }

            push_newrange(compiler, INT2FIX((node->operator_loc.end - node->operator_loc.start) == 3));
            return;
        }
        case YP_NODE_SELF_NODE:
            push_putself(compiler);
            return;
        case YP_NODE_STATEMENTS_NODE: {
            yp_statements_node_t *node = (yp_statements_node_t *) base_node;
            yp_node_list_t node_list = node->body;
            for (size_t index = 0; index < node_list.size; index++) {
                yp_compile_node(compiler, node_list.nodes[index]);
                if (index < node_list.size - 1) push_pop(compiler);
            }
            return;
        }
        case YP_NODE_STRING_NODE: {
            yp_string_node_t *node = (yp_string_node_t *) base_node;
            push_putstring(compiler, parse_string(&node->unescaped));
            return;
        }
        case YP_NODE_SYMBOL_NODE: {
            yp_symbol_node_t *node = (yp_symbol_node_t *) base_node;
            push_putobject(compiler, ID2SYM(parse_string_symbol(&node->unescaped)));
            return;
        }
        case YP_NODE_TRUE_NODE:
            push_putobject(compiler, Qtrue);
            return;
        case YP_NODE_UNDEF_NODE: {
            yp_undef_node_t *node = (yp_undef_node_t *) base_node;

            for (size_t index = 0; index < node->names.size; index++) {
                push_putspecialobject(compiler, YP_SPECIALOBJECT_VMCORE);
                push_putspecialobject(compiler, YP_SPECIALOBJECT_CBASE);
                yp_compile_node(compiler, node->names.nodes[index]);
                push_send(compiler, -2, yp_calldata_new(rb_intern("core#undef_method"), YP_CALLDATA_ARGS_SIMPLE, 2), Qnil);

                if (index < node->names.size - 1) push_pop(compiler);
            }

            return;
        }
        case YP_NODE_X_STRING_NODE: {
            yp_x_string_node_t *node = (yp_x_string_node_t *) base_node;
            push_putself(compiler);
            push_putobject(compiler, parse_string(&node->unescaped));
            push_send(compiler, -1, yp_calldata_new(rb_intern("`"), YP_CALLDATA_FCALL | YP_CALLDATA_ARGS_SIMPLE, 1), Qnil);
            return;
        }
        case YP_NODE_OPTIONAL_PARAMETER_NODE: {
            yp_optional_parameter_node_t *node = (yp_optional_parameter_node_t *) base_node;
            int depth = 0;
            int index = local_index(compiler, node->constant_id, depth);
            yp_compile_node(compiler, node->value);
            push_setlocal(compiler, INT2FIX(index), INT2FIX(depth));
            break;
        }
        default:
            rb_raise(rb_eNotImpError, "node type %d not implemented", base_node->type);
            return;
    }
}

// This function compiles the given node into a list of instructions.
VALUE
yp_compile(yp_node_t *node) {
    assert(node->type == YP_NODE_PROGRAM_NODE);

    yp_iseq_compiler_t compiler;
    yp_iseq_compiler_init(
        &compiler,
        NULL,
        &((yp_program_node_t *) node)->locals,
        "<compiled>",
        YP_ISEQ_TYPE_TOP
    );

    yp_compile_node(&compiler, node);
    return yp_iseq_new(&compiler);
}
