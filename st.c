/* This is a general purpose hash table package written by Peter Moore @ UCB. */

static	char	sccsid[] = "@(#) st.c 5.1 89/12/14 Crucible";

#include "config.h"
#include <stdio.h>
#include "st.h"

#ifdef USE_CWGUSI
#include <stdlib.h>
#endif

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
static int numcmp();
static int numhash();
static struct st_hash_type type_numhash = {
    numcmp,
    numhash,
};

extern int strcmp();
static int strhash();
static struct st_hash_type type_strhash = {
    strcmp,
    strhash,
};

void *xmalloc();
void *xcalloc();
void *xrealloc();
static void rehash();

#ifndef max
#define max(a,b) ((a) > (b) ? (a) : (b))
#endif

#define alloc(type) (type*)xmalloc((unsigned)sizeof(type))
#define Calloc(n,s) (char*)xcalloc((n),(s))

#define EQUAL(table, x, y) ((*table->type->compare)(x, y) == 0)

#define do_hash(key, table) (*(table)->type->hash)((key), (table)->num_bins)
#define do_hash2(key, table, bins) (*(table)->type->hash)((key), bins)

st_table*
st_init_table_with_size(type, size)
    struct st_hash_type *type;
    int size;
{
    st_table *tbl;

    if (size == 0) size = ST_DEFAULT_INIT_TABLE_SIZE;
    else size /= ST_DEFAULT_MAX_DENSITY*0.87;

    if (size < ST_DEFAULT_INIT_TABLE_SIZE)
	size = ST_DEFAULT_INIT_TABLE_SIZE;

    tbl = alloc(st_table);
    tbl->type = type;
    tbl->num_entries = 0;
    tbl->num_bins = size;
    tbl->bins = (st_table_entry **)Calloc(size, sizeof(st_table_entry*));
    return tbl;
}

st_table*
st_init_table(type)
    struct st_hash_type *type;
{
    return st_init_table_with_size(type, 0);
}

st_table*
st_init_numtable()
{
    return st_init_table(&type_numhash);
}

st_table*
st_init_strtable()
{
    return st_init_table(&type_strhash);
}

void
st_free_table(table)
    st_table *table;
{
    register st_table_entry *ptr, *next;
    int i;

    for(i = 0; i < table->num_bins ; i++) {
	ptr = table->bins[i];
	while (ptr != 0) {
	    next = ptr->next;
	    free(ptr);
	    ptr = next;
	}
    }
    free(table->bins);
    free(table);
}

#define PTR_NOT_EQUAL(table, ptr, key) \
(ptr != 0 && !EQUAL(table, key, (ptr)->key))

#define FIND_ENTRY(table, ptr, hash_val) \
ptr = (table)->bins[hash_val];\
if (PTR_NOT_EQUAL(table, ptr, key)) {\
    while (PTR_NOT_EQUAL(table, ptr->next, key)) {\
	ptr = ptr->next;\
    }\
    ptr = ptr->next;\
}

int
st_lookup(table, key, value)
    st_table *table;
    register char *key;
    char **value;
{
    int hash_val;
    register st_table_entry *ptr;

    hash_val = do_hash(key, table);

    FIND_ENTRY(table, ptr, hash_val);

    if (ptr == 0) {
	return 0;
    } else {
	if (value != 0)  *value = ptr->record;
	return 1;
    }
}

#define ADD_DIRECT(table, key, value, hash_val, tbl)\
{\
    if (table->num_entries/table->num_bins > ST_DEFAULT_MAX_DENSITY) {\
	rehash(table);\
	hash_val = do_hash(key, table);\
    }\
    \
    tbl = alloc(st_table_entry);\
    \
    tbl->key = key;\
    tbl->record = value;\
    tbl->next = table->bins[hash_val];\
    table->bins[hash_val] = tbl;\
    table->num_entries++;\
}

int
st_insert(table, key, value)
    register st_table *table;
    register char *key;
    char *value;
{
    int hash_val;
    st_table_entry *tbl;
    register st_table_entry *ptr;

    hash_val = do_hash(key, table);

    FIND_ENTRY(table, ptr, hash_val);

    if (ptr == 0) {
	ADD_DIRECT(table,key,value,hash_val,tbl);
	return 0;
    } else {
	ptr->record = value;
	return 1;
    }
}

void
st_add_direct(table, key, value)
    st_table *table;
    char *key;
    char *value;
{
    int hash_val;
    st_table_entry *tbl;

    hash_val = do_hash(key, table);
    ADD_DIRECT(table, key, value, hash_val, tbl);
}

int
st_find_or_add(table, key, slot)
    st_table *table;
    char *key;
    char ***slot;
{
    int hash_val;
    st_table_entry *tbl, *ptr;

    hash_val = do_hash(key, table);

    FIND_ENTRY(table, ptr, hash_val);

    if (ptr == 0) {
	ADD_DIRECT(table, key, (char*)0, hash_val, tbl)
	if (slot != 0) *slot = &tbl->record;
	return 0;
    } else {
	if (slot != 0) *slot = &ptr->record;
	return 1;
    }
}

static void
rehash(table)
    register st_table *table;
{
    register st_table_entry *ptr, *next, **new_bins;
    int i, old_num_bins = table->num_bins, new_num_bins, hash_val;

    new_num_bins = 1.79*old_num_bins;

    if (new_num_bins%2 == 0) {
	new_num_bins += 1;
    }

    new_bins = (st_table_entry **)
	Calloc((unsigned)new_num_bins, sizeof(st_table_entry*));

    for(i = 0; i < old_num_bins ; i++) {
	ptr = table->bins[i];
	while (ptr != 0) {
	    next = ptr->next;
	    hash_val = do_hash2(ptr->key, table, new_num_bins);
	    ptr->next = new_bins[hash_val];
	    new_bins[hash_val] = ptr;
	    ptr = next;
	}
    }
    free(table->bins);
    table->num_bins = new_num_bins;
    table->bins = new_bins;
}

st_table*
st_copy(old_table)
    st_table *old_table;
{
    st_table *new_table;
    st_table_entry *ptr, *tbl;
    int i, num_bins = old_table->num_bins;

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

    for(i = 0; i < num_bins ; i++) {
	new_table->bins[i] = 0;
	ptr = old_table->bins[i];
	while (ptr != 0) {
	    tbl = alloc(st_table_entry);
	    if (tbl == 0) {
		free(new_table->bins);
		free(new_table);
		return 0;
	    }
	    *tbl = *ptr;
	    tbl->next = new_table->bins[i];
	    new_table->bins[i] = tbl;
	    ptr = ptr->next;
	}
    }
    return new_table;
}

int
st_delete(table, key, value)
    register st_table *table;
    register char **key;
    char **value;
{
    int hash_val;
    st_table_entry *tmp;
    register st_table_entry *ptr;

    hash_val = do_hash(*key, table);

    ptr = table->bins[hash_val];

    if (ptr == 0) {
	if (value != 0) *value = 0;
	return 0;
    }

    if (EQUAL(table, *key, ptr->key)) {
	table->bins[hash_val] = ptr->next;
	table->num_entries--;
	if (value != 0) *value = ptr->record;
	*key = ptr->key;
	free(ptr);
	return 1;
    }

    for(; ptr->next != 0; ptr = ptr->next) {
	if (EQUAL(table, ptr->next->key, *key)) {
	    tmp = ptr->next;
	    ptr->next = ptr->next->next;
	    table->num_entries--;
	    if (value != 0) *value = tmp->record;
	    *key = tmp->key;
	    free(tmp);
	    return 1;
	}
    }

    return 0;
}

int
st_delete_safe(table, key, value, never)
    register st_table *table;
    register char **key;
    char **value;
    char *never;
{
    int hash_val;
    register st_table_entry *ptr;

    hash_val = do_hash(*key, table);

    ptr = table->bins[hash_val];

    if (ptr == 0) {
	if (value != 0) *value = 0;
	return 0;
    }

    if (EQUAL(table, *key, ptr->key)) {
	table->num_entries--;
	*key = ptr->key;
	if (value != 0) *value = ptr->record;
	ptr->key = ptr->record = never;
	return 1;
    }

    for(; ptr->next != 0; ptr = ptr->next) {
	if (EQUAL(table, ptr->next->key, *key)) {
	    table->num_entries--;
	    *key = ptr->key;
	    if (value != 0) *value = ptr->record;
	    ptr->key = ptr->record = never;
	    return 1;
	}
    }

    return 0;
}

void
st_foreach(table, func, arg)
    st_table *table;
    enum st_retval (*func)();
    char *arg;
{
    st_table_entry *ptr, *last, *tmp;
    enum st_retval retval;
    int i;

    for(i = 0; i < table->num_bins; i++) {
	last = 0;
	for(ptr = table->bins[i]; ptr != 0;) {
	    retval = (*func)(ptr->key, ptr->record, arg);
	    switch (retval) {
	    case ST_CONTINUE:
		last = ptr;
		ptr = ptr->next;
		break;
	    case ST_STOP:
		return;
	    case ST_DELETE:
		tmp = ptr;
		if (last == 0) {
		    table->bins[i] = ptr->next;
		} else {
		    last->next = ptr->next;
		}
		ptr = ptr->next;
		free(tmp);
		table->num_entries--;
	    }
	}
    }
}

static int
strhash(string, modulus)
    register char *string;
    int modulus;
{
    register int val = 0;
    register int c;

    while ((c = *string++) != '\0') {
	val = val*997 + c;
    }

    return ((val < 0) ? -val : val)%modulus;
}

static int
numcmp(x, y)
    int x, y;
{
    return x != y;
}

static int
numhash(n, modulus)
    int n;
    int modulus;
{
    return n % modulus;
}
