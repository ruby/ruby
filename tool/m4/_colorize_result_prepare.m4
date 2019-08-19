AC_DEFUN([_COLORIZE_RESULT_PREPARE], [
    msg_checking= msg_result_yes= msg_result_no= msg_result_other= msg_reset=
    AS_IF([test "x${CONFIGURE_TTY}" = xyes -o -t 1], [
	msg_begin="`tput smso 2>/dev/null`"
	AS_CASE(["$msg_begin"], ['@<:@'*m],
	    [msg_begin="`echo "$msg_begin" | sed ['s/[0-9]*m$//']`"
	    msg_checking="${msg_begin}33m"
	    AS_IF([test ${TEST_COLORS:+set}], [
		msg_result_yes=[`expr ":$TEST_COLORS:" : ".*:pass=\([^:]*\):"`]
		msg_result_no=[`expr ":$TEST_COLORS:" : ".*:fail=\([^:]*\):"`]
		msg_result_other=[`expr ":$TEST_COLORS:" : ".*:skip=\([^:]*\):"`]
	    ])
	    msg_result_yes="${msg_begin}${msg_result_yes:-32;1}m"
	    msg_result_no="${msg_begin}${msg_result_no:-31;1}m"
	    msg_result_other="${msg_begin}${msg_result_other:-33;1}m"
	    msg_reset="${msg_begin}m"
	    ])
	AS_UNSET(msg_begin)
	])
    AS_REQUIRE_SHELL_FN([colorize_result],
	[AS_FUNCTION_DESCRIBE([colorize_result], [MSG], [Colorize result])],
        [AS_CASE(["$[]1"],
            [yes], [AS_ECHO(["${msg_result_yes}$[]1${msg_reset}]")],
            [no], [AS_ECHO(["${msg_result_no}$[]1${msg_reset}]")],
            [AS_ECHO(["${msg_result_other}$[]1${msg_reset}]")])])
])dnl
