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
    st_index_t hash = (st_index_t)(table->type->hash)(key);

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

/* Make table TAB empty.  */
static void
make_tab_empty(st_table *tab)
{
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
find_table_bin_ptr_and_reserve(st_table *tab, st_index_t hash_value,
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
	        bin = find_table_bin_ptr_and_reserve(tab, curr_entry_ptr->hash,
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
		        new_bin = find_table_bin_ptr_and_reserve(tab, curr_entry_ptr->hash,
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
	st_assert(bound <= new_tab->allocated_entries);
	new_entries = new_tab->entries;
	ni = 0;
	for (i = tab->entries_start;;) {
	    curr_entry_ptr = &entries[i];
	    if (! DELETED_ENTRY_P(curr_entry_ptr)) {
	        new_entries[ni] = *curr_entry_ptr;
		if (new_tab->bins != NULL) {
		    new_bin = find_table_bin_ptr_and_reserve(new_tab, curr_entry_ptr->hash,
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
#ifdef ST_DEBUG
    st_check(tab);
#endif
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

/* Return TABLE bin vlaue for HASH_VALUE and KEY.  We always find such
   bin as bins array length is bigger entries array.  The result
   bin value is always empty if the table has no entry with KEY.  If the
   table has no allocated array bins, return the entries array
   index of the searched entry or EMPTY_BIN if it is not
   found.  */
static st_bin_t
find_table_bin(st_table *table, st_index_t hash_value, st_data_t key)
{
    st_index_t ind, peterb;
    st_bin_t bin;
    st_table_entry *entries = table->entries;
    
    st_assert(table != NULL);
    if (table->bins == NULL)
	return find_entry(table, hash_value, key);
    ind = hash_bin(hash_value, table);
    peterb = hash_value;
    FOUND_BIN;
    for (;;) {
        bin = table->bins[ind];
        if (! EMPTY_OR_DELETED_BIN_P(bin)
            && PTR_EQUAL(table, &entries[bin], hash_value, key))
            break;
        else if (EMPTY_BIN_P(bin))
            break;
        ind = secondary_hash(ind, table, &peterb);
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
    st_index_t ind, peterb;
    st_bin_t *bin_ptr;
    st_table_entry *entries = table->entries;
    
    st_assert(table != NULL);
    if (table->bins == NULL) {
        *res_bin_ptr = NULL;
	return find_entry(table, hash_value, key);
    }
    ind = hash_bin(hash_value, table);
    peterb = hash_value;
    FOUND_BIN;
    for (;;) {
        bin_ptr = table->bins + ind;
        if (! EMPTY_OR_DELETED_BIN_PTR_P(bin_ptr)
            && PTR_EQUAL(table, &entries[*bin_ptr], hash_value, key))
            break;
        else if (EMPTY_BIN_PTR_P(bin_ptr))
            break;
        ind = secondary_hash(ind, table, &peterb);
        COLLISION;
    }
    *res_bin_ptr = bin_ptr;
    return *bin_ptr;
}

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
find_table_bin_ptr_and_reserve(st_table *table, st_index_t hash_value,
			       st_data_t key, st_bin_t **res_bin_ptr)
{
  st_index_t bound, ind, peterb;
    st_bin_t *bin_ptr, *first_deleted_bin_ptr;
    st_table_entry *entries;
    
    st_assert(table != NULL);
    bound = table->entries_bound;
    if ((bound != 0 && bound == table->entries_start)
	|| (bound == table->allocated_entries
	    && table->entries_start == 0))
        rebuild_table(table);
    else if (2 * table->deleted_bins >= get_bins_num(table))
        rebuild_bins(table);
    if (table->bins == NULL) {
        st_index_t bin = find_entry(table, hash_value, key);
        *res_bin_ptr = NULL;
	if (EMPTY_BIN_P(bin))
            table->num_entries++;
	return bin;
    }
    ind = hash_bin(hash_value, table);
    peterb = hash_value;
    FOUND_BIN;
    first_deleted_bin_ptr = NULL;
    entries = table->entries;
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
            if (PTR_EQUAL(table, &entries[*bin_ptr], hash_value, key))
                break;
        } else if (first_deleted_bin_ptr == NULL)
            first_deleted_bin_ptr = bin_ptr;
        ind = secondary_hash(ind, table, &peterb);
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
    bin = find_table_bin_ptr_and_reserve(table, hash_value,
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
    bin = find_table_bin_ptr_and_reserve(table, hash_value, key, &bin_ptr);
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

/*
 * hash_32 - 32 bit Fowler/Noll/Vo FNV-1a hash code
 *
 * @(#) $Hash32: Revision: 1.1 $
 * @(#) $Hash32: Id: hash_32a.c,v 1.1 2003/10/03 20:38:53 chongo Exp $
 * @(#) $Hash32: Source: /usr/local/src/cmd/fnv/RCS/hash_32a.c,v $
 *
 ***
 *
 * Fowler/Noll/Vo hash
 *
 * The basis of this hash algorithm was taken from an idea sent
 * as reviewer comments to the IEEE POSIX P1003.2 committee by:
 *
 *      Phong Vo (http://www.research.att.com/info/kpv/)
 *      Glenn Fowler (http://www.research.att.com/~gsf/)
 *
 * In a subsequent ballot round:
 *
 *      Landon Curt Noll (http://www.isthe.com/chongo/)
 *
 * improved on their algorithm.  Some people tried this hash
 * and found that it worked rather well.  In an EMail message
 * to Landon, they named it the ``Fowler/Noll/Vo'' or FNV hash.
 *
 * FNV hashes are designed to be fast while maintaining a low
 * collision rate. The FNV speed allows one to quickly hash lots
 * of data while maintaining a reasonable collision rate.  See:
 *
 *      http://www.isthe.com/chongo/tech/comp/fnv/index.html
 *
 * for more details as well as other forms of the FNV hash.
 ***
 *
 * To use the recommended 32 bit FNV-1a hash, pass FNV1_32A_INIT as the
 * Fnv32_t hashval argument to fnv_32a_buf() or fnv_32a_str().
 *
 ***
 *
 * Please do not copyright this code.  This code is in the public domain.
 *
 * LANDON CURT NOLL DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
 * INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO
 * EVENT SHALL LANDON CURT NOLL BE LIABLE FOR ANY SPECIAL, INDIRECT OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
 * USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
 * OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 * PERFORMANCE OF THIS SOFTWARE.
 *
 * By:
 *      chongo <Landon Curt Noll> /\oo/\
 *      http://www.isthe.com/chongo/
 *
 * Share and Enjoy!     :-)
 */

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

#ifdef ST_USE_FNV1
static st_index_t
strhash(st_data_t arg)
{
    register const char *string = (const char *)arg;
    register st_index_t hval = FNV1_32A_INIT;

    /*
     * FNV-1a hash each octet in the buffer
     */
    while (*string) {
        /* xor the bottom with the current octet */
        hval ^= (unsigned int)*string++;

        /* multiply by the 32 bit FNV magic prime mod 2^32 */
        hval *= FNV_32_PRIME;
    }
    return hval;
}
#else

#if !defined(UNALIGNED_WORD_ACCESS) && defined(__GNUC__) && __GNUC__ >= 6
# define UNALIGNED_WORD_ACCESS 0
#endif

#ifndef UNALIGNED_WORD_ACCESS
# if defined(__i386) || defined(__i386__) || defined(_M_IX86) || \
     defined(__x86_64) || defined(__x86_64__) || defined(_M_AMD64) || \
     defined(__powerpc64__) || \
     defined(__mc68020__)
#   define UNALIGNED_WORD_ACCESS 1
# endif
#endif
#ifndef UNALIGNED_WORD_ACCESS
# define UNALIGNED_WORD_ACCESS 0
#endif

/* MurmurHash described in http://murmurhash.googlepages.com/ */
#ifndef MURMUR
#define MURMUR 2
#endif

#define MurmurMagic_1 (st_index_t)0xc6a4a793
#define MurmurMagic_2 (st_index_t)0x5bd1e995
#if MURMUR == 1
#define MurmurMagic MurmurMagic_1
#elif MURMUR == 2
#if SIZEOF_ST_INDEX_T > 4
#define MurmurMagic ((MurmurMagic_1 << 32) | MurmurMagic_2)
#else
#define MurmurMagic MurmurMagic_2
#endif
#endif

static inline st_index_t
murmur(st_index_t h, st_index_t k, int r)
{
    const st_index_t m = MurmurMagic;
#if MURMUR == 1
    h += k;
    h *= m;
    h ^= h >> r;
#elif MURMUR == 2
    k *= m;
    k ^= k >> r;
    k *= m;

    h *= m;
    h ^= k;
#endif
    return h;
}

static inline st_index_t
murmur_finish(st_index_t h)
{
#if MURMUR == 1
    h = murmur(h, 0, 10);
    h = murmur(h, 0, 17);
#elif MURMUR == 2
    h ^= h >> 13;
    h *= MurmurMagic;
    h ^= h >> 15;
#endif
    return h;
}

#define murmur_step(h, k) murmur((h), (k), 16)

#if MURMUR == 1
#define murmur1(h) murmur_step((h), 16)
#else
#define murmur1(h) murmur_step((h), 24)
#endif

st_index_t
st_hash(const void *ptr, size_t len, st_index_t h)
{
    const char *data = ptr;
    st_index_t t = 0;

    h += 0xdeadbeef;

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
# define UNALIGNED_ADD(n) case SIZEOF_ST_INDEX_T - (n) - 1:     \
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

#if MURMUR == 2
            if (len < (size_t)align) goto skip_tail;
#endif
            h = murmur_step(h, t);
            data += pack;
            len -= pack;
        }
        else
#endif
        {
            do {
                h = murmur_step(h, *(st_index_t *)data);
                data += sizeof(st_index_t);
                len -= sizeof(st_index_t);
            } while (len >= sizeof(st_index_t));
        }
    }

    t = 0;
    switch (len) {
#ifdef WORDS_BIGENDIAN
# define UNALIGNED_ADD(n) case (n) + 1: \
        t |= data_at(n) << CHAR_BIT*(SIZEOF_ST_INDEX_T - (n) - 1)
#else
# define UNALIGNED_ADD(n) case (n) + 1: \
        t |= data_at(n) << CHAR_BIT*(n)
#endif
        UNALIGNED_ADD_ALL;
#undef UNALIGNED_ADD
#if MURMUR == 1
        h = murmur_step(h, t);
#elif MURMUR == 2
# if !UNALIGNED_WORD_ACCESS
      skip_tail:
# endif
        h ^= t;
        h *= MurmurMagic;
#endif
    }

    return murmur_finish(h);
}

st_index_t
st_hash_uint32(st_index_t h, uint32_t i)
{
    return murmur_step(h + i, 16);
}

st_index_t
st_hash_uint(st_index_t h, st_index_t i)
{
    st_index_t v = 0;
    h += i;
#ifdef WORDS_BIGENDIAN
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 12*8
    v = murmur1(v + (h >> 12*8));
#endif
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 8*8
    v = murmur1(v + (h >> 8*8));
#endif
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 4*8
    v = murmur1(v + (h >> 4*8));
#endif
#endif
    v = murmur1(v + h);
#ifndef WORDS_BIGENDIAN
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 4*8
    v = murmur1(v + (h >> 4*8));
#endif
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 8*8
    v = murmur1(v + (h >> 8*8));
#endif
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 12*8
    v = murmur1(v + (h >> 12*8));
#endif
#endif
    return v;
}

st_index_t
st_hash_end(st_index_t h)
{
    h = murmur_step(h, 10);
    h = murmur_step(h, 17);
    return h;
}

#undef st_hash_start
st_index_t
st_hash_start(st_index_t h)
{
    return h;
}

static st_index_t
strhash(st_data_t arg)
{
    register const char *string = (const char *)arg;
    return st_hash(string, strlen(string), FNV1_32A_INIT);
}
#endif

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
