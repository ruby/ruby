# -*- Autoconf -*-
dnl RUBY_REPLACE_FUNC [func] [included]
AC_DEFUN([RUBY_REPLACE_FUNC], [dnl
    AC_CHECK_DECL([$1],dnl
        [AC_DEFINE(AS_TR_CPP(HAVE_[$1]))],dnl
        [AC_REPLACE_FUNCS($1)],dnl
        [$2])dnl
])

dnl RUBY_REPLACE_FUNCS [funcs] [included]
AC_DEFUN([RUBY_REPLACE_FUNCS] [dnl
    m4_map_args_w([$1], [RUBY_REPLACE_FUNC(], [), [$2]])dnl
])
