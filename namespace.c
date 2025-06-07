/* indent-tabs-mode: nil */

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
#include "ruby/internal/globals.h"
#include "ruby/util.h"
#include "vm_core.h"

#include <stdio.h>

VALUE rb_cNamespace = 0;
VALUE rb_cNamespaceEntry = 0;
VALUE rb_mNamespaceRefiner = 0;
VALUE rb_mNamespaceLoader = 0;

static rb_namespace_t builtin_namespace_data = {
    .ns_object = Qnil,
    .ns_id = 0,
    .is_builtin = true,
    .is_user = false,
    .is_optional = false
};
static rb_namespace_t * const root_namespace = 0;
static rb_namespace_t * const builtin_namespace = &builtin_namespace_data;
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

static int namespace_availability = 0;

VALUE rb_resolve_feature_path(VALUE klass, VALUE fname);
static VALUE rb_namespace_inspect(VALUE obj);

int
rb_namespace_available(void)
{
    const char *env;
    if (namespace_availability) {
        return namespace_availability > 0 ? 1 : 0;
    }
    env = getenv("RUBY_NAMESPACE");
    if (env && strlen(env) > 0) {
        if (strcmp(env, "1") == 0) {
            namespace_availability = 1;
            return 1;
        }
    }
    namespace_availability = -1;
    return 0;
}

static void namespace_push(rb_thread_t *th, VALUE namespace);
static VALUE namespace_pop(VALUE th_value);

void
rb_namespace_enable_builtin(void)
{
    VALUE require_stack = GET_VM()->require_stack;
    if (require_stack) {
        rb_ary_push(require_stack, Qnil);
    }
}

void
rb_namespace_disable_builtin(void)
{
    VALUE require_stack = GET_VM()->require_stack;
    if (require_stack) {
        rb_ary_pop(require_stack);
    }
}

void
rb_namespace_push_loading_namespace(const rb_namespace_t *ns)
{
    VALUE require_stack = GET_VM()->require_stack;
    rb_ary_push(require_stack, ns->ns_object);
}

void
rb_namespace_pop_loading_namespace(const rb_namespace_t *ns)
{
    VALUE require_stack = GET_VM()->require_stack;
    long size = RARRAY_LEN(require_stack);
    if (size == 0)
        rb_bug("popping on the empty require_stack");
    VALUE latest = RARRAY_AREF(require_stack, size-1);
    if (latest != ns->ns_object)
        rb_bug("Inconsistent loading namespace");
    rb_ary_pop(require_stack);
}

rb_namespace_t *
rb_root_namespace(void)
{
    return root_namespace;
}

const rb_namespace_t *
rb_builtin_namespace(void)
{
    return (const rb_namespace_t *)builtin_namespace;
}

rb_namespace_t *
rb_main_namespace(void)
{
    return main_namespace;
}

static bool
namespace_ignore_builtin_primitive_methods_p(const rb_namespace_t *ns, rb_method_definition_t *def)
{
    if (!NAMESPACE_BUILTIN_P(ns)) {
        return false;
    }
    /* Primitive methods (just to call C methods) covers/hides the effective
       namespaces, so ignore the methods' namespaces to expose user code's
       namespace to the implementation.
     */
    if (def->type == VM_METHOD_TYPE_ISEQ) {
        ID mid = def->original_id;
        const char *path = RSTRING_PTR(pathobj_path(def->body.iseq.iseqptr->body->location.pathobj));
        if (strcmp(path, "<internal:kernel>") == 0) {
            if (mid == rb_intern("class") || mid == rb_intern("clone") ||
                mid == rb_intern("tag") || mid == rb_intern("then") ||
                mid == rb_intern("yield_self") || mid == rb_intern("loop") ||
                mid == rb_intern("Float") || mid == rb_intern("Integer")
                ) {
                return true;
            }
        }
        else if (strcmp(path, "<internal:warning>") == 0) {
            if (mid == rb_intern("warn")) {
                return true;
            }
        }
        else if (strcmp(path, "<internal:marshal>") == 0) {
            if (mid == rb_intern("load"))
                return true;
        }
    }
    return false;
}

static inline const rb_namespace_t *
block_proc_namespace(const VALUE procval)
{
    rb_proc_t *proc;

    if (procval) {
        GetProcPtr(procval, proc);
        return proc->ns;
    }
    else {
        return NULL;
    }
}

static const rb_namespace_t *
current_namespace(bool permit_calling_builtin)
{
    /*
     * TODO: move this code to vm.c or somewhere else
     *       when it's fully updated with VM_FRAME_FLAG_*
     */
    const rb_callable_method_entry_t *cme;
    const rb_namespace_t *ns;
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    int calling = 1;

    if (!rb_namespace_available())
        return 0;

    if (th->namespaces && RARRAY_LEN(th->namespaces) > 0) {
        // temp code to detect the context is in require/load
        // TODO: this doesn't work well in optional namespaces
        // calling = 0;
    }
    while (calling) {
        const rb_namespace_t *proc_ns = NULL;
        VALUE bh;
        if (VM_FRAME_NS_SWITCH_P(cfp)) {
            bh = rb_vm_frame_block_handler(cfp);
            if (bh && vm_block_handler_type(bh) == block_handler_type_proc) {
                proc_ns = block_proc_namespace(VM_BH_TO_PROC(bh));
                if (permit_calling_builtin || NAMESPACE_USER_P(proc_ns))
                    return proc_ns;
            }
        }
        cme = rb_vm_frame_method_entry(cfp);
        if (cme && cme->def) {
            ns = cme->def->ns;
            if (ns) {
                // this method is not a built-in class/module's method
                // or a built-in primitive (Ruby) method
                if (!namespace_ignore_builtin_primitive_methods_p(ns, cme->def)) {
                    if (permit_calling_builtin || (proc_ns && NAMESPACE_USER_P(proc_ns)))
                        return ns;
                }
            }
            cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
        }
        else {
            calling = 0;
        }
    }
    // not in namespace-marked method calls
    ns = th->ns;
    if (ns) {
        return ns;
    }
    if (!main_namespace) {
        // Namespaces are not ready to be created
        return root_namespace;
    }
    return main_namespace;
}

const rb_namespace_t *
rb_current_namespace(void)
{
    return current_namespace(true);
}

const rb_namespace_t *
rb_loading_namespace(void)
{
    VALUE namespace;
    long len;
    VALUE require_stack = GET_VM()->require_stack;

    if (!rb_namespace_available())
        return 0;

    if (!require_stack) {
        return current_namespace(false);
    }
    if ((len = RARRAY_LEN(require_stack)) == 0) {
        return current_namespace(false);
    }

    if (!RB_TYPE_P(require_stack, T_ARRAY))
        rb_bug("require_stack is not an array: %s", rb_type_str(BUILTIN_TYPE(require_stack)));

    namespace = RARRAY_AREF(require_stack, len-1);
    return rb_get_namespace_t(namespace);
}

const rb_namespace_t *
rb_definition_namespace(void)
{
    const rb_namespace_t *ns = current_namespace(true);
    if (NAMESPACE_BUILTIN_P(ns)) {
        return root_namespace;
    }
    return ns;
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

static void
namespace_entry_initialize(rb_namespace_t *ns)
{
    rb_vm_t *vm = GET_VM();

    // These will be updated immediately
    ns->ns_object = 0;
    ns->ns_id = 0;

    ns->top_self = 0;
    ns->load_path = rb_ary_dup(vm->load_path);
    ns->expanded_load_path = rb_ary_dup(vm->expanded_load_path);
    ns->load_path_snapshot = rb_ary_new();
    ns->load_path_check_cache = 0;
    ns->loaded_features = rb_ary_dup(vm->loaded_features);
    ns->loaded_features_snapshot = rb_ary_new();
    ns->loaded_features_index = st_init_numtable();
    ns->loaded_features_realpaths = rb_hash_dup(vm->loaded_features_realpaths);
    ns->loaded_features_realpath_map = rb_hash_dup(vm->loaded_features_realpath_map);
    ns->loading_table = st_init_strtable();
    ns->ruby_dln_libmap = rb_hash_new_with_size(0);
    ns->gvar_tbl = rb_hash_new_with_size(0);

    ns->is_builtin = false;
    ns->is_user = true;
    ns->is_optional = true;
}

void rb_namespace_gc_update_references(void *ptr)
{
    rb_namespace_t *ns = (rb_namespace_t *)ptr;
    if (!NIL_P(ns->ns_object))
        ns->ns_object = rb_gc_location(ns->ns_object);
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

#define namespace_entry_free RUBY_TYPED_DEFAULT_FREE

static size_t
namespace_entry_memsize(const void *ptr)
{
    return sizeof(rb_namespace_t);
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

    if (!namespace)
        return root_namespace;
    if (NIL_P(namespace))
        return builtin_namespace;

    CONST_ID(id_namespace_entry, "__namespace_entry__");
    entry = rb_attr_get(namespace, id_namespace_entry);
    return get_namespace_struct_internal(entry);
}

VALUE
rb_get_namespace_object(rb_namespace_t *ns)
{
    if (!ns) // root namespace
        return Qfalse;
    return ns->ns_object;
}

static void setup_pushing_loading_namespace(rb_namespace_t *ns);

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
    ns->load_path = rb_ary_dup(GET_VM()->load_path);
    ns->is_user = true;
    rb_define_singleton_method(ns->load_path, "resolve_feature_path", rb_resolve_feature_path, 1);

    // Set the Namespace object unique/consistent from any namespaces to have just single
    // constant table from any view of every (including main) namespace.
    // If a code in the namespace adds a constant, the constant will be visible even from root/main.
    RCLASS_SET_PRIME_CLASSEXT_WRITABLE(namespace, true);

    // fallback to ivptr for ivars from shapes to manipulate the constant table
    rb_evict_ivars_to_hash(namespace);

    // Get a clean constant table of Object even by writable one
    // because ns was just created, so it has not touched any constants yet.
    object_classext = RCLASS_EXT_WRITABLE_IN_NS(rb_cObject, ns);
    RCLASS_SET_CONST_TBL(namespace, RCLASSEXT_CONST_TBL(object_classext), true);

    rb_ivar_set(namespace, id_namespace_entry, entry);

    setup_pushing_loading_namespace(ns);

    return namespace;
}

static VALUE
rb_namespace_s_getenabled(VALUE namespace)
{
    return RBOOL(rb_namespace_available());
}

static VALUE
rb_namespace_current(VALUE klass)
{
    const rb_namespace_t *ns = rb_current_namespace();
    if (NAMESPACE_USER_P(ns)) {
        return ns->ns_object;
    }
    if (NAMESPACE_BUILTIN_P(ns)) {
        return Qnil;
    }
    return Qfalse;
}

static VALUE
rb_namespace_s_is_builtin_p(VALUE namespace, VALUE klass)
{
    if (RCLASS_PRIME_CLASSEXT_READABLE_P(klass) && !RCLASS_PRIME_CLASSEXT_WRITABLE_P(klass))
        return Qtrue;
    return Qfalse;
}

static VALUE
rb_namespace_load_path(VALUE namespace)
{
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
fname_without_suffix(char *fname, char *rvalue)
{
    char *pos;
    strcpy(rvalue, fname);
    for (pos = rvalue + strlen(fname); pos > rvalue; pos--) {
        if (IS_SOEXT(pos) || IS_DLEXT(pos)) {
            *pos = '\0';
            return;
        }
    }
}

static void
escaped_basename(char *path, char *fname, char *rvalue)
{
    char *pos, *leaf, *found;
    leaf = path;
    // `leaf + 1` looks uncomfortable (when leaf == path), but fname must not be the top-dir itself
    while ((found = strstr(leaf + 1, fname)) != NULL) {
        leaf = found; // find the last occurrence for the path like /etc/my-crazy-lib-dir/etc.so
    }
    strcpy(rvalue, leaf);
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

    fname_without_suffix(fname_ptr, fname2);
    escaped_basename(src_path, fname2, basename);

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

static void
namespace_push(rb_thread_t *th, VALUE namespace)
{
    if (RTEST(th->namespaces)) {
        rb_ary_push(th->namespaces, namespace);
    }
    else {
        th->namespaces = rb_ary_new_from_args(1, namespace);
    }
    th->ns = rb_get_namespace_t(namespace);
}

static VALUE
namespace_pop(VALUE th_value)
{
    VALUE upper_ns;
    long stack_len;
    rb_thread_t *th = (rb_thread_t *)th_value;
    VALUE namespaces = th->namespaces;
    if (!namespaces) {
        rb_bug("Too many namespace pops");
    }
    rb_ary_pop(namespaces);
    stack_len = RARRAY_LEN(namespaces);
    if (stack_len == 0) {
        th->namespaces = 0;
        th->ns = main_namespace;
    }
    else {
        upper_ns = RARRAY_AREF(namespaces, stack_len-1);
        th->ns = rb_get_namespace_t(upper_ns);
    }
    return Qnil;
}

VALUE
rb_namespace_exec(const rb_namespace_t *ns, namespace_exec_func *func, VALUE arg)
{
    rb_thread_t *th = GET_THREAD();
    namespace_push(th, ns ? ns->ns_object : Qnil);
    return rb_ensure(func, arg, namespace_pop, (VALUE)th);
}

struct namespace_pop2_arg {
    rb_thread_t *th;
    rb_namespace_t *ns;
};

static VALUE
namespace_both_pop(VALUE arg)
{
    struct namespace_pop2_arg *data = (struct namespace_pop2_arg *)arg;
    namespace_pop((VALUE) data->th);
    rb_namespace_pop_loading_namespace(data->ns);
    return Qnil;
}

static VALUE
rb_namespace_load(int argc, VALUE *argv, VALUE namespace)
{
    VALUE fname, wrap;
    rb_thread_t *th = GET_THREAD();
    rb_namespace_t *ns = rb_get_namespace_t(namespace);

    rb_scan_args(argc, argv, "11", &fname, &wrap);

    VALUE args = rb_ary_new_from_args(2, fname, wrap);
    namespace_push(th, namespace);
    rb_namespace_push_loading_namespace(ns);
    struct namespace_pop2_arg arg = {
        .th = th,
        .ns = ns
    };
    return rb_ensure(rb_load_entrypoint, args, namespace_both_pop, (VALUE)&arg);
}

static VALUE
rb_namespace_require(VALUE namespace, VALUE fname)
{
    rb_thread_t *th = GET_THREAD();
    rb_namespace_t *ns = rb_get_namespace_t(namespace);
    namespace_push(th, namespace);
    rb_namespace_push_loading_namespace(ns);
    struct namespace_pop2_arg arg = {
        .th = th,
        .ns = ns
    };
    return rb_ensure(rb_require_string, fname, namespace_both_pop, (VALUE)&arg);
}

static VALUE
rb_namespace_require_relative(VALUE namespace, VALUE fname)
{
    rb_thread_t *th = GET_THREAD();
    rb_namespace_t *ns = rb_get_namespace_t(namespace);
    namespace_push(th, namespace);
    rb_namespace_push_loading_namespace(ns);
    struct namespace_pop2_arg arg = {
        .th = th,
        .ns = ns
    };
    return rb_ensure(rb_require_relative_entrypoint, fname, namespace_both_pop, (VALUE)&arg);
}

static int namespace_experimental_warned = 0;

void
rb_initialize_main_namespace(void)
{
    rb_namespace_t *ns;
    rb_vm_t *vm = GET_VM();
    rb_thread_t *th = GET_THREAD();
    VALUE main_ns;

    if (!namespace_experimental_warned) {
        rb_category_warn(RB_WARN_CATEGORY_EXPERIMENTAL,
                         "Namespace is experimental, and the behavior may change in the future!\n"
                         "See doc/namespace.md for known issues, etc.");
        namespace_experimental_warned = 1;
    }

    main_ns = rb_class_new_instance_pass_kw(0, NULL, rb_cNamespace);
    ns = rb_get_namespace_t(main_ns);
    ns->ns_object = main_ns;
    ns->ns_id = namespace_generate_id();
    ns->is_builtin = false;
    ns->is_user = true;
    ns->is_optional = false;

    rb_const_set(rb_cNamespace, rb_intern("MAIN"), main_ns);

    vm->main_namespace = th->ns = main_namespace = ns;
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
    if (NAMESPACE_BUILTIN_P(ns)) {
        rb_str_cat_cstr(r, ",builtin");
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

struct refiner_calling_super_data {
    int argc;
    VALUE *argv;
};

static VALUE
namespace_builtin_refiner_calling_super(VALUE arg)
{
    struct refiner_calling_super_data *data = (struct refiner_calling_super_data *)arg;
    return rb_call_super(data->argc, data->argv);
}

static VALUE
namespace_builtin_refiner_loading_func_ensure(VALUE _)
{
    rb_vm_t *vm = GET_VM();
    if (!vm->require_stack)
        rb_bug("require_stack is not ready but the namespace refiner is called");
    rb_namespace_disable_builtin();
    return Qnil;
}

static VALUE
rb_namespace_builtin_refiner_loading_func(int argc, VALUE *argv, VALUE _self)
{
    rb_vm_t *vm = GET_VM();
    if (!vm->require_stack)
        rb_bug("require_stack is not ready but the namespace refiner is called");
    rb_namespace_enable_builtin();
    // const rb_namespace_t *ns = rb_loading_namespace();
    // printf("N:current loading ns: %ld\n", ns->ns_id);
    struct refiner_calling_super_data data = {
        .argc = argc,
        .argv = argv
    };
    return rb_ensure(namespace_builtin_refiner_calling_super, (VALUE)&data,
                     namespace_builtin_refiner_loading_func_ensure, Qnil);
}

static void
setup_builtin_refinement(VALUE mod)
{
    struct rb_refinements_data data;
    rb_refinement_setup(&data, mod, rb_mKernel);
    rb_define_method(data.refinement, "require", rb_namespace_builtin_refiner_loading_func, -1);
    rb_define_method(data.refinement, "require_relative", rb_namespace_builtin_refiner_loading_func, -1);
    rb_define_method(data.refinement, "load", rb_namespace_builtin_refiner_loading_func, -1);
}

static VALUE
namespace_user_loading_func_calling_super(VALUE arg)
{
    struct refiner_calling_super_data *data = (struct refiner_calling_super_data *)arg;
    return rb_call_super(data->argc, data->argv);
}

static VALUE
namespace_user_loading_func_ensure(VALUE arg)
{
    rb_namespace_t *ns = (rb_namespace_t *)arg;
    rb_namespace_pop_loading_namespace(ns);
    return Qnil;
}

static VALUE
rb_namespace_user_loading_func(int argc, VALUE *argv, VALUE _self)
{
    const rb_namespace_t *ns;
    rb_vm_t *vm = GET_VM();
    if (!vm->require_stack)
        rb_bug("require_stack is not ready but require/load is called in user namespaces");
    ns = rb_current_namespace();
    VM_ASSERT(rb_namespace_available() || !ns);
    rb_namespace_push_loading_namespace(ns);
    struct refiner_calling_super_data data = {
        .argc = argc,
        .argv = argv
    };
    return rb_ensure(namespace_user_loading_func_calling_super, (VALUE)&data,
                     namespace_user_loading_func_ensure, (VALUE)ns);
}

static VALUE
setup_pushing_loading_namespace_include(VALUE mod)
{
    rb_include_module(rb_cObject, mod);
    return Qnil;
}

static void
setup_pushing_loading_namespace(rb_namespace_t *ns)
{
    rb_namespace_exec(ns, setup_pushing_loading_namespace_include, rb_mNamespaceLoader);
}

static void
namespace_define_loader_method(const char *name)
{
    rb_define_private_method(rb_mNamespaceLoader, name, rb_namespace_user_loading_func, -1);
    rb_define_singleton_method(rb_mNamespaceLoader, name, rb_namespace_user_loading_func, -1);
}

void
Init_Namespace(void)
{
    tmp_dir = system_tmpdir();
    tmp_dir_has_dirsep = (strcmp(tmp_dir + (strlen(tmp_dir) - strlen(DIRSEP)), DIRSEP) == 0);

    rb_cNamespace = rb_define_class("Namespace", rb_cModule);
    rb_define_method(rb_cNamespace, "initialize", namespace_initialize, 0);

    rb_cNamespaceEntry = rb_define_class_under(rb_cNamespace, "Entry", rb_cObject);
    rb_define_alloc_func(rb_cNamespaceEntry, rb_namespace_entry_alloc);

    rb_mNamespaceRefiner = rb_define_module_under(rb_cNamespace, "Refiner");
    if (rb_namespace_available()) {
        setup_builtin_refinement(rb_mNamespaceRefiner);
    }

    rb_mNamespaceLoader = rb_define_module_under(rb_cNamespace, "Loader");
    namespace_define_loader_method("require");
    namespace_define_loader_method("require_relative");
    namespace_define_loader_method("load");

    rb_define_singleton_method(rb_cNamespace, "enabled?", rb_namespace_s_getenabled, 0);
    rb_define_singleton_method(rb_cNamespace, "current", rb_namespace_current, 0);
    rb_define_singleton_method(rb_cNamespace, "is_builtin?", rb_namespace_s_is_builtin_p, 1);

    rb_define_method(rb_cNamespace, "load_path", rb_namespace_load_path, 0);
    rb_define_method(rb_cNamespace, "load", rb_namespace_load, -1);
    rb_define_method(rb_cNamespace, "require", rb_namespace_require, 1);
    rb_define_method(rb_cNamespace, "require_relative", rb_namespace_require_relative, 1);

    rb_define_method(rb_cNamespace, "inspect", rb_namespace_inspect, 0);

    rb_vm_t *vm = GET_VM();
    vm->require_stack = rb_ary_new();
}
