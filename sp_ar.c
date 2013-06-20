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

#define sp_ar_table_alloc()          (sp_ar_table*)malloc(sizeof(sp_ar_table))
#define sp_ar_table_xalloc()         (sp_ar_table*)calloc(1, sizeof(sp_ar_table))
#define sp_ar_table_dealloc(table)   free(table)
#define sp_ar_entry_alloc(n)         (sp_ar_entry*)calloc((n), sizeof(sp_ar_entry))
#define sp_ar_entry_dealloc(entries) free(entries)

#define SP_AR_LAST   1
#define SP_AR_OFFSET 2

#define SP_AR_MIN_SIZE 4

void
sp_ar_init_table(register sp_ar_table *table, sp_ar_index_t num_bins)
{
    if (num_bins) {
        table->num_entries = 0;
        table->entries = sp_ar_entry_alloc(num_bins);
        table->num_bins = num_bins;
        table->free_pos = num_bins;
    }
    else {
        memset(table, 0, sizeof(sp_ar_table));
    }
}

sp_ar_table*
sp_ar_new_table()
{
    sp_ar_table* table = sp_ar_table_alloc();
    sp_ar_init_table(table, 0);
    return table;
}

static inline sp_ar_index_t
calc_pos(register sp_ar_table* table, sp_ar_index_t key)
{
    /* this formula is empirical */
    /* it has no good avalanche, but works well in our case */
    key ^= key >> 16;
    key *= 0x445229;
    return (key + (key >> 16)) % table->num_bins;
}

static void
fix_empty(register sp_ar_table* table)
{
    while(--table->free_pos &&
            table->entries[table->free_pos-1].next != SP_AR_EMPTY);
}

#define FLOOR_TO_4 ((~((sp_ar_index_t)0)) << 2)
static sp_ar_index_t
find_empty(register sp_ar_table* table, register sp_ar_index_t pos)
{
    sp_ar_index_t new_pos = table->free_pos-1;
    sp_ar_entry *entry;
    pos &= FLOOR_TO_4;
    entry = table->entries+pos;

    if (entry->next == SP_AR_EMPTY) { new_pos = pos; goto check; }
    pos++; entry++;
    if (entry->next == SP_AR_EMPTY) { new_pos = pos; goto check; }
    pos++; entry++;
    if (entry->next == SP_AR_EMPTY) { new_pos = pos; goto check; }
    pos++; entry++;
    if (entry->next == SP_AR_EMPTY) { new_pos = pos; goto check; }

check:
    if (new_pos+1 == table->free_pos) fix_empty(table);
    return new_pos;
}

static void resize(register sp_ar_table* table);
static int insert_into_chain(register sp_ar_table*, register sp_ar_index_t, st_data_t, sp_ar_index_t pos);
static int insert_into_main(register sp_ar_table*, sp_ar_index_t, st_data_t, sp_ar_index_t pos, sp_ar_index_t prev_pos);

int
sp_ar_insert(register sp_ar_table* table, register sp_ar_index_t key, st_data_t value)
{
    sp_ar_index_t pos, main_pos;
    register sp_ar_entry *entry;

    if (table->num_bins == 0) {
        sp_ar_init_table(table, SP_AR_MIN_SIZE);
    }

    pos = calc_pos(table, key);
    entry = table->entries + pos;

    if (entry->next == SP_AR_EMPTY) {
        entry->next = SP_AR_LAST;
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
        return sp_ar_insert(table, key, value);
    }

    main_pos = calc_pos(table, entry->key);
    if (main_pos == pos) {
        return insert_into_chain(table, key, value, pos);
    }
    else {
        if (!table->free_pos) {
            resize(table);
            return sp_ar_insert(table, key, value);
        }
        return insert_into_main(table, key, value, pos, main_pos);
    }
}

static int
insert_into_chain(register sp_ar_table* table, register sp_ar_index_t key, st_data_t value, sp_ar_index_t pos)
{
    sp_ar_entry *entry = table->entries + pos, *new_entry;
    sp_ar_index_t new_pos;

    while (entry->next != SP_AR_LAST) {
        pos = entry->next - SP_AR_OFFSET;
        entry = table->entries + pos;
        if (entry->key == key) {
            entry->value = value;
            return 1;
        }
    }

    if (!table->free_pos) {
        resize(table);
        return sp_ar_insert(table, key, value);
    }

    new_pos = find_empty(table, pos);
    new_entry = table->entries + new_pos;
    entry->next = new_pos + SP_AR_OFFSET;

    new_entry->next = SP_AR_LAST;
    new_entry->key = key;
    new_entry->value = value;
    table->num_entries++;
    return 0;
}

static int
insert_into_main(register sp_ar_table* table, sp_ar_index_t key, st_data_t value, sp_ar_index_t pos, sp_ar_index_t prev_pos)
{
    sp_ar_entry *entry = table->entries + pos;
    sp_ar_index_t new_pos = find_empty(table, pos);
    sp_ar_entry *new_entry = table->entries + new_pos;
    sp_ar_index_t npos;

    *new_entry = *entry;

    while((npos = table->entries[prev_pos].next - SP_AR_OFFSET) != pos) {
        prev_pos = npos;
    }
    table->entries[prev_pos].next = new_pos + SP_AR_OFFSET;

    entry->next = SP_AR_LAST;
    entry->key = key;
    entry->value = value;
    table->num_entries++;
    return 0;
}

static sp_ar_index_t
new_size(sp_ar_index_t num_entries)
{
    sp_ar_index_t msb = num_entries;
    msb |= msb >> 1;
    msb |= msb >> 2;
    msb |= msb >> 4;
    msb |= msb >> 8;
    msb |= msb >> 16;
    msb = ((msb >> 4) + 1) << 3;
    return (num_entries & (msb | (msb >> 1))) + (msb >> 1);
}

static void
resize(register sp_ar_table *table)
{
    sp_ar_table tmp_table;
    sp_ar_entry *entry;
    sp_ar_index_t i;

    if (table->num_entries == 0) {
        sp_ar_entry_dealloc(table->entries);
        memset(table, 0, sizeof(sp_ar_table));
        return;
    }

    sp_ar_init_table(&tmp_table, new_size(table->num_entries + (table->num_entries >> 2)));
    entry = table->entries;

    for(i = 0; i < table->num_bins; i++, entry++) {
        if (entry->next != SP_AR_EMPTY) {
            sp_ar_insert(&tmp_table, entry->key, entry->value);
        }
    }
    sp_ar_entry_dealloc(table->entries);
    *table = tmp_table;
}

int
sp_ar_lookup(register sp_ar_table *table, register sp_ar_index_t key, st_data_t *value)
{
    register sp_ar_entry *entry;

    if (table->num_entries == 0) return 0;

    entry = table->entries + calc_pos(table, key);
    if (entry->next == SP_AR_EMPTY) return 0;

    if (entry->key == key) goto found;
    if (entry->next == SP_AR_LAST) return 0;

    entry = table->entries + (entry->next - SP_AR_OFFSET);
    if (entry->key == key) goto found;

    while(entry->next != SP_AR_LAST) {
        entry = table->entries + (entry->next - SP_AR_OFFSET);
        if (entry->key == key) goto found;
    }
    return 0;
found:
    if (value) *value = entry->value;
    return 1;
}

void
sp_ar_clear(sp_ar_table *table)
{
    sp_ar_entry_dealloc(table->entries);
    memset(table, 0, sizeof(sp_ar_table));
}

void
sp_ar_clear_no_free(sp_ar_table *table)
{
    memset(table->entries, 0, sizeof(sp_ar_entry) * table->num_bins);
    table->num_entries = 0;
    table->free_pos = table->num_bins;
}

void
sp_ar_free_table(sp_ar_table *table)
{
    sp_ar_entry_dealloc(table->entries);
    sp_ar_table_dealloc(table);
}

int
sp_ar_delete(sp_ar_table *table, sp_ar_index_t key, st_data_t *value)
{
    sp_ar_index_t pos, prev_pos = ~0;
    sp_ar_entry *entry;

    if (table->num_entries == 0) goto not_found;

    pos = calc_pos(table, key);
    entry = table->entries + pos;

    if (entry->next == SP_AR_EMPTY) goto not_found;

    do {
        if (entry->key == key) {
            if (value) *value = entry->value;
            if (entry->next != SP_AR_LAST) {
                sp_ar_index_t npos = entry->next - SP_AR_OFFSET;
                *entry = table->entries[npos];
                memset(table->entries + npos, 0, sizeof(sp_ar_entry));
            }
            else {
                memset(table->entries + pos, 0, sizeof(sp_ar_entry));
                if (~prev_pos) {
                    table->entries[prev_pos].next = SP_AR_LAST;
                }
            }
            table->num_entries--;
            if (table->num_entries < table->num_bins / 4) {
                resize(table);
            }
            return 1;
        }
        if (entry->next == SP_AR_LAST) break;
        prev_pos = pos;
        pos = entry->next - SP_AR_OFFSET;
        entry = table->entries + pos;
    } while(1);

not_found:
    if (value) *value = 0;
    return 0;
}

int
sp_ar_foreach(register sp_ar_table *table, int (*func)(), st_data_t arg)
{
    sp_ar_index_t i;
    if (table->num_bins == 0) {
        return 0;
    }
    for(i = 0; i < table->num_bins ; i++) {
	if (table->entries[i].next != SP_AR_EMPTY) {
	    sp_ar_index_t key = table->entries[i].key;
	    st_data_t val = table->entries[i].value;
	    if ((*func)(key, val, arg) == SP_AR_STOP) break;
	}
    }
    return 0;
}

size_t
sp_ar_memsize(const sp_ar_table *table)
{
    return sizeof(sp_ar_table) + table->num_bins * sizeof(sp_ar_entry);
}

sp_ar_table*
sp_ar_copy(sp_ar_table *table)
{
    sp_ar_table *new_table = sp_ar_table_alloc();
    *new_table = *table;
    if (table->num_bins) {
        new_table->entries = sp_ar_entry_alloc(table->num_bins);
        memcpy(new_table->entries, table->entries, table->num_bins*sizeof(sp_ar_entry));
    }
    return new_table;
}

void
sp_ar_copy_to(sp_ar_table *from, sp_ar_table *to)
{
    sp_ar_entry_dealloc(to->entries);
    *to = *from;
    if (to->num_bins) {
	to->entries = sp_ar_entry_alloc(to->num_bins);
	memcpy(to->entries, from->entries, from->num_bins*sizeof(sp_ar_entry));
    }
}
