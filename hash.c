/************************************************

  hash.c -

  $Author$
  $Date$
  created at: Mon Nov 22 18:51:18 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "st.h"
#include "rubysig.h"

#include <sys/types.h>
#include <sys/stat.h>

#ifndef HAVE_STRING_H
char *strchr _((char*,char));
#endif

#define HASH_FREEZE   FL_USER1
#define HASH_DELETED  FL_USER2

static void
rb_hash_modify(hash)
    VALUE hash;
{
    if (FL_TEST(hash, HASH_FREEZE))
	rb_raise(rb_eTypeError, "can't modify frozen hash");
    if (rb_safe_level() >= 4 && !FL_TEST(hash, FL_TAINT))
	rb_raise(rb_eSecurityError, "Insecure: can't modify hash");
}

VALUE
rb_hash_freeze(hash)
    VALUE hash;
{
    FL_SET(hash, HASH_FREEZE);
    return hash;
}

static VALUE
rb_hash_frozen_p(hash)
    VALUE hash;
{
    if (FL_TEST(hash, HASH_FREEZE))
	return Qtrue;
    return Qfalse;
}

VALUE rb_cHash;

static VALUE envtbl;
static ID hash;

VALUE
rb_hash(obj)
    VALUE obj;
{
    return rb_funcall(obj, hash, 0);
}

static int
rb_any_cmp(a, b)
    VALUE a, b;
{
    if (FIXNUM_P(a)) {
	if (FIXNUM_P(b)) return a != b;
    }
    else if (TYPE(a) == T_STRING) {
	if (TYPE(b) == T_STRING) return rb_str_cmp(a, b);
    }

    DEFER_INTS;
    a = !rb_eql(a, b);
    ENABLE_INTS;
    return a;
}

static int
rb_any_hash(a)
    VALUE a;
{
    unsigned int hval;

    switch (TYPE(a)) {
      case T_FIXNUM:
	hval = a;
	break;

      case T_STRING:
	hval = rb_str_hash(a);
	break;

      default:
	DEFER_INTS;
	hval = rb_funcall(a, hash, 0);
	if (!FIXNUM_P(hval)) {
	    hval = rb_funcall(hval, '%', 1, INT2FIX(65439));
	}
	ENABLE_INTS;
	hval = FIX2LONG(hval);
    }
    return  hval;
}

static struct st_hash_type objhash = {
    rb_any_cmp,
    rb_any_hash,
};

struct rb_hash_foreach_arg {
    VALUE hash;
    enum st_retval (*func)();
    char *arg;
};

static int
rb_hash_foreach_iter(key, value, arg)
    VALUE key, value;
    struct rb_hash_foreach_arg *arg;
{
    int status;
    st_table *tbl = RHASH(arg->hash)->tbl;
    struct st_table_entry **bins = tbl->bins;

    if (key == Qnil) return ST_CONTINUE;
    status = (*arg->func)(key, value, arg->arg);
    if (RHASH(arg->hash)->tbl != tbl || RHASH(arg->hash)->tbl->bins != bins){
	rb_raise(rb_eIndexError, "rehash occurred during iteration");
    }
    return status;
}

static VALUE
rb_hash_foreach_call(arg)
    struct rb_hash_foreach_arg *arg;
{
    st_foreach(RHASH(arg->hash)->tbl, rb_hash_foreach_iter, arg);
    return Qnil;
}

static int
rb_hash_delete_nil(key, value)
    VALUE key, value;
{
    if (value == Qnil) return ST_DELETE;
    return ST_CONTINUE;
}

static VALUE
rb_hash_foreach_ensure(hash)
    VALUE hash;
{
    RHASH(hash)->iter_lev--;

    if (RHASH(hash)->iter_lev == 0) {
	if (FL_TEST(hash, HASH_DELETED)) {
	    st_foreach(RHASH(hash)->tbl, rb_hash_delete_nil, 0);
	    FL_UNSET(hash, HASH_DELETED);
	}
    }
    return 0;
}

static int
rb_hash_foreach(hash, func, farg)
    VALUE hash;
    enum st_retval (*func)();
    char *farg;
{
    struct rb_hash_foreach_arg arg;

    RHASH(hash)->iter_lev++;
    arg.hash = hash;
    arg.func = func;
    arg.arg  = farg;
    return rb_ensure(rb_hash_foreach_call, (VALUE)&arg, rb_hash_foreach_ensure, hash);
}

static VALUE
rb_hash_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE sz, ifnone;
    int size;

    NEWOBJ(hash, struct RHash);
    OBJSETUP(hash, klass, T_HASH);

    hash->iter_lev = 0;
    hash->ifnone = Qnil;
    hash->tbl = 0;		/* avoid GC crashing  */

    rb_scan_args(argc, argv, "02", &ifnone, &sz);
    if (NIL_P(sz)) {
	size = 0;
    }
    else size = NUM2INT(sz);

    hash->ifnone = ifnone;
    hash->tbl = st_init_table_with_size(&objhash, size);
    rb_obj_call_init((VALUE)hash);

    return (VALUE)hash;
}

static VALUE
rb_hash_new2(klass)
    VALUE klass;
{
    NEWOBJ(hash, struct RHash);
    OBJSETUP(hash, klass, T_HASH);

    hash->iter_lev = 0;
    hash->ifnone = Qnil;
    hash->tbl = 0;		/* avoid GC crashing  */
    hash->tbl = st_init_table(&objhash);

    return (VALUE)hash;
}

VALUE
rb_hash_new()
{
    return rb_hash_new2(rb_cHash);
}

static VALUE
rb_hash_s_create(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE hash;
    int i;

    if (argc == 1 && TYPE(argv[0]) == T_HASH) {
	if (klass == CLASS_OF(argv[0])) return argv[0];
	else {
	    NEWOBJ(hash, struct RHash);
	    OBJSETUP(hash, klass, T_HASH);
	    
	    hash->iter_lev = 0;
	    hash->ifnone = Qnil;
	    hash->tbl = 0;	/* avoid GC crashing  */
	    hash->tbl = (st_table*)st_copy(RHASH(argv[0])->tbl);
	    rb_obj_call_init((VALUE)hash);
	    return (VALUE)hash;
	}
    }

    if (argc % 2 != 0) {
	rb_raise(rb_eArgError, "odd number args for Hash");
    }
    hash = rb_hash_new2(klass);

    for (i=0; i<argc; i+=2) {
	st_insert(RHASH(hash)->tbl, argv[i], argv[i+1]);
    }
    rb_obj_call_init(hash);

    return hash;
}

static VALUE
rb_hash_clone(hash)
    VALUE hash;
{
    NEWOBJ(hash2, struct RHash);
    CLONESETUP(hash2, hash);

    hash2->iter_lev = 0;
    hash2->ifnone = RHASH(hash)->ifnone;
    hash2->tbl = 0;		/* avoid GC crashing  */
    hash2->tbl = (st_table*)st_copy(RHASH(hash)->tbl);

    return (VALUE)hash2;
}

static VALUE
rb_hash_dup(hash)
    VALUE hash;
{
    NEWOBJ(hash2, struct RHash);
    OBJSETUP(hash2, CLASS_OF(hash), T_HASH);

    hash2->iter_lev = 0;
    hash2->ifnone = RHASH(hash)->ifnone;
    hash2->tbl = 0;		/* avoid GC crashing  */
    hash2->tbl = (st_table*)st_copy(RHASH(hash)->tbl);

    return (VALUE)hash2;
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
    if (key != Qnil) {
	st_insert(tbl, key, value);
    }
    return ST_CONTINUE;
}

static VALUE
rb_hash_rehash(hash)
    VALUE hash;
{
    st_table *tbl;

    tbl = st_init_table_with_size(&objhash, RHASH(hash)->tbl->num_entries);
    st_foreach(RHASH(hash)->tbl, rb_hash_rehash_i, tbl);
    st_free_table(RHASH(hash)->tbl);
    RHASH(hash)->tbl = tbl;

    return hash;
}

VALUE
rb_hash_aref(hash, key)
    VALUE hash, key;
{
    VALUE val;

    if (!st_lookup(RHASH(hash)->tbl, key, &val)) {
	return RHASH(hash)->ifnone;
    }
    return val;
}

static VALUE
rb_hash_fetch(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE key, if_none;
    VALUE val;

    rb_scan_args(argc, argv, "11", &key, &if_none);

    if (!st_lookup(RHASH(hash)->tbl, key, &val)) {
	if (rb_iterator_p()) {
	    if (argc > 1) {
		rb_raise(rb_eArgError, "wrong # of arguments", argc);
	    }
	    return rb_yield(argv[0]);
	}
	return if_none;
    }
    return val;
}

static VALUE
rb_hash_default(hash)
    VALUE hash;
{
    return RHASH(hash)->ifnone;
}

static VALUE
rb_hash_set_default(hash, ifnone)
    VALUE hash, ifnone;
{
    RHASH(hash)->ifnone = ifnone;
    return hash;
}

static VALUE
rb_hash_indexes(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE indexes;
    int i;

    indexes = rb_ary_new2(argc);
    for (i=0; i<argc; i++) {
	RARRAY(indexes)->ptr[i] = rb_hash_aref(hash, argv[i]);
    }
    RARRAY(indexes)->len = i;
    return indexes;
}

static VALUE
rb_hash_delete(hash, key)
    VALUE hash, key;
{
    VALUE val;

    rb_hash_modify(hash);
    if (RHASH(hash)->iter_lev > 0 &&
	st_delete_safe(RHASH(hash)->tbl, &key, &val, Qnil)) {
	FL_SET(hash, HASH_DELETED);
	return val;
    }
    else if (st_delete(RHASH(hash)->tbl, &key, &val))
	return val;
    if (rb_iterator_p()) {
	return rb_yield(key);
    }
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
rb_hash_shift(hash)
    VALUE hash;
{
    struct shift_var var;

    rb_hash_modify(hash);
    var.stop = 0;
    st_foreach(RHASH(hash)->tbl, shift_i, &var);

    if (var.stop == 0) return Qnil;
    return rb_assoc_new(var.key, var.val);
}

static int
delete_if_i(key, value)
    VALUE key, value;
{
    if (key == Qnil) return ST_CONTINUE;
    if (rb_yield(rb_assoc_new(key, value)))
	return ST_DELETE;
    return ST_CONTINUE;
}

static VALUE
rb_hash_delete_if(hash)
    VALUE hash;
{
    rb_hash_modify(hash);
    rb_hash_foreach(hash, delete_if_i, 0);

    return hash;
}

static int
clear_i(key, value)
    VALUE key, value;
{
    return ST_DELETE;
}

static VALUE
rb_hash_clear(hash)
    VALUE hash;
{
    rb_hash_modify(hash);
    st_foreach(RHASH(hash)->tbl, clear_i);

    return hash;
}

VALUE
rb_hash_aset(hash, key, val)
    VALUE hash, key, val;
{
    rb_hash_modify(hash);
    if (NIL_P(val)) {
	rb_hash_delete(hash, key);
	return Qnil;
    }
    if (TYPE(key) != T_STRING || st_lookup(RHASH(hash)->tbl, key, 0)) {
	st_insert(RHASH(hash)->tbl, key, val);
    }
    else {
	st_add_direct(RHASH(hash)->tbl, rb_str_dup_frozen(key), val);
    }
    return val;
}

static int
replace_i(key, val, hash)
    VALUE key, val, hash;
{
    rb_hash_aset(hash, key, val);
    return ST_CONTINUE;
}

static VALUE
rb_hash_replace(hash, hash2)
    VALUE hash, hash2;
{
    hash2 = to_hash(hash2);
    rb_hash_clear(hash);
    st_foreach(RHASH(hash2)->tbl, replace_i, hash);

    return hash;
}

static VALUE
rb_hash_length(hash)
    VALUE hash;
{
    return INT2FIX(RHASH(hash)->tbl->num_entries);
}

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
    if (key == Qnil) return ST_CONTINUE;
    rb_yield(value);
    return ST_CONTINUE;
}

static VALUE
rb_hash_each_value(hash)
    VALUE hash;
{
    rb_hash_foreach(hash, each_value_i, 0);
    return hash;
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
rb_hash_each_key(hash)
    VALUE hash;
{
    rb_hash_foreach(hash, each_key_i, 0);
    return hash;
}

static int
each_pair_i(key, value)
    VALUE key, value;
{
    if (key == Qnil) return ST_CONTINUE;
    rb_yield(rb_assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
rb_hash_each_pair(hash)
    VALUE hash;
{
    rb_hash_foreach(hash, each_pair_i, 0);
    return hash;
}

static int
to_a_i(key, value, ary)
    VALUE key, value, ary;
{
    if (key == Qnil) return ST_CONTINUE;
    rb_ary_push(ary, rb_assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
rb_hash_to_a(hash)
    VALUE hash;
{
    VALUE ary;

    ary = rb_ary_new();
    st_foreach(RHASH(hash)->tbl, to_a_i, ary);

    return ary;
}

static VALUE
rb_hash_sort(hash)
    VALUE hash;
{
    return rb_ary_sort_bang(rb_hash_to_a(hash));
}

static int
inspect_i(key, value, str)
    VALUE key, value, str;
{
    VALUE str2;

    if (key == Qnil) return ST_CONTINUE;
    if (RSTRING(str)->len > 1) {
	rb_str_cat(str, ", ", 2);
    }
    str2 = rb_inspect(key);
    rb_str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    rb_str_cat(str, "=>", 2);
    str2 = rb_inspect(value);
    rb_str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);

    return ST_CONTINUE;
}

static VALUE
rb_hash_inspect(hash)
    VALUE hash;
{
    VALUE str;

    str = rb_str_new2("{");
    st_foreach(RHASH(hash)->tbl, inspect_i, str);
    rb_str_cat(str, "}", 1);

    return str;
}

static VALUE
rb_hash_to_s(hash)
    VALUE hash;
{
    return rb_ary_to_s(rb_hash_to_a(hash));
}

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
    if (key == Qnil) return ST_CONTINUE;
    rb_ary_push(ary, key);
    return ST_CONTINUE;
}

static VALUE
rb_hash_keys(hash)
    VALUE hash;
{
    VALUE ary;

    ary = rb_ary_new();
    st_foreach(RHASH(hash)->tbl, keys_i, ary);

    return ary;
}

static int
values_i(key, value, ary)
    VALUE key, value, ary;
{
    if (key == Qnil) return ST_CONTINUE;
    rb_ary_push(ary, value);
    return ST_CONTINUE;
}

static VALUE
rb_hash_values(hash)
    VALUE hash;
{
    VALUE ary;

    ary = rb_ary_new();
    st_foreach(RHASH(hash)->tbl, values_i, ary);

    return ary;
}

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
    if (key == Qnil) return ST_CONTINUE;
    if (rb_equal(value, data[1])) {
	data[0] = Qtrue;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

static VALUE
rb_hash_has_value(hash, val)
    VALUE hash;
    VALUE val;
{
    VALUE data[2];

    data[0] = Qfalse;
    data[1] = val;
    st_foreach(RHASH(hash)->tbl, rb_hash_search_value, data);
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
	data->result = Qfalse;
	return ST_STOP;
    }
    if (!rb_equal(val1, val2)) {
	data->result = Qfalse;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

static VALUE
rb_hash_equal(hash1, hash2)
    VALUE hash1, hash2;
{
    struct equal_data data;

    if (TYPE(hash2) != T_HASH) return Qfalse;
    if (RHASH(hash1)->tbl->num_entries != RHASH(hash2)->tbl->num_entries)
	return Qfalse;

    data.tbl = RHASH(hash2)->tbl;
    data.result = Qtrue;
    st_foreach(RHASH(hash1)->tbl, equal_i, &data);

    return data.result;
}

static int
rb_hash_invert_i(key, value, hash)
    VALUE key, value;
    VALUE hash;
{
    if (key == Qnil) return ST_CONTINUE;
    rb_hash_aset(hash, value, key);
    return ST_CONTINUE;
}

static VALUE
rb_hash_invert(hash)
    VALUE hash;
{
    VALUE h = rb_hash_new();

    st_foreach(RHASH(hash)->tbl, rb_hash_invert_i, h);
    return h;
}

static int
rb_hash_update_i(key, value, hash)
    VALUE key, value;
    VALUE hash;
{
    if (key == Qnil) return ST_CONTINUE;
    rb_hash_aset(hash, key, value);
    return ST_CONTINUE;
}

static VALUE
rb_hash_update(hash1, hash2)
    VALUE hash1, hash2;
{
    hash2 = to_hash(hash2);
    st_foreach(RHASH(hash2)->tbl, rb_hash_update_i, hash1);
    return hash1;
}

#ifndef __MACOS__ /* environment variables nothing on MacOS. */
static int path_tainted = -1;

#ifndef NT
extern char **environ;
#endif

static VALUE
env_delete(obj, name)
    VALUE obj, name;
{
    int i, len;
    char *nam, *val = 0;

    rb_secure(4);
    nam = STR2CSTR(name);
    len = strlen(nam);
    if (strcmp(nam, "PATH") == 0) path_tainted = 0;
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
	return rb_str_new2(val);
    }
    return Qnil;
}

static VALUE
env_delete_method(obj, name)
    VALUE obj, name;
{
    VALUE val = env_delete(obj, name);
    if (rb_iterator_p()) rb_yield(name);
    return val;
}

static VALUE
rb_f_getenv(obj, name)
    VALUE obj, name;
{
    char *nam, *env;
    int len;

    nam = str2cstr(name, &len);
    if (strlen(nam) != len) {
	rb_raise(rb_eArgError, "Bad environment variable name");
    }
    env = getenv(nam);
    if (env) {
	if (strcmp(nam, "PATH") == 0 && !rb_env_path_tainted())
	    return rb_str_new2(env);
	return rb_tainted_str_new2(env);
    }
    return Qnil;
}

static int
path_check_1(path)
    char *path;
{
    struct stat st;
    char *p = 0;
    char *s;

    for (;;) {
	if (stat(path, &st) == 0 && (st.st_mode & 2)) {
	    return 0;
	}
	s = strrchr(path, '/');
	if (p) *p = '/';
	if (!s || s == path) return 1;
	p = s;
	*p = '\0';
    }
}

void
rb_path_check(path)
    char *path;
{
    char *p = path;
    char *pend = strchr(path, ':');

    if (!path) {
	path_tainted = 0;
    }

    p = path;
    pend = strchr(path, ':');
    
    for (;;) {
	int safe;

	if (pend) *pend = '\0';
	safe = path_check_1(p);
	if (!pend) break;
	*pend = ':';
	if (!safe) {
	    path_tainted = 1;
	    return;
	}
	p = pend + 1;
	pend = strchr(p, ':');
    }
    path_tainted = 0;
}

int
rb_env_path_tainted()
{
    if (path_tainted < 0) {
	rb_path_check(getenv("PATH"));
    }
    return path_tainted;
}

static VALUE
rb_f_setenv(obj, name, value)
    VALUE obj, name, value;
{
    if (rb_safe_level() >= 4) {
	rb_raise(rb_eSecurityError, "cannot change environment variable");
    }

    Check_SafeStr(name);
    if (NIL_P(value)) {
	env_delete(obj, name);
	return Qnil;
    }

    Check_SafeStr(value);
    if (strlen(RSTRING(name)->ptr) != RSTRING(name)->len)
	rb_raise(rb_eArgError, "Bad environment name");
    if (strlen(RSTRING(value)->ptr) != RSTRING(value)->len)
	rb_raise(rb_eArgError, "Bad environment value");
    
    setenv(RSTRING(name)->ptr, RSTRING(value)->ptr, 1);
    if (strcmp(RSTRING(name)->ptr, "PATH") == 0) {
	if (rb_obj_tainted(value)) {
	    /* already tainted, no check */
	    path_tainted = 1;
	    return Qtrue;
	}

	rb_path_check(RSTRING(name)->ptr);
    }
    return Qtrue;
}

static VALUE
env_keys()
{
    char **env;
    VALUE ary = rb_ary_new();

    env = environ;
    while (*env) {
	char *s = strchr(*env, '=');
	rb_ary_push(ary, rb_tainted_str_new(*env, s-*env));
	env++;
    }
    return ary;
}

static VALUE
env_each_key(hash)
    VALUE hash;
{
    return rb_ary_each(env_keys());
}

static VALUE
env_values()
{
    char **env;
    VALUE ary = rb_ary_new();

    env = environ;
    while (*env) {
	char *s = strchr(*env, '=');
	rb_ary_push(ary, rb_tainted_str_new2(s+1));
	env++;
    }
    return ary;
}

static VALUE
env_each_value(hash)
    VALUE hash;
{
    return rb_ary_each(env_values());
}

static VALUE
env_each(hash)
    VALUE hash;
{
    volatile VALUE ary = env_keys();
    VALUE *ptr = RARRAY(ary)->ptr;
    int len = RARRAY(ary)->len; 

    while (len--) {
	VALUE val = rb_f_getenv(Qnil, *ptr);
	if (!NIL_P(val)) {
	    rb_yield(rb_assoc_new(*ptr, val));
	}
	ptr++;
    }
    return hash;
}

static VALUE
env_delete_if()
{
    volatile VALUE ary;
    VALUE *ptr;
    int len;

    rb_secure(4);
    ary = env_keys();
    ptr = RARRAY(ary)->ptr;
    len = RARRAY(ary)->len; 

    while (len--) {
	VALUE val = rb_f_getenv(Qnil, *ptr);
	if (!NIL_P(val)) {
	    if (RTEST(rb_yield(rb_assoc_new(*ptr, val)))) {
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
    return rb_str_new2("ENV");
}

static VALUE
env_to_a()
{
    char **env;
    VALUE ary = rb_ary_new();

    env = environ;
    while (*env) {
	char *s = strchr(*env, '=');
	rb_ary_push(ary, rb_assoc_new(rb_tainted_str_new(*env, s-*env),
				      rb_tainted_str_new2(s+1)));
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
    if (environ[0] == 0) return Qtrue;
    return Qfalse;
}

static VALUE
env_has_key(env, key)
    VALUE env, key;
{
    if (TYPE(key) != T_STRING) return Qfalse;
    if (getenv(RSTRING(key)->ptr)) return Qtrue;
    return Qfalse;
}

static VALUE
env_has_value(dmy, value)
    VALUE dmy, value;
{
    char **env;
    volatile VALUE ary;

    if (TYPE(value) != T_STRING) return Qfalse;
    ary = rb_ary_new();
    env = environ;
    while (*env) {
	char *s = strchr(*env, '=')+1;
	int len = strlen(s);
	if (strncmp(s, RSTRING(value)->ptr, len) == 0) return Qtrue;
	env++;
    }
    return Qfalse;
}

static VALUE
env_indexes(argc, argv)
    int argc;
    VALUE *argv;
{
    int i;
    VALUE indexes = rb_ary_new2(argc);

    for (i=0;i<argc;i++) {
	char *v = 0;
	if (TYPE(argv[i]) == T_STRING) {
	    v = getenv(RSTRING(argv[i])->ptr);
	}
	if (v) {
	    RARRAY(indexes)->ptr[i] = rb_str_new2(v);
	}
	else {
	    RARRAY(indexes)->ptr[i] = Qnil;
	}
	RARRAY(indexes)->len = i+1;
    }

    return indexes;
}

static VALUE
env_to_hash(obj)
    VALUE obj;
{
    VALUE hash = rb_hash_new();
    volatile VALUE ary = env_keys();
    VALUE *ptr = RARRAY(ary)->ptr;
    int len = RARRAY(ary)->len; 

    while (len--) {
	VALUE val = rb_f_getenv(Qnil, *ptr);
	if (!NIL_P(val)) {
	    rb_hash_aset(hash, *ptr, val);
	}
	ptr++;
    }
    return hash;
}

#endif  /* ifndef __MACOS__  environment variables nothing on MacOS. */

void
Init_Hash()
{
    hash = rb_intern("hash");

    rb_cHash = rb_define_class("Hash", rb_cObject);

    rb_include_module(rb_cHash, rb_mEnumerable);

    rb_define_singleton_method(rb_cHash, "new", rb_hash_s_new, -1);
    rb_define_singleton_method(rb_cHash, "[]", rb_hash_s_create, -1);

    rb_define_method(rb_cHash,"clone", rb_hash_clone, 0);
    rb_define_method(rb_cHash,"dup", rb_hash_dup, 0);
    rb_define_method(rb_cHash,"rehash", rb_hash_rehash, 0);

    rb_define_method(rb_cHash,"freeze", rb_hash_freeze, 0);
    rb_define_method(rb_cHash,"frozen?",rb_hash_frozen_p, 0);

    rb_define_method(rb_cHash,"to_hash", rb_hash_to_hash, 0);
    rb_define_method(rb_cHash,"to_a", rb_hash_to_a, 0);
    rb_define_method(rb_cHash,"to_s", rb_hash_to_s, 0);
    rb_define_method(rb_cHash,"inspect", rb_hash_inspect, 0);

    rb_define_method(rb_cHash,"==", rb_hash_equal, 1);
    rb_define_method(rb_cHash,"[]", rb_hash_aref, 1);
    rb_define_method(rb_cHash,"fetch", rb_hash_fetch, -1);
    rb_define_method(rb_cHash,"[]=", rb_hash_aset, 2);
    rb_define_method(rb_cHash,"store", rb_hash_aset, 2);
    rb_define_method(rb_cHash,"default", rb_hash_default, 0);
    rb_define_method(rb_cHash,"default=", rb_hash_set_default, 1);
    rb_define_method(rb_cHash,"indexes", rb_hash_indexes, -1);
    rb_define_method(rb_cHash,"indices", rb_hash_indexes, -1);
    rb_define_method(rb_cHash,"length", rb_hash_length, 0);
    rb_define_alias(rb_cHash, "size", "length");
    rb_define_method(rb_cHash,"empty?", rb_hash_empty_p, 0);

    rb_define_method(rb_cHash,"each", rb_hash_each_pair, 0);
    rb_define_method(rb_cHash,"each_value", rb_hash_each_value, 0);
    rb_define_method(rb_cHash,"each_key", rb_hash_each_key, 0);
    rb_define_method(rb_cHash,"each_pair", rb_hash_each_pair, 0);
    rb_define_method(rb_cHash,"sort", rb_hash_sort, 0);

    rb_define_method(rb_cHash,"keys", rb_hash_keys, 0);
    rb_define_method(rb_cHash,"values", rb_hash_values, 0);

    rb_define_method(rb_cHash,"shift", rb_hash_shift, 0);
    rb_define_method(rb_cHash,"delete", rb_hash_delete, 1);
    rb_define_method(rb_cHash,"delete_if", rb_hash_delete_if, 0);
    rb_define_method(rb_cHash,"clear", rb_hash_clear, 0);
    rb_define_method(rb_cHash,"invert", rb_hash_invert, 0);
    rb_define_method(rb_cHash,"update", rb_hash_update, 1);
    rb_define_method(rb_cHash,"replace", rb_hash_replace, 1);

    rb_define_method(rb_cHash,"include?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash,"has_key?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash,"has_value?", rb_hash_has_value, 1);
    rb_define_method(rb_cHash,"key?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash,"value?", rb_hash_has_value, 1);

#ifndef __MACOS__ /* environment variables nothing on MacOS. */
    envtbl = rb_obj_alloc(rb_cObject);
    rb_extend_object(envtbl, rb_mEnumerable);

    rb_define_singleton_method(envtbl,"[]", rb_f_getenv, 1);
    rb_define_singleton_method(envtbl,"[]=", rb_f_setenv, 2);
    rb_define_singleton_method(envtbl,"each", env_each, 0);
    rb_define_singleton_method(envtbl,"each_pair", env_each, 0);
    rb_define_singleton_method(envtbl,"each_key", env_each_key, 0);
    rb_define_singleton_method(envtbl,"each_value", env_each_value, 0);
    rb_define_singleton_method(envtbl,"delete", env_delete_method, 1);
    rb_define_singleton_method(envtbl,"delete_if", env_delete_if, 0);
    rb_define_singleton_method(envtbl,"to_s", env_to_s, 0);
    rb_define_singleton_method(envtbl,"rehash", env_none, 0);
    rb_define_singleton_method(envtbl,"to_a", env_to_a, 0);
    rb_define_singleton_method(envtbl,"indexes", env_indexes, -1);
    rb_define_singleton_method(envtbl,"indices", env_indexes, -1);
    rb_define_singleton_method(envtbl,"length", env_size, 0);
    rb_define_singleton_method(envtbl,"empty?", env_empty_p, 0);
    rb_define_singleton_method(envtbl,"keys", env_keys, 0);
    rb_define_singleton_method(envtbl,"values", env_values, 0);
    rb_define_singleton_method(envtbl,"include?", env_has_key, 1);
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
