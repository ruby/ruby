#ifndef INTERNAL_SET_TABLE_H
#define INTERNAL_SET_TABLE_H

#include "include/ruby/st.h"

struct set_table_entry;

typedef struct set_table_entry set_table_entry;

struct set_table {
    /* Cached features of the table -- see st.c for more details.  */
    unsigned char entry_power, bin_power, size_ind;
    /* How many times the table was rebuilt.  */
    unsigned int rebuilds_num;
    const struct st_hash_type *type;
    /* Number of entries currently in the table.  */
    st_index_t num_entries;
    /* Array of bins used for access by keys.  */
    st_index_t *bins;
    /* Start and bound index of entries in array entries.
       entries_starts and entries_bound are in interval
       [0,allocated_entries].  */
    st_index_t entries_start, entries_bound;
    /* Array of size 2^entry_power.  */
    set_table_entry *entries;
};

typedef struct set_table set_table;

typedef int set_foreach_callback_func(st_data_t, st_data_t);
typedef int set_foreach_check_callback_func(st_data_t, st_data_t, int);
typedef int set_update_callback_func(st_data_t *key, st_data_t arg, int existing);

#define set_table_size rb_set_table_size
size_t rb_set_table_size(const struct set_table *tbl);
#define set_init_table_with_size rb_set_init_table_with_size
set_table *rb_set_init_table_with_size(set_table *tab, const struct st_hash_type *, st_index_t);
#define set_delete rb_set_delete
int rb_set_delete(set_table *, st_data_t *); /* returns 0:notfound 1:deleted */
#define set_insert rb_set_insert
int rb_set_insert(set_table *, st_data_t);
#define set_lookup rb_set_lookup
int rb_set_lookup(set_table *, st_data_t);
#define set_foreach_with_replace rb_set_foreach_with_replace
int rb_set_foreach_with_replace(set_table *tab, set_foreach_check_callback_func *func, set_update_callback_func *replace, st_data_t arg);
#define set_foreach rb_set_foreach
int rb_set_foreach(set_table *, set_foreach_callback_func *, st_data_t);
#define set_foreach_check rb_set_foreach_check
int rb_set_foreach_check(set_table *, set_foreach_check_callback_func *, st_data_t, st_data_t);
#define set_keys rb_set_keys
st_index_t rb_set_keys(set_table *table, st_data_t *keys, st_index_t size);
#define set_free_table rb_set_free_table
void rb_set_free_table(set_table *);
#define set_clear rb_set_clear
void rb_set_clear(set_table *);
#define set_copy rb_set_copy
set_table *rb_set_copy(set_table *new_table, set_table *old_table);
#define set_memsize rb_set_memsize
PUREFUNC(size_t rb_set_memsize(const set_table *));
#define set_compact_table rb_set_compact_table
void set_compact_table(set_table *tab);

#endif
