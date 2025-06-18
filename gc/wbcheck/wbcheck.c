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

// Useless write barrier warning control
static bool wbcheck_warn_useless_wb_enabled = false;

static void
wbcheck_debug(const char *format, ...)
{
    if (!wbcheck_debug_enabled) return;

    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
}

#define WBCHECK_DEBUG(...) do { \
    if (wbcheck_debug_enabled) { \
        wbcheck_debug(__VA_ARGS__); \
    } \
} while (0)

static void
wbcheck_debug_obj_info_dump(VALUE obj)
{
    if (!wbcheck_debug_enabled) return;
    rb_obj_info_dump(obj);
}

// Forward declaration
static void lock_and_maybe_gc(void *objspace_ptr);

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

// Object states for verification tracking
typedef enum {
    WBCHECK_STATE_CLEAR,    // Just allocated or writebarrier_remember, needs reference capture
    WBCHECK_STATE_MARKED,   // Has valid snapshot, ready for normal operation
    WBCHECK_STATE_DIRTY     // Has seen writebarrier since last snapshot, queued for verification
} wbcheck_object_state_t;

// List of objects
typedef struct {
    VALUE *items;
    size_t count;
    size_t capacity;
} wbcheck_object_list_t;

// Helper functions for object list
static wbcheck_object_list_t *
wbcheck_object_list_init_with_capacity(size_t capacity)
{
    wbcheck_object_list_t *list = calloc(1, sizeof(wbcheck_object_list_t));
    if (!list) rb_bug("wbcheck: failed to allocate object list structure");

    if (capacity < 4) capacity = 4;
    list->items = malloc(capacity * sizeof(VALUE));
    if (!list->items) rb_bug("wbcheck: failed to allocate object list array");
    list->capacity = capacity;
    list->count = 0;
    return list;
}

static wbcheck_object_list_t *
wbcheck_object_list_init(void)
{
    return wbcheck_object_list_init_with_capacity(4);
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

// Information tracked for each object
typedef struct {
    size_t alloc_size;      // Allocated size (static)
    bool wb_protected;      // Write barrier protection status (static)
    VALUE finalizers;       // Ruby Array of finalizers like [finalizer1, finalizer2, ...]
    wbcheck_object_list_t *gc_mark_snapshot; // Snapshot of references from last GC mark
    wbcheck_object_list_t *writebarrier_children; // References added via write barriers since last snapshot
    wbcheck_object_state_t state; // Current state in verification lifecycle
} rb_wbcheck_object_info_t;

// Structure to track objects that need dfree called
typedef struct wbcheck_zombie {
    VALUE obj;
    void (*dfree)(void *);
    void *data;
    struct wbcheck_zombie *next;
} wbcheck_zombie_t;

// wbcheck objspace structure to track all objects
typedef struct {
    st_table *object_table;  // Hash table to track all allocated objects (VALUE -> rb_wbcheck_object_info_t*)
    wbcheck_object_list_t *objects_to_capture; // Objects that need initial reference capture
    wbcheck_object_list_t *objects_to_verify; // Objects that need verification after write barriers
    wbcheck_zombie_t *zombie_list; // Linked list of objects with dfree functions to call
    wbcheck_object_list_t *current_refs; // Current list for collecting references during marking
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
wbcheck_report_error(void *objspace_ptr, VALUE parent_obj, wbcheck_object_list_t *current_refs, wbcheck_object_list_t *gc_mark_snapshot, wbcheck_object_list_t *writebarrier_children, wbcheck_object_list_t *missed_refs)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;

    rb_wbcheck_object_info_t *parent_info = wbcheck_get_object_info(parent_obj);

    size_t snapshot_count = gc_mark_snapshot ? gc_mark_snapshot->count : 0;
    size_t wb_count = writebarrier_children ? writebarrier_children->count : 0;

    fprintf(stderr, "WBCHECK ERROR: Missed write barrier detected!\n");
    fprintf(stderr, "  Parent object: %p (wb_protected: %s)\n",
           (void *)parent_obj, parent_info->wb_protected ? "true" : "false");
    fprintf(stderr, "    "); rb_obj_info_dump(parent_obj);
    fprintf(stderr, "  Reference counts - snapshot: %zu, writebarrier: %zu, current: %zu, missed: %zu\n",
           snapshot_count, wb_count, current_refs->count, missed_refs->count);

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
wbcheck_compare_references(void *objspace_ptr, VALUE parent_obj, wbcheck_object_list_t *current_refs, wbcheck_object_list_t *gc_mark_snapshot, wbcheck_object_list_t *writebarrier_children)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;

    size_t snapshot_count = gc_mark_snapshot ? gc_mark_snapshot->count : 0;
    size_t wb_count = writebarrier_children ? writebarrier_children->count : 0;

    WBCHECK_DEBUG("wbcheck: comparing references for object %p\n", (void *)parent_obj);
    WBCHECK_DEBUG("wbcheck: current refs: %zu, snapshot refs: %zu, wb refs: %zu\n",
                 current_refs->count, snapshot_count, wb_count);

    // Collect missed references (lazily allocated)
    wbcheck_object_list_t *missed_refs = NULL;

    // Check each object in current_refs to see if it's in either stored list
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

        // Check if reference exists in gc_mark_snapshot
        if (gc_mark_snapshot) {
            // Fast path: check if the reference is at the same index
            if (i < gc_mark_snapshot->count && gc_mark_snapshot->items[i] == current_ref) {
                continue;
            }
            // Slow path: search through the entire list
            if (wbcheck_object_list_contains(gc_mark_snapshot, current_ref)) {
                continue;
            }
        }

        // Check if reference exists in writebarrier_children
        if (writebarrier_children && wbcheck_object_list_contains(writebarrier_children, current_ref)) {
            continue;
        }

        // If we get here, the reference wasn't found in either list
        // Lazily allocate missed_refs list on first miss
        if (!missed_refs) {
            missed_refs = wbcheck_object_list_init();
        }
        wbcheck_object_list_append(missed_refs, current_ref);
    }

    // Report any errors found
    if (missed_refs) {
        wbcheck_report_error(objspace_ptr, parent_obj, current_refs, gc_mark_snapshot, writebarrier_children, missed_refs);
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
    info->state = WBCHECK_STATE_CLEAR;  /* Start in clear state */

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
    objspace->zombie_list = NULL;      // No zombies initially
    objspace->current_refs = NULL;     // No current refs initially
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

    // Configure useless write barrier warnings based on environment variable
    const char *warn_useless_wb_env = getenv("WBCHECK_WARN_USELESS_WB");
    if (warn_useless_wb_env && (strcmp(warn_useless_wb_env, "1") == 0 || strcmp(warn_useless_wb_env, "true") == 0)) {
        wbcheck_warn_useless_wb_enabled = true;
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
    lock_and_maybe_gc(objspace_ptr);
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
wbcheck_collect_references_from_object(VALUE obj, rb_wbcheck_object_info_t *info)
{
    rb_wbcheck_objspace_t *objspace = wbcheck_global_objspace;

    // Use combination of writebarrier children and last snapshot as capacity hint
    size_t snapshot_count = (info->gc_mark_snapshot) ? info->gc_mark_snapshot->count : 0;
    size_t wb_children_count = (info->writebarrier_children) ? info->writebarrier_children->count : 0;
    size_t capacity_hint = snapshot_count + wb_children_count;
    wbcheck_object_list_t *new_list = wbcheck_object_list_init_with_capacity(capacity_hint);

    // Set up objspace state for marking
    objspace->current_refs = new_list;
    objspace->during_gc = true;

    // Use the marking infrastructure to collect references
    rb_gc_mark_children(objspace, obj);

    // Clean up objspace state
    objspace->during_gc = false;
    objspace->current_refs = NULL;

    if (wbcheck_debug_enabled) {
        WBCHECK_DEBUG("wbcheck: collected %zu references from %p\n", new_list->count, (void *)obj);
        rb_obj_info_dump(obj);
        wbcheck_object_list_debug_print(new_list);
    }

    return new_list;
}

static void
wbcheck_collect_initial_references(void *objspace_ptr, VALUE obj)
{
    WBCHECK_DEBUG("wbcheck: collecting initial references from %p:\n", obj);
    wbcheck_debug_obj_info_dump(obj);

    // Get the object info and set the initial GC mark snapshot
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    wbcheck_object_list_t *new_list = wbcheck_collect_references_from_object(obj, info);
    RUBY_ASSERT(!info->gc_mark_snapshot);
    RUBY_ASSERT(info->state == WBCHECK_STATE_CLEAR);
    info->gc_mark_snapshot = new_list;  // Set the initial snapshot
    info->state = WBCHECK_STATE_MARKED;  // Transition to marked state
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
    if (info->state == WBCHECK_STATE_CLEAR) {
        RUBY_ASSERT(!info->gc_mark_snapshot);
        return;
    }

    WBCHECK_DEBUG("wbcheck: verifying references for object:\n");
    wbcheck_debug_obj_info_dump(obj);

    // Get the current references from the object
    wbcheck_object_list_t *current_refs = wbcheck_collect_references_from_object(obj, info);

    // Check for useless write barriers before clearing them
    if (wbcheck_warn_useless_wb_enabled && info->writebarrier_children) {
        for (size_t i = 0; i < info->writebarrier_children->count; i++) {
            VALUE wb_ref = info->writebarrier_children->items[i];
            if (!wbcheck_object_list_contains(current_refs, wb_ref)) {
                fprintf(stderr, "WBCHECK WARNING: Potentially useless write barrier detected for object %p\n", (void *)obj);
                fprintf(stderr, "  Write barrier was recorded for reference to %p, but object no longer references it\n", (void *)wb_ref);
                fprintf(stderr, "  Parent: "); rb_obj_info_dump(obj);
                fprintf(stderr, "  Stale reference: "); rb_obj_info_dump(wb_ref);
            }
        }
    }

    // Compare current_refs against both stored lists to detect missed write barriers
    wbcheck_compare_references(objspace_ptr, obj, current_refs, info->gc_mark_snapshot, info->writebarrier_children);

    // Update the snapshot with current references and clear write barrier children
    wbcheck_object_list_free(info->gc_mark_snapshot);
    wbcheck_object_list_free(info->writebarrier_children);
    info->gc_mark_snapshot = current_refs;
    info->writebarrier_children = NULL;
    info->state = WBCHECK_STATE_MARKED;  // Back to marked state after verification
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
    WBCHECK_DEBUG("wbcheck: gc_mark called\n");
    wbcheck_debug_obj_info_dump(obj);

    // Assume we're collecting references
    GC_ASSERT(objspace->during_gc);
    GC_ASSERT(objspace->current_refs);

    if (!RB_SPECIAL_CONST_P(obj)) {
        wbcheck_object_list_append(objspace->current_refs, obj);
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
    WBCHECK_DEBUG("wbcheck: rb_gc_impl_mark_weak called\n");
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

    // Only record the write barrier if we have a valid snapshot
    if (info->state != WBCHECK_STATE_CLEAR) {
        RUBY_ASSERT(info->gc_mark_snapshot);

        // Initialize writebarrier_children list if it doesn't exist
        if (!info->writebarrier_children) {
            info->writebarrier_children = wbcheck_object_list_init();
        }

        // Add the new reference to the write barrier children list
        wbcheck_object_list_append(info->writebarrier_children, b);

        WBCHECK_DEBUG("wbcheck: write barrier recorded reference from %p to %p\n", (void *)a, (void *)b);

        // If verification after write barrier is enabled, queue the object for verification
        if (wbcheck_verify_after_wb_enabled && info->state != WBCHECK_STATE_DIRTY) {
            WBCHECK_DEBUG("wbcheck: queueing object for verification after write barrier\n");
            info->state = WBCHECK_STATE_DIRTY;  // Mark as dirty
            wbcheck_object_list_append(objspace->objects_to_verify, a);
        }
    } else {
        WBCHECK_DEBUG("wbcheck: write barrier skipped (snapshot not initialized) from %p to %p\n", (void *)a, (void *)b);
    }

    rb_gc_vm_unlock(lev);
}

void
rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj)
{
    WBCHECK_DEBUG("wbcheck: writebarrier_unprotect called on object %p\n", (void *)obj);

    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    info->wb_protected = false;

    rb_gc_vm_unlock(lev);
}

void
rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj)
{
    WBCHECK_DEBUG("wbcheck: writebarrier_remember called on object %p\n", (void *)obj);

    unsigned int lev = rb_gc_vm_lock();

    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    // Clear existing references since they may be stale
    if (info->state != WBCHECK_STATE_CLEAR) {
        RUBY_ASSERT(info->gc_mark_snapshot);
        wbcheck_object_list_free(info->gc_mark_snapshot);
        info->gc_mark_snapshot = NULL;

        // Only re-add to objects_to_capture if it had previous snapshot
        // (new objects don't need to be re-added since they'll be captured at allocation)
        wbcheck_object_list_append(objspace->objects_to_capture, obj);

        // Also clear write barrier children
        if (info->writebarrier_children) {
            wbcheck_object_list_free(info->writebarrier_children);
            info->writebarrier_children = NULL;
        }

        // Reset to clear state
        info->state = WBCHECK_STATE_CLEAR;
    }
    RUBY_ASSERT(!info->gc_mark_snapshot);
    RUBY_ASSERT(!info->writebarrier_children);

    RB_GC_VM_UNLOCK(lev);
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
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;

    // Allocate a new zombie entry
    wbcheck_zombie_t *zombie = malloc(sizeof(wbcheck_zombie_t));
    if (!zombie) rb_bug("wbcheck: failed to allocate zombie entry");

    zombie->obj = obj;
    zombie->dfree = dfree;
    zombie->data = data;

    // Add to the front of the zombie list
    zombie->next = objspace->zombie_list;
    objspace->zombie_list = zombie;

    WBCHECK_DEBUG("wbcheck: made zombie for object %p with dfree function\n", (void *)obj);
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

static int
wbcheck_shutdown_finalizer_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *data)
{
    void *objspace_ptr = data;

    if (rb_gc_shutdown_call_finalizer_p(obj)) {
        WBCHECK_DEBUG("wbcheck: finalizing object during shutdown: %p\n", (void *)obj);
        rb_gc_obj_free_vm_weak_references(obj);
        if (rb_gc_obj_free(objspace_ptr, obj)) {
            RBASIC(obj)->flags = 0;
        }
    }

    return ST_CONTINUE;
}

static void
wbcheck_finalize_zombies(rb_wbcheck_objspace_t *objspace)
{
    wbcheck_zombie_t *zombie = objspace->zombie_list;

    while (zombie) {
        wbcheck_zombie_t *next = zombie->next;

        if (zombie->dfree) {
            WBCHECK_DEBUG("wbcheck: calling dfree for zombie object %p\n", (void *)zombie->obj);
            zombie->dfree(zombie->data);
        }

        free(zombie);
        zombie = next;
    }

    objspace->zombie_list = NULL;
}

void
rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;

    // Call all finalizers for all objects using our shared iteration helper
    wbcheck_foreach_object(objspace, wbcheck_shutdown_call_finalizer_callback, NULL);

    // After all finalizers have been called, verify all object references
    unsigned int verify_lev = RB_GC_VM_LOCK();
    WBCHECK_DEBUG("wbcheck: verifying references for all objects after finalizers\n");
    wbcheck_foreach_object(objspace, wbcheck_verify_all_references_callback, objspace_ptr);
    WBCHECK_DEBUG("wbcheck: finished verifying all object references\n");
    RB_GC_VM_UNLOCK(verify_lev);

    // Print summary and exit with error code if violations were found
    if (objspace->missed_write_barrier_parents > 0 || objspace->missed_write_barrier_children > 0) {
        fprintf(stderr, "WBCHECK SUMMARY: Found %zu objects with missed write barriers (%zu total violations)\n",
                objspace->missed_write_barrier_parents, objspace->missed_write_barrier_children);


        exit(1);  // Exit with error code to indicate violations were found
    } else {
        WBCHECK_DEBUG("wbcheck: no write barrier violations detected\n");
    }

    // Call rb_gc_obj_free on objects that need shutdown finalization (File, Data with dfree, etc.)
    unsigned int lev = RB_GC_VM_LOCK();
    WBCHECK_DEBUG("wbcheck: calling rb_gc_obj_free on objects that need shutdown finalization\n");
    wbcheck_foreach_object(objspace, wbcheck_shutdown_finalizer_callback, objspace_ptr);
    WBCHECK_DEBUG("wbcheck: finished calling rb_gc_obj_free\n");

    // Call dfree functions for all zombie objects (e.g., File objects)
    WBCHECK_DEBUG("wbcheck: finalizing zombie objects\n");
    wbcheck_finalize_zombies(objspace);
    WBCHECK_DEBUG("wbcheck: finished finalizing zombie objects\n");
    RB_GC_VM_UNLOCK(lev);
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
