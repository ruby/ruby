#ifndef RVALUE_OVERHEAD
#define RVALUE_OVERHEAD 0
#endif
#define BASE_SLOT_SIZE (sizeof(struct RBasic) + sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX]) + RVALUE_OVERHEAD)

#include "ruby/assert.h"
#include "ruby/atomic.h"
#include "ruby/debug.h"
#include "internal/object.h"


#include "gc/gc.h"
#include "gc/gc_impl.h"

#include <stdbool.h>

// Define a single heap size
static size_t heap_sizes[] = { BASE_SLOT_SIZE };

// Bootup
void *
rb_gc_impl_objspace_alloc(void)
{
    // Stub implementation
    return NULL;
}

void
rb_gc_impl_objspace_init(void *objspace_ptr)
{
    // Stub implementation
}

void *
rb_gc_impl_ractor_cache_alloc(void *objspace_ptr, void *ractor)
{
    // Stub implementation
    return NULL;
}

void
rb_gc_impl_set_params(void *objspace_ptr)
{
    // Stub implementation
}

void
rb_gc_impl_init(void)
{
    // Stub implementation
}

size_t *
rb_gc_impl_heap_sizes(void *objspace_ptr)
{
    return heap_sizes;
}

// Shutdown
void
rb_gc_impl_shutdown_free_objects(void *objspace_ptr)
{
    // Stub implementation
}

void
rb_gc_impl_objspace_free(void *objspace_ptr)
{
    // Stub implementation
}

void
rb_gc_impl_ractor_cache_free(void *objspace_ptr, void *cache)
{
    // Stub implementation
}

// GC
void
rb_gc_impl_start(void *objspace_ptr, bool full_mark, bool immediate_mark, bool immediate_sweep, bool compact)
{
    // Stub implementation
}

bool
rb_gc_impl_during_gc_p(void *objspace_ptr)
{
    // Stub implementation
    return false;
}

void
rb_gc_impl_prepare_heap(void *objspace_ptr)
{
    // Stub implementation
}

void
rb_gc_impl_gc_enable(void *objspace_ptr)
{
    // Stub implementation
}

void
rb_gc_impl_gc_disable(void *objspace_ptr, bool finish_current_gc)
{
    // Stub implementation
}

bool
rb_gc_impl_gc_enabled_p(void *objspace_ptr)
{
    // Stub implementation
    return false;
}

void
rb_gc_impl_stress_set(void *objspace_ptr, VALUE flag)
{
    // Stub implementation
}

VALUE
rb_gc_impl_stress_get(void *objspace_ptr)
{
    // Stub implementation
    return Qnil;
}

VALUE
rb_gc_impl_config_get(void *objspace_ptr)
{
    // Stub implementation
    return Qnil;
}

void
rb_gc_impl_config_set(void *objspace_ptr, VALUE hash)
{
    // Stub implementation
}

// Object allocation
VALUE
rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t alloc_size)
{
    // Ensure minimum allocation size of BASE_SLOT_SIZE
    size_t actual_size = alloc_size < BASE_SLOT_SIZE ? BASE_SLOT_SIZE : alloc_size;
    
    // Allocate memory for the object
    void *mem = malloc(actual_size);
    if (!mem) {
        rb_memerror();
    }

    // Initialize the object
    VALUE obj = (VALUE)mem;
    RBASIC(obj)->flags = flags;
    RBASIC_SET_CLASS(obj, klass);

    // Fill in provided values
    VALUE *ptr = (VALUE *)((char *)mem + sizeof(struct RBasic));
    ptr[0] = v1;
    ptr[1] = v2;
    ptr[2] = v3;

    return obj;
}

size_t
rb_gc_impl_obj_slot_size(VALUE obj)
{
    // For nogc, we don't track slot sizes since we use malloc directly
    return 0;
}

size_t
rb_gc_impl_heap_id_for_size(void *objspace_ptr, size_t size)
{
    // For nogc, we don't use heap IDs since we use malloc directly
    return 0;
}

bool
rb_gc_impl_size_allocatable_p(size_t size)
{
    // Allow any size that malloc can handle
    return true;
}

// Malloc
void *
rb_gc_impl_malloc(void *objspace_ptr, size_t size)
{
    void *mem = malloc(size);
    if (!mem) {
        rb_memerror();
    }
    return mem;
}

void *
rb_gc_impl_calloc(void *objspace_ptr, size_t size)
{
    void *mem = calloc(1, size);
    if (!mem) {
        rb_memerror();
    }
    return mem;
}

void *
rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size)
{
    void *mem = realloc(ptr, new_size);
    if (!mem) {
        rb_memerror();
    }
    return mem;
}

void
rb_gc_impl_free(void *objspace_ptr, void *ptr, size_t old_size)
{
    free(ptr);
}

void
rb_gc_impl_adjust_memory_usage(void *objspace_ptr, ssize_t diff)
{
    // For nogc, we don't track memory usage
}

// Marking
void
rb_gc_impl_mark(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
}

void
rb_gc_impl_mark_and_move(void *objspace_ptr, VALUE *ptr)
{
    // Stub implementation
}

void
rb_gc_impl_mark_and_pin(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
}

void
rb_gc_impl_mark_maybe(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
}

void
rb_gc_impl_mark_weak(void *objspace_ptr, VALUE *ptr)
{
    // Stub implementation
}

void
rb_gc_impl_remove_weak(void *objspace_ptr, VALUE parent_obj, VALUE *ptr)
{
    // Stub implementation
}

// Compaction
bool
rb_gc_impl_object_moved_p(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
    return false;
}

VALUE
rb_gc_impl_location(void *objspace_ptr, VALUE value)
{
    // Stub implementation
    return Qnil;
}

// Write barriers
void
rb_gc_impl_writebarrier(void *objspace_ptr, VALUE a, VALUE b)
{
    // Stub implementation
}

void
rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
}

void
rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
}

// Heap walking
void
rb_gc_impl_each_objects(void *objspace_ptr, int (*callback)(void *, void *, size_t, void *), void *data)
{
    // Stub implementation
}

void
rb_gc_impl_each_object(void *objspace_ptr, void (*func)(VALUE obj, void *data), void *data)
{
    // Stub implementation
}

// Finalizers
void
rb_gc_impl_make_zombie(void *objspace_ptr, VALUE obj, void (*dfree)(void *), void *data)
{
    // Stub implementation
}

VALUE
rb_gc_impl_define_finalizer(void *objspace_ptr, VALUE obj, VALUE block)
{
    // Stub implementation
    return Qnil;
}

void
rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
}

void
rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj)
{
    // Stub implementation
}

void
rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr)
{
    // Stub implementation
}

// Forking
void
rb_gc_impl_before_fork(void *objspace_ptr)
{
    // Stub implementation
}

void
rb_gc_impl_after_fork(void *objspace_ptr, rb_pid_t pid)
{
    // Stub implementation
}

// Statistics
void
rb_gc_impl_set_measure_total_time(void *objspace_ptr, VALUE flag)
{
    // Stub implementation
}

bool
rb_gc_impl_get_measure_total_time(void *objspace_ptr)
{
    // Stub implementation
    return false;
}

unsigned long long
rb_gc_impl_get_total_time(void *objspace_ptr)
{
    // Stub implementation
    return 0;
}

size_t
rb_gc_impl_gc_count(void *objspace_ptr)
{
    // Stub implementation
    return 0;
}

VALUE
rb_gc_impl_latest_gc_info(void *objspace_ptr, VALUE key)
{
    // Stub implementation
    return Qnil;
}

VALUE
rb_gc_impl_stat(void *objspace_ptr, VALUE hash_or_sym)
{
    // Stub implementation
    return Qnil;
}

VALUE
rb_gc_impl_stat_heap(void *objspace_ptr, VALUE heap_name, VALUE hash_or_sym)
{
    // Stub implementation
    return Qnil;
}

const char *
rb_gc_impl_active_gc_name(void)
{
    // Stub implementation
    return "nogc";
}

// Miscellaneous
struct rb_gc_object_metadata_entry *
rb_gc_impl_object_metadata(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
    return NULL;
}

bool
rb_gc_impl_pointer_to_heap_p(void *objspace_ptr, const void *ptr)
{
    // Stub implementation
    return false;
}

bool
rb_gc_impl_garbage_object_p(void *objspace_ptr, VALUE obj)
{
    // Stub implementation
    return false;
}

void
rb_gc_impl_set_event_hook(void *objspace_ptr, const rb_event_flag_t event)
{
    // Stub implementation
}

void
rb_gc_impl_copy_attributes(void *objspace_ptr, VALUE dest, VALUE obj)
{
    // Stub implementation
} 