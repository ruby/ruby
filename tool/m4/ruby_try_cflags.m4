# -*- Autoconf -*-
AC_DEFUN([RUBY_TRY_CFLAGS], [
    AC_MSG_CHECKING([whether ]$1[ is accepted as CFLAGS])
    RUBY_WERROR_FLAG([
    CFLAGS="[$]CFLAGS $1"
    AC_TRY_COMPILE([$4], [$5],
	[$2
	AC_MSG_RESULT(yes)],
	[$3
	AC_MSG_RESULT(no)])
    ])
])dnl
