/*
 * load methods from eval.c
 */

#include "ruby/encoding.h"
#include "ruby/util.h"
#include "internal.h"
#include "dln.h"
#include "eval_intern.h"
#include "probes.h"
#include "iseq.h"

static VALUE ruby_dln_librefs;

#define IS_RBEXT(e) (strcmp((e), ".rb") == 0)
#define IS_SOEXT(e) (strcmp((e), ".so") == 0 || strcmp((e), ".o") == 0)
#ifdef DLEXT2
#define IS_DLEXT(e) (strcmp((e), DLEXT) == 0 || strcmp((e), DLEXT2) == 0)
#else
#define IS_DLEXT(e) (strcmp((e), DLEXT) == 0)
#endif

static const char *const loadable_ext[] = {
    ".rb", DLEXT,
#ifdef DLEXT2
    DLEXT2,
#endif
    0
};

VALUE
rb_get_load_path(void)
{
    VALUE load_path = GET_VM()->load_path;
    return load_path;
}

enum expand_type {
    EXPAND_ALL,
    EXPAND_RELATIVE,
    EXPAND_HOME,
    EXPAND_NON_CACHE
};

/* Construct expanded load path and store it to cache.
   We rebuild load path partially if the cache is invalid.
   We don't cache non string object and expand it every time. We ensure that
   string objects in $LOAD_PATH are frozen.
 */
static void
rb_construct_expanded_load_path(enum expand_type type, int *has_relative, int *has_non_cache)
{
    rb_vm_t *vm = GET_VM();
    VALUE load_path = vm->load_path;
    VALUE expanded_load_path = vm->expanded_load_path;
    VALUE ary;
    long i;
    int level = rb_safe_level();

    ary = rb_ary_tmp_new(RARRAY_LEN(load_path));
    for (i = 0; i < RARRAY_LEN(load_path); ++i) {
	VALUE path, as_str, expanded_path;
	int is_string, non_cache;
	char *as_cstr;
	as_str = path = RARRAY_AREF(load_path, i);
	is_string = RB_TYPE_P(path, T_STRING) ? 1 : 0;
	non_cache = !is_string ? 1 : 0;
	as_str = rb_get_path_check_to_string(path, level);
	as_cstr = RSTRING_PTR(as_str);

	if (!non_cache) {
	    if ((type == EXPAND_RELATIVE &&
		    rb_is_absolute_path(as_cstr)) ||
		(type == EXPAND_HOME &&
		    (!as_cstr[0] || as_cstr[0] != '~')) ||
		(type == EXPAND_NON_CACHE)) {
		    /* Use cached expanded path. */
		    rb_ary_push(ary, RARRAY_AREF(expanded_load_path, i));
		    continue;
	    }
	}
	if (!*has_relative && !rb_is_absolute_path(as_cstr))
	    *has_relative = 1;
	if (!*has_non_cache && non_cache)
	    *has_non_cache = 1;
	/* Freeze only string object. We expand other objects every time. */
	if (is_string)
	    rb_str_freeze(path);
	as_str = rb_get_path_check_convert(path, as_str, level);
	expanded_path = rb_check_realpath(Qnil, as_str);
	if (NIL_P(expanded_path)) expanded_path = as_str;
	rb_ary_push(ary, rb_fstring(expanded_path));
    }
    rb_obj_freeze(ary);
    vm->expanded_load_path = ary;
    rb_ary_replace(vm->load_path_snapshot, vm->load_path);
}

VALUE
rb_get_expanded_load_path(void)
{
    rb_vm_t *vm = GET_VM();
    const VALUE non_cache = Qtrue;

    if (!rb_ary_shared_with_p(vm->load_path_snapshot, vm->load_path)) {
	/* The load path was modified. Rebuild the expanded load path. */
	int has_relative = 0, has_non_cache = 0;
	rb_construct_expanded_load_path(EXPAND_ALL, &has_relative, &has_non_cache);
	if (has_relative) {
	    vm->load_path_check_cache = rb_dir_getwd_ospath();
	}
	else if (has_non_cache) {
	    /* Non string object. */
	    vm->load_path_check_cache = non_cache;
	}
	else {
	    vm->load_path_check_cache = 0;
	}
    }
    else if (vm->load_path_check_cache == non_cache) {
	int has_relative = 1, has_non_cache = 1;
	/* Expand only non-cacheable objects. */
	rb_construct_expanded_load_path(EXPAND_NON_CACHE,
					&has_relative, &has_non_cache);
    }
    else if (vm->load_path_check_cache) {
	int has_relative = 1, has_non_cache = 1;
	VALUE cwd = rb_dir_getwd_ospath();
	if (!rb_str_equal(vm->load_path_check_cache, cwd)) {
	    /* Current working directory or filesystem encoding was changed.
	       Expand relative load path and non-cacheable objects again. */
	    vm->load_path_check_cache = cwd;
	    rb_construct_expanded_load_path(EXPAND_RELATIVE,
					    &has_relative, &has_non_cache);
	}
	else {
	    /* Expand only tilde (User HOME) and non-cacheable objects. */
	    rb_construct_expanded_load_path(EXPAND_HOME,
					    &has_relative, &has_non_cache);
	}
    }
    return vm->expanded_load_path;
}

static VALUE
load_path_getter(ID id, VALUE * p)
{
    rb_vm_t *vm = (void *)p;
    return vm->load_path;
}

static VALUE
get_loaded_features(void)
{
    return GET_VM()->loaded_features;
}

static VALUE
get_LOADED_FEATURES(ID _x, VALUE *_y)
{
    return get_loaded_features();
}

static void
reset_loaded_features_snapshot(void)
{
    rb_vm_t *vm = GET_VM();
    rb_ary_replace(vm->loaded_features_snapshot, vm->loaded_features);
}

static struct st_table *
get_loaded_features_index_raw(void)
{
    return GET_VM()->loaded_features_index;
}

static st_table *
get_loading_table(void)
{
    return GET_VM()->loading_table;
}

static st_data_t
feature_key(const char *str, size_t len)
{
    return st_hash(str, len, 0xfea7009e);
}

static void
features_index_add_single(const char* str, size_t len, VALUE offset)
{
    struct st_table *features_index;
    VALUE this_feature_index = Qnil;
    st_data_t short_feature_key;

    Check_Type(offset, T_FIXNUM);
    short_feature_key = feature_key(str, len);

    features_index = get_loaded_features_index_raw();
    st_lookup(features_index, short_feature_key, (st_data_t *)&this_feature_index);

    if (NIL_P(this_feature_index)) {
	st_insert(features_index, short_feature_key, (st_data_t)offset);
    }
    else if (RB_TYPE_P(this_feature_index, T_FIXNUM)) {
	VALUE feature_indexes[2];
	feature_indexes[0] = this_feature_index;
	feature_indexes[1] = offset;
	this_feature_index = (VALUE)xcalloc(1, sizeof(struct RArray));
	RBASIC(this_feature_index)->flags = T_ARRAY; /* fake VALUE, do not mark/sweep */
	rb_ary_cat(this_feature_index, feature_indexes, numberof(feature_indexes));
	st_insert(features_index, short_feature_key, (st_data_t)this_feature_index);
    }
    else {
	Check_Type(this_feature_index, T_ARRAY);
	rb_ary_push(this_feature_index, offset);
    }
}

/* Add to the loaded-features index all the required entries for
   `feature`, located at `offset` in $LOADED_FEATURES.  We add an
   index entry at each string `short_feature` for which
     feature == "#{prefix}#{short_feature}#{ext}"
   where `ext` is empty or matches %r{^\.[^./]*$}, and `prefix` is empty
   or ends in '/'.  This maintains the invariant that `rb_feature_p()`
   relies on for its fast lookup.
*/
static void
features_index_add(VALUE feature, VALUE offset)
{
    const char *feature_str, *feature_end, *ext, *p;

    feature_str = StringValuePtr(feature);
    feature_end = feature_str + RSTRING_LEN(feature);

    for (ext = feature_end; ext > feature_str; ext--)
	if (*ext == '.' || *ext == '/')
	    break;
    if (*ext != '.')
	ext = NULL;
    /* Now `ext` points to the only string matching %r{^\.[^./]*$} that is
       at the end of `feature`, or is NULL if there is no such string. */

    p = ext ? ext : feature_end;
    while (1) {
	p--;
	while (p >= feature_str && *p != '/')
	    p--;
	if (p < feature_str)
	    break;
	/* Now *p == '/'.  We reach this point for every '/' in `feature`. */
	features_index_add_single(p + 1, feature_end - p - 1, offset);
	if (ext) {
	    features_index_add_single(p + 1, ext - p - 1, offset);
	}
    }
    features_index_add_single(feature_str, feature_end - feature_str, offset);
    if (ext) {
	features_index_add_single(feature_str, ext - feature_str, offset);
    }
}

static int
loaded_features_index_clear_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE obj = (VALUE)val;
    if (!SPECIAL_CONST_P(obj)) {
	rb_ary_free(obj);
	ruby_sized_xfree((void *)obj, sizeof(struct RArray));
    }
    return ST_DELETE;
}

static st_table *
get_loaded_features_index(void)
{
    VALUE features;
    int i;
    rb_vm_t *vm = GET_VM();

    if (!rb_ary_shared_with_p(vm->loaded_features_snapshot, vm->loaded_features)) {
	/* The sharing was broken; something (other than us in rb_provide_feature())
	   modified loaded_features.  Rebuild the index. */
	st_foreach(vm->loaded_features_index, loaded_features_index_clear_i, 0);
	features = vm->loaded_features;
	for (i = 0; i < RARRAY_LEN(features); i++) {
	    VALUE entry, as_str;
	    as_str = entry = rb_ary_entry(features, i);
	    StringValue(as_str);
	    as_str = rb_fstring(rb_str_freeze(as_str));
	    if (as_str != entry)
		rb_ary_store(features, i, as_str);
	    features_index_add(as_str, INT2FIX(i));
	}
	reset_loaded_features_snapshot();
    }
    return vm->loaded_features_index;
}

/* This searches `load_path` for a value such that
     name == "#{load_path[i]}/#{feature}"
   if `feature` is a suffix of `name`, or otherwise
     name == "#{load_path[i]}/#{feature}#{ext}"
   for an acceptable string `ext`.  It returns
   `load_path[i].to_str` if found, else 0.

   If type is 's', then `ext` is acceptable only if IS_DLEXT(ext);
   if 'r', then only if IS_RBEXT(ext); otherwise `ext` may be absent
   or have any value matching `%r{^\.[^./]*$}`.
*/
static VALUE
loaded_feature_path(const char *name, long vlen, const char *feature, long len,
		    int type, VALUE load_path)
{
    long i;
    long plen;
    const char *e;

    if (vlen < len+1) return 0;
    if (strchr(feature, '.') && !strncmp(name+(vlen-len), feature, len)) {
	plen = vlen - len;
    }
    else {
	for (e = name + vlen; name != e && *e != '.' && *e != '/'; --e);
	if (*e != '.' ||
	    e-name < len ||
	    strncmp(e-len, feature, len))
	    return 0;
	plen = e - name - len;
    }
    if (plen > 0 && name[plen-1] != '/') {
	return 0;
    }
    if (type == 's' ? !IS_DLEXT(&name[plen+len]) :
	type == 'r' ? !IS_RBEXT(&name[plen+len]) :
	0) {
	return 0;
    }
    /* Now name == "#{prefix}/#{feature}#{ext}" where ext is acceptable
       (possibly empty) and prefix is some string of length plen. */

    if (plen > 0) --plen;	/* exclude '.' */
    for (i = 0; i < RARRAY_LEN(load_path); ++i) {
	VALUE p = RARRAY_AREF(load_path, i);
	const char *s = StringValuePtr(p);
	long n = RSTRING_LEN(p);

	if (n != plen) continue;
	if (n && strncmp(name, s, n)) continue;
	return p;
    }
    return 0;
}

struct loaded_feature_searching {
    const char *name;
    long len;
    int type;
    VALUE load_path;
    const char *result;
};

static int
loaded_feature_path_i(st_data_t v, st_data_t b, st_data_t f)
{
    const char *s = (const char *)v;
    struct loaded_feature_searching *fp = (struct loaded_feature_searching *)f;
    VALUE p = loaded_feature_path(s, strlen(s), fp->name, fp->len,
				  fp->type, fp->load_path);
    if (!p) return ST_CONTINUE;
    fp->result = s;
    return ST_STOP;
}

static int
rb_feature_p(const char *feature, const char *ext, int rb, int expanded, const char **fn)
{
    VALUE features, this_feature_index = Qnil, v, p, load_path = 0;
    const char *f, *e;
    long i, len, elen, n;
    st_table *loading_tbl, *features_index;
    st_data_t data;
    st_data_t key;
    int type;

    if (fn) *fn = 0;
    if (ext) {
	elen = strlen(ext);
	len = strlen(feature) - elen;
	type = rb ? 'r' : 's';
    }
    else {
	len = strlen(feature);
	elen = 0;
	type = 0;
    }
    features = get_loaded_features();
    features_index = get_loaded_features_index();

    key = feature_key(feature, strlen(feature));
    st_lookup(features_index, key, (st_data_t *)&this_feature_index);
    /* We search `features` for an entry such that either
         "#{features[i]}" == "#{load_path[j]}/#{feature}#{e}"
       for some j, or
         "#{features[i]}" == "#{feature}#{e}"
       Here `e` is an "allowed" extension -- either empty or one
       of the extensions accepted by IS_RBEXT, IS_SOEXT, or
       IS_DLEXT.  Further, if `ext && rb` then `IS_RBEXT(e)`,
       and if `ext && !rb` then `IS_SOEXT(e) || IS_DLEXT(e)`.

       If `expanded`, then only the latter form (without load_path[j])
       is accepted.  Otherwise either form is accepted, *unless* `ext`
       is false and an otherwise-matching entry of the first form is
       preceded by an entry of the form
         "#{features[i2]}" == "#{load_path[j2]}/#{feature}#{e2}"
       where `e2` matches %r{^\.[^./]*$} but is not an allowed extension.
       After a "distractor" entry of this form, only entries of the
       form "#{feature}#{e}" are accepted.

       In `rb_provide_feature()` and `get_loaded_features_index()` we
       maintain an invariant that the array `this_feature_index` will
       point to every entry in `features` which has the form
         "#{prefix}#{feature}#{e}"
       where `e` is empty or matches %r{^\.[^./]*$}, and `prefix` is empty
       or ends in '/'.  This includes both match forms above, as well
       as any distractors, so we may ignore all other entries in `features`.
     */
    if (!NIL_P(this_feature_index)) {
	for (i = 0; ; i++) {
	    VALUE entry;
	    long index;
	    if (RB_TYPE_P(this_feature_index, T_ARRAY)) {
		if (i >= RARRAY_LEN(this_feature_index)) break;
		entry = RARRAY_AREF(this_feature_index, i);
	    }
	    else {
		if (i > 0) break;
		entry = this_feature_index;
	    }
	    index = FIX2LONG(entry);

	    v = RARRAY_AREF(features, index);
	    f = StringValuePtr(v);
	    if ((n = RSTRING_LEN(v)) < len) continue;
	    if (strncmp(f, feature, len) != 0) {
		if (expanded) continue;
		if (!load_path) load_path = rb_get_expanded_load_path();
		if (!(p = loaded_feature_path(f, n, feature, len, type, load_path)))
		    continue;
		expanded = 1;
		f += RSTRING_LEN(p) + 1;
	    }
	    if (!*(e = f + len)) {
		if (ext) continue;
		return 'u';
	    }
	    if (*e != '.') continue;
	    if ((!rb || !ext) && (IS_SOEXT(e) || IS_DLEXT(e))) {
		return 's';
	    }
	    if ((rb || !ext) && (IS_RBEXT(e))) {
		return 'r';
	    }
	}
    }

    loading_tbl = get_loading_table();
    f = 0;
    if (!expanded) {
	struct loaded_feature_searching fs;
	fs.name = feature;
	fs.len = len;
	fs.type = type;
	fs.load_path = load_path ? load_path : rb_get_expanded_load_path();
	fs.result = 0;
	st_foreach(loading_tbl, loaded_feature_path_i, (st_data_t)&fs);
	if ((f = fs.result) != 0) {
	    if (fn) *fn = f;
	    goto loading;
	}
    }
    if (st_get_key(loading_tbl, (st_data_t)feature, &data)) {
	if (fn) *fn = (const char*)data;
      loading:
	if (!ext) return 'u';
	return !IS_RBEXT(ext) ? 's' : 'r';
    }
    else {
	VALUE bufstr;
	char *buf;
	static const char so_ext[][4] = {
	    ".so", ".o",
	};

	if (ext && *ext) return 0;
	bufstr = rb_str_tmp_new(len + DLEXT_MAXLEN);
	buf = RSTRING_PTR(bufstr);
	MEMCPY(buf, feature, char, len);
	for (i = 0; (e = loadable_ext[i]) != 0; i++) {
	    strlcpy(buf + len, e, DLEXT_MAXLEN + 1);
	    if (st_get_key(loading_tbl, (st_data_t)buf, &data)) {
		rb_str_resize(bufstr, 0);
		if (fn) *fn = (const char*)data;
		return i ? 's' : 'r';
	    }
	}
	for (i = 0; i < numberof(so_ext); i++) {
	    strlcpy(buf + len, so_ext[i], DLEXT_MAXLEN + 1);
	    if (st_get_key(loading_tbl, (st_data_t)buf, &data)) {
		rb_str_resize(bufstr, 0);
		if (fn) *fn = (const char*)data;
		return 's';
	    }
	}
	rb_str_resize(bufstr, 0);
    }
    return 0;
}

int
rb_provided(const char *feature)
{
    return rb_feature_provided(feature, 0);
}

int
rb_feature_provided(const char *feature, const char **loading)
{
    const char *ext = strrchr(feature, '.');
    VALUE fullpath = 0;

    if (*feature == '.' &&
	(feature[1] == '/' || strncmp(feature+1, "./", 2) == 0)) {
	fullpath = rb_file_expand_path_fast(rb_get_path(rb_str_new2(feature)), Qnil);
	feature = RSTRING_PTR(fullpath);
    }
    if (ext && !strchr(ext, '/')) {
	if (IS_RBEXT(ext)) {
	    if (rb_feature_p(feature, ext, TRUE, FALSE, loading)) return TRUE;
	    return FALSE;
	}
	else if (IS_SOEXT(ext) || IS_DLEXT(ext)) {
	    if (rb_feature_p(feature, ext, FALSE, FALSE, loading)) return TRUE;
	    return FALSE;
	}
    }
    if (rb_feature_p(feature, 0, TRUE, FALSE, loading))
	return TRUE;
    RB_GC_GUARD(fullpath);
    return FALSE;
}

static void
rb_provide_feature(VALUE feature)
{
    VALUE features;

    features = get_loaded_features();
    if (OBJ_FROZEN(features)) {
	rb_raise(rb_eRuntimeError,
		 "$LOADED_FEATURES is frozen; cannot append feature");
    }
    rb_str_freeze(feature);

    rb_ary_push(features, rb_fstring(feature));
    features_index_add(feature, INT2FIX(RARRAY_LEN(features)-1));
    reset_loaded_features_snapshot();
}

void
rb_provide(const char *feature)
{
    rb_provide_feature(rb_fstring_cstr(feature));
}

NORETURN(static void load_failed(VALUE));

static inline void
load_iseq_eval(rb_execution_context_t *ec, VALUE fname)
{
    const rb_iseq_t *iseq = rb_iseq_load_iseq(fname);

    if (!iseq) {
        rb_ast_t *ast;
        VALUE parser = rb_parser_new();
        rb_parser_set_context(parser, NULL, FALSE);
        ast = (rb_ast_t *)rb_parser_load_file(parser, fname);
        iseq = rb_iseq_new_top(&ast->body, rb_fstring_lit("<top (required)>"),
                               fname, rb_realpath_internal(Qnil, fname, 1), NULL);
        rb_ast_dispose(ast);
    }
    rb_exec_event_hook_script_compiled(ec, iseq, Qnil);
    rb_iseq_eval(iseq);
}

static inline enum ruby_tag_type
load_wrapping(rb_execution_context_t *ec, VALUE fname)
{
    enum ruby_tag_type state;
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    volatile VALUE wrapper = th->top_wrapper;
    volatile VALUE self = th->top_self;
#if !defined __GNUC__
    rb_thread_t *volatile th0 = th;
#endif

    ec->errinfo = Qnil; /* ensure */

    /* load in anonymous module as toplevel */
    th->top_self = rb_obj_clone(rb_vm_top_self());
    th->top_wrapper = rb_module_new();
    rb_extend_object(th->top_self, th->top_wrapper);

    EC_PUSH_TAG(ec);
    state = EC_EXEC_TAG();
    if (state == TAG_NONE) {
        load_iseq_eval(ec, fname);
    }
    EC_POP_TAG();

#if !defined __GNUC__
    th = th0;
    fname = RB_GC_GUARD(fname);
#endif
    th->top_self = self;
    th->top_wrapper = wrapper;
    return state;
}

static inline void
raise_load_if_failed(rb_execution_context_t *ec, enum ruby_tag_type state)
{
    if (state) {
        rb_vm_jump_tag_but_local_jump(state);
    }

    if (!NIL_P(ec->errinfo)) {
        rb_exc_raise(ec->errinfo);
    }
}

static void
rb_load_internal(VALUE fname, int wrap)
{
    rb_execution_context_t *ec = GET_EC();
    enum ruby_tag_type state = TAG_NONE;
    if (wrap) {
        state = load_wrapping(ec, fname);
    }
    else {
        load_iseq_eval(ec, fname);
    }
    raise_load_if_failed(ec, state);
}

void
rb_load(VALUE fname, int wrap)
{
    VALUE tmp = rb_find_file(FilePathValue(fname));
    if (!tmp) load_failed(fname);
    rb_load_internal(tmp, wrap);
}

void
rb_load_protect(VALUE fname, int wrap, int *pstate)
{
    enum ruby_tag_type state;

    EC_PUSH_TAG(GET_EC());
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        rb_load(fname, wrap);
    }
    EC_POP_TAG();

    if (state != TAG_NONE) *pstate = state;
}

/*
 *  call-seq:
 *     load(filename, wrap=false)   -> true
 *
 *  Loads and executes the Ruby
 *  program in the file _filename_. If the filename does not
 *  resolve to an absolute path, the file is searched for in the library
 *  directories listed in <code>$:</code>. If the optional _wrap_
 *  parameter is +true+, the loaded script will be executed
 *  under an anonymous module, protecting the calling program's global
 *  namespace. In no circumstance will any local variables in the loaded
 *  file be propagated to the loading environment.
 */

static VALUE
rb_f_load(int argc, VALUE *argv, VALUE _)
{
    VALUE fname, wrap, path, orig_fname;

    rb_scan_args(argc, argv, "11", &fname, &wrap);

    orig_fname = rb_get_path_check_to_string(fname, rb_safe_level());
    fname = rb_str_encode_ospath(orig_fname);
    RUBY_DTRACE_HOOK(LOAD_ENTRY, RSTRING_PTR(orig_fname));

    path = rb_find_file(fname);
    if (!path) {
	if (!rb_file_load_ok(RSTRING_PTR(fname)))
	    load_failed(orig_fname);
	path = fname;
    }
    rb_load_internal(path, RTEST(wrap));

    RUBY_DTRACE_HOOK(LOAD_RETURN, RSTRING_PTR(orig_fname));

    return Qtrue;
}

static char *
load_lock(const char *ftptr)
{
    st_data_t data;
    st_table *loading_tbl = get_loading_table();

    if (!st_lookup(loading_tbl, (st_data_t)ftptr, &data)) {
	/* partial state */
	ftptr = ruby_strdup(ftptr);
	data = (st_data_t)rb_thread_shield_new();
	st_insert(loading_tbl, (st_data_t)ftptr, data);
	return (char *)ftptr;
    }
    else if (imemo_type_p(data, imemo_memo)) {
	struct MEMO *memo = MEMO_CAST(data);
        void (*init)(void) = memo->u3.func;
	data = (st_data_t)rb_thread_shield_new();
	st_insert(loading_tbl, (st_data_t)ftptr, data);
	(*init)();
	return (char *)"";
    }
    if (RTEST(ruby_verbose)) {
	VALUE warning = rb_warning_string("loading in progress, circular require considered harmful - %s", ftptr);
	rb_backtrace_each(rb_str_append, warning);
	rb_warning("%"PRIsVALUE, warning);
    }
    switch (rb_thread_shield_wait((VALUE)data)) {
      case Qfalse:
      case Qnil:
	return 0;
    }
    return (char *)ftptr;
}

static int
release_thread_shield(st_data_t *key, st_data_t *value, st_data_t done, int existing)
{
    VALUE thread_shield = (VALUE)*value;
    if (!existing) return ST_STOP;
    if (done) {
	rb_thread_shield_destroy(thread_shield);
	/* Delete the entry even if there are waiting threads, because they
	 * won't load the file and won't delete the entry. */
    }
    else if (rb_thread_shield_release(thread_shield)) {
	/* still in-use */
	return ST_CONTINUE;
    }
    xfree((char *)*key);
    return ST_DELETE;
}

static void
load_unlock(const char *ftptr, int done)
{
    if (ftptr) {
	st_data_t key = (st_data_t)ftptr;
	st_table *loading_tbl = get_loading_table();

	st_update(loading_tbl, key, release_thread_shield, done);
    }
}


/*
 *  call-seq:
 *     require(name)    -> true or false
 *
 *  Loads the given +name+, returning +true+ if successful and +false+ if the
 *  feature is already loaded.
 *
 *  If the filename does not resolve to an absolute path, it will be searched
 *  for in the directories listed in <code>$LOAD_PATH</code> (<code>$:</code>).
 *
 *  If the filename has the extension ".rb", it is loaded as a source file; if
 *  the extension is ".so", ".o", or ".dll", or the default shared library
 *  extension on the current platform, Ruby loads the shared library as a
 *  Ruby extension.  Otherwise, Ruby tries adding ".rb", ".so", and so on
 *  to the name until found.  If the file named cannot be found, a LoadError
 *  will be raised.
 *
 *  For Ruby extensions the filename given may use any shared library
 *  extension.  For example, on Linux the socket extension is "socket.so" and
 *  <code>require 'socket.dll'</code> will load the socket extension.
 *
 *  The absolute path of the loaded file is added to
 *  <code>$LOADED_FEATURES</code> (<code>$"</code>).  A file will not be
 *  loaded again if its path already appears in <code>$"</code>.  For example,
 *  <code>require 'a'; require './a'</code> will not load <code>a.rb</code>
 *  again.
 *
 *    require "my-library.rb"
 *    require "db-driver"
 *
 *  Any constants or globals within the loaded source file will be available
 *  in the calling program's global namespace. However, local variables will
 *  not be propagated to the loading environment.
 *
 */

VALUE
rb_f_require(VALUE obj, VALUE fname)
{
    return rb_require_safe(fname, rb_safe_level());
}

/*
 * call-seq:
 *   require_relative(string) -> true or false
 *
 * Ruby tries to load the library named _string_ relative to the requiring
 * file's path.  If the file's path cannot be determined a LoadError is raised.
 * If a file is loaded +true+ is returned and false otherwise.
 */
VALUE
rb_f_require_relative(VALUE obj, VALUE fname)
{
    VALUE base = rb_current_realfilepath();
    if (NIL_P(base)) {
	rb_loaderror("cannot infer basepath");
    }
    base = rb_file_dirname(base);
    return rb_require_safe(rb_file_absolute_path(fname, base), rb_safe_level());
}

typedef int (*feature_func)(const char *feature, const char *ext, int rb, int expanded, const char **fn);

static int
search_required(VALUE fname, volatile VALUE *path, int safe_level, feature_func rb_feature_p)
{
    VALUE tmp;
    char *ext, *ftptr;
    int type, ft = 0;
    const char *loading;

    *path = 0;
    ext = strrchr(ftptr = RSTRING_PTR(fname), '.');
    if (ext && !strchr(ext, '/')) {
	if (IS_RBEXT(ext)) {
	    if (rb_feature_p(ftptr, ext, TRUE, FALSE, &loading)) {
		if (loading) *path = rb_filesystem_str_new_cstr(loading);
		return 'r';
	    }
	    if ((tmp = rb_find_file_safe(fname, safe_level)) != 0) {
		ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
		if (!rb_feature_p(ftptr, ext, TRUE, TRUE, &loading) || loading)
		    *path = tmp;
		return 'r';
	    }
	    return 0;
	}
	else if (IS_SOEXT(ext)) {
	    if (rb_feature_p(ftptr, ext, FALSE, FALSE, &loading)) {
		if (loading) *path = rb_filesystem_str_new_cstr(loading);
		return 's';
	    }
	    tmp = rb_str_subseq(fname, 0, ext - RSTRING_PTR(fname));
#ifdef DLEXT2
	    OBJ_FREEZE(tmp);
	    if (rb_find_file_ext_safe(&tmp, loadable_ext + 1, safe_level)) {
		ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
		if (!rb_feature_p(ftptr, ext, FALSE, TRUE, &loading) || loading)
		    *path = tmp;
		return 's';
	    }
#else
	    rb_str_cat2(tmp, DLEXT);
	    OBJ_FREEZE(tmp);
	    if ((tmp = rb_find_file_safe(tmp, safe_level)) != 0) {
		ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
		if (!rb_feature_p(ftptr, ext, FALSE, TRUE, &loading) || loading)
		    *path = tmp;
		return 's';
	    }
#endif
	}
	else if (IS_DLEXT(ext)) {
	    if (rb_feature_p(ftptr, ext, FALSE, FALSE, &loading)) {
		if (loading) *path = rb_filesystem_str_new_cstr(loading);
		return 's';
	    }
	    if ((tmp = rb_find_file_safe(fname, safe_level)) != 0) {
		ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
		if (!rb_feature_p(ftptr, ext, FALSE, TRUE, &loading) || loading)
		    *path = tmp;
		return 's';
	    }
	}
    }
    else if ((ft = rb_feature_p(ftptr, 0, FALSE, FALSE, &loading)) == 'r') {
	if (loading) *path = rb_filesystem_str_new_cstr(loading);
	return 'r';
    }
    tmp = fname;
    type = rb_find_file_ext_safe(&tmp, loadable_ext, safe_level);
    switch (type) {
      case 0:
	if (ft)
	    goto statically_linked;
	ftptr = RSTRING_PTR(tmp);
	return rb_feature_p(ftptr, 0, FALSE, TRUE, 0);

      default:
	if (ft) {
	  statically_linked:
	    if (loading) *path = rb_filesystem_str_new_cstr(loading);
	    return ft;
	}
        /* fall through */
      case 1:
	ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
	if (rb_feature_p(ftptr, ext, !--type, TRUE, &loading) && !loading)
	    break;
	*path = tmp;
    }
    return type ? 's' : 'r';
}

static void
load_failed(VALUE fname)
{
    rb_load_fail(fname, "cannot load such file");
}

static VALUE
load_ext(VALUE path)
{
    rb_scope_visibility_set(METHOD_VISI_PUBLIC);
    return (VALUE)dln_load(RSTRING_PTR(path));
}

static int
no_feature_p(const char *feature, const char *ext, int rb, int expanded, const char **fn)
{
    return 0;
}

// Documented in doc/globals.rdoc
VALUE
rb_resolve_feature_path(VALUE klass, VALUE fname)
{
    VALUE path;
    int found;
    VALUE sym;

    fname = rb_get_path_check(fname, 0);
    path = rb_str_encode_ospath(fname);
    found = search_required(path, &path, 0, no_feature_p);

    switch (found) {
      case 'r':
        sym = ID2SYM(rb_intern("rb"));
        break;
      case 's':
        sym = ID2SYM(rb_intern("so"));
        break;
      default:
        load_failed(fname);
    }

    return rb_ary_new_from_args(2, sym, path);
}

/*
 * returns
 *  0: if already loaded (false)
 *  1: successfully loaded (true)
 * <0: not found (LoadError)
 * >1: exception
 */
static int
require_internal(rb_execution_context_t *ec, VALUE fname, int safe, int exception)
{
    volatile int result = -1;
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    volatile VALUE wrapper = th->top_wrapper;
    volatile VALUE self = th->top_self;
    volatile VALUE errinfo = ec->errinfo;
    enum ruby_tag_type state;
    struct {
	int safe;
    } volatile saved;
    char *volatile ftptr = 0;
    VALUE path;

    fname = rb_get_path_check(fname, safe);
    path = rb_str_encode_ospath(fname);
    RUBY_DTRACE_HOOK(REQUIRE_ENTRY, RSTRING_PTR(fname));

    EC_PUSH_TAG(ec);
    saved.safe = rb_safe_level();
    ec->errinfo = Qnil; /* ensure */
    th->top_wrapper = 0;
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	long handle;
	int found;

	rb_set_safe_level_force(0);

	RUBY_DTRACE_HOOK(FIND_REQUIRE_ENTRY, RSTRING_PTR(fname));
        found = search_required(path, &path, safe, rb_feature_p);
	RUBY_DTRACE_HOOK(FIND_REQUIRE_RETURN, RSTRING_PTR(fname));

	if (found) {
            if (!path || !(ftptr = load_lock(RSTRING_PTR(path)))) {
		result = 0;
	    }
	    else if (!*ftptr) {
		rb_provide_feature(path);
		result = TAG_RETURN;
	    }
	    else {
		switch (found) {
		  case 'r':
                    load_iseq_eval(ec, path);
		    break;

		  case 's':
		    handle = (long)rb_vm_call_cfunc(rb_vm_top_self(), load_ext,
						    path, VM_BLOCK_HANDLER_NONE, path);
		    rb_ary_push(ruby_dln_librefs, LONG2NUM(handle));
		    break;
		}
                rb_provide_feature(path);
                result = TAG_RETURN;
	    }
	}
    }
    EC_POP_TAG();
    th = rb_ec_thread_ptr(ec);
    th->top_self = self;
    th->top_wrapper = wrapper;
    if (ftptr) load_unlock(RSTRING_PTR(path), !state);

    rb_set_safe_level_force(saved.safe);
    if (state) {
        if (exception) {
            /* usually state == TAG_RAISE only, except for
             * rb_iseq_load_iseq in load_iseq_eval case */
            VALUE exc = rb_vm_make_jump_tag_but_local_jump(state, Qundef);
            if (!NIL_P(exc)) ec->errinfo = exc;
            return TAG_RAISE;
        }
        else if (state == TAG_RETURN) {
            return TAG_RAISE;
        }
	RB_GC_GUARD(fname);
	/* never TAG_RETURN */
	return state;
    }
    if (!NIL_P(ec->errinfo)) {
        if (!exception) return TAG_RAISE;
        rb_exc_raise(ec->errinfo);
    }

    ec->errinfo = errinfo;

    RUBY_DTRACE_HOOK(REQUIRE_RETURN, RSTRING_PTR(fname));

    return result;
}

int
rb_require_internal(VALUE fname, int safe)
{
    rb_execution_context_t *ec = GET_EC();
    return require_internal(ec, fname, safe, 1);
}

int
ruby_require_internal(const char *fname, unsigned int len)
{
    struct RString fake;
    VALUE str = rb_setup_fake_str(&fake, fname, len, 0);
    rb_execution_context_t *ec = GET_EC();
    int result = require_internal(ec, str, 0, 0);
    rb_set_errinfo(Qnil);
    return result == TAG_RETURN ? 1 : result ? -1 : 0;
}

VALUE
rb_require_safe(VALUE fname, int safe)
{
    rb_execution_context_t *ec = GET_EC();
    int result = require_internal(ec, fname, safe, 1);

    if (result > TAG_RETURN) {
        EC_JUMP_TAG(ec, result);
    }
    if (result < 0) {
	load_failed(fname);
    }

    return result ? Qtrue : Qfalse;
}

VALUE
rb_require(const char *fname)
{
    VALUE fn = rb_str_new_cstr(fname);
    return rb_require_safe(fn, rb_safe_level());
}

static int
register_init_ext(st_data_t *key, st_data_t *value, st_data_t init, int existing)
{
    const char *name = (char *)*key;
    if (existing) {
	/* already registered */
	rb_warn("%s is already registered", name);
    }
    else {
	*value = (st_data_t)MEMO_NEW(0, 0, init);
	*key = (st_data_t)ruby_strdup(name);
    }
    return ST_CONTINUE;
}

RUBY_FUNC_EXPORTED void
ruby_init_ext(const char *name, void (*init)(void))
{
    st_table *loading_tbl = get_loading_table();

    if (rb_provided(name))
	return;
    st_update(loading_tbl, (st_data_t)name, register_init_ext, (st_data_t)init);
}

/*
 *  call-seq:
 *     mod.autoload(module, filename)   -> nil
 *
 *  Registers _filename_ to be loaded (using Kernel::require)
 *  the first time that _module_ (which may be a String or
 *  a symbol) is accessed in the namespace of _mod_.
 *
 *     module A
 *     end
 *     A.autoload(:B, "b")
 *     A::B.doit            # autoloads "b"
 */

static VALUE
rb_mod_autoload(VALUE mod, VALUE sym, VALUE file)
{
    ID id = rb_to_id(sym);

    FilePathValue(file);
    rb_autoload_str(mod, id, file);
    return Qnil;
}

/*
 *  call-seq:
 *     mod.autoload?(name, inherit=true)   -> String or nil
 *
 *  Returns _filename_ to be loaded if _name_ is registered as
 *  +autoload+ in the namespace of _mod_ or one of its ancestors.
 *
 *     module A
 *     end
 *     A.autoload(:B, "b")
 *     A.autoload?(:B)            #=> "b"
 *
 *  If +inherit+ is false, the lookup only checks the autoloads in the receiver:
 *
 *     class A
 *       autoload :CONST, "const.rb"
 *     end
 *
 *     class B < A
 *     end
 *
 *     B.autoload?(:CONST)          #=> "const.rb", found in A (ancestor)
 *     B.autoload?(:CONST, false)   #=> nil, not found in B itself
 *
 */

static VALUE
rb_mod_autoload_p(int argc, VALUE *argv, VALUE mod)
{
    int recur = (rb_check_arity(argc, 1, 2) == 1) ? TRUE : RTEST(argv[1]);
    VALUE sym = argv[0];

    ID id = rb_check_id(&sym);
    if (!id) {
	return Qnil;
    }
    return rb_autoload_at_p(mod, id, recur);
}

/*
 *  call-seq:
 *     autoload(module, filename)   -> nil
 *
 *  Registers _filename_ to be loaded (using Kernel::require)
 *  the first time that _module_ (which may be a String or
 *  a symbol) is accessed.
 *
 *     autoload(:MyModule, "/usr/local/lib/modules/my_module.rb")
 */

static VALUE
rb_f_autoload(VALUE obj, VALUE sym, VALUE file)
{
    VALUE klass = rb_class_real(rb_vm_cbase());
    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "Can not set autoload on singleton class");
    }
    return rb_mod_autoload(klass, sym, file);
}

/*
 *  call-seq:
 *     autoload?(name, inherit=true)   -> String or nil
 *
 *  Returns _filename_ to be loaded if _name_ is registered as
 *  +autoload+.
 *
 *     autoload(:B, "b")
 *     autoload?(:B)            #=> "b"
 */

static VALUE
rb_f_autoload_p(int argc, VALUE *argv, VALUE obj)
{
    /* use rb_vm_cbase() as same as rb_f_autoload. */
    VALUE klass = rb_vm_cbase();
    if (NIL_P(klass)) {
	return Qnil;
    }
    return rb_mod_autoload_p(argc, argv, klass);
}

void
Init_load(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern2((str), strlen(str))
    rb_vm_t *vm = GET_VM();
    static const char var_load_path[] = "$:";
    ID id_load_path = rb_intern2(var_load_path, sizeof(var_load_path)-1);

    rb_define_hooked_variable(var_load_path, (VALUE*)vm, load_path_getter, rb_gvar_readonly_setter);
    rb_alias_variable(rb_intern("$-I"), id_load_path);
    rb_alias_variable(rb_intern("$LOAD_PATH"), id_load_path);
    vm->load_path = rb_ary_new();
    vm->expanded_load_path = rb_ary_tmp_new(0);
    vm->load_path_snapshot = rb_ary_tmp_new(0);
    vm->load_path_check_cache = 0;
    rb_define_singleton_method(vm->load_path, "resolve_feature_path", rb_resolve_feature_path, 1);

    rb_define_virtual_variable("$\"", get_LOADED_FEATURES, 0);
    rb_define_virtual_variable("$LOADED_FEATURES", get_LOADED_FEATURES, 0);
    vm->loaded_features = rb_ary_new();
    vm->loaded_features_snapshot = rb_ary_tmp_new(0);
    vm->loaded_features_index = st_init_numtable();

    rb_define_global_function("load", rb_f_load, -1);
    rb_define_global_function("require", rb_f_require, 1);
    rb_define_global_function("require_relative", rb_f_require_relative, 1);
    rb_define_method(rb_cModule, "autoload", rb_mod_autoload, 2);
    rb_define_method(rb_cModule, "autoload?", rb_mod_autoload_p, -1);
    rb_define_global_function("autoload", rb_f_autoload, 2);
    rb_define_global_function("autoload?", rb_f_autoload_p, -1);

    ruby_dln_librefs = rb_ary_tmp_new(0);
    rb_gc_register_mark_object(ruby_dln_librefs);
}
