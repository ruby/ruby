/**********************************************************************
  reggnu.c -  Oniguruma (regular expression library)
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

#include "regint.h"

#ifndef ONIGGNU_H     /* name changes from oniggnu.h to regex.h in ruby. */
#include "oniggnu.h"
#endif

#if defined(RUBY_PLATFORM) || defined(RUBY)
#ifndef ONIG_RUBY_M17N
#define USE_COMPATIBILITY_FOR_RUBY_EXTENSION_LIBRARY
#endif
#endif

extern void
re_free_registers(OnigRegion* r)
{
  /* 0: don't free self */
  onig_region_free(r, 0);
}

extern int
re_adjust_startpos(regex_t* reg, const char* string, int size,
		   int startpos, int range)
{
  if (startpos > 0 && ONIGENC_MBC_MAXLEN(reg->enc) != 1 && startpos < size) {
    UChar *p;
    UChar *s = (UChar* )string + startpos;

    if (range > 0) {
      p = onigenc_get_right_adjust_char_head(reg->enc, (UChar* )string, s);
    }
    else {
      p = ONIGENC_LEFT_ADJUST_CHAR_HEAD(reg->enc, (UChar* )string, s);
    }
    return p - (UChar* )string;
  }

  return startpos;
}

extern int
re_match(regex_t* reg, const char* str, int size, int pos,
	 struct re_registers* regs)
{
  return onig_match(reg, (UChar* )str, (UChar* )(str + size),
		    (UChar* )(str + pos), regs, ONIG_OPTION_NONE);
}

extern int
re_search(regex_t* bufp, const char* string, int size, int startpos, int range,
	  struct re_registers* regs)
{
  return onig_search(bufp, (UChar* )string, (UChar* )(string + size),
		     (UChar* )(string + startpos),
		     (UChar* )(string + startpos + range),
		     regs, ONIG_OPTION_NONE);
}

extern int
re_compile_pattern(const char* pattern, int size, regex_t* reg, char* ebuf)
{
  int r;
  OnigErrorInfo einfo;

  r = onig_compile(reg, (UChar* )pattern, (UChar* )(pattern + size), &einfo);
  if (r != 0) {
    if (IS_NOT_NULL(ebuf))
      (void )onig_error_code_to_str((UChar* )ebuf, r, &einfo);
  }

  return r;
}

extern int
re_recompile_pattern(const char* pattern, int size, regex_t* reg, char* ebuf)
{
  int r;
  OnigErrorInfo einfo;
  OnigEncoding enc;

  /* I think encoding and options should be arguments of this function.
     But this is adapted to present re.c. (2002/11/29)
   */
  enc = OnigEncDefaultCharEncoding;

  r = onig_recompile(reg, (UChar* )pattern, (UChar* )(pattern + size),
		     reg->options, enc, OnigDefaultSyntax, &einfo);
  if (r != 0) {
    if (IS_NOT_NULL(ebuf))
      (void )onig_error_code_to_str((UChar* )ebuf, r, &einfo);
  }
  return r;
}

extern void
re_free_pattern(regex_t* reg)
{
  onig_free(reg);
}

extern int
re_alloc_pattern(regex_t** reg)
{
  return onig_alloc_init(reg, ONIG_OPTION_DEFAULT,
                         ONIGENC_AMBIGUOUS_MATCH_DEFAULT,
                         OnigEncDefaultCharEncoding,
			 OnigDefaultSyntax);
}

extern void
re_set_casetable(const char* table)
{
  onigenc_set_default_caseconv_table((UChar* )table);
}

#ifdef USE_COMPATIBILITY_FOR_RUBY_EXTENSION_LIBRARY
static const unsigned char mbctab_ascii[] = {
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
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

static const unsigned char mbctab_euc[] = {
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
};

static const unsigned char mbctab_sjis[] = {
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0
};

static const unsigned char mbctab_utf8[] = {
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
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 0, 0,
};

const unsigned char *re_mbctab = mbctab_ascii;
#endif

extern void
#ifdef ONIG_RUBY_M17N
re_mbcinit(OnigEncoding enc)
#else
re_mbcinit(int mb_code)
#endif
{
#ifdef ONIG_RUBY_M17N

  onigenc_set_default_encoding(enc);

#else

  OnigEncoding enc;

  switch (mb_code) {
  case MBCTYPE_ASCII:
    enc = ONIG_ENCODING_ASCII;
    break;
  case MBCTYPE_EUC:
    enc = ONIG_ENCODING_EUC_JP;
    break;
  case MBCTYPE_SJIS:
    enc = ONIG_ENCODING_SJIS;
    break;
  case MBCTYPE_UTF8:
    enc = ONIG_ENCODING_UTF8;
    break;
  default:
    return ;
    break;
  }

  onigenc_set_default_encoding(enc);
#endif

#ifdef USE_COMPATIBILITY_FOR_RUBY_EXTENSION_LIBRARY
  switch (mb_code) {
  case MBCTYPE_ASCII:
    re_mbctab = mbctab_ascii;
    break;
  case MBCTYPE_EUC:
    re_mbctab = mbctab_euc;
    break;
  case MBCTYPE_SJIS:
    re_mbctab = mbctab_sjis;
    break;
  case MBCTYPE_UTF8:
    re_mbctab = mbctab_utf8;
    break;
  }
#endif
}
