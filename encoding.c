/**********************************************************************

  encoding.c -

  $Author$
  created at: Thu May 24 17:23:27 JST 2007

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/encoding.h"
#include "internal.h"
#include "encindex.h"
#include "regenc.h"
#include <ctype.h>
#include "ruby/util.h"

#include "ruby_assert.h"
#ifndef ENC_DEBUG
#define ENC_DEBUG 0
#endif
#define ENC_ASSERT(expr) RUBY_ASSERT_WHEN(ENC_DEBUG, expr)
#define MUST_STRING(str) (ENC_ASSERT(RB_TYPE_P(str, T_STRING)), str)

#undef rb_ascii8bit_encindex
#undef rb_utf8_encindex
#undef rb_usascii_encindex

typedef OnigEncodingType rb_raw_encoding;

#if defined __GNUC__ && __GNUC__ >= 4
#pragma GCC visibility push(default)
int rb_enc_register(const char *name, rb_encoding *encoding);
void rb_enc_set_base(const char *name, const char *orig);
int rb_enc_set_dummy(int index);
void rb_encdb_declare(const char *name);
int rb_encdb_replicate(const char *name, const char *orig);
int rb_encdb_dummy(const char *name);
int rb_encdb_alias(const char *alias, const char *orig);
void rb_encdb_set_unicode(int index);
#pragma GCC visibility pop
#endif

static ID id_encoding;
VALUE rb_cEncoding;
static VALUE rb_encoding_list;

struct rb_encoding_entry {
    const char *name;
    rb_encoding *enc;
    rb_encoding *base;
};

static struct {
    struct rb_encoding_entry *list;
    int count;
    int size;
    st_table *names;
} enc_table;

#define ENC_DUMMY_FLAG (1<<24)
#define ENC_INDEX_MASK (~(~0U<<24))

#define ENC_TO_ENCINDEX(enc) (int)((enc)->ruby_encoding_index & ENC_INDEX_MASK)
#define ENC_DUMMY_P(enc) ((enc)->ruby_encoding_index & ENC_DUMMY_FLAG)
#define ENC_SET_DUMMY(enc) ((enc)->ruby_encoding_index |= ENC_DUMMY_FLAG)

#define ENCODING_COUNT ENCINDEX_BUILTIN_MAX
#define UNSPECIFIED_ENCODING INT_MAX

#define ENCODING_NAMELEN_MAX 63
#define valid_encoding_name_p(name) ((name) && strlen(name) <= ENCODING_NAMELEN_MAX)

#define enc_autoload_p(enc) (!rb_enc_mbmaxlen(enc))

static int load_encoding(const char *name);

static const rb_data_type_t encoding_data_type = {
    "encoding",
    {0, 0, 0,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#define is_data_encoding(obj) (RTYPEDDATA_P(obj) && RTYPEDDATA_TYPE(obj) == &encoding_data_type)
#define is_obj_encoding(obj) (RB_TYPE_P((obj), T_DATA) && is_data_encoding(obj))

int
rb_data_is_encoding(VALUE obj)
{
    return is_data_encoding(obj);
}

static VALUE
enc_new(rb_encoding *encoding)
{
    return TypedData_Wrap_Struct(rb_cEncoding, &encoding_data_type, (void *)encoding);
}

static VALUE
rb_enc_from_encoding_index(int idx)
{
    VALUE list, enc;

    if (!(list = rb_encoding_list)) {
	rb_bug("rb_enc_from_encoding_index(%d): no rb_encoding_list", idx);
    }
    enc = rb_ary_entry(list, idx);
    if (NIL_P(enc)) {
	rb_bug("rb_enc_from_encoding_index(%d): not created yet", idx);
    }
    return enc;
}

VALUE
rb_enc_from_encoding(rb_encoding *encoding)
{
    int idx;
    if (!encoding) return Qnil;
    idx = ENC_TO_ENCINDEX(encoding);
    return rb_enc_from_encoding_index(idx);
}

int
rb_enc_to_index(rb_encoding *enc)
{
    return enc ? ENC_TO_ENCINDEX(enc) : 0;
}

int
rb_enc_dummy_p(rb_encoding *enc)
{
    return ENC_DUMMY_P(enc) != 0;
}

static int enc_autoload(rb_encoding *);

static int
check_encoding(rb_encoding *enc)
{
    int index = rb_enc_to_index(enc);
    if (rb_enc_from_index(index) != enc)
	return -1;
    if (enc_autoload_p(enc)) {
	index = enc_autoload(enc);
    }
    return index;
}

static int
enc_check_encoding(VALUE obj)
{
    if (!is_obj_encoding(obj)) {
	return -1;
    }
    return check_encoding(RDATA(obj)->data);
}

NORETURN(static void not_encoding(VALUE enc));
static void
not_encoding(VALUE enc)
{
    rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected Encoding)",
	     rb_obj_class(enc));
}

static rb_encoding *
must_encoding(VALUE enc)
{
    int index = enc_check_encoding(enc);
    if (index < 0) {
	not_encoding(enc);
    }
    return DATA_PTR(enc);
}

static rb_encoding *
must_encindex(int index)
{
    rb_encoding *enc = rb_enc_from_index(index);
    if (!enc) {
	rb_raise(rb_eEncodingError, "encoding index out of bound: %d",
		 index);
    }
    if (ENC_TO_ENCINDEX(enc) != (int)(index & ENC_INDEX_MASK)) {
	rb_raise(rb_eEncodingError, "wrong encoding index %d for %s (expected %d)",
		 index, rb_enc_name(enc), ENC_TO_ENCINDEX(enc));
    }
    if (enc_autoload_p(enc) && enc_autoload(enc) == -1) {
	rb_loaderror("failed to load encoding (%s)",
		     rb_enc_name(enc));
    }
    return enc;
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
    if (!rb_enc_asciicompat(rb_enc_get(enc))) {
	return -1;
    }
    return rb_enc_find_index(StringValueCStr(enc));
}

/* Returns encoding index or UNSPECIFIED_ENCODING */
static int
str_find_encindex(VALUE enc)
{
    int idx;

    StringValue(enc);
    if (!rb_enc_asciicompat(rb_enc_get(enc))) {
	rb_raise(rb_eArgError, "invalid name encoding (non ASCII)");
    }
    idx = rb_enc_find_index(StringValueCStr(enc));
    return idx;
}

static int
str_to_encindex(VALUE enc)
{
    int idx = str_find_encindex(enc);
    if (idx < 0) {
	rb_raise(rb_eArgError, "unknown encoding name - %"PRIsVALUE, enc);
    }
    return idx;
}

static rb_encoding *
str_to_encoding(VALUE enc)
{
    return rb_enc_from_index(str_to_encindex(enc));
}

rb_encoding *
rb_to_encoding(VALUE enc)
{
    if (enc_check_encoding(enc) >= 0) return RDATA(enc)->data;
    return str_to_encoding(enc);
}

rb_encoding *
rb_find_encoding(VALUE enc)
{
    int idx;
    if (enc_check_encoding(enc) >= 0) return RDATA(enc)->data;
    idx = str_find_encindex(enc);
    if (idx < 0) return NULL;
    return rb_enc_from_index(idx);
}

static int
enc_table_expand(int newsize)
{
    struct rb_encoding_entry *ent;
    int count = newsize;

    if (enc_table.size >= newsize) return newsize;
    newsize = (newsize + 7) / 8 * 8;
    ent = REALLOC_N(enc_table.list, struct rb_encoding_entry, newsize);
    memset(ent + enc_table.size, 0, sizeof(*ent)*(newsize - enc_table.size));
    enc_table.list = ent;
    enc_table.size = newsize;
    return count;
}

static int
enc_register_at(int index, const char *name, rb_encoding *base_encoding)
{
    struct rb_encoding_entry *ent = &enc_table.list[index];
    rb_raw_encoding *encoding;
    VALUE list;

    if (!valid_encoding_name_p(name)) return -1;
    if (!ent->name) {
	ent->name = name = strdup(name);
    }
    else if (STRCASECMP(name, ent->name)) {
	return -1;
    }
    encoding = (rb_raw_encoding *)ent->enc;
    if (!encoding) {
	encoding = xmalloc(sizeof(rb_encoding));
    }
    if (base_encoding) {
	*encoding = *base_encoding;
    }
    else {
	memset(encoding, 0, sizeof(*ent->enc));
    }
    encoding->name = name;
    encoding->ruby_encoding_index = index;
    ent->enc = encoding;
    st_insert(enc_table.names, (st_data_t)name, (st_data_t)index);
    list = rb_encoding_list;
    if (list && NIL_P(rb_ary_entry(list, index))) {
	/* initialize encoding data */
	rb_ary_store(list, index, enc_new(encoding));
    }
    return index;
}

static int
enc_register(const char *name, rb_encoding *encoding)
{
    int index = enc_table.count;

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
	    index = enc_register(name, encoding);
	}
	else if (enc_autoload_p(oldenc) || !ENC_DUMMY_P(oldenc)) {
	    enc_register_at(index, name, encoding);
	}
	else {
	    rb_raise(rb_eArgError, "encoding %s is already registered", name);
	}
    }
    else {
	index = enc_register(name, encoding);
	set_encoding_const(name, rb_enc_from_index(index));
    }
    return index;
}

void
rb_encdb_declare(const char *name)
{
    int idx = rb_enc_registered(name);
    if (idx < 0) {
	idx = enc_register(name, 0);
    }
    set_encoding_const(name, rb_enc_from_index(idx));
}

static void
enc_check_duplication(const char *name)
{
    if (rb_enc_registered(name) >= 0) {
	rb_raise(rb_eArgError, "encoding %s is already registered", name);
    }
}

static rb_encoding*
set_base_encoding(int index, rb_encoding *base)
{
    rb_encoding *enc = enc_table.list[index].enc;

    enc_table.list[index].base = base;
    if (ENC_DUMMY_P(base)) ENC_SET_DUMMY((rb_raw_encoding *)enc);
    return enc;
}

/* for encdb.h
 * Set base encoding for encodings which are not replicas
 * but not in their own files.
 */
void
rb_enc_set_base(const char *name, const char *orig)
{
    int idx = rb_enc_registered(name);
    int origidx = rb_enc_registered(orig);
    set_base_encoding(idx, rb_enc_from_index(origidx));
}

/* for encdb.h
 * Set encoding dummy.
 */
int
rb_enc_set_dummy(int index)
{
    rb_encoding *enc = enc_table.list[index].enc;

    ENC_SET_DUMMY((rb_raw_encoding *)enc);
    return index;
}

int
rb_enc_replicate(const char *name, rb_encoding *encoding)
{
    int idx;

    enc_check_duplication(name);
    idx = enc_register(name, encoding);
    set_base_encoding(idx, encoding);
    set_encoding_const(name, rb_enc_from_index(idx));
    return idx;
}

/*
 * call-seq:
 *   enc.replicate(name) -> encoding
 *
 * Returns a replicated encoding of _enc_ whose name is _name_.
 * The new encoding should have the same byte structure of _enc_.
 * If _name_ is used by another encoding, raise ArgumentError.
 *
 */
static VALUE
enc_replicate(VALUE encoding, VALUE name)
{
    return rb_enc_from_encoding_index(
	rb_enc_replicate(StringValueCStr(name),
			 rb_to_encoding(encoding)));
}

static int
enc_replicate_with_index(const char *name, rb_encoding *origenc, int idx)
{
    if (idx < 0) {
	idx = enc_register(name, origenc);
    }
    else {
	idx = enc_register_at(idx, name, origenc);
    }
    if (idx >= 0) {
	set_base_encoding(idx, origenc);
	set_encoding_const(name, rb_enc_from_index(idx));
    }
    else {
        rb_raise(rb_eArgError, "failed to replicate encoding");
    }
    return idx;
}

int
rb_encdb_replicate(const char *name, const char *orig)
{
    int origidx = rb_enc_registered(orig);
    int idx = rb_enc_registered(name);

    if (origidx < 0) {
	origidx = enc_register(orig, 0);
    }
    return enc_replicate_with_index(name, rb_enc_from_index(origidx), idx);
}

int
rb_define_dummy_encoding(const char *name)
{
    int index = rb_enc_replicate(name, rb_ascii8bit_encoding());
    rb_encoding *enc = enc_table.list[index].enc;

    ENC_SET_DUMMY((rb_raw_encoding *)enc);
    return index;
}

int
rb_encdb_dummy(const char *name)
{
    int index = enc_replicate_with_index(name, rb_ascii8bit_encoding(),
					 rb_enc_registered(name));
    rb_encoding *enc = enc_table.list[index].enc;

    ENC_SET_DUMMY((rb_raw_encoding *)enc);
    return index;
}

/*
 * call-seq:
 *   enc.dummy? -> true or false
 *
 * Returns true for dummy encodings.
 * A dummy encoding is an encoding for which character handling is not properly
 * implemented.
 * It is used for stateful encodings.
 *
 *   Encoding::ISO_2022_JP.dummy?       #=> true
 *   Encoding::UTF_8.dummy?             #=> false
 *
 */
static VALUE
enc_dummy_p(VALUE enc)
{
    return ENC_DUMMY_P(must_encoding(enc)) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   enc.ascii_compatible? -> true or false
 *
 * Returns whether ASCII-compatible or not.
 *
 *   Encoding::UTF_8.ascii_compatible?     #=> true
 *   Encoding::UTF_16BE.ascii_compatible?  #=> false
 *
 */
static VALUE
enc_ascii_compatible_p(VALUE enc)
{
    return rb_enc_asciicompat(must_encoding(enc)) ? Qtrue : Qfalse;
}

/*
 * Returns non-zero when the encoding is Unicode series other than UTF-7 else 0.
 */
int
rb_enc_unicode_p(rb_encoding *enc)
{
    return ONIGENC_IS_UNICODE(enc);
}

static st_data_t
enc_dup_name(st_data_t name)
{
    return (st_data_t)strdup((const char *)name);
}

/*
 * Returns copied alias name when the key is added for st_table,
 * else returns NULL.
 */
static int
enc_alias_internal(const char *alias, int idx)
{
    return st_insert2(enc_table.names, (st_data_t)alias, (st_data_t)idx,
		      enc_dup_name);
}

static int
enc_alias(const char *alias, int idx)
{
    if (!valid_encoding_name_p(alias)) return -1;
    if (!enc_alias_internal(alias, idx))
	set_encoding_const(alias, rb_enc_from_index(idx));
    return idx;
}

int
rb_enc_alias(const char *alias, const char *orig)
{
    int idx;

    enc_check_duplication(alias);
    if ((idx = rb_enc_find_index(orig)) < 0) {
	return -1;
    }
    return enc_alias(alias, idx);
}

int
rb_encdb_alias(const char *alias, const char *orig)
{
    int idx = rb_enc_registered(orig);

    if (idx < 0) {
	idx = enc_register(orig, 0);
    }
    return enc_alias(alias, idx);
}

void
rb_encdb_set_unicode(int index)
{
    ((rb_raw_encoding *)rb_enc_from_index(index))->flags |= ONIGENC_FLAG_UNICODE;
}

void
rb_enc_init(void)
{
    enc_table_expand(ENCODING_COUNT + 1);
    if (!enc_table.names) {
	enc_table.names = st_init_strcasetable();
    }
#define ENC_REGISTER(enc) enc_register_at(ENCINDEX_##enc, rb_enc_name(&OnigEncoding##enc), &OnigEncoding##enc)
    ENC_REGISTER(ASCII);
    ENC_REGISTER(UTF_8);
    ENC_REGISTER(US_ASCII);
#undef ENC_REGISTER
#define ENCDB_REGISTER(name, enc) enc_register_at(ENCINDEX_##enc, name, NULL)
    ENCDB_REGISTER("UTF-16BE", UTF_16BE);
    ENCDB_REGISTER("UTF-16LE", UTF_16LE);
    ENCDB_REGISTER("UTF-32BE", UTF_32BE);
    ENCDB_REGISTER("UTF-32LE", UTF_32LE);
    ENCDB_REGISTER("UTF-16", UTF_16);
    ENCDB_REGISTER("UTF-32", UTF_32);
    ENCDB_REGISTER("UTF8-MAC", UTF8_MAC);

    ENCDB_REGISTER("EUC-JP", EUC_JP);
    ENCDB_REGISTER("Windows-31J", Windows_31J);
#undef ENCDB_REGISTER
    enc_table.count = ENCINDEX_BUILTIN_MAX;
}

rb_encoding *
rb_enc_from_index(int index)
{
    if (UNLIKELY(index < 0 || enc_table.count <= (index &= ENC_INDEX_MASK))) {
	return 0;
    }
    return enc_table.list[index].enc;
}

rb_encoding *
rb_enc_get_from_index(int index)
{
    return must_encindex(index);
}

int
rb_enc_registered(const char *name)
{
    st_data_t idx = 0;

    if (!name) return -1;
    if (!enc_table.list) return -1;
    if (st_lookup(enc_table.names, (st_data_t)name, &idx)) {
	return (int)idx;
    }
    return -1;
}

static int
load_encoding(const char *name)
{
    VALUE enclib = rb_sprintf("enc/%s.so", name);
    VALUE verbose = ruby_verbose;
    VALUE debug = ruby_debug;
    VALUE errinfo;
    char *s = RSTRING_PTR(enclib) + 4, *e = RSTRING_END(enclib) - 3;
    int loaded;
    int idx;

    while (s < e) {
	if (!ISALNUM(*s)) *s = '_';
	else if (ISUPPER(*s)) *s = (char)TOLOWER(*s);
	++s;
    }
    FL_UNSET(enclib, FL_TAINT);
    enclib = rb_fstring(enclib);
    ruby_verbose = Qfalse;
    ruby_debug = Qfalse;
    errinfo = rb_errinfo();
    loaded = rb_require_internal(enclib, rb_safe_level());
    ruby_verbose = verbose;
    ruby_debug = debug;
    rb_set_errinfo(errinfo);
    if (loaded < 0 || 1 < loaded) return -1;
    if ((idx = rb_enc_registered(name)) < 0) return -1;
    if (enc_autoload_p(enc_table.list[idx].enc)) return -1;
    return idx;
}

static int
enc_autoload(rb_encoding *enc)
{
    int i;
    rb_encoding *base = enc_table.list[ENC_TO_ENCINDEX(enc)].base;

    if (base) {
	i = 0;
	do {
	    if (i >= enc_table.count) return -1;
	} while (enc_table.list[i].enc != base && (++i, 1));
	if (enc_autoload_p(base)) {
	    if (enc_autoload(base) < 0) return -1;
	}
	i = enc->ruby_encoding_index;
	enc_register_at(i & ENC_INDEX_MASK, rb_enc_name(enc), base);
	((rb_raw_encoding *)enc)->ruby_encoding_index = i;
	i &= ENC_INDEX_MASK;
    }
    else {
	i = load_encoding(rb_enc_name(enc));
    }
    return i;
}

/* Return encoding index or UNSPECIFIED_ENCODING from encoding name */
int
rb_enc_find_index(const char *name)
{
    int i = rb_enc_registered(name);
    rb_encoding *enc;

    if (i < 0) {
	i = load_encoding(name);
    }
    else if (!(enc = rb_enc_from_index(i))) {
	if (i != UNSPECIFIED_ENCODING) {
	    rb_raise(rb_eArgError, "encoding %s is not registered", name);
	}
    }
    else if (enc_autoload_p(enc)) {
	if (enc_autoload(enc) < 0) {
	    rb_warn("failed to load encoding (%s); use ASCII-8BIT instead",
		    name);
	    return 0;
	}
    }
    return i;
}

int
rb_enc_find_index2(const char *name, long len)
{
    char buf[ENCODING_NAMELEN_MAX+1];

    if (len > ENCODING_NAMELEN_MAX) return -1;
    memcpy(buf, name, len);
    buf[len] = '\0';
    return rb_enc_find_index(buf);
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
    if (SPECIAL_CONST_P(obj)) return SYMBOL_P(obj);
    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
      case T_REGEXP:
      case T_FILE:
      case T_SYMBOL:
	return TRUE;
      case T_DATA:
	if (is_data_encoding(obj)) return TRUE;
      default:
	return FALSE;
    }
}

int
rb_enc_capable(VALUE obj)
{
    return enc_capable(obj);
}

ID
rb_id_encoding(void)
{
    CONST_ID(id_encoding, "encoding");
    return id_encoding;
}

static int
enc_get_index_str(VALUE str)
{
    int i = ENCODING_GET_INLINED(str);
    if (i == ENCODING_INLINE_MAX) {
	VALUE iv;

	iv = rb_ivar_get(str, rb_id_encoding());
	i = NUM2INT(iv);
    }
    return i;
}

int
rb_enc_get_index(VALUE obj)
{
    int i = -1;
    VALUE tmp;

    if (SPECIAL_CONST_P(obj)) {
	if (!SYMBOL_P(obj)) return -1;
	obj = rb_sym2str(obj);
    }
    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
      case T_SYMBOL:
      case T_REGEXP:
	i = enc_get_index_str(obj);
	break;
      case T_FILE:
	tmp = rb_funcallv(obj, rb_intern("internal_encoding"), 0, 0);
	if (NIL_P(tmp)) {
	    tmp = rb_funcallv(obj, rb_intern("external_encoding"), 0, 0);
	}
	if (is_obj_encoding(tmp)) {
	    i = enc_check_encoding(tmp);
	}
	break;
      case T_DATA:
	if (is_data_encoding(obj)) {
	    i = enc_check_encoding(obj);
	}
	break;
      default:
	break;
    }
    return i;
}

static void
enc_set_index(VALUE obj, int idx)
{
    if (!enc_capable(obj)) {
        rb_raise(rb_eArgError, "cannot set encoding on non-encoding capable object");
    }

    if (idx < ENCODING_INLINE_MAX) {
	ENCODING_SET_INLINED(obj, idx);
	return;
    }
    ENCODING_SET_INLINED(obj, ENCODING_INLINE_MAX);
    rb_ivar_set(obj, rb_id_encoding(), INT2NUM(idx));
}

void
rb_enc_set_index(VALUE obj, int idx)
{
    rb_check_frozen(obj);
    must_encindex(idx);
    enc_set_index(obj, idx);
}

VALUE
rb_enc_associate_index(VALUE obj, int idx)
{
    rb_encoding *enc;
    int oldidx, oldtermlen, termlen;

/*    enc_check_capable(obj);*/
    rb_check_frozen(obj);
    oldidx = rb_enc_get_index(obj);
    if (oldidx == idx)
	return obj;
    if (SPECIAL_CONST_P(obj)) {
	rb_raise(rb_eArgError, "cannot set encoding");
    }
    enc = must_encindex(idx);
    if (!ENC_CODERANGE_ASCIIONLY(obj) ||
	!rb_enc_asciicompat(enc)) {
	ENC_CODERANGE_CLEAR(obj);
    }
    termlen = rb_enc_mbminlen(enc);
    oldtermlen = rb_enc_mbminlen(rb_enc_from_index(oldidx));
    if (oldtermlen != termlen && RB_TYPE_P(obj, T_STRING)) {
	rb_str_change_terminator_length(obj, oldtermlen, termlen);
    }
    enc_set_index(obj, idx);
    return obj;
}

VALUE
rb_enc_associate(VALUE obj, rb_encoding *enc)
{
    return rb_enc_associate_index(obj, rb_enc_to_index(enc));
}

rb_encoding*
rb_enc_get(VALUE obj)
{
    return rb_enc_from_index(rb_enc_get_index(obj));
}

static rb_encoding* enc_compatible_str(VALUE str1, VALUE str2);

rb_encoding*
rb_enc_check_str(VALUE str1, VALUE str2)
{
    rb_encoding *enc = enc_compatible_str(MUST_STRING(str1), MUST_STRING(str2));
    if (!enc)
	rb_raise(rb_eEncCompatError, "incompatible character encodings: %s and %s",
		 rb_enc_name(rb_enc_get(str1)),
		 rb_enc_name(rb_enc_get(str2)));
    return enc;
}

rb_encoding*
rb_enc_check(VALUE str1, VALUE str2)
{
    rb_encoding *enc = rb_enc_compatible(str1, str2);
    if (!enc)
	rb_raise(rb_eEncCompatError, "incompatible character encodings: %s and %s",
		 rb_enc_name(rb_enc_get(str1)),
		 rb_enc_name(rb_enc_get(str2)));
    return enc;
}

static rb_encoding*
enc_compatible_latter(VALUE str1, VALUE str2, int idx1, int idx2)
{
    int isstr1, isstr2;
    rb_encoding *enc1 = rb_enc_from_index(idx1);
    rb_encoding *enc2 = rb_enc_from_index(idx2);

    isstr2 = RB_TYPE_P(str2, T_STRING);
    if (isstr2 && RSTRING_LEN(str2) == 0)
	return enc1;
    isstr1 = RB_TYPE_P(str1, T_STRING);
    if (isstr1 && RSTRING_LEN(str1) == 0)
	return (rb_enc_asciicompat(enc1) && rb_enc_str_asciionly_p(str2)) ? enc1 : enc2;
    if (!rb_enc_asciicompat(enc1) || !rb_enc_asciicompat(enc2)) {
	return 0;
    }

    /* objects whose encoding is the same of contents */
    if (!isstr2 && idx2 == ENCINDEX_US_ASCII)
	return enc1;
    if (!isstr1 && idx1 == ENCINDEX_US_ASCII)
	return enc2;

    if (!isstr1) {
	VALUE tmp = str1;
	int idx0 = idx1;
	str1 = str2;
	str2 = tmp;
	idx1 = idx2;
	idx2 = idx0;
	idx0 = isstr1;
	isstr1 = isstr2;
	isstr2 = idx0;
    }
    if (isstr1) {
	int cr1, cr2;

	cr1 = rb_enc_str_coderange(str1);
	if (isstr2) {
	    cr2 = rb_enc_str_coderange(str2);
	    if (cr1 != cr2) {
		/* may need to handle ENC_CODERANGE_BROKEN */
		if (cr1 == ENC_CODERANGE_7BIT) return enc2;
		if (cr2 == ENC_CODERANGE_7BIT) return enc1;
	    }
	    if (cr2 == ENC_CODERANGE_7BIT) {
		return enc1;
	    }
	}
	if (cr1 == ENC_CODERANGE_7BIT)
	    return enc2;
    }
    return 0;
}

static rb_encoding*
enc_compatible_str(VALUE str1, VALUE str2)
{
    int idx1 = enc_get_index_str(str1);
    int idx2 = enc_get_index_str(str2);

    if (idx1 < 0 || idx2 < 0)
        return 0;

    if (idx1 == idx2) {
	return rb_enc_from_index(idx1);
    }
    else {
	return enc_compatible_latter(str1, str2, idx1, idx2);
    }
}

rb_encoding*
rb_enc_compatible(VALUE str1, VALUE str2)
{
    int idx1 = rb_enc_get_index(str1);
    int idx2 = rb_enc_get_index(str2);

    if (idx1 < 0 || idx2 < 0)
        return 0;

    if (idx1 == idx2) {
	return rb_enc_from_index(idx1);
    }

    return enc_compatible_latter(str1, str2, idx1, idx2);
}

void
rb_enc_copy(VALUE obj1, VALUE obj2)
{
    rb_enc_associate_index(obj1, rb_enc_get_index(obj2));
}


/*
 *  call-seq:
 *     obj.encoding   -> encoding
 *
 *  Returns the Encoding object that represents the encoding of obj.
 */

VALUE
rb_obj_encoding(VALUE obj)
{
    int idx = rb_enc_get_index(obj);
    if (idx < 0) {
	rb_raise(rb_eTypeError, "unknown encoding");
    }
    return rb_enc_from_encoding_index(idx & ENC_INDEX_MASK);
}

int
rb_enc_fast_mbclen(const char *p, const char *e, rb_encoding *enc)
{
    return ONIGENC_MBC_ENC_LEN(enc, (UChar*)p, (UChar*)e);
}

int
rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc)
{
    int n = ONIGENC_PRECISE_MBC_ENC_LEN(enc, (UChar*)p, (UChar*)e);
    if (MBCLEN_CHARFOUND_P(n) && MBCLEN_CHARFOUND_LEN(n) <= e-p)
        return MBCLEN_CHARFOUND_LEN(n);
    else {
        int min = rb_enc_mbminlen(enc);
        return min <= e-p ? min : (int)(e-p);
    }
}

int
rb_enc_precise_mbclen(const char *p, const char *e, rb_encoding *enc)
{
    int n;
    if (e <= p)
        return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(1);
    n = ONIGENC_PRECISE_MBC_ENC_LEN(enc, (UChar*)p, (UChar*)e);
    if (e-p < n)
        return ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(n-(int)(e-p));
    return n;
}

int
rb_enc_ascget(const char *p, const char *e, int *len, rb_encoding *enc)
{
    unsigned int c;
    int l;
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
    if (!MBCLEN_CHARFOUND_P(l))
        return -1;
    c = rb_enc_mbc_to_codepoint(p, e, enc);
    if (!rb_enc_isascii(c, enc))
        return -1;
    if (len) *len = l;
    return c;
}

unsigned int
rb_enc_codepoint_len(const char *p, const char *e, int *len_p, rb_encoding *enc)
{
    int r;
    if (e <= p)
        rb_raise(rb_eArgError, "empty string");
    r = rb_enc_precise_mbclen(p, e, enc);
    if (!MBCLEN_CHARFOUND_P(r)) {
	rb_raise(rb_eArgError, "invalid byte sequence in %s", rb_enc_name(enc));
    }
    if (len_p) *len_p = MBCLEN_CHARFOUND_LEN(r);
    return rb_enc_mbc_to_codepoint(p, e, enc);
}

#undef rb_enc_codepoint
unsigned int
rb_enc_codepoint(const char *p, const char *e, rb_encoding *enc)
{
    return rb_enc_codepoint_len(p, e, 0, enc);
}

int
rb_enc_codelen(int c, rb_encoding *enc)
{
    int n = ONIGENC_CODE_TO_MBCLEN(enc,c);
    if (n == 0) {
	rb_raise(rb_eArgError, "invalid codepoint 0x%x in %s", c, rb_enc_name(enc));
    }
    return n;
}

#undef rb_enc_code_to_mbclen
int
rb_enc_code_to_mbclen(int code, rb_encoding *enc)
{
    return ONIGENC_CODE_TO_MBCLEN(enc, code);
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
 *   enc.inspect -> string
 *
 * Returns a string which represents the encoding for programmers.
 *
 *   Encoding::UTF_8.inspect       #=> "#<Encoding:UTF-8>"
 *   Encoding::ISO_2022_JP.inspect #=> "#<Encoding:ISO-2022-JP (dummy)>"
 */
static VALUE
enc_inspect(VALUE self)
{
    rb_encoding *enc;

    if (!is_data_encoding(self)) {
	not_encoding(self);
    }
    if (!(enc = DATA_PTR(self)) || rb_enc_from_index(rb_enc_to_index(enc)) != enc) {
	rb_raise(rb_eTypeError, "broken Encoding");
    }
    return rb_enc_sprintf(rb_usascii_encoding(),
			  "#<%"PRIsVALUE":%s%s%s>", rb_obj_class(self),
			  rb_enc_name(enc),
			  (ENC_DUMMY_P(enc) ? " (dummy)" : ""),
			  enc_autoload_p(enc) ? " (autoload)" : "");
}

/*
 * call-seq:
 *   enc.name -> string
 *   enc.to_s -> string
 *
 * Returns the name of the encoding.
 *
 *   Encoding::UTF_8.name      #=> "UTF-8"
 */
static VALUE
enc_name(VALUE self)
{
    return rb_fstring_cstr(rb_enc_name((rb_encoding*)DATA_PTR(self)));
}

static int
enc_names_i(st_data_t name, st_data_t idx, st_data_t args)
{
    VALUE *arg = (VALUE *)args;

    if ((int)idx == (int)arg[0]) {
	VALUE str = rb_fstring_cstr((char *)name);
	rb_ary_push(arg[1], str);
    }
    return ST_CONTINUE;
}

/*
 * call-seq:
 *   enc.names -> array
 *
 * Returns the list of name and aliases of the encoding.
 *
 *   Encoding::WINDOWS_31J.names  #=> ["Windows-31J", "CP932", "csWindows31J"]
 */
static VALUE
enc_names(VALUE self)
{
    VALUE args[2];

    args[0] = (VALUE)rb_to_encoding_index(self);
    args[1] = rb_ary_new2(0);
    st_foreach(enc_table.names, enc_names_i, (st_data_t)args);
    return args[1];
}

/*
 * call-seq:
 *   Encoding.list -> [enc1, enc2, ...]
 *
 * Returns the list of loaded encodings.
 *
 *   Encoding.list
 *   #=> [#<Encoding:ASCII-8BIT>, #<Encoding:UTF-8>,
 *         #<Encoding:ISO-2022-JP (dummy)>]
 *
 *   Encoding.find("US-ASCII")
 *   #=> #<Encoding:US-ASCII>
 *
 *   Encoding.list
 *   #=> [#<Encoding:ASCII-8BIT>, #<Encoding:UTF-8>,
 *         #<Encoding:US-ASCII>, #<Encoding:ISO-2022-JP (dummy)>]
 *
 */
static VALUE
enc_list(VALUE klass)
{
    VALUE ary = rb_ary_new2(0);
    rb_ary_replace(ary, rb_encoding_list);
    return ary;
}

/*
 * call-seq:
 *   Encoding.find(string) -> enc
 *
 * Search the encoding with specified <i>name</i>.
 * <i>name</i> should be a string.
 *
 *   Encoding.find("US-ASCII")  #=> #<Encoding:US-ASCII>
 *
 * Names which this method accept are encoding names and aliases
 * including following special aliases
 *
 * "external"::   default external encoding
 * "internal"::   default internal encoding
 * "locale"::     locale encoding
 * "filesystem":: filesystem encoding
 *
 * An ArgumentError is raised when no encoding with <i>name</i>.
 * Only <code>Encoding.find("internal")</code> however returns nil
 * when no encoding named "internal", in other words, when Ruby has no
 * default internal encoding.
 */
static VALUE
enc_find(VALUE klass, VALUE enc)
{
    int idx;
    if (is_obj_encoding(enc))
	return enc;
    idx = str_to_encindex(enc);
    if (idx == UNSPECIFIED_ENCODING) return Qnil;
    return rb_enc_from_encoding_index(idx);
}

/*
 * call-seq:
 *   Encoding.compatible?(obj1, obj2) -> enc or nil
 *
 * Checks the compatibility of two objects.
 *
 * If the objects are both strings they are compatible when they are
 * concatenatable.  The encoding of the concatenated string will be returned
 * if they are compatible, nil if they are not.
 *
 *   Encoding.compatible?("\xa1".force_encoding("iso-8859-1"), "b")
 *   #=> #<Encoding:ISO-8859-1>
 *
 *   Encoding.compatible?(
 *     "\xa1".force_encoding("iso-8859-1"),
 *     "\xa1\xa1".force_encoding("euc-jp"))
 *   #=> nil
 *
 * If the objects are non-strings their encodings are compatible when they
 * have an encoding and:
 * * Either encoding is US-ASCII compatible
 * * One of the encodings is a 7-bit encoding
 *
 */
static VALUE
enc_compatible_p(VALUE klass, VALUE str1, VALUE str2)
{
    rb_encoding *enc;

    if (!enc_capable(str1)) return Qnil;
    if (!enc_capable(str2)) return Qnil;
    enc = rb_enc_compatible(str1, str2);
    if (!enc) return Qnil;
    return rb_enc_from_encoding(enc);
}

/* :nodoc: */
static VALUE
enc_s_alloc(VALUE klass)
{
    rb_undefined_alloc(klass);
    return Qnil;
}

/* :nodoc: */
static VALUE
enc_dump(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 1);
    return enc_name(self);
}

/* :nodoc: */
static VALUE
enc_load(VALUE klass, VALUE str)
{
    return str;
}

/* :nodoc: */
static VALUE
enc_m_loader(VALUE klass, VALUE str)
{
    return enc_find(klass, str);
}

rb_encoding *
rb_ascii8bit_encoding(void)
{
    return enc_table.list[ENCINDEX_ASCII].enc;
}

int
rb_ascii8bit_encindex(void)
{
    return ENCINDEX_ASCII;
}

rb_encoding *
rb_utf8_encoding(void)
{
    return enc_table.list[ENCINDEX_UTF_8].enc;
}

int
rb_utf8_encindex(void)
{
    return ENCINDEX_UTF_8;
}

rb_encoding *
rb_usascii_encoding(void)
{
    return enc_table.list[ENCINDEX_US_ASCII].enc;
}

int
rb_usascii_encindex(void)
{
    return ENCINDEX_US_ASCII;
}

int rb_locale_charmap_index(void);

int
rb_locale_encindex(void)
{
    int idx = rb_locale_charmap_index();

    if (idx < 0) idx = ENCINDEX_ASCII;

    if (rb_enc_registered("locale") < 0) {
# if defined _WIN32
	void Init_w32_codepage(void);
	Init_w32_codepage();
# endif
	enc_alias_internal("locale", idx);
    }

    return idx;
}

rb_encoding *
rb_locale_encoding(void)
{
    return rb_enc_from_index(rb_locale_encindex());
}

int
rb_filesystem_encindex(void)
{
    int idx = rb_enc_registered("filesystem");
    if (idx < 0)
	idx = ENCINDEX_ASCII;
    return idx;
}

rb_encoding *
rb_filesystem_encoding(void)
{
    return rb_enc_from_index(rb_filesystem_encindex());
}

struct default_encoding {
    int index;			/* -2 => not yet set, -1 => nil */
    rb_encoding *enc;
};

static struct default_encoding default_external = {0};

static int
enc_set_default_encoding(struct default_encoding *def, VALUE encoding, const char *name)
{
    int overridden = FALSE;

    if (def->index != -2)
	/* Already set */
	overridden = TRUE;

    if (NIL_P(encoding)) {
	def->index = -1;
	def->enc = 0;
	st_insert(enc_table.names, (st_data_t)strdup(name),
		  (st_data_t)UNSPECIFIED_ENCODING);
    }
    else {
	def->index = rb_enc_to_index(rb_to_encoding(encoding));
	def->enc = 0;
	enc_alias_internal(name, def->index);
    }

    if (def == &default_external)
	enc_alias_internal("filesystem", Init_enc_set_filesystem_encoding());

    return overridden;
}

rb_encoding *
rb_default_external_encoding(void)
{
    if (default_external.enc) return default_external.enc;

    if (default_external.index >= 0) {
        default_external.enc = rb_enc_from_index(default_external.index);
        return default_external.enc;
    }
    else {
        return rb_locale_encoding();
    }
}

VALUE
rb_enc_default_external(void)
{
    return rb_enc_from_encoding(rb_default_external_encoding());
}

/*
 * call-seq:
 *   Encoding.default_external -> enc
 *
 * Returns default external encoding.
 *
 * The default external encoding is used by default for strings created from
 * the following locations:
 *
 * * CSV
 * * File data read from disk
 * * SDBM
 * * StringIO
 * * Zlib::GzipReader
 * * Zlib::GzipWriter
 * * String#inspect
 * * Regexp#inspect
 *
 * While strings created from these locations will have this encoding, the
 * encoding may not be valid.  Be sure to check String#valid_encoding?.
 *
 * File data written to disk will be transcoded to the default external
 * encoding when written.
 *
 * The default external encoding is initialized by the locale or -E option.
 */
static VALUE
get_default_external(VALUE klass)
{
    return rb_enc_default_external();
}

void
rb_enc_set_default_external(VALUE encoding)
{
    if (NIL_P(encoding)) {
        rb_raise(rb_eArgError, "default external can not be nil");
    }
    enc_set_default_encoding(&default_external, encoding,
                            "external");
}

/*
 * call-seq:
 *   Encoding.default_external = enc
 *
 * Sets default external encoding.  You should not set
 * Encoding::default_external in ruby code as strings created before changing
 * the value may have a different encoding from strings created after the value
 * was changed., instead you should use <tt>ruby -E</tt> to invoke ruby with
 * the correct default_external.
 *
 * See Encoding::default_external for information on how the default external
 * encoding is used.
 */
static VALUE
set_default_external(VALUE klass, VALUE encoding)
{
    rb_warning("setting Encoding.default_external");
    rb_enc_set_default_external(encoding);
    return encoding;
}

static struct default_encoding default_internal = {-2};

rb_encoding *
rb_default_internal_encoding(void)
{
    if (!default_internal.enc && default_internal.index >= 0) {
        default_internal.enc = rb_enc_from_index(default_internal.index);
    }
    return default_internal.enc; /* can be NULL */
}

VALUE
rb_enc_default_internal(void)
{
    /* Note: These functions cope with default_internal not being set */
    return rb_enc_from_encoding(rb_default_internal_encoding());
}

/*
 * call-seq:
 *   Encoding.default_internal -> enc
 *
 * Returns default internal encoding.  Strings will be transcoded to the
 * default internal encoding in the following places if the default internal
 * encoding is not nil:
 *
 * * CSV
 * * Etc.sysconfdir and Etc.systmpdir
 * * File data read from disk
 * * File names from Dir
 * * Integer#chr
 * * String#inspect and Regexp#inspect
 * * Strings returned from Readline
 * * Strings returned from SDBM
 * * Time#zone
 * * Values from ENV
 * * Values in ARGV including $PROGRAM_NAME
 *
 * Additionally String#encode and String#encode! use the default internal
 * encoding if no encoding is given.
 *
 * The script encoding (__ENCODING__), not default_internal, is used as the
 * encoding of created strings.
 *
 * Encoding::default_internal is initialized by the source file's
 * internal_encoding or -E option.
 */
static VALUE
get_default_internal(VALUE klass)
{
    return rb_enc_default_internal();
}

void
rb_enc_set_default_internal(VALUE encoding)
{
    enc_set_default_encoding(&default_internal, encoding,
                            "internal");
}

/*
 * call-seq:
 *   Encoding.default_internal = enc or nil
 *
 * Sets default internal encoding or removes default internal encoding when
 * passed nil.  You should not set Encoding::default_internal in ruby code as
 * strings created before changing the value may have a different encoding
 * from strings created after the change.  Instead you should use
 * <tt>ruby -E</tt> to invoke ruby with the correct default_internal.
 *
 * See Encoding::default_internal for information on how the default internal
 * encoding is used.
 */
static VALUE
set_default_internal(VALUE klass, VALUE encoding)
{
    rb_warning("setting Encoding.default_internal");
    rb_enc_set_default_internal(encoding);
    return encoding;
}

static void
set_encoding_const(const char *name, rb_encoding *enc)
{
    VALUE encoding = rb_enc_from_encoding(enc);
    char *s = (char *)name;
    int haslower = 0, hasupper = 0, valid = 0;

    if (ISDIGIT(*s)) return;
    if (ISUPPER(*s)) {
	hasupper = 1;
	while (*++s && (ISALNUM(*s) || *s == '_')) {
	    if (ISLOWER(*s)) haslower = 1;
	}
    }
    if (!*s) {
	if (s - name > ENCODING_NAMELEN_MAX) return;
	valid = 1;
	rb_define_const(rb_cEncoding, name, encoding);
    }
    if (!valid || haslower) {
	size_t len = s - name;
	if (len > ENCODING_NAMELEN_MAX) return;
	if (!haslower || !hasupper) {
	    do {
		if (ISLOWER(*s)) haslower = 1;
		if (ISUPPER(*s)) hasupper = 1;
	    } while (*++s && (!haslower || !hasupper));
	    len = s - name;
	}
	len += strlen(s);
	if (len++ > ENCODING_NAMELEN_MAX) return;
	MEMCPY(s = ALLOCA_N(char, len), name, char, len);
	name = s;
	if (!valid) {
	    if (ISLOWER(*s)) *s = ONIGENC_ASCII_CODE_TO_UPPER_CASE((int)*s);
	    for (; *s; ++s) {
		if (!ISALNUM(*s)) *s = '_';
	    }
	    if (hasupper) {
		rb_define_const(rb_cEncoding, name, encoding);
	    }
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
rb_enc_name_list_i(st_data_t name, st_data_t idx, st_data_t arg)
{
    VALUE ary = (VALUE)arg;
    VALUE str = rb_fstring_cstr((char *)name);
    rb_ary_push(ary, str);
    return ST_CONTINUE;
}

/*
 * call-seq:
 *   Encoding.name_list -> ["enc1", "enc2", ...]
 *
 * Returns the list of available encoding names.
 *
 *   Encoding.name_list
 *   #=> ["US-ASCII", "ASCII-8BIT", "UTF-8",
 *         "ISO-8859-1", "Shift_JIS", "EUC-JP",
 *         "Windows-31J",
 *         "BINARY", "CP932", "eucJP"]
 *
 */

static VALUE
rb_enc_name_list(VALUE klass)
{
    VALUE ary = rb_ary_new2(enc_table.names->num_entries);
    st_foreach(enc_table.names, rb_enc_name_list_i, (st_data_t)ary);
    return ary;
}

static int
rb_enc_aliases_enc_i(st_data_t name, st_data_t orig, st_data_t arg)
{
    VALUE *p = (VALUE *)arg;
    VALUE aliases = p[0], ary = p[1];
    int idx = (int)orig;
    VALUE key, str = rb_ary_entry(ary, idx);

    if (NIL_P(str)) {
	rb_encoding *enc = rb_enc_from_index(idx);

	if (!enc) return ST_CONTINUE;
	if (STRCASECMP((char*)name, rb_enc_name(enc)) == 0) {
	    return ST_CONTINUE;
	}
	str = rb_fstring_cstr(rb_enc_name(enc));
	rb_ary_store(ary, idx, str);
    }
    key = rb_fstring_cstr((char *)name);
    rb_hash_aset(aliases, key, str);
    return ST_CONTINUE;
}

/*
 * call-seq:
 *   Encoding.aliases -> {"alias1" => "orig1", "alias2" => "orig2", ...}
 *
 * Returns the hash of available encoding alias and original encoding name.
 *
 *   Encoding.aliases
 *   #=> {"BINARY"=>"ASCII-8BIT", "ASCII"=>"US-ASCII", "ANSI_X3.4-1986"=>"US-ASCII",
 *         "SJIS"=>"Shift_JIS", "eucJP"=>"EUC-JP", "CP932"=>"Windows-31J"}
 *
 */

static VALUE
rb_enc_aliases(VALUE klass)
{
    VALUE aliases[2];
    aliases[0] = rb_hash_new();
    aliases[1] = rb_ary_new();
    st_foreach(enc_table.names, rb_enc_aliases_enc_i, (st_data_t)aliases);
    return aliases[0];
}

/*
 * An Encoding instance represents a character encoding usable in Ruby. It is
 * defined as a constant under the Encoding namespace. It has a name and
 * optionally, aliases:
 *
 *   Encoding::ISO_8859_1.name
 *   #=> "ISO-8859-1"
 *
 *   Encoding::ISO_8859_1.names
 *   #=> ["ISO-8859-1", "ISO8859-1"]
 *
 * Ruby methods dealing with encodings return or accept Encoding instances as
 * arguments (when a method accepts an Encoding instance as an argument, it
 * can be passed an Encoding name or alias instead).
 *
 *   "some string".encoding
 *   #=> #<Encoding:UTF-8>
 *
 *   string = "some string".encode(Encoding::ISO_8859_1)
 *   #=> "some string"
 *   string.encoding
 *   #=> #<Encoding:ISO-8859-1>
 *
 *   "some string".encode "ISO-8859-1"
 *   #=> "some string"
 *
 * Encoding::ASCII_8BIT is a special encoding that is usually used for
 * a byte string, not a character string. But as the name insists, its
 * characters in the range of ASCII are considered as ASCII
 * characters.  This is useful when you use ASCII-8BIT characters with
 * other ASCII compatible characters.
 *
 * == Changing an encoding
 *
 * The associated Encoding of a String can be changed in two different ways.
 *
 * First, it is possible to set the Encoding of a string to a new Encoding
 * without changing the internal byte representation of the string, with
 * String#force_encoding. This is how you can tell Ruby the correct encoding
 * of a string.
 *
 *   string
 *   #=> "R\xC3\xA9sum\xC3\xA9"
 *   string.encoding
 *   #=> #<Encoding:ISO-8859-1>
 *   string.force_encoding(Encoding::UTF_8)
 *   #=> "R\u00E9sum\u00E9"
 *
 * Second, it is possible to transcode a string, i.e. translate its internal
 * byte representation to another encoding. Its associated encoding is also
 * set to the other encoding. See String#encode for the various forms of
 * transcoding, and the Encoding::Converter class for additional control over
 * the transcoding process.
 *
 *   string
 *   #=> "R\u00E9sum\u00E9"
 *   string.encoding
 *   #=> #<Encoding:UTF-8>
 *   string = string.encode!(Encoding::ISO_8859_1)
 *   #=> "R\xE9sum\xE9"
 *   string.encoding
 *   #=> #<Encoding::ISO-8859-1>
 *
 * == Script encoding
 *
 * All Ruby script code has an associated Encoding which any String literal
 * created in the source code will be associated to.
 *
 * The default script encoding is Encoding::UTF_8 after v2.0, but it
 * can be changed by a magic comment on the first line of the source
 * code file (or second line, if there is a shebang line on the
 * first). The comment must contain the word <code>coding</code> or
 * <code>encoding</code>, followed by a colon, space and the Encoding
 * name or alias:
 *
 *   # encoding: UTF-8
 *
 *   "some string".encoding
 *   #=> #<Encoding:UTF-8>
 *
 * The <code>__ENCODING__</code> keyword returns the script encoding of the file
 * which the keyword is written:
 *
 *   # encoding: ISO-8859-1
 *
 *   __ENCODING__
 *   #=> #<Encoding:ISO-8859-1>
 *
 * <code>ruby -K</code> will change the default locale encoding, but this is
 * not recommended. Ruby source files should declare its script encoding by a
 * magic comment even when they only depend on US-ASCII strings or regular
 * expressions.
 *
 * == Locale encoding
 *
 * The default encoding of the environment. Usually derived from locale.
 *
 * see Encoding.locale_charmap, Encoding.find('locale')
 *
 * == Filesystem encoding
 *
 * The default encoding of strings from the filesystem of the environment.
 * This is used for strings of file names or paths.
 *
 * see Encoding.find('filesystem')
 *
 * == External encoding
 *
 * Each IO object has an external encoding which indicates the encoding that
 * Ruby will use to read its data. By default Ruby sets the external encoding
 * of an IO object to the default external encoding. The default external
 * encoding is set by locale encoding or the interpreter <code>-E</code> option.
 * Encoding.default_external returns the current value of the external
 * encoding.
 *
 *   ENV["LANG"]
 *   #=> "UTF-8"
 *   Encoding.default_external
 *   #=> #<Encoding:UTF-8>
 *
 *   $ ruby -E ISO-8859-1 -e "p Encoding.default_external"
 *   #<Encoding:ISO-8859-1>
 *
 *   $ LANG=C ruby -e 'p Encoding.default_external'
 *   #<Encoding:US-ASCII>
 *
 * The default external encoding may also be set through
 * Encoding.default_external=, but you should not do this as strings created
 * before and after the change will have inconsistent encodings.  Instead use
 * <code>ruby -E</code> to invoke ruby with the correct external encoding.
 *
 * When you know that the actual encoding of the data of an IO object is not
 * the default external encoding, you can reset its external encoding with
 * IO#set_encoding or set it at IO object creation (see IO.new options).
 *
 * == Internal encoding
 *
 * To process the data of an IO object which has an encoding different
 * from its external encoding, you can set its internal encoding. Ruby will use
 * this internal encoding to transcode the data when it is read from the IO
 * object.
 *
 * Conversely, when data is written to the IO object it is transcoded from the
 * internal encoding to the external encoding of the IO object.
 *
 * The internal encoding of an IO object can be set with
 * IO#set_encoding or at IO object creation (see IO.new options).
 *
 * The internal encoding is optional and when not set, the Ruby default
 * internal encoding is used. If not explicitly set this default internal
 * encoding is +nil+ meaning that by default, no transcoding occurs.
 *
 * The default internal encoding can be set with the interpreter option
 * <code>-E</code>. Encoding.default_internal returns the current internal
 * encoding.
 *
 *    $ ruby -e 'p Encoding.default_internal'
 *    nil
 *
 *    $ ruby -E ISO-8859-1:UTF-8 -e "p [Encoding.default_external, \
 *      Encoding.default_internal]"
 *    [#<Encoding:ISO-8859-1>, #<Encoding:UTF-8>]
 *
 * The default internal encoding may also be set through
 * Encoding.default_internal=, but you should not do this as strings created
 * before and after the change will have inconsistent encodings.  Instead use
 * <code>ruby -E</code> to invoke ruby with the correct internal encoding.
 *
 * == IO encoding example
 *
 * In the following example a UTF-8 encoded string "R\u00E9sum\u00E9" is transcoded for
 * output to ISO-8859-1 encoding, then read back in and transcoded to UTF-8:
 *
 *   string = "R\u00E9sum\u00E9"
 *
 *   open("transcoded.txt", "w:ISO-8859-1") do |io|
 *     io.write(string)
 *   end
 *
 *   puts "raw text:"
 *   p File.binread("transcoded.txt")
 *   puts
 *
 *   open("transcoded.txt", "r:ISO-8859-1:UTF-8") do |io|
 *     puts "transcoded text:"
 *     p io.read
 *   end
 *
 * While writing the file, the internal encoding is not specified as it is
 * only necessary for reading.  While reading the file both the internal and
 * external encoding must be specified to obtain the correct result.
 *
 *   $ ruby t.rb
 *   raw text:
 *   "R\xE9sum\xE9"
 *
 *   transcoded text:
 *   "R\u00E9sum\u00E9"
 *
 */

void
Init_encodings(void)
{
    rb_enc_init();
}

void
Init_Encoding(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)
    VALUE list;
    int i;

    rb_cEncoding = rb_define_class("Encoding", rb_cObject);
    rb_define_alloc_func(rb_cEncoding, enc_s_alloc);
    rb_undef_method(CLASS_OF(rb_cEncoding), "new");
    rb_define_method(rb_cEncoding, "to_s", enc_name, 0);
    rb_define_method(rb_cEncoding, "inspect", enc_inspect, 0);
    rb_define_method(rb_cEncoding, "name", enc_name, 0);
    rb_define_method(rb_cEncoding, "names", enc_names, 0);
    rb_define_method(rb_cEncoding, "dummy?", enc_dummy_p, 0);
    rb_define_method(rb_cEncoding, "ascii_compatible?", enc_ascii_compatible_p, 0);
    rb_define_method(rb_cEncoding, "replicate", enc_replicate, 1);
    rb_define_singleton_method(rb_cEncoding, "list", enc_list, 0);
    rb_define_singleton_method(rb_cEncoding, "name_list", rb_enc_name_list, 0);
    rb_define_singleton_method(rb_cEncoding, "aliases", rb_enc_aliases, 0);
    rb_define_singleton_method(rb_cEncoding, "find", enc_find, 1);
    rb_define_singleton_method(rb_cEncoding, "compatible?", enc_compatible_p, 2);

    rb_define_method(rb_cEncoding, "_dump", enc_dump, -1);
    rb_define_singleton_method(rb_cEncoding, "_load", enc_load, 1);

    rb_define_singleton_method(rb_cEncoding, "default_external", get_default_external, 0);
    rb_define_singleton_method(rb_cEncoding, "default_external=", set_default_external, 1);
    rb_define_singleton_method(rb_cEncoding, "default_internal", get_default_internal, 0);
    rb_define_singleton_method(rb_cEncoding, "default_internal=", set_default_internal, 1);
    rb_define_singleton_method(rb_cEncoding, "locale_charmap", rb_locale_charmap, 0); /* in localeinit.c */

    list = rb_ary_new2(enc_table.count);
    RBASIC_CLEAR_CLASS(list);
    rb_encoding_list = list;
    rb_gc_register_mark_object(list);

    for (i = 0; i < enc_table.count; ++i) {
	rb_ary_push(list, enc_new(enc_table.list[i].enc));
    }

    rb_marshal_define_compat(rb_cEncoding, Qnil, NULL, enc_m_loader);
}

/* locale insensitive ctype functions */

void
rb_enc_foreach_name(int (*func)(st_data_t name, st_data_t idx, st_data_t arg), st_data_t arg)
{
    st_foreach(enc_table.names, func, arg);
}
