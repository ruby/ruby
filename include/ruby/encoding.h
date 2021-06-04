#ifndef RUBY_ENCODING_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_ENCODING_H 1
/**
 * @file
 * @author     $Author: matz $
 * @date       Thu May 24 11:49:41 JST 2007
 * @copyright  Copyright (C) 2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/config.h"
#include <stdarg.h>
#include "ruby/ruby.h"
#include "ruby/oniguruma.h"
#include "ruby/internal/dllexport.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

enum ruby_encoding_consts {
    RUBY_ENCODING_INLINE_MAX = 127,
    RUBY_ENCODING_SHIFT = (RUBY_FL_USHIFT+10),
    RUBY_ENCODING_MASK = (RUBY_ENCODING_INLINE_MAX<<RUBY_ENCODING_SHIFT
			  /* RUBY_FL_USER10..RUBY_FL_USER16 */),
    RUBY_ENCODING_MAXNAMELEN = 42
};

#define ENCODING_INLINE_MAX RUBY_ENCODING_INLINE_MAX
#define ENCODING_SHIFT RUBY_ENCODING_SHIFT
#define ENCODING_MASK RUBY_ENCODING_MASK

#define RB_ENCODING_SET_INLINED(obj,i) do {\
    RBASIC(obj)->flags &= ~RUBY_ENCODING_MASK;\
    RBASIC(obj)->flags |= (VALUE)(i) << RUBY_ENCODING_SHIFT;\
} while (0)
#define RB_ENCODING_SET(obj,i) rb_enc_set_index((obj), (i))

#define RB_ENCODING_GET_INLINED(obj) \
    (int)((RBASIC(obj)->flags & RUBY_ENCODING_MASK)>>RUBY_ENCODING_SHIFT)
#define RB_ENCODING_GET(obj) \
    (RB_ENCODING_GET_INLINED(obj) != RUBY_ENCODING_INLINE_MAX ? \
     RB_ENCODING_GET_INLINED(obj) : \
     rb_enc_get_index(obj))

#define RB_ENCODING_IS_ASCII8BIT(obj) (RB_ENCODING_GET_INLINED(obj) == 0)

#define ENCODING_SET_INLINED(obj,i) RB_ENCODING_SET_INLINED(obj,i)
#define ENCODING_SET(obj,i) RB_ENCODING_SET(obj,i)
#define ENCODING_GET_INLINED(obj) RB_ENCODING_GET_INLINED(obj)
#define ENCODING_GET(obj) RB_ENCODING_GET(obj)
#define ENCODING_IS_ASCII8BIT(obj) RB_ENCODING_IS_ASCII8BIT(obj)
#define ENCODING_MAXNAMELEN RUBY_ENCODING_MAXNAMELEN

enum ruby_coderange_type {
    RUBY_ENC_CODERANGE_UNKNOWN	= 0,
    RUBY_ENC_CODERANGE_7BIT	= ((int)RUBY_FL_USER8),
    RUBY_ENC_CODERANGE_VALID	= ((int)RUBY_FL_USER9),
    RUBY_ENC_CODERANGE_BROKEN	= ((int)(RUBY_FL_USER8|RUBY_FL_USER9)),
    RUBY_ENC_CODERANGE_MASK	= (RUBY_ENC_CODERANGE_7BIT|
				   RUBY_ENC_CODERANGE_VALID|
				   RUBY_ENC_CODERANGE_BROKEN)
};

static inline int
rb_enc_coderange_clean_p(int cr)
{
    return (cr ^ (cr >> 1)) & RUBY_ENC_CODERANGE_7BIT;
}
#define RB_ENC_CODERANGE_CLEAN_P(cr) rb_enc_coderange_clean_p(cr)
#define RB_ENC_CODERANGE(obj) ((int)RBASIC(obj)->flags & RUBY_ENC_CODERANGE_MASK)
#define RB_ENC_CODERANGE_ASCIIONLY(obj) (RB_ENC_CODERANGE(obj) == RUBY_ENC_CODERANGE_7BIT)
#define RB_ENC_CODERANGE_SET(obj,cr) (\
	RBASIC(obj)->flags = \
	(RBASIC(obj)->flags & ~RUBY_ENC_CODERANGE_MASK) | (cr))
#define RB_ENC_CODERANGE_CLEAR(obj) RB_ENC_CODERANGE_SET((obj),0)

/* assumed ASCII compatibility */
#define RB_ENC_CODERANGE_AND(a, b) \
    ((a) == RUBY_ENC_CODERANGE_7BIT ? (b) : \
     (a) != RUBY_ENC_CODERANGE_VALID ? RUBY_ENC_CODERANGE_UNKNOWN : \
     (b) == RUBY_ENC_CODERANGE_7BIT ? RUBY_ENC_CODERANGE_VALID : (b))

#define RB_ENCODING_CODERANGE_SET(obj, encindex, cr) \
    do { \
        VALUE rb_encoding_coderange_obj = (obj); \
        RB_ENCODING_SET(rb_encoding_coderange_obj, (encindex)); \
        RB_ENC_CODERANGE_SET(rb_encoding_coderange_obj, (cr)); \
    } while (0)

#define ENC_CODERANGE_MASK	RUBY_ENC_CODERANGE_MASK
#define ENC_CODERANGE_UNKNOWN	RUBY_ENC_CODERANGE_UNKNOWN
#define ENC_CODERANGE_7BIT	RUBY_ENC_CODERANGE_7BIT
#define ENC_CODERANGE_VALID	RUBY_ENC_CODERANGE_VALID
#define ENC_CODERANGE_BROKEN	RUBY_ENC_CODERANGE_BROKEN
#define ENC_CODERANGE_CLEAN_P(cr)    RB_ENC_CODERANGE_CLEAN_P(cr)
#define ENC_CODERANGE(obj)           RB_ENC_CODERANGE(obj)
#define ENC_CODERANGE_ASCIIONLY(obj) RB_ENC_CODERANGE_ASCIIONLY(obj)
#define ENC_CODERANGE_SET(obj,cr)    RB_ENC_CODERANGE_SET(obj,cr)
#define ENC_CODERANGE_CLEAR(obj)     RB_ENC_CODERANGE_CLEAR(obj)
#define ENC_CODERANGE_AND(a, b)      RB_ENC_CODERANGE_AND(a, b)
#define ENCODING_CODERANGE_SET(obj, encindex, cr) RB_ENCODING_CODERANGE_SET(obj, encindex, cr)

typedef const OnigEncodingType rb_encoding;

int rb_char_to_option_kcode(int c, int *option, int *kcode);

int rb_enc_replicate(const char *, rb_encoding *);
int rb_define_dummy_encoding(const char *);
PUREFUNC(int rb_enc_dummy_p(rb_encoding *enc));
PUREFUNC(int rb_enc_to_index(rb_encoding *enc));
int rb_enc_get_index(VALUE obj);
void rb_enc_set_index(VALUE obj, int encindex);
int rb_enc_capable(VALUE obj);
int rb_enc_find_index(const char *name);
int rb_enc_alias(const char *alias, const char *orig);
int rb_to_encoding_index(VALUE);
rb_encoding *rb_to_encoding(VALUE);
rb_encoding *rb_find_encoding(VALUE);
rb_encoding *rb_enc_get(VALUE);
rb_encoding *rb_enc_compatible(VALUE,VALUE);
rb_encoding *rb_enc_check(VALUE,VALUE);
VALUE rb_enc_associate_index(VALUE, int);
VALUE rb_enc_associate(VALUE, rb_encoding*);
void rb_enc_copy(VALUE dst, VALUE src);

VALUE rb_enc_str_new(const char*, long, rb_encoding*);
VALUE rb_enc_str_new_cstr(const char*, rb_encoding*);
VALUE rb_enc_str_new_static(const char*, long, rb_encoding*);
VALUE rb_enc_interned_str(const char *, long, rb_encoding *);
VALUE rb_enc_interned_str_cstr(const char *, rb_encoding *);
VALUE rb_enc_reg_new(const char*, long, rb_encoding*, int);
PRINTF_ARGS(VALUE rb_enc_sprintf(rb_encoding *, const char*, ...), 2, 3);
VALUE rb_enc_vsprintf(rb_encoding *, const char*, va_list);
long rb_enc_strlen(const char*, const char*, rb_encoding*);
char* rb_enc_nth(const char*, const char*, long, rb_encoding*);
VALUE rb_obj_encoding(VALUE);
VALUE rb_enc_str_buf_cat(VALUE str, const char *ptr, long len, rb_encoding *enc);
VALUE rb_enc_uint_chr(unsigned int code, rb_encoding *enc);

VALUE rb_external_str_new_with_enc(const char *ptr, long len, rb_encoding *);
VALUE rb_str_export_to_enc(VALUE, rb_encoding *);
VALUE rb_str_conv_enc(VALUE str, rb_encoding *from, rb_encoding *to);
VALUE rb_str_conv_enc_opts(VALUE str, rb_encoding *from, rb_encoding *to, int ecflags, VALUE ecopts);

#ifdef HAVE_BUILTIN___BUILTIN_CONSTANT_P
#define rb_enc_str_new(str, len, enc) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str) && __builtin_constant_p(len)) ? \
	rb_enc_str_new_static((str), (len), (enc)) : \
	rb_enc_str_new((str), (len), (enc)) \
)
#define rb_enc_str_new_cstr(str, enc) RB_GNUC_EXTENSION_BLOCK(	\
    (__builtin_constant_p(str)) ?	       \
	rb_enc_str_new_static((str), (long)strlen(str), (enc)) : \
	rb_enc_str_new_cstr((str), (enc)) \
)
#endif

PRINTF_ARGS(NORETURN(void rb_enc_raise(rb_encoding *, VALUE, const char*, ...)), 3, 4);

/* index -> rb_encoding */
rb_encoding *rb_enc_from_index(int idx);

/* name -> rb_encoding */
rb_encoding *rb_enc_find(const char *name);

/* rb_encoding * -> name */
#define rb_enc_name(enc) (enc)->name

/* rb_encoding * -> minlen/maxlen */
#define rb_enc_mbminlen(enc) (enc)->min_enc_len
#define rb_enc_mbmaxlen(enc) (enc)->max_enc_len

/* -> mbclen (no error notification: 0 < ret <= e-p, no exception) */
int rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc);

/* -> mbclen (only for valid encoding) */
int rb_enc_fast_mbclen(const char *p, const char *e, rb_encoding *enc);

/* -> chlen, invalid or needmore */
int rb_enc_precise_mbclen(const char *p, const char *e, rb_encoding *enc);
#define MBCLEN_CHARFOUND_P(ret)     ONIGENC_MBCLEN_CHARFOUND_P(ret)
#define MBCLEN_CHARFOUND_LEN(ret)     ONIGENC_MBCLEN_CHARFOUND_LEN(ret)
#define MBCLEN_INVALID_P(ret)       ONIGENC_MBCLEN_INVALID_P(ret)
#define MBCLEN_NEEDMORE_P(ret)      ONIGENC_MBCLEN_NEEDMORE_P(ret)
#define MBCLEN_NEEDMORE_LEN(ret)      ONIGENC_MBCLEN_NEEDMORE_LEN(ret)

/* -> 0x00..0x7f, -1 */
int rb_enc_ascget(const char *p, const char *e, int *len, rb_encoding *enc);


/* -> code (and len) or raise exception */
unsigned int rb_enc_codepoint_len(const char *p, const char *e, int *len, rb_encoding *enc);

/* prototype for obsolete function */
unsigned int rb_enc_codepoint(const char *p, const char *e, rb_encoding *enc);
/* overriding macro */
#define rb_enc_codepoint(p,e,enc) rb_enc_codepoint_len((p),(e),0,(enc))
#define rb_enc_mbc_to_codepoint(p, e, enc) ONIGENC_MBC_TO_CODE((enc),(UChar*)(p),(UChar*)(e))

/* -> codelen>0 or raise exception */
int rb_enc_codelen(int code, rb_encoding *enc);
/* -> 0 for invalid codepoint */
int rb_enc_code_to_mbclen(int code, rb_encoding *enc);
#define rb_enc_code_to_mbclen(c, enc) ONIGENC_CODE_TO_MBCLEN((enc), (c));

/* code,ptr,encoding -> write buf */
#define rb_enc_mbcput(c,buf,enc) ONIGENC_CODE_TO_MBC((enc),(c),(UChar*)(buf))

/* start, ptr, end, encoding -> prev_char */
#define rb_enc_prev_char(s,p,e,enc) ((char *)onigenc_get_prev_char_head((enc),(UChar*)(s),(UChar*)(p),(UChar*)(e)))
/* start, ptr, end, encoding -> next_char */
#define rb_enc_left_char_head(s,p,e,enc) ((char *)onigenc_get_left_adjust_char_head((enc),(UChar*)(s),(UChar*)(p),(UChar*)(e)))
#define rb_enc_right_char_head(s,p,e,enc) ((char *)onigenc_get_right_adjust_char_head((enc),(UChar*)(s),(UChar*)(p),(UChar*)(e)))
#define rb_enc_step_back(s,p,e,n,enc) ((char *)onigenc_step_back((enc),(UChar*)(s),(UChar*)(p),(UChar*)(e),(int)(n)))

/* ptr, ptr, encoding -> newline_or_not */
#define rb_enc_is_newline(p,end,enc)  ONIGENC_IS_MBC_NEWLINE((enc),(UChar*)(p),(UChar*)(end))

#define rb_enc_isctype(c,t,enc) ONIGENC_IS_CODE_CTYPE((enc),(c),(t))
#define rb_enc_isascii(c,enc) ONIGENC_IS_CODE_ASCII(c)
#define rb_enc_isalpha(c,enc) ONIGENC_IS_CODE_ALPHA((enc),(c))
#define rb_enc_islower(c,enc) ONIGENC_IS_CODE_LOWER((enc),(c))
#define rb_enc_isupper(c,enc) ONIGENC_IS_CODE_UPPER((enc),(c))
#define rb_enc_ispunct(c,enc) ONIGENC_IS_CODE_PUNCT((enc),(c))
#define rb_enc_isalnum(c,enc) ONIGENC_IS_CODE_ALNUM((enc),(c))
#define rb_enc_isprint(c,enc) ONIGENC_IS_CODE_PRINT((enc),(c))
#define rb_enc_isspace(c,enc) ONIGENC_IS_CODE_SPACE((enc),(c))
#define rb_enc_isdigit(c,enc) ONIGENC_IS_CODE_DIGIT((enc),(c))

static inline int
rb_enc_asciicompat_inline(rb_encoding *enc)
{
    return rb_enc_mbminlen(enc)==1 && !rb_enc_dummy_p(enc);
}
#define rb_enc_asciicompat(enc) rb_enc_asciicompat_inline(enc)

int rb_enc_casefold(char *to, const char *p, const char *e, rb_encoding *enc);
CONSTFUNC(int rb_enc_toupper(int c, rb_encoding *enc));
CONSTFUNC(int rb_enc_tolower(int c, rb_encoding *enc));
ID rb_intern3(const char*, long, rb_encoding*);
ID rb_interned_id_p(const char *, long, rb_encoding *);
int rb_enc_symname_p(const char*, rb_encoding*);
int rb_enc_symname2_p(const char*, long, rb_encoding*);
int rb_enc_str_coderange(VALUE);
long rb_str_coderange_scan_restartable(const char*, const char*, rb_encoding*, int*);
int rb_enc_str_asciionly_p(VALUE);
#define rb_enc_str_asciicompat_p(str) rb_enc_asciicompat(rb_enc_get(str))
VALUE rb_enc_from_encoding(rb_encoding *enc);
PUREFUNC(int rb_enc_unicode_p(rb_encoding *enc));
rb_encoding *rb_ascii8bit_encoding(void);
rb_encoding *rb_utf8_encoding(void);
rb_encoding *rb_usascii_encoding(void);
rb_encoding *rb_locale_encoding(void);
rb_encoding *rb_filesystem_encoding(void);
rb_encoding *rb_default_external_encoding(void);
rb_encoding *rb_default_internal_encoding(void);
#ifndef rb_ascii8bit_encindex
CONSTFUNC(int rb_ascii8bit_encindex(void));
#endif
#ifndef rb_utf8_encindex
CONSTFUNC(int rb_utf8_encindex(void));
#endif
#ifndef rb_usascii_encindex
CONSTFUNC(int rb_usascii_encindex(void));
#endif
int rb_locale_encindex(void);
int rb_filesystem_encindex(void);
VALUE rb_enc_default_external(void);
VALUE rb_enc_default_internal(void);
void rb_enc_set_default_external(VALUE encoding);
void rb_enc_set_default_internal(VALUE encoding);
VALUE rb_locale_charmap(VALUE klass);
long rb_memsearch(const void*,long,const void*,long,rb_encoding*);
char *rb_enc_path_next(const char *,const char *,rb_encoding*);
char *rb_enc_path_skip_prefix(const char *,const char *,rb_encoding*);
char *rb_enc_path_last_separator(const char *,const char *,rb_encoding*);
char *rb_enc_path_end(const char *,const char *,rb_encoding*);
const char *ruby_enc_find_basename(const char *name, long *baselen, long *alllen, rb_encoding *enc);
const char *ruby_enc_find_extname(const char *name, long *len, rb_encoding *enc);
ID rb_check_id_cstr(const char *ptr, long len, rb_encoding *enc);
VALUE rb_check_symbol_cstr(const char *ptr, long len, rb_encoding *enc);

RUBY_EXTERN VALUE rb_cEncoding;

/* econv stuff */

typedef enum {
    econv_invalid_byte_sequence,
    econv_undefined_conversion,
    econv_destination_buffer_full,
    econv_source_buffer_empty,
    econv_finished,
    econv_after_output,
    econv_incomplete_input
} rb_econv_result_t;

typedef struct rb_econv_t rb_econv_t;

VALUE rb_str_encode(VALUE str, VALUE to, int ecflags, VALUE ecopts);
int rb_econv_has_convpath_p(const char* from_encoding, const char* to_encoding);

int rb_econv_prepare_options(VALUE opthash, VALUE *ecopts, int ecflags);
int rb_econv_prepare_opts(VALUE opthash, VALUE *ecopts);

rb_econv_t *rb_econv_open(const char *source_encoding, const char *destination_encoding, int ecflags);
rb_econv_t *rb_econv_open_opts(const char *source_encoding, const char *destination_encoding, int ecflags, VALUE ecopts);

rb_econv_result_t rb_econv_convert(rb_econv_t *ec,
    const unsigned char **source_buffer_ptr, const unsigned char *source_buffer_end,
    unsigned char **destination_buffer_ptr, unsigned char *destination_buffer_end,
    int flags);
void rb_econv_close(rb_econv_t *ec);

/* result: 0:success -1:failure */
int rb_econv_set_replacement(rb_econv_t *ec, const unsigned char *str, size_t len, const char *encname);

/* result: 0:success -1:failure */
int rb_econv_decorate_at_first(rb_econv_t *ec, const char *decorator_name);
int rb_econv_decorate_at_last(rb_econv_t *ec, const char *decorator_name);

VALUE rb_econv_open_exc(const char *senc, const char *denc, int ecflags);

/* result: 0:success -1:failure */
int rb_econv_insert_output(rb_econv_t *ec,
    const unsigned char *str, size_t len, const char *str_encoding);

/* encoding that rb_econv_insert_output doesn't need conversion */
const char *rb_econv_encoding_to_insert_output(rb_econv_t *ec);

/* raise an error if the last rb_econv_convert is error */
void rb_econv_check_error(rb_econv_t *ec);

/* returns an exception object or nil */
VALUE rb_econv_make_exception(rb_econv_t *ec);

int rb_econv_putbackable(rb_econv_t *ec);
void rb_econv_putback(rb_econv_t *ec, unsigned char *p, int n);

/* returns the corresponding ASCII compatible encoding for encname,
 * or NULL if encname is not ASCII incompatible encoding. */
const char *rb_econv_asciicompat_encoding(const char *encname);

VALUE rb_econv_str_convert(rb_econv_t *ec, VALUE src, int flags);
VALUE rb_econv_substr_convert(rb_econv_t *ec, VALUE src, long byteoff, long bytesize, int flags);
VALUE rb_econv_str_append(rb_econv_t *ec, VALUE src, VALUE dst, int flags);
VALUE rb_econv_substr_append(rb_econv_t *ec, VALUE src, long byteoff, long bytesize, VALUE dst, int flags);
VALUE rb_econv_append(rb_econv_t *ec, const char *bytesrc, long bytesize, VALUE dst, int flags);

void rb_econv_binmode(rb_econv_t *ec);

enum ruby_econv_flag_type {
/* flags for rb_econv_open */
    RUBY_ECONV_ERROR_HANDLER_MASK               = 0x000000ff,

    RUBY_ECONV_INVALID_MASK                     = 0x0000000f,
    RUBY_ECONV_INVALID_REPLACE                  = 0x00000002,

    RUBY_ECONV_UNDEF_MASK                       = 0x000000f0,
    RUBY_ECONV_UNDEF_REPLACE                    = 0x00000020,
    RUBY_ECONV_UNDEF_HEX_CHARREF                = 0x00000030,

    RUBY_ECONV_DECORATOR_MASK                   = 0x0000ff00,
    RUBY_ECONV_NEWLINE_DECORATOR_MASK           = 0x00003f00,
    RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK      = 0x00000f00,
    RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK     = 0x00003000,

    RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR      = 0x00000100,
    RUBY_ECONV_CRLF_NEWLINE_DECORATOR           = 0x00001000,
    RUBY_ECONV_CR_NEWLINE_DECORATOR             = 0x00002000,
    RUBY_ECONV_XML_TEXT_DECORATOR               = 0x00004000,
    RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR       = 0x00008000,

    RUBY_ECONV_STATEFUL_DECORATOR_MASK          = 0x00f00000,
    RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR         = 0x00100000,

    RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR        =
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
	RUBY_ECONV_CRLF_NEWLINE_DECORATOR,
#else
	0,
#endif
#define ECONV_ERROR_HANDLER_MASK                RUBY_ECONV_ERROR_HANDLER_MASK
#define ECONV_INVALID_MASK                      RUBY_ECONV_INVALID_MASK
#define ECONV_INVALID_REPLACE                   RUBY_ECONV_INVALID_REPLACE
#define ECONV_UNDEF_MASK                        RUBY_ECONV_UNDEF_MASK
#define ECONV_UNDEF_REPLACE                     RUBY_ECONV_UNDEF_REPLACE
#define ECONV_UNDEF_HEX_CHARREF                 RUBY_ECONV_UNDEF_HEX_CHARREF
#define ECONV_DECORATOR_MASK                    RUBY_ECONV_DECORATOR_MASK
#define ECONV_NEWLINE_DECORATOR_MASK            RUBY_ECONV_NEWLINE_DECORATOR_MASK
#define ECONV_NEWLINE_DECORATOR_READ_MASK       RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK
#define ECONV_NEWLINE_DECORATOR_WRITE_MASK      RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK
#define ECONV_UNIVERSAL_NEWLINE_DECORATOR       RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR
#define ECONV_CRLF_NEWLINE_DECORATOR            RUBY_ECONV_CRLF_NEWLINE_DECORATOR
#define ECONV_CR_NEWLINE_DECORATOR              RUBY_ECONV_CR_NEWLINE_DECORATOR
#define ECONV_XML_TEXT_DECORATOR                RUBY_ECONV_XML_TEXT_DECORATOR
#define ECONV_XML_ATTR_CONTENT_DECORATOR        RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR
#define ECONV_STATEFUL_DECORATOR_MASK           RUBY_ECONV_STATEFUL_DECORATOR_MASK
#define ECONV_XML_ATTR_QUOTE_DECORATOR          RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR
#define ECONV_DEFAULT_NEWLINE_DECORATOR         RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR
/* end of flags for rb_econv_open */

/* flags for rb_econv_convert */
    RUBY_ECONV_PARTIAL_INPUT                    = 0x00010000,
    RUBY_ECONV_AFTER_OUTPUT                     = 0x00020000,
#define ECONV_PARTIAL_INPUT                     RUBY_ECONV_PARTIAL_INPUT
#define ECONV_AFTER_OUTPUT                      RUBY_ECONV_AFTER_OUTPUT
/* end of flags for rb_econv_convert */
RUBY_ECONV_FLAGS_PLACEHOLDER};

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_ENCODING_H */
