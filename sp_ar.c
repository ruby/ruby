/*
 * sparse array lib
 * inspired by Lua table
 * written by Sokolov Yura aka funny_falcon
 */
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

#ifdef RUBY
#define malloc xmalloc
#define calloc xcalloc
#define realloc xrealloc
#define free   xfree
#endif

#define sa_table_alloc()          (sa_table*)malloc(sizeof(sa_table))
#define sa_table_xalloc()         (sa_table*)calloc(1, sizeof(sa_table))
#define sa_table_dealloc(table)   free(table)
#define sa_entry_alloc(n)         (sa_entry*)calloc((n), sizeof(sa_entry))
#define sa_entry_dealloc(entries) free(entries)

#define SA_LAST   1
#define SA_OFFSET 2

#define SA_MIN_SIZE 4

void
sa_init_table(register sa_table *table, sa_index_t num_bins)
{
    if (num_bins) {
        table->num_entries = 0;
        table->entries = sa_entry_alloc(num_bins);
        table->num_bins = num_bins;
        table->free_pos = num_bins;
    }
    else {
        memset(table, 0, sizeof(sa_table));
    }
}

sa_table*
sa_new_table()
{
    sa_table* table = sa_table_alloc();
    sa_init_table(table, 0);
    return table;
}

static inline sa_index_t
calc_pos(register sa_table* table, sa_index_t key)
{
    /* this formula is empirical */
    /* it has no good avalanche, but works well in our case */
    key ^= key >> 16;
    key *= 0x445229;
    return (key + (key >> 16)) % table->num_bins;
}

static void
fix_empty(register sa_table* table)
{
    while(--table->free_pos &&
            table->entries[table->free_pos-1].next != SA_EMPTY);
}

#define FLOOR_TO_4 ((~((sa_index_t)0)) << 2)
static sa_index_t
find_empty(register sa_table* table, register sa_index_t pos)
{
    sa_index_t new_pos = table->free_pos-1;
    sa_entry *entry;
    pos &= FLOOR_TO_4;
    entry = table->entries+pos;

    if (entry->next == SA_EMPTY) { new_pos = pos; goto check; }
    pos++; entry++;
    if (entry->next == SA_EMPTY) { new_pos = pos; goto check; }
    pos++; entry++;
    if (entry->next == SA_EMPTY) { new_pos = pos; goto check; }
    pos++; entry++;
    if (entry->next == SA_EMPTY) { new_pos = pos; goto check; }

check:
    if (new_pos+1 == table->free_pos) fix_empty(table);
    return new_pos;
}

static void resize(register sa_table* table);
static int insert_into_chain(register sa_table*, register sa_index_t, st_data_t, sa_index_t pos);
static int insert_into_main(register sa_table*, sa_index_t, st_data_t, sa_index_t pos, sa_index_t prev_pos);

int
sa_insert(register sa_table* table, register sa_index_t key, st_data_t value)
{
    sa_index_t pos, main_pos;
    register sa_entry *entry;

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
insert_into_chain(register sa_table* table, register sa_index_t key, st_data_t value, sa_index_t pos)
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
insert_into_main(register sa_table* table, sa_index_t key, st_data_t value, sa_index_t pos, sa_index_t prev_pos)
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
    sa_index_t msb = num_entries;
    msb |= msb >> 1;
    msb |= msb >> 2;
    msb |= msb >> 4;
    msb |= msb >> 8;
    msb |= msb >> 16;
    msb = ((msb >> 4) + 1) << 3;
    return (num_entries & (msb | (msb >> 1))) + (msb >> 1);
}

static void
resize(register sa_table *table)
{
    sa_table tmp_table;
    sa_entry *entry;
    sa_index_t i;

    if (table->num_entries == 0) {
        sa_entry_dealloc(table->entries);
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
    sa_entry_dealloc(table->entries);
    *table = tmp_table;
}

int
sa_lookup(register sa_table *table, register sa_index_t key, st_data_t *value)
{
    register sa_entry *entry;

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
    if (value) *value = entry->value;
    return 1;
}

void
sa_clear(sa_table *table)
{
    sa_entry_dealloc(table->entries);
    memset(table, 0, sizeof(sa_table));
}

void
sa_clear_no_free(sa_table *table)
{
    memset(table->entries, 0, sizeof(sa_entry) * table->num_bins);
    table->num_entries = 0;
    table->free_pos = table->num_bins;
}

void
sa_free_table(sa_table *table)
{
    sa_entry_dealloc(table->entries);
    sa_table_dealloc(table);
}

int
sa_delete(sa_table *table, sa_index_t key, st_data_t *value)
{
    sa_index_t pos, prev_pos = ~0;
    sa_entry *entry;

    if (table->num_entries == 0) goto not_found;

    pos = calc_pos(table, key);
    entry = table->entries + pos;

    if (entry->next == SA_EMPTY) goto not_found;

    do {
        if (entry->key == key) {
            if (value) *value = entry->value;
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
    if (value) *value = 0;
    return 0;
}

int
sa_foreach(register sa_table *table, int (*func)(), st_data_t arg)
{
    sa_index_t i;
    if (table->num_bins == 0) {
        return 0;
    }
    for(i = 0; i < table->num_bins ; i++) {
	if (table->entries[i].next != SA_EMPTY) {
	    sa_index_t key = table->entries[i].key;
	    st_data_t val = table->entries[i].value;
	    if ((*func)(key, val, arg) == SA_STOP) break;
	}
    }
    return 0;
}

size_t
sa_memsize(const sa_table *table)
{
    return sizeof(sa_table) + table->num_bins * sizeof(sa_entry);
}

sa_table*
sa_copy(sa_table *table)
{
    sa_table *new_table = sa_table_alloc();
    *new_table = *table;
    if (table->num_bins) {
        new_table->entries = sa_entry_alloc(table->num_bins);
        memcpy(new_table->entries, table->entries, table->num_bins*sizeof(sa_entry));
    }
    return new_table;
}

void
sa_copy_to(sa_table *from, sa_table *to)
{
    sa_entry_dealloc(to->entries);
    *to = *from;
    if (to->num_bins) {
	to->entries = sa_entry_alloc(to->num_bins);
	memcpy(to->entries, from->entries, from->num_bins*sizeof(sa_entry));
    }
}
