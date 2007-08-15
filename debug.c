/**********************************************************************

  debug.c -

  $Author$
  $Date$
  created at: 04/08/25 02:31:54 JST

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "debug.h"
#include "vm_core.h"

void
ruby_debug_print_indent(int level, int debug_level, int indent_level)
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
ruby_debug_print_value(int level, int debug_level, const char *header, VALUE obj)
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
ruby_debug_print_v(VALUE v)
{
    ruby_debug_print_value(0, 1, "", v);
}

ID
ruby_debug_print_id(int level, int debug_level, const char *header, ID id)
{
    if (level < debug_level) {
	fprintf(stderr, "DBG> %s: %s\n", header, rb_id2name(id));
	fflush(stderr);
    }
    return id;
}

NODE *
ruby_debug_print_node(int level, int debug_level, const char *header, const NODE *node)
{
    if (level < debug_level) {
	fprintf(stderr, "DBG> %s: %s (%lu)\n", header,
		ruby_node_name(nd_type(node)), nd_line(node));
    }
    return (NODE *)node;
}

void
ruby_debug_breakpoint(void)
{
    /* */
}

#ifdef RUBY_DEBUG_ENV
#include <ctype.h>

void
ruby_set_debug_option(const char *str)
{
    const char *end;
    int len;

    if (!str) return;
    for (; *str; str = end) {
	while (ISSPACE(*str) || *str == ',') str++;
	if (!*str) break;
	end = str;
	while (*end && !ISSPACE(*end) && *end != ',') end++;
	len = end - str;
#define SET_WHEN(name, var)		    \
	if (len == sizeof(name) - 1 &&	    \
	    strncmp(str, name, len) == 0) { \
	    extern int ruby_##var;	    \
	    ruby_##var = 1;		    \
	    continue;			    \
	}
	SET_WHEN("gc_stress", gc_stress);
	SET_WHEN("core", enable_coredump);
	fprintf(stderr, "unexpected debug option: %.*s\n", len, str);
    }
}
#endif
