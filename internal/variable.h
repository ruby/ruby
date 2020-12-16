#ifndef INTERNAL_VARIABLE_H                              /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_VARIABLE_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for variables.
 */
#include "ruby/internal/config.h"
#include <stddef.h>             /* for size_t */
#include "constant.h"           /* for rb_const_entry_t */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "ruby/ruby.h"          /* for VALUE */

/* global variable */

#define ROBJECT_TRANSIENT_FLAG    FL_USER13

/* variable.c */
void rb_gc_mark_global_tbl(void);
void rb_gc_update_global_tbl(void);
size_t rb_generic_ivar_memsize(VALUE);
VALUE rb_search_class_path(VALUE);
VALUE rb_attr_delete(VALUE, ID);
VALUE rb_ivar_lookup(VALUE obj, ID id, VALUE undef);
void rb_autoload_str(VALUE mod, ID id, VALUE file);
VALUE rb_autoload_at_p(VALUE, ID, int);
NORETURN(VALUE rb_mod_const_missing(VALUE,VALUE));
rb_gvar_getter_t *rb_gvar_getter_function_of(ID);
rb_gvar_setter_t *rb_gvar_setter_function_of(ID);
void rb_gvar_readonly_setter(VALUE v, ID id, VALUE *_);
void rb_gvar_ractor_local(const char *name);
static inline bool ROBJ_TRANSIENT_P(VALUE obj);
static inline void ROBJ_TRANSIENT_SET(VALUE obj);
static inline void ROBJ_TRANSIENT_UNSET(VALUE obj);

RUBY_SYMBOL_EXPORT_BEGIN
/* variable.c (export) */
void rb_mark_generic_ivar(VALUE);
void rb_mv_generic_ivar(VALUE src, VALUE dst);
VALUE rb_const_missing(VALUE klass, VALUE name);
int rb_class_ivar_set(VALUE klass, ID vid, VALUE value);
void rb_iv_tbl_copy(VALUE dst, VALUE src);
void rb_deprecate_constant(VALUE mod, const char *name);
RUBY_SYMBOL_EXPORT_END

MJIT_SYMBOL_EXPORT_BEGIN
VALUE rb_gvar_get(ID);
VALUE rb_gvar_set(ID, VALUE);
VALUE rb_gvar_defined(ID);
void rb_const_warn_if_deprecated(const rb_const_entry_t *, VALUE, ID);
void rb_init_iv_list(VALUE obj);
MJIT_SYMBOL_EXPORT_END

static inline bool
ROBJ_TRANSIENT_P(VALUE obj)
{
#if USE_TRANSIENT_HEAP
    return FL_TEST_RAW(obj, ROBJECT_TRANSIENT_FLAG);
#else
    return false;
#endif
}

static inline void
ROBJ_TRANSIENT_SET(VALUE obj)
{
#if USE_TRANSIENT_HEAP
    FL_SET_RAW(obj, ROBJECT_TRANSIENT_FLAG);
#endif
}

static inline void
ROBJ_TRANSIENT_UNSET(VALUE obj)
{
#if USE_TRANSIENT_HEAP
    FL_UNSET_RAW(obj, ROBJECT_TRANSIENT_FLAG);
#endif
}

#endif /* INTERNAL_VARIABLE_H */
