# -*- Autoconf -*-
AC_DEFUN([RUBY_SETJMP_TYPE], [
RUBY_CHECK_BUILTIN_SETJMP
RUBY_CHECK_SETJMP(_setjmpex, [], [@%:@include <setjmpex.h>])
RUBY_CHECK_SETJMP(_setjmp)
RUBY_CHECK_SETJMP(sigsetjmp, [sigjmp_buf])
AC_MSG_CHECKING(for setjmp type)
setjmp_suffix=
unset setjmp_sigmask
AC_ARG_WITH(setjmp-type,
	AS_HELP_STRING([--with-setjmp-type], [select setjmp type]),
	[
	AS_CASE([$withval],
	[__builtin_setjmp], [setjmp=__builtin_setjmp],
	[_setjmp], [ setjmp_prefix=_],
	[sigsetjmp,*], [ setjmp_prefix=sig setjmp_sigmask=`expr "$withval" : 'sigsetjmp\(,.*\)'`],
	[sigsetjmp], [ setjmp_prefix=sig],
	[setjmp], [ setjmp_prefix=],
	[setjmpex], [ setjmp_prefix= setjmp_suffix=ex],
	[''], [ unset setjmp_prefix],
	[   AC_MSG_ERROR(invalid setjmp type: $withval)])], [unset setjmp_prefix])
setjmp_cast=
AS_IF([test ${setjmp_prefix+set}], [
    AS_IF([test "${setjmp_prefix}" && eval test '$ac_cv_func_'${setjmp_prefix}setjmp${setjmp_suffix} = no], [
	AC_MSG_ERROR(${setjmp_prefix}setjmp${setjmp_suffix} is not available)
    ])
], [{ AS_CASE("$ac_cv_func___builtin_setjmp", [yes*], [true], [false]) }], [
    setjmp_cast=`expr "$ac_cv_func___builtin_setjmp" : "yes with cast (\(.*\))"`
    setjmp_prefix=__builtin_
    setjmp_suffix=
], [test "$ac_cv_header_setjmpex_h:$ac_cv_func__setjmpex" = yes:yes], [
    setjmp_prefix=
    setjmp_suffix=ex
], [test "$ac_cv_func__setjmp" = yes], [
    setjmp_prefix=_
    setjmp_suffix=
], [test "$ac_cv_func_sigsetjmp" = yes], [
    AS_CASE([$target_os],[solaris*|cygwin*],[setjmp_prefix=],[setjmp_prefix=sig])
    setjmp_suffix=
], [
    setjmp_prefix=
    setjmp_suffix=
])
AS_IF([test x$setjmp_prefix:$setjmp_sigmask = xsig:], [
    setjmp_sigmask=,0
])
AC_MSG_RESULT(${setjmp_prefix}setjmp${setjmp_suffix}${setjmp_cast:+\($setjmp_cast\)}${setjmp_sigmask})
AC_DEFINE_UNQUOTED([RUBY_SETJMP(env)], [${setjmp_prefix}setjmp${setjmp_suffix}($setjmp_cast(env)${setjmp_sigmask})])
AC_DEFINE_UNQUOTED([RUBY_LONGJMP(env,val)], [${setjmp_prefix}longjmp($setjmp_cast(env),val)])
AS_IF([test x$setjmp_prefix != x__builtin_], AC_DEFINE_UNQUOTED(RUBY_JMP_BUF, ${setjmp_sigmask+${setjmp_prefix}}jmp_buf))
AS_IF([test x$setjmp_suffix = xex], [AC_DEFINE_UNQUOTED(RUBY_USE_SETJMPEX, 1)])
])dnl
