/* public domain rewrite of isnan(3) */

#include "ruby/missing.h"

/*
 * isnan() may be a macro, a function or both.
 * (The C99 standard defines that isnan() is a macro, though.)
 * http://www.gnu.org/software/automake/manual/autoconf/Function-Portability.html
 *
 * macro only: uClibc
 * both: GNU libc
 *
 * This file is compile if no isnan() function is available.
 * (autoconf AC_REPLACE_FUNCS detects only the function.)
 * The macro is detected by following #ifndef.
 */

#ifndef isnan
static int double_ne(double n1, double n2);

int
isnan(double n)
{
    return double_ne(n, n);
}

static int
double_ne(double n1, double n2)
{
    return n1 != n2;
}
#endif
