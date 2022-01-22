dnl -*- Autoconf -*-
dnl
dnl Autoconf 2.67 fails to detect `-Werror=old-style-definition` due
dnl to the old style definition of `main`.
m4_version_prereq([2.70], [], [
m4_defun([AC_LANG_PROGRAM(C)], m4_bpatsubst(m4_defn([AC_LANG_PROGRAM(C)]), [main ()], [main (void)]))
])dnl
dnl
AC_DEFUN([RUBY_TRY_CFLAGS], [
    AC_MSG_CHECKING([whether ]$1[ is accepted as CFLAGS])
    RUBY_WERROR_FLAG([
    CFLAGS="[$]CFLAGS $1"
    AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[$4]], [[$5]])],
	[$2
	AC_MSG_RESULT(yes)],
	[$3
	AC_MSG_RESULT(no)])
    ])
])dnl
