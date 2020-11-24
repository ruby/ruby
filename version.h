#ifndef RUBY_TOPLEVEL_VERSION_H                          /*-*-C-*-vi:se ft=c:*/
#define RUBY_TOPLEVEL_VERSION_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
# define RUBY_VERSION_MAJOR RUBY_API_VERSION_MAJOR
# define RUBY_VERSION_MINOR RUBY_API_VERSION_MINOR
#define RUBY_VERSION_TEENY 0
#define RUBY_RELEASE_DATE RUBY_RELEASE_YEAR_STR"-"RUBY_RELEASE_MONTH_STR"-"RUBY_RELEASE_DAY_STR
#define RUBY_PATCHLEVEL -1

#define RUBY_RELEASE_YEAR 2020
#define RUBY_RELEASE_MONTH 11
#define RUBY_RELEASE_DAY 25

#include "ruby/version.h"

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

#if !defined RUBY_LIB_VERSION && defined RUBY_LIB_VERSION_STYLE
# if RUBY_LIB_VERSION_STYLE == 3
#   define RUBY_LIB_VERSION STRINGIZE(RUBY_API_VERSION_MAJOR)"."STRINGIZE(RUBY_API_VERSION_MINOR)"."STRINGIZE(RUBY_API_VERSION_TEENY)
# elif RUBY_LIB_VERSION_STYLE == 2
#   define RUBY_LIB_VERSION STRINGIZE(RUBY_API_VERSION_MAJOR)"."STRINGIZE(RUBY_API_VERSION_MINOR)
# endif
#endif

#if RUBY_PATCHLEVEL == -1
#define RUBY_PATCHLEVEL_STR "dev"
#else
#define RUBY_PATCHLEVEL_STR "p"STRINGIZE(RUBY_PATCHLEVEL)
#endif

#ifndef RUBY_REVISION
# include "revision.h"
#endif

#ifdef RUBY_REVISION
# if RUBY_PATCHLEVEL == -1
#  ifndef RUBY_BRANCH_NAME
#   define RUBY_BRANCH_NAME "master"
#  endif
#  define RUBY_REVISION_STR " "RUBY_BRANCH_NAME" "RUBY_REVISION
# else
#  define RUBY_REVISION_STR " revision "RUBY_REVISION
# endif
#else
# define RUBY_REVISION "HEAD"
# define RUBY_REVISION_STR ""
#endif
#if !defined RUBY_RELEASE_DATETIME || RUBY_PATCHLEVEL != -1
# undef RUBY_RELEASE_DATETIME
# define RUBY_RELEASE_DATETIME RUBY_RELEASE_DATE
#endif

# define RUBY_DESCRIPTION_WITH(opt) \
    "ruby "RUBY_VERSION		    \
    RUBY_PATCHLEVEL_STR		    \
    " ("RUBY_RELEASE_DATETIME	    \
    RUBY_REVISION_STR")"opt" "	    \
    "["RUBY_PLATFORM"]"
# define RUBY_COPYRIGHT		    \
    "ruby - Copyright (C) "	    \
    RUBY_BIRTH_YEAR_STR"-"   \
    RUBY_RELEASE_YEAR_STR" " \
    RUBY_AUTHOR

#endif /* RUBY_TOPLEVEL_VERSION_H */
