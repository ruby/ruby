#include "ruby.h"
#include "ruby/encoding.h"

static VALUE rb_cCGI;
static ID id_escapeHTML;

#define HTML_ESCAPE_MAX_LEN 6

static const bool html_escape_table[UCHAR_MAX+1] = {
    ['\''] = true,
    ['&'] = true,
    ['"'] = true,
    ['<'] = true,
    ['>'] = true,
};

static inline long
escaped_length(VALUE str)
{
    const long len = RSTRING_LEN(str);
    if (len >= LONG_MAX / HTML_ESCAPE_MAX_LEN) {
        ruby_malloc_size_overflow(len, HTML_ESCAPE_MAX_LEN);
    }
    return len * HTML_ESCAPE_MAX_LEN;
}

#ifdef __clang__
# if __has_builtin(__builtin_ctzll)
#   define HAVE_BUILTIN_CTZLL 1
# else
#   define HAVE_BUILTIN_CTZLL 0
# endif
#elif defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 3))
# define HAVE_BUILTIN_CTZLL 1
#else
# define HAVE_BUILTIN_CTZLL 0
#endif

#ifdef ERB_ENABLE_SIMD
#if defined(__amd64__) || defined(__amd64) || defined(__x86_64__) || defined(__x86_64) || defined(_M_X64) || defined(_M_AMD64)
#ifdef HAVE_X86INTRIN_H
#include <x86intrin.h>
#define HAVE_SIMD 1
#define HAVE_SIMD_SSE2 1
#endif
#endif

#if defined(__aarch64__) || defined(_M_ARM64)
#define HAVE_SIMD 1
#define HAVE_SIMD_NEON 1
#include <arm_neon.h>
#endif
#endif // ERB_ENABLE_SIMD

typedef struct _search_state {
    const unsigned char *cstr;
    const unsigned char *end;

#if defined(HAVE_SIMD_NEON)
    uint64_t matches_bitmap;
#elif defined(HAVE_SIMD_SSE2)
    int matches_bitmap;
#endif
} search_state;

static inline bool
find_next_basic(search_state *search)
{
    while (search->cstr < search->end) {
        if (html_escape_table[*search->cstr]) {
            return true;
        }
        search->cstr++;
    }
    return false;
}

#ifdef HAVE_SIMD_SSE2

static inline int trailing_zeros32(int input)
{
    RUBY_ASSERT(input > 0); // __builtin_ctz(0) is undefined behavior

#if HAVE_BUILTIN_CTZLL
    return __builtin_ctz(input);
#else
    int trailing_zeros = 0;
    int temp = input;
    while ((temp & 1) == 0 && temp > 0) {
        trailing_zeros++;
        temp >>= 1;
    }
    return trailing_zeros;
#endif
}

static inline bool
find_next_match_sse2(search_state *search)
{
    uint32_t trailing_zeros = trailing_zeros32(search->matches_bitmap);
    search->matches_bitmap >>= trailing_zeros;
    search->cstr += trailing_zeros;
    RUBY_ASSERT(search->cstr <= search->end);
    return true;
}

static inline bool
find_next_sse2(search_state *search)
{
    if (search->matches_bitmap) {
        return find_next_match_sse2(search);
    }

    const __m128i single_quote = _mm_set1_epi8('\'');
    const __m128i double_quote = _mm_set1_epi8('"');
    const __m128i ampersand = _mm_set1_epi8('&');
    const __m128i lt = _mm_set1_epi8('<');
    const __m128i gt = _mm_set1_epi8('>');

    while ((size_t)(search->end - search->cstr) >= sizeof(__m128i)) {
        const __m128i bytes = _mm_loadu_si128((__m128i const *)search->cstr);
        const __m128i match1 = _mm_cmpeq_epi8(bytes, single_quote);
        const __m128i match2 = _mm_cmpeq_epi8(bytes, double_quote);
        const __m128i match3 = _mm_cmpeq_epi8(bytes, ampersand);
        const __m128i match4 = _mm_cmpeq_epi8(bytes, lt);
        const __m128i match5 = _mm_cmpeq_epi8(bytes, gt);

        const __m128i mask1 = _mm_or_si128(match1, match2);
        const __m128i mask2 = _mm_or_si128(match3, match4);
        const __m128i mask3 = _mm_or_si128(mask1, match5);
        const __m128i matches = _mm_or_si128(mask2, mask3);

        const int bitmap = _mm_movemask_epi8(matches);

        if (bitmap) {
            search->matches_bitmap = bitmap;
            return find_next_match_sse2(search);
        }
        search->cstr += sizeof(__m128i);
    }

    return find_next_basic(search);
}
#define find_next find_next_sse2
#endif

#ifdef HAVE_SIMD_NEON
#ifndef __has_builtin         // Optional of course.
  #define __has_builtin(x) 0  // Compatibility with non-clang compilers.
#endif

static inline uint32_t trailing_zeros64(uint64_t input)
{
#if HAVE_BUILTIN_CTZLL
    return __builtin_ctzll(input);
#else
    uint32_t trailing_zeros = 0;
    uint64_t temp = input;
    while ((temp & 1) == 0 && temp > 0) {
        trailing_zeros++;
        temp >>= 1;
    }
    return trailing_zeros;
#endif
}

static inline bool
find_next_match_neon(search_state *search)
{
    uint32_t trailing_zeros = trailing_zeros64(search->matches_bitmap);

    // uint64_t >>= 64 is undefined behaviour
    RUBY_ASSERT(trailing_zeros < 64);
    search->matches_bitmap >>= trailing_zeros;
    search->cstr += trailing_zeros;
    RUBY_ASSERT(search->cstr <= search->end);
    return true;
}

// This 16-byte lookup table is indexed into by using the
// low nibble of each input byte.
// Note: index 0 is intentionally set to a character that will not match
// the NULL byte.
static const uint8x16_t escape_char_by_low_nibble = {
    '\'', 0,    '"',  0,
    0,    0,    '&',  '\'',
    0,    0,    0,    0,
    '<',  0,    '>',  0,
};

static inline uint8x16_t
neon_escape_matches(const uint8x16_t bytes)
{
    // An example to demonstrate how this works. The goal is to get a uint8x16_t
    // with each lane to equal 0xFF if the corresponding byte in 'bytes' needs
    // to be escaped, or 0x00 otherwise.
    //
    // To keep things very simple, I'm going to assume a vector of length 6, in
    // reality, the vector would be 16 bytes wide.
    //
    // Assume the string is: "<br />"
    // Converted to integers:
    //   [0x3c 0x62 0x72 0x20 0x2f 0x3e]
    //
    // Next, we mask off the top nibble so we are left only with the low nibble
    // of each byte. We do this by AND'ing each byte with 0x0F.
    //
    // The result:
    //   [0x0c 0x02 0x02 0x00 0x0f 0x0e]
    //
    // Now, we use these low nibbles as indexes into the
    // escape_char_by_low_nibble array and find the full byte
    // value we expect to match in the input.
    //
    // The result:
    //   [0x3c 0x22 0x22 0x27 0x00 0x3e]
    //
    // Finally, we compare the bytes we expect with the actual input bytes.
    //
    // The result:
    //   [0xFF 0x00 0x00 0x00 0x00 0xFF]
    const uint8x16_t low_nibbles = vandq_u8(bytes, vdupq_n_u8(0x0F));
    const uint8x16_t looked_up = vqtbl1q_u8(escape_char_by_low_nibble, low_nibbles);
    return vceqq_u8(looked_up, bytes);
}

static inline uint64_t
neon_matches_to_bitmap16(const uint8x16_t matches)
{
    static const uint8x16_t bit_mask = {
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
    };

    uint8x16_t folded = vandq_u8(matches, bit_mask);
    folded = vpaddq_u8(folded, folded);
    folded = vpaddq_u8(folded, folded);
    folded = vpaddq_u8(folded, folded);

    return vgetq_lane_u16(vreinterpretq_u16_u8(folded), 0);
}

static inline uint64_t
neon_matches_to_bitmap64(const uint8x16_t m0, const uint8x16_t m1, const uint8x16_t m2, const uint8x16_t m3)
{
    static const uint8x16_t bit_mask = {
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
    };

    const uint8x16_t t0 = vandq_u8(m0, bit_mask);
    const uint8x16_t t1 = vandq_u8(m1, bit_mask);
    const uint8x16_t t2 = vandq_u8(m2, bit_mask);
    const uint8x16_t t3 = vandq_u8(m3, bit_mask);

    uint8x16_t folded = vpaddq_u8(vpaddq_u8(t0, t1), vpaddq_u8(t2, t3));
    folded = vpaddq_u8(folded, folded);

    return vgetq_lane_u64(vreinterpretq_u64_u8(folded), 0);
}

static inline bool
find_next_neon(search_state *search)
{
    if (search->matches_bitmap) {
        return find_next_match_neon(search);
    }

    while ((size_t)(search->end - search->cstr) >= sizeof(uint8x16x4_t)) {
        const uint8x16_t bytes0 = vld1q_u8(search->cstr +  0);
        const uint8x16_t bytes1 = vld1q_u8(search->cstr + 16);
        const uint8x16_t bytes2 = vld1q_u8(search->cstr + 32);
        const uint8x16_t bytes3 = vld1q_u8(search->cstr + 48);

        const uint8x16_t m0 = neon_escape_matches(bytes0);
        const uint8x16_t m1 = neon_escape_matches(bytes1);
        const uint8x16_t m2 = neon_escape_matches(bytes2);
        const uint8x16_t m3 = neon_escape_matches(bytes3);

        const uint64_t bitmap = neon_matches_to_bitmap64(m0, m1, m2, m3);

        if (bitmap) {
            search->matches_bitmap = bitmap;
            return find_next_match_neon(search);
        }

        search->cstr += 64;
    }

    while ((size_t)(search->end - search->cstr) >= sizeof(uint8x16_t)) {
        const uint8x16_t bytes = vld1q_u8(search->cstr);
        const uint8x16_t matches = neon_escape_matches(bytes);
        const uint64_t bitmap = neon_matches_to_bitmap16(matches);

        if (bitmap) {
            search->matches_bitmap = bitmap;
            return find_next_match_neon(search);
        }
        search->cstr += sizeof(uint8x16_t);
    }

    return find_next_basic(search);
}

#define find_next find_next_neon
#endif // HAVE_SIMD_NEON

static inline void
consume_match(search_state *search)
{
#ifdef HAVE_SIMD
    search->matches_bitmap >>= 1;
#endif
    search->cstr++;
}

#ifndef find_next
#define find_next find_next_basic
#endif

static VALUE
optimized_escape_html(VALUE str)
{
    VALUE vbuf;
    char *buf = NULL;
    search_state search = {
        .cstr = (const unsigned char *)RSTRING_PTR(str),
    };
    search.end = search.cstr + RSTRING_LEN(str);

    const unsigned char *segment_start = search.cstr;
    char *dest = NULL;

    while (find_next(&search)) {
        const unsigned char c = *search.cstr;

        size_t segment_len = search.cstr - segment_start;
        if (!buf) {
            buf = ALLOCV_N(char, vbuf, escaped_length(str));
            dest = buf;
        }
        if (segment_len) {
            memcpy(dest, segment_start, segment_len);
            dest += segment_len;
        }

        switch(c) {
            #define HTML_ESCAPE(c, str) \
            case c: \
                memcpy(dest, str, rb_strlen_lit(str)); \
                dest += rb_strlen_lit(str); \
                break

            HTML_ESCAPE('\'', "&#39;");
            HTML_ESCAPE('&', "&amp;");
            HTML_ESCAPE('"', "&quot;");
            HTML_ESCAPE('<', "&lt;");
            HTML_ESCAPE('>', "&gt;");
            default:
                UNREACHABLE_RETURN(Qundef);

            #undef HTML_ESCAPE
        }
        consume_match(&search);
        segment_start = search.cstr;
    }

    VALUE escaped = str;
    if (buf) {
        size_t segment_len = search.cstr - segment_start;
        if (segment_len) {
            memcpy(dest, segment_start, segment_len);
            dest += segment_len;
        }
        escaped = rb_enc_str_new(buf, dest - buf, rb_enc_get(str));
        ALLOCV_END(vbuf);
    }
    return escaped;
}

/*
 * ERB::Util.html_escape is similar to CGI.escapeHTML but different in the following two parts:
 *
 * * ERB::Util.html_escape converts an argument with #to_s first (only if it's not T_STRING)
 * * ERB::Util.html_escape does not allocate a new string when nothing needs to be escaped
 */
static VALUE
erb_escape_html(VALUE self, VALUE str)
{
    if (!RB_TYPE_P(str, T_STRING)) {
        str = rb_convert_type(str, T_STRING, "String", "to_s");
    }

    if (rb_enc_str_asciicompat_p(str)) {
        return optimized_escape_html(str);
    }
    else {
        return rb_funcall(rb_cCGI, id_escapeHTML, 1, str);
    }
}

void
Init_escape(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

    VALUE rb_cERB = rb_define_class("ERB", rb_cObject);
    VALUE rb_mEscape = rb_define_module_under(rb_cERB, "Escape");
    rb_define_module_function(rb_mEscape, "html_escape", erb_escape_html, 1);

    rb_cCGI = rb_define_class("CGI", rb_cObject);
    id_escapeHTML = rb_intern("escapeHTML");
}
