# -*- Autoconf -*-
AC_DEFUN([AC_MSG_RESULT], [dnl
{ _AS_ECHO_LOG([result: $1])
COLORIZE_RESULT([$1]); dnl
}])dnl
