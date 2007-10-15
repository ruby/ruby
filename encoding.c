/**********************************************************************

  encoding.c -

  $Author$
  $Date$
  created at: Thu May 24 17:23:27 JST 2007

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "regenc.h"

static ID id_encoding;
static VALUE rb_cEncoding;

struct rb_encoding_entry {
    const char *name;
    rb_encoding *enc;
};

static struct rb_encoding_entry *enc_table;
static int enc_table_size;
static st_table *enc_table_alias;

#define ENC_UNINITIALIZED (&rb_cEncoding)
#define enc_initialized_p(enc) ((enc)->auxiliary_data != &rb_cEncoding)
#define ENC_FROM_ENCODING(enc) ((VALUE)(enc)->auxiliary_data)

static void
enc_mark(void *ptr)
{
}

static VALUE
enc_new(rb_encoding *encoding)
{
    VALUE enc = Data_Wrap_Struct(rb_cEncoding, enc_mark, -1, encoding);
    encoding->auxiliary_data = (void *)enc;
    return enc;
}

static VALUE
enc_from_encoding(rb_encoding *enc)
{
    return enc_initialized_p(enc) ? ENC_FROM_ENCODING(enc) : enc_new(enc);
}

static rb_encoding *
enc_check_encoding(VALUE obj)
{
    if (SPECIAL_CONST_P(obj) || BUILTIN_TYPE(obj) != T_DATA ||
	RDATA(obj)->dmark != enc_mark) {
	return 0;
    }
    return RDATA(obj)->data;
}

static rb_encoding *
enc_get_encoding(VALUE obj)
{
    rb_encoding *enc = enc_check_encoding(obj);
    if (!enc) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected Encoding)",
		 rb_obj_classname(obj));
    }
    return enc;
}

int
rb_to_encoding_index(VALUE enc)
{
    rb_encoding *encoding;

    if (NIL_P(enc)) return 0;
    encoding = enc_check_encoding(enc);
    if (encoding) {
	return rb_enc_to_index(encoding);
    }
    else {
	return rb_enc_find_index(StringValueCStr(enc));
    }
}

rb_encoding *
rb_to_encoding(VALUE enc)
{
    rb_encoding *encoding;
    int idx;

    if (NIL_P(enc)) return rb_enc_from_index(0);
    encoding = enc_check_encoding(enc);
    if (encoding) return encoding;
    if ((idx = rb_enc_find_index(StringValueCStr(enc))) < 0) {
	rb_raise(rb_eArgError, "unknown encoding name - %s", RSTRING_PTR(enc));
    }
    return rb_enc_from_index(idx);
}

void
rb_gc_mark_encodings(void)
{
    int i;
    for (i = 0; i < enc_table_size; ++i) {
	rb_encoding *enc = enc_table[i].enc;
	if (enc && enc_initialized_p(enc)) {
	    rb_gc_mark(ENC_FROM_ENCODING(enc));
	}
    }
}

int
rb_enc_register(const char *name, rb_encoding *encoding)
{
    struct rb_encoding_entry *ent;
    int newsize;

    if (!enc_table) {
	ent = malloc(sizeof(*enc_table));
	newsize = 1;
    }
    else {
	newsize = enc_table_size + 1;
	ent = realloc(enc_table, sizeof(*enc_table)*newsize);
    }
    if (!ent) return -1;
    enc_table = ent;
    enc_table_size = newsize;
    ent = &enc_table[--newsize];
    ent->name = name;
    *(ent->enc = malloc(sizeof(rb_encoding))) = *encoding;
    encoding = ent->enc;
    encoding->name = name;
    if (rb_cEncoding) {
	enc_new(encoding);
    }
    else {
	encoding->auxiliary_data = ENC_UNINITIALIZED;
    }
    return newsize;
}

int
rb_enc_alias(const char *alias, const char *orig)
{
    st_data_t data;
    int idx;

    if (!enc_table_alias) {
	enc_table_alias = st_init_strcasetable();
    }
    while ((idx = rb_enc_find_index(orig)) < 0) {
	if (!st_lookup(enc_table_alias, (st_data_t)orig, &data))
	    return -1;
	orig = (const char *)data;
    }
    st_insert(enc_table_alias, (st_data_t)alias, (st_data_t)orig);
    return idx;
}

void
rb_enc_init(void)
{
#define ENC_REGISTER(enc) rb_enc_register(rb_enc_name(enc), enc)
    ENC_REGISTER(ONIG_ENCODING_ASCII);
    ENC_REGISTER(ONIG_ENCODING_EUC_JP);
    ENC_REGISTER(ONIG_ENCODING_SJIS);
    ENC_REGISTER(ONIG_ENCODING_UTF8);
#undef ENC_REGISTER
    rb_enc_alias("ascii", rb_enc_name(ONIG_ENCODING_ASCII));
    rb_enc_alias("binary", rb_enc_name(ONIG_ENCODING_ASCII));
    rb_enc_alias("us-ascii", rb_enc_name(ONIG_ENCODING_ASCII)); /* will be defined separately in future. */
    rb_enc_alias("sjis", rb_enc_name(ONIG_ENCODING_SJIS));
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

int
rb_enc_find_index(const char *name)
{
    int i;
    st_data_t alias = 0;

    if (!name) return -1;
    if (!enc_table) {
	rb_enc_init();
    }
  find:
    for (i=0; i<enc_table_size; i++) {
	if (strcasecmp(name, enc_table[i].name) == 0) {
	    return i;
	}
    }
    if (!alias && enc_table_alias) {
	if (st_lookup(enc_table_alias, (st_data_t)name, &alias)) {
	    name = (const char *)alias;
	    goto find;
	}
    }
    return -1;
}

rb_encoding *
rb_enc_find(const char *name)
{
    int idx = rb_enc_find_index(name);
    if (idx < 0) idx = 0;
    return rb_enc_from_index(idx);
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

    if (!enc_capable(obj)) return -1;
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

    if (BUILTIN_TYPE(str1) != T_STRING) {
	VALUE tmp = str1;
	str1 = str2;
	str2 = tmp;
    }
    if (BUILTIN_TYPE(str1) == T_STRING) {
	int cr1, cr2;

	cr1 = rb_enc_str_coderange(str1);
	if (BUILTIN_TYPE(str2) == T_STRING) {
	    cr2 = rb_enc_str_coderange(str2);
	    if (cr1 != cr2) {
		/* may need to handle ENC_CODERANGE_BROKEN */
		if (cr1 == ENC_CODERANGE_SINGLE) return rb_enc_from_index(idx2);
		if (cr2 == ENC_CODERANGE_SINGLE) return rb_enc_from_index(idx1);
	    }
	    if (cr1 == ENC_CODERANGE_SINGLE) return rb_enc_from_index(0);
	}
	if (cr1 == ENC_CODERANGE_SINGLE &&
	    rb_enc_asciicompat(enc = rb_enc_from_index(idx2)))
	    return enc;
    }
    rb_raise(rb_eArgError, "character encodings differ");
}

void
rb_enc_copy(VALUE obj1, VALUE obj2)
{
    rb_enc_associate_index(obj1, rb_enc_get_index(obj2));
}


/*
 *  call-seq:
 *     obj.encoding   => encoding
 *
 *  Returns the Encoding object that represents the encoding of obj.
 */

VALUE
rb_obj_encoding(VALUE obj)
{
    rb_encoding *enc = rb_enc_get(obj);
    if (!enc) {
	rb_raise(rb_eTypeError, "unknown encoding");
    }
    return enc_from_encoding(enc);
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

static VALUE
enc_inspect(VALUE self)
{
    return rb_sprintf("<%s:%s>", rb_obj_classname(self),
		      rb_enc_name(enc_get_encoding(self)));
}

static VALUE
enc_name(VALUE self)
{
    return rb_str_new2(rb_enc_name(enc_get_encoding(self)));
}

static VALUE
enc_list(VALUE klass)
{
    VALUE ary = rb_ary_new2(enc_table_size);
    int i;
    rb_cEncoding = rb_define_class("Encoding", rb_cObject);
    for (i = 0; i < enc_table_size; ++i) {
	rb_encoding *enc = enc_table[i].enc;
	if (enc) {
	    rb_ary_push(ary, enc_from_encoding(enc));
	}
    }
    return ary;
}

static VALUE
enc_find(VALUE klass, VALUE enc)
{
    int idx = rb_enc_find_index(StringValueCStr(enc));
    if (idx < 0) {
	rb_raise(rb_eArgError, "unknown encoding name - %s", RSTRING_PTR(enc));
    }
    return enc_from_encoding(rb_enc_from_index(idx));
}

/* :nodoc: */
static VALUE
enc_dump(int argc, VALUE *argv, VALUE self)
{
    rb_scan_args(argc, argv, "01", 0);
    return enc_name(self);
}

/* :nodoc: */
static VALUE
enc_load(VALUE klass, VALUE str)
{
    return enc_find(klass, str);
}

void
Init_Encoding(void)
{
    rb_cEncoding = rb_define_class("Encoding", rb_cObject);
    rb_undef_alloc_func(rb_cEncoding);
    rb_define_method(rb_cEncoding, "to_s", enc_inspect, 0);
    rb_define_method(rb_cEncoding, "inspect", enc_inspect, 0);
    rb_define_method(rb_cEncoding, "name", enc_name, 0);
    rb_define_singleton_method(rb_cEncoding, "list", enc_list, 0);
    rb_define_singleton_method(rb_cEncoding, "find", enc_find, 1);

    rb_define_method(rb_cEncoding, "_dump", enc_dump, -1);
    rb_define_singleton_method(rb_cEncoding, "_load", enc_load, 1);
}
