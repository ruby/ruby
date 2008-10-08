#define RUBY_VERSION "1.9.0"
#define RUBY_RELEASE_DATE "2008-10-09"
#define RUBY_VERSION_CODE 190
#define RUBY_RELEASE_CODE 20081009
#define RUBY_PATCHLEVEL 0

#define RUBY_VERSION_MAJOR 1
#define RUBY_VERSION_MINOR 9
#define RUBY_VERSION_TEENY 0
#define RUBY_RELEASE_YEAR 2008
#define RUBY_RELEASE_MONTH 10
#define RUBY_RELEASE_DAY 9

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

#ifndef RUBY_REVISION
#include "revision.h"
#endif
#ifndef RUBY_REVISION
#define RUBY_REVISION 0
#endif

#if RUBY_VERSION_TEENY > 0 && RUBY_PATCHLEVEL < 5000 && !RUBY_REVISION
#define RUBY_RELEASE_STR "patchlevel"
#define RUBY_RELEASE_NUM RUBY_PATCHLEVEL
#else
#ifdef RUBY_BRANCH_NAME
#define RUBY_RELEASE_STR RUBY_BRANCH_NAME
#else
#define RUBY_RELEASE_STR "revision"
#endif
#define RUBY_RELEASE_NUM RUBY_REVISION
#endif

# define RUBY_DESCRIPTION	    \
    "ruby "RUBY_VERSION		    \
    " ("RUBY_RELEASE_DATE" "	    \
    RUBY_RELEASE_STR" "		    \
    STRINGIZE(RUBY_RELEASE_NUM)") " \
    "["RUBY_PLATFORM"]"
# define RUBY_COPYRIGHT 	    \
    "ruby - Copyright (C) "	    \
    STRINGIZE(RUBY_BIRTH_YEAR)"-"   \
    STRINGIZE(RUBY_RELEASE_YEAR)" " \
    RUBY_AUTHOR
