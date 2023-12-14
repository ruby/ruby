#include "internal.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/proc.h"
#include "internal/sanitizers.h"
#include "ruby/st.h"
#include "ruby/st.h"

/* ===== WeakMap =====
 *
 * WeakMap contains one ST table which contains a pointer to the object as the
 * key and a pointer to the object as the value. This means that the key and
 * value of the table are both of the type `VALUE *`.
 *
 * The objects are not directly stored as keys and values in the table because
 * `rb_gc_mark_weak` requires a pointer to the memory location to overwrite
 * when the object is reclaimed. Using a pointer into the ST table entry is not
 * safe because the pointer can change when the ST table is resized.
 *
 * WeakMap hashes and compares using the pointer address of the object.
 *
 * For performance and memory efficiency reasons, the key and value
 * are allocated at the same time and adjacent to each other.
 *
 * During GC and while iterating, reclaimed entries (i.e. either the key or
 * value points to `Qundef`) are removed from the ST table.
 */

struct weakmap {
    st_table *table;
};

static bool
wmap_live_p(VALUE obj)
{
    return !UNDEF_P(obj);
}

static void
wmap_free_entry(VALUE *key, VALUE *val)
{
    assert(key + 1 == val);

    /* We only need to free key because val is allocated beside key on in the
     * same malloc call. */
    ruby_sized_xfree(key, sizeof(VALUE) * 2);
}

static int
wmap_mark_weak_table_i(st_data_t key, st_data_t val, st_data_t _)
{
    VALUE key_obj = *(VALUE *)key;
    VALUE val_obj = *(VALUE *)val;

    if (wmap_live_p(key_obj) && wmap_live_p(val_obj)) {
        rb_gc_mark_weak((VALUE *)key);
        rb_gc_mark_weak((VALUE *)val);

        return ST_CONTINUE;
    }
    else {
        wmap_free_entry((VALUE *)key, (VALUE *)val);

        return ST_DELETE;
    }
}

static void
wmap_mark(void *ptr)
{
    struct weakmap *w = ptr;
    if (w->table) {
        st_foreach(w->table, wmap_mark_weak_table_i, (st_data_t)0);
    }
}

static int
wmap_free_table_i(st_data_t key, st_data_t val, st_data_t arg)
{
    wmap_free_entry((VALUE *)key, (VALUE *)val);
    return ST_CONTINUE;
}

static void
wmap_free(void *ptr)
{
    struct weakmap *w = ptr;

    st_foreach(w->table, wmap_free_table_i, 0);
    st_free_table(w->table);
}

static size_t
wmap_memsize(const void *ptr)
{
    const struct weakmap *w = ptr;

    size_t size = 0;
    size += st_memsize(w->table);
    /* The key and value of the table each take sizeof(VALUE) in size. */
    size += st_table_size(w->table) * (2 * sizeof(VALUE));

    return size;
}

static int
wmap_compact_table_i(st_data_t key, st_data_t val, st_data_t data)
{
    st_table *table = (st_table *)data;

    VALUE key_obj = *(VALUE *)key;
    VALUE val_obj = *(VALUE *)val;

    if (wmap_live_p(key_obj) && wmap_live_p(val_obj)) {
        VALUE new_key_obj = rb_gc_location(key_obj);

        *(VALUE *)val = rb_gc_location(val_obj);

        /* If the key object moves, then we must reinsert because the hash is
         * based on the pointer rather than the object itself. */
        if (key_obj != new_key_obj) {
            *(VALUE *)key = new_key_obj;

            DURING_GC_COULD_MALLOC_REGION_START();
            {
                st_insert(table, key, val);
            }
            DURING_GC_COULD_MALLOC_REGION_END();

            return ST_DELETE;
        }
    }
    else {
        wmap_free_entry((VALUE *)key, (VALUE *)val);

        return ST_DELETE;
    }

    return ST_CONTINUE;
}

static void
wmap_compact(void *ptr)
{
    struct weakmap *w = ptr;

    if (w->table) {
        st_foreach(w->table, wmap_compact_table_i, (st_data_t)w->table);
    }
}

static const rb_data_type_t weakmap_type = {
    "weakmap",
    {
        wmap_mark,
        wmap_free,
        wmap_memsize,
        wmap_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

static int
wmap_cmp(st_data_t x, st_data_t y)
{
    return *(VALUE *)x != *(VALUE *)y;
}

static st_index_t
wmap_hash(st_data_t n)
{
    return st_numhash(*(VALUE *)n);
}

static const struct st_hash_type wmap_hash_type = {
    wmap_cmp,
    wmap_hash,
};

static VALUE
wmap_allocate(VALUE klass)
{
    struct weakmap *w;
    VALUE obj = TypedData_Make_Struct(klass, struct weakmap, &weakmap_type, w);
    w->table = st_init_table(&wmap_hash_type);
    return obj;
}

struct wmap_foreach_data {
    struct weakmap *w;
    void (*func)(VALUE, VALUE, st_data_t);
    st_data_t arg;
};

static int
wmap_foreach_i(st_data_t key, st_data_t val, st_data_t arg)
{
    struct wmap_foreach_data *data = (struct wmap_foreach_data *)arg;

    VALUE key_obj = *(VALUE *)key;
    VALUE val_obj = *(VALUE *)val;

    if (wmap_live_p(key_obj) && wmap_live_p(val_obj)) {
        data->func(key_obj, val_obj, data->arg);
    }
    else {
        wmap_free_entry((VALUE *)key, (VALUE *)val);

        return ST_DELETE;
    }

    return ST_CONTINUE;
}

static void
wmap_foreach(struct weakmap *w, void (*func)(VALUE, VALUE, st_data_t), st_data_t arg)
{
    struct wmap_foreach_data foreach_data = {
        .w = w,
        .func = func,
        .arg = arg,
    };

    st_foreach(w->table, wmap_foreach_i, (st_data_t)&foreach_data);
}

static VALUE
wmap_inspect_append(VALUE str, VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) {
        return rb_str_append(str, rb_inspect(obj));
    }
    else {
        return rb_str_append(str, rb_any_to_s(obj));
    }
}

static void
wmap_inspect_i(VALUE key, VALUE val, st_data_t data)
{
    VALUE str = (VALUE)data;

    if (RSTRING_PTR(str)[0] == '#') {
        rb_str_cat2(str, ", ");
    }
    else {
        rb_str_cat2(str, ": ");
        RSTRING_PTR(str)[0] = '#';
    }

    wmap_inspect_append(str, key);
    rb_str_cat2(str, " => ");
    wmap_inspect_append(str, val);
}

static VALUE
wmap_inspect(VALUE self)
{
    VALUE c = rb_class_name(CLASS_OF(self));
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE str = rb_sprintf("-<%"PRIsVALUE":%p", c, (void *)self);

    wmap_foreach(w, wmap_inspect_i, (st_data_t)str);

    RSTRING_PTR(str)[0] = '#';
    rb_str_cat2(str, ">");

    return str;
}

static void
wmap_each_i(VALUE key, VALUE val, st_data_t _)
{
    rb_yield_values(2, key, val);
}

/*
 * call-seq:
 *   map.each {|key, val| ... } -> self
 *
 * Iterates over keys and values. Note that unlike other collections,
 * +each+ without block isn't supported.
 *
 */
static VALUE
wmap_each(VALUE self)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    wmap_foreach(w, wmap_each_i, (st_data_t)0);

    return self;
}

static void
wmap_each_key_i(VALUE key, VALUE _val, st_data_t _data)
{
    rb_yield(key);
}

/*
 * call-seq:
 *   map.each_key {|key| ... } -> self
 *
 * Iterates over keys. Note that unlike other collections,
 * +each_key+ without block isn't supported.
 *
 */
static VALUE
wmap_each_key(VALUE self)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    wmap_foreach(w, wmap_each_key_i, (st_data_t)0);

    return self;
}

static void
wmap_each_value_i(VALUE _key, VALUE val, st_data_t _data)
{
    rb_yield(val);
}

/*
 * call-seq:
 *   map.each_value {|val| ... } -> self
 *
 * Iterates over values. Note that unlike other collections,
 * +each_value+ without block isn't supported.
 *
 */
static VALUE
wmap_each_value(VALUE self)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    wmap_foreach(w, wmap_each_value_i, (st_data_t)0);

    return self;
}

static void
wmap_keys_i(st_data_t key, st_data_t _, st_data_t arg)
{
    VALUE ary = (VALUE)arg;

    rb_ary_push(ary, key);
}

/*
 * call-seq:
 *   map.keys -> new_array
 *
 * Returns a new Array containing all keys in the map.
 *
 */
static VALUE
wmap_keys(VALUE self)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE ary = rb_ary_new();
    wmap_foreach(w, wmap_keys_i, (st_data_t)ary);

    return ary;
}

static void
wmap_values_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE ary = (VALUE)arg;

    rb_ary_push(ary, (VALUE)val);
}

/*
 * call-seq:
 *   map.values -> new_array
 *
 * Returns a new Array containing all values in the map.
 *
 */
static VALUE
wmap_values(VALUE self)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE ary = rb_ary_new();
    wmap_foreach(w, wmap_values_i, (st_data_t)ary);

    return ary;
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

static int
wmap_aset_replace(st_data_t *key, st_data_t *val, st_data_t new_key_ptr, int existing)
{
    VALUE new_key = *(VALUE *)new_key_ptr;
    VALUE new_val = *(((VALUE *)new_key_ptr) + 1);

    if (existing) {
        assert(*(VALUE *)*key == new_key);
    }
    else {
        VALUE *pair = xmalloc(sizeof(VALUE) * 2);

        *key = (st_data_t)pair;
        *val = (st_data_t)(pair + 1);
    }

    *(VALUE *)*key = new_key;
    *(VALUE *)*val = new_val;

    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    map[key] = value -> value
 *
 *  Associates the given +value+ with the given +key+.
 *
 *  If the given +key+ exists, replaces its value with the given +value+;
 *  the ordering is not affected.
 */
static VALUE
wmap_aset(VALUE self, VALUE key, VALUE val)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE pair[2] = { key, val };

    st_update(w->table, (st_data_t)pair, wmap_aset_replace, (st_data_t)pair);

    RB_OBJ_WRITTEN(self, Qundef, key);
    RB_OBJ_WRITTEN(self, Qundef, val);

    return nonspecial_obj_id(val);
}

/* Retrieves a weakly referenced object with the given key */
static VALUE
wmap_lookup(VALUE self, VALUE key)
{
    assert(wmap_live_p(key));

    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    st_data_t data;
    if (!st_lookup(w->table, (st_data_t)&key, &data)) return Qundef;

    if (!wmap_live_p(*(VALUE *)data)) return Qundef;

    return *(VALUE *)data;
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
wmap_aref(VALUE self, VALUE key)
{
    VALUE obj = wmap_lookup(self, key);
    return !UNDEF_P(obj) ? obj : Qnil;
}

/*
 *  call-seq:
 *    map.delete(key) -> value or nil
 *    map.delete(key) {|key| ... } -> object
 *
 *  Deletes the entry for the given +key+ and returns its associated value.
 *
 *  If no block is given and +key+ is found, deletes the entry and returns the associated value:
 *    m = ObjectSpace::WeakMap.new
 *    key = "foo"
 *    m[key] = 1
 *    m.delete(key) # => 1
 *    m[key] # => nil
 *
 *  If no block is given and +key+ is not found, returns +nil+.
 *
 *  If a block is given and +key+ is found, ignores the block,
 *  deletes the entry, and returns the associated value:
 *    m = ObjectSpace::WeakMap.new
 *    key = "foo"
 *    m[key] = 2
 *    m.delete(key) { |key| raise 'Will never happen'} # => 2
 *
 *  If a block is given and +key+ is not found,
 *  yields the +key+ to the block and returns the block's return value:
 *    m = ObjectSpace::WeakMap.new
 *    m.delete("nosuch") { |key| "Key #{key} not found" } # => "Key nosuch not found"
 */
static VALUE
wmap_delete(VALUE self, VALUE key)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    VALUE orig_key = key;
    st_data_t orig_key_data = (st_data_t)&orig_key;
    st_data_t orig_val_data;
    if (st_delete(w->table, &orig_key_data, &orig_val_data)) {
        VALUE orig_val = *(VALUE *)orig_val_data;

        rb_gc_remove_weak(self, (VALUE *)orig_key_data);
        rb_gc_remove_weak(self, (VALUE *)orig_val_data);

        wmap_free_entry((VALUE *)orig_key_data, (VALUE *)orig_val_data);

        if (wmap_live_p(orig_val)) {
            return orig_val;
        }
    }

    if (rb_block_given_p()) {
        return rb_yield(key);
    }
    else {
        return Qnil;
    }
}

/*
 *  call-seq:
 *    map.key?(key) -> true or false
 *
 *  Returns +true+ if +key+ is a key in +self+, otherwise +false+.
 */
static VALUE
wmap_has_key(VALUE self, VALUE key)
{
    return RBOOL(!UNDEF_P(wmap_lookup(self, key)));
}

/*
 * call-seq:
 *   map.size -> number
 *
 * Returns the number of referenced objects
 */
static VALUE
wmap_size(VALUE self)
{
    struct weakmap *w;
    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);

    st_index_t n = st_table_size(w->table);

#if SIZEOF_ST_INDEX_T <= SIZEOF_LONG
    return ULONG2NUM(n);
#else
    return ULL2NUM(n);
#endif
}

/* ===== WeakKeyMap =====
 *
 * WeakKeyMap contains one ST table which contains a pointer to the object as
 * the key and the object as the value. This means that the key is of the type
 * `VALUE *` while the value is of the type `VALUE`.
 *
 * The object is not not directly stored as keys in the table because
 * `rb_gc_mark_weak` requires a pointer to the memory location to overwrite
 * when the object is reclaimed. Using a pointer into the ST table entry is not
 * safe because the pointer can change when the ST table is resized.
 *
 * WeakKeyMap hashes and compares using the `#hash` and `#==` methods of the
 * object, respectively.
 *
 * During GC and while iterating, reclaimed entries (i.e. the key points to
 * `Qundef`) are removed from the ST table.
 */

struct weakkeymap {
    st_table *table;
};

static int
wkmap_mark_table_i(st_data_t key, st_data_t val_obj, st_data_t _)
{
    VALUE key_obj = *(VALUE *)key;

    if (wmap_live_p(key_obj)) {
        rb_gc_mark_weak((VALUE *)key);
        rb_gc_mark_movable((VALUE)val_obj);

        return ST_CONTINUE;
    }
    else {
        ruby_sized_xfree((VALUE *)key, sizeof(VALUE));

        return ST_DELETE;
    }
}

static void
wkmap_mark(void *ptr)
{
    struct weakkeymap *w = ptr;
    if (w->table) {
        st_foreach(w->table, wkmap_mark_table_i, (st_data_t)0);
    }
}

static int
wkmap_free_table_i(st_data_t key, st_data_t _val, st_data_t _arg)
{
    ruby_sized_xfree((VALUE *)key, sizeof(VALUE));
    return ST_CONTINUE;
}

static void
wkmap_free(void *ptr)
{
    struct weakkeymap *w = ptr;

    st_foreach(w->table, wkmap_free_table_i, 0);
    st_free_table(w->table);
}

static size_t
wkmap_memsize(const void *ptr)
{
    const struct weakkeymap *w = ptr;

    size_t size = 0;
    size += st_memsize(w->table);
    /* Each key of the table takes sizeof(VALUE) in size. */
    size += st_table_size(w->table) * sizeof(VALUE);

    return size;
}

static int
wkmap_compact_table_i(st_data_t key, st_data_t val_obj, st_data_t _data, int _error)
{
    VALUE key_obj = *(VALUE *)key;

    if (wmap_live_p(key_obj)) {
        if (key_obj != rb_gc_location(key_obj) || val_obj != rb_gc_location(val_obj)) {
            return ST_REPLACE;
        }
    }
    else {
        ruby_sized_xfree((VALUE *)key, sizeof(VALUE));

        return ST_DELETE;
    }

    return ST_CONTINUE;
}

static int
wkmap_compact_table_replace(st_data_t *key_ptr, st_data_t *val_ptr, st_data_t _data, int existing)
{
    assert(existing);

    *(VALUE *)*key_ptr = rb_gc_location(*(VALUE *)*key_ptr);
    *val_ptr = (st_data_t)rb_gc_location((VALUE)*val_ptr);

    return ST_CONTINUE;
}

static void
wkmap_compact(void *ptr)
{
    struct weakkeymap *w = ptr;

    if (w->table) {
        st_foreach_with_replace(w->table, wkmap_compact_table_i, wkmap_compact_table_replace, (st_data_t)0);
    }
}

static const rb_data_type_t weakkeymap_type = {
    "weakkeymap",
    {
        wkmap_mark,
        wkmap_free,
        wkmap_memsize,
        wkmap_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

static int
wkmap_cmp(st_data_t x, st_data_t y)
{
    VALUE x_obj = *(VALUE *)x;
    VALUE y_obj = *(VALUE *)y;

    if (wmap_live_p(x_obj) && wmap_live_p(y_obj)) {
        return rb_any_cmp(x_obj, y_obj);
    }
    else {
        /* If one of the objects is dead, then they cannot be the same. */
        return 1;
    }
}

static st_index_t
wkmap_hash(st_data_t n)
{
    VALUE obj = *(VALUE *)n;
    assert(wmap_live_p(obj));

    return rb_any_hash(obj);
}

static const struct st_hash_type wkmap_hash_type = {
    wkmap_cmp,
    wkmap_hash,
};

static VALUE
wkmap_allocate(VALUE klass)
{
    struct weakkeymap *w;
    VALUE obj = TypedData_Make_Struct(klass, struct weakkeymap, &weakkeymap_type, w);
    w->table = st_init_table(&wkmap_hash_type);
    return obj;
}

static VALUE
wkmap_lookup(VALUE self, VALUE key)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    st_data_t data;
    if (!st_lookup(w->table, (st_data_t)&key, &data)) return Qundef;

    return (VALUE)data;
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

struct wkmap_aset_args {
    VALUE new_key;
    VALUE new_val;
};

static int
wkmap_aset_replace(st_data_t *key, st_data_t *val, st_data_t data_args, int existing)
{
    struct wkmap_aset_args *args = (struct wkmap_aset_args *)data_args;

    if (!existing) {
        *key = (st_data_t)xmalloc(sizeof(VALUE));
    }

    *(VALUE *)*key = args->new_key;
    *val = (st_data_t)args->new_val;

    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    map[key] = value -> value
 *
 *  Associates the given +value+ with the given +key+
 *
 *  The reference to +key+ is weak, so when there is no other reference
 *  to +key+ it may be garbage collected.
 *
 *  If the given +key+ exists, replaces its value with the given +value+;
 *  the ordering is not affected
 */
static VALUE
wkmap_aset(VALUE self, VALUE key, VALUE val)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    if (!FL_ABLE(key) || SYMBOL_P(key) || RB_BIGNUM_TYPE_P(key) || RB_TYPE_P(key, T_FLOAT)) {
        rb_raise(rb_eArgError, "WeakKeyMap must be garbage collectable");
        UNREACHABLE_RETURN(Qnil);
    }

    struct wkmap_aset_args args = {
        .new_key = key,
        .new_val = val,
    };

    st_update(w->table, (st_data_t)&key, wkmap_aset_replace, (st_data_t)&args);

    RB_OBJ_WRITTEN(self, Qundef, key);
    RB_OBJ_WRITTEN(self, Qundef, val);

    return val;
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
 *    key = "foo" # to hold reference to the key
 *    m[key] = 1
 *    m.delete("foo") # => 1
 *    m["foo"] # => nil
 *
 *  If no block given and +key+ is not found, returns +nil+.
 *
 *  If a block is given and +key+ is found, ignores the block,
 *  deletes the entry, and returns the associated value:
 *    m = ObjectSpace::WeakKeyMap.new
 *    key = "foo" # to hold reference to the key
 *    m[key] = 2
 *    m.delete("foo") { |key| raise 'Will never happen'} # => 2
 *
 *  If a block is given and +key+ is not found,
 *  yields the +key+ to the block and returns the block's return value:
 *    m = ObjectSpace::WeakKeyMap.new
 *    m.delete("nosuch") { |key| "Key #{key} not found" } # => "Key nosuch not found"
 */

static VALUE
wkmap_delete(VALUE self, VALUE key)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    VALUE orig_key = key;
    st_data_t orig_key_data = (st_data_t)&orig_key;
    st_data_t orig_val_data;
    if (st_delete(w->table, &orig_key_data, &orig_val_data)) {
        VALUE orig_val = (VALUE)orig_val_data;

        rb_gc_remove_weak(self, (VALUE *)orig_key_data);

        ruby_sized_xfree((VALUE *)orig_key_data, sizeof(VALUE));

        return orig_val;
    }

    if (rb_block_given_p()) {
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
 *
 *  This might be useful for implementing caches, so that only one copy of
 *  some object would be used everywhere in the program:
 *
 *    value = {amount: 1, currency: 'USD'}
 *
 *    # Now if we put this object in a cache:
 *    cache = ObjectSpace::WeakKeyMap.new
 *    cache[value] = true
 *
 *    # ...we can always extract from there and use the same object:
 *    copy = cache.getkey({amount: 1, currency: 'USD'})
 *    copy.object_id == value.object_id #=> true
 */
static VALUE
wkmap_getkey(VALUE self, VALUE key)
{
    struct weakkeymap *w;
    TypedData_Get_Struct(self, struct weakkeymap, &weakkeymap_type, w);

    st_data_t orig_key;
    if (!st_get_key(w->table, (st_data_t)&key, &orig_key)) return Qnil;

    return *(VALUE *)orig_key;
}

/*
 *  call-seq:
 *    map.key?(key) -> true or false
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

    st_foreach(w->table, wkmap_free_table_i, 0);
    st_clear(w->table);

    return self;
}

/*
 *  call-seq:
 *    map.inspect -> new_string
 *
 *  Returns a new String containing informations about the map:
 *
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

    st_index_t n = st_table_size(w->table);

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
 *  An ObjectSpace::WeakMap is a key-value map that holds weak references
 *  to its keys and values, so they can be garbage-collected when there are
 *  no more references left.
 *
 *  Keys in the map are compared by identity.
 *
 *     m = ObjectSpace::WeekMap.new
 *     key1 = "foo"
 *     val1 = Object.new
 *     m[key1] = val1
 *
 *     key2 = "foo"
 *     val2 = Object.new
 *     m[key2] = val2
 *
 *     m[key1] #=> #<Object:0x0...>
 *     m[key2] #=> #<Object:0x0...>
 *
 *     val1 = nil # remove the other reference to value
 *     GC.start
 *
 *     m[key1] #=> nil
 *     m.keys #=> ["bar"]
 *
 *     key2 = nil # remove the other reference to key
 *     GC.start
 *
 *     m[key2] #=> nil
 *     m.keys #=> []
 *
 *  (Note that GC.start is used here only for demonstrational purposes and might
 *  not always lead to demonstrated results.)
 *
 *
 *  See also ObjectSpace::WeakKeyMap map class, which compares keys by value,
 *  and holds weak references only to the keys.
 */

/*
 *  Document-class: ObjectSpace::WeakKeyMap
 *
 *  An ObjectSpace::WeakKeyMap is a key-value map that holds weak references
 *  to its keys, so they can be garbage collected when there is no more references.
 *
 *  Unlike ObjectSpace::WeakMap:
 *
 *  * references to values are _strong_, so they aren't garbage collected while
 *    they are in the map;
 *  * keys are compared by value (using Object#eql?), not by identity;
 *  * only garbage-collectable objects can be used as keys.
 *
 *       map = ObjectSpace::WeakKeyMap.new
 *       val = Time.new(2023, 12, 7)
 *       key = "name"
 *       map[key] = val
 *
 *       # Value is fetched by equality: the instance of string "name" is
 *       # different here, but it is equal to the key
 *       map["name"] #=> 2023-12-07 00:00:00 +0200
 *
 *       val = nil
 *       GC.start
 *       # There is no more references to `val`, yet the pair isn't
 *       # garbage-collected.
 *       map["name"] #=> 2023-12-07 00:00:00 +0200
 *
 *       key = nil
 *       GC.start
 *       # There is no more references to `key`, key and value are
 *       # garbage-collected.
 *       map["name"] #=> nil
 *
 *  (Note that GC.start is used here only for demonstrational purposes and might
 *  not always lead to demonstrated results.)
 *
 *  The collection is especially useful for implementing caches of lightweight value
 *  objects, so that only one copy of each value representation would be stored in
 *  memory, but the copies that aren't used would be garbage-collected.
 *
 *    CACHE = ObjectSpace::WeakKeyMap
 *
 *    def make_value(**)
 *       val = ValueObject.new(**)
 *       if (existing = @cache.getkey(val))
 *          # if the object with this value exists, we return it
 *          existing
 *       else
 *          # otherwise, put it in the cache
 *          @cache[val] = true
 *          val
 *       end
 *    end
 *
 *  This will result in +make_value+ returning the same object for same set of attributes
 *  always, but the values that aren't needed anymore woudn't be sitting in the cache forever.
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
