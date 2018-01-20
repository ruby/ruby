# -*- Autoconf -*-
AC_DEFUN([RUBY_DEFINE_IF], [dnl
    m4_ifval([$1], [AS_LITERAL_IF([$1], [], [test "X$1" = X || ])cat <<EOH >> confdefs.h
@%:@if $1
EOH
])dnl
AC_DEFINE_UNQUOTED($2, $3)dnl
    m4_ifval([$1], [AS_LITERAL_IF([$1], [], [test "X$1" = X || ])cat <<EOH >> confdefs.h
@%:@endif /* $1 */
EOH
])dnl
])dnl
