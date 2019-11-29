#ifndef INTERNAL_HASH_H /* -*- C -*- */
#define INTERNAL_HASH_H
/**
 * @file
 * @brief      Internal header for Hash.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

enum ruby_rhash_flags {
    RHASH_PASS_AS_KEYWORDS = FL_USER1,                                   /* FL 1 */
    RHASH_PROC_DEFAULT = FL_USER2,                                       /* FL 2 */
    RHASH_ST_TABLE_FLAG = FL_USER3,                                      /* FL 3 */
#define RHASH_AR_TABLE_MAX_SIZE SIZEOF_VALUE
    RHASH_AR_TABLE_SIZE_MASK = (FL_USER4|FL_USER5|FL_USER6|FL_USER7),    /* FL 4..7 */
    RHASH_AR_TABLE_SIZE_SHIFT = (FL_USHIFT+4),
    RHASH_AR_TABLE_BOUND_MASK = (FL_USER8|FL_USER9|FL_USER10|FL_USER11), /* FL 8..11 */
    RHASH_AR_TABLE_BOUND_SHIFT = (FL_USHIFT+8),

    // we can not put it in "enum" because it can exceed "int" range.
#define RHASH_LEV_MASK (FL_USER13 | FL_USER14 | FL_USER15 |                /* FL 13..19 */ \
                        FL_USER16 | FL_USER17 | FL_USER18 | FL_USER19)

#if USE_TRANSIENT_HEAP
    RHASH_TRANSIENT_FLAG = FL_USER12,                                    /* FL 12 */
#endif

    RHASH_LEV_SHIFT = (FL_USHIFT + 13),
    RHASH_LEV_MAX = 127, /* 7 bits */

    RHASH_ENUM_END
};

#define RHASH_AR_TABLE_SIZE_RAW(h) \
  ((unsigned int)((RBASIC(h)->flags & RHASH_AR_TABLE_SIZE_MASK) >> RHASH_AR_TABLE_SIZE_SHIFT))

void rb_hash_st_table_set(VALUE hash, st_table *st);

#if 0 /* for debug */
int rb_hash_ar_table_p(VALUE hash);
struct ar_table_struct *rb_hash_ar_table(VALUE hash);
st_table *rb_hash_st_table(VALUE hash);
#define RHASH_AR_TABLE_P(hash)       rb_hash_ar_table_p(hash)
#define RHASH_AR_TABLE(h)            rb_hash_ar_table(h)
#define RHASH_ST_TABLE(h)            rb_hash_st_table(h)
#else
#define RHASH_AR_TABLE_P(hash)       (!FL_TEST_RAW((hash), RHASH_ST_TABLE_FLAG))
#define RHASH_AR_TABLE(hash)         (RHASH(hash)->as.ar)
#define RHASH_ST_TABLE(hash)         (RHASH(hash)->as.st)
#endif

#define RHASH(obj)                   (R_CAST(RHash)(obj))
#define RHASH_ST_SIZE(h)             (RHASH_ST_TABLE(h)->num_entries)
#define RHASH_ST_TABLE_P(h)          (!RHASH_AR_TABLE_P(h))
#define RHASH_ST_CLEAR(h)            (FL_UNSET_RAW(h, RHASH_ST_TABLE_FLAG), RHASH(h)->as.ar = NULL)

#define RHASH_AR_TABLE_SIZE_MASK     (VALUE)RHASH_AR_TABLE_SIZE_MASK
#define RHASH_AR_TABLE_SIZE_SHIFT    RHASH_AR_TABLE_SIZE_SHIFT
#define RHASH_AR_TABLE_BOUND_MASK    (VALUE)RHASH_AR_TABLE_BOUND_MASK
#define RHASH_AR_TABLE_BOUND_SHIFT   RHASH_AR_TABLE_BOUND_SHIFT

#if USE_TRANSIENT_HEAP
#define RHASH_TRANSIENT_P(hash)   FL_TEST_RAW((hash), RHASH_TRANSIENT_FLAG)
#define RHASH_SET_TRANSIENT_FLAG(h)   FL_SET_RAW(h, RHASH_TRANSIENT_FLAG)
#define RHASH_UNSET_TRANSIENT_FLAG(h) FL_UNSET_RAW(h, RHASH_TRANSIENT_FLAG)
#else
#define RHASH_TRANSIENT_P(hash)   0
#define RHASH_SET_TRANSIENT_FLAG(h)   ((void)0)
#define RHASH_UNSET_TRANSIENT_FLAG(h) ((void)0)
#endif

#if   SIZEOF_VALUE / RHASH_AR_TABLE_MAX_SIZE == 2
typedef uint16_t ar_hint_t;
#elif SIZEOF_VALUE / RHASH_AR_TABLE_MAX_SIZE == 1
typedef unsigned char ar_hint_t;
#else
#error unsupported
#endif

struct RHash {
    struct RBasic basic;
    union {
        st_table *st;
        struct ar_table_struct *ar; /* possibly 0 */
    } as;
    const VALUE ifnone;
    union {
        ar_hint_t ary[RHASH_AR_TABLE_MAX_SIZE];
        VALUE word;
    } ar_hint;
};

#ifdef RHASH_IFNONE
#  undef RHASH_IFNONE
#  undef RHASH_SIZE

#  define RHASH_IFNONE(h)    (RHASH(h)->ifnone)
#  define RHASH_SIZE(h)      (RHASH_AR_TABLE_P(h) ? RHASH_AR_TABLE_SIZE_RAW(h) : RHASH_ST_SIZE(h))
#endif /* ifdef RHASH_IFNONE */

/* hash.c */
#if RHASH_CONVERT_TABLE_DEBUG
struct st_table *rb_hash_tbl_raw(VALUE hash, const char *file, int line);
#define RHASH_TBL_RAW(h) rb_hash_tbl_raw(h, __FILE__, __LINE__)
#else
struct st_table *rb_hash_tbl_raw(VALUE hash);
#define RHASH_TBL_RAW(h) rb_hash_tbl_raw(h)
#endif

VALUE rb_hash_new_with_size(st_index_t size);
VALUE rb_hash_has_key(VALUE hash, VALUE key);
VALUE rb_hash_default_value(VALUE hash, VALUE key);
VALUE rb_hash_set_default_proc(VALUE hash, VALUE proc);
long rb_dbl_long_hash(double d);
st_table *rb_init_identtable(void);
VALUE rb_hash_compare_by_id_p(VALUE hash);
VALUE rb_to_hash_type(VALUE obj);
VALUE rb_hash_key_str(VALUE);
VALUE rb_hash_keys(VALUE hash);
VALUE rb_hash_values(VALUE hash);
VALUE rb_hash_rehash(VALUE hash);
VALUE rb_hash_resurrect(VALUE hash);
int rb_hash_add_new_element(VALUE hash, VALUE key, VALUE val);
VALUE rb_hash_set_pair(VALUE hash, VALUE pair);

int rb_hash_stlike_lookup(VALUE hash, st_data_t key, st_data_t *pval);
int rb_hash_stlike_delete(VALUE hash, st_data_t *pkey, st_data_t *pval);
RUBY_SYMBOL_EXPORT_BEGIN
int rb_hash_stlike_foreach(VALUE hash, st_foreach_callback_func *func, st_data_t arg);
RUBY_SYMBOL_EXPORT_END
int rb_hash_stlike_foreach_with_replace(VALUE hash, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg);
int rb_hash_stlike_update(VALUE hash, st_data_t key, st_update_callback_func func, st_data_t arg);

RUBY_SYMBOL_EXPORT_BEGIN
/* hash.c (export) */
VALUE rb_hash_delete_entry(VALUE hash, VALUE key);
VALUE rb_ident_hash_new(void);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_HASH_H */
