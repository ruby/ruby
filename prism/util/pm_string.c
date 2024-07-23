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
PRISM_EXPORTED_FUNCTION bool
pm_string_mapped_init(pm_string_t *string, const char *filepath) {
#ifdef _WIN32
    // Open the file for reading.
    HANDLE file = CreateFile(filepath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

    if (file == INVALID_HANDLE_VALUE) {
        return false;
    }

    // Get the file size.
    DWORD file_size = GetFileSize(file, NULL);
    if (file_size == INVALID_FILE_SIZE) {
        CloseHandle(file);
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
        return false;
    }

    // Map the file into memory.
    uint8_t *source = (uint8_t *) MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
    CloseHandle(mapping);
    CloseHandle(file);

    if (source == NULL) {
        return false;
    }

    *string = (pm_string_t) { .type = PM_STRING_MAPPED, .source = source, .length = (size_t) file_size };
    return true;
#elif defined(_POSIX_MAPPED_FILES)
    // Open the file for reading
    int fd = open(filepath, O_RDONLY);
    if (fd == -1) {
        return false;
    }

    // Stat the file to get the file size
    struct stat sb;
    if (fstat(fd, &sb) == -1) {
        close(fd);
        return false;
    }

    // Ensure it is a file and not a directory
    if (S_ISDIR(sb.st_mode)) {
        errno = EISDIR;
        close(fd);
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
        return false;
    }

    close(fd);
    *string = (pm_string_t) { .type = PM_STRING_MAPPED, .source = source, .length = size };
    return true;
#else
    (void) string;
    (void) filepath;
    perror("pm_string_mapped_init is not implemented for this platform");
    return false;
#endif
}

/**
 * Read the file indicated by the filepath parameter into source and load its
 * contents and size into the given `pm_string_t`. The given `pm_string_t`
 * should be freed using `pm_string_free` when it is no longer used.
 */
PRISM_EXPORTED_FUNCTION bool
pm_string_file_init(pm_string_t *string, const char *filepath) {
#ifdef _WIN32
    // Open the file for reading.
    HANDLE file = CreateFile(filepath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

    if (file == INVALID_HANDLE_VALUE) {
        return false;
    }

    // Get the file size.
    DWORD file_size = GetFileSize(file, NULL);
    if (file_size == INVALID_FILE_SIZE) {
        CloseHandle(file);
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

    // Create a buffer to read the file into.
    uint8_t *source = xmalloc(file_size);
    if (source == NULL) {
        CloseHandle(file);
        return false;
    }

    // Read the contents of the file
    DWORD bytes_read;
    if (!ReadFile(file, source, file_size, &bytes_read, NULL)) {
        CloseHandle(file);
        return false;
    }

    // Check the number of bytes read
    if (bytes_read != file_size) {
        xfree(source);
        CloseHandle(file);
        return false;
    }

    CloseHandle(file);
    *string = (pm_string_t) { .type = PM_STRING_OWNED, .source = source, .length = (size_t) file_size };
    return true;
#elif defined(_POSIX_MAPPED_FILES)
    FILE *file = fopen(filepath, "rb");
    if (file == NULL) {
        return false;
    }

    fseek(file, 0, SEEK_END);
    long file_size = ftell(file);

    if (file_size == -1) {
        fclose(file);
        return false;
    }

    if (file_size == 0) {
        fclose(file);
        const uint8_t source[] = "";
        *string = (pm_string_t) { .type = PM_STRING_CONSTANT, .source = source, .length = 0 };
        return true;
    }

    size_t length = (size_t) file_size;
    uint8_t *source = xmalloc(length);
    if (source == NULL) {
        fclose(file);
        return false;
    }

    fseek(file, 0, SEEK_SET);
    size_t bytes_read = fread(source, length, 1, file);
    fclose(file);

    if (bytes_read != 1) {
        xfree(source);
        return false;
    }

    *string = (pm_string_t) { .type = PM_STRING_OWNED, .source = source, .length = length };
    return true;
#else
    (void) string;
    (void) filepath;
    perror("pm_string_file_init is not implemented for this platform");
    return false;
#endif
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

    uint8_t *memory = xmalloc(length);
    if (!memory) return;

    pm_string_owned_init(string, memory, length);
    memcpy((void *) string->source, source, length);
}

/**
 * Compare the underlying lengths and bytes of two strings. Returns 0 if the
 * strings are equal, a negative number if the left string is less than the
 * right string, and a positive number if the left string is greater than the
 * right string.
 */
int
pm_string_compare(const pm_string_t *left, const pm_string_t *right) {
    size_t left_length = pm_string_length(left);
    size_t right_length = pm_string_length(right);

    if (left_length < right_length) {
        return -1;
    } else if (left_length > right_length) {
        return 1;
    }

    return memcmp(pm_string_source(left), pm_string_source(right), left_length);
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
        xfree(memory);
#ifdef PRISM_HAS_MMAP
    } else if (string->type == PM_STRING_MAPPED && string->length) {
#if defined(_WIN32)
        UnmapViewOfFile(memory);
#elif defined(_POSIX_MAPPED_FILES)
        munmap(memory, string->length);
#endif
#endif /* PRISM_HAS_MMAP */
    }
}
