#include "unicode.h"

#define unicode_escape(buffer, character)          \
    snprintf(buf, 7, "\\u%04x", (unsigned int) (character)); \
         rb_str_buf_cat(buffer, buf, 6);

/*
 * Copyright 2001-2004 Unicode, Inc.
 * 
 * Disclaimer
 * 
 * This source code is provided as is by Unicode, Inc. No claims are
 * made as to fitness for any particular purpose. No warranties of any
 * kind are expressed or implied. The recipient agrees to determine
 * applicability of information provided. If this file has been
 * purchased on magnetic or optical media from Unicode, Inc., the
 * sole remedy for any claim will be exchange of defective media
 * within 90 days of receipt.
 * 
 * Limitations on Rights to Redistribute This Code
 * 
 * Unicode, Inc. hereby grants the right to freely use the information
 * supplied in this file in the creation of products supporting the
 * Unicode Standard, and to make copies of this file in any form
 * for internal or external distribution as long as this notice
 * remains attached.
 */

/*
 * Index into the table below with the first byte of a UTF-8 sequence to
 * get the number of trailing bytes that are supposed to follow it.
 * Note that *legal* UTF-8 values can't have 4 or 5-bytes. The table is
 * left as-is for anyone who may want to do such conversion, which was
 * allowed in earlier algorithms.
 */
static const char trailingBytesForUTF8[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
};

/*
 * Magic values subtracted from a buffer value during UTF8 conversion.
 * This table contains as many values as there might be trailing bytes
 * in a UTF-8 sequence.
 */
static const UTF32 offsetsFromUTF8[6] = { 0x00000000UL, 0x00003080UL, 0x000E2080UL, 
		     0x03C82080UL, 0xFA082080UL, 0x82082080UL };

/*
 * Once the bits are split out into bytes of UTF-8, this is a mask OR-ed
 * into the first byte, depending on how many bytes follow.  There are
 * as many entries in this table as there are UTF-8 sequence types.
 * (I.e., one byte sequence, two byte... etc.). Remember that sequencs
 * for *legal* UTF-8 will be 4 or fewer bytes total.
 */
static const UTF8 firstByteMark[7] = { 0x00, 0x00, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC };

/*
 * Utility routine to tell whether a sequence of bytes is legal UTF-8.
 * This must be called with the length pre-determined by the first byte.
 * If not calling this from ConvertUTF8to*, then the length can be set by:
 *  length = trailingBytesForUTF8[*source]+1;
 * and the sequence is illegal right away if there aren't that many bytes
 * available.
 * If presented with a length > 4, this returns 0.  The Unicode
 * definition of UTF-8 goes up to 4-byte sequences.
 */

inline static unsigned char isLegalUTF8(const UTF8 *source, int length)
{
    UTF8 a;
    const UTF8 *srcptr = source+length;
    switch (length) {
        default: return 0;
                 /* Everything else falls through when "1"... */
        case 4: if ((a = (*--srcptr)) < 0x80 || a > 0xBF) return 0;
        case 3: if ((a = (*--srcptr)) < 0x80 || a > 0xBF) return 0;
        case 2: if ((a = (*--srcptr)) > 0xBF) return 0;

                    switch (*source) {
                        /* no fall-through in this inner switch */
                        case 0xE0: if (a < 0xA0) return 0; break;
                        case 0xED: if (a > 0x9F) return 0; break;
                        case 0xF0: if (a < 0x90) return 0; break;
                        case 0xF4: if (a > 0x8F) return 0; break;
                        default:   if (a < 0x80) return 0;
                    }

        case 1: if (*source >= 0x80 && *source < 0xC2) return 0;
    }
    if (*source > 0xF4) return 0;
    return 1;
}

void JSON_convert_UTF8_to_JSON(VALUE buffer, VALUE string, ConversionFlags flags)
{
    char buf[7];
    const UTF8* source = (UTF8 *) RSTRING_PTR(string);
    const UTF8* sourceEnd = source + RSTRING_LEN(string);

    while (source < sourceEnd) {
        UTF32 ch = 0;
        unsigned short extraBytesToRead = trailingBytesForUTF8[*source];
        if (source + extraBytesToRead >= sourceEnd) {
            rb_raise(rb_path2class("JSON::GeneratorError"),
                    "partial character in source, but hit end");
        }
        if (!isLegalUTF8(source, extraBytesToRead+1)) {
            rb_raise(rb_path2class("JSON::GeneratorError"),
                    "source sequence is illegal/malformed");
        }
        /*
         * The cases all fall through. See "Note A" below.
         */
        switch (extraBytesToRead) {
            case 5: ch += *source++; ch <<= 6; /* remember, illegal UTF-8 */
            case 4: ch += *source++; ch <<= 6; /* remember, illegal UTF-8 */
            case 3: ch += *source++; ch <<= 6;
            case 2: ch += *source++; ch <<= 6;
            case 1: ch += *source++; ch <<= 6;
            case 0: ch += *source++;
        }
        ch -= offsetsFromUTF8[extraBytesToRead];

        if (ch <= UNI_MAX_BMP) { /* Target is a character <= 0xFFFF */
            /* UTF-16 surrogate values are illegal in UTF-32 */
            if (ch >= UNI_SUR_HIGH_START && ch <= UNI_SUR_LOW_END) {
                if (flags == strictConversion) {
                    source -= (extraBytesToRead+1); /* return to the illegal value itself */
                    rb_raise(rb_path2class("JSON::GeneratorError"),
                        "source sequence is illegal/malformed");
                } else {
                    unicode_escape(buffer, UNI_REPLACEMENT_CHAR);
                }
            } else {
                /* normal case */
                if (ch == '"') {
                    rb_str_buf_cat2(buffer, "\\\"");
                } else if (ch == '\\') {
                    rb_str_buf_cat2(buffer, "\\\\");
                } else if (ch >= 0x20 && ch <= 0x7f) {
                    rb_str_buf_cat(buffer, (char *) source - 1, 1);
                } else if (ch == '\n') {
                    rb_str_buf_cat2(buffer, "\\n");
                } else if (ch == '\r') {
                    rb_str_buf_cat2(buffer, "\\r");
                } else if (ch == '\t') {
                    rb_str_buf_cat2(buffer, "\\t");
                } else if (ch == '\f') {
                    rb_str_buf_cat2(buffer, "\\f");
                } else if (ch == '\b') {
                    rb_str_buf_cat2(buffer, "\\b");
                } else if (ch < 0x20) {
                    unicode_escape(buffer, (UTF16) ch);
                } else {
                    unicode_escape(buffer, (UTF16) ch);
                }
            }
        } else if (ch > UNI_MAX_UTF16) {
            if (flags == strictConversion) {
                source -= (extraBytesToRead+1); /* return to the start */
                rb_raise(rb_path2class("JSON::GeneratorError"),
                        "source sequence is illegal/malformed");
            } else {
                unicode_escape(buffer, UNI_REPLACEMENT_CHAR);
            }
        } else {
            /* target is a character in range 0xFFFF - 0x10FFFF. */
            ch -= halfBase;
            unicode_escape(buffer, (UTF16)((ch >> halfShift) + UNI_SUR_HIGH_START));
            unicode_escape(buffer, (UTF16)((ch & halfMask) + UNI_SUR_LOW_START));
        }
    }
}
