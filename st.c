/* This is a public domain general purpose hash table package
   originally written by Peter Moore @ UCB.

   The hash table data structures were redesigned and the package was
   rewritten by Vladimir Makarov <vmakarov@redhat.com>.  */

/* The original package implemented classic bucket-based hash tables
   with entries doubly linked for an access by their insertion order.
   To decrease pointer chasing and as a consequence to improve a data
   locality the current implementation is based on storing entries in
   an array and using hash tables with open addressing.  The current
   entries are more compact in comparison with the original ones and
   this also improves the data locality.

   The hash table has two arrays called *bins* and *entries*.

     bins:
    -------
   |       |                  entries array:
   |-------|            --------------------------------
   | index |           |      | entry:  |        |      |
   |-------|           |      |         |        |      |
   | ...   |           | ...  | hash    |  ...   | ...  |
   |-------|           |      | key     |        |      |
   | empty |           |      | record  |        |      |
   |-------|            --------------------------------
   | ...   |                   ^                  ^
   |-------|                   |_ entries start   |_ entries bound
   |deleted|
    -------

   o The entry array contains table entries in the same order as they
     were inserted.

     When the first entry is deleted, a variable containing index of
     the current first entry (*entries start*) is changed.  In all
     other cases of the deletion, we just mark the entry as deleted by
     using a reserved hash value.

     Such organization of the entry storage makes operations of the
     table shift and the entries traversal very fast.

   o The bins provide access to the entries by their keys.  The
     key hash is mapped to a bin containing *index* of the
     corresponding entry in the entry array.

     The bin array size is always power of two, it makes mapping very
     fast by using the corresponding lower bits of the hash.
     Generally it is not a good idea to ignore some part of the hash.
     But alternative approach is worse.  For example, we could use a
     modulo operation for mapping and a prime number for the size of
     the bin array.  Unfortunately, the modulo operation for big
     64-bit numbers are extremely slow (it takes more than 100 cycles
     on modern Intel CPUs).

     Still other bits of the hash value are used when the mapping
     results in a collision.  In this case we use a secondary hash
     value which is a result of a function of the collision bin
     index and the original hash value.  The function choice
     guarantees that we can traverse all bins and finally find the
     corresponding bin as after several iterations the function
     becomes a full cycle linear congruential generator because it
     satisfies requirements of the Hull-Dobell theorem.

     When an entry is removed from the table besides marking the
     hash in the corresponding entry described above, we also mark
     the bin by a special value in order to find entries which had
     a collision with the removed entries.

     There are two reserved values for the bins.  One denotes an
     empty bin, another one denotes a bin for a deleted entry.

   o The length of the bin array is at least two times more than the
     entry array length.  This keeps the table load factor healthy.
     The trigger of rebuilding the table is always a case when we can
     not insert an entry anymore at the entries bound.  We could
     change the entries bound too in case of deletion but than we need
     a special code to count bins with corresponding deleted entries
     and reset the bin values when there are too many bins
     corresponding deleted entries

     Table rebuilding is done by creation of a new entry array and
     bins of an appropriate size.  We also try to reuse the arrays
     in some cases by compacting the array and removing deleted
     entries.

   o To save memory very small tables have no allocated arrays
     bins.  We use a linear search for an access by a key.

   o To save more memory we use 8-, 16-, 32- and 64- bit indexes in
     bins depending on the current hash table size.

   o The implementation takes into account that the table can be
     rebuilt during hashing or comparison functions.  It can happen if
     the functions are implemented in Ruby and a thread switch occurs
     during their execution.

   This implementation speeds up the Ruby hash table benchmarks in
   average by more 40% on Intel Haswell CPU.

*/

#ifdef NOT_RUBY
#include "regint.h"
#include "st.h"
#include <assert.h>
#elif defined RUBY_EXPORT
#include "internal.h"
#include "internal/bits.h"
#include "internal/hash.h"
#include "internal/sanitizers.h"
#include "internal/st.h"
#include "ruby_assert.h"
#endif

#include <stdio.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <string.h>

#ifdef __GNUC__
#define PREFETCH(addr, write_p) __builtin_prefetch(addr, write_p)
#define EXPECT(expr, val) __builtin_expect(expr, val)
#define ATTRIBUTE_UNUSED  __attribute__((unused))
#else
#define PREFETCH(addr, write_p)
#define EXPECT(expr, val) (expr)
#define ATTRIBUTE_UNUSED
#endif

/* The type of hashes.  */
typedef st_index_t st_hash_t;

struct st_table_entry {
    st_hash_t hash;
    st_data_t key;
    st_data_t record;
};

#define type_numhash st_hashtype_num
static const struct st_hash_type st_hashtype_num = {
    st_numcmp,
    st_numhash,
};

static int st_strcmp(st_data_t, st_data_t);
static st_index_t strhash(st_data_t);
static const struct st_hash_type type_strhash = {
    st_strcmp,
    strhash,
};

static int st_locale_insensitive_strcasecmp_i(st_data_t lhs, st_data_t rhs);
static st_index_t strcasehash(st_data_t);
static const struct st_hash_type type_strcasehash = {
    st_locale_insensitive_strcasecmp_i,
    strcasehash,
};

/* Value used to catch uninitialized entries/bins during debugging.
   There is a possibility for a false alarm, but its probability is
   extremely small.  */
#define ST_INIT_VAL 0xafafafafafafafaf
#define ST_INIT_VAL_BYTE 0xafa

#ifdef RUBY
#undef malloc
#undef realloc
#undef calloc
#undef free
#define malloc ruby_xmalloc
#define calloc ruby_xcalloc
#define realloc ruby_xrealloc
#define free ruby_xfree
#endif

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
struct st_features {
    /* Power of 2 used for number of allocated entries.  */
    unsigned char entry_power;
    /* Power of 2 used for number of allocated bins.  Depending on the
       table size, the number of bins is 2-4 times more than the
       number of entries.  */
    unsigned char bin_power;
    /* Enumeration of sizes of bins (8-bit, 16-bit etc).  */
    unsigned char size_ind;
    /* Bins are packed in words of type st_index_t.  The following is
       a size of bins counted by words.  */
    st_index_t bins_words;
};

/* Features of all possible size tables.  */
#if SIZEOF_ST_INDEX_T == 8
#define MAX_POWER2 62
static const struct st_features features[] = {
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

static const struct st_features features[] = {
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
#define RESERVED_HASH_VAL (~(st_hash_t) 0)
#define RESERVED_HASH_SUBSTITUTION_VAL ((st_hash_t) 0)

static inline st_hash_t
normalize_hash_value(st_hash_t hash)
{
    /* RESERVED_HASH_VAL is used for a deleted entry.  Map it into
       another value.  Such mapping should be extremely rare.  */
    return hash == RESERVED_HASH_VAL ? RESERVED_HASH_SUBSTITUTION_VAL : hash;
}

/* Return hash value of KEY for table TAB.  */
static inline st_hash_t
do_hash(st_data_t key, st_table *tab)
{
    st_hash_t hash = (st_hash_t)(tab->type->hash)(key);
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
get_power2(st_index_t size)
{
    unsigned int n = ST_INDEX_BITS - nlz_intptr(size);
    if (n <= MAX_POWER2)
        return n < MINIMAL_POWER2 ? MINIMAL_POWER2 : n;
#ifdef RUBY
    /* Ran out of the table entries */
    rb_raise(rb_eRuntimeError, "st_table too big");
#endif
    /* should raise exception */
    return -1;
}

/* Return value of N-th bin in array BINS of table with bins size
   index S.  */
static inline st_index_t
get_bin(st_index_t *bins, int s, st_index_t n)
{
    return (s == 0 ? ((unsigned char *) bins)[n]
            : s == 1 ? ((unsigned short *) bins)[n]
            : s == 2 ? ((unsigned int *) bins)[n]
            : ((st_index_t *) bins)[n]);
}

/* Set up N-th bin in array BINS of table with bins size index S to
   value V.  */
static inline void
set_bin(st_index_t *bins, int s, st_index_t n, st_index_t v)
{
    if (s == 0) ((unsigned char *) bins)[n] = (unsigned char) v;
    else if (s == 1) ((unsigned short *) bins)[n] = (unsigned short) v;
    else if (s == 2) ((unsigned int *) bins)[n] = (unsigned int) v;
    else ((st_index_t *) bins)[n] = v;
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
#define UNDEFINED_ENTRY_IND (~(st_index_t) 0)
#define UNDEFINED_BIN_IND (~(st_index_t) 0)

/* Entry and bin values returned when we found a table rebuild during
   the search.  */
#define REBUILT_TABLE_ENTRY_IND (~(st_index_t) 1)
#define REBUILT_TABLE_BIN_IND (~(st_index_t) 1)

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
get_size_ind(const st_table *tab)
{
    return tab->size_ind;
}

/* Return the number of allocated bins of table TAB.  */
static inline st_index_t
get_bins_num(const st_table *tab)
{
    return ((st_index_t) 1)<<tab->bin_power;
}

/* Return mask for a bin index in table TAB.  */
static inline st_index_t
bins_mask(const st_table *tab)
{
    return get_bins_num(tab) - 1;
}

/* Return the index of table TAB bin corresponding to
   HASH_VALUE.  */
static inline st_index_t
hash_bin(st_hash_t hash_value, st_table *tab)
{
    return hash_value & bins_mask(tab);
}

/* Return the number of allocated entries of table TAB.  */
static inline st_index_t
get_allocated_entries(const st_table *tab)
{
    return ((st_index_t) 1)<<tab->entry_power;
}

/* Return size of the allocated bins of table TAB.  */
static inline st_index_t
bins_size(const st_table *tab)
{
    return features[tab->entry_power].bins_words * sizeof (st_index_t);
}

/* Mark all bins of table TAB as empty.  */
static void
initialize_bins(st_table *tab)
{
    memset(tab->bins, 0, bins_size(tab));
}

/* Make table TAB empty.  */
static void
make_tab_empty(st_table *tab)
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

st_table *
st_init_existing_table_with_size(st_table *tab, const struct st_hash_type *type, st_index_t size)
{
    int n;

#ifdef HASH_LOG
#if HASH_LOG+0 < 0
    {
        const char *e = getenv("ST_HASH_LOG");
        if (!e || !*e) init_st = 1;
    }
#endif
    if (init_st == 0) {
        init_st = 1;
        atexit(stat_col);
    }
#endif

    n = get_power2(size);
#ifndef RUBY
    if (n < 0)
        return NULL;
#endif

    tab->type = type;
    tab->entry_power = n;
    tab->bin_power = features[n].bin_power;
    tab->size_ind = features[n].size_ind;
    if (n <= MAX_POWER2_FOR_TABLES_WITHOUT_BINS)
        tab->bins = NULL;
    else {
        tab->bins = (st_index_t *) malloc(bins_size(tab));
#ifndef RUBY
        if (tab->bins == NULL) {
            free(tab);
            return NULL;
        }
#endif
    }
    tab->entries = (st_table_entry *) malloc(get_allocated_entries(tab)
                                             * sizeof(st_table_entry));
#ifndef RUBY
    if (tab->entries == NULL) {
        st_free_table(tab);
        return NULL;
    }
#endif
    make_tab_empty(tab);
    tab->rebuilds_num = 0;
    return tab;
}

/* Create and return table with TYPE which can hold at least SIZE
   entries.  The real number of entries which the table can hold is
   the nearest power of two for SIZE.  */
st_table *
st_init_table_with_size(const struct st_hash_type *type, st_index_t size)
{
    st_table *tab = malloc(sizeof(st_table));
#ifndef RUBY
    if (tab == NULL)
        return NULL;
#endif

#ifdef RUBY
    st_init_existing_table_with_size(tab, type, size);
#else
    if (st_init_existing_table_with_size(tab, type, size) == NULL) {
        free(tab);
        return NULL;
    }
#endif

    return tab;
}

size_t
st_table_size(const struct st_table *tbl)
{
    return tbl->num_entries;
}

/* Create and return table with TYPE which can hold a minimal number
   of entries (see comments for get_power2).  */
st_table *
st_init_table(const struct st_hash_type *type)
{
    return st_init_table_with_size(type, 0);
}

/* Create and return table which can hold a minimal number of
   numbers.  */
st_table *
st_init_numtable(void)
{
    return st_init_table(&type_numhash);
}

/* Create and return table which can hold SIZE numbers.  */
st_table *
st_init_numtable_with_size(st_index_t size)
{
    return st_init_table_with_size(&type_numhash, size);
}

/* Create and return table which can hold a minimal number of
   strings.  */
st_table *
st_init_strtable(void)
{
    return st_init_table(&type_strhash);
}

/* Create and return table which can hold SIZE strings.  */
st_table *
st_init_strtable_with_size(st_index_t size)
{
    return st_init_table_with_size(&type_strhash, size);
}

/* Create and return table which can hold a minimal number of strings
   whose character case is ignored.  */
st_table *
st_init_strcasetable(void)
{
    return st_init_table(&type_strcasehash);
}

/* Create and return table which can hold SIZE strings whose character
   case is ignored.  */
st_table *
st_init_strcasetable_with_size(st_index_t size)
{
    return st_init_table_with_size(&type_strcasehash, size);
}

/* Make table TAB empty.  */
void
st_clear(st_table *tab)
{
    make_tab_empty(tab);
    tab->rebuilds_num++;
}

/* Free table TAB space.  */
void
st_free_table(st_table *tab)
{
    free(tab->bins);
    free(tab->entries);
    free(tab);
}

/* Return byte size of memory allocated for table TAB.  */
size_t
st_memsize(const st_table *tab)
{
    return(sizeof(st_table)
           + (tab->bins == NULL ? 0 : bins_size(tab))
           + get_allocated_entries(tab) * sizeof(st_table_entry));
}

static st_index_t
find_table_entry_ind(st_table *tab, st_hash_t hash_value, st_data_t key);

static st_index_t
find_table_bin_ind(st_table *tab, st_hash_t hash_value, st_data_t key);

static st_index_t
find_table_bin_ind_direct(st_table *table, st_hash_t hash_value, st_data_t key);

static st_index_t
find_table_bin_ptr_and_reserve(st_table *tab, st_hash_t *hash_value,
                               st_data_t key, st_index_t *bin_ind);

#ifdef HASH_LOG
static void
count_collision(const struct st_hash_type *type)
{
    collision.all++;
    if (type == &type_numhash) {
        collision.num++;
    }
    else if (type == &type_strhash) {
        collision.strcase++;
    }
    else if (type == &type_strcasehash) {
        collision.str++;
    }
}

#define COLLISION (collision_check ? count_collision(tab->type) : (void)0)
#define FOUND_BIN (collision_check ? collision.total++ : (void)0)
#define collision_check 0
#else
#define COLLISION
#define FOUND_BIN
#endif

/* If the number of entries in the table is at least REBUILD_THRESHOLD
   times less than the entry array length, decrease the table
   size.  */
#define REBUILD_THRESHOLD 4

#if REBUILD_THRESHOLD < 2
#error "REBUILD_THRESHOLD should be >= 2"
#endif

static void rebuild_table_with(st_table *const new_tab, st_table *const tab);
static void rebuild_move_table(st_table *const new_tab, st_table *const tab);
static void rebuild_cleanup(st_table *const tab);

/* Rebuild table TAB.  Rebuilding removes all deleted bins and entries
   and can change size of the table entries and bins arrays.
   Rebuilding is implemented by creation of a new table or by
   compaction of the existing one.  */
static void
rebuild_table(st_table *tab)
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
        st_table *new_tab;
        /* This allocation could trigger GC and compaction. If tab is the
         * gen_iv_tbl, then tab could have changed in size due to objects being
         * freed and/or moved. Do not store attributes of tab before this line. */
        new_tab = st_init_table_with_size(tab->type,
                                          2 * tab->num_entries - 1);
        rebuild_table_with(new_tab, tab);
        rebuild_move_table(new_tab, tab);
    }
    rebuild_cleanup(tab);
}

static void
rebuild_table_with(st_table *const new_tab, st_table *const tab)
{
    st_index_t i, ni;
    unsigned int size_ind;
    st_table_entry *new_entries;
    st_table_entry *curr_entry_ptr;
    st_index_t *bins;
    st_index_t bin_ind;

    new_entries = new_tab->entries;

    ni = 0;
    bins = new_tab->bins;
    size_ind = get_size_ind(new_tab);
    st_index_t bound = tab->entries_bound;
    st_table_entry *entries = tab->entries;

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
rebuild_move_table(st_table *const new_tab, st_table *const tab)
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
rebuild_cleanup(st_table *const tab)
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
static inline st_index_t
secondary_hash(st_index_t ind, st_table *tab, st_index_t *perturb)
{
    *perturb >>= 11;
    ind = (ind << 2) + ind + *perturb + 1;
    return hash_bin(ind, tab);
}

/* Find an entry with HASH_VALUE and KEY in TABLE using a linear
   search.  Return the index of the found entry in array `entries`.
   If it is not found, return UNDEFINED_ENTRY_IND.  If the table was
   rebuilt during the search, return REBUILT_TABLE_ENTRY_IND.  */
static inline st_index_t
find_entry(st_table *tab, st_hash_t hash_value, st_data_t key)
{
    int eq_p, rebuilt_p;
    st_index_t i, bound;
    st_table_entry *entries;

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
static st_index_t
find_table_entry_ind(st_table *tab, st_hash_t hash_value, st_data_t key)
{
    int eq_p, rebuilt_p;
    st_index_t ind;
#ifdef QUADRATIC_PROBE
    st_index_t d;
#else
    st_index_t perturb;
#endif
    st_index_t bin;
    st_table_entry *entries = tab->entries;

    ind = hash_bin(hash_value, tab);
#ifdef QUADRATIC_PROBE
    d = 1;
#else
    perturb = hash_value;
#endif
    FOUND_BIN;
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
        COLLISION;
    }
    return bin;
}

/* Find and return index of table TAB bin corresponding to an entry
   with HASH_VALUE and KEY.  If there is no such bin, return
   UNDEFINED_BIN_IND.  If the table was rebuilt during the search,
   return REBUILT_TABLE_BIN_IND.  */
static st_index_t
find_table_bin_ind(st_table *tab, st_hash_t hash_value, st_data_t key)
{
    int eq_p, rebuilt_p;
    st_index_t ind;
#ifdef QUADRATIC_PROBE
    st_index_t d;
#else
    st_index_t perturb;
#endif
    st_index_t bin;
    st_table_entry *entries = tab->entries;

    ind = hash_bin(hash_value, tab);
#ifdef QUADRATIC_PROBE
    d = 1;
#else
    perturb = hash_value;
#endif
    FOUND_BIN;
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
        COLLISION;
    }
    return ind;
}

/* Find and return index of table TAB bin corresponding to an entry
   with HASH_VALUE and KEY.  The entry should be in the table
   already.  */
static st_index_t
find_table_bin_ind_direct(st_table *tab, st_hash_t hash_value, st_data_t key)
{
    st_index_t ind;
#ifdef QUADRATIC_PROBE
    st_index_t d;
#else
    st_index_t perturb;
#endif
    st_index_t bin;

    ind = hash_bin(hash_value, tab);
#ifdef QUADRATIC_PROBE
    d = 1;
#else
    perturb = hash_value;
#endif
    FOUND_BIN;
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
        COLLISION;
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
static st_index_t
find_table_bin_ptr_and_reserve(st_table *tab, st_hash_t *hash_value,
                               st_data_t key, st_index_t *bin_ind)
{
    int eq_p, rebuilt_p;
    st_index_t ind;
    st_hash_t curr_hash_value = *hash_value;
#ifdef QUADRATIC_PROBE
    st_index_t d;
#else
    st_index_t perturb;
#endif
    st_index_t entry_index;
    st_index_t first_deleted_bin_ind;
    st_table_entry *entries;

    ind = hash_bin(curr_hash_value, tab);
#ifdef QUADRATIC_PROBE
    d = 1;
#else
    perturb = curr_hash_value;
#endif
    FOUND_BIN;
    first_deleted_bin_ind = UNDEFINED_BIN_IND;
    entries = tab->entries;
    for (;;) {
        entry_index = get_bin(tab->bins, get_size_ind(tab), ind);
        if (EMPTY_BIN_P(entry_index)) {
            tab->num_entries++;
            entry_index = UNDEFINED_ENTRY_IND;
            if (first_deleted_bin_ind != UNDEFINED_BIN_IND) {
                /* We can reuse bin of a deleted entry.  */
                ind = first_deleted_bin_ind;
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
        else if (first_deleted_bin_ind == UNDEFINED_BIN_IND)
            first_deleted_bin_ind = ind;
#ifdef QUADRATIC_PROBE
        ind = hash_bin(ind + d, tab);
        d++;
#else
        ind = secondary_hash(ind, tab, &perturb);
#endif
        COLLISION;
    }
    *bin_ind = ind;
    return entry_index;
}

/* Find an entry with KEY in table TAB.  Return non-zero if we found
   it.  Set up *RECORD to the found entry record.  */
int
st_lookup(st_table *tab, st_data_t key, st_data_t *value)
{
    st_index_t bin;
    st_hash_t hash = do_hash(key, tab);

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
    if (value != 0)
        *value = tab->entries[bin].record;
    return 1;
}

/* Find an entry with KEY in table TAB.  Return non-zero if we found
   it.  Set up *RESULT to the found table entry key.  */
int
st_get_key(st_table *tab, st_data_t key, st_data_t *result)
{
    st_index_t bin;
    st_hash_t hash = do_hash(key, tab);

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
    if (result != 0)
        *result = tab->entries[bin].key;
    return 1;
}

/* Check the table and rebuild it if it is necessary.  */
static inline void
rebuild_table_if_necessary (st_table *tab)
{
    st_index_t bound = tab->entries_bound;

    if (bound == get_allocated_entries(tab))
        rebuild_table(tab);
}

/* Insert (KEY, VALUE) into table TAB and return zero.  If there is
   already entry with KEY in the table, return nonzero and update
   the value of the found entry.  */
int
st_insert(st_table *tab, st_data_t key, st_data_t value)
{
    st_table_entry *entry;
    st_index_t bin;
    st_index_t ind;
    st_hash_t hash_value;
    st_index_t bin_ind;
    int new_p;

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
        entry->record = value;
        if (bin_ind != UNDEFINED_BIN_IND)
            set_bin(tab->bins, get_size_ind(tab), bin_ind, ind + ENTRY_BASE);
        return 0;
    }
    tab->entries[bin].record = value;
    return 1;
}

/* Insert (KEY, VALUE, HASH) into table TAB.  The table should not have
   entry with KEY before the insertion.  */
static inline void
st_add_direct_with_hash(st_table *tab,
                        st_data_t key, st_data_t value, st_hash_t hash)
{
    st_table_entry *entry;
    st_index_t ind;
    st_index_t bin_ind;

    assert(hash != RESERVED_HASH_VAL);

    rebuild_table_if_necessary(tab);
    ind = tab->entries_bound++;
    entry = &tab->entries[ind];
    entry->hash = hash;
    entry->key = key;
    entry->record = value;
    tab->num_entries++;
    if (tab->bins != NULL) {
        bin_ind = find_table_bin_ind_direct(tab, hash, key);
        set_bin(tab->bins, get_size_ind(tab), bin_ind, ind + ENTRY_BASE);
    }
}

void
rb_st_add_direct_with_hash(st_table *tab,
                           st_data_t key, st_data_t value, st_hash_t hash)
{
    st_add_direct_with_hash(tab, key, value, normalize_hash_value(hash));
}

/* Insert (KEY, VALUE) into table TAB.  The table should not have
   entry with KEY before the insertion.  */
void
st_add_direct(st_table *tab, st_data_t key, st_data_t value)
{
    st_hash_t hash_value;

    hash_value = do_hash(key, tab);
    st_add_direct_with_hash(tab, key, value, hash_value);
}

/* Insert (FUNC(KEY), VALUE) into table TAB and return zero.  If
   there is already entry with KEY in the table, return nonzero and
   update the value of the found entry.  */
int
st_insert2(st_table *tab, st_data_t key, st_data_t value,
           st_data_t (*func)(st_data_t))
{
    st_table_entry *entry;
    st_index_t bin;
    st_index_t ind;
    st_hash_t hash_value;
    st_index_t bin_ind;
    int new_p;

    hash_value = do_hash(key, tab);
 retry:
    rebuild_table_if_necessary (tab);
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
        key = (*func)(key);
        ind = tab->entries_bound++;
        entry = &tab->entries[ind];
        entry->hash = hash_value;
        entry->key = key;
        entry->record = value;
        if (bin_ind != UNDEFINED_BIN_IND)
            set_bin(tab->bins, get_size_ind(tab), bin_ind, ind + ENTRY_BASE);
        return 0;
    }
    tab->entries[bin].record = value;
    return 1;
}

/* Create a copy of old_tab into new_tab. */
st_table *
st_replace(st_table *new_tab, st_table *old_tab)
{
    *new_tab = *old_tab;
    if (old_tab->bins == NULL)
        new_tab->bins = NULL;
    else {
        new_tab->bins = (st_index_t *) malloc(bins_size(old_tab));
#ifndef RUBY
        if (new_tab->bins == NULL) {
            return NULL;
        }
#endif
    }
    new_tab->entries = (st_table_entry *) malloc(get_allocated_entries(old_tab)
                                                 * sizeof(st_table_entry));
#ifndef RUBY
    if (new_tab->entries == NULL) {
        return NULL;
    }
#endif
    MEMCPY(new_tab->entries, old_tab->entries, st_table_entry,
           get_allocated_entries(old_tab));
    if (old_tab->bins != NULL)
        MEMCPY(new_tab->bins, old_tab->bins, char, bins_size(old_tab));

    return new_tab;
}

/* Create and return a copy of table OLD_TAB.  */
st_table *
st_copy(st_table *old_tab)
{
    st_table *new_tab;

    new_tab = (st_table *) malloc(sizeof(st_table));
#ifndef RUBY
    if (new_tab == NULL)
        return NULL;
#endif

    if (st_replace(new_tab, old_tab) == NULL) {
        st_free_table(new_tab);
        return NULL;
    }

    return new_tab;
}

/* Update the entries start of table TAB after removing an entry
   with index N in the array entries.  */
static inline void
update_range_for_deleted(st_table *tab, st_index_t n)
{
    /* Do not update entries_bound here.  Otherwise, we can fill all
       bins by deleted entry value before rebuilding the table.  */
    if (tab->entries_start == n) {
        st_index_t start = n + 1;
        st_index_t bound = tab->entries_bound;
        st_table_entry *entries = tab->entries;
        while (start < bound && DELETED_ENTRY_P(&entries[start])) start++;
        tab->entries_start = start;
    }
}

/* Delete entry with KEY from table TAB, set up *VALUE (unless
   VALUE is zero) from deleted table entry, and return non-zero.  If
   there is no entry with KEY in the table, clear *VALUE (unless VALUE
   is zero), and return zero.  */
static int
st_general_delete(st_table *tab, st_data_t *key, st_data_t *value)
{
    st_table_entry *entry;
    st_index_t bin;
    st_index_t bin_ind;
    st_hash_t hash;

    hash = do_hash(*key, tab);
 retry:
    if (tab->bins == NULL) {
        bin = find_entry(tab, hash, *key);
        if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0))
            goto retry;
        if (bin == UNDEFINED_ENTRY_IND) {
            if (value != 0) *value = 0;
            return 0;
        }
    }
    else {
        bin_ind = find_table_bin_ind(tab, hash, *key);
        if (EXPECT(bin_ind == REBUILT_TABLE_BIN_IND, 0))
            goto retry;
        if (bin_ind == UNDEFINED_BIN_IND) {
            if (value != 0) *value = 0;
            return 0;
        }
        bin = get_bin(tab->bins, get_size_ind(tab), bin_ind) - ENTRY_BASE;
        MARK_BIN_DELETED(tab, bin_ind);
    }
    entry = &tab->entries[bin];
    *key = entry->key;
    if (value != 0) *value = entry->record;
    MARK_ENTRY_DELETED(entry);
    tab->num_entries--;
    update_range_for_deleted(tab, bin);
    return 1;
}

int
st_delete(st_table *tab, st_data_t *key, st_data_t *value)
{
    return st_general_delete(tab, key, value);
}

/* The function and other functions with suffix '_safe' or '_check'
   are originated from the previous implementation of the hash tables.
   It was necessary for correct deleting entries during traversing
   tables.  The current implementation permits deletion during
   traversing without a specific way to do this.  */
int
st_delete_safe(st_table *tab, st_data_t *key, st_data_t *value,
               st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_delete(tab, key, value);
}

/* If table TAB is empty, clear *VALUE (unless VALUE is zero), and
   return zero.  Otherwise, remove the first entry in the table.
   Return its key through KEY and its record through VALUE (unless
   VALUE is zero).  */
int
st_shift(st_table *tab, st_data_t *key, st_data_t *value)
{
    st_index_t i, bound;
    st_index_t bin;
    st_table_entry *entries, *curr_entry_ptr;
    st_index_t bin_ind;

    entries = tab->entries;
    bound = tab->entries_bound;
    for (i = tab->entries_start; i < bound; i++) {
        curr_entry_ptr = &entries[i];
        if (! DELETED_ENTRY_P(curr_entry_ptr)) {
            st_hash_t entry_hash = curr_entry_ptr->hash;
            st_data_t entry_key = curr_entry_ptr->key;

            if (value != 0) *value = curr_entry_ptr->record;
            *key = entry_key;
        retry:
            if (tab->bins == NULL) {
                bin = find_entry(tab, entry_hash, entry_key);
                if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0)) {
                    entries = tab->entries;
                    goto retry;
                }
                curr_entry_ptr = &entries[bin];
            }
            else {
                bin_ind = find_table_bin_ind(tab, entry_hash, entry_key);
                if (EXPECT(bin_ind == REBUILT_TABLE_BIN_IND, 0)) {
                    entries = tab->entries;
                    goto retry;
                }
                curr_entry_ptr = &entries[get_bin(tab->bins, get_size_ind(tab), bin_ind)
                                          - ENTRY_BASE];
                MARK_BIN_DELETED(tab, bin_ind);
            }
            MARK_ENTRY_DELETED(curr_entry_ptr);
            tab->num_entries--;
            update_range_for_deleted(tab, i);
            return 1;
        }
    }
    if (value != 0) *value = 0;
    return 0;
}

/* See comments for function st_delete_safe.  */
void
st_cleanup_safe(st_table *tab ATTRIBUTE_UNUSED,
                st_data_t never ATTRIBUTE_UNUSED)
{
}

/* Find entry with KEY in table TAB, call FUNC with pointers to copies
   of the key and the value of the found entry, and non-zero as the
   3rd argument.  If the entry is not found, call FUNC with a pointer
   to KEY, a pointer to zero, and a zero argument.  If the call
   returns ST_CONTINUE, the table will have an entry with key and
   value returned by FUNC through the 1st and 2nd parameters.  If the
   call of FUNC returns ST_DELETE, the table will not have entry with
   KEY.  The function returns flag of that the entry with KEY was in
   the table before the call.  */
int
st_update(st_table *tab, st_data_t key,
          st_update_callback_func *func, st_data_t arg)
{
    st_table_entry *entry = NULL; /* to avoid uninitialized value warning */
    st_index_t bin = 0; /* Ditto */
    st_table_entry *entries;
    st_index_t bin_ind;
    st_data_t value = 0, old_key;
    int retval, existing;
    st_hash_t hash = do_hash(key, tab);

 retry:
    entries = tab->entries;
    if (tab->bins == NULL) {
        bin = find_entry(tab, hash, key);
        if (EXPECT(bin == REBUILT_TABLE_ENTRY_IND, 0))
            goto retry;
        existing = bin != UNDEFINED_ENTRY_IND;
        entry = &entries[bin];
        bin_ind = UNDEFINED_BIN_IND;
    }
    else {
        bin_ind = find_table_bin_ind(tab, hash, key);
        if (EXPECT(bin_ind == REBUILT_TABLE_BIN_IND, 0))
            goto retry;
        existing = bin_ind != UNDEFINED_BIN_IND;
        if (existing) {
            bin = get_bin(tab->bins, get_size_ind(tab), bin_ind) - ENTRY_BASE;
            entry = &entries[bin];
        }
    }
    if (existing) {
        key = entry->key;
        value = entry->record;
    }
    old_key = key;
    retval = (*func)(&key, &value, arg, existing);
    switch (retval) {
      case ST_CONTINUE:
        if (! existing) {
            st_add_direct_with_hash(tab, key, value, hash);
            break;
        }
        if (old_key != key) {
            entry->key = key;
        }
        entry->record = value;
        break;
      case ST_DELETE:
        if (existing) {
            if (bin_ind != UNDEFINED_BIN_IND)
                MARK_BIN_DELETED(tab, bin_ind);
            MARK_ENTRY_DELETED(entry);
            tab->num_entries--;
            update_range_for_deleted(tab, bin);
        }
        break;
    }
    return existing;
}

/* Traverse all entries in table TAB calling FUNC with current entry
   key and value and zero.  If the call returns ST_STOP, stop
   traversing.  If the call returns ST_DELETE, delete the current
   entry from the table.  In case of ST_CHECK or ST_CONTINUE, continue
   traversing.  The function returns zero unless an error is found.
   CHECK_P is flag of st_foreach_check call.  The behavior is a bit
   different for ST_CHECK and when the current element is removed
   during traversing.  */
static inline int
st_general_foreach(st_table *tab, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg,
                   int check_p)
{
    st_index_t bin;
    st_index_t bin_ind;
    st_table_entry *entries, *curr_entry_ptr;
    enum st_retval retval;
    st_index_t i, rebuilds_num;
    st_hash_t hash;
    st_data_t key;
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
        retval = (*func)(key, curr_entry_ptr->record, arg, 0);

        if (retval == ST_REPLACE && replace) {
            st_data_t value;
            value = curr_entry_ptr->record;
            retval = (*replace)(&key, &value, arg, TRUE);
            curr_entry_ptr->key = key;
            curr_entry_ptr->record = value;
        }

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
                retval = (*func)(0, 0, arg, 1);
                return 1;
            }
            curr_entry_ptr = &entries[i];
        }
        switch (retval) {
          case ST_REPLACE:
            break;
          case ST_CONTINUE:
            break;
          case ST_CHECK:
            if (check_p)
                break;
          case ST_STOP:
            return 0;
          case ST_DELETE: {
            st_data_t key = curr_entry_ptr->key;

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

int
st_foreach_with_replace(st_table *tab, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg)
{
    return st_general_foreach(tab, func, replace, arg, TRUE);
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

int
st_foreach(st_table *tab, st_foreach_callback_func *func, st_data_t arg)
{
    const struct functor f = { func, arg };
    return st_general_foreach(tab, apply_functor, 0, (st_data_t)&f, FALSE);
}

/* See comments for function st_delete_safe.  */
int
st_foreach_check(st_table *tab, st_foreach_check_callback_func *func, st_data_t arg,
                 st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_foreach(tab, func, 0, arg, TRUE);
}

/* Set up array KEYS by at most SIZE keys of head table TAB entries.
   Return the number of keys set up in array KEYS.  */
static inline st_index_t
st_general_keys(st_table *tab, st_data_t *keys, st_index_t size)
{
    st_index_t i, bound;
    st_data_t key, *keys_start, *keys_end;
    st_table_entry *curr_entry_ptr, *entries = tab->entries;

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

st_index_t
st_keys(st_table *tab, st_data_t *keys, st_index_t size)
{
    return st_general_keys(tab, keys, size);
}

/* See comments for function st_delete_safe.  */
st_index_t
st_keys_check(st_table *tab, st_data_t *keys, st_index_t size,
              st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_keys(tab, keys, size);
}

/* Set up array VALUES by at most SIZE values of head table TAB
   entries.  Return the number of values set up in array VALUES.  */
static inline st_index_t
st_general_values(st_table *tab, st_data_t *values, st_index_t size)
{
    st_index_t i, bound;
    st_data_t *values_start, *values_end;
    st_table_entry *curr_entry_ptr, *entries = tab->entries;

    values_start = values;
    values_end = values + size;
    bound = tab->entries_bound;
    for (i = tab->entries_start; i < bound; i++) {
        if (values == values_end)
            break;
        curr_entry_ptr = &entries[i];
        if (! DELETED_ENTRY_P(curr_entry_ptr))
            *values++ = curr_entry_ptr->record;
    }

    return values - values_start;
}

st_index_t
st_values(st_table *tab, st_data_t *values, st_index_t size)
{
    return st_general_values(tab, values, size);
}

/* See comments for function st_delete_safe.  */
st_index_t
st_values_check(st_table *tab, st_data_t *values, st_index_t size,
                st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_values(tab, values, size);
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
#define BIG_CONSTANT(x,y) ((st_index_t)(x)<<32|(st_index_t)(y))
#define ROTL(x,n) ((x)<<(n)|(x)>>(SIZEOF_ST_INDEX_T*CHAR_BIT-(n)))

#if ST_INDEX_BITS <= 32
#define C1 (st_index_t)0xcc9e2d51
#define C2 (st_index_t)0x1b873593
#else
#define C1 BIG_CONSTANT(0x87c37b91,0x114253d5);
#define C2 BIG_CONSTANT(0x4cf5ad43,0x2745937f);
#endif
NO_SANITIZE("unsigned-integer-overflow", static inline st_index_t murmur_step(st_index_t h, st_index_t k));
NO_SANITIZE("unsigned-integer-overflow", static inline st_index_t murmur_finish(st_index_t h));
NO_SANITIZE("unsigned-integer-overflow", extern st_index_t st_hash(const void *ptr, size_t len, st_index_t h));

static inline st_index_t
murmur_step(st_index_t h, st_index_t k)
{
#if ST_INDEX_BITS <= 32
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

static inline st_index_t
murmur_finish(st_index_t h)
{
#if ST_INDEX_BITS <= 32
#define r1 (16)
#define r2 (13)
#define r3 (16)
    const st_index_t c1 = 0x85ebca6b;
    const st_index_t c2 = 0xc2b2ae35;
#else
/* values are taken from Mix13 on http://zimbry.blogspot.ru/2011/09/better-bit-mixing-improving-on.html */
#define r1 (30)
#define r2 (27)
#define r3 (31)
    const st_index_t c1 = BIG_CONSTANT(0xbf58476d,0x1ce4e5b9);
    const st_index_t c2 = BIG_CONSTANT(0x94d049bb,0x133111eb);
#endif
#if ST_INDEX_BITS > 64
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

st_index_t
st_hash(const void *ptr, size_t len, st_index_t h)
{
    const char *data = ptr;
    st_index_t t = 0;
    size_t l = len;

#define data_at(n) (st_index_t)((unsigned char)data[(n)])
#define UNALIGNED_ADD_4 UNALIGNED_ADD(2); UNALIGNED_ADD(1); UNALIGNED_ADD(0)
#if SIZEOF_ST_INDEX_T > 4
#define UNALIGNED_ADD_8 UNALIGNED_ADD(6); UNALIGNED_ADD(5); UNALIGNED_ADD(4); UNALIGNED_ADD(3); UNALIGNED_ADD_4
#if SIZEOF_ST_INDEX_T > 8
#define UNALIGNED_ADD_16 UNALIGNED_ADD(14); UNALIGNED_ADD(13); UNALIGNED_ADD(12); UNALIGNED_ADD(11); \
    UNALIGNED_ADD(10); UNALIGNED_ADD(9); UNALIGNED_ADD(8); UNALIGNED_ADD(7); UNALIGNED_ADD_8
#define UNALIGNED_ADD_ALL UNALIGNED_ADD_16
#endif
#define UNALIGNED_ADD_ALL UNALIGNED_ADD_8
#else
#define UNALIGNED_ADD_ALL UNALIGNED_ADD_4
#endif
#undef SKIP_TAIL
    if (len >= sizeof(st_index_t)) {
#if !UNALIGNED_WORD_ACCESS
        int align = (int)((st_data_t)data % sizeof(st_index_t));
        if (align) {
            st_index_t d = 0;
            int sl, sr, pack;

            switch (align) {
#ifdef WORDS_BIGENDIAN
# define UNALIGNED_ADD(n) case SIZEOF_ST_INDEX_T - (n) - 1: \
                t |= data_at(n) << CHAR_BIT*(SIZEOF_ST_INDEX_T - (n) - 2)
#else
# define UNALIGNED_ADD(n) case SIZEOF_ST_INDEX_T - (n) - 1:	\
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

            data += sizeof(st_index_t)-align;
            len -= sizeof(st_index_t)-align;

            sl = CHAR_BIT * (SIZEOF_ST_INDEX_T-align);
            sr = CHAR_BIT * align;

            while (len >= sizeof(st_index_t)) {
                d = *(st_index_t *)data;
#ifdef WORDS_BIGENDIAN
                t = (t << sr) | (d >> sl);
#else
                t = (t >> sr) | (d << sl);
#endif
                h = murmur_step(h, t);
                t = d;
                data += sizeof(st_index_t);
                len -= sizeof(st_index_t);
            }

            pack = len < (size_t)align ? (int)len : align;
            d = 0;
            switch (pack) {
#ifdef WORDS_BIGENDIAN
# define UNALIGNED_ADD(n) case (n) + 1: \
                d |= data_at(n) << CHAR_BIT*(SIZEOF_ST_INDEX_T - (n) - 1)
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
#define aligned_data __builtin_assume_aligned(data, sizeof(st_index_t))
#else
#define aligned_data data
#endif
        {
            do {
                h = murmur_step(h, *(st_index_t *)aligned_data);
                data += sizeof(st_index_t);
                len -= sizeof(st_index_t);
            } while (len >= sizeof(st_index_t));
        }
    }

    t = 0;
    switch (len) {
#if UNALIGNED_WORD_ACCESS && SIZEOF_ST_INDEX_T <= 8 && CHAR_BIT == 8
    /* in this case byteorder doesn't really matter */
#if SIZEOF_ST_INDEX_T > 4
      case 7: t |= data_at(6) << 48;
      case 6: t |= data_at(5) << 40;
      case 5: t |= data_at(4) << 32;
      case 4:
        t |= (st_index_t)*(uint32_t*)aligned_data;
        goto skip_tail;
# define SKIP_TAIL 1
#endif
      case 3: t |= data_at(2) << 16;
      case 2: t |= data_at(1) << 8;
      case 1: t |= data_at(0);
#else
#ifdef WORDS_BIGENDIAN
# define UNALIGNED_ADD(n) case (n) + 1: \
        t |= data_at(n) << CHAR_BIT*(SIZEOF_ST_INDEX_T - (n) - 1)
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

st_index_t
st_hash_uint32(st_index_t h, uint32_t i)
{
    return murmur_step(h, i);
}

NO_SANITIZE("unsigned-integer-overflow", extern st_index_t st_hash_uint(st_index_t h, st_index_t i));
st_index_t
st_hash_uint(st_index_t h, st_index_t i)
{
    i += h;
/* no matter if it is BigEndian or LittleEndian,
 * we hash just integers */
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 8*8
    h = murmur_step(h, i >> 8*8);
#endif
    h = murmur_step(h, i);
    return h;
}

st_index_t
st_hash_end(st_index_t h)
{
    h = murmur_finish(h);
    return h;
}

#undef st_hash_start
st_index_t
rb_st_hash_start(st_index_t h)
{
    return h;
}

static st_index_t
strhash(st_data_t arg)
{
    register const char *string = (const char *)arg;
    return st_hash(string, strlen(string), FNV1_32A_INIT);
}

int
st_locale_insensitive_strcasecmp(const char *s1, const char *s2)
{
    char c1, c2;

    while (1) {
        c1 = *s1++;
        c2 = *s2++;
        if (c1 == '\0' || c2 == '\0') {
            if (c1 != '\0') return 1;
            if (c2 != '\0') return -1;
            return 0;
        }
        if (('A' <= c1) && (c1 <= 'Z')) c1 += 'a' - 'A';
        if (('A' <= c2) && (c2 <= 'Z')) c2 += 'a' - 'A';
        if (c1 != c2) {
            if (c1 > c2)
                return 1;
            else
                return -1;
        }
    }
}

int
st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n)
{
    char c1, c2;
    size_t i;

    for (i = 0; i < n; i++) {
        c1 = *s1++;
        c2 = *s2++;
        if (c1 == '\0' || c2 == '\0') {
            if (c1 != '\0') return 1;
            if (c2 != '\0') return -1;
            return 0;
        }
        if (('A' <= c1) && (c1 <= 'Z')) c1 += 'a' - 'A';
        if (('A' <= c2) && (c2 <= 'Z')) c2 += 'a' - 'A';
        if (c1 != c2) {
            if (c1 > c2)
                return 1;
            else
                return -1;
        }
    }
    return 0;
}

static int
st_strcmp(st_data_t lhs, st_data_t rhs)
{
    const char *s1 = (char *)lhs;
    const char *s2 = (char *)rhs;
    return strcmp(s1, s2);
}

static int
st_locale_insensitive_strcasecmp_i(st_data_t lhs, st_data_t rhs)
{
    const char *s1 = (char *)lhs;
    const char *s2 = (char *)rhs;
    return st_locale_insensitive_strcasecmp(s1, s2);
}

NO_SANITIZE("unsigned-integer-overflow", PUREFUNC(static st_index_t strcasehash(st_data_t)));
static st_index_t
strcasehash(st_data_t arg)
{
    register const char *string = (const char *)arg;
    register st_index_t hval = FNV1_32A_INIT;

    /*
     * FNV-1a hash each octet in the buffer
     */
    while (*string) {
        unsigned int c = (unsigned char)*string++;
        if ((unsigned int)(c - 'A') <= ('Z' - 'A')) c += 'a' - 'A';
        hval ^= c;

        /* multiply by the 32 bit FNV magic prime mod 2^32 */
        hval *= FNV_32_PRIME;
    }
    return hval;
}

int
st_numcmp(st_data_t x, st_data_t y)
{
    return x != y;
}

st_index_t
st_numhash(st_data_t n)
{
    enum {s1 = 11, s2 = 3};
    return (st_index_t)((n>>s1|(n<<s2)) ^ (n>>s2));
}

#ifdef RUBY
/* Expand TAB to be suitable for holding SIZ entries in total.
   Pre-existing entries remain not deleted inside of TAB, but its bins
   are cleared to expect future reconstruction. See rehash below. */
static void
st_expand_table(st_table *tab, st_index_t siz)
{
    st_table *tmp;
    st_index_t n;

    if (siz <= get_allocated_entries(tab))
        return; /* enough room already */

    tmp = st_init_table_with_size(tab->type, siz);
    n = get_allocated_entries(tab);
    MEMCPY(tmp->entries, tab->entries, st_table_entry, n);
    free(tab->entries);
    free(tab->bins);
    free(tmp->bins);
    tab->entry_power = tmp->entry_power;
    tab->bin_power = tmp->bin_power;
    tab->size_ind = tmp->size_ind;
    tab->entries = tmp->entries;
    tab->bins = NULL;
    tab->rebuilds_num++;
    free(tmp);
}

/* Rehash using linear search.  Return TRUE if we found that the table
   was rebuilt.  */
static int
st_rehash_linear(st_table *tab)
{
    int eq_p, rebuilt_p;
    st_index_t i, j;
    st_table_entry *p, *q;

    free(tab->bins);
    tab->bins = NULL;

    for (i = tab->entries_start; i < tab->entries_bound; i++) {
        p = &tab->entries[i];
        if (DELETED_ENTRY_P(p))
            continue;
        for (j = i + 1; j < tab->entries_bound; j++) {
            q = &tab->entries[j];
            if (DELETED_ENTRY_P(q))
                continue;
            DO_PTR_EQUAL_CHECK(tab, p, q->hash, q->key, eq_p, rebuilt_p);
            if (EXPECT(rebuilt_p, 0))
                return TRUE;
            if (eq_p) {
                *p = *q;
                MARK_ENTRY_DELETED(q);
                tab->num_entries--;
                update_range_for_deleted(tab, j);
            }
        }
    }
    return FALSE;
}

/* Rehash using index.  Return TRUE if we found that the table was
   rebuilt.  */
static int
st_rehash_indexed(st_table *tab)
{
    int eq_p, rebuilt_p;
    st_index_t i;
    st_index_t const n = bins_size(tab);
    unsigned int const size_ind = get_size_ind(tab);
    st_index_t *bins = realloc(tab->bins, n);
    tab->bins = bins;
    initialize_bins(tab);
    for (i = tab->entries_start; i < tab->entries_bound; i++) {
        st_table_entry *p = &tab->entries[i];
        st_index_t ind;
#ifdef QUADRATIC_PROBE
        st_index_t d = 1;
#else
        st_index_t perturb = p->hash;
#endif

        if (DELETED_ENTRY_P(p))
            continue;

        ind = hash_bin(p->hash, tab);
        for (;;) {
            st_index_t bin = get_bin(bins, size_ind, ind);
            if (EMPTY_OR_DELETED_BIN_P(bin)) {
                /* ok, new room */
                set_bin(bins, size_ind, ind, i + ENTRY_BASE);
                break;
            }
            else {
                st_table_entry *q = &tab->entries[bin - ENTRY_BASE];
                DO_PTR_EQUAL_CHECK(tab, q, p->hash, p->key, eq_p, rebuilt_p);
                if (EXPECT(rebuilt_p, 0))
                    return TRUE;
                if (eq_p) {
                    /* duplicated key; delete it */
                    q->record = p->record;
                    MARK_ENTRY_DELETED(p);
                    tab->num_entries--;
                    update_range_for_deleted(tab, bin);
                    break;
                }
                else {
                    /* hash collision; skip it */
#ifdef QUADRATIC_PROBE
                    ind = hash_bin(ind + d, tab);
                    d++;
#else
                    ind = secondary_hash(ind, tab, &perturb);
#endif
                }
            }
        }
    }
    return FALSE;
}

/* Reconstruct TAB's bins according to TAB's entries. This function
   permits conflicting keys inside of entries.  No errors are reported
   then.  All but one of them are discarded silently. */
static void
st_rehash(st_table *tab)
{
    int rebuilt_p;

    do {
        if (tab->bin_power <= MAX_POWER2_FOR_TABLES_WITHOUT_BINS)
            rebuilt_p = st_rehash_linear(tab);
        else
            rebuilt_p = st_rehash_indexed(tab);
    } while (rebuilt_p);
}

static st_data_t
st_stringify(VALUE key)
{
    return (rb_obj_class(key) == rb_cString && !RB_OBJ_FROZEN(key)) ?
        rb_hash_key_str(key) : key;
}

static void
st_insert_single(st_table *tab, VALUE hash, VALUE key, VALUE val)
{
    st_data_t k = st_stringify(key);
    st_table_entry e;
    e.hash = do_hash(k, tab);
    e.key = k;
    e.record = val;

    tab->entries[tab->entries_bound++] = e;
    tab->num_entries++;
    RB_OBJ_WRITTEN(hash, Qundef, k);
    RB_OBJ_WRITTEN(hash, Qundef, val);
}

static void
st_insert_linear(st_table *tab, long argc, const VALUE *argv, VALUE hash)
{
    long i;

    for (i = 0; i < argc; /* */) {
        st_data_t k = st_stringify(argv[i++]);
        st_data_t v = argv[i++];
        st_insert(tab, k, v);
        RB_OBJ_WRITTEN(hash, Qundef, k);
        RB_OBJ_WRITTEN(hash, Qundef, v);
    }
}

static void
st_insert_generic(st_table *tab, long argc, const VALUE *argv, VALUE hash)
{
    long i;

    /* push elems */
    for (i = 0; i < argc; /* */) {
        VALUE key = argv[i++];
        VALUE val = argv[i++];
        st_insert_single(tab, hash, key, val);
    }

    /* reindex */
    st_rehash(tab);
}

/* Mimics ruby's { foo => bar } syntax. This function is subpart
   of rb_hash_bulk_insert. */
void
rb_hash_bulk_insert_into_st_table(long argc, const VALUE *argv, VALUE hash)
{
    st_index_t n, size = argc / 2;
    st_table *tab = RHASH_ST_TABLE(hash);

    tab = RHASH_TBL_RAW(hash);
    n = tab->entries_bound + size;
    st_expand_table(tab, n);
    if (UNLIKELY(tab->num_entries))
        st_insert_generic(tab, argc, argv, hash);
    else if (argc <= 2)
        st_insert_single(tab, hash, argv[0], argv[1]);
    else if (tab->bin_power <= MAX_POWER2_FOR_TABLES_WITHOUT_BINS)
        st_insert_linear(tab, argc, argv, hash);
    else
        st_insert_generic(tab, argc, argv, hash);
}

// to iterate iv_index_tbl
st_data_t
rb_st_nth_key(st_table *tab, st_index_t index)
{
    if (LIKELY(tab->entries_start == 0 &&
               tab->num_entries == tab->entries_bound &&
               index < tab->num_entries)) {
        return tab->entries[index].key;
    }
    else {
        rb_bug("unreachable");
    }
}

void
rb_st_compact_table(st_table *tab)
{
    st_index_t num = tab->num_entries;
    if (REBUILD_THRESHOLD * num <= get_allocated_entries(tab)) {
        /* Compaction: */
        st_table *new_tab = st_init_table_with_size(tab->type, 2 * num);
        rebuild_table_with(new_tab, tab);
        rebuild_move_table(new_tab, tab);
        rebuild_cleanup(tab);
    }
}

#endif
