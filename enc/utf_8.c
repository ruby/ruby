/**********************************************************************
  utf_8.c -  Oniguruma (regular expression library)
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

#define USE_INVALID_CODE_SCHEME

#ifdef USE_INVALID_CODE_SCHEME
/* virtual codepoint values for invalid encoding byte 0xfe and 0xff */
#define INVALID_CODE_FE   0xfffffffe
#define INVALID_CODE_FF   0xffffffff
#define VALID_CODE_LIMIT  0x7fffffff
#endif

#define utf8_islead(c)     ((UChar )((c) & 0xc0) != 0x80)

static const int EncLen_UTF8[] = {
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
  4, 4, 4, 4, 4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
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
    /* f */ 5, 6, 6, 6, 7, F, F, F, F, F, F, F, F, F, F, F 
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
    /* a */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
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
    /* 8 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 9 */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    /* a */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    /* b */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
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
    /* 8 */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    /* 9 */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    /* a */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    /* b */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    /* c */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* d */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* e */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
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
    /* 8 */ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    /* 9 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* a */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* b */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
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

  if (p == e) return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(EncLen_UTF8[firstbyte]-1);
  s = trans[s][*p++];
  if (s < 0) return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(2) :
                                  ONIGENC_CONSTRUCT_MBCLEN_INVALID();

  if (p == e) return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(EncLen_UTF8[firstbyte]-2);
  s = trans[s][*p++];
  if (s < 0) return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(3) :
                                  ONIGENC_CONSTRUCT_MBCLEN_INVALID();

  if (p == e) return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(EncLen_UTF8[firstbyte]-3);
  s = trans[s][*p++];
  return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(4) :
                       ONIGENC_CONSTRUCT_MBCLEN_INVALID();
}

static OnigCodePoint mbc_to_code(const UChar* p, const UChar* end, int *precise_ret, OnigEncoding enc);

/* generated from GraphemeBreakProperty-5.1.0.txt
 * Since CR LF is handled in another layer such as IO with text mode,
 * CR and LF are merged into CONTROL.  */
#define GRAPHEME_BIT_CONTROL         0x001
#define GRAPHEME_BIT_EXTEND          0x002
#define GRAPHEME_BIT_PREPEND         0x004
#define GRAPHEME_BIT_SPACINGMARK     0x008
#define GRAPHEME_BIT_L               0x010
#define GRAPHEME_BIT_V               0x020
#define GRAPHEME_BIT_T               0x040
#define GRAPHEME_BIT_LV              0x080
#define GRAPHEME_BIT_LVT             0x100
const struct graphme_table_t { /* codepoint_min <= c < codepoint_min+num_codepoints */
    OnigCodePoint codepoint_min;
    unsigned short num_codepoints;
    unsigned short properties;
} graphme_table[] = {
    {0x00000,32,0x001}, {0x0007F,33,0x001},
    {0x000AD,1,0x001}, {0x00300,112,0x002},
    {0x00483,7,0x002}, {0x00591,45,0x002},
    {0x005BF,1,0x002}, {0x005C1,2,0x002},
    {0x005C4,2,0x002}, {0x005C7,1,0x002},
    {0x00600,4,0x001}, {0x00610,11,0x002},
    {0x0064B,20,0x002}, {0x00670,1,0x002},
    {0x006D6,7,0x002}, {0x006DD,1,0x001},
    {0x006DE,7,0x002}, {0x006E7,2,0x002},
    {0x006EA,4,0x002}, {0x0070F,1,0x001},
    {0x00711,1,0x002}, {0x00730,27,0x002},
    {0x007A6,11,0x002}, {0x007EB,9,0x002},
    {0x00901,2,0x002}, {0x00903,1,0x008},
    {0x0093C,1,0x002}, {0x0093E,3,0x008},
    {0x00941,8,0x002}, {0x00949,4,0x008},
    {0x0094D,1,0x002}, {0x00951,4,0x002},
    {0x00962,2,0x002}, {0x00981,1,0x002},
    {0x00982,2,0x008}, {0x009BC,1,0x002},
    {0x009BE,1,0x002}, {0x009BF,2,0x008},
    {0x009C1,4,0x002}, {0x009C7,2,0x008},
    {0x009CB,2,0x008}, {0x009CD,1,0x002},
    {0x009D7,1,0x002}, {0x009E2,2,0x002},
    {0x00A01,2,0x002}, {0x00A03,1,0x008},
    {0x00A3C,1,0x002}, {0x00A3E,3,0x008},
    {0x00A41,2,0x002}, {0x00A47,2,0x002},
    {0x00A4B,3,0x002}, {0x00A51,1,0x002},
    {0x00A70,2,0x002}, {0x00A75,1,0x002},
    {0x00A81,2,0x002}, {0x00A83,1,0x008},
    {0x00ABC,1,0x002}, {0x00ABE,3,0x008},
    {0x00AC1,5,0x002}, {0x00AC7,2,0x002},
    {0x00AC9,1,0x008}, {0x00ACB,2,0x008},
    {0x00ACD,1,0x002}, {0x00AE2,2,0x002},
    {0x00B01,1,0x002}, {0x00B02,2,0x008},
    {0x00B3C,1,0x002}, {0x00B3E,2,0x002},
    {0x00B40,1,0x008}, {0x00B41,4,0x002},
    {0x00B47,2,0x008}, {0x00B4B,2,0x008},
    {0x00B4D,1,0x002}, {0x00B56,2,0x002},
    {0x00B62,2,0x002}, {0x00B82,1,0x002},
    {0x00BBE,1,0x002}, {0x00BBF,1,0x008},
    {0x00BC0,1,0x002}, {0x00BC1,2,0x008},
    {0x00BC6,3,0x008}, {0x00BCA,3,0x008},
    {0x00BCD,1,0x002}, {0x00BD7,1,0x002},
    {0x00C01,3,0x008}, {0x00C3E,3,0x002},
    {0x00C41,4,0x008}, {0x00C46,3,0x002},
    {0x00C4A,4,0x002}, {0x00C55,2,0x002},
    {0x00C62,2,0x002}, {0x00C82,2,0x008},
    {0x00CBC,1,0x002}, {0x00CBE,1,0x008},
    {0x00CBF,1,0x002}, {0x00CC0,2,0x008},
    {0x00CC2,1,0x002}, {0x00CC3,2,0x008},
    {0x00CC6,1,0x002}, {0x00CC7,2,0x008},
    {0x00CCA,2,0x008}, {0x00CCC,2,0x002},
    {0x00CD5,2,0x002}, {0x00CE2,2,0x002},
    {0x00D02,2,0x008}, {0x00D3E,1,0x002},
    {0x00D3F,2,0x008}, {0x00D41,4,0x002},
    {0x00D46,3,0x008}, {0x00D4A,3,0x008},
    {0x00D4D,1,0x002}, {0x00D57,1,0x002},
    {0x00D62,2,0x002}, {0x00D82,2,0x008},
    {0x00DCA,1,0x002}, {0x00DCF,1,0x002},
    {0x00DD0,2,0x008}, {0x00DD2,3,0x002},
    {0x00DD6,1,0x002}, {0x00DD8,7,0x008},
    {0x00DDF,1,0x002}, {0x00DF2,2,0x008},
    {0x00E30,11,0x002}, {0x00E40,5,0x004},
    {0x00E45,1,0x002}, {0x00E47,8,0x002},
    {0x00EB0,10,0x002}, {0x00EBB,2,0x002},
    {0x00EC0,5,0x004}, {0x00EC8,6,0x002},
    {0x00F18,2,0x002}, {0x00F35,1,0x002},
    {0x00F37,1,0x002}, {0x00F39,1,0x002},
    {0x00F3E,2,0x008}, {0x00F71,14,0x002},
    {0x00F7F,1,0x008}, {0x00F80,5,0x002},
    {0x00F86,2,0x002}, {0x00F90,8,0x002},
    {0x00F99,36,0x002}, {0x00FC6,1,0x002},
    {0x0102B,2,0x008}, {0x0102D,4,0x002},
    {0x01031,1,0x008}, {0x01032,6,0x002},
    {0x01038,1,0x008}, {0x01039,2,0x002},
    {0x0103B,2,0x008}, {0x0103D,2,0x002},
    {0x01056,2,0x008}, {0x01058,2,0x002},
    {0x0105E,3,0x002}, {0x01062,3,0x008},
    {0x01067,7,0x008}, {0x01071,4,0x002},
    {0x01082,1,0x002}, {0x01083,2,0x008},
    {0x01085,2,0x002}, {0x01087,6,0x008},
    {0x0108D,1,0x002}, {0x0108F,1,0x008},
    {0x01100,90,0x010}, {0x0115F,1,0x010},
    {0x01160,67,0x020}, {0x011A8,82,0x040},
    {0x0135F,1,0x002}, {0x01712,3,0x002},
    {0x01732,3,0x002}, {0x01752,2,0x002},
    {0x01772,2,0x002}, {0x017B4,2,0x001},
    {0x017B6,1,0x008}, {0x017B7,7,0x002},
    {0x017BE,8,0x008}, {0x017C6,1,0x002},
    {0x017C7,2,0x008}, {0x017C9,11,0x002},
    {0x017DD,1,0x002}, {0x0180B,3,0x002},
    {0x018A9,1,0x002}, {0x01920,3,0x002},
    {0x01923,4,0x008}, {0x01927,2,0x002},
    {0x01929,3,0x008}, {0x01930,2,0x008},
    {0x01932,1,0x002}, {0x01933,6,0x008},
    {0x01939,3,0x002}, {0x019B0,17,0x008},
    {0x019C8,2,0x008}, {0x01A17,2,0x002},
    {0x01A19,3,0x008}, {0x01B00,4,0x002},
    {0x01B04,1,0x008}, {0x01B34,1,0x002},
    {0x01B35,1,0x008}, {0x01B36,5,0x002},
    {0x01B3B,1,0x008}, {0x01B3C,1,0x002},
    {0x01B3D,5,0x008}, {0x01B42,1,0x002},
    {0x01B43,2,0x008}, {0x01B6B,9,0x002},
    {0x01B80,2,0x002}, {0x01B82,1,0x008},
    {0x01BA1,1,0x008}, {0x01BA2,4,0x002},
    {0x01BA6,2,0x008}, {0x01BA8,2,0x002},
    {0x01BAA,1,0x008}, {0x01C24,8,0x008},
    {0x01C2C,8,0x002}, {0x01C34,2,0x008},
    {0x01C36,2,0x002}, {0x01DC0,39,0x002},
    {0x01DFE,2,0x002}, {0x0200B,1,0x001},
    {0x0200C,2,0x002}, {0x0200E,2,0x001},
    {0x02028,7,0x001}, {0x02060,5,0x001},
    {0x0206A,6,0x001}, {0x020D0,33,0x002},
    {0x02DE0,32,0x002}, {0x0302A,6,0x002},
    {0x03099,2,0x002}, {0x0A66F,4,0x002},
    {0x0A67C,2,0x002}, {0x0A802,1,0x002},
    {0x0A806,1,0x002}, {0x0A80B,1,0x002},
    {0x0A823,2,0x008}, {0x0A825,2,0x002},
    {0x0A827,1,0x008}, {0x0A880,2,0x008},
    {0x0A8B4,16,0x008}, {0x0A8C4,1,0x002},
    {0x0A926,8,0x002}, {0x0A947,11,0x002},
    {0x0A952,2,0x008}, {0x0AA29,6,0x002},
    {0x0AA2F,2,0x008}, {0x0AA31,2,0x002},
    {0x0AA33,2,0x008}, {0x0AA35,2,0x002},
    {0x0AA43,1,0x002}, {0x0AA4C,1,0x002},
    {0x0AA4D,1,0x008}, {0x0AC00,1,0x080},
    {0x0AC01,27,0x100}, {0x0AC1C,1,0x080},
    {0x0AC1D,27,0x100}, {0x0AC38,1,0x080},
    {0x0AC39,27,0x100}, {0x0AC54,1,0x080},
    {0x0AC55,27,0x100}, {0x0AC70,1,0x080},
    {0x0AC71,27,0x100}, {0x0AC8C,1,0x080},
    {0x0AC8D,27,0x100}, {0x0ACA8,1,0x080},
    {0x0ACA9,27,0x100}, {0x0ACC4,1,0x080},
    {0x0ACC5,27,0x100}, {0x0ACE0,1,0x080},
    {0x0ACE1,27,0x100}, {0x0ACFC,1,0x080},
    {0x0ACFD,27,0x100}, {0x0AD18,1,0x080},
    {0x0AD19,27,0x100}, {0x0AD34,1,0x080},
    {0x0AD35,27,0x100}, {0x0AD50,1,0x080},
    {0x0AD51,27,0x100}, {0x0AD6C,1,0x080},
    {0x0AD6D,27,0x100}, {0x0AD88,1,0x080},
    {0x0AD89,27,0x100}, {0x0ADA4,1,0x080},
    {0x0ADA5,27,0x100}, {0x0ADC0,1,0x080},
    {0x0ADC1,27,0x100}, {0x0ADDC,1,0x080},
    {0x0ADDD,27,0x100}, {0x0ADF8,1,0x080},
    {0x0ADF9,27,0x100}, {0x0AE14,1,0x080},
    {0x0AE15,27,0x100}, {0x0AE30,1,0x080},
    {0x0AE31,27,0x100}, {0x0AE4C,1,0x080},
    {0x0AE4D,27,0x100}, {0x0AE68,1,0x080},
    {0x0AE69,27,0x100}, {0x0AE84,1,0x080},
    {0x0AE85,27,0x100}, {0x0AEA0,1,0x080},
    {0x0AEA1,27,0x100}, {0x0AEBC,1,0x080},
    {0x0AEBD,27,0x100}, {0x0AED8,1,0x080},
    {0x0AED9,27,0x100}, {0x0AEF4,1,0x080},
    {0x0AEF5,27,0x100}, {0x0AF10,1,0x080},
    {0x0AF11,27,0x100}, {0x0AF2C,1,0x080},
    {0x0AF2D,27,0x100}, {0x0AF48,1,0x080},
    {0x0AF49,27,0x100}, {0x0AF64,1,0x080},
    {0x0AF65,27,0x100}, {0x0AF80,1,0x080},
    {0x0AF81,27,0x100}, {0x0AF9C,1,0x080},
    {0x0AF9D,27,0x100}, {0x0AFB8,1,0x080},
    {0x0AFB9,27,0x100}, {0x0AFD4,1,0x080},
    {0x0AFD5,27,0x100}, {0x0AFF0,1,0x080},
    {0x0AFF1,27,0x100}, {0x0B00C,1,0x080},
    {0x0B00D,27,0x100}, {0x0B028,1,0x080},
    {0x0B029,27,0x100}, {0x0B044,1,0x080},
    {0x0B045,27,0x100}, {0x0B060,1,0x080},
    {0x0B061,27,0x100}, {0x0B07C,1,0x080},
    {0x0B07D,27,0x100}, {0x0B098,1,0x080},
    {0x0B099,27,0x100}, {0x0B0B4,1,0x080},
    {0x0B0B5,27,0x100}, {0x0B0D0,1,0x080},
    {0x0B0D1,27,0x100}, {0x0B0EC,1,0x080},
    {0x0B0ED,27,0x100}, {0x0B108,1,0x080},
    {0x0B109,27,0x100}, {0x0B124,1,0x080},
    {0x0B125,27,0x100}, {0x0B140,1,0x080},
    {0x0B141,27,0x100}, {0x0B15C,1,0x080},
    {0x0B15D,27,0x100}, {0x0B178,1,0x080},
    {0x0B179,27,0x100}, {0x0B194,1,0x080},
    {0x0B195,27,0x100}, {0x0B1B0,1,0x080},
    {0x0B1B1,27,0x100}, {0x0B1CC,1,0x080},
    {0x0B1CD,27,0x100}, {0x0B1E8,1,0x080},
    {0x0B1E9,27,0x100}, {0x0B204,1,0x080},
    {0x0B205,27,0x100}, {0x0B220,1,0x080},
    {0x0B221,27,0x100}, {0x0B23C,1,0x080},
    {0x0B23D,27,0x100}, {0x0B258,1,0x080},
    {0x0B259,27,0x100}, {0x0B274,1,0x080},
    {0x0B275,27,0x100}, {0x0B290,1,0x080},
    {0x0B291,27,0x100}, {0x0B2AC,1,0x080},
    {0x0B2AD,27,0x100}, {0x0B2C8,1,0x080},
    {0x0B2C9,27,0x100}, {0x0B2E4,1,0x080},
    {0x0B2E5,27,0x100}, {0x0B300,1,0x080},
    {0x0B301,27,0x100}, {0x0B31C,1,0x080},
    {0x0B31D,27,0x100}, {0x0B338,1,0x080},
    {0x0B339,27,0x100}, {0x0B354,1,0x080},
    {0x0B355,27,0x100}, {0x0B370,1,0x080},
    {0x0B371,27,0x100}, {0x0B38C,1,0x080},
    {0x0B38D,27,0x100}, {0x0B3A8,1,0x080},
    {0x0B3A9,27,0x100}, {0x0B3C4,1,0x080},
    {0x0B3C5,27,0x100}, {0x0B3E0,1,0x080},
    {0x0B3E1,27,0x100}, {0x0B3FC,1,0x080},
    {0x0B3FD,27,0x100}, {0x0B418,1,0x080},
    {0x0B419,27,0x100}, {0x0B434,1,0x080},
    {0x0B435,27,0x100}, {0x0B450,1,0x080},
    {0x0B451,27,0x100}, {0x0B46C,1,0x080},
    {0x0B46D,27,0x100}, {0x0B488,1,0x080},
    {0x0B489,27,0x100}, {0x0B4A4,1,0x080},
    {0x0B4A5,27,0x100}, {0x0B4C0,1,0x080},
    {0x0B4C1,27,0x100}, {0x0B4DC,1,0x080},
    {0x0B4DD,27,0x100}, {0x0B4F8,1,0x080},
    {0x0B4F9,27,0x100}, {0x0B514,1,0x080},
    {0x0B515,27,0x100}, {0x0B530,1,0x080},
    {0x0B531,27,0x100}, {0x0B54C,1,0x080},
    {0x0B54D,27,0x100}, {0x0B568,1,0x080},
    {0x0B569,27,0x100}, {0x0B584,1,0x080},
    {0x0B585,27,0x100}, {0x0B5A0,1,0x080},
    {0x0B5A1,27,0x100}, {0x0B5BC,1,0x080},
    {0x0B5BD,27,0x100}, {0x0B5D8,1,0x080},
    {0x0B5D9,27,0x100}, {0x0B5F4,1,0x080},
    {0x0B5F5,27,0x100}, {0x0B610,1,0x080},
    {0x0B611,27,0x100}, {0x0B62C,1,0x080},
    {0x0B62D,27,0x100}, {0x0B648,1,0x080},
    {0x0B649,27,0x100}, {0x0B664,1,0x080},
    {0x0B665,27,0x100}, {0x0B680,1,0x080},
    {0x0B681,27,0x100}, {0x0B69C,1,0x080},
    {0x0B69D,27,0x100}, {0x0B6B8,1,0x080},
    {0x0B6B9,27,0x100}, {0x0B6D4,1,0x080},
    {0x0B6D5,27,0x100}, {0x0B6F0,1,0x080},
    {0x0B6F1,27,0x100}, {0x0B70C,1,0x080},
    {0x0B70D,27,0x100}, {0x0B728,1,0x080},
    {0x0B729,27,0x100}, {0x0B744,1,0x080},
    {0x0B745,27,0x100}, {0x0B760,1,0x080},
    {0x0B761,27,0x100}, {0x0B77C,1,0x080},
    {0x0B77D,27,0x100}, {0x0B798,1,0x080},
    {0x0B799,27,0x100}, {0x0B7B4,1,0x080},
    {0x0B7B5,27,0x100}, {0x0B7D0,1,0x080},
    {0x0B7D1,27,0x100}, {0x0B7EC,1,0x080},
    {0x0B7ED,27,0x100}, {0x0B808,1,0x080},
    {0x0B809,27,0x100}, {0x0B824,1,0x080},
    {0x0B825,27,0x100}, {0x0B840,1,0x080},
    {0x0B841,27,0x100}, {0x0B85C,1,0x080},
    {0x0B85D,27,0x100}, {0x0B878,1,0x080},
    {0x0B879,27,0x100}, {0x0B894,1,0x080},
    {0x0B895,27,0x100}, {0x0B8B0,1,0x080},
    {0x0B8B1,27,0x100}, {0x0B8CC,1,0x080},
    {0x0B8CD,27,0x100}, {0x0B8E8,1,0x080},
    {0x0B8E9,27,0x100}, {0x0B904,1,0x080},
    {0x0B905,27,0x100}, {0x0B920,1,0x080},
    {0x0B921,27,0x100}, {0x0B93C,1,0x080},
    {0x0B93D,27,0x100}, {0x0B958,1,0x080},
    {0x0B959,27,0x100}, {0x0B974,1,0x080},
    {0x0B975,27,0x100}, {0x0B990,1,0x080},
    {0x0B991,27,0x100}, {0x0B9AC,1,0x080},
    {0x0B9AD,27,0x100}, {0x0B9C8,1,0x080},
    {0x0B9C9,27,0x100}, {0x0B9E4,1,0x080},
    {0x0B9E5,27,0x100}, {0x0BA00,1,0x080},
    {0x0BA01,27,0x100}, {0x0BA1C,1,0x080},
    {0x0BA1D,27,0x100}, {0x0BA38,1,0x080},
    {0x0BA39,27,0x100}, {0x0BA54,1,0x080},
    {0x0BA55,27,0x100}, {0x0BA70,1,0x080},
    {0x0BA71,27,0x100}, {0x0BA8C,1,0x080},
    {0x0BA8D,27,0x100}, {0x0BAA8,1,0x080},
    {0x0BAA9,27,0x100}, {0x0BAC4,1,0x080},
    {0x0BAC5,27,0x100}, {0x0BAE0,1,0x080},
    {0x0BAE1,27,0x100}, {0x0BAFC,1,0x080},
    {0x0BAFD,27,0x100}, {0x0BB18,1,0x080},
    {0x0BB19,27,0x100}, {0x0BB34,1,0x080},
    {0x0BB35,27,0x100}, {0x0BB50,1,0x080},
    {0x0BB51,27,0x100}, {0x0BB6C,1,0x080},
    {0x0BB6D,27,0x100}, {0x0BB88,1,0x080},
    {0x0BB89,27,0x100}, {0x0BBA4,1,0x080},
    {0x0BBA5,27,0x100}, {0x0BBC0,1,0x080},
    {0x0BBC1,27,0x100}, {0x0BBDC,1,0x080},
    {0x0BBDD,27,0x100}, {0x0BBF8,1,0x080},
    {0x0BBF9,27,0x100}, {0x0BC14,1,0x080},
    {0x0BC15,27,0x100}, {0x0BC30,1,0x080},
    {0x0BC31,27,0x100}, {0x0BC4C,1,0x080},
    {0x0BC4D,27,0x100}, {0x0BC68,1,0x080},
    {0x0BC69,27,0x100}, {0x0BC84,1,0x080},
    {0x0BC85,27,0x100}, {0x0BCA0,1,0x080},
    {0x0BCA1,27,0x100}, {0x0BCBC,1,0x080},
    {0x0BCBD,27,0x100}, {0x0BCD8,1,0x080},
    {0x0BCD9,27,0x100}, {0x0BCF4,1,0x080},
    {0x0BCF5,27,0x100}, {0x0BD10,1,0x080},
    {0x0BD11,27,0x100}, {0x0BD2C,1,0x080},
    {0x0BD2D,27,0x100}, {0x0BD48,1,0x080},
    {0x0BD49,27,0x100}, {0x0BD64,1,0x080},
    {0x0BD65,27,0x100}, {0x0BD80,1,0x080},
    {0x0BD81,27,0x100}, {0x0BD9C,1,0x080},
    {0x0BD9D,27,0x100}, {0x0BDB8,1,0x080},
    {0x0BDB9,27,0x100}, {0x0BDD4,1,0x080},
    {0x0BDD5,27,0x100}, {0x0BDF0,1,0x080},
    {0x0BDF1,27,0x100}, {0x0BE0C,1,0x080},
    {0x0BE0D,27,0x100}, {0x0BE28,1,0x080},
    {0x0BE29,27,0x100}, {0x0BE44,1,0x080},
    {0x0BE45,27,0x100}, {0x0BE60,1,0x080},
    {0x0BE61,27,0x100}, {0x0BE7C,1,0x080},
    {0x0BE7D,27,0x100}, {0x0BE98,1,0x080},
    {0x0BE99,27,0x100}, {0x0BEB4,1,0x080},
    {0x0BEB5,27,0x100}, {0x0BED0,1,0x080},
    {0x0BED1,27,0x100}, {0x0BEEC,1,0x080},
    {0x0BEED,27,0x100}, {0x0BF08,1,0x080},
    {0x0BF09,27,0x100}, {0x0BF24,1,0x080},
    {0x0BF25,27,0x100}, {0x0BF40,1,0x080},
    {0x0BF41,27,0x100}, {0x0BF5C,1,0x080},
    {0x0BF5D,27,0x100}, {0x0BF78,1,0x080},
    {0x0BF79,27,0x100}, {0x0BF94,1,0x080},
    {0x0BF95,27,0x100}, {0x0BFB0,1,0x080},
    {0x0BFB1,27,0x100}, {0x0BFCC,1,0x080},
    {0x0BFCD,27,0x100}, {0x0BFE8,1,0x080},
    {0x0BFE9,27,0x100}, {0x0C004,1,0x080},
    {0x0C005,27,0x100}, {0x0C020,1,0x080},
    {0x0C021,27,0x100}, {0x0C03C,1,0x080},
    {0x0C03D,27,0x100}, {0x0C058,1,0x080},
    {0x0C059,27,0x100}, {0x0C074,1,0x080},
    {0x0C075,27,0x100}, {0x0C090,1,0x080},
    {0x0C091,27,0x100}, {0x0C0AC,1,0x080},
    {0x0C0AD,27,0x100}, {0x0C0C8,1,0x080},
    {0x0C0C9,27,0x100}, {0x0C0E4,1,0x080},
    {0x0C0E5,27,0x100}, {0x0C100,1,0x080},
    {0x0C101,27,0x100}, {0x0C11C,1,0x080},
    {0x0C11D,27,0x100}, {0x0C138,1,0x080},
    {0x0C139,27,0x100}, {0x0C154,1,0x080},
    {0x0C155,27,0x100}, {0x0C170,1,0x080},
    {0x0C171,27,0x100}, {0x0C18C,1,0x080},
    {0x0C18D,27,0x100}, {0x0C1A8,1,0x080},
    {0x0C1A9,27,0x100}, {0x0C1C4,1,0x080},
    {0x0C1C5,27,0x100}, {0x0C1E0,1,0x080},
    {0x0C1E1,27,0x100}, {0x0C1FC,1,0x080},
    {0x0C1FD,27,0x100}, {0x0C218,1,0x080},
    {0x0C219,27,0x100}, {0x0C234,1,0x080},
    {0x0C235,27,0x100}, {0x0C250,1,0x080},
    {0x0C251,27,0x100}, {0x0C26C,1,0x080},
    {0x0C26D,27,0x100}, {0x0C288,1,0x080},
    {0x0C289,27,0x100}, {0x0C2A4,1,0x080},
    {0x0C2A5,27,0x100}, {0x0C2C0,1,0x080},
    {0x0C2C1,27,0x100}, {0x0C2DC,1,0x080},
    {0x0C2DD,27,0x100}, {0x0C2F8,1,0x080},
    {0x0C2F9,27,0x100}, {0x0C314,1,0x080},
    {0x0C315,27,0x100}, {0x0C330,1,0x080},
    {0x0C331,27,0x100}, {0x0C34C,1,0x080},
    {0x0C34D,27,0x100}, {0x0C368,1,0x080},
    {0x0C369,27,0x100}, {0x0C384,1,0x080},
    {0x0C385,27,0x100}, {0x0C3A0,1,0x080},
    {0x0C3A1,27,0x100}, {0x0C3BC,1,0x080},
    {0x0C3BD,27,0x100}, {0x0C3D8,1,0x080},
    {0x0C3D9,27,0x100}, {0x0C3F4,1,0x080},
    {0x0C3F5,27,0x100}, {0x0C410,1,0x080},
    {0x0C411,27,0x100}, {0x0C42C,1,0x080},
    {0x0C42D,27,0x100}, {0x0C448,1,0x080},
    {0x0C449,27,0x100}, {0x0C464,1,0x080},
    {0x0C465,27,0x100}, {0x0C480,1,0x080},
    {0x0C481,27,0x100}, {0x0C49C,1,0x080},
    {0x0C49D,27,0x100}, {0x0C4B8,1,0x080},
    {0x0C4B9,27,0x100}, {0x0C4D4,1,0x080},
    {0x0C4D5,27,0x100}, {0x0C4F0,1,0x080},
    {0x0C4F1,27,0x100}, {0x0C50C,1,0x080},
    {0x0C50D,27,0x100}, {0x0C528,1,0x080},
    {0x0C529,27,0x100}, {0x0C544,1,0x080},
    {0x0C545,27,0x100}, {0x0C560,1,0x080},
    {0x0C561,27,0x100}, {0x0C57C,1,0x080},
    {0x0C57D,27,0x100}, {0x0C598,1,0x080},
    {0x0C599,27,0x100}, {0x0C5B4,1,0x080},
    {0x0C5B5,27,0x100}, {0x0C5D0,1,0x080},
    {0x0C5D1,27,0x100}, {0x0C5EC,1,0x080},
    {0x0C5ED,27,0x100}, {0x0C608,1,0x080},
    {0x0C609,27,0x100}, {0x0C624,1,0x080},
    {0x0C625,27,0x100}, {0x0C640,1,0x080},
    {0x0C641,27,0x100}, {0x0C65C,1,0x080},
    {0x0C65D,27,0x100}, {0x0C678,1,0x080},
    {0x0C679,27,0x100}, {0x0C694,1,0x080},
    {0x0C695,27,0x100}, {0x0C6B0,1,0x080},
    {0x0C6B1,27,0x100}, {0x0C6CC,1,0x080},
    {0x0C6CD,27,0x100}, {0x0C6E8,1,0x080},
    {0x0C6E9,27,0x100}, {0x0C704,1,0x080},
    {0x0C705,27,0x100}, {0x0C720,1,0x080},
    {0x0C721,27,0x100}, {0x0C73C,1,0x080},
    {0x0C73D,27,0x100}, {0x0C758,1,0x080},
    {0x0C759,27,0x100}, {0x0C774,1,0x080},
    {0x0C775,27,0x100}, {0x0C790,1,0x080},
    {0x0C791,27,0x100}, {0x0C7AC,1,0x080},
    {0x0C7AD,27,0x100}, {0x0C7C8,1,0x080},
    {0x0C7C9,27,0x100}, {0x0C7E4,1,0x080},
    {0x0C7E5,27,0x100}, {0x0C800,1,0x080},
    {0x0C801,27,0x100}, {0x0C81C,1,0x080},
    {0x0C81D,27,0x100}, {0x0C838,1,0x080},
    {0x0C839,27,0x100}, {0x0C854,1,0x080},
    {0x0C855,27,0x100}, {0x0C870,1,0x080},
    {0x0C871,27,0x100}, {0x0C88C,1,0x080},
    {0x0C88D,27,0x100}, {0x0C8A8,1,0x080},
    {0x0C8A9,27,0x100}, {0x0C8C4,1,0x080},
    {0x0C8C5,27,0x100}, {0x0C8E0,1,0x080},
    {0x0C8E1,27,0x100}, {0x0C8FC,1,0x080},
    {0x0C8FD,27,0x100}, {0x0C918,1,0x080},
    {0x0C919,27,0x100}, {0x0C934,1,0x080},
    {0x0C935,27,0x100}, {0x0C950,1,0x080},
    {0x0C951,27,0x100}, {0x0C96C,1,0x080},
    {0x0C96D,27,0x100}, {0x0C988,1,0x080},
    {0x0C989,27,0x100}, {0x0C9A4,1,0x080},
    {0x0C9A5,27,0x100}, {0x0C9C0,1,0x080},
    {0x0C9C1,27,0x100}, {0x0C9DC,1,0x080},
    {0x0C9DD,27,0x100}, {0x0C9F8,1,0x080},
    {0x0C9F9,27,0x100}, {0x0CA14,1,0x080},
    {0x0CA15,27,0x100}, {0x0CA30,1,0x080},
    {0x0CA31,27,0x100}, {0x0CA4C,1,0x080},
    {0x0CA4D,27,0x100}, {0x0CA68,1,0x080},
    {0x0CA69,27,0x100}, {0x0CA84,1,0x080},
    {0x0CA85,27,0x100}, {0x0CAA0,1,0x080},
    {0x0CAA1,27,0x100}, {0x0CABC,1,0x080},
    {0x0CABD,27,0x100}, {0x0CAD8,1,0x080},
    {0x0CAD9,27,0x100}, {0x0CAF4,1,0x080},
    {0x0CAF5,27,0x100}, {0x0CB10,1,0x080},
    {0x0CB11,27,0x100}, {0x0CB2C,1,0x080},
    {0x0CB2D,27,0x100}, {0x0CB48,1,0x080},
    {0x0CB49,27,0x100}, {0x0CB64,1,0x080},
    {0x0CB65,27,0x100}, {0x0CB80,1,0x080},
    {0x0CB81,27,0x100}, {0x0CB9C,1,0x080},
    {0x0CB9D,27,0x100}, {0x0CBB8,1,0x080},
    {0x0CBB9,27,0x100}, {0x0CBD4,1,0x080},
    {0x0CBD5,27,0x100}, {0x0CBF0,1,0x080},
    {0x0CBF1,27,0x100}, {0x0CC0C,1,0x080},
    {0x0CC0D,27,0x100}, {0x0CC28,1,0x080},
    {0x0CC29,27,0x100}, {0x0CC44,1,0x080},
    {0x0CC45,27,0x100}, {0x0CC60,1,0x080},
    {0x0CC61,27,0x100}, {0x0CC7C,1,0x080},
    {0x0CC7D,27,0x100}, {0x0CC98,1,0x080},
    {0x0CC99,27,0x100}, {0x0CCB4,1,0x080},
    {0x0CCB5,27,0x100}, {0x0CCD0,1,0x080},
    {0x0CCD1,27,0x100}, {0x0CCEC,1,0x080},
    {0x0CCED,27,0x100}, {0x0CD08,1,0x080},
    {0x0CD09,27,0x100}, {0x0CD24,1,0x080},
    {0x0CD25,27,0x100}, {0x0CD40,1,0x080},
    {0x0CD41,27,0x100}, {0x0CD5C,1,0x080},
    {0x0CD5D,27,0x100}, {0x0CD78,1,0x080},
    {0x0CD79,27,0x100}, {0x0CD94,1,0x080},
    {0x0CD95,27,0x100}, {0x0CDB0,1,0x080},
    {0x0CDB1,27,0x100}, {0x0CDCC,1,0x080},
    {0x0CDCD,27,0x100}, {0x0CDE8,1,0x080},
    {0x0CDE9,27,0x100}, {0x0CE04,1,0x080},
    {0x0CE05,27,0x100}, {0x0CE20,1,0x080},
    {0x0CE21,27,0x100}, {0x0CE3C,1,0x080},
    {0x0CE3D,27,0x100}, {0x0CE58,1,0x080},
    {0x0CE59,27,0x100}, {0x0CE74,1,0x080},
    {0x0CE75,27,0x100}, {0x0CE90,1,0x080},
    {0x0CE91,27,0x100}, {0x0CEAC,1,0x080},
    {0x0CEAD,27,0x100}, {0x0CEC8,1,0x080},
    {0x0CEC9,27,0x100}, {0x0CEE4,1,0x080},
    {0x0CEE5,27,0x100}, {0x0CF00,1,0x080},
    {0x0CF01,27,0x100}, {0x0CF1C,1,0x080},
    {0x0CF1D,27,0x100}, {0x0CF38,1,0x080},
    {0x0CF39,27,0x100}, {0x0CF54,1,0x080},
    {0x0CF55,27,0x100}, {0x0CF70,1,0x080},
    {0x0CF71,27,0x100}, {0x0CF8C,1,0x080},
    {0x0CF8D,27,0x100}, {0x0CFA8,1,0x080},
    {0x0CFA9,27,0x100}, {0x0CFC4,1,0x080},
    {0x0CFC5,27,0x100}, {0x0CFE0,1,0x080},
    {0x0CFE1,27,0x100}, {0x0CFFC,1,0x080},
    {0x0CFFD,27,0x100}, {0x0D018,1,0x080},
    {0x0D019,27,0x100}, {0x0D034,1,0x080},
    {0x0D035,27,0x100}, {0x0D050,1,0x080},
    {0x0D051,27,0x100}, {0x0D06C,1,0x080},
    {0x0D06D,27,0x100}, {0x0D088,1,0x080},
    {0x0D089,27,0x100}, {0x0D0A4,1,0x080},
    {0x0D0A5,27,0x100}, {0x0D0C0,1,0x080},
    {0x0D0C1,27,0x100}, {0x0D0DC,1,0x080},
    {0x0D0DD,27,0x100}, {0x0D0F8,1,0x080},
    {0x0D0F9,27,0x100}, {0x0D114,1,0x080},
    {0x0D115,27,0x100}, {0x0D130,1,0x080},
    {0x0D131,27,0x100}, {0x0D14C,1,0x080},
    {0x0D14D,27,0x100}, {0x0D168,1,0x080},
    {0x0D169,27,0x100}, {0x0D184,1,0x080},
    {0x0D185,27,0x100}, {0x0D1A0,1,0x080},
    {0x0D1A1,27,0x100}, {0x0D1BC,1,0x080},
    {0x0D1BD,27,0x100}, {0x0D1D8,1,0x080},
    {0x0D1D9,27,0x100}, {0x0D1F4,1,0x080},
    {0x0D1F5,27,0x100}, {0x0D210,1,0x080},
    {0x0D211,27,0x100}, {0x0D22C,1,0x080},
    {0x0D22D,27,0x100}, {0x0D248,1,0x080},
    {0x0D249,27,0x100}, {0x0D264,1,0x080},
    {0x0D265,27,0x100}, {0x0D280,1,0x080},
    {0x0D281,27,0x100}, {0x0D29C,1,0x080},
    {0x0D29D,27,0x100}, {0x0D2B8,1,0x080},
    {0x0D2B9,27,0x100}, {0x0D2D4,1,0x080},
    {0x0D2D5,27,0x100}, {0x0D2F0,1,0x080},
    {0x0D2F1,27,0x100}, {0x0D30C,1,0x080},
    {0x0D30D,27,0x100}, {0x0D328,1,0x080},
    {0x0D329,27,0x100}, {0x0D344,1,0x080},
    {0x0D345,27,0x100}, {0x0D360,1,0x080},
    {0x0D361,27,0x100}, {0x0D37C,1,0x080},
    {0x0D37D,27,0x100}, {0x0D398,1,0x080},
    {0x0D399,27,0x100}, {0x0D3B4,1,0x080},
    {0x0D3B5,27,0x100}, {0x0D3D0,1,0x080},
    {0x0D3D1,27,0x100}, {0x0D3EC,1,0x080},
    {0x0D3ED,27,0x100}, {0x0D408,1,0x080},
    {0x0D409,27,0x100}, {0x0D424,1,0x080},
    {0x0D425,27,0x100}, {0x0D440,1,0x080},
    {0x0D441,27,0x100}, {0x0D45C,1,0x080},
    {0x0D45D,27,0x100}, {0x0D478,1,0x080},
    {0x0D479,27,0x100}, {0x0D494,1,0x080},
    {0x0D495,27,0x100}, {0x0D4B0,1,0x080},
    {0x0D4B1,27,0x100}, {0x0D4CC,1,0x080},
    {0x0D4CD,27,0x100}, {0x0D4E8,1,0x080},
    {0x0D4E9,27,0x100}, {0x0D504,1,0x080},
    {0x0D505,27,0x100}, {0x0D520,1,0x080},
    {0x0D521,27,0x100}, {0x0D53C,1,0x080},
    {0x0D53D,27,0x100}, {0x0D558,1,0x080},
    {0x0D559,27,0x100}, {0x0D574,1,0x080},
    {0x0D575,27,0x100}, {0x0D590,1,0x080},
    {0x0D591,27,0x100}, {0x0D5AC,1,0x080},
    {0x0D5AD,27,0x100}, {0x0D5C8,1,0x080},
    {0x0D5C9,27,0x100}, {0x0D5E4,1,0x080},
    {0x0D5E5,27,0x100}, {0x0D600,1,0x080},
    {0x0D601,27,0x100}, {0x0D61C,1,0x080},
    {0x0D61D,27,0x100}, {0x0D638,1,0x080},
    {0x0D639,27,0x100}, {0x0D654,1,0x080},
    {0x0D655,27,0x100}, {0x0D670,1,0x080},
    {0x0D671,27,0x100}, {0x0D68C,1,0x080},
    {0x0D68D,27,0x100}, {0x0D6A8,1,0x080},
    {0x0D6A9,27,0x100}, {0x0D6C4,1,0x080},
    {0x0D6C5,27,0x100}, {0x0D6E0,1,0x080},
    {0x0D6E1,27,0x100}, {0x0D6FC,1,0x080},
    {0x0D6FD,27,0x100}, {0x0D718,1,0x080},
    {0x0D719,27,0x100}, {0x0D734,1,0x080},
    {0x0D735,27,0x100}, {0x0D750,1,0x080},
    {0x0D751,27,0x100}, {0x0D76C,1,0x080},
    {0x0D76D,27,0x100}, {0x0D788,1,0x080},
    {0x0D789,27,0x100}, {0x0FB1E,1,0x002},
    {0x0FE00,16,0x002}, {0x0FE20,7,0x002},
    {0x0FEFF,1,0x001}, {0x0FF9E,2,0x002},
    {0x0FFF9,3,0x001}, {0x101FD,1,0x002},
    {0x10A01,3,0x002}, {0x10A05,2,0x002},
    {0x10A0C,4,0x002}, {0x10A38,3,0x002},
    {0x10A3F,1,0x002}, {0x1D165,1,0x002},
    {0x1D166,1,0x008}, {0x1D167,3,0x002},
    {0x1D16D,1,0x008}, {0x1D16E,5,0x002},
    {0x1D173,8,0x001}, {0x1D17B,8,0x002},
    {0x1D185,7,0x002}, {0x1D1AA,4,0x002},
    {0x1D242,3,0x002}, {0xE0001,1,0x001},
    {0xE0020,96,0x001}, {0xE0100,240,0x002},
};

static int
grapheme_cmp(const void *p1, const void *p2)
{
    const struct graphme_table_t *k = p1;
    const struct graphme_table_t *v = p2;
    OnigCodePoint c = k->codepoint_min;
    if (c < v->codepoint_min)
        return -1;
    if (v->codepoint_min + v->num_codepoints <= c)
        return 1;
    return 0;
}

static unsigned int
get_grapheme_properties(OnigCodePoint c)
{
    struct graphme_table_t key, *found;
    key.codepoint_min = c;
    found = bsearch(&key, graphme_table, sizeof(graphme_table)/sizeof(*graphme_table),
                sizeof(*graphme_table), grapheme_cmp);
    if (found)
        return found->properties;
    return 0;
}

/* Stream-Safe Text Format assumed
 * http://unicode.org/reports/tr15/ */
#define MAX_BYTES_LENGTH 128

static OnigCodePoint mbc_to_code0(const UChar* p, const UChar* end, int len);

static int
grapheme_boundary_p(int props1, int props2)
{
    if (props2 & GRAPHEME_BIT_CONTROL)
        return 1;
    if (((props1 & GRAPHEME_BIT_L) &&   (props2 & (GRAPHEME_BIT_L|
                                                   GRAPHEME_BIT_V|
                                                   GRAPHEME_BIT_LV|
                                                   GRAPHEME_BIT_LVT))) ||
        ((props1 & (GRAPHEME_BIT_LV|
                    GRAPHEME_BIT_V)) && (props2 & (GRAPHEME_BIT_V|
                                                   GRAPHEME_BIT_T))) ||
        ((props1 & (GRAPHEME_BIT_LVT|
                    GRAPHEME_BIT_T)) && (props2 & GRAPHEME_BIT_T)))
        return 0;
    if (props2 & (GRAPHEME_BIT_EXTEND|
                  GRAPHEME_BIT_SPACINGMARK))
        return 0;
    if (props1 & GRAPHEME_BIT_PREPEND)
        return 0;
    return 1;
}

static int
comb_char_enc_len(const UChar* p, const UChar* e, OnigEncoding enc ARG_UNUSED)
{
    /* 
     * this implements extended grapheme clusters ("user-perceived characters")
     * http://www.unicode.org/reports/tr29/
     */
    int r1, l1, r2, l2;
    OnigCodePoint c1, c2;
    unsigned int p1, p2;
    r1 = mbc_enc_len(p, e, enc);
    if (!ONIGENC_MBCLEN_CHARFOUND_P(r1))
        return r1;
    l1 = ONIGENC_MBCLEN_CHARFOUND_LEN(r1);
    c1 = mbc_to_code0(p, e, l1);
    p1 = get_grapheme_properties(c1);

    if (p + l1 == e)
        return r1;

    while (p + l1 < e && l1 < MAX_BYTES_LENGTH-4) {
        if (p1 & GRAPHEME_BIT_CONTROL)
            return ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(l1);
        r2 = mbc_enc_len(p+l1, e, enc);
        if (ONIGENC_MBCLEN_INVALID_P(r2))
            return ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(l1);
        if (ONIGENC_MBCLEN_NEEDMORE_P(r2))
            return r2;
        l2 = ONIGENC_MBCLEN_CHARFOUND_LEN(r2);
        c2 = mbc_to_code0(p+l1, e, l2);
        p2 = get_grapheme_properties(c2);
        if (grapheme_boundary_p(p1, p2))
            return ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(l1);
        l1 += l2;
        p1 = p2;
    }
    /* if p+l1==e, charfound AND needmore */
    return ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(l1);
}

static int
is_mbc_newline(const UChar* p, const UChar* end, OnigEncoding enc)
{
  if (p < end) {
    if (*p == 0x0a) return 1;

#ifdef USE_UNICODE_ALL_LINE_TERMINATORS
#ifndef USE_CRNL_AS_LINE_TERMINATOR
    if (*p == 0x0d) return 1;
#endif
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
mbc_to_code0(const UChar* p, const UChar* end, int len)
{
  int c;
  OnigCodePoint n;

  c = *p++;
  if (len > 1) {
    len--;
    n = c & ((1 << (6 - len)) - 1);
    while (len--) {
      c = *p++;
      n = (n << 6) | (c & ((1 << 6) - 1));
    }
    return n;
  }
  else {
#ifdef USE_INVALID_CODE_SCHEME
    if (c > 0xfd) {
      return ((c == 0xfe) ? INVALID_CODE_FE : INVALID_CODE_FF);
    }
#endif
    return (OnigCodePoint )c;
  }
}

static OnigCodePoint
mbc_to_code(const UChar* p, const UChar* end, int *precise_ret, OnigEncoding enc)
{
  int len;
  int ret;

  ret = mbc_enc_len(p, end, enc);
  if (precise_ret)
    *precise_ret = ret;
  if (ONIGENC_MBCLEN_CHARFOUND_P(ret))
    len = ONIGENC_MBCLEN_CHARFOUND_LEN(ret);
  else if (ONIGENC_MBCLEN_NEEDMORE_P(ret))
    len = end-p+ONIGENC_MBCLEN_NEEDMORE_LEN(ret);
  else
    len = 1;
  return mbc_to_code0(p, end, len);
}

static int
code_to_mbclen(OnigCodePoint code, OnigEncoding enc ARG_UNUSED)
{
  if      ((code & 0xffffff80) == 0) return 1;
  else if ((code & 0xfffff800) == 0) return 2;
  else if ((code & 0xffff0000) == 0) return 3;
  else if ((code & 0xffe00000) == 0) return 4;
  else if ((code & 0xfc000000) == 0) return 5;
  else if ((code & 0x80000000) == 0) return 6;
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
    else if ((code & 0xffe00000) == 0) {
      *p++ = (UChar )(((code>>18) & 0x07) | 0xf0);
      *p++ = UTF8_TRAILS(code, 12);
      *p++ = UTF8_TRAILS(code,  6);
    }
    else if ((code & 0xfc000000) == 0) {
      *p++ = (UChar )(((code>>24) & 0x03) | 0xf8);
      *p++ = UTF8_TRAILS(code, 18);
      *p++ = UTF8_TRAILS(code, 12);
      *p++ = UTF8_TRAILS(code,  6);
    }
    else if ((code & 0x80000000) == 0) {
      *p++ = (UChar )(((code>>30) & 0x01) | 0xfc);
      *p++ = UTF8_TRAILS(code, 24);
      *p++ = UTF8_TRAILS(code, 18);
      *p++ = UTF8_TRAILS(code, 12);
      *p++ = UTF8_TRAILS(code,  6);
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
    return p - buf;
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

static UChar*
left_adjust_combchar_head(const UChar* start, const UChar* s, const UChar* end, OnigEncoding enc ARG_UNUSED)
{
    const UChar *p = left_adjust_char_head(start, s, end, enc);
    const UChar *q;
    OnigCodePoint c1, c2;
    unsigned int p1, p2;

    c2 = mbc_to_code(p, end, NULL, enc);
    p2 = get_grapheme_properties(c2);

    while (start < p) {
        q = left_adjust_char_head(start, p-1, end, enc);
        c1 = mbc_to_code(q, end, NULL, enc);
        p1 = get_grapheme_properties(c1);
        if (grapheme_boundary_p(p1, p2))
            break;
        c2 = c1;
        p2 = p1;
        p = q;
    }
    return (UChar *)p;
}

static int
get_case_fold_codes_by_str(OnigCaseFoldType flag,
    const OnigUChar* p, const OnigUChar* end, OnigCaseFoldCodeItem items[],
    OnigEncoding enc)
{
  return onigenc_unicode_get_case_fold_codes_by_str(enc, flag, p, end, items);
}

OnigEncodingDefine(utf_8, UTF_8) = {
  comb_char_enc_len,
  "UTF-8",     /* name */
  MAX_BYTES_LENGTH, /* max byte length */
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
  left_adjust_combchar_head,
  onigenc_always_false_is_allowed_reverse_match
};
ENC_ALIAS("CP65001", "UTF-8")

/*
 * Name: UTF8-MAC
 * Link: http://developer.apple.com/documentation/MacOSX/Conceptual/BPFileSystem/BPFileSystem.html
 * Link: http://developer.apple.com/qa/qa2001/qa1235.html
 * Link: http://developer.apple.com/jp/qa/qa2001/qa1235.html
 */
ENC_REPLICATE("UTF8-MAC", "UTF-8")
ENC_ALIAS("UTF-8-MAC", "UTF8-MAC")

