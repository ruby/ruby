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

// Verification after write barrier control
static bool wbcheck_verify_after_wb_enabled = false;

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

// Define same heap sizes as the default GC
static size_t heap_sizes[HEAP_COUNT + 1] = {
    BASE_SLOT_SIZE,      // 40
    BASE_SLOT_SIZE * 2,  // 80
    BASE_SLOT_SIZE * 4,  // 160
    BASE_SLOT_SIZE * 8,  // 320
    BASE_SLOT_SIZE * 16, // 640
    0
};

// List of objects
typedef struct {
    VALUE *items;
    size_t count;
    size_t capacity;
} wbcheck_object_list_t;

// Helper functions for object list
static wbcheck_object_list_t *
wbcheck_object_list_init(void)
{
    wbcheck_object_list_t *list = calloc(1, sizeof(wbcheck_object_list_t));
    if (!list) rb_bug("wbcheck: failed to allocate object list structure");
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
    return list;
}

static void
wbcheck_object_list_append(wbcheck_object_list_t *list, VALUE obj)
{
    if (list->count >= list->capacity) {
        size_t new_capacity = list->capacity == 0 ? 4 : list->capacity * 2;
        VALUE *new_items = realloc(list->items, new_capacity * sizeof(VALUE));
        if (!new_items) rb_bug("wbcheck: failed to reallocate object list array");
        list->items = new_items;
        list->capacity = new_capacity;
    }
    list->items[list->count++] = obj;
}

static void
wbcheck_object_list_free(wbcheck_object_list_t *list)
{
    if (!list) return;
    if (list->items) {
        free(list->items);
    }
    free(list);
}

static void
wbcheck_object_list_debug_print(wbcheck_object_list_t *list)
{
    if (!wbcheck_debug_enabled) return;
    for (size_t i = 0; i < list->count; i++) {
        fprintf(stderr, "-> ");
        rb_obj_info_dump(list->items[i]);
    }
}

static bool
wbcheck_object_list_contains(wbcheck_object_list_t *list, VALUE obj)
{
    for (size_t i = 0; i < list->count; i++) {
        if (list->items[i] == obj) {
            return true;
        }
    }
    return false;
}

static wbcheck_object_list_t *
wbcheck_object_list_merge(wbcheck_object_list_t *list1, wbcheck_object_list_t *list2)
{
    wbcheck_object_list_t *merged = wbcheck_object_list_init();
    
    // Add all items from list1
    if (list1) {
        for (size_t i = 0; i < list1->count; i++) {
            wbcheck_object_list_append(merged, list1->items[i]);
        }
    }
    
    // Add items from list2 that are not already in the merged list
    if (list2) {
        for (size_t i = 0; i < list2->count; i++) {
            if (!wbcheck_object_list_contains(merged, list2->items[i])) {
                wbcheck_object_list_append(merged, list2->items[i]);
            }
        }
    }
    
    return merged;
}

// Information tracked for each object
typedef struct {
    size_t alloc_size;      // Allocated size (static)
    bool wb_protected;      // Write barrier protection status (static)
    VALUE finalizers;       // Ruby Array of finalizers like [finalizer1, finalizer2, ...]
    wbcheck_object_list_t *gc_mark_snapshot; // Snapshot of references from last GC mark
    wbcheck_object_list_t *writebarrier_children; // References added via write barriers since last snapshot
} rb_wbcheck_object_info_t;

// wbcheck objspace structure to track all objects
typedef struct {
    st_table *object_table;  // Hash table to track all allocated objects (VALUE -> rb_wbcheck_object_info_t*)
    wbcheck_object_list_t *objects_to_capture; // Objects that need initial reference capture
    wbcheck_object_list_t *objects_to_verify; // Objects that need verification after write barriers
    bool during_gc;          // True when we're currently marking
    size_t missed_write_barrier_parents; // Number of parent objects with missed write barriers
    size_t missed_write_barrier_children; // Total number of missed write barriers detected
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
wbcheck_report_error(void *objspace_ptr, VALUE parent_obj, wbcheck_object_list_t *current_refs, wbcheck_object_list_t *stored_refs, wbcheck_object_list_t *missed_refs)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;

    rb_wbcheck_object_info_t *parent_info = wbcheck_get_object_info(parent_obj);

    fprintf(stderr, "WBCHECK ERROR: Missed write barrier detected!\n");
    fprintf(stderr, "  Parent object: %p (wb_protected: %s)\n",
           (void *)parent_obj, parent_info->wb_protected ? "true" : "false");
    fprintf(stderr, "    "); rb_obj_info_dump(parent_obj);
    fprintf(stderr, "  Reference counts - stored: %zu, current: %zu, missed: %zu\n",
           stored_refs->count, current_refs->count, missed_refs->count);

    for (size_t i = 0; i < missed_refs->count; i++) {
        VALUE missed_ref = missed_refs->items[i];
        fprintf(stderr, "  Missing reference to: %p\n    ", (void *)missed_ref);
        rb_obj_info_dump(missed_ref);
    }

    fprintf(stderr, "\n");
    objspace->missed_write_barrier_parents++;
    objspace->missed_write_barrier_children += missed_refs->count;
}

static void
wbcheck_compare_references(void *objspace_ptr, VALUE parent_obj, wbcheck_object_list_t *current_refs, wbcheck_object_list_t *stored_refs)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    GC_ASSERT(stored_refs != NULL);

    wbcheck_debug("wbcheck: comparing references for object %p\n", (void *)parent_obj);
    wbcheck_debug("wbcheck: current refs: %zu, stored refs: %zu\n",
                 current_refs->count, stored_refs->count);

    // Collect missed references (lazily allocated)
    wbcheck_object_list_t *missed_refs = NULL;

    // Check each object in current_refs to see if it's in stored_refs
    for (size_t i = 0; i < current_refs->count; i++) {
        VALUE current_ref = current_refs->items[i];

        // Sometimes these are set via RBASIC_SET_CLASS_RAW
        if (current_ref == rb_cArray || current_ref == rb_cString) {
            continue;
        }

        // Self reference... Weird but okay I guess
        if (current_ref == parent_obj) {
            continue;
        }

        if (!wbcheck_object_list_contains(stored_refs, current_ref)) {
            // Lazily allocate missed_refs list on first miss
            if (!missed_refs) {
                missed_refs = wbcheck_object_list_init();
            }
            wbcheck_object_list_append(missed_refs, current_ref);
        }
    }

    // Report any errors found
    if (missed_refs) {
        wbcheck_report_error(objspace_ptr, parent_obj, current_refs, stored_refs, missed_refs);
        wbcheck_object_list_free(missed_refs);
    }
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
    info->gc_mark_snapshot = NULL;  /* No snapshot initially */
    info->writebarrier_children = NULL;  /* No write barrier children initially */

    // Store object info in hash table (VALUE -> rb_wbcheck_object_info_t*)
    st_insert(objspace->object_table, (st_data_t)obj, (st_data_t)info);
}

static void
wbcheck_unregister_object(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    rb_wbcheck_object_info_t *info;

    if (st_delete(objspace->object_table, (st_data_t *)&obj, (st_data_t *)&info)) {
        // Free both object lists if they were allocated
        wbcheck_object_list_free(info->gc_mark_snapshot);
        wbcheck_object_list_free(info->writebarrier_children);
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

    objspace->objects_to_capture = wbcheck_object_list_init();  // Initialize empty list
    objspace->objects_to_verify = wbcheck_object_list_init();   // Initialize empty list
    objspace->during_gc = false;       // Not marking initially
    objspace->missed_write_barrier_parents = 0;  // No errors found yet
    objspace->missed_write_barrier_children = 0; // No errors found yet

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
    // Configure debug output based on environment variable
    const char *debug_env = getenv("WBCHECK_DEBUG");
    if (debug_env && (strcmp(debug_env, "1") == 0 || strcmp(debug_env, "true") == 0)) {
        wbcheck_debug_enabled = true;
    }

    // Configure verification after write barrier based on environment variable
    const char *verify_after_wb_env = getenv("WBCHECK_VERIFY_AFTER_WB");
    if (verify_after_wb_env && (strcmp(verify_after_wb_env, "1") == 0 || strcmp(verify_after_wb_env, "true") == 0)) {
        wbcheck_verify_after_wb_enabled = true;
    }

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
    GC_ASSERT(!RB_SPECIAL_CONST_P(child_obj));

    wbcheck_object_list_t *list = (wbcheck_object_list_t *)data;
    wbcheck_object_list_append(list, child_obj);
}

static wbcheck_object_list_t *
wbcheck_collect_references_from_object(VALUE obj)
{
    // Create a new object list for collection
    wbcheck_object_list_t *new_list = wbcheck_object_list_init();

    // Collect all references into the temporary list
    rb_objspace_reachable_objects_from(obj, wbcheck_collect_references_from_object_i, (void *)new_list);

    if (wbcheck_debug_enabled) {
        wbcheck_debug("wbcheck: collected %zu references from %p\n", new_list->count, (void *)obj);
        rb_obj_info_dump(obj);
        wbcheck_object_list_debug_print(new_list);
    }

    return new_list;
}

static void
wbcheck_collect_initial_references(void *objspace_ptr, VALUE obj)
{
    wbcheck_debug("wbcheck: collecting initial references from %p:\n", obj);
    wbcheck_debug_obj_info_dump(obj);

    wbcheck_object_list_t *new_list = wbcheck_collect_references_from_object(obj);

    // Get the object info and set the initial GC mark snapshot
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    RUBY_ASSERT(!info->gc_mark_snapshot);
    info->gc_mark_snapshot = new_list;  // Set the initial snapshot
}

static void
wbcheck_verify_object_references(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    // Ignore objects which are not write barrier protected
    if (!info->wb_protected) {
        return;
    }

    // We hadn't captured initial references
    if (!info->gc_mark_snapshot) {
        return;
    }

    wbcheck_debug("wbcheck: verifying references for object:\n");
    wbcheck_debug_obj_info_dump(obj);

    // Get the current references from the object
    wbcheck_object_list_t *current_refs = wbcheck_collect_references_from_object(obj);

    // Merge gc_mark_snapshot and writebarrier_children to get stored references
    wbcheck_object_list_t *stored_refs = wbcheck_object_list_merge(info->gc_mark_snapshot, info->writebarrier_children);

    // Compare current_refs against stored_refs to detect missed write barriers
    wbcheck_compare_references(objspace_ptr, obj, current_refs, stored_refs);

    // Free the merged stored references
    wbcheck_object_list_free(stored_refs);

    // Update the snapshot with current references and clear write barrier children
    wbcheck_object_list_free(info->gc_mark_snapshot);
    wbcheck_object_list_free(info->writebarrier_children);
    info->gc_mark_snapshot = current_refs;
    info->writebarrier_children = NULL;
}

static void
maybe_gc(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;

    // Not initialized yet
    if (!objspace) return;

    // Process all objects that need verification after write barriers (if enabled)
    if (wbcheck_verify_after_wb_enabled) {
        for (size_t i = 0; i < objspace->objects_to_verify->count; i++) {
            VALUE obj = objspace->objects_to_verify->items[i];
            wbcheck_verify_object_references(objspace_ptr, obj);
        }

        // Clear the list after processing
        objspace->objects_to_verify->count = 0;

        // If any new errors were detected during verification, exit immediately
        if (objspace->missed_write_barrier_parents > 0) {
            rb_bug("wbcheck: missed write barrier detected during immediate verification (WBCHECK_VERIFY_AFTER_WB=1)");
        }
    }

    // Process all objects that need initial reference capture
    for (size_t i = 0; i < objspace->objects_to_capture->count; i++) {
        VALUE obj = objspace->objects_to_capture->items[i];
        wbcheck_collect_initial_references(objspace_ptr, obj);
    }

    // Clear the list after processing
    objspace->objects_to_capture->count = 0;
}

static void
lock_and_maybe_gc(void *objspace_ptr)
{
    if (!ruby_native_thread_p()) return;

    unsigned int lev = rb_gc_vm_lock();
    rb_gc_vm_barrier();

    maybe_gc(objspace_ptr);

    rb_gc_vm_unlock(lev);
}

VALUE
rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t alloc_size)
{
    unsigned int lev = rb_gc_vm_lock();
    rb_gc_vm_barrier();

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

    // Add this object to the list of objects that need initial reference capture
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    wbcheck_object_list_append(objspace->objects_to_capture, obj);

    rb_gc_vm_unlock(lev);
    return obj;
}

size_t
rb_gc_impl_obj_slot_size(VALUE obj)
{
    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    size_t result = info->alloc_size;

    rb_gc_vm_unlock(lev);
    return result;
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
    lock_and_maybe_gc(objspace_ptr);
    return malloc(size);
}

void *
rb_gc_impl_calloc(void *objspace_ptr, size_t size)
{
    lock_and_maybe_gc(objspace_ptr);
    return calloc(1, size);
}

void *
rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size)
{
    lock_and_maybe_gc(objspace_ptr);
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
    if (RB_SPECIAL_CONST_P(b)) return;

    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_objspace_t *objspace = objspace_ptr;

    // Get the object info for the parent object (a)
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(a);

    // Only record the write barrier if gc_mark_snapshot has been initialized
    if (info->gc_mark_snapshot) {
        // Initialize writebarrier_children list if it doesn't exist
        if (!info->writebarrier_children) {
            info->writebarrier_children = wbcheck_object_list_init();
        }
        
        // Add the new reference to the write barrier children list
        wbcheck_object_list_append(info->writebarrier_children, b);

        wbcheck_debug("wbcheck: write barrier recorded reference from %p to %p\n", (void *)a, (void *)b);

        // If verification after write barrier is enabled, queue the object for verification
        if (wbcheck_verify_after_wb_enabled) {
            wbcheck_debug("wbcheck: queueing object for verification after write barrier\n");
            wbcheck_object_list_append(objspace->objects_to_verify, a);
        }
    } else {
        wbcheck_debug("wbcheck: write barrier skipped (snapshot not initialized) from %p to %p\n", (void *)a, (void *)b);
    }

    rb_gc_vm_unlock(lev);
}

void
rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj)
{
    wbcheck_debug("wbcheck: writebarrier_unprotect called on object %p\n", (void *)obj);

    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    info->wb_protected = false;

    rb_gc_vm_unlock(lev);
}

void
rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj)
{
    wbcheck_debug("wbcheck: writebarrier_remember called on object %p\n", (void *)obj);

    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    // Clear existing references since they may be stale
    if (info->gc_mark_snapshot) {
        wbcheck_object_list_free(info->gc_mark_snapshot);
        info->gc_mark_snapshot = NULL;

        // Only re-add to objects_to_capture if it had previous snapshot
        // (new objects don't need to be re-added since they'll be captured at allocation)
        wbcheck_object_list_append(objspace->objects_to_capture, obj);
    }
    
    // Also clear write barrier children
    if (info->writebarrier_children) {
        wbcheck_object_list_free(info->writebarrier_children);
        info->writebarrier_children = NULL;
    }

    rb_gc_vm_unlock(lev);
}

// Heap walking
struct wbcheck_foreach_data {
    int (*callback)(VALUE obj, rb_wbcheck_object_info_t *info, void *data);
    void *data;
};

static int
wbcheck_foreach_object_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE obj = (VALUE)key;
    rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)val;
    struct wbcheck_foreach_data *foreach_data = (struct wbcheck_foreach_data *)arg;

    return foreach_data->callback(obj, info, foreach_data->data);
}

static void
wbcheck_foreach_object(rb_wbcheck_objspace_t *objspace, int (*callback)(VALUE obj, rb_wbcheck_object_info_t *info, void *data), void *data)
{
    struct wbcheck_foreach_data foreach_data = {
        .callback = callback,
        .data = data
    };

    st_foreach(objspace->object_table, wbcheck_foreach_object_i, (st_data_t)&foreach_data);
}

struct each_object_callback_data {
    void (*func)(VALUE obj, void *data);
    void *data;
};

static int
each_object_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *arg)
{
    struct each_object_callback_data *callback_data = (struct each_object_callback_data *)arg;
    callback_data->func(obj, callback_data->data);
    return ST_CONTINUE;
}

struct each_objects_callback_data {
    int (*callback)(void *, void *, size_t, void *);
    void *data;
};

static int
each_objects_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *arg)
{
    struct each_objects_callback_data *callback_data = (struct each_objects_callback_data *)arg;

    // Call the callback with the object as a single-object memory region
    int result = callback_data->callback(
        (void *)obj,
        (void *)((char *)obj + info->alloc_size),
        info->alloc_size,
        callback_data->data
    );

    return (result == 0) ? ST_CONTINUE : ST_STOP;
}

void
rb_gc_impl_each_objects(void *objspace_ptr, int (*callback)(void *, void *, size_t, void *), void *data)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    GC_ASSERT(objspace);

    struct each_objects_callback_data callback_data = {
        .callback = callback,
        .data = data
    };

    wbcheck_foreach_object(objspace, each_objects_callback, &callback_data);
}

void
rb_gc_impl_each_object(void *objspace_ptr, void (*func)(VALUE obj, void *data), void *data)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    GC_ASSERT(objspace);

    struct each_object_callback_data callback_data = {
        .func = func,
        .data = data
    };

    wbcheck_foreach_object(objspace, each_object_callback, &callback_data);
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
    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    GC_ASSERT(!OBJ_FROZEN(obj));

    RBASIC(obj)->flags |= FL_FINALIZE;

    VALUE table = info->finalizers;
    VALUE result = block;

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
                result = recv;  /* Duplicate found, return existing */
                goto unlock_and_return;
            }
        }

        rb_ary_push(table, block);
    }

unlock_and_return:
    rb_gc_vm_unlock(lev);
    return result;
}

void
rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj)
{
    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_objspace_t *objspace = objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    GC_ASSERT(!OBJ_FROZEN(obj));

    info->finalizers = 0;
    FL_UNSET(obj, FL_FINALIZE);

    rb_gc_vm_unlock(lev);
}

void
rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;

    if (!FL_TEST(obj, FL_FINALIZE)) return;

    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_object_info_t *src_info = wbcheck_get_object_info(obj);
    rb_wbcheck_object_info_t *dest_info = wbcheck_get_object_info(dest);

    if (src_info->finalizers) {
        VALUE table = rb_ary_dup(src_info->finalizers);
        dest_info->finalizers = table;
        FL_SET(dest, FL_FINALIZE);
    }

    rb_gc_vm_unlock(lev);
}

static VALUE
wbcheck_get_final(long i, void *data)
{
    VALUE table = (VALUE)data;

    return RARRAY_AREF(table, i);
}

static int
wbcheck_shutdown_call_finalizer_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *data)
{
    if (info->finalizers) {
        VALUE table = info->finalizers;
        long count = RARRAY_LEN(table);

        rb_gc_run_obj_finalizer(rb_obj_id(obj), count, wbcheck_get_final, (void *)table);

        FL_UNSET(obj, FL_FINALIZE);
    }

    return ST_CONTINUE;  /* Keep iterating through all objects */
}

static int
wbcheck_verify_all_references_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *data)
{
    void *objspace_ptr = data;
    wbcheck_verify_object_references(objspace_ptr, obj);
    return ST_CONTINUE;
}

void
rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;

    // Call all finalizers for all objects using our shared iteration helper
    wbcheck_foreach_object(objspace, wbcheck_shutdown_call_finalizer_callback, NULL);

    // HACK: Manually flush stdout and stderr since wbcheck never runs finalizers.
    // Normally, I/O object finalizers would handle this flushing automatically
    // when the GC collects them, but since we never run GC, we need to manually
    // flush during shutdown to prevent output loss in subprocess scenarios.
    rb_io_flush(rb_stdout);
    rb_io_flush(rb_stderr);

    // After all finalizers have been called, verify all object references
    wbcheck_debug("wbcheck: verifying references for all objects after finalizers\n");
    wbcheck_foreach_object(objspace, wbcheck_verify_all_references_callback, objspace_ptr);
    wbcheck_debug("wbcheck: finished verifying all object references\n");

    // Print summary and exit with error code if violations were found
    if (objspace->missed_write_barrier_parents > 0 || objspace->missed_write_barrier_children > 0) {
        fprintf(stderr, "WBCHECK SUMMARY: Found %zu objects with missed write barriers (%zu total violations)\n",
                objspace->missed_write_barrier_parents, objspace->missed_write_barrier_children);


        exit(1);  // Exit with error code to indicate violations were found
    } else {
        wbcheck_debug("wbcheck: no write barrier violations detected\n");
    }
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

    unsigned int lev = rb_gc_vm_lock();

    // Check if this pointer exists in our object tracking table
    st_data_t value;
    bool result = st_lookup(wbcheck_global_objspace->object_table, (st_data_t)ptr, &value);

    rb_gc_vm_unlock(lev);
    return result;
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
