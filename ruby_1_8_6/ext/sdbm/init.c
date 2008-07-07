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

static VALUE rb_cDBM, rb_eDBMError;

struct dbmdata {
    int  di_size;
    DBM *di_dbm;
};

static void
closed_sdbm()
{
    rb_raise(rb_eDBMError, "closed SDBM file");
}

#define GetDBM(obj, dbmp) {\
    Data_Get_Struct(obj, struct dbmdata, dbmp);\
    if (dbmp == 0) closed_sdbm();\
    if (dbmp->di_dbm == 0) closed_sdbm();\
}

#define GetDBM2(obj, data, dbm) {\
    GetDBM(obj, data);\
    (dbm) = dbmp->di_dbm;\
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
fsdbm_closed(obj)
    VALUE obj;
{
    struct dbmdata *dbmp;

    Data_Get_Struct(obj, struct dbmdata, dbmp);
    if (dbmp == 0)
	return Qtrue;
    if (dbmp->di_dbm == 0)
	return Qtrue;

    return Qfalse;
}

static VALUE fsdbm_alloc _((VALUE));
static VALUE
fsdbm_alloc(klass)
    VALUE klass;
{
    return Data_Wrap_Struct(klass, 0, free_sdbm, 0);
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
    SafeStringValue(file);

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

    StringValue(keystr);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM2(obj, dbmp, dbm);
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

    StringValue(valstr);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM2(obj, dbmp, dbm);
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
	rb_ary_push(new, fsdbm_fetch(obj, argv[i], Qnil));
    }

    return new;
}

static VALUE
fsdbm_select(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE new = rb_ary_new2(argc);
    int i;

    if (rb_block_given_p()) {
        datum key, val;
        DBM *dbm;
        struct dbmdata *dbmp;

	if (argc > 0) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)", argc);
	}
        GetDBM2(obj, dbmp, dbm);
        for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
            VALUE assoc, v;
            val = sdbm_fetch(dbm, key);
            assoc = rb_assoc_new(rb_tainted_str_new(key.dptr, key.dsize),
                                 rb_tainted_str_new(val.dptr, val.dsize));
	    v = rb_yield(assoc);
	    if (RTEST(v)) {
		rb_ary_push(new, assoc);
	    }
	    GetDBM2(obj, dbmp, dbm);
        }
    }
    else {
	rb_warn("SDBM#select(index..) is deprecated; use SDBM#values_at");

        for (i=0; i<argc; i++) {
            rb_ary_push(new, fsdbm_fetch(obj, argv[i], Qnil));
        }
    }

    return new;
}

static VALUE
fsdbm_values_at(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE new = rb_ary_new2(argc);
    int i;

    for (i=0; i<argc; i++) {
        rb_ary_push(new, fsdbm_fetch(obj, argv[i], Qnil));
    }

    return new;
}

static void
fdbm_modify(obj)
    VALUE obj;
{
    rb_secure(4);
    if (OBJ_FROZEN(obj)) rb_error_frozen("SDBM");
}

static VALUE
fsdbm_delete(obj, keystr)
    VALUE obj, keystr;
{
    datum key, value;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE valstr;

    fdbm_modify(obj);
    StringValue(keystr);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM2(obj, dbmp, dbm);
    dbmp->di_size = -1;

    value = sdbm_fetch(dbm, key);
    if (value.dptr == 0) {
	if (rb_block_given_p()) return rb_yield(keystr);
	return Qnil;
    }

    /* need to save value before sdbm_delete() */
    valstr = rb_tainted_str_new(value.dptr, value.dsize);

    if (sdbm_delete(dbm, key)) {
	dbmp->di_size = -1;
	rb_raise(rb_eDBMError, "dbm_delete failed");
    }
    else if (dbmp->di_size >= 0) {
	dbmp->di_size--;
    }
    return valstr;
}

static VALUE
fsdbm_shift(obj)
    VALUE obj;
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE keystr, valstr;

    fdbm_modify(obj);
    GetDBM2(obj, dbmp, dbm);
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

    fdbm_modify(obj);
    GetDBM2(obj, dbmp, dbm);
    n = dbmp->di_size;
    dbmp->di_size = -1;
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	keystr = rb_tainted_str_new(key.dptr, key.dsize);
	valstr = rb_tainted_str_new(val.dptr, val.dsize);
        ret = rb_protect(rb_yield, rb_assoc_new(rb_str_dup(keystr), valstr), &status);
        if (status != 0) break;
	if (RTEST(ret)) rb_ary_push(ary, keystr);
	GetDBM2(obj, dbmp, dbm);
    }

    for (i = 0; i < RARRAY(ary)->len; i++) {
	keystr = RARRAY(ary)->ptr[i];
	StringValue(keystr);
	key.dptr = RSTRING(keystr)->ptr;
	key.dsize = RSTRING(keystr)->len;
	if (sdbm_delete(dbm, key)) {
	    rb_raise(rb_eDBMError, "sdbm_delete failed");
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

    fdbm_modify(obj);
    GetDBM2(obj, dbmp, dbm);
    dbmp->di_size = -1;
    while (key = sdbm_firstkey(dbm), key.dptr) {
	if (sdbm_delete(dbm, key)) {
	    rb_raise(rb_eDBMError, "sdbm_delete failed");
	}
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

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	keystr = rb_tainted_str_new(key.dptr, key.dsize);
	valstr = rb_tainted_str_new(val.dptr, val.dsize);
	rb_hash_aset(hash, valstr, keystr);
    }
    return hash;
}

static VALUE each_pair _((VALUE));

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

    fdbm_modify(obj);
    StringValue(keystr);
    StringValue(valstr);

    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM2(obj, dbmp, dbm);
    dbmp->di_size = -1;
    if (sdbm_store(dbm, key, val, DBM_REPLACE)) {
#ifdef HAVE_DBM_CLAERERR
	sdbm_clearerr(dbm);
#endif
	if (errno == EPERM) rb_sys_fail(0);
	rb_raise(rb_eDBMError, "sdbm_store failed");
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

    GetDBM2(obj, dbmp, dbm);
    if (dbmp->di_size > 0) return INT2FIX(dbmp->di_size);

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

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_yield(rb_tainted_str_new(val.dptr, val.dsize));
	GetDBM2(obj, dbmp, dbm);
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

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	rb_yield(rb_tainted_str_new(key.dptr, key.dsize));
	GetDBM2(obj, dbmp, dbm);
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

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	keystr = rb_tainted_str_new(key.dptr, key.dsize);
	valstr = rb_tainted_str_new(val.dptr, val.dsize);
	rb_yield(rb_assoc_new(keystr, valstr));
	GetDBM2(obj, dbmp, dbm);
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

    GetDBM2(obj, dbmp, dbm);
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

    GetDBM2(obj, dbmp, dbm);
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

    StringValue(keystr);
    key.dptr = RSTRING(keystr)->ptr;
    key.dsize = RSTRING(keystr)->len;

    GetDBM2(obj, dbmp, dbm);
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

    StringValue(valstr);
    val.dptr = RSTRING(valstr)->ptr;
    val.dsize = RSTRING(valstr)->len;

    GetDBM2(obj, dbmp, dbm);
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

    GetDBM2(obj, dbmp, dbm);
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

    GetDBM2(obj, dbmp, dbm);
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
    rb_cDBM = rb_define_class("SDBM", rb_cObject);
    rb_eDBMError = rb_define_class("SDBMError", rb_eStandardError);
    rb_include_module(rb_cDBM, rb_mEnumerable);

    rb_define_alloc_func(rb_cDBM, fsdbm_alloc);
    rb_define_singleton_method(rb_cDBM, "open", fsdbm_s_open, -1);

    rb_define_method(rb_cDBM, "initialize", fsdbm_initialize, -1);
    rb_define_method(rb_cDBM, "close", fsdbm_close, 0);
    rb_define_method(rb_cDBM, "closed?", fsdbm_closed, 0);
    rb_define_method(rb_cDBM, "[]", fsdbm_aref, 1);
    rb_define_method(rb_cDBM, "fetch", fsdbm_fetch_m, -1);
    rb_define_method(rb_cDBM, "[]=", fsdbm_store, 2);
    rb_define_method(rb_cDBM, "store", fsdbm_store, 2);
    rb_define_method(rb_cDBM, "index",  fsdbm_index, 1);
    rb_define_method(rb_cDBM, "indexes",  fsdbm_indexes, -1);
    rb_define_method(rb_cDBM, "indices",  fsdbm_indexes, -1);
    rb_define_method(rb_cDBM, "select",  fsdbm_select, -1);
    rb_define_method(rb_cDBM, "values_at",  fsdbm_values_at, -1);
    rb_define_method(rb_cDBM, "length", fsdbm_length, 0);
    rb_define_method(rb_cDBM, "size", fsdbm_length, 0);
    rb_define_method(rb_cDBM, "empty?", fsdbm_empty_p, 0);
    rb_define_method(rb_cDBM, "each", fsdbm_each_pair, 0);
    rb_define_method(rb_cDBM, "each_value", fsdbm_each_value, 0);
    rb_define_method(rb_cDBM, "each_key", fsdbm_each_key, 0);
    rb_define_method(rb_cDBM, "each_pair", fsdbm_each_pair, 0);
    rb_define_method(rb_cDBM, "keys", fsdbm_keys, 0);
    rb_define_method(rb_cDBM, "values", fsdbm_values, 0);
    rb_define_method(rb_cDBM, "shift", fsdbm_shift, 0);
    rb_define_method(rb_cDBM, "delete", fsdbm_delete, 1);
    rb_define_method(rb_cDBM, "delete_if", fsdbm_delete_if, 0);
    rb_define_method(rb_cDBM, "reject!", fsdbm_delete_if, 0);
    rb_define_method(rb_cDBM, "reject", fsdbm_reject, 0);
    rb_define_method(rb_cDBM, "clear", fsdbm_clear, 0);
    rb_define_method(rb_cDBM,"invert", fsdbm_invert, 0);
    rb_define_method(rb_cDBM,"update", fsdbm_update, 1);
    rb_define_method(rb_cDBM,"replace", fsdbm_replace, 1);

    rb_define_method(rb_cDBM, "include?", fsdbm_has_key, 1);
    rb_define_method(rb_cDBM, "has_key?", fsdbm_has_key, 1);
    rb_define_method(rb_cDBM, "member?", fsdbm_has_key, 1);
    rb_define_method(rb_cDBM, "has_value?", fsdbm_has_value, 1);
    rb_define_method(rb_cDBM, "key?", fsdbm_has_key, 1);
    rb_define_method(rb_cDBM, "value?", fsdbm_has_value, 1);

    rb_define_method(rb_cDBM, "to_a", fsdbm_to_a, 0);
    rb_define_method(rb_cDBM, "to_hash", fsdbm_to_hash, 0);
}
