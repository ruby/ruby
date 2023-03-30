#include "internal.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/proc.h"
#include "internal/sanitizers.h"
#include "ruby/st.h"
#include "ruby/st.h"

struct weakmap {
    st_table *obj2wmap;		/* obj -> [ref,...] */
    st_table *wmap2obj;		/* ref -> obj */
    VALUE final;
};

static int
wmap_replace_ref(st_data_t *key, st_data_t *value, st_data_t _argp, int existing)
{
    *key = rb_gc_location((VALUE)*key);

    VALUE *values = (VALUE *)*value;
    VALUE size = values[0];

    for (VALUE index = 1; index <= size; index++) {
        values[index] = rb_gc_location(values[index]);
    }

    return ST_CONTINUE;
}

static int
wmap_foreach_replace(st_data_t key, st_data_t value, st_data_t _argp, int error)
{
    if (rb_gc_location((VALUE)key) != (VALUE)key) {
        return ST_REPLACE;
    }

    VALUE *values = (VALUE *)value;
    VALUE size = values[0];

    for (VALUE index = 1; index <= size; index++) {
        VALUE val = values[index];
        if (rb_gc_location(val) != val) {
            return ST_REPLACE;
        }
    }

    return ST_CONTINUE;
}

static void
wmap_compact(void *ptr)
{
    struct weakmap *w = ptr;
    if (w->wmap2obj) rb_gc_update_tbl_refs(w->wmap2obj);
    if (w->obj2wmap) st_foreach_with_replace(w->obj2wmap, wmap_foreach_replace, wmap_replace_ref, (st_data_t)NULL);
    w->final = rb_gc_location(w->final);
}

static void
wmap_mark(void *ptr)
{
    struct weakmap *w = ptr;
    rb_gc_mark_movable(w->final);
}

static int
wmap_free_map(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE *ptr = (VALUE *)val;
    ruby_sized_xfree(ptr, (ptr[0] + 1) * sizeof(VALUE));
    return ST_CONTINUE;
}

static void
wmap_free(void *ptr)
{
    struct weakmap *w = ptr;
    st_foreach(w->obj2wmap, wmap_free_map, 0);
    st_free_table(w->obj2wmap);
    st_free_table(w->wmap2obj);
    xfree(w);
}

static int
wmap_memsize_map(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE *ptr = (VALUE *)val;
    *(size_t *)arg += (ptr[0] + 1) * sizeof(VALUE);
    return ST_CONTINUE;
}

static size_t
wmap_memsize(const void *ptr)
{
    size_t size;
    const struct weakmap *w = ptr;
    size = sizeof(*w);
    size += st_memsize(w->obj2wmap);
    size += st_memsize(w->wmap2obj);
    st_foreach(w->obj2wmap, wmap_memsize_map, (st_data_t)&size);
    return size;
}

static const rb_data_type_t weakmap_type = {
    "weakmap",
    {
        wmap_mark,
        wmap_free,
        wmap_memsize,
        wmap_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE wmap_finalize(RB_BLOCK_CALL_FUNC_ARGLIST(objid, self));

static VALUE
wmap_allocate(VALUE klass)
{
    struct weakmap *w;
    VALUE obj = TypedData_Make_Struct(klass, struct weakmap, &weakmap_type, w);
    w->obj2wmap = rb_init_identtable();
    w->wmap2obj = rb_init_identtable();
    RB_OBJ_WRITE(obj, &w->final, rb_func_lambda_new(wmap_finalize, obj, 1, 1));
    return obj;
}

static int
wmap_live_p(VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) return TRUE;
    /* If rb_gc_is_ptr_to_obj returns false, the page could be in the tomb heap
     * or have already been freed. */
    if (!rb_gc_is_ptr_to_obj((void *)obj)) return FALSE;

    void *poisoned = asan_poisoned_object_p(obj);
    asan_unpoison_object(obj, false);

    enum ruby_value_type t = BUILTIN_TYPE(obj);
    int ret = (!(t == T_NONE || t >= T_FIXNUM || t == T_ICLASS) &&
                !rb_objspace_garbage_object_p(obj));

    if (poisoned) {
        asan_poison_object(obj);
    }

    return ret;
}

static int
wmap_remove_inverse_ref(st_data_t *key, st_data_t *val, st_data_t arg, int existing)
{
    if (!existing) return ST_STOP;

    VALUE old_ref = (VALUE)arg;

    VALUE *values = (VALUE *)*val;
    VALUE size = values[0];

    if (size == 1) {
        // fast path, we only had one backref
        RUBY_ASSERT(values[1] == old_ref);
        ruby_sized_xfree(values, 2 * sizeof(VALUE));
        return ST_DELETE;
    }

    bool found = false;
    VALUE index = 1;
    for (; index <= size; index++) {
        if (values[index] == old_ref) {
            found = true;
            break;
        }
    }
    if (!found) return ST_STOP;

    if (size > index) {
        MEMMOVE(&values[index], &values[index + 1], VALUE, size - index);
    }

    size -= 1;
    values[0] = size;
    SIZED_REALLOC_N(values, VALUE, size + 1, size + 2);
    *val = (st_data_t)values;
    return ST_CONTINUE;
}

/* :nodoc: */
static VALUE
wmap_finalize(RB_BLOCK_CALL_FUNC_ARGLIST(objid, self))
{
    st_data_t orig, wmap, data;
    VALUE obj, *rids, i, size;
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    /* Get reference from object id. */
    if (UNDEF_P(obj = rb_gc_id2ref_obj_tbl(objid))) {
        rb_bug("wmap_finalize: objid is not found.");
    }

    /* obj is original referenced object and/or weak reference. */
    orig = (st_data_t)obj;
    if (st_delete(w->obj2wmap, &orig, &data)) {
        rids = (VALUE *)data;
        size = *rids++;
        for (i = 0; i < size; ++i) {
            wmap = (st_data_t)rids[i];
            st_delete(w->wmap2obj, &wmap, NULL);
        }
        ruby_sized_xfree((VALUE *)data, (size + 1) * sizeof(VALUE));
    }

    wmap = (st_data_t)obj;
    if (st_delete(w->wmap2obj, &wmap, &orig)) {
        wmap = (st_data_t)obj;
        st_update(w->obj2wmap, orig, wmap_remove_inverse_ref, wmap);
    }
    return self;
}

static VALUE
wmap_inspect_append(VALUE str, VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) {
        return rb_str_append(str, rb_inspect(obj));
    }
    else if (wmap_live_p(obj)) {
        return rb_str_append(str, rb_any_to_s(obj));
    }
    else {
        return rb_str_catf(str, "#<collected:%p>", (void*)obj);
    }
}

static int
wmap_inspect_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE str = (VALUE)arg;
    VALUE k = (VALUE)key, v = (VALUE)val;

    if (RSTRING_PTR(str)[0] == '#') {
        rb_str_cat2(str, ", ");
    }
    else {
        rb_str_cat2(str, ": ");
        RSTRING_PTR(str)[0] = '#';
    }
    wmap_inspect_append(str, k);
    rb_str_cat2(str, " => ");
    wmap_inspect_append(str, v);

    return ST_CONTINUE;
}

static VALUE
wmap_inspect(VALUE self)
{
    VALUE c = rb_class_name(CLASS_OF(self));
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE str = rb_sprintf("-<%"PRIsVALUE":%p", c, (void *)self);
    if (w->wmap2obj) {
        st_foreach(w->wmap2obj, wmap_inspect_i, (st_data_t)str);
    }
    RSTRING_PTR(str)[0] = '#';
    rb_str_cat2(str, ">");
    return str;
}

static inline bool
wmap_live_entry_p(st_data_t key, st_data_t val)
{
    return wmap_live_p((VALUE)key) && wmap_live_p((VALUE)val);
}

static int
wmap_each_i(st_data_t key, st_data_t val, st_data_t _)
{
    if (wmap_live_entry_p(key, val)) {
        rb_yield_values(2, (VALUE)key, (VALUE)val);
        return ST_CONTINUE;
    }
    else {
        return ST_DELETE;
    }
}

/* Iterates over keys and objects in a weakly referenced object */
static VALUE
wmap_each(VALUE self)
{
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    st_foreach(w->wmap2obj, wmap_each_i, (st_data_t)0);
    return self;
}

static int
wmap_each_key_i(st_data_t key, st_data_t val, st_data_t arg)
{
    if (wmap_live_entry_p(key, val)) {
        rb_yield((VALUE)key);
        return ST_CONTINUE;
    }
    else {
        return ST_DELETE;
    }
}

/* Iterates over keys and objects in a weakly referenced object */
static VALUE
wmap_each_key(VALUE self)
{
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    st_foreach(w->wmap2obj, wmap_each_key_i, (st_data_t)0);
    return self;
}

static int
wmap_each_value_i(st_data_t key, st_data_t val, st_data_t arg)
{
    if (wmap_live_entry_p(key, val)) {
        rb_yield((VALUE)val);
        return ST_CONTINUE;
    }
    else {
        return ST_DELETE;
    }
}

/* Iterates over keys and objects in a weakly referenced object */
static VALUE
wmap_each_value(VALUE self)
{
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    st_foreach(w->wmap2obj, wmap_each_value_i, (st_data_t)0);
    return self;
}

static int
wmap_keys_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE ary = (VALUE)arg;

    if (wmap_live_entry_p(key, val)) {
        rb_ary_push(ary, (VALUE)key);
        return ST_CONTINUE;
    }
    else {
        return ST_DELETE;
    }
}

/* Iterates over keys and objects in a weakly referenced object */
static VALUE
wmap_keys(VALUE self)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE ary = rb_ary_new();
    st_foreach(w->wmap2obj, wmap_keys_i, (st_data_t)ary);
    return ary;
}

static int
wmap_values_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE ary = (VALUE)arg;

    if (wmap_live_entry_p(key, val)) {
        rb_ary_push(ary, (VALUE)val);
        return ST_CONTINUE;
    }
    else {
        return ST_DELETE;
    }
}

/* Iterates over values and objects in a weakly referenced object */
static VALUE
wmap_values(VALUE self)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE ary = rb_ary_new();
    st_foreach(w->wmap2obj, wmap_values_i, (st_data_t)ary);
    return ary;
}

static int
wmap_aset_update(st_data_t *key, st_data_t *val, st_data_t arg, int existing)
{
    VALUE size, *ptr, *optr;
    if (existing) {
        size = (ptr = optr = (VALUE *)*val)[0];

        for (VALUE index = 1; index <= size; index++) {
            if (ptr[index] == (VALUE)arg) {
                // The reference was already registered.
                return ST_STOP;
            }
        }

        ++size;
        SIZED_REALLOC_N(ptr, VALUE, size + 1, size);
    }
    else {
        optr = 0;
        size = 1;
        ptr = ruby_xmalloc(2 * sizeof(VALUE));
    }
    ptr[0] = size;
    ptr[size] = (VALUE)arg;
    if (ptr == optr) return ST_STOP;
    *val = (st_data_t)ptr;
    return ST_CONTINUE;
}

static VALUE
nonspecial_obj_id(VALUE obj)
{
#if SIZEOF_LONG == SIZEOF_VOIDP
    return (VALUE)((SIGNED_VALUE)(obj)|FIXNUM_FLAG);
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
    return LL2NUM((SIGNED_VALUE)(obj) / 2);
#else
# error not supported
#endif
}

struct wmap_aset_replace_args {
    VALUE new_value;
    VALUE old_value;
};

static int
wmap_aset_replace_value(st_data_t *key, st_data_t *val, st_data_t _args, int existing)
{
    struct wmap_aset_replace_args *args = (struct wmap_aset_replace_args *)_args;

    if (existing) {
        args->old_value = *val;
    }
    *val = (st_data_t)args->new_value;
    return ST_CONTINUE;
}

/* Creates a weak reference from the given key to the given value */
static VALUE
wmap_aset(VALUE self, VALUE key, VALUE value)
{
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    if (FL_ABLE(value)) {
        rb_define_finalizer_no_check(value, w->final);
    }
    if (FL_ABLE(key)) {
        rb_define_finalizer_no_check(key, w->final);
    }

    struct wmap_aset_replace_args aset_args = {
        .new_value = value,
        .old_value = Qundef,
    };
    st_update(w->wmap2obj, (st_data_t)key, wmap_aset_replace_value, (st_data_t)&aset_args);

    // If the value is unchanged, we have nothing to do.
    if (value != aset_args.old_value) {
        if (!UNDEF_P(aset_args.old_value) && FL_ABLE(aset_args.old_value)) {
            // That key existed and had an inverse reference, we need to clear the outdated inverse reference.
            st_update(w->obj2wmap, (st_data_t)aset_args.old_value, wmap_remove_inverse_ref, key);
        }

        if (FL_ABLE(value)) {
            // If the value has no finalizer, we don't need to keep the inverse reference
            st_update(w->obj2wmap, (st_data_t)value, wmap_aset_update, key);
        }
    }

    return nonspecial_obj_id(value);
}

/* Retrieves a weakly referenced object with the given key */
static VALUE
wmap_lookup(VALUE self, VALUE key)
{
    assert(wmap_live_p(key));

    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    st_data_t data;
    if (!st_lookup(w->wmap2obj, (st_data_t)key, &data)) return Qundef;

    VALUE obj = (VALUE)data;
    if (!wmap_live_p(obj)) return Qundef;
    return obj;
}

/* Retrieves a weakly referenced object with the given key */
static VALUE
wmap_aref(VALUE self, VALUE key)
{
    VALUE obj = wmap_lookup(self, key);
    return !UNDEF_P(obj) ? obj : Qnil;
}

/* Delete the given key from the map */
static VALUE
wmap_delete(VALUE self, VALUE key)
{
    assert(wmap_live_p(key));

    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE old_value = Qnil;
    if (st_delete(w->wmap2obj, (st_data_t *)&key, (st_data_t *)&old_value)) {
        if (FL_ABLE(old_value)) {
            // That key existed and had an inverse reference, we need to clear the outdated inverse reference.
            st_update(w->obj2wmap, (st_data_t)old_value, wmap_remove_inverse_ref, key);
        }
        return old_value;
    }
    else if (rb_block_given_p()) {
        return rb_yield(key);
    }
    else {
        return Qnil;
    }
}

/* Returns +true+ if +key+ is registered */
static VALUE
wmap_has_key(VALUE self, VALUE key)
{
    return RBOOL(!UNDEF_P(wmap_lookup(self, key)));
}

/* Returns the number of referenced objects */
static VALUE
wmap_size(VALUE self)
{
    struct weakmap *w;
    st_index_t n;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    n = w->wmap2obj->num_entries;
#if SIZEOF_ST_INDEX_T <= SIZEOF_LONG
    return ULONG2NUM(n);
#else
    return ULL2NUM(n);
#endif
}

typedef struct weakkeymap_entry {
    VALUE obj;
    st_index_t hash;
} weakkeymap_entry_t;

struct weakkeymap {
    st_table *map;
    st_table *obj2hash;
    VALUE final;
};

static int
weakkeymap_cmp_entry(st_data_t a, st_data_t b)
{
    struct weakkeymap_entry *entry_a = (struct weakkeymap_entry *)a;
    struct weakkeymap_entry *entry_b = (struct weakkeymap_entry *)b;
    if (entry_a == entry_b) {
        return 0;
    }
    else {
        return rb_any_cmp(entry_a->obj, entry_b->obj);
    }
}

static st_index_t
weakkeymap_hash_entry(st_data_t a)
{
    struct weakkeymap_entry *entry_a = (struct weakkeymap_entry *)a;
    return entry_a->hash;
}

static const struct st_hash_type weakkeymap_hash = {
    weakkeymap_cmp_entry,
    weakkeymap_hash_entry,
};

static void
wkmap_compact(void *ptr)
{
    struct weakkeymap *w = ptr;
    if (w->map) rb_gc_update_tbl_refs(w->map);
    w->final = rb_gc_location(w->final);
}

static void
wkmap_mark(void *ptr)
{
    struct weakkeymap *w = ptr;
    rb_mark_tbl_no_pin(w->map);
    rb_gc_mark_movable(w->final);
}

static void
wkmap_free(void *ptr)
{
    struct weakkeymap *w = ptr;
    st_free_table(w->map);
    st_free_table(w->obj2hash);
    xfree(w);
}

static size_t
wkmap_memsize(const void *ptr)
{
    const struct weakkeymap *w = ptr;
    return sizeof(struct weakkeymap) + st_memsize(w->map) + st_memsize(w->obj2hash);
}

static const rb_data_type_t weakkeymap_type = {
    "weakkeymap",
    {
        wkmap_mark,
        wkmap_free,
        wkmap_memsize,
        wkmap_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE
wkmap_finalize(RB_BLOCK_CALL_FUNC_ARGLIST(objid, self))
{
    struct weakkeymap *w;
    VALUE key;

    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    /* Get reference from object id. */
    if ((key = rb_gc_id2ref_obj_tbl(objid)) == Qundef) {
        rb_bug("wkmap_finalize: objid is not found.");
    }

    st_index_t hash;
    if (st_delete(w->obj2hash, (st_data_t *)key, &hash)) {
        weakkeymap_entry_t lookup_entry = {key, hash};
        weakkeymap_entry_t *deleted_entry = NULL;
        if (st_get_key(w->map, (st_data_t)&lookup_entry, (st_data_t *)deleted_entry)) {
            st_data_t deleted_value;
            st_delete(w->map, (st_data_t *)deleted_entry, &deleted_value);
            xfree(deleted_entry);
        }
    }

    return self;
}

static VALUE
wkmap_allocate(VALUE klass)
{
    struct weakkeymap *w;
    VALUE obj = TypedData_Make_Struct(klass, struct weakkeymap, &weakkeymap_type, w);
    w->map = st_init_table(&weakkeymap_hash);
    w->obj2hash = rb_init_identtable();
    RB_OBJ_WRITE(obj, &w->final, rb_func_lambda_new(wkmap_finalize, obj, 1, 1));
    return obj;
}

static st_index_t
wkmap_lookup_hash(struct weakkeymap *w, VALUE key)
{
    st_index_t hash;
    if (!st_lookup(w->obj2hash, (st_data_t)key, &hash)) {
        hash = rb_any_hash(key);
    }
    return hash;
}

static weakkeymap_entry_t*
wkmap_lookup_entry(struct weakkeymap *w, VALUE key, st_index_t hash)
{
    st_data_t data;
    weakkeymap_entry_t lookup_entry = {key, hash};

    if (st_get_key(w->map, (st_data_t)&lookup_entry, &data)) {
        return (weakkeymap_entry_t *)data;
    }

    return NULL;
}

static VALUE
wkmap_lookup(VALUE self, VALUE key)
{
    st_data_t data;
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    st_index_t hash = rb_any_hash(key);
    weakkeymap_entry_t lookup_entry = {key, hash};

    if (st_lookup(w->map, (st_data_t)&lookup_entry, &data)) {
        return (VALUE)data;
    }
    return Qundef;
}

/*
 *  call-seq:
 *    map[key] -> value
 *
 *  Returns the value associated with the given +key+ if found.
 *
 *  If +key+ is not found, returns +nil+.
 */
static VALUE
wkmap_aref(VALUE self, VALUE key)
{
    VALUE obj = wkmap_lookup(self, key);
    return obj != Qundef ? obj : Qnil;
}

/*
 *  call-seq:
 *    map[key] = value -> value
 *
 *  Associates the given +value+ with the given +key+; returns +value+.
 *
 *  The reference to +key+ is weak, so when there is no other reference
 *  to +key+ it may be garbage collected.
 *
 *  If the given +key+ exists, replaces its value with the given +value+;
 *  the ordering is not affected
 */
static VALUE
wkmap_aset(VALUE self, VALUE key, VALUE value)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    if (!FL_ABLE(key) || SYMBOL_P(key) || RB_BIGNUM_TYPE_P(key) || RB_TYPE_P(key, T_FLOAT)) {
        rb_raise(rb_eArgError, "WeakKeyMap must be garbage collectable");
        UNREACHABLE_RETURN(Qnil);
    }

    st_index_t hash = wkmap_lookup_hash(w, key);
    weakkeymap_entry_t *key_entry = wkmap_lookup_entry(w, key, hash);

    if (!key_entry) {
        key_entry = ALLOC(weakkeymap_entry_t);
        key_entry->obj = key;
        key_entry->hash = hash;
    }

    if (!st_insert(w->map, (st_data_t)key_entry, (st_data_t)value)) {
        st_insert(w->obj2hash, (st_data_t)key, (st_data_t)hash);
        rb_define_finalizer_no_check(key, w->final);
    }

    RB_OBJ_WRITTEN(self, Qundef, value);

    return value;
}

/*
 *  call-seq:
 *    map.delete(key) -> value or nil
 *    map.delete(key) {|key| ... } -> object
 *
 *  Deletes the entry for the given +key+ and returns its associated value.
 *
 *  If no block is given and +key+ is found, deletes the entry and returns the associated value:
 *    m = ObjectSpace::WeakKeyMap.new
 *    m["foo"] = 1
 *    m.delete("foo") # => 1
 *    m["foo"] # => nil
 *
 *  If no block given and +key+ is not found, returns +nil+.
 *
 *  If a block is given and +key+ is found, ignores the block,
 *  deletes the entry, and returns the associated value:
 *    m = ObjectSpace::WeakKeyMap.new
 *    m["foo"] = 2
 *    h.delete("foo") { |key| raise 'Will never happen'} # => 2
 *
 *  If a block is given and +key+ is not found,
 *  calls the block and returns the block's return value:
 *    m = ObjectSpace::WeakKeyMap.new
 *    h.delete("nosuch") { |key| "Key #{key} not found" } # => "Key nosuch not found"
 */

static VALUE
wkmap_delete(VALUE self, VALUE key)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    st_index_t hash = rb_any_hash(key);
    weakkeymap_entry_t lookup_entry = {key, hash};
    weakkeymap_entry_t *deleted_entry = NULL;
    if (st_get_key(w->map, (st_data_t)&lookup_entry, (st_data_t *)&deleted_entry)) {
        st_data_t deleted_value;
        if (st_delete(w->map, (st_data_t *)&deleted_entry, &deleted_value)) {
            xfree(deleted_entry);
            st_delete(w->obj2hash, (st_data_t *)key, &hash);
            return (VALUE)deleted_value;
        }
        else {
            rb_bug("WeakKeyMap: miss on delete, corrupted memory?");
        }
    }
    else if (rb_block_given_p()) {
        return rb_yield(key);
    }
    else {
        return Qnil;
    }
}

/*
 *  call-seq:
 *    map.getkey(key) -> existing_key or nil
 *
 *  Returns the existing equal key if it exists, otherwise returns +nil+.
 */
static VALUE
wkmap_getkey(VALUE self, VALUE key)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    st_index_t hash = rb_any_hash(key);
    weakkeymap_entry_t lookup_entry = {key, hash};

    weakkeymap_entry_t *key_entry = NULL;
    if (st_get_key(w->map, (st_data_t)&lookup_entry, (st_data_t *)&key_entry)) {
        assert(key_entry != NULL);

        VALUE obj = key_entry->obj;
        if (wmap_live_p(obj)) {
            return obj;
        }
    }
    return Qnil;
}

/*
 *  call-seq:
 *    hash.key?(key) -> true or false
 *
 *  Returns +true+ if +key+ is a key in +self+, otherwise +false+.
 */
static VALUE
wkmap_has_key(VALUE self, VALUE key)
{
    return RBOOL(wkmap_lookup(self, key) != Qundef);
}

/*
 *  call-seq:
 *    map.clear -> self
 *
 *  Removes all map entries; returns +self+.
 */
static VALUE
wkmap_clear(VALUE self)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);
    if (w->map) {
        st_clear(w->map);
    }
    if (w->obj2hash) {
        st_clear(w->obj2hash);
    }
    return self;
}

/*
 *  call-seq:
 *    map.inspect -> new_string
 *
 *  Returns a new \String containing informations about the map:

 *    m = ObjectSpace::WeakKeyMap.new
 *    m[key] = value
 *    m.inspect # => "#<ObjectSpace::WeakKeyMap:0x00000001028dcba8 size=1>"
 *
 */
static VALUE
wkmap_inspect(VALUE self)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    st_index_t n = 0;
    if (w->map) {
        n = w->map->num_entries;
    }

#if SIZEOF_ST_INDEX_T <= SIZEOF_LONG
    const char * format = "#<%"PRIsVALUE":%p size=%lu>";
#else
    const char * format = "#<%"PRIsVALUE":%p size=%llu>";
#endif

    VALUE str = rb_sprintf(format, rb_class_name(CLASS_OF(self)), (void *)self, n);
    return str;
}

/*
 *  Document-class: ObjectSpace::WeakMap
 *
 *  An ObjectSpace::WeakMap object holds references to
 *  any objects, but those objects can get garbage collected.
 *
 *  This class is mostly used internally by WeakRef, please use
 *  +lib/weakref.rb+ for the public interface.
 */

/*
 *  Document-class: ObjectSpace::WeakKeyMap
 *
 *  An ObjectSpace::WeakKeyMap object holds references to
 *  any objects, but objects uses as keys can be garbage collected.
 *
 *  Objects used as values can't be garbage collected until the key is.
 */

void
Init_WeakMap(void)
{
    VALUE rb_mObjectSpace = rb_define_module("ObjectSpace");

    VALUE rb_cWeakMap = rb_define_class_under(rb_mObjectSpace, "WeakMap", rb_cObject);
    rb_define_alloc_func(rb_cWeakMap, wmap_allocate);
    rb_define_method(rb_cWeakMap, "[]=", wmap_aset, 2);
    rb_define_method(rb_cWeakMap, "[]", wmap_aref, 1);
    rb_define_method(rb_cWeakMap, "delete", wmap_delete, 1);
    rb_define_method(rb_cWeakMap, "include?", wmap_has_key, 1);
    rb_define_method(rb_cWeakMap, "member?", wmap_has_key, 1);
    rb_define_method(rb_cWeakMap, "key?", wmap_has_key, 1);
    rb_define_method(rb_cWeakMap, "inspect", wmap_inspect, 0);
    rb_define_method(rb_cWeakMap, "each", wmap_each, 0);
    rb_define_method(rb_cWeakMap, "each_pair", wmap_each, 0);
    rb_define_method(rb_cWeakMap, "each_key", wmap_each_key, 0);
    rb_define_method(rb_cWeakMap, "each_value", wmap_each_value, 0);
    rb_define_method(rb_cWeakMap, "keys", wmap_keys, 0);
    rb_define_method(rb_cWeakMap, "values", wmap_values, 0);
    rb_define_method(rb_cWeakMap, "size", wmap_size, 0);
    rb_define_method(rb_cWeakMap, "length", wmap_size, 0);
    rb_include_module(rb_cWeakMap, rb_mEnumerable);

    VALUE rb_cWeakKeyMap = rb_define_class_under(rb_mObjectSpace, "WeakKeyMap", rb_cObject);
    rb_define_alloc_func(rb_cWeakKeyMap, wkmap_allocate);
    rb_define_method(rb_cWeakKeyMap, "[]=", wkmap_aset, 2);
    rb_define_method(rb_cWeakKeyMap, "[]", wkmap_aref, 1);
    rb_define_method(rb_cWeakKeyMap, "delete", wkmap_delete, 1);
    rb_define_method(rb_cWeakKeyMap, "getkey", wkmap_getkey, 1);
    rb_define_method(rb_cWeakKeyMap, "key?", wkmap_has_key, 1);
    rb_define_method(rb_cWeakKeyMap, "clear", wkmap_clear, 0);
    rb_define_method(rb_cWeakKeyMap, "inspect", wkmap_inspect, 0);
}
