/* This is a public domain general purpose hash table package written by Peter Moore @ UCB. */

/* @(#) st.h 5.1 89/12/14 */

#ifndef ST_INCLUDED

#define ST_INCLUDED

typedef struct st_table st_table;

struct st_hash_type {
    int (*compare)();
    int (*hash)();
};

struct st_table {
    struct st_hash_type *type;
    int num_bins;
    int num_entries;
    struct st_table_entry **bins;
};

#define st_is_member(table,key) st_lookup(table,key,(char **)0)

enum st_retval {ST_CONTINUE, ST_STOP, ST_DELETE};

st_table *st_init_table();
st_table *st_init_table_with_size();
st_table *st_init_numtable();
st_table *st_init_numtable_with_size();
st_table *st_init_strtable();
st_table *st_init_strtable_with_size();
int st_delete(), st_delete_safe();
int st_insert(), st_lookup();
void st_foreach(), st_add_direct(), st_free_table(), st_cleanup_safe();
st_table *st_copy();

#define ST_NUMCMP	((int (*)()) 0)
#define ST_NUMHASH	((int (*)()) -2)

#define st_numcmp	ST_NUMCMP
#define st_numhash	ST_NUMHASH

int st_strhash();

#endif /* ST_INCLUDED */
