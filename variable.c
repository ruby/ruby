/************************************************

  variable.c -

  $Author$
  $Date$
  created at: Tue Apr 19 23:55:15 JST 1994

************************************************/

#include "ruby.h"
#include "env.h"
#include "node.h"
#include "st.h"

static st_table *rb_global_tbl;
st_table *rb_class_tbl;
#define global_tbl rb_global_tbl
#define class_tbl rb_class_tbl

int rb_const_defined();

st_table*
new_idhash()
{
    return st_init_numtable();
}

void
Init_var_tables()
{
    global_tbl = new_idhash();
    class_tbl = new_idhash();
}

struct fc_result {
    ID name;
    VALUE klass;
    VALUE path;
    VALUE track;
    struct fc_result *prev;
};

extern VALUE cModule;

static int
fc_i(key, value, res)
    ID key;
    VALUE value;
    struct fc_result *res;
{
    VALUE path;
    char *name;
    
    if (!rb_is_const_id(key)) return ST_CONTINUE;

    name = rb_id2name(key);
    if (res->path) {
	path = str_dup(res->path);
	str_cat(path, "::", 2);
	str_cat(path, name, strlen(name));
    }
    else {
	path = str_new2(name);
    }
    if (value == res->klass) {
	res->name = key;
	res->path = path;
	return ST_STOP;
    }
    if (obj_is_kind_of(value, cModule)) {
	struct fc_result arg;
	struct fc_result *list;


	if (!RCLASS(value)->iv_tbl) return ST_CONTINUE;

	list = res;
	while (list) {
	    if (list->track == value) return ST_CONTINUE;
	    list = list->prev;
	}

	arg.name = 0;
	arg.path = path;
	arg.klass = res->klass;
	arg.track = value;
	arg.prev = res;
	st_foreach(RCLASS(value)->iv_tbl, fc_i, &arg);
	if (arg.name) {
	    res->name = arg.name;
	    res->path = arg.path;
	    return ST_STOP;
	}
    }
    return ST_CONTINUE;
}

static VALUE
find_class_path(cls)
    VALUE cls;
{
    struct fc_result arg;

    arg.name = 0;
    arg.path = 0;
    arg.klass = cls;
    arg.track = cObject;
    arg.prev = 0;
    if (RCLASS(cObject)->iv_tbl) {
	st_foreach(RCLASS(cObject)->iv_tbl, fc_i, &arg);
    }
    if (arg.name == 0) {
	st_foreach(class_tbl, fc_i, &arg);
    }
    if (arg.name) {
	rb_iv_set(cls, "__classpath__", arg.path);
	return arg.path;
    }
    return Qnil;
}

static VALUE
classname(cls)
    VALUE cls;
{
    VALUE path;

    while (TYPE(cls) == T_ICLASS || FL_TEST(cls, FL_SINGLETON)) {
	cls = (VALUE)RCLASS(cls)->super;
    }
    path = rb_iv_get(cls, "__classpath__");
    if (NIL_P(path)) {
	path = rb_iv_get(cls, "__classid__");
	if (!NIL_P(path)) {
	    path = str_new2(rb_id2name(FIX2INT(path)));
	}
    }
    if (NIL_P(path)) {
	path = find_class_path(cls);
	if (NIL_P(path)) {
	    return 0;
	}
	return path;
    }
    if (TYPE(path) != T_STRING) Bug("class path is not set properly");
    return path;
}

VALUE
mod_name(mod)
    VALUE mod;
{
    VALUE path = classname(mod);

    if (path) return path;
    return str_new(0,0);
}

VALUE
rb_class_path(cls)
    VALUE cls;
{
    VALUE path = classname(cls);

    if (path) return path;
    else {
	char buf[256];
	char *s = "Class";

	if (TYPE(cls) == T_MODULE) s = "Module";
	sprintf(buf, "#<%s 0x%x>", s, cls);
	return str_new2(buf);
    }
}

void
rb_set_class_path(cls, under, name)
    VALUE cls, under;
    char *name;
{
    VALUE str;

    if (under == cObject) {
	str = str_new2(name);
    }
    else {
	str = str_dup(rb_class_path(under));
	str_cat(str, "::", 2);
	str_cat(str, name, strlen(name));
    }
    rb_iv_set(cls, "__classpath__", str);
}

VALUE
rb_path2class(path)
    char *path;
{
    if (path[0] == '#') {
	ArgError("can't retrieve anonymous class %s", path);
    }
    return rb_eval_string(path);
}

void
rb_name_class(cls, id)
    VALUE cls;
    ID id;
{
    extern VALUE cString;

    if (cString) {
	rb_iv_set(cls, "__classpath__", str_new2(rb_id2name(id)));
    }
    else {
	rb_iv_set(cls, "__classid__", INT2FIX(id));
    }
}

static st_table *autoload_tbl = 0;

static void
rb_autoload_id(id, filename)
    ID id;
    char *filename;
{
    if (!rb_is_const_id(id)) {
	NameError("autoload must be constant name", rb_id2name(id));
    }

    if (!autoload_tbl) {
	autoload_tbl = new_idhash();
    }
    st_insert(autoload_tbl, id, strdup(filename));
}

void
rb_autoload(cls, filename)
    char *cls, *filename;
{
    rb_autoload_id(rb_intern(cls), filename);
}

VALUE
f_autoload(obj, cls, file)
    VALUE obj, cls, file;
{
    ID id = rb_to_id(cls);

    Check_Type(file, T_STRING);
    rb_autoload_id(id, RSTRING(file)->ptr);
    return Qnil;
}

char *
rb_class2name(cls)
    VALUE cls;
{
    return RSTRING(rb_class_path(cls))->ptr;
}

struct trace_var {
    int removed;
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
    Warning("global variable `%s' not initialized", rb_id2name(id));
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
readonly_setter(val, id, var)
    VALUE val;
    ID id;
    void *var;
{
    NameError("Can't set variable %s", rb_id2name(id));
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

static void
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
    if (NIL_P(cmd)) {
	return f_untrace_var(argc, argv);
    }
    id = rb_to_id(var);
    if (!st_lookup(global_tbl, id, &entry)) {
	NameError("undefined global variable %s", rb_id2name(id));
    }
    trace = ALLOC(struct trace_var);
    trace->next = entry->trace;
    trace->func = rb_trace_eval;
    trace->data = (void*)cmd;
    trace->removed = 0;
    entry->trace = trace;

    return Qnil;
}

static void
remove_trace(entry)
    struct global_entry *entry;
{
    struct trace_var *trace = entry->trace;
    struct trace_var t;
    struct trace_var *next;

    t.next = trace;
    trace = &t;
    while (trace->next) {
	next = trace->next;
	if (next->removed) {
	    trace->next = next->next;
	    free(next);
	}
	trace = next;
    }
    entry->trace = t.next;
}

VALUE
f_untrace_var(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE var, cmd;
    ID id;
    struct global_entry *entry;
    struct trace_var *trace;

    rb_scan_args(argc, argv, "11", &var, &cmd);
    id = rb_to_id(var);
    if (!st_lookup(global_tbl, id, &entry)) {
	NameError("undefined global variable %s", rb_id2name(id));
    }
    if (NIL_P(cmd)) {
	VALUE ary = ary_new();

	trace = entry->trace;
	while (trace) {
	    struct trace_var *next = trace->next;
	    ary_push(ary, (VALUE)trace->data);
	    trace->removed = 1;
	    trace = next;
	}
	entry->trace = 0;

	if (!entry->block_trace) remove_trace(entry);
	return ary;
    }
    else {
	while (trace) {
	    if (trace->data == (void*)cmd) {
		trace->removed = 1;
		if (!entry->block_trace) remove_trace(entry);
		return ary_new3(1, cmd);
	    }
	    trace = trace->next;
	}
    }
    return Qnil;
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
    remove_trace(entry);
}

VALUE
rb_gvar_set(entry, val)
    struct global_entry *entry;
    VALUE val;
{
    struct trace_data trace;

    if (rb_safe_level() >= 4) {
	extern VALUE eSecurityError;
	Raise(eSecurityError, "cannot change global variable value");
    }
    (*entry->setter)(val, entry->id, entry->data, entry);

    if (entry->trace && !entry->block_trace) {
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

static int
gvar_i(key, entry, ary)
    ID key;
    struct global_entry *entry;
    VALUE ary;
{
    ary_push(ary, str_new2(rb_id2name(entry->id)));
    return ST_CONTINUE;
}

VALUE
f_global_variables()
{
    VALUE ary = ary_new();
    char buf[3];
    char *s = "^&`'+123456789";

    st_foreach(global_tbl, gvar_i, ary);
    while (*s) {
	sprintf(buf, "$%c", *s++);
	ary_push(ary, str_new2(buf));
    }
    return ary;
}

void
rb_alias_variable(name1, name2)
    ID name1;
    ID name2;
{
    struct global_entry *entry1, *entry2;

    entry1 = rb_global_entry(name1);
    entry2 = rb_global_entry(name2);

    entry1->data   = entry2->data;
    entry1->getter = entry2->getter;
    entry1->setter = entry2->setter;
    entry1->marker = entry2->marker;
}

VALUE
rb_ivar_get(obj, id)
    VALUE obj;
    ID id;
{
    VALUE val;

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (ROBJECT(obj)->iv_tbl && st_lookup(ROBJECT(obj)->iv_tbl, id, &val))
	    return val;
	return Qnil;
      default:
	TypeError("class %s can not have instance variables",
		  rb_class2name(CLASS_OF(obj)));
	break;
    }
    Warning("instance var %s not initialized", rb_id2name(id));
    return Qnil;
}

VALUE
rb_ivar_set(obj, id, val)
    VALUE obj;
    ID id;
    VALUE val;
{
    if (rb_safe_level() >= 5) {
	extern VALUE eSecurityError;
	Raise(eSecurityError, "cannot change object status");
    }
    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (!ROBJECT(obj)->iv_tbl) ROBJECT(obj)->iv_tbl = new_idhash();
	st_insert(ROBJECT(obj)->iv_tbl, id, val);
	break;
      default:
	TypeError("class %s can not have instance variables",
		  rb_class2name(CLASS_OF(obj)));
	break;
    }
    return val;
}

VALUE
rb_ivar_defined(obj, id)
    VALUE obj;
    ID id;
{
    if (!rb_is_instance_id(id)) return FALSE;

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (ROBJECT(obj)->iv_tbl && st_lookup(ROBJECT(obj)->iv_tbl, id, 0))
	    return TRUE;
	break;
    }
    return FALSE;
}

static int
ivar_i(key, value, hash)
    ID key;
    VALUE value;
    VALUE hash;
{
    if (rb_is_instance_id(key)) {
	hash_aset(hash, str_new2(rb_id2name(key)), value);
    }
    return ST_CONTINUE;
}

VALUE
obj_instance_variables(obj)
    VALUE obj;
{
    VALUE hash = hash_new();

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (ROBJECT(obj)->iv_tbl) {
	    st_foreach(ROBJECT(obj)->iv_tbl, ivar_i, hash);
	}
	break;
      default:
       break;
    }
    return hash;
}

VALUE
obj_remove_instance_variable(obj, name)
    VALUE obj, name;
{
    VALUE val;
    ID id = rb_to_id(name);

    if (rb_ivar_defined(obj, id)) {
	NameError("`%s' is not an instance variable", rb_id2name(id));
    }

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (ROBJECT(obj)->iv_tbl) {
	    st_delete(ROBJECT(obj)->iv_tbl, &id, &val);
	}
	break;
      default:
	TypeError("object %s can not have instance variables",
		  rb_class2name(CLASS_OF(obj)));
	break;
    }
    return obj;
}

VALUE
rb_const_get_at(cls, id)
    VALUE cls;
    ID id;
{
    VALUE value;

    if (RCLASS(cls)->iv_tbl && st_lookup(RCLASS(cls)->iv_tbl, id, &value)) {
	return value;
    }
    if (cls == cObject) {
	return rb_const_get(cls, id);
    }
    NameError("Uninitialized constant %s::%s",
	      RSTRING(rb_class_path(cls))->ptr,
	      rb_id2name(id));
    /* not reached */
}


VALUE
rb_const_get(cls, id)
    VALUE cls;
    ID id;
{
    VALUE value;
    VALUE tmp;

    tmp = cls;
    while (tmp) {
	if (RCLASS(tmp)->iv_tbl && st_lookup(RCLASS(tmp)->iv_tbl,id,&value)) {
	    return value;
	}
	tmp = RCLASS(tmp)->super;
    }
    if (BUILTIN_TYPE(cls) == T_MODULE) {
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
	f_require(0, module);
	return rb_const_get(cls, id);
    }

    /* Uninitialized constant */
    if (cls && cls != cObject)
	NameError("Uninitialized constant %s::%s",
		  RSTRING(rb_class_path(cls))->ptr,
		  rb_id2name(id));
    else {
	NameError("Uninitialized constant %s",rb_id2name(id));
    }
    /* not reached */
}

static int
const_i(key, value, ary)
    ID key;
    VALUE value;
    VALUE ary;
{
    if (rb_is_const_id(key)) {
	VALUE kval = str_new2(rb_id2name(key));
	if (!ary_includes(ary, kval)) {
	    ary_push(ary, kval);
	}
    }
    return ST_CONTINUE;
}

static int
autoload_i(key, name, ary)
    ID key;
    char *name;
    VALUE ary;
{
    VALUE kval = str_new2(rb_id2name(key));
    if (!ary_includes(ary, kval)) {
	ary_push(ary, kval);
    }
    return ST_CONTINUE;
}

VALUE
mod_const_at(mod, ary)
    VALUE mod, ary;
{
    if (RCLASS(mod)->iv_tbl) {
	st_foreach(RCLASS(mod)->iv_tbl, const_i, ary);
    }
    if ((VALUE)mod == cObject) {
	st_foreach(class_tbl, const_i, ary);
	if (autoload_tbl) {
	    st_foreach(autoload_tbl, autoload_i, ary);
	}
    }
    return ary;
}

VALUE
mod_constants(mod)
    VALUE mod;
{
    return mod_const_at(mod, ary_new());
}

VALUE
mod_const_of(mod, ary)
    VALUE mod;
    VALUE ary;
{
    mod_const_at(mod, ary);
    for (;;) {
	mod = RCLASS(mod)->super;
	if (!mod) break;
	mod_const_at(mod, ary);
    }
    return ary;
}

int
rb_const_defined_at(cls, id)
    VALUE cls;
    ID id;
{
    if (RCLASS(cls)->iv_tbl && st_lookup(RCLASS(cls)->iv_tbl, id, 0)) {
	return TRUE;
    }
    if (cls == cObject) {
	return rb_const_defined(cls, id);
    }
    return FALSE;
}

int
rb_autoload_defined(id)
    ID id;
{
    if (autoload_tbl && st_lookup(autoload_tbl, id, 0))
	return TRUE;
    return FALSE;
}

int
rb_const_defined(cls, id)
    VALUE cls;
    ID id;
{
    while (cls) {
	if (RCLASS(cls)->iv_tbl && st_lookup(RCLASS(cls)->iv_tbl, id, 0)) {
	    return TRUE;
	}
	cls = RCLASS(cls)->super;
    }
    if (st_lookup(class_tbl, id, 0))
	return TRUE;
    return rb_autoload_defined(id);
}

void
rb_const_set(cls, id, val)
    VALUE cls;
    ID id;
    VALUE val;
{
    if (!RCLASS(cls)->iv_tbl) {
	RCLASS(cls)->iv_tbl = new_idhash();
    }
    else if (st_lookup(RCLASS(cls)->iv_tbl, id, 0)) {
	NameError("already initialized constant %s", rb_id2name(id));
    }

    st_insert(RCLASS(cls)->iv_tbl, id, val);
}

void
rb_define_const(cls, name, val)
    VALUE cls;
    char *name;
    VALUE val;
{
    ID id = rb_intern(name);
    if (!rb_is_const_id(id)) {
	NameError("wrong constant name %s", name);
    }
    rb_const_set(cls, id, val);
}

void
rb_define_global_const(name, val)
    char *name;
    VALUE val;
{
    rb_define_const(cObject, name, val);
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
