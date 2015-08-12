#include "ruby/ruby.h"

struct rb_id_table;

/* compatible with ST_* */
enum rb_id_table_iterator_result {
    ID_TABLE_CONTINUE = ST_CONTINUE,
    ID_TABLE_STOP     = ST_STOP,
    ID_TABLE_DELETE   = ST_DELETE,
};

struct rb_id_table *rb_id_table_create(size_t size);
void rb_id_table_free(struct rb_id_table *tbl);
void rb_id_table_clear(struct rb_id_table *tbl);

size_t rb_id_table_size(struct rb_id_table *tbl);
size_t rb_id_table_memsize(struct rb_id_table *tbl);

int rb_id_table_insert(struct rb_id_table *tbl, ID id, VALUE val);
int rb_id_table_lookup(struct rb_id_table *tbl, ID id, VALUE *valp);
int rb_id_table_delete(struct rb_id_table *tbl, ID id);
void rb_id_table_foreach(struct rb_id_table *tbl, enum rb_id_table_iterator_result (*func)(ID id, VALUE val, void *data), void *data);
void rb_id_table_foreach_values(struct rb_id_table *tbl, enum rb_id_table_iterator_result (*func)(VALUE val, void *data), void *data);
