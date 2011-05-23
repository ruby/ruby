/*
 * load methods from eval.c
 */

#include "ruby/ruby.h"
#include "ruby/util.h"
#include "dln.h"
#include "eval_intern.h"

VALUE ruby_dln_librefs;

#if CASEFOLD_FILESYSTEM
#define fncomp strcasecmp
#define fnncomp strncasecmp
#else
#define fncomp strcmp
#define fnncomp strncmp
#endif

#define IS_RBEXT(e) (fncomp((e), ".rb") == 0)
#define IS_SOEXT(e) (fncomp((e), ".so") == 0 || fncomp((e), ".o") == 0)
#ifdef DLEXT2
#define IS_DLEXT(e) (fncomp((e), DLEXT) == 0 || fncomp((e), DLEXT2) == 0)
#else
#define IS_DLEXT(e) (fncomp((e), DLEXT) == 0)
#endif


VALUE rb_f_require_2(VALUE, VALUE);
VALUE rb_f_require_relative_2(VALUE, VALUE fname);
VALUE rb_require_safe_2(VALUE, int);
static int rb_file_has_been_required(VALUE);
static int rb_file_is_ruby(VALUE);
static st_table * get_loaded_features_hash(void);
static void rb_load_internal(VALUE, int);
static char * load_lock(const char *);
static void load_unlock(const char *, int);
static void load_failed(VALUE fname);

static VALUE rb_locate_file(VALUE);
static VALUE rb_locate_file_absolute(VALUE);
static VALUE rb_locate_file_relative(VALUE);
static VALUE rb_locate_file_in_load_path(VALUE);
static VALUE rb_locate_file_with_extensions(VALUE);
static int rb_path_is_absolute(VALUE);
static int rb_path_is_relative(VALUE);
VALUE rb_get_expanded_load_path();

static VALUE rb_cLoadedFeaturesProxy;
static void rb_rehash_loaded_features();
static VALUE rb_loaded_features_hook(int, VALUE*, VALUE);
static void define_loaded_features_proxy();

VALUE ary_new(VALUE, long); // array.c

static const char *const loadable_ext[] = {
    ".rb", 
    DLEXT,
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

static st_table *
get_loaded_features_hash(void)
{
    st_table* loaded_features_hash;
    loaded_features_hash = GET_VM()->loaded_features_hash;

    if (!loaded_features_hash) {
      GET_VM()->loaded_features_hash = loaded_features_hash = st_init_strcasetable();
    }

    return loaded_features_hash;
}

static st_table *
get_filename_expansion_hash(void)
{
    st_table* filename_expansion_hash;
    filename_expansion_hash = GET_VM()->filename_expansion_hash;

    if (!filename_expansion_hash) {
      GET_VM()->filename_expansion_hash = filename_expansion_hash = st_init_strcasetable();
    }

    return filename_expansion_hash;
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

int
rb_provided(const char *feature)
{
    return rb_feature_provided(feature, 0);
}


	static void
rb_provide_feature(VALUE feature)
{
	int frozen = 0;
	st_table* loaded_features_hash;

	if (OBJ_FROZEN(get_loaded_features())) {
		rb_raise(rb_eRuntimeError,
				"$LOADED_FEATURES is frozen; cannot append feature");
	}

	loaded_features_hash = get_loaded_features_hash();
	st_insert(
			loaded_features_hash,
			(st_data_t)ruby_strdup(RSTRING_PTR(feature)),
			(st_data_t)rb_barrier_new());

	rb_ary_push(get_loaded_features(), feature);
}

void
rb_provide(const char *feature)
{
    rb_provide_feature(rb_usascii_str_new2(feature));
}

NORETURN(static void load_failed(VALUE));
VALUE rb_realpath_internal(VALUE basedir, VALUE path, int strict);

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
	    GET_VM()->loading_table = loading_tbl =
		(CASEFOLD_FILESYSTEM ? st_init_strcasetable() : st_init_strtable());
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
    return RTEST(rb_barrier_wait((VALUE)data)) ? (char *)ftptr : 0;
}

static void
load_unlock(const char *ftptr, int done)
{
    if (ftptr) {
	st_data_t key = (st_data_t)ftptr;
	st_data_t data;
	st_table *loading_tbl = get_loading_table();

	if (st_delete(loading_tbl, &key, &data)) {
	    VALUE barrier = (VALUE)data;
	    xfree((char *)key);
	    if (done)
		rb_barrier_destroy(barrier);
	    else
		rb_barrier_release(barrier);
	}
    }
}


/*
 *  call-seq:
 *     require(string)    -> true or false
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
 *  <code>$"</code>. A feature will not be loaded if its name already
 *  appears in <code>$"</code>. The file name is converted to an absolute
 *  path, so ``<code>require 'a'; require './a'</code>'' will not load
 *  <code>a.rb</code> twice.
 *
 *     require "my-library.rb"
 *     require "db-driver"
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
    VALUE rb_current_realfilepath(void);
    VALUE base = rb_current_realfilepath();
    if (NIL_P(base)) {
	rb_raise(rb_eLoadError, "cannot infer basepath");
    }
    base = rb_file_dirname(base);
    return rb_require_safe(rb_file_absolute_path(fname, base), rb_safe_level());
}

VALUE
rb_f_require_relative_2(VALUE obj, VALUE fname)
{
    VALUE rb_current_realfilepath(void);
    VALUE base = rb_current_realfilepath();
    if (NIL_P(base)) {
	rb_raise(rb_eLoadError, "cannot infer basepath");
    }
    base = rb_file_dirname(base);
    return (rb_require_safe_2(rb_file_absolute_path(fname, base), rb_safe_level()) == Qnil) ? Qfalse : Qtrue;
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
   return rb_require_safe_2(fname, safe); 
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
    return rb_autoload_p(mod, rb_to_id(sym));
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
    VALUE klass = rb_vm_cbase();
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

VALUE
rb_file_exist_p(VALUE obj, VALUE path);

static int
rb_feature_exists(VALUE expanded_path)
{
  return rb_funcall(rb_cFile, rb_intern("file?"), 1, expanded_path) == Qtrue;
}

const char *available_extensions[] = {
  ".rb",
  DLEXT,
#ifdef DLEXT2
  DLEXT2,
#endif
  ""
};

#ifdef DLEXT2
VALUE available_ext_rb_str[4];
#else
VALUE available_ext_rb_str[3];
#endif

const char *alternate_dl_extensions[] = {
  DLEXT,
#ifdef DLEXT2
  DLEXT2
#endif
};

#define CHAR_ARRAY_LEN(array) sizeof(array) / sizeof(char*)
#define VALUE_ARRAY_LEN(array) sizeof(array) / sizeof(VALUE)

// TODO: Optimize this function, it gets called heaps. Do far less in ruby.
static VALUE
rb_locate_file_with_extensions(VALUE base_file_name) {
	unsigned int j;
	VALUE file_name_with_extension;
	VALUE extension;
	VALUE directory, basename;

	extension = rb_funcall(rb_cFile, rb_intern("extname"), 1, base_file_name);

	if (RSTRING_LEN(extension) == 0) {
		for (j = 0; j < VALUE_ARRAY_LEN(available_ext_rb_str); ++j) {
			file_name_with_extension = rb_str_plus(
					base_file_name,
					available_ext_rb_str[j]);

			if (rb_feature_exists(file_name_with_extension)) {
				return file_name_with_extension;
			}
		}
	} else {
		if (rb_feature_exists(base_file_name)) {
			return base_file_name;
		} else {
			if (IS_SOEXT(RSTRING_PTR(extension))) {
				// Try loading the native DLEXT version of this platform.
				// This allows 'pathname.so' to require 'pathname.bundle' on OSX
				for (j = 0; j < CHAR_ARRAY_LEN(alternate_dl_extensions); ++j) {
					directory = rb_funcall(rb_cFile, rb_intern("dirname"), 1, 
							base_file_name);
					basename  = rb_funcall(rb_cFile, rb_intern("basename"), 2, 
							base_file_name, extension);
					basename  = rb_funcall(basename, rb_intern("+"), 1, 
							rb_str_new2(alternate_dl_extensions[j]));

					file_name_with_extension = rb_funcall(rb_cFile, rb_intern("join"), 2, 
							directory, basename);

					if (rb_feature_exists(file_name_with_extension)) {
						return file_name_with_extension;
					}
				}
			}
		}
	}
	return Qnil;
}

static VALUE
rb_locate_file_absolute(VALUE fname)
{
	return rb_locate_file_with_extensions(fname);
}

static VALUE
rb_locate_file_relative(VALUE fname)
{
	return rb_locate_file_with_extensions(rb_file_expand_path(fname, Qnil));
}

static VALUE
rb_locate_file_in_load_path(VALUE path)
{
	long i, j;
	VALUE load_path = rb_get_expanded_load_path();
	VALUE expanded_file_name = Qnil;
	VALUE base_file_name = Qnil;
	VALUE sep = rb_str_new2("/");

	for (i = 0; i < RARRAY_LEN(load_path); ++i) {
		VALUE directory = RARRAY_PTR(load_path)[i];

		base_file_name = rb_str_plus(directory, sep);
		base_file_name = rb_str_concat(base_file_name, path);

		expanded_file_name = rb_locate_file_with_extensions(base_file_name);

		if (expanded_file_name != Qnil) {
			return expanded_file_name;
		}
	}
	return Qnil;
}

static int
rb_path_is_relative(VALUE path)
{
	const char * path_ptr = RSTRING_PTR(path);
	const char * current_directory = "./";
	const char * parent_directory  = "../";

	return (
			strncmp(current_directory, path_ptr, 2) == 0 ||
			strncmp(parent_directory,  path_ptr, 3) == 0
		   );
}

static int
rb_file_is_ruby(VALUE path)
{
	const char * ext;
	ext = ruby_find_extname(RSTRING_PTR(path), 0);

	return ext && IS_RBEXT(ext);
}

static int
rb_path_is_absolute(VALUE path)
{
	// Delegate to file.c
	return rb_is_absolute_path(RSTRING_PTR(path));
}

static int
rb_file_has_been_required(VALUE expanded_path)
{
	st_data_t data;
	st_data_t path_key = (st_data_t)RSTRING_PTR(expanded_path);
	st_table *loaded_features_hash = get_loaded_features_hash();

	return st_lookup(loaded_features_hash, path_key, &data);
}

static VALUE
rb_get_cached_expansion(VALUE filename) 
{
	st_data_t data;
	st_data_t path_key = (st_data_t)RSTRING_PTR(filename);
	st_table *filename_expansion_hash = get_filename_expansion_hash();

	if (st_lookup(filename_expansion_hash, path_key, &data)) {
		return (VALUE)data;
	} else {
		return Qnil;
	};
}

static void
rb_set_cached_expansion(VALUE filename, VALUE expanded)
{
	st_data_t data = (st_data_t)expanded;
	st_data_t path_key = (st_data_t)RSTRING_PTR(filename);
	st_table *filename_expansion_hash = get_filename_expansion_hash();

	st_insert(filename_expansion_hash, path_key, data);
}

static VALUE
rb_locate_file(VALUE filename)
{
	VALUE full_path = Qnil;

	full_path = rb_get_cached_expansion(filename);

	if (full_path != Qnil)
		return full_path;

	if (rb_path_is_relative(filename)) {
		full_path = rb_locate_file_relative(filename);
	} else if (rb_path_is_absolute(filename)) {
		full_path = rb_locate_file_absolute(filename);
	} else {
		full_path = rb_locate_file_in_load_path(filename);
	}

	if (full_path != Qnil)
		rb_set_cached_expansion(filename, full_path);

	return full_path;
}

/* 
 * returns the path loaded, or nil if the file was already loaded. Raises
 * LoadError if a file cannot be found. 
 */
VALUE
rb_require_safe_2(VALUE fname, int safe)
{
	VALUE path = Qnil;
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
		long handle;
		int found;

		rb_set_safe_level_force(safe);
		FilePathValue(fname);
		rb_set_safe_level_force(0);

		path = rb_locate_file(fname);

		if (safe >= 1 && OBJ_TAINTED(path)) {
			rb_raise(rb_eSecurityError, "Loading from unsafe file %s", RSTRING_PTR(path));
		}

		result = Qfalse;
		if (path == Qnil) {
			load_failed(fname);
		} else {
			if (ftptr = load_lock(RSTRING_PTR(path))) { // Allows circular requires to work
				if (!rb_file_has_been_required(path)) {
					if (rb_file_is_ruby(path)) {
						rb_load_internal(path, 0);
					} else {
						handle = (long)rb_vm_call_cfunc(rb_vm_top_self(), load_ext,
								path, 0, path);
						rb_ary_push(ruby_dln_librefs, LONG2NUM(handle));
					}
					rb_provide_feature(path);
					result = Qtrue;
				}
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

	if (result == Qtrue) {
		return path;
	} else {
		return Qnil;
	}
}

VALUE
rb_f_require_2(VALUE obj, VALUE fname)
{
    return rb_require_safe_2(fname, rb_safe_level()) == Qnil ? Qfalse : Qtrue;
}

static void
rb_rehash_loaded_features()
{
  int i;
  VALUE features;
  VALUE feature;

  st_table* loaded_features_hash = get_loaded_features_hash();

  st_clear(loaded_features_hash);

  features = get_loaded_features();

  for (i = 0; i < RARRAY_LEN(features); ++i) {
    feature = RARRAY_PTR(features)[i];
    st_insert(
      loaded_features_hash,
      (st_data_t)ruby_strdup(RSTRING_PTR(feature)),
      (st_data_t)rb_barrier_new());
  }
}

static void
rb_clear_cached_expansions()
{
  st_table* filename_expansion_hash = get_filename_expansion_hash();
  st_clear(filename_expansion_hash);
}

static VALUE  
rb_loaded_features_hook(int argc, VALUE *argv, VALUE self)  
{ 
	VALUE ret;
	ret = rb_call_super(argc, argv);
	rb_rehash_loaded_features();
	rb_clear_cached_expansions();
	return ret;
}

/*
 * $LOADED_FEATURES is exposed publically as an array, but under the covers
 * we also store this data in a hash for fast lookups. So that we can rebuild
 * the hash whenever $LOADED_FEATURES is changed, we wrap the Array class
 * in a proxy that intercepts all data-modifying methods and rebuilds the
 * hash.
 *
 * Note that the list of intercepted methods is currently non-comprehensive
 * --- it only covers modifications made by the ruby and rubyspec test suites.
 */
static void 
define_loaded_features_proxy()
{
	const char* methods_to_hook[] = {"push", "clear", "replace", "delete"};
	unsigned int i;

	rb_cLoadedFeaturesProxy = rb_define_class("LoadedFeaturesProxy", rb_cArray); 
	for (i = 0; i < CHAR_ARRAY_LEN(methods_to_hook); ++i) {
		rb_define_method(
				rb_cLoadedFeaturesProxy,
				methods_to_hook[i],
				rb_loaded_features_hook,
				-1);
	}
}

static int
rb_file_is_being_required(VALUE full_path) {
	const char *ftptr = RSTRING_PTR(full_path);
	st_data_t data;
	st_table *loading_tbl = get_loading_table();

	return (loading_tbl && st_lookup(loading_tbl, (st_data_t)ftptr, &data));
}


/* Should return true if the file has or is being loaded, but should 
 * not actually load the file.
 */
int
rb_feature_provided_2(VALUE fname)
{
	VALUE full_path = rb_locate_file(fname);

	if (rb_file_has_been_required(full_path) || rb_file_is_being_required(full_path)) {
		return TRUE;
	} else {
		return FALSE;
	}
}

/*
 * Deprecated, use rb_feature_provided_2
 */
int
rb_feature_provided(const char *feature, const char **loading)
{
    VALUE fname = rb_str_new2(feature);
	rb_feature_provided_2(fname);
}


void
Init_load()
{
#undef rb_intern
#define rb_intern(str) rb_intern2((str), strlen(str))
	unsigned int j;
    rb_vm_t *vm = GET_VM();
    static const char var_load_path[] = "$:";
    ID id_load_path = rb_intern2(var_load_path, sizeof(var_load_path)-1);

    rb_define_hooked_variable(var_load_path, (VALUE*)vm, load_path_getter, rb_gvar_readonly_setter);
    rb_alias_variable(rb_intern("$-I"), id_load_path);
    rb_alias_variable(rb_intern("$LOAD_PATH"), id_load_path);
    vm->load_path = rb_ary_new();

    rb_define_virtual_variable("$\"", get_loaded_features, 0);
    rb_define_virtual_variable("$LOADED_FEATURES", get_loaded_features, 0);

    define_loaded_features_proxy();

    vm->loaded_features = ary_new(rb_cLoadedFeaturesProxy, RARRAY_EMBED_LEN_MAX);

    rb_define_global_function("load", rb_f_load, -1);
    rb_define_global_function("require", rb_f_require_2, 1);
    rb_define_global_function("require_2", rb_f_require_2, 1);
    rb_define_global_function("require_relative", rb_f_require_relative_2, 1);
    rb_define_global_function("require_relative_2", rb_f_require_relative_2, 1);
    rb_define_method(rb_cModule, "autoload", rb_mod_autoload, 2);
    rb_define_method(rb_cModule, "autoload?", rb_mod_autoload_p, 1);
    rb_define_global_function("autoload", rb_f_autoload, 2);
    rb_define_global_function("autoload?", rb_f_autoload_p, 1);

    ruby_dln_librefs = rb_ary_new();
    rb_gc_register_mark_object(ruby_dln_librefs);

	for (j = 0; j < CHAR_ARRAY_LEN(available_extensions); ++j) {
		available_ext_rb_str[j] = rb_str_new2(available_extensions[j]);
		rb_gc_register_mark_object(available_ext_rb_str[j]);
	}
}
