dnl -*- Autoconf -*-
dnl RUBY_REQUIRE_FUNC [func] [included]
AC_DEFUN([RUBY_REQUIRE_FUNC], [
# RUBY_REQUIRE_FUNC([$1], [$2])
    AC_CHECK_FUNCS([$1])
    AS_IF([test "$ac_cv_func_[]AS_TR_SH($1)" = yes], [],
          [AC_MSG_ERROR($1[() must be supported])])
])dnl
dnl
dnl RUBY_REQUIRE_FUNCS [funcs] [included]
AC_DEFUN([RUBY_REQUIRE_FUNCS], [dnl
    m4_map_args_w([$1], [RUBY_REQUIRE_FUNC(], [, [$2])])dnl
])dnl
