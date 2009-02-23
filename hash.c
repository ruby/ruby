/**********************************************************************

  hash.c -

  $Author$
  $Date$
  created at: Mon Nov 22 18:51:18 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "st.h"
#include "util.h"
#include "rubysig.h"

#ifdef __APPLE__
#include <crt_externs.h>
#endif

#define HASH_DELETED  FL_USER1
#define HASH_PROC_DEFAULT FL_USER2

static void
rb_hash_modify(hash)
    VALUE hash;
{
    if (!RHASH(hash)->tbl) rb_raise(rb_eTypeError, "uninitialized Hash");
    if (OBJ_FROZEN(hash)) rb_error_frozen("hash");
    if (!OBJ_TAINTED(hash) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't modify hash");
}

VALUE
rb_hash_freeze(hash)
    VALUE hash;
{
    return rb_obj_freeze(hash);
}

VALUE rb_cHash;

static VALUE envtbl;
static ID id_hash, id_call, id_default;

static VALUE
eql(args)
    VALUE *args;
{
    return (VALUE)rb_eql(args[0], args[1]);
}

static int
rb_any_cmp(a, b)
    VALUE a, b;
{
    VALUE args[2];

    if (a == b) return 0;
    if (FIXNUM_P(a) && FIXNUM_P(b)) {
	return a != b;
    }
    if (TYPE(a) == T_STRING && RBASIC(a)->klass == rb_cString &&
	TYPE(b) == T_STRING && RBASIC(b)->klass == rb_cString) {
	return rb_str_cmp(a, b);
    }
    if (a == Qundef || b == Qundef) return -1;
    if (SYMBOL_P(a) && SYMBOL_P(b)) {
	return a != b;
    }

    args[0] = a;
    args[1] = b;
    return !rb_with_disable_interrupt(eql, (VALUE)args);
}

VALUE
rb_hash(obj)
    VALUE obj;
{
    return rb_funcall(obj, id_hash, 0);
}

static int
rb_any_hash(a)
    VALUE a;
{
    VALUE hval;
    int hnum;

    switch (TYPE(a)) {
      case T_FIXNUM:
      case T_SYMBOL:
	hnum = (int)a;
	break;

      case T_STRING:
	hnum = rb_str_hash(a);
	break;

      default:
	hval = rb_funcall(a, id_hash, 0);
	if (!FIXNUM_P(hval)) {
	    hval = rb_funcall(hval, '%', 1, INT2FIX(536870923));
	}
	hnum = (int)FIX2LONG(hval);
    }
    hnum <<= 1;
    return RSHIFT(hnum, 1);
}

static struct st_hash_type objhash = {
    rb_any_cmp,
    rb_any_hash,
};

typedef int st_foreach_func(st_data_t, st_data_t, st_data_t);

struct foreach_safe_arg {
    st_table *tbl;
    st_foreach_func *func;
    st_data_t arg;
};

static int
foreach_safe_i(key, value, arg)
    st_data_t key, value;
    struct foreach_safe_arg *arg;
{
    int status;

    if (key == Qundef) return ST_CONTINUE;
    status = (*arg->func)(key, value, arg->arg);
    if (status == ST_CONTINUE) {
	return ST_CHECK;
    }
    return status;
}

void
st_foreach_safe(table, func, a)
    st_table *table;
    int (*func)();
    st_data_t a;
{
    struct foreach_safe_arg arg;

    arg.tbl = table;
    arg.func = (st_foreach_func *)func;
    arg.arg = a;
    if (st_foreach(table, foreach_safe_i, (st_data_t)&arg)) {
	rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

typedef int rb_foreach_func(VALUE, VALUE, VALUE);

struct hash_foreach_arg {
    VALUE hash;
    rb_foreach_func *func;
    VALUE arg;
};

static int
hash_foreach_iter(key, value, arg)
    VALUE key, value;
    struct hash_foreach_arg *arg;
{
    int status;
    st_table *tbl;

    tbl = RHASH(arg->hash)->tbl;
    if (key == Qundef) return ST_CONTINUE;
    status = (*arg->func)(key, value, arg->arg);
    if (RHASH(arg->hash)->tbl != tbl) {
	rb_raise(rb_eRuntimeError, "rehash occurred during iteration");
    }
    switch (status) {
      case ST_DELETE:
 	st_delete_safe(tbl, (st_data_t*)&key, 0, Qundef);
	FL_SET(arg->hash, HASH_DELETED);
      case ST_CONTINUE:
 	break;
      case ST_STOP:
 	return ST_STOP;
    }
    return ST_CHECK;
}

static VALUE
hash_foreach_ensure(hash)
    VALUE hash;
{
    RHASH(hash)->iter_lev--;

    if (RHASH(hash)->iter_lev == 0) {
	if (FL_TEST(hash, HASH_DELETED)) {
	    st_cleanup_safe(RHASH(hash)->tbl, Qundef);
	    FL_UNSET(hash, HASH_DELETED);
	}
    }
    return 0;
}

static VALUE
hash_foreach_call(arg)
    struct hash_foreach_arg *arg;
{
    if (st_foreach(RHASH(arg->hash)->tbl, hash_foreach_iter, (st_data_t)arg)) {
 	rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
    return Qnil;
}

void
rb_hash_foreach(hash, func, farg)
    VALUE hash;
    int (*func)();
    VALUE farg;
{
    struct hash_foreach_arg arg;

    RHASH(hash)->iter_lev++;
    arg.hash = hash;
    arg.func = (rb_foreach_func *)func;
    arg.arg  = farg;
    rb_ensure(hash_foreach_call, (VALUE)&arg, hash_foreach_ensure, hash);
}

static VALUE hash_alloc0 _((VALUE));
static VALUE hash_alloc _((VALUE));
static VALUE
hash_alloc0(klass)
    VALUE klass;
{
    NEWOBJ(hash, struct RHash);
    OBJSETUP(hash, klass, T_HASH);

    hash->ifnone = Qnil;

    return (VALUE)hash;
}

static VALUE
hash_alloc(klass)
    VALUE klass;
{
    VALUE hash = hash_alloc0(klass);

    RHASH(hash)->tbl = st_init_table(&objhash);

    return hash;
}

VALUE
rb_hash_new()
{
    return hash_alloc(rb_cHash);
}

/*
 *  call-seq:
 *     Hash.new                          => hash
 *     Hash.new(obj)                     => aHash
 *     Hash.new {|hash, key| block }     => aHash
 *
 *  Returns a new, empty hash. If this hash is subsequently accessed by
 *  a key that doesn't correspond to a hash entry, the value returned
 *  depends on the style of <code>new</code> used to create the hash. In
 *  the first form, the access returns <code>nil</code>. If
 *  <i>obj</i> is specified, this single object will be used for
 *  all <em>default values</em>. If a block is specified, it will be
 *  called with the hash object and the key, and should return the
 *  default value. It is the block's responsibility to store the value
 *  in the hash if required.
 *
 *     h = Hash.new("Go Fish")
 *     h["a"] = 100
 *     h["b"] = 200
 *     h["a"]           #=> 100
 *     h["c"]           #=> "Go Fish"
 *     # The following alters the single default object
 *     h["c"].upcase!   #=> "GO FISH"
 *     h["d"]           #=> "GO FISH"
 *     h.keys           #=> ["a", "b"]
 *
 *     # While this creates a new default object each time
 *     h = Hash.new { |hash, key| hash[key] = "Go Fish: #{key}" }
 *     h["c"]           #=> "Go Fish: c"
 *     h["c"].upcase!   #=> "GO FISH: C"
 *     h["d"]           #=> "Go Fish: d"
 *     h.keys           #=> ["c", "d"]
 *
 */

static VALUE
rb_hash_initialize(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE ifnone;

    rb_hash_modify(hash);
    if (rb_block_given_p()) {
	if (argc > 0) {
	    rb_raise(rb_eArgError, "wrong number of arguments");
	}
	RHASH(hash)->ifnone = rb_block_proc();
	FL_SET(hash, HASH_PROC_DEFAULT);
    }
    else {
	rb_scan_args(argc, argv, "01", &ifnone);
	RHASH(hash)->ifnone = ifnone;
    }

    return hash;
}

/*
 *  call-seq:
 *     Hash[ [key =>|, value]* ]   => hash
 *
 *  Creates a new hash populated with the given objects. Equivalent to
 *  the literal <code>{ <i>key</i>, <i>value</i>, ... }</code>. Keys and
 *  values occur in pairs, so there must be an even number of arguments.
 *
 *     Hash["a", 100, "b", 200]       #=> {"a"=>100, "b"=>200}
 *     Hash["a" => 100, "b" => 200]   #=> {"a"=>100, "b"=>200}
 *     { "a" => 100, "b" => 200 }     #=> {"a"=>100, "b"=>200}
 */

static VALUE
rb_hash_s_create(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE hash, tmp;
    int i;

    if (argc == 1) {
	tmp = rb_check_convert_type(argv[0], T_HASH, "Hash", "to_hash");
	if (!NIL_P(tmp)) {
	    hash = hash_alloc0(klass);
	    RHASH(hash)->tbl = st_copy(RHASH(tmp)->tbl);
	    return hash;
	}

	tmp = rb_check_array_type(argv[0]);
	if (!NIL_P(tmp)) {
	    long i;

	    hash = hash_alloc(klass);
	    for (i = 0; i < RARRAY_LEN(tmp); ++i) {
		VALUE v = rb_check_array_type(RARRAY_PTR(tmp)[i]);
		VALUE key, val = Qnil;

		if (NIL_P(v)) continue;
		switch (RARRAY_LEN(v)) {
		  case 2:
		    val = RARRAY_PTR(v)[1];
		  case 1:
		    key = RARRAY_PTR(v)[0];
		    rb_hash_aset(hash, key, val);
		}
	    }
	    return hash;
	}
    }
    if (argc % 2 != 0) {
	rb_raise(rb_eArgError, "odd number of arguments for Hash");
    }

    hash = hash_alloc(klass);
    for (i=0; i<argc; i+=2) {
        rb_hash_aset(hash, argv[i], argv[i + 1]);
    }

    return hash;
}

static VALUE
to_hash(hash)
    VALUE hash;
{
    return rb_convert_type(hash, T_HASH, "Hash", "to_hash");
}

static int
rb_hash_rehash_i(key, value, tbl)
    VALUE key, value;
    st_table *tbl;
{
    if (key != Qundef) st_insert(tbl, key, value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.rehash -> hsh
 *
 *  Rebuilds the hash based on the current hash values for each key. If
 *  values of key objects have changed since they were inserted, this
 *  method will reindex <i>hsh</i>. If <code>Hash#rehash</code> is
 *  called while an iterator is traversing the hash, an
 *  <code>IndexError</code> will be raised in the iterator.
 *
 *     a = [ "a", "b" ]
 *     c = [ "c", "d" ]
 *     h = { a => 100, c => 300 }
 *     h[a]       #=> 100
 *     a[0] = "z"
 *     h[a]       #=> nil
 *     h.rehash   #=> {["z", "b"]=>100, ["c", "d"]=>300}
 *     h[a]       #=> 100
 */

static VALUE
rb_hash_rehash(hash)
    VALUE hash;
{
    st_table *tbl;

    rb_hash_modify(hash);
    tbl = st_init_table_with_size(&objhash, RHASH(hash)->tbl->num_entries);
    rb_hash_foreach(hash, rb_hash_rehash_i, (st_data_t)tbl);
    st_free_table(RHASH(hash)->tbl);
    RHASH(hash)->tbl = tbl;

    return hash;
}

/*
 *  call-seq:
 *     hsh[key]    =>  value
 *
 *  Element Reference---Retrieves the <i>value</i> object corresponding
 *  to the <i>key</i> object. If not found, returns the a default value (see
 *  <code>Hash::new</code> for details).
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h["a"]   #=> 100
 *     h["c"]   #=> nil
 *
 */

VALUE
rb_hash_aref(hash, key)
    VALUE hash, key;
{
    VALUE val;

    if (!st_lookup(RHASH(hash)->tbl, key, &val)) {
	return rb_funcall(hash, id_default, 1, key);
    }
    return val;
}

VALUE
rb_hash_lookup(hash, key)
    VALUE hash, key;
{
    VALUE val;

    if (!st_lookup(RHASH(hash)->tbl, key, &val)) {
	return Qnil; /* without Hash#default */
    }
    return val;
}

/*
 *  call-seq:
 *     hsh.fetch(key [, default] )       => obj
 *     hsh.fetch(key) {| key | block }   => obj
 *
 *  Returns a value from the hash for the given key. If the key can't be
 *  found, there are several options: With no other arguments, it will
 *  raise an <code>IndexError</code> exception; if <i>default</i> is
 *  given, then that will be returned; if the optional code block is
 *  specified, then that will be run and its result returned.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.fetch("a")                            #=> 100
 *     h.fetch("z", "go fish")                 #=> "go fish"
 *     h.fetch("z") { |el| "go fish, #{el}"}   #=> "go fish, z"
 *
 *  The following example shows that an exception is raised if the key
 *  is not found and a default value is not supplied.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.fetch("z")
 *
 *  <em>produces:</em>
 *
 *     prog.rb:2:in `fetch': key not found (IndexError)
 *      from prog.rb:2
 *
 */

static VALUE
rb_hash_fetch(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE key, if_none;
    VALUE val;
    long block_given;

    rb_scan_args(argc, argv, "11", &key, &if_none);

    block_given = rb_block_given_p();
    if (block_given && argc == 2) {
	rb_warn("block supersedes default value argument");
    }
    if (!st_lookup(RHASH(hash)->tbl, key, &val)) {
	if (block_given) return rb_yield(key);
	if (argc == 1) {
	    rb_raise(rb_eIndexError, "key not found");
	}
	return if_none;
    }
    return val;
}

/*
 *  call-seq:
 *     hsh.default(key=nil)   => obj
 *
 *  Returns the default value, the value that would be returned by
 *  <i>hsh</i>[<i>key</i>] if <i>key</i> did not exist in <i>hsh</i>.
 *  See also <code>Hash::new</code> and <code>Hash#default=</code>.
 *
 *     h = Hash.new                            #=> {}
 *     h.default                               #=> nil
 *     h.default(2)                            #=> nil
 *
 *     h = Hash.new("cat")                     #=> {}
 *     h.default                               #=> "cat"
 *     h.default(2)                            #=> "cat"
 *
 *     h = Hash.new {|h,k| h[k] = k.to_i*10}   #=> {}
 *     h.default                               #=> nil
 *     h.default(2)                            #=> 20
 */

static VALUE
rb_hash_default(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE key;

    rb_scan_args(argc, argv, "01", &key);
    if (FL_TEST(hash, HASH_PROC_DEFAULT)) {
	if (argc == 0) return Qnil;
	return rb_funcall(RHASH(hash)->ifnone, id_call, 2, hash, key);
    }
    return RHASH(hash)->ifnone;
}

/*
 *  call-seq:
 *     hsh.default = obj     => hsh
 *
 *  Sets the default value, the value returned for a key that does not
 *  exist in the hash. It is not possible to set the a default to a
 *  <code>Proc</code> that will be executed on each key lookup.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.default = "Go fish"
 *     h["a"]     #=> 100
 *     h["z"]     #=> "Go fish"
 *     # This doesn't do what you might hope...
 *     h.default = proc do |hash, key|
 *       hash[key] = key + key
 *     end
 *     h[2]       #=> #<Proc:0x401b3948@-:6>
 *     h["cat"]   #=> #<Proc:0x401b3948@-:6>
 */

static VALUE
rb_hash_set_default(hash, ifnone)
    VALUE hash, ifnone;
{
    rb_hash_modify(hash);
    RHASH(hash)->ifnone = ifnone;
    FL_UNSET(hash, HASH_PROC_DEFAULT);
    return ifnone;
}

/*
 *  call-seq:
 *     hsh.default_proc -> anObject
 *
 *  If <code>Hash::new</code> was invoked with a block, return that
 *  block, otherwise return <code>nil</code>.
 *
 *     h = Hash.new {|h,k| h[k] = k*k }   #=> {}
 *     p = h.default_proc                 #=> #<Proc:0x401b3d08@-:1>
 *     a = []                             #=> []
 *     p.call(a, 2)
 *     a                                  #=> [nil, nil, 4]
 */


static VALUE
rb_hash_default_proc(hash)
    VALUE hash;
{
    if (FL_TEST(hash, HASH_PROC_DEFAULT)) {
	return RHASH(hash)->ifnone;
    }
    return Qnil;
}

static int
index_i(key, value, args)
    VALUE key, value;
    VALUE *args;
{
    if (rb_equal(value, args[0])) {
	args[1] = key;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

static VALUE
rb_hash_delete_key(hash, key)
    VALUE hash, key;
{
    st_data_t ktmp = (st_data_t)key, val;

    if (RHASH(hash)->iter_lev > 0) {
	if (st_delete_safe(RHASH(hash)->tbl, &ktmp, &val, Qundef)) {
	    FL_SET(hash, HASH_DELETED);
	    return (VALUE)val;
	}
    }
    else if (st_delete(RHASH(hash)->tbl, &ktmp, &val))
	return (VALUE)val;
    return Qundef;
}

/*
 *  call-seq:
 *     hsh.index(value)    => key
 *
 *  Returns the key for a given value. If not found, returns <code>nil</code>.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.index(200)   #=> "b"
 *     h.index(999)   #=> nil
 *
 */

static VALUE
rb_hash_index(hash, value)
    VALUE hash, value;
{
    VALUE args[2];

    args[0] = value;
    args[1] = Qnil;

    rb_hash_foreach(hash, index_i, (st_data_t)args);

    return args[1];
}

/*
 *  call-seq:
 *     hsh.indexes(key, ...)    => array
 *     hsh.indices(key, ...)    => array
 *
 *  Deprecated in favor of <code>Hash#select</code>.
 *
 */

static VALUE
rb_hash_indexes(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE indexes;
    int i;

    rb_warn("Hash#%s is deprecated; use Hash#values_at",
	    rb_id2name(rb_frame_last_func()));
    indexes = rb_ary_new2(argc);
    for (i=0; i<argc; i++) {
	RARRAY(indexes)->ptr[i] = rb_hash_aref(hash, argv[i]);
	RARRAY(indexes)->len++;
    }
    return indexes;
}

/*
 *  call-seq:
 *     hsh.delete(key)                   => value
 *     hsh.delete(key) {| key | block }  => value
 *
 *  Deletes and returns a key-value pair from <i>hsh</i> whose key is
 *  equal to <i>key</i>. If the key is not found, returns <code>nil</code>.
 *  If the optional code block is given and the key is not found,
 *  pass in the key and return the result of <i>block</i>.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.delete("a")                              #=> 100
 *     h.delete("z")                              #=> nil
 *     h.delete("z") { |el| "#{el} not found" }   #=> "z not found"
 *
 */

VALUE
rb_hash_delete(hash, key)
    VALUE hash, key;
{
    VALUE val;

    rb_hash_modify(hash);
    val = rb_hash_delete_key(hash, key);
    if (val != Qundef) return val;
    if (rb_block_given_p()) {
	return rb_yield(key);
    }
    return Qnil;
}

struct shift_var {
    VALUE key;
    VALUE val;
};

static int
shift_i(key, value, var)
    VALUE key, value;
    struct shift_var *var;
{
    if (key == Qundef) return ST_CONTINUE;
    if (var->key != Qundef) return ST_STOP;
    var->key = key;
    var->val = value;
    return ST_DELETE;
}

static int
shift_i_safe(key, value, var)
    VALUE key, value;
    struct shift_var *var;
{
    if (key == Qundef) return ST_CONTINUE;
    var->key = key;
    var->val = value;
    return ST_STOP;
}

/*
 *  call-seq:
 *     hsh.shift -> anArray or obj
 *
 *  Removes a key-value pair from <i>hsh</i> and returns it as the
 *  two-item array <code>[</code> <i>key, value</i> <code>]</code>, or
 *  the hash's default value if the hash is empty.
 *
 *     h = { 1 => "a", 2 => "b", 3 => "c" }
 *     h.shift   #=> [1, "a"]
 *     h         #=> {2=>"b", 3=>"c"}
 */

static VALUE
rb_hash_shift(hash)
    VALUE hash;
{
    struct shift_var var;

    rb_hash_modify(hash);
    var.key = Qundef;
    if (RHASH(hash)->iter_lev > 0) {
	rb_hash_foreach(hash, shift_i_safe, (st_data_t)&var);
	if (var.key != Qundef) {
	    st_data_t key = var.key;
	    if (st_delete_safe(RHASH(hash)->tbl, &key, 0, Qundef)) {
		FL_SET(hash, HASH_DELETED);
	    }
	}
    }
    else {
	rb_hash_foreach(hash, shift_i, (st_data_t)&var);
    }

    if (var.key != Qundef) {
	return rb_assoc_new(var.key, var.val);
    }
    else if (FL_TEST(hash, HASH_PROC_DEFAULT)) {
	return rb_funcall(RHASH(hash)->ifnone, id_call, 2, hash, Qnil);
    }
    else {
	return RHASH(hash)->ifnone;
    }
}

static int
delete_if_i(key, value, hash)
    VALUE key, value, hash;
{
    if (key == Qundef) return ST_CONTINUE;
    if (RTEST(rb_yield_values(2, key, value))) {
	rb_hash_delete_key(hash, key);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.delete_if {| key, value | block }  -> hsh
 *
 *  Deletes every key-value pair from <i>hsh</i> for which <i>block</i>
 *  evaluates to <code>true</code>.
 *
 *     h = { "a" => 100, "b" => 200, "c" => 300 }
 *     h.delete_if {|key, value| key >= "b" }   #=> {"a"=>100}
 *
 */

VALUE
rb_hash_delete_if(hash)
    VALUE hash;
{
    RETURN_ENUMERATOR(hash, 0, 0);
    rb_hash_modify(hash);
    rb_hash_foreach(hash, delete_if_i, hash);
    return hash;
}

/*
 *  call-seq:
 *     hsh.reject! {| key, value | block }  -> hsh or nil
 *
 *  Equivalent to <code>Hash#delete_if</code>, but returns
 *  <code>nil</code> if no changes were made.
 */

VALUE
rb_hash_reject_bang(hash)
    VALUE hash;
{
    int n;

    RETURN_ENUMERATOR(hash, 0, 0);
    n = RHASH(hash)->tbl->num_entries;
    rb_hash_delete_if(hash);
    if (n == RHASH(hash)->tbl->num_entries) return Qnil;
    return hash;
}

/*
 *  call-seq:
 *     hsh.reject {| key, value | block }  -> a_hash
 *
 *  Same as <code>Hash#delete_if</code>, but works on (and returns) a
 *  copy of the <i>hsh</i>. Equivalent to
 *  <code><i>hsh</i>.dup.delete_if</code>.
 *
 */

static VALUE
rb_hash_reject(hash)
    VALUE hash;
{
    return rb_hash_delete_if(rb_obj_dup(hash));
}

static int
select_i(key, value, result)
    VALUE key, value, result;
{
    if (key == Qundef) return ST_CONTINUE;
    if (RTEST(rb_yield_values(2, key, value)))
	rb_ary_push(result, rb_assoc_new(key, value));
    return ST_CONTINUE;
}

/*
 * call-seq:
 *   hsh.values_at(key, ...)   => array
 *
 * Return an array containing the values associated with the given keys.
 * Also see <code>Hash.select</code>.
 *
 *   h = { "cat" => "feline", "dog" => "canine", "cow" => "bovine" }
 *   h.values_at("cow", "cat")  #=> ["bovine", "feline"]
 */

VALUE
rb_hash_values_at(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE result = rb_ary_new();
    long i;

    for (i=0; i<argc; i++) {
	rb_ary_push(result, rb_hash_aref(hash, argv[i]));
    }
    return result;
}

/*
 *  call-seq:
 *     hsh.select {|key, value| block}   => array
 *
 *  Returns a new array consisting of <code>[key,value]</code>
 *  pairs for which the block returns true.
 *  Also see <code>Hash.values_at</code>.
 *
 *     h = { "a" => 100, "b" => 200, "c" => 300 }
 *     h.select {|k,v| k > "a"}  #=> [["b", 200], ["c", 300]]
 *     h.select {|k,v| v < 200}  #=> [["a", 100]]
 */

VALUE
rb_hash_select(hash)
    VALUE hash;
{
    VALUE result;

    RETURN_ENUMERATOR(hash, 0, 0);
    result = rb_ary_new();
    rb_hash_foreach(hash, select_i, result);
    return result;
}

static int
clear_i(key, value, dummy)
    VALUE key, value, dummy;
{
    return ST_DELETE;
}

/*
 *  call-seq:
 *     hsh.clear -> hsh
 *
 *  Removes all key-value pairs from <i>hsh</i>.
 *
 *     h = { "a" => 100, "b" => 200 }   #=> {"a"=>100, "b"=>200}
 *     h.clear                          #=> {}
 *
 */

static VALUE
rb_hash_clear(hash)
    VALUE hash;
{
    rb_hash_modify(hash);
    if (RHASH(hash)->tbl->num_entries > 0) {
	rb_hash_foreach(hash, clear_i, 0);
    }

    return hash;
}

/*
 *  call-seq:
 *     hsh[key] = value        => value
 *     hsh.store(key, value)   => value
 *
 *  Element Assignment---Associates the value given by
 *  <i>value</i> with the key given by <i>key</i>.
 *  <i>key</i> should not have its value changed while it is in
 *  use as a key (a <code>String</code> passed as a key will be
 *  duplicated and frozen).
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h["a"] = 9
 *     h["c"] = 4
 *     h   #=> {"a"=>9, "b"=>200, "c"=>4}
 *
 */

VALUE
rb_hash_aset(hash, key, val)
    VALUE hash, key, val;
{
    rb_hash_modify(hash);
    if (TYPE(key) != T_STRING || st_lookup(RHASH(hash)->tbl, key, 0)) {
	st_insert(RHASH(hash)->tbl, key, val);
    }
    else {
	st_add_direct(RHASH(hash)->tbl, rb_str_new4(key), val);
    }
    return val;
}

static int
replace_i(key, val, hash)
    VALUE key, val, hash;
{
    if (key != Qundef) {
	rb_hash_aset(hash, key, val);
    }

    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.replace(other_hash) -> hsh
 *
 *  Replaces the contents of <i>hsh</i> with the contents of
 *  <i>other_hash</i>.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.replace({ "c" => 300, "d" => 400 })   #=> {"c"=>300, "d"=>400}
 *
 */

static VALUE
rb_hash_replace(hash, hash2)
    VALUE hash, hash2;
{
    hash2 = to_hash(hash2);
    if (hash == hash2) return hash;
    rb_hash_clear(hash);
    rb_hash_foreach(hash2, replace_i, hash);
    RHASH(hash)->ifnone = RHASH(hash2)->ifnone;
    if (FL_TEST(hash2, HASH_PROC_DEFAULT)) {
	FL_SET(hash, HASH_PROC_DEFAULT);
    }
    else {
	FL_UNSET(hash, HASH_PROC_DEFAULT);
    }

    return hash;
}

/*
 *  call-seq:
 *     hsh.length    =>  fixnum
 *     hsh.size      =>  fixnum
 *
 *  Returns the number of key-value pairs in the hash.
 *
 *     h = { "d" => 100, "a" => 200, "v" => 300, "e" => 400 }
 *     h.length        #=> 4
 *     h.delete("a")   #=> 200
 *     h.length        #=> 3
 */

static VALUE
rb_hash_size(hash)
    VALUE hash;
{
    return INT2FIX(RHASH(hash)->tbl->num_entries);
}


/*
 *  call-seq:
 *     hsh.empty?    => true or false
 *
 *  Returns <code>true</code> if <i>hsh</i> contains no key-value pairs.
 *
 *     {}.empty?   #=> true
 *
 */

static VALUE
rb_hash_empty_p(hash)
    VALUE hash;
{
    if (RHASH(hash)->tbl->num_entries == 0)
	return Qtrue;
    return Qfalse;
}

static int
each_value_i(key, value)
    VALUE key, value;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_yield(value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.each_value {| value | block } -> hsh
 *
 *  Calls <i>block</i> once for each key in <i>hsh</i>, passing the
 *  value as a parameter.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.each_value {|value| puts value }
 *
 *  <em>produces:</em>
 *
 *     100
 *     200
 */

static VALUE
rb_hash_each_value(hash)
    VALUE hash;
{
    RETURN_ENUMERATOR(hash, 0, 0);
    rb_hash_foreach(hash, each_value_i, 0);
    return hash;
}

static int
each_key_i(key, value)
    VALUE key, value;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_yield(key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.each_key {| key | block } -> hsh
 *
 *  Calls <i>block</i> once for each key in <i>hsh</i>, passing the key
 *  as a parameter.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.each_key {|key| puts key }
 *
 *  <em>produces:</em>
 *
 *     a
 *     b
 */
static VALUE
rb_hash_each_key(hash)
    VALUE hash;
{
    RETURN_ENUMERATOR(hash, 0, 0);
    rb_hash_foreach(hash, each_key_i, 0);
    return hash;
}

static int
each_pair_i(key, value)
    VALUE key, value;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_yield_values(2, key, value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.each_pair {| key_value_array | block } -> hsh
 *
 *  Calls <i>block</i> once for each key in <i>hsh</i>, passing the key
 *  and value as parameters.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.each_pair {|key, value| puts "#{key} is #{value}" }
 *
 *  <em>produces:</em>
 *
 *     a is 100
 *     b is 200
 *
 */

static VALUE
rb_hash_each_pair(hash)
    VALUE hash;
{
    RETURN_ENUMERATOR(hash, 0, 0);
    rb_hash_foreach(hash, each_pair_i, 0);
    return hash;
}

static int
each_i(key, value)
    VALUE key, value;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_yield(rb_assoc_new(key, value));
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.each {| key, value | block } -> hsh
 *
 *  Calls <i>block</i> once for each key in <i>hsh</i>, passing the key
 *  and value to the block as a two-element array. Because of the assignment
 *  semantics of block parameters, these elements will be split out if the
 *  block has two formal parameters. Also see <code>Hash.each_pair</code>, which
 *  will be marginally more efficient for blocks with two parameters.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.each {|key, value| puts "#{key} is #{value}" }
 *
 *  <em>produces:</em>
 *
 *     a is 100
 *     b is 200
 *
 */

static VALUE
rb_hash_each(hash)
    VALUE hash;
{
    RETURN_ENUMERATOR(hash, 0, 0);
    rb_hash_foreach(hash, each_i, 0);
    return hash;
}

static int
to_a_i(key, value, ary)
    VALUE key, value, ary;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_ary_push(ary, rb_assoc_new(key, value));
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.to_a -> array
 *
 *  Converts <i>hsh</i> to a nested array of <code>[</code> <i>key,
 *  value</i> <code>]</code> arrays.
 *
 *     h = { "c" => 300, "a" => 100, "d" => 400, "c" => 300  }
 *     h.to_a   #=> [["a", 100], ["c", 300], ["d", 400]]
 */

static VALUE
rb_hash_to_a(hash)
    VALUE hash;
{
    VALUE ary;

    ary = rb_ary_new();
    rb_hash_foreach(hash, to_a_i, ary);
    if (OBJ_TAINTED(hash)) OBJ_TAINT(ary);

    return ary;
}

/*
 *  call-seq:
 *     hsh.sort                    => array
 *     hsh.sort {| a, b | block }  => array
 *
 *  Converts <i>hsh</i> to a nested array of <code>[</code> <i>key,
 *  value</i> <code>]</code> arrays and sorts it, using
 *  <code>Array#sort</code>.
 *
 *     h = { "a" => 20, "b" => 30, "c" => 10  }
 *     h.sort                       #=> [["a", 20], ["b", 30], ["c", 10]]
 *     h.sort {|a,b| a[1]<=>b[1]}   #=> [["c", 10], ["a", 20], ["b", 30]]
 *
 */

static VALUE
rb_hash_sort(hash)
    VALUE hash;
{
    VALUE entries = rb_hash_to_a(hash);
    rb_ary_sort_bang(entries);
    return entries;
}

static int
inspect_i(key, value, str)
    VALUE key, value, str;
{
    VALUE str2;

    if (key == Qundef) return ST_CONTINUE;
    if (RSTRING(str)->len > 1) {
	rb_str_cat2(str, ", ");
    }
    str2 = rb_inspect(key);
    rb_str_buf_append(str, str2);
    OBJ_INFECT(str, str2);
    rb_str_buf_cat2(str, "=>");
    str2 = rb_inspect(value);
    rb_str_buf_append(str, str2);
    OBJ_INFECT(str, str2);

    return ST_CONTINUE;
}

static VALUE
inspect_hash(hash)
    VALUE hash;
{
    VALUE str;

    str = rb_str_buf_new2("{");
    rb_hash_foreach(hash, inspect_i, str);
    rb_str_buf_cat2(str, "}");
    OBJ_INFECT(str, hash);

    return str;
}

/*
 * call-seq:
 *   hsh.inspect  => string
 *
 * Return the contents of this hash as a string.
 */

static VALUE
rb_hash_inspect(hash)
    VALUE hash;
{
    if (RHASH(hash)->tbl == 0 || RHASH(hash)->tbl->num_entries == 0)
	return rb_str_new2("{}");
    if (rb_inspecting_p(hash)) return rb_str_new2("{...}");
    return rb_protect_inspect(inspect_hash, hash, 0);
}

static VALUE
to_s_hash(hash)
    VALUE hash;
{
    return rb_ary_to_s(rb_hash_to_a(hash));
}

/*
 *  call-seq:
 *     hsh.to_s   => string
 *
 *  Converts <i>hsh</i> to a string by converting the hash to an array
 *  of <code>[</code> <i>key, value</i> <code>]</code> pairs and then
 *  converting that array to a string using <code>Array#join</code> with
 *  the default separator.
 *
 *     h = { "c" => 300, "a" => 100, "d" => 400, "c" => 300  }
 *     h.to_s   #=> "a100c300d400"
 */

static VALUE
rb_hash_to_s(hash)
    VALUE hash;
{
    if (rb_inspecting_p(hash)) return rb_str_new2("{...}");
    return rb_protect_inspect(to_s_hash, hash, 0);
}

/*
 * call-seq:
 *    hsh.to_hash   => hsh
 *
 * Returns <i>self</i>.
 */

static VALUE
rb_hash_to_hash(hash)
    VALUE hash;
{
    return hash;
}

static int
keys_i(key, value, ary)
    VALUE key, value, ary;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_ary_push(ary, key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.keys    => array
 *
 *  Returns a new array populated with the keys from this hash. See also
 *  <code>Hash#values</code>.
 *
 *     h = { "a" => 100, "b" => 200, "c" => 300, "d" => 400 }
 *     h.keys   #=> ["a", "b", "c", "d"]
 *
 */

static VALUE
rb_hash_keys(hash)
    VALUE hash;
{
    VALUE ary;

    ary = rb_ary_new();
    rb_hash_foreach(hash, keys_i, ary);

    return ary;
}

static int
values_i(key, value, ary)
    VALUE key, value, ary;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_ary_push(ary, value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.values    => array
 *
 *  Returns a new array populated with the values from <i>hsh</i>. See
 *  also <code>Hash#keys</code>.
 *
 *     h = { "a" => 100, "b" => 200, "c" => 300 }
 *     h.values   #=> [100, 200, 300]
 *
 */

static VALUE
rb_hash_values(hash)
    VALUE hash;
{
    VALUE ary;

    ary = rb_ary_new();
    rb_hash_foreach(hash, values_i, ary);

    return ary;
}

/*
 *  call-seq:
 *     hsh.has_key?(key)    => true or false
 *     hsh.include?(key)    => true or false
 *     hsh.key?(key)        => true or false
 *     hsh.member?(key)     => true or false
 *
 *  Returns <code>true</code> if the given key is present in <i>hsh</i>.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.has_key?("a")   #=> true
 *     h.has_key?("z")   #=> false
 *
 */

static VALUE
rb_hash_has_key(hash, key)
    VALUE hash;
    VALUE key;
{
    if (st_lookup(RHASH(hash)->tbl, key, 0)) {
	return Qtrue;
    }
    return Qfalse;
}

static int
rb_hash_search_value(key, value, data)
    VALUE key, value, *data;
{
    if (key == Qundef) return ST_CONTINUE;
    if (rb_equal(value, data[1])) {
	data[0] = Qtrue;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.has_value?(value)    => true or false
 *     hsh.value?(value)        => true or false
 *
 *  Returns <code>true</code> if the given value is present for some key
 *  in <i>hsh</i>.
 *
 *     h = { "a" => 100, "b" => 200 }
 *     h.has_value?(100)   #=> true
 *     h.has_value?(999)   #=> false
 */

static VALUE
rb_hash_has_value(hash, val)
    VALUE hash;
    VALUE val;
{
    VALUE data[2];

    data[0] = Qfalse;
    data[1] = val;
    rb_hash_foreach(hash, rb_hash_search_value, (st_data_t)data);
    return data[0];
}

struct equal_data {
    int result;
    st_table *tbl;
    int eql;
};

static int
eql_i(key, val1, data)
    VALUE key;
    VALUE val1;
    struct equal_data *data;
{
    VALUE val2;

    if (key == Qundef) return ST_CONTINUE;
    if (!st_lookup(data->tbl, key, &val2)) {
	data->result = Qfalse;
	return ST_STOP;
    }
    if (!(data->eql ? rb_eql(val1, val2) : rb_equal(val1, val2))) {
	data->result = Qfalse;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

static VALUE recursive_eql _((VALUE, VALUE, int));
static VALUE
recursive_eql(hash, dt, recur)
    VALUE hash;
    VALUE dt;
    int recur;
{
    struct equal_data *data;

    if (recur) return Qfalse;
    data = (struct equal_data*)dt;
    data->result = Qtrue;
    rb_hash_foreach(hash, eql_i, (st_data_t)data);

    return data->result;
}

static VALUE
hash_equal(hash1, hash2, eql)
    VALUE hash1, hash2;
    int eql;			/* compare default value if true */
{
    struct equal_data data;

    if (hash1 == hash2) return Qtrue;
    if (TYPE(hash2) != T_HASH) {
	if (!rb_respond_to(hash2, rb_intern("to_hash"))) {
	    return Qfalse;
	}
	return rb_equal(hash2, hash1);
    }
    if (RHASH(hash1)->tbl->num_entries != RHASH(hash2)->tbl->num_entries)
	return Qfalse;
    if (eql) {
	if (!(rb_equal(RHASH(hash1)->ifnone, RHASH(hash2)->ifnone) &&
	      FL_TEST(hash1, HASH_PROC_DEFAULT) == FL_TEST(hash2, HASH_PROC_DEFAULT)))
	    return Qfalse;
    }

    data.tbl = RHASH(hash2)->tbl;
    data.eql = eql;
    return rb_exec_recursive(recursive_eql, hash1, (VALUE)&data);
}

/*
 *  call-seq:
 *     hsh == other_hash    => true or false
 *
 *  Equality---Two hashes are equal if they each contain the same number
 *  of keys and if each key-value pair is equal to (according to
 *  <code>Object#==</code>) the corresponding elements in the other
 *  hash.
 *
 *     h1 = { "a" => 1, "c" => 2 }
 *     h2 = { 7 => 35, "c" => 2, "a" => 1 }
 *     h3 = { "a" => 1, "c" => 2, 7 => 35 }
 *     h4 = { "a" => 1, "d" => 2, "f" => 35 }
 *     h1 == h2   #=> false
 *     h2 == h3   #=> true
 *     h3 == h4   #=> false
 *
 */

static VALUE
rb_hash_equal(hash1, hash2)
    VALUE hash1, hash2;
{
    return hash_equal(hash1, hash2, Qfalse);
}

static int
hash_i(key, val, hval)
    VALUE key;
    VALUE val;
    int *hval;
{
    if (key == Qundef) return ST_CONTINUE;
    *hval ^= rb_hash(key);
    *hval ^= rb_hash(val);
    return ST_CONTINUE;
}

static VALUE recursive_hash _((VALUE, VALUE, int));
static VALUE
recursive_hash(hash, dummy, recur)
    VALUE hash;
    VALUE dummy;
    int recur;
{
    int hval;

    if (recur) {
	return LONG2FIX(0);
    }
    hval = RHASH(hash)->tbl->num_entries;
    rb_hash_foreach(hash, hash_i, (st_data_t)&hval);
    return INT2FIX(hval);
}

/*
 *  call-seq:
 *     array.hash   -> fixnum
 *
 *  Compute a hash-code for this array. Two arrays with the same content
 *  will have the same hash code (and will compare using <code>eql?</code>).
 */

static VALUE
rb_hash_hash(hash)
    VALUE hash;
{
    return rb_exec_recursive(recursive_hash, hash, 0);
}


/*
 *  call-seq:
 *     hash.eql?(other)  -> true or false
 *
 *  Returns <code>true</code> if <i>hash</i> and <i>other</i> are
 *  both hashes with the same content.
 */

static VALUE
rb_hash_eql(hash1, hash2)
    VALUE hash1, hash2;
{
    return hash_equal(hash1, hash2, Qtrue);
}

static int
rb_hash_invert_i(key, value, hash)
    VALUE key, value;
    VALUE hash;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_hash_aset(hash, value, key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.invert -> aHash
 *
 *  Returns a new hash created by using <i>hsh</i>'s values as keys, and
 *  the keys as values.
 *
 *     h = { "n" => 100, "m" => 100, "y" => 300, "d" => 200, "a" => 0 }
 *     h.invert   #=> {0=>"a", 100=>"n", 200=>"d", 300=>"y"}
 *
 */

static VALUE
rb_hash_invert(hash)
    VALUE hash;
{
    VALUE h = rb_hash_new();

    rb_hash_foreach(hash, rb_hash_invert_i, h);
    return h;
}

static int
rb_hash_update_i(key, value, hash)
    VALUE key, value;
    VALUE hash;
{
    if (key == Qundef) return ST_CONTINUE;
    rb_hash_aset(hash, key, value);
    return ST_CONTINUE;
}

static int
rb_hash_update_block_i(key, value, hash)
    VALUE key, value;
    VALUE hash;
{
    if (key == Qundef) return ST_CONTINUE;
    if (rb_hash_has_key(hash, key)) {
	value = rb_yield_values(3, key, rb_hash_aref(hash, key), value);
    }
    rb_hash_aset(hash, key, value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hsh.merge!(other_hash)                                 => hsh
 *     hsh.update(other_hash)                                 => hsh
 *     hsh.merge!(other_hash){|key, oldval, newval| block}    => hsh
 *     hsh.update(other_hash){|key, oldval, newval| block}    => hsh
 *
 *  Adds the contents of <i>other_hash</i> to <i>hsh</i>.  If no
 *  block is specified entries with duplicate keys are overwritten
 *  with the values from <i>other_hash</i>, otherwise the value
 *  of each duplicate key is determined by calling the block with
 *  the key, its value in <i>hsh</i> and its value in <i>other_hash</i>.
 *
 *     h1 = { "a" => 100, "b" => 200 }
 *     h2 = { "b" => 254, "c" => 300 }
 *     h1.merge!(h2)   #=> {"a"=>100, "b"=>254, "c"=>300}
 *
 *     h1 = { "a" => 100, "b" => 200 }
 *     h2 = { "b" => 254, "c" => 300 }
 *     h1.merge!(h2) { |key, v1, v2| v1 }
 *                     #=> {"a"=>100, "b"=>200, "c"=>300}
 */

static VALUE
rb_hash_update(hash1, hash2)
    VALUE hash1, hash2;
{
    hash2 = to_hash(hash2);
    if (rb_block_given_p()) {
	rb_hash_foreach(hash2, rb_hash_update_block_i, hash1);
    }
    else {
	rb_hash_foreach(hash2, rb_hash_update_i, hash1);
    }
    return hash1;
}

/*
 *  call-seq:
 *     hsh.merge(other_hash)                              -> a_hash
 *     hsh.merge(other_hash){|key, oldval, newval| block} -> a_hash
 *
 *  Returns a new hash containing the contents of <i>other_hash</i> and
 *  the contents of <i>hsh</i>, overwriting entries in <i>hsh</i> with
 *  duplicate keys with those from <i>other_hash</i>.
 *
 *     h1 = { "a" => 100, "b" => 200 }
 *     h2 = { "b" => 254, "c" => 300 }
 *     h1.merge(h2)   #=> {"a"=>100, "b"=>254, "c"=>300}
 *     h1             #=> {"a"=>100, "b"=>200}
 *
 */

static VALUE
rb_hash_merge(hash1, hash2)
    VALUE hash1, hash2;
{
    return rb_hash_update(rb_obj_dup(hash1), hash2);
}

static int path_tainted = -1;

static char **origenviron;
#ifdef _WIN32
#define GET_ENVIRON(e) (e = rb_w32_get_environ())
#define FREE_ENVIRON(e) rb_w32_free_environ(e)
static char **my_environ;
#undef environ
#define environ my_environ
#elif defined(__APPLE__)
#undef environ
#define environ (*_NSGetEnviron())
#define GET_ENVIRON(e) (e)
#define FREE_ENVIRON(e)
#else
extern char **environ;
#define GET_ENVIRON(e) (e)
#define FREE_ENVIRON(e)
#endif

static VALUE
env_str_new(ptr, len)
    const char *ptr;
    long len;
{
    VALUE str = rb_tainted_str_new(ptr, len);

    rb_obj_freeze(str);
    return str;
}

static VALUE
env_str_new2(ptr)
    const char *ptr;
{
    if (!ptr) return Qnil;
    return env_str_new(ptr, strlen(ptr));
}

static VALUE
env_delete(obj, name)
    VALUE obj, name;
{
    char *nam, *val;

    rb_secure(4);
    SafeStringValue(name);
    nam = RSTRING(name)->ptr;
    if (strlen(nam) != RSTRING(name)->len) {
	rb_raise(rb_eArgError, "bad environment variable name");
    }
    val = getenv(nam);
    if (val) {
	VALUE value = env_str_new2(val);

	ruby_setenv(nam, 0);
#ifdef ENV_IGNORECASE
	if (strcasecmp(nam, PATH_ENV) == 0)
#else
	if (strcmp(nam, PATH_ENV) == 0)
#endif
	{
	    path_tainted = 0;
	}
	return value;
    }
    return Qnil;
}

static VALUE
env_delete_m(obj, name)
    VALUE obj, name;
{
    VALUE val;

    val = env_delete(obj, name);
    if (NIL_P(val) && rb_block_given_p()) rb_yield(name);
    return val;
}

static VALUE
rb_f_getenv(obj, name)
    VALUE obj, name;
{
    char *nam, *env;

    rb_secure(4);
    SafeStringValue(name);
    nam = RSTRING(name)->ptr;
    if (strlen(nam) != RSTRING(name)->len) {
	rb_raise(rb_eArgError, "bad environment variable name");
    }
    env = getenv(nam);
    if (env) {
#ifdef ENV_IGNORECASE
	if (strcasecmp(nam, PATH_ENV) == 0 && !rb_env_path_tainted())
#else
	if (strcmp(nam, PATH_ENV) == 0 && !rb_env_path_tainted())
#endif
	{
	    VALUE str = rb_str_new2(env);

	    rb_obj_freeze(str);
	    return str;
	}
	return env_str_new2(env);
    }
    return Qnil;
}

static VALUE
env_fetch(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE key, if_none;
    long block_given;
    char *nam, *env;

    rb_secure(4);
    rb_scan_args(argc, argv, "11", &key, &if_none);
    block_given = rb_block_given_p();
    if (block_given && argc == 2) {
	rb_warn("block supersedes default value argument");
    }
    SafeStringValue(key);
    nam = RSTRING(key)->ptr;
    if (strlen(nam) != RSTRING(key)->len) {
	rb_raise(rb_eArgError, "bad environment variable name");
    }
    env = getenv(nam);
    if (!env) {
	if (block_given) return rb_yield(key);
	if (argc == 1) {
	    rb_raise(rb_eIndexError, "key not found");
	}
	return if_none;
    }
#ifdef ENV_IGNORECASE
    if (strcasecmp(nam, PATH_ENV) == 0 && !rb_env_path_tainted())
#else
    if (strcmp(nam, PATH_ENV) == 0 && !rb_env_path_tainted())
#endif
	return rb_str_new2(env);
    return env_str_new2(env);
}

static void
path_tainted_p(path)
    char *path;
{
    path_tainted = rb_path_check(path)?0:1;
}

int
rb_env_path_tainted()
{
    if (path_tainted < 0) {
	path_tainted_p(getenv(PATH_ENV));
    }
    return path_tainted;
}

#if !defined(_WIN32) && !(defined(HAVE_SETENV) && defined(HAVE_UNSETENV))
static int
envix(nam)
    const char *nam;
{
    register int i, len = strlen(nam);
    char **env;

    env = GET_ENVIRON(environ);
    for (i = 0; env[i]; i++) {
	if (
#ifdef ENV_IGNORECASE
	    strncasecmp(env[i],nam,len) == 0
#else
	    memcmp(env[i],nam,len) == 0
#endif
	    && env[i][len] == '=')
	    break;			/* memcmp must come first to avoid */
    }					/* potential SEGV's */
    FREE_ENVIRON(environ);
    return i;
}
#endif

void
ruby_setenv(name, value)
    const char *name;
    const char *value;
{
#if defined(_WIN32)
    /* The sane way to deal with the environment.
     * Has these advantages over putenv() & co.:
     *  * enables us to store a truly empty value in the
     *    environment (like in UNIX).
     *  * we don't have to deal with RTL globals, bugs and leaks.
     *  * Much faster.
     * Why you may want to enable USE_WIN32_RTL_ENV:
     *  * environ[] and RTL functions will not reflect changes,
     *    which might be an issue if extensions want to access
     *    the env. via RTL.  This cuts both ways, since RTL will
     *    not see changes made by extensions that call the Win32
     *    functions directly, either.
     * GSAR 97-06-07
     *
     * REMARK: USE_WIN32_RTL_ENV is already obsoleted since we don't use
     *         RTL's environ global variable directly yet.
     */
    SetEnvironmentVariable(name,value);
#elif defined(HAVE_SETENV) && defined(HAVE_UNSETENV)
#undef setenv
#undef unsetenv
    if (value)
	setenv(name,value,1);
    else
	unsetenv(name);
#else  /* WIN32 */
    size_t len;
    int i=envix(name);		        /* where does it go? */

    if (environ == origenviron) {	/* need we copy environment? */
	int j;
	int max;
	char **tmpenv;

	for (max = i; environ[max]; max++) ;
	tmpenv = ALLOC_N(char*, max+2);
	for (j=0; j<max; j++)		/* copy environment */
	    tmpenv[j] = strdup(environ[j]);
	tmpenv[max] = 0;
	environ = tmpenv;		/* tell exec where it is now */
    }
    if (environ[i]) {
	char **envp = origenviron;
	while (*envp && *envp != environ[i]) envp++;
	if (!*envp)
	    free(environ[i]);
	if (!value) {
	    while (environ[i]) {
		environ[i] = environ[i+1];
		i++;
	    }
	    return;
	}
    }
    else {			/* does not exist yet */
	if (!value) return;
	REALLOC_N(environ, char*, i+2);	/* just expand it a bit */
	environ[i+1] = 0;	/* make sure it's null terminated */
    }
    len = strlen(name) + strlen(value) + 2;
    environ[i] = ALLOC_N(char, len);
#ifndef MSDOS
    snprintf(environ[i],len,"%s=%s",name,value); /* all that work just for this */
#else
    /* MS-DOS requires environment variable names to be in uppercase */
    /* [Tom Dinger, 27 August 1990: Well, it doesn't _require_ it, but
     * some utilities and applications may break because they only look
     * for upper case strings. (Fixed strupr() bug here.)]
     */
    strcpy(environ[i],name); strupr(environ[i]);
    sprintf(environ[i] + strlen(name),"=%s", value);
#endif /* MSDOS */

#endif /* WIN32 */
}

void
ruby_unsetenv(name)
    const char *name;
{
    ruby_setenv(name, 0);
}

static VALUE
env_aset(obj, nm, val)
    VALUE obj, nm, val;
{
    char *name, *value;

    if (rb_safe_level() >= 4) {
	rb_raise(rb_eSecurityError, "can't change environment variable");
    }

    if (NIL_P(val)) {
	env_delete(obj, nm);
	return Qnil;
    }

    StringValue(nm);
    StringValue(val);
    name = RSTRING(nm)->ptr;
    value = RSTRING(val)->ptr;
    if (strlen(name) != RSTRING(nm)->len)
	rb_raise(rb_eArgError, "bad environment variable name");
    if (strlen(value) != RSTRING(val)->len)
	rb_raise(rb_eArgError, "bad environment variable value");

    ruby_setenv(name, value);
#ifdef ENV_IGNORECASE
    if (strcasecmp(name, PATH_ENV) == 0) {
#else
    if (strcmp(name, PATH_ENV) == 0) {
#endif
	if (OBJ_TAINTED(val)) {
	    /* already tainted, no check */
	    path_tainted = 1;
	    return val;
	}
	else {
	    path_tainted_p(value);
	}
    }
    return val;
}

static VALUE
env_keys()
{
    char **env;
    VALUE ary;

    rb_secure(4);
    ary = rb_ary_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, env_str_new(*env, s-*env));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return ary;
}

static VALUE
env_each_key(ehash)
    VALUE ehash;
{
    VALUE keys;
    long i;

    RETURN_ENUMERATOR(ehash, 0, 0);
    keys = env_keys();	/* rb_secure(4); */
    for (i=0; i<RARRAY(keys)->len; i++) {
	rb_yield(RARRAY(keys)->ptr[i]);
    }
    return ehash;
}

static VALUE
env_values()
{
    VALUE ary;
    char **env;

    rb_secure(4);
    ary = rb_ary_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, env_str_new2(s+1));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return ary;
}

static VALUE
env_each_value(ehash)
    VALUE ehash;
{
    VALUE values;
    long i;

    RETURN_ENUMERATOR(ehash, 0, 0);
    values = env_values();	/* rb_secure(4); */
    for (i=0; i<RARRAY(values)->len; i++) {
	rb_yield(RARRAY(values)->ptr[i]);
    }
    return ehash;
}

static VALUE
env_each_i(ehash, values)
    VALUE ehash;
    int values;
{
    char **env;
    VALUE ary;
    long i;

    rb_secure(4);
    ary = rb_ary_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, env_str_new(*env, s-*env));
	    rb_ary_push(ary, env_str_new2(s+1));
	}
	env++;
    }
    FREE_ENVIRON(environ);

    for (i=0; i<RARRAY(ary)->len; i+=2) {
	if (values) {
	    rb_yield_values(2, RARRAY(ary)->ptr[i], RARRAY(ary)->ptr[i+1]);
	}
	else {
	    rb_yield(rb_assoc_new(RARRAY(ary)->ptr[i], RARRAY(ary)->ptr[i+1]));
	}
    }
    return ehash;
}

static VALUE
env_each(ehash)
    VALUE ehash;
{
    RETURN_ENUMERATOR(ehash, 0, 0);
    return env_each_i(ehash, Qfalse);
}

static VALUE
env_each_pair(ehash)
    VALUE ehash;
{
    RETURN_ENUMERATOR(ehash, 0, 0);
    return env_each_i(ehash, Qtrue);
}

static VALUE
env_reject_bang(ehash)
    VALUE ehash;
{
    volatile VALUE keys;
    long i;
    int del = 0;

    RETURN_ENUMERATOR(ehash, 0, 0);
    keys = env_keys();	/* rb_secure(4); */
    for (i=0; i<RARRAY(keys)->len; i++) {
	VALUE val = rb_f_getenv(Qnil, RARRAY(keys)->ptr[i]);
	if (!NIL_P(val)) {
	    if (RTEST(rb_yield_values(2, RARRAY(keys)->ptr[i], val))) {
		FL_UNSET(RARRAY(keys)->ptr[i], FL_TAINT);
		env_delete(Qnil, RARRAY(keys)->ptr[i]);
		del++;
	    }
	}
    }
    if (del == 0) return Qnil;
    return envtbl;
}

static VALUE
env_delete_if(ehash)
    VALUE ehash;
{
    RETURN_ENUMERATOR(ehash, 0, 0);
    env_reject_bang(ehash);
    return envtbl;
}

static VALUE
env_values_at(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE result;
    long i;

    rb_secure(4);
    result = rb_ary_new();
    for (i=0; i<argc; i++) {
	rb_ary_push(result, rb_f_getenv(Qnil, argv[i]));
    }
    return result;
}

static VALUE
env_select(ehash)
    VALUE ehash;
{
    VALUE result;
    char **env;

    RETURN_ENUMERATOR(ehash, 0, 0);
    rb_secure(4);
    result = rb_ary_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    VALUE k = env_str_new(*env, s-*env);
	    VALUE v = env_str_new2(s+1);
	    if (RTEST(rb_yield_values(2, k, v))) {
		rb_ary_push(result, rb_assoc_new(k, v));
	    }
	}
	env++;
    }
    FREE_ENVIRON(environ);

    return result;
}

static VALUE
env_clear()
{
    volatile VALUE keys;
    long i;

    keys = env_keys();	/* rb_secure(4); */
    for (i=0; i<RARRAY(keys)->len; i++) {
	VALUE val = rb_f_getenv(Qnil, RARRAY(keys)->ptr[i]);
	if (!NIL_P(val)) {
	    env_delete(Qnil, RARRAY(keys)->ptr[i]);
	}
    }
    return envtbl;
}

static VALUE
env_to_s()
{
    return rb_str_new2("ENV");
}

static VALUE
env_inspect()
{
    char **env;
    VALUE str, i;

    rb_secure(4);
    str = rb_str_buf_new2("{");
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');

	if (env != environ) {
	    rb_str_buf_cat2(str, ", ");
	}
	if (s) {
	    rb_str_buf_cat2(str, "\"");
	    rb_str_buf_cat(str, *env, s-*env);
	    rb_str_buf_cat2(str, "\"=>");
	    i = rb_inspect(rb_str_new2(s+1));
	    rb_str_buf_append(str, i);
	}
	env++;
    }
    FREE_ENVIRON(environ);
    rb_str_buf_cat2(str, "}");
    OBJ_TAINT(str);

    return str;
}

static VALUE
env_to_a()
{
    char **env;
    VALUE ary;

    rb_secure(4);
    ary = rb_ary_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, rb_assoc_new(env_str_new(*env, s-*env),
					  env_str_new2(s+1)));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return ary;
}

static VALUE
env_none()
{
    return Qnil;
}

static VALUE
env_size()
{
    int i;
    char **env;

    rb_secure(4);
    env = GET_ENVIRON(environ);
    for(i=0; env[i]; i++)
	;
    FREE_ENVIRON(environ);
    return INT2FIX(i);
}

static VALUE
env_empty_p()
{
    char **env;

    rb_secure(4);
    env = GET_ENVIRON(environ);
    if (env[0] == 0) {
	FREE_ENVIRON(environ);
	return Qtrue;
    }
    FREE_ENVIRON(environ);
    return Qfalse;
}

static VALUE
env_has_key(env, key)
    VALUE env, key;
{
    char *s;

    rb_secure(4);
    s = StringValuePtr(key);
    if (strlen(s) != RSTRING(key)->len)
	rb_raise(rb_eArgError, "bad environment variable name");
    if (getenv(s)) return Qtrue;
    return Qfalse;
}

static VALUE
env_has_value(dmy, value)
    VALUE dmy, value;
{
    char **env;

    rb_secure(4);
    value = rb_check_string_type(value);
    if (NIL_P(value)) return Qfalse;
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s++) {
	    long len = strlen(s);
	    if (RSTRING(value)->len == len && strncmp(s, RSTRING(value)->ptr, len) == 0) {
		FREE_ENVIRON(environ);
		return Qtrue;
	    }
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return Qfalse;
}

static VALUE
env_index(dmy, value)
    VALUE dmy, value;
{
    char **env;
    VALUE str;

    rb_secure(4);
    StringValue(value);
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s++) {
	    long len = strlen(s);
	    if (RSTRING(value)->len == len && strncmp(s, RSTRING(value)->ptr, len) == 0) {
		str = env_str_new(*env, s-*env-1);
		FREE_ENVIRON(environ);
		return str;
	    }
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return Qnil;
}

static VALUE
env_indexes(argc, argv)
    int argc;
    VALUE *argv;
{
    int i;
    VALUE indexes = rb_ary_new2(argc);

    rb_warn("ENV.%s is deprecated; use ENV.values_at",
	    rb_id2name(rb_frame_last_func()));
    rb_secure(4);
    for (i=0;i<argc;i++) {
	VALUE tmp = rb_check_string_type(argv[i]);
	if (NIL_P(tmp)) {
	    RARRAY(indexes)->ptr[i] = Qnil;
	}
	else {
	    RARRAY(indexes)->ptr[i] = env_str_new2(getenv(RSTRING(tmp)->ptr));
	}
	RARRAY(indexes)->len = i+1;
    }

    return indexes;
}

static VALUE
env_to_hash()
{
    char **env;
    VALUE hash;

    rb_secure(4);
    hash = rb_hash_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_hash_aset(hash, env_str_new(*env, s-*env),
			       env_str_new2(s+1));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return hash;
}

static VALUE
env_reject()
{
    return rb_hash_delete_if(env_to_hash());
}

static VALUE
env_shift()
{
    char **env;

    rb_secure(4);
    env = GET_ENVIRON(environ);
    if (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    VALUE key = env_str_new(*env, s-*env);
	    VALUE val = env_str_new2(getenv(RSTRING(key)->ptr));
	    env_delete(Qnil, key);
	    return rb_assoc_new(key, val);
	}
    }
    FREE_ENVIRON(environ);
    return Qnil;
}

static VALUE
env_invert()
{
    return rb_hash_invert(env_to_hash());
}

static int
env_replace_i(key, val, keys)
    VALUE key, val, keys;
{
    if (key != Qundef) {
	env_aset(Qnil, key, val);
	if (rb_ary_includes(keys, key)) {
	    rb_ary_delete(keys, key);
	}
    }
    return ST_CONTINUE;
}

static VALUE
env_replace(env, hash)
    VALUE env, hash;
{
    volatile VALUE keys;
    long i;

    keys = env_keys();	/* rb_secure(4); */
    if (env == hash) return env;
    hash = to_hash(hash);
    rb_hash_foreach(hash, env_replace_i, keys);

    for (i=0; i<RARRAY(keys)->len; i++) {
	env_delete(env, RARRAY(keys)->ptr[i]);
    }
    return env;
}

static int
env_update_i(key, val)
    VALUE key, val;
{
    if (key != Qundef) {
	if (rb_block_given_p()) {
	    val = rb_yield_values(3, key, rb_f_getenv(Qnil, key), val);
	}
	env_aset(Qnil, key, val);
    }
    return ST_CONTINUE;
}

static VALUE
env_update(env, hash)
    VALUE env, hash;
{
    rb_secure(4);
    if (env == hash) return env;
    hash = to_hash(hash);
    rb_hash_foreach(hash, env_update_i, 0);
    return env;
}

/*
 *  A <code>Hash</code> is a collection of key-value pairs. It is
 *  similar to an <code>Array</code>, except that indexing is done via
 *  arbitrary keys of any object type, not an integer index. The order
 *  in which you traverse a hash by either key or value may seem
 *  arbitrary, and will generally not be in the insertion order.
 *
 *  Hashes have a <em>default value</em> that is returned when accessing
 *  keys that do not exist in the hash. By default, that value is
 *  <code>nil</code>.
 *
 *  <code>Hash</code> uses <code>key.eql?</code> to test keys for equality.
 *  If you need to use instances of your own classes as keys in a <code>Hash</code>,
 *  it is recommended that you define both the <code>eql?</code> and <code>hash</code>
 *  methods. The <code>hash</code> method must have the property that
 *  <code>a.eql?(b)</code> implies <code>a.hash == b.hash</code>.
 *
 *    class MyClass
 *      attr_reader :str
 *      def initialize(str)
 *        @str = str
 *      end
 *      def eql?(o)
 *        o.is_a?(MyClass) && str == o.str
 *      end
 *      def hash
 *        @str.hash
 *      end
 *    end
 *
 *    a = MyClass.new("some string")
 *    b = MyClass.new("some string")
 *    a.eql? b  #=> true
 *
 *    h = {}
 *
 *    h[a] = 1
 *    h[a]      #=> 1
 *    h[b]      #=> 1
 *
 *    h[b] = 2
 *    h[a]      #=> 2
 *    h[b]      #=> 2
 */

void
Init_Hash()
{
    id_hash = rb_intern("hash");
    id_call = rb_intern("call");
    id_default = rb_intern("default");

    rb_cHash = rb_define_class("Hash", rb_cObject);

    rb_include_module(rb_cHash, rb_mEnumerable);

    rb_define_alloc_func(rb_cHash, hash_alloc);
    rb_define_singleton_method(rb_cHash, "[]", rb_hash_s_create, -1);
    rb_define_method(rb_cHash,"initialize", rb_hash_initialize, -1);
    rb_define_method(rb_cHash,"initialize_copy", rb_hash_replace, 1);
    rb_define_method(rb_cHash,"rehash", rb_hash_rehash, 0);

    rb_define_method(rb_cHash,"to_hash", rb_hash_to_hash, 0);
    rb_define_method(rb_cHash,"to_a", rb_hash_to_a, 0);
    rb_define_method(rb_cHash,"to_s", rb_hash_to_s, 0);
    rb_define_method(rb_cHash,"inspect", rb_hash_inspect, 0);

    rb_define_method(rb_cHash,"==", rb_hash_equal, 1);
    rb_define_method(rb_cHash,"[]", rb_hash_aref, 1);
    rb_define_method(rb_cHash,"hash", rb_hash_hash, 0);
    rb_define_method(rb_cHash,"eql?", rb_hash_eql, 1);
    rb_define_method(rb_cHash,"fetch", rb_hash_fetch, -1);
    rb_define_method(rb_cHash,"[]=", rb_hash_aset, 2);
    rb_define_method(rb_cHash,"store", rb_hash_aset, 2);
    rb_define_method(rb_cHash,"default", rb_hash_default, -1);
    rb_define_method(rb_cHash,"default=", rb_hash_set_default, 1);
    rb_define_method(rb_cHash,"default_proc", rb_hash_default_proc, 0);
    rb_define_method(rb_cHash,"index", rb_hash_index, 1);
    rb_define_method(rb_cHash,"indexes", rb_hash_indexes, -1);
    rb_define_method(rb_cHash,"indices", rb_hash_indexes, -1);
    rb_define_method(rb_cHash,"size", rb_hash_size, 0);
    rb_define_method(rb_cHash,"length", rb_hash_size, 0);
    rb_define_method(rb_cHash,"empty?", rb_hash_empty_p, 0);

    rb_define_method(rb_cHash,"each", rb_hash_each, 0);
    rb_define_method(rb_cHash,"each_value", rb_hash_each_value, 0);
    rb_define_method(rb_cHash,"each_key", rb_hash_each_key, 0);
    rb_define_method(rb_cHash,"each_pair", rb_hash_each_pair, 0);
    rb_define_method(rb_cHash,"sort", rb_hash_sort, 0);

    rb_define_method(rb_cHash,"keys", rb_hash_keys, 0);
    rb_define_method(rb_cHash,"values", rb_hash_values, 0);
    rb_define_method(rb_cHash,"values_at", rb_hash_values_at, -1);

    rb_define_method(rb_cHash,"shift", rb_hash_shift, 0);
    rb_define_method(rb_cHash,"delete", rb_hash_delete, 1);
    rb_define_method(rb_cHash,"delete_if", rb_hash_delete_if, 0);
    rb_define_method(rb_cHash,"select", rb_hash_select, 0);
    rb_define_method(rb_cHash,"reject", rb_hash_reject, 0);
    rb_define_method(rb_cHash,"reject!", rb_hash_reject_bang, 0);
    rb_define_method(rb_cHash,"clear", rb_hash_clear, 0);
    rb_define_method(rb_cHash,"invert", rb_hash_invert, 0);
    rb_define_method(rb_cHash,"update", rb_hash_update, 1);
    rb_define_method(rb_cHash,"replace", rb_hash_replace, 1);
    rb_define_method(rb_cHash,"merge!", rb_hash_update, 1);
    rb_define_method(rb_cHash,"merge", rb_hash_merge, 1);

    rb_define_method(rb_cHash,"include?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash,"member?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash,"has_key?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash,"has_value?", rb_hash_has_value, 1);
    rb_define_method(rb_cHash,"key?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash,"value?", rb_hash_has_value, 1);

#ifndef __MACOS__ /* environment variables nothing on MacOS. */
    origenviron = environ;
    envtbl = rb_obj_alloc(rb_cObject);
    rb_extend_object(envtbl, rb_mEnumerable);

    rb_define_singleton_method(envtbl,"[]", rb_f_getenv, 1);
    rb_define_singleton_method(envtbl,"fetch", env_fetch, -1);
    rb_define_singleton_method(envtbl,"[]=", env_aset, 2);
    rb_define_singleton_method(envtbl,"store", env_aset, 2);
    rb_define_singleton_method(envtbl,"each", env_each, 0);
    rb_define_singleton_method(envtbl,"each_pair", env_each_pair, 0);
    rb_define_singleton_method(envtbl,"each_key", env_each_key, 0);
    rb_define_singleton_method(envtbl,"each_value", env_each_value, 0);
    rb_define_singleton_method(envtbl,"delete", env_delete_m, 1);
    rb_define_singleton_method(envtbl,"delete_if", env_delete_if, 0);
    rb_define_singleton_method(envtbl,"clear", env_clear, 0);
    rb_define_singleton_method(envtbl,"reject", env_reject, 0);
    rb_define_singleton_method(envtbl,"reject!", env_reject_bang, 0);
    rb_define_singleton_method(envtbl,"select", env_select, 0);
    rb_define_singleton_method(envtbl,"shift", env_shift, 0);
    rb_define_singleton_method(envtbl,"invert", env_invert, 0);
    rb_define_singleton_method(envtbl,"replace", env_replace, 1);
    rb_define_singleton_method(envtbl,"update", env_update, 1);
    rb_define_singleton_method(envtbl,"inspect", env_inspect, 0);
    rb_define_singleton_method(envtbl,"rehash", env_none, 0);
    rb_define_singleton_method(envtbl,"to_a", env_to_a, 0);
    rb_define_singleton_method(envtbl,"to_s", env_to_s, 0);
    rb_define_singleton_method(envtbl,"index", env_index, 1);
    rb_define_singleton_method(envtbl,"indexes", env_indexes, -1);
    rb_define_singleton_method(envtbl,"indices", env_indexes, -1);
    rb_define_singleton_method(envtbl,"size", env_size, 0);
    rb_define_singleton_method(envtbl,"length", env_size, 0);
    rb_define_singleton_method(envtbl,"empty?", env_empty_p, 0);
    rb_define_singleton_method(envtbl,"keys", env_keys, 0);
    rb_define_singleton_method(envtbl,"values", env_values, 0);
    rb_define_singleton_method(envtbl,"values_at", env_values_at, -1);
    rb_define_singleton_method(envtbl,"include?", env_has_key, 1);
    rb_define_singleton_method(envtbl,"member?", env_has_key, 1);
    rb_define_singleton_method(envtbl,"has_key?", env_has_key, 1);
    rb_define_singleton_method(envtbl,"has_value?", env_has_value, 1);
    rb_define_singleton_method(envtbl,"key?", env_has_key, 1);
    rb_define_singleton_method(envtbl,"value?", env_has_value, 1);
    rb_define_singleton_method(envtbl,"to_hash", env_to_hash, 0);

    rb_define_global_const("ENV", envtbl);
#else /* __MACOS__ */
	envtbl = rb_hash_s_new(0, NULL, rb_cHash);
    rb_define_global_const("ENV", envtbl);
#endif  /* ifndef __MACOS__  environment variables nothing on MacOS. */
}
