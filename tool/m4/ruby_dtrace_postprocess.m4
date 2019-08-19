# -*- Autoconf -*-
AC_DEFUN([RUBY_DTRACE_POSTPROCESS],
[AC_CACHE_CHECK(whether $DTRACE needs post processing, rb_cv_prog_dtrace_g,
[
  rb_cv_prog_dtrace_g=no
  AS_IF([{
    cat >conftest_provider.d <<_PROBES &&
    provider conftest {
      probe fire();
    };
_PROBES
    $DTRACE ${DTRACE_OPT} -h -o conftest_provider.h -s conftest_provider.d >/dev/null 2>/dev/null &&
    :
  }], [
    AC_TRY_COMPILE([@%:@include "conftest_provider.h"], [CONFTEST_FIRE();], [
	AS_IF([{
	    cp -p conftest.${ac_objext} conftest.${ac_objext}.save &&
	    $DTRACE ${DTRACE_OPT} -G -s conftest_provider.d conftest.${ac_objext} 2>/dev/null &&
	    :
	}], [
	    AS_IF([cmp -s conftest.o conftest.${ac_objext}.save], [
		rb_cv_prog_dtrace_g=yes
	    ], [
		rb_cv_prog_dtrace_g=rebuild
	    ])
	])])
  ])
  rm -f conftest.[co] conftest_provider.[dho]
])
])dnl
