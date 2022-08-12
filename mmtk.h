#ifndef MMTK_H
#define MMTK_H

#include <stdbool.h>
#include <stddef.h>
#include <unistd.h> // for ssize_t
#include <stdint.h> // for int32_t

#ifdef __cplusplus
extern "C" {
#endif

#define MMTK_MIN_OBJ_ALIGN 8
#define MMTK_OBJREF_OFFSET 8

typedef void* MMTk_Builder;
typedef void* MMTk_Mutator;
typedef void* MMTk_TraceLocal;

typedef void* MMTk_VMThread;
typedef void* MMTk_VMWorkerThread;
typedef void* MMTk_VMMutatorThread;

#define MMTK_GC_THREAD_KIND_CONTROLLER 0
#define MMTK_GC_THREAD_KIND_WORKER 1

typedef struct {
    void (*init_gc_worker_thread)(MMTk_VMWorkerThread worker_tls);
    MMTk_VMWorkerThread (*get_gc_thread_tls)(void);
    void (*stop_the_world)(MMTk_VMWorkerThread tls);
    void (*resume_mutators)(MMTk_VMWorkerThread tls);
    void (*blokc_for_gc)(MMTk_VMMutatorThread tls);
    size_t (*number_of_mutators)(void);
    void (*reset_mutator_iterator)(void);
    MMTk_Mutator (*get_next_mutator)(void);
    void (*scan_vm_specific_roots)(void);
    void (*scan_thread_roots)(void);
    void (*scan_thread_root)(MMTk_VMMutatorThread mutator, MMTk_VMWorkerThread worker);
    void (*scan_object_ruby_style)(void *object);
    void (*obj_free)(void *object);
} RubyUpcalls;

/**
 * MMTK builder and options
 */
MMTk_Builder mmtk_builder_default();

void mmtk_builder_set_heap_size(MMTk_Builder builder, uintptr_t heap_size);

void mmtk_builder_set_plan(MMTk_Builder builder, const char *plan_name);

void mmtk_init_binding(MMTk_Builder builder, const RubyUpcalls *upcalls);

/**
 * Initialization
 */
extern void mmtk_init_binding(MMTk_Builder builder, const RubyUpcalls *upcalls);
extern void mmtk_initialize_collection(void *tls);
extern void mmtk_enable_collection();

/**
 * GC thread entry points
 */
extern void mmtk_start_control_collector(void *tls);
extern void mmtk_start_worker(void *tls, void* worker);

/**
 * Allocation
 */
extern MMTk_Mutator mmtk_bind_mutator(MMTk_VMMutatorThread tls);
extern void mmtk_destroy_mutator(MMTk_Mutator mutator);

extern void* mmtk_alloc(MMTk_Mutator mutator, size_t size,
    size_t align, ssize_t offset, int32_t semantics);

extern void mmtk_post_alloc(MMTk_Mutator mutator, void* refer,
    size_t bytes, int32_t semantics);

/**
 * Tracing
 */
extern bool mmtk_is_live_object(void* ref);
extern bool mmtk_is_mmtk_object(void* ref);
extern bool mmtk_is_mmtk_object_prechecked(void* addr);
extern void mmtk_modify_check(void* ref);
extern void mmtk_flush_mark_buffer(MMTk_VMMutatorThread tls);

/**
 * Misc
 */
extern bool mmtk_will_never_move(void* object);
extern void mmtk_handle_user_collection_request(MMTk_VMMutatorThread tls);
extern const char* mmtk_plan_name();

/**
 * VM Accounting
 */
extern size_t mmtk_free_bytes();
extern size_t mmtk_total_bytes();
extern size_t mmtk_used_bytes();
extern void* mmtk_starting_heap_address();
extern void* mmtk_last_heap_address();

/**
 * Reference Processing
 */
extern void mmtk_add_weak_candidate(void* ref);
extern void mmtk_add_soft_candidate(void* ref);
extern void mmtk_add_phantom_candidate(void* ref);

extern void mmtk_harness_begin(void *tls);
extern void mmtk_harness_end(void *tls);

extern void mmtk_register_finalizable(void *reff);
extern void* mmtk_poll_finalizable(bool include_live);

struct ObjectClosure {
    void* (*c_function)(void* rust_closure, void* worker, void *data);
    void* rust_closure;
};

#ifdef __cplusplus
}
#endif

#endif // MMTK_H
