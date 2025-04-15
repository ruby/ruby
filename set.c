/* This implements sets using the same hash table implementation as in
   st.c, but without a value for each hash entry.  This results in the
   same basic performance characteristics as when using an st table,
   but uses 1/3 less memory.
   */

#include "id.h"
#include "internal.h"
#include "internal/bits.h"
#include "internal/hash.h"
#include "internal/proc.h"
#include "internal/sanitizers.h"
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

#ifdef __GNUC__
#define PREFETCH(addr, write_p) __builtin_prefetch(addr, write_p)
#define EXPECT(expr, val) __builtin_expect(expr, val)
#define ATTRIBUTE_UNUSED  __attribute__((unused))
#else
#define PREFETCH(addr, write_p)
#define EXPECT(expr, val) (expr)
#define ATTRIBUTE_UNUSED
#endif

#if SIZEOF_LONG == SIZEOF_VOIDP
typedef unsigned long set_data_t;
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
typedef unsigned LONG_LONG set_data_t;
#else
# error ---->> set.c requires sizeof(void*) == sizeof(long) or sizeof(LONG_LONG) to be compiled. <<----
#endif
#define SET_DATA_T_DEFINED

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

typedef struct set_table set_table;

typedef set_data_t set_index_t;

/* Maximal value of unsigned integer type set_index_t.  */
#define MAX_SET_INDEX_VAL (~(set_index_t) 0)

typedef int set_compare_func(set_data_t, set_data_t);
typedef set_index_t set_hash_func(set_data_t);

typedef char set_check_for_sizeof_set_index_t[SIZEOF_VOIDP == (int)sizeof(set_index_t) ? 1 : -1];
#define SIZEOF_SET_INDEX_T SIZEOF_VOIDP

struct set_hash_type {
    int (*compare)(set_data_t, set_data_t); /* set_compare_func* */
    set_index_t (*hash)(set_data_t);        /* set_hash_func* */
};

#define SET_INDEX_BITS (SIZEOF_SET_INDEX_T * CHAR_BIT)

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR) && defined(HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P)
# define SET_DATA_COMPATIBLE_P(type) \
   __builtin_choose_expr(__builtin_types_compatible_p(type, set_data_t), 1, 0)
#else
# define SET_DATA_COMPATIBLE_P(type) 0
#endif

typedef struct set_table_entry set_table_entry;

struct set_table_entry; /* defined in st.c */

struct set_table {
    /* Cached features of the table -- see st.c for more details.  */
    unsigned char entry_power, bin_power, size_ind;
    /* How many times the table was rebuilt.  */
    unsigned int rebuilds_num;
    const struct set_hash_type *type;
    /* Number of entries currently in the table.  */
    set_index_t num_entries;
    /* Array of bins used for access by keys.  */
    set_index_t *bins;
    /* Start and bound index of entries in array entries.
       entries_starts and entries_bound are in interval
       [0,allocated_entries].  */
    set_index_t entries_start, entries_bound;
    /* Array of size 2^entry_power.  */
    set_table_entry *entries;
};

enum set_retval {SET_CONTINUE, SET_STOP, SET_DELETE, SET_CHECK};

static size_t set_table_size(const struct set_table *tbl);
static set_table *set_init_table_with_size(const struct set_hash_type *, set_index_t);
static int set_delete(set_table *, set_data_t *); /* returns 0:notfound 1:deleted */
static int set_insert(set_table *, set_data_t);
static int set_lookup(set_table *, set_data_t);
/* *key may be altered, but must equal to the old key, i.e., the
 * results of hash() are same and compare() returns 0, otherwise the
 * behavior is undefined */
typedef int set_foreach_callback_func(set_data_t, set_data_t);
typedef int set_foreach_check_callback_func(set_data_t, set_data_t, int);
static int set_foreach(set_table *, set_foreach_callback_func *, set_data_t);
static int set_foreach_check(set_table *, set_foreach_check_callback_func *, set_data_t, set_data_t);
static set_index_t set_keys(set_table *table, set_data_t *keys, set_index_t size);
static void set_free_table(set_table *);
static void set_clear(set_table *);
static set_table *set_copy(set_table *);
static CONSTFUNC(int set_numcmp(set_data_t, set_data_t));
static PUREFUNC(size_t set_memsize(const set_table *));
static PUREFUNC(set_index_t set_hash(const void *ptr, size_t len, set_index_t h));
static CONSTFUNC(set_index_t set_hash_end(set_index_t h));
static CONSTFUNC(set_index_t set_hash_start(set_index_t h));

/* The type of hashes.  */
typedef set_index_t set_hash_t;

struct set_table_entry {
    set_hash_t hash;
    set_data_t key;
};

/* Value used to catch uninitialized entries/bins during debugging.
   There is a possibility for a false alarm, but its probability is
   extremely small.  */
#define SET_INIT_VAL 0xafafafafafafafaf
#define SET_INIT_VAL_BYTE 0xafa

#undef malloc
#undef realloc
#undef calloc
#undef free
#define malloc ruby_xmalloc
#define calloc ruby_xcalloc
#define realloc ruby_xrealloc
#define free ruby_xfree

#define EQUAL(tab,x,y) ((x) == (y) || (*(tab)->type->compare)((x),(y)) == 0)
#define PTR_EQUAL(tab, ptr, hash_val, key_) \
    ((ptr)->hash == (hash_val) && EQUAL((tab), (key_), (ptr)->key))

/* As PTR_EQUAL only its result is returned in RES.  REBUILT_P is set
   up to TRUE if the table is rebuilt during the comparison.  */
#define DO_PTR_EQUAL_CHECK(tab, ptr, hash_val, key, res, rebuilt_p) \
    do {							    \
        unsigned int _old_rebuilds_num = (tab)->rebuilds_num;       \
        res = PTR_EQUAL(tab, ptr, hash_val, key);		    \
        rebuilt_p = _old_rebuilds_num != (tab)->rebuilds_num;	    \
    } while (FALSE)

/* Features of a table.  */
struct set_features {
    /* Power of 2 used for number of allocated entries.  */
    unsigned char entry_power;
    /* Power of 2 used for number of allocated bins.  Depending on the
       table size, the number of bins is 2-4 times more than the
       number of entries.  */
    unsigned char bin_power;
    /* Enumeration of sizes of bins (8-bit, 16-bit etc).  */
    unsigned char size_ind;
    /* Bins are packed in words of type set_index_t.  The following is
       a size of bins counted by words.  */
    set_index_t bins_words;
};

/* Features of all possible size tables.  */
#if SIZEOF_SET_INDEX_T == 8
#define MAX_POWER2 62
static const struct set_features features[] = {
    {0, 1, 0, 0x0},
    {1, 2, 0, 0x1},
    {2, 3, 0, 0x1},
    {3, 4, 0, 0x2},
    {4, 5, 0, 0x4},
    {5, 6, 0, 0x8},
    {6, 7, 0, 0x10},
    {7, 8, 0, 0x20},
    {8, 9, 1, 0x80},
    {9, 10, 1, 0x100},
    {10, 11, 1, 0x200},
    {11, 12, 1, 0x400},
    {12, 13, 1, 0x800},
    {13, 14, 1, 0x1000},
    {14, 15, 1, 0x2000},
    {15, 16, 1, 0x4000},
    {16, 17, 2, 0x10000},
    {17, 18, 2, 0x20000},
    {18, 19, 2, 0x40000},
    {19, 20, 2, 0x80000},
    {20, 21, 2, 0x100000},
    {21, 22, 2, 0x200000},
    {22, 23, 2, 0x400000},
    {23, 24, 2, 0x800000},
    {24, 25, 2, 0x1000000},
    {25, 26, 2, 0x2000000},
    {26, 27, 2, 0x4000000},
    {27, 28, 2, 0x8000000},
    {28, 29, 2, 0x10000000},
    {29, 30, 2, 0x20000000},
    {30, 31, 2, 0x40000000},
    {31, 32, 2, 0x80000000},
    {32, 33, 3, 0x200000000},
    {33, 34, 3, 0x400000000},
    {34, 35, 3, 0x800000000},
    {35, 36, 3, 0x1000000000},
    {36, 37, 3, 0x2000000000},
    {37, 38, 3, 0x4000000000},
    {38, 39, 3, 0x8000000000},
    {39, 40, 3, 0x10000000000},
    {40, 41, 3, 0x20000000000},
    {41, 42, 3, 0x40000000000},
    {42, 43, 3, 0x80000000000},
    {43, 44, 3, 0x100000000000},
    {44, 45, 3, 0x200000000000},
    {45, 46, 3, 0x400000000000},
    {46, 47, 3, 0x800000000000},
    {47, 48, 3, 0x1000000000000},
    {48, 49, 3, 0x2000000000000},
    {49, 50, 3, 0x4000000000000},
    {50, 51, 3, 0x8000000000000},
    {51, 52, 3, 0x10000000000000},
    {52, 53, 3, 0x20000000000000},
    {53, 54, 3, 0x40000000000000},
    {54, 55, 3, 0x80000000000000},
    {55, 56, 3, 0x100000000000000},
    {56, 57, 3, 0x200000000000000},
    {57, 58, 3, 0x400000000000000},
    {58, 59, 3, 0x800000000000000},
    {59, 60, 3, 0x1000000000000000},
    {60, 61, 3, 0x2000000000000000},
    {61, 62, 3, 0x4000000000000000},
    {62, 63, 3, 0x8000000000000000},
};

#else
#define MAX_POWER2 30

static const struct set_features features[] = {
    {0, 1, 0, 0x1},
    {1, 2, 0, 0x1},
    {2, 3, 0, 0x2},
    {3, 4, 0, 0x4},
    {4, 5, 0, 0x8},
    {5, 6, 0, 0x10},
    {6, 7, 0, 0x20},
    {7, 8, 0, 0x40},
    {8, 9, 1, 0x100},
    {9, 10, 1, 0x200},
    {10, 11, 1, 0x400},
    {11, 12, 1, 0x800},
    {12, 13, 1, 0x1000},
    {13, 14, 1, 0x2000},
    {14, 15, 1, 0x4000},
    {15, 16, 1, 0x8000},
    {16, 17, 2, 0x20000},
    {17, 18, 2, 0x40000},
    {18, 19, 2, 0x80000},
    {19, 20, 2, 0x100000},
    {20, 21, 2, 0x200000},
    {21, 22, 2, 0x400000},
    {22, 23, 2, 0x800000},
    {23, 24, 2, 0x1000000},
    {24, 25, 2, 0x2000000},
    {25, 26, 2, 0x4000000},
    {26, 27, 2, 0x8000000},
    {27, 28, 2, 0x10000000},
    {28, 29, 2, 0x20000000},
    {29, 30, 2, 0x40000000},
    {30, 31, 2, 0x80000000},
};

#endif

/* The reserved hash value and its substitution.  */
#define RESERVED_HASH_VAL (~(set_hash_t) 0)
#define RESERVED_HASH_SUBSTITUTION_VAL ((set_hash_t) 0)

static inline set_hash_t
normalize_hash_value(set_hash_t hash)
{
    /* RESERVED_HASH_VAL is used for a deleted entry.  Map it into
       another value.  Such mapping should be extremely rare.  */
    return hash == RESERVED_HASH_VAL ? RESERVED_HASH_SUBSTITUTION_VAL : hash;
}

/* Return hash value of KEY for table TAB.  */
static inline set_hash_t
do_hash(set_data_t key, set_table *tab)
{
    set_hash_t hash = (set_hash_t)(tab->type->hash)(key);
    return normalize_hash_value(hash);
}

/* Power of 2 defining the minimal number of allocated entries.  */
#define MINIMAL_POWER2 2

#if MINIMAL_POWER2 < 2
#error "MINIMAL_POWER2 should be >= 2"
#endif

/* If the power2 of the allocated `entries` is less than the following
   value, don't allocate bins and use a linear search.  */
#define MAX_POWER2_FOR_TABLES_WITHOUT_BINS 4

/* Return smallest n >= MINIMAL_POWER2 such 2^n > SIZE.  */
static int
get_power2(set_index_t size)
{
    unsigned int n = SET_INDEX_BITS - nlz_intptr(size);
    if (n <= MAX_POWER2)
        return n < MINIMAL_POWER2 ? MINIMAL_POWER2 : n;
    /* Ran out of the table entries */
    rb_raise(rb_eRuntimeError, "set_table too big");
    /* should raise exception */
    return -1;
}

/* Return value of N-th bin in array BINS of table with bins size
   index S.  */
static inline set_index_t
get_bin(set_index_t *bins, int s, set_index_t n)
{
    return (s == 0 ? ((unsigned char *) bins)[n]
            : s == 1 ? ((unsigned short *) bins)[n]
            : s == 2 ? ((unsigned int *) bins)[n]
            : ((set_index_t *) bins)[n]);
}

/* Set up N-th bin in array BINS of table with bins size index S to
   value V.  */
static inline void
set_bin(set_index_t *bins, int s, set_index_t n, set_index_t v)
{
    if (s == 0) ((unsigned char *) bins)[n] = (unsigned char) v;
    else if (s == 1) ((unsigned short *) bins)[n] = (unsigned short) v;
    else if (s == 2) ((unsigned int *) bins)[n] = (unsigned int) v;
    else ((set_index_t *) bins)[n] = v;
}

/* These macros define reserved values for empty table bin and table
   bin which contains a deleted entry.  We will never use such values
   for an entry index in bins.  */
#define EMPTY_BIN    0
#define DELETED_BIN  1
/* Base of a real entry index in the bins.  */
#define ENTRY_BASE 2

/* Mark I-th bin of table TAB as empty, in other words not
   corresponding to any entry.  */
#define MARK_BIN_EMPTY(tab, i) (set_bin((tab)->bins, get_size_ind(tab), i, EMPTY_BIN))

/* Values used for not found entry and bin with given
   characteristics.  */
#define UNDEFINED_ENTRY_IND (~(set_index_t) 0)
#define UNDEFINED_BIN_IND (~(set_index_t) 0)

/* Entry and bin values returned when we found a table rebuild during
   the search.  */
#define REBUILT_TABLE_ENTRY_IND (~(set_index_t) 1)
#define REBUILT_TABLE_BIN_IND (~(set_index_t) 1)

/* Mark I-th bin of table TAB as corresponding to a deleted table
   entry.  Update number of entries in the table and number of bins
   corresponding to deleted entries. */
#define MARK_BIN_DELETED(tab, i)				\
    do {                                                        \
        set_bin((tab)->bins, get_size_ind(tab), i, DELETED_BIN); \
    } while (0)

/* Macros to check that value B is used empty bins and bins
   corresponding deleted entries.  */
#define EMPTY_BIN_P(b) ((b) == EMPTY_BIN)
#define DELETED_BIN_P(b) ((b) == DELETED_BIN)
#define EMPTY_OR_DELETED_BIN_P(b) ((b) <= DELETED_BIN)

/* Macros to check empty bins and bins corresponding to deleted
   entries.  Bins are given by their index I in table TAB.  */
#define IND_EMPTY_BIN_P(tab, i) (EMPTY_BIN_P(get_bin((tab)->bins, get_size_ind(tab), i)))
#define IND_DELETED_BIN_P(tab, i) (DELETED_BIN_P(get_bin((tab)->bins, get_size_ind(tab), i)))
#define IND_EMPTY_OR_DELETED_BIN_P(tab, i) (EMPTY_OR_DELETED_BIN_P(get_bin((tab)->bins, get_size_ind(tab), i)))

/* Macros for marking and checking deleted entries given by their
   pointer E_PTR.  */
#define MARK_ENTRY_DELETED(e_ptr) ((e_ptr)->hash = RESERVED_HASH_VAL)
#define DELETED_ENTRY_P(e_ptr) ((e_ptr)->hash == RESERVED_HASH_VAL)

/* Return bin size index of table TAB.  */
static inline unsigned int
get_size_ind(const set_table *tab)
{
    return tab->size_ind;
}

/* Return the number of allocated bins of table TAB.  */
static inline set_index_t
get_bins_num(const set_table *tab)
{
    return ((set_index_t) 1)<<tab->bin_power;
}

/* Return mask for a bin index in table TAB.  */
static inline set_index_t
bins_mask(const set_table *tab)
{
    return get_bins_num(tab) - 1;
}

/* Return the index of table TAB bin corresponding to
   HASH_VALUE.  */
static inline set_index_t
hash_bin(set_hash_t hash_value, set_table *tab)
{
    return hash_value & bins_mask(tab);
}

/* Return the number of allocated entries of table TAB.  */
static inline set_index_t
get_allocated_entries(const set_table *tab)
{
    return ((set_index_t) 1)<<tab->entry_power;
}

/* Return size of the allocated bins of table TAB.  */
static inline set_index_t
bins_size(const set_table *tab)
{
    return features[tab->entry_power].bins_words * sizeof (set_index_t);
}

/* Mark all bins of table TAB as empty.  */
static void
initialize_bins(set_table *tab)
{
    memset(tab->bins, 0, bins_size(tab));
}

/* Make table TAB empty.  */
static void
make_tab_empty(set_table *tab)
{
    tab->num_entries = 0;
    tab->entries_start = tab->entries_bound = 0;
    if (tab->bins != NULL)
        initialize_bins(tab);
}

#ifdef HASH_LOG
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
static struct {
    int all, total, num, str, strcase;
}  collision;

/* Flag switching off output of package statistics at the end of
   program.  */
static int init_st = 0;

/* Output overall number of table searches and collisions into a
   temporary file.  */
static void
stat_col(void)
{
    char fname[10+sizeof(long)*3];
    FILE *f;
    if (!collision.total) return;
    f = fopen((snprintf(fname, sizeof(fname), "/tmp/col%ld", (long)getpid()), fname), "w");
    if (f == NULL)
        return;
    fprintf(f, "collision: %d / %d (%6.2f)\n", collision.all, collision.total,
            ((double)collision.all / (collision.total)) * 100);
    fprintf(f, "num: %d, str: %d, strcase: %d\n", collision.num, collision.str, collision.strcase);
    fclose(f);
}
#endif

static set_table *
set_init_existing_table_with_size(set_table *tab, const struct set_hash_type *type, set_index_t size)
{
    int n;

#ifdef HASH_LOG
#if HASH_LOG+0 < 0
    {
        const char *e = getenv("SET_HASH_LOG");
        if (!e || !*e) init_st = 1;
    }
#endif
    if (init_st == 0) {
        init_st = 1;
        atexit(stat_col);
    }
#endif

    n = get_power2(size);

    tab->type = type;
    tab->entry_power = n;
    tab->bin_power = features[n].bin_power;
    tab->size_ind = features[n].size_ind;
    if (n <= MAX_POWER2_FOR_TABLES_WITHOUT_BINS)
        tab->bins = NULL;
    else {
        tab->bins = (set_index_t *) malloc(bins_size(tab));
    }
    tab->entries = (set_table_entry *) malloc(get_allocated_entries(tab)
                                             * sizeof(set_table_entry));
    make_tab_empty(tab);
    tab->rebuilds_num = 0;
    return tab;
}

/* Create and return table with TYPE which can hold at least SIZE
   entries.  The real number of entries which the table can hold is
   the nearest power of two for SIZE.  */
static set_table *
set_init_table_with_size(const struct set_hash_type *type, set_index_t size)
{
    set_table *tab = malloc(sizeof(set_table));

    set_init_existing_table_with_size(tab, type, size);

    return tab;
}

static size_t
set_table_size(const struct set_table *tbl)
{
    return tbl->num_entries;
}

/* Make table TAB empty.  */
static void
set_clear(set_table *tab)
{
    make_tab_empty(tab);
    tab->rebuilds_num++;
}

/* Free table TAB space.  */
static void
set_free_table(set_table *tab)
{
    free(tab->bins);
    free(tab->entries);
    free(tab);
}

/* Return byte size of memory allocated for table TAB.  */
static size_t
set_memsize(const set_table *tab)
{
    return(sizeof(set_table)
           + (tab->bins == NULL ? 0 : bins_size(tab))
           + get_allocated_entries(tab) * sizeof(set_table_entry));
}

static set_index_t
find_table_entry_ind(set_table *tab, set_hash_t hash_value, set_data_t key);

static set_index_t
find_table_bin_ind(set_table *tab, set_hash_t hash_value, set_data_t key);

static set_index_t
find_table_bin_ind_direct(set_table *table, set_hash_t hash_value, set_data_t key);

static set_index_t
find_table_bin_ptr_and_reserve(set_table *tab, set_hash_t *hash_value,
                               set_data_t key, set_index_t *bin_ind);

/* If the number of entries in the table is at least REBUILD_THRESHOLD
   times less than the entry array length, decrease the table
   size.  */
#define REBUILD_THRESHOLD 4

#if REBUILD_THRESHOLD < 2
#error "REBUILD_THRESHOLD should be >= 2"
#endif

static void rebuild_table_with(set_table *const new_tab, set_table *const tab);
static void rebuild_move_table(set_table *const new_tab, set_table *const tab);
static void rebuild_cleanup(set_table *const tab);

/* Rebuild table TAB.  Rebuilding removes all deleted bins and entries
   and can change size of the table entries and bins arrays.
   Rebuilding is implemented by creation of a new table or by
   compaction of the existing one.  */
static void
rebuild_table(set_table *tab)
{
    if ((2 * tab->num_entries <= get_allocated_entries(tab)
         && REBUILD_THRESHOLD * tab->num_entries > get_allocated_entries(tab))
        || tab->num_entries < (1 << MINIMAL_POWER2)) {
        /* Compaction: */
        tab->num_entries = 0;
        if (tab->bins != NULL)
            initialize_bins(tab);
        rebuild_table_with(tab, tab);
    }
    else {
        set_table *new_tab;
        /* This allocation could trigger GC and compaction. If tab is the
         * gen_iv_tbl, then tab could have changed in size due to objects being
         * freed and/or moved. Do not store attributes of tab before this line. */
        new_tab = set_init_table_with_size(tab->type,
                                          2 * tab->num_entries - 1);
        rebuild_table_with(new_tab, tab);
        rebuild_move_table(new_tab, tab);
    }
    rebuild_cleanup(tab);
}

static void
rebuild_table_with(set_table *const new_tab, set_table *const tab)
{
    set_index_t i, ni;
    unsigned int size_ind;
    set_table_entry *new_entries;
    set_table_entry *curr_entry_ptr;
    set_index_t *bins;
    set_index_t bin_ind;

    new_entries = new_tab->entries;

    ni = 0;
    bins = new_tab->bins;
    size_ind = get_size_ind(new_tab);
    set_index_t bound = tab->entries_bound;
    set_table_entry *entries = tab->entries;

    for (i = tab->entries_start; i < bound; i++) {
        curr_entry_ptr = &entries[i];
        PREFETCH(entries + i + 1, 0);
        if (EXPECT(DELETED_ENTRY_P(curr_entry_ptr), 0))
            continue;
        if (&new_entries[ni] != curr_entry_ptr)
            new_entries[ni] = *curr_entry_ptr;
        if (EXPECT(bins != NULL, 1)) {
            bin_ind = find_table_bin_ind_direct(new_tab, curr_entry_ptr->hash,
                                                curr_entry_ptr->key);
            set_bin(bins, size_ind, bin_ind, ni + ENTRY_BASE);
        }
        new_tab->num_entries++;
        ni++;
    }

    assert(new_tab->num_entries == tab->num_entries);
}

static void
rebuild_move_table(set_table *const new_tab, set_table *const tab)
{
    tab->entry_power = new_tab->entry_power;
    tab->bin_power = new_tab->bin_power;
    tab->size_ind = new_tab->size_ind;
    free(tab->bins);
    tab->bins = new_tab->bins;
    free(tab->entries);
    tab->entries = new_tab->entries;
    free(new_tab);
}

static void
rebuild_cleanup(set_table *const tab)
{
    tab->entries_start = 0;
    tab->entries_bound = tab->num_entries;
    tab->rebuilds_num++;
}

/* Return the next secondary hash index for table TAB using previous
   index IND and PERTURB.  Finally modulo of the function becomes a
   full *cycle linear congruential generator*, in other words it
   guarantees traversing all table bins in extreme case.

   According the Hull-Dobell theorem a generator
   "Xnext = (a*Xprev + c) mod m" is a full cycle generator if and only if
     o m and c are relatively prime
     o a-1 is divisible by all prime factors of m
     o a-1 is divisible by 4 if m is divisible by 4.

   For our case a is 5, c is 1, and m is a power of two.  */
static inline set_index_t
secondary_hash(set_index_t ind, set_table *tab, set_index_t *perturb)
{
    *perturb >>= 11;
    ind = (ind << 2) + ind + *perturb + 1;
    return hash_bin(ind, tab);
}

/* Find an entry with HASH_VALUE and KEY in TABLE using a linear
   search.  Return the index of the found entry in array `entries`.
   If it is not found, return UNDEFINED_ENTRY_IND.  If the table was
   rebuilt during the search, return REBUILT_TABLE_ENTRY_IND.  */
static inline set_index_t
find_entry(set_table *tab, set_hash_t hash_value, set_data_t key)
{
    int eq_p, rebuilt_p;
    set_index_t i, bound;
    set_table_entry *entries;

    bound = tab->entries_bound;
    entries = tab->entries;
    for (i = tab->entries_start; i < bound; i++) {
        DO_PTR_EQUAL_CHECK(tab, &entries[i], hash_value, key, eq_p, rebuilt_p);
        if (EXPECT(rebuilt_p, 0))
            return REBUILT_TABLE_ENTRY_IND;
        if (eq_p)
            return i;
    }
    return UNDEFINED_ENTRY_IND;
}

/* Use the quadratic probing.  The method has a better data locality
   but more collisions than the current approach.  In average it
   results in a bit slower search.  */
/*#define QUADRATIC_PROBE*/

/* Return index of entry with HASH_VALUE and KEY in table TAB.  If
   there is no such entry, return UNDEFINED_ENTRY_IND.  If the table
   was rebuilt during the search, return REBUILT_TABLE_ENTRY_IND.  */
static set_index_t
find_table_entry_ind(set_table *tab, set_hash_t hash_value, set_data_t key)
{
    int eq_p, rebuilt_p;
    set_index_t ind;
#ifdef QUADRATIC_PROBE
    set_index_t d;
#else
    set_index_t perturb;
#endif
    set_index_t bin;
    set_table_entry *entries = tab->entries;

    ind = hash_bin(hash_value, tab);
#ifdef QUADRATIC_PROBE
    d = 1;
#else
    perturb = hash_value;
#endif
    for (;;) {
        bin = get_bin(tab->bins, get_size_ind(tab), ind);
        if (! EMPTY_OR_DELETED_BIN_P(bin)) {
            DO_PTR_EQUAL_CHECK(tab, &entries[bin - ENTRY_BASE], hash_value, key, eq_p, rebuilt_p);
            if (EXPECT(rebuilt_p, 0))
                return REBUILT_TABLE_ENTRY_IND;
            if (eq_p)
                break;
        }
        else if (EMPTY_BIN_P(bin))
            return UNDEFINED_ENTRY_IND;
#ifdef QUADRATIC_PROBE
        ind = hash_bin(ind + d, tab);
        d++;
#else
        ind = secondary_hash(ind, tab, &perturb);
#endif
    }
    return bin;
}

/* Find and return index of table TAB bin corresponding to an entry
   with HASH_VALUE and KEY.  If there is no such bin, return
   UNDEFINED_BIN_IND.  If the table was rebuilt during the search,
   return REBUILT_TABLE_BIN_IND.  */
static set_index_t
find_table_bin_ind(set_table *tab, set_hash_t hash_value, set_data_t key)
{
    int eq_p, rebuilt_p;
    set_index_t ind;
#ifdef QUADRATIC_PROBE
    set_index_t d;
#else
    set_index_t perturb;
#endif
    set_index_t bin;
    set_table_entry *entries = tab->entries;

    ind = hash_bin(hash_value, tab);
#ifdef QUADRATIC_PROBE
    d = 1;
#else
    perturb = hash_value;
#endif
    for (;;) {
        bin = get_bin(tab->bins, get_size_ind(tab), ind);
        if (! EMPTY_OR_DELETED_BIN_P(bin)) {
            DO_PTR_EQUAL_CHECK(tab, &entries[bin - ENTRY_BASE], hash_value, key, eq_p, rebuilt_p);
            if (EXPECT(rebuilt_p, 0))
                return REBUILT_TABLE_BIN_IND;
            if (eq_p)
                break;
        }
        else if (EMPTY_BIN_P(bin))
            return UNDEFINED_BIN_IND;
#ifdef QUADRATIC_PROBE
        ind = hash_bin(ind + d, tab);
        d++;
#else
        ind = secondary_hash(ind, tab, &perturb);
#endif
    }
    return ind;
}

/* Find and return index of table TAB bin corresponding to an entry
   with HASH_VALUE and KEY.  The entry should be in the table
   already.  */
static set_index_t
find_table_bin_ind_direct(set_table *tab, set_hash_t hash_value, set_data_t key)
{
    set_index_t ind;
#ifdef QUADRATIC_PROBE
    set_index_t d;
#else
    set_index_t perturb;
#endif
    set_index_t bin;

    ind = hash_bin(hash_value, tab);
#ifdef QUADRATIC_PROBE
    d = 1;
#else
    perturb = hash_value;
#endif
    for (;;) {
        bin = get_bin(tab->bins, get_size_ind(tab), ind);
        if (EMPTY_OR_DELETED_BIN_P(bin))
            return ind;
#ifdef QUADRATIC_PROBE
        ind = hash_bin(ind + d, tab);
        d++;
#else
        ind = secondary_hash(ind, tab, &perturb);
#endif
    }
}

/* Return index of table TAB bin for HASH_VALUE and KEY through
   BIN_IND and the pointed value as the function result.  Reserve the
   bin for inclusion of the corresponding entry into the table if it
   is not there yet.  We always find such bin as bins array length is
   bigger entries array.  Although we can reuse a deleted bin, the
   result bin value is always empty if the table has no entry with
   KEY.  Return the entries array index of the found entry or
   UNDEFINED_ENTRY_IND if it is not found.  If the table was rebuilt
   during the search, return REBUILT_TABLE_ENTRY_IND.  */
static set_index_t
find_table_bin_ptr_and_reserve(set_table *tab, set_hash_t *hash_value,
                               set_data_t key, set_index_t *bin_ind)
{
    int eq_p, rebuilt_p;
    set_index_t ind;
    set_hash_t curr_hash_value = *hash_value;
#ifdef QUADRATIC_PROBE
    set_index_t d;
#else
    set_index_t perturb;
#endif
    set_index_t entry_index;
    set_index_t firset_deleted_bin_ind;
    set_table_entry *entries;

    ind = hash_bin(curr_hash_value, tab);
#ifdef QUADRATIC_PROBE
    d = 1;
#else
    perturb = curr_hash_value;
#endif
    firset_deleted_bin_ind = UNDEFINED_BIN_IND;
    entries = tab->entries;
    for (;;) {
        entry_index = get_bin(tab->bins, get_size_ind(tab), ind);
        if (EMPTY_BIN_P(entry_index)) {
            tab->num_entries++;
            entry_index = UNDEFINED_ENTRY_IND;
            if (firset_deleted_bin_ind != UNDEFINED_BIN_IND) {
                /* We can reuse bin of a deleted entry.  */
                ind = firset_deleted_bin_ind;
                MARK_BIN_EMPTY(tab, ind);
            }
            break;
        }
        else if (! DELETED_BIN_P(entry_index)) {
            DO_PTR_EQUAL_CHECK(tab, &entries[entry_index - ENTRY_BASE], curr_hash_value, key, eq_p, rebuilt_p);
            if (EXPECT(rebuilt_p, 0))
                return REBUILT_TABLE_ENTRY_IND;
            if (eq_p)
                break;
        }
        else if (firset_deleted_bin_ind == UNDEFINED_BIN_IND)
            firset_deleted_bin_ind = ind;
#ifdef QUADRATIC_PROBE
        ind = hash_bin(ind + d, tab);
        d++;
#else
        ind = secondary_hash(ind, tab, &perturb);
#endif
    }
    *bin_ind = ind;
    return entry_index;
}

/* Find an entry with KEY in table TAB.  Return non-zero if we found
   it.  */
static int
set_lookup(set_table *tab, set_data_t key)
{
    set_index_t bin;
    set_hash_t hash = do_hash(key, tab);

 retry:
    if (tab->bins == NULL) {
        bin = find_entry(tab, hash, key);
        if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0))
            goto retry;
        if (bin == UNDEFINED_ENTRY_IND)
            return 0;
    }
    else {
        bin = find_table_entry_ind(tab, hash, key);
        if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0))
            goto retry;
        if (bin == UNDEFINED_ENTRY_IND)
            return 0;
        bin -= ENTRY_BASE;
    }
    return 1;
}

/* Check the table and rebuild it if it is necessary.  */
static inline void
rebuild_table_if_necessary (set_table *tab)
{
    set_index_t bound = tab->entries_bound;

    if (bound == get_allocated_entries(tab))
        rebuild_table(tab);
}

static set_data_t
set_stringify(VALUE key)
{
    return (rb_obj_class(key) == rb_cString && !RB_OBJ_FROZEN(key)) ?
        rb_hash_key_str(key) : key;
}

static set_index_t
dbl_to_index(double d)
{
    union {double d; set_index_t i;} u;
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

static set_index_t
set_ident_hash(set_data_t n)
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

    return (set_index_t)set_index_hash((set_index_t)n);
}

static const struct set_hash_type identhash = {
    set_numcmp,
    set_ident_hash,
};

/* Insert (KEY, VALUE) into table TAB and return zero.  If there is
   already entry with KEY in the table, return nonzero and update
   the value of the found entry.  */
static int
set_insert(set_table *tab, set_data_t key)
{
    set_table_entry *entry;
    set_index_t bin;
    set_index_t ind;
    set_hash_t hash_value;
    set_index_t bin_ind;
    int new_p;
    if (tab->type != &identhash) {
        key = set_stringify(key);
    }

    hash_value = do_hash(key, tab);
 retry:
    rebuild_table_if_necessary(tab);
    if (tab->bins == NULL) {
        bin = find_entry(tab, hash_value, key);
        if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0))
            goto retry;
        new_p = bin == UNDEFINED_ENTRY_IND;
        if (new_p)
            tab->num_entries++;
        bin_ind = UNDEFINED_BIN_IND;
    }
    else {
        bin = find_table_bin_ptr_and_reserve(tab, &hash_value,
                                             key, &bin_ind);
        if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0))
            goto retry;
        new_p = bin == UNDEFINED_ENTRY_IND;
        bin -= ENTRY_BASE;
    }
    if (new_p) {
        ind = tab->entries_bound++;
        entry = &tab->entries[ind];
        entry->hash = hash_value;
        entry->key = key;
        if (bin_ind != UNDEFINED_BIN_IND)
            set_bin(tab->bins, get_size_ind(tab), bin_ind, ind + ENTRY_BASE);
        return 0;
    }
    return 1;
}

/* Insert (KEY, VALUE, HASH) into table TAB.  The table should not have
   entry with KEY before the insertion.  */
static inline void
set_add_direct_with_hash(set_table *tab,
                        set_data_t key, set_hash_t hash)
{
    set_table_entry *entry;
    set_index_t ind;
    set_index_t bin_ind;

    assert(hash != RESERVED_HASH_VAL);

    rebuild_table_if_necessary(tab);
    ind = tab->entries_bound++;
    entry = &tab->entries[ind];
    entry->hash = hash;
    entry->key = key;
    tab->num_entries++;
    if (tab->bins != NULL) {
        bin_ind = find_table_bin_ind_direct(tab, hash, key);
        set_bin(tab->bins, get_size_ind(tab), bin_ind, ind + ENTRY_BASE);
    }
}

/* Create a copy of old_tab into new_tab. */
static set_table *
set_replace(set_table *new_tab, set_table *old_tab)
{
    *new_tab = *old_tab;
    if (old_tab->bins == NULL)
        new_tab->bins = NULL;
    else {
        new_tab->bins = (set_index_t *) malloc(bins_size(old_tab));
    }
    new_tab->entries = (set_table_entry *) malloc(get_allocated_entries(old_tab)
                                                 * sizeof(set_table_entry));
    MEMCPY(new_tab->entries, old_tab->entries, set_table_entry,
           get_allocated_entries(old_tab));
    if (old_tab->bins != NULL)
        MEMCPY(new_tab->bins, old_tab->bins, char, bins_size(old_tab));

    return new_tab;
}

/* Create and return a copy of table OLD_TAB.  */
static set_table *
set_copy(set_table *old_tab)
{
    set_table *new_tab;

    new_tab = (set_table *) malloc(sizeof(set_table));

    if (set_replace(new_tab, old_tab) == NULL) {
        set_free_table(new_tab);
        return NULL;
    }

    return new_tab;
}

/* Update the entries start of table TAB after removing an entry
   with index N in the array entries.  */
static inline void
update_range_for_deleted(set_table *tab, set_index_t n)
{
    /* Do not update entries_bound here.  Otherwise, we can fill all
       bins by deleted entry value before rebuilding the table.  */
    if (tab->entries_start == n) {
        set_index_t start = n + 1;
        set_index_t bound = tab->entries_bound;
        set_table_entry *entries = tab->entries;
        while (start < bound && DELETED_ENTRY_P(&entries[start])) start++;
        tab->entries_start = start;
    }
}

/* Delete entry with KEY from table TAB, set up *VALUE (unless
   VALUE is zero) from deleted table entry, and return non-zero.  If
   there is no entry with KEY in the table, clear *VALUE (unless VALUE
   is zero), and return zero.  */
static int
set_delete(set_table *tab, set_data_t *key)
{
    set_table_entry *entry;
    set_index_t bin;
    set_index_t bin_ind;
    set_hash_t hash;

    hash = do_hash(*key, tab);
 retry:
    if (tab->bins == NULL) {
        bin = find_entry(tab, hash, *key);
        if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0))
            goto retry;
        if (bin == UNDEFINED_ENTRY_IND) {
            return 0;
        }
    }
    else {
        bin_ind = find_table_bin_ind(tab, hash, *key);
        if (EXPECT(bin_ind == REBUILT_TABLE_BIN_IND, 0))
            goto retry;
        if (bin_ind == UNDEFINED_BIN_IND) {
            return 0;
        }
        bin = get_bin(tab->bins, get_size_ind(tab), bin_ind) - ENTRY_BASE;
        MARK_BIN_DELETED(tab, bin_ind);
    }
    entry = &tab->entries[bin];
    *key = entry->key;
    MARK_ENTRY_DELETED(entry);
    tab->num_entries--;
    update_range_for_deleted(tab, bin);
    return 1;
}

/* Traverse all entries in table TAB calling FUNC with current entry
   key and value and zero.  If the call returns SET_STOP, stop
   traversing.  If the call returns SET_DELETE, delete the current
   entry from the table.  In case of SET_CHECK or SET_CONTINUE, continue
   traversing.  The function returns zero unless an error is found.
   CHECK_P is flag of set_foreach_check call.  The behavior is a bit
   different for SET_CHECK and when the current element is removed
   during traversing.  */
static inline int
set_general_foreach(set_table *tab, set_foreach_check_callback_func *func, set_data_t arg,
                   int check_p)
{
    set_index_t bin;
    set_index_t bin_ind;
    set_table_entry *entries, *curr_entry_ptr;
    enum set_retval retval;
    set_index_t i, rebuilds_num;
    set_hash_t hash;
    set_data_t key;
    int error_p, packed_p = tab->bins == NULL;

    entries = tab->entries;
    /* The bound can change inside the loop even without rebuilding
       the table, e.g. by an entry insertion.  */
    for (i = tab->entries_start; i < tab->entries_bound; i++) {
        curr_entry_ptr = &entries[i];
        if (EXPECT(DELETED_ENTRY_P(curr_entry_ptr), 0))
            continue;
        key = curr_entry_ptr->key;
        rebuilds_num = tab->rebuilds_num;
        hash = curr_entry_ptr->hash;
        retval = (*func)(key, arg, 0);

        if (rebuilds_num != tab->rebuilds_num) {
        retry:
            entries = tab->entries;
            packed_p = tab->bins == NULL;
            if (packed_p) {
                i = find_entry(tab, hash, key);
                if (EXPECT(i == REBUILT_TABLE_ENTRY_IND, 0))
                    goto retry;
                error_p = i == UNDEFINED_ENTRY_IND;
            }
            else {
                i = find_table_entry_ind(tab, hash, key);
                if (EXPECT(i == REBUILT_TABLE_ENTRY_IND, 0))
                    goto retry;
                error_p = i == UNDEFINED_ENTRY_IND;
                i -= ENTRY_BASE;
            }
            if (error_p && check_p) {
                /* call func with error notice */
                retval = (*func)(0, arg, 1);
                return 1;
            }
            curr_entry_ptr = &entries[i];
        }
        switch (retval) {
          case SET_CONTINUE:
            break;
          case SET_CHECK:
            if (check_p)
                break;
          case SET_STOP:
            return 0;
          case SET_DELETE: {
            set_data_t key = curr_entry_ptr->key;

              again:
            if (packed_p) {
                bin = find_entry(tab, hash, key);
                if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0))
                    goto again;
                if (bin == UNDEFINED_ENTRY_IND)
                    break;
            }
            else {
                bin_ind = find_table_bin_ind(tab, hash, key);
                if (EXPECT(bin_ind == REBUILT_TABLE_BIN_IND, 0))
                    goto again;
                if (bin_ind == UNDEFINED_BIN_IND)
                    break;
                bin = get_bin(tab->bins, get_size_ind(tab), bin_ind) - ENTRY_BASE;
                MARK_BIN_DELETED(tab, bin_ind);
            }
            curr_entry_ptr = &entries[bin];
            MARK_ENTRY_DELETED(curr_entry_ptr);
            tab->num_entries--;
            update_range_for_deleted(tab, bin);
            break;
          }
        }
    }
    return 0;
}

struct functor {
    set_foreach_callback_func *func;
    set_data_t arg;
};

static int
apply_functor(set_data_t k, set_data_t d, int _)
{
    const struct functor *f = (void *)d;
    return f->func(k, f->arg);
}

static int
set_foreach(set_table *tab, set_foreach_callback_func *func, set_data_t arg)
{
    const struct functor f = { func, arg };
    return set_general_foreach(tab, apply_functor, (set_data_t)&f, FALSE);
}

/* See comments for function set_delete_safe.  */
static int
set_foreach_check(set_table *tab, set_foreach_check_callback_func *func, set_data_t arg,
                 set_data_t never ATTRIBUTE_UNUSED)
{
    return set_general_foreach(tab, func, arg, TRUE);
}

/* Set up array KEYS by at most SIZE keys of head table TAB entries.
   Return the number of keys set up in array KEYS.  */
static inline set_index_t
set_keys(set_table *tab, set_data_t *keys, set_index_t size)
{
    set_index_t i, bound;
    set_data_t key, *keys_start, *keys_end;
    set_table_entry *curr_entry_ptr, *entries = tab->entries;

    bound = tab->entries_bound;
    keys_start = keys;
    keys_end = keys + size;
    for (i = tab->entries_start; i < bound; i++) {
        if (keys == keys_end)
            break;
        curr_entry_ptr = &entries[i];
        key = curr_entry_ptr->key;
        if (! DELETED_ENTRY_P(curr_entry_ptr))
            *keys++ = key;
    }

    return keys - keys_start;
}

#define FNV1_32A_INIT 0x811c9dc5

/*
 * 32 bit magic FNV-1a prime
 */
#define FNV_32_PRIME 0x01000193

/* __POWERPC__ added to accommodate Darwin case. */
#ifndef UNALIGNED_WORD_ACCESS
# if defined(__i386) || defined(__i386__) || defined(_M_IX86) || \
     defined(__x86_64) || defined(__x86_64__) || defined(_M_AMD64) || \
     defined(__powerpc64__) || defined(__POWERPC__) || defined(__aarch64__) || \
     defined(__mc68020__)
#   define UNALIGNED_WORD_ACCESS 1
# endif
#endif
#ifndef UNALIGNED_WORD_ACCESS
# define UNALIGNED_WORD_ACCESS 0
#endif

/* This hash function is quite simplified MurmurHash3
 * Simplification is legal, cause most of magic still happens in finalizator.
 * And finalizator is almost the same as in MurmurHash3 */
#define BIG_CONSTANT(x,y) ((set_index_t)(x)<<32|(set_index_t)(y))
#define ROTL(x,n) ((x)<<(n)|(x)>>(SIZEOF_SET_INDEX_T*CHAR_BIT-(n)))

#if SET_INDEX_BITS <= 32
#define C1 (set_index_t)0xcc9e2d51
#define C2 (set_index_t)0x1b873593
#else
#define C1 BIG_CONSTANT(0x87c37b91,0x114253d5);
#define C2 BIG_CONSTANT(0x4cf5ad43,0x2745937f);
#endif
NO_SANITIZE("unsigned-integer-overflow", static inline set_index_t murmur_step(set_index_t h, set_index_t k));
NO_SANITIZE("unsigned-integer-overflow", static inline set_index_t murmur_finish(set_index_t h));
NO_SANITIZE("unsigned-integer-overflow", extern set_index_t set_hash(const void *ptr, size_t len, set_index_t h));

static inline set_index_t
murmur_step(set_index_t h, set_index_t k)
{
#if SET_INDEX_BITS <= 32
#define r1 (17)
#define r2 (11)
#else
#define r1 (33)
#define r2 (24)
#endif
    k *= C1;
    h ^= ROTL(k, r1);
    h *= C2;
    h = ROTL(h, r2);
    return h;
}
#undef r1
#undef r2

static inline set_index_t
murmur_finish(set_index_t h)
{
#if SET_INDEX_BITS <= 32
#define r1 (16)
#define r2 (13)
#define r3 (16)
    const set_index_t c1 = 0x85ebca6b;
    const set_index_t c2 = 0xc2b2ae35;
#else
/* values are taken from Mix13 on http://zimbry.blogspot.ru/2011/09/better-bit-mixing-improving-on.html */
#define r1 (30)
#define r2 (27)
#define r3 (31)
    const set_index_t c1 = BIG_CONSTANT(0xbf58476d,0x1ce4e5b9);
    const set_index_t c2 = BIG_CONSTANT(0x94d049bb,0x133111eb);
#endif
#if SET_INDEX_BITS > 64
    h ^= h >> 64;
    h *= c2;
    h ^= h >> 65;
#endif
    h ^= h >> r1;
    h *= c1;
    h ^= h >> r2;
    h *= c2;
    h ^= h >> r3;
    return h;
}
#undef r1
#undef r2
#undef r3

static set_index_t
set_hash(const void *ptr, size_t len, set_index_t h)
{
    const char *data = ptr;
    set_index_t t = 0;
    size_t l = len;

#define data_at(n) (set_index_t)((unsigned char)data[(n)])
#define UNALIGNED_ADD_4 UNALIGNED_ADD(2); UNALIGNED_ADD(1); UNALIGNED_ADD(0)
#if SIZEOF_SET_INDEX_T > 4
#define UNALIGNED_ADD_8 UNALIGNED_ADD(6); UNALIGNED_ADD(5); UNALIGNED_ADD(4); UNALIGNED_ADD(3); UNALIGNED_ADD_4
#if SIZEOF_SET_INDEX_T > 8
#define UNALIGNED_ADD_16 UNALIGNED_ADD(14); UNALIGNED_ADD(13); UNALIGNED_ADD(12); UNALIGNED_ADD(11); \
    UNALIGNED_ADD(10); UNALIGNED_ADD(9); UNALIGNED_ADD(8); UNALIGNED_ADD(7); UNALIGNED_ADD_8
#define UNALIGNED_ADD_ALL UNALIGNED_ADD_16
#endif
#define UNALIGNED_ADD_ALL UNALIGNED_ADD_8
#else
#define UNALIGNED_ADD_ALL UNALIGNED_ADD_4
#endif
#undef SKIP_TAIL
    if (len >= sizeof(set_index_t)) {
#if !UNALIGNED_WORD_ACCESS
        int align = (int)((set_data_t)data % sizeof(set_index_t));
        if (align) {
            set_index_t d = 0;
            int sl, sr, pack;

            switch (align) {
#ifdef WORDS_BIGENDIAN
# define UNALIGNED_ADD(n) case SIZEOF_SET_INDEX_T - (n) - 1: \
                t |= data_at(n) << CHAR_BIT*(SIZEOF_SET_INDEX_T - (n) - 2)
#else
# define UNALIGNED_ADD(n) case SIZEOF_SET_INDEX_T - (n) - 1:	\
                t |= data_at(n) << CHAR_BIT*(n)
#endif
                UNALIGNED_ADD_ALL;
#undef UNALIGNED_ADD
            }

#ifdef WORDS_BIGENDIAN
            t >>= (CHAR_BIT * align) - CHAR_BIT;
#else
            t <<= (CHAR_BIT * align);
#endif

            data += sizeof(set_index_t)-align;
            len -= sizeof(set_index_t)-align;

            sl = CHAR_BIT * (SIZEOF_SET_INDEX_T-align);
            sr = CHAR_BIT * align;

            while (len >= sizeof(set_index_t)) {
                d = *(set_index_t *)data;
#ifdef WORDS_BIGENDIAN
                t = (t << sr) | (d >> sl);
#else
                t = (t >> sr) | (d << sl);
#endif
                h = murmur_step(h, t);
                t = d;
                data += sizeof(set_index_t);
                len -= sizeof(set_index_t);
            }

            pack = len < (size_t)align ? (int)len : align;
            d = 0;
            switch (pack) {
#ifdef WORDS_BIGENDIAN
# define UNALIGNED_ADD(n) case (n) + 1: \
                d |= data_at(n) << CHAR_BIT*(SIZEOF_SET_INDEX_T - (n) - 1)
#else
# define UNALIGNED_ADD(n) case (n) + 1: \
                d |= data_at(n) << CHAR_BIT*(n)
#endif
                UNALIGNED_ADD_ALL;
#undef UNALIGNED_ADD
            }
#ifdef WORDS_BIGENDIAN
            t = (t << sr) | (d >> sl);
#else
            t = (t >> sr) | (d << sl);
#endif

            if (len < (size_t)align) goto skip_tail;
# define SKIP_TAIL 1
            h = murmur_step(h, t);
            data += pack;
            len -= pack;
        }
        else
#endif
#ifdef HAVE_BUILTIN___BUILTIN_ASSUME_ALIGNED
#define aligned_data __builtin_assume_aligned(data, sizeof(set_index_t))
#else
#define aligned_data data
#endif
        {
            do {
                h = murmur_step(h, *(set_index_t *)aligned_data);
                data += sizeof(set_index_t);
                len -= sizeof(set_index_t);
            } while (len >= sizeof(set_index_t));
        }
    }

    t = 0;
    switch (len) {
#if UNALIGNED_WORD_ACCESS && SIZEOF_SET_INDEX_T <= 8 && CHAR_BIT == 8
    /* in this case byteorder doesn't really matter */
#if SIZEOF_SET_INDEX_T > 4
      case 7: t |= data_at(6) << 48;
      case 6: t |= data_at(5) << 40;
      case 5: t |= data_at(4) << 32;
      case 4:
        t |= (set_index_t)*(uint32_t*)aligned_data;
        goto skip_tail;
# define SKIP_TAIL 1
#endif
      case 3: t |= data_at(2) << 16;
      case 2: t |= data_at(1) << 8;
      case 1: t |= data_at(0);
#else
#ifdef WORDS_BIGENDIAN
# define UNALIGNED_ADD(n) case (n) + 1: \
        t |= data_at(n) << CHAR_BIT*(SIZEOF_SET_INDEX_T - (n) - 1)
#else
# define UNALIGNED_ADD(n) case (n) + 1: \
        t |= data_at(n) << CHAR_BIT*(n)
#endif
        UNALIGNED_ADD_ALL;
#undef UNALIGNED_ADD
#endif
#ifdef SKIP_TAIL
      skip_tail:
#endif
        h ^= t; h -= ROTL(t, 7);
        h *= C2;
    }
    h ^= l;
#undef aligned_data

    return murmur_finish(h);
}

static set_index_t
set_hash_end(set_index_t h)
{
    h = murmur_finish(h);
    return h;
}

#undef set_hash_start
static set_index_t
set_hash_start(set_index_t h)
{
    return h;
}

static int
set_numcmp(set_data_t x, set_data_t y)
{
    return x != y;
}

static void
set_compact_table(set_table *tab)
{
    set_index_t num = tab->num_entries;
    if (REBUILD_THRESHOLD * num <= get_allocated_entries(tab)) {
        /* Compaction: */
        set_table *new_tab = set_init_table_with_size(tab->type, 2 * num);
        rebuild_table_with(new_tab, tab);
        rebuild_move_table(new_tab, tab);
        rebuild_cleanup(tab);
    }
}

static const struct set_hash_type objhash = {
    rb_any_cmp,
    rb_any_hash,
};

VALUE rb_cSet;

#define id_each idEach
static ID id_each_entry;
static ID id_any_p;
static ID id_new;
static ID id_set_iter_lev;

#define RSET_INITIALIZED FL_USER1
#define RSET_LEV_MASK (FL_USER13 | FL_USER14 | FL_USER15 |                /* FL 13..19 */ \
                        FL_USER16 | FL_USER17 | FL_USER18 | FL_USER19)
#define RSET_LEV_SHIFT (FL_USHIFT + 13)
#define RSET_LEV_MAX 127 /* 7 bits */

#define SET_ASSERT(expr) RUBY_ASSERT_MESG_WHEN(SET_DEBUG, expr, #expr)

#define RSET_TABLE_SIZE(sobj) set_table_size((sobj)->table)

#define RSET_SIZE(set) set_table_size(RSET_TABLE(set))
#define RSET_EMPTY(set) (RSET_SIZE(set) == 0)
#define RSET_SIZE_NUM(set) SIZET2NUM(RSET_SIZE(set))
#define RSET_IS_MEMBER(sobj, item) set_lookup(RSET_TABLE(set), (set_data_t)(item))
#define RSET_COMPARE_BY_IDENTITY(set) (RSET_TABLE(set)->type == &identhash)

struct set_object {
    set_table *table;
};

static int
mark_key(set_data_t key, set_data_t data)
{
    rb_gc_mark((VALUE)key);

    return SET_CONTINUE;
}

static void
set_mark(void *ptr)
{
    struct set_object *sobj = ptr;
    if (sobj->table) set_foreach(sobj->table, mark_key, 0);
}

static void
set_free(void *ptr)
{
    struct set_object *sobj = ptr;
    set_free_table(sobj->table);
    sobj->table = NULL;
}

static size_t
set_size(const void *ptr)
{
    const struct set_object *sobj = ptr;
    return (unsigned long)set_memsize(sobj->table);
}

static void
set_compact(void *ptr)
{
    struct set_object *sobj = ptr;
    set_compact_table(sobj->table);
}

static const rb_data_type_t set_data_type = {
    .wrap_struct_name = "set",
    .function = {
        .dmark = set_mark,
        .dfree = set_free,
        .dsize = set_size,
        .dcompact = set_compact,
    },
    .flags = 0
};

static inline set_table *
RSET_TABLE(VALUE set)
{
    struct set_object *sobj;
    TypedData_Get_Struct(set, struct set_object, &set_data_type, sobj);
    return sobj->table;
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
    switch (status) {
      case SET_DELETE:
        return SET_DELETE;
      case SET_CONTINUE:
        break;
      case SET_STOP:
        return SET_STOP;
    }

    return SET_CHECK;
}

static int
set_foreach_iter(set_data_t key, set_data_t argp, int error)
{
    struct set_foreach_arg *arg = (struct set_foreach_arg *)argp;

    if (error) return SET_STOP;

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
                           (set_data_t)arg, (set_data_t)Qundef);
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

static VALUE
set_alloc_with_size(VALUE klass, set_index_t size)
{
    VALUE set;
    struct set_object *sobj;

    set = TypedData_Make_Struct(klass, struct set_object, &set_data_type, sobj);
    sobj->table = set_init_table_with_size(&objhash, size);

    return set;
}


static VALUE
set_s_alloc(VALUE klass)
{
    return set_alloc_with_size(klass, 0);
}

static VALUE
set_s_create(int argc, VALUE *argv, VALUE klass)
{
    VALUE set = set_alloc_with_size(klass, argc);
    set_table *table = RSET_TABLE(set);
    int i;

    for (i=0; i < argc; i++) {
        set_insert(table, (set_data_t)argv[i]);
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
set_initialize_without_block(RB_BLOCK_CALL_FUNC_ARGLIST(i, data))
{
    set_insert((set_table *)data, (set_data_t)i);
    return i;
}

static VALUE
set_initialize_with_block(RB_BLOCK_CALL_FUNC_ARGLIST(i, data))
{
    set_insert((set_table *)data, (set_data_t)rb_yield(i));
    return i;
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
        rb_block_call(other, enum_method_id(other), 0, 0,
            rb_block_given_p() ? set_initialize_with_block : set_initialize_without_block,
            (VALUE)RSET_TABLE(set));
    }

    return set;
}

static VALUE
set_i_initialize_copy(VALUE set, VALUE other)
{
    if (set == other) return set;

    if (set_iterating_p(set)) {
        rb_raise(rb_eRuntimeError, "cannot replace set during iteration");
    }

    struct set_object *sobj;
    TypedData_Get_Struct(set, struct set_object, &set_data_type, sobj);

    set_free_table(sobj->table);
    sobj->table = set_copy(RSET_TABLE(other));
    return set;
}

static int
set_inspect_i(set_data_t key, set_data_t arg)
{
    VALUE str = (VALUE)arg;
    if (RSTRING_LEN(str) > 8) {
        rb_str_buf_cat_ascii(str, ", ");
    }
    rb_str_buf_append(str, rb_inspect((VALUE)key));

    return SET_CONTINUE;
}

static VALUE
set_inspect(VALUE set, VALUE dummy, int recur)
{
    VALUE str;

    if (recur) return rb_usascii_str_new2("#<Set: {...}>");
    str = rb_str_buf_new2("#<Set: {");
    set_iter(set, set_inspect_i, str);
    rb_str_buf_cat2(str, "}>");

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
set_to_a_i(set_data_t key, set_data_t arg)
{
    rb_ary_push((VALUE)arg, (VALUE)key);
    return SET_CONTINUE;
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
    set_index_t size = RSET_SIZE(set);
    VALUE ary = rb_ary_new_capa(size);

    if (size == 0) return ary;

    if (SET_DATA_COMPATIBLE_P(VALUE)) {
        RARRAY_PTR_USE(ary, ptr, {
            size = set_keys(RSET_TABLE(set), ptr, size);
        });
        rb_gc_writebarrier_remember(ary);
        rb_ary_set_len(ary, size);
    }
    else {
        set_iter(set, set_to_a_i, (set_data_t)ary);
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
        if (!set_lookup(RSET_TABLE(set), (set_data_t)item)) {
            no_new_item();
        }
    }
    else {
        set_insert(RSET_TABLE(set), (set_data_t)item);
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
        if (!set_lookup(RSET_TABLE(set), (set_data_t)item)) {
            no_new_item();
        }
        return Qnil;
    }
    else {
        return set_insert(RSET_TABLE(set), (set_data_t)item) ? Qnil : set;
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
    if (set_delete(RSET_TABLE(set), (set_data_t *)&item)) {
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
    if (set_delete(RSET_TABLE(set), (set_data_t *)&item)) {
        set_compact_after_delete(set);
        return set;
    }
    return Qnil;
}

static int
set_delete_if_i(set_data_t key, set_data_t dummy)
{
    return RTEST(rb_yield((VALUE)key)) ? SET_DELETE : SET_CONTINUE;
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
set_classify_i(set_data_t key, set_data_t tmp)
{
    VALUE* args = (VALUE*)tmp;
    VALUE hash = args[0];
    VALUE hash_key = rb_yield(key);
    VALUE set = rb_hash_lookup2(hash, hash_key, Qundef);
    if (set == Qundef) {
        set = rb_funcall(args[1], id_new, 0);
        rb_hash_aset(hash, hash_key, set);
    }
    set_i_add(set, key);

    return SET_CONTINUE;
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
    set_iter(set, set_classify_i, (set_data_t)args);
    return args[0];
}

struct set_divide_args {
    VALUE self;
    VALUE set_class;
    VALUE final_set;
    VALUE hash;
    VALUE current_set;
    VALUE current_item;
    unsigned long ni;
    unsigned long nj;
};

static VALUE
set_divide_block0(RB_BLOCK_CALL_FUNC_ARGLIST(j, arg))
{
    struct set_divide_args *args = (struct set_divide_args *)arg;
    if (args->nj > args->ni) {
        VALUE i = args->current_item;
        if (RTEST(rb_yield_values(2, i, j)) && RTEST(rb_yield_values(2, j, i))) {
            VALUE hash = args->hash;
            if (args->current_set == Qnil) {
                VALUE set = rb_hash_aref(hash, j);
                if (set == Qnil) {
                    VALUE both[2] = {i, j};
                    set = set_s_create(2, both, args->set_class);
                    rb_hash_aset(hash, i, set);
                    rb_hash_aset(hash, j, set);
                    set_i_add(args->final_set, set);
                }
                else {
                    set_i_add(set, i);
                    rb_hash_aset(hash, i, set);
                }
                args->current_set = set;
            }
            else {
                set_i_add(args->current_set, j);
                rb_hash_aset(hash, j, args->current_set);
            }
        }
    }
    args->nj++;
    return j;
}

static VALUE
set_divide_block(RB_BLOCK_CALL_FUNC_ARGLIST(i, arg))
{
    struct set_divide_args *args = (struct set_divide_args *)arg;
    VALUE hash = args->hash;
    args->current_set = rb_hash_aref(hash, i);
    args->current_item = i;
    args->nj = 0;
    rb_block_call(args->self, id_each, 0, 0, set_divide_block0, arg);
    if (args->current_set == Qnil) {
        VALUE set = set_s_create(1, &i, args->set_class);
        rb_hash_aset(hash, i, set);
        set_i_add(args->final_set, set);
    }
    args->ni++;
    return i;
}

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
        VALUE final_set = set_s_create(0, 0, rb_cSet);
        struct set_divide_args args = {
            .self = set,
            .set_class = rb_obj_class(set),
            .final_set = final_set,
            .hash = rb_hash_new(),
            .current_set = 0,
            .current_item = 0,
            .ni = 0,
            .nj = 0
        };
        rb_block_call(set, id_each, 0, 0, set_divide_block, (VALUE)&args);
        return final_set;
    }

    VALUE values = rb_hash_values(set_i_classify(set));
    return rb_funcall(rb_cSet, id_new, 1, values);
}

static int
set_clear_i(set_data_t key, set_data_t dummy)
{
    return SET_DELETE;
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
        set_clear(RSET_TABLE(set));
        set_compact_after_delete(set);
    }
    return set;
}

struct set_intersection_data {
    set_table *into;
    set_table *other;
};

static int
set_intersection_i(set_data_t key, set_data_t tmp)
{
    struct set_intersection_data *data = (struct set_intersection_data *)tmp;
    if (set_lookup(data->other, key)) {
        set_insert(data->into, key);
    }

    return SET_CONTINUE;
}

static VALUE
set_intersection_block(RB_BLOCK_CALL_FUNC_ARGLIST(i, data))
{
    set_intersection_i((set_data_t)i, (set_data_t)data);
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
    VALUE new_set = rb_funcall(rb_obj_class(set), id_new, 0);
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
            .into = ntable,
            .other = otable
        };
        set_iter(set, set_intersection_i, (set_data_t)&data);
    }
    else {
        struct set_intersection_data data = {
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

static int
set_merge_i(set_data_t key, set_data_t into)
{
    set_insert((struct set_table *)into, key);
    return SET_CONTINUE;
}

static VALUE
set_merge_block(RB_BLOCK_CALL_FUNC_ARGLIST(key, set))
{
    rb_check_frozen(set);
    set_insert(RSET_TABLE(set), key);
    return key;
}

static void
set_merge_enum_into(VALUE set, VALUE arg)
{
    if (rb_obj_is_kind_of(arg, rb_cSet)) {
        set_iter(arg, set_merge_i, (set_data_t)RSET_TABLE(set));
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
    rb_check_frozen(set);

    int i;

    for (i=0; i < argc; i++) {
        set_merge_enum_into(set, argv[i]);
    }

    return set;
}

static VALUE
set_reset_table_with_type(VALUE set, const struct set_hash_type *type)
{
    rb_check_frozen(set);

    struct set_object *sobj;
    TypedData_Get_Struct(set, struct set_object, &set_data_type, sobj);
    set_table *old = sobj->table;

    size_t size = set_table_size(old);
    if (size > 0) {
        set_table *new = set_init_table_with_size(type, size);
        set_iter(set, set_merge_i, (set_data_t)new);
        sobj->table = new;
        set_free_table(old);
    }
    else {
        sobj->table->type = type;
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
set_xor_i(set_data_t key, set_data_t into)
{
    if (set_insert((struct set_table *)into, key)) {
        set_delete((struct set_table *)into, &key);
    }
    return SET_CONTINUE;
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
    other = rb_funcall(rb_obj_class(set), id_new, 1, other);
    set_iter(set, set_xor_i, (set_data_t)RSET_TABLE(other));
    return other;
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
set_remove_i(set_data_t key, set_data_t from)
{
    set_delete((struct set_table *)from, (set_data_t *)&key);
    return SET_CONTINUE;
}

static VALUE
set_remove_block(RB_BLOCK_CALL_FUNC_ARGLIST(key, set))
{
    rb_check_frozen(set);
    set_delete(RSET_TABLE(set), (set_data_t *)&key);
    return key;
}

static void
set_remove_enum_from(VALUE set, VALUE arg)
{
    if (rb_obj_is_kind_of(arg, rb_cSet)) {
        set_iter(arg, set_remove_i, (set_data_t)RSET_TABLE(set));
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
set_each_i(set_data_t key, set_data_t dummy)
{
    rb_yield(key);
    return SET_CONTINUE;
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
set_collect_i(set_data_t key, set_data_t into)
{
    set_insert((set_table *)into, rb_yield((VALUE)key));
    return SET_CONTINUE;
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

    VALUE new_set = rb_funcall(rb_obj_class(set), id_new, 0);
    set_iter(set, set_collect_i, (set_data_t)RSET_TABLE(new_set));
    set_i_initialize_copy(set, new_set);

    return set;
}

static int
set_keep_if_i(set_data_t key, set_data_t into)
{
    if (!RTEST(rb_yield((VALUE)key))) {
        set_delete((set_table *)into, &key);
    }
    return SET_CONTINUE;
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

    set_iter(set, set_keep_if_i, (set_data_t)RSET_TABLE(set));

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
    set_iter(set, set_keep_if_i, (set_data_t)table);

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

        set_clear(RSET_TABLE(set));
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
set_flatten_merge_i(set_data_t item, set_data_t arg)
{
    VALUE *args = (VALUE *)arg;
    VALUE set = args[0];
    if (rb_obj_is_kind_of(item, rb_cSet)) {
        VALUE e_id = rb_obj_id(item);
        VALUE hash = args[2];
        switch(rb_hash_aref(hash, e_id)) {
          case Qfalse:
           return SET_CONTINUE;
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
    return SET_CONTINUE;
}

static void
set_flatten_merge(VALUE set, VALUE from, VALUE hash)
{
    VALUE args[3] = {set, from, hash};
    set_iter(from, set_flatten_merge_i, (set_data_t)args);
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
    VALUE new_set = rb_funcall(rb_obj_class(set), id_new, 0);
    set_flatten_merge(new_set, set, rb_hash_new());
    return new_set;
}

static int
set_contains_set_i(set_data_t item, set_data_t arg)
{
    if (rb_obj_is_kind_of(item, rb_cSet)) {
        *(bool *)arg = true;
        return SET_STOP;
    }
    return SET_CONTINUE;
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
    set_iter(set, set_contains_set_i, (set_data_t)&contains_set);
    if (!contains_set) return Qnil;
    rb_check_frozen(set);
    return set_i_replace(set, set_i_flatten(set));
}

struct set_subset_data {
    set_table *table;
    VALUE result;
};

static int
set_le_i(set_data_t key, set_data_t arg)
{
    struct set_subset_data *data = (struct set_subset_data *)arg;
    if (set_lookup(data->table, key)) return SET_CONTINUE;
    data->result = Qfalse;
    return SET_STOP;
}

static VALUE
set_le(VALUE set, VALUE other)
{
    struct set_subset_data data = {
        .table = RSET_TABLE(other),
        .result = Qtrue
    };
    set_iter(set, set_le_i, (set_data_t)&data);
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
set_intersect_i(set_data_t key, set_data_t arg)
{
    VALUE *args = (VALUE *)arg;
    if (set_lookup((set_table *)args[0], key)) {
        args[1] = Qtrue;
        return SET_STOP;
    }
    return SET_CONTINUE;
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
        set_iter(iter_arg, set_intersect_i, (set_data_t)args);
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
set_eql_i(set_data_t item, set_data_t arg)
{
    struct set_equal_data *data = (struct set_equal_data *)arg;

    if (!set_lookup(RSET_TABLE(data->set), item)) {
        data->result = Qfalse;
        return SET_STOP;
    }
    return SET_CONTINUE;
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
set_hash_i(set_data_t item, set_data_t(arg))
{
    set_index_t *hval = (set_index_t *)arg;
    set_index_t ival = rb_hash(item);
    *hval ^= set_hash(&ival, sizeof(set_index_t), 0);
    return SET_CONTINUE;
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
    set_index_t size = RSET_SIZE(set);
    set_index_t hval = set_hash_start(size);
    hval = rb_hash_uint(hval, (set_index_t)set_i_hash);
    if (size) {
        set_iter(set, set_hash_i, (VALUE)&hval);
    }
    hval = set_hash_end(hval);
    return ST2FIX(hval);
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

    rb_provide("set.rb");
}
