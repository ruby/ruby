/************************************************

  hash.c -

  $Author: matz $
  $Date: 1996/12/25 10:42:26 $
  created at: Mon Nov 22 18:51:18 JST 1993

  Copyright (C) 1993-1997 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "st.h"
#include "sig.h"

#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strchr();
#endif

#define HASH_DELETED  0x1
#define HASH_REHASHED 0x2

#ifndef NT
char *getenv();
#endif

VALUE cHash;

static VALUE envtbl;
static ID hash;

VALUE
rb_hash(obj)
    VALUE obj;
{
    return rb_funcall(obj, hash, 0);
}

static int
any_cmp(a, b)
    VALUE a, b;
{
    if (FIXNUM_P(a)) {
	if (FIXNUM_P(b)) return a != b;
    }
    else if (TYPE(a) == T_STRING) {
	if (TYPE(b) == T_STRING) return str_cmp(a, b);
    }

    DEFER_INTS;
    a = !rb_eql(a, b);
    ENABLE_INTS;
    return a;
}

static int
any_hash(a, mod)
    VALUE a;
    int mod;
{
    unsigned int hval;

    switch (TYPE(a)) {
      case T_FIXNUM:
	hval = a;
	break;

      case T_STRING:
	hval = str_hash(a);
	break;

      default:
	DEFER_INTS;
	hval = rb_funcall(a, hash, 0);
	if (!FIXNUM_P(hval)) {
	    hval = rb_funcall(hval, '%', 1, INT2FIX(65439));
	}
	ENABLE_INTS;
	hval = FIX2INT(hval);
    }
    return  hval % mod;
}

static struct st_hash_type objhash = {
    any_cmp,
    any_hash,
};

struct hash_foreach_arg {
    struct RHash *hash;
    enum st_retval (*func)();
    char *arg;
};

static int
hash_foreach_iter(key, value, arg)
    VALUE key, value;
    struct hash_foreach_arg *arg;
{
    int status;

    if (key == Qnil) return ST_CONTINUE;
    status = (*arg->func)(key, value, arg->arg);
    if (arg->hash->status & HASH_REHASHED) return ST_STOP;
    return status;
}

static VALUE
hash_foreach_call(arg)
    struct hash_foreach_arg *arg;
{
    st_foreach(arg->hash->tbl, hash_foreach_iter, arg);
    return Qnil;
}

static int
hash_delete_nil(key, value)
    VALUE key, value;
{
    if (key == Qnil) return ST_DELETE;
    return ST_CONTINUE;
}

static void
hash_foreach_ensure(hash)
    struct RHash *hash;
{
    hash->iter_lev--;

    if (hash->iter_lev == 0) {
	if (hash->status & HASH_DELETED) {
	    st_foreach(hash->tbl, hash_delete_nil, 0);
	}
	hash->status = 0;
    }
}

static int
hash_foreach(hash, func, farg)
    struct RHash *hash;
    enum st_retval (*func)();
    char *farg;
{
    struct hash_foreach_arg arg;

    hash->iter_lev++;
    arg.hash = hash;
    arg.func = func;
    arg.arg  = farg;
    return rb_ensure(hash_foreach_call, &arg, hash_foreach_ensure, hash);
}

static VALUE
hash_s_new(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE sz;
    int size;

    NEWOBJ(hash, struct RHash);
    OBJSETUP(hash, class, T_HASH);

    rb_scan_args(argc, argv, "01", &sz);
    if (NIL_P(sz)) size = 0;
    else size = NUM2INT(sz);

    hash->iter_lev = 0;
    hash->status = 0;
    hash->tbl = 0;		/* avoid GC crashing  */
    hash->tbl = st_init_table_with_size(&objhash, size);

    return (VALUE)hash;
}

VALUE
hash_new2(class)
    VALUE class;
{
    return hash_s_new(0, 0, class);
}

VALUE
hash_new()
{
    return hash_new2(cHash);
}

static VALUE
hash_s_create(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    struct RHash *hash;
    int i;

    if (argc == 1 && TYPE(argv[0]) == T_HASH) {
	if (class == CLASS_OF(argv[0])) return argv[0];
	else {
	    NEWOBJ(hash, struct RHash);
	    OBJSETUP(hash, class, T_HASH);
	    
	    hash->iter_lev = 0;
	    hash->status = 0;
	    hash->tbl = 0;	/* avoid GC crashing  */
	    hash->tbl = (st_table*)st_copy(RHASH(argv[0])->tbl);
	    return (VALUE)hash;
	}
    }

    if (argc % 2 != 0) {
	ArgError("odd number args for Hash");
    }
    hash = (struct RHash*)hash_new2(class);

    for (i=0; i<argc; i+=2) {
	st_insert(hash->tbl, argv[i], argv[i+1]);
    }

    return (VALUE)hash;
}

static VALUE
hash_clone(hash)
    struct RHash *hash;
{
    NEWOBJ(hash2, struct RHash);
    CLONESETUP(hash2, hash);

    hash2->iter_lev = 0;
    hash2->status = 0;
    hash2->tbl = 0;		/* avoid GC crashing  */
    hash2->tbl = (st_table*)st_copy(hash->tbl);

    return (VALUE)hash2;
}

static int
hash_rehash_i(key, value, tbl)
    VALUE key, value;
    st_table *tbl;
{
    if (key != Qnil) {
	st_insert(tbl, key, value);
    }
    return ST_CONTINUE;
}

static VALUE
hash_rehash(hash)
    struct RHash *hash;
{
    st_table *tbl = st_init_table_with_size(&objhash, hash->tbl->num_entries);

    st_foreach(hash->tbl, hash_rehash_i, tbl);
    st_free_table(hash->tbl);
    hash->tbl = tbl;
    if (hash->iter_lev > 0) hash->status |= HASH_REHASHED;

    return (VALUE)hash;
}

VALUE
hash_aref(hash, key)
    struct RHash *hash;
    VALUE key;
{
    VALUE val;

    if (!st_lookup(hash->tbl, key, &val)) {
	return Qnil;
    }
    return val;
}

static VALUE
hash_indexes(argc, argv, hash)
    int argc;
    VALUE *argv;
    struct RHash *hash;
{
    struct RArray *indexes;
    int i;

    indexes = (struct RArray*)ary_new2(argc);
    for (i=0; i<argc; i++) {
	indexes->ptr[i] = hash_aref(hash, argv[i]);
    }
    indexes->len = i;
    return (VALUE)indexes;
}

static VALUE
hash_delete(hash, key)
    struct RHash *hash;
    VALUE key;
{
    VALUE val;

    rb_secure(5);
    if (hash->iter_lev > 0 && st_delete_safe(hash->tbl, &key, &val, Qnil))
	return val;
    else if (st_delete(hash->tbl, &key, &val))
	return val;
    if (iterator_p()) rb_yield(key);
    return Qnil;
}

struct shift_var {
    int stop;
    VALUE key;
    VALUE val;
};

static int
shift_i(key, value, var)
    VALUE key, value;
    struct shift_var *var;
{
    if (key == Qnil) return ST_CONTINUE;
    if (var->stop) return ST_STOP;
    var->stop = 1;
    var->key = key;
    var->val = value;
    return ST_DELETE;
}

static VALUE
hash_shift(hash)
    struct RHash *hash;
{
    struct shift_var var;

    rb_secure(5);
    var.stop = 0;
    st_foreach(hash->tbl, shift_i, &var);

    if (var.stop == 0) return Qnil;
    return assoc_new(var.key, var.val);
}

static int
delete_if_i(key, value)
    VALUE key, value;
{
    if (key == Qnil) return ST_CONTINUE;
    if (rb_yield(assoc_new(key, value)))
	return ST_DELETE;
    return ST_CONTINUE;
}

static VALUE
hash_delete_if(hash)
    struct RHash *hash;
{
    rb_secure(5);
    hash_foreach(hash, delete_if_i, 0);

    return (VALUE)hash;
}

static int
clear_i(key, value)
    VALUE key, value;
{
    return ST_DELETE;
}

static VALUE
hash_clear(hash)
    struct RHash *hash;
{
    rb_secure(5);
    st_foreach(hash->tbl, clear_i);

    return (VALUE)hash;
}

VALUE
hash_aset(hash, key, val)
    struct RHash *hash;
    VALUE key, val;
{
    rb_secure(5);
    if (NIL_P(val)) {
	hash_delete(hash, key);
	return Qnil;
    }
    if (TYPE(key) == T_STRING) {
	key = str_dup_freezed(key);
    }
    st_insert(hash->tbl, key, val);
    return val;
}

static VALUE
hash_length(hash)
    struct RHash *hash;
{
    return INT2FIX(hash->tbl->num_entries);
}

VALUE
hash_empty_p(hash)
    struct RHash *hash;
{
    if (hash->tbl->num_entries == 0)
	return TRUE;
    return FALSE;
}

static int
each_value_i(key, value)
    VALUE key, value;
{
    if (key == Qnil) return ST_CONTINUE;
    rb_yield(value);
    return ST_CONTINUE;
}

static VALUE
hash_each_value(hash)
    struct RHash *hash;
{
    hash_foreach(hash, each_value_i);
    return (VALUE)hash;
}

static int
each_key_i(key, value)
    VALUE key, value;
{
    if (key == Qnil) return ST_CONTINUE;
    rb_yield(key);
    return ST_CONTINUE;
}

static VALUE
hash_each_key(hash)
    struct RHash *hash;
{
    hash_foreach(hash, each_key_i);
    return (VALUE)hash;
}

static int
each_pair_i(key, value)
    VALUE key, value;
{
    if (key == Qnil) return ST_CONTINUE;
    rb_yield(assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
hash_each_pair(hash)
    struct RHash *hash;
{
    hash_foreach(hash, each_pair_i);
    return (VALUE)hash;
}

static int
to_a_i(key, value, ary)
    VALUE key, value, ary;
{
    if (key == Qnil) return ST_CONTINUE;
    ary_push(ary, assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
hash_to_a(hash)
    struct RHash *hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(hash->tbl, to_a_i, ary);

    return ary;
}

static int
inspect_i(key, value, str)
    VALUE key, value;
    struct RString *str;
{
    VALUE str2;

    if (key == Qnil) return ST_CONTINUE;
    if (str->len > 1) {
	str_cat(str, ", ", 2);
    }
    str2 = rb_inspect(key);
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    str_cat(str, "=>", 2);
    str2 = rb_inspect(value);
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return ST_CONTINUE;
}

static VALUE
hash_inspect(hash)
    struct RHash *hash;
{
    VALUE str;

    str = str_new2("{");
    st_foreach(hash->tbl, inspect_i, str);
    str_cat(str, "}", 1);

    return str;
}

static VALUE
hash_to_s(hash)
    VALUE hash;
{
    return ary_to_s(hash_to_a(hash));
}

static int
keys_i(key, value, ary)
    VALUE key, value, ary;
{
    if (key == Qnil) return ST_CONTINUE;
    ary_push(ary, key);
    return ST_CONTINUE;
}

static VALUE
hash_keys(hash)
    struct RHash *hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(hash->tbl, keys_i, ary);

    return ary;
}

static int
values_i(key, value, ary)
    VALUE key, value, ary;
{
    if (key == Qnil) return ST_CONTINUE;
    ary_push(ary, value);
    return ST_CONTINUE;
}

static VALUE
hash_values(hash)
    struct RHash *hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(hash->tbl, values_i, ary);

    return ary;
}

static VALUE
hash_has_key(hash, key)
    struct RHash *hash;
    VALUE key;
{
    if (st_lookup(hash->tbl, key, 0)) {
	return TRUE;
    }
    return FALSE;
}

static int
hash_search_value(key, value, data)
    VALUE key, value, *data;
{
    if (key == Qnil) return ST_CONTINUE;
    if (rb_equal(value, data[1])) {
	data[0] = TRUE;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

static VALUE
hash_has_value(hash, val)
    struct RHash *hash;
    VALUE val;
{
    VALUE data[2];

    data[0] = FALSE;
    data[1] = val;
    st_foreach(hash->tbl, hash_search_value, data);
    return data[0];
}

struct equal_data {
    int result;
    st_table *tbl;
};

static int
equal_i(key, val1, data)
    VALUE key, val1;
    struct equal_data *data;
{
    VALUE val2;

    if (key == Qnil) return ST_CONTINUE;
    if (!st_lookup(data->tbl, key, &val2)) {
	data->result = FALSE;
	return ST_STOP;
    }
    if (!rb_equal(val1, val2)) {
	data->result = FALSE;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

static VALUE
hash_equal(hash1, hash2)
    struct RHash *hash1, *hash2;
{
    struct equal_data data;

    if (TYPE(hash2) != T_HASH) return FALSE;
    if (hash1->tbl->num_entries != hash2->tbl->num_entries)
	return FALSE;

    data.tbl = hash2->tbl;
    data.result = TRUE;
    st_foreach(hash1->tbl, equal_i, &data);

    return data.result;
}

static int
hash_invert_i(key, value, hash)
    VALUE key, value;
    struct RHash *hash;
{
    if (key == Qnil) return ST_CONTINUE;
    hash_aset(hash, value, key);
    return ST_CONTINUE;
}

static VALUE
hash_invert(hash)
    struct RHash *hash;
{
    VALUE h = hash_new();

    st_foreach(hash->tbl, hash_invert_i, h);
    return h;
}

int env_path_tainted = 0;

#ifndef NT
extern char **environ;
#endif

static VALUE
env_delete(obj, name)
    VALUE obj;
    struct RString *name;
{
    int i, len;
    char *nam, *val = 0;

    rb_secure(4);
    Check_Type(name, T_STRING);
    nam = name->ptr;
    len = strlen(nam);
    if (strcmp(nam, "PATH") == 0) env_path_tainted = 0;
    for(i=0; environ[i]; i++) {
	if (strncmp(environ[i], nam, len) == 0 && environ[i][len] == '=') {
	    val = environ[i]+len+1;
	    break;
	}
    }
    while (environ[i]) {
	environ[i] = environ[i+1];
	i++;
    }
    if (val) {
	return str_new2(val);
    }
    return Qnil;
}

static VALUE
f_getenv(obj, name)
    VALUE obj;
    struct RString *name;
{
    char *env;

    Check_Type(name, T_STRING);

    if (strlen(name->ptr) != name->len)
	ArgError("Bad environment name");

    env = getenv(name->ptr);
    if (env) {
	if (strcmp(name->ptr, "PATH") == 0 && !env_path_tainted)
	    return str_new2(env);
	return str_taint(str_new2(env));
    }
    return Qnil;
}

static VALUE
f_setenv(obj, name, value)
    VALUE obj;
    struct RString *name, *value;
{
    if (rb_safe_level() >= 4) {
	extern VALUE eSecurityError;
	Raise(eSecurityError, "cannot change environment variable");
    }

    Check_SafeStr(name);
    if (NIL_P(value)) {
	env_delete(obj, name);
	return Qnil;
    }

    Check_SafeStr(value);
    if (strlen(name->ptr) != name->len)
	ArgError("Bad environment name");
    if (strlen(value->ptr) != value->len)
	ArgError("Bad environment value");

    setenv(name->ptr, value->ptr, 1);
    if (strcmp(name->ptr, "PATH") == 0) env_path_tainted = 0;
    return TRUE;
}

static VALUE
env_keys()
{
    char **env;
    VALUE ary = ary_new();

    env = environ;
    while (*env) {
	char *s = strchr(*env, '=');
	ary_push(ary, str_taint(str_new(*env, s-*env)));
	env++;
    }
    return ary;
}

static VALUE
env_each_key(hash)
    VALUE hash;
{
    return ary_each(env_keys());
}

static VALUE
env_values()
{
    char **env;
    VALUE ary = ary_new();

    env = environ;
    while (*env) {
	char *s = strchr(*env, '=');
	ary_push(ary, str_taint(str_new2(s+1)));
	env++;
    }
    return ary;
}

static VALUE
env_each_value(hash)
    VALUE hash;
{
    return ary_each(env_values());
}

static VALUE
env_each(hash)
    VALUE hash;
{
    VALUE ary = env_keys();
    VALUE *ptr = RARRAY(ary)->ptr;
    int len = RARRAY(ary)->len; 

    while (len--) {
	VALUE val = f_getenv(Qnil, *ptr);
	if (!NIL_P(val)) {
	    rb_yield(assoc_new(*ptr, val));
	}
	ptr++;
    }
    return hash;
}

static VALUE
env_delete_if()
{
    VALUE ary = env_keys();
    VALUE *ptr = RARRAY(ary)->ptr;
    int len = RARRAY(ary)->len; 

    while (len--) {
	VALUE val = f_getenv(Qnil, *ptr);
	if (!NIL_P(val)) {
	    if (RTEST(rb_yield(assoc_new(*ptr, val)))) {
		env_delete(Qnil, *ptr);
	    }
	}
	ptr++;
    }
    return envtbl;
}

static VALUE
env_to_s()
{
    return str_new2("ENV");
}

static VALUE
env_to_a()
{
    char **env;
    VALUE ary = ary_new();

    env = environ;
    while (*env) {
	char *s = strchr(*env, '=');
	ary_push(ary, assoc_new(str_taint(str_new(*env, s-*env)),
				str_taint(str_new2(s+1))));
	env++;
    }
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

    for(i=0; environ[i]; i++)
	;
    return INT2FIX(i);
}

static VALUE
env_empty_p()
{
    if (environ[0] == 0) return TRUE;
    return FALSE;
}

static VALUE
env_has_key(env, key)
    VALUE env, key;
{
    if (TYPE(key) != T_STRING) return FALSE;
    if (getenv(RSTRING(key)->ptr)) return TRUE;
    return FALSE;
}

static VALUE
env_has_value(dmy, value)
    VALUE dmy, value;
{
    char **env;
    VALUE ary;

    if (TYPE(value) != T_STRING) return FALSE;
    ary = ary_new();
    env = environ;
    while (*env) {
	char *s = strchr(*env, '=')+1;
	int len = strlen(s);
	if (strncmp(s, RSTRING(value)->ptr, len) == 0) return TRUE;
	env++;
    }
    return FALSE;
}

static VALUE
env_indexes(argc, argv)
    int argc;
    VALUE *argv;
{
    int i;
    VALUE indexes = ary_new2(argc);

    for (i=0;i<argc;i++) {
	char *v = 0;
	if (TYPE(argv[i]) == T_STRING) {
	    v = getenv(RSTRING(argv[i])->ptr);
	}
	if (v) {
	    RARRAY(indexes)->ptr[i] = str_new2(v);
	}
	else {
	    RARRAY(indexes)->ptr[i] = Qnil;
	}
	RARRAY(indexes)->len = i+1;
    }

    return indexes;
}

void
Init_Hash()
{
    extern VALUE mEnumerable;

    hash = rb_intern("hash");

    cHash = rb_define_class("Hash", cObject);

    rb_include_module(cHash, mEnumerable);

    rb_define_singleton_method(cHash, "new", hash_s_new, -1);
    rb_define_singleton_method(cHash, "[]", hash_s_create, -1);

    rb_define_method(cHash,"clone",  hash_clone, 0);
    rb_define_method(cHash,"rehash",  hash_rehash, 0);

    rb_define_method(cHash,"to_a",  hash_to_a, 0);
    rb_define_method(cHash,"to_s",  hash_to_s, 0);
    rb_define_method(cHash,"inspect",  hash_inspect, 0);

    rb_define_method(cHash,"==",  hash_equal, 1);
    rb_define_method(cHash,"[]",  hash_aref, 1);
    rb_define_method(cHash,"[]=", hash_aset, 2);
    rb_define_method(cHash,"indexes", hash_indexes, -1);
    rb_define_method(cHash,"length", hash_length, 0);
    rb_define_alias(cHash, "size", "length");
    rb_define_method(cHash,"empty?", hash_empty_p, 0);

    rb_define_method(cHash,"each", hash_each_pair, 0);
    rb_define_method(cHash,"each_value", hash_each_value, 0);
    rb_define_method(cHash,"each_key", hash_each_key, 0);
    rb_define_method(cHash,"each_pair", hash_each_pair, 0);

    rb_define_method(cHash,"keys", hash_keys, 0);
    rb_define_method(cHash,"values", hash_values, 0);

    rb_define_method(cHash,"shift", hash_shift, 0);
    rb_define_method(cHash,"delete", hash_delete, 1);
    rb_define_method(cHash,"delete_if", hash_delete_if, 0);
    rb_define_method(cHash,"clear", hash_clear, 0);
    rb_define_method(cHash,"invert", hash_invert, 0);

    rb_define_method(cHash,"include?", hash_has_key, 1);
    rb_define_method(cHash,"has_key?", hash_has_key, 1);
    rb_define_method(cHash,"has_value?", hash_has_value, 1);
    rb_define_method(cHash,"key?", hash_has_key, 1);
    rb_define_method(cHash,"value?", hash_has_value, 1);

    envtbl = obj_alloc(cObject);
    rb_extend_object(envtbl, mEnumerable);

    rb_define_singleton_method(envtbl,"[]", f_getenv, 1);
    rb_define_singleton_method(envtbl,"[]=", f_setenv, 2);
    rb_define_singleton_method(envtbl,"each", env_each, 0);
    rb_define_singleton_method(envtbl,"each_pair", env_each, 0);
    rb_define_singleton_method(envtbl,"each_key", env_each_key, 0);
    rb_define_singleton_method(envtbl,"each_value", env_each_value, 0);
    rb_define_singleton_method(envtbl,"delete", env_delete, 1);
    rb_define_singleton_method(envtbl,"delete_if", env_delete_if, 0);
    rb_define_singleton_method(envtbl,"to_s", env_to_s, 0);
    rb_define_singleton_method(envtbl,"rehash", env_none, 0);
    rb_define_singleton_method(envtbl,"to_a", env_to_a, 0);
    rb_define_singleton_method(envtbl,"indexes", env_indexes, -1);
    rb_define_singleton_method(envtbl,"length", env_size, 0);
    rb_define_singleton_method(envtbl,"empty?", env_empty_p, 0);
    rb_define_singleton_method(envtbl,"keys", env_keys, 0);
    rb_define_singleton_method(envtbl,"values", env_values, 0);
    rb_define_singleton_method(envtbl,"include?", env_has_key, 1);
    rb_define_singleton_method(envtbl,"has_key?", env_has_key, 1);
    rb_define_singleton_method(envtbl,"has_value?", env_has_value, 1);
    rb_define_singleton_method(envtbl,"key?", env_has_key, 1);
    rb_define_singleton_method(envtbl,"value?", env_has_value, 1);

    rb_define_global_const("ENV", envtbl);
}
