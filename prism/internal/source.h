#ifndef PRISM_INTERNAL_SOURCE_H
#define PRISM_INTERNAL_SOURCE_H

#include "prism/source.h"
#include "prism/buffer.h"

#include <stdbool.h>

/*
 * The type of source, which determines cleanup behavior.
 */
typedef enum {
    /* Wraps existing constant memory, no cleanup. */
    PM_SOURCE_CONSTANT,

    /* Wraps existing shared memory (non-owning slice), no cleanup. */
    PM_SOURCE_SHARED,

    /* Owns a heap-allocated buffer, freed on cleanup. */
    PM_SOURCE_OWNED,

    /* Memory-mapped file, unmapped on cleanup. */
    PM_SOURCE_MAPPED,

    /* Stream source backed by a pm_buffer_t. */
    PM_SOURCE_STREAM
} pm_source_type_t;

/*
 * The internal representation of a source.
 */
struct pm_source_t {
    /* A pointer to the start of the source data. */
    const uint8_t *source;

    /* The length of the source data in bytes. */
    size_t length;

    /* The type of the source. */
    pm_source_type_t type;

    /* Stream-specific data, only used for PM_SOURCE_STREAM sources. */
    struct {
        /* The buffer that holds the accumulated stream data. */
        pm_buffer_t *buffer;

        /* The stream object to read from. */
        void *stream;

        /* The function to use to read from the stream. */
        pm_source_stream_fgets_t *fgets;

        /* The function to use to check if the stream is at EOF. */
        pm_source_stream_feof_t *feof;

        /* Whether the stream has reached EOF. */
        bool eof;
    } stream;
};

/*
 * Read from a stream into the source's internal buffer. This is used by
 * pm_parse_stream to incrementally read the source.
 */
bool pm_source_stream_read(pm_source_t *source);

/*
 * Returns whether the stream source has reached EOF.
 */
bool pm_source_stream_eof(const pm_source_t *source);

#endif
