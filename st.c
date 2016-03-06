/* This is a public domain general purpose hash table package
   originally written by Peter Moore @ UCB.

   The hash table data strutures were redesigned and the package was
   rewritten by Vladimir Makarov <vmakarov@redhat.com>.  */

/* The original package implemented classic bucket-based hash tables.
   To decrease pointer chasing and as a consequence to improve a data
   locality the current implementation is based on hash tables with
   open addressing.  The current elements are more compact in
   comparison with the original ones and this also improves the data
   locality.

   The hash table has two arrays called *entries* and *elements*.

   entries:
    -------
   |       |                  elements array:
   |-------|            --------------------------------
   | index |           |      | element:|        |      |
   |-------|           |      |         |        |      |
   | ...   |           | ...  | hash    |  ...   | ...  |
   |-------|           |      | key     |        |      |
   | empty |           |      | record  |        |      |
   |-------|            --------------------------------
   | ...   |                   ^                  ^
   |-------|                   |_ elements start  |_ elements bound
   |deleted|
    -------

   o The element array contains table elements in the same order as
     they were inserted.

     When the first element is deleted, a variable containing index of
     the current first element (*elements start*) is incremented.  In
     all other cases of the deletion, we just mark the element as
     deleted by using a reserved hash value.

     Such organization of the element storage makes operations of the
     table shift and the elements traversal very fast.

   o The entries provide access to the elements by their keys.  The
     key hash is mapped to an entry containing *index* of the
     corresponding element in the element array.

     The entry array size is always size of two, it makes mapping very
     fast by using the corresponding lower bits of the hash.
     Generally it is not a good idea to ignore some part of the hash.
     But alternative approach is worse.  For example, we could use a
     modulo operation for mapping and a prime number for the size of
     the entry array.  Unfortunately, the modulo operation for big
     64-bit numbers are extremely slow (it takes more than 100 cycles
     on modern Intel CPUs).

     Still other bits of the hash value are used when the mapping
     results in a collision.  In this case we use a secondary hash
     value which is a result of a function of the collision entry
     index and the original hash value.  The function choice
     guarantees that we can traverse all entries and finally find the
     corresponding entry as after several iterations the function
     becomes a full cycle linear congruential generator because it
     satisfies requirements of the Hull-Dobell theorem.

     When an element is removed from the table besides marking the
     hash in the corresponding element described above, we also mark
     the entry by a special value in order to find elements which had
     a collision with the removed elements.

     There are two reserved values for the entries.  One denotes an
     empty entry, another one denotes an entry for a deleted element.

   o The length of the entry array is always two times more than the
     element array length.  This keeps the table load factor healthy.
     The trigger of rebuilding the table is always a case when we can
     not insert an element at the end of the element array.

     Table rebuilding is done by creation of a new element array and
     entries of an appropriate size.  We could try to reuse the arrays
     in some cases by moving non-deleted elements to the array start.
     But it has a little sense as the most expensive part of
     rebuilding is element moves and such approach just complicates
     the implementation.

   This implementation speeds up the Ruby hash table benchmarks in
   average by more 50% on Intel Haswell CPU.

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

#define st_assert(cond) ((void)(0 && (cond)))

struct st_table_element {
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

/* Max power of two can be used for length of elements array.  In
   reality such length can not be used as length of entries array is
   two times more and an element and an entry size are at lest 12 and
   4 bytes.  We need this value for eraly check that the table will be
   too big.  */
#if SIZEOF_ST_INDEX_T == 8
#define MAX_POWER2 62
#else
#define MAX_POWER2 30
#endif

/* Return hash value of KEY for TABLE.  */
inline st_index_t
do_hash(st_data_t key, st_table *table) {
    st_index_t hash = (st_index_t)(table->type->hash)(key);

    /* MAX_ST_INDEX_VAL is a reserved value used for deleted element.
       Map it into another value.  Such mapping should be extremely
       rare.  */
    return hash == MAX_ST_INDEX_VAL ? 0 : hash;
}

/* Return smallest n >= 3 such 2^n > SIZE.  */
static int
get_power2(st_index_t size) {
    unsigned int n;

    for (n = 0; size != 0; n++)
        size >>= 1;
    if (n <= MAX_POWER2)
        return n < 3 ? 3 : n;
#ifndef NOT_RUBY
    /* Ran out of the table elements */
    rb_raise(rb_eRuntimeError, "st_table too big");
#endif
    /* should raise exception */
    return -1;
}

/* These macros define reserved values for empty table entry and table
   entry which contains a deleted element.  We will never use such
   values for an index in entries (see comments for MAX_POWER2).  */
#define EMPTY_ENTRY    (~(st_entry_t) 0)
#define DELETED_ENTRY  (EMPTY_ENTRY - 1)

/* Mark entry E_PTR as empty, in other words not corresponding to any
   element.  */
#define MARK_ENTRY_EMPTY(e_ptr) (*(e_ptr) = EMPTY_ENTRY)

/* Mark entry E_PTR as corresponding to a deleted table element.
   Update number of elements in the table and number of entries
   corresponding to deleted elements. */
#define MARK_ENTRY_DELETED(tab, e_ptr)                          \
    do {                                                        \
        st_assert(! EMPTY_OR_DELETED_ENTRY_PTR_P(e_ptr));       \
        *(e_ptr) = DELETED_ENTRY;                               \
        (tab)->num_elements--;                                  \
        (tab)->deleted_entries++;                               \
    } while (0)

/* Macros to check empty entries and entries corresponding deleted
   elements.  */
#define EMPTY_ENTRY_P(e) ((e) == EMPTY_ENTRY)
#define DELETED_ENTRY_P(e) ((e) == DELETED_ENTRY)
#define EMPTY_OR_DELETED_ENTRY_P(e) ((e) >= DELETED_ENTRY)

#define EMPTY_ENTRY_PTR_P(e_ptr) EMPTY_ENTRY_P(*(e_ptr))
#define DELETED_ENTRY_PTR_P(e_ptr) DELETED_ENTRY_P(*(e_ptr))
#define EMPTY_OR_DELETED_ENTRY_PTR_P(e_ptr) EMPTY_OR_DELETED_ENTRY_P(*(e_ptr))

/* Macros for marking and checking deleted elements.  */
#define MARK_ELEMENT_DELETED(el_ptr) ((el_ptr)->hash = MAX_ST_INDEX_VAL)
#define DELETED_ELEMENT_P(el_ptr) ((el_ptr)->hash == MAX_ST_INDEX_VAL)

/* Mark all entries of table TAB as empty.  */
static void
initialize_entries(st_table *tab)
{
    st_index_t i;
    st_entry_t *entries;
    st_index_t n = tab->allocated_entries;
    
    entries = tab->entries;
    /* Mark all entries empty: */
    for (i = 0; i < n; i++)
        MARK_ENTRY_EMPTY(&entries[i]);
}

/* Make table TAB empty.  */
static void
make_tab_empty(st_table *tab)
{
    tab->num_elements = 0;
    tab->deleted_entries = 0;
    tab->rebuilds_num = 0;
    tab->elements_start = tab->elements_bound = 0;
    initialize_entries(tab);
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
    FILE *f = fopen((snprintf(fname, sizeof(fname), "/tmp/col%ld", (long)getpid()), fname), "w");
    fprintf(f, "collision: %d / %d (%6.2f)\n", collision.all, collision.total,
            ((double)collision.all / (collision.total)) * 100);
    fprintf(f, "num: %d, str: %d, strcase: %d\n", collision.num, collision.str, collision.strcase);
    fclose(f);
}
#endif

/* Create and return table with TYPE which can hold at least SIZE
   elements.  The real number of elements which the table can hold is
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
    tab->allocated_elements = 1 << n;
    tab->allocated_entries = 2 * tab->allocated_elements;
    tab->entries = (st_entry_t *) malloc(tab->allocated_entries * sizeof (st_entry_t));
    tab->elements = (st_table_element *) malloc(tab->allocated_elements
                                                * sizeof(st_table_element));
    make_tab_empty(tab);
    return tab;
}

/* Create and return table with TYPE which can hold a minimal number
   of elements (see comments for get_power2).  */
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
}

/* Free TABLE space.  */
void
st_free_table(st_table *table)
{
    free(table->entries);
    free(table->elements);
    free(table);
}

/* Return byte size of memory allocted for TABLE.  */
size_t
st_memsize(const st_table *table)
{
    return(sizeof(st_table)
           + table->allocated_entries * sizeof(st_entry_t)
           + table->allocated_elements * sizeof(st_table_element));
}

static st_entry_t
find_table_entry(st_table *tab, st_index_t hash_value, st_data_t key);

static st_entry_t *
find_table_entry_ptr(st_table *tab, st_index_t hash_value, st_data_t key);

static st_entry_t *
find_table_entry_ptr_and_reserve(st_table *tab, st_index_t hash_value, st_data_t key);

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
#define FOUND_ENTRY (collision_check ? collision.total++ : (void)0)
#else
#define COLLISION
#define FOUND_ENTRY
#endif

/*  Use elements array of table TAB to initialize the entries
    array.  */
static void
rebuild_entries(st_table *tab)
{
    st_index_t i, check, bound;
    st_table_element *elements, *curr_element_ptr;
    st_entry_t *entry_ptr;
    
    initialize_entries(tab);
    bound = tab->elements_bound;
    elements = tab->elements;
    tab->deleted_entries = 0;
    check = tab->rebuilds_num;
    for (i = tab->elements_start; i < bound; i++) {
        curr_element_ptr = &elements[i];
        if (DELETED_ELEMENT_P(curr_element_ptr))
            continue;
        entry_ptr = find_table_entry_ptr_and_reserve(tab, curr_element_ptr->hash,
                                                     curr_element_ptr->key);
        st_assert(tab->rebuilds_num == check && EMPTY_ENTRY_PTR_P(entry_ptr));
        *entry_ptr = (curr_element_ptr - elements);
    }
}

/* Rebuild table TAB.  Rebuilding removes all deleted entries and
   elements and can change size of the table elements and entries
   arrays.  Rebuilding is implemented by creation a new table for
   simplicity.  */
static void
rebuild_table(st_table *tab)
{
    st_index_t i, bound;
    st_table *new_tab;
    st_table_element *elements, *new_elements;
    st_table_element *curr_element_ptr;
    st_entry_t *new_entry_ptr;
    
    st_assert(tab != NULL);
    new_tab = st_init_table_with_size(tab->type,
                                      /* Make more room. ??? */
                                      tab->allocated_elements + 1);
    st_assert(tab->elements_bound <= new_tab->allocated_elements);
    bound = tab->elements_bound;
    elements = tab->elements;
    new_elements = new_tab->elements;
    for (i = tab->elements_start; i < bound; i++) {
        curr_element_ptr = &elements[i];
        if (DELETED_ELEMENT_P(curr_element_ptr)) {
            MARK_ELEMENT_DELETED(&new_elements[i]);
            continue;
        }
        new_elements[i] = *curr_element_ptr;
        new_entry_ptr = find_table_entry_ptr_and_reserve(new_tab, curr_element_ptr->hash,
                                                         curr_element_ptr->key);
        st_assert(new_tab->rebuilds_num == 0  && EMPTY_ENTRY_PTR_P(new_entry_ptr));
        *new_entry_ptr = i;
    }
    tab->deleted_entries = 0;
    tab->allocated_entries = new_tab->allocated_entries;
    tab->allocated_elements = new_tab->allocated_elements;
    tab->rebuilds_num++;
    free(tab->entries);
    tab->entries = new_tab->entries;
    free(tab->elements);
    tab->elements = new_tab->elements;
    free(new_tab);
}

/* Return index of table TAB entry corresponding to HASH_VALUE.  */
static inline st_index_t
hash_entry(st_index_t hash_value, st_table *tab)
{
    return hash_value & (tab->allocated_entries - 1);
}

/* Return the next secondary hash index for table TAB using previous
   index IND and PERTERB.  Finally modulo of the function becomes a
   full *cycle linear congruential generator*, in other words it
   guarantees traversing all table entries in extreme case.

   According the Hull-Dobell theorem a generator
   "Xnext = (a*Xprev + c) mod m" is a full cycle generator iff
     o m and c are relatively prime
     o a-1 is divisible by all prime factors of m
     o a-1 is divisible by 4 if m is divisible by 4.

   For our case a is 5, c is 1, and m is a power of two.  */
static inline st_index_t
secondary_hash(st_index_t ind, st_table *tab, st_index_t *perterb)
{
    ind = (ind << 2) + ind + *perterb + 1;
    *perterb >>= 5;
    return hash_entry(ind, tab);
}

/* Return TABLE entry for HASH_VALUE and KEY.  We always find such
   entry as entries array length is bigger elements array.  The result
   entry is always empty if the table has no element with KEY.  */
static st_entry_t
find_table_entry(st_table *table, st_index_t hash_value, st_data_t key)
{
    st_index_t ind, peterb;
    st_entry_t entry;
    st_table_element *elements = table->elements;
    
    st_assert(table != NULL);
    ind = hash_entry(hash_value, table);
    peterb = hash_value;
    FOUND_ENTRY;
    for (;;) {
        entry = table->entries[ind];
        if (! EMPTY_OR_DELETED_ENTRY_P(entry)
            && PTR_EQUAL(table, &elements[entry], hash_value, key))
            break;
        else if (EMPTY_ENTRY_P(entry))
            break;
        ind = secondary_hash(ind, table, &peterb);
        COLLISION;
    }
    return entry;
}

/* Return pointer to TABLE entry for HASH_VALUE and KEY.  We
   always find such entry as entries array length is bigger elements
   array.  The result entry is always empty if the table has no
   element with KEY.  */
static st_entry_t *
find_table_entry_ptr(st_table *table, st_index_t hash_value, st_data_t key)
{
    st_index_t ind, peterb;
    st_entry_t *entry_ptr;
    st_table_element *elements = table->elements;
    
    st_assert(table != NULL);
    ind = hash_entry(hash_value, table);
    peterb = hash_value;
    FOUND_ENTRY;
    for (;;) {
        entry_ptr = table->entries + ind;
        if (! EMPTY_OR_DELETED_ENTRY_PTR_P(entry_ptr)
            && PTR_EQUAL(table, &elements[*entry_ptr], hash_value, key))
            break;
        else if (EMPTY_ENTRY_PTR_P(entry_ptr))
            break;
        ind = secondary_hash(ind, table, &peterb);
        COLLISION;
    }
    return entry_ptr;
}

/* Return pointer to TABLE entry for HASH_VALUE and KEY.  Reserve it
   for inclusion of the corresponding element into the table if it is
   not there yet.  We always find such entry as entries array length
   is bigger elements array.  Although we can reuse a deleted entry,
   the result entry is always empty if the table has no element with
   KEY.  */
static st_entry_t *
find_table_entry_ptr_and_reserve(st_table *table, st_index_t hash_value, st_data_t key)
{
    st_index_t ind, peterb;
    st_entry_t *entry_ptr;
    st_entry_t *first_deleted_entry_ptr;
    st_table_element *elements;
    
    st_assert(table != NULL);
    if (table->elements_bound >= table->allocated_elements)
        rebuild_table(table);
    else if (2 * table->deleted_entries >= table->allocated_entries)
        rebuild_entries(table);
    ind = hash_entry(hash_value, table);
    peterb = hash_value;
    FOUND_ENTRY;
    first_deleted_entry_ptr = NULL;
    elements = table->elements;
    for (;;) {
        entry_ptr = table->entries + ind;
        if (EMPTY_ENTRY_PTR_P(entry_ptr)) {
            table->num_elements++;
            if (first_deleted_entry_ptr != NULL) {
                /* We can reuse entry of a deleted element.  */
                entry_ptr = first_deleted_entry_ptr;
                MARK_ENTRY_EMPTY(entry_ptr);
                st_assert(table->deleted_entries > 0);
                table->deleted_entries--;
            }
            break;
        } else if (! DELETED_ENTRY_PTR_P(entry_ptr)) {
            if (PTR_EQUAL(table, &elements[*entry_ptr], hash_value, key))
                break;
        } else if (first_deleted_entry_ptr == NULL)
            first_deleted_entry_ptr = entry_ptr;
        ind = secondary_hash(ind, table, &peterb);
        COLLISION;
    }
    return entry_ptr;
}

/* Find an element with KEY in TABLE.  Return non-zero if we found it.
   Set up *RECORD to the found element record.  */
int
st_lookup(st_table *table, st_data_t key, st_data_t *value)
{
    st_entry_t entry;
    st_index_t hash = do_hash(key, table);
    
    entry = find_table_entry(table, hash, key);
    if (EMPTY_ENTRY_P(entry))
        return 0;
    if (value != 0)
        *value = table->elements[entry].record;
    return 1;
}

/* Find an element with KEY in TABLE.  Return non-zero if we found it.
   Set up *RESULT to the found table element key.  */
int
st_get_key(st_table *table, st_data_t key, st_data_t *result)
{
    st_entry_t entry;
    
    entry = find_table_entry(table, do_hash(key, table), key);
    
    if (EMPTY_ENTRY_P(entry))
        return 0;
    if (result != 0)
        *result = table->elements[entry].key;
    return 1;
}

/* Insert (KEY, VALUE) into TABLE and return zero.  If there is
   already element with KEY in the table, return nonzero and and
   update the value of the found element.  */
int
st_insert(st_table *table, st_data_t key, st_data_t value)
{
    st_table_element *element;
    st_entry_t *entry_ptr;
    st_index_t ind, hash_value;
    
    hash_value = do_hash(key, table);
    entry_ptr = find_table_entry_ptr_and_reserve(table, hash_value, key);
    if (EMPTY_ENTRY_PTR_P(entry_ptr)) {
        st_assert(table->elements_bound < table->allocated_elements);
        ind = table->elements_bound++;
        element = &table->elements[ind];
        element->hash = hash_value;
        element->key = key;
        element->record = value;
        *entry_ptr = ind;
        return 0;
    }
    table->elements[*entry_ptr].record = value;
    return 1;
}

/* Insert (KEY, VALUE) into TABLE.  The table should not have element
   with KEY before the insertion.  */
void
st_add_direct(st_table *table, st_data_t key, st_data_t value)
{
    int res = st_insert(table, key, value);

    st_assert(!res);
}

/* Insert (FUNC(KEY), VALUE) into TABLE and return zero.  If there is
   already element with KEY in the table, return nonzero and and
   update the value of the found element.  */
int
st_insert2(st_table *table, st_data_t key, st_data_t value,
           st_data_t (*func)(st_data_t))
{
    st_table_element *element;
    st_entry_t *entry_ptr;
    st_index_t ind, hash_value, check;
    
    hash_value = do_hash(key, table);
    entry_ptr = find_table_entry_ptr_and_reserve(table, hash_value, key);
    if (EMPTY_ENTRY_PTR_P(entry_ptr)) {
        st_assert(table->elements_bound < table->allocated_elements);
        check = table->rebuilds_num;
        key = (*func)(key);
        st_assert(check == table->rebuilds_num
                  && do_hash(key, table) == hash_value);
        ind = table->elements_bound++;
        element = &table->elements[ind];
        element->hash = hash_value;
        element->key = key;
        element->record = value;
        *entry_ptr = ind;
        return 0;
    }
    table->elements[*entry_ptr].record = value;
    return 1;
}

/* Return a copy of table OLD_TAB.  The result table size can shrink
   and it still contains deleted elements.  */
st_table *
st_copy(st_table *old_tab)
{
    st_table *new_tab;
    st_entry_t *old_entries, *new_entries;
    st_index_t i, n, start;
    
    new_tab = (st_table *) malloc(sizeof(st_table));
    
    *new_tab = *old_tab;
    new_tab->elements_bound -= new_tab->elements_start;
    new_tab->elements_start = 0;
    n = old_tab->allocated_entries;
    new_tab->entries = (st_entry_t *) malloc(n * sizeof(st_entry_t));
    new_tab->elements = (st_table_element *) malloc(old_tab->allocated_elements
                                                    * sizeof(st_table_element));
    start = old_tab->elements_start;
    MEMCPY(new_tab->elements, old_tab->elements + start,
           st_table_element, old_tab->elements_bound - start);
    old_entries = old_tab->entries;
    new_entries = new_tab->entries;
    for (i = 0; i < n; i++) {
        new_entries[i] = old_entries[i];
        if (! EMPTY_OR_DELETED_ENTRY_PTR_P(&new_entries[i]))
            new_entries[i] -= start;
    }
    return new_tab;
}

/* Delete element with KEY from table TAB, set up *VALUE (unless VALUE
   is zero) from deleted table element, and return non-zero.  If there
   is no element with KEY in the table, clear *VALUE (unless VALUE is
   zero), and return zero.  */
static int
st_general_delete(st_table *tab, st_data_t *key, st_data_t *value)
{
    st_index_t n;
    st_table_element *element, *elements;
    st_entry_t *entry_ptr;
    
    st_assert(tab != NULL);
    entry_ptr = find_table_entry_ptr(tab, do_hash(*key, tab), *key);
    if (EMPTY_ENTRY_PTR_P(entry_ptr)) {
        if (value != 0) *value = 0;
        return 0;
    }
    elements = tab->elements;
    element = &elements[*entry_ptr];
    MARK_ENTRY_DELETED(tab, entry_ptr);
    *key = element->key;
    if (value != 0) *value = element->record;
    MARK_ELEMENT_DELETED(element);
    n = element - elements;
    if (n == tab->elements_start)
        tab->elements_start++;
    else if (n + 1 == tab->elements_bound)
        tab->elements_bound--;
    return 1;
}

int
st_delete(st_table *tab, st_data_t *key, st_data_t *value)
{
    return st_general_delete(tab, key, value);
}

/* The function and other functions with suffix '_safe' or '_check'
   are originated from previous implementation of the hash tables.  It
   was necessary for correct deleting elements during traversing
   tables.  The current implementation permits deletion during
   traversing without a specific way to do this.  */
int
st_delete_safe(st_table *tab, st_data_t *key, st_data_t *value,
               st_data_t never ATTRIBUTE_UNUSED)
{
    return st_general_delete(tab, key, value);
}

/* If TABLE is empty, clear *VALUE (unless VALUE is zero), and return
   zero.  Otherwise, remove the first element in the table.  Return
   its key through KEY and its record through VALUE (unless VALUE is
   zero).  */
int
st_shift(st_table *table, st_data_t *key, st_data_t *value)
{
    st_index_t i, bound;
    st_entry_t *entry;
    st_table_element *elements, *curr_element_ptr;
    
    if (table->num_elements == 0) {
        if (value != 0) *value = 0;
        return 0;
    }
    
    elements = table->elements;
    bound = table->elements_bound;
    for (i = table->elements_start; i < bound; i++) {
        curr_element_ptr = &elements[i];
        if (DELETED_ELEMENT_P(curr_element_ptr))
            continue;
        if (value != 0) *value = curr_element_ptr->record;
        *key = curr_element_ptr->key;
        entry = find_table_entry_ptr(table, curr_element_ptr->hash,
                                     curr_element_ptr->key);
        st_assert(! EMPTY_ENTRY_PTR_P(entry)
                  && &elements[*entry] == curr_element_ptr);
        MARK_ELEMENT_DELETED(curr_element_ptr);
        MARK_ENTRY_DELETED(table, entry);
        table->elements_start = i + 1;
        return 1;
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

/* Find element with KEY in TABLE, call FUNC with key, value of the
   found element, and non-zero as the 3rd argument.  If the element is
   not found, call FUNC with KEY, and 2 zero arguments.  If the call
   returns ST_CONTINUE, the table will have an element with key and
   value returned by FUNC through the 1st and 2nd parameters.  If the
   call of FUNC returns ST_DELETE, the table will not have element
   with KEY.  The function returns flag of that the element with KEY
   was in the table before the call.  */
int
st_update(st_table *table, st_data_t key, st_update_callback_func *func, st_data_t arg)
{
    st_table_element *element, *elements;
    st_entry_t *entry_ptr;
    st_data_t value = 0, old_key;
    st_index_t n, check;
    int retval, existing = 0;
    
    entry_ptr = find_table_entry_ptr(table, do_hash(key, table), key);
    elements = table->elements;
    element = &elements[*entry_ptr];
    if (! EMPTY_ENTRY_PTR_P(entry_ptr)) {
        key = element->key;
        value = element->record;
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
            element->key = key;
        }
        element->record = value;
        break;
    case ST_DELETE:
        if (existing) {
            MARK_ELEMENT_DELETED(element);
            MARK_ENTRY_DELETED(table, entry_ptr);
            n = element - table->elements;
            if (n == table->elements_start)
                table->elements_start++;
            else if (n + 1 == table->elements_bound)
                table->elements_bound--;
        }
        break;
    }
    return existing;
}

/* Traverse all elements in table TAB calling FUNC with current
   element key and value and zero.  If the call returns ST_STOP, stop
   traversing.  If the call returns ST_DELETE, delete the current
   element from the table.  In case of ST_CHECK or ST_CONTINUE,
   continue traversing.  The function always returns zero.  */
static int
st_general_foreach(st_table *tab, int (*func)(ANYARGS), st_data_t arg)
{
  st_entry_t *entry_ptr;
  st_table_element *elements, *curr_element_ptr;
  enum st_retval retval;
  st_index_t i, n, hash, rebuilds_num;
  st_data_t key;
  
  elements = tab->elements;
  for (i = tab->elements_start; i < tab->elements_bound; i++) {
      /* Bound can be changed inside the loop */
      curr_element_ptr = &elements[i];
      if (DELETED_ELEMENT_P(curr_element_ptr))
          continue;
      key = curr_element_ptr->key;
      rebuilds_num = tab->rebuilds_num;
      hash = curr_element_ptr->hash;
      retval = (*func)(key, curr_element_ptr->record, arg, 0);
      if (rebuilds_num != tab->rebuilds_num) {
          elements = tab->elements;
          curr_element_ptr = &elements[i];
      }
      switch (retval) {
      case ST_CHECK:
          break;
      case ST_CONTINUE:
          break;
      case ST_STOP:
          return 0;
      case ST_DELETE:
          entry_ptr = find_table_entry_ptr(tab, hash, curr_element_ptr->key);
          if (! EMPTY_ENTRY_PTR_P(entry_ptr)) {
              st_assert(&elements[*entry_ptr] == curr_element_ptr);
              MARK_ELEMENT_DELETED(curr_element_ptr);
              MARK_ENTRY_DELETED(tab, entry_ptr);
              n = curr_element_ptr - elements;
              if (n == tab->elements_start)
                  tab->elements_start++;
              else if (n + 1 == tab->elements_bound)
                  tab->elements_bound--;
          }
          break;
      }
  }
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

/* Set up array KEYS by at most SIZE keys of head table elements.
   Return the number of keys set up in array KEYS.  */
static st_index_t
st_general_keys(st_table *table, st_data_t *keys, st_index_t size)
{
    st_index_t i, bound;
    st_data_t key;
    st_data_t *keys_start = keys;
    st_data_t *keys_end = keys + size;
    st_table_element *curr_element_ptr, *elements = table->elements;
    
    bound = table->elements_bound;
    for (i = table->elements_start; i < bound && keys < keys_end; i++) {
        curr_element_ptr = &elements[i];
        if (DELETED_ELEMENT_P(curr_element_ptr))
            continue;
        key = curr_element_ptr->key;
        *keys++ = key;
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

/* Set up array VALUES by at most SIZE values of head table elements.
   Return the number of values set up in array VALUES.  */
static st_index_t
st_general_values(st_table *table, st_data_t *values, st_index_t size)
{
    st_index_t i, bound;
    st_data_t *values_start = values;
    st_data_t *values_end = values + size;
    st_table_element *curr_element_ptr, *elements = table->elements;
    
    bound = table->elements_bound;
    for (i = table->elements_start; i < bound && values < values_end; i++) {
        curr_element_ptr = &elements[i];
        if (DELETED_ELEMENT_P(curr_element_ptr))
            continue;
        *values++ = curr_element_ptr->record;
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
