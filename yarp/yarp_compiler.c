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
      case YP_NODE_MISSING_NODE: {
          rb_bug("A yp_missing_node_t should not exist in YARP's AST.");
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
