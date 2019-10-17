# -*- Autoconf -*-
AC_DEFUN([RUBY_DTRACE_AVAILABLE],
[AC_CACHE_CHECK(whether dtrace USDT is available, rb_cv_dtrace_available,
[
    echo "provider conftest{ probe fire(); };" > conftest_provider.d
    rb_cv_dtrace_available=no
    AS_FOR(opt, rb_dtrace_opt, ["-xnolibs" ""], [dnl
	AS_IF([$DTRACE opt -h -o conftest_provider.h -s conftest_provider.d >/dev/null 2>/dev/null],
	    [], [continue])
	AC_TRY_COMPILE([@%:@include "conftest_provider.h"], [CONFTEST_FIRE();],
	    [], [continue])
	# DTrace is available on the system
	rb_cv_dtrace_available=yes${rb_dtrace_opt:+"(opt)"}
	break
    ])
    rm -f conftest.[co] conftest_provider.[dho]
])
AS_CASE(["$rb_cv_dtrace_available"], ["yes("*")"],
    [DTRACE_OPT=`expr "$rb_cv_dtrace_available" : "yes(\(.*\))"`])
])dnl
