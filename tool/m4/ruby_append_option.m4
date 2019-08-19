# -*- Autoconf -*-
AC_DEFUN([RUBY_APPEND_OPTION],
	[# RUBY_APPEND_OPTION($1)
	AS_CASE([" [$]{$1-} "],
	[*" $2 "*], [], ['  '], [ $1="$2"], [ $1="[$]$1 $2"])])dnl
