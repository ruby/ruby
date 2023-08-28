#include "yarp.h"

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
