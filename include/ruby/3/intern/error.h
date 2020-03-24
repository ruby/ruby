/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
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
 * @brief      Public APIs related to ::rb_eException.
 */
#ifndef  RUBY3_INTERN_ERROR_H
#define  RUBY3_INTERN_ERROR_H
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"
#include "ruby/backward/2/attributes.h"

#define UNLIMITED_ARGUMENTS (-1)

RUBY3_SYMBOL_EXPORT_BEGIN()

/* error.c */
VALUE rb_exc_new(VALUE, const char*, long);
VALUE rb_exc_new_cstr(VALUE, const char*);
VALUE rb_exc_new_str(VALUE, VALUE);
#define rb_exc_new2 rb_exc_new_cstr
#define rb_exc_new3 rb_exc_new_str
PRINTF_ARGS(NORETURN(void rb_loaderror(const char*, ...)), 1, 2);
PRINTF_ARGS(NORETURN(void rb_loaderror_with_path(VALUE path, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_name_error(ID, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_name_error_str(VALUE, const char*, ...)), 2, 3);
PRINTF_ARGS(NORETURN(void rb_frozen_error_raise(VALUE, const char*, ...)), 2, 3);
NORETURN(void rb_invalid_str(const char*, const char*));
NORETURN(void rb_error_frozen(const char*));
NORETURN(void rb_error_frozen_object(VALUE));
void rb_error_untrusted(VALUE);
void rb_check_frozen(VALUE);
void rb_check_trusted(VALUE);
#define rb_check_frozen_internal(obj) do { \
        VALUE frozen_obj = (obj); \
        if (RB_UNLIKELY(RB_OBJ_FROZEN(frozen_obj))) { \
            rb_error_frozen_object(frozen_obj); \
        } \
    } while (0)
#ifdef __GNUC__
#define rb_check_frozen(obj) __extension__({rb_check_frozen_internal(obj);})
#else
static inline void
rb_check_frozen_inline(VALUE obj)
{
    rb_check_frozen_internal(obj);
}
#define rb_check_frozen(obj) rb_check_frozen_inline(obj)
static inline void
rb_check_trusted_inline(VALUE obj)
{
    rb_check_trusted(obj);
}
#define rb_check_trusted(obj) rb_check_trusted_inline(obj)
#endif
void rb_check_copyable(VALUE obj, VALUE orig);

NORETURN(MJIT_STATIC void rb_error_arity(int, int, int));
static inline int
rb_check_arity(int argc, int min, int max)
{
    if ((argc < min) || (max != UNLIMITED_ARGUMENTS && argc > max))
        rb_error_arity(argc, min, max);
    return argc;
}
#define rb_check_arity rb_check_arity /* for ifdef */

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_INTERN_ERROR_H */
