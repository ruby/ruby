/**
 * @file strings.h
 *
 * A generic string type that can have various ownership semantics.
 */
#ifndef PRISM_STRINGS_H
#define PRISM_STRINGS_H

#include "prism/compiler/exported.h"
#include "prism/compiler/filesystem.h"
#include "prism/compiler/nonnull.h"

#include <stddef.h>
#include <stdint.h>

/**
 * A generic string type that can have various ownership semantics.
 */
typedef struct {
    /** A pointer to the start of the string. */
    const uint8_t *source;

    /** The length of the string in bytes of memory. */
    size_t length;

    /** The type of the string. This field determines how the string should be freed. */
    enum {
        /** This string is a constant string, and should not be freed. */
        PM_STRING_CONSTANT,

        /** This is a slice of another string, and should not be freed. */
        PM_STRING_SHARED,

        /** This string owns its memory, and should be freed using `pm_string_cleanup()`. */
        PM_STRING_OWNED,

#ifdef PRISM_HAS_MMAP
        /** This string is a memory-mapped file, and should be freed using `pm_string_cleanup()`. */
        PM_STRING_MAPPED
#endif
    } type;
} pm_string_t;

/**
 * Returns the size of the pm_string_t struct. This is necessary to allocate the
 * correct amount of memory in the FFI backend.
 *
 * @returns The size of the pm_string_t struct.
 */
PRISM_EXPORTED_FUNCTION size_t pm_string_sizeof(void);

/**
 * Initialize a constant string that doesn't own its memory source.
 *
 * @param string The string to initialize.
 * @param source The source of the string.
 * @param length The length of the string.
 */
PRISM_EXPORTED_FUNCTION void pm_string_constant_init(pm_string_t *string, const char *source, size_t length) PRISM_NONNULL(1);

/**
 * Initialize an owned string that is responsible for freeing allocated memory.
 *
 * @param string The string to initialize.
 * @param source The source of the string.
 * @param length The length of the string.
 */
PRISM_EXPORTED_FUNCTION void pm_string_owned_init(pm_string_t *string, uint8_t *source, size_t length) PRISM_NONNULL(1, 2);

/**
 * Represents the result of calling pm_string_mapped_init or
 * pm_string_file_init. We need this additional information because there is
 * not a platform-agnostic way to indicate that the file that was attempted to
 * be opened was a directory.
 */
typedef enum {
    /** Indicates that the string was successfully initialized. */
    PM_STRING_INIT_SUCCESS = 0,

    /**
     * Indicates a generic error from a string_*_init function, where the type
     * of error should be read from `errno` or `GetLastError()`.
     */
    PM_STRING_INIT_ERROR_GENERIC = 1,

    /**
     * Indicates that the file that was attempted to be opened was a directory.
     */
    PM_STRING_INIT_ERROR_DIRECTORY = 2
} pm_string_init_result_t;

/**
 * Read the file indicated by the filepath parameter into source and load its
 * contents and size into the given `pm_string_t`. The given `pm_string_t`
 * should be freed using `pm_string_cleanup` when it is no longer used.
 *
 * We want to use demand paging as much as possible in order to avoid having to
 * read the entire file into memory (which could be detrimental to performance
 * for large files). This means that if we're on windows we'll use
 * `MapViewOfFile`, on POSIX systems that have access to `mmap` we'll use
 * `mmap`, and on other POSIX systems we'll use `read`.
 *
 * @param string The string to initialize.
 * @param filepath The filepath to read.
 * @returns The success of the read, indicated by the value of the enum.
 */
PRISM_EXPORTED_FUNCTION pm_string_init_result_t pm_string_mapped_init(pm_string_t *string, const char *filepath) PRISM_NONNULL(1, 2);

/**
 * Read the file indicated by the filepath parameter into source and load its
 * contents and size into the given `pm_string_t`. The given `pm_string_t`
 * should be freed using `pm_string_cleanup` when it is no longer used.
 *
 * @param string The string to initialize.
 * @param filepath The filepath to read.
 * @returns The success of the read, indicated by the value of the enum.
 */
PRISM_EXPORTED_FUNCTION pm_string_init_result_t pm_string_file_init(pm_string_t *string, const char *filepath) PRISM_NONNULL(1, 2);

/**
 * Returns the length associated with the string.
 *
 * @param string The string to get the length of.
 * @returns The length of the string.
 */
PRISM_EXPORTED_FUNCTION size_t pm_string_length(const pm_string_t *string) PRISM_NONNULL(1);

/**
 * Returns the start pointer associated with the string.
 *
 * @param string The string to get the start pointer of.
 * @returns The start pointer of the string.
 */
PRISM_EXPORTED_FUNCTION const uint8_t * pm_string_source(const pm_string_t *string) PRISM_NONNULL(1);

/**
 * Free the associated memory of the given string.
 *
 * @param string The string to free.
 */
PRISM_EXPORTED_FUNCTION void pm_string_cleanup(pm_string_t *string) PRISM_NONNULL(1);

#endif
