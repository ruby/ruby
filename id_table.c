/* This file is included by symbol.c */

#include "id_table.h"

#ifndef ID_TABLE_DEBUG
#define ID_TABLE_DEBUG 0
#endif

#if ID_TABLE_DEBUG == 0
#define NDEBUG
#endif
#include "ruby_assert.h"

/*
 * st
 *    0: using st with debug information.
 *    1: using st.
 * array
 *   11: simple array. ids = [ID1, ID2, ...], values = [val1, val2, ...]
 *   12: simple array, and use rb_id_serial_t instead of ID.
 *   13: simple array, and use rb_id_serial_t instead of ID. Swap recent access.
 *   14: sorted array, and use rb_id_serial_t instead of ID.
 *   15: sorted array, and use rb_id_serial_t instead of ID, linear small part.
 * hash
 *   21: funny falcon's Coalesced Hashing implementation [Feature #6962]
 *   22: simple open addressing with quadratic probing.
 * mix (array + hash)
 *   31: array(12) (capa <= 32) + hash(22)
 *   32: array(14) (capa <= 32) + hash(22)
 *   33: array(12) (capa <= 64) + hash(22)
 *   34: array(14) (capa <= 64) + hash(22)
 *   34: array(15) (capa <= 64) + hash(22)
 */

#ifndef ID_TABLE_IMPL
#define ID_TABLE_IMPL 34
#endif

#if ID_TABLE_IMPL == 0
#define ID_TABLE_NAME st
#define ID_TABLE_IMPL_TYPE struct st_id_table

#define ID_TABLE_USE_ST 1
#define ID_TABLE_USE_ST_DEBUG 1

#elif ID_TABLE_IMPL == 1
#define ID_TABLE_NAME st
#define ID_TABLE_IMPL_TYPE struct st_id_table

#define ID_TABLE_USE_ST 1
#define ID_TABLE_USE_ST_DEBUG 0

#elif ID_TABLE_IMPL == 11
#define ID_TABLE_NAME list
#define ID_TABLE_IMPL_TYPE struct list_id_table

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1

#elif ID_TABLE_IMPL == 12
#define ID_TABLE_NAME list
#define ID_TABLE_IMPL_TYPE struct list_id_table

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_ID_SERIAL 1

#elif ID_TABLE_IMPL == 13
#define ID_TABLE_NAME list
#define ID_TABLE_IMPL_TYPE struct list_id_table

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_ID_SERIAL 1
#define ID_TABLE_SWAP_RECENT_ACCESS 1

#elif ID_TABLE_IMPL == 14
#define ID_TABLE_NAME list
#define ID_TABLE_IMPL_TYPE struct list_id_table

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_ID_SERIAL 1
#define ID_TABLE_USE_LIST_SORTED 1

#elif ID_TABLE_IMPL == 15
#define ID_TABLE_NAME list
#define ID_TABLE_IMPL_TYPE struct list_id_table

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_ID_SERIAL 1
#define ID_TABLE_USE_LIST_SORTED 1
#define ID_TABLE_USE_LIST_SORTED_LINEAR_SMALL_RANGE 1

#elif ID_TABLE_IMPL == 21
#define ID_TABLE_NAME hash
#define ID_TABLE_IMPL_TYPE sa_table

#define ID_TABLE_USE_COALESCED_HASHING 1
#define ID_TABLE_USE_ID_SERIAL 1

#elif ID_TABLE_IMPL == 22
#define ID_TABLE_NAME hash
#define ID_TABLE_IMPL_TYPE struct hash_id_table

#define ID_TABLE_USE_SMALL_HASH 1
#define ID_TABLE_USE_ID_SERIAL 1

#elif ID_TABLE_IMPL == 31
#define ID_TABLE_NAME mix
#define ID_TABLE_IMPL_TYPE struct mix_id_table

#define ID_TABLE_USE_MIX 1
#define ID_TABLE_USE_MIX_LIST_MAX_CAPA 32

#define ID_TABLE_USE_ID_SERIAL 1

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_SMALL_HASH 1

#elif ID_TABLE_IMPL == 32
#define ID_TABLE_NAME mix
#define ID_TABLE_IMPL_TYPE struct mix_id_table

#define ID_TABLE_USE_MIX 1
#define ID_TABLE_USE_MIX_LIST_MAX_CAPA 32

#define ID_TABLE_USE_ID_SERIAL 1

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_LIST_SORTED 1

#define ID_TABLE_USE_SMALL_HASH 1

#elif ID_TABLE_IMPL == 33
#define ID_TABLE_NAME mix
#define ID_TABLE_IMPL_TYPE struct mix_id_table

#define ID_TABLE_USE_MIX 1
#define ID_TABLE_USE_MIX_LIST_MAX_CAPA 64

#define ID_TABLE_USE_ID_SERIAL 1

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_SMALL_HASH 1

#elif ID_TABLE_IMPL == 34
#define ID_TABLE_NAME mix
#define ID_TABLE_IMPL_TYPE struct mix_id_table

#define ID_TABLE_USE_MIX 1
#define ID_TABLE_USE_MIX_LIST_MAX_CAPA 64

#define ID_TABLE_USE_ID_SERIAL 1

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_LIST_SORTED 1

#define ID_TABLE_USE_SMALL_HASH 1

#elif ID_TABLE_IMPL == 35
#define ID_TABLE_NAME mix
#define ID_TABLE_IMPL_TYPE struct mix_id_table

#define ID_TABLE_USE_MIX 1
#define ID_TABLE_USE_MIX_LIST_MAX_CAPA 64

#define ID_TABLE_USE_ID_SERIAL 1

#define ID_TABLE_USE_LIST 1
#define ID_TABLE_USE_CALC_VALUES 1
#define ID_TABLE_USE_LIST_SORTED 1
#define ID_TABLE_USE_LIST_SORTED_LINEAR_SMALL_RANGE 1

#define ID_TABLE_USE_SMALL_HASH 1

#else
#error
#endif

#if ID_TABLE_SWAP_RECENT_ACCESS && ID_TABLE_USE_LIST_SORTED
#error
#endif

/* IMPL(create) will be "hash_id_table_create" and so on */
#define IMPL1(name, op) TOKEN_PASTE(name, _id##op) /* expand `name' */
#define IMPL(op)        IMPL1(ID_TABLE_NAME, _table##op) /* but prevent `op' */

#ifdef __GNUC__
# define UNUSED(func) static func __attribute__((unused))
#else
# define UNUSED(func) static func
#endif

UNUSED(ID_TABLE_IMPL_TYPE *IMPL(_create)(size_t));
UNUSED(void IMPL(_free)(ID_TABLE_IMPL_TYPE *));
UNUSED(void IMPL(_clear)(ID_TABLE_IMPL_TYPE *));
UNUSED(size_t IMPL(_size)(const ID_TABLE_IMPL_TYPE *));
UNUSED(size_t IMPL(_memsize)(const ID_TABLE_IMPL_TYPE *));
UNUSED(int IMPL(_insert)(ID_TABLE_IMPL_TYPE *, ID, VALUE));
UNUSED(int IMPL(_lookup)(ID_TABLE_IMPL_TYPE *, ID, VALUE *));
UNUSED(int IMPL(_delete)(ID_TABLE_IMPL_TYPE *, ID));
UNUSED(void IMPL(_foreach)(ID_TABLE_IMPL_TYPE *, rb_id_table_foreach_func_t *, void *));
UNUSED(void IMPL(_foreach_values)(ID_TABLE_IMPL_TYPE *, rb_id_table_foreach_values_func_t *, void *));

#if ID_TABLE_USE_ID_SERIAL
typedef rb_id_serial_t id_key_t;
static inline ID
key2id(id_key_t key)
{
    return rb_id_serial_to_id(key);
}

static inline id_key_t
id2key(ID id)
{
    return rb_id_to_serial(id);
}
#else /* ID_TABLE_USE_ID_SERIAL */

typedef ID id_key_t;
#define key2id(key) key
#define id2key(id)  id

#endif /* ID_TABLE_USE_ID_SERIAL */

/***************************************************************
 * 0: using st with debug information.
 * 1: using st.
 ***************************************************************/
#if ID_TABLE_USE_ST
#if ID_TABLE_USE_ST_DEBUG
#define ID_TABLE_MARK 0x12345678

struct st_id_table {
    struct st_table *st;
    unsigned int check;
};

static struct st_table *
tbl2st(struct st_id_table *tbl)
{
    if (tbl->check != ID_TABLE_MARK) rb_bug("tbl2st: check error %x", tbl->check);
    return tbl->st;
}

static struct st_id_table *
st_id_table_create(size_t size)
{
    struct st_id_table *tbl = ALLOC(struct st_id_table);
    tbl->st = st_init_numtable_with_size(size);
    tbl->check = ID_TABLE_MARK;
    return tbl;
}

static void
st_id_table_free(struct st_id_table *tbl)
{
    st_free_table(tbl->st);
    xfree(tbl);
}

#else /* ID_TABLE_USE_ST_DEBUG */

struct st_id_table {
    struct st_table st;
};

static struct st_table *
tbl2st(struct st_id_table *tbl)
{
    return (struct st_table *)tbl;
}

static struct st_id_table *
st_id_table_create(size_t size)
{
    return (struct st_id_table *)st_init_numtable_with_size(size);
}

static void
st_id_table_free(struct st_id_table *tbl)
{
    st_free_table((struct st_table*)tbl);
}

#endif /* ID_TABLE_USE_ST_DEBUG */

static void
st_id_table_clear(struct st_id_table *tbl)
{
    st_clear(tbl2st(tbl));
}

static size_t
st_id_table_size(const struct st_id_table *tbl)
{
    return tbl2st(tbl)->num_entries;
}

static size_t
st_id_table_memsize(const struct st_id_table *tbl)
{
    size_t header_size = ID_TABLE_USE_ST_DEBUG ? sizeof(struct st_id_table) : 0;
    return header_size + st_memsize(tbl2st(tbl));
}

static int
st_id_table_lookup(struct st_id_table *tbl, ID id, VALUE *val)
{
    return st_lookup(tbl2st(tbl), (st_data_t)id, (st_data_t *)val);
}

static int
st_id_table_insert(struct st_id_table *tbl, ID id, VALUE val)
{
    return st_insert(tbl2st(tbl), id, val);
}

static int
st_id_table_delete(struct st_id_table *tbl, ID id)
{
    return st_delete(tbl2st(tbl), (st_data_t *)&id, NULL);
}

static void
st_id_table_foreach(struct st_id_table *tbl, rb_id_table_foreach_func_t *func, void *data)
{
    st_foreach(tbl2st(tbl), (int (*)(ANYARGS))func, (st_data_t)data);
}

struct values_iter_data {
    rb_id_table_foreach_values_func_t *values_i;
    void *data;
};

static int
each_values(st_data_t key, st_data_t val, st_data_t ptr)
{
    struct values_iter_data *values_iter_data = (struct values_iter_data *)ptr;
    return values_iter_data->values_i(val, values_iter_data->data);
}

static void
st_id_table_foreach_values(struct st_id_table *tbl, rb_id_table_foreach_values_func_t *func, void *data)
{
    struct values_iter_data values_iter_data;
    values_iter_data.values_i = func;
    values_iter_data.data = data;
    st_foreach(tbl2st(tbl), each_values, (st_data_t)&values_iter_data);
}
#endif /* ID_TABLE_USE_ST */

#if ID_TABLE_USE_LIST

#define LIST_MIN_CAPA 4

struct list_id_table {
    int capa;
    int num;
    id_key_t *keys;
#if ID_TABLE_USE_CALC_VALUES == 0
    VALUE *values_;
#endif
};

#if ID_TABLE_USE_CALC_VALUES
#define TABLE_VALUES(tbl) ((VALUE *)((tbl)->keys + (tbl)->capa))
#else
#define TABLE_VALUES(tbl) (tbl)->values_
#endif

static struct list_id_table *
list_id_table_init(struct list_id_table *tbl, size_t capa)
{
    if (capa > 0) {
#if ID_TABLE_USE_CALC_VALUES && \
    (UNALIGNED_WORD_ACCESS == 0) && (SIZEOF_VALUE == 8)
	/* Workaround for 8-byte word alignment on 64-bit SPARC.
	 * This code assumes that sizeof(ID) == 4, sizeof(VALUE) == 8, and
	 *  xmalloc() returns 8-byte aligned memory block.
	 */
	if (capa & (size_t)1) capa += 1;
#endif
	tbl->capa = (int)capa;
#if ID_TABLE_USE_CALC_VALUES
	tbl->keys = (id_key_t *)xmalloc(sizeof(id_key_t) * capa + sizeof(VALUE) * capa);
#else
	tbl->keys = ALLOC_N(id_key_t, capa);
	tbl->values_ = ALLOC_N(VALUE, capa);
#endif
    }
    return tbl;
}

#ifndef ID_TABLE_USE_MIX
static struct list_id_table *
list_id_table_create(size_t capa)
{
    struct list_id_table *tbl = ZALLOC(struct list_id_table);
    return list_id_table_init(tbl, capa);
}
#endif

static void
list_id_table_free(struct list_id_table *tbl)
{
    xfree(tbl->keys);
#if ID_TABLE_USE_CALC_VALUES == 0
    xfree(tbl->values_);
#endif
    xfree(tbl);
}

static void
list_id_table_clear(struct list_id_table *tbl)
{
    tbl->num = 0;
}

static size_t
list_id_table_size(const struct list_id_table *tbl)
{
    return (size_t)tbl->num;
}

static size_t
list_id_table_memsize(const struct list_id_table *tbl)
{
    return (sizeof(id_key_t) + sizeof(VALUE)) * tbl->capa + sizeof(struct list_id_table);
}

static void
list_table_extend(struct list_id_table *tbl)
{
    if (tbl->capa == tbl->num) {
	const int capa = tbl->capa == 0 ? LIST_MIN_CAPA : (tbl->capa * 2);

#if ID_TABLE_USE_CALC_VALUES
	{
	    VALUE *old_values, *new_values;
	    VALUE *debug_values = NULL;
	    const int num = tbl->num;
	    const int size = sizeof(id_key_t) * capa + sizeof(VALUE) * capa;
	    int i;

	    if (num > 0) {
		VALUE *orig_values = (VALUE *)(tbl->keys + num);
		debug_values = ALLOC_N(VALUE, num);

		for (i=0; i<num; i++) {
		    debug_values[i] = orig_values[i];
		}

		if (0)
		    for (i=0; i< 2 * num; i++) {
			unsigned char *cs = (unsigned char *)&tbl->keys[i];
			size_t j;
			fprintf(stderr, ">> %3d | %p - ", i, cs);
			for (j=0; j<sizeof(VALUE); j++) {
			    fprintf(stderr, "%x ", cs[j]);
			}
			fprintf(stderr, "\n");
		    }
	    }

	    tbl->keys = (id_key_t *)xrealloc(tbl->keys, size);
	    old_values = (VALUE *)(tbl->keys + num);
	    new_values = (VALUE *)(tbl->keys + capa);

	    /*  [ keys (num) ] [ values (num) ]
	     *                 ^ old_values
	     * realloc =>
	     *  [ keys (capa = num * 2)  ] [ values (capa = num * 2) ]
	     *                             ^ new_values
	     */

	    /* memmove */
	    if (0) {
		fprintf(stderr, "memmove: %p -> %p (%d, capa: %d)\n",
			old_values, new_values, num, capa);
	    }
	    assert(num < capa);
	    assert(num == 0 || old_values < new_values);

	    for (i=num-1; i>=0; i--) {
		new_values[i] = old_values[i];
	    }

	    if (num > 0) {
		for (i=0; i<num; i++) {
		    assert(debug_values[i] == new_values[i]);
		}
		xfree(debug_values);
	    }
	}

	tbl->capa = capa;
#else
	tbl->capa = capa;
	tbl->keys = (id_key_t *)xrealloc(tbl->keys, sizeof(id_key_t) * capa);
	tbl->values_ = (VALUE *)xrealloc(tbl->values_, sizeof(VALUE) * capa);
#endif
    }
}

#if ID_TABLE_DEBUG
static void
list_table_show(struct list_id_table *tbl)
{
    const id_key_t *keys = tbl->keys;
    const int num = tbl->num;
    int i;

    fprintf(stderr, "tbl: %p (num: %d)\n", tbl, num);
    for (i=0; i<num; i++) {
	fprintf(stderr, " -> [%d] %s %d\n", i, rb_id2name(key2id(keys[i])), (int)keys[i]);
    }
}
#endif

static void
tbl_assert(struct list_id_table *tbl)
{
#if ID_TABLE_DEBUG
#if ID_TABLE_USE_LIST_SORTED
    const id_key_t *keys = tbl->keys;
    const int num = tbl->num;
    int i;

    for (i=0; i<num-1; i++) {
	if (keys[i] >= keys[i+1]) {
	    list_table_show(tbl);
	    rb_bug(": not sorted.");
	}
    }
#endif
#endif
}

#if ID_TABLE_USE_LIST_SORTED
static int
list_ids_bsearch(const id_key_t *keys, id_key_t key, int num)
{
    int p, min = 0, max = num;

#if ID_TABLE_USE_LIST_SORTED_LINEAR_SMALL_RANGE
    if (num <= 64) {
	if (num  > 32) {
	    if (keys[num/2] <= key) {
		min = num/2;
	    } else {
		max = num/2;
	    }
	}
	for (p = min; p<num && keys[p] < key; p++) {
	    assert(keys[p] != 0);
	}
	return (p<num && keys[p] == key) ? p : -p-1;
    }
#endif /* ID_TABLE_USE_LIST_SORTED_LINEAR_SMALL_RANGE */

    while (1) {
	p = min + (max - min) / 2;

	if (min >= max) {
	    break;
	}
	else {
	    id_key_t kp = keys[p];
	    assert(p < max);
	    assert(p >= min);

	    if      (kp > key) max = p;
	    else if (kp < key) min = p+1;
	    else {
		assert(kp == key);
		assert(p >= 0);
		assert(p < num);
		return p;
	    }
	}
    }

    assert(min == max);
    assert(min == p);
    return -p-1;
}
#endif /* ID_TABLE_USE_LIST_SORTED */

static int
list_table_index(struct list_id_table *tbl, id_key_t key)
{
    const int num = tbl->num;
    const id_key_t *keys = tbl->keys;

#if ID_TABLE_USE_LIST_SORTED
    return list_ids_bsearch(keys, key, num);
#else /* ID_TABLE_USE_LIST_SORTED */
    int i;

    for (i=0; i<num; i++) {
	assert(keys[i] != 0);

	if (keys[i] == key) {
	    return (int)i;
	}
    }
    return -1;
#endif
}

static int
list_id_table_lookup(struct list_id_table *tbl, ID id, VALUE *valp)
{
    id_key_t key = id2key(id);
    int index = list_table_index(tbl, key);

    if (index >= 0) {
	*valp = TABLE_VALUES(tbl)[index];

#if ID_TABLE_SWAP_RECENT_ACCESS
	if (index > 0) {
	    VALUE *values = TABLE_VALUES(tbl);
	    id_key_t tk = tbl->keys[index-1];
	    VALUE tv = values[index-1];
	    tbl->keys[index-1] = tbl->keys[index];
	    tbl->keys[index] = tk;
	    values[index-1] = values[index];
	    values[index] = tv;
	}
#endif /* ID_TABLE_SWAP_RECENT_ACCESS */
	return TRUE;
    }
    else {
	return FALSE;
    }
}

static int
list_id_table_insert(struct list_id_table *tbl, ID id, VALUE val)
{
    const id_key_t key = id2key(id);
    const int index = list_table_index(tbl, key);

    if (index >= 0) {
	TABLE_VALUES(tbl)[index] = val;
    }
    else {
	list_table_extend(tbl);
	{
	    const int num = tbl->num++;
#if ID_TABLE_USE_LIST_SORTED
	    const int insert_index = -(index + 1);
	    id_key_t *keys = tbl->keys;
	    VALUE *values = TABLE_VALUES(tbl);
	    int i;

	    if (0) fprintf(stderr, "insert: %d into %d on\n", (int)key, insert_index);

	    for (i=num; i>insert_index; i--) {
		keys[i] = keys[i-1];
		values[i] = values[i-1];
	    }
	    keys[i] = key;
	    values[i] = val;

	    tbl_assert(tbl);
#else
	    tbl->keys[num] = key;
	    TABLE_VALUES(tbl)[num] = val;
#endif
	}
    }

    return TRUE;
}

static int
list_delete_index(struct list_id_table *tbl, id_key_t key, int index)
{
    if (index >= 0) {
	VALUE *values = TABLE_VALUES(tbl);

#if ID_TABLE_USE_LIST_SORTED
	int i;
	const int num = tbl->num;
	id_key_t *keys = tbl->keys;

	for (i=index+1; i<num; i++) { /* compaction */
	    keys[i-1] = keys[i];
	    values[i-1] = values[i];
	}
#else
	tbl->keys[index] = tbl->keys[tbl->num-1];
	values[index] = values[tbl->num-1];
#endif
	tbl->num--;
	tbl_assert(tbl);

	return TRUE;
    }
    else {
	return FALSE;
    }
}

static int
list_id_table_delete(struct list_id_table *tbl, ID id)
{
    const id_key_t key = id2key(id);
    int index = list_table_index(tbl, key);
    return list_delete_index(tbl, key, index);
}

#define FOREACH_LAST() do {   \
    switch (ret) {            \
      case ID_TABLE_ITERATOR_RESULT_END: \
      case ID_TABLE_CONTINUE: \
      case ID_TABLE_STOP:     \
	break;                \
      case ID_TABLE_DELETE:   \
	list_delete_index(tbl, key, i); \
	values = TABLE_VALUES(tbl);     \
	num = tbl->num;                 \
	i--; /* redo same index */      \
	break; \
    } \
} while (0)

static void
list_id_table_foreach(struct list_id_table *tbl, rb_id_table_foreach_func_t *func, void *data)
{
    int num = tbl->num;
    int i;
    const id_key_t *keys = tbl->keys;
    const VALUE *values = TABLE_VALUES(tbl);

    for (i=0; i<num; i++) {
	const id_key_t key = keys[i];
	enum rb_id_table_iterator_result ret = (*func)(key2id(key), values[i], data);
	assert(key != 0);

	FOREACH_LAST();
	if (ret == ID_TABLE_STOP) return;
    }
}

static void
list_id_table_foreach_values(struct list_id_table *tbl, rb_id_table_foreach_values_func_t *func, void *data)
{
    int num = tbl->num;
    int i;
    const id_key_t *keys = tbl->keys;
    VALUE *values = TABLE_VALUES(tbl);

    for (i=0; i<num; i++) {
	const id_key_t key = keys[i];
	enum rb_id_table_iterator_result ret = (*func)(values[i], data);
	assert(key != 0);

	FOREACH_LAST();
	if (ret == ID_TABLE_STOP) return;
    }
}
#endif /* ID_TABLE_USE_LIST */


#if ID_TABLE_USE_COALESCED_HASHING
/* implementation is based on
 * https://bugs.ruby-lang.org/issues/6962 by funny_falcon
 */

typedef unsigned int sa_index_t;

#define SA_EMPTY    0
#define SA_LAST     1
#define SA_OFFSET   2
#define SA_MIN_SIZE 4

typedef struct sa_entry {
    sa_index_t next;
    id_key_t key;
    VALUE value;
} sa_entry;

typedef struct {
    sa_index_t num_bins;
    sa_index_t num_entries;
    sa_index_t free_pos;
    sa_entry *entries;
} sa_table;

static void
sa_init_table(register sa_table *table, sa_index_t num_bins)
{
    if (num_bins) {
        table->num_entries = 0;
        table->entries = ZALLOC_N(sa_entry, num_bins);
        table->num_bins = num_bins;
        table->free_pos = num_bins;
    }
}

static sa_table*
hash_id_table_create(size_t size)
{
    sa_table* table = ZALLOC(sa_table);
    sa_init_table(table, (sa_index_t)size);
    return table;
}

static void
hash_id_table_clear(sa_table *table)
{
    xfree(table->entries);
    memset(table, 0, sizeof(sa_table));
}

static void
hash_id_table_free(sa_table *table)
{
    xfree(table->entries);
    xfree(table);
}

static size_t
hash_id_table_memsize(const sa_table *table)
{
    return sizeof(sa_table) + table->num_bins * sizeof (sa_entry);
}

static inline sa_index_t
calc_pos(register sa_table* table, id_key_t key)
{
    return key & (table->num_bins - 1);
}

static void
fix_empty(register sa_table* table)
{
    while (--table->free_pos &&
	   table->entries[table->free_pos-1].next != SA_EMPTY);
}

#define FLOOR_TO_4 ((~((sa_index_t)0)) << 2)
static sa_index_t
find_empty(register sa_table* table, register sa_index_t pos)
{
    sa_index_t new_pos = table->free_pos-1;
    sa_entry *entry;
    static const unsigned offsets[][3] = {
	{1, 2, 3},
	{2, 3, 0},
	{3, 1, 0},
	{2, 1, 0}
    };
    const unsigned *const check = offsets[pos&3];
    pos &= FLOOR_TO_4;
    entry = table->entries+pos;

    if (entry[check[0]].next == SA_EMPTY) { new_pos = pos + check[0]; goto check; }
    if (entry[check[1]].next == SA_EMPTY) { new_pos = pos + check[1]; goto check; }
    if (entry[check[2]].next == SA_EMPTY) { new_pos = pos + check[2]; goto check; }

  check:
    if (new_pos+1 == table->free_pos) fix_empty(table);
    return new_pos;
}

static void resize(register sa_table* table);
static int insert_into_chain(register sa_table*, register id_key_t, st_data_t, sa_index_t pos);
static int insert_into_main(register sa_table*, id_key_t, st_data_t, sa_index_t pos, sa_index_t prev_pos);

static int
sa_insert(register sa_table* table, id_key_t key, VALUE value)
{
    register sa_entry *entry;
    sa_index_t pos, main_pos;

    if (table->num_bins == 0) {
        sa_init_table(table, SA_MIN_SIZE);
    }

    pos = calc_pos(table, key);
    entry = table->entries + pos;

    if (entry->next == SA_EMPTY) {
        entry->next = SA_LAST;
        entry->key = key;
        entry->value = value;
        table->num_entries++;
        if (pos+1 == table->free_pos) fix_empty(table);
        return 0;
    }

    if (entry->key == key) {
        entry->value = value;
        return 1;
    }

    if (table->num_entries + (table->num_entries >> 2) > table->num_bins) {
        resize(table);
	return sa_insert(table, key, value);
    }

    main_pos = calc_pos(table, entry->key);
    if (main_pos == pos) {
        return insert_into_chain(table, key, value, pos);
    }
    else {
        if (!table->free_pos) {
            resize(table);
            return sa_insert(table, key, value);
        }
        return insert_into_main(table, key, value, pos, main_pos);
    }
}

static int
hash_id_table_insert(register sa_table* table, ID id, VALUE value)
{
    return sa_insert(table, id2key(id), value);
}

static int
insert_into_chain(register sa_table* table, id_key_t key, st_data_t value, sa_index_t pos)
{
    sa_entry *entry = table->entries + pos, *new_entry;
    sa_index_t new_pos;

    while (entry->next != SA_LAST) {
        pos = entry->next - SA_OFFSET;
        entry = table->entries + pos;
        if (entry->key == key) {
            entry->value = value;
            return 1;
        }
    }

    if (!table->free_pos) {
        resize(table);
        return sa_insert(table, key, value);
    }

    new_pos = find_empty(table, pos);
    new_entry = table->entries + new_pos;
    entry->next = new_pos + SA_OFFSET;

    new_entry->next = SA_LAST;
    new_entry->key = key;
    new_entry->value = value;
    table->num_entries++;
    return 0;
}

static int
insert_into_main(register sa_table* table, id_key_t key, st_data_t value, sa_index_t pos, sa_index_t prev_pos)
{
    sa_entry *entry = table->entries + pos;
    sa_index_t new_pos = find_empty(table, pos);
    sa_entry *new_entry = table->entries + new_pos;
    sa_index_t npos;

    *new_entry = *entry;

    while((npos = table->entries[prev_pos].next - SA_OFFSET) != pos) {
        prev_pos = npos;
    }
    table->entries[prev_pos].next = new_pos + SA_OFFSET;

    entry->next = SA_LAST;
    entry->key = key;
    entry->value = value;
    table->num_entries++;
    return 0;
}

static sa_index_t
new_size(sa_index_t num_entries)
{
    sa_index_t size = num_entries >> 3;
    size |= size >> 1;
    size |= size >> 2;
    size |= size >> 4;
    size |= size >> 8;
    size |= size >> 16;
    return (size + 1) << 3;
}

static void
resize(register sa_table *table)
{
    sa_table tmp_table;
    sa_entry *entry;
    sa_index_t i;

    if (table->num_entries == 0) {
        xfree(table->entries);
	memset(table, 0, sizeof(sa_table));
        return;
    }

    sa_init_table(&tmp_table, new_size(table->num_entries + (table->num_entries >> 2)));
    entry = table->entries;

    for(i = 0; i < table->num_bins; i++, entry++) {
        if (entry->next != SA_EMPTY) {
            sa_insert(&tmp_table, entry->key, entry->value);
        }
    }
    xfree(table->entries);
    *table = tmp_table;
}

static int
hash_id_table_lookup(register sa_table *table, ID id, VALUE *valuep)
{
    register sa_entry *entry;
    id_key_t key = id2key(id);

    if (table->num_entries == 0) return 0;

    entry = table->entries + calc_pos(table, key);
    if (entry->next == SA_EMPTY) return 0;

    if (entry->key == key) goto found;
    if (entry->next == SA_LAST) return 0;

    entry = table->entries + (entry->next - SA_OFFSET);
    if (entry->key == key) goto found;

    while(entry->next != SA_LAST) {
        entry = table->entries + (entry->next - SA_OFFSET);
        if (entry->key == key) goto found;
    }
    return 0;
  found:
    if (valuep) *valuep = entry->value;
    return 1;
}

static size_t
hash_id_table_size(const sa_table *table)
{
    return table->num_entries;
}

static int
hash_id_table_delete(sa_table *table, ID id)
{
    sa_index_t pos, prev_pos = ~0;
    sa_entry *entry;
    id_key_t key = id2key(id);

    if (table->num_entries == 0) goto not_found;

    pos = calc_pos(table, key);
    entry = table->entries + pos;

    if (entry->next == SA_EMPTY) goto not_found;

    do {
        if (entry->key == key) {
            if (entry->next != SA_LAST) {
                sa_index_t npos = entry->next - SA_OFFSET;
                *entry = table->entries[npos];
                memset(table->entries + npos, 0, sizeof(sa_entry));
            }
            else {
                memset(table->entries + pos, 0, sizeof(sa_entry));
                if (~prev_pos) {
                    table->entries[prev_pos].next = SA_LAST;
                }
            }
            table->num_entries--;
            if (table->num_entries < table->num_bins / 4) {
                resize(table);
            }
            return 1;
        }
        if (entry->next == SA_LAST) break;
        prev_pos = pos;
        pos = entry->next - SA_OFFSET;
        entry = table->entries + pos;
    } while(1);

  not_found:
    return 0;
}

enum foreach_type {
    foreach_key_values,
    foreach_values
};

static void
hash_foreach(sa_table *table, enum rb_id_table_iterator_result (*func)(ANYARGS), void *arg, enum foreach_type type)
{
    sa_index_t i;

    if (table->num_bins > 0) {
	for(i = 0; i < table->num_bins ; i++) {
	    if (table->entries[i].next != SA_EMPTY) {
		id_key_t key = table->entries[i].key;
		st_data_t val = table->entries[i].value;
		enum rb_id_table_iterator_result ret;

		switch (type) {
		  case foreach_key_values:
		    ret = (*func)(key2id(key), val, arg);
		    break;
		  case foreach_values:
		    ret = (*func)(val, arg);
		    break;
		}

		switch (ret) {
		  case ID_TABLE_DELETE:
		    rb_warn("unsupported yet");
		    break;
		  default:
		    break;
		}
		if (ret == ID_TABLE_STOP) break;
	    }
	}
    }
}

static void
hash_id_table_foreach(sa_table *table, enum rb_id_table_iterator_result (*func)(ID, VALUE, void *), void *arg)
{
    hash_foreach(table, func, arg, foreach_key_values);
}

static void
hash_id_table_foreach_values(sa_table *table, enum rb_id_table_iterator_result (*func)(VALUE, void *), void *arg)
{
    hash_foreach(table, func, arg, foreach_values);
}
#endif /* ID_TABLE_USE_COALESCED_HASHING */

#ifdef ID_TABLE_USE_SMALL_HASH
/* simple open addressing with quadratic probing.
   uses mark-bit on collisions - need extra 1 bit,
   ID is strictly 3 bits larger than rb_id_serial_t */

typedef struct rb_id_item {
    id_key_t key;
#if SIZEOF_VALUE == 8
    int      collision;
#endif
    VALUE    val;
} item_t;

struct hash_id_table {
    int capa;
    int num;
    int used;
    item_t *items;
};

#if SIZEOF_VALUE == 8
#define ITEM_GET_KEY(tbl, i) ((tbl)->items[i].key)
#define ITEM_KEY_ISSET(tbl, i) ((tbl)->items[i].key)
#define ITEM_COLLIDED(tbl, i) ((tbl)->items[i].collision)
#define ITEM_SET_COLLIDED(tbl, i) ((tbl)->items[i].collision = 1)
static inline void
ITEM_SET_KEY(struct hash_id_table *tbl, int i, id_key_t key)
{
    tbl->items[i].key = key;
}
#else
#define ITEM_GET_KEY(tbl, i) ((tbl)->items[i].key >> 1)
#define ITEM_KEY_ISSET(tbl, i) ((tbl)->items[i].key > 1)
#define ITEM_COLLIDED(tbl, i) ((tbl)->items[i].key & 1)
#define ITEM_SET_COLLIDED(tbl, i) ((tbl)->items[i].key |= 1)
static inline void
ITEM_SET_KEY(struct hash_id_table *tbl, int i, id_key_t key)
{
    tbl->items[i].key = (key << 1) | ITEM_COLLIDED(tbl, i);
}
#endif

static inline int
round_capa(int capa)
{
    /* minsize is 4 */
    capa >>= 2;
    capa |= capa >> 1;
    capa |= capa >> 2;
    capa |= capa >> 4;
    capa |= capa >> 8;
    capa |= capa >> 16;
    return (capa + 1) << 2;
}

static struct hash_id_table *
hash_id_table_init(struct hash_id_table *tbl, int capa)
{
    MEMZERO(tbl, struct hash_id_table, 1);
    if (capa > 0) {
	capa = round_capa(capa);
	tbl->capa = (int)capa;
	tbl->items = ZALLOC_N(item_t, capa);
    }
    return tbl;
}

#ifndef ID_TABLE_USE_MIX
static struct hash_id_table *
hash_id_table_create(size_t capa)
{
    struct hash_id_table *tbl = ALLOC(struct hash_id_table);
    return hash_id_table_init(tbl, (int)capa);
}
#endif

static void
hash_id_table_free(struct hash_id_table *tbl)
{
    xfree(tbl->items);
    xfree(tbl);
}

static void
hash_id_table_clear(struct hash_id_table *tbl)
{
    tbl->num = 0;
    tbl->used = 0;
    MEMZERO(tbl->items, item_t, tbl->capa);
}

static size_t
hash_id_table_size(const struct hash_id_table *tbl)
{
    return (size_t)tbl->num;
}

static size_t
hash_id_table_memsize(const struct hash_id_table *tbl)
{
    return sizeof(item_t) * tbl->capa + sizeof(struct hash_id_table);
}

static int
hash_table_index(struct hash_id_table* tbl, id_key_t key)
{
    if (tbl->capa > 0) {
	int mask = tbl->capa - 1;
	int ix = key & mask;
	int d = 1;
	while (key != ITEM_GET_KEY(tbl, ix)) {
	    if (!ITEM_COLLIDED(tbl, ix))
		return -1;
	    ix = (ix + d) & mask;
	    d++;
	}
	return ix;
    }
    return -1;
}

static void
hash_table_raw_insert(struct hash_id_table *tbl, id_key_t key, VALUE val)
{
    int mask = tbl->capa - 1;
    int ix = key & mask;
    int d = 1;
    assert(key != 0);
    while (ITEM_KEY_ISSET(tbl, ix)) {
	ITEM_SET_COLLIDED(tbl, ix);
	ix = (ix + d) & mask;
	d++;
    }
    tbl->num++;
    if (!ITEM_COLLIDED(tbl, ix)) {
	tbl->used++;
    }
    ITEM_SET_KEY(tbl, ix, key);
    tbl->items[ix].val = val;
}

static int
hash_delete_index(struct hash_id_table *tbl, int ix)
{
    if (ix >= 0) {
	if (!ITEM_COLLIDED(tbl, ix)) {
	    tbl->used--;
	}
	tbl->num--;
	ITEM_SET_KEY(tbl, ix, 0);
	tbl->items[ix].val = 0;
	return TRUE;
    } else {
	return FALSE;
    }
}

static void
hash_table_extend(struct hash_id_table* tbl)
{
    if (tbl->used + (tbl->used >> 1) >= tbl->capa) {
	int new_cap = round_capa(tbl->num + (tbl->num >> 1));
	int i;
	item_t* old;
	struct hash_id_table tmp_tbl = {0, 0, 0};
	if (new_cap < tbl->capa) {
	    new_cap = round_capa(tbl->used + (tbl->used >> 1));
	}
	tmp_tbl.capa = new_cap;
	tmp_tbl.items = ZALLOC_N(item_t, new_cap);
	for (i = 0; i < tbl->capa; i++) {
	    id_key_t key = ITEM_GET_KEY(tbl, i);
	    if (key != 0) {
		hash_table_raw_insert(&tmp_tbl, key, tbl->items[i].val);
	    }
	}
	old = tbl->items;
	*tbl = tmp_tbl;
	xfree(old);
    }
}

#if ID_TABLE_DEBUG && 0
static void
hash_table_show(struct hash_id_table *tbl)
{
    const id_key_t *keys = tbl->keys;
    const int capa = tbl->capa;
    int i;

    fprintf(stderr, "tbl: %p (capa: %d, num: %d, used: %d)\n", tbl, tbl->capa, tbl->num, tbl->used);
    for (i=0; i<capa; i++) {
	if (ITEM_KEY_ISSET(tbl, i)) {
	    fprintf(stderr, " -> [%d] %s %d\n", i, rb_id2name(key2id(keys[i])), (int)keys[i]);
	}
    }
}
#endif

static int
hash_id_table_lookup(struct hash_id_table *tbl, ID id, VALUE *valp)
{
    id_key_t key = id2key(id);
    int index = hash_table_index(tbl, key);

    if (index >= 0) {
	*valp = tbl->items[index].val;
	return TRUE;
    }
    else {
	return FALSE;
    }
}

static int
hash_id_table_insert_key(struct hash_id_table *tbl, const id_key_t key, const VALUE val)
{
    const int index = hash_table_index(tbl, key);

    if (index >= 0) {
	tbl->items[index].val = val;
    }
    else {
	hash_table_extend(tbl);
	hash_table_raw_insert(tbl, key, val);
    }
    return TRUE;
}

static int
hash_id_table_insert(struct hash_id_table *tbl, ID id, VALUE val)
{
    return hash_id_table_insert_key(tbl, id2key(id), val);
}

static int
hash_id_table_delete(struct hash_id_table *tbl, ID id)
{
    const id_key_t key = id2key(id);
    int index = hash_table_index(tbl, key);
    return hash_delete_index(tbl, index);
}

static void
hash_id_table_foreach(struct hash_id_table *tbl, rb_id_table_foreach_func_t *func, void *data)
{
    int i, capa = tbl->capa;

    for (i=0; i<capa; i++) {
	if (ITEM_KEY_ISSET(tbl, i)) {
	    const id_key_t key = ITEM_GET_KEY(tbl, i);
	    enum rb_id_table_iterator_result ret = (*func)(key2id(key), tbl->items[i].val, data);
	    assert(key != 0);

	    if (ret == ID_TABLE_DELETE)
		hash_delete_index(tbl, i);
	    else if (ret == ID_TABLE_STOP)
		return;
	}
    }
}

static void
hash_id_table_foreach_values(struct hash_id_table *tbl, rb_id_table_foreach_values_func_t *func, void *data)
{
    int i, capa = tbl->capa;

    for (i=0; i<capa; i++) {
	if (ITEM_KEY_ISSET(tbl, i)) {
	    enum rb_id_table_iterator_result ret = (*func)(tbl->items[i].val, data);

	    if (ret == ID_TABLE_DELETE)
		hash_delete_index(tbl, i);
	    else if (ret == ID_TABLE_STOP)
		return;
	}
    }
}
#endif /* ID_TABLE_USE_SMALL_HASH */

#if ID_TABLE_USE_MIX

struct mix_id_table {
    union {
	struct {
	    int capa;
	    int num;
	} size;
	struct list_id_table list;
	struct hash_id_table hash;
    } aux;
};

#define LIST_LIMIT_P(mix) ((mix)->aux.size.num == ID_TABLE_USE_MIX_LIST_MAX_CAPA)
#define LIST_P(mix)       ((mix)->aux.size.capa <= ID_TABLE_USE_MIX_LIST_MAX_CAPA)

static struct mix_id_table *
mix_id_table_create(size_t size)
{
    struct mix_id_table *mix = ZALLOC(struct mix_id_table);
    list_id_table_init((struct list_id_table *)mix, size);
    return mix;
}

static void
mix_id_table_free(struct mix_id_table *tbl)
{
    if (LIST_P(tbl)) list_id_table_free(&tbl->aux.list);
    else             hash_id_table_free(&tbl->aux.hash);
}

static void
mix_id_table_clear(struct mix_id_table *tbl)
{
    if (LIST_P(tbl)) list_id_table_clear(&tbl->aux.list);
    else             hash_id_table_clear(&tbl->aux.hash);
}

static size_t
mix_id_table_size(const struct mix_id_table *tbl)
{
    if (LIST_P(tbl)) return list_id_table_size(&tbl->aux.list);
    else             return hash_id_table_size(&tbl->aux.hash);
}

static size_t
mix_id_table_memsize(const struct mix_id_table *tbl)
{
    if (LIST_P(tbl)) return list_id_table_memsize(&tbl->aux.list) - sizeof(struct list_id_table) + sizeof(struct mix_id_table);
    else             return hash_id_table_memsize(&tbl->aux.hash);
}

static int
mix_id_table_insert(struct mix_id_table *tbl, ID id, VALUE val)
{
    int r;

    if (LIST_P(tbl)) {
	if (!LIST_LIMIT_P(tbl)) {
	    r = list_id_table_insert(&tbl->aux.list, id, val);
	}
	else {
	    /* convert to hash */
	    /* overflow. TODO: this promotion should be done in list_extend_table */
	    struct list_id_table *list = &tbl->aux.list;
	    struct hash_id_table hash_body;
	    id_key_t *keys = list->keys;
	    VALUE *values = TABLE_VALUES(list);
	    const int num = list->num;
	    int i;

	    hash_id_table_init(&hash_body, 0);

	    for (i=0; i<num; i++) {
		/* note that GC can run */
		hash_id_table_insert_key(&hash_body, keys[i], values[i]);
	    }

	    tbl->aux.hash = hash_body;

	    /* free list keys/values */
	    xfree(keys);
#if ID_TABLE_USE_CALC_VALUES == 0
	    xfree(values);
#endif
	    goto hash_insert;
	}
    }
    else {
      hash_insert:
	r = hash_id_table_insert(&tbl->aux.hash, id, val);
	assert(!LIST_P(tbl));
    }
    return r;
}

static int
mix_id_table_lookup(struct mix_id_table *tbl, ID id, VALUE *valp)
{
    if (LIST_P(tbl)) return list_id_table_lookup(&tbl->aux.list, id, valp);
    else             return hash_id_table_lookup(&tbl->aux.hash, id, valp);
}

static int
mix_id_table_delete(struct mix_id_table *tbl, ID id)
{
    if (LIST_P(tbl)) return list_id_table_delete(&tbl->aux.list, id);
    else             return hash_id_table_delete(&tbl->aux.hash, id);
}

static void
mix_id_table_foreach(struct mix_id_table *tbl, rb_id_table_foreach_func_t *func, void *data)
{
    if (LIST_P(tbl)) list_id_table_foreach(&tbl->aux.list, func, data);
    else             hash_id_table_foreach(&tbl->aux.hash, func, data);
}

static void
mix_id_table_foreach_values(struct mix_id_table *tbl, rb_id_table_foreach_values_func_t *func, void *data)
{
    if (LIST_P(tbl)) list_id_table_foreach_values(&tbl->aux.list, func, data);
    else             hash_id_table_foreach_values(&tbl->aux.hash, func, data);
}

#endif /* ID_TABLE_USE_MIX */

#define IMPL_TYPE1(type, prot, name, args) \
    RUBY_ALIAS_FUNCTION_TYPE(type, prot, name, args)
#define IMPL_TYPE(type, name, prot, args) \
    IMPL_TYPE1(type, rb_id_table_##name prot, IMPL(_##name), args)
#define IMPL_VOID1(prot, name, args) \
    RUBY_ALIAS_FUNCTION_VOID(prot, name, args)
#define IMPL_VOID(name, prot, args) \
    IMPL_VOID1(rb_id_table_##name prot, IMPL(_##name), args)
#define id_tbl (ID_TABLE_IMPL_TYPE *)tbl

IMPL_TYPE(struct rb_id_table *, create, (size_t size), (size))
IMPL_VOID(free, (struct rb_id_table *tbl), (id_tbl))
IMPL_VOID(clear, (struct rb_id_table *tbl), (id_tbl))
IMPL_TYPE(size_t, size, (const struct rb_id_table *tbl), (id_tbl))
IMPL_TYPE(size_t, memsize, (const struct rb_id_table *tbl), (id_tbl))

IMPL_TYPE(int , insert, (struct rb_id_table *tbl, ID id, VALUE val),
	  (id_tbl, id, val))
IMPL_TYPE(int, lookup, (struct rb_id_table *tbl, ID id, VALUE *valp),
	  (id_tbl, id, valp))
IMPL_TYPE(int, delete, (struct rb_id_table *tbl, ID id),
	  (id_tbl, id))

IMPL_VOID(foreach,
	  (struct rb_id_table *tbl, rb_id_table_foreach_func_t *func, void *data),
	  (id_tbl, func, data))
IMPL_VOID(foreach_values,
	  (struct rb_id_table *tbl, rb_id_table_foreach_values_func_t *func, void *data),
	  (id_tbl, func, data))

#if ID_TABLE_STARTUP_SIG
__attribute__((constructor))
static void
show_impl(void)
{
    fprintf(stderr, "impl: %d\n", ID_TABLE_IMPL);
}
#endif
