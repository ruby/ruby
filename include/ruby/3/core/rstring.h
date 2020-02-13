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
 * @brief      Defines struct ::RString.
 */
#ifndef  RUBY3_RSTRING_H
#define  RUBY3_RSTRING_H
#include "ruby/3/core/rbasic.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/fl_type.h"
#include "ruby/3/value.h"
#include "ruby/backward/2/gcc_version_since.h"
#include "ruby/backward/2/r_cast.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#define RSTRING_NOEMBED RSTRING_NOEMBED
#define RSTRING_EMBED_LEN_MASK RSTRING_EMBED_LEN_MASK
#define RSTRING_EMBED_LEN_SHIFT RSTRING_EMBED_LEN_SHIFT
#define RSTRING_EMBED_LEN_MAX RSTRING_EMBED_LEN_MAX
#define RSTRING_FSTR RSTRING_FSTR
enum ruby_rstring_flags {
    RSTRING_NOEMBED = RUBY_FL_USER1,
    RSTRING_EMBED_LEN_MASK = (RUBY_FL_USER2|RUBY_FL_USER3|RUBY_FL_USER4|
                              RUBY_FL_USER5|RUBY_FL_USER6),
    RSTRING_EMBED_LEN_SHIFT = (RUBY_FL_USHIFT+2),
    RSTRING_EMBED_LEN_MAX = (int)((sizeof(VALUE)*RVALUE_EMBED_LEN_MAX)/sizeof(char)-1),
    RSTRING_FSTR = RUBY_FL_USER17,

    RSTRING_ENUM_END
};

struct RString {
    struct RBasic basic;
    union {
        struct {
            long len;
            char *ptr;
            union {
                long capa;
                VALUE shared;
            } aux;
        } heap;
        char ary[RSTRING_EMBED_LEN_MAX + 1];
    } as;
};
#define RSTRING_EMBED_LEN(str) \
     (long)((RBASIC(str)->flags >> RSTRING_EMBED_LEN_SHIFT) & \
            (RSTRING_EMBED_LEN_MASK >> RSTRING_EMBED_LEN_SHIFT))
#define RSTRING_LEN(str) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     RSTRING_EMBED_LEN(str) : \
     RSTRING(str)->as.heap.len)
#define RSTRING_PTR(str) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     RSTRING(str)->as.ary : \
     RSTRING(str)->as.heap.ptr)
#define RSTRING_END(str) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     (RSTRING(str)->as.ary + RSTRING_EMBED_LEN(str)) : \
     (RSTRING(str)->as.heap.ptr + RSTRING(str)->as.heap.len))
#define RSTRING_LENINT(str) rb_long2int(RSTRING_LEN(str))
#define RSTRING_GETMEM(str, ptrvar, lenvar) \
    (!(RBASIC(str)->flags & RSTRING_NOEMBED) ? \
     ((ptrvar) = RSTRING(str)->as.ary, (lenvar) = RSTRING_EMBED_LEN(str)) : \
     ((ptrvar) = RSTRING(str)->as.heap.ptr, (lenvar) = RSTRING(str)->as.heap.len))
#define RSTRING(obj) (R_CAST(RString)(obj))

VALUE rb_str_to_str(VALUE);
VALUE rb_string_value(volatile VALUE*);
char *rb_string_value_ptr(volatile VALUE*);
char *rb_string_value_cstr(volatile VALUE*);

#define StringValue(v) rb_string_value(&(v))
#define StringValuePtr(v) rb_string_value_ptr(&(v))
#define StringValueCStr(v) rb_string_value_cstr(&(v))

#define SafeStringValue(v) StringValue(v)
#if GCC_VERSION_SINCE(4,4,0)
void rb_check_safe_str(VALUE) __attribute__((error("rb_check_safe_str() and Check_SafeStr() are obsolete; use StringValue() instead")));
# define Check_SafeStr(v) rb_check_safe_str((VALUE)(v))
#else
# define rb_check_safe_str(x) [<"rb_check_safe_str() is obsolete; use StringValue() instead">]
# define Check_SafeStr(v) [<"Check_SafeStr() is obsolete; use StringValue() instead">]
#endif

VALUE rb_str_export(VALUE);
#define ExportStringValue(v) do {\
    StringValue(v);\
   (v) = rb_str_export(v);\
} while (0)
VALUE rb_str_export_locale(VALUE);

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_RSTRING_H */
