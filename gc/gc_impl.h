#ifndef GC_GC_IMPL_H
#define GC_GC_IMPL_H

#include "ruby/ruby.h"

// Bootup
void *rb_gc_impl_objspace_alloc(void);
void rb_gc_impl_objspace_init(void *objspace_ptr);
void rb_gc_impl_objspace_free(void *objspace_ptr);
void *rb_gc_impl_ractor_cache_alloc(void *objspace_ptr);
void rb_gc_impl_ractor_cache_free(void *objspace_ptr, void *cache);
void rb_gc_impl_set_params(void *objspace_ptr);
void rb_gc_impl_init(void);
void rb_gc_impl_initial_stress_set(VALUE flag);
size_t *rb_gc_impl_size_pool_sizes(void *objspace_ptr);
// Shutdown
void rb_gc_impl_shutdown_free_objects(void *objspace_ptr);
// GC
void rb_gc_impl_start(void *objspace_ptr, bool full_mark, bool immediate_mark, bool immediate_sweep, bool compact);
bool rb_gc_impl_during_gc_p(void *objspace_ptr);
void rb_gc_impl_prepare_heap(void *objspace_ptr);
void rb_gc_impl_gc_enable(void *objspace_ptr);
void rb_gc_impl_gc_disable(void *objspace_ptr, bool finish_current_gc);
bool rb_gc_impl_gc_enabled_p(void *objspace_ptr);
void rb_gc_impl_stress_set(void *objspace_ptr, VALUE flag);
VALUE rb_gc_impl_stress_get(void *objspace_ptr);
// Object allocation
VALUE rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t alloc_size);
size_t rb_gc_impl_obj_slot_size(VALUE obj);
size_t rb_gc_impl_size_pool_id_for_size(void *objspace_ptr, size_t size);
bool rb_gc_impl_size_allocatable_p(size_t size);
// Malloc
void *rb_gc_impl_malloc(void *objspace_ptr, size_t size);
void *rb_gc_impl_calloc(void *objspace_ptr, size_t size);
void *rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size);
void rb_gc_impl_free(void *objspace_ptr, void *ptr, size_t old_size);
void rb_gc_impl_adjust_memory_usage(void *objspace_ptr, ssize_t diff);
// Marking
void rb_gc_impl_mark(void *objspace_ptr, VALUE obj);
void rb_gc_impl_mark_and_move(void *objspace_ptr, VALUE *ptr);
void rb_gc_impl_mark_and_pin(void *objspace_ptr, VALUE obj);
void rb_gc_impl_mark_maybe(void *objspace_ptr, VALUE obj);
void rb_gc_impl_mark_weak(void *objspace_ptr, VALUE *ptr);
void rb_gc_impl_remove_weak(void *objspace_ptr, VALUE parent_obj, VALUE *ptr);
void rb_gc_impl_objspace_mark(void *objspace_ptr);
// Compaction
bool rb_gc_impl_object_moved_p(void *objspace_ptr, VALUE obj);
VALUE rb_gc_impl_location(void *objspace_ptr, VALUE value);
// Write barriers
void rb_gc_impl_writebarrier(void *objspace_ptr, VALUE a, VALUE b);
void rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj);
void rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj);
// Heap walking
void rb_gc_impl_each_objects(void *objspace_ptr, int (*callback)(void *, void *, size_t, void *), void *data);
void rb_gc_impl_each_object(void *objspace_ptr, void (*func)(VALUE obj, void *data), void *data);
// Finalizers
void rb_gc_impl_make_zombie(void *objspace_ptr, VALUE obj, void (*dfree)(void *), void *data);
VALUE rb_gc_impl_define_finalizer(void *objspace_ptr, VALUE obj, VALUE block);
VALUE rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj);
void rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj);
void rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr);
// Object ID
VALUE rb_gc_impl_object_id(void *objspace_ptr, VALUE obj);
VALUE rb_gc_impl_object_id_to_ref(void *objspace_ptr, VALUE object_id);
// Statistics
VALUE rb_gc_impl_set_measure_total_time(void *objspace_ptr, VALUE flag);
VALUE rb_gc_impl_get_measure_total_time(void *objspace_ptr);
VALUE rb_gc_impl_get_profile_total_time(void *objspace_ptr);
size_t rb_gc_impl_gc_count(void *objspace_ptr);
VALUE rb_gc_impl_latest_gc_info(void *objspace_ptr, VALUE key);
size_t rb_gc_impl_stat(void *objspace_ptr, VALUE hash_or_sym);
size_t rb_gc_impl_stat_heap(void *objspace_ptr, VALUE heap_name, VALUE hash_or_sym);
// Miscellaneous
size_t rb_gc_impl_obj_flags(void *objspace_ptr, VALUE obj, ID* flags, size_t max);
bool rb_gc_impl_pointer_to_heap_p(void *objspace_ptr, const void *ptr);
bool rb_gc_impl_garbage_object_p(void *objspace_ptr, VALUE obj);
void rb_gc_impl_set_event_hook(void *objspace_ptr, const rb_event_flag_t event);
void rb_gc_impl_copy_attributes(void *objspace_ptr, VALUE dest, VALUE obj);

#endif
