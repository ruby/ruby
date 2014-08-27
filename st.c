/* This is a public domain general purpose hash table package written by Peter Moore @ UCB. */

/* static	char	sccsid[] = "@(#) st.c 5.1 89/12/14 Crucible"; */

#ifdef NOT_RUBY
#include "regint.h"
#include "st.h"
#else
#include "ruby/ruby.h"
#endif

#include <stdio.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <string.h>

typedef struct st_table_entry st_table_entry;

struct st_table_entry {
    st_index_t hash;
    st_data_t key;
    st_data_t record;
    st_table_entry *next;
    st_table_entry *fore, *back;
};

typedef struct st_packed_entry {
    st_index_t hash;
    st_data_t key, val;
} st_packed_entry;

#define STATIC_ASSERT(name, expr) typedef int static_assert_##name##_check[(expr) ? 1 : -1];

#define ST_DEFAULT_MAX_DENSITY 5
#define ST_DEFAULT_INIT_TABLE_SIZE 16
#define ST_DEFAULT_PACKED_TABLE_SIZE 18
#define PACKED_UNIT (int)(sizeof(st_packed_entry) / sizeof(st_table_entry*))
#define MAX_PACKED_HASH (int)(ST_DEFAULT_PACKED_TABLE_SIZE * sizeof(st_table_entry*) / sizeof(st_packed_entry))

STATIC_ASSERT(st_packed_entry, sizeof(st_packed_entry) == sizeof(st_table_entry*[PACKED_UNIT]))
STATIC_ASSERT(st_packed_bins, sizeof(st_packed_entry[MAX_PACKED_HASH]) <= sizeof(st_table_entry*[ST_DEFAULT_PACKED_TABLE_SIZE]))

    /*
     * DEFAULT_MAX_DENSITY is the default for the largest we allow the
     * average number of items per bin before increasing the number of
     * bins
     *
     * DEFAULT_INIT_TABLE_SIZE is the default for the number of bins
     * allocated initially
     *
     */

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

static void rehash(st_table *);

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

#define numberof(array) (int)(sizeof(array) / sizeof((array)[0]))

#define EQUAL(table,x,y) ((x)==(y) || (*(table)->type->compare)((x),(y)) == 0)

#define do_hash(key,table) (st_index_t)(*(table)->type->hash)((key))
#define hash_pos(h,n) ((h) & (n - 1))
#define do_hash_bin(key,table) hash_pos(do_hash((key), (table)), (table)->num_bins)

/* preparation for possible allocation improvements */
#define st_alloc_entry() (st_table_entry *)malloc(sizeof(st_table_entry))
#define st_free_entry(entry) free(entry)
#define st_alloc_table() (st_table *)malloc(sizeof(st_table))
#define st_dealloc_table(table) free(table)
#define st_alloc_bins(size) (st_table_entry **)calloc(size, sizeof(st_table_entry *))
#define st_free_bins(bins, size) free(bins)
static inline st_table_entry**
st_realloc_bins(st_table_entry **bins, st_index_t newsize, st_index_t oldsize)
{
    bins = (st_table_entry **)realloc(bins, newsize * sizeof(st_table_entry *));
    MEMZERO(bins, st_table_entry*, newsize);
    return bins;
}

/* Shortcut */
#define bins as.big.bins
#define head as.big.head
#define tail as.big.tail
#define real_entries as.packed.real_entries

/* preparation for possible packing improvements */
#define PACKED_BINS(table) ((table)->as.packed.entries)
#define PACKED_ENT(table, i) PACKED_BINS(table)[i]
#define PKEY(table, i) PACKED_ENT((table), (i)).key
#define PVAL(table, i) PACKED_ENT((table), (i)).val
#define PHASH(table, i) PACKED_ENT((table), (i)).hash
#define PKEY_SET(table, i, v) (PKEY((table), (i)) = (v))
#define PVAL_SET(table, i, v) (PVAL((table), (i)) = (v))
#define PHASH_SET(table, i, v) (PHASH((table), (i)) = (v))

/* this function depends much on packed layout, so that it placed here */
static inline void
remove_packed_entry(st_table *table, st_index_t i)
{
    table->real_entries--;
    table->num_entries--;
    if (i < table->real_entries) {
	MEMMOVE(&PACKED_ENT(table, i), &PACKED_ENT(table, i+1),
		st_packed_entry, table->real_entries - i);
    }
}

static inline void
remove_safe_packed_entry(st_table *table, st_index_t i, st_data_t never)
{
    table->num_entries--;
    PKEY_SET(table, i, never);
    PVAL_SET(table, i, never);
    PHASH_SET(table, i, 0);
}

static st_index_t
new_size(st_index_t size)
{
    st_index_t i;

    for (i=3; i<31; i++) {
	if ((st_index_t)(1<<i) > size) return 1<<i;
    }
#ifndef NOT_RUBY
    rb_raise(rb_eRuntimeError, "st_table too big");
#endif
    return -1;			/* should raise exception */
}

#ifdef HASH_LOG
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
static struct {
    int all, total, num, str, strcase;
}  collision;
static int init_st = 0;

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

st_table*
st_init_table_with_size(const struct st_hash_type *type, st_index_t size)
{
    st_table *tbl;

#ifdef HASH_LOG
# if HASH_LOG+0 < 0
    {
	const char *e = getenv("ST_HASH_LOG");
	if (!e || !*e) init_st = 1;
    }
# endif
    if (init_st == 0) {
	init_st = 1;
	atexit(stat_col);
    }
#endif


    tbl = st_alloc_table();
    tbl->type = type;
    tbl->num_entries = 0;
    tbl->entries_packed = size <= MAX_PACKED_HASH;
    if (tbl->entries_packed) {
	size = ST_DEFAULT_PACKED_TABLE_SIZE;
    }
    else {
	size = new_size(size);	/* round up to power-of-two */
    }
    tbl->num_bins = size;
    tbl->bins = st_alloc_bins(size);
    tbl->head = 0;
    tbl->tail = 0;

    return tbl;
}

st_table*
st_init_table(const struct st_hash_type *type)
{
    return st_init_table_with_size(type, 0);
}

st_table*
st_init_numtable(void)
{
    return st_init_table(&type_numhash);
}

st_table*
st_init_numtable_with_size(st_index_t size)
{
    return st_init_table_with_size(&type_numhash, size);
}

st_table*
st_init_strtable(void)
{
    return st_init_table(&type_strhash);
}

st_table*
st_init_strtable_with_size(st_index_t size)
{
    return st_init_table_with_size(&type_strhash, size);
}

st_table*
st_init_strcasetable(void)
{
    return st_init_table(&type_strcasehash);
}

st_table*
st_init_strcasetable_with_size(st_index_t size)
{
    return st_init_table_with_size(&type_strcasehash, size);
}

void
st_clear(st_table *table)
{
    register st_table_entry *ptr, *next;
    st_index_t i;

    if (table->entries_packed) {
        table->num_entries = 0;
        table->real_entries = 0;
        return;
    }

    for (i = 0; i < table->num_bins; i++) {
	ptr = table->bins[i];
	table->bins[i] = 0;
	while (ptr != 0) {
	    next = ptr->next;
	    st_free_entry(ptr);
	    ptr = next;
	}
    }
    table->num_entries = 0;
    table->head = 0;
    table->tail = 0;
}

void
st_free_table(st_table *table)
{
    st_clear(table);
    st_free_bins(table->bins, table->num_bins);
    st_dealloc_table(table);
}

size_t
st_memsize(const st_table *table)
{
    if (table->entries_packed) {
	return table->num_bins * sizeof (void *) + sizeof(st_table);
    }
    else {
	return table->num_entries * sizeof(struct st_table_entry) + table->num_bins * sizeof (void *) + sizeof(st_table);
    }
}

#define PTR_NOT_EQUAL(table, ptr, hash_val, key) \
((ptr) != 0 && ((ptr)->hash != (hash_val) || !EQUAL((table), (key), (ptr)->key)))

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
#define COLLISION (collision_check ? count_collision(table->type) : (void)0)
#define FOUND_ENTRY (collision_check ? collision.total++ : (void)0)
#else
#define COLLISION
#define FOUND_ENTRY
#endif

#define FIND_ENTRY(table, ptr, hash_val, bin_pos) \
    ((ptr) = find_entry((table), key, (hash_val), ((bin_pos) = hash_pos(hash_val, (table)->num_bins))))

static st_table_entry *
find_entry(st_table *table, st_data_t key, st_index_t hash_val, st_index_t bin_pos)
{
    register st_table_entry *ptr = table->bins[bin_pos];
    FOUND_ENTRY;
    if (PTR_NOT_EQUAL(table, ptr, hash_val, key)) {
	COLLISION;
	while (PTR_NOT_EQUAL(table, ptr->next, hash_val, key)) {
	    ptr = ptr->next;
	}
	ptr = ptr->next;
    }
    return ptr;
}

static inline st_index_t
find_packed_index_from(st_table *table, st_index_t hash_val, st_data_t key, st_index_t i)
{
    while (i < table->real_entries &&
	   (PHASH(table, i) != hash_val || !EQUAL(table, key, PKEY(table, i)))) {
	i++;
    }
    return i;
}

static inline st_index_t
find_packed_index(st_table *table, st_index_t hash_val, st_data_t key)
{
    return find_packed_index_from(table, hash_val, key, 0);
}

#define collision_check 0

int
st_lookup(st_table *table, register st_data_t key, st_data_t *value)
{
    st_index_t hash_val;
    register st_table_entry *ptr;

    hash_val = do_hash(key, table);

    if (table->entries_packed) {
	st_index_t i = find_packed_index(table, hash_val, key);
	if (i < table->real_entries) {
	    if (value != 0) *value = PVAL(table, i);
	    return 1;
	}
        return 0;
    }

    ptr = find_entry(table, key, hash_val, hash_pos(hash_val, table->num_bins));

    if (ptr == 0) {
	return 0;
    }
    else {
	if (value != 0) *value = ptr->record;
	return 1;
    }
}

int
st_get_key(st_table *table, register st_data_t key, st_data_t *result)
{
    st_index_t hash_val;
    register st_table_entry *ptr;

    hash_val = do_hash(key, table);

    if (table->entries_packed) {
	st_index_t i = find_packed_index(table, hash_val, key);
	if (i < table->real_entries) {
	    if (result != 0) *result = PKEY(table, i);
	    return 1;
	}
        return 0;
    }

    ptr = find_entry(table, key, hash_val, hash_pos(hash_val, table->num_bins));

    if (ptr == 0) {
	return 0;
    }
    else {
	if (result != 0)  *result = ptr->key;
	return 1;
    }
}

#undef collision_check
#define collision_check 1

static inline st_table_entry *
new_entry(st_table * table, st_data_t key, st_data_t value,
	st_index_t hash_val, register st_index_t bin_pos)
{
    register st_table_entry *entry = st_alloc_entry();

    entry->next = table->bins[bin_pos];
    table->bins[bin_pos] = entry;
    entry->hash = hash_val;
    entry->key = key;
    entry->record = value;

    return entry;
}

static inline void
add_direct(st_table *table, st_data_t key, st_data_t value,
	   st_index_t hash_val, register st_index_t bin_pos)
{
    register st_table_entry *entry;
    if (table->num_entries > ST_DEFAULT_MAX_DENSITY * table->num_bins) {
	rehash(table);
        bin_pos = hash_pos(hash_val, table->num_bins);
    }

    entry = new_entry(table, key, value, hash_val, bin_pos);

    if (table->head != 0) {
	entry->fore = 0;
	(entry->back = table->tail)->fore = entry;
	table->tail = entry;
    }
    else {
	table->head = table->tail = entry;
	entry->fore = entry->back = 0;
    }
    table->num_entries++;
}

static void
unpack_entries(register st_table *table)
{
    st_index_t i;
    st_packed_entry packed_bins[MAX_PACKED_HASH];
    register st_table_entry *entry, *preventry = 0, **chain;
    st_table tmp_table = *table;

    MEMCPY(packed_bins, PACKED_BINS(table), st_packed_entry, MAX_PACKED_HASH);
    table->as.packed.entries = packed_bins;
    tmp_table.entries_packed = 0;
#if ST_DEFAULT_INIT_TABLE_SIZE == ST_DEFAULT_PACKED_TABLE_SIZE
    MEMZERO(tmp_table.bins, st_table_entry*, tmp_table.num_bins);
#else
    tmp_table.bins = st_realloc_bins(tmp_table.bins, ST_DEFAULT_INIT_TABLE_SIZE, tmp_table.num_bins);
    tmp_table.num_bins = ST_DEFAULT_INIT_TABLE_SIZE;
#endif
    i = 0;
    chain = &tmp_table.head;
    do {
	st_data_t key = packed_bins[i].key;
	st_data_t val = packed_bins[i].val;
	st_index_t hash = packed_bins[i].hash;
	entry = new_entry(&tmp_table, key, val, hash,
			  hash_pos(hash, ST_DEFAULT_INIT_TABLE_SIZE));
	*chain = entry;
	entry->back = preventry;
	preventry = entry;
	chain = &entry->fore;
    } while (++i < MAX_PACKED_HASH);
    *chain = NULL;
    tmp_table.tail = entry;
    *table = tmp_table;
}

static void
add_packed_direct(st_table *table, st_data_t key, st_data_t value, st_index_t hash_val)
{
    if (table->real_entries < MAX_PACKED_HASH) {
	st_index_t i = table->real_entries++;
	PKEY_SET(table, i, key);
	PVAL_SET(table, i, value);
	PHASH_SET(table, i, hash_val);
	table->num_entries++;
    }
    else {
	unpack_entries(table);
	add_direct(table, key, value, hash_val, hash_pos(hash_val, table->num_bins));
    }
}


int
st_insert(register st_table *table, register st_data_t key, st_data_t value)
{
    st_index_t hash_val;
    register st_index_t bin_pos;
    register st_table_entry *ptr;

    hash_val = do_hash(key, table);

    if (table->entries_packed) {
	st_index_t i = find_packed_index(table, hash_val, key);
	if (i < table->real_entries) {
	    PVAL_SET(table, i, value);
	    return 1;
        }
	add_packed_direct(table, key, value, hash_val);
	return 0;
    }

    FIND_ENTRY(table, ptr, hash_val, bin_pos);

    if (ptr == 0) {
	add_direct(table, key, value, hash_val, bin_pos);
	return 0;
    }
    else {
	ptr->record = value;
	return 1;
    }
}

int
st_insert2(register st_table *table, register st_data_t key, st_data_t value,
	   st_data_t (*func)(st_data_t))
{
    st_index_t hash_val;
    register st_index_t bin_pos;
    register st_table_entry *ptr;

    hash_val = do_hash(key, table);

    if (table->entries_packed) {
	st_index_t i = find_packed_index(table, hash_val, key);
	if (i < table->real_entries) {
	    PVAL_SET(table, i, value);
	    return 1;
	}
	key = (*func)(key);
	add_packed_direct(table, key, value, hash_val);
	return 0;
    }

    FIND_ENTRY(table, ptr, hash_val, bin_pos);

    if (ptr == 0) {
	key = (*func)(key);
	add_direct(table, key, value, hash_val, bin_pos);
	return 0;
    }
    else {
	ptr->record = value;
	return 1;
    }
}

void
st_add_direct(st_table *table, st_data_t key, st_data_t value)
{
    st_index_t hash_val;

    hash_val = do_hash(key, table);
    if (table->entries_packed) {
	add_packed_direct(table, key, value, hash_val);
	return;
    }

    add_direct(table, key, value, hash_val, hash_pos(hash_val, table->num_bins));
}

static void
rehash(register st_table *table)
{
    register st_table_entry *ptr, **new_bins;
    st_index_t new_num_bins, hash_val;

    new_num_bins = new_size(table->num_bins+1);
    new_bins = st_realloc_bins(table->bins, new_num_bins, table->num_bins);
    table->num_bins = new_num_bins;
    table->bins = new_bins;

    if ((ptr = table->head) != 0) {
	do {
	    hash_val = hash_pos(ptr->hash, new_num_bins);
	    ptr->next = new_bins[hash_val];
	    new_bins[hash_val] = ptr;
	} while ((ptr = ptr->fore) != 0);
    }
}

st_table*
st_copy(st_table *old_table)
{
    st_table *new_table;
    st_table_entry *ptr, *entry, *prev, **tailp;
    st_index_t num_bins = old_table->num_bins;
    st_index_t hash_val;

    new_table = st_alloc_table();
    if (new_table == 0) {
	return 0;
    }

    *new_table = *old_table;
    new_table->bins = st_alloc_bins(num_bins);

    if (new_table->bins == 0) {
	st_dealloc_table(new_table);
	return 0;
    }

    if (old_table->entries_packed) {
        MEMCPY(new_table->bins, old_table->bins, st_table_entry*, old_table->num_bins);
        return new_table;
    }

    if ((ptr = old_table->head) != 0) {
	prev = 0;
	tailp = &new_table->head;
	do {
	    entry = st_alloc_entry();
	    if (entry == 0) {
		st_free_table(new_table);
		return 0;
	    }
	    *entry = *ptr;
	    hash_val = hash_pos(entry->hash, num_bins);
	    entry->next = new_table->bins[hash_val];
	    new_table->bins[hash_val] = entry;
	    entry->back = prev;
	    *tailp = prev = entry;
	    tailp = &entry->fore;
	} while ((ptr = ptr->fore) != 0);
	new_table->tail = prev;
    }

    return new_table;
}

static inline void
remove_entry(st_table *table, st_table_entry *ptr)
{
    if (ptr->fore == 0 && ptr->back == 0) {
	table->head = 0;
	table->tail = 0;
    }
    else {
	st_table_entry *fore = ptr->fore, *back = ptr->back;
	if (fore) fore->back = back;
	if (back) back->fore = fore;
	if (ptr == table->head) table->head = fore;
	if (ptr == table->tail) table->tail = back;
    }
    table->num_entries--;
}

int
st_delete(register st_table *table, register st_data_t *key, st_data_t *value)
{
    st_index_t hash_val;
    st_table_entry **prev;
    register st_table_entry *ptr;

    hash_val = do_hash(*key, table);

    if (table->entries_packed) {
	st_index_t i = find_packed_index(table, hash_val, *key);
	if (i < table->real_entries) {
	    if (value != 0) *value = PVAL(table, i);
	    *key = PKEY(table, i);
	    remove_packed_entry(table, i);
	    return 1;
        }
        if (value != 0) *value = 0;
        return 0;
    }

    prev = &table->bins[hash_pos(hash_val, table->num_bins)];
    for (;(ptr = *prev) != 0; prev = &ptr->next) {
	if (EQUAL(table, *key, ptr->key)) {
	    *prev = ptr->next;
	    remove_entry(table, ptr);
	    if (value != 0) *value = ptr->record;
	    *key = ptr->key;
	    st_free_entry(ptr);
	    return 1;
	}
    }

    if (value != 0) *value = 0;
    return 0;
}

int
st_delete_safe(register st_table *table, register st_data_t *key, st_data_t *value, st_data_t never)
{
    st_index_t hash_val;
    register st_table_entry *ptr;

    hash_val = do_hash(*key, table);

    if (table->entries_packed) {
	st_index_t i = find_packed_index(table, hash_val, *key);
	if (i < table->real_entries) {
	    if (value != 0) *value = PVAL(table, i);
	    *key = PKEY(table, i);
	    remove_safe_packed_entry(table, i, never);
	    return 1;
	}
	if (value != 0) *value = 0;
	return 0;
    }

    ptr = table->bins[hash_pos(hash_val, table->num_bins)];

    for (; ptr != 0; ptr = ptr->next) {
	if ((ptr->key != never) && EQUAL(table, ptr->key, *key)) {
	    remove_entry(table, ptr);
	    *key = ptr->key;
	    if (value != 0) *value = ptr->record;
	    ptr->key = ptr->record = never;
	    return 1;
	}
    }

    if (value != 0) *value = 0;
    return 0;
}

int
st_shift(register st_table *table, register st_data_t *key, st_data_t *value)
{
    st_table_entry **prev;
    register st_table_entry *ptr;

    if (table->num_entries == 0) {
        if (value != 0) *value = 0;
        return 0;
    }

    if (table->entries_packed) {
        if (value != 0) *value = PVAL(table, 0);
        *key = PKEY(table, 0);
        remove_packed_entry(table, 0);
        return 1;
    }

    prev = &table->bins[hash_pos(table->head->hash, table->num_bins)];
    while ((ptr = *prev) != table->head) prev = &ptr->next;
    *prev = ptr->next;
    if (value != 0) *value = ptr->record;
    *key = ptr->key;
    remove_entry(table, ptr);
    st_free_entry(ptr);
    return 1;
}

void
st_cleanup_safe(st_table *table, st_data_t never)
{
    st_table_entry *ptr, **last, *tmp;
    st_index_t i;

    if (table->entries_packed) {
	st_index_t i = 0, j = 0;
	while (PKEY(table, i) != never) {
	    if (i++ == table->real_entries) return;
	}
	for (j = i; ++i < table->real_entries;) {
	    if (PKEY(table, i) == never) continue;
	    PACKED_ENT(table, j) = PACKED_ENT(table, i);
	    j++;
	}
	table->real_entries = j;
	/* table->num_entries really should be equal j at this moment, but let set it anyway */
	table->num_entries = j;
	return;
    }

    for (i = 0; i < table->num_bins; i++) {
	ptr = *(last = &table->bins[i]);
	while (ptr != 0) {
	    if (ptr->key == never) {
		tmp = ptr;
		*last = ptr = ptr->next;
		st_free_entry(tmp);
	    }
	    else {
		ptr = *(last = &ptr->next);
	    }
	}
    }
}

int
st_update(st_table *table, st_data_t key, st_update_callback_func *func, st_data_t arg)
{
    st_index_t hash_val, bin_pos;
    register st_table_entry *ptr, **last, *tmp;
    st_data_t value = 0, old_key;
    int retval, existing = 0;

    hash_val = do_hash(key, table);

    if (table->entries_packed) {
	st_index_t i = find_packed_index(table, hash_val, key);
	if (i < table->real_entries) {
	    key = PKEY(table, i);
	    value = PVAL(table, i);
	    existing = 1;
	}
	{
	    old_key = key;
	    retval = (*func)(&key, &value, arg, existing);
	    if (!table->entries_packed) {
		FIND_ENTRY(table, ptr, hash_val, bin_pos);
		goto unpacked;
	    }
	    switch (retval) {
	      case ST_CONTINUE:
		if (!existing) {
		    add_packed_direct(table, key, value, hash_val);
		    break;
		}
		if (old_key != key) {
		    PKEY(table, i) = key;
		}
		PVAL_SET(table, i, value);
		break;
	      case ST_DELETE:
		if (!existing) break;
		remove_packed_entry(table, i);
	    }
	}
	return existing;
    }

    FIND_ENTRY(table, ptr, hash_val, bin_pos);

    if (ptr != 0) {
	key = ptr->key;
	value = ptr->record;
	existing = 1;
    }
    {
	old_key = key;
	retval = (*func)(&key, &value, arg, existing);
      unpacked:
	switch (retval) {
	  case ST_CONTINUE:
	    if (!existing) {
		add_direct(table, key, value, hash_val, hash_pos(hash_val, table->num_bins));
		break;
	    }
	    if (old_key != key) {
		ptr->key = key;
	    }
	    ptr->record = value;
	    break;
	  case ST_DELETE:
	    if (!existing) break;
	    last = &table->bins[bin_pos];
	    for (; (tmp = *last) != 0; last = &tmp->next) {
		if (ptr == tmp) {
		    *last = ptr->next;
		    remove_entry(table, ptr);
		    st_free_entry(ptr);
		    break;
		}
	    }
	    break;
	}
	return existing;
    }
}

int
st_foreach_check(st_table *table, int (*func)(ANYARGS), st_data_t arg, st_data_t never)
{
    st_table_entry *ptr, **last, *tmp;
    enum st_retval retval;
    st_index_t i;

    if (table->entries_packed) {
	for (i = 0; i < table->real_entries; i++) {
	    st_data_t key, val;
	    st_index_t hash;
	    key = PKEY(table, i);
	    val = PVAL(table, i);
	    hash = PHASH(table, i);
	    if (key == never) continue;
	    retval = (*func)(key, val, arg, 0);
	    if (!table->entries_packed) {
		FIND_ENTRY(table, ptr, hash, i);
		if (retval == ST_CHECK) {
		    if (!ptr) goto deleted;
		    goto unpacked_continue;
		}
		goto unpacked;
	    }
	    switch (retval) {
	      case ST_CHECK:	/* check if hash is modified during iteration */
		if (PHASH(table, i) == 0 && PKEY(table, i) == never) {
		    break;
		}
		i = find_packed_index_from(table, hash, key, i);
		if (i >= table->real_entries) {
		    i = find_packed_index(table, hash, key);
		    if (i >= table->real_entries) goto deleted;
		}
		/* fall through */
	      case ST_CONTINUE:
		break;
	      case ST_STOP:
		return 0;
	      case ST_DELETE:
		remove_safe_packed_entry(table, i, never);
		break;
	    }
	}
	return 0;
    }
    else {
	ptr = table->head;
    }

    if (ptr != 0) {
	do {
	    if (ptr->key == never)
		goto unpacked_continue;
	    i = hash_pos(ptr->hash, table->num_bins);
	    retval = (*func)(ptr->key, ptr->record, arg, 0);
	  unpacked:
	    switch (retval) {
	      case ST_CHECK:	/* check if hash is modified during iteration */
		for (tmp = table->bins[i]; tmp != ptr; tmp = tmp->next) {
		    if (!tmp) {
		      deleted:
			/* call func with error notice */
			retval = (*func)(0, 0, arg, 1);
			return 1;
		    }
		}
		/* fall through */
	      case ST_CONTINUE:
	      unpacked_continue:
		ptr = ptr->fore;
		break;
	      case ST_STOP:
		return 0;
	      case ST_DELETE:
		last = &table->bins[hash_pos(ptr->hash, table->num_bins)];
		for (; (tmp = *last) != 0; last = &tmp->next) {
		    if (ptr == tmp) {
			tmp = ptr->fore;
			remove_entry(table, ptr);
			ptr->key = ptr->record = never;
			ptr->hash = 0;
			ptr = tmp;
			break;
		    }
		}
	    }
	} while (ptr && table->head);
    }
    return 0;
}

int
st_foreach(st_table *table, int (*func)(ANYARGS), st_data_t arg)
{
    st_table_entry *ptr, **last, *tmp;
    enum st_retval retval;
    st_index_t i;

    if (table->entries_packed) {
	for (i = 0; i < table->real_entries; i++) {
	    st_data_t key, val;
	    st_index_t hash;
	    key = PKEY(table, i);
	    val = PVAL(table, i);
	    hash = PHASH(table, i);
	    retval = (*func)(key, val, arg, 0);
	    if (!table->entries_packed) {
		FIND_ENTRY(table, ptr, hash, i);
		if (!ptr) return 0;
		goto unpacked;
	    }
	    switch (retval) {
	      case ST_CONTINUE:
		break;
	      case ST_CHECK:
	      case ST_STOP:
		return 0;
	      case ST_DELETE:
		remove_packed_entry(table, i);
		i--;
		break;
	    }
	}
	return 0;
    }
    else {
	ptr = table->head;
    }

    if (ptr != 0) {
	do {
	    i = hash_pos(ptr->hash, table->num_bins);
	    retval = (*func)(ptr->key, ptr->record, arg, 0);
	  unpacked:
	    switch (retval) {
	      case ST_CONTINUE:
		ptr = ptr->fore;
		break;
	      case ST_CHECK:
	      case ST_STOP:
		return 0;
	      case ST_DELETE:
		last = &table->bins[hash_pos(ptr->hash, table->num_bins)];
		for (; (tmp = *last) != 0; last = &tmp->next) {
		    if (ptr == tmp) {
			tmp = ptr->fore;
			*last = ptr->next;
			remove_entry(table, ptr);
			st_free_entry(ptr);
			ptr = tmp;
			break;
		    }
		}
	    }
	} while (ptr && table->head);
    }
    return 0;
}

static st_index_t
get_keys(st_table *table, st_data_t *keys, st_index_t size, int check, st_data_t never)
{
    st_data_t key;
    st_data_t *keys_start = keys;

    if (table->entries_packed) {
	st_index_t i;

	if (size > table->real_entries) size = table->real_entries;
	for (i = 0; i < size; i++) {
	    key = PKEY(table, i);
	    if (check && key == never) continue;
	    *keys++ = key;
	}
    }
    else {
	st_table_entry *ptr = table->head;
	st_data_t *keys_end = keys + size;
	for (; ptr && keys < keys_end; ptr = ptr->fore) {
	    key = ptr->key;
	    if (check && key == never) continue;
	    *keys++ = key;
	}
    }

    return keys - keys_start;
}

st_index_t
st_keys(st_table *table, st_data_t *keys, st_index_t size)
{
    return get_keys(table, keys, size, 0, 0);
}

st_index_t
st_keys_check(st_table *table, st_data_t *keys, st_index_t size, st_data_t never)
{
    return get_keys(table, keys, size, 1, never);
}

static st_index_t
get_values(st_table *table, st_data_t *values, st_index_t size, int check, st_data_t never)
{
    st_data_t key;
    st_data_t *values_start = values;

    if (table->entries_packed) {
	st_index_t i;

	if (size > table->real_entries) size = table->real_entries;
	for (i = 0; i < size; i++) {
	    key = PKEY(table, i);
	    if (check && key == never) continue;
	    *values++ = PVAL(table, i);
	}
    }
    else {
	st_table_entry *ptr = table->head;
	st_data_t *values_end = values + size;
	for (; ptr && values < values_end; ptr = ptr->fore) {
	    key = ptr->key;
	    if (check && key == never) continue;
	    *values++ = ptr->record;
	}
    }

    return values - values_start;
}

st_index_t
st_values(st_table *table, st_data_t *values, st_index_t size)
{
    return get_values(table, values, size, 0, 0);
}

st_index_t
st_values_check(st_table *table, st_data_t *values, st_index_t size, st_data_t never)
{
    return get_values(table, values, size, 1, never);
}

#if 0  /* unused right now */
int
st_reverse_foreach(st_table *table, int (*func)(ANYARGS), st_data_t arg)
{
    st_table_entry *ptr, **last, *tmp;
    enum st_retval retval;
    int i;

    if (table->entries_packed) {
        for (i = table->num_entries-1; 0 <= i; i--) {
            int j;
            st_data_t key, val;
            key = PKEY(table, i);
            val = PVAL(table, i);
            retval = (*func)(key, val, arg, 0);
            switch (retval) {
	      case ST_CHECK:	/* check if hash is modified during iteration */
                for (j = 0; j < table->num_entries; j++) {
                    if (PKEY(table, j) == key)
                        break;
                }
                if (j == table->num_entries) {
                    /* call func with error notice */
                    retval = (*func)(0, 0, arg, 1);
                    return 1;
                }
		/* fall through */
	      case ST_CONTINUE:
		break;
	      case ST_STOP:
		return 0;
	      case ST_DELETE:
		remove_packed_entry(table, i);
                break;
            }
        }
        return 0;
    }

    if ((ptr = table->head) != 0) {
	ptr = ptr->back;
	do {
	    retval = (*func)(ptr->key, ptr->record, arg, 0);
	    switch (retval) {
	      case ST_CHECK:	/* check if hash is modified during iteration */
		i = hash_pos(ptr->hash, table->num_bins);
		for (tmp = table->bins[i]; tmp != ptr; tmp = tmp->next) {
		    if (!tmp) {
			/* call func with error notice */
			retval = (*func)(0, 0, arg, 1);
			return 1;
		    }
		}
		/* fall through */
	      case ST_CONTINUE:
		ptr = ptr->back;
		break;
	      case ST_STOP:
		return 0;
	      case ST_DELETE:
		last = &table->bins[hash_pos(ptr->hash, table->num_bins)];
		for (; (tmp = *last) != 0; last = &tmp->next) {
		    if (ptr == tmp) {
			tmp = ptr->back;
			*last = ptr->next;
			remove_entry(table, ptr);
			st_free_entry(ptr);
			ptr = tmp;
			break;
		    }
		}
		ptr = ptr->next;
		free(tmp);
		table->num_entries--;
	    }
	} while (ptr && table->head);
    }
    return 0;
}
#endif

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
 *	chongo <Landon Curt Noll> /\oo/\
 *      http://www.isthe.com/chongo/
 *
 * Share and Enjoy!	:-)
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
    /*
     * This hash function is lightly-tuned for Ruby.  Further tuning
     * should be possible.  Notes:
     *
     * - (n >> 3) alone is great for heap objects and OK for fixnum,
     *   however symbols perform poorly.
     * - (n >> (RUBY_SPECIAL_SHIFT+3)) was added to make symbols hash well,
     *   n.b.: +3 to remove ID scope, +1 worked well initially, too
     * - (n << 3) was finally added to avoid losing bits for fixnums
     * - avoid expensive modulo instructions, it is currently only
     *   shifts and bitmask operations.
     */
    return (st_index_t)((n>>(RUBY_SPECIAL_SHIFT+3)|(n<<3)) ^ (n>>3));
}
