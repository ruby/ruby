/**
 * @file attribute/exported.h
 *
 * Macro definitions for make functions publically visible.
 */
#ifndef PRISM_EXPORTED_H
#define PRISM_EXPORTED_H

/**
 * By default, we compile with -fvisibility=hidden. When this is enabled, we
 * need to mark certain functions as being publically-visible. This macro does
 * that in a compiler-agnostic way.
 */
#ifndef PRISM_EXPORTED_FUNCTION
#   ifdef PRISM_EXPORT_SYMBOLS
#       ifdef _WIN32
#          define PRISM_EXPORTED_FUNCTION __declspec(dllexport) extern
#       else
#          define PRISM_EXPORTED_FUNCTION __attribute__((__visibility__("default"))) extern
#       endif
#   else
#       define PRISM_EXPORTED_FUNCTION
#   endif
#endif

#endif
