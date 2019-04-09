/* This is a public domain general purpose hash table package
   originally written by Peter Moore @ UCB.

   The hash table data strutures were redesigned and the package was
   rewritten by Vladimir Makarov <vmakarov@redhat.com>.  */

#ifndef RUBY_ST_H
#define RUBY_ST_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include "ruby/defines.h"

RUBY_SYMBOL_EXPORT_BEGIN

#if SIZEOF_LONG == SIZEOF_VOIDP
typedef unsigned long st_data_t;
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
typedef unsigned LONG_LONG st_data_t;
#else
# error ---->> st.c requires sizeof(void*) == sizeof(long) or sizeof(LONG_LONG) to be compiled. <<----
#endif
#define ST_DATA_T_DEFINED

#ifndef CHAR_BIT
# ifdef HAVE_LIMITS_H
#  include <limits.h>
# else
#  define CHAR_BIT 8
# endif
#endif
#ifndef _
# define _(args) args
#endif
#ifndef ANYARGS
# ifdef __cplusplus
#   define ANYARGS ...
# else
#   define ANYARGS
# endif
#endif

typedef struct st_table st_table;

typedef st_data_t st_index_t;

/* Maximal value of unsigned integer type st_index_t.  */
#define MAX_ST_INDEX_VAL (~(st_index_t) 0)

typedef int st_compare_func(st_data_t, st_data_t);
typedef st_index_t st_hash_func(st_data_t);

typedef char st_check_for_sizeof_st_index_t[SIZEOF_VOIDP == (int)sizeof(st_index_t) ? 1 : -1];
#define SIZEOF_ST_INDEX_T SIZEOF_VOIDP

struct st_hash_type {
    int (*compare)(ANYARGS /*st_data_t, st_data_t*/); /* st_compare_func* */
    st_index_t (*hash)(ANYARGS /*st_data_t*/);        /* st_hash_func* */
};

#define ST_INDEX_BITS (SIZEOF_ST_INDEX_T * CHAR_BIT)

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR) && defined(HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P)
# define ST_DATA_COMPATIBLE_P(type) \
   __builtin_choose_expr(__builtin_types_compatible_p(type, st_data_t), 1, 0)
#else
# define ST_DATA_COMPATIBLE_P(type) 0
#endif

typedef struct st_table_entry st_table_entry;

struct st_table_entry; /* defined in st.c */

struct st_table {
    /* Cached features of the table -- see st.c for more details.  */
    unsigned char entry_power, bin_power, size_ind;
    /* How many times the table was rebuilt.  */
    unsigned int rebuilds_num;
    const struct st_hash_type *type;
    /* Number of entries currently in the table.  */
    st_index_t num_entries;
    /* Array of bins used for access by keys.  */
    st_index_t *bins;
    /* Start and bound index of entries in array entries.
       entries_starts and entries_bound are in interval
       [0,allocated_entries].  */
    st_index_t entries_start, entries_bound;
    /* Array of size 2^entry_power.  */
    st_table_entry *entries;
};

#define st_is_member(table,key) st_lookup((table),(key),(st_data_t *)0)

enum st_retval {ST_CONTINUE, ST_STOP, ST_DELETE, ST_CHECK, ST_REPLACE};

st_table *st_init_table(const struct st_hash_type *);
st_table *st_init_table_with_size(const struct st_hash_type *, st_index_t);
st_table *st_init_numtable(void);
st_table *st_init_numtable_with_size(st_index_t);
st_table *st_init_strtable(void);
st_table *st_init_strtable_with_size(st_index_t);
st_table *st_init_strcasetable(void);
st_table *st_init_strcasetable_with_size(st_index_t);
int st_delete(st_table *, st_data_t *, st_data_t *); /* returns 0:notfound 1:deleted */
int st_delete_safe(st_table *, st_data_t *, st_data_t *, st_data_t);
int st_shift(st_table *, st_data_t *, st_data_t *); /* returns 0:notfound 1:deleted */
int st_insert(st_table *, st_data_t, st_data_t);
int st_insert2(st_table *, st_data_t, st_data_t, st_data_t (*)(st_data_t));
int st_lookup(st_table *, st_data_t, st_data_t *);
int st_get_key(st_table *, st_data_t, st_data_t *);
typedef int st_update_callback_func(st_data_t *key, st_data_t *value, st_data_t arg, int existing);
/* *key may be altered, but must equal to the old key, i.e., the
 * results of hash() are same and compare() returns 0, otherwise the
 * behavior is undefined */
int st_update(st_table *table, st_data_t key, st_update_callback_func *func, st_data_t arg);
int st_foreach_with_replace(st_table *tab, int (*func)(ANYARGS), st_update_callback_func *replace, st_data_t arg);
int st_foreach(st_table *, int (*)(ANYARGS), st_data_t);
int st_foreach_check(st_table *, int (*)(ANYARGS), st_data_t, st_data_t);
st_index_t st_keys(st_table *table, st_data_t *keys, st_index_t size);
st_index_t st_keys_check(st_table *table, st_data_t *keys, st_index_t size, st_data_t never);
st_index_t st_values(st_table *table, st_data_t *values, st_index_t size);
st_index_t st_values_check(st_table *table, st_data_t *values, st_index_t size, st_data_t never);
void st_add_direct(st_table *, st_data_t, st_data_t);
void st_free_table(st_table *);
void st_cleanup_safe(st_table *, st_data_t);
void st_clear(st_table *);
st_table *st_copy(st_table *);
CONSTFUNC(int st_numcmp(st_data_t, st_data_t));
CONSTFUNC(st_index_t st_numhash(st_data_t));
PUREFUNC(int st_locale_insensitive_strcasecmp(const char *s1, const char *s2));
PUREFUNC(int st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n));
#define st_strcasecmp st_locale_insensitive_strcasecmp
#define st_strncasecmp st_locale_insensitive_strncasecmp
PUREFUNC(size_t st_memsize(const st_table *));
PUREFUNC(st_index_t st_hash(const void *ptr, size_t len, st_index_t h));
CONSTFUNC(st_index_t st_hash_uint32(st_index_t h, uint32_t i));
CONSTFUNC(st_index_t st_hash_uint(st_index_t h, st_index_t i));
CONSTFUNC(st_index_t st_hash_end(st_index_t h));
CONSTFUNC(st_index_t st_hash_start(st_index_t h));
#define st_hash_start(h) ((st_index_t)(h))

void rb_hash_bulk_insert_into_st_table(long, const VALUE *, VALUE);

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_ST_H */
