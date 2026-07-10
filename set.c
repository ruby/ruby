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
#include "internal/vm.h"
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
static ID id_subclass_compatible;
static ID id_class_methods;

#define RSET_INITIALIZED FL_USER1
#define RSET_LEV_MASK (FL_USER13 | FL_USER14 | FL_USER15 |                /* FL 13..19 */ \
                        FL_USER16 | FL_USER17 | FL_USER18 | FL_USER19)
#define RSET_LEV_SHIFT (FL_USHIFT + 13)
#define RSET_LEV_MAX 127 /* 7 bits */

#define SET_ASSERT(expr) RUBY_ASSERT_MESG_WHEN(SET_DEBUG, expr, #expr)

#define RSET_SIZE(set) set_table_size(RSET_TABLE(set))
#define RSET_EMPTY(set) (RSET_SIZE(set) == 0)
#define RSET_SIZE_NUM(set) SIZET2NUM(RSET_SIZE(set))
#define RSET_IS_MEMBER(set, item) set_table_lookup(RSET_TABLE(set), (st_data_t)(item))
#define RSET_COMPARE_BY_IDENTITY(set) (RSET_TABLE(set)->type == &identhash)

struct set_object {
    set_table table;
};

static int
mark_and_pin_key(st_data_t key, st_data_t data)
{
    rb_gc_mark((VALUE)key);

    return ST_CONTINUE;
}

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
    if (sobj->table.entries) {
        if (sobj->table.type == &identhash) {
            set_table_foreach(&sobj->table, mark_and_pin_key, 0);
        }
        else {
            set_table_foreach(&sobj->table, mark_key, 0);
        }
    }
}

static void
set_free(void *ptr)
{
    struct set_object *sobj = ptr;
    set_free_embedded_table(&sobj->table);
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
    rb_gc_mark_and_move((VALUE *)key);

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
    .flags = RUBY_TYPED_EMBEDDABLE | RUBY_TYPED_THREAD_SAFE_FREE | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FROZEN_SHAREABLE
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
set_table_insert_wb(set_table *tab, VALUE set, VALUE key)
{
    if (tab->type != &identhash && rb_obj_class(key) == rb_cString && !RB_OBJ_FROZEN(key)) {
        key = rb_hash_key_str(key);
    }
    int ret = set_insert(tab, (st_data_t)key);
    if (ret == 0) RB_OBJ_WRITTEN(set, Qundef, key);
    return ret;
}

static int
set_insert_wb(VALUE set, VALUE key)
{
    return set_table_insert_wb(RSET_TABLE(set), set, key);
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
 *  Returns a new set populated with the given +objects+:
 *
 *    Set[1, 'one', :one, 1.0, %w[a b c], {foo: 0, bar: 1}]
 *    # => Set[1, "one", :one, 1.0, ["a", "b", "c"], {foo: 0, bar: 1}]
 *    Set[Set[0, 1, 2], Set[%w[a b c]]]
 *    # => Set[Set[0, 1, 2], Set[["a", "b", "c"]]]
 *    Set[] # => Set[]
 *
 *  Related: see {Methods for Creating a Set}[rdoc-ref:Set@Methods+for+Creating+a+Set].
 *
 */
static VALUE
set_s_create(int argc, VALUE *argv, VALUE klass)
{
    VALUE set = set_alloc_with_size(klass, argc);
    set_table *table = RSET_TABLE(set);
    int i;

    for (i=0; i < argc; i++) {
        set_table_insert_wb(table, set, argv[i]);
    }

    return set;
}

static VALUE
set_s_inherited(VALUE klass, VALUE subclass)
{
    if (klass == rb_cSet) {
        // When subclassing directly from Set, include the compatibility layer
        rb_require("set/subclass_compatible.rb");
        VALUE subclass_compatible = rb_const_get(klass, id_subclass_compatible);
        rb_include_module(subclass, subclass_compatible);
        rb_extend_object(subclass, rb_const_get(subclass_compatible, id_class_methods));
    }
    return Qnil;
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
    set_insert_wb(set, element);
    return element;
}

static VALUE
set_initialize_with_block(RB_BLOCK_CALL_FUNC_ARGLIST(i, set))
{
    VALUE element = rb_yield(i);
    set_insert_wb(set, element);
    return element;
}

/*
 * call-seq:
 *   Set.new(object = nil) -> new_set
 *   Set.new(object = nil) {|element| ... } -> new_set
 *
 * Returns a new set based on the given +object+,
 * which must be an Enumerable or +nil+.
 *
 * With argument +object+ given as +nil+,
 * returns a new empty set:
 *
 *   Set.new                          # => Set[]
 *   Set.new { fail 'Cannot happen' } # => Set[]  # Block not called.
 *
 * With no block given and enumerable argument +object+ given,
 * populates the new set with the elements of +object+:
 *
 *   Set.new(%w[ a b c ])      # => Set["a", "b", "c"]
 *   Set.new({foo: 0, bar: 1}) # => Set[[:foo, 0], [:bar, 1]]
 *   Set.new(4..10)            # => Set[4, 5, 6, 7, 8, 9, 10]
 *   Set.new(Dir.new('lib')).take(5)
 *   # => [".", "..", "bundled_gems.rb", "bundler", "bundler.rb"]
 *   Set.new(File.new('doc/NEWS/NEWS-4.0.0.md')).take(3)
 *   # => ["# NEWS for Ruby 4.0.0\n", "\n", "This document is a list of user-visible feature changes\n"]
 *
 * With a block given and enumerable argument +object+ given,
 * calls the block with each element of +object+;
 * adds the block's return value to the new set:
 *
 *   Set.new(4..10) {|i| i * 2 } # => Set[8, 10, 12, 14, 16, 18, 20]
 *
 * Related: see {Methods for Creating a Set}[rdoc-ref:Set@Methods+for+Creating+a+Set].
 *
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
                set_table_insert_wb(into, set, key);
            }
        }
        else {
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

    set_free_embedded_table(&sobj->table);
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
 *    inspect -> string
 *
 *  Returns a string representation of +self+:
 *
 *    Set[*%w[foo bar], {foo: 0, bar: 1}].inspect
 *    # => "Set[\"foo\", \"bar\", {foo: 0, bar: 1}]"
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
 *  Returns an array containing the elements of +self+:
 *
 *    Set[1, 2].to_a       # => [1, 2]
 *    Set[1, 'c', :s].to_a # => [1, "c", :s]
 *
 *  Related: {Methods for Converting}[rdoc-ref:Set@Methods+for+Converting].
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
 *    to_set {|element| ... } -> new_set
 *    to_set -> self or new_set
 *
 *  With a block given, creates and returns a new set;
 *  calls the block with each element of +self+,
 *  and adds the block's returns value to the new set:
 *
 *    set = Set[*0..9]        # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *    set.to_set {|i| i * 2 } # => Set[0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
 *
 *  With no block given, when +self+ is an instance of +Set+,
 *  returns +self+:
 *
 *    set = Set[*0..9]
 *    set.to_set
 *    set.to_set.equal?(set) # => true
 *
 *  With no block given, when +self+ is an instance of a subclass of +Set+,
 *  returns a set containing the elements of +self+:
 *
 *    class MySet < Set; end
 *    my_set = MySet[*0..9] # => #<MySet: {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}>
 *    set = my_set.to_set   # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Set@Methods+for+Converting].
 */
static VALUE
set_i_to_set(VALUE set)
{
    if (rb_obj_is_instance_of(set, rb_cSet) && !rb_block_given_p()) {
        return set;
    }

    return rb_funcall_passing_block(rb_cSet, id_new, 1, &set);
}

/*
 *  call-seq:
 *    join(separator = $,) -> string
 *
 *  Returns the string formed by joining the string-converted elements of +self+
 *  with the given +separator+ (defaults to <tt>$,</tt>):
 *
 *    $, # => nil
 *    Set[*%w[foo bar baz]].join
 *    # => "foobarbaz"
 *    Set[*%w[foo bar baz]].join(', ')
 *    # => "foo, bar, baz"
 *
 *  Flattens nested arrays:
 *
 *    Set[[:foo, [:bar, [:baz, :bat]]]].join
 *    # => "foobarbazbat"
 *
 *  Does not flatten nested sets:
 *
 *    Set[Set[:foo, Set[:bar, Set[:baz, :bat]]]].join
 *    # => "Set[:foo, Set[:bar, Set[:baz, :bat]]]"
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Set@Methods+for+Converting].
 */
static VALUE
set_i_join(int argc, VALUE *argv, VALUE set)
{
    rb_check_arity(argc, 0, 1);
    return rb_ary_join(set_i_to_a(set), argc == 0 ? Qnil : argv[0]);
}

/*
 *  call-seq:
 *    add(object) -> self
 *
 *  Adds the given +object+ to +self+; returns +self+:
 *
 *    set = Set[0, 1, 2]
 *    set.add(%w[a b c]) # => Set[0, 1, 2, ["a", "b", "c"]]
 *    set.add(0)         # => Set[0, 1, 2, ["a", "b", "c"]]
 *
 *  Related: see {Methods for Assigning}[rdoc-ref:Set@Methods+for+Assigning].
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
        set_insert_wb(set, item);
    }
    return set;
}

/*
 *  call-seq:
 *    add?(object) -> self or nil
 *
 *  Like #add, but returns +nil+ if the given +object+ is already in +self+:
 *
 *    set = Set[0, 1, 2]
 *    set.add?(:foo)   # => Set[0, 1, 2, :foo]
 *    set.add?(0..9) # => Set[0, 1, 2, :foo, 0..9]
 *    set.add?(2) # => nil
 *
 *  Related: see {Methods for Assigning}[rdoc-ref:Set@Methods+for+Assigning].
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
        return set_insert_wb(set, item) ? Qnil : set;
    }
}

/*
 *  call-seq:
 *    delete(object) -> self
 *
 *  Removes the given +object+ from +self+ if +self+ includes the object;
 *  returns +self+:
 *
 *    set = Set[0, 'zero', :zero]
 *    set.delete(0)       # => Set["zero", :zero]
 *    set.delete(:nosuch) # => Set["zero", :zero]
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Set@Methods+for+Deleting].
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
 *    delete?(object) -> self or nil
 *
 *  Like #delete, but returns +nil+ if the object is not in +self+:
 *
 *    set = Set[0, 'zero', :zero]
 *    set.delete?(0) # => Set["zero", :zero]
 *    set.delete?(0) # => nil
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Set@Methods+for+Deleting].
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
 *    delete_if {|element| ... } -> self
 *    delete_if -> enumerator
 *
 *  With a block given, calls the block with each element in +self+;
 *  removes the element if the block returns a truthy value:
 *
 *    set = Set[*0..9]
 *    # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *    set.delete_if {|element| element.even? }
 *    # => Set[1, 3, 5, 7, 9]
 *
 *  With no block given, returns an Enumerator.
 *
 *  Related: {Methods for Deleting}[rdoc-ref:Set@Methods+for+Deleting].
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
 *    reject! {|element| ... } -> self or nil
 *    reject! -> enumerator
 *
 *  With a block given, like #delete_if, but returns +nil+ if no changes were made:
 *
 *    set = Set[*0..9]                       # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *    set.reject! {|element| element.even? } # => Set[1, 3, 5, 7, 9]
 *    set.reject! {|element| element.even? } # => nil
 *    set.reject! {|element| element.odd? }  # => Set[]
 *
 *  With no block given, returns an Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Set@Methods+for+Deleting].
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
 *    classify {|element| ... } -> hash
 *    classify -> enumerator
 *
 *  With a block given, calls the block with each element of +self+;
 *  returns a hash whose keys are the block's return values.
 *  The value for each key is a set containing the elements
 *  for which the block returned that key.
 *
 *  This example classifies elements by their classes:
 *
 *    set = Set[*(5..7), *%w[foo bar]] # => Set[5, 6, 7, "foo", "bar"]
 *    set.classify {|element| element.class }
 *    # => {Integer => Set[5, 6, 7], String => Set["foo", "bar"]}
 *
 *  With no block given, returns an Enumerator.
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Set@Methods+for+Converting].
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
 *    divide {|ele| ... } -> new_set
 *    divide {|ele0, ele1| ... } -> new_set
 *    divide -> enumerator
 *
 *  With a block given, returns a set of sets.
 *
 *  For a block that accepts one argument,
 *  calls the block with each element;
 *  creates a set for each distinct block return value:
 *
 *    set = Set[*0..9]
 *    # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *    # Divide into mod 3 sets.
 *    set.divide {|ele| ele % 3 }
 *    # => Set[Set[0, 3, 6, 9], Set[1, 4, 7], Set[2, 5, 8]]
 *    # Divide into mod 5 sets.
 *    set.divide {|ele| ele % 5 }
 *    # => Set[Set[0, 5], Set[1, 6], Set[2, 7], Set[3, 8], Set[4, 9]]
 *
 *    Set[0].divide {|ele| anything } # => Set[Set[0]]
 *    Set[].divide {|ele| not called } # => Set[]
 *
 *  For a block that accepts two arguments,
 *  divides +self+ into connected components based on the binary
 *  relation defined by the block, calling the block with each 2-element
 *  permutation of the elements of +self+:
 *
 *    set = Set[*0..9]
 *    # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *    # Divide into mod 2 sets.
 *    set.divide {|i, j| (i - j) % 2 == 0 }
 *    # => Set[Set[0, 2, 4, 6, 8], Set[1, 3, 5, 7, 9]]
 *    # Divide into mod 3 sets.
 *    set.divide {|i, j| (i - j) % 3 == 0 }
 *    # => Set[Set[0, 3, 6, 9], Set[1, 4, 7], Set[2, 5, 8]]
 *
 *    Set[0].divide {|i, j| not called } # => Set[Set[0]]
 *    Set[].divide {|i, j| not called } # => Set[]
 *
 *  With no block given, returns an Enumerator.
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Set@Methods+for+Converting].
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
 *  Returns +self+ with all elements removed:
 *
 *    Set[1, :one, 'one', 1.0].clear # => Set[]
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Set@Methods+for+Deleting].
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
        set_table_insert_wb(data->into, data->set, key);
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
 *    self & enumerable -> new_set
 *
 *  Returns a new set containing the {intersection}[https://en.wikipedia.org/wiki/Intersection_(set_theory)]
 *  of +self+ and +enumerable+;
 *  that is, containing all elements common to both, with no duplicates.
 *  Argument +enumerable+ must be an Enumerable object:
 *
 *    set = Set[*(0..6), *%w[ a b c]] # => Set[0, 1, 2, 3, 4, 5, 6, "a", "b", "c"]
 *    set & ['c', 6, 8, 4]            # => Set["c", 6, 4]
 *    set & [:foo, :bar]              # => Set[]  # No elements in common.
 *
 *  Related: see {Methods for Set Operations}[rdoc-ref:Set@Methods+for+Set+Operations].
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
        rb_block_call_noescape(other, enum_method_id(other), 0, 0, set_intersection_block, (VALUE)&data);
    }

    return new_set;
}

/*
 *  call-seq:
 *    include?(object) -> true or false
 *
 *  Returns whether the given +object+ is an element of +self+:
 *
 *    set = [0, :zero, '0']
 *    set.include?('0')    # => true
 *    set.include?('zero') # => false
 *
 *  Tests equality using `hash` and `eql?`.
 *
 *  Aliased as #===, which means that sets may be used in +case+ expressions:
 *
 *    case :apple
 *    when Set[:potato, :carrot]
 *      'vegetable'
 *    when Set[:apple, :banana]
 *      'fruit'
 *    else
 *      'unknown'
 *    end
 *    # => "fruit"
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
    set_table_insert_wb(args->into, args->set, key);
    return ST_CONTINUE;
}

static VALUE
set_merge_block(RB_BLOCK_CALL_FUNC_ARGLIST(key, set))
{
    VALUE element = key;
    set_insert_wb(set, element);
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
            set_table_insert_wb(into, set, RARRAY_AREF(arg, i));
        }
    }
    else {
        rb_block_call(arg, enum_method_id(arg), 0, 0, set_merge_block, (VALUE)set);
    }
}

/*
 *  call-seq:
 *    merge(*enumerables, **nil) -> self
 *
 *  Adds each element of each of the given +enumerables+ to +self+;
 *  returns +self+:
 *
 *    set = Set[*0..2]                 # => Set[0, 1, 2]
 *    set.merge('a'..'c', %w[foo bar]) # => Set[0, 1, 2, "a", "b", "c", "foo", "bar"]
 *    set.merge('a'..'c', %w[foo bar]) # => Set[0, 1, 2, "a", "b", "c", "foo", "bar"]
 *
 *  Related: see {Methods for Assigning}[rdoc-ref:Set@Methods+for+Assigning].
 *
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
        set_free_embedded_table(&sobj->table);
        memcpy(&sobj->table, new, sizeof(*new));
        SIZED_FREE(new);
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
 *  Sets +self+ to compare by object identity
 *  (rather than by object content, which is the initial setting);
 *  returns +self+:
 *
 *    set = Set.new
 *    set.compare_by_identity
 *    str = +"foo"
 *    set.add(str)
 *    # =>  Set["foo"]
 *    set.include?(str)
 *    # => true
 *    set.add(str)
 *    # => Set["foo"])
 *    set.include?(+"foo")
 *    # => false
 *    set.add(+"foo")
 *    # => Set["foo", "foo"])
 *
 *  Once set, the compare-by-identity property may not be unset.
 *
 *  Related: #compare_by_identity?.
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
 *  Returns whether +self+ compares elements by object identity
 *  (rather than by content):
 *
 *    set = Set[]
 *    set.compare_by_identity? # => false
 *    set.compare_by_identity
 *    set.compare_by_identity? # => true
 *
 *  Related: #compare_by_identity;
 *  see also {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
 *  Returns the number of elements in +self+:
 *
 *    Set[*0..9].size # => 10
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
 *  Returns whether +self+ contains no elements:
 *
 *    Set[].empty?  # => true
 *    Set[0].empty? # => false
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
    if (set_table_insert_wb(table, set, element)) {
        set_table_delete(table, &element);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    self ^ enumerable -> new_set
 *
 *  Returns a new set containing
 *  the {exclusive OR}[https://en.wikipedia.org/wiki/Exclusive_or]
 *  of +self+ and the given +enumerable+;
 *  that is, containing each element that is in either +self+ or +enumerable+,
 *  but not in both:
 *
 *    set = Set[0, 1, 2]
 *    set ^ Set[1, 2, 3]        # => Set[0, 3]
 *    set ^ Set[2, 1]           # => Set[0]
 *    set ^ Set[2, *('a'..'c')] # => Set[0, 1, "a", "b", "c"]
 *    set ^ Set[2, 1, 0]        # => Set[]
 *
 *  For \Set +set+ and \Enumerable +enumerable+, these expressions are equivalent:
 *
 *    set ^ enumerable
 *    ((set | enumerable) - (set & enumerable))
 *
 *  Related: see {Methods for Set Operations}[rdoc-ref:Set@Methods+for+Set+Operations].
 */
static VALUE
set_i_xor(VALUE set, VALUE other)
{
    VALUE new_set = rb_obj_dup(set);

    if (rb_obj_is_kind_of(other, rb_cSet)) {
        set_iter(other, set_xor_i, (st_data_t)new_set);
    }
    else {
        VALUE tmp = set_s_alloc(rb_cSet);
        set_merge_enum_into(tmp, other);
        set_iter(tmp, set_xor_i, (st_data_t)new_set);
    }

    return new_set;
}

/*
 *  call-seq:
 *    self | enumerable -> new_set
 *
 *  Returns a new set containing
 *  the {union}[https://en.wikipedia.org/wiki/Union_(set_theory)]
 *  of +self+ and the given +enumerable+;
 *  that is, containing the elements of both +self+ and +enumerable+.
 *
 *    set = Set[0, 1, 2]
 *    set | Set[2, 1, 'a'] # => Set[0, 1, 2, "a"]
 *    set | set            # => Set[0, 1, 2]
 *
 *  Related: see {Methods for Set Operations}[rdoc-ref:Set@Methods+for+Set+Operations].
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
 *    subtract(enumerable) -> self
 *
 *  Deletes from +self+ every element found in the given +enumerable+;
 *  returns +self+:
 *
 *    set = Set[*0..9]        # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *    set.subtract(5..14)     # => Set[0, 1, 2, 3, 4]
 *    set.subtract(Set[6, 2]) # => Set[0, 1, 3, 4]
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Set@Methods+for+Deleting].
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
 *    self - enumerable -> new_set
 *
 *  Returns a new set containing the
 *  {difference}[https://en.wikipedia.org/wiki/Complement_(set_theory)#Relative_complement]
 *  of +self+ and argument +enumerable+;
 *  that is, containing all elements in +self+ that are not in +enumerable+.
 *
 *
 *    set = Set[*(0..6), *%w[ a b c]] # => Set[0, 1, 2, 3, 4, 5, 6, "a", "b", "c"]
 *    set - ['b', 6, 4, 1]            # => Set[0, 2, 3, 5, "a", "c"]
 *    set - ['d', 7, 9]               # => Set[0, 1, 2, 3, 4, 5, 6, "a", "b", "c"]
 *
 *  Related: see {Methods for Set Operations}[rdoc-ref:Set@Methods+for+Set+Operations].
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
 *    each {|element| ... } -> self
 *    each -> enumerator
 *
 *  With a block given, calls the block once for each element in the set,
 *  passing the element as a parameter;
 *  returns +self+:
 *
 *    sum = 0
 *    Set[1, 2, 3].each {|i| sum += i }
 *    sum => 6
 *
 *  With no block given, returns an Enumerator.
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
    set_insert_wb((VALUE)data, rb_yield((VALUE)key));
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    collect! {|element| ... } -> self
 *    collect! -> enumerator
 *
 *  With a block given, calls the block with each element in +self+;
 *  replaces the element with the block's return value:
 *
 *    Set[1, :one, 'one', 1.0].collect! {|element| element.class }
 *    # => Set[Integer, Symbol, String, Float]
 *
 *  With no block given, returns an Enumerator.
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Set@Methods+for+Converting].
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
 *    keep_if {|element| ... } -> self
 *    keep_if -> enumerator
 *
 *  With a block given,
 *  calls the block with each element in +self+,
 *  deleting the element if the block returns +false+ or +nil+;
 *  returns +self+:
 *
 *    set = Set[*0..9]           # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *    set.keep_if {|i| i.even? } # => Set[0, 2, 4, 6, 8]
 *    set.keep_if {|i| i.odd? }  # => Set[]
 *
 *  With no block given, returns an Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Set@Methods+for+Deleting].
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
 *    select! {|element| ... } -> self or nil
 *    select! -> enumerator
 *
 *  With a block given, like #keep_if, but returns +nil+ if no changes were made:
 *
 *    set = Set[*0..9]           # => Set[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *    set.select! {|i| i.even? } # => Set[0, 2, 4, 6, 8]
 *    set.select! {|i| i.even? } # => nil
 *    set.select! {|i| i.odd? }  # => Set[]
 *
 *  With no block given, returns an Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Set@Methods+for+Deleting].
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
 *    replace(enumerable) -> self
 *
 *  Replaces the contents +self+ with the contents of the given +enumerable+;
 *  returns +self+:
 *
 *    set = Set[1, 'c', :s] # => Set[1, "c", :s]
 *    set.replace([1, 2])   # => Set[1, 2]
 *
 *  Related: see {Methods for Assigning}[rdoc-ref:Set@Methods+for+Assigning].
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
 *  Resets the internal state of +self+; returns +self+.
 *
 *  A set relies on the #hash results of each element being consistent.
 *  Modifying an element in a way that changes the results of #hash
 *  may allow duplicate elements in the set:
 *
 *    array = [1]
 *    set = Set[array]  # => Set[[1]]
 *    array << 2
 *    set.add(array)    # => Set[[1, 2], [1, 2]]
 *
 *  Calling #reset will recalculate all of the hash values and remove
 *  duplicate elements:
 *
 *    set.reset         # => Set[[1, 2]]
 *
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
 *    flatten -> new_set
 *
 *  Returns a new set that is a copy of +self+,
 *  but with +self+ and its nested sets flattened;
 *  that is, their elements become elements of +self+:
 *
 *    Set[Set[0, 1], Set[2, 3]].flatten
 *    # => Set[0, 1, 2, 3]
 *    Set[Set[0, 1], Set[Set[2, 3], Set[3, 4]]].flatten
 *    # => Set[0, 1, 2, 3, 4]
 *
 *  Does not flatten nested arrays or hashes:
 *
 *    Set[%w[foo bar]].flatten      # => Set[["foo", "bar"]]
 *    Set[{foo: 0, bar: 1}].flatten # => Set[{foo: 0, bar: 1}]
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Set@Methods+for+Converting].
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
 *    flatten! -> self or nil
 *
 *  Like #flatten, but if any changes were made
 *  replaces +self+ with the result and returns +self+:
 *
 *    Set[Set[0, 1], Set[2, 3]].flatten!
 *    # => Set[0, 1, 2, 3]
 *    Set[Set[0, 1], Set[Set[2, 3], Set[3, 4]]].flatten!
 *    # => Set[0, 1, 2, 3, 4]
 *
 *  Returns +nil+ if no changes were made:
 *
 *    Set[0, 1, 2].flatten! # => nil
 *
 *  Related: see {Methods for Assigning}[rdoc-ref:Set@Methods+for+Assigning].
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
 *    proper_subset?(other_set) -> true or false
 *
 *  Returns whether +self+ is
 *  a {proper subset}[https://en.wikipedia.org/wiki/Subset]
 *  of the given +other_set+:
 *
 *    set = Set[*'b'..'e']
 *    set.proper_subset?(set)            # => false
 *    set.proper_subset?(Set[*'a'..'f']) # => true
 *
 *  Related: {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
 *    subset?(other_set) -> true or false
 *
 *  Returns whether +self+ is a {subset}[https://en.wikipedia.org/wiki/Subset]
 *  of the given +other_set+:
 *
 *    set = Set[*'b'..'e']
 *    set.subset?(set)            # => true
 *    set.subset?(Set[*'a'..'f']) # => true
 *    set.subset?(Set[*'c'..'e']) # => false
 *
 *  Related: {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
 *    proper_superset?(other_set) -> true or false
 *
 *  Returns whether +self+ is
 *  a {proper superset}[https://en.wikipedia.org/wiki/Subset]
 *  of the given +other_set+:
 *
 *    set = Set[*'a'..'f']
 *    set.proper_superset?(set)            # => false
 *    set.proper_superset?(Set[*'b'..'e']) # => true
 *
 *  Related: {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
 *    superset?(other_set) -> true or false
 *
 *  Returns whether +self+ is a {superset}[https://en.wikipedia.org/wiki/Subset]
 *  of the given +other_set+:
 *
 *    set = Set[*'a'..'f']          # => Set["a", "b", "c", "d", "e", "f"]
 *    set.superset?(set)            # => true
 *    set.superset?(Set[*'b'..'e']) # => true
 *    set.superset?(Set[*'b'..'x']) # => false
 *
 *  Related: {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
 *    intersect?(enumerable) -> true or false
 *
 *  Returns whether +self+ and +enumerable+ have any elements in common:
 *
 *    set = Set[0, 'zero', :zero]
 *    set.intersect?([0, 1, 2])        # => true
 *    set.intersect?(%w[zero one two]) # => true
 *    set.intersect?(Set[3])           # => false
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
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
 *    disjoint?(enumerable) -> true or false
 *
 *  Returns whether no element of +enumerable+ is present in +self+:
 *
 *    set = Set[0, 'zero', :zero]
 *    set.disjoint?([1, 2, 3])    # => true
 *    set.disjoint?([0, 1, 2, 3]) # => false
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Set@Methods+for+Querying].
 */
static VALUE
set_i_disjoint(VALUE set, VALUE other)
{
    return RBOOL(!RTEST(set_i_intersect(set, other)));
}

/*
 *  call-seq:
 *    self <=> object -> -1, 0, 1, or nil
 *
 *  Compares +self+ and +object+.
 *
 *  If +object+ is another set, returns:
 *
 *  - +-1+, if +self+ is a proper subset of +object+.
 *  - +0+, if +self+ and +object+ have the same elements.
 *  - +1+, if +self+ is a proper superset of +object+.
 *  - +nil+, if none of the above;
 *    that is, if +self+ and +object+ each have one or more elements
 *    not included in the other.
 *
 *  Examples:
 *
 *    set = Set[0, 1, 2]
 *    set <=> Set[3, 2, 1, 0] # => -1
 *    set <=> Set[2, 1, 0]    # => 0
 *    set <=> Set[1, 0]       # => 1
 *    set <=> Set[1, 0, 3]    # => nil
 *
 *  Returns +nil+ if +object+ is not a set:
 *
 *    set <=> [2, 1, 0] # => nil  # Array, not Set.
 *
 *  Related: see {Methods for Comparing}[rdoc-ref:Set@Methods+for+Comparing].
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
 *    self == object -> true or false
 *
 *  Returns whether +object+ is a set, and has the same elements as +self+:
 *
 *    set = Set[0, 1, 2]
 *    set == Set[1, 2, 0]   # => true
 *    set == [1, 2, 3]      # => false
 *    set == Set[1, 2, '3'] # => false
 *
 *  Related: see {Methods for Comparing}[rdoc-ref:Set@Methods+for+Comparing].
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
 *  Returns the integer hash value for +self+.
 *
 *  Two sets with the same content have the same hash value.
 *
 *    Set[0, 1].hash == Set[1, 0].hash # => true
 *    Set[0, 1].hash == Set[0].hash    # => false
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
 * An instance of class \Set contains a collection
 * of objects (elements), with no duplicates.
 *
 * By default:
 *
 * - Set determines equality via Object#eql? and Object#hash,
 *   and assumes that these values do not change for a stored element.
 *   If these values do change, the set enters an unreliable state;
 *   see #reset.
 * - A String instance added to a set is stored as a frozen copy of the string,
 *   unless it is already frozen.
 *
 * Calling #compare_by_identity causes:
 *
 * - All following determinations of equality
 *   to use object identity instead of the methods mentioned above.
 * - A String added to a set is stored "as is", whether or not frozen.
 *
 * \Set includes module Enumerable, and is easy to use with other enumerable objects.
 * Many of its methods accept enumerable objects as arguments;
 * any enumerable object may be converted to a set via #to_set.
 *
 * == Contact
 *
 * - Akinori MUSHA <knu@iDaemons.org> (current maintainer)
 *
 * == Inheriting from \Set
 *
 * Before Ruby 4.0 (released in December, 2025),
 * class \Set had a different, less efficient implementation.
 * In Ruby 4.0, the class was reimplemented in C,
 * and the behaviors of some methods were adjusted.
 *
 * When compatibility with the older implementation is needed,
 * a \Set subclass should inherit directly from class +Set+;
 * this automatically includes module +Set::SubclassCompatible+,
 * which makes behaviors closer to those in the older implementation.
 *
 * A difference may be seen as follows:
 *
 *   Set[[1, 2, 3]]       # => Set[[1, 2, 3]]
 *   class MySet < Set; end
 *   MySet[[1, 2, 3]]     # => #<MySet: {[1, 2, 3]}>  # Same as in Ruby 3.4.
 *
 * When backward compatibility is not needed,
 * a \Set subclass should inherit from +Set::CoreSet+,
 * which avoids including the compatibility layer:
 *
 *   class MyCoreSet < Set::CoreSet; end
 *   MyCoreSet[[1, 2, 3]] # => MyCoreSet[[1, 2, 3]]
 *
 * == What's Here
 *
 * First, what's elsewhere. \Class \Set:
 *
 * - Inherits from {class Object}[rdoc-ref:Object@Whats+Here].
 * - Includes {module Enumerable}[rdoc-ref:Enumerable@Whats+Here],
 *   which provides dozens of additional methods.
 *
 * In particular, class \Set does not have many methods of its own
 * for fetching or for iterating.
 * Instead, it relies on those in \Enumerable.
 *
 * Here, class \Set provides methods that are useful for:
 *
 * - {Creating a Set}[rdoc-ref:Set@Methods+for+Creating+a+Set]
 * - {Set Operations}[rdoc-ref:Set@Methods+for+Set+Operations]
 * - {Comparing}[rdoc-ref:Set@Methods+for+Comparing]
 * - {Querying}[rdoc-ref:Set@Methods+for+Querying]
 * - {Assigning}[rdoc-ref:Set@Methods+for+Assigning]
 * - {Deleting}[rdoc-ref:Set@Methods+for+Deleting]
 * - {Converting}[rdoc-ref:Set@Methods+for+Converting]
 * - {Iterating}[rdoc-ref:Set@Methods+for+Iterating]
 * - {And more....}[rdoc-ref:Set@Other+Methods]
 *
 * === Methods for Creating a \Set
 *
 * - ::[]:
 *   Returns a new set populated with the given objects.
 * - ::new:
 *   Returns a new set based on the given object (if no block given),
 *   or on the return values from the called block (if a block given).
 *
 * === Methods for \Set Operations
 *
 * - #& (aliased as #intersection):
 *   Returns a new set containing the intersection of +self+ and the given enumerable.
 * - #- (aliased as #difference):
 *   Returns a new set containing the difference of +self+ and the given enumerable.
 * - #^: Returns a new set containing the exclusive OR of +self+ and the given enumerable.
 * - #| (aliased as #union and #+):
 *   Returns a new set containing the union of +self+ and the given enumerable.
 *
 * === Methods for Comparing
 *
 * - #<=>: Returns -1, 0, or 1 as +self+ is less than, equal to,
 *   or greater than a given object.
 * - #==: Returns whether +self+ and a given enumerable are equal,
 *   as determined by Object#eql?.
 * - #compare_by_identity?:
 *   Returns whether +self+ considers only identity
 *   when comparing elements.
 * - #proper_subset? (aliased as #<):
 *   Returns whether the given enumerable is a proper subset of +self+.
 * - #proper_superset? (aliased as #>):
 *   Returns whether the given enumerable is a proper superset of +self+.
 * - #subset? (aliased as #<=):
 *   Returns whether the given object is a subset of +self+.
 * - #superset? (aliased as #>=):
 *   Returns whether the given enumerable is a superset of +self+.
 *
 * === Methods for Querying
 *
 * - #disjoint?:
 *   Returns whether no element of the given enumerable is present in +self+.
 * - #empty?:
 *   Returns whether +self+ contains no elements.
 * - #include? (aliased as #member? and #===):
 *   Returns whether the given object is an element of +self+.
 * - #intersect?:
 *   Returns whether +self+ and the given enumerable have any elements in common.
 * - #size (aliased as #length):
 *   Returns the number of elements in +self+.
 *
 * === Methods for Assigning
 *
 * - #add (aliased as #<<):
 *   Adds the given object to +self+; returns +self+.
 * - #add?:
 *   Like #add, but returns +nil+ if the given object is already in +self+.
 * - #merge:
 *   Adds each element of each of the given enumerables to +self+; returns +self+.
 * - #replace:
 *   Replaces the contents of +self+ with the contents of the given enumerable;
 *   returns +self+.
 *
 * === Methods for Deleting
 *
 * - #clear:
 *   Removes all elements from +self+; returns +self+.
 * - #delete:
 *   Removes the given object from +self+ if +self+ includes the object; returns +self+.
 * - #delete?:
 *   Like #delete, but returns +nil+ if the object is not in +self+.
 * - #delete_if:
 *   Calls the block with each element in +self+;
 *   removes the element if the block returns a truthy value.
 * - #keep_if:
 *   Calls the block with each element in +self+,
 *   deleting the element if the block returns +false+ or +nil+; returns +self+.
 * - #reject!
 *   Like #delete_if, but returns +nil+ if no changes were made.
 * - #select! (aliased as #filter!):
 *   Like #keep_if, but returns +nil+ if no changes were made.
 * - #subtract:
 *   Deletes from +self+ every element found in the given enumerable; returns +self+:
 *
 * === Methods for Converting
 *
 * - #classify:
 *   Returns a hash that partitions the elements,
 *   as determined by the given block.
 * - #collect! (aliased as #map!):
 *   Replaces each element with a block return-value.
 * - #divide:
 *   Returns a set of sets that partition the elements,
 *   as determined by the given block.
 * - #flatten:
 *   Returns a new set that is a recursive flattening of +self+.
 * - #flatten!: Like #flatten, but if any changes were made
 *   replaces +self+ with the result and returns +self+.
 * - #inspect (aliased as #to_s):
 *   Returns a string representation of +self+.
 * - #join:
 *   Returns the string formed by joining the string-converted elements of +self+
 *   with the given separator.
 * - #to_a:
 *   Returns an array containing the elements of +self+.
 * - #to_set:
 *   With a block given, creates and returns a new set;
 *   calls the block with each element of +self+,
 *   and adds the block's returns value to the new set.
 *
 * === Other Methods
 *
 * - #compare_by_identity:
 *   Sets +self+ to compare by object identity (rather than by object content).
 * - #each:
 *   Calls the block with each successive element of +self+; returns +self+.
 * - #reset:
 *   Resets the internal state of +self+; returns +self+.
 *   Useful if an element has been modified while an element in the set.
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
    id_subclass_compatible = rb_intern_const("SubclassCompatible");
    id_class_methods = rb_intern_const("ClassMethods");
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
    rb_define_method(rb_cSet, "to_set", set_i_to_set, 0);

    /* :nodoc: */
    VALUE compat = rb_define_class_under(rb_cSet, "compatible", rb_cObject);
    rb_marshal_define_compat(rb_cSet, compat, compat_dumper, compat_loader);

    // Create Set::CoreSet before defining inherited, so it does not include
    // the backwards compatibility layer.
    rb_define_class_under(rb_cSet, "CoreSet", rb_cSet);
    rb_define_private_method(rb_singleton_class(rb_cSet), "inherited", set_s_inherited, 1);

    rb_provide("set.rb");
}
