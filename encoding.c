/**********************************************************************

  encoding.c -

  $Author: matz $
  $Date: 2007-05-24 17:22:33 +0900 (Thu, 24 May 2007) $
  created at: Thu May 24 17:23:27 JST 2007

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "regenc.h"

static ID id_encoding;

struct rb_encoding_entry {
    const char *name;
    rb_encoding *enc;
};

static struct rb_encoding_entry *enc_table;
static int enc_table_size;

void
rb_enc_register(const char *name, rb_encoding *encoding)
{
    struct rb_encoding_entry *ent;

    if (!enc_table) {
	enc_table = malloc(sizeof(struct rb_encoding_entry));
	enc_table_size = 1;
    }
    else {
	enc_table_size++;
	enc_table = realloc(enc_table, sizeof(struct rb_encoding_entry)*enc_table_size);
    }
    ent = &enc_table[enc_table_size-1];
    ent->name = name;
    ent->enc = encoding;
}

void
rb_enc_init(void)
{
    rb_enc_register("ascii", ONIG_ENCODING_ASCII);
    rb_enc_register("sjis", ONIG_ENCODING_SJIS);
    rb_enc_register("euc-jp", ONIG_ENCODING_EUC_JP);
    rb_enc_register("utf-8", ONIG_ENCODING_UTF8);
}

rb_encoding *
rb_enc_from_index(int index)
{
    if (!enc_table) {
	rb_enc_init();
    }
    if (index < 0 || enc_table_size <= index) {
	return 0;
    }
    return enc_table[index].enc;
}

rb_encoding *
rb_enc_find(const char *name)
{
    int i;

    if (!enc_table) {
	rb_enc_init();
    }
    for (i=0; i<enc_table_size; i++) {
	if (strcmp(name, enc_table[i].name) == 0) {
	    return enc_table[i].enc;
	}
    }
    return ONIG_ENCODING_ASCII;
}

static int
enc_capable(VALUE obj)
{
    if (IMMEDIATE_P(obj)) return Qfalse;
    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
      case T_REGEXP:
      case T_FILE:
	return Qtrue;
      default:
	return Qfalse;
    }
}

static void
enc_check_capable(VALUE x)
{
    if (!enc_capable(x)) {
	const char *etype;

	if (NIL_P(x)) {
	    etype = "nil";
	}
	else if (FIXNUM_P(x)) {
	    etype = "Fixnum";
	}
	else if (SYMBOL_P(x)) {
	    etype = "Symbol";
	}
	else if (rb_special_const_p(x)) {
	    etype = RSTRING_PTR(rb_obj_as_string(x));
	}
	else {
	    etype = rb_obj_classname(x);
	}
	rb_raise(rb_eTypeError, "wrong argument type %s (not encode capable)", etype);
    }
}

void
rb_enc_associate_index(VALUE obj, int idx)
{
    enc_check_capable(obj);
    if (!ENC_CODERANGE_ASCIIONLY(obj) ||
	!rb_enc_asciicompat(rb_enc_from_index(idx))) {
	ENC_CODERANGE_CLEAR(obj);
    }
    if (idx < ENCODING_INLINE_MAX) {
	ENCODING_SET(obj, idx);
	return;
    }
    ENCODING_SET(obj, ENCODING_INLINE_MAX);
    if (!id_encoding) {
	id_encoding = rb_intern("encoding");
    }
    rb_ivar_set(obj, id_encoding, INT2NUM(idx));
    return;
}

int
rb_enc_to_index(rb_encoding *enc)
{
    int i;

    if (!enc) return 0;
    for (i=0; i<enc_table_size; i++) {
	if (enc_table[i].enc == enc) {
	    return i;
	}
    }
    return 0;
}

void
rb_enc_associate(VALUE obj, rb_encoding *enc)
{
    rb_enc_associate_index(obj, rb_enc_to_index(enc));
}

int
rb_enc_get_index(VALUE obj)
{
    int i;

    enc_check_capable(obj);
    i = ENCODING_GET(obj);
    if (i == ENCODING_INLINE_MAX) {
	VALUE iv;

	if (!id_encoding) {
	    id_encoding = rb_intern("encoding");
	}
	iv = rb_ivar_get(obj, id_encoding);
	i = NUM2INT(iv);
    }
    return i;
}

rb_encoding*
rb_enc_get(VALUE obj)
{
    return rb_enc_from_index(rb_enc_get_index(obj));
}

rb_encoding*
rb_enc_check(VALUE str1, VALUE str2)
{
    int idx1, idx2;
    rb_encoding *enc;

    idx1 = rb_enc_get_index(str1);
    idx2 = rb_enc_get_index(str2);

    if (idx1 == idx2) {
	return rb_enc_from_index(idx1);
    }

    if (idx1 == 0) {
	enc = rb_enc_from_index(idx2);
	if (rb_enc_asciicompat(enc)) {
	    return enc;
	}
    }
    else if (idx2 == 0) {
	enc = rb_enc_from_index(idx1);
	if (rb_enc_asciicompat(enc)) {
	    return enc;
	}
    }
    if (BUILTIN_TYPE(str1) == T_STRING &&
	BUILTIN_TYPE(str2) == T_STRING &&
	rb_enc_asciicompat(rb_enc_from_index(idx1)) &&
	rb_enc_asciicompat(rb_enc_from_index(idx2)) &&
	rb_enc_str_coderange(str1) == ENC_CODERANGE_SINGLE &&
	rb_enc_str_coderange(str2) == ENC_CODERANGE_SINGLE) {
	return ONIG_ENCODING_ASCII;
    }
    rb_raise(rb_eArgError, "character encodings differ");
}

void
rb_enc_copy(VALUE obj1, VALUE obj2)
{
    rb_enc_associate_index(obj1, rb_enc_get_index(obj2));
}


char*
rb_enc_nth(const char *p, const char *e, int nth, rb_encoding *enc)
{
    int c;

    if (rb_enc_mbmaxlen(enc) == 1) {
	p += nth;
    }
    else if (rb_enc_mbmaxlen(enc) == rb_enc_mbminlen(enc)) {
	p += nth * rb_enc_mbmaxlen(enc);
    }
    else {
	for (c=0; p<e && nth--; c++) {
	    int n = rb_enc_mbclen(p, e, enc);

	    if (n == 0) return 0;
	    p += n;
	}
    }
    return (char*)p;
}

long
rb_enc_strlen(const char *p, const char *e, rb_encoding *enc)
{
    long c;

    if (rb_enc_mbmaxlen(enc) == rb_enc_mbminlen(enc)) {
	return (e - p) / rb_enc_mbminlen(enc);
    }

    for (c=0; p<e; c++) {
	int n = rb_enc_mbclen(p, e, enc);

	if (n == 0) return -1;
	p += n;
    }
    return c;
}

int
rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc)
{
    int n = ONIGENC_MBC_ENC_LEN(enc, (UChar*)p, (UChar*)e);
    if (n == 0) {
	rb_raise(rb_eArgError, "invalid mbstring sequence");
    }
    return n;
}

int
rb_enc_codelen(int c, rb_encoding *enc)
{
    int n = ONIGENC_CODE_TO_MBCLEN(enc,c);
    if (n == 0) {
	rb_raise(rb_eArgError, "invalid mbstring sequence");
    }
    return n;
}

int
rb_enc_toupper(int c, rb_encoding *enc)
{
    return (ONIGENC_IS_ASCII_CODE(c)?ONIGENC_ASCII_CODE_TO_UPPER_CASE(c):(c));
}

int
rb_enc_tolower(int c, rb_encoding *enc)
{
    return (ONIGENC_IS_ASCII_CODE(c)?ONIGENC_ASCII_CODE_TO_LOWER_CASE(c):(c));
}
