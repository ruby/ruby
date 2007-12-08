/**********************************************************************

  encoding.h -

  $Author: matz $
  $Date: 2007-05-24 11:49:41 +0900 (Thu, 24 May 2007) $
  created at: Thu May 24 11:49:41 JST 2007

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_ENCODING_H
#define RUBY_ENCODING_H 1

#include "ruby/oniguruma.h"

#define ENCODING_INLINE_MAX 15
#define ENCODING_MASK (FL_USER8|FL_USER9|FL_USER10|FL_USER11)
#define ENCODING_SHIFT (FL_USHIFT+8)
#define ENCODING_SET(obj,i) do {\
    RBASIC(obj)->flags &= ~ENCODING_MASK;\
    RBASIC(obj)->flags |= i << ENCODING_SHIFT;\
} while (0)
#define ENCODING_GET(obj) ((RBASIC(obj)->flags & ENCODING_MASK)>>ENCODING_SHIFT)

#define ENC_CODERANGE_MASK	(FL_USER12|FL_USER13)
#define ENC_CODERANGE_UNKNOWN	0
#define ENC_CODERANGE_7BIT	FL_USER12
#define ENC_CODERANGE_8BIT	FL_USER13
#define ENC_CODERANGE_BROKEN	(FL_USER12|FL_USER13)
#define ENC_CODERANGE(obj) (RBASIC(obj)->flags & ENC_CODERANGE_MASK)
#define ENC_CODERANGE_ASCIIONLY(obj) (ENC_CODERANGE(obj) == ENC_CODERANGE_7BIT)
#define ENC_CODERANGE_SET(obj,cr) (RBASIC(obj)->flags = \
				   (RBASIC(obj)->flags & ~ENC_CODERANGE_MASK) | (cr))
#define ENC_CODERANGE_CLEAR(obj) ENC_CODERANGE_SET(obj,0)


typedef OnigEncodingType rb_encoding;

int rb_enc_to_index(rb_encoding*);
int rb_enc_get_index(VALUE obj);
int rb_enc_find_index(const char *name);
int rb_to_encoding_index(VALUE);
rb_encoding* rb_to_encoding(VALUE);
rb_encoding* rb_enc_get(VALUE);
rb_encoding* rb_enc_compatible(VALUE,VALUE);
rb_encoding* rb_enc_check(VALUE,VALUE);
void rb_enc_associate_index(VALUE, int);
void rb_enc_associate(VALUE, rb_encoding*);
void rb_enc_copy(VALUE, VALUE);

VALUE rb_enc_str_new(const char*, long len, rb_encoding*);
long rb_enc_strlen(const char*, const char*, rb_encoding*);
char* rb_enc_nth(const char*, const char*, int, rb_encoding*);
VALUE rb_obj_encoding(VALUE);

/* index -> rb_encoding */
rb_encoding* rb_enc_from_index(int idx);

/* name -> rb_encoding */
rb_encoding * rb_enc_find(const char *name);

/* encoding -> name */
#define rb_enc_name(enc) (enc)->name

/* encoding -> minlen/maxlen */
#define rb_enc_mbminlen(enc) (enc)->min_enc_len
#define rb_enc_mbmaxlen(enc) (enc)->max_enc_len

/* ptr,endptr,encoding -> mbclen */
int rb_enc_mbclen(const char*, const char *, rb_encoding*);

/* ptr,endptr,encoding -> chlen, invalid or needmore */
int rb_enc_precise_mbclen(const char*, const char *, rb_encoding*);
#define MBCLEN_CHARFOUND(ret)     ONIGENC_MBCLEN_CHARFOUND(ret)
#define MBCLEN_INVALID(ret)       ONIGENC_MBCLEN_INVALID(ret)
#define MBCLEN_NEEDMORE(ret)      ONIGENC_MBCLEN_NEEDMORE(ret)

/* ptr,endptr,encoding -> 0x00..0x7f, -1 */
int rb_enc_get_ascii(const char*, const char *, rb_encoding*);

/* code,encoding -> codelen */
int rb_enc_codelen(int, rb_encoding*);

/* code,ptr,encoding -> write buf */
#define rb_enc_mbcput(c,buf,enc) ONIGENC_CODE_TO_MBC(enc,c,(UChar*)buf)

/* ptr,ptr,encoding -> codepoint */
#define rb_enc_codepoint(p,e,enc) ONIGENC_MBC_TO_CODE(enc,(UChar*)p,(UChar*)e) 

/* ptr, ptr, encoding -> prev_char */
#define rb_enc_prev_char(s,p,enc) (char *)onigenc_get_prev_char_head(enc,(UChar*)s,(UChar*)p)

#define rb_enc_isctype(c,t,enc) ONIGENC_IS_CODE_CTYPE(enc,c,t)
#define rb_enc_isascii(c,enc) ONIGENC_IS_CODE_ASCII(c)
#define rb_enc_isalpha(c,enc) ONIGENC_IS_CODE_ALPHA(enc,c)
#define rb_enc_islower(c,enc) ONIGENC_IS_CODE_LOWER(enc,c)
#define rb_enc_isupper(c,enc) ONIGENC_IS_CODE_UPPER(enc,c)
#define rb_enc_isalnum(c,enc) ONIGENC_IS_CODE_ALNUM(enc,c)
#define rb_enc_isprint(c,enc) ONIGENC_IS_CODE_PRINT(enc,c)
#define rb_enc_isspace(c,enc) ONIGENC_IS_CODE_SPACE(enc,c)
#define rb_enc_isdigit(c,enc) ONIGENC_IS_CODE_DIGIT(enc,c)

#define rb_enc_asciicompat(enc) (rb_enc_mbminlen(enc)==1)

int rb_enc_toupper(int c, rb_encoding *enc);
int rb_enc_tolower(int c, rb_encoding *enc);
ID rb_intern3(const char*, long, rb_encoding*);
int rb_enc_symname_p(const char*, rb_encoding*);
int rb_enc_str_coderange(VALUE);
int rb_enc_str_asciionly_p(VALUE);
#define rb_enc_str_asciicompat_p(str) rb_enc_asciicompat(rb_enc_get(str))
VALUE rb_enc_from_encoding(rb_encoding *enc);
rb_encoding *rb_default_encoding(void);
rb_encoding *rb_default_external_encoding(void);
VALUE rb_enc_default_external(void);
void rb_enc_set_default_external(VALUE encoding);

#endif /* RUBY_ENCODING_H */
