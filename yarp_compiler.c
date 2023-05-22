// This file is part of a bigger compilation unit

#include "internal/yarp.h"

// The reason we're using this is because we need access to the linked list
// internals, but we also don't want to make a large diff in compile.c
//
//
//
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

    static int
yp_optimizable_range_item_p(yp_node_t *node)
{
    return (!node || node->type == YP_NODE_INTEGER_NODE || node->type == YP_NODE_NIL_NODE);
}

/*
 *
 * iseq is used by ADD_INSN
 * node is the current node
 * ret is the linked list of iseqs we'll return
 * src is the head of the src, just temporarily used for location counting
 * popped is true if the expression can be popped off if it doesn't have side effects
 *  (eg an integer only should be added if !popped)
 */
static void
yp_compile_node(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret, const char * src, bool popped) {
    int lineno = (int)(node->location.start - src);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);
    switch (node->type) {
      case YP_NODE_ARGUMENTS_NODE: {
          yp_arguments_node_t *arguments_node = (yp_arguments_node_t *) node;
          yp_node_list_t node_list = arguments_node->arguments;
          for (size_t index = 0; index < node_list.size; index++) {
              yp_compile_node(iseq, node_list.nodes[index], ret, src, popped);
          }
          return;
      }
      case YP_NODE_ARRAY_NODE: {
          yp_array_node_t *array_node = (yp_array_node_t *) node;
          yp_node_list_t elements = array_node->elements;
          for (size_t index = 0; index < elements.size; index++) {
              yp_compile_node(iseq, elements.nodes[index], ret, src, popped);
          }
          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, newarray, INT2FIX(elements.size));
          }
          // push_newarray(compiler, sizet2int(elements.size));
          return;
      }
      case YP_NODE_ASSOC_NODE: {
          yp_assoc_node_t *assoc_node = (yp_assoc_node_t *) node;
          yp_compile_node(iseq, assoc_node->key, ret, src, popped);
          yp_compile_node(iseq, assoc_node->value, ret, src, popped);
          return;
      }
      case YP_NODE_CALL_NODE: {
          const yp_call_node_t *call_node = (yp_call_node_t *)node;
          // Figure out how many parameters
          // Figure out whether or not it has a block
          const char *method_name = yp_string_source(&call_node->name);
          long method_name_len = (long)yp_string_length(&call_node->name);

          // Look into other types of ADD_SEND to be able to send flags too
          ADD_SEND(ret, &dummy_line_node, rb_intern2(method_name, method_name_len), INT2NUM(call_node->arguments->arguments.size));

          return;
      }
      case YP_NODE_CONSTANT_PATH_NODE: {
          yp_constant_path_node_t *constant_path_node = (yp_constant_path_node_t*) node;
          yp_compile_node(iseq, constant_path_node->parent, ret, src, popped);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
          ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(parse_node_symbol((yp_node_t *)constant_path_node->child)));
          return;
      }
      case YP_NODE_CONSTANT_READ_NODE: {
          yp_constant_read_node_t *constant_read_node = (yp_constant_read_node_t *) node;
          ADD_INSN(ret, &dummy_line_node, putnil);
          ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
          ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(parse_node_symbol((yp_node_t *)constant_read_node)));
          if (!popped) {
              ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_FALSE_NODE:
        // push_putobject(compiler, Qfalse);
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
        }
        return;
      case YP_NODE_HASH_NODE: {
          yp_hash_node_t *hash_node = (yp_hash_node_t *) node;
          yp_node_list_t elements = hash_node->elements;

          for (size_t index = 0; index < elements.size; index++) {
              yp_compile_node(iseq, elements.nodes[index], ret, src, popped);
          }

          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(elements.size * 2));
          }
          return;
      }
      case YP_NODE_INTEGER_NODE: {
          if (!popped) {
              ADD_INSN1(ret, &dummy_line_node, putobject, parse_number(node));
          }
          return;
      }
      case YP_NODE_NIL_NODE:
        //  push_putnil(compiler);
        if (!popped) {
            ADD_INSN(ret, &dummy_line_node, putnil);
        }
        return;
      case YP_NODE_PARENTHESES_NODE: {
          yp_parentheses_node_t *parentheses_node = (yp_parentheses_node_t *) node;

          if (parentheses_node->statements == NULL) {
              //  push_putnil(compiler);
              ADD_INSN(ret, &dummy_line_node, putnil);
          } else {
              yp_compile_node(iseq, parentheses_node->statements, ret, src, popped);
          }

          return;
      }
      case YP_NODE_PROGRAM_NODE: {
          yp_program_node_t *program_node = (yp_program_node_t *) node;

          if (program_node->statements->body.size == 0) {
              ADD_INSN(ret, &dummy_line_node, putnil);
          } else {
              yp_compile_node(iseq, (yp_node_t *) program_node->statements, ret, src, popped);
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
                  yp_compile_node(iseq, range_node->left, ret, src, popped);
              }

              if (range_node->right == NULL) {
                  ADD_INSN(ret, &dummy_line_node, putnil);
              } else {
                  yp_compile_node(iseq, range_node->right, ret, src, popped);
              }

              if (!popped) {
                  ADD_INSN1(ret, &dummy_line_node, newrange, INT2FIX(exclusive));
              }
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
              bool popped = true;
              if (index == node_list.size - 1) {
                  popped = false;
              }
              yp_compile_node(iseq, node_list.nodes[index], ret, src, popped);
              //        if (index < node_list.size - 1) ADD_INSN(ret, &dummy_line_node, pop);
          }
          return;
      }
      case YP_NODE_STRING_NODE: {
          if (!popped) {
              yp_string_node_t *string_node = (yp_string_node_t *) node;
              ADD_INSN1(ret, &dummy_line_node, putstring, parse_string(&string_node->unescaped));
          }
          return;
      }
      case YP_NODE_STRING_INTERPOLATED_NODE: {
          yp_string_interpolated_node_t *string_interpolated_node = (yp_string_interpolated_node_t *) node;
          yp_compile_node(iseq, (yp_node_t *) string_interpolated_node->statements, ret, src, popped);
          return;
      }
      case YP_NODE_SYMBOL_NODE: {
          yp_symbol_node_t *symbol_node = (yp_symbol_node_t *) node;
          ADD_INSN1(ret, &dummy_line_node, putobject, ID2SYM(parse_string_symbol(&symbol_node->unescaped)));
          //push_putobject(compiler, ID2SYM(parse_string_symbol(&node->unescaped)));
          return;
      }
      case YP_NODE_TRUE_NODE:
        // push_putobject(compiler, Qtrue);
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        }
        return;
      default:
        rb_raise(rb_eNotImpError, "jem: node type %d not implemented", node->type);
        return;
    }
}

static VALUE
rb_translate_yarp(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret)
{
    RUBY_ASSERT(ISEQ_COMPILE_DATA(iseq));
    RUBY_ASSERT(node->type == YP_NODE_PROGRAM_NODE);

    yp_compile_node(iseq, node, ret, node->location.start, false);
    iseq_set_sequence(iseq, ret);
    // Call YARP specific compiler
    return Qnil;
}

// vim: ft=c
