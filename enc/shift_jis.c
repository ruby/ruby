/**********************************************************************
  shift_jis.c -  Onigmo (Oniguruma-mod) (regular expression library)
**********************************************************************/
/*-
 * Copyright (c) 2002-2009  K.Kosako  <sndgk393 AT ybb DOT ne DOT jp>
 * Copyright (c) 2011-2017  K.Takata  <kentkt AT csc DOT jp>
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

#include "shift_jis.h"

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
  apply_all_case_fold,
  get_case_fold_codes_by_str,
  property_name_to_ctype,
  is_code_ctype,
  get_ctype_code_range,
  left_adjust_char_head,
  is_allowed_reverse_match,
  onigenc_ascii_only_case_map,
  0,
  ONIGENC_FLAG_NONE,
};
/*
 * Name: Shift_JIS
 * MIBenum: 17
 * Link: http://www.iana.org/assignments/character-sets
 * Link: http://ja.wikipedia.org/wiki/Shift_JIS
 */

/*
 * Name: MacJapanese
 * Link: http://unicode.org/Public/MAPPINGS/VENDORS/APPLE/JAPANESE.TXT
 * Link: http://ja.wikipedia.org/wiki/MacJapanese
 */
ENC_REPLICATE("MacJapanese", "Shift_JIS")
ENC_ALIAS("MacJapan", "MacJapanese")
