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
hash_modify(hash)
    VALUE hash;
{
    rb_secure(5);
    if (FL_TEST(hash, HASH_FREEZE)) {
	TypeError("can't modify frozen hash");
    }
}

VALUE
hash_freeze(hash)
    VALUE hash;
{
    FL_SET(hash, HASH_FREEZE);
    return hash;
}

static VALUE
hash_frozen_p(hash)
    VALUE hash;
{
    if (FL_TEST(hash, HASH_FREEZE))
	return TRUE;
    return FALSE;
}

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
	hval = FIX2LONG(hval);
    }
    return  hval % mod;
}

static struct st_hash_type objhash = {
    any_cmp,
    any_hash,
};

struct hash_foreach_arg {
    VALUE hash;
    enum st_retval (*func)();
    char *arg;
};

static int
hash_foreach_iter(key, value, arg)
    VALUE key, value;
    struct hash_foreach_arg *arg;
{
    int status;
    st_table *tbl = RHASH(arg->hash)->tbl;
    st_table_entry **bins = tbl->bins;

    if (key == Qnil) return ST_CONTINUE;
    status = (*arg->func)(key, value, arg->arg);
    if (RHASH(arg->hash)->tbl != tbl || RHASH(arg->hash)->tbl->bins != bins){
	IndexError("rehash occurred during iteration");
    }
    return status;
}

static VALUE
hash_foreach_call(arg)
    struct hash_foreach_arg *arg;
{
    st_foreach(RHASH(arg->hash)->tbl, hash_foreach_iter, arg);
    return Qnil;
}

static int
hash_delete_nil(key, value)
    VALUE key, value;
{
    if (value == Qnil) return ST_DELETE;
    return ST_CONTINUE;
}

static VALUE
hash_foreach_ensure(hash)
    VALUE hash;
{
    RHASH(hash)->iter_lev--;

    if (RHASH(hash)->iter_lev == 0) {
	if (FL_TEST(hash, HASH_DELETED)) {
	    st_foreach(RHASH(hash)->tbl, hash_delete_nil, 0);
	    FL_UNSET(hash, HASH_DELETED);
	}
    }
    return 0;
}

static int
hash_foreach(hash, func, farg)
    VALUE hash;
    enum st_retval (*func)();
    char *farg;
{
    struct hash_foreach_arg arg;

    RHASH(hash)->iter_lev++;
    arg.hash = hash;
    arg.func = func;
    arg.arg  = farg;
    return rb_ensure(hash_foreach_call, (VALUE)&arg, hash_foreach_ensure, hash);
}

static VALUE
hash_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE sz;
    int size;

    NEWOBJ(hash, struct RHash);
    OBJSETUP(hash, klass, T_HASH);

    hash->iter_lev = 0;
    hash->status = 0;
    hash->tbl = 0;		/* avoid GC crashing  */

    if (rb_scan_args(argc, argv, "01", &sz) == 0) {
	size = 0;
    }
    else size = NUM2INT(sz);

    hash->tbl = st_init_table_with_size(&objhash, size);
    obj_call_init((VALUE)hash);

    return (VALUE)hash;
}

static VALUE
hash_new2(klass)
    VALUE klass;
{
    NEWOBJ(hash, struct RHash);
    OBJSETUP(hash, klass, T_HASH);

    hash->iter_lev = 0;
    hash->status = 0;
    hash->tbl = 0;		/* avoid GC crashing  */
    hash->tbl = st_init_table(&objhash);

    return (VALUE)hash;
}

VALUE
hash_new()
{
    return hash_new2(cHash);
}

static VALUE
hash_s_create(argc, argv, klass)
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
	    hash->status = 0;
	    hash->tbl = 0;	/* avoid GC crashing  */
	    hash->tbl = (st_table*)st_copy(RHASH(argv[0])->tbl);
	    obj_call_init((VALUE)hash);
	    return (VALUE)hash;
	}
    }

    if (argc % 2 != 0) {
	ArgError("odd number args for Hash");
    }
    hash = hash_new2(klass);

    for (i=0; i<argc; i+=2) {
	st_insert(RHASH(hash)->tbl, argv[i], argv[i+1]);
    }
    obj_call_init(hash);

    return hash;
}

static VALUE
hash_clone(hash)
    VALUE hash;
{
    NEWOBJ(hash2, struct RHash);
    CLONESETUP(hash2, hash);

    hash2->iter_lev = 0;
    hash2->status = 0;
    hash2->tbl = 0;		/* avoid GC crashing  */
    hash2->tbl = (st_table*)st_copy(RHASH(hash)->tbl);

    return (VALUE)hash2;
}

static VALUE
hash_dup(hash)
    VALUE hash;
{
    NEWOBJ(hash2, struct RHash);
    OBJSETUP(hash2, CLASS_OF(hash), T_HASH);

    hash2->iter_lev = 0;
    hash2->status = 0;
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
    VALUE hash;
{
    st_table *tbl;

    tbl = st_init_table_with_size(&objhash, RHASH(hash)->tbl->num_entries);
    st_foreach(RHASH(hash)->tbl, hash_rehash_i, tbl);
    st_free_table(RHASH(hash)->tbl);
    RHASH(hash)->tbl = tbl;

    return hash;
}

VALUE
hash_aref(hash, key)
    VALUE hash, key;
{
    VALUE val;

    if (!st_lookup(RHASH(hash)->tbl, key, &val)) {
	return Qnil;
    }
    return val;
}

static VALUE
hash_fetch(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE key, if_none;
    VALUE val;

    rb_scan_args(argc, argv, "11", &key, &if_none);

    if (!st_lookup(RHASH(hash)->tbl, key, &val)) {
	if (iterator_p()) {
	    if (argc > 1) {
		ArgError("wrong # of arguments", argc);
	    }
	    return rb_yield(argv[0]);
	}
	return if_none;
    }
    return val;
}

static VALUE
hash_indexes(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE indexes;
    int i;

    indexes = ary_new2(argc);
    for (i=0; i<argc; i++) {
	RARRAY(indexes)->ptr[i] = hash_aref(hash, argv[i]);
    }
    RARRAY(indexes)->len = i;
    return indexes;
}

static VALUE
hash_delete(hash, key)
    VALUE hash, key;
{
    VALUE val;

    hash_modify(hash);
    if (RHASH(hash)->iter_lev > 0 &&
	st_delete_safe(RHASH(hash)->tbl, &key, &val, Qnil)) {
	FL_SET(hash, HASH_DELETED);
	return val;
    }
    else if (st_delete(RHASH(hash)->tbl, &key, &val))
	return val;
    if (iterator_p()) {
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
hash_shift(hash)
    VALUE hash;
{
    struct shift_var var;

    hash_modify(hash);
    var.stop = 0;
    st_foreach(RHASH(hash)->tbl, shift_i, &var);

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
    VALUE hash;
{
    hash_modify(hash);
    hash_foreach(hash, delete_if_i, 0);

    return hash;
}

static int
clear_i(key, value)
    VALUE key, value;
{
    return ST_DELETE;
}

static VALUE
hash_clear(hash)
    VALUE hash;
{
    hash_modify(hash);
    st_foreach(RHASH(hash)->tbl, clear_i);

    return hash;
}

VALUE
hash_aset(hash, key, val)
    VALUE hash, key, val;
{
    hash_modify(hash);
    if (NIL_P(val)) {
	hash_delete(hash, key);
	return Qnil;
    }
    if (TYPE(key) == T_STRING) {
	key = str_dup_frozen(key);
    }
    st_insert(RHASH(hash)->tbl, key, val);
    return val;
}

static int
replace_i(key, val, hash)
    VALUE key, val, hash;
{
    hash_aset(hash, key, val);
    return ST_CONTINUE;
}

static VALUE
hash_replace(hash, hash2)
    VALUE hash, hash2;
{
    hash2 = to_hash(hash2);
    hash_clear(hash);
    st_foreach(RHASH(hash2)->tbl, replace_i, hash);

    return hash;
}

static VALUE
hash_length(hash)
    VALUE hash;
{
    return INT2FIX(RHASH(hash)->tbl->num_entries);
}

static VALUE
hash_empty_p(hash)
    VALUE hash;
{
    if (RHASH(hash)->tbl->num_entries == 0)
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
    VALUE hash;
{
    hash_foreach(hash, each_value_i);
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
hash_each_key(hash)
    VALUE hash;
{
    hash_foreach(hash, each_key_i);
    return hash;
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
    VALUE hash;
{
    hash_foreach(hash, each_pair_i, 0);
    return hash;
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
    VALUE hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(RHASH(hash)->tbl, to_a_i, ary);

    return ary;
}

static int
inspect_i(key, value, str)
    VALUE key, value, str;
{
    VALUE str2;

    if (key == Qnil) return ST_CONTINUE;
    if (RSTRING(str)->len > 1) {
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
    VALUE hash;
{
    VALUE str;

    str = str_new2("{");
    st_foreach(RHASH(hash)->tbl, inspect_i, str);
    str_cat(str, "}", 1);

    return str;
}

static VALUE
hash_to_s(hash)
    VALUE hash;
{
    return ary_to_s(hash_to_a(hash));
}

static VALUE
hash_to_hash(hash)
    VALUE hash;
{
    return hash;
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
    VALUE hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(RHASH(hash)->tbl, keys_i, ary);

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
    VALUE hash;
{
    VALUE ary;

    ary = ary_new();
    st_foreach(RHASH(hash)->tbl, values_i, ary);

    return ary;
}

static VALUE
hash_has_key(hash, key)
    VALUE hash;
    VALUE key;
{
    if (st_lookup(RHASH(hash)->tbl, key, 0)) {
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
    VALUE hash;
    VALUE val;
{
    VALUE data[2];

    data[0] = FALSE;
    data[1] = val;
    st_foreach(RHASH(hash)->tbl, hash_search_value, data);
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
    VALUE hash1, hash2;
{
    struct equal_data data;

    if (TYPE(hash2) != T_HASH) return FALSE;
    if (RHASH(hash1)->tbl->num_entries != RHASH(hash2)->tbl->num_entries)
	return FALSE;

    data.tbl = RHASH(hash2)->tbl;
    data.result = TRUE;
    st_foreach(RHASH(hash1)->tbl, equal_i, &data);

    return data.result;
}

static int
hash_invert_i(key, value, hash)
    VALUE key, value;
    VALUE hash;
{
    if (key == Qnil) return ST_CONTINUE;
    hash_aset(hash, value, key);
    return ST_CONTINUE;
}

static VALUE
hash_invert(hash)
    VALUE hash;
{
    VALUE h = hash_new();

    st_foreach(RHASH(hash)->tbl, hash_invert_i, h);
    return h;
}

static int
hash_update_i(key, value, hash)
    VALUE key, value;
    VALUE hash;
{
    if (key == Qnil) return ST_CONTINUE;
    hash_aset(hash, key, value);
    return ST_CONTINUE;
}

static VALUE
hash_update(hash1, hash2)
    VALUE hash1, hash2;
{
    hash2 = to_hash(hash2);
    st_foreach(RHASH(hash2)->tbl, hash_update_i, hash1);
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
	return str_new2(val);
    }
    return Qnil;
}

static VALUE
env_delete_method(obj, name)
    VALUE obj, name;
{
    VALUE val = env_delete(obj, name);
    if (iterator_p()) rb_yield(name);
    return val;
}

static VALUE
f_getenv(obj, name)
    VALUE obj, name;
{
    char *nam, *env;
    int len;

    nam = str2cstr(name, &len);
    if (strlen(nam) != len) {
	ArgError("Bad environment variable name");
    }
    env = getenv(nam);
    if (env) {
	if (strcmp(nam, "PATH") == 0 && !env_path_tainted())
	    return str_new2(env);
	return str_taint(str_new2(env));
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

static void
path_check(path)
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
env_path_tainted()
{
    if (path_tainted < 0) {
	path_check(getenv("PATH"));
    }
    return path_tainted;
}

static VALUE
f_setenv(obj, name, value)
    VALUE obj, name, value;
{
    if (rb_safe_level() >= 4) {
	Raise(eSecurityError, "cannot change environment variable");
    }

    Check_SafeStr(name);
    if (NIL_P(value)) {
	env_delete(obj, name);
	return Qnil;
    }

    Check_SafeStr(value);
    if (strlen(RSTRING(name)->ptr) != RSTRING(name)->len)
	ArgError("Bad environment name");
    if (strlen(RSTRING(value)->ptr) != RSTRING(value)->len)
	ArgError("Bad environment value");

    setenv(RSTRING(name)->ptr, RSTRING(value)->ptr, 1);
    if (strcmp(RSTRING(name)->ptr, "PATH") == 0) {
	if (str_tainted(value)) {
	    /* already tainted, no check */
	    path_tainted = 1;
	    return TRUE;
	}

	path_check(RSTRING(name)->ptr);
    }
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

static VALUE
env_to_hash(obj)
    VALUE obj;
{
    VALUE hash = hash_new();
    VALUE ary = env_keys();
    VALUE *ptr = RARRAY(ary)->ptr;
    int len = RARRAY(ary)->len; 

    while (len--) {
	VALUE val = f_getenv(Qnil, *ptr);
	if (!NIL_P(val)) {
	    hash_aset(hash, *ptr, val);
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

    cHash = rb_define_class("Hash", cObject);

    rb_include_module(cHash, mEnumerable);

    rb_define_singleton_method(cHash, "new", hash_s_new, -1);
    rb_define_singleton_method(cHash, "[]", hash_s_create, -1);

    rb_define_method(cHash,"clone", hash_clone, 0);
    rb_define_method(cHash,"dup", hash_dup, 0);
    rb_define_method(cHash,"rehash", hash_rehash, 0);

    rb_define_method(cHash,"freeze", hash_freeze, 0);
    rb_define_method(cHash,"frozen?",hash_frozen_p, 0);

    rb_define_method(cHash,"to_hash", hash_to_hash, 0);
    rb_define_method(cHash,"to_a", hash_to_a, 0);
    rb_define_method(cHash,"to_s", hash_to_s, 0);
    rb_define_method(cHash,"inspect", hash_inspect, 0);

    rb_define_method(cHash,"==", hash_equal, 1);
    rb_define_method(cHash,"[]", hash_aref, 1);
    rb_define_method(cHash,"fetch", hash_fetch, -1);
    rb_define_method(cHash,"[]=", hash_aset, 2);
    rb_define_method(cHash,"store", hash_aset, 2);
    rb_define_method(cHash,"indexes", hash_indexes, -1);
    rb_define_method(cHash,"indices", hash_indexes, -1);
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
    rb_define_method(cHash,"update", hash_update, 1);
    rb_define_method(cHash,"replace", hash_replace, 1);

    rb_define_method(cHash,"include?", hash_has_key, 1);
    rb_define_method(cHash,"has_key?", hash_has_key, 1);
    rb_define_method(cHash,"has_value?", hash_has_value, 1);
    rb_define_method(cHash,"key?", hash_has_key, 1);
    rb_define_method(cHash,"value?", hash_has_value, 1);

#ifndef __MACOS__ /* environment variables nothing on MacOS. */
    envtbl = obj_alloc(cObject);
    rb_extend_object(envtbl, mEnumerable);

    rb_define_singleton_method(envtbl,"[]", f_getenv, 1);
    rb_define_singleton_method(envtbl,"[]=", f_setenv, 2);
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
	envtbl = hash_s_new(0, NULL, cHash);
    rb_define_global_const("ENV", envtbl);
#endif  /* ifndef __MACOS__  environment variables nothing on MacOS. */
}
