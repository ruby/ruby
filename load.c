/*
 * load methods from eval.c
 */

#include "ruby/ruby.h"
#include "ruby/util.h"
#include "internal.h"
#include "dln.h"
#include "eval_intern.h"

VALUE ruby_dln_librefs;

#define IS_RBEXT(e) (strcmp((e), ".rb") == 0)
#define IS_SOEXT(e) (strcmp((e), ".so") == 0 || strcmp((e), ".o") == 0)
#ifdef DLEXT2
#define IS_DLEXT(e) (strcmp((e), DLEXT) == 0 || strcmp((e), DLEXT2) == 0)
#else
#define IS_DLEXT(e) (strcmp((e), DLEXT) == 0)
#endif

static int sorted_loaded_features = 1;

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

VALUE
rb_get_expanded_load_path(void)
{
    VALUE load_path = rb_get_load_path();
    VALUE ary;
    long i;

    ary = rb_ary_new2(RARRAY_LEN(load_path));
    for (i = 0; i < RARRAY_LEN(load_path); ++i) {
	VALUE path = rb_file_expand_path(RARRAY_PTR(load_path)[i], Qnil);
	rb_str_freeze(path);
	rb_ary_push(ary, path);
    }
    rb_obj_freeze(ary);
    return ary;
}

static VALUE
load_path_getter(ID id, rb_vm_t *vm)
{
    return vm->load_path;
}

static VALUE
get_loaded_features(void)
{
    return GET_VM()->loaded_features;
}

static st_table *
get_loading_table(void)
{
    return GET_VM()->loading_table;
}

static VALUE
loaded_feature_path(const char *name, long vlen, const char *feature, long len,
		    int type, VALUE load_path)
{
    long i;
    long plen;
    const char *e;

    if(vlen < len) return 0;
    if (!strncmp(name+(vlen-len),feature,len)){
	plen = vlen - len - 1;
    } else {
	for (e = name + vlen; name != e && *e != '.' && *e != '/'; --e);
	if (*e!='.' ||
	    e-name < len ||
	    strncmp(e-len,feature,len) )
	    return 0;
	plen = e - name - len - 1;
    }
    for (i = 0; i < RARRAY_LEN(load_path); ++i) {
	VALUE p = RARRAY_PTR(load_path)[i];
	const char *s = StringValuePtr(p);
	long n = RSTRING_LEN(p);

	if (n != plen ) continue;
	if (n && (strncmp(name, s, n) || name[n] != '/')) continue;
	switch (type) {
	  case 's':
	    if (IS_DLEXT(&name[n+len+1])) return p;
	    break;
	  case 'r':
	    if (IS_RBEXT(&name[n+len+1])) return p;
	    break;
	  default:
	    return p;
	}
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

static int rb_feature_first_equal_or_greater(VALUE, const char *, long);
static int rb_stop_search_feature(VALUE, const char *, long);

static int
rb_feature_p(const char *feature, const char *ext, int rb, int expanded, const char **fn)
{
    VALUE v, features, p, load_path = 0;
    const char *f, *e;
    long i, len, elen, n;
    st_table *loading_tbl;
    st_data_t data;
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
    i = rb_feature_first_equal_or_greater(features, feature, len);
    for (; i < RARRAY_LEN(features); ++i) {
	v = RARRAY_PTR(features)[i];
	if (rb_stop_search_feature(v, feature, len)) break;
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
    loading_tbl = get_loading_table();
    if (loading_tbl && loading_tbl->num_entries > 0) {
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
	    rb_str_resize(bufstr, 0);
	}
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
    volatile VALUE fullpath = 0;

    if (*feature == '.' &&
	(feature[1] == '/' || strncmp(feature+1, "./", 2) == 0)) {
	fullpath = rb_file_expand_path(rb_str_new2(feature), Qnil);
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
    return FALSE;
}

static int
feature_basename_length(const char *feature, long flen)
{
    if (sorted_loaded_features) {
	const char *ext = strrchr(feature, '.');
	return ext && !strchr(ext, '/') ? ext - feature : flen;
    } else {
	return 0;
    }
}

static int
compare_feature_name(const char *left, long llen, const char *right, long rlen)
{
    int diff = 0;
    while (llen-- && rlen--) {
	diff = left[llen] - right[rlen];
	if (diff) break;
	if (left[llen] == '/') break;
    }
    return diff;
}

static int
rb_compare_feature_name(VALUE loaded, const char *feature, long flen)
{
    const char *loaded_name = StringValuePtr(loaded);
    long loaded_len = feature_basename_length(loaded_name, RSTRING_LEN(loaded));
    return compare_feature_name(loaded_name, loaded_len, feature, flen);
}

/* used to find when equal features run out */
static int
rb_stop_search_feature(VALUE loaded, const char *feature, long flen)
{
    if (sorted_loaded_features)
	return rb_compare_feature_name(loaded, feature, flen) > 0;
    else
	return FALSE;
}

/* returns first position to search feature from */
static int
rb_feature_first_equal_or_greater(VALUE features, const char *feature, long flen)
{
    if (sorted_loaded_features) {
	int before = 0, first = RARRAY_LEN(features);
	VALUE *values = RARRAY_PTR(features);
	if (first == 0)
	    return 0;
	if (rb_compare_feature_name(values[0], feature, flen) >= 0)
	    return 0;

	while (first - before > 1) {
	    int mid = (first + before) / 2;
	    int cmp = rb_compare_feature_name(values[mid], feature, flen);
	    if (cmp >= 0)
		first = mid;
	    else
		before = mid;
	}
	return first;
    } else {
	return 0;
    }
}

/* returns position to insert new feature in */
static int
rb_feature_first_greater(VALUE features, const char *feature, long flen)
{
    if (sorted_loaded_features) {
	int before = 0, first = RARRAY_LEN(features);
	VALUE *values = RARRAY_PTR(features);
	if (first == 0)
	    return 0;
	if (rb_compare_feature_name(values[0], feature, flen) > 0)
	    return 0;
	if (rb_compare_feature_name(values[first-1], feature, flen) <= 0)
	    return first;

	while (first - before > 1) {
	    int mid = (first + before) / 2;
	    int cmp = rb_compare_feature_name(values[mid], feature, flen);
	    if (cmp > 0)
		first = mid;
	    else
		before = mid;
	}
	return first;
    } else {
	return RARRAY_LEN(features);
    }
}


static VALUE
rb_push_feature_1(VALUE features, VALUE feature)
{
    const char *fname = StringValuePtr(feature);
    long flen = feature_basename_length(fname, RSTRING_LEN(feature));
    int i = rb_feature_first_greater(features, fname, flen);
    rb_ary_push(features, feature);
    if ( i < RARRAY_LEN(features) - 1 ) {
	MEMMOVE(RARRAY_PTR(features) + i + 1, RARRAY_PTR(features) + i,
		VALUE, RARRAY_LEN(features) - i - 1);
	RARRAY_PTR(features)[i] = feature;
    }
    return features;
}

static VALUE
rb_push_feature_m(int argc, VALUE *argv, VALUE features)
{
    while (argc--) {
	rb_push_feature_1(features, *argv++);
    }
    return features;
}

static VALUE
rb_concat_features(VALUE features, VALUE add)
{
    add = rb_convert_type(add, T_ARRAY, "Array", "to_ary");
    if (RARRAY_LEN(add)) {
	rb_push_feature_m(RARRAY_LEN(add), RARRAY_PTR(add), features);
    }
    return features;
}
static const char *load_features_undefined_methods[] = {
    "[]=", "reverse!", "rotate!", "sort!", "sort_by!",
    "collect!", "map!", "shuffle!", "fill", "insert",
    NULL
};

static VALUE
rb_loaded_features_init(void)
{
    char *sorted_flag;
    const char **name;
    VALUE loaded_features = rb_ary_new();
    VALUE loaded_features_c = rb_singleton_class(loaded_features);

    sorted_flag = getenv("RUBY_LOADED_FEATURES_SORTED");
    if (sorted_flag != NULL) {
	int sorted_set = atoi(sorted_flag);
	if (RTEST(ruby_verbose))
	    fprintf(stderr, "sorted_loaded_features=%d (%d)\n", sorted_set, sorted_loaded_features);
	sorted_loaded_features = sorted_set;
    }

    for(name = load_features_undefined_methods; *name; name++) {
	rb_undef_method(loaded_features_c, *name);
    }

    if (sorted_loaded_features) {
	rb_define_method(loaded_features_c, "<<", rb_push_feature_1, 1);
	rb_define_method(loaded_features_c, "push", rb_push_feature_m, -1);
	rb_define_method(loaded_features_c, "concat", rb_concat_features, 1);
	rb_define_method(loaded_features_c, "unshift", rb_push_feature_m, -1);
    }
    return loaded_features;
}

static void
rb_provide_feature(VALUE feature)
{
    if (OBJ_FROZEN(get_loaded_features())) {
	rb_raise(rb_eRuntimeError,
		 "$LOADED_FEATURES is frozen; cannot append feature");
    }
    rb_push_feature_1(get_loaded_features(), feature);
}

void
rb_provide(const char *feature)
{
    rb_provide_feature(rb_usascii_str_new2(feature));
}

NORETURN(static void load_failed(VALUE));

static void
rb_load_internal(VALUE fname, int wrap)
{
    int state;
    rb_thread_t *th = GET_THREAD();
    volatile VALUE wrapper = th->top_wrapper;
    volatile VALUE self = th->top_self;
    volatile int loaded = FALSE;
    volatile int mild_compile_error;
#ifndef __GNUC__
    rb_thread_t *volatile th0 = th;
#endif

    th->errinfo = Qnil; /* ensure */

    if (!wrap) {
	rb_secure(4);		/* should alter global state */
	th->top_wrapper = 0;
    }
    else {
	/* load in anonymous module as toplevel */
	th->top_self = rb_obj_clone(rb_vm_top_self());
	th->top_wrapper = rb_module_new();
	rb_extend_object(th->top_self, th->top_wrapper);
    }

    mild_compile_error = th->mild_compile_error;
    PUSH_TAG();
    state = EXEC_TAG();
    if (state == 0) {
	NODE *node;
	VALUE iseq;

	th->mild_compile_error++;
	node = (NODE *)rb_load_file(RSTRING_PTR(fname));
	loaded = TRUE;
	iseq = rb_iseq_new_top(node, rb_str_new2("<top (required)>"), fname, rb_realpath_internal(Qnil, fname, 1), Qfalse);
	th->mild_compile_error--;
	rb_iseq_eval(iseq);
    }
    POP_TAG();

#ifndef __GNUC__
    th = th0;
    fname = RB_GC_GUARD(fname);
#endif
    th->mild_compile_error = mild_compile_error;
    th->top_self = self;
    th->top_wrapper = wrapper;

    if (!loaded) {
	rb_exc_raise(GET_THREAD()->errinfo);
    }
    if (state) {
	rb_vm_jump_tag_but_local_jump(state, Qundef);
    }

    if (!NIL_P(GET_THREAD()->errinfo)) {
	/* exception during load */
	rb_exc_raise(th->errinfo);
    }
}

void
rb_load(VALUE fname, int wrap)
{
    VALUE tmp = rb_find_file(FilePathValue(fname));
    if (!tmp) load_failed(fname);
    rb_load_internal(tmp, wrap);
}

void
rb_load_protect(VALUE fname, int wrap, int *state)
{
    int status;

    PUSH_TAG();
    if ((status = EXEC_TAG()) == 0) {
	rb_load(fname, wrap);
    }
    POP_TAG();
    if (state)
	*state = status;
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
rb_f_load(int argc, VALUE *argv)
{
    VALUE fname, wrap, path;

    rb_scan_args(argc, argv, "11", &fname, &wrap);
    path = rb_find_file(FilePathValue(fname));
    if (!path) {
	if (!rb_file_load_ok(RSTRING_PTR(fname)))
	    load_failed(fname);
	path = fname;
    }
    rb_load_internal(path, RTEST(wrap));
    return Qtrue;
}

static char *
load_lock(const char *ftptr)
{
    st_data_t data;
    st_table *loading_tbl = get_loading_table();

    if (!loading_tbl || !st_lookup(loading_tbl, (st_data_t)ftptr, &data)) {
	/* loading ruby library should be serialized. */
	if (!loading_tbl) {
	    GET_VM()->loading_table = loading_tbl = st_init_strtable();
	}
	/* partial state */
	ftptr = ruby_strdup(ftptr);
	data = (st_data_t)rb_barrier_new();
	st_insert(loading_tbl, (st_data_t)ftptr, data);
	return (char *)ftptr;
    }
    if (RTEST(ruby_verbose)) {
	rb_warning("loading in progress, circular require considered harmful - %s", ftptr);
	rb_backtrace();
    }
    switch (rb_barrier_wait((VALUE)data)) {
      case Qfalse:
	data = (st_data_t)ftptr;
	st_delete(loading_tbl, &data, 0);
	return 0;
      case Qnil:
	return 0;
    }
    return (char *)ftptr;
}

static int
release_barrier(st_data_t key, st_data_t *value, st_data_t done)
{
    VALUE barrier = (VALUE)*value;
    if (done ? rb_barrier_destroy(barrier) : rb_barrier_release(barrier)) {
	/* still in-use */
	return ST_CONTINUE;
    }
    xfree((char *)key);
    return ST_DELETE;
}

static void
load_unlock(const char *ftptr, int done)
{
    if (ftptr) {
	st_data_t key = (st_data_t)ftptr;
	st_table *loading_tbl = get_loading_table();

	st_update(loading_tbl, key, release_barrier, done);
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
	rb_raise(rb_eLoadError, "cannot infer basepath");
    }
    base = rb_file_dirname(base);
    return rb_require_safe(rb_file_absolute_path(fname, base), rb_safe_level());
}

static int
search_required(VALUE fname, volatile VALUE *path, int safe_level)
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
		if (loading) *path = rb_str_new2(loading);
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
		if (loading) *path = rb_str_new2(loading);
		return 's';
	    }
	    tmp = rb_str_new(RSTRING_PTR(fname), ext - RSTRING_PTR(fname));
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
		if (loading) *path = rb_str_new2(loading);
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
	if (loading) *path = rb_str_new2(loading);
	return 'r';
    }
    tmp = fname;
    type = rb_find_file_ext_safe(&tmp, loadable_ext, safe_level);
    switch (type) {
      case 0:
	if (ft)
	    break;
	ftptr = RSTRING_PTR(tmp);
	return rb_feature_p(ftptr, 0, FALSE, TRUE, 0);

      default:
	if (ft)
	    break;
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
    VALUE mesg = rb_str_buf_new_cstr("cannot load such file -- ");
    rb_str_append(mesg, fname);	/* should be ASCII compatible */
    rb_exc_raise(rb_exc_new3(rb_eLoadError, mesg));
}

static VALUE
load_ext(VALUE path)
{
    SCOPE_SET(NOEX_PUBLIC);
    return (VALUE)dln_load(RSTRING_PTR(path));
}

VALUE
rb_require_safe(VALUE fname, int safe)
{
    volatile VALUE result = Qnil;
    rb_thread_t *th = GET_THREAD();
    volatile VALUE errinfo = th->errinfo;
    int state;
    struct {
	int safe;
    } volatile saved;
    char *volatile ftptr = 0;

    PUSH_TAG();
    saved.safe = rb_safe_level();
    if ((state = EXEC_TAG()) == 0) {
	VALUE path;
	long handle;
	int found;

	rb_set_safe_level_force(safe);
	FilePathValue(fname);
	rb_set_safe_level_force(0);
	found = search_required(fname, &path, safe);
	if (found) {
	    if (!path || !(ftptr = load_lock(RSTRING_PTR(path)))) {
		result = Qfalse;
	    }
	    else {
		switch (found) {
		  case 'r':
		    rb_load_internal(path, 0);
		    break;

		  case 's':
		    handle = (long)rb_vm_call_cfunc(rb_vm_top_self(), load_ext,
						    path, 0, path);
		    rb_ary_push(ruby_dln_librefs, LONG2NUM(handle));
		    break;
		}
		rb_provide_feature(path);
		result = Qtrue;
	    }
	}
    }
    POP_TAG();
    load_unlock(ftptr, !state);

    rb_set_safe_level_force(saved.safe);
    if (state) {
	JUMP_TAG(state);
    }

    if (NIL_P(result)) {
	load_failed(fname);
    }

    th->errinfo = errinfo;

    return result;
}

VALUE
rb_require(const char *fname)
{
    VALUE fn = rb_str_new2(fname);
    OBJ_FREEZE(fn);
    return rb_require_safe(fn, rb_safe_level());
}

static VALUE
init_ext_call(VALUE arg)
{
    SCOPE_SET(NOEX_PUBLIC);
    (*(void (*)(void))arg)();
    return Qnil;
}

RUBY_FUNC_EXPORTED void
ruby_init_ext(const char *name, void (*init)(void))
{
    if (load_lock(name)) {
	rb_vm_call_cfunc(rb_vm_top_self(), init_ext_call, (VALUE)init,
			 0, rb_str_new2(name));
	rb_provide(name);
	load_unlock(name, 1);
    }
}

/*
 *  call-seq:
 *     mod.autoload(module, filename)   -> nil
 *
 *  Registers _filename_ to be loaded (using <code>Kernel::require</code>)
 *  the first time that _module_ (which may be a <code>String</code> or
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
    rb_autoload(mod, id, RSTRING_PTR(file));
    return Qnil;
}

/*
 *  call-seq:
 *     mod.autoload?(name)   -> String or nil
 *
 *  Returns _filename_ to be loaded if _name_ is registered as
 *  +autoload+ in the namespace of _mod_.
 *
 *     module A
 *     end
 *     A.autoload(:B, "b")
 *     A.autoload?(:B)            #=> "b"
 */

static VALUE
rb_mod_autoload_p(VALUE mod, VALUE sym)
{
    ID id = rb_check_id(&sym);
    if (!id) {
	return Qnil;
    }
    return rb_autoload_p(mod, id);
}

/*
 *  call-seq:
 *     autoload(module, filename)   -> nil
 *
 *  Registers _filename_ to be loaded (using <code>Kernel::require</code>)
 *  the first time that _module_ (which may be a <code>String</code> or
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
 *     autoload?(name)   -> String or nil
 *
 *  Returns _filename_ to be loaded if _name_ is registered as
 *  +autoload+.
 *
 *     autoload(:B, "b")
 *     autoload?(:B)            #=> "b"
 */

static VALUE
rb_f_autoload_p(VALUE obj, VALUE sym)
{
    /* use rb_vm_cbase() as same as rb_f_autoload. */
    VALUE klass = rb_vm_cbase();
    if (NIL_P(klass)) {
	return Qnil;
    }
    return rb_mod_autoload_p(klass, sym);
}

void
Init_load()
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

    rb_define_virtual_variable("$\"", get_loaded_features, 0);
    rb_define_virtual_variable("$LOADED_FEATURES", get_loaded_features, 0);
    vm->loaded_features = rb_loaded_features_init();

    rb_define_global_function("load", rb_f_load, -1);
    rb_define_global_function("require", rb_f_require, 1);
    rb_define_global_function("require_relative", rb_f_require_relative, 1);
    rb_define_method(rb_cModule, "autoload", rb_mod_autoload, 2);
    rb_define_method(rb_cModule, "autoload?", rb_mod_autoload_p, 1);
    rb_define_global_function("autoload", rb_f_autoload, 2);
    rb_define_global_function("autoload?", rb_f_autoload_p, 1);

    ruby_dln_librefs = rb_ary_new();
    rb_gc_register_mark_object(ruby_dln_librefs);
}
