/* public domain rewrite of finite(3) */

#include "missing.h"

int
finite(n)
    double n;
{
    return !isnan(n) && !isinf(n);
}
