/************************************************

  hash.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:26 $
  created at: Mon Nov 22 18:51:18 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "st.h"

#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#else
char *getenv();
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strchr();
#endif

VALUE C_Hash;

static VALUE envtbl;
static ID hash;
VALUE Fgetenv(), Fsetenv();

static VALUE
rb_cmp(a, b)
    VALUE a, b;
{
    return rb_equal(a, b)?0:1;
}

static VALUE
rb_hash(a, mod)
    VALUE a;
    int mod;
{
    return rb_funcall(a, hash, 0) % mod;
}

#define ASSOC_KEY(a) RASSOC(a)->car
#define ASSOC_VAL(a) RASSOC(a)->cdr

static VALUE
Shash_new(class)
    VALUE class;
{
    NEWOBJ(hash, struct RHash);
    OBJSETUP(hash, class, T_HASH);

    hash->tbl = st_init_table(rb_cmp, rb_hash);

    return (VALUE)hash;
}

static VALUE Fhash_clone();

static VALUE
Shash_create(argc, argv, class)
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
	Fail("odd number args for Hash");
    }
    hash = (struct RHash*)Shash_new(class);

    for (i=0; i<argc; i+=2) {
	st_insert(hash->tbl, argv[i], argv[i+1]);
    }

    return (VALUE)hash;
}

VALUE
hash_new()
{
    return Shash_new(C_Hash);
}

static VALUE
Fhash_clone(hash)
    struct RHash *hash;
{
    NEWOBJ(hash2, struct RHash);
    CLONESETUP(hash2, hash);

    hash2->tbl = (st_table*)st_copy(hash->tbl);

    return (VALUE)hash2;
}

static VALUE
Fhash_aref(hash, key)
    struct RHash *hash;
    VALUE key;
{
    VALUE val = Qnil;

    if (!st_lookup(hash->tbl, key, &val)) {
	return Qnil;
    }
    return val;
}

static VALUE
Fhash_indexes(hash, args)
    struct RHash *hash;
    struct RArray *args;
{
    VALUE *p, *pend;
    struct RArray *new_hash;
    int i = 0;

    if (!args || args->len == 0) {
	Fail("wrong # of argment");
    }
    else if (args->len == 1) {
	if (TYPE(args->ptr[0])) {
	    args = (struct RArray*)rb_to_a(args->ptr[0]);
	}
	else {
	    args = (struct RArray*)args->ptr[0];
	}
    }

    new_hash = (struct RArray*)ary_new2(args->len);

    p = args->ptr; pend = p + args->len;
    while (p < pend) {
	new_hash->ptr[i++] = Fhash_aref(hash, *p++);
    }
    new_hash->len = i;
    return (VALUE)new_hash;
}

static VALUE
Fhash_delete(hash, key)
    struct RHash *hash;
    VALUE key;
{
    VALUE val;

    if (st_delete(hash->tbl, &key, &val))
	return val;
    return Qnil;
}

struct shift_var {
    int stop;
    VALUE key;
    VALUE val;
};

static
hash_shift(key, value, var)
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
Fhash_shift(hash)
    struct RHash *hash;
{
    struct shift_var var;

    var.stop = 0;
    st_foreach(hash->tbl, hash_shift, &var);

    if (var.stop == 0) return Qnil;
    return assoc_new(var.key, var.val);
}

static int
hash_delete_if(key, value)
    VALUE key, value;
{
    if (rb_yield(assoc_new(key, value)))
	return ST_DELETE;
    return ST_CONTINUE;
}

static VALUE
Fhash_delete_if(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, hash_delete_if, Qnil);

    return (VALUE)hash;
}

static
hash_clear(key, value)
    VALUE key, value;
{
    return ST_DELETE;
}

static VALUE
Fhash_clear(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, hash_clear);

    return (VALUE)hash;
}

VALUE
Fhash_aset(hash, key, val)
    struct RHash *hash;
    VALUE key, val;
{
    if (val == Qnil) {
	Fhash_delete(hash, key);
	return Qnil;
    }
    st_insert(hash->tbl, key, val);
    return val;
}

static VALUE
Fhash_length(hash)
    struct RHash *hash;
{
    return INT2FIX(hash->tbl->num_entries);
}

static
hash_each_value(key, value)
    VALUE key, value;
{
    rb_yield(value);
    return ST_CONTINUE;
}

static VALUE
Fhash_each_value(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, hash_each_value);
    return (VALUE)hash;
}

static
hash_each_key(key, value)
    VALUE key, value;
{
    rb_yield(key);
    return ST_CONTINUE;
}

static VALUE
Fhash_each_key(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, hash_each_key);
    return (VALUE)hash;
}

static
hash_each_pair(key, value)
    VALUE key, value;
{
    rb_yield(assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
Fhash_each_pair(hash)
    struct RHash *hash;
{
    st_foreach(hash->tbl, hash_each_pair);
    return (VALUE)hash;
}

static
hash_to_a(key, value, ary)
    VALUE key, value, ary;
{
    ary_push(ary, assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
Fhash_to_a(hash)
    struct RHash *hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(hash->tbl, hash_to_a, ary);

    return ary;
}

static
hash_inspect(key, value, str)
    VALUE key, value;
    struct RString *str;
{
    VALUE str2;
    ID inspect = rb_intern("_inspect");

    if (str->len > 1) {
	str_cat(str, ", ", 2);
    }
    str2 = rb_funcall(key, inspect, 0, Qnil);
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    str_cat(str, "=>", 2);
    str2 = rb_funcall(value, inspect, 0, Qnil);
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return ST_CONTINUE;
}

static VALUE
Fhash_inspect(hash)
    struct RHash *hash;
{
    VALUE str;

    str = str_new2("{");
    st_foreach(hash->tbl, hash_inspect, str);
    str_cat(str, "}", 1);

    return str;
}

static VALUE
Fhash_to_s(hash)
    VALUE hash;
{
    return Fary_to_s(Fhash_to_a(hash));
}

static
hash_keys(key, value, ary)
    VALUE key, value, ary;
{
    ary_push(ary, key);
    return ST_CONTINUE;
}

static VALUE
Fhash_keys(hash)
    struct RHash *hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(hash->tbl, hash_keys, ary);

    return ary;
}

static
hash_values(key, value, ary)
    VALUE key, value, ary;
{
    ary_push(ary, key);
    return ST_CONTINUE;
}

static VALUE
Fhash_values(hash)
    struct RHash *hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(hash->tbl, hash_values, ary);

    return ary;
}

static VALUE
Fhash_has_key(hash, key)
    struct RHash *hash;
    VALUE key;
{
    VALUE val;

    if (st_lookup(hash->tbl, key, &val))
	return TRUE;
    return FALSE;
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
Fhash_has_value(hash, val)
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
hash_equal(key, val1, data)
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
Fhash_equal(hash1, hash2)
    struct RHash *hash1, *hash2;
{
    struct equal_data data;

    if (TYPE(hash2) != T_HASH) return FALSE;
    if (hash1->tbl->num_entries != hash2->tbl->num_entries)
	return FALSE;

    data.tbl = hash2->tbl;
    data.result = TRUE;
    st_foreach(hash1->tbl, hash_equal, &data);

    return data.result;
}

static int
hash_hash(key, val, data)
    VALUE key, val;
    int *data;
{
    *data ^= rb_funcall(key, hash, 0);
    *data ^= rb_funcall(val, hash, 0);
    return ST_CONTINUE;
}

static VALUE
Fhash_hash(hash)
    struct RHash *hash;
{
    int h;

    st_foreach(hash->tbl, hash_hash, &h);
    return INT2FIX(h);
}

extern VALUE rb_readonly_hook();

extern char **environ;

static VALUE
Fenv_each(hash)
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
Fenv_delete(obj, name)
    VALUE obj;
    struct RString *name;
{
    int i, len;
    char *nam, *val = Qnil;

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
Fgetenv(obj, name)
    VALUE obj;
    struct RString *name;
{
    char *env;

    Check_Type(name, T_STRING);

    if (strlen(name->ptr) != name->len)
	Fail("Bad environment name");

    env = getenv(name->ptr);
    if (env) {
	return str_new2(env);
    }
    return Qnil;
}

VALUE
Fsetenv(obj, name, value)
    VALUE obj;
    struct RString *name, *value;
{
    Check_Type(name, T_STRING);
    if (value == Qnil) {
	Fenv_delete(obj, name);
	return Qnil;
    }

    Check_Type(value, T_STRING);

    if (strlen(name->ptr) != name->len)
	Fail("Bad environment name");
    if (strlen(value->ptr) != value->len)
	Fail("Bad environment value");

#ifdef HAVE_SETENV
    if (setenv(name->ptr, value->ptr, 1) == 0) return TRUE;
#else
#ifdef HAVE_PUTENV
    {
	char *str;
	int len;

	str = ALLOC_N(char, name->len + value->len + 2);
	sprintf("%s=%s", name->ptr, value->ptr);
	if (putenv(str) == 0) return TRUE;
    }
#else
    Fail("setenv is not supported on this system");
#endif
#endif

    Fail("setenv failed");
    return FALSE;		/* not reached */
}

static VALUE
Fenv_to_s()
{
    return str_new2("$ENV");
}

Init_Hash()
{
    extern VALUE C_Kernel;
    extern VALUE M_Enumerable;

    hash = rb_intern("hash");

    C_Hash = rb_define_class("Hash", C_Object);

    rb_include_module(C_Hash, M_Enumerable);

    rb_define_single_method(C_Hash, "new", Shash_new, 0);
    rb_define_single_method(C_Hash, "[]", Shash_create, -1);

    rb_define_method(C_Hash,"clone",  Fhash_clone, 0);

    rb_define_method(C_Hash,"to_a",  Fhash_to_a, 0);
    rb_define_method(C_Hash,"to_s",  Fhash_to_s, 0);
    rb_define_method(C_Hash,"_inspect",  Fhash_inspect, 0);

    rb_define_method(C_Hash,"==",  Fhash_equal, 1);
    rb_define_method(C_Hash,"hash",  Fhash_hash, 0);
    rb_define_method(C_Hash,"[]",  Fhash_aref, 1);
    rb_define_method(C_Hash,"[]=", Fhash_aset, 2);
    rb_define_method(C_Hash,"indexes",  Fhash_indexes, -2);
    rb_define_method(C_Hash,"length", Fhash_length, 0);
    rb_define_alias(C_Hash,  "size", "length");
    rb_define_method(C_Hash,"each", Fhash_each_pair, 0);
    rb_define_method(C_Hash,"each_value", Fhash_each_value, 0);
    rb_define_method(C_Hash,"each_key", Fhash_each_key, 0);
    rb_define_method(C_Hash,"each_pair", Fhash_each_pair, 0);

    rb_define_method(C_Hash,"keys", Fhash_keys, 0);
    rb_define_method(C_Hash,"values", Fhash_values, 0);

    rb_define_method(C_Hash,"shift", Fhash_shift, 0);
    rb_define_method(C_Hash,"delete", Fhash_delete, 1);
    rb_define_method(C_Hash,"delete_if", Fhash_delete_if, 0);
    rb_define_method(C_Hash,"clear", Fhash_clear, 0);

    rb_define_method(C_Hash,"includes", Fhash_has_key, 1);
    rb_define_method(C_Hash,"has_key", Fhash_has_key, 1);
    rb_define_method(C_Hash,"has_value", Fhash_has_value, 1);

    envtbl = obj_alloc(C_Object);
    rb_extend_object(envtbl, M_Enumerable);

    rb_define_single_method(envtbl,"[]", Fgetenv, 1);
    rb_define_single_method(envtbl,"[]=", Fsetenv, 2);
    rb_define_single_method(envtbl,"each", Fenv_each, 0);
    rb_define_single_method(envtbl,"delete", Fenv_delete, 1);
    rb_define_single_method(envtbl,"to_s", Fenv_to_s, 0);

    rb_define_variable("$ENV", &envtbl, Qnil, rb_readonly_hook, 0);
    rb_define_const(C_Kernel, "ENV", envtbl);
}
