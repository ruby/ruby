#include "ruby/ruby.h"
#include "ruby/assert.h"
#include "ruby/atomic.h"
#include "ruby/debug.h"
#include "ruby/internal/core/rbasic.h"
#include "internal/object.h"

#include "gc/gc.h"
#include "gc/gc_impl.h"

#include <stdbool.h>

#define BASE_SLOT_SIZE 40
#define HEAP_COUNT 5
#define MAX_HEAP_SIZE (BASE_SLOT_SIZE * 16)

// Define heap sizes using power-of-2 progression
static size_t heap_sizes[HEAP_COUNT + 1] = {
    BASE_SLOT_SIZE,      // 40
    BASE_SLOT_SIZE * 2,  // 80
    BASE_SLOT_SIZE * 4,  // 160
    BASE_SLOT_SIZE * 8,  // 320
    BASE_SLOT_SIZE * 16, // 640
    0
};

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

static VALUE
gc_verify_internal_consistency(VALUE self)
{
    return Qnil;
}

void
rb_gc_impl_init(void)
{
    VALUE gc_constants = rb_hash_new();
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("BASE_SLOT_SIZE")), SIZET2NUM(BASE_SLOT_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RBASIC_SIZE")), SIZET2NUM(sizeof(struct RBasic)));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_OVERHEAD")), INT2NUM(0));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVARGC_MAX_ALLOCATE_SIZE")), LONG2FIX(MAX_HEAP_SIZE));
    // Pretend we have 5 size pools
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("SIZE_POOL_COUNT")), LONG2FIX(HEAP_COUNT));
    OBJ_FREEZE(gc_constants);
    rb_define_const(rb_mGC, "INTERNAL_CONSTANTS", gc_constants);

    // no-ops for compatibility
    rb_define_singleton_method(rb_mGC, "verify_internal_consistency", gc_verify_internal_consistency, 0);

    rb_define_singleton_method(rb_mGC, "compact", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mGC, "auto_compact", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mGC, "auto_compact=", rb_f_notimplement, 1);
    rb_define_singleton_method(rb_mGC, "latest_compact_info", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mGC, "verify_compaction_references", rb_f_notimplement, -1);
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
    alloc_size = heap_sizes[rb_gc_impl_heap_id_for_size(objspace_ptr, alloc_size)];

    // Allocate memory for the object plus one extra VALUE for slot size
    VALUE *mem = malloc(alloc_size + sizeof(VALUE));
    if (!mem) rb_bug("FIXME: malloc failed");

    // Store the slot size in the extra VALUE before the object
    *mem++ = alloc_size;

    // Initialize the object after the slot size
    VALUE obj = (VALUE)mem;
    RBASIC(obj)->flags = flags;
    RBASIC_SET_CLASS(obj, klass);

    // Fill in provided values
    VALUE *ptr = (VALUE *)((char *)obj + sizeof(struct RBasic));
    ptr[0] = v1;
    ptr[1] = v2;
    ptr[2] = v3;

    return obj;
}

size_t
rb_gc_impl_obj_slot_size(VALUE obj)
{
    // Read the slot size from the extra VALUE before the object
    return ((VALUE *)obj)[-1];
}

size_t
rb_gc_impl_heap_id_for_size(void *objspace_ptr, size_t size)
{
    for (int i = 0; i < HEAP_COUNT; i++) {
        if (size == heap_sizes[i]) return i;
        if (size < heap_sizes[i]) return i;
    }
    rb_bug("size too big");
}

bool
rb_gc_impl_size_allocatable_p(size_t size)
{
    // Only allow sizes up to the largest heap size
    return size <= (BASE_SLOT_SIZE * 16);
}

// Malloc
void *
rb_gc_impl_malloc(void *objspace_ptr, size_t size)
{
    return malloc(size);
}

void *
rb_gc_impl_calloc(void *objspace_ptr, size_t size)
{
    return calloc(1, size);
}

void *
rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size)
{
    return realloc(ptr, new_size);
}

void
rb_gc_impl_free(void *objspace_ptr, void *ptr, size_t old_size)
{
    free(ptr);
}

void
rb_gc_impl_adjust_memory_usage(void *objspace_ptr, ssize_t diff)
{
    // For wbcheck, we don't track memory usage
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
    // HACK: Manually flush stdout and stderr since wbcheck never runs finalizers.
    // Normally, I/O object finalizers would handle this flushing automatically
    // when the GC collects them, but since we never run GC, we need to manually
    // flush during shutdown to prevent output loss in subprocess scenarios.
    rb_io_flush(rb_stdout);
    rb_io_flush(rb_stderr);
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
    return "wbcheck";
}

// Miscellaneous
struct rb_gc_object_metadata_entry *
rb_gc_impl_object_metadata(void *objspace_ptr, VALUE obj)
{
    static struct rb_gc_object_metadata_entry entries[1] = {
        {0, Qnil}
    };
    return entries;
}

bool
rb_gc_impl_pointer_to_heap_p(void *objspace_ptr, const void *ptr)
{
    // Stub implementation
    return true;
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
