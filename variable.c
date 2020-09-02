/**********************************************************************

  variable.c -

  $Author$
  created at: Tue Apr 19 23:55:15 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"
#include <stddef.h>
#include "ruby/internal/stdbool.h"
#include "ccan/list/list.h"
#include "constant.h"
#include "debug_counter.h"
#include "id.h"
#include "id_table.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/compilers.h"
#include "internal/error.h"
#include "internal/eval.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/re.h"
#include "internal/symbol.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "ruby/encoding.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "transient_heap.h"
#include "variable.h"
#include "vm_core.h"

typedef void rb_gvar_compact_t(void *var);

static struct rb_id_table *rb_global_tbl;
static ID autoload, classpath, tmp_classpath;
static VALUE autoload_featuremap; /* feature => autoload_i */

static void check_before_mod_set(VALUE, ID, VALUE, const char *);
static void setup_const_entry(rb_const_entry_t *, VALUE, VALUE, rb_const_flag_t);
static VALUE rb_const_search(VALUE klass, ID id, int exclude, int recurse, int visibility);
static st_table *generic_iv_tbl;

struct ivar_update {
    union {
	st_table *iv_index_tbl;
	struct gen_ivtbl *ivtbl;
    } u;
    st_data_t index;
    int iv_extended;
};

void
Init_var_tables(void)
{
    rb_global_tbl = rb_id_table_create(0);
    generic_iv_tbl = st_init_numtable();
    autoload = rb_intern_const("__autoload__");
    /* __classpath__: fully qualified class path */
    classpath = rb_intern_const("__classpath__");
    /* __tmp_classpath__: temporary class path which contains anonymous names */
    tmp_classpath = rb_intern_const("__tmp_classpath__");
}

static inline bool
rb_namespace_p(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) return false;
    switch (RB_BUILTIN_TYPE(obj)) {
      case T_MODULE: case T_CLASS: return true;
      default: break;
    }
    return false;
}

/**
 * Returns +classpath+ of _klass_, if it is named, or +nil+ for
 * anonymous +class+/+module+. A named +classpath+ may contain
 * an anonymous component, but the last component is guaranteed
 * to not be anonymous. <code>*permanent</code> is set to 1
 * if +classpath+ has no anonymous components. There is no builtin
 * Ruby level APIs that can change a permanent +classpath+.
 */
static VALUE
classname(VALUE klass, int *permanent)
{
    st_table *ivtbl;
    st_data_t n;

    *permanent = 0;
    if (!RCLASS_EXT(klass)) return Qnil;
    if (!(ivtbl = RCLASS_IV_TBL(klass))) return Qnil;
    if (st_lookup(ivtbl, (st_data_t)classpath, &n)) {
        *permanent = 1;
        return (VALUE)n;
    }
    if (st_lookup(ivtbl, (st_data_t)tmp_classpath, &n)) return (VALUE)n;
    return Qnil;
}

/*
 *  call-seq:
 *     mod.name    -> string
 *
 *  Returns the name of the module <i>mod</i>.  Returns nil for anonymous modules.
 */

VALUE
rb_mod_name(VALUE mod)
{
    int permanent;
    return classname(mod, &permanent);
}

static VALUE
make_temporary_path(VALUE obj, VALUE klass)
{
    VALUE path;
    switch (klass) {
      case Qnil:
	path = rb_sprintf("#<Class:%p>", (void*)obj);
	break;
      case Qfalse:
	path = rb_sprintf("#<Module:%p>", (void*)obj);
	break;
      default:
	path = rb_sprintf("#<%"PRIsVALUE":%p>", klass, (void*)obj);
	break;
    }
    OBJ_FREEZE(path);
    return path;
}

typedef VALUE (*fallback_func)(VALUE obj, VALUE name);

static VALUE
rb_tmp_class_path(VALUE klass, int *permanent, fallback_func fallback)
{
    VALUE path = classname(klass, permanent);

    if (!NIL_P(path)) {
	return path;
    }
    else {
	if (RB_TYPE_P(klass, T_MODULE)) {
	    if (rb_obj_class(klass) == rb_cModule) {
		path = Qfalse;
	    }
	    else {
		int perm;
		path = rb_tmp_class_path(RBASIC(klass)->klass, &perm, fallback);
	    }
	}
	*permanent = 0;
	return fallback(klass, path);
    }
}

VALUE
rb_class_path(VALUE klass)
{
    int permanent;
    VALUE path = rb_tmp_class_path(klass, &permanent, make_temporary_path);
    if (!NIL_P(path)) path = rb_str_dup(path);
    return path;
}

VALUE
rb_class_path_cached(VALUE klass)
{
    int permanent;
    return classname(klass, &permanent);
}

static VALUE
no_fallback(VALUE obj, VALUE name)
{
    return name;
}

VALUE
rb_search_class_path(VALUE klass)
{
    int permanent;
    return rb_tmp_class_path(klass, &permanent, no_fallback);
}

static VALUE
build_const_pathname(VALUE head, VALUE tail)
{
    VALUE path = rb_str_dup(head);
    rb_str_cat2(path, "::");
    rb_str_append(path, tail);
    OBJ_FREEZE(path);
    return path;
}

static VALUE
build_const_path(VALUE head, ID tail)
{
    return build_const_pathname(head, rb_id2str(tail));
}

void
rb_set_class_path_string(VALUE klass, VALUE under, VALUE name)
{
    VALUE str;
    ID pathid = classpath;

    if (under == rb_cObject) {
	str = rb_str_new_frozen(name);
    }
    else {
	int permanent;
        str = rb_tmp_class_path(under, &permanent, make_temporary_path);
        str = build_const_pathname(str, name);
	if (!permanent) {
	    pathid = tmp_classpath;
	}
    }
    rb_ivar_set(klass, pathid, str);
}

void
rb_set_class_path(VALUE klass, VALUE under, const char *name)
{
    VALUE str = rb_str_new2(name);
    OBJ_FREEZE(str);
    rb_set_class_path_string(klass, under, str);
}

VALUE
rb_path_to_class(VALUE pathname)
{
    rb_encoding *enc = rb_enc_get(pathname);
    const char *pbeg, *pend, *p, *path = RSTRING_PTR(pathname);
    ID id;
    VALUE c = rb_cObject;

    if (!rb_enc_asciicompat(enc)) {
	rb_raise(rb_eArgError, "invalid class path encoding (non ASCII)");
    }
    pbeg = p = path;
    pend = path + RSTRING_LEN(pathname);
    if (path == pend || path[0] == '#') {
	rb_raise(rb_eArgError, "can't retrieve anonymous class %"PRIsVALUE,
		 QUOTE(pathname));
    }
    while (p < pend) {
	while (p < pend && *p != ':') p++;
	id = rb_check_id_cstr(pbeg, p-pbeg, enc);
	if (p < pend && p[0] == ':') {
	    if ((size_t)(pend - p) < 2 || p[1] != ':') goto undefined_class;
	    p += 2;
	    pbeg = p;
	}
	if (!id) {
            goto undefined_class;
	}
	c = rb_const_search(c, id, TRUE, FALSE, FALSE);
	if (c == Qundef) goto undefined_class;
        if (!rb_namespace_p(c)) {
	    rb_raise(rb_eTypeError, "%"PRIsVALUE" does not refer to class/module",
		     pathname);
	}
    }
    RB_GC_GUARD(pathname);

    return c;

  undefined_class:
    rb_raise(rb_eArgError, "undefined class/module % "PRIsVALUE,
             rb_str_subseq(pathname, 0, p-path));
    UNREACHABLE_RETURN(Qundef);
}

VALUE
rb_path2class(const char *path)
{
    return rb_path_to_class(rb_str_new_cstr(path));
}

VALUE
rb_class_name(VALUE klass)
{
    return rb_class_path(rb_class_real(klass));
}

const char *
rb_class2name(VALUE klass)
{
    int permanent;
    VALUE path = rb_tmp_class_path(rb_class_real(klass), &permanent, make_temporary_path);
    if (NIL_P(path)) return NULL;
    return RSTRING_PTR(path);
}

const char *
rb_obj_classname(VALUE obj)
{
    return rb_class2name(CLASS_OF(obj));
}

struct trace_var {
    int removed;
    void (*func)(VALUE arg, VALUE val);
    VALUE data;
    struct trace_var *next;
};

struct rb_global_variable {
    int counter;
    int block_trace;
    VALUE *data;
    rb_gvar_getter_t *getter;
    rb_gvar_setter_t *setter;
    rb_gvar_marker_t *marker;
    rb_gvar_compact_t *compactor;
    struct trace_var *trace;
};

struct rb_global_entry {
    struct rb_global_variable *var;
    ID id;
};

static struct rb_id_table *
global_tbl(void)
{
    return rb_global_tbl;
}

static struct rb_global_entry*
rb_find_global_entry(ID id)
{
    struct rb_global_entry *entry;
    VALUE data;

    if (!rb_id_table_lookup(global_tbl(), id, &data)) {
        return NULL;
    }
    entry = (struct rb_global_entry *)data;
    ASSUME(entry != NULL);
    return entry;
}

static void
rb_gvar_undef_compactor(void *var)
{
}

static struct rb_global_entry*
rb_global_entry(ID id)
{
    struct rb_global_entry *entry = rb_find_global_entry(id);
    if (!entry) {
	struct rb_global_variable *var;
	entry = ALLOC(struct rb_global_entry);
	var = ALLOC(struct rb_global_variable);
	entry->id = id;
	entry->var = var;
	var->counter = 1;
	var->data = 0;
	var->getter = rb_gvar_undef_getter;
	var->setter = rb_gvar_undef_setter;
	var->marker = rb_gvar_undef_marker;
	var->compactor = rb_gvar_undef_compactor;

	var->block_trace = 0;
	var->trace = 0;
	rb_id_table_insert(global_tbl(), id, (VALUE)entry);
    }
    return entry;
}

VALUE
rb_gvar_undef_getter(ID id, VALUE *_)
{
    rb_warning("global variable `%"PRIsVALUE"' not initialized", QUOTE_ID(id));

    return Qnil;
}

static void
rb_gvar_val_compactor(void *_var)
{
    struct rb_global_variable *var = (struct rb_global_variable *)_var;

    VALUE obj = (VALUE)var->data;

    if (obj) {
        VALUE new = rb_gc_location(obj);
        if (new != obj) {
            var->data = (void*)new;
        }
    }
}

void
rb_gvar_undef_setter(VALUE val, ID id, VALUE *_)
{
    struct rb_global_variable *var = rb_global_entry(id)->var;
    var->getter = rb_gvar_val_getter;
    var->setter = rb_gvar_val_setter;
    var->marker = rb_gvar_val_marker;
    var->compactor = rb_gvar_val_compactor;

    var->data = (void*)val;
}

void
rb_gvar_undef_marker(VALUE *var)
{
}

VALUE
rb_gvar_val_getter(ID id, VALUE *data)
{
    return (VALUE)data;
}

void
rb_gvar_val_setter(VALUE val, ID id, VALUE *_)
{
    struct rb_global_variable *var = rb_global_entry(id)->var;
    var->data = (void*)val;
}

void
rb_gvar_val_marker(VALUE *var)
{
    VALUE data = (VALUE)var;
    if (data) rb_gc_mark_movable(data);
}

VALUE
rb_gvar_var_getter(ID id, VALUE *var)
{
    if (!var) return Qnil;
    return *var;
}

void
rb_gvar_var_setter(VALUE val, ID id, VALUE *data)
{
    *data = val;
}

void
rb_gvar_var_marker(VALUE *var)
{
    if (var) rb_gc_mark_maybe(*var);
}

void
rb_gvar_readonly_setter(VALUE v, ID id, VALUE *_)
{
    rb_name_error(id, "%"PRIsVALUE" is a read-only variable", QUOTE_ID(id));
}

static enum rb_id_table_iterator_result
mark_global_entry(VALUE v, void *ignored)
{
    struct rb_global_entry *entry = (struct rb_global_entry *)v;
    struct trace_var *trace;
    struct rb_global_variable *var = entry->var;

    (*var->marker)(var->data);
    trace = var->trace;
    while (trace) {
	if (trace->data) rb_gc_mark_maybe(trace->data);
	trace = trace->next;
    }
    return ID_TABLE_CONTINUE;
}

void
rb_gc_mark_global_tbl(void)
{
    if (rb_global_tbl) {
        rb_id_table_foreach_values(rb_global_tbl, mark_global_entry, 0);
    }
}

static enum rb_id_table_iterator_result
update_global_entry(VALUE v, void *ignored)
{
    struct rb_global_entry *entry = (struct rb_global_entry *)v;
    struct rb_global_variable *var = entry->var;

    (*var->compactor)(var);
    return ID_TABLE_CONTINUE;
}

void
rb_gc_update_global_tbl(void)
{
    if (rb_global_tbl)
        rb_id_table_foreach_values(rb_global_tbl, update_global_entry, 0);
}

static ID
global_id(const char *name)
{
    ID id;

    if (name[0] == '$') id = rb_intern(name);
    else {
	size_t len = strlen(name);
        VALUE vbuf = 0;
        char *buf = ALLOCV_N(char, vbuf, len+1);
	buf[0] = '$';
	memcpy(buf+1, name, len);
	id = rb_intern2(buf, len+1);
        ALLOCV_END(vbuf);
    }
    return id;
}

static ID
find_global_id(const char *name)
{
    ID id;
    size_t len = strlen(name);

    if (name[0] == '$') {
        id = rb_check_id_cstr(name, len, NULL);
    }
    else {
        VALUE vbuf = 0;
        char *buf = ALLOCV_N(char, vbuf, len+1);
        buf[0] = '$';
        memcpy(buf+1, name, len);
        id = rb_check_id_cstr(buf, len+1, NULL);
        ALLOCV_END(vbuf);
    }

    return id;
}

void
rb_define_hooked_variable(
    const char *name,
    VALUE *var,
    rb_gvar_getter_t *getter,
    rb_gvar_setter_t *setter)
{
    volatile VALUE tmp = var ? *var : Qnil;
    ID id = global_id(name);
    struct rb_global_variable *gvar = rb_global_entry(id)->var;

    gvar->data = (void*)var;
    gvar->getter = getter ? (rb_gvar_getter_t *)getter : rb_gvar_var_getter;
    gvar->setter = setter ? (rb_gvar_setter_t *)setter : rb_gvar_var_setter;
    gvar->marker = rb_gvar_var_marker;

    RB_GC_GUARD(tmp);
}

void
rb_define_variable(const char *name, VALUE *var)
{
    rb_define_hooked_variable(name, var, 0, 0);
}

void
rb_define_readonly_variable(const char *name, const VALUE *var)
{
    rb_define_hooked_variable(name, (VALUE *)var, 0, rb_gvar_readonly_setter);
}

void
rb_define_virtual_variable(
    const char *name,
    rb_gvar_getter_t *getter,
    rb_gvar_setter_t *setter)
{
    if (!getter) getter = rb_gvar_val_getter;
    if (!setter) setter = rb_gvar_readonly_setter;
    rb_define_hooked_variable(name, 0, getter, setter);
}

static void
rb_trace_eval(VALUE cmd, VALUE val)
{
    rb_eval_cmd_kw(cmd, rb_ary_new3(1, val), RB_NO_KEYWORDS);
}

VALUE
rb_f_trace_var(int argc, const VALUE *argv)
{
    VALUE var, cmd;
    struct rb_global_entry *entry;
    struct trace_var *trace;

    if (rb_scan_args(argc, argv, "11", &var, &cmd) == 1) {
	cmd = rb_block_proc();
    }
    if (NIL_P(cmd)) {
	return rb_f_untrace_var(argc, argv);
    }
    entry = rb_global_entry(rb_to_id(var));
    trace = ALLOC(struct trace_var);
    trace->next = entry->var->trace;
    trace->func = rb_trace_eval;
    trace->data = cmd;
    trace->removed = 0;
    entry->var->trace = trace;

    return Qnil;
}

static void
remove_trace(struct rb_global_variable *var)
{
    struct trace_var *trace = var->trace;
    struct trace_var t;
    struct trace_var *next;

    t.next = trace;
    trace = &t;
    while (trace->next) {
	next = trace->next;
	if (next->removed) {
	    trace->next = next->next;
	    xfree(next);
	}
	else {
	    trace = next;
	}
    }
    var->trace = t.next;
}

VALUE
rb_f_untrace_var(int argc, const VALUE *argv)
{
    VALUE var, cmd;
    ID id;
    struct rb_global_entry *entry;
    struct trace_var *trace;
    VALUE data;

    rb_scan_args(argc, argv, "11", &var, &cmd);
    id = rb_check_id(&var);
    if (!id) {
	rb_name_error_str(var, "undefined global variable %"PRIsVALUE"", QUOTE(var));
    }
    if (!rb_id_table_lookup(global_tbl(), id, &data)) {
	rb_name_error(id, "undefined global variable %"PRIsVALUE"", QUOTE_ID(id));
    }

    trace = (entry = (struct rb_global_entry *)data)->var->trace;
    if (NIL_P(cmd)) {
	VALUE ary = rb_ary_new();

	while (trace) {
	    struct trace_var *next = trace->next;
	    rb_ary_push(ary, (VALUE)trace->data);
	    trace->removed = 1;
	    trace = next;
	}

	if (!entry->var->block_trace) remove_trace(entry->var);
	return ary;
    }
    else {
	while (trace) {
	    if (trace->data == cmd) {
		trace->removed = 1;
		if (!entry->var->block_trace) remove_trace(entry->var);
		return rb_ary_new3(1, cmd);
	    }
	    trace = trace->next;
	}
    }
    return Qnil;
}

struct trace_data {
    struct trace_var *trace;
    VALUE val;
};

static VALUE
trace_ev(VALUE v)
{
    struct trace_data *data = (void *)v;
    struct trace_var *trace = data->trace;

    while (trace) {
	(*trace->func)(trace->data, data->val);
	trace = trace->next;
    }

    return Qnil;
}

static VALUE
trace_en(VALUE v)
{
    struct rb_global_variable *var = (void *)v;
    var->block_trace = 0;
    remove_trace(var);
    return Qnil;		/* not reached */
}

static VALUE
rb_gvar_set_entry(struct rb_global_entry *entry, VALUE val)
{
    struct trace_data trace;
    struct rb_global_variable *var = entry->var;

    (*var->setter)(val, entry->id, var->data);

    if (var->trace && !var->block_trace) {
	var->block_trace = 1;
	trace.trace = var->trace;
	trace.val = val;
	rb_ensure(trace_ev, (VALUE)&trace, trace_en, (VALUE)var);
    }
    return val;
}

VALUE
rb_gvar_set(ID id, VALUE val)
{
    struct rb_global_entry *entry;
    entry = rb_global_entry(id);

    return rb_gvar_set_entry(entry, val);
}

VALUE
rb_gv_set(const char *name, VALUE val)
{
    return rb_gvar_set(global_id(name), val);
}

VALUE
rb_gvar_get(ID id)
{
    struct rb_global_entry *entry = rb_global_entry(id);
    struct rb_global_variable *var = entry->var;
    return (*var->getter)(entry->id, var->data);
}

VALUE
rb_gv_get(const char *name)
{
    ID id = find_global_id(name);

    if (!id) {
        rb_warning("global variable `%s' not initialized", name);
        return Qnil;
    }

    return rb_gvar_get(id);
}

MJIT_FUNC_EXPORTED VALUE
rb_gvar_defined(ID id)
{
    struct rb_global_entry *entry = rb_global_entry(id);
    if (entry->var->getter == rb_gvar_undef_getter) return Qfalse;
    return Qtrue;
}

rb_gvar_getter_t *
rb_gvar_getter_function_of(ID id)
{
    const struct rb_global_entry *entry = rb_global_entry(id);
    return entry->var->getter;
}

rb_gvar_setter_t *
rb_gvar_setter_function_of(ID id)
{
    const struct rb_global_entry *entry = rb_global_entry(id);
    return entry->var->setter;
}

static enum rb_id_table_iterator_result
gvar_i(ID key, VALUE val, void *a)
{
    VALUE ary = (VALUE)a;
    rb_ary_push(ary, ID2SYM(key));
    return ID_TABLE_CONTINUE;
}

VALUE
rb_f_global_variables(void)
{
    VALUE ary = rb_ary_new();
    VALUE sym, backref = rb_backref_get();

    rb_id_table_foreach(global_tbl(), gvar_i, (void *)ary);
    if (!NIL_P(backref)) {
	char buf[2];
	int i, nmatch = rb_match_count(backref);
	buf[0] = '$';
	for (i = 1; i <= nmatch; ++i) {
	    if (!rb_match_nth_defined(i, backref)) continue;
	    if (i < 10) {
		/* probably reused, make static ID */
		buf[1] = (char)(i + '0');
		sym = ID2SYM(rb_intern2(buf, 2));
	    }
	    else {
		/* dynamic symbol */
		sym = rb_str_intern(rb_sprintf("$%d", i));
	    }
	    rb_ary_push(ary, sym);
	}
    }
    return ary;
}

void
rb_alias_variable(ID name1, ID name2)
{
    struct rb_global_entry *entry1, *entry2;
    VALUE data1;
    struct rb_id_table *gtbl = global_tbl();

    entry2 = rb_global_entry(name2);
    if (!rb_id_table_lookup(gtbl, name1, &data1)) {
	entry1 = ALLOC(struct rb_global_entry);
	entry1->id = name1;
	rb_id_table_insert(gtbl, name1, (VALUE)entry1);
    }
    else if ((entry1 = (struct rb_global_entry *)data1)->var != entry2->var) {
	struct rb_global_variable *var = entry1->var;
	if (var->block_trace) {
	    rb_raise(rb_eRuntimeError, "can't alias in tracer");
	}
	var->counter--;
	if (var->counter == 0) {
	    struct trace_var *trace = var->trace;
	    while (trace) {
		struct trace_var *next = trace->next;
		xfree(trace);
		trace = next;
	    }
	    xfree(var);
	}
    }
    else {
	return;
    }
    entry2->var->counter++;
    entry1->var = entry2->var;
}

static int
gen_ivtbl_get(VALUE obj, struct gen_ivtbl **ivtbl)
{
    st_data_t data;

    if (st_lookup(generic_iv_tbl, (st_data_t)obj, &data)) {
	*ivtbl = (struct gen_ivtbl *)data;
	return 1;
    }
    return 0;
}

MJIT_FUNC_EXPORTED struct st_table *
rb_ivar_generic_ivtbl(void)
{
    return generic_iv_tbl;
}

static VALUE
generic_ivar_delete(VALUE obj, ID id, VALUE undef)
{
    struct gen_ivtbl *ivtbl;

    if (gen_ivtbl_get(obj, &ivtbl)) {
	st_table *iv_index_tbl = RCLASS_IV_INDEX_TBL(rb_obj_class(obj));
	st_data_t index;

	if (iv_index_tbl && st_lookup(iv_index_tbl, (st_data_t)id, &index)) {
	    if (index < ivtbl->numiv) {
		VALUE ret = ivtbl->ivptr[index];

		ivtbl->ivptr[index] = Qundef;
		return ret == Qundef ? undef : ret;
	    }
	}
    }
    return undef;
}

static VALUE
generic_ivar_get(VALUE obj, ID id, VALUE undef)
{
    struct gen_ivtbl *ivtbl;

    if (gen_ivtbl_get(obj, &ivtbl)) {
	st_table *iv_index_tbl = RCLASS_IV_INDEX_TBL(rb_obj_class(obj));
	st_data_t index;

	if (iv_index_tbl && st_lookup(iv_index_tbl, (st_data_t)id, &index)) {
	    if (index < ivtbl->numiv) {
		VALUE ret = ivtbl->ivptr[index];

		return ret == Qundef ? undef : ret;
	    }
	}
    }
    return undef;
}

static size_t
gen_ivtbl_bytes(size_t n)
{
    return offsetof(struct gen_ivtbl, ivptr) + n * sizeof(VALUE);
}

static struct gen_ivtbl *
gen_ivtbl_resize(struct gen_ivtbl *old, uint32_t n)
{
    uint32_t len = old ? old->numiv : 0;
    struct gen_ivtbl *ivtbl = xrealloc(old, gen_ivtbl_bytes(n));

    ivtbl->numiv = n;
    for (; len < n; len++) {
	ivtbl->ivptr[len] = Qundef;
    }

    return ivtbl;
}

#if 0
static struct gen_ivtbl *
gen_ivtbl_dup(const struct gen_ivtbl *orig)
{
    size_t s = gen_ivtbl_bytes(orig->numiv);
    struct gen_ivtbl *ivtbl = xmalloc(s);

    memcpy(ivtbl, orig, s);

    return ivtbl;
}
#endif

static uint32_t
iv_index_tbl_newsize(struct ivar_update *ivup)
{
    uint32_t index = (uint32_t)ivup->index;	/* should not overflow */
    uint32_t newsize = (index+1) + (index+1)/4; /* (index+1)*1.25 */

    if (!ivup->iv_extended) {
        newsize = (uint32_t)ivup->u.iv_index_tbl->num_entries;
    }
    return newsize;
}

static int
generic_ivar_update(st_data_t *k, st_data_t *v, st_data_t u, int existing)
{
    struct ivar_update *ivup = (struct ivar_update *)u;
    struct gen_ivtbl *ivtbl = 0;

    if (existing) {
	ivtbl = (struct gen_ivtbl *)*v;
        if (ivup->index < ivtbl->numiv) {
            ivup->u.ivtbl = ivtbl;
            return ST_STOP;
        }
    }
    FL_SET((VALUE)*k, FL_EXIVAR);
    uint32_t newsize = iv_index_tbl_newsize(ivup);
    ivtbl = gen_ivtbl_resize(ivtbl, newsize);
    *v = (st_data_t)ivtbl;
    ivup->u.ivtbl = ivtbl;
    return ST_CONTINUE;
}

static VALUE
generic_ivar_defined(VALUE obj, ID id)
{
    struct gen_ivtbl *ivtbl;
    st_table *iv_index_tbl = RCLASS_IV_INDEX_TBL(rb_obj_class(obj));
    st_data_t index;

    if (!iv_index_tbl) return Qfalse;
    if (!st_lookup(iv_index_tbl, (st_data_t)id, &index)) return Qfalse;
    if (!gen_ivtbl_get(obj, &ivtbl)) return Qfalse;

    if ((index < ivtbl->numiv) && (ivtbl->ivptr[index] != Qundef))
	return Qtrue;

    return Qfalse;
}

static int
generic_ivar_remove(VALUE obj, ID id, VALUE *valp)
{
    struct gen_ivtbl *ivtbl;
    st_data_t key = (st_data_t)id;
    st_data_t index;
    st_table *iv_index_tbl = RCLASS_IV_INDEX_TBL(rb_obj_class(obj));

    if (!iv_index_tbl) return 0;
    if (!st_lookup(iv_index_tbl, key, &index)) return 0;
    if (!gen_ivtbl_get(obj, &ivtbl)) return 0;

    if (index < ivtbl->numiv) {
	if (ivtbl->ivptr[index] != Qundef) {
	    *valp = ivtbl->ivptr[index];
	    ivtbl->ivptr[index] = Qundef;
	    return 1;
	}
    }
    return 0;
}

static void
gen_ivtbl_mark(const struct gen_ivtbl *ivtbl)
{
    uint32_t i;

    for (i = 0; i < ivtbl->numiv; i++) {
	rb_gc_mark(ivtbl->ivptr[i]);
    }
}

void
rb_mark_generic_ivar(VALUE obj)
{
    struct gen_ivtbl *ivtbl;

    if (gen_ivtbl_get(obj, &ivtbl)) {
	gen_ivtbl_mark(ivtbl);
    }
}

void
rb_mv_generic_ivar(VALUE rsrc, VALUE dst)
{
    st_data_t key = (st_data_t)rsrc;
    struct gen_ivtbl *ivtbl;

    if (st_delete(generic_iv_tbl, &key, (st_data_t *)&ivtbl))
        st_insert(generic_iv_tbl, (st_data_t)dst, (st_data_t)ivtbl);
}

void
rb_free_generic_ivar(VALUE obj)
{
    st_data_t key = (st_data_t)obj;
    struct gen_ivtbl *ivtbl;

    if (st_delete(generic_iv_tbl, &key, (st_data_t *)&ivtbl))
	xfree(ivtbl);
}

RUBY_FUNC_EXPORTED size_t
rb_generic_ivar_memsize(VALUE obj)
{
    struct gen_ivtbl *ivtbl;

    if (gen_ivtbl_get(obj, &ivtbl))
	return gen_ivtbl_bytes(ivtbl->numiv);
    return 0;
}

static size_t
gen_ivtbl_count(const struct gen_ivtbl *ivtbl)
{
    uint32_t i;
    size_t n = 0;

    for (i = 0; i < ivtbl->numiv; i++) {
	if (ivtbl->ivptr[i] != Qundef) {
	    n++;
	}
    }

    return n;
}

VALUE
rb_ivar_lookup(VALUE obj, ID id, VALUE undef)
{
    VALUE val, *ptr;
    struct st_table *iv_index_tbl;
    uint32_t len;
    st_data_t index;

    if (SPECIAL_CONST_P(obj)) return undef;
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        len = ROBJECT_NUMIV(obj);
        ptr = ROBJECT_IVPTR(obj);
        iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);
        if (!iv_index_tbl) break;
        if (!st_lookup(iv_index_tbl, (st_data_t)id, &index)) break;
        if (len <= index) break;
        val = ptr[index];
        if (val != Qundef)
            return val;
	break;
      case T_CLASS:
      case T_MODULE:
	if (RCLASS_IV_TBL(obj) &&
		st_lookup(RCLASS_IV_TBL(obj), (st_data_t)id, &index))
	    return (VALUE)index;
	break;
      default:
	if (FL_TEST(obj, FL_EXIVAR))
	    return generic_ivar_get(obj, id, undef);
	break;
    }
    return undef;
}

VALUE
rb_ivar_get(VALUE obj, ID id)
{
    VALUE iv = rb_ivar_lookup(obj, id, Qundef);
    RB_DEBUG_COUNTER_INC(ivar_get_base);

    if (iv == Qundef) {
	if (RTEST(ruby_verbose))
	    rb_warning("instance variable %"PRIsVALUE" not initialized", QUOTE_ID(id));
	iv = Qnil;
    }
    return iv;
}

VALUE
rb_attr_get(VALUE obj, ID id)
{
    return rb_ivar_lookup(obj, id, Qnil);
}

static VALUE
rb_ivar_delete(VALUE obj, ID id, VALUE undef)
{
    VALUE val, *ptr;
    struct st_table *iv_index_tbl;
    uint32_t len;
    st_data_t index;

    rb_check_frozen(obj);
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        len = ROBJECT_NUMIV(obj);
        ptr = ROBJECT_IVPTR(obj);
        iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);
        if (!iv_index_tbl) break;
        if (!st_lookup(iv_index_tbl, (st_data_t)id, &index)) break;
        if (len <= index) break;
        val = ptr[index];
        ptr[index] = Qundef;
        if (val != Qundef)
            return val;
	break;
      case T_CLASS:
      case T_MODULE:
	if (RCLASS_IV_TBL(obj) &&
		st_delete(RCLASS_IV_TBL(obj), (st_data_t *)&id, &index))
	    return (VALUE)index;
	break;
      default:
	if (FL_TEST(obj, FL_EXIVAR))
	    return generic_ivar_delete(obj, id, undef);
	break;
    }
    return undef;
}

VALUE
rb_attr_delete(VALUE obj, ID id)
{
    return rb_ivar_delete(obj, id, Qnil);
}

static st_table *
iv_index_tbl_make(VALUE obj)
{
    VALUE klass = rb_obj_class(obj);
    st_table *iv_index_tbl;

    if (!klass) {
        rb_raise(rb_eTypeError, "hidden object cannot have instance variables");
    }
    if (!(iv_index_tbl = RCLASS_IV_INDEX_TBL(klass))) {
	iv_index_tbl = RCLASS_IV_INDEX_TBL(klass) = st_init_numtable();
    }

    return iv_index_tbl;
}

static void
iv_index_tbl_extend(struct ivar_update *ivup, ID id)
{
    if (st_lookup(ivup->u.iv_index_tbl, (st_data_t)id, &ivup->index)) {
	return;
    }
    if (ivup->u.iv_index_tbl->num_entries >= INT_MAX) {
	rb_raise(rb_eArgError, "too many instance variables");
    }
    ivup->index = (st_data_t)ivup->u.iv_index_tbl->num_entries;
    st_add_direct(ivup->u.iv_index_tbl, (st_data_t)id, ivup->index);
    ivup->iv_extended = 1;
}

static void
generic_ivar_set(VALUE obj, ID id, VALUE val)
{
    struct ivar_update ivup;

    ivup.iv_extended = 0;
    ivup.u.iv_index_tbl = iv_index_tbl_make(obj);
    iv_index_tbl_extend(&ivup, id);
    st_update(generic_iv_tbl, (st_data_t)obj, generic_ivar_update,
	      (st_data_t)&ivup);

    ivup.u.ivtbl->ivptr[ivup.index] = val;

    RB_OBJ_WRITTEN(obj, Qundef, val);
}

static VALUE *
obj_ivar_heap_alloc(VALUE obj, size_t newsize)
{
    VALUE *newptr = rb_transient_heap_alloc(obj, sizeof(VALUE) * newsize);

    if (newptr != NULL) {
        ROBJ_TRANSIENT_SET(obj);
    }
    else {
        ROBJ_TRANSIENT_UNSET(obj);
        newptr = ALLOC_N(VALUE, newsize);
    }
    return newptr;
}

static VALUE *
obj_ivar_heap_realloc(VALUE obj, int32_t len, size_t newsize)
{
    VALUE *newptr;
    int i;

    if (ROBJ_TRANSIENT_P(obj)) {
        const VALUE *orig_ptr = ROBJECT(obj)->as.heap.ivptr;
        newptr = obj_ivar_heap_alloc(obj, newsize);

        assert(newptr);
        ROBJECT(obj)->as.heap.ivptr = newptr;
        for (i=0; i<(int)len; i++) {
            newptr[i] = orig_ptr[i];
        }
    }
    else {
        REALLOC_N(ROBJECT(obj)->as.heap.ivptr, VALUE, newsize);
        newptr = ROBJECT(obj)->as.heap.ivptr;
    }

    return newptr;
}

#if USE_TRANSIENT_HEAP
void
rb_obj_transient_heap_evacuate(VALUE obj, int promote)
{
    if (ROBJ_TRANSIENT_P(obj)) {
        uint32_t len = ROBJECT_NUMIV(obj);
        const VALUE *old_ptr = ROBJECT_IVPTR(obj);
        VALUE *new_ptr;

        if (promote) {
            new_ptr = ALLOC_N(VALUE, len);
            ROBJ_TRANSIENT_UNSET(obj);
        }
        else {
            new_ptr = obj_ivar_heap_alloc(obj, len);
        }
        MEMCPY(new_ptr, old_ptr, VALUE, len);
        ROBJECT(obj)->as.heap.ivptr = new_ptr;
    }
}
#endif

static VALUE
obj_ivar_set(VALUE obj, ID id, VALUE val)
{
    struct ivar_update ivup;
    uint32_t i, len;

    ivup.iv_extended = 0;
    ivup.u.iv_index_tbl = iv_index_tbl_make(obj);
    iv_index_tbl_extend(&ivup, id);
    len = ROBJECT_NUMIV(obj);
    if (len <= ivup.index) {
        VALUE *ptr = ROBJECT_IVPTR(obj);
        if (ivup.index < ROBJECT_EMBED_LEN_MAX) {
            RBASIC(obj)->flags |= ROBJECT_EMBED;
            ptr = ROBJECT(obj)->as.ary;
            for (i = 0; i < ROBJECT_EMBED_LEN_MAX; i++) {
                ptr[i] = Qundef;
            }
        }
        else {
            VALUE *newptr;
            uint32_t newsize = iv_index_tbl_newsize(&ivup);

            if (RBASIC(obj)->flags & ROBJECT_EMBED) {
                newptr = obj_ivar_heap_alloc(obj, newsize);
                MEMCPY(newptr, ptr, VALUE, len);
                RBASIC(obj)->flags &= ~ROBJECT_EMBED;
                ROBJECT(obj)->as.heap.ivptr = newptr;
            }
            else {
                newptr = obj_ivar_heap_realloc(obj, len, newsize);
            }
            for (; len < newsize; len++) {
                newptr[len] = Qundef;
            }
            ROBJECT(obj)->as.heap.numiv = newsize;
            ROBJECT(obj)->as.heap.iv_index_tbl = ivup.u.iv_index_tbl;
        }
    }
    RB_OBJ_WRITE(obj, &ROBJECT_IVPTR(obj)[ivup.index], val);

    return val;
}

static void
ivar_set(VALUE obj, ID id, VALUE val)
{
    RB_DEBUG_COUNTER_INC(ivar_set_base);

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        obj_ivar_set(obj, id, val);
        break;
      case T_CLASS:
      case T_MODULE:
        if (!RCLASS_IV_TBL(obj)) RCLASS_IV_TBL(obj) = st_init_numtable();
        rb_class_ivar_set(obj, id, val);
        break;
      default:
        generic_ivar_set(obj, id, val);
        break;
    }
}

VALUE
rb_ivar_set(VALUE obj, ID id, VALUE val)
{
    rb_check_frozen(obj);
    ivar_set(obj, id, val);
    return val;
}

void
rb_ivar_set_internal(VALUE obj, ID id, VALUE val)
{
    // should be internal instance variable name (no @ prefix)
    VM_ASSERT(!rb_is_instance_id(id));

    ivar_set(obj, id, val);
}

VALUE
rb_ivar_defined(VALUE obj, ID id)
{
    VALUE val;
    struct st_table *iv_index_tbl;
    st_data_t index;

    if (SPECIAL_CONST_P(obj)) return Qfalse;
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);
        if (!iv_index_tbl) break;
        if (!st_lookup(iv_index_tbl, (st_data_t)id, &index)) break;
        if (ROBJECT_NUMIV(obj) <= index) break;
        val = ROBJECT_IVPTR(obj)[index];
        if (val != Qundef)
            return Qtrue;
	break;
      case T_CLASS:
      case T_MODULE:
	if (RCLASS_IV_TBL(obj) && st_is_member(RCLASS_IV_TBL(obj), (st_data_t)id))
	    return Qtrue;
	break;
      default:
	if (FL_TEST(obj, FL_EXIVAR))
	    return generic_ivar_defined(obj, id);
	break;
    }
    return Qfalse;
}

typedef int rb_ivar_foreach_callback_func(ID key, VALUE val, st_data_t arg);

struct obj_ivar_tag {
    VALUE obj;
    rb_ivar_foreach_callback_func *func;
    st_data_t arg;
};

static int
obj_ivar_i(st_data_t key, st_data_t index, st_data_t arg)
{
    struct obj_ivar_tag *data = (struct obj_ivar_tag *)arg;
    if (index < ROBJECT_NUMIV(data->obj)) {
        VALUE val = ROBJECT_IVPTR(data->obj)[index];
        if (val != Qundef) {
            return (data->func)((ID)key, val, data->arg);
        }
    }
    return ST_CONTINUE;
}

static void
obj_ivar_each(VALUE obj, rb_ivar_foreach_callback_func *func, st_data_t arg)
{
    st_table *tbl;
    struct obj_ivar_tag data;

    tbl = ROBJECT_IV_INDEX_TBL(obj);
    if (!tbl)
        return;

    data.obj = obj;
    data.func = (int (*)(ID key, VALUE val, st_data_t arg))func;
    data.arg = arg;

    st_foreach_safe(tbl, obj_ivar_i, (st_data_t)&data);
}

struct gen_ivar_tag {
    struct gen_ivtbl *ivtbl;
    rb_ivar_foreach_callback_func *func;
    st_data_t arg;
};

static int
gen_ivar_each_i(st_data_t key, st_data_t index, st_data_t data)
{
    struct gen_ivar_tag *arg = (struct gen_ivar_tag *)data;

    if (index < arg->ivtbl->numiv) {
        VALUE val = arg->ivtbl->ivptr[index];
        if (val != Qundef) {
            return (arg->func)((ID)key, val, arg->arg);
        }
    }
    return ST_CONTINUE;
}

static void
gen_ivar_each(VALUE obj, rb_ivar_foreach_callback_func *func, st_data_t arg)
{
    struct gen_ivar_tag data;
    st_table *iv_index_tbl = RCLASS_IV_INDEX_TBL(rb_obj_class(obj));

    if (!iv_index_tbl) return;
    if (!gen_ivtbl_get(obj, &data.ivtbl)) return;

    data.func = (int (*)(ID key, VALUE val, st_data_t arg))func;
    data.arg = arg;

    st_foreach_safe(iv_index_tbl, gen_ivar_each_i, (st_data_t)&data);
}

struct givar_copy {
    VALUE obj;
    st_table *iv_index_tbl;
    struct gen_ivtbl *ivtbl;
};

static int
gen_ivar_copy(ID id, VALUE val, st_data_t arg)
{
    struct givar_copy *c = (struct givar_copy *)arg;
    struct ivar_update ivup;

    ivup.iv_extended = 0;
    ivup.u.iv_index_tbl = c->iv_index_tbl;
    iv_index_tbl_extend(&ivup, id);
    if (ivup.index >= c->ivtbl->numiv) {
	uint32_t newsize = iv_index_tbl_newsize(&ivup);
	c->ivtbl = gen_ivtbl_resize(c->ivtbl, newsize);
    }
    c->ivtbl->ivptr[ivup.index] = val;

    RB_OBJ_WRITTEN(c->obj, Qundef, val);

    return ST_CONTINUE;
}

void
rb_copy_generic_ivar(VALUE clone, VALUE obj)
{
    struct gen_ivtbl *ivtbl;

    rb_check_frozen(clone);

    if (!FL_TEST(obj, FL_EXIVAR)) {
        goto clear;
    }
    if (gen_ivtbl_get(obj, &ivtbl)) {
	struct givar_copy c;
	uint32_t i;

	if (gen_ivtbl_count(ivtbl) == 0)
	    goto clear;

	if (gen_ivtbl_get(clone, &c.ivtbl)) {
	    for (i = 0; i < c.ivtbl->numiv; i++)
		c.ivtbl->ivptr[i] = Qundef;
	}
	else {
	    c.ivtbl = gen_ivtbl_resize(0, ivtbl->numiv);
	    FL_SET(clone, FL_EXIVAR);
	}

	c.iv_index_tbl = iv_index_tbl_make(clone);
	c.obj = clone;
	gen_ivar_each(obj, gen_ivar_copy, (st_data_t)&c);
	/*
	 * c.ivtbl may change in gen_ivar_copy due to realloc,
	 * no need to free
	 */
	st_insert(generic_iv_tbl, (st_data_t)clone, (st_data_t)c.ivtbl);
    }
    return;

  clear:
    if (FL_TEST(clone, FL_EXIVAR)) {
        rb_free_generic_ivar(clone);
        FL_UNSET(clone, FL_EXIVAR);
    }
}

void
rb_ivar_foreach(VALUE obj, rb_ivar_foreach_callback_func *func, st_data_t arg)
{
    if (SPECIAL_CONST_P(obj)) return;
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        obj_ivar_each(obj, func, arg);
	break;
      case T_CLASS:
      case T_MODULE:
	if (RCLASS_IV_TBL(obj)) {
	    st_foreach_safe(RCLASS_IV_TBL(obj), func, arg);
	}
	break;
      default:
	if (FL_TEST(obj, FL_EXIVAR)) {
	    gen_ivar_each(obj, func, arg);
	}
	break;
    }
}

st_index_t
rb_ivar_count(VALUE obj)
{
    st_table *tbl;

    if (SPECIAL_CONST_P(obj)) return 0;

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
	if ((tbl = ROBJECT_IV_INDEX_TBL(obj)) != 0) {
	    st_index_t i, count, num = ROBJECT_NUMIV(obj);
	    const VALUE *const ivptr = ROBJECT_IVPTR(obj);
	    for (i = count = 0; i < num; ++i) {
		if (ivptr[i] != Qundef) {
		    count++;
		}
	    }
	    return count;
	}
	break;
      case T_CLASS:
      case T_MODULE:
	if ((tbl = RCLASS_IV_TBL(obj)) != 0) {
	    return tbl->num_entries;
	}
	break;
      default:
	if (FL_TEST(obj, FL_EXIVAR)) {
	    struct gen_ivtbl *ivtbl;

	    if (gen_ivtbl_get(obj, &ivtbl)) {
		return gen_ivtbl_count(ivtbl);
	    }
	}
	break;
    }
    return 0;
}

static int
ivar_i(st_data_t k, st_data_t v, st_data_t a)
{
    ID key = (ID)k;
    VALUE ary = (VALUE)a;

    if (rb_is_instance_id(key)) {
	rb_ary_push(ary, ID2SYM(key));
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     obj.instance_variables    -> array
 *
 *  Returns an array of instance variable names for the receiver. Note
 *  that simply defining an accessor does not create the corresponding
 *  instance variable.
 *
 *     class Fred
 *       attr_accessor :a1
 *       def initialize
 *         @iv = 3
 *       end
 *     end
 *     Fred.new.instance_variables   #=> [:@iv]
 */

VALUE
rb_obj_instance_variables(VALUE obj)
{
    VALUE ary;

    ary = rb_ary_new();
    rb_ivar_foreach(obj, ivar_i, ary);
    return ary;
}

#define rb_is_constant_id rb_is_const_id
#define rb_is_constant_name rb_is_const_name
#define id_for_var(obj, name, part, type) \
    id_for_var_message(obj, name, type, "`%1$s' is not allowed as "#part" "#type" variable name")
#define id_for_var_message(obj, name, type, message) \
    check_id_type(obj, &(name), rb_is_##type##_id, rb_is_##type##_name, message, strlen(message))
static ID
check_id_type(VALUE obj, VALUE *pname,
	      int (*valid_id_p)(ID), int (*valid_name_p)(VALUE),
	      const char *message, size_t message_len)
{
    ID id = rb_check_id(pname);
    VALUE name = *pname;

    if (id ? !valid_id_p(id) : !valid_name_p(name)) {
	rb_name_err_raise_str(rb_fstring_new(message, message_len),
			      obj, name);
    }
    return id;
}

/*
 *  call-seq:
 *     obj.remove_instance_variable(symbol)    -> obj
 *     obj.remove_instance_variable(string)    -> obj
 *
 *  Removes the named instance variable from <i>obj</i>, returning that
 *  variable's value.
 *  String arguments are converted to symbols.
 *
 *     class Dummy
 *       attr_reader :var
 *       def initialize
 *         @var = 99
 *       end
 *       def remove
 *         remove_instance_variable(:@var)
 *       end
 *     end
 *     d = Dummy.new
 *     d.var      #=> 99
 *     d.remove   #=> 99
 *     d.var      #=> nil
 */

VALUE
rb_obj_remove_instance_variable(VALUE obj, VALUE name)
{
    VALUE val = Qnil;
    const ID id = id_for_var(obj, name, an, instance);
    st_data_t n, v;
    struct st_table *iv_index_tbl;
    st_data_t index;

    rb_check_frozen(obj);
    if (!id) {
	goto not_defined;
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);
        if (!iv_index_tbl) break;
        if (!st_lookup(iv_index_tbl, (st_data_t)id, &index)) break;
        if (ROBJECT_NUMIV(obj) <= index) break;
        val = ROBJECT_IVPTR(obj)[index];
        if (val != Qundef) {
            ROBJECT_IVPTR(obj)[index] = Qundef;
            return val;
        }
	break;
      case T_CLASS:
      case T_MODULE:
	n = id;
	if (RCLASS_IV_TBL(obj) && st_delete(RCLASS_IV_TBL(obj), &n, &v)) {
	    return (VALUE)v;
	}
	break;
      default:
	if (FL_TEST(obj, FL_EXIVAR)) {
	    if (generic_ivar_remove(obj, id, &val)) {
		return val;
	    }
	}
	break;
    }

  not_defined:
    rb_name_err_raise("instance variable %1$s not defined",
		      obj, name);
    UNREACHABLE_RETURN(Qnil);
}

NORETURN(static void uninitialized_constant(VALUE, VALUE));
static void
uninitialized_constant(VALUE klass, VALUE name)
{
    if (klass && rb_class_real(klass) != rb_cObject)
	rb_name_err_raise("uninitialized constant %2$s::%1$s",
			  klass, name);
    else
	rb_name_err_raise("uninitialized constant %1$s",
			  klass, name);
}

VALUE
rb_const_missing(VALUE klass, VALUE name)
{
    VALUE value = rb_funcallv(klass, idConst_missing, 1, &name);
    rb_vm_inc_const_missing_count();
    return value;
}


/*
 * call-seq:
 *    mod.const_missing(sym)    -> obj
 *
 * Invoked when a reference is made to an undefined constant in
 * <i>mod</i>. It is passed a symbol for the undefined constant, and
 * returns a value to be used for that constant. The
 * following code is an example of the same:
 *
 *   def Foo.const_missing(name)
 *     name # return the constant name as Symbol
 *   end
 *
 *   Foo::UNDEFINED_CONST    #=> :UNDEFINED_CONST: symbol returned
 *
 * In the next example when a reference is made to an undefined constant,
 * it attempts to load a file whose name is the lowercase version of the
 * constant (thus class <code>Fred</code> is assumed to be in file
 * <code>fred.rb</code>).  If found, it returns the loaded class. It
 * therefore implements an autoload feature similar to Kernel#autoload and
 * Module#autoload.
 *
 *   def Object.const_missing(name)
 *     @looked_for ||= {}
 *     str_name = name.to_s
 *     raise "Class not found: #{name}" if @looked_for[str_name]
 *     @looked_for[str_name] = 1
 *     file = str_name.downcase
 *     require file
 *     klass = const_get(name)
 *     return klass if klass
 *     raise "Class not found: #{name}"
 *   end
 *
 */

VALUE
rb_mod_const_missing(VALUE klass, VALUE name)
{
    VALUE ref = GET_EC()->private_const_reference;
    rb_vm_pop_cfunc_frame();
    if (ref) {
	rb_name_err_raise("private constant %2$s::%1$s referenced",
			  ref, name);
    }
    uninitialized_constant(klass, name);

    UNREACHABLE_RETURN(Qnil);
}

static void
autoload_mark(void *ptr)
{
    rb_mark_tbl_no_pin((st_table *)ptr);
}

static void
autoload_free(void *ptr)
{
    st_free_table((st_table *)ptr);
}

static size_t
autoload_memsize(const void *ptr)
{
    const st_table *tbl = ptr;
    return st_memsize(tbl);
}

static void
autoload_compact(void *ptr)
{
    rb_gc_update_tbl_refs((st_table *)ptr);
}

static const rb_data_type_t autoload_data_type = {
    "autoload",
    {autoload_mark, autoload_free, autoload_memsize, autoload_compact,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#define check_autoload_table(av) \
    (struct st_table *)rb_check_typeddata((av), &autoload_data_type)

static VALUE
autoload_data(VALUE mod, ID id)
{
    struct st_table *tbl;
    st_data_t val;

    if (!st_lookup(RCLASS_IV_TBL(mod), autoload, &val) ||
	    !(tbl = check_autoload_table((VALUE)val)) ||
	    !st_lookup(tbl, (st_data_t)id, &val)) {
	return 0;
    }
    return (VALUE)val;
}

struct autoload_const {
    struct list_node cnode; /* <=> autoload_data_i.constants */
    VALUE mod;
    VALUE ad; /* autoload_data_i */
    VALUE value;
    VALUE file;
    ID id;
    rb_const_flag_t flag;
    int line;
};

/* always on stack, no need to mark */
struct autoload_state {
    struct autoload_const *ac;
    VALUE result;
    VALUE thread;
    struct list_node waitq;
};

struct autoload_data_i {
    VALUE feature;
    struct autoload_state *state; /* points to on-stack struct */
    rb_serial_t fork_gen;
    struct list_head constants; /* <=> autoload_const.cnode */
};

static void
autoload_i_compact(void *ptr)
{
    struct autoload_data_i *p = ptr;
    p->feature = rb_gc_location(p->feature);
}

static void
autoload_i_mark(void *ptr)
{
    struct autoload_data_i *p = ptr;

    rb_gc_mark_movable(p->feature);

    /* allow GC to free us if no modules refer to this via autoload_const.ad */
    if (list_empty(&p->constants)) {
        rb_hash_delete(autoload_featuremap, p->feature);
    }
}

static void
autoload_i_free(void *ptr)
{
    struct autoload_data_i *p = ptr;

    /* we may leak some memory at VM shutdown time, no big deal */
    if (list_empty(&p->constants)) {
	xfree(p);
    }
}

static size_t
autoload_i_memsize(const void *ptr)
{
    return sizeof(struct autoload_data_i);
}

static const rb_data_type_t autoload_data_i_type = {
    "autoload_i",
    {autoload_i_mark, autoload_i_free, autoload_i_memsize, autoload_i_compact},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static void
autoload_c_compact(void *ptr)
{
    struct autoload_const *ac = ptr;

    ac->mod = rb_gc_location(ac->mod);
    ac->ad = rb_gc_location(ac->ad);
    ac->value = rb_gc_location(ac->value);
    ac->file = rb_gc_location(ac->file);
}

static void
autoload_c_mark(void *ptr)
{
    struct autoload_const *ac = ptr;

    rb_gc_mark_movable(ac->mod);
    rb_gc_mark_movable(ac->ad);
    rb_gc_mark_movable(ac->value);
    rb_gc_mark_movable(ac->file);
}

static void
autoload_c_free(void *ptr)
{
    struct autoload_const *ac = ptr;
    list_del(&ac->cnode);
    xfree(ac);
}

static size_t
autoload_c_memsize(const void *ptr)
{
    return sizeof(struct autoload_const);
}

static const rb_data_type_t autoload_const_type = {
    "autoload_const",
    {autoload_c_mark, autoload_c_free, autoload_c_memsize, autoload_c_compact,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static struct autoload_data_i *
get_autoload_data(VALUE acv, struct autoload_const **acp)
{
    struct autoload_const *ac = rb_check_typeddata(acv, &autoload_const_type);
    struct autoload_data_i *ele;

    ele = rb_check_typeddata(ac->ad, &autoload_data_i_type);
    /* do not reach across stack for ->state after forking: */
    if (ele && ele->state && ele->fork_gen != GET_VM()->fork_gen) {
        ele->state = 0;
        ele->fork_gen = 0;
    }
    if (acp) *acp = ac;
    return ele;
}

RUBY_FUNC_EXPORTED void
rb_autoload(VALUE mod, ID id, const char *file)
{
    if (!file || !*file) {
	rb_raise(rb_eArgError, "empty file name");
    }
    rb_autoload_str(mod, id, rb_fstring_cstr(file));
}

void
rb_autoload_str(VALUE mod, ID id, VALUE file)
{
    st_data_t av;
    VALUE ad;
    struct st_table *tbl;
    struct autoload_data_i *ele;
    rb_const_entry_t *ce;

    if (!rb_is_const_id(id)) {
	rb_raise(rb_eNameError, "autoload must be constant name: %"PRIsVALUE"",
		 QUOTE_ID(id));
    }

    Check_Type(file, T_STRING);
    if (!RSTRING_LEN(file)) {
	rb_raise(rb_eArgError, "empty file name");
    }

    ce = rb_const_lookup(mod, id);
    if (ce && ce->value != Qundef) {
	return;
    }

    rb_const_set(mod, id, Qundef);
    tbl = RCLASS_IV_TBL(mod);
    if (tbl && st_lookup(tbl, (st_data_t)autoload, &av)) {
	tbl = check_autoload_table((VALUE)av);
    }
    else {
	if (!tbl) tbl = RCLASS_IV_TBL(mod) = st_init_numtable();
	av = (st_data_t)TypedData_Wrap_Struct(0, &autoload_data_type, 0);
	st_add_direct(tbl, (st_data_t)autoload, av);
	RB_OBJ_WRITTEN(mod, Qnil, av);
	DATA_PTR(av) = tbl = st_init_numtable();
    }

    file = rb_fstring(file);
    if (!autoload_featuremap) {
        autoload_featuremap = rb_ident_hash_new();
        rb_obj_hide(autoload_featuremap);
        rb_gc_register_mark_object(autoload_featuremap);
    }
    ad = rb_hash_aref(autoload_featuremap, file);
    if (NIL_P(ad)) {
        ad = TypedData_Make_Struct(0, struct autoload_data_i,
                                    &autoload_data_i_type, ele);
        ele->feature = file;
        ele->state = 0;
        list_head_init(&ele->constants);
        rb_hash_aset(autoload_featuremap, file, ad);
    }
    else {
        ele = rb_check_typeddata(ad, &autoload_data_i_type);
    }
    {
        VALUE acv;
        struct autoload_const *ac;
        acv = TypedData_Make_Struct(0, struct autoload_const,
                                    &autoload_const_type, ac);
        ac->mod = mod;
        ac->id = id;
        ac->value = Qundef;
        ac->flag = CONST_PUBLIC;
        ac->ad = ad;
        list_add_tail(&ele->constants, &ac->cnode);
        st_insert(tbl, (st_data_t)id, (st_data_t)acv);
    }
}

static void
autoload_delete(VALUE mod, ID id)
{
    st_data_t val, load = 0, n = id;

    if (st_lookup(RCLASS_IV_TBL(mod), (st_data_t)autoload, &val)) {
	struct st_table *tbl = check_autoload_table((VALUE)val);
	struct autoload_data_i *ele;
	struct autoload_const *ac;

	st_delete(tbl, &n, &load);
	ele = get_autoload_data((VALUE)load, &ac);
	VM_ASSERT(ele);
	if (ele) {
	    VM_ASSERT(!list_empty(&ele->constants));
	}

	/*
	 * we must delete here to avoid "already initialized" warnings
	 * with parallel autoload.  Using list_del_init here so list_del
	 * works in autoload_c_free
	 */
	list_del_init(&ac->cnode);

	if (tbl->num_entries == 0) {
	    n = autoload;
	    st_delete(RCLASS_IV_TBL(mod), &n, &val);
	}
    }
}

static VALUE
check_autoload_required(VALUE mod, ID id, const char **loadingpath)
{
    VALUE file;
    VALUE load = autoload_data(mod, id);
    struct autoload_data_i *ele;
    const char *loading;

    if (!load || !(ele = get_autoload_data(load, 0))) {
	return 0;
    }
    file = ele->feature;
    Check_Type(file, T_STRING);
    if (!RSTRING_LEN(file) || !*RSTRING_PTR(file)) {
	rb_raise(rb_eArgError, "empty file name");
    }

    /*
     * if somebody else is autoloading, we MUST wait for them, since
     * rb_provide_feature can provide a feature before autoload_const_set
     * completes.  We must wait until autoload_const_set finishes in
     * the other thread.
     */
    if (ele->state && ele->state->thread != rb_thread_current()) {
	return load;
    }

    loading = RSTRING_PTR(file);
    if (!rb_feature_provided(loading, &loading)) {
	return load;
    }
    if (loadingpath && loading) {
	*loadingpath = loading;
	return load;
    }
    return 0;
}

static struct autoload_const *autoloading_const_entry(VALUE mod, ID id);

MJIT_FUNC_EXPORTED int
rb_autoloading_value(VALUE mod, ID id, VALUE* value, rb_const_flag_t *flag)
{
    struct autoload_const *ac = autoloading_const_entry(mod, id);
    if (!ac) return FALSE;

    if (value) {
        *value = ac->value;
    }
    if (flag) {
        *flag = ac->flag;
    }
    return TRUE;
}

struct autoload_const *
autoloading_const_entry(VALUE mod, ID id)
{
    VALUE load = autoload_data(mod, id);
    struct autoload_data_i *ele;
    struct autoload_const *ac;

    if (!load || !(ele = get_autoload_data(load, &ac))) {
        return 0;
    }

    if (ele->state && ele->state->thread == rb_thread_current()) {
	if (ac->value != Qundef) {
            return ac;
	}
    }
    return 0;
}

static int
autoload_defined_p(VALUE mod, ID id)
{
    rb_const_entry_t *ce = rb_const_lookup(mod, id);

    if (!ce || ce->value != Qundef) {
	return 0;
    }
    return !rb_autoloading_value(mod, id, NULL, NULL);
}

static void const_tbl_update(struct autoload_const *);

static VALUE
autoload_const_set(struct autoload_const *ac)
{
    VALUE klass = ac->mod;
    ID id = ac->id;
    check_before_mod_set(klass, id, ac->value, "constant");
    const_tbl_update(ac);
    return 0;			/* ignored */
}

static VALUE
autoload_require(VALUE arg)
{
    struct autoload_state *state = (struct autoload_state *)arg;
    struct autoload_const *ac = state->ac;
    struct autoload_data_i *ele;

    ele = rb_check_typeddata(ac->ad, &autoload_data_i_type);
    /* this may release GVL and switch threads: */
    state->result = rb_funcall(rb_vm_top_self(), rb_intern("require"), 1,
			       ele->feature);

    return state->result;
}

static VALUE
autoload_reset(VALUE arg)
{
    struct autoload_state *state = (struct autoload_state *)arg;
    int need_wakeups = 0;
    struct autoload_const *ac = state->ac;
    struct autoload_data_i *ele;

    ele = rb_check_typeddata(ac->ad, &autoload_data_i_type);
    if (ele->state == state) {
        need_wakeups = 1;
        ele->state = 0;
        ele->fork_gen = 0;
    }

    /* At the last, move a value defined in autoload to constant table */
    if (RTEST(state->result)) {
        struct autoload_const *next;

        list_for_each_safe(&ele->constants, ac, next, cnode) {
            if (ac->value != Qundef) {
                autoload_const_set(ac);
            }
        }
    }

    /* wakeup any waiters we had */
    if (need_wakeups) {
	struct autoload_state *cur = 0, *nxt;

	list_for_each_safe((struct list_head *)&state->waitq, cur, nxt, waitq) {
	    VALUE th = cur->thread;

	    cur->thread = Qfalse;
	    list_del_init(&cur->waitq); /* idempotent */

	    /*
	     * cur is stored on the stack of cur->waiting_th,
	     * do not touch cur after waking up waiting_th
	     */
	    rb_thread_wakeup_alive(th);
	}
    }

    return 0;			/* ignored */
}

static VALUE
autoload_sleep(VALUE arg)
{
    struct autoload_state *state = (struct autoload_state *)arg;

    /*
     * autoload_reset in other thread will resume us and remove us
     * from the waitq list
     */
    do {
	rb_thread_sleep_deadly();
    } while (state->thread != Qfalse);

    return Qfalse;
}

static VALUE
autoload_sleep_done(VALUE arg)
{
    struct autoload_state *state = (struct autoload_state *)arg;

    if (state->thread != Qfalse && rb_thread_to_be_killed(state->thread)) {
	list_del(&state->waitq); /* idempotent after list_del_init */
    }

    return Qfalse;
}

VALUE
rb_autoload_load(VALUE mod, ID id)
{
    VALUE load, result;
    const char *loading = 0, *src;
    struct autoload_data_i *ele;
    struct autoload_const *ac;
    struct autoload_state state;
    int flag = -1;
    rb_const_entry_t *ce;

    if (!autoload_defined_p(mod, id)) return Qfalse;
    load = check_autoload_required(mod, id, &loading);
    if (!load) return Qfalse;
    src = rb_sourcefile();
    if (src && loading && strcmp(src, loading) == 0) return Qfalse;

    if ((ce = rb_const_lookup(mod, id))) {
        flag = ce->flag & (CONST_DEPRECATED | CONST_VISIBILITY_MASK);
    }

    /* set ele->state for a marker of autoloading thread */
    if (!(ele = get_autoload_data(load, &ac))) {
	return Qfalse;
    }
    state.ac = ac;
    state.thread = rb_thread_current();
    if (!ele->state) {
	ele->state = &state;
	ele->fork_gen = GET_VM()->fork_gen;

	/*
	 * autoload_reset will wake up any threads added to this
	 * iff the GVL is released during autoload_require
	 */
	list_head_init((struct list_head *)&state.waitq);
    }
    else if (state.thread == ele->state->thread) {
	return Qfalse;
    }
    else {
	list_add_tail((struct list_head *)&ele->state->waitq, &state.waitq);

	rb_ensure(autoload_sleep, (VALUE)&state,
		autoload_sleep_done, (VALUE)&state);
    }

    /* autoload_data_i can be deleted by another thread while require */
    state.result = Qfalse;
    result = rb_ensure(autoload_require, (VALUE)&state,
		       autoload_reset, (VALUE)&state);

    if (flag > 0 && (ce = rb_const_lookup(mod, id))) {
        ce->flag |= flag;
    }
    RB_GC_GUARD(load);
    return result;
}

VALUE
rb_autoload_p(VALUE mod, ID id)
{
    return rb_autoload_at_p(mod, id, TRUE);
}

VALUE
rb_autoload_at_p(VALUE mod, ID id, int recur)
{
    VALUE load;
    struct autoload_data_i *ele;

    while (!autoload_defined_p(mod, id)) {
        if (!recur) return Qnil;
	mod = RCLASS_SUPER(mod);
	if (!mod) return Qnil;
    }
    load = check_autoload_required(mod, id, 0);
    if (!load) return Qnil;
    return (ele = get_autoload_data(load, 0)) ? ele->feature : Qnil;
}

MJIT_FUNC_EXPORTED void
rb_const_warn_if_deprecated(const rb_const_entry_t *ce, VALUE klass, ID id)
{
    if (RB_CONST_DEPRECATED_P(ce) &&
        rb_warning_category_enabled_p(RB_WARN_CATEGORY_DEPRECATED)) {
	if (klass == rb_cObject) {
	    rb_warn("constant ::%"PRIsVALUE" is deprecated", QUOTE_ID(id));
	}
	else {
	    rb_warn("constant %"PRIsVALUE"::%"PRIsVALUE" is deprecated",
		    rb_class_name(klass), QUOTE_ID(id));
	}
    }
}

static VALUE
rb_const_get_0(VALUE klass, ID id, int exclude, int recurse, int visibility)
{
    VALUE c = rb_const_search(klass, id, exclude, recurse, visibility);
    if (c != Qundef) return c;
    return rb_const_missing(klass, ID2SYM(id));
}

static VALUE
rb_const_search_from(VALUE klass, ID id, int exclude, int recurse, int visibility)
{
    VALUE value, tmp;

    tmp = klass;
    while (RTEST(tmp)) {
	VALUE am = 0;
	rb_const_entry_t *ce;

	while ((ce = rb_const_lookup(tmp, id))) {
	    if (visibility && RB_CONST_PRIVATE_P(ce)) {
		if (BUILTIN_TYPE(tmp) == T_ICLASS) tmp = RBASIC(tmp)->klass;
		GET_EC()->private_const_reference = tmp;
		return Qundef;
	    }
	    rb_const_warn_if_deprecated(ce, tmp, id);
	    value = ce->value;
	    if (value == Qundef) {
                struct autoload_const *ac;
		if (am == tmp) break;
		am = tmp;
                ac = autoloading_const_entry(tmp, id);
                if (ac) return ac->value;
		rb_autoload_load(tmp, id);
		continue;
	    }
            if (exclude && tmp == rb_cObject) {
		goto not_found;
	    }
	    return value;
	}
	if (!recurse) break;
	tmp = RCLASS_SUPER(tmp);
    }

  not_found:
    GET_EC()->private_const_reference = 0;
    return Qundef;
}

static VALUE
rb_const_search(VALUE klass, ID id, int exclude, int recurse, int visibility)
{
    VALUE value;

    if (klass == rb_cObject) exclude = FALSE;
    value = rb_const_search_from(klass, id, exclude, recurse, visibility);
    if (value != Qundef) return value;
    if (exclude) return value;
    if (BUILTIN_TYPE(klass) != T_MODULE) return value;
    /* search global const too, if klass is a module */
    return rb_const_search_from(rb_cObject, id, FALSE, recurse, visibility);
}

VALUE
rb_const_get_from(VALUE klass, ID id)
{
    return rb_const_get_0(klass, id, TRUE, TRUE, FALSE);
}

VALUE
rb_const_get(VALUE klass, ID id)
{
    return rb_const_get_0(klass, id, FALSE, TRUE, FALSE);
}

VALUE
rb_const_get_at(VALUE klass, ID id)
{
    return rb_const_get_0(klass, id, TRUE, FALSE, FALSE);
}

MJIT_FUNC_EXPORTED VALUE
rb_public_const_get_from(VALUE klass, ID id)
{
    return rb_const_get_0(klass, id, TRUE, TRUE, TRUE);
}

MJIT_FUNC_EXPORTED VALUE
rb_public_const_get_at(VALUE klass, ID id)
{
    return rb_const_get_0(klass, id, TRUE, FALSE, TRUE);
}

NORETURN(static void undefined_constant(VALUE mod, VALUE name));
static void
undefined_constant(VALUE mod, VALUE name)
{
    rb_name_err_raise("constant %2$s::%1$s not defined",
                      mod, name);
}

static VALUE
rb_const_location_from(VALUE klass, ID id, int exclude, int recurse, int visibility)
{
    while (RTEST(klass)) {
        rb_const_entry_t *ce;

        while ((ce = rb_const_lookup(klass, id))) {
            if (visibility && RB_CONST_PRIVATE_P(ce)) {
                return Qnil;
            }
            if (exclude && klass == rb_cObject) {
                goto not_found;
            }
            if (NIL_P(ce->file)) return rb_ary_new();
            return rb_assoc_new(ce->file, INT2NUM(ce->line));
        }
        if (!recurse) break;
        klass = RCLASS_SUPER(klass);
    }

  not_found:
    return Qnil;
}

static VALUE
rb_const_location(VALUE klass, ID id, int exclude, int recurse, int visibility)
{
    VALUE loc;

    if (klass == rb_cObject) exclude = FALSE;
    loc = rb_const_location_from(klass, id, exclude, recurse, visibility);
    if (!NIL_P(loc)) return loc;
    if (exclude) return loc;
    if (BUILTIN_TYPE(klass) != T_MODULE) return loc;
    /* search global const too, if klass is a module */
    return rb_const_location_from(rb_cObject, id, FALSE, recurse, visibility);
}

VALUE
rb_const_source_location(VALUE klass, ID id)
{
    return rb_const_location(klass, id, FALSE, TRUE, FALSE);
}

MJIT_FUNC_EXPORTED VALUE
rb_const_source_location_at(VALUE klass, ID id)
{
    return rb_const_location(klass, id, TRUE, FALSE, FALSE);
}

/*
 *  call-seq:
 *     remove_const(sym)   -> obj
 *
 *  Removes the definition of the given constant, returning that
 *  constant's previous value.  If that constant referred to
 *  a module, this will not change that module's name and can lead
 *  to confusion.
 */

VALUE
rb_mod_remove_const(VALUE mod, VALUE name)
{
    const ID id = id_for_var(mod, name, a, constant);

    if (!id) {
        undefined_constant(mod, name);
    }
    return rb_const_remove(mod, id);
}

VALUE
rb_const_remove(VALUE mod, ID id)
{
    VALUE val;
    rb_const_entry_t *ce;

    rb_check_frozen(mod);
    ce = rb_const_lookup(mod, id);
    if (!ce || !rb_id_table_delete(RCLASS_CONST_TBL(mod), id)) {
	if (rb_const_defined_at(mod, id)) {
	    rb_name_err_raise("cannot remove %2$s::%1$s",
			      mod, ID2SYM(id));
	}
        undefined_constant(mod, ID2SYM(id));
    }

    rb_clear_constant_cache();

    val = ce->value;
    if (val == Qundef) {
	autoload_delete(mod, id);
	val = Qnil;
    }
    xfree(ce);
    return val;
}

static int
cv_i_update(st_data_t *k, st_data_t *v, st_data_t a, int existing)
{
    if (existing) return ST_STOP;
    *v = a;
    return ST_CONTINUE;
}

static enum rb_id_table_iterator_result
sv_i(ID key, VALUE v, void *a)
{
    rb_const_entry_t *ce = (rb_const_entry_t *)v;
    st_table *tbl = a;

    if (rb_is_const_id(key)) {
	st_update(tbl, (st_data_t)key, cv_i_update, (st_data_t)ce);
    }
    return ID_TABLE_CONTINUE;
}

static enum rb_id_table_iterator_result
rb_local_constants_i(ID const_name, VALUE const_value, void *ary)
{
    if (rb_is_const_id(const_name) && !RB_CONST_PRIVATE_P((rb_const_entry_t *)const_value)) {
	rb_ary_push((VALUE)ary, ID2SYM(const_name));
    }
    return ID_TABLE_CONTINUE;
}

static VALUE
rb_local_constants(VALUE mod)
{
    struct rb_id_table *tbl = RCLASS_CONST_TBL(mod);
    VALUE ary;

    if (!tbl) return rb_ary_new2(0);

    ary = rb_ary_new2(rb_id_table_size(tbl));
    rb_id_table_foreach(tbl, rb_local_constants_i, (void *)ary);
    return ary;
}

void*
rb_mod_const_at(VALUE mod, void *data)
{
    st_table *tbl = data;
    if (!tbl) {
	tbl = st_init_numtable();
    }
    if (RCLASS_CONST_TBL(mod)) {
	rb_id_table_foreach(RCLASS_CONST_TBL(mod), sv_i, tbl);
    }
    return tbl;
}

void*
rb_mod_const_of(VALUE mod, void *data)
{
    VALUE tmp = mod;
    for (;;) {
	data = rb_mod_const_at(tmp, data);
	tmp = RCLASS_SUPER(tmp);
	if (!tmp) break;
	if (tmp == rb_cObject && mod != rb_cObject) break;
    }
    return data;
}

static int
list_i(st_data_t key, st_data_t value, VALUE ary)
{
    ID sym = (ID)key;
    rb_const_entry_t *ce = (rb_const_entry_t *)value;
    if (RB_CONST_PUBLIC_P(ce)) rb_ary_push(ary, ID2SYM(sym));
    return ST_CONTINUE;
}

VALUE
rb_const_list(void *data)
{
    st_table *tbl = data;
    VALUE ary;

    if (!tbl) return rb_ary_new2(0);
    ary = rb_ary_new2(tbl->num_entries);
    st_foreach_safe(tbl, list_i, ary);
    st_free_table(tbl);

    return ary;
}

/*
 *  call-seq:
 *     mod.constants(inherit=true)    -> array
 *
 *  Returns an array of the names of the constants accessible in
 *  <i>mod</i>. This includes the names of constants in any included
 *  modules (example at start of section), unless the <i>inherit</i>
 *  parameter is set to <code>false</code>.
 *
 *  The implementation makes no guarantees about the order in which the
 *  constants are yielded.
 *
 *    IO.constants.include?(:SYNC)        #=> true
 *    IO.constants(false).include?(:SYNC) #=> false
 *
 *  Also see Module#const_defined?.
 */

VALUE
rb_mod_constants(int argc, const VALUE *argv, VALUE mod)
{
    bool inherit = true;

    if (rb_check_arity(argc, 0, 1)) inherit = RTEST(argv[0]);

    if (inherit) {
	return rb_const_list(rb_mod_const_of(mod, 0));
    }
    else {
	return rb_local_constants(mod);
    }
}

static int
rb_const_defined_0(VALUE klass, ID id, int exclude, int recurse, int visibility)
{
    VALUE tmp;
    int mod_retry = 0;
    rb_const_entry_t *ce;

    tmp = klass;
  retry:
    while (tmp) {
	if ((ce = rb_const_lookup(tmp, id))) {
	    if (visibility && RB_CONST_PRIVATE_P(ce)) {
		return (int)Qfalse;
	    }
	    if (ce->value == Qundef && !check_autoload_required(tmp, id, 0) &&
		!rb_autoloading_value(tmp, id, NULL, NULL))
		return (int)Qfalse;

	    if (exclude && tmp == rb_cObject && klass != rb_cObject) {
		return (int)Qfalse;
	    }

	    return (int)Qtrue;
	}
	if (!recurse) break;
	tmp = RCLASS_SUPER(tmp);
    }
    if (!exclude && !mod_retry && BUILTIN_TYPE(klass) == T_MODULE) {
	mod_retry = 1;
	tmp = rb_cObject;
	goto retry;
    }
    return (int)Qfalse;
}

int
rb_const_defined_from(VALUE klass, ID id)
{
    return rb_const_defined_0(klass, id, TRUE, TRUE, FALSE);
}

int
rb_const_defined(VALUE klass, ID id)
{
    return rb_const_defined_0(klass, id, FALSE, TRUE, FALSE);
}

int
rb_const_defined_at(VALUE klass, ID id)
{
    return rb_const_defined_0(klass, id, TRUE, FALSE, FALSE);
}

MJIT_FUNC_EXPORTED int
rb_public_const_defined_from(VALUE klass, ID id)
{
    return rb_const_defined_0(klass, id, TRUE, TRUE, TRUE);
}

static void
check_before_mod_set(VALUE klass, ID id, VALUE val, const char *dest)
{
    rb_check_frozen(klass);
}

static void set_namespace_path(VALUE named_namespace, VALUE name);

static enum rb_id_table_iterator_result
set_namespace_path_i(ID id, VALUE v, void *payload)
{
    rb_const_entry_t *ce = (rb_const_entry_t *)v;
    VALUE value = ce->value;
    int has_permanent_classpath;
    VALUE parental_path = *((VALUE *) payload);
    if (!rb_is_const_id(id)) {
        return ID_TABLE_CONTINUE;
    }
    if (!rb_namespace_p(value)) {
        return ID_TABLE_CONTINUE;
    }
    classname(value, &has_permanent_classpath);
    if (has_permanent_classpath) {
        return ID_TABLE_CONTINUE;
    }
    set_namespace_path(value, build_const_path(parental_path, id));
    if (RCLASS_IV_TBL(value)) {
        st_data_t tmp = tmp_classpath;
        st_delete(RCLASS_IV_TBL(value), &tmp, 0);
    }

    return ID_TABLE_CONTINUE;
}

/*
 * Assign permanent classpaths to all namespaces that are directly or indirectly
 * nested under +named_namespace+. +named_namespace+ must have a permanent
 * classpath.
 */
static void
set_namespace_path(VALUE named_namespace, VALUE namespace_path)
{
    struct rb_id_table *const_table = RCLASS_CONST_TBL(named_namespace);
    if (!RCLASS_IV_TBL(named_namespace)) {
        RCLASS_IV_TBL(named_namespace) = st_init_numtable();
    }
    rb_class_ivar_set(named_namespace, classpath, namespace_path);
    if (const_table) {
        rb_id_table_foreach(const_table, set_namespace_path_i, &namespace_path);
    }
}

void
rb_const_set(VALUE klass, ID id, VALUE val)
{
    rb_const_entry_t *ce;
    struct rb_id_table *tbl = RCLASS_CONST_TBL(klass);

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class/module to define constant %"PRIsVALUE"",
		 QUOTE_ID(id));
    }

    check_before_mod_set(klass, id, val, "constant");
    if (!tbl) {
	RCLASS_CONST_TBL(klass) = tbl = rb_id_table_create(0);
	rb_clear_constant_cache();
	ce = ZALLOC(rb_const_entry_t);
	rb_id_table_insert(tbl, id, (VALUE)ce);
	setup_const_entry(ce, klass, val, CONST_PUBLIC);
    }
    else {
        struct autoload_const ac = {
            .mod = klass, .id = id,
            .value = val, .flag = CONST_PUBLIC,
            /* fill the rest with 0 */
        };
	const_tbl_update(&ac);
    }
    /*
     * Resolve and cache class name immediately to resolve ambiguity
     * and avoid order-dependency on const_tbl
     */
    if (rb_cObject && rb_namespace_p(val)) {
        int val_path_permanent;
        VALUE val_path = classname(val, &val_path_permanent);
        if (NIL_P(val_path) || !val_path_permanent) {
	    if (klass == rb_cObject) {
                set_namespace_path(val, rb_id2str(id));
	    }
	    else {
                int parental_path_permanent;
                VALUE parental_path = classname(klass, &parental_path_permanent);
                if (NIL_P(parental_path)) {
                    int throwaway;
                    parental_path = rb_tmp_class_path(klass, &throwaway, make_temporary_path);
                }
                if (parental_path_permanent && !val_path_permanent) {
                    set_namespace_path(val, build_const_path(parental_path, id));
                }
                else if (!parental_path_permanent && NIL_P(val_path)) {
                    rb_ivar_set(val, tmp_classpath, build_const_path(parental_path, id));
                }
	    }
	}
    }
}

static struct autoload_data_i *
current_autoload_data(VALUE mod, ID id, struct autoload_const **acp)
{
    struct autoload_data_i *ele;
    VALUE load = autoload_data(mod, id);
    if (!load) return 0;
    ele = get_autoload_data(load, acp);
    if (!ele) return 0;
    /* for autoloading thread, keep the defined value to autoloading storage */
    if (ele->state && (ele->state->thread == rb_thread_current())) {
	return ele;
    }
    return 0;
}

static void
const_tbl_update(struct autoload_const *ac)
{
    VALUE value;
    VALUE klass = ac->mod;
    VALUE val = ac->value;
    ID id = ac->id;
    struct rb_id_table *tbl = RCLASS_CONST_TBL(klass);
    rb_const_flag_t visibility = ac->flag;
    rb_const_entry_t *ce;

    if (rb_id_table_lookup(tbl, id, &value)) {
	ce = (rb_const_entry_t *)value;
	if (ce->value == Qundef) {
	    struct autoload_data_i *ele = current_autoload_data(klass, id, &ac);

	    if (ele) {
		rb_clear_constant_cache();

		ac->value = val; /* autoload_i is non-WB-protected */
                ac->file = rb_source_location(&ac->line);
	    }
            else {
                /* otherwise autoloaded constant, allow to override */
                autoload_delete(klass, id);
                ce->flag = visibility;
                RB_OBJ_WRITE(klass, &ce->value, val);
                RB_OBJ_WRITE(klass, &ce->file, ac->file);
                ce->line = ac->line;
            }
            return;
	}
	else {
	    VALUE name = QUOTE_ID(id);
	    visibility = ce->flag;
	    if (klass == rb_cObject)
		rb_warn("already initialized constant %"PRIsVALUE"", name);
	    else
		rb_warn("already initialized constant %"PRIsVALUE"::%"PRIsVALUE"",
			rb_class_name(klass), name);
	    if (!NIL_P(ce->file) && ce->line) {
		rb_compile_warn(RSTRING_PTR(ce->file), ce->line,
				"previous definition of %"PRIsVALUE" was here", name);
	    }
	}
	rb_clear_constant_cache();
	setup_const_entry(ce, klass, val, visibility);
    }
    else {
	rb_clear_constant_cache();

	ce = ZALLOC(rb_const_entry_t);
	rb_id_table_insert(tbl, id, (VALUE)ce);
	setup_const_entry(ce, klass, val, visibility);
    }
}

static void
setup_const_entry(rb_const_entry_t *ce, VALUE klass, VALUE val,
		  rb_const_flag_t visibility)
{
    ce->flag = visibility;
    RB_OBJ_WRITE(klass, &ce->value, val);
    RB_OBJ_WRITE(klass, &ce->file, rb_source_location(&ce->line));
}

void
rb_define_const(VALUE klass, const char *name, VALUE val)
{
    ID id = rb_intern(name);

    if (!rb_is_const_id(id)) {
	rb_warn("rb_define_const: invalid name `%s' for constant", name);
    }
    rb_gc_register_mark_object(val);
    rb_const_set(klass, id, val);
}

void
rb_define_global_const(const char *name, VALUE val)
{
    rb_define_const(rb_cObject, name, val);
}

static void
set_const_visibility(VALUE mod, int argc, const VALUE *argv,
		     rb_const_flag_t flag, rb_const_flag_t mask)
{
    int i;
    rb_const_entry_t *ce;
    ID id;

    rb_class_modify_check(mod);
    if (argc == 0) {
	rb_warning("%"PRIsVALUE" with no argument is just ignored",
		   QUOTE_ID(rb_frame_callee()));
	return;
    }

    for (i = 0; i < argc; i++) {
	struct autoload_const *ac;
	VALUE val = argv[i];
	id = rb_check_id(&val);
	if (!id) {
	    if (i > 0) {
		rb_clear_constant_cache();
	    }

            undefined_constant(mod, val);
	}
	if ((ce = rb_const_lookup(mod, id))) {
	    ce->flag &= ~mask;
	    ce->flag |= flag;
	    if (ce->value == Qundef) {
		struct autoload_data_i *ele;

		ele = current_autoload_data(mod, id, &ac);
		if (ele) {
		    ac->flag &= ~mask;
		    ac->flag |= flag;
		}
	    }
	}
	else {
	    if (i > 0) {
		rb_clear_constant_cache();
	    }
            undefined_constant(mod, ID2SYM(id));
	}
    }
    rb_clear_constant_cache();
}

void
rb_deprecate_constant(VALUE mod, const char *name)
{
    rb_const_entry_t *ce;
    ID id;
    long len = strlen(name);

    rb_class_modify_check(mod);
    if (!(id = rb_check_id_cstr(name, len, NULL))) {
        undefined_constant(mod, rb_fstring_new(name, len));
    }
    if (!(ce = rb_const_lookup(mod, id))) {
        undefined_constant(mod, ID2SYM(id));
    }
    ce->flag |= CONST_DEPRECATED;
}

/*
 *  call-seq:
 *     mod.private_constant(symbol, ...)    => mod
 *
 *  Makes a list of existing constants private.
 */

VALUE
rb_mod_private_constant(int argc, const VALUE *argv, VALUE obj)
{
    set_const_visibility(obj, argc, argv, CONST_PRIVATE, CONST_VISIBILITY_MASK);
    return obj;
}

/*
 *  call-seq:
 *     mod.public_constant(symbol, ...)    => mod
 *
 *  Makes a list of existing constants public.
 */

VALUE
rb_mod_public_constant(int argc, const VALUE *argv, VALUE obj)
{
    set_const_visibility(obj, argc, argv, CONST_PUBLIC, CONST_VISIBILITY_MASK);
    return obj;
}

/*
 *  call-seq:
 *     mod.deprecate_constant(symbol, ...)    => mod
 *
 *  Makes a list of existing constants deprecated. Attempt
 *  to refer to them will produce a warning.
 *
 *     module HTTP
 *       NotFound = Exception.new
 *       NOT_FOUND = NotFound # previous version of the library used this name
 *
 *       deprecate_constant :NOT_FOUND
 *     end
 *
 *     HTTP::NOT_FOUND
 *     # warning: constant HTTP::NOT_FOUND is deprecated
 *
 */

VALUE
rb_mod_deprecate_constant(int argc, const VALUE *argv, VALUE obj)
{
    set_const_visibility(obj, argc, argv, CONST_DEPRECATED, CONST_DEPRECATED);
    return obj;
}

static VALUE
original_module(VALUE c)
{
    if (RB_TYPE_P(c, T_ICLASS))
	return RBASIC(c)->klass;
    return c;
}

static int
cvar_lookup_at(VALUE klass, ID id, st_data_t *v)
{
    if (!RCLASS_IV_TBL(klass)) return 0;
    return st_lookup(RCLASS_IV_TBL(klass), (st_data_t)id, v);
}

static VALUE
cvar_front_klass(VALUE klass)
{
    if (FL_TEST(klass, FL_SINGLETON)) {
	VALUE obj = rb_ivar_get(klass, id__attached__);
        if (rb_namespace_p(obj)) {
	    return obj;
	}
    }
    return RCLASS_SUPER(klass);
}

static void
cvar_overtaken(VALUE front, VALUE target, ID id)
{
    if (front && target != front) {
	st_data_t did = (st_data_t)id;

        if (original_module(front) != original_module(target)) {
            rb_raise(rb_eRuntimeError,
                     "class variable % "PRIsVALUE" of %"PRIsVALUE" is overtaken by %"PRIsVALUE"",
		       ID2SYM(id), rb_class_name(original_module(front)),
		       rb_class_name(original_module(target)));
	}
	if (BUILTIN_TYPE(front) == T_CLASS) {
	    st_delete(RCLASS_IV_TBL(front), &did, 0);
	}
    }
}

#define CVAR_FOREACH_ANCESTORS(klass, v, r) \
    for (klass = cvar_front_klass(klass); klass; klass = RCLASS_SUPER(klass)) { \
	if (cvar_lookup_at(klass, id, (v))) { \
	    r; \
	} \
    }

#define CVAR_LOOKUP(v,r) do {\
    if (cvar_lookup_at(klass, id, (v))) {r;}\
    CVAR_FOREACH_ANCESTORS(klass, v, r);\
} while(0)

void
rb_cvar_set(VALUE klass, ID id, VALUE val)
{
    VALUE tmp, front = 0, target = 0;

    tmp = klass;
    CVAR_LOOKUP(0, {if (!front) front = klass; target = klass;});
    if (target) {
	cvar_overtaken(front, target, id);
    }
    else {
	target = tmp;
    }

    if (RB_TYPE_P(target, T_ICLASS)) {
        target = RBASIC(target)->klass;
    }
    check_before_mod_set(target, id, val, "class variable");
    if (!RCLASS_IV_TBL(target)) {
	RCLASS_IV_TBL(target) = st_init_numtable();
    }

    rb_class_ivar_set(target, id, val);
}

VALUE
rb_cvar_get(VALUE klass, ID id)
{
    VALUE tmp, front = 0, target = 0;
    st_data_t value;

    tmp = klass;
    CVAR_LOOKUP(&value, {if (!front) front = klass; target = klass;});
    if (!target) {
	rb_name_err_raise("uninitialized class variable %1$s in %2$s",
			  tmp, ID2SYM(id));
    }
    cvar_overtaken(front, target, id);
    return (VALUE)value;
}

VALUE
rb_cvar_defined(VALUE klass, ID id)
{
    if (!klass) return Qfalse;
    CVAR_LOOKUP(0,return Qtrue);
    return Qfalse;
}

static ID
cv_intern(VALUE klass, const char *name)
{
    ID id = rb_intern(name);
    if (!rb_is_class_id(id)) {
	rb_name_err_raise("wrong class variable name %1$s",
			  klass, rb_str_new_cstr(name));
    }
    return id;
}

void
rb_cv_set(VALUE klass, const char *name, VALUE val)
{
    ID id = cv_intern(klass, name);
    rb_cvar_set(klass, id, val);
}

VALUE
rb_cv_get(VALUE klass, const char *name)
{
    ID id = cv_intern(klass, name);
    return rb_cvar_get(klass, id);
}

void
rb_define_class_variable(VALUE klass, const char *name, VALUE val)
{
    ID id = cv_intern(klass, name);
    rb_cvar_set(klass, id, val);
}

static int
cv_i(st_data_t k, st_data_t v, st_data_t a)
{
    ID key = (ID)k;
    st_table *tbl = (st_table *)a;

    if (rb_is_class_id(key)) {
	st_update(tbl, (st_data_t)key, cv_i_update, 0);
    }
    return ST_CONTINUE;
}

static void*
mod_cvar_at(VALUE mod, void *data)
{
    st_table *tbl = data;
    if (!tbl) {
	tbl = st_init_numtable();
    }
    if (RCLASS_IV_TBL(mod)) {
	st_foreach_safe(RCLASS_IV_TBL(mod), cv_i, (st_data_t)tbl);
    }
    return tbl;
}

static void*
mod_cvar_of(VALUE mod, void *data)
{
    VALUE tmp = mod;
    if (FL_TEST(mod, FL_SINGLETON)) {
        if (rb_namespace_p(rb_ivar_get(mod, id__attached__))) {
            data = mod_cvar_at(tmp, data);
            tmp = cvar_front_klass(tmp);
        }
    }
    for (;;) {
	data = mod_cvar_at(tmp, data);
	tmp = RCLASS_SUPER(tmp);
	if (!tmp) break;
    }
    return data;
}

static int
cv_list_i(st_data_t key, st_data_t value, VALUE ary)
{
    ID sym = (ID)key;
    rb_ary_push(ary, ID2SYM(sym));
    return ST_CONTINUE;
}

static VALUE
cvar_list(void *data)
{
    st_table *tbl = data;
    VALUE ary;

    if (!tbl) return rb_ary_new2(0);
    ary = rb_ary_new2(tbl->num_entries);
    st_foreach_safe(tbl, cv_list_i, ary);
    st_free_table(tbl);

    return ary;
}

/*
 *  call-seq:
 *     mod.class_variables(inherit=true)    -> array
 *
 *  Returns an array of the names of class variables in <i>mod</i>.
 *  This includes the names of class variables in any included
 *  modules, unless the <i>inherit</i> parameter is set to
 *  <code>false</code>.
 *
 *     class One
 *       @@var1 = 1
 *     end
 *     class Two < One
 *       @@var2 = 2
 *     end
 *     One.class_variables          #=> [:@@var1]
 *     Two.class_variables          #=> [:@@var2, :@@var1]
 *     Two.class_variables(false)   #=> [:@@var2]
 */

VALUE
rb_mod_class_variables(int argc, const VALUE *argv, VALUE mod)
{
    bool inherit = true;
    st_table *tbl;

    if (rb_check_arity(argc, 0, 1)) inherit = RTEST(argv[0]);
    if (inherit) {
	tbl = mod_cvar_of(mod, 0);
    }
    else {
	tbl = mod_cvar_at(mod, 0);
    }
    return cvar_list(tbl);
}

/*
 *  call-seq:
 *     remove_class_variable(sym)    -> obj
 *
 *  Removes the named class variable from the receiver, returning that
 *  variable's value.
 *
 *     class Example
 *       @@var = 99
 *       puts remove_class_variable(:@@var)
 *       p(defined? @@var)
 *     end
 *
 *  <em>produces:</em>
 *
 *     99
 *     nil
 */

VALUE
rb_mod_remove_cvar(VALUE mod, VALUE name)
{
    const ID id = id_for_var_message(mod, name, class, "wrong class variable name %1$s");
    st_data_t val, n = id;

    if (!id) {
        goto not_defined;
    }
    rb_check_frozen(mod);
    if (RCLASS_IV_TBL(mod) && st_delete(RCLASS_IV_TBL(mod), &n, &val)) {
	return (VALUE)val;
    }
    if (rb_cvar_defined(mod, id)) {
	rb_name_err_raise("cannot remove %1$s for %2$s", mod, ID2SYM(id));
    }
  not_defined:
    rb_name_err_raise("class variable %1$s not defined for %2$s",
                      mod, name);
    UNREACHABLE_RETURN(Qundef);
}

VALUE
rb_iv_get(VALUE obj, const char *name)
{
    ID id = rb_check_id_cstr(name, strlen(name), rb_usascii_encoding());

    if (!id) {
        if (RTEST(ruby_verbose))
            rb_warning("instance variable %s not initialized", name);
        return Qnil;
    }
    return rb_ivar_get(obj, id);
}

VALUE
rb_iv_set(VALUE obj, const char *name, VALUE val)
{
    ID id = rb_intern(name);

    return rb_ivar_set(obj, id, val);
}

/* tbl = xx(obj); tbl[key] = value; */
int
rb_class_ivar_set(VALUE obj, ID key, VALUE value)
{
    st_table *tbl = RCLASS_IV_TBL(obj);
    int result = st_insert(tbl, (st_data_t)key, (st_data_t)value);
    RB_OBJ_WRITTEN(obj, Qundef, value);
    return result;
}

static int
tbl_copy_i(st_data_t key, st_data_t value, st_data_t data)
{
    RB_OBJ_WRITTEN((VALUE)data, Qundef, (VALUE)value);
    return ST_CONTINUE;
}

void
rb_iv_tbl_copy(VALUE dst, VALUE src)
{
    st_table *orig_tbl = RCLASS_IV_TBL(src);
    st_table *new_tbl = st_copy(orig_tbl);
    st_foreach(new_tbl, tbl_copy_i, (st_data_t)dst);
    RCLASS_IV_TBL(dst) = new_tbl;
}

MJIT_FUNC_EXPORTED rb_const_entry_t *
rb_const_lookup(VALUE klass, ID id)
{
    struct rb_id_table *tbl = RCLASS_CONST_TBL(klass);
    VALUE val;

    if (tbl && rb_id_table_lookup(tbl, id, &val)) {
	return (rb_const_entry_t *)val;
    }
    return 0;
}
