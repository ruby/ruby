/*
 * load methods from eval.c
 */

#include "dln.h"
#include "eval_intern.h"
#include "internal.h"
#include "internal/dir.h"
#include "internal/error.h"
#include "internal/file.h"
#include "internal/hash.h"
#include "internal/load.h"
#include "internal/ruby_parser.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "iseq.h"
#include "probes.h"
#include "darray.h"
#include "ruby/encoding.h"
#include "ruby/util.h"

static VALUE ruby_dln_libmap;

#define IS_RBEXT(e) (strcmp((e), ".rb") == 0)
#define IS_SOEXT(e) (strcmp((e), ".so") == 0 || strcmp((e), ".o") == 0)
#define IS_DLEXT(e) (strcmp((e), DLEXT) == 0)

#if SIZEOF_VALUE <= SIZEOF_LONG
# define SVALUE2NUM(x) LONG2NUM((long)(x))
# define NUM2SVALUE(x) (SIGNED_VALUE)NUM2LONG(x)
#elif SIZEOF_VALUE <= SIZEOF_LONG_LONG
# define SVALUE2NUM(x) LL2NUM((LONG_LONG)(x))
# define NUM2SVALUE(x) (SIGNED_VALUE)NUM2LL(x)
#else
# error Need integer for VALUE
#endif

enum {
    loadable_ext_rb = (0+ /* .rb extension is the first in both tables */
                       1) /* offset by rb_find_file_ext() */
};

static const char *const loadable_ext[] = {
    ".rb", DLEXT,
    0
};

static const char *const ruby_ext[] = {
    ".rb",
    0
};

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
rb_construct_expanded_load_path(rb_vm_t *vm, enum expand_type type, int *has_relative, int *has_non_cache)
{
    VALUE load_path = vm->load_path;
    VALUE expanded_load_path = vm->expanded_load_path;
    VALUE ary;
    long i;

    ary = rb_ary_hidden_new(RARRAY_LEN(load_path));
    for (i = 0; i < RARRAY_LEN(load_path); ++i) {
        VALUE path, as_str, expanded_path;
        int is_string, non_cache;
        char *as_cstr;
        as_str = path = RARRAY_AREF(load_path, i);
        is_string = RB_TYPE_P(path, T_STRING) ? 1 : 0;
        non_cache = !is_string ? 1 : 0;
        as_str = rb_get_path_check_to_string(path);
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
        as_str = rb_get_path_check_convert(as_str);
        expanded_path = rb_check_realpath(Qnil, as_str, NULL);
        if (NIL_P(expanded_path)) expanded_path = as_str;
        rb_ary_push(ary, rb_fstring(expanded_path));
    }
    rb_obj_freeze(ary);
    vm->expanded_load_path = ary;
    rb_ary_replace(vm->load_path_snapshot, vm->load_path);
}

static VALUE
get_expanded_load_path(rb_vm_t *vm)
{
    const VALUE non_cache = Qtrue;

    if (!rb_ary_shared_with_p(vm->load_path_snapshot, vm->load_path)) {
        /* The load path was modified. Rebuild the expanded load path. */
        int has_relative = 0, has_non_cache = 0;
        rb_construct_expanded_load_path(vm, EXPAND_ALL, &has_relative, &has_non_cache);
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
        rb_construct_expanded_load_path(vm, EXPAND_NON_CACHE,
                                        &has_relative, &has_non_cache);
    }
    else if (vm->load_path_check_cache) {
        int has_relative = 1, has_non_cache = 1;
        VALUE cwd = rb_dir_getwd_ospath();
        if (!rb_str_equal(vm->load_path_check_cache, cwd)) {
            /* Current working directory or filesystem encoding was changed.
               Expand relative load path and non-cacheable objects again. */
            vm->load_path_check_cache = cwd;
            rb_construct_expanded_load_path(vm, EXPAND_RELATIVE,
                                            &has_relative, &has_non_cache);
        }
        else {
            /* Expand only tilde (User HOME) and non-cacheable objects. */
            rb_construct_expanded_load_path(vm, EXPAND_HOME,
                                            &has_relative, &has_non_cache);
        }
    }
    return vm->expanded_load_path;
}

VALUE
rb_get_expanded_load_path(void)
{
    return get_expanded_load_path(GET_VM());
}

static VALUE
load_path_getter(ID id, VALUE * p)
{
    rb_vm_t *vm = (void *)p;
    return vm->load_path;
}

static VALUE
get_loaded_features(rb_vm_t *vm)
{
    return vm->loaded_features;
}

static VALUE
get_loaded_features_realpaths(rb_vm_t *vm)
{
    return vm->loaded_features_realpaths;
}

static VALUE
get_loaded_features_realpath_map(rb_vm_t *vm)
{
    return vm->loaded_features_realpath_map;
}

static VALUE
get_LOADED_FEATURES(ID _x, VALUE *_y)
{
    return get_loaded_features(GET_VM());
}

static void
reset_loaded_features_snapshot(rb_vm_t *vm)
{
    rb_ary_replace(vm->loaded_features_snapshot, vm->loaded_features);
}

static struct st_table *
get_loaded_features_index_raw(rb_vm_t *vm)
{
    return vm->loaded_features_index;
}

static st_table *
get_loading_table(rb_vm_t *vm)
{
    return vm->loading_table;
}

static st_data_t
feature_key(const char *str, size_t len)
{
    return st_hash(str, len, 0xfea7009e);
}

static bool
is_rbext_path(VALUE feature_path)
{
    long len = RSTRING_LEN(feature_path);
    long rbext_len = rb_strlen_lit(".rb");
    if (len <= rbext_len) return false;
    return IS_RBEXT(RSTRING_PTR(feature_path) + len - rbext_len);
}

typedef rb_darray(long) feature_indexes_t;

struct features_index_add_single_args {
    rb_vm_t *vm;
    VALUE offset;
    bool rb;
};

static int
features_index_add_single_callback(st_data_t *key, st_data_t *value, st_data_t raw_args, int existing)
{
    struct features_index_add_single_args *args = (struct features_index_add_single_args *)raw_args;
    rb_vm_t *vm = args->vm;
    VALUE offset = args->offset;
    bool rb = args->rb;

    if (existing) {
        VALUE this_feature_index = *value;

        if (FIXNUM_P(this_feature_index)) {
            VALUE loaded_features = get_loaded_features(vm);
            VALUE this_feature_path = RARRAY_AREF(loaded_features, FIX2LONG(this_feature_index));

            feature_indexes_t feature_indexes;
            rb_darray_make(&feature_indexes, 2);
            int top = (rb && !is_rbext_path(this_feature_path)) ? 1 : 0;
            rb_darray_set(feature_indexes, top^0, FIX2LONG(this_feature_index));
            rb_darray_set(feature_indexes, top^1, FIX2LONG(offset));

            assert(rb_darray_size(feature_indexes) == 2);
            // assert feature_indexes does not look like a special const
            assert(!SPECIAL_CONST_P((VALUE)feature_indexes));

            *value = (st_data_t)feature_indexes;
        }
        else {
            feature_indexes_t feature_indexes = (feature_indexes_t)this_feature_index;
            long pos = -1;

            if (rb) {
                VALUE loaded_features = get_loaded_features(vm);
                for (size_t i = 0; i < rb_darray_size(feature_indexes); ++i) {
                    long idx = rb_darray_get(feature_indexes, i);
                    VALUE this_feature_path = RARRAY_AREF(loaded_features, idx);
                    Check_Type(this_feature_path, T_STRING);
                    if (!is_rbext_path(this_feature_path)) {
                        pos = i;
                        break;
                    }
                }
            }

            rb_darray_append(&feature_indexes, FIX2LONG(offset));
            /* darray may realloc which will change the pointer */
            *value = (st_data_t)feature_indexes;

            if (pos >= 0) {
                long *ptr = rb_darray_data_ptr(feature_indexes);
                long len = rb_darray_size(feature_indexes);
                MEMMOVE(ptr + pos, ptr + pos + 1, long, len - pos - 1);
                ptr[pos] = FIX2LONG(offset);
            }
        }
    }
    else {
        *value = offset;
    }

    return ST_CONTINUE;
}

static void
features_index_add_single(rb_vm_t *vm, const char* str, size_t len, VALUE offset, bool rb)
{
    struct st_table *features_index;
    st_data_t short_feature_key;

    Check_Type(offset, T_FIXNUM);
    short_feature_key = feature_key(str, len);

    features_index = get_loaded_features_index_raw(vm);

    struct features_index_add_single_args args = {
        .vm = vm,
        .offset = offset,
        .rb = rb,
    };

    st_update(features_index, short_feature_key, features_index_add_single_callback, (st_data_t)&args);
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
features_index_add(rb_vm_t *vm, VALUE feature, VALUE offset)
{
    const char *feature_str, *feature_end, *ext, *p;
    bool rb = false;

    feature_str = StringValuePtr(feature);
    feature_end = feature_str + RSTRING_LEN(feature);

    for (ext = feature_end; ext > feature_str; ext--)
        if (*ext == '.' || *ext == '/')
            break;
    if (*ext != '.')
        ext = NULL;
    else
        rb = IS_RBEXT(ext);
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
        features_index_add_single(vm, p + 1, feature_end - p - 1, offset, false);
        if (ext) {
            features_index_add_single(vm, p + 1, ext - p - 1, offset, rb);
        }
    }
    features_index_add_single(vm, feature_str, feature_end - feature_str, offset, false);
    if (ext) {
        features_index_add_single(vm, feature_str, ext - feature_str, offset, rb);
    }
}

static int
loaded_features_index_clear_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE obj = (VALUE)val;
    if (!SPECIAL_CONST_P(obj)) {
        rb_darray_free((void *)obj);
    }
    return ST_DELETE;
}

void
rb_free_loaded_features_index(rb_vm_t *vm)
{
    st_foreach(vm->loaded_features_index, loaded_features_index_clear_i, 0);
    st_free_table(vm->loaded_features_index);
}

static st_table *
get_loaded_features_index(rb_vm_t *vm)
{
    VALUE features;
    int i;

    if (!rb_ary_shared_with_p(vm->loaded_features_snapshot, vm->loaded_features)) {
        /* The sharing was broken; something (other than us in rb_provide_feature())
           modified loaded_features.  Rebuild the index. */
        st_foreach(vm->loaded_features_index, loaded_features_index_clear_i, 0);

        VALUE realpaths = vm->loaded_features_realpaths;
        VALUE realpath_map = vm->loaded_features_realpath_map;
        VALUE previous_realpath_map = rb_hash_dup(realpath_map);
        rb_hash_clear(realpaths);
        rb_hash_clear(realpath_map);
        features = vm->loaded_features;
        for (i = 0; i < RARRAY_LEN(features); i++) {
            VALUE entry, as_str;
            as_str = entry = rb_ary_entry(features, i);
            StringValue(as_str);
            as_str = rb_fstring(as_str);
            if (as_str != entry)
                rb_ary_store(features, i, as_str);
            features_index_add(vm, as_str, INT2FIX(i));
        }
        reset_loaded_features_snapshot(vm);

        features = rb_ary_dup(vm->loaded_features_snapshot);
        long j = RARRAY_LEN(features);
        for (i = 0; i < j; i++) {
            VALUE as_str = rb_ary_entry(features, i);
            VALUE realpath = rb_hash_aref(previous_realpath_map, as_str);
            if (NIL_P(realpath)) {
                realpath = rb_check_realpath(Qnil, as_str, NULL);
                if (NIL_P(realpath)) realpath = as_str;
                realpath = rb_fstring(realpath);
            }
            rb_hash_aset(realpaths, realpath, Qtrue);
            rb_hash_aset(realpath_map, as_str, realpath);
        }
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

/*
 * Returns the type of already provided feature.
 * 'r': ruby script (".rb")
 * 's': shared object (".so"/"."DLEXT)
 * 'u': unsuffixed
 */
static int
rb_feature_p(rb_vm_t *vm, const char *feature, const char *ext, int rb, int expanded, const char **fn)
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
    features = get_loaded_features(vm);
    features_index = get_loaded_features_index(vm);

    key = feature_key(feature, strlen(feature));
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
    if (st_lookup(features_index, key, &data) && !NIL_P(this_feature_index = (VALUE)data)) {
        for (size_t i = 0; ; i++) {
            long index;
            if (FIXNUM_P(this_feature_index)) {
                if (i > 0) break;
                index = FIX2LONG(this_feature_index);
            }
            else {
                feature_indexes_t feature_indexes = (feature_indexes_t)this_feature_index;
                if (i >= rb_darray_size(feature_indexes)) break;
                index = rb_darray_get(feature_indexes, i);
            }

            v = RARRAY_AREF(features, index);
            f = StringValuePtr(v);
            if ((n = RSTRING_LEN(v)) < len) continue;
            if (strncmp(f, feature, len) != 0) {
                if (expanded) continue;
                if (!load_path) load_path = get_expanded_load_path(vm);
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

    loading_tbl = get_loading_table(vm);
    f = 0;
    if (!expanded) {
        struct loaded_feature_searching fs;
        fs.name = feature;
        fs.len = len;
        fs.type = type;
        fs.load_path = load_path ? load_path : get_expanded_load_path(vm);
        fs.result = 0;
        st_foreach(loading_tbl, loaded_feature_path_i, (st_data_t)&fs);
        if ((f = fs.result) != 0) {
            if (fn) *fn = f;
            goto loading;
        }
    }
    if (st_get_key(loading_tbl, (st_data_t)feature, &data)) {
        if (fn) *fn = (const char*)data;
        goto loading;
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

  loading:
    if (!ext) return 'u';
    return !IS_RBEXT(ext) ? 's' : 'r';
}

int
rb_provided(const char *feature)
{
    return rb_feature_provided(feature, 0);
}

static int
feature_provided(rb_vm_t *vm, const char *feature, const char **loading)
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
            if (rb_feature_p(vm, feature, ext, TRUE, FALSE, loading)) return TRUE;
            return FALSE;
        }
        else if (IS_SOEXT(ext) || IS_DLEXT(ext)) {
            if (rb_feature_p(vm, feature, ext, FALSE, FALSE, loading)) return TRUE;
            return FALSE;
        }
    }
    if (rb_feature_p(vm, feature, 0, TRUE, FALSE, loading))
        return TRUE;
    RB_GC_GUARD(fullpath);
    return FALSE;
}

int
rb_feature_provided(const char *feature, const char **loading)
{
    return feature_provided(GET_VM(), feature, loading);
}

static void
rb_provide_feature(rb_vm_t *vm, VALUE feature)
{
    VALUE features;

    features = get_loaded_features(vm);
    if (OBJ_FROZEN(features)) {
        rb_raise(rb_eRuntimeError,
                 "$LOADED_FEATURES is frozen; cannot append feature");
    }
    feature = rb_fstring(feature);

    get_loaded_features_index(vm);
    // If loaded_features and loaded_features_snapshot share the same backing
    // array, pushing into it would cause the whole array to be copied.
    // To avoid this we first clear loaded_features_snapshot.
    rb_ary_clear(vm->loaded_features_snapshot);
    rb_ary_push(features, feature);
    features_index_add(vm, feature, INT2FIX(RARRAY_LEN(features)-1));
    reset_loaded_features_snapshot(vm);
}

void
rb_provide(const char *feature)
{
    rb_provide_feature(GET_VM(), rb_fstring_cstr(feature));
}

NORETURN(static void load_failed(VALUE));

static inline VALUE
realpath_internal_cached(VALUE hash, VALUE path)
{
    VALUE ret = rb_hash_aref(hash, path);
    if(RTEST(ret)) {
        return ret;
    }

    VALUE realpath = rb_realpath_internal(Qnil, path, 1);
    rb_hash_aset(hash, rb_fstring(path), rb_fstring(realpath));
    return realpath;
}

static inline void
load_iseq_eval(rb_execution_context_t *ec, VALUE fname)
{
    const rb_iseq_t *iseq = rb_iseq_load_iseq(fname);

    if (!iseq) {
        if (*rb_ruby_prism_ptr()) {
            pm_string_t input;
            pm_options_t options = { 0 };

            pm_string_mapped_init(&input, RSTRING_PTR(fname));
            pm_options_filepath_set(&options, RSTRING_PTR(fname));

            pm_parser_t parser;
            pm_parser_init(&parser, pm_string_source(&input), pm_string_length(&input), &options);

            iseq = rb_iseq_new_main_prism(&input, &options, fname);

            pm_string_free(&input);
            pm_options_free(&options);
        }
        else {
            rb_execution_context_t *ec = GET_EC();
            VALUE v = rb_vm_push_frame_fname(ec, fname);
            rb_ast_t *ast;
            VALUE parser = rb_parser_new();
            rb_parser_set_context(parser, NULL, FALSE);
            ast = (rb_ast_t *)rb_parser_load_file(parser, fname);

            rb_thread_t *th = rb_ec_thread_ptr(ec);
            VALUE realpath_map = get_loaded_features_realpath_map(th->vm);

            iseq = rb_iseq_new_top(&ast->body, rb_fstring_lit("<top (required)>"),
                                   fname, realpath_internal_cached(realpath_map, fname), NULL);
            rb_ast_dispose(ast);
            rb_vm_pop_frame(ec);
            RB_GC_GUARD(v);
        }
    }
    rb_exec_event_hook_script_compiled(ec, iseq, Qnil);
    rb_iseq_eval(iseq);
}

static inline enum ruby_tag_type
load_wrapping(rb_execution_context_t *ec, VALUE fname, VALUE load_wrapper)
{
    enum ruby_tag_type state;
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    volatile VALUE wrapper = th->top_wrapper;
    volatile VALUE self = th->top_self;
#if !defined __GNUC__
    rb_thread_t *volatile th0 = th;
#endif

    ec->errinfo = Qnil; /* ensure */

    /* load in module as toplevel */
    th->top_self = rb_obj_clone(rb_vm_top_self());
    th->top_wrapper = load_wrapper;
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
rb_load_internal(VALUE fname, VALUE wrap)
{
    rb_execution_context_t *ec = GET_EC();
    enum ruby_tag_type state = TAG_NONE;
    if (RTEST(wrap)) {
        if (!RB_TYPE_P(wrap, T_MODULE)) {
            wrap = rb_module_new();
        }
        state = load_wrapping(ec, fname, wrap);
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
    rb_load_internal(tmp, RBOOL(wrap));
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
 *  Loads and executes the Ruby program in the file _filename_.
 *
 *  If the filename is an absolute path (e.g. starts with '/'), the file
 *  will be loaded directly using the absolute path.
 *
 *  If the filename is an explicit relative path (e.g. starts with './' or
 *  '../'), the file will be loaded using the relative path from the current
 *  directory.
 *
 *  Otherwise, the file will be searched for in the library
 *  directories listed in <code>$LOAD_PATH</code> (<code>$:</code>).
 *  If the file is found in a directory, it will attempt to load the file
 *  relative to that directory.  If the file is not found in any of the
 *  directories in <code>$LOAD_PATH</code>, the file will be loaded using
 *  the relative path from the current directory.
 *
 *  If the file doesn't exist when there is an attempt to load it, a
 *  LoadError will be raised.
 *
 *  If the optional _wrap_ parameter is +true+, the loaded script will
 *  be executed under an anonymous module, protecting the calling
 *  program's global namespace.  If the optional _wrap_ parameter is a
 *  module, the loaded script will be executed under the given module.
 *  In no circumstance will any local variables in the loaded file be
 *  propagated to the loading environment.
 */

static VALUE
rb_f_load(int argc, VALUE *argv, VALUE _)
{
    VALUE fname, wrap, path, orig_fname;

    rb_scan_args(argc, argv, "11", &fname, &wrap);

    orig_fname = rb_get_path_check_to_string(fname);
    fname = rb_str_encode_ospath(orig_fname);
    RUBY_DTRACE_HOOK(LOAD_ENTRY, RSTRING_PTR(orig_fname));

    path = rb_find_file(fname);
    if (!path) {
        if (!rb_file_load_ok(RSTRING_PTR(fname)))
            load_failed(orig_fname);
        path = fname;
    }
    rb_load_internal(path, wrap);

    RUBY_DTRACE_HOOK(LOAD_RETURN, RSTRING_PTR(orig_fname));

    return Qtrue;
}

static char *
load_lock(rb_vm_t *vm, const char *ftptr, bool warn)
{
    st_data_t data;
    st_table *loading_tbl = get_loading_table(vm);

    if (!st_lookup(loading_tbl, (st_data_t)ftptr, &data)) {
        /* partial state */
        ftptr = ruby_strdup(ftptr);
        data = (st_data_t)rb_thread_shield_new();
        st_insert(loading_tbl, (st_data_t)ftptr, data);
        return (char *)ftptr;
    }

    if (warn && rb_thread_shield_owned((VALUE)data)) {
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
load_unlock(rb_vm_t *vm, const char *ftptr, int done)
{
    if (ftptr) {
        st_data_t key = (st_data_t)ftptr;
        st_table *loading_tbl = get_loading_table(vm);

        st_update(loading_tbl, key, release_thread_shield, done);
    }
}

static VALUE rb_require_string_internal(VALUE fname, bool resurrect);

/*
 *  call-seq:
 *     require(name)    -> true or false
 *
 *  Loads the given +name+, returning +true+ if successful and +false+ if the
 *  feature is already loaded.
 *
 *  If the filename neither resolves to an absolute path nor starts with
 *  './' or '../', the file will be searched for in the library
 *  directories listed in <code>$LOAD_PATH</code> (<code>$:</code>).
 *  If the filename starts with './' or '../', resolution is based on Dir.pwd.
 *
 *  If the filename has the extension ".rb", it is loaded as a source file; if
 *  the extension is ".so", ".o", or the default shared library extension on
 *  the current platform, Ruby loads the shared library as a Ruby extension.
 *  Otherwise, Ruby tries adding ".rb", ".so", and so on to the name until
 *  found.  If the file named cannot be found, a LoadError will be raised.
 *
 *  For Ruby extensions the filename given may use ".so" or ".o".  For example,
 *  on macOS the socket extension is "socket.bundle" and
 *  <code>require 'socket.so'</code> will load the socket extension.
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
    return rb_require_string(fname);
}

/*
 * call-seq:
 *   require_relative(string) -> true or false
 *
 * Ruby tries to load the library named _string_ relative to the directory
 * containing the requiring file.  If the file does not exist a LoadError is
 * raised. Returns +true+ if the file was loaded and +false+ if the file was
 * already loaded before.
 */
VALUE
rb_f_require_relative(VALUE obj, VALUE fname)
{
    VALUE base = rb_current_realfilepath();
    if (NIL_P(base)) {
        rb_loaderror("cannot infer basepath");
    }
    base = rb_file_dirname(base);
    return rb_require_string_internal(rb_file_absolute_path(fname, base), false);
}

typedef int (*feature_func)(rb_vm_t *vm, const char *feature, const char *ext, int rb, int expanded, const char **fn);

static int
search_required(rb_vm_t *vm, VALUE fname, volatile VALUE *path, feature_func rb_feature_p)
{
    VALUE tmp;
    char *ext, *ftptr;
    int ft = 0;
    const char *loading;

    *path = 0;
    ext = strrchr(ftptr = RSTRING_PTR(fname), '.');
    if (ext && !strchr(ext, '/')) {
        if (IS_RBEXT(ext)) {
            if (rb_feature_p(vm, ftptr, ext, TRUE, FALSE, &loading)) {
                if (loading) *path = rb_filesystem_str_new_cstr(loading);
                return 'r';
            }
            if ((tmp = rb_find_file(fname)) != 0) {
                ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
                if (!rb_feature_p(vm, ftptr, ext, TRUE, TRUE, &loading) || loading)
                    *path = tmp;
                return 'r';
            }
            return 0;
        }
        else if (IS_SOEXT(ext)) {
            if (rb_feature_p(vm, ftptr, ext, FALSE, FALSE, &loading)) {
                if (loading) *path = rb_filesystem_str_new_cstr(loading);
                return 's';
            }
            tmp = rb_str_subseq(fname, 0, ext - RSTRING_PTR(fname));
            rb_str_cat2(tmp, DLEXT);
            OBJ_FREEZE(tmp);
            if ((tmp = rb_find_file(tmp)) != 0) {
                ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
                if (!rb_feature_p(vm, ftptr, ext, FALSE, TRUE, &loading) || loading)
                    *path = tmp;
                return 's';
            }
        }
        else if (IS_DLEXT(ext)) {
            if (rb_feature_p(vm, ftptr, ext, FALSE, FALSE, &loading)) {
                if (loading) *path = rb_filesystem_str_new_cstr(loading);
                return 's';
            }
            if ((tmp = rb_find_file(fname)) != 0) {
                ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
                if (!rb_feature_p(vm, ftptr, ext, FALSE, TRUE, &loading) || loading)
                    *path = tmp;
                return 's';
            }
        }
    }
    else if ((ft = rb_feature_p(vm, ftptr, 0, FALSE, FALSE, &loading)) == 'r') {
        if (loading) *path = rb_filesystem_str_new_cstr(loading);
        return 'r';
    }
    tmp = fname;
    const unsigned int type = rb_find_file_ext(&tmp, ft == 's' ? ruby_ext : loadable_ext);

    // Check if it's a statically linked extension when
    // not already a feature and not found as a dynamic library.
    if (!ft && type != loadable_ext_rb && vm->static_ext_inits) {
        VALUE lookup_name = tmp;
        // Append ".so" if not already present so for example "etc" can find "etc.so".
        // We always register statically linked extensions with a ".so" extension.
        // See encinit.c and extinit.c (generated at build-time).
        if (!ext) {
            lookup_name = rb_str_dup(lookup_name);
            rb_str_cat_cstr(lookup_name, ".so");
        }
        ftptr = RSTRING_PTR(lookup_name);
        if (st_lookup(vm->static_ext_inits, (st_data_t)ftptr, NULL)) {
            *path = rb_filesystem_str_new_cstr(ftptr);
            return 's';
        }
    }

    switch (type) {
      case 0:
        if (ft)
            goto feature_present;
        ftptr = RSTRING_PTR(tmp);
        return rb_feature_p(vm, ftptr, 0, FALSE, TRUE, 0);

      default:
        if (ft) {
            goto feature_present;
        }
        /* fall through */
      case loadable_ext_rb:
        ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
        if (rb_feature_p(vm, ftptr, ext, type == loadable_ext_rb, TRUE, &loading) && !loading)
            break;
        *path = tmp;
    }
    return type > loadable_ext_rb ? 's' : 'r';

  feature_present:
    if (loading) *path = rb_filesystem_str_new_cstr(loading);
    return ft;
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

static bool
run_static_ext_init(rb_vm_t *vm, const char *feature)
{
    st_data_t key = (st_data_t)feature;
    st_data_t init_func;

    if (vm->static_ext_inits && st_delete(vm->static_ext_inits, &key, &init_func)) {
        ((void (*)(void))init_func)();
        return true;
    }
    return false;
}

static int
no_feature_p(rb_vm_t *vm, const char *feature, const char *ext, int rb, int expanded, const char **fn)
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

    fname = rb_get_path(fname);
    path = rb_str_encode_ospath(fname);
    found = search_required(GET_VM(), path, &path, no_feature_p);

    switch (found) {
      case 'r':
        sym = ID2SYM(rb_intern("rb"));
        break;
      case 's':
        sym = ID2SYM(rb_intern("so"));
        break;
      default:
        return Qnil;
    }

    return rb_ary_new_from_args(2, sym, path);
}

static void
ext_config_push(rb_thread_t *th, struct rb_ext_config *prev)
{
    *prev = th->ext_config;
    th->ext_config = (struct rb_ext_config){0};
}

static void
ext_config_pop(rb_thread_t *th, struct rb_ext_config *prev)
{
    th->ext_config = *prev;
}

void
rb_ext_ractor_safe(bool flag)
{
    GET_THREAD()->ext_config.ractor_safe = flag;
}

/*
 * returns
 *  0: if already loaded (false)
 *  1: successfully loaded (true)
 * <0: not found (LoadError)
 * >1: exception
 */
static int
require_internal(rb_execution_context_t *ec, VALUE fname, int exception, bool warn)
{
    volatile int result = -1;
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    volatile const struct {
        VALUE wrapper, self, errinfo;
        rb_execution_context_t *ec;
    } saved = {
        th->top_wrapper, th->top_self, ec->errinfo,
        ec,
    };
    enum ruby_tag_type state;
    char *volatile ftptr = 0;
    VALUE path;
    volatile VALUE saved_path;
    volatile VALUE realpath = 0;
    VALUE realpaths = get_loaded_features_realpaths(th->vm);
    VALUE realpath_map = get_loaded_features_realpath_map(th->vm);
    volatile bool reset_ext_config = false;
    struct rb_ext_config prev_ext_config;

    path = rb_str_encode_ospath(fname);
    RUBY_DTRACE_HOOK(REQUIRE_ENTRY, RSTRING_PTR(fname));
    saved_path = path;

    EC_PUSH_TAG(ec);
    ec->errinfo = Qnil; /* ensure */
    th->top_wrapper = 0;
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        VALUE handle;
        int found;

        RUBY_DTRACE_HOOK(FIND_REQUIRE_ENTRY, RSTRING_PTR(fname));
        found = search_required(th->vm, path, &saved_path, rb_feature_p);
        RUBY_DTRACE_HOOK(FIND_REQUIRE_RETURN, RSTRING_PTR(fname));
        path = saved_path;

        if (found) {
            if (!path || !(ftptr = load_lock(th->vm, RSTRING_PTR(path), warn))) {
                result = 0;
            }
            else if (!*ftptr) {
                result = TAG_RETURN;
            }
            else if (found == 's' && run_static_ext_init(th->vm, RSTRING_PTR(path))) {
                result = TAG_RETURN;
            }
            else if (RTEST(rb_hash_aref(realpaths,
                                        realpath = realpath_internal_cached(realpath_map, path)))) {
                result = 0;
            }
            else {
                switch (found) {
                  case 'r':
                    load_iseq_eval(ec, path);
                    break;

                  case 's':
                    reset_ext_config = true;
                    ext_config_push(th, &prev_ext_config);
                    handle = rb_vm_call_cfunc(rb_vm_top_self(), load_ext,
                                              path, VM_BLOCK_HANDLER_NONE, path);
                    rb_hash_aset(ruby_dln_libmap, path, SVALUE2NUM((SIGNED_VALUE)handle));
                    break;
                }
                result = TAG_RETURN;
            }
        }
    }
    EC_POP_TAG();

    ec = saved.ec;
    rb_thread_t *th2 = rb_ec_thread_ptr(ec);
    th2->top_self = saved.self;
    th2->top_wrapper = saved.wrapper;
    if (reset_ext_config) ext_config_pop(th2, &prev_ext_config);

    path = saved_path;
    if (ftptr) load_unlock(th2->vm, RSTRING_PTR(path), !state);

    if (state) {
        if (state == TAG_FATAL || state == TAG_THROW) {
            EC_JUMP_TAG(ec, state);
        }
        else if (exception) {
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

    if (result == TAG_RETURN) {
        rb_provide_feature(th2->vm, path);
        VALUE real = realpath;
        if (real) {
            real = rb_fstring(real);
            rb_hash_aset(realpaths, real, Qtrue);
        }
    }
    ec->errinfo = saved.errinfo;

    RUBY_DTRACE_HOOK(REQUIRE_RETURN, RSTRING_PTR(fname));

    return result;
}

int
rb_require_internal_silent(VALUE fname)
{
    rb_execution_context_t *ec = GET_EC();
    return require_internal(ec, fname, 1, false);
}

int
rb_require_internal(VALUE fname)
{
    rb_execution_context_t *ec = GET_EC();
    return require_internal(ec, fname, 1, RTEST(ruby_verbose));
}

int
ruby_require_internal(const char *fname, unsigned int len)
{
    struct RString fake;
    VALUE str = rb_setup_fake_str(&fake, fname, len, 0);
    rb_execution_context_t *ec = GET_EC();
    int result = require_internal(ec, str, 0, RTEST(ruby_verbose));
    rb_set_errinfo(Qnil);
    return result == TAG_RETURN ? 1 : result ? -1 : 0;
}

VALUE
rb_require_string(VALUE fname)
{
    return rb_require_string_internal(FilePathValue(fname), false);
}

static VALUE
rb_require_string_internal(VALUE fname, bool resurrect)
{
    rb_execution_context_t *ec = GET_EC();
    int result = require_internal(ec, fname, 1, RTEST(ruby_verbose));

    if (result > TAG_RETURN) {
        EC_JUMP_TAG(ec, result);
    }
    if (result < 0) {
        if (resurrect) fname = rb_str_resurrect(fname);
        load_failed(fname);
    }

    return RBOOL(result);
}

VALUE
rb_require(const char *fname)
{
    struct RString fake;
    VALUE str = rb_setup_fake_str(&fake, fname, strlen(fname), 0);
    return rb_require_string_internal(str, true);
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
        *value = (st_data_t)init;
    }
    return ST_CONTINUE;
}

// Private API for statically linked extensions.
// Used with the ext/Setup file, the --with-setup and
// --with-static-linked-ext configuration option, etc.
void
ruby_init_ext(const char *name, void (*init)(void))
{
    st_table *inits_table;
    rb_vm_t *vm = GET_VM();

    if (feature_provided(vm, name, 0))
        return;

    inits_table = vm->static_ext_inits;
    if (!inits_table) {
        inits_table = st_init_strtable();
        vm->static_ext_inits = inits_table;
    }
    st_update(inits_table, (st_data_t)name, register_init_ext, (st_data_t)init);
}

/*
 *  call-seq:
 *     mod.autoload(const, filename)   -> nil
 *
 *  Registers _filename_ to be loaded (using Kernel::require)
 *  the first time that _const_ (which may be a String or
 *  a symbol) is accessed in the namespace of _mod_.
 *
 *     module A
 *     end
 *     A.autoload(:B, "b")
 *     A::B.doit            # autoloads "b"
 *
 * If _const_ in _mod_ is defined as autoload, the file name to be
 * loaded is replaced with _filename_.  If _const_ is defined but not
 * as autoload, does nothing.
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
 *     autoload(const, filename)   -> nil
 *
 *  Registers _filename_ to be loaded (using Kernel::require)
 *  the first time that _const_ (which may be a String or
 *  a symbol) is accessed.
 *
 *     autoload(:MyModule, "/usr/local/lib/modules/my_module.rb")
 *
 * If _const_ is defined as autoload, the file name to be loaded is
 * replaced with _filename_.  If _const_ is defined but not as
 * autoload, does nothing.
 */

static VALUE
rb_f_autoload(VALUE obj, VALUE sym, VALUE file)
{
    VALUE klass = rb_class_real(rb_vm_cbase());
    if (!klass) {
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

void *
rb_ext_resolve_symbol(const char* fname, const char* symbol)
{
    VALUE handle;
    VALUE resolved;
    VALUE path;
    char *ext;
    VALUE fname_str = rb_str_new_cstr(fname);

    resolved = rb_resolve_feature_path((VALUE)NULL, fname_str);
    if (NIL_P(resolved)) {
        ext = strrchr(fname, '.');
        if (!ext || !IS_SOEXT(ext)) {
            rb_str_cat_cstr(fname_str, ".so");
        }
        if (rb_feature_p(GET_VM(), fname, 0, FALSE, FALSE, 0)) {
            return dln_symbol(NULL, symbol);
        }
        return NULL;
    }
    if (RARRAY_LEN(resolved) != 2 || rb_ary_entry(resolved, 0) != ID2SYM(rb_intern("so"))) {
        return NULL;
    }
    path = rb_ary_entry(resolved, 1);
    handle = rb_hash_lookup(ruby_dln_libmap, path);
    if (NIL_P(handle)) {
        return NULL;
    }
    return dln_symbol((void *)NUM2SVALUE(handle), symbol);
}

void
Init_load(void)
{
    rb_vm_t *vm = GET_VM();
    static const char var_load_path[] = "$:";
    ID id_load_path = rb_intern2(var_load_path, sizeof(var_load_path)-1);

    rb_define_hooked_variable(var_load_path, (VALUE*)vm, load_path_getter, rb_gvar_readonly_setter);
    rb_alias_variable(rb_intern_const("$-I"), id_load_path);
    rb_alias_variable(rb_intern_const("$LOAD_PATH"), id_load_path);
    vm->load_path = rb_ary_new();
    vm->expanded_load_path = rb_ary_hidden_new(0);
    vm->load_path_snapshot = rb_ary_hidden_new(0);
    vm->load_path_check_cache = 0;
    rb_define_singleton_method(vm->load_path, "resolve_feature_path", rb_resolve_feature_path, 1);

    rb_define_virtual_variable("$\"", get_LOADED_FEATURES, 0);
    rb_define_virtual_variable("$LOADED_FEATURES", get_LOADED_FEATURES, 0);
    vm->loaded_features = rb_ary_new();
    vm->loaded_features_snapshot = rb_ary_hidden_new(0);
    vm->loaded_features_index = st_init_numtable();
    vm->loaded_features_realpaths = rb_hash_new();
    rb_obj_hide(vm->loaded_features_realpaths);
    vm->loaded_features_realpath_map = rb_hash_new();
    rb_obj_hide(vm->loaded_features_realpath_map);

    rb_define_global_function("load", rb_f_load, -1);
    rb_define_global_function("require", rb_f_require, 1);
    rb_define_global_function("require_relative", rb_f_require_relative, 1);
    rb_define_method(rb_cModule, "autoload", rb_mod_autoload, 2);
    rb_define_method(rb_cModule, "autoload?", rb_mod_autoload_p, -1);
    rb_define_global_function("autoload", rb_f_autoload, 2);
    rb_define_global_function("autoload?", rb_f_autoload_p, -1);

    ruby_dln_libmap = rb_hash_new_with_size(0);
    rb_gc_register_mark_object(ruby_dln_libmap);
}
