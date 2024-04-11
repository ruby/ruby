#include "ruby/internal/config.h"

#if USE_MMTK
#include "internal/mmtk_support.h"

#include "internal.h"
#include "internal/cmdlineopt.h"
#include "internal/gc.h"
#include "internal/imemo.h"
#include "internal/mmtk.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "ruby/ruby.h"
#include "ractor_core.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "stdatomic.h"

#ifdef __APPLE__
#include <sys/sysctl.h>
#endif

#ifdef __GNUC__
#define PREFETCH(addr, write_p) __builtin_prefetch(addr, write_p)
#define EXPECT(expr, val) __builtin_expect(expr, val)
#define ATTRIBUTE_UNUSED  __attribute__((unused))
#else
#define PREFETCH(addr, write_p)
#define EXPECT(expr, val) (expr)
#define ATTRIBUTE_UNUSED
#endif

////////////////////////////////////////////////////////////////////////////////
// Workaround: Declare some data types defined elsewhere.
////////////////////////////////////////////////////////////////////////////////

// rb_objspace_t from gc.c
typedef struct rb_objspace rb_objspace_t;
#define rb_objspace (*rb_objspace_of(GET_VM()))
#define rb_objspace_of(vm) ((vm)->objspace)
// From ractor.c.  gc.c also declared this function locally.
bool rb_obj_is_main_ractor(VALUE gv);

////////////////////////////////////////////////////////////////////////////////
// Mirror some data structures from mmtk-core.
// TODO: We are having problem generating the BumpPointer struct from mmtk-core.
// It should be generated automatically using cbindgen.
////////////////////////////////////////////////////////////////////////////////

struct BumpPointer {
    uintptr_t cursor;
    uintptr_t limit;
};

////////////////////////////////////////////////////////////////////////////////
// Command line arguments
////////////////////////////////////////////////////////////////////////////////

const char *mmtk_pre_arg_plan = NULL;
const char *mmtk_post_arg_plan = NULL;
const char *mmtk_chosen_plan = NULL;
bool mmtk_plan_is_immix = false;
bool mmtk_plan_uses_bump_pointer = false;
bool mmtk_plan_implicitly_pinning = false;

size_t mmtk_pre_max_heap_size = 0;
size_t mmtk_post_max_heap_size = 0;

bool mmtk_max_heap_parse_error = false;
size_t mmtk_max_heap_size = 0;

// Use up to 80% of memory for the heap
static const int rb_mmtk_heap_limit_percentage = 80;

////////////////////////////////////////////////////////////////////////////////
// Global and thread-local states.
////////////////////////////////////////////////////////////////////////////////

static bool mmtk_enable = false;

RubyBindingOptions ruby_binding_options;
MMTk_RubyUpcalls ruby_upcalls;

// TODO: Generate them as constants.
static uintptr_t mmtk_vo_bit_log_region_size;
static uintptr_t mmtk_vo_bit_base_addr;

bool obj_free_on_exit_started = false;


// DEBUG: Vanilla GC timing
static struct gc_timing {
    bool enabled;
    bool in_alloc_slow_path;
    uint64_t gc_time_ns;
    struct timespec last_enabled;
    struct timespec last_gc_start;
    uint64_t last_num_of_gc;
    uint64_t last_vanilla_mark;
    uint64_t last_vanilla_sweep;
} g_vanilla_timing;

// xmalloc accounting
struct rb_mmtk_xmalloc_accounting {
    size_t malloc_total;
} g_xmalloc_accounting;

struct RubyMMTKGlobal {
    pthread_mutex_t mutex;
    pthread_cond_t cond_world_stopped;
    pthread_cond_t cond_world_started;
    size_t stopped_ractors;
    size_t start_the_world_count;
} rb_mmtk_global = {
    .mutex = PTHREAD_MUTEX_INITIALIZER,
    .cond_world_stopped = PTHREAD_COND_INITIALIZER,
    .cond_world_started = PTHREAD_COND_INITIALIZER,
    .stopped_ractors = 0,
    .start_the_world_count = 0,
};

struct rb_mmtk_address_buffer {
    void **slots;
    size_t len;
    size_t capa;
};

#define RB_MMTK_VALUES_BUFFER_SIZE 4096

struct rb_mmtk_values_buffer {
    VALUE objects[RB_MMTK_VALUES_BUFFER_SIZE];
    size_t len;
};

struct rb_mmtk_mutator_local {
    struct BumpPointer *immix_bump_pointer;
    // for prefetching
    uintptr_t last_new_cursor;
    // for prefetching
    uintptr_t last_meta_addr;
    struct rb_mmtk_values_buffer obj_free_candidates;
    struct rb_mmtk_values_buffer ppp_buffer;
};

#ifdef RB_THREAD_LOCAL_SPECIFIER
RB_THREAD_LOCAL_SPECIFIER struct MMTk_GCThreadTLS *rb_mmtk_gc_thread_tls;
RB_THREAD_LOCAL_SPECIFIER struct rb_mmtk_mutator_local rb_mmtk_mutator_local;
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

// Helper functions for rb_mmtk_values_buffer
static bool
rb_mmtk_values_buffer_append(struct rb_mmtk_values_buffer *buffer, VALUE obj)
{
    RUBY_ASSERT(buffer != NULL);
    buffer->objects[buffer->len] = obj;
    buffer->len++;

    return buffer->len == RB_MMTK_VALUES_BUFFER_SIZE;
}

static void
rb_mmtk_values_buffer_clear(struct rb_mmtk_values_buffer *buffer)
{
    buffer->len = 0;

    // Just to be safe.
    memset(buffer->objects, 0, sizeof(buffer->objects));
}

////////////////////////////////////////////////////////////////////////////////
// Query for enabled/disabled.
////////////////////////////////////////////////////////////////////////////////

bool
rb_mmtk_enabled_p(void)
{
    return mmtk_enable;
}

////////////////////////////////////////////////////////////////////////////////
// MMTk binding initialization
////////////////////////////////////////////////////////////////////////////////

void
rb_mmtk_bind_mutator(MMTk_VMMutatorThread cur_thread)
{
    MMTk_Mutator *mutator = mmtk_bind_mutator((MMTk_VMMutatorThread)cur_thread);

    cur_thread->mutator = mutator;
    cur_thread->mutator_local = (void*)&rb_mmtk_mutator_local;

    rb_mmtk_mutator_local.immix_bump_pointer = (struct BumpPointer*)((char*)mutator + mmtk_get_immix_bump_ptr_offset());
}

static size_t
rb_mmtk_system_physical_memory(void)
{
#ifdef __linux__
    const long physical_pages = sysconf(_SC_PHYS_PAGES);
    const long page_size = sysconf(_SC_PAGE_SIZE);
    if (physical_pages == -1 || page_size == -1)
    {
        rb_bug("failed to get system physical memory size");
    }
    return (size_t) physical_pages * (size_t) page_size;
#elif defined(__APPLE__)
    int mib[2];
    mib[0] = CTL_HW;
    mib[1] = HW_MEMSIZE; // total physical memory
    int64_t physical_memory;
    size_t length = sizeof(int64_t);
    if (sysctl(mib, 2, &physical_memory, &length, NULL, 0) == -1)
    {
        rb_bug("failed to get system physical memory size");
    }
    return (size_t) physical_memory;
#else
#error no implementation of rb_mmtk_system_physical_memory on this platform
#endif
}

static size_t
rb_mmtk_available_system_memory(void)
{
    /*
     * If we're in a container, we should use the maximum container memory,
     * otherwise each container will try to use all system memory. There's
     * example logic for this in the JVM and SVM (see CgroupV1Subsystem
     * and CgroupV2Subsystem).
     */

    return rb_mmtk_system_physical_memory();
}

static void
set_default_options(MMTk_Builder *mmtk_builder)
{
    mmtk_builder_set_plan(mmtk_builder, MMTK_DEFAULT_PLAN);

    const size_t default_min = 1024 * 1024;
    size_t default_max = rb_mmtk_available_system_memory() / 100 * rb_mmtk_heap_limit_percentage;
    if (default_max < default_min) {
        default_max = default_min;
    }
    mmtk_builder_set_dynamic_heap_size(mmtk_builder, default_min, default_max);
}

static void
apply_cmdline_options(MMTk_Builder *mmtk_builder)
{
    if (mmtk_chosen_plan != NULL) {
        mmtk_builder_set_plan(mmtk_builder, mmtk_chosen_plan);
        mmtk_plan_is_immix = strcmp(mmtk_chosen_plan, "Immix") == 0 || strcmp(mmtk_chosen_plan, "StickyImmix") == 0;
        mmtk_plan_uses_bump_pointer = mmtk_plan_is_immix;
        mmtk_plan_implicitly_pinning = strcmp(mmtk_chosen_plan, "MarkSweep") == 0;
    }

    if (mmtk_max_heap_size > 0) {
        mmtk_builder_set_fixed_heap_size(mmtk_builder, mmtk_max_heap_size);
    }
}

void
rb_mmtk_main_thread_init(void)
{
    // (1) Create the builder, using MMTk's built-in defaults.
    MMTk_Builder *mmtk_builder = mmtk_builder_default();

    // (2) Override MMTK defaults with Ruby defaults.
    set_default_options(mmtk_builder);

    // (3) Read MMTk environment options (e.g. MMTK_THREADS=100)
    mmtk_builder_read_env_var_settings(mmtk_builder);

    // (4) Apply cmdline or RUBYOPT options if set.
    apply_cmdline_options(mmtk_builder);

#if RACTOR_CHECK_MODE
    ruby_binding_options.ractor_check_mode = true;
    // Ruby only needs a uint32_t for the ractor ID.
    // But we make the object size a multiple of alignment.
    ruby_binding_options.suffix_size = MMTK_MIN_OBJ_ALIGN > sizeof(uint32_t) ?
        MMTK_MIN_OBJ_ALIGN : sizeof(uint32_t);
#else
    ruby_binding_options.ractor_check_mode = false;
    ruby_binding_options.suffix_size = 0;
#endif

    mmtk_init_binding(mmtk_builder, &ruby_binding_options, &ruby_upcalls);

    mmtk_vo_bit_base_addr = mmtk_get_vo_bit_base();
    mmtk_vo_bit_log_region_size = mmtk_get_vo_bit_log_region_size();
}

////////////////////////////////////////////////////////////////////////////////
// Flushing and de-initialization
////////////////////////////////////////////////////////////////////////////////

static void rb_mmtk_flush_obj_free_candidates(struct rb_mmtk_values_buffer *buffer);
static void rb_mmtk_flush_ppp_buffer(struct rb_mmtk_values_buffer *buffer);

void
rb_mmtk_flush_mutator_local_buffers(MMTk_VMMutatorThread thread)
{
    struct rb_mmtk_mutator_local *local = (struct rb_mmtk_mutator_local*)thread->mutator_local;
    rb_mmtk_flush_obj_free_candidates(&local->obj_free_candidates);
    rb_mmtk_flush_ppp_buffer(&local->ppp_buffer);
}

void
rb_mmtk_destroy_mutator(MMTk_VMMutatorThread cur_thread)
{
    // Currently a thread can only destroy its own mutator.
    RUBY_ASSERT(cur_thread == GET_THREAD());
    RUBY_ASSERT(cur_thread->mutator_local == &rb_mmtk_mutator_local);

    rb_mmtk_flush_mutator_local_buffers(cur_thread);

    MMTk_Mutator *mutator = cur_thread->mutator;
    mmtk_destroy_mutator(mutator);

    cur_thread->mutator = NULL;
    cur_thread->mutator_local = NULL;
}

////////////////////////////////////////////////////////////////////////////////
// Object layout
////////////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////////////
// Allocation
////////////////////////////////////////////////////////////////////////////////

static void*
rb_mmtk_immix_alloc_fast_bump_pointer(size_t size)
{
    struct rb_mmtk_mutator_local *local = &rb_mmtk_mutator_local;
    // TODO: verify the usefulness of this prefetching.
    PREFETCH((void*)local->last_new_cursor, 1);
    PREFETCH((void*)local->last_meta_addr, 1);

    struct BumpPointer *immix_bump_pointer = local->immix_bump_pointer;
    uintptr_t cursor = immix_bump_pointer->cursor;
    uintptr_t limit = immix_bump_pointer->limit;

    void *result = (void*)cursor;
    uintptr_t new_cursor = cursor + size;

    // Note: If the selected plan is not Immix, then both the cursor and the limit will always be
    // 0.  In that case this function will return NULL and the caller will try the slow path.
    if (new_cursor > limit) {
        return NULL;
    } else {
        immix_bump_pointer->cursor = new_cursor;
        local->last_new_cursor = new_cursor; // save for prefetching
        return result;
    }
}

/// Wrap mmtk_alloc, but use fast path if possible.
static void*
rb_mmtk_alloc(size_t size, MMTk_AllocationSemantics semantics)
{
    if (semantics == MMTK_ALLOCATION_SEMANTICS_DEFAULT && mmtk_plan_uses_bump_pointer) {
        // Try the fast path.
        void *fast_result = rb_mmtk_immix_alloc_fast_bump_pointer(size);
        if (fast_result != NULL) {
            return fast_result;
        }
    }

    // Fall back to the slow path.
    void *result = mmtk_alloc(GET_THREAD()->mutator, size, MMTK_MIN_OBJ_ALIGN, 0, semantics);

    return result;
}

#define RB_MMTK_USE_POST_ALLOC_FAST_PATH true
#define RB_MMTK_VO_BIT_SET_NON_ATOMIC true

static void
rb_mmtk_post_alloc_fast_immix(VALUE obj)
{
    uintptr_t obj_addr = obj;
    uintptr_t region_offset = obj_addr >> mmtk_vo_bit_log_region_size;
    uintptr_t byte_offset = region_offset / 8;
    uintptr_t bit_offset = region_offset % 8;
    uintptr_t meta_byte_address = mmtk_vo_bit_base_addr + byte_offset;
    uint8_t byte = 1 << bit_offset;
    if (RB_MMTK_VO_BIT_SET_NON_ATOMIC) {
        uint8_t *meta_byte_ptr = (uint8_t*)meta_byte_address;
        *meta_byte_ptr |= byte;
    } else {
        volatile _Atomic uint8_t *meta_byte_ptr = (volatile _Atomic uint8_t*)meta_byte_address;
        // relaxed: We don't use VO bits for synchronisation during mutator phase.
        // When GC is triggered, the handshake between GC and mutator provides synchronization.
        atomic_fetch_or_explicit(meta_byte_ptr, byte, memory_order_relaxed);
    }
    rb_mmtk_mutator_local.last_meta_addr = meta_byte_address;
}

/// Wrap mmtk_post_alloc, but use fast path if possible.
static void
rb_mmtk_post_alloc(VALUE obj, size_t mmtk_alloc_size, MMTk_AllocationSemantics semantics)
{
    if (RB_MMTK_USE_POST_ALLOC_FAST_PATH && semantics == MMTK_ALLOCATION_SEMANTICS_DEFAULT && mmtk_plan_is_immix) {
        rb_mmtk_post_alloc_fast_immix(obj);
    } else {
        // Call post_alloc.  This will initialize GC-specific metadata.
        mmtk_post_alloc(GET_THREAD()->mutator, (void*)obj, mmtk_alloc_size, semantics);
    }
}

VALUE
rb_mmtk_alloc_obj(size_t mmtk_alloc_size, size_t size_pool_size, size_t prefix_size)
{
    MMTk_AllocationSemantics semantics = mmtk_alloc_size <= MMTK_MAX_IMMIX_OBJECT_SIZE ? MMTK_ALLOCATION_SEMANTICS_DEFAULT
                                       : MMTK_ALLOCATION_SEMANTICS_LOS;

    // Allocate the object.
    void *addr = rb_mmtk_alloc(mmtk_alloc_size, semantics);

    // Store the Ruby-level object size before the object.
    *(size_t*)addr = size_pool_size;

    // The Ruby-level object reference (i.e. VALUE) is at an offset from the MMTk-level
    // allocation unit.
    VALUE obj = (VALUE)addr + prefix_size;

    rb_mmtk_post_alloc(obj, mmtk_alloc_size, semantics);

    return obj;
}

////////////////////////////////////////////////////////////////////////////////
// Tracing
////////////////////////////////////////////////////////////////////////////////

static inline MMTk_ObjectReference
rb_mmtk_call_object_closure(MMTk_ObjectReference object, bool pin) {
    return rb_mmtk_gc_thread_tls->object_closure.c_function(rb_mmtk_gc_thread_tls->object_closure.rust_closure,
                                                            rb_mmtk_gc_thread_tls->gc_context,
                                                            object,
                                                            pin);
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

////////////////////////////////////////////////////////////////////////////////
// PPP support
////////////////////////////////////////////////////////////////////////////////

static bool
rb_mmtk_is_ppp(VALUE obj) {
    RUBY_ASSERT(!rb_special_const_p(obj));

    switch (RB_BUILTIN_TYPE(obj)) {
      case T_DATA:
        return true;
      case T_IMEMO:
        switch (imemo_type(obj)) {
          case imemo_iseq:
          case imemo_tmpbuf:
          case imemo_ast:
          case imemo_ifunc:
          case imemo_memo:
          case imemo_parser_strterm:
            return true;
          default:
            return false;
        }
      default:
        return false;
    }
}

static void
rb_mmtk_flush_ppp_buffer(struct rb_mmtk_values_buffer *buffer)
{
    RUBY_ASSERT(buffer != NULL);
    mmtk_register_ppps((MMTk_ObjectReference*)buffer->objects, buffer->len);
    rb_mmtk_values_buffer_clear(buffer);
}

void
rb_mmtk_maybe_register_ppp(VALUE obj) {
    RUBY_ASSERT(!rb_special_const_p(obj));

    if (rb_mmtk_is_ppp(obj)) {
        struct rb_mmtk_values_buffer *buffer = &rb_mmtk_mutator_local.ppp_buffer;
        if (rb_mmtk_values_buffer_append(buffer, obj)) {
            rb_mmtk_flush_ppp_buffer(buffer);
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
// Finalization and exiting
////////////////////////////////////////////////////////////////////////////////

static void
rb_mmtk_flush_obj_free_candidates(struct rb_mmtk_values_buffer *buffer)
{
    RUBY_ASSERT(buffer != NULL);
    mmtk_add_obj_free_candidates((MMTk_ObjectReference*)buffer->objects, buffer->len);
    rb_mmtk_values_buffer_clear(buffer);
}

static void
rb_mmtk_register_obj_free_candidate(VALUE obj)
{
    RUBY_DEBUG_LOG("Object registered for obj_free: %p: %s %s",
        (void*)obj,
        rb_type_str(RB_BUILTIN_TYPE(obj)),
        RB_BUILTIN_TYPE(obj) == T_IMEMO ? rb_imemo_name(imemo_type(obj)) :
        rb_obj_class(obj) == 0 ? "(null klass)" :
        rb_class2name(rb_obj_class(obj))
        );

    struct rb_mmtk_values_buffer *buffer = &rb_mmtk_mutator_local.obj_free_candidates;
    if (rb_mmtk_values_buffer_append(buffer, obj)) {
        rb_mmtk_flush_obj_free_candidates(buffer);
    }
}

static bool
rb_mmtk_is_obj_free_candidate(VALUE obj)
{
    // Any object that has non-trivial cleaning-up code in `obj_free`
    // should be registered as "finalizable" to MMTk.
    switch (RB_BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        // FIXME: Ordinary objects can be non-embedded, too,
        // but there are just too many such objects,
        // and few of them have large buffers.
        // Just let them leak for now.
        // We'll prioritize eliminating the underlying buffer of ordinary objects.
        return false;
      case T_MODULE:
      case T_CLASS:
      case T_HASH:
      case T_REGEXP:
      case T_DATA:
      case T_FILE:
      case T_ICLASS:
      case T_BIGNUM:
      case T_STRUCT:
        // These types need obj_free.
        return true;
      case T_IMEMO:
        switch (imemo_type(obj)) {
          case imemo_ment:
          case imemo_iseq:
          case imemo_env:
          case imemo_tmpbuf:
          case imemo_ast:
            // These imemos need obj_free.
            return true;
          default:
            // Other imemos don't need obj_free.
            return false;
        }
      case T_SYMBOL:
        // Will be unregistered from global symbol table during weak reference processing phase.
        return false;
      case T_STRING:
        // We use imemo:mmtk_strbuf (rb_mmtk_strbuf_t) as the underlying buffer.
        return false;
      case T_ARRAY:
        // We use imemo:mmtk_objbuf (rb_mmtk_objbuf_t) as the underlying buffer.
        return false;
      case T_MATCH:
        // We use imemo:mmtk_strbuf (rb_mmtk_strbuf_t) for its several underlying buffers.
        return false;
      case T_RATIONAL:
      case T_COMPLEX:
      case T_FLOAT:
        // There are only counters increments for these types in `obj_free`
        return false;
      case T_NIL:
      case T_FIXNUM:
      case T_TRUE:
      case T_FALSE:
        // These are non-heap value types.
      case T_MOVED:
        // Should not see this when object is just created.
      case T_NODE:
        // GC doesn't handle T_NODE.
        rb_bug("rb_mmtk_maybe_register_obj_free_candidate: unexpected data type 0x%x(%p) 0x%"PRIxVALUE,
               BUILTIN_TYPE(obj), (void*)obj, RBASIC(obj)->flags);
      default:
        rb_bug("rb_mmtk_maybe_register_obj_free_candidate: unknown data type 0x%x(%p) 0x%"PRIxVALUE,
               BUILTIN_TYPE(obj), (void*)obj, RBASIC(obj)->flags);
    }
    UNREACHABLE;
}

void
rb_mmtk_maybe_register_obj_free_candidate(VALUE obj)
{
    if (rb_mmtk_is_obj_free_candidate(obj)) {
        rb_mmtk_register_obj_free_candidate(obj);
    }
}

static void
rb_mmtk_call_obj_free_inner(VALUE obj, bool on_exit) {
    if (on_exit) {
        switch (BUILTIN_TYPE(obj)) {
          case T_DATA:
            if (!DATA_PTR(obj) || !((struct RData*)obj)->dfree) {
                RUBY_DEBUG_LOG("Skipped data without dfree: %p: %s", (void*)obj, rb_type_str(RB_BUILTIN_TYPE(obj)));
                return;
            }
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
            break;
          case T_FILE:
            if (!((struct RFile*)obj)->fptr) {
                RUBY_DEBUG_LOG("Skipped file without fptr: %p: %s", (void*)obj, rb_type_str(RB_BUILTIN_TYPE(obj)));
                return;
            }
            break;
          default:
            RUBY_DEBUG_LOG("Skipped obj-free candidate that is neither T_DATA nor T_FILE: %p: %s",
                (void*)obj, rb_type_str(RB_BUILTIN_TYPE(obj)));
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

static inline void
rb_mmtk_call_obj_free(MMTk_ObjectReference object)
{
    rb_mmtk_assert_mmtk_worker();

    VALUE obj = (VALUE)object;

    rb_mmtk_call_obj_free_inner(obj, false);
}

static void
rb_mmtk_call_obj_free_for_each_on_exit(VALUE *objects, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        VALUE obj = objects[i];
        rb_mmtk_call_obj_free_inner(obj, true);
    }
}

void
rb_mmtk_call_obj_free_on_exit(void)
{
    struct MMTk_RawVecOfObjRef registered_candidates = mmtk_get_all_obj_free_candidates();
    rb_mmtk_call_obj_free_for_each_on_exit((VALUE*)registered_candidates.ptr, registered_candidates.len);
    mmtk_free_raw_vec_of_obj_ref(registered_candidates);

    rb_ractor_t *main_ractor = GET_VM()->ractor.main_ractor;
    rb_thread_t *th = NULL;
    ccan_list_for_each(&main_ractor->threads.set, th, lt_node) {
        // Ruby caches native threads on some platforms,
        // and the rb_thread_t structs can be reused while a thread is cached.
        // Currently we destroy the mutator and the mutator_local structs when a thread exits.
        if (th->mutator != NULL) {
            struct rb_mmtk_mutator_local *local = (struct rb_mmtk_mutator_local*)th->mutator_local;
            struct rb_mmtk_values_buffer *buffer = &local->obj_free_candidates;
            rb_mmtk_call_obj_free_for_each_on_exit(buffer->objects, buffer->len);
        } else {
            RUBY_ASSERT(th->mutator_local == NULL);
        }
    }
}

bool
rb_gc_obj_free_on_exit_started(void) {
    return obj_free_on_exit_started;
}

void
rb_gc_set_obj_free_on_exit_started(void) {
    obj_free_on_exit_started = true;
}

////////////////////////////////////////////////////////////////////////////////
// Weak table processing
////////////////////////////////////////////////////////////////////////////////

struct rb_mmtk_weak_table_rebuilding_context {
    st_table *old_table;
    st_table *new_table;
    enum RbMmtkWeakTableValueKind values_kind;
    rb_mmtk_hash_on_delete_func on_delete;
    void *on_delete_arg;
};

static int
rb_mmtk_update_weak_table_migrate_each(st_data_t key, st_data_t value, st_data_t arg)
{
    struct rb_mmtk_weak_table_rebuilding_context *ctx =
        (struct rb_mmtk_weak_table_rebuilding_context*)arg;

    // Preconditions:
    // The key must be an object reference,
    RUBY_ASSERT(!SPECIAL_CONST_P((VALUE)key));
    // and the key must point to a valid object (may be dead, but must be allocated).
    RUBY_ASSERT(mmtk_is_mmtk_object((MMTk_ObjectReference)key));

    bool key_live = mmtk_is_reachable((MMTk_ObjectReference)key);
    bool keep = key_live;
    bool value_live = true;

    if (ctx->values_kind == RB_MMTK_VALUES_WEAK_REF) {
        RUBY_ASSERT(
            // The value is either a primitive value (e.g. Fixnum that represents an ID)
            SPECIAL_CONST_P((VALUE)value) ||
            // or a valid object reference (e.g. to a Bignum that represents an ID).
            // It may be dead, but must be allocated.
            mmtk_is_mmtk_object((MMTk_ObjectReference)value));
        if (!SPECIAL_CONST_P((VALUE)value)) {
            value_live = mmtk_is_reachable((MMTk_ObjectReference)value);
            keep = keep && value_live;
        }
    }

    if (keep) {
        st_data_t new_key = (st_data_t)rb_mmtk_call_object_closure((MMTk_ObjectReference)key, false);
        st_data_t new_value = ctx->values_kind == RB_MMTK_VALUES_NON_REF ?
            value :
            (st_data_t)rb_mmtk_maybe_forward((VALUE)value); // Note that value may be primitive value or objref.
        st_insert(ctx->new_table, new_key, new_value);
        RUBY_DEBUG_LOG("Forwarding key-value pair: (%p, %p) -> (%p, %p)",
            (void*)key, (void*)value, (void*)new_key, (void*)new_value);
    } else {
        // The key or the value is dead. Discard the entry.
        RUBY_DEBUG_LOG("Discarding key-value pair: (%p, %p). Key is %s, value is %s",
            (void*)key, (void*)value, key_live ? "live" : "dead", value_live ? "live" : "dead");
        if (ctx->on_delete != NULL) {
            ctx->on_delete(key, value, ctx->on_delete_arg);
        }
    }

    return ST_CONTINUE;
}

struct rb_mmtk_weak_table_updating_context {
    enum RbMmtkWeakTableValueKind values_kind;
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

    if (ctx->values_kind == RB_MMTK_VALUES_WEAK_REF && !mmtk_is_live_object((MMTk_ObjectReference)value)) {
        return ST_DELETE;
    }

    MMTk_ObjectReference new_key = mmtk_get_forwarded_object((MMTk_ObjectReference)key);
    if (new_key != NULL && new_key != (MMTk_ObjectReference)key) {
        return ST_REPLACE;
    }

    if (ctx->values_kind != RB_MMTK_VALUES_NON_REF) {
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

    if (ctx->values_kind != RB_MMTK_VALUES_NON_REF) {
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
 * If update_values is true, also discard the key-value pair if the value is dead.
 */
void
rb_mmtk_update_weak_table(st_table *table,
                          bool addr_hashed,
                          enum RbMmtkWeakTableValueKind values_kind,
                          rb_mmtk_hash_on_delete_func on_delete,
                          void *on_delete_arg)
{
    if (!table || table->num_entries == 0) return;

    // HACK: The way we update non-address-hashed tables will be unsound if we run `obj_free` in
    // parallel or before we update the weak table.  When deleting entries from st_table,
    // st_general_foreach will try to compare elements by value.  But if `obj_free` has been called
    // on dead objects, it may destroy the object (for example, freeing the underlying off-heap
    // buffer of strings), making them unable to be compared by value.  Creating another hash table
    // and replacing the existing one has a performance overhead, but is correct.  We should find a
    // more efficient way to delete dead objects from a hash table.
    addr_hashed = true;

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
            .values_kind = values_kind,
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
            .values_kind = values_kind,
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

////////////////////////////////////////////////////////////////////////////////
// String buffer implementation
////////////////////////////////////////////////////////////////////////////////

rb_mmtk_strbuf_t*
rb_mmtk_new_strbuf(size_t capa)
{
    VALUE flags = T_IMEMO | (imemo_mmtk_strbuf << FL_USHIFT);
    size_t payload_size = offsetof(rb_mmtk_strbuf_t, ary) + capa;
    if (payload_size % MMTK_MIN_OBJ_ALIGN != 0) {
        payload_size = (payload_size + MMTK_MIN_OBJ_ALIGN - 1) & ~(MMTK_MIN_OBJ_ALIGN - 1);
    }
    VALUE obj = rb_mmtk_newobj_raw(capa, flags, true, payload_size);
    return (rb_mmtk_strbuf_t*)obj;
}

char*
rb_mmtk_strbuf_to_chars(rb_mmtk_strbuf_t* strbuf)
{
    return strbuf->ary;
}

rb_mmtk_strbuf_t*
rb_mmtk_chars_to_strbuf(char* chars)
{
    return (rb_mmtk_strbuf_t*)(chars - offsetof(rb_mmtk_strbuf_t, ary));
}

rb_mmtk_strbuf_t*
rb_mmtk_strbuf_realloc(rb_mmtk_strbuf_t* old_strbuf, size_t new_capa)
{
    // Allocate a new strbuf.
    rb_mmtk_strbuf_t *new_strbuf = rb_mmtk_new_strbuf(new_capa);

    // Copy content if old_strbuf is not NULL.
    if (old_strbuf != NULL) {
        size_t old_capa = old_strbuf->capa;
        size_t copy_size = old_capa > new_capa ? new_capa : old_capa;
        memcpy(new_strbuf->ary, old_strbuf->ary, copy_size);
    }

    return new_strbuf;
}

void
rb_mmtk_scan_offsetted_strbuf_field(char** field, bool update)
{
    // If the field contains NULL, return immediately.
    char *old_field_value = *field;
    if (old_field_value == NULL) {
        return;
    }

    // Trace the actual object.
    VALUE old_ref = (VALUE)rb_mmtk_chars_to_strbuf(old_field_value);
    VALUE new_ref = rb_mmtk_maybe_forward(old_ref);

    // Update the field if needed.
    if (update && new_ref != old_ref) {
        char *new_field_value = rb_mmtk_strbuf_to_chars((rb_mmtk_strbuf_t*)new_ref);
        *field = new_field_value;
    }
}

////////////////////////////////////////////////////////////////////////////////
// Object buffer implementation
////////////////////////////////////////////////////////////////////////////////

rb_mmtk_objbuf_t*
rb_mmtk_new_objbuf(size_t capa)
{
    VALUE flags = T_IMEMO | (imemo_mmtk_objbuf << FL_USHIFT);
    size_t payload_size = offsetof(rb_mmtk_objbuf_t, ary) + capa * sizeof(VALUE);
    if (payload_size % MMTK_MIN_OBJ_ALIGN != 0) {
        payload_size = (payload_size + MMTK_MIN_OBJ_ALIGN - 1) & ~(MMTK_MIN_OBJ_ALIGN - 1);
    }
    VALUE obj = rb_mmtk_newobj_raw(capa, flags, true, payload_size);
    return (rb_mmtk_objbuf_t*)obj;
}

VALUE*
rb_mmtk_objbuf_to_elems(rb_mmtk_objbuf_t* objbuf)
{
    return objbuf->ary;
}

////////////////////////////////////////////////////////////////////////////////
// Object pinning
////////////////////////////////////////////////////////////////////////////////

// Pin an object.  Do nothing if the plan implicitly pins all objects (i.e. non-moving).
void
rb_mmtk_pin_object(VALUE obj)
{
    if (!mmtk_plan_implicitly_pinning) {
        mmtk_pin_object((MMTk_ObjectReference)obj);
    }
}

// Assert if an object is pinned.  Do nothing if the plan implicitly pins all objects (i.e. non-moving).
void
rb_mmtk_assert_is_pinned(VALUE obj)
{
    if (!mmtk_plan_implicitly_pinning) {
        RUBY_ASSERT(mmtk_is_pinned((MMTk_ObjectReference)obj));
    }
}

// Temporarily pin the buffer of an array so that it can be passed to native functions which are
// not aware of object movement.
void
rb_mmtk_pin_array_buffer(VALUE array, volatile VALUE *stack_slot)
{
    // We store the reference into the given stack slot so that the conservative stack scanner can
    // pick it up.
    if (ARY_EMBED_P(array)) {
        *stack_slot = array;
    } else {
        *stack_slot = RARRAY_EXT(array)->objbuf;
    }
}

////////////////////////////////////////////////////////////////////////////////
// Forking support
////////////////////////////////////////////////////////////////////////////////
void
rb_mmtk_shutdown_gc_threads(void)
{
    mmtk_prepare_to_fork();
}

void rb_mmtk_respawn_gc_threads(void)
{
    mmtk_after_fork(GET_THREAD());
}

////////////////////////////////////////////////////////////////////////////////
// MMTk-specific Ruby module (GC::MMTk)
////////////////////////////////////////////////////////////////////////////////

void
rb_mmtk_define_gc_mmtk_module(void)
{
    VALUE rb_mMMTk = rb_define_module_under(rb_mGC, "MMTk");
    rb_define_singleton_method(rb_mMMTk, "plan_name", rb_mmtk_plan_name, 0);
    rb_define_singleton_method(rb_mMMTk, "enabled?", rb_mmtk_enabled, 0);
    rb_define_singleton_method(rb_mMMTk, "harness_begin", rb_mmtk_harness_begin, 0);
    rb_define_singleton_method(rb_mMMTk, "harness_end", rb_mmtk_harness_end, 0);
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
    if (rb_mmtk_enabled_p()) {
        mmtk_harness_begin((MMTk_VMMutatorThread)GET_THREAD());
    } else {
        g_vanilla_timing.last_num_of_gc = rb_gc_count();
        rb_mmtk_get_vanilla_times(&g_vanilla_timing.last_vanilla_mark, &g_vanilla_timing.last_vanilla_sweep);
        g_vanilla_timing.enabled = true;
        clock_gettime(CLOCK_MONOTONIC, &g_vanilla_timing.last_enabled);
    }

    return Qnil;
}

static uint64_t elapsed_ns(struct timespec *now, struct timespec *then) {
    uint64_t diff_s = now->tv_sec - then->tv_sec;
    uint64_t elapsed = diff_s * 1000000000 + now->tv_nsec - then->tv_nsec;
    return elapsed;
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
    if (rb_mmtk_enabled_p()) {
        mmtk_harness_end((MMTk_VMMutatorThread)GET_THREAD());
    } else {
        g_vanilla_timing.enabled = false;
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        uint64_t total_time_ns = elapsed_ns(&now, &g_vanilla_timing.last_enabled);
        uint64_t gc_time_ns = g_vanilla_timing.gc_time_ns;
        uint64_t stw_time_ns = total_time_ns - gc_time_ns;

        double total_time_ms = total_time_ns / 1000000.0;
        double gc_time_ms = gc_time_ns / 1000000.0;
        double stw_time_ms = stw_time_ns / 1000000.0;

        size_t num_of_gc = rb_gc_count() - g_vanilla_timing.last_num_of_gc;

        uint64_t cur_vanilla_mark, cur_vanilla_sweep;
        rb_mmtk_get_vanilla_times(&cur_vanilla_mark, &cur_vanilla_sweep);
        uint64_t vanilla_mark = cur_vanilla_mark - g_vanilla_timing.last_vanilla_mark;
        uint64_t vanilla_sweep = cur_vanilla_sweep - g_vanilla_timing.last_vanilla_sweep;
        uint64_t vanilla_time = vanilla_mark + vanilla_sweep;

        double vanilla_time_ms = vanilla_time / 1000000.0;
        double vanilla_mark_ms = vanilla_mark / 1000000.0;
        double vanilla_sweep_ms = vanilla_sweep / 1000000.0;

        fprintf(stderr, "======== Begin vanilla GC timing report (mmtk-ruby) ========\n");
        fprintf(stderr, "%10s %18s %18s %18s %18s %18s\n", "GC", "time.other", "time.stw", "v.time.gc", "v.time.mark", "v.time.sweep");
        fprintf(stderr, "%10zu %18lf %18lf %18lf %18lf %18lf\n", num_of_gc, stw_time_ms, gc_time_ms, vanilla_time_ms, vanilla_mark_ms, vanilla_sweep_ms);
        fprintf(stderr, "Total time: %lf ms\n", total_time_ms);
        fprintf(stderr, "======== End vanilla GC timing report (mmtk-ruby) ========\n");
    }

    return Qnil;
}

////////////////////////////////////////////////////////////////////////////////
// Debugging
////////////////////////////////////////////////////////////////////////////////

bool
rb_mmtk_is_mmtk_worker(void)
{
    return rb_mmtk_gc_thread_tls != NULL;
}

bool
rb_mmtk_is_mutator(void)
{
    return ruby_native_thread_p();
}

void
rb_mmtk_assert_mmtk_worker(void)
{
    RUBY_ASSERT_MESG(rb_mmtk_is_mmtk_worker(), "The current thread is not an MMTk worker");
}

void
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

////////////////////////////////////////////////////////////////////////////////
// Vanilla GC timing
////////////////////////////////////////////////////////////////////////////////

void
rb_mmtk_gc_probe(bool enter)
{
    if (!g_vanilla_timing.enabled) {
        return;
    }

    if (g_vanilla_timing.in_alloc_slow_path) {
        return;
    }

    if (enter) {
        // Note: Vanilla GC also has timing facilities exposed with `GC.stat[:time]`.
        // But that uses `current_process_time` which uses `CLOCK_PROCESS_CPUTIME_ID`
        // while MMTk uses Rust's `std::time::Instant` which uses `CLOCK_MONOTONIC`.
        // To be fair, we reimplmenet the probing and use `CLOCK_MONOTONIC` instead.
        clock_gettime(CLOCK_MONOTONIC, &g_vanilla_timing.last_gc_start);
    } else {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        uint64_t elapsed = elapsed_ns(&now, &g_vanilla_timing.last_gc_start);
        g_vanilla_timing.gc_time_ns += elapsed;
    }
}

// Use this to exclude the allocation slow path from the STW time.
void
rb_mmtk_gc_probe_slowpath(bool enter)
{
    g_vanilla_timing.in_alloc_slow_path = enter;
}

////////////////////////////////////////////////////////////////////////////////
// xmalloc accounting
////////////////////////////////////////////////////////////////////////////////

// copied from gc.c
static inline void
atomic_sub_nounderflow(size_t *var, size_t sub)
{
    if (sub == 0) return;

    while (1) {
        size_t val = *var;
        if (val < sub) sub = val;
        if (ATOMIC_SIZE_CAS(*var, val, val-sub) == val) break;
    }
}

// Record the increment of xmalloc-ed memory and potentially trigger a GC.
void
rb_mmtk_xmalloc_increase_body(size_t new_size, size_t old_size)
{
    if (new_size > old_size) {
        ATOMIC_SIZE_ADD(g_xmalloc_accounting.malloc_total, new_size - old_size);
    }
    else {
        atomic_sub_nounderflow(&g_xmalloc_accounting.malloc_total, old_size - new_size);
    }
}

static size_t
rb_mmtk_vm_live_bytes(void)
{
    return g_xmalloc_accounting.malloc_total;
}

////////////////////////////////////////////////////////////////////////////////
// MMTk-Ruby Upcalls
////////////////////////////////////////////////////////////////////////////////

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

    rb_mmtk_set_during_gc(true);
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

    rb_mmtk_set_during_gc(false);

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

    rb_ractor_t *main_ractor = GET_VM()->ractor.main_ractor;
    rb_thread_t *th = NULL;
    ccan_list_for_each(&main_ractor->threads.set, th, lt_node) {
        // Ruby caches native threads on some platforms,
        // and the rb_thread_t structs can be reused while a thread is cached.
        // Currently we destroy the mutator and the mutator_local structs when a thread exits.
        if (th->mutator != NULL) {
            rb_mmtk_flush_mutator_local_buffers(th);
        } else {
            RUBY_ASSERT(th->mutator_local == NULL);
        }
    }

    rb_thread_t *cur_th = GET_THREAD();
    RB_VM_SAVE_MACHINE_CONTEXT(cur_th);
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
rb_mmtk_get_mutators(void (*visit_mutator)(MMTk_Mutator *mutator, void *data), void *data)
{
    rb_mmtk_assert_mmtk_worker();
    rb_mmtk_panic_if_multiple_ractor(__FUNCTION__);

    rb_ractor_t *main_ractor = GET_VM()->ractor.main_ractor;

    rb_thread_t *th = NULL;
    ccan_list_for_each(&main_ractor->threads.set, th, lt_node) {
        // Ruby caches native threads on some platforms,
        // and the rb_thread_t structs can be reused while a thread is cached.
        // Currently we destroy the mutator and the mutator_local structs when a thread exits.
        if (th->mutator != NULL) {
            visit_mutator(th->mutator, data);
        } else {
            RUBY_ASSERT(th->mutator_local == NULL);
        }
    }
}

static void
rb_mmtk_scan_vm_specific_roots(void)
{
    rb_mmtk_assert_mmtk_worker();

    RUBY_DEBUG_LOG("Scanning VM-specific roots...");

    rb_mmtk_mark_roots();
}

static void
rb_mmtk_scan_roots_in_mutator_thread(MMTk_VMMutatorThread mutator, MMTk_VMWorkerThread worker)
{
    rb_mmtk_assert_mmtk_worker();

    rb_thread_t *thread = mutator;
    rb_execution_context_t *ec = thread->ec;

    RUBY_DEBUG_LOG("[Worker: %p] We will scan thread root for thread: %p, ec: %p", worker, thread, ec);

    rb_execution_context_mark(ec);

    RUBY_DEBUG_LOG("[Worker: %p] Finished scanning thread for thread: %p, ec: %p", worker, thread, ec);
}

static void*
rb_mmtk_get_original_givtbl(MMTk_ObjectReference object) {
    VALUE obj = (VALUE)object;

    RUBY_ASSERT(FL_TEST(obj, FL_EXIVAR));
    struct gen_ivtbl *ivtbl;
    if (rb_gen_ivtbl_get(obj, 0, &ivtbl)) {
        return ivtbl;
    } else {
        return NULL;
    }
}

static void
rb_mmtk_move_givtbl(MMTk_ObjectReference old_objref, MMTk_ObjectReference new_objref) {
    rb_mv_generic_ivar((VALUE)old_objref, (VALUE)new_objref);
}

void rb_mmtk_cleanup_generic_iv_tbl(void); // Defined in variable.c
void rb_mmtk_update_frozen_strings_table(void); // Defined in gc.c
void rb_mmtk_update_finalizer_table(void); // Defined in gc.c
void rb_mmtk_update_obj_id_tables(void); // Defined in gc.c
void rb_mmtk_update_global_symbols_table(void); // Defined in gc.c
void rb_mmtk_update_overloaded_cme_table(void); // Defined in gc.c
void rb_mmtk_update_ci_table(void); // Defined in gc.c

MMTk_RubyUpcalls ruby_upcalls = {
    rb_mmtk_init_gc_worker_thread,
    rb_mmtk_get_gc_thread_tls,
    rb_mmtk_is_mutator,
    rb_mmtk_stop_the_world,
    rb_mmtk_resume_mutators,
    rb_mmtk_block_for_gc,
    rb_mmtk_number_of_mutators,
    rb_mmtk_get_mutators,
    rb_mmtk_scan_vm_specific_roots,
    rb_mmtk_scan_roots_in_mutator_thread,
    rb_mmtk_scan_object_ruby_style,
    rb_mmtk_call_gc_mark_children,
    rb_mmtk_call_obj_free,
    rb_mmtk_cleanup_generic_iv_tbl,
    rb_mmtk_update_frozen_strings_table,
    rb_mmtk_update_finalizer_table,
    rb_mmtk_update_obj_id_tables,
    rb_mmtk_update_global_symbols_table,
    rb_mmtk_update_overloaded_cme_table,
    rb_mmtk_update_ci_table,
    rb_mmtk_get_original_givtbl,
    rb_mmtk_move_givtbl,
    rb_mmtk_vm_live_bytes,
};

////////////////////////////////////////////////////////////////////////////////
// Commandline options parsing
////////////////////////////////////////////////////////////////////////////////

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
                        mmtk_max_heap_size = mmtk_pre_max_heap_size;
                    }

                    env_args += length;
                }
            }
        }
    }

    if (mmtk_pre_arg_plan) {
        mmtk_chosen_plan = mmtk_pre_arg_plan;
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

#endif // USE_MMTK
