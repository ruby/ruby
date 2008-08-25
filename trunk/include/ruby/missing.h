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

#ifndef HAVE_ACOSH
extern double acosh(double);
extern double asinh(double);
extern double atanh(double);
#endif

#ifndef HAVE_CRYPT
extern char *crypt(const char *, const char *);
#endif

#ifndef HAVE_DUP2
extern int dup2(int, int);
#endif

#ifndef HAVE_EACCESS
extern int eaccess(const char*, int);
#endif

#ifndef HAVE_FINITE
extern int finite(double);
#endif

#ifndef HAVE_FLOCK
extern int flock(int, int);
#endif

/*
#ifndef HAVE_FREXP
extern double frexp(double, int *);
#endif
*/

#ifndef HAVE_HYPOT
extern double hypot(double, double);
#endif

#ifndef HAVE_ERF
extern double erf(double);
extern double erfc(double);
#endif

#ifndef HAVE_TGAMMA
extern double tgamma(double);
#endif

#ifndef HAVE_LGAMMA_R
extern double lgamma_r(double, int *);
#endif

#ifndef HAVE_CBRT
extern double cbrt(double);
#endif

#ifndef isinf
# ifndef HAVE_ISINF
#  if defined(HAVE_FINITE) && defined(HAVE_ISNAN)
#  define isinf(x) (!finite(x) && !isnan(x))
#  else
extern int isinf(double);
#  endif
# endif
#endif

#ifndef HAVE_ISNAN
extern int isnan(double);
#endif

/*
#ifndef HAVE_MEMCMP
extern int memcmp(const void *, const void *, size_t);
#endif
*/

#ifndef HAVE_MEMMOVE
extern void *memmove(void *, const void *, size_t);
#endif

/*
#ifndef HAVE_MODF
extern double modf(double, double *);
#endif
*/

#ifndef HAVE_STRCHR
extern char *strchr(const char *, int);
extern char *strrchr(const char *, int);
#endif

#ifndef HAVE_STRERROR
extern char *strerror(int);
#endif

#ifndef HAVE_STRSTR
extern char *strstr(const char *, const char *);
#endif

/*
#ifndef HAVE_STRTOL
extern long strtol(const char *, char **, int);
#endif
*/

#ifndef HAVE_VSNPRINTF
# include <stdarg.h>
extern int snprintf(char *, size_t n, char const *, ...);
extern int vsnprintf(char *, size_t n, char const *, va_list);
#endif

#ifndef HAVE_STRLCPY
extern size_t strlcpy(char *, const char*, size_t);
#endif

#ifndef HAVE_STRLCAT
extern size_t strlcat(char *, const char*, size_t);
#endif

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_MISSING_H */
