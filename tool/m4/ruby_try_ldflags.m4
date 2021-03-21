# -*- Autoconf -*-
AC_DEFUN([RUBY_TRY_LDFLAGS], [
    save_LDFLAGS="$LDFLAGS"
    LDFLAGS="[$]LDFLAGS $1"
    AC_MSG_CHECKING([whether $1 is accepted as LDFLAGS])
    RUBY_WERROR_FLAG([
    AC_TRY_LINK([$4], [$5],
	[$2
	AC_MSG_RESULT(yes)],
	[$3
	AC_MSG_RESULT(no)])
    ])
    LDFLAGS="$save_LDFLAGS"
    save_LDFLAGS=
])dnl
