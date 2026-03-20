#ifndef PRISM_INTERNAL_ISINF_H
#define PRISM_INTERNAL_ISINF_H

/*
 * isinf on POSIX systems accepts a float, a double, or a long double. But mingw
 * didn't provide an isinf macro, only an isinf function that only accepts
 * floats, so we need to use _finite instead.
 */
#ifdef __MINGW64__
    #include <float.h>
    #define PRISM_ISINF(x) (!_finite(x))
#else
    #define PRISM_ISINF(x) isinf(x)
#endif

#endif
