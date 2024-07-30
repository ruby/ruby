#ifndef GC_GC_H
#define GC_GC_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Private header for the default GC and other GC implementations
 *             first introduced for [Feature #20470].
 */
#include "ruby/ruby.h"
#include "gc/gc_impl.h"

RUBY_SYMBOL_EXPORT_BEGIN
unsigned int rb_gc_vm_lock(void);
void rb_gc_vm_unlock(unsigned int lev);
unsigned int rb_gc_cr_lock(void);
void rb_gc_cr_unlock(unsigned int lev);
unsigned int rb_gc_vm_lock_no_barrier(void);
void rb_gc_vm_unlock_no_barrier(unsigned int lev);
void rb_gc_vm_barrier(void);
size_t rb_gc_obj_optimal_size(VALUE obj);
void rb_gc_mark_children(void *objspace, VALUE obj);
void rb_gc_update_object_references(void *objspace, VALUE obj);
void rb_gc_update_vm_references(void *objspace);
void rb_gc_reachable_objects_from_callback(VALUE obj);
void rb_gc_event_hook(VALUE obj, rb_event_flag_t event);
void *rb_gc_get_objspace(void);
size_t rb_size_mul_or_raise(size_t x, size_t y, VALUE exc);
void rb_gc_run_obj_finalizer(VALUE objid, long count, VALUE (*callback)(long i, void *data), void *data);
void rb_gc_set_pending_interrupt(void);
void rb_gc_unset_pending_interrupt(void);
bool rb_gc_obj_free(void *objspace, VALUE obj);
void rb_gc_mark_roots(void *objspace, const char **categoryp);
void rb_gc_ractor_newobj_cache_foreach(void (*func)(void *cache, void *data), void *data);
bool rb_gc_multi_ractor_p(void);
void rb_objspace_reachable_objects_from_root(void (func)(const char *category, VALUE, void *), void *passing_data);
void rb_objspace_reachable_objects_from(VALUE obj, void (func)(VALUE, void *), void *data);
void rb_obj_info_dump(VALUE obj);
const char *rb_obj_info(VALUE obj);
bool rb_gc_shutdown_call_finalizer_p(VALUE obj);
uint32_t rb_gc_get_shape(VALUE obj);
void rb_gc_set_shape(VALUE obj, uint32_t shape_id);
uint32_t rb_gc_rebuild_shape(VALUE obj, size_t size_pool_id);
size_t rb_obj_memsize_of(VALUE obj);
RUBY_SYMBOL_EXPORT_END

void rb_ractor_finish_marking(void);

// -------------------Private section begin------------------------
// Functions in this section are private to the default GC and gc.c

static int
hash_foreach_replace_value(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    void *objspace;

    objspace = (void *)argp;

    if (rb_gc_impl_object_moved_p(objspace, (VALUE)value)) {
        return ST_REPLACE;
    }
    return ST_CONTINUE;
}

static int
hash_replace_ref_value(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    void *objspace = (void *)argp;

    if (rb_gc_impl_object_moved_p(objspace, (VALUE)*value)) {
        *value = rb_gc_impl_location(objspace, (VALUE)*value);
    }

    return ST_CONTINUE;
}

static void
gc_ref_update_table_values_only(void *objspace, st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;

    if (st_foreach_with_replace(tbl, hash_foreach_replace_value, hash_replace_ref_value, (st_data_t)objspace)) {
        rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

static int
gc_mark_tbl_no_pin_i(st_data_t key, st_data_t value, st_data_t data)
{
    void *objspace = (void *)data;

    rb_gc_impl_mark(objspace, (VALUE)value);

    return ST_CONTINUE;
}

static int
hash_foreach_replace(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    void *objspace;

    objspace = (void *)argp;

    if (rb_gc_impl_object_moved_p(objspace, (VALUE)key)) {
        return ST_REPLACE;
    }

    if (rb_gc_impl_object_moved_p(objspace, (VALUE)value)) {
        return ST_REPLACE;
    }
    return ST_CONTINUE;
}

static int
hash_replace_ref(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    void *objspace = (void *)argp;

    if (rb_gc_impl_object_moved_p(objspace, (VALUE)*key)) {
        *key = rb_gc_impl_location(objspace, (VALUE)*key);
    }

    if (rb_gc_impl_object_moved_p(objspace, (VALUE)*value)) {
        *value = rb_gc_impl_location(objspace, (VALUE)*value);
    }

    return ST_CONTINUE;
}

static void
gc_update_table_refs(void *objspace, st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;

    if (st_foreach_with_replace(tbl, hash_foreach_replace, hash_replace_ref, (st_data_t)objspace)) {
        rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

static inline size_t
xmalloc2_size(const size_t count, const size_t elsize)
{
    return rb_size_mul_or_raise(count, elsize, rb_eArgError);
}

static VALUE
type_sym(size_t type)
{
    switch (type) {
#define COUNT_TYPE(t) case (t): return ID2SYM(rb_intern(#t)); break;
        COUNT_TYPE(T_NONE);
        COUNT_TYPE(T_OBJECT);
        COUNT_TYPE(T_CLASS);
        COUNT_TYPE(T_MODULE);
        COUNT_TYPE(T_FLOAT);
        COUNT_TYPE(T_STRING);
        COUNT_TYPE(T_REGEXP);
        COUNT_TYPE(T_ARRAY);
        COUNT_TYPE(T_HASH);
        COUNT_TYPE(T_STRUCT);
        COUNT_TYPE(T_BIGNUM);
        COUNT_TYPE(T_FILE);
        COUNT_TYPE(T_DATA);
        COUNT_TYPE(T_MATCH);
        COUNT_TYPE(T_COMPLEX);
        COUNT_TYPE(T_RATIONAL);
        COUNT_TYPE(T_NIL);
        COUNT_TYPE(T_TRUE);
        COUNT_TYPE(T_FALSE);
        COUNT_TYPE(T_SYMBOL);
        COUNT_TYPE(T_FIXNUM);
        COUNT_TYPE(T_IMEMO);
        COUNT_TYPE(T_UNDEF);
        COUNT_TYPE(T_NODE);
        COUNT_TYPE(T_ICLASS);
        COUNT_TYPE(T_ZOMBIE);
        COUNT_TYPE(T_MOVED);
#undef COUNT_TYPE
        default:              return SIZET2NUM(type); break;
    }
}
// -------------------Private section end------------------------

#endif
