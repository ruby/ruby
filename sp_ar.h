/*
 * sparse array lib
 * inspired by Lua table
 * written by Sokolov Yura aka funny_falcon
 */

#ifndef RUBY_SP_AR_H
#define RUBY_SP_AR_H

#include "ruby/st.h"

#if HAVE_UINT32_T
  typedef uint32_t sp_ar_index_t;
#else
  typedef unsigned int sp_ar_index_t;
#endif

#define SP_AR_STOP     ST_STOP
#define SP_AR_CONTINUE ST_CONTINUE

#define SP_AR_EMPTY   0

typedef struct sp_ar_entry {
    sp_ar_index_t next;
    sp_ar_index_t key;
    st_data_t value;
} sp_ar_entry;

typedef struct sp_ar_table {
    sp_ar_index_t num_bins;
    sp_ar_index_t num_entries;
    sp_ar_index_t free_pos;
    sp_ar_entry *entries;
} sp_ar_table;

#define SP_AR_EMPTY_TABLE {0, 0, 0, 0};
void sp_ar_init_table(sp_ar_table *, sp_ar_index_t);
sp_ar_table *sp_ar_new_table();
int  sp_ar_insert(sp_ar_table *, sp_ar_index_t, st_data_t);
int  sp_ar_lookup(sp_ar_table *, sp_ar_index_t, st_data_t *);
int  sp_ar_delete(sp_ar_table *, sp_ar_index_t, st_data_t *);
void sp_ar_clear(sp_ar_table *);
void sp_ar_clear_no_free(sp_ar_table *);
void sp_ar_free_table(sp_ar_table *);
int  sp_ar_foreach(sp_ar_table *, int (*)(ANYARGS), st_data_t);
size_t sp_ar_memsize(const sp_ar_table *);
sp_ar_table *sp_ar_copy(sp_ar_table*);
void sp_ar_copy_to(sp_ar_table*, sp_ar_table*);
typedef int (*sp_ar_iter_func)(sp_ar_index_t key, st_data_t val, st_data_t arg);

#define SP_AR_FOREACH_START_I(table, entry) do { \
    sp_ar_table *T##entry = (table); \
    sp_ar_index_t K##entry; \
    for(K##entry = 0; K##entry < T##entry->num_bins; K##entry++) { \
	sp_ar_entry *entry = T##entry->entries + K##entry; \
	if (entry->next != SP_AR_EMPTY) { \
	    st_data_t value = entry->value
#define SP_AR_FOREACH_END() } } } while(0)

#define SP_AR_FOREACH_START(table) SP_AR_FOREACH_START_I(table, entry)

#endif
