dnl -*- Autoconf -*-
AC_DEFUN([COLORIZE_RESULT], [AC_REQUIRE([_COLORIZE_RESULT_PREPARE])dnl
    AS_LITERAL_IF([$1],
	[m4_case([$1],
		[yes], [_AS_ECHO([${msg_result_yes}$1${msg_reset}])],
		[no], [_AS_ECHO([${msg_result_no}$1${msg_reset}])],
		[_AS_ECHO([${msg_result_other}$1${msg_reset}])])],
	[colorize_result "$1"]) dnl
])dnl
