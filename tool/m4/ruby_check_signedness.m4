dnl -*- Autoconf -*-
dnl RUBY_CHECK_SIGNEDNESS [typename] [if-signed] [if-unsigned] [included]
AC_DEFUN([RUBY_CHECK_SIGNEDNESS], [dnl
    AC_COMPILE_IFELSE([AC_LANG_BOOL_COMPILE_TRY([AC_INCLUDES_DEFAULT([$4])], [($1)-1 > 0])],
		      [$3], [$2])])dnl
