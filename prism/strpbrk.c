#include "prism/internal/strpbrk.h"

#include "prism/attribute/inline.h"
#include "prism/attribute/unused.h"
#include "prism/internal/accel.h"
#include "prism/internal/bit.h"
#include "prism/internal/diagnostic.h"
#include "prism/internal/encoding.h"

#include <assert.h>
#include <stdbool.h>
#include <string.h>

/**
 * Add an invalid multibyte character error to the parser.
 */
static PRISM_INLINE void
pm_strpbrk_invalid_multibyte_character(pm_parser_t *parser, uint32_t start, uint32_t length) {
    pm_diagnostic_list_append_format(&parser->metadata_arena, &parser->error_list, start, length, PM_ERR_INVALID_MULTIBYTE_CHARACTER, parser->start[start]);
}

/**
 * Set the explicit encoding for the parser to the current encoding.
 */
static PRISM_INLINE void
pm_strpbrk_explicit_encoding_set(pm_parser_t *parser, uint32_t start, uint32_t length) {
    if (parser->explicit_encoding != NULL) {
        if (parser->explicit_encoding == parser->encoding) {
            // Okay, we already locked to this encoding.
        } else if (parser->explicit_encoding == PM_ENCODING_UTF_8_ENTRY) {
            // Not okay, we already found a Unicode escape sequence and this
            // conflicts.
            pm_diagnostic_list_append_format(&parser->metadata_arena, &parser->error_list, start, length, PM_ERR_MIXED_ENCODING, parser->encoding->name);
        } else {
            // Should not be anything else.
            assert(false && "unreachable");
        }
    }

    parser->explicit_encoding = parser->encoding;
}

/**
 * Scan forward through ASCII bytes looking for a byte that is in the given
 * charset. Returns true if a match was found, storing its offset in *index.
 * Returns false if no match was found, storing the number of ASCII bytes
 * consumed in *index (so the caller can skip past them).
 *
 * All charset characters must be ASCII (< 0x80). The scanner stops at non-ASCII
 * bytes, returning control to the caller's encoding-aware loop.
 *
 * Up to three optimized implementations are selected at compile time, with a
 * no-op fallback for unsupported platforms:
 *   1. NEON — processes 16 bytes per iteration on aarch64.
 *   2. SSSE3 — processes 16 bytes per iteration on x86-64.
 *   3. SWAR — little-endian fallback, processes 8 bytes per iteration.
 */

#if defined(PRISM_HAS_NEON) || defined(PRISM_HAS_SSSE3) || defined(PRISM_HAS_SWAR)

/**
 * Update the cached strpbrk lookup tables if the charset has changed. The
 * parser caches the last charset's precomputed tables so that repeated calls
 * with the same breakpoints (the common case during string/regex/list lexing)
 * skip table construction entirely.
 *
 * Builds three structures:
 *   - low_lut/high_lut: nibble-based lookup tables for SIMD matching (NEON/SSSE3)
 *   - table: 256-bit bitmap for scalar fallback matching (all platforms)
 */
static PRISM_INLINE void
pm_strpbrk_cache_update(pm_parser_t *parser, const uint8_t *charset) {
    // The cache key is the full charset buffer (PM_STRPBRK_CACHE_SIZE bytes).
    // Since it is always NUL-padded, a fixed-size comparison covers both
    // content and length.
    if (memcmp(parser->strpbrk_cache.charset, charset, sizeof(parser->strpbrk_cache.charset)) == 0) return;

    memset(parser->strpbrk_cache.low_lut, 0, sizeof(parser->strpbrk_cache.low_lut));
    memset(parser->strpbrk_cache.high_lut, 0, sizeof(parser->strpbrk_cache.high_lut));
    memset(parser->strpbrk_cache.table, 0, sizeof(parser->strpbrk_cache.table));

    // Always include NUL in the tables. The slow path uses strchr, which
    // always matches NUL (it finds the C string terminator), so NUL is
    // effectively always a breakpoint. Replicating that here lets the fast
    // scanner handle NUL at full speed instead of bailing to the slow path.
    parser->strpbrk_cache.low_lut[0x00] |= (uint8_t) (1 << 0);
    parser->strpbrk_cache.high_lut[0x00] = (uint8_t) (1 << 0);
    parser->strpbrk_cache.table[0] |= (uint64_t) 1;

    size_t charset_len = 0;
    for (const uint8_t *c = charset; *c != '\0'; c++) {
        parser->strpbrk_cache.low_lut[*c & 0x0F] |= (uint8_t) (1 << (*c >> 4));
        parser->strpbrk_cache.high_lut[*c >> 4] = (uint8_t) (1 << (*c >> 4));
        parser->strpbrk_cache.table[*c >> 6] |= (uint64_t) 1 << (*c & 0x3F);
        charset_len++;
    }

    // Store the new charset key, NUL-padded to the full buffer size.
    memcpy(parser->strpbrk_cache.charset, charset, charset_len + 1);
    memset(parser->strpbrk_cache.charset + charset_len + 1, 0, sizeof(parser->strpbrk_cache.charset) - charset_len - 1);
}

#endif

#if defined(PRISM_HAS_NEON)
#include <arm_neon.h>

static PRISM_INLINE bool
scan_strpbrk_ascii(pm_parser_t *parser, const uint8_t *source, size_t maximum, const uint8_t *charset, size_t *index) {
    pm_strpbrk_cache_update(parser, charset);

    uint8x16_t low_lut = vld1q_u8(parser->strpbrk_cache.low_lut);
    uint8x16_t high_lut = vld1q_u8(parser->strpbrk_cache.high_lut);
    uint8x16_t mask_0f = vdupq_n_u8(0x0F);
    uint8x16_t mask_80 = vdupq_n_u8(0x80);

    size_t idx = 0;

    while (idx + 16 <= maximum) {
        uint8x16_t v = vld1q_u8(source + idx);

        // If any byte has the high bit set, we have non-ASCII data.
        // Return to let the caller's encoding-aware loop handle it.
        if (vmaxvq_u8(vandq_u8(v, mask_80)) != 0) break;

        uint8x16_t lo_class = vqtbl1q_u8(low_lut, vandq_u8(v, mask_0f));
        uint8x16_t hi_class = vqtbl1q_u8(high_lut, vshrq_n_u8(v, 4));
        uint8x16_t matched = vtstq_u8(lo_class, hi_class);

        if (vmaxvq_u8(matched) == 0) {
            idx += 16;
            continue;
        }

        // Find the position of the first matching byte.
        uint64_t lo64 = vgetq_lane_u64(vreinterpretq_u64_u8(matched), 0);
        if (lo64 != 0) {
            *index = idx + pm_ctzll(lo64) / 8;
            return true;
        }
        uint64_t hi64 = vgetq_lane_u64(vreinterpretq_u64_u8(matched), 1);
        *index = idx + 8 + pm_ctzll(hi64) / 8;
        return true;
    }

    // Scalar tail for remaining < 16 ASCII bytes.
    while (idx < maximum && source[idx] < 0x80) {
        uint8_t byte = source[idx];
        if (parser->strpbrk_cache.table[byte >> 6] & ((uint64_t) 1 << (byte & 0x3F))) {
            *index = idx;
            return true;
        }
        idx++;
    }

    *index = idx;
    return false;
}

#elif defined(PRISM_HAS_SSSE3)
#include <tmmintrin.h>

static PRISM_INLINE bool
scan_strpbrk_ascii(pm_parser_t *parser, const uint8_t *source, size_t maximum, const uint8_t *charset, size_t *index) {
    pm_strpbrk_cache_update(parser, charset);

    __m128i low_lut = _mm_loadu_si128((const __m128i *) parser->strpbrk_cache.low_lut);
    __m128i high_lut = _mm_loadu_si128((const __m128i *) parser->strpbrk_cache.high_lut);
    __m128i mask_0f = _mm_set1_epi8(0x0F);

    size_t idx = 0;

    while (idx + 16 <= maximum) {
        __m128i v = _mm_loadu_si128((const __m128i *) (source + idx));

        // If any byte has the high bit set, stop.
        if (_mm_movemask_epi8(v) != 0) break;

        // Nibble-based classification using pshufb (SSSE3), same as NEON
        // vqtbl1q_u8. A byte matches iff (low_lut[lo_nib] & high_lut[hi_nib]) != 0.
        __m128i lo_class = _mm_shuffle_epi8(low_lut, _mm_and_si128(v, mask_0f));
        __m128i hi_class = _mm_shuffle_epi8(high_lut, _mm_and_si128(_mm_srli_epi16(v, 4), mask_0f));
        __m128i matched = _mm_and_si128(lo_class, hi_class);

        // Check if any byte matched.
        int mask = _mm_movemask_epi8(_mm_cmpeq_epi8(matched, _mm_setzero_si128()));

        if (mask == 0xFFFF) {
            // All bytes were zero — no match in this chunk.
            idx += 16;
            continue;
        }

        // Find the first matching byte (first non-zero in matched).
        *index = idx + pm_ctzll((uint64_t) (~mask & 0xFFFF));
        return true;
    }

    // Scalar tail.
    while (idx < maximum && source[idx] < 0x80) {
        uint8_t byte = source[idx];
        if (parser->strpbrk_cache.table[byte >> 6] & ((uint64_t) 1 << (byte & 0x3F))) {
            *index = idx;
            return true;
        }
        idx++;
    }

    *index = idx;
    return false;
}

#elif defined(PRISM_HAS_SWAR)

static PRISM_INLINE bool
scan_strpbrk_ascii(pm_parser_t *parser, const uint8_t *source, size_t maximum, const uint8_t *charset, size_t *index) {
    pm_strpbrk_cache_update(parser, charset);

    static const uint64_t highs = 0x8080808080808080ULL;
    size_t idx = 0;

    while (idx + 8 <= maximum) {
        uint64_t word;
        memcpy(&word, source + idx, 8);

        // Bail on any non-ASCII byte.
        if (word & highs) break;

        // Check each byte against the charset table.
        for (size_t j = 0; j < 8; j++) {
            uint8_t byte = source[idx + j];
            if (parser->strpbrk_cache.table[byte >> 6] & ((uint64_t) 1 << (byte & 0x3F))) {
                *index = idx + j;
                return true;
            }
        }

        idx += 8;
    }

    // Scalar tail.
    while (idx < maximum && source[idx] < 0x80) {
        uint8_t byte = source[idx];
        if (parser->strpbrk_cache.table[byte >> 6] & ((uint64_t) 1 << (byte & 0x3F))) {
            *index = idx;
            return true;
        }
        idx++;
    }

    *index = idx;
    return false;
}

#else

static PRISM_INLINE bool
scan_strpbrk_ascii(PRISM_ATTRIBUTE_UNUSED pm_parser_t *parser, PRISM_ATTRIBUTE_UNUSED const uint8_t *source, PRISM_ATTRIBUTE_UNUSED size_t maximum, PRISM_ATTRIBUTE_UNUSED const uint8_t *charset, size_t *index) {
    *index = 0;
    return false;
}

#endif

/**
 * This is the default path.
 */
static PRISM_INLINE const uint8_t *
pm_strpbrk_utf8(pm_parser_t *parser, const uint8_t *source, const uint8_t *charset, size_t index, size_t maximum, bool validate) {
    while (index < maximum) {
        if (strchr((const char *) charset, source[index]) != NULL) {
            return source + index;
        }

        if (source[index] < 0x80) {
            index++;
        } else {
            size_t width = pm_encoding_utf_8_char_width(source + index, (ptrdiff_t) (maximum - index));

            if (width > 0) {
                index += width;
            } else if (!validate) {
                index++;
            } else {
                // At this point we know we have an invalid multibyte character.
                // We'll walk forward as far as we can until we find the next
                // valid character so that we don't spam the user with a ton of
                // the same kind of error.
                const size_t start = index;

                do {
                    index++;
                } while (index < maximum && pm_encoding_utf_8_char_width(source + index, (ptrdiff_t) (maximum - index)) == 0);

                pm_strpbrk_invalid_multibyte_character(parser, (uint32_t) ((source + start) - parser->start), (uint32_t) (index - start));
            }
        }
    }

    return NULL;
}

/**
 * This is the path when the encoding is ASCII-8BIT.
 */
static PRISM_INLINE const uint8_t *
pm_strpbrk_ascii_8bit(pm_parser_t *parser, const uint8_t *source, const uint8_t *charset, size_t index, size_t maximum, bool validate) {
    while (index < maximum) {
        if (strchr((const char *) charset, source[index]) != NULL) {
            return source + index;
        }

        if (validate && source[index] >= 0x80) pm_strpbrk_explicit_encoding_set(parser, (uint32_t) (source - parser->start), 1);
        index++;
    }

    return NULL;
}

/**
 * This is the slow path that does care about the encoding.
 */
static PRISM_INLINE const uint8_t *
pm_strpbrk_multi_byte(pm_parser_t *parser, const uint8_t *source, const uint8_t *charset, size_t index, size_t maximum, bool validate) {
    const pm_encoding_t *encoding = parser->encoding;

    while (index < maximum) {
        if (strchr((const char *) charset, source[index]) != NULL) {
            return source + index;
        }

        if (source[index] < 0x80) {
            index++;
        } else {
            size_t width = encoding->char_width(source + index, (ptrdiff_t) (maximum - index));
            if (validate) pm_strpbrk_explicit_encoding_set(parser, (uint32_t) (source - parser->start), (uint32_t) width);

            if (width > 0) {
                index += width;
            } else if (!validate) {
                index++;
            } else {
                // At this point we know we have an invalid multibyte character.
                // We'll walk forward as far as we can until we find the next
                // valid character so that we don't spam the user with a ton of
                // the same kind of error.
                const size_t start = index;

                do {
                    index++;
                } while (index < maximum && encoding->char_width(source + index, (ptrdiff_t) (maximum - index)) == 0);

                pm_strpbrk_invalid_multibyte_character(parser, (uint32_t) ((source + start) - parser->start), (uint32_t) (index - start));
            }
        }
    }

    return NULL;
}

/**
 * This is the fast path that does not care about the encoding because we know
 * the encoding only supports single-byte characters.
 */
static PRISM_INLINE const uint8_t *
pm_strpbrk_single_byte(pm_parser_t *parser, const uint8_t *source, const uint8_t *charset, size_t index, size_t maximum, bool validate) {
    const pm_encoding_t *encoding = parser->encoding;

    while (index < maximum) {
        if (strchr((const char *) charset, source[index]) != NULL) {
            return source + index;
        }

        if (source[index] < 0x80 || !validate) {
            index++;
        } else {
            size_t width = encoding->char_width(source + index, (ptrdiff_t) (maximum - index));
            pm_strpbrk_explicit_encoding_set(parser, (uint32_t) (source - parser->start), (uint32_t) width);

            if (width > 0) {
                index += width;
            } else {
                // At this point we know we have an invalid multibyte character.
                // We'll walk forward as far as we can until we find the next
                // valid character so that we don't spam the user with a ton of
                // the same kind of error.
                const size_t start = index;

                do {
                    index++;
                } while (index < maximum && encoding->char_width(source + index, (ptrdiff_t) (maximum - index)) == 0);

                pm_strpbrk_invalid_multibyte_character(parser, (uint32_t) ((source + start) - parser->start), (uint32_t) (index - start));
            }
        }
    }

    return NULL;
}

/**
 * Here we have rolled our own version of strpbrk. The standard library strpbrk
 * has undefined behavior when the source string is not null-terminated. We want
 * to support strings that are not null-terminated because pm_parse does not
 * have the contract that the string is null-terminated. (This is desirable
 * because it means the extension can call pm_parse with the result of a call to
 * mmap).
 *
 * The standard library strpbrk also does not support passing a maximum length
 * to search. We want to support this for the reason mentioned above, but we
 * also don't want it to stop on null bytes. Ruby actually allows null bytes
 * within strings, comments, regular expressions, etc. So we need to be able to
 * skip past them.
 *
 * Finally, we want to support encodings wherein the charset could contain
 * characters that are trailing bytes of multi-byte characters. For example, in
 * Shift_JIS, the backslash character can be a trailing byte. In that case we
 * need to take a slower path and iterate one multi-byte character at a time.
 */
const uint8_t *
pm_strpbrk(pm_parser_t *parser, const uint8_t *source, const uint8_t *charset, ptrdiff_t length, bool validate) {
    if (length <= 0) return NULL;

    size_t maximum = (size_t) length;
    size_t index = 0;
    if (scan_strpbrk_ascii(parser, source, maximum, charset, &index)) return source + index;

    if (!parser->encoding_changed) {
        return pm_strpbrk_utf8(parser, source, charset, index, maximum, validate);
    } else if (parser->encoding == PM_ENCODING_ASCII_8BIT_ENTRY) {
        return pm_strpbrk_ascii_8bit(parser, source, charset, index, maximum, validate);
    } else if (parser->encoding->multibyte) {
        return pm_strpbrk_multi_byte(parser, source, charset, index, maximum, validate);
    } else {
        return pm_strpbrk_single_byte(parser, source, charset, index, maximum, validate);
    }
}
