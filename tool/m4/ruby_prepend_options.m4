# -*- Autoconf -*-
AC_DEFUN([RUBY_PREPEND_OPTIONS],
	[# RUBY_PREPEND_OPTIONS($1)
	unset rb_opts; for rb_opt in $2; do
	AS_CASE([" [$]{rb_opts} [$]{$1-} "],
	[*" [$]{rb_opt} "*], [], ['  '], [ $1="[$]{rb_opt}"], [ rb_opts="[$]{rb_opts}[$]{rb_opt} "])
	done
	$1="[$]{rb_opts}[$]$1"])dnl
