/**********************************************************************

  hash.c -

  $Author$
  created at: Mon Nov 22 18:51:18 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"

#include <errno.h>

#ifdef __APPLE__
# ifdef HAVE_CRT_EXTERNS_H
#  include <crt_externs.h>
# else
#  include "missing/crt_externs.h"
# endif
#endif

#include "debug_counter.h"
#include "id.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/bignum.h"
#include "internal/basic_operators.h"
#include "internal/class.h"
#include "internal/cont.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/st.h"
#include "internal/symbol.h"
#include "internal/thread.h"
#include "internal/time.h"
#include "internal/vm.h"
#include "probes.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby_assert.h"
#include "symbol.h"
#include "ruby/thread_native.h"
#include "ruby/ractor.h"
#include "vm_sync.h"
#include "builtin.h"

/* Flags of RHash
 *
 * 1:     RHASH_PASS_AS_KEYWORDS
 *            The hash is flagged as Ruby 2 keywords hash.
 * 2:     RHASH_PROC_DEFAULT
 *            The hash has a default proc (rather than a default value).
 * 3:     RHASH_ST_TABLE_FLAG
 *            The hash uses a ST table (rather than an AR table).
 * 4-7:   RHASH_AR_TABLE_SIZE_MASK
 *            The size of the AR table.
 * 8-11:  RHASH_AR_TABLE_BOUND_MASK
 *            The bounds of the AR table.
 * 13-19: RHASH_LEV_MASK
 *            The iterational level of the hash. Used to prevent modifications
 *            to the hash during iteration.
 */

#ifndef HASH_DEBUG
#define HASH_DEBUG 0
#endif

#if HASH_DEBUG
#include "internal/gc.h"
#endif

#define SET_DEFAULT(hash, ifnone) ( \
    FL_UNSET_RAW(hash, RHASH_PROC_DEFAULT), \
    RHASH_SET_IFNONE(hash, ifnone))

#define SET_PROC_DEFAULT(hash, proc) set_proc_default(hash, proc)

#define COPY_DEFAULT(hash, hash2) copy_default(RHASH(hash), RHASH(hash2))

static inline void
copy_default(struct RHash *hash, const struct RHash *hash2)
{
    hash->basic.flags &= ~RHASH_PROC_DEFAULT;
    hash->basic.flags |= hash2->basic.flags & RHASH_PROC_DEFAULT;
    RHASH_SET_IFNONE(hash, RHASH_IFNONE((VALUE)hash2));
}

static VALUE rb_hash_s_try_convert(VALUE, VALUE);

/*
 * Hash WB strategy:
 *  1. Check mutate st_* functions
 *     * st_insert()
 *     * st_insert2()
 *     * st_update()
 *     * st_add_direct()
 *  2. Insert WBs
 */

/* :nodoc: */
VALUE
rb_hash_freeze(VALUE hash)
{
    return rb_obj_freeze(hash);
}

VALUE rb_cHash;
VALUE rb_cHash_empty_frozen;

static VALUE envtbl;
static ID id_hash, id_flatten_bang;
static ID id_hash_iter_lev;

#define id_default idDefault

VALUE
rb_hash_set_ifnone(VALUE hash, VALUE ifnone)
{
    RB_OBJ_WRITE(hash, (&RHASH(hash)->ifnone), ifnone);
    return hash;
}

int
rb_any_cmp(VALUE a, VALUE b)
{
    if (a == b) return 0;
    if (RB_TYPE_P(a, T_STRING) && RBASIC(a)->klass == rb_cString &&
        RB_TYPE_P(b, T_STRING) && RBASIC(b)->klass == rb_cString) {
        return rb_str_hash_cmp(a, b);
    }
    if (UNDEF_P(a) || UNDEF_P(b)) return -1;
    if (SYMBOL_P(a) && SYMBOL_P(b)) {
        return a != b;
    }

    return !rb_eql(a, b);
}

static VALUE
hash_recursive(VALUE obj, VALUE arg, int recurse)
{
    if (recurse) return INT2FIX(0);
    return rb_funcallv(obj, id_hash, 0, 0);
}

static long rb_objid_hash(st_index_t index);

static st_index_t
dbl_to_index(double d)
{
    union {double d; st_index_t i;} u;
    u.d = d;
    return u.i;
}

long
rb_dbl_long_hash(double d)
{
    /* normalize -0.0 to 0.0 */
    if (d == 0.0) d = 0.0;
#if SIZEOF_INT == SIZEOF_VOIDP
    return rb_memhash(&d, sizeof(d));
#else
    return rb_objid_hash(dbl_to_index(d));
#endif
}

static inline long
any_hash(VALUE a, st_index_t (*other_func)(VALUE))
{
    VALUE hval;
    st_index_t hnum;

    switch (TYPE(a)) {
      case T_SYMBOL:
        if (STATIC_SYM_P(a)) {
            hnum = a >> (RUBY_SPECIAL_SHIFT + ID_SCOPE_SHIFT);
            hnum = rb_hash_start(hnum);
        }
        else {
            hnum = RSYMBOL(a)->hashval;
        }
        break;
      case T_FIXNUM:
      case T_TRUE:
      case T_FALSE:
      case T_NIL:
        hnum = rb_objid_hash((st_index_t)a);
        break;
      case T_STRING:
        hnum = rb_str_hash(a);
        break;
      case T_BIGNUM:
        hval = rb_big_hash(a);
        hnum = FIX2LONG(hval);
        break;
      case T_FLOAT: /* prevent pathological behavior: [Bug #10761] */
        hnum = rb_dbl_long_hash(rb_float_value(a));
        break;
      default:
        hnum = other_func(a);
    }
    if ((SIGNED_VALUE)hnum > 0)
        hnum &= FIXNUM_MAX;
    else
        hnum |= FIXNUM_MIN;
    return (long)hnum;
}

VALUE rb_obj_hash(VALUE obj);
VALUE rb_vm_call0(rb_execution_context_t *ec, VALUE recv, ID id, int argc, const VALUE *argv, const rb_callable_method_entry_t *cme, int kw_splat);

static st_index_t
obj_any_hash(VALUE obj)
{
    VALUE hval = Qundef;
    VALUE klass = CLASS_OF(obj);
    if (klass) {
        const rb_callable_method_entry_t *cme = rb_callable_method_entry(klass, id_hash);
        if (cme && METHOD_ENTRY_BASIC(cme)) {
            // Optimize away the frame push overhead if it's the default Kernel#hash
            if (cme->def->type == VM_METHOD_TYPE_CFUNC && cme->def->body.cfunc.func == (rb_cfunc_t)rb_obj_hash) {
                hval = rb_obj_hash(obj);
            }
            else if (RBASIC_CLASS(cme->defined_class) == rb_mKernel) {
                hval = rb_vm_call0(GET_EC(), obj, id_hash, 0, 0, cme, 0);
            }
        }
    }

    if (UNDEF_P(hval)) {
        hval = rb_exec_recursive_outer_mid(hash_recursive, obj, 0, id_hash);
    }

    while (!FIXNUM_P(hval)) {
        if (RB_TYPE_P(hval, T_BIGNUM)) {
            int sign;
            unsigned long ul;
            sign = rb_integer_pack(hval, &ul, 1, sizeof(ul), 0,
                    INTEGER_PACK_NATIVE_BYTE_ORDER);
            if (sign < 0) {
                hval = LONG2FIX(ul | FIXNUM_MIN);
            }
            else {
                hval = LONG2FIX(ul & FIXNUM_MAX);
            }
        }
        hval = rb_to_int(hval);
    }

    return FIX2LONG(hval);
}

st_index_t
rb_any_hash(VALUE a)
{
    return any_hash(a, obj_any_hash);
}

VALUE
rb_hash(VALUE obj)
{
    return LONG2FIX(any_hash(obj, obj_any_hash));
}


/* Here is a hash function for 64-bit key.  It is about 5 times faster
   (2 times faster when uint128 type is absent) on Haswell than
   tailored Spooky or City hash function can be.  */

/* Here we two primes with random bit generation.  */
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
#define st_index_hash(index) key64_hash(rb_hash_start(index), prime2)

static long
rb_objid_hash(st_index_t index)
{
    return (long)st_index_hash(index);
}

static st_index_t
objid_hash(VALUE obj)
{
    VALUE object_id = rb_obj_id(obj);
    if (!FIXNUM_P(object_id))
        object_id = rb_big_hash(object_id);

#if SIZEOF_LONG == SIZEOF_VOIDP
    return (st_index_t)st_index_hash((st_index_t)NUM2LONG(object_id));
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
    return (st_index_t)st_index_hash((st_index_t)NUM2LL(object_id));
#endif
}

/**
 * call-seq:
 *    obj.hash    -> integer
 *
 * Generates an Integer hash value for this object.  This function must have the
 * property that <code>a.eql?(b)</code> implies <code>a.hash == b.hash</code>.
 *
 * The hash value is used along with #eql? by the Hash class to determine if
 * two objects reference the same hash key.  Any hash value that exceeds the
 * capacity of an Integer will be truncated before being used.
 *
 * The hash value for an object may not be identical across invocations or
 * implementations of Ruby.  If you need a stable identifier across Ruby
 * invocations and implementations you will need to generate one with a custom
 * method.
 *
 * Certain core classes such as Integer use built-in hash calculations and
 * do not call the #hash method when used as a hash key.
 *
 * When implementing your own #hash based on multiple values, the best
 * practice is to combine the class and any values using the hash code of an
 * array:
 *
 * For example:
 *
 *   def hash
 *     [self.class, a, b, c].hash
 *   end
 *
 * The reason for this is that the Array#hash method already has logic for
 * safely and efficiently combining multiple hash values.
 *--
 * \private
 *++
 */
VALUE
rb_obj_hash(VALUE obj)
{
    long hnum = any_hash(obj, objid_hash);
    return ST2FIX(hnum);
}

static const struct st_hash_type objhash = {
    rb_any_cmp,
    rb_any_hash,
};

#define rb_ident_cmp st_numcmp

static st_index_t
rb_ident_hash(st_data_t n)
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

    return (st_index_t)st_index_hash((st_index_t)n);
}

#define identhash rb_hashtype_ident
const struct st_hash_type rb_hashtype_ident = {
    rb_ident_cmp,
    rb_ident_hash,
};

#define RHASH_IDENTHASH_P(hash) (RHASH_TYPE(hash) == &identhash)
#define RHASH_STRING_KEY_P(hash, key) (!RHASH_IDENTHASH_P(hash) && (rb_obj_class(key) == rb_cString))

typedef st_index_t st_hash_t;

/*
 * RHASH_AR_TABLE_P(h):
 *   RHASH_AR_TABLE points to ar_table.
 *
 * !RHASH_AR_TABLE_P(h):
 *   RHASH_ST_TABLE points st_table.
 */

#define RHASH_AR_TABLE_MAX_BOUND     RHASH_AR_TABLE_MAX_SIZE

#define RHASH_AR_TABLE_REF(hash, n) (&RHASH_AR_TABLE(hash)->pairs[n])
#define RHASH_AR_CLEARED_HINT 0xff

static inline st_hash_t
ar_do_hash(st_data_t key)
{
    return (st_hash_t)rb_any_hash(key);
}

static inline ar_hint_t
ar_do_hash_hint(st_hash_t hash_value)
{
    return (ar_hint_t)hash_value;
}

static inline ar_hint_t
ar_hint(VALUE hash, unsigned int index)
{
    return RHASH_AR_TABLE(hash)->ar_hint.ary[index];
}

static inline void
ar_hint_set_hint(VALUE hash, unsigned int index, ar_hint_t hint)
{
    RHASH_AR_TABLE(hash)->ar_hint.ary[index] = hint;
}

static inline void
ar_hint_set(VALUE hash, unsigned int index, st_hash_t hash_value)
{
    ar_hint_set_hint(hash, index, ar_do_hash_hint(hash_value));
}

static inline void
ar_clear_entry(VALUE hash, unsigned int index)
{
    ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, index);
    pair->key = Qundef;
    ar_hint_set_hint(hash, index, RHASH_AR_CLEARED_HINT);
}

static inline int
ar_cleared_entry(VALUE hash, unsigned int index)
{
    if (ar_hint(hash, index) == RHASH_AR_CLEARED_HINT) {
        /* RHASH_AR_CLEARED_HINT is only a hint, not mean cleared entry,
         * so you need to check key == Qundef
         */
        ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, index);
        return UNDEF_P(pair->key);
    }
    else {
        return FALSE;
    }
}

static inline void
ar_set_entry(VALUE hash, unsigned int index, st_data_t key, st_data_t val, st_hash_t hash_value)
{
    ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, index);
    pair->key = key;
    pair->val = val;
    ar_hint_set(hash, index, hash_value);
}

#define RHASH_AR_TABLE_SIZE(h) (HASH_ASSERT(RHASH_AR_TABLE_P(h)), \
                                RHASH_AR_TABLE_SIZE_RAW(h))

#define RHASH_AR_TABLE_BOUND_RAW(h) \
  ((unsigned int)((RBASIC(h)->flags >> RHASH_AR_TABLE_BOUND_SHIFT) & \
                  (RHASH_AR_TABLE_BOUND_MASK >> RHASH_AR_TABLE_BOUND_SHIFT)))

#define RHASH_ST_TABLE_SET(h, s)  rb_hash_st_table_set(h, s)
#define RHASH_TYPE(hash) (RHASH_AR_TABLE_P(hash) ? &objhash : RHASH_ST_TABLE(hash)->type)

#define HASH_ASSERT(expr) RUBY_ASSERT_MESG_WHEN(HASH_DEBUG, expr, #expr)

static inline unsigned int
RHASH_AR_TABLE_BOUND(VALUE h)
{
    HASH_ASSERT(RHASH_AR_TABLE_P(h));
    const unsigned int bound = RHASH_AR_TABLE_BOUND_RAW(h);
    HASH_ASSERT(bound <= RHASH_AR_TABLE_MAX_SIZE);
    return bound;
}

#if HASH_DEBUG
#define hash_verify(hash) hash_verify_(hash, __FILE__, __LINE__)

void
rb_hash_dump(VALUE hash)
{
    rb_obj_info_dump(hash);

    if (RHASH_AR_TABLE_P(hash)) {
        unsigned i, bound = RHASH_AR_TABLE_BOUND(hash);

        fprintf(stderr, "  size:%u bound:%u\n",
                RHASH_AR_TABLE_SIZE(hash), bound);

        for (i=0; i<bound; i++) {
            st_data_t k, v;

            if (!ar_cleared_entry(hash, i)) {
                char b1[0x100], b2[0x100];
                ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
                k = pair->key;
                v = pair->val;
                fprintf(stderr, "  %d key:%s val:%s hint:%02x\n", i,
                        rb_raw_obj_info(b1, 0x100, k),
                        rb_raw_obj_info(b2, 0x100, v),
                        ar_hint(hash, i));
            }
            else {
                fprintf(stderr, "  %d empty\n", i);
            }
        }
    }
}

static VALUE
hash_verify_(VALUE hash, const char *file, int line)
{
    HASH_ASSERT(RB_TYPE_P(hash, T_HASH));

    if (RHASH_AR_TABLE_P(hash)) {
        unsigned i, n = 0, bound = RHASH_AR_TABLE_BOUND(hash);

        for (i=0; i<bound; i++) {
            st_data_t k, v;
            if (!ar_cleared_entry(hash, i)) {
                ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
                k = pair->key;
                v = pair->val;
                HASH_ASSERT(!UNDEF_P(k));
                HASH_ASSERT(!UNDEF_P(v));
                n++;
            }
        }
        if (n != RHASH_AR_TABLE_SIZE(hash)) {
            rb_bug("n:%u, RHASH_AR_TABLE_SIZE:%u", n, RHASH_AR_TABLE_SIZE(hash));
        }
    }
    else {
        HASH_ASSERT(RHASH_ST_TABLE(hash) != NULL);
        HASH_ASSERT(RHASH_AR_TABLE_SIZE_RAW(hash) == 0);
        HASH_ASSERT(RHASH_AR_TABLE_BOUND_RAW(hash) == 0);
    }

    return hash;
}

#else
#define hash_verify(h) ((void)0)
#endif

static inline int
RHASH_TABLE_EMPTY_P(VALUE hash)
{
    return RHASH_SIZE(hash) == 0;
}

#define RHASH_SET_ST_FLAG(h)          FL_SET_RAW(h, RHASH_ST_TABLE_FLAG)
#define RHASH_UNSET_ST_FLAG(h)        FL_UNSET_RAW(h, RHASH_ST_TABLE_FLAG)

static void
hash_st_table_init(VALUE hash, const struct st_hash_type *type, st_index_t size)
{
    st_init_existing_table_with_size(RHASH_ST_TABLE(hash), type, size);
    RHASH_SET_ST_FLAG(hash);
}

void
rb_hash_st_table_set(VALUE hash, st_table *st)
{
    HASH_ASSERT(st != NULL);
    RHASH_SET_ST_FLAG(hash);

    *RHASH_ST_TABLE(hash) = *st;
}

static inline void
RHASH_AR_TABLE_BOUND_SET(VALUE h, st_index_t n)
{
    HASH_ASSERT(RHASH_AR_TABLE_P(h));
    HASH_ASSERT(n <= RHASH_AR_TABLE_MAX_BOUND);

    RBASIC(h)->flags &= ~RHASH_AR_TABLE_BOUND_MASK;
    RBASIC(h)->flags |= n << RHASH_AR_TABLE_BOUND_SHIFT;
}

static inline void
RHASH_AR_TABLE_SIZE_SET(VALUE h, st_index_t n)
{
    HASH_ASSERT(RHASH_AR_TABLE_P(h));
    HASH_ASSERT(n <= RHASH_AR_TABLE_MAX_SIZE);

    RBASIC(h)->flags &= ~RHASH_AR_TABLE_SIZE_MASK;
    RBASIC(h)->flags |= n << RHASH_AR_TABLE_SIZE_SHIFT;
}

static inline void
HASH_AR_TABLE_SIZE_ADD(VALUE h, st_index_t n)
{
    HASH_ASSERT(RHASH_AR_TABLE_P(h));

    RHASH_AR_TABLE_SIZE_SET(h, RHASH_AR_TABLE_SIZE(h) + n);

    hash_verify(h);
}

#define RHASH_AR_TABLE_SIZE_INC(h) HASH_AR_TABLE_SIZE_ADD(h, 1)

static inline void
RHASH_AR_TABLE_SIZE_DEC(VALUE h)
{
    HASH_ASSERT(RHASH_AR_TABLE_P(h));
    int new_size = RHASH_AR_TABLE_SIZE(h) - 1;

    if (new_size != 0) {
        RHASH_AR_TABLE_SIZE_SET(h, new_size);
    }
    else {
        RHASH_AR_TABLE_SIZE_SET(h, 0);
        RHASH_AR_TABLE_BOUND_SET(h, 0);
    }
    hash_verify(h);
}

static inline void
RHASH_AR_TABLE_CLEAR(VALUE h)
{
    RBASIC(h)->flags &= ~RHASH_AR_TABLE_SIZE_MASK;
    RBASIC(h)->flags &= ~RHASH_AR_TABLE_BOUND_MASK;

    memset(RHASH_AR_TABLE(h), 0, sizeof(ar_table));
}

NOINLINE(static int ar_equal(VALUE x, VALUE y));

static int
ar_equal(VALUE x, VALUE y)
{
    return rb_any_cmp(x, y) == 0;
}

static unsigned
ar_find_entry_hint(VALUE hash, ar_hint_t hint, st_data_t key)
{
    unsigned i, bound = RHASH_AR_TABLE_BOUND(hash);
    const ar_hint_t *hints = RHASH_AR_TABLE(hash)->ar_hint.ary;

    /* if table is NULL, then bound also should be 0 */

    for (i = 0; i < bound; i++) {
        if (hints[i] == hint) {
            ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
            if (ar_equal(key, pair->key)) {
                RB_DEBUG_COUNTER_INC(artable_hint_hit);
                return i;
            }
            else {
#if 0
                static int pid;
                static char fname[256];
                static FILE *fp;

                if (pid != getpid()) {
                    snprintf(fname, sizeof(fname), "/tmp/ruby-armiss.%d", pid = getpid());
                    if ((fp = fopen(fname, "w")) == NULL) rb_bug("fopen");
                }

                st_hash_t h1 = ar_do_hash(key);
                st_hash_t h2 = ar_do_hash(pair->key);

                fprintf(fp, "miss: hash_eq:%d hints[%d]:%02x hint:%02x\n"
                            "      key      :%016lx %s\n"
                            "      pair->key:%016lx %s\n",
                        h1 == h2, i, hints[i], hint,
                        h1, rb_obj_info(key), h2, rb_obj_info(pair->key));
#endif
                RB_DEBUG_COUNTER_INC(artable_hint_miss);
            }
        }
    }
    RB_DEBUG_COUNTER_INC(artable_hint_notfound);
    return RHASH_AR_TABLE_MAX_BOUND;
}

static unsigned
ar_find_entry(VALUE hash, st_hash_t hash_value, st_data_t key)
{
    ar_hint_t hint = ar_do_hash_hint(hash_value);
    return ar_find_entry_hint(hash, hint, key);
}

static inline void
hash_ar_free_and_clear_table(VALUE hash)
{
    RHASH_AR_TABLE_CLEAR(hash);

    HASH_ASSERT(RHASH_AR_TABLE_SIZE(hash) == 0);
    HASH_ASSERT(RHASH_AR_TABLE_BOUND(hash) == 0);
}

void rb_st_add_direct_with_hash(st_table *tab, st_data_t key, st_data_t value, st_hash_t hash); // st.c

enum ar_each_key_type {
    ar_each_key_copy,
    ar_each_key_cmp,
    ar_each_key_insert,
};

static inline int
ar_each_key(ar_table *ar, int max, enum ar_each_key_type type, st_data_t *dst_keys, st_table *new_tab, st_hash_t *hashes)
{
    for (int i = 0; i < max; i++) {
        ar_table_pair *pair = &ar->pairs[i];

        switch (type) {
          case ar_each_key_copy:
            dst_keys[i] = pair->key;
            break;
          case ar_each_key_cmp:
            if (dst_keys[i] != pair->key) return 1;
            break;
          case ar_each_key_insert:
            if (UNDEF_P(pair->key)) continue; // deleted entry
            rb_st_add_direct_with_hash(new_tab, pair->key, pair->val, hashes[i]);
            break;
        }
    }

    return 0;
}

static st_table *
ar_force_convert_table(VALUE hash, const char *file, int line)
{
    if (RHASH_ST_TABLE_P(hash)) {
        return RHASH_ST_TABLE(hash);
    }
    else {
        ar_table *ar = RHASH_AR_TABLE(hash);
        st_hash_t hashes[RHASH_AR_TABLE_MAX_SIZE];
        unsigned int bound, size;

        // prepare hash values
        do {
            st_data_t keys[RHASH_AR_TABLE_MAX_SIZE];
            bound = RHASH_AR_TABLE_BOUND(hash);
            size = RHASH_AR_TABLE_SIZE(hash);
            ar_each_key(ar, bound, ar_each_key_copy, keys, NULL, NULL);

            for (unsigned int i = 0; i < bound; i++) {
                // do_hash calls #hash method and it can modify hash object
                hashes[i] = UNDEF_P(keys[i]) ? 0 : ar_do_hash(keys[i]);
            }

            // check if modified
            if (UNLIKELY(!RHASH_AR_TABLE_P(hash))) return RHASH_ST_TABLE(hash);
            if (UNLIKELY(RHASH_AR_TABLE_BOUND(hash) != bound)) continue;
            if (UNLIKELY(ar_each_key(ar, bound, ar_each_key_cmp, keys, NULL, NULL))) continue;
        } while (0);

        // make st
        st_table tab;
        st_table *new_tab = &tab;
        st_init_existing_table_with_size(new_tab, &objhash, size);
        ar_each_key(ar, bound, ar_each_key_insert, NULL, new_tab, hashes);
        hash_ar_free_and_clear_table(hash);
        RHASH_ST_TABLE_SET(hash, new_tab);
        return RHASH_ST_TABLE(hash);
    }
}

static int
ar_compact_table(VALUE hash)
{
    const unsigned bound = RHASH_AR_TABLE_BOUND(hash);
    const unsigned size = RHASH_AR_TABLE_SIZE(hash);

    if (size == bound) {
        return size;
    }
    else {
        unsigned i, j=0;
        ar_table_pair *pairs = RHASH_AR_TABLE(hash)->pairs;

        for (i=0; i<bound; i++) {
            if (ar_cleared_entry(hash, i)) {
                if (j <= i) j = i+1;
                for (; j<bound; j++) {
                    if (!ar_cleared_entry(hash, j)) {
                        pairs[i] = pairs[j];
                        ar_hint_set_hint(hash, i, (st_hash_t)ar_hint(hash, j));
                        ar_clear_entry(hash, j);
                        j++;
                        goto found;
                    }
                }
                /* non-empty is not found */
                goto done;
              found:;
            }
        }
      done:
        HASH_ASSERT(i<=bound);

        RHASH_AR_TABLE_BOUND_SET(hash, size);
        hash_verify(hash);
        return size;
    }
}

static int
ar_add_direct_with_hash(VALUE hash, st_data_t key, st_data_t val, st_hash_t hash_value)
{
    unsigned bin = RHASH_AR_TABLE_BOUND(hash);

    if (RHASH_AR_TABLE_SIZE(hash) >= RHASH_AR_TABLE_MAX_SIZE) {
        return 1;
    }
    else {
        if (UNLIKELY(bin >= RHASH_AR_TABLE_MAX_BOUND)) {
            bin = ar_compact_table(hash);
        }
        HASH_ASSERT(bin < RHASH_AR_TABLE_MAX_BOUND);

        ar_set_entry(hash, bin, key, val, hash_value);
        RHASH_AR_TABLE_BOUND_SET(hash, bin+1);
        RHASH_AR_TABLE_SIZE_INC(hash);
        return 0;
    }
}

static void
ensure_ar_table(VALUE hash)
{
    if (!RHASH_AR_TABLE_P(hash)) {
        rb_raise(rb_eRuntimeError, "hash representation was changed during iteration");
    }
}

static int
ar_general_foreach(VALUE hash, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg)
{
    if (RHASH_AR_TABLE_SIZE(hash) > 0) {
        unsigned i, bound = RHASH_AR_TABLE_BOUND(hash);

        for (i = 0; i < bound; i++) {
            if (ar_cleared_entry(hash, i)) continue;

            ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
            st_data_t key = (st_data_t)pair->key;
            st_data_t val = (st_data_t)pair->val;
            enum st_retval retval = (*func)(key, val, arg, 0);
            ensure_ar_table(hash);
            /* pair may be not valid here because of theap */

            switch (retval) {
              case ST_CONTINUE:
                break;
              case ST_CHECK:
              case ST_STOP:
                return 0;
              case ST_REPLACE:
                if (replace) {
                    retval = (*replace)(&key, &val, arg, TRUE);

                    // TODO: pair should be same as pair before.
                    pair = RHASH_AR_TABLE_REF(hash, i);
                    pair->key = (VALUE)key;
                    pair->val = (VALUE)val;
                }
                break;
              case ST_DELETE:
                ar_clear_entry(hash, i);
                RHASH_AR_TABLE_SIZE_DEC(hash);
                break;
            }
        }
    }
    return 0;
}

static int
ar_foreach_with_replace(VALUE hash, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg)
{
    return ar_general_foreach(hash, func, replace, arg);
}

struct functor {
    st_foreach_callback_func *func;
    st_data_t arg;
};

static int
apply_functor(st_data_t k, st_data_t v, st_data_t d, int _)
{
    const struct functor *f = (void *)d;
    return f->func(k, v, f->arg);
}

static int
ar_foreach(VALUE hash, st_foreach_callback_func *func, st_data_t arg)
{
    const struct functor f = { func, arg };
    return ar_general_foreach(hash, apply_functor, NULL, (st_data_t)&f);
}

static int
ar_foreach_check(VALUE hash, st_foreach_check_callback_func *func, st_data_t arg,
                 st_data_t never)
{
    if (RHASH_AR_TABLE_SIZE(hash) > 0) {
        unsigned i, ret = 0, bound = RHASH_AR_TABLE_BOUND(hash);
        enum st_retval retval;
        st_data_t key;
        ar_table_pair *pair;
        ar_hint_t hint;

        for (i = 0; i < bound; i++) {
            if (ar_cleared_entry(hash, i)) continue;

            pair = RHASH_AR_TABLE_REF(hash, i);
            key = pair->key;
            hint = ar_hint(hash, i);

            retval = (*func)(key, pair->val, arg, 0);
            ensure_ar_table(hash);
            hash_verify(hash);

            switch (retval) {
              case ST_CHECK: {
                pair = RHASH_AR_TABLE_REF(hash, i);
                if (pair->key == never) break;
                ret = ar_find_entry_hint(hash, hint, key);
                if (ret == RHASH_AR_TABLE_MAX_BOUND) {
                    retval = (*func)(0, 0, arg, 1);
                    return 2;
                }
              }
              case ST_CONTINUE:
                break;
              case ST_STOP:
              case ST_REPLACE:
                return 0;
              case ST_DELETE: {
                if (!ar_cleared_entry(hash, i)) {
                    ar_clear_entry(hash, i);
                    RHASH_AR_TABLE_SIZE_DEC(hash);
                }
                break;
              }
            }
        }
    }
    return 0;
}

static int
ar_update(VALUE hash, st_data_t key,
              st_update_callback_func *func, st_data_t arg)
{
    int retval, existing;
    unsigned bin = RHASH_AR_TABLE_MAX_BOUND;
    st_data_t value = 0, old_key;
    st_hash_t hash_value = ar_do_hash(key);

    if (UNLIKELY(!RHASH_AR_TABLE_P(hash))) {
        // `#hash` changes ar_table -> st_table
        return -1;
    }

    if (RHASH_AR_TABLE_SIZE(hash) > 0) {
        bin = ar_find_entry(hash, hash_value, key);
        existing = (bin != RHASH_AR_TABLE_MAX_BOUND) ? TRUE : FALSE;
    }
    else {
        existing = FALSE;
    }

    if (existing) {
        ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, bin);
        key = pair->key;
        value = pair->val;
    }
    old_key = key;
    retval = (*func)(&key, &value, arg, existing);
    /* pair can be invalid here because of theap */
    ensure_ar_table(hash);

    switch (retval) {
      case ST_CONTINUE:
        if (!existing) {
            if (ar_add_direct_with_hash(hash, key, value, hash_value)) {
                return -1;
            }
        }
        else {
            ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, bin);
            if (old_key != key) {
                pair->key = key;
            }
            pair->val = value;
        }
        break;
      case ST_DELETE:
        if (existing) {
            ar_clear_entry(hash, bin);
            RHASH_AR_TABLE_SIZE_DEC(hash);
        }
        break;
    }
    return existing;
}

static int
ar_insert(VALUE hash, st_data_t key, st_data_t value)
{
    unsigned bin = RHASH_AR_TABLE_BOUND(hash);
    st_hash_t hash_value = ar_do_hash(key);

    if (UNLIKELY(!RHASH_AR_TABLE_P(hash))) {
        // `#hash` changes ar_table -> st_table
        return -1;
    }

    bin = ar_find_entry(hash, hash_value, key);
    if (bin == RHASH_AR_TABLE_MAX_BOUND) {
        if (RHASH_AR_TABLE_SIZE(hash) >= RHASH_AR_TABLE_MAX_SIZE) {
            return -1;
        }
        else if (bin >= RHASH_AR_TABLE_MAX_BOUND) {
            bin = ar_compact_table(hash);
        }
        HASH_ASSERT(bin < RHASH_AR_TABLE_MAX_BOUND);

        ar_set_entry(hash, bin, key, value, hash_value);
        RHASH_AR_TABLE_BOUND_SET(hash, bin+1);
        RHASH_AR_TABLE_SIZE_INC(hash);
        return 0;
    }
    else {
        RHASH_AR_TABLE_REF(hash, bin)->val = value;
        return 1;
    }
}

static int
ar_lookup(VALUE hash, st_data_t key, st_data_t *value)
{
    if (RHASH_AR_TABLE_SIZE(hash) == 0) {
        return 0;
    }
    else {
        st_hash_t hash_value = ar_do_hash(key);
        if (UNLIKELY(!RHASH_AR_TABLE_P(hash))) {
            // `#hash` changes ar_table -> st_table
            return st_lookup(RHASH_ST_TABLE(hash), key, value);
        }
        unsigned bin = ar_find_entry(hash, hash_value, key);

        if (bin == RHASH_AR_TABLE_MAX_BOUND) {
            return 0;
        }
        else {
            HASH_ASSERT(bin < RHASH_AR_TABLE_MAX_BOUND);
            if (value != NULL) {
                *value = RHASH_AR_TABLE_REF(hash, bin)->val;
            }
            return 1;
        }
    }
}

static int
ar_delete(VALUE hash, st_data_t *key, st_data_t *value)
{
    unsigned bin;
    st_hash_t hash_value = ar_do_hash(*key);

    if (UNLIKELY(!RHASH_AR_TABLE_P(hash))) {
        // `#hash` changes ar_table -> st_table
        return st_delete(RHASH_ST_TABLE(hash), key, value);
    }

    bin = ar_find_entry(hash, hash_value, *key);

    if (bin == RHASH_AR_TABLE_MAX_BOUND) {
        if (value != 0) *value = 0;
        return 0;
    }
    else {
        if (value != 0) {
            ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, bin);
            *value = pair->val;
        }
        ar_clear_entry(hash, bin);
        RHASH_AR_TABLE_SIZE_DEC(hash);
        return 1;
    }
}

static int
ar_shift(VALUE hash, st_data_t *key, st_data_t *value)
{
    if (RHASH_AR_TABLE_SIZE(hash) > 0) {
        unsigned i, bound = RHASH_AR_TABLE_BOUND(hash);

        for (i = 0; i < bound; i++) {
            if (!ar_cleared_entry(hash, i)) {
                ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
                if (value != 0) *value = pair->val;
                *key = pair->key;
                ar_clear_entry(hash, i);
                RHASH_AR_TABLE_SIZE_DEC(hash);
                return 1;
            }
        }
    }
    if (value != NULL) *value = 0;
    return 0;
}

static long
ar_keys(VALUE hash, st_data_t *keys, st_index_t size)
{
    unsigned i, bound = RHASH_AR_TABLE_BOUND(hash);
    st_data_t *keys_start = keys, *keys_end = keys + size;

    for (i = 0; i < bound; i++) {
        if (keys == keys_end) {
          break;
        }
        else {
            if (!ar_cleared_entry(hash, i)) {
                *keys++ = RHASH_AR_TABLE_REF(hash, i)->key;
            }
        }
    }

    return keys - keys_start;
}

static long
ar_values(VALUE hash, st_data_t *values, st_index_t size)
{
    unsigned i, bound = RHASH_AR_TABLE_BOUND(hash);
    st_data_t *values_start = values, *values_end = values + size;

    for (i = 0; i < bound; i++) {
        if (values == values_end) {
          break;
        }
        else {
            if (!ar_cleared_entry(hash, i)) {
                *values++ = RHASH_AR_TABLE_REF(hash, i)->val;
            }
        }
    }

    return values - values_start;
}

static ar_table*
ar_copy(VALUE hash1, VALUE hash2)
{
    ar_table *old_tab = RHASH_AR_TABLE(hash2);
    ar_table *new_tab = RHASH_AR_TABLE(hash1);

    *new_tab = *old_tab;
    RHASH_AR_TABLE(hash1)->ar_hint.word = RHASH_AR_TABLE(hash2)->ar_hint.word;
    RHASH_AR_TABLE_BOUND_SET(hash1, RHASH_AR_TABLE_BOUND(hash2));
    RHASH_AR_TABLE_SIZE_SET(hash1, RHASH_AR_TABLE_SIZE(hash2));

    rb_gc_writebarrier_remember(hash1);

    return new_tab;
}

static void
ar_clear(VALUE hash)
{
    if (RHASH_AR_TABLE(hash) != NULL) {
        RHASH_AR_TABLE_SIZE_SET(hash, 0);
        RHASH_AR_TABLE_BOUND_SET(hash, 0);
    }
    else {
        HASH_ASSERT(RHASH_AR_TABLE_SIZE(hash) == 0);
        HASH_ASSERT(RHASH_AR_TABLE_BOUND(hash) == 0);
    }
}

static void
hash_st_free(VALUE hash)
{
    HASH_ASSERT(RHASH_ST_TABLE_P(hash));

    st_table *tab = RHASH_ST_TABLE(hash);

    xfree(tab->bins);
    xfree(tab->entries);
}

static void
hash_st_free_and_clear_table(VALUE hash)
{
    hash_st_free(hash);

    RHASH_ST_CLEAR(hash);
}

void
rb_hash_free(VALUE hash)
{
    if (RHASH_ST_TABLE_P(hash)) {
        hash_st_free(hash);
    }
}

typedef int st_foreach_func(st_data_t, st_data_t, st_data_t);

struct foreach_safe_arg {
    st_table *tbl;
    st_foreach_func *func;
    st_data_t arg;
};

static int
foreach_safe_i(st_data_t key, st_data_t value, st_data_t args, int error)
{
    int status;
    struct foreach_safe_arg *arg = (void *)args;

    if (error) return ST_STOP;
    status = (*arg->func)(key, value, arg->arg);
    if (status == ST_CONTINUE) {
        return ST_CHECK;
    }
    return status;
}

void
st_foreach_safe(st_table *table, st_foreach_func *func, st_data_t a)
{
    struct foreach_safe_arg arg;

    arg.tbl = table;
    arg.func = (st_foreach_func *)func;
    arg.arg = a;
    if (st_foreach_check(table, foreach_safe_i, (st_data_t)&arg, 0)) {
        rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

typedef int rb_foreach_func(VALUE, VALUE, VALUE);

struct hash_foreach_arg {
    VALUE hash;
    rb_foreach_func *func;
    VALUE arg;
};

static int
hash_iter_status_check(int status)
{
    switch (status) {
      case ST_DELETE:
        return ST_DELETE;
      case ST_CONTINUE:
        break;
      case ST_STOP:
        return ST_STOP;
    }

    return ST_CHECK;
}

static int
hash_ar_foreach_iter(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    struct hash_foreach_arg *arg = (struct hash_foreach_arg *)argp;

    if (error) return ST_STOP;

    int status = (*arg->func)((VALUE)key, (VALUE)value, arg->arg);
    /* TODO: rehash check? rb_raise(rb_eRuntimeError, "rehash occurred during iteration"); */

    return hash_iter_status_check(status);
}

static int
hash_foreach_iter(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    struct hash_foreach_arg *arg = (struct hash_foreach_arg *)argp;

    if (error) return ST_STOP;

    st_table *tbl = RHASH_ST_TABLE(arg->hash);
    int status = (*arg->func)((VALUE)key, (VALUE)value, arg->arg);

    if (RHASH_ST_TABLE(arg->hash) != tbl) {
        rb_raise(rb_eRuntimeError, "rehash occurred during iteration");
    }

    return hash_iter_status_check(status);
}

static unsigned long
iter_lev_in_ivar(VALUE hash)
{
    VALUE levval = rb_ivar_get(hash, id_hash_iter_lev);
    HASH_ASSERT(FIXNUM_P(levval));
    long lev = FIX2LONG(levval);
    HASH_ASSERT(lev >= 0);
    return (unsigned long)lev;
}

void rb_ivar_set_internal(VALUE obj, ID id, VALUE val);

static void
iter_lev_in_ivar_set(VALUE hash, unsigned long lev)
{
    HASH_ASSERT(lev >= RHASH_LEV_MAX);
    HASH_ASSERT(POSFIXABLE(lev)); /* POSFIXABLE means fitting to long */
    rb_ivar_set_internal(hash, id_hash_iter_lev, LONG2FIX((long)lev));
}

static inline unsigned long
iter_lev_in_flags(VALUE hash)
{
    return (unsigned long)((RBASIC(hash)->flags >> RHASH_LEV_SHIFT) & RHASH_LEV_MAX);
}

static inline void
iter_lev_in_flags_set(VALUE hash, unsigned long lev)
{
    HASH_ASSERT(lev <= RHASH_LEV_MAX);
    RBASIC(hash)->flags = ((RBASIC(hash)->flags & ~RHASH_LEV_MASK) | ((VALUE)lev << RHASH_LEV_SHIFT));
}

static inline bool
hash_iterating_p(VALUE hash)
{
    return iter_lev_in_flags(hash) > 0;
}

static void
hash_iter_lev_inc(VALUE hash)
{
    unsigned long lev = iter_lev_in_flags(hash);
    if (lev == RHASH_LEV_MAX) {
        lev = iter_lev_in_ivar(hash) + 1;
        if (!POSFIXABLE(lev)) { /* paranoiac check */
            rb_raise(rb_eRuntimeError, "too much nested iterations");
        }
    }
    else {
        lev += 1;
        iter_lev_in_flags_set(hash, lev);
        if (lev < RHASH_LEV_MAX) return;
    }
    iter_lev_in_ivar_set(hash, lev);
}

static void
hash_iter_lev_dec(VALUE hash)
{
    unsigned long lev = iter_lev_in_flags(hash);
    if (lev == RHASH_LEV_MAX) {
        lev = iter_lev_in_ivar(hash);
        if (lev > RHASH_LEV_MAX) {
            iter_lev_in_ivar_set(hash, lev-1);
            return;
        }
        rb_attr_delete(hash, id_hash_iter_lev);
    }
    else if (lev == 0) {
        rb_raise(rb_eRuntimeError, "iteration level underflow");
    }
    iter_lev_in_flags_set(hash, lev - 1);
}

static VALUE
hash_foreach_ensure(VALUE hash)
{
    hash_iter_lev_dec(hash);
    return 0;
}

int
rb_hash_stlike_foreach(VALUE hash, st_foreach_callback_func *func, st_data_t arg)
{
    if (RHASH_AR_TABLE_P(hash)) {
        return ar_foreach(hash, func, arg);
    }
    else {
        return st_foreach(RHASH_ST_TABLE(hash), func, arg);
    }
}

int
rb_hash_stlike_foreach_with_replace(VALUE hash, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg)
{
    if (RHASH_AR_TABLE_P(hash)) {
        return ar_foreach_with_replace(hash, func, replace, arg);
    }
    else {
        return st_foreach_with_replace(RHASH_ST_TABLE(hash), func, replace, arg);
    }
}

static VALUE
hash_foreach_call(VALUE arg)
{
    VALUE hash = ((struct hash_foreach_arg *)arg)->hash;
    int ret = 0;
    if (RHASH_AR_TABLE_P(hash)) {
        ret = ar_foreach_check(hash, hash_ar_foreach_iter,
                                   (st_data_t)arg, (st_data_t)Qundef);
    }
    else if (RHASH_ST_TABLE_P(hash)) {
        ret = st_foreach_check(RHASH_ST_TABLE(hash), hash_foreach_iter,
                               (st_data_t)arg, (st_data_t)Qundef);
    }
    if (ret) {
        rb_raise(rb_eRuntimeError, "ret: %d, hash modified during iteration", ret);
    }
    return Qnil;
}

void
rb_hash_foreach(VALUE hash, rb_foreach_func *func, VALUE farg)
{
    struct hash_foreach_arg arg;

    if (RHASH_TABLE_EMPTY_P(hash))
        return;
    arg.hash = hash;
    arg.func = (rb_foreach_func *)func;
    arg.arg  = farg;
    if (RB_OBJ_FROZEN(hash)) {
        hash_foreach_call((VALUE)&arg);
    }
    else {
        hash_iter_lev_inc(hash);
        rb_ensure(hash_foreach_call, (VALUE)&arg, hash_foreach_ensure, hash);
    }
    hash_verify(hash);
}

void rb_st_compact_table(st_table *tab);

static void
compact_after_delete(VALUE hash)
{
    if (!hash_iterating_p(hash) && RHASH_ST_TABLE_P(hash)) {
        rb_st_compact_table(RHASH_ST_TABLE(hash));
    }
}

static VALUE
hash_alloc_flags(VALUE klass, VALUE flags, VALUE ifnone, bool st)
{
    const VALUE wb = (RGENGC_WB_PROTECTED_HASH ? FL_WB_PROTECTED : 0);
    const size_t size = sizeof(struct RHash) + (st ? sizeof(st_table) : sizeof(ar_table));

    NEWOBJ_OF(hash, struct RHash, klass, T_HASH | wb | flags, size, 0);

    RHASH_SET_IFNONE((VALUE)hash, ifnone);

    return (VALUE)hash;
}

static VALUE
hash_alloc(VALUE klass)
{
    /* Allocate to be able to fit both st_table and ar_table. */
    return hash_alloc_flags(klass, 0, Qnil, sizeof(st_table) > sizeof(ar_table));
}

static VALUE
empty_hash_alloc(VALUE klass)
{
    RUBY_DTRACE_CREATE_HOOK(HASH, 0);

    return hash_alloc(klass);
}

VALUE
rb_hash_new(void)
{
    return hash_alloc(rb_cHash);
}

static VALUE
copy_compare_by_id(VALUE hash, VALUE basis)
{
    if (rb_hash_compare_by_id_p(basis)) {
        return rb_hash_compare_by_id(hash);
    }
    return hash;
}

VALUE
rb_hash_new_with_size(st_index_t size)
{
    bool st = size > RHASH_AR_TABLE_MAX_SIZE;
    VALUE ret = hash_alloc_flags(rb_cHash, 0, Qnil, st);

    if (st) {
        hash_st_table_init(ret, &objhash, size);
    }

    return ret;
}

VALUE
rb_hash_new_capa(long capa)
{
    return rb_hash_new_with_size((st_index_t)capa);
}

static VALUE
hash_copy(VALUE ret, VALUE hash)
{
    if (RHASH_AR_TABLE_P(hash)) {
        if (RHASH_AR_TABLE_P(ret)) {
            ar_copy(ret, hash);
        }
        else {
            st_table *tab = RHASH_ST_TABLE(ret);
            st_init_existing_table_with_size(tab, &objhash, RHASH_AR_TABLE_SIZE(hash));

            int bound = RHASH_AR_TABLE_BOUND(hash);
            for (int i = 0; i < bound; i++) {
                if (ar_cleared_entry(hash, i)) continue;

                ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
                st_add_direct(tab, pair->key, pair->val);
                RB_OBJ_WRITTEN(ret, Qundef, pair->key);
                RB_OBJ_WRITTEN(ret, Qundef, pair->val);
            }
        }
    }
    else {
        HASH_ASSERT(sizeof(st_table) <= sizeof(ar_table));

        RHASH_SET_ST_FLAG(ret);
        st_replace(RHASH_ST_TABLE(ret), RHASH_ST_TABLE(hash));

        rb_gc_writebarrier_remember(ret);
    }
    return ret;
}

static VALUE
hash_dup_with_compare_by_id(VALUE hash)
{
    VALUE dup = hash_alloc_flags(rb_cHash, 0, Qnil, RHASH_ST_TABLE_P(hash));
    if (RHASH_ST_TABLE_P(hash)) {
        RHASH_SET_ST_FLAG(dup);
    }
    else {
        RHASH_UNSET_ST_FLAG(dup);
    }

    return hash_copy(dup, hash);
}

static VALUE
hash_dup(VALUE hash, VALUE klass, VALUE flags)
{
    return hash_copy(hash_alloc_flags(klass, flags, RHASH_IFNONE(hash), !RHASH_EMPTY_P(hash) && RHASH_ST_TABLE_P(hash)),
                     hash);
}

VALUE
rb_hash_dup(VALUE hash)
{
    const VALUE flags = RBASIC(hash)->flags;
    VALUE ret = hash_dup(hash, rb_obj_class(hash),
                         flags & (FL_EXIVAR|RHASH_PROC_DEFAULT));
    if (flags & FL_EXIVAR)
        rb_copy_generic_ivar(ret, hash);
    return ret;
}

VALUE
rb_hash_resurrect(VALUE hash)
{
    VALUE ret = hash_dup(hash, rb_cHash, 0);
    return ret;
}

static void
rb_hash_modify_check(VALUE hash)
{
    rb_check_frozen(hash);
}

struct st_table *
rb_hash_tbl_raw(VALUE hash, const char *file, int line)
{
    return ar_force_convert_table(hash, file, line);
}

struct st_table *
rb_hash_tbl(VALUE hash, const char *file, int line)
{
    OBJ_WB_UNPROTECT(hash);
    return rb_hash_tbl_raw(hash, file, line);
}

static void
rb_hash_modify(VALUE hash)
{
    rb_hash_modify_check(hash);
}

NORETURN(static void no_new_key(void));
static void
no_new_key(void)
{
    rb_raise(rb_eRuntimeError, "can't add a new key into hash during iteration");
}

struct update_callback_arg {
    VALUE hash;
    st_data_t arg;
};

#define NOINSERT_UPDATE_CALLBACK(func)                                       \
static int                                                                   \
func##_noinsert(st_data_t *key, st_data_t *val, st_data_t arg, int existing) \
{                                                                            \
    if (!existing) no_new_key();                                             \
    return func(key, val, (struct update_arg *)arg, existing);               \
}                                                                            \
                                                                             \
static int                                                                   \
func##_insert(st_data_t *key, st_data_t *val, st_data_t arg, int existing)   \
{                                                                            \
    return func(key, val, (struct update_arg *)arg, existing);               \
}

struct update_arg {
    st_data_t arg;
    st_update_callback_func *func;
    VALUE hash;
    VALUE key;
    VALUE value;
};

typedef int (*tbl_update_func)(st_data_t *, st_data_t *, st_data_t, int);

int
rb_hash_stlike_update(VALUE hash, st_data_t key, st_update_callback_func *func, st_data_t arg)
{
    if (RHASH_AR_TABLE_P(hash)) {
        int result = ar_update(hash, key, func, arg);
        if (result == -1) {
            ar_force_convert_table(hash, __FILE__, __LINE__);
        }
        else {
            return result;
        }
    }

    return st_update(RHASH_ST_TABLE(hash), key, func, arg);
}

static int
tbl_update_modify(st_data_t *key, st_data_t *val, st_data_t arg, int existing)
{
    struct update_arg *p = (struct update_arg *)arg;
    st_data_t old_key = *key;
    st_data_t old_value = *val;
    VALUE hash = p->hash;
    int ret = (p->func)(key, val, arg, existing);
    switch (ret) {
      default:
        break;
      case ST_CONTINUE:
        if (!existing || *key != old_key || *val != old_value) {
            rb_hash_modify(hash);
            p->key = *key;
            p->value = *val;
        }
        break;
      case ST_DELETE:
        if (existing)
            rb_hash_modify(hash);
        break;
    }

    return ret;
}

static int
tbl_update(VALUE hash, VALUE key, tbl_update_func func, st_data_t optional_arg)
{
    struct update_arg arg = {
        .arg = optional_arg,
        .func = func,
        .hash = hash,
        .key  = key,
        .value = (VALUE)optional_arg,
    };

    int ret = rb_hash_stlike_update(hash, key, tbl_update_modify, (st_data_t)&arg);

    /* write barrier */
    RB_OBJ_WRITTEN(hash, Qundef, arg.key);
    RB_OBJ_WRITTEN(hash, Qundef, arg.value);

    return ret;
}

#define UPDATE_CALLBACK(iter_p, func) ((iter_p) ? func##_noinsert : func##_insert)

#define RHASH_UPDATE_ITER(h, iter_p, key, func, a) do { \
    tbl_update((h), (key), UPDATE_CALLBACK(iter_p, func), (st_data_t)(a)); \
} while (0)

#define RHASH_UPDATE(hash, key, func, arg) \
    RHASH_UPDATE_ITER(hash, hash_iterating_p(hash), key, func, arg)

static void
set_proc_default(VALUE hash, VALUE proc)
{
    if (rb_proc_lambda_p(proc)) {
        int n = rb_proc_arity(proc);

        if (n != 2 && (n >= 0 || n < -3)) {
            if (n < 0) n = -n-1;
            rb_raise(rb_eTypeError, "default_proc takes two arguments (2 for %d)", n);
        }
    }

    FL_SET_RAW(hash, RHASH_PROC_DEFAULT);
    RHASH_SET_IFNONE(hash, proc);
}

static VALUE
rb_hash_init(rb_execution_context_t *ec, VALUE hash, VALUE capa_value, VALUE ifnone_unset, VALUE ifnone, VALUE block)
{
    rb_hash_modify(hash);

    if (capa_value != INT2FIX(0)) {
        long capa = NUM2LONG(capa_value);
        if (capa > 0 && RHASH_SIZE(hash) == 0 && RHASH_AR_TABLE_P(hash)) {
            hash_st_table_init(hash, &objhash, capa);
        }
    }

    if (!NIL_P(block)) {
        if (ifnone_unset != Qtrue) {
            rb_check_arity(1, 0, 0);
        }
        else {
            SET_PROC_DEFAULT(hash, block);
        }
    }
    else {
        RHASH_SET_IFNONE(hash, ifnone_unset == Qtrue ? Qnil : ifnone);
    }

    hash_verify(hash);
    return hash;
}

static VALUE rb_hash_to_a(VALUE hash);

/*
 *  call-seq:
 *    Hash[] -> new_empty_hash
 *    Hash[hash] -> new_hash
 *    Hash[ [*2_element_arrays] ] -> new_hash
 *    Hash[*objects] -> new_hash
 *
 *  Returns a new +Hash+ object populated with the given objects, if any.
 *  See Hash::new.
 *
 *  With no argument, returns a new empty +Hash+.
 *
 *  When the single given argument is a +Hash+, returns a new +Hash+
 *  populated with the entries from the given +Hash+, excluding the
 *  default value or proc.
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    Hash[h] # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  When the single given argument is an Array of 2-element Arrays,
 *  returns a new +Hash+ object wherein each 2-element array forms a
 *  key-value entry:
 *
 *    Hash[ [ [:foo, 0], [:bar, 1] ] ] # => {:foo=>0, :bar=>1}
 *
 *  When the argument count is an even number;
 *  returns a new +Hash+ object wherein each successive pair of arguments
 *  has become a key-value entry:
 *
 *    Hash[:foo, 0, :bar, 1] # => {:foo=>0, :bar=>1}
 *
 *  Raises an exception if the argument list does not conform to any
 *  of the above.
 */

static VALUE
rb_hash_s_create(int argc, VALUE *argv, VALUE klass)
{
    VALUE hash, tmp;

    if (argc == 1) {
        tmp = rb_hash_s_try_convert(Qnil, argv[0]);
        if (!NIL_P(tmp)) {
            if (!RHASH_EMPTY_P(tmp)  && rb_hash_compare_by_id_p(tmp)) {
                /* hash_copy for non-empty hash will copy compare_by_identity
                   flag, but we don't want it copied. Work around by
                   converting hash to flattened array and using that. */
                tmp = rb_hash_to_a(tmp);
            }
            else {
                hash = hash_alloc(klass);
                if (!RHASH_EMPTY_P(tmp))
                    hash_copy(hash, tmp);
                return hash;
            }
        }
        else {
            tmp = rb_check_array_type(argv[0]);
        }

        if (!NIL_P(tmp)) {
            long i;

            hash = hash_alloc(klass);
            for (i = 0; i < RARRAY_LEN(tmp); ++i) {
                VALUE e = RARRAY_AREF(tmp, i);
                VALUE v = rb_check_array_type(e);
                VALUE key, val = Qnil;

                if (NIL_P(v)) {
                    rb_raise(rb_eArgError, "wrong element type %s at %ld (expected array)",
                             rb_builtin_class_name(e), i);
                }
                switch (RARRAY_LEN(v)) {
                  default:
                    rb_raise(rb_eArgError, "invalid number of elements (%ld for 1..2)",
                             RARRAY_LEN(v));
                  case 2:
                    val = RARRAY_AREF(v, 1);
                  case 1:
                    key = RARRAY_AREF(v, 0);
                    rb_hash_aset(hash, key, val);
                }
            }
            return hash;
        }
    }
    if (argc % 2 != 0) {
        rb_raise(rb_eArgError, "odd number of arguments for Hash");
    }

    hash = hash_alloc(klass);
    rb_hash_bulk_insert(argc, argv, hash);
    hash_verify(hash);
    return hash;
}

VALUE
rb_to_hash_type(VALUE hash)
{
    return rb_convert_type_with_id(hash, T_HASH, "Hash", idTo_hash);
}
#define to_hash rb_to_hash_type

VALUE
rb_check_hash_type(VALUE hash)
{
    return rb_check_convert_type_with_id(hash, T_HASH, "Hash", idTo_hash);
}

/*
 *  call-seq:
 *    Hash.try_convert(obj) -> obj, new_hash, or nil
 *
 *  If +obj+ is a +Hash+ object, returns +obj+.
 *
 *  Otherwise if +obj+ responds to <tt>:to_hash</tt>,
 *  calls <tt>obj.to_hash</tt> and returns the result.
 *
 *  Returns +nil+ if +obj+ does not respond to <tt>:to_hash</tt>
 *
 *  Raises an exception unless <tt>obj.to_hash</tt> returns a +Hash+ object.
 */
static VALUE
rb_hash_s_try_convert(VALUE dummy, VALUE hash)
{
    return rb_check_hash_type(hash);
}

/*
 *  call-seq:
 *     Hash.ruby2_keywords_hash?(hash) -> true or false
 *
 *  Checks if a given hash is flagged by Module#ruby2_keywords (or
 *  Proc#ruby2_keywords).
 *  This method is not for casual use; debugging, researching, and
 *  some truly necessary cases like serialization of arguments.
 *
 *     ruby2_keywords def foo(*args)
 *       Hash.ruby2_keywords_hash?(args.last)
 *     end
 *     foo(k: 1)   #=> true
 *     foo({k: 1}) #=> false
 */
static VALUE
rb_hash_s_ruby2_keywords_hash_p(VALUE dummy, VALUE hash)
{
    Check_Type(hash, T_HASH);
    return RBOOL(RHASH(hash)->basic.flags & RHASH_PASS_AS_KEYWORDS);
}

/*
 *  call-seq:
 *     Hash.ruby2_keywords_hash(hash) -> hash
 *
 *  Duplicates a given hash and adds a ruby2_keywords flag.
 *  This method is not for casual use; debugging, researching, and
 *  some truly necessary cases like deserialization of arguments.
 *
 *     h = {k: 1}
 *     h = Hash.ruby2_keywords_hash(h)
 *     def foo(k: 42)
 *       k
 *     end
 *     foo(*[h]) #=> 1 with neither a warning or an error
 */
static VALUE
rb_hash_s_ruby2_keywords_hash(VALUE dummy, VALUE hash)
{
    Check_Type(hash, T_HASH);
    VALUE tmp = rb_hash_dup(hash);
    if (RHASH_EMPTY_P(hash) && rb_hash_compare_by_id_p(hash)) {
        rb_hash_compare_by_id(tmp);
    }
    RHASH(tmp)->basic.flags |= RHASH_PASS_AS_KEYWORDS;
    return tmp;
}

struct rehash_arg {
    VALUE hash;
    st_table *tbl;
};

static int
rb_hash_rehash_i(VALUE key, VALUE value, VALUE arg)
{
    if (RHASH_AR_TABLE_P(arg)) {
        ar_insert(arg, (st_data_t)key, (st_data_t)value);
    }
    else {
        st_insert(RHASH_ST_TABLE(arg), (st_data_t)key, (st_data_t)value);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hash.rehash -> self
 *
 *  Rebuilds the hash table by recomputing the hash index for each key;
 *  returns <tt>self</tt>.
 *
 *  The hash table becomes invalid if the hash value of a key
 *  has changed after the entry was created.
 *  See {Modifying an Active Hash Key}[rdoc-ref:Hash@Modifying+an+Active+Hash+Key].
 */

VALUE
rb_hash_rehash(VALUE hash)
{
    VALUE tmp;
    st_table *tbl;

    if (hash_iterating_p(hash)) {
        rb_raise(rb_eRuntimeError, "rehash during iteration");
    }
    rb_hash_modify_check(hash);
    if (RHASH_AR_TABLE_P(hash)) {
        tmp = hash_alloc(0);
        rb_hash_foreach(hash, rb_hash_rehash_i, (VALUE)tmp);

        hash_ar_free_and_clear_table(hash);
        ar_copy(hash, tmp);
    }
    else if (RHASH_ST_TABLE_P(hash)) {
        st_table *old_tab = RHASH_ST_TABLE(hash);
        tmp = hash_alloc(0);

        hash_st_table_init(tmp, old_tab->type, old_tab->num_entries);
        tbl = RHASH_ST_TABLE(tmp);

        rb_hash_foreach(hash, rb_hash_rehash_i, (VALUE)tmp);

        hash_st_free(hash);
        RHASH_ST_TABLE_SET(hash, tbl);
        RHASH_ST_CLEAR(tmp);
    }
    hash_verify(hash);
    return hash;
}

static VALUE
call_default_proc(VALUE proc, VALUE hash, VALUE key)
{
    VALUE args[2] = {hash, key};
    return rb_proc_call_with_block(proc, 2, args, Qnil);
}

static bool
rb_hash_default_unredefined(VALUE hash)
{
    VALUE klass = RBASIC_CLASS(hash);
    if (LIKELY(klass == rb_cHash)) {
        return !!BASIC_OP_UNREDEFINED_P(BOP_DEFAULT, HASH_REDEFINED_OP_FLAG);
    }
    else {
        return LIKELY(rb_method_basic_definition_p(klass, id_default));
    }
}

VALUE
rb_hash_default_value(VALUE hash, VALUE key)
{
    RUBY_ASSERT(RB_TYPE_P(hash, T_HASH));

    if (LIKELY(rb_hash_default_unredefined(hash))) {
        VALUE ifnone = RHASH_IFNONE(hash);
        if (LIKELY(!FL_TEST_RAW(hash, RHASH_PROC_DEFAULT))) return ifnone;
        if (UNDEF_P(key)) return Qnil;
        return call_default_proc(ifnone, hash, key);
    }
    else {
        return rb_funcall(hash, id_default, 1, key);
    }
}

static inline int
hash_stlike_lookup(VALUE hash, st_data_t key, st_data_t *pval)
{
    hash_verify(hash);

    if (RHASH_AR_TABLE_P(hash)) {
        return ar_lookup(hash, key, pval);
    }
    else {
        extern st_index_t rb_iseq_cdhash_hash(VALUE);
        RUBY_ASSERT(RHASH_ST_TABLE(hash)->type->hash == rb_any_hash ||
                    RHASH_ST_TABLE(hash)->type->hash == rb_ident_hash ||
                    RHASH_ST_TABLE(hash)->type->hash == rb_iseq_cdhash_hash);
        return st_lookup(RHASH_ST_TABLE(hash), key, pval);
    }
}

int
rb_hash_stlike_lookup(VALUE hash, st_data_t key, st_data_t *pval)
{
    return hash_stlike_lookup(hash, key, pval);
}

/*
 *  call-seq:
 *    hash[key] -> value
 *
 *  Returns the value associated with the given +key+, if found:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:foo] # => 0
 *
 *  If +key+ is not found, returns a default value
 *  (see {Default Values}[rdoc-ref:Hash@Default+Values]):
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:nosuch] # => nil
 */

VALUE
rb_hash_aref(VALUE hash, VALUE key)
{
    st_data_t val;

    if (hash_stlike_lookup(hash, key, &val)) {
        return (VALUE)val;
    }
    else {
        return rb_hash_default_value(hash, key);
    }
}

VALUE
rb_hash_lookup2(VALUE hash, VALUE key, VALUE def)
{
    st_data_t val;

    if (hash_stlike_lookup(hash, key, &val)) {
        return (VALUE)val;
    }
    else {
        return def; /* without Hash#default */
    }
}

VALUE
rb_hash_lookup(VALUE hash, VALUE key)
{
    return rb_hash_lookup2(hash, key, Qnil);
}

/*
 *  call-seq:
 *    hash.fetch(key) -> object
 *    hash.fetch(key, default_value) -> object
 *    hash.fetch(key) {|key| ... } -> object
 *
 *  Returns the value for the given +key+, if found.
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.fetch(:bar) # => 1
 *
 *  If +key+ is not found and no block was given,
 *  returns +default_value+:
 *    {}.fetch(:nosuch, :default) # => :default
 *
 *  If +key+ is not found and a block was given,
 *  yields +key+ to the block and returns the block's return value:
 *    {}.fetch(:nosuch) {|key| "No key #{key}"} # => "No key nosuch"
 *
 *  Raises KeyError if neither +default_value+ nor a block was given.
 *
 *  Note that this method does not use the values of either #default or #default_proc.
 */

static VALUE
rb_hash_fetch_m(int argc, VALUE *argv, VALUE hash)
{
    VALUE key;
    st_data_t val;
    long block_given;

    rb_check_arity(argc, 1, 2);
    key = argv[0];

    block_given = rb_block_given_p();
    if (block_given && argc == 2) {
        rb_warn("block supersedes default value argument");
    }

    if (hash_stlike_lookup(hash, key, &val)) {
        return (VALUE)val;
    }
    else {
        if (block_given) {
            return rb_yield(key);
        }
        else if (argc == 1) {
            VALUE desc = rb_protect(rb_inspect, key, 0);
            if (NIL_P(desc)) {
                desc = rb_any_to_s(key);
            }
            desc = rb_str_ellipsize(desc, 65);
            rb_key_err_raise(rb_sprintf("key not found: %"PRIsVALUE, desc), hash, key);
        }
        else {
            return argv[1];
        }
    }
}

VALUE
rb_hash_fetch(VALUE hash, VALUE key)
{
    return rb_hash_fetch_m(1, &key, hash);
}

/*
 *  call-seq:
 *    hash.default -> object
 *    hash.default(key) -> object
 *
 *  Returns the default value for the given +key+.
 *  The returned value will be determined either by the default proc or by the default value.
 *  See {Default Values}[rdoc-ref:Hash@Default+Values].
 *
 *  With no argument, returns the current default value:
 *    h = {}
 *    h.default # => nil
 *
 *  If +key+ is given, returns the default value for +key+,
 *  regardless of whether that key exists:
 *    h = Hash.new { |hash, key| hash[key] = "No key #{key}"}
 *    h[:foo] = "Hello"
 *    h.default(:foo) # => "No key foo"
 */

static VALUE
rb_hash_default(int argc, VALUE *argv, VALUE hash)
{
    VALUE ifnone;

    rb_check_arity(argc, 0, 1);
    ifnone = RHASH_IFNONE(hash);
    if (FL_TEST(hash, RHASH_PROC_DEFAULT)) {
        if (argc == 0) return Qnil;
        return call_default_proc(ifnone, hash, argv[0]);
    }
    return ifnone;
}

/*
 *  call-seq:
 *    hash.default = value -> object
 *
 *  Sets the default value to +value+; returns +value+:
 *    h = {}
 *    h.default # => nil
 *    h.default = false # => false
 *    h.default # => false
 *
 *  See {Default Values}[rdoc-ref:Hash@Default+Values].
 */

static VALUE
rb_hash_set_default(VALUE hash, VALUE ifnone)
{
    rb_hash_modify_check(hash);
    SET_DEFAULT(hash, ifnone);
    return ifnone;
}

/*
 *  call-seq:
 *    hash.default_proc -> proc or nil
 *
 *  Returns the default proc for +self+
 *  (see {Default Values}[rdoc-ref:Hash@Default+Values]):
 *    h = {}
 *    h.default_proc # => nil
 *    h.default_proc = proc {|hash, key| "Default value for #{key}" }
 *    h.default_proc.class # => Proc
 */

static VALUE
rb_hash_default_proc(VALUE hash)
{
    if (FL_TEST(hash, RHASH_PROC_DEFAULT)) {
        return RHASH_IFNONE(hash);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    hash.default_proc = proc -> proc
 *
 *  Sets the default proc for +self+ to +proc+
 *  (see {Default Values}[rdoc-ref:Hash@Default+Values]):
 *    h = {}
 *    h.default_proc # => nil
 *    h.default_proc = proc { |hash, key| "Default value for #{key}" }
 *    h.default_proc.class # => Proc
 *    h.default_proc = nil
 *    h.default_proc # => nil
 */

VALUE
rb_hash_set_default_proc(VALUE hash, VALUE proc)
{
    VALUE b;

    rb_hash_modify_check(hash);
    if (NIL_P(proc)) {
        SET_DEFAULT(hash, proc);
        return proc;
    }
    b = rb_check_convert_type_with_id(proc, T_DATA, "Proc", idTo_proc);
    if (NIL_P(b) || !rb_obj_is_proc(b)) {
        rb_raise(rb_eTypeError,
                 "wrong default_proc type %s (expected Proc)",
                 rb_obj_classname(proc));
    }
    proc = b;
    SET_PROC_DEFAULT(hash, proc);
    return proc;
}

static int
key_i(VALUE key, VALUE value, VALUE arg)
{
    VALUE *args = (VALUE *)arg;

    if (rb_equal(value, args[0])) {
        args[1] = key;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.key(value) -> key or nil
 *
 *  Returns the key for the first-found entry with the given +value+
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *    h = {foo: 0, bar: 2, baz: 2}
 *    h.key(0) # => :foo
 *    h.key(2) # => :bar
 *
 *  Returns +nil+ if no such value is found.
 */

static VALUE
rb_hash_key(VALUE hash, VALUE value)
{
    VALUE args[2];

    args[0] = value;
    args[1] = Qnil;

    rb_hash_foreach(hash, key_i, (VALUE)args);

    return args[1];
}

int
rb_hash_stlike_delete(VALUE hash, st_data_t *pkey, st_data_t *pval)
{
    if (RHASH_AR_TABLE_P(hash)) {
        return ar_delete(hash, pkey, pval);
    }
    else {
        return st_delete(RHASH_ST_TABLE(hash), pkey, pval);
    }
}

/*
 * delete a specified entry by a given key.
 * if there is the corresponding entry, return a value of the entry.
 * if there is no corresponding entry, return Qundef.
 */
VALUE
rb_hash_delete_entry(VALUE hash, VALUE key)
{
    st_data_t ktmp = (st_data_t)key, val;

    if (rb_hash_stlike_delete(hash, &ktmp, &val)) {
        return (VALUE)val;
    }
    else {
        return Qundef;
    }
}

/*
 * delete a specified entry by a given key.
 * if there is the corresponding entry, return a value of the entry.
 * if there is no corresponding entry, return Qnil.
 */
VALUE
rb_hash_delete(VALUE hash, VALUE key)
{
    VALUE deleted_value = rb_hash_delete_entry(hash, key);

    if (!UNDEF_P(deleted_value)) { /* likely pass */
        return deleted_value;
    }
    else {
        return Qnil;
    }
}

/*
 *  call-seq:
 *    hash.delete(key) -> value or nil
 *    hash.delete(key) {|key| ... } -> object
 *
 *  Deletes the entry for the given +key+ and returns its associated value.
 *
 *  If no block is given and +key+ is found, deletes the entry and returns the associated value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:bar) # => 1
 *    h # => {:foo=>0, :baz=>2}
 *
 *  If no block given and +key+ is not found, returns +nil+.
 *
 *  If a block is given and +key+ is found, ignores the block,
 *  deletes the entry, and returns the associated value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:baz) { |key| raise 'Will never happen'} # => 2
 *    h # => {:foo=>0, :bar=>1}
 *
 *  If a block is given and +key+ is not found,
 *  calls the block and returns the block's return value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:nosuch) { |key| "Key #{key} not found" } # => "Key nosuch not found"
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 */

static VALUE
rb_hash_delete_m(VALUE hash, VALUE key)
{
    VALUE val;

    rb_hash_modify_check(hash);
    val = rb_hash_delete_entry(hash, key);

    if (!UNDEF_P(val)) {
        compact_after_delete(hash);
        return val;
    }
    else {
        if (rb_block_given_p()) {
            return rb_yield(key);
        }
        else {
            return Qnil;
        }
    }
}

struct shift_var {
    VALUE key;
    VALUE val;
};

static int
shift_i_safe(VALUE key, VALUE value, VALUE arg)
{
    struct shift_var *var = (struct shift_var *)arg;

    var->key = key;
    var->val = value;
    return ST_STOP;
}

/*
 *  call-seq:
 *    hash.shift -> [key, value] or nil
 *
 *  Removes the first hash entry
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]);
 *  returns a 2-element Array containing the removed key and value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.shift # => [:foo, 0]
 *    h # => {:bar=>1, :baz=>2}
 *
 *  Returns nil if the hash is empty.
 */

static VALUE
rb_hash_shift(VALUE hash)
{
    struct shift_var var;

    rb_hash_modify_check(hash);
    if (RHASH_AR_TABLE_P(hash)) {
        var.key = Qundef;
        if (!hash_iterating_p(hash)) {
            if (ar_shift(hash, &var.key, &var.val)) {
                return rb_assoc_new(var.key, var.val);
            }
        }
        else {
            rb_hash_foreach(hash, shift_i_safe, (VALUE)&var);
            if (!UNDEF_P(var.key)) {
                rb_hash_delete_entry(hash, var.key);
                return rb_assoc_new(var.key, var.val);
            }
        }
    }
    if (RHASH_ST_TABLE_P(hash)) {
        var.key = Qundef;
        if (!hash_iterating_p(hash)) {
            if (st_shift(RHASH_ST_TABLE(hash), &var.key, &var.val)) {
                return rb_assoc_new(var.key, var.val);
            }
        }
        else {
            rb_hash_foreach(hash, shift_i_safe, (VALUE)&var);
            if (!UNDEF_P(var.key)) {
                rb_hash_delete_entry(hash, var.key);
                return rb_assoc_new(var.key, var.val);
            }
        }
    }
    return Qnil;
}

static int
delete_if_i(VALUE key, VALUE value, VALUE hash)
{
    if (RTEST(rb_yield_values(2, key, value))) {
        rb_hash_modify(hash);
        return ST_DELETE;
    }
    return ST_CONTINUE;
}

static VALUE
hash_enum_size(VALUE hash, VALUE args, VALUE eobj)
{
    return rb_hash_size(hash);
}

/*
 *  call-seq:
 *    hash.delete_if {|key, value| ... } -> self
 *    hash.delete_if -> new_enumerator
 *
 *  If a block given, calls the block with each key-value pair;
 *  deletes each entry for which the block returns a truthy value;
 *  returns +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete_if {|key, value| value > 0 } # => {:foo=>0}
 *
 *  If no block given, returns a new Enumerator:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.delete_if # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:delete_if>
 *    e.each { |key, value| value > 0 } # => {:foo=>0}
 */

VALUE
rb_hash_delete_if(VALUE hash)
{
    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_modify_check(hash);
    if (!RHASH_TABLE_EMPTY_P(hash)) {
        rb_hash_foreach(hash, delete_if_i, hash);
        compact_after_delete(hash);
    }
    return hash;
}

/*
 *  call-seq:
 *    hash.reject! {|key, value| ... } -> self or nil
 *    hash.reject! -> new_enumerator
 *
 *  Returns +self+, whose remaining entries are those
 *  for which the block returns +false+ or +nil+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.reject! {|key, value| value < 2 } # => {:baz=>2}
 *
 *  Returns +nil+ if no entries are removed.
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.reject! # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:reject!>
 *    e.each {|key, value| key.start_with?('b') } # => {:foo=>0}
 */

static VALUE
rb_hash_reject_bang(VALUE hash)
{
    st_index_t n;

    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_modify(hash);
    n = RHASH_SIZE(hash);
    if (!n) return Qnil;
    rb_hash_foreach(hash, delete_if_i, hash);
    if (n == RHASH_SIZE(hash)) return Qnil;
    return hash;
}

/*
 *  call-seq:
 *    hash.reject {|key, value| ... } -> new_hash
 *    hash.reject -> new_enumerator
 *
 *  Returns a new +Hash+ object whose entries are all those
 *  from +self+ for which the block returns +false+ or +nil+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.reject {|key, value| key.start_with?('b') }
 *    h1 # => {:foo=>0}
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.reject # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:reject>
 *    h1 = e.each {|key, value| key.start_with?('b') }
 *    h1 # => {:foo=>0}
 */

static VALUE
rb_hash_reject(VALUE hash)
{
    VALUE result;

    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    result = hash_dup_with_compare_by_id(hash);
    if (!RHASH_EMPTY_P(hash)) {
        rb_hash_foreach(result, delete_if_i, result);
        compact_after_delete(result);
    }
    return result;
}

/*
 *  call-seq:
 *    hash.slice(*keys) -> new_hash
 *
 *  Returns a new +Hash+ object containing the entries for the given +keys+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.slice(:baz, :foo) # => {:baz=>2, :foo=>0}
 *
 *  Any given +keys+ that are not found are ignored.
 */

static VALUE
rb_hash_slice(int argc, VALUE *argv, VALUE hash)
{
    int i;
    VALUE key, value, result;

    if (argc == 0 || RHASH_EMPTY_P(hash)) {
        return copy_compare_by_id(rb_hash_new(), hash);
    }
    result = copy_compare_by_id(rb_hash_new_with_size(argc), hash);

    for (i = 0; i < argc; i++) {
        key = argv[i];
        value = rb_hash_lookup2(hash, key, Qundef);
        if (!UNDEF_P(value))
            rb_hash_aset(result, key, value);
    }

    return result;
}

/*
 *  call-seq:
 *     hsh.except(*keys) -> a_hash
 *
 *  Returns a new +Hash+ excluding entries for the given +keys+:
 *     h = { a: 100, b: 200, c: 300 }
 *     h.except(:a)          #=> {:b=>200, :c=>300}
 *
 *  Any given +keys+ that are not found are ignored.
 */

static VALUE
rb_hash_except(int argc, VALUE *argv, VALUE hash)
{
    int i;
    VALUE key, result;

    result = hash_dup_with_compare_by_id(hash);

    for (i = 0; i < argc; i++) {
        key = argv[i];
        rb_hash_delete(result, key);
    }
    compact_after_delete(result);

    return result;
}

/*
 *  call-seq:
 *    hash.values_at(*keys) -> new_array
 *
 *  Returns a new Array containing values for the given +keys+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.values_at(:baz, :foo) # => [2, 0]
 *
 *  The {default values}[rdoc-ref:Hash@Default+Values] are returned
 *  for any keys that are not found:
 *    h.values_at(:hello, :foo) # => [nil, 0]
 */

static VALUE
rb_hash_values_at(int argc, VALUE *argv, VALUE hash)
{
    VALUE result = rb_ary_new2(argc);
    long i;

    for (i=0; i<argc; i++) {
        rb_ary_push(result, rb_hash_aref(hash, argv[i]));
    }
    return result;
}

/*
 *  call-seq:
 *    hash.fetch_values(*keys) -> new_array
 *    hash.fetch_values(*keys) {|key| ... } -> new_array
 *
 *  Returns a new Array containing the values associated with the given keys *keys:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.fetch_values(:baz, :foo) # => [2, 0]
 *
 *  Returns a new empty Array if no arguments given.
 *
 *  When a block is given, calls the block with each missing key,
 *  treating the block's return value as the value for that key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    values = h.fetch_values(:bar, :foo, :bad, :bam) {|key| key.to_s}
 *    values # => [1, 0, "bad", "bam"]
 *
 *  When no block is given, raises an exception if any given key is not found.
 */

static VALUE
rb_hash_fetch_values(int argc, VALUE *argv, VALUE hash)
{
    VALUE result = rb_ary_new2(argc);
    long i;

    for (i=0; i<argc; i++) {
        rb_ary_push(result, rb_hash_fetch(hash, argv[i]));
    }
    return result;
}

static int
keep_if_i(VALUE key, VALUE value, VALUE hash)
{
    if (!RTEST(rb_yield_values(2, key, value))) {
        rb_hash_modify(hash);
        return ST_DELETE;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.select {|key, value| ... } -> new_hash
 *    hash.select -> new_enumerator
 *
 *  Returns a new +Hash+ object whose entries are those for which the block returns a truthy value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.select {|key, value| value < 2 } # => {:foo=>0, :bar=>1}
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.select # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:select>
 *    e.each {|key, value| value < 2 } # => {:foo=>0, :bar=>1}
 */

static VALUE
rb_hash_select(VALUE hash)
{
    VALUE result;

    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    result = hash_dup_with_compare_by_id(hash);
    if (!RHASH_EMPTY_P(hash)) {
        rb_hash_foreach(result, keep_if_i, result);
        compact_after_delete(result);
    }
    return result;
}

/*
 *  call-seq:
 *    hash.select! {|key, value| ... } -> self or nil
 *    hash.select! -> new_enumerator
 *
 *  Returns +self+, whose entries are those for which the block returns a truthy value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.select! {|key, value| value < 2 }  => {:foo=>0, :bar=>1}
 *
 *  Returns +nil+ if no entries were removed.
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.select!  # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:select!>
 *    e.each { |key, value| value < 2 } # => {:foo=>0, :bar=>1}
 */

static VALUE
rb_hash_select_bang(VALUE hash)
{
    st_index_t n;

    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_modify_check(hash);
    n = RHASH_SIZE(hash);
    if (!n) return Qnil;
    rb_hash_foreach(hash, keep_if_i, hash);
    if (n == RHASH_SIZE(hash)) return Qnil;
    return hash;
}

/*
 *  call-seq:
 *    hash.keep_if {|key, value| ... } -> self
 *    hash.keep_if -> new_enumerator
 *
 *  Calls the block for each key-value pair;
 *  retains the entry if the block returns a truthy value;
 *  otherwise deletes the entry; returns +self+.
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.keep_if { |key, value| key.start_with?('b') } # => {:bar=>1, :baz=>2}
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.keep_if # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:keep_if>
 *    e.each { |key, value| key.start_with?('b') } # => {:bar=>1, :baz=>2}
 */

static VALUE
rb_hash_keep_if(VALUE hash)
{
    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_modify_check(hash);
    if (!RHASH_TABLE_EMPTY_P(hash)) {
        rb_hash_foreach(hash, keep_if_i, hash);
    }
    return hash;
}

static int
clear_i(VALUE key, VALUE value, VALUE dummy)
{
    return ST_DELETE;
}

/*
 *  call-seq:
 *    hash.clear -> self
 *
 *  Removes all hash entries; returns +self+.
 */

VALUE
rb_hash_clear(VALUE hash)
{
    rb_hash_modify_check(hash);

    if (hash_iterating_p(hash)) {
        rb_hash_foreach(hash, clear_i, 0);
    }
    else if (RHASH_AR_TABLE_P(hash)) {
        ar_clear(hash);
    }
    else {
        st_clear(RHASH_ST_TABLE(hash));
        compact_after_delete(hash);
    }

    return hash;
}

static int
hash_aset(st_data_t *key, st_data_t *val, struct update_arg *arg, int existing)
{
    *val = arg->arg;
    return ST_CONTINUE;
}

VALUE
rb_hash_key_str(VALUE key)
{
    if (!RB_FL_ANY_RAW(key, FL_EXIVAR) && RBASIC_CLASS(key) == rb_cString) {
        return rb_fstring(key);
    }
    else {
        return rb_str_new_frozen(key);
    }
}

static int
hash_aset_str(st_data_t *key, st_data_t *val, struct update_arg *arg, int existing)
{
    if (!existing && !RB_OBJ_FROZEN(*key)) {
        *key = rb_hash_key_str(*key);
    }
    return hash_aset(key, val, arg, existing);
}

NOINSERT_UPDATE_CALLBACK(hash_aset)
NOINSERT_UPDATE_CALLBACK(hash_aset_str)

/*
 *  call-seq:
 *    hash[key] = value -> value
 *    hash.store(key, value)
 *
 *  Associates the given +value+ with the given +key+; returns +value+.
 *
 *  If the given +key+ exists, replaces its value with the given +value+;
 *  the ordering is not affected
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *    h = {foo: 0, bar: 1}
 *    h[:foo] = 2 # => 2
 *    h.store(:bar, 3) # => 3
 *    h # => {:foo=>2, :bar=>3}
 *
 *  If +key+ does not exist, adds the +key+ and +value+;
 *  the new entry is last in the order
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *    h = {foo: 0, bar: 1}
 *    h[:baz] = 2 # => 2
 *    h.store(:bat, 3) # => 3
 *    h # => {:foo=>0, :bar=>1, :baz=>2, :bat=>3}
 */

VALUE
rb_hash_aset(VALUE hash, VALUE key, VALUE val)
{
    bool iter_p = hash_iterating_p(hash);

    rb_hash_modify(hash);

    if (!RHASH_STRING_KEY_P(hash, key)) {
        RHASH_UPDATE_ITER(hash, iter_p, key, hash_aset, val);
    }
    else {
        RHASH_UPDATE_ITER(hash, iter_p, key, hash_aset_str, val);
    }
    return val;
}

/*
 *  call-seq:
 *    hash.replace(other_hash) -> self
 *
 *  Replaces the entire contents of +self+ with the contents of +other_hash+;
 *  returns +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.replace({bat: 3, bam: 4}) # => {:bat=>3, :bam=>4}
 */

static VALUE
rb_hash_replace(VALUE hash, VALUE hash2)
{
    rb_hash_modify_check(hash);
    if (hash == hash2) return hash;
    if (hash_iterating_p(hash)) {
        rb_raise(rb_eRuntimeError, "can't replace hash during iteration");
    }
    hash2 = to_hash(hash2);

    COPY_DEFAULT(hash, hash2);

    if (RHASH_AR_TABLE_P(hash)) {
        hash_ar_free_and_clear_table(hash);
    }
    else {
        hash_st_free_and_clear_table(hash);
    }

    hash_copy(hash, hash2);

    return hash;
}

/*
 *  call-seq:
 *     hash.length -> integer
 *     hash.size -> integer
 *
 *  Returns the count of entries in +self+:
 *
 *    {foo: 0, bar: 1, baz: 2}.length # => 3
 *
 */

VALUE
rb_hash_size(VALUE hash)
{
    return INT2FIX(RHASH_SIZE(hash));
}

size_t
rb_hash_size_num(VALUE hash)
{
    return (long)RHASH_SIZE(hash);
}

/*
 *  call-seq:
 *    hash.empty? -> true or false
 *
 *  Returns +true+ if there are no hash entries, +false+ otherwise:
 *    {}.empty? # => true
 *    {foo: 0, bar: 1, baz: 2}.empty? # => false
 */

VALUE
rb_hash_empty_p(VALUE hash)
{
    return RBOOL(RHASH_EMPTY_P(hash));
}

static int
each_value_i(VALUE key, VALUE value, VALUE _)
{
    rb_yield(value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.each_value {|value| ... } -> self
 *    hash.each_value -> new_enumerator
 *
 *  Calls the given block with each value; returns +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.each_value {|value| puts value } # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    0
 *    1
 *    2
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.each_value # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:each_value>
 *    h1 = e.each {|value| puts value }
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    0
 *    1
 *    2
 */

static VALUE
rb_hash_each_value(VALUE hash)
{
    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_foreach(hash, each_value_i, 0);
    return hash;
}

static int
each_key_i(VALUE key, VALUE value, VALUE _)
{
    rb_yield(key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.each_key {|key| ... } -> self
 *    hash.each_key -> new_enumerator
 *
 *  Calls the given block with each key; returns +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.each_key {|key| puts key }  # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    foo
 *    bar
 *    baz
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.each_key # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:each_key>
 *    h1 = e.each {|key| puts key }
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    foo
 *    bar
 *    baz
 */
static VALUE
rb_hash_each_key(VALUE hash)
{
    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_foreach(hash, each_key_i, 0);
    return hash;
}

static int
each_pair_i(VALUE key, VALUE value, VALUE _)
{
    rb_yield(rb_assoc_new(key, value));
    return ST_CONTINUE;
}

static int
each_pair_i_fast(VALUE key, VALUE value, VALUE _)
{
    VALUE argv[2];
    argv[0] = key;
    argv[1] = value;
    rb_yield_values2(2, argv);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.each {|key, value| ... } -> self
 *    hash.each_pair {|key, value| ... } -> self
 *    hash.each -> new_enumerator
 *    hash.each_pair -> new_enumerator
 *
 *  Calls the given block with each key-value pair; returns +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.each_pair {|key, value| puts "#{key}: #{value}"} # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    foo: 0
 *    bar: 1
 *    baz: 2
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.each_pair # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:each_pair>
 *    h1 = e.each {|key, value| puts "#{key}: #{value}"}
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    foo: 0
 *    bar: 1
 *    baz: 2
 */

static VALUE
rb_hash_each_pair(VALUE hash)
{
    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    if (rb_block_pair_yield_optimizable())
        rb_hash_foreach(hash, each_pair_i_fast, 0);
    else
        rb_hash_foreach(hash, each_pair_i, 0);
    return hash;
}

struct transform_keys_args{
    VALUE trans;
    VALUE result;
    int block_given;
};

static int
transform_keys_hash_i(VALUE key, VALUE value, VALUE transarg)
{
    struct transform_keys_args *p = (void *)transarg;
    VALUE trans = p->trans, result = p->result;
    VALUE new_key = rb_hash_lookup2(trans, key, Qundef);
    if (UNDEF_P(new_key)) {
        if (p->block_given)
            new_key = rb_yield(key);
        else
            new_key = key;
    }
    rb_hash_aset(result, new_key, value);
    return ST_CONTINUE;
}

static int
transform_keys_i(VALUE key, VALUE value, VALUE result)
{
    VALUE new_key = rb_yield(key);
    rb_hash_aset(result, new_key, value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.transform_keys {|key| ... } -> new_hash
 *    hash.transform_keys(hash2) -> new_hash
 *    hash.transform_keys(hash2) {|other_key| ...} -> new_hash
 *    hash.transform_keys -> new_enumerator
 *
 *  Returns a new +Hash+ object; each entry has:
 *  * A key provided by the block.
 *  * The value from +self+.
 *
 *  An optional hash argument can be provided to map keys to new keys.
 *  Any key not given will be mapped using the provided block,
 *  or remain the same if no block is given.
 *
 *  Transform keys:
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h1 = h.transform_keys {|key| key.to_s }
 *      h1 # => {"foo"=>0, "bar"=>1, "baz"=>2}
 *
 *      h.transform_keys(foo: :bar, bar: :foo)
 *      #=> {bar: 0, foo: 1, baz: 2}
 *
 *      h.transform_keys(foo: :hello, &:to_s)
 *      #=> {:hello=>0, "bar"=>1, "baz"=>2}
 *
 *  Overwrites values for duplicate keys:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_keys {|key| :bat }
 *    h1 # => {:bat=>2}
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.transform_keys # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:transform_keys>
 *    h1 = e.each { |key| key.to_s }
 *    h1 # => {"foo"=>0, "bar"=>1, "baz"=>2}
 */
static VALUE
rb_hash_transform_keys(int argc, VALUE *argv, VALUE hash)
{
    VALUE result;
    struct transform_keys_args transarg = {0};

    argc = rb_check_arity(argc, 0, 1);
    if (argc > 0) {
        transarg.trans = to_hash(argv[0]);
        transarg.block_given = rb_block_given_p();
    }
    else {
        RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    }
    result = rb_hash_new();
    if (!RHASH_EMPTY_P(hash)) {
        if (transarg.trans) {
            transarg.result = result;
            rb_hash_foreach(hash, transform_keys_hash_i, (VALUE)&transarg);
        }
        else {
            rb_hash_foreach(hash, transform_keys_i, result);
        }
    }

    return result;
}

static int flatten_i(VALUE key, VALUE val, VALUE ary);

/*
 *  call-seq:
 *    hash.transform_keys! {|key| ... } -> self
 *    hash.transform_keys!(hash2) -> self
 *    hash.transform_keys!(hash2) {|other_key| ...} -> self
 *    hash.transform_keys! -> new_enumerator
 *
 *  Same as Hash#transform_keys but modifies the receiver in place
 *  instead of returning a new hash.
 */
static VALUE
rb_hash_transform_keys_bang(int argc, VALUE *argv, VALUE hash)
{
    VALUE trans = 0;
    int block_given = 0;

    argc = rb_check_arity(argc, 0, 1);
    if (argc > 0) {
        trans = to_hash(argv[0]);
        block_given = rb_block_given_p();
    }
    else {
        RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    }
    rb_hash_modify_check(hash);
    if (!RHASH_TABLE_EMPTY_P(hash)) {
        long i;
        VALUE new_keys = hash_alloc(0);
        VALUE pairs = rb_ary_hidden_new(RHASH_SIZE(hash) * 2);
        rb_hash_foreach(hash, flatten_i, pairs);
        for (i = 0; i < RARRAY_LEN(pairs); i += 2) {
            VALUE key = RARRAY_AREF(pairs, i), new_key, val;

            if (!trans) {
                new_key = rb_yield(key);
            }
            else if (!UNDEF_P(new_key = rb_hash_lookup2(trans, key, Qundef))) {
                /* use the transformed key */
            }
            else if (block_given) {
                new_key = rb_yield(key);
            }
            else {
                new_key = key;
            }
            val = RARRAY_AREF(pairs, i+1);
            if (!hash_stlike_lookup(new_keys, key, NULL)) {
                rb_hash_stlike_delete(hash, &key, NULL);
            }
            rb_hash_aset(hash, new_key, val);
            rb_hash_aset(new_keys, new_key, Qnil);
        }
        rb_ary_clear(pairs);
        rb_hash_clear(new_keys);
    }
    compact_after_delete(hash);
    return hash;
}

static int
transform_values_foreach_func(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    return ST_REPLACE;
}

static int
transform_values_foreach_replace(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    VALUE new_value = rb_yield((VALUE)*value);
    VALUE hash = (VALUE)argp;
    rb_hash_modify(hash);
    RB_OBJ_WRITE(hash, value, new_value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.transform_values {|value| ... } -> new_hash
 *    hash.transform_values -> new_enumerator
 *
 *  Returns a new +Hash+ object; each entry has:
 *  * A key from +self+.
 *  * A value provided by the block.
 *
 *  Transform values:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_values {|value| value * 100}
 *    h1 # => {:foo=>0, :bar=>100, :baz=>200}
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.transform_values # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:transform_values>
 *    h1 = e.each { |value| value * 100}
 *    h1 # => {:foo=>0, :bar=>100, :baz=>200}
 */
static VALUE
rb_hash_transform_values(VALUE hash)
{
    VALUE result;

    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    result = hash_dup_with_compare_by_id(hash);
    SET_DEFAULT(result, Qnil);

    if (!RHASH_EMPTY_P(hash)) {
        rb_hash_stlike_foreach_with_replace(result, transform_values_foreach_func, transform_values_foreach_replace, result);
        compact_after_delete(result);
    }

    return result;
}

/*
 *  call-seq:
 *    hash.transform_values! {|value| ... } -> self
 *    hash.transform_values! -> new_enumerator
 *
 *  Returns +self+, whose keys are unchanged, and whose values are determined by the given block.
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.transform_values! {|value| value * 100} # => {:foo=>0, :bar=>100, :baz=>200}
 *
 *  Returns a new Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.transform_values! # => #<Enumerator: {:foo=>0, :bar=>100, :baz=>200}:transform_values!>
 *    h1 = e.each {|value| value * 100}
 *    h1 # => {:foo=>0, :bar=>100, :baz=>200}
 */
static VALUE
rb_hash_transform_values_bang(VALUE hash)
{
    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_modify_check(hash);

    if (!RHASH_TABLE_EMPTY_P(hash)) {
        rb_hash_stlike_foreach_with_replace(hash, transform_values_foreach_func, transform_values_foreach_replace, hash);
    }

    return hash;
}

static int
to_a_i(VALUE key, VALUE value, VALUE ary)
{
    rb_ary_push(ary, rb_assoc_new(key, value));
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.to_a -> new_array
 *
 *  Returns a new Array of 2-element Array objects;
 *  each nested Array contains a key-value pair from +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.to_a # => [[:foo, 0], [:bar, 1], [:baz, 2]]
 */

static VALUE
rb_hash_to_a(VALUE hash)
{
    VALUE ary;

    ary = rb_ary_new_capa(RHASH_SIZE(hash));
    rb_hash_foreach(hash, to_a_i, ary);

    return ary;
}

static bool
symbol_key_needs_quote(VALUE str)
{
    long len = RSTRING_LEN(str);
    if (len == 0 || !rb_str_symname_p(str)) return true;
    const char *s = RSTRING_PTR(str);
    char first = s[0];
    if (first == '@' || first == '$' || first == '!') return true;
    if (!at_char_boundary(s, s + len - 1, RSTRING_END(str), rb_enc_get(str))) return false;
    switch (s[len - 1]) {
        case '+':
        case '-':
        case '*':
        case '/':
        case '`':
        case '%':
        case '^':
        case '&':
        case '|':
        case ']':
        case '<':
        case '=':
        case '>':
        case '~':
        case '@':
            return true;
        default:
            return false;
    }
}

static int
inspect_i(VALUE key, VALUE value, VALUE str)
{
    VALUE str2;

    bool is_symbol = SYMBOL_P(key);
    bool quote = false;
    if (is_symbol) {
        str2 = rb_sym2str(key);
        quote = symbol_key_needs_quote(str2);
    }
    else {
        str2 = rb_inspect(key);
    }
    if (RSTRING_LEN(str) > 1) {
        rb_str_buf_cat_ascii(str, ", ");
    }
    else {
        rb_enc_copy(str, str2);
    }
    if (quote) {
        rb_str_buf_append(str, rb_str_inspect(str2));
    }
    else {
        rb_str_buf_append(str, str2);
    }

    rb_str_buf_cat_ascii(str, is_symbol ? ": " : " => ");
    str2 = rb_inspect(value);
    rb_str_buf_append(str, str2);

    return ST_CONTINUE;
}

static VALUE
inspect_hash(VALUE hash, VALUE dummy, int recur)
{
    VALUE str;

    if (recur) return rb_usascii_str_new2("{...}");
    str = rb_str_buf_new2("{");
    rb_hash_foreach(hash, inspect_i, str);
    rb_str_buf_cat2(str, "}");

    return str;
}

/*
 *  call-seq:
 *    hash.inspect -> new_string
 *
 *  Returns a new String containing the hash entries:

 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.inspect # => "{foo: 0, bar: 1, baz: 2}"
 *
 */

static VALUE
rb_hash_inspect(VALUE hash)
{
    if (RHASH_EMPTY_P(hash))
        return rb_usascii_str_new2("{}");
    return rb_exec_recursive(inspect_hash, hash, 0);
}

/*
 *  call-seq:
 *    hash.to_hash -> self
 *
 *  Returns +self+.
 */
static VALUE
rb_hash_to_hash(VALUE hash)
{
    return hash;
}

VALUE
rb_hash_set_pair(VALUE hash, VALUE arg)
{
    VALUE pair;

    pair = rb_check_array_type(arg);
    if (NIL_P(pair)) {
        rb_raise(rb_eTypeError, "wrong element type %s (expected array)",
                 rb_builtin_class_name(arg));
    }
    if (RARRAY_LEN(pair) != 2) {
        rb_raise(rb_eArgError, "element has wrong array length (expected 2, was %ld)",
                 RARRAY_LEN(pair));
    }
    rb_hash_aset(hash, RARRAY_AREF(pair, 0), RARRAY_AREF(pair, 1));
    return hash;
}

static int
to_h_i(VALUE key, VALUE value, VALUE hash)
{
    rb_hash_set_pair(hash, rb_yield_values(2, key, value));
    return ST_CONTINUE;
}

static VALUE
rb_hash_to_h_block(VALUE hash)
{
    VALUE h = rb_hash_new_with_size(RHASH_SIZE(hash));
    rb_hash_foreach(hash, to_h_i, h);
    return h;
}

/*
 *  call-seq:
 *    hash.to_h -> self or new_hash
 *    hash.to_h {|key, value| ... } -> new_hash
 *
 *  For an instance of +Hash+, returns +self+.
 *
 *  For a subclass of +Hash+, returns a new +Hash+
 *  containing the content of +self+.
 *
 *  When a block is given, returns a new +Hash+ object
 *  whose content is based on the block;
 *  the block should return a 2-element Array object
 *  specifying the key-value pair to be included in the returned Array:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.to_h {|key, value| [value, key] }
 *    h1 # => {0=>:foo, 1=>:bar, 2=>:baz}
 */

static VALUE
rb_hash_to_h(VALUE hash)
{
    if (rb_block_given_p()) {
        return rb_hash_to_h_block(hash);
    }
    if (rb_obj_class(hash) != rb_cHash) {
        const VALUE flags = RBASIC(hash)->flags;
        hash = hash_dup(hash, rb_cHash, flags & RHASH_PROC_DEFAULT);
    }
    return hash;
}

static int
keys_i(VALUE key, VALUE value, VALUE ary)
{
    rb_ary_push(ary, key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.keys -> new_array
 *
 *  Returns a new Array containing all keys in +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.keys # => [:foo, :bar, :baz]
 */

VALUE
rb_hash_keys(VALUE hash)
{
    st_index_t size = RHASH_SIZE(hash);
    VALUE keys =  rb_ary_new_capa(size);

    if (size == 0) return keys;

    if (ST_DATA_COMPATIBLE_P(VALUE)) {
        RARRAY_PTR_USE(keys, ptr, {
            if (RHASH_AR_TABLE_P(hash)) {
                size = ar_keys(hash, ptr, size);
            }
            else {
                st_table *table = RHASH_ST_TABLE(hash);
                size = st_keys(table, ptr, size);
            }
        });
        rb_gc_writebarrier_remember(keys);
        rb_ary_set_len(keys, size);
    }
    else {
        rb_hash_foreach(hash, keys_i, keys);
    }

    return keys;
}

static int
values_i(VALUE key, VALUE value, VALUE ary)
{
    rb_ary_push(ary, value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.values -> new_array
 *
 *  Returns a new Array containing all values in +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.values # => [0, 1, 2]
 */

VALUE
rb_hash_values(VALUE hash)
{
    VALUE values;
    st_index_t size = RHASH_SIZE(hash);

    values = rb_ary_new_capa(size);
    if (size == 0) return values;

    if (ST_DATA_COMPATIBLE_P(VALUE)) {
        if (RHASH_AR_TABLE_P(hash)) {
            rb_gc_writebarrier_remember(values);
            RARRAY_PTR_USE(values, ptr, {
                size = ar_values(hash, ptr, size);
            });
        }
        else if (RHASH_ST_TABLE_P(hash)) {
            st_table *table = RHASH_ST_TABLE(hash);
            rb_gc_writebarrier_remember(values);
            RARRAY_PTR_USE(values, ptr, {
                size = st_values(table, ptr, size);
            });
        }
        rb_ary_set_len(values, size);
    }

    else {
        rb_hash_foreach(hash, values_i, values);
    }

    return values;
}

/*
 *  call-seq:
 *    hash.include?(key) -> true or false
 *    hash.has_key?(key) -> true or false
 *    hash.key?(key) -> true or false
 *    hash.member?(key) -> true or false
 *
 *  Returns +true+ if +key+ is a key in +self+, otherwise +false+.
 */

VALUE
rb_hash_has_key(VALUE hash, VALUE key)
{
    return RBOOL(hash_stlike_lookup(hash, key, NULL));
}

static int
rb_hash_search_value(VALUE key, VALUE value, VALUE arg)
{
    VALUE *data = (VALUE *)arg;

    if (rb_equal(value, data[1])) {
        data[0] = Qtrue;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.has_value?(value) -> true or false
 *    hash.value?(value) -> true or false
 *
 *  Returns +true+ if +value+ is a value in +self+, otherwise +false+.
 */

static VALUE
rb_hash_has_value(VALUE hash, VALUE val)
{
    VALUE data[2];

    data[0] = Qfalse;
    data[1] = val;
    rb_hash_foreach(hash, rb_hash_search_value, (VALUE)data);
    return data[0];
}

struct equal_data {
    VALUE result;
    VALUE hash;
    int eql;
};

static int
eql_i(VALUE key, VALUE val1, VALUE arg)
{
    struct equal_data *data = (struct equal_data *)arg;
    st_data_t val2;

    if (!hash_stlike_lookup(data->hash, key, &val2)) {
        data->result = Qfalse;
        return ST_STOP;
    }
    else {
        if (!(data->eql ? rb_eql(val1, (VALUE)val2) : (int)rb_equal(val1, (VALUE)val2))) {
            data->result = Qfalse;
            return ST_STOP;
        }
        return ST_CONTINUE;
    }
}

static VALUE
recursive_eql(VALUE hash, VALUE dt, int recur)
{
    struct equal_data *data;

    if (recur) return Qtrue;	/* Subtle! */
    data = (struct equal_data*)dt;
    data->result = Qtrue;
    rb_hash_foreach(hash, eql_i, dt);

    return data->result;
}

static VALUE
hash_equal(VALUE hash1, VALUE hash2, int eql)
{
    struct equal_data data;

    if (hash1 == hash2) return Qtrue;
    if (!RB_TYPE_P(hash2, T_HASH)) {
        if (!rb_respond_to(hash2, idTo_hash)) {
            return Qfalse;
        }
        if (eql) {
            if (rb_eql(hash2, hash1)) {
                return Qtrue;
            }
            else {
                return Qfalse;
            }
        }
        else {
            return rb_equal(hash2, hash1);
        }
    }
    if (RHASH_SIZE(hash1) != RHASH_SIZE(hash2))
        return Qfalse;
    if (!RHASH_TABLE_EMPTY_P(hash1) && !RHASH_TABLE_EMPTY_P(hash2)) {
        if (RHASH_TYPE(hash1) != RHASH_TYPE(hash2)) {
            return Qfalse;
        }
        else {
            data.hash = hash2;
            data.eql = eql;
            return rb_exec_recursive_paired(recursive_eql, hash1, hash2, (VALUE)&data);
        }
    }

#if 0
    if (!(rb_equal(RHASH_IFNONE(hash1), RHASH_IFNONE(hash2)) &&
          FL_TEST(hash1, RHASH_PROC_DEFAULT) == FL_TEST(hash2, RHASH_PROC_DEFAULT)))
        return Qfalse;
#endif
    return Qtrue;
}

/*
 *  call-seq:
 *    hash == object -> true or false
 *
 *  Returns +true+ if all of the following are true:
 *  * +object+ is a +Hash+ object.
 *  * +hash+ and +object+ have the same keys (regardless of order).
 *  * For each key +key+, <tt>hash[key] == object[key]</tt>.
 *
 *  Otherwise, returns +false+.
 *
 *  Equal:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1, baz: 2}
 *    h1 == h2 # => true
 *    h3 = {baz: 2, bar: 1, foo: 0}
 *    h1 == h3 # => true
 */

static VALUE
rb_hash_equal(VALUE hash1, VALUE hash2)
{
    return hash_equal(hash1, hash2, FALSE);
}

/*
 *  call-seq:
 *    hash.eql?(object) -> true or false
 *
 *  Returns +true+ if all of the following are true:
 *  * +object+ is a +Hash+ object.
 *  * +hash+ and +object+ have the same keys (regardless of order).
 *  * For each key +key+, <tt>h[key].eql?(object[key])</tt>.
 *
 *  Otherwise, returns +false+.
 *
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1, baz: 2}
 *    h1.eql? h2 # => true
 *    h3 = {baz: 2, bar: 1, foo: 0}
 *    h1.eql? h3 # => true
 */

static VALUE
rb_hash_eql(VALUE hash1, VALUE hash2)
{
    return hash_equal(hash1, hash2, TRUE);
}

static int
hash_i(VALUE key, VALUE val, VALUE arg)
{
    st_index_t *hval = (st_index_t *)arg;
    st_index_t hdata[2];

    hdata[0] = rb_hash(key);
    hdata[1] = rb_hash(val);
    *hval ^= st_hash(hdata, sizeof(hdata), 0);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.hash -> an_integer
 *
 *  Returns the Integer hash-code for the hash.
 *
 *  Two +Hash+ objects have the same hash-code if their content is the same
 *  (regardless of order):
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {baz: 2, bar: 1, foo: 0}
 *    h2.hash == h1.hash # => true
 *    h2.eql? h1 # => true
 */

static VALUE
rb_hash_hash(VALUE hash)
{
    st_index_t size = RHASH_SIZE(hash);
    st_index_t hval = rb_hash_start(size);
    hval = rb_hash_uint(hval, (st_index_t)rb_hash_hash);
    if (size) {
        rb_hash_foreach(hash, hash_i, (VALUE)&hval);
    }
    hval = rb_hash_end(hval);
    return ST2FIX(hval);
}

static int
rb_hash_invert_i(VALUE key, VALUE value, VALUE hash)
{
    rb_hash_aset(hash, value, key);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.invert -> new_hash
 *
 *  Returns a new +Hash+ object with the each key-value pair inverted:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.invert
 *    h1 # => {0=>:foo, 1=>:bar, 2=>:baz}
 *
 *  Overwrites any repeated new keys:
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *    h = {foo: 0, bar: 0, baz: 0}
 *    h.invert # => {0=>:baz}
 */

static VALUE
rb_hash_invert(VALUE hash)
{
    VALUE h = rb_hash_new_with_size(RHASH_SIZE(hash));

    rb_hash_foreach(hash, rb_hash_invert_i, h);
    return h;
}

static int
rb_hash_update_i(VALUE key, VALUE value, VALUE hash)
{
    rb_hash_aset(hash, key, value);
    return ST_CONTINUE;
}

static int
rb_hash_update_block_callback(st_data_t *key, st_data_t *value, struct update_arg *arg, int existing)
{
    st_data_t newvalue = arg->arg;

    if (existing) {
        newvalue = (st_data_t)rb_yield_values(3, (VALUE)*key, (VALUE)*value, (VALUE)newvalue);
    }
    else if (RHASH_STRING_KEY_P(arg->hash, *key) && !RB_OBJ_FROZEN(*key)) {
        *key = rb_hash_key_str(*key);
    }
    *value = newvalue;
    return ST_CONTINUE;
}

NOINSERT_UPDATE_CALLBACK(rb_hash_update_block_callback)

static int
rb_hash_update_block_i(VALUE key, VALUE value, VALUE hash)
{
    RHASH_UPDATE(hash, key, rb_hash_update_block_callback, value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.merge! -> self
 *    hash.merge!(*other_hashes) -> self
 *    hash.merge!(*other_hashes) { |key, old_value, new_value| ... } -> self
 *
 *  Merges each of +other_hashes+ into +self+; returns +self+.
 *
 *  Each argument in +other_hashes+ must be a +Hash+.
 *
 *  With arguments and no block:
 *  * Returns +self+, after the given hashes are merged into it.
 *  * The given hashes are merged left to right.
 *  * Each new entry is added at the end.
 *  * Each duplicate-key entry's value overwrites the previous value.
 *
 *  Example:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h.merge!(h1, h2) # => {:foo=>0, :bar=>4, :baz=>2, :bat=>6, :bam=>5}
 *
 *  With arguments and a block:
 *  * Returns +self+, after the given hashes are merged.
 *  *  The given hashes are merged left to right.
 *  *  Each new-key entry is added at the end.
 *  *  For each duplicate key:
 *     * Calls the block with the key and the old and new values.
 *     * The block's return value becomes the new value for the entry.
 *
 *  Example:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h3 = h.merge!(h1, h2) { |key, old_value, new_value| old_value + new_value }
 *    h3 # => {:foo=>0, :bar=>5, :baz=>2, :bat=>9, :bam=>5}
 *
 *  With no arguments:
 *  * Returns +self+, unmodified.
 *  * The block, if given, is ignored.
 *
 *  Example:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.merge # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1 = h.merge! { |key, old_value, new_value| raise 'Cannot happen' }
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 */

static VALUE
rb_hash_update(int argc, VALUE *argv, VALUE self)
{
    int i;
    bool block_given = rb_block_given_p();

    rb_hash_modify(self);
    for (i = 0; i < argc; i++){
        VALUE hash = to_hash(argv[i]);
        if (block_given) {
            rb_hash_foreach(hash, rb_hash_update_block_i, self);
        }
        else {
            rb_hash_foreach(hash, rb_hash_update_i, self);
        }
    }
    return self;
}

struct update_func_arg {
    VALUE hash;
    VALUE value;
    rb_hash_update_func *func;
};

static int
rb_hash_update_func_callback(st_data_t *key, st_data_t *value, struct update_arg *arg, int existing)
{
    struct update_func_arg *uf_arg = (struct update_func_arg *)arg->arg;
    VALUE newvalue = uf_arg->value;

    if (existing) {
        newvalue = (*uf_arg->func)((VALUE)*key, (VALUE)*value, newvalue);
    }
    *value = newvalue;
    return ST_CONTINUE;
}

NOINSERT_UPDATE_CALLBACK(rb_hash_update_func_callback)

static int
rb_hash_update_func_i(VALUE key, VALUE value, VALUE arg0)
{
    struct update_func_arg *arg = (struct update_func_arg *)arg0;
    VALUE hash = arg->hash;

    arg->value = value;
    RHASH_UPDATE(hash, key, rb_hash_update_func_callback, (VALUE)arg);
    return ST_CONTINUE;
}

VALUE
rb_hash_update_by(VALUE hash1, VALUE hash2, rb_hash_update_func *func)
{
    rb_hash_modify(hash1);
    hash2 = to_hash(hash2);
    if (func) {
        struct update_func_arg arg;
        arg.hash = hash1;
        arg.func = func;
        rb_hash_foreach(hash2, rb_hash_update_func_i, (VALUE)&arg);
    }
    else {
        rb_hash_foreach(hash2, rb_hash_update_i, hash1);
    }
    return hash1;
}

/*
 *  call-seq:
 *    hash.merge -> copy_of_self
 *    hash.merge(*other_hashes) -> new_hash
 *    hash.merge(*other_hashes) { |key, old_value, new_value| ... } -> new_hash
 *
 *  Returns the new +Hash+ formed by merging each of +other_hashes+
 *  into a copy of +self+.
 *
 *  Each argument in +other_hashes+ must be a +Hash+.
 *
 *  ---
 *
 *  With arguments and no block:
 *  * Returns the new +Hash+ object formed by merging each successive
 *    +Hash+ in +other_hashes+ into +self+.
 *  * Each new-key entry is added at the end.
 *  * Each duplicate-key entry's value overwrites the previous value.
 *
 *  Example:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h.merge(h1, h2) # => {:foo=>0, :bar=>4, :baz=>2, :bat=>6, :bam=>5}
 *
 *  With arguments and a block:
 *  * Returns a new +Hash+ object that is the merge of +self+ and each given hash.
 *  * The given hashes are merged left to right.
 *  * Each new-key entry is added at the end.
 *  * For each duplicate key:
 *    * Calls the block with the key and the old and new values.
 *    * The block's return value becomes the new value for the entry.
 *
 *  Example:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h3 = h.merge(h1, h2) { |key, old_value, new_value| old_value + new_value }
 *    h3 # => {:foo=>0, :bar=>5, :baz=>2, :bat=>9, :bam=>5}
 *
 *  With no arguments:
 *  * Returns a copy of +self+.
 *  * The block, if given, is ignored.
 *
 *  Example:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.merge # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1 = h.merge { |key, old_value, new_value| raise 'Cannot happen' }
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 */

static VALUE
rb_hash_merge(int argc, VALUE *argv, VALUE self)
{
    return rb_hash_update(argc, argv, copy_compare_by_id(rb_hash_dup(self), self));
}

static int
assoc_cmp(VALUE a, VALUE b)
{
    return !RTEST(rb_equal(a, b));
}

struct assoc_arg {
    st_table *tbl;
    st_data_t key;
};

static VALUE
assoc_lookup(VALUE arg)
{
    struct assoc_arg *p = (struct assoc_arg*)arg;
    st_data_t data;
    if (st_lookup(p->tbl, p->key, &data)) return (VALUE)data;
    return Qundef;
}

static int
assoc_i(VALUE key, VALUE val, VALUE arg)
{
    VALUE *args = (VALUE *)arg;

    if (RTEST(rb_equal(args[0], key))) {
        args[1] = rb_assoc_new(key, val);
        return ST_STOP;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.assoc(key) -> new_array or nil
 *
 *  If the given +key+ is found, returns a 2-element Array containing that key and its value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.assoc(:bar) # => [:bar, 1]
 *
 *  Returns +nil+ if key +key+ is not found.
 */

static VALUE
rb_hash_assoc(VALUE hash, VALUE key)
{
    VALUE args[2];

    if (RHASH_EMPTY_P(hash)) return Qnil;

    if (RHASH_ST_TABLE_P(hash) && !RHASH_IDENTHASH_P(hash)) {
        VALUE value = Qundef;
        st_table assoctable = *RHASH_ST_TABLE(hash);
        assoctable.type = &(struct st_hash_type){
            .compare = assoc_cmp,
            .hash = assoctable.type->hash,
        };
        VALUE arg = (VALUE)&(struct assoc_arg){
            .tbl = &assoctable,
            .key = (st_data_t)key,
        };

        if (RB_OBJ_FROZEN(hash)) {
            value = assoc_lookup(arg);
        }
        else {
            hash_iter_lev_inc(hash);
            value = rb_ensure(assoc_lookup, arg, hash_foreach_ensure, hash);
        }
        hash_verify(hash);
        if (!UNDEF_P(value)) return rb_assoc_new(key, value);
    }

    args[0] = key;
    args[1] = Qnil;
    rb_hash_foreach(hash, assoc_i, (VALUE)args);
    return args[1];
}

static int
rassoc_i(VALUE key, VALUE val, VALUE arg)
{
    VALUE *args = (VALUE *)arg;

    if (RTEST(rb_equal(args[0], val))) {
        args[1] = rb_assoc_new(key, val);
        return ST_STOP;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.rassoc(value) -> new_array or nil
 *
 *  Returns a new 2-element Array consisting of the key and value
 *  of the first-found entry whose value is <tt>==</tt> to value
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *    h = {foo: 0, bar: 1, baz: 1}
 *    h.rassoc(1) # => [:bar, 1]
 *
 *  Returns +nil+ if no such value found.
 */

static VALUE
rb_hash_rassoc(VALUE hash, VALUE obj)
{
    VALUE args[2];

    args[0] = obj;
    args[1] = Qnil;
    rb_hash_foreach(hash, rassoc_i, (VALUE)args);
    return args[1];
}

static int
flatten_i(VALUE key, VALUE val, VALUE ary)
{
    VALUE pair[2];

    pair[0] = key;
    pair[1] = val;
    rb_ary_cat(ary, pair, 2);

    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     hash.flatten -> new_array
 *     hash.flatten(level) -> new_array
 *
 *  Returns a new Array object that is a 1-dimensional flattening of +self+.
 *
 *  ---
 *
 *  By default, nested Arrays are not flattened:
 *    h = {foo: 0, bar: [:bat, 3], baz: 2}
 *    h.flatten # => [:foo, 0, :bar, [:bat, 3], :baz, 2]
 *
 *  Takes the depth of recursive flattening from Integer argument +level+:
 *    h = {foo: 0, bar: [:bat, [:baz, [:bat, ]]]}
 *    h.flatten(1) # => [:foo, 0, :bar, [:bat, [:baz, [:bat]]]]
 *    h.flatten(2) # => [:foo, 0, :bar, :bat, [:baz, [:bat]]]
 *    h.flatten(3) # => [:foo, 0, :bar, :bat, :baz, [:bat]]
 *    h.flatten(4) # => [:foo, 0, :bar, :bat, :baz, :bat]
 *
 *  When +level+ is negative, flattens all nested Arrays:
 *    h = {foo: 0, bar: [:bat, [:baz, [:bat, ]]]}
 *    h.flatten(-1) # => [:foo, 0, :bar, :bat, :baz, :bat]
 *    h.flatten(-2) # => [:foo, 0, :bar, :bat, :baz, :bat]
 *
 *  When +level+ is zero, returns the equivalent of #to_a :
 *    h = {foo: 0, bar: [:bat, 3], baz: 2}
 *    h.flatten(0) # => [[:foo, 0], [:bar, [:bat, 3]], [:baz, 2]]
 *    h.flatten(0) == h.to_a # => true
 */

static VALUE
rb_hash_flatten(int argc, VALUE *argv, VALUE hash)
{
    VALUE ary;

    rb_check_arity(argc, 0, 1);

    if (argc) {
        int level = NUM2INT(argv[0]);

        if (level == 0) return rb_hash_to_a(hash);

        ary = rb_ary_new_capa(RHASH_SIZE(hash) * 2);
        rb_hash_foreach(hash, flatten_i, ary);
        level--;

        if (level > 0) {
            VALUE ary_flatten_level = INT2FIX(level);
            rb_funcallv(ary, id_flatten_bang, 1, &ary_flatten_level);
        }
        else if (level < 0) {
            /* flatten recursively */
            rb_funcallv(ary, id_flatten_bang, 0, 0);
        }
    }
    else {
        ary = rb_ary_new_capa(RHASH_SIZE(hash) * 2);
        rb_hash_foreach(hash, flatten_i, ary);
    }

    return ary;
}

static int
delete_if_nil(VALUE key, VALUE value, VALUE hash)
{
    if (NIL_P(value)) {
        return ST_DELETE;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.compact -> new_hash
 *
 *  Returns a copy of +self+ with all +nil+-valued entries removed:
 *    h = {foo: 0, bar: nil, baz: 2, bat: nil}
 *    h1 = h.compact
 *    h1 # => {:foo=>0, :baz=>2}
 */

static VALUE
rb_hash_compact(VALUE hash)
{
    VALUE result = rb_hash_dup(hash);
    if (!RHASH_EMPTY_P(hash)) {
        rb_hash_foreach(result, delete_if_nil, result);
        compact_after_delete(result);
    }
    else if (rb_hash_compare_by_id_p(hash)) {
        result = rb_hash_compare_by_id(result);
    }
    return result;
}

/*
 *  call-seq:
 *    hash.compact! -> self or nil
 *
 *  Returns +self+ with all its +nil+-valued entries removed (in place):
 *    h = {foo: 0, bar: nil, baz: 2, bat: nil}
 *    h.compact! # => {:foo=>0, :baz=>2}
 *
 *  Returns +nil+ if no entries were removed.
 */

static VALUE
rb_hash_compact_bang(VALUE hash)
{
    st_index_t n;
    rb_hash_modify_check(hash);
    n = RHASH_SIZE(hash);
    if (n) {
        rb_hash_foreach(hash, delete_if_nil, hash);
        if (n != RHASH_SIZE(hash))
            return hash;
    }
    return Qnil;
}

/*
 *  call-seq:
 *    hash.compare_by_identity -> self
 *
 *  Sets +self+ to consider only identity in comparing keys;
 *  two keys are considered the same only if they are the same object;
 *  returns +self+.
 *
 *  By default, these two object are considered to be the same key,
 *  so +s1+ will overwrite +s0+:
 *    s0 = 'x'
 *    s1 = 'x'
 *    h = {}
 *    h.compare_by_identity? # => false
 *    h[s0] = 0
 *    h[s1] = 1
 *    h # => {"x"=>1}
 *
 *  After calling \#compare_by_identity, the keys are considered to be different,
 *  and therefore do not overwrite each other:
 *    h = {}
 *    h.compare_by_identity # => {}
 *    h.compare_by_identity? # => true
 *    h[s0] = 0
 *    h[s1] = 1
 *    h # => {"x"=>0, "x"=>1}
 */

VALUE
rb_hash_compare_by_id(VALUE hash)
{
    VALUE tmp;
    st_table *identtable;

    if (rb_hash_compare_by_id_p(hash)) return hash;

    rb_hash_modify_check(hash);
    if (hash_iterating_p(hash)) {
        rb_raise(rb_eRuntimeError, "compare_by_identity during iteration");
    }

    if (RHASH_TABLE_EMPTY_P(hash)) {
        // Fast path: There's nothing to rehash, so we don't need a `tmp` table.
        // We're most likely an AR table, so this will need an allocation.
        ar_force_convert_table(hash, __FILE__, __LINE__);
        HASH_ASSERT(RHASH_ST_TABLE_P(hash));

        RHASH_ST_TABLE(hash)->type = &identhash;
    }
    else {
        // Slow path: Need to rehash the members of `self` into a new
        // `tmp` table using the new `identhash` compare/hash functions.
        tmp = hash_alloc(0);
        hash_st_table_init(tmp, &identhash, RHASH_SIZE(hash));
        identtable = RHASH_ST_TABLE(tmp);

        rb_hash_foreach(hash, rb_hash_rehash_i, (VALUE)tmp);
        rb_hash_free(hash);

        // We know for sure `identtable` is an st table,
        // so we can skip `ar_force_convert_table` here.
        RHASH_ST_TABLE_SET(hash, identtable);
        RHASH_ST_CLEAR(tmp);
    }

    return hash;
}

/*
 *  call-seq:
 *    hash.compare_by_identity? -> true or false
 *
 *  Returns +true+ if #compare_by_identity has been called, +false+ otherwise.
 */

VALUE
rb_hash_compare_by_id_p(VALUE hash)
{
    return RBOOL(RHASH_IDENTHASH_P(hash));
}

VALUE
rb_ident_hash_new(void)
{
    VALUE hash = rb_hash_new();
    hash_st_table_init(hash, &identhash, 0);
    return hash;
}

VALUE
rb_ident_hash_new_with_size(st_index_t size)
{
    VALUE hash = rb_hash_new();
    hash_st_table_init(hash, &identhash, size);
    return hash;
}

st_table *
rb_init_identtable(void)
{
    return st_init_table(&identhash);
}

static int
any_p_i(VALUE key, VALUE value, VALUE arg)
{
    VALUE ret = rb_yield(rb_assoc_new(key, value));
    if (RTEST(ret)) {
        *(VALUE *)arg = Qtrue;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

static int
any_p_i_fast(VALUE key, VALUE value, VALUE arg)
{
    VALUE ret = rb_yield_values(2, key, value);
    if (RTEST(ret)) {
        *(VALUE *)arg = Qtrue;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

static int
any_p_i_pattern(VALUE key, VALUE value, VALUE arg)
{
    VALUE ret = rb_funcall(((VALUE *)arg)[1], idEqq, 1, rb_assoc_new(key, value));
    if (RTEST(ret)) {
        *(VALUE *)arg = Qtrue;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.any? -> true or false
 *    hash.any?(object) -> true or false
 *    hash.any? {|key, value| ... } -> true or false
 *
 *  Returns +true+ if any element satisfies a given criterion;
 *  +false+ otherwise.
 *
 *  If +self+ has no element, returns +false+ and argument or block
 *  are not used.
 *
 *  With no argument and no block,
 *  returns +true+ if +self+ is non-empty; +false+ if empty.
 *
 *  With argument +object+ and no block,
 *  returns +true+ if for any key +key+
 *  <tt>h.assoc(key) == object</tt>:
 *   h = {foo: 0, bar: 1, baz: 2}
 *   h.any?([:bar, 1]) # => true
 *   h.any?([:bar, 0]) # => false
 *   h.any?([:baz, 1]) # => false
 *
 *  With no argument and a block,
 *  calls the block with each key-value pair;
 *  returns +true+ if the block returns any truthy value,
 *  +false+ otherwise:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.any? {|key, value| value < 3 } # => true
 *    h.any? {|key, value| value > 3 } # => false
 *
 *  Related: Enumerable#any?
 */

static VALUE
rb_hash_any_p(int argc, VALUE *argv, VALUE hash)
{
    VALUE args[2];
    args[0] = Qfalse;

    rb_check_arity(argc, 0, 1);
    if (RHASH_EMPTY_P(hash)) return Qfalse;
    if (argc) {
        if (rb_block_given_p()) {
            rb_warn("given block not used");
        }
        args[1] = argv[0];

        rb_hash_foreach(hash, any_p_i_pattern, (VALUE)args);
    }
    else {
        if (!rb_block_given_p()) {
            /* yields pairs, never false */
            return Qtrue;
        }
        if (rb_block_pair_yield_optimizable())
            rb_hash_foreach(hash, any_p_i_fast, (VALUE)args);
        else
            rb_hash_foreach(hash, any_p_i, (VALUE)args);
    }
    return args[0];
}

/*
 *  call-seq:
 *    hash.dig(key, *identifiers) -> object
 *
 *  Finds and returns the object in nested objects
 *  that is specified by +key+ and +identifiers+.
 *  The nested objects may be instances of various classes.
 *  See {Dig Methods}[rdoc-ref:dig_methods.rdoc].
 *
 *  Nested Hashes:
 *    h = {foo: {bar: {baz: 2}}}
 *    h.dig(:foo) # => {:bar=>{:baz=>2}}
 *    h.dig(:foo, :bar) # => {:baz=>2}
 *    h.dig(:foo, :bar, :baz) # => 2
 *    h.dig(:foo, :bar, :BAZ) # => nil
 *
 *  Nested Hashes and Arrays:
 *    h = {foo: {bar: [:a, :b, :c]}}
 *    h.dig(:foo, :bar, 2) # => :c
 *
 *  This method will use the {default values}[rdoc-ref:Hash@Default+Values]
 *  for keys that are not present:
 *    h = {foo: {bar: [:a, :b, :c]}}
 *    h.dig(:hello) # => nil
 *    h.default_proc = -> (hash, _key) { hash }
 *    h.dig(:hello, :world) # => h
 *    h.dig(:hello, :world, :foo, :bar, 2) # => :c
 */

static VALUE
rb_hash_dig(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    self = rb_hash_aref(self, *argv);
    if (!--argc) return self;
    ++argv;
    return rb_obj_dig(argc, argv, self, Qnil);
}

static int
hash_le_i(VALUE key, VALUE value, VALUE arg)
{
    VALUE *args = (VALUE *)arg;
    VALUE v = rb_hash_lookup2(args[0], key, Qundef);
    if (!UNDEF_P(v) && rb_equal(value, v)) return ST_CONTINUE;
    args[1] = Qfalse;
    return ST_STOP;
}

static VALUE
hash_le(VALUE hash1, VALUE hash2)
{
    VALUE args[2];
    args[0] = hash2;
    args[1] = Qtrue;
    rb_hash_foreach(hash1, hash_le_i, (VALUE)args);
    return args[1];
}

/*
 *  call-seq:
 *    hash <= other_hash -> true or false
 *
 *  Returns +true+ if +hash+ is a subset of +other_hash+, +false+ otherwise:
 *    h1 = {foo: 0, bar: 1}
 *    h2 = {foo: 0, bar: 1, baz: 2}
 *    h1 <= h2 # => true
 *    h2 <= h1 # => false
 *    h1 <= h1 # => true
 */
static VALUE
rb_hash_le(VALUE hash, VALUE other)
{
    other = to_hash(other);
    if (RHASH_SIZE(hash) > RHASH_SIZE(other)) return Qfalse;
    return hash_le(hash, other);
}

/*
 *  call-seq:
 *    hash < other_hash -> true or false
 *
 *  Returns +true+ if +hash+ is a proper subset of +other_hash+, +false+ otherwise:
 *    h1 = {foo: 0, bar: 1}
 *    h2 = {foo: 0, bar: 1, baz: 2}
 *    h1 < h2 # => true
 *    h2 < h1 # => false
 *    h1 < h1 # => false
 */
static VALUE
rb_hash_lt(VALUE hash, VALUE other)
{
    other = to_hash(other);
    if (RHASH_SIZE(hash) >= RHASH_SIZE(other)) return Qfalse;
    return hash_le(hash, other);
}

/*
 *  call-seq:
 *    hash >= other_hash -> true or false
 *
 *  Returns +true+ if +hash+ is a superset of +other_hash+, +false+ otherwise:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1}
 *    h1 >= h2 # => true
 *    h2 >= h1 # => false
 *    h1 >= h1 # => true
 */
static VALUE
rb_hash_ge(VALUE hash, VALUE other)
{
    other = to_hash(other);
    if (RHASH_SIZE(hash) < RHASH_SIZE(other)) return Qfalse;
    return hash_le(other, hash);
}

/*
 *  call-seq:
 *    hash > other_hash -> true or false
 *
 *  Returns +true+ if +hash+ is a proper superset of +other_hash+, +false+ otherwise:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1}
 *    h1 > h2 # => true
 *    h2 > h1 # => false
 *    h1 > h1 # => false
 */
static VALUE
rb_hash_gt(VALUE hash, VALUE other)
{
    other = to_hash(other);
    if (RHASH_SIZE(hash) <= RHASH_SIZE(other)) return Qfalse;
    return hash_le(other, hash);
}

static VALUE
hash_proc_call(RB_BLOCK_CALL_FUNC_ARGLIST(key, hash))
{
    rb_check_arity(argc, 1, 1);
    return rb_hash_aref(hash, *argv);
}

/*
 *  call-seq:
 *    hash.to_proc -> proc
 *
 *  Returns a Proc object that maps a key to its value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    proc = h.to_proc
 *    proc.class # => Proc
 *    proc.call(:foo) # => 0
 *    proc.call(:bar) # => 1
 *    proc.call(:nosuch) # => nil
 */
static VALUE
rb_hash_to_proc(VALUE hash)
{
    return rb_func_lambda_new(hash_proc_call, hash, 1, 1);
}

/* :nodoc: */
static VALUE
rb_hash_deconstruct_keys(VALUE hash, VALUE keys)
{
    return hash;
}

static int
add_new_i(st_data_t *key, st_data_t *val, st_data_t arg, int existing)
{
    VALUE *args = (VALUE *)arg;
    if (existing) return ST_STOP;
    RB_OBJ_WRITTEN(args[0], Qundef, (VALUE)*key);
    RB_OBJ_WRITE(args[0], (VALUE *)val, args[1]);
    return ST_CONTINUE;
}

/*
 * add +key+ to +val+ pair if +hash+ does not contain +key+.
 * returns non-zero if +key+ was contained.
 */
int
rb_hash_add_new_element(VALUE hash, VALUE key, VALUE val)
{
    st_table *tbl;
    int ret = 0;
    VALUE args[2];
    args[0] = hash;
    args[1] = val;

    if (RHASH_AR_TABLE_P(hash)) {
        ret = ar_update(hash, (st_data_t)key, add_new_i, (st_data_t)args);
        if (ret != -1) {
            return ret;
        }
        ar_force_convert_table(hash, __FILE__, __LINE__);
    }

    tbl = RHASH_TBL_RAW(hash);
    return st_update(tbl, (st_data_t)key, add_new_i, (st_data_t)args);

}

static st_data_t
key_stringify(VALUE key)
{
    return (rb_obj_class(key) == rb_cString && !RB_OBJ_FROZEN(key)) ?
        rb_hash_key_str(key) : key;
}

static void
ar_bulk_insert(VALUE hash, long argc, const VALUE *argv)
{
    long i;
    for (i = 0; i < argc; ) {
        st_data_t k = key_stringify(argv[i++]);
        st_data_t v = argv[i++];
        ar_insert(hash, k, v);
        RB_OBJ_WRITTEN(hash, Qundef, k);
        RB_OBJ_WRITTEN(hash, Qundef, v);
    }
}

void
rb_hash_bulk_insert(long argc, const VALUE *argv, VALUE hash)
{
    HASH_ASSERT(argc % 2 == 0);
    if (argc > 0) {
        st_index_t size = argc / 2;

        if (RHASH_AR_TABLE_P(hash) &&
            (RHASH_AR_TABLE_SIZE(hash) + size <= RHASH_AR_TABLE_MAX_SIZE)) {
            ar_bulk_insert(hash, argc, argv);
        }
        else {
            rb_hash_bulk_insert_into_st_table(argc, argv, hash);
        }
    }
}

static char **origenviron;
#ifdef _WIN32
#define GET_ENVIRON(e) ((e) = rb_w32_get_environ())
#define FREE_ENVIRON(e) rb_w32_free_environ(e)
static char **my_environ;
#undef environ
#define environ my_environ
#undef getenv
#define getenv(n) rb_w32_ugetenv(n)
#elif defined(__APPLE__)
#undef environ
#define environ (*_NSGetEnviron())
#define GET_ENVIRON(e) (e)
#define FREE_ENVIRON(e)
#else
extern char **environ;
#define GET_ENVIRON(e) (e)
#define FREE_ENVIRON(e)
#endif
#ifdef ENV_IGNORECASE
#define ENVMATCH(s1, s2) (STRCASECMP((s1), (s2)) == 0)
#define ENVNMATCH(s1, s2, n) (STRNCASECMP((s1), (s2), (n)) == 0)
#else
#define ENVMATCH(n1, n2) (strcmp((n1), (n2)) == 0)
#define ENVNMATCH(s1, s2, n) (memcmp((s1), (s2), (n)) == 0)
#endif

#define ENV_LOCK()   RB_VM_LOCK_ENTER()
#define ENV_UNLOCK() RB_VM_LOCK_LEAVE()

static inline rb_encoding *
env_encoding(void)
{
#ifdef _WIN32
    return rb_utf8_encoding();
#else
    return rb_locale_encoding();
#endif
}

static VALUE
env_enc_str_new(const char *ptr, long len, rb_encoding *enc)
{
    VALUE str = rb_external_str_new_with_enc(ptr, len, enc);

    rb_obj_freeze(str);
    return str;
}

static VALUE
env_str_new(const char *ptr, long len)
{
    return env_enc_str_new(ptr, len, env_encoding());
}

static VALUE
env_str_new2(const char *ptr)
{
    if (!ptr) return Qnil;
    return env_str_new(ptr, strlen(ptr));
}

static VALUE
getenv_with_lock(const char *name)
{
    VALUE ret;
    ENV_LOCK();
    {
        const char *val = getenv(name);
        ret = env_str_new2(val);
    }
    ENV_UNLOCK();
    return ret;
}

static bool
has_env_with_lock(const char *name)
{
    const char *val;

    ENV_LOCK();
    {
        val = getenv(name);
    }
    ENV_UNLOCK();

    return val ? true : false;
}

static const char TZ_ENV[] = "TZ";

static void *
get_env_cstr(VALUE str, const char *name)
{
    char *var;
    rb_encoding *enc = rb_enc_get(str);
    if (!rb_enc_asciicompat(enc)) {
        rb_raise(rb_eArgError, "bad environment variable %s: ASCII incompatible encoding: %s",
                 name, rb_enc_name(enc));
    }
    var = RSTRING_PTR(str);
    if (memchr(var, '\0', RSTRING_LEN(str))) {
        rb_raise(rb_eArgError, "bad environment variable %s: contains null byte", name);
    }
    return rb_str_fill_terminator(str, 1); /* ASCII compatible */
}

#define get_env_ptr(var, val) \
    (var = get_env_cstr(val, #var))

static inline const char *
env_name(volatile VALUE *s)
{
    const char *name;
    StringValue(*s);
    get_env_ptr(name, *s);
    return name;
}

#define env_name(s) env_name(&(s))

static VALUE env_aset(VALUE nm, VALUE val);

static void
reset_by_modified_env(const char *nam, const char *val)
{
    /*
     * ENV['TZ'] = nil has a special meaning.
     * TZ is no longer considered up-to-date and ruby call tzset() as needed.
     * It could be useful if sysadmin change /etc/localtime.
     * This hack might works only on Linux glibc.
     */
    if (ENVMATCH(nam, TZ_ENV)) {
        ruby_reset_timezone(val);
    }
}

static VALUE
env_delete(VALUE name)
{
    const char *nam = env_name(name);
    reset_by_modified_env(nam, NULL);
    VALUE val = getenv_with_lock(nam);

    if (!NIL_P(val)) {
        ruby_setenv(nam, 0);
    }
    return val;
}

/*
 * call-seq:
 *   ENV.delete(name)                           -> value
 *   ENV.delete(name) { |name| block }          -> value
 *   ENV.delete(missing_name)                   -> nil
 *   ENV.delete(missing_name) { |name| block }  -> block_value
 *
 * Deletes the environment variable with +name+ if it exists and returns its value:
 *   ENV['foo'] = '0'
 *   ENV.delete('foo') # => '0'
 *
 * If a block is not given and the named environment variable does not exist, returns +nil+.
 *
 * If a block given and the environment variable does not exist,
 * yields +name+ to the block and returns the value of the block:
 *   ENV.delete('foo') { |name| name * 2 } # => "foofoo"
 *
 * If a block given and the environment variable exists,
 * deletes the environment variable and returns its value (ignoring the block):
 *   ENV['foo'] = '0'
 *   ENV.delete('foo') { |name| raise 'ignored' } # => "0"
 *
 * Raises an exception if +name+ is invalid.
 * See {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values].
 */
static VALUE
env_delete_m(VALUE obj, VALUE name)
{
    VALUE val;

    val = env_delete(name);
    if (NIL_P(val) && rb_block_given_p()) val = rb_yield(name);
    return val;
}

/*
 * call-seq:
 *   ENV[name] -> value
 *
 * Returns the value for the environment variable +name+ if it exists:
 *   ENV['foo'] = '0'
 *   ENV['foo'] # => "0"
 * Returns +nil+ if the named variable does not exist.
 *
 * Raises an exception if +name+ is invalid.
 * See {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values].
 */
static VALUE
rb_f_getenv(VALUE obj, VALUE name)
{
    const char *nam = env_name(name);
    VALUE env = getenv_with_lock(nam);
    return env;
}

/*
 * call-seq:
 *   ENV.fetch(name)                  -> value
 *   ENV.fetch(name, default)         -> value
 *   ENV.fetch(name) { |name| block } -> value
 *
 * If +name+ is the name of an environment variable, returns its value:
 *   ENV['foo'] = '0'
 *   ENV.fetch('foo') # => '0'
 * Otherwise if a block is given (but not a default value),
 * yields +name+ to the block and returns the block's return value:
 *   ENV.fetch('foo') { |name| :need_not_return_a_string } # => :need_not_return_a_string
 * Otherwise if a default value is given (but not a block), returns the default value:
 *   ENV.delete('foo')
 *   ENV.fetch('foo', :default_need_not_be_a_string) # => :default_need_not_be_a_string
 * If the environment variable does not exist and both default and block are given,
 * issues a warning ("warning: block supersedes default value argument"),
 * yields +name+ to the block, and returns the block's return value:
 *   ENV.fetch('foo', :default) { |name| :block_return } # => :block_return
 * Raises KeyError if +name+ is valid, but not found,
 * and neither default value nor block is given:
 *   ENV.fetch('foo') # Raises KeyError (key not found: "foo")
 * Raises an exception if +name+ is invalid.
 * See {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values].
 */
static VALUE
env_fetch(int argc, VALUE *argv, VALUE _)
{
    VALUE key;
    long block_given;
    const char *nam;
    VALUE env;

    rb_check_arity(argc, 1, 2);
    key = argv[0];
    block_given = rb_block_given_p();
    if (block_given && argc == 2) {
        rb_warn("block supersedes default value argument");
    }
    nam = env_name(key);
    env = getenv_with_lock(nam);

    if (NIL_P(env)) {
        if (block_given) return rb_yield(key);
        if (argc == 1) {
            rb_key_err_raise(rb_sprintf("key not found: \"%"PRIsVALUE"\"", key), envtbl, key);
        }
        return argv[1];
    }
    return env;
}

#if defined(_WIN32) || (defined(HAVE_SETENV) && defined(HAVE_UNSETENV))
#elif defined __sun
static int
in_origenv(const char *str)
{
    char **env;
    for (env = origenviron; *env; ++env) {
        if (*env == str) return 1;
    }
    return 0;
}
#else
static int
envix(const char *nam)
{
    // should be locked

    register int i, len = strlen(nam);
    char **env;

    env = GET_ENVIRON(environ);
    for (i = 0; env[i]; i++) {
        if (ENVNMATCH(env[i],nam,len) && env[i][len] == '=')
            break;			/* memcmp must come first to avoid */
    }					/* potential SEGV's */
    FREE_ENVIRON(environ);
    return i;
}
#endif

#if defined(_WIN32) || \
  (defined(__sun) && !(defined(HAVE_SETENV) && defined(HAVE_UNSETENV)))

NORETURN(static void invalid_envname(const char *name));

static void
invalid_envname(const char *name)
{
    rb_syserr_fail_str(EINVAL, rb_sprintf("ruby_setenv(%s)", name));
}

static const char *
check_envname(const char *name)
{
    if (strchr(name, '=')) {
        invalid_envname(name);
    }
    return name;
}
#endif

void
ruby_setenv(const char *name, const char *value)
{
#if defined(_WIN32)
    VALUE buf;
    WCHAR *wname;
    WCHAR *wvalue = 0;
    int failed = 0;
    int len;
    check_envname(name);
    len = MultiByteToWideChar(CP_UTF8, 0, name, -1, NULL, 0);
    if (value) {
        int len2;
        len2 = MultiByteToWideChar(CP_UTF8, 0, value, -1, NULL, 0);
        wname = ALLOCV_N(WCHAR, buf, len + len2);
        wvalue = wname + len;
        MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, len);
        MultiByteToWideChar(CP_UTF8, 0, value, -1, wvalue, len2);
    }
    else {
        wname = ALLOCV_N(WCHAR, buf, len + 1);
        MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, len);
        wvalue = wname + len;
        *wvalue = L'\0';
    }

    ENV_LOCK();
    {
        /* Use _wputenv_s() instead of SetEnvironmentVariableW() to make sure
         * special variables like "TZ" are interpret by libc. */
        failed = _wputenv_s(wname, wvalue);
    }
    ENV_UNLOCK();

    ALLOCV_END(buf);
    /* even if putenv() failed, clean up and try to delete the
     * variable from the system area. */
    if (!value || !*value) {
        /* putenv() doesn't handle empty value */
        if (!SetEnvironmentVariableW(wname, value ? wvalue : NULL) &&
            GetLastError() != ERROR_ENVVAR_NOT_FOUND) goto fail;
    }
    if (failed) {
      fail:
        invalid_envname(name);
    }
#elif defined(HAVE_SETENV) && defined(HAVE_UNSETENV)
    if (value) {
        int ret;
        ENV_LOCK();
        {
            ret = setenv(name, value, 1);
        }
        ENV_UNLOCK();

        if (ret) rb_sys_fail_sprintf("setenv(%s)", name);
    }
    else {
#ifdef VOID_UNSETENV
        ENV_LOCK();
        {
            unsetenv(name);
        }
        ENV_UNLOCK();
#else
        int ret;
        ENV_LOCK();
        {
            ret = unsetenv(name);
        }
        ENV_UNLOCK();

        if (ret) rb_sys_fail_sprintf("unsetenv(%s)", name);
#endif
    }
#elif defined __sun
    /* Solaris 9 (or earlier) does not have setenv(3C) and unsetenv(3C). */
    /* The below code was tested on Solaris 10 by:
         % ./configure ac_cv_func_setenv=no ac_cv_func_unsetenv=no
    */
    size_t len, mem_size;
    char **env_ptr, *str, *mem_ptr;

    check_envname(name);
    len = strlen(name);
    if (value) {
        mem_size = len + strlen(value) + 2;
        mem_ptr = malloc(mem_size);
        if (mem_ptr == NULL)
            rb_sys_fail_sprintf("malloc(%"PRIuSIZE")", mem_size);
        snprintf(mem_ptr, mem_size, "%s=%s", name, value);
    }

    ENV_LOCK();
    {
        for (env_ptr = GET_ENVIRON(environ); (str = *env_ptr) != 0; ++env_ptr) {
            if (!strncmp(str, name, len) && str[len] == '=') {
                if (!in_origenv(str)) free(str);
                while ((env_ptr[0] = env_ptr[1]) != 0) env_ptr++;
                break;
            }
        }
    }
    ENV_UNLOCK();

    if (value) {
        int ret;
        ENV_LOCK();
        {
            ret = putenv(mem_ptr);
        }
        ENV_UNLOCK();

        if (ret) {
            free(mem_ptr);
            rb_sys_fail_sprintf("putenv(%s)", name);
        }
    }
#else  /* WIN32 */
    size_t len;
    int i;

    ENV_LOCK();
    {
        i = envix(name);		/* where does it go? */

        if (environ == origenviron) {	/* need we copy environment? */
            int j;
            int max;
            char **tmpenv;

            for (max = i; environ[max]; max++) ;
            tmpenv = ALLOC_N(char*, max+2);
            for (j=0; j<max; j++)		/* copy environment */
                tmpenv[j] = ruby_strdup(environ[j]);
            tmpenv[max] = 0;
            environ = tmpenv;		/* tell exec where it is now */
        }

        if (environ[i]) {
            char **envp = origenviron;
            while (*envp && *envp != environ[i]) envp++;
            if (!*envp)
                xfree(environ[i]);
            if (!value) {
                while (environ[i]) {
                    environ[i] = environ[i+1];
                    i++;
                }
                goto finish;
            }
        }
        else {			/* does not exist yet */
            if (!value) goto finish;
            REALLOC_N(environ, char*, i+2);	/* just expand it a bit */
            environ[i+1] = 0;	/* make sure it's null terminated */
        }

        len = strlen(name) + strlen(value) + 2;
        environ[i] = ALLOC_N(char, len);
        snprintf(environ[i],len,"%s=%s",name,value); /* all that work just for this */

      finish:;
    }
    ENV_UNLOCK();
#endif /* WIN32 */
}

void
ruby_unsetenv(const char *name)
{
    ruby_setenv(name, 0);
}

/*
 * call-seq:
 *   ENV[name] = value      -> value
 *   ENV.store(name, value) -> value
 *
 * Creates, updates, or deletes the named environment variable, returning the value.
 * Both +name+ and +value+ may be instances of String.
 * See {Valid Names and Values}[rdoc-ref:ENV@Valid+Names+and+Values].
 *
 * - If the named environment variable does not exist:
 *   - If +value+ is +nil+, does nothing.
 *       ENV.clear
 *       ENV['foo'] = nil # => nil
 *       ENV.include?('foo') # => false
 *       ENV.store('bar', nil) # => nil
 *       ENV.include?('bar') # => false
 *   - If +value+ is not +nil+, creates the environment variable with +name+ and +value+:
 *       # Create 'foo' using ENV.[]=.
 *       ENV['foo'] = '0' # => '0'
 *       ENV['foo'] # => '0'
 *       # Create 'bar' using ENV.store.
 *       ENV.store('bar', '1') # => '1'
 *       ENV['bar'] # => '1'
 * - If the named environment variable exists:
 *   - If +value+ is not +nil+, updates the environment variable with value +value+:
 *       # Update 'foo' using ENV.[]=.
 *       ENV['foo'] = '2' # => '2'
 *       ENV['foo'] # => '2'
 *       # Update 'bar' using ENV.store.
 *       ENV.store('bar', '3') # => '3'
 *       ENV['bar'] # => '3'
 *   - If +value+ is +nil+, deletes the environment variable:
 *       # Delete 'foo' using ENV.[]=.
 *       ENV['foo'] = nil # => nil
 *       ENV.include?('foo') # => false
 *       # Delete 'bar' using ENV.store.
 *       ENV.store('bar', nil) # => nil
 *       ENV.include?('bar') # => false
 *
 * Raises an exception if +name+ or +value+ is invalid.
 * See {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values].
 */
static VALUE
env_aset_m(VALUE obj, VALUE nm, VALUE val)
{
    return env_aset(nm, val);
}

static VALUE
env_aset(VALUE nm, VALUE val)
{
    char *name, *value;

    if (NIL_P(val)) {
        env_delete(nm);
        return Qnil;
    }
    StringValue(nm);
    StringValue(val);
    /* nm can be modified in `val.to_str`, don't get `name` before
     * check for `val` */
    get_env_ptr(name, nm);
    get_env_ptr(value, val);

    ruby_setenv(name, value);
    reset_by_modified_env(name, value);
    return val;
}

static VALUE
env_keys(int raw)
{
    rb_encoding *enc = raw ? 0 : rb_locale_encoding();
    VALUE ary = rb_ary_new();

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        while (*env) {
            char *s = strchr(*env, '=');
            if (s) {
                const char *p = *env;
                size_t l = s - p;
                VALUE e = raw ? rb_utf8_str_new(p, l) : env_enc_str_new(p, l, enc);
                rb_ary_push(ary, e);
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return ary;
}

/*
 * call-seq:
 *   ENV.keys -> array of names
 *
 * Returns all variable names in an Array:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.keys # => ['bar', 'foo']
 * The order of the names is OS-dependent.
 * See {About Ordering}[rdoc-ref:ENV@About+Ordering].
 *
 * Returns the empty Array if ENV is empty.
 */

static VALUE
env_f_keys(VALUE _)
{
    return env_keys(FALSE);
}

static VALUE
rb_env_size(VALUE ehash, VALUE args, VALUE eobj)
{
    char **env;
    long cnt = 0;

    ENV_LOCK();
    {
        env = GET_ENVIRON(environ);
        for (; *env ; ++env) {
            if (strchr(*env, '=')) {
                cnt++;
            }
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return LONG2FIX(cnt);
}

/*
 * call-seq:
 *   ENV.each_key { |name| block } -> ENV
 *   ENV.each_key                  -> an_enumerator
 *
 * Yields each environment variable name:
 *   ENV.replace('foo' => '0', 'bar' => '1') # => ENV
 *   names = []
 *   ENV.each_key { |name| names.push(name) } # => ENV
 *   names # => ["bar", "foo"]
 *
 * Returns an Enumerator if no block given:
 *   e = ENV.each_key # => #<Enumerator: {"bar"=>"1", "foo"=>"0"}:each_key>
 *   names = []
 *   e.each { |name| names.push(name) } # => ENV
 *   names # => ["bar", "foo"]
 */
static VALUE
env_each_key(VALUE ehash)
{
    VALUE keys;
    long i;

    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);
    keys = env_keys(FALSE);
    for (i=0; i<RARRAY_LEN(keys); i++) {
        rb_yield(RARRAY_AREF(keys, i));
    }
    return ehash;
}

static VALUE
env_values(void)
{
    VALUE ary = rb_ary_new();

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);

        while (*env) {
            char *s = strchr(*env, '=');
            if (s) {
                rb_ary_push(ary, env_str_new2(s+1));
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return ary;
}

/*
 * call-seq:
 *   ENV.values -> array of values
 *
 * Returns all environment variable values in an Array:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.values # => ['1', '0']
 * The order of the values is OS-dependent.
 * See {About Ordering}[rdoc-ref:ENV@About+Ordering].
 *
 * Returns the empty Array if ENV is empty.
 */
static VALUE
env_f_values(VALUE _)
{
    return env_values();
}

/*
 * call-seq:
 *   ENV.each_value { |value| block } -> ENV
 *   ENV.each_value                   -> an_enumerator
 *
 * Yields each environment variable value:
 *   ENV.replace('foo' => '0', 'bar' => '1') # => ENV
 *   values = []
 *   ENV.each_value { |value| values.push(value) } # => ENV
 *   values # => ["1", "0"]
 *
 * Returns an Enumerator if no block given:
 *   e = ENV.each_value # => #<Enumerator: {"bar"=>"1", "foo"=>"0"}:each_value>
 *   values = []
 *   e.each { |value| values.push(value) } # => ENV
 *   values # => ["1", "0"]
 */
static VALUE
env_each_value(VALUE ehash)
{
    VALUE values;
    long i;

    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);
    values = env_values();
    for (i=0; i<RARRAY_LEN(values); i++) {
        rb_yield(RARRAY_AREF(values, i));
    }
    return ehash;
}

/*
 * call-seq:
 *   ENV.each      { |name, value| block } -> ENV
 *   ENV.each                              -> an_enumerator
 *   ENV.each_pair { |name, value| block } -> ENV
 *   ENV.each_pair                         -> an_enumerator
 *
 * Yields each environment variable name and its value as a 2-element Array:
 *   h = {}
 *   ENV.each_pair { |name, value| h[name] = value } # => ENV
 *   h # => {"bar"=>"1", "foo"=>"0"}
 *
 * Returns an Enumerator if no block given:
 *   h = {}
 *   e = ENV.each_pair # => #<Enumerator: {"bar"=>"1", "foo"=>"0"}:each_pair>
 *   e.each { |name, value| h[name] = value } # => ENV
 *   h # => {"bar"=>"1", "foo"=>"0"}
 */
static VALUE
env_each_pair(VALUE ehash)
{
    long i;

    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);

    VALUE ary = rb_ary_new();

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);

        while (*env) {
            char *s = strchr(*env, '=');
            if (s) {
                rb_ary_push(ary, env_str_new(*env, s-*env));
                rb_ary_push(ary, env_str_new2(s+1));
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    if (rb_block_pair_yield_optimizable()) {
        for (i=0; i<RARRAY_LEN(ary); i+=2) {
            rb_yield_values(2, RARRAY_AREF(ary, i), RARRAY_AREF(ary, i+1));
        }
    }
    else {
        for (i=0; i<RARRAY_LEN(ary); i+=2) {
            rb_yield(rb_assoc_new(RARRAY_AREF(ary, i), RARRAY_AREF(ary, i+1)));
        }
    }

    return ehash;
}

/*
 * call-seq:
 *   ENV.reject! { |name, value| block } -> ENV or nil
 *   ENV.reject!                         -> an_enumerator
 *
 * Similar to ENV.delete_if, but returns +nil+ if no changes were made.
 *
 * Yields each environment variable name and its value as a 2-element Array,
 * deleting each environment variable for which the block returns a truthy value,
 * and returning ENV (if any deletions) or +nil+ (if not):
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   ENV.reject! { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"foo"=>"0"}
 *   ENV.reject! { |name, value| name.start_with?('b') } # => nil
 *
 * Returns an Enumerator if no block given:
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   e = ENV.reject! # => #<Enumerator: {"bar"=>"1", "baz"=>"2", "foo"=>"0"}:reject!>
 *   e.each { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"foo"=>"0"}
 *   e.each { |name, value| name.start_with?('b') } # => nil
 */
static VALUE
env_reject_bang(VALUE ehash)
{
    VALUE keys;
    long i;
    int del = 0;

    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);
    keys = env_keys(FALSE);
    RBASIC_CLEAR_CLASS(keys);
    for (i=0; i<RARRAY_LEN(keys); i++) {
        VALUE val = rb_f_getenv(Qnil, RARRAY_AREF(keys, i));
        if (!NIL_P(val)) {
            if (RTEST(rb_yield_values(2, RARRAY_AREF(keys, i), val))) {
                env_delete(RARRAY_AREF(keys, i));
                del++;
            }
        }
    }
    RB_GC_GUARD(keys);
    if (del == 0) return Qnil;
    return envtbl;
}

/*
 * call-seq:
 *   ENV.delete_if { |name, value| block } -> ENV
 *   ENV.delete_if                         -> an_enumerator
 *
 * Yields each environment variable name and its value as a 2-element Array,
 * deleting each environment variable for which the block returns a truthy value,
 * and returning ENV (regardless of whether any deletions):
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   ENV.delete_if { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"foo"=>"0"}
 *   ENV.delete_if { |name, value| name.start_with?('b') } # => ENV
 *
 * Returns an Enumerator if no block given:
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   e = ENV.delete_if # => #<Enumerator: {"bar"=>"1", "baz"=>"2", "foo"=>"0"}:delete_if!>
 *   e.each { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"foo"=>"0"}
 *   e.each { |name, value| name.start_with?('b') } # => ENV
 */
static VALUE
env_delete_if(VALUE ehash)
{
    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);
    env_reject_bang(ehash);
    return envtbl;
}

/*
 * call-seq:
 *   ENV.values_at(*names) -> array of values
 *
 * Returns an Array containing the environment variable values associated with
 * the given names:
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   ENV.values_at('foo', 'baz') # => ["0", "2"]
 *
 * Returns +nil+ in the Array for each name that is not an ENV name:
 *   ENV.values_at('foo', 'bat', 'bar', 'bam') # => ["0", nil, "1", nil]
 *
 * Returns an empty Array if no names given.
 *
 * Raises an exception if any name is invalid.
 * See {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values].
 */
static VALUE
env_values_at(int argc, VALUE *argv, VALUE _)
{
    VALUE result;
    long i;

    result = rb_ary_new();
    for (i=0; i<argc; i++) {
        rb_ary_push(result, rb_f_getenv(Qnil, argv[i]));
    }
    return result;
}

/*
 * call-seq:
 *   ENV.select { |name, value| block } -> hash of name/value pairs
 *   ENV.select                         -> an_enumerator
 *   ENV.filter { |name, value| block } -> hash of name/value pairs
 *   ENV.filter                         -> an_enumerator
 *
 * Yields each environment variable name and its value as a 2-element Array,
 * returning a Hash of the names and values for which the block returns a truthy value:
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   ENV.select { |name, value| name.start_with?('b') } # => {"bar"=>"1", "baz"=>"2"}
 *   ENV.filter { |name, value| name.start_with?('b') } # => {"bar"=>"1", "baz"=>"2"}
 *
 * Returns an Enumerator if no block given:
 *   e = ENV.select # => #<Enumerator: {"bar"=>"1", "baz"=>"2", "foo"=>"0"}:select>
 *   e.each { |name, value | name.start_with?('b') } # => {"bar"=>"1", "baz"=>"2"}
 *   e = ENV.filter # => #<Enumerator: {"bar"=>"1", "baz"=>"2", "foo"=>"0"}:filter>
 *   e.each { |name, value | name.start_with?('b') } # => {"bar"=>"1", "baz"=>"2"}
 */
static VALUE
env_select(VALUE ehash)
{
    VALUE result;
    VALUE keys;
    long i;

    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);
    result = rb_hash_new();
    keys = env_keys(FALSE);
    for (i = 0; i < RARRAY_LEN(keys); ++i) {
        VALUE key = RARRAY_AREF(keys, i);
        VALUE val = rb_f_getenv(Qnil, key);
        if (!NIL_P(val)) {
            if (RTEST(rb_yield_values(2, key, val))) {
                rb_hash_aset(result, key, val);
            }
        }
    }
    RB_GC_GUARD(keys);

    return result;
}

/*
 * call-seq:
 *   ENV.select! { |name, value| block } -> ENV or nil
 *   ENV.select!                         -> an_enumerator
 *   ENV.filter! { |name, value| block } -> ENV or nil
 *   ENV.filter!                         -> an_enumerator
 *
 * Yields each environment variable name and its value as a 2-element Array,
 * deleting each entry for which the block returns +false+ or +nil+,
 * and returning ENV if any deletions made, or +nil+ otherwise:
 *
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   ENV.select! { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"bar"=>"1", "baz"=>"2"}
 *   ENV.select! { |name, value| true } # => nil
 *
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   ENV.filter! { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"bar"=>"1", "baz"=>"2"}
 *   ENV.filter! { |name, value| true } # => nil
 *
 * Returns an Enumerator if no block given:
 *
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   e = ENV.select! # => #<Enumerator: {"bar"=>"1", "baz"=>"2"}:select!>
 *   e.each { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"bar"=>"1", "baz"=>"2"}
 *   e.each { |name, value| true } # => nil
 *
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   e = ENV.filter! # => #<Enumerator: {"bar"=>"1", "baz"=>"2"}:filter!>
 *   e.each { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"bar"=>"1", "baz"=>"2"}
 *   e.each { |name, value| true } # => nil
 */
static VALUE
env_select_bang(VALUE ehash)
{
    VALUE keys;
    long i;
    int del = 0;

    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);
    keys = env_keys(FALSE);
    RBASIC_CLEAR_CLASS(keys);
    for (i=0; i<RARRAY_LEN(keys); i++) {
        VALUE val = rb_f_getenv(Qnil, RARRAY_AREF(keys, i));
        if (!NIL_P(val)) {
            if (!RTEST(rb_yield_values(2, RARRAY_AREF(keys, i), val))) {
                env_delete(RARRAY_AREF(keys, i));
                del++;
            }
        }
    }
    RB_GC_GUARD(keys);
    if (del == 0) return Qnil;
    return envtbl;
}

/*
 * call-seq:
 *   ENV.keep_if { |name, value| block } -> ENV
 *   ENV.keep_if                         -> an_enumerator
 *
 * Yields each environment variable name and its value as a 2-element Array,
 * deleting each environment variable for which the block returns +false+ or +nil+,
 * and returning ENV:
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   ENV.keep_if { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"bar"=>"1", "baz"=>"2"}
 *
 * Returns an Enumerator if no block given:
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   e = ENV.keep_if # => #<Enumerator: {"bar"=>"1", "baz"=>"2", "foo"=>"0"}:keep_if>
 *   e.each { |name, value| name.start_with?('b') } # => ENV
 *   ENV # => {"bar"=>"1", "baz"=>"2"}
 */
static VALUE
env_keep_if(VALUE ehash)
{
    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);
    env_select_bang(ehash);
    return envtbl;
}

/*
 * call-seq:
 *   ENV.slice(*names) -> hash of name/value pairs
 *
 * Returns a Hash of the given ENV names and their corresponding values:
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2', 'bat' => '3')
 *   ENV.slice('foo', 'baz') # => {"foo"=>"0", "baz"=>"2"}
 *   ENV.slice('baz', 'foo') # => {"baz"=>"2", "foo"=>"0"}
 * Raises an exception if any of the +names+ is invalid
 * (see {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values]):
 *   ENV.slice('foo', 'bar', :bat) # Raises TypeError (no implicit conversion of Symbol into String)
 */
static VALUE
env_slice(int argc, VALUE *argv, VALUE _)
{
    int i;
    VALUE key, value, result;

    if (argc == 0) {
        return rb_hash_new();
    }
    result = rb_hash_new_with_size(argc);

    for (i = 0; i < argc; i++) {
        key = argv[i];
        value = rb_f_getenv(Qnil, key);
        if (value != Qnil)
            rb_hash_aset(result, key, value);
    }

    return result;
}

VALUE
rb_env_clear(void)
{
    VALUE keys;
    long i;

    keys = env_keys(TRUE);
    for (i=0; i<RARRAY_LEN(keys); i++) {
        VALUE key = RARRAY_AREF(keys, i);
        const char *nam = RSTRING_PTR(key);
        ruby_setenv(nam, 0);
    }
    RB_GC_GUARD(keys);
    return envtbl;
}

/*
 * call-seq:
 *   ENV.clear -> ENV
 *
 * Removes every environment variable; returns ENV:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.size # => 2
 *   ENV.clear # => ENV
 *   ENV.size # => 0
 */
static VALUE
env_clear(VALUE _)
{
    return rb_env_clear();
}

/*
 * call-seq:
 *   ENV.to_s -> "ENV"
 *
 * Returns String 'ENV':
 *   ENV.to_s # => "ENV"
 */
static VALUE
env_to_s(VALUE _)
{
    return rb_usascii_str_new2("ENV");
}

/*
 * call-seq:
 *   ENV.inspect -> a_string
 *
 * Returns the contents of the environment as a String:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.inspect # => "{\"bar\"=>\"1\", \"foo\"=>\"0\"}"
 */
static VALUE
env_inspect(VALUE _)
{
    VALUE str = rb_str_buf_new2("{");
    rb_encoding *enc = env_encoding();

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        while (*env) {
            const char *s = strchr(*env, '=');

            if (env != environ) {
                rb_str_buf_cat2(str, ", ");
            }
            if (s) {
                rb_str_buf_append(str, rb_str_inspect(env_enc_str_new(*env, s-*env, enc)));
                rb_str_buf_cat2(str, " => ");
                s++;
                rb_str_buf_append(str, rb_str_inspect(env_enc_str_new(s, strlen(s), enc)));
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    rb_str_buf_cat2(str, "}");

    return str;
}

/*
 * call-seq:
 *   ENV.to_a -> array of 2-element arrays
 *
 * Returns the contents of ENV as an Array of 2-element Arrays,
 * each of which is a name/value pair:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.to_a # => [["bar", "1"], ["foo", "0"]]
 */
static VALUE
env_to_a(VALUE _)
{
    VALUE ary = rb_ary_new();

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        while (*env) {
            char *s = strchr(*env, '=');
            if (s) {
                rb_ary_push(ary, rb_assoc_new(env_str_new(*env, s-*env),
                                              env_str_new2(s+1)));
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return ary;
}

/*
 * call-seq:
 *   ENV.rehash -> nil
 *
 * (Provided for compatibility with Hash.)
 *
 * Does not modify ENV; returns +nil+.
 */
static VALUE
env_none(VALUE _)
{
    return Qnil;
}

static int
env_size_with_lock(void)
{
    int i = 0;

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        while (env[i]) i++;
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return i;
}

/*
 * call-seq:
 *   ENV.length -> an_integer
 *   ENV.size   -> an_integer
 *
 * Returns the count of environment variables:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.length # => 2
 *   ENV.size # => 2
 */
static VALUE
env_size(VALUE _)
{
    return INT2FIX(env_size_with_lock());
}

/*
 * call-seq:
 *   ENV.empty? -> true or false
 *
 * Returns +true+ when there are no environment variables, +false+ otherwise:
 *   ENV.clear
 *   ENV.empty? # => true
 *   ENV['foo'] = '0'
 *   ENV.empty? # => false
 */
static VALUE
env_empty_p(VALUE _)
{
    bool empty = true;

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        if (env[0] != 0) {
            empty = false;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return RBOOL(empty);
}

/*
 * call-seq:
 *   ENV.include?(name) -> true or false
 *   ENV.has_key?(name) -> true or false
 *   ENV.member?(name)  -> true or false
 *   ENV.key?(name)     -> true or false
 *
 * Returns +true+ if there is an environment variable with the given +name+:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.include?('foo') # => true
 * Returns +false+ if +name+ is a valid String and there is no such environment variable:
 *   ENV.include?('baz') # => false
 * Returns +false+ if +name+ is the empty String or is a String containing character <code>'='</code>:
 *   ENV.include?('') # => false
 *   ENV.include?('=') # => false
 * Raises an exception if +name+ is a String containing the NUL character <code>"\0"</code>:
 *   ENV.include?("\0") # Raises ArgumentError (bad environment variable name: contains null byte)
 * Raises an exception if +name+ has an encoding that is not ASCII-compatible:
 *   ENV.include?("\xa1\xa1".force_encoding(Encoding::UTF_16LE))
 *   # Raises ArgumentError (bad environment variable name: ASCII incompatible encoding: UTF-16LE)
 * Raises an exception if +name+ is not a String:
 *   ENV.include?(Object.new) # TypeError (no implicit conversion of Object into String)
 */
static VALUE
env_has_key(VALUE env, VALUE key)
{
    const char *s = env_name(key);
    return RBOOL(has_env_with_lock(s));
}

/*
 * call-seq:
 *   ENV.assoc(name) -> [name, value] or nil
 *
 * Returns a 2-element Array containing the name and value of the environment variable
 * for +name+ if it exists:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.assoc('foo') # => ['foo', '0']
 * Returns +nil+ if +name+ is a valid String and there is no such environment variable.
 *
 * Returns +nil+ if +name+ is the empty String or is a String containing character <code>'='</code>.
 *
 * Raises an exception if +name+ is a String containing the NUL character <code>"\0"</code>:
 *   ENV.assoc("\0") # Raises ArgumentError (bad environment variable name: contains null byte)
 * Raises an exception if +name+ has an encoding that is not ASCII-compatible:
 *   ENV.assoc("\xa1\xa1".force_encoding(Encoding::UTF_16LE))
 *   # Raises ArgumentError (bad environment variable name: ASCII incompatible encoding: UTF-16LE)
 * Raises an exception if +name+ is not a String:
 *   ENV.assoc(Object.new) # TypeError (no implicit conversion of Object into String)
 */
static VALUE
env_assoc(VALUE env, VALUE key)
{
    const char *s = env_name(key);
    VALUE e = getenv_with_lock(s);

    if (!NIL_P(e)) {
        return rb_assoc_new(key, e);
    }
    else {
        return Qnil;
    }
}

/*
 * call-seq:
 *   ENV.value?(value)     -> true or false
 *   ENV.has_value?(value) -> true or false
 *
 * Returns +true+ if +value+ is the value for some environment variable name, +false+ otherwise:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.value?('0') # => true
 *   ENV.has_value?('0') # => true
 *   ENV.value?('2') # => false
 *   ENV.has_value?('2') # => false
 */
static VALUE
env_has_value(VALUE dmy, VALUE obj)
{
    obj = rb_check_string_type(obj);
    if (NIL_P(obj)) return Qnil;

    VALUE ret = Qfalse;

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        while (*env) {
            char *s = strchr(*env, '=');
            if (s++) {
                long len = strlen(s);
                if (RSTRING_LEN(obj) == len && strncmp(s, RSTRING_PTR(obj), len) == 0) {
                    ret = Qtrue;
                    break;
                }
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return ret;
}

/*
 * call-seq:
 *   ENV.rassoc(value) -> [name, value] or nil
 *
 * Returns a 2-element Array containing the name and value of the
 * *first* *found* environment variable that has value +value+, if one
 * exists:
 *   ENV.replace('foo' => '0', 'bar' => '0')
 *   ENV.rassoc('0') # => ["bar", "0"]
 * The order in which environment variables are examined is OS-dependent.
 * See {About Ordering}[rdoc-ref:ENV@About+Ordering].
 *
 * Returns +nil+ if there is no such environment variable.
 */
static VALUE
env_rassoc(VALUE dmy, VALUE obj)
{
    obj = rb_check_string_type(obj);
    if (NIL_P(obj)) return Qnil;

    VALUE result = Qnil;

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);

        while (*env) {
            const char *p = *env;
            char *s = strchr(p, '=');
            if (s++) {
                long len = strlen(s);
                if (RSTRING_LEN(obj) == len && strncmp(s, RSTRING_PTR(obj), len) == 0) {
                    result = rb_assoc_new(rb_str_new(p, s-p-1), obj);
                    break;
                }
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return result;
}

/*
 * call-seq:
 *   ENV.key(value) -> name or nil
 *
 * Returns the name of the first environment variable with +value+, if it exists:
 *   ENV.replace('foo' => '0', 'bar' => '0')
 *   ENV.key('0') # => "foo"
 * The order in which environment variables are examined is OS-dependent.
 * See {About Ordering}[rdoc-ref:ENV@About+Ordering].
 *
 * Returns +nil+ if there is no such value.
 *
 * Raises an exception if +value+ is invalid:
 *   ENV.key(Object.new) # raises TypeError (no implicit conversion of Object into String)
 * See {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values].
 */
static VALUE
env_key(VALUE dmy, VALUE value)
{
    StringValue(value);
    VALUE str = Qnil;

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        while (*env) {
            char *s = strchr(*env, '=');
            if (s++) {
                long len = strlen(s);
                if (RSTRING_LEN(value) == len && strncmp(s, RSTRING_PTR(value), len) == 0) {
                    str = env_str_new(*env, s-*env-1);
                    break;
                }
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return str;
}

static VALUE
env_to_hash(void)
{
    VALUE hash = rb_hash_new();

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        while (*env) {
            char *s = strchr(*env, '=');
            if (s) {
                rb_hash_aset(hash, env_str_new(*env, s-*env),
                             env_str_new2(s+1));
            }
            env++;
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    return hash;
}

VALUE
rb_envtbl(void)
{
    return envtbl;
}

VALUE
rb_env_to_hash(void)
{
    return env_to_hash();
}

/*
 * call-seq:
 *   ENV.to_hash -> hash of name/value pairs
 *
 * Returns a Hash containing all name/value pairs from ENV:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.to_hash # => {"bar"=>"1", "foo"=>"0"}
 */

static VALUE
env_f_to_hash(VALUE _)
{
    return env_to_hash();
}

/*
 * call-seq:
 *   ENV.to_h                        -> hash of name/value pairs
 *   ENV.to_h {|name, value| block } -> hash of name/value pairs
 *
 * With no block, returns a Hash containing all name/value pairs from ENV:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.to_h # => {"bar"=>"1", "foo"=>"0"}
 * With a block, returns a Hash whose items are determined by the block.
 * Each name/value pair in ENV is yielded to the block.
 * The block must return a 2-element Array (name/value pair)
 * that is added to the return Hash as a key and value:
 *   ENV.to_h { |name, value| [name.to_sym, value.to_i] } # => {:bar=>1, :foo=>0}
 * Raises an exception if the block does not return an Array:
 *   ENV.to_h { |name, value| name } # Raises TypeError (wrong element type String (expected array))
 * Raises an exception if the block returns an Array of the wrong size:
 *   ENV.to_h { |name, value| [name] } # Raises ArgumentError (element has wrong array length (expected 2, was 1))
 */
static VALUE
env_to_h(VALUE _)
{
    VALUE hash = env_to_hash();
    if (rb_block_given_p()) {
        hash = rb_hash_to_h_block(hash);
    }
    return hash;
}

/*
 *  call-seq:
 *     ENV.except(*keys) -> a_hash
 *
 *  Returns a hash except the given keys from ENV and their values.
 *
 *     ENV                       #=> {"LANG"=>"en_US.UTF-8", "TERM"=>"xterm-256color", "HOME"=>"/Users/rhc"}
 *     ENV.except("TERM","HOME") #=> {"LANG"=>"en_US.UTF-8"}
 */
static VALUE
env_except(int argc, VALUE *argv, VALUE _)
{
    int i;
    VALUE key, hash = env_to_hash();

    for (i = 0; i < argc; i++) {
        key = argv[i];
        rb_hash_delete(hash, key);
    }

    return hash;
}

/*
 * call-seq:
 *   ENV.reject { |name, value| block } -> hash of name/value pairs
 *   ENV.reject                         -> an_enumerator
 *
 * Yields each environment variable name and its value as a 2-element Array.
 * Returns a Hash whose items are determined by the block.
 * When the block returns a truthy value, the name/value pair is added to the return Hash;
 * otherwise the pair is ignored:
 *   ENV.replace('foo' => '0', 'bar' => '1', 'baz' => '2')
 *   ENV.reject { |name, value| name.start_with?('b') } # => {"foo"=>"0"}
 * Returns an Enumerator if no block given:
 *   e = ENV.reject
 *   e.each { |name, value| name.start_with?('b') } # => {"foo"=>"0"}
 */
static VALUE
env_reject(VALUE _)
{
    return rb_hash_delete_if(env_to_hash());
}

NORETURN(static VALUE env_freeze(VALUE self));
/*
 * call-seq:
 *   ENV.freeze
 *
 * Raises an exception:
 *   ENV.freeze # Raises TypeError (cannot freeze ENV)
 */
static VALUE
env_freeze(VALUE self)
{
    rb_raise(rb_eTypeError, "cannot freeze ENV");
    UNREACHABLE_RETURN(self);
}

/*
 * call-seq:
 *   ENV.shift -> [name, value] or nil
 *
 * Removes the first environment variable from ENV and returns
 * a 2-element Array containing its name and value:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.to_hash # => {'bar' => '1', 'foo' => '0'}
 *   ENV.shift # => ['bar', '1']
 *   ENV.to_hash # => {'foo' => '0'}
 * Exactly which environment variable is "first" is OS-dependent.
 * See {About Ordering}[rdoc-ref:ENV@About+Ordering].
 *
 * Returns +nil+ if the environment is empty.
 */
static VALUE
env_shift(VALUE _)
{
    VALUE result = Qnil;
    VALUE key = Qnil;

    ENV_LOCK();
    {
        char **env = GET_ENVIRON(environ);
        if (*env) {
            const char *p = *env;
            char *s = strchr(p, '=');
            if (s) {
                key = env_str_new(p, s-p);
                VALUE val = env_str_new2(getenv(RSTRING_PTR(key)));
                result = rb_assoc_new(key, val);
            }
        }
        FREE_ENVIRON(environ);
    }
    ENV_UNLOCK();

    if (!NIL_P(key)) {
        env_delete(key);
    }

    return result;
}

/*
 * call-seq:
 *   ENV.invert -> hash of value/name pairs
 *
 * Returns a Hash whose keys are the ENV values,
 * and whose values are the corresponding ENV names:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.invert # => {"1"=>"bar", "0"=>"foo"}
 * For a duplicate ENV value, overwrites the hash entry:
 *   ENV.replace('foo' => '0', 'bar' => '0')
 *   ENV.invert # => {"0"=>"foo"}
 * Note that the order of the ENV processing is OS-dependent,
 * which means that the order of overwriting is also OS-dependent.
 * See {About Ordering}[rdoc-ref:ENV@About+Ordering].
 */
static VALUE
env_invert(VALUE _)
{
    return rb_hash_invert(env_to_hash());
}

static void
keylist_delete(VALUE keys, VALUE key)
{
    long keylen, elen;
    const char *keyptr, *eptr;
    RSTRING_GETMEM(key, keyptr, keylen);
    /* Don't stop at first key, as it is possible to have
       multiple environment values with the same key.
    */
    for (long i=0; i<RARRAY_LEN(keys); i++) {
        VALUE e = RARRAY_AREF(keys, i);
        RSTRING_GETMEM(e, eptr, elen);
        if (elen != keylen) continue;
        if (!ENVNMATCH(keyptr, eptr, elen)) continue;
        rb_ary_delete_at(keys, i);
        i--;
    }
}

static int
env_replace_i(VALUE key, VALUE val, VALUE keys)
{
    env_name(key);
    env_aset(key, val);

    keylist_delete(keys, key);
    return ST_CONTINUE;
}

/*
 * call-seq:
 *   ENV.replace(hash) -> ENV
 *
 * Replaces the entire content of the environment variables
 * with the name/value pairs in the given +hash+;
 * returns ENV.
 *
 * Replaces the content of ENV with the given pairs:
 *   ENV.replace('foo' => '0', 'bar' => '1') # => ENV
 *   ENV.to_hash # => {"bar"=>"1", "foo"=>"0"}
 *
 * Raises an exception if a name or value is invalid
 * (see {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values]):
 *   ENV.replace('foo' => '0', :bar => '1') # Raises TypeError (no implicit conversion of Symbol into String)
 *   ENV.replace('foo' => '0', 'bar' => 1) # Raises TypeError (no implicit conversion of Integer into String)
 *   ENV.to_hash # => {"bar"=>"1", "foo"=>"0"}
 */
static VALUE
env_replace(VALUE env, VALUE hash)
{
    VALUE keys;
    long i;

    keys = env_keys(TRUE);
    if (env == hash) return env;
    hash = to_hash(hash);
    rb_hash_foreach(hash, env_replace_i, keys);

    for (i=0; i<RARRAY_LEN(keys); i++) {
        env_delete(RARRAY_AREF(keys, i));
    }
    RB_GC_GUARD(keys);
    return env;
}

static int
env_update_i(VALUE key, VALUE val, VALUE _)
{
    env_aset(key, val);
    return ST_CONTINUE;
}

static int
env_update_block_i(VALUE key, VALUE val, VALUE _)
{
    VALUE oldval = rb_f_getenv(Qnil, key);
    if (!NIL_P(oldval)) {
        val = rb_yield_values(3, key, oldval, val);
    }
    env_aset(key, val);
    return ST_CONTINUE;
}

/*
 * call-seq:
 *   ENV.update                                              -> ENV
 *   ENV.update(*hashes)                                     -> ENV
 *   ENV.update(*hashes) { |name, env_val, hash_val| block } -> ENV
 *   ENV.merge!                                              -> ENV
 *   ENV.merge!(*hashes)                                     -> ENV
 *   ENV.merge!(*hashes) { |name, env_val, hash_val| block } -> ENV
 *
 * Adds to ENV each key/value pair in the given +hash+; returns ENV:
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.merge!('baz' => '2', 'bat' => '3') # => {"bar"=>"1", "bat"=>"3", "baz"=>"2", "foo"=>"0"}
 * Deletes the ENV entry for a hash value that is +nil+:
 *   ENV.merge!('baz' => nil, 'bat' => nil) # => {"bar"=>"1", "foo"=>"0"}
 * For an already-existing name, if no block given, overwrites the ENV value:
 *   ENV.merge!('foo' => '4') # => {"bar"=>"1", "foo"=>"4"}
 * For an already-existing name, if block given,
 * yields the name, its ENV value, and its hash value;
 * the block's return value becomes the new name:
 *   ENV.merge!('foo' => '5') { |name, env_val, hash_val | env_val + hash_val } # => {"bar"=>"1", "foo"=>"45"}
 * Raises an exception if a name or value is invalid
 * (see {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values]);
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.merge!('foo' => '6', :bar => '7', 'baz' => '9') # Raises TypeError (no implicit conversion of Symbol into String)
 *   ENV # => {"bar"=>"1", "foo"=>"6"}
 *   ENV.merge!('foo' => '7', 'bar' => 8, 'baz' => '9') # Raises TypeError (no implicit conversion of Integer into String)
 *   ENV # => {"bar"=>"1", "foo"=>"7"}
 * Raises an exception if the block returns an invalid name:
 * (see {Invalid Names and Values}[rdoc-ref:ENV@Invalid+Names+and+Values]):
 *   ENV.merge!('bat' => '8', 'foo' => '9') { |name, env_val, hash_val | 10 } # Raises TypeError (no implicit conversion of Integer into String)
 *   ENV # => {"bar"=>"1", "bat"=>"8", "foo"=>"7"}
 *
 * Note that for the exceptions above,
 * hash pairs preceding an invalid name or value are processed normally;
 * those following are ignored.
 */
static VALUE
env_update(int argc, VALUE *argv, VALUE env)
{
    rb_foreach_func *func = rb_block_given_p() ?
        env_update_block_i : env_update_i;
    for (int i = 0; i < argc; ++i) {
        VALUE hash = argv[i];
        if (env == hash) continue;
        hash = to_hash(hash);
        rb_hash_foreach(hash, func, 0);
    }
    return env;
}

NORETURN(static VALUE env_clone(int, VALUE *, VALUE));
/*
 * call-seq:
 *   ENV.clone(freeze: nil) # raises TypeError
 *
 * Raises TypeError, because ENV is a wrapper for the process-wide
 * environment variables and a clone is useless.
 * Use #to_h to get a copy of ENV data as a hash.
 */
static VALUE
env_clone(int argc, VALUE *argv, VALUE obj)
{
    if (argc) {
        VALUE opt;
        if (rb_scan_args(argc, argv, "0:", &opt) < argc) {
            rb_get_freeze_opt(1, &opt);
        }
    }

    rb_raise(rb_eTypeError, "Cannot clone ENV, use ENV.to_h to get a copy of ENV as a hash");
}

NORETURN(static VALUE env_dup(VALUE));
/*
 * call-seq:
 *   ENV.dup # raises TypeError
 *
 * Raises TypeError, because ENV is a singleton object.
 * Use #to_h to get a copy of ENV data as a hash.
 */
static VALUE
env_dup(VALUE obj)
{
    rb_raise(rb_eTypeError, "Cannot dup ENV, use ENV.to_h to get a copy of ENV as a hash");
}

static const rb_data_type_t env_data_type = {
    "ENV",
    {
        NULL,
        NULL,
        NULL,
        NULL,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};

/*
 *  A +Hash+ maps each of its unique keys to a specific value.
 *
 *  A +Hash+ has certain similarities to an Array, but:
 *  - An Array index is always an Integer.
 *  - A +Hash+ key can be (almost) any object.
 *
 *  === +Hash+ \Data Syntax
 *
 *  The older syntax for +Hash+ data uses the "hash rocket," <tt>=></tt>:
 *
 *    h = {:foo => 0, :bar => 1, :baz => 2}
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  Alternatively, but only for a +Hash+ key that's a Symbol,
 *  you can use a newer JSON-style syntax,
 *  where each bareword becomes a Symbol:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  You can also use a String in place of a bareword:
 *
 *    h = {'foo': 0, 'bar': 1, 'baz': 2}
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  And you can mix the styles:
 *
 *    h = {foo: 0, :bar => 1, 'baz': 2}
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  But it's an error to try the JSON-style syntax
 *  for a key that's not a bareword or a String:
 *
 *    # Raises SyntaxError (syntax error, unexpected ':', expecting =>):
 *    h = {0: 'zero'}
 *
 *  +Hash+ value can be omitted, meaning that value will be fetched from the context
 *  by the name of the key:
 *
 *    x = 0
 *    y = 100
 *    h = {x:, y:}
 *    h # => {:x=>0, :y=>100}
 *
 *  === Common Uses
 *
 *  You can use a +Hash+ to give names to objects:
 *
 *    person = {name: 'Matz', language: 'Ruby'}
 *    person # => {:name=>"Matz", :language=>"Ruby"}
 *
 *  You can use a +Hash+ to give names to method arguments:
 *
 *    def some_method(hash)
 *      p hash
 *    end
 *    some_method({foo: 0, bar: 1, baz: 2}) # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  Note: when the last argument in a method call is a +Hash+,
 *  the curly braces may be omitted:
 *
 *    some_method(foo: 0, bar: 1, baz: 2) # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  You can use a +Hash+ to initialize an object:
 *
 *    class Dev
 *      attr_accessor :name, :language
 *      def initialize(hash)
 *        self.name = hash[:name]
 *        self.language = hash[:language]
 *      end
 *    end
 *    matz = Dev.new(name: 'Matz', language: 'Ruby')
 *    matz # => #<Dev: @name="Matz", @language="Ruby">
 *
 *  === Creating a +Hash+
 *
 *  You can create a +Hash+ object explicitly with:
 *
 *  - A {hash literal}[rdoc-ref:syntax/literals.rdoc@Hash+Literals].
 *
 *  You can convert certain objects to Hashes with:
 *
 *  - \Method #Hash.
 *
 *  You can create a +Hash+ by calling method Hash.new.
 *
 *  Create an empty +Hash+:
 *
 *    h = Hash.new
 *    h # => {}
 *    h.class # => Hash
 *
 *  You can create a +Hash+ by calling method Hash.[].
 *
 *  Create an empty +Hash+:
 *
 *    h = Hash[]
 *    h # => {}
 *
 *  Create a +Hash+ with initial entries:
 *
 *    h = Hash[foo: 0, bar: 1, baz: 2]
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  You can create a +Hash+ by using its literal form (curly braces).
 *
 *  Create an empty +Hash+:
 *
 *    h = {}
 *    h # => {}
 *
 *  Create a +Hash+ with initial entries:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *
 *  === +Hash+ Value Basics
 *
 *  The simplest way to retrieve a +Hash+ value (instance method #[]):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:foo] # => 0
 *
 *  The simplest way to create or update a +Hash+ value (instance method #[]=):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:bat] = 3 # => 3
 *    h # => {:foo=>0, :bar=>1, :baz=>2, :bat=>3}
 *    h[:foo] = 4 # => 4
 *    h # => {:foo=>4, :bar=>1, :baz=>2, :bat=>3}
 *
 *  The simplest way to delete a +Hash+ entry (instance method #delete):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:bar) # => 1
 *    h # => {:foo=>0, :baz=>2}
 *
 *  === Entry Order
 *
 *  A +Hash+ object presents its entries in the order of their creation. This is seen in:
 *
 *  - Iterative methods such as <tt>each</tt>, <tt>each_key</tt>, <tt>each_pair</tt>, <tt>each_value</tt>.
 *  - Other order-sensitive methods such as <tt>shift</tt>, <tt>keys</tt>, <tt>values</tt>.
 *  - The String returned by method <tt>inspect</tt>.
 *
 *  A new +Hash+ has its initial ordering per the given entries:
 *
 *    h = Hash[foo: 0, bar: 1]
 *    h # => {:foo=>0, :bar=>1}
 *
 *  New entries are added at the end:
 *
 *    h[:baz] = 2
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  Updating a value does not affect the order:
 *
 *    h[:baz] = 3
 *    h # => {:foo=>0, :bar=>1, :baz=>3}
 *
 *  But re-creating a deleted entry can affect the order:
 *
 *    h.delete(:foo)
 *    h[:foo] = 5
 *    h # => {:bar=>1, :baz=>3, :foo=>5}
 *
 *  === +Hash+ Keys
 *
 *  ==== +Hash+ Key Equivalence
 *
 *  Two objects are treated as the same \hash key when their <code>hash</code> value
 *  is identical and the two objects are <code>eql?</code> to each other.
 *
 *  ==== Modifying an Active +Hash+ Key
 *
 *  Modifying a +Hash+ key while it is in use damages the hash's index.
 *
 *  This +Hash+ has keys that are Arrays:
 *
 *    a0 = [ :foo, :bar ]
 *    a1 = [ :baz, :bat ]
 *    h = {a0 => 0, a1 => 1}
 *    h.include?(a0) # => true
 *    h[a0] # => 0
 *    a0.hash # => 110002110
 *
 *  Modifying array element <tt>a0[0]</tt> changes its hash value:
 *
 *    a0[0] = :bam
 *    a0.hash # => 1069447059
 *
 *  And damages the +Hash+ index:
 *
 *    h.include?(a0) # => false
 *    h[a0] # => nil
 *
 *  You can repair the hash index using method +rehash+:
 *
 *    h.rehash # => {[:bam, :bar]=>0, [:baz, :bat]=>1}
 *    h.include?(a0) # => true
 *    h[a0] # => 0
 *
 *  A String key is always safe.
 *  That's because an unfrozen String
 *  passed as a key will be replaced by a duplicated and frozen String:
 *
 *    s = 'foo'
 *    s.frozen? # => false
 *    h = {s => 0}
 *    first_key = h.keys.first
 *    first_key.frozen? # => true
 *
 *  ==== User-Defined +Hash+ Keys
 *
 *  To be usable as a +Hash+ key, objects must implement the methods <code>hash</code> and <code>eql?</code>.
 *  Note: this requirement does not apply if the +Hash+ uses #compare_by_identity since comparison will then
 *  rely on the keys' object id instead of <code>hash</code> and <code>eql?</code>.
 *
 *  Object defines basic implementation for <code>hash</code> and <code>eq?</code> that makes each object
 *  a distinct key. Typically, user-defined classes will want to override these methods to provide meaningful
 *  behavior, or for example inherit Struct that has useful definitions for these.
 *
 *  A typical implementation of <code>hash</code> is based on the
 *  object's data while <code>eql?</code> is usually aliased to the overridden
 *  <code>==</code> method:
 *
 *    class Book
 *      attr_reader :author, :title
 *
 *      def initialize(author, title)
 *        @author = author
 *        @title = title
 *      end
 *
 *      def ==(other)
 *        self.class === other &&
 *          other.author == @author &&
 *          other.title == @title
 *      end
 *
 *      alias eql? ==
 *
 *      def hash
 *        [self.class, @author, @title].hash
 *      end
 *    end
 *
 *    book1 = Book.new 'matz', 'Ruby in a Nutshell'
 *    book2 = Book.new 'matz', 'Ruby in a Nutshell'
 *
 *    reviews = {}
 *
 *    reviews[book1] = 'Great reference!'
 *    reviews[book2] = 'Nice and compact!'
 *
 *    reviews.length #=> 1
 *
 *  === Default Values
 *
 *  The methods #[], #values_at and #dig need to return the value associated to a certain key.
 *  When that key is not found, that value will be determined by its default proc (if any)
 *  or else its default (initially `nil`).
 *
 *  You can retrieve the default value with method #default:
 *
 *    h = Hash.new
 *    h.default # => nil
 *
 *  You can set the default value by passing an argument to method Hash.new or
 *  with method #default=
 *
 *    h = Hash.new(-1)
 *    h.default # => -1
 *    h.default = 0
 *    h.default # => 0
 *
 *  This default value is returned for #[], #values_at and #dig when a key is
 *  not found:
 *
 *    counts = {foo: 42}
 *    counts.default # => nil (default)
 *    counts[:foo] = 42
 *    counts[:bar] # => nil
 *    counts.default = 0
 *    counts[:bar] # => 0
 *    counts.values_at(:foo, :bar, :baz) # => [42, 0, 0]
 *    counts.dig(:bar) # => 0
 *
 *  Note that the default value is used without being duplicated. It is not advised to set
 *  the default value to a mutable object:
 *
 *    synonyms = Hash.new([])
 *    synonyms[:hello] # => []
 *    synonyms[:hello] << :hi # => [:hi], but this mutates the default!
 *    synonyms.default # => [:hi]
 *    synonyms[:world] << :universe
 *    synonyms[:world] # => [:hi, :universe], oops
 *    synonyms.keys # => [], oops
 *
 *  To use a mutable object as default, it is recommended to use a default proc
 *
 *  ==== Default Proc
 *
 *  When the default proc for a +Hash+ is set (i.e., not +nil+),
 *  the default value returned by method #[] is determined by the default proc alone.
 *
 *  You can retrieve the default proc with method #default_proc:
 *
 *    h = Hash.new
 *    h.default_proc # => nil
 *
 *  You can set the default proc by calling Hash.new with a block or
 *  calling the method #default_proc=
 *
 *    h = Hash.new { |hash, key| "Default value for #{key}" }
 *    h.default_proc.class # => Proc
 *    h.default_proc = proc { |hash, key| "Default value for #{key.inspect}" }
 *    h.default_proc.class # => Proc
 *
 *  When the default proc is set (i.e., not +nil+)
 *  and method #[] is called with with a non-existent key,
 *  #[] calls the default proc with both the +Hash+ object itself and the missing key,
 *  then returns the proc's return value:
 *
 *    h = Hash.new { |hash, key| "Default value for #{key}" }
 *    h[:nosuch] # => "Default value for nosuch"
 *
 *  Note that in the example above no entry for key +:nosuch+ is created:
 *
 *    h.include?(:nosuch) # => false
 *
 *  However, the proc itself can add a new entry:
 *
 *    synonyms = Hash.new { |hash, key| hash[key] = [] }
 *    synonyms.include?(:hello) # => false
 *    synonyms[:hello] << :hi # => [:hi]
 *    synonyms[:world] << :universe # => [:universe]
 *    synonyms.keys # => [:hello, :world]
 *
 *  Note that setting the default proc will clear the default value and vice versa.
 *
 *  Be aware that a default proc that modifies the hash is not thread-safe in the
 *  sense that multiple threads can call into the default proc concurrently for the
 *  same key.
 *
 *  === What's Here
 *
 *  First, what's elsewhere. \Class +Hash+:
 *
 *  - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
 *  - Includes {module Enumerable}[rdoc-ref:Enumerable@What-27s+Here],
 *    which provides dozens of additional methods.
 *
 *  Here, class +Hash+ provides methods that are useful for:
 *
 *  - {Creating a Hash}[rdoc-ref:Hash@Methods+for+Creating+a+Hash]
 *  - {Setting Hash State}[rdoc-ref:Hash@Methods+for+Setting+Hash+State]
 *  - {Querying}[rdoc-ref:Hash@Methods+for+Querying]
 *  - {Comparing}[rdoc-ref:Hash@Methods+for+Comparing]
 *  - {Fetching}[rdoc-ref:Hash@Methods+for+Fetching]
 *  - {Assigning}[rdoc-ref:Hash@Methods+for+Assigning]
 *  - {Deleting}[rdoc-ref:Hash@Methods+for+Deleting]
 *  - {Iterating}[rdoc-ref:Hash@Methods+for+Iterating]
 *  - {Converting}[rdoc-ref:Hash@Methods+for+Converting]
 *  - {Transforming Keys and Values}[rdoc-ref:Hash@Methods+for+Transforming+Keys+and+Values]
 *  - {And more....}[rdoc-ref:Hash@Other+Methods]
 *
 *  \Class +Hash+ also includes methods from module Enumerable.
 *
 *  ==== Methods for Creating a +Hash+
 *
 *  - ::[]: Returns a new hash populated with given objects.
 *  - ::new: Returns a new empty hash.
 *  - ::try_convert: Returns a new hash created from a given object.
 *
 *  ==== Methods for Setting +Hash+ State
 *
 *  - #compare_by_identity: Sets +self+ to consider only identity in comparing keys.
 *  - #default=: Sets the default to a given value.
 *  - #default_proc=: Sets the default proc to a given proc.
 *  - #rehash: Rebuilds the hash table by recomputing the hash index for each key.
 *
 *  ==== Methods for Querying
 *
 *  - #any?: Returns whether any element satisfies a given criterion.
 *  - #compare_by_identity?: Returns whether the hash considers only identity when comparing keys.
 *  - #default: Returns the default value, or the default value for a given key.
 *  - #default_proc: Returns the default proc.
 *  - #empty?: Returns whether there are no entries.
 *  - #eql?: Returns whether a given object is equal to +self+.
 *  - #hash: Returns the integer hash code.
 *  - #has_value? (aliased as #value?): Returns whether a given object is a value in +self+.
 *  - #include? (aliased as #has_key?, #member?, #key?): Returns whether a given object is a key in +self+.
 *  - #size (aliased as #length): Returns the count of entries.
 *
 *  ==== Methods for Comparing
 *
 *  - #<: Returns whether +self+ is a proper subset of a given object.
 *  - #<=: Returns whether +self+ is a subset of a given object.
 *  - #==: Returns whether a given object is equal to +self+.
 *  - #>: Returns whether +self+ is a proper superset of a given object
 *  - #>=: Returns whether +self+ is a superset of a given object.
 *
 *  ==== Methods for Fetching
 *
 *  - #[]: Returns the value associated with a given key.
 *  - #assoc: Returns a 2-element array containing a given key and its value.
 *  - #dig: Returns the object in nested objects that is specified
 *    by a given key and additional arguments.
 *  - #fetch: Returns the value for a given key.
 *  - #fetch_values: Returns array containing the values associated with given keys.
 *  - #key: Returns the key for the first-found entry with a given value.
 *  - #keys: Returns an array containing all keys in +self+.
 *  - #rassoc: Returns a 2-element array consisting of the key and value
 *    of the first-found entry having a given value.
 *  - #values: Returns an array containing all values in +self+/
 *  - #values_at: Returns an array containing values for given keys.
 *
 *  ==== Methods for Assigning
 *
 *  - #[]= (aliased as #store): Associates a given key with a given value.
 *  - #merge: Returns the hash formed by merging each given hash into a copy of +self+.
 *  - #update (aliased as #merge!): Merges each given hash into +self+.
 *  - #replace (aliased as #initialize_copy): Replaces the entire contents of +self+ with the contents of a given hash.
 *
 *  ==== Methods for Deleting
 *
 *  These methods remove entries from +self+:
 *
 *  - #clear: Removes all entries from +self+.
 *  - #compact!: Removes all +nil+-valued entries from +self+.
 *  - #delete: Removes the entry for a given key.
 *  - #delete_if: Removes entries selected by a given block.
 *  - #select! (aliased as #filter!): Keep only those entries selected by a given block.
 *  - #keep_if: Keep only those entries selected by a given block.
 *  - #reject!: Removes entries selected by a given block.
 *  - #shift: Removes and returns the first entry.
 *
 *  These methods return a copy of +self+ with some entries removed:
 *
 *  - #compact: Returns a copy of +self+ with all +nil+-valued entries removed.
 *  - #except: Returns a copy of +self+ with entries removed for specified keys.
 *  - #select (aliased as #filter): Returns a copy of +self+ with only those entries selected by a given block.
 *  - #reject: Returns a copy of +self+ with entries removed as specified by a given block.
 *  - #slice: Returns a hash containing the entries for given keys.
 *
 *  ==== Methods for Iterating
 *  - #each_pair (aliased as #each): Calls a given block with each key-value pair.
 *  - #each_key: Calls a given block with each key.
 *  - #each_value: Calls a given block with each value.
 *
 *  ==== Methods for Converting
 *
 *  - #inspect (aliased as #to_s): Returns a new String containing the hash entries.
 *  - #to_a: Returns a new array of 2-element arrays;
 *    each nested array contains a key-value pair from +self+.
 *  - #to_h: Returns +self+ if a +Hash+;
 *    if a subclass of +Hash+, returns a +Hash+ containing the entries from +self+.
 *  - #to_hash: Returns +self+.
 *  - #to_proc: Returns a proc that maps a given key to its value.
 *
 *  ==== Methods for Transforming Keys and Values
 *
 *  - #transform_keys: Returns a copy of +self+ with modified keys.
 *  - #transform_keys!: Modifies keys in +self+
 *  - #transform_values: Returns a copy of +self+ with modified values.
 *  - #transform_values!: Modifies values in +self+.
 *
 *  ==== Other Methods
 *  - #flatten: Returns an array that is a 1-dimensional flattening of +self+.
 *  - #invert: Returns a hash with the each key-value pair inverted.
 *
 */

void
Init_Hash(void)
{
    id_hash = rb_intern_const("hash");
    id_flatten_bang = rb_intern_const("flatten!");
    id_hash_iter_lev = rb_make_internal_id();

    rb_cHash = rb_define_class("Hash", rb_cObject);

    rb_include_module(rb_cHash, rb_mEnumerable);

    rb_define_alloc_func(rb_cHash, empty_hash_alloc);
    rb_define_singleton_method(rb_cHash, "[]", rb_hash_s_create, -1);
    rb_define_singleton_method(rb_cHash, "try_convert", rb_hash_s_try_convert, 1);
    rb_define_method(rb_cHash, "initialize_copy", rb_hash_replace, 1);
    rb_define_method(rb_cHash, "rehash", rb_hash_rehash, 0);
    rb_define_method(rb_cHash, "freeze", rb_hash_freeze, 0);

    rb_define_method(rb_cHash, "to_hash", rb_hash_to_hash, 0);
    rb_define_method(rb_cHash, "to_h", rb_hash_to_h, 0);
    rb_define_method(rb_cHash, "to_a", rb_hash_to_a, 0);
    rb_define_method(rb_cHash, "inspect", rb_hash_inspect, 0);
    rb_define_alias(rb_cHash, "to_s", "inspect");
    rb_define_method(rb_cHash, "to_proc", rb_hash_to_proc, 0);

    rb_define_method(rb_cHash, "==", rb_hash_equal, 1);
    rb_define_method(rb_cHash, "[]", rb_hash_aref, 1);
    rb_define_method(rb_cHash, "hash", rb_hash_hash, 0);
    rb_define_method(rb_cHash, "eql?", rb_hash_eql, 1);
    rb_define_method(rb_cHash, "fetch", rb_hash_fetch_m, -1);
    rb_define_method(rb_cHash, "[]=", rb_hash_aset, 2);
    rb_define_method(rb_cHash, "store", rb_hash_aset, 2);
    rb_define_method(rb_cHash, "default", rb_hash_default, -1);
    rb_define_method(rb_cHash, "default=", rb_hash_set_default, 1);
    rb_define_method(rb_cHash, "default_proc", rb_hash_default_proc, 0);
    rb_define_method(rb_cHash, "default_proc=", rb_hash_set_default_proc, 1);
    rb_define_method(rb_cHash, "key", rb_hash_key, 1);
    rb_define_method(rb_cHash, "size", rb_hash_size, 0);
    rb_define_method(rb_cHash, "length", rb_hash_size, 0);
    rb_define_method(rb_cHash, "empty?", rb_hash_empty_p, 0);

    rb_define_method(rb_cHash, "each_value", rb_hash_each_value, 0);
    rb_define_method(rb_cHash, "each_key", rb_hash_each_key, 0);
    rb_define_method(rb_cHash, "each_pair", rb_hash_each_pair, 0);
    rb_define_method(rb_cHash, "each", rb_hash_each_pair, 0);

    rb_define_method(rb_cHash, "transform_keys", rb_hash_transform_keys, -1);
    rb_define_method(rb_cHash, "transform_keys!", rb_hash_transform_keys_bang, -1);
    rb_define_method(rb_cHash, "transform_values", rb_hash_transform_values, 0);
    rb_define_method(rb_cHash, "transform_values!", rb_hash_transform_values_bang, 0);

    rb_define_method(rb_cHash, "keys", rb_hash_keys, 0);
    rb_define_method(rb_cHash, "values", rb_hash_values, 0);
    rb_define_method(rb_cHash, "values_at", rb_hash_values_at, -1);
    rb_define_method(rb_cHash, "fetch_values", rb_hash_fetch_values, -1);

    rb_define_method(rb_cHash, "shift", rb_hash_shift, 0);
    rb_define_method(rb_cHash, "delete", rb_hash_delete_m, 1);
    rb_define_method(rb_cHash, "delete_if", rb_hash_delete_if, 0);
    rb_define_method(rb_cHash, "keep_if", rb_hash_keep_if, 0);
    rb_define_method(rb_cHash, "select", rb_hash_select, 0);
    rb_define_method(rb_cHash, "select!", rb_hash_select_bang, 0);
    rb_define_method(rb_cHash, "filter", rb_hash_select, 0);
    rb_define_method(rb_cHash, "filter!", rb_hash_select_bang, 0);
    rb_define_method(rb_cHash, "reject", rb_hash_reject, 0);
    rb_define_method(rb_cHash, "reject!", rb_hash_reject_bang, 0);
    rb_define_method(rb_cHash, "slice", rb_hash_slice, -1);
    rb_define_method(rb_cHash, "except", rb_hash_except, -1);
    rb_define_method(rb_cHash, "clear", rb_hash_clear, 0);
    rb_define_method(rb_cHash, "invert", rb_hash_invert, 0);
    rb_define_method(rb_cHash, "update", rb_hash_update, -1);
    rb_define_method(rb_cHash, "replace", rb_hash_replace, 1);
    rb_define_method(rb_cHash, "merge!", rb_hash_update, -1);
    rb_define_method(rb_cHash, "merge", rb_hash_merge, -1);
    rb_define_method(rb_cHash, "assoc", rb_hash_assoc, 1);
    rb_define_method(rb_cHash, "rassoc", rb_hash_rassoc, 1);
    rb_define_method(rb_cHash, "flatten", rb_hash_flatten, -1);
    rb_define_method(rb_cHash, "compact", rb_hash_compact, 0);
    rb_define_method(rb_cHash, "compact!", rb_hash_compact_bang, 0);

    rb_define_method(rb_cHash, "include?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash, "member?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash, "has_key?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash, "has_value?", rb_hash_has_value, 1);
    rb_define_method(rb_cHash, "key?", rb_hash_has_key, 1);
    rb_define_method(rb_cHash, "value?", rb_hash_has_value, 1);

    rb_define_method(rb_cHash, "compare_by_identity", rb_hash_compare_by_id, 0);
    rb_define_method(rb_cHash, "compare_by_identity?", rb_hash_compare_by_id_p, 0);

    rb_define_method(rb_cHash, "any?", rb_hash_any_p, -1);
    rb_define_method(rb_cHash, "dig", rb_hash_dig, -1);

    rb_define_method(rb_cHash, "<=", rb_hash_le, 1);
    rb_define_method(rb_cHash, "<", rb_hash_lt, 1);
    rb_define_method(rb_cHash, ">=", rb_hash_ge, 1);
    rb_define_method(rb_cHash, ">", rb_hash_gt, 1);

    rb_define_method(rb_cHash, "deconstruct_keys", rb_hash_deconstruct_keys, 1);

    rb_define_singleton_method(rb_cHash, "ruby2_keywords_hash?", rb_hash_s_ruby2_keywords_hash_p, 1);
    rb_define_singleton_method(rb_cHash, "ruby2_keywords_hash", rb_hash_s_ruby2_keywords_hash, 1);

    rb_cHash_empty_frozen = rb_hash_freeze(rb_hash_new());
    rb_vm_register_global_object(rb_cHash_empty_frozen);

    /* Document-class: ENV
     *
     * +ENV+ is a hash-like accessor for environment variables.
     *
     * === Interaction with the Operating System
     *
     * The +ENV+ object interacts with the operating system's environment variables:
     *
     * - When you get the value for a name in +ENV+, the value is retrieved from among the current environment variables.
     * - When you create or set a name-value pair in +ENV+, the name and value are immediately set in the environment variables.
     * - When you delete a name-value pair in +ENV+, it is immediately deleted from the environment variables.
     *
     * === Names and Values
     *
     * Generally, a name or value is a String.
     *
     * ==== Valid Names and Values
     *
     * Each name or value must be one of the following:
     *
     * - A String.
     * - An object that responds to \#to_str by returning a String, in which case that String will be used as the name or value.
     *
     * ==== Invalid Names and Values
     *
     * A new name:
     *
     * - May not be the empty string:
     *     ENV[''] = '0'
     *     # Raises Errno::EINVAL (Invalid argument - ruby_setenv())
     *
     * - May not contain character <code>"="</code>:
     *     ENV['='] = '0'
     *     # Raises Errno::EINVAL (Invalid argument - ruby_setenv(=))
     *
     * A new name or value:
     *
     * - May not be a non-String that does not respond to \#to_str:
     *
     *     ENV['foo'] = Object.new
     *     # Raises TypeError (no implicit conversion of Object into String)
     *     ENV[Object.new] = '0'
     *     # Raises TypeError (no implicit conversion of Object into String)
     *
     * - May not contain the NUL character <code>"\0"</code>:
     *
     *     ENV['foo'] = "\0"
     *     # Raises ArgumentError (bad environment variable value: contains null byte)
     *     ENV["\0"] == '0'
     *     # Raises ArgumentError (bad environment variable name: contains null byte)
     *
     * - May not have an ASCII-incompatible encoding such as UTF-16LE or ISO-2022-JP:
     *
     *     ENV['foo'] = '0'.force_encoding(Encoding::ISO_2022_JP)
     *     # Raises ArgumentError (bad environment variable name: ASCII incompatible encoding: ISO-2022-JP)
     *     ENV["foo".force_encoding(Encoding::ISO_2022_JP)] = '0'
     *     # Raises ArgumentError (bad environment variable name: ASCII incompatible encoding: ISO-2022-JP)
     *
     * === About Ordering
     *
     * +ENV+ enumerates its name/value pairs in the order found
     * in the operating system's environment variables.
     * Therefore the ordering of +ENV+ content is OS-dependent, and may be indeterminate.
     *
     * This will be seen in:
     * - A Hash returned by an +ENV+ method.
     * - An Enumerator returned by an +ENV+ method.
     * - An Array returned by ENV.keys, ENV.values, or ENV.to_a.
     * - The String returned by ENV.inspect.
     * - The Array returned by ENV.shift.
     * - The name returned by ENV.key.
     *
     * === About the Examples
     * Some methods in +ENV+ return +ENV+ itself. Typically, there are many environment variables.
     * It's not useful to display a large +ENV+ in the examples here,
     * so most example snippets begin by resetting the contents of +ENV+:
     * - ENV.replace replaces +ENV+ with a new collection of entries.
     * - ENV.clear empties +ENV+.
     *
     * === What's Here
     *
     * First, what's elsewhere. \Class +ENV+:
     *
     * - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
     * - Extends {module Enumerable}[rdoc-ref:Enumerable@What-27s+Here],
     *
     * Here, class +ENV+ provides methods that are useful for:
     *
     * - {Querying}[rdoc-ref:ENV@Methods+for+Querying]
     * - {Assigning}[rdoc-ref:ENV@Methods+for+Assigning]
     * - {Deleting}[rdoc-ref:ENV@Methods+for+Deleting]
     * - {Iterating}[rdoc-ref:ENV@Methods+for+Iterating]
     * - {Converting}[rdoc-ref:ENV@Methods+for+Converting]
     * - {And more ....}[rdoc-ref:ENV@More+Methods]
     *
     * ==== Methods for Querying
     *
     * - ::[]: Returns the value for the given environment variable name if it exists:
     * - ::empty?: Returns whether +ENV+ is empty.
     * - ::has_value?, ::value?: Returns whether the given value is in +ENV+.
     * - ::include?, ::has_key?, ::key?, ::member?: Returns whether the given name
         is in +ENV+.
     * - ::key: Returns the name of the first entry with the given value.
     * - ::size, ::length: Returns the number of entries.
     * - ::value?: Returns whether any entry has the given value.
     *
     * ==== Methods for Assigning
     *
     * - ::[]=, ::store: Creates, updates, or deletes the named environment variable.
     * - ::clear: Removes every environment variable; returns +ENV+:
     * - ::update, ::merge!: Adds to +ENV+ each key/value pair in the given hash.
     * - ::replace: Replaces the entire content of the +ENV+
     *   with the name/value pairs in the given hash.
     *
     * ==== Methods for Deleting
     *
     * - ::delete: Deletes the named environment variable name if it exists.
     * - ::delete_if: Deletes entries selected by the block.
     * - ::keep_if: Deletes entries not selected by the block.
     * - ::reject!: Similar to #delete_if, but returns +nil+ if no change was made.
     * - ::select!, ::filter!: Deletes entries selected by the block.
     * - ::shift: Removes and returns the first entry.
     *
     * ==== Methods for Iterating
     *
     * - ::each, ::each_pair: Calls the block with each name/value pair.
     * - ::each_key: Calls the block with each name.
     * - ::each_value: Calls the block with each value.
     *
     * ==== Methods for Converting
     *
     * - ::assoc: Returns a 2-element array containing the name and value
     *   of the named environment variable if it exists:
     * - ::clone: Returns +ENV+ (and issues a warning).
     * - ::except: Returns a hash of all name/value pairs except those given.
     * - ::fetch: Returns the value for the given name.
     * - ::inspect: Returns the contents of +ENV+ as a string.
     * - ::invert: Returns a hash whose keys are the +ENV+ values,
         and whose values are the corresponding +ENV+ names.
     * - ::keys: Returns an array of all names.
     * - ::rassoc: Returns the name and value of the first found entry
     *   that has the given value.
     * - ::reject: Returns a hash of those entries not rejected by the block.
     * - ::select, ::filter: Returns a hash of name/value pairs selected by the block.
     * - ::slice: Returns a hash of the given names and their corresponding values.
     * - ::to_a: Returns the entries as an array of 2-element Arrays.
     * - ::to_h: Returns a hash of entries selected by the block.
     * - ::to_hash: Returns a hash of all entries.
     * - ::to_s: Returns the string <tt>'ENV'</tt>.
     * - ::values: Returns all values as an array.
     * - ::values_at: Returns an array of the values for the given name.
     *
     * ==== More Methods
     *
     * - ::dup: Raises an exception.
     * - ::freeze: Raises an exception.
     * - ::rehash: Returns +nil+, without modifying +ENV+.
     *
     */

    /*
     * Hack to get RDoc to regard ENV as a class:
     * envtbl = rb_define_class("ENV", rb_cObject);
     */
    origenviron = environ;
    envtbl = TypedData_Wrap_Struct(rb_cObject, &env_data_type, NULL);
    rb_extend_object(envtbl, rb_mEnumerable);
    FL_SET_RAW(envtbl, RUBY_FL_SHAREABLE);


    rb_define_singleton_method(envtbl, "[]", rb_f_getenv, 1);
    rb_define_singleton_method(envtbl, "fetch", env_fetch, -1);
    rb_define_singleton_method(envtbl, "[]=", env_aset_m, 2);
    rb_define_singleton_method(envtbl, "store", env_aset_m, 2);
    rb_define_singleton_method(envtbl, "each", env_each_pair, 0);
    rb_define_singleton_method(envtbl, "each_pair", env_each_pair, 0);
    rb_define_singleton_method(envtbl, "each_key", env_each_key, 0);
    rb_define_singleton_method(envtbl, "each_value", env_each_value, 0);
    rb_define_singleton_method(envtbl, "delete", env_delete_m, 1);
    rb_define_singleton_method(envtbl, "delete_if", env_delete_if, 0);
    rb_define_singleton_method(envtbl, "keep_if", env_keep_if, 0);
    rb_define_singleton_method(envtbl, "slice", env_slice, -1);
    rb_define_singleton_method(envtbl, "except", env_except, -1);
    rb_define_singleton_method(envtbl, "clear", env_clear, 0);
    rb_define_singleton_method(envtbl, "reject", env_reject, 0);
    rb_define_singleton_method(envtbl, "reject!", env_reject_bang, 0);
    rb_define_singleton_method(envtbl, "select", env_select, 0);
    rb_define_singleton_method(envtbl, "select!", env_select_bang, 0);
    rb_define_singleton_method(envtbl, "filter", env_select, 0);
    rb_define_singleton_method(envtbl, "filter!", env_select_bang, 0);
    rb_define_singleton_method(envtbl, "shift", env_shift, 0);
    rb_define_singleton_method(envtbl, "freeze", env_freeze, 0);
    rb_define_singleton_method(envtbl, "invert", env_invert, 0);
    rb_define_singleton_method(envtbl, "replace", env_replace, 1);
    rb_define_singleton_method(envtbl, "update", env_update, -1);
    rb_define_singleton_method(envtbl, "merge!", env_update, -1);
    rb_define_singleton_method(envtbl, "inspect", env_inspect, 0);
    rb_define_singleton_method(envtbl, "rehash", env_none, 0);
    rb_define_singleton_method(envtbl, "to_a", env_to_a, 0);
    rb_define_singleton_method(envtbl, "to_s", env_to_s, 0);
    rb_define_singleton_method(envtbl, "key", env_key, 1);
    rb_define_singleton_method(envtbl, "size", env_size, 0);
    rb_define_singleton_method(envtbl, "length", env_size, 0);
    rb_define_singleton_method(envtbl, "empty?", env_empty_p, 0);
    rb_define_singleton_method(envtbl, "keys", env_f_keys, 0);
    rb_define_singleton_method(envtbl, "values", env_f_values, 0);
    rb_define_singleton_method(envtbl, "values_at", env_values_at, -1);
    rb_define_singleton_method(envtbl, "include?", env_has_key, 1);
    rb_define_singleton_method(envtbl, "member?", env_has_key, 1);
    rb_define_singleton_method(envtbl, "has_key?", env_has_key, 1);
    rb_define_singleton_method(envtbl, "has_value?", env_has_value, 1);
    rb_define_singleton_method(envtbl, "key?", env_has_key, 1);
    rb_define_singleton_method(envtbl, "value?", env_has_value, 1);
    rb_define_singleton_method(envtbl, "to_hash", env_f_to_hash, 0);
    rb_define_singleton_method(envtbl, "to_h", env_to_h, 0);
    rb_define_singleton_method(envtbl, "assoc", env_assoc, 1);
    rb_define_singleton_method(envtbl, "rassoc", env_rassoc, 1);
    rb_define_singleton_method(envtbl, "clone", env_clone, -1);
    rb_define_singleton_method(envtbl, "dup", env_dup, 0);

    VALUE envtbl_class = rb_singleton_class(envtbl);
    rb_undef_method(envtbl_class, "initialize");
    rb_undef_method(envtbl_class, "initialize_clone");
    rb_undef_method(envtbl_class, "initialize_copy");
    rb_undef_method(envtbl_class, "initialize_dup");

    /*
     * +ENV+ is a Hash-like accessor for environment variables.
     *
     * See ENV (the class) for more details.
     */
    rb_define_global_const("ENV", envtbl);

    HASH_ASSERT(sizeof(ar_hint_t) * RHASH_AR_TABLE_MAX_SIZE == sizeof(VALUE));
}

#include "hash.rbinc"
