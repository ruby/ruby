/************************************************

  missing.h - prototype for *.c in ./missing, and
  	      for missing timeval struct

  $Author$
  $Date$
  created at: Sat May 11 23:46:03 JST 2002

************************************************/

#ifndef MISSING_H
#define MISSING_H

#include "config.h"
#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif

#if defined(HAVE_SYS_TIME_H)
#  include <sys/time.h>
#elif !defined(_WIN32)
#  define time_t long
struct timeval {
    time_t tv_sec;	/* seconds */
    time_t tv_usec;	/* microseconds */
};
#endif
#if defined(HAVE_SYS_TYPES_H)
#  include <sys/types.h>
#endif

#if !defined(HAVE_STRUCT_TIMEZONE)
struct timezone {
    int tz_minuteswest;
    int tz_dsttime;
};
#endif

#ifndef RUBY_EXTERN
#define RUBY_EXTERN extern
#endif

#ifndef HAVE_ACOSH
RUBY_EXTERN double acosh _((double));
RUBY_EXTERN double asinh _((double));
RUBY_EXTERN double atanh _((double));
#endif

#ifndef HAVE_CRYPT
RUBY_EXTERN char *crypt _((const char *, const char *));
#endif

#ifndef HAVE_DUP2
RUBY_EXTERN int dup2 _((int, int));
#endif

#ifndef HAVE_EACCESS
RUBY_EXTERN int eaccess _((const char*, int));
#endif

#ifndef HAVE_FINITE
RUBY_EXTERN int finite _((double));
#endif

#ifndef HAVE_FLOCK
RUBY_EXTERN int flock _((int, int));
#endif

/*
#ifndef HAVE_FREXP
RUBY_EXTERN double frexp _((double, int *));
#endif
*/

#ifndef HAVE_HYPOT
RUBY_EXTERN double hypot _((double, double));
#endif

#ifndef HAVE_ERF
RUBY_EXTERN double erf _((double));
RUBY_EXTERN double erfc _((double));
#endif

#ifndef HAVE_ISINF
# if defined(HAVE_FINITE) && defined(HAVE_ISNAN)
# define isinf(x) (!finite(x) && !isnan(x))
# else
RUBY_EXTERN int isinf _((double));
# endif
#endif

#ifndef HAVE_ISNAN
RUBY_EXTERN int isnan _((double));
#endif

/*
#ifndef HAVE_MEMCMP
RUBY_EXTERN int memcmp _((char *, char *, int));
#endif
*/

#ifndef HAVE_MEMMOVE
RUBY_EXTERN void *memmove _((void *, void *, int));
#endif

/*
#ifndef HAVE_MODF
RUBY_EXTERN double modf _((double, double *));
#endif
*/

#ifndef HAVE_STRCASECMP
RUBY_EXTERN int strcasecmp _((char *, char *));
#endif

#ifndef HAVE_STRNCASECMP
RUBY_EXTERN int strncasecmp _((char *, char *, int));
#endif

#ifndef HAVE_STRCHR
RUBY_EXTERN char *strchr _((char *, int));
RUBY_EXTERN char *strrchr _((char *, int));
#endif

#ifndef HAVE_STRERROR
RUBY_EXTERN char *strerror _((int));
#endif

#ifndef HAVE_STRFTIME
RUBY_EXTERN size_t strftime _((char *, size_t, const char *, const struct tm *));
#endif

#ifndef HAVE_STRSTR
RUBY_EXTERN char *strstr _((char *, char *));
#endif

/*
#ifndef HAVE_STRTOL
RUBY_EXTERN long strtol _((char *, char **, int));
#endif
*/

#ifndef HAVE_STRTOUL
RUBY_EXTERN unsigned long strtoul _((char *, char **, int));
#endif

#ifndef HAVE_VSNPRINTF
# ifdef HAVE_STDARG_PROTOTYPES
#  include <stdarg.h>
# else
#  include <varargs.h>
# endif
RUBY_EXTERN int snprintf __((char *, size_t n, char const *, ...));
RUBY_EXTERN int vsnprintf _((char *, size_t n, char const *, va_list));
#endif

#endif /* MISSING_H */
