/************************************************

  dbm.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:24 $
  created at: Mon Jan 24 15:59:52 JST 1994

  Copyright (C) 1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

#include <ndbm.h>
#include <fcntl.h>
#include <errno.h>

VALUE cDBM;
static ID id_dbm;

extern VALUE mEnumerable;

static void
closeddbm()
{
    Fail("closed DBM file");
}

#define GetDBM(obj, dbmp) {\
    DBM **_dbm;\
    Get_Data_Struct(obj, id_dbm, DBM*, _dbm);\
    dbmp = *_dbm;\
    if (dbmp == Qnil) closeddbm();\
}

static void
free_dbm(dbmp)
    DBM **dbmp;
{
    if (*dbmp) dbm_close(*dbmp);
}

#define MakeDBM(obj, dp) {\
    DBM **_dbm;\
    if (!id_dbm) id_dbm = rb_intern("dbm");\
    Make_Data_Struct(obj,id_dbm,DBM*,Qnil,free_dbm,_dbm);\
    *_dbm=dp;\
}

static VALUE
fdbm_s_open(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE file, vmode;
    DBM *dbm, **dbm2;
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
    Check_Type(file, T_STRING);

    dbm = Qnil;
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

    obj = obj_alloc(class);
    MakeDBM(obj, dbm);

    return obj;
}

static VALUE
fdbm_close(obj)
    VALUE obj;
{
    DBM **dbmp;

    Get_Data_Struct(obj, id_dbm, DBM*, dbmp);
    if (*dbmp == Qnil) Fail("already closed DBM file");
    dbm_close(*dbmp);
    *dbmp = Qnil;

    return Qnil;
}

static VALUE
fdbm_fetch(obj, keystr)
    VALUE obj, keystr;
{
    datum key, value;
    DBM *dbm;

    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbm);
    value = dbm_fetch(dbm, key);
    if (value.dptr == Qnil) {
	return Qnil;
    }
    return str_new(value.dptr, value.dsize);
}

static VALUE
fdbm_indexes(obj, args)
    VALUE obj;
    struct RArray *args;
{
    VALUE *p, *pend;
    struct RArray *new;
    int i = 0;

    if (!args || args->len == 1 && TYPE(args->ptr) != T_ARRAY) {
	args = (struct RArray*)rb_to_a(args->ptr[0]);
    }

    new = (struct RArray*)ary_new2(args->len);

    p = args->ptr; pend = p + args->len;
    while (p < pend) {
	new->ptr[i++] = fdbm_fetch(obj, *p++);
	new->len = i;
    }
    return (VALUE)new;
}

static VALUE
fdbm_delete(obj, keystr)
    VALUE obj, keystr;
{
    datum key;
    DBM *dbm;

    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbm);
    if (dbm_delete(dbm, key)) {
	Fail("dbm_delete failed");
    }
    return obj;
}

static VALUE
fdbm_shift(obj)
    VALUE obj;
{
    datum key, val;
    DBM *dbm;
    VALUE keystr, valstr;

    GetDBM(obj, dbm);

    key = dbm_firstkey(dbm); 
    if (!key.dptr) return Qnil;
    val = dbm_fetch(dbm, key);
    dbm_delete(dbm, key);

    keystr = str_new(key.dptr, key.dsize);
    valstr = str_new(val.dptr, val.dsize);
    return assoc_new(keystr, valstr);
}

static VALUE
fdbm_delete_if(obj)
    VALUE obj;
{
    datum key, val;
    DBM *dbm;
    VALUE keystr, valstr;

    GetDBM(obj, dbm);
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	keystr = str_new(key.dptr, key.dsize);
	valstr = str_new(val.dptr, val.dsize);
	if (rb_yield(assoc_new(keystr, valstr))
	    && dbm_delete(dbm, key)) {
	    Fail("dbm_delete failed");
	}
    }
    return obj;
}

static VALUE
fdbm_clear(obj)
    VALUE obj;
{
    datum key;
    DBM *dbm;

    GetDBM(obj, dbm);
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	if (dbm_delete(dbm, key)) {
	    Fail("dbm_delete failed");
	}
    }
    return obj;
}

static VALUE
fdbm_store(obj, keystr, valstr)
    VALUE obj, keystr, valstr;
{
    datum key, val;
    DBM *dbm;

    if (valstr == Qnil) {
	fdbm_delete(obj, keystr);
	return Qnil;
    }

    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;
    Check_Type(valstr, T_STRING);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM(obj, dbm);
    if (dbm_store(dbm, key, val, DBM_REPLACE)) {
	dbm_clearerr(dbm);
	if (errno == EPERM) rb_sys_fail(Qnil);
	Fail("dbm_store failed");
    }
    return valstr;
}

static VALUE
fdbm_length(obj)
    VALUE obj;
{
    datum key;
    DBM *dbm;
    int i = 0;

    GetDBM(obj, dbm);
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	i++;
    }
    return INT2FIX(i);
}

static VALUE
fdbm_each_value(obj)
    VALUE obj;
{
    datum key, val;
    DBM *dbm;

    GetDBM(obj, dbm);
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	rb_yield(str_new(val.dptr, val.dsize));
    }
    return obj;
}

static VALUE
fdbm_each_key(obj)
    VALUE obj;
{
    datum key;
    DBM *dbm;

    GetDBM(obj, dbm);
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	rb_yield(str_new(key.dptr, key.dsize));
    }
    return obj;
}

static VALUE
fdbm_each_pair(obj)
    VALUE obj;
{
    datum key, val;
    DBM *dbm;
    VALUE keystr, valstr;

    GetDBM(obj, dbm);

    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	keystr = str_new(key.dptr, key.dsize);
	valstr = str_new(val.dptr, val.dsize);
	rb_yield(assoc_new(keystr, valstr));
    }

    return obj;
}

static VALUE
fdbm_keys(obj)
    VALUE obj;
{
    datum key;
    DBM *dbm;
    VALUE ary;

    ary = ary_new();
    GetDBM(obj, dbm);
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	ary_push(ary, str_new(key.dptr, key.dsize));
    }

    return ary;
}

static VALUE
fdbm_values(obj)
    VALUE obj;
{
    datum key, val;
    DBM *dbm;
    VALUE ary;

    ary = ary_new();
    GetDBM(obj, dbm);
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	ary_push(ary, str_new(val.dptr, val.dsize));
    }

    return ary;
}

static VALUE
fdbm_has_key(obj, keystr)
    VALUE obj, keystr;
{
    datum key, val;
    DBM *dbm;

    Check_Type(keystr, T_STRING);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbm);
    val = dbm_fetch(dbm, key);
    if (val.dptr) return TRUE;
    return FALSE;
}

static VALUE
fdbm_has_value(obj, valstr)
    VALUE obj, valstr;
{
    datum key, val;
    DBM *dbm;

    Check_Type(valstr, T_STRING);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM(obj, dbm);
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	if (val.dsize == RSTRING(valstr)->len &&
	    memcmp(val.dptr, RSTRING(valstr)->ptr, val.dsize) == 0)
	    return TRUE;
    }
    return FALSE;
}

static VALUE
fdbm_to_a(obj)
    VALUE obj;
{
    datum key, val;
    DBM *dbm;
    VALUE ary;

    GetDBM(obj, dbm);

    ary = ary_new();
    for (key = dbm_firstkey(dbm); key.dptr; key = dbm_nextkey(dbm)) {
	val = dbm_fetch(dbm, key);
	ary_push(ary, assoc_new(str_new(key.dptr, key.dsize),
				str_new(val.dptr, val.dsize)));
    }

    return ary;
}

Init_dbm()
{
    cDBM = rb_define_class("DBM", cObject);
    rb_include_module(cDBM, mEnumerable);

    rb_define_singleton_method(cDBM, "open", fdbm_s_open, -1);
    rb_define_method(cDBM, "close", fdbm_close, 0);
    rb_define_method(cDBM, "[]", fdbm_fetch, 1);
    rb_define_method(cDBM, "[]=", fdbm_store, 2);
    rb_define_method(cDBM, "indexes",  fdbm_indexes, -2);
    rb_define_method(cDBM, "length", fdbm_length, 0);
    rb_define_alias(cDBM,  "size", "length");
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
    rb_define_method(cDBM, "includes", fdbm_has_key, 1);
    rb_define_method(cDBM, "has_key", fdbm_has_key, 1);
    rb_define_method(cDBM, "has_value", fdbm_has_value, 1);

    rb_define_method(cDBM, "to_a", fdbm_to_a, 0);
}
