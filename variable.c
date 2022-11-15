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
#include "shape.h"
#include "variable.h"
#include "vm_core.h"
#include "ractor_core.h"
#include "vm_sync.h"

RUBY_EXTERN rb_serial_t ruby_vm_global_cvar_state;
#define GET_GLOBAL_CVAR_STATE() (ruby_vm_global_cvar_state)

typedef void rb_gvar_compact_t(void *var);

static struct rb_id_table *rb_global_tbl;
static ID autoload, classpath, tmp_classpath;

// This hash table maps file paths to loadable features. We use this to track
// autoload state until it's no longer needed.
// feature (file path) => struct autoload_data
static VALUE autoload_features;

// This mutex is used to protect autoloading state. We use a global mutex which
// is held until a per-feature mutex can be created. This ensures there are no
// race conditions relating to autoload state.
static VALUE autoload_mutex;

static void check_before_mod_set(VALUE, ID, VALUE, const char *);
static void setup_const_entry(rb_const_entry_t *, VALUE, VALUE, rb_const_flag_t);
static VALUE rb_const_search(VALUE klass, ID id, int exclude, int recurse, int visibility);
static st_table *generic_iv_tbl_;

struct ivar_update {
    struct gen_ivtbl *ivtbl;
    uint32_t iv_index;
    rb_shape_t* shape;
};

void
Init_var_tables(void)
{
    rb_global_tbl = rb_id_table_create(0);
    generic_iv_tbl_ = st_init_numtable();
    autoload = rb_intern_const("__autoload__");
    /* __classpath__: fully qualified class path */
    classpath = rb_intern_const("__classpath__");
    /* __tmp_classpath__: temporary class path which contains anonymous names */
    tmp_classpath = rb_intern_const("__tmp_classpath__");

    autoload_mutex = rb_mutex_new();
    rb_obj_hide(autoload_mutex);
    rb_gc_register_mark_object(autoload_mutex);

    autoload_features = rb_ident_hash_new();
    rb_obj_hide(autoload_features);
    rb_gc_register_mark_object(autoload_features);
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
    *permanent = 0;
    if (!RCLASS_EXT(klass)) return Qnil;

    VALUE classpathv = rb_ivar_lookup(klass, classpath, Qnil);
    if (RTEST(classpathv)) {
        *permanent = 1;
        return classpathv;
    }

    return rb_ivar_lookup(klass, tmp_classpath, Qnil);;
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
    return rb_mod_name(klass);
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
    return rb_fstring(path);
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
        if (UNDEF_P(c)) goto undefined_class;
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
    bool ractor_local;
};

static struct rb_global_entry*
rb_find_global_entry(ID id)
{
    struct rb_global_entry *entry;
    VALUE data;

    if (!rb_id_table_lookup(rb_global_tbl, id, &data)) {
        entry = NULL;
    }
    else {
        entry = (struct rb_global_entry *)data;
        RUBY_ASSERT(entry != NULL);
    }

    if (UNLIKELY(!rb_ractor_main_p()) && (!entry || !entry->ractor_local)) {
        rb_raise(rb_eRactorIsolationError, "can not access global variables %s from non-main Ractors", rb_id2name(id));
    }

    return entry;
}

void
rb_gvar_ractor_local(const char *name)
{
    struct rb_global_entry *entry = rb_find_global_entry(rb_intern(name));
    entry->ractor_local = true;
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
        entry->ractor_local = false;
        var->counter = 1;
        var->data = 0;
        var->getter = rb_gvar_undef_getter;
        var->setter = rb_gvar_undef_setter;
        var->marker = rb_gvar_undef_marker;
        var->compactor = rb_gvar_undef_compactor;

        var->block_trace = 0;
        var->trace = 0;
        rb_id_table_insert(rb_global_tbl, id, (VALUE)entry);
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
    if (rb_global_tbl) {
        rb_id_table_foreach_values(rb_global_tbl, update_global_entry, 0);
    }
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

    rb_scan_args(argc, argv, "11", &var, &cmd);
    id = rb_check_id(&var);
    if (!id) {
        rb_name_error_str(var, "undefined global variable %"PRIsVALUE"", QUOTE(var));
    }
    if ((entry = rb_find_global_entry(id)) == NULL) {
        rb_name_error(id, "undefined global variable %"PRIsVALUE"", QUOTE_ID(id));
    }

    trace = entry->var->trace;
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
    return RBOOL(entry->var->getter != rb_gvar_undef_getter);
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

    if (!rb_ractor_main_p()) {
        rb_raise(rb_eRactorIsolationError, "can not access global variables from non-main Ractors");
    }

    rb_id_table_foreach(rb_global_tbl, gvar_i, (void *)ary);
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
    struct rb_id_table *gtbl = rb_global_tbl;

    if (!rb_ractor_main_p()) {
        rb_raise(rb_eRactorIsolationError, "can not access global variables from non-main Ractors");
    }

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

static void
IVAR_ACCESSOR_SHOULD_BE_MAIN_RACTOR(ID id)
{
    if (UNLIKELY(!rb_ractor_main_p())) {
        if (rb_is_instance_id(id)) { // check only normal ivars
            rb_raise(rb_eRactorIsolationError, "can not set instance variables of classes/modules by non-main Ractors");
        }
    }
}

#define CVAR_ACCESSOR_SHOULD_BE_MAIN_RACTOR() \
  if (UNLIKELY(!rb_ractor_main_p())) { \
      rb_raise(rb_eRactorIsolationError, "can not access class variables from non-main Ractors"); \
  }

static inline struct st_table *
generic_ivtbl(VALUE obj, ID id, bool force_check_ractor)
{
    ASSERT_vm_locking();

    if ((force_check_ractor || LIKELY(rb_is_instance_id(id)) /* not internal ID */ )  &&
        !RB_OBJ_FROZEN_RAW(obj) &&
        UNLIKELY(!rb_ractor_main_p()) &&
        UNLIKELY(rb_ractor_shareable_p(obj))) {

        rb_raise(rb_eRactorIsolationError, "can not access instance variables of shareable objects from non-main Ractors");
    }
    return generic_iv_tbl_;
}

static inline struct st_table *
generic_ivtbl_no_ractor_check(VALUE obj)
{
    return generic_ivtbl(obj, 0, false);
}

static int
gen_ivtbl_get_unlocked(VALUE obj, ID id, struct gen_ivtbl **ivtbl)
{
    st_data_t data;

    if (st_lookup(generic_ivtbl(obj, id, false), (st_data_t)obj, &data)) {
        *ivtbl = (struct gen_ivtbl *)data;
        return 1;
    }

    return 0;
}

MJIT_FUNC_EXPORTED int
rb_gen_ivtbl_get(VALUE obj, ID id, struct gen_ivtbl **ivtbl)
{
    RUBY_ASSERT(!RB_TYPE_P(obj, T_ICLASS));

    st_data_t data;
    int r = 0;

    RB_VM_LOCK_ENTER();
    {
        if (st_lookup(generic_ivtbl(obj, id, false), (st_data_t)obj, &data)) {
            *ivtbl = (struct gen_ivtbl *)data;
            r = 1;
        }
    }
    RB_VM_LOCK_LEAVE();

    return r;
}

MJIT_FUNC_EXPORTED int
rb_ivar_generic_ivtbl_lookup(VALUE obj, struct gen_ivtbl **ivtbl)
{
    return rb_gen_ivtbl_get(obj, 0, ivtbl);
}

static size_t
gen_ivtbl_bytes(size_t n)
{
    return offsetof(struct gen_ivtbl, ivptr) + n * sizeof(VALUE);
}

static struct gen_ivtbl *
gen_ivtbl_resize(struct gen_ivtbl *old, uint32_t n)
{
    RUBY_ASSERT(n > 0);

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

static int
generic_ivar_update(st_data_t *k, st_data_t *v, st_data_t u, int existing)
{
    ASSERT_vm_locking();

    struct ivar_update *ivup = (struct ivar_update *)u;
    struct gen_ivtbl *ivtbl = 0;

    if (existing) {
        ivtbl = (struct gen_ivtbl *)*v;
        if (ivup->iv_index < ivtbl->numiv) {
            ivup->ivtbl = ivtbl;
            return ST_STOP;
        }
    }
    FL_SET((VALUE)*k, FL_EXIVAR);
    ivtbl = gen_ivtbl_resize(ivtbl, ivup->shape->next_iv_index);
    // Reinsert in to the hash table because ivtbl might be a newly resized chunk of memory
    *v = (st_data_t)ivtbl;
    ivup->ivtbl = ivtbl;
#if !SHAPE_IN_BASIC_FLAGS
    ivtbl->shape_id = rb_shape_id(ivup->shape);
#endif
    return ST_CONTINUE;
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

    if (rb_gen_ivtbl_get(obj, 0, &ivtbl)) {
        gen_ivtbl_mark(ivtbl);
    }
}

void
rb_mv_generic_ivar(VALUE rsrc, VALUE dst)
{
    st_data_t key = (st_data_t)rsrc;
    st_data_t ivtbl;

    if (st_delete(generic_ivtbl_no_ractor_check(rsrc), &key, &ivtbl))
        st_insert(generic_ivtbl_no_ractor_check(dst), (st_data_t)dst, ivtbl);
}

void
rb_free_generic_ivar(VALUE obj)
{
    st_data_t key = (st_data_t)obj, ivtbl;

    if (st_delete(generic_ivtbl_no_ractor_check(obj), &key, &ivtbl))
        xfree((struct gen_ivtbl *)ivtbl);
}

RUBY_FUNC_EXPORTED size_t
rb_generic_ivar_memsize(VALUE obj)
{
    struct gen_ivtbl *ivtbl;

    if (rb_gen_ivtbl_get(obj, 0, &ivtbl))
        return gen_ivtbl_bytes(ivtbl->numiv);
    return 0;
}

#if !SHAPE_IN_BASIC_FLAGS
MJIT_FUNC_EXPORTED shape_id_t
rb_generic_shape_id(VALUE obj)
{
    struct gen_ivtbl *ivtbl = 0;
    shape_id_t shape_id = 0;

    RB_VM_LOCK_ENTER();
    {
        st_table* global_iv_table = generic_ivtbl(obj, 0, false);

        if (global_iv_table && st_lookup(global_iv_table, obj, (st_data_t *)&ivtbl)) {
            shape_id = ivtbl->shape_id;
        }
        else if (OBJ_FROZEN(obj)) {
            shape_id = SPECIAL_CONST_SHAPE_ID;
        }
    }
    RB_VM_LOCK_LEAVE();

    return shape_id;
}
#endif

static size_t
gen_ivtbl_count(const struct gen_ivtbl *ivtbl)
{
    uint32_t i;
    size_t n = 0;

    for (i = 0; i < ivtbl->numiv; i++) {
        if (!UNDEF_P(ivtbl->ivptr[i])) {
            n++;
        }
    }

    return n;
}

VALUE
rb_ivar_lookup(VALUE obj, ID id, VALUE undef)
{
    if (SPECIAL_CONST_P(obj)) return undef;

    shape_id_t shape_id;
    VALUE * ivar_list;
    rb_shape_t * shape;

#if SHAPE_IN_BASIC_FLAGS
    shape_id = RBASIC_SHAPE_ID(obj);
#endif

    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
      case T_MODULE:
        {
            bool found;
            VALUE val;

            RB_VM_LOCK_ENTER();
            {
#if !SHAPE_IN_BASIC_FLAGS
                shape_id = RCLASS_SHAPE_ID(obj);
#endif

                attr_index_t index = 0;
                shape = rb_shape_get_shape_by_id(shape_id);
                found = rb_shape_get_iv_index(shape, id, &index);

                if (found) {
                    ivar_list = RCLASS_IVPTR(obj);
                    RUBY_ASSERT(ivar_list);

                    val = ivar_list[index];
                }
                else {
                    val = undef;
                }
            }
            RB_VM_LOCK_LEAVE();

            if (found &&
                    rb_is_instance_id(id) &&
                    UNLIKELY(!rb_ractor_main_p()) &&
                    !rb_ractor_shareable_p(val)) {
                rb_raise(rb_eRactorIsolationError,
                        "can not get unshareable values from instance variables of classes/modules from non-main Ractors");
            }
            return val;
        }
      case T_OBJECT:
        {
#if !SHAPE_IN_BASIC_FLAGS
            shape_id = ROBJECT_SHAPE_ID(obj);
#endif
            ivar_list = ROBJECT_IVPTR(obj);
            break;
        }
      default:
        if (FL_TEST_RAW(obj, FL_EXIVAR)) {
            struct gen_ivtbl *ivtbl;
            rb_gen_ivtbl_get(obj, id, &ivtbl);
#if !SHAPE_IN_BASIC_FLAGS
            shape_id = ivtbl->shape_id;
#endif
            ivar_list = ivtbl->ivptr;
        }
        else {
            return undef;
        }
        break;
    }

    attr_index_t index = 0;
    shape = rb_shape_get_shape_by_id(shape_id);
    if (rb_shape_get_iv_index(shape, id, &index)) {
        return ivar_list[index];
    }

    return undef;
}

VALUE
rb_ivar_get(VALUE obj, ID id)
{
    VALUE iv = rb_ivar_lookup(obj, id, Qnil);
    RB_DEBUG_COUNTER_INC(ivar_get_base);
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
    rb_check_frozen(obj);

    VALUE val = undef;
    attr_index_t index;

    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
      case T_MODULE:
        IVAR_ACCESSOR_SHOULD_BE_MAIN_RACTOR(id);

        RB_VM_LOCK_ENTER();
        {
            rb_shape_t * shape = rb_shape_get_shape(obj);
            if (rb_shape_get_iv_index(shape, id, &index)) {
                rb_shape_transition_shape_remove_ivar(obj, id, shape);
                val = RCLASS_IVPTR(obj)[index];
                RCLASS_IVPTR(obj)[index] = Qundef;
            }
        }
        RB_VM_LOCK_LEAVE();

        break;
      case T_OBJECT: {
        rb_shape_t * shape = rb_shape_get_shape(obj);
        if (rb_shape_get_iv_index(shape, id, &index)) {
            rb_shape_transition_shape_remove_ivar(obj, id, shape);
            val = ROBJECT_IVPTR(obj)[index];
            ROBJECT_IVPTR(obj)[index] = Qundef;
        }

        break;
      }
      default: {
        rb_shape_t * shape = rb_shape_get_shape(obj);

        if (rb_shape_get_iv_index(shape, id, &index)) {
            rb_shape_transition_shape_remove_ivar(obj, id, shape);
            struct gen_ivtbl *ivtbl;
            rb_gen_ivtbl_get(obj, id, &ivtbl);
            val = ivtbl->ivptr[index];
            ivtbl->ivptr[index] = Qundef;
        }

        break;
      }
    }

    return val;
}

VALUE
rb_attr_delete(VALUE obj, ID id)
{
    return rb_ivar_delete(obj, id, Qnil);
}

static void
generic_ivar_set(VALUE obj, ID id, VALUE val)
{
    struct ivar_update ivup;
    // The returned shape will have `id` in its iv_table
    rb_shape_t * shape = rb_shape_get_next(rb_shape_get_shape(obj), obj, id);
    ivup.shape = shape;

    RB_VM_LOCK_ENTER();
    {
        attr_index_t ent_data;
        if (rb_shape_get_iv_index(shape, id, &ent_data)) {
            ivup.iv_index = (uint32_t) ent_data;
        }
        else {
            rb_bug("unreachable.  Shape was not found for id: %s", rb_id2name(id));
        }

        st_update(generic_ivtbl(obj, id, false), (st_data_t)obj, generic_ivar_update, (st_data_t)&ivup);
    }
    RB_VM_LOCK_LEAVE();

    ivup.ivtbl->ivptr[ivup.iv_index] = val;

    rb_shape_set_shape(obj, shape);
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
        assert(!RB_FL_TEST_RAW(obj, ROBJECT_EMBED));

        uint32_t len = ROBJECT_IV_CAPACITY(obj);
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

void
rb_ensure_iv_list_size(VALUE obj, uint32_t current_capacity, uint32_t new_capacity)
{
    VALUE *ptr = ROBJECT_IVPTR(obj);
    VALUE *newptr;

    if (RBASIC(obj)->flags & ROBJECT_EMBED) {
        newptr = obj_ivar_heap_alloc(obj, new_capacity);
        MEMCPY(newptr, ptr, VALUE, current_capacity);
        RB_FL_UNSET_RAW(obj, ROBJECT_EMBED);
        ROBJECT(obj)->as.heap.ivptr = newptr;
    }
    else {
        newptr = obj_ivar_heap_realloc(obj, current_capacity, new_capacity);
    }
}

struct gen_ivtbl *
rb_ensure_generic_iv_list_size(VALUE obj, uint32_t newsize)
{
    struct gen_ivtbl * ivtbl = 0;

    RB_VM_LOCK_ENTER();
    {
        if (UNLIKELY(!gen_ivtbl_get_unlocked(obj, 0, &ivtbl) || newsize > ivtbl->numiv)) {
            ivtbl = gen_ivtbl_resize(ivtbl, newsize);
            st_insert(generic_ivtbl_no_ractor_check(obj), (st_data_t)obj, (st_data_t)ivtbl);
            FL_SET_RAW(obj, FL_EXIVAR);
        }
    }
    RB_VM_LOCK_LEAVE();

    RUBY_ASSERT(ivtbl);

    return ivtbl;
}

// @note May raise when there are too many instance variables.
rb_shape_t *
rb_grow_iv_list(VALUE obj)
{
    rb_shape_t * initial_shape = rb_shape_get_shape(obj);
    uint32_t len = initial_shape->capacity;
    RUBY_ASSERT(len > 0);
    uint32_t newsize = (uint32_t)(len * 2);
    rb_ensure_iv_list_size(obj, len, newsize);

    rb_shape_t * res = rb_shape_transition_shape_capa(initial_shape, newsize);
    rb_shape_set_shape(obj, res);
    return res;
}

static VALUE
obj_ivar_set(VALUE obj, ID id, VALUE val)
{
    attr_index_t index;

    // Get the current shape
    rb_shape_t * shape = rb_shape_get_shape_by_id(ROBJECT_SHAPE_ID(obj));

    bool found = true;
    if (!rb_shape_get_iv_index(shape, id, &index)) {
        index = shape->next_iv_index;
        found = false;
    }

    // Reallocating can kick off GC.  We can't set the new shape
    // on this object until the buffer has been allocated, otherwise
    // GC could read off the end of the buffer.
    if (shape->capacity <= index) {
        shape = rb_grow_iv_list(obj);
    }

    if (!found) {
        shape = rb_shape_get_next(shape, obj, id);
        RUBY_ASSERT(index == (shape->next_iv_index - 1));
        rb_shape_set_shape(obj, shape);
    }

    RB_OBJ_WRITE(obj, &ROBJECT_IVPTR(obj)[index], val);

    return val;
}

/* Set the instance variable +val+ on object +obj+ at ivar name +id+.
 * This function only works with T_OBJECT objects, so make sure
 * +obj+ is of type T_OBJECT before using this function.
 */
VALUE
rb_vm_set_ivar_id(VALUE obj, ID id, VALUE val)
{
    rb_check_frozen_internal(obj);
    obj_ivar_set(obj, id, val);
    return val;
}

bool
rb_shape_set_shape_id(VALUE obj, shape_id_t shape_id)
{
    if (rb_shape_get_shape_id(obj) == shape_id) {
        return false;
    }

#if SHAPE_IN_BASIC_FLAGS
    RBASIC_SET_SHAPE_ID(obj, shape_id);
#else
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        ROBJECT_SET_SHAPE_ID(obj, shape_id);
        break;
      case T_CLASS:
      case T_MODULE:
        RCLASS_EXT(obj)->shape_id = shape_id;
        break;
      default:
        if (shape_id != SPECIAL_CONST_SHAPE_ID) {
            struct gen_ivtbl *ivtbl = 0;
            RB_VM_LOCK_ENTER();
            {
                st_table* global_iv_table = generic_ivtbl(obj, 0, false);

                if (st_lookup(global_iv_table, obj, (st_data_t *)&ivtbl)) {
                    ivtbl->shape_id = shape_id;
                }
                else {
                    rb_bug("Expected shape_id entry in global iv table");
                }
            }
            RB_VM_LOCK_LEAVE();
        }
    }
#endif

    return true;
}

/**
 * Prevents further modifications to the given object.  ::rb_eFrozenError shall
 * be raised if modification is attempted.
 *
 * @param[out]  x  Object in question.
 */
void rb_obj_freeze_inline(VALUE x)
{
    if (RB_FL_ABLE(x)) {
        RB_OBJ_FREEZE_RAW(x);

        rb_shape_transition_shape_frozen(x);

        if (RBASIC_CLASS(x) && !(RBASIC(x)->flags & RUBY_FL_SINGLETON)) {
            rb_freeze_singleton_class(x);
        }
    }
}

static void
ivar_set(VALUE obj, ID id, VALUE val)
{
    RB_DEBUG_COUNTER_INC(ivar_set_base);

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
      {
          obj_ivar_set(obj, id, val);
          break;
      }
      case T_CLASS:
      case T_MODULE:
        IVAR_ACCESSOR_SHOULD_BE_MAIN_RACTOR(id);
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
    attr_index_t index;

    if (SPECIAL_CONST_P(obj)) return Qfalse;
    return RBOOL(rb_shape_get_iv_index(rb_shape_get_shape(obj), id, &index));
}

typedef int rb_ivar_foreach_callback_func(ID key, VALUE val, st_data_t arg);
st_data_t rb_st_nth_key(st_table *tab, st_index_t index);

struct iv_itr_data {
    VALUE obj;
    struct gen_ivtbl * ivtbl;
    st_data_t arg;
};

static void
iterate_over_shapes_with_callback(rb_shape_t *shape, rb_ivar_foreach_callback_func *callback, struct iv_itr_data * itr_data)
{
    switch ((enum shape_type)shape->type) {
      case SHAPE_ROOT:
        return;
      case SHAPE_IVAR:
        iterate_over_shapes_with_callback(rb_shape_get_parent(shape), callback, itr_data);
        VALUE * iv_list;
        switch (BUILTIN_TYPE(itr_data->obj)) {
          case T_OBJECT:
            iv_list = ROBJECT_IVPTR(itr_data->obj);
            break;
          case T_CLASS:
          case T_MODULE:
            iv_list = RCLASS_IVPTR(itr_data->obj);
            break;
          default:
            iv_list = itr_data->ivtbl->ivptr;
            break;
        }
        VALUE val = iv_list[shape->next_iv_index - 1];
        if (!UNDEF_P(val)) {
            callback(shape->edge_name, val, itr_data->arg);
        }
        return;
      case SHAPE_INITIAL_CAPACITY:
      case SHAPE_CAPACITY_CHANGE:
      case SHAPE_FROZEN:
      case SHAPE_IVAR_UNDEF:
        iterate_over_shapes_with_callback(rb_shape_get_parent(shape), callback, itr_data);
        return;
    }
}

static void
obj_ivar_each(VALUE obj, rb_ivar_foreach_callback_func *func, st_data_t arg)
{
    rb_shape_t* shape = rb_shape_get_shape(obj);
    struct iv_itr_data itr_data;
    itr_data.obj = obj;
    itr_data.arg = arg;
    iterate_over_shapes_with_callback(shape, func, &itr_data);
}

static void
gen_ivar_each(VALUE obj, rb_ivar_foreach_callback_func *func, st_data_t arg)
{
    rb_shape_t *shape = rb_shape_get_shape(obj);
    struct gen_ivtbl *ivtbl;
    if (!rb_gen_ivtbl_get(obj, 0, &ivtbl)) return;

    struct iv_itr_data itr_data;
    itr_data.obj = obj;
    itr_data.ivtbl = ivtbl;
    itr_data.arg = arg;
    iterate_over_shapes_with_callback(shape, func, &itr_data);
}

static void
class_ivar_each(VALUE obj, rb_ivar_foreach_callback_func *func, st_data_t arg)
{
    RUBY_ASSERT(RB_TYPE_P(obj, T_CLASS) || RB_TYPE_P(obj, T_MODULE));

    rb_shape_t* shape = rb_shape_get_shape(obj);
    struct iv_itr_data itr_data;
    itr_data.obj = obj;
    itr_data.arg = arg;
    iterate_over_shapes_with_callback(shape, func, &itr_data);
}

void
rb_copy_generic_ivar(VALUE clone, VALUE obj)
{
    struct gen_ivtbl *obj_ivtbl;
    struct gen_ivtbl *new_ivtbl;

    rb_check_frozen(clone);

    if (!FL_TEST(obj, FL_EXIVAR)) {
        goto clear;
    }

    if (rb_gen_ivtbl_get(obj, 0, &obj_ivtbl)) {
        if (gen_ivtbl_count(obj_ivtbl) == 0)
            goto clear;

        new_ivtbl = gen_ivtbl_resize(0, obj_ivtbl->numiv);
        FL_SET(clone, FL_EXIVAR);

        for (uint32_t i=0; i<obj_ivtbl->numiv; i++) {
            new_ivtbl->ivptr[i] = obj_ivtbl->ivptr[i];
            RB_OBJ_WRITTEN(clone, Qundef, &new_ivtbl[i]);
        }

        /*
         * c.ivtbl may change in gen_ivar_copy due to realloc,
         * no need to free
         */
        RB_VM_LOCK_ENTER();
        {
            generic_ivtbl_no_ractor_check(clone);
            st_insert(generic_ivtbl_no_ractor_check(obj), (st_data_t)clone, (st_data_t)new_ivtbl);
        }
        RB_VM_LOCK_LEAVE();

        rb_shape_t * obj_shape = rb_shape_get_shape(obj);
        if (rb_shape_frozen_shape_p(obj_shape)) {
            rb_shape_set_shape_id(clone, obj_shape->parent_id);
        }
        else {
            rb_shape_set_shape(clone, obj_shape);
        }
    }
    return;

  clear:
    if (FL_TEST(clone, FL_EXIVAR)) {
        rb_free_generic_ivar(clone);
        FL_UNSET(clone, FL_EXIVAR);
    }
}

void
rb_replace_generic_ivar(VALUE clone, VALUE obj)
{
    RUBY_ASSERT(FL_TEST(obj, FL_EXIVAR));

    RB_VM_LOCK_ENTER();
    {
        st_data_t ivtbl, obj_data = (st_data_t)obj;
        if (st_lookup(generic_iv_tbl_, (st_data_t)obj, &ivtbl)) {
            st_insert(generic_iv_tbl_, (st_data_t)clone, ivtbl);
            st_delete(generic_iv_tbl_, &obj_data, NULL);
        }
        else {
            rb_bug("unreachable");
        }
    }
    RB_VM_LOCK_LEAVE();

    FL_SET(clone, FL_EXIVAR);
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
        IVAR_ACCESSOR_SHOULD_BE_MAIN_RACTOR(0);
        RB_VM_LOCK_ENTER();
        {
            class_ivar_each(obj, func, arg);
        }
        RB_VM_LOCK_LEAVE();
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
    if (SPECIAL_CONST_P(obj)) return 0;

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        if (rb_shape_get_shape(obj)->next_iv_index > 0) {
            st_index_t i, count, num = ROBJECT_IV_COUNT(obj);
            const VALUE *const ivptr = ROBJECT_IVPTR(obj);
            for (i = count = 0; i < num; ++i) {
                if (!UNDEF_P(ivptr[i])) {
                    count++;
                }
            }
            return count;
        }
        break;
      case T_CLASS:
      case T_MODULE:
        if (rb_shape_get_shape(obj)->next_iv_index > 0) {
            st_index_t count = 0;

            RB_VM_LOCK_ENTER();
            {
                st_index_t i, num = rb_shape_get_shape(obj)->next_iv_index;
                const VALUE *const ivptr = RCLASS_IVPTR(obj);
                for (i = count = 0; i < num; ++i) {
                    if (!UNDEF_P(ivptr[i])) {
                        count++;
                    }
                }
            }
            RB_VM_LOCK_LEAVE();

            return count;
        }
        break;
      default:
        if (FL_TEST(obj, FL_EXIVAR)) {
            struct gen_ivtbl *ivtbl;

            if (rb_gen_ivtbl_get(obj, 0, &ivtbl)) {
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

    // Frozen check comes here because it's expected that we raise a
    // NameError (from the id_for_var check) before we raise a FrozenError
    rb_check_frozen(obj);

    attr_index_t index;

    if (!id) {
        goto not_defined;
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
      case T_MODULE:
        IVAR_ACCESSOR_SHOULD_BE_MAIN_RACTOR(id);
        rb_shape_t * shape = rb_shape_get_shape(obj);
        if (rb_shape_get_iv_index(shape, id, &index)) {
            rb_shape_transition_shape_remove_ivar(obj, id, shape);
            val = RCLASS_IVPTR(obj)[index];
            RCLASS_IVPTR(obj)[index] = Qundef;
            return val;
        }
        break;
      case T_OBJECT: {
        rb_shape_t * shape = rb_shape_get_shape(obj);
        if (rb_shape_get_iv_index(shape, id, &index)) {
            rb_shape_transition_shape_remove_ivar(obj, id, shape);
            val = ROBJECT_IVPTR(obj)[index];
            ROBJECT_IVPTR(obj)[index] = Qundef;
            return val;
        }

        break;
      }
      default: {
        rb_shape_t * shape = rb_shape_get_shape(obj);

        if (rb_shape_get_iv_index(shape, id, &index)) {
            rb_shape_transition_shape_remove_ivar(obj, id, shape);
            struct gen_ivtbl *ivtbl;
            rb_gen_ivtbl_get(obj, id, &ivtbl);
            val = ivtbl->ivptr[index];
            ivtbl->ivptr[index] = Qundef;
            return val;
        }

        break;
      }
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
autoload_table_mark(void *ptr)
{
    rb_mark_tbl_no_pin((st_table *)ptr);
}

static void
autoload_table_free(void *ptr)
{
    st_free_table((st_table *)ptr);
}

static size_t
autoload_table_memsize(const void *ptr)
{
    const st_table *tbl = ptr;
    return st_memsize(tbl);
}

static void
autoload_table_compact(void *ptr)
{
    rb_gc_update_tbl_refs((st_table *)ptr);
}

static const rb_data_type_t autoload_table_type = {
    "autoload_table",
    {autoload_table_mark, autoload_table_free, autoload_table_memsize, autoload_table_compact,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#define check_autoload_table(av) \
    (struct st_table *)rb_check_typeddata((av), &autoload_table_type)

static VALUE
autoload_data(VALUE mod, ID id)
{
    struct st_table *tbl;
    st_data_t val;

    // If we are called with a non-origin ICLASS, fetch the autoload data from
    // the original module.
    if (RB_TYPE_P(mod, T_ICLASS)) {
        if (FL_TEST_RAW(mod, RICLASS_IS_ORIGIN)) {
            return 0;
        }
        else {
            mod = RBASIC(mod)->klass;
        }
    }

    RUBY_ASSERT(RB_TYPE_P(mod, T_CLASS) || RB_TYPE_P(mod, T_MODULE));

    // Look up the instance variable table for `autoload`, then index into that table with the given constant name `id`.

    VALUE tbl_value = rb_ivar_lookup(mod, autoload, 0);
    if (!tbl_value || !(tbl = check_autoload_table(tbl_value)) || !st_lookup(tbl, (st_data_t)id, &val)) {
        return 0;
    }

    return (VALUE)val;
}

// Every autoload constant has exactly one instance of autoload_const, stored in `autoload_features`. Since multiple autoload constants can refer to the same file, every `autoload_const` refers to a de-duplicated `autoload_data`.
struct autoload_const {
    // The linked list node of all constants which are loaded by the related autoload feature.
    struct ccan_list_node cnode; /* <=> autoload_data.constants */

    // The shared "autoload_data" if multiple constants are defined from the same feature.
    VALUE autoload_data_value;

    // The module we are loading a constant into.
    VALUE module;

    // The name of the constant we are loading.
    ID name;

    // The value of the constant (after it's loaded).
    VALUE value;

    // The constant entry flags which need to be re-applied after autoloading the feature.
    rb_const_flag_t flag;

    // The source file and line number that defined this constant (different from feature path).
    VALUE file;
    int line;
};

// Each `autoload_data` uniquely represents a specific feature which can be loaded, and a list of constants which it is able to define. We use a mutex to coordinate multiple threads trying to load the same feature.
struct autoload_data {
    // The feature path to require to load this constant.
    VALUE feature;

    // The mutex which is protecting autoloading this feature.
    VALUE mutex;

    // The process fork serial number since the autoload mutex will become invalid on fork.
    rb_serial_t fork_gen;

    // The linked list of all constants that are going to be loaded by this autoload.
    struct ccan_list_head constants; /* <=> autoload_const.cnode */
};

static void
autoload_data_compact(void *ptr)
{
    struct autoload_data *p = ptr;

    p->feature = rb_gc_location(p->feature);
    p->mutex = rb_gc_location(p->mutex);
}

static void
autoload_data_mark(void *ptr)
{
    struct autoload_data *p = ptr;

    rb_gc_mark_movable(p->feature);
    rb_gc_mark_movable(p->mutex);
}

static void
autoload_data_free(void *ptr)
{
    struct autoload_data *p = ptr;

    // We may leak some memory at VM shutdown time, no big deal...?
    if (ccan_list_empty(&p->constants)) {
        ruby_xfree(p);
    }
}

static size_t
autoload_data_memsize(const void *ptr)
{
    return sizeof(struct autoload_data);
}

static const rb_data_type_t autoload_data_type = {
    "autoload_data",
    {autoload_data_mark, autoload_data_free, autoload_data_memsize, autoload_data_compact},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static void
autoload_const_compact(void *ptr)
{
    struct autoload_const *ac = ptr;

    ac->module = rb_gc_location(ac->module);
    ac->autoload_data_value = rb_gc_location(ac->autoload_data_value);
    ac->value = rb_gc_location(ac->value);
    ac->file = rb_gc_location(ac->file);
}

static void
autoload_const_mark(void *ptr)
{
    struct autoload_const *ac = ptr;

    rb_gc_mark_movable(ac->module);
    rb_gc_mark_movable(ac->autoload_data_value);
    rb_gc_mark_movable(ac->value);
    rb_gc_mark_movable(ac->file);
}

static size_t
autoload_const_memsize(const void *ptr)
{
    return sizeof(struct autoload_const);
}

static void
autoload_const_free(void *ptr)
{
    struct autoload_const *autoload_const = ptr;

    ccan_list_del(&autoload_const->cnode);
    ruby_xfree(ptr);
}

static const rb_data_type_t autoload_const_type = {
    "autoload_const",
    {autoload_const_mark, autoload_const_free, autoload_const_memsize, autoload_const_compact,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static struct autoload_data *
get_autoload_data(VALUE autoload_const_value, struct autoload_const **autoload_const_pointer)
{
    struct autoload_const *autoload_const = rb_check_typeddata(autoload_const_value, &autoload_const_type);

    struct autoload_data *autoload_data = rb_check_typeddata(autoload_const->autoload_data_value, &autoload_data_type);

    /* do not reach across stack for ->state after forking: */
    if (autoload_data && autoload_data->fork_gen != GET_VM()->fork_gen) {
        autoload_data->mutex = Qnil;
        autoload_data->fork_gen = 0;
    }

    if (autoload_const_pointer) *autoload_const_pointer = autoload_const;

    return autoload_data;
}

RUBY_FUNC_EXPORTED void
rb_autoload(VALUE module, ID name, const char *feature)
{
    if (!feature || !*feature) {
        rb_raise(rb_eArgError, "empty feature name");
    }

    rb_autoload_str(module, name, rb_fstring_cstr(feature));
}

static void const_set(VALUE klass, ID id, VALUE val);
static void const_added(VALUE klass, ID const_name);

struct autoload_arguments {
    VALUE module;
    ID name;
    VALUE feature;
};

static VALUE
autoload_feature_lookup_or_create(VALUE feature, struct autoload_data **autoload_data_pointer)
{
    RUBY_ASSERT_MUTEX_OWNED(autoload_mutex);
    RUBY_ASSERT_CRITICAL_SECTION_ENTER();

    VALUE autoload_data_value = rb_hash_aref(autoload_features, feature);
    struct autoload_data *autoload_data;

    if (NIL_P(autoload_data_value)) {
        autoload_data_value = TypedData_Make_Struct(0, struct autoload_data, &autoload_data_type, autoload_data);
        autoload_data->feature = feature;
        autoload_data->mutex = Qnil;
        ccan_list_head_init(&autoload_data->constants);

        if (autoload_data_pointer) *autoload_data_pointer = autoload_data;

        rb_hash_aset(autoload_features, feature, autoload_data_value);
    }
    else if (autoload_data_pointer) {
        *autoload_data_pointer = rb_check_typeddata(autoload_data_value, &autoload_data_type);
    }

    RUBY_ASSERT_CRITICAL_SECTION_LEAVE();
    return autoload_data_value;
}

static struct st_table *
autoload_table_lookup_or_create(VALUE module)
{
    VALUE autoload_table_value = rb_ivar_lookup(module, autoload, 0);
    if (autoload_table_value) {
        return check_autoload_table(autoload_table_value);
    }
    else {
        autoload_table_value = TypedData_Wrap_Struct(0, &autoload_table_type, 0);
        rb_class_ivar_set(module, autoload, autoload_table_value);
        return (DATA_PTR(autoload_table_value) = st_init_numtable());
    }
}

static VALUE
autoload_synchronized(VALUE _arguments)
{
    struct autoload_arguments *arguments = (struct autoload_arguments *)_arguments;

    rb_const_entry_t *constant_entry = rb_const_lookup(arguments->module, arguments->name);
    if (constant_entry && !UNDEF_P(constant_entry->value)) {
        return Qfalse;
    }

    // Reset any state associated with any previous constant:
    const_set(arguments->module, arguments->name, Qundef);

    struct st_table *autoload_table = autoload_table_lookup_or_create(arguments->module);

    // Ensure the string is uniqued since we use an identity lookup:
    VALUE feature = rb_fstring(arguments->feature);

    struct autoload_data *autoload_data;
    VALUE autoload_data_value = autoload_feature_lookup_or_create(feature, &autoload_data);

    {
        struct autoload_const *autoload_const;
        VALUE autoload_const_value = TypedData_Make_Struct(0, struct autoload_const, &autoload_const_type, autoload_const);
        autoload_const->module = arguments->module;
        autoload_const->name = arguments->name;
        autoload_const->value = Qundef;
        autoload_const->flag = CONST_PUBLIC;
        autoload_const->autoload_data_value = autoload_data_value;
        ccan_list_add_tail(&autoload_data->constants, &autoload_const->cnode);
        st_insert(autoload_table, (st_data_t)arguments->name, (st_data_t)autoload_const_value);
    }

    return Qtrue;
}

void
rb_autoload_str(VALUE module, ID name, VALUE feature)
{
    if (!rb_is_const_id(name)) {
        rb_raise(rb_eNameError, "autoload must be constant name: %"PRIsVALUE"", QUOTE_ID(name));
    }

    Check_Type(feature, T_STRING);
    if (!RSTRING_LEN(feature)) {
        rb_raise(rb_eArgError, "empty feature name");
    }

    struct autoload_arguments arguments = {
        .module = module,
        .name = name,
        .feature = feature,
    };

    VALUE result = rb_mutex_synchronize(autoload_mutex, autoload_synchronized, (VALUE)&arguments);

    if (result == Qtrue) {
        const_added(module, name);
    }
}

static void
autoload_delete(VALUE module, ID name)
{
    RUBY_ASSERT_CRITICAL_SECTION_ENTER();

    st_data_t load = 0, key = name;

    RUBY_ASSERT(RB_TYPE_P(module, T_CLASS) || RB_TYPE_P(module, T_MODULE));

    VALUE table_value = rb_ivar_lookup(module, autoload, 0);
    if (table_value) {
        struct st_table *table = check_autoload_table(table_value);

        st_delete(table, &key, &load);

        /* Qfalse can indicate already deleted */
        if (load != Qfalse) {
            struct autoload_const *autoload_const;
            struct autoload_data *autoload_data = get_autoload_data((VALUE)load, &autoload_const);

            VM_ASSERT(autoload_data);
            VM_ASSERT(!ccan_list_empty(&autoload_data->constants));

            /*
             * we must delete here to avoid "already initialized" warnings
             * with parallel autoload.  Using list_del_init here so list_del
             * works in autoload_const_free
             */
            ccan_list_del_init(&autoload_const->cnode);

            if (ccan_list_empty(&autoload_data->constants)) {
                rb_hash_delete(autoload_features, autoload_data->feature);
            }

            // If the autoload table is empty, we can delete it.
            if (table->num_entries == 0) {
                rb_attr_delete(module, autoload);
            }
        }
    }

    RUBY_ASSERT_CRITICAL_SECTION_LEAVE();
}

static int
autoload_by_someone_else(struct autoload_data *ele)
{
    return ele->mutex != Qnil && !rb_mutex_owned_p(ele->mutex);
}

static VALUE
check_autoload_required(VALUE mod, ID id, const char **loadingpath)
{
    VALUE autoload_const_value = autoload_data(mod, id);
    struct autoload_data *autoload_data;
    const char *loading;

    if (!autoload_const_value || !(autoload_data = get_autoload_data(autoload_const_value, 0))) {
        return 0;
    }

    VALUE feature = autoload_data->feature;

    /*
     * if somebody else is autoloading, we MUST wait for them, since
     * rb_provide_feature can provide a feature before autoload_const_set
     * completes.  We must wait until autoload_const_set finishes in
     * the other thread.
     */
    if (autoload_by_someone_else(autoload_data)) {
        return autoload_const_value;
    }

    loading = RSTRING_PTR(feature);

    if (!rb_feature_provided(loading, &loading)) {
        return autoload_const_value;
    }

    if (loadingpath && loading) {
        *loadingpath = loading;
        return autoload_const_value;
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

static int
autoload_by_current(struct autoload_data *ele)
{
    return ele->mutex != Qnil && rb_mutex_owned_p(ele->mutex);
}

// If there is an autoloading constant and it has been set by the current
// execution context, return it. This allows threads which are loading code to
// refer to their own autoloaded constants.
struct autoload_const *
autoloading_const_entry(VALUE mod, ID id)
{
    VALUE load = autoload_data(mod, id);
    struct autoload_data *ele;
    struct autoload_const *ac;

    // Find the autoloading state:
    if (!load || !(ele = get_autoload_data(load, &ac))) {
        // Couldn't be found:
        return 0;
    }

    // Check if it's being loaded by the current thread/fiber:
    if (autoload_by_current(ele)) {
        if (!UNDEF_P(ac->value)) {
            return ac;
        }
    }

    return 0;
}

static int
autoload_defined_p(VALUE mod, ID id)
{
    rb_const_entry_t *ce = rb_const_lookup(mod, id);

    // If there is no constant or the constant is not undefined (special marker for autoloading):
    if (!ce || !UNDEF_P(ce->value)) {
        // We are not autoloading:
        return 0;
    }

    // Otherwise check if there is an autoload in flight right now:
    return !rb_autoloading_value(mod, id, NULL, NULL);
}

static void const_tbl_update(struct autoload_const *, int);

struct autoload_load_arguments {
    VALUE module;
    ID name;
    int flag;

    VALUE mutex;

    // The specific constant which triggered the autoload code to fire:
    struct autoload_const *autoload_const;

    // The parent autoload data which is shared between multiple constants:
    struct autoload_data *autoload_data;
};

static VALUE
autoload_const_set(struct autoload_const *ac)
{
    check_before_mod_set(ac->module, ac->name, ac->value, "constant");

    RB_VM_LOCK_ENTER();
    {
        const_tbl_update(ac, true);
    }
    RB_VM_LOCK_LEAVE();

    return 0; /* ignored */
}

static VALUE
autoload_load_needed(VALUE _arguments)
{
    struct autoload_load_arguments *arguments = (struct autoload_load_arguments*)_arguments;

    const char *loading = 0, *src;

    if (!autoload_defined_p(arguments->module, arguments->name)) {
        return Qfalse;
    }

    VALUE autoload_const_value = check_autoload_required(arguments->module, arguments->name, &loading);
    if (!autoload_const_value) {
        return Qfalse;
    }

    src = rb_sourcefile();
    if (src && loading && strcmp(src, loading) == 0) {
        return Qfalse;
    }

    struct autoload_const *autoload_const;
    struct autoload_data *autoload_data;
    if (!(autoload_data = get_autoload_data(autoload_const_value, &autoload_const))) {
        return Qfalse;
    }

    if (NIL_P(autoload_data->mutex)) {
        autoload_data->mutex = rb_mutex_new();
        autoload_data->fork_gen = GET_VM()->fork_gen;
    }
    else if (rb_mutex_owned_p(autoload_data->mutex)) {
        return Qfalse;
    }

    arguments->mutex = autoload_data->mutex;
    arguments->autoload_const = autoload_const;

    return autoload_const_value;
}

static VALUE
autoload_apply_constants(VALUE _arguments)
{
    RUBY_ASSERT_CRITICAL_SECTION_ENTER();

    struct autoload_load_arguments *arguments = (struct autoload_load_arguments*)_arguments;

    struct autoload_const *autoload_const = 0; // for ccan_container_off_var()
    struct autoload_const *next;

    // We use safe iteration here because `autoload_const_set` will eventually invoke
    // `autoload_delete` which will remove the constant from the linked list. In theory, once
    // the `autoload_data->constants` linked list is empty, we can remove it.

    // Iterate over all constants and assign them:
    ccan_list_for_each_safe(&arguments->autoload_data->constants, autoload_const, next, cnode) {
        if (!UNDEF_P(autoload_const->value)) {
            autoload_const_set(autoload_const);
        }
    }

    RUBY_ASSERT_CRITICAL_SECTION_LEAVE();

    return Qtrue;
}

static VALUE
autoload_feature_require(VALUE _arguments)
{
    struct autoload_load_arguments *arguments = (struct autoload_load_arguments*)_arguments;

    struct autoload_const *autoload_const = arguments->autoload_const;

    // We save this for later use in autoload_apply_constants:
    arguments->autoload_data = rb_check_typeddata(autoload_const->autoload_data_value, &autoload_data_type);

    VALUE result = rb_funcall(rb_vm_top_self(), rb_intern("require"), 1, arguments->autoload_data->feature);

    if (RTEST(result)) {
        return rb_mutex_synchronize(autoload_mutex, autoload_apply_constants, _arguments);
    }

    return result;
}

static VALUE
autoload_try_load(VALUE _arguments)
{
    struct autoload_load_arguments *arguments = (struct autoload_load_arguments*)_arguments;

    VALUE result = autoload_feature_require(_arguments);

    // After we loaded the feature, if the constant is not defined, we remove it completely:
    rb_const_entry_t *ce = rb_const_lookup(arguments->module, arguments->name);

    if (!ce || UNDEF_P(ce->value)) {
        result = Qfalse;

        rb_const_remove(arguments->module, arguments->name);

        if (arguments->module == rb_cObject) {
            rb_warning(
                "Expected %"PRIsVALUE" to define %"PRIsVALUE" but it didn't",
                arguments->autoload_data->feature,
                ID2SYM(arguments->name)
            );
        }
        else {
            rb_warning(
                "Expected %"PRIsVALUE" to define %"PRIsVALUE"::%"PRIsVALUE" but it didn't",
                arguments->autoload_data->feature,
                arguments->module,
                ID2SYM(arguments->name)
            );
        }
    }
    else {
        // Otherwise, it was loaded, copy the flags from the autoload constant:
        ce->flag |= arguments->flag;
    }

    return result;
}

VALUE
rb_autoload_load(VALUE module, ID name)
{
    rb_const_entry_t *ce = rb_const_lookup(module, name);

    // We bail out as early as possible without any synchronisation:
    if (!ce || !UNDEF_P(ce->value)) {
        return Qfalse;
    }

    // At this point, we assume there might be autoloading, so fail if it's ractor:
    if (UNLIKELY(!rb_ractor_main_p())) {
        rb_raise(rb_eRactorUnsafeError, "require by autoload on non-main Ractor is not supported (%s)", rb_id2name(name));
    }

    // This state is stored on thes stack and is used during the autoload process.
    struct autoload_load_arguments arguments = {.module = module, .name = name, .mutex = Qnil};

    // Figure out whether we can autoload the named constant:
    VALUE autoload_const_value = rb_mutex_synchronize(autoload_mutex, autoload_load_needed, (VALUE)&arguments);

    // This confirms whether autoloading is required or not:
    if (autoload_const_value == Qfalse) return autoload_const_value;

    arguments.flag = ce->flag & (CONST_DEPRECATED | CONST_VISIBILITY_MASK);

    // Only one thread will enter here at a time:
    VALUE result = rb_mutex_synchronize(arguments.mutex, autoload_try_load, (VALUE)&arguments);

    // If you don't guard this value, it's possible for the autoload constant to
    // be freed by another thread which loads multiple constants, one of which
    // resolves to the constant this thread is trying to load, so proteect this
    // so that it is not freed until we are done with it in `autoload_try_load`:
    RB_GC_GUARD(autoload_const_value);

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
    struct autoload_data *ele;

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
            rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "constant ::%"PRIsVALUE" is deprecated", QUOTE_ID(id));
        }
        else {
            rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "constant %"PRIsVALUE"::%"PRIsVALUE" is deprecated",
                    rb_class_name(klass), QUOTE_ID(id));
        }
    }
}

static VALUE
rb_const_get_0(VALUE klass, ID id, int exclude, int recurse, int visibility)
{
    VALUE c = rb_const_search(klass, id, exclude, recurse, visibility);
    if (!UNDEF_P(c)) {
        if (UNLIKELY(!rb_ractor_main_p())) {
            if (!rb_ractor_shareable_p(c)) {
                rb_raise(rb_eRactorIsolationError, "can not access non-shareable objects in constant %"PRIsVALUE"::%s by non-main Ractor.", rb_class_path(klass), rb_id2name(id));
            }
        }
        return c;
    }
    return rb_const_missing(klass, ID2SYM(id));
}

static VALUE
rb_const_search_from(VALUE klass, ID id, int exclude, int recurse, int visibility)
{
    VALUE value, current;
    bool first_iteration = true;

    for (current = klass;
            RTEST(current);
            current = RCLASS_SUPER(current), first_iteration = false) {
        VALUE tmp;
        VALUE am = 0;
        rb_const_entry_t *ce;

        if (!first_iteration && RCLASS_ORIGIN(current) != current) {
            // This item in the super chain has an origin iclass
            // that comes later in the chain. Skip this item so
            // prepended modules take precedence.
            continue;
        }

        // Do lookup in original class or module in case we are at an origin
        // iclass in the chain.
        tmp = current;
        if (BUILTIN_TYPE(tmp) == T_ICLASS) tmp = RBASIC(tmp)->klass;

        // Do the lookup. Loop in case of autoload.
        while ((ce = rb_const_lookup(tmp, id))) {
            if (visibility && RB_CONST_PRIVATE_P(ce)) {
                GET_EC()->private_const_reference = tmp;
                return Qundef;
            }
            rb_const_warn_if_deprecated(ce, tmp, id);
            value = ce->value;
            if (UNDEF_P(value)) {
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
    if (!UNDEF_P(value)) return value;
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
            rb_name_err_raise("cannot remove %2$s::%1$s", mod, ID2SYM(id));
        }

        undefined_constant(mod, ID2SYM(id));
    }

    rb_clear_constant_cache_for_id(id);

    val = ce->value;

    if (UNDEF_P(val)) {
        autoload_delete(mod, id);
        val = Qnil;
    }

    ruby_xfree(ce);

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

    RB_VM_LOCK_ENTER();
    {
        ary = rb_ary_new2(rb_id_table_size(tbl));
        rb_id_table_foreach(tbl, rb_local_constants_i, (void *)ary);
    }
    RB_VM_LOCK_LEAVE();

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
        RB_VM_LOCK_ENTER();
        {
            rb_id_table_foreach(RCLASS_CONST_TBL(mod), sv_i, tbl);
        }
        RB_VM_LOCK_LEAVE();
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
            if (UNDEF_P(ce->value) && !check_autoload_required(tmp, id, 0) &&
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
    if (!rb_is_const_id(id) || !rb_namespace_p(value)) {
        return ID_TABLE_CONTINUE;
    }
    classname(value, &has_permanent_classpath);
    if (has_permanent_classpath) {
        return ID_TABLE_CONTINUE;
    }
    set_namespace_path(value, build_const_path(parental_path, id));
    rb_attr_delete(value, tmp_classpath);

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

    RB_VM_LOCK_ENTER();
    {
        rb_class_ivar_set(named_namespace, classpath, namespace_path);
        if (const_table) {
            rb_id_table_foreach(const_table, set_namespace_path_i, &namespace_path);
        }
    }
    RB_VM_LOCK_LEAVE();
}

static void
const_added(VALUE klass, ID const_name)
{
    if (GET_VM()->running) {
        VALUE name = ID2SYM(const_name);
        rb_funcallv(klass, idConst_added, 1, &name);
    }
}

static void
const_set(VALUE klass, ID id, VALUE val)
{
    rb_const_entry_t *ce;

    if (NIL_P(klass)) {
        rb_raise(rb_eTypeError, "no class/module to define constant %"PRIsVALUE"",
                 QUOTE_ID(id));
    }

    if (!rb_ractor_main_p() && !rb_ractor_shareable_p(val)) {
        rb_raise(rb_eRactorIsolationError, "can not set constants with non-shareable objects by non-main Ractors");
    }

    check_before_mod_set(klass, id, val, "constant");

    RB_VM_LOCK_ENTER();
    {
        struct rb_id_table *tbl = RCLASS_CONST_TBL(klass);
        if (!tbl) {
            RCLASS_CONST_TBL(klass) = tbl = rb_id_table_create(0);
            rb_clear_constant_cache_for_id(id);
            ce = ZALLOC(rb_const_entry_t);
            rb_id_table_insert(tbl, id, (VALUE)ce);
            setup_const_entry(ce, klass, val, CONST_PUBLIC);
        }
        else {
            struct autoload_const ac = {
                .module = klass, .name = id,
                .value = val, .flag = CONST_PUBLIC,
                /* fill the rest with 0 */
            };
            ac.file = rb_source_location(&ac.line);
            const_tbl_update(&ac, false);
        }
    }
    RB_VM_LOCK_LEAVE();

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
                    ivar_set(val, tmp_classpath, build_const_path(parental_path, id));
                }
            }
        }
    }
}

void
rb_const_set(VALUE klass, ID id, VALUE val)
{
    const_set(klass, id, val);
    const_added(klass, id);
}

static struct autoload_data *
autoload_data_for_named_constant(VALUE module, ID name, struct autoload_const **autoload_const_pointer)
{
    VALUE autoload_data_value = autoload_data(module, name);
    if (!autoload_data_value) return 0;

    struct autoload_data *autoload_data = get_autoload_data(autoload_data_value, autoload_const_pointer);
    if (!autoload_data) return 0;

    /* for autoloading thread, keep the defined value to autoloading storage */
    if (autoload_by_current(autoload_data)) {
        return autoload_data;
    }

    return 0;
}

static void
const_tbl_update(struct autoload_const *ac, int autoload_force)
{
    VALUE value;
    VALUE klass = ac->module;
    VALUE val = ac->value;
    ID id = ac->name;
    struct rb_id_table *tbl = RCLASS_CONST_TBL(klass);
    rb_const_flag_t visibility = ac->flag;
    rb_const_entry_t *ce;

    if (rb_id_table_lookup(tbl, id, &value)) {
        ce = (rb_const_entry_t *)value;
        if (UNDEF_P(ce->value)) {
            RUBY_ASSERT_CRITICAL_SECTION_ENTER();
            VALUE file = ac->file;
            int line = ac->line;
            struct autoload_data *ele = autoload_data_for_named_constant(klass, id, &ac);

            if (!autoload_force && ele) {
                rb_clear_constant_cache_for_id(id);

                ac->value = val; /* autoload_data is non-WB-protected */
                ac->file = rb_source_location(&ac->line);
            }
            else {
                /* otherwise autoloaded constant, allow to override */
                autoload_delete(klass, id);
                ce->flag = visibility;
                RB_OBJ_WRITE(klass, &ce->value, val);
                RB_OBJ_WRITE(klass, &ce->file, file);
                ce->line = line;
            }
            RUBY_ASSERT_CRITICAL_SECTION_LEAVE();
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
        rb_clear_constant_cache_for_id(id);
        setup_const_entry(ce, klass, val, visibility);
    }
    else {
        rb_clear_constant_cache_for_id(id);

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
            undefined_constant(mod, val);
        }
        if ((ce = rb_const_lookup(mod, id))) {
            ce->flag &= ~mask;
            ce->flag |= flag;
            if (UNDEF_P(ce->value)) {
                struct autoload_data *ele;

                ele = autoload_data_for_named_constant(mod, id, &ac);
                if (ele) {
                    ac->flag &= ~mask;
                    ac->flag |= flag;
                }
            }
        rb_clear_constant_cache_for_id(id);
        }
        else {
            undefined_constant(mod, ID2SYM(id));
        }
    }
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
    if (RB_TYPE_P(klass, T_ICLASS)) {
        if (FL_TEST_RAW(klass, RICLASS_IS_ORIGIN)) {
            return 0;
        }
        else {
            // check the original module
            klass = RBASIC(klass)->klass;
        }
    }

    VALUE n = rb_ivar_lookup(klass, id, Qundef);
    if (UNDEF_P(n)) return 0;

    if (v) *v = n;
    return 1;
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
        if (original_module(front) != original_module(target)) {
            rb_raise(rb_eRuntimeError,
                     "class variable % "PRIsVALUE" of %"PRIsVALUE" is overtaken by %"PRIsVALUE"",
                       ID2SYM(id), rb_class_name(original_module(front)),
                       rb_class_name(original_module(target)));
        }
        if (BUILTIN_TYPE(front) == T_CLASS) {
            rb_ivar_delete(front, id, Qundef);
        }
    }
}

static VALUE
find_cvar(VALUE klass, VALUE * front, VALUE * target, ID id)
{
    VALUE v = Qundef;
    CVAR_ACCESSOR_SHOULD_BE_MAIN_RACTOR();
    if (cvar_lookup_at(klass, id, (&v))) {
        if (!*front) {
            *front = klass;
        }
        *target = klass;
    }

    for (klass = cvar_front_klass(klass); klass; klass = RCLASS_SUPER(klass)) {
        if (cvar_lookup_at(klass, id, (&v))) {
            if (!*front) {
                *front = klass;
            }
            *target = klass;
        }
    }

    return v;
}

#define CVAR_FOREACH_ANCESTORS(klass, v, r) \
    for (klass = cvar_front_klass(klass); klass; klass = RCLASS_SUPER(klass)) { \
        if (cvar_lookup_at(klass, id, (v))) { \
            r; \
        } \
    }

#define CVAR_LOOKUP(v,r) do {\
    CVAR_ACCESSOR_SHOULD_BE_MAIN_RACTOR(); \
    if (cvar_lookup_at(klass, id, (v))) {r;}\
    CVAR_FOREACH_ANCESTORS(klass, v, r);\
} while(0)

static void
check_for_cvar_table(VALUE subclass, VALUE key)
{
    // Must not check ivar on ICLASS
    if (!RB_TYPE_P(subclass, T_ICLASS) && RTEST(rb_ivar_defined(subclass, key))) {
        RB_DEBUG_COUNTER_INC(cvar_class_invalidate);
        ruby_vm_global_cvar_state++;
        return;
    }

    rb_class_foreach_subclass(subclass, check_for_cvar_table, key);
}

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

    int result = rb_class_ivar_set(target, id, val);

    struct rb_id_table *rb_cvc_tbl = RCLASS_CVC_TBL(target);

    if (!rb_cvc_tbl) {
        rb_cvc_tbl = RCLASS_CVC_TBL(target) = rb_id_table_create(2);
    }

    struct rb_cvar_class_tbl_entry *ent;
    VALUE ent_data;

    if (!rb_id_table_lookup(rb_cvc_tbl, id, &ent_data)) {
        ent = ALLOC(struct rb_cvar_class_tbl_entry);
        ent->class_value = target;
        ent->global_cvar_state = GET_GLOBAL_CVAR_STATE();
        rb_id_table_insert(rb_cvc_tbl, id, (VALUE)ent);
        RB_DEBUG_COUNTER_INC(cvar_inline_miss);
    }
    else {
        ent = (void *)ent_data;
        ent->global_cvar_state = GET_GLOBAL_CVAR_STATE();
    }

    // Break the cvar cache if this is a new class variable
    // and target is a module or a subclass with the same
    // cvar in this lookup.
    if (result == 0) {
        if (RB_TYPE_P(target, T_CLASS)) {
            if (RCLASS_SUBCLASSES(target)) {
                rb_class_foreach_subclass(target, check_for_cvar_table, id);
            }
        }
    }
}

VALUE
rb_cvar_find(VALUE klass, ID id, VALUE *front)
{
    VALUE target = 0;
    VALUE value;

    value = find_cvar(klass, front, &target, id);
    if (!target) {
        rb_name_err_raise("uninitialized class variable %1$s in %2$s",
                          klass, ID2SYM(id));
    }
    cvar_overtaken(*front, target, id);
    return (VALUE)value;
}

VALUE
rb_cvar_get(VALUE klass, ID id)
{
    VALUE front = 0;
    return rb_cvar_find(klass, id, &front);
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
    rb_cv_set(klass, name, val);
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
    mod = original_module(mod);

    rb_ivar_foreach(mod, cv_i, (st_data_t)tbl);
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
    st_data_t val;

    if (!id) {
        goto not_defined;
    }
    rb_check_frozen(mod);
    val = rb_ivar_delete(mod, id, Qundef);
    if (!UNDEF_P(val)) {
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
    RUBY_ASSERT(RB_TYPE_P(obj, T_CLASS) || RB_TYPE_P(obj, T_MODULE));
    int found;

    RB_VM_LOCK_ENTER();
    {
        rb_shape_t * shape = rb_shape_get_shape(obj);
        attr_index_t idx;
        found = rb_shape_get_iv_index(shape, key, &idx);

        if (found) {
            // Changing an existing instance variable
            RUBY_ASSERT(RCLASS_IVPTR(obj));

            RCLASS_IVPTR(obj)[idx] = value;
            RB_OBJ_WRITTEN(obj, Qundef, value);
        }
        else {
            // Creating and setting a new instance variable

            // Move to a shape which fits the new ivar
            idx = shape->next_iv_index;
            shape = rb_shape_get_next(shape, obj, key);

            // We always allocate a power of two sized IV array. This way we
            // only need to realloc when we expand into a new power of two size
            if ((idx & (idx - 1)) == 0) {
                size_t newsize = idx ? idx * 2 : 1;
                REALLOC_N(RCLASS_IVPTR(obj), VALUE, newsize);
            }

            RUBY_ASSERT(RCLASS_IVPTR(obj));

            RB_OBJ_WRITE(obj, &RCLASS_IVPTR(obj)[idx], value);
            rb_shape_set_shape(obj, shape);
        }
    }
    RB_VM_LOCK_LEAVE();

    return found;
}

static int
tbl_copy_i(st_data_t key, st_data_t val, st_data_t dest) {
    rb_class_ivar_set(dest, key, val);

    return ST_CONTINUE;
}

void
rb_iv_tbl_copy(VALUE dst, VALUE src)
{
    RUBY_ASSERT(rb_type(dst) == rb_type(src));
    RUBY_ASSERT(RB_TYPE_P(dst, T_CLASS) || RB_TYPE_P(dst, T_MODULE));

    RUBY_ASSERT(RCLASS_SHAPE_ID(dst) == ROOT_SHAPE_ID || rb_shape_get_shape_by_id(RCLASS_SHAPE_ID(dst))->type == SHAPE_INITIAL_CAPACITY);
    RUBY_ASSERT(!RCLASS_IVPTR(dst));

    rb_ivar_foreach(src, tbl_copy_i, dst);
}

MJIT_FUNC_EXPORTED rb_const_entry_t *
rb_const_lookup(VALUE klass, ID id)
{
    struct rb_id_table *tbl = RCLASS_CONST_TBL(klass);

    if (tbl) {
        VALUE val;
        bool r;
        RB_VM_LOCK_ENTER();
        {
            r = rb_id_table_lookup(tbl, id, &val);
        }
        RB_VM_LOCK_LEAVE();

        if (r) return (rb_const_entry_t *)val;
    }
    return NULL;
}
