#ifndef RUBY_RACTOR_SAFE_TABLE_H
#define RUBY_RACTOR_SAFE_TABLE_H

#include "ruby/ruby.h"

typedef VALUE (*rb_ractor_safe_set_hash_func)(VALUE key);
typedef bool (*rb_ractor_safe_set_cmp_func)(VALUE a, VALUE b);
typedef VALUE (*rb_ractor_safe_set_create_func)(VALUE key, void *data);

struct rb_ractor_safe_set_funcs {
    rb_ractor_safe_set_hash_func hash;
    rb_ractor_safe_set_cmp_func cmp;
    rb_ractor_safe_set_create_func create;
};

VALUE rb_ractor_safe_set_new(struct rb_ractor_safe_set_funcs *funcs, int capacity);
VALUE rb_ractor_safe_set_find_or_insert(VALUE *set_obj_ptr, VALUE key, void *data);
VALUE rb_ractor_safe_set_delete_by_identity(VALUE set_obj, VALUE key);
void rb_ractor_safe_set_foreach_with_replace(VALUE set_obj, int (*callback)(VALUE *key, void *data), void *data);

#endif
