#include "prism/internal/memchr.h"

#include "prism/compiler/accel.h"
#include "prism/compiler/inline.h"
#include "prism/internal/bit.h"

#include <stdint.h>

#define TRAILING_BYTE_MINIMUM 0x40

static PRISM_INLINE const uint8_t *
pm_memchr_scalar(const uint8_t *source, uint8_t byte, size_t length) {
    for (size_t index = 0; index < length; index++) {
        if (source[index] == byte) return source + index;
    }

    return NULL;
}

#if defined(PRISM_HAS_NEON)
#include <arm_neon.h>

const uint8_t *
pm_memchr(const uint8_t *source, uint8_t byte, size_t length) {
    const uint8x16_t needle = vdupq_n_u8(byte);

    /* Check four vectors per iteration. When any byte matches, the loop below
     * finds the first match in source order. */
    while (length >= 64) {
        uint8x16_t matches = vceqq_u8(vld1q_u8(source), needle);
        matches = vorrq_u8(matches, vceqq_u8(vld1q_u8(source + 16), needle));
        matches = vorrq_u8(matches, vceqq_u8(vld1q_u8(source + 32), needle));
        matches = vorrq_u8(matches, vceqq_u8(vld1q_u8(source + 48), needle));
        if (vmaxvq_u8(matches)) break;

        source += 64;
        length -= 64;
    }

    while (length >= 16) {
        uint8x16_t matches = vceqq_u8(vld1q_u8(source), needle);
        if (vmaxvq_u8(matches)) {
            /* Keep four bits per byte, with the first byte in the low nibble. */
            uint8x8_t nibbles = vshrn_n_u16(vreinterpretq_u16_u8(matches), 4);
            uint64_t mask = vget_lane_u64(vreinterpret_u64_u8(nibbles), 0);
            return source + pm_ctzll(mask) / 4;
        }

        source += 16;
        length -= 16;
    }

    if (length >= 8 && !vmaxv_u8(vceq_u8(vld1_u8(source), vget_low_u8(needle)))) {
        source += 8;
        length -= 8;
    }

    return pm_memchr_scalar(source, byte, length);
}

#elif defined(PRISM_HAS_SSE2)
#include <emmintrin.h>

static PRISM_INLINE __m128i
pm_memchr_sse2_compare(const uint8_t *source, __m128i needle) {
    return _mm_cmpeq_epi8(_mm_loadu_si128((const __m128i *) source), needle);
}

static PRISM_INLINE const uint8_t *
pm_memchr_sse2_16(const uint8_t *source, __m128i needle) {
    unsigned matches = (unsigned) _mm_movemask_epi8(pm_memchr_sse2_compare(source, needle));
    return matches ? source + pm_ctzll(matches) : NULL;
}

const uint8_t *
pm_memchr(const uint8_t *source, uint8_t byte, size_t length) {
    const __m128i needle = _mm_set1_epi8((char) byte);

    if (length >= 16) {
        const uint8_t *last = source + (length - 16);

        /* Skip 64 bytes per mask until a block contains a match. */
        while (length >= 64) {
            __m128i matches = pm_memchr_sse2_compare(source, needle);
            matches = _mm_or_si128(matches, pm_memchr_sse2_compare(source + 16, needle));
            matches = _mm_or_si128(matches, pm_memchr_sse2_compare(source + 32, needle));
            matches = _mm_or_si128(matches, pm_memchr_sse2_compare(source + 48, needle));
            if (_mm_movemask_epi8(matches)) break;

            source += 64;
            length -= 64;
        }

        while (source < last) {
            const uint8_t *match = pm_memchr_sse2_16(source, needle);
            if (match) return match;
            source += 16;
        }

        /* The final vector can overlap a vector we already checked. */
        return pm_memchr_sse2_16(last, needle);
    }

    if (length >= 8) {
        /* Pack the overlapping first and last eight bytes into one vector. */
        const uint8_t *last = source + (length - 8);
        __m128i chunk = _mm_unpacklo_epi64(
            _mm_loadl_epi64((const __m128i *) source),
            _mm_loadl_epi64((const __m128i *) last)
        );
        unsigned matches = (unsigned) _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, needle));
        if (!matches) return NULL;

        unsigned index = pm_ctzll(matches);
        return index < 8 ? source + index : last + (index - 8);
    }

    return pm_memchr_scalar(source, byte, length);
}

#elif defined(PRISM_HAS_SWAR)
#include <string.h>

const uint8_t *
pm_memchr(const uint8_t *source, uint8_t byte, size_t length) {
    const uint64_t ones = UINT64_C(0x0101010101010101);
    const uint64_t high_bits = UINT64_C(0x8080808080808080);
    const uint64_t needle = byte * ones;

    while (length >= sizeof(uint64_t)) {
        uint64_t word;
        memcpy(&word, source, sizeof(word));

        /* XOR makes matching bytes zero. Check for a zero byte in the word. */
        uint64_t diff = word ^ needle;
        if ((diff - ones) & ~diff & high_bits) break;

        source += sizeof(word);
        length -= sizeof(word);
    }

    return pm_memchr_scalar(source, byte, length);
}

#else

const uint8_t *
pm_memchr(const uint8_t *source, uint8_t byte, size_t length) {
    return pm_memchr_scalar(source, byte, length);
}

#endif

/**
 * Find an ASCII delimiter at a character boundary in the given encoding.
 * Scan one character at a time when the delimiter could be a trailing byte.
 */
const uint8_t *
pm_memchr_boundary(const uint8_t *source, uint8_t byte, size_t length, const pm_encoding_t *encoding) {
    if (encoding != PM_ENCODING_UTF_8_ENTRY && pm_encoding_multibyte_p(encoding) && byte >= TRAILING_BYTE_MINIMUM) {
        size_t index = 0;

        while (index < length) {
            if (source[index] == byte) {
                return source + index;
            }

            size_t width = pm_encoding_char_width(encoding, source + index, (ptrdiff_t) (length - index));
            if (!width) {
                return NULL;
            }

            index += width;
        }

        return NULL;
    } else {
        return pm_memchr(source, byte, length);
    }
}
