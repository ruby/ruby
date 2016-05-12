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

#include "ruby/config.h"
#include <stddef.h>
#include <math.h> /* for INFINITY and NAN */
#ifdef RUBY_ALTERNATIVE_MALLOC_HEADER
# include RUBY_ALTERNATIVE_MALLOC_HEADER
#endif
#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif

#if !defined(HAVE_STRUCT_TIMEVAL) || !defined(HAVE_STRUCT_TIMESPEC)
#if defined(HAVE_TIME_H)
# include <time.h>
#endif
#if defined(HAVE_SYS_TIME_H)
# include <sys/time.h>
#endif
#endif

#ifndef M_PI
# define M_PI 3.14159265358979323846
#endif
#ifndef M_PI_2
# define M_PI_2 (M_PI/2)
#endif

#ifndef RUBY_SYMBOL_EXPORT_BEGIN
# define RUBY_SYMBOL_EXPORT_BEGIN /* begin */
# define RUBY_SYMBOL_EXPORT_END   /* end */
#endif

#if !defined(HAVE_STRUCT_TIMEVAL)
struct timeval {
    time_t tv_sec;	/* seconds */
    long tv_usec;	/* microseconds */
};
#endif /* HAVE_STRUCT_TIMEVAL */

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

#ifdef RUBY_EXPORT
#undef RUBY_EXTERN
#endif
#ifndef RUBY_EXTERN
#define RUBY_EXTERN extern
#endif

RUBY_SYMBOL_EXPORT_BEGIN

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

#ifndef HAVE_ROUND
RUBY_EXTERN double round(double);	/* numeric.c */
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

#if !defined(HAVE_INFINITY) || !defined(HAVE_NAN)
union bytesequence4_or_float {
  unsigned char bytesequence[4];
  float float_value;
};
#endif

#ifndef INFINITY
/** @internal */
RUBY_EXTERN const union bytesequence4_or_float rb_infinity;
# define INFINITY (rb_infinity.float_value)
#endif

#ifndef NAN
/** @internal */
RUBY_EXTERN const union bytesequence4_or_float rb_nan;
# define NAN (rb_nan.float_value)
#endif

#ifndef isinf
# ifndef HAVE_ISINF
#  if defined(HAVE_FINITE) && defined(HAVE_ISNAN)
#    ifdef HAVE_IEEEFP_H
#    include <ieeefp.h>
#    endif
#  define isinf(x) (!finite(x) && !isnan(x))
#  else
RUBY_EXTERN int isinf(double);
#  endif
# endif
#endif

#ifndef isnan
# ifndef HAVE_ISNAN
RUBY_EXTERN int isnan(double);
# endif
#endif

#ifndef HAVE_NEXTAFTER
RUBY_EXTERN double nextafter(double x, double y);
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

#ifndef HAVE_SIGNBIT
RUBY_EXTERN int signbit(double x);
#endif

#ifndef HAVE_FFS
RUBY_EXTERN int ffs(int);
#endif

#ifdef BROKEN_CLOSE
#include <sys/types.h>
#include <sys/socket.h>
RUBY_EXTERN int ruby_getpeername(int, struct sockaddr *, socklen_t *);
RUBY_EXTERN int ruby_getsockname(int, struct sockaddr *, socklen_t *);
RUBY_EXTERN int ruby_shutdown(int, int);
RUBY_EXTERN int ruby_close(int);
#endif

#ifndef HAVE_SETPROCTITLE
RUBY_EXTERN void setproctitle(const char *fmt, ...);
#endif

#ifndef HAVE_EXPLICIT_BZERO
RUBY_EXTERN void explicit_bzero(void *b, size_t len);
# if defined SecureZeroMemory
#   define explicit_bzero(b, len) SecureZeroMemory(b, len)
# endif
#endif

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_MISSING_H */
