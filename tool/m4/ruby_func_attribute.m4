# -*- Autoconf -*-
dnl RUBY_FUNC_ATTRIBUTE(attrib, macroname, cachevar, condition)
AC_DEFUN([RUBY_FUNC_ATTRIBUTE], [dnl
    RUBY_DECL_ATTRIBUTE([$1], [$2], [$3], [$4],
	[function], [@%:@define x int conftest_attribute_check(void)]
    )
])dnl
