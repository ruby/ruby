/*
 * load methods from eval.c
 */

#include "eval_intern.h"

extern VALUE ruby_top_self;

VALUE ruby_dln_librefs;

#define IS_SOEXT(e) (strcmp(e, ".so") == 0 || strcmp(e, ".o") == 0)
#ifdef DLEXT2
#define IS_DLEXT(e) (strcmp(e, DLEXT) == 0 || strcmp(e, DLEXT2) == 0)
#else
#define IS_DLEXT(e) (strcmp(e, DLEXT) == 0)
#endif


static const char *const loadable_ext[] = {
    ".rb", DLEXT,
#ifdef DLEXT2
    DLEXT2,
#endif
    0
};

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

static int
rb_feature_p(const char *feature, const char *ext, int rb)
{
    VALUE v, features;
    const char *f, *e;
    long i, len, elen;
    st_table *loading_tbl;

    if (ext) {
	len = ext - feature;
	elen = strlen(ext);
    }
    else {
	len = strlen(feature);
	elen = 0;
    }
    features = get_loaded_features();
    for (i = 0; i < RARRAY_LEN(features); ++i) {
	v = RARRAY_PTR(features)[i];
	f = StringValuePtr(v);
	if (RSTRING_LEN(v) < len || strncmp(f, feature, len) != 0)
	    continue;
	if (!*(e = f + len)) {
	    if (ext) continue;
	    return 'u';
	}
	if (*e != '.') continue;
	if ((!rb || !ext) && (IS_SOEXT(e) || IS_DLEXT(e))) {
	    return 's';
	}
	if ((rb || !ext) && (strcmp(e, ".rb") == 0)) {
	    return 'r';
	}
    }
    loading_tbl = get_loading_table();
    if (loading_tbl) {
	if (st_lookup(loading_tbl, (st_data_t)feature, 0)) {
	    if (!ext) return 'u';
	    return strcmp(ext, ".rb") ? 's' : 'r';
	}
	else {
	    char *buf;

	    if (ext && *ext) return 0;
	    buf = ALLOCA_N(char, len + DLEXT_MAXLEN + 1);
	    MEMCPY(buf, feature, char, len);
	    for (i = 0; (e = loadable_ext[i]) != 0; i++) {
		strncpy(buf + len, e, DLEXT_MAXLEN + 1);
		if (st_lookup(loading_tbl, (st_data_t)buf, 0)) {
		    return i ? 's' : 'r';
		}
	    }
	}
    }
    return 0;
}

int
rb_provided(const char *feature)
{
    const char *ext = strrchr(feature, '.');

    if (ext && !strchr(ext, '/')) {
	if (strcmp(".rb", ext) == 0) {
	    if (rb_feature_p(feature, ext, Qtrue)) return Qtrue;
	    return Qfalse;
	}
	else if (IS_SOEXT(ext) || IS_DLEXT(ext)) {
	    if (rb_feature_p(feature, ext, Qfalse)) return Qtrue;
	    return Qfalse;
	}
    }
    if (rb_feature_p(feature, feature + strlen(feature), Qtrue))
	return Qtrue;

    return Qfalse;
}

static void
rb_provide_feature(VALUE feature)
{
    rb_ary_push(get_loaded_features(), feature);
}

void
rb_provide(const char *feature)
{
    rb_provide_feature(rb_str_new2(feature));
}

VALUE rb_load_path;

NORETURN(static void load_failed _((VALUE)));

RUBY_EXTERN NODE *ruby_eval_tree;

static VALUE
rb_load_internal(char *file)
{
    NODE *node;
    VALUE iseq;
    rb_thread_t *th = GET_THREAD();

    {
	th->parse_in_eval++;
	node = (NODE *)rb_load_file(file);
	th->parse_in_eval--;
	node = ruby_eval_tree;
    }

    if (ruby_nerrs > 0) {
	return 0;
    }

    iseq = rb_iseq_new(node, rb_str_new2("<top (required)>"),
		       rb_str_new2(file), Qfalse, ISEQ_TYPE_TOP);

    rb_thread_eval(GET_THREAD(), iseq);
    return 0;
}

void
rb_load(VALUE fname, int wrap)
{
    VALUE tmp;
    int state;
    rb_thread_t *th = GET_THREAD();
    VALUE wrapper = th->top_wrapper;
    VALUE self = th->top_self;

    FilePathValue(fname);
    fname = rb_str_new4(fname);
    tmp = rb_find_file(fname);
    if (!tmp) {
	load_failed(fname);
    }
    fname = tmp;

    th->errinfo = Qnil; /* ensure */

    if (!wrap) {
	rb_secure(4);		/* should alter global state */
	th->top_wrapper = 0;
    }
    else {
	/* load in anonymous module as toplevel */
	th->top_self = rb_obj_clone(ruby_top_self);
	th->top_wrapper = rb_module_new();
	rb_extend_object(th->top_self, th->top_wrapper);
    }

    PUSH_TAG();
    state = EXEC_TAG();
    if (state == 0) {
	rb_load_internal(RSTRING_PTR(fname));
    }
    POP_TAG();

    th->top_self = self;
    th->top_wrapper = wrapper;

    if (ruby_nerrs > 0) {
	ruby_nerrs = 0;
	rb_exc_raise(GET_THREAD()->errinfo);
    }
    if (state) {
	th_jump_tag_but_local_jump(state, Qundef);
    }

    if (!NIL_P(GET_THREAD()->errinfo)) {
	/* exception during load */
	rb_exc_raise(th->errinfo);
    }
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
 *     load(filename, wrap=false)   => true
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
rb_f_load(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname, wrap;

    rb_scan_args(argc, argv, "11", &fname, &wrap);
    rb_load(fname, RTEST(wrap));
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
    rb_barrier_wait((VALUE)data);
    return 0;
}

static void
load_unlock(const char *ftptr)
{
    if (ftptr) {
	st_data_t key = (st_data_t)ftptr;
	st_data_t data;
	st_table *loading_tbl = get_loading_table();

	if (st_delete(loading_tbl, &key, &data)) {
	    free((char *)key);
	    rb_barrier_release((VALUE)data);
	}
    }
}


/*
 *  call-seq:
 *     require(string)    => true or false
 *  
 *  Ruby tries to load the library named _string_, returning
 *  +true+ if successful. If the filename does not resolve to
 *  an absolute path, it will be searched for in the directories listed
 *  in <code>$:</code>. If the file has the extension ``.rb'', it is
 *  loaded as a source file; if the extension is ``.so'', ``.o'', or
 *  ``.dll'', or whatever the default shared library extension is on
 *  the current platform, Ruby loads the shared library as a Ruby
 *  extension. Otherwise, Ruby tries adding ``.rb'', ``.so'', and so on
 *  to the name. The name of the loaded feature is added to the array in
 *  <code>$"</code>. A feature will not be loaded if it's name already
 *  appears in <code>$"</code>. However, the file name is not converted
 *  to an absolute path, so that ``<code>require 'a';require
 *  './a'</code>'' will load <code>a.rb</code> twice.
 *     
 *     require "my-library.rb"
 *     require "db-driver"
 */

VALUE
rb_f_require(VALUE obj, VALUE fname)
{
    return rb_require_safe(fname, rb_safe_level());
}

static int
search_required(VALUE fname, VALUE *path)
{
    VALUE tmp;
    char *ext, *ftptr;
    int type, ft = 0;

    *path = 0;
    ext = strrchr(ftptr = RSTRING_PTR(fname), '.');
    if (ext && !strchr(ext, '/')) {
	if (strcmp(".rb", ext) == 0) {
	    if (rb_feature_p(ftptr, ext, Qtrue))
		return 'r';
	    if (tmp = rb_find_file(fname)) {
		tmp = rb_file_expand_path(tmp, Qnil);
		ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
		if (!rb_feature_p(ftptr, ext, Qtrue))
		    *path = tmp;
		return 'r';
	    }
	    return 0;
	}
	else if (IS_SOEXT(ext)) {
	    if (rb_feature_p(ftptr, ext, Qfalse))
		return 's';
	    tmp = rb_str_new(RSTRING_PTR(fname), ext - RSTRING_PTR(fname));
#ifdef DLEXT2
	    OBJ_FREEZE(tmp);
	    if (rb_find_file_ext(&tmp, loadable_ext + 1)) {
		tmp = rb_file_expand_path(tmp, Qnil);
		ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
		if (!rb_feature_p(ftptr, ext, Qfalse))
		    *path = tmp;
		return 's';
	    }
#else
	    rb_str_cat2(tmp, DLEXT);
	    OBJ_FREEZE(tmp);
	    if (tmp = rb_find_file(tmp)) {
		tmp = rb_file_expand_path(tmp, Qnil);
		ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
		if (!rb_feature_p(ftptr, ext, Qfalse))
		    *path = tmp;
		return 's';
	    }
#endif
	}
	else if (IS_DLEXT(ext)) {
	    if (rb_feature_p(ftptr, ext, Qfalse))
		return 's';
	    if (tmp = rb_find_file(fname)) {
		tmp = rb_file_expand_path(tmp, Qnil);
		ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
		if (!rb_feature_p(ftptr, ext, Qfalse))
		    *path = tmp;
		return 's';
	    }
	}
    }
    else if ((ft = rb_feature_p(ftptr, 0, Qfalse)) == 'r') {
	return 'r';
    }
    tmp = fname;
    type = rb_find_file_ext(&tmp, loadable_ext);
    tmp = rb_file_expand_path(tmp, Qnil);
    switch (type) {
      case 0:
	ftptr = RSTRING_PTR(tmp);
	if (ft)
	    break;
	return rb_feature_p(ftptr, 0, Qfalse);

      default:
	if (ft)
	    break;
      case 1:
	ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
	if (rb_feature_p(ftptr, ext, !--type))
	    break;
	*path = tmp;
    }
    return type ? 's' : 'r';
}

static void
load_failed(VALUE fname)
{
    rb_raise(rb_eLoadError, "no such file to load -- %s",
	     RSTRING_PTR(fname));
}

static VALUE
load_ext(VALUE arg)
{
    SCOPE_SET(NOEX_PUBLIC);
    return (VALUE)dln_load((const char *)arg);
}

VALUE
rb_require_safe(VALUE fname, int safe)
{
    VALUE result = Qnil;
    rb_thread_t *th = GET_THREAD();
    volatile VALUE errinfo = th->errinfo;
    int state;
    struct {
	NODE *node;
	int safe;
    } volatile saved;
    char *volatile ftptr = 0;

    PUSH_TAG();
    saved.node = ruby_current_node;
    saved.safe = rb_safe_level();
    if ((state = EXEC_TAG()) == 0) {
	VALUE path;
	long handle;
	int found;

	rb_set_safe_level_force(safe);
	FilePathValue(fname);
	*(volatile VALUE *)&fname = rb_str_new4(fname);
	found = search_required(fname, &path);
	if (found) {
	    if (!path || !(ftptr = load_lock(RSTRING_PTR(path)))) {
		result = Qfalse;
	    }
	    else {
		rb_set_safe_level_force(0);
		switch (found) {
		  case 'r':
		    rb_load(path, 0);
		    break;

		  case 's':
		    ruby_current_node = 0;
		    ruby_sourcefile = rb_source_filename(RSTRING_PTR(path));
		    ruby_sourceline = 0;
		    handle = (long)rb_vm_call_cfunc(ruby_top_self, load_ext,
						    ruby_source_filename, 0, path);
		    rb_ary_push(ruby_dln_librefs, LONG2NUM(handle));
		    break;
		}
		rb_provide_feature(path);
		result = Qtrue;
	    }
	}
    }
    POP_TAG();
    load_unlock(ftptr);

    ruby_current_node = saved.node;
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

void
ruby_init_ext(const char *name, void (*init)(void))
{
    ruby_current_node = 0;
    ruby_sourcefile = rb_source_filename(name);
    ruby_sourceline = 0;
    if (load_lock(name)) {
	rb_vm_call_cfunc(ruby_top_self, init_ext_call, (VALUE)init, 0, rb_str_new2(name));
	rb_provide(name);
	load_unlock(name);
    }
}

/*
 *  call-seq:
 *     mod.autoload(name, filename)   => nil
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

    Check_SafeStr(file);
    rb_autoload(mod, id, RSTRING_PTR(file));
    return Qnil;
}

/*
 * MISSING: documentation
 */

static VALUE
rb_mod_autoload_p(VALUE mod, VALUE sym)
{
    return rb_autoload_p(mod, rb_to_id(sym));
}

/*
 *  call-seq:
 *     autoload(module, filename)   => nil
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
    VALUE klass = ruby_cbase();
    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "Can not set autoload on singleton class");
    }
    return rb_mod_autoload(klass, sym, file);
}

/*
 * MISSING: documentation
 */

static VALUE
rb_f_autoload_p(VALUE obj, VALUE sym)
{
    /* use ruby_cbase() as same as rb_f_autoload. */
    VALUE klass = ruby_cbase();
    if (NIL_P(klass)) {
	return Qnil;
    }
    return rb_mod_autoload_p(klass, sym);
}

void
Init_load()
{
    rb_define_readonly_variable("$:", &rb_load_path);
    rb_define_readonly_variable("$-I", &rb_load_path);
    rb_define_readonly_variable("$LOAD_PATH", &rb_load_path);
    rb_load_path = rb_ary_new();

    rb_define_virtual_variable("$\"", get_loaded_features, 0);
    rb_define_virtual_variable("$LOADED_FEATURES", get_loaded_features, 0);
    GET_VM()->loaded_features = rb_ary_new();

    rb_define_global_function("load", rb_f_load, -1);
    rb_define_global_function("require", rb_f_require, 1);
    rb_define_method(rb_cModule, "autoload", rb_mod_autoload, 2);
    rb_define_method(rb_cModule, "autoload?", rb_mod_autoload_p, 1);
    rb_define_global_function("autoload", rb_f_autoload, 2);
    rb_define_global_function("autoload?", rb_f_autoload_p, 1);

    ruby_dln_librefs = rb_ary_new();
    rb_register_mark_object(ruby_dln_librefs);
}
