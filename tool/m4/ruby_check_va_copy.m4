# -*- Autoconf -*-
AC_DEFUN([RUBY_CHECK_VA_COPY], [
    AS_IF([test "x$rb_cv_va_copy" = x], [dnl
        AC_TRY_LINK(
[@%:@include <stdlib.h>
@%:@include <stdarg.h>
@%:@include <string.h>
@%:@define CONFTEST_VA_COPY(dst, src) $2
void
conftest(int n, ...)
{
    va_list ap, ap2;
    int i;
    va_start(ap, n);
    CONFTEST_VA_COPY(ap2, ap);
    for (i = 0; i < n; i++) if ((int)va_arg(ap, int) != n - i - 1) abort();
    va_end(ap);
    CONFTEST_VA_COPY(ap, ap2);
    for (i = 0; i < n; i++) if ((int)va_arg(ap, int) != n - i - 1) abort();
    va_end(ap);
    va_end(ap2);
}],
[
    conftest(10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0);
],
    [rb_cv_va_copy="$1"],
    [rb_cv_va_copy=""])dnl
    ])dnl
])dnl
dnl
