/**********************************************************************

  debug.c -

  $Author$
  $Date$
  created at: 04/08/25 02:31:54 JST

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "debug.h"
#include "vm_core.h"

/* for gdb */
static const union {
    enum ruby_special_consts    special_consts;
    enum ruby_value_type        value_type;
    enum node_type              node_type;
    enum {
        RUBY_ENCODING_SHIFT = ENCODING_SHIFT
    } various;
} dummy_gdb_enums;

const VALUE RUBY_FL_MARK      = FL_MARK;
const VALUE RUBY_FL_RESERVED  = FL_RESERVED;
const VALUE RUBY_FL_FINALIZE  = FL_FINALIZE;
const VALUE RUBY_FL_TAINT     = FL_TAINT;
const VALUE RUBY_FL_EXIVAR    = FL_EXIVAR;
const VALUE RUBY_FL_FREEZE    = FL_FREEZE;
const VALUE RUBY_FL_SINGLETON = FL_SINGLETON;
const VALUE RUBY_FL_USER0     = FL_USER0;
const VALUE RUBY_FL_USER1     = FL_USER1;
const VALUE RUBY_FL_USER2     = FL_USER2;
const VALUE RUBY_FL_USER3     = FL_USER3;
const VALUE RUBY_FL_USER4     = FL_USER4;
const VALUE RUBY_FL_USER5     = FL_USER5;
const VALUE RUBY_FL_USER6     = FL_USER6;
const VALUE RUBY_FL_USER7     = FL_USER7;
const VALUE RUBY_FL_USER8     = FL_USER8;
const VALUE RUBY_FL_USER9     = FL_USER9;
const VALUE RUBY_FL_USER10    = FL_USER10;
const VALUE RUBY_FL_USER11    = FL_USER11;
const VALUE RUBY_FL_USER12    = FL_USER12;
const VALUE RUBY_FL_USER13    = FL_USER13;
const VALUE RUBY_FL_USER14    = FL_USER14;
const VALUE RUBY_FL_USER15    = FL_USER15;
const VALUE RUBY_FL_USER16    = FL_USER16;
const VALUE RUBY_FL_USER17    = FL_USER17;
const VALUE RUBY_FL_USER18    = FL_USER18;
const VALUE RUBY_FL_USER19    = FL_USER19;
const VALUE RUBY_FL_USER20    = FL_USER20;
const int RUBY_FL_USHIFT = FL_USHIFT;

const VALUE RUBY_NODE_NEWLINE = NODE_NEWLINE;
const int RUBY_NODE_TYPESHIFT = NODE_TYPESHIFT;
const VALUE RUBY_NODE_TYPEMASK = NODE_TYPEMASK;
const int RUBY_NODE_LSHIFT = NODE_LSHIFT;
const VALUE RUBY_NODE_LMASK = NODE_LMASK;

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
