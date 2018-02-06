# -*- Autoconf -*-
AC_DEFUN([RUBY_CHECK_VA_COPY], [
    if test "x$rb_cv_va_copy" = x; then
        AC_TRY_RUN(
[#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#define CONFTEST_VA_COPY(dst, src) $2
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
}
int
main()
{
    conftest(10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0);
    exit(0);
}],
	rb_cv_va_copy="$1",
        rb_cv_va_copy="",
        rb_cv_va_copy="")dnl
    fi
])dnl
dnl
