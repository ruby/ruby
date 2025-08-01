/**********************************************************************

  gc.c -

  $Author$
  created at: Tue Oct  5 09:44:46 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#define rb_data_object_alloc rb_data_object_alloc
#define rb_data_typed_object_alloc rb_data_typed_object_alloc

#include "ruby/internal/config.h"
#ifdef _WIN32
# include "ruby/ruby.h"
#endif

#if defined(__wasm__) && !defined(__EMSCRIPTEN__)
# include "wasm/setjmp.h"
# include "wasm/machine.h"
#else
# include <setjmp.h>
#endif
#include <stdarg.h>
#include <stdio.h>

/* MALLOC_HEADERS_BEGIN */
#ifndef HAVE_MALLOC_USABLE_SIZE
# ifdef _WIN32
#  define HAVE_MALLOC_USABLE_SIZE
#  define malloc_usable_size(a) _msize(a)
# elif defined HAVE_MALLOC_SIZE
#  define HAVE_MALLOC_USABLE_SIZE
#  define malloc_usable_size(a) malloc_size(a)
# endif
#endif

#ifdef HAVE_MALLOC_USABLE_SIZE
# ifdef RUBY_ALTERNATIVE_MALLOC_HEADER
/* Alternative malloc header is included in ruby/missing.h */
# elif defined(HAVE_MALLOC_H)
#  include <malloc.h>
# elif defined(HAVE_MALLOC_NP_H)
#  include <malloc_np.h>
# elif defined(HAVE_MALLOC_MALLOC_H)
#  include <malloc/malloc.h>
# endif
#endif

/* MALLOC_HEADERS_END */

#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#endif

#ifdef HAVE_SYS_RESOURCE_H
# include <sys/resource.h>
#endif

#if defined _WIN32 || defined __CYGWIN__
# include <windows.h>
#elif defined(HAVE_POSIX_MEMALIGN)
#elif defined(HAVE_MEMALIGN)
# include <malloc.h>
#endif

#include <sys/types.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

/* For ruby_annotate_mmap */
#ifdef HAVE_SYS_PRCTL_H
#include <sys/prctl.h>
#endif

#undef LIST_HEAD /* ccan/list conflicts with BSD-origin sys/queue.h. */

#include "constant.h"
#include "darray.h"
#include "debug_counter.h"
#include "eval_intern.h"
#include "gc/gc.h"
#include "id_table.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/compile.h"
#include "internal/complex.h"
#include "internal/concurrent_set.h"
#include "internal/cont.h"
#include "internal/error.h"
#include "internal/eval.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/imemo.h"
#include "internal/io.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/rational.h"
#include "internal/sanitizers.h"
#include "internal/struct.h"
#include "internal/symbol.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "internal/warnings.h"
#include "probes.h"
#include "regint.h"
#include "ruby/debug.h"
#include "ruby/io.h"
#include "ruby/re.h"
#include "ruby/st.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "ruby/vm.h"
#include "ruby_assert.h"
#include "ruby_atomic.h"
#include "symbol.h"
#include "variable.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "vm_callinfo.h"
#include "ractor_core.h"
#include "yjit.h"

#include "builtin.h"
#include "shape.h"

unsigned int
rb_gc_vm_lock(const char *file, int line)
{
    unsigned int lev = 0;
    rb_vm_lock_enter(&lev, file, line);
    return lev;
}

void
rb_gc_vm_unlock(unsigned int lev, const char *file, int line)
{
    rb_vm_lock_leave(&lev, file, line);
}

unsigned int
rb_gc_cr_lock(const char *file, int line)
{
    unsigned int lev;
    rb_vm_lock_enter_cr(GET_RACTOR(), &lev, file, line);
    return lev;
}

void
rb_gc_cr_unlock(unsigned int lev, const char *file, int line)
{
    rb_vm_lock_leave_cr(GET_RACTOR(), &lev, file, line);
}

unsigned int
rb_gc_vm_lock_no_barrier(const char *file, int line)
{
    unsigned int lev = 0;
    rb_vm_lock_enter_nb(&lev, file, line);
    return lev;
}

void
rb_gc_vm_unlock_no_barrier(unsigned int lev, const char *file, int line)
{
    rb_vm_lock_leave_nb(&lev, file, line);
}

void
rb_gc_vm_barrier(void)
{
    rb_vm_barrier();
}

#if USE_MODULAR_GC
void *
rb_gc_get_ractor_newobj_cache(void)
{
    return GET_RACTOR()->newobj_cache;
}

void
rb_gc_initialize_vm_context(struct rb_gc_vm_context *context)
{
    rb_native_mutex_initialize(&context->lock);
    context->ec = GET_EC();
}

void
rb_gc_worker_thread_set_vm_context(struct rb_gc_vm_context *context)
{
    rb_native_mutex_lock(&context->lock);

    GC_ASSERT(rb_current_execution_context(false) == NULL);

#ifdef RB_THREAD_LOCAL_SPECIFIER
    rb_current_ec_set(context->ec);
#else
    native_tls_set(ruby_current_ec_key, context->ec);
#endif
}

void
rb_gc_worker_thread_unset_vm_context(struct rb_gc_vm_context *context)
{
    rb_native_mutex_unlock(&context->lock);

    GC_ASSERT(rb_current_execution_context(true) == context->ec);

#ifdef RB_THREAD_LOCAL_SPECIFIER
    rb_current_ec_set(NULL);
#else
    native_tls_set(ruby_current_ec_key, NULL);
#endif
}
#endif

bool
rb_gc_event_hook_required_p(rb_event_flag_t event)
{
    return ruby_vm_event_flags & event;
}

void
rb_gc_event_hook(VALUE obj, rb_event_flag_t event)
{
    if (LIKELY(!rb_gc_event_hook_required_p(event))) return;

    rb_execution_context_t *ec = GET_EC();
    if (!ec->cfp) return;

    EXEC_EVENT_HOOK(ec, event, ec->cfp->self, 0, 0, 0, obj);
}

void *
rb_gc_get_objspace(void)
{
    return GET_VM()->gc.objspace;
}


void
rb_gc_ractor_newobj_cache_foreach(void (*func)(void *cache, void *data), void *data)
{
    rb_ractor_t *r = NULL;
    if (RB_LIKELY(ruby_single_main_ractor)) {
        GC_ASSERT(
            ccan_list_empty(&GET_VM()->ractor.set) ||
                (ccan_list_top(&GET_VM()->ractor.set, rb_ractor_t, vmlr_node) == ruby_single_main_ractor &&
                    ccan_list_tail(&GET_VM()->ractor.set, rb_ractor_t, vmlr_node) == ruby_single_main_ractor)
        );

        func(ruby_single_main_ractor->newobj_cache, data);
    }
    else {
        ccan_list_for_each(&GET_VM()->ractor.set, r, vmlr_node) {
            func(r->newobj_cache, data);
        }
    }
}

void
rb_gc_run_obj_finalizer(VALUE objid, long count, VALUE (*callback)(long i, void *data), void *data)
{
    volatile struct {
        VALUE errinfo;
        VALUE final;
        rb_control_frame_t *cfp;
        VALUE *sp;
        long finished;
    } saved;

    rb_execution_context_t * volatile ec = GET_EC();
#define RESTORE_FINALIZER() (\
        ec->cfp = saved.cfp, \
        ec->cfp->sp = saved.sp, \
        ec->errinfo = saved.errinfo)

    saved.errinfo = ec->errinfo;
    saved.cfp = ec->cfp;
    saved.sp = ec->cfp->sp;
    saved.finished = 0;
    saved.final = Qundef;

    rb_ractor_ignore_belonging(true);
    EC_PUSH_TAG(ec);
    enum ruby_tag_type state = EC_EXEC_TAG();
    if (state != TAG_NONE) {
        ++saved.finished;	/* skip failed finalizer */

        VALUE failed_final = saved.final;
        saved.final = Qundef;
        if (!UNDEF_P(failed_final) && !NIL_P(ruby_verbose)) {
            rb_warn("Exception in finalizer %+"PRIsVALUE, failed_final);
            rb_ec_error_print(ec, ec->errinfo);
        }
    }

    for (long i = saved.finished; RESTORE_FINALIZER(), i < count; saved.finished = ++i) {
        saved.final = callback(i, data);
        rb_check_funcall(saved.final, idCall, 1, &objid);
    }
    EC_POP_TAG();
    rb_ractor_ignore_belonging(false);
#undef RESTORE_FINALIZER
}

void
rb_gc_set_pending_interrupt(void)
{
    rb_execution_context_t *ec = GET_EC();
    ec->interrupt_mask |= PENDING_INTERRUPT_MASK;
}

void
rb_gc_unset_pending_interrupt(void)
{
    rb_execution_context_t *ec = GET_EC();
    ec->interrupt_mask &= ~PENDING_INTERRUPT_MASK;
}

bool
rb_gc_multi_ractor_p(void)
{
    return rb_multi_ractor_p();
}

bool rb_obj_is_main_ractor(VALUE gv);

bool
rb_gc_shutdown_call_finalizer_p(VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
      case T_DATA:
        if (!ruby_free_at_exit_p() && (!DATA_PTR(obj) || !RDATA(obj)->dfree)) return false;
        if (rb_obj_is_thread(obj)) return false;
        if (rb_obj_is_mutex(obj)) return false;
        if (rb_obj_is_fiber(obj)) return false;
        if (rb_obj_is_main_ractor(obj)) return false;
        if (rb_obj_is_fstring_table(obj)) return false;
        if (rb_obj_is_symbol_table(obj)) return false;

        return true;

      case T_FILE:
        return true;

      case T_SYMBOL:
        return true;

      case T_NONE:
        return false;

      default:
        return ruby_free_at_exit_p();
    }
}

uint32_t
rb_gc_get_shape(VALUE obj)
{
    return (uint32_t)rb_obj_shape_id(obj);
}

void
rb_gc_set_shape(VALUE obj, uint32_t shape_id)
{
    rb_obj_set_shape_id(obj, (uint32_t)shape_id);
}

uint32_t
rb_gc_rebuild_shape(VALUE obj, size_t heap_id)
{
    RUBY_ASSERT(RB_TYPE_P(obj, T_OBJECT));

    return (uint32_t)rb_shape_transition_heap(obj, heap_id);
}

void rb_vm_update_references(void *ptr);

#define rb_setjmp(env) RUBY_SETJMP(env)
#define rb_jmp_buf rb_jmpbuf_t
#undef rb_data_object_wrap

#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif

#define unless_objspace(objspace) \
    void *objspace; \
    rb_vm_t *unless_objspace_vm = GET_VM(); \
    if (unless_objspace_vm) objspace = unless_objspace_vm->gc.objspace; \
    else /* return; or objspace will be warned uninitialized */

#define RMOVED(obj) ((struct RMoved *)(obj))

#define TYPED_UPDATE_IF_MOVED(_objspace, _type, _thing) do { \
    if (rb_gc_impl_object_moved_p((_objspace), (VALUE)(_thing))) {    \
        *(_type *)&(_thing) = (_type)gc_location_internal(_objspace, (VALUE)_thing); \
    } \
} while (0)

#define UPDATE_IF_MOVED(_objspace, _thing) TYPED_UPDATE_IF_MOVED(_objspace, VALUE, _thing)

#if RUBY_MARK_FREE_DEBUG
int ruby_gc_debug_indent = 0;
#endif

#ifndef RGENGC_OBJ_INFO
# define RGENGC_OBJ_INFO RGENGC_CHECK_MODE
#endif

#ifndef CALC_EXACT_MALLOC_SIZE
# define CALC_EXACT_MALLOC_SIZE 0
#endif

VALUE rb_mGC;

static size_t malloc_offset = 0;
#if defined(HAVE_MALLOC_USABLE_SIZE)
static size_t
gc_compute_malloc_offset(void)
{
    // Different allocators use different metadata storage strategies which result in different
    // ideal sizes.
    // For instance malloc(64) will waste 8B with glibc, but waste 0B with jemalloc.
    // But malloc(56) will waste 0B with glibc, but waste 8B with jemalloc.
    // So we try allocating 64, 56 and 48 bytes and select the first offset that doesn't
    // waste memory.
    // This was tested on Linux with glibc 2.35 and jemalloc 5, and for both it result in
    // no wasted memory.
    size_t offset = 0;
    for (offset = 0; offset <= 16; offset += 8) {
        size_t allocated = (64 - offset);
        void *test_ptr = malloc(allocated);
        size_t wasted = malloc_usable_size(test_ptr) - allocated;
        free(test_ptr);

        if (wasted == 0) {
            return offset;
        }
    }
    return 0;
}
#else
static size_t
gc_compute_malloc_offset(void)
{
    // If we don't have malloc_usable_size, we use powers of 2.
    return 0;
}
#endif

size_t
rb_malloc_grow_capa(size_t current, size_t type_size)
{
    size_t current_capacity = current;
    if (current_capacity < 4) {
        current_capacity = 4;
    }
    current_capacity *= type_size;

    // We double the current capacity.
    size_t new_capacity = (current_capacity * 2);

    // And round up to the next power of 2 if it's not already one.
    if (rb_popcount64(new_capacity) != 1) {
        new_capacity = (size_t)(1 << (64 - nlz_int64(new_capacity)));
    }

    new_capacity -= malloc_offset;
    new_capacity /= type_size;
    if (current > new_capacity) {
        rb_bug("rb_malloc_grow_capa: current_capacity=%zu, new_capacity=%zu, malloc_offset=%zu", current, new_capacity, malloc_offset);
    }
    RUBY_ASSERT(new_capacity > current);
    return new_capacity;
}

static inline struct rbimpl_size_mul_overflow_tag
size_mul_add_overflow(size_t x, size_t y, size_t z) /* x * y + z */
{
    struct rbimpl_size_mul_overflow_tag t = rbimpl_size_mul_overflow(x, y);
    struct rbimpl_size_mul_overflow_tag u = rbimpl_size_add_overflow(t.right, z);
    return (struct rbimpl_size_mul_overflow_tag) { t.left || u.left, u.right };
}

static inline struct rbimpl_size_mul_overflow_tag
size_mul_add_mul_overflow(size_t x, size_t y, size_t z, size_t w) /* x * y + z * w */
{
    struct rbimpl_size_mul_overflow_tag t = rbimpl_size_mul_overflow(x, y);
    struct rbimpl_size_mul_overflow_tag u = rbimpl_size_mul_overflow(z, w);
    struct rbimpl_size_mul_overflow_tag v = rbimpl_size_add_overflow(t.right, u.right);
    return (struct rbimpl_size_mul_overflow_tag) { t.left || u.left || v.left, v.right };
}

PRINTF_ARGS(NORETURN(static void gc_raise(VALUE, const char*, ...)), 2, 3);

static inline size_t
size_mul_or_raise(size_t x, size_t y, VALUE exc)
{
    struct rbimpl_size_mul_overflow_tag t = rbimpl_size_mul_overflow(x, y);
    if (LIKELY(!t.left)) {
        return t.right;
    }
    else if (rb_during_gc()) {
        rb_memerror();          /* or...? */
    }
    else {
        gc_raise(
            exc,
            "integer overflow: %"PRIuSIZE
            " * %"PRIuSIZE
            " > %"PRIuSIZE,
            x, y, (size_t)SIZE_MAX);
    }
}

size_t
rb_size_mul_or_raise(size_t x, size_t y, VALUE exc)
{
    return size_mul_or_raise(x, y, exc);
}

static inline size_t
size_mul_add_or_raise(size_t x, size_t y, size_t z, VALUE exc)
{
    struct rbimpl_size_mul_overflow_tag t = size_mul_add_overflow(x, y, z);
    if (LIKELY(!t.left)) {
        return t.right;
    }
    else if (rb_during_gc()) {
        rb_memerror();          /* or...? */
    }
    else {
        gc_raise(
            exc,
            "integer overflow: %"PRIuSIZE
            " * %"PRIuSIZE
            " + %"PRIuSIZE
            " > %"PRIuSIZE,
            x, y, z, (size_t)SIZE_MAX);
    }
}

size_t
rb_size_mul_add_or_raise(size_t x, size_t y, size_t z, VALUE exc)
{
    return size_mul_add_or_raise(x, y, z, exc);
}

static inline size_t
size_mul_add_mul_or_raise(size_t x, size_t y, size_t z, size_t w, VALUE exc)
{
    struct rbimpl_size_mul_overflow_tag t = size_mul_add_mul_overflow(x, y, z, w);
    if (LIKELY(!t.left)) {
        return t.right;
    }
    else if (rb_during_gc()) {
        rb_memerror();          /* or...? */
    }
    else {
        gc_raise(
            exc,
            "integer overflow: %"PRIdSIZE
            " * %"PRIdSIZE
            " + %"PRIdSIZE
            " * %"PRIdSIZE
            " > %"PRIdSIZE,
            x, y, z, w, (size_t)SIZE_MAX);
    }
}

#if defined(HAVE_RB_GC_GUARDED_PTR_VAL) && HAVE_RB_GC_GUARDED_PTR_VAL
/* trick the compiler into thinking a external signal handler uses this */
volatile VALUE rb_gc_guarded_val;
volatile VALUE *
rb_gc_guarded_ptr_val(volatile VALUE *ptr, VALUE val)
{
    rb_gc_guarded_val = val;

    return ptr;
}
#endif

static const char *obj_type_name(VALUE obj);
#include "gc/default/default.c"

#if USE_MODULAR_GC && !defined(HAVE_DLOPEN)
# error "Modular GC requires dlopen"
#elif USE_MODULAR_GC
#include <dlfcn.h>

typedef struct gc_function_map {
    // Bootup
    void *(*objspace_alloc)(void);
    void (*objspace_init)(void *objspace_ptr);
    void *(*ractor_cache_alloc)(void *objspace_ptr, void *ractor);
    void (*set_params)(void *objspace_ptr);
    void (*init)(void);
    size_t *(*heap_sizes)(void *objspace_ptr);
    // Shutdown
    void (*shutdown_free_objects)(void *objspace_ptr);
    void (*objspace_free)(void *objspace_ptr);
    void (*ractor_cache_free)(void *objspace_ptr, void *cache);
    // GC
    void (*start)(void *objspace_ptr, bool full_mark, bool immediate_mark, bool immediate_sweep, bool compact);
    bool (*during_gc_p)(void *objspace_ptr);
    void (*prepare_heap)(void *objspace_ptr);
    void (*gc_enable)(void *objspace_ptr);
    void (*gc_disable)(void *objspace_ptr, bool finish_current_gc);
    bool (*gc_enabled_p)(void *objspace_ptr);
    VALUE (*config_get)(void *objpace_ptr);
    void (*config_set)(void *objspace_ptr, VALUE hash);
    void (*stress_set)(void *objspace_ptr, VALUE flag);
    VALUE (*stress_get)(void *objspace_ptr);
    // Object allocation
    VALUE (*new_obj)(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t alloc_size);
    size_t (*obj_slot_size)(VALUE obj);
    size_t (*heap_id_for_size)(void *objspace_ptr, size_t size);
    bool (*size_allocatable_p)(size_t size);
    // Malloc
    void *(*malloc)(void *objspace_ptr, size_t size);
    void *(*calloc)(void *objspace_ptr, size_t size);
    void *(*realloc)(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size);
    void (*free)(void *objspace_ptr, void *ptr, size_t old_size);
    void (*adjust_memory_usage)(void *objspace_ptr, ssize_t diff);
    // Marking
    void (*mark)(void *objspace_ptr, VALUE obj);
    void (*mark_and_move)(void *objspace_ptr, VALUE *ptr);
    void (*mark_and_pin)(void *objspace_ptr, VALUE obj);
    void (*mark_maybe)(void *objspace_ptr, VALUE obj);
    void (*mark_weak)(void *objspace_ptr, VALUE *ptr);
    void (*remove_weak)(void *objspace_ptr, VALUE parent_obj, VALUE *ptr);
    // Compaction
    bool (*object_moved_p)(void *objspace_ptr, VALUE obj);
    VALUE (*location)(void *objspace_ptr, VALUE value);
    // Write barriers
    void (*writebarrier)(void *objspace_ptr, VALUE a, VALUE b);
    void (*writebarrier_unprotect)(void *objspace_ptr, VALUE obj);
    void (*writebarrier_remember)(void *objspace_ptr, VALUE obj);
    // Heap walking
    void (*each_objects)(void *objspace_ptr, int (*callback)(void *, void *, size_t, void *), void *data);
    void (*each_object)(void *objspace_ptr, void (*func)(VALUE obj, void *data), void *data);
    // Finalizers
    void (*make_zombie)(void *objspace_ptr, VALUE obj, void (*dfree)(void *), void *data);
    VALUE (*define_finalizer)(void *objspace_ptr, VALUE obj, VALUE block);
    void (*undefine_finalizer)(void *objspace_ptr, VALUE obj);
    void (*copy_finalizer)(void *objspace_ptr, VALUE dest, VALUE obj);
    void (*shutdown_call_finalizer)(void *objspace_ptr);
    // Forking
    void (*before_fork)(void *objspace_ptr);
    void (*after_fork)(void *objspace_ptr, rb_pid_t pid);
    // Statistics
    void (*set_measure_total_time)(void *objspace_ptr, VALUE flag);
    bool (*get_measure_total_time)(void *objspace_ptr);
    unsigned long long (*get_total_time)(void *objspace_ptr);
    size_t (*gc_count)(void *objspace_ptr);
    VALUE (*latest_gc_info)(void *objspace_ptr, VALUE key);
    VALUE (*stat)(void *objspace_ptr, VALUE hash_or_sym);
    VALUE (*stat_heap)(void *objspace_ptr, VALUE heap_name, VALUE hash_or_sym);
    const char *(*active_gc_name)(void);
    // Miscellaneous
    struct rb_gc_object_metadata_entry *(*object_metadata)(void *objspace_ptr, VALUE obj);
    bool (*pointer_to_heap_p)(void *objspace_ptr, const void *ptr);
    bool (*garbage_object_p)(void *objspace_ptr, VALUE obj);
    void (*set_event_hook)(void *objspace_ptr, const rb_event_flag_t event);
    void (*copy_attributes)(void *objspace_ptr, VALUE dest, VALUE obj);

    bool modular_gc_loaded_p;
} rb_gc_function_map_t;

static rb_gc_function_map_t rb_gc_functions;

# define RUBY_GC_LIBRARY "RUBY_GC_LIBRARY"
# define MODULAR_GC_DIR STRINGIZE(modular_gc_dir)

static void
ruby_modular_gc_init(void)
{
    // Assert that the directory path ends with a /
    RUBY_ASSERT_ALWAYS(MODULAR_GC_DIR[sizeof(MODULAR_GC_DIR) - 2] == '/');

    const char *gc_so_file = getenv(RUBY_GC_LIBRARY);

    rb_gc_function_map_t gc_functions = { 0 };

    char *gc_so_path = NULL;
    void *handle = NULL;
    if (gc_so_file) {
        /* Check to make sure that gc_so_file matches /[\w-_]+/ so that it does
         * not load a shared object outside of the directory. */
        for (size_t i = 0; i < strlen(gc_so_file); i++) {
            char c = gc_so_file[i];
            if (isalnum(c)) continue;
            switch (c) {
              case '-':
              case '_':
                break;
              default:
                fprintf(stderr, "Only alphanumeric, dash, and underscore is allowed in "RUBY_GC_LIBRARY"\n");
                exit(1);
            }
        }

        size_t gc_so_path_size = strlen(MODULAR_GC_DIR "librubygc." DLEXT) + strlen(gc_so_file) + 1;
#ifdef LOAD_RELATIVE
        Dl_info dli;
        size_t prefix_len = 0;
        if (dladdr((void *)(uintptr_t)ruby_modular_gc_init, &dli)) {
            const char *base = strrchr(dli.dli_fname, '/');
            if (base) {
                size_t tail = 0;
# define end_with_p(lit) \
                (prefix_len >= (tail = rb_strlen_lit(lit)) && \
                 memcmp(base - tail, lit, tail) == 0)

                prefix_len = base - dli.dli_fname;
                if (end_with_p("/bin") || end_with_p("/lib")) {
                    prefix_len -= tail;
                }
                prefix_len += MODULAR_GC_DIR[0] != '/';
                gc_so_path_size += prefix_len;
            }
        }
#endif
        gc_so_path = alloca(gc_so_path_size);
        {
            size_t gc_so_path_idx = 0;
#define GC_SO_PATH_APPEND(str) do { \
    gc_so_path_idx += strlcpy(gc_so_path + gc_so_path_idx, str, gc_so_path_size - gc_so_path_idx); \
} while (0)
#ifdef LOAD_RELATIVE
            if (prefix_len > 0) {
                memcpy(gc_so_path, dli.dli_fname, prefix_len);
                gc_so_path_idx = prefix_len;
            }
#endif
            GC_SO_PATH_APPEND(MODULAR_GC_DIR "librubygc.");
            GC_SO_PATH_APPEND(gc_so_file);
            GC_SO_PATH_APPEND(DLEXT);
            GC_ASSERT(gc_so_path_idx == gc_so_path_size - 1);
#undef GC_SO_PATH_APPEND
        }

        handle = dlopen(gc_so_path, RTLD_LAZY | RTLD_GLOBAL);
        if (!handle) {
            fprintf(stderr, "ruby_modular_gc_init: Shared library %s cannot be opened: %s\n", gc_so_path, dlerror());
            exit(1);
        }

        gc_functions.modular_gc_loaded_p = true;
    }

# define load_modular_gc_func(name) do { \
    if (handle) { \
        const char *func_name = "rb_gc_impl_" #name; \
        gc_functions.name = dlsym(handle, func_name); \
        if (!gc_functions.name) { \
            fprintf(stderr, "ruby_modular_gc_init: %s function not exported by library %s\n", func_name, gc_so_path); \
            exit(1); \
        } \
    } \
    else { \
        gc_functions.name = rb_gc_impl_##name; \
    } \
} while (0)

    // Bootup
    load_modular_gc_func(objspace_alloc);
    load_modular_gc_func(objspace_init);
    load_modular_gc_func(ractor_cache_alloc);
    load_modular_gc_func(set_params);
    load_modular_gc_func(init);
    load_modular_gc_func(heap_sizes);
    // Shutdown
    load_modular_gc_func(shutdown_free_objects);
    load_modular_gc_func(objspace_free);
    load_modular_gc_func(ractor_cache_free);
    // GC
    load_modular_gc_func(start);
    load_modular_gc_func(during_gc_p);
    load_modular_gc_func(prepare_heap);
    load_modular_gc_func(gc_enable);
    load_modular_gc_func(gc_disable);
    load_modular_gc_func(gc_enabled_p);
    load_modular_gc_func(config_set);
    load_modular_gc_func(config_get);
    load_modular_gc_func(stress_set);
    load_modular_gc_func(stress_get);
    // Object allocation
    load_modular_gc_func(new_obj);
    load_modular_gc_func(obj_slot_size);
    load_modular_gc_func(heap_id_for_size);
    load_modular_gc_func(size_allocatable_p);
    // Malloc
    load_modular_gc_func(malloc);
    load_modular_gc_func(calloc);
    load_modular_gc_func(realloc);
    load_modular_gc_func(free);
    load_modular_gc_func(adjust_memory_usage);
    // Marking
    load_modular_gc_func(mark);
    load_modular_gc_func(mark_and_move);
    load_modular_gc_func(mark_and_pin);
    load_modular_gc_func(mark_maybe);
    load_modular_gc_func(mark_weak);
    load_modular_gc_func(remove_weak);
    // Compaction
    load_modular_gc_func(object_moved_p);
    load_modular_gc_func(location);
    // Write barriers
    load_modular_gc_func(writebarrier);
    load_modular_gc_func(writebarrier_unprotect);
    load_modular_gc_func(writebarrier_remember);
    // Heap walking
    load_modular_gc_func(each_objects);
    load_modular_gc_func(each_object);
    // Finalizers
    load_modular_gc_func(make_zombie);
    load_modular_gc_func(define_finalizer);
    load_modular_gc_func(undefine_finalizer);
    load_modular_gc_func(copy_finalizer);
    load_modular_gc_func(shutdown_call_finalizer);
    // Forking
    load_modular_gc_func(before_fork);
    load_modular_gc_func(after_fork);
    // Statistics
    load_modular_gc_func(set_measure_total_time);
    load_modular_gc_func(get_measure_total_time);
    load_modular_gc_func(get_total_time);
    load_modular_gc_func(gc_count);
    load_modular_gc_func(latest_gc_info);
    load_modular_gc_func(stat);
    load_modular_gc_func(stat_heap);
    load_modular_gc_func(active_gc_name);
    // Miscellaneous
    load_modular_gc_func(object_metadata);
    load_modular_gc_func(pointer_to_heap_p);
    load_modular_gc_func(garbage_object_p);
    load_modular_gc_func(set_event_hook);
    load_modular_gc_func(copy_attributes);

# undef load_modular_gc_func

    rb_gc_functions = gc_functions;
}

// Bootup
# define rb_gc_impl_objspace_alloc rb_gc_functions.objspace_alloc
# define rb_gc_impl_objspace_init rb_gc_functions.objspace_init
# define rb_gc_impl_ractor_cache_alloc rb_gc_functions.ractor_cache_alloc
# define rb_gc_impl_set_params rb_gc_functions.set_params
# define rb_gc_impl_init rb_gc_functions.init
# define rb_gc_impl_heap_sizes rb_gc_functions.heap_sizes
// Shutdown
# define rb_gc_impl_shutdown_free_objects rb_gc_functions.shutdown_free_objects
# define rb_gc_impl_objspace_free rb_gc_functions.objspace_free
# define rb_gc_impl_ractor_cache_free rb_gc_functions.ractor_cache_free
// GC
# define rb_gc_impl_start rb_gc_functions.start
# define rb_gc_impl_during_gc_p rb_gc_functions.during_gc_p
# define rb_gc_impl_prepare_heap rb_gc_functions.prepare_heap
# define rb_gc_impl_gc_enable rb_gc_functions.gc_enable
# define rb_gc_impl_gc_disable rb_gc_functions.gc_disable
# define rb_gc_impl_gc_enabled_p rb_gc_functions.gc_enabled_p
# define rb_gc_impl_config_get rb_gc_functions.config_get
# define rb_gc_impl_config_set rb_gc_functions.config_set
# define rb_gc_impl_stress_set rb_gc_functions.stress_set
# define rb_gc_impl_stress_get rb_gc_functions.stress_get
// Object allocation
# define rb_gc_impl_new_obj rb_gc_functions.new_obj
# define rb_gc_impl_obj_slot_size rb_gc_functions.obj_slot_size
# define rb_gc_impl_heap_id_for_size rb_gc_functions.heap_id_for_size
# define rb_gc_impl_size_allocatable_p rb_gc_functions.size_allocatable_p
// Malloc
# define rb_gc_impl_malloc rb_gc_functions.malloc
# define rb_gc_impl_calloc rb_gc_functions.calloc
# define rb_gc_impl_realloc rb_gc_functions.realloc
# define rb_gc_impl_free rb_gc_functions.free
# define rb_gc_impl_adjust_memory_usage rb_gc_functions.adjust_memory_usage
// Marking
# define rb_gc_impl_mark rb_gc_functions.mark
# define rb_gc_impl_mark_and_move rb_gc_functions.mark_and_move
# define rb_gc_impl_mark_and_pin rb_gc_functions.mark_and_pin
# define rb_gc_impl_mark_maybe rb_gc_functions.mark_maybe
# define rb_gc_impl_mark_weak rb_gc_functions.mark_weak
# define rb_gc_impl_remove_weak rb_gc_functions.remove_weak
// Compaction
# define rb_gc_impl_object_moved_p rb_gc_functions.object_moved_p
# define rb_gc_impl_location rb_gc_functions.location
// Write barriers
# define rb_gc_impl_writebarrier rb_gc_functions.writebarrier
# define rb_gc_impl_writebarrier_unprotect rb_gc_functions.writebarrier_unprotect
# define rb_gc_impl_writebarrier_remember rb_gc_functions.writebarrier_remember
// Heap walking
# define rb_gc_impl_each_objects rb_gc_functions.each_objects
# define rb_gc_impl_each_object rb_gc_functions.each_object
// Finalizers
# define rb_gc_impl_make_zombie rb_gc_functions.make_zombie
# define rb_gc_impl_define_finalizer rb_gc_functions.define_finalizer
# define rb_gc_impl_undefine_finalizer rb_gc_functions.undefine_finalizer
# define rb_gc_impl_copy_finalizer rb_gc_functions.copy_finalizer
# define rb_gc_impl_shutdown_call_finalizer rb_gc_functions.shutdown_call_finalizer
// Forking
# define rb_gc_impl_before_fork rb_gc_functions.before_fork
# define rb_gc_impl_after_fork rb_gc_functions.after_fork
// Statistics
# define rb_gc_impl_set_measure_total_time rb_gc_functions.set_measure_total_time
# define rb_gc_impl_get_measure_total_time rb_gc_functions.get_measure_total_time
# define rb_gc_impl_get_total_time rb_gc_functions.get_total_time
# define rb_gc_impl_gc_count rb_gc_functions.gc_count
# define rb_gc_impl_latest_gc_info rb_gc_functions.latest_gc_info
# define rb_gc_impl_stat rb_gc_functions.stat
# define rb_gc_impl_stat_heap rb_gc_functions.stat_heap
# define rb_gc_impl_active_gc_name rb_gc_functions.active_gc_name
// Miscellaneous
# define rb_gc_impl_object_metadata rb_gc_functions.object_metadata
# define rb_gc_impl_pointer_to_heap_p rb_gc_functions.pointer_to_heap_p
# define rb_gc_impl_garbage_object_p rb_gc_functions.garbage_object_p
# define rb_gc_impl_set_event_hook rb_gc_functions.set_event_hook
# define rb_gc_impl_copy_attributes rb_gc_functions.copy_attributes
#endif

#ifdef RUBY_ASAN_ENABLED
static void
asan_death_callback(void)
{
    if (GET_VM()) {
        rb_bug_without_die("ASAN error");
    }
}
#endif

static VALUE initial_stress = Qfalse;

void *
rb_objspace_alloc(void)
{
#if USE_MODULAR_GC
    ruby_modular_gc_init();
#endif

    void *objspace = rb_gc_impl_objspace_alloc();
    ruby_current_vm_ptr->gc.objspace = objspace;
    rb_gc_impl_objspace_init(objspace);
    rb_gc_impl_stress_set(objspace, initial_stress);

#ifdef RUBY_ASAN_ENABLED
    __sanitizer_set_death_callback(asan_death_callback);
#endif

    return objspace;
}

void
rb_objspace_free(void *objspace)
{
    rb_gc_impl_objspace_free(objspace);
}

size_t
rb_gc_obj_slot_size(VALUE obj)
{
    return rb_gc_impl_obj_slot_size(obj);
}

static inline void
gc_validate_pc(void)
{
#if RUBY_DEBUG
    rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = ec->cfp;
    if (cfp && VM_FRAME_RUBYFRAME_P(cfp) && cfp->pc) {
        RUBY_ASSERT(cfp->pc >= ISEQ_BODY(cfp->iseq)->iseq_encoded);
        RUBY_ASSERT(cfp->pc <= ISEQ_BODY(cfp->iseq)->iseq_encoded + ISEQ_BODY(cfp->iseq)->iseq_size);
    }
#endif
}

static inline VALUE
newobj_of(rb_ractor_t *cr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t size)
{
    VALUE obj = rb_gc_impl_new_obj(rb_gc_get_objspace(), cr->newobj_cache, klass, flags, v1, v2, v3, wb_protected, size);

    gc_validate_pc();

    if (UNLIKELY(rb_gc_event_hook_required_p(RUBY_INTERNAL_EVENT_NEWOBJ))) {
        unsigned int lev;
        RB_VM_LOCK_ENTER_CR_LEV(cr, &lev);
        {
            memset((char *)obj + RVALUE_SIZE, 0, rb_gc_obj_slot_size(obj) - RVALUE_SIZE);

            /* We must disable GC here because the callback could call xmalloc
             * which could potentially trigger a GC, and a lot of code is unsafe
             * to trigger a GC right after an object has been allocated because
             * they perform initialization for the object and assume that the
             * GC does not trigger before then. */
            bool gc_disabled = RTEST(rb_gc_disable_no_rest());
            {
                rb_gc_event_hook(obj, RUBY_INTERNAL_EVENT_NEWOBJ);
            }
            if (!gc_disabled) rb_gc_enable();
        }
        RB_VM_LOCK_LEAVE_CR_LEV(cr, &lev);
    }

    return obj;
}

VALUE
rb_wb_unprotected_newobj_of(VALUE klass, VALUE flags, size_t size)
{
    GC_ASSERT((flags & FL_WB_PROTECTED) == 0);
    return newobj_of(GET_RACTOR(), klass, flags, 0, 0, 0, FALSE, size);
}

VALUE
rb_wb_protected_newobj_of(rb_execution_context_t *ec, VALUE klass, VALUE flags, size_t size)
{
    GC_ASSERT((flags & FL_WB_PROTECTED) == 0);
    return newobj_of(rb_ec_ractor_ptr(ec), klass, flags, 0, 0, 0, TRUE, size);
}

#define UNEXPECTED_NODE(func) \
    rb_bug(#func"(): GC does not handle T_NODE 0x%x(%p) 0x%"PRIxVALUE, \
           BUILTIN_TYPE(obj), (void*)(obj), RBASIC(obj)->flags)

static inline void
rb_data_object_check(VALUE klass)
{
    if (klass != rb_cObject && (rb_get_alloc_func(klass) == rb_class_allocate_instance)) {
        rb_undef_alloc_func(klass);
        rb_warn("undefining the allocator of T_DATA class %"PRIsVALUE, klass);
    }
}

VALUE
rb_data_object_wrap(VALUE klass, void *datap, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    RUBY_ASSERT_ALWAYS(dfree != (RUBY_DATA_FUNC)1);
    if (klass) rb_data_object_check(klass);
    return newobj_of(GET_RACTOR(), klass, T_DATA, (VALUE)dmark, (VALUE)datap, (VALUE)dfree, !dmark, sizeof(struct RTypedData));
}

VALUE
rb_data_object_zalloc(VALUE klass, size_t size, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    VALUE obj = rb_data_object_wrap(klass, 0, dmark, dfree);
    DATA_PTR(obj) = xcalloc(1, size);
    return obj;
}

static VALUE
typed_data_alloc(VALUE klass, VALUE typed_flag, void *datap, const rb_data_type_t *type, size_t size)
{
    RBIMPL_NONNULL_ARG(type);
    if (klass) rb_data_object_check(klass);
    bool wb_protected = (type->flags & RUBY_FL_WB_PROTECTED) || !type->function.dmark;
    return newobj_of(GET_RACTOR(), klass, T_DATA, ((VALUE)type) | IS_TYPED_DATA | typed_flag, (VALUE)datap, 0, wb_protected, size);
}

VALUE
rb_data_typed_object_wrap(VALUE klass, void *datap, const rb_data_type_t *type)
{
    if (UNLIKELY(type->flags & RUBY_TYPED_EMBEDDABLE)) {
        rb_raise(rb_eTypeError, "Cannot wrap an embeddable TypedData");
    }

    return typed_data_alloc(klass, 0, datap, type, sizeof(struct RTypedData));
}

VALUE
rb_data_typed_object_zalloc(VALUE klass, size_t size, const rb_data_type_t *type)
{
    if (type->flags & RUBY_TYPED_EMBEDDABLE) {
        if (!(type->flags & RUBY_TYPED_FREE_IMMEDIATELY)) {
            rb_raise(rb_eTypeError, "Embeddable TypedData must be freed immediately");
        }

        size_t embed_size = offsetof(struct RTypedData, data) + size;
        if (rb_gc_size_allocatable_p(embed_size)) {
            VALUE obj = typed_data_alloc(klass, TYPED_DATA_EMBEDDED, 0, type, embed_size);
            memset((char *)obj + offsetof(struct RTypedData, data), 0, size);
            return obj;
        }
    }

    VALUE obj = typed_data_alloc(klass, 0, NULL, type, sizeof(struct RTypedData));
    DATA_PTR(obj) = xcalloc(1, size);
    return obj;
}

static size_t
rb_objspace_data_type_memsize(VALUE obj)
{
    size_t size = 0;
    if (RTYPEDDATA_P(obj)) {
        const rb_data_type_t *type = RTYPEDDATA_TYPE(obj);
        const void *ptr = RTYPEDDATA_GET_DATA(obj);

        if (RTYPEDDATA_TYPE(obj)->flags & RUBY_TYPED_EMBEDDABLE && !RTYPEDDATA_EMBEDDED_P(obj)) {
#ifdef HAVE_MALLOC_USABLE_SIZE
            size += malloc_usable_size((void *)ptr);
#endif
        }

        if (ptr && type->function.dsize) {
            size += type->function.dsize(ptr);
        }
    }

    return size;
}

const char *
rb_objspace_data_type_name(VALUE obj)
{
    if (RTYPEDDATA_P(obj)) {
        return RTYPEDDATA_TYPE(obj)->wrap_struct_name;
    }
    else {
        return 0;
    }
}

static enum rb_id_table_iterator_result
cvar_table_free_i(VALUE value, void *ctx)
{
    xfree((void *)value);
    return ID_TABLE_CONTINUE;
}

static void
io_fptr_finalize(void *fptr)
{
    rb_io_fptr_finalize((struct rb_io *)fptr);
}

static inline void
make_io_zombie(void *objspace, VALUE obj)
{
    rb_io_t *fptr = RFILE(obj)->fptr;
    rb_gc_impl_make_zombie(objspace, obj, io_fptr_finalize, fptr);
}

static bool
rb_data_free(void *objspace, VALUE obj)
{
    void *data = RTYPEDDATA_P(obj) ? RTYPEDDATA_GET_DATA(obj) : DATA_PTR(obj);
    if (data) {
        int free_immediately = false;
        void (*dfree)(void *);

        if (RTYPEDDATA_P(obj)) {
            free_immediately = (RTYPEDDATA_TYPE(obj)->flags & RUBY_TYPED_FREE_IMMEDIATELY) != 0;
            dfree = RTYPEDDATA_TYPE(obj)->function.dfree;
        }
        else {
            dfree = RDATA(obj)->dfree;
        }

        if (dfree) {
            if (dfree == RUBY_DEFAULT_FREE) {
                if (!RTYPEDDATA_P(obj) || !RTYPEDDATA_EMBEDDED_P(obj)) {
                    xfree(data);
                    RB_DEBUG_COUNTER_INC(obj_data_xfree);
                }
            }
            else if (free_immediately) {
                (*dfree)(data);
                if (RTYPEDDATA_TYPE(obj)->flags & RUBY_TYPED_EMBEDDABLE && !RTYPEDDATA_EMBEDDED_P(obj)) {
                    xfree(data);
                }

                RB_DEBUG_COUNTER_INC(obj_data_imm_free);
            }
            else {
                rb_gc_impl_make_zombie(objspace, obj, dfree, data);
                RB_DEBUG_COUNTER_INC(obj_data_zombie);
                return FALSE;
            }
        }
        else {
            RB_DEBUG_COUNTER_INC(obj_data_empty);
        }
    }

    return true;
}

struct classext_foreach_args {
    VALUE klass;
    rb_objspace_t *objspace; // used for update_*
};

static void
classext_free(rb_classext_t *ext, bool is_prime, VALUE namespace, void *arg)
{
    struct rb_id_table *tbl;
    struct classext_foreach_args *args = (struct classext_foreach_args *)arg;

    rb_id_table_free(RCLASSEXT_M_TBL(ext));

    if (!RCLASSEXT_SHARED_CONST_TBL(ext) && (tbl = RCLASSEXT_CONST_TBL(ext)) != NULL) {
        rb_free_const_table(tbl);
    }
    if ((tbl = RCLASSEXT_CVC_TBL(ext)) != NULL) {
        rb_id_table_foreach_values(tbl, cvar_table_free_i, NULL);
        rb_id_table_free(tbl);
    }
    rb_class_classext_free_subclasses(ext, args->klass);
    if (RCLASSEXT_SUPERCLASSES_WITH_SELF(ext)) {
        RUBY_ASSERT(is_prime); // superclasses should only be used on prime
        xfree(RCLASSEXT_SUPERCLASSES(ext));
    }
    if (!is_prime) { // the prime classext will be freed with RClass
        xfree(ext);
    }
}

static void
classext_iclass_free(rb_classext_t *ext, bool is_prime, VALUE namespace, void *arg)
{
    struct classext_foreach_args *args = (struct classext_foreach_args *)arg;

    if (RCLASSEXT_ICLASS_IS_ORIGIN(ext) && !RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(ext)) {
        /* Method table is not shared for origin iclasses of classes */
        rb_id_table_free(RCLASSEXT_M_TBL(ext));
    }
    if (RCLASSEXT_CALLABLE_M_TBL(ext) != NULL) {
        rb_id_table_free(RCLASSEXT_CALLABLE_M_TBL(ext));
    }

    rb_class_classext_free_subclasses(ext, args->klass);

    if (!is_prime) { // the prime classext will be freed with RClass
        xfree(ext);
    }
}

bool
rb_gc_obj_free(void *objspace, VALUE obj)
{
    struct classext_foreach_args args;

    RB_DEBUG_COUNTER_INC(obj_free);

    switch (BUILTIN_TYPE(obj)) {
      case T_NIL:
      case T_FIXNUM:
      case T_TRUE:
      case T_FALSE:
        rb_bug("obj_free() called for broken object");
        break;
      default:
        break;
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        if (rb_shape_obj_too_complex_p(obj)) {
            RB_DEBUG_COUNTER_INC(obj_obj_too_complex);
            st_free_table(ROBJECT_FIELDS_HASH(obj));
        }
        else if (RBASIC(obj)->flags & ROBJECT_EMBED) {
            RB_DEBUG_COUNTER_INC(obj_obj_embed);
        }
        else {
            xfree(ROBJECT(obj)->as.heap.fields);
            RB_DEBUG_COUNTER_INC(obj_obj_ptr);
        }
        break;
      case T_MODULE:
      case T_CLASS:
        args.klass = obj;
        rb_class_classext_foreach(obj, classext_free, (void *)&args);
        if (RCLASS_CLASSEXT_TBL(obj)) {
            st_free_table(RCLASS_CLASSEXT_TBL(obj));
        }
        (void)RB_DEBUG_COUNTER_INC_IF(obj_module_ptr, BUILTIN_TYPE(obj) == T_MODULE);
        (void)RB_DEBUG_COUNTER_INC_IF(obj_class_ptr, BUILTIN_TYPE(obj) == T_CLASS);
        break;
      case T_STRING:
        rb_str_free(obj);
        break;
      case T_ARRAY:
        rb_ary_free(obj);
        break;
      case T_HASH:
#if USE_DEBUG_COUNTER
        switch (RHASH_SIZE(obj)) {
          case 0:
            RB_DEBUG_COUNTER_INC(obj_hash_empty);
            break;
          case 1:
            RB_DEBUG_COUNTER_INC(obj_hash_1);
            break;
          case 2:
            RB_DEBUG_COUNTER_INC(obj_hash_2);
            break;
          case 3:
            RB_DEBUG_COUNTER_INC(obj_hash_3);
            break;
          case 4:
            RB_DEBUG_COUNTER_INC(obj_hash_4);
            break;
          case 5:
          case 6:
          case 7:
          case 8:
            RB_DEBUG_COUNTER_INC(obj_hash_5_8);
            break;
          default:
            GC_ASSERT(RHASH_SIZE(obj) > 8);
            RB_DEBUG_COUNTER_INC(obj_hash_g8);
        }

        if (RHASH_AR_TABLE_P(obj)) {
            if (RHASH_AR_TABLE(obj) == NULL) {
                RB_DEBUG_COUNTER_INC(obj_hash_null);
            }
            else {
                RB_DEBUG_COUNTER_INC(obj_hash_ar);
            }
        }
        else {
            RB_DEBUG_COUNTER_INC(obj_hash_st);
        }
#endif

        rb_hash_free(obj);
        break;
      case T_REGEXP:
        if (RREGEXP(obj)->ptr) {
            onig_free(RREGEXP(obj)->ptr);
            RB_DEBUG_COUNTER_INC(obj_regexp_ptr);
        }
        break;
      case T_DATA:
        if (!rb_data_free(objspace, obj)) return false;
        break;
      case T_MATCH:
        {
            rb_matchext_t *rm = RMATCH_EXT(obj);
#if USE_DEBUG_COUNTER
            if (rm->regs.num_regs >= 8) {
                RB_DEBUG_COUNTER_INC(obj_match_ge8);
            }
            else if (rm->regs.num_regs >= 4) {
                RB_DEBUG_COUNTER_INC(obj_match_ge4);
            }
            else if (rm->regs.num_regs >= 1) {
                RB_DEBUG_COUNTER_INC(obj_match_under4);
            }
#endif
            onig_region_free(&rm->regs, 0);
            xfree(rm->char_offset);

            RB_DEBUG_COUNTER_INC(obj_match_ptr);
        }
        break;
      case T_FILE:
        if (RFILE(obj)->fptr) {
            make_io_zombie(objspace, obj);
            RB_DEBUG_COUNTER_INC(obj_file_ptr);
            return FALSE;
        }
        break;
      case T_RATIONAL:
        RB_DEBUG_COUNTER_INC(obj_rational);
        break;
      case T_COMPLEX:
        RB_DEBUG_COUNTER_INC(obj_complex);
        break;
      case T_MOVED:
        break;
      case T_ICLASS:
        args.klass = obj;

        rb_class_classext_foreach(obj, classext_iclass_free, (void *)&args);
        if (RCLASS_CLASSEXT_TBL(obj)) {
            st_free_table(RCLASS_CLASSEXT_TBL(obj));
        }

        RB_DEBUG_COUNTER_INC(obj_iclass_ptr);
        break;

      case T_FLOAT:
        RB_DEBUG_COUNTER_INC(obj_float);
        break;

      case T_BIGNUM:
        if (!BIGNUM_EMBED_P(obj) && BIGNUM_DIGITS(obj)) {
            xfree(BIGNUM_DIGITS(obj));
            RB_DEBUG_COUNTER_INC(obj_bignum_ptr);
        }
        else {
            RB_DEBUG_COUNTER_INC(obj_bignum_embed);
        }
        break;

      case T_NODE:
        UNEXPECTED_NODE(obj_free);
        break;

      case T_STRUCT:
        if ((RBASIC(obj)->flags & RSTRUCT_EMBED_LEN_MASK) ||
            RSTRUCT(obj)->as.heap.ptr == NULL) {
            RB_DEBUG_COUNTER_INC(obj_struct_embed);
        }
        else {
            xfree((void *)RSTRUCT(obj)->as.heap.ptr);
            RB_DEBUG_COUNTER_INC(obj_struct_ptr);
        }
        break;

      case T_SYMBOL:
        RB_DEBUG_COUNTER_INC(obj_symbol);
        break;

      case T_IMEMO:
        rb_imemo_free((VALUE)obj);
        break;

      default:
        rb_bug("gc_sweep(): unknown data type 0x%x(%p) 0x%"PRIxVALUE,
               BUILTIN_TYPE(obj), (void*)obj, RBASIC(obj)->flags);
    }

    if (FL_TEST_RAW(obj, FL_FINALIZE)) {
        rb_gc_impl_make_zombie(objspace, obj, 0, 0);
        return FALSE;
    }
    else {
        return TRUE;
    }
}

void
rb_objspace_set_event_hook(const rb_event_flag_t event)
{
    rb_gc_impl_set_event_hook(rb_gc_get_objspace(), event);
}

static int
internal_object_p(VALUE obj)
{
    void *ptr = asan_unpoison_object_temporary(obj);

    if (RBASIC(obj)->flags) {
        switch (BUILTIN_TYPE(obj)) {
          case T_NODE:
            UNEXPECTED_NODE(internal_object_p);
            break;
          case T_NONE:
          case T_MOVED:
          case T_IMEMO:
          case T_ICLASS:
          case T_ZOMBIE:
            break;
          case T_CLASS:
            if (obj == rb_mRubyVMFrozenCore)
                return 1;

            if (!RBASIC_CLASS(obj)) break;
            if (RCLASS_SINGLETON_P(obj)) {
                return rb_singleton_class_internal_p(obj);
            }
            return 0;
          default:
            if (!RBASIC(obj)->klass) break;
            return 0;
        }
    }
    if (ptr || !RBASIC(obj)->flags) {
        rb_asan_poison_object(obj);
    }
    return 1;
}

int
rb_objspace_internal_object_p(VALUE obj)
{
    return internal_object_p(obj);
}

struct os_each_struct {
    size_t num;
    VALUE of;
};

static int
os_obj_of_i(void *vstart, void *vend, size_t stride, void *data)
{
    struct os_each_struct *oes = (struct os_each_struct *)data;

    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        if (!internal_object_p(v)) {
            if (!oes->of || rb_obj_is_kind_of(v, oes->of)) {
                if (!rb_multi_ractor_p() || rb_ractor_shareable_p(v)) {
                    rb_yield(v);
                    oes->num++;
                }
            }
        }
    }

    return 0;
}

static VALUE
os_obj_of(VALUE of)
{
    struct os_each_struct oes;

    oes.num = 0;
    oes.of = of;
    rb_objspace_each_objects(os_obj_of_i, &oes);
    return SIZET2NUM(oes.num);
}

/*
 *  call-seq:
 *     ObjectSpace.each_object([module]) {|obj| ... } -> integer
 *     ObjectSpace.each_object([module])              -> an_enumerator
 *
 *  Calls the block once for each living, nonimmediate object in this
 *  Ruby process. If <i>module</i> is specified, calls the block
 *  for only those classes or modules that match (or are a subclass of)
 *  <i>module</i>. Returns the number of objects found. Immediate
 *  objects (<code>Fixnum</code>s, <code>Symbol</code>s
 *  <code>true</code>, <code>false</code>, and <code>nil</code>) are
 *  never returned. In the example below, #each_object returns both
 *  the numbers we defined and several constants defined in the Math
 *  module.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     a = 102.7
 *     b = 95       # Won't be returned
 *     c = 12345678987654321
 *     count = ObjectSpace.each_object(Numeric) {|x| p x }
 *     puts "Total count: #{count}"
 *
 *  <em>produces:</em>
 *
 *     12345678987654321
 *     102.7
 *     2.71828182845905
 *     3.14159265358979
 *     2.22044604925031e-16
 *     1.7976931348623157e+308
 *     2.2250738585072e-308
 *     Total count: 7
 *
 *  Due to a current known Ractor implementation issue, this method will not yield
 *  Ractor-unshareable objects in multi-Ractor mode (when
 *  <code>Ractor.new</code> has been called within the process at least once).
 *  See https://bugs.ruby-lang.org/issues/19387 for more information.
 *
 *     a = 12345678987654321 # shareable
 *     b = [].freeze # shareable
 *     c = {} # not shareable
 *     ObjectSpace.each_object {|x| x } # yields a, b, and c
 *     Ractor.new {} # enter multi-Ractor mode
 *     ObjectSpace.each_object {|x| x } # does not yield c
 *
 */

static VALUE
os_each_obj(int argc, VALUE *argv, VALUE os)
{
    VALUE of;

    of = (!rb_check_arity(argc, 0, 1) ? 0 : argv[0]);
    RETURN_ENUMERATOR(os, 1, &of);
    return os_obj_of(of);
}

/*
 *  call-seq:
 *     ObjectSpace.undefine_finalizer(obj)
 *
 *  Removes all finalizers for <i>obj</i>.
 *
 */

static VALUE
undefine_final(VALUE os, VALUE obj)
{
    return rb_undefine_finalizer(obj);
}

VALUE
rb_undefine_finalizer(VALUE obj)
{
    rb_check_frozen(obj);

    rb_gc_impl_undefine_finalizer(rb_gc_get_objspace(), obj);

    return obj;
}

static void
should_be_callable(VALUE block)
{
    if (!rb_obj_respond_to(block, idCall, TRUE)) {
        rb_raise(rb_eArgError, "wrong type argument %"PRIsVALUE" (should be callable)",
                 rb_obj_class(block));
    }
}

static void
should_be_finalizable(VALUE obj)
{
    if (!FL_ABLE(obj)) {
        rb_raise(rb_eArgError, "cannot define finalizer for %s",
                 rb_obj_classname(obj));
    }
    rb_check_frozen(obj);
}

void
rb_gc_copy_finalizer(VALUE dest, VALUE obj)
{
    rb_gc_impl_copy_finalizer(rb_gc_get_objspace(), dest, obj);
}

/*
 *  call-seq:
 *     ObjectSpace.define_finalizer(obj, aProc=proc())
 *
 *  Adds <i>aProc</i> as a finalizer, to be called after <i>obj</i>
 *  was destroyed. The object ID of the <i>obj</i> will be passed
 *  as an argument to <i>aProc</i>. If <i>aProc</i> is a lambda or
 *  method, make sure it can be called with a single argument.
 *
 *  The return value is an array <code>[0, aProc]</code>.
 *
 *  The two recommended patterns are to either create the finaliser proc
 *  in a non-instance method where it can safely capture the needed state,
 *  or to use a custom callable object that stores the needed state
 *  explicitly as instance variables.
 *
 *      class Foo
 *        def initialize(data_needed_for_finalization)
 *          ObjectSpace.define_finalizer(self, self.class.create_finalizer(data_needed_for_finalization))
 *        end
 *
 *        def self.create_finalizer(data_needed_for_finalization)
 *          proc {
 *            puts "finalizing #{data_needed_for_finalization}"
 *          }
 *        end
 *      end
 *
 *      class Bar
 *       class Remover
 *          def initialize(data_needed_for_finalization)
 *            @data_needed_for_finalization = data_needed_for_finalization
 *          end
 *
 *          def call(id)
 *            puts "finalizing #{@data_needed_for_finalization}"
 *          end
 *        end
 *
 *        def initialize(data_needed_for_finalization)
 *          ObjectSpace.define_finalizer(self, Remover.new(data_needed_for_finalization))
 *        end
 *      end
 *
 *  Note that if your finalizer references the object to be
 *  finalized it will never be run on GC, although it will still be
 *  run at exit. You will get a warning if you capture the object
 *  to be finalized as the receiver of the finalizer.
 *
 *      class CapturesSelf
 *        def initialize(name)
 *          ObjectSpace.define_finalizer(self, proc {
 *            # this finalizer will only be run on exit
 *            puts "finalizing #{name}"
 *          })
 *        end
 *      end
 *
 *  Also note that finalization can be unpredictable and is never guaranteed
 *  to be run except on exit.
 */

static VALUE
define_final(int argc, VALUE *argv, VALUE os)
{
    VALUE obj, block;

    rb_scan_args(argc, argv, "11", &obj, &block);
    if (argc == 1) {
        block = rb_block_proc();
    }

    if (rb_callable_receiver(block) == obj) {
        rb_warn("finalizer references object to be finalized");
    }

    return rb_define_finalizer(obj, block);
}

VALUE
rb_define_finalizer(VALUE obj, VALUE block)
{
    should_be_finalizable(obj);
    should_be_callable(block);

    block = rb_gc_impl_define_finalizer(rb_gc_get_objspace(), obj, block);

    block = rb_ary_new3(2, INT2FIX(0), block);
    OBJ_FREEZE(block);
    return block;
}

void
rb_objspace_call_finalizer(void)
{
    rb_gc_impl_shutdown_call_finalizer(rb_gc_get_objspace());
}

void
rb_objspace_free_objects(void *objspace)
{
    rb_gc_impl_shutdown_free_objects(objspace);
}

int
rb_objspace_garbage_object_p(VALUE obj)
{
    return !SPECIAL_CONST_P(obj) && rb_gc_impl_garbage_object_p(rb_gc_get_objspace(), obj);
}

bool
rb_gc_pointer_to_heap_p(VALUE obj)
{
    return rb_gc_impl_pointer_to_heap_p(rb_gc_get_objspace(), (void *)obj);
}

#define OBJ_ID_INCREMENT (RUBY_IMMEDIATE_MASK + 1)
#define LAST_OBJECT_ID() (object_id_counter * OBJ_ID_INCREMENT)
static VALUE id2ref_value = 0;
static st_table *id2ref_tbl = NULL;
static bool id2ref_tbl_built = false;

#if SIZEOF_SIZE_T == SIZEOF_LONG_LONG
static size_t object_id_counter = 1;
#else
static unsigned long long object_id_counter = 1;
#endif

static inline VALUE
generate_next_object_id(void)
{
#if SIZEOF_SIZE_T == SIZEOF_LONG_LONG
    // 64bit atomics are available
    return SIZET2NUM(RUBY_ATOMIC_SIZE_FETCH_ADD(object_id_counter, 1) * OBJ_ID_INCREMENT);
#else
    unsigned int lock_lev = RB_GC_VM_LOCK();
    VALUE id = ULL2NUM(++object_id_counter * OBJ_ID_INCREMENT);
    RB_GC_VM_UNLOCK(lock_lev);
    return id;
#endif
}

void
rb_gc_obj_id_moved(VALUE obj)
{
    if (UNLIKELY(id2ref_tbl)) {
        st_insert(id2ref_tbl, (st_data_t)rb_obj_id(obj), (st_data_t)obj);
    }
}

static int
object_id_cmp(st_data_t x, st_data_t y)
{
    if (RB_TYPE_P(x, T_BIGNUM)) {
        return !rb_big_eql(x, y);
    }
    else {
        return x != y;
    }
}

static st_index_t
object_id_hash(st_data_t n)
{
    return FIX2LONG(rb_hash((VALUE)n));
}

static const struct st_hash_type object_id_hash_type = {
    object_id_cmp,
    object_id_hash,
};

static void gc_mark_tbl_no_pin(st_table *table);

static void
id2ref_tbl_mark(void *data)
{
    st_table *table = (st_table *)data;
    if (UNLIKELY(!RB_POSFIXABLE(LAST_OBJECT_ID()))) {
        // It's very unlikely, but if enough object ids were generated, keys may be T_BIGNUM
        rb_mark_set(table);
    }
    // We purposedly don't mark values, as they are weak references.
    // rb_gc_obj_free_vm_weak_references takes care of cleaning them up.
}

static size_t
id2ref_tbl_memsize(const void *data)
{
    return rb_st_memsize(data);
}

static void
id2ref_tbl_free(void *data)
{
    id2ref_tbl = NULL; // clear global ref
    st_table *table = (st_table *)data;
    st_free_table(table);
}

static const rb_data_type_t id2ref_tbl_type = {
    .wrap_struct_name = "VM/_id2ref_table",
    .function = {
        .dmark = id2ref_tbl_mark,
        .dfree = id2ref_tbl_free,
        .dsize = id2ref_tbl_memsize,
        // dcompact function not required because the table is reference updated
        // in rb_gc_vm_weak_table_foreach
    },
    .flags = RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
class_object_id(VALUE klass)
{
    VALUE id = RUBY_ATOMIC_VALUE_LOAD(RCLASS(klass)->object_id);
    if (!id) {
        unsigned int lock_lev = RB_GC_VM_LOCK();
        id = generate_next_object_id();
        VALUE existing_id = RUBY_ATOMIC_VALUE_CAS(RCLASS(klass)->object_id, 0, id);
        if (existing_id) {
            id = existing_id;
        }
        else if (RB_UNLIKELY(id2ref_tbl)) {
            st_insert(id2ref_tbl, id, klass);
        }
        RB_GC_VM_UNLOCK(lock_lev);
    }
    return id;
}

static inline VALUE
object_id_get(VALUE obj, shape_id_t shape_id)
{
    VALUE id;
    if (rb_shape_too_complex_p(shape_id)) {
        id = rb_obj_field_get(obj, ROOT_TOO_COMPLEX_WITH_OBJ_ID);
    }
    else {
        id = rb_obj_field_get(obj, rb_shape_object_id(shape_id));
    }

#if RUBY_DEBUG
    if (!(FIXNUM_P(id) || RB_TYPE_P(id, T_BIGNUM))) {
        rb_p(obj);
        rb_bug("Object's shape includes object_id, but it's missing %s", rb_obj_info(obj));
    }
#endif

    return id;
}

static VALUE
object_id0(VALUE obj)
{
    VALUE id = Qfalse;
    shape_id_t shape_id = RBASIC_SHAPE_ID(obj);

    if (rb_shape_has_object_id(shape_id)) {
        return object_id_get(obj, shape_id);
    }

    // rb_shape_object_id_shape may lock if the current shape has
    // multiple children.
    shape_id_t object_id_shape_id = rb_shape_transition_object_id(obj);

    id = generate_next_object_id();
    rb_obj_field_set(obj, object_id_shape_id, 0, id);

    RUBY_ASSERT(RBASIC_SHAPE_ID(obj) == object_id_shape_id);
    RUBY_ASSERT(rb_shape_obj_has_id(obj));

    if (RB_UNLIKELY(id2ref_tbl)) {
        st_insert(id2ref_tbl, (st_data_t)id, (st_data_t)obj);
    }
    return id;
}

static VALUE
object_id(VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
      case T_MODULE:
        // With namespaces, classes and modules have different fields
        // in different namespaces, so we cannot store the object id
        // in fields.
        return class_object_id(obj);
      case T_IMEMO:
        rb_bug("T_IMEMO can't have an object_id");
        break;
      default:
        break;
    }

    if (UNLIKELY(rb_gc_multi_ractor_p() && rb_ractor_shareable_p(obj))) {
        unsigned int lock_lev = RB_GC_VM_LOCK();
        VALUE id = object_id0(obj);
        RB_GC_VM_UNLOCK(lock_lev);
        return id;
    }

    return object_id0(obj);
}

static void
build_id2ref_i(VALUE obj, void *data)
{
    st_table *id2ref_tbl = (st_table *)data;

    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
      case T_MODULE:
        if (RCLASS(obj)->object_id) {
            st_insert(id2ref_tbl, RCLASS(obj)->object_id, obj);
        }
        break;
      case T_IMEMO:
      case T_NONE:
        break;
      default:
        if (rb_shape_obj_has_id(obj)) {
            st_insert(id2ref_tbl, rb_obj_id(obj), obj);
        }
        break;
    }
}

static VALUE
object_id_to_ref(void *objspace_ptr, VALUE object_id)
{
    rb_objspace_t *objspace = objspace_ptr;

    unsigned int lev = RB_GC_VM_LOCK();

    if (!id2ref_tbl) {
        rb_gc_vm_barrier(); // stop other ractors

        // GC Must not trigger while we build the table, otherwise if we end
        // up freeing an object that had an ID, we might try to delete it from
        // the table even though it wasn't inserted yet.
        id2ref_tbl = st_init_table(&object_id_hash_type);
        id2ref_value = TypedData_Wrap_Struct(0, &id2ref_tbl_type, id2ref_tbl);

        // build_id2ref_i will most certainly malloc, which could trigger GC and sweep
        // objects we just added to the table.
        bool gc_disabled = RTEST(rb_gc_disable_no_rest());
        {
            rb_gc_impl_each_object(objspace, build_id2ref_i, (void *)id2ref_tbl);
        }
        if (!gc_disabled) rb_gc_enable();
        id2ref_tbl_built = true;
    }

    VALUE obj;
    bool found = st_lookup(id2ref_tbl, object_id, &obj) && !rb_gc_impl_garbage_object_p(objspace, obj);

    RB_GC_VM_UNLOCK(lev);

    if (found) {
        return obj;
    }

    if (rb_funcall(object_id, rb_intern(">="), 1, ULL2NUM(LAST_OBJECT_ID()))) {
        rb_raise(rb_eRangeError, "%+"PRIsVALUE" is not an id value", rb_funcall(object_id, rb_intern("to_s"), 1, INT2FIX(10)));
    }
    else {
        rb_raise(rb_eRangeError, "%+"PRIsVALUE" is a recycled object", rb_funcall(object_id, rb_intern("to_s"), 1, INT2FIX(10)));
    }
}

static inline void
obj_free_object_id(VALUE obj)
{
    VALUE obj_id = 0;
    if (RB_UNLIKELY(id2ref_tbl)) {
        switch (BUILTIN_TYPE(obj)) {
          case T_CLASS:
          case T_MODULE:
            obj_id = RCLASS(obj)->object_id;
            break;
          case T_IMEMO:
            if (!IMEMO_TYPE_P(obj, imemo_fields)) {
                return;
            }
            // fallthrough
          case T_OBJECT:
            {
            shape_id_t shape_id = RBASIC_SHAPE_ID(obj);
            if (rb_shape_has_object_id(shape_id)) {
                obj_id = object_id_get(obj, shape_id);
            }
            break;
          }
          default:
            // For generic_fields, the T_IMEMO/fields is responsible for freeing the id.
            return;
        }

        if (RB_UNLIKELY(obj_id)) {
            RUBY_ASSERT(FIXNUM_P(obj_id) || RB_TYPE_P(obj_id, T_BIGNUM));

            if (!st_delete(id2ref_tbl, (st_data_t *)&obj_id, NULL)) {
                // If we're currently building the table then it's not a bug.
                // The the object is a T_IMEMO/fields, then it's possible the actual object
                // has been garbage collected already.
                if (id2ref_tbl_built && !RB_TYPE_P(obj, T_IMEMO)) {
                    rb_bug("Object ID seen, but not in _id2ref table: object_id=%llu object=%s", NUM2ULL(obj_id), rb_obj_info(obj));
                }
            }
        }
    }
}

void
rb_gc_obj_free_vm_weak_references(VALUE obj)
{
    obj_free_object_id(obj);

    if (rb_obj_exivar_p(obj)) {
        rb_free_generic_ivar(obj);
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
        if (FL_TEST_RAW(obj, RSTRING_FSTR)) {
            rb_gc_free_fstring(obj);
        }
        break;
      case T_SYMBOL:
        rb_gc_free_dsymbol(obj);
        break;
      case T_IMEMO:
        switch (imemo_type(obj)) {
          case imemo_callcache: {
            const struct rb_callcache *cc = (const struct rb_callcache *)obj;

            if (vm_cc_refinement_p(cc)) {
                rb_vm_delete_cc_refinement(cc);
            }

            break;
          }
          case imemo_callinfo:
            rb_vm_ci_free((const struct rb_callinfo *)obj);
            break;
          case imemo_ment:
            rb_free_method_entry_vm_weak_references((const rb_method_entry_t *)obj);
            break;
          default:
            break;
        }
        break;
      default:
        break;
    }
}

/*
 *  call-seq:
 *     ObjectSpace._id2ref(object_id) -> an_object
 *
 *  Converts an object id to a reference to the object. May not be
 *  called on an object id passed as a parameter to a finalizer.
 *
 *     s = "I am a string"                    #=> "I am a string"
 *     r = ObjectSpace._id2ref(s.object_id)   #=> "I am a string"
 *     r == s                                 #=> true
 *
 *  On multi-ractor mode, if the object is not shareable, it raises
 *  RangeError.
 *
 *  This method is deprecated and should no longer be used.
 */

static VALUE
id2ref(VALUE objid)
{
#if SIZEOF_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULONG(x)
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULL(x)
#endif
    objid = rb_to_int(objid);
    if (FIXNUM_P(objid) || rb_big_size(objid) <= SIZEOF_VOIDP) {
        VALUE ptr = NUM2PTR(objid);
        if (SPECIAL_CONST_P(ptr)) {
            if (ptr == Qtrue) return Qtrue;
            if (ptr == Qfalse) return Qfalse;
            if (NIL_P(ptr)) return Qnil;
            if (FIXNUM_P(ptr)) return ptr;
            if (FLONUM_P(ptr)) return ptr;

            if (SYMBOL_P(ptr)) {
                // Check that the symbol is valid
                if (rb_static_id_valid_p(SYM2ID(ptr))) {
                    return ptr;
                }
                else {
                    rb_raise(rb_eRangeError, "%p is not a symbol id value", (void *)ptr);
                }
            }

            rb_raise(rb_eRangeError, "%+"PRIsVALUE" is not an id value", rb_int2str(objid, 10));
        }
    }

    VALUE obj = object_id_to_ref(rb_gc_get_objspace(), objid);
    if (!rb_multi_ractor_p() || rb_ractor_shareable_p(obj)) {
        return obj;
    }
    else {
        rb_raise(rb_eRangeError, "%+"PRIsVALUE" is the id of an unshareable object on multi-ractor", rb_int2str(objid, 10));
    }
}

/* :nodoc: */
static VALUE
os_id2ref(VALUE os, VALUE objid)
{
    rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "ObjectSpace._id2ref is deprecated");
    return id2ref(objid);
}

static VALUE
rb_find_object_id(void *objspace, VALUE obj, VALUE (*get_heap_object_id)(VALUE))
{
    if (SPECIAL_CONST_P(obj)) {
#if SIZEOF_LONG == SIZEOF_VOIDP
        return LONG2NUM((SIGNED_VALUE)obj);
#else
        return LL2NUM((SIGNED_VALUE)obj);
#endif
    }

    return get_heap_object_id(obj);
}

static VALUE
nonspecial_obj_id(VALUE obj)
{
#if SIZEOF_LONG == SIZEOF_VOIDP
    return (VALUE)((SIGNED_VALUE)(obj)|FIXNUM_FLAG);
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
    return LL2NUM((SIGNED_VALUE)(obj) / 2);
#else
# error not supported
#endif
}

VALUE
rb_memory_id(VALUE obj)
{
    return rb_find_object_id(NULL, obj, nonspecial_obj_id);
}

/*
 *  Document-method: __id__
 *  Document-method: object_id
 *
 *  call-seq:
 *     obj.__id__       -> integer
 *     obj.object_id    -> integer
 *
 *  Returns an integer identifier for +obj+.
 *
 *  The same number will be returned on all calls to +object_id+ for a given
 *  object, and no two active objects will share an id.
 *
 *  Note: that some objects of builtin classes are reused for optimization.
 *  This is the case for immediate values and frozen string literals.
 *
 *  BasicObject implements +__id__+, Kernel implements +object_id+.
 *
 *  Immediate values are not passed by reference but are passed by value:
 *  +nil+, +true+, +false+, Fixnums, Symbols, and some Floats.
 *
 *      Object.new.object_id  == Object.new.object_id  # => false
 *      (21 * 2).object_id    == (21 * 2).object_id    # => true
 *      "hello".object_id     == "hello".object_id     # => false
 *      "hi".freeze.object_id == "hi".freeze.object_id # => true
 */

VALUE
rb_obj_id(VALUE obj)
{
    /* If obj is an immediate, the object ID is obj directly converted to a Numeric.
     * Otherwise, the object ID is a Numeric that is a non-zero multiple of
     * (RUBY_IMMEDIATE_MASK + 1) which guarantees that it does not collide with
     * any immediates. */
    return rb_find_object_id(rb_gc_get_objspace(), obj, object_id);
}

bool
rb_obj_id_p(VALUE obj)
{
    return !RB_TYPE_P(obj, T_IMEMO) && rb_shape_obj_has_id(obj);
}

/*
 * GC implementations should call this function before the GC phase that updates references
 * embedded in the machine code generated by JIT compilers.  JIT compilers usually enforce the
 * "W^X" policy and protect the code memory from being modified during execution.  This function
 * makes the code memory writeable.
 */
void
rb_gc_before_updating_jit_code(void)
{
#if USE_YJIT
    rb_yjit_mark_all_writeable();
#endif
}

/*
 * GC implementations should call this function before the GC phase that updates references
 * embedded in the machine code generated by JIT compilers.  This function makes the code memory
 * executable again.
 */
void
rb_gc_after_updating_jit_code(void)
{
#if USE_YJIT
    rb_yjit_mark_all_executable();
#endif
}

static void
classext_memsize(rb_classext_t *ext, bool prime, VALUE namespace, void *arg)
{
    size_t *size = (size_t *)arg;
    size_t s = 0;

    if (RCLASSEXT_M_TBL(ext)) {
        s += rb_id_table_memsize(RCLASSEXT_M_TBL(ext));
    }
    if (RCLASSEXT_CVC_TBL(ext)) {
        s += rb_id_table_memsize(RCLASSEXT_CVC_TBL(ext));
    }
    if (RCLASSEXT_CONST_TBL(ext)) {
        s += rb_id_table_memsize(RCLASSEXT_CONST_TBL(ext));
    }
    if (RCLASSEXT_SUPERCLASSES_WITH_SELF(ext)) {
        s += (RCLASSEXT_SUPERCLASS_DEPTH(ext) + 1) * sizeof(VALUE);
    }
    if (!prime) {
        s += sizeof(rb_classext_t);
    }
    *size += s;
}

static void
classext_superclasses_memsize(rb_classext_t *ext, bool prime, VALUE namespace, void *arg)
{
    size_t *size = (size_t *)arg;
    size_t array_size;
    if (RCLASSEXT_SUPERCLASSES_WITH_SELF(ext)) {
        RUBY_ASSERT(prime);
        array_size = RCLASSEXT_SUPERCLASS_DEPTH(ext) + 1;
        *size += array_size * sizeof(VALUE);
    }
}

size_t
rb_obj_memsize_of(VALUE obj)
{
    size_t size = 0;

    if (SPECIAL_CONST_P(obj)) {
        return 0;
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        if (rb_shape_obj_too_complex_p(obj)) {
            size += rb_st_memsize(ROBJECT_FIELDS_HASH(obj));
        }
        else if (!(RBASIC(obj)->flags & ROBJECT_EMBED)) {
            size += ROBJECT_FIELDS_CAPACITY(obj) * sizeof(VALUE);
        }
        break;
      case T_MODULE:
      case T_CLASS:
        rb_class_classext_foreach(obj, classext_memsize, (void *)&size);
        rb_class_classext_foreach(obj, classext_superclasses_memsize, (void *)&size);
        break;
      case T_ICLASS:
        if (RICLASS_OWNS_M_TBL_P(obj)) {
            if (RCLASS_M_TBL(obj)) {
                size += rb_id_table_memsize(RCLASS_M_TBL(obj));
            }
        }
        break;
      case T_STRING:
        size += rb_str_memsize(obj);
        break;
      case T_ARRAY:
        size += rb_ary_memsize(obj);
        break;
      case T_HASH:
        if (RHASH_ST_TABLE_P(obj)) {
            VM_ASSERT(RHASH_ST_TABLE(obj) != NULL);
            /* st_table is in the slot */
            size += st_memsize(RHASH_ST_TABLE(obj)) - sizeof(st_table);
        }
        break;
      case T_REGEXP:
        if (RREGEXP_PTR(obj)) {
            size += onig_memsize(RREGEXP_PTR(obj));
        }
        break;
      case T_DATA:
        size += rb_objspace_data_type_memsize(obj);
        break;
      case T_MATCH:
        {
            rb_matchext_t *rm = RMATCH_EXT(obj);
            size += onig_region_memsize(&rm->regs);
            size += sizeof(struct rmatch_offset) * rm->char_offset_num_allocated;
        }
        break;
      case T_FILE:
        if (RFILE(obj)->fptr) {
            size += rb_io_memsize(RFILE(obj)->fptr);
        }
        break;
      case T_RATIONAL:
      case T_COMPLEX:
        break;
      case T_IMEMO:
        size += rb_imemo_memsize(obj);
        break;

      case T_FLOAT:
      case T_SYMBOL:
        break;

      case T_BIGNUM:
        if (!(RBASIC(obj)->flags & BIGNUM_EMBED_FLAG) && BIGNUM_DIGITS(obj)) {
            size += BIGNUM_LEN(obj) * sizeof(BDIGIT);
        }
        break;

      case T_NODE:
        UNEXPECTED_NODE(obj_memsize_of);
        break;

      case T_STRUCT:
        if ((RBASIC(obj)->flags & RSTRUCT_EMBED_LEN_MASK) == 0 &&
            RSTRUCT(obj)->as.heap.ptr) {
            size += sizeof(VALUE) * RSTRUCT_LEN(obj);
        }
        break;

      case T_ZOMBIE:
      case T_MOVED:
        break;

      default:
        rb_bug("objspace/memsize_of(): unknown data type 0x%x(%p)",
               BUILTIN_TYPE(obj), (void*)obj);
    }

    return size + rb_gc_obj_slot_size(obj);
}

static int
set_zero(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE k = (VALUE)key;
    VALUE hash = (VALUE)arg;
    rb_hash_aset(hash, k, INT2FIX(0));
    return ST_CONTINUE;
}

struct count_objects_data {
    size_t counts[T_MASK+1];
    size_t freed;
    size_t total;
};

static void
count_objects_i(VALUE obj, void *d)
{
    struct count_objects_data *data = (struct count_objects_data *)d;

    if (RBASIC(obj)->flags) {
        data->counts[BUILTIN_TYPE(obj)]++;
    }
    else {
        data->freed++;
    }

    data->total++;
}

/*
 *  call-seq:
 *     ObjectSpace.count_objects([result_hash]) -> hash
 *
 *  Counts all objects grouped by type.
 *
 *  It returns a hash, such as:
 *	{
 *	  :TOTAL=>10000,
 *	  :FREE=>3011,
 *	  :T_OBJECT=>6,
 *	  :T_CLASS=>404,
 *	  # ...
 *	}
 *
 *  The contents of the returned hash are implementation specific.
 *  It may be changed in future.
 *
 *  The keys starting with +:T_+ means live objects.
 *  For example, +:T_ARRAY+ is the number of arrays.
 *  +:FREE+ means object slots which is not used now.
 *  +:TOTAL+ means sum of above.
 *
 *  If the optional argument +result_hash+ is given,
 *  it is overwritten and returned. This is intended to avoid probe effect.
 *
 *    h = {}
 *    ObjectSpace.count_objects(h)
 *    puts h
 *    # => { :TOTAL=>10000, :T_CLASS=>158280, :T_MODULE=>20672, :T_STRING=>527249 }
 *
 *  This method is only expected to work on C Ruby.
 *
 */

static VALUE
count_objects(int argc, VALUE *argv, VALUE os)
{
    struct count_objects_data data = { 0 };
    VALUE hash = Qnil;
    VALUE types[T_MASK + 1];

    if (rb_check_arity(argc, 0, 1) == 1) {
        hash = argv[0];
        if (!RB_TYPE_P(hash, T_HASH))
            rb_raise(rb_eTypeError, "non-hash given");
    }

    for (size_t i = 0; i <= T_MASK; i++) {
        // type_sym can allocate an object,
        // so we need to create all key symbols in advance
        // not to disturb the result
        types[i] = type_sym(i);
    }

    rb_gc_impl_each_object(rb_gc_get_objspace(), count_objects_i, &data);

    if (NIL_P(hash)) {
        hash = rb_hash_new();
    }
    else if (!RHASH_EMPTY_P(hash)) {
        rb_hash_stlike_foreach(hash, set_zero, hash);
    }
    rb_hash_aset(hash, ID2SYM(rb_intern("TOTAL")), SIZET2NUM(data.total));
    rb_hash_aset(hash, ID2SYM(rb_intern("FREE")), SIZET2NUM(data.freed));

    for (size_t i = 0; i <= T_MASK; i++) {
        if (data.counts[i]) {
            rb_hash_aset(hash, types[i], SIZET2NUM(data.counts[i]));
        }
    }

    return hash;
}

#define SET_STACK_END SET_MACHINE_STACK_END(&ec->machine.stack_end)

#define STACK_START (ec->machine.stack_start)
#define STACK_END (ec->machine.stack_end)
#define STACK_LEVEL_MAX (ec->machine.stack_maxsize/sizeof(VALUE))

#if STACK_GROW_DIRECTION < 0
# define STACK_LENGTH  (size_t)(STACK_START - STACK_END)
#elif STACK_GROW_DIRECTION > 0
# define STACK_LENGTH  (size_t)(STACK_END - STACK_START + 1)
#else
# define STACK_LENGTH  ((STACK_END < STACK_START) ? (size_t)(STACK_START - STACK_END) \
                        : (size_t)(STACK_END - STACK_START + 1))
#endif
#if !STACK_GROW_DIRECTION
int ruby_stack_grow_direction;
int
ruby_get_stack_grow_direction(volatile VALUE *addr)
{
    VALUE *end;
    SET_MACHINE_STACK_END(&end);

    if (end > addr) return ruby_stack_grow_direction = 1;
    return ruby_stack_grow_direction = -1;
}
#endif

size_t
ruby_stack_length(VALUE **p)
{
    rb_execution_context_t *ec = GET_EC();
    SET_STACK_END;
    if (p) *p = STACK_UPPER(STACK_END, STACK_START, STACK_END);
    return STACK_LENGTH;
}

#define PREVENT_STACK_OVERFLOW 1
#ifndef PREVENT_STACK_OVERFLOW
#if !(defined(POSIX_SIGNAL) && defined(SIGSEGV) && defined(HAVE_SIGALTSTACK))
# define PREVENT_STACK_OVERFLOW 1
#else
# define PREVENT_STACK_OVERFLOW 0
#endif
#endif
#if PREVENT_STACK_OVERFLOW && !defined(__EMSCRIPTEN__)
static int
stack_check(rb_execution_context_t *ec, int water_mark)
{
    SET_STACK_END;

    size_t length = STACK_LENGTH;
    size_t maximum_length = STACK_LEVEL_MAX - water_mark;

    return length > maximum_length;
}
#else
#define stack_check(ec, water_mark) FALSE
#endif

#define STACKFRAME_FOR_CALL_CFUNC 2048

int
rb_ec_stack_check(rb_execution_context_t *ec)
{
    return stack_check(ec, STACKFRAME_FOR_CALL_CFUNC);
}

int
ruby_stack_check(void)
{
    return stack_check(GET_EC(), STACKFRAME_FOR_CALL_CFUNC);
}

/* ==================== Marking ==================== */

#define RB_GC_MARK_OR_TRAVERSE(func, obj_or_ptr, obj, check_obj) do { \
    if (!RB_SPECIAL_CONST_P(obj)) { \
        rb_vm_t *vm = GET_VM(); \
        void *objspace = vm->gc.objspace; \
        if (LIKELY(vm->gc.mark_func_data == NULL)) { \
            GC_ASSERT(rb_gc_impl_during_gc_p(objspace)); \
            (func)(objspace, (obj_or_ptr)); \
        } \
        else if (check_obj ? \
                rb_gc_impl_pointer_to_heap_p(objspace, (const void *)obj) && \
                    !rb_gc_impl_garbage_object_p(objspace, obj) : \
                true) { \
            GC_ASSERT(!rb_gc_impl_during_gc_p(objspace)); \
            struct gc_mark_func_data_struct *mark_func_data = vm->gc.mark_func_data; \
            vm->gc.mark_func_data = NULL; \
            mark_func_data->mark_func((obj), mark_func_data->data); \
            vm->gc.mark_func_data = mark_func_data; \
        } \
    } \
} while (0)

static inline void
gc_mark_internal(VALUE obj)
{
    RB_GC_MARK_OR_TRAVERSE(rb_gc_impl_mark, obj, obj, false);
}

void
rb_gc_mark_movable(VALUE obj)
{
    gc_mark_internal(obj);
}

void
rb_gc_mark_and_move(VALUE *ptr)
{
    RB_GC_MARK_OR_TRAVERSE(rb_gc_impl_mark_and_move, ptr, *ptr, false);
}

static inline void
gc_mark_and_pin_internal(VALUE obj)
{
    RB_GC_MARK_OR_TRAVERSE(rb_gc_impl_mark_and_pin, obj, obj, false);
}

void
rb_gc_mark(VALUE obj)
{
    gc_mark_and_pin_internal(obj);
}

static inline void
gc_mark_maybe_internal(VALUE obj)
{
    RB_GC_MARK_OR_TRAVERSE(rb_gc_impl_mark_maybe, obj, obj, true);
}

void
rb_gc_mark_maybe(VALUE obj)
{
    gc_mark_maybe_internal(obj);
}

void
rb_gc_mark_weak(VALUE *ptr)
{
    if (RB_SPECIAL_CONST_P(*ptr)) return;

    rb_vm_t *vm = GET_VM();
    void *objspace = vm->gc.objspace;
    if (LIKELY(vm->gc.mark_func_data == NULL)) {
        GC_ASSERT(rb_gc_impl_during_gc_p(objspace));

        rb_gc_impl_mark_weak(objspace, ptr);
    }
    else {
        GC_ASSERT(!rb_gc_impl_during_gc_p(objspace));
    }
}

void
rb_gc_remove_weak(VALUE parent_obj, VALUE *ptr)
{
    rb_gc_impl_remove_weak(rb_gc_get_objspace(), parent_obj, ptr);
}

ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS(static void each_location(register const VALUE *x, register long n, void (*cb)(VALUE, void *), void *data));
static void
each_location(register const VALUE *x, register long n, void (*cb)(VALUE, void *), void *data)
{
    VALUE v;
    while (n--) {
        v = *x;
        cb(v, data);
        x++;
    }
}

static void
each_location_ptr(const VALUE *start, const VALUE *end, void (*cb)(VALUE, void *), void *data)
{
    if (end <= start) return;
    each_location(start, end - start, cb, data);
}

static void
gc_mark_maybe_each_location(VALUE obj, void *data)
{
    gc_mark_maybe_internal(obj);
}

void
rb_gc_mark_locations(const VALUE *start, const VALUE *end)
{
    each_location_ptr(start, end, gc_mark_maybe_each_location, NULL);
}

void
rb_gc_mark_values(long n, const VALUE *values)
{
    for (long i = 0; i < n; i++) {
        gc_mark_internal(values[i]);
    }
}

void
rb_gc_mark_vm_stack_values(long n, const VALUE *values)
{
    for (long i = 0; i < n; i++) {
        gc_mark_and_pin_internal(values[i]);
    }
}

static int
mark_key(st_data_t key, st_data_t value, st_data_t data)
{
    gc_mark_and_pin_internal((VALUE)key);

    return ST_CONTINUE;
}

void
rb_mark_set(st_table *tbl)
{
    if (!tbl) return;

    st_foreach(tbl, mark_key, (st_data_t)rb_gc_get_objspace());
}

static int
mark_keyvalue(st_data_t key, st_data_t value, st_data_t data)
{
    gc_mark_internal((VALUE)key);
    gc_mark_internal((VALUE)value);

    return ST_CONTINUE;
}

static int
pin_key_pin_value(st_data_t key, st_data_t value, st_data_t data)
{
    gc_mark_and_pin_internal((VALUE)key);
    gc_mark_and_pin_internal((VALUE)value);

    return ST_CONTINUE;
}

static int
pin_key_mark_value(st_data_t key, st_data_t value, st_data_t data)
{
    gc_mark_and_pin_internal((VALUE)key);
    gc_mark_internal((VALUE)value);

    return ST_CONTINUE;
}

static void
mark_hash(VALUE hash)
{
    if (rb_hash_compare_by_id_p(hash)) {
        rb_hash_stlike_foreach(hash, pin_key_mark_value, 0);
    }
    else {
        rb_hash_stlike_foreach(hash, mark_keyvalue, 0);
    }

    gc_mark_internal(RHASH(hash)->ifnone);
}

void
rb_mark_hash(st_table *tbl)
{
    if (!tbl) return;

    st_foreach(tbl, pin_key_pin_value, 0);
}

static enum rb_id_table_iterator_result
mark_method_entry_i(VALUE me, void *objspace)
{
    gc_mark_internal(me);

    return ID_TABLE_CONTINUE;
}

static void
mark_m_tbl(void *objspace, struct rb_id_table *tbl)
{
    if (tbl) {
        rb_id_table_foreach_values(tbl, mark_method_entry_i, objspace);
    }
}

static enum rb_id_table_iterator_result
mark_const_entry_i(VALUE value, void *objspace)
{
    const rb_const_entry_t *ce = (const rb_const_entry_t *)value;

    gc_mark_internal(ce->value);
    gc_mark_internal(ce->file);
    return ID_TABLE_CONTINUE;
}

static void
mark_const_tbl(rb_objspace_t *objspace, struct rb_id_table *tbl)
{
    if (!tbl) return;
    rb_id_table_foreach_values(tbl, mark_const_entry_i, objspace);
}

static enum rb_id_table_iterator_result
mark_cvc_tbl_i(VALUE cvc_entry, void *objspace)
{
    struct rb_cvar_class_tbl_entry *entry;

    entry = (struct rb_cvar_class_tbl_entry *)cvc_entry;

    RUBY_ASSERT(entry->cref == 0 || (BUILTIN_TYPE((VALUE)entry->cref) == T_IMEMO && IMEMO_TYPE_P(entry->cref, imemo_cref)));
    gc_mark_internal((VALUE)entry->cref);

    return ID_TABLE_CONTINUE;
}

static void
mark_cvc_tbl(rb_objspace_t *objspace, struct rb_id_table *tbl)
{
    if (!tbl) return;
    rb_id_table_foreach_values(tbl, mark_cvc_tbl_i, objspace);
}

#if STACK_GROW_DIRECTION < 0
#define GET_STACK_BOUNDS(start, end, appendix) ((start) = STACK_END, (end) = STACK_START)
#elif STACK_GROW_DIRECTION > 0
#define GET_STACK_BOUNDS(start, end, appendix) ((start) = STACK_START, (end) = STACK_END+(appendix))
#else
#define GET_STACK_BOUNDS(start, end, appendix) \
    ((STACK_END < STACK_START) ? \
     ((start) = STACK_END, (end) = STACK_START) : ((start) = STACK_START, (end) = STACK_END+(appendix)))
#endif

static void
gc_mark_machine_stack_location_maybe(VALUE obj, void *data)
{
    gc_mark_maybe_internal(obj);

#ifdef RUBY_ASAN_ENABLED
    const rb_execution_context_t *ec = (const rb_execution_context_t *)data;
    void *fake_frame_start;
    void *fake_frame_end;
    bool is_fake_frame = asan_get_fake_stack_extents(
        ec->machine.asan_fake_stack_handle, obj,
        ec->machine.stack_start, ec->machine.stack_end,
        &fake_frame_start, &fake_frame_end
    );
    if (is_fake_frame) {
        each_location_ptr(fake_frame_start, fake_frame_end, gc_mark_maybe_each_location, NULL);
    }
#endif
}

static VALUE
gc_location_internal(void *objspace, VALUE value)
{
    if (SPECIAL_CONST_P(value)) {
        return value;
    }

    GC_ASSERT(rb_gc_impl_pointer_to_heap_p(objspace, (void *)value));

    return rb_gc_impl_location(objspace, value);
}

VALUE
rb_gc_location(VALUE value)
{
    return gc_location_internal(rb_gc_get_objspace(), value);
}

void
rb_gc_update_reference(VALUE *value_ptr)
{
    void *objspace = rb_gc_get_objspace();
    if (rb_gc_impl_object_moved_p(objspace, *value_ptr)) {
        *value_ptr = gc_location_internal(objspace, *value_ptr);
    }
}

#if defined(__wasm__)


static VALUE *rb_stack_range_tmp[2];

static void
rb_mark_locations(void *begin, void *end)
{
    rb_stack_range_tmp[0] = begin;
    rb_stack_range_tmp[1] = end;
}

void
rb_gc_save_machine_context(void)
{
    // no-op
}

# if defined(__EMSCRIPTEN__)

static void
mark_current_machine_context(const rb_execution_context_t *ec)
{
    emscripten_scan_stack(rb_mark_locations);
    each_location_ptr(rb_stack_range_tmp[0], rb_stack_range_tmp[1], gc_mark_maybe_each_location, NULL);

    emscripten_scan_registers(rb_mark_locations);
    each_location_ptr(rb_stack_range_tmp[0], rb_stack_range_tmp[1], gc_mark_maybe_each_location, NULL);
}
# else // use Asyncify version

static void
mark_current_machine_context(rb_execution_context_t *ec)
{
    VALUE *stack_start, *stack_end;
    SET_STACK_END;
    GET_STACK_BOUNDS(stack_start, stack_end, 1);
    each_location_ptr(stack_start, stack_end, gc_mark_maybe_each_location, NULL);

    rb_wasm_scan_locals(rb_mark_locations);
    each_location_ptr(rb_stack_range_tmp[0], rb_stack_range_tmp[1], gc_mark_maybe_each_location, NULL);
}

# endif

#else // !defined(__wasm__)

void
rb_gc_save_machine_context(void)
{
    rb_thread_t *thread = GET_THREAD();

    RB_VM_SAVE_MACHINE_CONTEXT(thread);
}


static void
mark_current_machine_context(const rb_execution_context_t *ec)
{
    rb_gc_mark_machine_context(ec);
}
#endif

void
rb_gc_mark_machine_context(const rb_execution_context_t *ec)
{
    VALUE *stack_start, *stack_end;

    GET_STACK_BOUNDS(stack_start, stack_end, 0);
    RUBY_DEBUG_LOG("ec->th:%u stack_start:%p stack_end:%p", rb_ec_thread_ptr(ec)->serial, stack_start, stack_end);

    void *data =
#ifdef RUBY_ASAN_ENABLED
        /* gc_mark_machine_stack_location_maybe() uses data as const */
        (rb_execution_context_t *)ec;
#else
        NULL;
#endif

    each_location_ptr(stack_start, stack_end, gc_mark_machine_stack_location_maybe, data);
    int num_regs = sizeof(ec->machine.regs)/(sizeof(VALUE));
    each_location((VALUE*)&ec->machine.regs, num_regs, gc_mark_machine_stack_location_maybe, data);
}

static int
rb_mark_tbl_i(st_data_t key, st_data_t value, st_data_t data)
{
    gc_mark_and_pin_internal((VALUE)value);

    return ST_CONTINUE;
}

void
rb_mark_tbl(st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;

    st_foreach(tbl, rb_mark_tbl_i, 0);
}

static void
gc_mark_tbl_no_pin(st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;

    st_foreach(tbl, gc_mark_tbl_no_pin_i, 0);
}

void
rb_mark_tbl_no_pin(st_table *tbl)
{
    gc_mark_tbl_no_pin(tbl);
}

static bool
gc_declarative_marking_p(const rb_data_type_t *type)
{
    return (type->flags & RUBY_TYPED_DECL_MARKING) != 0;
}

void
rb_gc_mark_roots(void *objspace, const char **categoryp)
{
    rb_execution_context_t *ec = GET_EC();
    rb_vm_t *vm = rb_ec_vm_ptr(ec);

#define MARK_CHECKPOINT(category) do { \
    if (categoryp) *categoryp = category; \
} while (0)

    MARK_CHECKPOINT("vm");
    rb_vm_mark(vm);

    MARK_CHECKPOINT("end_proc");
    rb_mark_end_proc();

    MARK_CHECKPOINT("global_tbl");
    rb_gc_mark_global_tbl();

#if USE_YJIT
    void rb_yjit_root_mark(void); // in Rust

    if (rb_yjit_enabled_p) {
        MARK_CHECKPOINT("YJIT");
        rb_yjit_root_mark();
    }
#endif

    MARK_CHECKPOINT("machine_context");
    mark_current_machine_context(ec);

    MARK_CHECKPOINT("global_symbols");
    rb_sym_global_symbols_mark();

    MARK_CHECKPOINT("finish");

#undef MARK_CHECKPOINT
}

struct gc_mark_classext_foreach_arg {
    rb_objspace_t *objspace;
    VALUE obj;
};

static void
gc_mark_classext_module(rb_classext_t *ext, bool prime, VALUE namespace, void *arg)
{
    struct gc_mark_classext_foreach_arg *foreach_arg = (struct gc_mark_classext_foreach_arg *)arg;
    rb_objspace_t *objspace = foreach_arg->objspace;

    if (RCLASSEXT_SUPER(ext)) {
        gc_mark_internal(RCLASSEXT_SUPER(ext));
    }
    mark_m_tbl(objspace, RCLASSEXT_M_TBL(ext));
    gc_mark_internal(RCLASSEXT_FIELDS_OBJ(ext));
    if (!RCLASSEXT_SHARED_CONST_TBL(ext) && RCLASSEXT_CONST_TBL(ext)) {
        mark_const_tbl(objspace, RCLASSEXT_CONST_TBL(ext));
    }
    mark_m_tbl(objspace, RCLASSEXT_CALLABLE_M_TBL(ext));
    gc_mark_internal(RCLASSEXT_CC_TBL(ext));
    mark_cvc_tbl(objspace, RCLASSEXT_CVC_TBL(ext));
    gc_mark_internal(RCLASSEXT_CLASSPATH(ext));
}

static void
gc_mark_classext_iclass(rb_classext_t *ext, bool prime, VALUE namespace, void *arg)
{
    struct gc_mark_classext_foreach_arg *foreach_arg = (struct gc_mark_classext_foreach_arg *)arg;
    rb_objspace_t *objspace = foreach_arg->objspace;

    if (RCLASSEXT_SUPER(ext)) {
        gc_mark_internal(RCLASSEXT_SUPER(ext));
    }
    if (RCLASSEXT_ICLASS_IS_ORIGIN(ext) && !RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(ext)) {
        mark_m_tbl(objspace, RCLASSEXT_M_TBL(ext));
    }
    if (RCLASSEXT_INCLUDER(ext)) {
        gc_mark_internal(RCLASSEXT_INCLUDER(ext));
    }
    mark_m_tbl(objspace, RCLASSEXT_CALLABLE_M_TBL(ext));
    gc_mark_internal(RCLASSEXT_CC_TBL(ext));
}

#define TYPED_DATA_REFS_OFFSET_LIST(d) (size_t *)(uintptr_t)RTYPEDDATA_TYPE(d)->function.dmark

void
rb_gc_mark_children(void *objspace, VALUE obj)
{
    struct gc_mark_classext_foreach_arg foreach_args;

    if (rb_obj_exivar_p(obj)) {
        rb_mark_generic_ivar(obj);
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_FLOAT:
      case T_BIGNUM:
        return;

      case T_NIL:
      case T_FIXNUM:
        rb_bug("rb_gc_mark() called for broken object");
        break;

      case T_NODE:
        UNEXPECTED_NODE(rb_gc_mark);
        break;

      case T_IMEMO:
        rb_imemo_mark_and_move(obj, false);
        return;

      default:
        break;
    }

    gc_mark_internal(RBASIC(obj)->klass);

    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
        if (FL_TEST_RAW(obj, FL_SINGLETON)) {
            gc_mark_internal(RCLASS_ATTACHED_OBJECT(obj));
        }
        // Continue to the shared T_CLASS/T_MODULE
      case T_MODULE:
        foreach_args.objspace = objspace;
        foreach_args.obj = obj;
        rb_class_classext_foreach(obj, gc_mark_classext_module, (void *)&foreach_args);
        break;

      case T_ICLASS:
        foreach_args.objspace = objspace;
        foreach_args.obj = obj;
        rb_class_classext_foreach(obj, gc_mark_classext_iclass, (void *)&foreach_args);
        break;

      case T_ARRAY:
        if (ARY_SHARED_P(obj)) {
            VALUE root = ARY_SHARED_ROOT(obj);
            gc_mark_internal(root);
        }
        else {
            long len = RARRAY_LEN(obj);
            const VALUE *ptr = RARRAY_CONST_PTR(obj);
            for (long i = 0; i < len; i++) {
                gc_mark_internal(ptr[i]);
            }
        }
        break;

      case T_HASH:
        mark_hash(obj);
        break;

      case T_SYMBOL:
        gc_mark_internal(RSYMBOL(obj)->fstr);
        break;

      case T_STRING:
        if (STR_SHARED_P(obj)) {
            if (STR_EMBED_P(RSTRING(obj)->as.heap.aux.shared)) {
                /* Embedded shared strings cannot be moved because this string
                 * points into the slot of the shared string. There may be code
                 * using the RSTRING_PTR on the stack, which would pin this
                 * string but not pin the shared string, causing it to move. */
                gc_mark_and_pin_internal(RSTRING(obj)->as.heap.aux.shared);
            }
            else {
                gc_mark_internal(RSTRING(obj)->as.heap.aux.shared);
            }
        }
        break;

      case T_DATA: {
        void *const ptr = RTYPEDDATA_P(obj) ? RTYPEDDATA_GET_DATA(obj) : DATA_PTR(obj);

        if (ptr) {
            if (RTYPEDDATA_P(obj) && gc_declarative_marking_p(RTYPEDDATA_TYPE(obj))) {
                size_t *offset_list = TYPED_DATA_REFS_OFFSET_LIST(obj);

                for (size_t offset = *offset_list; offset != RUBY_REF_END; offset = *offset_list++) {
                    gc_mark_internal(*(VALUE *)((char *)ptr + offset));
                }
            }
            else {
                RUBY_DATA_FUNC mark_func = RTYPEDDATA_P(obj) ?
                    RTYPEDDATA_TYPE(obj)->function.dmark :
                    RDATA(obj)->dmark;
                if (mark_func) (*mark_func)(ptr);
            }
        }

        break;
      }

      case T_OBJECT: {
        if (rb_shape_obj_too_complex_p(obj)) {
            gc_mark_tbl_no_pin(ROBJECT_FIELDS_HASH(obj));
        }
        else {
            const VALUE * const ptr = ROBJECT_FIELDS(obj);

            uint32_t len = ROBJECT_FIELDS_COUNT(obj);
            for (uint32_t i = 0; i < len; i++) {
                gc_mark_internal(ptr[i]);
            }
        }

        attr_index_t fields_count = ROBJECT_FIELDS_COUNT(obj);
        if (fields_count) {
            VALUE klass = RBASIC_CLASS(obj);

            // Increment max_iv_count if applicable, used to determine size pool allocation
            if (RCLASS_MAX_IV_COUNT(klass) < fields_count) {
                RCLASS_SET_MAX_IV_COUNT(klass, fields_count);
            }
        }

        break;
      }

      case T_FILE:
        if (RFILE(obj)->fptr) {
            gc_mark_internal(RFILE(obj)->fptr->self);
            gc_mark_internal(RFILE(obj)->fptr->pathv);
            gc_mark_internal(RFILE(obj)->fptr->tied_io_for_writing);
            gc_mark_internal(RFILE(obj)->fptr->writeconv_asciicompat);
            gc_mark_internal(RFILE(obj)->fptr->writeconv_pre_ecopts);
            gc_mark_internal(RFILE(obj)->fptr->encs.ecopts);
            gc_mark_internal(RFILE(obj)->fptr->write_lock);
            gc_mark_internal(RFILE(obj)->fptr->timeout);
            gc_mark_internal(RFILE(obj)->fptr->wakeup_mutex);
        }
        break;

      case T_REGEXP:
        gc_mark_internal(RREGEXP(obj)->src);
        break;

      case T_MATCH:
        gc_mark_internal(RMATCH(obj)->regexp);
        if (RMATCH(obj)->str) {
            gc_mark_internal(RMATCH(obj)->str);
        }
        break;

      case T_RATIONAL:
        gc_mark_internal(RRATIONAL(obj)->num);
        gc_mark_internal(RRATIONAL(obj)->den);
        break;

      case T_COMPLEX:
        gc_mark_internal(RCOMPLEX(obj)->real);
        gc_mark_internal(RCOMPLEX(obj)->imag);
        break;

      case T_STRUCT: {
        const long len = RSTRUCT_LEN(obj);
        const VALUE * const ptr = RSTRUCT_CONST_PTR(obj);

        for (long i = 0; i < len; i++) {
            gc_mark_internal(ptr[i]);
        }

        break;
      }

      default:
        if (BUILTIN_TYPE(obj) == T_MOVED)   rb_bug("rb_gc_mark(): %p is T_MOVED", (void *)obj);
        if (BUILTIN_TYPE(obj) == T_NONE)   rb_bug("rb_gc_mark(): %p is T_NONE", (void *)obj);
        if (BUILTIN_TYPE(obj) == T_ZOMBIE) rb_bug("rb_gc_mark(): %p is T_ZOMBIE", (void *)obj);
        rb_bug("rb_gc_mark(): unknown data type 0x%x(%p) %s",
               BUILTIN_TYPE(obj), (void *)obj,
               rb_gc_impl_pointer_to_heap_p(objspace, (void *)obj) ? "corrupted object" : "non object");
    }
}

size_t
rb_gc_obj_optimal_size(VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
      case T_ARRAY:
        return rb_ary_size_as_embedded(obj);

      case T_OBJECT:
        if (rb_shape_obj_too_complex_p(obj)) {
            return sizeof(struct RObject);
        }
        else {
            return rb_obj_embedded_size(ROBJECT_FIELDS_CAPACITY(obj));
        }

      case T_STRING:
        return rb_str_size_as_embedded(obj);

      case T_HASH:
        return sizeof(struct RHash) + (RHASH_ST_TABLE_P(obj) ? sizeof(st_table) : sizeof(ar_table));

      default:
        return 0;
    }
}

void
rb_gc_writebarrier(VALUE a, VALUE b)
{
    rb_gc_impl_writebarrier(rb_gc_get_objspace(), a, b);
}

void
rb_gc_writebarrier_unprotect(VALUE obj)
{
    rb_gc_impl_writebarrier_unprotect(rb_gc_get_objspace(), obj);
}

/*
 * remember `obj' if needed.
 */
void
rb_gc_writebarrier_remember(VALUE obj)
{
    rb_gc_impl_writebarrier_remember(rb_gc_get_objspace(), obj);
}

void
rb_gc_copy_attributes(VALUE dest, VALUE obj)
{
    rb_gc_impl_copy_attributes(rb_gc_get_objspace(), dest, obj);
}

int
rb_gc_modular_gc_loaded_p(void)
{
#if USE_MODULAR_GC
    return rb_gc_functions.modular_gc_loaded_p;
#else
    return false;
#endif
}

const char *
rb_gc_active_gc_name(void)
{
    const char *gc_name = rb_gc_impl_active_gc_name();

    const size_t len = strlen(gc_name);
    if (len > RB_GC_MAX_NAME_LEN) {
        rb_bug("GC should have a name no more than %d chars long. Currently: %zu (%s)",
               RB_GC_MAX_NAME_LEN, len, gc_name);
    }

    return gc_name;
}

struct rb_gc_object_metadata_entry *
rb_gc_object_metadata(VALUE obj)
{
    return rb_gc_impl_object_metadata(rb_gc_get_objspace(), obj);
}

/* GC */

void *
rb_gc_ractor_cache_alloc(rb_ractor_t *ractor)
{
    return rb_gc_impl_ractor_cache_alloc(rb_gc_get_objspace(), ractor);
}

void
rb_gc_ractor_cache_free(void *cache)
{
    rb_gc_impl_ractor_cache_free(rb_gc_get_objspace(), cache);
}

void
rb_gc_register_mark_object(VALUE obj)
{
    if (!rb_gc_impl_pointer_to_heap_p(rb_gc_get_objspace(), (void *)obj))
        return;

    rb_vm_register_global_object(obj);
}

void
rb_gc_register_address(VALUE *addr)
{
    rb_vm_t *vm = GET_VM();

    VALUE obj = *addr;

    struct global_object_list *tmp = ALLOC(struct global_object_list);
    tmp->next = vm->global_object_list;
    tmp->varptr = addr;
    vm->global_object_list = tmp;

    /*
     * Because some C extensions have assignment-then-register bugs,
     * we guard `obj` here so that it would not get swept defensively.
     */
    RB_GC_GUARD(obj);
    if (0 && !SPECIAL_CONST_P(obj)) {
        rb_warn("Object is assigned to registering address already: %"PRIsVALUE,
                rb_obj_class(obj));
        rb_print_backtrace(stderr);
    }
}

void
rb_gc_unregister_address(VALUE *addr)
{
    rb_vm_t *vm = GET_VM();
    struct global_object_list *tmp = vm->global_object_list;

    if (tmp->varptr == addr) {
        vm->global_object_list = tmp->next;
        xfree(tmp);
        return;
    }
    while (tmp->next) {
        if (tmp->next->varptr == addr) {
            struct global_object_list *t = tmp->next;

            tmp->next = tmp->next->next;
            xfree(t);
            break;
        }
        tmp = tmp->next;
    }
}

void
rb_global_variable(VALUE *var)
{
    rb_gc_register_address(var);
}

static VALUE
gc_start_internal(rb_execution_context_t *ec, VALUE self, VALUE full_mark, VALUE immediate_mark, VALUE immediate_sweep, VALUE compact)
{
    rb_gc_impl_start(rb_gc_get_objspace(), RTEST(full_mark), RTEST(immediate_mark), RTEST(immediate_sweep), RTEST(compact));

    return Qnil;
}

/*
 * rb_objspace_each_objects() is special C API to walk through
 * Ruby object space.  This C API is too difficult to use it.
 * To be frank, you should not use it. Or you need to read the
 * source code of this function and understand what this function does.
 *
 * 'callback' will be called several times (the number of heap page,
 * at current implementation) with:
 *   vstart: a pointer to the first living object of the heap_page.
 *   vend: a pointer to next to the valid heap_page area.
 *   stride: a distance to next VALUE.
 *
 * If callback() returns non-zero, the iteration will be stopped.
 *
 * This is a sample callback code to iterate liveness objects:
 *
 *   static int
 *   sample_callback(void *vstart, void *vend, int stride, void *data)
 *   {
 *       VALUE v = (VALUE)vstart;
 *       for (; v != (VALUE)vend; v += stride) {
 *           if (!rb_objspace_internal_object_p(v)) { // liveness check
 *               // do something with live object 'v'
 *           }
 *       }
 *       return 0; // continue to iteration
 *   }
 *
 * Note: 'vstart' is not a top of heap_page.  This point the first
 *       living object to grasp at least one object to avoid GC issue.
 *       This means that you can not walk through all Ruby object page
 *       including freed object page.
 *
 * Note: On this implementation, 'stride' is the same as sizeof(RVALUE).
 *       However, there are possibilities to pass variable values with
 *       'stride' with some reasons.  You must use stride instead of
 *       use some constant value in the iteration.
 */
void
rb_objspace_each_objects(int (*callback)(void *, void *, size_t, void *), void *data)
{
    rb_gc_impl_each_objects(rb_gc_get_objspace(), callback, data);
}

static void
gc_ref_update_array(void *objspace, VALUE v)
{
    if (ARY_SHARED_P(v)) {
        VALUE old_root = RARRAY(v)->as.heap.aux.shared_root;

        UPDATE_IF_MOVED(objspace, RARRAY(v)->as.heap.aux.shared_root);

        VALUE new_root = RARRAY(v)->as.heap.aux.shared_root;
        // If the root is embedded and its location has changed
        if (ARY_EMBED_P(new_root) && new_root != old_root) {
            size_t offset = (size_t)(RARRAY(v)->as.heap.ptr - RARRAY(old_root)->as.ary);
            GC_ASSERT(RARRAY(v)->as.heap.ptr >= RARRAY(old_root)->as.ary);
            RARRAY(v)->as.heap.ptr = RARRAY(new_root)->as.ary + offset;
        }
    }
    else {
        long len = RARRAY_LEN(v);

        if (len > 0) {
            VALUE *ptr = (VALUE *)RARRAY_CONST_PTR(v);
            for (long i = 0; i < len; i++) {
                UPDATE_IF_MOVED(objspace, ptr[i]);
            }
        }

        if (rb_gc_obj_slot_size(v) >= rb_ary_size_as_embedded(v)) {
            if (rb_ary_embeddable_p(v)) {
                rb_ary_make_embedded(v);
            }
        }
    }
}

static void
gc_ref_update_object(void *objspace, VALUE v)
{
    VALUE *ptr = ROBJECT_FIELDS(v);

    if (rb_shape_obj_too_complex_p(v)) {
        gc_ref_update_table_values_only(ROBJECT_FIELDS_HASH(v));
        return;
    }

    size_t slot_size = rb_gc_obj_slot_size(v);
    size_t embed_size = rb_obj_embedded_size(ROBJECT_FIELDS_CAPACITY(v));
    if (slot_size >= embed_size && !RB_FL_TEST_RAW(v, ROBJECT_EMBED)) {
        // Object can be re-embedded
        memcpy(ROBJECT(v)->as.ary, ptr, sizeof(VALUE) * ROBJECT_FIELDS_COUNT(v));
        RB_FL_SET_RAW(v, ROBJECT_EMBED);
        xfree(ptr);
        ptr = ROBJECT(v)->as.ary;
    }

    for (uint32_t i = 0; i < ROBJECT_FIELDS_COUNT(v); i++) {
        UPDATE_IF_MOVED(objspace, ptr[i]);
    }
}

void
rb_gc_ref_update_table_values_only(st_table *tbl)
{
    gc_ref_update_table_values_only(tbl);
}

/* Update MOVED references in a VALUE=>VALUE st_table */
void
rb_gc_update_tbl_refs(st_table *ptr)
{
    gc_update_table_refs(ptr);
}

static void
gc_ref_update_hash(void *objspace, VALUE v)
{
    rb_hash_stlike_foreach_with_replace(v, hash_foreach_replace, hash_replace_ref, (st_data_t)objspace);
}

static void
gc_update_values(void *objspace, long n, VALUE *values)
{
    for (long i = 0; i < n; i++) {
        UPDATE_IF_MOVED(objspace, values[i]);
    }
}

void
rb_gc_update_values(long n, VALUE *values)
{
    gc_update_values(rb_gc_get_objspace(), n, values);
}

static enum rb_id_table_iterator_result
check_id_table_move(VALUE value, void *data)
{
    void *objspace = (void *)data;

    if (rb_gc_impl_object_moved_p(objspace, (VALUE)value)) {
        return ID_TABLE_REPLACE;
    }

    return ID_TABLE_CONTINUE;
}

void
rb_gc_prepare_heap_process_object(VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
        // Precompute the string coderange. This both save time for when it will be
        // eventually needed, and avoid mutating heap pages after a potential fork.
        rb_enc_str_coderange(obj);
        break;
      default:
        break;
    }
}

void
rb_gc_prepare_heap(void)
{
    rb_gc_impl_prepare_heap(rb_gc_get_objspace());
}

size_t
rb_gc_heap_id_for_size(size_t size)
{
    return rb_gc_impl_heap_id_for_size(rb_gc_get_objspace(), size);
}

bool
rb_gc_size_allocatable_p(size_t size)
{
    return rb_gc_impl_size_allocatable_p(size);
}

static enum rb_id_table_iterator_result
update_id_table(VALUE *value, void *data, int existing)
{
    void *objspace = (void *)data;

    if (rb_gc_impl_object_moved_p(objspace, (VALUE)*value)) {
        *value = gc_location_internal(objspace, (VALUE)*value);
    }

    return ID_TABLE_CONTINUE;
}

static void
update_m_tbl(void *objspace, struct rb_id_table *tbl)
{
    if (tbl) {
        rb_id_table_foreach_values_with_replace(tbl, check_id_table_move, update_id_table, objspace);
    }
}

static enum rb_id_table_iterator_result
update_cvc_tbl_i(VALUE cvc_entry, void *objspace)
{
    struct rb_cvar_class_tbl_entry *entry;

    entry = (struct rb_cvar_class_tbl_entry *)cvc_entry;

    if (entry->cref) {
        TYPED_UPDATE_IF_MOVED(objspace, rb_cref_t *, entry->cref);
    }

    entry->class_value = gc_location_internal(objspace, entry->class_value);

    return ID_TABLE_CONTINUE;
}

static void
update_cvc_tbl(void *objspace, struct rb_id_table *tbl)
{
    if (!tbl) return;
    rb_id_table_foreach_values(tbl, update_cvc_tbl_i, objspace);
}

static enum rb_id_table_iterator_result
update_const_tbl_i(VALUE value, void *objspace)
{
    rb_const_entry_t *ce = (rb_const_entry_t *)value;

    if (rb_gc_impl_object_moved_p(objspace, ce->value)) {
        ce->value = gc_location_internal(objspace, ce->value);
    }

    if (rb_gc_impl_object_moved_p(objspace, ce->file)) {
        ce->file = gc_location_internal(objspace, ce->file);
    }

    return ID_TABLE_CONTINUE;
}

static void
update_const_tbl(void *objspace, struct rb_id_table *tbl)
{
    if (!tbl) return;
    rb_id_table_foreach_values(tbl, update_const_tbl_i, objspace);
}

static void
update_subclasses(void *objspace, rb_classext_t *ext)
{
    rb_subclass_entry_t *entry;
    rb_subclass_anchor_t *anchor = RCLASSEXT_SUBCLASSES(ext);
    if (!anchor) return;
    entry = anchor->head;
    while (entry) {
        if (entry->klass)
            UPDATE_IF_MOVED(objspace, entry->klass);
        entry = entry->next;
    }
}

static void
update_superclasses(rb_objspace_t *objspace, rb_classext_t *ext)
{
    if (RCLASSEXT_SUPERCLASSES_WITH_SELF(ext)) {
        size_t array_size = RCLASSEXT_SUPERCLASS_DEPTH(ext) + 1;
        for (size_t i = 0; i < array_size; i++) {
            UPDATE_IF_MOVED(objspace, RCLASSEXT_SUPERCLASSES(ext)[i]);
        }
    }
}

static void
update_classext_values(rb_objspace_t *objspace, rb_classext_t *ext, bool is_iclass)
{
    UPDATE_IF_MOVED(objspace, RCLASSEXT_ORIGIN(ext));
    UPDATE_IF_MOVED(objspace, RCLASSEXT_REFINED_CLASS(ext));
    UPDATE_IF_MOVED(objspace, RCLASSEXT_CLASSPATH(ext));
    if (is_iclass) {
        UPDATE_IF_MOVED(objspace, RCLASSEXT_INCLUDER(ext));
    }
}

static void
update_classext(rb_classext_t *ext, bool is_prime, VALUE namespace, void *arg)
{
    struct classext_foreach_args *args = (struct classext_foreach_args *)arg;
    rb_objspace_t *objspace = args->objspace;

    if (RCLASSEXT_SUPER(ext)) {
        UPDATE_IF_MOVED(objspace, RCLASSEXT_SUPER(ext));
    }

    update_m_tbl(objspace, RCLASSEXT_M_TBL(ext));

    UPDATE_IF_MOVED(objspace, ext->fields_obj);
    if (!RCLASSEXT_SHARED_CONST_TBL(ext)) {
        update_const_tbl(objspace, RCLASSEXT_CONST_TBL(ext));
    }
    UPDATE_IF_MOVED(objspace, RCLASSEXT_CC_TBL(ext));
    update_cvc_tbl(objspace, RCLASSEXT_CVC_TBL(ext));
    update_superclasses(objspace, ext);
    update_subclasses(objspace, ext);

    update_classext_values(objspace, ext, false);
}

static void
update_iclass_classext(rb_classext_t *ext, bool is_prime, VALUE namespace, void *arg)
{
    struct classext_foreach_args *args = (struct classext_foreach_args *)arg;
    rb_objspace_t *objspace = args->objspace;

    if (RCLASSEXT_SUPER(ext)) {
        UPDATE_IF_MOVED(objspace, RCLASSEXT_SUPER(ext));
    }
    update_m_tbl(objspace, RCLASSEXT_M_TBL(ext));
    update_m_tbl(objspace, RCLASSEXT_CALLABLE_M_TBL(ext));
    UPDATE_IF_MOVED(objspace, RCLASSEXT_CC_TBL(ext));
    update_subclasses(objspace, ext);

    update_classext_values(objspace, ext, true);
}

struct global_vm_table_foreach_data {
    vm_table_foreach_callback_func callback;
    vm_table_update_callback_func update_callback;
    void *data;
    bool weak_only;
};

static int
vm_weak_table_foreach_weak_key(st_data_t key, st_data_t value, st_data_t data, int error)
{
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;

    int ret = iter_data->callback((VALUE)key, iter_data->data);

    if (!iter_data->weak_only) {
        if (ret != ST_CONTINUE) return ret;

        ret = iter_data->callback((VALUE)value, iter_data->data);
    }

    return ret;
}

static int
vm_weak_table_foreach_update_weak_key(st_data_t *key, st_data_t *value, st_data_t data, int existing)
{
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;

    int ret = iter_data->update_callback((VALUE *)key, iter_data->data);

    if (!iter_data->weak_only) {
        if (ret != ST_CONTINUE) return ret;

        ret = iter_data->update_callback((VALUE *)value, iter_data->data);
    }

    return ret;
}

static int
vm_weak_table_cc_refinement_foreach(st_data_t key, st_data_t data, int error)
{
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;

    return iter_data->callback((VALUE)key, iter_data->data);
}

static int
vm_weak_table_cc_refinement_foreach_update_update(st_data_t *key, st_data_t data, int existing)
{
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;

    return iter_data->update_callback((VALUE *)key, iter_data->data);
}


static int
vm_weak_table_sym_set_foreach(VALUE *sym_ptr, void *data)
{
    VALUE sym = *sym_ptr;
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;

    if (RB_SPECIAL_CONST_P(sym)) return ST_CONTINUE;

    int ret = iter_data->callback(sym, iter_data->data);

    if (ret == ST_REPLACE) {
        ret = iter_data->update_callback(sym_ptr, iter_data->data);
    }

    return ret;
}

struct st_table *rb_generic_fields_tbl_get(void);

static int
vm_weak_table_id2ref_foreach(st_data_t key, st_data_t value, st_data_t data, int error)
{
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;

    if (!iter_data->weak_only && !FIXNUM_P((VALUE)key)) {
        int ret = iter_data->callback((VALUE)key, iter_data->data);
        if (ret != ST_CONTINUE) return ret;
    }

    return iter_data->callback((VALUE)value, iter_data->data);
}

static int
vm_weak_table_id2ref_foreach_update(st_data_t *key, st_data_t *value, st_data_t data, int existing)
{
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;

    iter_data->update_callback((VALUE *)value, iter_data->data);

    if (!iter_data->weak_only && !FIXNUM_P((VALUE)*key)) {
        iter_data->update_callback((VALUE *)key, iter_data->data);
    }

    return ST_CONTINUE;
}

static int
vm_weak_table_gen_fields_foreach(st_data_t key, st_data_t value, st_data_t data)
{
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;

    int ret = iter_data->callback((VALUE)key, iter_data->data);

    VALUE new_value = (VALUE)value;
    VALUE new_key = (VALUE)key;

    switch (ret) {
      case ST_CONTINUE:
        break;

      case ST_DELETE:
        RBASIC_SET_SHAPE_ID((VALUE)key, ROOT_SHAPE_ID);
        return ST_DELETE;

      case ST_REPLACE: {
        ret = iter_data->update_callback(&new_key, iter_data->data);
        if (key != new_key) {
            ret = ST_DELETE;
        }
        break;
      }

      default:
        rb_bug("vm_weak_table_gen_fields_foreach: return value %d not supported", ret);
    }

    if (!iter_data->weak_only) {
        int ivar_ret = iter_data->callback(new_value, iter_data->data);
        switch (ivar_ret) {
          case ST_CONTINUE:
            break;

          case ST_REPLACE:
            iter_data->update_callback(&new_value, iter_data->data);
            break;

          default:
            rb_bug("vm_weak_table_gen_fields_foreach: return value %d not supported", ivar_ret);
        }
    }

    if (key != new_key || value != new_value) {
        DURING_GC_COULD_MALLOC_REGION_START();
        {
            st_insert(rb_generic_fields_tbl_get(), (st_data_t)new_key, new_value);
        }
        DURING_GC_COULD_MALLOC_REGION_END();
    }

    return ret;
}

static int
vm_weak_table_frozen_strings_foreach(VALUE *str, void *data)
{
    // int retval = vm_weak_table_foreach_weak_key(key, value, data, error);
    struct global_vm_table_foreach_data *iter_data = (struct global_vm_table_foreach_data *)data;
    int retval = iter_data->callback(*str, iter_data->data);

    if (retval == ST_REPLACE) {
        retval = iter_data->update_callback(str, iter_data->data);
    }

    if (retval == ST_DELETE) {
        FL_UNSET(*str, RSTRING_FSTR);
    }

    return retval;
}

void rb_fstring_foreach_with_replace(int (*callback)(VALUE *str, void *data), void *data);
void
rb_gc_vm_weak_table_foreach(vm_table_foreach_callback_func callback,
                            vm_table_update_callback_func update_callback,
                            void *data,
                            bool weak_only,
                            enum rb_gc_vm_weak_tables table)
{
    rb_vm_t *vm = GET_VM();

    struct global_vm_table_foreach_data foreach_data = {
        .callback = callback,
        .update_callback = update_callback,
        .data = data,
        .weak_only = weak_only,
    };

    switch (table) {
      case RB_GC_VM_CI_TABLE: {
        if (vm->ci_table) {
            st_foreach_with_replace(
                vm->ci_table,
                vm_weak_table_foreach_weak_key,
                vm_weak_table_foreach_update_weak_key,
                (st_data_t)&foreach_data
            );
        }
        break;
      }
      case RB_GC_VM_OVERLOADED_CME_TABLE: {
        if (vm->overloaded_cme_table) {
            st_foreach_with_replace(
                vm->overloaded_cme_table,
                vm_weak_table_foreach_weak_key,
                vm_weak_table_foreach_update_weak_key,
                (st_data_t)&foreach_data
            );
        }
        break;
      }
      case RB_GC_VM_GLOBAL_SYMBOLS_TABLE: {
        rb_sym_global_symbol_table_foreach_weak_reference(
            vm_weak_table_sym_set_foreach,
            &foreach_data
        );
        break;
      }
      case RB_GC_VM_ID2REF_TABLE: {
        if (id2ref_tbl) {
            st_foreach_with_replace(
                id2ref_tbl,
                vm_weak_table_id2ref_foreach,
                vm_weak_table_id2ref_foreach_update,
                (st_data_t)&foreach_data
            );
        }
        break;
      }
      case RB_GC_VM_GENERIC_FIELDS_TABLE: {
        st_table *generic_fields_tbl = rb_generic_fields_tbl_get();
        if (generic_fields_tbl) {
            st_foreach(
                generic_fields_tbl,
                vm_weak_table_gen_fields_foreach,
                (st_data_t)&foreach_data
            );
        }
        break;
      }
      case RB_GC_VM_FROZEN_STRINGS_TABLE: {
        rb_fstring_foreach_with_replace(
            vm_weak_table_frozen_strings_foreach,
            &foreach_data
        );
        break;
      }
      case RB_GC_VM_CC_REFINEMENT_TABLE: {
        if (vm->cc_refinement_table) {
            set_foreach_with_replace(
              vm->cc_refinement_table,
              vm_weak_table_cc_refinement_foreach,
              vm_weak_table_cc_refinement_foreach_update_update,
              (st_data_t)&foreach_data
            );
        }
        break;
      }
      case RB_GC_VM_WEAK_TABLE_COUNT:
        rb_bug("Unreachable");
      default:
        rb_bug("rb_gc_vm_weak_table_foreach: unknown table %d", table);
    }
}

void
rb_gc_update_vm_references(void *objspace)
{
    rb_execution_context_t *ec = GET_EC();
    rb_vm_t *vm = rb_ec_vm_ptr(ec);

    rb_vm_update_references(vm);
    rb_gc_update_global_tbl();
    rb_sym_global_symbols_update_references();

#if USE_YJIT
    void rb_yjit_root_update_references(void); // in Rust

    if (rb_yjit_enabled_p) {
        rb_yjit_root_update_references();
    }
#endif
}

void
rb_gc_update_object_references(void *objspace, VALUE obj)
{
    struct classext_foreach_args args;

    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
        if (FL_TEST_RAW(obj, FL_SINGLETON)) {
            UPDATE_IF_MOVED(objspace, RCLASS_ATTACHED_OBJECT(obj));
        }
        // Continue to the shared T_CLASS/T_MODULE
      case T_MODULE:
        args.klass = obj;
        args.objspace = objspace;
        rb_class_classext_foreach(obj, update_classext, (void *)&args);
        break;

      case T_ICLASS:
        args.objspace = objspace;
        rb_class_classext_foreach(obj, update_iclass_classext, (void *)&args);
        break;

      case T_IMEMO:
        rb_imemo_mark_and_move(obj, true);
        return;

      case T_NIL:
      case T_FIXNUM:
      case T_NODE:
      case T_MOVED:
      case T_NONE:
        /* These can't move */
        return;

      case T_ARRAY:
        gc_ref_update_array(objspace, obj);
        break;

      case T_HASH:
        gc_ref_update_hash(objspace, obj);
        UPDATE_IF_MOVED(objspace, RHASH(obj)->ifnone);
        break;

      case T_STRING:
        {
            if (STR_SHARED_P(obj)) {
                UPDATE_IF_MOVED(objspace, RSTRING(obj)->as.heap.aux.shared);
            }

            /* If, after move the string is not embedded, and can fit in the
             * slot it's been placed in, then re-embed it. */
            if (rb_gc_obj_slot_size(obj) >= rb_str_size_as_embedded(obj)) {
                if (!STR_EMBED_P(obj) && rb_str_reembeddable_p(obj)) {
                    rb_str_make_embedded(obj);
                }
            }

            break;
        }
      case T_DATA:
        /* Call the compaction callback, if it exists */
        {
            void *const ptr = RTYPEDDATA_P(obj) ? RTYPEDDATA_GET_DATA(obj) : DATA_PTR(obj);
            if (ptr) {
                if (RTYPEDDATA_P(obj) && gc_declarative_marking_p(RTYPEDDATA_TYPE(obj))) {
                    size_t *offset_list = TYPED_DATA_REFS_OFFSET_LIST(obj);

                    for (size_t offset = *offset_list; offset != RUBY_REF_END; offset = *offset_list++) {
                        VALUE *ref = (VALUE *)((char *)ptr + offset);
                        *ref = gc_location_internal(objspace, *ref);
                    }
                }
                else if (RTYPEDDATA_P(obj)) {
                    RUBY_DATA_FUNC compact_func = RTYPEDDATA_TYPE(obj)->function.dcompact;
                    if (compact_func) (*compact_func)(ptr);
                }
            }
        }
        break;

      case T_OBJECT:
        gc_ref_update_object(objspace, obj);
        break;

      case T_FILE:
        if (RFILE(obj)->fptr) {
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->self);
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->pathv);
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->tied_io_for_writing);
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->writeconv_asciicompat);
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->writeconv_pre_ecopts);
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->encs.ecopts);
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->write_lock);
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->timeout);
            UPDATE_IF_MOVED(objspace, RFILE(obj)->fptr->wakeup_mutex);
        }
        break;
      case T_REGEXP:
        UPDATE_IF_MOVED(objspace, RREGEXP(obj)->src);
        break;

      case T_SYMBOL:
        UPDATE_IF_MOVED(objspace, RSYMBOL(obj)->fstr);
        break;

      case T_FLOAT:
      case T_BIGNUM:
        break;

      case T_MATCH:
        UPDATE_IF_MOVED(objspace, RMATCH(obj)->regexp);

        if (RMATCH(obj)->str) {
            UPDATE_IF_MOVED(objspace, RMATCH(obj)->str);
        }
        break;

      case T_RATIONAL:
        UPDATE_IF_MOVED(objspace, RRATIONAL(obj)->num);
        UPDATE_IF_MOVED(objspace, RRATIONAL(obj)->den);
        break;

      case T_COMPLEX:
        UPDATE_IF_MOVED(objspace, RCOMPLEX(obj)->real);
        UPDATE_IF_MOVED(objspace, RCOMPLEX(obj)->imag);

        break;

      case T_STRUCT:
        {
            long i, len = RSTRUCT_LEN(obj);
            VALUE *ptr = (VALUE *)RSTRUCT_CONST_PTR(obj);

            for (i = 0; i < len; i++) {
                UPDATE_IF_MOVED(objspace, ptr[i]);
            }
        }
        break;
      default:
        rb_bug("unreachable");
        break;
    }

    UPDATE_IF_MOVED(objspace, RBASIC(obj)->klass);
}

VALUE
rb_gc_start(void)
{
    rb_gc();
    return Qnil;
}

void
rb_gc(void)
{
    unless_objspace(objspace) { return; }

    rb_gc_impl_start(objspace, true, true, true, false);
}

int
rb_during_gc(void)
{
    unless_objspace(objspace) { return FALSE; }

    return rb_gc_impl_during_gc_p(objspace);
}

size_t
rb_gc_count(void)
{
    return rb_gc_impl_gc_count(rb_gc_get_objspace());
}

static VALUE
gc_count(rb_execution_context_t *ec, VALUE self)
{
    return SIZET2NUM(rb_gc_count());
}

VALUE
rb_gc_latest_gc_info(VALUE key)
{
    if (!SYMBOL_P(key) && !RB_TYPE_P(key, T_HASH)) {
        rb_raise(rb_eTypeError, "non-hash or symbol given");
    }

    VALUE val = rb_gc_impl_latest_gc_info(rb_gc_get_objspace(), key);

    if (val == Qundef) {
        rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(key));
    }

    return val;
}

static VALUE
gc_stat(rb_execution_context_t *ec, VALUE self, VALUE arg) // arg is (nil || hash || symbol)
{
    if (NIL_P(arg)) {
        arg = rb_hash_new();
    }
    else if (!RB_TYPE_P(arg, T_HASH) && !SYMBOL_P(arg)) {
        rb_raise(rb_eTypeError, "non-hash or symbol given");
    }

    VALUE ret = rb_gc_impl_stat(rb_gc_get_objspace(), arg);

    if (ret == Qundef) {
        GC_ASSERT(SYMBOL_P(arg));

        rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(arg));
    }

    return ret;
}

size_t
rb_gc_stat(VALUE arg)
{
    if (!RB_TYPE_P(arg, T_HASH) && !SYMBOL_P(arg)) {
        rb_raise(rb_eTypeError, "non-hash or symbol given");
    }

    VALUE ret = rb_gc_impl_stat(rb_gc_get_objspace(), arg);

    if (ret == Qundef) {
        GC_ASSERT(SYMBOL_P(arg));

        rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(arg));
    }

    if (SYMBOL_P(arg)) {
        return NUM2SIZET(ret);
    }
    else {
        return 0;
    }
}

static VALUE
gc_stat_heap(rb_execution_context_t *ec, VALUE self, VALUE heap_name, VALUE arg)
{
    if (NIL_P(arg)) {
        arg = rb_hash_new();
    }

    if (NIL_P(heap_name)) {
        if (!RB_TYPE_P(arg, T_HASH)) {
            rb_raise(rb_eTypeError, "non-hash given");
        }
    }
    else if (FIXNUM_P(heap_name)) {
        if (!SYMBOL_P(arg) && !RB_TYPE_P(arg, T_HASH)) {
            rb_raise(rb_eTypeError, "non-hash or symbol given");
        }
    }
    else {
        rb_raise(rb_eTypeError, "heap_name must be nil or an Integer");
    }

    VALUE ret = rb_gc_impl_stat_heap(rb_gc_get_objspace(), heap_name, arg);

    if (ret == Qundef) {
        GC_ASSERT(SYMBOL_P(arg));

        rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(arg));
    }

    return ret;
}

static VALUE
gc_config_get(rb_execution_context_t *ec, VALUE self)
{
    VALUE cfg_hash = rb_gc_impl_config_get(rb_gc_get_objspace());
    rb_hash_aset(cfg_hash, sym("implementation"), rb_fstring_cstr(rb_gc_impl_active_gc_name()));

    return cfg_hash;
}

static VALUE
gc_config_set(rb_execution_context_t *ec, VALUE self, VALUE hash)
{
    void *objspace = rb_gc_get_objspace();

    rb_gc_impl_config_set(objspace, hash);

    return rb_gc_impl_config_get(objspace);
}

static VALUE
gc_stress_get(rb_execution_context_t *ec, VALUE self)
{
    return rb_gc_impl_stress_get(rb_gc_get_objspace());
}

static VALUE
gc_stress_set_m(rb_execution_context_t *ec, VALUE self, VALUE flag)
{
    rb_gc_impl_stress_set(rb_gc_get_objspace(), flag);

    return flag;
}

void
rb_gc_initial_stress_set(VALUE flag)
{
    initial_stress = flag;
}

size_t *
rb_gc_heap_sizes(void)
{
    return rb_gc_impl_heap_sizes(rb_gc_get_objspace());
}

VALUE
rb_gc_enable(void)
{
    return rb_objspace_gc_enable(rb_gc_get_objspace());
}

VALUE
rb_objspace_gc_enable(void *objspace)
{
    bool disabled = !rb_gc_impl_gc_enabled_p(objspace);
    rb_gc_impl_gc_enable(objspace);
    return RBOOL(disabled);
}

static VALUE
gc_enable(rb_execution_context_t *ec, VALUE _)
{
    return rb_gc_enable();
}

static VALUE
gc_disable_no_rest(void *objspace)
{
    bool disabled = !rb_gc_impl_gc_enabled_p(objspace);
    rb_gc_impl_gc_disable(objspace, false);
    return RBOOL(disabled);
}

VALUE
rb_gc_disable_no_rest(void)
{
    return gc_disable_no_rest(rb_gc_get_objspace());
}

VALUE
rb_gc_disable(void)
{
    return rb_objspace_gc_disable(rb_gc_get_objspace());
}

VALUE
rb_objspace_gc_disable(void *objspace)
{
    bool disabled = !rb_gc_impl_gc_enabled_p(objspace);
    rb_gc_impl_gc_disable(objspace, true);
    return RBOOL(disabled);
}

static VALUE
gc_disable(rb_execution_context_t *ec, VALUE _)
{
    return rb_gc_disable();
}

// TODO: think about moving ruby_gc_set_params into Init_heap or Init_gc
void
ruby_gc_set_params(void)
{
    rb_gc_impl_set_params(rb_gc_get_objspace());
}

void
rb_objspace_reachable_objects_from(VALUE obj, void (func)(VALUE, void *), void *data)
{
    RB_VM_LOCKING() {
        if (rb_gc_impl_during_gc_p(rb_gc_get_objspace())) rb_bug("rb_objspace_reachable_objects_from() is not supported while during GC");

        if (!RB_SPECIAL_CONST_P(obj)) {
            rb_vm_t *vm = GET_VM();
            struct gc_mark_func_data_struct *prev_mfd = vm->gc.mark_func_data;
            struct gc_mark_func_data_struct mfd = {
                .mark_func = func,
                .data = data,
            };

            vm->gc.mark_func_data = &mfd;
            rb_gc_mark_children(rb_gc_get_objspace(), obj);
            vm->gc.mark_func_data = prev_mfd;
        }
    }
}

struct root_objects_data {
    const char *category;
    void (*func)(const char *category, VALUE, void *);
    void *data;
};

static void
root_objects_from(VALUE obj, void *ptr)
{
    const struct root_objects_data *data = (struct root_objects_data *)ptr;
    (*data->func)(data->category, obj, data->data);
}

void
rb_objspace_reachable_objects_from_root(void (func)(const char *category, VALUE, void *), void *passing_data)
{
    if (rb_gc_impl_during_gc_p(rb_gc_get_objspace())) rb_bug("rb_gc_impl_objspace_reachable_objects_from_root() is not supported while during GC");

    rb_vm_t *vm = GET_VM();

    struct root_objects_data data = {
        .func = func,
        .data = passing_data,
    };

    struct gc_mark_func_data_struct *prev_mfd = vm->gc.mark_func_data;
    struct gc_mark_func_data_struct mfd = {
        .mark_func = root_objects_from,
        .data = &data,
    };

    vm->gc.mark_func_data = &mfd;
    rb_gc_save_machine_context();
    rb_gc_mark_roots(vm->gc.objspace, &data.category);
    vm->gc.mark_func_data = prev_mfd;
}

/*
  ------------------------------ DEBUG ------------------------------
*/

static const char *
type_name(int type, VALUE obj)
{
    switch (type) {
#define TYPE_NAME(t) case (t): return #t;
            TYPE_NAME(T_NONE);
            TYPE_NAME(T_OBJECT);
            TYPE_NAME(T_CLASS);
            TYPE_NAME(T_MODULE);
            TYPE_NAME(T_FLOAT);
            TYPE_NAME(T_STRING);
            TYPE_NAME(T_REGEXP);
            TYPE_NAME(T_ARRAY);
            TYPE_NAME(T_HASH);
            TYPE_NAME(T_STRUCT);
            TYPE_NAME(T_BIGNUM);
            TYPE_NAME(T_FILE);
            TYPE_NAME(T_MATCH);
            TYPE_NAME(T_COMPLEX);
            TYPE_NAME(T_RATIONAL);
            TYPE_NAME(T_NIL);
            TYPE_NAME(T_TRUE);
            TYPE_NAME(T_FALSE);
            TYPE_NAME(T_SYMBOL);
            TYPE_NAME(T_FIXNUM);
            TYPE_NAME(T_UNDEF);
            TYPE_NAME(T_IMEMO);
            TYPE_NAME(T_ICLASS);
            TYPE_NAME(T_MOVED);
            TYPE_NAME(T_ZOMBIE);
      case T_DATA:
        if (obj && rb_objspace_data_type_name(obj)) {
            return rb_objspace_data_type_name(obj);
        }
        return "T_DATA";
#undef TYPE_NAME
    }
    return "unknown";
}

static const char *
obj_type_name(VALUE obj)
{
    return type_name(TYPE(obj), obj);
}

const char *
rb_method_type_name(rb_method_type_t type)
{
    switch (type) {
      case VM_METHOD_TYPE_ISEQ:           return "iseq";
      case VM_METHOD_TYPE_ATTRSET:        return "attrest";
      case VM_METHOD_TYPE_IVAR:           return "ivar";
      case VM_METHOD_TYPE_BMETHOD:        return "bmethod";
      case VM_METHOD_TYPE_ALIAS:          return "alias";
      case VM_METHOD_TYPE_REFINED:        return "refined";
      case VM_METHOD_TYPE_CFUNC:          return "cfunc";
      case VM_METHOD_TYPE_ZSUPER:         return "zsuper";
      case VM_METHOD_TYPE_MISSING:        return "missing";
      case VM_METHOD_TYPE_OPTIMIZED:      return "optimized";
      case VM_METHOD_TYPE_UNDEF:          return "undef";
      case VM_METHOD_TYPE_NOTIMPLEMENTED: return "notimplemented";
    }
    rb_bug("rb_method_type_name: unreachable (type: %d)", type);
}

static void
rb_raw_iseq_info(char *const buff, const size_t buff_size, const rb_iseq_t *iseq)
{
    if (buff_size > 0 && ISEQ_BODY(iseq) && ISEQ_BODY(iseq)->location.label && !RB_TYPE_P(ISEQ_BODY(iseq)->location.pathobj, T_MOVED)) {
        VALUE path = rb_iseq_path(iseq);
        int n = ISEQ_BODY(iseq)->location.first_lineno;
        snprintf(buff, buff_size, " %s@%s:%d",
                 RSTRING_PTR(ISEQ_BODY(iseq)->location.label),
                 RSTRING_PTR(path), n);
    }
}

static int
str_len_no_raise(VALUE str)
{
    long len = RSTRING_LEN(str);
    if (len < 0) return 0;
    if (len > INT_MAX) return INT_MAX;
    return (int)len;
}

#define BUFF_ARGS buff + pos, buff_size - pos
#define APPEND_F(...) if ((pos += snprintf(BUFF_ARGS, "" __VA_ARGS__)) >= buff_size) goto end
#define APPEND_S(s) do { \
        if ((pos + (int)rb_strlen_lit(s)) >= buff_size) { \
            goto end; \
        } \
        else { \
            memcpy(buff + pos, (s), rb_strlen_lit(s) + 1); \
        } \
    } while (0)
#define C(c, s) ((c) != 0 ? (s) : " ")

static size_t
rb_raw_obj_info_common(char *const buff, const size_t buff_size, const VALUE obj)
{
    size_t pos = 0;

    if (SPECIAL_CONST_P(obj)) {
        APPEND_F("%s", obj_type_name(obj));

        if (FIXNUM_P(obj)) {
            APPEND_F(" %ld", FIX2LONG(obj));
        }
        else if (SYMBOL_P(obj)) {
            APPEND_F(" %s", rb_id2name(SYM2ID(obj)));
        }
    }
    else {
        // const int age = RVALUE_AGE_GET(obj);

        if (rb_gc_impl_pointer_to_heap_p(rb_gc_get_objspace(), (void *)obj)) {
            APPEND_F("%p %s/", (void *)obj, obj_type_name(obj));
            // TODO: fixme
            // APPEND_F("%p [%d%s%s%s%s%s%s] %s ",
            //          (void *)obj, age,
            //          C(RVALUE_UNCOLLECTIBLE_BITMAP(obj),  "L"),
            //          C(RVALUE_MARK_BITMAP(obj),           "M"),
            //          C(RVALUE_PIN_BITMAP(obj),            "P"),
            //          C(RVALUE_MARKING_BITMAP(obj),        "R"),
            //          C(RVALUE_WB_UNPROTECTED_BITMAP(obj), "U"),
            //          C(rb_objspace_garbage_object_p(obj), "G"),
            //          obj_type_name(obj));
        }
        else {
            /* fake */
            // APPEND_F("%p [%dXXXX] %s",
            //          (void *)obj, age,
            //          obj_type_name(obj));
        }

        if (internal_object_p(obj)) {
            /* ignore */
        }
        else if (RBASIC(obj)->klass == 0) {
            APPEND_S("(temporary internal)");
        }
        else if (RTEST(RBASIC(obj)->klass)) {
            VALUE class_path = rb_class_path_cached(RBASIC(obj)->klass);
            if (!NIL_P(class_path)) {
                APPEND_F("%s ", RSTRING_PTR(class_path));
            }
        }
    }
  end:

    return pos;
}

const char *rb_raw_obj_info(char *const buff, const size_t buff_size, VALUE obj);

static size_t
rb_raw_obj_info_buitin_type(char *const buff, const size_t buff_size, const VALUE obj, size_t pos)
{
    if (LIKELY(pos < buff_size) && !SPECIAL_CONST_P(obj)) {
        const enum ruby_value_type type = BUILTIN_TYPE(obj);

        switch (type) {
          case T_NODE:
            UNEXPECTED_NODE(rb_raw_obj_info);
            break;
          case T_ARRAY:
            if (ARY_SHARED_P(obj)) {
                APPEND_S("shared -> ");
                rb_raw_obj_info(BUFF_ARGS, ARY_SHARED_ROOT(obj));
            }
            else if (ARY_EMBED_P(obj)) {
                APPEND_F("[%s%s] len: %ld (embed)",
                         C(ARY_EMBED_P(obj),  "E"),
                         C(ARY_SHARED_P(obj), "S"),
                         RARRAY_LEN(obj));
            }
            else {
                APPEND_F("[%s%s] len: %ld, capa:%ld ptr:%p",
                         C(ARY_EMBED_P(obj),  "E"),
                         C(ARY_SHARED_P(obj), "S"),
                         RARRAY_LEN(obj),
                         ARY_EMBED_P(obj) ? -1L : RARRAY(obj)->as.heap.aux.capa,
                         (void *)RARRAY_CONST_PTR(obj));
            }
            break;
          case T_STRING: {
            if (STR_SHARED_P(obj)) {
                APPEND_F(" [shared] len: %ld", RSTRING_LEN(obj));
            }
            else {
                if (STR_EMBED_P(obj)) APPEND_S(" [embed]");

                APPEND_F(" len: %ld, capa: %" PRIdSIZE, RSTRING_LEN(obj), rb_str_capacity(obj));
            }
            APPEND_F(" \"%.*s\"", str_len_no_raise(obj), RSTRING_PTR(obj));
            break;
          }
          case T_SYMBOL: {
            VALUE fstr = RSYMBOL(obj)->fstr;
            ID id = RSYMBOL(obj)->id;
            if (RB_TYPE_P(fstr, T_STRING)) {
                APPEND_F(":%s id:%d", RSTRING_PTR(fstr), (unsigned int)id);
            }
            else {
                APPEND_F("(%p) id:%d", (void *)fstr, (unsigned int)id);
            }
            break;
          }
          case T_MOVED: {
            APPEND_F("-> %p", (void*)gc_location_internal(rb_gc_get_objspace(), obj));
            break;
          }
          case T_HASH: {
            APPEND_F("[%c] %"PRIdSIZE,
                     RHASH_AR_TABLE_P(obj) ? 'A' : 'S',
                     RHASH_SIZE(obj));
            break;
          }
          case T_CLASS:
          case T_MODULE:
            {
                VALUE class_path = rb_class_path_cached(obj);
                if (!NIL_P(class_path)) {
                    APPEND_F("%s", RSTRING_PTR(class_path));
                }
                else {
                    APPEND_S("(anon)");
                }
                break;
            }
          case T_ICLASS:
            {
                VALUE class_path = rb_class_path_cached(RBASIC_CLASS(obj));
                if (!NIL_P(class_path)) {
                    APPEND_F("src:%s", RSTRING_PTR(class_path));
                }
                break;
            }
          case T_OBJECT:
            {
                if (rb_shape_obj_too_complex_p(obj)) {
                    size_t hash_len = rb_st_table_size(ROBJECT_FIELDS_HASH(obj));
                    APPEND_F("(too_complex) len:%zu", hash_len);
                }
                else {
                    uint32_t len = ROBJECT_FIELDS_CAPACITY(obj);

                    if (RBASIC(obj)->flags & ROBJECT_EMBED) {
                        APPEND_F("(embed) len:%d", len);
                    }
                    else {
                        VALUE *ptr = ROBJECT_FIELDS(obj);
                        APPEND_F("len:%d ptr:%p", len, (void *)ptr);
                    }
                }
            }
            break;
          case T_DATA: {
            const struct rb_block *block;
            const rb_iseq_t *iseq;
            if (rb_obj_is_proc(obj) &&
                (block = vm_proc_block(obj)) != NULL &&
                (vm_block_type(block) == block_type_iseq) &&
                (iseq = vm_block_iseq(block)) != NULL) {
                rb_raw_iseq_info(BUFF_ARGS, iseq);
            }
            else if (rb_ractor_p(obj)) {
                rb_ractor_t *r = (void *)DATA_PTR(obj);
                if (r) {
                    APPEND_F("r:%d", r->pub.id);
                }
            }
            else {
                const char * const type_name = rb_objspace_data_type_name(obj);
                if (type_name) {
                    APPEND_F("%s", type_name);
                }
            }
            break;
          }
          case T_IMEMO: {
            APPEND_F("<%s> ", rb_imemo_name(imemo_type(obj)));

            switch (imemo_type(obj)) {
              case imemo_ment:
                {
                    const rb_method_entry_t *me = (const rb_method_entry_t *)obj;

                    APPEND_F(":%s (%s%s%s%s) type:%s aliased:%d owner:%p defined_class:%p",
                             rb_id2name(me->called_id),
                             METHOD_ENTRY_VISI(me) == METHOD_VISI_PUBLIC ?  "pub" :
                             METHOD_ENTRY_VISI(me) == METHOD_VISI_PRIVATE ? "pri" : "pro",
                             METHOD_ENTRY_COMPLEMENTED(me) ? ",cmp" : "",
                             METHOD_ENTRY_CACHED(me) ? ",cc" : "",
                             METHOD_ENTRY_INVALIDATED(me) ? ",inv" : "",
                             me->def ? rb_method_type_name(me->def->type) : "NULL",
                             me->def ? me->def->aliased : -1,
                             (void *)me->owner, // obj_info(me->owner),
                             (void *)me->defined_class); //obj_info(me->defined_class)));

                    if (me->def) {
                        switch (me->def->type) {
                          case VM_METHOD_TYPE_ISEQ:
                            APPEND_S(" (iseq:");
                            rb_raw_obj_info(BUFF_ARGS, (VALUE)me->def->body.iseq.iseqptr);
                            APPEND_S(")");
                            break;
                          default:
                            break;
                        }
                    }

                    break;
                }
              case imemo_iseq: {
                const rb_iseq_t *iseq = (const rb_iseq_t *)obj;
                rb_raw_iseq_info(BUFF_ARGS, iseq);
                break;
              }
              case imemo_callinfo:
                {
                    const struct rb_callinfo *ci = (const struct rb_callinfo *)obj;
                    APPEND_F("(mid:%s, flag:%x argc:%d, kwarg:%s)",
                             rb_id2name(vm_ci_mid(ci)),
                             vm_ci_flag(ci),
                             vm_ci_argc(ci),
                             vm_ci_kwarg(ci) ? "available" : "NULL");
                    break;
                }
              case imemo_callcache:
                {
                    const struct rb_callcache *cc = (const struct rb_callcache *)obj;
                    VALUE class_path = vm_cc_valid(cc) ? rb_class_path_cached(cc->klass) : Qnil;
                    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);

                    APPEND_F("(klass:%s cme:%s%s (%p) call:%p",
                             NIL_P(class_path) ? (vm_cc_valid(cc) ? "??" : "<NULL>") : RSTRING_PTR(class_path),
                             cme ? rb_id2name(cme->called_id) : "<NULL>",
                             cme ? (METHOD_ENTRY_INVALIDATED(cme) ? " [inv]" : "") : "",
                             (void *)cme,
                             (void *)(uintptr_t)vm_cc_call(cc));
                    break;
                }
              default:
                break;
            }
          }
          default:
            break;
        }
    }
  end:

    return pos;
}

#undef C

#ifdef RUBY_ASAN_ENABLED
void
rb_asan_poison_object(VALUE obj)
{
    MAYBE_UNUSED(struct RVALUE *) ptr = (void *)obj;
    asan_poison_memory_region(ptr, rb_gc_obj_slot_size(obj));
}

void
rb_asan_unpoison_object(VALUE obj, bool newobj_p)
{
    MAYBE_UNUSED(struct RVALUE *) ptr = (void *)obj;
    asan_unpoison_memory_region(ptr, rb_gc_obj_slot_size(obj), newobj_p);
}

void *
rb_asan_poisoned_object_p(VALUE obj)
{
    MAYBE_UNUSED(struct RVALUE *) ptr = (void *)obj;
    return __asan_region_is_poisoned(ptr, rb_gc_obj_slot_size(obj));
}
#endif

static void
raw_obj_info(char *const buff, const size_t buff_size, VALUE obj)
{
    size_t pos = rb_raw_obj_info_common(buff, buff_size, obj);
    pos = rb_raw_obj_info_buitin_type(buff, buff_size, obj, pos);
    if (pos >= buff_size) {} // truncated
}

const char *
rb_raw_obj_info(char *const buff, const size_t buff_size, VALUE obj)
{
    void *objspace = rb_gc_get_objspace();

    if (SPECIAL_CONST_P(obj)) {
        raw_obj_info(buff, buff_size, obj);
    }
    else if (!rb_gc_impl_pointer_to_heap_p(objspace, (const void *)obj)) {
        snprintf(buff, buff_size, "out-of-heap:%p", (void *)obj);
    }
#if 0 // maybe no need to check it?
    else if (0 && rb_gc_impl_garbage_object_p(objspace, obj)) {
        snprintf(buff, buff_size, "garbage:%p", (void *)obj);
    }
#endif
    else {
        asan_unpoisoning_object(obj) {
            raw_obj_info(buff, buff_size, obj);
        }
    }
    return buff;
}

#undef APPEND_S
#undef APPEND_F
#undef BUFF_ARGS

#if RGENGC_OBJ_INFO
#define OBJ_INFO_BUFFERS_NUM  10
#define OBJ_INFO_BUFFERS_SIZE 0x100
static rb_atomic_t obj_info_buffers_index = 0;
static char obj_info_buffers[OBJ_INFO_BUFFERS_NUM][OBJ_INFO_BUFFERS_SIZE];

/* Increments *var atomically and resets *var to 0 when maxval is
 * reached. Returns the wraparound old *var value (0...maxval). */
static rb_atomic_t
atomic_inc_wraparound(rb_atomic_t *var, const rb_atomic_t maxval)
{
    rb_atomic_t oldval = RUBY_ATOMIC_FETCH_ADD(*var, 1);
    if (RB_UNLIKELY(oldval >= maxval - 1)) { // wraparound *var
        const rb_atomic_t newval = oldval + 1;
        RUBY_ATOMIC_CAS(*var, newval, newval % maxval);
        oldval %= maxval;
    }
    return oldval;
}

static const char *
obj_info(VALUE obj)
{
    rb_atomic_t index = atomic_inc_wraparound(&obj_info_buffers_index, OBJ_INFO_BUFFERS_NUM);
    char *const buff = obj_info_buffers[index];
    return rb_raw_obj_info(buff, OBJ_INFO_BUFFERS_SIZE, obj);
}
#else
static const char *
obj_info(VALUE obj)
{
    return obj_type_name(obj);
}
#endif

/*
  ------------------------ Extended allocator ------------------------
*/

struct gc_raise_tag {
    VALUE exc;
    const char *fmt;
    va_list *ap;
};

static void *
gc_vraise(void *ptr)
{
    struct gc_raise_tag *argv = ptr;
    rb_vraise(argv->exc, argv->fmt, *argv->ap);
    UNREACHABLE_RETURN(NULL);
}

static void
gc_raise(VALUE exc, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    struct gc_raise_tag argv = {
        exc, fmt, &ap,
    };

    if (ruby_thread_has_gvl_p()) {
        gc_vraise(&argv);
        UNREACHABLE;
    }
    else if (ruby_native_thread_p()) {
        rb_thread_call_with_gvl(gc_vraise, &argv);
        UNREACHABLE;
    }
    else {
        /* Not in a ruby thread */
        fprintf(stderr, "%s", "[FATAL] ");
        vfprintf(stderr, fmt, ap);
    }

    va_end(ap);
    abort();
}

NORETURN(static void negative_size_allocation_error(const char *));
static void
negative_size_allocation_error(const char *msg)
{
    gc_raise(rb_eNoMemError, "%s", msg);
}

static void *
ruby_memerror_body(void *dummy)
{
    rb_memerror();
    return 0;
}

NORETURN(static void ruby_memerror(void));
RBIMPL_ATTR_MAYBE_UNUSED()
static void
ruby_memerror(void)
{
    if (ruby_thread_has_gvl_p()) {
        rb_memerror();
    }
    else {
        if (ruby_native_thread_p()) {
            rb_thread_call_with_gvl(ruby_memerror_body, 0);
        }
        else {
            /* no ruby thread */
            fprintf(stderr, "[FATAL] failed to allocate memory\n");
        }
    }

    /* We have discussions whether we should die here; */
    /* We might rethink about it later. */
    exit(EXIT_FAILURE);
}

void
rb_memerror(void)
{
    /* the `GET_VM()->special_exceptions` below assumes that
     * the VM is reachable from the current thread.  We should
     * definitely make sure of that. */
    RUBY_ASSERT_ALWAYS(ruby_thread_has_gvl_p());

    rb_execution_context_t *ec = GET_EC();
    VALUE exc = GET_VM()->special_exceptions[ruby_error_nomemory];

    if (!exc ||
        rb_ec_raised_p(ec, RAISED_NOMEMORY) ||
        rb_ec_vm_lock_rec(ec) != ec->tag->lock_rec) {
        fprintf(stderr, "[FATAL] failed to allocate memory\n");
        exit(EXIT_FAILURE);
    }
    if (rb_ec_raised_p(ec, RAISED_NOMEMORY)) {
        rb_ec_raised_clear(ec);
    }
    else {
        rb_ec_raised_set(ec, RAISED_NOMEMORY);
        exc = ruby_vm_special_exception_copy(exc);
    }
    ec->errinfo = exc;
    EC_JUMP_TAG(ec, TAG_RAISE);
}

bool
rb_memerror_reentered(void)
{
    rb_execution_context_t *ec = GET_EC();
    return (ec && rb_ec_raised_p(ec, RAISED_NOMEMORY));
}

static void *
handle_malloc_failure(void *ptr)
{
    if (LIKELY(ptr)) {
        return ptr;
    }
    else {
        ruby_memerror();
        UNREACHABLE_RETURN(ptr);
    }
}

static void *ruby_xmalloc_body(size_t size);

void *
ruby_xmalloc(size_t size)
{
    return handle_malloc_failure(ruby_xmalloc_body(size));
}

static void *
ruby_xmalloc_body(size_t size)
{
    if ((ssize_t)size < 0) {
        negative_size_allocation_error("too large allocation size");
    }

    return rb_gc_impl_malloc(rb_gc_get_objspace(), size);
}

void
ruby_malloc_size_overflow(size_t count, size_t elsize)
{
    rb_raise(rb_eArgError,
             "malloc: possible integer overflow (%"PRIuSIZE"*%"PRIuSIZE")",
             count, elsize);
}

void
ruby_malloc_add_size_overflow(size_t x, size_t y)
{
    rb_raise(rb_eArgError,
             "malloc: possible integer overflow (%"PRIuSIZE"+%"PRIuSIZE")",
             x, y);
}

static void *ruby_xmalloc2_body(size_t n, size_t size);

void *
ruby_xmalloc2(size_t n, size_t size)
{
    return handle_malloc_failure(ruby_xmalloc2_body(n, size));
}

static void *
ruby_xmalloc2_body(size_t n, size_t size)
{
    return rb_gc_impl_malloc(rb_gc_get_objspace(), xmalloc2_size(n, size));
}

static void *ruby_xcalloc_body(size_t n, size_t size);

void *
ruby_xcalloc(size_t n, size_t size)
{
    return handle_malloc_failure(ruby_xcalloc_body(n, size));
}

static void *
ruby_xcalloc_body(size_t n, size_t size)
{
    return rb_gc_impl_calloc(rb_gc_get_objspace(), xmalloc2_size(n, size));
}

static void *ruby_sized_xrealloc_body(void *ptr, size_t new_size, size_t old_size);

#ifdef ruby_sized_xrealloc
#undef ruby_sized_xrealloc
#endif
void *
ruby_sized_xrealloc(void *ptr, size_t new_size, size_t old_size)
{
    return handle_malloc_failure(ruby_sized_xrealloc_body(ptr, new_size, old_size));
}

static void *
ruby_sized_xrealloc_body(void *ptr, size_t new_size, size_t old_size)
{
    if ((ssize_t)new_size < 0) {
        negative_size_allocation_error("too large allocation size");
    }

    return rb_gc_impl_realloc(rb_gc_get_objspace(), ptr, new_size, old_size);
}

void *
ruby_xrealloc(void *ptr, size_t new_size)
{
    return ruby_sized_xrealloc(ptr, new_size, 0);
}

static void *ruby_sized_xrealloc2_body(void *ptr, size_t n, size_t size, size_t old_n);

#ifdef ruby_sized_xrealloc2
#undef ruby_sized_xrealloc2
#endif
void *
ruby_sized_xrealloc2(void *ptr, size_t n, size_t size, size_t old_n)
{
    return handle_malloc_failure(ruby_sized_xrealloc2_body(ptr, n, size, old_n));
}

static void *
ruby_sized_xrealloc2_body(void *ptr, size_t n, size_t size, size_t old_n)
{
    size_t len = xmalloc2_size(n, size);
    return rb_gc_impl_realloc(rb_gc_get_objspace(), ptr, len, old_n * size);
}

void *
ruby_xrealloc2(void *ptr, size_t n, size_t size)
{
    return ruby_sized_xrealloc2(ptr, n, size, 0);
}

#ifdef ruby_sized_xfree
#undef ruby_sized_xfree
#endif
void
ruby_sized_xfree(void *x, size_t size)
{
    if (LIKELY(x)) {
        /* It's possible for a C extension's pthread destructor function set by pthread_key_create
         * to be called after ruby_vm_destruct and attempt to free memory. Fall back to mimfree in
         * that case. */
        if (LIKELY(GET_VM())) {
            rb_gc_impl_free(rb_gc_get_objspace(), x, size);
        }
        else {
            ruby_mimfree(x);
        }
    }
}

void
ruby_xfree(void *x)
{
    ruby_sized_xfree(x, 0);
}

void *
rb_xmalloc_mul_add(size_t x, size_t y, size_t z) /* x * y + z */
{
    size_t w = size_mul_add_or_raise(x, y, z, rb_eArgError);
    return ruby_xmalloc(w);
}

void *
rb_xcalloc_mul_add(size_t x, size_t y, size_t z) /* x * y + z */
{
    size_t w = size_mul_add_or_raise(x, y, z, rb_eArgError);
    return ruby_xcalloc(w, 1);
}

void *
rb_xrealloc_mul_add(const void *p, size_t x, size_t y, size_t z) /* x * y + z */
{
    size_t w = size_mul_add_or_raise(x, y, z, rb_eArgError);
    return ruby_xrealloc((void *)p, w);
}

void *
rb_xmalloc_mul_add_mul(size_t x, size_t y, size_t z, size_t w) /* x * y + z * w */
{
    size_t u = size_mul_add_mul_or_raise(x, y, z, w, rb_eArgError);
    return ruby_xmalloc(u);
}

void *
rb_xcalloc_mul_add_mul(size_t x, size_t y, size_t z, size_t w) /* x * y + z * w */
{
    size_t u = size_mul_add_mul_or_raise(x, y, z, w, rb_eArgError);
    return ruby_xcalloc(u, 1);
}

/* Mimic ruby_xmalloc, but need not rb_objspace.
 * should return pointer suitable for ruby_xfree
 */
void *
ruby_mimmalloc(size_t size)
{
    void *mem;
#if CALC_EXACT_MALLOC_SIZE
    size += sizeof(struct malloc_obj_info);
#endif
    mem = malloc(size);
#if CALC_EXACT_MALLOC_SIZE
    if (!mem) {
        return NULL;
    }
    else
    /* set 0 for consistency of allocated_size/allocations */
    {
        struct malloc_obj_info *info = mem;
        info->size = 0;
        mem = info + 1;
    }
#endif
    return mem;
}

void *
ruby_mimcalloc(size_t num, size_t size)
{
    void *mem;
#if CALC_EXACT_MALLOC_SIZE
    struct rbimpl_size_mul_overflow_tag t = rbimpl_size_mul_overflow(num, size);
    if (UNLIKELY(t.left)) {
        return NULL;
    }
    size = t.right + sizeof(struct malloc_obj_info);
    mem = calloc1(size);
    if (!mem) {
        return NULL;
    }
    else
    /* set 0 for consistency of allocated_size/allocations */
    {
        struct malloc_obj_info *info = mem;
        info->size = 0;
        mem = info + 1;
    }
#else
    mem = calloc(num, size);
#endif
    return mem;
}

void
ruby_mimfree(void *ptr)
{
#if CALC_EXACT_MALLOC_SIZE
    struct malloc_obj_info *info = (struct malloc_obj_info *)ptr - 1;
    ptr = info;
#endif
    free(ptr);
}

void
rb_gc_adjust_memory_usage(ssize_t diff)
{
    unless_objspace(objspace) { return; }

    rb_gc_impl_adjust_memory_usage(objspace, diff);
}

const char *
rb_obj_info(VALUE obj)
{
    return obj_info(obj);
}

void
rb_obj_info_dump(VALUE obj)
{
    char buff[0x100];
    fprintf(stderr, "rb_obj_info_dump: %s\n", rb_raw_obj_info(buff, 0x100, obj));
}

void
rb_obj_info_dump_loc(VALUE obj, const char *file, int line, const char *func)
{
    char buff[0x100];
    fprintf(stderr, "<OBJ_INFO:%s@%s:%d> %s\n", func, file, line, rb_raw_obj_info(buff, 0x100, obj));
}

void
rb_gc_before_fork(void)
{
    rb_gc_impl_before_fork(rb_gc_get_objspace());
}

void
rb_gc_after_fork(rb_pid_t pid)
{
    rb_gc_impl_after_fork(rb_gc_get_objspace(), pid);
}

/*
 * Document-module: ObjectSpace
 *
 *  The ObjectSpace module contains a number of routines
 *  that interact with the garbage collection facility and allow you to
 *  traverse all living objects with an iterator.
 *
 *  ObjectSpace also provides support for object finalizers, procs that will be
 *  called after a specific object was destroyed by garbage collection.  See
 *  the documentation for +ObjectSpace.define_finalizer+ for important
 *  information on how to use this method correctly.
 *
 *     a = "A"
 *     b = "B"
 *
 *     ObjectSpace.define_finalizer(a, proc {|id| puts "Finalizer one on #{id}" })
 *     ObjectSpace.define_finalizer(b, proc {|id| puts "Finalizer two on #{id}" })
 *
 *     a = nil
 *     b = nil
 *
 *  _produces:_
 *
 *     Finalizer two on 537763470
 *     Finalizer one on 537763480
 */

/*  Document-class: GC::Profiler
 *
 *  The GC profiler provides access to information on GC runs including time,
 *  length and object space size.
 *
 *  Example:
 *
 *    GC::Profiler.enable
 *
 *    require 'rdoc/rdoc'
 *
 *    GC::Profiler.report
 *
 *    GC::Profiler.disable
 *
 *  See also GC.count, GC.malloc_allocated_size and GC.malloc_allocations
 */

#include "gc.rbinc"

void
Init_GC(void)
{
#undef rb_intern
    rb_gc_register_address(&id2ref_value);

    malloc_offset = gc_compute_malloc_offset();

    rb_mGC = rb_define_module("GC");

    VALUE rb_mObjSpace = rb_define_module("ObjectSpace");

    rb_define_module_function(rb_mObjSpace, "each_object", os_each_obj, -1);

    rb_define_module_function(rb_mObjSpace, "define_finalizer", define_final, -1);
    rb_define_module_function(rb_mObjSpace, "undefine_finalizer", undefine_final, 1);

    rb_define_module_function(rb_mObjSpace, "_id2ref", os_id2ref, 1);

    rb_vm_register_special_exception(ruby_error_nomemory, rb_eNoMemError, "failed to allocate memory");

    rb_define_method(rb_cBasicObject, "__id__", rb_obj_id, 0);
    rb_define_method(rb_mKernel, "object_id", rb_obj_id, 0);

    rb_define_module_function(rb_mObjSpace, "count_objects", count_objects, -1);

    rb_gc_impl_init();
}

// Set a name for the anonymous virtual memory area. `addr` is the starting
// address of the area and `size` is its length in bytes. `name` is a
// NUL-terminated human-readable string.
//
// This function is usually called after calling `mmap()`.  The human-readable
// annotation helps developers identify the call site of `mmap()` that created
// the memory mapping.
//
// This function currently only works on Linux 5.17 or higher.  After calling
// this function, we can see annotations in the form of "[anon:...]" in
// `/proc/self/maps`, where `...` is the content of `name`.  This function has
// no effect when called on other platforms.
void
ruby_annotate_mmap(const void *addr, unsigned long size, const char *name)
{
#if defined(HAVE_SYS_PRCTL_H) && defined(PR_SET_VMA) && defined(PR_SET_VMA_ANON_NAME)
    // The name length cannot exceed 80 (including the '\0').
    RUBY_ASSERT(strlen(name) < 80);
    prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, (unsigned long)addr, size, name);
    // We ignore errors in prctl. prctl may set errno to EINVAL for several
    // reasons.
    // 1. The attr (PR_SET_VMA_ANON_NAME) is not a valid attribute.
    // 2. addr is an invalid address.
    // 3. The string pointed by name is too long.
    // The first error indicates PR_SET_VMA_ANON_NAME is not available, and may
    // happen if we run the compiled binary on an old kernel.  In theory, all
    // other errors should result in a failure.  But since EINVAL cannot tell
    // the first error from others, and this function is mainly used for
    // debugging, we silently ignore the error.
    errno = 0;
#endif
}
