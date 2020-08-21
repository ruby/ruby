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
#include "internal/class.h"
#include "internal/cont.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/symbol.h"
#include "internal/time.h"
#include "internal/vm.h"
#include "probes.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby_assert.h"
#include "symbol.h"
#include "transient_heap.h"

#ifndef HASH_DEBUG
#define HASH_DEBUG 0
#endif

#if HASH_DEBUG
#include "gc.h"
#endif

#define HAS_EXTRA_STATES(hash, klass) ( \
    ((klass = has_extra_methods(rb_obj_class(hash))) != 0) || \
    FL_TEST((hash), FL_EXIVAR|RHASH_PROC_DEFAULT) || \
    !NIL_P(RHASH_IFNONE(hash)))

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

static VALUE
has_extra_methods(VALUE klass)
{
    const VALUE base = rb_cHash;
    VALUE c = klass;
    while (c != base) {
	if (rb_class_has_methods(c)) return klass;
	c = RCLASS_SUPER(c);
    }
    return 0;
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

VALUE
rb_hash_freeze(VALUE hash)
{
    return rb_obj_freeze(hash);
}

VALUE rb_cHash;

static VALUE envtbl;
static ID id_hash, id_default, id_flatten_bang;
static ID id_hash_iter_lev;

VALUE
rb_hash_set_ifnone(VALUE hash, VALUE ifnone)
{
    RB_OBJ_WRITE(hash, (&RHASH(hash)->ifnone), ifnone);
    return hash;
}

static int
rb_any_cmp(VALUE a, VALUE b)
{
    if (a == b) return 0;
    if (RB_TYPE_P(a, T_STRING) && RBASIC(a)->klass == rb_cString &&
	RB_TYPE_P(b, T_STRING) && RBASIC(b)->klass == rb_cString) {
	return rb_str_hash_cmp(a, b);
    }
    if (a == Qundef || b == Qundef) return -1;
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

VALUE
rb_hash(VALUE obj)
{
    VALUE hval = rb_exec_recursive_outer(hash_recursive, obj, 0);

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
    return hval;
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
#if SIZEOF_LONG < SIZEOF_ST_INDEX_T
    if (hnum > 0)
	hnum &= (unsigned long)-1 >> 2;
    else
	hnum |= ~((unsigned long)-1 >> 2);
#else
    hnum <<= 1;
    hnum = RSHIFT(hnum, 1);
#endif
    return (long)hnum;
}

static st_index_t
obj_any_hash(VALUE obj)
{
    obj = rb_hash(obj);
    return FIX2LONG(obj);
}

static st_index_t
rb_any_hash(VALUE a)
{
    return any_hash(a, obj_any_hash);
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

typedef st_index_t st_hash_t;

/*
 * RHASH_AR_TABLE_P(h):
 * * as.ar == NULL or
 *   as.ar points ar_table.
 * * as.ar is allocated by transient heap or xmalloc.
 *
 * !RHASH_AR_TABLE_P(h):
 * * as.st points st_table.
 */

#define RHASH_AR_TABLE_MAX_BOUND     RHASH_AR_TABLE_MAX_SIZE

#define RHASH_AR_TABLE_REF(hash, n) (&RHASH_AR_TABLE(hash)->pairs[n])
#define RHASH_AR_CLEARED_HINT 0xff

typedef struct ar_table_pair_struct {
    VALUE key;
    VALUE val;
} ar_table_pair;

typedef struct ar_table_struct {
    /* 64bit CPU: 8B * 2 * 8 = 128B */
    ar_table_pair pairs[RHASH_AR_TABLE_MAX_SIZE];
} ar_table;

size_t
rb_hash_ar_table_size(void)
{
    return sizeof(ar_table);
}

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
    return RHASH(hash)->ar_hint.ary[index];
}

static inline void
ar_hint_set_hint(VALUE hash, unsigned int index, ar_hint_t hint)
{
    RHASH(hash)->ar_hint.ary[index] = hint;
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
        return pair->key == Qundef;
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

#define RHASH_AR_TABLE_BOUND(h) (HASH_ASSERT(RHASH_AR_TABLE_P(h)), \
                                 RHASH_AR_TABLE_BOUND_RAW(h))

#define RHASH_ST_TABLE_SET(h, s)  rb_hash_st_table_set(h, s)
#define RHASH_TYPE(hash) (RHASH_AR_TABLE_P(hash) ? &objhash : RHASH_ST_TABLE(hash)->type)

#define HASH_ASSERT(expr) RUBY_ASSERT_MESG_WHEN(HASH_DEBUG, expr, #expr)

#if HASH_DEBUG
#define hash_verify(hash) hash_verify_(hash, __FILE__, __LINE__)

void
rb_hash_dump(VALUE hash)
{
    rb_obj_info_dump(hash);

    if (RHASH_AR_TABLE_P(hash)) {
        unsigned i, n = 0, bound = RHASH_AR_TABLE_BOUND(hash);

        fprintf(stderr, "  size:%u bound:%u\n",
                RHASH_AR_TABLE_SIZE(hash), RHASH_AR_TABLE_BOUND(hash));

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
                n++;
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
                HASH_ASSERT(k != Qundef);
                HASH_ASSERT(v != Qundef);
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

#if USE_TRANSIENT_HEP
    if (RHASH_TRANSIENT_P(hash)) {
        volatile st_data_t MAYBE_UNUSED(key) = RHASH_AR_TABLE_REF(hash, 0)->key; /* read */
        HASH_ASSERT(RHASH_AR_TABLE(hash) != NULL);
        HASH_ASSERT(rb_transient_heap_managed_ptr_p(RHASH_AR_TABLE(hash)));
    }
#endif
    return hash;
}

#else
#define hash_verify(h) ((void)0)
#endif

static inline int
RHASH_TABLE_NULL_P(VALUE hash)
{
    if (RHASH(hash)->as.ar == NULL) {
        HASH_ASSERT(RHASH_AR_TABLE_P(hash));
        return TRUE;
    }
    else {
        return FALSE;
    }
}

static inline int
RHASH_TABLE_EMPTY_P(VALUE hash)
{
    return RHASH_SIZE(hash) == 0;
}

int
rb_hash_ar_table_p(VALUE hash)
{
    if (FL_TEST_RAW((hash), RHASH_ST_TABLE_FLAG)) {
        HASH_ASSERT(RHASH(hash)->as.st != NULL);
        return FALSE;
    }
    else {
        return TRUE;
    }
}

ar_table *
rb_hash_ar_table(VALUE hash)
{
    HASH_ASSERT(RHASH_AR_TABLE_P(hash));
    return RHASH(hash)->as.ar;
}

st_table *
rb_hash_st_table(VALUE hash)
{
    HASH_ASSERT(!RHASH_AR_TABLE_P(hash));
    return RHASH(hash)->as.st;
}

void
rb_hash_st_table_set(VALUE hash, st_table *st)
{
    HASH_ASSERT(st != NULL);
    FL_SET_RAW((hash), RHASH_ST_TABLE_FLAG);
    RHASH(hash)->as.st = st;
}

static void
hash_ar_table_set(VALUE hash, ar_table *ar)
{
    HASH_ASSERT(RHASH_AR_TABLE_P(hash));
    HASH_ASSERT((RHASH_TRANSIENT_P(hash) && ar == NULL) ? FALSE : TRUE);
    RHASH(hash)->as.ar = ar;
    hash_verify(hash);
}

#define RHASH_SET_ST_FLAG(h)          FL_SET_RAW(h, RHASH_ST_TABLE_FLAG)
#define RHASH_UNSET_ST_FLAG(h)        FL_UNSET_RAW(h, RHASH_ST_TABLE_FLAG)

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

    hash_ar_table_set(h, NULL);
}

static ar_table*
ar_alloc_table(VALUE hash)
{
    ar_table *tab = (ar_table*)rb_transient_heap_alloc(hash, sizeof(ar_table));

    if (tab != NULL) {
        RHASH_SET_TRANSIENT_FLAG(hash);
    }
    else {
        RHASH_UNSET_TRANSIENT_FLAG(hash);
        tab = (ar_table*)ruby_xmalloc(sizeof(ar_table));
    }

    RHASH_AR_TABLE_SIZE_SET(hash, 0);
    RHASH_AR_TABLE_BOUND_SET(hash, 0);
    hash_ar_table_set(hash, tab);

    return tab;
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
    const ar_hint_t *hints = RHASH(hash)->ar_hint.ary;

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
ar_free_and_clear_table(VALUE hash)
{
    ar_table *tab = RHASH_AR_TABLE(hash);

    if (tab) {
        if (RHASH_TRANSIENT_P(hash)) {
            RHASH_UNSET_TRANSIENT_FLAG(hash);
        }
        else {
            ruby_xfree(RHASH_AR_TABLE(hash));
        }
        RHASH_AR_TABLE_CLEAR(hash);
    }
    HASH_ASSERT(RHASH_AR_TABLE_SIZE(hash) == 0);
    HASH_ASSERT(RHASH_AR_TABLE_BOUND(hash) == 0);
    HASH_ASSERT(RHASH_TRANSIENT_P(hash) == 0);
}

static void
ar_try_convert_table(VALUE hash)
{
    if (!RHASH_AR_TABLE_P(hash)) return;

    const unsigned size = RHASH_AR_TABLE_SIZE(hash);

    st_table *new_tab;
    st_index_t i;

    if (size < RHASH_AR_TABLE_MAX_SIZE) {
        return;
    }

    new_tab = st_init_table_with_size(&objhash, size * 2);

    for (i = 0; i < RHASH_AR_TABLE_MAX_BOUND; i++) {
        ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
        st_add_direct(new_tab, pair->key, pair->val);
    }
    ar_free_and_clear_table(hash);
    RHASH_ST_TABLE_SET(hash, new_tab);
    return;
}

static st_table *
ar_force_convert_table(VALUE hash, const char *file, int line)
{
    st_table *new_tab;

    if (RHASH_ST_TABLE_P(hash)) {
        return RHASH_ST_TABLE(hash);
    }

    if (RHASH_AR_TABLE(hash)) {
        unsigned i, bound = RHASH_AR_TABLE_BOUND(hash);

#if RHASH_CONVERT_TABLE_DEBUG
        rb_obj_info_dump(hash);
        fprintf(stderr, "force_convert: %s:%d\n", file, line);
        RB_DEBUG_COUNTER_INC(obj_hash_force_convert);
#endif

        new_tab = st_init_table_with_size(&objhash, RHASH_AR_TABLE_SIZE(hash));

        for (i = 0; i < bound; i++) {
            if (ar_cleared_entry(hash, i)) continue;

            ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
            st_add_direct(new_tab, pair->key, pair->val);
        }
        ar_free_and_clear_table(hash);
    }
    else {
        new_tab = st_init_table(&objhash);
    }
    RHASH_ST_TABLE_SET(hash, new_tab);

    return new_tab;
}

static ar_table *
hash_ar_table(VALUE hash)
{
    if (RHASH_TABLE_NULL_P(hash)) {
        ar_alloc_table(hash);
    }
    return RHASH_AR_TABLE(hash);
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
            hash_ar_table(hash);
        }
        HASH_ASSERT(bin < RHASH_AR_TABLE_MAX_BOUND);

        ar_set_entry(hash, bin, key, val, hash_value);
        RHASH_AR_TABLE_BOUND_SET(hash, bin+1);
        RHASH_AR_TABLE_SIZE_INC(hash);
        return 0;
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
            enum st_retval retval = (*func)(pair->key, pair->val, arg, 0);
            /* pair may be not valid here because of theap */

            switch (retval) {
              case ST_CONTINUE:
                break;
              case ST_CHECK:
              case ST_STOP:
                return 0;
              case ST_REPLACE:
                if (replace) {
                    VALUE key = pair->key;
                    VALUE val = pair->val;
                    retval = (*replace)(&key, &val, arg, TRUE);

                    // TODO: pair should be same as pair before.
                    ar_table_pair *pair = RHASH_AR_TABLE_REF(hash, i);
                    pair->key = key;
                    pair->val = val;
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
        hash_ar_table(hash); /* allocate ltbl if needed */
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

    hash_ar_table(hash); /* prepare ltbl */

    bin = ar_find_entry(hash, hash_value, key);
    if (bin == RHASH_AR_TABLE_MAX_BOUND) {
        if (RHASH_AR_TABLE_SIZE(hash) >= RHASH_AR_TABLE_MAX_SIZE) {
            return -1;
        }
        else if (bin >= RHASH_AR_TABLE_MAX_BOUND) {
            bin = ar_compact_table(hash);
            hash_ar_table(hash);
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

    if (old_tab != NULL) {
        ar_table *new_tab = RHASH_AR_TABLE(hash1);
        if (new_tab == NULL) {
            new_tab = (ar_table*) rb_transient_heap_alloc(hash1, sizeof(ar_table));
            if (new_tab != NULL) {
                RHASH_SET_TRANSIENT_FLAG(hash1);
            }
            else {
                RHASH_UNSET_TRANSIENT_FLAG(hash1);
                new_tab = (ar_table*)ruby_xmalloc(sizeof(ar_table));
            }
        }
        *new_tab = *old_tab;
        RHASH(hash1)->ar_hint.word = RHASH(hash2)->ar_hint.word;
        RHASH_AR_TABLE_BOUND_SET(hash1, RHASH_AR_TABLE_BOUND(hash2));
        RHASH_AR_TABLE_SIZE_SET(hash1, RHASH_AR_TABLE_SIZE(hash2));
        hash_ar_table_set(hash1, new_tab);

        rb_gc_writebarrier_remember(hash1);
        return new_tab;
    }
    else {
        RHASH_AR_TABLE_BOUND_SET(hash1, RHASH_AR_TABLE_BOUND(hash2));
        RHASH_AR_TABLE_SIZE_SET(hash1, RHASH_AR_TABLE_SIZE(hash2));

        if (RHASH_TRANSIENT_P(hash1)) {
            RHASH_UNSET_TRANSIENT_FLAG(hash1);
        }
        else if (RHASH_AR_TABLE(hash1)) {
            ruby_xfree(RHASH_AR_TABLE(hash1));
        }

        hash_ar_table_set(hash1, NULL);

        rb_gc_writebarrier_remember(hash1);
        return old_tab;
    }
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

#if USE_TRANSIENT_HEAP
void
rb_hash_transient_heap_evacuate(VALUE hash, int promote)
{
    if (RHASH_TRANSIENT_P(hash)) {
        ar_table *new_tab;
        ar_table *old_tab = RHASH_AR_TABLE(hash);

        if (UNLIKELY(old_tab == NULL)) {
            rb_gc_force_recycle(hash);
            return;
        }
        HASH_ASSERT(old_tab != NULL);
        if (! promote) {
            new_tab = rb_transient_heap_alloc(hash, sizeof(ar_table));
            if (new_tab == NULL) promote = true;
        }
        if (promote) {
            new_tab = ruby_xmalloc(sizeof(ar_table));
            RHASH_UNSET_TRANSIENT_FLAG(hash);
        }
        *new_tab = *old_tab;
        hash_ar_table_set(hash, new_tab);
    }
    hash_verify(hash);
}
#endif

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
hash_ar_foreach_iter(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    struct hash_foreach_arg *arg = (struct hash_foreach_arg *)argp;
    int status;

    if (error) return ST_STOP;
    status = (*arg->func)((VALUE)key, (VALUE)value, arg->arg);
    /* TODO: rehash check? rb_raise(rb_eRuntimeError, "rehash occurred during iteration"); */

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
hash_foreach_iter(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    struct hash_foreach_arg *arg = (struct hash_foreach_arg *)argp;
    int status;
    st_table *tbl;

    if (error) return ST_STOP;
    tbl = RHASH_ST_TABLE(arg->hash);
    status = (*arg->func)((VALUE)key, (VALUE)value, arg->arg);
    if (RHASH_ST_TABLE(arg->hash) != tbl) {
    	rb_raise(rb_eRuntimeError, "rehash occurred during iteration");
    }
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
iter_lev_in_ivar(VALUE hash)
{
    VALUE levval = rb_ivar_get(hash, id_hash_iter_lev);
    HASH_ASSERT(FIXNUM_P(levval));
    return FIX2INT(levval);
}

void rb_ivar_set_internal(VALUE obj, ID id, VALUE val);

static void
iter_lev_in_ivar_set(VALUE hash, int lev)
{
    rb_ivar_set_internal(hash, id_hash_iter_lev, INT2FIX(lev));
}

static int
iter_lev_in_flags(VALUE hash)
{
    unsigned int u = (unsigned int)((RBASIC(hash)->flags >> RHASH_LEV_SHIFT) & RHASH_LEV_MAX);
    return (int)u;
}

static int
RHASH_ITER_LEV(VALUE hash)
{
    int lev = iter_lev_in_flags(hash);

    if (lev == RHASH_LEV_MAX) {
        return iter_lev_in_ivar(hash);
    }
    else {
        return lev;
    }
}

static void
hash_iter_lev_inc(VALUE hash)
{
    int lev = iter_lev_in_flags(hash);
    if (lev == RHASH_LEV_MAX) {
        lev = iter_lev_in_ivar(hash);
        iter_lev_in_ivar_set(hash, lev+1);
    }
    else {
        lev += 1;
        RBASIC(hash)->flags = ((RBASIC(hash)->flags & ~RHASH_LEV_MASK) | ((VALUE)lev << RHASH_LEV_SHIFT));
        if (lev == RHASH_LEV_MAX) {
            iter_lev_in_ivar_set(hash, lev);
        }
    }
}

static void
hash_iter_lev_dec(VALUE hash)
{
    int lev = iter_lev_in_flags(hash);
    if (lev == RHASH_LEV_MAX) {
        lev = iter_lev_in_ivar(hash);
        HASH_ASSERT(lev > 0);
        iter_lev_in_ivar_set(hash, lev-1);
    }
    else {
        HASH_ASSERT(lev > 0);
        RBASIC(hash)->flags = ((RBASIC(hash)->flags & ~RHASH_LEV_MASK) | ((lev-1) << RHASH_LEV_SHIFT));
    }
}

static VALUE
hash_foreach_ensure_rollback(VALUE hash)
{
    hash_iter_lev_inc(hash);
    return 0;
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
    hash_iter_lev_inc(hash);
    arg.hash = hash;
    arg.func = (rb_foreach_func *)func;
    arg.arg  = farg;
    rb_ensure(hash_foreach_call, (VALUE)&arg, hash_foreach_ensure, hash);
    hash_verify(hash);
}

static VALUE
hash_alloc_flags(VALUE klass, VALUE flags, VALUE ifnone)
{
    const VALUE wb = (RGENGC_WB_PROTECTED_HASH ? FL_WB_PROTECTED : 0);
    NEWOBJ_OF(hash, struct RHash, klass, T_HASH | wb | flags);

    RHASH_SET_IFNONE((VALUE)hash, ifnone);

    return (VALUE)hash;
}

static VALUE
hash_alloc(VALUE klass)
{
    return hash_alloc_flags(klass, 0, Qnil);
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

MJIT_FUNC_EXPORTED VALUE
rb_hash_new_with_size(st_index_t size)
{
    VALUE ret = rb_hash_new();
    if (size == 0) {
        /* do nothing */
    }
    else if (size <= RHASH_AR_TABLE_MAX_SIZE) {
        ar_alloc_table(ret);
    }
    else {
        RHASH_ST_TABLE_SET(ret, st_init_table_with_size(&objhash, size));
    }
    return ret;
}

static VALUE
hash_copy(VALUE ret, VALUE hash)
{
    if (!RHASH_EMPTY_P(hash)) {
        if (RHASH_AR_TABLE_P(hash))
            ar_copy(ret, hash);
        else if (RHASH_ST_TABLE_P(hash))
            RHASH_ST_TABLE_SET(ret, st_copy(RHASH_ST_TABLE(hash)));
    }
    return ret;
}

static VALUE
hash_dup(VALUE hash, VALUE klass, VALUE flags)
{
    return hash_copy(hash_alloc_flags(klass, flags, RHASH_IFNONE(hash)),
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

MJIT_FUNC_EXPORTED VALUE
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

MJIT_FUNC_EXPORTED struct st_table *
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
    VALUE hash;
    VALUE new_key;
    VALUE old_key;
    VALUE new_value;
    VALUE old_value;
};

typedef int (*tbl_update_func)(st_data_t *, st_data_t *, st_data_t, int);

int
rb_hash_stlike_update(VALUE hash, st_data_t key, st_update_callback_func *func, st_data_t arg)
{
    if (RHASH_AR_TABLE_P(hash)) {
        int result = ar_update(hash, (st_data_t)key, func, arg);
        if (result == -1) {
            ar_try_convert_table(hash);
        }
        else {
            return result;
        }
    }

    return st_update(RHASH_ST_TABLE(hash), (st_data_t)key, func, arg);
}

static int
tbl_update(VALUE hash, VALUE key, tbl_update_func func, st_data_t optional_arg)
{
    struct update_arg arg;
    int result;

    arg.arg = optional_arg;
    arg.hash = hash;
    arg.new_key = 0;
    arg.old_key = Qundef;
    arg.new_value = 0;
    arg.old_value = Qundef;

    result = rb_hash_stlike_update(hash, key, func, (st_data_t)&arg);

    /* write barrier */
    if (arg.new_key)   RB_OBJ_WRITTEN(hash, arg.old_key, arg.new_key);
    if (arg.new_value) RB_OBJ_WRITTEN(hash, arg.old_value, arg.new_value);

    return result;
}

#define UPDATE_CALLBACK(iter_lev, func) ((iter_lev) > 0 ? func##_noinsert : func##_insert)

#define RHASH_UPDATE_ITER(h, iter_lev, key, func, a) do {                        \
    tbl_update((h), (key), UPDATE_CALLBACK((iter_lev), func), (st_data_t)(a)); \
} while (0)

#define RHASH_UPDATE(hash, key, func, arg) \
    RHASH_UPDATE_ITER(hash, RHASH_ITER_LEV(hash), key, func, arg)

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

/*
 *  call-seq:
 *     Hash.new                                        -> new_hash
 *     Hash.new(default_value)                         -> new_hash
 *     Hash.new{|hash, key| hash[key] = default_value} -> new_hash
 *
 *  Returns a new empty \Hash object.
 *
 *  The initial default value and initial default proc for the new hash
 *  depend on which form above was used. See {Default Values}[#class-Hash-label-Default+Values].
 *
 *  If neither argument nor block given,
 *  initializes both the default value and the default proc to <tt>nil</tt>:
 *    h = Hash.new
 *    h # => {}
 *    h.class # => Hash
 *    h.default # => nil
 *    h.default_proc # => nil
 *    h[:nosuch] # => nil
 *
 *  If argument <tt>default_value</tt> given but no block given,
 *  initializes the default value to the given <tt>default_value</tt>
 *  and the default proc to <tt>nil</tt>:
 *
 *    h = Hash.new(false)
 *    h # => {}
 *    h.default # => false
 *    h.default_proc # => nil
 *    h[:nosuch] # => false
 *
 *  If block given but no argument given, stores the block as the default proc,
 *  and sets the default value to <tt>nil</tt>:
 *
 *    h = Hash.new { |hash, key| "Default value for #{key}" }
 *    h # => {}
 *    h.default # => nil
 *    h.default_proc.class # => Proc
 *    h[:nosuch] # => "Default value for nosuch"
 *
 *  ---
 *
 *  Raises an exception if both argument <tt>default_value</tt> and a block are given:
 *
 *    # Raises ArgumentError (wrong number of arguments (given 1, expected 0)):
 *    Hash.new(0) { }
 */

static VALUE
rb_hash_initialize(int argc, VALUE *argv, VALUE hash)
{
    VALUE ifnone;

    rb_hash_modify(hash);
    if (rb_block_given_p()) {
	rb_check_arity(argc, 0, 0);
	ifnone = rb_block_proc();
	SET_PROC_DEFAULT(hash, ifnone);
    }
    else {
	rb_check_arity(argc, 0, 1);
	ifnone = argc == 0 ? Qnil : argv[0];
	RHASH_SET_IFNONE(hash, ifnone);
    }

    return hash;
}

/*
 *  call-seq:
 *    Hash[] -> new_empty_hash
 *    Hash[ [*2_element_arrays] ] -> new_hash
 *    Hash[*objects] -> new_hash
 *    Hash[hash] -> new_hash
 *
 *  Returns a new \Hash object populated with the given objects, if any.
 *
 *  The initial default value and default proc are set to <tt>nil</tt>
 *  (see {Default Values}[#class-Hash-label-Default+Values]):
 *
 *    h = Hash[]
 *    h # => {}
 *    h.class # => Hash
 *    h.default # => nil
 *    h.default_proc # => nil
 *
 *  When argument <tt>[*2_element_arrays]</tt> is given,
 *  each element of the outer array must be a 2-element array;
 *  returns a new \Hash object wherein each 2-element array forms a key-value entry:
 *
 *    Hash[ [ [:foo, 0], [:bar, 1] ] ] # => {:foo=>0, :bar=>1}
 *
 *  When arguments <tt>*objects</tt> are given,
 *  the argument count must be an even number;
 *  returns a new \Hash object wherein each successive pair of arguments has become a key-value entry:
 *
 *    Hash[] # => {}
 *    Hash[:foo, 0, :bar, 1] # => {:foo=>0, :bar=>1}
 *
 *  When argument <tt>hash</tt> is given,
 *  the argument must be a \Hash:
 *    class Foo
 *      def to_hash
 *        {foo: 0, bar: 1}
 *      end
 *    end
 *    Hash[Foo.new] # => {:foo=>0, :bar=>1}
 *
 *  ---
 *
 *  Raises an exception if the argument count is 1,
 *  but the argument is not an array of 2-element arrays or a \Hash:
 *    # Raises ArgumentError (odd number of arguments for Hash):
 *    Hash[:foo]
 *    # Raises ArgumentError (invalid number of elements (3 for 1..2)):
 *    Hash[ [ [:foo, 0, 1] ] ]
 *
 *  Raises an exception if the argument count is odd and greater than 1:
 *
 *    # Raises ArgumentError (odd number of arguments for Hash):
 *    Hash[0, 1, 2]
 *
 *  Raises an exception if the argument is an array containing an element
 *  that is not a 2-element array:
 *
 *    # Raises ArgumentError (wrong element type Symbol at 0 (expected array)):
 *    Hash[ [ :foo ] ]
 *
 *  Raises an exception if the argument is an array containing an element
 *  that is an array of size different from 2:
 *
 *    # Raises ArgumentError (invalid number of elements (3 for 1..2)):
 *    Hash[ [ [0, 1, 2] ] ]
 */

static VALUE
rb_hash_s_create(int argc, VALUE *argv, VALUE klass)
{
    VALUE hash, tmp;

    if (argc == 1) {
        tmp = rb_hash_s_try_convert(Qnil, argv[0]);
	if (!NIL_P(tmp)) {
	    hash = hash_alloc(klass);
            hash_copy(hash, tmp);
	    return hash;
	}

	tmp = rb_check_array_type(argv[0]);
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

MJIT_FUNC_EXPORTED VALUE
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
 *    Hash.try_convert(obj) -> new_hash or nil
 *
 *  Returns the Hash object created by calling <tt>obj.to_hash</tt>:
 *    require 'csv' # => true
 *    row = CSV::Row.new(['Name', 'Age'], ['Bob', 45])
 *    row.respond_to?(:to_hash)  # => true
 *    Hash.try_convert(row) # => {"Name"=>"Bob", "Age"=>45}
 *
 *  Returns the given <tt>obj</tt> if it is a Hash:
 *    h = {}
 *    h1 = Hash.try_convert(h)
 *    h1.equal?(h) # => true # Identity check
 *
 *  Returns <tt>nil</tt> unless <tt>obj.respond_to?(:to_hash)</tt>.
 *
 *  ---
 *
 *  Raises an exception unless <tt>obj.to_hash</tt> returns a \Hash object:
 *    class BadToHash
 *      def to_hash
 *        1
 *      end
 *    end
 *    bad = BadToHash.new
 *    Hash.try_convert(bad) # Raises TypeError (can't convert BadToHash to Hash (BadToHash#to_hash gives Integer))
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
    return (RHASH(hash)->basic.flags & RHASH_PASS_AS_KEYWORDS) ? Qtrue : Qfalse;
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
    hash = rb_hash_dup(hash);
    RHASH(hash)->basic.flags |= RHASH_PASS_AS_KEYWORDS;
    return hash;
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
 *  See {Modifying an Active Hash Key}[#class-Hash-label-Modifying+an+Active+Hash+Key].
 *
 *  ---
 *
 *  Raises an exception if called while an iterator is traversing the hash:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (rehash during iteration):
 *    h.each { |x| h.rehash }
 */

VALUE
rb_hash_rehash(VALUE hash)
{
    VALUE tmp;
    st_table *tbl;

    if (RHASH_ITER_LEV(hash) > 0) {
	rb_raise(rb_eRuntimeError, "rehash during iteration");
    }
    rb_hash_modify_check(hash);
    if (RHASH_AR_TABLE_P(hash)) {
        tmp = hash_alloc(0);
        ar_alloc_table(tmp);
        rb_hash_foreach(hash, rb_hash_rehash_i, (VALUE)tmp);
        ar_free_and_clear_table(hash);
        ar_copy(hash, tmp);
        ar_free_and_clear_table(tmp);
    }
    else if (RHASH_ST_TABLE_P(hash)) {
        st_table *old_tab = RHASH_ST_TABLE(hash);
        tmp = hash_alloc(0);
        tbl = st_init_table_with_size(old_tab->type, old_tab->num_entries);
        RHASH_ST_TABLE_SET(tmp, tbl);
        rb_hash_foreach(hash, rb_hash_rehash_i, (VALUE)tmp);
        st_free_table(old_tab);
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

VALUE
rb_hash_default_value(VALUE hash, VALUE key)
{
    if (LIKELY(rb_method_basic_definition_p(CLASS_OF(hash), id_default))) {
	VALUE ifnone = RHASH_IFNONE(hash);
        if (!FL_TEST(hash, RHASH_PROC_DEFAULT)) return ifnone;
	if (key == Qundef) return Qnil;
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
        return st_lookup(RHASH_ST_TABLE(hash), key, pval);
    }
}

MJIT_FUNC_EXPORTED int
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
 *  (see {Default Values}[#class-Hash-label-Default+Values]):
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:nosuch] # => nil
 *
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
 *    hash.fetch(key) -> value
 *    hash.fetch(key, default) -> value
 *    hash.fetch(key) { |key| ... } -> value
 *
 *  Returns the value for the given +key+.
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.fetch(:bar) # => 1
 *
 *  If +key+ is not found, then the given +default+ or
 *  block (if any) will be used:
 *
 *    {}.fetch(:nosuch, :default) # => :default
 *    {}.fetch(:nosuch) { |key| "No #{key}"}) # => "No nosuch"
 *
 *  If neither is given, an error is raised:
 *
 *    {}.fetch(:foo) # => KeyError (key not found: :nosuch)
 *
 *  Note that the #default or #default_proc are always ignored by `fetch`
 *
 *    h = Hash.new(0)
 *    h[:nosuch] # => 0
 *    h.fetch(:nosuch) # => KeyError
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
 *    hash.default -> value
 *    hash.default(key) -> value
 *
 *  With no argument, returns the current default value:
 *    h = {}
 *    h.default # => nil
 *    h.default = false
 *    h.default # => false
 *
 *  With +key+ given, returns the default value for +key+,
 *  regardless of whether that key exists:
 *    h = Hash.new { |hash, key| hash[key] = "No #{key}"}
 #    h[:foo] = "Hello"
 *    h.default(:foo) # => "No foo"
 *
 *  The returned value will be determined either by the default proc or by the default value.
 *  See {Default Values}[#class-Hash-label-Default+Values].
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
 *    hash.default = value -> value
 *
 *  Sets the default value to +value+, returning +value+:
 *    h = {}
 *    h.default # => nil
 *    h.default = false # => false
 *    h.default # => false
 *
 *  See {Default Values}[#class-Hash-label-Default+Values].
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
 *  Returns the default proc:
 *    h = {}
 *    h.default_proc # => nil
 *    h.default_proc = proc { |hash, key| "Default value for #{key}" }
 *    h.default_proc.class # => Proc
 *
 *  See {Default Values}[#class-Hash-label-Default+Values].
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
 *  Sets the default proc to +proc+:
 *    h = {}
 *    h.default_proc # => nil
 *    h.default_proc = proc { |hash, key| "Default value for #{key}" }
 *    h.default_proc.class # => Proc
 *    h.default_proc = nil
 *    h.default_proc # => nil
 *
 *  See {Default Values}[#class-Hash-label-Default+Values].
 *
 *  ---
 *
 *  Raises an exception if +proc+ is not a \Proc:
 *    # Raises TypeError (wrong default_proc type Integer (expected Proc)):
 *    h.default_proc = 1
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
 *  (see {Entry Order}[#class-Hash-label-Entry+Order]):
 *    h = {foo: 0, bar: 2, baz: 2}
 *    h.key(0) # => :foo
 *    h.key(2) # => :bar
 *
 *  Returns +nil+ if so such value is found.
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

/* :nodoc: */
static VALUE
rb_hash_index(VALUE hash, VALUE value)
{
    rb_warn_deprecated("Hash#index", "Hash#key");
    return rb_hash_key(hash, value);
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
 * delete a specified entry a given key.
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

    if (deleted_value != Qundef) { /* likely pass */
	return deleted_value;
    }
    else {
	return Qnil;
    }
}

/*
 *  call-seq:
 *    hash.delete(key) -> value or nil
 *    hash.delete(key) { |key| ... } -> value
 *
 *  Deletes the entry for the given +key+
 *  and returns its associated value.
 *
 *  ---
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

    if (val != Qundef) {
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
 *    hash.shift -> [key, value] or default_value
 *
 *  Removes the first hash entry
 *  (see {Entry Order}[#class-Hash-label-Entry+Order]);
 *  returns a 2-element \Array containing the removed key and value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.shift # => [:foo, 0]
 *    h # => {:bar=>1, :baz=>2}
 *
 *  Returns the default value if the hash is empty
 *  (see {Default Values}[#class-Hash-label-Default+Values]):
 *    h = {}
 *    h.shift # => nil
 */

static VALUE
rb_hash_shift(VALUE hash)
{
    struct shift_var var;

    rb_hash_modify_check(hash);
    if (RHASH_AR_TABLE_P(hash)) {
	var.key = Qundef;
	if (RHASH_ITER_LEV(hash) == 0) {
            if (ar_shift(hash, &var.key, &var.val)) {
		return rb_assoc_new(var.key, var.val);
	    }
	}
	else {
            rb_hash_foreach(hash, shift_i_safe, (VALUE)&var);
            if (var.key != Qundef) {
                rb_hash_delete_entry(hash, var.key);
                return rb_assoc_new(var.key, var.val);
            }
        }
    }
    if (RHASH_ST_TABLE_P(hash)) {
        var.key = Qundef;
        if (RHASH_ITER_LEV(hash) == 0) {
            if (st_shift(RHASH_ST_TABLE(hash), &var.key, &var.val)) {
                return rb_assoc_new(var.key, var.val);
            }
        }
        else {
	    rb_hash_foreach(hash, shift_i_safe, (VALUE)&var);
	    if (var.key != Qundef) {
		rb_hash_delete_entry(hash, var.key);
		return rb_assoc_new(var.key, var.val);
	    }
	}
    }
    return rb_hash_default_value(hash, Qnil);
}

static int
delete_if_i(VALUE key, VALUE value, VALUE hash)
{
    if (RTEST(rb_yield_values(2, key, value))) {
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
 *    h1 = h.delete_if { |key, value| value > 0 }
 *    h1 # => {:foo=>0}
 *    h1.equal?(h) # => true #  Identity check
 *
 *  If no block given, returns a new \Enumerator:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.delete_if # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:delete_if>
 *    h1 = e.each { |key, value| value > 0 }
 *    h1 # => {:foo=>0}
 *    h1.equal?(h) # => true #  Identity check
 *
 *  ----
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration):
 *    h.delete_if { |key, value| h[:new_key] = 3 }
 */

VALUE
rb_hash_delete_if(VALUE hash)
{
    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    rb_hash_modify_check(hash);
    if (!RHASH_TABLE_EMPTY_P(hash)) {
        rb_hash_foreach(hash, delete_if_i, hash);
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
 *    h1 = h.reject! {|key, value| value < 2 }
 *    h1 # => {:baz=>2}
 *    h1.equal?(h) # => true # Identity check
 *
 *  Returns +nil+ if no entries are removed.
 *
 *  Returns a new \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.reject! # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:reject!>
 *    h1 = e.each {|key, value| key.start_with?('b') }
 *    h1 # => {:foo=>0}
 *    h1.equal?(h) # => true # Identity check
 *
 *  ---
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration):
 *    h.reject! { |key, value| h[:new_Key] = 3 }
 */

VALUE
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

static int
reject_i(VALUE key, VALUE value, VALUE result)
{
    if (!RTEST(rb_yield_values(2, key, value))) {
	rb_hash_aset(result, key, value);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.reject {|key, value| ... } -> new_hash
 *    hash.reject -> new_enumerator
 *
 *  Returns a new \Hash object whose entries are all those
 *  from +self+ for which the block returns +false+ or +nil+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.reject {|key, value| key.start_with?('b') }
 *    h1 # => {:foo=>0}
 *
 *  Returns a new \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.reject # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:reject>
 *    h1 = e.each {|key, value| key.start_with?('b') }
 *    h1 # => {:foo=>0}
 */

VALUE
rb_hash_reject(VALUE hash)
{
    VALUE result;

    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    if (RTEST(ruby_verbose)) {
	VALUE klass;
	if (HAS_EXTRA_STATES(hash, klass)) {
	    rb_warn("extra states are no longer copied: %+"PRIsVALUE, hash);
	}
    }
    result = rb_hash_new();
    if (!RHASH_EMPTY_P(hash)) {
	rb_hash_foreach(hash, reject_i, result);
    }
    return result;
}

/*
 *  call-seq:
 *    hash.slice(*keys) -> new_hash
 *
 *  Returns a new \Hash object containing the entries for the given +keys+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.slice(:baz, :foo)
 *    h1 # => {:baz=>2, :foo=>0}
 *    h1.equal?(h) # => false
 *
 *  The given keys that are not found are ignored:
 *    h = {foo: 0, bar: 1}
 *    h.slice(:not_there, :bar, :not_there_either) # => {bar: 1}
 */

static VALUE
rb_hash_slice(int argc, VALUE *argv, VALUE hash)
{
    int i;
    VALUE key, value, result;

    if (argc == 0 || RHASH_EMPTY_P(hash)) {
	return rb_hash_new();
    }
    result = rb_hash_new_with_size(argc);

    for (i = 0; i < argc; i++) {
	key = argv[i];
	value = rb_hash_lookup2(hash, key, Qundef);
	if (value != Qundef)
	    rb_hash_aset(result, key, value);
    }

    return result;
}

/*
 *  call-seq:
 *     hsh.except(*keys) -> a_hash
 *
 *  Returns a hash excluding the given keys and their values.
 *
 *     h = { a: 100, b: 200, c: 300 }
 *     h.except(:a)          #=> {:b=>200, :c=>300}
 *
 *  The given keys that are not found are ignored:
 *     h.except(:b, :c, :not_there, :idem)  #=> {:a=>100}
 */

static VALUE
rb_hash_except(int argc, VALUE *argv, VALUE hash)
{
    int i;
    VALUE key, result;

    result = rb_obj_dup(hash);

    for (i = 0; i < argc; i++) {
        key = argv[i];
        rb_hash_delete(result, key);
    }

    return result;
}

/*
 *  call-seq:
 *    hash.values_at(*keys) -> new_array
 *
 *  Returns a new \Array containing values for the given +keys+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.values_at(:foo, :baz) # => [0, 2]
 *
 *  The {default values}[#class-Hash-label-Default+Values] will be used for keys
 *  that are not present:
 *    h.values_at(:hello, :foo) # => [nil, 0]
 *    h.default = -1
 *    h.values_at(:hello, :foo) # => [-1, 0]
 */

VALUE
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
 *  Returns a new \Array containing the values associated with the given keys *keys:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.fetch_values(:baz, :foo) # => [2, 0]
 *
 *  Returns a new empty \Array if no arguments given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.fetch_values # => []
 *
 *  When a block given, calls the block with each missing key,
 *  treating the block's return value as the value for that key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    values = h.fetch_values(:bar, :foo, :bad, :bam) {|key| key.to_s}
 *    values # => [1, 0, "bad", "bam"]
 *
 *  ---
 *
 *  When no block is given, raises an exception if any given key is not found:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.fetch_values(:baz, :nosuch) # Raises KeyError (key not found: :nosuch)
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
select_i(VALUE key, VALUE value, VALUE result)
{
    if (RTEST(rb_yield_values(2, key, value))) {
	rb_hash_aset(result, key, value);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.select {|key, value| ... } -> new_hash
 *    hash.select -> new_enumerator
 *    hash.filter {|key, value| ... } -> new_hash
 *    hash.filter -> new_enumerator
 *
 *  Hash#filter is an alias for Hash#select.
 *
 *  Returns a new \Hash object whose entries are those for which the block returns a truthy value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.select {|key, value| value < 2 }
 *    h1 # => {:foo=>0, :bar=>1}
 *    h1.equal?(h) # => false
 *
 *  Returns a new \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.select # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:select>
 *    h1 = e.each {|key, value| value < 2 }
 *    h1 # => {:foo=>0, :bar=>1}
 *    h1.equal?(h) # => false
 *
 *  ---
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration):
 *    h.select {|key, value| h[:new_key] = 3 }
 */

static VALUE
rb_hash_select(VALUE hash)
{
    VALUE result;

    RETURN_SIZED_ENUMERATOR(hash, 0, 0, hash_enum_size);
    result = rb_hash_new();
    if (!RHASH_EMPTY_P(hash)) {
	rb_hash_foreach(hash, select_i, result);
    }
    return result;
}

static int
keep_if_i(VALUE key, VALUE value, VALUE hash)
{
    if (!RTEST(rb_yield_values(2, key, value))) {
	return ST_DELETE;
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.select! {|key, value| ... } -> self or nil
 *    hash.select! -> new_enumerator
 *    hash.filter! {|key, value| ... } -> self or nil
 *    hash.filter! -> new_enumerator
 *
 *  Hash#filter! is an alias for Hash#select!.
 *
 *  Returns +self+, whose entries are those for which the block returns a truthy value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.select! {|key, value| value < 2 }
 *    h # => {:foo=>0, :bar=>1}
 *    h1.equal?(h) # => true
 *
 *  Returns +nil+ if no entries were removed.
 *
 *  Returns a new \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.select!  # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:select!>
 *    h1 = e.each { |key, value| value < 2 }
 *    h1 # => {:foo=>0, :bar=>1}
 *    h1.equal?(h) # => true
 *
 *  ---
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration)
 *    h.select! {|key, value| h[:new_key] = 3 }
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
 *  deletes the entry otherwise; returns +self+.
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.keep_if { |key, value| key.start_with?('b') }
 *    h1 # => {:bar=>1, :baz=>2}
 *    h1.object_id == h.object_id # => true
 *
 *  Returns a new \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.keep_if # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:keep_if>
 *    h1 = e.each { |key, value| key.start_with?('b') }
 *    h1 # => {:bar=>1, :baz=>2}
 *    h1.object_id == h.object_id # => true
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration):
 *    h.keep_if { |key, value| h[:new_key] = 3 }
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
 *  Removes all hash entries; returns +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.clear # => {}
 *    h1.equal?(h) # => true # Identity check
 */

VALUE
rb_hash_clear(VALUE hash)
{
    rb_hash_modify_check(hash);

    if (RHASH_ITER_LEV(hash) > 0) {
        rb_hash_foreach(hash, clear_i, 0);
    }
    else if (RHASH_AR_TABLE_P(hash)) {
        ar_clear(hash);
    }
    else {
        st_clear(RHASH_ST_TABLE(hash));
    }

    return hash;
}

static int
hash_aset(st_data_t *key, st_data_t *val, struct update_arg *arg, int existing)
{
    if (existing) {
	arg->new_value = arg->arg;
	arg->old_value = *val;
    }
    else {
	arg->new_key = *key;
	arg->new_value = arg->arg;
    }
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
 *  Associates the given +value+ with the given +key+, and returns +value+.
 *
 *  If the given +key+ exists, replaces its value with the given +value+;
 *  the ordering is not affected
 *  (see {Entry Order}[#class-Hash-label-Entry+Order]):
 *    h = {foo: 0, bar: 1}
 *    h[:foo] = 2 # => 2
 *    h.store(:bar, 3) # => 3
 *    h # => {:foo=>2, :bar=>3}
 *
 *  If +key+ does not exist, adds the +key+ and +value+;
 *  the new entry is last in the order
 *  (see {Entry Order}[#class-Hash-label-Entry+Order]):
 *    h = {foo: 0, bar: 1}
 *    h[:baz] = 2 # => 2
 *    h.store(:bat, 3) # => 3
 *    h # => {:foo=>0, :bar=>1, :baz=>2, :bat=>3}
 */

VALUE
rb_hash_aset(VALUE hash, VALUE key, VALUE val)
{
    int iter_lev = RHASH_ITER_LEV(hash);

    rb_hash_modify(hash);

    if (RHASH_TABLE_NULL_P(hash)) {
	if (iter_lev > 0) no_new_key();
        ar_alloc_table(hash);
    }

    if (RHASH_TYPE(hash) == &identhash || rb_obj_class(key) != rb_cString) {
	RHASH_UPDATE_ITER(hash, iter_lev, key, hash_aset, val);
    }
    else {
	RHASH_UPDATE_ITER(hash, iter_lev, key, hash_aset_str, val);
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
 *    h1 = h.replace({bat: 3, bam: 4})
 *    h1 # => {:bat=>3, :bam=>4}
 *    h1.equal?(h) # => true # Identity check
 */

static VALUE
rb_hash_replace(VALUE hash, VALUE hash2)
{
    rb_hash_modify_check(hash);
    if (hash == hash2) return hash;
    if (RHASH_ITER_LEV(hash) > 0) {
        rb_raise(rb_eRuntimeError, "can't replace hash during iteration");
    }
    hash2 = to_hash(hash2);

    COPY_DEFAULT(hash, hash2);

    if (RHASH_AR_TABLE_P(hash)) {
        if (RHASH_AR_TABLE_P(hash2)) {
            ar_clear(hash);
        }
        else {
            ar_free_and_clear_table(hash);
            RHASH_ST_TABLE_SET(hash, st_init_table_with_size(RHASH_TYPE(hash2), RHASH_SIZE(hash2)));
        }
    }
    else {
        if (RHASH_AR_TABLE_P(hash2)) {
            st_free_table(RHASH_ST_TABLE(hash));
            RHASH_ST_CLEAR(hash);
        }
        else {
            st_clear(RHASH_ST_TABLE(hash));
            RHASH_TBL_RAW(hash)->type = RHASH_ST_TABLE(hash2)->type;
        }
    }
    rb_hash_foreach(hash2, rb_hash_rehash_i, (VALUE)hash);

    rb_gc_writebarrier_remember(hash);

    return hash;
}

/*
 *  call-seq:
 *     hash.length -> integer
 *     hash.size -> integer
 *
 *  Returns the count of entries in +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.length # => 3
 *
 *  Hash#length is an alias for Hash#size.
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

static VALUE
rb_hash_empty_p(VALUE hash)
{
    return RHASH_EMPTY_P(hash) ? Qtrue : Qfalse;
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
 *    h1 = h.each_value {|value| puts value }
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1.equal?(h) # => true # Identity check
 *  Output:
 *    0
 *    1
 *    2
 *
 *  Returns an \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.each_value # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:each_value>
 *    h1 = e.each {|value| puts value }
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    0
 *    1
 *    2
 *
 *  ---
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration):
 *    h.each_value {|value| h[:new_key] = 3 }
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
 *    h1 = h.each_key {|key| puts key }
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1.equal?(h) # => true # Identity check
 *  Output:
 *    foo
 *    bar
 *    baz
 *
 *  Returns an \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.each_key # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:each_key>
 *    h1 = e.each {|key| puts key }
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    foo
 *    bar
 *    baz
 *
 *  ---
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration):
 *    h.each_key {|key| h[:new_key] = 3 }
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
 *  Calls the given block with each key-value pair, returning self:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.each_pair {|key, value| puts "#{key}: #{value}"}
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1.equal?(h) # => true # Identity check
 *  Output:
 *    foo: 0
 *    bar: 1
 *    baz: 2
 *
 *  Returns an \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.each_pair # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:each_pair>
 *    h1 = e.each {|key, value| puts "#{key}: #{value}"}
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *  Output:
 *    foo: 0
 *    bar: 1
 *    baz: 2
 *
 *  ---
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration)
 *    h.each_pair {|key, value| h[:new_key] = 3 }
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
    if (new_key == Qundef) {
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
 *    hash.transform_keys -> new_enumerator
 *
 *  Returns a new \Hash object; each entry has:
 *  * A key provided by the block.
 *  * The value from +self+.
 *
 *  Transform keys:
 *      h = {foo: 0, bar: 1, baz: 2}
 *      h1 = h.transform_keys {|key| key.to_s }
 *      h1 # => {"foo"=>0, "bar"=>1, "baz"=>2}
 *
 *  Overwrites values for duplicate keys:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_keys {|key| :bat }
 *    h1 # => {:bat=>2}
 *
 *  Returns a new \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.transform_keys # => #<Enumerator: {:foo=>0, :bar=>1, :baz=>2}:transform_keys>
 *    h1 = e.each { |key| key.to_s }
 *    h1 # => {"foo"=>0, "bar"=>1, "baz"=>2}
 *
 *  ---
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration)
 *    h.transform_keys {|key| h[:new_key] = 3 }
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

static VALUE rb_hash_flatten(int argc, VALUE *argv, VALUE hash);

/*
 *  call-seq:
 *    hash.transform_keys! {|key| ... } -> self
 *    hash.transform_keys! -> new_enumerator
 *
 *  Returns +self+ with new keys provided by the block:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_keys! {|key| key.to_s }
 *    h1 # => {"foo"=>0, "bar"=>1, "baz"=>2}
 *    h1.equal?(h) # => true # Identity check
 *
 *  Overwrites values for duplicate keys:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_keys! {|key| :bat }
 *    h1 # => {:bat=>2}
 *
 *  Allows the block to add a new entry:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_keys! {|key| h[:new_key] = key.to_s }
 *    h1 # => {:new_key=>"baz", "foo"=>0, "bar"=>1, "baz"=>2}
 *
 *  Returns a new \Enumerator if no block given:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    e = h.transform_keys! # => #<Enumerator: {"foo"=>0, "bar"=>1, "baz"=>2}:transform_keys!>
 *    h1 = e.each { |key| key.to_s }
 *    h1 # => {"foo"=>0, "bar"=>1, "baz"=>2}
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
        VALUE pairs = rb_hash_flatten(0, NULL, hash);
        rb_hash_clear(hash);
        for (i = 0; i < RARRAY_LEN(pairs); i += 2) {
            VALUE key = RARRAY_AREF(pairs, i), new_key, val;

            if (!trans) {
                new_key = rb_yield(key);
            }
            else if ((new_key = rb_hash_lookup2(trans, key, Qundef)) != Qundef) {
                /* use the transformed key */
            }
            else if (block_given) {
                new_key = rb_yield(key);
            }
            else {
                new_key = key;
            }
            val = RARRAY_AREF(pairs, i+1);
            rb_hash_aset(hash, new_key, val);
        }
    }
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
    RB_OBJ_WRITE(hash, value, new_value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    hash.transform_values {|value| ... } -> new_hash
 *    hash.transform_values -> new_enumerator
 *
 *  Returns a new \Hash object; each entry has:
 *  * A key from +self+.
 *  * A value provided by the block.
 *
 *  Transform values:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_values {|value| value * 100}
 *    h1 # => {:foo=>0, :bar=>100, :baz=>200}
 *
 *  Ignores an attempt in the block to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_values {|value| h[:new_key] = 3; value * 100 }
 *    h1 # => {:foo=>0, :bar=>100, :baz=>200}
 *
 *  Returns a new \Enumerator if no block given:
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
    result = hash_copy(hash_alloc(rb_cHash), hash);

    if (!RHASH_EMPTY_P(hash)) {
        rb_hash_stlike_foreach_with_replace(result, transform_values_foreach_func, transform_values_foreach_replace, result);
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
 *    h1 = h.transform_values! {|value| value * 100}
 *    h1 # => {:foo=>0, :bar=>100, :baz=>200}
 *    h1.equal?(h) # => true # Identity check
 *
 *  Allows the block to add a new entry:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.transform_values! {|value| h[:new_key] = 3; value * 100 }
 *    h1 # => {:foo=>0, :bar=>100, :baz=>200, :new_key=>3}
 *
 *  Returns a new \Enumerator if no block given:
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
 *  Returns a new \Array of 2-element \Array objects;
 *  each nested \Array contains the key and value for a hash entry:
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

static int
inspect_i(VALUE key, VALUE value, VALUE str)
{
    VALUE str2;

    str2 = rb_inspect(key);
    if (RSTRING_LEN(str) > 1) {
	rb_str_buf_cat_ascii(str, ", ");
    }
    else {
	rb_enc_copy(str, str2);
    }
    rb_str_buf_append(str, str2);
    rb_str_buf_cat_ascii(str, "=>");
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
 *  Returns a new \String containing the hash entries:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.inspect # => "{:foo=>0, :bar=>1, :baz=>2}"
 *
 *  Hash#to_s is an alias for Hash#inspect.
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
 *  Returns +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.to_hash
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1.equal?(h) # => true # Identity check
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
 *  For an instance of \Hash, returns +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.to_h
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1.equal?(h) #  => true # Identity check
 *
 *  For a subclass of \Hash, returns a new \Hash
 *  containing the content of +self+:
 *    class MyHash < Hash; end
 *    h = MyHash[foo: 0, bar: 1, baz: 2]
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *    h.class # => MyHash
 *    h1 = h.to_h
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1.class # => Hash
 *
 *  When a block is given, returns a new \Hash object
 *  whose content is based on the block;
 *  the block should return a 2-element \Array object
 *  specifying the key-value pair to be included in the returned \Array:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.to_h {|key, value| [value, key] }
 *    h1 # => {0=>:foo, 1=>:bar, 2=>:baz}
 *
 *  ---
 *
 *  Raises an exception if the block does not return an \Array:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises TypeError (wrong element type Symbol (expected array)):
 *    h1 = h.to_h {|key, value| :array }
 *
 *  Raises an exception if the block returns an \Array of size different from 2:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises ArgumentError (element has wrong array length (expected 2, was 3)):
 *    h1 = h.to_h {|key, value| [0, 1, 2] }
 *
 *  Raises an exception if the block attempts to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    # Raises RuntimeError (can't add a new key into hash during iteration):
 *    h.to_h {|key, value| h[:new_key] = 3 }
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
 *  hash.keys -> new_array
 *
 *  Returns a new \Array containing all keys in +self+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.keys # => [:foo, :bar, :baz]
 */

MJIT_FUNC_EXPORTED VALUE
rb_hash_keys(VALUE hash)
{
    st_index_t size = RHASH_SIZE(hash);
    VALUE keys =  rb_ary_new_capa(size);

    if (size == 0) return keys;

    if (ST_DATA_COMPATIBLE_P(VALUE)) {
        RARRAY_PTR_USE_TRANSIENT(keys, ptr, {
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
 *  Returns a new \Array containing all values in +self+:
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
            RARRAY_PTR_USE_TRANSIENT(values, ptr, {
                size = ar_values(hash, ptr, size);
            });
        }
        else if (RHASH_ST_TABLE_P(hash)) {
            st_table *table = RHASH_ST_TABLE(hash);
            rb_gc_writebarrier_remember(values);
            RARRAY_PTR_USE_TRANSIENT(values, ptr, {
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

 *  Methods #has_key?, #key?, and #member? are aliases for \#include?.
 *
 *  Returns +true+ if +key+ is a key in +self+, otherwise +false+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.include?(:bar) # => true
 *    h.include?(:nosuch) # => false
 */

MJIT_FUNC_EXPORTED VALUE
rb_hash_has_key(VALUE hash, VALUE key)
{
    if (hash_stlike_lookup(hash, key, NULL)) {
        return Qtrue;
    }
    else {
        return Qfalse;
    }
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
 *
 *  Returns +true+ if +value+ is a value in +self+, otherwise +false+:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.has_value?(1) # => true
 *    h.has_value?(123) # => false
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
 *  * +object+ is a \Hash object.
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
*
 *  Not equal because of class:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h1 == 1 # false
 *
 *  Not equal because of different keys:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1, zab: 2}
 *    h1 == h2 # => false
 *
 *  Not equal because of different values:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1, baz: 3}
 *    h1 == h2 # => false
 */

static VALUE
rb_hash_equal(VALUE hash1, VALUE hash2)
{
    return hash_equal(hash1, hash2, FALSE);
}

/*
 *  call-seq:
 *    hash.eql? object -> true or false
 *
 *  Returns +true+ if all of the following are true:
 *  * +object+ is a \Hash object.
 *  * +hash+ and +object+ have the same keys (regardless of order).
 *  * For each key +key+, <tt>h[key] eql? object[key]</tt>.
 *
 *  Otherwise, returns +false+.
 *
 *  Equal:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1, baz: 2}
 *    h1.eql? h2 # => true
 *    h3 = {baz: 2, bar: 1, foo: 0}
 *    h1.eql? h3 # => true
 *
 *  Not equal because of class:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h1.eql? 1 # false
 *
 *  Not equal because of different keys:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1, zab: 2}
 *    h1.eql? h2 # => false
 *
 *  Not equal because of different values:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h2 = {foo: 0, bar: 1, baz: 3}
 *    h1.eql? h2 # => false
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
 *  Returns the \Integer hash-code for the hash:
 *    h1 = {foo: 0, bar: 1, baz: 2}
 *    h1.hash.class # => Integer
 *
 *  Two \Hash objects have the same hash-code if their content is the same
 *  (regardless or order):
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
 *  Returns a new \Hash object with the each key-value pair inverted:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.invert
 *    h1 # => {0=>:foo, 1=>:bar, 2=>:baz}
 *
 *  Overwrites any repeated new keys:
 *  (see {Entry Order}[#class-Hash-label-Entry+Order]):
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
rb_hash_update_callback(st_data_t *key, st_data_t *value, struct update_arg *arg, int existing)
{
    if (existing) {
	arg->old_value = *value;
	arg->new_value = arg->arg;
    }
    else {
	arg->new_key = *key;
	arg->new_value = arg->arg;
    }
    *value = arg->arg;
    return ST_CONTINUE;
}

NOINSERT_UPDATE_CALLBACK(rb_hash_update_callback)

static int
rb_hash_update_i(VALUE key, VALUE value, VALUE hash)
{
    RHASH_UPDATE(hash, key, rb_hash_update_callback, value);
    return ST_CONTINUE;
}

static int
rb_hash_update_block_callback(st_data_t *key, st_data_t *value, struct update_arg *arg, int existing)
{
    VALUE newvalue = (VALUE)arg->arg;

    if (existing) {
	newvalue = rb_yield_values(3, (VALUE)*key, (VALUE)*value, newvalue);
	arg->old_value = *value;
    }
    else {
	arg->new_key = *key;
    }
    arg->new_value = newvalue;
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
 *  Each argument in +other_hashes+ must be a \Hash.
 *
 *  \Method #update is an alias for \#merge!.
 *
 *  ---
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
 *    h3 = h.merge!(h1, h2) # => {:foo=>0, :bar=>4, :baz=>2, :bat=>6, :bam=>5}
 *    h3.equal?(h) # => true # Identity check
 *
 *  ---
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
 *    h3.equal?(h) # => true # Identity check
 *
 *  Allows the block to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h3 = h.merge!(h1, h2) { |key, old_value, new_value| h[:new_key] = 10 }
 *    h3 # => {:foo=>0, :bar=>10, :baz=>2, :bat=>10, :new_key=>10, :bam=>5}
 *    h3.equal?(h) # => true # Identity check
 *
 *  ---
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
 *    h1.equal?(h) # => true # Identity check
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
	arg->old_value = *value;
    }
    else {
	arg->new_key = *key;
    }
    arg->new_value = newvalue;
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
 *  Returns the new \Hash formed by merging each of +other_hashes+
 *  into a copy of +self+.
 *
 *  Each argument in +other_hashes+ must be a \Hash.
 *
 *  ---
 *
 *  With arguments and no block:
 *  * Returns the new \Hash object formed by merging each successive
 *    \Hash in +other_hashes+ into +self+.
 *  * Each new-key entry is added at the end.
 *  * Each duplicate-key entry's value overwrites the previous value.
 *
 *  Example:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h3 = h.merge(h1, h2)
 *    h3 # => {:foo=>0, :bar=>4, :baz=>2, :bat=>6, :bam=>5}
 *    h3.equal?(h) # => false # Identity check
 *
 *  ---
 *
 *  With arguments and a block:
 *  * Returns a new \Hash object that is the merge of +self+ and each given hash.
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
 *    h3.equal?(h) # => false # Identity check
 *
 *  Ignores an attempt in the block to add a new key:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = {bat: 3, bar: 4}
 *    h2 = {bam: 5, bat:6}
 *    h3 = h.merge(h1, h2) { |key, old_value, new_value| h[:new_key] = 10 }
 *    h3 # => {:foo=>0, :bar=>10, :baz=>2, :bat=>10, :bam=>5}
 *    h3.equal?(h) # => false # Identity check
 *
 *  ---
 *
 *  With no arguments:
 *  * Returns a copy of +self+.
 *  * The block, if given, is ignored.
 *
 *  Example:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h1 = h.merge
 *    h1 # => {:foo=>0, :bar=>1, :baz=>2}
 *    h1.equal?(h) # => false # Identity check
 *    h2 = h.merge { |key, old_value, new_value| raise 'Cannot happen' }
 *    h2 # => {:foo=>0, :bar=>1, :baz=>2}
 *    h2.equal?(h) # => false # Identity check
 */

static VALUE
rb_hash_merge(int argc, VALUE *argv, VALUE self)
{
    return rb_hash_update(argc, argv, rb_hash_dup(self));
}

static int
assoc_cmp(VALUE a, VALUE b)
{
    return !RTEST(rb_equal(a, b));
}

static VALUE
lookup2_call(VALUE arg)
{
    VALUE *args = (VALUE *)arg;
    return rb_hash_lookup2(args[0], args[1], Qundef);
}

struct reset_hash_type_arg {
    VALUE hash;
    const struct st_hash_type *orighash;
};

static VALUE
reset_hash_type(VALUE arg)
{
    struct reset_hash_type_arg *p = (struct reset_hash_type_arg *)arg;
    HASH_ASSERT(RHASH_ST_TABLE_P(p->hash));
    RHASH_ST_TABLE(p->hash)->type = p->orighash;
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
 *  If the given +key+ is found, returns a 2-element \Array containing that key and its value:
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.assoc(:bar) # => [:bar, 1]
 *
 *  Returns +nil+ if key +key+ is not found.
 */

VALUE
rb_hash_assoc(VALUE hash, VALUE key)
{
    st_table *table;
    const struct st_hash_type *orighash;
    VALUE args[2];

    if (RHASH_EMPTY_P(hash)) return Qnil;

    ar_force_convert_table(hash, __FILE__, __LINE__);
    HASH_ASSERT(RHASH_ST_TABLE_P(hash));
    table = RHASH_ST_TABLE(hash);
    orighash = table->type;

    if (orighash != &identhash) {
	VALUE value;
	struct reset_hash_type_arg ensure_arg;
	struct st_hash_type assochash;

	assochash.compare = assoc_cmp;
	assochash.hash = orighash->hash;
        table->type = &assochash;
	args[0] = hash;
	args[1] = key;
	ensure_arg.hash = hash;
	ensure_arg.orighash = orighash;
	value = rb_ensure(lookup2_call, (VALUE)&args, reset_hash_type, (VALUE)&ensure_arg);
	if (value != Qundef) return rb_assoc_new(key, value);
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
 *  Returns a new 2-element \Array consisting of the key and value
 *  of the first-found entry whose value is <tt>==</tt> to value
 *  (see {Entry Order}[#class-Hash-label-Entry+Order]):
 *    h = {foo: 0, bar: 1, baz: 1}
 *    h.rassoc(1) # => [:bar, 1]
 *
 *  Returns +nil+ if no such value found.
 */

VALUE
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
 *  Argument +level+, if given, must be an \Integer.
 *
 *  Returns a new \Array object that is a 1-dimensional flattening of +self+.
 *
 *  ---
 *
 *  By default, nested Arrays are not flattened:
 *    h = {foo: 0, bar: [:bat, 3], baz: 2}
 *    h.flatten # => [:foo, 0, :bar, [:bat, 3], :baz, 2]
 *
 *  Takes the depth of recursive flattening from argument +level+:
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

static int
set_if_not_nil(VALUE key, VALUE value, VALUE hash)
{
    if (!NIL_P(value)) {
	rb_hash_aset(hash, key, value);
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
    VALUE result = rb_hash_new();
    if (!RHASH_EMPTY_P(hash)) {
	rb_hash_foreach(hash, set_if_not_nil, result);
    }
    return result;
}

/*
 *  call-seq:
 *    hash.compact! -> self or nil
 *
 *  Returns +self+ with all its +nil+-valued entries removed (in place):
 *    h = {foo: 0, bar: nil, baz: 2, bat: nil}
 *    h1 = h.compact!
 *    h1 # => {:foo=>0, :baz=>2}
 *    h1.equal?(h) # => true
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

static st_table *rb_init_identtable_with_size(st_index_t size);

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
 *    s0.equal?(s0) # => false
 *    h = {}
 *    h.compare_by_identity? # => false
 *    h[s0] = 0
 *    h[s1] = 1
 *    h # => {"x"=>1}
 *
 *  After calling \#compare_by_identity, the keys are considered to be different,
 *  and therefore do not overwrite each other:
 *    h = {}
 *    h1 = h.compare_by_identity # => {}
 *    h1.equal?(h) # => true
 *    h.compare_by_identity? # => true
 *    h[s0] = 0
 *    h[s1] = 1
 *    h # => {"x"=>0, "x"=>1}
 */

static VALUE
rb_hash_compare_by_id(VALUE hash)
{
    VALUE tmp;
    st_table *identtable;

    if (rb_hash_compare_by_id_p(hash)) return hash;

    rb_hash_modify_check(hash);
    ar_force_convert_table(hash, __FILE__, __LINE__);
    HASH_ASSERT(RHASH_ST_TABLE_P(hash));

    tmp = hash_alloc(0);
    identtable = rb_init_identtable_with_size(RHASH_SIZE(hash));
    RHASH_ST_TABLE_SET(tmp, identtable);
    rb_hash_foreach(hash, rb_hash_rehash_i, (VALUE)tmp);
    st_free_table(RHASH_ST_TABLE(hash));
    RHASH_ST_TABLE_SET(hash, identtable);
    RHASH_ST_CLEAR(tmp);
    rb_gc_force_recycle(tmp);

    return hash;
}

/*
 *  call-seq:
 *    hash.compare_by_identity? -> true or false
 *
 *  Returns +true+ if #compare_by_identity has been called, +false+ otherwise:
 *    h = {}
 *    h.compare_by_identity? # false
 *    h.compare_by_identity
 *    h.compare_by_identity? # true
 */

MJIT_FUNC_EXPORTED VALUE
rb_hash_compare_by_id_p(VALUE hash)
{
    if (RHASH_ST_TABLE_P(hash) && RHASH_ST_TABLE(hash)->type == &identhash) {
	return Qtrue;
    }
    else {
        return Qfalse;
    }
}

VALUE
rb_ident_hash_new(void)
{
    VALUE hash = rb_hash_new();
    RHASH_ST_TABLE_SET(hash, st_init_table(&identhash));
    return hash;
}

st_table *
rb_init_identtable(void)
{
    return st_init_table(&identhash);
}

static st_table *
rb_init_identtable_with_size(st_index_t size)
{
    return st_init_table_with_size(&identhash, size);
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
 *  ---
 *
 *  With no argument and no block,
 *  returns +true+ if +self+ is non-empty; +false+ if empty:
 *    {}.any? # => false
 *    {nil => false}.any? # => true
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
 *  With argument +object+ and a block,
 *  issues a warning ('given block not used') and ignores the block:
 *   h = {foo: 0, bar: 1, baz: 2}
 *   h.any?([:bar, 1]) # => true
 *   h.any?([:bar, 0]) # => false
 *   h.any?([:baz, 1]) # => false
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
 *  See {Dig Methods}[rdoc-ref:doc/dig_methods.rdoc].
 *
 *  Examples:
 *    h = {foo: {bar: {baz: 2}}}
 *    h.dig(:foo) # => {:bar=>{:baz=>2}}
 *    h.dig(:foo, :bar) # => {:bar=>{:baz=>2}}
 *    h.dig(:foo, :bar, :baz) # => 2
 *    h.dig(:foo, :bar, :BAZ) # => nil
 *
 *  The nested objects may include any that respond to \#dig.  See:
 *  - Hash#dig
 *  - Array#dig
 *  - Struct#dig
 *  - OpenStruct#dig
 *  - CSV::Table#dig
 *  - CSV::Row#dig
 *
 *  Example:
 *    h = {foo: {bar: [:a, :b, :c]}}
 *    h.dig(:foo, :bar, 2) # => :c
 *
 *  This method will use the {default values}[#class-Hash-label-Default+Values]
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
    if (v != Qundef && rb_equal(value, v)) return ST_CONTINUE;
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
 *  Returns a \Proc object that maps a key to its value:
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
        hash_ar_table(hash);

        ret = ar_update(hash, (st_data_t)key, add_new_i, (st_data_t)args);
        if (ret != -1) {
            return ret;
        }
        ar_try_convert_table(hash);
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

        if (RHASH_TABLE_NULL_P(hash)) {
            if (size <= RHASH_AR_TABLE_MAX_SIZE) {
                hash_ar_table(hash);
            }
            else {
                RHASH_TBL_RAW(hash);
            }
        }

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
static char *(*w32_getenv)(const char*);
static char *
w32_getenv_unknown(const char *name)
{
    char *(*func)(const char*);
    if (rb_locale_encindex() == rb_ascii8bit_encindex()) {
	func = rb_w32_getenv;
    }
    else {
	func = rb_w32_ugetenv;
    }
    /* atomic assignment in flat memory model */
    return (w32_getenv = func)(name);
}
static char *(*w32_getenv)(const char*) = w32_getenv_unknown;
#define getenv(n) w32_getenv(n)
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

static VALUE
env_enc_str_new(const char *ptr, long len, rb_encoding *enc)
{
#ifdef _WIN32
    rb_encoding *internal = rb_default_internal_encoding();
    const int ecflags = ECONV_INVALID_REPLACE | ECONV_UNDEF_REPLACE;
    rb_encoding *utf8 = rb_utf8_encoding();
    VALUE str = rb_enc_str_new(NULL, 0, (internal ? internal : enc));
    if (NIL_P(rb_str_cat_conv_enc_opts(str, 0, ptr, len, utf8, ecflags, Qnil))) {
        rb_str_initialize(str, ptr, len, NULL);
    }
#else
    VALUE str = rb_external_str_new_with_enc(ptr, len, enc);
#endif

    rb_obj_freeze(str);
    return str;
}

static VALUE
env_enc_str_new_cstr(const char *ptr, rb_encoding *enc)
{
    return env_enc_str_new(ptr, strlen(ptr), enc);
}

static VALUE
env_str_new(const char *ptr, long len)
{
    return env_enc_str_new(ptr, len, rb_locale_encoding());
}

static VALUE
env_str_new2(const char *ptr)
{
    if (!ptr) return Qnil;
    return env_str_new(ptr, strlen(ptr));
}

static const char TZ_ENV[] = "TZ";

static rb_encoding *
env_encoding_for(const char *name, const char *ptr)
{
    if (ENVMATCH(name, PATH_ENV)) {
	return rb_filesystem_encoding();
    }
    else {
	return rb_locale_encoding();
    }
}

static VALUE
env_name_new(const char *name, const char *ptr)
{
    return env_enc_str_new_cstr(ptr, env_encoding_for(name, ptr));
}

static void *
get_env_cstr(
#ifdef _WIN32
    volatile VALUE *pstr,
#else
    VALUE str,
#endif
    const char *name)
{
#ifdef _WIN32
    VALUE str = *pstr;
#endif
    char *var;
    rb_encoding *enc = rb_enc_get(str);
    if (!rb_enc_asciicompat(enc)) {
	rb_raise(rb_eArgError, "bad environment variable %s: ASCII incompatible encoding: %s",
		 name, rb_enc_name(enc));
    }
#ifdef _WIN32
    if (!rb_enc_str_asciionly_p(str)) {
	*pstr = str = rb_str_conv_enc(str, NULL, rb_utf8_encoding());
    }
#endif
    var = RSTRING_PTR(str);
    if (memchr(var, '\0', RSTRING_LEN(str))) {
	rb_raise(rb_eArgError, "bad environment variable %s: contains null byte", name);
    }
    return rb_str_fill_terminator(str, 1); /* ASCII compatible */
}

#ifdef _WIN32
#define get_env_ptr(var, val) \
    (var = get_env_cstr(&(val), #var))
#else
#define get_env_ptr(var, val) \
    (var = get_env_cstr(val, #var))
#endif

static inline const char *
env_name(volatile VALUE *s)
{
    const char *name;
    SafeStringValue(*s);
    get_env_ptr(name, *s);
    return name;
}

#define env_name(s) env_name(&(s))

static VALUE env_aset(VALUE nm, VALUE val);

static void
reset_by_modified_env(const char *nam)
{
    /*
     * ENV['TZ'] = nil has a special meaning.
     * TZ is no longer considered up-to-date and ruby call tzset() as needed.
     * It could be useful if sysadmin change /etc/localtime.
     * This hack might works only on Linux glibc.
     */
    if (ENVMATCH(nam, TZ_ENV)) {
        ruby_reset_timezone();
    }
}

static VALUE
env_delete(VALUE name)
{
    const char *nam = env_name(name);
    const char *val = getenv(nam);

    reset_by_modified_env(nam);

    if (val) {
	VALUE value = env_str_new2(val);

	ruby_setenv(nam, 0);
	if (ENVMATCH(nam, PATH_ENV)) {
	    RB_GC_GUARD(name);
	}
	return value;
    }
    return Qnil;
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
 * See {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values].
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
 * See {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values].
 */
static VALUE
rb_f_getenv(VALUE obj, VALUE name)
{
    const char *nam, *env;

    nam = env_name(name);
    env = getenv(nam);
    if (env) {
	return env_name_new(nam, env);
    }
    return Qnil;
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
 * See {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values].
 */
static VALUE
env_fetch(int argc, VALUE *argv, VALUE _)
{
    VALUE key;
    long block_given;
    const char *nam, *env;

    rb_check_arity(argc, 1, 2);
    key = argv[0];
    block_given = rb_block_given_p();
    if (block_given && argc == 2) {
	rb_warn("block supersedes default value argument");
    }
    nam = env_name(key);
    env = getenv(nam);
    if (!env) {
	if (block_given) return rb_yield(key);
	if (argc == 1) {
	    rb_key_err_raise(rb_sprintf("key not found: \"%"PRIsVALUE"\"", key), envtbl, key);
	}
	return argv[1];
    }
    return env_name_new(nam, env);
}

int
rb_env_path_tainted(void)
{
    rb_warn_deprecated_to_remove("rb_env_path_tainted", "3.2");
    return 0;
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

#if defined(_WIN32)
static size_t
getenvsize(const WCHAR* p)
{
    const WCHAR* porg = p;
    while (*p++) p += lstrlenW(p) + 1;
    return p - porg + 1;
}

static size_t
getenvblocksize(void)
{
#ifdef _MAX_ENV
    return _MAX_ENV;
#else
    return 32767;
#endif
}

static int
check_envsize(size_t n)
{
    if (_WIN32_WINNT < 0x0600 && rb_w32_osver() < 6) {
	/* https://msdn.microsoft.com/en-us/library/windows/desktop/ms682653(v=vs.85).aspx */
	/* Windows Server 2003 and Windows XP: The maximum size of the
	 * environment block for the process is 32,767 characters. */
	WCHAR* p = GetEnvironmentStringsW();
	if (!p) return -1; /* never happen */
	n += getenvsize(p);
	FreeEnvironmentStringsW(p);
	if (n >= getenvblocksize()) {
	    return -1;
	}
    }
    return 0;
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
# if defined(MINGW_HAS_SECURE_API) || RUBY_MSVCRT_VERSION >= 80
#   define HAVE__WPUTENV_S 1
# endif
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
	if (check_envsize((size_t)len + len2)) { /* len and len2 include '\0' */
	    goto fail;  /* 2 for '=' & '\0' */
	}
	wname = ALLOCV_N(WCHAR, buf, len + len2);
	wvalue = wname + len;
	MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, len);
	MultiByteToWideChar(CP_UTF8, 0, value, -1, wvalue, len2);
#ifndef HAVE__WPUTENV_S
	wname[len-1] = L'=';
#endif
    }
    else {
	wname = ALLOCV_N(WCHAR, buf, len + 1);
	MultiByteToWideChar(CP_UTF8, 0, name, -1, wname, len);
	wvalue = wname + len;
	*wvalue = L'\0';
#ifndef HAVE__WPUTENV_S
	wname[len-1] = L'=';
#endif
    }
#ifndef HAVE__WPUTENV_S
    failed = _wputenv(wname);
#else
    failed = _wputenv_s(wname, wvalue);
#endif
    ALLOCV_END(buf);
    /* even if putenv() failed, clean up and try to delete the
     * variable from the system area. */
    if (!value || !*value) {
	/* putenv() doesn't handle empty value */
	if (!SetEnvironmentVariable(name, value) &&
	    GetLastError() != ERROR_ENVVAR_NOT_FOUND) goto fail;
    }
    if (failed) {
      fail:
	invalid_envname(name);
    }
#elif defined(HAVE_SETENV) && defined(HAVE_UNSETENV)
    if (value) {
	if (setenv(name, value, 1))
	    rb_sys_fail_str(rb_sprintf("setenv(%s)", name));
    }
    else {
#ifdef VOID_UNSETENV
	unsetenv(name);
#else
	if (unsetenv(name))
	    rb_sys_fail_str(rb_sprintf("unsetenv(%s)", name));
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
	    rb_sys_fail_str(rb_sprintf("malloc("PRIuSIZE")", mem_size));
	snprintf(mem_ptr, mem_size, "%s=%s", name, value);
    }
    for (env_ptr = GET_ENVIRON(environ); (str = *env_ptr) != 0; ++env_ptr) {
	if (!strncmp(str, name, len) && str[len] == '=') {
	    if (!in_origenv(str)) free(str);
	    while ((env_ptr[0] = env_ptr[1]) != 0) env_ptr++;
	    break;
	}
    }
    if (value) {
	if (putenv(mem_ptr)) {
	    free(mem_ptr);
	    rb_sys_fail_str(rb_sprintf("putenv(%s)", name));
	}
    }
#else  /* WIN32 */
    size_t len;
    int i;

    i=envix(name);		        /* where does it go? */

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
	    return;
	}
    }
    else {			/* does not exist yet */
	if (!value) return;
	REALLOC_N(environ, char*, i+2);	/* just expand it a bit */
	environ[i+1] = 0;	/* make sure it's null terminated */
    }
    len = strlen(name) + strlen(value) + 2;
    environ[i] = ALLOC_N(char, len);
    snprintf(environ[i],len,"%s=%s",name,value); /* all that work just for this */
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
 * ENV.store is an alias for ENV.[]=.
 *
 * Creates, updates, or deletes the named environment variable, returning the value.
 * Both +name+ and +value+ may be instances of String.
 * See {Valid Names and Values}[#class-ENV-label-Valid+Names+and+Values].
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
 * See {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values].
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
    SafeStringValue(nm);
    SafeStringValue(val);
    /* nm can be modified in `val.to_str`, don't get `name` before
     * check for `val` */
    get_env_ptr(name, nm);
    get_env_ptr(value, val);

    ruby_setenv(name, value);
    if (ENVMATCH(name, PATH_ENV)) {
	RB_GC_GUARD(nm);
    }
    reset_by_modified_env(name);
    return val;
}

static VALUE
env_keys(int raw)
{
    char **env;
    VALUE ary;
    rb_encoding *enc = raw ? 0 : rb_locale_encoding();

    ary = rb_ary_new();
    env = GET_ENVIRON(environ);
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
 * See {About Ordering}[#class-ENV-label-About+Ordering].
 *
 * Returns the empty Array if ENV is empty:
 *   ENV.clear
 *   ENV.keys # => []
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

    env = GET_ENVIRON(environ);
    for (; *env ; ++env) {
	if (strchr(*env, '=')) {
	    cnt++;
	}
    }
    FREE_ENVIRON(environ);
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
    VALUE ary;
    char **env;

    ary = rb_ary_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, env_str_new2(s+1));
	}
	env++;
    }
    FREE_ENVIRON(environ);
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
 * See {About Ordering}[#class-ENV-label-About+Ordering].
 *
 * Returns the empty Array if ENV is empty:
 *   ENV.clear
 *   ENV.values # => []
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
 * Yields each environment variable name and its value as a 2-element \Array:
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
    char **env;
    VALUE ary;
    long i;

    RETURN_SIZED_ENUMERATOR(ehash, 0, 0, rb_env_size);

    ary = rb_ary_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, env_str_new(*env, s-*env));
	    rb_ary_push(ary, env_str_new2(s+1));
	}
	env++;
    }
    FREE_ENVIRON(environ);

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
 * Returns an empty \Array if no names given:
 *   ENV.values_at() # => []
 *
 * Raises an exception if any name is invalid.
 * See {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values].
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
 * ENV.filter is an alias for ENV.select.
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
 * ENV.filter! is an alias for ENV.select!.
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
 * (see {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values]):
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
    char **env;
    VALUE str, i;

    str = rb_str_buf_new2("{");
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');

	if (env != environ) {
	    rb_str_buf_cat2(str, ", ");
	}
	if (s) {
	    rb_str_buf_cat2(str, "\"");
	    rb_str_buf_cat(str, *env, s-*env);
	    rb_str_buf_cat2(str, "\"=>");
	    i = rb_inspect(rb_str_new2(s+1));
	    rb_str_buf_append(str, i);
	}
	env++;
    }
    FREE_ENVIRON(environ);
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
    char **env;
    VALUE ary;

    ary = rb_ary_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_ary_push(ary, rb_assoc_new(env_str_new(*env, s-*env),
					  env_str_new2(s+1)));
	}
	env++;
    }
    FREE_ENVIRON(environ);
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
    int i;
    char **env;

    env = GET_ENVIRON(environ);
    for (i=0; env[i]; i++)
	;
    FREE_ENVIRON(environ);
    return INT2FIX(i);
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
    char **env;

    env = GET_ENVIRON(environ);
    if (env[0] == 0) {
	FREE_ENVIRON(environ);
	return Qtrue;
    }
    FREE_ENVIRON(environ);
    return Qfalse;
}

/*
 * call-seq:
 *   ENV.include?(name) -> true or false
 *   ENV.has_key?(name) -> true or false
 *   ENV.member?(name)  -> true or false
 *   ENV.key?(name)     -> true or false
 *
 * ENV.has_key?, ENV.member?, and ENV.key? are aliases for ENV.include?.
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
    const char *s;

    s = env_name(key);
    if (getenv(s)) return Qtrue;
    return Qfalse;
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
    const char *s, *e;

    s = env_name(key);
    e = getenv(s);
    if (e) return rb_assoc_new(key, env_str_new2(e));
    return Qnil;
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
    char **env;

    obj = rb_check_string_type(obj);
    if (NIL_P(obj)) return Qnil;
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s++) {
	    long len = strlen(s);
	    if (RSTRING_LEN(obj) == len && strncmp(s, RSTRING_PTR(obj), len) == 0) {
		FREE_ENVIRON(environ);
		return Qtrue;
	    }
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return Qfalse;
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
 * See {About Ordering}[#class-ENV-label-About+Ordering].
 *
 * Returns +nil+ if there is no such environment variable.
 */
static VALUE
env_rassoc(VALUE dmy, VALUE obj)
{
    char **env;

    obj = rb_check_string_type(obj);
    if (NIL_P(obj)) return Qnil;
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s++) {
	    long len = strlen(s);
	    if (RSTRING_LEN(obj) == len && strncmp(s, RSTRING_PTR(obj), len) == 0) {
                VALUE result = rb_assoc_new(rb_str_new(*env, s-*env-1), obj);
		FREE_ENVIRON(environ);
		return result;
	    }
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return Qnil;
}

/*
 * call-seq:
 *   ENV.key(value) -> name or nil
 *
 * Returns the name of the first environment variable with +value+, if it exists:
 *   ENV.replace('foo' => '0', 'bar' => '0')
 *   ENV.key('0') # => "foo"
 * The order in which environment variables are examined is OS-dependent.
 * See {About Ordering}[#class-ENV-label-About+Ordering].
 *
 * Returns +nil+ if there is no such value.
 *
 * Raises an exception if +value+ is invalid:
 *   ENV.key(Object.new) # raises TypeError (no implicit conversion of Object into String)
 * See {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values].
 */
static VALUE
env_key(VALUE dmy, VALUE value)
{
    char **env;
    VALUE str;

    SafeStringValue(value);
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s++) {
	    long len = strlen(s);
	    if (RSTRING_LEN(value) == len && strncmp(s, RSTRING_PTR(value), len) == 0) {
		str = env_str_new(*env, s-*env-1);
		FREE_ENVIRON(environ);
		return str;
	    }
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return Qnil;
}

/*
 * call-seq:
 *   ENV.index(value) -> name
 *
 * Deprecated method that is equivalent to ENV.key.
 */
static VALUE
env_index(VALUE dmy, VALUE value)
{
    rb_warn_deprecated("ENV.index", "ENV.key");
    return env_key(dmy, value);
}

static VALUE
env_to_hash(void)
{
    char **env;
    VALUE hash;

    hash = rb_hash_new();
    env = GET_ENVIRON(environ);
    while (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    rb_hash_aset(hash, env_str_new(*env, s-*env),
			       env_str_new2(s+1));
	}
	env++;
    }
    FREE_ENVIRON(environ);
    return hash;
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
 *     ENV                       #=> {"LANG"="en_US.UTF-8", "TERM"=>"xterm-256color", "HOME"=>"/Users/rhc"}
 *     ENV.except("TERM","HOME") #=> {"LANG"="en_US.UTF-8"}
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
 * See {About Ordering}[#class-ENV-label-About+Ordering].
 *
 * Returns +nil+ if the environment is empty.
 */
static VALUE
env_shift(VALUE _)
{
    char **env;
    VALUE result = Qnil;

    env = GET_ENVIRON(environ);
    if (*env) {
	char *s = strchr(*env, '=');
	if (s) {
	    VALUE key = env_str_new(*env, s-*env);
	    VALUE val = env_str_new2(getenv(RSTRING_PTR(key)));
            env_delete(key);
	    result = rb_assoc_new(key, val);
	}
    }
    FREE_ENVIRON(environ);
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
 * See {About Ordering}[#class-ENV-label-About+Ordering].
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
    for (long i=0; i<RARRAY_LEN(keys); i++) {
        VALUE e = RARRAY_AREF(keys, i);
        RSTRING_GETMEM(e, eptr, elen);
        if (elen != keylen) continue;
        if (!ENVNMATCH(keyptr, eptr, elen)) continue;
        rb_ary_delete_at(keys, i);
        return;
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
 * (see {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values]):
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
 *   ENV.update(hash)                                     -> ENV
 *   ENV.update(hash) { |name, env_val, hash_val| block } -> ENV
 *   ENV.merge!(hash)                                     -> ENV
 *   ENV.merge!(hash) { |name, env_val, hash_val| block } -> ENV
 *
 * ENV.update is an alias for ENV.merge!.
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
 * (see {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values]);
 *   ENV.replace('foo' => '0', 'bar' => '1')
 *   ENV.merge!('foo' => '6', :bar => '7', 'baz' => '9') # Raises TypeError (no implicit conversion of Symbol into String)
 *   ENV # => {"bar"=>"1", "foo"=>"6"}
 *   ENV.merge!('foo' => '7', 'bar' => 8, 'baz' => '9') # Raises TypeError (no implicit conversion of Integer into String)
 *   ENV # => {"bar"=>"1", "foo"=>"7"}
 * Raises an exception if the block returns an invalid name:
 * (see {Invalid Names and Values}[#class-ENV-label-Invalid+Names+and+Values]):
 *   ENV.merge!('bat' => '8', 'foo' => '9') { |name, env_val, hash_val | 10 } # Raises TypeError (no implicit conversion of Integer into String)
 *   ENV # => {"bar"=>"1", "bat"=>"8", "foo"=>"7"}
 *
 * Note that for the exceptions above,
 * hash pairs preceding an invalid name or value are processed normally;
 * those following are ignored.
 */
static VALUE
env_update(VALUE env, VALUE hash)
{
    if (env == hash) return env;
    hash = to_hash(hash);
    rb_foreach_func *func = rb_block_given_p() ?
        env_update_block_i : env_update_i;
    rb_hash_foreach(hash, func, 0);
    return env;
}

/*
 *  A \Hash maps each of its unique keys to a specific value.
 *
 *  A \Hash has certain similarities to an \Array, but:
 *  - An \Array index is always an \Integer.
 *  - A \Hash key can be (almost) any object.
 *
 *  === \Hash \Data Syntax
 *
 *  The older syntax for \Hash data uses the "hash rocket," <tt>=></tt>:
 *
 *    h = {:foo => 0, :bar => 1, :baz => 2}
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  Alternatively, but only for a \Hash key that's a \Symbol,
 *  you can use a newer JSON-style syntax,
 *  where each bareword becomes a \Symbol:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  You can also use a \String in place of a bareword:
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
 *  === Common Uses
 *
 *  You can use a \Hash to give names to objects:
 *
 *    person = {name: 'Matz', language: 'Ruby'}
 *    person # => {:name=>"Matz", :language=>"Ruby"}
 *
 *  You can use a \Hash to give names to method arguments:
 *
 *    def some_method(hash)
 *      p hash
 *    end
 *    some_method({foo: 0, bar: 1, baz: 2}) # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  Note: when the last argument in a method call is a \Hash,
 *  the curly braces may be omitted:
 *
 *    some_method(foo: 0, bar: 1, baz: 2) # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  You can use a \Hash to initialize an object:
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
 *  Here are three ways to create a \Hash:
 *
 *  - \Method <tt>Hash.new</tt>
 *  - \Method <tt>Hash[]</tt>
 *  - Literal form: <tt>{}</tt>.
 *
 *  ---
 *
 *  You can create a \Hash by calling method Hash.new.
 *
 *  Create an empty Hash:
 *
 *    h = Hash.new
 *    h # => {}
 *    h.class # => Hash
 *
 *  ---
 *
 *  You can create a \Hash by calling method Hash.[].
 *
 *  Create an empty Hash:
 *
 *    h = Hash[]
 *    h # => {}
 *
 *  Create a \Hash with initial entries:
 *
 *    h = Hash[foo: 0, bar: 1, baz: 2]
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *  ---
 *
 *  You can create a \Hash by using its literal form (curly braces).
 *
 *  Create an empty \Hash:
 *
 *    h = {}
 *    h # => {}
 *
 *  Create a \Hash with initial entries:
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h # => {:foo=>0, :bar=>1, :baz=>2}
 *
 *
 *  === \Hash Value Basics
 *
 *  The simplest way to retrieve a \Hash value (instance method #[]):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:foo] # => 0
 *
 *  The simplest way to create or update a \Hash value (instance method #[]=):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h[:bat] = 3 # => 3
 *    h # => {:foo=>0, :bar=>1, :baz=>2, :bat=>3}
 *    h[:foo] = 4 # => 4
 *    h # => {:foo=>4, :bar=>1, :baz=>2, :bat=>3}
 *
 *  The simplest way to delete a \Hash entry (instance method #delete):
 *
 *    h = {foo: 0, bar: 1, baz: 2}
 *    h.delete(:bar) # => 1
 *    h # => {:foo=>0, :baz=>2}
 *
 *  === Entry Order
 *
 *  A \Hash object presents its entries in the order of their creation. This is seen in:
 *
 *  - Iterative methods such as <tt>each</tt>, <tt>each_key</tt>, <tt>each_pair</tt>, <tt>each_value</tt>.
 *  - Other order-sensitive methods such as <tt>shift</tt>, <tt>keys</tt>, <tt>values</tt>.
 *  - The \String returned by method <tt>inspect</tt>.
 *
 *  A new \Hash has its initial ordering per the given entries:
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
 *  === \Hash Keys
 *
 *  ==== \Hash Key Equivalence
 *
 *  Two objects are treated as the same \hash key when their <code>hash</code> value
 *  is identical and the two objects are <code>eql?</code> to each other.
 *
 *  ==== Modifying an Active \Hash Key
 *
 *  Modifying a \Hash key while it is in use damages the hash's index.
 *
 *  This \Hash has keys that are Arrays:
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
 *  And damages the \Hash index:
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
 *  A \String key is always safe.
 *  That's because an unfrozen \String
 *  passed as a key will be replaced by a duplicated and frozen \String:
 *
 *    s = 'foo'
 *    s.frozen? # => false
 *    h = {s => 0}
 *    first_key = h.keys.first
 *    first_key.frozen? # => true
 *    first_key.equal?(s) # => false
 *
 *  ==== User-Defined \Hash Keys
 *
 *  To be useable as a \Hash key, objects must implement the methods <code>hash</code> and <code>eql?</code>.
 *  Note: this requirement does not apply if the \Hash uses #compare_by_id since comparison will then rely on
 *  the keys' object id instead of <code>hash</code> and <code>eql?</code>.
 *
 *  \Object defines basic implementation for <code>hash</code> and <code>eq?</code> that makes each object
 *  a distinct key. Typically, user-defined classes will want to override these methods to provide meaningful
 *  behavior, or for example inherit \Struct that has useful definitions for these.
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
 *        @author.hash ^ @title.hash # XOR
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
 *  The methods #[], #values_at and #dig need to return the value associated to a certain key
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
 *  ==== Default \Proc
 *
 *  When the default proc for a \Hash is set (i.e., not +nil+),
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
 *  #[] calls the default proc with both the \Hash object itself and the missing key,
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
 */

void
Init_Hash(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)
    id_hash = rb_intern("hash");
    id_default = rb_intern("default");
    id_flatten_bang = rb_intern("flatten!");
    id_hash_iter_lev = rb_make_internal_id();

    rb_cHash = rb_define_class("Hash", rb_cObject);

    rb_include_module(rb_cHash, rb_mEnumerable);

    rb_define_alloc_func(rb_cHash, empty_hash_alloc);
    rb_define_singleton_method(rb_cHash, "[]", rb_hash_s_create, -1);
    rb_define_singleton_method(rb_cHash, "try_convert", rb_hash_s_try_convert, 1);
    rb_define_method(rb_cHash, "initialize", rb_hash_initialize, -1);
    rb_define_method(rb_cHash, "initialize_copy", rb_hash_replace, 1);
    rb_define_method(rb_cHash, "rehash", rb_hash_rehash, 0);

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
    rb_define_method(rb_cHash, "index", rb_hash_index, 1);
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

    /* Document-class: ENV
     *
     * ENV is a hash-like accessor for environment variables.
     *
     * === Interaction with the Operating System
     *
     * The ENV object interacts with the operating system's environment variables:
     *
     * - When you get the value for a name in ENV, the value is retrieved from among the current environment variables.
     * - When you create or set a name-value pair in ENV, the name and value are immediately set in the environment variables.
     * - When you delete a name-value pair in ENV, it is immediately deleted from the environment variables.
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
     * ENV enumerates its name/value pairs in the order found
     * in the operating system's environment variables.
     * Therefore the ordering of ENV content is OS-dependent, and may be indeterminate.
     *
     * This will be seen in:
     * - A Hash returned by an ENV method.
     * - An Enumerator returned by an ENV method.
     * - An Array returned by ENV.keys, ENV.values, or ENV.to_a.
     * - The String returned by ENV.inspect.
     * - The Array returned by ENV.shift.
     * - The name returned by ENV.key.
     *
     * === About the Examples
     * Some methods in ENV return ENV itself. Typically, there are many environment variables.
     * It's not useful to display a large ENV in the examples here,
     * so most example snippets begin by resetting the contents of ENV:
     * - ENV.replace replaces ENV with a new collection of entries.
     * - ENV.clear empties ENV.
     */

    /*
     * Hack to get RDoc to regard ENV as a class:
     * envtbl = rb_define_class("ENV", rb_cObject);
     */
    origenviron = environ;
    envtbl = rb_obj_alloc(rb_cObject);
    rb_extend_object(envtbl, rb_mEnumerable);

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
    rb_define_singleton_method(envtbl, "update", env_update, 1);
    rb_define_singleton_method(envtbl, "merge!", env_update, 1);
    rb_define_singleton_method(envtbl, "inspect", env_inspect, 0);
    rb_define_singleton_method(envtbl, "rehash", env_none, 0);
    rb_define_singleton_method(envtbl, "to_a", env_to_a, 0);
    rb_define_singleton_method(envtbl, "to_s", env_to_s, 0);
    rb_define_singleton_method(envtbl, "key", env_key, 1);
    rb_define_singleton_method(envtbl, "index", env_index, 1);
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

    /*
     * ENV is a Hash-like accessor for environment variables.
     *
     * See ENV (the class) for more details.
     */
    rb_define_global_const("ENV", envtbl);

    /* for callcc */
    ruby_register_rollback_func_for_ensure(hash_foreach_ensure, hash_foreach_ensure_rollback);

    HASH_ASSERT(sizeof(ar_hint_t) * RHASH_AR_TABLE_MAX_SIZE == sizeof(VALUE));
}
