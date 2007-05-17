/**********************************************************************

  debug.c -

  $Author$
  $Date$
  created at: 04/08/25 02:31:54 JST

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#include "ruby.h"
#include "debug.h"

void
ruby_debug_indent(int level, int debug_level, int indent_level)
{
    if (level < debug_level) {
	int i;
	for (i = 0; i < indent_level; i++) {
	    fprintf(stderr, " ");
	}
	fflush(stderr);
    }
}

VALUE
ruby_debug_value(int level, int debug_level, char *header, VALUE obj)
{
    if (level < debug_level) {
	VALUE str;
	str = rb_inspect(obj);
	fprintf(stderr, "DBG> %s: %s\n", header,
	       obj == -1 ? "" : StringValueCStr(str));
	fflush(stderr);
    }
    return obj;
}

void
ruby_debug_v(VALUE v)
{
    ruby_debug_value(0, 1, "", v);
}

ID
ruby_debug_id(int level, int debug_level, char *header, ID id)
{
    if (level < debug_level) {
	fprintf(stderr, "DBG> %s: %s\n", header, rb_id2name(id));
	fflush(stderr);
    }
    return id;
}

NODE *
ruby_debug_node(int level, int debug_level, char *header, NODE *node)
{
    if (level < debug_level) {
	fprintf(stderr, "DBG> %s: %s (%d)\n", header,
		ruby_node_name(nd_type(node)), nd_line(node));
    }
    return node;
}


void
ruby_debug_gc_check_func(void)
{
    int i;
#define GCMKMAX 0x10
    for (i = 0; i < GCMKMAX; i++) {
	rb_ary_new2(1000);
    }
    rb_gc();
}

void
ruby_debug_breakpoint(void)
{
    /* */
}
