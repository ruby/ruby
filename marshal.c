/************************************************

  marshal.c -

  $Author$
  $Revision$
  $Date$
  created at: Thu Apr 27 16:30:01 JST 1995

************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "st.h"

#define MARSHAL_MAJOR   4
#define MARSHAL_MINOR   0

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
#define TYPE_STRUCT	'S'
#define TYPE_MODULE	'M'

#define TYPE_SYMBOL	':'
#define TYPE_SYMLINK	';'

#define TYPE_LINK	'@'

VALUE rb_path2class _((char*));

static ID s_dump, s_load;

struct dump_arg {
    VALUE obj;
    FILE *fp;
    VALUE str;
    st_table *symbol;
    st_table *data;
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
    else str_cat(arg->str, &c, 1);
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
	str_cat(arg->str, s, n);
    }
}

static void
w_short(x, arg)
    int x;
    struct dump_arg *arg;
{
    int i;

    for (i=0; i<sizeof(short); i++) {
	w_byte((x >> (i*8)) & 0xff, arg);
    }
}

static void
w_long(x, arg)
    long x;
    struct dump_arg *arg;
{
    char buf[sizeof(long)+1];
    int i, len = 0;

    if (x == 0) {
	w_byte(0, arg);
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

    sprintf(buf, "%.12g", d);
    w_bytes(buf, strlen(buf), arg);
}

static void
w_symbol(id, arg)
    ID id;
    struct dump_arg *arg;
{
    char *sym = rb_id2name(id);
    int num;

    if (st_lookup(arg->symbol, id, &num)) {
	w_byte(TYPE_SYMLINK, arg);
	w_long(num, arg);
    }
    else {
	w_byte(TYPE_SYMBOL, arg);
	w_bytes(sym, strlen(sym), arg);
	st_insert(arg->symbol, id, arg->symbol->num_entries);
    }
}

static void
w_unique(s, arg)
    char *s;
    struct dump_arg *arg;
{
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
    if (CLASS_OF(obj) != klass) {
	w_byte(TYPE_UCLASS, arg);
	w_unique(rb_class2name(CLASS_OF(obj)), arg);
    }
}

static void
w_object(obj, arg, limit)
    VALUE obj;
    struct dump_arg *arg;
    int limit;
{
    struct dump_call_arg c_arg;

    if (limit == 0) {
	Fail("exceed depth limit");
    }
    if (obj == Qnil) {
	w_byte(TYPE_NIL, arg);
    }
    else if (obj == TRUE) {
	w_byte(TYPE_TRUE, arg);
    }
    else if (obj == FALSE) {
	w_byte(TYPE_FALSE, arg);
    }
    else if (FIXNUM_P(obj)) {
#if SIZEOF_LONG <= 4
	w_byte(TYPE_FIXNUM, arg);
	w_long(FIX2INT(obj), arg);
#else
	if (RSHIFT((long)obj, 32) == 0 || RSHIFT((long)obj, 32) == -1) {
	    w_byte(TYPE_FIXNUM, arg);
	    w_long(FIX2LONG(obj), arg);
	}
	else {
	    w_object(int2big(FIX2LONG(obj)), arg, limit);
	    return;
	}
#endif
    }
    else {
	int num;

	limit--;
	c_arg.limit = limit;
	c_arg.arg = arg;

	if (st_lookup(arg->data, obj, &num)) {
	    w_byte(TYPE_LINK, arg);
	    w_long(num, arg);
	    return;
	}

	st_insert(arg->data, obj, arg->data->num_entries);
	if (rb_respond_to(obj, s_dump)) {
	    VALUE v;

	    w_byte(TYPE_USERDEF, arg);
	    w_unique(rb_class2name(CLASS_OF(obj)), arg);
	    v = rb_funcall(obj, s_dump, 1, limit);
	    if (TYPE(v) != T_STRING) {
		TypeError("_dump_to must return String");
	    }
	    w_bytes(RSTRING(v)->ptr, RSTRING(v)->len, arg);
	    return;
	}

	switch (BUILTIN_TYPE(obj)) {
	  case T_MODULE:
	  case T_CLASS:
	    w_byte(TYPE_MODULE, arg);
	    {
		VALUE path = rb_class_path(obj);
		w_bytes(RSTRING(path)->ptr, RSTRING(path)->len, arg);
	    }
	    return;

	  case T_FLOAT:
	    w_byte(TYPE_FLOAT, arg);
	    w_float(RFLOAT(obj)->value, arg);
	    return;

	  case T_BIGNUM:
	    w_byte(TYPE_BIGNUM, arg);
	    {
		char sign = RBIGNUM(obj)->sign?'+':'-';
		int len = RBIGNUM(obj)->len;
		unsigned short *d = RBIGNUM(obj)->digits;

		w_byte(sign, arg);
		w_long(len, arg);
		while (len--) {
		    w_short(*d, arg);
		    d++;
		}
	    }
	    return;

	  case T_STRING:
	    w_uclass(obj, cString, arg);
	    w_byte(TYPE_STRING, arg);
	    w_bytes(RSTRING(obj)->ptr, RSTRING(obj)->len, arg);
	    return;

	  case T_REGEXP:
	    w_uclass(obj, cRegexp, arg);
	    w_byte(TYPE_REGEXP, arg);
	    w_bytes(RREGEXP(obj)->str, RREGEXP(obj)->len, arg);
	    w_byte(FL_TEST(obj, FL_USER1), arg);
	    return;

	  case T_ARRAY:
	    w_uclass(obj, cArray, arg);
	    w_byte(TYPE_ARRAY, arg);
	    {
		int len = RARRAY(obj)->len;
		VALUE *ptr = RARRAY(obj)->ptr;

		w_long(len, arg);
		while (len--) {
		    w_object(*ptr, arg, limit);
		    ptr++;
		}
	    }
	    break;

	  case T_HASH:
	    w_uclass(obj, cHash, arg);
	    w_byte(TYPE_HASH, arg);
	    w_long(RHASH(obj)->tbl->num_entries, arg);
	    st_foreach(RHASH(obj)->tbl, hash_each, &c_arg);
	    break;

	  case T_STRUCT:
	    w_byte(TYPE_STRUCT, arg);
	    {
		int len = RSTRUCT(obj)->len;
		char *path = rb_class2name(CLASS_OF(obj));
		VALUE mem;
		int i;

		w_unique(path, arg);
		w_long(len, arg);
		mem = rb_ivar_get(CLASS_OF(obj), rb_intern("__member__"));
		if (mem == Qnil) {
		    Fatal("non-initialized struct");
		}
		for (i=0; i<len; i++) {
		    w_symbol(FIX2LONG(RARRAY(mem)->ptr[i]), arg);
		    w_object(RSTRUCT(obj)->ptr[i], arg, limit);
		}
	    }
	    break;

	  case T_OBJECT:
	    w_byte(TYPE_OBJECT, arg);
	    {
		VALUE klass = CLASS_OF(obj);
		char *path;

		if (FL_TEST(klass, FL_SINGLETON)) {
		    TypeError("singleton can't be dumped");
		}
		path = rb_class2name(klass);
		w_unique(path, arg);
		if (ROBJECT(obj)->iv_tbl) {
		    w_long(ROBJECT(obj)->iv_tbl->num_entries, arg);
		    st_foreach(ROBJECT(obj)->iv_tbl, obj_each, &c_arg);
		}
		else {
		    w_long(0, arg);
		}
	    }
	    break;

	  default:
	    TypeError("can't dump %s", rb_class2name(CLASS_OF(obj)));
	    break;
	}
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
	limit = NUM2INT(a2);
	port = a1;
    }
    else if (argc == 2) {
	if (FIXNUM_P(a1)) limit = FIX2INT(a1);
	else port = a1;
    }
    if (port) {
	if (obj_is_kind_of(port, cIO)) {
	    OpenFile *fptr;

	    io_binmode(port);
	    GetOpenFile(port, fptr);
	    io_writable(fptr);
	    arg.fp = (fptr->f2) ? fptr->f2 : fptr->f;
	}
	else {
	    TypeError("instance of IO needed");
	}
    }
    else {
	arg.fp = 0;
	port = str_new(0, 0);
	arg.str = port;
    }

    arg.symbol = st_init_numtable();
    arg.data   = st_init_numtable();
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
    st_table *data;
    VALUE proc;
};

static int
r_byte(arg)
    struct load_arg *arg;
{
    if (arg->fp) return getc(arg->fp);
    if (arg->ptr < arg->end) return *(unsigned char*)arg->ptr++;
    return EOF;
}

static unsigned short
r_short(arg)
    struct load_arg *arg;
{
    unsigned short x;
    int i;

    x = 0;
    for (i=0; i<sizeof(short); i++) {
	x |= r_byte(arg)<<(i*8);
    }

    return x;
}

static void
long_toobig(size)
    int size;
{
    TypeError("long too big for this architecture (size %d, given %d)",
	      sizeof(long), size);
}

static long
r_long(arg)
    struct load_arg *arg;
{
    register long x;
    int c = (char)r_byte(arg);
    int i;

    if (c == 0) return 0;
    if (c > 0) {
	if (c > sizeof(long)) long_toobig((int)c);
	x = 0;
	for (i=0;i<c;i++) {
	    x |= (long)r_byte(arg) << (8*i);
	}
    }
    else {
	c = -c;
	if (c > sizeof(long)) long_toobig((int)c);
	x = -1;
	for (i=0;i<c;i++) {
	    x &= ~(0xff << (8*i));
	    x |= (long)r_byte(arg) << (8*i);
	}
    }
    return x;
}

static long blen;		/* hidden length register */
#define r_bytes(s, arg) \
  (blen = r_long(arg), r_bytes0(&s,ALLOCA_N(char,blen),blen,arg))

static int
r_bytes0(sp, s, len, arg)
    char **sp, *s;
    int len;
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

    (s)[len] = '\0';
    *sp = s;

    return len;
}

static ID
r_symbol(arg)
    struct load_arg *arg;
{
    char *buf;
    ID id;

    if (r_byte(arg) == TYPE_SYMLINK) {
	int num = r_long(arg);

	if (st_lookup(arg->symbol, num, &id)) {
	    return id;
	}
	TypeError("bad symbol");
    }
    r_bytes(buf, arg);
    id = rb_intern(buf);
    st_insert(arg->symbol, arg->symbol->num_entries, id);

    return id;
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
    int len = r_bytes(buf, arg);

    return str_taint(str_new(buf, len));
}

static VALUE
r_regist(v, arg)
    VALUE v;
    struct load_arg *arg;
{
    if (arg->proc) {
	rb_funcall(arg->proc, rb_intern("call"), 1, v);
    }
    st_insert(arg->data, arg->data->num_entries, v);
    return v;
}

static VALUE
r_object(arg)
    struct load_arg *arg;
{
    VALUE v;
    int type = r_byte(arg);

    switch (type) {
      case EOF:
	eof_error();
	return Qnil;

      case TYPE_LINK:
	if (st_lookup(arg->data, r_long(arg), &v)) {
	    return v;
	}
	ArgError("dump format error (unlinked)");
	break;

      case TYPE_UCLASS:
	{
	    VALUE c = rb_path2class(r_unique(arg));
	    v = r_object(arg);
	    if (rb_special_const_p(v)) {
		ArgError("dump format error (user class)");
	    }
	    RBASIC(v)->klass = c;
	    return v;
	}

      case TYPE_NIL:
	return Qnil;

      case TYPE_TRUE:
	return TRUE;

      case TYPE_FALSE:
	return FALSE;

      case TYPE_FIXNUM:
	{
	    int i = r_long(arg);
	    return INT2FIX(i);
	}

      case TYPE_FLOAT:
	{
#ifndef atof
	    double atof();
#endif
	    char *buf;

	    r_bytes(buf, arg);
	    v = float_new(atof(buf));
	    return r_regist(v, arg);
	}

      case TYPE_BIGNUM:
	{
	    int len;
	    unsigned short *digits;

	    NEWOBJ(big, struct RBignum);
	    OBJSETUP(big, cBignum, T_BIGNUM);
	    big->sign = (r_byte(arg) == '+');
	    big->len = len = r_long(arg);
	    big->digits = digits = ALLOC_N(unsigned short, len);
	    while (len--) {
		*digits++ = r_short(arg);
	    }
	    big = RBIGNUM(big_norm((VALUE)big));
	    if (TYPE(big) == T_BIGNUM) {
		r_regist(big, arg);
	    }
	    return (VALUE)big;
	}

      case TYPE_STRING:
	return r_regist(r_string(arg), arg);

      case TYPE_REGEXP:
	{
	    char *buf;
	    int len = r_bytes(buf, arg);
	    int ci = r_byte(arg);
	    return r_regist(reg_new(buf, len, ci), arg);
	}

      case TYPE_ARRAY:
	{
	    volatile int len = r_long(arg);
	    v = ary_new2(len);
	    r_regist(v, arg);
	    while (len--) {
		ary_push(v, r_object(arg));
	    }
	    return v;
	}

      case TYPE_HASH:
	{
	    int len = r_long(arg);

	    v = hash_new();
	    r_regist(v, arg);
	    while (len--) {
		VALUE key = r_object(arg);
		VALUE value = r_object(arg);
		hash_aset(v, key, value);
	    }
	    return v;
	}

      case TYPE_STRUCT:
	{
	    VALUE klass, mem, values;
	    volatile int i;	/* gcc 2.7.2.3 -O2 bug?? */
	    int len;
	    ID slot;

	    klass = rb_path2class(r_unique(arg));
	    mem = rb_ivar_get(klass, rb_intern("__member__"));
	    if (mem == Qnil) {
		Fatal("non-initialized struct");
	    }
	    len = r_long(arg);

	    values = ary_new2(len);
	    for (i=0; i<len; i++) {
		ary_push(values, Qnil);
	    }
	    v = struct_alloc(klass, values);
	    r_regist(v, arg);
	    for (i=0; i<len; i++) {
		slot = r_symbol(arg);

		if (RARRAY(mem)->ptr[i] != INT2FIX(slot)) {
		    TypeError("struct %s not compatible (:%s for :%s)",
			      rb_class2name(klass),
			      rb_id2name(slot),
			      rb_id2name(FIX2INT(RARRAY(mem)->ptr[i])));
		}
		struct_aset(v, INT2FIX(i), r_object(arg));
	    }
	    return v;
	}
	break;

      case TYPE_USERDEF:
        {
	    VALUE klass;

	    klass = rb_path2class(r_unique(arg));
	    if (rb_respond_to(klass, s_load)) {
		v = rb_funcall(klass, s_load, 1, r_string(arg));
		return r_regist(v, arg);
	    }
	    TypeError("class %s needs to have method `_load_from'",
		      rb_class2name(klass));
	}
        break;

      case TYPE_OBJECT:
	{
	    VALUE klass;
	    int len;

	    klass = rb_path2class(r_unique(arg));
	    len = r_long(arg);
	    v = obj_alloc(klass);
	    r_regist(v, arg);
	    if (len > 0) {
		while (len--) {
		    ID id = r_symbol(arg);
		    VALUE val = r_object(arg);
		    rb_ivar_set(v, id, val);
		}
	    }
	    return v;
	}
	break;

      case TYPE_MODULE:
        {
	    char *buf;
	    r_bytes(buf, arg);
	    return rb_path2class(buf);
	}

      default:
	ArgError("dump format error(0x%x)", type);
	break;
    }
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
    st_free_table(arg->data);
    return 0;
}

static VALUE
marshal_load(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE port, proc;
    int major;
    VALUE v;
    OpenFile *fptr;
    struct load_arg arg;

    rb_scan_args(argc, argv, "11", &port, &proc);
    if (TYPE(port) == T_STRING) {
	arg.fp = 0;
	arg.ptr = RSTRING(port)->ptr;
	arg.end = arg.ptr + RSTRING(port)->len;
    }
    else {
	if (obj_is_kind_of(port, cIO)) {
	    io_binmode(port);
	    GetOpenFile(port, fptr);
	    io_readable(fptr);
	    arg.fp = fptr->f;
	}
	else {
	    TypeError("instance of IO needed");
	}
    }

    major = r_byte(&arg);
    if (major == MARSHAL_MAJOR) {
	if (r_byte(&arg) != MARSHAL_MINOR) {
	    Warn("Old marshal file format (can be read)");
	}
	arg.symbol = st_init_numtable();
	arg.data   = st_init_numtable();
	if (NIL_P(proc)) arg.proc = 0;
	else             arg.proc = proc;
	v = rb_ensure(load, (VALUE)&arg, load_ensure, (VALUE)&arg);
    }
    else {
	TypeError("Old marshal file format (can't read)");
    }

    return v;
}

void
Init_marshal()
{
    VALUE mMarshal = rb_define_module("Marshal");

    s_dump = rb_intern("_dump_to");
    s_load = rb_intern("_load_from");
    rb_define_module_function(mMarshal, "dump", marshal_dump, -1);
    rb_define_module_function(mMarshal, "load", marshal_load, -1);
    rb_define_module_function(mMarshal, "restore", marshal_load, 1);

    rb_provide("marshal.o");	/* for backward compatibility */
}
