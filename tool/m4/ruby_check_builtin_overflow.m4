dnl -*- Autoconf -*-
AC_DEFUN([RUBY_CHECK_BUILTIN_OVERFLOW], [dnl
{ # $0($1)
  RUBY_CHECK_BUILTIN_FUNC(__builtin_[$1]_overflow, [int x;__builtin_[$1]_overflow(0,0,&x)])
  RUBY_CHECK_BUILTIN_FUNC(__builtin_[$1]_overflow_p, [__builtin_[$1]_overflow_p(0,0,(int)0)])

  AS_IF([test "$rb_cv_builtin___builtin_[$1]_overflow" != no], [
    AC_CACHE_CHECK(for __builtin_[$1]_overflow with long long arguments, rb_cv_use___builtin_[$1]_overflow_long_long, [
      AC_LINK_IFELSE([AC_LANG_SOURCE([[
@%:@pragma clang optimize off

int
main(void)
{
    long long x = 0, y;
    __builtin_$1_overflow(x, x, &y);

    return 0;
}
]])],
	rb_cv_use___builtin_[$1]_overflow_long_long=yes,
	rb_cv_use___builtin_[$1]_overflow_long_long=no)])
  ])
  AS_IF([test "$rb_cv_use___builtin_[$1]_overflow_long_long" = yes], [
    AC_DEFINE(USE___BUILTIN_[]AS_TR_CPP($1)_OVERFLOW_LONG_LONG, 1)
  ])
}
])dnl
