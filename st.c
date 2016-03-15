/* This is a public domain general purpose hash table package
   originally written by Peter Moore @ UCB.

   The hash table data structures were redesigned and the package was
   rewritten by Vladimir Makarov <vmakarov@redhat.com>.  */

/* The original package implemented classic bucket-based hash tables.
   To decrease pointer chasing and as a consequence to improve a data
   locality the current implementation is based on hash tables with
   open addressing.  The current entries are more compact in
   comparison with the original ones and this also improves the data
   locality.

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

   o The entry array contains table entries in the same order as
     they were inserted.  The array actually implements a circular
     buffer.

     When the first entry is deleted, a variable containing index of
     the current first entry (*entries start*) is changed.  Analogous
     modification is done for *entries bound* when we remove the last
     element.  In all other cases of the deletion, we just mark the
     entry as deleted by using a reserved hash value.

     Such organization of the entry storage makes operations of the
     table shift and the entries traversal very fast.

   o The bins provide access to the entries by their keys.  The
     key hash is mapped to a bin containing *index* of the
     corresponding entry in the entry array.

     The bin array size is always size of two, it makes mapping very
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

   o The length of the bin array is always two times more than the
     entry array length.  This keeps the table load factor healthy.
     The trigger of rebuilding the table is always a case when we can
     not insert an entry anymore.

     Table rebuilding is done by creation of a new entry array and
     bins of an appropriate size.  We also try to reuse the arrays
     in some cases by compacting the array and removing deleted
     entries.

   o To save memory very small tables have no allocated arrays
     bins.  We use a linear search for an access by a key.

   This implementation speeds up the Ruby hash table benchmarks in
   average by more 20% on Intel Haswell CPU.

*/

#ifdef NOT_RUBY
#include "regint.h"
#include "st.h"
#else
#include "internal.h"
#endif

#include <stdio.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <string.h>
#include <assert.h>

#ifdef __GNUC__
# define ATTRIBUTE_UNUSED __attribute__((unused))
#else
# define ATTRIBUTE_UNUSED
#endif

#ifdef ST_DEBUG
#define st_assert(cond) assert(cond)
#else
#define st_assert(cond) ((void)(0 && (cond)))
#endif

struct st_table_entry {
    st_index_t hash;
    st_data_t key;
    st_data_t record;
};

#define type_numhash st_hashtype_num
const struct st_hash_type st_hashtype_num = {
    st_numcmp,
    st_numhash,
};

/* extern int strcmp(const char *, const char *); */
static st_index_t strhash(st_data_t);
static const struct st_hash_type type_strhash = {
    strcmp,
    strhash,
};

static st_index_t strcasehash(st_data_t);
static const struct st_hash_type type_strcasehash = {
    st_locale_insensitive_strcasecmp,
    strcasehash,
};

/* Value used to catch uninitialized entries/bins during
   debugging.  There is a possibility for a false alarm, but the
   probability is extremely small.  */
#define ST_INIT_VAL 0xafafafafafafafaf
#define ST_INIT_VAL_BYTE 0xafa

#ifdef RUBY
#undef malloc
#undef realloc
#undef calloc
#undef free
#define malloc xmalloc
#define calloc xcalloc
#define realloc xrealloc
#define free(x) xfree(x)
#endif

#include <stdlib.h>

#define EQUAL(table,x,y) ((x) == (y) || (*(table)->type->compare)((x),(y)) == 0)
#define PTR_EQUAL(table, ptr, hash_val, key) \
    ((ptr)->hash == (hash_val) && EQUAL((table), (key), (ptr)->key))

/* Max power of two can be used for length of entries array.  In
   reality such length can not be used as length of bins array is
   two times more and an entry and an bin size are at least 12 and
   4 bytes.  We need this value for early check that the table will be
   too big.  */
#if SIZEOF_ST_INDEX_T == 8
#define MAX_POWER2 62
#else
#define MAX_POWER2 30
#endif

/* Return hash value of KEY for TABLE.  */
static inline st_index_t
do_hash(st_data_t key, st_table *table) {
    st_index_t hash = (st_index_t)(table->curr_hash)(key);

    /* MAX_ST_INDEX_VAL is a reserved value used for deleted entry.
       Map it into another value.  Such mapping should be extremely
       rare.  */
    return hash == MAX_ST_INDEX_VAL ? 0 : hash;
}

/* Power of 2 defining the minimal entry array length.  */
#define MINIMAL_POWER2 3

#if MINIMAL_POWER2 < 2
#error "MINIMAL_POWER2 should be >= 2"
#endif

/* If the power2 of the array `entries` is less than the following
   value, don't allocate bins and use a linear search.  */
#define MAX_POWER2_FOR_TABLES_WITHOUT_BINS 3

/* Return smallest n >= MINIMAL_POWER2 such 2^n > SIZE.  */
static int
get_power2(st_index_t size) {
    unsigned int n;

    for (n = 0; size != 0; n++)
        size >>= 1;
    if (n <= MAX_POWER2)
        return n < MINIMAL_POWER2 ? MINIMAL_POWER2 : n;
#ifndef NOT_RUBY
    /* Ran out of the table entries */
    rb_raise(rb_eRuntimeError, "st_table too big");
#endif
    /* should raise exception */
    return -1;
}

/* These macros define reserved values for empty table bin and table
   bin which contains a deleted entry.  We will never use such
   values for an index in bins (see comments for MAX_POWER2).  */
#define EMPTY_BIN    (~(st_bin_t) 0)
#define DELETED_BIN  (EMPTY_BIN - 1)

/* Mark bin B_PTR as empty, in other words not corresponding to any
   entry.  */
#define MARK_BIN_EMPTY(b_ptr) (*(b_ptr) = EMPTY_BIN)

/* Mark bin B_PTR as corresponding to a deleted table entry.
   Update number of entries in the table and number of bins
   corresponding to deleted entries. */
#define MARK_BIN_DELETED(tab, b_ptr)                          \
    do {                                                        \
        if (b_ptr != NULL) {					\
            st_assert(! EMPTY_OR_DELETED_BIN_PTR_P(b_ptr));	\
            *(b_ptr) = DELETED_BIN;                           \
	}							\
        (tab)->num_entries--;                                  \
        (tab)->deleted_bins++;                               \
    } while (0)

/* Macros to check empty bins and bins corresponding deleted
   entries.  */
#define EMPTY_BIN_P(b) ((b) == EMPTY_BIN)
#define DELETED_BIN_P(b) ((b) == DELETED_BIN)
#define EMPTY_OR_DELETED_BIN_P(b) ((b) >= DELETED_BIN)

#define EMPTY_BIN_PTR_P(b_ptr) EMPTY_BIN_P(*(b_ptr))
#define DELETED_BIN_PTR_P(b_ptr) DELETED_BIN_P(*(b_ptr))
#define EMPTY_OR_DELETED_BIN_PTR_P(b_ptr) EMPTY_OR_DELETED_BIN_P(*(b_ptr))

/* Macros for marking and checking deleted entries.  */
#define MARK_ENTRY_DELETED(e_ptr) ((e_ptr)->hash = MAX_ST_INDEX_VAL)
#define DELETED_ENTRY_P(e_ptr) ((e_ptr)->hash == MAX_ST_INDEX_VAL)

/* Return the bins number of the table TAB.  */
static inline st_index_t
get_bins_num(const st_table *tab) {
    return tab->allocated_entries << 1;
}

/* Return index of table TAB bin corresponding to HASH_VALUE.  */
static inline st_index_t
hash_bin(st_index_t hash_value, st_table *tab)
{
  return hash_value & (get_bins_num(tab) - 1);
}

/* Return mask for an entry index in table TAB.  */
static inline st_index_t
entries_mask(st_table *tab)
{
    return tab->allocated_entries - 1;
}

/* Mark all bins of table TAB as empty.  */
static void
initialize_bins(st_table *tab)
{
    st_index_t i;
    st_bin_t *bins;
    st_index_t n = get_bins_num(tab);
    
    bins = tab->bins;
    /* Mark all bins empty: */
    for (i = 0; i < n; i++)
        MARK_BIN_EMPTY(&bins[i]);
}

/* Make table TAB empty.  Use the major hash function.  */
static void
make_tab_empty(st_table *tab)
{
    tab->curr_hash = tab->type->hash;
    tab->num_entries = 0;
    tab->deleted_bins = 0;
    tab->rebuilds_num = 0;
    tab->entries_start = tab->entries_bound = 0;
    if (tab->bins != NULL)
        initialize_bins(tab);
}

#ifdef ST_DEBUG
/* Check the table T consistency.  It can be extremely slow.  So use
   it only for debugging.  */
static void
st_check(st_table *t) {
    st_index_t d, e, i, n, mask, p;

    for (p = t->allocated_entries, i = 0; p > 1; i++, p>>=1)
        ;
    p = i;
    assert (p >= MINIMAL_POWER2);
    mask = entries_mask(t);
    assert ((t->entries_start == 0 && t->entries_bound == 0 && t->num_entries == 0)
	    || (t->num_entries != 0 && t->entries_start < t->allocated_entries
		&& t->entries_bound >= 1 && t->entries_bound <= t->allocated_entries));
    n = 0;
    if (t->entries_bound != 0)
        for (i = t->entries_start;;) {
	    assert (t->entries[i].hash != ST_INIT_VAL && t->entries[i].key != ST_INIT_VAL
		    && t->entries[i].record != ST_INIT_VAL);
	    if (! DELETED_ENTRY_P(&t->entries[i]))
	      n++;
	    if (++i == t->entries_bound)
	        break;
	    i &= mask;
	}
    assert (n == t->num_entries);
    if (t->bins == NULL)
        assert (p <= MAX_POWER2_FOR_TABLES_WITHOUT_BINS);
    else {
        assert (p > MAX_POWER2_FOR_TABLES_WITHOUT_BINS);
	for (n = d = i = 0; i < get_bins_num(t); i++) {
  	    assert (t->bins[i] != ST_INIT_VAL);
	    if (DELETED_BIN_P(t->bins[i])) {
	        d++;
		continue;
	    }
	    else if (EMPTY_BIN_P(t->bins[i]))
	        continue;
	    n++;
	    e = t->bins[i];
	    assert (e < t->allocated_entries);
	    assert (t->entries[e].hash != ST_INIT_VAL && t->entries[e].key != ST_INIT_VAL
		    && t->entries[e].record != ST_INIT_VAL);
	    assert (! DELETED_ENTRY_P(&t->entries[e]));
	    if (t->entries_bound > t->entries_start)
	        assert (t->entries_start <= e && e < t->entries_bound);
	    else
	        assert (! (t->entries_bound <= e && e < t->entries_start));
	}
	assert (d == t->deleted_bins && n == t->num_entries);
    }
}
#endif

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
    FILE *f = fopen((snprintf(fname, sizeof(fname), "/tmp/col%ld", (long)getpid()), fname), "w");
    fprintf(f, "collision: %d / %d (%6.2f)\n", collision.all, collision.total,
            ((double)collision.all / (collision.total)) * 100);
    fprintf(f, "num: %d, str: %d, strcase: %d\n", collision.num, collision.str, collision.strcase);
    fclose(f);
}
#endif

/* Create and return table with TYPE which can hold at least SIZE
   entries.  The real number of entries which the table can hold is
   the nearest power of two for SIZE.  */
st_table *
st_init_table_with_size(const struct st_hash_type *type, st_index_t size)
{
    st_table *tab;
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
    tab = (st_table *) malloc(sizeof (st_table));
    tab->type = type;
    tab->allocated_entries = 1 << n;
    if (n <= MAX_POWER2_FOR_TABLES_WITHOUT_BINS)
        tab->bins = NULL;
    else
        tab->bins = (st_bin_t *) malloc(get_bins_num(tab) * sizeof (st_bin_t));
    tab->entries = (st_table_entry *) malloc(tab->allocated_entries
					     * sizeof(st_table_entry));
#ifdef ST_DEBUG
    memset (tab->entries, ST_INIT_VAL_BYTE,
	    tab->allocated_entries * sizeof(st_table_entry));
    if (tab->bins != NULL)
        memset (tab->bins, ST_INIT_VAL_BYTE,
		get_bins_num(tab) * sizeof(st_bin_t));
#endif
    make_tab_empty(tab);
#ifdef ST_DEBUG
    st_check(tab);
#endif
    return tab;
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

/* Make TABLE empty.  */
void
st_clear(st_table *table)
{
    make_tab_empty(table);
#ifdef ST_DEBUG
    st_check(table);
#endif
}

/* Free TABLE space.  */
void
st_free_table(st_table *table)
{
    if (table->bins != NULL)
        free(table->bins);
    free(table->entries);
    free(table);
}

/* Return byte size of memory allocted for TABLE.  */
size_t
st_memsize(const st_table *table)
{
    return(sizeof(st_table)
           + (table->bins == NULL ? 0 : get_bins_num(table) * sizeof(st_bin_t))
           + table->allocated_entries * sizeof(st_table_entry));
}

static st_bin_t
find_table_bin(st_table *tab, st_index_t hash_value, st_data_t key);

static st_bin_t
find_table_bin_ptr(st_table *tab, st_index_t hash_value,
		   st_data_t key, st_bin_t **res_bin_ptr);

static st_bin_t
find_table_bin_ptr_and_reserve(st_table *tab, st_index_t *hash_value,
			       st_data_t key, st_bin_t **res_bin_ptr);

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

#define collision_check 1

#define COLLISION (collision_check ? count_collision(table->type) : (void)0)
#define FOUND_BIN (collision_check ? collision.total++ : (void)0)
#else
#define COLLISION
#define FOUND_BIN
#endif

/*  Use entries array of table TAB to initialize the bins
    array.  */
static void
rebuild_bins(st_table *tab)
{
    st_index_t i, check, bound, mask;
    st_table_entry *entries, *curr_entry_ptr;
    st_bin_t bin, *bin_ptr;
    
    tab->deleted_bins = 0;
    if (tab->bins == NULL)
      return;
    initialize_bins(tab);
    bound = tab->entries_bound;
    entries = tab->entries;
    check = tab->rebuilds_num;
    mask = entries_mask(tab);
    if (bound == 0)
      st_assert (tab->num_entries == 0);
    else {
        tab->num_entries = 0;
        for (i = tab->entries_start;;) {
	    curr_entry_ptr = &entries[i];
	    if (! DELETED_ENTRY_P(curr_entry_ptr)) {
	        bin = find_table_bin_ptr_and_reserve(tab, &curr_entry_ptr->hash,
						     curr_entry_ptr->key, &bin_ptr);
		st_assert(tab->rebuilds_num == check && EMPTY_BIN_P(bin));
		*bin_ptr = (curr_entry_ptr - entries);
	    }
	    if (++i == bound)
	      break;
	    i &= mask;
	}
    }
#ifdef ST_DEBUG
    st_check(tab);
#endif
}

/* If the number of entries is at least REBUILD_THRESHOLD times less
   than the entry array length, decrease the table.  */
#define REBUILD_THRESHOLD 4

#if REBUILD_THRESHOLD < 2
#error "REBUILD_THRESHOLD should be >=2"
#endif

static int inside_table_rebuild_p = FALSE;

/* Rebuild table TAB.  Rebuilding removes all deleted bins and
   entries and can change size of the table entries and bins
   arrays.  Rebuilding is implemented by creation a new table for
   simplicity.  */
static void
rebuild_table(st_table *tab)
{
    st_index_t i, ni, bound, mask;
    st_table *new_tab;
    st_table_entry *entries, *new_entries;
    st_table_entry *curr_entry_ptr;
    st_bin_t new_bin, *new_bin_ptr;
    
    st_assert(tab != NULL);
    bound = tab->entries_bound;
    entries = tab->entries;
    mask = entries_mask(tab);
    inside_table_rebuild_p = TRUE;
    if (tab->num_entries < tab->allocated_entries
	&& (REBUILD_THRESHOLD * tab->num_entries > tab->allocated_entries
	    || tab->num_entries < (1 << MINIMAL_POWER2))) {
        st_index_t start;
	int first_p;

	/* Table compaction: */
	if (tab->bins != NULL)
	    initialize_bins(tab);
	start = tab->entries_start;
        /* Prevent rebuilding during bin reservations.  */
        tab->deleted_bins = tab->entries_start = tab->entries_bound = 0;
	if (bound == 0)
	  st_assert (tab->num_entries == 0);
	else {
	    tab->num_entries = 0;
	    first_p = TRUE;
	    for (ni = i = start;;) {
		curr_entry_ptr = &entries[i];
		if (! DELETED_ENTRY_P(curr_entry_ptr)) {
		    if (ni != i)
		        entries[ni] = *curr_entry_ptr;
		    if (first_p) {
		        tab->entries_start = ni;
			first_p = FALSE;
		    }
		    if (tab->bins != NULL) {
		        new_bin = find_table_bin_ptr_and_reserve(tab, &curr_entry_ptr->hash,
								 curr_entry_ptr->key,
								 &new_bin_ptr);
			st_assert(EMPTY_BIN_P(new_bin));
			*new_bin_ptr = ni;
		    }
		    ni = (ni + 1) & mask;
		}
		if (++i == bound)
		  break;
		i &= mask;
	    }
	    tab->entries_bound = ni == 0 ? tab->allocated_entries : ni;
	}
    } else {
        st_assert (bound != 0 && tab->num_entries != 0);
        new_tab = st_init_table_with_size(tab->type,
					  2 * tab->num_entries - 1);
	st_assert(bound <= new_tab->allocated_entries
		  && new_tab->curr_hash == new_tab->type->hash);
	new_tab->curr_hash = tab->curr_hash;
	new_entries = new_tab->entries;
	ni = 0;
	for (i = tab->entries_start;;) {
	    curr_entry_ptr = &entries[i];
	    if (! DELETED_ENTRY_P(curr_entry_ptr)) {
	        new_entries[ni] = *curr_entry_ptr;
		if (new_tab->bins != NULL) {
		    new_bin = find_table_bin_ptr_and_reserve(new_tab, &curr_entry_ptr->hash,
							     curr_entry_ptr->key,
							     &new_bin_ptr);
		    st_assert(new_tab->rebuilds_num == 0 && EMPTY_BIN_P(new_bin));
		    *new_bin_ptr = ni;
		}
		ni++;
	    }
	    if (++i == bound)
	        break;
	    i &= mask;
	}
	st_assert (tab->num_entries == ni && new_tab->num_entries == ni);
	tab->allocated_entries = new_tab->allocated_entries;
	if (tab->bins != NULL)
	    free(tab->bins);
	tab->bins = new_tab->bins;
	free(tab->entries);
	tab->entries = new_tab->entries;
	free(new_tab);
	tab->deleted_bins = 0;
	tab->entries_start = 0;
	tab->entries_bound = tab->num_entries;
    }
    tab->rebuilds_num++;
    inside_table_rebuild_p = FALSE;
#ifdef ST_DEBUG
    st_check(tab);
#endif
}

/* Recalculate hashes of entries in table TAB.  */
static void
reset_entry_hashes (st_table *tab)
{
    st_index_t i, bound, mask;
    st_table_entry *entries, *curr_entry_ptr;
    
    bound = tab->entries_bound;
    entries = tab->entries;
    mask = entries_mask(tab);
    for (i = tab->entries_start;;) {
      curr_entry_ptr = &entries[i];
      if (! DELETED_ENTRY_P(curr_entry_ptr))
	  curr_entry_ptr->hash = do_hash(curr_entry_ptr->key, tab);
      if (++i == bound)
	  break;
      i &= mask;
    }
}

/* Return the next secondary hash index for table TAB using previous
   index IND and PERTERB.  Finally modulo of the function becomes a
   full *cycle linear congruential generator*, in other words it
   guarantees traversing all table bins in extreme case.

   According the Hull-Dobell theorem a generator
   "Xnext = (a*Xprev + c) mod m" is a full cycle generator iff
     o m and c are relatively prime
     o a-1 is divisible by all prime factors of m
     o a-1 is divisible by 4 if m is divisible by 4.

   For our case a is 5, c is 1, and m is a power of two.  */
static inline st_index_t
secondary_hash(st_index_t ind, st_table *tab, st_index_t *perterb)
{
    *perterb >>= 11;
    ind = (ind << 2) + ind + *perterb + 1;
    return hash_bin(ind, tab);
}

/* Find an entry with HASH_VALUE and KEY in TABLE using a linear
   search.  Return the index of the found entry in array `entries`.
   If it is not found, return EMPTY_BIN.  */
static st_bin_t
find_entry(st_table *table, st_index_t hash_value, st_data_t key) {
    st_index_t i, bound, mask;
    st_table_entry *entries;

    bound = table->entries_bound;
    if (bound == 0) {
        st_assert (table->num_entries == 0);
	return EMPTY_BIN;
    }
    entries = table->entries;
    mask = entries_mask(table);
    for (i = table->entries_start;;) {
	if (PTR_EQUAL(table, &entries[i], hash_value, key))
	    return i;
	if (++i == bound)
	    break;
	i &= mask;
    }
    return EMPTY_BIN;
}

/*#define DOUBLE_PROBE*/

/* Return TABLE bin vlaue for HASH_VALUE and KEY.  We always find such
   bin as bins array length is bigger entries array.  The result
   bin value is always empty if the table has no entry with KEY.  If the
   table has no allocated array bins, return the entries array
   index of the searched entry or EMPTY_BIN if it is not
   found.  */
static st_bin_t
find_table_bin(st_table *table, st_index_t hash_value, st_data_t key)
{
    st_index_t ind;
#ifdef DOUBLE_PROBE
    st_index_t d;
#else
    st_index_t peterb;
#endif
    st_bin_t bin;
    st_table_entry *entries = table->entries;
    
    st_assert(table != NULL);
    if (table->bins == NULL)
	return find_entry(table, hash_value, key);
    ind = hash_bin(hash_value, table);
#ifdef DOUBLE_PROBE
    d = 1;
#else
    peterb = hash_value;
#endif
    FOUND_BIN;
    for (;;) {
        bin = table->bins[ind];
        if (! EMPTY_OR_DELETED_BIN_P(bin)
            && PTR_EQUAL(table, &entries[bin], hash_value, key))
            break;
        else if (EMPTY_BIN_P(bin))
            break;
#ifdef DOUBLE_PROBE
	ind = hash_bin(ind + d, table);
	d++;
#else
        ind = secondary_hash(ind, table, &peterb);
#endif
        COLLISION;
    }
    return bin;
}

/* Return pointer to TABLE bin for HASH_VALUE and KEY through
   RES_BIN_PTR and the pointed value as the function result.  We
   always find such bin as bins array length is bigger entries
   array.  The result bin value is always empty if the table has no
   entry with KEY.  If the table has no allocated array bins,
   return the entries array index of the searched entry or
   EMPTY_BIN if it is not found.  */
static st_bin_t
find_table_bin_ptr(st_table *table, st_index_t hash_value, st_data_t key,
		   st_bin_t **res_bin_ptr)
{
    st_index_t ind;
#ifdef DOUBLE_PROBE
    st_index_t d;
#else
    st_index_t peterb;
#endif
    st_bin_t *bin_ptr;
    st_table_entry *entries = table->entries;
    
    st_assert(table != NULL);
    if (table->bins == NULL) {
        *res_bin_ptr = NULL;
	return find_entry(table, hash_value, key);
    }
    ind = hash_bin(hash_value, table);
#ifdef DOUBLE_PROBE
    d = 1;
#else
    peterb = hash_value;
#endif
    FOUND_BIN;
    for (;;) {
        bin_ptr = table->bins + ind;
        if (! EMPTY_OR_DELETED_BIN_PTR_P(bin_ptr)
            && PTR_EQUAL(table, &entries[*bin_ptr], hash_value, key))
            break;
        else if (EMPTY_BIN_PTR_P(bin_ptr))
            break;
#ifdef DOUBLE_PROBE
	ind = hash_bin(ind + d, table);
	d++;
#else
        ind = secondary_hash(ind, table, &peterb);
#endif
        COLLISION;
    }
    *res_bin_ptr = bin_ptr;
    return *bin_ptr;
}

/* If we have the following number of collisions with different keys
   but with the same hash during finding a bin for new entry
   inclusions, possibly a denial attack is going on.  Start to use a
   stronger hash.  */
#define HIT_THRESHOULD_FOR_STRONG_HASH 10

/* Return pointer to TABLE bin for HASH_VALUE and KEY through
   RES_BIN_PTR and the pointed value as the function result.
   Reserve the bin for inclusion of the corresponding entry into the
   table if it is not there yet.  We always find such bin as bins
   array length is bigger entries array.  Although we can reuse a
   deleted bin, the result bin value is always empty if the table has no
   entry with KEY.  If the table has no allocated array bins,
   return the entries array index of the searched entry or
   EMPTY_BIN if it is not found.  */
static st_bin_t
find_table_bin_ptr_and_reserve(st_table *table, st_index_t *hash_value,
			       st_data_t key, st_bin_t **res_bin_ptr)
{
    st_index_t bound, ind, curr_hash_value = *hash_value;
#ifdef DOUBLE_PROBE
    st_index_t d;
#else
    st_index_t peterb;
#endif
    st_bin_t *bin_ptr, *first_deleted_bin_ptr;
    st_table_entry *entries;
    int hit;
    
    st_assert(table != NULL);
    bound = table->entries_bound;
    if ((bound != 0 && bound == table->entries_start)
	|| (bound == table->allocated_entries
	    && table->entries_start == 0))
        rebuild_table(table);
    else if (2 * table->deleted_bins >= get_bins_num(table))
        rebuild_bins(table);
    if (table->bins == NULL) {
        st_index_t bin = find_entry(table, curr_hash_value, key);
        *res_bin_ptr = NULL;
	if (EMPTY_BIN_P(bin))
            table->num_entries++;
	return bin;
    }
 repeat:
    ind = hash_bin(curr_hash_value, table);
#ifdef DOUBLE_PROBE
    d = 1;
#else
    peterb = curr_hash_value;
#endif
    FOUND_BIN;
    first_deleted_bin_ptr = NULL;
    entries = table->entries;
    hit = 0;
    for (;;) {
        bin_ptr = table->bins + ind;
        if (EMPTY_BIN_PTR_P(bin_ptr)) {
            table->num_entries++;
            if (first_deleted_bin_ptr != NULL) {
                /* We can reuse bin of a deleted entry.  */
                bin_ptr = first_deleted_bin_ptr;
                MARK_BIN_EMPTY(bin_ptr);
                st_assert(table->deleted_bins > 0);
                table->deleted_bins--;
            }
            break;
        } else if (! DELETED_BIN_PTR_P(bin_ptr)) {
            if (PTR_EQUAL(table, &entries[*bin_ptr], curr_hash_value, key))
                break;
	    if (curr_hash_value == entries[*bin_ptr].hash) {
	        hit++;
		if (hit > HIT_THRESHOULD_FOR_STRONG_HASH
		    && table->curr_hash != table->type->strong_hash
		    && table->type->strong_hash != NULL
		    && ! inside_table_rebuild_p) {
		    table->curr_hash = table->type->strong_hash;
		    *hash_value = curr_hash_value = do_hash(key, table);
		    reset_entry_hashes(table);
		    rebuild_table(table);
		    bound = table->entries_bound;
		    goto repeat;
		}
	    }
        } else if (first_deleted_bin_ptr == NULL)
            first_deleted_bin_ptr = bin_ptr;
#ifdef DOUBLE_PROBE
	ind = hash_bin(ind + d, table);
	d++;
#else
        ind = secondary_hash(ind, table, &peterb);
#endif
        COLLISION;
    }
    *res_bin_ptr = bin_ptr;
    return *bin_ptr;
}

/* Find an entry with KEY in TABLE.  Return non-zero if we found it.
   Set up *RECORD to the found entry record.  */
int
st_lookup(st_table *table, st_data_t key, st_data_t *value)
{
    st_bin_t bin;
    st_index_t hash = do_hash(key, table);
    
    bin = find_table_bin(table, hash, key);
    if (EMPTY_BIN_P(bin))
        return 0;
    if (value != 0)
        *value = table->entries[bin].record;
    return 1;
}

/* Find an entry with KEY in TABLE.  Return non-zero if we found it.
   Set up *RESULT to the found table entry key.  */
int
st_get_key(st_table *table, st_data_t key, st_data_t *result)
{
    st_bin_t bin;
    
    bin = find_table_bin(table, do_hash(key, table), key);
    if (EMPTY_BIN_P(bin))
        return 0;
    if (result != 0)
        *result = table->entries[bin].key;
    return 1;
}

/* Insert (KEY, VALUE) into TABLE and return zero.  If there is
   already entry with KEY in the table, return nonzero and and
   update the value of the found entry.  */
int
st_insert(st_table *table, st_data_t key, st_data_t value)
{
    st_table_entry *entry;
    st_bin_t bin, *bin_ptr;
    st_index_t ind, hash_value;
    
    hash_value = do_hash(key, table);
    bin = find_table_bin_ptr_and_reserve(table, &hash_value,
					 key, &bin_ptr);
    if (EMPTY_BIN_P(bin)) {
        st_assert(table->entries_bound <= table->allocated_entries);
        if (table->entries_bound == table->allocated_entries)
	    table->entries_bound = 0;
	ind = table->entries_bound++;
        entry = &table->entries[ind];
        entry->hash = hash_value;
        entry->key = key;
        entry->record = value;
	if (bin_ptr != NULL)
	    *bin_ptr = ind;
#ifdef ST_DEBUG
	st_check(table);
#endif
        return 0;
    }
    table->entries[bin].record = value;
#ifdef ST_DEBUG
    st_check(table);
#endif
    return 1;
}

/* Insert (KEY, VALUE) into TABLE.  The table should not have entry
   with KEY before the insertion.  */
void
st_add_direct(st_table *table, st_data_t key, st_data_t value)
{
    int res = st_insert(table, key, value);

    st_assert(!res);
}

/* Insert (FUNC(KEY), VALUE) into TABLE and return zero.  If there is
   already entry with KEY in the table, return nonzero and and
   update the value of the found entry.  */
int
st_insert2(st_table *table, st_data_t key, st_data_t value,
           st_data_t (*func)(st_data_t))
{
    st_table_entry *entry;
    st_bin_t bin, *bin_ptr;
    st_index_t ind, hash_value, check;
    
    hash_value = do_hash(key, table);
    bin = find_table_bin_ptr_and_reserve(table, &hash_value, key, &bin_ptr);
    if (EMPTY_BIN_P(bin)) {
        st_assert(table->entries_bound <= table->allocated_entries);
        check = table->rebuilds_num;
        key = (*func)(key);
        st_assert(check == table->rebuilds_num
                  && do_hash(key, table) == hash_value);
        if (table->entries_bound == table->allocated_entries)
	    table->entries_bound = 0;
        ind = table->entries_bound++;
        entry = &table->entries[ind];
        entry->hash = hash_value;
        entry->key = key;
        entry->record = value;
	if (bin_ptr != NULL)
	  *bin_ptr = ind;
#ifdef ST_DEBUG
	st_check(table);
#endif
        return 0;
    }
    table->entries[bin].record = value;
#ifdef ST_DEBUG
    st_check(table);
#endif
    return 1;
}

/* Return a copy of table OLD_TAB.  */
st_table *
st_copy(st_table *old_tab)
{
    st_table *new_tab;
    st_index_t n;
    
    new_tab = (st_table *) malloc(sizeof(st_table));
    *new_tab = *old_tab;
    n = get_bins_num(old_tab);
    if (old_tab->bins == NULL)
        new_tab->bins = NULL;
    else
        new_tab->bins = (st_bin_t *) malloc(n * sizeof(st_bin_t));
    new_tab->entries = (st_table_entry *) malloc(old_tab->allocated_entries
                                                    * sizeof(st_table_entry));
    MEMCPY(new_tab->entries, old_tab->entries, st_table_entry, old_tab->allocated_entries);
    if (old_tab->bins != NULL)
        MEMCPY(new_tab->bins, old_tab->bins, st_bin_t, n);
#ifdef ST_DEBUG
    st_check(new_tab);
#endif
    return new_tab;
}

/* Update the entries start/bound of the table TAB after removing an
   entry with index N in the array entries.  */
static inline int
update_range_for_deleted(st_table *tab, st_index_t n) {
  st_index_t temp;
  
  if (tab->num_entries == 0) {
      tab->entries_start = tab->entries_bound = 0;
      return TRUE;
  }
  else if (tab->entries_start == n)
      tab->entries_start = (n + 1) & entries_mask(tab);
  else if ((temp = tab->entries_bound) == n + 1)
      tab->entries_bound = (n == 0 ? tab->allocated_entries : n);
  return FALSE;
}

/* Delete entry with KEY from table TAB, set up *VALUE (unless VALUE
   is zero) from deleted table entry, and return non-zero.  If there
   is no entry with KEY in the table, clear *VALUE (unless VALUE is
   zero), and return zero.  */
static int
st_general_delete(st_table *tab, st_data_t *key, st_data_t *value)
{
    st_index_t n;
    st_table_entry *entry, *entries;
    st_bin_t bin, *bin_ptr;
    
    st_assert(tab != NULL);
    bin = find_table_bin_ptr(tab, do_hash(*key, tab), *key, &bin_ptr);
    if (EMPTY_BIN_P(bin)) {
        if (value != 0) *value = 0;
        return 0;
    }
    entries = tab->entries;
    entry = &entries[bin];
    MARK_BIN_DELETED(tab, bin_ptr);
    *key = entry->key;
    if (value != 0) *value = entry->record;
    MARK_ENTRY_DELETED(entry);
    n = entry - entries;
    update_range_for_deleted(tab, n);
#ifdef ST_DEBUG
    st_check(tab);
#endif
    return 1;
}

int
st_delete(st_table *tab, st_data_t *key, st_data_t *value)
{
    return st_general_delete(tab, key, value);
}

/* The function and other functions with suffix '_safe' or '_check'
   are originated from previous implementation of the hash tables.  It
   was necessary for correct deleting entries during traversing
   tables.  The current implementation permits deletion during
   traversing without a specific way to do this.  */
int
st_delete_safe(st_table *tab, st_data_t *key, st_data_t *value,
               st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_delete(tab, key, value);
}

/* If TABLE is empty, clear *VALUE (unless VALUE is zero), and return
   zero.  Otherwise, remove the first entry in the table.  Return
   its key through KEY and its record through VALUE (unless VALUE is
   zero).  */
int
st_shift(st_table *table, st_data_t *key, st_data_t *value)
{
    st_index_t i, bound, mask;
    st_bin_t bin, *bin_ptr;
    st_table_entry *entries, *curr_entry_ptr;
    
    if (table->num_entries == 0) {
        if (value != 0) *value = 0;
        return 0;
    }
    
    entries = table->entries;
    bound = table->entries_bound;
    st_assert (bound != 0);
    mask = entries_mask(table);
    for (i = table->entries_start;;) {
        curr_entry_ptr = &entries[i];
	if (! DELETED_ENTRY_P(curr_entry_ptr)) {
	    if (value != 0) *value = curr_entry_ptr->record;
	    *key = curr_entry_ptr->key;
	    bin = find_table_bin_ptr(table, curr_entry_ptr->hash,
				     curr_entry_ptr->key, &bin_ptr);
	    st_assert(! EMPTY_BIN_P(bin)
		      && &entries[bin] == curr_entry_ptr);
	    MARK_ENTRY_DELETED(curr_entry_ptr);
	    MARK_BIN_DELETED(table, bin_ptr);
	    if (table->num_entries == 0)
	        table->entries_start = table->entries_bound = 0;
	    else
	        table->entries_start = (i + 1) & mask;
#ifdef ST_DEBUG
	    st_check(table);
#endif
	    return 1;
	}
	if (++i == bound)
	  break;
	i &= mask;
    }
    st_assert(0);
    return 0;
}

/* See comments for function st_delete_safe.  */
void
st_cleanup_safe(st_table *table ATTRIBUTE_UNUSED,
                st_data_t never ATTRIBUTE_UNUSED)
{
}

/* Find entry with KEY in TABLE, call FUNC with key, value of the
   found entry, and non-zero as the 3rd argument.  If the entry is
   not found, call FUNC with KEY, and 2 zero arguments.  If the call
   returns ST_CONTINUE, the table will have an entry with key and
   value returned by FUNC through the 1st and 2nd parameters.  If the
   call of FUNC returns ST_DELETE, the table will not have entry
   with KEY.  The function returns flag of that the entry with KEY
   was in the table before the call.  */
int
st_update(st_table *table, st_data_t key, st_update_callback_func *func, st_data_t arg)
{
    st_table_entry *entry, *entries;
    st_bin_t bin, *bin_ptr;
    st_data_t value = 0, old_key;
    st_index_t n, check;
    int retval, existing = 0;
    
    bin = find_table_bin_ptr(table, do_hash(key, table), key, &bin_ptr);
    entries = table->entries;
    entry = &entries[bin];
    if (! EMPTY_BIN_P(bin)) {
        key = entry->key;
        value = entry->record;
        existing = 1;
    }
    old_key = key;
    check = table->rebuilds_num;
    retval = (*func)(&key, &value, arg, existing);
    st_assert(check == table->rebuilds_num);
    switch (retval) {
    case ST_CONTINUE:
        if (! existing) {
            st_insert(table, key, value);
            break;
        }
        if (old_key != key) {
            entry->key = key;
        }
        entry->record = value;
        break;
    case ST_DELETE:
        if (existing) {
            MARK_ENTRY_DELETED(entry);
	    MARK_BIN_DELETED(table, bin_ptr);
            n = entry - table->entries;
	    update_range_for_deleted(table, n);
        }
        break;
    }
#ifdef ST_DEBUG
    st_check(table);
#endif
    return existing;
}

/* Traverse all entries in table TAB calling FUNC with current
   entry key and value and zero.  If the call returns ST_STOP, stop
   traversing.  If the call returns ST_DELETE, delete the current
   entry from the table.  In case of ST_CHECK or ST_CONTINUE,
   continue traversing.  The function always returns zero.  */
static int
st_general_foreach(st_table *tab, int (*func)(ANYARGS), st_data_t arg)
{
    st_bin_t bin, *bin_ptr;
    st_table_entry *entries, *curr_entry_ptr;
    enum st_retval retval;
    st_index_t i, bound, n, mask, hash, rebuilds_num;
    st_data_t key;
    
    if (tab->num_entries == 0)
      return 0;
    bound = tab->entries_bound;
    st_assert (bound != 0);
    entries = tab->entries;
    mask = entries_mask(tab);
    for (i = tab->entries_start;;) {
        curr_entry_ptr = &entries[i];
	if (! DELETED_ENTRY_P(curr_entry_ptr)) {
	      key = curr_entry_ptr->key;
	      rebuilds_num = tab->rebuilds_num;
	      hash = curr_entry_ptr->hash;
	      retval = (*func)(key, curr_entry_ptr->record, arg, 0);
	      if (rebuilds_num != tab->rebuilds_num) {
		  bound = tab->entries_bound;
		  entries = tab->entries;
		  mask = entries_mask(tab);
		  i = find_table_bin(tab, hash, key);
		  if (EMPTY_BIN_P (i)) {
		      /* call func with error notice */
		      retval = (*func)(0, 0, arg, 1);
#ifdef ST_DEBUG
		      st_check(tab);
#endif
		      return 1;
		  }
		  curr_entry_ptr = &entries[i];
	      }
	      switch (retval) {
	      case ST_CHECK:
		  break;
	      case ST_CONTINUE:
		  break;
	      case ST_STOP:
#ifdef ST_DEBUG
		  st_check(tab);
#endif
		  return 0;
	      case ST_DELETE:
		  bin = find_table_bin_ptr(tab, hash, curr_entry_ptr->key, &bin_ptr);
		  if (! EMPTY_BIN_P(bin)) {
		      st_assert(&entries[bin] == curr_entry_ptr);
		      MARK_ENTRY_DELETED(curr_entry_ptr);
		      MARK_BIN_DELETED(tab, bin_ptr);
		      n = curr_entry_ptr - entries;
		      if (update_range_for_deleted(tab, n)) {
#ifdef ST_DEBUG
			  st_check(tab);
#endif
			  return 0;
		      }
		  }
		  break;
	      }
	  }
	if (++i == bound)
	    break;
	i &= mask;
    }
#ifdef ST_DEBUG
    st_check(tab);
#endif
    return 0;
}

int
st_foreach(st_table *tab, int (*func)(ANYARGS), st_data_t arg)
{
    return st_general_foreach(tab, func, arg);
}

/* See comments for function st_delete_safe.  */
int
st_foreach_check(st_table *tab, int (*func)(ANYARGS), st_data_t arg,
                 st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_foreach(tab, func, arg);
}

/* Set up array KEYS by at most SIZE keys of head table entries.
   Return the number of keys set up in array KEYS.  */
static st_index_t
st_general_keys(st_table *table, st_data_t *keys, st_index_t size)
{
    st_index_t i, bound, mask;
    st_data_t *keys_start, *keys_end;
    st_table_entry *curr_entry_ptr, *entries = table->entries;
    
    if (table->num_entries == 0 || size == 0)
        return 0;
    bound = table->entries_bound;
    st_assert (bound != 0);
    mask = entries_mask(table);
    keys_start = keys;
    keys_end = keys + size;
    for (i = table->entries_start;;) {
	curr_entry_ptr = &entries[i];
        if (! DELETED_ENTRY_P(curr_entry_ptr))
	    *keys++ = curr_entry_ptr->key;
	if (++i == bound || keys == keys_end)
	    break;
	i &= mask;
    }
    
    return keys - keys_start;
}

st_index_t
st_keys(st_table *table, st_data_t *keys, st_index_t size)
{
    return st_general_keys(table, keys, size);
}

/* See comments for function st_delete_safe.  */
st_index_t
st_keys_check(st_table *table, st_data_t *keys, st_index_t size,
              st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_keys(table, keys, size);
}

/* Set up array VALUES by at most SIZE values of head table entries.
   Return the number of values set up in array VALUES.  */
static st_index_t
st_general_values(st_table *table, st_data_t *values, st_index_t size)
{
    st_index_t i, bound, mask;
    st_data_t *values_start, *values_end;
    st_table_entry *curr_entry_ptr, *entries = table->entries;
    
    if (table->num_entries == 0 || size == 0)
        return 0;
    bound = table->entries_bound;
    st_assert (bound != 0);
    mask = entries_mask(table);
    values_start = values;
    values_end = values + size;
    for (i = table->entries_start;;) {
        curr_entry_ptr = &entries[i];
        if (! DELETED_ENTRY_P(curr_entry_ptr))
	    *values++ = curr_entry_ptr->record;
	if (++i == bound || values == values_end)
	    break;
	i &= mask;
    }
    
    return values - values_start;
}

st_index_t
st_values(st_table *table, st_data_t *values, st_index_t size)
{
    return st_general_values(table, values, size);
}

/* See comments for function st_delete_safe.  */
st_index_t
st_values_check(st_table *table, st_data_t *values, st_index_t size,
                st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_values(table, values, size);
}



/* Copyright (c) 2011 Google, Inc.
  
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:
  
   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.
  
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.
  
   CityHash, by Geoff Pike and Jyrki Alakuijala
  
   This file provides CityHash64() and related functions.
  
   It's probably possible to create even faster hash functions by
   writing a program that systematically explores some of the space of
   possible hash functions, by using SIMD instructions, or by
   compromising on hash quality.  */

static inline uint64_t Uint128Low64(uint64_t x, uint64_t y) { return x; }
static inline uint64_t Uint128High64(uint64_t x, uint64_t y) { return y; }

/* Hash 128 input bits down to 64 bits of output.  This is intended to
   be a reasonably good hash function. */
static inline uint64_t
Hash128to64(uint64_t first, uint64_t second) {
    /* Murmur-inspired hashing. */
    const uint64_t kMul = 0x9ddfea08eb382d69ULL;
    uint64_t b, a = (Uint128Low64(first, second) ^ Uint128High64(first, second)) * kMul;

    a ^= (a >> 47);
    b = (Uint128High64(first, second) ^ a) * kMul;
    b ^= (b >> 47);
    b *= kMul;
    return b;
}

static uint64_t
UNALIGNED_LOAD64(const char *p) {
    uint64_t result;
    
    memcpy(&result, p, sizeof(result));
    return result;
}

static uint32_t
UNALIGNED_LOAD32(const char *p) {
    uint32_t result;
    
    memcpy(&result, p, sizeof(result));
    return result;
}

#ifndef __BIG_ENDIAN__

#define uint32_in_expected_order(x) (x)
#define uint64_in_expected_order(x) (x)

#else

#ifdef _MSC_VER
#include <stdlib.h>
#define bswap_32(x) _byteswap_ulong(x)
#define bswap_64(x) _byteswap_uint64_t(x)

#elif defined(__APPLE__)
/* Mac OS X / Darwin features: */
#include <libkern/OSByteOrder.h>
#define bswap_32(x) OSSwapInt32(x)
#define bswap_64(x) OSSwapInt64(x)

#else
#include <byteswap.h>
#endif

#define uint32_in_expected_order(x) (bswap_32(x))
#define uint64_in_expected_order(x) (bswap_64(x))

#endif  /* __BIG_ENDIAN__ */

#if !defined(LIKELY)
#if defined(__GNUC__) || defined(__INTEL_COMPILER)
#define LIKELY(x) (__builtin_expect(!!(x), 1))
#else
#define LIKELY(x) (x)
#endif
#endif

static uint64_t
Fetch64(const char *p) {
    return uint64_in_expected_order(UNALIGNED_LOAD64(p));
}

static uint32_t
Fetch32(const char *p) {
    return uint32_in_expected_order(UNALIGNED_LOAD32(p));
}

/* Some primes between 2^63 and 2^64 for various uses. */
static const uint64_t k0 = 0xc3a5c85c97cb3127ULL;
static const uint64_t k1 = 0xb492b66fbe98f273ULL;
static const uint64_t k2 = 0x9ae16a3b2f90404fULL;
static const uint64_t k3 = 0xc949d7c7509e6557ULL;

/* Bitwise right rotate.  Normally this will compile to a single
   instruction, especially if the shift is a manifest constant.  */
static uint64_t
Rotate(uint64_t val, int shift) {
  /* Avoid shifting by 64: doing so yields an undefined result.  */
  return shift == 0 ? val : ((val >> shift) | (val << (64 - shift)));
}

/* Equivalent to Rotate(), but requires the second arg to be non-zero.
   On x86-64, and probably others, it's possible for this to compile
   to a single instruction if both args are already in registers.  */
static uint64_t
RotateByAtLeast1(uint64_t val, int shift) {
    return (val >> shift) | (val << (64 - shift));
}

static uint64_t
ShiftMix(uint64_t val) {
    return val ^ (val >> 47);
}

static uint64_t
HashLen16(uint64_t u, uint64_t v) {
    return Hash128to64(u, v);
}

static uint64_t
HashLen0to16(const char *s, size_t len) {
    if (len > 8) {
        uint64_t a = Fetch64(s);
	uint64_t b = Fetch64(s + len - 8);
	return HashLen16(a, RotateByAtLeast1(b + len, len)) ^ b;
    }
    if (len >= 4) {
        uint64_t a = Fetch32(s);
	return HashLen16(len + (a << 3), Fetch32(s + len - 4));
    }
    if (len > 0) {
        uint8_t a = s[0];
	uint8_t b = s[len >> 1];
	uint8_t c = s[len - 1];
	uint32_t y = ((uint32_t)(a) + (uint32_t)(b) << 8);
	uint32_t z = len + ((uint32_t)(c) << 2);
	return ShiftMix(y * k2 ^ z * k3) * k2;
    }
    return k2;
}

/* This probably works well for 16-byte strings as well, but it may be
   overkill in that case.  */
static uint64_t
HashLen17to32(const char *s, size_t len) {
    uint64_t a = Fetch64(s) * k1;
    uint64_t b = Fetch64(s + 8);
    uint64_t c = Fetch64(s + len - 8) * k2;
    uint64_t d = Fetch64(s + len - 16) * k0;
    return HashLen16(Rotate(a - b, 43) + Rotate(c, 30) + d,
		     a + Rotate(b ^ k3, 20) - c + len);
}

typedef struct pair64 {uint64_t first, second;} pair64;

/* Return a 16-byte hash for 48 bytes.  Quick and dirty.
   Callers do best to use "random-looking" values for a and b.  */
static pair64
WeakHashLen32WithSeeds0(uint64_t w, uint64_t x, uint64_t y, uint64_t z, uint64_t a, uint64_t b) {
    pair64 res;
    uint64_t c;
    a += w;
    b = Rotate(b + a + z, 21);
    c = a;
    a += x;
    a += y;
    b += Rotate(a, 44);
    res.first = a + z; res.second = b + c;
    return res;
}

/* Return a 16-byte hash for s[0] ... s[31], a, and b.  Quick and dirty.  */
static pair64
WeakHashLen32WithSeeds(const char* s, uint64_t a, uint64_t b) {
    return WeakHashLen32WithSeeds0(Fetch64(s),
				   Fetch64(s + 8),
				   Fetch64(s + 16),
				   Fetch64(s + 24),
				   a,
				   b);
}

/* Return an 8-byte hash for 33 to 64 bytes.  */
static uint64_t
HashLen33to64(const char *s, size_t len) {
    uint64_t z = Fetch64(s + 24);
    uint64_t a = Fetch64(s) + (len + Fetch64(s + len - 16)) * k0;
    uint64_t b = Rotate(a + z, 52);
    uint64_t c = Rotate(a, 37);
    uint64_t vf, vs, wf, ws, r;
    
    a += Fetch64(s + 8);
    c += Rotate(a, 7);
    a += Fetch64(s + 16);
    vf = a + z;
    vs = b + Rotate(a, 31) + c;
    a = Fetch64(s + 16) + Fetch64(s + len - 32);
    z = Fetch64(s + len - 8);
    b = Rotate(a + z, 52);
    c = Rotate(a, 37);
    a += Fetch64(s + len - 24);
    c += Rotate(a, 7);
    a += Fetch64(s + len - 16);
    wf = a + z;
    ws = b + Rotate(a, 31) + c;
    r = ShiftMix((vf + ws) * k2 + (wf + vs) * k0);
    return ShiftMix(r * k0 + vs) * k2;
}

static uint64_t
CityHash64(const char *s, size_t len) {
    uint64_t x, y, z, t;
    pair64 v, w;
    if (len <= 32) {
        if (len <= 16) {
	    return HashLen0to16(s, len);
	} else {
	    return HashLen17to32(s, len);
	}
    } else if (len <= 64) {
        return HashLen33to64(s, len);
    }
    
    /* For strings over 64 bytes we hash the end first, and then as we
       loop we keep 56 bytes of state: v, w, x, y, and z.  */
    x = Fetch64(s + len - 40);
    y = Fetch64(s + len - 16) + Fetch64(s + len - 56);
    z = HashLen16(Fetch64(s + len - 48) + len, Fetch64(s + len - 24));
    v = WeakHashLen32WithSeeds(s + len - 64, len, z);
    w = WeakHashLen32WithSeeds(s + len - 32, y + k1, x);
    x = x * k1 + Fetch64(s);
    
    /* Decrease len to the nearest multiple of 64, and operate on
       64-byte chunks.  */
    len = (len - 1) & ~(size_t)(63);
    do {
        x = Rotate(x + y + v.first + Fetch64(s + 8), 37) * k1;
	y = Rotate(y + v.second + Fetch64(s + 48), 42) * k1;
	x ^= w.second;
	y += v.first + Fetch64(s + 40);
	z = Rotate(z + w.first, 33) * k1;
	v = WeakHashLen32WithSeeds(s, v.second * k1, x + w.first);
	w = WeakHashLen32WithSeeds(s + 32, z + w.second, y + Fetch64(s + 16));
	t = x; x = z; z = t;
	s += 64;
	len -= 64;
    } while (len != 0);
    return HashLen16(HashLen16(v.first, w.first) + ShiftMix(y) * k1 + z,
		     HashLen16(v.second, w.second) + x);
}


static uint64_t
CityHash64WithSeeds(const char *s, size_t len, uint64_t seed0, uint64_t seed1) {
    return HashLen16(CityHash64(s, len) - seed0, seed1);
}

static uint64_t
CityHash64WithSeed(const char *s, size_t len, uint64_t seed) {
    return CityHash64WithSeeds(s, len, k2, seed);
}



st_index_t
st_hash(const void *ptr, size_t len, st_index_t h) {
    return CityHash64WithSeed(ptr, len, h);
}

static st_index_t
strhash(st_data_t arg) {
    const char *string = (const char *)arg;
    return CityHash64(string, strlen(string));
}

st_index_t
st_hash_index(st_index_t k) {
    return CityHash64((const char *) &k, sizeof (k));
}


st_index_t
st_hash_double(double d) {
    /* normalize -0.0 to 0.0 */
    if (d == 0.0) d = 0.0;
    return CityHash64((const char *) &d, sizeof (d));
}

st_index_t
st_hash_uint(st_index_t h, st_index_t i) {
    return CityHash64WithSeed((const char *) &i, sizeof (st_index_t), h);
}

st_index_t
st_hash_end(st_index_t h) {
    return h;
}

#undef st_hash_start

st_index_t
st_hash_start(st_index_t h) {
    return h;
}

/*
 * 32 bit FNV-1 and FNV-1a non-zero initial basis
 *
 * The FNV-1 initial basis is the FNV-0 hash of the following 32 octets:
 *
 *              chongo <Landon Curt Noll> /\../\
 *
 * NOTE: The \'s above are not back-slashing escape characters.
 * They are literal ASCII  backslash 0x5c characters.
 *
 * NOTE: The FNV-1a initial basis is the same value as FNV-1 by definition.
 */
#define FNV1_32A_INIT 0x811c9dc5

/*
 * 32 bit magic FNV-1a prime
 */
#define FNV_32_PRIME 0x01000193

int
st_locale_insensitive_strcasecmp(const char *s1, const char *s2)
{
    unsigned int c1, c2;

    while (1) {
        c1 = (unsigned char)*s1++;
        c2 = (unsigned char)*s2++;
        if (c1 == '\0' || c2 == '\0') {
            if (c1 != '\0') return 1;
            if (c2 != '\0') return -1;
            return 0;
        }
        if ((unsigned int)(c1 - 'A') <= ('Z' - 'A')) c1 += 'a' - 'A';
        if ((unsigned int)(c2 - 'A') <= ('Z' - 'A')) c2 += 'a' - 'A';
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
    unsigned int c1, c2;

    while (n--) {
        c1 = (unsigned char)*s1++;
        c2 = (unsigned char)*s2++;
        if (c1 == '\0' || c2 == '\0') {
            if (c1 != '\0') return 1;
            if (c2 != '\0') return -1;
            return 0;
        }
        if ((unsigned int)(c1 - 'A') <= ('Z' - 'A')) c1 += 'a' - 'A';
        if ((unsigned int)(c2 - 'A') <= ('Z' - 'A')) c2 += 'a' - 'A';
        if (c1 != c2) {
            if (c1 > c2)
                return 1;
            else
                return -1;
        }
    }
    return 0;
}

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
