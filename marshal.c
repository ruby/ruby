/**********************************************************************

  marshal.c -

  $Author$
  $Date$
  created at: Thu Apr 27 16:30:01 JST 1995

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "st.h"

#if !defined(atof) && !defined(HAVE_STDLIB_H)
double strtod();
#endif

#if SIZEOF_INT*2 <= SIZEOF_LONG_LONG || SIZEOF_INT*2 <= SIZEOF___INT64
typedef unsigned int BDIGIT;
#define SIZEOF_BDIGITS SIZEOF_INT
#else
typedef unsigned short BDIGIT;
#define SIZEOF_BDIGITS SIZEOF_SHORT
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
#define MARSHAL_MINOR   6

#define TYPE_NIL	'0'
#define TYPE_TRUE	'T'
#define TYPE_FALSE	'F'
#define TYPE_FIXNUM	'i'

#define TYPE_UCLASS	'C'
#define TYPE_OBJECT	'o'
#define TYPE_USERDEF	'u'
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

static ID s_dump, s_load;

struct dump_arg {
    VALUE obj;
    FILE *fp;
    VALUE str;
    st_table *symbol;
    st_table *data;
    int taint;
};

struct dump_call_arg {
    VALUE obj;
    struct dump_arg *arg;
    int limit;
};

static void w_long _((long, struct dump_arg*));

static void
w_byte(c, arg)
    char c;
    struct dump_arg *arg;
{
    if (arg->fp) putc(c, arg->fp);
    else rb_str_cat(arg->str, &c, 1);
}

static void
w_bytes(s, n, arg)
    char *s;
    int n;
    struct dump_arg *arg;
{
    w_long(n, arg);
    if (arg->fp) {
	fwrite(s, 1, n, arg->fp);
    }
    else {
	rb_str_cat(arg->str, s, n);
    }
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

static void
w_float(d, arg)
    double d;
    struct dump_arg *arg;
{
    char buf[100];

    sprintf(buf, "%.16g", d);
    w_bytes(buf, strlen(buf), arg);
}

static void
w_symbol(id, arg)
    ID id;
    struct dump_arg *arg;
{
    char *sym = rb_id2name(id);
    long num;

    if (st_lookup(arg->symbol, id, &num)) {
	w_byte(TYPE_SYMLINK, arg);
	w_long(num, arg);
    }
    else {
	w_byte(TYPE_SYMBOL, arg);
	w_bytes(sym, strlen(sym), arg);
	st_add_direct(arg->symbol, id, arg->symbol->num_entries);
    }
}

static void
w_unique(s, arg)
    char *s;
    struct dump_arg *arg;
{
    if (s[0] == '#') {
	rb_raise(rb_eArgError, "can't dump anonymous class %s", s);
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

static int
obj_each(id, value, arg)
    ID id;
    VALUE value;
    struct dump_call_arg *arg;
{
    w_symbol(id, arg->arg);
    w_object(value, arg->arg, arg->limit);
    return ST_CONTINUE;
}

static void
w_uclass(obj, klass, arg)
    VALUE obj, klass;
    struct dump_arg *arg;
{
    if (rb_obj_class(obj) != klass) {
	w_byte(TYPE_UCLASS, arg);
	w_unique(rb_class2name(CLASS_OF(obj)), arg);
    }
}

static void
w_ivar(tbl, arg)
    st_table *tbl;
    struct dump_call_arg *arg;
{
    if (tbl) {
	w_long(tbl->num_entries, arg->arg);
	st_foreach(tbl, obj_each, arg);
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

    if (limit == 0) {
	rb_raise(rb_eArgError, "exceed depth limit");
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
	    return;
	}
#endif
    }
    else if (SYMBOL_P(obj)) {
	w_symbol(SYM2ID(obj), arg);
	return;
    }
    else {
	long num;

	limit--;
	c_arg.limit = limit;
	c_arg.arg = arg;

	if (st_lookup(arg->data, obj, &num)) {
	    w_byte(TYPE_LINK, arg);
	    w_long(num, arg);
	    return;
	}

	if (OBJ_TAINTED(obj)) arg->taint = Qtrue;

	st_add_direct(arg->data, obj, arg->data->num_entries);
	if (rb_respond_to(obj, s_dump)) {
	    VALUE v;

	    w_byte(TYPE_USERDEF, arg);
	    w_unique(rb_class2name(CLASS_OF(obj)), arg);
	    v = rb_funcall(obj, s_dump, 1, INT2NUM(limit));
	    if (TYPE(v) != T_STRING) {
		rb_raise(rb_eTypeError, "_dump() must return String");
	    }
	    w_bytes(RSTRING(v)->ptr, RSTRING(v)->len, arg);
	    return;
	}

	if (ivtbl = rb_generic_ivar_table(obj)) {
	    w_byte(TYPE_IVAR, arg);
	}

	switch (BUILTIN_TYPE(obj)) {
	  case T_CLASS:
	    if (FL_TEST(obj, FL_SINGLETON)) {
		rb_raise(rb_eTypeError, "singleton class can't be dumped");
	    }
	    w_byte(TYPE_CLASS, arg);
	    {
		VALUE path = rb_class_path(obj);
		if (RSTRING(path)->ptr[0] == '#') {
		    rb_raise(rb_eArgError, "can't dump anonymous class %s",
			     RSTRING(path)->ptr);
		}
		w_bytes(RSTRING(path)->ptr, RSTRING(path)->len, arg);
	    }
	    break;

	  case T_MODULE:
	    w_byte(TYPE_MODULE, arg);
	    {
		VALUE path = rb_class_path(obj);
		if (RSTRING(path)->ptr[0] == '#') {
		    rb_raise(rb_eArgError, "can't dump anonymous module %s",
			     RSTRING(path)->ptr);
		}
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
		char sign = RBIGNUM(obj)->sign?'+':'-';
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
	    if (!NIL_P(RHASH(obj)->ifnone)) {
		w_byte(TYPE_HASH_DEF, arg);
	    }
	    else {
		w_byte(TYPE_HASH, arg);
	    }
	    w_long(RHASH(obj)->tbl->num_entries, arg);
	    st_foreach(RHASH(obj)->tbl, hash_each, &c_arg);
	    if (!NIL_P(RHASH(obj)->ifnone)) {
		w_object(RHASH(obj)->ifnone, arg, limit);
	    }
	    break;

	  case T_STRUCT:
	    w_byte(TYPE_STRUCT, arg);
	    {
		long len = RSTRUCT(obj)->len;
		VALUE c, mem;
		long i;

		c = CLASS_OF(obj);
		w_unique(rb_class2name(c), arg);
		w_long(len, arg);
		if (FL_TEST(c, FL_SINGLETON))
		    c = RCLASS(c)->super;
		mem = rb_ivar_get(c, rb_intern("__member__"));
		if (mem == Qnil) {
		    rb_raise(rb_eTypeError, "uninitialized struct");
		}
		for (i=0; i<len; i++) {
		    w_symbol(SYM2ID(RARRAY(mem)->ptr[i]), arg);
		    w_object(RSTRUCT(obj)->ptr[i], arg, limit);
		}
	    }
	    break;

	  case T_OBJECT:
	    w_byte(TYPE_OBJECT, arg);
	    {
		VALUE klass = CLASS_OF(obj);
		char *path;

		while (FL_TEST(klass, FL_SINGLETON) || BUILTIN_TYPE(klass) == T_ICLASS) {
		    if (RCLASS(klass)->m_tbl->num_entries > 0 ||
			RCLASS(klass)->iv_tbl->num_entries > 1) {
			rb_raise(rb_eTypeError, "singleton can't be dumped");
		    }
		    klass = RCLASS(klass)->super;
		}
		path = rb_class2name(klass);
		w_unique(path, arg);
		w_ivar(ROBJECT(obj)->iv_tbl, &c_arg);
	    }
	    break;

	  default:
	    rb_raise(rb_eTypeError, "can't dump %s",
		     rb_class2name(CLASS_OF(obj)));
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
    return 0;
}

static VALUE
dump_ensure(arg)
    struct dump_arg *arg;
{
    st_free_table(arg->symbol);
    st_free_table(arg->data);
    if (!arg->fp && arg->taint) {
	OBJ_TAINT(arg->str);
    }
    return 0;
}

static VALUE
marshal_dump(argc, argv)
    int argc;
    VALUE* argv;
{
    VALUE obj, port, a1, a2;
    int limit = -1;
    struct dump_arg arg;
    struct dump_call_arg c_arg;

    port = 0;
    rb_scan_args(argc, argv, "12", &obj, &a1, &a2);
    if (argc == 3) {
	if (!NIL_P(a2)) limit = NUM2INT(a2);
	port = a1;
    }
    else if (argc == 2) {
	if (FIXNUM_P(a1)) limit = FIX2INT(a1);
	else port = a1;
    }
    if (port) {
	if (rb_obj_is_kind_of(port, rb_cIO)) {
	    OpenFile *fptr;

	    rb_io_binmode(port);
	    GetOpenFile(port, fptr);
	    rb_io_check_writable(fptr);
	    arg.fp = (fptr->f2) ? fptr->f2 : fptr->f;
	}
	else {
	    rb_raise(rb_eTypeError, "instance of IO needed");
	}
    }
    else {
	arg.fp = 0;
	port = rb_str_new(0, 0);
	arg.str = port;
    }

    arg.symbol = st_init_numtable();
    arg.data   = st_init_numtable();
    arg.taint  = Qfalse;
    c_arg.obj = obj;
    c_arg.arg = &arg;
    c_arg.limit = limit;

    w_byte(MARSHAL_MAJOR, &arg);
    w_byte(MARSHAL_MINOR, &arg);

    rb_ensure(dump, (VALUE)&c_arg, dump_ensure, (VALUE)&arg);

    return port;
}

struct load_arg {
    FILE *fp;
    char *ptr, *end;
    st_table *symbol;
    VALUE data;
    VALUE proc;
    int taint;
};

static VALUE r_object _((struct load_arg *arg));

static int
r_byte(arg)
    struct load_arg *arg;
{
    int c;

    if (arg->fp) {
	c = rb_getc(arg->fp);
	if (c == EOF) rb_eof_error();
    }
    else if (arg->ptr < arg->end) {
	c = *(unsigned char*)arg->ptr++;
    }
    else {
	rb_raise(rb_eArgError, "marshal data too short");
    }
    return c;
}

static unsigned short
r_short(arg)
    struct load_arg *arg;
{
    unsigned short x;

    x =  r_byte(arg);
    x |= r_byte(arg)<<8;

    return x;
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

#define r_bytes2(s, len, arg) do {	\
    (len) = r_long(arg);		\
    (s) = ALLOCA_N(char,(len)+1);	\
    r_bytes0((s),(len),(arg));		\
} while (0)

#define r_bytes(s, arg) do {		\
    long r_bytes_len;			\
    r_bytes2((s), r_bytes_len, (arg));	\
} while (0)

static void
r_bytes0(s, len, arg)
    char *s;
    long len;
    struct load_arg *arg;
{
    if (arg->fp) {
	len = fread(s, 1, len, arg->fp);
    }
    else {
	if (arg->ptr + len > arg->end) {
	    len = arg->end - arg->ptr;
	}
	memcpy(s, arg->ptr, len);
	arg->ptr += len;
    }
    s[len] = '\0';
}

static ID
r_symlink(arg)
    struct load_arg *arg;
{
    ID id;
    long num = r_long(arg);

    if (st_lookup(arg->symbol, num, &id)) {
	return id;
    }
    rb_raise(rb_eTypeError, "bad symbol");
}

static ID
r_symreal(arg)
    struct load_arg *arg;
{
    char *buf;
    ID id;

    r_bytes(buf, arg);
    id = rb_intern(buf);
    st_insert(arg->symbol, arg->symbol->num_entries, id);

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

static char*
r_unique(arg)
    struct load_arg *arg;
{
    return rb_id2name(r_symbol(arg));
}

static VALUE
r_string(arg)
    struct load_arg *arg;
{
    char *buf;
    long len;

    r_bytes2(buf, len, arg);
    return rb_str_new(buf, len);
}

static VALUE
r_regist(v, arg)
    VALUE v;
    struct load_arg *arg;
{
    rb_hash_aset(arg->data, INT2FIX(RHASH(arg->data)->tbl->num_entries), v);
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
r_object(arg)
    struct load_arg *arg;
{
    VALUE v = Qnil;
    int type = r_byte(arg);
    long id;

    switch (type) {
      case TYPE_LINK:
	id = r_long(arg);
	v = rb_hash_aref(arg->data, INT2FIX(id));
	if (NIL_P(v)) {
	    rb_raise(rb_eArgError, "dump format error (unlinked)");
	}
	return v;

      case TYPE_IVAR:
	v = r_object(arg);
	r_ivar(v, arg);
	return v;

      case TYPE_UCLASS:
	{
	    VALUE c = rb_path2class(r_unique(arg));

	    if (FL_TEST(c, FL_SINGLETON)) {
		rb_raise(rb_eTypeError, "singleton can't be loaded");
	    }
	    v = r_object(arg);
	    if (rb_special_const_p(v) || TYPE(v) == T_OBJECT || TYPE(v) == T_CLASS) {
	      format_error:
		rb_raise(rb_eArgError, "dump format error (user class)");
	    }
	    if (TYPE(v) == T_MODULE || !RTEST(rb_funcall(c, '<', 1, RBASIC(v)->klass))) {
		VALUE tmp = rb_obj_alloc(c);

		if (TYPE(v) != TYPE(tmp)) goto format_error;
	    }
	    RBASIC(v)->klass = c;
	    return v;
	}

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
	    v = INT2FIX(i);
	}
	break;

      case TYPE_FLOAT:
	{
	    char *buf;
	    double d, t = 0.0;

	    r_bytes(buf, arg);
	    if (strcmp(buf, "nan") == 0) {
		d = t / t;
	    }
	    else if (strcmp(buf, "inf") == 0) {
		d = 1.0 / t;
	    }
	    else if (strcmp(buf, "-inf") == 0) {
		d = -1.0 / t;
	    }
	    else {
		/* xxx: should not use system's strtod(3) */
		d = strtod(buf, 0);
	    }
	    v = rb_float_new(d);
	    r_regist(v, arg);
	}
	break;

      case TYPE_BIGNUM:
	{
	    long len;
	    BDIGIT *digits;

	    NEWOBJ(big, struct RBignum);
	    OBJSETUP(big, rb_cBignum, T_BIGNUM);
	    big->sign = (r_byte(arg) == '+');
	    len = r_long(arg);
#if SIZEOF_BDIGITS == SIZEOF_SHORT
	    big->len = len;
#else
	    big->len = (len + 1) * 2 / sizeof(BDIGIT);
#endif
	    big->digits = digits = ALLOC_N(BDIGIT, big->len);
	    while (len > 0) {
#if SIZEOF_BDIGITS > SIZEOF_SHORT
		BDIGIT num = 0;
		int shift = 0;
		int i;

		for (i=0; i<SIZEOF_BDIGITS; i+=2) {
		    int j = r_short(arg);
		    num |= j << shift;
		    shift += BITSPERSHORT;
		    if (--len == 0) break;
		}
		*digits++ = num;
#else
		*digits++ = r_short(arg);
		len--;
#endif
	    }
	    v = rb_big_norm((VALUE)big);
	    if (TYPE(v) == T_BIGNUM) {
		r_regist(v, arg);
	    }
	}
	break;

      case TYPE_STRING:
	v = r_regist(r_string(arg), arg);
	break;

      case TYPE_REGEXP:
	{
	    char *buf;
	    long len;
	    int options;

	    r_bytes2(buf, len, arg);
	    options = r_byte(arg);
	    v = r_regist(rb_reg_new(buf, len, options), arg);
	}
	break;

      case TYPE_ARRAY:
	{
	    volatile long len = r_long(arg); /* gcc 2.7.2.3 -O2 bug?? */

	    v = rb_ary_new2(len);
	    r_regist(v, arg);
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
	    r_regist(v, arg);
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

	    klass = rb_path2class(r_unique(arg));
	    mem = rb_ivar_get(klass, rb_intern("__member__"));
	    if (mem == Qnil) {
		rb_raise(rb_eTypeError, "uninitialized struct");
	    }
	    len = r_long(arg);

	    values = rb_ary_new2(len);
	    for (i=0; i<len; i++) {
		rb_ary_push(values, Qnil);
	    }
	    v = rb_struct_alloc(klass, values);
	    r_regist(v, arg);
	    for (i=0; i<len; i++) {
		slot = r_symbol(arg);

		if (RARRAY(mem)->ptr[i] != ID2SYM(slot)) {
		    rb_raise(rb_eTypeError, "struct %s not compatible (:%s for :%s)",
			     rb_class2name(klass),
			     rb_id2name(slot),
			     rb_id2name(SYM2ID(RARRAY(mem)->ptr[i])));
		}
		rb_struct_aset(v, INT2FIX(i), r_object(arg));
	    }
	}
	break;

      case TYPE_USERDEF:
        {
	    VALUE klass;

	    klass = rb_path2class(r_unique(arg));
	    if (!rb_respond_to(klass, s_load)) {
		rb_raise(rb_eTypeError, "class %s needs to have method `_load'",
			 rb_class2name(klass));
	    }
	    v = rb_funcall(klass, s_load, 1, r_string(arg));
	    r_regist(v, arg);
	}
        break;

      case TYPE_OBJECT:
	{
	    VALUE klass;

	    klass = rb_path2class(r_unique(arg));
	    if (TYPE(klass) != T_CLASS) {
		rb_raise(rb_eArgError, "dump format error");
	    }
	    v = rb_obj_alloc(klass);
	    if (TYPE(v) != T_OBJECT) {
		rb_raise(rb_eArgError, "dump format error");
	    }
	    r_regist(v, arg);
	    r_ivar(v, arg);
	}
	break;

      case TYPE_MODULE_OLD:
        {
	    char *buf;
	    r_bytes(buf, arg);
	    v = r_regist(rb_path2class(buf), arg);
	}
	break;

      case TYPE_CLASS:
        {
	    char *buf;
	    r_bytes(buf, arg);
	    v = rb_path2class(buf);
	    if (TYPE(v) != T_CLASS) {
		rb_raise(rb_eTypeError, "%s is not a class", buf);
	    }
	    r_regist(v, arg);
	}
	break;

      case TYPE_MODULE:
        {
	    char *buf;
	    r_bytes(buf, arg);
	    v = rb_path2class(buf);
	    if (TYPE(v) != T_MODULE) {
		rb_raise(rb_eTypeError, "%s is not a module", buf);
	    }
	    r_regist(v, arg);
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
    if (arg->proc) {
	rb_funcall(arg->proc, rb_intern("call"), 1, v);
    }
    return v;
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
    st_free_table(arg->symbol);
    return 0;
}

static VALUE
marshal_load(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE port, proc;
    int major, minor;
    VALUE v;
    OpenFile *fptr;
    struct load_arg arg;
    volatile VALUE hash;	/* protect from GC */

    rb_scan_args(argc, argv, "11", &port, &proc);
    if (rb_obj_is_kind_of(port, rb_cIO)) {
	rb_io_binmode(port);
	GetOpenFile(port, fptr);
	rb_io_check_readable(fptr);
	arg.fp = fptr->f;
	arg.taint = Qtrue;
    }
    else if (rb_respond_to(port, rb_intern("to_str"))) {
	int len;

	arg.fp = 0;
	arg.ptr = rb_str2cstr(port, &len);
	arg.end = arg.ptr + len;
	arg.taint = OBJ_TAINTED(port);
    }
    else {
	rb_raise(rb_eTypeError, "instance of IO needed");
    }

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

    arg.symbol = st_init_numtable();
    arg.data   = hash = rb_hash_new();
    if (NIL_P(proc)) arg.proc = 0;
    else             arg.proc = proc;
    v = rb_ensure(load, (VALUE)&arg, load_ensure, (VALUE)&arg);

    return v;
}

void
Init_marshal()
{
    VALUE rb_mMarshal = rb_define_module("Marshal");

    s_dump = rb_intern("_dump");
    s_load = rb_intern("_load");
    rb_define_module_function(rb_mMarshal, "dump", marshal_dump, -1);
    rb_define_module_function(rb_mMarshal, "load", marshal_load, -1);
    rb_define_module_function(rb_mMarshal, "restore", marshal_load, -1);
}
