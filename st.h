/* This is a general purpose hash table package written by Peter Moore @ UCB. */

/* @(#) st.h 5.1 89/12/14 */

#ifndef ST_INCLUDED

#define ST_INCLUDED

typedef struct st_table_entry st_table_entry;

struct st_table_entry {
    char *key;
    char *record;
    st_table_entry *next;
};

typedef struct st_table st_table;

struct st_hash_type {
    int (*compare)();
    int (*hash)();
};

struct st_table {
    struct st_hash_type *type;
    int num_bins;
    int num_entries;
    st_table_entry **bins;
};

#define st_is_member(table,key) st_lookup(table,key,(char **) 0)

enum st_retval {ST_CONTINUE, ST_STOP, ST_DELETE};

st_table *st_init_table();
st_table *st_init_table_with_size();
st_table *st_init_numtable();
st_table *st_init_strtable();
int st_delete(), st_delete_safe(), st_insert();
int st_lookup(), st_find_or_add();
void st_foreach(), st_add_direct(), st_free_table();
st_table *st_copy();

#define ST_NUMCMP	((int (*)()) 0)
#define ST_NUMHASH	((int (*)()) -2)

#define st_numcmp	ST_NUMCMP
#define st_numhash	ST_NUMHASH

int st_strhash();

#endif /* ST_INCLUDED */
