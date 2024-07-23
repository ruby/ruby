#ifndef GC_GC_H
#define GC_GC_H

#include "ruby/ruby.h"

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

#endif
