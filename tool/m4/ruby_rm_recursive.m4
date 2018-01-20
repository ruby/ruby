# -*- Autoconf -*-
AC_DEFUN([RUBY_RM_RECURSIVE], [
m4_version_prereq([2.70], [-1], [
# suppress error messages, rm: cannot remove 'conftest.dSYM', from
# AC_EGREP_CPP with CFLAGS=-g on Darwin.
AS_CASE([$build_os], [darwin*], [
rm() {
    rm_recursive=''
    for arg do
	AS_CASE("$arg",
		[--*], [],
		[-*r*], [break],
		[conftest.*], [AS_IF([test -d "$arg"], [rm_recursive=-r; break])],
		[])
    done
    command rm $rm_recursive "[$]@"
}
])])])dnl
