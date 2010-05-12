/************************************************

  missing.h - prototype for *.c in ./missing, and
  	      for missing timeval struct

  $Author$
  created at: Sat May 11 23:46:03 JST 2002

************************************************/

#ifndef RUBY_MISSING_H
#define RUBY_MISSING_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#if defined(HAVE_SYS_TIME_H)
#  include <sys/time.h>
#elif !defined(_WIN32)
#  define time_t long
struct timeval {
    time_t tv_sec;	/* seconds */
    long tv_usec;	/* microseconds */
};
#endif
#if defined(HAVE_SYS_TYPES_H)
#  include <sys/types.h>
#endif

#if !defined(HAVE_STRUCT_TIMESPEC)
struct timespec {
    time_t tv_sec;	/* seconds */
    long tv_nsec;	/* nanoseconds */
};
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
RUBY_EXTERN double acosh(double);
RUBY_EXTERN double asinh(double);
RUBY_EXTERN double atanh(double);
#endif

#ifndef HAVE_CRYPT
RUBY_EXTERN char *crypt(const char *, const char *);
#endif

#ifndef HAVE_DUP2
RUBY_EXTERN int dup2(int, int);
#endif

#ifndef HAVE_EACCESS
RUBY_EXTERN int eaccess(const char*, int);
#endif

#ifndef HAVE_FINITE
RUBY_EXTERN int finite(double);
#endif

#ifndef HAVE_FLOCK
RUBY_EXTERN int flock(int, int);
#endif

/*
#ifndef HAVE_FREXP
RUBY_EXTERN double frexp(double, int *);
#endif
*/

#ifndef HAVE_HYPOT
RUBY_EXTERN double hypot(double, double);
#endif

#ifndef HAVE_ERF
RUBY_EXTERN double erf(double);
RUBY_EXTERN double erfc(double);
#endif

#ifndef HAVE_TGAMMA
RUBY_EXTERN double tgamma(double);
#endif

#ifndef HAVE_LGAMMA_R
RUBY_EXTERN double lgamma_r(double, int *);
#endif

#ifndef HAVE_CBRT
RUBY_EXTERN double cbrt(double);
#endif

#ifndef isinf
# ifndef HAVE_ISINF
#  if defined(HAVE_FINITE) && defined(HAVE_ISNAN)
#  define isinf(x) (!finite(x) && !isnan(x))
#  else
RUBY_EXTERN int isinf(double);
#  endif
# endif
#endif

#ifndef HAVE_ISNAN
RUBY_EXTERN int isnan(double);
#endif

/*
#ifndef HAVE_MEMCMP
RUBY_EXTERN int memcmp(const void *, const void *, size_t);
#endif
*/

#ifndef HAVE_MEMMOVE
RUBY_EXTERN void *memmove(void *, const void *, size_t);
#endif

/*
#ifndef HAVE_MODF
RUBY_EXTERN double modf(double, double *);
#endif
*/

#ifndef HAVE_STRCHR
RUBY_EXTERN char *strchr(const char *, int);
RUBY_EXTERN char *strrchr(const char *, int);
#endif

#ifndef HAVE_STRERROR
RUBY_EXTERN char *strerror(int);
#endif

#ifndef HAVE_STRSTR
RUBY_EXTERN char *strstr(const char *, const char *);
#endif

/*
#ifndef HAVE_STRTOL
RUBY_EXTERN long strtol(const char *, char **, int);
#endif
*/

#ifndef HAVE_STRLCPY
RUBY_EXTERN size_t strlcpy(char *, const char*, size_t);
#endif

#ifndef HAVE_STRLCAT
RUBY_EXTERN size_t strlcat(char *, const char*, size_t);
#endif

#ifndef HAVE_FFS
RUBY_EXTERN int ffs(int);
#endif

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_MISSING_H */
