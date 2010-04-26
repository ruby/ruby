
#ifndef _PARSER_UNICODE_H_
#define _PARSER_UNICODE_H_

#include "ruby.h"

typedef unsigned long	UTF32;	/* at least 32 bits */
typedef unsigned short	UTF16;	/* at least 16 bits */
typedef unsigned char	UTF8;	/* typically 8 bits */

#define UNI_REPLACEMENT_CHAR (UTF32)0x0000FFFD
#define UNI_MAX_BMP (UTF32)0x0000FFFF
#define UNI_MAX_UTF16 (UTF32)0x0010FFFF
#define UNI_MAX_UTF32 (UTF32)0x7FFFFFFF
#define UNI_MAX_LEGAL_UTF32 (UTF32)0x0010FFFF

#define UNI_SUR_HIGH_START  (UTF32)0xD800
#define UNI_SUR_HIGH_END    (UTF32)0xDBFF
#define UNI_SUR_LOW_START   (UTF32)0xDC00
#define UNI_SUR_LOW_END     (UTF32)0xDFFF

static const int halfShift  = 10; /* used for shifting by 10 bits */

static const UTF32 halfBase = 0x0010000UL;
static const UTF32 halfMask = 0x3FFUL;

typedef enum {
	conversionOK = 0, 	/* conversion successful */
	sourceExhausted,	/* partial character in source, but hit end */
	targetExhausted,	/* insuff. room in target for conversion */
	sourceIllegal		/* source sequence is illegal/malformed */
} ConversionResult;

typedef enum {
	strictConversion = 0,
	lenientConversion
} ConversionFlags;

char *JSON_convert_UTF16_to_UTF8 (
    VALUE buffer,
    char *source,
    char *sourceEnd,
		ConversionFlags flags);

#ifndef RARRAY_PTR
#define RARRAY_PTR(ARRAY) RARRAY(ARRAY)->ptr
#endif
#ifndef RARRAY_LEN
#define RARRAY_LEN(ARRAY) RARRAY(ARRAY)->len
#endif
#ifndef RSTRING_PTR
#define RSTRING_PTR(string) RSTRING(string)->ptr
#endif
#ifndef RSTRING_LEN
#define RSTRING_LEN(string) RSTRING(string)->len
#endif

#endif
