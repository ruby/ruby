dnl -*- Autoconf -*-
AC_DEFUN([RUBY_PREPEND_OPTION],
	[# RUBY_PREPEND_OPTION($1)
	AS_CASE([" [$]{$1-} "],
	[*" $2 "*], [], ['  '], [ $1="$2"], [ $1="$2 [$]$1"])])dnl
