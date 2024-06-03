dnl -*- Autoconf -*-
AC_DEFUN([RUBY_CHECK_HEADER],
    [# RUBY_CHECK_HEADER($@)
    save_CPPFLAGS="$CPPFLAGS"
    CPPFLAGS="$CPPFLAGS m4_if([$5], [], [$INCFLAGS], [$5])"
    AC_CHECK_HEADERS([$1], [$2], [$3], [$4])
    CPPFLAGS="$save_CPPFLAGS"
    unset save_CPPFLAGS])
