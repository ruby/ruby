dnl -*- Autoconf -*-
AC_DEFUN([RUBY_DEFINE_IF], [dnl
    m4_ifval([$1], [AS_LITERAL_IF([$1], [], [test "X$1" = X || ])printf "@%:@if %s\n" "$1" >>confdefs.h])
AC_DEFINE_UNQUOTED($2, $3)dnl
    m4_ifval([$1], [AS_LITERAL_IF([$1], [], [test "X$1" = X || ])printf "@%:@endif /* %s */\n" "$1" >>confdefs.h])
])dnl
