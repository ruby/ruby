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
#if defined(YP_STATIC)
#   define YP_EXPORTED_FUNCTION
#elif defined(_WIN32)
#   define YP_EXPORTED_FUNCTION __declspec(dllexport) extern
#else
#   ifndef YP_EXPORTED_FUNCTION
#       ifndef RUBY_FUNC_EXPORTED
#           define YP_EXPORTED_FUNCTION __attribute__((__visibility__("default"))) extern
#       else
#           define YP_EXPORTED_FUNCTION RUBY_FUNC_EXPORTED
#       endif
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
#endif

#endif
