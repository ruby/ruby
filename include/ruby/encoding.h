/**********************************************************************

  encoding.h -

  $Author: matz $
  created at: Thu May 24 11:49:41 JST 2007

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_ENCODING_H
#define RUBY_ENCODING_H 1

#include <stdarg.h>
#include "ruby/oniguruma.h"

#define ENCODING_INLINE_MAX 1023
#define ENCODING_SHIFT (FL_USHIFT+10)
#define ENCODING_MASK (ENCODING_INLINE_MAX<<ENCODING_SHIFT)

#define ENCODING_SET_INLINED(obj,i) do {\
    RBASIC(obj)->flags &= ~ENCODING_MASK;\
    RBASIC(obj)->flags |= (i) << ENCODING_SHIFT;\
} while (0)
#define ENCODING_SET(obj,i) do {\
    VALUE rb_encoding_set_obj = (obj); \
    int encoding_set_enc_index = (i); \
    if (encoding_set_enc_index < ENCODING_INLINE_MAX) \
        ENCODING_SET_INLINED(rb_encoding_set_obj, encoding_set_enc_index); \
    else \
        rb_enc_set_index(rb_encoding_set_obj, encoding_set_enc_index); \
} while (0)

#define ENCODING_GET_INLINED(obj) ((RBASIC(obj)->flags & ENCODING_MASK)>>ENCODING_SHIFT)
#define ENCODING_GET(obj) \
    (ENCODING_GET_INLINED(obj) != ENCODING_INLINE_MAX ? \
     ENCODING_GET_INLINED(obj) : \
     rb_enc_get_index(obj))

#define ENCODING_IS_ASCII8BIT(obj) (ENCODING_GET_INLINED(obj) == 0)

#define ENCODING_MAXNAMELEN 42

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

/* assumed ASCII compatiblity */
#define ENC_CODERANGE_AND(a, b) \
    (a == ENC_CODERANGE_7BIT ? b : \
     a == ENC_CODERANGE_VALID ? (b == ENC_CODERANGE_7BIT ? ENC_CODERANGE_VALID : b) : \
     ENC_CODERANGE_UNKNOWN)

#define ENCODING_CODERANGE_SET(obj, encindex, cr) \
    do { \
        VALUE rb_encoding_coderange_obj = (obj); \
        ENCODING_SET(rb_encoding_coderange_obj, (encindex)); \
        ENC_CODERANGE_SET(rb_encoding_coderange_obj, (cr)); \
    } while (0)

typedef OnigEncodingType rb_encoding;

int rb_enc_replicate(const char *, rb_encoding *);
int rb_define_dummy_encoding(const char *);
#define rb_enc_to_index(enc) ((enc) ? ENC_TO_ENCINDEX(enc) : 0)
int rb_enc_get_index(VALUE obj);
void rb_enc_set_index(VALUE obj, int encindex);
int rb_enc_find_index(const char *name);
int rb_to_encoding_index(VALUE);
rb_encoding* rb_to_encoding(VALUE);
rb_encoding* rb_enc_get(VALUE);
rb_encoding* rb_enc_compatible(VALUE,VALUE);
rb_encoding* rb_enc_check(VALUE,VALUE);
VALUE rb_enc_associate_index(VALUE, int);
VALUE rb_enc_associate(VALUE, rb_encoding*);
void rb_enc_copy(VALUE dst, VALUE src);

VALUE rb_enc_str_new(const char*, long, rb_encoding*);
VALUE rb_enc_reg_new(const char*, long, rb_encoding*, int);
PRINTF_ARGS(VALUE rb_enc_sprintf(rb_encoding *, const char*, ...), 2, 3);
VALUE rb_enc_vsprintf(rb_encoding *, const char*, va_list);
long rb_enc_strlen(const char*, const char*, rb_encoding*);
char* rb_enc_nth(const char*, const char*, int, rb_encoding*);
VALUE rb_obj_encoding(VALUE);
VALUE rb_enc_str_buf_cat(VALUE str, const char *ptr, long len, rb_encoding *enc);

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
#define MBCLEN_CHARFOUND_P(ret)     ONIGENC_MBCLEN_CHARFOUND_P(ret)
#define MBCLEN_CHARFOUND_LEN(ret)     ONIGENC_MBCLEN_CHARFOUND_LEN(ret)
#define MBCLEN_INVALID_P(ret)       ONIGENC_MBCLEN_INVALID_P(ret)
#define MBCLEN_NEEDMORE_P(ret)      ONIGENC_MBCLEN_NEEDMORE_P(ret)
#define MBCLEN_NEEDMORE_LEN(ret)      ONIGENC_MBCLEN_NEEDMORE_LEN(ret)

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

/* ptr, ptr, encoding -> newline_or_not */
#define rb_enc_is_newline(p,end,enc)  ONIGENC_IS_MBC_NEWLINE(enc,(UChar*)(p),(UChar*)(end))

#define rb_enc_isctype(c,t,enc) ONIGENC_IS_CODE_CTYPE(enc,c,t)
#define rb_enc_isascii(c,enc) ONIGENC_IS_CODE_ASCII(c)
#define rb_enc_isalpha(c,enc) ONIGENC_IS_CODE_ALPHA(enc,c)
#define rb_enc_islower(c,enc) ONIGENC_IS_CODE_LOWER(enc,c)
#define rb_enc_isupper(c,enc) ONIGENC_IS_CODE_UPPER(enc,c)
#define rb_enc_ispunct(c,enc) ONIGENC_IS_CODE_PUNCT(enc,c)
#define rb_enc_isalnum(c,enc) ONIGENC_IS_CODE_ALNUM(enc,c)
#define rb_enc_isprint(c,enc) ONIGENC_IS_CODE_PRINT(enc,c)
#define rb_enc_isspace(c,enc) ONIGENC_IS_CODE_SPACE(enc,c)
#define rb_enc_isdigit(c,enc) ONIGENC_IS_CODE_DIGIT(enc,c)

#define rb_enc_asciicompat(enc) (rb_enc_mbminlen(enc)==1 && !rb_enc_dummy_p(enc))

int rb_enc_casefold(char *to, const char *p, const char *e, rb_encoding *enc);
int rb_enc_toupper(int c, rb_encoding *enc);
int rb_enc_tolower(int c, rb_encoding *enc);
ID rb_intern3(const char*, long, rb_encoding*);
ID rb_interned_id_p(const char *, long, rb_encoding *);
int rb_enc_symname_p(const char*, rb_encoding*);
int rb_enc_str_coderange(VALUE);
long rb_str_coderange_scan_restartable(const char*, const char*, rb_encoding*, int*);
int rb_enc_str_asciionly_p(VALUE);
#define rb_enc_str_asciicompat_p(str) rb_enc_asciicompat(rb_enc_get(str))
VALUE rb_enc_from_encoding(rb_encoding *enc);
rb_encoding *rb_ascii8bit_encoding(void);
rb_encoding *rb_utf8_encoding(void);
rb_encoding *rb_usascii_encoding(void);
rb_encoding *rb_locale_encoding(void);
rb_encoding *rb_filesystem_encoding(void);
rb_encoding *rb_default_external_encoding(void);
int rb_ascii8bit_encindex(void);
int rb_utf8_encindex(void);
int rb_usascii_encindex(void);
VALUE rb_enc_default_external(void);
void rb_enc_set_default_external(VALUE encoding);
VALUE rb_locale_charmap(VALUE klass);
long rb_memsearch(const void*,long,const void*,long,rb_encoding*);

RUBY_EXTERN VALUE rb_cEncoding;
#define enc_initialized_p(enc) ((enc)->ruby_encoding_index != ENC_UNINITIALIZED)
#define ENC_DUMMY_FLAG (1<<24)
#define ENC_INDEX_MASK (~(~0U<<24))

#define ENC_TO_ENCINDEX(enc)   ((enc)->ruby_encoding_index & ENC_INDEX_MASK)
#define ENC_FROM_ENCINDEX(idx) (RARRAY_PTR(rb_encoding_list)[idx])
#define ENC_FROM_ENCODING(enc) ENC_FROM_ENCINDEX(ENC_TO_ENCINDEX(enc))

#define ENC_DUMMY_P(enc) ((enc)->ruby_encoding_index & ENC_DUMMY_FLAG)
#define ENC_SET_DUMMY(enc) ((enc)->ruby_encoding_index |= ENC_DUMMY_FLAG)

static inline int
rb_enc_dummy_p(rb_encoding *enc)
{
    return ENC_DUMMY_P(enc) != 0;
}

VALUE rb_str_transcode(VALUE str, VALUE to);

/* econv stuff */

typedef enum {
    econv_invalid_byte_sequence,
    econv_undefined_conversion,
    econv_destination_buffer_full,
    econv_source_buffer_empty,
    econv_finished,
    econv_output_followed_by_input,
} rb_econv_result_t;

typedef struct {
    struct rb_transcoding *tc;
    unsigned char *out_buf_start;
    unsigned char *out_data_start;
    unsigned char *out_data_end;
    unsigned char *out_buf_end;
    rb_econv_result_t last_result;
} rb_econv_elem_t;

typedef struct {
    int flags;
    const char *source_encoding_name;
    const char *destination_encoding_name;

    unsigned char *in_buf_start;
    unsigned char *in_data_start;
    unsigned char *in_data_end;
    unsigned char *in_buf_end;
    rb_econv_elem_t *elems;
    int num_trans;
    int num_finished;
    int last_trans_index; /* last trans, not including universal newline */
    struct rb_transcoding *last_tc;

    /* last error */
    struct {
        rb_econv_result_t result;
        struct rb_transcoding *error_tc;
        const char *source_encoding;
        const char *destination_encoding;
        const unsigned char *error_bytes_start;
        size_t error_bytes_len;
        size_t readagain_len;
        int partial_input;
    } last_error;

    /* The following fields are only for Encoding::Converter.
     * rb_econv_open set them NULL. */
    rb_encoding *source_encoding;
    rb_encoding *destination_encoding;
} rb_econv_t;

rb_econv_t *rb_econv_open(const char *source_encoding, const char *destination_encoding, int flags);
rb_econv_result_t rb_econv_convert(rb_econv_t *ec,
    const unsigned char **source_buffer_ptr, const unsigned char *source_buffer_end,
    unsigned char **destination_buffer_ptr, unsigned char *destination_buffer_end,
    int flags);
void rb_econv_close(rb_econv_t *ec);

/* result: 0:success -1:failure */
int rb_econv_insert_output(rb_econv_t *ec,
    const unsigned char *str, size_t len, const char *str_encoding);

/* encoding that rb_econv_insert_output doesn't need conversion */
const char *rb_econv_encoding_to_insert_output(rb_econv_t *ec);

/* raise an error if the last rb_econv_convert is error */
void rb_econv_check_error(rb_econv_t *ec);

int rb_econv_putbackable(rb_econv_t *ec);
void rb_econv_putback(rb_econv_t *ec, unsigned char *p, int n);

/* returns corresponding stateless encoding, or NULL if not stateful. */
const char *rb_econv_stateless_encoding(const char *stateful_enc);

VALUE rb_econv_string(rb_econv_t *ec, VALUE src, long off, long len, VALUE dst, int flags);

void rb_econv_binmode(rb_econv_t *ec);

/* flags for rb_econv_open */
#define ECONV_INVALID_MASK                      0x000f
#define ECONV_INVALID_IGNORE                    0x0001
#define ECONV_INVALID_REPLACE                   0x0002

#define ECONV_UNDEF_MASK                        0x00f0
#define ECONV_UNDEF_IGNORE                      0x0010
#define ECONV_UNDEF_REPLACE                     0x0020

#define ECONV_UNIVERSAL_NEWLINE_DECODER         0x0100
#define ECONV_CRLF_NEWLINE_ENCODER              0x0200
#define ECONV_CR_NEWLINE_ENCODER                0x0400

/* flags for rb_econv_convert */
#define ECONV_PARTIAL_INPUT                   0x10000
#define ECONV_OUTPUT_FOLLOWED_BY_INPUT        0x20000

#endif /* RUBY_ENCODING_H */
