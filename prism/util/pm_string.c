#include "prism/util/pm_string.h"

/**
 * Returns the size of the pm_string_t struct. This is necessary to allocate the
 * correct amount of memory in the FFI backend.
 */
PRISM_EXPORTED_FUNCTION size_t
pm_string_sizeof(void) {
    return sizeof(pm_string_t);
}

/**
 * Initialize a shared string that is based on initial input.
 */
void
pm_string_shared_init(pm_string_t *string, const uint8_t *start, const uint8_t *end) {
    assert(start <= end);

    *string = (pm_string_t) {
        .type = PM_STRING_SHARED,
        .source = start,
        .length = (size_t) (end - start)
    };
}

/**
 * Initialize an owned string that is responsible for freeing allocated memory.
 */
void
pm_string_owned_init(pm_string_t *string, uint8_t *source, size_t length) {
    *string = (pm_string_t) {
        .type = PM_STRING_OWNED,
        .source = source,
        .length = length
    };
}

/**
 * Initialize a constant string that doesn't own its memory source.
 */
void
pm_string_constant_init(pm_string_t *string, const char *source, size_t length) {
    *string = (pm_string_t) {
        .type = PM_STRING_CONSTANT,
        .source = (const uint8_t *) source,
        .length = length
    };
}

/**
 * Read the file indicated by the filepath parameter into source and load its
 * contents and size into the given `pm_string_t`. The given `pm_string_t`
 * should be freed using `pm_string_free` when it is no longer used.
 *
 * We want to use demand paging as much as possible in order to avoid having to
 * read the entire file into memory (which could be detrimental to performance
 * for large files). This means that if we're on windows we'll use
 * `MapViewOfFile`, on POSIX systems that have access to `mmap` we'll use
 * `mmap`, and on other POSIX systems we'll use `read`.
 */
bool
pm_string_mapped_init(pm_string_t *string, const char *filepath) {
#ifdef _WIN32
    // Open the file for reading.
    HANDLE file = CreateFile(filepath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

    if (file == INVALID_HANDLE_VALUE) {
        perror("CreateFile failed");
        return false;
    }

    // Get the file size.
    DWORD file_size = GetFileSize(file, NULL);
    if (file_size == INVALID_FILE_SIZE) {
        CloseHandle(file);
        perror("GetFileSize failed");
        return false;
    }

    // If the file is empty, then we don't need to do anything else, we'll set
    // the source to a constant empty string and return.
    if (file_size == 0) {
        CloseHandle(file);
        const uint8_t source[] = "";
        *string = (pm_string_t) { .type = PM_STRING_CONSTANT, .source = source, .length = 0 };
        return true;
    }

    // Create a mapping of the file.
    HANDLE mapping = CreateFileMapping(file, NULL, PAGE_READONLY, 0, 0, NULL);
    if (mapping == NULL) {
        CloseHandle(file);
        perror("CreateFileMapping failed");
        return false;
    }

    // Map the file into memory.
    uint8_t *source = (uint8_t *) MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
    CloseHandle(mapping);
    CloseHandle(file);

    if (source == NULL) {
        perror("MapViewOfFile failed");
        return false;
    }

    *string = (pm_string_t) { .type = PM_STRING_MAPPED, .source = source, .length = (size_t) file_size };
    return true;
#else
    // Open the file for reading
    int fd = open(filepath, O_RDONLY);
    if (fd == -1) {
        perror("open");
        return false;
    }

    // Stat the file to get the file size
    struct stat sb;
    if (fstat(fd, &sb) == -1) {
        close(fd);
        perror("fstat");
        return false;
    }

    // mmap the file descriptor to virtually get the contents
    size_t size = (size_t) sb.st_size;
    uint8_t *source = NULL;

    if (size == 0) {
        close(fd);
        const uint8_t source[] = "";
        *string = (pm_string_t) { .type = PM_STRING_CONSTANT, .source = source, .length = 0 };
        return true;
    }

    source = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (source == MAP_FAILED) {
        perror("Map failed");
        return false;
    }

    close(fd);
    *string = (pm_string_t) { .type = PM_STRING_MAPPED, .source = source, .length = size };
    return true;
#endif
}

/**
 * Returns the memory size associated with the string.
 */
size_t
pm_string_memsize(const pm_string_t *string) {
    size_t size = sizeof(pm_string_t);
    if (string->type == PM_STRING_OWNED) {
        size += string->length;
    }
    return size;
}

/**
 * Ensure the string is owned. If it is not, then reinitialize it as owned and
 * copy over the previous source.
 */
void
pm_string_ensure_owned(pm_string_t *string) {
    if (string->type == PM_STRING_OWNED) return;

    size_t length = pm_string_length(string);
    const uint8_t *source = pm_string_source(string);

    uint8_t *memory = malloc(length);
    if (!memory) return;

    pm_string_owned_init(string, memory, length);
    memcpy((void *) string->source, source, length);
}

/**
 * Returns the length associated with the string.
 */
PRISM_EXPORTED_FUNCTION size_t
pm_string_length(const pm_string_t *string) {
    return string->length;
}

/**
 * Returns the start pointer associated with the string.
 */
PRISM_EXPORTED_FUNCTION const uint8_t *
pm_string_source(const pm_string_t *string) {
    return string->source;
}

/**
 * Free the associated memory of the given string.
 */
PRISM_EXPORTED_FUNCTION void
pm_string_free(pm_string_t *string) {
    void *memory = (void *) string->source;

    if (string->type == PM_STRING_OWNED) {
        free(memory);
    } else if (string->type == PM_STRING_MAPPED && string->length) {
#if defined(_WIN32)
        UnmapViewOfFile(memory);
#else
        munmap(memory, string->length);
#endif
    }
}
