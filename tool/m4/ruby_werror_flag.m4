dnl -*- Autoconf -*-
AC_DEFUN([RUBY_WERROR_FLAG], [dnl
save_CFLAGS="$CFLAGS"
CFLAGS="$CFLAGS $rb_cv_warnflags"
AS_IF([test "${ac_c_werror_flag+set}"], [
  rb_c_werror_flag="$ac_c_werror_flag"
], [
  unset rb_c_werror_flag
])
ac_c_werror_flag=yes
$1
CFLAGS="$save_CFLAGS"
save_CFLAGS=
AS_IF([test "${rb_c_werror_flag+set}"], [
  ac_c_werror_flag="$rb_c_werror_flag"
], [
  unset ac_c_werror_flag
])])dnl
