# -*- Autoconf -*-
AC_DEFUN([COLORIZE_RESULT], [AC_REQUIRE([_COLORIZE_RESULT_PREPARE])dnl
    AS_LITERAL_IF([$1],
	[m4_case([$1],
		[yes], [AS_ECHO(["${msg_result_yes}$1${msg_reset}"])],
		[no], [AS_ECHO(["${msg_result_no}$1${msg_reset}"])],
		[AS_ECHO(["${msg_result_other}$1${msg_reset}"])])],
	[colorize_result "$1"]) dnl
])dnl
