/**********************************************************************
  cesu_8.c -  Oniguruma (regular expression library)
**********************************************************************/
/*-
 * Copyright (c) 2002-2007  K.Kosako  <sndgk393 AT ybb DOT ne DOT jp>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include "regenc.h"
#ifdef RUBY
# include "encindex.h"
#endif

#define USE_INVALID_CODE_SCHEME

#ifdef USE_INVALID_CODE_SCHEME
/* virtual codepoint values for invalid encoding byte 0xfe and 0xff */
# define INVALID_CODE_FE  0xfffffffe
# define INVALID_CODE_FF  0xffffffff
#endif
#define VALID_CODE_LIMIT  0x0010ffff

#define utf8_islead(c)     ((UChar )((c) & 0xc0) != 0x80)

static const int EncLen_CESU8[] = {
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
};

typedef enum {
  FAILURE = -2,
  ACCEPT,
  S0, S1, S2, S3,
  S4, S5, S6, S7
} state_t;
#define A ACCEPT
#define F FAILURE
static const signed char trans[][0x100] = {
  { /* S0   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 1 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 2 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 3 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 4 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 5 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 6 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 7 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 8 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 9 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* a */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* b */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* c */ F, F, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* d */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* e */ 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 3, 3,
    /* f */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  },
  { /* S1   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 1 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 2 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 3 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 4 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 5 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 6 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 7 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 8 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 9 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* a */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* b */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* c */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* d */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* e */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* f */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  },
  { /* S2   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 1 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 2 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 3 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 4 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 5 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 6 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 7 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 8 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 9 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* a */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* b */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* c */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* d */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* e */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* f */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  },
  { /* S3   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 1 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 2 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 3 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 4 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 5 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 6 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 7 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 8 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* 9 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* a */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* b */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* c */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* d */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* e */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* f */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  },
  { /* S4   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 1 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 2 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 3 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 4 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 5 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 6 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 7 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 8 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* 9 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* a */ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    /* b */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* c */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* d */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* e */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* f */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  },
  { /* S5   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 1 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 2 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 3 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 4 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 5 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 6 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 7 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 8 */ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    /* 9 */ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    /* a */ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    /* b */ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    /* c */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* d */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* e */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* f */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  },
  { /* S6   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 1 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 2 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 3 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 4 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 5 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 6 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 7 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 8 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 9 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* a */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* b */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* c */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* d */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* e */ F, F, F, F, F, F, F, F, F, F, F, F, F, 7, F, F,
    /* f */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  },
  { /* S7   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 1 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 2 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 3 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 4 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 5 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 6 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 7 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 8 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 9 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* a */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* b */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* c */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* d */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* e */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* f */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F
  },
};
#undef A
#undef F

static int
mbc_enc_len(const UChar* p, const UChar* e, OnigEncoding enc ARG_UNUSED)
{
  int firstbyte = *p++;
  state_t s;
  s = trans[0][firstbyte];
  if (s < 0) return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(1) :
                                  ONIGENC_CONSTRUCT_MBCLEN_INVALID();

  if (p == e) return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(EncLen_CESU8[firstbyte]-1);
  s = trans[s][*p++];
  if (s < 0) return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(2) :
                                  ONIGENC_CONSTRUCT_MBCLEN_INVALID();

  if (p == e) {
      int len = EncLen_CESU8[firstbyte];
      if (s == 4) { /* S4 is CESU-8's surrogate pair; len is 6 */
          len = 6;
      }
      return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(len-2);
  }
  s = trans[s][*p++];
  if (s < 0) return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(3) :
                                  ONIGENC_CONSTRUCT_MBCLEN_INVALID();

  if (p == e) return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(3);
  s = trans[s][*p++];
  if (s < 0) return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(4) :
                                  ONIGENC_CONSTRUCT_MBCLEN_INVALID();

  if (p == e) return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(2);
  s = trans[s][*p++];
  if (s < 0) return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(5) :
                                  ONIGENC_CONSTRUCT_MBCLEN_INVALID();

  if (p == e) return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(1);
  s = trans[s][*p++];
  return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(6) :
                       ONIGENC_CONSTRUCT_MBCLEN_INVALID();
}

static int
is_mbc_newline(const UChar* p, const UChar* end, OnigEncoding enc)
{
  if (p < end) {
    if (*p == 0x0a) return 1;

#ifdef USE_UNICODE_ALL_LINE_TERMINATORS
    if (*p == 0x0b || *p == 0x0c || *p == 0x0d) return 1;
    if (p + 1 < end) {
      if (*(p+1) == 0x85 && *p == 0xc2) /* U+0085 */
	return 1;
      if (p + 2 < end) {
	if ((*(p+2) == 0xa8 || *(p+2) == 0xa9)
	    && *(p+1) == 0x80 && *p == 0xe2)  /* U+2028, U+2029 */
	  return 1;
      }
    }
#endif
  }

  return 0;
}

static OnigCodePoint
mbc_to_code(const UChar* p, const UChar* end, OnigEncoding enc)
{
  int len;

  len = mbc_enc_len(p, end, enc);
  switch (len) {
    case 1:
      return *p;
    case 2:
      return ((p[0] & 0x1F)  << 6) | (p[1] & 0x3f);
    case 3:
      return ((p[0] & 0xF) << 12) | ((p[1] & 0x3f) << 6) | (p[2] & 0x3f);
    case 6:
      {
          int high = ((p[0] & 0xF) << 12) | ((p[1] & 0x3f) << 6) | (p[2] & 0x3f);
          int low  = ((p[3] & 0xF) << 12) | ((p[4] & 0x3f) << 6) | (p[5] & 0x3f);
          return ((high & 0x03ff) << 10) + (low & 0x03ff) + 0x10000;
      }
  }
#ifdef USE_INVALID_CODE_SCHEME
  if (*p > 0xfd) {
      return ((*p == 0xfe) ? INVALID_CODE_FE : INVALID_CODE_FF);
  }
#endif
  return (OnigCodePoint )*p;
}

static int
code_to_mbclen(OnigCodePoint code, OnigEncoding enc ARG_UNUSED)
{
  if      ((code & 0xffffff80) == 0) return 1;
  else if ((code & 0xfffff800) == 0) return 2;
  else if ((code & 0xffff0000) == 0) return 3;
  else if (code <= VALID_CODE_LIMIT) return 6;
#ifdef USE_INVALID_CODE_SCHEME
  else if (code == INVALID_CODE_FE) return 1;
  else if (code == INVALID_CODE_FF) return 1;
#endif
  else
    return ONIGERR_TOO_BIG_WIDE_CHAR_VALUE;
}

static int
code_to_mbc(OnigCodePoint code, UChar *buf, OnigEncoding enc ARG_UNUSED)
{
#define UTF8_TRAILS(code, shift) (UChar )((((code) >> (shift)) & 0x3f) | 0x80)
#define UTF8_TRAIL0(code)        (UChar )(((code) & 0x3f) | 0x80)

  if ((code & 0xffffff80) == 0) {
    *buf = (UChar )code;
    return 1;
  }
  else {
    UChar *p = buf;

    if ((code & 0xfffff800) == 0) {
      *p++ = (UChar )(((code>>6)& 0x1f) | 0xc0);
    }
    else if ((code & 0xffff0000) == 0) {
      *p++ = (UChar )(((code>>12) & 0x0f) | 0xe0);
      *p++ = UTF8_TRAILS(code, 6);
    }
    else if (code <= VALID_CODE_LIMIT) {
      unsigned int high = (code >> 10) + 0xD7C0;
      code = (code & 0x3FF) + 0xDC00;
      *p++ = (UChar )(((high>>12) & 0x0f) | 0xe0);
      *p++ = UTF8_TRAILS(high, 6);
      *p++ = UTF8_TRAIL0(high);
      *p++ = (UChar )(((code>>12) & 0x0f) | 0xe0);
      *p++ = UTF8_TRAILS(code, 6);
    }
#ifdef USE_INVALID_CODE_SCHEME
    else if (code == INVALID_CODE_FE) {
      *p = 0xfe;
      return 1;
    }
    else if (code == INVALID_CODE_FF) {
      *p = 0xff;
      return 1;
    }
#endif
    else {
      return ONIGERR_TOO_BIG_WIDE_CHAR_VALUE;
    }

    *p++ = UTF8_TRAIL0(code);
    return (int )(p - buf);
  }
}

static int
mbc_case_fold(OnigCaseFoldType flag, const UChar** pp,
	      const UChar* end, UChar* fold, OnigEncoding enc)
{
  const UChar* p = *pp;

  if (ONIGENC_IS_MBC_ASCII(p)) {
#ifdef USE_UNICODE_CASE_FOLD_TURKISH_AZERI
    if ((flag & ONIGENC_CASE_FOLD_TURKISH_AZERI) != 0) {
      if (*p == 0x49) {
	*fold++ = 0xc4;
	*fold   = 0xb1;
	(*pp)++;
	return 2;
      }
    }
#endif

    *fold = ONIGENC_ASCII_CODE_TO_LOWER_CASE(*p);
    (*pp)++;
    return 1; /* return byte length of converted char to lower */
  }
  else {
    return onigenc_unicode_mbc_case_fold(enc, flag, pp, end, fold);
  }
}


static int
get_ctype_code_range(OnigCtype ctype, OnigCodePoint *sb_out,
		     const OnigCodePoint* ranges[], OnigEncoding enc ARG_UNUSED)
{
  *sb_out = 0x80;
  return onigenc_unicode_ctype_code_range(ctype, ranges);
}


static UChar*
left_adjust_char_head(const UChar* start, const UChar* s, const UChar* end, OnigEncoding enc ARG_UNUSED)
{
  const UChar *p;

  if (s <= start) return (UChar* )s;
  p = s;

  while (!utf8_islead(*p) && p > start) p--;
  return (UChar* )p;
}

static int
get_case_fold_codes_by_str(OnigCaseFoldType flag,
    const OnigUChar* p, const OnigUChar* end, OnigCaseFoldCodeItem items[],
    OnigEncoding enc)
{
  return onigenc_unicode_get_case_fold_codes_by_str(enc, flag, p, end, items);
}

OnigEncodingDefine(cesu_8, CESU_8) = {
  mbc_enc_len,
  "CESU-8",     /* name */
  6,           /* max byte length */
  1,           /* min byte length */
  is_mbc_newline,
  mbc_to_code,
  code_to_mbclen,
  code_to_mbc,
  mbc_case_fold,
  onigenc_unicode_apply_all_case_fold,
  get_case_fold_codes_by_str,
  onigenc_unicode_property_name_to_ctype,
  onigenc_unicode_is_code_ctype,
  get_ctype_code_range,
  left_adjust_char_head,
  onigenc_always_true_is_allowed_reverse_match,
  onigenc_unicode_case_map,
  ENCINDEX_UTF_8,
  ONIGENC_FLAG_UNICODE,
};
