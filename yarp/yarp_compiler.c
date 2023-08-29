#include "yarp.h"

static VALUE
parse_number(const yp_node_t *node) {
    const char *start = node->location.start;
    const char *end = node->location.end;
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
    return rb_str_new(yp_string_source(string), yp_string_length(string));
}

static inline ID
parse_symbol(const char *start, const char *end) {
    return rb_intern2(start, end - start);
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

static inline ID
parse_location_symbol(yp_location_t *location) {
    return parse_symbol(location->start, location->end);
}

static int
yp_optimizable_range_item_p(yp_node_t *node)
{
    return (!node || node->type == YP_NODE_INTEGER_NODE || node->type == YP_NODE_NIL_NODE);
}

static void yp_compile_node(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret, const char * src, bool popped, yp_compile_context_t *context);

static int
yp_compile_class_path(LINK_ANCHOR *const ret, rb_iseq_t *iseq, const yp_node_t *constant_path_node, const NODE *line_node)
{
    if (constant_path_node->type == YP_NODE_CONSTANT_PATH_NODE) {
        if (((yp_constant_path_node_t *)constant_path_node)->parent) {
            /* Bar::Foo */
            // TODO: yp_compile_node(ret, "nd_else->nd_head", cpath->nd_head));
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
yp_compile_node(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret, const char * src, bool popped, yp_compile_context_t *compile_context) {
    yp_parser_t *parser = compile_context->parser;
    yp_newline_list_t newline_list = parser->newline_list;
    int lineno = (int)yp_newline_list_line_column(&newline_list, node->location.start).line;
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    switch (YP_NODE_TYPE(node)) {
      case YP_NODE_ALIAS_NODE: {
          yp_alias_node_t *alias_node = (yp_alias_node_t *) node;

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, VM_SPECIAL_OBJECT_VMCORE);
          ADD_INSN1(ret, &dummy_line_node, putspecialobject, VM_SPECIAL_OBJECT_CBASE);

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
      case YP_NODE_ASSOC_NODE: {
          yp_assoc_node_t *assoc_node = (yp_assoc_node_t *) node;
          yp_compile_node(iseq, assoc_node->key, ret, src, popped, compile_context);
          yp_compile_node(iseq, assoc_node->value, ret, src, popped, compile_context);
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
      case YP_NODE_BEGIN_NODE: {
          yp_begin_node_t *begin_node = (yp_begin_node_t *) node;
          if (begin_node->statements) {
              yp_compile_node(iseq, (yp_node_t *)begin_node->statements, ret, src, popped, compile_context);
          }
          return;
      }
      case YP_NODE_CLASS_VARIABLE_READ_NODE:
        if (!popped) {
            ID cvar_name = parse_node_symbol((yp_node_t *)node);
            ADD_INSN2(
                    ret,
                    &dummy_line_node,
                    getclassvariable,
                    ID2SYM(cvar_name),
                    get_cvar_ic_value(iseq, cvar_name)
                    );
        }
        return;
      case YP_NODE_CLASS_VARIABLE_WRITE_NODE: {
          yp_class_variable_write_node_t *write_node = (yp_class_variable_write_node_t *) node;
          yp_compile_node(iseq, write_node->value, ret, src, popped, compile_context);
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ID cvar_name = parse_location_symbol(&write_node->name_loc);
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
          return;
      }
      case YP_NODE_CONSTANT_WRITE_NODE: {
          yp_constant_write_node_t *constant_write_node = (yp_constant_write_node_t *) node;
          yp_compile_node(iseq, constant_write_node->value, ret, src, popped, compile_context);

          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }

          ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
          ID constant_name = parse_location_symbol(&constant_write_node->name_loc);
          ADD_INSN1(ret, &dummy_line_node, setconstant, ID2SYM(constant_name));
          return;
      }
      case YP_NODE_DEFINED_NODE: {
          ADD_INSN(ret, &dummy_line_node, putself);
          yp_defined_node_t *defined_node = (yp_defined_node_t *)node;
          enum defined_type dtype = DEFINED_CONST;
          VALUE sym;

          sym = parse_number(defined_node->value);

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
      case YP_NODE_GLOBAL_VARIABLE_READ_NODE:
        if (!popped) {
            ID gvar_name = parse_node_symbol((yp_node_t *)node);
            ADD_INSN1(ret, &dummy_line_node, getglobal, ID2SYM(gvar_name));
        }
        return;
      case YP_NODE_GLOBAL_VARIABLE_WRITE_NODE: {
          yp_global_variable_write_node_t *write_node = (yp_global_variable_write_node_t *) node;
          yp_compile_node(iseq, write_node->value, ret, src, popped, compile_context);
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }
          ID ivar_name = parse_location_symbol(&write_node->name_loc);
          ADD_INSN1(ret, &dummy_line_node, setglobal, ID2SYM(ivar_name));
          return;
      }
      case YP_NODE_IMAGINARY_NODE: {
          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, putobject, parse_number(node));
          }
          return;
      }
      case YP_NODE_INSTANCE_VARIABLE_READ_NODE: {
          if (!popped) {
              ID ivar_name = parse_node_symbol((yp_node_t *)node);
              ADD_INSN2(ret, &dummy_line_node, getinstancevariable,
                      ID2SYM(ivar_name),
                      get_ivar_ic_value(iseq, ivar_name));
          }
          return;
      }
      case YP_NODE_INSTANCE_VARIABLE_WRITE_NODE: {
          yp_instance_variable_write_node_t *write_node = (yp_instance_variable_write_node_t *) node;
          yp_compile_node(iseq, write_node->value, ret, src, popped, compile_context);
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, dup);
          }
          ID ivar_name = parse_location_symbol(&write_node->name_loc);
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
      case YP_NODE_LOCAL_VARIABLE_READ_NODE: {
          yp_local_variable_read_node_t *local_read_node = (yp_local_variable_read_node_t *) node;

          yp_constant_id_t constant_id = local_read_node->name;
          st_data_t local_index;

          for(uint32_t i = 0; i < local_read_node->depth; i++) {
              compile_context = compile_context->previous;
              iseq = (rb_iseq_t *)ISEQ_BODY(iseq)->parent_iseq;
          }

          int num_params = ISEQ_BODY(iseq)->param.size;

          if (!st_lookup(compile_context->index_lookup_table, constant_id, &local_index)) {
              rb_bug("This local does not exist");
          }

          int index = num_params - (int)local_index;

          if (!popped) {
              ADD_GETLOCAL(ret, &dummy_line_node, index, local_read_node->depth);
          }
          return;
      }
      case YP_NODE_LOCAL_VARIABLE_WRITE_NODE: {
          yp_local_variable_write_node_t *local_write_node = (yp_local_variable_write_node_t *) node;

          // TODO: Unclear how we get into the case where this has no value
          if (local_write_node->value) {
              yp_compile_node(iseq, local_write_node->value, ret, src, false, compile_context);
          }
          else {
              rb_bug("???");
          }

          if (!popped)
              ADD_INSN(ret, &dummy_line_node, dup);

          yp_constant_id_t constant_id = local_write_node->name;
          size_t stack_index;

          if (!st_lookup(compile_context->index_lookup_table, constant_id, &stack_index)) {
              rb_bug("This local doesn't exist");
          }

          unsigned int num_params = ISEQ_BODY(iseq)->param.size;
          size_t index = num_params - stack_index;

          ADD_SETLOCAL(ret, &dummy_line_node, (int)index, local_write_node->depth);
          return;
      }
      case YP_NODE_MISSING_NODE: {
          rb_bug("A yp_missing_node_t should not exist in YARP's AST.");
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
      case YP_NODE_NIL_NODE:
        if (!popped) {
            ADD_INSN(ret, &dummy_line_node, putnil);
        }
        return;
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

          yp_constant_id_t constant_id = optional_parameter_node->name;

          size_t param_number;
          if (!st_lookup(compile_context->index_lookup_table, constant_id, &param_number)) {
              rb_bug("This local doesn't exist");
          }

          unsigned int num_params = ISEQ_BODY(iseq)->param.size;
          int index = (int) (num_params - param_number);

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

          if (program_node->statements->body.size == 0) {
              ADD_INSN(ret, &dummy_line_node, putnil);
          } else {
              yp_compile_node(iseq, (yp_node_t *) program_node->statements, ret, src, popped, compile_context);
          }

          ADD_INSN(ret, &dummy_line_node, leave);
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
      case YP_NODE_SELF_NODE:
        ADD_INSN(ret, &dummy_line_node, putself);
        return;
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
          for (size_t index = 0; index < node_list.size; index++) {
              // We only want to have popped == false for the last instruction
              if (!popped && (index != node_list.size - 1)) {
                  popped = true;
              }
              yp_compile_node(iseq, node_list.nodes[index], ret, src, popped, compile_context);
          }
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
