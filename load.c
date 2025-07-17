/*
 * load methods from eval.c
 */

#include "dln.h"
#include "eval_intern.h"
#include "internal.h"
#include "internal/dir.h"
#include "internal/error.h"
#include "internal/eval.h"
#include "internal/file.h"
#include "internal/hash.h"
#include "internal/load.h"
#include "internal/namespace.h"
#include "internal/ruby_parser.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "iseq.h"
#include "probes.h"
#include "darray.h"
#include "ruby/encoding.h"
#include "ruby/util.h"
#include "ractor_core.h"
#include "vm_core.h"

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

#define IS_NAMESPACE(obj) (CLASS_OF(obj) == rb_cNamespace)

struct vm_and_namespace_struct {
    rb_vm_t *vm;
    rb_namespace_t *ns;
};
typedef struct vm_and_namespace_struct vm_ns_t;
#define GET_vm_ns() vm_ns_t vm_ns_v = { .vm = GET_VM(), .ns = (rb_namespace_t *)rb_current_namespace(), }; vm_ns_t *vm_ns = &vm_ns_v;
#define GET_loading_vm_ns() vm_ns_t vm_ns_v = { .vm = GET_VM(), .ns = (rb_namespace_t *)rb_loading_namespace(), }; vm_ns_t *vm_ns = &vm_ns_v;

#define CURRENT_NS_attr(vm_ns, attr) (NAMESPACE_USER_P(vm_ns->ns) ? vm_ns->ns->attr : vm_ns->vm->attr)
#define SET_NS_attr(vm_ns, attr, value) do {                      \
    if (NAMESPACE_USER_P(vm_ns->ns)) { vm_ns->ns->attr = value; } \
    else { vm_ns->vm->attr = value; }                             \
} while (0)

#define SET_NS_LOAD_PATH_CHECK_CACHE(vm_ns, value) SET_NS_attr(vm_ns, load_path_check_cache, value)
#define SET_NS_EXPANDED_LOAD_PATH(vm_ns, value)    SET_NS_attr(vm_ns, expanded_load_path, value)

#define CURRENT_NS_LOAD_PATH(vm_ns)             CURRENT_NS_attr(vm_ns, load_path)
#define CURRENT_NS_LOAD_PATH_SNAPSHOT(vm_ns)    CURRENT_NS_attr(vm_ns, load_path_snapshot)
#define CURRENT_NS_LOAD_PATH_CHECK_CACHE(vm_ns) CURRENT_NS_attr(vm_ns, load_path_check_cache)
#define CURRENT_NS_EXPANDED_LOAD_PATH(vm_ns)    CURRENT_NS_attr(vm_ns, expanded_load_path)
#define CURRENT_NS_LOADING_TABLE(vm_ns)         CURRENT_NS_attr(vm_ns, loading_table)
#define CURRENT_NS_LOADED_FEATURES(vm_ns)       CURRENT_NS_attr(vm_ns, loaded_features)
#define CURRENT_NS_LOADED_FEATURES_SNAPSHOT(vm_ns)     CURRENT_NS_attr(vm_ns, loaded_features_snapshot)
#define CURRENT_NS_LOADED_FEATURES_REALPATHS(vm_ns)    CURRENT_NS_attr(vm_ns, loaded_features_realpaths)
#define CURRENT_NS_LOADED_FEATURES_REALPATH_MAP(vm_ns) CURRENT_NS_attr(vm_ns, loaded_features_realpath_map)
#define CURRENT_NS_LOADED_FEATURES_INDEX(vm_ns)        CURRENT_NS_attr(vm_ns, loaded_features_index)

#define CURRENT_NS_RUBY_DLN_LIBMAP(vm_ns, map) (NAMESPACE_USER_P(vm_ns->ns) ? vm_ns->ns->ruby_dln_libmap : map)

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
rb_construct_expanded_load_path(vm_ns_t *vm_ns, enum expand_type type, int *has_relative, int *has_non_cache)
{
    VALUE load_path = CURRENT_NS_LOAD_PATH(vm_ns);
    VALUE expanded_load_path = CURRENT_NS_EXPANDED_LOAD_PATH(vm_ns);
    VALUE snapshot;
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
    rb_ary_freeze(ary);
    SET_NS_EXPANDED_LOAD_PATH(vm_ns, ary);
    snapshot = CURRENT_NS_LOAD_PATH_SNAPSHOT(vm_ns);
    load_path = CURRENT_NS_LOAD_PATH(vm_ns);
    rb_ary_replace(snapshot, load_path);
}

static VALUE
get_expanded_load_path(vm_ns_t *vm_ns)
{
    VALUE check_cache;
    const VALUE non_cache = Qtrue;
    const VALUE load_path_snapshot = CURRENT_NS_LOAD_PATH_SNAPSHOT(vm_ns);
    const VALUE load_path = CURRENT_NS_LOAD_PATH(vm_ns);

    if (!rb_ary_shared_with_p(load_path_snapshot, load_path)) {
        /* The load path was modified. Rebuild the expanded load path. */
        int has_relative = 0, has_non_cache = 0;
        rb_construct_expanded_load_path(vm_ns, EXPAND_ALL, &has_relative, &has_non_cache);
        if (has_relative) {
            SET_NS_LOAD_PATH_CHECK_CACHE(vm_ns, rb_dir_getwd_ospath());
        }
        else if (has_non_cache) {
            /* Non string object. */
            SET_NS_LOAD_PATH_CHECK_CACHE(vm_ns, non_cache);
        }
        else {
            SET_NS_LOAD_PATH_CHECK_CACHE(vm_ns, 0);
        }
    }
    else if ((check_cache = CURRENT_NS_LOAD_PATH_CHECK_CACHE(vm_ns)) == non_cache) {
        int has_relative = 1, has_non_cache = 1;
        /* Expand only non-cacheable objects. */
        rb_construct_expanded_load_path(vm_ns, EXPAND_NON_CACHE,
                                        &has_relative, &has_non_cache);
    }
    else if (check_cache) {
        int has_relative = 1, has_non_cache = 1;
        VALUE cwd = rb_dir_getwd_ospath();
        if (!rb_str_equal(check_cache, cwd)) {
            /* Current working directory or filesystem encoding was changed.
               Expand relative load path and non-cacheable objects again. */
            SET_NS_LOAD_PATH_CHECK_CACHE(vm_ns, cwd);
            rb_construct_expanded_load_path(vm_ns, EXPAND_RELATIVE,
                                            &has_relative, &has_non_cache);
        }
        else {
            /* Expand only tilde (User HOME) and non-cacheable objects. */
            rb_construct_expanded_load_path(vm_ns, EXPAND_HOME,
                                            &has_relative, &has_non_cache);
        }
    }
    return CURRENT_NS_EXPANDED_LOAD_PATH(vm_ns);
}

VALUE
rb_get_expanded_load_path(void)
{
    GET_loading_vm_ns();
    return get_expanded_load_path(vm_ns);
}

static VALUE
load_path_getter(ID id, VALUE * p)
{
    GET_loading_vm_ns();
    return CURRENT_NS_LOAD_PATH(vm_ns);
}

static VALUE
get_loaded_features(vm_ns_t *vm_ns)
{
    return CURRENT_NS_LOADED_FEATURES(vm_ns);
}

static VALUE
get_loaded_features_realpaths(vm_ns_t *vm_ns)
{
    return CURRENT_NS_LOADED_FEATURES_REALPATHS(vm_ns);
}

static VALUE
get_loaded_features_realpath_map(vm_ns_t *vm_ns)
{
    return CURRENT_NS_LOADED_FEATURES_REALPATH_MAP(vm_ns);
}

static VALUE
get_LOADED_FEATURES(ID _x, VALUE *_y)
{
    GET_loading_vm_ns();
    return get_loaded_features(vm_ns);
}

static void
reset_loaded_features_snapshot(vm_ns_t *vm_ns)
{
    VALUE snapshot = CURRENT_NS_LOADED_FEATURES_SNAPSHOT(vm_ns);
    VALUE loaded_features = CURRENT_NS_LOADED_FEATURES(vm_ns);
    rb_ary_replace(snapshot, loaded_features);
}

static struct st_table *
get_loaded_features_index_raw(vm_ns_t *vm_ns)
{
    return CURRENT_NS_LOADED_FEATURES_INDEX(vm_ns);
}

static st_table *
get_loading_table(vm_ns_t *vm_ns)
{
    return CURRENT_NS_LOADING_TABLE(vm_ns);
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
    vm_ns_t *vm_ns;
    VALUE offset;
    bool rb;
};

static int
features_index_add_single_callback(st_data_t *key, st_data_t *value, st_data_t raw_args, int existing)
{
    struct features_index_add_single_args *args = (struct features_index_add_single_args *)raw_args;
    vm_ns_t *vm_ns = args->vm_ns;
    VALUE offset = args->offset;
    bool rb = args->rb;

    if (existing) {
        VALUE this_feature_index = *value;

        if (FIXNUM_P(this_feature_index)) {
            VALUE loaded_features = get_loaded_features(vm_ns);
            VALUE this_feature_path = RARRAY_AREF(loaded_features, FIX2LONG(this_feature_index));

            feature_indexes_t feature_indexes;
            rb_darray_make(&feature_indexes, 2);
            int top = (rb && !is_rbext_path(this_feature_path)) ? 1 : 0;
            rb_darray_set(feature_indexes, top^0, FIX2LONG(this_feature_index));
            rb_darray_set(feature_indexes, top^1, FIX2LONG(offset));

            RUBY_ASSERT(rb_darray_size(feature_indexes) == 2);
            // assert feature_indexes does not look like a special const
            RUBY_ASSERT(!SPECIAL_CONST_P((VALUE)feature_indexes));

            *value = (st_data_t)feature_indexes;
        }
        else {
            feature_indexes_t feature_indexes = (feature_indexes_t)this_feature_index;
            long pos = -1;

            if (rb) {
                VALUE loaded_features = get_loaded_features(vm_ns);
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
features_index_add_single(vm_ns_t *vm_ns, const char* str, size_t len, VALUE offset, bool rb)
{
    struct st_table *features_index;
    st_data_t short_feature_key;

    Check_Type(offset, T_FIXNUM);
    short_feature_key = feature_key(str, len);

    features_index = get_loaded_features_index_raw(vm_ns);

    struct features_index_add_single_args args = {
        .vm_ns = vm_ns,
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
features_index_add(vm_ns_t *vm_ns, VALUE feature, VALUE offset)
{
    RUBY_ASSERT(rb_ractor_main_p());

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
        features_index_add_single(vm_ns, p + 1, feature_end - p - 1, offset, false);
        if (ext) {
            features_index_add_single(vm_ns, p + 1, ext - p - 1, offset, rb);
        }
    }
    features_index_add_single(vm_ns, feature_str, feature_end - feature_str, offset, false);
    if (ext) {
        features_index_add_single(vm_ns, feature_str, ext - feature_str, offset, rb);
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
    /* Destructs vm->loaded_features_index directly because this is only for
       the VM destruction */
    st_foreach(vm->loaded_features_index, loaded_features_index_clear_i, 0);
    st_free_table(vm->loaded_features_index);
}



static st_table *
get_loaded_features_index(vm_ns_t *vm_ns)
{
    int i;
    VALUE features = CURRENT_NS_LOADED_FEATURES(vm_ns);
    const VALUE snapshot = CURRENT_NS_LOADED_FEATURES_SNAPSHOT(vm_ns);

    if (!rb_ary_shared_with_p(snapshot, features)) {
        /* The sharing was broken; something (other than us in rb_provide_feature())
           modified loaded_features.  Rebuild the index. */
        st_foreach(CURRENT_NS_LOADED_FEATURES_INDEX(vm_ns), loaded_features_index_clear_i, 0);

        VALUE realpaths = CURRENT_NS_LOADED_FEATURES_REALPATHS(vm_ns);
        VALUE realpath_map = CURRENT_NS_LOADED_FEATURES_REALPATH_MAP(vm_ns);
        VALUE previous_realpath_map = rb_hash_dup(realpath_map);
        rb_hash_clear(realpaths);
        rb_hash_clear(realpath_map);
        for (i = 0; i < RARRAY_LEN(features); i++) {
            VALUE entry, as_str;
            as_str = entry = rb_ary_entry(features, i);
            StringValue(as_str);
            as_str = rb_fstring(as_str);
            if (as_str != entry)
                rb_ary_store(features, i, as_str);
            features_index_add(vm_ns, as_str, INT2FIX(i));
        }
        reset_loaded_features_snapshot(vm_ns);

        features = CURRENT_NS_LOADED_FEATURES_SNAPSHOT(vm_ns);
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
    return CURRENT_NS_LOADED_FEATURES_INDEX(vm_ns);
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
rb_feature_p(vm_ns_t *vm_ns, const char *feature, const char *ext, int rb, int expanded, const char **fn)
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
    features = get_loaded_features(vm_ns);
    features_index = get_loaded_features_index(vm_ns);

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
                if (!load_path) load_path = get_expanded_load_path(vm_ns);
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

    loading_tbl = get_loading_table(vm_ns);
    f = 0;
    if (!expanded && !rb_is_absolute_path(feature)) {
        struct loaded_feature_searching fs;
        fs.name = feature;
        fs.len = len;
        fs.type = type;
        fs.load_path = load_path ? load_path : get_expanded_load_path(vm_ns);
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
feature_provided(vm_ns_t *vm_ns, const char *feature, const char **loading)
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
            if (rb_feature_p(vm_ns, feature, ext, TRUE, FALSE, loading)) return TRUE;
            return FALSE;
        }
        else if (IS_SOEXT(ext) || IS_DLEXT(ext)) {
            if (rb_feature_p(vm_ns, feature, ext, FALSE, FALSE, loading)) return TRUE;
            return FALSE;
        }
    }
    if (rb_feature_p(vm_ns, feature, 0, TRUE, FALSE, loading))
        return TRUE;
    RB_GC_GUARD(fullpath);
    return FALSE;
}

int
rb_feature_provided(const char *feature, const char **loading)
{
    GET_vm_ns();
    return feature_provided(vm_ns, feature, loading);
}

static void
rb_provide_feature(vm_ns_t *vm_ns, VALUE feature)
{
    VALUE features;

    features = get_loaded_features(vm_ns);
    if (OBJ_FROZEN(features)) {
        rb_raise(rb_eRuntimeError,
                 "$LOADED_FEATURES is frozen; cannot append feature");
    }
    feature = rb_fstring(feature);

    get_loaded_features_index(vm_ns);
    // If loaded_features and loaded_features_snapshot share the same backing
    // array, pushing into it would cause the whole array to be copied.
    // To avoid this we first clear loaded_features_snapshot.
    rb_ary_clear(CURRENT_NS_LOADED_FEATURES_SNAPSHOT(vm_ns));
    rb_ary_push(features, feature);
    features_index_add(vm_ns, feature, INT2FIX(RARRAY_LEN(features)-1));
    reset_loaded_features_snapshot(vm_ns);
}

void
rb_provide(const char *feature)
{
    /*
     * rb_provide() must use rb_current_namespace to store provided features
     * in the current namespace's loaded_features, etc.
     */
    GET_vm_ns();
    rb_provide_feature(vm_ns, rb_fstring_cstr(feature));
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

struct iseq_eval_in_namespace_data {
    const rb_iseq_t *iseq;
    bool in_builtin;
};

static VALUE
iseq_eval_in_namespace(VALUE arg)
{
    struct iseq_eval_in_namespace_data *data = (struct iseq_eval_in_namespace_data *)arg;
    if (rb_namespace_available() && data->in_builtin) {
        return rb_iseq_eval_with_refinement(data->iseq, rb_mNamespaceRefiner);
    }
    else {
        return rb_iseq_eval(data->iseq);
    }
}

static inline void
load_iseq_eval(rb_execution_context_t *ec, VALUE fname)
{
    GET_loading_vm_ns();
    const rb_namespace_t *loading_ns = rb_loading_namespace();
    const rb_iseq_t *iseq = rb_iseq_load_iseq(fname);

    if (!iseq) {
        rb_execution_context_t *ec = GET_EC();
        VALUE v = rb_vm_push_frame_fname(ec, fname);

        VALUE realpath_map = get_loaded_features_realpath_map(vm_ns);

        if (rb_ruby_prism_p()) {
            pm_parse_result_t result = { 0 };
            result.options.line = 1;
            result.node.coverage_enabled = 1;

            VALUE error = pm_load_parse_file(&result, fname, NULL);

            if (error == Qnil) {
                int error_state;
                iseq = pm_iseq_new_top(&result.node, rb_fstring_lit("<top (required)>"), fname, realpath_internal_cached(realpath_map, fname), NULL, &error_state);

                pm_parse_result_free(&result);

                if (error_state) {
                    RUBY_ASSERT(iseq == NULL);
                    rb_jump_tag(error_state);
                }
            }
            else {
                rb_vm_pop_frame(ec);
                RB_GC_GUARD(v);
                pm_parse_result_free(&result);
                rb_exc_raise(error);
            }
        }
        else {
            rb_ast_t *ast;
            VALUE ast_value;
            VALUE parser = rb_parser_new();
            rb_parser_set_context(parser, NULL, FALSE);
            ast_value = rb_parser_load_file(parser, fname);
            ast = rb_ruby_ast_data_get(ast_value);

            iseq = rb_iseq_new_top(ast_value, rb_fstring_lit("<top (required)>"),
                                   fname, realpath_internal_cached(realpath_map, fname), NULL);
            rb_ast_dispose(ast);
        }

        rb_vm_pop_frame(ec);
        RB_GC_GUARD(v);
    }
    rb_exec_event_hook_script_compiled(ec, iseq, Qnil);

    if (loading_ns) {
        struct iseq_eval_in_namespace_data arg = {
            .iseq = iseq,
            .in_builtin = NAMESPACE_BUILTIN_P(loading_ns),
        };
        rb_namespace_exec(loading_ns, iseq_eval_in_namespace, (VALUE)&arg);
    }
    else {
        rb_iseq_eval(iseq);
    }
}

static inline enum ruby_tag_type
load_wrapping(rb_execution_context_t *ec, VALUE fname, VALUE load_wrapper)
{
    enum ruby_tag_type state;
    rb_namespace_t *ns;
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    volatile VALUE wrapper = th->top_wrapper;
    volatile VALUE self = th->top_self;
#if !defined __GNUC__
    rb_thread_t *volatile th0 = th;
#endif

    ec->errinfo = Qnil; /* ensure */

    /* load in module as toplevel */
    if (IS_NAMESPACE(load_wrapper)) {
        ns = rb_get_namespace_t(load_wrapper);
        if (!ns->top_self) {
            ns->top_self = rb_obj_clone(rb_vm_top_self());
        }
        th->top_self = ns->top_self;
    }
    else {
        th->top_self = rb_obj_clone(rb_vm_top_self());
    }
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
    VALUE namespace;
    rb_execution_context_t *ec = GET_EC();
    const rb_namespace_t *ns = rb_loading_namespace();
    enum ruby_tag_type state = TAG_NONE;
    if (RTEST(wrap)) {
        if (!RB_TYPE_P(wrap, T_MODULE)) {
            wrap = rb_module_new();
        }
        state = load_wrapping(ec, fname, wrap);
    }
    else if (NAMESPACE_OPTIONAL_P(ns)) {
        namespace = ns->ns_object;
        state = load_wrapping(ec, fname, namespace);
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

static VALUE
load_entrypoint_internal(VALUE fname, VALUE wrap)
{
    VALUE path, orig_fname;

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

VALUE
rb_load_entrypoint(VALUE args)
{
    VALUE fname, wrap;
    if (RARRAY_LEN(args) != 2) {
        rb_bug("invalid arguments: %ld", RARRAY_LEN(args));
    }
    fname = rb_ary_entry(args, 0);
    wrap = rb_ary_entry(args, 1);
    return load_entrypoint_internal(fname, wrap);
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
 *  be executed under an anonymous module. If the optional _wrap_ parameter
 *  is a module, the loaded script will be executed under the given module.
 *  In no circumstance will any local variables in the loaded file be
 *  propagated to the loading environment.
 */

static VALUE
rb_f_load(int argc, VALUE *argv, VALUE _)
{
    VALUE fname, wrap;
    rb_scan_args(argc, argv, "11", &fname, &wrap);
    return load_entrypoint_internal(fname, wrap);
}

static char *
load_lock(vm_ns_t *vm_ns, const char *ftptr, bool warn)
{
    st_data_t data;
    st_table *loading_tbl = get_loading_table(vm_ns);

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
load_unlock(vm_ns_t *vm_ns, const char *ftptr, int done)
{
    if (ftptr) {
        st_data_t key = (st_data_t)ftptr;
        st_table *loading_tbl = get_loading_table(vm_ns);

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
    // const rb_namespace_t *ns = rb_loading_namespace();
    // printf("F:current loading ns: %ld\n", ns->ns_id);
    return rb_require_string(fname);
}

VALUE
rb_require_relative_entrypoint(VALUE fname)
{
    VALUE base = rb_current_realfilepath();
    if (NIL_P(base)) {
        rb_loaderror("cannot infer basepath");
    }
    base = rb_file_dirname(base);
    return rb_require_string_internal(rb_file_absolute_path(fname, base), false);
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
    return rb_require_relative_entrypoint(fname);
}

typedef int (*feature_func)(vm_ns_t *vm_ns, const char *feature, const char *ext, int rb, int expanded, const char **fn);

static int
search_required(vm_ns_t *vm_ns, VALUE fname, volatile VALUE *path, feature_func rb_feature_p)
{
    VALUE tmp;
    char *ext, *ftptr;
    int ft = 0;
    const char *loading;

    *path = 0;
    ext = strrchr(ftptr = RSTRING_PTR(fname), '.');
    if (ext && !strchr(ext, '/')) {
        if (IS_RBEXT(ext)) {
            if (rb_feature_p(vm_ns, ftptr, ext, TRUE, FALSE, &loading)) {
                if (loading) *path = rb_filesystem_str_new_cstr(loading);
                return 'r';
            }
            if ((tmp = rb_find_file(fname)) != 0) {
                ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
                if (!rb_feature_p(vm_ns, ftptr, ext, TRUE, TRUE, &loading) || loading)
                    *path = tmp;
                return 'r';
            }
            return 0;
        }
        else if (IS_SOEXT(ext)) {
            if (rb_feature_p(vm_ns, ftptr, ext, FALSE, FALSE, &loading)) {
                if (loading) *path = rb_filesystem_str_new_cstr(loading);
                return 's';
            }
            tmp = rb_str_subseq(fname, 0, ext - RSTRING_PTR(fname));
            rb_str_cat2(tmp, DLEXT);
            OBJ_FREEZE(tmp);
            if ((tmp = rb_find_file(tmp)) != 0) {
                ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
                if (!rb_feature_p(vm_ns, ftptr, ext, FALSE, TRUE, &loading) || loading)
                    *path = tmp;
                return 's';
            }
        }
        else if (IS_DLEXT(ext)) {
            if (rb_feature_p(vm_ns, ftptr, ext, FALSE, FALSE, &loading)) {
                if (loading) *path = rb_filesystem_str_new_cstr(loading);
                return 's';
            }
            if ((tmp = rb_find_file(fname)) != 0) {
                ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
                if (!rb_feature_p(vm_ns, ftptr, ext, FALSE, TRUE, &loading) || loading)
                    *path = tmp;
                return 's';
            }
        }
    }
    else if ((ft = rb_feature_p(vm_ns, ftptr, 0, FALSE, FALSE, &loading)) == 'r') {
        if (loading) *path = rb_filesystem_str_new_cstr(loading);
        return 'r';
    }
    tmp = fname;
    const unsigned int type = rb_find_file_ext(&tmp, ft == 's' ? ruby_ext : loadable_ext);

    // Check if it's a statically linked extension when
    // not already a feature and not found as a dynamic library.
    if (!ft && type != loadable_ext_rb && vm_ns->vm->static_ext_inits) {
        VALUE lookup_name = tmp;
        // Append ".so" if not already present so for example "etc" can find "etc.so".
        // We always register statically linked extensions with a ".so" extension.
        // See encinit.c and extinit.c (generated at build-time).
        if (!ext) {
            lookup_name = rb_str_dup(lookup_name);
            rb_str_cat_cstr(lookup_name, ".so");
        }
        ftptr = RSTRING_PTR(lookup_name);
        if (st_lookup(vm_ns->vm->static_ext_inits, (st_data_t)ftptr, NULL)) {
            *path = rb_filesystem_str_new_cstr(ftptr);
            RB_GC_GUARD(lookup_name);
            return 's';
        }
    }

    switch (type) {
      case 0:
        if (ft)
            goto feature_present;
        ftptr = RSTRING_PTR(tmp);
        return rb_feature_p(vm_ns, ftptr, 0, FALSE, TRUE, 0);

      default:
        if (ft) {
            goto feature_present;
        }
        /* fall through */
      case loadable_ext_rb:
        ext = strrchr(ftptr = RSTRING_PTR(tmp), '.');
        if (rb_feature_p(vm_ns, ftptr, ext, type == loadable_ext_rb, TRUE, &loading) && !loading)
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
load_ext(VALUE path, VALUE fname)
{
    VALUE loaded = path;
    GET_loading_vm_ns();
    if (NAMESPACE_USER_P(vm_ns->ns)) {
        loaded = rb_namespace_local_extension(vm_ns->ns->ns_object, fname, path);
    }
    rb_scope_visibility_set(METHOD_VISI_PUBLIC);
    return (VALUE)dln_load_feature(RSTRING_PTR(loaded), RSTRING_PTR(fname));
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
no_feature_p(vm_ns_t *vm_ns, const char *feature, const char *ext, int rb, int expanded, const char **fn)
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
    GET_loading_vm_ns();

    fname = rb_get_path(fname);
    path = rb_str_encode_ospath(fname);
    found = search_required(vm_ns, path, &path, no_feature_p);

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

struct rb_vm_call_cfunc2_data {
    VALUE recv;
    VALUE arg1;
    VALUE arg2;
    VALUE block_handler;
    VALUE filename;
};

static VALUE
call_load_ext_in_ns(VALUE data)
{
    struct rb_vm_call_cfunc2_data *arg = (struct rb_vm_call_cfunc2_data *)data;
    return rb_vm_call_cfunc2(arg->recv, load_ext, arg->arg1, arg->arg2, arg->block_handler, arg->filename);
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
    GET_loading_vm_ns();
    enum ruby_tag_type state;
    char *volatile ftptr = 0;
    VALUE path;
    volatile VALUE saved_path;
    volatile VALUE realpath = 0;
    VALUE realpaths = get_loaded_features_realpaths(vm_ns);
    VALUE realpath_map = get_loaded_features_realpath_map(vm_ns);
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
        found = search_required(vm_ns, path, &saved_path, rb_feature_p);
        RUBY_DTRACE_HOOK(FIND_REQUIRE_RETURN, RSTRING_PTR(fname));
        path = saved_path;

        if (found) {
            if (!path || !(ftptr = load_lock(vm_ns, RSTRING_PTR(path), warn))) {
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
                    // iseq_eval_in_namespace will be called with the loading namespace eventually
                    if (NAMESPACE_OPTIONAL_P(vm_ns->ns)) {
                        // check with NAMESPACE_OPTIONAL_P (not NAMESPACE_USER_P) for NS1::xxx naming
                        // it is not expected for the main namespace
                        load_wrapping(saved.ec, path, vm_ns->ns->ns_object);
                    }
                    else {
                        load_iseq_eval(saved.ec, path);
                    }
                    break;

                  case 's':
                    // the loading namespace must be set to the current namespace before calling load_ext
                    reset_ext_config = true;
                    ext_config_push(th, &prev_ext_config);
                    struct rb_vm_call_cfunc2_data arg = {
                        .recv = rb_vm_top_self(),
                        .arg1 = path,
                        .arg2 = fname,
                        .block_handler = VM_BLOCK_HANDLER_NONE,
                        .filename = path,
                    };
                    handle = rb_namespace_exec(vm_ns->ns, call_load_ext_in_ns, (VALUE)&arg);
                    rb_hash_aset(CURRENT_NS_RUBY_DLN_LIBMAP(vm_ns, ruby_dln_libmap), path,
                                 SVALUE2NUM((SIGNED_VALUE)handle));
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
    if (ftptr) load_unlock(vm_ns, RSTRING_PTR(path), !state);

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
        rb_provide_feature(vm_ns, path);
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
    if (!rb_ractor_main_p()) {
        return NUM2INT(rb_ractor_require(fname, true));
    }

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

    // main ractor check
    if (!rb_ractor_main_p()) {
        if (resurrect) fname = rb_str_resurrect(fname);
        return rb_ractor_require(fname, false);
    }
    else {
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
    GET_loading_vm_ns();

    if (feature_provided(vm_ns, name, 0))
        return;

    inits_table = vm_ns->vm->static_ext_inits;
    if (!inits_table) {
        inits_table = st_init_strtable();
        vm_ns->vm->static_ext_inits = inits_table;
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
 *  If _const_ in _mod_ is defined as autoload, the file name to be
 *  loaded is replaced with _filename_.  If _const_ is defined but not
 *  as autoload, does nothing.
 *
 *  Files that are currently being loaded must not be registered for
 *  autoload.
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
 *  If _const_ is defined as autoload, the file name to be loaded is
 *  replaced with _filename_.  If _const_ is defined but not as
 *  autoload, does nothing.
 *
 *  Files that are currently being loaded must not be registered for
 *  autoload.
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
 *  +autoload+ in the current namespace or one of its ancestors.
 *
 *     autoload(:B, "b")
 *     autoload?(:B)            #=> "b"
 *
 *     module C
 *       autoload(:D, "d")
 *       autoload?(:D)          #=> "d"
 *       autoload?(:B)          #=> nil
 *     end
 *
 *     class E
 *       autoload(:F, "f")
 *       autoload?(:F)          #=> "f"
 *       autoload?(:B)          #=> "b"
 *     end
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
    GET_loading_vm_ns();

    resolved = rb_resolve_feature_path((VALUE)NULL, fname_str);
    if (NIL_P(resolved)) {
        ext = strrchr(fname, '.');
        if (!ext || !IS_SOEXT(ext)) {
            rb_str_cat_cstr(fname_str, ".so");
        }
        if (rb_feature_p(vm_ns, fname, 0, FALSE, FALSE, 0)) {
            return dln_symbol(NULL, symbol);
        }
        return NULL;
    }
    if (RARRAY_LEN(resolved) != 2 || rb_ary_entry(resolved, 0) != ID2SYM(rb_intern("so"))) {
        return NULL;
    }
    path = rb_ary_entry(resolved, 1);
    handle = rb_hash_lookup(CURRENT_NS_RUBY_DLN_LIBMAP(vm_ns, ruby_dln_libmap), path);
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
    rb_gvar_namespace_ready(var_load_path);
    rb_alias_variable(rb_intern_const("$-I"), id_load_path);
    rb_alias_variable(rb_intern_const("$LOAD_PATH"), id_load_path);
    vm->load_path = rb_ary_new();
    vm->expanded_load_path = rb_ary_hidden_new(0);
    vm->load_path_snapshot = rb_ary_hidden_new(0);
    vm->load_path_check_cache = 0;
    rb_define_singleton_method(vm->load_path, "resolve_feature_path", rb_resolve_feature_path, 1);

    rb_define_virtual_variable("$\"", get_LOADED_FEATURES, 0);
    rb_gvar_namespace_ready("$\"");
    rb_define_virtual_variable("$LOADED_FEATURES", get_LOADED_FEATURES, 0); // TODO: rb_alias_variable ?
    rb_gvar_namespace_ready("$LOADED_FEATURES");
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
    rb_vm_register_global_object(ruby_dln_libmap);
}
