/************************************************

  sdbminit.c -

  $Author$
  $Date$
  created at: Fri May  7 08:34:24 JST 1999

  Copyright (C) 1995-2001 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

#include "sdbm.h"
#include <fcntl.h>
#include <errno.h>

static VALUE cSDBM;

struct dbmdata {
    int  di_size;
    DBM *di_dbm;
};

static void
closed_sdbm()
{
    rb_raise(rb_eRuntimeError, "closed SDBM file");
}

#define GetDBM(obj, dbmp) {\
    Data_Get_Struct(obj, struct dbmdata, dbmp);\
    if (dbmp->di_dbm == 0) closed_sdbm();\
}

static void
free_sdbm(dbmp)
    struct dbmdata *dbmp;
{

    if (dbmp->di_dbm) sdbm_close(dbmp->di_dbm);
    free(dbmp);
}

static VALUE
fsdbm_close(obj)
    VALUE obj;
{
    struct dbmdata *dbmp;

    GetDBM(obj, dbmp);
    sdbm_close(dbmp->di_dbm);
    dbmp->di_dbm = 0;

    return Qnil;
}

static VALUE
fsdbm_initialize(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE file, vmode;
    DBM *dbm;
    struct dbmdata *dbmp;
    int mode;

    if (rb_scan_args(argc, argv, "11", &file, &vmode) == 1) {
	mode = 0666;		/* default value */
    }
    else if (NIL_P(vmode)) {
	mode = -1;		/* return nil if DB not exist */
    }
    else {
	mode = NUM2INT(vmode);
    }
    file = rb_str_to_str(file);
    Check_SafeStr(file);

    dbm = 0;
    if (mode >= 0)
	dbm = sdbm_open(RSTRING(file)->ptr, O_RDWR|O_CREAT, mode);
    if (!dbm)
	dbm = sdbm_open(RSTRING(file)->ptr, O_RDWR, 0);
    if (!dbm)
	dbm = sdbm_open(RSTRING(file)->ptr, O_RDONLY, 0);

    if (!dbm) {
	if (mode == -1) return Qnil;
	rb_sys_fail(RSTRING(file)->ptr);
    }

    dbmp = ALLOC(struct dbmdata);
    DATA_PTR(obj) = dbmp;
    dbmp->di_dbm = dbm;
    dbmp->di_size = -1;

    return obj;
}

static VALUE
fsdbm_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE obj = Data_Wrap_Struct(klass, 0, free_sdbm, 0);
    rb_obj_call_init(obj, argc, argv);
    return obj;
}

static VALUE
fsdbm_s_open(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE obj = Data_Wrap_Struct(klass, 0, free_sdbm, 0);

    if (NIL_P(fsdbm_initialize(argc, argv, obj))) {
	return Qnil;
    }

    if (rb_block_given_p()) {
        return rb_ensure(rb_yield, obj, fsdbm_close, obj);
    }

    return obj;
}

static VALUE
fsdbm_fetch(obj, keystr, ifnone)
    VALUE obj, keystr, ifnone;
{
    datum key, value;
    struct dbmdata *dbmp;
    DBM *dbm;

    keystr = rb_str_to_str(keystr);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    value = sdbm_fetch(dbm, key);
    if (value.dptr == 0) {
	if (ifnone == Qnil && rb_block_given_p())
	    return rb_yield(rb_tainted_str_new(key.dptr, key.dsize));
	return ifnone;
    }
    return rb_tainted_str_new(value.dptr, value.dsize);
}

static VALUE
fsdbm_aref(obj, keystr)
    VALUE obj, keystr;
{
    return fsdbm_fetch(obj, keystr, Qnil);
}

static VALUE
fsdbm_fetch_m(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE keystr, valstr, ifnone;

    rb_scan_args(argc, argv, "11", &keystr, &ifnone);
    valstr = fsdbm_fetch(obj, keystr, ifnone);
    if (argc == 1 && !rb_block_given_p() && NIL_P(valstr))
	rb_raise(rb_eIndexError, "key not found");

    return valstr;
}

static VALUE
fsdbm_index(obj, valstr)
    VALUE obj, valstr;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    valstr = rb_str_to_str(valstr);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	if (val.dsize == RSTRING(valstr)->len &&
	    memcmp(val.dptr, RSTRING(valstr)->ptr, val.dsize) == 0)
	    return rb_tainted_str_new(key.dptr, key.dsize);
    }
    return Qnil;
}

static VALUE
fsdbm_indexes(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE new;
    int i;

    new = rb_ary_new2(argc);
    for (i=0; i<argc; i++) {
	rb_ary_push(new, fsdbm_fetch(obj, argv[i]));
    }

    return new;
}

static VALUE
fsdbm_delete(obj, keystr)
    VALUE obj, keystr;
{
    datum key, value;
    struct dbmdata *dbmp;
    DBM *dbm;

    rb_secure(4);
    keystr = rb_str_to_str(keystr);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    dbmp->di_size = -1;

    value = sdbm_fetch(dbm, key);
    if (value.dptr == 0) {
	if (rb_block_given_p()) rb_yield(keystr);
	return Qnil;
    }

    if (sdbm_delete(dbm, key)) {
	dbmp->di_size = -1;
	rb_raise(rb_eRuntimeError, "dbm_delete failed");
    }
    else if (dbmp->di_size >= 0) {
	dbmp->di_size--;
    }
    return obj;
}

static VALUE
fsdbm_shift(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE keystr, valstr;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    key = sdbm_firstkey(dbm); 
    if (!key.dptr) return Qnil;
    val = sdbm_fetch(dbm, key);
    keystr = rb_tainted_str_new(key.dptr, key.dsize);
    valstr = rb_tainted_str_new(val.dptr, val.dsize);
    sdbm_delete(dbm, key);
    if (dbmp->di_size >= 0) {
	dbmp->di_size--;
    }

    return rb_assoc_new(keystr, valstr);
}

static VALUE
fsdbm_delete_if(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE keystr, valstr;
    VALUE ret, ary = rb_ary_new();
    int i, status = 0, n;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    n = dbmp->di_size;
    dbmp->di_size = -1;
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	keystr = rb_tainted_str_new(key.dptr, key.dsize);
	valstr = rb_tainted_str_new(val.dptr, val.dsize);
        ret = rb_protect(rb_yield, rb_assoc_new(rb_str_dup(keystr), valstr), &status);
        if (status != 0) goto delete;
	if (RTEST(ret)) rb_ary_push(ary, keystr);
    }
 delete:
    for (i = 0; i < RARRAY(ary)->len; i++) {
	keystr = RARRAY(ary)->ptr[i];
	key.dptr = RSTRING(keystr)->ptr;
	key.dsize = RSTRING(keystr)->len;
	if (sdbm_delete(dbm, key)) {
	    rb_raise(rb_eRuntimeError, "sdbm_delete failed");
	}
    }
    if (status) rb_jump_tag(status);
    if (n > 0) dbmp->di_size = n - RARRAY(ary)->len;

    return obj;
}

static VALUE
fsdbm_clear(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;

    rb_secure(4);
    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    dbmp->di_size = -1;
    while (key = sdbm_firstkey(dbm), key.dptr) {
        do {
	    if (sdbm_delete(dbm, key)) {
		rb_raise(rb_eRuntimeError, "sdbm_delete failed");
	    }
	    key = sdbm_nextkey(dbm);
	} while (key.dptr);
    }
    dbmp->di_size = 0;

    return obj;
}

static VALUE
fsdbm_invert(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE keystr, valstr;
    VALUE hash = rb_hash_new();

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
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

static VALUE fsdbm_store _((VALUE,VALUE,VALUE));

static VALUE
update_i(pair, dbm)
    VALUE pair, dbm;
{
    Check_Type(pair, T_ARRAY);
    if (RARRAY(pair)->len < 2) {
	rb_raise(rb_eArgError, "pair must be [key, value]");
    }
    fsdbm_store(dbm, RARRAY(pair)->ptr[0], RARRAY(pair)->ptr[1]);
    return Qnil;
}

static VALUE
fsdbm_update(obj, other)
    VALUE obj, other;
{
    rb_iterate(each_pair, other, update_i, obj);
    return obj;
}

static VALUE
fsdbm_replace(obj, other)
    VALUE obj, other;
{
    fsdbm_clear(obj);
    rb_iterate(each_pair, other, update_i, obj);
    return obj;
}

static VALUE
fsdbm_store(obj, keystr, valstr)
    VALUE obj, keystr, valstr;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    if (valstr == Qnil) {
	fsdbm_delete(obj, keystr);
	return Qnil;
    }

    rb_secure(4);
    keystr = rb_obj_as_string(keystr);

    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    if (NIL_P(valstr)) return fsdbm_delete(obj, keystr);

    valstr = rb_obj_as_string(valstr);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM(obj, dbmp);
    dbmp->di_size = -1;
    dbm = dbmp->di_dbm;
    if (sdbm_store(dbm, key, val, DBM_REPLACE)) {
#ifdef HAVE_DBM_CLAERERR
	sdbm_clearerr(dbm);
#endif
	if (errno == EPERM) rb_sys_fail(0);
	rb_raise(rb_eRuntimeError, "sdbm_store failed");
    }

    return valstr;
}

static VALUE
fsdbm_length(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;
    int i = 0;

    GetDBM(obj, dbmp);
    if (dbmp->di_size > 0) return INT2FIX(dbmp->di_size);
    dbm = dbmp->di_dbm;

    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	i++;
    }
    dbmp->di_size = i;

    return INT2FIX(i);
}

static VALUE
fsdbm_empty_p(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;
    int i = 0;

    GetDBM(obj, dbmp);
    if (dbmp->di_size < 0) {
	dbm = dbmp->di_dbm;

	for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
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
fsdbm_each_value(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_yield(rb_tainted_str_new(val.dptr, val.dsize));
    }
    return obj;
}

static VALUE
fsdbm_each_key(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	rb_yield(rb_tainted_str_new(key.dptr, key.dsize));
    }
    return obj;
}

static VALUE
fsdbm_each_pair(obj)
    VALUE obj;
{
    datum key, val;
    DBM *dbm;
    struct dbmdata *dbmp;
    VALUE keystr, valstr;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	keystr = rb_tainted_str_new(key.dptr, key.dsize);
	valstr = rb_tainted_str_new(val.dptr, val.dsize);
	rb_yield(rb_assoc_new(keystr, valstr));
    }

    return obj;
}

static VALUE
fsdbm_keys(obj)
    VALUE obj;
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	rb_ary_push(ary, rb_tainted_str_new(key.dptr, key.dsize));
    }

    return ary;
}

static VALUE
fsdbm_values(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_ary_push(ary, rb_tainted_str_new(val.dptr, val.dsize));
    }

    return ary;
}

static VALUE
fsdbm_has_key(obj, keystr)
    VALUE obj, keystr;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    keystr = rb_str_to_str(keystr);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    val = sdbm_fetch(dbm, key);
    if (val.dptr) return Qtrue;
    return Qfalse;
}

static VALUE
fsdbm_has_value(obj, valstr)
    VALUE obj, valstr;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    valstr = rb_str_to_str(valstr);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	if (val.dsize == RSTRING(valstr)->len &&
	    memcmp(val.dptr, RSTRING(valstr)->ptr, val.dsize) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

static VALUE
fsdbm_to_a(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    ary = rb_ary_new();
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_ary_push(ary, rb_assoc_new(rb_tainted_str_new(key.dptr, key.dsize),
				      rb_tainted_str_new(val.dptr, val.dsize)));
    }

    return ary;
}

static VALUE
fsdbm_to_hash(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE hash;

    GetDBM(obj, dbmp);
    dbm = dbmp->di_dbm;

    hash = rb_hash_new();
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_hash_aset(hash, rb_tainted_str_new(key.dptr, key.dsize),
		           rb_tainted_str_new(val.dptr, val.dsize));
    }

    return hash;
}

static VALUE
fsdbm_reject(obj)
    VALUE obj;
{
    return rb_hash_delete_if(fsdbm_to_hash(obj));
}

void
Init_sdbm()
{
    cSDBM = rb_define_class("SDBM", rb_cObject);
    rb_include_module(cSDBM, rb_mEnumerable);

    rb_define_singleton_method(cSDBM, "open", fsdbm_s_open, -1);
    rb_define_singleton_method(cSDBM, "new", fsdbm_s_new, -1);
    rb_define_method(cSDBM, "initialize", fsdbm_initialize, -1);
    rb_define_method(cSDBM, "close", fsdbm_close, 0);
    rb_define_method(cSDBM, "[]", fsdbm_aref, 1);
    rb_define_method(cSDBM, "fetch", fsdbm_fetch_m, -1);
    rb_define_method(cSDBM, "[]=", fsdbm_store, 2);
    rb_define_method(cSDBM, "store", fsdbm_store, 2);
    rb_define_method(cSDBM, "index",  fsdbm_index, 1);
    rb_define_method(cSDBM, "indexes",  fsdbm_indexes, -1);
    rb_define_method(cSDBM, "indices",  fsdbm_indexes, -1);
    rb_define_method(cSDBM, "length", fsdbm_length, 0);
    rb_define_alias(cSDBM,  "size", "length");
    rb_define_method(cSDBM, "empty?", fsdbm_empty_p, 0);
    rb_define_method(cSDBM, "each", fsdbm_each_pair, 0);
    rb_define_method(cSDBM, "each_value", fsdbm_each_value, 0);
    rb_define_method(cSDBM, "each_key", fsdbm_each_key, 0);
    rb_define_method(cSDBM, "each_pair", fsdbm_each_pair, 0);
    rb_define_method(cSDBM, "keys", fsdbm_keys, 0);
    rb_define_method(cSDBM, "values", fsdbm_values, 0);
    rb_define_method(cSDBM, "shift", fsdbm_shift, 0);
    rb_define_method(cSDBM, "delete", fsdbm_delete, 1);
    rb_define_method(cSDBM, "delete_if", fsdbm_delete_if, 0);
    rb_define_method(cSDBM, "reject!", fsdbm_delete_if, 0);
    rb_define_method(cSDBM, "reject", fsdbm_reject, 0);
    rb_define_method(cSDBM, "clear", fsdbm_clear, 0);
    rb_define_method(cSDBM,"invert", fsdbm_invert, 0);
    rb_define_method(cSDBM,"update", fsdbm_update, 1);
    rb_define_method(cSDBM,"replace", fsdbm_replace, 1);

    rb_define_method(cSDBM, "include?", fsdbm_has_key, 1);
    rb_define_method(cSDBM, "has_key?", fsdbm_has_key, 1);
    rb_define_method(cSDBM, "member?", fsdbm_has_key, 1);
    rb_define_method(cSDBM, "has_value?", fsdbm_has_value, 1);
    rb_define_method(cSDBM, "key?", fsdbm_has_key, 1);
    rb_define_method(cSDBM, "value?", fsdbm_has_value, 1);

    rb_define_method(cSDBM, "to_a", fsdbm_to_a, 0);
    rb_define_method(cSDBM, "to_hash", fsdbm_to_hash, 0);
}
