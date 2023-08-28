#include "yarp.h"

static void
yp_compile_node(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret, const char * src, bool popped) {
    return;
}

static VALUE
rb_translate_yarp(rb_iseq_t *iseq, const yp_node_t *node, LINK_ANCHOR *const ret)
{
    RUBY_ASSERT(ISEQ_COMPILE_DATA(iseq));
    RUBY_ASSERT(node->type == YP_NODE_PROGRAM_NODE);

    yp_compile_node(iseq, node, ret, node->location.start, false);
    iseq_set_sequence(iseq, ret);

    return Qnil;
}
