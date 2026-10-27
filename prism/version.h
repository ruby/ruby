/**
 * @file version.h
 *
 * The version of the Prism library.
 */
#ifndef PRISM_VERSION_H
#define PRISM_VERSION_H

#include "prism/compiler/exported.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * The major version of the Prism library as an int.
 */
#define PRISM_VERSION_MAJOR 2

/**
 * The minor version of the Prism library as an int.
 */
#define PRISM_VERSION_MINOR 0

/**
 * The patch version of the Prism library as an int.
 */
#define PRISM_VERSION_PATCH 0

/**
 * The version of the Prism library as a constant string.
 */
#define PRISM_VERSION "2.0.0"

/**
 * The prism version and the serialization format.
 *
 * @returns The prism version as a constant string.
 */
PRISM_EXPORTED_FUNCTION const char * pm_version(void);

#ifdef __cplusplus
}
#endif

#endif
