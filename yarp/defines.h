#ifndef YARP_DEFINES_H
#define YARP_DEFINES_H

// YP_EXPORTED_FUNCTION
#if defined(_WIN32)
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
# define YP_ATTRIBUTE_UNUSED __attribute__((unused))
#else
# define YP_ATTRIBUTE_UNUSED
#endif

// inline
#if defined(_MSC_VER) && !defined(inline)
#   define inline __inline
#endif

#endif
