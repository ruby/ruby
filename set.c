/* This implements sets using the same hash table implementation as in
   st.c, but without a value for each hash entry.  This results in the
   same basic performance characteristics as when using an st table,
   but uses 1/3 less memory.
   */

#include "id.h"
#include "internal.h"
#include "internal/bits.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/proc.h"
#include "internal/sanitizers.h"
#include "internal/set_table.h"
#include "internal/symbol.h"
#include "internal/variable.h"
#include "ruby_assert.h"

#include <stdio.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <string.h>

#ifndef SET_DEBUG
#define SET_DEBUG 0
#endif

#if SET_DEBUG
#include "internal/gc.h"
#endif

static st_index_t
dbl_to_index(double d)
{
    union {double d; st_index_t i;} u;
    u.d = d;
    return u.i;
}

static const uint64_t prime1 = ((uint64_t)0x2e0bb864 << 32) | 0xe9ea7df5;
static const uint32_t prime2 = 0x830fcab9;

static inline uint64_t
mult_and_mix(uint64_t m1, uint64_t m2)
{
#if defined HAVE_UINT128_T
    uint128_t r = (uint128_t) m1 * (uint128_t) m2;
    return (uint64_t) (r >> 64) ^ (uint64_t) r;
#else
    uint64_t hm1 = m1 >> 32, hm2 = m2 >> 32;
    uint64_t lm1 = m1, lm2 = m2;
    uint64_t v64_128 = hm1 * hm2;
    uint64_t v32_96 = hm1 * lm2 + lm1 * hm2;
    uint64_t v1_32 = lm1 * lm2;

    return (v64_128 + (v32_96 >> 32)) ^ ((v32_96 << 32) + v1_32);
#endif
}

static inline uint64_t
key64_hash(uint64_t key, uint32_t seed)
{
    return mult_and_mix(key + seed, prime1);
}

/* Should cast down the result for each purpose */
#define set_index_hash(index) key64_hash(rb_hash_start(index), prime2)

static st_index_t
set_ident_hash(st_data_t n)
{
#ifdef USE_FLONUM /* RUBY */
    /*
     * - flonum (on 64-bit) is pathologically bad, mix the actual
     *   float value in, but do not use the float value as-is since
     *   many integers get interpreted as 2.0 or -2.0 [Bug #10761]
     */
    if (FLONUM_P(n)) {
        n ^= dbl_to_index(rb_float_value(n));
    }
#endif

    return (st_index_t)set_index_hash((st_index_t)n);
}

static const struct st_hash_type identhash = {
    rb_st_numcmp,
    set_ident_hash,
};

static const struct st_hash_type objhash = {
    rb_any_cmp,
    rb_any_hash,
};

VALUE rb_cSet;

#define id_each idEach
static ID id_each_entry;
static ID id_any_p;
static ID id_new;
static ID id_i_hash;
static ID id_set_iter_lev;

#define RSET_INITIALIZED FL_USER1
#define RSET_LEV_MASK (FL_USER13 | FL_USER14 | FL_USER15 |                /* FL 13..19 */ \
                        FL_USER16 | FL_USER17 | FL_USER18 | FL_USER19)
#define RSET_LEV_SHIFT (FL_USHIFT + 13)
#define RSET_LEV_MAX 127 /* 7 bits */

#define SET_ASSERT(expr) RUBY_ASSERT_MESG_WHEN(SET_DEBUG, expr, #expr)

#define RSET_SIZE(set) set_table_size(RSET_TABLE(set))
#define RSET_EMPTY(set) (RSET_SIZE(set) == 0)
#define RSET_SIZE_NUM(set) SIZET2NUM(RSET_SIZE(set))
#define RSET_IS_MEMBER(sobj, item) set_table_lookup(RSET_TABLE(set), (st_data_t)(item))
#define RSET_COMPARE_BY_IDENTITY(set) (RSET_TABLE(set)->type == &identhash)

struct set_object {
    set_table table;
};

static int
mark_key(st_data_t key, st_data_t data)
{
    rb_gc_mark_movable((VALUE)key);

    return ST_CONTINUE;
}

static void
set_mark(void *ptr)
{
    struct set_object *sobj = ptr;
    if (sobj->table.entries) set_table_foreach(&sobj->table, mark_key, 0);
}

static void
set_free_embedded(struct set_object *sobj)
{
    free((&sobj->table)->bins);
    free((&sobj->table)->entries);
}

static void
set_free(void *ptr)
{
    struct set_object *sobj = ptr;
    set_free_embedded(sobj);
    memset(&sobj->table, 0, sizeof(sobj->table));
}

static size_t
set_size(const void *ptr)
{
    const struct set_object *sobj = ptr;
    /* Do not count the table size twice, as it is embedded */
    return (unsigned long)set_memsize(&sobj->table) - sizeof(sobj->table);
}

static int
set_foreach_replace(st_data_t key, st_data_t argp, int error)
{
    if (rb_gc_location((VALUE)key) != (VALUE)key) {
        return ST_REPLACE;
    }

    return ST_CONTINUE;
}

static int
set_replace_ref(st_data_t *key, st_data_t argp, int existing)
{
    if (rb_gc_location((VALUE)*key) != (VALUE)*key) {
        *key = rb_gc_location((VALUE)*key);
    }

    return ST_CONTINUE;
}

static void
set_update_references(void *ptr)
{
    struct set_object *sobj = ptr;
    set_foreach_with_replace(&sobj->table, set_foreach_replace, set_replace_ref, 0);
}

static const rb_data_type_t set_data_type = {
    .wrap_struct_name = "set",
    .function = {
        .dmark = set_mark,
        .dfree = set_free,
        .dsize = set_size,
        .dcompact = set_update_references,
    },
    .flags = RUBY_TYPED_EMBEDDABLE | RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FROZEN_SHAREABLE
};

static inline set_table *
RSET_TABLE(VALUE set)
{
    struct set_object *sobj;
    TypedData_Get_Struct(set, struct set_object, &set_data_type, sobj);
    return &sobj->table;
}

static unsigned long
iter_lev_in_ivar(VALUE set)
{
    VALUE levval = rb_ivar_get(set, id_set_iter_lev);
    SET_ASSERT(FIXNUM_P(levval));
    long lev = FIX2LONG(levval);
    SET_ASSERT(lev >= 0);
    return (unsigned long)lev;
}

void rb_ivar_set_internal(VALUE obj, ID id, VALUE val);

static void
iter_lev_in_ivar_set(VALUE set, unsigned long lev)
{
    SET_ASSERT(lev >= RSET_LEV_MAX);
    SET_ASSERT(POSFIXABLE(lev)); /* POSFIXABLE means fitting to long */
    rb_ivar_set_internal(set, id_set_iter_lev, LONG2FIX((long)lev));
}

static inline unsigned long
iter_lev_in_flags(VALUE set)
{
    return (unsigned long)((RBASIC(set)->flags >> RSET_LEV_SHIFT) & RSET_LEV_MAX);
}

static inline void
iter_lev_in_flags_set(VALUE set, unsigned long lev)
{
    SET_ASSERT(lev <= RSET_LEV_MAX);
    RBASIC(set)->flags = ((RBASIC(set)->flags & ~RSET_LEV_MASK) | ((VALUE)lev << RSET_LEV_SHIFT));
}

static inline bool
set_iterating_p(VALUE set)
{
    return iter_lev_in_flags(set) > 0;
}

static void
set_iter_lev_inc(VALUE set)
{
    unsigned long lev = iter_lev_in_flags(set);
    if (lev == RSET_LEV_MAX) {
        lev = iter_lev_in_ivar(set) + 1;
        if (!POSFIXABLE(lev)) { /* paranoiac check */
            rb_raise(rb_eRuntimeError, "too much nested iterations");
        }
    }
    else {
        lev += 1;
        iter_lev_in_flags_set(set, lev);
        if (lev < RSET_LEV_MAX) return;
    }
    iter_lev_in_ivar_set(set, lev);
}

static void
set_iter_lev_dec(VALUE set)
{
    unsigned long lev = iter_lev_in_flags(set);
    if (lev == RSET_LEV_MAX) {
        lev = iter_lev_in_ivar(set);
        if (lev > RSET_LEV_MAX) {
            iter_lev_in_ivar_set(set, lev-1);
            return;
        }
        rb_attr_delete(set, id_set_iter_lev);
    }
    else if (lev == 0) {
        rb_raise(rb_eRuntimeError, "iteration level underflow");
    }
    iter_lev_in_flags_set(set, lev - 1);
}

static VALUE
set_foreach_ensure(VALUE set)
{
    set_iter_lev_dec(set);
    return 0;
}

typedef int set_foreach_func(VALUE, VALUE);

struct set_foreach_arg {
    VALUE set;
    set_foreach_func *func;
    VALUE arg;
};

static int
set_iter_status_check(int status)
{
    if (status == ST_CONTINUE) {
      return ST_CHECK;
    }

    return status;
}

static int
set_foreach_iter(st_data_t key, st_data_t argp, int error)
{
    struct set_foreach_arg *arg = (struct set_foreach_arg *)argp;

    if (error) return ST_STOP;

    set_table *tbl = RSET_TABLE(arg->set);
    int status = (*arg->func)((VALUE)key, arg->arg);

    if (RSET_TABLE(arg->set) != tbl) {
        rb_raise(rb_eRuntimeError, "reset occurred during iteration");
    }

    return set_iter_status_check(status);
}

static VALUE
set_foreach_call(VALUE arg)
{
    VALUE set = ((struct set_foreach_arg *)arg)->set;
    int ret = 0;
    ret = set_foreach_check(RSET_TABLE(set), set_foreach_iter,
                           (st_data_t)arg, (st_data_t)Qundef);
    if (ret) {
        rb_raise(rb_eRuntimeError, "ret: %d, set modified during iteration", ret);
    }
    return Qnil;
}

static void
set_iter(VALUE set, set_foreach_func *func, VALUE farg)
{
    struct set_foreach_arg arg;

    if (RSET_EMPTY(set))
        return;
    arg.set = set;
    arg.func = func;
    arg.arg  = farg;
    if (RB_OBJ_FROZEN(set)) {
        set_foreach_call((VALUE)&arg);
    }
    else {
        set_iter_lev_inc(set);
        rb_ensure(set_foreach_call, (VALUE)&arg, set_foreach_ensure, set);
    }
}

NORETURN(static void no_new_item(void));
static void
no_new_item(void)
{
    rb_raise(rb_eRuntimeError, "can't add a new item into set during iteration");
}

static void
set_compact_after_delete(VALUE set)
{
    if (!set_iterating_p(set)) {
        set_compact_table(RSET_TABLE(set));
    }
}

static int
set_table_insert_wb(set_table *tab, VALUE set, VALUE key, VALUE *key_addr)
{
    if (tab->type != &identhash && rb_obj_class(key) == rb_cString && !RB_OBJ_FROZEN(key)) {
        key = rb_hash_key_str(key);
        if (key_addr) *key_addr = key;
    }
    int ret = set_insert(tab, (st_data_t)key);
    if (ret == 0) RB_OBJ_WRITTEN(set, Qundef, key);
    return ret;
}

static int
set_insert_wb(VALUE set, VALUE key, VALUE *key_addr)
{
    return set_table_insert_wb(RSET_TABLE(set), set, key, key_addr);
}

static VALUE
set_alloc_with_size(VALUE klass, st_index_t size)
{
    VALUE set;
    struct set_object *sobj;

    set = TypedData_Make_Struct(klass, struct set_object, &set_data_type, sobj);
    set_init_table_with_size(&sobj->table, &objhash, size);

    return set;
}


static VALUE
set_s_alloc(VALUE klass)
{
    return set_alloc_with_size(klass, 0);
}

/*
 *  call-seq:
 *    Set[*objects] -> new_set
 *
 *  Returns a new Set object populated with the given objects,
 *  See Set::new.
 */
static VALUE
set_s_create(int argc, VALUE *argv, VALUE klass)
{
    VALUE set = set_alloc_with_size(klass, argc);
    set_table *table = RSET_TABLE(set);
    int i;

    for (i=0; i < argc; i++) {
        set_table_insert_wb(table, set, argv[i], NULL);
    }

    return set;
}

static void
check_set(VALUE arg)
{
    if (!rb_obj_is_kind_of(arg, rb_cSet)) {
        rb_raise(rb_eArgError, "value must be a set");
    }
}

static ID
enum_method_id(VALUE other)
{
    if (rb_respond_to(other, id_each_entry)) {
        return id_each_entry;
    }
    else if (rb_respond_to(other, id_each)) {
        return id_each;
    }
    else {
        rb_raise(rb_eArgError, "value must be enumerable");
    }
}

static VALUE
set_enum_size(VALUE set, VALUE args, VALUE eobj)
{
    return RSET_SIZE_NUM(set);
}

static VALUE
set_initialize_without_block(RB_BLOCK_CALL_FUNC_ARGLIST(i, set))
{
    VALUE element = i;
    set_insert_wb(set, element, &element);
    return element;
}

static VALUE
set_initialize_with_block(RB_BLOCK_CALL_FUNC_ARGLIST(i, set))
{
    VALUE element = rb_yield(i);
    set_insert_wb(set, element, &element);
    return element;
}

/*
 *  call-seq:
 *    Set.new -> new_set
 *    Set.new(enum) -> new_set
 *    Set.new(enum) { |elem| ... } -> new_set
 *
 *  Creates a new set containing the elements of the given enumerable
 *  object.
 *
 *  If a block is given, the elements of enum are preprocessed by the
 *  given block.
 *
 *    Set.new([1, 2])                       #=> #<Set: {1, 2}>
 *    Set.new([1, 2, 1])                    #=> #<Set: {1, 2}>
 *    Set.new([1, 'c', :s])                 #=> #<Set: {1, "c", :s}>
 *    Set.new(1..5)                         #=> #<Set: {1, 2, 3, 4, 5}>
 *    Set.new([1, 2, 3]) { |x| x * x }      #=> #<Set: {1, 4, 9}>
 */
static VALUE
set_i_initialize(int argc, VALUE *argv, VALUE set)
{
    if (RBASIC(set)->flags & RSET_INITIALIZED) {
        rb_raise(rb_eRuntimeError, "cannot reinitialize set");
    }
    RBASIC(set)->flags |= RSET_INITIALIZED;

    VALUE other;
    rb_check_arity(argc, 0, 1);

    if (argc > 0 && (other = argv[0]) != Qnil) {
        if (RB_TYPE_P(other, T_ARRAY)) {
            long i;
            int block_given = rb_block_given_p();
            set_table *into = RSET_TABLE(set);
            for (i=0; i<RARRAY_LEN(other); i++) {
                VALUE key = RARRAY_AREF(other, i);
                if (block_given) key = rb_yield(key);
                set_table_insert_wb(into, set, key, NULL);
            }
        }
        else {
            ID id_size = rb_intern("size");
            if (rb_obj_is_kind_of(other, rb_mEnumerable) && rb_respond_to(other, id_size)) {
                VALUE size = rb_funcall(other, id_size, 0);
                if (RB_TYPE_P(size, T_FLOAT) && RFLOAT_VALUE(size) == INFINITY) {
                    rb_raise(rb_eArgError, "cannot initialize Set from an object with infinite size");
                }
            }

            rb_block_call(other, enum_method_id(other), 0, 0,
                rb_block_given_p() ? set_initialize_with_block : set_initialize_without_block,
                set);
        }
    }

    return set;
}

/* :nodoc: */
static VALUE
set_i_initialize_copy(VALUE set, VALUE other)
{
    if (set == other) return set;

    if (set_iterating_p(set)) {
        rb_raise(rb_eRuntimeError, "cannot replace set during iteration");
    }

    struct set_object *sobj;
    TypedData_Get_Struct(set, struct set_object, &set_data_type, sobj);

    set_free_embedded(sobj);
    set_copy(&sobj->table, RSET_TABLE(other));
    rb_gc_writebarrier_remember(set);

    return set;
}

static int
set_inspect_i(st_data_t key, st_data_t arg)
{
    VALUE *args = (VALUE*)arg;
    VALUE str = args[0];
    if (args[1] == Qtrue) {
        rb_str_buf_cat_ascii(str, ", ");
    }
    else {
        args[1] = Qtrue;
    }
    rb_str_buf_append(str, rb_inspect((VALUE)key));

    return ST_CONTINUE;
}

static VALUE
set_inspect(VALUE set, VALUE dummy, int recur)
{
    VALUE str;
    VALUE klass_name = rb_class_path(CLASS_OF(set));

    if (recur) {
        str = rb_sprintf("%"PRIsVALUE"[...]", klass_name);
        return rb_str_export_to_enc(str, rb_usascii_encoding());
    }

    str = rb_sprintf("%"PRIsVALUE"[", klass_name);
    VALUE args[2] = {str, Qfalse};
    set_iter(set, set_inspect_i, (st_data_t)args);
    rb_str_buf_cat2(str, "]");

    return str;
}

/*
 *  call-seq:
 *    inspect -> new_string
 *
 *  Returns a new string containing the set entries:
 *
 *    s = Set.new
 *    s.inspect # => "#<Set: {}>"
 *    s.add(1)
 *    s.inspect # => "#<Set: {1}>"
 *    s.add(2)
 *    s.inspect # => "#<Set: {1, 2}>"
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Set@Methods+for+Converting].
 */
static VALUE
set_i_inspect(VALUE set)
{
    return rb_exec_recursive(set_inspect, set, 0);
}

static int
set_to_a_i(st_data_t key, st_data_t arg)
{
    rb_ary_push((VALUE)arg, (VALUE)key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    to_a -> array
 *
 *  Returns an array containing all elements in the set.
 *
 *    Set[1, 2].to_a                    #=> [1, 2]
 *    Set[1, 'c', :s].to_a              #=> [1, "c", :s]
 */
static VALUE
set_i_to_a(VALUE set)
{
    st_index_t size = RSET_SIZE(set);
    VALUE ary = rb_ary_new_capa(size);

    if (size == 0) return ary;

    if (ST_DATA_COMPATIBLE_P(VALUE)) {
        RARRAY_PTR_USE(ary, ptr, {
            size = set_keys(RSET_TABLE(set), ptr, size);
        });
        rb_gc_writebarrier_remember(ary);
        rb_ary_set_len(ary, size);
    }
    else {
        set_iter(set, set_to_a_i, (st_data_t)ary);
    }
    return ary;
}

/*
 *  call-seq:
 *    to_set(klass = Set, *args, &block) -> self or new_set
 *
 *  Returns self if receiver is an instance of +Set+ and no arguments or
 *  block are given.  Otherwise, converts the set to another with
 *  <tt>klass.new(self, *args, &block)</tt>.
 *
 *  In subclasses, returns `klass.new(self, *args, &block)` unless overridden.
 */
static VALUE
set_i_to_set(int argc, VALUE *argv, VALUE set)
{
    VALUE klass;

    if (argc == 0) {
        klass = rb_cSet;
        argv = &set;
        argc = 1;
    }
    else {
        rb_warn_deprecated("passing arguments to Set#to_set", NULL);
        klass = argv[0];
        argv[0] = set;
    }

    if (klass == rb_cSet && rb_obj_is_instance_of(set, rb_cSet) &&
            argc == 1 && !rb_block_given_p()) {
        return set;
    }

    return rb_funcall_passing_block(klass, id_new, argc, argv);
}

/*
 *  call-seq:
 *    join(separator=nil)-> new_string
 *
 *  Returns a string created by converting each element of the set to a string.
 */
static VALUE
set_i_join(int argc, VALUE *argv, VALUE set)
{
    rb_check_arity(argc, 0, 1);
    return rb_ary_join(set_i_to_a(set), argc == 0 ? Qnil : argv[0]);
}

/*
 *  call-seq:
 *    add(obj) -> self
 *
 *  Adds the given object to the set and returns self.  Use `merge` to
 *  add many elements at once.
 *
 *    Set[1, 2].add(3)                    #=> #<Set: {1, 2, 3}>
 *    Set[1, 2].add([3, 4])               #=> #<Set: {1, 2, [3, 4]}>
 *    Set[1, 2].add(2)                    #=> #<Set: {1, 2}>
 */
static VALUE
set_i_add(VALUE set, VALUE item)
{
    rb_check_frozen(set);
    if (set_iterating_p(set)) {
        if (!set_table_lookup(RSET_TABLE(set), (st_data_t)item)) {
            no_new_item();
        }
    }
    else {
        set_insert_wb(set, item, NULL);
    }
    return set;
}

/*
 *  call-seq:
 *    add?(obj) -> self or nil
 *
 *  Adds the given object to the set and returns self. If the object is
 *  already in the set, returns nil.
 *
 *    Set[1, 2].add?(3)                    #=> #<Set: {1, 2, 3}>
 *    Set[1, 2].add?([3, 4])               #=> #<Set: {1, 2, [3, 4]}>
 *    Set[1, 2].add?(2)                    #=> nil
 */
static VALUE
set_i_add_p(VALUE set, VALUE item)
{
    rb_check_frozen(set);
    if (set_iterating_p(set)) {
        if (!set_table_lookup(RSET_TABLE(set), (st_data_t)item)) {
            no_new_item();
        }
        return Qnil;
    }
    else {
        return set_insert_wb(set, item, NULL) ? Qnil : set;
    }
}

/*
 *  call-seq:
 *    delete(obj) -> self
 *
 *  Deletes the given object from the set and returns self. Use subtract
 *  to delete many items at once.
 */
static VALUE
set_i_delete(VALUE set, VALUE item)
{
    rb_check_frozen(set);
    if (set_table_delete(RSET_TABLE(set), (st_data_t *)&item)) {
        set_compact_after_delete(set);
    }
    return set;
}

/*
 *  call-seq:
 *    delete?(obj) -> self or nil
 *
 *  Deletes the given object from the set and returns self.  If the
 *  object is not in the set, returns nil.
 */
static VALUE
set_i_delete_p(VALUE set, VALUE item)
{
    rb_check_frozen(set);
    if (set_table_delete(RSET_TABLE(set), (st_data_t *)&item)) {
        set_compact_after_delete(set);
        return set;
    }
    return Qnil;
}

static int
set_delete_if_i(st_data_t key, st_data_t dummy)
{
    return RTEST(rb_yield((VALUE)key)) ? ST_DELETE : ST_CONTINUE;
}

/*
 *  call-seq:
 *    delete_if { |o| ... } -> self
 *    delete_if -> enumerator
 *
 *  Deletes every element of the set for which block evaluates to
 *  true, and returns self. Returns an enumerator if no block is given.
 */
static VALUE
set_i_delete_if(VALUE set)
{
    RETURN_SIZED_ENUMERATOR(set, 0, 0, set_enum_size);
    rb_check_frozen(set);
    set_iter(set, set_delete_if_i, 0);
    set_compact_after_delete(set);
    return set;
}

/*
 *  call-seq:
 *    reject! { |o| ... } -> self
 *    reject! -> enumerator
 *
 *  Equivalent to Set#delete_if, but returns nil if no changes were made.
 *  Returns an enumerator if no block is given.
 */
static VALUE
set_i_reject(VALUE set)
{
    RETURN_SIZED_ENUMERATOR(set, 0, 0, set_enum_size);
    rb_check_frozen(set);

    set_table *table = RSET_TABLE(set);
    size_t n = set_table_size(table);
    set_iter(set, set_delete_if_i, 0);

    if (n == set_table_size(table)) return Qnil;

    set_compact_after_delete(set);
    return set;
}

static int
set_classify_i(st_data_t key, st_data_t tmp)
{
    VALUE* args = (VALUE*)tmp;
    VALUE hash = args[0];
    VALUE hash_key = rb_yield(key);
    VALUE set = rb_hash_lookup2(hash, hash_key, Qundef);
    if (set == Qundef) {
        set = set_s_alloc(args[1]);
        rb_hash_aset(hash, hash_key, set);
    }
    set_i_add(set, key);

    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    classify { |o| ... } -> hash
 *    classify -> enumerator
 *
 *  Classifies the set by the return value of the given block and
 *  returns a hash of {value => set of elements} pairs.  The block is
 *  called once for each element of the set, passing the element as
 *  parameter.
 *
 *    files = Set.new(Dir.glob("*.rb"))
 *    hash = files.classify { |f| File.mtime(f).year }
 *    hash       #=> {2000 => #<Set: {"a.rb", "b.rb"}>,
 *               #    2001 => #<Set: {"c.rb", "d.rb", "e.rb"}>,
 *               #    2002 => #<Set: {"f.rb"}>}
 *
 *  Returns an enumerator if no block is given.
 */
static VALUE
set_i_classify(VALUE set)
{
    RETURN_SIZED_ENUMERATOR(set, 0, 0, set_enum_size);
    VALUE args[2];
    args[0] = rb_hash_new();
    args[1] = rb_obj_class(set);
    set_iter(set, set_classify_i, (st_data_t)args);
    return args[0];
}

// Union-find with path compression
static long
set_divide_union_find_root(long *uf_parents, long index, long *tmp_array)
{
    long root = uf_parents[index];
    long update_size = 0;
    while (root != index) {
        tmp_array[update_size++] = index;
        index = root;
        root = uf_parents[index];
    }
    for (long j = 0; j < update_size; j++) {
        long idx = tmp_array[j];
        uf_parents[idx] = root;
    }
    return root;
}

static void
set_divide_union_find_merge(long *uf_parents, long i, long j, long *tmp_array)
{
    long root_i = set_divide_union_find_root(uf_parents, i, tmp_array);
    long root_j = set_divide_union_find_root(uf_parents, j, tmp_array);
    if (root_i != root_j) uf_parents[root_j] = root_i;
}

static VALUE
set_divide_arity2(VALUE set)
{
    VALUE tmp, uf;
    long size, *uf_parents, *tmp_array;
    VALUE set_class = rb_obj_class(set);
    VALUE items = set_i_to_a(set);
    rb_ary_freeze(items);
    size = RARRAY_LEN(items);
    tmp_array = ALLOCV_N(long, tmp, size);
    uf_parents = ALLOCV_N(long, uf, size);
    for (long i = 0; i < size; i++) {
        uf_parents[i] = i;
    }
    for (long i = 0; i < size - 1; i++) {
        VALUE item1 = RARRAY_AREF(items, i);
        for (long j = i + 1; j < size; j++) {
            VALUE item2 = RARRAY_AREF(items, j);
            if (RTEST(rb_yield_values(2, item1, item2)) &&
                RTEST(rb_yield_values(2, item2, item1))) {
                set_divide_union_find_merge(uf_parents, i, j, tmp_array);
            }
        }
    }
    VALUE final_set = set_s_create(0, 0, rb_cSet);
    VALUE hash = rb_hash_new();
    for (long i = 0; i < size; i++) {
        VALUE v = RARRAY_AREF(items, i);
        long root = set_divide_union_find_root(uf_parents, i, tmp_array);
        VALUE set = rb_hash_aref(hash, LONG2FIX(root));
        if (set == Qnil) {
            set = set_s_create(0, 0, set_class);
            rb_hash_aset(hash, LONG2FIX(root), set);
            set_i_add(final_set, set);
        }
        set_i_add(set, v);
    }
    ALLOCV_END(tmp);
    ALLOCV_END(uf);
    return final_set;
}

static void set_merge_enum_into(VALUE set, VALUE arg);

/*
 *  call-seq:
 *    divide { |o1, o2| ... } -> set
 *    divide { |o| ... } -> set
 *    divide -> enumerator
 *
 *  Divides the set into a set of subsets according to the commonality
 *  defined by the given block.
 *
 *  If the arity of the block is 2, elements o1 and o2 are in common
 *  if both block.call(o1, o2) and block.call(o2, o1) are true.
 *  Otherwise, elements o1 and o2 are in common if
 *  block.call(o1) == block.call(o2).
 *
 *    numbers = Set[1, 3, 4, 6, 9, 10, 11]
 *    set = numbers.divide { |i,j| (i - j).abs == 1 }
 *    set        #=> #<Set: {#<Set: {1}>,
 *               #           #<Set: {3, 4}>,
 *               #           #<Set: {6}>}>
 *               #           #<Set: {9, 10, 11}>,
 *
 *  Returns an enumerator if no block is given.
 */
static VALUE
set_i_divide(VALUE set)
{
    RETURN_SIZED_ENUMERATOR(set, 0, 0, set_enum_size);

    if (rb_block_arity() == 2) {
        return set_divide_arity2(set);
    }

    VALUE values = rb_hash_values(set_i_classify(set));
    set = set_alloc_with_size(rb_cSet, RARRAY_LEN(values));
    set_merge_enum_into(set, values);
    return set;
}

static int
set_clear_i(st_data_t key, st_data_t dummy)
{
    return ST_DELETE;
}

/*
 *  call-seq:
 *    clear -> self
 *
 *  Removes all elements and returns self.
 *
 *    set = Set[1, 'c', :s]             #=> #<Set: {1, "c", :s}>
 *    set.clear                         #=> #<Set: {}>
 *    set                               #=> #<Set: {}>
 */
static VALUE
set_i_clear(VALUE set)
{
    rb_check_frozen(set);
    if (RSET_SIZE(set) == 0) return set;
    if (set_iterating_p(set)) {
        set_iter(set, set_clear_i, 0);
    }
    else {
        set_table_clear(RSET_TABLE(set));
        set_compact_after_delete(set);
    }
    return set;
}

struct set_intersection_data {
    VALUE set;
    set_table *into;
    set_table *other;
};

static int
set_intersection_i(st_data_t key, st_data_t tmp)
{
    struct set_intersection_data *data = (struct set_intersection_data *)tmp;
    if (set_table_lookup(data->other, key)) {
        set_table_insert_wb(data->into, data->set, key, NULL);
    }

    return ST_CONTINUE;
}

static VALUE
set_intersection_block(RB_BLOCK_CALL_FUNC_ARGLIST(i, data))
{
    set_intersection_i((st_data_t)i, (st_data_t)data);
    return i;
}

/*
 *  call-seq:
 *    set & enum -> new_set
 *
 *  Returns a new set containing elements common to the set and the given
 *  enumerable object.
 *
 *    Set[1, 3, 5] & Set[3, 2, 1]             #=> #<Set: {3, 1}>
 *    Set['a', 'b', 'z'] & ['a', 'b', 'c']    #=> #<Set: {"a", "b"}>
 */
static VALUE
set_i_intersection(VALUE set, VALUE other)
{
    VALUE new_set = set_s_alloc(rb_obj_class(set));
    set_table *stable = RSET_TABLE(set);
    set_table *ntable = RSET_TABLE(new_set);

    if (rb_obj_is_kind_of(other, rb_cSet)) {
        set_table *otable = RSET_TABLE(other);
        if (set_table_size(stable) >= set_table_size(otable)) {
            /* Swap so we iterate over the smaller set */
            otable = stable;
            set = other;
        }

        struct set_intersection_data data = {
            .set = new_set,
            .into = ntable,
            .other = otable
        };
        set_iter(set, set_intersection_i, (st_data_t)&data);
    }
    else {
        struct set_intersection_data data = {
            .set = new_set,
            .into = ntable,
            .other = stable
        };
        rb_block_call(other, enum_method_id(other), 0, 0, set_intersection_block, (VALUE)&data);
    }

    return new_set;
}

/*
 *  call-seq:
 *    include?(item) -> true or false
 *
 *  Returns true if the set contains the given object:
 *
 *    Set[1, 2, 3].include? 2   #=> true
 *    Set[1, 2, 3].include? 4   #=> false
 *
 *  Note that <code>include?</code> and <code>member?</code> do not test member
 *  equality using <code>==</code> as do other Enumerables.
 *
 *  This is aliased to #===, so it is usable in +case+ expressions:
 *
 *    case :apple
 *    when Set[:potato, :carrot]
 *      "vegetable"
 *    when Set[:apple, :banana]
 *      "fruit"
 *    end
 *    # => "fruit"
 *
 *  See also Enumerable#include?
 */
static VALUE
set_i_include(VALUE set, VALUE item)
{
    return RBOOL(RSET_IS_MEMBER(set, item));
}

struct set_merge_args {
  VALUE set;
  set_table *into;
};

static int
set_merge_i(st_data_t key, st_data_t data)
{
    struct set_merge_args *args = (struct set_merge_args *)data;
    set_table_insert_wb(args->into, args->set, key, NULL);
    return ST_CONTINUE;
}

static VALUE
set_merge_block(RB_BLOCK_CALL_FUNC_ARGLIST(key, set))
{
    VALUE element = key;
    set_insert_wb(set, element, &element);
    return element;
}

static void
set_merge_enum_into(VALUE set, VALUE arg)
{
    if (rb_obj_is_kind_of(arg, rb_cSet)) {
        struct set_merge_args args = {
            .set = set,
            .into = RSET_TABLE(set)
        };
        set_iter(arg, set_merge_i, (st_data_t)&args);
    }
    else if (RB_TYPE_P(arg, T_ARRAY)) {
        long i;
        set_table *into = RSET_TABLE(set);
        for (i=0; i<RARRAY_LEN(arg); i++) {
            set_table_insert_wb(into, set, RARRAY_AREF(arg, i), NULL);
        }
    }
    else {
        rb_block_call(arg, enum_method_id(arg), 0, 0, set_merge_block, (VALUE)set);
    }
}

/*
 *  call-seq:
 *    merge(*enums, **nil) -> self
 *
 *  Merges the elements of the given enumerable objects to the set and
 *  returns self.
 */
static VALUE
set_i_merge(int argc, VALUE *argv, VALUE set)
{
    if (rb_keyword_given_p()) {
        rb_raise(rb_eArgError, "no keywords accepted");
    }

    if (set_iterating_p(set)) {
        rb_raise(rb_eRuntimeError, "cannot add to set during iteration");
    }

    rb_check_frozen(set);

    int i;

    for (i=0; i < argc; i++) {
        set_merge_enum_into(set, argv[i]);
    }

    return set;
}

static VALUE
set_reset_table_with_type(VALUE set, const struct st_hash_type *type)
{
    rb_check_frozen(set);

    struct set_object *sobj;
    TypedData_Get_Struct(set, struct set_object, &set_data_type, sobj);
    set_table *old = &sobj->table;

    size_t size = set_table_size(old);
    if (size > 0) {
        set_table *new = set_init_table_with_size(NULL, type, size);
        struct set_merge_args args = {
            .set = set,
            .into = new
        };
        set_iter(set, set_merge_i, (st_data_t)&args);
        set_free_embedded(sobj);
        memcpy(&sobj->table, new, sizeof(*new));
        free(new);
    }
    else {
        sobj->table.type = type;
    }

    return set;
}

/*
 *  call-seq:
 *    compare_by_identity -> self
 *
 *  Makes the set compare its elements by their identity and returns self.
 */
static VALUE
set_i_compare_by_identity(VALUE set)
{
    if (RSET_COMPARE_BY_IDENTITY(set)) return set;

    if (set_iterating_p(set)) {
        rb_raise(rb_eRuntimeError, "compare_by_identity during iteration");
    }

    return set_reset_table_with_type(set, &identhash);
}

/*
 *  call-seq:
 *    compare_by_identity? -> true or false
 *
 *  Returns true if the set will compare its elements by their
 *  identity.  Also see Set#compare_by_identity.
 */
static VALUE
set_i_compare_by_identity_p(VALUE set)
{
    return RBOOL(RSET_COMPARE_BY_IDENTITY(set));
}

/*
 *  call-seq:
 *    size -> integer
 *
 *  Returns the number of elements.
 */
static VALUE
set_i_size(VALUE set)
{
    return RSET_SIZE_NUM(set);
}

/*
 *  call-seq:
 *    empty? -> true or false
 *
 *  Returns true if the set contains no elements.
 */
static VALUE
set_i_empty(VALUE set)
{
    return RBOOL(RSET_EMPTY(set));
}

static int
set_xor_i(st_data_t key, st_data_t data)
{
    VALUE element = (VALUE)key;
    VALUE set = (VALUE)data;
    set_table *table = RSET_TABLE(set);
    if (set_table_insert_wb(table, set, element, &element)) {
        set_table_delete(table, &element);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    set ^ enum -> new_set
 *
 *  Returns a new set containing elements exclusive between the set and the
 *  given enumerable object.  <tt>(set ^ enum)</tt> is equivalent to
 *  <tt>((set | enum) - (set & enum))</tt>.
 *
 *    Set[1, 2] ^ Set[2, 3]                   #=> #<Set: {3, 1}>
 *    Set[1, 'b', 'c'] ^ ['b', 'd']           #=> #<Set: {"d", 1, "c"}>
 */
static VALUE
set_i_xor(VALUE set, VALUE other)
{
    VALUE new_set;
    if (rb_obj_is_kind_of(other, rb_cSet)) {
        new_set = other;
    }
    else {
        new_set = set_s_alloc(rb_obj_class(set));
        set_merge_enum_into(new_set, other);
    }
    set_iter(set, set_xor_i, (st_data_t)new_set);
    return new_set;
}

/*
 *  call-seq:
 *    set | enum -> new_set
 *
 *  Returns a new set built by merging the set and the elements of the
 *  given enumerable object.
 *
 *    Set[1, 2, 3] | Set[2, 4, 5]         #=> #<Set: {1, 2, 3, 4, 5}>
 *    Set[1, 5, 'z'] | (1..6)             #=> #<Set: {1, 5, "z", 2, 3, 4, 6}>
 */
static VALUE
set_i_union(VALUE set, VALUE other)
{
    set = rb_obj_dup(set);
    set_merge_enum_into(set, other);
    return set;
}

static int
set_remove_i(st_data_t key, st_data_t from)
{
    set_table_delete((struct set_table *)from, (st_data_t *)&key);
    return ST_CONTINUE;
}

static VALUE
set_remove_block(RB_BLOCK_CALL_FUNC_ARGLIST(key, set))
{
    rb_check_frozen(set);
    set_table_delete(RSET_TABLE(set), (st_data_t *)&key);
    return key;
}

static void
set_remove_enum_from(VALUE set, VALUE arg)
{
    if (rb_obj_is_kind_of(arg, rb_cSet)) {
        set_iter(arg, set_remove_i, (st_data_t)RSET_TABLE(set));
    }
    else {
        rb_block_call(arg, enum_method_id(arg), 0, 0, set_remove_block, (VALUE)set);
    }
}

/*
 *  call-seq:
 *    subtract(enum) -> self
 *
 *  Deletes every element that appears in the given enumerable object
 *  and returns self.
 */
static VALUE
set_i_subtract(VALUE set, VALUE other)
{
    rb_check_frozen(set);
    set_remove_enum_from(set, other);
    return set;
}

/*
 *  call-seq:
 *    set - enum -> new_set
 *
 *  Returns a new set built by duplicating the set, removing every
 *  element that appears in the given enumerable object.
 *
 *    Set[1, 3, 5] - Set[1, 5]                #=> #<Set: {3}>
 *    Set['a', 'b', 'z'] - ['a', 'c']         #=> #<Set: {"b", "z"}>
 */
static VALUE
set_i_difference(VALUE set, VALUE other)
{
    return set_i_subtract(rb_obj_dup(set), other);
}

static int
set_each_i(st_data_t key, st_data_t dummy)
{
    rb_yield(key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    each { |o| ... } -> self
 *    each -> enumerator
 *
 *  Calls the given block once for each element in the set, passing
 *  the element as parameter.  Returns an enumerator if no block is
 *  given.
 */
static VALUE
set_i_each(VALUE set)
{
    RETURN_SIZED_ENUMERATOR(set, 0, 0, set_enum_size);
    set_iter(set, set_each_i, 0);
    return set;
}

static int
set_collect_i(st_data_t key, st_data_t data)
{
    set_insert_wb((VALUE)data, rb_yield((VALUE)key), NULL);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    collect! { |o| ... } -> self
 *    collect! -> enumerator
 *
 *  Replaces the elements with ones returned by +collect+.
 *  Returns an enumerator if no block is given.
 */
static VALUE
set_i_collect(VALUE set)
{
    RETURN_SIZED_ENUMERATOR(set, 0, 0, set_enum_size);
    rb_check_frozen(set);

    VALUE new_set = set_s_alloc(rb_obj_class(set));
    set_iter(set, set_collect_i, (st_data_t)new_set);
    set_i_initialize_copy(set, new_set);

    return set;
}

static int
set_keep_if_i(st_data_t key, st_data_t into)
{
    if (!RTEST(rb_yield((VALUE)key))) {
        set_table_delete((set_table *)into, &key);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    keep_if { |o| ... } -> self
 *    keep_if -> enumerator
 *
 *  Deletes every element of the set for which block evaluates to false, and
 *  returns self. Returns an enumerator if no block is given.
 */
static VALUE
set_i_keep_if(VALUE set)
{
    RETURN_SIZED_ENUMERATOR(set, 0, 0, set_enum_size);
    rb_check_frozen(set);

    set_iter(set, set_keep_if_i, (st_data_t)RSET_TABLE(set));

    return set;
}

/*
 *  call-seq:
 *    select! { |o| ... } -> self
 *    select! -> enumerator
 *
 *  Equivalent to Set#keep_if, but returns nil if no changes were made.
 *  Returns an enumerator if no block is given.
 */
static VALUE
set_i_select(VALUE set)
{
    RETURN_SIZED_ENUMERATOR(set, 0, 0, set_enum_size);
    rb_check_frozen(set);

    set_table *table = RSET_TABLE(set);
    size_t n = set_table_size(table);
    set_iter(set, set_keep_if_i, (st_data_t)table);

    return (n == set_table_size(table)) ? Qnil : set;
}

/*
 *  call-seq:
 *    replace(enum) -> self
 *
 *  Replaces the contents of the set with the contents of the given
 *  enumerable object and returns self.
 *
 *    set = Set[1, 'c', :s]             #=> #<Set: {1, "c", :s}>
 *    set.replace([1, 2])               #=> #<Set: {1, 2}>
 *    set                               #=> #<Set: {1, 2}>
 */
static VALUE
set_i_replace(VALUE set, VALUE other)
{
    rb_check_frozen(set);

    if (rb_obj_is_kind_of(other, rb_cSet)) {
        set_i_initialize_copy(set, other);
    }
    else {
        if (set_iterating_p(set)) {
            rb_raise(rb_eRuntimeError, "cannot replace set during iteration");
        }

        // make sure enum is enumerable before calling clear
        enum_method_id(other);

        set_table_clear(RSET_TABLE(set));
        set_merge_enum_into(set, other);
    }

    return set;
}

/*
 *  call-seq:
 *    reset -> self
 *
 *  Resets the internal state after modification to existing elements
 *  and returns self. Elements will be reindexed and deduplicated.
 */
static VALUE
set_i_reset(VALUE set)
{
    if (set_iterating_p(set)) {
        rb_raise(rb_eRuntimeError, "reset during iteration");
    }

    return set_reset_table_with_type(set, RSET_TABLE(set)->type);
}

static void set_flatten_merge(VALUE set, VALUE from, VALUE seen);

static int
set_flatten_merge_i(st_data_t item, st_data_t arg)
{
    VALUE *args = (VALUE *)arg;
    VALUE set = args[0];
    if (rb_obj_is_kind_of(item, rb_cSet)) {
        VALUE e_id = rb_obj_id(item);
        VALUE hash = args[2];
        switch(rb_hash_aref(hash, e_id)) {
          case Qfalse:
           return ST_CONTINUE;
          case Qtrue:
            rb_raise(rb_eArgError, "tried to flatten recursive Set");
          default:
            break;
        }

        rb_hash_aset(hash, e_id, Qtrue);
        set_flatten_merge(set, item, hash);
        rb_hash_aset(hash, e_id, Qfalse);
    }
    else {
        set_i_add(set, item);
    }
    return ST_CONTINUE;
}

static void
set_flatten_merge(VALUE set, VALUE from, VALUE hash)
{
    VALUE args[3] = {set, from, hash};
    set_iter(from, set_flatten_merge_i, (st_data_t)args);
}

/*
 *  call-seq:
 *    flatten -> set
 *
 *  Returns a new set that is a copy of the set, flattening each
 *  containing set recursively.
 */
static VALUE
set_i_flatten(VALUE set)
{
    VALUE new_set = set_s_alloc(rb_obj_class(set));
    set_flatten_merge(new_set, set, rb_hash_new());
    return new_set;
}

static int
set_contains_set_i(st_data_t item, st_data_t arg)
{
    if (rb_obj_is_kind_of(item, rb_cSet)) {
        *(bool *)arg = true;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    flatten! -> self
 *
 *  Equivalent to Set#flatten, but replaces the receiver with the
 *  result in place.  Returns nil if no modifications were made.
 */
static VALUE
set_i_flatten_bang(VALUE set)
{
    bool contains_set = false;
    set_iter(set, set_contains_set_i, (st_data_t)&contains_set);
    if (!contains_set) return Qnil;
    rb_check_frozen(set);
    return set_i_replace(set, set_i_flatten(set));
}

struct set_subset_data {
    set_table *table;
    VALUE result;
};

static int
set_le_i(st_data_t key, st_data_t arg)
{
    struct set_subset_data *data = (struct set_subset_data *)arg;
    if (set_table_lookup(data->table, key)) return ST_CONTINUE;
    data->result = Qfalse;
    return ST_STOP;
}

static VALUE
set_le(VALUE set, VALUE other)
{
    struct set_subset_data data = {
        .table = RSET_TABLE(other),
        .result = Qtrue
    };
    set_iter(set, set_le_i, (st_data_t)&data);
    return data.result;
}

/*
 *  call-seq:
 *    proper_subset?(set) -> true or false
 *
 *  Returns true if the set is a proper subset of the given set.
 */
static VALUE
set_i_proper_subset(VALUE set, VALUE other)
{
    check_set(other);
    if (RSET_SIZE(set) >= RSET_SIZE(other)) return Qfalse;
    return set_le(set, other);
}

/*
 *  call-seq:
 *    subset?(set) -> true or false
 *
 *  Returns true if the set is a subset of the given set.
 */
static VALUE
set_i_subset(VALUE set, VALUE other)
{
    check_set(other);
    if (RSET_SIZE(set) > RSET_SIZE(other)) return Qfalse;
    return set_le(set, other);
}

/*
 *  call-seq:
 *    proper_superset?(set) -> true or false
 *
 *  Returns true if the set is a proper superset of the given set.
 */
static VALUE
set_i_proper_superset(VALUE set, VALUE other)
{
    check_set(other);
    if (RSET_SIZE(set) <= RSET_SIZE(other)) return Qfalse;
    return set_le(other, set);
}

/*
 *  call-seq:
 *    superset?(set) -> true or false
 *
 *  Returns true if the set is a superset of the given set.
 */
static VALUE
set_i_superset(VALUE set, VALUE other)
{
    check_set(other);
    if (RSET_SIZE(set) < RSET_SIZE(other)) return Qfalse;
    return set_le(other, set);
}

static int
set_intersect_i(st_data_t key, st_data_t arg)
{
    VALUE *args = (VALUE *)arg;
    if (set_table_lookup((set_table *)args[0], key)) {
        args[1] = Qtrue;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    intersect?(set) -> true or false
 *
 *  Returns true if the set and the given enumerable have at least one
 *  element in common.
 *
 *    Set[1, 2, 3].intersect? Set[4, 5]   #=> false
 *    Set[1, 2, 3].intersect? Set[3, 4]   #=> true
 *    Set[1, 2, 3].intersect? 4..5        #=> false
 *    Set[1, 2, 3].intersect? [3, 4]      #=> true
 */
static VALUE
set_i_intersect(VALUE set, VALUE other)
{
    if (rb_obj_is_kind_of(other, rb_cSet)) {
        size_t set_size = RSET_SIZE(set);
        size_t other_size = RSET_SIZE(other);
        VALUE args[2];
        args[1] = Qfalse;
        VALUE iter_arg;

        if (set_size < other_size) {
            iter_arg = set;
            args[0] = (VALUE)RSET_TABLE(other);
        }
        else {
            iter_arg = other;
            args[0] = (VALUE)RSET_TABLE(set);
        }
        set_iter(iter_arg, set_intersect_i, (st_data_t)args);
        return args[1];
    }
    else if (rb_obj_is_kind_of(other, rb_mEnumerable)) {
        return rb_funcall(other, id_any_p, 1, set);
    }
    else {
        rb_raise(rb_eArgError, "value must be enumerable");
    }
}

/*
 *  call-seq:
 *    disjoint?(set) -> true or false
 *
 *  Returns true if the set and the given enumerable have no
 *  element in common.  This method is the opposite of +intersect?+.
 *
 *    Set[1, 2, 3].disjoint? Set[3, 4]   #=> false
 *    Set[1, 2, 3].disjoint? Set[4, 5]   #=> true
 *    Set[1, 2, 3].disjoint? [3, 4]      #=> false
 *    Set[1, 2, 3].disjoint? 4..5        #=> true
 */
static VALUE
set_i_disjoint(VALUE set, VALUE other)
{
    return RBOOL(!RTEST(set_i_intersect(set, other)));
}

/*
 *  call-seq:
 *    set <=> other -> -1, 0, 1, or nil
 *
 *  Returns 0 if the set are equal, -1 / 1 if the set is a
 *  proper subset / superset of the given set, or or nil if
 *  they both have unique elements.
 */
static VALUE
set_i_compare(VALUE set, VALUE other)
{
    if (rb_obj_is_kind_of(other, rb_cSet)) {
        size_t set_size = RSET_SIZE(set);
        size_t other_size = RSET_SIZE(other);

        if (set_size < other_size) {
            if (set_le(set, other) == Qtrue) {
                return INT2NUM(-1);
            }
        }
        else if (set_size > other_size) {
            if (set_le(other, set) == Qtrue) {
                return INT2NUM(1);
            }
        }
        else if (set_le(set, other) == Qtrue) {
            return INT2NUM(0);
        }
    }

    return Qnil;
}

struct set_equal_data {
    VALUE result;
    VALUE set;
};

static int
set_eql_i(st_data_t item, st_data_t arg)
{
    struct set_equal_data *data = (struct set_equal_data *)arg;

    if (!set_table_lookup(RSET_TABLE(data->set), item)) {
        data->result = Qfalse;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

static VALUE
set_recursive_eql(VALUE set, VALUE dt, int recur)
{
    if (recur) return Qtrue;
    struct set_equal_data *data = (struct set_equal_data*)dt;
    data->result = Qtrue;
    set_iter(set, set_eql_i, dt);
    return data->result;
}

/*
 *  call-seq:
 *    set == other -> true or false
 *
 *  Returns true if two sets are equal.
 */
static VALUE
set_i_eq(VALUE set, VALUE other)
{
    if (!rb_obj_is_kind_of(other, rb_cSet)) return Qfalse;
    if (set == other) return Qtrue;

    set_table *stable = RSET_TABLE(set);
    set_table *otable = RSET_TABLE(other);
    size_t ssize = set_table_size(stable);
    size_t osize = set_table_size(otable);

    if (ssize != osize) return Qfalse;
    if (ssize == 0 && osize == 0) return Qtrue;
    if (stable->type != otable->type) return Qfalse;

    struct set_equal_data data;
    data.set = other;
    return rb_exec_recursive_paired(set_recursive_eql, set, other, (VALUE)&data);
}

static int
set_hash_i(st_data_t item, st_data_t(arg))
{
    st_index_t *hval = (st_index_t *)arg;
    st_index_t ival = rb_hash(item);
    *hval ^= rb_st_hash(&ival, sizeof(st_index_t), 0);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash -> integer
 *
 *  Returns hash code for set.
 */
static VALUE
set_i_hash(VALUE set)
{
    st_index_t size = RSET_SIZE(set);
    st_index_t hval = rb_st_hash_start(size);
    hval = rb_hash_uint(hval, (st_index_t)set_i_hash);
    if (size) {
        set_iter(set, set_hash_i, (VALUE)&hval);
    }
    hval = rb_st_hash_end(hval);
    return ST2FIX(hval);
}

/* :nodoc: */
static int
set_to_hash_i(st_data_t key, st_data_t arg)
{
    rb_hash_aset((VALUE)arg, (VALUE)key, Qtrue);
    return ST_CONTINUE;
}

static VALUE
set_i_to_h(VALUE set)
{
    st_index_t size = RSET_SIZE(set);
    VALUE hash;
    if (RSET_COMPARE_BY_IDENTITY(set)) {
        hash = rb_ident_hash_new_with_size(size);
    }
    else {
        hash = rb_hash_new_with_size(size);
    }
    rb_hash_set_default(hash, Qfalse);

    if (size == 0) return hash;

    set_iter(set, set_to_hash_i, (st_data_t)hash);
    return hash;
}

static VALUE
compat_dumper(VALUE set)
{
    VALUE dumper = rb_class_new_instance(0, 0, rb_cObject);
    rb_ivar_set(dumper, id_i_hash, set_i_to_h(set));
    return dumper;
}

static int
set_i_from_hash_i(st_data_t key, st_data_t val, st_data_t set)
{
    if ((VALUE)val != Qtrue) {
        rb_raise(rb_eRuntimeError, "expect true as Set value: %"PRIsVALUE, rb_obj_class((VALUE)val));
    }
    set_i_add((VALUE)set, (VALUE)key);
    return ST_CONTINUE;
}

static VALUE
set_i_from_hash(VALUE set, VALUE hash)
{
    Check_Type(hash, T_HASH);
    if (rb_hash_compare_by_id_p(hash)) set_i_compare_by_identity(set);
    rb_hash_stlike_foreach(hash, set_i_from_hash_i, (st_data_t)set);
    return set;
}

static VALUE
compat_loader(VALUE self, VALUE a)
{
    return set_i_from_hash(self, rb_ivar_get(a, id_i_hash));
}

/* C-API functions */

void
rb_set_foreach(VALUE set, int (*func)(VALUE element, VALUE arg), VALUE arg)
{
    set_iter(set, func, arg);
}

VALUE
rb_set_new(void)
{
    return set_alloc_with_size(rb_cSet, 0);
}

VALUE
rb_set_new_capa(size_t capa)
{
    return set_alloc_with_size(rb_cSet, (st_index_t)capa);
}

bool
rb_set_lookup(VALUE set, VALUE element)
{
    return RSET_IS_MEMBER(set, element);
}

bool
rb_set_add(VALUE set, VALUE element)
{
    return set_i_add_p(set, element) != Qnil;
}

VALUE
rb_set_clear(VALUE set)
{
    return set_i_clear(set);
}

bool
rb_set_delete(VALUE set, VALUE element)
{
    return set_i_delete_p(set, element) != Qnil;
}

size_t
rb_set_size(VALUE set)
{
    return RSET_SIZE(set);
}

/*
 *  Document-class: Set
 *
 * Copyright (c) 2002-2024 Akinori MUSHA <knu@iDaemons.org>
 *
 * Documentation by Akinori MUSHA and Gavin Sinclair.
 *
 * All rights reserved.  You can redistribute and/or modify it under the same
 * terms as Ruby.
 *
 * The Set class implements a collection of unordered values with no
 * duplicates. It is a hybrid of Array's intuitive inter-operation
 * facilities and Hash's fast lookup.
 *
 * Set is easy to use with Enumerable objects (implementing `each`).
 * Most of the initializer methods and binary operators accept generic
 * Enumerable objects besides sets and arrays.  An Enumerable object
 * can be converted to Set using the `to_set` method.
 *
 * Set uses a data structure similar to Hash for storage, except that
 * it only has keys and no values.
 *
 * * Equality of elements is determined according to Object#eql? and
 *   Object#hash.  Use Set#compare_by_identity to make a set compare
 *   its elements by their identity.
 * * Set assumes that the identity of each element does not change
 *   while it is stored.  Modifying an element of a set will render the
 *   set to an unreliable state.
 * * When a string is to be stored, a frozen copy of the string is
 *   stored instead unless the original string is already frozen.
 *
 * == Comparison
 *
 * The comparison operators <tt><</tt>, <tt>></tt>, <tt><=</tt>, and
 * <tt>>=</tt> are implemented as shorthand for the
 * {proper_,}{subset?,superset?} methods.  The <tt><=></tt>
 * operator reflects this order, or returns +nil+ for sets that both
 * have distinct elements (<tt>{x, y}</tt> vs. <tt>{x, z}</tt> for example).
 *
 * == Example
 *
 *   s1 = Set[1, 2]                        #=> #<Set: {1, 2}>
 *   s2 = [1, 2].to_set                    #=> #<Set: {1, 2}>
 *   s1 == s2                              #=> true
 *   s1.add("foo")                         #=> #<Set: {1, 2, "foo"}>
 *   s1.merge([2, 6])                      #=> #<Set: {1, 2, "foo", 6}>
 *   s1.subset?(s2)                        #=> false
 *   s2.subset?(s1)                        #=> true
 *
 * == Contact
 *
 * - Akinori MUSHA <knu@iDaemons.org> (current maintainer)
 *
 * == What's Here
 *
 *  First, what's elsewhere. \Class \Set:
 *
 * - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
 * - Includes {module Enumerable}[rdoc-ref:Enumerable@What-27s+Here],
 *   which provides dozens of additional methods.
 *
 * In particular, class \Set does not have many methods of its own
 * for fetching or for iterating.
 * Instead, it relies on those in \Enumerable.
 *
 * Here, class \Set provides methods that are useful for:
 *
 * - {Creating an Array}[rdoc-ref:Array@Methods+for+Creating+an+Array]
 * - {Creating a Set}[rdoc-ref:Array@Methods+for+Creating+a+Set]
 * - {Set Operations}[rdoc-ref:Array@Methods+for+Set+Operations]
 * - {Comparing}[rdoc-ref:Array@Methods+for+Comparing]
 * - {Querying}[rdoc-ref:Array@Methods+for+Querying]
 * - {Assigning}[rdoc-ref:Array@Methods+for+Assigning]
 * - {Deleting}[rdoc-ref:Array@Methods+for+Deleting]
 * - {Converting}[rdoc-ref:Array@Methods+for+Converting]
 * - {Iterating}[rdoc-ref:Array@Methods+for+Iterating]
 * - {And more....}[rdoc-ref:Array@Other+Methods]
 *
 * === Methods for Creating a \Set
 *
 * - ::[]:
 *   Returns a new set containing the given objects.
 * - ::new:
 *   Returns a new set containing either the given objects
 *   (if no block given) or the return values from the called block
 *   (if a block given).
 *
 * === Methods for \Set Operations
 *
 * - #| (aliased as #union and #+):
 *   Returns a new set containing all elements from +self+
 *   and all elements from a given enumerable (no duplicates).
 * - #& (aliased as #intersection):
 *   Returns a new set containing all elements common to +self+
 *   and a given enumerable.
 * - #- (aliased as #difference):
 *   Returns a copy of +self+ with all elements
 *   in a given enumerable removed.
 * - #^: Returns a new set containing all elements from +self+
 *   and a given enumerable except those common to both.
 *
 * === Methods for Comparing
 *
 * - #<=>: Returns -1, 0, or 1 as +self+ is less than, equal to,
 *   or greater than a given object.
 * - #==: Returns whether +self+ and a given enumerable are equal,
 *   as determined by Object#eql?.
 * - #compare_by_identity?:
 *   Returns whether the set considers only identity
 *   when comparing elements.
 *
 * === Methods for Querying
 *
 * - #length (aliased as #size):
 *   Returns the count of elements.
 * - #empty?:
 *   Returns whether the set has no elements.
 * - #include? (aliased as #member? and #===):
 *   Returns whether a given object is an element in the set.
 * - #subset? (aliased as #<=):
 *   Returns whether a given object is a subset of the set.
 * - #proper_subset? (aliased as #<):
 *   Returns whether a given enumerable is a proper subset of the set.
 * - #superset? (aliased as #>=):
 *   Returns whether a given enumerable is a superset of the set.
 * - #proper_superset? (aliased as #>):
 *   Returns whether a given enumerable is a proper superset of the set.
 * - #disjoint?:
 *   Returns +true+ if the set and a given enumerable
 *   have no common elements, +false+ otherwise.
 * - #intersect?:
 *   Returns +true+ if the set and a given enumerable:
 *   have any common elements, +false+ otherwise.
 * - #compare_by_identity?:
 *   Returns whether the set considers only identity
 *   when comparing elements.
 *
 * === Methods for Assigning
 *
 * - #add (aliased as #<<):
 *   Adds a given object to the set; returns +self+.
 * - #add?:
 *   If the given object is not an element in the set,
 *   adds it and returns +self+; otherwise, returns +nil+.
 * - #merge:
 *   Merges the elements of each given enumerable object to the set; returns +self+.
 * - #replace:
 *   Replaces the contents of the set with the contents
 *   of a given enumerable.
 *
 * === Methods for Deleting
 *
 * - #clear:
 *   Removes all elements in the set; returns +self+.
 * - #delete:
 *   Removes a given object from the set; returns +self+.
 * - #delete?:
 *   If the given object is an element in the set,
 *   removes it and returns +self+; otherwise, returns +nil+.
 * - #subtract:
 *   Removes each given object from the set; returns +self+.
 * - #delete_if - Removes elements specified by a given block.
 * - #select! (aliased as #filter!):
 *   Removes elements not specified by a given block.
 * - #keep_if:
 *   Removes elements not specified by a given block.
 * - #reject!
 *   Removes elements specified by a given block.
 *
 * === Methods for Converting
 *
 * - #classify:
 *   Returns a hash that classifies the elements,
 *   as determined by the given block.
 * - #collect! (aliased as #map!):
 *   Replaces each element with a block return-value.
 * - #divide:
 *   Returns a hash that classifies the elements,
 *   as determined by the given block;
 *   differs from #classify in that the block may accept
 *   either one or two arguments.
 * - #flatten:
 *   Returns a new set that is a recursive flattening of +self+.
 * - #flatten!:
 *   Replaces each nested set in +self+ with the elements from that set.
 * - #inspect (aliased as #to_s):
 *   Returns a string displaying the elements.
 * - #join:
 *   Returns a string containing all elements, converted to strings
 *   as needed, and joined by the given record separator.
 * - #to_a:
 *   Returns an array containing all set elements.
 * - #to_set:
 *   Returns +self+ if given no arguments and no block;
 *   with a block given, returns a new set consisting of block
 *   return values.
 *
 * === Methods for Iterating
 *
 * - #each:
 *   Calls the block with each successive element; returns +self+.
 *
 * === Other Methods
 *
 * - #reset:
 *   Resets the internal state; useful if an object
 *   has been modified while an element in the set.
 *
 */
void
Init_Set(void)
{
    rb_cSet = rb_define_class("Set", rb_cObject);
    rb_include_module(rb_cSet, rb_mEnumerable);

    id_each_entry = rb_intern_const("each_entry");
    id_any_p = rb_intern_const("any?");
    id_new = rb_intern_const("new");
    id_i_hash = rb_intern_const("@hash");
    id_set_iter_lev = rb_make_internal_id();

    rb_define_alloc_func(rb_cSet, set_s_alloc);
    rb_define_singleton_method(rb_cSet, "[]", set_s_create, -1);

    rb_define_method(rb_cSet, "initialize", set_i_initialize, -1);
    rb_define_method(rb_cSet, "initialize_copy", set_i_initialize_copy, 1);

    rb_define_method(rb_cSet, "&", set_i_intersection, 1);
    rb_define_alias(rb_cSet, "intersection", "&");
    rb_define_method(rb_cSet, "-", set_i_difference, 1);
    rb_define_alias(rb_cSet, "difference", "-");
    rb_define_method(rb_cSet, "^", set_i_xor, 1);
    rb_define_method(rb_cSet, "|", set_i_union, 1);
    rb_define_alias(rb_cSet, "+", "|");
    rb_define_alias(rb_cSet, "union", "|");
    rb_define_method(rb_cSet, "<=>", set_i_compare, 1);
    rb_define_method(rb_cSet, "==", set_i_eq, 1);
    rb_define_alias(rb_cSet, "eql?", "==");
    rb_define_method(rb_cSet, "add", set_i_add, 1);
    rb_define_alias(rb_cSet, "<<", "add");
    rb_define_method(rb_cSet, "add?", set_i_add_p, 1);
    rb_define_method(rb_cSet, "classify", set_i_classify, 0);
    rb_define_method(rb_cSet, "clear", set_i_clear, 0);
    rb_define_method(rb_cSet, "collect!", set_i_collect, 0);
    rb_define_alias(rb_cSet, "map!", "collect!");
    rb_define_method(rb_cSet, "compare_by_identity", set_i_compare_by_identity, 0);
    rb_define_method(rb_cSet, "compare_by_identity?", set_i_compare_by_identity_p, 0);
    rb_define_method(rb_cSet, "delete", set_i_delete, 1);
    rb_define_method(rb_cSet, "delete?", set_i_delete_p, 1);
    rb_define_method(rb_cSet, "delete_if", set_i_delete_if, 0);
    rb_define_method(rb_cSet, "disjoint?", set_i_disjoint, 1);
    rb_define_method(rb_cSet, "divide", set_i_divide, 0);
    rb_define_method(rb_cSet, "each", set_i_each, 0);
    rb_define_method(rb_cSet, "empty?", set_i_empty, 0);
    rb_define_method(rb_cSet, "flatten", set_i_flatten, 0);
    rb_define_method(rb_cSet, "flatten!", set_i_flatten_bang, 0);
    rb_define_method(rb_cSet, "hash", set_i_hash, 0);
    rb_define_method(rb_cSet, "include?", set_i_include, 1);
    rb_define_alias(rb_cSet, "member?", "include?");
    rb_define_alias(rb_cSet, "===", "include?");
    rb_define_method(rb_cSet, "inspect", set_i_inspect, 0);
    rb_define_alias(rb_cSet, "to_s", "inspect");
    rb_define_method(rb_cSet, "intersect?", set_i_intersect, 1);
    rb_define_method(rb_cSet, "join", set_i_join, -1);
    rb_define_method(rb_cSet, "keep_if", set_i_keep_if, 0);
    rb_define_method(rb_cSet, "merge", set_i_merge, -1);
    rb_define_method(rb_cSet, "proper_subset?", set_i_proper_subset, 1);
    rb_define_alias(rb_cSet, "<", "proper_subset?");
    rb_define_method(rb_cSet, "proper_superset?", set_i_proper_superset, 1);
    rb_define_alias(rb_cSet, ">", "proper_superset?");
    rb_define_method(rb_cSet, "reject!", set_i_reject, 0);
    rb_define_method(rb_cSet, "replace", set_i_replace, 1);
    rb_define_method(rb_cSet, "reset", set_i_reset, 0);
    rb_define_method(rb_cSet, "size", set_i_size, 0);
    rb_define_alias(rb_cSet, "length", "size");
    rb_define_method(rb_cSet, "select!", set_i_select, 0);
    rb_define_alias(rb_cSet, "filter!", "select!");
    rb_define_method(rb_cSet, "subset?", set_i_subset, 1);
    rb_define_alias(rb_cSet, "<=", "subset?");
    rb_define_method(rb_cSet, "subtract", set_i_subtract, 1);
    rb_define_method(rb_cSet, "superset?", set_i_superset, 1);
    rb_define_alias(rb_cSet, ">=", "superset?");
    rb_define_method(rb_cSet, "to_a", set_i_to_a, 0);
    rb_define_method(rb_cSet, "to_set", set_i_to_set, -1);

    /* :nodoc: */
    VALUE compat = rb_define_class_under(rb_cSet, "compatible", rb_cObject);
    rb_marshal_define_compat(rb_cSet, compat, compat_dumper, compat_loader);

    rb_provide("set.rb");
}
