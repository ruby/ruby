#include "internal.h"
#include "ruby/ruby.h"
#include "ruby/assert.h"
#include "ruby/atomic.h"
#include "ruby/debug.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/st.h"
#include "internal/object.h"
#include "internal/array.h"
#include "internal/class.h"

#include "ruby/thread.h"
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
    char buff[0x100];
    fprintf(stderr, "%s\n", rb_raw_obj_info(buff, sizeof(buff), obj));
}

// Forward declaration
static void lock_and_maybe_gc(void *objspace_ptr);
static void force_gc(void *objspace_ptr);

// Configure wbcheck from environment variables
static void
wbcheck_configure_from_env(void)
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
}

// Define same heap sizes as the default GC
static size_t heap_sizes[] = {
    32,
    40,
    48,
    56,
    64,
    72,
    80,
    96,
    128,
    160,
    256,
    512,
    640,
    768,
    1024,
    0
};

#define HEAP_COUNT ((int)(sizeof(heap_sizes) / sizeof(heap_sizes[0])) - 1)
#define MAX_HEAP_SIZE (heap_sizes[(HEAP_COUNT) - 1])

// Object states for verification tracking
typedef enum {
    WBCHECK_STATE_CLEAR,    // Just allocated or writebarrier_remember, needs reference capture
    WBCHECK_STATE_MARKED,   // Has valid snapshot, ready for normal operation
    WBCHECK_STATE_DIRTY     // Has seen writebarrier since last snapshot, queued for verification
} wbcheck_object_state_t;

// Tri-color marking colors
typedef enum {
    WBCHECK_COLOR_WHITE,    // Unmarked - will be swept
    WBCHECK_COLOR_GRAY,     // Marked but children not processed
    WBCHECK_COLOR_BLACK     // Marked and children processed
} wbcheck_color_t;

// GC phases
typedef enum {
    WBCHECK_PHASE_MUTATOR,   // Normal execution
    WBCHECK_PHASE_SNAPSHOT,  // Collecting references for verification
    WBCHECK_PHASE_FULL_GC    // Marking objects during full GC
} wbcheck_phase_t;

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
        char buff[0x100];
        fprintf(stderr, "-> %s\n", rb_raw_obj_info(buff, sizeof(buff), list->items[i]));
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
    wbcheck_object_list_t *mark_maybe_snapshot; // Conservative refs reported via mark_maybe; needed for liveness, not verifiable
    wbcheck_object_list_t *writebarrier_children; // References added via write barriers since last snapshot
    wbcheck_object_state_t state; // Current state in verification lifecycle
    wbcheck_color_t color;  // Tri-color marking color
} rb_wbcheck_object_info_t;

// Finalizer job types
struct wbcheck_final_job {
    struct wbcheck_final_job *next;
    enum {
        WBCHECK_FINAL_JOB_DFREE,
        WBCHECK_FINAL_JOB_FINALIZE,
    } kind;
    union {
        struct {
            void (*func)(void *);
            void *data;
        } dfree;
        struct {
            VALUE finalizer_array;
        } finalize;
    } as;
};

// wbcheck objspace structure to track all objects
typedef struct {
    st_table *object_table;  // Hash table to track all allocated objects (VALUE -> rb_wbcheck_object_info_t*)
    wbcheck_object_list_t *objects_to_capture; // Objects that need initial reference capture
    wbcheck_object_list_t *objects_to_verify; // Objects that need verification after write barriers
    wbcheck_object_list_t *current_refs; // Current list for collecting references during marking
    wbcheck_object_list_t *current_maybe_refs; // Current list for collecting mark_maybe references during marking
    wbcheck_object_list_t *mark_queue; // Queue of gray objects for tri-color marking
    wbcheck_object_list_t *weak_references; // Objects holding weak references, found during marking
    wbcheck_phase_t phase;   // Current GC phase
    bool gc_enabled;         // Whether GC is allowed to run
    bool gc_stress;          // GC stress mode (run GC on every allocation)
    size_t gc_threshold;     // Trigger GC when object count reaches this
    size_t missed_write_barrier_parents; // Number of parent objects with missed write barriers
    size_t missed_write_barrier_children; // Total number of missed write barriers detected
    size_t simulated_gc_count; // Simulated GC count incremented on each GC.start
    bool measure_total_time;   // Whether to accumulate :time in stats
    struct wbcheck_final_job *finalizer_jobs; // Linked list of finalizer jobs
    rb_nativethread_lock_t finalizer_lock;   // Protects finalizer_jobs list
    rb_postponed_job_handle_t finalizer_postponed_job; // Postponed job handle for finalizers
} rb_wbcheck_objspace_t;

// Global objspace pointer for accessing from obj_slot_size function
static rb_wbcheck_objspace_t *wbcheck_global_objspace = NULL;

// Forward declarations
static void wbcheck_foreach_object(rb_wbcheck_objspace_t *objspace, int (*callback)(VALUE obj, rb_wbcheck_object_info_t *info, void *data), void *data);
static int wbcheck_verify_all_references_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *data);
static int wbcheck_update_all_snapshots_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *data);
static void wbcheck_run_finalizers_for_object(VALUE obj, rb_wbcheck_object_info_t *info);
static void gc_run_finalizers(void *data);
static void make_final_job(rb_wbcheck_objspace_t *objspace, VALUE obj, VALUE finalizer_array);

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

    fprintf(stderr, "wbcheck: object not found in tracking table\n");
    char buff[0x100];
    fprintf(stderr, "%s\n", rb_raw_obj_info(buff, sizeof(buff), obj));

    // Force ASAN crash?
    ((volatile VALUE *)obj)[0];

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
    char buff[0x100];
    fprintf(stderr, "    %s\n", rb_raw_obj_info(buff, sizeof(buff), parent_obj));
    fprintf(stderr, "  Reference counts - snapshot: %zu, writebarrier: %zu, current: %zu, missed: %zu\n",
           snapshot_count, wb_count, current_refs->count, missed_refs->count);

    for (size_t i = 0; i < missed_refs->count; i++) {
        VALUE missed_ref = missed_refs->items[i];
        char buff[0x100];
        fprintf(stderr, "  Missing reference to: %p\n    %s\n", (void *)missed_ref, rb_raw_obj_info(buff, sizeof(buff), missed_ref));
    }

    fprintf(stderr, "\n");
    objspace->missed_write_barrier_parents++;
    objspace->missed_write_barrier_children += missed_refs->count;
}

static void
wbcheck_compare_references(void *objspace_ptr, VALUE parent_obj, wbcheck_object_list_t *current_refs, wbcheck_object_list_t *gc_mark_snapshot, wbcheck_object_list_t *writebarrier_children)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    (void)objspace;

    size_t snapshot_count = gc_mark_snapshot ? gc_mark_snapshot->count : 0;
    size_t wb_count = writebarrier_children ? writebarrier_children->count : 0;

    WBCHECK_DEBUG("wbcheck: comparing references for object %p\n", (void *)parent_obj);
    WBCHECK_DEBUG("wbcheck: current refs: %zu, snapshot refs: %zu, wb refs: %zu\n",
                 current_refs->count, snapshot_count, wb_count);

    // Collect missed references (lazily allocated)
    wbcheck_object_list_t *missed_refs = NULL;

    // Use circular comparison for better performance when lists are mostly similar
    size_t snapshot_idx = 0;

    // Check each object in current_refs to see if it's in either stored list
    for (size_t i = 0; i < current_refs->count; i++) {
        VALUE current_ref = current_refs->items[i];

        // Usually the lists are nearly identical. We take advantage of this by
        // attempting to loop over both lists in sequence. When the next element
        // of the snapshot doesn't match the next element of our current_refs,
        // we'll loop around the list to try to find it and continue from that
        // match, so any runs of identical items can be matched efficiently.
        //
        // Pathologically this is O(N**2), but is O(N * num_changes)
        bool found_in_snapshot = false;
        if (gc_mark_snapshot && snapshot_count > 0) {
            size_t start_idx = snapshot_idx;
            do {
                if (gc_mark_snapshot->items[snapshot_idx] == current_ref) {
                    found_in_snapshot = true;
                    snapshot_idx++;
                    if (snapshot_idx >= snapshot_count) snapshot_idx = 0;
                    break;
                }
                snapshot_idx++;
                if (snapshot_idx >= snapshot_count) snapshot_idx = 0;
            } while (snapshot_idx != start_idx);
        }

        if (found_in_snapshot) {
            continue;
        }

        // Built-in immortal classes can be assigned via RBASIC_SET_CLASS_RAW,
        // which bypasses the write barrier. They're pinned as VM roots and
        // can never be collected, so a missing WB to them is harmless.
        if (RB_TYPE_P(current_ref, T_CLASS) && FL_TEST_RAW(current_ref, RCLASS_IS_ROOT)) {
            continue;
        }

        // Self reference... Weird but okay I guess
        if (current_ref == parent_obj) {
            continue;
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
    info->mark_maybe_snapshot = NULL;  /* No mark_maybe snapshot initially */
    info->writebarrier_children = NULL;  /* No write barrier children initially */
    info->state = WBCHECK_STATE_CLEAR;  /* Start in clear state */
    info->color = WBCHECK_COLOR_BLACK;  /* Start as black to survive current GC */

    // Store object info in hash table (VALUE -> rb_wbcheck_object_info_t*)
    st_insert(objspace->object_table, (st_data_t)obj, (st_data_t)info);
}

static void
wbcheck_unregister_object(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    rb_wbcheck_object_info_t *info;

    if (st_delete(objspace->object_table, (st_data_t *)&obj, (st_data_t *)&info)) {
        // Free object lists if they were allocated
        wbcheck_object_list_free(info->gc_mark_snapshot);
        wbcheck_object_list_free(info->mark_maybe_snapshot);
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
    wbcheck_configure_from_env();

    rb_wbcheck_objspace_t *objspace = calloc(1, sizeof(rb_wbcheck_objspace_t));
    if (!objspace) rb_bug("wbcheck: failed to allocate objspace");

    objspace->object_table = st_init_numtable();
    if (!objspace->object_table) {
        free(objspace);
        rb_bug("wbcheck: failed to create object table");
    }

    objspace->objects_to_capture = wbcheck_object_list_init();  // Initialize empty list
    objspace->objects_to_verify = wbcheck_object_list_init();   // Initialize empty list
    objspace->current_refs = NULL;     // No current refs initially
    objspace->current_maybe_refs = NULL; // No current maybe refs initially
    objspace->mark_queue = wbcheck_object_list_init(); // Initialize mark queue
    objspace->weak_references = wbcheck_object_list_init(); // Initialize weak references array
    objspace->phase = WBCHECK_PHASE_MUTATOR; // Start in mutator phase
    objspace->gc_enabled = true;       // GC enabled by default (like default GC)
    objspace->gc_stress = false;       // GC stress disabled by default
    objspace->gc_threshold = 1000;     // Start with 1000 objects, will adjust after first GC
    objspace->missed_write_barrier_parents = 0;  // No errors found yet
    objspace->missed_write_barrier_children = 0; // No errors found yet
    objspace->simulated_gc_count = 0;   // Start with GC count of 0
    objspace->measure_total_time = true; // On by default

    return objspace;
}

void
rb_gc_impl_objspace_init(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = objspace_ptr;

    // Object table is already initialized in objspace_alloc
    // Set up global objspace pointer for obj_slot_size function
    wbcheck_global_objspace = objspace;

    // Initialize postponed job for finalizers
    rb_native_mutex_initialize(&objspace->finalizer_lock);
    objspace->finalizer_postponed_job = rb_postponed_job_preregister(0, gc_run_finalizers, objspace);
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
    //rb_hash_aset(gc_constants, ID2SYM(rb_intern("BASE_SLOT_SIZE")), SIZET2NUM(BASE_SLOT_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_SIZE")), SIZET2NUM(sizeof(struct RBasic) + sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX])));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RBASIC_SIZE")), SIZET2NUM(sizeof(struct RBasic)));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_OVERHEAD")), INT2NUM(0));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVARGC_MAX_ALLOCATE_SIZE")), LONG2FIX(MAX_HEAP_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_COUNT")), LONG2FIX(HEAP_COUNT));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("SIZE_POOL_COUNT")), LONG2FIX(HEAP_COUNT));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_OLD_AGE")), INT2FIX(3));
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
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    if (objspace) {
        objspace->simulated_gc_count++;
    }

    if (!ruby_native_thread_p()) return;

    unsigned int lev = RB_GC_VM_LOCK();
    rb_gc_vm_barrier();
    force_gc(objspace_ptr);
    RB_GC_VM_UNLOCK(lev);
}

bool
rb_gc_impl_during_gc_p(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    return objspace->phase != WBCHECK_PHASE_MUTATOR;
}

static void
wbcheck_prepare_heap_i(VALUE obj, void *data)
{
    rb_gc_prepare_heap_process_object(obj);
}

void
rb_gc_impl_prepare_heap(void *objspace_ptr)
{
    rb_gc_impl_each_object(objspace_ptr, wbcheck_prepare_heap_i, NULL);
}

void
rb_gc_impl_gc_enable(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    objspace->gc_enabled = true;
}

void
rb_gc_impl_gc_disable(void *objspace_ptr, bool finish_current_gc)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    objspace->gc_enabled = false;
}

bool
rb_gc_impl_gc_enabled_p(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    return objspace->gc_enabled;
}

void
rb_gc_impl_stress_set(void *objspace_ptr, VALUE flag)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    objspace->gc_stress = RTEST(flag);
}

VALUE
rb_gc_impl_stress_get(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    return objspace->gc_stress ? Qtrue : Qfalse;
}

VALUE
rb_gc_impl_config_get(void *objspace_ptr)
{
    return rb_hash_new();
}

void
rb_gc_impl_config_set(void *objspace_ptr, VALUE hash)
{
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

    // Set up objspace state for marking. current_maybe_refs is allocated lazily
    // by rb_gc_impl_mark_maybe, since most objects have no conservative refs.
    objspace->current_refs = new_list;
    objspace->current_maybe_refs = NULL;
    objspace->phase = WBCHECK_PHASE_SNAPSHOT;

    // Use the marking infrastructure to collect references
    rb_gc_mark_children(objspace, obj);

    // Clean up objspace state
    objspace->phase = WBCHECK_PHASE_MUTATOR;
    objspace->current_refs = NULL;

    // Update the mark_maybe snapshot in place. These references don't participate
    // in verification, but we need to keep them so full GC can mark them gray.
    wbcheck_object_list_free(info->mark_maybe_snapshot);
    info->mark_maybe_snapshot = objspace->current_maybe_refs;
    objspace->current_maybe_refs = NULL;

    if (wbcheck_debug_enabled) {
        WBCHECK_DEBUG("wbcheck: collected %zu references from %p\n", new_list->count, (void *)obj);
        char buff[0x100];
        fprintf(stderr, "%s\n", rb_raw_obj_info(buff, sizeof(buff), obj));
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
                char buff[0x100];
                fprintf(stderr, "  Parent: %s\n", rb_raw_obj_info(buff, sizeof(buff), obj));
                fprintf(stderr, "  Stale reference: %s\n", rb_raw_obj_info(buff, sizeof(buff), wb_ref));
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

// Mark object as gray (add to mark queue)
static void
wbcheck_mark_gray(rb_wbcheck_objspace_t *objspace, VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) return;

    st_data_t value;
    if (!st_lookup(objspace->object_table, (st_data_t)obj, &value)) {
        rb_bug("wbcheck: asked to mark object %p not in our object table", (void *)obj);
    }

    rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)value;
    if (info->color != WBCHECK_COLOR_WHITE) {
        return; // Already marked
    }

    info->color = WBCHECK_COLOR_GRAY;
    wbcheck_object_list_append(objspace->mark_queue, obj);

    if (RB_FL_TEST_RAW(obj, RUBY_FL_WEAK_REFERENCE)) {
        wbcheck_object_list_append(objspace->weak_references, obj);
    }

    WBCHECK_DEBUG("wbcheck: marked gray: %p\n", (void *)obj);
}

// Reset all objects to white
static int
st_foreach_reset_white(st_data_t key, st_data_t val, st_data_t arg)
{
    rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)val;
    info->color = WBCHECK_COLOR_WHITE;
    return ST_CONTINUE;
}

// Mark all finalizer arrays to keep them alive during GC
static int
st_foreach_mark_finalizers(st_data_t key, st_data_t val, st_data_t arg)
{
    rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)val;
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)arg;

    if (info->finalizers) {
        wbcheck_mark_gray(objspace, info->finalizers);
    }

    return ST_CONTINUE;
}

// Full mark phase using tri-color marking with snapshots
static void
wbcheck_mark_phase(rb_wbcheck_objspace_t *objspace)
{
    WBCHECK_DEBUG("wbcheck: starting GC mark phase\n");

    objspace->phase = WBCHECK_PHASE_FULL_GC;

    // Clear mark queue and reset all objects to white
    objspace->mark_queue->count = 0;
    st_foreach(objspace->object_table, st_foreach_reset_white, 0);

    // Mark all finalizer arrays first to keep them alive
    st_foreach(objspace->object_table, st_foreach_mark_finalizers, (st_data_t)objspace);

    // Mark finalizer arrays in pending jobs to keep them alive.
    // No lock needed: all other threads are stopped during GC.
    struct wbcheck_final_job *job = objspace->finalizer_jobs;
    while (job != NULL) {
        switch (job->kind) {
          case WBCHECK_FINAL_JOB_DFREE:
            break;
          case WBCHECK_FINAL_JOB_FINALIZE:
            wbcheck_mark_gray(objspace, job->as.finalize.finalizer_array);
            break;
          default:
            rb_bug("wbcheck_mark_phase: unknown final job type %d", job->kind);
        }
        job = job->next;
    }

    // Mark roots gray
    rb_gc_save_machine_context();
    rb_gc_mark_roots(objspace, NULL);

    // Process gray queue until empty
    while (objspace->mark_queue->count > 0) {
        // Get last object from queue (LIFO)
        VALUE obj = objspace->mark_queue->items[--objspace->mark_queue->count];

        st_data_t value;
        if (st_lookup(objspace->object_table, (st_data_t)obj, &value)) {
            rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)value;
            if (info->color == WBCHECK_COLOR_GRAY) {
                // Mark all children from snapshot gray
                if (info->gc_mark_snapshot) {
                    for (size_t i = 0; i < info->gc_mark_snapshot->count; i++) {
                        wbcheck_mark_gray(objspace, info->gc_mark_snapshot->items[i]);
                    }
                }

                // Conservatively-scanned children must also be kept alive
                if (info->mark_maybe_snapshot) {
                    for (size_t i = 0; i < info->mark_maybe_snapshot->count; i++) {
                        wbcheck_mark_gray(objspace, info->mark_maybe_snapshot->items[i]);
                    }
                }

                // Mark this object black
                info->color = WBCHECK_COLOR_BLACK;
                WBCHECK_DEBUG("wbcheck: marked black: %p\n", (void *)obj);
            }
        }
    }

    objspace->phase = WBCHECK_PHASE_MUTATOR;

    WBCHECK_DEBUG("wbcheck: tri-color mark phase complete\n");
}

// Sweep phase callback - free white objects
static int
wbcheck_sweep_callback(st_data_t key, st_data_t val, st_data_t arg, int error)
{
    VALUE obj = (VALUE)key;
    rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)val;
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)arg;

    if (info->color == WBCHECK_COLOR_WHITE) {
        WBCHECK_DEBUG("wbcheck: sweeping unmarked object %p\n", (void *)obj);

        rb_gc_event_hook(obj, RUBY_INTERNAL_EVENT_FREEOBJ);

        // Clear weak references first
        rb_gc_obj_free_vm_weak_references(obj);

        // Queue finalizers for postponed job if they exist
        if (info->finalizers) {
            make_final_job(objspace, obj, info->finalizers);
            rb_postponed_job_trigger(objspace->finalizer_postponed_job);
        }

        // Call rb_gc_obj_free which handles finalizers/zombies
        if (rb_gc_obj_free(objspace, obj)) {
            // Object was actually freed, clean up our tracking
            wbcheck_object_list_free(info->gc_mark_snapshot);
            wbcheck_object_list_free(info->mark_maybe_snapshot);
            wbcheck_object_list_free(info->writebarrier_children);
            free(info);

            // Free the actual object memory
            free((void *)obj);

            return ST_DELETE; // Remove from hash table
        } else {
            // Object became a zombie - it will be freed by postponed job
            // Remove from tracking since we can't safely access it anymore
            wbcheck_object_list_free(info->gc_mark_snapshot);
            wbcheck_object_list_free(info->mark_maybe_snapshot);
            wbcheck_object_list_free(info->writebarrier_children);
            free(info);

            // Free the actual object memory
            free((void *)obj);

            return ST_DELETE; // Remove from hash table
        }
    }

    return ST_CONTINUE; // Keep marked objects
}

static void
wbcheck_sweep_phase(rb_wbcheck_objspace_t *objspace)
{
    WBCHECK_DEBUG("wbcheck: starting sweep phase\n");

    size_t objects_before = st_table_size(objspace->object_table);

    // Sweep unmarked objects
    st_foreach_check(objspace->object_table, wbcheck_sweep_callback, (st_data_t)objspace, 0);

    size_t objects_after = st_table_size(objspace->object_table);
    size_t freed_objects = objects_before - objects_after;

    // Update GC threshold: 2x the live set after GC
    objspace->gc_threshold = objects_after * 2;

    WBCHECK_DEBUG("wbcheck: sweep phase complete - freed %zu objects (%zu -> %zu), new threshold: %zu\n",
                  freed_objects, objects_before, objects_after, objspace->gc_threshold);
}

// Process weak references after marking - call rb_gc_handle_weak_references
// on each object that was flagged with RUBY_FL_WEAK_REFERENCE and collected
// during the mark phase.
static void
wbcheck_process_weak_references(rb_wbcheck_objspace_t *objspace)
{
    WBCHECK_DEBUG("wbcheck: processing %zu weak reference objects\n", objspace->weak_references->count);

    for (size_t i = 0; i < objspace->weak_references->count; i++) {
        VALUE obj = objspace->weak_references->items[i];
        rb_gc_handle_weak_references(obj);
    }

    objspace->weak_references->count = 0;
}

// Full GC: verify all objects then mark from roots
static void
wbcheck_full_gc(rb_wbcheck_objspace_t *objspace)
{
    WBCHECK_DEBUG("wbcheck: starting full GC\n");

    rb_gc_event_hook(0, RUBY_INTERNAL_EVENT_GC_ENTER);
    rb_gc_event_hook(0, RUBY_INTERNAL_EVENT_GC_START);

    // First, update snapshots for all objects (verify wb_protected ones)
    WBCHECK_DEBUG("wbcheck: updating snapshots for all objects\n");
    wbcheck_foreach_object(objspace, wbcheck_update_all_snapshots_callback, objspace);

    // Now start tri-color marking
    wbcheck_mark_phase(objspace);

    rb_gc_event_hook(0, RUBY_INTERNAL_EVENT_GC_END_MARK);

    // Process weak references after marking, before sweeping
    wbcheck_process_weak_references(objspace);

    // Sweep unmarked objects
    wbcheck_sweep_phase(objspace);

    rb_gc_event_hook(0, RUBY_INTERNAL_EVENT_GC_END_SWEEP);
    rb_gc_event_hook(0, RUBY_INTERNAL_EVENT_GC_EXIT);

    WBCHECK_DEBUG("wbcheck: full GC complete\n");
}

static void
gc_step(void *objspace_ptr, bool force)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;

    // Not initialized yet
    if (!objspace) return;

    if (!objspace->gc_enabled && !force) return;

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

    // Run full GC if forced, if we exceed the threshold, or if gc_stress is enabled
    if (ruby_native_thread_p() &&
        (force ||
         (objspace->gc_enabled &&
          (objspace->gc_stress || st_table_size(objspace->object_table) >= objspace->gc_threshold)))) {
        wbcheck_full_gc(objspace);
    }

}

static void
maybe_gc(void *objspace_ptr)
{
    gc_step(objspace_ptr, false);
}

static void
force_gc(void *objspace_ptr)
{
    gc_step(objspace_ptr, true);
}

int ruby_thread_has_gvl_p(void);

static void *
lock_and_maybe_gc_gvl(void *objspace_ptr)
{
    unsigned int lev = RB_GC_VM_LOCK();
    rb_gc_vm_barrier();

    maybe_gc(objspace_ptr);

    RB_GC_VM_UNLOCK(lev);
    return NULL;
}

static void
lock_and_maybe_gc(void *objspace_ptr)
{
    if (!ruby_native_thread_p()) return;

    if (!ruby_thread_has_gvl_p()) {
        rb_thread_call_with_gvl(lock_and_maybe_gc_gvl, objspace_ptr);
    }
    else {
        lock_and_maybe_gc_gvl(objspace_ptr);
    }
}

VALUE
rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, bool wb_protected, size_t alloc_size)
{
    unsigned int lev = RB_GC_VM_LOCK();
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

    // Register the new object in our tracking table
    wbcheck_register_object(objspace_ptr, obj, alloc_size, wb_protected);

    // Add this object to the list of objects that need initial reference capture
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    wbcheck_object_list_append(objspace->objects_to_capture, obj);

    RB_GC_VM_UNLOCK(lev);
    return obj;
}

size_t
rb_gc_impl_obj_slot_size(VALUE obj)
{
    unsigned int lev = RB_GC_VM_LOCK();

    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    size_t result = info->alloc_size;

    RB_GC_VM_UNLOCK(lev);
    return result;
}

size_t
rb_gc_impl_heap_id_for_size(void *objspace_ptr, size_t size)
{
    for (int i = 0; i < HEAP_COUNT; i++) {
        if (size <= heap_sizes[i]) return i;
    }
    rb_bug("size too big");
}

bool
rb_gc_impl_size_allocatable_p(size_t size)
{
    // Only allow sizes up to the largest heap size
    return size <= MAX_HEAP_SIZE;
}

// Malloc
void *
rb_gc_impl_malloc(void *objspace_ptr, size_t size, bool gc_allowed)
{
    if (gc_allowed) {
        lock_and_maybe_gc(objspace_ptr);
    }
    return malloc(size);
}

void *
rb_gc_impl_calloc(void *objspace_ptr, size_t size, bool gc_allowed)
{
    if (gc_allowed) {
        lock_and_maybe_gc(objspace_ptr);
    }
    return calloc(1, size);
}

void *
rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size, bool gc_allowed)
{
    if (gc_allowed) {
        lock_and_maybe_gc(objspace_ptr);
    }
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

    if (RB_SPECIAL_CONST_P(obj)) return;

    switch (objspace->phase) {
        case WBCHECK_PHASE_SNAPSHOT:
            // Collecting references during verification
            GC_ASSERT(objspace->current_refs);
            wbcheck_object_list_append(objspace->current_refs, obj);
            break;
        case WBCHECK_PHASE_FULL_GC:
            // Marking during full GC
            wbcheck_mark_gray(objspace, obj);
            break;
        case WBCHECK_PHASE_MUTATOR:
            // Should not be called during mutator phase
            rb_bug("wbcheck: gc_mark called during mutator phase");
            break;
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

    if (!rb_gc_impl_pointer_to_heap_p(objspace_ptr, (void *)obj)) return;

    switch (objspace->phase) {
        case WBCHECK_PHASE_SNAPSHOT:
            // We don't know if this is actually a reference or just a value
            // that looks like one, so we can't expect a write barrier for it.
            // Keep it separate from the verifiable refs, but retain it so full
            // GC can mark the target gray if it does turn out to be live.
            if (!objspace->current_maybe_refs) {
                objspace->current_maybe_refs = wbcheck_object_list_init();
            }
            wbcheck_object_list_append(objspace->current_maybe_refs, obj);
            break;
        case WBCHECK_PHASE_FULL_GC:
            wbcheck_mark_gray(objspace, obj);
            break;
        case WBCHECK_PHASE_MUTATOR:
            rb_bug("wbcheck: rb_gc_impl_mark_maybe called during mutator phase");
            break;
    }
}

// Weak references
void
rb_gc_impl_declare_weak_references(void *objspace_ptr, VALUE obj)
{
    FL_SET_RAW(obj, RUBY_FL_WEAK_REFERENCE);
}

bool
rb_gc_impl_handle_weak_references_alive_p(void *objspace_ptr, VALUE obj)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;

    st_data_t value;
    if (st_lookup(objspace->object_table, (st_data_t)obj, &value)) {
        rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)value;
        return info->color != WBCHECK_COLOR_WHITE;
    }

    return false;
}

// Compaction
void
rb_gc_impl_register_pinning_obj(void *objspace_ptr, VALUE obj)
{
    /* no-op */
}

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

    unsigned int lev = RB_GC_VM_LOCK_NO_BARRIER();

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

    RB_GC_VM_UNLOCK_NO_BARRIER(lev);
}

void
rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj)
{
    WBCHECK_DEBUG("wbcheck: writebarrier_unprotect called on object %p\n", (void *)obj);

    unsigned int lev = RB_GC_VM_LOCK_NO_BARRIER();

    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);
    info->wb_protected = false;

    RB_GC_VM_UNLOCK_NO_BARRIER(lev);
}

void
rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj)
{
    WBCHECK_DEBUG("wbcheck: writebarrier_remember called on object %p\n", (void *)obj);

    unsigned int lev = RB_GC_VM_LOCK_NO_BARRIER();

    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    // Clear existing references since they may be stale
    if (info->state != WBCHECK_STATE_CLEAR) {
        RUBY_ASSERT(info->gc_mark_snapshot);
        wbcheck_object_list_free(info->gc_mark_snapshot);
        info->gc_mark_snapshot = NULL;

        wbcheck_object_list_free(info->mark_maybe_snapshot);
        info->mark_maybe_snapshot = NULL;

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
    RUBY_ASSERT(!info->mark_maybe_snapshot);
    RUBY_ASSERT(!info->writebarrier_children);

    RB_GC_VM_UNLOCK_NO_BARRIER(lev);
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

// Helper to collect all objects into a snapshot list
static int
wbcheck_snapshot_collector(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE obj = (VALUE)key;
    wbcheck_object_list_t *snapshot = (wbcheck_object_list_t *)arg;
    wbcheck_object_list_append(snapshot, obj);
    return ST_CONTINUE;
}

// Take a snapshot of all objects for safe iteration
static wbcheck_object_list_t *
wbcheck_take_object_snapshot(rb_wbcheck_objspace_t *objspace)
{
    size_t object_count = st_table_size(objspace->object_table);
    wbcheck_object_list_t *snapshot = wbcheck_object_list_init_with_capacity(object_count);
    st_foreach(objspace->object_table, wbcheck_snapshot_collector, (st_data_t)snapshot);
    return snapshot;
}


void
rb_gc_impl_each_objects(void *objspace_ptr, int (*callback)(void *, void *, size_t, void *), void *data)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    GC_ASSERT(objspace);

    wbcheck_object_list_t *snapshot = wbcheck_take_object_snapshot(objspace);

    for (size_t i = 0; i < snapshot->count; i++) {
        VALUE obj = snapshot->items[i];
        st_data_t value;
        if (st_lookup(objspace->object_table, (st_data_t)obj, &value)) {
            rb_wbcheck_object_info_t *info = (rb_wbcheck_object_info_t *)value;
            int result = callback(
                (void *)obj,
                (void *)((char *)obj + info->alloc_size),
                info->alloc_size,
                data
            );
            if (result != 0) break;
        }
    }

    wbcheck_object_list_free(snapshot);
}

void
rb_gc_impl_each_object(void *objspace_ptr, void (*func)(VALUE obj, void *data), void *data)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    GC_ASSERT(objspace);

    wbcheck_object_list_t *snapshot = wbcheck_take_object_snapshot(objspace);

    for (size_t i = 0; i < snapshot->count; i++) {
        VALUE obj = snapshot->items[i];
        st_data_t value;
        if (st_lookup(objspace->object_table, (st_data_t)obj, &value)) {
            func(obj, data);
        }
    }

    wbcheck_object_list_free(snapshot);
}

static void
finalizer_jobs_push(rb_wbcheck_objspace_t *objspace, struct wbcheck_final_job *job)
{
    rb_native_mutex_lock(&objspace->finalizer_lock);
    job->next = objspace->finalizer_jobs;
    objspace->finalizer_jobs = job;
    rb_native_mutex_unlock(&objspace->finalizer_lock);
}

static struct wbcheck_final_job *
finalizer_jobs_pop(rb_wbcheck_objspace_t *objspace)
{
    rb_native_mutex_lock(&objspace->finalizer_lock);
    struct wbcheck_final_job *job = objspace->finalizer_jobs;
    if (job) {
        objspace->finalizer_jobs = job->next;
    }
    rb_native_mutex_unlock(&objspace->finalizer_lock);
    return job;
}

// Finalizers
void
rb_gc_impl_make_zombie(void *objspace_ptr, VALUE obj, void (*dfree)(void *), void *data)
{
    if (dfree == NULL) return;

    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;

    struct wbcheck_final_job *job = malloc(sizeof(struct wbcheck_final_job));
    job->kind = WBCHECK_FINAL_JOB_DFREE;
    job->as.dfree.func = dfree;
    job->as.dfree.data = data;

    finalizer_jobs_push(objspace, job);

    if (!ruby_free_at_exit_p()) {
        rb_postponed_job_trigger(objspace->finalizer_postponed_job);
    }

    WBCHECK_DEBUG("wbcheck: made zombie for object %p with dfree function\n", (void *)obj);
}

VALUE
rb_gc_impl_define_finalizer(void *objspace_ptr, VALUE obj, VALUE block)
{
    unsigned int lev = RB_GC_VM_LOCK();

    (void)objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    GC_ASSERT(!OBJ_FROZEN(obj));

    RBASIC(obj)->flags |= FL_FINALIZE;

    VALUE table = info->finalizers;
    VALUE result = block;

    if (!table) {
        /* First finalizer for this object - store object ID as first element */
        table = rb_ary_new3(2, rb_obj_id(obj), block);
        rb_obj_hide(table);
        info->finalizers = table;
    } else {
        /* Check for duplicate finalizers (skip index 0 which is object ID) */
        long len = RARRAY_LEN(table);
        long i;

        for (i = 1; i < len; i++) {
            VALUE recv = RARRAY_AREF(table, i);
            if (rb_equal(recv, block)) {
                result = recv;  /* Duplicate found, return existing */
                goto unlock_and_return;
            }
        }

        rb_ary_push(table, block);
    }

unlock_and_return:
    RB_GC_VM_UNLOCK(lev);
    return result;
}

void
rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj)
{
    unsigned int lev = RB_GC_VM_LOCK();

    (void)objspace_ptr;
    rb_wbcheck_object_info_t *info = wbcheck_get_object_info(obj);

    GC_ASSERT(!OBJ_FROZEN(obj));

    info->finalizers = 0;
    FL_UNSET(obj, FL_FINALIZE);

    RB_GC_VM_UNLOCK(lev);
}

void
rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj)
{
    (void)objspace_ptr;

    if (!FL_TEST(obj, FL_FINALIZE)) return;

    unsigned int lev = RB_GC_VM_LOCK();

    rb_wbcheck_object_info_t *src_info = wbcheck_get_object_info(obj);
    rb_wbcheck_object_info_t *dest_info = wbcheck_get_object_info(dest);

    if (src_info->finalizers) {
        VALUE table = rb_ary_dup(src_info->finalizers);
        RARRAY_ASET(table, 0, rb_obj_id(dest));
        rb_obj_hide(table);
        dest_info->finalizers = table;
        FL_SET(dest, FL_FINALIZE);
    }

    RB_GC_VM_UNLOCK(lev);
}

static VALUE
wbcheck_get_final(long i, void *data)
{
    VALUE table = (VALUE)data;

    return RARRAY_AREF(table, i + 1);
}

static void
make_final_job(rb_wbcheck_objspace_t *objspace, VALUE obj, VALUE finalizer_array)
{
    RUBY_ASSERT(RB_FL_TEST(obj, FL_FINALIZE));
    RUBY_ASSERT(RB_BUILTIN_TYPE(finalizer_array) == T_ARRAY);

    RB_FL_UNSET(obj, FL_FINALIZE);

    struct wbcheck_final_job *job = malloc(sizeof(struct wbcheck_final_job));
    job->kind = WBCHECK_FINAL_JOB_FINALIZE;
    job->as.finalize.finalizer_array = finalizer_array;

    finalizer_jobs_push(objspace, job);
}

static void
gc_run_finalizers(void *data)
{
    rb_wbcheck_objspace_t *objspace = data;

    rb_gc_set_pending_interrupt();

    struct wbcheck_final_job *job;
    while ((job = finalizer_jobs_pop(objspace)) != NULL) {
        switch (job->kind) {
          case WBCHECK_FINAL_JOB_DFREE:
            job->as.dfree.func(job->as.dfree.data);
            break;
          case WBCHECK_FINAL_JOB_FINALIZE: {
            VALUE finalizer_array = job->as.finalize.finalizer_array;

            rb_gc_run_obj_finalizer(
                RARRAY_AREF(finalizer_array, 0),
                RARRAY_LEN(finalizer_array) - 1,
                wbcheck_get_final,
                (void *)finalizer_array
            );

            RB_GC_GUARD(finalizer_array);
            break;
          }
        }

        free(job);
    }

    rb_gc_unset_pending_interrupt();
}

static void
wbcheck_run_finalizers_for_object(VALUE obj, rb_wbcheck_object_info_t *info)
{
    if (info->finalizers) {
        VALUE table = info->finalizers;
        long count = RARRAY_LEN(table) - 1;
        rb_gc_run_obj_finalizer(RARRAY_AREF(table, 0), count, wbcheck_get_final, (void *)table);
        FL_UNSET(obj, FL_FINALIZE);
    }
    info->finalizers = 0;
}

static int
wbcheck_shutdown_call_finalizer_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *data)
{
    wbcheck_run_finalizers_for_object(obj, info);
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
wbcheck_update_all_snapshots_callback(VALUE obj, rb_wbcheck_object_info_t *info, void *data)
{
    void *objspace_ptr = data;

    // For wb_protected objects, do full verification if they have a snapshot
    if (info->wb_protected && info->state != WBCHECK_STATE_CLEAR) {
        wbcheck_verify_object_references(objspace_ptr, obj);
    } else {
        // For CLEAR objects (wb_protected or not) and non-wb_protected objects, just take a new snapshot
        wbcheck_object_list_t *current_refs = wbcheck_collect_references_from_object(obj, info);
        wbcheck_object_list_free(info->gc_mark_snapshot);
        info->gc_mark_snapshot = current_refs;
        info->state = WBCHECK_STATE_MARKED;
    }

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

    // Run any pending finalizer jobs (dfree functions)
    WBCHECK_DEBUG("wbcheck: running pending finalizer jobs\n");
    gc_run_finalizers(objspace);
    WBCHECK_DEBUG("wbcheck: finished running finalizer jobs\n");
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
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    objspace->measure_total_time = RTEST(flag);
}

bool
rb_gc_impl_get_measure_total_time(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    return objspace->measure_total_time;
}

unsigned long long
rb_gc_impl_get_total_time(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    return objspace->measure_total_time ? objspace->simulated_gc_count : 0;
}

size_t
rb_gc_impl_gc_count(void *objspace_ptr)
{
    rb_wbcheck_objspace_t *objspace = (rb_wbcheck_objspace_t *)objspace_ptr;
    if (objspace) {
        return objspace->simulated_gc_count;
    }
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

    VALUE hash = Qnil, key = Qnil;

    if (RB_TYPE_P(hash_or_sym, T_HASH)) {
        hash = hash_or_sym;
    }
    else if (SYMBOL_P(hash_or_sym)) {
        key = hash_or_sym;
    }
    else {
        rb_bug("non-hash or symbol given");
    }

#define SET(name, attr) \
    if (key == ID2SYM(rb_intern(#name))) \
        return SIZET2NUM(attr); \
    else if (hash != Qnil) \
        rb_hash_aset(hash, ID2SYM(rb_intern(#name)), SIZET2NUM(attr));

    /* Pretend each GC takes 1ms; :time is reported in milliseconds. */
    SET(count, objspace->simulated_gc_count);
    SET(time, objspace->measure_total_time ? objspace->simulated_gc_count : 0);
    SET(tracked_objects, st_table_size(objspace->object_table));
#undef SET

    if (!NIL_P(key)) {
        rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(key));
    }

    rb_hash_aset(hash, ID2SYM(rb_intern("gc_implementation")), rb_str_new_cstr("wbcheck"));

    return hash;
}

VALUE
rb_gc_impl_stat_heap(void *objspace_ptr, VALUE heap_name, VALUE hash_or_sym)
{
    if (FIXNUM_P(heap_name) && SYMBOL_P(hash_or_sym)) {
        int heap_idx = FIX2INT(heap_name);
        if (heap_idx < 0 || heap_idx >= HEAP_COUNT) {
            rb_raise(rb_eArgError, "size pool index out of range");
        }

        if (hash_or_sym == ID2SYM(rb_intern("slot_size"))) {
            return SIZET2NUM(heap_sizes[heap_idx]);
        }

        return Qundef;
    }

    if (RB_TYPE_P(hash_or_sym, T_HASH)) {
        return hash_or_sym;
    }

    return Qundef;
}

const char *
rb_gc_impl_active_gc_name(void)
{
    // Stub implementation
    return "wbcheck";
}

// Miscellaneous
#define WBCHECK_OBJECT_METADATA_ENTRY_COUNT 2
static struct rb_gc_object_metadata_entry object_metadata_entries[WBCHECK_OBJECT_METADATA_ENTRY_COUNT + 1];

struct rb_gc_object_metadata_entry *
rb_gc_impl_object_metadata(void *objspace_ptr, VALUE obj)
{
    static ID ID_object_id, ID_shareable;

    if (!ID_object_id) {
        ID_object_id = rb_intern("object_id");
        ID_shareable = rb_intern("shareable");
    }

    size_t n = 0;

#define SET_ENTRY(na, v) do { \
    GC_ASSERT(n < WBCHECK_OBJECT_METADATA_ENTRY_COUNT); \
    object_metadata_entries[n].name = ID_##na; \
    object_metadata_entries[n].val = v; \
    n++; \
} while (0)

    if (rb_obj_id_p(obj)) SET_ENTRY(object_id, rb_obj_id(obj));
    if (FL_TEST(obj, FL_SHAREABLE)) SET_ENTRY(shareable, Qtrue);
#undef SET_ENTRY

    object_metadata_entries[n].name = 0;
    object_metadata_entries[n].val = 0;

    return object_metadata_entries;
}

bool
rb_gc_impl_pointer_to_heap_p(void *objspace_ptr, const void *ptr)
{
    GC_ASSERT(wbcheck_global_objspace);

    unsigned int lev = RB_GC_VM_LOCK();

    // Check if this pointer exists in our object tracking table
    st_data_t value;
    bool result = st_lookup(wbcheck_global_objspace->object_table, (st_data_t)ptr, &value);

    RB_GC_VM_UNLOCK(lev);
    return result;
}

bool
rb_gc_impl_garbage_object_p(void *objspace_ptr, VALUE obj)
{
    unsigned int lev = RB_GC_VM_LOCK();

    // Check if this pointer exists in our object tracking table
    st_data_t value;
    bool result = st_lookup(wbcheck_global_objspace->object_table, (st_data_t)obj, &value);

    RB_GC_VM_UNLOCK(lev);
    return !result;
}

void
rb_gc_impl_set_event_hook(void *objspace_ptr, const rb_event_flag_t event)
{
    // Stub implementation
}

void
rb_gc_impl_copy_attributes(void *objspace_ptr, VALUE dest, VALUE obj)
{
    rb_wbcheck_object_info_t *src_info = wbcheck_get_object_info(obj);

    if (!src_info->wb_protected) {
        rb_gc_impl_writebarrier_unprotect(objspace_ptr, dest);
    }
    rb_gc_impl_copy_finalizer(objspace_ptr, dest, obj);
}

