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

#ifdef USE_CWGUSI
char* strdup(char*);
#endif

static st_table *rb_global_tbl;
st_table *rb_class_tbl;

void
Init_var_tables()
{
    rb_global_tbl = st_init_numtable();
    rb_class_tbl = st_init_numtable();
}

struct fc_result {
    ID name;
    VALUE klass;
    VALUE path;
    VALUE track;
    struct fc_result *prev;
};

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
	path = rb_str_dup(res->path);
	rb_str_cat(path, "::", 2);
	rb_str_cat(path, name, strlen(name));
    }
    else {
	path = rb_str_new2(name);
    }
    if (value == res->klass) {
	res->name = key;
	res->path = path;
	return ST_STOP;
    }
    if (rb_obj_is_kind_of(value, rb_cModule)) {
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
find_class_path(klass)
    VALUE klass;
{
    struct fc_result arg;

    arg.name = 0;
    arg.path = 0;
    arg.klass = klass;
    arg.track = rb_cObject;
    arg.prev = 0;
    if (RCLASS(rb_cObject)->iv_tbl) {
	st_foreach(RCLASS(rb_cObject)->iv_tbl, fc_i, &arg);
    }
    if (arg.name == 0) {
	st_foreach(rb_class_tbl, fc_i, &arg);
    }
    if (arg.name) {
	rb_iv_set(klass, "__classpath__", arg.path);
	return arg.path;
    }
    return Qnil;
}

static VALUE
classname(klass)
    VALUE klass;
{
    VALUE path;

    while (TYPE(klass) == T_ICLASS || FL_TEST(klass, FL_SINGLETON)) {
	klass = (VALUE)RCLASS(klass)->super;
    }
    if (!klass) klass = rb_cObject;
    path = rb_iv_get(klass, "__classpath__");
    if (NIL_P(path)) {
	ID classid = rb_intern("__classid__");

	path = rb_ivar_get(klass, classid);
	if (!NIL_P(path)) {
	    path = rb_str_new2(rb_id2name(FIX2INT(path)));
	    rb_ivar_set(klass, classid, path);
	    st_delete(RCLASS(klass)->iv_tbl, &classid, 0);
	}
    }
    if (NIL_P(path)) {
	path = find_class_path(klass);
	if (NIL_P(path)) {
	    return 0;
	}
	return path;
    }
    if (TYPE(path) != T_STRING)
	rb_bug("class path is not set properly");
    return path;
}

VALUE
rb_mod_name(mod)
    VALUE mod;
{
    VALUE path = classname(mod);

    if (path) return rb_str_dup(path);
    return rb_str_new(0,0);
}

VALUE
rb_class_path(klass)
    VALUE klass;
{
    VALUE path = classname(klass);

    if (path) return path;
    else {
	char buf[256];
	char *s = "Class";

	if (TYPE(klass) == T_MODULE) s = "Module";
	sprintf(buf, "#<%s 0x%x>", s, klass);
	return rb_str_new2(buf);
    }
}

void
rb_set_class_path(klass, under, name)
    VALUE klass, under;
    char *name;
{
    VALUE str;

    if (under == rb_cObject) {
	str = rb_str_new2(name);
    }
    else {
	str = rb_str_dup(rb_class_path(under));
	rb_str_cat(str, "::", 2);
	rb_str_cat(str, name, strlen(name));
    }
    rb_iv_set(klass, "__classpath__", str);
}

VALUE
rb_path2class(path)
    char *path;
{
    if (path[0] == '#') {
	rb_raise(rb_eArgError, "can't retrieve anonymous class %s", path);
    }
    return rb_eval_string(path);
}

void
rb_name_class(klass, id)
    VALUE klass;
    ID id;
{
    if (rb_cString) {
	rb_iv_set(klass, "__classpath__", rb_str_new2(rb_id2name(id)));
    }
    else {
	rb_iv_set(klass, "__classid__", INT2FIX(id));
    }
}

static st_table *autoload_tbl = 0;

static void
rb_autoload_id(id, filename)
    ID id;
    char *filename;
{
    if (!rb_is_const_id(id)) {
	rb_raise(rb_eNameError, "autoload must be constant name",
		 rb_id2name(id));
    }

    if (!autoload_tbl) {
	autoload_tbl = st_init_numtable();
    }
    st_insert(autoload_tbl, id, strdup(filename));
}

void
rb_autoload(klass, filename)
    char *klass, *filename;
{
    rb_autoload_id(rb_intern(klass), filename);
}

VALUE
rb_f_autoload(obj, klass, file)
    VALUE obj, klass, file;
{
    rb_autoload_id(rb_to_id(klass), STR2CSTR(file));
    return Qnil;
}

char *
rb_class2name(klass)
    VALUE klass;
{
    return RSTRING(rb_class_path(klass))->ptr;
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

    if (!st_lookup(rb_global_tbl, id, &entry)) {
	entry = ALLOC(struct global_entry);
	st_add_direct(rb_global_tbl, id, entry);
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
    if (rb_verbose) {
	rb_warning("global variable `%s' not initialized", rb_id2name(id));
    }
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
    if (data) rb_gc_mark_maybe(data);
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
    if (var) rb_gc_mark_maybe(*var);
}

static void
readonly_setter(val, id, var)
    VALUE val;
    ID id;
    void *var;
{
    rb_raise(rb_eNameError, "Can't set variable %s", rb_id2name(id));
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
	if (trace->data) rb_gc_mark_maybe(trace->data);
	trace = trace->next;
    }
    return ST_CONTINUE;
}

void
rb_gc_mark_global_tbl()
{
    st_foreach(rb_global_tbl, mark_global_entry, 0);
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
    rb_eval_cmd(cmd, rb_ary_new3(1, val));
}

VALUE
rb_f_trace_var(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE var, cmd;
    ID id;
    struct global_entry *entry;
    struct trace_var *trace;

    if (rb_scan_args(argc, argv, "11", &var, &cmd) == 1) {
	cmd = rb_f_lambda();
    }
    if (NIL_P(cmd)) {
	return rb_f_untrace_var(argc, argv);
    }
    id = rb_to_id(var);
    if (!st_lookup(rb_global_tbl, id, &entry)) {
	rb_raise(rb_eNameError, "undefined global variable %s",
		 rb_id2name(id));
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
rb_f_untrace_var(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE var, cmd;
    ID id;
    struct global_entry *entry;
    struct trace_var *trace;

    rb_scan_args(argc, argv, "11", &var, &cmd);
    id = rb_to_id(var);
    if (!st_lookup(rb_global_tbl, id, &entry)) {
	rb_raise(rb_eNameError, "undefined global variable %s",
		 rb_id2name(id));
    }

    trace = entry->trace;
    if (NIL_P(cmd)) {
	VALUE ary = rb_ary_new();

	while (trace) {
	    struct trace_var *next = trace->next;
	    rb_ary_push(ary, (VALUE)trace->data);
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
		return rb_ary_new3(1, cmd);
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
    
static VALUE
trace_ev(data)
    struct trace_data *data;
{
    struct trace_var *trace = data->trace;

    while (trace) {
	(*trace->func)(trace->data, data->val);
	trace = trace->next;
    }
}

static VALUE
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

    if (rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't change global variable value");
    (*entry->setter)(val, entry->id, entry->data, entry);

    if (entry->trace && !entry->block_trace) {
	entry->block_trace = 1;
	trace.trace = entry->trace;
	trace.val = val;
	rb_ensure(trace_ev, (VALUE)&trace, trace_en, (VALUE)entry);
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
    if (entry->getter == undef_getter) return Qfalse;
    return Qtrue;
}

static int
gvar_i(key, entry, ary)
    ID key;
    struct global_entry *entry;
    VALUE ary;
{
    rb_ary_push(ary, rb_str_new2(rb_id2name(key)));
    return ST_CONTINUE;
}

VALUE
rb_f_global_variables()
{
    VALUE ary = rb_ary_new();
    char buf[4];
    char *s = "&`'+123456789";

    st_foreach(rb_global_tbl, gvar_i, ary);
    if (!NIL_P(rb_backref_get())) {
	while (*s) {
	    sprintf(buf, "$%c", *s++);
	    rb_ary_push(ary, rb_str_new2(buf));
	}
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
	rb_raise(rb_eTypeError, "class %s can not have instance variables",
		 rb_class2name(CLASS_OF(obj)));
	break;
    }
    if (rb_verbose) {
	rb_warning("instance var %s not initialized", rb_id2name(id));
    }
    return Qnil;
}

VALUE
rb_ivar_set(obj, id, val)
    VALUE obj;
    ID id;
    VALUE val;
{
    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (rb_safe_level() >= 4 && !FL_TEST(obj, FL_TAINT))
	    rb_raise(rb_eSecurityError, "Insecure: can't modify instance variable");
	if (!ROBJECT(obj)->iv_tbl) ROBJECT(obj)->iv_tbl = st_init_numtable();
	st_insert(ROBJECT(obj)->iv_tbl, id, val);
	break;
      default:
	rb_raise(rb_eTypeError, "class %s can not have instance variables",
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
    if (!rb_is_instance_id(id)) return Qfalse;

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (ROBJECT(obj)->iv_tbl && st_lookup(ROBJECT(obj)->iv_tbl, id, 0))
	    return Qtrue;
	break;
    }
    return Qfalse;
}

static int
ivar_i(key, entry, ary)
    ID key;
    struct global_entry *entry;
    VALUE ary;
{
    if (rb_is_instance_id(key)) {
	rb_ary_push(ary, rb_str_new2(rb_id2name(key)));
    }
    return ST_CONTINUE;
}

VALUE
rb_obj_instance_variables(obj)
    VALUE obj;
{
    VALUE ary;

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	ary = rb_ary_new();
	if (ROBJECT(obj)->iv_tbl) {
	    st_foreach(ROBJECT(obj)->iv_tbl, ivar_i, ary);
	}
	return ary;
    }
    return Qnil;
}

VALUE
rb_obj_remove_instance_variable(obj, name)
    VALUE obj, name;
{
    VALUE val = Qnil;
    ID id = rb_to_id(name);

    if (!rb_is_instance_id(id)) {
	rb_raise(rb_eNameError, "`%s' is not an instance variable",
		 rb_id2name(id));
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
	rb_raise(rb_eTypeError, "object %s can not have instance variables",
		 rb_class2name(CLASS_OF(obj)));
	break;
    }
    return val;
}

VALUE
rb_const_get_at(klass, id)
    VALUE klass;
    ID id;
{
    VALUE value;

    if (RCLASS(klass)->iv_tbl && st_lookup(RCLASS(klass)->iv_tbl, id, &value)) {
	return value;
    }
    if (klass == rb_cObject) {
	return rb_const_get(klass, id);
    }
    rb_raise(rb_eNameError, "Uninitialized constant %s::%s",
	     RSTRING(rb_class_path(klass))->ptr,
	     rb_id2name(id));
    /* not reached */
}


VALUE
rb_const_get(klass, id)
    VALUE klass;
    ID id;
{
    VALUE value;
    VALUE tmp;

    tmp = klass;
    while (tmp) {
	if (RCLASS(tmp)->iv_tbl && st_lookup(RCLASS(tmp)->iv_tbl,id,&value)) {
	    return value;
	}
	tmp = RCLASS(tmp)->super;
    }
    if (BUILTIN_TYPE(klass) == T_MODULE) {
	return rb_const_get(rb_cObject, id);
    }

    /* pre-defined class */
    if (st_lookup(rb_class_tbl, id, &value)) return value;

    /* autoload */
    if (autoload_tbl && st_lookup(autoload_tbl, id, 0)) {
	char *modname;
	VALUE module;

	st_delete(autoload_tbl, &id, &modname);
	module = rb_str_new2(modname);
	free(modname);
	rb_f_require(Qnil, module);
	return rb_const_get(klass, id);
    }

    /* Uninitialized constant */
    if (klass && klass != rb_cObject)
	rb_raise(rb_eNameError, "Uninitialized constant %s::%s",
		 RSTRING(rb_class_path(klass))->ptr,
		 rb_id2name(id));
    else {
	rb_raise(rb_eNameError, "Uninitialized constant %s",rb_id2name(id));
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
	VALUE kval = rb_str_new2(rb_id2name(key));
	if (!rb_ary_includes(ary, kval)) {
	    rb_ary_push(ary, kval);
	}
    }
    return ST_CONTINUE;
}

VALUE
rb_mod_remove_const(mod, name)
    VALUE mod, name;
{
    ID id = rb_to_id(name);
    VALUE val;

    if (!rb_is_const_id(id)) {
	rb_raise(rb_eNameError, "`%s' is not constant", rb_id2name(id));
    }

    if (RCLASS(mod)->iv_tbl && st_delete(ROBJECT(mod)->iv_tbl, &id, &val)) {
	return val;
    }
    if (rb_const_defined_at(mod, id)) {
	rb_raise(rb_eNameError, "cannot remove %s::%s", 
		 rb_class2name(mod), rb_id2name(id));
    }
    rb_raise(rb_eNameError, "constant %s::%s not defined", 
	     rb_class2name(mod), rb_id2name(id));
}

static int
autoload_i(key, name, ary)
    ID key;
    char *name;
    VALUE ary;
{
    VALUE kval = rb_str_new2(rb_id2name(key));
    if (!rb_ary_includes(ary, kval)) {
	rb_ary_push(ary, kval);
    }
    return ST_CONTINUE;
}

VALUE
rb_mod_const_at(mod, ary)
    VALUE mod, ary;
{
    if (RCLASS(mod)->iv_tbl) {
	st_foreach(RCLASS(mod)->iv_tbl, const_i, ary);
    }
    if ((VALUE)mod == rb_cObject) {
	st_foreach(rb_class_tbl, const_i, ary);
	if (autoload_tbl) {
	    st_foreach(autoload_tbl, autoload_i, ary);
	}
    }
    return ary;
}

VALUE
rb_mod_constants(mod)
    VALUE mod;
{
    return rb_mod_const_at(mod, rb_ary_new());
}

VALUE
rb_mod_const_of(mod, ary)
    VALUE mod;
    VALUE ary;
{
    rb_mod_const_at(mod, ary);
    for (;;) {
	mod = RCLASS(mod)->super;
	if (!mod) break;
	rb_mod_const_at(mod, ary);
    }
    return ary;
}

int
rb_const_defined_at(klass, id)
    VALUE klass;
    ID id;
{
    if (RCLASS(klass)->iv_tbl && st_lookup(RCLASS(klass)->iv_tbl, id, 0)) {
	return Qtrue;
    }
    if (klass == rb_cObject) {
	return rb_const_defined(klass, id);
    }
    return Qfalse;
}

int
rb_autoload_defined(id)
    ID id;
{
    if (autoload_tbl && st_lookup(autoload_tbl, id, 0))
	return Qtrue;
    return Qfalse;
}

int
rb_const_defined(klass, id)
    VALUE klass;
    ID id;
{
    VALUE tmp = klass;

    while (tmp) {
	if (RCLASS(tmp)->iv_tbl && st_lookup(RCLASS(tmp)->iv_tbl,id,0)) {
	    return Qtrue;
	}
	tmp = RCLASS(tmp)->super;
    }
    if (BUILTIN_TYPE(klass) == T_MODULE) {
	return rb_const_defined(rb_cObject, id);
    }
    if (st_lookup(rb_class_tbl, id, 0))
	return Qtrue;
    return rb_autoload_defined(id);
}

void
rb_const_set(klass, id, val)
    VALUE klass;
    ID id;
    VALUE val;
{
    if (rb_safe_level() >= 4 && !FL_TEST(klass, FL_TAINT))
	rb_raise(rb_eSecurityError, "Insecure: can't set constant");
    if (!RCLASS(klass)->iv_tbl) {
	RCLASS(klass)->iv_tbl = st_init_numtable();
    }
    else if (st_lookup(RCLASS(klass)->iv_tbl, id, 0)) {
	rb_raise(rb_eNameError, "already initialized constant %s",
		 rb_id2name(id));
    }

    st_add_direct(RCLASS(klass)->iv_tbl, id, val);
}

void
rb_define_const(klass, name, val)
    VALUE klass;
    char *name;
    VALUE val;
{
    ID id = rb_intern(name);

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    if (!rb_is_const_id(id)) {
	rb_raise(rb_eNameError, "wrong constant name %s", name);
    }
    rb_const_set(klass, id, val);
}

void
rb_define_global_const(name, val)
    char *name;
    VALUE val;
{
    rb_define_const(rb_cObject, name, val);
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
