/* This is a general purpose hash table package written by Peter Moore @ UCB. */

static	char	sccsid[] = "@(#) st.c 5.1 89/12/14 Crucible";
#ifndef lint
static char *rcsid = "$Header: /work/cvsroot/ruby/st.c,v 1.2 1994/06/27 15:48:41 matz Exp $";
#endif

#include <stdio.h>
#include "st.h"

extern void *xmalloc();
static rehash();

#define max(a,b) ((a) > (b) ? (a) : (b))
#define nil(type) ((type *) 0)
#define alloc(type) (type *)xmalloc((unsigned)sizeof(type))
#define Calloc(n,s) (char *)xcalloc((n),(s))

    /*
     * DEFAULT_MAX_DENSITY is the default for the largest we allow the
     * average number of items per bin before increasing the number of
     * bins
     *
     * DEFAULT_INIT_TABLE_SIZE is the default for the number of bins
     * allocated initially
     *
     * DEFAULT_GROW_FACTOR is the amount the hash table is expanded after
     * the density has reached max_density
     */

#define EQUAL(func, x, y) \
    ((func == ST_NUMCMP) ? ((x) == (y)) : ((*func)((x), (y)) == 0))

/*#define do_hash(key, table) (*table->hash)(key, table->num_bins)*/

#define do_hash(key, table)\
    ((table->hash == ST_PTRHASH) ? (((int) (key) >> 2) % table->num_bins) :\
	(table->hash == ST_NUMHASH) ? ((int) (key) % table->num_bins) :\
	(*table->hash)((key), table->num_bins))

st_table *st_init_table_with_params(compare, hash, size, density, grow_factor,
				    reorder_flag)
int (*compare)();
int (*hash)();
int size;
int density;
double grow_factor;
int reorder_flag;
{
    st_table *tbl;

    tbl = alloc(st_table);
    tbl->compare = compare;
    tbl->hash = hash;
    tbl->num_entries = 0;
    tbl->max_density = density;
    tbl->grow_factor = grow_factor;
    tbl->reorder_flag = reorder_flag;
    tbl->num_bins = size;
    tbl->bins = 
	(st_table_entry **) Calloc((unsigned)size, sizeof(st_table_entry *));
    return tbl;
}

st_table *st_init_table(compare, hash)
int (*compare)();
int (*hash)();
{
    return st_init_table_with_params(compare, hash, ST_DEFAULT_INIT_TABLE_SIZE,
				     ST_DEFAULT_MAX_DENSITY,
				     ST_DEFAULT_GROW_FACTOR,
				     ST_DEFAULT_REORDER_FLAG);
}

st_free_table(table)
st_table *table;
{
    register st_table_entry *ptr, *next;
    int i;

    for(i = 0; i < table->num_bins ; i++) {
	ptr = table->bins[i];
	while (ptr != nil(st_table_entry)) {
	    next = ptr->next;
	    free((char *) ptr);
	    ptr = next;
	}
    }
    free((char *) table->bins);
    free((char *) table);
}

#define PTR_NOT_EQUAL(table, ptr, key)\
(ptr != nil(st_table_entry) && !EQUAL(table->compare, key, (ptr)->key))

#define FIND_ENTRY(table, ptr, hash_val)\
ptr = (table)->bins[hash_val];\
if (PTR_NOT_EQUAL(table, ptr, key)) {\
    while (PTR_NOT_EQUAL(table, ptr->next, key)) {\
	ptr = ptr->next;\
    }\
    if (ptr->next != nil(st_table_entry) && (table)->reorder_flag) {\
	st_table_entry *_tmp = (ptr)->next;\
	(ptr)->next = (ptr)->next->next;\
	_tmp->next = (table)->bins[hash_val];\
	(table)->bins[hash_val] = _tmp;\
	ptr = _tmp;\
    } else {\
	ptr = ptr->next;\
    }\
}

st_lookup(table, key, value)
st_table *table;
register char *key;
char **value;
{
    int hash_val;
    register st_table_entry *ptr;

    hash_val = do_hash(key, table);

    FIND_ENTRY(table, ptr, hash_val);
    
    if (ptr == nil(st_table_entry)) {
	return 0;
    } else {
	if (value != nil(char *))  *value = ptr->record; 
	return 1;
    }
}

#define ADD_DIRECT(table, key, value, hash_val, tbl)\
{\
    if (table->num_entries/table->num_bins > table->max_density) {\
	rehash(table);\
	hash_val = do_hash(key,table);\
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

    if (ptr == nil(st_table_entry)) {
	ADD_DIRECT(table,key,value,hash_val,tbl);
	return 0;
    } else {
	ptr->record = value;
	return 1;
    }
}

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

st_find_or_add(table, key, slot)
st_table *table;
char *key;
char ***slot;
{
    int hash_val;
    st_table_entry *tbl, *ptr;

    hash_val = do_hash(key, table);

    FIND_ENTRY(table, ptr, hash_val);

    if (ptr == nil(st_table_entry)) {
	ADD_DIRECT(table, key, (char *)0, hash_val, tbl)
	if (slot != nil(char **)) *slot = &tbl->record;
	return 0;
    } else {
	if (slot != nil(char **)) *slot = &ptr->record;
	return 1;
    }
}

static rehash(table)
register st_table *table;
{
    register st_table_entry *ptr, *next, **old_bins = table->bins;
    int i, old_num_bins = table->num_bins, hash_val;

    table->num_bins = table->grow_factor*old_num_bins;
    
    if (table->num_bins%2 == 0) {
	table->num_bins += 1;
    }
    
    table->num_entries = 0;
    table->bins = 
      (st_table_entry **) Calloc((unsigned) table->num_bins,
	    sizeof(st_table_entry *));

    for(i = 0; i < old_num_bins ; i++) {
	ptr = old_bins[i];
	while (ptr != nil(st_table_entry)) {
	    next = ptr->next;
	    hash_val = do_hash(ptr->key, table);
	    ptr->next = table->bins[hash_val];
	    table->bins[hash_val] = ptr;
	    table->num_entries++;
	    ptr = next;
	}
    }
    free((char *) old_bins);
}

st_table *st_copy(old_table)
st_table *old_table;
{
    st_table *new_table;
    st_table_entry *ptr, *tbl;
    int i, num_bins = old_table->num_bins;

    new_table = alloc(st_table);
    if (new_table == nil(st_table)) {
	return nil(st_table);
    }
    
    *new_table = *old_table;
    new_table->bins = 
      (st_table_entry **) Calloc((unsigned) num_bins,
		sizeof(st_table_entry *));

    if (new_table->bins == nil(st_table_entry *)) {
	free((char *) new_table);
	return nil(st_table);
    }

    for(i = 0; i < num_bins ; i++) {
	new_table->bins[i] = nil(st_table_entry);
	ptr = old_table->bins[i];
	while (ptr != nil(st_table_entry)) {
	    tbl = alloc(st_table_entry);
	    if (tbl == nil(st_table_entry)) {
		free((char *) new_table->bins);
		free((char *) new_table);
		return nil(st_table);
	    }
	    *tbl = *ptr;
	    tbl->next = new_table->bins[i];
	    new_table->bins[i] = tbl;
	    ptr = ptr->next;
	}
    }
    return new_table;
}

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

    if (ptr == nil(st_table_entry)) {
	if (value != nil(char *)) *value = nil(char);
	return 0;
    }

    if (EQUAL(table->compare, *key, ptr->key)) {
	table->bins[hash_val] = ptr->next;
	table->num_entries--;
	if (value != nil(char *)) *value = ptr->record;
	*key = ptr->key;
	free((char *) ptr);
	return 1;
    }

    for(; ptr->next != nil(st_table_entry); ptr = ptr->next) {
	if (EQUAL(table->compare, ptr->next->key, *key)) {
	    tmp = ptr->next;
	    ptr->next = ptr->next->next;
	    table->num_entries--;
	    if (value != nil(char *)) *value = tmp->record;
	    *key = tmp->key;
	    free((char *) tmp);
	    return 1;
	}
    }

    return 0;
}

st_foreach(table, func, arg)
st_table *table;
enum st_retval (*func)();
char *arg;
{
    st_table_entry *ptr, *last, *tmp;
    enum st_retval retval;
    int i;

    for(i = 0; i < table->num_bins; i++) {
	last = nil(st_table_entry);
	for(ptr = table->bins[i]; ptr != nil(st_table_entry);) {
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
		if (last == nil(st_table_entry)) {
		    table->bins[i] = ptr->next;
		} else {
		    last->next = ptr->next;
		}
		ptr = ptr->next;
		free((char *) tmp);
	    }
	}
    }
}

st_strhash(string, modulus)
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
