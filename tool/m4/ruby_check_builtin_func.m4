dnl -*- Autoconf -*-
AC_DEFUN([RUBY_CHECK_BUILTIN_FUNC], [dnl
AC_CACHE_CHECK([for $1], AS_TR_SH(rb_cv_builtin_$1),
  [AC_LINK_IFELSE(
    [AC_LANG_PROGRAM([int foo;], [$2;])],
    [AS_TR_SH(rb_cv_builtin_$1)=yes],
    [AS_TR_SH(rb_cv_builtin_$1)=no])])
AS_IF([test "${AS_TR_SH(rb_cv_builtin_$1)}" != no], [
  AC_DEFINE(AS_TR_CPP(HAVE_BUILTIN_$1))
])])dnl
