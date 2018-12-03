#ifndef RBIMPL_INTERN_VM_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_VM_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Public APIs related to ::rb_cRubyVM.
 */
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* vm.c */
int rb_sourceline(void);
const char *rb_sourcefile(void);
int rb_frame_method_id_and_class(ID *idp, VALUE *klassp);

/**
 * Checks if the innermost block/method that the calling function represents is
 * expected to return meaningful return value(s) or not.
 *
 * @retval false It isn't.
 * @retval true  Not sure.
 *
 * When this function returns `false`, the  VM detects that the return value of
 * the  current  block/method  is  discarded.   Such  block/method  can  return
 * anything.  Care  should be taken  if this function returns  otherwise.  That
 * merely indicates that the VM cannot detect the usage of the return values of
 * the current block/method.  They might or might not be actually used.
 */
bool rb_whether_the_return_value_is_used_p(void);

/* vm_eval.c */
VALUE rb_check_funcall(VALUE, ID, int, const VALUE*);
VALUE rb_check_funcall_kw(VALUE, ID, int, const VALUE*, int);
void rb_remove_method(VALUE, const char*);
void rb_remove_method_id(VALUE, ID);

VALUE rb_eval_cmd_kw(VALUE, VALUE, int);
VALUE rb_apply(VALUE, ID, VALUE);

VALUE rb_obj_instance_eval(int, const VALUE*, VALUE);
VALUE rb_obj_instance_exec(int, const VALUE*, VALUE);
VALUE rb_mod_module_eval(int, const VALUE*, VALUE);
VALUE rb_mod_module_exec(int, const VALUE*, VALUE);

/* vm_method.c */
#define HAVE_RB_DEFINE_ALLOC_FUNC 1
typedef VALUE (*rb_alloc_func_t)(VALUE);
void rb_define_alloc_func(VALUE, rb_alloc_func_t);
void rb_undef_alloc_func(VALUE);
rb_alloc_func_t rb_get_alloc_func(VALUE);
void rb_clear_constant_cache(void);
void rb_clear_method_cache_by_class(VALUE);
void rb_alias(VALUE, ID, ID);
void rb_attr(VALUE,ID,int,int,int);
int rb_method_boundp(VALUE, ID, int);
int rb_method_basic_definition_p(VALUE, ID);

int rb_obj_respond_to(VALUE, ID, int);
int rb_respond_to(VALUE, ID);

RBIMPL_ATTR_NORETURN()
VALUE rb_f_notimplement(int argc, const VALUE *argv, VALUE obj, VALUE marker);
#if !defined(RUBY_EXPORT) && defined(_WIN32)
RUBY_EXTERN VALUE (*const rb_f_notimplement_)(int, const VALUE *, VALUE, VALUE marker);
#define rb_f_notimplement (*rb_f_notimplement_)
#endif

/* vm_backtrace.c */
void rb_backtrace(void);
VALUE rb_make_backtrace(void);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_VM_H */
