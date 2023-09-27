#ifndef PRISM_PACK_H
#define PRISM_PACK_H

#include "prism/defines.h"

#include <stdint.h>
#include <stdlib.h>

typedef enum pm_pack_version {
    PM_PACK_VERSION_3_2_0
} pm_pack_version;

typedef enum pm_pack_variant {
    PM_PACK_VARIANT_PACK,
    PM_PACK_VARIANT_UNPACK
} pm_pack_variant;

typedef enum pm_pack_type {
    PM_PACK_SPACE,
    PM_PACK_COMMENT,
    PM_PACK_INTEGER,
    PM_PACK_UTF8,
    PM_PACK_BER,
    PM_PACK_FLOAT,
    PM_PACK_STRING_SPACE_PADDED,
    PM_PACK_STRING_NULL_PADDED,
    PM_PACK_STRING_NULL_TERMINATED,
    PM_PACK_STRING_MSB,
    PM_PACK_STRING_LSB,
    PM_PACK_STRING_HEX_HIGH,
    PM_PACK_STRING_HEX_LOW,
    PM_PACK_STRING_UU,
    PM_PACK_STRING_MIME,
    PM_PACK_STRING_BASE64,
    PM_PACK_STRING_FIXED,
    PM_PACK_STRING_POINTER,
    PM_PACK_MOVE,
    PM_PACK_BACK,
    PM_PACK_NULL,
    PM_PACK_END
} pm_pack_type;

typedef enum pm_pack_signed {
    PM_PACK_UNSIGNED,
    PM_PACK_SIGNED,
    PM_PACK_SIGNED_NA
} pm_pack_signed;

typedef enum pm_pack_endian {
    PM_PACK_AGNOSTIC_ENDIAN,
    PM_PACK_LITTLE_ENDIAN,      // aka 'VAX', or 'V'
    PM_PACK_BIG_ENDIAN,         // aka 'network', or 'N'
    PM_PACK_NATIVE_ENDIAN,
    PM_PACK_ENDIAN_NA
} pm_pack_endian;

typedef enum pm_pack_size {
    PM_PACK_SIZE_SHORT,
    PM_PACK_SIZE_INT,
    PM_PACK_SIZE_LONG,
    PM_PACK_SIZE_LONG_LONG,
    PM_PACK_SIZE_8,
    PM_PACK_SIZE_16,
    PM_PACK_SIZE_32,
    PM_PACK_SIZE_64,
    PM_PACK_SIZE_P,
    PM_PACK_SIZE_NA
} pm_pack_size;

typedef enum pm_pack_length_type {
    PM_PACK_LENGTH_FIXED,
    PM_PACK_LENGTH_MAX,
    PM_PACK_LENGTH_RELATIVE,  // special case for unpack @*
    PM_PACK_LENGTH_NA
} pm_pack_length_type;

typedef enum pm_pack_encoding {
    PM_PACK_ENCODING_START,
    PM_PACK_ENCODING_ASCII_8BIT,
    PM_PACK_ENCODING_US_ASCII,
    PM_PACK_ENCODING_UTF_8
} pm_pack_encoding;

typedef enum pm_pack_result {
    PM_PACK_OK,
    PM_PACK_ERROR_UNSUPPORTED_DIRECTIVE,
    PM_PACK_ERROR_UNKNOWN_DIRECTIVE,
    PM_PACK_ERROR_LENGTH_TOO_BIG,
    PM_PACK_ERROR_BANG_NOT_ALLOWED,
    PM_PACK_ERROR_DOUBLE_ENDIAN
} pm_pack_result;

// Parse a single directive from a pack or unpack format string.
//
// Parameters:
//  - [in] pm_pack_version version    the version of Ruby
//  - [in] pm_pack_variant variant    pack or unpack
//  - [in out] const char **format    the start of the next directive to parse
//      on calling, and advanced beyond the parsed directive on return, or as
//      much of it as was consumed until an error was encountered
//  - [in] const char *format_end     the end of the format string
//  - [out] pm_pack_type *type        the type of the directive
//  - [out] pm_pack_signed *signed_type
//                                    whether the value is signed
//  - [out] pm_pack_endian *endian    the endianness of the value
//  - [out] pm_pack_size *size        the size of the value
//  - [out] pm_pack_length_type *length_type
//                                    what kind of length is specified
//  - [out] size_t *length            the length of the directive
//  - [in out] pm_pack_encoding *encoding
//                                    takes the current encoding of the string
//      which would result from parsing the whole format string, and returns a
//      possibly changed directive - the encoding should be
//      PM_PACK_ENCODING_START when pm_pack_parse is called for the first
//      directive in a format string
//
// Return:
//  - PM_PACK_OK on success
//  - PM_PACK_ERROR_* on error
//
// Notes:
//   Consult Ruby documentation for the meaning of directives.
PRISM_EXPORTED_FUNCTION pm_pack_result
pm_pack_parse(
    pm_pack_variant variant_arg,
    const char **format,
    const char *format_end,
    pm_pack_type *type,
    pm_pack_signed *signed_type,
    pm_pack_endian *endian,
    pm_pack_size *size,
    pm_pack_length_type *length_type,
    uint64_t *length,
    pm_pack_encoding *encoding
);

// prism abstracts sizes away from the native system - this converts an abstract
// size to a native size.
PRISM_EXPORTED_FUNCTION size_t pm_size_to_native(pm_pack_size size);

#endif
