/**********************************************************************
  utf8.c -  Oniguruma (regular expression library)
**********************************************************************/
/*-
 * Copyright (c) 2002-2004  K.Kosako  <kosako AT sofnec DOT co DOT jp>
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

static int EncLen_UTF8[] = {
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
  4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 1, 1
};

static int
utf8_mbc_enc_len(UChar* p)
{
  return EncLen_UTF8[*p];
}

static OnigCodePoint
utf8_mbc_to_code(UChar* p, UChar* end)
{
  int c, len;
  OnigCodePoint n;

  len = enc_len(ONIG_ENCODING_UTF8, p);
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

static int
utf8_code_to_mbclen(OnigCodePoint code)
{
  if      ((code & 0xffffff80) == 0) return 1;
  else if ((code & 0xfffff800) == 0) {
    if (code <= 0xff && code >= 0xfe)
      return 1;
    return 2;
  }
  else if ((code & 0xffff0000) == 0) return 3;
  else if ((code & 0xffe00000) == 0) return 4;
  else if ((code & 0xfc000000) == 0) return 5;
  else if ((code & 0x80000000) == 0) return 6;
#ifdef USE_INVALID_CODE_SCHEME
  else if (code == INVALID_CODE_FE) return 1;
  else if (code == INVALID_CODE_FF) return 1;
#endif
  else
    return ONIGENCERR_TOO_BIG_WIDE_CHAR_VALUE;
}

#if 0
static int
utf8_code_to_mbc_first(OnigCodePoint code)
{
  if ((code & 0xffffff80) == 0)
    return code;
  else {
    if ((code & 0xfffff800) == 0)
      return ((code>>6)& 0x1f) | 0xc0;
    else if ((code & 0xffff0000) == 0)
      return ((code>>12) & 0x0f) | 0xe0;
    else if ((code & 0xffe00000) == 0)
      return ((code>>18) & 0x07) | 0xf0;
    else if ((code & 0xfc000000) == 0)
      return ((code>>24) & 0x03) | 0xf8;
    else if ((code & 0x80000000) == 0)
      return ((code>>30) & 0x01) | 0xfc;
    else {
      return ONIGENCERR_TOO_BIG_WIDE_CHAR_VALUE;
    }
  }
}
#endif

static int
utf8_code_to_mbc(OnigCodePoint code, UChar *buf)
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
      return ONIGENCERR_TOO_BIG_WIDE_CHAR_VALUE;
    }

    *p++ = UTF8_TRAIL0(code);
    return p - buf;
  }
}

static int
utf8_mbc_to_normalize(OnigAmbigType flag, UChar** pp, UChar* end, UChar* lower)
{
  UChar* p = *pp;

  if (ONIGENC_IS_MBC_ASCII(p)) {
    if (end > p + 1 &&
        (flag & ONIGENC_AMBIGUOUS_MATCH_COMPOUND) != 0 &&
	((*p == 's' && *(p+1) == 's') ||
	 ((flag & ONIGENC_AMBIGUOUS_MATCH_ASCII_CASE) != 0 &&
	  (*p == 'S' && *(p+1) == 'S')))) {
      *lower++ = '\303';
      *lower   = '\237';
      (*pp) += 2;
      return 2;
    }

    if ((flag & ONIGENC_AMBIGUOUS_MATCH_ASCII_CASE) != 0) {
      *lower = ONIGENC_ASCII_CODE_TO_LOWER_CASE(*p);
    }
    else {
      *lower = *p;
    }
    (*pp)++;
    return 1; /* return byte length of converted char to lower */
  }
  else {
    int len;

    if (*p == 195) { /* 195 == '\303' */
      int c = *(p + 1);
      if (c >= 128) {
        if (c <= '\236' &&  /* upper */
            (flag & ONIGENC_AMBIGUOUS_MATCH_NONASCII_CASE) != 0) {
          if (c != '\227') {
            *lower++ = *p;
            *lower   = (UChar )(c + 32);
            (*pp) += 2;
            return 2;
          }
        }
#if 0
        else if (c == '\237' &&
                 (flag & ONIGENC_AMBIGUOUS_MATCH_COMPOUND) != 0) {
          *lower++ = '\303';
          *lower   = '\237';
          (*pp) += 2;
          return 2;
        }
#endif
      }
    }

    len = enc_len(ONIG_ENCODING_UTF8, p);
    if (lower != p) {
      int i;
      for (i = 0; i < len; i++) {
	*lower++ = *p++;
      }
    }
    (*pp) += len;
    return len; /* return byte length of converted char to lower */
  }
}

static int
utf8_is_mbc_ambiguous(OnigAmbigType flag, UChar** pp, UChar* end)
{
  UChar* p = *pp;

  if (ONIGENC_IS_MBC_ASCII(p)) {
    if (end > p + 1 &&
        (flag & ONIGENC_AMBIGUOUS_MATCH_COMPOUND) != 0 &&
	((*p == 's' && *(p+1) == 's') ||
	 ((flag & ONIGENC_AMBIGUOUS_MATCH_ASCII_CASE) != 0 &&
	  (*p == 'S' && *(p+1) == 'S')))) {
      (*pp) += 2;
      return TRUE;
    }

    (*pp)++;
    if ((flag & ONIGENC_AMBIGUOUS_MATCH_ASCII_CASE) != 0) {
      return ONIGENC_IS_ASCII_CODE_CASE_AMBIG(*p);
    }
  }
  else {
    (*pp) += enc_len(ONIG_ENCODING_UTF8, p);

    if (*p == 195) { /* 195 == '\303' */
      int c = *(p + 1);
      if (c >= 128) {
        if ((flag & ONIGENC_AMBIGUOUS_MATCH_NONASCII_CASE) != 0) {
          if (c <= '\236') { /* upper */
            if (c == '\227') return FALSE;
            return TRUE;
          }
          else if (c >= '\240' && c <= '\276') { /* lower */
            if (c == '\267') return FALSE;
            return TRUE;
          }
        }
        else if (c == '\237' &&
                 (flag & ONIGENC_AMBIGUOUS_MATCH_COMPOUND) != 0) {
	  return TRUE;
        }
      }
    }
  }

  return FALSE;
}

static int
utf8_is_code_ctype(OnigCodePoint code, unsigned int ctype)
{
  if (code < 256) {
    return ONIGENC_IS_UNICODE_ISO_8859_1_CTYPE(code, ctype);
  }

  if ((ctype & ONIGENC_CTYPE_WORD) != 0) {
#ifdef USE_INVALID_CODE_SCHEME
    if (code <= VALID_CODE_LIMIT)
#endif
      return TRUE;
  }

  return FALSE;
}

static int
utf8_get_ctype_code_range(int ctype, int* nsb, int* nmb,
			  OnigCodePointRange* sbr[], OnigCodePointRange* mbr[])
{
#define CR_SET(sbl,mbl) do { \
  *nsb = sizeof(sbl) / sizeof(OnigCodePointRange); \
  *nmb = sizeof(mbl) / sizeof(OnigCodePointRange); \
  *sbr = sbl; \
  *mbr = mbl; \
} while (0)

#define CR_SB_SET(sbl) do { \
  *nsb = sizeof(sbl) / sizeof(OnigCodePointRange); \
  *nmb = 0; \
  *sbr = sbl; \
} while (0)

  static OnigCodePointRange SBAlpha[] = {
    { 0x41, 0x5a }, { 0x61, 0x7a }
  };

  static OnigCodePointRange MBAlpha[] = {
    { 0xaa, 0xaa }, { 0xb5, 0xb5 },
    { 0xba, 0xba }, { 0xc0, 0xd6 },
    { 0xd8, 0xf6 }, { 0xf8, 0x220 }
  };

  static OnigCodePointRange SBBlank[] = {
    { 0x09, 0x09 }, { 0x20, 0x20 }
  };

  static OnigCodePointRange MBBlank[] = {
    { 0xa0, 0xa0 }
  };

  static OnigCodePointRange SBCntrl[] = {
    { 0x00, 0x1f }, { 0x7f, 0x7f }
  };

  static OnigCodePointRange MBCntrl[] = {
    { 0x80, 0x9f }
  };

  static OnigCodePointRange SBDigit[] = {
    { 0x30, 0x39 }
  };

  static OnigCodePointRange SBGraph[] = {
    { 0x21, 0x7e }
  };

  static OnigCodePointRange MBGraph[] = {
    { 0xa1, 0x220 }
  };

  static OnigCodePointRange SBLower[] = {
    { 0x61, 0x7a }
  };

  static OnigCodePointRange MBLower[] = {
    { 0xaa, 0xaa }, { 0xb5, 0xb5 },
    { 0xba, 0xba }, { 0xdf, 0xf6 },
    { 0xf8, 0xff }
  };

  static OnigCodePointRange SBPrint[] = {
    { 0x20, 0x7e }
  };

  static OnigCodePointRange MBPrint[] = {
    { 0xa0, 0x220 }
  };

  static OnigCodePointRange SBPunct[] = {
    { 0x21, 0x23 }, { 0x25, 0x2a },
    { 0x2c, 0x2f }, { 0x3a, 0x3b },
    { 0x3f, 0x40 }, { 0x5b, 0x5d },
    { 0x5f, 0x5f }, { 0x7b, 0x7b },
    { 0x7d, 0x7d }
  };

  static OnigCodePointRange MBPunct[] = {
    { 0xa1, 0xa1 }, { 0xab, 0xab },
    { 0xad, 0xad }, { 0xb7, 0xb7 },
    { 0xbb, 0xbb }, { 0xbf, 0xbf }
  };

  static OnigCodePointRange SBSpace[] = {
    { 0x09, 0x0d }, { 0x20, 0x20 }
  };

  static OnigCodePointRange MBSpace[] = {
    { 0xa0, 0xa0 }
  };

  static OnigCodePointRange SBUpper[] = {
    { 0x41, 0x5a }
  };

  static OnigCodePointRange MBUpper[] = {
    { 0xc0, 0xd6 }, { 0xd8, 0xde }
  };

  static OnigCodePointRange SBXDigit[] = {
    { 0x30, 0x39 }, { 0x41, 0x46 },
    { 0x61, 0x66 }
  };

  static OnigCodePointRange SBWord[] = {
    { 0x30, 0x39 }, { 0x41, 0x5a },
    { 0x5f, 0x5f }, { 0x61, 0x7a }
  };

  static OnigCodePointRange MBWord[] = {
    { 0xaa, 0xaa }, { 0xb2, 0xb3 },
    { 0xb5, 0xb5 }, { 0xb9, 0xba },
    { 0xbc, 0xbe }, { 0xc0, 0xd6 },
    { 0xd8, 0xf6 },
#if 0
    { 0xf8, 0x220 }
#else
    { 0xf8, 0x7fffffff } /* all multibyte code as word */
#endif
  };

  static OnigCodePointRange SBAscii[] = {
    { 0x00, 0x7f }
  };

  static OnigCodePointRange SBAlnum[] = {
    { 0x30, 0x39 }, { 0x41, 0x5a },
    { 0x61, 0x7a }
  };

  static OnigCodePointRange MBAlnum[] = {
    { 0xaa, 0xaa }, { 0xb5, 0xb5 },
    { 0xba, 0xba }, { 0xc0, 0xd6 },
    { 0xd8, 0xf6 }, { 0xf8, 0x220 }
  };

  switch (ctype) {
  case ONIGENC_CTYPE_ALPHA:
    CR_SET(SBAlpha, MBAlpha);
    break;
  case ONIGENC_CTYPE_BLANK:
    CR_SET(SBBlank, MBBlank);
    break;
  case ONIGENC_CTYPE_CNTRL:
    CR_SET(SBCntrl, MBCntrl);
    break;
  case ONIGENC_CTYPE_DIGIT:
    CR_SB_SET(SBDigit);
    break;
  case ONIGENC_CTYPE_GRAPH:
    CR_SET(SBGraph, MBGraph);
    break;
  case ONIGENC_CTYPE_LOWER:
    CR_SET(SBLower, MBLower);
    break;
  case ONIGENC_CTYPE_PRINT:
    CR_SET(SBPrint, MBPrint);
    break;
  case ONIGENC_CTYPE_PUNCT:
    CR_SET(SBPunct, MBPunct);
    break;
  case ONIGENC_CTYPE_SPACE:
    CR_SET(SBSpace, MBSpace);
    break;
  case ONIGENC_CTYPE_UPPER:
    CR_SET(SBUpper, MBUpper);
    break;
  case ONIGENC_CTYPE_XDIGIT:
    CR_SB_SET(SBXDigit);
    break;
  case ONIGENC_CTYPE_WORD:
    CR_SET(SBWord, MBWord);
    break;
  case ONIGENC_CTYPE_ASCII:
    CR_SB_SET(SBAscii);
    break;
  case ONIGENC_CTYPE_ALNUM:
    CR_SET(SBAlnum, MBAlnum);
    break;

  default:
    return ONIGENCERR_TYPE_BUG;
    break;
  }

  return 0;
}

static UChar*
utf8_left_adjust_char_head(UChar* start, UChar* s)
{
  UChar *p;

  if (s <= start) return s;
  p = s;

  while (!utf8_islead(*p) && p > start) p--;
  return p;
}

OnigEncodingType OnigEncodingUTF8 = {
  utf8_mbc_enc_len,
  "UTF-8",     /* name */
  6,           /* max byte length */
  1,           /* min byte length */
  (ONIGENC_AMBIGUOUS_MATCH_ASCII_CASE | 
   ONIGENC_AMBIGUOUS_MATCH_NONASCII_CASE | 
   ONIGENC_AMBIGUOUS_MATCH_COMPOUND),
  {
      (OnigCodePoint )'\\'                       /* esc */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* anychar '.'  */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* anytime '*'  */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* zero or one time '?' */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* one or more time '+' */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* anychar anytime */
  },
  onigenc_is_mbc_newline_0x0a,
  utf8_mbc_to_code,
  utf8_code_to_mbclen,
  utf8_code_to_mbc,
  utf8_mbc_to_normalize,
  utf8_is_mbc_ambiguous,
  onigenc_iso_8859_1_get_all_pair_ambig_codes,
  onigenc_ess_tsett_get_all_comp_ambig_codes,
  utf8_is_code_ctype,
  utf8_get_ctype_code_range,
  utf8_left_adjust_char_head,
  onigenc_always_true_is_allowed_reverse_match
};
