dnl -*- Autoconf -*-
AC_DEFUN([RUBY_MODULAR_GC],[
AC_ARG_WITH(modular-gc,
    AS_HELP_STRING([--with-modular-gc=DIR],
    [Enable replacement of Ruby's GC from a modular library in the specified directory.]),
    [modular_gc_dir=$withval], [unset modular_gc_dir]
)

AS_IF([test "$modular_gc_dir" = yes], [
    AC_MSG_ERROR(you must specify a directory when using --with-modular-gc)
])

AC_MSG_CHECKING([if building with modular GC support])
AS_IF([test x"$modular_gc_dir" != x], [
    AC_MSG_RESULT([yes])

    # Ensure that modular_gc_dir is always an absolute path so that Ruby
    # never loads a modular GC from a relative path
    AS_CASE(["$modular_gc_dir"],
        [/*], [],
        [test "$load_relative" = yes || modular_gc_dir="$prefix/$modular_gc_dir"]
    )

    # Ensure that modular_gc_dir always terminates with a /
    AS_CASE(["$modular_gc_dir"],
        [*/], [],
        [modular_gc_dir="$modular_gc_dir/"]
    )

    AC_DEFINE([USE_MODULAR_GC], [1])

    modular_gc_summary="yes (in $modular_gc_dir)"
], [
    AC_MSG_RESULT([no])
    AC_DEFINE([USE_MODULAR_GC], [0])

    modular_gc_summary="no"
])

AC_SUBST(modular_gc_dir, "${modular_gc_dir}")
])dnl
