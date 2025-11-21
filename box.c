/* indent-tabs-mode: nil */

#include "eval_intern.h"
#include "internal.h"
#include "internal/box.h"
#include "internal/class.h"
#include "internal/eval.h"
#include "internal/error.h"
#include "internal/file.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/load.h"
#include "internal/st.h"
#include "internal/variable.h"
#include "iseq.h"
#include "ruby/internal/globals.h"
#include "ruby/util.h"
#include "vm_core.h"
#include "darray.h"

#include <stdio.h>

VALUE rb_cBox = 0;
VALUE rb_cBoxEntry = 0;
VALUE rb_mBoxLoader = 0;

static rb_box_t root_box_data = {
    /* Initialize values lazily in Init_Box() */
    (VALUE)NULL, 0,
    (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL, (VALUE)NULL,
    (struct st_table *)NULL, (struct st_table *)NULL, (VALUE)NULL, (VALUE)NULL,
    false, false
};

static rb_box_t * root_box = &root_box_data;
static rb_box_t * main_box = 0;
static char *tmp_dir;
static bool tmp_dir_has_dirsep;

#define BOX_TMP_PREFIX "_ruby_box_"

#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif

#if defined(_WIN32)
# define DIRSEP "\\"
#else
# define DIRSEP "/"
#endif

bool ruby_box_enabled = false; // extern
bool ruby_box_init_done = false; // extern
bool ruby_box_crashed = false; // extern, changed only in vm.c

VALUE rb_resolve_feature_path(VALUE klass, VALUE fname);
static VALUE rb_box_inspect(VALUE obj);

void
rb_box_init_done(void)
{
    ruby_box_init_done = true;
}

const rb_box_t *
rb_root_box(void)
{
    return root_box;
}

const rb_box_t *
rb_main_box(void)
{
    return main_box;
}

const rb_box_t *
rb_current_box(void)
{
    /*
     * If RUBY_BOX is not set, the root box is the only available one.
     *
     * Until the main_box is not initialized, the root box is
     * the only valid box.
     * This early return is to avoid accessing EC before its setup.
     */
    if (!main_box)
        return root_box;

    return rb_vm_current_box(GET_EC());
}

const rb_box_t *
rb_loading_box(void)
{
    if (!main_box)
        return root_box;

    return rb_vm_loading_box(GET_EC());
}

const rb_box_t *
rb_current_box_in_crash_report(void)
{
    if (ruby_box_crashed)
        return NULL;
    return rb_current_box();
}

static long box_id_counter = 0;

static long
box_generate_id(void)
{
    long id;
    RB_VM_LOCKING() {
        id = ++box_id_counter;
    }
    return id;
}

static VALUE
box_main_to_s(VALUE obj)
{
    return rb_str_new2("main");
}

static void
box_entry_initialize(rb_box_t *box)
{
    const rb_box_t *root = rb_root_box();

    // These will be updated immediately
    box->box_object = 0;
    box->box_id = 0;

    box->top_self = rb_obj_alloc(rb_cObject);
    rb_define_singleton_method(box->top_self, "to_s", box_main_to_s, 0);
    rb_define_alias(rb_singleton_class(box->top_self), "inspect", "to_s");
    box->load_path = rb_ary_dup(root->load_path);
    box->expanded_load_path = rb_ary_dup(root->expanded_load_path);
    box->load_path_snapshot = rb_ary_new();
    box->load_path_check_cache = 0;
    box->loaded_features = rb_ary_dup(root->loaded_features);
    box->loaded_features_snapshot = rb_ary_new();
    box->loaded_features_index = st_init_numtable();
    box->loaded_features_realpaths = rb_hash_dup(root->loaded_features_realpaths);
    box->loaded_features_realpath_map = rb_hash_dup(root->loaded_features_realpath_map);
    box->loading_table = st_init_strtable();
    box->ruby_dln_libmap = rb_hash_new_with_size(0);
    box->gvar_tbl = rb_hash_new_with_size(0);

    box->is_user = true;
    box->is_optional = true;
}

void
rb_box_gc_update_references(void *ptr)
{
    rb_box_t *box = (rb_box_t *)ptr;
    if (!box) return;

    if (box->box_object)
        box->box_object = rb_gc_location(box->box_object);
    if (box->top_self)
        box->top_self = rb_gc_location(box->top_self);
    box->load_path = rb_gc_location(box->load_path);
    box->expanded_load_path = rb_gc_location(box->expanded_load_path);
    box->load_path_snapshot = rb_gc_location(box->load_path_snapshot);
    if (box->load_path_check_cache) {
        box->load_path_check_cache = rb_gc_location(box->load_path_check_cache);
    }
    box->loaded_features = rb_gc_location(box->loaded_features);
    box->loaded_features_snapshot = rb_gc_location(box->loaded_features_snapshot);
    box->loaded_features_realpaths = rb_gc_location(box->loaded_features_realpaths);
    box->loaded_features_realpath_map = rb_gc_location(box->loaded_features_realpath_map);
    box->ruby_dln_libmap = rb_gc_location(box->ruby_dln_libmap);
    box->gvar_tbl = rb_gc_location(box->gvar_tbl);
}

void
rb_box_entry_mark(void *ptr)
{
    const rb_box_t *box = (rb_box_t *)ptr;
    if (!box) return;

    rb_gc_mark(box->box_object);
    rb_gc_mark(box->top_self);
    rb_gc_mark(box->load_path);
    rb_gc_mark(box->expanded_load_path);
    rb_gc_mark(box->load_path_snapshot);
    rb_gc_mark(box->load_path_check_cache);
    rb_gc_mark(box->loaded_features);
    rb_gc_mark(box->loaded_features_snapshot);
    rb_gc_mark(box->loaded_features_realpaths);
    rb_gc_mark(box->loaded_features_realpath_map);
    if (box->loading_table) {
        rb_mark_tbl(box->loading_table);
    }
    rb_gc_mark(box->ruby_dln_libmap);
    rb_gc_mark(box->gvar_tbl);
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
box_root_free(void *ptr)
{
    rb_box_t *box = (rb_box_t *)ptr;
    if (box->loading_table) {
        st_foreach(box->loading_table, free_loading_table_entry, 0);
        st_free_table(box->loading_table);
        box->loading_table = 0;
    }

    if (box->loaded_features_index) {
        st_foreach(box->loaded_features_index, free_loaded_feature_index_i, 0);
        st_free_table(box->loaded_features_index);
    }
}

static void
box_entry_free(void *ptr)
{
    box_root_free(ptr);
    xfree(ptr);
}

static size_t
box_entry_memsize(const void *ptr)
{
    const rb_box_t *box = (const rb_box_t *)ptr;
    return sizeof(rb_box_t) + \
        rb_st_memsize(box->loaded_features_index) + \
        rb_st_memsize(box->loading_table);
}

const rb_data_type_t rb_box_data_type = {
    "Namespace::Entry",
    {
        rb_box_entry_mark,
        box_entry_free,
        box_entry_memsize,
        rb_box_gc_update_references,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY // TODO: enable RUBY_TYPED_WB_PROTECTED when inserting write barriers
};

const rb_data_type_t rb_root_box_data_type = {
    "Namespace::Root",
    {
        rb_box_entry_mark,
        box_root_free,
        box_entry_memsize,
        rb_box_gc_update_references,
    },
    &rb_box_data_type, 0, RUBY_TYPED_FREE_IMMEDIATELY // TODO: enable RUBY_TYPED_WB_PROTECTED when inserting write barriers
};

VALUE
rb_box_entry_alloc(VALUE klass)
{
    rb_box_t *entry;
    VALUE obj = TypedData_Make_Struct(klass, rb_box_t, &rb_box_data_type, entry);
    box_entry_initialize(entry);
    return obj;
}

static rb_box_t *
get_box_struct_internal(VALUE entry)
{
    rb_box_t *sval;
    TypedData_Get_Struct(entry, rb_box_t, &rb_box_data_type, sval);
    return sval;
}

rb_box_t *
rb_get_box_t(VALUE box)
{
    VALUE entry;
    ID id_box_entry;

    VM_ASSERT(box);

    if (NIL_P(box))
        return root_box;

    VM_ASSERT(BOX_OBJ_P(box));

    CONST_ID(id_box_entry, "__box_entry__");
    entry = rb_attr_get(box, id_box_entry);
    return get_box_struct_internal(entry);
}

VALUE
rb_get_box_object(rb_box_t *box)
{
    VM_ASSERT(box && box->box_object);
    return box->box_object;
}

/*
 *  call-seq:
 *    Namespace.new -> new_box
 *
 *  Returns a new Ruby::Box object.
 */
static VALUE
box_initialize(VALUE box_value)
{
    rb_box_t *box;
    rb_classext_t *object_classext;
    VALUE entry;
    ID id_box_entry;
    CONST_ID(id_box_entry, "__box_entry__");

    if (!rb_box_available()) {
        rb_raise(rb_eRuntimeError, "Ruby Box is disabled. Set RUBY_BOX=1 environment variable to use Ruby::Box.");
    }

    entry = rb_class_new_instance_pass_kw(0, NULL, rb_cBoxEntry);
    box = get_box_struct_internal(entry);

    box->box_object = box_value;
    box->box_id = box_generate_id();
    rb_define_singleton_method(box->load_path, "resolve_feature_path", rb_resolve_feature_path, 1);

    // Set the Ruby::Box object unique/consistent from any boxes to have just single
    // constant table from any view of every (including main) box.
    // If a code in the box adds a constant, the constant will be visible even from root/main.
    RCLASS_SET_PRIME_CLASSEXT_WRITABLE(box_value, true);

    // Get a clean constant table of Object even by writable one
    // because ns was just created, so it has not touched any constants yet.
    object_classext = RCLASS_EXT_WRITABLE_IN_BOX(rb_cObject, box);
    RCLASS_SET_CONST_TBL(box_value, RCLASSEXT_CONST_TBL(object_classext), true);

    rb_ivar_set(box_value, id_box_entry, entry);

    return box_value;
}

/*
 *  call-seq:
 *    Namespace.enabled? -> true or false
 *
 *  Returns +true+ if Ruby::Box is enabled.
 */
static VALUE
rb_box_s_getenabled(VALUE recv)
{
    return RBOOL(rb_box_available());
}

/*
 *  call-seq:
 *    Namespace.current -> box, nil or false
 *
 *  Returns the current box.
 *  Returns +nil+ if Ruby Box is not enabled.
 */
static VALUE
rb_box_s_current(VALUE recv)
{
    const rb_box_t *box;

    if (!rb_box_available())
        return Qnil;

    box = rb_vm_current_box(GET_EC());
    VM_ASSERT(box && box->box_object);
    return box->box_object;
}

/*
 *  call-seq:
 *    load_path -> array
 *
 *  Returns box local load path.
 */
static VALUE
rb_box_load_path(VALUE box)
{
    VM_ASSERT(BOX_OBJ_P(box));
    return rb_get_box_t(box)->load_path;
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
sprint_ext_filename(char *str, size_t size, long box_id, const char *prefix, const char *basename)
{
    if (tmp_dir_has_dirsep) {
        return snprintf(str, size, "%s%sp%"PRI_PIDT_PREFIX"u_%ld_%s", tmp_dir, prefix, getpid(), box_id, basename);
    }
    return snprintf(str, size, "%s%s%sp%"PRI_PIDT_PREFIX"u_%ld_%s", tmp_dir, DIRSEP, prefix, getpid(), box_id, basename);
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
copy_ext_file_error(char *message, size_t size, int copy_retvalue, const char *src_path, const char *dst_path)
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
copy_ext_file(const char *src_path, const char *dst_path)
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
rb_box_local_extension(VALUE box_value, VALUE fname, VALUE path)
{
    char ext_path[MAXPATHLEN], fname2[MAXPATHLEN], basename[MAXPATHLEN];
    int copy_error, wrote;
    const char *src_path = RSTRING_PTR(path), *fname_ptr = RSTRING_PTR(fname);
    rb_box_t *box = rb_get_box_t(box_value);

    fname_without_suffix(fname_ptr, fname2, sizeof(fname2));
    escaped_basename(src_path, fname2, basename, sizeof(basename));

    wrote = sprint_ext_filename(ext_path, sizeof(ext_path), box->box_id, BOX_TMP_PREFIX, basename);
    if (wrote >= (int)sizeof(ext_path)) {
        rb_bug("Extension file path in the box was too long");
    }
    copy_error = copy_ext_file(src_path, ext_path);
    if (copy_error) {
        char message[1024];
#if defined(_WIN32)
        copy_ext_file_error(message, sizeof(message));
#else
        copy_ext_file_error(message, sizeof(message), copy_error, src_path, ext_path);
#endif
        rb_raise(rb_eLoadError, "can't prepare the extension file for Ruby Box (%s from %s): %s", ext_path, src_path, message);
    }
    // TODO: register the path to be clean-uped
    return rb_str_new_cstr(ext_path);
}

// TODO: delete it just after dln_load? or delay it?
//       At least for _WIN32, deleting extension files should be delayed until the namespace's destructor.
//       And it requires calling dlclose before deleting it.

static VALUE
rb_box_load(int argc, VALUE *argv, VALUE box)
{
    VALUE fname, wrap;
    rb_scan_args(argc, argv, "11", &fname, &wrap);

    rb_vm_frame_flag_set_box_require(GET_EC());

    VALUE args = rb_ary_new_from_args(2, fname, wrap);
    return rb_load_entrypoint(args);
}

static VALUE
rb_box_require(VALUE box, VALUE fname)
{
    rb_vm_frame_flag_set_box_require(GET_EC());

    return rb_require_string(fname);
}

static VALUE
rb_box_require_relative(VALUE box, VALUE fname)
{
    rb_vm_frame_flag_set_box_require(GET_EC());

    return rb_require_relative_entrypoint(fname);
}

static void
initialize_root_box(void)
{
    VALUE root_box, entry;
    ID id_box_entry;
    rb_vm_t *vm = GET_VM();
    rb_box_t *root = (rb_box_t *)rb_root_box();

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

    vm->root_box = root;

    if (rb_box_available()) {
        CONST_ID(id_box_entry, "__box_entry__");

        root_box = rb_obj_alloc(rb_cBox);
        RCLASS_SET_PRIME_CLASSEXT_WRITABLE(root_box, true);
        RCLASS_SET_CONST_TBL(root_box, RCLASSEXT_CONST_TBL(RCLASS_EXT_PRIME(rb_cObject)), true);

        root->box_id = box_generate_id();
        root->box_object = root_box;

        entry = TypedData_Wrap_Struct(rb_cBoxEntry, &rb_root_box_data_type, root);
        rb_ivar_set(root_box, id_box_entry, entry);
    }
    else {
        root->box_id = 1;
        root->box_object = Qnil;
    }
}

static VALUE
rb_box_eval(VALUE box_value, VALUE str)
{
    const rb_iseq_t *iseq;
    const rb_box_t *box;

    StringValue(str);

    iseq = rb_iseq_compile_iseq(str, rb_str_new_cstr("eval"));
    VM_ASSERT(iseq);

    box = (const rb_box_t *)rb_get_box_t(box_value);

    return rb_iseq_eval(iseq, box);
}

static int box_experimental_warned = 0;

void
rb_initialize_main_box(void)
{
    rb_box_t *box;
    VALUE main_box_value;
    rb_vm_t *vm = GET_VM();

    VM_ASSERT(rb_box_available());

    if (!box_experimental_warned) {
        rb_category_warn(RB_WARN_CATEGORY_EXPERIMENTAL,
                         "Ruby::Box is experimental, and the behavior may change in the future!\n"
                         "See doc/box.md for known issues, etc.");
        box_experimental_warned = 1;
    }

    main_box_value = rb_class_new_instance(0, NULL, rb_cBox);
    VM_ASSERT(BOX_OBJ_P(main_box_value));
    box = rb_get_box_t(main_box_value);
    box->box_object = main_box_value;
    box->is_user = true;
    box->is_optional = false;

    rb_const_set(rb_cBox, rb_intern("MAIN"), main_box_value);

    vm->main_box = main_box = box;

    // create the writable classext of ::Object explicitly to finalize the set of visible top-level constants
    RCLASS_EXT_WRITABLE_IN_BOX(rb_cObject, box);
}

static VALUE
rb_box_inspect(VALUE obj)
{
    rb_box_t *box;
    VALUE r;
    if (obj == Qfalse) {
        r = rb_str_new_cstr("#<Namespace:root>");
        return r;
    }
    box = rb_get_box_t(obj);
    r = rb_str_new_cstr("#<Namespace:");
    rb_str_concat(r, rb_funcall(LONG2NUM(box->box_id), rb_intern("to_s"), 0));
    if (BOX_ROOT_P(box)) {
        rb_str_cat_cstr(r, ",root");
    }
    if (BOX_USER_P(box)) {
        rb_str_cat_cstr(r, ",user");
    }
    if (BOX_MAIN_P(box)) {
        rb_str_cat_cstr(r, ",main");
    }
    else if (BOX_OPTIONAL_P(box)) {
        rb_str_cat_cstr(r, ",optional");
    }
    rb_str_cat_cstr(r, ">");
    return r;
}

static VALUE
rb_box_loading_func(int argc, VALUE *argv, VALUE _self)
{
    rb_vm_frame_flag_set_box_require(GET_EC());
    return rb_call_super(argc, argv);
}

static void
box_define_loader_method(const char *name)
{
    rb_define_private_method(rb_mBoxLoader, name, rb_box_loading_func, -1);
    rb_define_singleton_method(rb_mBoxLoader, name, rb_box_loading_func, -1);
}

void
Init_root_box(void)
{
    root_box->loading_table = st_init_strtable();
}

void
Init_enable_box(void)
{
    const char *env = getenv("RUBY_BOX");
    if (env && strlen(env) == 1 && env[0] == '1') {
        ruby_box_enabled = true;
    }
    else {
        ruby_box_init_done = true;
    }
}

/* :nodoc: */
static VALUE
rb_box_s_root(VALUE recv)
{
    return root_box->box_object;
}

/* :nodoc: */
static VALUE
rb_box_s_main(VALUE recv)
{
    return main_box->box_object;
}

/* :nodoc: */
static VALUE
rb_box_root_p(VALUE box_value)
{
    const rb_box_t *box = (const rb_box_t *)rb_get_box_t(box_value);
    return RBOOL(BOX_ROOT_P(box));
}

/* :nodoc: */
static VALUE
rb_box_main_p(VALUE box_value)
{
    const rb_box_t *box = (const rb_box_t *)rb_get_box_t(box_value);
    return RBOOL(BOX_MAIN_P(box));
}

#if RUBY_DEBUG

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
dump_classext_i(rb_classext_t *ext, bool is_prime, VALUE _recv, void *data)
{
    char buf[4096];
    struct rb_id_table *tbl;
    VALUE ary, res = (VALUE)data;

    snprintf(buf, 4096, "Ruby::Box %ld:%s classext %p\n",
             RCLASSEXT_BOX(ext)->box_id, is_prime ? " prime" : "", (void *)ext);
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
     * Prime classext box(2,main), readable(t), writable(f)
     * Non-prime classexts: 3
     * Box 2: prime classext 0x88800933
     *   Super: Object
     *   Methods(43): aaaaa, bbbb, cccc, dddd, eeeee, ffff, gggg, hhhhh, ...
     *   Constants(12): FOO, Bar, ...
     * Box 5: classext 0x88800934
     *   Super: Object
     *   Methods(43): aaaaa, bbbb, cccc, dddd, eeeee, ffff, gggg, hhhhh, ...
     *   Constants(12): FOO, Bar, ...
     */
    char buf[2048];
    VALUE res;
    const rb_classext_t *ext;
    const rb_box_t *box;
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
    box = RCLASSEXT_BOX(ext);
    snprintf(buf, 2048, "Prime classext box(%ld,%s), readable(%s), writable(%s)\n",
             box->box_id,
             BOX_ROOT_P(box) ? "root" : (BOX_MAIN_P(box) ? "main" : "optional"),
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

#endif /* RUBY_DEBUG */

/*
 *  Document-class: Ruby::Box
 *
 *  Ruby::Box is designed to provide separated spaces in a Ruby
 *  process, to isolate applications and libraries.
 *  See {Ruby::Box}[rdoc-ref:box.md].
 */
void
Init_Box(void)
{
    tmp_dir = system_tmpdir();
    tmp_dir_has_dirsep = (strcmp(tmp_dir + (strlen(tmp_dir) - strlen(DIRSEP)), DIRSEP) == 0);

    VALUE mRuby = rb_path2class("Ruby");

    rb_cBox = rb_define_class_under(mRuby, "Box", rb_cModule);
    rb_define_method(rb_cBox, "initialize", box_initialize, 0);

    /* :nodoc: */
    rb_cBoxEntry = rb_define_class_under(rb_cBox, "Entry", rb_cObject);
    rb_define_alloc_func(rb_cBoxEntry, rb_box_entry_alloc);

    initialize_root_box();

    /* :nodoc: */
    rb_mBoxLoader = rb_define_module_under(rb_cBox, "Loader");
    box_define_loader_method("require");
    box_define_loader_method("require_relative");
    box_define_loader_method("load");

    if (rb_box_available()) {
        rb_include_module(rb_cObject, rb_mBoxLoader);

        rb_define_singleton_method(rb_cBox, "root", rb_box_s_root, 0);
        rb_define_singleton_method(rb_cBox, "main", rb_box_s_main, 0);
        rb_define_method(rb_cBox, "root?", rb_box_root_p, 0);
        rb_define_method(rb_cBox, "main?", rb_box_main_p, 0);

#if RUBY_DEBUG
        rb_define_global_function("dump_classext", rb_f_dump_classext, 1);
#endif
    }

    rb_define_singleton_method(rb_cBox, "enabled?", rb_box_s_getenabled, 0);
    rb_define_singleton_method(rb_cBox, "current", rb_box_s_current, 0);

    rb_define_method(rb_cBox, "load_path", rb_box_load_path, 0);
    rb_define_method(rb_cBox, "load", rb_box_load, -1);
    rb_define_method(rb_cBox, "require", rb_box_require, 1);
    rb_define_method(rb_cBox, "require_relative", rb_box_require_relative, 1);
    rb_define_method(rb_cBox, "eval", rb_box_eval, 1);

    rb_define_method(rb_cBox, "inspect", rb_box_inspect, 0);
}
