dnl -*- Autoconf -*-
AC_DEFUN([RUBY_CHECK_BUILTIN_SETJMP], [
AS_IF([test x"${ac_cv_func___builtin_setjmp}" = xyes], [
   unset ac_cv_func___builtin_setjmp
])
AC_CACHE_CHECK(for __builtin_setjmp, ac_cv_func___builtin_setjmp,
    [
    ac_cv_func___builtin_setjmp=no
    for cast in "" "(void **)"; do
	RUBY_WERROR_FLAG(
	[AC_LINK_IFELSE([AC_LANG_PROGRAM([[@%:@include <setjmp.h>
	    @%:@include <stdio.h>
	    jmp_buf jb;
	    @%:@ifdef NORETURN
	    NORETURN(void t(void));
	    @%:@endif
	    void t(void) {__builtin_longjmp($cast jb, 1);}
	    int jump(void) {(void)(__builtin_setjmp($cast jb) ? 1 : 0); return 0;}]],
	    [[
	    void (*volatile f)(void) = t;
	    if (!jump()) printf("%d\n", f != 0);
	    ]])],
	    [ac_cv_func___builtin_setjmp="yes${cast:+ with cast ($cast)}"])
	])
	test "$ac_cv_func___builtin_setjmp" = no || break
    done])
])dnl
