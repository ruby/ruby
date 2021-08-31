dnl -*- Autoconf -*-
AC_DEFUN([RUBY_CHECK_SYSCONF], [dnl
AC_CACHE_CHECK([whether _SC_$1 is supported], rb_cv_have_sc_[]m4_tolower($1),
  [AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[#include <unistd.h>
      ]],
      [[_SC_$1 >= 0]])],
    rb_cv_have_sc_[]m4_tolower($1)=yes,
    rb_cv_have_sc_[]m4_tolower($1)=no)
  ])
AS_IF([test "$rb_cv_have_sc_[]m4_tolower($1)" = yes], [
  AC_DEFINE(HAVE__SC_$1)
])
])dnl
