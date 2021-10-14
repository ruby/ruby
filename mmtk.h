#ifndef MMTK_H
#define MMTK_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* MMTk_Mutator;
typedef void* MMTk_TraceLocal;

/**
 * Allocation
 */
extern MMTk_Mutator mmtk_bind_mutator(void *tls);
extern void mmtk_destroy_mutator(MMTk_Mutator mutator);

extern void* mmtk_alloc(MMTk_Mutator mutator, size_t size,
    size_t align, ssize_t offset, int allocator);

extern void* mmtk_alloc_slow(MMTk_Mutator mutator, size_t size,
    size_t align, ssize_t offset, int allocator);

extern void mmtk_post_alloc(MMTk_Mutator mutator, void* refer, void* type_refer,
    int bytes, int allocator);

extern bool mmtk_is_live_object(void* ref);
extern bool mmtk_is_mapped_object(void* ref);
extern bool mmtk_is_mapped_address(void* addr);
extern void mmtk_modify_check(void* ref);

/**
 * Tracing
 */
extern void mmtk_report_delayed_root_edge(MMTk_TraceLocal trace_local,
                                          void* addr);

extern bool mmtk_will_not_move_in_current_collection(MMTk_TraceLocal trace_local,
                                                     void* obj);

extern void mmtk_process_interior_edge(MMTk_TraceLocal trace_local, void* target,
                                      void* slot, bool root);

extern void* mmtk_trace_get_forwarded_referent(MMTk_TraceLocal trace_local, void* obj);

extern void* mmtk_trace_get_forwarded_reference(MMTk_TraceLocal trace_local, void* obj);

extern void* mmtk_trace_retain_referent(MMTk_TraceLocal trace_local, void* obj);

/**
 * Misc
 */
extern void mmtk_gc_init(size_t heap_size);
extern bool mmtk_will_never_move(void* object);
extern bool mmtk_process(char* name, char* value);
extern void mmtk_scan_region();
extern void mmtk_handle_user_collection_request(void *tls);

extern void mmtk_start_control_collector(void *tls);
extern void mmtk_start_worker(void *tls, void* worker);

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
extern void mmtk_add_weak_candidate(void* ref, void* referent);
extern void mmtk_add_soft_candidate(void* ref, void* referent);
extern void mmtk_add_phantom_candidate(void* ref, void* referent);

extern void mmtk_harness_begin(void *tls);
extern void mmtk_harness_end();

/**
 * VM introspection callbacks (defined in C)
 */
extern void rb_mmtk_referent_objects(void *object, void *closure, void *callback);
extern void rb_mmtk_roots(void (*callback)(void **root));
extern void rb_mmtk_stacks(void (*callback)(void *stack, size_t size));

#ifdef __cplusplus
}
#endif

#endif // MMTK_H
