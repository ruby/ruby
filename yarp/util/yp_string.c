#include "yarp/util/yp_string.h"

// The following headers are necessary to read files using demand paging.
#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

// Initialize a shared string that is based on initial input.
void
yp_string_shared_init(yp_string_t *string, const char *start, const char *end) {
    *string = (yp_string_t) {
        .type = YP_STRING_SHARED,
        .as.shared = {
            .start = start,
            .end = end
        }
    };
}

// Initialize an owned string that is responsible for freeing allocated memory.
void
yp_string_owned_init(yp_string_t *string, char *source, size_t length) {
    *string = (yp_string_t) {
        .type = YP_STRING_OWNED,
        .as.owned = {
            .source = source,
            .length = length
        }
    };
}

// Initialize a constant string that doesn't own its memory source.
void
yp_string_constant_init(yp_string_t *string, const char *source, size_t length) {
    *string = (yp_string_t) {
        .type = YP_STRING_CONSTANT,
        .as.constant = {
            .source = source,
            .length = length
        }
    };
}

static void
yp_string_mapped_init_internal(yp_string_t *string, char *source, size_t length) {
    *string = (yp_string_t) {
        .type = YP_STRING_MAPPED,
        .as.mapped = {
            .source = source,
            .length = length
        }
    };
}

// Returns the memory size associated with the string.
size_t
yp_string_memsize(const yp_string_t *string) {
    size_t size = sizeof(yp_string_t);
    if (string->type == YP_STRING_OWNED) {
        size += string->as.owned.length;
    }
    return size;
}

// Ensure the string is owned. If it is not, then reinitialize it as owned and
// copy over the previous source.
void
yp_string_ensure_owned(yp_string_t *string) {
    if (string->type == YP_STRING_OWNED) return;

    size_t length = yp_string_length(string);
    const char *source = yp_string_source(string);

    yp_string_owned_init(string, malloc(length), length);
    memcpy(string->as.owned.source, source, length);
}

// Returns the length associated with the string.
YP_EXPORTED_FUNCTION size_t
yp_string_length(const yp_string_t *string) {
    if (string->type == YP_STRING_SHARED) {
        return (size_t) (string->as.shared.end - string->as.shared.start);
    } else {
        return string->as.owned.length;
    }
}

// Returns the start pointer associated with the string.
YP_EXPORTED_FUNCTION const char *
yp_string_source(const yp_string_t *string) {
    if (string->type == YP_STRING_SHARED) {
        return string->as.shared.start;
    } else {
        return string->as.owned.source;
    }
}

// Free the associated memory of the given string.
YP_EXPORTED_FUNCTION void
yp_string_free(yp_string_t *string) {
    if (string->type == YP_STRING_OWNED) {
        free(string->as.owned.source);
    } else if (string->type == YP_STRING_MAPPED && string->as.mapped.length) {
        void *memory = (void *) string->as.mapped.source;
        #if defined(_WIN32)
        UnmapViewOfFile(memory);
        #elif defined(HAVE_MMAP)
        munmap(memory, string->as.mapped.length);
        #else
        free(memory);
        #endif
    }
}

bool
yp_string_mapped_init(yp_string_t *string, const char *filepath) {
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
        yp_string_mapped_init_internal(string, "", 0);
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
    char *source = (char *) MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
    CloseHandle(mapping);
    CloseHandle(file);

    if (source == NULL) {
        perror("MapViewOfFile failed");
        return false;
    }

    yp_string_mapped_init_internal(string, source, (size_t) file_size);
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
    char *source = NULL;

    if (size == 0) {
        close(fd);
        yp_string_mapped_init_internal(string, "", 0);
        return true;
    }

#ifdef HAVE_MMAP
    source = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (source == MAP_FAILED) {
        perror("Map failed");
        return false;
    }
#else
    source = malloc(size);
    if (source == NULL) {
        return false;
    }

    ssize_t read_size = read(fd, (void *) source, size);
    if (read_size < 0 || (size_t)read_size != size) {
        perror("Read size is incorrect");
        free((void *) source);
        return false;
    }
#endif

    close(fd);
    yp_string_mapped_init_internal(string, source, size);
    return true;
#endif
}
