/************************************************

  gdbm.c -

  $Author$
  $Date$
  modified at: Mon Jan 24 15:59:52 JST 1994

************************************************/

#include "ruby.h"

#include <gdbm.h>
#include <fcntl.h>
#include <errno.h>
#ifdef USE_CWGUSI
# include <sys/errno.h>
#endif

VALUE cGDBM;

#define MY_BLOCK_SIZE (2048)
#define MY_FATAL_FUNC (0)

struct dbmdata {
    int  di_size;
    GDBM_FILE di_dbm;
};

static void
closed_dbm()
{
    rb_raise(rb_eRuntimeError, "closed GDBM file");
}

#define GetDBM(obj, dbmp) {\
    Data_Get_Struct(obj, struct dbmdata, dbmp);\
    if (dbmp->di_dbm == 0) closed_dbm();\
}

static void
free_dbm(dbmp)
    struct dbmdata *dbmp;
{
    if (dbmp->di_dbm) gdbm_close(dbmp->di_dbm);
    free(dbmp);
}

static VALUE
fgdbm_s_open(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE file, vmode;
    GDBM_FILE dbm;
    struct dbmdata *dbmp;
    int mode;
    VALUE obj;

    if (rb_scan_args(argc, argv, "11", &file, &vmode) == 1) {
	mode = 0666;		/* default value */
    }
    else if (NIL_P(vmode)) {
	mode = -1;		/* return nil if DB not exist */
    }
    else {
	mode = NUM2INT(vmode);
    }
    Check_SafeStr(file);

    dbm = 0;
    if (mode >= 0)
	dbm = gdbm_open(RSTRING(file)->ptr, MY_BLOCK_SIZE, 
			O_RDWR|O_CREAT, mode, MY_FATAL_FUNC);
    if (!dbm)
	dbm = gdbm_open(RSTRING(file)->ptr, MY_BLOCK_SIZE, 
			O_RDWR, mode, MY_FATAL_FUNC);
    if (!dbm)
	dbm = gdbm_open(RSTRING(file)->ptr, MY_BLOCK_SIZE, 
			O_RDONLY, mode, MY_FATAL_FUNC);

    if (!dbm) {
	if (mode == -1) return Qnil;
	rb_sys_fail(RSTRING(file)->ptr);
    }

    obj = Data_Make_Struct(klass,struct dbmdata,0,free_dbm,dbmp);
    dbmp->di_dbm = dbm;
    dbmp->di_size = -1;
    rb_obj_call_init(obj, argc, argv);

    return obj;
}

static VALUE
fgdbm_close(obj)
    VALUE obj;
{
    struct dbmdata *dbmp;

    GetDBM(obj, dbmp);
    gdbm_close(dbmp->di_dbm);
    dbmp->di_dbm = 0;

    return Qnil;
}

static VALUE
fgdbm_fetch(obj, keystr)
    VALUE obj, keystr;
{
    datum key, value;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    value = gdbm_fetch(dbm, key);
    if (value.dptr == 0) {
	return Qnil;
    }
    return rb_tainted_str_new(value.dptr, value.dsize);
}

static VALUE
fgdbm_indexes(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE new;
    int i;

    new = rb_ary_new2(argc);
    for (i=0; i<argc; i++) {
	rb_ary_push(new, fgdbm_fetch(obj, argv[i]));
    }

    return new;
}

static VALUE
fgdbm_delete(obj, keystr)
    VALUE obj, keystr;
{
    datum key, value;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    rb_secure(4);
    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    value = gdbm_fetch(dbm, key);
    if (value.dptr == 0) {
	if (rb_iterator_p()) rb_yield(keystr);
	return Qnil;
    }

    if (gdbm_delete(dbm, key)) {
	dbmp->di_size = -1;
	rb_raise(rb_eRuntimeError, "dbm_delete failed");
    }
    else if (dbmp->di_size >= 0) {
	dbmp->di_size--;
    }
    return obj;
}

static VALUE
fgdbm_shift(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;
    VALUE keystr, valstr;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    key = gdbm_firstkey(dbm); 
    if (!key.dptr) return Qnil;
    val = gdbm_fetch(dbm, key);
    gdbm_delete(dbm, key);

    keystr = rb_tainted_str_new(key.dptr, key.dsize);
    valstr = rb_tainted_str_new(val.dptr, val.dsize);
    return rb_assoc_new(keystr, valstr);
}

static VALUE
fgdbm_delete_if(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;
    VALUE keystr, valstr;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	val = gdbm_fetch(dbm, key);
	keystr = rb_tainted_str_new(key.dptr, key.dsize);
	valstr = rb_tainted_str_new(val.dptr, val.dsize);
	if (RTEST(rb_yield(rb_assoc_new(keystr, valstr)))) {
	    if (gdbm_delete(dbm, key)) {
		rb_raise(rb_eRuntimeError, "dbm_delete failed");
	    }
	}
    }
    return obj;
}

static VALUE
fgdbm_clear(obj)
    VALUE obj;
{
    datum key, nextkey;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    dbmp->di_size = -1;
    for (key = gdbm_firstkey(dbm); key.dptr; key = nextkey) {
	nextkey = gdbm_nextkey(dbm, key);
	if (gdbm_delete(dbm, key)) {
	    rb_raise(rb_eRuntimeError, "dbm_delete failed");
	}
    }
    return obj;
}

static VALUE
fgdbm_invert(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;
    VALUE keystr, valstr;
    VALUE hash = rb_hash_new();

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	val = gdbm_fetch(dbm, key);
	keystr = rb_tainted_str_new(key.dptr, key.dsize);
	valstr = rb_tainted_str_new(val.dptr, val.dsize);
	rb_hash_aset(hash, valstr, keystr);
    }
    return hash;
}

static VALUE
each_pair(obj)
    VALUE obj;
{
    return rb_funcall(obj, rb_intern("each_pair"), 0, 0);
}

static VALUE fgdbm_store _((VALUE,VALUE,VALUE));

static VALUE
update_i(pair, dbm)
    VALUE pair, dbm;
{
    Check_Type(pair, T_ARRAY);
    if (RARRAY(pair)->len < 2) {
	rb_raise(rb_eArgError, "pair must be [key, value]");
    }
    fgdbm_store(dbm, RARRAY(pair)->ptr[0], RARRAY(pair)->ptr[1]);
    return Qnil;
}

static VALUE
fgdbm_update(obj, other)
    VALUE obj, other;
{
    rb_iterate(each_pair, other, update_i, obj);
    return obj;
}

static VALUE
fgdbm_replace(obj, other)
    VALUE obj, other;
{
    fgdbm_clear(obj);
    rb_iterate(each_pair, other, update_i, obj);
    return obj;
}

static VALUE
fgdbm_store(obj, keystr, valstr)
    VALUE obj, keystr, valstr;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    if (valstr == Qnil) {
	fgdbm_delete(obj, keystr);
	return Qnil;
    }

    rb_secure(4);
    keystr = rb_obj_as_string(keystr);

    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    if (NIL_P(valstr)) return fgdbm_delete(obj, keystr);

    valstr = rb_obj_as_string(valstr);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM(obj, dbmp);
    dbmp->di_size = -1;
    dbm = dbmp->di_dbm;
    if (gdbm_store(dbm, key, val, GDBM_REPLACE)) {
	if (errno == EPERM) rb_sys_fail(0);
	rb_raise(rb_eRuntimeError, "dbm_store failed");
    }

    return valstr;
}

static VALUE
fgdbm_length(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;
    int i = 0;

    GetDBM(obj, dbmp);
    if (dbmp->di_size > 0) return INT2FIX(dbmp->di_size);
    dbm = dbmp->di_dbm;

    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	i++;
    }
    dbmp->di_size = i;

    return INT2FIX(i);
}

static VALUE
fgdbm_empty_p(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;
    int i = 0;

    GetDBM(obj, dbmp);
    if (dbmp->di_size < 0) {
	dbm = dbmp->di_dbm;

	for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	    i++;
	}
    }
    else {
	i = dbmp->di_size;
    }
    if (i == 0) return Qtrue;
    return Qfalse;
}

static VALUE
fgdbm_each_value(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	val = gdbm_fetch(dbm, key);
	rb_yield(rb_tainted_str_new(val.dptr, val.dsize));
    }
    return obj;
}

static VALUE
fgdbm_each_key(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	rb_yield(rb_tainted_str_new(key.dptr, key.dsize));
    }
    return obj;
}

static VALUE
fgdbm_each_pair(obj)
    VALUE obj;
{
    datum key, val;
    GDBM_FILE dbm;
    struct dbmdata *dbmp;
    VALUE keystr, valstr;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	val = gdbm_fetch(dbm, key);
	keystr = rb_tainted_str_new(key.dptr, key.dsize);
	valstr = rb_tainted_str_new(val.dptr, val.dsize);
	rb_yield(rb_assoc_new(keystr, valstr));
    }

    return obj;
}

static VALUE
fgdbm_keys(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	rb_ary_push(ary, rb_tainted_str_new(key.dptr, key.dsize));
    }

    return ary;
}

static VALUE
fgdbm_values(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	val = gdbm_fetch(dbm, key);
	rb_ary_push(ary, rb_tainted_str_new(val.dptr, val.dsize));
    }

    return ary;
}

static VALUE
fgdbm_has_key(obj, keystr)
    VALUE obj, keystr;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    val = gdbm_fetch(dbm, key);
    if (val.dptr) return Qtrue;
    return Qfalse;
}

static VALUE
fgdbm_has_value(obj, valstr)
    VALUE obj, valstr;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    Check_Type(valstr, T_STRING);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	val = gdbm_fetch(dbm, key);
	if (val.dsize == RSTRING(valstr)->len &&
	    memcmp(val.dptr, RSTRING(valstr)->ptr, val.dsize) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

static VALUE
fgdbm_to_a(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    GDBM_FILE dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = gdbm_firstkey(dbm); key.dptr; key = gdbm_nextkey(dbm, key)) {
	val = gdbm_fetch(dbm, key);
	rb_ary_push(ary, rb_assoc_new(rb_tainted_str_new(key.dptr, key.dsize),
				rb_tainted_str_new(val.dptr, val.dsize)));
    }

    return ary;
}

static VALUE
fgdbm_reorganize(obj)
    VALUE obj;
{
    struct dbmdata *dbmp;
    GDBM_FILE dbm;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    gdbm_reorganize(dbm);
    return obj;
}

void
Init_gdbm()
{
    cGDBM = rb_define_class("GDBM", rb_cObject);
    rb_include_module(cGDBM, rb_mEnumerable);

    rb_define_singleton_method(cGDBM, "open", fgdbm_s_open, -1);
    rb_define_singleton_method(cGDBM, "new", fgdbm_s_open, -1);
    rb_define_method(cGDBM, "close", fgdbm_close, 0);
    rb_define_method(cGDBM, "[]", fgdbm_fetch, 1);
    rb_define_method(cGDBM, "[]=", fgdbm_store, 2);
    rb_define_method(cGDBM, "indexes",  fgdbm_indexes, -1);
    rb_define_method(cGDBM, "indices",  fgdbm_indexes, -1);
    rb_define_method(cGDBM, "length", fgdbm_length, 0);
    rb_define_alias(cGDBM,  "size", "length");
    rb_define_method(cGDBM, "empty?", fgdbm_empty_p, 0);
    rb_define_method(cGDBM, "each", fgdbm_each_pair, 0);
    rb_define_method(cGDBM, "each_value", fgdbm_each_value, 0);
    rb_define_method(cGDBM, "each_key", fgdbm_each_key, 0);
    rb_define_method(cGDBM, "each_pair", fgdbm_each_pair, 0);
    rb_define_method(cGDBM, "keys", fgdbm_keys, 0);
    rb_define_method(cGDBM, "values", fgdbm_values, 0);
    rb_define_method(cGDBM, "shift", fgdbm_shift, 1);
    rb_define_method(cGDBM, "delete", fgdbm_delete, 1);
    rb_define_method(cGDBM, "delete_if", fgdbm_delete_if, 0);
    rb_define_method(cGDBM, "clear", fgdbm_clear, 0);
    rb_define_method(cGDBM,"invert", fgdbm_invert, 0);
    rb_define_method(cGDBM,"update", fgdbm_update, 1);
    rb_define_method(cGDBM,"replace", fgdbm_replace, 1);
    rb_define_method(cGDBM,"reorganize", fgdbm_reorganize, 0);

    rb_define_method(cGDBM, "include?", fgdbm_has_key, 1);
    rb_define_method(cGDBM, "has_key?", fgdbm_has_key, 1);
    rb_define_method(cGDBM, "has_value?", fgdbm_has_value, 1);
    rb_define_method(cGDBM, "key?", fgdbm_has_key, 1);
    rb_define_method(cGDBM, "value?", fgdbm_has_value, 1);

    rb_define_method(cGDBM, "to_a", fgdbm_to_a, 0);
}
