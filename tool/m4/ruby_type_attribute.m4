# -*- Autoconf -*-
dnl RUBY_TYPE_ATTRIBUTE(attrib, macroname, cachevar, condition)
AC_DEFUN([RUBY_TYPE_ATTRIBUTE], [dnl
    RUBY_DECL_ATTRIBUTE([$1], [$2], [$3], [$4],
	[type], [
@%:@define x struct conftest_attribute_check {int i;}
])
])dnl
