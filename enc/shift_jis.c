/**********************************************************************
  sjis.c -  Oniguruma (regular expression library)
**********************************************************************/
/*-
 * Copyright (c) 2002-2008  K.Kosako  <sndgk393 AT ybb DOT ne DOT jp>
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

#include "regint.h"

static const int EncLen_SJIS[] = {
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1
};

static const char SJIS_CAN_BE_TRAIL_TABLE[256] = {
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0
};

#define SJIS_ISMB_FIRST(byte)  (EncLen_SJIS[byte] > 1)
#define SJIS_ISMB_TRAIL(byte)  SJIS_CAN_BE_TRAIL_TABLE[(byte)]

typedef enum { FAILURE = -2, ACCEPT = -1, S0 = 0, S1 } state_t;
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
    /* 8 */ F, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* 9 */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* a */ F, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* b */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* c */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* d */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* e */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    /* f */ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, F, F, F
  },
  { /* S1   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /* 0 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 1 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 2 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 3 */ F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
    /* 4 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 5 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 6 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 7 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, F,
    /* 8 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* 9 */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* a */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* b */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* c */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* d */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* e */ A, A, A, A, A, A, A, A, A, A, A, A, A, A, A, A,
    /* f */ A, A, A, A, A, A, A, A, A, A, A, A, A, F, F, F
  }
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
  if (p == e) return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(EncLen_SJIS[firstbyte]-1);
  s = trans[s][*p++];
  return s == ACCEPT ? ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(2) :
                       ONIGENC_CONSTRUCT_MBCLEN_INVALID();
}

static int
code_to_mbclen(OnigCodePoint code, OnigEncoding enc ARG_UNUSED)
{
  if (code < 256) {
    if (EncLen_SJIS[(int )code] == 1)
      return 1;
    else
      return 0;
  }
  else if (code <= 0xffff) {
    return 2;
  }
  else
    return ONIGERR_INVALID_CODE_POINT_VALUE;
}

static OnigCodePoint
mbc_to_code(const UChar* p, const UChar* end, OnigEncoding enc)
{
  int c, i, len;
  OnigCodePoint n;

  len = enclen(enc, p, end);
  c = *p++;
  n = c;
  if (len == 1) return n;

  for (i = 1; i < len; i++) {
    if (p >= end) break;
    c = *p++;
    n <<= 8;  n += c;
  }
  return n;
}

static int
code_to_mbc(OnigCodePoint code, UChar *buf, OnigEncoding enc)
{
  UChar *p = buf;

  if ((code & 0xff00) != 0) *p++ = (UChar )(((code >>  8) & 0xff));
  *p++ = (UChar )(code & 0xff);

#if 0
  if (enclen(enc, buf) != (p - buf))
    return REGERR_INVALID_CODE_POINT_VALUE;
#endif
  return (int)(p - buf);
}

static int
mbc_case_fold(OnigCaseFoldType flag,
	      const UChar** pp, const UChar* end, UChar* lower,
	      OnigEncoding enc)
{
  const UChar* p = *pp;

  if (ONIGENC_IS_MBC_ASCII(p)) {
    *lower = ONIGENC_ASCII_CODE_TO_LOWER_CASE(*p);
    (*pp)++;
    return 1;
  }
  else {
    int i;
    int len = enclen(enc, p, end);

    for (i = 0; i < len; i++) {
      *lower++ = *p++;
    }
    (*pp) += len;
    return len; /* return byte length of converted char to lower */
  }
}

#if 0
static int
is_mbc_ambiguous(OnigCaseFoldType flag,
		 const UChar** pp, const UChar* end)
{
  return onigenc_mbn_is_mbc_ambiguous(enc, flag, pp, end);
                                      
}
#endif

#if 0
static int
is_code_ctype(OnigCodePoint code, unsigned int ctype)
{
  if (code < 128)
    return ONIGENC_IS_ASCII_CODE_CTYPE(code, ctype);
  else {
    if (CTYPE_IS_WORD_GRAPH_PRINT(ctype)) {
      return (code_to_mbclen(code) > 1 ? TRUE : FALSE);
    }
  }

  return FALSE;
}
#endif

static UChar*
left_adjust_char_head(const UChar* start, const UChar* s, const UChar* end, OnigEncoding enc)
{
  const UChar *p;
  int len;

  if (s <= start) return (UChar* )s;
  p = s;

  if (SJIS_ISMB_TRAIL(*p)) {
    while (p > start) {
      if (! SJIS_ISMB_FIRST(*--p)) {
	p++;
	break;
      }
    } 
  }
  len = enclen(enc, p, end);
  if (p + len > s) return (UChar* )p;
  p += len;
  return (UChar* )(p + ((s - p) & ~1));
}

static int
is_allowed_reverse_match(const UChar* s, const UChar* end, OnigEncoding enc ARG_UNUSED)
{
  const UChar c = *s;
  return (SJIS_ISMB_TRAIL(c) ? FALSE : TRUE);
}


static int PropertyInited = 0;
static const OnigCodePoint** PropertyList;
static int PropertyListNum;
static int PropertyListSize;
static hash_table_type* PropertyNameTable;

static const OnigCodePoint CR_Hiragana[] = {
  1,
  0x829f, 0x82f1
}; /* CR_Hiragana */

static const OnigCodePoint CR_Katakana[] = {
  4,
  0x00a6, 0x00af,
  0x00b1, 0x00dd,
  0x8340, 0x837e,
  0x8380, 0x8396,
}; /* CR_Katakana */

static int
init_property_list(void)
{
  int r;

  PROPERTY_LIST_ADD_PROP("hiragana", CR_Hiragana);
  PROPERTY_LIST_ADD_PROP("katakana", CR_Katakana);
  PropertyInited = 1;

 end:
  return r;
}

static int
property_name_to_ctype(OnigEncoding enc, UChar* p, UChar* end)
{
  hash_data_type ctype;
  UChar *s, *e;

  PROPERTY_LIST_INIT_CHECK;

  s = e = ALLOCA_N(UChar, end-p+1);
  for (; p < end; p++) {
    *e++ = ONIGENC_ASCII_CODE_TO_LOWER_CASE(*p);
  }

  if (onig_st_lookup_strend(PropertyNameTable, s, e, &ctype) == 0) {
    return onigenc_minimum_property_name_to_ctype(enc, s, e);
  }

  return (int)ctype;
}

static int
is_code_ctype(OnigCodePoint code, unsigned int ctype, OnigEncoding enc)
{
  if (ctype <= ONIGENC_MAX_STD_CTYPE) {
    if (code < 128)
      return ONIGENC_IS_ASCII_CODE_CTYPE(code, ctype);
    else {
      if (CTYPE_IS_WORD_GRAPH_PRINT(ctype)) {
	return TRUE;
      }
    }
  }
  else {
    PROPERTY_LIST_INIT_CHECK;

    ctype -= (ONIGENC_MAX_STD_CTYPE + 1);
    if (ctype >= (unsigned int )PropertyListNum)
      return ONIGERR_TYPE_BUG;

    return onig_is_in_code_range((UChar* )PropertyList[ctype], code);
  }

  return FALSE;
}

static int
get_ctype_code_range(OnigCtype ctype, OnigCodePoint* sb_out,
		     const OnigCodePoint* ranges[], OnigEncoding enc ARG_UNUSED)
{
  if (ctype <= ONIGENC_MAX_STD_CTYPE) {
    return ONIG_NO_SUPPORT_CONFIG;
  }
  else {
    *sb_out = 0x80;

    PROPERTY_LIST_INIT_CHECK;

    ctype -= (ONIGENC_MAX_STD_CTYPE + 1);
    if (ctype >= (OnigCtype )PropertyListNum)
      return ONIGERR_TYPE_BUG;

    *ranges = PropertyList[ctype];
    return 0;
  }
}

OnigEncodingDefine(shift_jis, Shift_JIS) = {
  mbc_enc_len,
  "Shift_JIS",   /* name */
  2,             /* max byte length */
  1,             /* min byte length */
  onigenc_is_mbc_newline_0x0a,
  mbc_to_code,
  code_to_mbclen,
  code_to_mbc,
  mbc_case_fold,
  onigenc_ascii_apply_all_case_fold,
  onigenc_ascii_get_case_fold_codes_by_str,
  property_name_to_ctype,
  is_code_ctype,
  get_ctype_code_range,
  left_adjust_char_head,
  is_allowed_reverse_match,
  0
};
/*
 * Name: Shift_JIS
 * MIBenum: 17
 * Link: http://www.iana.org/assignments/character-sets
 * Link: http://ja.wikipedia.org/wiki/Shift_JIS
 */
ENC_ALIAS("SJIS", "Shift_JIS")

/*
 * Name: Windows-31J
 * MIBenum: 2024
 * Link: http://www.iana.org/assignments/character-sets
 * Link: http://www.microsoft.com/globaldev/reference/dbcs/932.mspx
 * Link: http://ja.wikipedia.org/wiki/Windows-31J
 * Link: http://source.icu-project.org/repos/icu/data/trunk/charset/data/ucm/windows-932-2000.ucm
 */
ENC_REPLICATE("Windows-31J", "Shift_JIS")
ENC_ALIAS("CP932", "Windows-31J")
ENC_ALIAS("csWindows31J", "Windows-31J") /* IANA.  IE6 don't accept Windows-31J but csWindows31J. */

/*
 * Name: MacJapanese
 * Link: http://unicode.org/Public/MAPPINGS/VENDORS/APPLE/JAPANESE.TXT
 * Link: http://ja.wikipedia.org/wiki/MacJapanese
 */
ENC_REPLICATE("MacJapanese", "Shift_JIS")
ENC_ALIAS("MacJapan", "MacJapanese")
