/************************************************

  marshal.c -

  $Author$
  $Revision$
  $Date$
  created at: Thu Apr 27 16:30:01 JST 1995

************************************************/

#include "ruby.h"
#include "io.h"
#include "st.h"

#define MARSHAL_MAJOR   2
#define MARSHAL_MINOR   1

#define TYPE_NIL	'0'
#define TYPE_TRUE	'T'
#define TYPE_FALSE	'F'
#define TYPE_FIXNUM	'i'

#define TYPE_OBJECT	'o'
#define TYPE_USERDEF	'u'
#define TYPE_FLOAT	'f'
#define TYPE_BIGNUM	'l'
#define TYPE_STRING	'"'
#define TYPE_STRING2	'\''
#define TYPE_REGEXP	'/'
#define TYPE_ARRAY	'['
#define TYPE_ARRAY2	']'
#define TYPE_HASH	'{'
#define TYPE_HASH2	'}'
#define TYPE_STRUCT	'S'

#define TYPE_SYMBOL	':'
#define TYPE_SYMLINK	';'

VALUE cString;
VALUE cArray;
VALUE cHash;

char *rb_class2path();
VALUE rb_path2class();

static ID s_dump, s_load;

#if (defined(linux) && defined(USE_DLN_A_OUT)) || !defined(HAVE_TMPNAM)
#define tmpnam(s) ltmpnam(s)
static char *
tmpnam(s)
    char *s;
{
    static int n = 0;

    sprintf(s, "/tmp/rb-mrsr-%x%x", getpid(), n++);
    return s;
}
#endif

#define w_byte(c, fp) putc((c), fp)
#define w_bytes(s, n, fp) (w_long((n), fp),fwrite(s, 1, n, fp))

static void
w_short(x, fp)
    int x;
    FILE *fp;
{
    w_byte( x      & 0xff, fp);
    w_byte((x>> 8) & 0xff, fp);
}

static void
w_long(x, fp)
    long x;
    FILE *fp;
{
    w_byte((int)( x      & 0xff), fp);
    w_byte((int)((x>> 8) & 0xff), fp);
    w_byte((int)((x>>16) & 0xff), fp);
    w_byte((int)((x>>24) & 0xff), fp);
}

static void
w_float(d, fp)
    double d;
    FILE *fp;
{
    char buf[100];

    sprintf(buf, "%.12g", d);
    w_bytes(buf, strlen(buf), fp);
}

static void
w_symbol(id, fp, table)
    ID id;
    FILE *fp;
    st_table *table;
{
    char *sym = rb_id2name(id);
    int num;

    if (st_lookup(table, id, &num)) {
	w_byte(TYPE_SYMLINK, fp);
	w_long(num, fp);
    }
    else {
	w_byte(TYPE_SYMBOL, fp);
	w_bytes(sym, strlen(sym), fp);
	st_insert(table, id, table->num_entries);
    }
}

static void
w_unique(s, fp, table)
    char *s;
    FILE *fp;
    st_table *table;
{
    w_symbol(rb_intern(s), fp, table);
}

static void w_object();
extern VALUE cBignum, cStruct;

struct each_arg {
    FILE *fp;
    VALUE limit;
    st_table *table;
};

static int
hash_each(key, value, arg)
    VALUE key, value;
    struct each_arg *arg;
{
    w_object(key, arg->fp, arg->limit, arg->table);
    w_object(value, arg->fp, arg->limit, arg->table);
    return ST_CONTINUE;
}

static int
obj_each(id, value, arg)
    ID id;
    VALUE value;
    struct each_arg *arg;
{
    w_symbol(id, arg->fp, arg->table);
    w_object(value, arg->fp, arg->limit, arg->table);
    return ST_CONTINUE;
}

static void
w_object(obj, fp, limit, table)
    VALUE obj;
    FILE *fp;
    int limit;
    st_table *table;
{
    struct each_arg arg;
    int n;

    if (limit == 0) {
	Fail("exceed depth limit");
    }
    limit--;

    arg.fp = fp;
    arg.limit = limit;
    arg.table = table;

    if (obj == Qnil) {
	w_byte(TYPE_NIL, fp);
    }
    else if (obj == TRUE) {
	w_byte(TYPE_TRUE, fp);
    }
    else if (obj == FALSE) {
	w_byte(TYPE_FALSE, fp);
    }
    else if (FIXNUM_P(obj)) {
	if (sizeof(long) == 4) {
	    w_byte(TYPE_FIXNUM, fp);
	    w_long(FIX2INT(obj), fp);
	}
    }
    else {
	if (rb_respond_to(obj, s_dump)) {
	    VALUE v;

	    w_byte(TYPE_USERDEF, fp);
	    w_unique(rb_class2path(CLASS_OF(obj)), fp, table);
	    v = rb_funcall(obj, s_dump, 1, limit);
	    if (TYPE(v) != T_STRING) {
		TypeError("_dump_to must return String");
	    }
	    w_bytes(RSTRING(v)->ptr, RSTRING(v)->len, fp);
	    return;
	}
	switch (BUILTIN_TYPE(obj)) {
	  case T_FLOAT:
	    w_byte(TYPE_FLOAT, fp);
	    w_float(RFLOAT(obj)->value, fp);
	    return;

	  case T_BIGNUM:
	    w_byte(TYPE_BIGNUM, fp);
	    {
		char sign = RBIGNUM(obj)->sign?'+':'-';
		int len = RBIGNUM(obj)->len;
		USHORT *d = RBIGNUM(obj)->digits;

		w_byte(sign, fp);
		w_long(len, fp);
		while (len--) {
		    w_short(d, fp);
		    d++;
		}
	    }
	    return;
	}

	switch (BUILTIN_TYPE(obj)) {
	  case T_STRING:
	    if (CLASS_OF(obj) == cString) {
		w_byte(TYPE_STRING, fp);
		w_bytes(RSTRING(obj)->ptr, RSTRING(obj)->len, fp);
	    }
	    else {
		w_byte(TYPE_STRING2, fp);
		w_bytes(RSTRING(obj)->ptr, RSTRING(obj)->len, fp);
		w_unique(rb_class2path(CLASS_OF(obj)), fp, table);
	    }
	    return;

	  case T_REGEXP:
	    w_byte(TYPE_REGEXP, fp);
	    w_bytes(RREGEXP(obj)->str, RREGEXP(obj)->len, fp);
	    w_byte(FL_TEST(obj, FL_USER1), fp);
	    return;

	  case T_ARRAY:
	    if (CLASS_OF(obj) == cArray) w_byte(TYPE_ARRAY, fp);
	    else w_byte(TYPE_ARRAY2, fp);
	    {
		int len = RARRAY(obj)->len;
		VALUE *ptr = RARRAY(obj)->ptr;

		w_long(len, fp);
		while (len--) {
		    w_object(*ptr, fp, limit, table);
		    ptr++;
		}
	    }
	    if (CLASS_OF(obj) != cArray) {
		w_unique(rb_class2path(CLASS_OF(obj)), fp, table);
	    }
	    break;

	  case T_HASH:
	    if (CLASS_OF(obj) == cHash) w_byte(TYPE_HASH, fp);
	    else w_byte(TYPE_HASH2, fp);
	    w_byte(TYPE_HASH, fp);
	    w_long(RHASH(obj)->tbl->num_entries, fp);
	    st_foreach(RHASH(obj)->tbl, hash_each, &arg);
	    if (CLASS_OF(obj) != cHash) {
		w_unique(rb_class2path(CLASS_OF(obj)), fp, table);
	    }
	    break;

	  case T_STRUCT:
	    w_byte(TYPE_STRUCT, fp);
	    {
		int len = RSTRUCT(obj)->len;
		char *path = rb_class2path(CLASS_OF(obj));
		VALUE mem;
		int i;

		w_unique(path, fp, table);
		w_long(len, fp);
		mem = rb_ivar_get(CLASS_OF(obj), rb_intern("__member__"));
		if (mem == Qnil) {
		    Fatal("non-initialized struct");
		}
		for (i=0; i<len; i++) {
		    w_symbol(FIX2INT(RARRAY(mem)->ptr[i]), fp, table);
		    w_object(RSTRUCT(obj)->ptr[i], fp, limit, table);
		}
	    }
	    break;

	  case T_OBJECT:
	    w_byte(TYPE_OBJECT, fp);
	    {
		VALUE class = CLASS_OF(obj);
		char *path;

		if (FL_TEST(class, FL_SINGLETON)) {
		    TypeError("singleton can't be dumped");
		}
		path = rb_class2path(class);
		w_unique(path, fp, table);
		if (ROBJECT(obj)->iv_tbl) {
		    w_long(ROBJECT(obj)->iv_tbl->num_entries, fp);
		    st_foreach(ROBJECT(obj)->iv_tbl, obj_each, &arg);
		}
		else {
		    w_long(0, fp);
		}
	    }
	    break;

	  default:
	    TypeError("can't dump %s", rb_class2name(CLASS_OF(obj)));
	    break;
	}
    }
}

struct dump_arg {
    VALUE obj;
    FILE *fp;
    int limit;
    st_table *table;
};

static VALUE
dump(arg)
    struct dump_arg *arg;
{
    w_object(arg->obj, arg->fp, arg->limit, arg->table);
}

static VALUE
dump_ensure(arg)
    struct dump_arg *arg;
{
    st_free_table(arg->table);
}

static VALUE
dump_on(obj, port, limit)
    VALUE obj, port;
    int limit;
{
    extern VALUE cIO;
    FILE *fp;
    OpenFile *fptr;
    struct dump_arg arg;

    if (obj_is_kind_of(port, cIO)) {
	GetOpenFile(port, fptr);
	io_writable(fptr);
	fp = (fptr->f2) ? fptr->f2 : fptr->f;
    }
    else {
	TypeError("instance of IO needed");
    }

    w_byte(MARSHAL_MAJOR, fp);
    w_byte(MARSHAL_MINOR, fp);

    arg.obj = obj;
    arg.fp = fp;
    arg.limit = limit;
    arg.table = st_init_numtable();
    rb_ensure(dump, &arg, dump_ensure, &arg);

    return Qnil;
}

static VALUE
marshal_dump(argc, argv)
    int argc;
    VALUE argv;
{
    VALUE obj, port, lim;
    int limit;

    rb_scan_args(argc, argv, "21", &obj, &port, &lim);
    if (NIL_P(lim)) limit = 100;
    else limit = NUM2INT(lim);

    dump_on(obj, port, limit);
}

static VALUE
marshal_dumps(argc, argv)
    int argc;
    VALUE argv;
{
    VALUE obj, lim;
    int limit;
    VALUE str = str_new(0, 0);
    VALUE port;
    FILE *fp = 0;
    char buf[BUFSIZ];
    int n;

    rb_scan_args(argc, argv, "11", &obj, &lim);
    if (NIL_P(lim)) limit = 100;
    else limit = NUM2INT(lim);

    tmpnam(buf);
    port = file_open(buf, "w");
    fp = rb_fopen(buf, "r");
#if !defined(MSDOS) && !defined(__BOW__)
    unlink(buf);
#endif

    dump_on(obj, port, limit);
    io_close(port);
#if defined(MSDOS) || defined(__BOW__)
    unlink(buf);
#endif

    while (n = fread(buf, 1, BUFSIZ, fp)) {
	str_cat(str, buf, n);
    }

    return str;
}

#define r_byte(fp)	getc(fp)

static int
r_short(fp)
    FILE *fp;
{
    register short x;
    x = r_byte(fp);
    x |= r_byte(fp) << 8;
    /* XXX If your short is > 16 bits, add sign-extension here!!! */
    return x;
}

static long
r_long(fp)
    FILE *fp;
{
    register long x;
    x = r_byte(fp);
    x |= (long)r_byte(fp) << 8;
    x |= (long)r_byte(fp) << 16;
    x |= (long)r_byte(fp) << 24;
    /* XXX If your long is > 32 bits, add sign-extension here!!! */
    return x;
}

#define r_bytes(s, fp) \
  (s = (char*)r_long(fp), r_bytes0(&s,ALLOCA_N(char,(int)s),(int)s,fp))

static char 
r_bytes0(sp, s, len, fp)
    char **sp, *s;
    int len;
    FILE *fp;
{
    fread(s, 1, len, fp);
    (s)[len] = '\0';
    *sp = s;

    return len;
}

static ID
r_symbol(fp, table)
    FILE *fp;
    st_table *table;
{
    char *buf;
    ID id;
    char type;

    if (r_byte(fp) == TYPE_SYMLINK) {
	int num = r_long(fp);

	if (st_lookup(table, num, &id)) {
	    return id;
	}
	TypeError("bad symbol");
    }
    r_bytes(buf, fp);
    id = rb_intern(buf);
    st_insert(table, table->num_entries, id);

    return id;
}

static char*
r_unique(fp, table)
    FILE *fp;
    st_table *table;
{
    return rb_id2name(r_symbol(fp, table));
}

static VALUE
r_string(fp)
    FILE *fp;
{
    char *buf;
    int len = r_bytes(buf, fp);
    VALUE v;

    v = str_new(buf, len);

    return v;
}

static VALUE
r_object(fp, table)
    FILE *fp;
    st_table *table;
{
    VALUE v;
    int type = r_byte(fp);

    switch (type) {
      case EOF:
	eof_error("EOF read where object expected");
	return Qnil;

      case TYPE_NIL:
	return Qnil;

      case TYPE_TRUE:
	return TRUE;

      case TYPE_FALSE:
	return FALSE;

      case TYPE_FIXNUM:
	{
	    int i = r_long(fp);
	    return INT2FIX(i);
	}

      case TYPE_FLOAT:
	{
	    double atof();
	    char *buf;

	    r_bytes(buf, fp);
	    v = float_new(atof(buf));
	    return v;
	}

      case TYPE_BIGNUM:
	{
	    int len;
	    USHORT *digits;

	    NEWOBJ(big, struct RBignum);
	    OBJSETUP(big, cBignum, T_BIGNUM);
	    big->sign = (r_byte(fp) == '+');
	    big->len = len = r_long(fp);
	    big->digits = digits = ALLOC_N(USHORT, len);
	    while (len--) {
		*digits++ = r_short(fp);
	    }
	    return (VALUE)big;
	}

      case TYPE_STRING:
	return r_string(fp);

      case TYPE_STRING2:
	v = r_string(fp);
	RBASIC(v)->class = rb_path2class(r_unique(fp, table));
	return v;

      case TYPE_REGEXP:
	{
	    char *buf;
	    int len = r_bytes(buf, fp);
	    int ci = r_byte(fp);
	    v = reg_new(buf, len, ci);
	    return v;
	}

      case TYPE_ARRAY:
	{
	    int len = r_long(fp);
	    v = ary_new2(len);
	    while (len--) {
		ary_push(v, r_object(fp, table));
	    }
	    return v;
	}

      case TYPE_HASH:
	{
	    int len = r_long(fp);

	    v = hash_new();
	    while (len--) {
		VALUE key = r_object(fp, table);
		VALUE value = r_object(fp, table);
		hash_aset(v, key, value);
	    }
	    return v;
	}

      case TYPE_STRUCT:
	{
	    VALUE class, mem, values;
	    int i, len;

	    class = rb_path2class(r_unique(fp, table));
	    mem = rb_ivar_get(class, rb_intern("__member__"));
	    if (mem == Qnil) {
		Fatal("non-initialized struct");
	    }
	    len = r_long(fp);

	    values = ary_new2(len);
	    i = 0;
	    for (i=0; i<len; i++) {
		ID slot = r_symbol(fp, table);
		if (RARRAY(mem)->ptr[i] != INT2FIX(slot))
		    TypeError("struct not compatible");
		ary_push(values, r_object(fp, table));
	    }
	    v = struct_alloc(class, values);
	}
	break;

      case TYPE_USERDEF:
        {
	    VALUE class;
	    int len;

	    class = rb_path2class(r_unique(fp, table));
	    if (rb_respond_to(class, s_load)) {
		v = rb_funcall(class, s_load, 1, r_string(fp));
	    }
	    else {
		TypeError("class %s needs to have method `_load_from'",
			  rb_class2name(class));
	    }
	}
        break;
      case TYPE_OBJECT:
	{
	    VALUE class;
	    int len;

	    class = rb_path2class(r_unique(fp, table));
	    len = r_long(fp);
	    v = obj_alloc(class);
	    if (len > 0) {
		while (len--) {
		    ID id = r_symbol(fp, table);
		    VALUE val = r_object(fp, table);
		    rb_ivar_set(v, id, val);
		}
	    }
	}
	break;

      default:
	ArgError("dump format error(0x%x)", type);
	break;
    }
    return v;
}

struct load_arg {
    FILE *fp;
    st_table *table;
};

static VALUE
load(arg)
    struct load_arg *arg;
{
    return r_object(arg->fp, arg->table);
}

static VALUE
load_ensure(arg)
    struct load_arg *arg;
{
    st_free_table(arg->table);
}

static VALUE
marshal_load(self, port)
    VALUE self, port;
{
    extern VALUE cIO;
    FILE *fp;
    int major;
    VALUE v;
    OpenFile *fptr;
    char buf[32];
#if defined(MSDOS) || defined(__BOW__)
    int need_unlink_tmp = 0;
#endif
    struct load_arg arg;

    if (TYPE(port) == T_STRING) {
	tmpnam(buf);
	fp = rb_fopen(buf, "w");
	v = file_open(buf, "r");
#if defined(MSDOS) || defined(__BOW__)
	need_unlink_tmp = 0;
#else
	unlink(buf);
#endif

	fwrite(RSTRING(port)->ptr, RSTRING(port)->len, 1, fp);
	fclose(fp);
	port = v;
    }

    if (obj_is_kind_of(port, cIO)) {
	GetOpenFile(port, fptr);
	io_readable(fptr);
	fp = fptr->f;
    }
    else {
	TypeError("instance of IO needed");
    }

    major = r_byte(fp);
    if (major == MARSHAL_MAJOR) {
	if (r_byte(fp) != MARSHAL_MINOR) {
	    Warning("Old marshal file format (can be read)");
	}
	arg.fp = fp;
	arg.table = st_init_numtable();
	v = rb_ensure(load, &arg, load_ensure, &arg);
    }
#if defined(MSDOS) || defined(__BOW__)
    if (need_unlink_tmp) unlink(buf);
#endif
    if (major != MARSHAL_MAJOR) {
	TypeError("Old marshal file format (can't read)");
    }

    return v;
}

Init_marshal()
{
    VALUE mMarshal = rb_define_module("Marshal");

    s_dump = rb_intern("_dump_to");
    s_load = rb_intern("_load_from");
    rb_define_module_function(mMarshal, "dump", marshal_dump, -1);
    rb_define_module_function(mMarshal, "dumps", marshal_dumps, -1);
    rb_define_module_function(mMarshal, "load", marshal_load, 1);
    rb_define_module_function(mMarshal, "restore", marshal_load, 1);
}
