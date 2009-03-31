#define RUBY_VERSION "1.9.2"
#define RUBY_RELEASE_DATE "2009-04-01"
#define RUBY_PATCHLEVEL -1
#define RUBY_BRANCH_NAME "trunk"

#define RUBY_VERSION_MAJOR 1
#define RUBY_VERSION_MINOR 9
#define RUBY_VERSION_TEENY 1
#define RUBY_RELEASE_YEAR 2009
#define RUBY_RELEASE_MONTH 4
#define RUBY_RELEASE_DAY 1

#ifdef RUBY_EXTERN
RUBY_EXTERN const char ruby_version[];
RUBY_EXTERN const char ruby_release_date[];
RUBY_EXTERN const char ruby_platform[];
RUBY_EXTERN const int ruby_patchlevel;
RUBY_EXTERN const char ruby_description[];
RUBY_EXTERN const char ruby_copyright[];
#endif

#define RUBY_AUTHOR "Yukihiro Matsumoto"
#define RUBY_BIRTH_YEAR 1993
#define RUBY_BIRTH_MONTH 2
#define RUBY_BIRTH_DAY 24

#if !defined RUBY_LIB_VERSION && defined RUBY_LIB_VERSION_STYLE
# if RUBY_LIB_VERSION_STYLE == 3
#   define RUBY_LIB_VERSION STRINGIZE(RUBY_VERSION_MAJOR)"."STRINGIZE(RUBY_VERSION_MINOR)"."STRINGIZE(RUBY_VERSION_TEENY)
# elif RUBY_LIB_VERSION_STYLE == 2
#   define RUBY_LIB_VERSION STRINGIZE(RUBY_VERSION_MAJOR)"."STRINGIZE(RUBY_VERSION_MINOR)
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
# ifndef RUBY_REVISION
# define RUBY_REVISION 0
#endif

#if RUBY_REVISION
# ifdef RUBY_BRANCH_NAME
#  define RUBY_REVISION_STR " "RUBY_BRANCH_NAME" "STRINGIZE(RUBY_REVISION)
# else
#  define RUBY_REVISION_STR " revision "STRINGIZE(RUBY_REVISION)
# endif
#else
# define RUBY_REVISION_STR ""
#endif

# define RUBY_DESCRIPTION	    \
    "ruby "RUBY_VERSION		    \
    RUBY_PATCHLEVEL_STR             \
    " ("RUBY_RELEASE_DATE	    \
    RUBY_REVISION_STR") "	    \
    "["RUBY_PLATFORM"]"
# define RUBY_COPYRIGHT 	    \
    "ruby - Copyright (C) "	    \
    STRINGIZE(RUBY_BIRTH_YEAR)"-"   \
    STRINGIZE(RUBY_RELEASE_YEAR)" " \
    RUBY_AUTHOR
