/**
 * @file source.h
 *
 * An opaque type representing the source code being parsed, regardless of
 * origin (constant memory, file, memory-mapped file, or stream).
 */
#ifndef PRISM_SOURCE_H
#define PRISM_SOURCE_H

#include "prism/compiler/exported.h"
#include "prism/compiler/filesystem.h"
#include "prism/compiler/nodiscard.h"
#include "prism/compiler/nonnull.h"

#include <stddef.h>
#include <stdint.h>

/**
 * An opaque type representing source code being parsed.
 */
typedef struct pm_source_t pm_source_t;

/**
 * This function is used to retrieve a line of input from a stream. It closely
 * mirrors that of fgets so that fgets can be used as the default
 * implementation.
 */
typedef char * (pm_source_stream_fgets_t)(char *string, int size, void *stream);

/**
 * This function is used to check whether a stream is at EOF. It closely mirrors
 * that of feof so that feof can be used as the default implementation.
 */
typedef int (pm_source_stream_feof_t)(void *stream);

/**
 * Represents the result of initializing a source from a file.
 */
typedef enum {
    /** Indicates that the source was successfully initialized. */
    PM_SOURCE_INIT_SUCCESS = 0,

    /**
     * Indicates a generic error from a source init function, where the type
     * of error should be read from `errno` or `GetLastError()`.
     */
    PM_SOURCE_INIT_ERROR_GENERIC = 1,

    /**
     * Indicates that the file that was attempted to be opened was a directory.
     */
    PM_SOURCE_INIT_ERROR_DIRECTORY = 2,

    /**
     * Indicates that the file is not a regular file (e.g. a pipe or character
     * device) and the caller should handle reading it.
     */
    PM_SOURCE_INIT_ERROR_NON_REGULAR = 3
} pm_source_init_result_t;

/**
 * Create a new source that wraps existing constant memory. The memory is not
 * owned and will not be freed.
 *
 * @param data The pointer to the source data.
 * @param length The length of the source data in bytes.
 * @returns A new source, or NULL on allocation failure.
 */
PRISM_EXPORTED_FUNCTION pm_source_t * pm_source_constant_new(const uint8_t *data, size_t length) PRISM_NODISCARD;

/**
 * Create a new source that wraps existing shared memory. The memory is not
 * owned and will not be freed. Semantically a "slice" of another source.
 *
 * @param data The pointer to the source data.
 * @param length The length of the source data in bytes.
 * @returns A new source, or NULL on allocation failure.
 */
PRISM_EXPORTED_FUNCTION pm_source_t * pm_source_shared_new(const uint8_t *data, size_t length) PRISM_NODISCARD;

/**
 * Create a new source by reading a file into a heap-allocated buffer.
 *
 * @param filepath The path to the file to read.
 * @param result Out parameter for the result of the initialization.
 * @returns A new source, or NULL on error (with result written to out param).
 */
PRISM_EXPORTED_FUNCTION pm_source_t * pm_source_file_new(const char *filepath, pm_source_init_result_t *result) PRISM_NODISCARD PRISM_NONNULL(1, 2);

/**
 * Create a new source by memory-mapping a file. Falls back to file reading on
 * platforms without mmap support.
 *
 * If the file is a non-regular file (e.g. a pipe or character device),
 * PM_SOURCE_INIT_ERROR_NON_REGULAR is returned, allowing the caller to handle
 * it appropriately (e.g. by reading it through their own I/O layer).
 *
 * @param filepath The path to the file to read.
 * @param open_flags Additional flags to pass to open(2) (e.g. O_NONBLOCK).
 * @param result Out parameter for the result of the initialization.
 * @returns A new source, or NULL on error (with result written to out param).
 */
PRISM_EXPORTED_FUNCTION pm_source_t * pm_source_mapped_new(const char *filepath, int open_flags, pm_source_init_result_t *result) PRISM_NODISCARD PRISM_NONNULL(1, 3);

/**
 * Create a new source by reading from a stream using the provided callbacks.
 *
 * @param stream The stream to read from.
 * @param fgets The function to use to read from the stream.
 * @param feof The function to use to check if the stream is at EOF.
 * @returns A new source, or NULL on allocation failure.
 */
PRISM_EXPORTED_FUNCTION pm_source_t * pm_source_stream_new(void *stream, pm_source_stream_fgets_t *fgets, pm_source_stream_feof_t *feof) PRISM_NODISCARD;

/**
 * Free the given source and any memory it owns.
 *
 * @param source The source to free.
 */
PRISM_EXPORTED_FUNCTION void pm_source_free(pm_source_t *source) PRISM_NONNULL(1);

/**
 * Returns the length of the source data in bytes.
 *
 * @param source The source to get the length of.
 * @returns The length of the source data.
 */
PRISM_EXPORTED_FUNCTION size_t pm_source_length(const pm_source_t *source) PRISM_NONNULL(1);

/**
 * Returns a pointer to the source data.
 *
 * @param source The source to get the data of.
 * @returns A pointer to the source data.
 */
PRISM_EXPORTED_FUNCTION const uint8_t * pm_source_source(const pm_source_t *source) PRISM_NONNULL(1);

#endif
