#ifndef YARP_PACK_H
#define YARP_PACK_H

#include "yarp/defines.h"

#include <stdint.h>
#include <stdlib.h>

typedef enum yp_pack_version {
    YP_PACK_VERSION_3_2_0
} yp_pack_version;

typedef enum yp_pack_variant {
    YP_PACK_VARIANT_PACK,
    YP_PACK_VARIANT_UNPACK
} yp_pack_variant;

typedef enum yp_pack_type {
    YP_PACK_SPACE,
    YP_PACK_COMMENT,
    YP_PACK_INTEGER,
    YP_PACK_UTF8,
    YP_PACK_BER,
    YP_PACK_FLOAT,
    YP_PACK_STRING_SPACE_PADDED,
    YP_PACK_STRING_NULL_PADDED,
    YP_PACK_STRING_NULL_TERMINATED,
    YP_PACK_STRING_MSB,
    YP_PACK_STRING_LSB,
    YP_PACK_STRING_HEX_HIGH,
    YP_PACK_STRING_HEX_LOW,
    YP_PACK_STRING_UU,
    YP_PACK_STRING_MIME,
    YP_PACK_STRING_BASE64,
    YP_PACK_STRING_FIXED,
    YP_PACK_STRING_POINTER,
    YP_PACK_MOVE,
    YP_PACK_BACK,
    YP_PACK_NULL,
    YP_PACK_END
} yp_pack_type;

typedef enum yp_pack_signed {
    YP_PACK_UNSIGNED,
    YP_PACK_SIGNED,
    YP_PACK_SIGNED_NA
} yp_pack_signed;

typedef enum yp_pack_endian {
    YP_PACK_AGNOSTIC_ENDIAN,
    YP_PACK_LITTLE_ENDIAN,      // aka 'VAX', or 'V'
    YP_PACK_BIG_ENDIAN,         // aka 'network', or 'N'
    YP_PACK_NATIVE_ENDIAN,
    YP_PACK_ENDIAN_NA
} yp_pack_endian;

typedef enum yp_pack_size {
    YP_PACK_SIZE_SHORT,
    YP_PACK_SIZE_INT,
    YP_PACK_SIZE_LONG,
    YP_PACK_SIZE_LONG_LONG,
    YP_PACK_SIZE_8,
    YP_PACK_SIZE_16,
    YP_PACK_SIZE_32,
    YP_PACK_SIZE_64,
    YP_PACK_SIZE_P,
    YP_PACK_SIZE_NA
} yp_pack_size;

typedef enum yp_pack_length_type {
    YP_PACK_LENGTH_FIXED,
    YP_PACK_LENGTH_MAX,
    YP_PACK_LENGTH_RELATIVE,  // special case for unpack @*
    YP_PACK_LENGTH_NA
} yp_pack_length_type;

typedef enum yp_pack_encoding {
    YP_PACK_ENCODING_START,
    YP_PACK_ENCODING_ASCII_8BIT,
    YP_PACK_ENCODING_US_ASCII,
    YP_PACK_ENCODING_UTF_8
} yp_pack_encoding;

typedef enum yp_pack_result {
    YP_PACK_OK,
    YP_PACK_ERROR_UNSUPPORTED_DIRECTIVE,
    YP_PACK_ERROR_UNKNOWN_DIRECTIVE,
    YP_PACK_ERROR_LENGTH_TOO_BIG,
    YP_PACK_ERROR_BANG_NOT_ALLOWED,
    YP_PACK_ERROR_DOUBLE_ENDIAN
} yp_pack_result;

// Parse a single directive from a pack or unpack format string.
//
// Parameters:
//  - [in] yp_pack_version version    the version of Ruby
//  - [in] yp_pack_variant variant    pack or unpack
//  - [in out] const char **format    the start of the next directive to parse
//      on calling, and advanced beyond the parsed directive on return, or as
//      much of it as was consumed until an error was encountered
//  - [in] const char *format_end     the end of the format string
//  - [out] yp_pack_type *type        the type of the directive
//  - [out] yp_pack_signed *signed_type
//                                    whether the value is signed
//  - [out] yp_pack_endian *endian    the endianness of the value
//  - [out] yp_pack_size *size        the size of the value
//  - [out] yp_pack_length_type *length_type
//                                    what kind of length is specified
//  - [out] size_t *length            the length of the directive
//  - [in out] yp_pack_encoding *encoding
//                                    takes the current encoding of the string
//      which would result from parsing the whole format string, and returns a
//      possibly changed directive - the encoding should be
//      YP_PACK_ENCODING_START when yp_pack_parse is called for the first
//      directive in a format string
//
// Return:
//  - YP_PACK_OK on success
//  - YP_PACK_ERROR_* on error
//
// Notes:
//   Consult Ruby documentation for the meaning of directives.
YP_EXPORTED_FUNCTION yp_pack_result
yp_pack_parse(
    yp_pack_variant variant_arg,
    const char **format,
    const char *format_end,
    yp_pack_type *type,
    yp_pack_signed *signed_type,
    yp_pack_endian *endian,
    yp_pack_size *size,
    yp_pack_length_type *length_type,
    uint64_t *length,
    yp_pack_encoding *encoding
);

// YARP abstracts sizes away from the native system - this converts an abstract
// size to a native size.
YP_EXPORTED_FUNCTION size_t yp_size_to_native(yp_pack_size size);

#endif
