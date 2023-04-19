// This file is part of a bigger compilation unit

#include "yarp.h"

// The reason we're using this is because we need access to the linked list
// internals, but we also don't want to make a large diff in compile.c
//
//
//
static VALUE
parse_number(const char *start, const char *end) {
  size_t length = end - start;

  char *buffer = malloc(length + 1);
  memcpy(buffer, start, length);

  buffer[length] = '\0';
  VALUE number = rb_cstr_to_inum(buffer, -10, Qfalse);

  free(buffer);
  return number;
}

static void
yp_compile_node(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret) {
  switch (node->type) {
    case YP_NODE_PROGRAM_NODE: {
      yp_program_node_t *program_node = (yp_program_node_t *) node;

      if (program_node->statements->body.size == 0) {
      //  push_putnil(iseq);
      } else {
        yp_compile_node(iseq, (yp_node_t *) program_node->statements, ret);
      }

      NODE dummy_line_node = generate_dummy_line_node(ISEQ_COMPILE_DATA(iseq)->last_line, -1);
      ADD_INSN(ret, &dummy_line_node, leave);
      return;
    }
    case YP_NODE_STATEMENTS_NODE: {
      yp_statements_node_t *statements_node = (yp_statements_node_t *) node;
      yp_node_list_t node_list = statements_node->body;
      for (size_t index = 0; index < node_list.size; index++) {
        yp_compile_node(iseq, node_list.nodes[index], ret);
        // if (index < node_list.size - 1) push_pop(iseq);
      }
      return;
    }
    case YP_NODE_INTEGER_NODE: {
      //push_putobject(iseq, parse_number(node->location.start, node->location.end));
      NODE dummy_line_node = generate_dummy_line_node(ISEQ_COMPILE_DATA(iseq)->last_line, -1);
      ADD_INSN1(ret, &dummy_line_node, putobject, parse_number(node->location.start, node->location.end));
    }
      return;
    default:
      rb_raise(rb_eNotImpError, "node type %d not implemented", node->type);
      return;
    }
}

static VALUE
rb_translate_yarp(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret)
{
    RUBY_ASSERT(ISEQ_COMPILE_DATA(iseq));
    assert(node->type == YP_NODE_PROGRAM_NODE);

    yp_compile_node(iseq, node, ret);
    iseq_set_sequence(iseq, ret);
    // Call YARP specific compiler
    return Qnil;
}

// vim: ft=c
