dnl -*- Autoconf -*-
AC_DEFUN([RUBY_APPEND_OPTIONS],
	[# RUBY_APPEND_OPTIONS($1)
	for rb_opt in $2; do
	AS_CASE([" [$]{$1-} "],
	[*" [$]{rb_opt} "*], [], ['  '], [ $1="[$]{rb_opt}"], [ $1="[$]$1 [$]{rb_opt}"])
	done])dnl
