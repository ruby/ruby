dnl -*- Autoconf -*-
AC_DEFUN([RUBY_SHARED_GC],[
AC_ARG_WITH(shared-gc,
    AS_HELP_STRING([--with-shared-gc=DIR],
    [Enable replacement of Ruby's GC from a shared library in the specified directory.]),
    [shared_gc_dir=$withval], [unset shared_gc_dir]
)

AC_MSG_CHECKING([if building with shared GC support])
AS_IF([test x"$shared_gc_dir" != x], [
    AC_MSG_RESULT([yes])

    # Ensure that shared_gc_dir is always an absolute path so that Ruby
    # never loads a shared GC from a relative path
    AS_CASE(["$shared_gc_dir"],
        [/*], [shared_gc_dir=$shared_gc_dir],
        [shared_gc_dir=`pwd`/$shared_gc_dir]
    )

    # Ensure that shared_gc_dir always terminates with a /
    AS_CASE(["$shared_gc_dir"],
        [*/], [],
        [shared_gc_dir="$shared_gc_dir/"]
    )

    AC_DEFINE([USE_SHARED_GC], [1])
    AC_DEFINE_UNQUOTED([SHARED_GC_DIR], "$shared_gc_dir")

    shared_gc_summary="yes (in $shared_gc_dir)"
], [
    AC_MSG_RESULT([no])
    AC_DEFINE([USE_SHARED_GC], [0])

    shared_gc_summary="no"
])

AC_SUBST(shared_gc_dir, "${shared_gc_dir}")
])dnl
