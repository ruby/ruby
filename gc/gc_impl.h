#ifndef GC_GC_IMPL_H
#define GC_GC_IMPL_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Header for GC implementations introduced in [Feature #20470].
 */
#include "ruby/ruby.h"

#ifndef RB_GC_OBJECT_METADATA_ENTRY_DEFINED
# define RB_GC_OBJECT_METADATA_ENTRY_DEFINED
struct rb_gc_object_metadata_entry {
    ID name;
    VALUE val;
};
#endif

#ifdef BUILDING_MODULAR_GC
# define GC_IMPL_FN
#else
// `GC_IMPL_FN` is an implementation detail of `!USE_MODULAR_GC` builds
// to have the default GC in the same translation unit as gc.c for
// the sake of optimizer visibility. It expands to nothing unless
// you're the default GC.
//
// For the default GC, do not copy-paste this when implementing
// these functions. This takes advantage of internal linkage winning
// when appearing first. See C99 6.2.2p4.
# define GC_IMPL_FN static
#endif

// Bootup
GC_IMPL_FN void *rb_gc_impl_objspace_alloc(void);
GC_IMPL_FN void rb_gc_impl_objspace_init(void *objspace_ptr);
GC_IMPL_FN void *rb_gc_impl_ractor_cache_alloc(void *objspace_ptr, void *ractor);
GC_IMPL_FN void rb_gc_impl_set_params(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_init(void);
GC_IMPL_FN size_t *rb_gc_impl_heap_sizes(void *objspace_ptr);
// Shutdown
GC_IMPL_FN void rb_gc_impl_shutdown_free_objects(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_objspace_free(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_ractor_cache_free(void *objspace_ptr, void *cache);
// GC
GC_IMPL_FN void rb_gc_impl_start(void *objspace_ptr, bool full_mark, bool immediate_mark, bool immediate_sweep, bool compact);
GC_IMPL_FN bool rb_gc_impl_during_gc_p(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_prepare_heap(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_gc_enable(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_gc_disable(void *objspace_ptr, bool finish_current_gc);
GC_IMPL_FN bool rb_gc_impl_gc_enabled_p(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_stress_set(void *objspace_ptr, VALUE flag);
GC_IMPL_FN VALUE rb_gc_impl_stress_get(void *objspace_ptr);
GC_IMPL_FN VALUE rb_gc_impl_config_get(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_config_set(void *objspace_ptr, VALUE hash);
// Object allocation
GC_IMPL_FN VALUE rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t alloc_size);
GC_IMPL_FN size_t rb_gc_impl_obj_slot_size(VALUE obj);
GC_IMPL_FN size_t rb_gc_impl_heap_id_for_size(void *objspace_ptr, size_t size);
GC_IMPL_FN bool rb_gc_impl_size_allocatable_p(size_t size);
// Malloc
/*
 * BEWARE: These functions may or may not run under GVL.
 *
 * You might want to make them thread-safe.
 * Garbage collecting inside is possible if and only if you
 * already have GVL.  Also raising exceptions without one is a
 * total disaster.
 *
 * When you absolutely cannot allocate the requested amount of
 * memory just return NULL (with appropriate errno set).
 * The caller side takes care of that situation.
 */
GC_IMPL_FN void *rb_gc_impl_malloc(void *objspace_ptr, size_t size);
GC_IMPL_FN void *rb_gc_impl_calloc(void *objspace_ptr, size_t size);
GC_IMPL_FN void *rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size);
GC_IMPL_FN void rb_gc_impl_free(void *objspace_ptr, void *ptr, size_t old_size);
GC_IMPL_FN void rb_gc_impl_adjust_memory_usage(void *objspace_ptr, ssize_t diff);
// Marking
GC_IMPL_FN void rb_gc_impl_mark(void *objspace_ptr, VALUE obj);
GC_IMPL_FN void rb_gc_impl_mark_and_move(void *objspace_ptr, VALUE *ptr);
GC_IMPL_FN void rb_gc_impl_mark_and_pin(void *objspace_ptr, VALUE obj);
GC_IMPL_FN void rb_gc_impl_mark_maybe(void *objspace_ptr, VALUE obj);
GC_IMPL_FN void rb_gc_impl_mark_weak(void *objspace_ptr, VALUE *ptr);
GC_IMPL_FN void rb_gc_impl_remove_weak(void *objspace_ptr, VALUE parent_obj, VALUE *ptr);
// Compaction
GC_IMPL_FN bool rb_gc_impl_object_moved_p(void *objspace_ptr, VALUE obj);
GC_IMPL_FN VALUE rb_gc_impl_location(void *objspace_ptr, VALUE value);
// Write barriers
GC_IMPL_FN void rb_gc_impl_writebarrier(void *objspace_ptr, VALUE a, VALUE b);
GC_IMPL_FN void rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj);
GC_IMPL_FN void rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj);
// Heap walking
GC_IMPL_FN void rb_gc_impl_each_objects(void *objspace_ptr, int (*callback)(void *, void *, size_t, void *), void *data);
GC_IMPL_FN void rb_gc_impl_each_object(void *objspace_ptr, void (*func)(VALUE obj, void *data), void *data);
// Finalizers
GC_IMPL_FN void rb_gc_impl_make_zombie(void *objspace_ptr, VALUE obj, void (*dfree)(void *), void *data);
GC_IMPL_FN VALUE rb_gc_impl_define_finalizer(void *objspace_ptr, VALUE obj, VALUE block);
GC_IMPL_FN void rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj);
GC_IMPL_FN void rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj);
GC_IMPL_FN void rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr);
// Forking
GC_IMPL_FN void rb_gc_impl_before_fork(void *objspace_ptr);
GC_IMPL_FN void rb_gc_impl_after_fork(void *objspace_ptr, rb_pid_t pid);
// Statistics
GC_IMPL_FN void rb_gc_impl_set_measure_total_time(void *objspace_ptr, VALUE flag);
GC_IMPL_FN bool rb_gc_impl_get_measure_total_time(void *objspace_ptr);
GC_IMPL_FN unsigned long long rb_gc_impl_get_total_time(void *objspace_ptr);
GC_IMPL_FN size_t rb_gc_impl_gc_count(void *objspace_ptr);
GC_IMPL_FN VALUE rb_gc_impl_latest_gc_info(void *objspace_ptr, VALUE key);
GC_IMPL_FN VALUE rb_gc_impl_stat(void *objspace_ptr, VALUE hash_or_sym);
GC_IMPL_FN VALUE rb_gc_impl_stat_heap(void *objspace_ptr, VALUE heap_name, VALUE hash_or_sym);
GC_IMPL_FN const char *rb_gc_impl_active_gc_name(void);
// Miscellaneous
GC_IMPL_FN struct rb_gc_object_metadata_entry *rb_gc_impl_object_metadata(void *objspace_ptr, VALUE obj);
GC_IMPL_FN bool rb_gc_impl_pointer_to_heap_p(void *objspace_ptr, const void *ptr);
GC_IMPL_FN bool rb_gc_impl_garbage_object_p(void *objspace_ptr, VALUE obj);
GC_IMPL_FN void rb_gc_impl_set_event_hook(void *objspace_ptr, const rb_event_flag_t event);
GC_IMPL_FN void rb_gc_impl_copy_attributes(void *objspace_ptr, VALUE dest, VALUE obj);

#undef GC_IMPL_FN

#endif
