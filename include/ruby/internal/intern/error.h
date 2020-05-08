#ifndef RBIMPL_INTERN_ERROR_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_ERROR_H
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
 * @brief      Public APIs related to ::rb_eException.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/fl_type.h"
#include "ruby/backward/2/assume.h"
#include "ruby/backward/2/attributes.h"

#define UNLIMITED_ARGUMENTS     (-1)
#define rb_exc_new2             rb_exc_new_cstr
#define rb_exc_new3             rb_exc_new_str
#define rb_check_trusted        rb_check_trusted
#define rb_check_trusted_inline rb_check_trusted
#define rb_check_arity          rb_check_arity

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* error.c */
VALUE rb_exc_new(VALUE, const char*, long);
VALUE rb_exc_new_cstr(VALUE, const char*);
VALUE rb_exc_new_str(VALUE, VALUE);
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
void rb_check_copyable(VALUE obj, VALUE orig);
NORETURN(MJIT_STATIC void rb_error_arity(int, int, int));
RBIMPL_SYMBOL_EXPORT_END()

/* Does anyone use this?  Remain not deleted for compatibility. */
#define rb_check_frozen_internal(obj) do { \
        VALUE frozen_obj = (obj); \
        if (RB_UNLIKELY(RB_OBJ_FROZEN(frozen_obj))) { \
            rb_error_frozen_object(frozen_obj); \
        } \
    } while (0)

static inline void
rb_check_frozen_inline(VALUE obj)
{
    if (RB_UNLIKELY(RB_OBJ_FROZEN(obj))) {
        rb_error_frozen_object(obj);
    }
}
#define rb_check_frozen rb_check_frozen_inline

static inline int
rb_check_arity(int argc, int min, int max)
{
    if ((argc < min) || (max != UNLIMITED_ARGUMENTS && argc > max))
        rb_error_arity(argc, min, max);
    return argc;
}

#endif /* RBIMPL_INTERN_ERROR_H */
