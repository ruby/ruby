#include "yarp.h"

#define OLD_ISEQ NEW_ISEQ
#undef NEW_ISEQ

#define NEW_ISEQ(node, name, type, line_no) \
    yp_new_child_iseq(iseq, (node), parser, rb_fstring(name), 0, (type), (line_no))

#define OLD_CHILD_ISEQ NEW_CHILD_ISEQ
#undef NEW_CHILD_ISEQ

#define NEW_CHILD_ISEQ(node, name, type, line_no) \
    yp_new_child_iseq(iseq, (node), parser, rb_fstring(name), iseq, (type), (line_no))

rb_iseq_t *
yp_iseq_new_with_opt(yp_scope_node_t *node, yp_parser_t *parser, VALUE name, VALUE path, VALUE realpath,
                     int first_lineno, const rb_iseq_t *parent, int isolated_depth,
                     enum rb_iseq_type type, const rb_compile_option_t *option);

static VALUE
parse_number(const yp_node_t *node) {
    const uint8_t *start = node->location.start;
    const uint8_t *end = node->location.end;
    size_t length = end - start;

    char *buffer = malloc(length + 1);
    memcpy(buffer, start, length);

    buffer[length] = '\0';
    VALUE number = rb_cstr_to_inum(buffer, -10, Qfalse);

    free(buffer);
    return number;
}

static inline VALUE
parse_string(yp_string_t *string) {
    return rb_str_new((const char *) yp_string_source(string), yp_string_length(string));
}

static inline ID
parse_symbol(const uint8_t *start, const uint8_t *end) {
    return rb_intern2((const char *) start, end - start);
}

static inline ID
parse_node_symbol(yp_node_t *node) {
    return parse_symbol(node->location.start, node->location.end);
}

static inline ID
parse_string_symbol(yp_string_t *string) {
    const uint8_t *start = yp_string_source(string);
    return parse_symbol(start, start + yp_string_length(string));
}

static inline ID
parse_location_symbol(yp_location_t *location) {
    return parse_symbol(location->start, location->end);
}

static int
yp_optimizable_range_item_p(yp_node_t *node)
{
    return (!node || node->type == YP_NODE_INTEGER_NODE || node->type == YP_NODE_NIL_NODE);
}

static bool
yp_static_node_literal_p(yp_node_t *node)
{
    switch(node->type) {
      case YP_NODE_FALSE_NODE:
      case YP_NODE_FLOAT_NODE:
      case YP_NODE_IMAGINARY_NODE:
      case YP_NODE_INTEGER_NODE:
      case YP_NODE_NIL_NODE:
      case YP_NODE_RATIONAL_NODE:
      case YP_NODE_SELF_NODE:
      case YP_NODE_STRING_NODE:
      case YP_NODE_SOURCE_ENCODING_NODE:
      case YP_NODE_SOURCE_FILE_NODE:
      case YP_NODE_SOURCE_LINE_NODE:
      case YP_NODE_SYMBOL_NODE:
      case YP_NODE_TRUE_NODE:
        return true;
      default:
        return false;
    }
}

static inline VALUE
yp_static_literal_value(yp_node_t *node)
{
    switch(node->type) {
      case YP_NODE_NIL_NODE:
        return Qnil;
      case YP_NODE_TRUE_NODE:
        return Qtrue;
      case YP_NODE_FALSE_NODE:
        return Qfalse;
        // TODO: Implement this method for the other literal nodes described above
      default:
        rb_bug("This node type doesn't have a literal value");
    }
}

static void
yp_compile_branch_condition(rb_iseq_t *iseq, LINK_ANCHOR *const ret, const yp_node_t *cond,
                         LABEL *then_label, LABEL *else_label, const uint8_t *src, bool popped, yp_compile_context_t *compile_context);

static void
yp_compile_logical(rb_iseq_t *iseq, LINK_ANCHOR *const ret, yp_node_t *cond,
                LABEL *then_label, LABEL *else_label, const uint8_t *src, bool popped, yp_compile_context_t *compile_context)
{
    yp_parser_t *parser = compile_context->parser;
    yp_newline_list_t newline_list = parser->newline_list;
    int lineno = (int)yp_newline_list_line_column(&newline_list, cond->location.start).line;
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    DECL_ANCHOR(seq);
    INIT_ANCHOR(seq);
    LABEL *label = NEW_LABEL(lineno);
    if (!then_label) then_label = label;
    else if (!else_label) else_label = label;

    yp_compile_branch_condition(iseq, seq, cond, then_label, else_label, src, popped, compile_context);

    if (LIST_INSN_SIZE_ONE(seq)) {
        INSN *insn = (INSN *)ELEM_FIRST_INSN(FIRST_ELEMENT(seq));
        if (insn->insn_id == BIN(jump) && (LABEL *)(insn->operands[0]) == label)
            return;
    }
    if (!label->refcnt) {
        ADD_INSN(seq, &dummy_line_node, putnil);
    }
    else {
        ADD_LABEL(seq, label);
    }
    ADD_SEQ(ret, seq);
    return;
}

static void yp_compile_node(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, yp_compile_context_t *context);

static void
yp_compile_branch_condition(rb_iseq_t *iseq, LINK_ANCHOR *const ret, const yp_node_t *cond,
                         LABEL *then_label, LABEL *else_label, const uint8_t *src, bool popped, yp_compile_context_t *compile_context)
{
    yp_parser_t *parser = compile_context->parser;
    yp_newline_list_t newline_list = parser->newline_list;
    int lineno = (int) yp_newline_list_line_column(&newline_list, cond->location.start).line;
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

again:
    switch (YP_NODE_TYPE(cond)) {
      case YP_NODE_AND_NODE: {
          yp_and_node_t *and_node = (yp_and_node_t *)cond;
          yp_compile_logical(iseq, ret, and_node->left, NULL, else_label, src, popped, compile_context);
          cond = and_node->right;
          goto again;
      }
      case YP_NODE_OR_NODE: {
          yp_or_node_t *or_node = (yp_or_node_t *)cond;
          yp_compile_logical(iseq, ret, or_node->left, then_label, NULL, src, popped, compile_context);
          cond = or_node->right;
          goto again;
      }
      case YP_NODE_FALSE_NODE:
      case YP_NODE_NIL_NODE:
        ADD_INSNL(ret, &dummy_line_node, jump, else_label);
        return;
      case YP_NODE_FLOAT_NODE:
      case YP_NODE_IMAGINARY_NODE:
      case YP_NODE_INTEGER_NODE:
      case YP_NODE_LAMBDA_NODE:
      case YP_NODE_RATIONAL_NODE:
      case YP_NODE_REGULAR_EXPRESSION_NODE:
      case YP_NODE_STRING_NODE:
      case YP_NODE_SYMBOL_NODE:
      case YP_NODE_TRUE_NODE:
        ADD_INSNL(ret, &dummy_line_node, jump, then_label);
        return;
        // TODO: Several more nodes in this case statement
      default:
        {
            DECL_ANCHOR(cond_seq);
            INIT_ANCHOR(cond_seq);

            yp_compile_node(iseq, cond, cond_seq, src, false, compile_context);
            ADD_SEQ(ret, cond_seq);
        }
        break;
    }
    ADD_INSNL(ret, &dummy_line_node, branchunless, else_label);
    ADD_INSNL(ret, &dummy_line_node, jump, then_label);
    return;
}

static void
yp_compile_if(rb_iseq_t *iseq, const int line, yp_statements_node_t *node_body, yp_node_t *node_else, yp_node_t *predicate, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, yp_compile_context_t *compile_context) {
    NODE line_node = generate_dummy_line_node(line, line);

    DECL_ANCHOR(cond_seq);

    LABEL *then_label, *else_label, *end_label;

    INIT_ANCHOR(cond_seq);
    then_label = NEW_LABEL(line);
    else_label = NEW_LABEL(line);
    end_label = 0;

    yp_compile_branch_condition(iseq, cond_seq, predicate, then_label, else_label, src, popped, compile_context);
    ADD_SEQ(ret, cond_seq);

    if (then_label->refcnt) {
        ADD_LABEL(ret, then_label);

        DECL_ANCHOR(then_seq);
        INIT_ANCHOR(then_seq);
        if (node_body) {
            yp_compile_node(iseq, (yp_node_t *)node_body, then_seq, src, popped, compile_context);
        }
        else {
            if (!popped) {
                ADD_INSN(ret, &line_node, putnil);
            }
        }

        if (else_label->refcnt) {
            end_label = NEW_LABEL(line);
            ADD_INSNL(then_seq, &line_node, jump, end_label);
            if (!popped) {
                ADD_INSN(then_seq, &line_node, pop);
            }
        }
        ADD_SEQ(ret, then_seq);
    }

    if (else_label->refcnt) {
        ADD_LABEL(ret, else_label);

        DECL_ANCHOR(else_seq);
        INIT_ANCHOR(else_seq);
        if (node_else) {
            yp_compile_node(iseq, (yp_node_t *)(((yp_else_node_t *)node_else)->statements), else_seq, src, popped, compile_context);
        }
        else {
            if (!popped) {
                ADD_INSN(ret, &line_node, putnil);
            }
        }

        ADD_SEQ(ret, else_seq);
    }

    if (end_label) {
        ADD_LABEL(ret, end_label);
    }

    return;
}

static void
yp_compile_while(rb_iseq_t *iseq, int lineno, yp_node_flags_t flags, enum yp_node_type type, yp_statements_node_t *statements, yp_node_t *predicate, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, yp_compile_context_t *compile_context)
{
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    LABEL *prev_start_label = ISEQ_COMPILE_DATA(iseq)->start_label;
    LABEL *prev_end_label = ISEQ_COMPILE_DATA(iseq)->end_label;
    LABEL *prev_redo_label = ISEQ_COMPILE_DATA(iseq)->redo_label;

    // TODO: Deal with ensures in here
    LABEL *next_label = ISEQ_COMPILE_DATA(iseq)->start_label = NEW_LABEL(lineno); /* next  */
    LABEL *redo_label = ISEQ_COMPILE_DATA(iseq)->redo_label = NEW_LABEL(lineno);  /* redo  */
    LABEL *break_label = ISEQ_COMPILE_DATA(iseq)->end_label = NEW_LABEL(lineno);  /* break */
    LABEL *end_label = NEW_LABEL(lineno);
    LABEL *adjust_label = NEW_LABEL(lineno);

    LABEL *next_catch_label = NEW_LABEL(lineno);
    LABEL *tmp_label = NULL;

    // begin; end while true
    if (flags & YP_LOOP_FLAGS_BEGIN_MODIFIER) {
        tmp_label = NEW_LABEL(lineno);
        ADD_INSNL(ret, &dummy_line_node, jump, tmp_label);
    }
    else {
        // while true; end
        ADD_INSNL(ret, &dummy_line_node, jump, next_label);
    }

    ADD_LABEL(ret, adjust_label);
    ADD_INSN(ret, &dummy_line_node, putnil);
    ADD_LABEL(ret, next_catch_label);
    ADD_INSN(ret, &dummy_line_node, pop);
    ADD_INSNL(ret, &dummy_line_node, jump, next_label);
    if (tmp_label) ADD_LABEL(ret, tmp_label);

    ADD_LABEL(ret, redo_label);
    if (statements) {
        yp_compile_node(iseq, (yp_node_t *)statements, ret, src, true, compile_context);
    }

    ADD_LABEL(ret, next_label);

    if (type == YP_NODE_WHILE_NODE) {
        yp_compile_branch_condition(iseq, ret, predicate, redo_label, end_label, src, popped, compile_context);
    }
    else if (type == YP_NODE_UNTIL_NODE) {
        yp_compile_branch_condition(iseq, ret, predicate, end_label, redo_label, src, popped, compile_context);
    }

    ADD_LABEL(ret, end_label);
    ADD_ADJUST_RESTORE(ret, adjust_label);

    ADD_INSN(ret, &dummy_line_node, putnil);

    ADD_LABEL(ret, break_label);

    if (popped) {
        ADD_INSN(ret, &dummy_line_node, pop);
    }

    ADD_CATCH_ENTRY(CATCH_TYPE_BREAK, redo_label, break_label, NULL,
            break_label);
    ADD_CATCH_ENTRY(CATCH_TYPE_NEXT, redo_label, break_label, NULL,
            next_catch_label);
    ADD_CATCH_ENTRY(CATCH_TYPE_REDO, redo_label, break_label, NULL,
            ISEQ_COMPILE_DATA(iseq)->redo_label);

    ISEQ_COMPILE_DATA(iseq)->start_label = prev_start_label;
    ISEQ_COMPILE_DATA(iseq)->end_label = prev_end_label;
    ISEQ_COMPILE_DATA(iseq)->redo_label = prev_redo_label;
    return;
}

static int
yp_lookup_local_index(rb_iseq_t *iseq, yp_compile_context_t *compile_context, yp_constant_id_t constant_id)
{
    st_data_t local_index;

    int num_params = ISEQ_BODY(iseq)->param.size;

    if (!st_lookup(compile_context->index_lookup_table, constant_id, &local_index)) {
        rb_bug("This local does not exist");
    }

    return num_params - (int)local_index;
}

static int
yp_lookup_local_index_with_depth(rb_iseq_t *iseq, yp_compile_context_t *compile_context, yp_constant_id_t constant_id, uint32_t depth)
{
    for(uint32_t i = 0; i < depth; i++) {
        compile_context = compile_context->previous;
        iseq = (rb_iseq_t *)ISEQ_BODY(iseq)->parent_iseq;
    }

    return yp_lookup_local_index(iseq, compile_context, constant_id);
}

// This returns the CRuby ID which maps to the yp_constant_id_t
//
// Constant_ids in YARP are indexes of the constants in YARP's constant pool.
// We add a constants mapping on the compile_context which is a mapping from
// these constant_id indexes to the CRuby IDs that they represent.
// This helper method allows easy access to those IDs
static ID
yp_constant_id_lookup(yp_compile_context_t *compile_context, yp_constant_id_t constant_id)
{
    return compile_context->constants[constant_id - 1];
}

static rb_iseq_t *
yp_new_child_iseq(rb_iseq_t *iseq, yp_scope_node_t * node, yp_parser_t *parser,
               VALUE name, const rb_iseq_t *parent, enum rb_iseq_type type, int line_no)
{
    debugs("[new_child_iseq]> ---------------------------------------\n");
    int isolated_depth = ISEQ_COMPILE_DATA(iseq)->isolated_depth;
    rb_iseq_t * ret_iseq = yp_iseq_new_with_opt(node, parser, name,
            rb_iseq_path(iseq), rb_iseq_realpath(iseq),
            line_no, parent,
            isolated_depth ? isolated_depth + 1 : 0,
            type, ISEQ_COMPILE_DATA(iseq)->option);
    debugs("[new_child_iseq]< ---------------------------------------\n");
    return ret_iseq;
}


static int
yp_compile_class_path(LINK_ANCHOR *const ret, rb_iseq_t *iseq, const yp_node_t *constant_path_node, const NODE *line_node, const uint8_t * src, bool popped, yp_compile_context_t *compile_context)
{
    if (constant_path_node->type == YP_NODE_CONSTANT_PATH_NODE) {
        yp_node_t *parent = ((yp_constant_path_node_t *)constant_path_node)->parent;
        if (parent) {
            /* Bar::Foo */
            yp_compile_node(iseq, parent, ret, src, popped, compile_context);
            return VM_DEFINECLASS_FLAG_SCOPED;
        }
        else {
            /* toplevel class ::Foo */
            ADD_INSN1(ret, line_node, putobject, rb_cObject);
            return VM_DEFINECLASS_FLAG_SCOPED;
        }
    }
    else {
        /* class at cbase Foo */
        ADD_INSN1(ret, line_node, putspecialobject,
                INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        return 0;
    }
}

/*
 * Compiles a YARP node into instruction sequences
 *
 * iseq -            The current instruction sequence object (used for locals)
 * node -            The yarp node to compile
 * ret -             The linked list of instruction sequences to append instructions onto
 * popped -          True if compiling something with no side effects, so instructions don't
 *                   need to be added
 * compile_context - Stores parser and local information
 */
static void
yp_compile_node(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, yp_compile_context_t *compile_context)
{
    yp_parser_t *parser = compile_context->parser;
    yp_newline_list_t newline_list = parser->newline_list;
    int lineno = (int)yp_newline_list_line_column(&newline_list, node->location.start).line;
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    switch (YP_NODE_TYPE(node)) {
      case YP_NODE_ALIAS_NODE: {
          yp_alias_node_t *alias_node = (yp_alias_node_t *) node;

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CBASE));

          yp_compile_node(iseq, alias_node->new_name, ret, src, popped, compile_context);
          yp_compile_node(iseq, alias_node->old_name, ret, src, popped, compile_context);

          ADD_SEND(ret, &dummy_line_node, id_core_set_method_alias, INT2FIX(3));
          return;
      }
      case YP_NODE_AND_NODE: {
          yp_and_node_t *and_node = (yp_and_node_t *) node;

          LABEL *end_label = NEW_LABEL(lineno);
          yp_compile_node(iseq, and_node->left, ret, src, popped, compile_context);
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }
          ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          yp_compile_node(iseq, and_node->right, ret, src, popped, compile_context);
          ADD_LABEL(ret, end_label);
          return;
      }
      case YP_NODE_ARGUMENTS_NODE: {
          yp_arguments_node_t *arguments_node = (yp_arguments_node_t *) node;
          yp_node_list_t node_list = arguments_node->arguments;
          for (size_t index = 0; index < node_list.size; index++) {
              yp_compile_node(iseq, node_list.nodes[index], ret, src, popped, compile_context);
          }
          return;
      }
      case YP_NODE_ARRAY_NODE: {
          yp_array_node_t *array_node = (yp_array_node_t *) node;
          yp_node_list_t elements = array_node->elements;
          if (elements.size == 1 && yp_static_node_literal_p(elements.nodes[0])) {
              VALUE ary = rb_ary_hidden_new(1);
              rb_ary_push(ary, yp_static_literal_value(elements.nodes[0]));
              OBJ_FREEZE(ary);

              ADD_INSN1(ret, &dummy_line_node, duparray, ary);
          }
          else {
              for (size_t index = 0; index < elements.size; index++) {
                  yp_compile_node(iseq, elements.nodes[index], ret, src, popped, compile_context);
              }

              if (!popped) {
                  ADD_INSN1(ret, &dummy_line_node, newarray, INT2FIX(elements.size));
              }
          }

          return;
      }
      case YP_NODE_ASSOC_NODE: {
          yp_assoc_node_t *assoc_node = (yp_assoc_node_t *) node;
          yp_compile_node(iseq, assoc_node->key, ret, src, popped, compile_context);
          if (assoc_node->value) {
              yp_compile_node(iseq, assoc_node->value, ret, src, popped, compile_context);
          }
          return;
      }
      case YP_NODE_ASSOC_SPLAT_NODE: {
          yp_assoc_splat_node_t *assoc_splat_node = (yp_assoc_splat_node_t *)node;
          yp_compile_node(iseq, assoc_splat_node->value, ret, src, popped, compile_context);

          // TODO: Not sure this is accurate, look at FLUSH_CHUNK in the compiler
          ADD_INSN1(ret, &dummy_line_node, newarraykwsplat, INT2FIX(0));

          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_BACK_REFERENCE_READ_NODE: {
          if (!popped) {
              // Since a back reference is `$<char>`, ruby represents the ID as the
              // an rb_intern on the value after the `$`.
              char *char_ptr = (char *)(node->location.start) + 1;
              ID backref_val = INT2FIX(rb_intern2(char_ptr, 1)) << 1 | 1;
              ADD_INSN2(ret, &dummy_line_node, getspecial, INT2FIX(1), backref_val);
          }
          return;
      }
      case YP_NODE_BEGIN_NODE: {
          yp_begin_node_t *begin_node = (yp_begin_node_t *) node;
          if (begin_node->statements) {
              yp_compile_node(iseq, (yp_node_t *)begin_node->statements, ret, src, popped, compile_context);
          }
          return;
      }
      case YP_NODE_BREAK_NODE: {
          yp_break_node_t *break_node = (yp_break_node_t *) node;
          if (break_node->arguments) {
              yp_compile_node(iseq, (yp_node_t *)break_node->arguments, ret, src, Qfalse, compile_context);
          }
          else {
              ADD_INSN(ret, &dummy_line_node, putnil);
          }

          ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->end_label);

          return;
      }
      case YP_NODE_CALL_NODE: {
          yp_call_node_t *call_node = (yp_call_node_t *) node;

          ID method_id = parse_string_symbol(&call_node->name);
          int flags = 0;
          int orig_argc = 0;

          if (call_node->receiver == NULL) {
              ADD_INSN(ret, &dummy_line_node, putself);
          } else {
              yp_compile_node(iseq, call_node->receiver, ret, src, false, compile_context);
          }

          if (call_node->arguments == NULL) {
              if (flags & VM_CALL_FCALL) {
                  flags |= VM_CALL_VCALL;
              }
          } else {
              yp_arguments_node_t *arguments = call_node->arguments;
              yp_compile_node(iseq, (yp_node_t *) arguments, ret, src, false, compile_context);
              orig_argc = (int)arguments->arguments.size;
          }

          VALUE block_iseq = Qnil;
          if (call_node->block != NULL) {
              // Scope associated with the block
              yp_scope_node_t scope_node;
              yp_scope_node_init((yp_node_t *)call_node->block, &scope_node);

              const rb_iseq_t *block_iseq = NEW_CHILD_ISEQ(&scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
              ISEQ_COMPILE_DATA(iseq)->current_block = block_iseq;
              ADD_SEND_WITH_BLOCK(ret, &dummy_line_node, method_id, INT2FIX(orig_argc), block_iseq);
          }
          else {
              if (block_iseq == Qnil && flags == 0) {
                  flags |= VM_CALL_ARGS_SIMPLE;
              }

              if (call_node->receiver == NULL) {
                  flags |= VM_CALL_FCALL;

                  if (block_iseq == Qnil && call_node->arguments == NULL) {
                      flags |= VM_CALL_VCALL;
                  }
              }

              ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(orig_argc), INT2FIX(flags));
          }
          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_CLASS_NODE: {
          yp_class_node_t *class_node = (yp_class_node_t *)node;
          yp_scope_node_t scope_node;
          yp_scope_node_init((yp_node_t *)class_node, &scope_node);

          ID class_id = yp_constant_id_lookup(compile_context, class_node->name_constant);

          VALUE class_name = rb_str_freeze(rb_sprintf("<class:%"PRIsVALUE">", rb_id2str(class_id)));

          const rb_iseq_t *class_iseq = NEW_CHILD_ISEQ(&scope_node, class_name, ISEQ_TYPE_CLASS, lineno);

          // TODO: Once we merge constant path nodes correctly, fix this flag
          const int flags = VM_DEFINECLASS_TYPE_CLASS |
              (class_node->superclass ? VM_DEFINECLASS_FLAG_HAS_SUPERCLASS : 0) |
              yp_compile_class_path(ret, iseq, class_node->constant_path, &dummy_line_node, src, popped, compile_context);

          if (class_node->superclass) {
              yp_compile_node(iseq, class_node->superclass, ret, src, popped, compile_context);
          }
          else {
              ADD_INSN(ret, &dummy_line_node, putnil);
          }

          ADD_INSN3(ret, &dummy_line_node, defineclass, ID2SYM(class_id), class_iseq, INT2FIX(flags));
          RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)class_iseq);

          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_CLASS_VARIABLE_AND_WRITE_NODE: {
          yp_class_variable_and_write_node_t *class_variable_and_write_node = (yp_class_variable_and_write_node_t*) node;

          LABEL *end_label = NEW_LABEL(lineno);

          ID class_variable_name_id = yp_constant_id_lookup(compile_context, class_variable_and_write_node->name);
          VALUE class_variable_name_val = ID2SYM(class_variable_name_id);

          ADD_INSN2(ret, &dummy_line_node, getclassvariable,
                  class_variable_name_val,
                  get_cvar_ic_value(iseq, class_variable_name_id));

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          yp_compile_node(iseq, class_variable_and_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN2(ret, &dummy_line_node, setclassvariable,
                  class_variable_name_val,
                  get_cvar_ic_value(iseq, class_variable_name_id));
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_CLASS_VARIABLE_OPERATOR_WRITE_NODE: {
          yp_class_variable_operator_write_node_t *class_variable_operator_write_node = (yp_class_variable_operator_write_node_t*) node;

          ID class_variable_name_id = yp_constant_id_lookup(compile_context, class_variable_operator_write_node->name);
          VALUE class_variable_name_val = ID2SYM(class_variable_name_id);

          ADD_INSN2(ret, &dummy_line_node, getclassvariable,
                  class_variable_name_val,
                  get_cvar_ic_value(iseq, class_variable_name_id));

          yp_compile_node(iseq, class_variable_operator_write_node->value, ret, src, false, compile_context);
          ID method_id = yp_constant_id_lookup(compile_context, class_variable_operator_write_node->operator);

          int flags = VM_CALL_ARGS_SIMPLE;
          ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN2(ret, &dummy_line_node, setclassvariable,
                  class_variable_name_val,
                  get_cvar_ic_value(iseq, class_variable_name_id));

          return;
      }
      case YP_NODE_CLASS_VARIABLE_OR_WRITE_NODE: {
          yp_class_variable_or_write_node_t *class_variable_or_write_node = (yp_class_variable_or_write_node_t*) node;

          LABEL *end_label = NEW_LABEL(lineno);

          ID class_variable_name_id = yp_constant_id_lookup(compile_context, class_variable_or_write_node->name);
          VALUE class_variable_name_val = ID2SYM(class_variable_name_id);

          ADD_INSN2(ret, &dummy_line_node, getclassvariable,
                  class_variable_name_val,
                  get_cvar_ic_value(iseq, class_variable_name_id));

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          yp_compile_node(iseq, class_variable_or_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN2(ret, &dummy_line_node, setclassvariable,
                  class_variable_name_val,
                  get_cvar_ic_value(iseq, class_variable_name_id));
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_CLASS_VARIABLE_READ_NODE: {
          if (!popped) {
              yp_class_variable_read_node_t *class_variable_read_node = (yp_class_variable_read_node_t *) node;
              ID cvar_name = yp_constant_id_lookup(compile_context, class_variable_read_node->name);
              ADD_INSN2(
                      ret,
                      &dummy_line_node,
                      getclassvariable,
                      ID2SYM(cvar_name),
                      get_cvar_ic_value(iseq, cvar_name)
                      );
          }
          return;
      }
      case YP_NODE_CLASS_VARIABLE_WRITE_NODE: {
          yp_class_variable_write_node_t *write_node = (yp_class_variable_write_node_t *) node;
          yp_compile_node(iseq, write_node->value, ret, src, false, compile_context);
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ID cvar_name = yp_constant_id_lookup(compile_context, write_node->name);
          ADD_INSN2(ret, &dummy_line_node, setclassvariable, ID2SYM(cvar_name), get_cvar_ic_value(iseq, cvar_name));
          return;
      }
      case YP_NODE_CONSTANT_PATH_NODE: {
          yp_constant_path_node_t *constant_path_node = (yp_constant_path_node_t*) node;
          if (constant_path_node->parent) {
              yp_compile_node(iseq, constant_path_node->parent, ret, src, popped, compile_context);
          }
          ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
          ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(parse_node_symbol((yp_node_t *)constant_path_node->child)));
          return;
      }
      case YP_NODE_CONSTANT_PATH_WRITE_NODE: {
          yp_constant_path_write_node_t *constant_path_write_node = (yp_constant_path_write_node_t*) node;
          yp_compile_node(iseq, constant_path_write_node->value, ret, src, popped, compile_context);
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ID constant_var_name = parse_location_symbol(&constant_path_write_node->target->base.location);

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
          ADD_INSN1(ret, &dummy_line_node, setconstant, ID2SYM(constant_var_name));
          return;
      }

      case YP_NODE_CONSTANT_READ_NODE: {
          yp_constant_read_node_t *constant_read_node = (yp_constant_read_node_t *) node;
          ADD_INSN(ret, &dummy_line_node, putnil);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
          ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(parse_node_symbol((yp_node_t *)constant_read_node)));
          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_CONSTANT_AND_WRITE_NODE: {
          yp_constant_and_write_node_t *constant_and_write_node = (yp_constant_and_write_node_t*) node;

          LABEL *end_label = NEW_LABEL(lineno);

          VALUE constant_name = ID2SYM(parse_location_symbol(&constant_and_write_node->name_loc));

          ADD_INSN(ret, &dummy_line_node, putnil);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
          ADD_INSN1(ret, &dummy_line_node, getconstant, constant_name);
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          yp_compile_node(iseq, constant_and_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
          ADD_INSN1(ret, &dummy_line_node, setconstant, constant_name);
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_CONSTANT_OPERATOR_WRITE_NODE: {
          yp_constant_operator_write_node_t *constant_operator_write_node = (yp_constant_operator_write_node_t*) node;

          ID constant_name = parse_location_symbol(&constant_operator_write_node->name_loc);
          ADD_INSN(ret, &dummy_line_node, putnil);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
          ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(constant_name));

          yp_compile_node(iseq, constant_operator_write_node->value, ret, src, false, compile_context);
          ID method_id = yp_constant_id_lookup(compile_context, constant_operator_write_node->operator);

          int flags = VM_CALL_ARGS_SIMPLE;
          ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));


          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
          ADD_INSN1(ret, &dummy_line_node, setconstant, ID2SYM(constant_name));

          return;
      }
      case YP_NODE_CONSTANT_OR_WRITE_NODE: {
          yp_constant_or_write_node_t *constant_or_write_node = (yp_constant_or_write_node_t*) node;

          LABEL *set_label= NEW_LABEL(lineno);
          LABEL *end_label = NEW_LABEL(lineno);

          ADD_INSN(ret, &dummy_line_node, putnil);
          VALUE constant_name = ID2SYM(parse_location_symbol(&constant_or_write_node->name_loc));

          ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CONST), constant_name, Qtrue);

          ADD_INSNL(ret, &dummy_line_node, branchunless, set_label);

          ADD_INSN(ret, &dummy_line_node, putnil);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
          ADD_INSN1(ret, &dummy_line_node, getconstant, constant_name);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          ADD_LABEL(ret, set_label);
          yp_compile_node(iseq, constant_or_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
          ADD_INSN1(ret, &dummy_line_node, setconstant, constant_name);
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_CONSTANT_WRITE_NODE: {
          yp_constant_write_node_t *constant_write_node = (yp_constant_write_node_t *) node;
          yp_compile_node(iseq, constant_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
          ID constant_name = parse_location_symbol(&constant_write_node->name_loc);
          ADD_INSN1(ret, &dummy_line_node, setconstant, ID2SYM(constant_name));
          return;
      }
      case YP_NODE_DEF_NODE: {
          yp_def_node_t *def_node = (yp_def_node_t *) node;
          ID method_name = parse_location_symbol(&def_node->name_loc);
          yp_scope_node_t scope_node;
          yp_scope_node_init((yp_node_t *)def_node, &scope_node);
          rb_iseq_t *method_iseq = NEW_ISEQ(&scope_node, rb_id2str(method_name), ISEQ_TYPE_METHOD, lineno);

          ADD_INSN2(ret, &dummy_line_node, definemethod, ID2SYM(method_name), method_iseq);
          RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)method_iseq);

          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, putobject, ID2SYM(method_name));
          }
          return;
      }
      case YP_NODE_DEFINED_NODE: {
          ADD_INSN(ret, &dummy_line_node, putself);
          yp_defined_node_t *defined_node = (yp_defined_node_t *)node;
          // TODO: Correct defined_type
          enum defined_type dtype = DEFINED_CONST;
          VALUE sym = parse_number(defined_node->value);

          ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(dtype), sym, rb_iseq_defined_string(dtype));
          return;
      }
      case YP_NODE_EMBEDDED_STATEMENTS_NODE: {
          yp_embedded_statements_node_t *embedded_statements_node = (yp_embedded_statements_node_t *)node;

          if (embedded_statements_node->statements)
              yp_compile_node(iseq, (yp_node_t *) (embedded_statements_node->statements), ret, src, popped, compile_context);
          // TODO: Concatenate the strings that exist here
          return;
      }
      case YP_NODE_EMBEDDED_VARIABLE_NODE: {
          yp_embedded_variable_node_t *embedded_node = (yp_embedded_variable_node_t *)node;
          yp_compile_node(iseq, embedded_node->variable, ret, src, popped, compile_context);
          return;
      }
      case YP_NODE_FALSE_NODE:
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
        }
        return;
      case YP_NODE_FLIP_FLOP_NODE: {
          // TODO: The labels here are wrong, figure out why.....
          yp_flip_flop_node_t *flip_flop_node = (yp_flip_flop_node_t *)node;

          LABEL *lend = NEW_LABEL(lineno);
          LABEL *then_label = NEW_LABEL(lineno);
          LABEL *else_label = NEW_LABEL(lineno);
          //TODO:         int again = type == NODE_FLIP2;
          int again = 0;

          rb_num_t cnt = ISEQ_FLIP_CNT_INCREMENT(ISEQ_BODY(iseq)->local_iseq)
              + VM_SVAR_FLIPFLOP_START;
          VALUE key = INT2FIX(cnt);

          ADD_INSN2(ret, &dummy_line_node, getspecial, key, INT2FIX(0));
          ADD_INSNL(ret, &dummy_line_node, branchif, lend);

          yp_compile_node(iseq, flip_flop_node->left, ret, src, popped, compile_context);
          /* *flip == 0 */
          ADD_INSNL(ret, &dummy_line_node, branchunless, else_label);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
          ADD_INSN1(ret, &dummy_line_node, setspecial, key);
          if (!again) {
              ADD_INSNL(ret, &dummy_line_node, jump, then_label);
          }

          /* *flip == 1 */
          ADD_LABEL(ret, lend);
          yp_compile_node(iseq, flip_flop_node->right, ret, src, popped, compile_context);
          ADD_INSNL(ret, &dummy_line_node, branchunless, then_label);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
          ADD_INSN1(ret, &dummy_line_node, setspecial, key);
          ADD_INSNL(ret, &dummy_line_node, jump, then_label);
          ADD_LABEL(ret, then_label);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
          ADD_INSNL(ret, &dummy_line_node, jump, lend);
          ADD_LABEL(ret, else_label);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
          ADD_LABEL(ret, lend);
          return;
      }
      case YP_NODE_FLOAT_NODE: {
          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, putobject, parse_number(node));
          }
          return;
      }
      case YP_NODE_GLOBAL_VARIABLE_AND_WRITE_NODE: {
          yp_global_variable_and_write_node_t *global_variable_and_write_node = (yp_global_variable_and_write_node_t*) node;

          LABEL *end_label = NEW_LABEL(lineno);

          VALUE global_variable_name = ID2SYM(yp_constant_id_lookup(compile_context, global_variable_and_write_node->name));

          ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          yp_compile_node(iseq, global_variable_and_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN1(ret, &dummy_line_node, setglobal, global_variable_name);
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE: {
          yp_global_variable_operator_write_node_t *global_variable_operator_write_node = (yp_global_variable_operator_write_node_t*) node;

          VALUE global_variable_name = ID2SYM(yp_constant_id_lookup(compile_context, global_variable_operator_write_node->name));
          ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);

          yp_compile_node(iseq, global_variable_operator_write_node->value, ret, src, false, compile_context);
          ID method_id = yp_constant_id_lookup(compile_context, global_variable_operator_write_node->operator);

          int flags = VM_CALL_ARGS_SIMPLE;
          ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));


          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN1(ret, &dummy_line_node, setglobal, global_variable_name);

          return;
      }
      case YP_NODE_GLOBAL_VARIABLE_OR_WRITE_NODE: {
          yp_global_variable_or_write_node_t *global_variable_or_write_node = (yp_global_variable_or_write_node_t*) node;

          LABEL *set_label= NEW_LABEL(lineno);
          LABEL *end_label = NEW_LABEL(lineno);

          ADD_INSN(ret, &dummy_line_node, putnil);
          VALUE global_variable_name = ID2SYM(yp_constant_id_lookup(compile_context, global_variable_or_write_node->name));

          ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_GVAR), global_variable_name, Qtrue);

          ADD_INSNL(ret, &dummy_line_node, branchunless, set_label);

          ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          ADD_LABEL(ret, set_label);
          yp_compile_node(iseq, global_variable_or_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN1(ret, &dummy_line_node, setglobal, global_variable_name);
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_GLOBAL_VARIABLE_READ_NODE: {
          yp_global_variable_read_node_t *global_variable_read_node = (yp_global_variable_read_node_t *)node;
          VALUE global_variable_name = ID2SYM(yp_constant_id_lookup(compile_context, global_variable_read_node->name));
          ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);
          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_GLOBAL_VARIABLE_WRITE_NODE: {
          yp_global_variable_write_node_t *write_node = (yp_global_variable_write_node_t *) node;
          yp_compile_node(iseq, write_node->value, ret, src, false, compile_context);
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }
          ID ivar_name = yp_constant_id_lookup(compile_context, write_node->name);
          ADD_INSN1(ret, &dummy_line_node, setglobal, ID2SYM(ivar_name));
          return;
      }
      case YP_NODE_HASH_NODE: {
          yp_hash_node_t *hash_node = (yp_hash_node_t *) node;
          yp_node_list_t elements = hash_node->elements;

          if (elements.size == 1) {
              assert(elements.nodes[0]->type == YP_NODE_ASSOC_NODE);
              yp_assoc_node_t *assoc_node = (yp_assoc_node_t *) elements.nodes[0];

              if (yp_static_node_literal_p(assoc_node->key) &&
                      yp_static_node_literal_p(assoc_node->value)) {
                  VALUE hash = rb_hash_new_with_size(1);
                  hash = rb_obj_hide(hash);
                  OBJ_FREEZE(hash);
                  ADD_INSN1(ret, &dummy_line_node, duphash, hash);
                  return;
              }
          }

          for (size_t index = 0; index < elements.size; index++) {
              yp_compile_node(iseq, elements.nodes[index], ret, src, popped, compile_context);
          }

          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(elements.size * 2));
          }
          return;
      }
      case YP_NODE_IF_NODE: {
          const int line = (int)yp_newline_list_line_column(&(parser->newline_list), node->location.start).line;
          yp_if_node_t *if_node = (yp_if_node_t *)node;
          yp_statements_node_t *node_body = if_node->statements;
          yp_node_t *node_else = if_node->consequent;
          yp_node_t *predicate = if_node->predicate;

          yp_compile_if(iseq, line, node_body, node_else, predicate, ret, src, popped, compile_context);
          return;
      }
      case YP_NODE_IMAGINARY_NODE: {
          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, putobject, parse_number(node));
          }
          return;
      }
      case YP_NODE_INSTANCE_VARIABLE_AND_WRITE_NODE: {
          yp_instance_variable_and_write_node_t *instance_variable_and_write_node = (yp_instance_variable_and_write_node_t*) node;

          LABEL *end_label = NEW_LABEL(lineno);

          ID instance_variable_name_id = yp_constant_id_lookup(compile_context, instance_variable_and_write_node->name);

          VALUE instance_variable_name_val = ID2SYM(instance_variable_name_id);

          ADD_INSN2(ret, &dummy_line_node, getinstancevariable,
                  instance_variable_name_val,
                  get_ivar_ic_value(iseq, instance_variable_name_id));

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          yp_compile_node(iseq, instance_variable_and_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN2(ret, &dummy_line_node, setinstancevariable,
                  instance_variable_name_val,
                  get_ivar_ic_value(iseq, instance_variable_name_id));
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_INSTANCE_VARIABLE_OPERATOR_WRITE_NODE: {
          yp_instance_variable_operator_write_node_t *instance_variable_operator_write_node = (yp_instance_variable_operator_write_node_t*) node;

          ID instance_variable_name_id = yp_constant_id_lookup(compile_context, instance_variable_operator_write_node->name);
          VALUE instance_variable_name_val = ID2SYM(instance_variable_name_id);

          ADD_INSN2(ret, &dummy_line_node, getinstancevariable,
                  instance_variable_name_val,
                  get_ivar_ic_value(iseq, instance_variable_name_id));

          yp_compile_node(iseq, instance_variable_operator_write_node->value, ret, src, false, compile_context);
          ID method_id = yp_constant_id_lookup(compile_context, instance_variable_operator_write_node->operator);

          int flags = VM_CALL_ARGS_SIMPLE;
          ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN2(ret, &dummy_line_node, setinstancevariable,
                  instance_variable_name_val,
                  get_ivar_ic_value(iseq, instance_variable_name_id));

          return;
      }
      case YP_NODE_INSTANCE_VARIABLE_OR_WRITE_NODE: {
          yp_instance_variable_or_write_node_t *instance_variable_or_write_node = (yp_instance_variable_or_write_node_t*) node;

          LABEL *end_label = NEW_LABEL(lineno);

          ID instance_variable_name_id = yp_constant_id_lookup(compile_context, instance_variable_or_write_node->name);
          VALUE instance_variable_name_val = ID2SYM(instance_variable_name_id);

          ADD_INSN2(ret, &dummy_line_node, getinstancevariable,
                  instance_variable_name_val,
                  get_ivar_ic_value(iseq, instance_variable_name_id));


          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          yp_compile_node(iseq, instance_variable_or_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN2(ret, &dummy_line_node, setinstancevariable,
                  instance_variable_name_val,
                  get_ivar_ic_value(iseq, instance_variable_name_id));
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_INSTANCE_VARIABLE_READ_NODE: {
          if (!popped) {
              yp_instance_variable_read_node_t *instance_variable_read_node = (yp_instance_variable_read_node_t *) node;
              ID ivar_name = yp_constant_id_lookup(compile_context, instance_variable_read_node->name);
              ADD_INSN2(ret, &dummy_line_node, getinstancevariable,
                      ID2SYM(ivar_name),
                      get_ivar_ic_value(iseq, ivar_name));
          }
          return;
      }
      case YP_NODE_INSTANCE_VARIABLE_WRITE_NODE: {
          yp_instance_variable_write_node_t *write_node = (yp_instance_variable_write_node_t *) node;
          yp_compile_node(iseq, write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ID ivar_name = yp_constant_id_lookup(compile_context, write_node->name);
          ADD_INSN2(ret, &dummy_line_node, setinstancevariable,
                  ID2SYM(ivar_name),
                  get_ivar_ic_value(iseq, ivar_name));
          return;
      }
      case YP_NODE_INTEGER_NODE: {
          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, putobject, parse_number(node));
          }
          return;
      }
      case YP_NODE_INTERPOLATED_STRING_NODE: {
          yp_interpolated_string_node_t *interp_string_node= (yp_interpolated_string_node_t *) node;

          for (size_t index = 0; index < interp_string_node->parts.size; index++) {
              yp_node_t *part = interp_string_node->parts.nodes[index];

              switch (part->type) {
                case YP_NODE_STRING_NODE: {
                    yp_string_node_t *string_node = (yp_string_node_t *) part;
                    ADD_INSN1(ret, &dummy_line_node, putobject,parse_string(&string_node->unescaped));
                    break;
                }
                default:
                  yp_compile_node(iseq, part, ret, src, popped, compile_context);
                  ADD_INSN(ret, &dummy_line_node, dup);
                  ADD_INSN1(ret, &dummy_line_node, objtostring, new_callinfo(iseq, idTo_s, 0, VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE , NULL, FALSE));
                  ADD_INSN(ret, &dummy_line_node, anytostring);
                  break;
              }
          }

          if (interp_string_node->parts.size > 1) {
              ADD_INSN1(ret, &dummy_line_node, concatstrings, INT2FIX((int)(interp_string_node->parts.size)));
          }
          return;
      }
      case YP_NODE_INTERPOLATED_SYMBOL_NODE: {
          yp_interpolated_symbol_node_t *interp_symbol_node= (yp_interpolated_symbol_node_t *) node;

          for (size_t index = 0; index < interp_symbol_node->parts.size; index++) {
              yp_node_t *part = interp_symbol_node->parts.nodes[index];

              switch (part->type) {
                case YP_NODE_STRING_NODE: {
                    yp_string_node_t *string_node = (yp_string_node_t *) part;
                    ADD_INSN1(ret, &dummy_line_node, putobject, parse_string(&string_node->unescaped));
                    break;
                }
                default:
                  yp_compile_node(iseq, part, ret, src, popped, compile_context);
                  ADD_INSN(ret, &dummy_line_node, dup);
                  ADD_INSN1(ret, &dummy_line_node, objtostring, new_callinfo(iseq, idTo_s, 0, VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE, NULL, FALSE));
                  ADD_INSN(ret, &dummy_line_node, anytostring);
                  break;
              }
          }

          if (interp_symbol_node->parts.size > 1) {
              ADD_INSN1(ret, &dummy_line_node, concatstrings, INT2FIX((int)(interp_symbol_node->parts.size)));
          }

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, intern);
          }
          else {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          return;
      }
      case YP_NODE_KEYWORD_HASH_NODE: {
          yp_keyword_hash_node_t *keyword_hash_node = (yp_keyword_hash_node_t *) node;
          yp_node_list_t elements = keyword_hash_node->elements;

          for (size_t index = 0; index < elements.size; index++) {
              yp_compile_node(iseq, elements.nodes[index], ret, src, popped, compile_context);
          }

          ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(elements.size * 2));
          return;
      }
      case YP_NODE_LAMBDA_NODE: {
          yp_scope_node_t scope_node;
          yp_scope_node_init((yp_node_t *)node, &scope_node);

          const rb_iseq_t *block = NEW_CHILD_ISEQ(&scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
          VALUE argc = INT2FIX(0);

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
          ADD_CALL_WITH_BLOCK(ret, &dummy_line_node, idLambda, argc, block);
          RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)block);

          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_LOCAL_VARIABLE_AND_WRITE_NODE: {
          yp_local_variable_and_write_node_t *local_variable_and_write_node = (yp_local_variable_and_write_node_t*) node;

          LABEL *end_label = NEW_LABEL(lineno);

          yp_constant_id_t constant_id = local_variable_and_write_node->name;
          int depth = local_variable_and_write_node->depth;
          int local_index = yp_lookup_local_index_with_depth(iseq, compile_context, constant_id, depth);
          ADD_GETLOCAL(ret, &dummy_line_node, local_index, depth);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          yp_compile_node(iseq, local_variable_and_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_SETLOCAL(ret, &dummy_line_node, local_index, depth);
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_LOCAL_VARIABLE_OPERATOR_WRITE_NODE: {
          yp_local_variable_operator_write_node_t *local_variable_operator_write_node = (yp_local_variable_operator_write_node_t*) node;

          yp_constant_id_t constant_id = local_variable_operator_write_node->name;

          int depth = local_variable_operator_write_node->depth;
          int local_index = yp_lookup_local_index_with_depth(iseq, compile_context, constant_id, depth);
          ADD_GETLOCAL(ret, &dummy_line_node, local_index, depth);

          yp_compile_node(iseq, local_variable_operator_write_node->value, ret, src, false, compile_context);
          ID method_id = yp_constant_id_lookup(compile_context, local_variable_operator_write_node->operator);

          int flags = VM_CALL_ARGS_SIMPLE | VM_CALL_FCALL | VM_CALL_VCALL;
          ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_SETLOCAL(ret, &dummy_line_node, local_index, depth);

          return;
      }
      case YP_NODE_LOCAL_VARIABLE_OR_WRITE_NODE: {
          yp_local_variable_or_write_node_t *local_variable_or_write_node = (yp_local_variable_or_write_node_t*) node;

          LABEL *set_label= NEW_LABEL(lineno);
          LABEL *end_label = NEW_LABEL(lineno);

          ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
          ADD_INSNL(ret, &dummy_line_node, branchunless, set_label);

          yp_constant_id_t constant_id = local_variable_or_write_node->name;
          int depth = local_variable_or_write_node->depth;
          int local_index = yp_lookup_local_index_with_depth(iseq, compile_context, constant_id, depth);
          ADD_GETLOCAL(ret, &dummy_line_node, local_index, depth);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          ADD_LABEL(ret, set_label);
          yp_compile_node(iseq, local_variable_or_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_SETLOCAL(ret, &dummy_line_node, local_index, depth);
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_LOCAL_VARIABLE_READ_NODE: {
          yp_local_variable_read_node_t *local_read_node = (yp_local_variable_read_node_t *) node;

          if (!popped) {
              int index = yp_lookup_local_index(iseq, compile_context, local_read_node->name);
              ADD_GETLOCAL(ret, &dummy_line_node, index, local_read_node->depth);
          }
          return;
      }
      case YP_NODE_LOCAL_VARIABLE_WRITE_NODE: {
          yp_local_variable_write_node_t *local_write_node = (yp_local_variable_write_node_t *) node;
          yp_compile_node(iseq, local_write_node->value, ret, src, false, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          yp_constant_id_t constant_id = local_write_node->name;
          int index = yp_lookup_local_index(iseq, compile_context, constant_id);

          ADD_SETLOCAL(ret, &dummy_line_node, (int)index, local_write_node->depth);
          return;
      }
      case YP_NODE_MISSING_NODE: {
          rb_bug("A yp_missing_node_t should not exist in YARP's AST.");
          return;
      }
      case YP_NODE_MODULE_NODE: {
          yp_module_node_t *module_node = (yp_module_node_t *)node;
          yp_scope_node_t scope_node;
          yp_scope_node_init((yp_node_t *)module_node, &scope_node);

          ID module_id = yp_constant_id_lookup(compile_context, module_node->name_constant);
          VALUE module_name = rb_str_freeze(rb_sprintf("<module:%"PRIsVALUE">", rb_id2str(module_id)));

          const rb_iseq_t *module_iseq = NEW_CHILD_ISEQ(&scope_node, module_name, ISEQ_TYPE_CLASS, lineno);

          const int flags = VM_DEFINECLASS_TYPE_MODULE |
              yp_compile_class_path(ret, iseq, module_node->constant_path, &dummy_line_node, src, popped, compile_context);

          ADD_INSN(ret, &dummy_line_node, putnil);
          ADD_INSN3(ret, &dummy_line_node, defineclass, ID2SYM(module_id), module_iseq, INT2FIX(flags));
          RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)module_iseq);

          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_MULTI_WRITE_NODE: {
          yp_multi_write_node_t *multi_write_node = (yp_multi_write_node_t *)node;
          yp_compile_node(iseq, multi_write_node->value, ret, src, popped, compile_context);

          // TODO: int flag = 0x02 | (NODE_NAMED_REST_P(restn) ? 0x01 : 0x00);
          int flag = 0x00;

          ADD_INSN(ret, &dummy_line_node, dup);
          ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(multi_write_node->targets.size), INT2FIX(flag));
          yp_node_list_t node_list = multi_write_node->targets;

          for (size_t index = 0; index < node_list.size; index++) {
              yp_compile_node(iseq, node_list.nodes[index], ret, src, popped, compile_context);
          }

          return;
      }
      case YP_NODE_NEXT_NODE: {
          yp_next_node_t *next_node = (yp_next_node_t *) node;
          if (next_node->arguments) {
              yp_compile_node(iseq, (yp_node_t *)next_node->arguments, ret, src, Qfalse, compile_context);
          }
          else {
              ADD_INSN(ret, &dummy_line_node, putnil);
          }

          ADD_INSN(ret, &dummy_line_node, pop);
          ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->start_label);

          return;
      }
      case YP_NODE_NIL_NODE:
        if (!popped) {
            ADD_INSN(ret, &dummy_line_node, putnil);
        }
        return;
      case YP_NODE_NUMBERED_REFERENCE_READ_NODE: {
          if (!popped) {
              uint32_t reference_number = ((yp_numbered_reference_read_node_t *)node)->number;
              ADD_INSN2(ret, &dummy_line_node, getspecial, INT2FIX(1), INT2FIX(reference_number << 1));
          }
          return;
      }
      case YP_NODE_OR_NODE: {
          yp_or_node_t *or_node = (yp_or_node_t *) node;

          LABEL *end_label = NEW_LABEL(lineno);
          yp_compile_node(iseq, or_node->left, ret, src, popped, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }
          ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          yp_compile_node(iseq, or_node->right, ret, src, popped, compile_context);
          ADD_LABEL(ret, end_label);

          return;
      }
      case YP_NODE_OPTIONAL_PARAMETER_NODE: {
          yp_optional_parameter_node_t *optional_parameter_node = (yp_optional_parameter_node_t *)node;
          yp_compile_node(iseq, optional_parameter_node->value, ret, src, false, compile_context);

          int index = yp_lookup_local_index(iseq, compile_context, optional_parameter_node->name);

          ADD_SETLOCAL(ret, &dummy_line_node, index, 0);

          return;
      }
      case YP_NODE_PARENTHESES_NODE: {
          yp_parentheses_node_t *parentheses_node = (yp_parentheses_node_t *) node;

          if (parentheses_node->body == NULL) {
              ADD_INSN(ret, &dummy_line_node, putnil);
          } else {
              yp_compile_node(iseq, parentheses_node->body, ret, src, popped, compile_context);
          }

          return;
      }
      case YP_NODE_PROGRAM_NODE: {
          yp_program_node_t *program_node = (yp_program_node_t *) node;

          yp_scope_node_t scope_node;
          yp_scope_node_init((yp_node_t *)node, &scope_node);
          if (program_node->statements->body.size == 0) {
              ADD_INSN(ret, &dummy_line_node, putnil);
          } else {
              yp_scope_node_t *res_node = &scope_node;
              yp_compile_node(iseq, (yp_node_t *) res_node, ret, src, popped, compile_context);
          }

          return;
      }
      case YP_NODE_RANGE_NODE: {
          yp_range_node_t *range_node = (yp_range_node_t *) node;
          bool exclusive = (range_node->operator_loc.end - range_node->operator_loc.start) == 3;

          if (yp_optimizable_range_item_p(range_node->left) && yp_optimizable_range_item_p(range_node->right))  {
              if (!popped) {
                  yp_node_t *left = range_node->left;
                  yp_node_t *right = range_node->right;
                  VALUE val = rb_range_new(
                          left && left->type == YP_NODE_INTEGER_NODE ? parse_number(left) : Qnil,
                          right && right->type == YP_NODE_INTEGER_NODE ? parse_number(right) : Qnil,
                          exclusive
                          );
                  ADD_INSN1(ret, &dummy_line_node, putobject, val);
                  RB_OBJ_WRITTEN(iseq, Qundef, val);
              }
          }
          else {
              if (range_node->left == NULL) {
                  ADD_INSN(ret, &dummy_line_node, putnil);
              } else {
                  yp_compile_node(iseq, range_node->left, ret, src, popped, compile_context);
              }

              if (range_node->right == NULL) {
                  ADD_INSN(ret, &dummy_line_node, putnil);
              } else {
                  yp_compile_node(iseq, range_node->right, ret, src, popped, compile_context);
              }

              if (!popped) {
                  ADD_INSN1(ret, &dummy_line_node, newrange, INT2FIX(exclusive));
              }
          }
          return;
      }
      case YP_NODE_REDO_NODE: {
          ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->redo_label);
          return;
      }
      case YP_NODE_RETURN_NODE: {
          yp_arguments_node_t *arguments = ((yp_return_node_t *)node)->arguments;

          if (arguments) {
              yp_compile_node(iseq, (yp_node_t *)arguments, ret, src, popped, compile_context);
          }
          else {
              ADD_INSN(ret, &dummy_line_node, putnil);
          }

          ADD_TRACE(ret, RUBY_EVENT_RETURN);
          ADD_INSN(ret, &dummy_line_node, leave);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, putnil);
          }
          return;
      }
      case YP_NODE_SCOPE_NODE: {
          yp_scope_node_t *scope_node = (yp_scope_node_t *)node;
          yp_constant_id_list_t locals = scope_node->locals;

          yp_parameters_node_t *parameters_node = (yp_parameters_node_t *)scope_node->parameters;
          yp_node_list_t requireds_list = YP_EMPTY_NODE_LIST;
          yp_node_list_t optionals_list = YP_EMPTY_NODE_LIST;


          if (parameters_node) {
              requireds_list = parameters_node->requireds;
              optionals_list = parameters_node->optionals;
          }

          size_t size = locals.size;

          // Index lookup table buffer size is only the number of the locals
          st_table *index_lookup_table = st_init_numtable();

          VALUE idtmp = 0;
          rb_ast_id_table_t *tbl = ALLOCV(idtmp, sizeof(rb_ast_id_table_t) + size * sizeof(ID));
          tbl->size = (int)size;

          // First param gets 0, second param 1, param n...
          // Calculate the local index for all locals
          for (size_t i = 0; i < size; i++) {
              yp_constant_id_t constant_id = locals.ids[i];
              ID local = yp_constant_id_lookup(compile_context, constant_id);
              tbl->ids[i] = local;
              st_insert(index_lookup_table, constant_id, i);
          }

          yp_compile_context_t scope_compile_context = {
              .parser = parser,
              .previous = compile_context,
              .constants = compile_context->constants,
              .index_lookup_table = index_lookup_table
          };

          ISEQ_BODY(iseq)->param.lead_num = (int)requireds_list.size;
          ISEQ_BODY(iseq)->param.opt_num = (int)optionals_list.size;
          // TODO: Set all the other nums (good comment by lead_num illustrating what they are)
          ISEQ_BODY(iseq)->param.size = (unsigned int)size;

          if (optionals_list.size) {
              LABEL **opt_table = (LABEL **)ALLOC_N(VALUE, optionals_list.size + 1);
              LABEL *label;

              // TODO: Should we make an api for NEW_LABEL where you can pass
              // a pointer to the label it should fill out?  We already
              // have a list of labels allocated above so it seems wasteful
              // to do the copies.
              for (size_t i = 0; i < optionals_list.size; i++) {
                  label = NEW_LABEL(lineno);
                  opt_table[i] = label;
                  ADD_LABEL(ret, label);
                  yp_node_t *optional_node = optionals_list.nodes[i];
                  yp_compile_node(iseq, optional_node, ret, src, false, &scope_compile_context);
              }

              // Set the last label
              label = NEW_LABEL(lineno);
              opt_table[optionals_list.size] = label;
              ADD_LABEL(ret, label);

              ISEQ_BODY(iseq)->param.flags.has_opt = TRUE;
              ISEQ_BODY(iseq)->param.opt_table = (const VALUE *)opt_table;
          }

          iseq_set_local_table(iseq, tbl);

          switch (ISEQ_BODY(iseq)->type) {
            case ISEQ_TYPE_BLOCK:
              {
                  LABEL *start = ISEQ_COMPILE_DATA(iseq)->start_label = NEW_LABEL(0);
                  LABEL *end = ISEQ_COMPILE_DATA(iseq)->end_label = NEW_LABEL(0);

                  start->rescued = LABEL_RESCUE_BEG;
                  end->rescued = LABEL_RESCUE_END;

                  ADD_TRACE(ret, RUBY_EVENT_B_CALL);
                  NODE dummy_line_node = generate_dummy_line_node(ISEQ_BODY(iseq)->location.first_lineno, -1);
                  ADD_INSN (ret, &dummy_line_node, nop);
                  ADD_LABEL(ret, start);

                  if (scope_node->body) {
                      yp_compile_node(iseq, (yp_node_t *)(scope_node->body), ret, src, popped, &scope_compile_context);
                  }

                  ADD_LABEL(ret, end);
                  ADD_TRACE(ret, RUBY_EVENT_B_RETURN);
                  ISEQ_COMPILE_DATA(iseq)->last_line = ISEQ_BODY(iseq)->location.code_location.end_pos.lineno;

                  /* wide range catch handler must put at last */
                  ADD_CATCH_ENTRY(CATCH_TYPE_REDO, start, end, NULL, start);
                  ADD_CATCH_ENTRY(CATCH_TYPE_NEXT, start, end, NULL, end);
                  break;
              }
            default:
              if (scope_node->body) {
                  yp_compile_node(iseq, (yp_node_t *)(scope_node->body), ret, src, popped, &scope_compile_context);
              }
              else {
                  ADD_INSN(ret, &dummy_line_node, putnil);
              }
          }

          free(index_lookup_table);

          ADD_INSN(ret, &dummy_line_node, leave);
          return;
      }
      case YP_NODE_SELF_NODE:
        ADD_INSN(ret, &dummy_line_node, putself);
        return;
      case YP_NODE_SINGLETON_CLASS_NODE: {
          yp_singleton_class_node_t *singleton_class_node = (yp_singleton_class_node_t *)node;
          yp_scope_node_t scope_node;
          yp_scope_node_init((yp_node_t *)singleton_class_node, &scope_node);

          const rb_iseq_t *singleton_class = NEW_ISEQ(&scope_node, rb_fstring_lit("singleton class"),
                  ISEQ_TYPE_CLASS, lineno);

          yp_compile_node(iseq, singleton_class_node->expression, ret, src, popped, compile_context);
          ADD_INSN(ret, &dummy_line_node, putnil);
          ID singletonclass;
          CONST_ID(singletonclass, "singletonclass");

          ADD_INSN3(ret, &dummy_line_node, defineclass,
                  ID2SYM(singletonclass), singleton_class,
                  INT2FIX(VM_DEFINECLASS_TYPE_SINGLETON_CLASS));
          RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)singleton_class);

          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          return;
      }
      case YP_NODE_SOURCE_ENCODING_NODE: {
          const char *encoding = compile_context->parser->encoding.name;
          if (!popped) {
              rb_encoding *enc = rb_find_encoding(rb_str_new_cstr(encoding));
              if (!enc) {
                  rb_bug("Encoding not found!");
              }
              ADD_INSN1(ret, &dummy_line_node, putobject, rb_enc_from_encoding(enc));
          }
          return;
      }
      case YP_NODE_SOURCE_FILE_NODE: {
          yp_source_file_node_t *source_file_node = (yp_source_file_node_t *)node;

          if (!popped) {
              VALUE filepath;
              if (source_file_node->filepath.length == 0) {
                  filepath = rb_fstring_lit("<compiled>");
              }
              else {
                  filepath = parse_string(&source_file_node->filepath);
              }

              ADD_INSN1(ret, &dummy_line_node, putstring, filepath);
          }
          return;
      }
      case YP_NODE_SOURCE_LINE_NODE: {
          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, putobject, INT2FIX(lineno));
          }
          return;
      }
      case YP_NODE_SPLAT_NODE: {
          yp_splat_node_t *splat_node = (yp_splat_node_t *)node;
          yp_compile_node(iseq, splat_node->expression, ret, src, popped, compile_context);

          ADD_INSN1(ret, &dummy_line_node, splatarray, Qtrue);

          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_STATEMENTS_NODE: {
          yp_statements_node_t *statements_node = (yp_statements_node_t *) node;
          yp_node_list_t node_list = statements_node->body;
          for (size_t index = 0; index < node_list.size - 1; index++) {
              yp_compile_node(iseq, node_list.nodes[index], ret, src, true, compile_context);
          }
          yp_compile_node(iseq, node_list.nodes[node_list.size - 1], ret, src, false, compile_context);
          return;
      }
      case YP_NODE_STRING_CONCAT_NODE: {
          yp_string_concat_node_t *str_concat_node = (yp_string_concat_node_t *)node;
          yp_compile_node(iseq, str_concat_node->left, ret, src, popped, compile_context);
          yp_compile_node(iseq, str_concat_node->right, ret, src, popped, compile_context);
          return;
      }
      case YP_NODE_STRING_NODE: {
          if (!popped) {
              yp_string_node_t *string_node = (yp_string_node_t *) node;
              ADD_INSN1(ret, &dummy_line_node, putstring, parse_string(&string_node->unescaped));
          }
          return;
      }
      case YP_NODE_SYMBOL_NODE: {
          yp_symbol_node_t *symbol_node = (yp_symbol_node_t *) node;
          ADD_INSN1(ret, &dummy_line_node, putobject, ID2SYM(parse_string_symbol(&symbol_node->unescaped)));
          return;
      }
      case YP_NODE_TRUE_NODE:
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        }
        return;
      case YP_NODE_UNDEF_NODE: {
          yp_undef_node_t *undef_node = (yp_undef_node_t *) node;

          for (size_t index = 0; index < undef_node->names.size; index++) {
              ADD_INSN1(ret, &dummy_line_node, putspecialobject, VM_SPECIAL_OBJECT_VMCORE);
              ADD_INSN1(ret, &dummy_line_node, putspecialobject, VM_SPECIAL_OBJECT_CBASE);

              yp_compile_node(iseq, undef_node->names.nodes[index], ret, src, popped, compile_context);

              ADD_SEND(ret, &dummy_line_node, rb_intern("core#undef_method"), INT2NUM(2));

              if (index < undef_node->names.size - 1)
                  ADD_INSN(ret, &dummy_line_node, pop);
          }

          return;
      }
      case YP_NODE_UNLESS_NODE: {
          const int line = (int)yp_newline_list_line_column(&(parser->newline_list), node->location.start).line;
          yp_unless_node_t *unless_node = (yp_unless_node_t *)node;
          yp_statements_node_t *node_body = unless_node->statements;
          yp_node_t *node_else = (yp_node_t *)(unless_node->consequent);
          yp_node_t *predicate = unless_node->predicate;

          yp_compile_if(iseq, line, node_body, node_else, predicate, ret, src, popped, compile_context);
          return;
      }
      case YP_NODE_UNTIL_NODE: {
          yp_until_node_t *until_node = (yp_until_node_t *)node;
          yp_statements_node_t *statements = until_node->statements;
          yp_node_t *predicate = until_node->predicate;
          yp_node_flags_t flags = node->flags;

          yp_compile_while(iseq, lineno, flags, node->type, statements, predicate, ret, src, popped, compile_context);
          return;
      }
      case YP_NODE_WHILE_NODE: {
          yp_while_node_t *while_node = (yp_while_node_t *)node;
          yp_statements_node_t *statements = while_node->statements;
          yp_node_t *predicate = while_node->predicate;
          yp_node_flags_t flags = node->flags;

          yp_compile_while(iseq, lineno, flags, node->type, statements, predicate, ret, src, popped, compile_context);
          return;
      }
      case YP_NODE_X_STRING_NODE: {
          yp_x_string_node_t *xstring_node = (yp_x_string_node_t *) node;
          ADD_INSN(ret, &dummy_line_node, putself);
          ADD_INSN1(ret, &dummy_line_node, putobject, parse_string(&xstring_node->unescaped));
          ADD_SEND_WITH_FLAG(ret, &dummy_line_node, rb_intern("`"), INT2NUM(1), INT2FIX(VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE));
          return;
      }
      case YP_NODE_YIELD_NODE: {
          unsigned int flag = 0;
          struct rb_callinfo_kwarg *keywords = NULL;

          VALUE argc = INT2FIX(0);

          ADD_INSN1(ret, &dummy_line_node, invokeblock, new_callinfo(iseq, 0, FIX2INT(argc), flag, keywords, FALSE));

          if (popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }

          int level = 0;
          const rb_iseq_t *tmp_iseq = iseq;
          for (; tmp_iseq != ISEQ_BODY(iseq)->local_iseq; level++ ) {
              tmp_iseq = ISEQ_BODY(tmp_iseq)->parent_iseq;
          }

          if (level > 0) access_outer_variables(iseq, level, rb_intern("yield"), true);

          return;
      }
      default:
        rb_raise(rb_eNotImpError, "node type %s not implemented", yp_node_type_to_str(node->type));
        return;
    }
}

static VALUE
rb_translate_yarp(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret, yp_compile_context_t *compile_context)
{
    RUBY_ASSERT(ISEQ_COMPILE_DATA(iseq));
    RUBY_ASSERT(node->type == YP_NODE_PROGRAM_NODE || node->type == YP_NODE_SCOPE_NODE);

    yp_compile_node(iseq, node, ret, node->location.start, false, compile_context);
    iseq_set_sequence(iseq, ret);
    return Qnil;
}

#undef NEW_ISEQ
#define NEW_ISEQ OLD_ISEQ

#undef NEW_CHILD_ISEQ
#define NEW_CHILD_ISEQ OLD_CHILD_ISEQ
