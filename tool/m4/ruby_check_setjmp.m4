# -*- Autoconf -*-
# used for AC_ARG_WITH(setjmp-type)
AC_DEFUN([RUBY_CHECK_SETJMP], [
AC_CACHE_CHECK([for ]$1[ as a macro or function], ac_cv_func_$1,
  [AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[
@%:@include <setjmp.h>
]AC_INCLUDES_DEFAULT([$3])[
@%:@define JMPARGS_1 env
@%:@define JMPARGS_2 env,1
@%:@define JMPARGS JMPARGS_]m4_ifval($2,2,1)[
]],
    [m4_ifval($2,$2,jmp_buf)[ env; $1(JMPARGS);]])],
    ac_cv_func_$1=yes,
    ac_cv_func_$1=no)]
)
AS_IF([test "$ac_cv_func_]$1[" = yes], [AC_DEFINE([HAVE_]AS_TR_CPP($1), 1)])
])dnl
