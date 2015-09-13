/**********************************************************************

  debug.c -

  $Author$
  created at: 04/08/25 02:31:54 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "ruby/util.h"
#include "vm_debug.h"
#include "eval_intern.h"
#include "vm_core.h"
#include "id.h"

/* for gdb */
const union {
    enum ruby_special_consts    special_consts;
    enum ruby_value_type        value_type;
    enum ruby_tag_type          tag_type;
    enum node_type              node_type;
    enum ruby_method_ids        method_ids;
    enum ruby_id_types          id_types;
    enum ruby_fl_type           fl_types;
    enum ruby_encoding_consts   encoding_consts;
    enum ruby_coderange_type    enc_coderange_types;
    enum ruby_econv_flag_type   econv_flag_types;
    enum {
        RUBY_NODE_TYPESHIFT = NODE_TYPESHIFT,
        RUBY_NODE_TYPEMASK  = NODE_TYPEMASK,
        RUBY_NODE_LSHIFT    = NODE_LSHIFT,
        RUBY_NODE_FL_NEWLINE   = NODE_FL_NEWLINE
    } various;
} ruby_dummy_gdb_enums;

const SIGNED_VALUE RUBY_NODE_LMASK = NODE_LMASK;

int
ruby_debug_print_indent(int level, int debug_level, int indent_level)
{
    if (level < debug_level) {
	fprintf(stderr, "%*s", indent_level, "");
	fflush(stderr);
	return TRUE;
    }
    return FALSE;
}

void
ruby_debug_printf(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    vfprintf(stderr, format, ap);
    va_end(ap);
}

VALUE
ruby_debug_print_value(int level, int debug_level, const char *header, VALUE obj)
{
    if (level < debug_level) {
	VALUE str;
	str = rb_inspect(obj);
	fprintf(stderr, "DBG> %s: %s\n", header,
		obj == (VALUE)(SIGNED_VALUE)-1 ? "" : StringValueCStr(str));
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
	fprintf(stderr, "DBG> %s: %s (%u)\n", header,
		ruby_node_name(nd_type(node)), nd_line(node));
    }
    return (NODE *)node;
}

void
ruby_debug_breakpoint(void)
{
    /* */
}

static void
set_debug_option(const char *str, int len, void *arg)
{
#if defined _WIN32 && RUBY_MSVCRT_VERSION >= 80
    extern int ruby_w32_rtc_error;
#endif
#define SET_WHEN(name, var, val) do {	    \
	if (len == sizeof(name) - 1 &&	    \
	    strncmp(str, (name), len) == 0) { \
	    (var) = (val);		    \
	    return;			    \
	}				    \
    } while (0)
    SET_WHEN("gc_stress", *ruby_initial_gc_stress_ptr, Qtrue);
    SET_WHEN("core", ruby_enable_coredump, 1);
#if defined _WIN32 && RUBY_MSVCRT_VERSION >= 80
    SET_WHEN("rtc_error", ruby_w32_rtc_error, 1);
#endif
    fprintf(stderr, "unexpected debug option: %.*s\n", len, str);
}

void
ruby_set_debug_option(const char *str)
{
    ruby_each_words(str, set_debug_option, 0);
}
