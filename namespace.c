/* indent-tabs-mode: nil */

#include "eval_intern.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/eval.h"
#include "internal/error.h"
#include "internal/file.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/load.h"
#include "internal/namespace.h"
#include "internal/st.h"
#include "internal/variable.h"
#include "iseq.h"
#include "ruby/internal/globals.h"
#include "ruby/util.h"
#include "vm_core.h"
#include "darray.h"

#include <stdio.h>

VALUE rb_cNamespace = 0;
VALUE rb_cNamespaceEntry = 0;
VALUE rb_mNamespaceLoader = 0;

static rb_namespace_t root_namespace_data = {
    /* Initialize values lazily in Init_namespace() */
    (VALUE)NULL, 0,
    (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL,
    (struct st_table *)NULL, (struct st_table *)NULL, (VALUE)NULL, (VALUE)NULL,
    false, false
};

static rb_namespace_t * root_namespace = &root_namespace_data;
static rb_namespace_t * main_namespace = 0;
static char *tmp_dir;
static bool tmp_dir_has_dirsep;

#define NAMESPACE_TMP_PREFIX "_ruby_ns_"

#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif

#if defined(_WIN32)
# define DIRSEP "\\"
#else
# define DIRSEP "/"
#endif

bool ruby_namespace_enabled = false; // extern
bool ruby_namespace_init_done = false; // extern
bool ruby_namespace_crashed = false; // extern, changed only in vm.c

VALUE rb_resolve_feature_path(VALUE klass, VALUE fname);
static VALUE rb_namespace_inspect(VALUE obj);

void
rb_namespace_init_done(void)
{
    ruby_namespace_init_done = true;
}

const rb_namespace_t *
rb_root_namespace(void)
{
    return root_namespace;
}

const rb_namespace_t *
rb_main_namespace(void)
{
    return main_namespace;
}

const rb_namespace_t *
rb_current_namespace(void)
{
    /*
     * If RUBY_NAMESPACE is not set, the root namespace is the only available one.
     *
     * Until the main_namespace is not initialized, the root namespace is
     * the only valid namespace.
     * This early return is to avoid accessing EC before its setup.
     */
    if (!main_namespace)
        return root_namespace;

    return rb_vm_current_namespace(GET_EC());
}

const rb_namespace_t *
rb_loading_namespace(void)
{
    if (!main_namespace)
        return root_namespace;

    return rb_vm_loading_namespace(GET_EC());
}

const rb_namespace_t *
rb_current_namespace_in_crash_report(void)
{
    if (ruby_namespace_crashed)
        return NULL;
    return rb_current_namespace();
}

static long namespace_id_counter = 0;

static long
namespace_generate_id(void)
{
    long id;
    RB_VM_LOCKING() {
        id = ++namespace_id_counter;
    }
    return id;
}

static VALUE
namespace_main_to_s(VALUE obj)
{
    return rb_str_new2("main");
}

static void
namespace_entry_initialize(rb_namespace_t *ns)
{
    const rb_namespace_t *root = rb_root_namespace();

    // These will be updated immediately
    ns->ns_object = 0;
    ns->ns_id = 0;

    ns->top_self = rb_obj_alloc(rb_cObject);
    rb_define_singleton_method(ns->top_self, "to_s", namespace_main_to_s, 0);
    rb_define_alias(rb_singleton_class(ns->top_self), "inspect", "to_s");
    ns->load_path = rb_ary_dup(root->load_path);
    ns->expanded_load_path = rb_ary_dup(root->expanded_load_path);
    ns->load_path_snapshot = rb_ary_new();
    ns->load_path_check_cache = 0;
    ns->loaded_features = rb_ary_dup(root->loaded_features);
    ns->loaded_features_snapshot = rb_ary_new();
    ns->loaded_features_index = st_init_numtable();
    ns->loaded_features_realpaths = rb_hash_dup(root->loaded_features_realpaths);
    ns->loaded_features_realpath_map = rb_hash_dup(root->loaded_features_realpath_map);
    ns->loading_table = st_init_strtable();
    ns->ruby_dln_libmap = rb_hash_new_with_size(0);
    ns->gvar_tbl = rb_hash_new_with_size(0);

    ns->is_user = true;
    ns->is_optional = true;
}

void
rb_namespace_gc_update_references(void *ptr)
{
    rb_namespace_t *ns = (rb_namespace_t *)ptr;
    if (!ns) return;

    if (ns->ns_object)
        ns->ns_object = rb_gc_location(ns->ns_object);
    if (ns->top_self)
        ns->top_self = rb_gc_location(ns->top_self);
    ns->load_path = rb_gc_location(ns->load_path);
    ns->expanded_load_path = rb_gc_location(ns->expanded_load_path);
    ns->load_path_snapshot = rb_gc_location(ns->load_path_snapshot);
    if (ns->load_path_check_cache) {
        ns->load_path_check_cache = rb_gc_location(ns->load_path_check_cache);
    }
    ns->loaded_features = rb_gc_location(ns->loaded_features);
    ns->loaded_features_snapshot = rb_gc_location(ns->loaded_features_snapshot);
    ns->loaded_features_realpaths = rb_gc_location(ns->loaded_features_realpaths);
    ns->loaded_features_realpath_map = rb_gc_location(ns->loaded_features_realpath_map);
    ns->ruby_dln_libmap = rb_gc_location(ns->ruby_dln_libmap);
    ns->gvar_tbl = rb_gc_location(ns->gvar_tbl);
}

void
rb_namespace_entry_mark(void *ptr)
{
    const rb_namespace_t *ns = (rb_namespace_t *)ptr;
    if (!ns) return;

    rb_gc_mark(ns->ns_object);
    rb_gc_mark(ns->top_self);
    rb_gc_mark(ns->load_path);
    rb_gc_mark(ns->expanded_load_path);
    rb_gc_mark(ns->load_path_snapshot);
    rb_gc_mark(ns->load_path_check_cache);
    rb_gc_mark(ns->loaded_features);
    rb_gc_mark(ns->loaded_features_snapshot);
    rb_gc_mark(ns->loaded_features_realpaths);
    rb_gc_mark(ns->loaded_features_realpath_map);
    if (ns->loading_table) {
        rb_mark_tbl(ns->loading_table);
    }
    rb_gc_mark(ns->ruby_dln_libmap);
    rb_gc_mark(ns->gvar_tbl);
}

static int
free_loading_table_entry(st_data_t key, st_data_t value, st_data_t arg)
{
    xfree((char *)key);
    return ST_DELETE;
}

static int
free_loaded_feature_index_i(st_data_t key, st_data_t value, st_data_t arg)
{
    if (!FIXNUM_P(value)) {
        rb_darray_free((void *)value);
    }
    return ST_CONTINUE;
}

static void
namespace_root_free(void *ptr)
{
    rb_namespace_t *ns = (rb_namespace_t *)ptr;
    if (ns->loading_table) {
        st_foreach(ns->loading_table, free_loading_table_entry, 0);
        st_free_table(ns->loading_table);
        ns->loading_table = 0;
    }

    if (ns->loaded_features_index) {
        st_foreach(ns->loaded_features_index, free_loaded_feature_index_i, 0);
        st_free_table(ns->loaded_features_index);
    }
}

static void
namespace_entry_free(void *ptr)
{
    namespace_root_free(ptr);
    xfree(ptr);
}

static size_t
namespace_entry_memsize(const void *ptr)
{
    const rb_namespace_t *ns = (const rb_namespace_t *)ptr;
    return sizeof(rb_namespace_t) + \
        rb_st_memsize(ns->loaded_features_index) + \
        rb_st_memsize(ns->loading_table);
}

const rb_data_type_t rb_namespace_data_type = {
    "Namespace::Entry",
    {
        rb_namespace_entry_mark,
        namespace_entry_free,
        namespace_entry_memsize,
        rb_namespace_gc_update_references,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY // TODO: enable RUBY_TYPED_WB_PROTECTED when inserting write barriers
};

const rb_data_type_t rb_root_namespace_data_type = {
    "Namespace::Root",
    {
        rb_namespace_entry_mark,
        namespace_root_free,
        namespace_entry_memsize,
        rb_namespace_gc_update_references,
    },
    &rb_namespace_data_type, 0, RUBY_TYPED_FREE_IMMEDIATELY // TODO: enable RUBY_TYPED_WB_PROTECTED when inserting write barriers
};

VALUE
rb_namespace_entry_alloc(VALUE klass)
{
    rb_namespace_t *entry;
    VALUE obj = TypedData_Make_Struct(klass, rb_namespace_t, &rb_namespace_data_type, entry);
    namespace_entry_initialize(entry);
    return obj;
}

static rb_namespace_t *
get_namespace_struct_internal(VALUE entry)
{
    rb_namespace_t *sval;
    TypedData_Get_Struct(entry, rb_namespace_t, &rb_namespace_data_type, sval);
    return sval;
}

rb_namespace_t *
rb_get_namespace_t(VALUE namespace)
{
    VALUE entry;
    ID id_namespace_entry;

    VM_ASSERT(namespace);

    if (NIL_P(namespace))
        return root_namespace;

    VM_ASSERT(NAMESPACE_OBJ_P(namespace));

    CONST_ID(id_namespace_entry, "__namespace_entry__");
    entry = rb_attr_get(namespace, id_namespace_entry);
    return get_namespace_struct_internal(entry);
}

VALUE
rb_get_namespace_object(rb_namespace_t *ns)
{
    VM_ASSERT(ns && ns->ns_object);
    return ns->ns_object;
}

/*
 *  call-seq:
 *    Namespace.new -> new_namespace
 *
 *  Returns a new Namespace object.
 */
static VALUE
namespace_initialize(VALUE namespace)
{
    rb_namespace_t *ns;
    rb_classext_t *object_classext;
    VALUE entry;
    ID id_namespace_entry;
    CONST_ID(id_namespace_entry, "__namespace_entry__");

    if (!rb_namespace_available()) {
        rb_raise(rb_eRuntimeError, "Namespace is disabled. Set RUBY_NAMESPACE=1 environment variable to use Namespace.");
    }

    entry = rb_class_new_instance_pass_kw(0, NULL, rb_cNamespaceEntry);
    ns = get_namespace_struct_internal(entry);

    ns->ns_object = namespace;
    ns->ns_id = namespace_generate_id();
    rb_define_singleton_method(ns->load_path, "resolve_feature_path", rb_resolve_feature_path, 1);

    // Set the Namespace object unique/consistent from any namespaces to have just single
    // constant table from any view of every (including main) namespace.
    // If a code in the namespace adds a constant, the constant will be visible even from root/main.
    RCLASS_SET_PRIME_CLASSEXT_WRITABLE(namespace, true);

    // Get a clean constant table of Object even by writable one
    // because ns was just created, so it has not touched any constants yet.
    object_classext = RCLASS_EXT_WRITABLE_IN_NS(rb_cObject, ns);
    RCLASS_SET_CONST_TBL(namespace, RCLASSEXT_CONST_TBL(object_classext), true);

    rb_ivar_set(namespace, id_namespace_entry, entry);

    return namespace;
}

/*
 *  call-seq:
 *    Namespace.enabled? -> true or false
 *
 *  Returns +true+ if namespace is enabled.
 */
static VALUE
rb_namespace_s_getenabled(VALUE recv)
{
    return RBOOL(rb_namespace_available());
}

/*
 *  call-seq:
 *    Namespace.current -> namespace, nil or false
 *
 *  Returns the current namespace.
 *  Returns +nil+ if it is the built-in namespace.
 *  Returns +false+ if namespace is not enabled.
 */
static VALUE
rb_namespace_s_current(VALUE recv)
{
    const rb_namespace_t *ns;

    if (!rb_namespace_available())
        return Qnil;

    ns = rb_vm_current_namespace(GET_EC());
    VM_ASSERT(ns && ns->ns_object);
    return ns->ns_object;
}

/*
 *  call-seq:
 *    load_path -> array
 *
 *  Returns namespace local load path.
 */
static VALUE
rb_namespace_load_path(VALUE namespace)
{
    VM_ASSERT(NAMESPACE_OBJ_P(namespace));
    return rb_get_namespace_t(namespace)->load_path;
}

#ifdef _WIN32
UINT rb_w32_system_tmpdir(WCHAR *path, UINT len);
#endif

/* Copied from mjit.c Ruby 3.0.3 */
static char *
system_default_tmpdir(void)
{
    // c.f. ext/etc/etc.c:etc_systmpdir()
#ifdef _WIN32
    WCHAR tmppath[_MAX_PATH];
    UINT len = rb_w32_system_tmpdir(tmppath, numberof(tmppath));
    if (len) {
        int blen = WideCharToMultiByte(CP_UTF8, 0, tmppath, len, NULL, 0, NULL, NULL);
        char *tmpdir = xmalloc(blen + 1);
        WideCharToMultiByte(CP_UTF8, 0, tmppath, len, tmpdir, blen, NULL, NULL);
        tmpdir[blen] = '\0';
        return tmpdir;
    }
#elif defined _CS_DARWIN_USER_TEMP_DIR
    char path[MAXPATHLEN];
    size_t len = confstr(_CS_DARWIN_USER_TEMP_DIR, path, sizeof(path));
    if (len > 0) {
        char *tmpdir = xmalloc(len);
        if (len > sizeof(path)) {
            confstr(_CS_DARWIN_USER_TEMP_DIR, tmpdir, len);
        }
        else {
            memcpy(tmpdir, path, len);
        }
        return tmpdir;
    }
#endif
    return 0;
}

static int
check_tmpdir(const char *dir)
{
    struct stat st;

    if (!dir) return FALSE;
    if (stat(dir, &st)) return FALSE;
#ifndef S_ISDIR
#   define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif
    if (!S_ISDIR(st.st_mode)) return FALSE;
#ifndef _WIN32
# ifndef S_IWOTH
#   define S_IWOTH 002
# endif
    if (st.st_mode & S_IWOTH) {
# ifdef S_ISVTX
        if (!(st.st_mode & S_ISVTX)) return FALSE;
# else
        return FALSE;
# endif
    }
    if (access(dir, W_OK)) return FALSE;
#endif
    return TRUE;
}

static char *
system_tmpdir(void)
{
    char *tmpdir;
# define RETURN_ENV(name) \
    if (check_tmpdir(tmpdir = getenv(name))) return ruby_strdup(tmpdir)
    RETURN_ENV("TMPDIR");
    RETURN_ENV("TMP");
    tmpdir = system_default_tmpdir();
    if (check_tmpdir(tmpdir)) return tmpdir;
    return ruby_strdup("/tmp");
# undef RETURN_ENV
}

/* end of copy */

static int
sprint_ext_filename(char *str, size_t size, long namespace_id, const char *prefix, const char *basename)
{
    if (tmp_dir_has_dirsep) {
        return snprintf(str, size, "%s%sp%"PRI_PIDT_PREFIX"u_%ld_%s", tmp_dir, prefix, getpid(), namespace_id, basename);
    }
    return snprintf(str, size, "%s%s%sp%"PRI_PIDT_PREFIX"u_%ld_%s", tmp_dir, DIRSEP, prefix, getpid(), namespace_id, basename);
}

#ifdef _WIN32
static const char *
copy_ext_file_error(char *message, size_t size)
{
    int error = GetLastError();
    char *p = message;
    size_t len = snprintf(message, size, "%d: ", error);

#define format_message(sublang) FormatMessage(\
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,	\
        NULL, error, MAKELANGID(LANG_NEUTRAL, (sublang)),		\
        message + len, size - len, NULL)
    if (format_message(SUBLANG_ENGLISH_US) == 0)
        format_message(SUBLANG_DEFAULT);
    for (p = message + len; *p; p++) {
        if (*p == '\n' || *p == '\r')
            *p = ' ';
    }
    return message;
}
#else
static const char *
copy_ext_file_error(char *message, size_t size, int copy_retvalue, char *src_path, char *dst_path)
{
    switch (copy_retvalue) {
      case 1:
        snprintf(message, size, "can't open the extension path: %s", src_path);
      case 2:
        snprintf(message, size, "can't open the file to write: %s", dst_path);
      case 3:
        snprintf(message, size, "failed to read the extension path: %s", src_path);
      case 4:
        snprintf(message, size, "failed to write the extension path: %s", dst_path);
      case 5:
        snprintf(message, size, "failed to stat the extension path to copy permissions: %s", src_path);
      case 6:
        snprintf(message, size, "failed to set permissions to the copied extension path: %s", dst_path);
      default:
        rb_bug("unknown return value of copy_ext_file: %d", copy_retvalue);
    }
    return message;
}
#endif

static int
copy_ext_file(char *src_path, char *dst_path)
{
#if defined(_WIN32)
    int rvalue;

    WCHAR *w_src = rb_w32_mbstr_to_wstr(CP_UTF8, src_path, -1, NULL);
    WCHAR *w_dst = rb_w32_mbstr_to_wstr(CP_UTF8, dst_path, -1, NULL);
    if (!w_src || !w_dst) {
        rb_memerror();
    }

    rvalue = CopyFileW(w_src, w_dst, FALSE) ? 0 : 1;
    free(w_src);
    free(w_dst);
    return rvalue;
#else
    FILE *src, *dst;
    char buffer[1024];
    size_t read = 0, wrote, written = 0;
    size_t maxread = sizeof(buffer);
    int eof = 0;
    int clean_read = 1;
    int retvalue = 0;

    src = fopen(src_path, "rb");
    if (!src) {
        return 1;
    }
    dst = fopen(dst_path, "wb");
    if (!dst) {
        return 2;
    }
    while (!eof) {
        if (clean_read) {
            read = fread(buffer, 1, sizeof(buffer), src);
            written = 0;
        }
        if (read > 0) {
            wrote = fwrite(buffer+written, 1, read-written, dst);
            if (wrote < read-written) {
                if (ferror(dst)) {
                    retvalue = 4;
                    break;
                }
                else { // partial write
                    clean_read = 0;
                    written += wrote;
                }
            }
            else { // Wrote the entire buffer to dst, next read is clean one
                clean_read = 1;
            }
        }
        if (read < maxread) {
            if (clean_read && feof(src)) {
                // If it's not clean, buffer should have bytes not written yet.
                eof = 1;
            }
            else if (ferror(src)) {
                retvalue = 3;
                // Writes could be partial/dirty, but this load is failure anyway
                break;
            }
        }
    }
    fclose(src);
    fclose(dst);
#if defined(__CYGWIN__)
    // On Cygwin, CopyFile-like operations may strip executable bits.
    // Explicitly match destination file permissions to source.
    if (retvalue == 0) {
        struct stat st;
        if (stat(src_path, &st) != 0) {
            retvalue = 5;
        }
        else if (chmod(dst_path, st.st_mode & 0777) != 0) {
            retvalue = 6;
        }
    }
#endif
    return retvalue;
#endif
}

#if defined __CYGWIN__ || defined DOSISH
#define isdirsep(x) ((x) == '/' || (x) == '\\')
#else
#define isdirsep(x) ((x) == '/')
#endif

#define IS_SOEXT(e) (strcmp((e), ".so") == 0 || strcmp((e), ".o") == 0)
#define IS_DLEXT(e) (strcmp((e), DLEXT) == 0)

static void
fname_without_suffix(const char *fname, char *rvalue, size_t rsize)
{
    size_t len = strlen(fname);
    const char *pos;
    for (pos = fname + len; pos > fname; pos--) {
        if (IS_SOEXT(pos) || IS_DLEXT(pos)) {
            len = pos - fname;
            break;
        }
        if (fname + len - pos > DLEXT_MAXLEN) break;
    }
    if (len > rsize - 1) len = rsize - 1;
    memcpy(rvalue, fname, len);
    rvalue[len] = '\0';
}

static void
escaped_basename(const char *path, const char *fname, char *rvalue, size_t rsize)
{
    char *pos;
    const char *leaf = path, *found;
    // `leaf + 1` looks uncomfortable (when leaf == path), but fname must not be the top-dir itself
    while ((found = strstr(leaf + 1, fname)) != NULL) {
        leaf = found; // find the last occurrence for the path like /etc/my-crazy-lib-dir/etc.so
    }
    strlcpy(rvalue, leaf, rsize);
    for (pos = rvalue; *pos; pos++) {
        if (isdirsep(*pos)) {
            *pos = '+';
        }
    }
}

VALUE
rb_namespace_local_extension(VALUE namespace, VALUE fname, VALUE path)
{
    char ext_path[MAXPATHLEN], fname2[MAXPATHLEN], basename[MAXPATHLEN];
    int copy_error, wrote;
    char *src_path = RSTRING_PTR(path), *fname_ptr = RSTRING_PTR(fname);
    rb_namespace_t *ns = rb_get_namespace_t(namespace);

    fname_without_suffix(fname_ptr, fname2, sizeof(fname2));
    escaped_basename(src_path, fname2, basename, sizeof(basename));

    wrote = sprint_ext_filename(ext_path, sizeof(ext_path), ns->ns_id, NAMESPACE_TMP_PREFIX, basename);
    if (wrote >= (int)sizeof(ext_path)) {
        rb_bug("Extension file path in namespace was too long");
    }
    copy_error = copy_ext_file(src_path, ext_path);
    if (copy_error) {
        char message[1024];
#if defined(_WIN32)
        copy_ext_file_error(message, sizeof(message));
#else
        copy_ext_file_error(message, sizeof(message), copy_error, src_path, ext_path);
#endif
        rb_raise(rb_eLoadError, "can't prepare the extension file for namespaces (%s from %s): %s", ext_path, src_path, message);
    }
    // TODO: register the path to be clean-uped
    return rb_str_new_cstr(ext_path);
}

// TODO: delete it just after dln_load? or delay it?
//       At least for _WIN32, deleting extension files should be delayed until the namespace's destructor.
//       And it requires calling dlclose before deleting it.

static VALUE
rb_namespace_load(int argc, VALUE *argv, VALUE namespace)
{
    VALUE fname, wrap;
    rb_scan_args(argc, argv, "11", &fname, &wrap);

    rb_vm_frame_flag_set_ns_require(GET_EC());

    VALUE args = rb_ary_new_from_args(2, fname, wrap);
    return rb_load_entrypoint(args);
}

static VALUE
rb_namespace_require(VALUE namespace, VALUE fname)
{
    rb_vm_frame_flag_set_ns_require(GET_EC());

    return rb_require_string(fname);
}

static VALUE
rb_namespace_require_relative(VALUE namespace, VALUE fname)
{
    rb_vm_frame_flag_set_ns_require(GET_EC());

    return rb_require_relative_entrypoint(fname);
}

static void
initialize_root_namespace(void)
{
    VALUE root_namespace, entry;
    ID id_namespace_entry;
    rb_vm_t *vm = GET_VM();
    rb_namespace_t *root = (rb_namespace_t *)rb_root_namespace();

    root->load_path = rb_ary_new();
    root->expanded_load_path = rb_ary_hidden_new(0);
    root->load_path_snapshot = rb_ary_hidden_new(0);
    root->load_path_check_cache = 0;
    rb_define_singleton_method(root->load_path, "resolve_feature_path", rb_resolve_feature_path, 1);

    root->loaded_features = rb_ary_new();
    root->loaded_features_snapshot = rb_ary_hidden_new(0);
    root->loaded_features_index = st_init_numtable();
    root->loaded_features_realpaths = rb_hash_new();
    rb_obj_hide(root->loaded_features_realpaths);
    root->loaded_features_realpath_map = rb_hash_new();
    rb_obj_hide(root->loaded_features_realpath_map);

    root->ruby_dln_libmap = rb_hash_new_with_size(0);
    root->gvar_tbl = rb_hash_new_with_size(0);

    vm->root_namespace = root;

    if (rb_namespace_available()) {
        CONST_ID(id_namespace_entry, "__namespace_entry__");

        root_namespace = rb_obj_alloc(rb_cNamespace);
        RCLASS_SET_PRIME_CLASSEXT_WRITABLE(root_namespace, true);
        RCLASS_SET_CONST_TBL(root_namespace, RCLASSEXT_CONST_TBL(RCLASS_EXT_PRIME(rb_cObject)), true);

        root->ns_id = namespace_generate_id();
        root->ns_object = root_namespace;

        entry = TypedData_Wrap_Struct(rb_cNamespaceEntry, &rb_root_namespace_data_type, root);
        rb_ivar_set(root_namespace, id_namespace_entry, entry);
    }
    else {
        root->ns_id = 1;
        root->ns_object = Qnil;
    }
}

static VALUE
rb_namespace_eval(VALUE namespace, VALUE str)
{
    const rb_iseq_t *iseq;
    const rb_namespace_t *ns;

    StringValue(str);

    iseq = rb_iseq_compile_iseq(str, rb_str_new_cstr("eval"));
    VM_ASSERT(iseq);

    ns = (const rb_namespace_t *)rb_get_namespace_t(namespace);

    return rb_iseq_eval(iseq, ns);
}

static int namespace_experimental_warned = 0;

void
rb_initialize_main_namespace(void)
{
    rb_namespace_t *ns;
    VALUE main_ns;
    rb_vm_t *vm = GET_VM();

    VM_ASSERT(rb_namespace_available());

    if (!namespace_experimental_warned) {
        rb_category_warn(RB_WARN_CATEGORY_EXPERIMENTAL,
                         "Namespace is experimental, and the behavior may change in the future!\n"
                         "See doc/namespace.md for known issues, etc.");
        namespace_experimental_warned = 1;
    }

    main_ns = rb_class_new_instance(0, NULL, rb_cNamespace);
    VM_ASSERT(NAMESPACE_OBJ_P(main_ns));
    ns = rb_get_namespace_t(main_ns);
    ns->ns_object = main_ns;
    ns->is_user = true;
    ns->is_optional = false;

    rb_const_set(rb_cNamespace, rb_intern("MAIN"), main_ns);

    vm->main_namespace = main_namespace = ns;

    // create the writable classext of ::Object explicitly to finalize the set of visible top-level constants
    RCLASS_EXT_WRITABLE_IN_NS(rb_cObject, ns);
}

static VALUE
rb_namespace_inspect(VALUE obj)
{
    rb_namespace_t *ns;
    VALUE r;
    if (obj == Qfalse) {
        r = rb_str_new_cstr("#<Namespace:root>");
        return r;
    }
    ns = rb_get_namespace_t(obj);
    r = rb_str_new_cstr("#<Namespace:");
    rb_str_concat(r, rb_funcall(LONG2NUM(ns->ns_id), rb_intern("to_s"), 0));
    if (NAMESPACE_ROOT_P(ns)) {
        rb_str_cat_cstr(r, ",root");
    }
    if (NAMESPACE_USER_P(ns)) {
        rb_str_cat_cstr(r, ",user");
    }
    if (NAMESPACE_MAIN_P(ns)) {
        rb_str_cat_cstr(r, ",main");
    }
    else if (NAMESPACE_OPTIONAL_P(ns)) {
        rb_str_cat_cstr(r, ",optional");
    }
    rb_str_cat_cstr(r, ">");
    return r;
}

static VALUE
rb_namespace_loading_func(int argc, VALUE *argv, VALUE _self)
{
    rb_vm_frame_flag_set_ns_require(GET_EC());
    return rb_call_super(argc, argv);
}

static void
namespace_define_loader_method(const char *name)
{
    rb_define_private_method(rb_mNamespaceLoader, name, rb_namespace_loading_func, -1);
    rb_define_singleton_method(rb_mNamespaceLoader, name, rb_namespace_loading_func, -1);
}

void
Init_root_namespace(void)
{
    root_namespace->loading_table = st_init_strtable();
}

void
Init_enable_namespace(void)
{
    const char *env = getenv("RUBY_NAMESPACE");
    if (env && strlen(env) == 1 && env[0] == '1') {
        ruby_namespace_enabled = true;
    }
    else {
        ruby_namespace_init_done = true;
    }
}

#ifdef RUBY_DEBUG

/* :nodoc: */
static VALUE
rb_namespace_s_root(VALUE recv)
{
    return root_namespace->ns_object;
}

/* :nodoc: */
static VALUE
rb_namespace_s_main(VALUE recv)
{
    return main_namespace->ns_object;
}

static const char *
classname(VALUE klass)
{
    VALUE p;
    if (!klass) {
        return "Qfalse";
    }
    p = RCLASSEXT_CLASSPATH(RCLASS_EXT_PRIME(klass));
    if (RTEST(p))
        return RSTRING_PTR(p);
    if (RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_MODULE) || RB_TYPE_P(klass, T_ICLASS))
        return "AnyClassValue";
    return "NonClassValue";
}

static enum rb_id_table_iterator_result
dump_classext_methods_i(ID mid, VALUE _val, void *data)
{
    VALUE ary = (VALUE)data;
    rb_ary_push(ary, rb_id2str(mid));
    return ID_TABLE_CONTINUE;
}

static enum rb_id_table_iterator_result
dump_classext_constants_i(ID mid, VALUE _val, void *data)
{
    VALUE ary = (VALUE)data;
    rb_ary_push(ary, rb_id2str(mid));
    return ID_TABLE_CONTINUE;
}

static void
dump_classext_i(rb_classext_t *ext, bool is_prime, VALUE _ns, void *data)
{
    char buf[4096];
    struct rb_id_table *tbl;
    VALUE ary, res = (VALUE)data;

    snprintf(buf, 4096, "Namespace %ld:%s classext %p\n",
             RCLASSEXT_NS(ext)->ns_id, is_prime ? " prime" : "", (void *)ext);
    rb_str_cat_cstr(res, buf);

    snprintf(buf, 2048, "  Super: %s\n", classname(RCLASSEXT_SUPER(ext)));
    rb_str_cat_cstr(res, buf);

    tbl = RCLASSEXT_M_TBL(ext);
    if (tbl) {
        ary = rb_ary_new_capa((long)rb_id_table_size(tbl));
        rb_id_table_foreach(RCLASSEXT_M_TBL(ext), dump_classext_methods_i, (void *)ary);
        rb_ary_sort_bang(ary);
        snprintf(buf, 4096, "  Methods(%ld): ", RARRAY_LEN(ary));
        rb_str_cat_cstr(res, buf);
        rb_str_concat(res, rb_ary_join(ary, rb_str_new_cstr(",")));
        rb_str_cat_cstr(res, "\n");
    }
    else {
        rb_str_cat_cstr(res, "  Methods(0): .\n");
    }

    tbl = RCLASSEXT_CONST_TBL(ext);
    if (tbl) {
        ary = rb_ary_new_capa((long)rb_id_table_size(tbl));
        rb_id_table_foreach(tbl, dump_classext_constants_i, (void *)ary);
        rb_ary_sort_bang(ary);
        snprintf(buf, 4096, "  Constants(%ld): ", RARRAY_LEN(ary));
        rb_str_cat_cstr(res, buf);
        rb_str_concat(res, rb_ary_join(ary, rb_str_new_cstr(",")));
        rb_str_cat_cstr(res, "\n");
    }
    else {
        rb_str_cat_cstr(res, "  Constants(0): .\n");
    }
}

/* :nodoc: */
static VALUE
rb_f_dump_classext(VALUE recv, VALUE klass)
{
    /*
     * The desired output String value is:
     * Class: 0x88800932 (String) [singleton]
     * Prime classext namespace(2,main), readable(t), writable(f)
     * Non-prime classexts: 3
     * Namespace 2: prime classext 0x88800933
     *   Super: Object
     *   Methods(43): aaaaa, bbbb, cccc, dddd, eeeee, ffff, gggg, hhhhh, ...
     *   Constants(12): FOO, Bar, ...
     * Namespace 5: classext 0x88800934
     *   Super: Object
     *   Methods(43): aaaaa, bbbb, cccc, dddd, eeeee, ffff, gggg, hhhhh, ...
     *   Constants(12): FOO, Bar, ...
     */
    char buf[2048];
    VALUE res;
    const rb_classext_t *ext;
    const rb_namespace_t *ns;
    st_table *classext_tbl;

    if (!(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_MODULE))) {
        snprintf(buf, 2048, "Non-class/module value: %p (%s)\n", (void *)klass, rb_type_str(BUILTIN_TYPE(klass)));
        return rb_str_new_cstr(buf);
    }

    if (RB_TYPE_P(klass, T_CLASS)) {
        snprintf(buf, 2048, "Class: %p (%s)%s\n",
                 (void *)klass, classname(klass), RCLASS_SINGLETON_P(klass) ? " [singleton]" : "");
    }
    else {
        snprintf(buf, 2048, "Module: %p (%s)\n", (void *)klass, classname(klass));
    }
    res = rb_str_new_cstr(buf);

    ext = RCLASS_EXT_PRIME(klass);
    ns = RCLASSEXT_NS(ext);
    snprintf(buf, 2048, "Prime classext namespace(%ld,%s), readable(%s), writable(%s)\n",
             ns->ns_id,
             NAMESPACE_ROOT_P(ns) ? "root" : (NAMESPACE_MAIN_P(ns) ? "main" : "optional"),
             RCLASS_PRIME_CLASSEXT_READABLE_P(klass) ? "t" : "f",
             RCLASS_PRIME_CLASSEXT_WRITABLE_P(klass) ? "t" : "f");
    rb_str_cat_cstr(res, buf);

    classext_tbl = RCLASS_CLASSEXT_TBL(klass);
    if (!classext_tbl) {
        rb_str_cat_cstr(res, "Non-prime classexts: 0\n");
    }
    else {
        snprintf(buf, 2048, "Non-prime classexts: %zu\n", st_table_size(classext_tbl));
        rb_str_cat_cstr(res, buf);
    }

    rb_class_classext_foreach(klass, dump_classext_i, (void *)res);

    return res;
}

/* :nodoc: */
static VALUE
rb_namespace_root_p(VALUE namespace)
{
    const rb_namespace_t *ns = (const rb_namespace_t *)rb_get_namespace_t(namespace);
    return RBOOL(NAMESPACE_ROOT_P(ns));
}

/* :nodoc: */
static VALUE
rb_namespace_main_p(VALUE namespace)
{
    const rb_namespace_t *ns = (const rb_namespace_t *)rb_get_namespace_t(namespace);
    return RBOOL(NAMESPACE_MAIN_P(ns));
}

/* :nodoc: */
static VALUE
rb_namespace_user_p(VALUE namespace)
{
    const rb_namespace_t *ns = (const rb_namespace_t *)rb_get_namespace_t(namespace);
    return RBOOL(NAMESPACE_USER_P(ns));
}

#endif /* RUBY_DEBUG */

/*
 *  Document-class: Namespace
 *
 *  Namespace is designed to provide separated spaces in a Ruby
 *  process, to isolate applications and libraries.
 *  See {Namespace}[rdoc-ref:namespace.md].
 */
void
Init_Namespace(void)
{
    tmp_dir = system_tmpdir();
    tmp_dir_has_dirsep = (strcmp(tmp_dir + (strlen(tmp_dir) - strlen(DIRSEP)), DIRSEP) == 0);

    rb_cNamespace = rb_define_class("Namespace", rb_cModule);
    rb_define_method(rb_cNamespace, "initialize", namespace_initialize, 0);

    /* :nodoc: */
    rb_cNamespaceEntry = rb_define_class_under(rb_cNamespace, "Entry", rb_cObject);
    rb_define_alloc_func(rb_cNamespaceEntry, rb_namespace_entry_alloc);

    initialize_root_namespace();

    /* :nodoc: */
    rb_mNamespaceLoader = rb_define_module_under(rb_cNamespace, "Loader");
    namespace_define_loader_method("require");
    namespace_define_loader_method("require_relative");
    namespace_define_loader_method("load");

    if (rb_namespace_available()) {
        rb_include_module(rb_cObject, rb_mNamespaceLoader);

#ifdef RUBY_DEBUG
        rb_define_singleton_method(rb_cNamespace, "root", rb_namespace_s_root, 0);
        rb_define_singleton_method(rb_cNamespace, "main", rb_namespace_s_main, 0);
        rb_define_global_function("dump_classext", rb_f_dump_classext, 1);

        rb_define_method(rb_cNamespace, "root?", rb_namespace_root_p, 0);
        rb_define_method(rb_cNamespace, "main?", rb_namespace_main_p, 0);
        rb_define_method(rb_cNamespace, "user?", rb_namespace_user_p, 0);
#endif
    }

    rb_define_singleton_method(rb_cNamespace, "enabled?", rb_namespace_s_getenabled, 0);
    rb_define_singleton_method(rb_cNamespace, "current", rb_namespace_s_current, 0);

    rb_define_method(rb_cNamespace, "load_path", rb_namespace_load_path, 0);
    rb_define_method(rb_cNamespace, "load", rb_namespace_load, -1);
    rb_define_method(rb_cNamespace, "require", rb_namespace_require, 1);
    rb_define_method(rb_cNamespace, "require_relative", rb_namespace_require_relative, 1);
    rb_define_method(rb_cNamespace, "eval", rb_namespace_eval, 1);

    rb_define_method(rb_cNamespace, "inspect", rb_namespace_inspect, 0);
}
