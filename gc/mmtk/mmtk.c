#include <pthread.h>
#include <stdbool.h>

#include "ruby/assert.h"
#include "ruby/atomic.h"
#include "ruby/debug.h"

#include "gc/gc.h"
#include "gc/gc_impl.h"
#include "gc/mmtk/mmtk.h"

#include "ccan/list/list.h"
#include "darray.h"

#ifdef __APPLE__
#include <sys/sysctl.h>
#endif

struct objspace {
    bool measure_gc_time;
    bool gc_stress;

    size_t gc_count;
    size_t total_gc_time;
    size_t total_allocated_objects;

    st_table *finalizer_table;
    struct MMTk_final_job *finalizer_jobs;
    rb_postponed_job_handle_t finalizer_postponed_job;

    struct ccan_list_head ractor_caches;
    unsigned long live_ractor_cache_count;

    pthread_mutex_t mutex;
    bool world_stopped;
    pthread_cond_t cond_world_stopped;
    pthread_cond_t cond_world_started;
    size_t start_the_world_count;

    struct rb_gc_vm_context vm_context;
};

struct MMTk_ractor_cache {
    struct ccan_list_node list_node;

    MMTk_Mutator *mutator;
    bool gc_mutator_p;
};

struct MMTk_final_job {
    struct MMTk_final_job *next;
    enum {
        MMTK_FINAL_JOB_DFREE,
        MMTK_FINAL_JOB_FINALIZE,
    } kind;
    union {
        struct {
            void (*func)(void *);
            void *data;
        } dfree;
        struct {
            VALUE object_id;
            VALUE finalizer_array;
        } finalize;
    } as;
};

#ifdef RB_THREAD_LOCAL_SPECIFIER
RB_THREAD_LOCAL_SPECIFIER struct MMTk_GCThreadTLS *rb_mmtk_gc_thread_tls;
#else
# error We currently need language-supported TLS
#endif

#include <pthread.h>

static void
rb_mmtk_init_gc_worker_thread(MMTk_VMWorkerThread gc_thread_tls)
{
    rb_mmtk_gc_thread_tls = gc_thread_tls;
}

static bool
rb_mmtk_is_mutator(void)
{
    return ruby_native_thread_p();
}

static void
rb_mmtk_stop_the_world(void)
{
    struct objspace *objspace = rb_gc_get_objspace();

    int err;
    if ((err = pthread_mutex_lock(&objspace->mutex)) != 0) {
        rb_bug("ERROR: cannot lock objspace->mutex: %s", strerror(err));
    }

    while (!objspace->world_stopped) {
        pthread_cond_wait(&objspace->cond_world_stopped, &objspace->mutex);
    }

    if ((err = pthread_mutex_unlock(&objspace->mutex)) != 0) {
        rb_bug("ERROR: cannot release objspace->mutex: %s", strerror(err));
    }
}

static void
rb_mmtk_resume_mutators(void)
{
    struct objspace *objspace = rb_gc_get_objspace();

    int err;
    if ((err = pthread_mutex_lock(&objspace->mutex)) != 0) {
        rb_bug("ERROR: cannot lock objspace->mutex: %s", strerror(err));
    }

    objspace->world_stopped = false;
    objspace->gc_count++;
    pthread_cond_broadcast(&objspace->cond_world_started);

    if ((err = pthread_mutex_unlock(&objspace->mutex)) != 0) {
        rb_bug("ERROR: cannot release objspace->mutex: %s", strerror(err));
    }
}

static void
rb_mmtk_block_for_gc(MMTk_VMMutatorThread mutator)
{
    struct objspace *objspace = rb_gc_get_objspace();

    size_t starting_gc_count = objspace->gc_count;
    int lock_lev = rb_gc_vm_lock();
    int err;
    if ((err = pthread_mutex_lock(&objspace->mutex)) != 0) {
        rb_bug("ERROR: cannot lock objspace->mutex: %s", strerror(err));
    }

    if (objspace->gc_count == starting_gc_count) {
        rb_gc_event_hook(0, RUBY_INTERNAL_EVENT_GC_START);

        rb_gc_initialize_vm_context(&objspace->vm_context);

        mutator->gc_mutator_p = true;

        struct timespec gc_start_time;
        if (objspace->measure_gc_time) {
            clock_gettime(CLOCK_MONOTONIC, &gc_start_time);
        }

        rb_gc_save_machine_context();

        rb_gc_vm_barrier();

        objspace->world_stopped = true;

        pthread_cond_broadcast(&objspace->cond_world_stopped);

        // Wait for GC end
        while (objspace->world_stopped) {
            pthread_cond_wait(&objspace->cond_world_started, &objspace->mutex);
        }

        if (objspace->measure_gc_time) {
            struct timespec gc_end_time;
            clock_gettime(CLOCK_MONOTONIC, &gc_end_time);

            objspace->total_gc_time +=
                (gc_end_time.tv_sec - gc_start_time.tv_sec) * (1000 * 1000 * 1000) +
                    (gc_end_time.tv_nsec - gc_start_time.tv_nsec);
        }
    }

    if ((err = pthread_mutex_unlock(&objspace->mutex)) != 0) {
        rb_bug("ERROR: cannot release objspace->mutex: %s", strerror(err));
    }
    rb_gc_vm_unlock(lock_lev);
}

static size_t
rb_mmtk_number_of_mutators(void)
{
    struct objspace *objspace = rb_gc_get_objspace();
    return objspace->live_ractor_cache_count;
}

static void
rb_mmtk_get_mutators(void (*visit_mutator)(MMTk_Mutator *mutator, void *data), void *data)
{
    struct objspace *objspace = rb_gc_get_objspace();
    struct MMTk_ractor_cache *ractor_cache;

    ccan_list_for_each(&objspace->ractor_caches, ractor_cache, list_node) {
        visit_mutator(ractor_cache->mutator, data);
    }
}

static void
rb_mmtk_scan_gc_roots(void)
{
    struct objspace *objspace = rb_gc_get_objspace();

    // FIXME: Make `rb_gc_mark_roots` aware that the current thread may not have EC.
    // See: https://github.com/ruby/mmtk/issues/22
    rb_gc_worker_thread_set_vm_context(&objspace->vm_context);
    rb_gc_mark_roots(objspace, NULL);
    rb_gc_worker_thread_unset_vm_context(&objspace->vm_context);
}

static int
pin_value(st_data_t key, st_data_t value, st_data_t data)
{
    rb_gc_impl_mark_and_pin((void *)data, (VALUE)value);

    return ST_CONTINUE;
}

static void
rb_mmtk_scan_objspace(void)
{
    struct objspace *objspace = rb_gc_get_objspace();

    if (objspace->finalizer_table != NULL) {
        st_foreach(objspace->finalizer_table, pin_value, (st_data_t)objspace);
    }

    struct MMTk_final_job *job = objspace->finalizer_jobs;
    while (job != NULL) {
        switch (job->kind) {
          case MMTK_FINAL_JOB_DFREE:
            break;
          case MMTK_FINAL_JOB_FINALIZE:
            rb_gc_impl_mark(objspace, job->as.finalize.object_id);
            rb_gc_impl_mark(objspace, job->as.finalize.finalizer_array);
            break;
          default:
            rb_bug("rb_mmtk_scan_objspace: unknown final job type %d", job->kind);
        }

        job = job->next;
    }
}

static void
rb_mmtk_scan_object_ruby_style(MMTk_ObjectReference object)
{
    rb_gc_mark_children(rb_gc_get_objspace(), (VALUE)object);
}

static void
rb_mmtk_call_gc_mark_children(MMTk_ObjectReference object)
{
    rb_gc_mark_children(rb_gc_get_objspace(), (VALUE)object);
}

static void
rb_mmtk_call_obj_free(MMTk_ObjectReference object)
{
    VALUE obj = (VALUE)object;
    struct objspace *objspace = rb_gc_get_objspace();

    if (RB_UNLIKELY(rb_gc_event_hook_required_p(RUBY_INTERNAL_EVENT_FREEOBJ))) {
        rb_gc_worker_thread_set_vm_context(&objspace->vm_context);
        rb_gc_event_hook(obj, RUBY_INTERNAL_EVENT_FREEOBJ);
        rb_gc_worker_thread_unset_vm_context(&objspace->vm_context);
    }

    rb_gc_obj_free(objspace, obj);
}

static size_t
rb_mmtk_vm_live_bytes(void)
{
    return 0;
}

static void
make_final_job(struct objspace *objspace, VALUE obj, VALUE table)
{
    RUBY_ASSERT(RB_FL_TEST(obj, RUBY_FL_FINALIZE));
    RUBY_ASSERT(mmtk_is_reachable((MMTk_ObjectReference)table));
    RUBY_ASSERT(RB_BUILTIN_TYPE(table) == T_ARRAY);

    RB_FL_UNSET(obj, RUBY_FL_FINALIZE);

    struct MMTk_final_job *job = xmalloc(sizeof(struct MMTk_final_job));
    job->next = objspace->finalizer_jobs;
    job->kind = MMTK_FINAL_JOB_FINALIZE;
    job->as.finalize.object_id = rb_obj_id((VALUE)obj);
    job->as.finalize.finalizer_array = table;

    objspace->finalizer_jobs = job;
}

static int
rb_mmtk_update_finalizer_table_i(st_data_t key, st_data_t value, st_data_t data)
{
    RUBY_ASSERT(RB_FL_TEST(key, RUBY_FL_FINALIZE));
    RUBY_ASSERT(mmtk_is_reachable((MMTk_ObjectReference)value));
    RUBY_ASSERT(RB_BUILTIN_TYPE(value) == T_ARRAY);

    struct objspace *objspace = (struct objspace *)data;

    if (!mmtk_is_reachable((MMTk_ObjectReference)key)) {
        make_final_job(objspace, (VALUE)key, (VALUE)value);

        rb_postponed_job_trigger(objspace->finalizer_postponed_job);

        return ST_DELETE;
    }

    return ST_CONTINUE;
}

static void
rb_mmtk_update_finalizer_table(void)
{
    struct objspace *objspace = rb_gc_get_objspace();

    // TODO: replace with st_foreach_with_replace when GC is moving
    st_foreach(objspace->finalizer_table, rb_mmtk_update_finalizer_table_i, (st_data_t)objspace);
}

static int
rb_mmtk_update_table_i(VALUE val, void *data)
{
    if (!mmtk_is_reachable((MMTk_ObjectReference)val)) {
        return ST_DELETE;
    }

    return ST_CONTINUE;
}

static int
rb_mmtk_global_tables_count(void)
{
    return RB_GC_VM_WEAK_TABLE_COUNT;
}

static void
rb_mmtk_update_global_tables(int table)
{
    RUBY_ASSERT(table < RB_GC_VM_WEAK_TABLE_COUNT);

    rb_gc_vm_weak_table_foreach(rb_mmtk_update_table_i, NULL, NULL, true, (enum rb_gc_vm_weak_tables)table);
}

// Bootup
MMTk_RubyUpcalls ruby_upcalls = {
    rb_mmtk_init_gc_worker_thread,
    rb_mmtk_is_mutator,
    rb_mmtk_stop_the_world,
    rb_mmtk_resume_mutators,
    rb_mmtk_block_for_gc,
    rb_mmtk_number_of_mutators,
    rb_mmtk_get_mutators,
    rb_mmtk_scan_gc_roots,
    rb_mmtk_scan_objspace,
    rb_mmtk_scan_object_ruby_style,
    rb_mmtk_call_gc_mark_children,
    rb_mmtk_call_obj_free,
    rb_mmtk_vm_live_bytes,
    rb_mmtk_update_global_tables,
    rb_mmtk_global_tables_count,
    rb_mmtk_update_finalizer_table,
};

// Use max 80% of the available memory by default for MMTk
#define RB_MMTK_HEAP_LIMIT_PERC 80
#define RB_MMTK_DEFAULT_HEAP_MIN (1024 * 1024)
#define RB_MMTK_DEFAULT_HEAP_MAX (rb_mmtk_system_physical_memory() / 100 * RB_MMTK_HEAP_LIMIT_PERC)

enum mmtk_heap_mode {
    RB_MMTK_DYNAMIC_HEAP,
    RB_MMTK_FIXED_HEAP
};

MMTk_Builder *
rb_mmtk_builder_init(void)
{
    MMTk_Builder *builder = mmtk_builder_default();
    return builder;
}

void *
rb_gc_impl_objspace_alloc(void)
{
    MMTk_Builder *builder = rb_mmtk_builder_init();
    mmtk_init_binding(builder, NULL, &ruby_upcalls, (MMTk_ObjectReference)Qundef);

    return calloc(1, sizeof(struct objspace));
}

static void gc_run_finalizers(void *data);

void
rb_gc_impl_objspace_init(void *objspace_ptr)
{
    struct objspace *objspace = objspace_ptr;

    objspace->measure_gc_time = true;

    objspace->finalizer_table = st_init_numtable();
    objspace->finalizer_postponed_job = rb_postponed_job_preregister(0, gc_run_finalizers, objspace);

    ccan_list_head_init(&objspace->ractor_caches);

    objspace->mutex = (pthread_mutex_t)PTHREAD_MUTEX_INITIALIZER;
    objspace->cond_world_stopped = (pthread_cond_t)PTHREAD_COND_INITIALIZER;
    objspace->cond_world_started = (pthread_cond_t)PTHREAD_COND_INITIALIZER;
}

void
rb_gc_impl_objspace_free(void *objspace_ptr)
{
    free(objspace_ptr);
}

void *
rb_gc_impl_ractor_cache_alloc(void *objspace_ptr, void *ractor)
{
    struct objspace *objspace = objspace_ptr;
    if (objspace->live_ractor_cache_count == 0) {
        mmtk_initialize_collection(ractor);
    }
    objspace->live_ractor_cache_count++;

    struct MMTk_ractor_cache *cache = malloc(sizeof(struct MMTk_ractor_cache));
    ccan_list_add(&objspace->ractor_caches, &cache->list_node);

    cache->mutator = mmtk_bind_mutator(cache);

    return cache;
}

void
rb_gc_impl_ractor_cache_free(void *objspace_ptr, void *cache_ptr)
{
    struct objspace *objspace = objspace_ptr;
    struct MMTk_ractor_cache *cache = cache_ptr;

    ccan_list_del(&cache->list_node);

    RUBY_ASSERT(objspace->live_ractor_cache_count > 1);
    objspace->live_ractor_cache_count--;

    mmtk_destroy_mutator(cache->mutator);
}

void rb_gc_impl_set_params(void *objspace_ptr) { }

static VALUE gc_verify_internal_consistency(VALUE self) { return Qnil; }

void
rb_gc_impl_init(void)
{
    VALUE gc_constants = rb_hash_new();
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("BASE_SLOT_SIZE")), SIZET2NUM(sizeof(VALUE) * 5));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_OVERHEAD")), INT2NUM(0));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVARGC_MAX_ALLOCATE_SIZE")), LONG2FIX(640));
    // Pretend we have 5 size pools
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("SIZE_POOL_COUNT")), LONG2FIX(5));
    OBJ_FREEZE(gc_constants);
    rb_define_const(rb_mGC, "INTERNAL_CONSTANTS", gc_constants);

    // no-ops for compatibility
    rb_define_singleton_method(rb_mGC, "verify_internal_consistency", gc_verify_internal_consistency, 0);

    rb_define_singleton_method(rb_mGC, "compact", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mGC, "auto_compact", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mGC, "auto_compact=", rb_f_notimplement, 1);
    rb_define_singleton_method(rb_mGC, "latest_compact_info", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mGC, "verify_compaction_references", rb_f_notimplement, -1);
}

static size_t heap_sizes[6] = {
    40, 80, 160, 320, 640, 0
};

size_t *
rb_gc_impl_heap_sizes(void *objspace_ptr)
{
    return heap_sizes;
}

int
rb_mmtk_obj_free_iter_wrapper(VALUE obj, void *data)
{
    struct objspace *objspace = data;

    if (!RB_TYPE_P(obj, T_NONE)) {
        rb_gc_obj_free_vm_weak_references(obj);
        rb_gc_obj_free(objspace, obj);
    }

    return 0;
}

// Shutdown
static void each_object(struct objspace *objspace, int (*func)(VALUE, void *), void *data);

void
rb_gc_impl_shutdown_free_objects(void *objspace_ptr)
{
    mmtk_set_gc_enabled(false);
    each_object(objspace_ptr, rb_mmtk_obj_free_iter_wrapper, objspace_ptr);
    mmtk_set_gc_enabled(true);
}

// GC
void
rb_gc_impl_start(void *objspace_ptr, bool full_mark, bool immediate_mark, bool immediate_sweep, bool compact)
{
    mmtk_handle_user_collection_request(rb_gc_get_ractor_newobj_cache(), true, full_mark);
}

bool
rb_gc_impl_during_gc_p(void *objspace_ptr)
{
    // TODO
    return false;
}

static void
rb_gc_impl_prepare_heap_i(MMTk_ObjectReference obj, void *d)
{
    rb_gc_prepare_heap_process_object((VALUE)obj);
}

void
rb_gc_impl_prepare_heap(void *objspace_ptr)
{
    mmtk_enumerate_objects(rb_gc_impl_prepare_heap_i, NULL);
}

void
rb_gc_impl_gc_enable(void *objspace_ptr)
{
    mmtk_set_gc_enabled(true);
}

void
rb_gc_impl_gc_disable(void *objspace_ptr, bool finish_current_gc)
{
    mmtk_set_gc_enabled(false);
}

bool
rb_gc_impl_gc_enabled_p(void *objspace_ptr)
{
    return mmtk_gc_enabled_p();
}

void
rb_gc_impl_stress_set(void *objspace_ptr, VALUE flag)
{
    struct objspace *objspace = objspace_ptr;

    objspace->gc_stress = RTEST(flag);
}

VALUE
rb_gc_impl_stress_get(void *objspace_ptr)
{
    struct objspace *objspace = objspace_ptr;

    return objspace->gc_stress ? Qtrue : Qfalse;
}

VALUE
rb_gc_impl_config_get(void *objspace_ptr)
{
    VALUE hash = rb_hash_new();

    rb_hash_aset(hash, ID2SYM(rb_intern_const("mmtk_worker_count")), RB_ULONG2NUM(mmtk_worker_count()));
    rb_hash_aset(hash, ID2SYM(rb_intern_const("mmtk_plan")), rb_str_new_cstr((const char *)mmtk_plan()));
    rb_hash_aset(hash, ID2SYM(rb_intern_const("mmtk_heap_mode")), rb_str_new_cstr((const char *)mmtk_heap_mode()));
    size_t heap_min = mmtk_heap_min();
    if (heap_min > 0) rb_hash_aset(hash, ID2SYM(rb_intern_const("mmtk_heap_min")), RB_ULONG2NUM(heap_min));
    rb_hash_aset(hash, ID2SYM(rb_intern_const("mmtk_heap_max")), RB_ULONG2NUM(mmtk_heap_max()));

    return hash;
}

void
rb_gc_impl_config_set(void *objspace_ptr, VALUE hash)
{
    // TODO
}

// Object allocation

VALUE
rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t alloc_size)
{
#define MMTK_ALLOCATION_SEMANTICS_DEFAULT 0
    struct objspace *objspace = objspace_ptr;
    struct MMTk_ractor_cache *ractor_cache = cache_ptr;

    if (alloc_size > 640) rb_bug("too big");
    for (int i = 0; i < 5; i++) {
        if (alloc_size == heap_sizes[i]) break;
        if (alloc_size < heap_sizes[i]) {
            alloc_size = heap_sizes[i];
            break;
        }
    }

    if (objspace->gc_stress) {
        mmtk_handle_user_collection_request(ractor_cache, false, false);
    }

    VALUE *alloc_obj = mmtk_alloc(ractor_cache->mutator, alloc_size + 8, MMTk_MIN_OBJ_ALIGN, 0, MMTK_ALLOCATION_SEMANTICS_DEFAULT);
    alloc_obj++;
    alloc_obj[-1] = alloc_size;
    alloc_obj[0] = flags;
    alloc_obj[1] = klass;
    if (alloc_size > 16) alloc_obj[2] = v1;
    if (alloc_size > 24) alloc_obj[3] = v2;
    if (alloc_size > 32) alloc_obj[4] = v3;

    mmtk_post_alloc(ractor_cache->mutator, (void*)alloc_obj, alloc_size + 8, MMTK_ALLOCATION_SEMANTICS_DEFAULT);

    // TODO: only add when object needs obj_free to be called
    mmtk_add_obj_free_candidate(alloc_obj);

    objspace->total_allocated_objects++;

    return (VALUE)alloc_obj;
}

size_t
rb_gc_impl_obj_slot_size(VALUE obj)
{
    return ((VALUE *)obj)[-1];
}

size_t
rb_gc_impl_heap_id_for_size(void *objspace_ptr, size_t size)
{
    for (int i = 0; i < 5; i++) {
        if (size == heap_sizes[i]) return i;
        if (size < heap_sizes[i])  return i;
    }

    rb_bug("size too big");
}

bool
rb_gc_impl_size_allocatable_p(size_t size)
{
    return size <= 640;
}

// Malloc
void *
rb_gc_impl_malloc(void *objspace_ptr, size_t size)
{
    // TODO: don't use system malloc
    return malloc(size);
}

void *
rb_gc_impl_calloc(void *objspace_ptr, size_t size)
{
    // TODO: don't use system calloc
    return calloc(1, size);
}

void *
rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size)
{
    // TODO: don't use system realloc
    return realloc(ptr, new_size);
}

void
rb_gc_impl_free(void *objspace_ptr, void *ptr, size_t old_size)
{
    // TODO: don't use system free
    free(ptr);
}

void rb_gc_impl_adjust_memory_usage(void *objspace_ptr, ssize_t diff) { }

// Marking
void
rb_gc_impl_mark(void *objspace_ptr, VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) return;

    rb_mmtk_gc_thread_tls->object_closure.c_function(rb_mmtk_gc_thread_tls->object_closure.rust_closure,
                                                     rb_mmtk_gc_thread_tls->gc_context,
                                                     (MMTk_ObjectReference)obj,
                                                     false);
}

void
rb_gc_impl_mark_and_move(void *objspace_ptr, VALUE *ptr)
{
    if (RB_SPECIAL_CONST_P(*ptr)) return;

    // TODO: make it movable
    rb_gc_impl_mark(objspace_ptr, *ptr);
}

void
rb_gc_impl_mark_and_pin(void *objspace_ptr, VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) return;

    // TODO: also pin
    rb_gc_impl_mark(objspace_ptr, obj);
}

void
rb_gc_impl_mark_maybe(void *objspace_ptr, VALUE obj)
{
    if (rb_gc_impl_pointer_to_heap_p(objspace_ptr, (const void *)obj)) {
        rb_gc_impl_mark_and_pin(objspace_ptr, obj);
    }
}

void
rb_gc_impl_mark_weak(void *objspace_ptr, VALUE *ptr)
{
    mmtk_mark_weak((MMTk_ObjectReference *)ptr);
}

void
rb_gc_impl_remove_weak(void *objspace_ptr, VALUE parent_obj, VALUE *ptr)
{
    mmtk_remove_weak((MMTk_ObjectReference *)ptr);
}

// Compaction
bool
rb_gc_impl_object_moved_p(void *objspace_ptr, VALUE obj)
{
    rb_bug("unimplemented");
}

VALUE
rb_gc_impl_location(void *objspace_ptr, VALUE value)
{
    rb_bug("unimplemented");
}

// Write barriers
void
rb_gc_impl_writebarrier(void *objspace_ptr, VALUE a, VALUE b)
{
    struct MMTk_ractor_cache *cache = rb_gc_get_ractor_newobj_cache();

    mmtk_object_reference_write_post(cache->mutator, (MMTk_ObjectReference)a);
}

void
rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj)
{
    mmtk_register_wb_unprotected_object((MMTk_ObjectReference)obj);
}

void
rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj)
{
    struct MMTk_ractor_cache *cache = rb_gc_get_ractor_newobj_cache();

    mmtk_object_reference_write_post(cache->mutator, (MMTk_ObjectReference)obj);
}

// Heap walking
static void
each_objects_i(MMTk_ObjectReference obj, void *d)
{
    rb_darray(VALUE) *objs = d;

    rb_darray_append(objs, (VALUE)obj);
}

static void
each_object(struct objspace *objspace, int (*func)(VALUE, void *), void *data)
{
    rb_darray(VALUE) objs;
    rb_darray_make(&objs, 0);

    mmtk_enumerate_objects(each_objects_i, &objs);

    VALUE *obj_ptr;
    rb_darray_foreach(objs, i, obj_ptr) {
        if (!mmtk_is_mmtk_object((MMTk_ObjectReference)*obj_ptr)) continue;

        if (func(*obj_ptr, data) != 0) {
            break;
        }
    }

    rb_darray_free(objs);
}

struct rb_gc_impl_each_objects_data {
    int (*func)(void *, void *, size_t, void *);
    void *data;
};

static int
rb_gc_impl_each_objects_i(VALUE obj, void *d)
{
    struct rb_gc_impl_each_objects_data *data = d;

    size_t slot_size = rb_gc_impl_obj_slot_size(obj);

    return data->func((void *)obj, (void *)(obj + slot_size), slot_size, data->data);
}

void
rb_gc_impl_each_objects(void *objspace_ptr, int (*func)(void *, void *, size_t, void *), void *data)
{
    struct rb_gc_impl_each_objects_data each_objects_data = {
        .func = func,
        .data = data
    };

    each_object(objspace_ptr, rb_gc_impl_each_objects_i, &each_objects_data);
}

struct rb_gc_impl_each_object_data {
    void (*func)(VALUE, void *);
    void *data;
};

static int
rb_gc_impl_each_object_i(VALUE obj, void *d)
{
    struct rb_gc_impl_each_object_data *data = d;

    data->func(obj, data->data);

    return 0;
}

void
rb_gc_impl_each_object(void *objspace_ptr, void (*func)(VALUE, void *), void *data)
{
    struct rb_gc_impl_each_object_data each_object_data = {
        .func = func,
        .data = data
    };

    each_object(objspace_ptr, rb_gc_impl_each_object_i, &each_object_data);
}

// Finalizers
static VALUE
gc_run_finalizers_get_final(long i, void *data)
{
    VALUE table = (VALUE)data;

    return RARRAY_AREF(table, i);
}

static void
gc_run_finalizers(void *data)
{
    struct objspace *objspace = data;

    rb_gc_set_pending_interrupt();

    while (objspace->finalizer_jobs != NULL) {
        struct MMTk_final_job *job = objspace->finalizer_jobs;
        objspace->finalizer_jobs = job->next;

        switch (job->kind) {
          case MMTK_FINAL_JOB_DFREE:
            job->as.dfree.func(job->as.dfree.data);
            break;
          case MMTK_FINAL_JOB_FINALIZE: {
            VALUE object_id = job->as.finalize.object_id;
            VALUE finalizer_array = job->as.finalize.finalizer_array;

            rb_gc_run_obj_finalizer(
                job->as.finalize.object_id,
                RARRAY_LEN(finalizer_array),
                gc_run_finalizers_get_final,
                (void *)finalizer_array
            );

            RB_GC_GUARD(object_id);
            RB_GC_GUARD(finalizer_array);
            break;
          }
        }

        xfree(job);
    }

    rb_gc_unset_pending_interrupt();
}

void
rb_gc_impl_make_zombie(void *objspace_ptr, VALUE obj, void (*dfree)(void *), void *data)
{
    if (dfree == NULL) return;

    struct objspace *objspace = objspace_ptr;

    struct MMTk_final_job *job = xmalloc(sizeof(struct MMTk_final_job));
    job->kind = MMTK_FINAL_JOB_DFREE;
    job->as.dfree.func = dfree;
    job->as.dfree.data = data;

    struct MMTk_final_job *prev;
    do {
        job->next = objspace->finalizer_jobs;
        prev = RUBY_ATOMIC_PTR_CAS(objspace->finalizer_jobs, job->next, job);
    } while (prev != job->next);

    if (!ruby_free_at_exit_p()) {
        rb_postponed_job_trigger(objspace->finalizer_postponed_job);
    }
}

VALUE
rb_gc_impl_define_finalizer(void *objspace_ptr, VALUE obj, VALUE block)
{
    struct objspace *objspace = objspace_ptr;
    VALUE table;
    st_data_t data;

    RBASIC(obj)->flags |= FL_FINALIZE;

    int lev = rb_gc_vm_lock();

    if (st_lookup(objspace->finalizer_table, obj, &data)) {
        table = (VALUE)data;

        /* avoid duplicate block, table is usually small */
        {
            long len = RARRAY_LEN(table);
            long i;

            for (i = 0; i < len; i++) {
                VALUE recv = RARRAY_AREF(table, i);
                if (rb_equal(recv, block)) {
                    rb_gc_vm_unlock(lev);
                    return recv;
                }
            }
        }

        rb_ary_push(table, block);
    }
    else {
        table = rb_ary_new3(1, block);
        rb_obj_hide(table);
        st_add_direct(objspace->finalizer_table, obj, table);
    }

    rb_gc_vm_unlock(lev);

    return block;
}

void
rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj)
{
    struct objspace *objspace = objspace_ptr;

    st_data_t data = obj;

    int lev = rb_gc_vm_lock();
    st_delete(objspace->finalizer_table, &data, 0);
    rb_gc_vm_unlock(lev);

    FL_UNSET(obj, FL_FINALIZE);
}

void
rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj)
{
    struct objspace *objspace = objspace_ptr;
    VALUE table;
    st_data_t data;

    if (!FL_TEST(obj, FL_FINALIZE)) return;

    int lev = rb_gc_vm_lock();
    if (RB_LIKELY(st_lookup(objspace->finalizer_table, obj, &data))) {
        table = rb_ary_dup((VALUE)data);
        RARRAY_ASET(table, 0, rb_obj_id(dest));
        st_insert(objspace->finalizer_table, dest, table);
        FL_SET(dest, FL_FINALIZE);
    }
    else {
        rb_bug("rb_gc_copy_finalizer: FL_FINALIZE set but not found in finalizer_table: %s", rb_obj_info(obj));
    }
    rb_gc_vm_unlock(lev);
}

static int
move_finalizer_from_table_i(st_data_t key, st_data_t val, st_data_t arg)
{
    struct objspace *objspace = (struct objspace *)arg;

    make_final_job(objspace, (VALUE)key, (VALUE)val);

    return ST_DELETE;
}

void
rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr)
{
    struct objspace *objspace = objspace_ptr;

    while (objspace->finalizer_table->num_entries) {
        st_foreach(objspace->finalizer_table, move_finalizer_from_table_i, (st_data_t)objspace);

        gc_run_finalizers(objspace);
    }

    struct MMTk_RawVecOfObjRef registered_candidates = mmtk_get_all_obj_free_candidates();
    for (size_t i = 0; i < registered_candidates.len; i++) {
        VALUE obj = (VALUE)registered_candidates.ptr[i];

        if (rb_gc_shutdown_call_finalizer_p(obj)) {
            rb_gc_obj_free(objspace_ptr, obj);
            RBASIC(obj)->flags = 0;
        }
    }
    mmtk_free_raw_vec_of_obj_ref(registered_candidates);

    gc_run_finalizers(objspace);
}

// Forking

void
rb_gc_impl_before_fork(void *objspace_ptr)
{
    mmtk_before_fork();
}

void
rb_gc_impl_after_fork(void *objspace_ptr, rb_pid_t pid)
{
    mmtk_after_fork(rb_gc_get_ractor_newobj_cache());
}

// Statistics

void
rb_gc_impl_set_measure_total_time(void *objspace_ptr, VALUE flag)
{
    struct objspace *objspace = objspace_ptr;

    objspace->measure_gc_time = RTEST(flag);
}

bool
rb_gc_impl_get_measure_total_time(void *objspace_ptr)
{
    struct objspace *objspace = objspace_ptr;

    return objspace->measure_gc_time;
}

unsigned long long
rb_gc_impl_get_total_time(void *objspace_ptr)
{
    struct objspace *objspace = objspace_ptr;

    return objspace->total_gc_time;
}

size_t
rb_gc_impl_gc_count(void *objspace_ptr)
{
    struct objspace *objspace = objspace_ptr;

    return objspace->gc_count;
}

VALUE
rb_gc_impl_latest_gc_info(void *objspace_ptr, VALUE hash_or_key)
{
    VALUE hash = Qnil, key = Qnil;

    if (SYMBOL_P(hash_or_key)) {
        key = hash_or_key;
    }
    else if (RB_TYPE_P(hash_or_key, T_HASH)) {
        hash = hash_or_key;
    }
    else {
        rb_bug("gc_info_decode: non-hash or symbol given");
    }

#define SET(name, attr) \
    if (key == ID2SYM(rb_intern_const(#name))) \
        return (attr); \
    else if (hash != Qnil) \
        rb_hash_aset(hash, ID2SYM(rb_intern_const(#name)), (attr));

    /* Hack to get StackProf working because it calls rb_gc_latest_gc_info with
     * the :state key and expects a result. This always returns the :none state. */
    SET(state, ID2SYM(rb_intern_const("none")));
#undef SET

    if (!NIL_P(key)) {
        // Matched key should return above
        return Qundef;
    }

    return hash;
}

enum gc_stat_sym {
    gc_stat_sym_count,
    gc_stat_sym_time,
    gc_stat_sym_total_allocated_objects,
    gc_stat_sym_total_bytes,
    gc_stat_sym_used_bytes,
    gc_stat_sym_free_bytes,
    gc_stat_sym_starting_heap_address,
    gc_stat_sym_last_heap_address,
    gc_stat_sym_last
};

static VALUE gc_stat_symbols[gc_stat_sym_last];

static void
setup_gc_stat_symbols(void)
{
    if (gc_stat_symbols[0] == 0) {
#define S(s) gc_stat_symbols[gc_stat_sym_##s] = ID2SYM(rb_intern_const(#s))
        S(count);
        S(time);
        S(total_allocated_objects);
        S(total_bytes);
        S(used_bytes);
        S(free_bytes);
        S(starting_heap_address);
        S(last_heap_address);
    }
}

VALUE
rb_gc_impl_stat(void *objspace_ptr, VALUE hash_or_sym)
{
    struct objspace *objspace = objspace_ptr;
    VALUE hash = Qnil, key = Qnil;

    setup_gc_stat_symbols();

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
    if (key == gc_stat_symbols[gc_stat_sym_##name]) \
        return SIZET2NUM(attr); \
    else if (hash != Qnil) \
        rb_hash_aset(hash, gc_stat_symbols[gc_stat_sym_##name], SIZET2NUM(attr));

        SET(count, objspace->gc_count);
        SET(time, objspace->total_gc_time / (1000 * 1000));
        SET(total_allocated_objects, objspace->total_allocated_objects);
        SET(total_bytes, mmtk_total_bytes());
        SET(used_bytes, mmtk_used_bytes());
        SET(free_bytes, mmtk_free_bytes());
        SET(starting_heap_address, (size_t)mmtk_starting_heap_address());
        SET(last_heap_address, (size_t)mmtk_last_heap_address());
#undef SET

    if (!NIL_P(key)) {
        // Matched key should return above
        return Qundef;
    }

    return hash;
}

VALUE
rb_gc_impl_stat_heap(void *objspace_ptr, VALUE heap_name, VALUE hash_or_sym)
{
    if (RB_TYPE_P(hash_or_sym, T_HASH)) {
        return hash_or_sym;
    }
    else {
        return Qundef;
    }
}

// Miscellaneous

#define RB_GC_OBJECT_METADATA_ENTRY_COUNT 1
static struct rb_gc_object_metadata_entry object_metadata_entries[RB_GC_OBJECT_METADATA_ENTRY_COUNT + 1];

struct rb_gc_object_metadata_entry *
rb_gc_impl_object_metadata(void *objspace_ptr, VALUE obj)
{
    static ID ID_object_id;

    if (!ID_object_id) {
#define I(s) ID_##s = rb_intern(#s);
        I(object_id);
#undef I
    }

    size_t n = 0;

#define SET_ENTRY(na, v) do { \
    RUBY_ASSERT(n <= RB_GC_OBJECT_METADATA_ENTRY_COUNT); \
    object_metadata_entries[n].name = ID_##na; \
    object_metadata_entries[n].val = v; \
    n++; \
} while (0)

    if (rb_obj_id_p(obj)) SET_ENTRY(object_id, rb_obj_id(obj));

    object_metadata_entries[n].name = 0;
    object_metadata_entries[n].val = 0;

    return object_metadata_entries;
}

bool
rb_gc_impl_pointer_to_heap_p(void *objspace_ptr, const void *ptr)
{
    if (ptr == NULL) return false;
    if ((uintptr_t)ptr % sizeof(void*) != 0) return false;
    return mmtk_is_mmtk_object((MMTk_Address)ptr);
}

bool
rb_gc_impl_garbage_object_p(void *objspace_ptr, VALUE obj)
{
    return false;
}

void rb_gc_impl_set_event_hook(void *objspace_ptr, const rb_event_flag_t event) { }

void
rb_gc_impl_copy_attributes(void *objspace_ptr, VALUE dest, VALUE obj)
{
    if (mmtk_object_wb_unprotected_p((MMTk_ObjectReference)obj)) {
        rb_gc_impl_writebarrier_unprotect(objspace_ptr, dest);
    }

    rb_gc_impl_copy_finalizer(objspace_ptr, dest, obj);
}

// GC Identification

const char *
rb_gc_impl_active_gc_name(void)
{
    return "mmtk";
}
