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

#define ST_DEFAULT_MAX_DENSITY 5
#define ST_DEFAULT_INIT_TABLE_SIZE 11

    /*
     * DEFAULT_MAX_DENSITY is the default for the largest we allow the
     * average number of items per bin before increasing the number of
     * bins
     *
     * DEFAULT_INIT_TABLE_SIZE is the default for the number of bins
     * allocated initially
     *
     */

static const struct st_hash_type type_numhash = {
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
    st_strcasecmp,
    strcasehash,
};

static void rehash(st_table *);

#ifdef RUBY
#define malloc xmalloc
#define calloc xcalloc
#define free(x) xfree(x)
#endif

#define numberof(array) (int)(sizeof(array) / sizeof((array)[0]))

#define alloc(type) (type*)malloc((size_t)sizeof(type))
#define Calloc(n,s) (char*)calloc((n),(s))

#define EQUAL(table,x,y) ((x)==(y) || (*table->type->compare)((x),(y)) == 0)

/* remove cast to unsigned int in the future */
#define do_hash(key,table) (unsigned int)(st_index_t)(*(table)->type->hash)((key))
#define do_hash_bin(key,table) (do_hash(key, table)%(table)->num_bins)

/*
 * MINSIZE is the minimum size of a dictionary.
 */

#define MINSIZE 8

/*
Table of prime numbers 2^n+a, 2<=n<=30.
*/
static const unsigned int primes[] = {
	8 + 3,
	16 + 3,
	32 + 5,
	64 + 3,
	128 + 3,
	256 + 27,
	512 + 9,
	1024 + 9,
	2048 + 5,
	4096 + 3,
	8192 + 27,
	16384 + 43,
	32768 + 3,
	65536 + 45,
	131072 + 29,
	262144 + 3,
	524288 + 21,
	1048576 + 7,
	2097152 + 17,
	4194304 + 15,
	8388608 + 9,
	16777216 + 43,
	33554432 + 35,
	67108864 + 15,
	134217728 + 29,
	268435456 + 3,
	536870912 + 11,
	1073741824 + 85,
	0
};

static st_index_t
new_size(st_index_t size)
{
    int i;

#if 0
    for (i=3; i<31; i++) {
	if ((1<<i) > size) return 1<<i;
    }
    return -1;
#else
    st_index_t newsize;

    for (i = 0, newsize = MINSIZE; i < numberof(primes); i++, newsize <<= 1) {
	if (newsize > size) return primes[i];
    }
    /* Ran out of polynomials */
#ifndef NOT_RUBY
    rb_raise(rb_eRuntimeError, "st_table too big");
#endif
    return -1;			/* should raise exception */
#endif
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

#define MAX_PACKED_NUMHASH (ST_DEFAULT_INIT_TABLE_SIZE/2)

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

    size = new_size(size);	/* round up to prime number */

    tbl = alloc(st_table);
    tbl->type = type;
    tbl->num_entries = 0;
    tbl->entries_packed = type == &type_numhash && size/2 <= MAX_PACKED_NUMHASH;
    tbl->num_bins = size;
    tbl->bins = (st_table_entry **)Calloc(size, sizeof(st_table_entry*));
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
        return;
    }

    for(i = 0; i < table->num_bins; i++) {
	ptr = table->bins[i];
	table->bins[i] = 0;
	while (ptr != 0) {
	    next = ptr->next;
	    free(ptr);
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
    free(table->bins);
    free(table);
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
((ptr) != 0 && (ptr->hash != (hash_val) || !EQUAL((table), (key), (ptr)->key)))

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

#define FIND_ENTRY(table, ptr, hash_val, bin_pos) do {\
    bin_pos = hash_val%(table)->num_bins;\
    ptr = (table)->bins[bin_pos];\
    FOUND_ENTRY;\
    if (PTR_NOT_EQUAL(table, ptr, hash_val, key)) {\
	COLLISION;\
	while (PTR_NOT_EQUAL(table, ptr->next, hash_val, key)) {\
	    ptr = ptr->next;\
	}\
	ptr = ptr->next;\
    }\
} while (0)

#define collision_check 0

int
st_lookup(st_table *table, register st_data_t key, st_data_t *value)
{
    st_index_t hash_val, bin_pos;
    register st_table_entry *ptr;

    if (table->entries_packed) {
        st_index_t i;
        for (i = 0; i < table->num_entries; i++) {
            if ((st_data_t)table->bins[i*2] == key) {
                if (value !=0) *value = (st_data_t)table->bins[i*2+1];
                return 1;
            }
        }
        return 0;
    }

    hash_val = do_hash(key, table);
    FIND_ENTRY(table, ptr, hash_val, bin_pos);

    if (ptr == 0) {
	return 0;
    }
    else {
	if (value != 0)  *value = ptr->record;
	return 1;
    }
}

int
st_get_key(st_table *table, register st_data_t key, st_data_t *result)
{
    st_index_t hash_val, bin_pos;
    register st_table_entry *ptr;

    if (table->entries_packed) {
        st_index_t i;
        for (i = 0; i < table->num_entries; i++) {
            if ((st_data_t)table->bins[i*2] == key) {
                if (result !=0) *result = (st_data_t)table->bins[i*2];
                return 1;
            }
        }
        return 0;
    }

    hash_val = do_hash(key, table);
    FIND_ENTRY(table, ptr, hash_val, bin_pos);

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

#define MORE_PACKABLE_P(table) \
    ((st_index_t)((table)->num_entries+1) * 2 <= (table)->num_bins && \
     (table)->num_entries+1 <= MAX_PACKED_NUMHASH)

#define ADD_DIRECT(table, key, value, hash_val, bin_pos)\
do {\
    st_table_entry *entry;\
    if (table->num_entries > ST_DEFAULT_MAX_DENSITY * table->num_bins) {\
	rehash(table);\
        bin_pos = hash_val % table->num_bins;\
    }\
    \
    entry = alloc(st_table_entry);\
    \
    entry->hash = hash_val;\
    entry->key = key;\
    entry->record = value;\
    entry->next = table->bins[bin_pos];\
    if (table->head != 0) {\
	entry->fore = 0;\
	(entry->back = table->tail)->fore = entry;\
	table->tail = entry;\
    }\
    else {\
	table->head = table->tail = entry;\
	entry->fore = entry->back = 0;\
    }\
    table->bins[bin_pos] = entry;\
    table->num_entries++;\
} while (0)

static void
unpack_entries(register st_table *table)
{
    st_index_t i;
    struct st_table_entry *packed_bins[MAX_PACKED_NUMHASH*2];
    st_table tmp_table = *table;

    memcpy(packed_bins, table->bins, sizeof(struct st_table_entry *) * table->num_entries*2);
    table->bins = packed_bins;
    tmp_table.entries_packed = 0;
    tmp_table.num_entries = 0;
    memset(tmp_table.bins, 0, sizeof(struct st_table_entry *) * tmp_table.num_bins);
    for (i = 0; i < table->num_entries; i++) {
        st_insert(&tmp_table, (st_data_t)packed_bins[i*2], (st_data_t)packed_bins[i*2+1]);
    }
    *table = tmp_table;
}

int
st_insert(register st_table *table, register st_data_t key, st_data_t value)
{
    st_index_t hash_val, bin_pos;
    register st_table_entry *ptr;

    if (table->entries_packed) {
        st_index_t i;
        for (i = 0; i < table->num_entries; i++) {
            if ((st_data_t)table->bins[i*2] == key) {
                table->bins[i*2+1] = (struct st_table_entry*)value;
                return 1;
            }
        }
        if (MORE_PACKABLE_P(table)) {
            i = table->num_entries++;
            table->bins[i*2] = (struct st_table_entry*)key;
            table->bins[i*2+1] = (struct st_table_entry*)value;
            return 0;
        }
        else {
            unpack_entries(table);
        }
    }

    hash_val = do_hash(key, table);
    FIND_ENTRY(table, ptr, hash_val, bin_pos);

    if (ptr == 0) {
	ADD_DIRECT(table, key, value, hash_val, bin_pos);
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
    st_index_t hash_val, bin_pos;
    register st_table_entry *ptr;

    if (table->entries_packed) {
        st_index_t i;
        for (i = 0; i < table->num_entries; i++) {
            if ((st_data_t)table->bins[i*2] == key) {
                table->bins[i*2+1] = (struct st_table_entry*)value;
                return 1;
            }
        }
        if (MORE_PACKABLE_P(table)) {
            i = table->num_entries++;
            table->bins[i*2] = (struct st_table_entry*)key;
            table->bins[i*2+1] = (struct st_table_entry*)value;
            return 0;
        }
        else {
            unpack_entries(table);
        }
    }

    hash_val = do_hash(key, table);
    FIND_ENTRY(table, ptr, hash_val, bin_pos);

    if (ptr == 0) {
	key = (*func)(key);
	ADD_DIRECT(table, key, value, hash_val, bin_pos);
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
    st_index_t hash_val, bin_pos;

    if (table->entries_packed) {
        int i;
        if (MORE_PACKABLE_P(table)) {
            i = table->num_entries++;
            table->bins[i*2] = (struct st_table_entry*)key;
            table->bins[i*2+1] = (struct st_table_entry*)value;
            return;
        }
        else {
            unpack_entries(table);
        }
    }

    hash_val = do_hash(key, table);
    bin_pos = hash_val % table->num_bins;
    ADD_DIRECT(table, key, value, hash_val, bin_pos);
}

static void
rehash(register st_table *table)
{
    register st_table_entry *ptr, **new_bins;
    st_index_t i, new_num_bins, hash_val;

    new_num_bins = new_size(table->num_bins+1);
    new_bins = (st_table_entry**)
	xrealloc(table->bins, new_num_bins * sizeof(st_table_entry*));
    for (i = 0; i < new_num_bins; ++i) new_bins[i] = 0;
    table->num_bins = new_num_bins;
    table->bins = new_bins;

    if ((ptr = table->head) != 0) {
	do {
	    hash_val = ptr->hash % new_num_bins;
	    ptr->next = new_bins[hash_val];
	    new_bins[hash_val] = ptr;
	} while ((ptr = ptr->fore) != 0);
    }
}

st_table*
st_copy(st_table *old_table)
{
    st_table *new_table;
    st_table_entry *ptr, *entry, *prev, **tail;
    st_index_t num_bins = old_table->num_bins;
    st_index_t hash_val;

    new_table = alloc(st_table);
    if (new_table == 0) {
	return 0;
    }

    *new_table = *old_table;
    new_table->bins = (st_table_entry**)
	Calloc((unsigned)num_bins, sizeof(st_table_entry*));

    if (new_table->bins == 0) {
	free(new_table);
	return 0;
    }

    if (old_table->entries_packed) {
        memcpy(new_table->bins, old_table->bins, sizeof(struct st_table_entry *) * old_table->num_bins);
        return new_table;
    }

    if ((ptr = old_table->head) != 0) {
	prev = 0;
	tail = &new_table->head;
	do {
	    entry = alloc(st_table_entry);
	    if (entry == 0) {
		st_free_table(new_table);
		return 0;
	    }
	    *entry = *ptr;
	    hash_val = entry->hash % num_bins;
	    entry->next = new_table->bins[hash_val];
	    new_table->bins[hash_val] = entry;
	    entry->back = prev;
	    *tail = prev = entry;
	    tail = &entry->fore;
	} while ((ptr = ptr->fore) != 0);
	new_table->tail = prev;
    }

    return new_table;
}

#define REMOVE_ENTRY(table, ptr) do					\
    {									\
	if (ptr->fore == 0 && ptr->back == 0) {				\
	    table->head = 0;						\
	    table->tail = 0;						\
	}								\
	else {								\
	    st_table_entry *fore = ptr->fore, *back = ptr->back;	\
	    if (fore) fore->back = back;				\
	    if (back) back->fore = fore;				\
	    if (ptr == table->head) table->head = fore;			\
	    if (ptr == table->tail) table->tail = back;			\
	}								\
	table->num_entries--;						\
    } while (0)

int
st_delete(register st_table *table, register st_data_t *key, st_data_t *value)
{
    st_index_t hash_val;
    st_table_entry **prev;
    register st_table_entry *ptr;

    if (table->entries_packed) {
        st_index_t i;
        for (i = 0; i < table->num_entries; i++) {
            if ((st_data_t)table->bins[i*2] == *key) {
                if (value != 0) *value = (st_data_t)table->bins[i*2+1];
                table->num_entries--;
                memmove(&table->bins[i*2], &table->bins[(i+1)*2],
                        sizeof(struct st_table_entry*) * 2*(table->num_entries-i));
                return 1;
            }
        }
        if (value != 0) *value = 0;
        return 0;
    }

    hash_val = do_hash_bin(*key, table);

    for (prev = &table->bins[hash_val]; (ptr = *prev) != 0; prev = &ptr->next) {
	if (EQUAL(table, *key, ptr->key)) {
	    *prev = ptr->next;
	    REMOVE_ENTRY(table, ptr);
	    if (value != 0) *value = ptr->record;
	    *key = ptr->key;
	    free(ptr);
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

    if (table->entries_packed) {
	st_index_t i;
	for (i = 0; i < table->num_entries; i++) {
	    if ((st_data_t)table->bins[i*2] == *key) {
		if (value != 0) *value = (st_data_t)table->bins[i*2+1];
		table->bins[i*2] = (void *)never;
		return 1;
	    }
	}
	if (value != 0) *value = 0;
	return 0;
    }

    hash_val = do_hash_bin(*key, table);
    ptr = table->bins[hash_val];

    for (; ptr != 0; ptr = ptr->next) {
	if ((ptr->key != never) && EQUAL(table, ptr->key, *key)) {
	    REMOVE_ENTRY(table, ptr);
	    *key = ptr->key;
	    if (value != 0) *value = ptr->record;
	    ptr->key = ptr->record = never;
	    return 1;
	}
    }

    if (value != 0) *value = 0;
    return 0;
}

void
st_cleanup_safe(st_table *table, st_data_t never)
{
    st_table_entry *ptr, **last, *tmp;
    st_index_t i;

    if (table->entries_packed) {
	st_index_t i = 0, j = 0;
	while ((st_data_t)table->bins[i*2] != never) {
	    if (i++ == table->num_entries) return;
	}
	for (j = i; ++i < table->num_entries;) {
	    if ((st_data_t)table->bins[i*2] == never) continue;
	    table->bins[j*2] = table->bins[i*2];
	    table->bins[j*2+1] = table->bins[i*2+1];
	    j++;
	}
	table->num_entries = j;
	return;
    }

    for (i = 0; i < table->num_bins; i++) {
	ptr = *(last = &table->bins[i]);
	while (ptr != 0) {
	    if (ptr->key == never) {
		tmp = ptr;
		*last = ptr = ptr->next;
		free(tmp);
	    }
	    else {
		ptr = *(last = &ptr->next);
	    }
	}
    }
}

int
st_foreach(st_table *table, int (*func)(ANYARGS), st_data_t arg)
{
    st_table_entry *ptr, **last, *tmp;
    enum st_retval retval;
    st_index_t i;

    if (table->entries_packed) {
        for (i = 0; i < table->num_entries; i++) {
            st_index_t j;
            st_data_t key, val;
            key = (st_data_t)table->bins[i*2];
            val = (st_data_t)table->bins[i*2+1];
            retval = (*func)(key, val, arg);
            switch (retval) {
	      case ST_CHECK:	/* check if hash is modified during iteration */
                for (j = 0; j < table->num_entries; j++) {
                    if ((st_data_t)table->bins[j*2] == key)
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
                table->num_entries--;
                memmove(&table->bins[i*2], &table->bins[(i+1)*2],
                        sizeof(struct st_table_entry*) * 2*(table->num_entries-i));
                i--;
                break;
            }
        }
        return 0;
    }

    if ((ptr = table->head) != 0) {
	do {
	    retval = (*func)(ptr->key, ptr->record, arg);
	    switch (retval) {
	      case ST_CHECK:	/* check if hash is modified during iteration */
		i = ptr->hash % table->num_bins;
		for (tmp = table->bins[i]; tmp != ptr; tmp = tmp->next) {
		    if (!tmp) {
			/* call func with error notice */
			retval = (*func)(0, 0, arg, 1);
			return 1;
		    }
		}
		/* fall through */
	      case ST_CONTINUE:
		ptr = ptr->fore;
		break;
	      case ST_STOP:
		return 0;
	      case ST_DELETE:
		last = &table->bins[ptr->hash % table->num_bins];
		for (; (tmp = *last) != 0; last = &tmp->next) {
		    if (ptr == tmp) {
			tmp = ptr->fore;
			*last = ptr->next;
			REMOVE_ENTRY(table, ptr);
			free(ptr);
			if (ptr == tmp) return 0;
			ptr = tmp;
			break;
		    }
		}
	    }
	} while (ptr && table->head);
    }
    return 0;
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
            key = (st_data_t)table->bins[i*2];
            val = (st_data_t)table->bins[i*2+1];
            retval = (*func)(key, val, arg);
            switch (retval) {
	      case ST_CHECK:	/* check if hash is modified during iteration */
                for (j = 0; j < table->num_entries; j++) {
                    if ((st_data_t)table->bins[j*2] == key)
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
                table->num_entries--;
                memmove(&table->bins[i*2], &table->bins[(i+1)*2],
                        sizeof(struct st_table_entry*) * 2*(table->num_entries-i));
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
		i = ptr->hash % table->num_bins;
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
		last = &table->bins[ptr->hash % table->num_bins];
		for (; (tmp = *last) != 0; last = &tmp->next) {
		    if (ptr == tmp) {
			tmp = ptr->back;
			*last = ptr->next;
			REMOVE_ENTRY(table, ptr);
			free(ptr);
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
# if defined __i386__ || defined _M_IX86
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

#if MURMUR == 1
#define MurmurMagic 0xc6a4a793
#elif MURMUR == 2
#if SIZEOF_ST_INDEX_T > 4
#define MurmurMagic 0xc6a4a7935bd1e995
#else
#define MurmurMagic 0x5bd1e995
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

#define murmur_step(h, k) murmur(h, k, 16)

#if MURMUR == 1
#define murmur1(h) murmur_step(h, 16)
#else
#define murmur1(h) murmur_step(h, 24)
#endif

st_index_t
st_hash(const void *ptr, size_t len, st_index_t h)
{
    const char *data = ptr;
    st_index_t t = 0;

    h += 0xdeadbeef;

#define data_at(n) (st_index_t)((unsigned char)data[n])
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
st_strcasecmp(const char *s1, const char *s2)
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
st_strncasecmp(const char *s1, const char *s2, size_t n)
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
    return (st_index_t)n;
}
