/**********************************************************************

  encoding.h -

  $Author: matz $
  $Date: 2007-05-24 11:49:41 +0900 (Thu, 24 May 2007) $
  created at: Thu May 24 11:49:41 JST 2007

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_ENCODING_H
#define RUBY_ENCODING_H 1

#ifdef HAVE_STDARG_PROTOTYPES
# include <stdarg.h>
#else
# include <varargs.h>
#endif
#include "ruby/oniguruma.h"

#define ENCODING_INLINE_MAX 1023
#define ENCODING_SHIFT (FL_USHIFT+10)
#define ENCODING_MASK (ENCODING_INLINE_MAX<<ENCODING_SHIFT)
#define ENCODING_SET(obj,i) do {\
    RBASIC(obj)->flags &= ~ENCODING_MASK;\
    RBASIC(obj)->flags |= i << ENCODING_SHIFT;\
} while (0)
#define ENCODING_GET(obj) ((RBASIC(obj)->flags & ENCODING_MASK)>>ENCODING_SHIFT)

#define ENC_CODERANGE_MASK	(FL_USER8|FL_USER9)
#define ENC_CODERANGE_UNKNOWN	0
#define ENC_CODERANGE_7BIT	FL_USER8
#define ENC_CODERANGE_VALID	FL_USER9
#define ENC_CODERANGE_BROKEN	(FL_USER8|FL_USER9)
#define ENC_CODERANGE(obj) (RBASIC(obj)->flags & ENC_CODERANGE_MASK)
#define ENC_CODERANGE_ASCIIONLY(obj) (ENC_CODERANGE(obj) == ENC_CODERANGE_7BIT)
#define ENC_CODERANGE_SET(obj,cr) (RBASIC(obj)->flags = \
				   (RBASIC(obj)->flags & ~ENC_CODERANGE_MASK) | (cr))
#define ENC_CODERANGE_CLEAR(obj) ENC_CODERANGE_SET(obj,0)


typedef OnigEncodingType rb_encoding;

int rb_enc_replicate(const char *, rb_encoding *);
int rb_define_dummy_encoding(const char *);
int rb_enc_dummy_p(rb_encoding *);
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
void rb_enc_copy(VALUE dst, VALUE src);

VALUE rb_enc_str_new(const char*, long len, rb_encoding*);
PRINTF_ARGS(VALUE rb_enc_sprintf(rb_encoding *, const char*, ...), 2, 3);
VALUE rb_enc_vsprintf(rb_encoding *, const char*, va_list);
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

/* -> mbclen (no error notification: 0 < ret <= e-p, no exception) */
int rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc);

/* -> chlen, invalid or needmore */
int rb_enc_precise_mbclen(const char *p, const char *e, rb_encoding *enc);
#define MBCLEN_CHARFOUND(ret)     ONIGENC_MBCLEN_CHARFOUND(ret)
#define MBCLEN_INVALID(ret)       ONIGENC_MBCLEN_INVALID(ret)
#define MBCLEN_NEEDMORE(ret)      ONIGENC_MBCLEN_NEEDMORE(ret)

/* -> 0x00..0x7f, -1 */
int rb_enc_ascget(const char *p, const char *e, int *len, rb_encoding *enc);

/* -> code or raise exception */
int rb_enc_codepoint(const char *p, const char *e, rb_encoding *enc);
#define rb_enc_mbc_to_codepoint(p, e, enc) ONIGENC_MBC_TO_CODE(enc,(UChar*)(p),(UChar*)(e))

/* -> codelen>0 or raise exception */
int rb_enc_codelen(int code, rb_encoding *enc);

/* code,ptr,encoding -> write buf */
#define rb_enc_mbcput(c,buf,enc) ONIGENC_CODE_TO_MBC(enc,c,(UChar*)(buf))

/* ptr, ptr, encoding -> prev_char */
#define rb_enc_prev_char(s,p,enc) (char *)onigenc_get_prev_char_head(enc,(UChar*)(s),(UChar*)(p))
/* ptr, ptr, encoding -> next_char */
#define rb_enc_left_char_head(s,p,enc) (char *)onigenc_get_left_adjust_char_head(enc,(UChar*)(s),(UChar*)(p))
#define rb_enc_right_char_head(s,p,enc) (char *)onigenc_get_right_adjust_char_head(enc,(UChar*)(s),(UChar*)(p))

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

int rb_enc_casefold(char *to, const char *p, const char *e, rb_encoding *enc);
int rb_enc_toupper(int c, rb_encoding *enc);
int rb_enc_tolower(int c, rb_encoding *enc);
ID rb_intern3(const char*, long, rb_encoding*);
ID rb_interned_id_p(const char *, long, rb_encoding *);
int rb_enc_symname_p(const char*, rb_encoding*);
int rb_enc_str_coderange(VALUE);
int rb_enc_str_asciionly_p(VALUE);
#define rb_enc_str_asciicompat_p(str) rb_enc_asciicompat(rb_enc_get(str))
VALUE rb_enc_from_encoding(rb_encoding *enc);
rb_encoding *rb_ascii8bit_encoding(void);
rb_encoding *rb_utf8_encoding(void);
rb_encoding *rb_locale_encoding(void);
rb_encoding *rb_default_external_encoding(void);
VALUE rb_enc_default_external(void);
void rb_enc_set_default_external(VALUE encoding);
VALUE rb_locale_charmap(VALUE klass);

#define rb_isascii(c) ONIGENC_IS_CODE_ASCII(c)
#define rb_isalnum(c) ONIGENC_IS_CODE_ALNUM(ONIG_ENCODING_ASCII, c)
#define rb_isalpha(c) ONIGENC_IS_CODE_ALPHA(ONIG_ENCODING_ASCII, c)
#define rb_isblank(c) ONIGENC_IS_CODE_BLANK(ONIG_ENCODING_ASCII, c)
#define rb_iscntrl(c) ONIGENC_IS_CODE_CNTRL(ONIG_ENCODING_ASCII, c)
#define rb_isdigit(c) ONIGENC_IS_CODE_DIGIT(ONIG_ENCODING_ASCII, c)
#define rb_isgraph(c) ONIGENC_IS_CODE_GRAPH(ONIG_ENCODING_ASCII, c)
#define rb_islower(c) ONIGENC_IS_CODE_LOWER(ONIG_ENCODING_ASCII, c)
#define rb_isprint(c) ONIGENC_IS_CODE_PRINT(ONIG_ENCODING_ASCII, c)
#define rb_ispunct(c) ONIGENC_IS_CODE_PUNCT(ONIG_ENCODING_ASCII, c)
#define rb_isspace(c) ONIGENC_IS_CODE_SPACE(ONIG_ENCODING_ASCII, c)
#define rb_isupper(c) ONIGENC_IS_CODE_UPPER(ONIG_ENCODING_ASCII, c)
#define rb_isxdigit(c) ONIGENC_IS_CODE_XDIGIT(ONIG_ENCODING_ASCII, c)
#define rb_tolower(c) rb_enc_tolower(c, ONIG_ENCODING_ASCII)
#define rb_toupper(c) rb_enc_toupper(c, ONIG_ENCODING_ASCII)

#endif /* RUBY_ENCODING_H */
