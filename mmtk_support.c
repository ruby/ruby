#include "ruby/internal/config.h"

#if USE_MMTK
#include "internal/mmtk_support.h"

#include "internal.h"
#include "internal/cmdlineopt.h"
#include "internal/gc.h"
#include "internal/mmtk.h"
#include "internal/thread.h"
#include "ruby/ruby.h"
#include "ractor_core.h"
#include "vm_core.h"
#include "vm_sync.h"

// Declare some data types defined elsewhere.
// rb_objspace_t from gc.c
typedef struct rb_objspace rb_objspace_t;
#define rb_objspace (*rb_objspace_of(GET_VM()))
#define rb_objspace_of(vm) ((vm)->objspace)
// From ractor.c.  gc.c also declared this function locally.
bool rb_obj_is_main_ractor(VALUE gv);

static bool mmtk_enable = false;

RubyBindingOptions ruby_binding_options;
MMTk_RubyUpcalls ruby_upcalls;

const char *mmtk_pre_arg_plan = NULL;
const char *mmtk_post_arg_plan = NULL;
const char *mmtk_chosen_plan = NULL;
size_t mmtk_pre_max_heap_size = 0;
size_t mmtk_post_max_heap_size = 0;

bool mmtk_max_heap_parse_error = false;
size_t mmtk_max_heap_size = 0;

bool obj_free_on_exit_started = false;

// Use up to 80% of memory for the heap
static const int rb_mmtk_heap_limit_percentage = 80;

bool
rb_mmtk_enabled_p(void)
{
    return mmtk_enable;
}

static size_t rb_mmtk_system_physical_memory(void)
{
#ifdef __linux__
    const long physical_pages = sysconf(_SC_PHYS_PAGES);
    const long page_size = sysconf(_SC_PAGE_SIZE);
    if (physical_pages == -1 || page_size == -1)
    {
        rb_bug("failed to get system physical memory size");
    }
    return (size_t) physical_pages * (size_t) page_size;
#else
#error no implementation of rb_mmtk_system_physical_memory on this platform
#endif
}

static size_t rb_mmtk_available_system_memory(void)
{
    /*
     * If we're in a container, we should use the maximum container memory,
     * otherwise each container will try to use all system memory. There's
     * example logic for this in the JVM and SVM (see CgroupV1Subsystem
     * and CgroupV2Subsystem).
     */

    return rb_mmtk_system_physical_memory();
}

static void rb_mmtk_heap_limit(bool *is_dynamic, size_t *min_size, size_t *max_size) {
    if (mmtk_max_heap_size > 0) {
        *is_dynamic = false;
        *min_size = 0;
        *max_size = mmtk_max_heap_size;
    } else {
        const size_t default_min = 1024 * 1024;
        size_t default_max = rb_mmtk_available_system_memory() / 100 * rb_mmtk_heap_limit_percentage;
        if (default_max < default_min) {
            default_max = default_min;
        }
        *is_dynamic = true;
        *min_size = default_min;
        *max_size = default_max;
    }
}

void
rb_mmtk_main_thread_init(void)
{
MMTk_Builder *mmtk_builder = mmtk_builder_default();

        mmtk_builder_set_plan(mmtk_builder, mmtk_chosen_plan);

        bool is_dynamic;
        size_t min_size, max_size;
        rb_mmtk_heap_limit(&is_dynamic, &min_size, &max_size);
        if (is_dynamic) {
            mmtk_builder_set_dynamic_heap_size(mmtk_builder, min_size, max_size);
        } else {
            mmtk_builder_set_fixed_heap_size(mmtk_builder, max_size);
        }

#if RACTOR_CHECK_MODE
        ruby_binding_options.ractor_check_mode = true;
        ruby_binding_options.suffix_size = sizeof(uint32_t);
#else
        ruby_binding_options.ractor_check_mode = false;
        ruby_binding_options.suffix_size = 0;
#endif

        mmtk_init_binding(mmtk_builder, &ruby_binding_options, &ruby_upcalls);
}

size_t
rb_mmtk_prefix_size(void)
{
    return MMTK_OBJREF_OFFSET;
}

size_t
rb_mmtk_suffix_size(void)
{
    // In RACTOR_CHECK_MODE, an additional hidden field is added to hold the Ractor ID.
    return ruby_binding_options.suffix_size;
}


/*
 *  call-seq:
 *      GC::MMTk.plan_name -> String
 *
 *  Returns the name of the current MMTk plan.
 */
VALUE
rb_mmtk_plan_name(VALUE _)
{
    if (!rb_mmtk_enabled_p()) {
        rb_raise(rb_eRuntimeError, "Debug harness can only be used when MMTk is enabled, re-run with --mmtk.");
    }
    const char* plan_name = mmtk_plan_name();
    return rb_str_new(plan_name, strlen(plan_name));
}

/*
 *  call-seq:
 *      GC::MMTk.enabled? -> true or false
 *
 *  Returns true if using MMTk as garbage collector, false otherwise.
 *
 *  Note: If the Ruby interpreter is not compiled with MMTk support, the
 *  <code>GC::MMTk</code> module will not exist in the first place.
 *  You can check if the module exists by
 *
 *    defined? GC::MMTk
 */
VALUE
rb_mmtk_enabled(VALUE _)
{
    return RBOOL(rb_mmtk_enabled_p());
}

/*
 *  call-seq:
 *      GC::MMTk.harness_begin
 *
 *  A hook to be called before a benchmark begins.
 *
 *  MMTk will do necessary preparations (such as triggering a full-heap GC)
 *  and start collecting statistic data, such as the number of GC triggered,
 *  time spent in GC, time spent in mutator, etc.
 */
VALUE
rb_mmtk_harness_begin(VALUE _)
{
    if (!rb_mmtk_enabled_p()) {
        rb_raise(rb_eRuntimeError, "Debug harness can only be used when MMTk is enabled, re-run with --mmtk.");
    }
    mmtk_harness_begin((MMTk_VMMutatorThread)GET_THREAD());
    return Qnil;
}

/*
 *  call-seq:
 *      GC::MMTk.harness_end
 *
 *  A hook to be called after a benchmark ends.
 *
 *  When this method is called, MMTk will stop collecting statistic data and
 *  print out the data already collected.
 */
VALUE
rb_mmtk_harness_end(VALUE _)
{
    if (!rb_mmtk_enabled_p()) {
        rb_raise(rb_eRuntimeError, "Debug harness can only be used when MMTk is enabled, re-run with --mmtk.");
    }
    mmtk_harness_end((MMTk_VMMutatorThread)GET_THREAD());
    return Qnil;
}

#endif // USE_MMTK

bool
rb_gc_obj_free_on_exit_started(void) {
    return obj_free_on_exit_started;
}

void
rb_gc_set_obj_free_on_exit_started(void) {
    obj_free_on_exit_started = true;
}

struct RubyMMTKThreadIterator {
    rb_thread_t **threads;
    size_t num_threads;
    size_t cursor;
};

struct RubyMMTKGlobal {
    pthread_mutex_t mutex;
    pthread_cond_t cond_world_stopped;
    pthread_cond_t cond_world_started;
    size_t stopped_ractors;
    size_t start_the_world_count;
    struct RubyMMTKThreadIterator thread_iter;
} rb_mmtk_global = {
    .mutex = PTHREAD_MUTEX_INITIALIZER,
    .cond_world_stopped = PTHREAD_COND_INITIALIZER,
    .cond_world_started = PTHREAD_COND_INITIALIZER,
    .stopped_ractors = 0,
    .start_the_world_count = 0,
    .thread_iter = {
        .threads = NULL,
        .num_threads = 0,
        .cursor = 0,
    },
};

struct rb_mmtk_address_buffer {
    void **slots;
    size_t len;
    size_t capa;
};

#ifdef RB_THREAD_LOCAL_SPECIFIER
RB_THREAD_LOCAL_SPECIFIER struct MMTk_GCThreadTLS *rb_mmtk_gc_thread_tls;
#else // RB_THREAD_LOCAL_SPECIFIER
#error We currently need language-supported TLS
#endif // RB_THREAD_LOCAL_SPECIFIER

static void
rb_mmtk_use_mmtk_global(void (*func)(void *), void* arg)
{
    int err;
    if ((err = pthread_mutex_lock(&rb_mmtk_global.mutex)) != 0) {
        fprintf(stderr, "ERROR: cannot lock rb_mmtk_global.mutex: %s", strerror(err));
        abort();
    }

    func(arg);

    if ((err = pthread_mutex_unlock(&rb_mmtk_global.mutex)) != 0) {
        fprintf(stderr, "ERROR: cannot release rb_mmtk_global.mutex: %s", strerror(err));
        abort();
    }
}

void
rb_gc_init_collection(void)
{
    rb_thread_t *cur_thread = GET_THREAD();
    mmtk_initialize_collection((void*)cur_thread);
    cur_thread->mutator = mmtk_bind_mutator((MMTk_VMMutatorThread)cur_thread);
}

static inline MMTk_ObjectReference
rb_mmtk_call_object_closure(MMTk_ObjectReference object, bool pin) {
    return rb_mmtk_gc_thread_tls->object_closure.c_function(rb_mmtk_gc_thread_tls->object_closure.rust_closure,
                                                            rb_mmtk_gc_thread_tls->gc_context,
                                                            object,
                                                            pin);
}

static void
rb_mmtk_init_gc_worker_thread(MMTk_VMWorkerThread gc_thread_tls)
{
    rb_mmtk_gc_thread_tls = gc_thread_tls;
}

static MMTk_VMWorkerThread
rb_mmtk_get_gc_thread_tls(void)
{
    return rb_mmtk_gc_thread_tls;
}

static inline bool
rb_mmtk_is_mmtk_worker(void)
{
    return rb_mmtk_gc_thread_tls != NULL;
}

static inline bool
rb_mmtk_is_mutator(void)
{
    return ruby_native_thread_p();
}

void
rb_mmtk_assert_mmtk_worker(void)
{
    RUBY_ASSERT_MESG(rb_mmtk_is_mmtk_worker(), "The current thread is not an MMTk worker");
}

static inline void
rb_mmtk_assert_mutator(void)
{
    RUBY_ASSERT_MESG(rb_mmtk_is_mutator(), "The current thread is not a mutator (i.e. Ruby thread)");
}

static void
rb_mmtk_panic_if_multiple_ractor(const char *msg)
{
    if (rb_multi_ractor_p()) {
        fprintf(stderr, "Panic: %s is not implememted for multiple ractors.\n", msg);
        abort();
    }
}

static void
rb_mmtk_wait_until_ractors_stopped(void *unused)
{
    while (rb_mmtk_global.stopped_ractors < 1) {
        RUBY_DEBUG_LOG("Will wait for 1 ractor to stop. cur: %zu, expected: %zu",
                rb_mmtk_global.stopped_ractors, (size_t)1);
        pthread_cond_wait(&rb_mmtk_global.cond_world_stopped, &rb_mmtk_global.mutex);
    }
}

static void
rb_mmtk_stop_the_world(MMTk_VMWorkerThread _tls)
{
    rb_mmtk_assert_mmtk_worker();
    rb_mmtk_panic_if_multiple_ractor(__FUNCTION__);

    // We assume there is only one ractor.
    // Then the only cause of stop the world is allocation failure.
    // We wait until the only ractor has stopped.

    rb_mmtk_use_mmtk_global(rb_mmtk_wait_until_ractors_stopped, NULL);
}

static void
rb_mmtk_increment_start_the_world_count(void *unused)
{
    (void)unused;
    rb_mmtk_global.start_the_world_count++;
    pthread_cond_broadcast(&rb_mmtk_global.cond_world_started);
}

static void
rb_mmtk_resume_mutators(MMTk_VMWorkerThread tls)
{
    rb_mmtk_assert_mmtk_worker();
    rb_mmtk_panic_if_multiple_ractor(__FUNCTION__);

    rb_mmtk_use_mmtk_global(rb_mmtk_increment_start_the_world_count, NULL);
}

static void
rb_mmtk_block_for_gc_internal(void *unused)
{
    // Increment the stopped ractor count
    rb_mmtk_global.stopped_ractors++;
    if (rb_mmtk_global.stopped_ractors == 1) {
        RUBY_DEBUG_LOG("The only ractor has stopped.  Notify the GC thread.");
        pthread_cond_broadcast(&rb_mmtk_global.cond_world_stopped);
    }

    // Wait for GC end
    size_t my_count = rb_mmtk_global.start_the_world_count;

    while (rb_mmtk_global.start_the_world_count < my_count + 1) {
        RUBY_DEBUG_LOG("Will wait for cond. cur: %zu, expected: %zu",
                rb_mmtk_global.start_the_world_count, my_count + 1);
        pthread_cond_wait(&rb_mmtk_global.cond_world_started, &rb_mmtk_global.mutex);
    }

    // Decrement the stopped ractor count
    rb_mmtk_global.stopped_ractors--;

    RUBY_DEBUG_LOG("GC finished.");
}

static void
rb_mmtk_block_for_gc(MMTk_VMMutatorThread tls)
{
    rb_mmtk_assert_mutator();

    rb_thread_t *th = GET_THREAD();
    RB_GC_SAVE_MACHINE_CONTEXT(th);
    rb_mmtk_use_mmtk_global(rb_mmtk_block_for_gc_internal, NULL);

#if USE_MMTK
    if (rb_mmtk_enabled_p()) {
        RUBY_DEBUG_LOG("GC finished.  Mutator resumed.");
    }
#endif
}

static size_t
rb_mmtk_number_of_mutators(void)
{
    rb_mmtk_assert_mmtk_worker();
    rb_mmtk_panic_if_multiple_ractor(__FUNCTION__);

    rb_ractor_t *main_ractor = GET_VM()->ractor.main_ractor;
    size_t num_threads = main_ractor->threads.cnt;
    return num_threads;
}

static void
rb_mmtk_reset_mutator_iterator(void)
{
    rb_mmtk_assert_mmtk_worker();
    rb_mmtk_panic_if_multiple_ractor(__FUNCTION__);

    struct RubyMMTKThreadIterator *thread_iter = &rb_mmtk_global.thread_iter;

    if (thread_iter->threads != NULL) {
        free(thread_iter->threads);
    }

    rb_ractor_t *main_ractor = GET_VM()->ractor.main_ractor;

    size_t num_threads = main_ractor->threads.cnt;

    rb_thread_t **threads = (rb_thread_t**)malloc(sizeof(rb_thread_t*) * num_threads);
    RUBY_ASSERT(threads != NULL); // Could this fail? Maybe if the GC itself uses malloc.

    size_t i = 0;
    rb_thread_t *th = NULL;
    ccan_list_for_each(&main_ractor->threads.set, th, lt_node) {
        RUBY_ASSERT(i < num_threads);
        threads[i] = th;
        i++;
    }

    thread_iter->threads = threads;
    thread_iter->num_threads = num_threads;
    thread_iter->cursor = 0;
}

static MMTk_Mutator*
rb_mmtk_get_next_mutator(void)
{
    rb_mmtk_assert_mmtk_worker();
    rb_mmtk_panic_if_multiple_ractor(__FUNCTION__);

    struct RubyMMTKThreadIterator *thread_iter = &rb_mmtk_global.thread_iter;

    RUBY_ASSERT_MESG(thread_iter->threads != NULL,
        "thread_iter->threads is NULL. Maybe rb_mmtk_reset_mutator_iterator is not called");

    if (thread_iter->cursor < thread_iter->num_threads) {
        rb_thread_t *thread = thread_iter->threads[thread_iter->cursor];
        thread_iter->cursor++;
        return thread->mutator;
    } else {
        return NULL;
    }
}

static void
rb_mmtk_scan_vm_specific_roots(void)
{
    rb_mmtk_assert_mmtk_worker();

    RUBY_DEBUG_LOG("Scanning VM-specific roots...");

    rb_mmtk_mark_roots();
}

RBIMPL_ATTR_NORETURN()
static void
rb_mmtk_scan_thread_roots(void)
{
    abort(); // We are not using this function at this time.
}

static void
rb_mmtk_scan_thread_root(MMTk_VMMutatorThread mutator, MMTk_VMWorkerThread worker)
{
    rb_mmtk_assert_mmtk_worker();

    rb_thread_t *thread = mutator;
    rb_execution_context_t *ec = thread->ec;

    RUBY_DEBUG_LOG("[Worker: %p] We will scan thread root for thread: %p, ec: %p", worker, thread, ec);

    rb_execution_context_mark(ec);

    RUBY_DEBUG_LOG("[Worker: %p] Finished scanning thread for thread: %p, ec: %p", worker, thread, ec);
}

static inline void
rb_mmtk_mark(VALUE obj, bool pin)
{
    rb_mmtk_assert_mmtk_worker();
    RUBY_DEBUG_LOG("Marking: %s %s %p",
        pin ? "(pin)" : "     ",
        RB_SPECIAL_CONST_P(obj) ? "(spc)" : "     ",
        (void*)obj);

    if (!RB_SPECIAL_CONST_P(obj)) {
        rb_mmtk_call_object_closure((MMTk_ObjectReference)obj, pin);
    }
}

void
rb_mmtk_mark_movable(VALUE obj)
{
    rb_mmtk_mark(obj, false);
}

void
rb_mmtk_mark_pin(VALUE obj)
{
    rb_mmtk_mark(obj, true);
}

void
rb_mmtk_mark_and_move(VALUE *field)
{
    VALUE obj = *field;
    if (!RB_SPECIAL_CONST_P(obj)) {
        MMTk_ObjectReference old_ref = (MMTk_ObjectReference)obj;
        MMTk_ObjectReference new_ref = rb_mmtk_call_object_closure(old_ref, false);
        if (new_ref != old_ref) {
            *field = (VALUE)new_ref;
        }
    }
}

// This function is used to visit and update all fields during tracing.
// It shall call both gc_mark_children and gc_update_object_references during copying GC.
static inline void
rb_mmtk_scan_object_ruby_style(MMTk_ObjectReference object)
{
    rb_mmtk_assert_mmtk_worker();

    VALUE obj = (VALUE)object;

    // TODO: When mmtk-core can clear the VO bit (a.k.a. alloc-bit), we can remove this.
    if (RB_BUILTIN_TYPE(obj) == T_NONE) {
        return;
    }

    rb_mmtk_mark_children(obj);
    rb_mmtk_update_object_references(obj);
}

// This is used to determine the pinning fields of potential pinning parents (PPPs).
// It should only call gc_mark_children.
static inline void
rb_mmtk_call_gc_mark_children(MMTk_ObjectReference object)
{
    rb_mmtk_assert_mmtk_worker();

    VALUE obj = (VALUE)object;

    // TODO: When mmtk-core can clear the VO bit (a.k.a. alloc-bit), we can remove this.
    if (RB_BUILTIN_TYPE(obj) == T_NONE) {
        return;
    }

    rb_mmtk_mark_children(obj);
}

static void
rb_mmtk_call_obj_free_inner(VALUE obj, bool on_exit) {
    if (on_exit) {
        if (rb_obj_is_thread(obj)) {
            RUBY_DEBUG_LOG("Skipped thread: %p: %s", (void*)obj, rb_type_str(RB_BUILTIN_TYPE(obj)));
            return;
        }
        if (rb_obj_is_mutex(obj)) {
            RUBY_DEBUG_LOG("Skipped mutex: %p: %s", (void*)obj, rb_type_str(RB_BUILTIN_TYPE(obj)));
            return;
        }
        if (rb_obj_is_fiber(obj)) {
            RUBY_DEBUG_LOG("Skipped fiber: %p: %s", (void*)obj, rb_type_str(RB_BUILTIN_TYPE(obj)));
            return;
        }
        if (rb_obj_is_main_ractor(obj)) {
            RUBY_DEBUG_LOG("Skipped main ractor: %p: %s", (void*)obj, rb_type_str(RB_BUILTIN_TYPE(obj)));
            return;
        }
    }

    RUBY_DEBUG_LOG("Freeing object: %p: %s", (void*)obj, rb_type_str(RB_BUILTIN_TYPE(obj)));
    rb_mmtk_obj_free(obj);

    // The object may contain dangling pointers after `obj_free`.
    // Clear its flags field to ensure the GC does not attempt to scan it.
    // TODO: We can instead clear the VO bit (a.k.a. alloc-bit) when mmtk-core supports that.
    RBASIC(obj)->flags = 0;
    *(VALUE*)(&RBASIC(obj)->klass) = 0;
}

int
rb_mmtk_run_finalizers_immediately(st_data_t key, st_data_t value, st_data_t data)
{
    VALUE obj = (VALUE)key;
    VALUE finalizer_array = (VALUE)value;
    VALUE observed_id = rb_obj_id(obj);

    RUBY_DEBUG_LOG("Running finalizer on exits for %p", (void*)obj);
    rb_mmtk_run_finalizer(observed_id, finalizer_array);

    return ST_CONTINUE;
}

void
rb_mmtk_call_obj_free_on_exit(void)
{
    struct MMTk_RawVecOfObjRef resurrrected_objs = mmtk_get_all_obj_free_candidates();

    for (size_t i = 0; i < resurrrected_objs.len; i++) {
        void *resurrected = resurrrected_objs.ptr[resurrrected_objs.len - i - 1];

        VALUE obj = (VALUE)resurrected;
        rb_mmtk_call_obj_free_inner(obj, true);
    }

    mmtk_free_raw_vec_of_obj_ref(resurrrected_objs);
}

static inline void
rb_mmtk_call_obj_free(MMTk_ObjectReference object)
{
    rb_mmtk_assert_mmtk_worker();

    VALUE obj = (VALUE)object;

    rb_mmtk_call_obj_free_inner(obj, false);
}

bool
rb_mmtk_object_moved_p(VALUE value)
{
    if (!SPECIAL_CONST_P(value)) {
        MMTk_ObjectReference object = (MMTk_ObjectReference)value;
        return rb_mmtk_call_object_closure(object, false) != object;
    } else {
        return false;
    }
}

VALUE
rb_mmtk_maybe_forward(VALUE value)
{
    if (!SPECIAL_CONST_P(value)) {
        return (VALUE)rb_mmtk_call_object_closure((MMTk_ObjectReference)value, false);
    } else {
        return value;
    }
}

struct rb_mmtk_weak_table_rebuilding_context {
    st_table *old_table;
    st_table *new_table;
    bool update_values;
    rb_mmtk_hash_on_delete_func on_delete;
    void *on_delete_arg;
};

static int
rb_mmtk_update_weak_table_migrate_each(st_data_t key, st_data_t value, st_data_t arg)
{
    struct rb_mmtk_weak_table_rebuilding_context *ctx =
        (struct rb_mmtk_weak_table_rebuilding_context*)arg;

    if (mmtk_is_reachable((MMTk_ObjectReference)key)) {
        st_data_t new_key = (st_data_t)rb_mmtk_call_object_closure((MMTk_ObjectReference)key, false);
        st_data_t new_value = ctx->update_values ?
            (st_data_t)rb_mmtk_maybe_forward((VALUE)value) : // Note that value may be primitive value or objref.
            value;
        st_insert(ctx->new_table, new_key, new_value);
        RUBY_DEBUG_LOG("Forwarding key-value pair: (%p, %p) -> (%p, %p)",
            (void*)key, (void*)value, (void*)new_key, (void*)new_value);
    } else {
        // The key is dead. Discard the entry.
        RUBY_DEBUG_LOG("Discarding key-value pair: (%p, %p)",
            (void*)key, (void*)value);
        if (ctx->on_delete != NULL) {
            ctx->on_delete(key, value, ctx->on_delete_arg);
        }
    }

    return ST_CONTINUE;
}

struct rb_mmtk_weak_table_updating_context {
    bool update_values;
    rb_mmtk_hash_on_delete_func on_delete;
    void *on_delete_arg;
};

static int
rb_mmtk_update_weak_table_should_replace(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    struct rb_mmtk_weak_table_updating_context *ctx =
        (struct rb_mmtk_weak_table_updating_context*)argp;

    if (!mmtk_is_live_object((MMTk_ObjectReference)key)) {
        return ST_DELETE;
    }

    if (ctx->update_values && !mmtk_is_live_object((MMTk_ObjectReference)key)) {
        return ST_DELETE;
    }

    MMTk_ObjectReference new_key = mmtk_get_forwarded_object((MMTk_ObjectReference)key);
    if (new_key != NULL && new_key != (MMTk_ObjectReference)key) {
        return ST_REPLACE;
    }

    if (ctx->update_values) {
        MMTk_ObjectReference new_value = mmtk_get_forwarded_object((MMTk_ObjectReference)value);
        if (new_value != NULL && new_value != (MMTk_ObjectReference)value) {
            return ST_REPLACE;
        }
    }

    return ST_CONTINUE;
}

static int
rb_mmtk_update_weak_table_replace(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    struct rb_mmtk_weak_table_updating_context *ctx =
        (struct rb_mmtk_weak_table_updating_context*)argp;

    MMTk_ObjectReference new_key = mmtk_get_forwarded_object((MMTk_ObjectReference)*key);
    if (new_key != NULL && new_key != (MMTk_ObjectReference)*key) {
        *key = (st_data_t)new_key;
    }

    if (ctx->update_values) {
        MMTk_ObjectReference new_value = mmtk_get_forwarded_object((MMTk_ObjectReference)*value);
        if (new_value != NULL && new_value != (MMTk_ObjectReference)*value) {
            *value = (st_data_t)new_value;
        }
    }

    return ST_CONTINUE;
}


/*
 * Update a weak hash table after a copying GC finished.
 * If a key points to a live object, keep the key-value pair,
 * and update the key (and optionally the value) to point to their new addresses.
 * If a key points to a dead object, discard the key-value pair.
 */
void
rb_mmtk_update_weak_table(st_table *table,
                          bool addr_hashed,
                          bool update_values,
                          rb_mmtk_hash_on_delete_func on_delete,
                          void *on_delete_arg)
{
    if (!table || table->num_entries == 0) return;

    if (addr_hashed) {
        // The has table uses the address of the key object as key.
        // If a key object is moved, its hash is changed as well.
        // Therefore we must rebuild the whole hash table.
        // TODO: Implement address-based hashing to avoid this need.

        st_table *old_table = table;
        st_table *new_table = st_init_table(old_table->type);

        struct rb_mmtk_weak_table_rebuilding_context ctx = {
            .old_table = old_table,
            .new_table = new_table,
            .update_values = update_values,
            .on_delete = on_delete,
            .on_delete_arg = on_delete_arg,
        };
        if (st_foreach(old_table, rb_mmtk_update_weak_table_migrate_each, (st_data_t)&ctx)) {
            fprintf(stderr, "Did anything go wrong?");
            abort();
        }

        // Swap the contents of the old and the new table.
        // Note: The mutator may be rebuilding the same table when GC is updating it.
        // (see `rebuild_table` in st.c)
        // If the old table was not big enough, it will allocate a new table, but that may trigger GC.
        // After GC finishes and the new table is allocated,
        // the mutator will copy entries from the old table.
        // If we replace the whole old table,
        // the mutator shouldn't notice that the entire old table has been replaced during GC.
        st_table old_table_copy = *old_table;
        *old_table = *new_table;
        *new_table = old_table_copy;

        st_free_table(new_table);
    } else {
        // The table uses the content of the key object to compute the hash.
        // The hash will not change if the object is moved.
        // We can update the table in place.
        struct rb_mmtk_weak_table_updating_context ctx = {
            .update_values = update_values,
            .on_delete = on_delete,
            .on_delete_arg = on_delete_arg,
        };
        if (st_foreach_with_replace(table,
                                    rb_mmtk_update_weak_table_should_replace,
                                    rb_mmtk_update_weak_table_replace,
                                    (st_data_t)&ctx)) {
            fprintf(stderr, "Did anything go wrong?");
            abort();
        }
    }
}

struct rb_mmtk_update_value_hashed_weak_table_context {
    bool update_values;
};


MMTk_RubyUpcalls ruby_upcalls = {
    rb_mmtk_init_gc_worker_thread,
    rb_mmtk_get_gc_thread_tls,
    rb_mmtk_is_mutator,
    rb_mmtk_stop_the_world,
    rb_mmtk_resume_mutators,
    rb_mmtk_block_for_gc,
    rb_mmtk_number_of_mutators,
    rb_mmtk_reset_mutator_iterator,
    rb_mmtk_get_next_mutator,
    rb_mmtk_scan_vm_specific_roots,
    rb_mmtk_scan_thread_roots,
    rb_mmtk_scan_thread_root,
    rb_mmtk_scan_object_ruby_style,
    rb_mmtk_call_gc_mark_children,
    rb_mmtk_call_obj_free,
    rb_mmtk_update_global_weak_tables_early,
    rb_mmtk_update_global_weak_tables,
};

static size_t
rb_mmtk_parse_heap_limit(const char *argv, bool* had_error)
{
    char *endval = NULL;
    int pow = 0;

    size_t base = strtol(argv, &endval, 10);
    if (base == 0) {
        *had_error = true;
    }

    // if there were non-numbers in the string
    // try and parse them as IEC units
    if (*endval) {

        if (strcmp(endval, "TiB") == 0)  {
            pow = 40; // tebibytes. 2^40
        } else if (strcmp(endval, "GiB") == 0)  {
            pow = 30; // gibibytes. 2^30
        } else if (strcmp(endval, "MiB") == 0)  {
            pow = 20; // mebibytes. 2^20
        } else if (strcmp(endval, "KiB") == 0)  {
            pow = 10; // kibibytes. 2^10
        }
    }

    return (base << pow);
}

void rb_mmtk_pre_process_opts(int argc, char **argv) {
    /*
     * Processing these arguments is a mess - we have to process them before
     * Ruby is set up, when arguments are normally processed, because we need
     * the GC up and running to set up Ruby. We have to kind of rough parsing
     * and then re-parse them properly later and compare against our rough
     * parsing. We also can't report errors using exceptions. Needs tidying
     * up in general, but may always be a bit awkward.
     */

    bool enable_rubyopt = true;

    for (int n = 1; n < argc; n++) {
        if (strcmp(argv[n], "--") == 0) {
            break;
        }
        else if (strcmp(argv[n], "--mmtk") == 0) {
            mmtk_enable = true;
        }
        else if (strcmp(argv[n], "--enable-rubyopt") == 0
                || strcmp(argv[n], "--enable=rubyopt") == 0) {
            enable_rubyopt = true;
        }
        else if (strcmp(argv[n], "--disable-rubyopt") == 0
                || strcmp(argv[n], "--disable=rubyopt") == 0) {
            enable_rubyopt = false;
        }
        else if (strcmp(argv[n], "--enable-mmtk") == 0
                || strcmp(argv[n], "--enable=mmtk") == 0) {
            mmtk_enable = true;
        }
        else if (strcmp(argv[n], "--disable-mmtk") == 0
                || strcmp(argv[n], "--disable=mmtk") == 0) {
            mmtk_enable = false;
        }
        else if (strncmp(argv[n], "--mmtk-plan", strlen("--mmtk-plan")) == 0) {
            mmtk_enable = true;
            mmtk_pre_arg_plan = argv[n] + strlen("--mmtk-plan=");
            if (argv[n][strlen("--mmtk-plan")] != '=' || strlen(mmtk_pre_arg_plan) == 0) {
                fputs("[FATAL] --mmtk-plan needs an argument\n", stderr);
                exit(EXIT_FAILURE);
            }
        }
        else if (strncmp(argv[n], "--mmtk-max-heap", strlen("--mmtk-max-heap")) == 0) {
            mmtk_enable = true;
            char *mmtk_max_heap_size_arg = argv[n] + strlen("--mmtk-max-heap=");
            if (argv[n][strlen("--mmtk-max-heap")] != '=' || strlen(mmtk_max_heap_size_arg) == 0) {
                fputs("[FATAL] --mmtk-max-heap needs an argument\n", stderr);
                exit(EXIT_FAILURE);
            }
            mmtk_pre_max_heap_size = rb_mmtk_parse_heap_limit(mmtk_max_heap_size_arg, &mmtk_max_heap_parse_error);
            mmtk_max_heap_size = mmtk_pre_max_heap_size;
        }
    }

    if (enable_rubyopt) {
        char *env_args = getenv("RUBYOPT");
        if (env_args != NULL) {
            while (*env_args != '\0') {
                if (ISSPACE(*env_args)) {
                    env_args++;
                }
                else {
                    size_t length = 0;
                    while (env_args[length] != '\0' && !ISSPACE(env_args[length])) {
                        length++;
                    }

                    if (strncmp(env_args, "--mmtk", strlen("--mmtk")) == 0) {
                        mmtk_enable = true;
                    } else if (strncmp(env_args, "--enable-mmtk", strlen("--enable-mmtk")) == 0) {
                        mmtk_enable = true;
                    } else if (strncmp(env_args, "--enable=mmtk", strlen("--enable=mmtk")) == 0) {
                        mmtk_enable = true;
                    }

                    if (strncmp(env_args, "--mmtk-plan", strlen("--mmtk-plan")) == 0) {
                        if (env_args[strlen("--mmtk-plan")] != '=') {
                            fputs("[FATAL] --mmtk-plan needs an argument\n", stderr);
                            exit(EXIT_FAILURE);
                        }
                        mmtk_pre_arg_plan = strndup(env_args + strlen("--mmtk-plan="), length - strlen("--mmtk-plan="));
                        if (mmtk_pre_arg_plan == NULL) {
                            rb_bug("could not allocate space for argument");
                        }
                        if (strlen(mmtk_pre_arg_plan) == 0) {
                            fputs("[FATAL] --mmtk-plan needs an argument\n", stderr);
                            exit(EXIT_FAILURE);
                        }
                    } else if (strncmp(env_args, "--mmtk-max-heap", strlen("--mmtk-max-heap")) == 0) {
                        if (env_args[strlen("--mmtk-max-heap")] != '=') {
                            fputs("[FATAL] --mmtk-max-heap needs an argument\n", stderr);
                            exit(EXIT_FAILURE);
                        }
                        char *mmtk_max_heap_size_arg = strndup(env_args + strlen("--mmtk-max-heap="), length - strlen("--mmtk-max-heap="));
                        if (mmtk_max_heap_size_arg == NULL) {
                            rb_bug("could not allocate space for argument");
                        }
                        if (strlen(mmtk_max_heap_size_arg) == 0) {
                            fputs("[FATAL] --mmtk-max-heap needs an argument\n", stderr);
                            exit(EXIT_FAILURE);
                        }
                        mmtk_pre_max_heap_size = rb_mmtk_parse_heap_limit(mmtk_max_heap_size_arg, &mmtk_max_heap_parse_error);
                    }

                    env_args += length;
                }
            }
        }
    }

    if (mmtk_pre_arg_plan) {
        mmtk_chosen_plan = mmtk_pre_arg_plan;
    }
    else {
        mmtk_chosen_plan = MMTK_DEFAULT_PLAN;
    }
}

#define opt_match_arg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? 1 : (rb_raise(rb_eRuntimeError, "--mmtk-" name " needs an argument"), 0))

void rb_mmtk_post_process_opts(const char *s) {
    const size_t l = strlen(s);
    if (l == 0) {
        return;
    }
    if (opt_match_arg(s, l, "plan")) {
        mmtk_post_arg_plan = s + 1;
    }
    else if (opt_match_arg(s, l, "max-heap")) {
        mmtk_post_max_heap_size = rb_mmtk_parse_heap_limit((char *) (s + 1), &mmtk_max_heap_parse_error);
    }
    else {
        rb_raise(rb_eRuntimeError,
                 "invalid MMTk option `%s' (--help will show valid MMTk options)", s);
    }
}

void rb_mmtk_post_process_opts_finish(bool feature_enable) {
    if (feature_enable && !mmtk_enable) {
        rb_raise(rb_eRuntimeError, "--mmtk values disagree");
    }

    if (strcmp(mmtk_pre_arg_plan ? mmtk_pre_arg_plan : "", mmtk_post_arg_plan ? mmtk_post_arg_plan : "") != 0) {
        rb_raise(rb_eRuntimeError, "--mmtk-plan values disagree");
    }

    if (mmtk_pre_max_heap_size != 0 && mmtk_post_max_heap_size != 0 && mmtk_pre_max_heap_size != mmtk_post_max_heap_size) {
        rb_raise(rb_eRuntimeError, "--mmtk-max-heap values disagree");
    }

    if (mmtk_max_heap_parse_error) {
        rb_raise(rb_eRuntimeError,
                "--mmtk-max-heap Invalid. Valid values positive integers, with optional KiB, MiB, GiB, TiB suffixes.");
    }
}


