dnl -*- Autoconf -*-
AC_DEFUN([RUBY_CPPOUTFILE],
[AC_CACHE_CHECK(whether ${CPP} accepts -o, rb_cv_cppoutfile,
[save_CPPFLAGS="$CPPFLAGS"
CPPFLAGS='-o conftest-1.i'
rb_cv_cppoutfile=no
AC_PREPROC_IFELSE([AC_LANG_SOURCE([[test-for-cppout]])],
                  [grep test-for-cppout conftest-1.i > /dev/null && rb_cv_cppoutfile=yes])
CPPFLAGS="$save_CPPFLAGS"
rm -f conftest*])
AS_IF([test "$rb_cv_cppoutfile" = yes], [
  CPPOUTFILE='-o conftest.i'
], [test "$rb_cv_cppoutfile" = no], [
  CPPOUTFILE='> conftest.i'
], [test -n "$rb_cv_cppoutfile"], [
  CPPOUTFILE="$rb_cv_cppoutfile"
])
AC_SUBST(CPPOUTFILE)])dnl
