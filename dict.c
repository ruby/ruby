/************************************************

  dict.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:49 $
  created at: Mon Nov 22 18:51:18 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "st.h"

VALUE C_Dict, C_EnvDict;
static ID hash, eq;
VALUE Fgetenv(), Fsetenv();

static VALUE
rb_cmp(a, b)
    VALUE a, b;
{
    return rb_funcall(a, eq, 1, b)?0:1;
}

static VALUE
rb_hash(a, mod)
    VALUE a;
    int mod;
{
    return rb_funcall(a, hash, 0) % mod;
}

#define ASSOC_KEY(a) RARRAY(a)->ptr[0]
#define ASSOC_VAL(a) RARRAY(a)->ptr[1]

VALUE
Fdic_new(class)
    VALUE class;
{
    int i, max;
    NEWOBJ(dic, struct RDict);
    OBJSETUP(dic, class, T_DICT);

    GC_LINK;
    GC_PRO(dic);

    dic->tbl = st_init_table(rb_cmp, rb_hash);
    GC_UNLINK;

    return (VALUE)dic;
}

static VALUE
Fdic_clone(dic)
    struct RDict *dic;
{
    NEWOBJ(dic2, struct RDict);
    CLONESETUP(dic2, dic);

    GC_LINK;
    GC_PRO(dic2);

    dic2->tbl = (st_table*)st_copy(dic->tbl);

    GC_UNLINK;

    return (VALUE)dic2;
}

static VALUE
Fdic_aref(dic, key)
    struct RDict *dic;
    VALUE key;
{
    VALUE val = Qnil;

    if (!st_lookup(dic->tbl, key, &val)) {
	return Qnil;
    }
    return val;
}

static VALUE
Fdic_delete(dic, key)
    struct RDict *dic;
    VALUE key;
{
    VALUE val;

    if (st_delete(dic->tbl, &key, &val))
	return val;
    return Qnil;
}

static int
dic_delete_if(key, value)
    VALUE key, value;
{
    if (rb_yield(assoc_new(key, value)))
	return ST_DELETE;
    return ST_CONTINUE;
}

static VALUE
Fdic_delete_if(dic)
    struct RDict *dic;
{
    st_foreach(dic->tbl, dic_delete_if, Qnil);

    return (VALUE)dic;
}

static
dic_clear(key, value)
    VALUE key, value;
{
    return ST_DELETE;
}

static VALUE
Fdic_clear(dic)
    struct RDict *dic;
{
    st_foreach(dic->tbl, dic_clear, Qnil);

    return (VALUE)dic;
}

VALUE
Fdic_aset(dic, key, val)
    struct RDict *dic;
    VALUE key, val;
{
    if (val == Qnil) {
	Fdic_delete(dic, key);
	return Qnil;
    }
    st_insert(dic->tbl, key, val);
    return val;
}

static VALUE
Fdic_length(dic)
    struct RDict *dic;
{
    return INT2FIX(dic->tbl->num_entries);
}

static
dic_each(key, value)
    VALUE key, value;
{
    rb_yield(value);
    return ST_CONTINUE;
}

static VALUE
Fdic_each(dic)
    struct RDict *dic;
{
    st_foreach(dic->tbl, dic_each);
    return (VALUE)dic;
}

static
dic_each_key(key, value)
    VALUE key, value;
{
    rb_yield(key);
    return ST_CONTINUE;
}

static VALUE
Fdic_each_key(dic)
    struct RDict *dic;
{
    st_foreach(dic->tbl, dic_each_key);
    return (VALUE)dic;
}

static
dic_each_pair(key, value)
    VALUE key, value;
{
    rb_yield(assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
Fdic_each_pair(dic)
    struct RDict *dic;
{
    st_foreach(dic->tbl, dic_each_pair);
    return (VALUE)dic;
}

static
dic_to_a(key, value, ary)
    VALUE key, value, ary;
{
    Fary_push(ary, assoc_new(key, value));
    return ST_CONTINUE;
}

static VALUE
Fdic_to_a(dic)
    struct RDict *dic;
{
    VALUE ary;

    GC_LINK;
    GC_PRO3(ary, ary_new());
    st_foreach(dic->tbl, dic_to_a, ary);
    GC_UNLINK;

    return ary;
}

static
dic_inspect(key, value, str)
    VALUE key, value;
    struct RString *str;
{
    VALUE str2;
    ID inspect = rb_intern("_inspect");

    if (str->len > 1) {
	str_cat(str, ", ", 2);
    }
    GC_LINK;
    GC_PRO3(str2, rb_funcall(key, inspect, 0, Qnil));
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    str_cat(str, "=>", 2);
    str2 = rb_funcall(value, inspect, 0, Qnil);
    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    GC_UNLINK;

    return ST_CONTINUE;
}

static VALUE
Fdic_inspect(dic)
    struct RDict *dic;
{
    VALUE str;

    GC_LINK;
    GC_PRO3(str, str_new2("{"));
    st_foreach(dic->tbl, dic_inspect, str);
    str_cat(str, "}", 1);
    GC_UNLINK;

    return str;
}

static VALUE
Fdic_to_s(dic)
    VALUE dic;
{
    VALUE str;

    GC_LINK;
    GC_PRO(dic);
    dic = Fdic_to_a(dic);
    str = Fary_to_s(dic);
    GC_UNLINK;

    return str;
}

static
dic_keys(key, value, ary)
    VALUE key, value, ary;
{
    Fary_push(ary, key);
    return ST_CONTINUE;
}

static VALUE
Fdic_keys(dic)
    struct RDict *dic;
{
    VALUE ary;

    GC_LINK;
    GC_PRO3(ary, ary_new());
    st_foreach(dic->tbl, dic_keys, ary);
    GC_UNLINK;
    return ary;
}

static
dic_values(key, value, ary)
    VALUE key, value, ary;
{
    Fary_push(ary, key);
    return ST_CONTINUE;
}

static VALUE
Fdic_values(dic)
    struct RDict *dic;
{
    VALUE ary;

    GC_LINK;
    GC_PRO3(ary, ary_new());
    st_foreach(dic->tbl, dic_values, ary);
    GC_UNLINK;
    return ary;
}

static VALUE
Fdic_has_key(dic, key)
    struct RDict *dic;
    VALUE key;
{
    VALUE val;

    if (st_lookup(dic->tbl, key, &val))
	return TRUE;
    return FALSE;
}

static VALUE value_found;

static
dic_search_value(key, value, arg)
    VALUE key, value, arg;
{
    if (rb_funcall(value, eq, 1, arg)) {
	value_found = TRUE;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

static VALUE
Fdic_has_value(dic, val)
    struct RDict *dic;
    VALUE val;
{
    value_found = FALSE;
    st_foreach(dic->tbl, dic_search_value, val);
    return value_found;
}

char *index();
extern VALUE rb_readonly_hook();

extern char **environ;

static VALUE
Fenv_each(dic)
    VALUE dic;
{
    char **env;

    env = environ;
    while (*env) {
	VALUE var, val;
	char *s = index(*env, '=');

	GC_LINK;
	GC_PRO3(var, str_new(*env, s-*env));
	GC_PRO3(val, str_new2(s+1));
	rb_yield(assoc_new(var, val));
	GC_UNLINK;
	env++;
    }
    return dic;
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
    extern char *getenv();
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

Init_Dict()
{
    extern VALUE C_Kernel;
    extern VALUE M_Enumerable;
    static VALUE envtbl;

    hash = rb_intern("hash");
    eq   = rb_intern("==");

    C_Dict = rb_define_class("Dict", C_Object);
    rb_name_class(C_Dict, rb_intern("Hash")); /* alias */

    rb_include_module(C_Dict, M_Enumerable);

    rb_define_single_method(C_Dict, "new", Fdic_new, 0);

    rb_define_method(C_Dict,"clone",  Fdic_clone, 0);

    rb_define_method(C_Dict,"to_a",  Fdic_to_a, 0);
    rb_define_method(C_Dict,"to_s",  Fdic_to_s, 0);
    rb_define_method(C_Dict,"_inspect",  Fdic_inspect, 0);

    rb_define_method(C_Dict,"[]",  Fdic_aref, 1);
    rb_define_method(C_Dict,"[]=", Fdic_aset, 2);
    rb_define_method(C_Dict,"length", Fdic_length, 0);
    rb_define_method(C_Dict,"each", Fdic_each, 0);
    rb_define_method(C_Dict,"each_value", Fdic_each, 0);
    rb_define_method(C_Dict,"each_key", Fdic_each_key, 0);
    rb_define_method(C_Dict,"each_pair", Fdic_each_pair, 0);

    rb_define_method(C_Dict,"keys", Fdic_keys, 0);
    rb_define_method(C_Dict,"values", Fdic_values, 0);

    rb_define_method(C_Dict,"delete", Fdic_delete, 1);
    rb_define_method(C_Dict,"delete_if", Fdic_delete_if, 0);
    rb_define_method(C_Dict,"clear", Fdic_clear, 0);

    rb_define_method(C_Dict,"includes", Fdic_has_key, 1);
    rb_define_method(C_Dict,"has_key", Fdic_has_key, 1);
    rb_define_method(C_Dict,"has_value", Fdic_has_value, 1);


    C_EnvDict = rb_define_class("EnvDict", C_Object);

    rb_include_module(C_EnvDict, M_Enumerable);

    rb_define_method(C_EnvDict,"[]", Fgetenv, 1);
    rb_define_method(C_EnvDict,"[]=", Fsetenv, 2);
    rb_define_method(C_EnvDict,"each", Fenv_each, 0);
    rb_define_method(C_EnvDict,"delete", Fenv_delete, 1);
    envtbl = obj_alloc(C_EnvDict);
    rb_define_variable("$ENV", &envtbl, Qnil, rb_readonly_hook);

    rb_define_func(C_Kernel, "getenv", Fgetenv, 1);
    rb_define_func(C_Kernel, "setenv", Fsetenv, 2);
}
