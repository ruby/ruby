/************************************************

  variable.c -

  $Author: matz $
  $Date: 1995/01/12 08:54:53 $
  created at: Tue Apr 19 23:55:15 JST 1994

************************************************/

#include "ruby.h"
#include "env.h"
#include "st.h"

st_table *rb_global_tbl;
st_table *rb_class_tbl;
#define global_tbl rb_global_tbl
#define class_tbl rb_class_tbl

VALUE rb_const_defined();
VALUE rb_const_get();

st_table *
new_idhash()
{
    return st_init_table(ST_NUMCMP, ST_NUMHASH);
}

void
Init_var_tables()
{
    global_tbl = new_idhash();
    class_tbl = new_idhash();
}

char *
rb_class2path(class)
    VALUE class;
{
    VALUE path;

    while (TYPE(class) == T_ICLASS) {
	class = (VALUE)RCLASS(class)->super;
    }
    path = rb_ivar_get(class, rb_intern("__classpath__"));
    if (TYPE(path) != T_STRING) Bug("class path does not set properly");
    return RSTRING(path)->ptr;
}

VALUE
rb_class_path(class)
    VALUE class;
{
    char *name = rb_class2path(class);

    if (strchr(name, ':')) {
	VALUE ary = str_split(str_new2(name), ":");
	ary_pop(ary);
	ary = ary_reverse(ary);
	return ary_join(ary, str_new2("::"));
    }
    return str_new2(name);
}

void
rb_set_class_path(class, under, name)
    VALUE class, under;
    char *name;
{
    VALUE str;
    char *s;

    str = str_new2(name);
    if (under) {
	str_cat(str, ":", 1);
	s = rb_class2path(under);
	str_cat(str, s, strlen(s));
    }
    rb_ivar_set(class, rb_intern("__classpath__"), str);
}

VALUE
rb_path2class(path)
    char *path;
{
    char *p, *name, *s;
    ID id;
    VALUE class;

    p = path;
    while (*p) {
	if (*p == ':') break;
	*p++;
    }
    if (*p == '\0') {		/* pre-defined class */
	if (!st_lookup(class_tbl, rb_intern(path), &class)) {
	    Fail("Undefined class -- %s", path);
	}
	return class;
    }
    class = rb_path2class(p+1);
    name = ALLOCA_N(char, p-path+1);
    s = name;
    while (path<p) {
	*s++ = *path++;
    }
    *s = '\0';
    id = rb_intern(name);
    if (!rb_const_defined(class, id))
	Fail("%s not defined", name);
    class = rb_const_get(class, id);
    switch (TYPE(class)) {
      case T_CLASS:
      case T_MODULE:
	break;
      default:
	Fail("%s not a module/class");
    }
    return class;
}

void
rb_name_class(class, id)
    VALUE class;
    ID id;
{
    rb_ivar_set(class, rb_intern("__classname__"), INT2FIX(id));
}

static st_table *autoload_tbl = 0;

static void
rb_autoload_id(id, filename)
    ID id;
    char *filename;
{
    if (!autoload_tbl) {
	autoload_tbl = new_idhash();
    }
    st_insert(autoload_tbl, id, strdup(filename));
}

void
rb_autoload(class, filename)
    char *class, *filename;
{
    rb_autoload_id(rb_intern(class), filename);
}

VALUE
f_autoload(obj, class, file)
    VALUE obj, class;
    struct RString *file;
{
    ID id = rb_to_id(class);

    Check_Type(file, T_STRING);
    rb_autoload_id(id, file->ptr);
    return Qnil;
}

char *
rb_class2name(class)
    struct RClass *class;
{
    int name;

    switch (TYPE(class)) {
      case T_ICLASS:
        class = (struct RClass*)RBASIC(class)->class;
	break;
      case T_CLASS:
      case T_MODULE:
	break;
      default:
	Fail("0x%x is not a class/module", class);
    }

    while (FL_TEST(class, FL_SINGLE) || TYPE(class) == T_ICLASS) {
	class = (struct RClass*)class->super;
    }

    name = rb_ivar_get(class, rb_intern("__classname__"));
    if (name) {
	name = FIX2INT(name);
	return rb_id2name((ID)name);
    }
    Bug("class 0x%x not named", class);
}

struct trace_var {
    void (*func)();
    void *data;
    struct trace_var *next;
};

struct global_entry {
    ID id;
    void *data;
    VALUE (*getter)();
    void  (*setter)();
    void  (*marker)();
    int block_trace;
    struct trace_var *trace;
};

static VALUE undef_getter();
static void  undef_setter();
static void  undef_marker();

static VALUE val_getter();
static void  val_setter();
static void  val_marker();

static VALUE var_getter();
static void  var_setter();
static void  var_marker();

struct global_entry*
rb_global_entry(id)
    ID id;
{
    struct global_entry *entry;

    if (!st_lookup(global_tbl, id, &entry)) {
	entry = ALLOC(struct global_entry);
	st_insert(global_tbl, id, entry);
	entry->id = id;
	entry->data = 0;
	entry->getter = undef_getter;
	entry->setter = undef_setter;
	entry->marker = undef_marker;

	entry->block_trace = 0;
	entry->trace = 0;
    }
    return entry;
}

static VALUE
undef_getter(id)
    ID id;
{
    Warning("global var %s not initialized", rb_id2name(id));
    return Qnil;
}

static void
undef_setter(val, id, data, entry)
    VALUE val;
    ID id;
    void *data;
    struct global_entry *entry;
{
    entry->getter = val_getter;
    entry->setter = val_setter;
    entry->marker = val_marker;

    entry->data = (void*)val;
}

static void
undef_marker()
{
}

static VALUE
val_getter(id, val)
    ID id;
    VALUE val;
{
    return val;
}

static void
val_setter(val, id, data, entry)
    VALUE val;
    ID id;
    void *data;
    struct global_entry *entry;
{
    entry->data = (void*)val;
}

static void
val_marker(data)
    void *data;
{
    if (data) gc_mark_maybe(data);
}

static VALUE
var_getter(id, var)
    ID id;
    VALUE *var;
{
    if (!var || !*var) return Qnil;
    return *var;
}

static void
var_setter(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    *var = val;
}

static void
var_marker(var)
    VALUE **var;
{
    if (var) gc_mark_maybe(*var);
}

static void
readonly_setter(id, var, val)
    ID id;
    void *var;
    VALUE val;
{
    Fail("Can't set variable %s", rb_id2name(id));
}

static int
mark_global_entry(key, entry)
    ID key;
    struct global_entry *entry;
{
    struct trace_var *trace;

    (*entry->marker)(entry->data);
    trace = entry->trace;
    while (trace) {
	if (trace->data) gc_mark_maybe(trace->data);
	trace = trace->next;
    }
    return ST_CONTINUE;
}

void
gc_mark_global_tbl()
{
    st_foreach(global_tbl, mark_global_entry, 0);
}

static ID
global_id(name)
    char *name;
{
    ID id;

    if (name[0] == '$') id = rb_intern(name);
    else {
	char *buf = ALLOCA_N(char, strlen(name)+2);
	buf[0] = '$';
	strcpy(buf+1, name);
	id = rb_intern(buf);
    }
    return id;
}

void
rb_define_hooked_variable(name, var, getter, setter)
    char  *name;
    VALUE *var;
    VALUE (*getter)();
    void  (*setter)();
{
    struct global_entry *entry;
    ID id = global_id(name);

    entry = rb_global_entry(id);
    entry->data = (void*)var;
    entry->getter = getter?getter:var_getter;
    entry->setter = setter?setter:var_setter;
    entry->marker = var_marker;
}

void
rb_define_variable(name, var)
    char  *name;
    VALUE *var;
{
    rb_define_hooked_variable(name, var, 0, 0);
}

void
rb_define_readonly_variable(name, var)
    char  *name;
    VALUE *var;
{
    rb_define_hooked_variable(name, var, 0, readonly_setter);
}

void
rb_define_virtual_variable(name, getter, setter)
    char  *name;
    VALUE (*getter)();
    void  (*setter)();
{
    if (!getter) getter = val_getter;
    if (!setter) setter = readonly_setter;
    rb_define_hooked_variable(name, 0, getter, setter);
}

void rb_trace_eval();

void
rb_trace_eval(cmd, val)
    VALUE cmd, val;
{
    rb_eval_cmd(cmd, ary_new3(1, val));
}

VALUE
f_trace_var(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE var, cmd;
    ID id;
    struct global_entry *entry;
    struct trace_var *trace;

    if (rb_scan_args(argc, argv, "11", &var, &cmd) == 1) {
	cmd = f_lambda();
    }
    id = rb_to_id(var);
    if (!st_lookup(global_tbl, id, &entry)) {
	Fail("undefined global variable %s", rb_id2name(id));
    }
    trace = ALLOC(struct trace_var);
    trace->next = entry->trace;
    trace->func = rb_trace_eval;
    trace->data = (void*)cmd;
    entry->trace = trace;

    return Qnil;
}

VALUE
f_untrace_var(obj, var)
    VALUE obj, var;
{
    ID id;
    struct global_entry *entry;
    struct trace_var *trace;
    VALUE ary;

    id = rb_to_id(var);
    if (!st_lookup(global_tbl, id, &entry)) {
	Fail("undefined global variable %s", rb_id2name(id));
    }
    ary = ary_new();
    trace = entry->trace;
    while (trace) {
	struct trace_var *next = trace->next;
	ary_push(ary, trace->data);
	free(trace);
	trace = next;
    }
    entry->trace = 0;

    return ary;
}

VALUE
rb_gvar_get(entry)
    struct global_entry *entry;
{
    return (*entry->getter)(entry->id, entry->data, entry);
}

struct trace_data {
    struct trace_var *trace;
    VALUE val;
};
    
static void
trace_ev(data)
    struct trace_data *data;
{
    struct trace_var *trace = data->trace;

    while (trace) {
	(*trace->func)(trace->data, data->val);
	trace = trace->next;
    }
}

static void
trace_en(entry)
    struct global_entry *entry;
{
    entry->block_trace = 0;
}

VALUE
rb_gvar_set(entry, val)
    struct global_entry *entry;
    VALUE val;
{
    struct trace_data trace;

    (*entry->setter)(val, entry->id, entry->data, entry);

    if (!entry->block_trace) {
	entry->block_trace = 1;
	trace.trace = entry->trace;
	trace.val = val;
	rb_ensure(trace_ev, &trace, trace_en, entry);
    }
    return val;
}

VALUE
rb_gvar_set2(name, val)
    char *name;
    VALUE val;
{
    struct global_entry *entry;

    entry = rb_global_entry(global_id(name));
    return rb_gvar_set(entry, val);
}

VALUE
rb_gvar_defined(entry)
    struct global_entry *entry;
{
    if (entry->getter == undef_getter) return FALSE;
    return TRUE;
}

VALUE
rb_ivar_get(obj, id)
    struct RObject *obj;
    ID id;
{
    VALUE val;

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (obj->iv_tbl && st_lookup(obj->iv_tbl, id, &val))
	    return val;
	return Qnil;
      default:
	Fail("class %s can not have instance variables",
	     rb_class2name(CLASS_OF(obj)));
	break;
    }
    Warning("instance var %s not initialized", rb_id2name(id));
    return Qnil;
}

VALUE
rb_ivar_set(obj, id, val)
    struct RObject *obj;
    ID id;
    VALUE val;
{
    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (!obj->iv_tbl) obj->iv_tbl = new_idhash();
	st_insert(obj->iv_tbl, id, val);
	break;
      default:
	Fail("class %s can not have instance variables",
	     rb_class2name(CLASS_OF(obj)));
	break;
    }
    return val;
}

VALUE
rb_ivar_defined(obj, id)
    struct RObject *obj;
    ID id;
{
    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (obj->iv_tbl && st_lookup(obj->iv_tbl, id, 0))
	    return TRUE;
	break;
    }
    return FALSE;
}

VALUE
rb_const_get(class, id)
    struct RClass *class;
    ID id;
{
    VALUE value;
    struct RClass *tmp;

    tmp = class;
    while (tmp) {
	if (tmp->iv_tbl && st_lookup(tmp->iv_tbl, id, &value)) {
	    return value;
	}
	tmp = tmp->super;
    }
    if (BUILTIN_TYPE(class) == T_MODULE) {
	return rb_const_get(cObject, id);
    }

    /* pre-defined class */
    if (st_lookup(class_tbl, id, &value)) return value;

    /* autoload */
    if (autoload_tbl && st_lookup(autoload_tbl, id, 0)) {
	char *modname;
	VALUE module;

	st_delete(autoload_tbl, &id, &modname);
	module = str_new2(modname);
	free(modname);
	f_require(Qnil, module);
	return rb_const_get(class, id);
    }

    /* Uninitialized constant */
    if (class && (VALUE)class != cObject)
	Fail("Uninitialized constant %s::%s",
	     RSTRING(rb_class_path(class))->ptr,
	     rb_id2name(id));
    else
	Fail("Uninitialized constant %s",rb_id2name(id));
    /* not reached */
}

VALUE
rb_const_defined(class, id)
    struct RClass *class;
    ID id;
{
    while (class) {
	if (class->iv_tbl && st_lookup(class->iv_tbl, id, 0)) {
	    return TRUE;
	}
	class = class->super;
    }
    if (st_lookup(class_tbl, id, 0))
	return TRUE;
    if (autoload_tbl && st_lookup(autoload_tbl, id, 0))
	return TRUE;
    return FALSE;
}

void
rb_const_set(class, id, val)
    struct RClass *class;
    ID id;
    VALUE val;
{
    if (rb_const_defined(class, id))
	Fail("already initialized constnant %s", rb_id2name(id));

    if (!class->iv_tbl) class->iv_tbl = new_idhash();
    st_insert(class->iv_tbl, id, val);
}

void
rb_define_const(class, name, val)
    struct RClass *class;
    char *name;
    VALUE val;
{
    rb_const_set(class, rb_intern(name), val);
}

VALUE
rb_iv_get(obj, name)
    VALUE obj;
    char *name;
{
    ID id = rb_intern(name);

    return rb_ivar_get(obj, id);
}

VALUE
rb_iv_set(obj, name, val)
    VALUE obj;
    char *name;
    VALUE val;
{
    ID id = rb_intern(name);

    return rb_ivar_set(obj, id, val);
}

VALUE
backref_get()
{
    int cnt, max;

    if (!the_scope->local_vars) return Qnil;
    for (cnt=1, max=the_scope->local_tbl[0]+1; cnt<max ;cnt++) {
	if (the_scope->local_tbl[cnt] == '~') {
	    cnt--;
	    if (the_scope->local_vars[cnt]) 
		return the_scope->local_vars[cnt];
	    else
		return 1;
	}
    }
    return Qnil;
}

void
backref_set(val)
    VALUE val;
{
    int cnt, max;

    for (cnt=1, max=the_scope->local_tbl[0]+1; cnt<max ;cnt++) {
	if (the_scope->local_tbl[cnt] == '~') break;
    }
    the_scope->local_vars[cnt-1] = val;
}
