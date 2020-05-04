#ifndef RUBY_RUBY_H                                  /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_RUBY_H 1
/**
 * @file
 * @author     $Author$
 * @date       Thu Jun 10 14:26:32 JST 1993
 * @copyright  Copyright (C) 1993-2008 Yukihiro Matsumoto
 * @copyright  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
 * @copyright  Copyright (C) 2000  Information-technology Promotion Agency, Japan
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/impl/config.h"

#ifdef HAVE_INTRINSICS_H
# include <intrinsics.h>
#endif

#include <stdarg.h>

#include "defines.h"
#include "ruby/impl/anyargs.h"
#include "ruby/impl/arithmetic.h"
#include "ruby/impl/core.h"
#include "ruby/impl/ctype.h"
#include "ruby/impl/dllexport.h"
#include "ruby/impl/error.h"
#include "ruby/impl/eval.h"
#include "ruby/impl/event.h"
#include "ruby/impl/fl_type.h"
#include "ruby/impl/gc.h"
#include "ruby/impl/glob.h"
#include "ruby/impl/globals.h"
#include "ruby/impl/has/warning.h"
#include "ruby/impl/interpreter.h"
#include "ruby/impl/iterator.h"
#include "ruby/impl/memory.h"
#include "ruby/impl/method.h"
#include "ruby/impl/module.h"
#include "ruby/impl/newobj.h"
#include "ruby/impl/rgengc.h"
#include "ruby/impl/scan_args.h"
#include "ruby/impl/special_consts.h"
#include "ruby/impl/symbol.h"
#include "ruby/impl/value.h"
#include "ruby/impl/value_type.h"
#include "ruby/impl/variable.h"
#include "ruby/assert.h"
#include "ruby/backward/2/assume.h"
#include "ruby/backward/2/inttypes.h"
#include "ruby/backward/2/limits.h"
#include "ruby/backward/2/rmodule.h"
#include "ruby/backward/2/r_cast.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* Module#methods, #singleton_methods and so on return Symbols */
#define USE_SYMBOL_AS_METHOD_NAME 1

VALUE rb_get_path(VALUE);
#define FilePathValue(v) (RB_GC_GUARD(v) = rb_get_path(v))

VALUE rb_get_path_no_checksafe(VALUE);
#define FilePathStringValue(v) ((v) = rb_get_path(v))

#if defined(HAVE_BUILTIN___BUILTIN_CONSTANT_P) && defined(HAVE_STMT_AND_DECL_IN_EXPR)
# define rb_varargs_argc_check_runtime(argc, vargc) \
    (((argc) <= (vargc)) ? (argc) : \
     (rb_fatal("argc(%d) exceeds actual arguments(%d)", \
	       argc, vargc), 0))
# define rb_varargs_argc_valid_p(argc, vargc) \
    ((argc) == 0 ? (vargc) <= 1 : /* [ruby-core:85266] [Bug #14425] */ \
     (argc) == (vargc))
# if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
#   if HAVE_ATTRIBUTE_ERRORFUNC
ERRORFUNC((" argument length doesn't match"), int rb_varargs_bad_length(int,int));
#   else
#     define rb_varargs_bad_length(argc, vargc) \
	((argc)/rb_varargs_argc_valid_p(argc, vargc))
#   endif
#   define rb_varargs_argc_check(argc, vargc) \
    __builtin_choose_expr(__builtin_constant_p(argc), \
	(rb_varargs_argc_valid_p(argc, vargc) ? (argc) : \
	 rb_varargs_bad_length(argc, vargc)), \
	rb_varargs_argc_check_runtime(argc, vargc))
# else
#   define rb_varargs_argc_check(argc, vargc) \
	rb_varargs_argc_check_runtime(argc, vargc)
# endif
#endif

const char *rb_class2name(VALUE);
const char *rb_obj_classname(VALUE);

void rb_p(VALUE);

VALUE rb_equal(VALUE,VALUE);

VALUE rb_require(const char*);

#include "ruby/intern.h"

#if defined(EXTLIB) && defined(USE_DLN_A_OUT)
/* hook for external modules */
static char *dln_libs_to_be_linked[] = { EXTLIB, 0 };
#endif

#define RUBY_VM 1 /* YARV */
#define HAVE_NATIVETHREAD
int ruby_native_thread_p(void);

#define InitVM(ext) {void InitVM_##ext(void);InitVM_##ext();}

PRINTF_ARGS(int ruby_snprintf(char *str, size_t n, char const *fmt, ...), 3, 4);
int ruby_vsnprintf(char *str, size_t n, char const *fmt, va_list ap);

#if RBIMPL_HAS_WARNING("-Wgnu-zero-variadic-macro-arguments")
# /* Skip it; clang -pedantic doesn't like the following */
#elif defined(__GNUC__) && defined(HAVE_VA_ARGS_MACRO) && defined(__OPTIMIZE__)
# define rb_yield_values(argc, ...) \
__extension__({ \
	const int rb_yield_values_argc = (argc); \
	const VALUE rb_yield_values_args[] = {__VA_ARGS__}; \
	const int rb_yield_values_nargs = \
	    (int)(sizeof(rb_yield_values_args) / sizeof(VALUE)); \
	rb_yield_values2( \
	    rb_varargs_argc_check(rb_yield_values_argc, rb_yield_values_nargs), \
	    rb_yield_values_nargs ? rb_yield_values_args : NULL); \
    })

# define rb_funcall(recv, mid, argc, ...) \
__extension__({ \
	const int rb_funcall_argc = (argc); \
	const VALUE rb_funcall_args[] = {__VA_ARGS__}; \
	const int rb_funcall_nargs = \
	    (int)(sizeof(rb_funcall_args) / sizeof(VALUE)); \
        rb_funcallv(recv, mid, \
	    rb_varargs_argc_check(rb_funcall_argc, rb_funcall_nargs), \
	    rb_funcall_nargs ? rb_funcall_args : NULL); \
    })
#endif

#ifndef RUBY_DONT_SUBST
#include "ruby/subst.h"
#endif

#if !defined RUBY_EXPORT && !defined RUBY_NO_OLD_COMPATIBILITY
# include "ruby/backward.h"
#endif

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_RUBY_H */
