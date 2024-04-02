dnl -*- Autoconf -*-
AC_DEFUN([RUBY_SHARED_GC],[
AC_ARG_WITH(shared-gc,
    AS_HELP_STRING([--with-shared-gc],
    [Enable replacement of Ruby's GC from a shared library.]),
    [with_shared_gc=$withval], [unset with_shared_gc]
)

AC_SUBST([with_shared_gc])
AC_MSG_CHECKING([if Ruby is build with shared GC support])
AS_IF([test "$with_shared_gc" = "yes"], [
    AC_MSG_RESULT([yes])
    AC_DEFINE([USE_SHARED_GC], [1])
], [
    AC_MSG_RESULT([no])
    with_shared_gc="no"
    AC_DEFINE([USE_SHARED_GC], [0])
])
])dnl
