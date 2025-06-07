#include "ruby/ruby.h"
#include "ruby/assert.h"
#include "ruby/atomic.h"
#include "ruby/debug.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/st.h"
#include "internal/object.h"

#include "gc/gc.h"
#include "gc/gc_impl.h"

#include <stdbool.h>
#include <stdarg.h>

// Debug output control
static bool wbcheck_debug_enabled = false;

static void
wbcheck_debug(const char *format, ...)
{
    if (!wbcheck_debug_enabled) return;
    
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
}

static void
wbcheck_debug_obj_info_dump(VALUE obj)
{
    if (!wbcheck_debug_enabled) return;
    rb_obj_info_dump(obj);
}

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

// References list structure
typedef struct {
    VALUE *items;
    size_t count;
    size_t capacity;
} wbcheck_references_t;

// Helper functions for references list
static wbcheck_references_t *
wbcheck_references_init(void)
{
    wbcheck_references_t *refs = calloc(1, sizeof(wbcheck_references_t));
    if (!refs) rb_bug("wbcheck: failed to allocate references structure");
    refs->items = NULL;
    refs->count = 0;
    refs->capacity = 0;
    return refs;
}

static void
wbcheck_references_append(wbcheck_references_t *refs, VALUE obj)
{
    if (refs->count >= refs->capacity) {
        size_t new_capacity = refs->capacity == 0 ? 4 : refs->capacity * 2;
        VALUE *new_items = realloc(refs->items, new_capacity * sizeof(VALUE));
        if (!new_items) rb_bug("wbcheck: failed to reallocate references array");
        refs->items = new_items;
        refs->capacity = new_capacity;
    }
    refs->items[refs->count++] = obj;
}

static void
wbcheck_references_free(wbcheck_references_t *refs)
{
    if (!refs) return;
    if (refs->items) {
        free(refs->items);
    }
    free(refs);
}

static void
wbcheck_references_debug_print(wbcheck_references_t *refs)
{
    if (!wbcheck_debug_enabled) return;
    for (size_t i = 0; i < refs->count; i++) {
        fprintf(stderr, "-> ");
        rb_obj_info_dump(refs->items[i]);
    }
}

// Information tracked for each object
typedef struct {
    size_t alloc_size;      // Allocated size (static)
    bool wb_protected;      // Write barrier protection status (static)
    VALUE finalizers;       // Ruby Array of finalizers like [finalizer1, finalizer2, ...]
    wbcheck_references_t *references; // Pointer to list of objects this object references
} rb_wbcheck_object_info_t;

// wbcheck objspace structure to track all objects
typedef struct {
    st_table *object_table;  // Hash table to track all allocated objects (VALUE -> rb_wbcheck_object_info_t*)
    VALUE last_allocated_obj; // The most recently allocated object
    bool during_gc;          // True when we're currently marking
} rb_wbcheck_objspace_t;

// Global objspace pointer for accessing from obj_slot_size function
static rb_wbcheck_objspace_t *wbcheck_global_objspace = NULL;

// Helper functions for object tracking
static rb_wbcheck_object_info_t *
wbcheck_get_object_info(VALUE obj)
{
    // Objspace must be initialized by this point
    GC_ASSERT(wbcheck_global_objspace);
    
    st_data_t value;
    if (st_lookup(wbcheck_global_objspace->object_table, (st_data_t)obj, &value)) {
        return (rb_wbcheck_object_info_t *)value;
    }
    
    // Object not found in tracking table - this should never happen
    rb_bug("wbcheck: object not found in tracking table");
}

static void
wbcheck_register_object(void *objspace_ptr, VALUE obj, size_t alloc_size, bool wb_protected)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    GC_ASSERT(objspace);

    // Allocate and initialize object info structure
    rb_wbcheck_object_info_t *info = calloc(1, sizeof(rb_wbcheck_object_info_t));
    if (!info) rb_bug("wbcheck_register_object: failed to allocate object info");

    info->alloc_size = alloc_size;
    info->wb_protected = wb_protected;
    info->finalizers = 0;  /* No finalizers initially */
    info->references = NULL;  /* No references initially */
    
    // Store object info in hash table (VALUE -> rb_wbcheck_object_info_t*)
    st_insert(objspace->object_table, (st_data_t)obj, (st_data_t)info);
}

static void
wbcheck_unregister_object(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    rb_wbcheck_object_info_t *info;

    if (st_delete(objspace->object_table, (st_data_t *)&obj, (st_data_t *)&info)) {
        // Free the references array if it was allocated
        wbcheck_references_free(info->references);
        free(info);
    } else {
        rb_bug("wbcheck_unregister_object: object not found in table");
    }
}

// Bootup
void *
rb_gc_impl_objspace_alloc(void)
{
    rb_wbcheck_objspace_t *objspace = calloc(1, sizeof(rb_wbcheck_objspace_t));
    if (!objspace) rb_bug("wbcheck: failed to allocate objspace");
    
    objspace->object_table = st_init_numtable();
    if (!objspace->object_table) {
        free(objspace);
        rb_bug("wbcheck: failed to create object table");
    }
    
    objspace->last_allocated_obj = 0;  // No objects allocated yet
    objspace->during_gc = false;       // Not marking initially
    
    return objspace;
}

void
rb_gc_impl_objspace_init(void *objspace_ptr)
{
    // Object table is already initialized in objspace_alloc
    // Set up global objspace pointer for obj_slot_size function
    wbcheck_global_objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
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
    // This should free everything, but we'll just let it leak
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
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    return objspace->during_gc;
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
static void
wbcheck_collect_references_from_object_i(VALUE child_obj, void *data)
{
    wbcheck_references_t *refs = (wbcheck_references_t *)data;
    wbcheck_references_append(refs, child_obj);
}

static wbcheck_references_t *
wbcheck_collect_references_from_object(VALUE obj)
{
    // Create a new references array for collection
    wbcheck_references_t *new_refs = wbcheck_references_init();
    
    // Collect all references into the temporary array
    rb_objspace_reachable_objects_from(obj, wbcheck_collect_references_from_object_i, (void *)new_refs);
    
    wbcheck_debug("wbcheck: collected %zu references from %p\n", new_refs->count, (void *)obj);
    wbcheck_references_debug_print(new_refs);
    
    return new_refs;
}

static void
wbcheck_collect_initial_references(void *objspace_ptr, VALUE obj)
{
    wbcheck_debug("wbcheck: collecting initial references from object:\n");
    wbcheck_debug_obj_info_dump(obj);
    
    wbcheck_references_t *new_refs = wbcheck_collect_references_from_object(obj);
    
    // Get the object info and replace the old references with the new ones
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    RUBY_ASSERT(!info->references);
    info->references = new_refs;  // Set the new references
}

static void
maybe_gc(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    
    if (objspace->last_allocated_obj) {
       wbcheck_collect_initial_references(objspace_ptr, objspace->last_allocated_obj);
       objspace->last_allocated_obj = Qfalse;
    }
}

VALUE
rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t alloc_size)
{
    // Check if we should trigger GC before allocating
    maybe_gc(objspace_ptr);

    // Ensure minimum allocation size of BASE_SLOT_SIZE
    alloc_size = heap_sizes[rb_gc_impl_heap_id_for_size(objspace_ptr, alloc_size)];

    // Allocate memory for the object
    VALUE *mem = malloc(alloc_size);
    if (!mem) rb_bug("FIXME: malloc failed");

    // Initialize the object
    VALUE obj = (VALUE)mem;
    RBASIC(obj)->flags = flags;
    *((VALUE *)&RBASIC(obj)->klass) = klass;

    // Fill in provided values
    VALUE *ptr = (VALUE *)((char *)obj + sizeof(struct RBasic));
    ptr[0] = v1;
    ptr[1] = v2;
    ptr[2] = v3;

    // Register the new object in our tracking table
    wbcheck_register_object(objspace_ptr, obj, alloc_size, wb_protected);

    // Store this as the last allocated object
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    objspace->last_allocated_obj = obj;

    return obj;
}

size_t
rb_gc_impl_obj_slot_size(VALUE obj)
{
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    return info->alloc_size;
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
static void
gc_mark(rb_wbcheck_objspace_t *objspace, VALUE obj)
{
    wbcheck_debug("wbcheck: gc_mark called\n");
    wbcheck_debug_obj_info_dump(obj);
    
    // Mark the finalizers for this object
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    if (info->finalizers) {
        rb_gc_mark(info->finalizers);
    }
}

void
rb_gc_impl_mark(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    gc_mark(objspace, obj);
}

void
rb_gc_impl_mark_and_move(void *objspace_ptr, VALUE *ptr)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    gc_mark(objspace, *ptr);
}

void
rb_gc_impl_mark_and_pin(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    gc_mark(objspace, obj);
}

void
rb_gc_impl_mark_maybe(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    
    if (rb_gc_impl_pointer_to_heap_p(objspace_ptr, (void *)obj)) {
        GC_ASSERT(BUILTIN_TYPE(obj) != T_ZOMBIE);
        GC_ASSERT(BUILTIN_TYPE(obj) != T_NONE);
        gc_mark(objspace, obj);
    }
}

void
rb_gc_impl_mark_weak(void *objspace_ptr, VALUE *ptr)
{
    wbcheck_debug("wbcheck: rb_gc_impl_mark_weak called\n");
    wbcheck_debug_obj_info_dump(*ptr);
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
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    
    // Get the object info for the parent object (a)
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(a);
    
    // Only record the write barrier if references have been initialized
    if (info->references) {
        // Add the new reference to the parent's references list
        wbcheck_references_append(info->references, b);
        
        wbcheck_debug("wbcheck: write barrier recorded reference from %p to %p\n", (void *)a, (void *)b);
    } else {
        wbcheck_debug("wbcheck: write barrier skipped (references not initialized) from %p to %p\n", (void *)a, (void *)b);
    }
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
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    GC_ASSERT(!OBJ_FROZEN(obj));

    RBASIC(obj)->flags |= FL_FINALIZE;

    VALUE table = info->finalizers;
    
    if (!table) {
        /* First finalizer for this object */
        table = rb_ary_new3(1, block);
        rb_obj_hide(table);
        info->finalizers = table;
    } else {
        /* Check for duplicate finalizers */
        long len = RARRAY_LEN(table);
        long i;

        for (i = 0; i < len; i++) {
            VALUE recv = RARRAY_AREF(table, i);
            if (rb_equal(recv, block)) {
                return recv;  /* Duplicate found, return existing */
            }
        }

        rb_ary_push(table, block);
    }

    return block;
}

void
rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    GC_ASSERT(!OBJ_FROZEN(obj));

    info->finalizers = 0;
    FL_UNSET(obj, FL_FINALIZE);
}

void
rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    
    if (!FL_TEST(obj, FL_FINALIZE)) return;

    rb_wbcheck_object_info_t *src_info = wbcheck_get_object_info(obj);
    rb_wbcheck_object_info_t *dest_info = wbcheck_get_object_info(dest);

    if (src_info->finalizers) {
        VALUE table = rb_ary_dup(src_info->finalizers);
        dest_info->finalizers = table;
        FL_SET(dest, FL_FINALIZE);
    }
}

static VALUE
wbcheck_get_final(long i, void *data)
{
    VALUE table = (VALUE)data;
    
    return RARRAY_AREF(table, i);
}

static int
wbcheck_shutdown_call_finalizer_i(st_data_t key, st_data_t val, st_data_t _data)
{
    VALUE obj = (VALUE)key;
    rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)val;
    
    if (info->finalizers) {
        VALUE table = info->finalizers;
        long count = RARRAY_LEN(table);
        
        rb_gc_run_obj_finalizer(rb_obj_id(obj), count, wbcheck_get_final, (void *)table);
        
        FL_UNSET(obj, FL_FINALIZE);
    }
    
    return ST_CONTINUE;  /* Keep iterating through all objects */
}

void
rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    
    // Call all finalizers for all objects
    st_foreach(objspace->object_table, wbcheck_shutdown_call_finalizer_i, 0);
    
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
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    GC_ASSERT(objspace);
    
    // Create a hash with wbcheck-specific statistics
    VALUE hash = rb_hash_new();
    
    rb_hash_aset(hash, ID2SYM(rb_intern("tracked_objects")), 
                 SIZET2NUM(st_table_size(objspace->object_table)));
    
    rb_hash_aset(hash, ID2SYM(rb_intern("gc_implementation")), rb_str_new_cstr("wbcheck"));
    
    return hash;
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
    GC_ASSERT(wbcheck_global_objspace);
    
    // Check if this pointer exists in our object tracking table
    st_data_t value;
    return st_lookup(wbcheck_global_objspace->object_table, (st_data_t)ptr, &value);
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
