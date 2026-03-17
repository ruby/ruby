/**
 * @file defines.h
 *
 * Macro definitions used throughout the prism library.
 *
 * This file should be included first by any *.h or *.c in prism for consistency
 * and to ensure that the macros are defined before they are used.
 */
#ifndef PRISM_DEFINES_H
#define PRISM_DEFINES_H

#include "prism/attribute/align.h"
#include "prism/attribute/exported.h"
#include "prism/attribute/fallthrough.h"
#include "prism/attribute/flex_array.h"
#include "prism/attribute/format.h"
#include "prism/attribute/inline.h"
#include "prism/attribute/unused.h"

#include "prism/internal/bit.h"
#include "prism/internal/isinf.h"

#include "prism/accel.h"
#include "prism/allocator.h"
#include "prism/excludes.h"
#include "prism/files.h"

#include <ctype.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/**
 * We want to be able to use the PRI* macros for printing out integers, but on
 * some platforms they aren't included unless this is already defined.
 */
#define __STDC_FORMAT_MACROS
// Include sys/types.h before inttypes.h to work around issue with
// certain versions of GCC and newlib which causes omission of PRIx64
#include <sys/types.h>
#include <inttypes.h>

/**
 * When we are parsing using recursive descent, we want to protect against
 * malicious payloads that could attempt to crash our parser. We do this by
 * specifying a maximum depth to which we are allowed to recurse.
 */
#ifndef PRISM_DEPTH_MAXIMUM
    #define PRISM_DEPTH_MAXIMUM 10000
#endif

/**
 * A simple utility macro to concatenate two tokens together, necessary when one
 * of the tokens is itself a macro.
 */
#define PM_CONCATENATE(left, right) left ## right

/**
 * We want to be able to use static assertions, but they weren't standardized
 * until C11. As such, we polyfill it here by making a hacky typedef that will
 * fail to compile due to a negative array size if the condition is false.
 */
#if defined(_Static_assert)
#   define PM_STATIC_ASSERT(line, condition, message) _Static_assert(condition, message)
#else
#   define PM_STATIC_ASSERT(line, condition, message) typedef char PM_CONCATENATE(static_assert_, line)[(condition) ? 1 : -1]
#endif

/**
 * isinf on POSIX systems it accepts a float, a double, or a long double.
 * But mingw didn't provide an isinf macro, only an isinf function that only
 * accepts floats, so we need to use _finite instead.
 */
#ifdef __MINGW64__
    #include <float.h>
    #define PRISM_ISINF(x) (!_finite(x))
#else
    #define PRISM_ISINF(x) isinf(x)
#endif

/**
 * Support PRISM_LIKELY and PRISM_UNLIKELY to help the compiler optimize its
 * branch predication.
 */
#if defined(__GNUC__) || defined(__clang__)
    /** The compiler should predicate that this branch will be taken. */
    #define PRISM_LIKELY(x) __builtin_expect(!!(x), 1)

    /** The compiler should predicate that this branch will not be taken. */
    #define PRISM_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
    /** Void because this platform does not support branch prediction hints. */
    #define PRISM_LIKELY(x)   (x)

    /** Void because this platform does not support branch prediction hints. */
    #define PRISM_UNLIKELY(x) (x)
#endif

#endif
