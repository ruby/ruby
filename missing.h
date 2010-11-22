/************************************************

  missing.h - prototype for *.c in ./missing, and
  	      for missing timeval struct

  $Author$
  $Date$
  created at: Sat May 11 23:46:03 JST 2002

************************************************/

#ifndef MISSING_H
#define MISSING_H

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

#ifndef HAVE_ACOSH
extern double acosh _((double));
extern double asinh _((double));
extern double atanh _((double));
#endif

#ifndef HAVE_CRYPT
extern char *crypt _((const char *, const char *));
#endif

#ifndef HAVE_DUP2
extern int dup2 _((int, int));
#endif

#ifndef HAVE_EACCESS
extern int eaccess _((const char*, int));
#endif

#ifndef HAVE_FINITE
extern int finite _((double));
#endif

#ifndef HAVE_FLOCK
extern int flock _((int, int));
#endif

/*
#ifndef HAVE_FREXP
extern double frexp _((double, int *));
#endif
*/

#ifndef HAVE_HYPOT
extern double hypot _((double, double));
#endif

#ifndef HAVE_ERF
extern double erf _((double));
extern double erfc _((double));
#endif

#ifndef HAVE_ISINF
# if defined(HAVE_FINITE) && defined(HAVE_ISNAN)
# define isinf(x) (!finite(x) && !isnan(x))
# else
extern int isinf _((double));
# endif
#endif

#ifndef HAVE_ISNAN
extern int isnan _((double));
#endif

/*
#ifndef HAVE_MEMCMP
extern int memcmp _((char *, char *, int));
#endif
*/

#ifndef HAVE_MEMMOVE
extern void *memmove _((void *, void *, int));
#endif

/*
#ifndef HAVE_MODF
extern double modf _((double, double *));
#endif
*/

#ifndef HAVE_STRCASECMP
extern int strcasecmp _((char *, char *));
#endif

#ifndef HAVE_STRNCASECMP
extern int strncasecmp _((char *, char *, int));
#endif

#ifndef HAVE_STRCHR
extern char *strchr _((char *, int));
extern char *strrchr _((char *, int));
#endif

#ifndef HAVE_STRERROR
extern char *strerror _((int));
#endif

#ifndef HAVE_STRFTIME
extern size_t strftime _((char *, size_t, const char *, const struct tm *));
#endif

#ifndef HAVE_STRSTR
extern char *strstr _((char *, char *));
#endif

/*
#ifndef HAVE_STRTOL
extern long strtol _((char *, char **, int));
#endif
*/

#ifndef HAVE_STRTOUL
extern unsigned long strtoul _((char *, char **, int));
#endif

#ifndef HAVE_VSNPRINTF
# ifdef HAVE_STDARG_PROTOTYPES
#  include <stdarg.h>
# else
#  include <varargs.h>
# endif
extern int snprintf __((char *, size_t n, char const *, ...));
extern int vsnprintf _((char *, size_t n, char const *, va_list));
#endif

#endif /* MISSING_H */
