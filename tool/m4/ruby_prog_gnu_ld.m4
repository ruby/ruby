# -*- Autoconf -*-
AC_DEFUN([RUBY_PROG_GNU_LD],
[AC_CACHE_CHECK(whether the linker is GNU ld, rb_cv_prog_gnu_ld,
[AS_IF([`$CC $CFLAGS $CPPFLAGS $LDFLAGS --print-prog-name=ld 2>&1` -v 2>&1 | grep "GNU ld" > /dev/null], [
  rb_cv_prog_gnu_ld=yes
], [
  rb_cv_prog_gnu_ld=no
])])
GNU_LD=$rb_cv_prog_gnu_ld
AC_SUBST(GNU_LD)])dnl
