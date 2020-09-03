#ifndef RBIMPL_ERROR_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ERROR_H
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
 * @brief      Declares ::rb_raise().
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/backward/2/attributes.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

VALUE rb_errinfo(void);
void rb_set_errinfo(VALUE);

/* for rb_readwrite_sys_fail first argument */
enum rb_io_wait_readwrite {RB_IO_WAIT_READABLE, RB_IO_WAIT_WRITABLE};
#define RB_IO_WAIT_READABLE RB_IO_WAIT_READABLE
#define RB_IO_WAIT_WRITABLE RB_IO_WAIT_WRITABLE

PRINTF_ARGS(NORETURN(void rb_raise(VALUE, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_fatal(const char*, ...)), 1, 2);
COLDFUNC PRINTF_ARGS(NORETURN(void rb_bug(const char*, ...)), 1, 2);
NORETURN(void rb_bug_errno(const char*, int));
NORETURN(void rb_sys_fail(const char*));
NORETURN(void rb_sys_fail_str(VALUE));
NORETURN(void rb_mod_sys_fail(VALUE, const char*));
NORETURN(void rb_mod_sys_fail_str(VALUE, VALUE));
NORETURN(void rb_readwrite_sys_fail(enum rb_io_wait_readwrite, const char*));
NORETURN(void rb_iter_break(void));
NORETURN(void rb_iter_break_value(VALUE));
NORETURN(void rb_exit(int));
NORETURN(void rb_notimplement(void));
VALUE rb_syserr_new(int, const char *);
VALUE rb_syserr_new_str(int n, VALUE arg);
NORETURN(void rb_syserr_fail(int, const char*));
NORETURN(void rb_syserr_fail_str(int, VALUE));
NORETURN(void rb_mod_syserr_fail(VALUE, int, const char*));
NORETURN(void rb_mod_syserr_fail_str(VALUE, int, VALUE));
NORETURN(void rb_readwrite_syserr_fail(enum rb_io_wait_readwrite, int, const char*));
NORETURN(void rb_unexpected_type(VALUE,int));

VALUE *rb_ruby_verbose_ptr(void);
VALUE *rb_ruby_debug_ptr(void);
#define ruby_verbose (*rb_ruby_verbose_ptr())
#define ruby_debug   (*rb_ruby_debug_ptr())

/* reports if `-W' specified */
PRINTF_ARGS(void rb_warning(const char*, ...), 1, 2);
PRINTF_ARGS(void rb_category_warning(const char*, const char*, ...), 2, 3);
PRINTF_ARGS(void rb_compile_warning(const char *, int, const char*, ...), 3, 4);
PRINTF_ARGS(void rb_sys_warning(const char*, ...), 1, 2);
/* reports always */
COLDFUNC PRINTF_ARGS(void rb_warn(const char*, ...), 1, 2);
COLDFUNC PRINTF_ARGS(void rb_category_warn(const char *, const char*, ...), 2, 3);
PRINTF_ARGS(void rb_compile_warn(const char *, int, const char*, ...), 3, 4);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_ERROR_H */
