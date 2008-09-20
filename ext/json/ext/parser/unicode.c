#include "unicode.h"

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

char *JSON_convert_UTF16_to_UTF8 (
        VALUE buffer,
        char *source,
        char *sourceEnd,
        ConversionFlags flags)
{
    UTF16 *tmp, *tmpPtr, *tmpEnd;
    char buf[5];
    long n = 0, i;
    char *p = source - 1;

    while (p < sourceEnd && p[0] == '\\' && p[1] == 'u') {
        p += 6;
        n++;
    }
    p = source + 1;
    buf[4] = 0;
    tmpPtr = tmp = ALLOC_N(UTF16, n);
    tmpEnd = tmp + n;
    for (i = 0; i < n; i++) {
        buf[0] = *p++;
        buf[1] = *p++;
        buf[2] = *p++;
        buf[3] = *p++;
        tmpPtr[i] = strtol(buf, NULL, 16);
        p += 2;
    }

    while (tmpPtr < tmpEnd) {
        UTF32 ch;
        unsigned short bytesToWrite = 0;
        const UTF32 byteMask = 0xBF;
        const UTF32 byteMark = 0x80; 
        ch = *tmpPtr++;
        /* If we have a surrogate pair, convert to UTF32 first. */
        if (ch >= UNI_SUR_HIGH_START && ch <= UNI_SUR_HIGH_END) {
            /* If the 16 bits following the high surrogate are in the source
             * buffer... */
            if (tmpPtr < tmpEnd) {
                UTF32 ch2 = *tmpPtr;
                /* If it's a low surrogate, convert to UTF32. */
                if (ch2 >= UNI_SUR_LOW_START && ch2 <= UNI_SUR_LOW_END) {
                    ch = ((ch - UNI_SUR_HIGH_START) << halfShift)
                        + (ch2 - UNI_SUR_LOW_START) + halfBase;
                    ++tmpPtr;
                } else if (flags == strictConversion) { /* it's an unpaired high surrogate */
                    free(tmp);
                    rb_raise(rb_path2class("JSON::ParserError"),
                            "source sequence is illegal/malformed near %s", source);
                }
            } else { /* We don't have the 16 bits following the high surrogate. */
                free(tmp);
                rb_raise(rb_path2class("JSON::ParserError"),
                    "partial character in source, but hit end near %s", source);
                break;
            }
        } else if (flags == strictConversion) {
            /* UTF-16 surrogate values are illegal in UTF-32 */
            if (ch >= UNI_SUR_LOW_START && ch <= UNI_SUR_LOW_END) {
                free(tmp);
                rb_raise(rb_path2class("JSON::ParserError"),
                    "source sequence is illegal/malformed near %s", source);
            }
        }
        /* Figure out how many bytes the result will require */
        if (ch < (UTF32) 0x80) {
            bytesToWrite = 1;
        } else if (ch < (UTF32) 0x800) {
            bytesToWrite = 2;
        } else if (ch < (UTF32) 0x10000) {
            bytesToWrite = 3;
        } else if (ch < (UTF32) 0x110000) {
            bytesToWrite = 4;
        } else {
            bytesToWrite = 3;
            ch = UNI_REPLACEMENT_CHAR;
        }

        buf[0] = 0;
        buf[1] = 0;
        buf[2] = 0;
        buf[3] = 0;
        p = buf + bytesToWrite;
        switch (bytesToWrite) { /* note: everything falls through. */
            case 4: *--p = (UTF8) ((ch | byteMark) & byteMask); ch >>= 6;
            case 3: *--p = (UTF8) ((ch | byteMark) & byteMask); ch >>= 6;
            case 2: *--p = (UTF8) ((ch | byteMark) & byteMask); ch >>= 6;
            case 1: *--p = (UTF8) (ch | firstByteMark[bytesToWrite]);
        }
        rb_str_buf_cat(buffer, p, bytesToWrite);
    }
    free(tmp);
    source += 5 + (n - 1) * 6;
    return source;
}
