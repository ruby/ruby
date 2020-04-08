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
 * @brief      Various attribute-related macros.
 *
 * ### Q&A ###
 *
 * - Q: Why  are the  macros defined  in this  header file  so inconsistent  in
 *      style?
 *
 * - A: Don't know.   Don't blame me.  Backward compatibility is  the key here.
 *      I'm just preserving what they have been.
 */
#ifndef  RUBY_BACKWARD2_ATTRIBUTES_H
#define  RUBY_BACKWARD2_ATTRIBUTES_H
#include "ruby/3/config.h"
#include "ruby/3/attr/alloc_size.h"
#include "ruby/3/attr/cold.h"
#include "ruby/3/attr/const.h"
#include "ruby/3/attr/deprecated.h"
#include "ruby/3/attr/error.h"
#include "ruby/3/attr/forceinline.h"
#include "ruby/3/attr/format.h"
#include "ruby/3/attr/maybe_unused.h"
#include "ruby/3/attr/noinline.h"
#include "ruby/3/attr/nonnull.h"
#include "ruby/3/attr/noreturn.h"
#include "ruby/3/attr/pure.h"
#include "ruby/3/attr/restrict.h"
#include "ruby/3/attr/returns_nonnull.h"
#include "ruby/3/attr/warning.h"
#include "ruby/3/has/attribute.h"

/* function attributes */
#undef CONSTFUNC
#define CONSTFUNC(x) RUBY3_ATTR_CONST() x

#undef PUREFUNC
#define PUREFUNC(x) RUBY3_ATTR_PURE() x

#undef DEPRECATED
#define DEPRECATED(x) RUBY3_ATTR_DEPRECATED(("")) x

#undef DEPRECATED_BY
#define DEPRECATED_BY(n,x) RUBY3_ATTR_DEPRECATED(("by: " # n)) x

#undef DEPRECATED_TYPE
#define DEPRECATED_TYPE(mseg, decl) decl RUBY3_ATTR_DEPRECATED(mseg)

#undef RUBY_CXX_DEPRECATED
#define RUBY_CXX_DEPRECATED(mseg) RUBY3_ATTR_DEPRECATED((mseg))

#undef NOINLINE
#define NOINLINE(x) RUBY3_ATTR_NOINLINE() x

#ifndef MJIT_HEADER
# undef ALWAYS_INLINE
# define ALWAYS_INLINE(x) RUBY3_ATTR_FORCEINLINE() x
#endif

#undef ERRORFUNC
#define ERRORFUNC(mesg, x) RUBY3_ATTR_ERROR(mesg) x
#if RUBY3_HAS_ATTRIBUTE(error)
# define HAVE_ATTRIBUTE_ERRORFUNC 1
#else
# define HAVE_ATTRIBUTE_ERRORFUNC 0
#endif

#undef WARNINGFUNC
#define WARNINGFUNC(mesg, x) RUBY3_ATTR_WARNING(mesg) x
#if RUBY3_HAS_ATTRIBUTE(warning)
# define HAVE_ATTRIBUTE_WARNINGFUNC 1
#else
# define HAVE_ATTRIBUTE_WARNINGFUNC 0
#endif

/*
  cold attribute for code layout improvements
  RUBY_FUNC_ATTRIBUTE not used because MSVC does not like nested func macros
 */
#undef COLDFUNC
#define COLDFUNC RUBY3_ATTR_COLD()

#define PRINTF_ARGS(decl, string_index, first_to_check) \
    RUBY3_ATTR_FORMAT(RUBY3_PRINTF_FORMAT, (string_index), (first_to_check)) \
    decl

#undef RUBY_ATTR_ALLOC_SIZE
#define RUBY_ATTR_ALLOC_SIZE RUBY3_ATTR_ALLOC_SIZE

#undef RUBY_ATTR_MALLOC
#define RUBY_ATTR_MALLOC RUBY3_ATTR_RESTRICT()

#undef RUBY_ATTR_RETURNS_NONNULL
#define RUBY_ATTR_RETURNS_NONNULL RUBY3_ATTR_RETURNS_NONNULL()

#ifndef FUNC_MINIMIZED
#define FUNC_MINIMIZED(x) x
#endif

#ifndef FUNC_UNOPTIMIZED
#define FUNC_UNOPTIMIZED(x) x
#endif

#ifndef RUBY_ALIAS_FUNCTION_TYPE
#define RUBY_ALIAS_FUNCTION_TYPE(type, prot, name, args) \
    FUNC_MINIMIZED(type prot) {return (type)name args;}
#endif

#ifndef RUBY_ALIAS_FUNCTION_VOID
#define RUBY_ALIAS_FUNCTION_VOID(prot, name, args) \
    FUNC_MINIMIZED(void prot) {name args;}
#endif

#ifndef RUBY_ALIAS_FUNCTION
#define RUBY_ALIAS_FUNCTION(prot, name, args) \
    RUBY_ALIAS_FUNCTION_TYPE(VALUE, prot, name, args)
#endif

#undef RUBY_FUNC_NONNULL
#define RUBY_FUNC_NONNULL(n, x) RUBY3_ATTR_NONNULL(n) x

#undef  NORETURN
#define NORETURN(x) RUBY3_ATTR_NORETURN() x
#define NORETURN_STYLE_NEW

#ifndef PACKED_STRUCT
# define PACKED_STRUCT(x) x
#endif

#ifndef PACKED_STRUCT_UNALIGNED
# if UNALIGNED_WORD_ACCESS
#   define PACKED_STRUCT_UNALIGNED(x) PACKED_STRUCT(x)
# else
#   define PACKED_STRUCT_UNALIGNED(x) x
# endif
#endif

#undef RB_UNUSED_VAR
#define RB_UNUSED_VAR(x) x RUBY3_ATTR_MAYBE_UNUSED()

#endif /* RUBY_BACKWARD2_ATTRIBUTES_H */
