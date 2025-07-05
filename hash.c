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
stable_obj_address_hash(VALUE obj)
{
    if (RB_TYPE_P(obj, T_OBJECT)) {
        return (st_index_t)st_index_hash(rb_obj_stable_address(obj));
    }
    else {
        VALUE object_id = rb_obj_id(obj);
        if (UNLIKELY(!FIXNUM_P(object_id))) {
            object_id = rb_big_hash(object_id);
        }

#if SIZEOF_LONG == SIZEOF_VOIDP
        return (st_index_t)NUM2LONG(object_id);
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
        return (st_index_t)NUM2LL(object_id);
#else
#error "Unexpected VALUE size"
#endif
    }
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
    long hnum = any_hash(obj, stable_obj_address_hash);
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
                    (*replace)(&key, &val, arg, TRUE);

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
                    (*func)(0, 0, arg, 1);
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

/* This does not manage iteration level */
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

/* This does not manage iteration level */
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
    VALUE ret = hash_dup(hash, rb_obj_class(hash), flags & RHASH_PROC_DEFAULT);

    if (rb_obj_exivar_p(hash)) {
        rb_copy_generic_ivar(ret, hash);
    }
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
        .value = 0
    };

    int ret = rb_hash_stlike_update(hash, key, tbl_update_modify, (st_data_t)&arg);

    /* write barrier */
    RB_OBJ_WRITTEN(hash, Qundef, arg.key);
    if (arg.value) RB_OBJ_WRITTEN(hash, Qundef, arg.value);

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
 *    Hash[other_hash] -> new_hash
 *    Hash[ [*2_element_arrays] ] -> new_hash
 *    Hash[*objects] -> new_hash
 *
 *  Returns a new \Hash object populated with the given objects, if any.
 *  See Hash::new.
 *
 *  With no argument given, returns a new empty hash.
 *
 *  With a single argument +other_hash+ given that is a hash,
 *  returns a new hash initialized with the entries from that hash
 *  (but not with its +default+ or +default_proc+):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    Hash[h] # => {foo: 0, bar: 1, baz: 2}
 *
 *  With a single argument +2_element_arrays+ given that is an array of 2-element arrays,
 *  returns a new hash wherein each given 2-element array forms a
 *  key-value entry:
 *
 *    Hash[ [ [:foo, 0], [:bar, 1] ] ] # => {foo: 0, bar: 1}
 *
 *  With an even number of arguments +objects+ given,
 *  returns a new hash wherein each successive pair of arguments
 *  is a key-value entry:
 *
 *    Hash[:foo, 0, :bar, 1] # => {foo: 0, bar: 1}
 *
 *  Raises ArgumentError if the argument list does not conform to any
 *  of the above.
 *
 *  See also {Methods for Creating a Hash}[rdoc-ref:Hash@Methods+for+Creating+a+Hash].
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
 *    Hash.try_convert(object) -> object, new_hash, or nil
 *
 *  If +object+ is a hash, returns +object+.
 *
 *  Otherwise if +object+ responds to +:to_hash+,
 *  calls <tt>object.to_hash</tt>;
 *  returns the result if it is a hash, or raises TypeError if not.
 *
 *  Otherwise if +object+ does not respond to +:to_hash+, returns +nil+.
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
 *     rehash -> self
 *
 *  Rebuilds the hash table for +self+ by recomputing the hash index for each key;
 *  returns <tt>self</tt>.
 *  Calling this method ensures that the hash table is valid.
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

bool
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
 *    self[key] -> object
 *
 *  Searches for a hash key equivalent to the given +key+;
 *  see {Hash Key Equivalence}[rdoc-ref:Hash@Hash+Key+Equivalence].
 *
 *  If the key is found, returns its value:
 *
 *    {foo: 0, bar: 1, baz: 2}
 *    h[:bar] # => 1
 *
 *  Otherwise, returns a default value (see {Hash Default}[rdoc-ref:Hash@Hash+Default]).
 *
 *  Related: #[]=; see also {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    fetch(key) -> object
 *    fetch(key, default_value) -> object
 *    fetch(key) {|key| ... } -> object
 *
 *  With no block given, returns the value for the given +key+, if found;
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.fetch(:bar)  # => 1
 *
 *  If the key is not found, returns +default_value+, if given,
 *  or raises KeyError otherwise:
 *
 *    h.fetch(:nosuch, :default) # => :default
 *    h.fetch(:nosuch)           # Raises KeyError.
 *
 *  With a block given, calls the block with +key+ and returns the block's return value:
 *
 *    {}.fetch(:nosuch) {|key| "No key #{key}"} # => "No key nosuch"
 *
 *  Note that this method does not use the values of either #default or #default_proc.
 *
 *  Related: see {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    default -> object
 *    default(key) -> object
 *
 *  Returns the default value for the given +key+.
 *  The returned value will be determined either by the default proc or by the default value.
 *  See {Hash Default}[rdoc-ref:Hash@Hash+Default].
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
 *    default = value -> object
 *
 *  Sets the default value to +value+; returns +value+:
 *    h = {}
 *    h.default # => nil
 *    h.default = false # => false
 *    h.default # => false
 *
 *  See {Hash Default}[rdoc-ref:Hash@Hash+Default].
 */

VALUE
rb_hash_set_default(VALUE hash, VALUE ifnone)
{
    rb_hash_modify_check(hash);
    SET_DEFAULT(hash, ifnone);
    return ifnone;
}

/*
 *  call-seq:
 *    default_proc -> proc or nil
 *
 *  Returns the default proc for +self+
 *  (see {Hash Default}[rdoc-ref:Hash@Hash+Default]):
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
 *    default_proc = proc -> proc
 *
 *  Sets the default proc for +self+ to +proc+
 *  (see {Hash Default}[rdoc-ref:Hash@Hash+Default]):
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
 *    key(value) -> key or nil
 *
 *  Returns the key for the first-found entry with the given +value+
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *
 *    h = {foo: 0, bar: 2, baz: 2}
 *    h.key(0) # => :foo
 *    h.key(2) # => :bar
 *
 *  Returns +nil+ if no such value is found.
 *
 *  Related: see {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    delete(key) -> value or nil
 *    delete(key) {|key| ... } -> object
 *
 *  If an entry for the given +key+ is found,
 *  deletes the entry and returns its associated value;
 *  otherwise returns +nil+ or calls the given block.
 *
 *  With no block given and +key+ found, deletes the entry and returns its value:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:bar) # => 1
 *    h # => {foo: 0, baz: 2}
 *
 *  With no block given and +key+ not found, returns +nil+.
 *
 *  With a block given and +key+ found, ignores the block,
 *  deletes the entry, and returns its value:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:baz) { |key| raise 'Will never happen'} # => 2
 *    h # => {foo: 0, bar: 1}
 *
 *  With a block given and +key+ not found,
 *  calls the block and returns the block's return value:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:nosuch) { |key| "Key #{key} not found" } # => "Key nosuch not found"
 *    h # => {foo: 0, bar: 1, baz: 2}
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    shift -> [key, value] or nil
 *
 *  Removes and returns the first entry of +self+ as a 2-element array;
 *  see {Entry Order}[rdoc-ref:Hash@Entry+Order]:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.shift # => [:foo, 0]
 *    h       # => {bar: 1, baz: 2}
 *
 *  Returns +nil+ if +self+ is empty.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    delete_if {|key, value| ... } -> self
 *    delete_if -> new_enumerator
 *
 *  With a block given, calls the block with each key-value pair,
 *  deletes each entry for which the block returns a truthy value,
 *  and returns +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete_if {|key, value| value > 0 } # => {foo: 0}
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    reject! {|key, value| ... } -> self or nil
 *    reject! -> new_enumerator
 *
 *  With a block given, calls the block with each entry's key and value;
 *  removes the entry from +self+ if the block returns a truthy value.
 *
 *  Return +self+ if any entries were removed, +nil+ otherwise:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.reject! {|key, value| value < 2 } # => {baz: 2}
 *    h.reject! {|key, value| value < 2 } # => nil
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    reject {|key, value| ... } -> new_hash
 *    reject -> new_enumerator
 *
 *  With a block given, returns a copy of +self+ with zero or more entries removed;
 *  calls the block with each key-value pair;
 *  excludes the entry in the copy if the block returns a truthy value,
 *  includes it otherwise:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.reject {|key, value| key.start_with?('b') }
 *    # => {foo: 0}
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    slice(*keys) -> new_hash
 *
 *  Returns a new hash containing the entries from +self+ for the given +keys+;
 *  ignores any keys that are not found:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.slice(:baz, :foo, :nosuch) # => {baz: 2, foo: 0}
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    except(*keys) -> new_hash
 *
 *  Returns a copy of +self+ that excludes entries for the given +keys+;
 *  any +keys+ that are not found are ignored:
 *
 *    h = {foo:0, bar: 1, baz: 2} # => {:foo=>0, :bar=>1, :baz=>2}
 *    h.except(:baz, :foo)        # => {:bar=>1}
 *    h.except(:bar, :nosuch)     # => {:foo=>0, :baz=>2}
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    values_at(*keys) -> new_array
 *
 *  Returns a new array containing values for the given +keys+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.values_at(:baz, :foo) # => [2, 0]
 *
 *  The {hash default}[rdoc-ref:Hash@Hash+Default] is returned
 *  for each key that is not found:
 *
 *    h.values_at(:hello, :foo) # => [nil, 0]
 *
 *  Related: see {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    fetch_values(*keys) -> new_array
 *    fetch_values(*keys) {|key| ... } -> new_array
 *
 *  When all given +keys+ are found,
 *  returns a new array containing the values associated with the given +keys+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.fetch_values(:baz, :foo) # => [2, 0]
 *
 *  When any given +keys+ are not found and a block is given,
 *  calls the block with each unfound key and uses the block's return value
 *  as the value for that key:
 *
 *    h.fetch_values(:bar, :foo, :bad, :bam) {|key| key.to_s}
 *    # => [1, 0, "bad", "bam"]
 *
 *  When any given +keys+ are not found and no block is given,
 *  raises KeyError.
 *
 *  Related: see {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    select {|key, value| ... } -> new_hash
 *    select -> new_enumerator
 *
 *  With a block given, calls the block with each entry's key and value;
 *  returns a new hash whose entries are those for which the block returns a truthy value:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.select {|key, value| value < 2 } # => {foo: 0, bar: 1}
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    select! {|key, value| ... } -> self or nil
 *    select! -> new_enumerator
 *
 *  With a block given, calls the block with each entry's key and value;
 *  removes from +self+ each entry for which the block returns +false+ or +nil+.
 *
 *  Returns +self+ if any entries were removed, +nil+ otherwise:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.select! {|key, value| value < 2 } # => {foo: 0, bar: 1}
 *    h.select! {|key, value| value < 2 } # => nil
 *
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    keep_if {|key, value| ... } -> self
 *    keep_if -> new_enumerator
 *
 *  With a block given, calls the block for each key-value pair;
 *  retains the entry if the block returns a truthy value;
 *  otherwise deletes the entry; returns +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.keep_if { |key, value| key.start_with?('b') } # => {bar: 1, baz: 2}
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    clear -> self
 *
 *  Removes all entries from +self+; returns emptied +self+.
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
    if (!rb_obj_exivar_p(key) && RBASIC_CLASS(key) == rb_cString) {
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
 *    self[key] = object -> object
 *
 *  Associates the given +object+ with the given +key+; returns +object+.
 *
 *  Searches for a hash key equivalent to the given +key+;
 *  see {Hash Key Equivalence}[rdoc-ref:Hash@Hash+Key+Equivalence].
 *
 *  If the key is found, replaces its value with the given +object+;
 *  the ordering is not affected
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *
 *    h = {foo: 0, bar: 1}
 *    h[:foo] = 2 # => 2
 *    h[:foo]     # => 2
 *
 *  If +key+ is not found, creates a new entry for the given +key+ and +object+;
 *  the new entry is last in the order
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *
 *    h = {foo: 0, bar: 1}
 *    h[:baz] = 2 # => 2
 *    h[:baz]     # => 2
 *    h           # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  Related: #[]; see also {Methods for Assigning}[rdoc-ref:Hash@Methods+for+Assigning].
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
 *    replace(other_hash) -> self
 *
 *  Replaces the entire contents of +self+ with the contents of +other_hash+;
 *  returns +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.replace({bat: 3, bam: 4}) # => {bat: 3, bam: 4}
 *
 *  Related: see {Methods for Assigning}[rdoc-ref:Hash@Methods+for+Assigning].
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
 *     size -> integer
 *
 *  Returns the count of entries in +self+:
 *
 *    {foo: 0, bar: 1, baz: 2}.size # => 3
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Hash@Methods+for+Querying].
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
 *    empty? -> true or false
 *
 *  Returns +true+ if there are no hash entries, +false+ otherwise:
 *
 *    {}.empty? # => true
 *    {foo: 0}.empty? # => false
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Hash@Methods+for+Querying].
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
 *    each_value {|value| ... } -> self
 *    each_value -> new_enumerator
 *
 *  With a block given, calls the block with each value; returns +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.each_value {|value| puts value } # => {foo: 0, bar: 1, baz: 2}
 *
 *  Output:
 *    0
 *    1
 *    2
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Iterating}[rdoc-ref:Hash@Methods+for+Iterating].
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
 *    each_key {|key| ... } -> self
 *    each_key -> new_enumerator
 *
 *  With a block given, calls the block with each key; returns +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.each_key {|key| puts key }  # => {foo: 0, bar: 1, baz: 2}
 *
 *  Output:
 *    foo
 *    bar
 *    baz
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Iterating}[rdoc-ref:Hash@Methods+for+Iterating].
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
 *    each_pair {|key, value| ... } -> self
 *    each_pair -> new_enumerator
 *
 *  With a block given, calls the block with each key-value pair; returns +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.each_pair {|key, value| puts "#{key}: #{value}"} # => {foo: 0, bar: 1, baz: 2}
 *
 *  Output:
 *
 *    foo: 0
 *    bar: 1
 *    baz: 2
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Iterating}[rdoc-ref:Hash@Methods+for+Iterating].
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
 *    transform_keys {|old_key| ... } -> new_hash
 *    transform_keys(other_hash) -> new_hash
 *    transform_keys(other_hash) {|old_key| ...} -> new_hash
 *    transform_keys -> new_enumerator
 *
 *  With an argument, a block, or both given,
 *  derives a new hash +new_hash+ from +self+, the argument, and/or the block;
 *  all, some, or none of its keys may be different from those in +self+.
 *
 *  With a block given and no argument,
 *  +new_hash+ has keys determined only by the block.
 *
 *  For each key/value pair <tt>old_key/value</tt> in +self+, calls the block with +old_key+;
 *  the block's return value becomes +new_key+;
 *  sets <tt>new_hash[new_key] = value</tt>;
 *  a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys {|old_key| old_key.to_s }
 *      # => {"foo" => 0, "bar" => 1, "baz" => 2}
 *      h.transform_keys {|old_key| 'xxx' }
 *      # => {"xxx" => 2}
 *
 *  With argument +other_hash+ given and no block,
 *  +new_hash+ may have new keys provided by +other_hash+
 *  and unchanged keys provided by +self+.
 *
 *  For each key/value pair <tt>old_key/old_value</tt> in +self+,
 *  looks for key +old_key+ in +other_hash+:
 *
 *  - If +old_key+ is found, its value <tt>other_hash[old_key]</tt> is taken as +new_key+;
 *    sets <tt>new_hash[new_key] = value</tt>;
 *    a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys(baz: :BAZ, bar: :BAR, foo: :FOO)
 *      # => {FOO: 0, BAR: 1, BAZ: 2}
 *      h.transform_keys(baz: :FOO, bar: :FOO, foo: :FOO)
 *      # => {FOO: 2}
 *
 *  - If +old_key+ is not found,
 *    sets <tt>new_hash[old_key] = value</tt>;
 *    a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys({})
 *      # => {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys(baz: :foo)
 *      # => {foo: 2, bar: 1}
 *
 *  Unused keys in +other_hash+ are ignored:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.transform_keys(bat: 3)
 *    # => {foo: 0, bar: 1, baz: 2}
 *
 *  With both argument +other_hash+ and a block given,
 *  +new_hash+ has new keys specified by +other_hash+ or by the block,
 *  and unchanged keys provided by +self+.
 *
 *  For each pair +old_key+ and +value+ in +self+:
 *
 *  - If +other_hash+ has key +old_key+ (with value +new_key+),
 *    does not call the block for that key;
 *    sets <tt>new_hash[new_key] = value</tt>;
 *    a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys(baz: :BAZ, bar: :BAR, foo: :FOO) {|key| fail 'Not called' }
 *      # => {FOO: 0, BAR: 1, BAZ: 2}
 *
 *  - If +other_hash+ does not have key +old_key+,
 *    calls the block with +old_key+ and takes its return value as +new_key+;
 *    sets <tt>new_hash[new_key] = value</tt>;
 *    a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys(baz: :BAZ) {|key| key.to_s.reverse }
 *      # => {"oof" => 0, "rab" => 1, BAZ: 2}
 *      h.transform_keys(baz: :BAZ) {|key| 'ook' }
 *      # => {"ook" => 1, BAZ: 2}
 *
 *  With no argument and no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Transforming Keys and Values}[rdoc-ref:Hash@Methods+for+Transforming+Keys+and+Values].
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
 *    transform_keys! {|old_key| ... } -> self
 *    transform_keys!(other_hash) -> self
 *    transform_keys!(other_hash) {|old_key| ...} -> self
 *    transform_keys! -> new_enumerator
 *
 *  With an argument, a block, or both given,
 *  derives keys from the argument, the block, and +self+;
 *  all, some, or none of the keys in +self+ may be changed.
 *
 *  With a block given and no argument,
 *  derives keys only from the block;
 *  all, some, or none of the keys in +self+ may be changed.
 *
 *  For each key/value pair <tt>old_key/value</tt> in +self+, calls the block with +old_key+;
 *  the block's return value becomes +new_key+;
 *  removes the entry for +old_key+: <tt>self.delete(old_key)</tt>;
 *  sets <tt>self[new_key] = value</tt>;
 *  a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys! {|old_key| old_key.to_s }
 *      # => {"foo" => 0, "bar" => 1, "baz" => 2}
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys! {|old_key| 'xxx' }
 *      # => {"xxx" => 2}
 *
 *  With argument +other_hash+ given and no block,
 *  derives keys for +self+ from +other_hash+ and +self+;
 *  all, some, or none of the keys in +self+ may be changed.
 *
 *  For each key/value pair <tt>old_key/old_value</tt> in +self+,
 *  looks for key +old_key+ in +other_hash+:
 *
 *  - If +old_key+ is found, takes value <tt>other_hash[old_key]</tt> as +new_key+;
 *    removes the entry for +old_key+: <tt>self.delete(old_key)</tt>;
 *    sets <tt>self[new_key] = value</tt>;
 *    a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys!(baz: :BAZ, bar: :BAR, foo: :FOO)
 *      # => {FOO: 0, BAR: 1, BAZ: 2}
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys!(baz: :FOO, bar: :FOO, foo: :FOO)
 *      # => {FOO: 2}
 *
 *  - If +old_key+ is not found, does nothing:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys!({})
 *      # => {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys!(baz: :foo)
 *      # => {foo: 2, bar: 1}
 *
 *  Unused keys in +other_hash+ are ignored:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.transform_keys!(bat: 3)
 *    # => {foo: 0, bar: 1, baz: 2}
 *
 *  With both argument +other_hash+ and a block given,
 *  derives keys from +other_hash+, the block, and +self+;
 *  all, some, or none of the keys in +self+ may be changed.
 *
 *  For each pair +old_key+ and +value+ in +self+:
 *
 *  - If +other_hash+ has key +old_key+ (with value +new_key+),
 *    does not call the block for that key;
 *    removes the entry for +old_key+: <tt>self.delete(old_key)</tt>;
 *    sets <tt>self[new_key] = value</tt>;
 *    a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys!(baz: :BAZ, bar: :BAR, foo: :FOO) {|key| fail 'Not called' }
 *      # => {FOO: 0, BAR: 1, BAZ: 2}
 *
 *  - If +other_hash+ does not have key +old_key+,
 *    calls the block with +old_key+ and takes its return value as +new_key+;
 *    removes the entry for +old_key+: <tt>self.delete(old_key)</tt>;
 *    sets <tt>self[new_key] = value</tt>;
 *    a duplicate key overwrites:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys!(baz: :BAZ) {|key| key.to_s.reverse }
 *      # => {"oof" => 0, "rab" => 1, BAZ: 2}
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.transform_keys!(baz: :BAZ) {|key| 'ook' }
 *      # => {"ook" => 1, BAZ: 2}
 *
 *  With no argument and no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Transforming Keys and Values}[rdoc-ref:Hash@Methods+for+Transforming+Keys+and+Values].
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

static VALUE
transform_values_call(VALUE hash)
{
    rb_hash_stlike_foreach_with_replace(hash, transform_values_foreach_func, transform_values_foreach_replace, hash);
    return hash;
}

static void
transform_values(VALUE hash)
{
    hash_iter_lev_inc(hash);
    rb_ensure(transform_values_call, hash, hash_foreach_ensure, hash);
}

/*
 *  call-seq:
 *    transform_values {|value| ... } -> new_hash
 *    transform_values -> new_enumerator
 *
 *  With a block given, returns a new hash +new_hash+;
 *  for each pair +key+/+value+ in +self+,
 *  calls the block with +value+ and captures its return as +new_value+;
 *  adds to +new_hash+ the entry +key+/+new_value+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_values {|value| value * 100}
 *    h1 # => {foo: 0, bar: 100, baz: 200}
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Transforming Keys and Values}[rdoc-ref:Hash@Methods+for+Transforming+Keys+and+Values].
 */
static VALUE
rb_hash_transform_values(VALUE hash)
{
    VALUE result;

    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    result = hash_dup_with_compare_by_id(hash);
    SET_DEFAULT(result, Qnil);

    if (!RHASH_EMPTY_P(hash)) {
        transform_values(result);
        compact_after_delete(result);
    }

    return result;
}

/*
 *  call-seq:
 *    transform_values! {|old_value| ... } -> self
 *    transform_values! -> new_enumerator
 *
 *
 *  With a block given, changes the values of +self+ as determined by the block;
 *  returns +self+.
 *
 *  For each entry +key+/+old_value+ in +self+,
 *  calls the block with +old_value+,
 *  captures its return value as +new_value+,
 *  and sets <tt>self[key] = new_value</tt>:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.transform_values! {|value| value * 100} # => {foo: 0, bar: 100, baz: 200}
 *
 *  With no block given, returns a new Enumerator.
 *
 *  Related: see {Methods for Transforming Keys and Values}[rdoc-ref:Hash@Methods+for+Transforming+Keys+and+Values].
 */
static VALUE
rb_hash_transform_values_bang(VALUE hash)
{
    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_modify_check(hash);

    if (!RHASH_TABLE_EMPTY_P(hash)) {
        transform_values(hash);
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
 *    to_a -> new_array
 *
 *  Returns all elements of +self+ as an array of 2-element arrays;
 *  each nested array contains a key-value pair from +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.to_a # => [[:foo, 0], [:bar, 1], [:baz, 2]]
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Hash@Methods+for+Converting].
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
 *    inspect -> new_string
 *
 *  Returns a new string containing the hash entries:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.inspect # => "{foo: 0, bar: 1, baz: 2}"
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Hash@Methods+for+Converting].
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
 *    to_hash -> self
 *
 *  Returns +self+.
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Hash@Methods+for+Converting].
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
 *    to_h {|key, value| ... } -> new_hash
 *    to_h -> self or new_hash
 *
 *  With a block given, returns a new hash whose content is based on the block;
 *  the block is called with each entry's key and value;
 *  the block should return a 2-element array
 *  containing the key and value to be included in the returned array:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.to_h {|key, value| [value, key] }
 *    # => {0 => :foo, 1 => :bar, 2 => :baz}
 *
 *  With no block given, returns +self+ if +self+ is an instance of +Hash+;
 *  if +self+ is a subclass of +Hash+, returns a new hash containing the content of +self+.
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Hash@Methods+for+Converting].
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
 *    keys -> new_array
 *
 *  Returns a new array containing all keys in +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.keys # => [:foo, :bar, :baz]
 *
 *  Related: see {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    values -> new_array
 *
 *  Returns a new array containing all values in +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.values # => [0, 1, 2]
 *
 *  Related: see {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    include?(key) -> true or false
 *
 *  Returns whether +key+ is a key in +self+:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.include?(:bar) # => true
 *    h.include?(:BAR) # => false
 *
 *  Related: {Methods for Querying}[rdoc-ref:Hash@Methods+for+Querying].
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
 *    has_value?(value) -> true or false
 *
 *  Returns whether +value+ is a value in +self+.
 *
 *  Related: {Methods for Querying}[rdoc-ref:Hash@Methods+for+Querying].
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
 *    self == object -> true or false
 *
 *  Returns whether +self+ and +object+ are equal.
 *
 *  Returns +true+ if all of the following are true:
 *
 *  - +object+ is a +Hash+ object (or can be converted to one).
 *  - +self+ and +object+ have the same keys (regardless of order).
 *  - For each key +key+, <tt>self[key] == object[key]</tt>.
 *
 *  Otherwise, returns +false+.
 *
 *  Examples:
 *
 *    h =  {foo: 0, bar: 1}
 *    h == {foo: 0, bar: 1} # => true   # Equal entries (same order)
 *    h == {bar: 1, foo: 0} # => true   # Equal entries (different order).
 *    h == 1                            # => false  # Object not a hash.
 *    h == {}                           # => false  # Different number of entries.
 *    h == {foo: 0, bar: 1} # => false  # Different key.
 *    h == {foo: 0, bar: 1} # => false  # Different value.
 *
 *  Related: see {Methods for Comparing}[rdoc-ref:Hash@Methods+for+Comparing].
 */

static VALUE
rb_hash_equal(VALUE hash1, VALUE hash2)
{
    return hash_equal(hash1, hash2, FALSE);
}

/*
 *  call-seq:
 *    eql?(object) -> true or false
 *
 *  Returns +true+ if all of the following are true:
 *
 *  - The given +object+ is a +Hash+ object.
 *  - +self+ and +object+ have the same keys (regardless of order).
 *  - For each key +key+, <tt>self[key].eql?(object[key])</tt>.
 *
 *  Otherwise, returns +false+.
 *
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1, baz: 2}
 *    h1.eql? h2 # => true
 *    h3 = {baz: 2, bar: 1, foo: 0}
 *    h1.eql? h3 # => true
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Hash@Methods+for+Querying].
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
 *    hash -> an_integer
 *
 *  Returns the integer hash-code for the hash.
 *
 *  Two hashes have the same hash-code if their content is the same
 *  (regardless of order):
 *
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {baz: 2, bar: 1, foo: 0}
 *    h2.hash == h1.hash # => true
 *    h2.eql? h1 # => true
 *
 *  Related: see {Methods for Querying}[rdoc-ref:Hash@Methods+for+Querying].
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
 *    invert -> new_hash
 *
 *  Returns a new hash with each key-value pair inverted:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.invert
 *    h1 # => {0=>:foo, 1=>:bar, 2=>:baz}
 *
 *  Overwrites any repeated new keys
 *  (see {Entry Order}[rdoc-ref:Hash@Entry+Order]):
 *
 *    h = {foo: 0, bar: 0, baz: 0}
 *    h.invert # => {0=>:baz}
 *
 *  Related: see {Methods for Transforming Keys and Values}[rdoc-ref:Hash@Methods+for+Transforming+Keys+and+Values].
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

struct update_call_args {
    VALUE hash, newvalue, *argv;
    int argc;
    bool block_given;
    bool iterating;
};

static int
rb_hash_update_block_callback(st_data_t *key, st_data_t *value, struct update_arg *arg, int existing)
{
    VALUE k = (VALUE)*key, v = (VALUE)*value;
    struct update_call_args *ua = (void *)arg->arg;
    VALUE newvalue = ua->newvalue, hash = arg->hash;

    if (existing) {
        hash_iter_lev_inc(hash);
        ua->iterating = true;
        newvalue = rb_yield_values(3, k, v, newvalue);
        hash_iter_lev_dec(hash);
        ua->iterating = false;
    }
    else if (RHASH_STRING_KEY_P(hash, k) && !RB_OBJ_FROZEN(k)) {
        *key = (st_data_t)rb_hash_key_str(k);
    }
    *value = (st_data_t)newvalue;
    return ST_CONTINUE;
}

NOINSERT_UPDATE_CALLBACK(rb_hash_update_block_callback)

static int
rb_hash_update_block_i(VALUE key, VALUE value, VALUE args)
{
    struct update_call_args *ua = (void *)args;
    ua->newvalue = value;
    RHASH_UPDATE(ua->hash, key, rb_hash_update_block_callback, args);
    return ST_CONTINUE;
}

static VALUE
rb_hash_update_call(VALUE args)
{
    struct update_call_args *arg = (void *)args;

    for (int i = 0; i < arg->argc; i++){
        VALUE hash = to_hash(arg->argv[i]);
        if (arg->block_given) {
            rb_hash_foreach(hash, rb_hash_update_block_i, args);
        }
        else {
            rb_hash_foreach(hash, rb_hash_update_i, arg->hash);
        }
    }
    return arg->hash;
}

static VALUE
rb_hash_update_ensure(VALUE args)
{
    struct update_call_args *ua = (void *)args;
    if (ua->iterating) hash_iter_lev_dec(ua->hash);
    return Qnil;
}

/*
 *  call-seq:
 *    update(*other_hashes) -> self
 *    update(*other_hashes) { |key, old_value, new_value| ... } -> self
 *
 *  Updates values and/or adds entries to +self+; returns +self+.
 *
 *  Each argument +other_hash+ in +other_hashes+ must be a hash.
 *
 *  With no block given, for each successive entry +key+/+new_value+ in each successive +other_hash+:
 *
 *  - If +key+ is in +self+, sets <tt>self[key] = new_value</tt>, whose position is unchanged:
 *
 *      h0 = {foo: 0, bar: 1, baz: 2}
 *      h1 = {bar: 3, foo: -1}
 *      h0.update(h1) # => {foo: -1, bar: 3, baz: 2}
 *
 *  - If +key+ is not in +self+, adds the entry at the end of +self+:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.update({bam: 3, bah: 4}) # => {foo: 0, bar: 1, baz: 2, bam: 3, bah: 4}
 *
 *  With a block given, for each successive entry +key+/+new_value+ in each successive +other_hash+:
 *
 *  - If +key+ is in +self+, fetches +old_value+ from <tt>self[key]</tt>,
 *    calls the block with +key+, +old_value+, and +new_value+,
 *    and sets <tt>self[key] = new_value</tt>, whose position is unchanged  :
 *
 *      season = {AB: 75, H: 20, HR: 3, SO: 17, W: 11, HBP: 3}
 *      today = {AB: 3, H: 1, W: 1}
 *      yesterday = {AB: 4, H: 2, HR: 1}
 *      season.update(yesterday, today) {|key, old_value, new_value| old_value + new_value }
 *      # => {AB: 82, H: 23, HR: 4, SO: 17, W: 12, HBP: 3}
 *
 *  - If +key+ is not in +self+, adds the entry at the end of +self+:
 *
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h.update({bat: 3}) { fail 'Cannot happen' }
 *      # => {foo: 0, bar: 1, baz: 2, bat: 3}
 *
 *  Related: see {Methods for Assigning}[rdoc-ref:Hash@Methods+for+Assigning].
 */

static VALUE
rb_hash_update(int argc, VALUE *argv, VALUE self)
{
    struct update_call_args args = {
        .hash = self,
        .argv = argv,
        .argc = argc,
        .block_given = rb_block_given_p(),
        .iterating = false,
    };
    VALUE arg = (VALUE)&args;

    rb_hash_modify(self);
    return rb_ensure(rb_hash_update_call, arg, rb_hash_update_ensure, arg);
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
 *    merge(*other_hashes) -> new_hash
 *    merge(*other_hashes) { |key, old_value, new_value| ... } -> new_hash
 *
 *  Each argument +other_hash+ in +other_hashes+ must be a hash.
 *
 *  With arguments +other_hashes+ given and no block,
 *  returns the new hash formed by merging each successive +other_hash+
 *  into a copy of +self+;
 *  returns that copy;
 *  for each successive entry in +other_hash+:
 *
 *  - For a new key, the entry is added at the end of +self+.
 *  - For duplicate key, the entry overwrites the entry in +self+,
 *    whose position is unchanged.
 *
 *  Example:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h.merge(h1, h2) # => {foo: 0, bar: 4, baz: 2, bat: 6, bam: 5}
 *
 *  With arguments +other_hashes+ and a block given, behaves as above
 *  except that for a duplicate key
 *  the overwriting entry takes it value not from the entry in +other_hash+,
 *  but instead from the block:
 *
 *  - The block is called with the duplicate key and the values
 *    from both +self+ and +other_hash+.
 *  - The block's return value becomes the new value for the entry in +self+.
 *
 *  Example:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h.merge(h1, h2) { |key, old_value, new_value| old_value + new_value }
 *    # => {foo: 0, bar: 5, baz: 2, bat: 9, bam: 5}
 *
 *  With no arguments, returns a copy of +self+; the block, if given, is ignored.
 *
 *  Related: see {Methods for Assigning}[rdoc-ref:Hash@Methods+for+Assigning].
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
 *    assoc(key) -> entry or nil
 *
 *  If the given +key+ is found, returns its entry as a 2-element array
 *  containing that key and its value:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.assoc(:bar) # => [:bar, 1]
 *
 *  Returns +nil+ if the key is not found.
 *
 *  Related: see {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    rassoc(value) -> new_array or nil
 *
 *  Searches +self+ for the first entry whose value is <tt>==</tt> to the given +value+;
 *  see {Entry Order}[rdoc-ref:Hash@Entry+Order].
 *
 *  If the entry is found, returns its key and value as a 2-element array;
 *  returns +nil+ if not found:
 *
 *    h = {foo: 0, bar: 1, baz: 1}
 *    h.rassoc(1) # => [:bar, 1]
 *
 *  Related: see {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    flatten(depth = 1) -> new_array
 *
 *  With positive integer +depth+,
 *  returns a new array that is a recursive flattening of +self+ to the given +depth+.
 *
 *  At each level of recursion:
 *
 *  - Each element whose value is an array is "flattened" (that is, replaced by its individual array elements);
 *    see Array#flatten.
 *  - Each element whose value is not an array is unchanged.
 *    even if the value is an object that has instance method flatten (such as a hash).
 *
 *  Examples; note that entry <tt>foo: {bar: 1, baz: 2}</tt> is never flattened.
 *
 *   h = {foo: {bar: 1, baz: 2}, bat: [:bam, [:bap, [:bah]]]}
 *   h.flatten(1) # => [:foo, {:bar=>1, :baz=>2}, :bat, [:bam, [:bap, [:bah]]]]
 *   h.flatten(2) # => [:foo, {:bar=>1, :baz=>2}, :bat, :bam, [:bap, [:bah]]]
 *   h.flatten(3) # => [:foo, {:bar=>1, :baz=>2}, :bat, :bam, :bap, [:bah]]
 *   h.flatten(4) # => [:foo, {:bar=>1, :baz=>2}, :bat, :bam, :bap, :bah]
 *   h.flatten(5) # => [:foo, {:bar=>1, :baz=>2}, :bat, :bam, :bap, :bah]
 *
 *  With negative integer +depth+,
 *  flattens all levels:
 *
 *    h.flatten(-1) # => [:foo, {:bar=>1, :baz=>2}, :bat, :bam, :bap, :bah]
 *
 *  With +depth+ zero,
 *  returns the equivalent of #to_a:
 *
 *    h.flatten(0) # => [[:foo, {:bar=>1, :baz=>2}], [:bat, [:bam, [:bap, [:bah]]]]]
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Hash@Methods+for+Converting].
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
 *    compact -> new_hash
 *
 *  Returns a copy of +self+ with all +nil+-valued entries removed:
 *
 *    h = {foo: 0, bar: nil, baz: 2, bat: nil}
 *    h.compact # => {foo: 0, baz: 2}
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    compact! -> self or nil
 *
 *  If +self+ contains any +nil+-valued entries,
 *  returns +self+ with all +nil+-valued entries removed;
 *  returns +nil+ otherwise:
 *
 *    h = {foo: 0, bar: nil, baz: 2, bat: nil}
 *    h.compact!
 *    h          # => {foo: 0, baz: 2}
 *    h.compact! # => nil
 *
 *  Related: see {Methods for Deleting}[rdoc-ref:Hash@Methods+for+Deleting].
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
 *    compare_by_identity -> self
 *
 *  Sets +self+ to compare keys using _identity_ (rather than mere _equality_);
 *  returns +self+:
 *
 *  By default, two keys are considered to be the same key
 *  if and only if they are _equal_ objects (per method #==):
 *
 *    h = {}
 *    h['x'] = 0
 *    h['x'] = 1 # Overwrites.
 *    h # => {"x"=>1}
 *
 *  When this method has been called, two keys are considered to be the same key
 *  if and only if they are the _same_ object:
 *
 *    h.compare_by_identity
 *    h['x'] = 2 # Does not overwrite.
 *    h # => {"x"=>1, "x"=>2}
 *
 *  Related: #compare_by_identity?;
 *  see also {Methods for Comparing}[rdoc-ref:Hash@Methods+for+Comparing].
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
 *    compare_by_identity? -> true or false
 *
 *  Returns whether #compare_by_identity has been called:
 *
 *    h = {}
 *    h.compare_by_identity? # => false
 *    h.compare_by_identity
 *    h.compare_by_identity? # => true
 *
 *  Related: #compare_by_identity;
 *  see also {Methods for Comparing}[rdoc-ref:Hash@Methods+for+Comparing].
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
 *    any? -> true or false
 *    any?(entry) -> true or false
 *    any? {|key, value| ... } -> true or false
 *
 *  Returns +true+ if any element satisfies a given criterion;
 *  +false+ otherwise.
 *
 *  If +self+ has no element, returns +false+ and argument or block are not used;
 *  otherwise behaves as below.
 *
 *  With no argument and no block,
 *  returns +true+ if +self+ is non-empty, +false+ otherwise.
 *
 *  With argument +entry+ and no block,
 *  returns +true+ if for any key +key+
 *  <tt>self.assoc(key) == entry</tt>, +false+ otherwise:
 *
 *   h = {foo: 0, bar: 1, baz: 2}
 *   h.assoc(:bar)     # => [:bar, 1]
 *   h.any?([:bar, 1]) # => true
 *   h.any?([:bar, 0]) # => false
 *
 *  With no argument and a block given,
 *  calls the block with each key-value pair;
 *  returns +true+ if the block returns a truthy value,
 *  +false+ otherwise:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.any? {|key, value| value < 3 } # => true
 *    h.any? {|key, value| value > 3 } # => false
 *
 *  With both argument +entry+ and a block given,
 *  issues a warning and ignores the block.
 *
 *  Related: Enumerable#any? (which this method overrides);
 *  see also {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    dig(key, *identifiers) -> object
 *
 *  Finds and returns an object found in nested objects,
 *  as specified by +key+ and +identifiers+.
 *
 *  The nested objects may be instances of various classes.
 *  See {Dig Methods}[rdoc-ref:dig_methods.rdoc].
 *
 *  Nested hashes:
 *
 *    h = {foo: {bar: {baz: 2}}}
 *    h.dig(:foo) # => {bar: {baz: 2}}
 *    h.dig(:foo, :bar) # => {baz: 2}
 *    h.dig(:foo, :bar, :baz) # => 2
 *    h.dig(:foo, :bar, :BAZ) # => nil
 *
 *  Nested hashes and arrays:
 *
 *    h = {foo: {bar: [:a, :b, :c]}}
 *    h.dig(:foo, :bar, 2) # => :c
 *
 *  If no such object is found,
 *  returns the {hash default}[rdoc-ref:Hash@Hash+Default]:
 *
 *    h = {foo: {bar: [:a, :b, :c]}}
 *    h.dig(:hello) # => nil
 *    h.default_proc = -> (hash, _key) { hash }
 *    h.dig(:hello, :world)
 *    # => {:foo=>{:bar=>[:a, :b, :c]}}
 *
 *  Related: {Methods for Fetching}[rdoc-ref:Hash@Methods+for+Fetching].
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
 *    self <= other_hash -> true or false
 *
 *  Returns +true+ if the entries of +self+ are a subset of the entries of +other_hash+,
 *  +false+ otherwise:
 *
 *    h0 = {foo: 0, bar: 1}
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h0 <= h0 # => true
 *    h0 <= h1 # => true
 *    h1 <= h0 # => false
 *
 *  See {Hash Inclusion}[rdoc-ref:hash_inclusion.rdoc].
 *
 *  Raises TypeError if +other_hash+ is not a hash and cannot be converted to a hash.
 *
 *  Related: see {Methods for Comparing}[rdoc-ref:Hash@Methods+for+Comparing].
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
 *    self < other_hash -> true or false
 *
 *  Returns +true+ if the entries of +self+ are a proper subset of the entries of +other_hash+,
 *  +false+ otherwise:
 *
 *    h = {foo: 0, bar: 1}
 *    h < {foo: 0, bar: 1, baz: 2} # => true   # Proper subset.
 *    h < {baz: 2, bar: 1, foo: 0} # => true   # Order may differ.
 *    h < h                        # => false  # Not a proper subset.
 *    h < {bar: 1, foo: 0}         # => false  # Not a proper subset.
 *    h < {foo: 0, bar: 1, baz: 2} # => false  # Different key.
 *    h < {foo: 0, bar: 1, baz: 2} # => false  # Different value.
 *
 *  See {Hash Inclusion}[rdoc-ref:hash_inclusion.rdoc].
 *
 *  Raises TypeError if +other_hash+ is not a hash and cannot be converted to a hash.
 *
 *  Related: see {Methods for Comparing}[rdoc-ref:Hash@Methods+for+Comparing].
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
 *    self >= other_hash -> true or false
 *
 *  Returns +true+ if the entries of +self+ are a superset of the entries of +other_hash+,
 *  +false+ otherwise:
 *
 *    h0 = {foo: 0, bar: 1, baz: 2}
 *    h1 = {foo: 0, bar: 1}
 *    h0 >= h1 # => true
 *    h0 >= h0 # => true
 *    h1 >= h0 # => false
 *
 *  See {Hash Inclusion}[rdoc-ref:hash_inclusion.rdoc].
 *
 *  Raises TypeError if +other_hash+ is not a hash and cannot be converted to a hash.
 *
 *  Related: see {Methods for Comparing}[rdoc-ref:Hash@Methods+for+Comparing].
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
 *    self > other_hash -> true or false
 *
 *  Returns +true+ if the entries of +self+ are a proper superset of the entries of +other_hash+,
 *  +false+ otherwise:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h > {foo: 0, bar: 1}         # => true   # Proper superset.
 *    h > {bar: 1, foo: 0}         # => true   # Order may differ.
 *    h > h                        # => false  # Not a proper superset.
 *    h > {baz: 2, bar: 1, foo: 0} # => false  # Not a proper superset.
 *    h > {foo: 0, bar: 1}         # => false  # Different key.
 *    h > {foo: 0, bar: 1}         # => false  # Different value.
 *
 *  See {Hash Inclusion}[rdoc-ref:hash_inclusion.rdoc].
 *
 *  Raises TypeError if +other_hash+ is not a hash and cannot be converted to a hash.
 *
 *  Related: see {Methods for Comparing}[rdoc-ref:Hash@Methods+for+Comparing].
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
 *    to_proc -> proc
 *
 *  Returns a Proc object that maps a key to its value:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    proc = h.to_proc
 *    proc.class # => Proc
 *    proc.call(:foo) # => 0
 *    proc.call(:bar) # => 1
 *    proc.call(:nosuch) # => nil
 *
 *  Related: see {Methods for Converting}[rdoc-ref:Hash@Methods+for+Converting].
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
    if (existing) return ST_STOP;
    *val = arg;
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
    int ret = -1;

    if (RHASH_AR_TABLE_P(hash)) {
        ret = ar_update(hash, (st_data_t)key, add_new_i, (st_data_t)val);
        if (ret == -1) {
            ar_force_convert_table(hash, __FILE__, __LINE__);
        }
    }

    if (ret == -1) {
        tbl = RHASH_TBL_RAW(hash);
        ret = st_update(tbl, (st_data_t)key, add_new_i, (st_data_t)val);
    }
    if (!ret) {
        // Newly inserted
        RB_OBJ_WRITTEN(hash, Qundef, key);
        RB_OBJ_WRITTEN(hash, Qundef, val);
    }
    return ret;
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

#define ENV_LOCKING() RB_VM_LOCKING()

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
    ENV_LOCKING() {
        const char *val = getenv(name);
        ret = env_str_new2(val);
    }
    return ret;
}

static bool
has_env_with_lock(const char *name)
{
    const char *val;

    ENV_LOCKING() {
        val = getenv(name);
    }

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

    ENV_LOCKING() {
        /* Use _wputenv_s() instead of SetEnvironmentVariableW() to make sure
         * special variables like "TZ" are interpret by libc. */
        failed = _wputenv_s(wname, wvalue);
    }

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
        ENV_LOCKING() {
            ret = setenv(name, value, 1);
        }

        if (ret) rb_sys_fail_sprintf("setenv(%s)", name);
    }
    else {
#ifdef VOID_UNSETENV
        ENV_LOCKING() {
            unsetenv(name);
        }
#else
        int ret;
        ENV_LOCKING() {
            ret = unsetenv(name);
        }

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

    ENV_LOCKING() {
        for (env_ptr = GET_ENVIRON(environ); (str = *env_ptr) != 0; ++env_ptr) {
            if (!strncmp(str, name, len) && str[len] == '=') {
                if (!in_origenv(str)) free(str);
                while ((env_ptr[0] = env_ptr[1]) != 0) env_ptr++;
                break;
            }
        }
    }

    if (value) {
        int ret;
        ENV_LOCKING() {
            ret = putenv(mem_ptr);
        }

        if (ret) {
            free(mem_ptr);
            rb_sys_fail_sprintf("putenv(%s)", name);
        }
    }
#else  /* WIN32 */
    size_t len;
    int i;

    ENV_LOCKING() {
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

    ENV_LOCKING() {
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

    ENV_LOCKING() {
        env = GET_ENVIRON(environ);
        for (; *env ; ++env) {
            if (strchr(*env, '=')) {
                cnt++;
            }
        }
        FREE_ENVIRON(environ);
    }

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

    ENV_LOCKING() {
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

    ENV_LOCKING() {
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

    ENV_LOCKING() {
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

    ENV_LOCKING() {
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

    ENV_LOCKING() {
        char **env = GET_ENVIRON(environ);
        while (env[i]) i++;
        FREE_ENVIRON(environ);
    }

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

    ENV_LOCKING() {
        char **env = GET_ENVIRON(environ);
        if (env[0] != 0) {
            empty = false;
        }
        FREE_ENVIRON(environ);
    }

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

    ENV_LOCKING() {
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

    ENV_LOCKING() {
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

    ENV_LOCKING() {
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

    return str;
}

static VALUE
env_to_hash(void)
{
    VALUE hash = rb_hash_new();

    ENV_LOCKING() {
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
 *   ENV.to_h { |name, value| [name.to_sym, value.to_i] } # => {bar: 1, foo: 0}
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

    ENV_LOCKING() {
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
 *  A \Hash object maps each of its unique keys to a specific value.
 *
 *  A hash has certain similarities to an Array, but:

 *  - An array index is always an integer.
 *  - A hash key can be (almost) any object.
 *
 *  === \Hash \Data Syntax
 *
 *  The original syntax for a hash entry uses the "hash rocket," <tt>=></tt>:
 *
 *    h = {:foo => 0, :bar => 1, :baz => 2}
 *    h # => {foo: 0, bar: 1, baz: 2}
 *
 *  Alternatively, but only for a key that's a symbol,
 *  you can use a newer JSON-style syntax,
 *  where each bareword becomes a symbol:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h # => {foo: 0, bar: 1, baz: 2}
 *
 *  You can also use a string in place of a bareword:
 *
 *    h = {'foo': 0, 'bar': 1, 'baz': 2}
 *    h # => {foo: 0, bar: 1, baz: 2}
 *
 *  And you can mix the styles:
 *
 *    h = {foo: 0, :bar => 1, 'baz': 2}
 *    h # => {foo: 0, bar: 1, baz: 2}
 *
 *  But it's an error to try the JSON-style syntax
 *  for a key that's not a bareword or a string:
 *
 *    # Raises SyntaxError (syntax error, unexpected ':', expecting =>):
 *    h = {0: 'zero'}
 *
 *  The value can be omitted, meaning that value will be fetched from the context
 *  by the name of the key:
 *
 *    x = 0
 *    y = 100
 *    h = {x:, y:}
 *    h # => {x: 0, y: 100}
 *
 *  === Common Uses
 *
 *  You can use a hash to give names to objects:
 *
 *    person = {name: 'Matz', language: 'Ruby'}
 *    person # => {name: "Matz", language: "Ruby"}
 *
 *  You can use a hash to give names to method arguments:
 *
 *    def some_method(hash)
 *      p hash
 *    end
 *    some_method({foo: 0, bar: 1, baz: 2}) # => {foo: 0, bar: 1, baz: 2}
 *
 *  Note: when the last argument in a method call is a hash,
 *  the curly braces may be omitted:
 *
 *    some_method(foo: 0, bar: 1, baz: 2) # => {foo: 0, bar: 1, baz: 2}
 *
 *  You can use a hash to initialize an object:
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
 *  === Creating a \Hash
 *
 *  You can create a \Hash object explicitly with:
 *
 *  - A {hash literal}[rdoc-ref:syntax/literals.rdoc@Hash+Literals].
 *
 *  You can convert certain objects to hashes with:
 *
 *  - Method Kernel#Hash.
 *
 *  You can create a hash by calling method Hash.new:
 *
 *    # Create an empty hash.
 *    h = Hash.new
 *    h # => {}
 *    h.class # => Hash
 *
 *  You can create a hash by calling method Hash.[]:
 *
 *    # Create an empty hash.
 *    h = Hash[]
 *    h # => {}
 *    # Create a hash with initial entries.
 *    h = Hash[foo: 0, bar: 1, baz: 2]
 *    h # => {foo: 0, bar: 1, baz: 2}
 *
 *  You can create a hash by using its literal form (curly braces):
 *
 *    # Create an empty hash.
 *    h = {}
 *    h # => {}
 *    # Create a +Hash+ with initial entries.
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h # => {foo: 0, bar: 1, baz: 2}
 *
 *  === \Hash Value Basics
 *
 *  The simplest way to retrieve a hash value (instance method #[]):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:foo] # => 0
 *
 *  The simplest way to create or update a hash value (instance method #[]=):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:bat] = 3 # => 3
 *    h # => {foo: 0, bar: 1, baz: 2, bat: 3}
 *    h[:foo] = 4 # => 4
 *    h # => {foo: 4, bar: 1, baz: 2, bat: 3}
 *
 *  The simplest way to delete a hash entry (instance method #delete):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:bar) # => 1
 *    h # => {foo: 0, baz: 2}
 *
 *  === Entry Order
 *
 *  A \Hash object presents its entries in the order of their creation. This is seen in:
 *
 *  - Iterative methods such as <tt>each</tt>, <tt>each_key</tt>, <tt>each_pair</tt>, <tt>each_value</tt>.
 *  - Other order-sensitive methods such as <tt>shift</tt>, <tt>keys</tt>, <tt>values</tt>.
 *  - The string returned by method <tt>inspect</tt>.
 *
 *  A new hash has its initial ordering per the given entries:
 *
 *    h = Hash[foo: 0, bar: 1]
 *    h # => {foo: 0, bar: 1}
 *
 *  New entries are added at the end:
 *
 *    h[:baz] = 2
 *    h # => {foo: 0, bar: 1, baz: 2}
 *
 *  Updating a value does not affect the order:
 *
 *    h[:baz] = 3
 *    h # => {foo: 0, bar: 1, baz: 3}
 *
 *  But re-creating a deleted entry can affect the order:
 *
 *    h.delete(:foo)
 *    h[:foo] = 5
 *    h # => {bar: 1, baz: 3, foo: 5}
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
 *  === Key Not Found?
 *
 *  When a method tries to retrieve and return the value for a key and that key <i>is found</i>,
 *  the returned value is the value associated with the key.
 *
 *  But what if the key <i>is not found</i>?
 *  In that case, certain methods will return a default value while other will raise a \KeyError.
 *
 *  ==== Nil Return Value
 *
 *  If you want +nil+ returned for a not-found key, you can call:
 *
 *  - #[](key) (usually written as <tt>#[key]</tt>.
 *  - #assoc(key).
 *  - #dig(key, *identifiers).
 *  - #values_at(*keys).
 *
 *  You can override these behaviors for #[], #dig, and #values_at (but not #assoc);
 *  see {Hash Default}[rdoc-ref:Hash@Hash+Default].
 *
 *  ==== \KeyError
 *
 *  If you want KeyError raised for a not-found key, you can call:
 *
 *  - #fetch(key).
 *  - #fetch_values(*keys).
 *
 *  ==== \Hash Default
 *
 *  For certain methods (#[], #dig, and #values_at),
 *  the return value for a not-found key is determined by two hash properties:
 *
 *  - <i>default value</i>: returned by method #default.
 *  - <i>default proc</i>: returned by method #default_proc.
 *
 *  In the simple case, both values are +nil+,
 *  and the methods return +nil+ for a not-found key;
 *  see {Nil Return Value}[rdoc-ref:Hash@Nil+Return+Value] above.
 *
 *  Note that this entire section ("Hash Default"):
 *
 *  - Applies _only_ to methods #[], #dig, and #values_at.
 *  - Does _not_ apply to methods #assoc, #fetch, or #fetch_values,
 *    which are not affected by the default value or default proc.
 *
 *  ===== Any-Key Default
 *
 *  You can define an any-key default for a hash;
 *  that is, a value that will be returned for _any_ not-found key:
 *
 *  - The value of #default_proc <i>must be</i> +nil+.
 *  - The value of #default (which may be any object, including +nil+)
 *    will be returned for a not-found key.
 *
 *  You can set the default value when the hash is created with Hash.new and option +default_value+,
 *  or later with method #default=.
 *
 *  Note: although the value of #default may be any object,
 *  it may not be a good idea to use a mutable object.
 *
 *  ===== Per-Key Defaults
 *
 *  You can define a per-key default for a hash;
 *  that is, a Proc that will return a value based on the key itself.
 *
 *  You can set the default proc when the hash is created with Hash.new and a block,
 *  or later with method #default_proc=.
 *
 *  Note that the proc can modify +self+,
 *  but modifying +self+ in this way is not thread-safe;
 *  multiple threads can concurrently call into the default proc
 *  for the same key.
 *
 *  ==== \Method Default
 *
 *  For two methods, you can specify a default value for a not-found key
 *  that has effect only for a single method call
 *  (and not for any subsequent calls):
 *
 *  - For method #fetch, you can specify an any-key default:
 *  - For either method #fetch or method #fetch_values,
 *    you can specify a per-key default via a block.
 *
 *  === What's Here
 *
 *  First, what's elsewhere. Class +Hash+:
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
 *
 *  Class +Hash+ also includes methods from module Enumerable.
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
 *  - #flatten: Returns an array that is a 1-dimensional flattening of +self+.
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
 *  - #flatten!: Returns +self+, flattened.
 *  - #invert: Returns a hash with the each key-value pair inverted.
 *  - #transform_keys: Returns a copy of +self+ with modified keys.
 *  - #transform_keys!: Modifies keys in +self+
 *  - #transform_values: Returns a copy of +self+ with modified values.
 *  - #transform_values!: Modifies values in +self+.
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
     * First, what's elsewhere. Class +ENV+:
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
