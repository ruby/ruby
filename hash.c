/************************************************

  hash.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:26 $
  created at: Mon Nov 22 18:51:18 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "st.h"

#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strchr();
#endif

char *getenv();

VALUE cHash;

static VALUE envtbl;
static ID hash;
VALUE f_getenv(), f_setenv();

static int
rb_cmp(a, b)
    VALUE a, b;
{
    if (FIXNUM_P(a)) {
	if (FIXNUM_P(b)) return a != b;
    }

    if (TYPE(a) == T_STRING) {
	if (TYPE(b) == T_STRING) return str_cmp(a, b);
    }

    return !rb_eql(a, b);
}

static int
rb_hash(a, mod)
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
	hval = rb_funcall(a, hash, 0);
	hval = FIX2INT(hval);
    }
    return  hval % mod;
}

static struct st_hash_type objhash = {
    rb_cmp,
    rb_hash,
};

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

    hash->tbl = st_init_table_with_size(&objhash, size);

    return (VALUE)hash;
}

static VALUE hash_clone();

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

    hash2->tbl = (st_table*)st_copy(hash->tbl);

    return (VALUE)hash2;
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
hash_indexes(hash, args)
    struct RHash *hash;
    struct RArray *args;
{
    VALUE *p, *pend;
    struct RArray *indexes;
    int i = 0;

    if (!args || NIL_P(args)) {
	return ary_new2(0);
    }

    indexes = (struct RArray*)ary_new2(args->len);

    p = args->ptr; pend = p + args->len;
    while (p < pend) {
	indexes->ptr[i++] = hash_aref(hash, *p++);
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

    if (st_delete(hash->tbl, &key, &val))
	return val;
    if (iterator_p()) rb_yield(Qnil);
    return Qnil;
}

struct shift_var {
    int stop;
    VALUE key;
    VALUE val;
};

static
shift_i(key, value, var)
    VALUE key, value;
    struct shift_var *var;
{
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

    var.stop = 0;
    st_foreach(hash->tbl, shift_i, &var);

    if (var.stop == 0) return Qnil;
    return assoc_new(var.key, var.val);
}

static int
delete_if_i(key, value)
    VALUE key, value;
{
    if (rb_yield(assoc_new(key, value)))
	return ST_DELETE;
    return ST_CONTINUE;
}

static VALUE
hash_delete_if(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, delete_if_i, 0);

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
    st_foreach(hash->tbl, clear_i);

    return (VALUE)hash;
}

VALUE
hash_aset(hash, key, val)
    struct RHash *hash;
    VALUE key, val;
{
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
    rb_yield(value);
    return ST_CONTINUE;
}

static VALUE
hash_each_value(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, each_value_i);
    return (VALUE)hash;
}

static int
each_key_i(key, value)
    VALUE key, value;
{
    rb_yield(key);
    return ST_CONTINUE;
}

static VALUE
hash_each_key(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, each_key_i);
    return (VALUE)hash;
}

static int
each_pair_i(key, value)
    VALUE key, value;
{
    rb_yield(assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
hash_each_pair(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, each_pair_i);
    return (VALUE)hash;
}

static int
to_a_i(key, value, ary)
    VALUE key, value, ary;
{
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

static int
hash_search_value(key, value, data)
    VALUE key, value, *data;
{
    if (rb_equal(value, data[1])) {
	data[0] = TRUE;
	return ST_STOP;
    }
    return ST_CONTINUE;
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
hash_i(key, val, data)
    VALUE key, val;
    int *data;
{
    *data ^= rb_funcall(key, hash, 0);
    *data ^= rb_funcall(val, hash, 0);
    return ST_CONTINUE;
}

static VALUE
hash_hash(hash)
    struct RHash *hash;
{
    int h;

    st_foreach(hash->tbl, hash_i, &h);
    return INT2FIX(h);
}

extern char **environ;

static VALUE
env_each(hash)
    VALUE hash;
{
    char **env;

    env = environ;
    while (*env) {
	VALUE var, val;
	char *s = strchr(*env, '=');

	var = str_new(*env, s-*env);
	val = str_new2(s+1);
	rb_yield(assoc_new(var, val));
	env++;
    }
    return hash;
}

static VALUE
env_delete(obj, name)
    VALUE obj;
    struct RString *name;
{
    int i, len;
    char *nam, *val = 0;

    Check_Type(name, T_STRING);
    nam = name->ptr;
    len = strlen(nam);
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

VALUE
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
	return str_new2(env);
    }
    return Qnil;
}

VALUE
f_setenv(obj, name, value)
    VALUE obj;
    struct RString *name, *value;
{
    Check_Type(name, T_STRING);
    if (NIL_P(value)) {
	env_delete(obj, name);
	return Qnil;
    }

    Check_Type(value, T_STRING);

    if (strlen(name->ptr) != name->len)
	ArgError("Bad environment name");
    if (strlen(value->ptr) != value->len)
	ArgError("Bad environment value");

    setenv(name->ptr, value->ptr, 1);
    return TRUE;
}

static VALUE
env_to_s()
{
    return str_new2("ENV");
}

void
Init_Hash()
{
    extern VALUE cKernel;
    extern VALUE mEnumerable;

    hash = rb_intern("hash");

    cHash = rb_define_class("Hash", cObject);

    rb_include_module(cHash, mEnumerable);

    rb_define_singleton_method(cHash, "new", hash_s_new, -1);
    rb_define_singleton_method(cHash, "[]", hash_s_create, -1);

    rb_define_method(cHash,"clone",  hash_clone, 0);

    rb_define_method(cHash,"to_a",  hash_to_a, 0);
    rb_define_method(cHash,"to_s",  hash_to_s, 0);
    rb_define_method(cHash,"inspect",  hash_inspect, 0);

    rb_define_method(cHash,"==",  hash_equal, 1);
    rb_define_method(cHash,"hash",  hash_hash, 0);
    rb_define_method(cHash,"[]",  hash_aref, 1);
    rb_define_method(cHash,"[]=", hash_aset, 2);
    rb_define_method(cHash,"indexes", hash_indexes, -2);
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
    rb_define_singleton_method(envtbl,"delete", env_delete, 1);
    rb_define_singleton_method(envtbl,"to_s", env_to_s, 0);

    rb_define_readonly_variable("$ENV", &envtbl);
    rb_define_global_const("ENV", envtbl);
}
