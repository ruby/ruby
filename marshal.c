/**********************************************************************

  marshal.c -

  $Author$
  created at: Thu Apr 27 16:30:01 JST 1995

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#if defined __GNUC__ && __GNUC__ < 3
# error too old GCC
#endif

#include "internal.h"
#include "ruby/io.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "encindex.h"
#include "id_table.h"

#include <math.h>
#ifdef HAVE_FLOAT_H
#include <float.h>
#endif
#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

#define BITSPERSHORT (2*CHAR_BIT)
#define SHORTMASK ((1<<BITSPERSHORT)-1)
#define SHORTDN(x) RSHIFT((x),BITSPERSHORT)

#if SIZEOF_SHORT == SIZEOF_BDIGIT
#define SHORTLEN(x) (x)
#else
static size_t
shortlen(size_t len, BDIGIT *ds)
{
    BDIGIT num;
    int offset = 0;

    num = ds[len-1];
    while (num) {
	num = SHORTDN(num);
	offset++;
    }
    return (len - 1)*SIZEOF_BDIGIT/2 + offset;
}
#define SHORTLEN(x) shortlen((x),d)
#endif

#define MARSHAL_MAJOR   4
#define MARSHAL_MINOR   8

#define TYPE_NIL	'0'
#define TYPE_TRUE	'T'
#define TYPE_FALSE	'F'
#define TYPE_FIXNUM	'i'

#define TYPE_EXTENDED	'e'
#define TYPE_UCLASS	'C'
#define TYPE_OBJECT	'o'
#define TYPE_DATA       'd'
#define TYPE_USERDEF	'u'
#define TYPE_USRMARSHAL	'U'
#define TYPE_FLOAT	'f'
#define TYPE_BIGNUM	'l'
#define TYPE_STRING	'"'
#define TYPE_REGEXP	'/'
#define TYPE_ARRAY	'['
#define TYPE_HASH	'{'
#define TYPE_HASH_DEF	'}'
#define TYPE_STRUCT	'S'
#define TYPE_MODULE_OLD	'M'
#define TYPE_CLASS	'c'
#define TYPE_MODULE	'm'

#define TYPE_SYMBOL	':'
#define TYPE_SYMLINK	';'

#define TYPE_IVAR	'I'
#define TYPE_LINK	'@'

static ID s_dump, s_load, s_mdump, s_mload;
static ID s_dump_data, s_load_data, s_alloc, s_call;
static ID s_getbyte, s_read, s_write, s_binmode;

#define name_s_dump	"_dump"
#define name_s_load	"_load"
#define name_s_mdump	"marshal_dump"
#define name_s_mload	"marshal_load"
#define name_s_dump_data "_dump_data"
#define name_s_load_data "_load_data"
#define name_s_alloc	"_alloc"
#define name_s_call	"call"
#define name_s_getbyte	"getbyte"
#define name_s_read	"read"
#define name_s_write	"write"
#define name_s_binmode	"binmode"

typedef struct {
    VALUE newclass;
    VALUE oldclass;
    VALUE (*dumper)(VALUE);
    VALUE (*loader)(VALUE, VALUE);
} marshal_compat_t;

static st_table *compat_allocator_tbl;
static VALUE compat_allocator_tbl_wrapper;
static VALUE rb_marshal_dump_limited(VALUE obj, VALUE port, int limit);
static VALUE rb_marshal_load_with_proc(VALUE port, VALUE proc);

static int
mark_marshal_compat_i(st_data_t key, st_data_t value)
{
    marshal_compat_t *p = (marshal_compat_t *)value;
    rb_gc_mark(p->newclass);
    rb_gc_mark(p->oldclass);
    return ST_CONTINUE;
}

static void
mark_marshal_compat_t(void *tbl)
{
    if (!tbl) return;
    st_foreach(tbl, mark_marshal_compat_i, 0);
}

static st_table *compat_allocator_table(void);

void
rb_marshal_define_compat(VALUE newclass, VALUE oldclass, VALUE (*dumper)(VALUE), VALUE (*loader)(VALUE, VALUE))
{
    marshal_compat_t *compat;
    rb_alloc_func_t allocator = rb_get_alloc_func(newclass);

    if (!allocator) {
        rb_raise(rb_eTypeError, "no allocator");
    }

    compat = ALLOC(marshal_compat_t);
    compat->newclass = Qnil;
    compat->oldclass = Qnil;
    compat->newclass = newclass;
    compat->oldclass = oldclass;
    compat->dumper = dumper;
    compat->loader = loader;

    st_insert(compat_allocator_table(), (st_data_t)allocator, (st_data_t)compat);
}

#define MARSHAL_INFECTION FL_TAINT
STATIC_ASSERT(marshal_infection_is_int, MARSHAL_INFECTION == (int)MARSHAL_INFECTION);

struct dump_arg {
    VALUE str, dest;
    st_table *symbols;
    st_table *data;
    st_table *compat_tbl;
    st_table *encodings;
    int infection;
};

struct dump_call_arg {
    VALUE obj;
    struct dump_arg *arg;
    int limit;
};

static VALUE
check_dump_arg(VALUE ret, struct dump_arg *arg, const char *name)
{
    if (!arg->symbols) {
        rb_raise(rb_eRuntimeError, "Marshal.dump reentered at %s",
		 name);
    }
    return ret;
}

static VALUE
check_userdump_arg(VALUE obj, ID sym, int argc, const VALUE *argv,
		   struct dump_arg *arg, const char *name)
{
    VALUE ret = rb_funcallv(obj, sym, argc, argv);
    VALUE klass = CLASS_OF(obj);
    if (CLASS_OF(ret) == klass) {
        rb_raise(rb_eRuntimeError, "%"PRIsVALUE"#%s returned same class instance",
		 klass, name);
    }
    return check_dump_arg(ret, arg, name);
}

#define dump_funcall(arg, obj, sym, argc, argv) \
    check_userdump_arg(obj, sym, argc, argv, arg, name_##sym)
#define dump_check_funcall(arg, obj, sym, argc, argv) \
    check_dump_arg(rb_check_funcall(obj, sym, argc, argv), arg, name_##sym)

static void clear_dump_arg(struct dump_arg *arg);

static void
mark_dump_arg(void *ptr)
{
    struct dump_arg *p = ptr;
    if (!p->symbols)
        return;
    rb_mark_set(p->symbols);
    rb_mark_set(p->data);
    rb_mark_hash(p->compat_tbl);
    rb_gc_mark(p->str);
}

static void
free_dump_arg(void *ptr)
{
    clear_dump_arg(ptr);
    xfree(ptr);
}

static size_t
memsize_dump_arg(const void *ptr)
{
    return sizeof(struct dump_arg);
}

static const rb_data_type_t dump_arg_data = {
    "dump_arg",
    {mark_dump_arg, free_dump_arg, memsize_dump_arg,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
must_not_be_anonymous(const char *type, VALUE path)
{
    char *n = RSTRING_PTR(path);

    if (!rb_enc_asciicompat(rb_enc_get(path))) {
	/* cannot occur? */
	rb_raise(rb_eTypeError, "can't dump non-ascii %s name % "PRIsVALUE,
		 type, path);
    }
    if (n[0] == '#') {
	rb_raise(rb_eTypeError, "can't dump anonymous %s % "PRIsVALUE,
		 type, path);
    }
    return path;
}

static VALUE
class2path(VALUE klass)
{
    VALUE path = rb_class_path(klass);

    must_not_be_anonymous((RB_TYPE_P(klass, T_CLASS) ? "class" : "module"), path);
    if (rb_path_to_class(path) != rb_class_real(klass)) {
	rb_raise(rb_eTypeError, "% "PRIsVALUE" can't be referred to", path);
    }
    return path;
}

static void w_long(long, struct dump_arg*);
static void w_encoding(VALUE encname, struct dump_call_arg *arg);
static VALUE encoding_name(VALUE obj, struct dump_arg *arg);

static void
w_nbyte(const char *s, long n, struct dump_arg *arg)
{
    VALUE buf = arg->str;
    rb_str_buf_cat(buf, s, n);
    RBASIC(buf)->flags |= arg->infection;
    if (arg->dest && RSTRING_LEN(buf) >= BUFSIZ) {
	rb_io_write(arg->dest, buf);
	rb_str_resize(buf, 0);
    }
}

static void
w_byte(char c, struct dump_arg *arg)
{
    w_nbyte(&c, 1, arg);
}

static void
w_bytes(const char *s, long n, struct dump_arg *arg)
{
    w_long(n, arg);
    w_nbyte(s, n, arg);
}

#define w_cstr(s, arg) w_bytes((s), strlen(s), (arg))

static void
w_short(int x, struct dump_arg *arg)
{
    w_byte((char)((x >> 0) & 0xff), arg);
    w_byte((char)((x >> 8) & 0xff), arg);
}

static void
w_long(long x, struct dump_arg *arg)
{
    char buf[sizeof(long)+1];
    int i;

#if SIZEOF_LONG > 4
    if (!(RSHIFT(x, 31) == 0 || RSHIFT(x, 31) == -1)) {
	/* big long does not fit in 4 bytes */
	rb_raise(rb_eTypeError, "long too big to dump");
    }
#endif

    if (x == 0) {
	w_byte(0, arg);
	return;
    }
    if (0 < x && x < 123) {
	w_byte((char)(x + 5), arg);
	return;
    }
    if (-124 < x && x < 0) {
	w_byte((char)((x - 5)&0xff), arg);
	return;
    }
    for (i=1;i<(int)sizeof(long)+1;i++) {
	buf[i] = (char)(x & 0xff);
	x = RSHIFT(x,8);
	if (x == 0) {
	    buf[0] = i;
	    break;
	}
	if (x == -1) {
	    buf[0] = -i;
	    break;
	}
    }
    w_nbyte(buf, i+1, arg);
}

#ifdef DBL_MANT_DIG
#define DECIMAL_MANT (53-16)	/* from IEEE754 double precision */

#if DBL_MANT_DIG > 32
#define MANT_BITS 32
#elif DBL_MANT_DIG > 24
#define MANT_BITS 24
#elif DBL_MANT_DIG > 16
#define MANT_BITS 16
#else
#define MANT_BITS 8
#endif

static double
load_mantissa(double d, const char *buf, long len)
{
    if (!len) return d;
    if (--len > 0 && !*buf++) {	/* binary mantissa mark */
	int e, s = d < 0, dig = 0;
	unsigned long m;

	modf(ldexp(frexp(fabs(d), &e), DECIMAL_MANT), &d);
	do {
	    m = 0;
	    switch (len) {
	      default: m = *buf++ & 0xff;
#if MANT_BITS > 24
	      case 3: m = (m << 8) | (*buf++ & 0xff);
#endif
#if MANT_BITS > 16
	      case 2: m = (m << 8) | (*buf++ & 0xff);
#endif
#if MANT_BITS > 8
	      case 1: m = (m << 8) | (*buf++ & 0xff);
#endif
	    }
	    dig -= len < MANT_BITS / 8 ? 8 * (unsigned)len : MANT_BITS;
	    d += ldexp((double)m, dig);
	} while ((len -= MANT_BITS / 8) > 0);
	d = ldexp(d, e - DECIMAL_MANT);
	if (s) d = -d;
    }
    return d;
}
#else
#define load_mantissa(d, buf, len) (d)
#endif

#ifdef DBL_DIG
#define FLOAT_DIG (DBL_DIG+2)
#else
#define FLOAT_DIG 17
#endif

static void
w_float(double d, struct dump_arg *arg)
{
    char buf[FLOAT_DIG + (DECIMAL_MANT + 7) / 8 + 10];

    if (isinf(d)) {
	if (d < 0) w_cstr("-inf", arg);
	else       w_cstr("inf", arg);
    }
    else if (isnan(d)) {
	w_cstr("nan", arg);
    }
    else if (d == 0.0) {
	if (1.0/d < 0) w_cstr("-0", arg);
	else           w_cstr("0", arg);
    }
    else {
	int decpt, sign, digs, len = 0;
	char *e, *p = ruby_dtoa(d, 0, 0, &decpt, &sign, &e);
	if (sign) buf[len++] = '-';
	digs = (int)(e - p);
	if (decpt < -3 || decpt > digs) {
	    buf[len++] = p[0];
	    if (--digs > 0) buf[len++] = '.';
	    memcpy(buf + len, p + 1, digs);
	    len += digs;
	    len += snprintf(buf + len, sizeof(buf) - len, "e%d", decpt - 1);
	}
	else if (decpt > 0) {
	    memcpy(buf + len, p, decpt);
	    len += decpt;
	    if ((digs -= decpt) > 0) {
		buf[len++] = '.';
		memcpy(buf + len, p + decpt, digs);
		len += digs;
	    }
	}
	else {
	    buf[len++] = '0';
	    buf[len++] = '.';
	    if (decpt) {
		memset(buf + len, '0', -decpt);
		len -= decpt;
	    }
	    memcpy(buf + len, p, digs);
	    len += digs;
	}
	xfree(p);
	w_bytes(buf, len, arg);
    }
}

static void
w_symbol(VALUE sym, struct dump_arg *arg)
{
    st_data_t num;
    VALUE encname;

    if (st_lookup(arg->symbols, sym, &num)) {
	w_byte(TYPE_SYMLINK, arg);
	w_long((long)num, arg);
    }
    else {
	const VALUE orig_sym = sym;
	sym = rb_sym2str(sym);
	if (!sym) {
	    rb_raise(rb_eTypeError, "can't dump anonymous ID %"PRIdVALUE, sym);
	}
	encname = encoding_name(sym, arg);
	if (NIL_P(encname) ||
	    rb_enc_str_coderange(sym) == ENC_CODERANGE_7BIT) {
	    encname = Qnil;
	}
	else {
	    w_byte(TYPE_IVAR, arg);
	}
	w_byte(TYPE_SYMBOL, arg);
	w_bytes(RSTRING_PTR(sym), RSTRING_LEN(sym), arg);
	st_add_direct(arg->symbols, orig_sym, arg->symbols->num_entries);
	if (!NIL_P(encname)) {
	    struct dump_call_arg c_arg;
	    c_arg.limit = 1;
	    c_arg.arg = arg;
	    w_long(1L, arg);
	    w_encoding(encname, &c_arg);
	}
    }
}

static void
w_unique(VALUE s, struct dump_arg *arg)
{
    must_not_be_anonymous("class", s);
    w_symbol(rb_str_intern(s), arg);
}

static void w_object(VALUE,struct dump_arg*,int);

static int
hash_each(VALUE key, VALUE value, struct dump_call_arg *arg)
{
    w_object(key, arg->arg, arg->limit);
    w_object(value, arg->arg, arg->limit);
    return ST_CONTINUE;
}

#define SINGLETON_DUMP_UNABLE_P(klass) \
    (rb_id_table_size(RCLASS_M_TBL(klass)) > 0 || \
     (RCLASS_IV_TBL(klass) && RCLASS_IV_TBL(klass)->num_entries > 1))

static void
w_extended(VALUE klass, struct dump_arg *arg, int check)
{
    if (check && FL_TEST(klass, FL_SINGLETON)) {
	VALUE origin = RCLASS_ORIGIN(klass);
	if (SINGLETON_DUMP_UNABLE_P(klass) ||
	    (origin != klass && SINGLETON_DUMP_UNABLE_P(origin))) {
	    rb_raise(rb_eTypeError, "singleton can't be dumped");
	}
	klass = RCLASS_SUPER(klass);
    }
    while (BUILTIN_TYPE(klass) == T_ICLASS) {
	VALUE path = rb_class_name(RBASIC(klass)->klass);
	w_byte(TYPE_EXTENDED, arg);
	w_unique(path, arg);
	klass = RCLASS_SUPER(klass);
    }
}

static void
w_class(char type, VALUE obj, struct dump_arg *arg, int check)
{
    VALUE path;
    st_data_t real_obj;
    VALUE klass;

    if (arg->compat_tbl &&
		st_lookup(arg->compat_tbl, (st_data_t)obj, &real_obj)) {
        obj = (VALUE)real_obj;
    }
    klass = CLASS_OF(obj);
    w_extended(klass, arg, check);
    w_byte(type, arg);
    path = class2path(rb_class_real(klass));
    w_unique(path, arg);
}

static void
w_uclass(VALUE obj, VALUE super, struct dump_arg *arg)
{
    VALUE klass = CLASS_OF(obj);

    w_extended(klass, arg, TRUE);
    klass = rb_class_real(klass);
    if (klass != super) {
	w_byte(TYPE_UCLASS, arg);
	w_unique(class2path(klass), arg);
    }
}

#define to_be_skipped_id(id) (id == rb_id_encoding() || id == rb_intern("E") || !rb_id2str(id))

static int
w_obj_each(st_data_t key, st_data_t val, st_data_t a)
{
    ID id = (ID)key;
    VALUE value = (VALUE)val;
    struct dump_call_arg *arg = (struct dump_call_arg *)a;

    if (to_be_skipped_id(id)) return ST_CONTINUE;
    w_symbol(ID2SYM(id), arg->arg);
    w_object(value, arg->arg, arg->limit);
    return ST_CONTINUE;
}

static int
obj_count_ivars(st_data_t key, st_data_t val, st_data_t a)
{
    ID id = (ID)key;
    if (!to_be_skipped_id(id)) ++*(st_index_t *)a;
    return ST_CONTINUE;
}

static VALUE
encoding_name(VALUE obj, struct dump_arg *arg)
{
    int encidx = rb_enc_get_index(obj);
    rb_encoding *enc = 0;
    st_data_t name;

    if (encidx <= 0 || !(enc = rb_enc_from_index(encidx))) {
	return Qnil;
    }

    /* special treatment for US-ASCII and UTF-8 */
    if (encidx == rb_usascii_encindex()) {
	return Qfalse;
    }
    else if (encidx == rb_utf8_encindex()) {
	return Qtrue;
    }

    if (arg->encodings ?
	!st_lookup(arg->encodings, (st_data_t)rb_enc_name(enc), &name) :
	(arg->encodings = st_init_strcasetable(), 1)) {
	name = (st_data_t)rb_str_new_cstr(rb_enc_name(enc));
	st_insert(arg->encodings, (st_data_t)rb_enc_name(enc), name);
    }
    return (VALUE)name;
}

static void
w_encoding(VALUE encname, struct dump_call_arg *arg)
{
    switch (encname) {
      case Qfalse:
      case Qtrue:
	w_symbol(ID2SYM(rb_intern("E")), arg->arg);
	w_object(encname, arg->arg, arg->limit + 1);
      case Qnil:
	return;
    }
    w_symbol(ID2SYM(rb_id_encoding()), arg->arg);
    w_object(encname, arg->arg, arg->limit + 1);
}

static st_index_t
has_ivars(VALUE obj, VALUE encname, VALUE *ivobj)
{
    st_index_t enc = !NIL_P(encname);
    st_index_t num = 0;

    if (SPECIAL_CONST_P(obj)) goto generic;
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	break; /* counted elsewhere */
      default:
      generic:
	rb_ivar_foreach(obj, obj_count_ivars, (st_data_t)&num);
	if (num) *ivobj = obj;
    }

    return num + enc;
}

static void
w_ivar(st_index_t num, VALUE ivobj, VALUE encname, struct dump_call_arg *arg)
{
    w_long(num, arg->arg);
    w_encoding(encname, arg);
    if (ivobj != Qundef) {
	rb_ivar_foreach(ivobj, w_obj_each, (st_data_t)arg);
    }
}

static void
w_objivar(VALUE obj, struct dump_call_arg *arg)
{
    st_data_t num = 0;

    rb_ivar_foreach(obj, obj_count_ivars, (st_data_t)&num);
    w_long(num, arg->arg);
    if (num != 0) {
        rb_ivar_foreach(obj, w_obj_each, (st_data_t)arg);
    }
}

static void
w_object(VALUE obj, struct dump_arg *arg, int limit)
{
    struct dump_call_arg c_arg;
    VALUE ivobj = Qundef;
    st_data_t num;
    st_index_t hasiv = 0;
    VALUE encname = Qnil;

    if (limit == 0) {
	rb_raise(rb_eArgError, "exceed depth limit");
    }

    limit--;
    c_arg.limit = limit;
    c_arg.arg = arg;

    if (st_lookup(arg->data, obj, &num)) {
	w_byte(TYPE_LINK, arg);
	w_long((long)num, arg);
	return;
    }

    if (obj == Qnil) {
	w_byte(TYPE_NIL, arg);
    }
    else if (obj == Qtrue) {
	w_byte(TYPE_TRUE, arg);
    }
    else if (obj == Qfalse) {
	w_byte(TYPE_FALSE, arg);
    }
    else if (FIXNUM_P(obj)) {
#if SIZEOF_LONG <= 4
	w_byte(TYPE_FIXNUM, arg);
	w_long(FIX2INT(obj), arg);
#else
	if (RSHIFT((long)obj, 31) == 0 || RSHIFT((long)obj, 31) == -1) {
	    w_byte(TYPE_FIXNUM, arg);
	    w_long(FIX2LONG(obj), arg);
	}
	else {
	    w_object(rb_int2big(FIX2LONG(obj)), arg, limit);
	}
#endif
    }
    else if (SYMBOL_P(obj)) {
	w_symbol(obj, arg);
    }
    else if (FLONUM_P(obj)) {
	st_add_direct(arg->data, obj, arg->data->num_entries);
	w_byte(TYPE_FLOAT, arg);
	w_float(RFLOAT_VALUE(obj), arg);
    }
    else {
	VALUE v;

	if (!RBASIC_CLASS(obj)) {
	    rb_raise(rb_eTypeError, "can't dump internal %s",
		     rb_builtin_type_name(BUILTIN_TYPE(obj)));
	}

	arg->infection |= (int)FL_TEST(obj, MARSHAL_INFECTION);

	if (rb_obj_respond_to(obj, s_mdump, TRUE)) {
	    st_add_direct(arg->data, obj, arg->data->num_entries);

	    v = dump_funcall(arg, obj, s_mdump, 0, 0);
	    w_class(TYPE_USRMARSHAL, obj, arg, FALSE);
	    w_object(v, arg, limit);
	    return;
	}
	if (rb_obj_respond_to(obj, s_dump, TRUE)) {
	    VALUE ivobj2 = Qundef;
	    st_index_t hasiv2;
	    VALUE encname2;

	    v = INT2NUM(limit);
	    v = dump_funcall(arg, obj, s_dump, 1, &v);
	    if (!RB_TYPE_P(v, T_STRING)) {
		rb_raise(rb_eTypeError, "_dump() must return string");
	    }
	    hasiv = has_ivars(obj, (encname = encoding_name(obj, arg)), &ivobj);
	    hasiv2 = has_ivars(v, (encname2 = encoding_name(v, arg)), &ivobj2);
	    if (hasiv2) {
		hasiv = hasiv2;
		ivobj = ivobj2;
		encname = encname2;
	    }
	    if (hasiv) w_byte(TYPE_IVAR, arg);
	    w_class(TYPE_USERDEF, obj, arg, FALSE);
	    w_bytes(RSTRING_PTR(v), RSTRING_LEN(v), arg);
	    if (hasiv) {
		w_ivar(hasiv, ivobj, encname, &c_arg);
	    }
            st_add_direct(arg->data, obj, arg->data->num_entries);
	    return;
	}

        st_add_direct(arg->data, obj, arg->data->num_entries);

	hasiv = has_ivars(obj, (encname = encoding_name(obj, arg)), &ivobj);
        {
            st_data_t compat_data;
            rb_alloc_func_t allocator = rb_get_alloc_func(RBASIC(obj)->klass);
            if (st_lookup(compat_allocator_tbl,
                          (st_data_t)allocator,
                          &compat_data)) {
                marshal_compat_t *compat = (marshal_compat_t*)compat_data;
                VALUE real_obj = obj;
                obj = compat->dumper(real_obj);
                if (!arg->compat_tbl) {
                    arg->compat_tbl = rb_init_identtable();
                }
                st_insert(arg->compat_tbl, (st_data_t)obj, (st_data_t)real_obj);
		if (obj != real_obj && ivobj == Qundef) hasiv = 0;
            }
        }
	if (hasiv) w_byte(TYPE_IVAR, arg);

	switch (BUILTIN_TYPE(obj)) {
	  case T_CLASS:
	    if (FL_TEST(obj, FL_SINGLETON)) {
		rb_raise(rb_eTypeError, "singleton class can't be dumped");
	    }
	    w_byte(TYPE_CLASS, arg);
	    {
		VALUE path = class2path(obj);
		w_bytes(RSTRING_PTR(path), RSTRING_LEN(path), arg);
		RB_GC_GUARD(path);
	    }
	    break;

	  case T_MODULE:
	    w_byte(TYPE_MODULE, arg);
	    {
		VALUE path = class2path(obj);
		w_bytes(RSTRING_PTR(path), RSTRING_LEN(path), arg);
		RB_GC_GUARD(path);
	    }
	    break;

	  case T_FLOAT:
	    w_byte(TYPE_FLOAT, arg);
	    w_float(RFLOAT_VALUE(obj), arg);
	    break;

	  case T_BIGNUM:
	    w_byte(TYPE_BIGNUM, arg);
	    {
		char sign = BIGNUM_SIGN(obj) ? '+' : '-';
		size_t len = BIGNUM_LEN(obj);
		size_t slen;
		BDIGIT *d = BIGNUM_DIGITS(obj);

                slen = SHORTLEN(len);
                if (LONG_MAX < slen) {
                    rb_raise(rb_eTypeError, "too big Bignum can't be dumped");
                }

		w_byte(sign, arg);
		w_long((long)slen, arg);
		while (len--) {
#if SIZEOF_BDIGIT > SIZEOF_SHORT
		    BDIGIT num = *d;
		    int i;

		    for (i=0; i<SIZEOF_BDIGIT; i+=SIZEOF_SHORT) {
			w_short(num & SHORTMASK, arg);
			num = SHORTDN(num);
			if (len == 0 && num == 0) break;
		    }
#else
		    w_short(*d, arg);
#endif
		    d++;
		}
	    }
	    break;

	  case T_STRING:
	    w_uclass(obj, rb_cString, arg);
	    w_byte(TYPE_STRING, arg);
	    w_bytes(RSTRING_PTR(obj), RSTRING_LEN(obj), arg);
	    break;

	  case T_REGEXP:
            w_uclass(obj, rb_cRegexp, arg);
            w_byte(TYPE_REGEXP, arg);
            {
                int opts = rb_reg_options(obj);
                w_bytes(RREGEXP_SRC_PTR(obj), RREGEXP_SRC_LEN(obj), arg);
                w_byte((char)opts, arg);
            }
	    break;

	  case T_ARRAY:
	    w_uclass(obj, rb_cArray, arg);
	    w_byte(TYPE_ARRAY, arg);
	    {
		long i, len = RARRAY_LEN(obj);

		w_long(len, arg);
		for (i=0; i<RARRAY_LEN(obj); i++) {
		    w_object(RARRAY_AREF(obj, i), arg, limit);
		    if (len != RARRAY_LEN(obj)) {
			rb_raise(rb_eRuntimeError, "array modified during dump");
		    }
		}
	    }
	    break;

	  case T_HASH:
	    w_uclass(obj, rb_cHash, arg);
	    if (NIL_P(RHASH_IFNONE(obj))) {
		w_byte(TYPE_HASH, arg);
	    }
	    else if (FL_TEST(obj, HASH_PROC_DEFAULT)) {
		rb_raise(rb_eTypeError, "can't dump hash with default proc");
	    }
	    else {
		w_byte(TYPE_HASH_DEF, arg);
	    }
	    w_long(RHASH_SIZE(obj), arg);
	    rb_hash_foreach(obj, hash_each, (st_data_t)&c_arg);
	    if (!NIL_P(RHASH_IFNONE(obj))) {
		w_object(RHASH_IFNONE(obj), arg, limit);
	    }
	    break;

	  case T_STRUCT:
	    w_class(TYPE_STRUCT, obj, arg, TRUE);
	    {
		long len = RSTRUCT_LEN(obj);
		VALUE mem;
		long i;

		w_long(len, arg);
		mem = rb_struct_members(obj);
		for (i=0; i<len; i++) {
		    w_symbol(RARRAY_AREF(mem, i), arg);
		    w_object(RSTRUCT_GET(obj, i), arg, limit);
		}
	    }
	    break;

	  case T_OBJECT:
	    w_class(TYPE_OBJECT, obj, arg, TRUE);
	    w_objivar(obj, &c_arg);
	    break;

	  case T_DATA:
	    {
		VALUE v;

		if (!rb_obj_respond_to(obj, s_dump_data, TRUE)) {
		    rb_raise(rb_eTypeError,
			     "no _dump_data is defined for class %"PRIsVALUE,
			     rb_obj_class(obj));
		}
		v = dump_funcall(arg, obj, s_dump_data, 0, 0);
		w_class(TYPE_DATA, obj, arg, TRUE);
		w_object(v, arg, limit);
	    }
	    break;

	  default:
	    rb_raise(rb_eTypeError, "can't dump %"PRIsVALUE,
		     rb_obj_class(obj));
	    break;
	}
	RB_GC_GUARD(obj);
    }
    if (hasiv) {
	w_ivar(hasiv, ivobj, encname, &c_arg);
    }
}

static void
clear_dump_arg(struct dump_arg *arg)
{
    if (!arg->symbols) return;
    st_free_table(arg->symbols);
    arg->symbols = 0;
    st_free_table(arg->data);
    arg->data = 0;
    if (arg->compat_tbl) {
	st_free_table(arg->compat_tbl);
	arg->compat_tbl = 0;
    }
    if (arg->encodings) {
	st_free_table(arg->encodings);
	arg->encodings = 0;
    }
}

NORETURN(static inline void io_needed(void));
static inline void
io_needed(void)
{
    rb_raise(rb_eTypeError, "instance of IO needed");
}

/*
 * call-seq:
 *      dump( obj [, anIO] , limit=-1 ) -> anIO
 *
 * Serializes obj and all descendant objects. If anIO is
 * specified, the serialized data will be written to it, otherwise the
 * data will be returned as a String. If limit is specified, the
 * traversal of subobjects will be limited to that depth. If limit is
 * negative, no checking of depth will be performed.
 *
 *     class Klass
 *       def initialize(str)
 *         @str = str
 *       end
 *       def say_hello
 *         @str
 *       end
 *     end
 *
 * (produces no output)
 *
 *     o = Klass.new("hello\n")
 *     data = Marshal.dump(o)
 *     obj = Marshal.load(data)
 *     obj.say_hello  #=> "hello\n"
 *
 * Marshal can't dump following objects:
 * * anonymous Class/Module.
 * * objects which are related to system (ex: Dir, File::Stat, IO, File, Socket
 *   and so on)
 * * an instance of MatchData, Data, Method, UnboundMethod, Proc, Thread,
 *   ThreadGroup, Continuation
 * * objects which define singleton methods
 */
static VALUE
marshal_dump(int argc, VALUE *argv)
{
    VALUE obj, port, a1, a2;
    int limit = -1;

    port = Qnil;
    rb_scan_args(argc, argv, "12", &obj, &a1, &a2);
    if (argc == 3) {
	if (!NIL_P(a2)) limit = NUM2INT(a2);
	if (NIL_P(a1)) io_needed();
	port = a1;
    }
    else if (argc == 2) {
	if (FIXNUM_P(a1)) limit = FIX2INT(a1);
	else if (NIL_P(a1)) io_needed();
	else port = a1;
    }
    return rb_marshal_dump_limited(obj, port, limit);
}

VALUE
rb_marshal_dump_limited(VALUE obj, VALUE port, int limit)
{
    struct dump_arg *arg;
    volatile VALUE wrapper; /* used to avoid memory leak in case of exception */

    wrapper = TypedData_Make_Struct(rb_cData, struct dump_arg, &dump_arg_data, arg);
    arg->dest = 0;
    arg->symbols = st_init_numtable();
    arg->data    = rb_init_identtable();
    arg->infection = 0;
    arg->compat_tbl = 0;
    arg->encodings = 0;
    arg->str = rb_str_buf_new(0);
    if (!NIL_P(port)) {
	if (!rb_respond_to(port, s_write)) {
	    io_needed();
	}
	arg->dest = port;
	dump_check_funcall(arg, port, s_binmode, 0, 0);
    }
    else {
	port = arg->str;
    }

    w_byte(MARSHAL_MAJOR, arg);
    w_byte(MARSHAL_MINOR, arg);

    w_object(obj, arg, limit);
    if (arg->dest) {
	rb_io_write(arg->dest, arg->str);
	rb_str_resize(arg->str, 0);
    }
    clear_dump_arg(arg);
    RB_GC_GUARD(wrapper);

    return port;
}

struct load_arg {
    VALUE src;
    char *buf;
    long buflen;
    long readable;
    long offset;
    st_table *symbols;
    st_table *data;
    VALUE proc;
    st_table *compat_tbl;
    int infection;
};

static VALUE
check_load_arg(VALUE ret, struct load_arg *arg, const char *name)
{
    if (!arg->symbols) {
        rb_raise(rb_eRuntimeError, "Marshal.load reentered at %s",
		 name);
    }
    return ret;
}
#define load_funcall(arg, obj, sym, argc, argv) \
    check_load_arg(rb_funcallv(obj, sym, argc, argv), arg, name_##sym)

static void clear_load_arg(struct load_arg *arg);

static void
mark_load_arg(void *ptr)
{
    struct load_arg *p = ptr;
    if (!p->symbols)
        return;
    rb_mark_tbl(p->symbols);
    rb_mark_tbl(p->data);
    rb_mark_hash(p->compat_tbl);
}

static void
free_load_arg(void *ptr)
{
    clear_load_arg(ptr);
    xfree(ptr);
}

static size_t
memsize_load_arg(const void *ptr)
{
    return sizeof(struct load_arg);
}

static const rb_data_type_t load_arg_data = {
    "load_arg",
    {mark_load_arg, free_load_arg, memsize_load_arg,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#define r_entry(v, arg) r_entry0((v), (arg)->data->num_entries, (arg))
static VALUE r_entry0(VALUE v, st_index_t num, struct load_arg *arg);
static VALUE r_object(struct load_arg *arg);
static VALUE r_symbol(struct load_arg *arg);
static VALUE path2class(VALUE path);

NORETURN(static void too_short(void));
static void
too_short(void)
{
    rb_raise(rb_eArgError, "marshal data too short");
}

static st_index_t
r_prepare(struct load_arg *arg)
{
    st_index_t idx = arg->data->num_entries;

    st_insert(arg->data, (st_data_t)idx, (st_data_t)Qundef);
    return idx;
}

static unsigned char
r_byte1_buffered(struct load_arg *arg)
{
    if (arg->buflen == 0) {
	long readable = arg->readable < BUFSIZ ? arg->readable : BUFSIZ;
	VALUE str, n = LONG2NUM(readable);

	str = load_funcall(arg, arg->src, s_read, 1, &n);
	if (NIL_P(str)) too_short();
	StringValue(str);
	arg->infection |= (int)FL_TEST(str, MARSHAL_INFECTION);
	memcpy(arg->buf, RSTRING_PTR(str), RSTRING_LEN(str));
	arg->offset = 0;
	arg->buflen = RSTRING_LEN(str);
    }
    arg->buflen--;
    return arg->buf[arg->offset++];
}

static int
r_byte(struct load_arg *arg)
{
    int c;

    if (RB_TYPE_P(arg->src, T_STRING)) {
	if (RSTRING_LEN(arg->src) > arg->offset) {
	    c = (unsigned char)RSTRING_PTR(arg->src)[arg->offset++];
	}
	else {
	    too_short();
	}
    }
    else {
	if (arg->readable >0 || arg->buflen > 0) {
	    c = r_byte1_buffered(arg);
	}
	else {
	    VALUE v = load_funcall(arg, arg->src, s_getbyte, 0, 0);
	    if (NIL_P(v)) rb_eof_error();
	    c = (unsigned char)NUM2CHR(v);
	}
    }
    return c;
}

static void
long_toobig(int size)
{
    rb_raise(rb_eTypeError, "long too big for this architecture (size "
	     STRINGIZE(SIZEOF_LONG)", given %d)", size);
}

#undef SIGN_EXTEND_CHAR
#if __STDC__
# define SIGN_EXTEND_CHAR(c) ((signed char)(c))
#else  /* not __STDC__ */
/* As in Harbison and Steele.  */
# define SIGN_EXTEND_CHAR(c) ((((unsigned char)(c)) ^ 128) - 128)
#endif

static long
r_long(struct load_arg *arg)
{
    register long x;
    int c = SIGN_EXTEND_CHAR(r_byte(arg));
    long i;

    if (c == 0) return 0;
    if (c > 0) {
	if (4 < c && c < 128) {
	    return c - 5;
	}
	if (c > (int)sizeof(long)) long_toobig(c);
	x = 0;
	for (i=0;i<c;i++) {
	    x |= (long)r_byte(arg) << (8*i);
	}
    }
    else {
	if (-129 < c && c < -4) {
	    return c + 5;
	}
	c = -c;
	if (c > (int)sizeof(long)) long_toobig(c);
	x = -1;
	for (i=0;i<c;i++) {
	    x &= ~((long)0xff << (8*i));
	    x |= (long)r_byte(arg) << (8*i);
	}
    }
    return x;
}

static VALUE
r_bytes1(long len, struct load_arg *arg)
{
    VALUE str, n = LONG2NUM(len);

    str = load_funcall(arg, arg->src, s_read, 1, &n);
    if (NIL_P(str)) too_short();
    StringValue(str);
    if (RSTRING_LEN(str) != len) too_short();
    arg->infection |= (int)FL_TEST(str, MARSHAL_INFECTION);

    return str;
}

static VALUE
r_bytes1_buffered(long len, struct load_arg *arg)
{
    VALUE str;

    if (len <= arg->buflen) {
	str = rb_str_new(arg->buf+arg->offset, len);
	arg->offset += len;
	arg->buflen -= len;
    }
    else {
	long buflen = arg->buflen;
	long readable = arg->readable + 1;
	long tmp_len, read_len, need_len = len - buflen;
	VALUE tmp, n;

	readable = readable < BUFSIZ ? readable : BUFSIZ;
	read_len = need_len > readable ? need_len : readable;
	n = LONG2NUM(read_len);
	tmp = load_funcall(arg, arg->src, s_read, 1, &n);
	if (NIL_P(tmp)) too_short();
	StringValue(tmp);

	tmp_len = RSTRING_LEN(tmp);

	if (tmp_len < need_len) too_short();
	arg->infection |= (int)FL_TEST(tmp, MARSHAL_INFECTION);

	str = rb_str_new(arg->buf+arg->offset, buflen);
	rb_str_cat(str, RSTRING_PTR(tmp), need_len);

	if (tmp_len > need_len) {
	    buflen = tmp_len - need_len;
	    memcpy(arg->buf, RSTRING_PTR(tmp)+need_len, buflen);
	    arg->buflen = buflen;
	}
	else {
	    arg->buflen = 0;
	}
	arg->offset = 0;
    }

    return str;
}

#define r_bytes(arg) r_bytes0(r_long(arg), (arg))

static VALUE
r_bytes0(long len, struct load_arg *arg)
{
    VALUE str;

    if (len == 0) return rb_str_new(0, 0);
    if (RB_TYPE_P(arg->src, T_STRING)) {
	if (RSTRING_LEN(arg->src) - arg->offset >= len) {
	    str = rb_str_new(RSTRING_PTR(arg->src)+arg->offset, len);
	    arg->offset += len;
	}
	else {
	    too_short();
	}
    }
    else {
	if (arg->readable > 0 || arg->buflen > 0) {
	    str = r_bytes1_buffered(len, arg);
	}
	else {
	    str = r_bytes1(len, arg);
	}
    }
    return str;
}

static int
sym2encidx(VALUE sym, VALUE val)
{
    static const char name_encoding[8] = "encoding";
    const char *p;
    long l;
    if (rb_enc_get_index(sym) != ENCINDEX_US_ASCII) return -1;
    RSTRING_GETMEM(sym, p, l);
    if (l <= 0) return -1;
    if (l == sizeof(name_encoding) &&
	memcmp(p, name_encoding, sizeof(name_encoding)) == 0) {
	int idx = rb_enc_find_index(StringValueCStr(val));
	return idx;
    }
    else if (l == 1 && *p == 'E') {
	if (val == Qfalse) return rb_usascii_encindex();
	else if (val == Qtrue) return rb_utf8_encindex();
	/* bogus ignore */
    }
    return -1;
}

static VALUE
r_symlink(struct load_arg *arg)
{
    st_data_t sym;
    long num = r_long(arg);

    if (!st_lookup(arg->symbols, num, &sym)) {
	rb_raise(rb_eArgError, "bad symbol");
    }
    return (VALUE)sym;
}

static VALUE
r_symreal(struct load_arg *arg, int ivar)
{
    VALUE s = r_bytes(arg);
    VALUE sym;
    int idx = -1;
    st_index_t n = arg->symbols->num_entries;

    if (rb_enc_str_asciionly_p(s)) rb_enc_associate_index(s, ENCINDEX_US_ASCII);
    st_insert(arg->symbols, (st_data_t)n, (st_data_t)s);
    if (ivar) {
	long num = r_long(arg);
	while (num-- > 0) {
	    sym = r_symbol(arg);
	    idx = sym2encidx(sym, r_object(arg));
	}
    }
    if (idx > 0) rb_enc_associate_index(s, idx);

    return s;
}

static VALUE
r_symbol(struct load_arg *arg)
{
    int type, ivar = 0;

  again:
    switch ((type = r_byte(arg))) {
      default:
	rb_raise(rb_eArgError, "dump format error for symbol(0x%x)", type);
      case TYPE_IVAR:
	ivar = 1;
	goto again;
      case TYPE_SYMBOL:
	return r_symreal(arg, ivar);
      case TYPE_SYMLINK:
	if (ivar) {
	    rb_raise(rb_eArgError, "dump format error (symlink with encoding)");
	}
	return r_symlink(arg);
    }
}

static VALUE
r_unique(struct load_arg *arg)
{
    return r_symbol(arg);
}

static VALUE
r_string(struct load_arg *arg)
{
    return r_bytes(arg);
}

static VALUE
r_entry0(VALUE v, st_index_t num, struct load_arg *arg)
{
    st_data_t real_obj = (VALUE)Qundef;
    if (arg->compat_tbl && st_lookup(arg->compat_tbl, v, &real_obj)) {
        st_insert(arg->data, num, (st_data_t)real_obj);
    }
    else {
        st_insert(arg->data, num, (st_data_t)v);
    }
    if (arg->infection &&
	!RB_TYPE_P(v, T_CLASS) && !RB_TYPE_P(v, T_MODULE)) {
	OBJ_TAINT(v);
	if ((VALUE)real_obj != Qundef)
	    OBJ_TAINT((VALUE)real_obj);
    }
    return v;
}

static VALUE
r_fixup_compat(VALUE v, struct load_arg *arg)
{
    st_data_t data;
    st_data_t key = (st_data_t)v;
    if (arg->compat_tbl && st_delete(arg->compat_tbl, &key, &data)) {
        VALUE real_obj = (VALUE)data;
        rb_alloc_func_t allocator = rb_get_alloc_func(CLASS_OF(real_obj));
        if (st_lookup(compat_allocator_tbl, (st_data_t)allocator, &data)) {
            marshal_compat_t *compat = (marshal_compat_t*)data;
            compat->loader(real_obj, v);
        }
        v = real_obj;
    }
    return v;
}

static VALUE
r_post_proc(VALUE v, struct load_arg *arg)
{
    if (arg->proc) {
	v = load_funcall(arg, arg->proc, s_call, 1, &v);
    }
    return v;
}

static VALUE
r_leave(VALUE v, struct load_arg *arg)
{
    v = r_fixup_compat(v, arg);
    v = r_post_proc(v, arg);
    return v;
}

static int
copy_ivar_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE obj = (VALUE)arg, value = (VALUE)val;
    ID vid = (ID)key;

    if (!rb_ivar_defined(obj, vid))
	rb_ivar_set(obj, vid, value);
    return ST_CONTINUE;
}

static VALUE
r_copy_ivar(VALUE v, VALUE data)
{
    rb_ivar_foreach(data, copy_ivar_i, (st_data_t)v);
    return v;
}

static void
r_ivar(VALUE obj, int *has_encoding, struct load_arg *arg)
{
    long len;

    len = r_long(arg);
    if (len > 0) {
	do {
	    VALUE sym = r_symbol(arg);
	    VALUE val = r_object(arg);
	    int idx = sym2encidx(sym, val);
	    if (idx >= 0) {
		rb_enc_associate_index(obj, idx);
		if (has_encoding) *has_encoding = TRUE;
	    }
	    else {
		rb_ivar_set(obj, rb_intern_str(sym), val);
	    }
	} while (--len > 0);
    }
}

static VALUE
path2class(VALUE path)
{
    VALUE v = rb_path_to_class(path);

    if (!RB_TYPE_P(v, T_CLASS)) {
	rb_raise(rb_eArgError, "%"PRIsVALUE" does not refer to class", path);
    }
    return v;
}

#define path2module(path) must_be_module(rb_path_to_class(path), path)

static VALUE
must_be_module(VALUE v, VALUE path)
{
    if (!RB_TYPE_P(v, T_MODULE)) {
	rb_raise(rb_eArgError, "%"PRIsVALUE" does not refer to module", path);
    }
    return v;
}

static VALUE
obj_alloc_by_klass(VALUE klass, struct load_arg *arg, VALUE *oldclass)
{
    st_data_t data;
    rb_alloc_func_t allocator;

    allocator = rb_get_alloc_func(klass);
    if (st_lookup(compat_allocator_tbl, (st_data_t)allocator, &data)) {
        marshal_compat_t *compat = (marshal_compat_t*)data;
        VALUE real_obj = rb_obj_alloc(klass);
        VALUE obj = rb_obj_alloc(compat->oldclass);
	if (oldclass) *oldclass = compat->oldclass;

        if (!arg->compat_tbl) {
            arg->compat_tbl = rb_init_identtable();
        }
        st_insert(arg->compat_tbl, (st_data_t)obj, (st_data_t)real_obj);
        return obj;
    }

    return rb_obj_alloc(klass);
}

static VALUE
obj_alloc_by_path(VALUE path, struct load_arg *arg)
{
    return obj_alloc_by_klass(path2class(path), arg, 0);
}

static VALUE
append_extmod(VALUE obj, VALUE extmod)
{
    long i = RARRAY_LEN(extmod);
    while (i > 0) {
	VALUE m = RARRAY_AREF(extmod, --i);
	rb_extend_object(obj, m);
    }
    return obj;
}

#define prohibit_ivar(type, str) do { \
	if (!ivp || !*ivp) break; \
	rb_raise(rb_eTypeError, \
		 "can't override instance variable of "type" `%"PRIsVALUE"'", \
		 (str)); \
    } while (0)

static VALUE
r_object0(struct load_arg *arg, int *ivp, VALUE extmod)
{
    VALUE v = Qnil;
    int type = r_byte(arg);
    long id;
    st_data_t link;

    switch (type) {
      case TYPE_LINK:
	id = r_long(arg);
	if (!st_lookup(arg->data, (st_data_t)id, &link)) {
	    rb_raise(rb_eArgError, "dump format error (unlinked)");
	}
	v = (VALUE)link;
	v = r_post_proc(v, arg);
	break;

      case TYPE_IVAR:
        {
	    int ivar = TRUE;

	    v = r_object0(arg, &ivar, extmod);
	    if (ivar) r_ivar(v, NULL, arg);
	}
	break;

      case TYPE_EXTENDED:
	{
	    VALUE path = r_unique(arg);
	    VALUE m = rb_path_to_class(path);
	    if (NIL_P(extmod)) extmod = rb_ary_tmp_new(0);

	    if (RB_TYPE_P(m, T_CLASS)) { /* prepended */
		VALUE c;

		v = r_object0(arg, 0, Qnil);
		c = CLASS_OF(v);
		if (c != m || FL_TEST(c, FL_SINGLETON)) {
		    rb_raise(rb_eArgError,
			     "prepended class %"PRIsVALUE" differs from class %"PRIsVALUE,
			     path, rb_class_name(c));
		}
		c = rb_singleton_class(v);
		while (RARRAY_LEN(extmod) > 0) {
		    m = rb_ary_pop(extmod);
		    rb_prepend_module(c, m);
		}
	    }
	    else {
		must_be_module(m, path);
		rb_ary_push(extmod, m);

		v = r_object0(arg, 0, extmod);
		while (RARRAY_LEN(extmod) > 0) {
		    m = rb_ary_pop(extmod);
		    rb_extend_object(v, m);
		}
	    }
	}
	break;

      case TYPE_UCLASS:
	{
	    VALUE c = path2class(r_unique(arg));

	    if (FL_TEST(c, FL_SINGLETON)) {
		rb_raise(rb_eTypeError, "singleton can't be loaded");
	    }
	    v = r_object0(arg, 0, extmod);
	    if (rb_special_const_p(v) || RB_TYPE_P(v, T_OBJECT) || RB_TYPE_P(v, T_CLASS)) {
	      format_error:
		rb_raise(rb_eArgError, "dump format error (user class)");
	    }
	    if (RB_TYPE_P(v, T_MODULE) || !RTEST(rb_class_inherited_p(c, RBASIC(v)->klass))) {
		VALUE tmp = rb_obj_alloc(c);

		if (TYPE(v) != TYPE(tmp)) goto format_error;
	    }
	    RBASIC_SET_CLASS(v, c);
	}
	break;

      case TYPE_NIL:
	v = Qnil;
	v = r_leave(v, arg);
	break;

      case TYPE_TRUE:
	v = Qtrue;
	v = r_leave(v, arg);
	break;

      case TYPE_FALSE:
	v = Qfalse;
	v = r_leave(v, arg);
	break;

      case TYPE_FIXNUM:
	{
	    long i = r_long(arg);
	    v = LONG2FIX(i);
	}
	v = r_leave(v, arg);
	break;

      case TYPE_FLOAT:
	{
	    double d;
	    VALUE str = r_bytes(arg);
	    const char *ptr = RSTRING_PTR(str);

	    if (strcmp(ptr, "nan") == 0) {
		d = NAN;
	    }
	    else if (strcmp(ptr, "inf") == 0) {
		d = INFINITY;
	    }
	    else if (strcmp(ptr, "-inf") == 0) {
		d = -INFINITY;
	    }
	    else {
		char *e;
		d = strtod(ptr, &e);
		d = load_mantissa(d, e, RSTRING_LEN(str) - (e - ptr));
	    }
	    v = DBL2NUM(d);
	    v = r_entry(v, arg);
            v = r_leave(v, arg);
	}
	break;

      case TYPE_BIGNUM:
	{
	    long len;
	    VALUE data;
            int sign;

	    sign = r_byte(arg);
	    len = r_long(arg);
	    data = r_bytes0(len * 2, arg);
            v = rb_integer_unpack(RSTRING_PTR(data), len, 2, 0,
                INTEGER_PACK_LITTLE_ENDIAN | (sign == '-' ? INTEGER_PACK_NEGATIVE : 0));
	    rb_str_resize(data, 0L);
	    v = r_entry(v, arg);
            v = r_leave(v, arg);
	}
	break;

      case TYPE_STRING:
	v = r_entry(r_string(arg), arg);
        v = r_leave(v, arg);
	break;

      case TYPE_REGEXP:
	{
	    VALUE str = r_bytes(arg);
	    int options = r_byte(arg);
	    int has_encoding = FALSE;
	    st_index_t idx = r_prepare(arg);

	    if (ivp) {
		r_ivar(str, &has_encoding, arg);
		*ivp = FALSE;
	    }
	    if (!has_encoding) {
		/* 1.8 compatibility; remove escapes undefined in 1.8 */
		char *ptr = RSTRING_PTR(str), *dst = ptr, *src = ptr;
		long len = RSTRING_LEN(str);
		long bs = 0;
		for (; len-- > 0; *dst++ = *src++) {
		    switch (*src) {
		      case '\\': bs++; break;
		      case 'g': case 'h': case 'i': case 'j': case 'k': case 'l':
		      case 'm': case 'o': case 'p': case 'q': case 'u': case 'y':
		      case 'E': case 'F': case 'H': case 'I': case 'J': case 'K':
		      case 'L': case 'N': case 'O': case 'P': case 'Q': case 'R':
		      case 'S': case 'T': case 'U': case 'V': case 'X': case 'Y':
			if (bs & 1) --dst;
		      default: bs = 0; break;
		    }
		}
		rb_str_set_len(str, dst - ptr);
	    }
	    v = r_entry0(rb_reg_new_str(str, options), idx, arg);
	    v = r_leave(v, arg);
	}
	break;

      case TYPE_ARRAY:
	{
	    long len = r_long(arg);

	    v = rb_ary_new2(len);
	    v = r_entry(v, arg);
	    arg->readable += len - 1;
	    while (len--) {
		rb_ary_push(v, r_object(arg));
		arg->readable--;
	    }
            v = r_leave(v, arg);
	    arg->readable++;
	}
	break;

      case TYPE_HASH:
      case TYPE_HASH_DEF:
	{
	    long len = r_long(arg);

	    v = rb_hash_new();
	    v = r_entry(v, arg);
	    arg->readable += (len - 1) * 2;
	    while (len--) {
		VALUE key = r_object(arg);
		VALUE value = r_object(arg);
		rb_hash_aset(v, key, value);
		arg->readable -= 2;
	    }
	    arg->readable += 2;
	    if (type == TYPE_HASH_DEF) {
		RHASH_SET_IFNONE(v, r_object(arg));
	    }
            v = r_leave(v, arg);
	}
	break;

      case TYPE_STRUCT:
	{
	    VALUE mem, values;
	    long i;
	    VALUE slot;
	    st_index_t idx = r_prepare(arg);
	    VALUE klass = path2class(r_unique(arg));
	    long len = r_long(arg);

            v = rb_obj_alloc(klass);
	    if (!RB_TYPE_P(v, T_STRUCT)) {
		rb_raise(rb_eTypeError, "class %"PRIsVALUE" not a struct", rb_class_name(klass));
	    }
	    mem = rb_struct_s_members(klass);
            if (RARRAY_LEN(mem) != len) {
                rb_raise(rb_eTypeError, "struct %"PRIsVALUE" not compatible (struct size differs)",
                         rb_class_name(klass));
            }

	    arg->readable += (len - 1) * 2;
	    v = r_entry0(v, idx, arg);
	    values = rb_ary_new2(len);
	    for (i=0; i<len; i++) {
		VALUE n = rb_sym2str(RARRAY_AREF(mem, i));
		slot = r_symbol(arg);

		if (!rb_str_equal(n, slot)) {
		    rb_raise(rb_eTypeError, "struct %"PRIsVALUE" not compatible (:%"PRIsVALUE" for :%"PRIsVALUE")",
			     rb_class_name(klass),
			     slot, n);
		}
                rb_ary_push(values, r_object(arg));
		arg->readable -= 2;
	    }
            rb_struct_initialize(v, values);
            v = r_leave(v, arg);
	    arg->readable += 2;
	}
	break;

      case TYPE_USERDEF:
        {
	    VALUE name = r_unique(arg);
	    VALUE klass = path2class(name);
	    VALUE data;
	    st_data_t d;

	    if (!rb_obj_respond_to(klass, s_load, TRUE)) {
		rb_raise(rb_eTypeError, "class %"PRIsVALUE" needs to have method `_load'",
			 name);
	    }
	    data = r_string(arg);
	    if (ivp) {
		r_ivar(data, NULL, arg);
		*ivp = FALSE;
	    }
	    v = load_funcall(arg, klass, s_load, 1, &data);
	    v = r_entry(v, arg);
	    if (st_lookup(compat_allocator_tbl, (st_data_t)rb_get_alloc_func(klass), &d)) {
		marshal_compat_t *compat = (marshal_compat_t*)d;
		v = compat->loader(klass, v);
	    }
	    v = r_post_proc(v, arg);
	}
        break;

      case TYPE_USRMARSHAL:
        {
	    VALUE name = r_unique(arg);
	    VALUE klass = path2class(name);
	    VALUE oldclass = 0;
	    VALUE data;

	    v = obj_alloc_by_klass(klass, arg, &oldclass);
            if (!NIL_P(extmod)) {
		/* for the case marshal_load is overridden */
		append_extmod(v, extmod);
            }
	    if (!rb_obj_respond_to(v, s_mload, TRUE)) {
		rb_raise(rb_eTypeError, "instance of %"PRIsVALUE" needs to have method `marshal_load'",
			 name);
	    }
	    v = r_entry(v, arg);
	    data = r_object(arg);
	    load_funcall(arg, v, s_mload, 1, &data);
	    v = r_fixup_compat(v, arg);
	    v = r_copy_ivar(v, data);
	    v = r_post_proc(v, arg);
	    if (!NIL_P(extmod)) {
		if (oldclass) append_extmod(v, extmod);
		rb_ary_clear(extmod);
	    }
	}
        break;

      case TYPE_OBJECT:
	{
	    st_index_t idx = r_prepare(arg);
            v = obj_alloc_by_path(r_unique(arg), arg);
	    if (!RB_TYPE_P(v, T_OBJECT)) {
		rb_raise(rb_eArgError, "dump format error");
	    }
	    v = r_entry0(v, idx, arg);
	    r_ivar(v, NULL, arg);
	    v = r_leave(v, arg);
	}
	break;

      case TYPE_DATA:
	{
	    VALUE name = r_unique(arg);
	    VALUE klass = path2class(name);
	    VALUE oldclass = 0;
	    VALUE r;

	    v = obj_alloc_by_klass(klass, arg, &oldclass);
	    if (!RB_TYPE_P(v, T_DATA)) {
		rb_raise(rb_eArgError, "dump format error");
	    }
	    v = r_entry(v, arg);
	    if (!rb_obj_respond_to(v, s_load_data, TRUE)) {
		rb_raise(rb_eTypeError,
			 "class %"PRIsVALUE" needs to have instance method `_load_data'",
			 name);
	    }
	    r = r_object0(arg, 0, extmod);
	    load_funcall(arg, v, s_load_data, 1, &r);
	    v = r_leave(v, arg);
	}
	break;

      case TYPE_MODULE_OLD:
        {
	    VALUE str = r_bytes(arg);

	    v = rb_path_to_class(str);
	    prohibit_ivar("class/module", str);
	    v = r_entry(v, arg);
            v = r_leave(v, arg);
	}
	break;

      case TYPE_CLASS:
        {
	    VALUE str = r_bytes(arg);

	    v = path2class(str);
	    prohibit_ivar("class", str);
	    v = r_entry(v, arg);
            v = r_leave(v, arg);
	}
	break;

      case TYPE_MODULE:
        {
	    VALUE str = r_bytes(arg);

	    v = path2module(str);
	    prohibit_ivar("module", str);
	    v = r_entry(v, arg);
            v = r_leave(v, arg);
	}
	break;

      case TYPE_SYMBOL:
	if (ivp) {
	    v = r_symreal(arg, *ivp);
	    *ivp = FALSE;
	}
	else {
	    v = r_symreal(arg, 0);
	}
	v = rb_str_intern(v);
	v = r_leave(v, arg);
	break;

      case TYPE_SYMLINK:
	v = rb_str_intern(r_symlink(arg));
	break;

      default:
	rb_raise(rb_eArgError, "dump format error(0x%x)", type);
	break;
    }

    if (v == Qundef) {
	rb_raise(rb_eArgError, "dump format error (bad link)");
    }

    return v;
}

static VALUE
r_object(struct load_arg *arg)
{
    return r_object0(arg, 0, Qnil);
}

static void
clear_load_arg(struct load_arg *arg)
{
    if (arg->buf) {
	xfree(arg->buf);
	arg->buf = 0;
    }
    arg->buflen = 0;
    arg->offset = 0;
    arg->readable = 0;
    if (!arg->symbols) return;
    st_free_table(arg->symbols);
    arg->symbols = 0;
    st_free_table(arg->data);
    arg->data = 0;
    if (arg->compat_tbl) {
	st_free_table(arg->compat_tbl);
	arg->compat_tbl = 0;
    }
}

/*
 * call-seq:
 *     load( source [, proc] ) -> obj
 *     restore( source [, proc] ) -> obj
 *
 * Returns the result of converting the serialized data in source into a
 * Ruby object (possibly with associated subordinate objects). source
 * may be either an instance of IO or an object that responds to
 * to_str. If proc is specified, each object will be passed to the proc, as the object
 * is being deserialized.
 *
 * Never pass untrusted data (including user supplied input) to this method.
 * Please see the overview for further details.
 */
static VALUE
marshal_load(int argc, VALUE *argv)
{
    VALUE port, proc;

    rb_check_arity(argc, 1, 2);
    port = argv[0];
    proc = argc > 1 ? argv[1] : Qnil;
    return rb_marshal_load_with_proc(port, proc);
}

VALUE
rb_marshal_load_with_proc(VALUE port, VALUE proc)
{
    int major, minor, infection = 0;
    VALUE v;
    volatile VALUE wrapper; /* used to avoid memory leak in case of exception */
    struct load_arg *arg;

    v = rb_check_string_type(port);
    if (!NIL_P(v)) {
	infection = (int)FL_TEST(port, MARSHAL_INFECTION); /* original taintedness */
	port = v;
    }
    else if (rb_respond_to(port, s_getbyte) && rb_respond_to(port, s_read)) {
	rb_check_funcall(port, s_binmode, 0, 0);
	infection = (int)FL_TAINT;
    }
    else {
	io_needed();
    }
    wrapper = TypedData_Make_Struct(rb_cData, struct load_arg, &load_arg_data, arg);
    arg->infection = infection;
    arg->src = port;
    arg->offset = 0;
    arg->symbols = st_init_numtable();
    arg->data    = rb_init_identtable();
    arg->compat_tbl = 0;
    arg->proc = 0;
    arg->readable = 0;

    if (NIL_P(v))
	arg->buf = xmalloc(BUFSIZ);
    else
	arg->buf = 0;

    major = r_byte(arg);
    minor = r_byte(arg);
    if (major != MARSHAL_MAJOR || minor > MARSHAL_MINOR) {
	clear_load_arg(arg);
	rb_raise(rb_eTypeError, "incompatible marshal file format (can't be read)\n\
\tformat version %d.%d required; %d.%d given",
		 MARSHAL_MAJOR, MARSHAL_MINOR, major, minor);
    }
    if (RTEST(ruby_verbose) && minor != MARSHAL_MINOR) {
	rb_warn("incompatible marshal file format (can be read)\n\
\tformat version %d.%d required; %d.%d given",
		MARSHAL_MAJOR, MARSHAL_MINOR, major, minor);
    }

    if (!NIL_P(proc)) arg->proc = proc;
    v = r_object(arg);
    clear_load_arg(arg);
    RB_GC_GUARD(wrapper);

    return v;
}

/*
 * The marshaling library converts collections of Ruby objects into a
 * byte stream, allowing them to be stored outside the currently
 * active script. This data may subsequently be read and the original
 * objects reconstituted.
 *
 * Marshaled data has major and minor version numbers stored along
 * with the object information. In normal use, marshaling can only
 * load data written with the same major version number and an equal
 * or lower minor version number. If Ruby's ``verbose'' flag is set
 * (normally using -d, -v, -w, or --verbose) the major and minor
 * numbers must match exactly. Marshal versioning is independent of
 * Ruby's version numbers. You can extract the version by reading the
 * first two bytes of marshaled data.
 *
 *     str = Marshal.dump("thing")
 *     RUBY_VERSION   #=> "1.9.0"
 *     str[0].ord     #=> 4
 *     str[1].ord     #=> 8
 *
 * Some objects cannot be dumped: if the objects to be dumped include
 * bindings, procedure or method objects, instances of class IO, or
 * singleton objects, a TypeError will be raised.
 *
 * If your class has special serialization needs (for example, if you
 * want to serialize in some specific format), or if it contains
 * objects that would otherwise not be serializable, you can implement
 * your own serialization strategy.
 *
 * There are two methods of doing this, your object can define either
 * marshal_dump and marshal_load or _dump and _load.  marshal_dump will take
 * precedence over _dump if both are defined.  marshal_dump may result in
 * smaller Marshal strings.
 *
 * == Security considerations
 *
 * By design, Marshal.load can deserialize almost any class loaded into the
 * Ruby process. In many cases this can lead to remote code execution if the
 * Marshal data is loaded from an untrusted source.
 *
 * As a result, Marshal.load is not suitable as a general purpose serialization
 * format and you should never unmarshal user supplied input or other untrusted
 * data.
 *
 * If you need to deserialize untrusted data, use JSON or another serialization
 * format that is only able to load simple, 'primitive' types such as String,
 * Array, Hash, etc. Never allow user input to specify arbitrary types to
 * deserialize into.
 *
 * == marshal_dump and marshal_load
 *
 * When dumping an object the method marshal_dump will be called.
 * marshal_dump must return a result containing the information necessary for
 * marshal_load to reconstitute the object.  The result can be any object.
 *
 * When loading an object dumped using marshal_dump the object is first
 * allocated then marshal_load is called with the result from marshal_dump.
 * marshal_load must recreate the object from the information in the result.
 *
 * Example:
 *
 *   class MyObj
 *     def initialize name, version, data
 *       @name    = name
 *       @version = version
 *       @data    = data
 *     end
 *
 *     def marshal_dump
 *       [@name, @version]
 *     end
 *
 *     def marshal_load array
 *       @name, @version = array
 *     end
 *   end
 *
 * == _dump and _load
 *
 * Use _dump and _load when you need to allocate the object you're restoring
 * yourself.
 *
 * When dumping an object the instance method _dump is called with an Integer
 * which indicates the maximum depth of objects to dump (a value of -1 implies
 * that you should disable depth checking).  _dump must return a String
 * containing the information necessary to reconstitute the object.
 *
 * The class method _load should take a String and use it to return an object
 * of the same class.
 *
 * Example:
 *
 *   class MyObj
 *     def initialize name, version, data
 *       @name    = name
 *       @version = version
 *       @data    = data
 *     end
 *
 *     def _dump level
 *       [@name, @version].join ':'
 *     end
 *
 *     def self._load args
 *       new(*args.split(':'))
 *     end
 *   end
 *
 * Since Marshal.dump outputs a string you can have _dump return a Marshal
 * string which is Marshal.loaded in _load for complex objects.
 */
void
Init_marshal(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    VALUE rb_mMarshal = rb_define_module("Marshal");
#define set_id(sym) sym = rb_intern_const(name_##sym)
    set_id(s_dump);
    set_id(s_load);
    set_id(s_mdump);
    set_id(s_mload);
    set_id(s_dump_data);
    set_id(s_load_data);
    set_id(s_alloc);
    set_id(s_call);
    set_id(s_getbyte);
    set_id(s_read);
    set_id(s_write);
    set_id(s_binmode);

    rb_define_module_function(rb_mMarshal, "dump", marshal_dump, -1);
    rb_define_module_function(rb_mMarshal, "load", marshal_load, -1);
    rb_define_module_function(rb_mMarshal, "restore", marshal_load, -1);

    /* major version */
    rb_define_const(rb_mMarshal, "MAJOR_VERSION", INT2FIX(MARSHAL_MAJOR));
    /* minor version */
    rb_define_const(rb_mMarshal, "MINOR_VERSION", INT2FIX(MARSHAL_MINOR));
}

static st_table *
compat_allocator_table(void)
{
    if (compat_allocator_tbl) return compat_allocator_tbl;
    compat_allocator_tbl = st_init_numtable();
#undef RUBY_UNTYPED_DATA_WARNING
#define RUBY_UNTYPED_DATA_WARNING 0
    compat_allocator_tbl_wrapper =
	Data_Wrap_Struct(rb_cData, mark_marshal_compat_t, 0, compat_allocator_tbl);
    rb_gc_register_mark_object(compat_allocator_tbl_wrapper);
    return compat_allocator_tbl;
}

VALUE
rb_marshal_dump(VALUE obj, VALUE port)
{
    return rb_marshal_dump_limited(obj, port, -1);
}

VALUE
rb_marshal_load(VALUE port)
{
    return rb_marshal_load_with_proc(port, Qnil);
}
