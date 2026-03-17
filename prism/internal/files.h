/**
 * @file internal/files.h
 *
 * Platform detection for mmap and filesystem support.
 */
#ifndef PRISM_INTERNAL_FILES_H
#define PRISM_INTERNAL_FILES_H

/**
 * In general, libc for embedded systems does not support memory-mapped files.
 * If the target platform is POSIX or Windows, we can map a file in memory and
 * read it in a more efficient manner.
 */
#ifdef _WIN32
#   define PRISM_HAS_MMAP
#else
#   include <unistd.h>
#   ifdef _POSIX_MAPPED_FILES
#       define PRISM_HAS_MMAP
#   endif
#endif

/**
 * If PRISM_HAS_NO_FILESYSTEM is defined, then we want to exclude all filesystem
 * related code from the library. All filesystem related code should be guarded
 * by PRISM_HAS_FILESYSTEM.
 */
#ifndef PRISM_HAS_NO_FILESYSTEM
#   define PRISM_HAS_FILESYSTEM
#endif

#endif
