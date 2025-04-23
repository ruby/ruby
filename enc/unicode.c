/**********************************************************************
  unicode.c -  Oniguruma (regular expression library)
**********************************************************************/
/*-
 * Copyright (c) 2002-2013  K.Kosako  <sndgk393 AT ybb DOT ne DOT jp>
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

#define ONIGENC_IS_UNICODE_ISO_8859_1_CTYPE(code,ctype) \
  ((EncUNICODE_ISO_8859_1_CtypeTable[code] & CTYPE_TO_BIT(ctype)) != 0)
#if 0
#define ONIGENC_IS_UNICODE_ISO_8859_1_BIT_CTYPE(code,cbit) \
  ((EncUNICODE_ISO_8859_1_CtypeTable[code] & (cbit)) != 0)
#endif

static const unsigned short EncUNICODE_ISO_8859_1_CtypeTable[256] = {
  0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008,
  0x4008, 0x420c, 0x4209, 0x4208, 0x4208, 0x4208, 0x4008, 0x4008,
  0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008,
  0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008,
  0x4284, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0,
  0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0,
  0x78b0, 0x78b0, 0x78b0, 0x78b0, 0x78b0, 0x78b0, 0x78b0, 0x78b0,
  0x78b0, 0x78b0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0,
  0x41a0, 0x7ca2, 0x7ca2, 0x7ca2, 0x7ca2, 0x7ca2, 0x7ca2, 0x74a2,
  0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2,
  0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2,
  0x74a2, 0x74a2, 0x74a2, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x51a0,
  0x41a0, 0x78e2, 0x78e2, 0x78e2, 0x78e2, 0x78e2, 0x78e2, 0x70e2,
  0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2,
  0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2,
  0x70e2, 0x70e2, 0x70e2, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x4008,
  0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0288, 0x0008, 0x0008,
  0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008,
  0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008,
  0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008,
  0x0284, 0x01a0, 0x00a0, 0x00a0, 0x00a0, 0x00a0, 0x00a0, 0x00a0,
  0x00a0, 0x00a0, 0x30e2, 0x01a0, 0x00a0, 0x00a8, 0x00a0, 0x00a0,
  0x00a0, 0x00a0, 0x10a0, 0x10a0, 0x00a0, 0x30e2, 0x00a0, 0x01a0,
  0x00a0, 0x10a0, 0x30e2, 0x01a0, 0x10a0, 0x10a0, 0x10a0, 0x01a0,
  0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2,
  0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2,
  0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x00a0,
  0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x34a2, 0x30e2,
  0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2,
  0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2,
  0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x00a0,
  0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2, 0x30e2
};

typedef struct {
  int n;
  OnigCodePoint code[3];
} CodePointList3;

typedef struct {
  OnigCodePoint  from;
  CodePointList3 to;
} CaseFold_11_Type;

typedef struct {
  OnigCodePoint  from;
  CodePointList3 to;
} CaseUnfold_11_Type;

typedef struct {
  int n;
  OnigCodePoint code[2];
} CodePointList2;

typedef struct {
  OnigCodePoint  from[2];
  CodePointList2 to;
} CaseUnfold_12_Type;

typedef struct {
  OnigCodePoint  from[3];
  CodePointList2 to;
} CaseUnfold_13_Type;

static inline int
bits_of(const OnigCodePoint c, const int n)
{
  return (c >> (2 - n) * 7) & 127;
}

static inline int
bits_at(const OnigCodePoint *c, const int n)
{
  return bits_of(c[n / 3], n % 3);
}

static int
code1_equal(const OnigCodePoint x, const OnigCodePoint y)
{
  if (x != y) return 0;
  return 1;
}

static int
code2_equal(const OnigCodePoint *x, const OnigCodePoint *y)
{
  if (x[0] != y[0]) return 0;
  if (x[1] != y[1]) return 0;
  return 1;
}

static int
code3_equal(const OnigCodePoint *x, const OnigCodePoint *y)
{
  if (x[0] != y[0]) return 0;
  if (x[1] != y[1]) return 0;
  if (x[2] != y[2]) return 0;
  return 1;
}

/* macros related to ONIGENC_CASE flags */
/* defined here because not used in other files */
#define ONIGENC_CASE_SPECIALS       (ONIGENC_CASE_TITLECASE | ONIGENC_CASE_IS_TITLECASE | ONIGENC_CASE_UP_SPECIAL | ONIGENC_CASE_DOWN_SPECIAL)

/* macros for length in CaseMappingSpecials array in enc/unicode/casefold.h */
#define SpecialsLengthOffset 25  /* needs to be higher than the 22 bits used for Unicode codepoints */
#define SpecialsLengthExtract(n)    ((n) >> SpecialsLengthOffset)
#define SpecialsCodepointExtract(n) ((n) & ((1 << SpecialsLengthOffset) - 1))
#define SpecialsLengthEncode(n)     ((n) << SpecialsLengthOffset)

#define OnigSpecialIndexMask        (((1 << OnigSpecialIndexWidth) - 1) << OnigSpecialIndexShift)
#define OnigSpecialIndexEncode(n)   ((n) << OnigSpecialIndexShift)
#define OnigSpecialIndexDecode(n)   (((n) & OnigSpecialIndexMask) >> OnigSpecialIndexShift)

/* macros to shorten "enc/unicode/casefold.h", undefined immediately after including the file */
#define U ONIGENC_CASE_UPCASE
#define D ONIGENC_CASE_DOWNCASE
#define F ONIGENC_CASE_FOLD
#define ST ONIGENC_CASE_TITLECASE
#define SU ONIGENC_CASE_UP_SPECIAL
#define SL ONIGENC_CASE_DOWN_SPECIAL
#define IT ONIGENC_CASE_IS_TITLECASE
#define I(n) OnigSpecialIndexEncode(n)
#define L(n) SpecialsLengthEncode(n)

#include "casefold.h"

#undef U
#undef D
#undef F
#undef ST
#undef SU
#undef SL
#undef IT
#undef I
#undef L

#include "name2ctype.h"

#define CODE_RANGES_NUM numberof(CodeRanges)

extern int
onigenc_unicode_is_code_ctype(OnigCodePoint code, unsigned int ctype, OnigEncoding enc ARG_UNUSED)
{
  if (
#ifdef USE_UNICODE_PROPERTIES
      ctype <= ONIGENC_MAX_STD_CTYPE &&
#endif
      code < 256) {
    return ONIGENC_IS_UNICODE_ISO_8859_1_CTYPE(code, ctype);
  }

  if (ctype >= CODE_RANGES_NUM) {
    return ONIGERR_TYPE_BUG;
  }

  return onig_is_in_code_range((UChar* )CodeRanges[ctype], code);
}


extern int
onigenc_unicode_ctype_code_range(int ctype, const OnigCodePoint* ranges[])
{
  if (ctype >= CODE_RANGES_NUM) {
    return ONIGERR_TYPE_BUG;
  }

  *ranges = CodeRanges[ctype];

  return 0;
}

extern int
onigenc_utf16_32_get_ctype_code_range(OnigCtype ctype, OnigCodePoint* sb_out,
                                      const OnigCodePoint* ranges[],
				      OnigEncoding enc ARG_UNUSED)
{
  *sb_out = 0x00;
  return onigenc_unicode_ctype_code_range(ctype, ranges);
}

#define PROPERTY_NAME_MAX_SIZE    (MAX_WORD_LENGTH + 1)

extern int
onigenc_unicode_property_name_to_ctype(OnigEncoding enc, const UChar* name, const UChar* end)
{
  int len;
  int ctype;
  UChar buf[PROPERTY_NAME_MAX_SIZE];
  const UChar *p;
  OnigCodePoint code;

  len = 0;
  for (p = name; p < end; p += enclen(enc, p, end)) {
    code = ONIGENC_MBC_TO_CODE(enc, p, end);
    if (code == ' ' || code == '-' || code == '_')
      continue;
    if (code >= 0x80)
      return ONIGERR_INVALID_CHAR_PROPERTY_NAME;

    buf[len++] = ONIGENC_ASCII_CODE_TO_LOWER_CASE(code);
    if (len >= PROPERTY_NAME_MAX_SIZE)
      return ONIGERR_INVALID_CHAR_PROPERTY_NAME;
  }

  buf[len] = 0;

  if ((ctype = uniname2ctype(buf, len)) < 0) {
    return ONIGERR_INVALID_CHAR_PROPERTY_NAME;
  }

  return ctype;
}

#define onigenc_unicode_fold_lookup onigenc_unicode_CaseFold_11_lookup
#define onigenc_unicode_unfold1_lookup onigenc_unicode_CaseUnfold_11_lookup
#define onigenc_unicode_unfold2_lookup onigenc_unicode_CaseUnfold_12_lookup
#define onigenc_unicode_unfold3_lookup onigenc_unicode_CaseUnfold_13_lookup

enum {
  I_WITH_DOT_ABOVE = 0x0130,
  DOTLESS_i = 0x0131,
  DOT_ABOVE = 0x0307
};

extern int
onigenc_unicode_mbc_case_fold(OnigEncoding enc,
    OnigCaseFoldType flag ARG_UNUSED, const UChar** pp, const UChar* end,
    UChar* fold)
{
  const CodePointList3 *to;
  OnigCodePoint code;
  int i, len, rlen;
  const UChar *p = *pp;

  code = ONIGENC_MBC_TO_CODE(enc, p, end);
  len = enclen(enc, p, end);
  *pp += len;

#ifdef USE_UNICODE_CASE_FOLD_TURKISH_AZERI
  if ((flag & ONIGENC_CASE_FOLD_TURKISH_AZERI) != 0) {
    if (code == 'I') {
      return ONIGENC_CODE_TO_MBC(enc, DOTLESS_i, fold);
    }
    else if (code == I_WITH_DOT_ABOVE) {
      return ONIGENC_CODE_TO_MBC(enc, 'i', fold);
    }
  }
#endif

  if ((to = onigenc_unicode_fold_lookup(code)) != 0) {
    if (OnigCodePointCount(to->n) == 1) {
      return ONIGENC_CODE_TO_MBC(enc, to->code[0], fold);
    }
#if 0
    /* NO NEEDS TO CHECK */
    else if ((flag & INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR) != 0)
#else
    else
#endif
    {
      rlen = 0;
      for (i = 0; i < OnigCodePointCount(to->n); i++) {
	len = ONIGENC_CODE_TO_MBC(enc, to->code[i], fold);
	fold += len;
	rlen += len;
      }
      return rlen;
    }
  }

  for (i = 0; i < len; i++) {
    *fold++ = *p++;
  }
  return len;
}

extern int
onigenc_unicode_apply_all_case_fold(OnigCaseFoldType flag,
				    OnigApplyAllCaseFoldFunc f, void* arg,
				    OnigEncoding enc ARG_UNUSED)
{
  const CaseUnfold_11_Type* p11;
  OnigCodePoint code;
  int i, j, k, r;

  for (i = 0; i < numberof(CaseUnfold_11); i++) {
    p11 = &CaseUnfold_11[i];
    for (j = 0; j < OnigCodePointCount(p11->to.n); j++) {
      code = p11->from;
      r = (*f)(p11->to.code[j], &code, 1, arg);
      if (r != 0) return r;

      code = p11->to.code[j];
      r = (*f)(p11->from, &code, 1, arg);
      if (r != 0) return r;

      for (k = 0; k < j; k++) {
	r = (*f)(p11->to.code[j], (OnigCodePoint* )(&p11->to.code[k]), 1, arg);
	if (r != 0) return r;

	r = (*f)(p11->to.code[k], (OnigCodePoint* )(&p11->to.code[j]), 1, arg);
	if (r != 0) return r;
      }
    }
  }

#ifdef USE_UNICODE_CASE_FOLD_TURKISH_AZERI
  if ((flag & ONIGENC_CASE_FOLD_TURKISH_AZERI) != 0) {
    code = DOTLESS_i;
    r = (*f)('I', &code, 1, arg);
    if (r != 0) return r;
    code = 'I';
    r = (*f)(DOTLESS_i, &code, 1, arg);
    if (r != 0) return r;

    code = I_WITH_DOT_ABOVE;
    r = (*f)('i', &code, 1, arg);
    if (r != 0) return r;
    code = 'i';
    r = (*f)(I_WITH_DOT_ABOVE, &code, 1, arg);
    if (r != 0) return r;
  }
  else {
#endif
    for (i = 0; i < numberof(CaseUnfold_11_Locale); i++) {
      p11 = &CaseUnfold_11_Locale[i];
      for (j = 0; j < OnigCodePointCount(p11->to.n); j++) {
	code = p11->from;
	r = (*f)(p11->to.code[j], &code, 1, arg);
	if (r != 0) return r;

	code = p11->to.code[j];
	r = (*f)(p11->from, &code, 1, arg);
	if (r != 0) return r;

	for (k = 0; k < j; k++) {
	  r = (*f)(p11->to.code[j], (OnigCodePoint* )(&p11->to.code[k]),
		   1, arg);
	  if (r != 0) return r;

	  r = (*f)(p11->to.code[k], (OnigCodePoint* )(&p11->to.code[j]),
		   1, arg);
	  if (r != 0) return r;
	}
      }
    }
#ifdef USE_UNICODE_CASE_FOLD_TURKISH_AZERI
  }
#endif

  if ((flag & INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR) != 0) {
    for (i = 0; i < numberof(CaseUnfold_12); i++) {
      for (j = 0; j < OnigCodePointCount(CaseUnfold_12[i].to.n); j++) {
	r = (*f)(CaseUnfold_12[i].to.code[j],
		 (OnigCodePoint* )CaseUnfold_12[i].from, 2, arg);
	if (r != 0) return r;

	for (k = 0; k < OnigCodePointCount(CaseUnfold_12[i].to.n); k++) {
	  if (k == j) continue;

	  r = (*f)(CaseUnfold_12[i].to.code[j],
		   (OnigCodePoint* )(&CaseUnfold_12[i].to.code[k]), 1, arg);
	  if (r != 0) return r;
	}
      }
    }

#ifdef USE_UNICODE_CASE_FOLD_TURKISH_AZERI
    if ((flag & ONIGENC_CASE_FOLD_TURKISH_AZERI) == 0) {
#endif
      for (i = 0; i < numberof(CaseUnfold_12_Locale); i++) {
	for (j = 0; j < OnigCodePointCount(CaseUnfold_12_Locale[i].to.n); j++) {
	  r = (*f)(CaseUnfold_12_Locale[i].to.code[j],
		   (OnigCodePoint* )CaseUnfold_12_Locale[i].from, 2, arg);
	  if (r != 0) return r;

	  for (k = 0; k < OnigCodePointCount(CaseUnfold_12_Locale[i].to.n); k++) {
	    if (k == j) continue;

	    r = (*f)(CaseUnfold_12_Locale[i].to.code[j],
		     (OnigCodePoint* )(&CaseUnfold_12_Locale[i].to.code[k]),
		     1, arg);
	    if (r != 0) return r;
	  }
	}
      }
#ifdef USE_UNICODE_CASE_FOLD_TURKISH_AZERI
    }
#endif

    for (i = 0; i < numberof(CaseUnfold_13); i++) {
      for (j = 0; j < OnigCodePointCount(CaseUnfold_13[i].to.n); j++) {
	r = (*f)(CaseUnfold_13[i].to.code[j],
		 (OnigCodePoint* )CaseUnfold_13[i].from, 3, arg);
	if (r != 0) return r;

	for (k = 0; k < OnigCodePointCount(CaseUnfold_13[i].to.n); k++) {
	  if (k == j) continue;

	  r = (*f)(CaseUnfold_13[i].to.code[j],
		   (OnigCodePoint* )(&CaseUnfold_13[i].to.code[k]), 1, arg);
	  if (r != 0) return r;
	}
      }
    }
  }

  return 0;
}

#define CodePointListValidP(x) (OnigCodePointCount((x)->n) <= numberof((x)->code))

extern int
onigenc_unicode_get_case_fold_codes_by_str(OnigEncoding enc,
    OnigCaseFoldType flag, const OnigUChar* p, const OnigUChar* end,
    OnigCaseFoldCodeItem items[])
{
  int n, i, j, k, len;
  OnigCodePoint code, codes[3];
  const CodePointList3 *to, *z3;
  const CodePointList2 *z2;

  n = 0;

  code = ONIGENC_MBC_TO_CODE(enc, p, end);
  len = enclen(enc, p, end);

#ifdef USE_UNICODE_CASE_FOLD_TURKISH_AZERI
  if ((flag & ONIGENC_CASE_FOLD_TURKISH_AZERI) != 0) {
    switch (code) {
    case 'I':
      items[0].byte_len = len;
      items[0].code_len = 1;
      items[0].code[0]  = DOTLESS_i;
      return 1;
    case I_WITH_DOT_ABOVE:
      items[0].byte_len = len;
      items[0].code_len = 1;
      items[0].code[0]  = 'i';
      return 1;
    case DOTLESS_i:
      items[0].byte_len = len;
      items[0].code_len = 1;
      items[0].code[0]  = 'I';
      return 1;
    case 'i':
      items[0].byte_len = len;
      items[0].code_len = 1;
      items[0].code[0]  = I_WITH_DOT_ABOVE;
      return 1;
    }
  }
#endif

  if ((to = onigenc_unicode_fold_lookup(code)) != 0) {
    if (OnigCodePointCount(to->n) == 0) {
      /* any codepoint should not be empty */
      UNREACHABLE_RETURN(0);
    }
    if (OnigCodePointCount(to->n) == 1) {
      OnigCodePoint orig_code = code;

      items[0].byte_len = len;
      items[0].code_len = 1;
      items[0].code[0]  = to->code[0];
      n++;

      code = to->code[0];
      if ((to = onigenc_unicode_unfold1_lookup(code)) != 0 &&
	  CodePointListValidP(to)) {
	for (i = 0; i < OnigCodePointCount(to->n); i++) {
	  if (to->code[i] != orig_code) {
	    items[n].byte_len = len;
	    items[n].code_len = 1;
	    items[n].code[0]  = to->code[i];
	    n++;
	  }
	}
      }
    }
    else if ((flag & INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR) != 0) {
      OnigCodePoint cs[3][4];
      int fn, ncs[3];

      for (fn = 0; fn < OnigCodePointCount(to->n); fn++) {
	cs[fn][0] = to->code[fn];
	if ((z3 = onigenc_unicode_unfold1_lookup(cs[fn][0])) != 0) {
	  for (i = 0; i < OnigCodePointCount(z3->n); i++) {
	    cs[fn][i+1] = z3->code[i];
	  }
	  ncs[fn] = OnigCodePointCount(z3->n) + 1;
	}
	else
	  ncs[fn] = 1;
      }

      if (fn == 2) {
	for (i = 0; i < ncs[0]; i++) {
	  for (j = 0; j < ncs[1]; j++) {
	    items[n].byte_len = len;
	    items[n].code_len = 2;
	    items[n].code[0]  = cs[0][i];
	    items[n].code[1]  = cs[1][j];
	    n++;
	  }
	}

	if ((z2 = onigenc_unicode_unfold2_lookup(to->code)) != 0 &&
	    CodePointListValidP(z2)) {
	  for (i = 0; i < OnigCodePointCount(z2->n); i++) {
	    if (z2->code[i] == code) continue;

	    items[n].byte_len = len;
	    items[n].code_len = 1;
	    items[n].code[0]  = z2->code[i];
	    n++;
	  }
	}
      }
      else {
	for (i = 0; i < ncs[0]; i++) {
	  for (j = 0; j < ncs[1]; j++) {
	    for (k = 0; k < ncs[2]; k++) {
	      items[n].byte_len = len;
	      items[n].code_len = 3;
	      items[n].code[0]  = cs[0][i];
	      items[n].code[1]  = cs[1][j];
	      items[n].code[2]  = cs[2][k];
	      n++;
	    }
	  }
	}

	if ((z2 = onigenc_unicode_unfold3_lookup(to->code)) != 0 &&
	    CodePointListValidP(z2)) {
	  for (i = 0; i < OnigCodePointCount(z2->n); i++) {
	    if (z2->code[i] == code) continue;

	    items[n].byte_len = len;
	    items[n].code_len = 1;
	    items[n].code[0]  = z2->code[i];
	    n++;
	  }
	}
      }

      /* multi char folded code is not head of another folded multi char */
      flag = 0; /* DISABLE_CASE_FOLD_MULTI_CHAR(flag); */
    }
  }
  else {
    if ((to = onigenc_unicode_unfold1_lookup(code)) != 0 &&
	CodePointListValidP(to)) {
      for (i = 0; i < OnigCodePointCount(to->n); i++) {
	items[n].byte_len = len;
	items[n].code_len = 1;
	items[n].code[0]  = to->code[i];
	n++;
      }
    }
  }


  if ((flag & INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR) != 0) {
    p += len;
    if (p < end) {
      int clen;

      codes[0] = code;
      code = ONIGENC_MBC_TO_CODE(enc, p, end);
      if ((to = onigenc_unicode_fold_lookup(code)) != 0
	  && OnigCodePointCount(to->n) == 1) {
	codes[1] = to->code[0];
      }
      else
	codes[1] = code;

      clen = enclen(enc, p, end);
      len += clen;
      if ((z2 = onigenc_unicode_unfold2_lookup(codes)) != 0 &&
	  CodePointListValidP(z2)) {
	for (i = 0; i < OnigCodePointCount(z2->n); i++) {
	  items[n].byte_len = len;
	  items[n].code_len = 1;
	  items[n].code[0]  = z2->code[i];
	  n++;
	}
      }

      p += clen;
      if (p < end) {
	code = ONIGENC_MBC_TO_CODE(enc, p, end);
	if ((to = onigenc_unicode_fold_lookup(code)) != 0
	    && OnigCodePointCount(to->n) == 1) {
	  codes[2] = to->code[0];
	}
	else
	  codes[2] = code;

	clen = enclen(enc, p, end);
	len += clen;
	if ((z2 = onigenc_unicode_unfold3_lookup(codes)) != 0 &&
	    CodePointListValidP(z2)) {
	  for (i = 0; i < OnigCodePointCount(z2->n); i++) {
	    items[n].byte_len = len;
	    items[n].code_len = 1;
	    items[n].code[0]  = z2->code[i];
	    n++;
	  }
	}
      }
    }
  }

  return n;
}

/* length in bytes for three characters in UTF-32; e.g. needed for ffi (U+FB03) */
#define CASE_MAPPING_SLACK 12
#define MODIFIED (flags |= ONIGENC_CASE_MODIFIED)
extern int
onigenc_unicode_case_map(OnigCaseFoldType* flagP,
    const OnigUChar** pp, const OnigUChar* end,
    OnigUChar* to, OnigUChar* to_end,
    const struct OnigEncodingTypeST* enc)
{
  OnigCodePoint code;
  OnigUChar *to_start = to;
  OnigCaseFoldType flags = *flagP;
  int codepoint_length;

  to_end -= CASE_MAPPING_SLACK;
  /* copy flags ONIGENC_CASE_UPCASE     and ONIGENC_CASE_DOWNCASE over to
   *            ONIGENC_CASE_UP_SPECIAL and ONIGENC_CASE_DOWN_SPECIAL */
  flags |= (flags & (ONIGENC_CASE_UPCASE | ONIGENC_CASE_DOWNCASE)) << ONIGENC_CASE_SPECIAL_OFFSET;

  while (*pp < end && to <= to_end) {
    codepoint_length = ONIGENC_PRECISE_MBC_ENC_LEN(enc, *pp, end);
    if (codepoint_length < 0)
      return codepoint_length; /* encoding invalid */
    code = ONIGENC_MBC_TO_CODE(enc, *pp, end);
    *pp += codepoint_length;

    if (code <= 'z') { /* ASCII comes first */
      if (code >= 'a' && code <= 'z') {
	if (flags & ONIGENC_CASE_UPCASE) {
	  MODIFIED;
	  if (flags & ONIGENC_CASE_FOLD_TURKISH_AZERI && code == 'i')
	    code = I_WITH_DOT_ABOVE;
          else {
            code -= 'a';
            code += 'A';
          }
	}
      }
      else if (code >= 'A' && code <= 'Z') {
	if (flags & (ONIGENC_CASE_DOWNCASE | ONIGENC_CASE_FOLD)) {
	  MODIFIED;
	  if (flags & ONIGENC_CASE_FOLD_TURKISH_AZERI && code == 'I')
	    code = DOTLESS_i;
	  else
	    code += 'a' - 'A';
	}
      }
    }
    else if (!(flags & ONIGENC_CASE_ASCII_ONLY) && code >= 0x00B5) { /* deal with non-ASCII; micron sign (U+00B5) is lowest affected */
      const CodePointList3 *folded;

      if (code == I_WITH_DOT_ABOVE) {
	if (flags & (ONIGENC_CASE_DOWNCASE | ONIGENC_CASE_FOLD)) {
	  MODIFIED;
	  code = 'i';
	  if (!(flags & ONIGENC_CASE_FOLD_TURKISH_AZERI)) { /* make dot above explicit */
	    to += ONIGENC_CODE_TO_MBC(enc, code, to);
	    code = DOT_ABOVE;
	  }
	}
      }
      else if (code == DOTLESS_i) { /* handle this manually, because it isn't involved in folding */
	if (flags & ONIGENC_CASE_UPCASE) {
	  MODIFIED;
	  code = 'I';
	}
      }
      else if ((folded = onigenc_unicode_fold_lookup(code)) != 0) { /* data about character found in CaseFold_11_Table */
	if ((flags & ONIGENC_CASE_TITLECASE) && code>=0x1C90 && code<=0x1CBF) { /* Georgian MTAVRULI */
          MODIFIED;
	  code += 0x10D0 - 0x1C90;
        }
        else if ((flags & ONIGENC_CASE_TITLECASE)                            /* Titlecase needed, */
	    && (OnigCaseFoldFlags(folded->n) & ONIGENC_CASE_IS_TITLECASE)) { /* but already Titlecase  */
	  /* already Titlecase, no changes needed */
	}
	else if (flags & OnigCaseFoldFlags(folded->n)) { /* needs and data availability match */
	  const OnigCodePoint *next;
	  int count;

	  MODIFIED;
	  if (flags & OnigCaseFoldFlags(folded->n) & ONIGENC_CASE_SPECIALS) { /* special */
	    const OnigCodePoint *SpecialsStart = CaseMappingSpecials + OnigSpecialIndexDecode(folded->n);

	    if (OnigCaseFoldFlags(folded->n) & ONIGENC_CASE_IS_TITLECASE) { /* swapCASE available */
	      if ((flags & (ONIGENC_CASE_UPCASE | ONIGENC_CASE_DOWNCASE))
		  == (ONIGENC_CASE_UPCASE | ONIGENC_CASE_DOWNCASE)) /* swapCASE needed */
		goto SpecialsCopy;
	      else /* swapCASE not needed */
		SpecialsStart += SpecialsLengthExtract(*SpecialsStart);
	    }
	    if (OnigCaseFoldFlags(folded->n) & ONIGENC_CASE_TITLECASE) { /* Titlecase available */
	      if (flags & ONIGENC_CASE_TITLECASE) /* Titlecase needed, but not yet Titlecase */
		goto SpecialsCopy;
	      else /* Titlecase not needed */
		SpecialsStart += SpecialsLengthExtract(*SpecialsStart);
	    }
	    if (OnigCaseFoldFlags(folded->n) & ONIGENC_CASE_DOWN_SPECIAL) {
	      if (!(flags & ONIGENC_CASE_DOWN_SPECIAL))
		SpecialsStart += SpecialsLengthExtract(*SpecialsStart);
	    }
	    /* here, we know we use ONIGENC_CASE_UP_SPECIAL, and the position is right */
SpecialsCopy:
	    count = SpecialsLengthExtract(*SpecialsStart);
	    next = SpecialsStart;
	    code = SpecialsCodepointExtract(*next++);
	  }
	  else { /* no specials */
	    count = OnigCodePointCount(folded->n);
	    next = folded->code;
	    code = *next++;
	  }
	  if (count == 1)
	    ;
	  else if (count == 2) {
	    to += ONIGENC_CODE_TO_MBC(enc, code, to);
	    code = *next;
	  }
	  else { /* count == 3 */
	    to += ONIGENC_CODE_TO_MBC(enc, code, to);
	    to += ONIGENC_CODE_TO_MBC(enc, *next++, to);
	    code = *next;
	  }
	}
      }
      else if ((folded = onigenc_unicode_unfold1_lookup(code)) != 0) { /* data about character found in CaseUnfold_11_Table */
	if ((flags & ONIGENC_CASE_TITLECASE)                                 /* Titlecase needed, */
	    && (OnigCaseFoldFlags(folded->n) & ONIGENC_CASE_IS_TITLECASE)) { /* but already Titlecase */
	  /* already Titlecase, no changes needed */
	}
	else if (flags & OnigCaseFoldFlags(folded->n)) { /* needs and data availability match */
	  MODIFIED;
	  code = folded->code[(flags & OnigCaseFoldFlags(folded->n) & ONIGENC_CASE_TITLECASE) ? 1 : 0];
	}
      }
    }
    to += ONIGENC_CODE_TO_MBC(enc, code, to);
    /* switch from titlecase to lowercase for capitalize */
    if (flags & ONIGENC_CASE_TITLECASE)
      flags ^= (ONIGENC_CASE_UPCASE | ONIGENC_CASE_DOWNCASE | ONIGENC_CASE_TITLECASE |
	  ONIGENC_CASE_UP_SPECIAL | ONIGENC_CASE_DOWN_SPECIAL);
  }
  *flagP = flags;
  return (int )(to - to_start);
}

const char onigenc_unicode_version_string[] =
#ifdef ONIG_UNICODE_VERSION_STRING
    ONIG_UNICODE_VERSION_STRING
#endif
    "";

const int onigenc_unicode_version_number[3] = {
#ifdef ONIG_UNICODE_VERSION_MAJOR
    ONIG_UNICODE_VERSION_MAJOR,
    ONIG_UNICODE_VERSION_MINOR,
    ONIG_UNICODE_VERSION_TEENY,
#else
    0
#endif
};
