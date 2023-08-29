#ifndef YARP_DEFINES_H
#define YARP_DEFINES_H

// This file should be included first by any *.h or *.c in YARP

#include <ctype.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// YP_EXPORTED_FUNCTION
#ifndef YP_EXPORTED_FUNCTION
#   ifdef YP_EXPORT_SYMBOLS
#       ifdef _WIN32
#          define YP_EXPORTED_FUNCTION __declspec(dllexport) extern
#       else
#          define YP_EXPORTED_FUNCTION __attribute__((__visibility__("default"))) extern
#       endif
#   else
#       define YP_EXPORTED_FUNCTION
#   endif
#endif

// YP_ATTRIBUTE_UNUSED
#if defined(__GNUC__)
#   define YP_ATTRIBUTE_UNUSED __attribute__((unused))
#else
#   define YP_ATTRIBUTE_UNUSED
#endif

// inline
#if defined(_MSC_VER) && !defined(inline)
#   define inline __inline
#endif

// Windows versions before 2015 use _snprintf
#if defined(_MSC_VER) && (_MSC_VER < 1900)
#   define snprintf _snprintf
#endif

int yp_strncasecmp(const uint8_t *string1, const uint8_t *string2, size_t length);

#endif
