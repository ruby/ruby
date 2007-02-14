/*
 * load methods from eval.c
 */

#include "eval_intern.h"

extern VALUE ruby_top_self;

VALUE ruby_dln_librefs;
static st_table *loading_tbl;

#define IS_SOEXT(e) (strcmp(e, ".so") == 0 || strcmp(e, ".o") == 0)
#ifdef DLEXT2
#define IS_DLEXT(e) (strcmp(e, DLEXT) == 0 || strcmp(e, DLEXT2) == 0)
#else
#define IS_DLEXT(e) (strcmp(e, DLEXT) == 0)
#endif

static VALUE
get_loaded_features(void)
{
    return GET_VM()->loaded_features;
}

static int
rb_feature_p(const char *feature, const char *ext, int rb)
{
    VALUE v;
    char *f, *e;
    long i, len, elen;

    if (ext) {
	len = ext - feature;
	elen = strlen(ext);
    }
    else {
	len = strlen(feature);
	elen = 0;
    }
    for (i = 0; i < RARRAY_LEN(get_loaded_features()); ++i) {
	v = RARRAY_PTR(get_loaded_features())[i];
	f = StringValuePtr(v);
	if (strncmp(f, feature, len) != 0)
	    continue;
	if (!*(e = f + len)) {
	    if (ext)
		continue;
	    return 'u';
	}
	if (*e != '.')
	    continue;
	if ((!rb || !ext) && (IS_SOEXT(e) || IS_DLEXT(e))) {
	    return 's';
	}
	if ((rb || !ext) && (strcmp(e, ".rb") == 0)) {
	    return 'r';
	}
    }
    return 0;
}

static const char *const loadable_ext[] = {
    ".rb", DLEXT,
#ifdef DLEXT2
    DLEXT2,
#endif
    0
};

static int search_required _((VALUE, VALUE *));

int
rb_provided(const char *feature)
{
    int i;
    char *buf;
    VALUE fname;

    if (rb_feature_p(feature, 0, Qfalse))
	return Qtrue;
    if (loading_tbl) {
	if (st_lookup(loading_tbl, (st_data_t) feature, 0))
	    return Qtrue;
	buf = ALLOCA_N(char, strlen(feature) + 8);
	strcpy(buf, feature);
	for (i = 0; loadable_ext[i]; i++) {
	    strcpy(buf + strlen(feature), loadable_ext[i]);
	    if (st_lookup(loading_tbl, (st_data_t) buf, 0))
		return Qtrue;
	}
    }
    if (search_required(rb_str_new2(feature), &fname)) {
	feature = RSTRING_PTR(fname);
	if (rb_feature_p(feature, 0, Qfalse))
	    return Qtrue;
	if (loading_tbl && st_lookup(loading_tbl, (st_data_t) feature, 0))
	    return Qtrue;
    }
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
    volatile VALUE self = ruby_top_self;

    FilePathValue(fname);
    fname = rb_str_new4(fname);
    tmp = rb_find_file(fname);
    if (!tmp) {
	load_failed(fname);
    }
    fname = tmp;

    GET_THREAD()->errinfo = Qnil;	/* ensure */
    
    if (!wrap) {
	rb_secure(4);		/* should alter global state */
    }
    else {
	/* load in anonymous module as toplevel */
	self = rb_obj_clone(ruby_top_self);
    }

    PUSH_TAG(PROT_NONE);
    state = EXEC_TAG();
    if (state == 0) {
	rb_load_internal(RSTRING_PTR(fname));
    }
    POP_TAG();

    if (ruby_nerrs > 0) {
	ruby_nerrs = 0;
	rb_exc_raise(GET_THREAD()->errinfo);
    }
    if (state) {
	th_jump_tag_but_local_jump(state, Qundef);
    }

    if (!NIL_P(GET_THREAD()->errinfo)) {
	/* exception during load */
	rb_exc_raise(GET_THREAD()->errinfo);
    }
}

void
rb_load_protect(VALUE fname, int wrap, int *state)
{
    int status;

    PUSH_THREAD_TAG();
    if ((status = EXEC_TAG()) == 0) {
	rb_load(fname, wrap);
    }
    POP_THREAD_TAG();
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

static int
load_wait(char *ftptr)
{
    st_data_t th;
    if (!loading_tbl) {
	return Qfalse;
    }
    if (!st_lookup(loading_tbl, (st_data_t) ftptr, &th)) {
	return Qfalse;
    }

    /* TODO: write wait routine */
    return Qtrue;
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

VALUE
rb_require_safe(VALUE fname, int safe)
{
    VALUE result = Qnil;
    volatile VALUE errinfo = GET_THREAD()->errinfo;
    rb_thread_t *th = GET_THREAD();
    int state;
    char *volatile ftptr = 0;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	VALUE path;
	long handle;
	int found;

	rb_set_safe_level_force(safe);
	FilePathValue(fname);
	*(volatile VALUE *)&fname = rb_str_new4(fname);
	found = search_required(fname, &path);
	if (found) {
	    if (!path || load_wait(RSTRING_PTR(path))) {
		result = Qfalse;
	    }
	    else {
		rb_set_safe_level_force(0);
		switch (found) {
		case 'r':
		    /* loading ruby library should be serialized. */
		    if (!loading_tbl) {
			loading_tbl = st_init_strtable();
		    }
		    /* partial state */
		    ftptr = ruby_strdup(RSTRING_PTR(path));
		    st_insert(loading_tbl, (st_data_t) ftptr,
			      (st_data_t) GET_THREAD()->self);
		    rb_load(path, 0);
		    break;

		case 's':
		    ruby_current_node = 0;
		    ruby_sourcefile = rb_source_filename(RSTRING_PTR(path));
		    ruby_sourceline = 0;
		    /* SCOPE_SET(NOEX_PUBLIC); */
		    handle = (long)dln_load(RSTRING_PTR(path));
		    rb_ary_push(ruby_dln_librefs, LONG2NUM(handle));
		    break;
		}
		rb_provide_feature(path);
		result = Qtrue;
	    }
	}
    }
    POP_TAG();

    if (ftptr) {
	if (st_delete(loading_tbl, (st_data_t *) & ftptr, 0)) {	/* loading done */
	    free(ftptr);
	}
    }
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
    rb_load_path = rb_ary_new();
    rb_define_readonly_variable("$:", &rb_load_path);
    rb_define_readonly_variable("$-I", &rb_load_path);
    rb_define_readonly_variable("$LOAD_PATH", &rb_load_path);

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
