/************************************************

  sdbminit.c -

  $Author$
  created at: Fri May  7 08:34:24 JST 1999

  Copyright (C) 1995-2001 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

#include "sdbm.h"
#include <fcntl.h>
#include <errno.h>

/*
 * Document-class: SDBM
 *
 * SDBM provides a simple file-based key-value store, which can only store
 * String keys and values.
 *
 * Note that Ruby comes with the source code for SDBM, while the DBM and GDBM
 * standard libraries rely on external libraries and headers.
 *
 * === Examples
 *
 * Insert values:
 *
 *   require 'sdbm'
 *
 *   SDBM.open 'my_database' do |db|
 *     db['apple'] = 'fruit'
 *     db['pear'] = 'fruit'
 *     db['carrot'] = 'vegetable'
 *     db['tomato'] = 'vegetable'
 *   end
 *
 * Bulk update:
 *
 *   require 'sdbm'
 *
 *   SDBM.open 'my_database' do |db|
 *     db.update('peach' => 'fruit', 'tomato' => 'fruit')
 *   end
 *
 * Retrieve values:
 *
 *   require 'sdbm'
 *
 *   SDBM.open 'my_database' do |db|
 *     db.each do |key, value|
 *       puts "Key: #{key}, Value: #{value}"
 *     end
 *   end
 *
 * Outputs:
 *
 *   Key: apple, Value: fruit
 *   Key: pear, Value: fruit
 *   Key: carrot, Value: vegetable
 *   Key: peach, Value: fruit
 *   Key: tomato, Value: fruit
 */

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
    Data_Get_Struct((obj), struct dbmdata, (dbmp));\
    if ((dbmp) == 0) closed_sdbm();\
    if ((dbmp)->di_dbm == 0) closed_sdbm();\
}

#define GetDBM2(obj, data, dbm) {\
    GetDBM((obj), (data));\
    (dbm) = dbmp->di_dbm;\
}

static void
free_sdbm(struct dbmdata *dbmp)
{

    if (dbmp->di_dbm) sdbm_close(dbmp->di_dbm);
    ruby_xfree(dbmp);
}

/*
 * call-seq:
 *   sdbm.close -> nil
 *
 * Closes the database file.
 *
 * Raises SDBMError if the database is already closed.
 */
static VALUE
fsdbm_close(VALUE obj)
{
    struct dbmdata *dbmp;

    GetDBM(obj, dbmp);
    sdbm_close(dbmp->di_dbm);
    dbmp->di_dbm = 0;

    return Qnil;
}

/*
 * call-seq:
 *   sdbm.closed? -> true or false
 *
 * Returns +true+ if the database is closed.
 */
static VALUE
fsdbm_closed(VALUE obj)
{
    struct dbmdata *dbmp;

    Data_Get_Struct(obj, struct dbmdata, dbmp);
    if (dbmp == 0)
	return Qtrue;
    if (dbmp->di_dbm == 0)
	return Qtrue;

    return Qfalse;
}

static VALUE
fsdbm_alloc(VALUE klass)
{
    return Data_Wrap_Struct(klass, 0, free_sdbm, 0);
}
/*
 * call-seq:
 *   SDBM.new(filename, mode = 0666)
 *
 * Creates a new database handle by opening the given +filename+. SDBM actually
 * uses two physical files, with extensions '.dir' and '.pag'. These extensions
 * will automatically be appended to the +filename+.
 *
 * If the file does not exist, a new file will be created using the given
 * +mode+, unless +mode+ is explicitly set to nil. In the latter case, no
 * database will be created.
 *
 * If the file exists, it will be opened in read/write mode. If this fails, it
 * will be opened in read-only mode.
 */
static VALUE
fsdbm_initialize(int argc, VALUE *argv, VALUE obj)
{
    volatile VALUE file;
    VALUE vmode;
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
    FilePathValue(file);

    dbm = 0;
    if (mode >= 0)
	dbm = sdbm_open(RSTRING_PTR(file), O_RDWR|O_CREAT, mode);
    if (!dbm)
	dbm = sdbm_open(RSTRING_PTR(file), O_RDWR, 0);
    if (!dbm)
	dbm = sdbm_open(RSTRING_PTR(file), O_RDONLY, 0);

    if (!dbm) {
	if (mode == -1) return Qnil;
	rb_sys_fail_str(file);
    }

    dbmp = ALLOC(struct dbmdata);
    DATA_PTR(obj) = dbmp;
    dbmp->di_dbm = dbm;
    dbmp->di_size = -1;

    return obj;
}

/*
 * call-seq:
 *   SDBM.open(filename, mode = 0666)
 *   SDBM.open(filename, mode = 0666) { |sdbm| ... }
 *
 * If called without a block, this is the same as SDBM.new.
 *
 * If a block is given, the new database will be passed to the block and
 * will be safely closed after the block has executed.
 *
 * Example:
 *
 *     require 'sdbm'
 *
 *     SDBM.open('my_database') do |db|
 *       db['hello'] = 'world'
 *     end
 */
static VALUE
fsdbm_s_open(int argc, VALUE *argv, VALUE klass)
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
fsdbm_fetch(VALUE obj, VALUE keystr, VALUE ifnone)
{
    datum key, value;
    struct dbmdata *dbmp;
    DBM *dbm;

    ExportStringValue(keystr);
    key.dptr = RSTRING_PTR(keystr);
    key.dsize = RSTRING_LENINT(keystr);

    GetDBM2(obj, dbmp, dbm);
    value = sdbm_fetch(dbm, key);
    if (value.dptr == 0) {
	if (ifnone == Qnil && rb_block_given_p())
	    return rb_yield(rb_external_str_new(key.dptr, key.dsize));
	return ifnone;
    }
    return rb_external_str_new(value.dptr, value.dsize);
}

/*
 * call-seq:
 *   sdbm[key] -> value or nil
 *
 * Returns the +value+ in the database associated with the given +key+ string.
 *
 * If no value is found, returns +nil+.
 */
static VALUE
fsdbm_aref(VALUE obj, VALUE keystr)
{
    return fsdbm_fetch(obj, keystr, Qnil);
}

/*
 * call-seq:
 *   sdbm.fetch(key) -> value or nil
 *   sdbm.fetch(key) { |key| ... }
 *
 * Returns the +value+ in the database associated with the given +key+ string.
 *
 * If a block is provided, the block will be called when there is no
 * +value+ associated with the given +key+. The +key+ will be passed in as an
 * argument to the block.
 *
 * If no block is provided and no value is associated with the given +key+,
 * then an IndexError will be raised.
 */
static VALUE
fsdbm_fetch_m(int argc, VALUE *argv, VALUE obj)
{
    VALUE keystr, valstr, ifnone;

    rb_scan_args(argc, argv, "11", &keystr, &ifnone);
    valstr = fsdbm_fetch(obj, keystr, ifnone);
    if (argc == 1 && !rb_block_given_p() && NIL_P(valstr))
	rb_raise(rb_eIndexError, "key not found");

    return valstr;
}

/*
 * call-seq:
 *   sdbm.key(value) -> key
 *
 * Returns the +key+ associated with the given +value+. If more than one
 * +key+ corresponds to the given +value+, then the first key to be found
 * will be returned. If no keys are found, +nil+ will be returned.
 */
static VALUE
fsdbm_key(VALUE obj, VALUE valstr)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    ExportStringValue(valstr);
    val.dptr = RSTRING_PTR(valstr);
    val.dsize = RSTRING_LENINT(valstr);

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	if (val.dsize == RSTRING_LEN(valstr) &&
	    memcmp(val.dptr, RSTRING_PTR(valstr), val.dsize) == 0)
	    return rb_external_str_new(key.dptr, key.dsize);
    }
    return Qnil;
}

/*
 * :nodoc:
 */
static VALUE
fsdbm_index(VALUE hash, VALUE value)
{
    rb_warn("SDBM#index is deprecated; use SDBM#key");
    return fsdbm_key(hash, value);
}

/* call-seq:
 *   sdbm.select { |key, value| ... } -> Array
 *
 * Returns a new Array of key-value pairs for which the block returns +true+.
 *
 * Example:
 *
 *    require 'sdbm'
 *
 *    SDBM.open 'my_database' do |db|
 *      db['apple'] = 'fruit'
 *      db['pear'] = 'fruit'
 *      db['spinach'] = 'vegetable'
 *
 *      veggies = db.select do |key, value|
 *        value == 'vegetable'
 *      end #=> [["apple", "fruit"], ["pear", "fruit"]]
 *    end
 */
static VALUE
fsdbm_select(VALUE obj)
{
    VALUE new = rb_ary_new();
    datum key, val;
    DBM *dbm;
    struct dbmdata *dbmp;

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	VALUE assoc, v;
	val = sdbm_fetch(dbm, key);
	assoc = rb_assoc_new(rb_external_str_new(key.dptr, key.dsize),
			     rb_external_str_new(val.dptr, val.dsize));
	v = rb_yield(assoc);
	if (RTEST(v)) {
	    rb_ary_push(new, assoc);
	}
	GetDBM2(obj, dbmp, dbm);
    }

    return new;
}

/* call-seq:
 *   sdbm.values_at(key, ...) -> Array
 *
 * Returns an Array of values corresponding to the given keys.
 */
static VALUE
fsdbm_values_at(int argc, VALUE *argv, VALUE obj)
{
    VALUE new = rb_ary_new2(argc);
    int i;

    for (i=0; i<argc; i++) {
        rb_ary_push(new, fsdbm_fetch(obj, argv[i], Qnil));
    }

    return new;
}

static void
fdbm_modify(VALUE obj)
{
    if (OBJ_FROZEN(obj)) rb_error_frozen("SDBM");
}

/*
 * call-seq:
 *   sdbm.delete(key) -> value or nil
 *   sdbm.delete(key) { |key, value| ... }
 *
 * Deletes the key-value pair corresponding to the given +key+. If the
 * +key+ exists, the deleted value will be returned, otherwise +nil+.
 *
 * If a block is provided, the deleted +key+ and +value+ will be passed to
 * the block as arguments. If the +key+ does not exist in the database, the
 * value will be +nil+.
 */
static VALUE
fsdbm_delete(VALUE obj, VALUE keystr)
{
    datum key, value;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE valstr;

    fdbm_modify(obj);
    ExportStringValue(keystr);
    key.dptr = RSTRING_PTR(keystr);
    key.dsize = RSTRING_LENINT(keystr);

    GetDBM2(obj, dbmp, dbm);
    dbmp->di_size = -1;

    value = sdbm_fetch(dbm, key);
    if (value.dptr == 0) {
	if (rb_block_given_p()) return rb_yield(keystr);
	return Qnil;
    }

    /* need to save value before sdbm_delete() */
    valstr = rb_external_str_new(value.dptr, value.dsize);

    if (sdbm_delete(dbm, key)) {
	dbmp->di_size = -1;
	rb_raise(rb_eDBMError, "dbm_delete failed");
    }
    else if (dbmp->di_size >= 0) {
	dbmp->di_size--;
    }
    return valstr;
}

/*
 * call-seq:
 *   sdbm.shift -> Array or nil
 *
 * Removes a key-value pair from the database and returns them as an
 * Array. If the database is empty, returns +nil+.
 */
static VALUE
fsdbm_shift(VALUE obj)
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
    keystr = rb_external_str_new(key.dptr, key.dsize);
    valstr = rb_external_str_new(val.dptr, val.dsize);
    sdbm_delete(dbm, key);
    if (dbmp->di_size >= 0) {
	dbmp->di_size--;
    }

    return rb_assoc_new(keystr, valstr);
}

/*
 * call-seq:
 *   sdbm.delete_if { |key, value| ... } -> self
 *   sdbm.reject!   { |key, value| ... } -> self
 *
 * Iterates over the key-value pairs in the database, deleting those for
 * which the block returns +true+.
 */
static VALUE
fsdbm_delete_if(VALUE obj)
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
	keystr = rb_external_str_new(key.dptr, key.dsize);
	valstr = rb_external_str_new(val.dptr, val.dsize);
        ret = rb_protect(rb_yield, rb_assoc_new(rb_str_dup(keystr), valstr), &status);
        if (status != 0) break;
	if (RTEST(ret)) rb_ary_push(ary, keystr);
	GetDBM2(obj, dbmp, dbm);
    }

    for (i = 0; i < RARRAY_LEN(ary); i++) {
	keystr = RARRAY_PTR(ary)[i];
	ExportStringValue(keystr);
	key.dptr = RSTRING_PTR(keystr);
	key.dsize = RSTRING_LENINT(keystr);
	if (sdbm_delete(dbm, key)) {
	    rb_raise(rb_eDBMError, "sdbm_delete failed");
	}
    }
    if (status) rb_jump_tag(status);
    if (n > 0) dbmp->di_size = n - RARRAY_LENINT(ary);

    return obj;
}

/*
 * call-seq:
 *   sdbm.clear -> self
 *
 * Deletes all data from the database.
 */
static VALUE
fsdbm_clear(VALUE obj)
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

/*
 * call-seq:
 *   sdbm.invert -> Hash
 *
 * Returns a Hash in which the key-value pairs have been inverted.
 *
 * Example:
 *
 *   require 'sdbm'
 *
 *   SDBM.open 'my_database' do |db|
 *     db.update('apple' => 'fruit', 'spinach' => 'vegetable')
 *
 *     db.invert  #=> {"fruit" => "apple", "vegetable" => "spinach"}
 *   end
 */
static VALUE
fsdbm_invert(VALUE obj)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE keystr, valstr;
    VALUE hash = rb_hash_new();

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	keystr = rb_external_str_new(key.dptr, key.dsize);
	valstr = rb_external_str_new(val.dptr, val.dsize);
	rb_hash_aset(hash, valstr, keystr);
    }
    return hash;
}

/*
 * call-seq:
 *   sdbm[key] = value      -> value
 *   sdbm.store(key, value) -> value
 *
 * Stores a new +value+ in the database with the given +key+ as an index.
 *
 * If the +key+ already exists, this will update the +value+ associated with
 * the +key+.
 *
 * Returns the given +value+.
 */
static VALUE
fsdbm_store(VALUE obj, VALUE keystr, VALUE valstr)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    if (valstr == Qnil) {
	fsdbm_delete(obj, keystr);
	return Qnil;
    }

    fdbm_modify(obj);
    ExportStringValue(keystr);
    ExportStringValue(valstr);

    key.dptr = RSTRING_PTR(keystr);
    key.dsize = RSTRING_LENINT(keystr);

    val.dptr = RSTRING_PTR(valstr);
    val.dsize = RSTRING_LENINT(valstr);

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
update_i(RB_BLOCK_CALL_FUNC_ARGLIST(pair, dbm))
{
    Check_Type(pair, T_ARRAY);
    if (RARRAY_LEN(pair) < 2) {
	rb_raise(rb_eArgError, "pair must be [key, value]");
    }
    fsdbm_store(dbm, RARRAY_PTR(pair)[0], RARRAY_PTR(pair)[1]);
    return Qnil;
}

/*
 * call-seq:
 *   sdbm.update(pairs) -> self
 *
 * Insert or update key-value pairs.
 *
 * This method will work with any object which implements an each_pair
 * method, such as a Hash.
 */
static VALUE
fsdbm_update(VALUE obj, VALUE other)
{
    rb_block_call(other, rb_intern("each_pair"), 0, 0, update_i, obj);
    return obj;
}

/*
 * call-seq:
 *   sdbm.replace(pairs) -> self
 *
 * Empties the database, then inserts the given key-value pairs.
 *
 * This method will work with any object which implements an each_pair
 * method, such as a Hash.
 */
static VALUE
fsdbm_replace(VALUE obj, VALUE other)
{
    fsdbm_clear(obj);
    rb_block_call(other, rb_intern("each_pair"), 0, 0, update_i, obj);
    return obj;
}

/*
 * call-seq:
 *   sdbm.length -> integer
 *   sdbm.size -> integer
 *
 * Returns the number of keys in the database.
 */
static VALUE
fsdbm_length(VALUE obj)
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

/*
 * call-seq:
 *   sdbm.empty? -> true or false
 *
 * Returns +true+ if the database is empty.
 */
static VALUE
fsdbm_empty_p(VALUE obj)
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;

    GetDBM(obj, dbmp);
    if (dbmp->di_size < 0) {
	dbm = dbmp->di_dbm;

	for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	    return Qfalse;
	}
    }
    else {
	if (dbmp->di_size)
	    return Qfalse;
    }
    return Qtrue;
}

/*
 * call-seq:
 *   sdbm.each_value
 *   sdbm.each_value { |value| ... }
 *
 * Iterates over each +value+ in the database.
 *
 * If no block is given, returns an Enumerator.
 */
static VALUE
fsdbm_each_value(VALUE obj)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    RETURN_ENUMERATOR(obj, 0, 0);

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_yield(rb_external_str_new(val.dptr, val.dsize));
	GetDBM2(obj, dbmp, dbm);
    }
    return obj;
}

/*
 * call-seq:
 *   sdbm.each_key
 *   sdbm.each_key { |key| ... }
 *
 * Iterates over each +key+ in the database.
 *
 * If no block is given, returns an Enumerator.
 */
static VALUE
fsdbm_each_key(VALUE obj)
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;

    RETURN_ENUMERATOR(obj, 0, 0);

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	rb_yield(rb_external_str_new(key.dptr, key.dsize));
	GetDBM2(obj, dbmp, dbm);
    }
    return obj;
}

/*
 * call-seq:
 *   sdbm.each
 *   sdbm.each { |key, value| ... }
 *   sdbm.each_pair
 *   sdbm.each_pair { |key, value| ... }
 *
 * Iterates over each key-value pair in the database.
 *
 * If no block is given, returns an Enumerator.
 */
static VALUE
fsdbm_each_pair(VALUE obj)
{
    datum key, val;
    DBM *dbm;
    struct dbmdata *dbmp;
    VALUE keystr, valstr;

    RETURN_ENUMERATOR(obj, 0, 0);

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	keystr = rb_external_str_new(key.dptr, key.dsize);
	valstr = rb_external_str_new(val.dptr, val.dsize);
	rb_yield(rb_assoc_new(keystr, valstr));
	GetDBM2(obj, dbmp, dbm);
    }

    return obj;
}

/*
 * call-seq:
 *   sdbm.keys -> Array
 *
 * Returns a new Array containing the keys in the database.
 */
static VALUE
fsdbm_keys(VALUE obj)
{
    datum key;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM2(obj, dbmp, dbm);
    ary = rb_ary_new();
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	rb_ary_push(ary, rb_external_str_new(key.dptr, key.dsize));
    }

    return ary;
}

/*
 * call-seq:
 *   sdbm.values -> Array
 *
 * Returns a new Array containing the values in the database.
 */
static VALUE
fsdbm_values(VALUE obj)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM2(obj, dbmp, dbm);
    ary = rb_ary_new();
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_ary_push(ary, rb_external_str_new(val.dptr, val.dsize));
    }

    return ary;
}

/*
 * call-seq:
 *   sdbm.include?(key) -> true or false
 *   sdbm.key?(key) -> true or false
 *   sdbm.member?(key) -> true or false
 *   sdbm.has_key?(key) -> true or false
 *
 * Returns +true+ if the database contains the given +key+.
 */
static VALUE
fsdbm_has_key(VALUE obj, VALUE keystr)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    ExportStringValue(keystr);
    key.dptr = RSTRING_PTR(keystr);
    key.dsize = RSTRING_LENINT(keystr);

    GetDBM2(obj, dbmp, dbm);
    val = sdbm_fetch(dbm, key);
    if (val.dptr) return Qtrue;
    return Qfalse;
}

/*
 * call-seq:
 *   sdbm.value?(key) -> true or false
 *   sdbm.has_value?(key) -> true or false
 *
 * Returns +true+ if the database contains the given +value+.
 */
static VALUE
fsdbm_has_value(VALUE obj, VALUE valstr)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;

    ExportStringValue(valstr);
    val.dptr = RSTRING_PTR(valstr);
    val.dsize = RSTRING_LENINT(valstr);

    GetDBM2(obj, dbmp, dbm);
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	if (val.dsize == RSTRING_LENINT(valstr) &&
	    memcmp(val.dptr, RSTRING_PTR(valstr), val.dsize) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

/*
 * call-seq:
 *   sdbm.to_a -> Array
 *
 * Returns a new Array containing each key-value pair in the database.
 *
 * Example:
 *
 *   require 'sdbm'
 *
 *   SDBM.open 'my_database' do |db|
 *     db.update('apple' => 'fruit', 'spinach' => 'vegetable')
 *
 *     db.to_a  #=> [["apple", "fruit"], ["spinach", "vegetable"]]
 *   end
 */
static VALUE
fsdbm_to_a(VALUE obj)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE ary;

    GetDBM2(obj, dbmp, dbm);
    ary = rb_ary_new();
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_ary_push(ary, rb_assoc_new(rb_external_str_new(key.dptr, key.dsize),
				      rb_external_str_new(val.dptr, val.dsize)));
    }

    return ary;
}

/*
 * call-seq:
 *   sdbm.to_hash -> Hash
 *
 * Returns a new Hash containing each key-value pair in the database.
 */
static VALUE
fsdbm_to_hash(VALUE obj)
{
    datum key, val;
    struct dbmdata *dbmp;
    DBM *dbm;
    VALUE hash;

    GetDBM2(obj, dbmp, dbm);
    hash = rb_hash_new();
    for (key = sdbm_firstkey(dbm); key.dptr; key = sdbm_nextkey(dbm)) {
	val = sdbm_fetch(dbm, key);
	rb_hash_aset(hash, rb_external_str_new(key.dptr, key.dsize),
		           rb_external_str_new(val.dptr, val.dsize));
    }

    return hash;
}

/*
 * call-seq:
 *   sdbm.reject { |key, value| ... } -> Hash
 *
 * Creates a new Hash using the key-value pairs from the database, then
 * calls Hash#reject with the given block, which returns a Hash with
 * only the key-value pairs for which the block returns +false+.
 */
static VALUE
fsdbm_reject(VALUE obj)
{
    return rb_hash_delete_if(fsdbm_to_hash(obj));
}

void
Init_sdbm()
{
    rb_cDBM = rb_define_class("SDBM", rb_cObject);
    rb_eDBMError = rb_define_class("SDBMError", rb_eStandardError);
    /* Document-class: SDBMError
     * Exception class used to return errors from the sdbm library.
     */
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
    rb_define_method(rb_cDBM, "key",  fsdbm_key, 1);
    rb_define_method(rb_cDBM, "select",  fsdbm_select, 0);
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

    rb_define_method(rb_cDBM, "has_key?", fsdbm_has_key, 1);
    rb_define_method(rb_cDBM, "include?", fsdbm_has_key, 1);
    rb_define_method(rb_cDBM, "key?", fsdbm_has_key, 1);
    rb_define_method(rb_cDBM, "member?", fsdbm_has_key, 1);
    rb_define_method(rb_cDBM, "has_value?", fsdbm_has_value, 1);
    rb_define_method(rb_cDBM, "value?", fsdbm_has_value, 1);

    rb_define_method(rb_cDBM, "to_a", fsdbm_to_a, 0);
    rb_define_method(rb_cDBM, "to_hash", fsdbm_to_hash, 0);
}
