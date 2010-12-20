#define RUBY_VERSION "1.8.8"
#define RUBY_RELEASE_DATE "2010-12-21"
#define RUBY_VERSION_CODE 188
#define RUBY_RELEASE_CODE 20101221
#define RUBY_PATCHLEVEL -1

#define RUBY_VERSION_MAJOR 1
#define RUBY_VERSION_MINOR 8
#define RUBY_VERSION_TEENY 8
#define RUBY_RELEASE_YEAR 2010
#define RUBY_RELEASE_MONTH 12
#define RUBY_RELEASE_DAY 21

#define NO_STRING_LITERAL_CONCATENATION 1
#ifdef RUBY_EXTERN
RUBY_EXTERN const char ruby_version[];
RUBY_EXTERN const char ruby_release_date[];
RUBY_EXTERN const char ruby_platform[];
RUBY_EXTERN const int ruby_patchlevel;
#if !defined(RUBY_VERSION_C) || !defined(NO_STRING_LITERAL_CONCATENATION)
RUBY_EXTERN const char ruby_description[];
RUBY_EXTERN const char ruby_copyright[];
#endif
#endif

#define RUBY_AUTHOR "Yukihiro Matsumoto"
#define RUBY_BIRTH_YEAR 1993
#define RUBY_BIRTH_MONTH 2
#define RUBY_BIRTH_DAY 24

#ifndef RUBY_REVISION
#include "revision.h"
#endif
#ifndef RUBY_REVISION
#define RUBY_REVISION 0
#endif

#if RUBY_PATCHLEVEL == -1
#define RUBY_PATCHLEVEL_STR "dev"
#else
#define RUBY_PATCHLEVEL_STR "p"STRINGIZE(RUBY_PATCHLEVEL)
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

#ifndef NO_STRING_LITERAL_CONCATENATION
#ifndef RUBY_DESCRIPTION
# define RUBY_DESCRIPTION	    \
    "ruby "RUBY_VERSION		    \
    RUBY_PATCHLEVEL_STR             \
    " ("RUBY_RELEASE_DATE	    \
    RUBY_REVISION_STR") "	    \
    "["RUBY_PLATFORM"]"
#endif
#ifndef RUBY_COPYRIGHT
# define RUBY_COPYRIGHT 	    \
    "ruby - Copyright (C) "	    \
    STRINGIZE(RUBY_BIRTH_YEAR)"-"   \
    STRINGIZE(RUBY_RELEASE_YEAR)" " \
    RUBY_AUTHOR
#endif
#endif
