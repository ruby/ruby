#ifndef YARP_DEFINES_H
#define YARP_DEFINES_H

// This file should be included first by any *.h or *.c in YARP

#include "yarp/config.h"

#include <ctype.h>
#include <stdarg.h>
#include <stddef.h>
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

int yp_strncasecmp(const char *string1, const char *string2, size_t length);

int yp_snprintf(char *dest, YP_ATTRIBUTE_UNUSED size_t size, const char *format, ...);

#if defined(HAVE_SNPRINTF)
    // We use snprintf if it's available
#   define yp_snprintf snprintf

#else
    // In case snprintf isn't present on the system, we provide our own that simply
    // forwards to the less-safe sprintf.
#   define yp_snprintf(dest, size, ...) sprintf((dest), __VA_ARGS__)

#endif

#endif
