/**********************************************************************

  marshal.c -

  $Author$
  $Date$
  created at: Thu Apr 27 16:30:01 JST 1995

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "st.h"
#include "util.h"

#include <math.h>
#ifdef HAVE_FLOAT_H
#include <float.h>
#endif
#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

#define BITSPERSHORT (2*CHAR_BIT)
#define SHORTMASK ((1<<BITSPERSHORT)-1)
#define SHORTDN(x) RSHIFT(x,BITSPERSHORT)

#if SIZEOF_SHORT == SIZEOF_BDIGITS
#define SHORTLEN(x) (x)
#else
static int
shortlen(len, ds)
    long len;
    BDIGIT *ds;
{
    BDIGIT num;
    int offset = 0;

    num = ds[len-1];
    while (num) {
	num = SHORTDN(num);
	offset++;
    }
    return (len - 1)*sizeof(BDIGIT)/2 + offset;
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
static ID s_getc, s_read, s_write, s_binmode;

struct dump_arg {
    VALUE obj;
    VALUE str, dest;
    st_table *symbols;
    st_table *data;
    int taint;
    VALUE wrapper;
};

struct dump_call_arg {
    VALUE obj;
    struct dump_arg *arg;
    int limit;
};

static void
check_dump_arg(arg, sym)
    struct dump_arg *arg;
    ID sym;
{
    if (!DATA_PTR(arg->wrapper)) {
        rb_raise(rb_eRuntimeError, "Marshal.dump reentered at %s",
		 rb_id2name(sym));
    }
}

static void
mark_dump_arg(ptr)
    void *ptr;
{
    struct dump_arg *p = ptr;
    if (!ptr)
        return;
    rb_mark_set(p->data);
}

static VALUE
class2path(klass)
    VALUE klass;
{
    VALUE path = rb_class_path(klass);
    char *n = RSTRING(path)->ptr;

    if (n[0] == '#') {
	rb_raise(rb_eTypeError, "can't dump anonymous %s %s",
		 (TYPE(klass) == T_CLASS ? "class" : "module"),
		 n);
    }
    if (rb_path2class(n) != rb_class_real(klass)) {
	rb_raise(rb_eTypeError, "%s can't be referred", n);
    }
    return path;
}

static void w_long _((long, struct dump_arg*));

static void
w_nbyte(s, n, arg)
    const char *s;
    int n;
    struct dump_arg *arg;
{
    VALUE buf = arg->str;
    rb_str_buf_cat(buf, s, n);
    if (arg->dest && RSTRING(buf)->len >= BUFSIZ) {
	if (arg->taint) OBJ_TAINT(buf);
	rb_io_write(arg->dest, buf);
	rb_str_resize(buf, 0);
    }
}

static void
w_byte(c, arg)
    char c;
    struct dump_arg *arg;
{
    w_nbyte(&c, 1, arg);
}

static void
w_bytes(s, n, arg)
    const char *s;
    int n;
    struct dump_arg *arg;
{
    w_long(n, arg);
    w_nbyte(s, n, arg);
}

static void
w_short(x, arg)
    int x;
    struct dump_arg *arg;
{
    w_byte((x >> 0) & 0xff, arg);
    w_byte((x >> 8) & 0xff, arg);
}

static void
w_long(x, arg)
    long x;
    struct dump_arg *arg;
{
    char buf[sizeof(long)+1];
    int i, len = 0;

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
	w_byte(x + 5, arg);
	return;
    }
    if (-124 < x && x < 0) {
	w_byte((x - 5)&0xff, arg);
	return;
    }
    for (i=1;i<sizeof(long)+1;i++) {
	buf[i] = x & 0xff;
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
    len = i;
    for (i=0;i<=len;i++) {
	w_byte(buf[i], arg);
    }
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

static int
save_mantissa(d, buf)
    double d;
    char *buf;
{
    int e, i = 0;
    unsigned long m;
    double n;

    d = modf(ldexp(frexp(fabs(d), &e), DECIMAL_MANT), &d);
    if (d > 0) {
	buf[i++] = 0;
	do {
	    d = modf(ldexp(d, MANT_BITS), &n);
	    m = (unsigned long)n;
#if MANT_BITS > 24
	    buf[i++] = m >> 24;
#endif
#if MANT_BITS > 16
	    buf[i++] = m >> 16;
#endif
#if MANT_BITS > 8
	    buf[i++] = m >> 8;
#endif
	    buf[i++] = m;
	} while (d > 0);
	while (!buf[i - 1]) --i;
    }
    return i;
}

static double
load_mantissa(d, buf, len)
    double d;
    const char *buf;
    int len;
{
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
#define save_mantissa(d, buf) 0
#endif

#ifdef DBL_DIG
#define FLOAT_DIG (DBL_DIG+2)
#else
#define FLOAT_DIG 17
#endif

static void
w_float(d, arg)
    double d;
    struct dump_arg *arg;
{
    char buf[100];

    if (isinf(d)) {
	if (d < 0) strcpy(buf, "-inf");
	else       strcpy(buf, "inf");
    }
    else if (isnan(d)) {
	strcpy(buf, "nan");
    }
    else if (d == 0.0) {
	if (1.0/d < 0) strcpy(buf, "-0");
	else           strcpy(buf, "0");
    }
    else {
	int len;

	/* xxx: should not use system's sprintf(3) */
	sprintf(buf, "%.*g", FLOAT_DIG, d);
	len = strlen(buf);
	w_bytes(buf, len + save_mantissa(d, buf + len), arg);
	return;
    }
    w_bytes(buf, strlen(buf), arg);
}

static void
w_symbol(id, arg)
    ID id;
    struct dump_arg *arg;
{
    const char *sym = rb_id2name(id);
    st_data_t num;

    if (st_lookup(arg->symbols, id, &num)) {
	w_byte(TYPE_SYMLINK, arg);
	w_long((long)num, arg);
    }
    else {
	w_byte(TYPE_SYMBOL, arg);
	w_bytes(sym, strlen(sym), arg);
	st_add_direct(arg->symbols, id, arg->symbols->num_entries);
    }
}

static void
w_unique(s, arg)
    const char *s;
    struct dump_arg *arg;
{
    if (s[0] == '#') {
	rb_raise(rb_eTypeError, "can't dump anonymous class %s", s);
    }
    w_symbol(rb_intern(s), arg);
}

static void w_object _((VALUE,struct dump_arg*,int));

static int
hash_each(key, value, arg)
    VALUE key, value;
    struct dump_call_arg *arg;
{
    w_object(key, arg->arg, arg->limit);
    w_object(value, arg->arg, arg->limit);
    return ST_CONTINUE;
}

static void
w_extended(klass, arg, check)
    VALUE klass;
    struct dump_arg *arg;
    int check;
{
    const char *path;

    if (check && FL_TEST(klass, FL_SINGLETON)) {
	if (RCLASS(klass)->m_tbl->num_entries ||
	    (RCLASS(klass)->iv_tbl && RCLASS(klass)->iv_tbl->num_entries > 1)) {
	    rb_raise(rb_eTypeError, "singleton can't be dumped");
	}
	klass = RCLASS(klass)->super;
    }
    while (BUILTIN_TYPE(klass) == T_ICLASS) {
	path = rb_class2name(RBASIC(klass)->klass);
	w_byte(TYPE_EXTENDED, arg);
	w_unique(path, arg);
	klass = RCLASS(klass)->super;
    }
}

static void
w_class(type, obj, arg, check)
    int type;
    VALUE obj;
    struct dump_arg *arg;
    int check;
{
    char *path;

    VALUE klass = CLASS_OF(obj);
    w_extended(klass, arg, check);
    w_byte(type, arg);
    path = RSTRING(class2path(rb_class_real(klass)))->ptr;
    w_unique(path, arg);
}

static void
w_uclass(obj, base_klass, arg)
    VALUE obj, base_klass;
    struct dump_arg *arg;
{
    VALUE klass = CLASS_OF(obj);

    w_extended(klass, arg, Qtrue);
    klass = rb_class_real(klass);
    if (klass != base_klass) {
	w_byte(TYPE_UCLASS, arg);
	w_unique(RSTRING(class2path(klass))->ptr, arg);
    }
}

static int
w_obj_each(id, value, arg)
    ID id;
    VALUE value;
    struct dump_call_arg *arg;
{
    w_symbol(id, arg->arg);
    w_object(value, arg->arg, arg->limit);
    return ST_CONTINUE;
}

static void
w_ivar(tbl, arg)
    st_table *tbl;
    struct dump_call_arg *arg;
{
    if (tbl) {
	w_long(tbl->num_entries, arg->arg);
	st_foreach_safe(tbl, w_obj_each, (st_data_t)arg);
    }
    else {
	w_long(0, arg->arg);
    }
}

static void
w_object(obj, arg, limit)
    VALUE obj;
    struct dump_arg *arg;
    int limit;
{
    struct dump_call_arg c_arg;
    st_table *ivtbl = 0;
    st_data_t num;

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

    if ((ivtbl = rb_generic_ivar_table(obj)) != 0) {
	w_byte(TYPE_IVAR, arg);
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
	w_symbol(SYM2ID(obj), arg);
    }
    else {
	if (OBJ_TAINTED(obj)) arg->taint = Qtrue;

	st_add_direct(arg->data, obj, arg->data->num_entries);
	if (rb_respond_to(obj, s_mdump)) {
	    volatile VALUE v;

	    v = rb_funcall(obj, s_mdump, 0, 0);
	    check_dump_arg(arg, s_mdump);
	    w_class(TYPE_USRMARSHAL, obj, arg, Qfalse);
	    w_object(v, arg, limit);
	    if (ivtbl) w_ivar(0, &c_arg);
	    return;
	}
	if (rb_respond_to(obj, s_dump)) {
	    VALUE v;

	    v = rb_funcall(obj, s_dump, 1, INT2NUM(limit));
	    check_dump_arg(arg, s_dump);
	    if (TYPE(v) != T_STRING) {
		rb_raise(rb_eTypeError, "_dump() must return string");
	    }
	    if (!ivtbl && (ivtbl = rb_generic_ivar_table(v))) {
		w_byte(TYPE_IVAR, arg);
	    }
	    w_class(TYPE_USERDEF, obj, arg, Qfalse);
	    w_bytes(RSTRING(v)->ptr, RSTRING(v)->len, arg);
	    if (ivtbl) {
		w_ivar(ivtbl, &c_arg);
	    }
	    return;
	}

	switch (BUILTIN_TYPE(obj)) {
	  case T_CLASS:
	    if (FL_TEST(obj, FL_SINGLETON)) {
		rb_raise(rb_eTypeError, "singleton class can't be dumped");
	    }
	    w_byte(TYPE_CLASS, arg);
	    {
		VALUE path = class2path(obj);
		w_bytes(RSTRING(path)->ptr, RSTRING(path)->len, arg);
	    }
	    break;

	  case T_MODULE:
	    w_byte(TYPE_MODULE, arg);
	    {
		VALUE path = class2path(obj);
		w_bytes(RSTRING(path)->ptr, RSTRING(path)->len, arg);
	    }
	    break;

	  case T_FLOAT:
	    w_byte(TYPE_FLOAT, arg);
	    w_float(RFLOAT(obj)->value, arg);
	    break;

	  case T_BIGNUM:
	    w_byte(TYPE_BIGNUM, arg);
	    {
		char sign = RBIGNUM(obj)->sign ? '+' : '-';
		long len = RBIGNUM(obj)->len;
		BDIGIT *d = RBIGNUM(obj)->digits;

		w_byte(sign, arg);
		w_long(SHORTLEN(len), arg); /* w_short? */
		while (len--) {
#if SIZEOF_BDIGITS > SIZEOF_SHORT
		    BDIGIT num = *d;
		    int i;

		    for (i=0; i<SIZEOF_BDIGITS; i+=SIZEOF_SHORT) {
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
	    w_bytes(RSTRING(obj)->ptr, RSTRING(obj)->len, arg);
	    break;

	  case T_REGEXP:
	    w_uclass(obj, rb_cRegexp, arg);
	    w_byte(TYPE_REGEXP, arg);
	    w_bytes(RREGEXP(obj)->str, RREGEXP(obj)->len, arg);
	    w_byte(rb_reg_options(obj), arg);
	    break;

	  case T_ARRAY:
	    w_uclass(obj, rb_cArray, arg);
	    w_byte(TYPE_ARRAY, arg);
	    {
		long len = RARRAY(obj)->len;
		VALUE *ptr = RARRAY(obj)->ptr;

		w_long(len, arg);
		while (len--) {
		    w_object(*ptr, arg, limit);
		    ptr++;
		}
	    }
	    break;

	  case T_HASH:
	    w_uclass(obj, rb_cHash, arg);
	    if (NIL_P(RHASH(obj)->ifnone)) {
		w_byte(TYPE_HASH, arg);
	    }
	    else if (FL_TEST(obj, FL_USER2)) {
		/* FL_USER2 means HASH_PROC_DEFAULT (see hash.c) */
		rb_raise(rb_eTypeError, "can't dump hash with default proc");
	    }
	    else {
		w_byte(TYPE_HASH_DEF, arg);
	    }
	    w_long(RHASH(obj)->tbl->num_entries, arg);
	    rb_hash_foreach(obj, hash_each, (st_data_t)&c_arg);
	    if (!NIL_P(RHASH(obj)->ifnone)) {
		w_object(RHASH(obj)->ifnone, arg, limit);
	    }
	    break;

	  case T_STRUCT:
	    w_class(TYPE_STRUCT, obj, arg, Qtrue);
	    {
		long len = RSTRUCT(obj)->len;
		VALUE mem;
		long i;

		w_long(len, arg);
		mem = rb_struct_members(obj);
		for (i=0; i<len; i++) {
		    w_symbol(SYM2ID(RARRAY(mem)->ptr[i]), arg);
		    w_object(RSTRUCT(obj)->ptr[i], arg, limit);
		}
	    }
	    break;

	  case T_OBJECT:
	    w_class(TYPE_OBJECT, obj, arg, Qtrue);
	    w_ivar(ROBJECT(obj)->iv_tbl, &c_arg);
	    break;

	  case T_DATA:
	    {
		VALUE v;

		if (!rb_respond_to(obj, s_dump_data)) {
		    rb_raise(rb_eTypeError,
			     "no marshal_dump is defined for class %s",
			     rb_obj_classname(obj));
		}
		v = rb_funcall(obj, s_dump_data, 0);
		check_dump_arg(arg, s_dump_data);
		w_class(TYPE_DATA, obj, arg, Qtrue);
		w_object(v, arg, limit);
	    }
	    break;

	  default:
	    rb_raise(rb_eTypeError, "can't dump %s",
		     rb_obj_classname(obj));
	    break;
	}
    }
    if (ivtbl) {
	w_ivar(ivtbl, &c_arg);
    }
}

static VALUE
dump(arg)
    struct dump_call_arg *arg;
{
    w_object(arg->obj, arg->arg, arg->limit);
    if (arg->arg->dest) {
	rb_io_write(arg->arg->dest, arg->arg->str);
	rb_str_resize(arg->arg->str, 0);
    }
    return 0;
}

static VALUE
dump_ensure(arg)
    struct dump_arg *arg;
{
    if (!DATA_PTR(arg->wrapper)) return 0;
    st_free_table(arg->symbols);
    st_free_table(arg->data);
    DATA_PTR(arg->wrapper) = 0;
    arg->wrapper = 0;
    if (arg->taint) {
	OBJ_TAINT(arg->str);
    }

    return 0;
}

/*
 * call-seq:
 *      dump( obj [, anIO] , limit=--1 ) => anIO
 *
 * Serializes obj and all descendent objects. If anIO is
 * specified, the serialized data will be written to it, otherwise the
 * data will be returned as a String. If limit is specified, the
 * traversal of subobjects will be limited to that depth. If limit is
 * negative, no checking of depth will be performed.
 *
 *     class Klass
 *       def initialize(str)
 *         @str = str
 *       end
 *       def sayHello
 *         @str
 *       end
 *     end
 *
 * (produces no output)
 *
 *     o = Klass.new("hello\n")
 *     data = Marshal.dump(o)
 *     obj = Marshal.load(data)
 *     obj.sayHello   #=> "hello\n"
 */
static VALUE
marshal_dump(argc, argv)
    int argc;
    VALUE* argv;
{
    VALUE obj, port, a1, a2;
    int limit = -1;
    struct dump_arg arg;
    struct dump_call_arg c_arg;

    port = Qnil;
    rb_scan_args(argc, argv, "12", &obj, &a1, &a2);
    if (argc == 3) {
	if (!NIL_P(a2)) limit = NUM2INT(a2);
	if (NIL_P(a1)) goto type_error;
	port = a1;
    }
    else if (argc == 2) {
	if (FIXNUM_P(a1)) limit = FIX2INT(a1);
	else if (NIL_P(a1)) goto type_error;
	else port = a1;
    }
    arg.dest = 0;
    arg.symbols = st_init_numtable();
    arg.data    = st_init_numtable();
    arg.taint   = Qfalse;
    arg.str = rb_str_buf_new(0);
    RBASIC(arg.str)->klass = 0;
    arg.wrapper = Data_Wrap_Struct(rb_cData, mark_dump_arg, 0, &arg);
    if (!NIL_P(port)) {
	if (!rb_respond_to(port, s_write)) {
	  type_error:
	    rb_raise(rb_eTypeError, "instance of IO needed");
	}
	arg.dest = port;
	if (rb_respond_to(port, s_binmode)) {
	    rb_funcall2(port, s_binmode, 0, 0);
	    check_dump_arg(&arg, s_binmode);
	}
    }
    else {
	port = arg.str;
    }

    c_arg.obj   = obj;
    c_arg.arg   = &arg;
    c_arg.limit = limit;

    w_byte(MARSHAL_MAJOR, &arg);
    w_byte(MARSHAL_MINOR, &arg);

    rb_ensure(dump, (VALUE)&c_arg, dump_ensure, (VALUE)&arg);
    RBASIC(arg.str)->klass = rb_cString;

    return port;
}

struct load_arg {
    VALUE src;
    long offset;
    st_table *symbols;
    st_table *data;
    VALUE proc;
    int taint;
    VALUE wrapper;
};

static void
check_load_arg(arg, sym)
    struct load_arg *arg;
    ID sym;
{
    if (!DATA_PTR(arg->wrapper)) {
        rb_raise(rb_eRuntimeError, "Marshal.load reentered at %s",
		 rb_id2name(sym));
    }
}

static void
mark_load_arg(ptr)
    void *ptr;
{
    struct load_arg *p = ptr;
    if (!ptr)
        return;
    rb_mark_tbl(p->data);
}

static VALUE r_object _((struct load_arg *arg));

static int
r_byte(arg)
    struct load_arg *arg;
{
    int c;

    if (TYPE(arg->src) == T_STRING) {
	if (RSTRING(arg->src)->len > arg->offset) {
	    c = (unsigned char)RSTRING(arg->src)->ptr[arg->offset++];
	}
	else {
	    rb_raise(rb_eArgError, "marshal data too short");
	}
    }
    else {
	VALUE src = arg->src;
	VALUE v = rb_funcall2(src, s_getc, 0, 0);
	check_load_arg(arg, s_getc);
	if (NIL_P(v)) rb_eof_error();
	c = (unsigned char)FIX2INT(v);
    }
    return c;
}

static void
long_toobig(size)
    int size;
{
    rb_raise(rb_eTypeError, "long too big for this architecture (size %d, given %d)",
	     sizeof(long), size);
}

#undef SIGN_EXTEND_CHAR
#if __STDC__
# define SIGN_EXTEND_CHAR(c) ((signed char)(c))
#else  /* not __STDC__ */
/* As in Harbison and Steele.  */
# define SIGN_EXTEND_CHAR(c) ((((unsigned char)(c)) ^ 128) - 128)
#endif

static long
r_long(arg)
    struct load_arg *arg;
{
    register long x;
    int c = SIGN_EXTEND_CHAR(r_byte(arg));
    long i;

    if (c == 0) return 0;
    if (c > 0) {
	if (4 < c && c < 128) {
	    return c - 5;
	}
	if (c > sizeof(long)) long_toobig(c);
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
	if (c > sizeof(long)) long_toobig(c);
	x = -1;
	for (i=0;i<c;i++) {
	    x &= ~((long)0xff << (8*i));
	    x |= (long)r_byte(arg) << (8*i);
	}
    }
    return x;
}

#define r_bytes(arg) r_bytes0(r_long(arg), (arg))

static VALUE
r_bytes0(len, arg)
    long len;
    struct load_arg *arg;
{
    VALUE str;

    if (len == 0) return rb_str_new(0, 0);
    if (TYPE(arg->src) == T_STRING) {
	if (RSTRING(arg->src)->len - arg->offset >= len) {
	    str = rb_str_new(RSTRING(arg->src)->ptr+arg->offset, len);
	    arg->offset += len;
	}
	else {
	  too_short:
	    rb_raise(rb_eArgError, "marshal data too short");
	}
    }
    else {
	VALUE src = arg->src;
	VALUE n = LONG2NUM(len);
	str = rb_funcall2(src, s_read, 1, &n);
	check_load_arg(arg, s_read);
	if (NIL_P(str)) goto too_short;
	StringValue(str);
	if (RSTRING(str)->len != len) goto too_short;
	if (OBJ_TAINTED(str)) arg->taint = Qtrue;
    }
    return str;
}

static ID
r_symlink(arg)
    struct load_arg *arg;
{
    ID id;
    long num = r_long(arg);

    if (st_lookup(arg->symbols, num, &id)) {
	return id;
    }
    rb_raise(rb_eArgError, "bad symbol");
}

static ID
r_symreal(arg)
    struct load_arg *arg;
{
    ID id;

    id = rb_intern(RSTRING(r_bytes(arg))->ptr);
    st_insert(arg->symbols, arg->symbols->num_entries, id);

    return id;
}

static ID
r_symbol(arg)
    struct load_arg *arg;
{
    if (r_byte(arg) == TYPE_SYMLINK) {
	return r_symlink(arg);
    }
    return r_symreal(arg);
}

static const char*
r_unique(arg)
    struct load_arg *arg;
{
    return rb_id2name(r_symbol(arg));
}

static VALUE
r_string(arg)
    struct load_arg *arg;
{
    return r_bytes(arg);
}

static VALUE
r_entry(v, arg)
    VALUE v;
    struct load_arg *arg;
{
    st_insert(arg->data, arg->data->num_entries, (st_data_t)v);
    if (arg->taint) OBJ_TAINT(v);
    return v;
}

static void
r_ivar(obj, arg)
    VALUE obj;
    struct load_arg *arg;
{
    long len;

    len = r_long(arg);
    if (len > 0) {
	while (len--) {
	    ID id = r_symbol(arg);
	    VALUE val = r_object(arg);
	    rb_ivar_set(obj, id, val);
	}
    }
}

static VALUE
path2class(path)
    const char *path;
{
    VALUE v = rb_path2class(path);

    if (TYPE(v) != T_CLASS) {
	rb_raise(rb_eArgError, "%s does not refer class", path);
    }
    return v;
}

static VALUE
path2module(path)
    const char *path;
{
    VALUE v = rb_path2class(path);

    if (TYPE(v) != T_MODULE) {
	rb_raise(rb_eArgError, "%s does not refer module", path);
    }
    return v;
}

static VALUE
r_object0(arg, proc, ivp, extmod)
    struct load_arg *arg;
    VALUE proc;
    int *ivp;
    VALUE extmod;
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
	v = (st_data_t)link;
	return v;

      case TYPE_IVAR:
        {
	    int ivar = Qtrue;

	    v = r_object0(arg, 0, &ivar, extmod);
	    if (ivar) r_ivar(v, arg);
	}
	break;

      case TYPE_EXTENDED:
	{
	    VALUE m = path2module(r_unique(arg));

            if (NIL_P(extmod)) extmod = rb_ary_new2(0);
            rb_ary_push(extmod, m);

	    v = r_object0(arg, 0, 0, extmod);
            while (RARRAY(extmod)->len > 0) {
                m = rb_ary_pop(extmod);
                rb_extend_object(v, m);
            }
	}
	break;

      case TYPE_UCLASS:
	{
	    VALUE c = path2class(r_unique(arg));

	    if (FL_TEST(c, FL_SINGLETON)) {
		rb_raise(rb_eTypeError, "singleton can't be loaded");
	    }
	    v = r_object0(arg, 0, 0, extmod);
	    if (rb_special_const_p(v) || TYPE(v) == T_OBJECT || TYPE(v) == T_CLASS) {
	      format_error:
		rb_raise(rb_eArgError, "dump format error (user class)");
	    }
	    if (TYPE(v) == T_MODULE || !RTEST(rb_class_inherited_p(c, RBASIC(v)->klass))) {
		VALUE tmp = rb_obj_alloc(c);

		if (TYPE(v) != TYPE(tmp)) goto format_error;
	    }
	    RBASIC(v)->klass = c;
	}
	break;

      case TYPE_NIL:
	v = Qnil;
	break;

      case TYPE_TRUE:
	v = Qtrue;
	break;

      case TYPE_FALSE:
	v = Qfalse;
	break;

      case TYPE_FIXNUM:
	{
	    long i = r_long(arg);
	    v = LONG2FIX(i);
	}
	break;

      case TYPE_FLOAT:
	{
	    double d, t = 0.0;
	    VALUE str = r_bytes(arg);
	    const char *ptr = RSTRING(str)->ptr;

	    if (strcmp(ptr, "nan") == 0) {
		d = t / t;
	    }
	    else if (strcmp(ptr, "inf") == 0) {
		d = 1.0 / t;
	    }
	    else if (strcmp(ptr, "-inf") == 0) {
		d = -1.0 / t;
	    }
	    else {
		char *e;
		d = strtod(ptr, &e);
		d = load_mantissa(d, e, RSTRING(str)->len - (e - ptr));
	    }
	    v = rb_float_new(d);
	    r_entry(v, arg);
	}
	break;

      case TYPE_BIGNUM:
	{
	    long len;
	    BDIGIT *digits;
	    volatile VALUE data;

	    NEWOBJ(big, struct RBignum);
	    OBJSETUP(big, rb_cBignum, T_BIGNUM);
	    big->sign = (r_byte(arg) == '+');
	    len = r_long(arg);
	    data = r_bytes0(len * 2, arg);
#if SIZEOF_BDIGITS == SIZEOF_SHORT
	    big->len = len;
#else
	    big->len = (len + 1) * 2 / sizeof(BDIGIT);
#endif
	    big->digits = digits = ALLOC_N(BDIGIT, big->len);
	    MEMCPY(digits, RSTRING(data)->ptr, char, len * 2);
#if SIZEOF_BDIGITS > SIZEOF_SHORT
	    MEMZERO((char *)digits + len * 2, char,
		    big->len * sizeof(BDIGIT) - len * 2);
#endif
	    len = big->len;
	    while (len > 0) {
		unsigned char *p = (unsigned char *)digits;
		BDIGIT num = 0;
#if SIZEOF_BDIGITS > SIZEOF_SHORT
		int shift = 0;
		int i;

		for (i=0; i<SIZEOF_BDIGITS; i++) {
		    num |= (int)p[i] << shift;
		    shift += 8;
		}
#else
		num = p[0] | (p[1] << 8);
#endif
		*digits++ = num;
		len--;
	    }
	    v = rb_big_norm((VALUE)big);
	    r_entry(v, arg);
	}
	break;

      case TYPE_STRING:
	v = r_entry(r_string(arg), arg);
	break;

      case TYPE_REGEXP:
	{
	    volatile VALUE str = r_bytes(arg);
	    int options = r_byte(arg);
	    v = r_entry(rb_reg_new(RSTRING(str)->ptr, RSTRING(str)->len, options), arg);
	}
	break;

      case TYPE_ARRAY:
	{
	    volatile long len = r_long(arg); /* gcc 2.7.2.3 -O2 bug?? */

	    v = rb_ary_new2(len);
	    r_entry(v, arg);
	    while (len--) {
		rb_ary_push(v, r_object(arg));
	    }
	}
	break;

      case TYPE_HASH:
      case TYPE_HASH_DEF:
	{
	    long len = r_long(arg);

	    v = rb_hash_new();
	    r_entry(v, arg);
	    while (len--) {
		VALUE key = r_object(arg);
		VALUE value = r_object(arg);
		rb_hash_aset(v, key, value);
	    }
	    if (type == TYPE_HASH_DEF) {
		RHASH(v)->ifnone = r_object(arg);
	    }
	}
	break;

      case TYPE_STRUCT:
	{
	    VALUE klass, mem, values;
	    volatile long i;	/* gcc 2.7.2.3 -O2 bug?? */
	    long len;
	    ID slot;

	    klass = path2class(r_unique(arg));
	    mem = rb_struct_s_members(klass);
	    len = r_long(arg);

	    values = rb_ary_new2(len);
	    for (i=0; i<len; i++) {
		rb_ary_push(values, Qnil);
	    }
	    v = rb_struct_alloc(klass, values);
	    r_entry(v, arg);
	    for (i=0; i<len; i++) {
		slot = r_symbol(arg);

		if (RARRAY(mem)->ptr[i] != ID2SYM(slot)) {
		    rb_raise(rb_eTypeError, "struct %s not compatible (:%s for :%s)",
			     rb_class2name(klass),
			     rb_id2name(slot),
			     rb_id2name(SYM2ID(RARRAY(mem)->ptr[i])));
		}
		rb_struct_aset(v, LONG2FIX(i), r_object(arg));
	    }
	}
	break;

      case TYPE_USERDEF:
        {
	    VALUE klass = path2class(r_unique(arg));
	    VALUE data;

	    if (!rb_respond_to(klass, s_load)) {
		rb_raise(rb_eTypeError, "class %s needs to have method `_load'",
			 rb_class2name(klass));
	    }
	    data = r_string(arg);
	    if (ivp) {
		r_ivar(data, arg);
		*ivp = Qfalse;
	    }
	    v = rb_funcall(klass, s_load, 1, data);
	    check_load_arg(arg, s_load);
	    r_entry(v, arg);
	}
        break;

      case TYPE_USRMARSHAL:
        {
	    VALUE klass = path2class(r_unique(arg));
	    VALUE data;

	    v = rb_obj_alloc(klass);
            if (! NIL_P(extmod)) {
                while (RARRAY(extmod)->len > 0) {
                    VALUE m = rb_ary_pop(extmod);
                    rb_extend_object(v, m);
                }
            }
	    if (!rb_respond_to(v, s_mload)) {
		rb_raise(rb_eTypeError, "instance of %s needs to have method `marshal_load'",
			 rb_class2name(klass));
	    }
	    r_entry(v, arg);
	    data = r_object(arg);
	    rb_funcall(v, s_mload, 1, data);
	    check_load_arg(arg, s_mload);
	}
        break;

      case TYPE_OBJECT:
	{
	    VALUE klass = path2class(r_unique(arg));

	    v = rb_obj_alloc(klass);
	    if (TYPE(v) != T_OBJECT) {
		rb_raise(rb_eArgError, "dump format error");
	    }
	    r_entry(v, arg);
	    r_ivar(v, arg);
	}
	break;

      case TYPE_DATA:
       {
           VALUE klass = path2class(r_unique(arg));
           if (rb_respond_to(klass, s_alloc)) {
	       static int warn = Qtrue;
	       if (warn) {
		   rb_warn("define `allocate' instead of `_alloc'");
		   warn = Qfalse;
	       }
	       v = rb_funcall(klass, s_alloc, 0);
	       check_load_arg(arg, s_alloc);
           }
	   else {
	       v = rb_obj_alloc(klass);
	   }
           if (TYPE(v) != T_DATA) {
               rb_raise(rb_eArgError, "dump format error");
           }
           r_entry(v, arg);
           if (!rb_respond_to(v, s_load_data)) {
               rb_raise(rb_eTypeError,
                        "class %s needs to have instance method `_load_data'",
                        rb_class2name(klass));
           }
           rb_funcall(v, s_load_data, 1, r_object0(arg, 0, 0, extmod));
	   check_load_arg(arg, s_load_data);
       }
       break;

      case TYPE_MODULE_OLD:
        {
	    volatile VALUE str = r_bytes(arg);

	    v = rb_path2class(RSTRING(str)->ptr);
	    r_entry(v, arg);
	}
	break;

      case TYPE_CLASS:
        {
	    volatile VALUE str = r_bytes(arg);

	    v = path2class(RSTRING(str)->ptr);
	    r_entry(v, arg);
	}
	break;

      case TYPE_MODULE:
        {
	    volatile VALUE str = r_bytes(arg);

	    v = path2module(RSTRING(str)->ptr);
	    r_entry(v, arg);
	}
	break;

      case TYPE_SYMBOL:
	v = ID2SYM(r_symreal(arg));
	break;

      case TYPE_SYMLINK:
	return ID2SYM(r_symlink(arg));

      default:
	rb_raise(rb_eArgError, "dump format error(0x%x)", type);
	break;
    }
    if (proc) {
	rb_funcall(proc, s_call, 1, v);
	check_load_arg(arg, s_call);
    }
    return v;
}

static VALUE
r_object(arg)
    struct load_arg *arg;
{
    return r_object0(arg, arg->proc, 0, Qnil);
}

static VALUE
load(arg)
    struct load_arg *arg;
{
    return r_object(arg);
}

static VALUE
load_ensure(arg)
    struct load_arg *arg;
{
    if (!DATA_PTR(arg->wrapper)) return 0;
    st_free_table(arg->symbols);
    st_free_table(arg->data);
    DATA_PTR(arg->wrapper) = 0;
    arg->wrapper = 0;
    return 0;
}

/*
 * call-seq:
 *     load( source [, proc] ) => obj
 *     restore( source [, proc] ) => obj
 * 
 * Returns the result of converting the serialized data in source into a
 * Ruby object (possibly with associated subordinate objects). source
 * may be either an instance of IO or an object that responds to
 * to_str. If proc is specified, it will be passed each object as it
 * is deserialized.
 */
static VALUE
marshal_load(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE port, proc;
    int major, minor, taint = Qfalse;
    VALUE v;
    struct load_arg arg;

    rb_scan_args(argc, argv, "11", &port, &proc);
    v = rb_check_string_type(port);
    if (!NIL_P(v)) {
	taint = OBJ_TAINTED(port); /* original taintedness */
	port = v;
    }
    else if (rb_respond_to(port, s_getc) && rb_respond_to(port, s_read)) {
	if (rb_respond_to(port, s_binmode)) {
	    rb_funcall2(port, s_binmode, 0, 0);
	}
	taint = Qtrue;
    }
    else {
	rb_raise(rb_eTypeError, "instance of IO needed");
    }
    arg.src = port;
    arg.offset = 0;
    arg.symbols = st_init_numtable();
    arg.data    = st_init_numtable();
    arg.proc = 0;
    arg.wrapper = Data_Wrap_Struct(rb_cData, mark_load_arg, 0, &arg);
    arg.taint = taint;

    major = r_byte(&arg);
    minor = r_byte(&arg);
    if (major != MARSHAL_MAJOR || minor > MARSHAL_MINOR) {
	rb_raise(rb_eTypeError, "incompatible marshal file format (can't be read)\n\
\tformat version %d.%d required; %d.%d given",
		 MARSHAL_MAJOR, MARSHAL_MINOR, major, minor);
    }
    if (RTEST(ruby_verbose) && minor != MARSHAL_MINOR) {
	rb_warn("incompatible marshal file format (can be read)\n\
\tformat version %d.%d required; %d.%d given",
		MARSHAL_MAJOR, MARSHAL_MINOR, major, minor);
    }

    if (!NIL_P(proc)) arg.proc = proc;
    v = rb_ensure(load, (VALUE)&arg, load_ensure, (VALUE)&arg);

    return v;
}

/*
 * The marshaling library converts collections of Ruby objects into a
 * byte stream, allowing them to be stored outside the currently
 * active script. This data may subsequently be read and the original
 * objects reconstituted.
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
 *     RUBY_VERSION   #=> "1.8.0"
 *     str[0]         #=> 4
 *     str[1]         #=> 8
 *
 * Some objects cannot be dumped: if the objects to be dumped include
 * bindings, procedure or method objects, instances of class IO, or
 * singleton objects, a TypeError will be raised.
 * If your class has special serialization needs (for example, if you
 * want to serialize in some specific format), or if it contains
 * objects that would otherwise not be serializable, you can implement
 * your own serialization strategy by defining two methods, _dump and
 * _load:
 * The instance method _dump should return a String object containing
 * all the information necessary to reconstitute objects of this class
 * and all referenced objects up to a maximum depth given as an integer
 * parameter (a value of -1 implies that you should disable depth checking).
 * The class method _load should take a String and return an object of this class.
 */
void
Init_marshal()
{
    VALUE rb_mMarshal = rb_define_module("Marshal");

    s_dump = rb_intern("_dump");
    s_load = rb_intern("_load");
    s_mdump = rb_intern("marshal_dump");
    s_mload = rb_intern("marshal_load");
    s_dump_data = rb_intern("_dump_data");
    s_load_data = rb_intern("_load_data");
    s_alloc = rb_intern("_alloc");
    s_call = rb_intern("call");
    s_getc = rb_intern("getc");
    s_read = rb_intern("read");
    s_write = rb_intern("write");
    s_binmode = rb_intern("binmode");

    rb_define_module_function(rb_mMarshal, "dump", marshal_dump, -1);
    rb_define_module_function(rb_mMarshal, "load", marshal_load, -1);
    rb_define_module_function(rb_mMarshal, "restore", marshal_load, -1);

    rb_define_const(rb_mMarshal, "MAJOR_VERSION", INT2FIX(MARSHAL_MAJOR));
    rb_define_const(rb_mMarshal, "MINOR_VERSION", INT2FIX(MARSHAL_MINOR));
}

VALUE
rb_marshal_dump(obj, port)
    VALUE obj, port;
{
    int argc = 1;
    VALUE argv[2];

    argv[0] = obj;
    argv[1] = port;
    if (!NIL_P(port)) argc = 2;
    return marshal_dump(argc, argv);
}

VALUE
rb_marshal_load(port)
    VALUE port;
{
    return marshal_load(1, &port);
}
