/**********************************************************************

  hash.c -

  $Author$
  $Date$
  created at: Mon Nov 22 18:51:18 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "st.h"
#include "util.h"
#include "rubysig.h"

#define HASH_DELETED  FL_USER1

static void
rb_hash_modify(hash)
    VALUE hash;
{
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
static ID hash;

VALUE
rb_hash(obj)
    VALUE obj;
{
    return rb_funcall(obj, hash, 0);
}

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
    if (FIXNUM_P(a) && FIXNUM_P(b)) {
	return a != b;
    }
    if (TYPE(a) == T_STRING && RBASIC(a)->klass == rb_cString &&
	TYPE(b) == T_STRING && RBASIC(b)->klass == rb_cString) {
	return rb_str_cmp(a, b);
    }
    if (SYMBOL_P(a) && SYMBOL_P(b)) {
	return a != b;
    }
    if (a == Qundef || b == Qundef) return -1;

    args[0] = a;
    args[1] = b;
    return !rb_with_disable_interrupt(eql, (VALUE)args);
}

static int
rb_any_hash(a)
    VALUE a;
{
    VALUE hval;

    switch (TYPE(a)) {
      case T_FIXNUM:
      case T_SYMBOL:
	return (int)a;
	break;

      case T_STRING:
	return rb_str_hash(a);
	break;

      default:
	DEFER_INTS;
	hval = rb_funcall(a, hash, 0);
	if (!FIXNUM_P(hval)) {
	    hval = rb_funcall(hval, '%', 1, INT2FIX(536870923));
	}
	ENABLE_INTS;
	return (int)FIX2LONG(hval);
    }
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

    if (key == Qundef) return ST_CONTINUE;
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

static VALUE
rb_hash_foreach_ensure(hash)
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
rb_hash_new2(klass)
    VALUE klass;
{
    NEWOBJ(hash, struct RHash);
    OBJSETUP(hash, klass, T_HASH);

    hash->ifnone = Qnil;
    hash->tbl = st_init_table(&objhash);

    return (VALUE)hash;
}

VALUE
rb_hash_new()
{
    return rb_hash_new2(rb_cHash);
}

static VALUE
rb_hash_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE hash = rb_hash_new2(klass);

    rb_obj_call_init(hash, argc, argv);
    return hash;
}

static VALUE
rb_hash_initialize(argc, argv, hash)
    int argc;
    VALUE *argv;
    VALUE hash;
{
    VALUE ifnone;

    rb_scan_args(argc, argv, "01", &ifnone);
    rb_hash_modify(hash);
    RHASH(hash)->ifnone = ifnone;

    return hash;
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
	NEWOBJ(hash, struct RHash);
	OBJSETUP(hash, klass, T_HASH);
	    
	hash->ifnone = Qnil;
	hash->tbl = st_copy(RHASH(argv[0])->tbl);

	return (VALUE)hash;
    }

    if (argc % 2 != 0) {
	rb_raise(rb_eArgError, "odd number args for Hash");
    }
    hash = rb_hash_new2(klass);

    for (i=0; i<argc; i+=2) {
	st_insert(RHASH(hash)->tbl, argv[i], argv[i+1]);
    }

    return hash;
}

static VALUE
rb_hash_clone(hash)
    VALUE hash;
{
    NEWOBJ(clone, struct RHash);
    CLONESETUP(clone, hash);

    clone->ifnone = RHASH(hash)->ifnone;
    clone->tbl = (st_table*)st_copy(RHASH(hash)->tbl);

    return (VALUE)clone;
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
	if (rb_block_given_p()) {
	    if (argc > 1) {
		rb_raise(rb_eArgError, "wrong # of arguments", argc);
	    }
	    return rb_yield(key);
	}
	if (argc == 1) {
	    rb_raise(rb_eIndexError, "key not found");
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
    rb_hash_modify(hash);
    RHASH(hash)->ifnone = ifnone;
    return ifnone;
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
rb_hash_index(hash, value)
    VALUE hash, value;
{
    VALUE args[2];

    args[0] = value;
    args[1] = Qnil;

    st_foreach(RHASH(hash)->tbl, index_i, args);

    return args[1];
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
    if (RHASH(hash)->iter_lev > 0) {
	if (st_delete_safe(RHASH(hash)->tbl, &key, &val, Qundef)) {
	    FL_SET(hash, HASH_DELETED);
	    return val;
	}
    }
    else if (st_delete(RHASH(hash)->tbl, &key, &val))
	return val;
    if (rb_block_given_p()) {
	return rb_yield(key);
    }
    return RHASH(hash)->ifnone;
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
    if (key == Qundef) return ST_CONTINUE;
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

    if (var.stop == 0) return RHASH(hash)->ifnone;
    return rb_assoc_new(var.key, var.val);
}

static int
delete_if_i(key, value)
    VALUE key, value;
{
    if (key == Qundef) return ST_CONTINUE;
    if (RTEST(rb_yield(rb_assoc_new(key, value))))
	return ST_DELETE;
    return ST_CONTINUE;
}

VALUE
rb_hash_delete_if(hash)
    VALUE hash;
{
    rb_hash_modify(hash);
    rb_hash_foreach(hash, delete_if_i, 0);
    return hash;
}

VALUE
rb_hash_reject_bang(hash)
    VALUE hash;
{
    int n = RHASH(hash)->tbl->num_entries;
    rb_hash_delete_if(hash);
    if (n == RHASH(hash)->tbl->num_entries) return Qnil;
    return hash;
}

static VALUE
rb_hash_reject(hash)
    VALUE hash;
{
    return rb_hash_delete_if(rb_obj_dup(hash));
}

static int
clear_i(key, value, dummy)
    VALUE key, value, dummy;
{
    return ST_DELETE;
}

static VALUE
rb_hash_clear(hash)
    VALUE hash;
{
    rb_hash_modify(hash);
    st_foreach(RHASH(hash)->tbl, clear_i, 0);

    return hash;
}

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
rb_hash_size(hash)
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
    if (key == Qundef) return ST_CONTINUE;
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
    if (key == Qundef) return ST_CONTINUE;
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
    if (key == Qundef) return ST_CONTINUE;
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
    if (key == Qundef) return ST_CONTINUE;
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
    if (OBJ_TAINTED(hash)) OBJ_TAINT(ary);

    return ary;
}

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
    rb_str_append(str, str2);
    OBJ_INFECT(str, str2);
    rb_str_cat2(str, "=>");
    str2 = rb_inspect(value);
    rb_str_append(str, str2);
    OBJ_INFECT(str, str2);

    return ST_CONTINUE;
}

static VALUE
inspect_hash(hash)
    VALUE hash;
{
    VALUE str;

    str = rb_str_new2("{");
    st_foreach(RHASH(hash)->tbl, inspect_i, str);
    rb_str_cat2(str, "}");
    
    OBJ_INFECT(str, hash);
    return str;
}

static VALUE
rb_hash_inspect(hash)
    VALUE hash;
{
    if (RHASH(hash)->tbl->num_entries == 0) return rb_str_new2("{}");
    if (rb_inspecting_p(hash)) return rb_str_new2("{...}");
    return rb_protect_inspect(inspect_hash, hash, 0);
}

static VALUE
to_s_hash(hash)
    VALUE hash;
{
    return rb_ary_to_s(rb_hash_to_a(hash));
}

static VALUE
rb_hash_to_s(hash)
    VALUE hash;
{
    if (rb_inspecting_p(hash)) return rb_str_new2("{...}");
    return rb_protect_inspect(to_s_hash, hash, 0);
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
    if (key == Qundef) return ST_CONTINUE;
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
    if (key == Qundef) return ST_CONTINUE;
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
    if (key == Qundef) return ST_CONTINUE;
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

    if (key == Qundef) return ST_CONTINUE;
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

    if (hash1 == hash2) return Qtrue;
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
    if (key == Qundef) return ST_CONTINUE;
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
    if (key == Qundef) return ST_CONTINUE;
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

static int path_tainted = -1;

static char **origenviron;
#ifdef NT
#define GET_ENVIRON(e) (e = win32_get_environ())
#define FREE_ENVIRON(e) win32_free_environ(e)
static char **my_environ;
#undef environ
#define environ my_environ
#else
extern char **environ;
#define GET_ENVIRON(e) (e)
#define FREE_ENVIRON(e)
#endif

static VALUE
env_delete(obj, name)
    VALUE obj, name;
{
    int len;
    char *nam, *val;

    rb_secure(4);
    nam = rb_str2cstr(name, &len);
    if (strlen(nam) != len) {
	rb_raise(rb_eArgError, "bad environment variable name");
    }
    val = getenv(nam);
    if (val) {
	VALUE value = rb_tainted_str_new2(val);

	ruby_setenv(nam, 0);
	if (strcmp(nam, "PATH") == 0 && !OBJ_TAINTED(name)) {
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
    VALUE val = env_delete(obj, name);
    if (rb_block_given_p()) rb_yield(name);
    return val;
}

static VALUE
rb_f_getenv(obj, name)
    VALUE obj, name;
{
    char *nam, *env;
    int len;

    nam = rb_str2cstr(name, &len);
    if (strlen(nam) != len) {
	rb_raise(rb_eArgError, "bad environment variable name");
    }
    env = getenv(nam);
    if (env) {
	if (strcmp(nam, "PATH") == 0 && !rb_env_path_tainted())
	    return rb_str_new2(env);
	return rb_tainted_str_new2(env);
    }
    return Qnil;
}

static VALUE
env_fetch(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE key, if_none;
    char *nam, *env;
    int len;

    rb_scan_args(argc, argv, "11", &key, &if_none);
    nam = rb_str2cstr(key, &len);
    if (strlen(nam) != len) {
	rb_raise(rb_eArgError, "bad environment variable name");
    }
    env = getenv(nam);
    if (!env) {
	if (rb_block_given_p()) {
	    if (argc > 1) {
		rb_raise(rb_eArgError, "wrong # of arguments", argc);
	    }
	    return rb_yield(key);
	}
	if (argc == 1) {
	    rb_raise(rb_eIndexError, "key not found");
	}
	return if_none;
    }
    if (strcmp(nam, "PATH") == 0 && !rb_env_path_tainted())
	return rb_str_new2(env);
    return rb_tainted_str_new2(env);
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
	path_tainted_p(getenv("PATH"));
    }
    return path_tainted;
}

static int
envix(nam)
char *nam;
{
    register int i, len = strlen(nam);
    char **env;

    env = GET_ENVIRON(environ);
    for (i = 0; env[i]; i++) {
	if (
#ifdef WIN32
	    strnicmp(env[i],nam,len) == 0
#else
	    memcmp(env[i],nam,len) == 0
#endif
	    && env[i][len] == '=')
	    break;			/* memcmp must come first to avoid */
    }					/* potential SEGV's */
    FREE_ENVIRON(environ);
    return i;
}

void
ruby_setenv(name, value)
    const char *name;
    const char *value;
{
#if defined(WIN32) && !defined(__CYGWIN32__)
#ifdef USE_WIN32_RTL_ENV
    register char *envstr;
    STRLEN namlen = strlen(name);
    STRLEN vallen;
    char *oldstr = environ[envix(name)];

    /* putenv() has totally broken semantics in both the Borland
     * and Microsoft CRTLs.  They either store the passed pointer in
     * the environment without making a copy, or make a copy and don't
     * free it. And on top of that, they dont free() old entries that
     * are being replaced/deleted.  This means the caller must
     * free any old entries somehow, or we end up with a memory
     * leak every time setenv() is called.  One might think
     * one could directly manipulate environ[], like the UNIX code
     * above, but direct changes to environ are not allowed when
     * calling putenv(), since the RTLs maintain an internal
     * *copy* of environ[]. Bad, bad, *bad* stink.
     * GSAR 97-06-07
     */

    if (!value) {
	if (!oldstr)
	    return;
	value = "";
	vallen = 0;
    }
    else
	vallen = strlen(val);
    envstr = ALLOC_N(char, namelen + vallen + 3);
    sprintf(envstr,"%s=%s",name,value);
    putenv(envstr);
    if (oldstr) free(oldstr);
#ifdef _MSC_VER
    free(envstr);		/* MSVCRT leaks without this */
#endif

#else /* !USE_WIN32_RTL_ENV */

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
     */
    SetEnvironmentVariable(name,value);
#endif

#elif defined __CYGWIN__
#undef setenv
#undef unsetenv
    if (value)
	setenv(name,value,1);
    else
	unsetenv(name);
#else  /* WIN32 */

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
    if (!value) {
	if (environ != origenviron) {
	    char **envp = origenviron;
	    while (*envp && *envp != environ[i]) envp++;
	    if (!*envp)
		free(environ[i]);
	}
	while (environ[i]) {
	    environ[i] = environ[i+1];
	    i++;
	}
	return;
    }
    if (!environ[i]) {			/* does not exist yet */
	REALLOC_N(environ, char*, i+2);	/* just expand it a bit */
	environ[i+1] = 0;	/* make sure it's null terminated */
    }
    else {
	if (environ[i] != origenviron[i])
	    free(environ[i]);
    }
    environ[i] = ALLOC_N(char, strlen(name) + strlen(value) + 2);
#ifndef MSDOS
    sprintf(environ[i],"%s=%s",name,value); /* all that work just for this */
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
rb_f_setenv(obj, nm, val)
    VALUE obj, nm, val;
{
    char *name, *value;
    int nlen, vlen;

    if (rb_safe_level() >= 4) {
	rb_raise(rb_eSecurityError, "cannot change environment variable");
    }

    if (NIL_P(val)) {
	env_delete(obj, nm);
	return Qnil;
    }

    name = rb_str2cstr(nm, &nlen);
    value = rb_str2cstr(val, &vlen);
    if (strlen(name) != nlen)
	rb_raise(rb_eArgError, "bad environment variable name");
    if (strlen(value) != vlen)
	rb_raise(rb_eArgError, "bad environment variable value");

    ruby_setenv(name, value);
    if (strcmp(name, "PATH") == 0) {
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
    VALUE ary = rb_ary_new();

    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, rb_tainted_str_new(*env, s-*env));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return ary;
}

static VALUE
env_each_key(hash)
    VALUE hash;
{
    char **env;

    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_yield(rb_tainted_str_new(*env, s-*env));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return Qnil;
}

static VALUE
env_values()
{
    char **env;
    VALUE ary = rb_ary_new();

    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, rb_tainted_str_new2(s+1));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return ary;
}

static VALUE
env_each_value(hash)
    VALUE hash;
{
    char **env;

    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_yield(rb_tainted_str_new2(s+1));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return Qnil;
}

static VALUE
env_each(hash)
    VALUE hash;
{
    char **env;

    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_yield(rb_assoc_new(rb_tainted_str_new(*env, s-*env),
				  rb_tainted_str_new2(s+1)));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return Qnil;
}

static VALUE
env_reject_bang()
{
    volatile VALUE keys;
    VALUE *ptr;
    int len, del = 0;

    rb_secure(4);
    keys = env_keys();
    ptr = RARRAY(keys)->ptr;
    len = RARRAY(keys)->len; 

    while (len--) {
	VALUE val = rb_f_getenv(Qnil, *ptr);
	if (!NIL_P(val)) {
	    if (RTEST(rb_yield(rb_assoc_new(*ptr, val)))) {
		env_delete(Qnil, *ptr);
		del++;
	    }
	}
	ptr++;
    }
    if (del == 0) return Qnil;
    return envtbl;
}

static VALUE
env_delete_if()
{
    env_reject_bang();
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
    VALUE str = rb_str_new2("{");
    VALUE i;

    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');

	if (env != environ) {
	    rb_str_cat2(str, ", ");
	}
	if (s) {
	    rb_str_cat2(str, "\"");
	    rb_str_cat(str, *env, s-*env);
	    rb_str_cat2(str, "\"=>");
	    i = rb_inspect(rb_str_new2(s+1));
	    rb_str_append(str, i);
	}
	env++;
    }
    FREE_ENVIRON(environ);
    rb_str_cat2(str, "}");
    OBJ_TAINT(str);

    return str;
}

static VALUE
env_to_a()
{
    char **env;
    VALUE ary = rb_ary_new();

    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, rb_assoc_new(rb_tainted_str_new(*env, s-*env),
					  rb_tainted_str_new2(s+1)));
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
    if (TYPE(key) != T_STRING) return Qfalse;
    if (getenv(STR2CSTR(key))) return Qtrue;
    return Qfalse;
}

static VALUE
env_has_value(dmy, value)
    VALUE dmy, value;
{
    char **env;

    if (TYPE(value) != T_STRING) return Qfalse;
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=')+1;
	if (s) {
	    if (strncmp(s, RSTRING(value)->ptr, strlen(s)) == 0) {
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

    if (TYPE(value) != T_STRING) return Qnil;
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=')+1;
	if (s) {
	    if (strncmp(s, RSTRING(value)->ptr, strlen(s)) == 0) {
		str = rb_tainted_str_new(*env, s-*env-1);
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

    for (i=0;i<argc;i++) {
	char *v = 0;
	if (TYPE(argv[i]) == T_STRING) {
	    v = getenv(RSTRING(argv[i])->ptr);
	}
	if (v) {
	    RARRAY(indexes)->ptr[i] = rb_tainted_str_new2(v);
	}
	else {
	    RARRAY(indexes)->ptr[i] = Qnil;
	}
	RARRAY(indexes)->len = i+1;
    }

    return indexes;
}

static VALUE
env_to_hash()
{
    char **env;
    VALUE hash = rb_hash_new();

    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_hash_aset(hash, rb_tainted_str_new(*env, s-*env),
			       rb_tainted_str_new2(s+1));
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

void
Init_Hash()
{
    hash = rb_intern("hash");

    rb_cHash = rb_define_class("Hash", rb_cObject);

    rb_include_module(rb_cHash, rb_mEnumerable);

    rb_define_singleton_method(rb_cHash, "new", rb_hash_s_new, -1);
    rb_define_singleton_method(rb_cHash, "[]", rb_hash_s_create, -1);
    rb_define_method(rb_cHash,"initialize", rb_hash_initialize, -1);

    rb_define_method(rb_cHash,"clone", rb_hash_clone, 0);
    rb_define_method(rb_cHash,"rehash", rb_hash_rehash, 0);

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
    rb_define_method(rb_cHash,"index", rb_hash_index, 1);
    rb_define_method(rb_cHash,"indexes", rb_hash_indexes, -1);
    rb_define_method(rb_cHash,"indices", rb_hash_indexes, -1);
    rb_define_method(rb_cHash,"size", rb_hash_size, 0);
    rb_define_method(rb_cHash,"length", rb_hash_size, 0);
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
    rb_define_method(rb_cHash,"reject", rb_hash_reject, 0);
    rb_define_method(rb_cHash,"reject!", rb_hash_reject_bang, 0);
    rb_define_method(rb_cHash,"clear", rb_hash_clear, 0);
    rb_define_method(rb_cHash,"invert", rb_hash_invert, 0);
    rb_define_method(rb_cHash,"update", rb_hash_update, 1);
    rb_define_method(rb_cHash,"replace", rb_hash_replace, 1);

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
    rb_define_singleton_method(envtbl,"[]=", rb_f_setenv, 2);
    rb_define_singleton_method(envtbl,"store", rb_f_setenv, 2);
    rb_define_singleton_method(envtbl,"each", env_each, 0);
    rb_define_singleton_method(envtbl,"each_pair", env_each, 0);
    rb_define_singleton_method(envtbl,"each_key", env_each_key, 0);
    rb_define_singleton_method(envtbl,"each_value", env_each_value, 0);
    rb_define_singleton_method(envtbl,"delete", env_delete_m, 1);
    rb_define_singleton_method(envtbl,"delete_if", env_delete_if, 0);
    rb_define_singleton_method(envtbl,"reject", env_reject, 0);
    rb_define_singleton_method(envtbl,"reject!", env_reject_bang, 0);
    rb_define_singleton_method(envtbl,"to_s", env_to_s, 0);
    rb_define_singleton_method(envtbl,"inspect", env_inspect, 0);
    rb_define_singleton_method(envtbl,"rehash", env_none, 0);
    rb_define_singleton_method(envtbl,"to_a", env_to_a, 0);
    rb_define_singleton_method(envtbl,"index", env_index, 1);
    rb_define_singleton_method(envtbl,"indexes", env_indexes, -1);
    rb_define_singleton_method(envtbl,"indices", env_indexes, -1);
    rb_define_singleton_method(envtbl,"size", env_size, 0);
    rb_define_singleton_method(envtbl,"length", env_size, 0);
    rb_define_singleton_method(envtbl,"empty?", env_empty_p, 0);
    rb_define_singleton_method(envtbl,"keys", env_keys, 0);
    rb_define_singleton_method(envtbl,"values", env_values, 0);
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
