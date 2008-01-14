/**********************************************************************

  encoding.c -

  $Author$
  created at: Thu May 24 17:23:27 JST 2007

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include "regenc.h"
#include <ctype.h>
#ifdef HAVE_LANGINFO_H
#include <langinfo.h>
#endif

static ID id_encoding, id_base_encoding;
static VALUE rb_cEncoding;

struct rb_encoding_entry {
    const char *name;
    rb_encoding *enc;
};

static struct {
    struct rb_encoding_entry *list;
    int count;
    int size;
    st_table *alias;
    st_table *replica_name;
    st_table *alias_name;
} enc_table;

#undef ENC_REPLICATE
#undef ENC_ALIAS
#define ENC_REPLICATE(name, orig) st_insert(enc_table.replica_name, (st_data_t)(name), (st_data_t)(orig))
#define ENC_ALIAS(name, orig) st_insert(enc_table.alias_name, (st_data_t)(name), (st_data_t)(orig))
#define enc_name_list_size (sizeof(enc_name_list)/sizeof(enc_name_list[0]))

#include "encdb.h"

#define ENC_UNINITIALIZED (&rb_cEncoding)
#define enc_initialized_p(enc) ((enc)->auxiliary_data != &rb_cEncoding)
#define ENC_FROM_ENCODING(enc) ((VALUE)(enc)->auxiliary_data)

#define ENC_DUMMY FL_USER2
#define ENC_DUMMY_P(enc) (RBASIC(enc)->flags & ENC_DUMMY)

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

VALUE
rb_enc_from_encoding(rb_encoding *encoding)
{
    if (!encoding) return Qnil;
    if (enc_initialized_p(encoding))
	return ENC_FROM_ENCODING(encoding);
    return enc_new(encoding);
}

static int
enc_check_encoding(VALUE obj)
{
    int index;
    if (SPECIAL_CONST_P(obj) || BUILTIN_TYPE(obj) != T_DATA ||
	RDATA(obj)->dmark != enc_mark) {
	return -1;
    }
    index = rb_enc_to_index((rb_encoding*)RDATA(obj)->data);
    if (rb_enc_from_index(index) != RDATA(obj)->data)
	return -1;
    return index;
}

int
rb_to_encoding_index(VALUE enc)
{
    int idx;

    idx = enc_check_encoding(enc);
    if (idx >= 0) {
	return idx;
    }
    else if (NIL_P(enc = rb_check_string_type(enc))) {
	return -1;
    }
    else {
	return rb_enc_find_index(StringValueCStr(enc));
    }
}

rb_encoding *
rb_to_encoding(VALUE enc)
{
    int idx;

    idx = enc_check_encoding(enc);
    if (idx >= 0) return RDATA(enc)->data;
    if ((idx = rb_enc_find_index(StringValueCStr(enc))) < 0) {
	rb_raise(rb_eArgError, "unknown encoding name - %s", RSTRING_PTR(enc));
    }
    return rb_enc_from_index(idx);
}

void
rb_gc_mark_encodings(void)
{
    int i;
    for (i = 0; i < enc_table.size; ++i) {
	rb_encoding *enc = enc_table.list[i].enc;
	if (enc && enc_initialized_p(enc)) {
	    rb_gc_mark(ENC_FROM_ENCODING(enc));
	}
    }
}

static int
enc_table_expand(int newsize)
{
    struct rb_encoding_entry *ent;

    if (enc_table.size >= newsize) return newsize;
    ent = realloc(enc_table.list, sizeof(*enc_table.list) * newsize);
    if (!ent) return -1;
    memset(ent + enc_table.size, 0, sizeof(*ent)*(newsize - enc_table.size));
    enc_table.list = ent;
    enc_table.size = newsize;
    return newsize;
}

static int
enc_register_at(int index, const char *name, rb_encoding *encoding)
{
    struct rb_encoding_entry *ent = &enc_table.list[index];

    ent->name = name;
    if (!ent->enc) ent->enc = malloc(sizeof(rb_encoding));
    *ent->enc = *encoding;
    encoding = ent->enc;
    encoding->name = name;
    encoding->ruby_encoding_index = index;
    if (rb_cEncoding) {
	/* initialize encoding data */
	enc_new(encoding);
    }
    else {
	encoding->auxiliary_data = ENC_UNINITIALIZED;
    }
    return index;
}

static int
enc_register(const char *name, rb_encoding *encoding)
{
    int index = enc_table.count;

    if (index >= ENCODING_INLINE_MAX) index = enc_table.size;
    if ((index = enc_table_expand(index + 1)) < 0) return -1;
    enc_table.count = index;
    return enc_register_at(index - 1, name, encoding);
}

static void set_encoding_const(const char *, rb_encoding *);
int rb_enc_registered(const char *name);

int
rb_enc_register(const char *name, rb_encoding *encoding)
{
    int index = rb_enc_registered(name);

    if (index >= 0) {
	rb_encoding *oldenc = rb_enc_from_index(index);
	if (STRCASECMP(name, rb_enc_name(oldenc))) {
	    st_data_t key = (st_data_t)name, alias;
	    st_delete(enc_table.alias, &key, &alias);
	    index = enc_register(name, encoding);
	}
	else if (enc_initialized_p(oldenc) &&
		 !ENC_DUMMY_P(ENC_FROM_ENCODING(oldenc))) {
	    enc_register_at(index, name, encoding);
	}
	else {
	    rb_raise(rb_eArgError, "encoding %s is already registered", name);
	}
    }
    else {
	index = enc_register(name, encoding);
    }
    set_encoding_const(name, rb_enc_from_index(index));
    return index;
}

static void
enc_check_duplication(const char *name)
{
    if (rb_enc_registered(name) >= 0) {
	rb_raise(rb_eArgError, "encoding %s is already registered", name);
    }
}

static VALUE
set_base_encoding(int index, rb_encoding *base)
{
    VALUE enc = rb_enc_from_encoding(enc_table.list[index].enc);

    rb_ivar_set(enc, id_base_encoding, rb_enc_from_encoding(base));
    if (rb_enc_dummy_p(base)) FL_SET(enc, ENC_DUMMY);
    return enc;
}

int
rb_enc_replicate(const char *name, rb_encoding *encoding)
{
    int index = enc_table.size;

    enc_check_duplication(name);
    if (enc_table_expand(index + 1) < 0) return -1;
    enc_register_at(index, name, encoding);
    set_base_encoding(index, encoding);
    return index;
}

int
rb_define_dummy_encoding(const char *name)
{
    int index = enc_table.size;
    rb_encoding *encoding;
    VALUE enc;

    enc_check_duplication(name);
    if (index < ENCODING_INLINE_MAX) index = ENCODING_INLINE_MAX;
    if (enc_table_expand(index + 1) < 0) return -1;
    encoding = rb_ascii8bit_encoding();
    enc_register_at(index, name, encoding);
    enc = set_base_encoding(index, encoding);
    FL_SET(enc, ENC_DUMMY);
    return index;
}

int
rb_enc_dummy_p(rb_encoding *enc)
{
    VALUE encoding = rb_enc_from_encoding(enc);
    return ENC_DUMMY_P(encoding);
}

/*
 * call-seq:
 *   enc.dummy? => true or false
 *
 * Returns true for dummy encoding.
 * A dummy encoding is a encoding which character handling is not properly
 * implemented.
 * It is used for stateful encoding.
 *
 *   Encoding::ISO_2022_JP.dummy?       #=> true
 *   Encoding::UTF_8.dummy?             #=> false
 *
 */
static VALUE
enc_dummy_p(VALUE enc)
{
    return rb_enc_dummy_p(rb_to_encoding(enc)) ? Qtrue : Qfalse;
}

static int
enc_alias(const char *alias, const char *orig)
{
    st_data_t data;
    int idx;

    if (!enc_table.alias) {
	enc_table.alias = st_init_strcasetable();
    }
    if ((idx = rb_enc_find_index(orig)) < 0) {
	if (!st_lookup(enc_table.alias, (st_data_t)orig, &data))
	    return -1;
	idx = (int)data;
    }
    st_insert(enc_table.alias, (st_data_t)alias, (st_data_t)idx);
    return idx;
}

int
rb_enc_alias(const char *alias, const char *orig)
{
    enc_check_duplication(alias);
    return enc_alias(alias, orig);
}

enum {
    ENCINDEX_ASCII,
    ENCINDEX_UTF8,
    ENCINDEX_BUILTIN_MAX
};

void
rb_enc_init(void)
{
    enc_table.count = enc_table_expand(ENCINDEX_BUILTIN_MAX);
#define ENC_REGISTER(enc) enc_register_at(ENCINDEX_##enc, rb_enc_name(ONIG_ENCODING_##enc), ONIG_ENCODING_##enc)
    ENC_REGISTER(ASCII);
    ENC_REGISTER(UTF8);
#undef ENC_REGISTER
}

rb_encoding *
rb_enc_from_index(int index)
{
    if (!enc_table.list) {
	rb_enc_init();
    }
    if (index < 0 || enc_table.size <= index) {
	return 0;
    }
    return enc_table.list[index].enc;
}

int
rb_enc_registered(const char *name)
{
    int i;
    st_data_t alias = 0;

    if (!name) return -1;
    if (!enc_table.list) {
	rb_enc_init();
    }
    for (i=0; i<enc_table.size; i++) {
	if (!enc_table.list[i].name) {
	    if (i < ENCODING_INLINE_MAX - 1) i = ENCODING_INLINE_MAX - 1;
	    continue;
	}
	if (STRCASECMP(name, enc_table.list[i].name) == 0) {
	    return i;
	}
    }
    if (!alias && enc_table.alias) {
	if (st_lookup(enc_table.alias, (st_data_t)name, &alias)) {
	    return (int)alias;
	}
    }
    return -1;
}

static VALUE
require_enc(VALUE enclib)
{
    return rb_require_safe(enclib, rb_safe_level());
}

int
rb_enc_find_index(const char *name)
{
    int i = rb_enc_registered(name);
    if (i < 0) {
	VALUE enclib = rb_sprintf("enc/%s", name);
	char *s = RSTRING_PTR(enclib) + 4, *e = RSTRING_END(enclib);
	while (s < e) {
	    if (!ISALNUM(*s)) *s = '_';
	    else if (ISUPPER(*s)) *s = TOLOWER(*s);
	    ++s;
	}
	OBJ_FREEZE(enclib);
	if (RTEST(rb_protect(require_enc, enclib, 0)))
	    i = rb_enc_registered(name);
	rb_set_errinfo(Qnil);
    }
    if (i < 0) {
	st_data_t key = (st_data_t)name, orig;
	if (st_lookup(enc_table.replica_name, key, &orig)) {
	    i = rb_enc_find_index((char *)orig);
	    if (i < 0) {
		rb_raise(rb_eRuntimeError, "unknown original encoding name - '%s' for replica '%s'", (char *)orig, name);
	    }
	    i = rb_enc_replicate(name, rb_enc_from_index(i));
	    st_delete(enc_table.replica_name, &key, &orig);
	}
	else if (st_lookup(enc_table.alias_name, key, &orig)) {
	    i = rb_enc_alias(name, (char *)orig);
	    if (i < 0) {
		rb_raise(rb_eRuntimeError, "unknown original encoding name - '%s' for alias '%s'", (char *)orig, name);
	    }
	    st_delete(enc_table.alias_name, &key, &orig);
	}
    }
    return i;
}

rb_encoding *
rb_enc_find(const char *name)
{
    int idx = rb_enc_find_index(name);
    if (idx < 0) idx = 0;
    return rb_enc_from_index(idx);
}

static inline int
enc_capable(VALUE obj)
{
    if (IMMEDIATE_P(obj)) return Qfalse;
    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
      case T_REGEXP:
      case T_FILE:
	return Qtrue;
      case T_DATA:
	if (RDATA(obj)->dmark == enc_mark) return Qtrue;
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

ID
rb_id_encoding(void)
{
    if (!id_encoding) {
	id_encoding = rb_intern("encoding");
    }
    return id_encoding;
}

int
rb_enc_internal_get_index(VALUE obj)
{
    int i;

    i = ENCODING_GET_INLINED(obj);
    if (i == ENCODING_INLINE_MAX) {
	VALUE iv;

	iv = rb_ivar_get(obj, rb_id_encoding());
	i = NUM2INT(iv);
    }
    return i;
}

void
rb_enc_internal_set_index(VALUE obj, int idx)
{
    if (idx < ENCODING_INLINE_MAX) {
	ENCODING_SET_INLINED(obj, idx);
	return;
    }
    ENCODING_SET_INLINED(obj, ENCODING_INLINE_MAX);
    rb_ivar_set(obj, rb_id_encoding(), INT2NUM(idx));
    return;
}

void
rb_enc_associate_index(VALUE obj, int idx)
{
    enc_check_capable(obj);
    if (!ENC_CODERANGE_ASCIIONLY(obj) ||
	!rb_enc_asciicompat(rb_enc_from_index(idx))) {
	ENC_CODERANGE_CLEAR(obj);
    }
    rb_enc_internal_set_index(obj, idx);
}

void
rb_enc_associate(VALUE obj, rb_encoding *enc)
{
    rb_enc_associate_index(obj, rb_enc_to_index(enc));
}

int
rb_enc_get_index(VALUE obj)
{
    if (!enc_capable(obj)) return -1;
    return rb_enc_internal_get_index(obj);
}

rb_encoding*
rb_enc_get(VALUE obj)
{
    return rb_enc_from_index(rb_enc_get_index(obj));
}

rb_encoding*
rb_enc_check(VALUE str1, VALUE str2)
{
    rb_encoding *enc = rb_enc_compatible(str1, str2);
    if (!enc)
	rb_raise(rb_eArgError, "character encodings differ: %s and %s",
            rb_enc_name(rb_enc_get(str1)),
            rb_enc_name(rb_enc_get(str2)));
    return enc;
}

rb_encoding*
rb_enc_compatible(VALUE str1, VALUE str2)
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
	int idx0 = idx1;
	str1 = str2;
	str2 = tmp;
	idx1 = idx2;
	idx2 = idx0;
    }
    if (BUILTIN_TYPE(str1) == T_STRING) {
	int cr1, cr2;

	cr1 = rb_enc_str_coderange(str1);
	if (BUILTIN_TYPE(str2) == T_STRING) {
	    cr2 = rb_enc_str_coderange(str2);
	    if (cr1 != cr2) {
		/* may need to handle ENC_CODERANGE_BROKEN */
		if (cr1 == ENC_CODERANGE_7BIT) return rb_enc_from_index(idx2);
		if (cr2 == ENC_CODERANGE_7BIT) return rb_enc_from_index(idx1);
	    }
	    if (cr2 == ENC_CODERANGE_7BIT) {
		if (idx1 == 0) return rb_enc_from_index(idx2);
		return rb_enc_from_index(idx1);
	    }
	}
	if (cr1 == ENC_CODERANGE_7BIT &&
	    rb_enc_asciicompat(enc = rb_enc_from_index(idx2)))
	    return enc;
    }
    return 0;
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
    return rb_enc_from_encoding(enc);
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

	p += n;
    }
    return c;
}

int
rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc)
{
    int n = ONIGENC_PRECISE_MBC_ENC_LEN(enc, (UChar*)p, (UChar*)e);
    n = MBCLEN_CHARFOUND(n);
    if (0 < n && n <= e-p)
        return n;
    else
        return 1;
}

int
rb_enc_precise_mbclen(const char *p, const char *e, rb_encoding *enc)
{
    int n;
    if (e <= p)
        return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(1);
    n = ONIGENC_PRECISE_MBC_ENC_LEN(enc, (UChar*)p, (UChar*)e);
    if (e-p < n)
        return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(n-(e-p));
    return n;
}

int
rb_enc_ascget(const char *p, const char *e, int *len, rb_encoding *enc)
{
    int c, l;
    if (e <= p)
        return -1;
    if (rb_enc_asciicompat(enc)) {
        c = (unsigned char)*p;
        if (!ISASCII(c))
            return -1;
        if (len) *len = 1;
        return c;
    }
    l = rb_enc_precise_mbclen(p, e, enc);
    if (!MBCLEN_CHARFOUND(l))
        return -1;
    c = rb_enc_codepoint(p, e, enc);
    if (!rb_enc_isascii(c, enc))
        return -1;
    if (len) *len = l;
    return c;
}

int
rb_enc_codepoint(const char *p, const char *e, rb_encoding *enc)
{
    int r;
    if (e <= p)
        rb_raise(rb_eArgError, "empty string");
    r = rb_enc_precise_mbclen(p, e, enc);
    if (MBCLEN_CHARFOUND(r))
        return rb_enc_mbc_to_codepoint(p, e, enc);
    else
	rb_raise(rb_eArgError, "invalid mbstring sequence");
}

int
rb_enc_codelen(int c, rb_encoding *enc)
{
    int n = ONIGENC_CODE_TO_MBCLEN(enc,c);
    if (n == 0) {
	rb_raise(rb_eArgError, "invalid codepoint 0x%x", c);
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

/*
 * call-seq:
 *   enc.inspect => string
 *
 * Returns a string which represents the encoding for programmers.
 *
 *   Encoding::UTF_8.inspect       #=> "#<Encoding:UTF-8>"
 *   Encoding::ISO_2022_JP.inspect #=> "#<Encoding:ISO-2022-JP (dummy)>"
 */
static VALUE
enc_inspect(VALUE self)
{
    return rb_sprintf("#<%s:%s%s>", rb_obj_classname(self),
		      rb_enc_name((rb_encoding*)DATA_PTR(self)),
		      (ENC_DUMMY_P(self) ? " (dummy)" : ""));
}

/*
 * call-seq:
 *   enc.name => string
 *
 * Returns the name of the encoding.
 *
 *   Encoding::UTF_8.name       => "UTF-8"
 */
static VALUE
enc_name(VALUE self)
{
    return rb_str_new2(rb_enc_name((rb_encoding*)DATA_PTR(self)));
}

static VALUE
enc_base_encoding(VALUE self)
{
    return rb_attr_get(self, id_base_encoding);
}

/*
 * call-seq:
 *   Encoding.list => [enc1, enc2, ...]
 *
 * Returns the list of loaded encodings.
 *
 *   Encoding.list
 *   => [#<Encoding:ASCII-8BIT>, #<Encoding:UTF-8>,
 *       #<Encoding:ISO-2022-JP (dummy)>]
 *
 *   Encoding.find("US-ASCII")
 *   => #<Encoding:US-ASCII>
 *
 *   Encoding.list
 *   => [#<Encoding:ASCII-8BIT>, #<Encoding:UTF-8>,
 *       #<Encoding:US-ASCII>, #<Encoding:ISO-2022-JP (dummy)>]
 *
 */
static VALUE
enc_list(VALUE klass)
{
    VALUE ary = rb_ary_new2(enc_table.size);
    int i;
    for (i = 0; i < enc_table.size; ++i) {
	rb_encoding *enc = enc_table.list[i].enc;
	if (enc) {
	    rb_ary_push(ary, rb_enc_from_encoding(enc));
	}
    }
    return ary;
}

/*
 * call-seq:
 *   Encoding.find(string) => enc
 *   Encoding.find(symbol) => enc
 *
 * Search the encoding with specified <i>name</i>.
 * <i>name</i> should be a string or symbol.
 *
 *   Encoding.find("US-ASCII")  => #<Encoding:US-ASCII>
 *   Encoding.find(:Shift_JIS)  => #<Encoding:Shift_JIS>
 *
 */
static VALUE
enc_find(VALUE klass, VALUE enc)
{
    int idx;
    if (SYMBOL_P(enc)) enc = rb_id2str(SYM2ID(enc));
    idx = rb_enc_find_index(StringValueCStr(enc));
    if (idx < 0) {
	rb_raise(rb_eArgError, "unknown encoding name - %s", RSTRING_PTR(enc));
    }
    return rb_enc_from_encoding(rb_enc_from_index(idx));
}

/*
 * call-seq:
 *   Encoding.compatible?(str1, str2) => enc or nil
 *
 * Checks the compatibility of two strings.
 * If they are compatible, means concatenatable, 
 * returns an encoding which the concatinated string will be.
 * If they are not compatible, nil is returned.
 *
 *   Encoding.compatible?("\xa1".force_encoding("iso-8859-1"), "b")
 *   => #<Encoding:ISO-8859-1>
 *
 *   Encoding.compatible?(
 *     "\xa1".force_encoding("iso-8859-1"),
 *     "\xa1\xa1".force_encoding("euc-jp"))
 *   => nil
 *
 */
static VALUE
enc_compatible_p(VALUE klass, VALUE str1, VALUE str2)
{
    rb_encoding *enc = rb_enc_compatible(str1, str2);
    VALUE encoding = Qnil;
    if (!enc || !(encoding = rb_enc_from_encoding(enc)))
	encoding = Qnil;
    return encoding;
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

rb_encoding *
rb_ascii8bit_encoding(void)
{
    if (!enc_table.list) {
	rb_enc_init();
    }
    return enc_table.list[0].enc;
}

rb_encoding *
rb_utf8_encoding(void)
{
    if (!enc_table.list) {
	rb_enc_init();
    }
    return enc_table.list[ENCINDEX_UTF8].enc;
}

rb_encoding *
rb_locale_encoding(void)
{
    VALUE charmap = rb_locale_charmap(rb_cEncoding);
    int idx;

    if (NIL_P(charmap))
        idx = rb_enc_find_index("US-ASCII");
    else
        idx = rb_enc_find_index(StringValueCStr(charmap));
    if (idx < 0)
        return rb_ascii8bit_encoding();

    return rb_enc_from_index(idx);
}

static int default_external_index;

rb_encoding *
rb_default_external_encoding(void)
{
    return rb_enc_from_index(default_external_index);
}

VALUE
rb_enc_default_external(void)
{
    return rb_enc_from_encoding(rb_default_external_encoding());
}

/*
 * call-seq:
 *   Encoding.default_external => enc
 *
 * Returns default external encoding.
 *
 * It is initialized by the locale or -E option.
 */
static VALUE
get_default_external(VALUE klass)
{
    return rb_enc_default_external();
}

void
rb_enc_set_default_external(VALUE encoding)
{
    default_external_index = rb_enc_to_index(rb_to_encoding(encoding));
}

/*
 * call-seq:
 *   Encoding.locale_charmap => string
 *
 * Returns the locale charmap name.
 *
 *   Debian GNU/Linux
 *     LANG=C
 *       Encoding.locale_charmap  => "ANSI_X3.4-1968"
 *     LANG=ja_JP.EUC-JP
 *       Encoding.locale_charmap  => "EUC-JP"
 *
 *   SunOS 5
 *     LANG=C
 *       Encoding.locale_charmap  => "646"
 *     LANG=ja
 *       Encoding.locale_charmap  => "eucJP"
 *
 */
VALUE
rb_locale_charmap(VALUE klass)
{
#ifdef HAVE_LANGINFO_H
    char *codeset;
    codeset = nl_langinfo(CODESET);
    return rb_str_new2(codeset);
#elif defined _WIN32
    return rb_sprintf("CP%d", GetACP());
#else
    return Qnil;
#endif
}

static void
set_encoding_const(const char *name, rb_encoding *enc)
{
    VALUE encoding = rb_enc_from_encoding(enc);
    char *s = (char *)name;
    int haslower = 0, valid = 0;

    if (ISUPPER(*s)) {
	while (*++s && (ISALNUM(*s) || *s == '_')) {
	    if (ISLOWER(*s)) haslower = 1;
	}
    }
    if (!*s) {
	valid = 1;
	rb_define_const(rb_cEncoding, name, encoding);
    }
    if (!valid || haslower) {
	int len = strlen(name) + 1;
	if (!haslower) {
	    while (!ISLOWER(*s) && *++s);
	    if (*s) haslower = 1;
	}
	MEMCPY(s = ALLOCA_N(char, len), name, char, len);
	name = s;
	if (!valid) {
	    if (ISLOWER(*s)) *s = ONIGENC_ASCII_CODE_TO_UPPER_CASE((int)*s);
	    for (; *s; ++s) {
		if (!ISALNUM(*s)) *s = '_';
	    }
	    rb_define_const(rb_cEncoding, name, encoding);
	}
	if (haslower) {
	    for (s = (char *)name; *s; ++s) {
		if (ISLOWER(*s)) *s = ONIGENC_ASCII_CODE_TO_UPPER_CASE((int)*s);
	    }
	    rb_define_const(rb_cEncoding, name, encoding);
	}
    }
}

static int
set_encoding_alias(st_data_t name, st_data_t orig, st_data_t arg)
{
    rb_encoding *enc = rb_enc_from_index((int)orig);
    set_encoding_const((const char *)name, enc);
    return ST_CONTINUE;
}

/*
 * call-seq:
 *   Encoding.name_list => ["enc1", "enc2", ...]
 *
 * Returns the list of available encoding names.
 *
 *   Encoding.name_list
 *   => ["US-ASCII", "ASCII-8BIT", "UTF-8",
 *       "ISO-8859-1", "Shift_JIS", "EUC-JP",
 *       "Windows-31J",
 *       "BINARY", "CP932", "eucJP"]
 *
 * This list doesn't include dummy encodings.
 *
 */

static VALUE
rb_enc_name_list(VALUE klass)
{
    VALUE ary = rb_ary_new2(enc_name_list_size);
    int i;
    for (i = 0; i < enc_name_list_size; i++) {
	rb_ary_push(ary, rb_str_new2(enc_name_list[i]));
    }
    return ary;
}

static int
rb_enc_aliases_enc_i(st_data_t name, st_data_t orig, st_data_t arg)
{
    rb_hash_aset((VALUE)arg, rb_str_new2((char *)name), rb_str_new2(rb_enc_name(rb_enc_from_index((int)orig))));
    return 0;
}

static int
rb_enc_aliases_str_i(st_data_t name, st_data_t orig, st_data_t arg)
{
    rb_hash_aset((VALUE)arg, rb_str_new2((char *)name), rb_str_new2((char *)orig));
    return 0;
}

/*
 * call-seq:
 *   Encoding.aliases => {"alias1" => "orig1", "alias2" => "orig2", ...}
 *
 * Returns the hash of available encoding alias and original encoding name.
 *
 *   Encoding.aliases
 *   => {"BINARY"=>"ASCII-8BIT", "ASCII"=>"US-ASCII", "ANSI_X3.4-1986"=>"US-ASCII",
 *       "SJIS"=>"Shift_JIS", "eucJP"=>"EUC-JP", "CP932"=>"Windows-31J"}
 *
 */

static VALUE
rb_enc_aliases(VALUE klass)
{
    VALUE aliases = rb_hash_new();
    if (enc_table.alias) st_foreach(enc_table.alias, rb_enc_aliases_enc_i, (st_data_t)aliases);
    st_foreach(enc_table.alias_name, rb_enc_aliases_str_i, (st_data_t)aliases);
    return aliases;
}

void
Init_Encoding(void)
{
    id_base_encoding = rb_intern("#base_encoding");

    enc_table.replica_name = st_init_strcasetable();
    enc_table.alias_name = st_init_strcasetable();

    rb_cEncoding = rb_define_class("Encoding", rb_cObject);
    rb_undef_alloc_func(rb_cEncoding);
    rb_define_method(rb_cEncoding, "to_s", enc_name, 0);
    rb_define_method(rb_cEncoding, "inspect", enc_inspect, 0);
    rb_define_method(rb_cEncoding, "name", enc_name, 0);
    rb_define_method(rb_cEncoding, "base_encoding", enc_base_encoding, 0);
    rb_define_method(rb_cEncoding, "dummy?", enc_dummy_p, 0);
    rb_define_singleton_method(rb_cEncoding, "list", enc_list, 0);
    rb_define_singleton_method(rb_cEncoding, "name_list", rb_enc_name_list, 0);
    rb_define_singleton_method(rb_cEncoding, "aliases", rb_enc_aliases, 0);
    rb_define_singleton_method(rb_cEncoding, "find", enc_find, 1);
    rb_define_singleton_method(rb_cEncoding, "compatible?", enc_compatible_p, 2);

    rb_define_method(rb_cEncoding, "_dump", enc_dump, -1);
    rb_define_singleton_method(rb_cEncoding, "_load", enc_load, 1);

    rb_define_singleton_method(rb_cEncoding, "default_external", get_default_external, 0);
    rb_define_singleton_method(rb_cEncoding, "locale_charmap", rb_locale_charmap, 0);

    enc_init_db();

    /* dummy for unsupported, statefull encoding */
    rb_define_dummy_encoding("ISO-2022-JP");
    rb_enc_alias("ISO2022-JP", "ISO-2022-JP");
    rb_define_dummy_encoding("ISO-2022-JP-2");
    rb_enc_alias("ISO2022-JP2", "ISO-2022-JP-2");
}

/* locale insensitive functions */

#define ctype_test(c, ctype) \
    (rb_isascii(c) && ONIGENC_IS_ASCII_CODE_CTYPE((c), ctype))

int rb_isalnum(int c) { return ctype_test(c, ONIGENC_CTYPE_ALNUM); }
int rb_isalpha(int c) { return ctype_test(c, ONIGENC_CTYPE_ALPHA); }
int rb_isblank(int c) { return ctype_test(c, ONIGENC_CTYPE_BLANK); }
int rb_iscntrl(int c) { return ctype_test(c, ONIGENC_CTYPE_CNTRL); }
int rb_isdigit(int c) { return ctype_test(c, ONIGENC_CTYPE_DIGIT); }
int rb_isgraph(int c) { return ctype_test(c, ONIGENC_CTYPE_GRAPH); }
int rb_islower(int c) { return ctype_test(c, ONIGENC_CTYPE_LOWER); }
int rb_isprint(int c) { return ctype_test(c, ONIGENC_CTYPE_PRINT); }
int rb_ispunct(int c) { return ctype_test(c, ONIGENC_CTYPE_PUNCT); }
int rb_isspace(int c) { return ctype_test(c, ONIGENC_CTYPE_SPACE); }
int rb_isupper(int c) { return ctype_test(c, ONIGENC_CTYPE_UPPER); }
int rb_isxdigit(int c) { return ctype_test(c, ONIGENC_CTYPE_XDIGIT); }

int
rb_tolower(int c)
{
    return rb_isascii(c) ? ONIGENC_ASCII_CODE_TO_LOWER_CASE(c) : c;
}

int
rb_toupper(int c)
{
    return rb_isascii(c) ? ONIGENC_ASCII_CODE_TO_UPPER_CASE(c) : c;
}

