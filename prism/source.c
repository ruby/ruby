#include "prism/internal/source.h"

#include "prism/internal/allocator.h"
#include "prism/internal/buffer.h"

#include <stdlib.h>
#include <string.h>

/* The following headers are necessary to read files using demand paging. */
#ifdef _WIN32
#include <windows.h>
#elif defined(_POSIX_MAPPED_FILES)
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#elif defined(PRISM_HAS_FILESYSTEM)
#include <fcntl.h>
#include <sys/stat.h>
#endif

static const uint8_t empty_source[] = "";

/**
 * Allocate and initialize a pm_source_t with the given fields.
 */
static pm_source_t *
pm_source_alloc(const uint8_t *source, size_t length, pm_source_type_t type) {
    pm_source_t *result = xmalloc(sizeof(pm_source_t));
    if (result == NULL) abort();

    *result = (struct pm_source_t) {
        .source = source,
        .length = length,
        .type = type
    };

    return result;
}

/**
 * Create a new source that wraps existing constant memory.
 */
pm_source_t *
pm_source_constant_new(const uint8_t *data, size_t length) {
    return pm_source_alloc(data, length, PM_SOURCE_CONSTANT);
}

/**
 * Create a new source that wraps existing shared memory.
 */
pm_source_t *
pm_source_shared_new(const uint8_t *data, size_t length) {
    return pm_source_alloc(data, length, PM_SOURCE_SHARED);
}

/**
 * Create a new source that owns its memory.
 */
pm_source_t *
pm_source_owned_new(uint8_t *data, size_t length) {
    return pm_source_alloc(data, length, PM_SOURCE_OWNED);
}

#ifdef _WIN32
/**
 * Represents a file handle on Windows, where the path will need to be freed
 * when the file is closed.
 */
typedef struct {
    /** The path to the file, which will become allocated memory. */
    WCHAR *path;

    /** The size of the allocated path in bytes. */
    size_t path_size;

    /** The handle to the file, which will start as uninitialized memory. */
    HANDLE file;
} pm_source_file_handle_t;

/**
 * Open the file indicated by the filepath parameter for reading on Windows.
 */
static pm_source_init_result_t
pm_source_file_handle_open(pm_source_file_handle_t *handle, const char *filepath) {
    int length = MultiByteToWideChar(CP_UTF8, 0, filepath, -1, NULL, 0);
    if (length == 0) return PM_SOURCE_INIT_ERROR_GENERIC;

    handle->path_size = sizeof(WCHAR) * ((size_t) length);
    handle->path = xmalloc(handle->path_size);
    if ((handle->path == NULL) || (MultiByteToWideChar(CP_UTF8, 0, filepath, -1, handle->path, length) == 0)) {
        xfree_sized(handle->path, handle->path_size);
        return PM_SOURCE_INIT_ERROR_GENERIC;
    }

    handle->file = CreateFileW(handle->path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_READONLY, NULL);
    if (handle->file == INVALID_HANDLE_VALUE) {
        pm_source_init_result_t result = PM_SOURCE_INIT_ERROR_GENERIC;

        if (GetLastError() == ERROR_ACCESS_DENIED) {
            DWORD attributes = GetFileAttributesW(handle->path);
            if ((attributes != INVALID_FILE_ATTRIBUTES) && (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
                result = PM_SOURCE_INIT_ERROR_DIRECTORY;
            }
        }

        xfree_sized(handle->path, handle->path_size);
        return result;
    }

    return PM_SOURCE_INIT_SUCCESS;
}

/**
 * Close the file handle and free the path.
 */
static void
pm_source_file_handle_close(pm_source_file_handle_t *handle) {
    xfree_sized(handle->path, handle->path_size);
    CloseHandle(handle->file);
}
#endif

/**
 * Create a new source by memory-mapping a file.
 */
pm_source_t *
pm_source_mapped_new(const char *filepath, int open_flags, pm_source_init_result_t *result) {
#ifdef _WIN32
    (void) open_flags;

    /* Open the file for reading. */
    pm_source_file_handle_t handle;
    *result = pm_source_file_handle_open(&handle, filepath);
    if (*result != PM_SOURCE_INIT_SUCCESS) return NULL;

    /* Get the file size. */
    DWORD file_size = GetFileSize(handle.file, NULL);
    if (file_size == INVALID_FILE_SIZE) {
        pm_source_file_handle_close(&handle);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* If the file is empty, then return a constant source. */
    if (file_size == 0) {
        pm_source_file_handle_close(&handle);
        *result = PM_SOURCE_INIT_SUCCESS;
        return pm_source_alloc(empty_source, 0, PM_SOURCE_CONSTANT);
    }

    /* Create a mapping of the file. */
    HANDLE mapping = CreateFileMapping(handle.file, NULL, PAGE_READONLY, 0, 0, NULL);
    if (mapping == NULL) {
        pm_source_file_handle_close(&handle);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* Map the file into memory. */
    uint8_t *source = (uint8_t *) MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
    CloseHandle(mapping);
    pm_source_file_handle_close(&handle);

    if (source == NULL) {
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    *result = PM_SOURCE_INIT_SUCCESS;
    return pm_source_alloc(source, (size_t) file_size, PM_SOURCE_MAPPED);
#elif defined(_POSIX_MAPPED_FILES)
    /* Open the file for reading. */
    int fd = open(filepath, O_RDONLY | open_flags);
    if (fd == -1) {
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* Stat the file to get the file size. */
    struct stat sb;
    if (fstat(fd, &sb) == -1) {
        close(fd);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* Ensure it is a file and not a directory. */
    if (S_ISDIR(sb.st_mode)) {
        close(fd);
        *result = PM_SOURCE_INIT_ERROR_DIRECTORY;
        return NULL;
    }

    /*
     * For non-regular files (pipes, character devices), return a specific
     * error so the caller can handle reading through their own I/O layer.
     */
    if (!S_ISREG(sb.st_mode)) {
        close(fd);
        *result = PM_SOURCE_INIT_ERROR_NON_REGULAR;
        return NULL;
    }

    /* mmap the file descriptor to virtually get the contents. */
    size_t size = (size_t) sb.st_size;

    if (size == 0) {
        close(fd);
        *result = PM_SOURCE_INIT_SUCCESS;
        return pm_source_alloc(empty_source, 0, PM_SOURCE_CONSTANT);
    }

    uint8_t *source = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (source == MAP_FAILED) {
        close(fd);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    close(fd);
    *result = PM_SOURCE_INIT_SUCCESS;
    return pm_source_alloc(source, size, PM_SOURCE_MAPPED);
#else
    (void) open_flags;
    return pm_source_file_new(filepath, result);
#endif
}

/**
 * Create a new source by reading a file into a heap-allocated buffer.
 */
pm_source_t *
pm_source_file_new(const char *filepath, pm_source_init_result_t *result) {
#ifdef _WIN32
    /* Open the file for reading. */
    pm_source_file_handle_t handle;
    *result = pm_source_file_handle_open(&handle, filepath);
    if (*result != PM_SOURCE_INIT_SUCCESS) return NULL;

    /* Get the file size. */
    const DWORD file_size = GetFileSize(handle.file, NULL);
    if (file_size == INVALID_FILE_SIZE) {
        pm_source_file_handle_close(&handle);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* If the file is empty, return a constant source. */
    if (file_size == 0) {
        pm_source_file_handle_close(&handle);
        *result = PM_SOURCE_INIT_SUCCESS;
        return pm_source_alloc(empty_source, 0, PM_SOURCE_CONSTANT);
    }

    /* Create a buffer to read the file into. */
    uint8_t *source = xmalloc(file_size);
    if (source == NULL) {
        pm_source_file_handle_close(&handle);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* Read the contents of the file. */
    DWORD bytes_read;
    if (!ReadFile(handle.file, source, file_size, &bytes_read, NULL)) {
        xfree_sized(source, file_size);
        pm_source_file_handle_close(&handle);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* Check the number of bytes read. */
    if (bytes_read != file_size) {
        xfree_sized(source, file_size);
        pm_source_file_handle_close(&handle);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    pm_source_file_handle_close(&handle);
    *result = PM_SOURCE_INIT_SUCCESS;
    return pm_source_alloc(source, (size_t) file_size, PM_SOURCE_OWNED);
#elif defined(PRISM_HAS_FILESYSTEM)
    /* Open the file for reading. */
    int fd = open(filepath, O_RDONLY);
    if (fd == -1) {
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* Stat the file to get the file size. */
    struct stat sb;
    if (fstat(fd, &sb) == -1) {
        close(fd);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    /* Ensure it is a file and not a directory. */
    if (S_ISDIR(sb.st_mode)) {
        close(fd);
        *result = PM_SOURCE_INIT_ERROR_DIRECTORY;
        return NULL;
    }

    /* Check the size to see if it's empty. */
    size_t size = (size_t) sb.st_size;
    if (size == 0) {
        close(fd);
        *result = PM_SOURCE_INIT_SUCCESS;
        return pm_source_alloc(empty_source, 0, PM_SOURCE_CONSTANT);
    }

    const size_t length = (size_t) size;
    uint8_t *source = xmalloc(length);
    if (source == NULL) {
        close(fd);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    ssize_t bytes_read = read(fd, source, length);
    close(fd);

    if (bytes_read == -1 || (size_t) bytes_read != length) {
        xfree_sized(source, length);
        *result = PM_SOURCE_INIT_ERROR_GENERIC;
        return NULL;
    }

    *result = PM_SOURCE_INIT_SUCCESS;
    return pm_source_alloc(source, length, PM_SOURCE_OWNED);
#else
    (void) filepath;
    *result = PM_SOURCE_INIT_ERROR_GENERIC;
    perror("pm_source_file_new is not implemented for this platform");
    return NULL;
#endif
}

/**
 * Create a new source by reading from a stream. This allocates the source
 * but does not read from the stream yet. Use pm_source_stream_read to read
 * data.
 */
pm_source_t *
pm_source_stream_new(void *stream, pm_source_stream_fgets_t *fgets, pm_source_stream_feof_t *feof) {
    pm_source_t *source = pm_source_alloc(NULL, 0, PM_SOURCE_STREAM);
    source->stream.buffer = pm_buffer_new();
    source->stream.stream = stream;
    source->stream.fgets = fgets;
    source->stream.feof = feof;
    source->stream.eof = false;

    return source;
}

/**
 * Read from the stream into the source's internal buffer until __END__ is
 * encountered or EOF is reached. Updates the source pointer and length.
 *
 * Returns true if EOF was reached, false if __END__ was encountered.
 */
bool
pm_source_stream_read(pm_source_t *source) {
    pm_buffer_t *buffer = source->stream.buffer;

#define LINE_SIZE 4096
    char line[LINE_SIZE];

    while (memset(line, '\n', LINE_SIZE), source->stream.fgets(line, LINE_SIZE, source->stream.stream) != NULL) {
        size_t length = LINE_SIZE;
        while (length > 0 && line[length - 1] == '\n') length--;

        if (length == LINE_SIZE) {
            /*
             * If we read a line that is the maximum size and it doesn't end
             * with a newline, then we'll just append it to the buffer and
             * continue reading.
             */
            length--;
            pm_buffer_append_string(buffer, line, length);
            continue;
        }

        /* Append the line to the buffer. */
        length--;
        pm_buffer_append_string(buffer, line, length);

        /*
         * Check if the line matches the __END__ marker. If it does, then stop
         * reading and return false. In most circumstances, this means we should
         * stop reading from the stream so that the DATA constant can pick it
         * up.
         */
        switch (length) {
            case 7:
                if (strncmp(line, "__END__", 7) == 0) {
                    source->source = (const uint8_t *) pm_buffer_value(buffer);
                    source->length = pm_buffer_length(buffer);
                    return false;
                }
                break;
            case 8:
                if (strncmp(line, "__END__\n", 8) == 0) {
                    source->source = (const uint8_t *) pm_buffer_value(buffer);
                    source->length = pm_buffer_length(buffer);
                    return false;
                }
                break;
            case 9:
                if (strncmp(line, "__END__\r\n", 9) == 0) {
                    source->source = (const uint8_t *) pm_buffer_value(buffer);
                    source->length = pm_buffer_length(buffer);
                    return false;
                }
                break;
        }

        /*
         * All data should be read via gets. If the string returned by gets
         * _doesn't_ end with a newline, then we assume we hit EOF condition.
         */
        if (source->stream.feof(source->stream.stream)) {
            break;
        }
    }

#undef LINE_SIZE

    source->stream.eof = true;
    source->source = (const uint8_t *) pm_buffer_value(buffer);
    source->length = pm_buffer_length(buffer);
    return true;
}

/**
 * Returns whether the stream source has reached EOF.
 */
bool
pm_source_stream_eof(const pm_source_t *source) {
    return source->stream.eof;
}

/**
 * Free the given source and any memory it owns.
 */
void
pm_source_free(pm_source_t *source) {
    switch (source->type) {
        case PM_SOURCE_CONSTANT:
        case PM_SOURCE_SHARED:
            /* No cleanup needed for the data. */
            break;
        case PM_SOURCE_OWNED:
            xfree_sized((void *) source->source, source->length);
            break;
        case PM_SOURCE_MAPPED:
#if defined(_WIN32)
            if (source->length > 0) {
                UnmapViewOfFile((void *) source->source);
            }
#elif defined(_POSIX_MAPPED_FILES)
            if (source->length > 0) {
                munmap((void *) source->source, source->length);
            }
#endif
            break;
        case PM_SOURCE_STREAM:
            pm_buffer_free(source->stream.buffer);
            break;
    }

    xfree_sized(source, sizeof(pm_source_t));
}

/**
 * Returns the length of the source data in bytes.
 */
size_t
pm_source_length(const pm_source_t *source) {
    return source->length;
}

/**
 * Returns a pointer to the source data.
 */
const uint8_t *
pm_source_source(const pm_source_t *source) {
    return source->source;
}
