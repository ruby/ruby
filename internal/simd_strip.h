static const char isspacetable[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

static const char isspacetable_0[256] = {
    1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

#define ascii_isspace(c) isspacetable[(unsigned char)(c)]
#define ascii_isspace_0(c) isspacetable_0[(unsigned char)(c)]

#if defined __SSE2__
#include <immintrin.h>
#include "internal/bits.h"

static int lstrip_mask(__m128i x)
{
    __m128i horizontal_tab = _mm_set1_epi8(9);
    __m128i line_feed = _mm_set1_epi8(10);
    __m128i vertical_tab = _mm_set1_epi8(11);
    __m128i form_feed = _mm_set1_epi8(12);
    __m128i carriage_return = _mm_set1_epi8(13);
    __m128i space = _mm_set1_epi8(32);
    __m128i xhorizontal_tab = _mm_cmpeq_epi8(x, horizontal_tab);
    __m128i xline_feed = _mm_cmpeq_epi8(x, line_feed);
    __m128i xvertical_tab = _mm_cmpeq_epi8(x, vertical_tab);
    __m128i xform_feed = _mm_cmpeq_epi8(x, form_feed);
    __m128i xcarriage_return = _mm_cmpeq_epi8(x, carriage_return);
    __m128i xspace = _mm_cmpeq_epi8(x, space);
    __m128i anywhite = _mm_or_si128(_mm_or_si128(_mm_or_si128(_mm_or_si128(_mm_or_si128(xhorizontal_tab,
            xline_feed),
            xvertical_tab),
            xform_feed),
            xcarriage_return),
            xspace);

    return _mm_movemask_epi8(anywhite);
}

static int rstrip_mask(__m128i x)
{
    __m128i null_char = _mm_set1_epi8(0);
    __m128i horizontal_tab = _mm_set1_epi8(9);
    __m128i line_feed = _mm_set1_epi8(10);
    __m128i vertical_tab = _mm_set1_epi8(11);
    __m128i form_feed = _mm_set1_epi8(12);
    __m128i carriage_return = _mm_set1_epi8(13);
    __m128i space = _mm_set1_epi8(32);
    __m128i xnull_char = _mm_cmpeq_epi8(x, null_char);
    __m128i xhorizontal_tab = _mm_cmpeq_epi8(x, horizontal_tab);
    __m128i xline_feed = _mm_cmpeq_epi8(x, line_feed);
    __m128i xvertical_tab = _mm_cmpeq_epi8(x, vertical_tab);
    __m128i xform_feed = _mm_cmpeq_epi8(x, form_feed);
    __m128i xcarriage_return = _mm_cmpeq_epi8(x, carriage_return);
    __m128i xspace = _mm_cmpeq_epi8(x, space);
    __m128i anywhite = _mm_or_si128(_mm_or_si128(_mm_or_si128(_mm_or_si128(_mm_or_si128(_mm_or_si128(xnull_char,
            xhorizontal_tab),
            xline_feed),
            xvertical_tab),
            xform_feed),
            xcarriage_return),
            xspace);
    
    return _mm_movemask_epi8(anywhite);
}

static long
lstrip_offset_sb(const char *s, const char *e)
{
  const char *const start = s;
  while ((s + 15) < e) {
    __m128i x = _mm_loadu_si128((const __m128i *)(s));
    int mask16 = lstrip_mask(x);
    if (mask16 == 0) {
        return s - start;
    } else if (mask16 == 65535) {
        s += 16;
    } else {
        s += ntz_int32(mask16 ^ 65535);
        return s - start;
    }
  }
  while (s < e && ascii_isspace(*s)) s++;
  return s - start;
}

static long
rstrip_offset_sb(const char *s, const char *e)
{
  const char *t = e;
  while ((s + 15) < t) {
    __m128i x = _mm_loadu_si128((const __m128i *)(t - 16));
    int mask16 = rstrip_mask(x);
    if (mask16 == 0) {
        return e - t;
    } else if (mask16 == 65535) {
        t -= 16;
    } else {
        t -= nlz_int32(mask16 ^ 65535) - 16;
        return e - t;
    }
  }
  while (s < t && ascii_isspace_0(*(t - 1))) t--;
  return e - t;
}

#else

static long
lstrip_offset_sb(const char *s, const char *e)
{
  const char *const start = s;
  while (s < e && ascii_isspace(*s)) s++;
  return s - start;
}

static long
rstrip_offset_sb(const char *s, const char *e)
{
  const char *t = e;
  while (s < t && ascii_isspace_0(*(t - 1))) t--;
  return e - t;
}
#endif
