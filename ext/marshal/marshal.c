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

#define TYPE_NIL	'0'
#define TYPE_FIXNUM	'i'

#define TYPE_OBJECT	'o'
#define TYPE_LINK	'@'
#define TYPE_FLOAT	'f'
#define TYPE_BIGNUM	'l'
#define TYPE_STRING	'"'
#define TYPE_REGEXP	'/'
#define TYPE_ARRAY	'['
#define TYPE_HASH	'{'
#define TYPE_STRUCT	'S'

char *rb_class2path();
VALUE rb_path2class();

static ID s_dump, s_load;

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
w_symbol(id, fp)
    ID id;
    FILE *fp;
{
    char *sym = rb_id2name(id);

    w_bytes(sym, strlen(sym), fp);
}

static void w_object();
extern VALUE cBignum, cStruct;

static int
hash_each(key, value, fp)
    VALUE key, value;
    FILE *fp;
{
    w_object(key, fp);
    w_object(value, fp);
    return ST_CONTINUE;
}

static int
obj_each(id, value, fp)
    ID id;
    VALUE value;
    FILE *fp;
{
    w_symbol(id, fp);
    w_object(value, fp);
    return ST_CONTINUE;
}

struct st_table *new_idhash();

static void
w_object(obj, fp, port, table)
    VALUE obj, port;
    FILE *fp;
    st_table *table;
{
    if (obj == Qnil) {
	w_byte(TYPE_NIL, fp);
    }
    else if (FIXNUM_P(obj)) {
	w_byte(TYPE_FIXNUM, fp);
	w_long(FIX2INT(obj), fp);
    }
    else if (st_lookup(table, obj, 0)) {
	w_byte(TYPE_LINK, fp);
	w_long(obj, fp);
    }
    else {
	st_insert(table, obj, 0);
	switch (BUILTIN_TYPE(obj)) {
	  case T_FLOAT:
	    w_byte(TYPE_FLOAT, fp);
	    w_long(obj, fp);
	    w_float(RFLOAT(obj)->value, fp);
	    break;

	  case T_BIGNUM:
	    w_byte(TYPE_BIGNUM, fp);
	    w_long(obj, fp);
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
	    break;

	  case T_STRING:
	    w_byte(TYPE_STRING, fp);
	    w_long(obj, fp);
	    w_bytes(RSTRING(obj)->ptr, RSTRING(obj)->len, fp);
	    break;

	  case T_REGEXP:
	    w_byte(TYPE_REGEXP, fp);
	    w_long(obj, fp);
	    w_bytes(RREGEXP(obj)->str, RREGEXP(obj)->len, fp);
	    w_byte(FL_TEST(obj, FL_USER1), fp);
	    break;

	  case T_ARRAY:
	    w_byte(TYPE_ARRAY, fp);
	    w_long(obj, fp);
	    {
		int len = RARRAY(obj)->len;
		VALUE *ptr = RARRAY(obj)->ptr;

		w_long(len, fp);
		while (len--) {
		    w_object(*ptr, fp, port, table);
		    ptr++;
		}
	    }
	    break;

	  case T_HASH:
	    w_byte(TYPE_HASH, fp);
	    w_long(obj, fp);
	    w_long(RHASH(obj)->tbl->num_entries, fp);
	    st_foreach(RHASH(obj)->tbl, hash_each, fp);
	    break;

	  case T_STRUCT:
	    w_byte(TYPE_STRUCT, fp);
	    w_long(obj, fp);
	    {
		int len = RSTRUCT(obj)->len;
		char *path = rb_class2path(CLASS_OF(obj));
		VALUE mem;
		int i;

		w_bytes(path, strlen(path), fp);
		w_long(len, fp);
		mem = rb_ivar_get(CLASS_OF(obj), rb_intern("__member__"));
		if (mem == Qnil) {
		    Fail("non-initialized struct");
		}
		for (i=0; i<len; i++) {
		    w_symbol(FIX2INT(RARRAY(mem)->ptr[i]), fp);
		    w_object(RSTRUCT(obj)->ptr[i], fp, port, table);
		}
	    }
	    break;

	  case T_OBJECT:
	    w_byte(TYPE_OBJECT, fp);
	    w_long(obj, fp);
	    {
		VALUE class = CLASS_OF(obj);
		char *path = rb_class2path(class);

		w_bytes(path, strlen(path), fp);
		if (rb_responds_to(obj, s_dump)) {
		    w_long(-1, fp);
		    rb_funcall(obj, s_dump, 1, port);
		}
		else if (ROBJECT(obj)->iv_tbl) {
		    w_long(ROBJECT(obj)->iv_tbl->num_entries, fp);
		    st_foreach(ROBJECT(obj)->iv_tbl, obj_each, fp);
		}
		else {
		    w_long(0, fp);
		}
	    }
	    break;

	  default:
	    Fail("can't dump %s", rb_class2name(CLASS_OF(obj)));
	    break;
	}
    }
}

static VALUE
marshal_dump(self, obj, port)
    VALUE self, obj, port;
{
    extern VALUE cIO;
    FILE *fp;
    OpenFile *fptr;
    st_table *table;

    if (obj_is_kind_of(port, cIO)) {
	GetOpenFile(port, fptr);
	if (!(fptr->mode & FMODE_WRITABLE)) {
	    Fail("not opened for writing");
	}
	fp = (fptr->f2) ? fptr->f2 : fptr->f;
    }
    else {
	Fail("instance of IO needed");
    }

    table = new_idhash();

    w_object(obj, fp, port, table);

    st_free_table(table);
    return Qnil;
}

static VALUE
marshal_dumps(self, obj)
    VALUE self, obj;
{
    VALUE str = str_new(0, 0);
    VALUE port;
    FILE *fp = Qnil;
    char buf[BUFSIZ];
    int n;

    sprintf(buf, "/tmp/rb-mrsr-%x", getpid()^(int)buf);
    port = file_open(buf, "w");
    if (!port) rb_sys_fail("tmp file");
    fp = fopen(buf, "r");
    if (!fp) rb_sys_fail("tmp file(read)");
    unlink(buf);

    marshal_dump(self, obj, port);
    io_close(port);

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
#define r_bytes(s, fp) r_bytes0(&s, fp)
static int
r_bytes0(s, fp)
    char **s;
    FILE *fp;
{
    int len = r_long(fp);
    *s = ALLOC_N(char, len+1);

    fread(*s, 1, len, fp);
    (*s)[len] = '\0';
    return len;
}

static ID
r_symbol(fp)
    FILE *fp;
{
    char *buf;
    ID id;

    r_bytes(buf, fp);
    id = rb_intern(buf);
    free(buf);
    return id;
}

static VALUE
r_object(fp, port, table)
    FILE *fp;
    VALUE port;
    st_table *table;
{
    VALUE v;
    int type = r_byte(fp);
    int id;

    switch (type) {
      case EOF:
	Fail("EOF read where object expected");
	return Qnil;

      case TYPE_NIL:
	return Qnil;

      case TYPE_LINK:
	if (st_lookup(table, r_long(fp), &v)) {
	    return v;
	}
	Fail("corrupted marshal file");
	break;

      case TYPE_FIXNUM:
	{
	    int i = r_long(fp);
	    return INT2FIX(i);
	}
    }

    id = r_long(fp);
    switch (type) {
      case TYPE_FLOAT:
	{
	    double atof();
	    char *buf;

	    r_bytes(buf, fp);
	    v = float_new(atof(buf));
	    free(buf);
	}
	break;

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
	    v = (VALUE)big;
	}
	break;

      case TYPE_STRING:
	{
	    char *buf;
	    int len = r_bytes(buf, fp);
	    v = str_new(buf, len);
	    free(buf);
	}
	break;

      case TYPE_REGEXP:
	{
	    char *buf;
	    int len = r_bytes(buf, fp);
	    int ci = r_byte(fp);
	    v = reg_new(buf, len, ci);
	    free(buf);
	}
	break;

      case TYPE_ARRAY:
	{
	    int len = r_long(fp);
	    v = ary_new2(len);
	    while (len--) {
		ary_push(v, r_object(fp, port, table));
	    }
	}
	break;

      case TYPE_HASH:
	{
	    int len = r_long(fp);

	    v = hash_new();
	    while (len--) {
		VALUE key = r_object(fp, port, table);
		VALUE value = r_object(fp, port, table);
		hash_aset(v, key, value);
	    }
	}
	break;

      case TYPE_STRUCT:
	{
	    VALUE class, mem, values;
	    char *path;
	    int i, len;

	    r_bytes(path, fp);
	    class = rb_path2class(path);
	    free(path);
	    mem = rb_ivar_get(class, rb_intern("__member__"));
	    if (mem == Qnil) {
		Fail("non-initialized struct");
	    }
	    len = r_long(fp);

	    values = ary_new();
	    i = 0;
	    while (len--) {
		ID slot = r_symbol(fp);
		if (RARRAY(mem)->ptr[i++] != INT2FIX(slot))
		    Fail("struct not compatible");
		ary_push(values, r_object(fp, port, table));
	    }
	    v = struct_alloc(class, values);
	}
	break;

      case TYPE_OBJECT:
	{
	    VALUE class;
	    int len;
	    char *path;

	    r_bytes(path, fp);
	    class = rb_path2class(path);
	    free(path);
	    len = r_long(fp);
	    if (len == -1) {
		if (rb_responds_to(class, s_load)) {
		    v = rb_funcall(class, s_load, 1, port);
		}
		else {
		    Fail("class %s needs to have method `_load_from'",
			 rb_class2name(class));
		}
	    }
	    else {
		v = obj_alloc(class);
		if (len > 0) {
		    while (len--) {
			ID id = r_symbol(fp);
			VALUE val = r_object(fp, port, table);
			rb_ivar_set(v, id, val);
		    }
		}
	    }
	}
	break;

      default:
	Fail("dump format error(0x%x)", type);
	break;
    }
    st_insert(table, id, v);
    return v;
}

static VALUE
marshal_load(self, port)
    VALUE self, port;
{
    extern VALUE cIO;
    void *fp;
    VALUE v;
    OpenFile *fptr;
    st_table *table;

    if (TYPE(port) == T_STRING) {
	char buf[32];

	sprintf(buf, "/tmp/rb-mrsw-%x", getpid()^(int)buf);
	fp = fopen(buf, "w");
	if (!fp) rb_sys_fail("tmp file");
	v = file_open(buf, "r");
	if (!v) rb_sys_fail("tmp file(read)");
	unlink(buf);

	fwrite(RSTRING(port)->ptr, RSTRING(port)->len, 1, fp);
	fclose(fp);
	port = v;
    }
    if (obj_is_kind_of(port, cIO)) {
	GetOpenFile(port, fptr);
	if (!(fptr->mode & FMODE_READABLE)) {
	    Fail("not opened for reading");
	}
	fp = fptr->f;
    }
    else {
	Fail("instance of IO needed");
    }

    table = new_idhash();

    v = r_object(fp, port, table);

    st_free_table(table);

    return v;
}

Init_marshal()
{
    VALUE mMarshal = rb_define_module("Marshal");

    s_dump = rb_intern("_dump_to");
    s_load = rb_intern("_load_from");
    rb_define_module_function(mMarshal, "dump", marshal_dump, 2);
    rb_define_module_function(mMarshal, "dumps", marshal_dumps, 1);
    rb_define_module_function(mMarshal, "load", marshal_load, 1);
    rb_define_module_function(mMarshal, "restore", marshal_load, 1);
}
