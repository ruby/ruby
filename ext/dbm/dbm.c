/************************************************

  dbm.c -

  $Author$
  $Date$
  created at: Mon Jan 24 15:59:52 JST 1994

  Copyright (C) 1995-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

#include <ndbm.h>
#include <fcntl.h>
#include <errno.h>
#ifdef USE_CWGUSI
# include <sys/errno.h>
#endif

VALUE cDBM;

extern VALUE rb_mEnumerable;

struct dbmdata {
    int  di_size;
    DBM *di_dbm;
};

static void
closed_dbm()
{
    rb_raise(rb_eRuntimeError, "closed DBM file");
}

#define GetDBM(obj, dbmp) {\
    Data_Get_Struct(obj, struct dbmdata, dbmp);\
    if (dbmp->di_dbm == 0) closed_dbm();\
}

static void
free_dbm(dbmp)
    struct dbmdata *dbmp;
{
    if (dbmp->di_dbm) dbm_close(dbmp->di_dbm);
    free(dbmp);
}

static VALUE
fdbm_s_open(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE file, vmode;
    DBM *dbm;
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
	dbm = dbm_open(RSTRING(file)->ptr, O_RDWR|O_CREAT, mode);
    if (!dbm)
	dbm = dbm_open(RSTRING(file)->ptr, O_RDWR, mode);
    if (!dbm)
	dbm = dbm_open(RSTRING(file)->ptr, O_RDONLY, mode);

    if (!dbm) {
	if (mode == -1) return Qnil;
	rb_sys_fail(RSTRING(file)->ptr);
    }

    obj = Data_Make_Struct(class,struct dbmdata,0,free_dbm,dbmp);
    dbmp->di_dbm = dbm;
    dbmp->di_size = -1;
    rb_obj_call_init(obj);

    return obj;
}

static VALUE
fdbm_close(obj)
    VALUE obj;
{
    struct dbmdata *dbmp;

    Data_Get_Struct(obj, struct dbmdata, dbmp);
    if (dbmp->di_dbm == 0) closed_dbm();
    dbm_close(dbmp->di_dbm);
    dbmp->di_dbm = 0;

    return Qnil;
}

static VALUE
fdbm_fetch(obj, keystr)
    VALUE obj, keystr;
{
    datum key, value;
    struct dbmdata *dbmp;
    DBM *dbm;

    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    value = dbm_fetch(dbm, key);
    if (value.dptr == 0) {
	return Qnil;
    }
    return rb_str_taint(rb_str_new(value.dptr, value.dsize));
}

static VALUE
fdbm_indexes(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE new;
    int i;

    new = rb_ary_new2(argc);
    for (i=0; i<argc; i++) {
	rb_ary_push(new, fdbm_fetch(obj, argv[i]));
    }

    return new;
}

static VALUE
fdbm_delete(obj, keystr)
    VALUE obj, keystr;
{
    datum key, value;
    struct dbmdata *dbmp;
    DBM *dbm;

    rb_secure(4);
    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    value = dbm_fetch(dbm, key);
    if (value.dptr == 0) {
	if (rb_iterator_p()) rb_yield(keystr);
	return Qnil;
    }

    if (dbm_delete(dbm, key)) {
	dbmp->di_size = -1;
	rb_raise(rb_eRuntimeError, "dbm_delete failed");
    }
    else if (dbmp->di_size >= 0) {
	dbmp->di_size--;
    }
    return obj;
}

static VALUE
fdbm_shift(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE keystr, valstr;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    key = dbm_firstkey(dbm); 
    if (!key.dptr) return Qnil;
    val = dbm_fetch(dbm, key);
    dbm_delete(dbm, key);

    keystr = rb_str_taint(rb_str_new(key.dptr, key.dsize));
    valstr = rb_str_taint(rb_str_new(val.dptr, val.dsize));
    return rb_assoc_new(keystr, valstr);
}

static VALUE
fdbm_delete_if(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE keystr, valstr;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	keystr = rb_str_taint(rb_str_new(key.dptr, key.dsize));
	valstr = rb_str_taint(rb_str_new(val.dptr, val.dsize));
	if (RTEST(rb_yield(rb_assoc_new(keystr, valstr)))) {
	    if (dbm_delete(dbm, key)) {
		rb_raise(rb_eRuntimeError, "dbm_delete failed");
	    }
	}
    }
    return obj;
}

static VALUE
fdbm_clear(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    dbmp->di_size = -1;
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	if (dbm_delete(dbm, key)) {
	    rb_raise(rb_eRuntimeError, "dbm_delete failed");
	}
    }
    return obj;
}

static VALUE
fdbm_invert(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE keystr, valstr;
    VALUE hash = rb_hash_new();

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	keystr = rb_str_taint(rb_str_new(key.dptr, key.dsize));
	valstr = rb_str_taint(rb_str_new(val.dptr, val.dsize));
	rb_hash_aset(hash, valstr, keystr);
    }
    return obj;
}

static VALUE
each_pair(obj)
    VALUE obj;
{
    return rb_funcall(obj, rb_intern("each_pair"), 0, 0);
}

static VALUE fdbm_store _((VALUE,VALUE,VALUE));

static VALUE
update_i(pair, dbm)
    VALUE pair, dbm;
{
    Check_Type(pair, T_ARRAY);
    if (RARRAY(pair)->len < 2) {
	rb_raise(rb_eArgError, "pair must be [key, value]");
    }
    fdbm_store(dbm, RARRAY(pair)->ptr[0], RARRAY(pair)->ptr[1]);
    return Qnil;
}

static VALUE
fdbm_update(obj, other)
    VALUE obj, other;
{
    rb_iterate(each_pair, other, update_i, obj);
    return obj;
}

static VALUE
fdbm_replace(obj, other)
    VALUE obj, other;
{
    fdbm_clear(obj);
    rb_iterate(each_pair, other, update_i, obj);
    return obj;
}

static VALUE
fdbm_store(obj, keystr, valstr)
    VALUE obj, keystr, valstr;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    if (valstr == Qnil) {
	fdbm_delete(obj, keystr);
	return Qnil;
    }

    rb_secure(4);
    keystr = rb_obj_as_string(keystr);

    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    if (NIL_P(valstr)) return fdbm_delete(obj, keystr);

    valstr = rb_obj_as_string(valstr);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    Data_Get_Struct(obj, struct dbmdata, dbmp);
    dbmp->di_size = -1;
    dbm = dbmp->di_dbm;
    if (dbm_store(dbm, key, val, DBM_REPLACE)) {
#ifdef HAVE_DBM_CLAERERR
	dbm_clearerr(dbm);
#endif
	if (errno == EPERM) rb_sys_fail(0);
	rb_raise(rb_eRuntimeError, "dbm_store failed");
    }

    return valstr;
}

static VALUE
fdbm_length(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;
    int i = 0;

    Data_Get_Struct(obj, struct dbmdata, dbmp);
    if (dbmp->di_size > 0) return INT2FIX(dbmp->di_size);
    dbm = dbmp->di_dbm;

    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	i++;
    }
    dbmp->di_size = i;

    return INT2FIX(i);
}

static VALUE
fdbm_empty_p(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;
    int i = 0;

    Data_Get_Struct(obj, struct dbmdata, dbmp);
    if (dbmp->di_size < 0) {
	dbm = dbmp->di_dbm;

	for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
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
fdbm_each_value(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	rb_yield(rb_str_taint(rb_str_new(val.dptr, val.dsize)));
    }
    return obj;
}

static VALUE
fdbm_each_key(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	rb_yield(rb_str_taint(rb_str_new(key.dptr, key.dsize)));
    }
    return obj;
}

static VALUE
fdbm_each_pair(obj)
    VALUE obj;
{
    datum key, val;
    DBM *dbm;
    struct dbmdata *dbmp;
    VALUE keystr, valstr;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	keystr = rb_str_taint(rb_str_new(key.dptr, key.dsize));
	valstr = rb_str_taint(rb_str_new(val.dptr, val.dsize));
	rb_yield(rb_assoc_new(keystr, valstr));
    }

    return obj;
}

static VALUE
fdbm_keys(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	rb_ary_push(ary, rb_str_taint(rb_str_new(key.dptr, key.dsize)));
    }

    return ary;
}

static VALUE
fdbm_values(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	rb_ary_push(ary, rb_str_taint(rb_str_new(val.dptr, val.dsize)));
    }

    return ary;
}

static VALUE
fdbm_has_key(obj, keystr)
    VALUE obj, keystr;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    val = dbm_fetch(dbm, key);
    if (val.dptr) return Qtrue;
    return Qfalse;
}

static VALUE
fdbm_has_value(obj, valstr)
    VALUE obj, valstr;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    Check_Type(valstr, T_STRING);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	if (val.dsize == RSTRING(valstr)->len &&
	    memcmp(val.dptr, RSTRING(valstr)->ptr, val.dsize) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

static VALUE
fdbm_to_a(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	rb_ary_push(ary, rb_assoc_new(rb_str_taint(rb_str_new(key.dptr, key.dsize)),
				rb_str_taint(rb_str_new(val.dptr, val.dsize))));
    }

    return ary;
}

Init_dbm()
{
    cDBM = rb_define_class("DBM", rb_cObject);
    rb_include_module(cDBM, rb_mEnumerable);

    rb_define_singleton_method(cDBM, "open", fdbm_s_open, -1);
    rb_define_singleton_method(cDBM, "new", fdbm_s_open, -1);
    rb_define_method(cDBM, "close", fdbm_close, 0);
    rb_define_method(cDBM, "[]", fdbm_fetch, 1);
    rb_define_method(cDBM, "[]=", fdbm_store, 2);
    rb_define_method(cDBM, "indexes",  fdbm_indexes, -1);
    rb_define_method(cDBM, "indices",  fdbm_indexes, -1);
    rb_define_method(cDBM, "length", fdbm_length, 0);
    rb_define_alias(cDBM,  "size", "length");
    rb_define_method(cDBM, "empty?", fdbm_empty_p, 0);
    rb_define_method(cDBM, "each", fdbm_each_pair, 0);
    rb_define_method(cDBM, "each_value", fdbm_each_value, 0);
    rb_define_method(cDBM, "each_key", fdbm_each_key, 0);
    rb_define_method(cDBM, "each_pair", fdbm_each_pair, 0);
    rb_define_method(cDBM, "keys", fdbm_keys, 0);
    rb_define_method(cDBM, "values", fdbm_values, 0);
    rb_define_method(cDBM, "shift", fdbm_shift, 1);
    rb_define_method(cDBM, "delete", fdbm_delete, 1);
    rb_define_method(cDBM, "delete_if", fdbm_delete_if, 0);
    rb_define_method(cDBM, "clear", fdbm_clear, 0);
    rb_define_method(cDBM,"invert", fdbm_invert, 0);
    rb_define_method(cDBM,"update", fdbm_update, 1);
    rb_define_method(cDBM,"replace", fdbm_replace, 1);

    rb_define_method(cDBM, "include?", fdbm_has_key, 1);
    rb_define_method(cDBM, "has_key?", fdbm_has_key, 1);
    rb_define_method(cDBM, "has_value?", fdbm_has_value, 1);
    rb_define_method(cDBM, "key?", fdbm_has_key, 1);
    rb_define_method(cDBM, "value?", fdbm_has_value, 1);

    rb_define_method(cDBM, "to_a", fdbm_to_a, 0);
}
