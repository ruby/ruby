#ifndef RUBY_TOPLEVEL_VERSION_H                          /*-*-C-*-vi:se ft=c:*/
#define RUBY_TOPLEVEL_VERSION_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
# define RUBY_VERSION_MAJOR RUBY_API_VERSION_MAJOR
# define RUBY_VERSION_MINOR RUBY_API_VERSION_MINOR
#define RUBY_VERSION_TEENY 1
#define RUBY_RELEASE_DATE RUBY_RELEASE_YEAR_STR"-"RUBY_RELEASE_MONTH_STR"-"RUBY_RELEASE_DAY_STR
#define RUBY_PATCHLEVEL 59

#include "ruby/version.h"
#include "ruby/internal/abi.h"

#ifndef RUBY_REVISION
#include "revision.h"

#ifndef TOKEN_PASTE
#define TOKEN_PASTE(x,y) x##y
#endif
#define ONLY_ONE_DIGIT(x) TOKEN_PASTE(10,x) < 1000
#define WITH_ZERO_PADDING(x) TOKEN_PASTE(0,x)
#define RUBY_BIRTH_YEAR_STR STRINGIZE(RUBY_BIRTH_YEAR)
#define RUBY_RELEASE_YEAR_STR STRINGIZE(RUBY_RELEASE_YEAR)
#if ONLY_ONE_DIGIT(RUBY_RELEASE_MONTH)
#define RUBY_RELEASE_MONTH_STR STRINGIZE(WITH_ZERO_PADDING(RUBY_RELEASE_MONTH))
#else
#define RUBY_RELEASE_MONTH_STR STRINGIZE(RUBY_RELEASE_MONTH)
#endif
#if ONLY_ONE_DIGIT(RUBY_RELEASE_DAY)
#define RUBY_RELEASE_DAY_STR STRINGIZE(WITH_ZERO_PADDING(RUBY_RELEASE_DAY))
#else
#define RUBY_RELEASE_DAY_STR STRINGIZE(RUBY_RELEASE_DAY)
#endif

#endif

#ifdef RUBY_ABI_VERSION
# define RUBY_ABI_VERSION_SUFFIX "+"STRINGIZE(RUBY_ABI_VERSION)
#else
# define RUBY_ABI_VERSION_SUFFIX ""
#endif
#if !defined RUBY_LIB_VERSION && defined RUBY_LIB_VERSION_STYLE
# if RUBY_LIB_VERSION_STYLE == 3
#   define RUBY_LIB_VERSION STRINGIZE(RUBY_API_VERSION_MAJOR)"."STRINGIZE(RUBY_API_VERSION_MINOR) \
        "."STRINGIZE(RUBY_API_VERSION_TEENY) RUBY_ABI_VERSION_SUFFIX
# elif RUBY_LIB_VERSION_STYLE == 2
#   define RUBY_LIB_VERSION STRINGIZE(RUBY_API_VERSION_MAJOR)"."STRINGIZE(RUBY_API_VERSION_MINOR) \
        RUBY_ABI_VERSION_SUFFIX
# endif
#endif

#if RUBY_PATCHLEVEL == -1
# ifdef RUBY_PATCHLEVEL_NAME
#  define RUBY_PATCHLEVEL_STR STRINGIZE(RUBY_PATCHLEVEL_NAME)
# else
#  define RUBY_PATCHLEVEL_STR "dev"
# endif
#elif defined RUBY_ABI_VERSION
# error RUBY_ABI_VERSION is defined in non-development branch
#else
# define RUBY_PATCHLEVEL_STR ""
#endif

#endif /* RUBY_TOPLEVEL_VERSION_H */
