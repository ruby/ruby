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
