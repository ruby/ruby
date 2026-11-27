/**
 * @file excludes.h
 *
 * A header file that defines macros to exclude certain features of the prism
 * library. This is useful for reducing the size of the library when certain
 * features are not needed.
 */
#ifndef PRISM_EXCLUDES_H
#define PRISM_EXCLUDES_H

/**
 * If PRISM_BUILD_MINIMAL is defined, then we're going to define every possible
 * switch that will turn off certain features of prism.
 */
#ifdef PRISM_BUILD_MINIMAL
    /** Exclude the serialization API. */
    #define PRISM_EXCLUDE_SERIALIZATION

    /** Exclude the JSON serialization API. */
    #define PRISM_EXCLUDE_JSON

    /** Exclude the prettyprint API. */
    #define PRISM_EXCLUDE_PRETTYPRINT

    /** Exclude the full set of encodings, using the minimal only. */
    #define PRISM_ENCODING_EXCLUDE_FULL
#endif

#endif
