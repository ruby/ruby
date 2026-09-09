#include "ruby.h"
#include "ruby/encoding.h"

static VALUE rb_cCGI;
static ID id_escapeHTML;

#define HTML_ESCAPE_MAX_LEN 6

static const struct {
    uint8_t len;
    char str[HTML_ESCAPE_MAX_LEN+1];
} html_escape_table[UCHAR_MAX+1] = {
#define HTML_ESCAPE(c, str) [c] = {rb_strlen_lit(str), str}
    HTML_ESCAPE('\'', "&#39;"),
    HTML_ESCAPE('&', "&amp;"),
    HTML_ESCAPE('"', "&quot;"),
    HTML_ESCAPE('<', "&lt;"),
    HTML_ESCAPE('>', "&gt;"),
#undef HTML_ESCAPE
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

#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__) || defined(_M_ARM64)
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
        const unsigned char c = *search->cstr;
        if (html_escape_table[c].len) {
            return true;
        }
        search->cstr++;
    }
    return false;
}

#ifdef HAVE_SIMD_SSE2

static inline int trailing_zeros(int input)
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
    int next_match_offset = trailing_zeros(search->matches_bitmap);
    search->matches_bitmap >>= (next_match_offset + 1);
    search->cstr += next_match_offset;
    if (search->cstr > search->end) {
        search->cstr = search->end;
        return false;
    }
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
    size_t next_match_offset = trailing_zeros64(search->matches_bitmap) / 4;
    search->matches_bitmap >>= (next_match_offset + 1) * 4;
    search->cstr += next_match_offset;
    if (search->cstr > search->end) {
        search->cstr = search->end;
        return false;
    }
    return true;
}

static inline bool
find_next_neon(search_state *search)
{
    if (search->matches_bitmap) {
        return find_next_match_neon(search);
    }

    const uint8x16_t single_quote = vdupq_n_u8('\'');
    const uint8x16_t double_quote = vdupq_n_u8('"');
    const uint8x16_t ampersand = vdupq_n_u8('&');
    const uint8x16_t lt = vdupq_n_u8('<');
    const uint8x16_t gt = vdupq_n_u8('>');

    while ((size_t)(search->end - search->cstr) >= sizeof(uint8x16_t)) {
        const uint8x16_t bytes = vld1q_u8(search->cstr);
        const uint8x16_t match1 = vceqq_u8(bytes, single_quote);
        const uint8x16_t match2 = vceqq_u8(bytes, double_quote);
        const uint8x16_t match3 = vceqq_u8(bytes, ampersand);
        const uint8x16_t match4 = vceqq_u8(bytes, lt);
        const uint8x16_t match5 = vceqq_u8(bytes, gt);

        const uint8x16_t mask1 = vorrq_u8(match1, match2);
        const uint8x16_t mask2 = vorrq_u8(match3, match4);
        const uint8x16_t mask3 = vorrq_u8(mask1, match5);
        const uint8x16_t matches = vorrq_u8(mask2, mask3);

        const uint8x8_t res = vshrn_n_u16(vreinterpretq_u16_u8(matches), 4);
        const uint64_t bitmap = vget_lane_u64(vreinterpret_u64_u8(res), 0) & 0x8888888888888888ull;

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

#ifndef find_next
#define find_next_basic
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
        uint8_t len = html_escape_table[c].len;
        size_t segment_len = search.cstr - segment_start;
        search.cstr++;

        if (!buf) {
            buf = ALLOCV_N(char, vbuf, escaped_length(str));
            dest = buf;
        }
        if (segment_len) {
            memcpy(dest, segment_start, segment_len);
            dest += segment_len;
        }
        segment_start = search.cstr;
        memcpy(dest, html_escape_table[c].str, len);
        dest += len;
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
