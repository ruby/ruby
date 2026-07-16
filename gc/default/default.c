#include "ruby/internal/config.h"

#include <signal.h>
#include <string.h>

#ifndef _WIN32
# include <sys/mman.h>
# include <unistd.h>
# include <fcntl.h>
# ifdef HAVE_SYS_PRCTL_H
#  include <sys/prctl.h>
# endif
#endif

#if !defined(PAGE_SIZE) && defined(HAVE_SYS_USER_H)
/* LIST_HEAD conflicts with sys/queue.h on macOS */
# include <sys/user.h>
#endif

#ifdef BUILDING_MODULAR_GC
# define nlz_int64(x) (x == 0 ? 64 : (unsigned int)__builtin_clzll((unsigned long long)x))
#else
# include "internal/bits.h"
#endif

#include "ruby/ruby.h"
#include "ruby/atomic.h"
#include "ruby_atomic.h"
#include "ruby/debug.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "ruby/vm.h"
#include "ruby/internal/encoding/string.h"
#include "ccan/list/list.h"
#include "darray.h"
#include "gc/gc.h"
#include "gc/gc_impl.h"
#include "yjit.h"
#include "zjit.h"

#ifdef BUILDING_MODULAR_GC
/* hrtime.h transitively includes internal/time.h -> internal/bits.h, which are
 * not available to out-of-tree modular GC builds.  We only use a monotonic
 * clock plus saturating add/sub, so provide that subset locally with the same
 * semantics as hrtime.h. */
# include <time.h>
typedef uint64_t rb_hrtime_t;
# define RB_HRTIME_PER_SEC ((rb_hrtime_t)1000000000)

static inline rb_hrtime_t
rb_hrtime_now(void)
{
# if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_MONOTONIC)
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
        return (rb_hrtime_t)ts.tv_sec * RB_HRTIME_PER_SEC + (rb_hrtime_t)ts.tv_nsec;
    }
# endif
    return 0;
}

static inline rb_hrtime_t
rb_hrtime_add(rb_hrtime_t a, rb_hrtime_t b)
{
    rb_hrtime_t c = a + b;
    return c < a ? UINT64_MAX : c; /* saturate on overflow */
}

static inline rb_hrtime_t
rb_hrtime_sub(rb_hrtime_t a, rb_hrtime_t b)
{
    return a < b ? 0 : a - b;
}
#else
# include "hrtime.h"
#endif

#include "probes.h"

#define RUBY_DTRACE_GC_HOOK(name, ...) \
    do {if (RUBY_DTRACE_GC_##name##_ENABLED()) RUBY_DTRACE_GC_##name(__VA_ARGS__);} while (0)

#if USE_ZJIT
# include "gc/default/zjit_fastpath.h"
#endif

#ifdef BUILDING_MODULAR_GC
# define RB_DEBUG_COUNTER_INC(_name) ((void)0)
# define RB_DEBUG_COUNTER_INC_IF(_name, cond) (!!(cond))
#else
# include "debug_counter.h"
#endif

#ifdef BUILDING_MODULAR_GC
# define rb_asan_poison_object(obj) ((void)(obj))
# define rb_asan_unpoison_object(obj, newobj_p) ((void)(obj), (void)(newobj_p))
# define asan_unpoisoning_object(obj) if ((obj) || true)
# define asan_poison_memory_region(ptr, size) ((void)(ptr), (void)(size))
# define asan_unpoison_memory_region(ptr, size, malloc_p) ((void)(ptr), (size), (malloc_p))
# define asan_unpoisoning_memory_region(ptr, size) if ((ptr) || (size) || true)

# define VALGRIND_MAKE_MEM_DEFINED(ptr, size) ((void)(ptr), (void)(size))
# define VALGRIND_MAKE_MEM_UNDEFINED(ptr, size) ((void)(ptr), (void)(size))
#else
# include "internal/sanitizers.h"
#endif

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

#ifdef HAVE_MALLOC_TRIM
# include <malloc.h>

# ifdef __EMSCRIPTEN__
/* malloc_trim is defined in emscripten/emmalloc.h on emscripten. */
#  include <emscripten/emmalloc.h>
# endif
#endif

#ifdef HAVE_MACH_TASK_EXCEPTION_PORTS
# include <mach/task.h>
# include <mach/mach_init.h>
# include <mach/mach_port.h>
#endif

#ifndef RUBY_DEBUG_LOG
# define RUBY_DEBUG_LOG(...)
#endif

#ifndef GC_HEAP_INIT_BYTES
#define GC_HEAP_INIT_BYTES (2560 * 1024)
#endif
#ifndef GC_HEAP_FREE_SLOTS
#define GC_HEAP_FREE_SLOTS  4096
#endif
#ifndef GC_HEAP_GROWTH_FACTOR
#define GC_HEAP_GROWTH_FACTOR 1.8
#endif
#ifndef GC_HEAP_GROWTH_MAX_BYTES
#define GC_HEAP_GROWTH_MAX_BYTES 0 /* 0 is disable */
#endif
#ifndef GC_HEAP_REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO
# define GC_HEAP_REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO 0.01
#endif
#ifndef GC_HEAP_OLDOBJECT_LIMIT_FACTOR
#define GC_HEAP_OLDOBJECT_LIMIT_FACTOR 2.0
#endif

#ifndef GC_HEAP_FREE_SLOTS_MIN_RATIO
#define GC_HEAP_FREE_SLOTS_MIN_RATIO  0.20
#endif
#ifndef GC_HEAP_FREE_SLOTS_GOAL_RATIO
#define GC_HEAP_FREE_SLOTS_GOAL_RATIO 0.40
#endif
#ifndef GC_HEAP_FREE_SLOTS_MAX_RATIO
#define GC_HEAP_FREE_SLOTS_MAX_RATIO  0.65
#endif

#ifndef GC_MALLOC_LIMIT_MIN
#define GC_MALLOC_LIMIT_MIN (16 * 1024 * 1024 /* 16MB */)
#endif
#ifndef GC_MALLOC_LIMIT_MAX
#define GC_MALLOC_LIMIT_MAX (32 * 1024 * 1024 /* 32MB */)
#endif
#ifndef GC_MALLOC_LIMIT_GROWTH_FACTOR
#define GC_MALLOC_LIMIT_GROWTH_FACTOR 1.4
#endif

#ifndef GC_OLDMALLOC_LIMIT_MIN
#define GC_OLDMALLOC_LIMIT_MIN (16 * 1024 * 1024 /* 16MB */)
#endif
#ifndef GC_OLDMALLOC_LIMIT_GROWTH_FACTOR
#define GC_OLDMALLOC_LIMIT_GROWTH_FACTOR 1.2
#endif
#ifndef GC_OLDMALLOC_LIMIT_MAX
#define GC_OLDMALLOC_LIMIT_MAX (128 * 1024 * 1024 /* 128MB */)
#endif

#ifndef GC_MALLOC_INCREASE_LOCAL_THRESHOLD
#define GC_MALLOC_INCREASE_LOCAL_THRESHOLD (8 * 1024 /* 8KB */)
#endif

#ifdef RB_THREAD_LOCAL_SPECIFIER
#define USE_MALLOC_INCREASE_LOCAL 1
static RB_THREAD_LOCAL_SPECIFIER int malloc_increase_local;
#else
#define USE_MALLOC_INCREASE_LOCAL 0
#endif

#ifndef GC_CAN_COMPILE_COMPACTION
#if defined(__wasi__) /* WebAssembly doesn't support signals */
# define GC_CAN_COMPILE_COMPACTION 0
#else
# define GC_CAN_COMPILE_COMPACTION 1
#endif
#endif

#ifndef PRINT_ENTER_EXIT_TICK
# define PRINT_ENTER_EXIT_TICK 0
#endif
#ifndef PRINT_ROOT_TICKS
#define PRINT_ROOT_TICKS 0
#endif

#define USE_TICK_T                 (PRINT_ENTER_EXIT_TICK || PRINT_ROOT_TICKS)

#ifndef HEAP_COUNT
# if SIZEOF_VALUE >= 8
#  define HEAP_COUNT 12
# else
#  define HEAP_COUNT 5
# endif
#endif

/* The reciprocal table and pool_slot_sizes array are both generated from this
 * single definition, so they can never get out of sync. */
#if SIZEOF_VALUE >= 8
# define EACH_POOL_SLOT_SIZE(SLOT) \
    SLOT(32) SLOT(40) SLOT(64) SLOT(80) SLOT(96) SLOT(128) \
    SLOT(160) SLOT(256) SLOT(512) SLOT(640) SLOT(768) SLOT(1024)
#else
# define EACH_POOL_SLOT_SIZE(SLOT) \
    SLOT(32) SLOT(64) SLOT(128) SLOT(256) SLOT(512)
#endif

typedef struct {
    size_t heap_init_bytes;
    size_t heap_free_slots;
    double growth_factor;
    size_t growth_max_bytes;

    double heap_free_slots_min_ratio;
    double heap_free_slots_goal_ratio;
    double heap_free_slots_max_ratio;
    double uncollectible_wb_unprotected_objects_limit_ratio;
    double oldobject_limit_factor;

    size_t malloc_limit_min;
    size_t malloc_limit_max;
    double malloc_limit_growth_factor;

    size_t oldmalloc_limit_min;
    size_t oldmalloc_limit_max;
    double oldmalloc_limit_growth_factor;
} ruby_gc_params_t;

static ruby_gc_params_t gc_params = {
    GC_HEAP_INIT_BYTES,
    GC_HEAP_FREE_SLOTS,
    GC_HEAP_GROWTH_FACTOR,
    GC_HEAP_GROWTH_MAX_BYTES,

    GC_HEAP_FREE_SLOTS_MIN_RATIO,
    GC_HEAP_FREE_SLOTS_GOAL_RATIO,
    GC_HEAP_FREE_SLOTS_MAX_RATIO,
    GC_HEAP_REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO,
    GC_HEAP_OLDOBJECT_LIMIT_FACTOR,

    GC_MALLOC_LIMIT_MIN,
    GC_MALLOC_LIMIT_MAX,
    GC_MALLOC_LIMIT_GROWTH_FACTOR,

    GC_OLDMALLOC_LIMIT_MIN,
    GC_OLDMALLOC_LIMIT_MAX,
    GC_OLDMALLOC_LIMIT_GROWTH_FACTOR,
};

/* GC_DEBUG:
 *  enable to embed GC debugging information.
 */
#ifndef GC_DEBUG
#define GC_DEBUG 0
#endif

/* RGENGC_DEBUG:
 * 1: basic information
 * 2: remember set operation
 * 3: mark
 * 4:
 * 5: sweep
 */
#ifndef RGENGC_DEBUG
#ifdef RUBY_DEVEL
#define RGENGC_DEBUG       -1
#else
#define RGENGC_DEBUG       0
#endif
#endif
#if RGENGC_DEBUG < 0 && !defined(_MSC_VER)
# define RGENGC_DEBUG_ENABLED(level) (-(RGENGC_DEBUG) >= (level) && ruby_rgengc_debug >= (level))
#else
# define RGENGC_DEBUG_ENABLED(level) ((RGENGC_DEBUG) >= (level))
#endif
int ruby_rgengc_debug;

/* RGENGC_PROFILE
 * 0: disable RGenGC profiling
 * 1: enable profiling for basic information
 * 2: enable profiling for each types
 */
#ifndef RGENGC_PROFILE
# define RGENGC_PROFILE     0
#endif

/* RGENGC_ESTIMATE_OLDMALLOC
 * Enable/disable to estimate increase size of malloc'ed size by old objects.
 * If estimation exceeds threshold, then will invoke full GC.
 * 0: disable estimation.
 * 1: enable estimation.
 */
#ifndef RGENGC_ESTIMATE_OLDMALLOC
# define RGENGC_ESTIMATE_OLDMALLOC 1
#endif

#ifndef GC_PROFILE_MORE_DETAIL
# define GC_PROFILE_MORE_DETAIL 0
#endif
#ifndef GC_PROFILE_DETAIL_MEMORY
# define GC_PROFILE_DETAIL_MEMORY 0
#endif
#ifndef GC_ENABLE_LAZY_SWEEP
# define GC_ENABLE_LAZY_SWEEP   1
#endif

#ifndef VERIFY_FREE_SIZE
#if RUBY_DEBUG
#define VERIFY_FREE_SIZE 1
#else
#define VERIFY_FREE_SIZE 0
#endif
#endif

#if VERIFY_FREE_SIZE
#undef CALC_EXACT_MALLOC_SIZE
#define CALC_EXACT_MALLOC_SIZE 1
#endif

#ifndef CALC_EXACT_MALLOC_SIZE
# define CALC_EXACT_MALLOC_SIZE 0
#endif

#if defined(HAVE_MALLOC_USABLE_SIZE) || CALC_EXACT_MALLOC_SIZE > 0
# ifndef MALLOC_ALLOCATED_SIZE
#  define MALLOC_ALLOCATED_SIZE 0
# endif
#else
# define MALLOC_ALLOCATED_SIZE 0
#endif
#ifndef MALLOC_ALLOCATED_SIZE_CHECK
# define MALLOC_ALLOCATED_SIZE_CHECK 0
#endif

#ifndef GC_DEBUG_STRESS_TO_CLASS
# define GC_DEBUG_STRESS_TO_CLASS RUBY_DEBUG
#endif

typedef enum {
    GPR_FLAG_NONE               = 0x000,
    /* major reason */
    GPR_FLAG_MAJOR_BY_NOFREE    = 0x001,
    GPR_FLAG_MAJOR_BY_OLDGEN    = 0x002,
    GPR_FLAG_MAJOR_BY_SHADY     = 0x004,
    GPR_FLAG_MAJOR_BY_FORCE     = 0x008,
#if RGENGC_ESTIMATE_OLDMALLOC
    GPR_FLAG_MAJOR_BY_OLDMALLOC = 0x020,
#endif
    GPR_FLAG_MAJOR_MASK         = 0x0ff,

    /* gc reason */
    GPR_FLAG_NEWOBJ             = 0x100,
    GPR_FLAG_MALLOC             = 0x200,
    GPR_FLAG_METHOD             = 0x400,
    GPR_FLAG_CAPI               = 0x800,
    GPR_FLAG_STRESS            = 0x1000,

    /* others */
    GPR_FLAG_IMMEDIATE_SWEEP   = 0x2000,
    GPR_FLAG_HAVE_FINALIZE     = 0x4000,
    GPR_FLAG_IMMEDIATE_MARK    = 0x8000,
    GPR_FLAG_FULL_MARK        = 0x10000,
    GPR_FLAG_COMPACT          = 0x20000,

    GPR_DEFAULT_REASON =
        (GPR_FLAG_FULL_MARK | GPR_FLAG_IMMEDIATE_MARK |
         GPR_FLAG_IMMEDIATE_SWEEP | GPR_FLAG_CAPI),
} gc_profile_record_flag;

typedef struct gc_profile_record {
    unsigned int flags;
    size_t sequence;

    double gc_time;
    double gc_invoke_time;
    rb_hrtime_t gc_wall_time;
    rb_hrtime_t gc_invoke_wall_time;
    rb_hrtime_t gc_pause_time;
    rb_hrtime_t gc_stop_time;
    rb_hrtime_t gc_stw_time;
    rb_hrtime_t gc_mark_wall_time;
    rb_hrtime_t gc_sweep_wall_time;
    rb_hrtime_t gc_compact_wall_time;

    size_t heap_total_objects;
    size_t heap_use_size;
    size_t heap_total_size;
    size_t moved_objects;

#if GC_PROFILE_MORE_DETAIL
    double gc_mark_time;
    double gc_sweep_time;

    size_t heap_use_pages;
    size_t heap_live_objects;
    size_t heap_free_objects;

    size_t allocate_increase;
    size_t allocate_limit;

    double prepare_time;
    size_t removing_objects;
    size_t empty_objects;
#if GC_PROFILE_DETAIL_MEMORY
    long maxrss;
    long minflt;
    long majflt;
#endif
#endif
#if MALLOC_ALLOCATED_SIZE
    size_t allocated_size;
#endif

#if RGENGC_PROFILE > 0
    size_t old_objects;
    size_t remembered_normal_objects;
    size_t remembered_shady_objects;
#endif
} gc_profile_record;

struct RMoved {
    VALUE flags;
    VALUE dummy;
    VALUE destination;
};

#define RMOVED(obj) ((struct RMoved *)(obj))

typedef uintptr_t bits_t;
enum {
    BITS_SIZE = sizeof(bits_t),
    BITS_BITLENGTH = ( BITS_SIZE * CHAR_BIT )
};

struct heap_page_header {
    struct heap_page *page;
};

struct heap_page_body {
    struct heap_page_header header;
    /* char gap[];      */
    /* RVALUE values[]; */
};

#define STACK_CHUNK_SIZE 500

typedef struct stack_chunk {
    VALUE data[STACK_CHUNK_SIZE];
    struct stack_chunk *next;
} stack_chunk_t;

typedef struct mark_stack {
    stack_chunk_t *chunk;
    stack_chunk_t *cache;
    int index;
    int limit;
    size_t cache_size;
    size_t unused_cache_size;
} mark_stack_t;

typedef int (*gc_compact_compare_func)(const void *l, const void *r, void *d);

typedef struct rb_heap_struct {
    short slot_size;

    /* Basic statistics */
    size_t total_allocated_pages;
    size_t force_major_gc_count;
    size_t force_incremental_marking_finish_count;
    size_t total_allocated_objects;
    size_t total_freed_objects;
    size_t final_slots_count;

    /* Sweeping statistics */
    size_t freed_slots;
    size_t empty_slots;

    /* bump-pointer 割り当ての状態。この objspace の所有者スレッドだけが書き込む。 */
    uintptr_t alloc_cursor;
    uintptr_t alloc_cursor_end;
    struct free_region *alloc_next_region;
    struct heap_page *alloc_using_page;

    struct heap_page *free_pages;
    struct ccan_list_head pages;
    struct heap_page *sweeping_page; /* iterator for .pages */
    struct heap_page *compact_cursor;
    uintptr_t compact_cursor_index;
    struct heap_page *pooled_pages;
    size_t total_pages;      /* total page count in a heap */
    size_t total_slots;      /* total slot count */

} rb_heap_t;

enum {
    gc_stress_no_major,
    gc_stress_no_immediate_sweep,
    gc_stress_full_mark_after_malloc,
    gc_stress_max
};

enum gc_mode {
    gc_mode_none,
    gc_mode_marking,
    gc_mode_sweeping,
    gc_mode_compacting,
};

typedef rbimpl_atomic_uint64_t gc_counter_t;

#if !defined(HAVE_GCC_ATOMIC_BUILTINS_64) && !defined(_WIN32) && \
    !(defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx)))
# define MALLOC_COUNTERS_NEED_LOCK 1
#endif

struct gc_malloc_bytes {
    gc_counter_t malloc;
    gc_counter_t free;

    /* Snapshots of `malloc` / `free` taken at the end of the last GC */
    gc_counter_t malloc_at_last_gc;
    gc_counter_t free_at_last_gc;
};

typedef struct rb_objspace {
    struct {
        struct gc_malloc_bytes counters;
#if RGENGC_ESTIMATE_OLDMALLOC
        struct gc_malloc_bytes oldcounters;
#endif
#ifdef MALLOC_COUNTERS_NEED_LOCK
        rb_nativethread_lock_t lock;
#endif
    } malloc_counters;

    struct {
        size_t limit;
#if MALLOC_ALLOCATED_SIZE
        size_t allocated_size;
        size_t allocations;
#endif
    } malloc_params;

    struct rb_gc_config {
        bool full_mark;
    } gc_config;

    struct {
        unsigned int mode : 2;
        unsigned int immediate_sweep : 1;
        unsigned int dont_gc : 1;
        unsigned int dont_incremental : 1;
        unsigned int during_gc : 1;
        unsigned int during_compacting : 1;
        unsigned int gc_lock_barrier : 1;
        unsigned int during_reference_updating : 1;
        unsigned int gc_stressful: 1;
        unsigned int during_minor_gc : 1;
        unsigned int during_incremental_marking : 1;
        unsigned int measure_gc : 1;
    } flags;

    unsigned char during_global_gc;

    rb_event_flag_t hook_events;

    rb_heap_t heaps[HEAP_COUNT];
    size_t empty_pages_count;
    struct heap_page *empty_pages;

    struct {
        rb_atomic_t finalizing;
    } atomic_flags;

    mark_stack_t mark_stack;
    size_t marked_slots;

    /* 割り当ては objspace ごとに 1 つ。 */
    size_t incremental_mark_step_allocated_slots;

    /* global GC 起動判定の入力。すべてこの objspace のスレッドが所有する。
     * shareable_objects は shareable の生存数。stalled_shareables は前回の local GC が
     * pin だけで生かした（global GC のみが回収できる）オブジェクト数の上限。 */
    struct {
        size_t shareable_objects;
        size_t shareable_objects_limit;
        size_t stalled_shareables;
        /* 直近の mark が pinned walk を実行したか。sweep の assert が参照する。 */
        unsigned char last_cycle_pinned;
    } rlgc;

    struct {
        rb_darray(struct heap_page *) sorted;

        size_t allocated_pages;
        size_t freed_pages;
        uintptr_t range[2];
        size_t freeable_pages;

        size_t allocatable_bytes;

        /* final */
        VALUE deferred_final;
    } heap_pages;

    st_table *finalizer_table;

    struct {
        int run;
        unsigned int latest_gc_info;
        gc_profile_record *records;
        gc_profile_record *current_record;
        size_t next_index;
        size_t size;
        size_t record_count;
        size_t max_records;
        size_t record_sequence;

#if GC_PROFILE_MORE_DETAIL
        double prepare_time;
#endif
        double invoke_time;
        rb_hrtime_t invoke_wall_time;

        size_t minor_gc_count;
        size_t major_gc_count;
        size_t compact_count;
        size_t read_barrier_faults;
#if RGENGC_PROFILE > 0
        size_t total_generated_normal_object_count;
        size_t total_generated_shady_object_count;
        size_t total_shade_operation_count;
        size_t total_promoted_count;
        size_t total_remembered_normal_object_count;
        size_t total_remembered_shady_object_count;

#if RGENGC_PROFILE >= 2
        size_t generated_normal_object_count_types[RUBY_T_MASK];
        size_t generated_shady_object_count_types[RUBY_T_MASK];
        size_t shade_operation_count_types[RUBY_T_MASK];
        size_t promoted_types[RUBY_T_MASK];
        size_t remembered_normal_object_count_types[RUBY_T_MASK];
        size_t remembered_shady_object_count_types[RUBY_T_MASK];
#endif
#endif /* RGENGC_PROFILE */

        /* temporary profiling space */
        double gc_sweep_start_time;
        rb_hrtime_t gc_wall_start_time;
        rb_hrtime_t gc_sweep_wall_start_time;
        rb_hrtime_t gc_sweep_excluded_wall_time;
        rb_hrtime_t gc_pause_start_time;
        rb_hrtime_t gc_stw_start_time;
        rb_hrtime_t gc_stop_time;
        rb_hrtime_t gc_mark_phase_wall_start_time;
        rb_hrtime_t gc_sweep_phase_wall_start_time;
        size_t total_allocated_objects_at_gc_start;
        size_t heap_used_at_gc_start;
        size_t heap_total_slots_at_gc_start;

        /* basic statistics */
        size_t count;
        unsigned long long marking_time_ns;
        struct timespec marking_start_time;
        unsigned long long sweeping_time_ns;
        struct timespec sweeping_start_time;

        /* Weak references */
        size_t weak_references_count;
    } profile;

    VALUE gc_stress_mode;

    struct {
        bool parent_object_old_p;
        VALUE parent_object;

        int need_major_gc;
        size_t last_major_gc;
        size_t uncollectible_wb_unprotected_objects;
        size_t uncollectible_wb_unprotected_objects_limit;
        size_t old_objects;
        size_t old_objects_limit;

#if RGENGC_ESTIMATE_OLDMALLOC
        size_t oldmalloc_increase_limit;
#endif

#if RGENGC_CHECK_MODE >= 2
        struct st_table *allrefs_table;
        size_t error_count;
#endif
    } rgengc;

    struct {
        size_t considered_count_table[T_MASK];
        size_t moved_count_table[T_MASK];
        size_t moved_up_count_table[T_MASK];
        size_t moved_down_count_table[T_MASK];
        size_t total_moved;

        /* This function will be used, if set, to sort the heap prior to compaction */
        gc_compact_compare_func compare_func;
    } rcompactor;

    struct {
        size_t pooled_slots;
        size_t step_slots;
    } rincgc;

#if GC_DEBUG_STRESS_TO_CLASS
    VALUE stress_to_class;
#endif

    rb_darray(VALUE) weak_references;
    rb_postponed_job_handle_t finalize_deferred_pjob;

    unsigned long live_ractor_cache_count;

    int sweeping_heap_count;

    int fork_vm_lock_lev;

    struct rb_gc_vm_context vm_context;
} rb_objspace_t;

/* 唯一の VM グローバル GC 構造。今は page pool のみを持つ。heap page body を大きな
 * mmap アリーナから切り出しプロセス共通の freelist で再利用し、ページ単位の
 * mmap/munmap（カーネルの mmap_lock を全スレッドで直列化する）を避ける。
 * lock は leaf lock で、保持中は割り当ても GC もしない。 */
struct rlgc_page_arena {
    struct rlgc_page_arena *next;
    char *start;                /* HEAP_PAGE_ALIGN 整列の使用可能領域 */
    size_t size;                /* 使用可能バイト数（HEAP_PAGE_SIZE の倍数） */
};

typedef struct rb_global_objspace {
    struct {
        rb_nativethread_lock_t lock;
        struct heap_page_body *freelist; /* 再利用する body。next ポインタは body 内に置く */
        struct rlgc_page_arena *arenas;  /* 全アリーナ。新しい順 */
        char *arena_cursor;              /* 最新アリーナの未切り出しの先頭 body */
        char *arena_end;
    } page_pool;
} rb_global_objspace_t;

static rb_global_objspace_t rb_global_objspace_instance;
static rb_global_objspace_t *global_objspace = NULL;

/* floor は shareable が少し出来ただけで global GC が走るのを防ぐ。factor は
 * old 世代 limit の規則に倣う。 */
#define RLGC_SHAREABLE_LIMIT_MIN (1 << 16)
#define RLGC_SHAREABLE_LIMIT_FACTOR 2.0
/* 終了して未継承の Ractor がこれだけの heap page を保持したら global GC を起動する
 * （小さな Ractor の objspace は約 13 ページなので大量廃棄でも越えにくく、肥えた
 * zombie は 1 つで越える）。 */
#define RLGC_ZOMBIE_PAGES_TRIGGER 256

/* mark/sweep の述語は objspace ごとの during_global_gc を見る。これは driver が
 * barrier 下で取る反復用スナップショット。 */
static struct {
    bool active;
    /* compacting global GC の move 相の間 true。gc_sweep_compact は全 objspace を
     * 移動させるが、全 forwarding pointer が揃うまで参照更新（gc_compact_finish）を
     * 遅延させる 2 相方式。cross-objspace 参照を 1 度だけ書き換えるため。 */
    bool compacting;
    struct rb_objspace **list;
    size_t count, capa;
} rlgc_global;

/* 死んだ Ractor の objspace を別へ併合中は true。併合中は VM グローバル root 表が
 * 未併合の src を指しオブジェクトも移動途中なので、verifier の cross-objspace 検査は
 * 一時的な非 heap/foreign エッジを見る。この間は抑止し、次の通常 GC が検証する。 */
static bool rlgc_during_absorb = false;

/* world 停止中の verify（VM lock+barrier を取る GC.verify、または barrier を持つ
 * global GC）でのみ true。cross-objspace 検査は全 objspace のページを走査するため
 * world 停止時のみ健全で、mid-local-GC の verify では他 Ractor の
 * lock-free 割り当てと競合する（SEGV）。false 時は当該検査をスキップする。 */
static bool rlgc_verify_world_stopped = false;

static void rlgc_objspace_absorb(rb_objspace_t *dst, rb_objspace_t *src);

/* gc_enter のロック方針が使う main の objspace。Ractor 生成中に
 * main_ractor->objspace が一時的に差し替わるため、GC の両端で同じ判定をするよう
 * 安定したポインタを別に持つ。起動時に設定し、fork した子では貼り直す。 */
static rb_objspace_t *rlgc_main_objspace;

static struct heap_page_body *page_pool_acquire(void);
static void page_pool_release(struct heap_page_body *body);

static void
global_objspace_init(void)
{
    if (global_objspace == NULL) {
        rb_global_objspace_t *g = &rb_global_objspace_instance;
        rb_native_mutex_initialize(&g->page_pool.lock);
        g->page_pool.freelist = NULL;
        g->page_pool.arenas = NULL;
        g->page_pool.arena_cursor = NULL;
        g->page_pool.arena_end = NULL;
        global_objspace = g;
    }
}

void *
rb_gc_impl_global_objspace_alloc(void)
{
    global_objspace_init();

    return global_objspace;
}

#ifndef HEAP_PAGE_ALIGN_LOG
/* default tiny heap size: 64KiB */
#define HEAP_PAGE_ALIGN_LOG 16
#endif

#if RB_GC_OBJ_HAS_SUFFIX || GC_DEBUG
struct rvalue_overhead {
# if RB_GC_OBJ_HAS_SUFFIX
    struct rb_gc_obj_suffix suffix;
# endif
# if GC_DEBUG
    const char *file;
    int line;
# endif
};

// Make sure that RVALUE_OVERHEAD aligns to sizeof(VALUE)
# define RVALUE_OVERHEAD (sizeof(struct { \
    union { \
        struct rvalue_overhead overhead; \
        VALUE value; \
    }; \
}))
size_t rb_gc_impl_obj_slot_size(VALUE obj);
# define GET_RVALUE_OVERHEAD(obj) ((struct rvalue_overhead *)((uintptr_t)obj + rb_gc_impl_obj_slot_size(obj)))
#else
# ifndef RVALUE_OVERHEAD
#  define RVALUE_OVERHEAD 0
# endif
#endif

#define RVALUE_SLOT_SIZE (sizeof(struct RBasic) + sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX]) + RVALUE_OVERHEAD)

static const size_t pool_slot_sizes[HEAP_COUNT] = {
#define SLOT(size) ((size) + RVALUE_OVERHEAD),
    EACH_POOL_SLOT_SIZE(SLOT)
#undef SLOT
};

/* Precomputed reciprocals for fast slot index calculation.
 * For slot size d: reciprocal = ceil(2^48 / d).
 * Then offset / d == (uint32_t)((offset * reciprocal) >> 48)
 * for all offset < HEAP_PAGE_SIZE. */
#define SLOT_RECIPROCAL_SHIFT 48
#define SLOT_RECIPROCAL(size) (((1ULL << SLOT_RECIPROCAL_SHIFT) + (size) - 1) / (size))

static const uint64_t heap_slot_reciprocal_table[HEAP_COUNT] = {
#define SLOT(size) SLOT_RECIPROCAL((size) + RVALUE_OVERHEAD),
    EACH_POOL_SLOT_SIZE(SLOT)
#undef SLOT
};

#if SIZEOF_VALUE >= 8
static uint8_t size_to_heap_idx[1024 / 8 + 1];
#else
static uint8_t size_to_heap_idx[512 / 8 + 1];
#endif

#ifndef MAX
# define MAX(a, b) (((a) > (b)) ? (a) : (b))
#endif
#ifndef MIN
# define MIN(a, b) (((a) < (b)) ? (a) : (b))
#endif
#define roomof(x, y) (((x) + (y) - 1) / (y))
#define CEILDIV(i, mod) roomof(i, mod)
#define MIN_POOL_SLOT_SIZE 32
enum {
    HEAP_PAGE_ALIGN = (1UL << HEAP_PAGE_ALIGN_LOG),
    HEAP_PAGE_ALIGN_MASK = (~(~0UL << HEAP_PAGE_ALIGN_LOG)),
    HEAP_PAGE_SIZE = HEAP_PAGE_ALIGN,
    HEAP_PAGE_BITMAP_LIMIT = CEILDIV(CEILDIV(HEAP_PAGE_SIZE, MIN_POOL_SLOT_SIZE), BITS_BITLENGTH),
    HEAP_PAGE_BITMAP_SIZE = (BITS_SIZE * HEAP_PAGE_BITMAP_LIMIT),
};
#define HEAP_PAGE_ALIGN (1 << HEAP_PAGE_ALIGN_LOG)
#define HEAP_PAGE_SIZE HEAP_PAGE_ALIGN

#if !defined(INCREMENTAL_MARK_STEP_ALLOCATIONS)
# define INCREMENTAL_MARK_STEP_ALLOCATIONS 500
#endif

#undef INIT_HEAP_PAGE_ALLOC_USE_MMAP
/* Must define either HEAP_PAGE_ALLOC_USE_MMAP or
 * INIT_HEAP_PAGE_ALLOC_USE_MMAP. */

#ifndef HAVE_MMAP
/* We can't use mmap of course, if it is not available. */
static const bool HEAP_PAGE_ALLOC_USE_MMAP = false;

#elif defined(__wasm__)
/* wasmtime does not have proper support for mmap.
 * See https://github.com/bytecodealliance/wasmtime/blob/main/docs/WASI-rationale.md#why-no-mmap-and-friends
 */
static const bool HEAP_PAGE_ALLOC_USE_MMAP = false;

#elif HAVE_CONST_PAGE_SIZE
/* If we have the PAGE_SIZE and it is a constant, then we can directly use it. */
static const bool HEAP_PAGE_ALLOC_USE_MMAP = (PAGE_SIZE <= HEAP_PAGE_SIZE);

#elif defined(PAGE_MAX_SIZE) && (PAGE_MAX_SIZE <= HEAP_PAGE_SIZE)
/* If we can use the maximum page size. */
static const bool HEAP_PAGE_ALLOC_USE_MMAP = true;

#elif defined(PAGE_SIZE)
/* If the PAGE_SIZE macro can be used dynamically. */
# define INIT_HEAP_PAGE_ALLOC_USE_MMAP (PAGE_SIZE <= HEAP_PAGE_SIZE)

#elif defined(HAVE_SYSCONF) && defined(_SC_PAGE_SIZE)
/* If we can use sysconf to determine the page size. */
# define INIT_HEAP_PAGE_ALLOC_USE_MMAP (sysconf(_SC_PAGE_SIZE) <= HEAP_PAGE_SIZE)

#else
/* Otherwise we can't determine the system page size, so don't use mmap. */
static const bool HEAP_PAGE_ALLOC_USE_MMAP = false;
#endif

#ifdef INIT_HEAP_PAGE_ALLOC_USE_MMAP
/* We can determine the system page size at runtime. */
# define HEAP_PAGE_ALLOC_USE_MMAP (heap_page_alloc_use_mmap != false)

static bool heap_page_alloc_use_mmap;
#endif

#define RVALUE_AGE_BIT_COUNT 2
#define RVALUE_AGE_BIT_MASK (((bits_t)1 << RVALUE_AGE_BIT_COUNT) - 1)
#define RVALUE_OLD_AGE   3

struct free_region {
    VALUE flags;		/* always 0 for freed obj */
    uintptr_t end;		/* exclusive end address of the run */
    struct free_region *next;	/* next free region in the page */
};

struct heap_page {
    /* Cache line 0: allocation fast path + SLOT_INDEX */
    struct free_region *free_region;
    uintptr_t start;
    uint64_t slot_size_reciprocal;
    unsigned short slot_size;
    unsigned short total_slots;
    unsigned short free_slots;
    unsigned short final_slots;
    unsigned short pinned_slots;
    /* bitfield ではなく 1 バイトずつ持つ。has_remembered_objects は lock-free な
     * write barrier が任意の Ractor スレッドから立てるため、bitfield の read-modify-write
     * だと隣のフラグへの並行 store を失いうる。バイト単位なら各 store は独立。
     * 順序: write barrier は bit を立ててからこのフラグを立て、rgengc_rememberset_mark は
     * フラグを消してから bit を drain するので、競合しても再走査に漏れない。 */
    struct {
        unsigned char before_sweep;
        unsigned char has_remembered_objects;
        unsigned char has_uncollectible_wb_unprotected_objects;
    } flags;

    /* このページのいずれかのオブジェクトに shref / shareable bit が立つと立てる。
     * バイトにする理由は上のフラグと同じ。bit 自体は所有者スレッドのみが書くので
     * atomic 不要。 */
    unsigned char has_shref_objects;
    unsigned char has_shareable_objects;

    rb_heap_t *heap;

    /* このページを所有する objspace。任意のオブジェクトから所有者を 1 ロードで
     * 引ける（GET_HEAP_OBJSPACE）。ページの所有者が変わる（継承）ときだけ書き換える。 */
    rb_objspace_t *objspace;

    struct heap_page *free_next;
    struct heap_page_body *body;
    struct ccan_list_node page_node;

    bits_t wb_unprotected_bits[HEAP_PAGE_BITMAP_LIMIT];
    /* the following three bitmaps are cleared at the beginning of full GC */
    bits_t mark_bits[HEAP_PAGE_BITMAP_LIMIT];
    bits_t uncollectible_bits[HEAP_PAGE_BITMAP_LIMIT];
    bits_t marking_bits[HEAP_PAGE_BITMAP_LIMIT];

    bits_t remembered_bits[HEAP_PAGE_BITMAP_LIMIT];

    /* オブジェクトごとの追加 2 bit。shareable_bits は local GC の sweep が決して free して
     * はならないもの（shareable の死は global GC だけが判定できる）を示す。生成時と
     * rb_gc_impl_obj_became_shareable で立てる。shref_bits は shref（shareable から参照
     * される unshareable）を示し、local GC は root 扱いする。write barrier が維持する。 */
    bits_t shareable_bits[HEAP_PAGE_BITMAP_LIMIT];
    bits_t shref_bits[HEAP_PAGE_BITMAP_LIMIT];

    /* If set, the object is not movable */
    bits_t pinned_bits[HEAP_PAGE_BITMAP_LIMIT];
    bits_t age_bits[HEAP_PAGE_BITMAP_LIMIT * RVALUE_AGE_BIT_COUNT];
};

/*
 * When asan is enabled, this will prohibit writing to the freelist until it is unlocked
 */
static void
asan_lock_freelist(struct heap_page *page)
{
    asan_poison_memory_region(&page->free_region, sizeof(struct free_region *));
}

/*
 * When asan is enabled, this will enable the ability to write to the freelist
 */
static void
asan_unlock_freelist(struct heap_page *page)
{
    asan_unpoison_memory_region(&page->free_region, sizeof(struct free_region *), false);
}

static inline bool
heap_page_in_global_empty_pages_pool(rb_objspace_t *objspace, struct heap_page *page)
{
    if (page->total_slots == 0) {
        GC_ASSERT(page->start == 0);
        GC_ASSERT(page->slot_size == 0);
        GC_ASSERT(page->heap == NULL);
        GC_ASSERT(page->free_slots == 0);
        asan_unpoisoning_memory_region(&page->free_region, sizeof(&page->free_region)) {
            GC_ASSERT(page->free_region == NULL);
        }

        return true;
    }
    else {
        GC_ASSERT(page->start != 0);
        GC_ASSERT(page->slot_size != 0);
        GC_ASSERT(page->heap != NULL);

        return false;
    }
}

#define GET_PAGE_BODY(x)   ((struct heap_page_body *)((bits_t)(x) & ~(HEAP_PAGE_ALIGN_MASK)))
#define GET_PAGE_HEADER(x) (&GET_PAGE_BODY(x)->header)
#define GET_HEAP_PAGE(x)   (GET_PAGE_HEADER(x)->page)

static inline size_t
slot_index_for_offset(size_t offset, uint64_t reciprocal)
{
    return (uint32_t)(((uint64_t)offset * reciprocal) >> SLOT_RECIPROCAL_SHIFT);
}

#define SLOT_INDEX(page, p)          slot_index_for_offset((uintptr_t)(p) - (page)->start, (page)->slot_size_reciprocal)
#define SLOT_BITMAP_INDEX(page, p)   (SLOT_INDEX(page, p) / BITS_BITLENGTH)
#define SLOT_BITMAP_OFFSET(page, p)  (SLOT_INDEX(page, p) & (BITS_BITLENGTH - 1))
#define SLOT_BITMAP_BIT(page, p)     ((bits_t)1 << SLOT_BITMAP_OFFSET(page, p))

#define _MARKED_IN_BITMAP(bits, page, p)  ((bits)[SLOT_BITMAP_INDEX(page, p)] & SLOT_BITMAP_BIT(page, p))
#define _MARK_IN_BITMAP(bits, page, p)    ((bits)[SLOT_BITMAP_INDEX(page, p)] |= SLOT_BITMAP_BIT(page, p))
#define _CLEAR_IN_BITMAP(bits, page, p)   ((bits)[SLOT_BITMAP_INDEX(page, p)] &= ~SLOT_BITMAP_BIT(page, p))

#define MARKED_IN_BITMAP(bits, p)    _MARKED_IN_BITMAP(bits, GET_HEAP_PAGE(p), p)
#define MARK_IN_BITMAP(bits, p)      _MARK_IN_BITMAP(bits, GET_HEAP_PAGE(p), p)
#define CLEAR_IN_BITMAP(bits, p)     _CLEAR_IN_BITMAP(bits, GET_HEAP_PAGE(p), p)

/* remembered_bits は他 Ractor のスレッドから lock-free write barrier で書かれる唯一の
 * bitmap。素の |= だと同じ word の別オブジェクトの bit を並行 writer が失いうるので、
 * word 全体を size_t CAS で更新する。bit を立てたとき true を返す。 */
static inline bool
gc_bitmap_atomic_set(bits_t *bits, const struct heap_page *page, VALUE obj)
{
    volatile size_t *const word = (volatile size_t *)&bits[SLOT_BITMAP_INDEX(page, obj)];
    const size_t mask = (size_t)SLOT_BITMAP_BIT(page, obj);
    size_t old = 0;
    while ((old & mask) != mask) {
        const size_t prev = RUBY_ATOMIC_SIZE_CAS(*word, old, old | mask);
        if (prev == old) return true;
        old = prev;
    }
    return false;
}

static inline void
gc_bitmap_atomic_clear(bits_t *bits, const struct heap_page *page, VALUE obj)
{
    volatile size_t *const word = (volatile size_t *)&bits[SLOT_BITMAP_INDEX(page, obj)];
    const size_t mask = (size_t)SLOT_BITMAP_BIT(page, obj);
    size_t old = mask;
    while ((old & mask) != 0) {
        const size_t prev = RUBY_ATOMIC_SIZE_CAS(*word, old, old & ~mask);
        if (prev == old) return;
        old = prev;
    }
}

#define GET_HEAP_MARK_BITS(x)           (&GET_HEAP_PAGE(x)->mark_bits[0])
#define GET_HEAP_PINNED_BITS(x)         (&GET_HEAP_PAGE(x)->pinned_bits[0])
#define GET_HEAP_UNCOLLECTIBLE_BITS(x)  (&GET_HEAP_PAGE(x)->uncollectible_bits[0])
#define GET_HEAP_WB_UNPROTECTED_BITS(x) (&GET_HEAP_PAGE(x)->wb_unprotected_bits[0])
#define GET_HEAP_MARKING_BITS(x)        (&GET_HEAP_PAGE(x)->marking_bits[0])
#define GET_HEAP_SHAREABLE_BITS(x)      (&GET_HEAP_PAGE(x)->shareable_bits[0])
#define GET_HEAP_SHREF_BITS(x)          (&GET_HEAP_PAGE(x)->shref_bits[0])
#define GET_HEAP_OBJSPACE(x)            (GET_HEAP_PAGE(x)->objspace)

static int
RVALUE_AGE_GET(VALUE obj)
{
    struct heap_page *page = GET_HEAP_PAGE(obj);
    bits_t *age_bits = page->age_bits;
    size_t slot_idx = SLOT_INDEX(page, obj);
    size_t idx = (slot_idx / BITS_BITLENGTH) * 2;
    int shift = (int)(slot_idx & (BITS_BITLENGTH - 1));
    int lo = (age_bits[idx] >> shift) & 1;
    int hi = (age_bits[idx + 1] >> shift) & 1;
    return lo | (hi << 1);
}

static void
RVALUE_AGE_SET_BITMAP(VALUE obj, int age)
{
    RUBY_ASSERT(age <= RVALUE_OLD_AGE);
    struct heap_page *page = GET_HEAP_PAGE(obj);
    bits_t *age_bits = page->age_bits;
    size_t slot_idx = SLOT_INDEX(page, obj);
    size_t idx = (slot_idx / BITS_BITLENGTH) * 2;
    int shift = (int)(slot_idx & (BITS_BITLENGTH - 1));
    bits_t mask = (bits_t)1 << shift;

    age_bits[idx]     = (age_bits[idx]     & ~mask) | ((bits_t)(age & 1) << shift);
    age_bits[idx + 1] = (age_bits[idx + 1] & ~mask) | ((bits_t)((age >> 1) & 1) << shift);
}

static void
RVALUE_AGE_SET(VALUE obj, int age)
{
    RVALUE_AGE_SET_BITMAP(obj, age);
    if (age == RVALUE_OLD_AGE) {
        RB_FL_SET_RAW(obj, RUBY_FL_PROMOTED);
    }
    else {
        RB_FL_UNSET_RAW(obj, RUBY_FL_PROMOTED);
    }
}

#define malloc_limit		objspace->malloc_params.limit
#define malloc_increase 	gc_malloc_counters_increase_unsigned(objspace, &objspace->malloc_counters.counters)
#define malloc_allocated_size 	objspace->malloc_params.allocated_size

#ifdef MALLOC_COUNTERS_NEED_LOCK
# define MALLOC_COUNTERS_LOCK(o)   rb_native_mutex_lock(&(o)->malloc_counters.lock)
# define MALLOC_COUNTERS_UNLOCK(o) rb_native_mutex_unlock(&(o)->malloc_counters.lock)
#else
# define MALLOC_COUNTERS_LOCK(o)   ((void)0)
# define MALLOC_COUNTERS_UNLOCK(o) ((void)0)
#endif

static inline void
gc_counter_add(gc_counter_t *p, size_t delta)
{
#ifdef MALLOC_COUNTERS_NEED_LOCK
    *p += (gc_counter_t)delta;
#else
    rbimpl_atomic_u64_fetch_add_relaxed(p, (uint64_t)delta);
#endif
}

static inline gc_counter_t
gc_counter_load_relaxed(const gc_counter_t *p)
{
#ifdef MALLOC_COUNTERS_NEED_LOCK
    return *p;
#else
    return rbimpl_atomic_u64_load_relaxed(p);
#endif
}

static inline gc_counter_t
gc_counter_load_acquire(const gc_counter_t *p)
{
#ifdef MALLOC_COUNTERS_NEED_LOCK
    return *p;
#else
    return rbimpl_atomic_u64_load_acquire(p);
#endif
}

static inline void
gc_counter_store_release(gc_counter_t *p, gc_counter_t v)
{
#ifdef MALLOC_COUNTERS_NEED_LOCK
    *p = v;
#else
    rbimpl_atomic_u64_set_release(p, v);
#endif
}

static inline int64_t
gc_malloc_counters_increase(rb_objspace_t *objspace, const struct gc_malloc_bytes *c)
{
    MALLOC_COUNTERS_LOCK(objspace);
    gc_counter_t malloc_at = gc_counter_load_acquire(&c->malloc_at_last_gc);
    gc_counter_t free_at   = gc_counter_load_acquire(&c->free_at_last_gc);
    gc_counter_t malloc_now = gc_counter_load_relaxed(&c->malloc);
    gc_counter_t free_now   = gc_counter_load_relaxed(&c->free);
    MALLOC_COUNTERS_UNLOCK(objspace);

    gc_counter_t malloc_delta = malloc_now - malloc_at;
    gc_counter_t free_delta   = free_now   - free_at;

    if (malloc_delta >= free_delta) {
        return (int64_t)(malloc_delta - free_delta);
    }
    else {
        return -(int64_t)(free_delta - malloc_delta);
    }
}

static inline size_t
gc_malloc_counters_increase_unsigned(rb_objspace_t *objspace, const struct gc_malloc_bytes *c)
{
    int64_t inc = gc_malloc_counters_increase(objspace, c);
    if (inc <= 0) return 0;
#if SIZEOF_SIZE_T < 8
    if ((uint64_t)inc > SIZE_MAX) return SIZE_MAX;
#endif
    return (size_t)inc;
}

static inline void
gc_malloc_counters_snapshot(rb_objspace_t *objspace, struct gc_malloc_bytes *c)
{
    MALLOC_COUNTERS_LOCK(objspace);
    gc_counter_t malloc_now = gc_counter_load_relaxed(&c->malloc);
    gc_counter_t free_now   = gc_counter_load_relaxed(&c->free);
    gc_counter_store_release(&c->malloc_at_last_gc, malloc_now);
    gc_counter_store_release(&c->free_at_last_gc,   free_now);
    MALLOC_COUNTERS_UNLOCK(objspace);
}

#define heap_pages_lomem	objspace->heap_pages.range[0]
#define heap_pages_himem	objspace->heap_pages.range[1]
#define heap_pages_freeable_pages	objspace->heap_pages.freeable_pages
#define heap_pages_deferred_final	objspace->heap_pages.deferred_final
#define heaps              objspace->heaps
#define during_gc		objspace->flags.during_gc
#define finalizing		objspace->atomic_flags.finalizing
#define finalizer_table 	objspace->finalizer_table
#define ruby_gc_stressful	objspace->flags.gc_stressful
#define ruby_gc_stress_mode     objspace->gc_stress_mode
#if GC_DEBUG_STRESS_TO_CLASS
#define stress_to_class         objspace->stress_to_class
#define set_stress_to_class(c)  (stress_to_class = (c))
#else
#define stress_to_class         ((void)objspace, 0)
#define set_stress_to_class(c)  ((void)objspace, (c))
#endif

#if 0
#define dont_gc_on()          (fprintf(stderr, "dont_gc_on@%s:%d\n",      __FILE__, __LINE__), objspace->flags.dont_gc = 1)
#define dont_gc_off()         (fprintf(stderr, "dont_gc_off@%s:%d\n",     __FILE__, __LINE__), objspace->flags.dont_gc = 0)
#define dont_gc_set(b)        (fprintf(stderr, "dont_gc_set(%d)@%s:%d\n", __FILE__, __LINE__), objspace->flags.dont_gc = (int)(b))
#define dont_gc_val()         (objspace->flags.dont_gc)
#else
#define dont_gc_on()          (objspace->flags.dont_gc = 1)
#define dont_gc_off()         (objspace->flags.dont_gc = 0)
#define dont_gc_set(b)        (objspace->flags.dont_gc = (int)(b))
#define dont_gc_val()         (objspace->flags.dont_gc)
#endif

#define gc_config_full_mark_set(b) (objspace->gc_config.full_mark = (int)(b))
#define gc_config_full_mark_val    (objspace->gc_config.full_mark)

#ifndef DURING_GC_COULD_MALLOC_REGION_START
# define DURING_GC_COULD_MALLOC_REGION_START() \
    assert(rb_during_gc()); \
    bool _prev_enabled = rb_gc_impl_gc_enabled_p(objspace); \
    rb_gc_impl_gc_disable(objspace, false)
#endif

#ifndef DURING_GC_COULD_MALLOC_REGION_END
# define DURING_GC_COULD_MALLOC_REGION_END() \
    if (_prev_enabled) rb_gc_impl_gc_enable(objspace)
#endif

static inline enum gc_mode
gc_mode_verify(enum gc_mode mode)
{
#if RGENGC_CHECK_MODE > 0
    switch (mode) {
      case gc_mode_none:
      case gc_mode_marking:
      case gc_mode_sweeping:
      case gc_mode_compacting:
        break;
      default:
        rb_bug("gc_mode_verify: unreachable (%d)", (int)mode);
    }
#endif
    return mode;
}

static inline bool
has_sweeping_pages(rb_objspace_t *objspace)
{
    return objspace->sweeping_heap_count != 0;
}

static inline size_t
heap_eden_total_pages(rb_objspace_t *objspace)
{
    size_t count = 0;
    for (int i = 0; i < HEAP_COUNT; i++) {
        count += (&heaps[i])->total_pages;
    }
    return count;
}

static inline size_t
total_allocated_objects(rb_objspace_t *objspace)
{
    size_t count = 0;
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        count += heap->total_allocated_objects;
    }
    return count;
}

static inline size_t
total_freed_objects(rb_objspace_t *objspace)
{
    size_t count = 0;
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        count += heap->total_freed_objects;
    }
    return count;
}

static inline size_t
total_final_slots_count(rb_objspace_t *objspace)
{
    size_t count = 0;
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        count += heap->final_slots_count;
    }
    return count;
}

#define gc_mode(objspace)                gc_mode_verify((enum gc_mode)(objspace)->flags.mode)
#define gc_mode_set(objspace, m)         ((objspace)->flags.mode = (unsigned int)gc_mode_verify(m))
#define gc_needs_major_flags objspace->rgengc.need_major_gc

#define is_marking(objspace)             (gc_mode(objspace) == gc_mode_marking)
#define is_sweeping(objspace)            (gc_mode(objspace) == gc_mode_sweeping)
#define is_full_marking(objspace)        ((objspace)->flags.during_minor_gc == FALSE)
#define is_incremental_marking(objspace) ((objspace)->flags.during_incremental_marking != FALSE)
#define will_be_incremental_marking(objspace) ((objspace)->rgengc.need_major_gc != GPR_FLAG_NONE)
/*
 * Byte budget for incremental sweep steps. Each step sweeps at most
 * this many bytes worth of slots before yielding. The effective slot
 * count per step is GC_INCREMENTAL_SWEEP_BYTES / heap->slot_size,
 * so larger slot pools (which are less heavily used) naturally get
 * fewer slots swept per step.
 *
 * Baseline: 2048 slots * RVALUE_SLOT_SIZE = 2048 * 40 = 81920 bytes,
 * preserving the historical behavior for the smallest heap.
 */
#define GC_INCREMENTAL_SWEEP_BYTES           (2048 * RVALUE_SLOT_SIZE)
#define GC_INCREMENTAL_SWEEP_POOL_BYTES      (1024 * RVALUE_SLOT_SIZE)
#define is_lazy_sweeping(objspace)           (GC_ENABLE_LAZY_SWEEP && has_sweeping_pages(objspace))
/* In lazy sweeping or the previous incremental marking finished and did not yield a free page. */
#define needs_continue_sweeping(objspace, heap) \
    ((heap)->free_pages == NULL && is_lazy_sweeping(objspace))

#if SIZEOF_LONG == SIZEOF_VOIDP
# define obj_id_to_ref(objid) ((objid) ^ FIXNUM_FLAG) /* unset FIXNUM_FLAG */
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
# define obj_id_to_ref(objid) (FIXNUM_P(objid) ? \
   ((objid) ^ FIXNUM_FLAG) : (NUM2PTR(objid) << 1))
#else
# error not supported
#endif

struct RZombie {
    VALUE flags;
    VALUE next;
    void (*dfree)(void *);
    void *data;
};

#define RZOMBIE(o) ((struct RZombie *)(o))

static bool ruby_enable_autocompact = false;
#if RGENGC_CHECK_MODE
static gc_compact_compare_func ruby_autocompact_compare_func;
#endif

static void init_mark_stack(mark_stack_t *stack);
static int garbage_collect(rb_objspace_t *, unsigned int reason);

static int  gc_start(rb_objspace_t *objspace, unsigned int reason);
static void gc_rest(rb_objspace_t *objspace);

/* GC サイクルのイベント（ENTER/EXIT/START/END_MARK/END_SWEEP）は、その objspace の
 * Ractor が有効化した場合だけ発火する。並行する local GC が、他 Ractor が変更中の
 * VM グローバル hook リストを走査しないため。NEWOBJ/FREEOBJ は元から同様に絞る。 */
#define gc_event_hook_objspace(objspace, event) do { \
    if (RB_UNLIKELY((objspace)->hook_events & (event))) { \
        rb_gc_event_hook(0, (event)); \
    } \
} while (0)

enum gc_enter_event {
    gc_enter_event_start,
    gc_enter_event_continue,
    gc_enter_event_rest,
    gc_enter_event_finalizer,
    gc_enter_event_global,
};

static inline void gc_enter(rb_objspace_t *objspace, enum gc_enter_event event, unsigned int *lock_lev);
static inline void gc_exit(rb_objspace_t *objspace, enum gc_enter_event event, unsigned int *lock_lev);
static void gc_marking_enter(rb_objspace_t *objspace);
static void gc_marking_exit(rb_objspace_t *objspace);
static void gc_sweeping_enter(rb_objspace_t *objspace);
static void gc_sweeping_exit(rb_objspace_t *objspace);
static bool gc_marks_continue(rb_objspace_t *objspace, rb_heap_t *heap);

static void gc_sweep(rb_objspace_t *objspace);
static void gc_sweep_finish_heap(rb_objspace_t *objspace, rb_heap_t *heap);
static void gc_sweep_continue(rb_objspace_t *objspace, rb_heap_t *heap);

static inline void gc_mark(rb_objspace_t *objspace, VALUE ptr);
static inline void gc_pin(rb_objspace_t *objspace, VALUE ptr);
static inline void gc_mark_and_pin(rb_objspace_t *objspace, VALUE ptr);

static int gc_mark_stacked_objects_incremental(rb_objspace_t *, size_t count);
NO_SANITIZE("memory", static inline bool is_pointer_to_heap(rb_objspace_t *objspace, const void *ptr));

static void gc_verify_internal_consistency(void *objspace_ptr);

static double getrusage_time(void);
static inline rb_hrtime_t elapsed_hrtime_from(rb_hrtime_t start);
static inline void gc_prof_setup_new_record(rb_objspace_t *objspace, unsigned int reason);
static inline void gc_prof_timer_start(rb_objspace_t *);
static inline void gc_prof_timer_stop(rb_objspace_t *);
static inline void gc_prof_mark_timer_start(rb_objspace_t *);
static inline void gc_prof_mark_timer_stop(rb_objspace_t *);
static inline void gc_prof_sweep_timer_start(rb_objspace_t *);
static inline void gc_prof_sweep_timer_stop(rb_objspace_t *);
static inline void gc_prof_set_malloc_info(rb_objspace_t *);
static inline void gc_prof_set_heap_info(rb_objspace_t *);

#define gc_prof_record(objspace) (objspace)->profile.current_record
#define gc_prof_enabled(objspace) ((objspace)->profile.run && (objspace)->profile.current_record)

#define gc_report(level, objspace, ...) \
    if (!RGENGC_DEBUG_ENABLED(level)) {} else gc_report_body(level, objspace, __VA_ARGS__)
PRINTF_ARGS(static void gc_report_body(int level, rb_objspace_t *objspace, const char *fmt, ...), 3, 4);

static void gc_finalize_deferred(void *dmy);

#if USE_TICK_T

/* the following code is only for internal tuning. */

/* Source code to use RDTSC is quoted and modified from
 * https://www.mcs.anl.gov/~kazutomo/rdtsc.html
 * written by Kazutomo Yoshii <kazutomo@mcs.anl.gov>
 */

#if defined(__GNUC__) && defined(__i386__)
typedef unsigned long long tick_t;
#define PRItick "llu"
static inline tick_t
tick(void)
{
    unsigned long long int x;
    __asm__ __volatile__ ("rdtsc" : "=A" (x));
    return x;
}

#elif defined(__GNUC__) && defined(__x86_64__)
typedef unsigned long long tick_t;
#define PRItick "llu"

static __inline__ tick_t
tick(void)
{
    unsigned long hi, lo;
    __asm__ __volatile__ ("rdtsc" : "=a"(lo), "=d"(hi));
    return ((unsigned long long)lo)|( ((unsigned long long)hi)<<32);
}

#elif defined(__powerpc64__) && (GCC_VERSION_SINCE(4,8,0) || defined(__clang__))
typedef unsigned long long tick_t;
#define PRItick "llu"

static __inline__ tick_t
tick(void)
{
    unsigned long long val = __builtin_ppc_get_timebase();
    return val;
}

#elif defined(__POWERPC__) && defined(__APPLE__)
/* Implementation for macOS PPC by @nobu
 * See: https://github.com/ruby/ruby/pull/5975#discussion_r890045558
 */
typedef unsigned long long tick_t;
#define PRItick "llu"

static __inline__ tick_t
tick(void)
{
    unsigned long int upper, lower, tmp;
    # define mftbu(r) __asm__ volatile("mftbu   %0" : "=r"(r))
    # define mftb(r)  __asm__ volatile("mftb    %0" : "=r"(r))
        do {
            mftbu(upper);
            mftb(lower);
            mftbu(tmp);
        } while (tmp != upper);
    return ((tick_t)upper << 32) | lower;
}

#elif defined(__aarch64__) &&  defined(__GNUC__)
typedef unsigned long tick_t;
#define PRItick "lu"

static __inline__ tick_t
tick(void)
{
    unsigned long val;
    __asm__ __volatile__ ("mrs %0, cntvct_el0" : "=r" (val));
    return val;
}


#elif defined(_WIN32) && defined(_MSC_VER)
#include <intrin.h>
typedef unsigned __int64 tick_t;
#define PRItick "llu"

static inline tick_t
tick(void)
{
    return __rdtsc();
}

#else /* use clock */
typedef clock_t tick_t;
#define PRItick "llu"

static inline tick_t
tick(void)
{
    return clock();
}
#endif /* TSC */
#else /* USE_TICK_T */
#define MEASURE_LINE(expr) expr
#endif /* USE_TICK_T */

static inline VALUE check_rvalue_consistency(rb_objspace_t *objspace, const VALUE obj);

#define RVALUE_MARKED_BITMAP(obj)         MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), (obj))
#define RVALUE_WB_UNPROTECTED_BITMAP(obj) MARKED_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(obj), (obj))
#define RVALUE_MARKING_BITMAP(obj)        MARKED_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), (obj))
#define RVALUE_UNCOLLECTIBLE_BITMAP(obj)  MARKED_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS(obj), (obj))
#define RVALUE_PINNED_BITMAP(obj)         MARKED_IN_BITMAP(GET_HEAP_PINNED_BITS(obj), (obj))

static inline int
RVALUE_MARKED(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(objspace, obj);
    return RVALUE_MARKED_BITMAP(obj) != 0;
}

static inline int
RVALUE_PINNED(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(objspace, obj);
    return RVALUE_PINNED_BITMAP(obj) != 0;
}

static inline int
RVALUE_WB_UNPROTECTED(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(objspace, obj);
    return RVALUE_WB_UNPROTECTED_BITMAP(obj) != 0;
}

static inline int
RVALUE_MARKING(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(objspace, obj);
    return RVALUE_MARKING_BITMAP(obj) != 0;
}

static inline int
RVALUE_REMEMBERED(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(objspace, obj);
    return MARKED_IN_BITMAP(GET_HEAP_PAGE(obj)->remembered_bits, obj) != 0;
}

static inline int
RVALUE_UNCOLLECTIBLE(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(objspace, obj);
    return RVALUE_UNCOLLECTIBLE_BITMAP(obj) != 0;
}

#define RVALUE_PAGE_WB_UNPROTECTED(page, obj) MARKED_IN_BITMAP((page)->wb_unprotected_bits, (obj))
#define RVALUE_PAGE_UNCOLLECTIBLE(page, obj)  MARKED_IN_BITMAP((page)->uncollectible_bits, (obj))
#define RVALUE_PAGE_MARKING(page, obj)        MARKED_IN_BITMAP((page)->marking_bits, (obj))

static int rgengc_remember(rb_objspace_t *objspace, VALUE obj);
static void rgengc_mark_and_rememberset_clear(rb_objspace_t *objspace, rb_heap_t *heap);
static void rgengc_rememberset_mark(rb_objspace_t *objspace, rb_heap_t *heap);
static bool verify_pointer_in_any_heap_p(const void *ptr); /* cross-objspace の所属判定 */

static int
check_rvalue_consistency_force(rb_objspace_t *objspace, const VALUE obj, int terminate)
{
    int err = 0;

    /* global GC 中は barrier が全 Ractor を止めているので、下の cross-objspace 走査は
     * VM lock なしで安全。zombie objspace（所有者なし）の sweep では GET_RACTOR() が
     * NULL になり、ここで lock を取ると NULL 参照になる。 */
    const bool world_stopped = objspace->during_global_gc;
    /* 下の VM lock は、write barrier から呼ばれた local GC 中の verify（他 Ractor が走行し
     * heap を realloc する）での cross-objspace 走査を守る。ただしこの objspace で GC 進行中は
     * 取ってはいけない。ページは安定で cross-objspace 走査も world 停止時のみ行い、かつ
     * Ractor が自分の ractor lock を保持済みのことがあり、ractor→VM の逆順ロックになるため。
     * global GC は barrier を持つので lock 不要。 */
    const bool take_vm_lock = !world_stopped && !during_gc;
    unsigned int lev = 0;
    if (take_vm_lock) lev = RB_GC_VM_LOCK_NO_BARRIER();
    {
        if (SPECIAL_CONST_P(obj)) {
            fprintf(stderr, "check_rvalue_consistency: %p is a special const.\n", (void *)obj);
            err++;
        }
        else if (!is_pointer_to_heap(objspace, (void *)obj)) {
            /* obj は別 objspace に住む正当な cross-objspace 参照（shareable や in-flight の
             * shref payload）かもしれない。is_pointer_to_heap は渡した objspace しか探さない。
             * どの objspace の heap にも無いときだけ本当に Ruby オブジェクトでない。foreign な
             * オブジェクトの mark/age/remembered bit は所有者のもので、ここで読むと所有者の
             * local GC と競合するため、per-object 検査には入らない。 */
            if (!world_stopped) {
                /* local GC 中の verify は no-barrier VM lock しか持たず barrier は持たない。
                 * 他 Ractor が 自 objspace への割り当てで heap_pages.sorted を realloc しており、
                 * verify_pointer_in_any_heap_p の全 objspace bsearch はそれと競合して SEGV する。
                 * barrier 無しでは foreign ポインタを確認できないのでここでは許容し、
                 * global GC の verify（world 停止）が完全な存在検査を行う。 */
            }
            else if (!verify_pointer_in_any_heap_p((void *)obj)) {
                struct heap_page *empty_page = objspace->empty_pages;
                while (empty_page) {
                    if ((uintptr_t)empty_page->body <= (uintptr_t)obj &&
                            (uintptr_t)obj < (uintptr_t)empty_page->body + HEAP_PAGE_SIZE) {
                        GC_ASSERT(heap_page_in_global_empty_pages_pool(objspace, empty_page));
                        fprintf(stderr, "check_rvalue_consistency: %p is in an empty page (%p).\n",
                                (void *)obj, (void *)empty_page);
                        err++;
                        goto skip;
                    }
                    empty_page = empty_page->free_next;
                }
                fprintf(stderr, "check_rvalue_consistency: %p is not a Ruby object.\n", (void *)obj);
                err++;
              skip:
                ;
            }
        }
        else {
            const int wb_unprotected_bit = RVALUE_WB_UNPROTECTED_BITMAP(obj) != 0;
            const int uncollectible_bit = RVALUE_UNCOLLECTIBLE_BITMAP(obj) != 0;
            const int mark_bit = RVALUE_MARKED_BITMAP(obj) != 0;
            const int marking_bit = RVALUE_MARKING_BITMAP(obj) != 0;
            const int remembered_bit = MARKED_IN_BITMAP(GET_HEAP_PAGE(obj)->remembered_bits, obj) != 0;
            const int age = RVALUE_AGE_GET((VALUE)obj);

            if (heap_page_in_global_empty_pages_pool(objspace, GET_HEAP_PAGE(obj))) {
                fprintf(stderr, "check_rvalue_consistency: %s is in tomb page.\n", rb_obj_info(obj));
                err++;
            }
            if (BUILTIN_TYPE(obj) == T_NONE) {
                fprintf(stderr, "check_rvalue_consistency: %s is T_NONE.\n", rb_obj_info(obj));
                err++;
            }
            if (BUILTIN_TYPE(obj) == T_ZOMBIE) {
                fprintf(stderr, "check_rvalue_consistency: %s is T_ZOMBIE.\n", rb_obj_info(obj));
                err++;
            }

            if (BUILTIN_TYPE(obj) != T_DATA) {
                rb_obj_memsize_of((VALUE)obj);
            }

            /* check generation
             *
             * OLD == age == 3 && old-bitmap && mark-bit (except incremental marking)
             */
            if (age > 0 && wb_unprotected_bit) {
                fprintf(stderr, "check_rvalue_consistency: %s is not WB protected, but age is %d > 0.\n", rb_obj_info(obj), age);
                err++;
            }

            if (!is_marking(objspace) && uncollectible_bit && !mark_bit) {
                fprintf(stderr, "check_rvalue_consistency: %s is uncollectible, but is not marked while !gc.\n", rb_obj_info(obj));
                err++;
            }

            if (!is_full_marking(objspace)) {
                if (uncollectible_bit && age != RVALUE_OLD_AGE && !wb_unprotected_bit) {
                    fprintf(stderr, "check_rvalue_consistency: %s is uncollectible, but not old (age: %d) and not WB unprotected.\n",
                            rb_obj_info(obj), age);
                    err++;
                }
                if (remembered_bit && age != RVALUE_OLD_AGE) {
                    fprintf(stderr, "check_rvalue_consistency: %s is remembered, but not old (age: %d).\n",
                            rb_obj_info(obj), age);
                    err++;
                }
            }

            /*
             * check coloring
             *
             *               marking:false marking:true
             * marked:false  white         *invalid*
             * marked:true   black         grey
             */
            if (is_incremental_marking(objspace) && marking_bit) {
                if (!is_marking(objspace) && !mark_bit) {
                    fprintf(stderr, "check_rvalue_consistency: %s is marking, but not marked.\n", rb_obj_info(obj));
                    err++;
                }
            }
        }
    }
    if (take_vm_lock) RB_GC_VM_UNLOCK_NO_BARRIER(lev);

    if (err > 0 && terminate) {
        rb_bug("check_rvalue_consistency_force: there is %d errors.", err);
    }
    return err;
}

#if RGENGC_CHECK_MODE == 0
static inline VALUE
check_rvalue_consistency(rb_objspace_t *objspace, const VALUE obj)
{
    return obj;
}
#else
static VALUE
check_rvalue_consistency(rb_objspace_t *objspace, const VALUE obj)
{
    check_rvalue_consistency_force(objspace, obj, TRUE);
    return obj;
}
#endif

static inline bool
gc_object_moved_p(rb_objspace_t *objspace, VALUE obj)
{

    bool ret;
    asan_unpoisoning_object(obj) {
        ret = BUILTIN_TYPE(obj) == T_MOVED;
    }
    return ret;
}

static inline int
RVALUE_OLD_P(rb_objspace_t *objspace, VALUE obj)
{
    GC_ASSERT(!RB_SPECIAL_CONST_P(obj));
    check_rvalue_consistency(objspace, obj);
    // Because this will only ever be called on GC controlled objects,
    // we can use the faster _RAW function here
    return RB_OBJ_PROMOTED_RAW(obj);
}

static inline void
RVALUE_PAGE_OLD_UNCOLLECTIBLE_SET(rb_objspace_t *objspace, struct heap_page *page, VALUE obj)
{
    MARK_IN_BITMAP(&page->uncollectible_bits[0], obj);
    /* promotion はそのオブジェクトの objspace に数える。global GC の unified mark は
     * driver から全 objspace の slot を aging するため、driver に計上すると他 objspace の
     * old_objects（サイクル開始時に 0 化）と major GC の頻度がずれる。 */
    page->objspace->rgengc.old_objects++;

#if RGENGC_PROFILE >= 2
    objspace->profile.total_promoted_count++;
    objspace->profile.promoted_types[BUILTIN_TYPE(obj)]++;
#endif
}

static inline void
RVALUE_OLD_UNCOLLECTIBLE_SET(rb_objspace_t *objspace, VALUE obj)
{
    RB_DEBUG_COUNTER_INC(obj_promote);
    RVALUE_PAGE_OLD_UNCOLLECTIBLE_SET(objspace, GET_HEAP_PAGE(obj), obj);
}

/* set age to age+1 */
static inline void
RVALUE_AGE_INC(rb_objspace_t *objspace, VALUE obj)
{
    int age = RVALUE_AGE_GET((VALUE)obj);

    if (RGENGC_CHECK_MODE && age == RVALUE_OLD_AGE) {
        rb_bug("RVALUE_AGE_INC: can not increment age of OLD object %s.", rb_obj_info(obj));
    }

    age++;
    RVALUE_AGE_SET(obj, age);

    if (age == RVALUE_OLD_AGE) {
        RVALUE_OLD_UNCOLLECTIBLE_SET(objspace, obj);
    }

    check_rvalue_consistency(objspace, obj);
}

static inline void
RVALUE_AGE_SET_CANDIDATE(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(objspace, obj);
    GC_ASSERT(!RVALUE_OLD_P(objspace, obj));
    RVALUE_AGE_SET(obj, RVALUE_OLD_AGE - 1);
    check_rvalue_consistency(objspace, obj);
}

static inline void
RVALUE_AGE_RESET(VALUE obj)
{
    RVALUE_AGE_SET(obj, 0);
}

static inline void
RVALUE_DEMOTE(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(objspace, obj);
    GC_ASSERT(RVALUE_OLD_P(objspace, obj));

    if (!is_incremental_marking(objspace) && RVALUE_REMEMBERED(objspace, obj)) {
        /* atomic。素の &= ~mask だと、並行する write barrier による同じ word 内の別オブジェクトの
         * bit セットを失いうる。 */
        struct heap_page *page = GET_HEAP_PAGE(obj);
        gc_bitmap_atomic_clear(page->remembered_bits, page, obj);
    }

    CLEAR_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS(obj), obj);
    RVALUE_AGE_RESET(obj);

    if (RVALUE_MARKED(objspace, obj)) {
        /* symmetric with RVALUE_PAGE_OLD_UNCOLLECTIBLE_SET */
        GET_HEAP_PAGE(obj)->objspace->rgengc.old_objects--;
    }

    check_rvalue_consistency(objspace, obj);
}

static inline int
RVALUE_BLACK_P(rb_objspace_t *objspace, VALUE obj)
{
    return RVALUE_MARKED(objspace, obj) && !RVALUE_MARKING(objspace, obj);
}

static inline int
RVALUE_WHITE_P(rb_objspace_t *objspace, VALUE obj)
{
    return !RVALUE_MARKED(objspace, obj);
}

bool
rb_gc_impl_gc_enabled_p(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;
    return !dont_gc_val();
}

void
rb_gc_impl_gc_enable(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    dont_gc_off();
}

void
rb_gc_impl_gc_disable(void *objspace_ptr, bool finish_current_gc)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (finish_current_gc) {
        gc_rest(objspace);
    }

    dont_gc_on();
}

/* enabled 状態を変えずに進行中の incremental mark / lazy sweep を完了させる。
 * multi-objspace 化する直前に唯一の objspace を落ち着かせるため gc.c が使う。 */
void
rb_gc_impl_gc_rest(void *objspace_ptr)
{
    gc_rest(objspace_ptr);
}

/*
  --------------------------- ObjectSpace -----------------------------
*/

static inline void *
calloc1(size_t n)
{
    return calloc(1, n);
}

void
rb_gc_impl_set_event_hook(void *objspace_ptr, const rb_event_flag_t event)
{
    rb_objspace_t *objspace = objspace_ptr;
    objspace->hook_events = event & RUBY_INTERNAL_EVENT_OBJSPACE_MASK;
}

unsigned long long
rb_gc_impl_get_total_time(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    unsigned long long marking_time = objspace->profile.marking_time_ns;
    unsigned long long sweeping_time = objspace->profile.sweeping_time_ns;

    return marking_time + sweeping_time;
}

void
rb_gc_impl_set_measure_total_time(void *objspace_ptr, VALUE flag)
{
    rb_objspace_t *objspace = objspace_ptr;

    objspace->flags.measure_gc = RTEST(flag) ? TRUE : FALSE;
}

bool
rb_gc_impl_get_measure_total_time(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    return objspace->flags.measure_gc;
}

/* garbage objects will be collected soon. */
bool
rb_gc_impl_garbage_object_p(void *objspace_ptr, VALUE ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    /* foreign なオブジェクトはここでは生きた葉。その生死と回収は所有者の担当で、
     * type / before_sweep / mark bit を読むと所有者の local GC と競合する。global GC の
     * barrier 外では garbage と報告しない。fstring / symbol の weak-set 検索は
     * cross-objspace にこれを引くが、それらは born-shareable で global STW でしか回収
     * されないため「garbage でない」が正しい。 */
    if (RB_UNLIKELY(GET_HEAP_OBJSPACE(ptr) != objspace) && !objspace->during_global_gc) {
        return false;
    }

    /* Asking whether a freed (T_NONE), moved (T_MOVED), or finalized (T_ZOMBIE)
     * object is garbage gives an unreliable answer: the slot may since have been
     * reused for an unrelated object. A reference to one of these is stale and a
     * bug in the caller. */
    asan_unpoisoning_object(ptr) {
        GC_ASSERT(BUILTIN_TYPE(ptr) != T_NONE);
        GC_ASSERT(BUILTIN_TYPE(ptr) != T_MOVED);
        GC_ASSERT(BUILTIN_TYPE(ptr) != T_ZOMBIE);
    }

    return is_lazy_sweeping(objspace) && GET_HEAP_PAGE(ptr)->flags.before_sweep &&
        !RVALUE_MARKED(objspace, ptr);
}

struct rb_gc_vm_context *
rb_gc_impl_get_vm_context(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    return &objspace->vm_context;
}

static void free_stack_chunks(mark_stack_t *);
static void mark_stack_free_cache(mark_stack_t *);
static void heap_page_free(rb_objspace_t *objspace, struct heap_page *page);

static inline void
gc_check_obj_in_page(struct heap_page *page, VALUE obj)
{
    if (RGENGC_CHECK_MODE &&
        /* obj should belong to page */
        !(page->start <= (uintptr_t)obj &&
          (uintptr_t)obj   <  ((uintptr_t)page->start + (page->total_slots * page->slot_size)) &&
          obj % sizeof(VALUE) == 0)) {
        rb_bug("gc_check_obj_in_page: %p is not rvalue.", (void *)obj);
    }
}

static inline void
heap_page_add_free_region(rb_objspace_t *objspace, struct heap_page *page, VALUE obj)
{
    rb_asan_unpoison_object(obj, false);

    // Should have already been reset
    GC_ASSERT(RVALUE_AGE_GET(obj) == 0);

    gc_check_obj_in_page(page, obj);

    asan_unlock_freelist(page);

    /* free した slot が古い shareable/shref bit を次の生に持ち越さないようにする。 */
    CLEAR_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(obj), obj);
    CLEAR_IN_BITMAP(GET_HEAP_SHREF_BITS(obj), obj);

    struct free_region *region = (struct free_region *)obj;
    region->flags = 0;
    region->end = (uintptr_t)obj + page->slot_size;
    region->next = page->free_region;
    page->free_region = region;

    asan_lock_freelist(page);

    rb_asan_poison_object(obj);
    gc_report(3, objspace, "heap_page_add_free_region: %p\n", (void *)obj);
}

static void
heap_allocatable_bytes_expand(rb_objspace_t *objspace,
        rb_heap_t *heap, size_t free_slots, size_t total_slots, size_t slot_size)
{
    double goal_ratio = gc_params.heap_free_slots_goal_ratio;
    size_t target_total_slots;

    if (goal_ratio == 0.0) {
        target_total_slots = (size_t)(total_slots * gc_params.growth_factor);
    }
    else if (total_slots == 0) {
        target_total_slots = gc_params.heap_init_bytes / slot_size;
    }
    else {
        /* Find `f' where free_slots = f * total_slots * goal_ratio
         * => f = (total_slots - free_slots) / ((1 - goal_ratio) * total_slots)
         */
        double f = (double)(total_slots - free_slots) / ((1 - goal_ratio) * total_slots);

        if (f > gc_params.growth_factor) f = gc_params.growth_factor;
        if (f < 1.0) f = 1.1;

        target_total_slots = (size_t)(f * total_slots);

        if (0) {
            fprintf(stderr,
                    "free_slots(%8"PRIuSIZE")/total_slots(%8"PRIuSIZE")=%1.2f,"
                    " G(%1.2f), f(%1.2f),"
                    " total_slots(%8"PRIuSIZE") => target_total_slots(%8"PRIuSIZE")\n",
                    free_slots, total_slots, free_slots/(double)total_slots,
                    goal_ratio, f, total_slots, target_total_slots);
        }
    }

    if (gc_params.growth_max_bytes > 0) {
        size_t max_total_slots = total_slots + gc_params.growth_max_bytes / slot_size;
        if (target_total_slots > max_total_slots) target_total_slots = max_total_slots;
    }

    size_t extend_slot_count = target_total_slots - total_slots;
    /* Extend by at least 1 page. */
    if (extend_slot_count == 0) extend_slot_count = 1;

    objspace->heap_pages.allocatable_bytes += extend_slot_count * slot_size;
}

static inline void
heap_add_freepage(rb_heap_t *heap, struct heap_page *page)
{
    asan_unlock_freelist(page);
    GC_ASSERT(page->free_slots != 0);
    GC_ASSERT(page->free_region != NULL);

    page->free_next = heap->free_pages;
    heap->free_pages = page;

    RUBY_DEBUG_LOG("page:%p free_region:%p", (void *)page, (void *)page->free_region);

    asan_lock_freelist(page);
}

static inline void
heap_add_poolpage(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    asan_unlock_freelist(page);
    GC_ASSERT(page->free_slots != 0);
    GC_ASSERT(page->free_region != NULL);

    page->free_next = heap->pooled_pages;
    heap->pooled_pages = page;
    objspace->rincgc.pooled_slots += page->free_slots;

    asan_lock_freelist(page);
}

static void
heap_unlink_page(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    ccan_list_del(&page->page_node);
    heap->total_pages--;
    heap->total_slots -= page->total_slots;
}

static void
gc_aligned_free(void *ptr, size_t size)
{
#if defined __MINGW32__
    __mingw_aligned_free(ptr);
#elif defined _WIN32
    _aligned_free(ptr);
#elif defined(HAVE_POSIX_MEMALIGN) || defined(HAVE_MEMALIGN)
    free(ptr);
#else
    free(((void**)ptr)[-1]);
#endif
}

static void
heap_page_body_free(struct heap_page_body *page_body)
{
    GC_ASSERT((uintptr_t)page_body % HEAP_PAGE_ALIGN == 0);

    page_pool_release(page_body);
}

static void
heap_page_free(rb_objspace_t *objspace, struct heap_page *page)
{
    objspace->heap_pages.freed_pages++;
    heap_page_body_free(page->body);
    free(page);
}

static void
heap_pages_free_unused_pages(rb_objspace_t *objspace)
{
    if (objspace->empty_pages != NULL && heap_pages_freeable_pages > 0) {
        GC_ASSERT(objspace->empty_pages_count > 0);
        objspace->empty_pages = NULL;
        objspace->empty_pages_count = 0;

        size_t i, j;
        for (i = j = 0; i < rb_darray_size(objspace->heap_pages.sorted); i++) {
            struct heap_page *page = rb_darray_get(objspace->heap_pages.sorted, i);

            if (heap_page_in_global_empty_pages_pool(objspace, page) && heap_pages_freeable_pages > 0) {
                heap_page_free(objspace, page);
                heap_pages_freeable_pages--;
            }
            else {
                if (heap_page_in_global_empty_pages_pool(objspace, page)) {
                    page->free_next = objspace->empty_pages;
                    objspace->empty_pages = page;
                    objspace->empty_pages_count++;
                }

                if (i != j) {
                    rb_darray_set(objspace->heap_pages.sorted, j, page);
                }
                j++;
            }
        }

        rb_darray_pop(objspace->heap_pages.sorted, i - j);
        GC_ASSERT(rb_darray_size(objspace->heap_pages.sorted) == j);

        struct heap_page *hipage = rb_darray_get(objspace->heap_pages.sorted, rb_darray_size(objspace->heap_pages.sorted) - 1);
        uintptr_t himem = (uintptr_t)hipage->body + HEAP_PAGE_SIZE;
        GC_ASSERT(himem <= heap_pages_himem);
        heap_pages_himem = himem;

        struct heap_page *lopage = rb_darray_get(objspace->heap_pages.sorted, 0);
        uintptr_t lomem = (uintptr_t)lopage->body + sizeof(struct heap_page_header);
        GC_ASSERT(lomem >= heap_pages_lomem);
        heap_pages_lomem = lomem;
    }
}

static void *
gc_aligned_malloc(size_t alignment, size_t size)
{
    /* alignment must be a power of 2 */
    GC_ASSERT(((alignment - 1) & alignment) == 0);
    GC_ASSERT(alignment % sizeof(void*) == 0);

    void *res;

#if defined __MINGW32__
    res = __mingw_aligned_malloc(size, alignment);
#elif defined _WIN32
    void *_aligned_malloc(size_t, size_t);
    res = _aligned_malloc(size, alignment);
#elif defined(HAVE_POSIX_MEMALIGN)
    if (posix_memalign(&res, alignment, size) != 0) {
        return NULL;
    }
#elif defined(HAVE_MEMALIGN)
    res = memalign(alignment, size);
#else
    char* aligned;
    res = malloc(alignment + size + sizeof(void*));
    aligned = (char*)res + alignment + sizeof(void*);
    aligned -= ((VALUE)aligned & (alignment - 1));
    ((void**)aligned)[-1] = res;
    res = (void*)aligned;
#endif

    GC_ASSERT((uintptr_t)res % alignment == 0);

    return res;
}

/* page pool (global_objspace->page_pool)。heap page body は大きなアリーナから
 * 切り出し、pool の freelist で再利用する。 */

#define PAGE_POOL_ARENA_SIZE (HEAP_PAGE_SIZE * 32) /* 2MiB with 64KiB pages */

#ifdef HAVE_MMAP
/* 新しいアリーナを mmap し切り出し元にする。pool lock 保持で呼ばれ、この時点で前のアリーナは
 * 常に切り出し尽くされている。 */
static bool
page_pool_add_arena(rb_global_objspace_t *g)
{
    GC_ASSERT(HEAP_PAGE_ALIGN % sysconf(_SC_PAGE_SIZE) == 0);

    size_t mmap_size = PAGE_POOL_ARENA_SIZE + HEAP_PAGE_ALIGN;
    char *ptr = mmap(NULL, mmap_size,
                     PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (ptr == MAP_FAILED) {
        return false;
    }

    // If we are building `default.c` as part of the ruby executable, we
    // may just call `ruby_annotate_mmap`.  But if we are building
    // `default.c` as a shared library, we will not have access to private
    // symbols, and we have to either call prctl directly or make our own
    // wrapper.
#if defined(HAVE_SYS_PRCTL_H) && defined(PR_SET_VMA) && defined(PR_SET_VMA_ANON_NAME)
    prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, ptr, mmap_size, "Ruby:GC:default:page_pool_arena");
    errno = 0;
#endif

    /* 使用領域が HEAP_PAGE_ALIGN に整列するよう、非整列の先頭と末尾を削る。 */
    char *aligned = ptr + HEAP_PAGE_ALIGN;
    aligned -= ((uintptr_t)aligned & (HEAP_PAGE_ALIGN - 1));
    GC_ASSERT(aligned > ptr);
    GC_ASSERT(aligned <= ptr + HEAP_PAGE_ALIGN);

    size_t start_out_of_range_size = aligned - ptr;
    GC_ASSERT(start_out_of_range_size % sysconf(_SC_PAGE_SIZE) == 0);
    if (start_out_of_range_size > 0) {
        if (munmap(ptr, start_out_of_range_size)) {
            rb_bug("page_pool_add_arena: munmap failed for start");
        }
    }

    size_t end_out_of_range_size = HEAP_PAGE_ALIGN - start_out_of_range_size;
    GC_ASSERT(end_out_of_range_size % sysconf(_SC_PAGE_SIZE) == 0);
    if (end_out_of_range_size > 0) {
        if (munmap(aligned + PAGE_POOL_ARENA_SIZE, end_out_of_range_size)) {
            rb_bug("page_pool_add_arena: munmap failed for end");
        }
    }

    struct rlgc_page_arena *arena = calloc1(sizeof(struct rlgc_page_arena));
    if (arena == NULL) {
        if (munmap(aligned, PAGE_POOL_ARENA_SIZE)) {
            rb_bug("page_pool_add_arena: munmap failed for arena");
        }
        return false;
    }
    arena->start = aligned;
    arena->size = PAGE_POOL_ARENA_SIZE;
    arena->next = g->page_pool.arenas;
    g->page_pool.arenas = arena;

    g->page_pool.arena_cursor = aligned;
    g->page_pool.arena_end = aligned + PAGE_POOL_ARENA_SIZE;

    return true;
}
#endif

static struct heap_page_body *
page_pool_acquire(void)
{
    struct heap_page_body *body = NULL;

    if (HEAP_PAGE_ALLOC_USE_MMAP) {
#ifdef HAVE_MMAP
        rb_global_objspace_t *g = global_objspace;

        rb_native_mutex_lock(&g->page_pool.lock);
        if (g->page_pool.freelist != NULL) {
            body = g->page_pool.freelist;
            asan_unpoison_memory_region(body, sizeof(struct heap_page_body *), false);
            g->page_pool.freelist = *(struct heap_page_body **)body;
        }
        else if (g->page_pool.arena_cursor != g->page_pool.arena_end ||
                 page_pool_add_arena(g)) {
            GC_ASSERT(g->page_pool.arena_cursor + HEAP_PAGE_SIZE <= g->page_pool.arena_end);
            body = (struct heap_page_body *)g->page_pool.arena_cursor;
            g->page_pool.arena_cursor += HEAP_PAGE_SIZE;
        }
        rb_native_mutex_unlock(&g->page_pool.lock);

        if (body != NULL) {
            asan_unpoison_memory_region(body, HEAP_PAGE_SIZE, false);
        }
#endif
    }
    else {
        body = gc_aligned_malloc(HEAP_PAGE_ALIGN, HEAP_PAGE_SIZE);
    }

    return body;
}

static void
page_pool_release(struct heap_page_body *body)
{
    if (HEAP_PAGE_ALLOC_USE_MMAP) {
#ifdef HAVE_MMAP
        rb_global_objspace_t *g = global_objspace;

        rb_native_mutex_lock(&g->page_pool.lock);
        /* empty pages pool に置かれたページの body は完全に poison されたまま
         * （gc_sweep_page 参照）。pool freelist に繋ぐ前に先頭を unpoison する。 */
        asan_unpoison_memory_region(body, sizeof(struct heap_page_body *), false);
        *(struct heap_page_body **)body = g->page_pool.freelist;
        g->page_pool.freelist = body;
        asan_poison_memory_region(body, HEAP_PAGE_SIZE);
        rb_native_mutex_unlock(&g->page_pool.lock);
#endif
    }
    else {
        gc_aligned_free(body, HEAP_PAGE_SIZE);
    }
}

static struct heap_page_body *
heap_page_body_allocate(void)
{
    struct heap_page_body *page_body = page_pool_acquire();

    GC_ASSERT(page_body == NULL || (uintptr_t)page_body % HEAP_PAGE_ALIGN == 0);

    return page_body;
}

static struct heap_page *
heap_page_resurrect(rb_objspace_t *objspace)
{
    struct heap_page *page = NULL;
    if (objspace->empty_pages == NULL) {
        GC_ASSERT(objspace->empty_pages_count == 0);
    }
    else {
        GC_ASSERT(objspace->empty_pages_count > 0);
        objspace->empty_pages_count--;
        page = objspace->empty_pages;
        objspace->empty_pages = page->free_next;
    }

    return page;
}

static struct heap_page *
heap_page_allocate(rb_objspace_t *objspace)
{
    struct heap_page_body *page_body = heap_page_body_allocate();
    if (page_body == 0) {
        rb_memerror();
    }

    struct heap_page *page = calloc1(sizeof(struct heap_page));
    if (page == 0) {
        heap_page_body_free(page_body);
        rb_memerror();
    }

    uintptr_t start = (uintptr_t)page_body + sizeof(struct heap_page_header);
    uintptr_t end = (uintptr_t)page_body + HEAP_PAGE_SIZE;

    size_t lo = 0;
    size_t hi = rb_darray_size(objspace->heap_pages.sorted);
    while (lo < hi) {
        struct heap_page *mid_page;

        size_t mid = (lo + hi) / 2;
        mid_page = rb_darray_get(objspace->heap_pages.sorted, mid);
        if ((uintptr_t)mid_page->start < start) {
            lo = mid + 1;
        }
        else if ((uintptr_t)mid_page->start > start) {
            hi = mid;
        }
        else {
            rb_bug("same heap page is allocated: %p at %"PRIuVALUE, (void *)page_body, (VALUE)mid);
        }
    }

    rb_darray_insert_without_gc(&objspace->heap_pages.sorted, hi, page);

    if (heap_pages_lomem == 0 || heap_pages_lomem > start) heap_pages_lomem = start;
    if (heap_pages_himem < end) heap_pages_himem = end;

    page->body = page_body;
    page_body->header.page = page;
    page->objspace = objspace;

    objspace->heap_pages.allocated_pages++;

    return page;
}

static void
heap_add_page(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    /* Adding to eden heap during incremental sweeping is forbidden */
    GC_ASSERT(!heap->sweeping_page);
    GC_ASSERT(heap_page_in_global_empty_pages_pool(objspace, page));

    /* Align start to slot_size boundary */
    uintptr_t start = (uintptr_t)page->body + sizeof(struct heap_page_header);
    uintptr_t rem = start % heap->slot_size;
    if (rem) start += heap->slot_size - rem;

    int slot_count = (int)((HEAP_PAGE_SIZE - (start - (uintptr_t)page->body))/heap->slot_size);

    page->start = start;
    page->total_slots = slot_count;
    page->slot_size = heap->slot_size;
    page->slot_size_reciprocal = heap_slot_reciprocal_table[heap - heaps];
    page->heap = heap;

    memset(&page->wb_unprotected_bits[0], 0, HEAP_PAGE_BITMAP_SIZE);
    memset(&page->age_bits[0], 0, sizeof(page->age_bits));

    asan_unlock_freelist(page);
    asan_unpoison_memory_region(page->body, HEAP_PAGE_SIZE, false);

    uintptr_t slots_end = start + (uintptr_t)slot_count * heap->slot_size;

    memset((void *)start, 0, slots_end - start);

    struct free_region *region = (struct free_region *)start;
    region->flags = 0;
    region->end = slots_end;
    region->next = NULL;
    page->free_region = region;

    /* Poison every free slot; each is unpoisoned again as it is handed out. */
    for (uintptr_t p = start; p < slots_end; p += heap->slot_size) {
        rb_asan_poison_object((VALUE)p);
    }
    asan_lock_freelist(page);

    page->free_slots = slot_count;

    heap->total_allocated_pages++;

    ccan_list_add_tail(&heap->pages, &page->page_node);
    heap->total_pages++;
    heap->total_slots += page->total_slots;
}

static int
heap_page_allocate_and_initialize(rb_objspace_t *objspace, rb_heap_t *heap)
{
    gc_report(1, objspace, "heap_page_allocate_and_initialize: rb_darray_size(objspace->heap_pages.sorted): %"PRIdSIZE", "
                  "allocatable_bytes: %"PRIdSIZE", heap->total_pages: %"PRIdSIZE"\n",
                  rb_darray_size(objspace->heap_pages.sorted), objspace->heap_pages.allocatable_bytes, heap->total_pages);

    bool allocated = false;
    struct heap_page *page = heap_page_resurrect(objspace);

    if (page == NULL && objspace->heap_pages.allocatable_bytes > 0) {
        page = heap_page_allocate(objspace);
        allocated = true;

        GC_ASSERT(page != NULL);
    }

    if (page != NULL) {
        heap_add_page(objspace, heap, page);
        heap_add_freepage(heap, page);

        if (allocated) {
            size_t page_bytes = (size_t)page->total_slots * page->slot_size;
            if (objspace->heap_pages.allocatable_bytes > page_bytes) {
                objspace->heap_pages.allocatable_bytes -= page_bytes;
            }
            else {
                objspace->heap_pages.allocatable_bytes = 0;
            }
        }
    }

    return page != NULL;
}

static void
heap_page_allocate_and_initialize_force(rb_objspace_t *objspace, rb_heap_t *heap)
{
    size_t prev_allocatable_bytes = objspace->heap_pages.allocatable_bytes;
    objspace->heap_pages.allocatable_bytes = HEAP_PAGE_SIZE;
    heap_page_allocate_and_initialize(objspace, heap);
    GC_ASSERT(heap->free_pages != NULL);
    objspace->heap_pages.allocatable_bytes = prev_allocatable_bytes;
}

static void
gc_continue(rb_objspace_t *objspace, rb_heap_t *heap)
{
    unsigned int lock_lev;
    bool needs_gc = is_incremental_marking(objspace) || needs_continue_sweeping(objspace, heap);
    if (!needs_gc) return;

    gc_enter(objspace, gc_enter_event_continue, &lock_lev); // takes vm barrier, try to avoid

    /* Continue marking if in incremental marking. */
    if (is_incremental_marking(objspace)) {
        if (gc_marks_continue(objspace, heap)) {
            gc_sweep(objspace);
        }
    }

    if (needs_continue_sweeping(objspace, heap)) {
        gc_sweep_continue(objspace, heap);
    }

    gc_exit(objspace, gc_enter_event_continue, &lock_lev);
}

static void
heap_prepare(rb_objspace_t *objspace, rb_heap_t *heap)
{
    GC_ASSERT(heap->free_pages == NULL);

    if (heap->total_slots < gc_params.heap_init_bytes / heap->slot_size &&
            heap->sweeping_page == NULL) {
        heap_page_allocate_and_initialize_force(objspace, heap);
        GC_ASSERT(heap->free_pages != NULL);
        return;
    }

    /* Continue incremental marking or lazy sweeping, if in any of those steps. */
    gc_continue(objspace, heap);

    if (heap->free_pages == NULL) {
        heap_page_allocate_and_initialize(objspace, heap);
    }

    /* If we still don't have a free page and not allowed to create a new page,
     * we should start a new GC cycle. */
    if (heap->free_pages == NULL) {
        GC_ASSERT(objspace->empty_pages_count == 0);
        GC_ASSERT(objspace->heap_pages.allocatable_bytes == 0);

        if (gc_start(objspace, GPR_FLAG_NEWOBJ) == FALSE) {
            rb_memerror();
        }
        else {
            if (objspace->heap_pages.allocatable_bytes == 0 && !gc_config_full_mark_val) {
                heap_allocatable_bytes_expand(objspace, heap,
                        heap->freed_slots + heap->empty_slots,
                        heap->total_slots, heap->slot_size);
                GC_ASSERT(objspace->heap_pages.allocatable_bytes > 0);
            }
            /* Do steps of incremental marking or lazy sweeping if the GC run permits. */
            gc_continue(objspace, heap);

            /* If we're not incremental marking (e.g. a minor GC) or finished
             * sweeping and still don't have a free page, then
             * gc_sweep_finish_heap should allow us to create a new page. */
            if (heap->free_pages == NULL && !heap_page_allocate_and_initialize(objspace, heap)) {
                if (gc_needs_major_flags == GPR_FLAG_NONE) {
                    rb_bug("cannot create a new page after GC");
                }
                else { // Major GC is required, which will allow us to create new page
                    if (gc_start(objspace, GPR_FLAG_NEWOBJ) == FALSE) {
                        rb_memerror();
                    }
                    else {
                        /* Do steps of incremental marking or lazy sweeping. */
                        gc_continue(objspace, heap);

                        if (heap->free_pages == NULL &&
                                !heap_page_allocate_and_initialize(objspace, heap)) {
                            rb_bug("cannot create a new page after major GC");
                        }
                    }
                }
            }
        }
    }

    GC_ASSERT(heap->free_pages != NULL);
}

#if GC_DEBUG
static inline const char*
rb_gc_impl_source_location_cstr(int *ptr)
{
    /* We could directly refer `rb_source_location_cstr()` before, but not any
     * longer.  We have to heavy lift using our debugging API. */
    if (! ptr) {
        return NULL;
    }
    else if (! (*ptr = rb_sourceline())) {
        return NULL;
    }
    else {
        return rb_sourcefile();
    }
}
#endif

static inline VALUE
newobj_init(VALUE klass, VALUE flags, int wb_protected, rb_objspace_t *objspace, VALUE obj)
{
    GC_ASSERT(BUILTIN_TYPE(obj) == T_NONE);
    GC_ASSERT((flags & FL_WB_PROTECTED) == 0);
    RBASIC(obj)->flags = flags;
    *((VALUE *)&RBASIC(obj)->klass) = klass;
#if RBASIC_SHAPE_ID_FIELD
    RBASIC(obj)->shape_id = 0;
#endif

    if (RB_UNLIKELY(flags & RUBY_FL_SHAREABLE)) {
        /* born-shareable は WB protected でなければならない
         * (shareable の shref/remset 規律は WB 前提)。 */
        GC_ASSERT(wb_protected);
        /* born-shareable をページの bitmap にも反映する。local GC は
         * ここから shareable を root にする（rlgc_pinned_roots_mark）。 */
        struct heap_page *page = GET_HEAP_PAGE(obj);
        _MARK_IN_BITMAP(page->shareable_bits, page, obj);
        page->has_shareable_objects = TRUE;
        objspace->rlgc.shareable_objects++;
    }

#if RGENGC_CHECK_MODE
    int lev = RB_GC_VM_LOCK_NO_BARRIER();
    {
        check_rvalue_consistency(objspace, obj);

        GC_ASSERT(RVALUE_MARKED(objspace, obj) == FALSE);
        GC_ASSERT(RVALUE_MARKING(objspace, obj) == FALSE);
        GC_ASSERT(RVALUE_OLD_P(objspace, obj) == FALSE);
        GC_ASSERT(RVALUE_WB_UNPROTECTED(objspace, obj) == FALSE);

        if (RVALUE_REMEMBERED(objspace, obj)) rb_bug("newobj: %s is remembered.", rb_obj_info(obj));
    }
    RB_GC_VM_UNLOCK_NO_BARRIER(lev);
#endif

    if (RB_UNLIKELY(wb_protected == FALSE)) {
        MARK_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(obj), obj);
    }

#if RGENGC_PROFILE
    if (wb_protected) {
        objspace->profile.total_generated_normal_object_count++;
#if RGENGC_PROFILE >= 2
        objspace->profile.generated_normal_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
    }
    else {
        objspace->profile.total_generated_shady_object_count++;
#if RGENGC_PROFILE >= 2
        objspace->profile.generated_shady_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
    }
#endif

#if GC_DEBUG
    GET_RVALUE_OVERHEAD(obj)->file = rb_gc_impl_source_location_cstr(&GET_RVALUE_OVERHEAD(obj)->line);
    GC_ASSERT(!SPECIAL_CONST_P(obj)); /* check alignment */
#endif

    gc_report(5, objspace, "newobj: %s\n", rb_obj_info(obj));

    // RUBY_DEBUG_LOG("obj:%p (%s)", (void *)obj, rb_obj_info(obj));
    return obj;
}

size_t
rb_gc_impl_obj_slot_size(VALUE obj)
{
    return GET_HEAP_PAGE(obj)->slot_size - RVALUE_OVERHEAD;
}

static inline size_t
heap_slot_size(unsigned char pool_id)
{
    GC_ASSERT(pool_id < HEAP_COUNT);

    return pool_slot_sizes[pool_id] - RVALUE_OVERHEAD;
}

size_t
rb_gc_impl_max_allocation_size(void)
{
    return heap_slot_size(HEAP_COUNT - 1);
}

bool
rb_gc_impl_size_allocatable_p(size_t size)
{
    return size <= rb_gc_impl_max_allocation_size();
}

static inline bool
heap_advance_region(rb_heap_t *heap)
{
    struct free_region *region = heap->alloc_next_region;
    if (region == NULL) {
        return false;
    }

    rb_asan_unpoison_object((VALUE)region, false);
    GC_ASSERT(RB_TYPE_P((VALUE)region, T_NONE));
    heap->alloc_cursor = (uintptr_t)region;
    heap->alloc_cursor_end = region->end;
    heap->alloc_next_region = region->next;
    rb_asan_poison_object((VALUE)region);

    return true;
}

static inline VALUE
heap_alloc_slot(rb_objspace_t *objspace, size_t heap_idx)
{
    rb_heap_t *heap = &heaps[heap_idx];

    uintptr_t cursor = heap->alloc_cursor;
    if (RB_UNLIKELY(cursor >= heap->alloc_cursor_end)) {
        if (heap_advance_region(heap) == false) {
            return Qfalse;
        }
        cursor = heap->alloc_cursor;
    }

    if (RB_UNLIKELY(is_incremental_marking(objspace))) {
        // Not allowed to allocate without running an incremental marking step
        if (objspace->incremental_mark_step_allocated_slots >= INCREMENTAL_MARK_STEP_ALLOCATIONS) {
            return Qfalse;
        }

        objspace->incremental_mark_step_allocated_slots++;
    }

    VALUE obj = (VALUE)cursor;
    rb_asan_unpoison_object(obj, true);
    heap->alloc_cursor = cursor + pool_slot_sizes[heap_idx];

    /* single-writer（所有 Ractor の GVL）なので素のインクリメントで足りる。 */
    heap->total_allocated_objects++;

#if RGENGC_CHECK_MODE
    GC_ASSERT(rb_gc_impl_obj_slot_size(obj) == heap_slot_size(heap_idx));
    // zero clear
    MEMZERO((char *)obj, char, heap_slot_size(heap_idx));
#endif
    return obj;
}

static struct heap_page *
heap_next_free_page(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page;

    if (heap->free_pages == NULL) {
        heap_prepare(objspace, heap);
    }

    page = heap->free_pages;
    heap->free_pages = page->free_next;

    GC_ASSERT(page->free_slots != 0);

    asan_unlock_freelist(page);

    return page;
}

static inline void
heap_set_alloc_page(rb_objspace_t *objspace, size_t heap_idx, struct heap_page *page)
{
    gc_report(3, objspace, "heap_set_alloc_page: Using page %p\n", (void *)page->body);

    rb_heap_t *heap = &heaps[heap_idx];

    GC_ASSERT(heap->alloc_cursor >= heap->alloc_cursor_end);
    GC_ASSERT(heap->alloc_next_region == NULL);
    GC_ASSERT(page->free_slots != 0);
    GC_ASSERT(page->free_region != NULL);

    heap->alloc_using_page = page;

    struct free_region *region = page->free_region;
    rb_asan_unpoison_object((VALUE)region, false);
    GC_ASSERT(RB_TYPE_P((VALUE)region, T_NONE));
    heap->alloc_cursor = (uintptr_t)region;
    heap->alloc_cursor_end = region->end;
    heap->alloc_next_region = region->next;
    rb_asan_poison_object((VALUE)region);

    page->free_slots = 0;
    page->free_region = NULL;
}

static void
init_size_to_heap_idx(void)
{
    /* この表はプロセス共通で内容は変わらないので起動時に 1 度だけ作る。後の objspace_init
     * （Ractor 生成）で作り直すと同じ値を書くだけだが、他スレッドの lock-free な割り当て
     * fast path の読み取りと競合する。 */
    static bool initialized = false;
    if (initialized) return;
    initialized = true;

    for (size_t i = 0; i < sizeof(size_to_heap_idx); i++) {
        size_t effective = i * 8 + RVALUE_OVERHEAD;
        uint8_t idx;
        for (idx = 0; idx < HEAP_COUNT; idx++) {
            if (effective <= pool_slot_sizes[idx]) break;
        }
        size_to_heap_idx[i] = idx;
    }
}

static inline size_t
heap_idx_for_size(size_t size)
{
    size_t compressed = (size + 7) >> 3;
    if (compressed < sizeof(size_to_heap_idx)) {
        size_t heap_idx = size_to_heap_idx[compressed];
        if (RB_LIKELY(heap_idx < HEAP_COUNT)) return heap_idx;
    }

    rb_bug("heap_idx_for_size: allocation size too large "
           "(size=%"PRIuSIZE")", size);
}

size_t
rb_gc_impl_size_slot_size(void *objspace_ptr, size_t size)
{
    return heap_slot_size((unsigned char)heap_idx_for_size(size));
}

bool
rb_gc_impl_zjit_new_obj_fastpath(void *objspace_ptr, size_t alloc_size, VALUE flags, VALUE klass,
                                 struct rb_gc_zjit_fastpath *fastpath)
{
    /* bump-pointer 割り当ての状態は objspace ごとの heaps にあり、ZJIT の inline
     * fastpath はそれとは別の cache 構造体を前提にしている。「fastpath なし」を返し、
     * 呼び出し側は通常の割り当て経路に fallback する（gc/wbcheck と同じ）。
     * heaps は single-writer なので、heap 直結の fastpath は将来提供しうる。 */
    return false;
}

NOINLINE(static VALUE newobj_refill(rb_objspace_t *objspace, size_t heap_idx));

static VALUE
newobj_refill(rb_objspace_t *objspace, size_t heap_idx)
{
    rb_heap_t *heap = &heaps[heap_idx];
    VALUE obj = Qfalse;

    /* lock なし。heap は single-writer（所有者スレッドが Ractor 内で GVL 直列化）で、
     * page pool は独自 mutex を持ち、ここから始まる GC は gc_enter が必要な分だけ取る。 */
    if (is_incremental_marking(objspace)) {
        gc_continue(objspace, heap);
        objspace->incremental_mark_step_allocated_slots = 0;

        // Retry allocation after resetting incremental_mark_step_allocated_slots
        obj = heap_alloc_slot(objspace, heap_idx);
    }

    if (obj == Qfalse) {
        // Get next free page (possibly running GC)
        struct heap_page *page = heap_next_free_page(objspace, heap);
        heap_set_alloc_page(objspace, heap_idx, page);

        // Retry allocation after moving to new page
        obj = heap_alloc_slot(objspace, heap_idx);
    }

    if (RB_UNLIKELY(obj == Qfalse)) {
        rb_memerror();
    }
    return obj;
}

static VALUE
newobj_alloc(rb_objspace_t *objspace, size_t heap_idx)
{
    /* objspace は現在の Ractor のもので single-writer なので、fast path に lock は不要。 */
    VALUE obj = heap_alloc_slot(objspace, heap_idx);

    if (RB_UNLIKELY(obj == Qfalse)) {
        obj = newobj_refill(objspace, heap_idx);
    }

    return obj;
}

ALWAYS_INLINE(static VALUE newobj_slowpath(VALUE klass, VALUE flags, rb_objspace_t *objspace, int wb_protected, size_t heap_idx));

static inline VALUE
newobj_slowpath(VALUE klass, VALUE flags, rb_objspace_t *objspace, int wb_protected, size_t heap_idx)
{
    VALUE obj;

    /* lock なし（newobj_refill 参照）。during_gc と stress フラグはこの objspace 自身の状態。 */
    if (RB_UNLIKELY(during_gc || ruby_gc_stressful)) {
        if (during_gc) {
            dont_gc_on();
            during_gc = 0;
            if (rb_memerror_reentered()) {
                rb_memerror();
            }
            rb_bug("object allocation during garbage collection phase");
        }

        if (ruby_gc_stressful) {
            if (!garbage_collect(objspace, GPR_FLAG_NEWOBJ)) {
                rb_memerror();
            }
        }
    }

    obj = newobj_alloc(objspace, heap_idx);
    newobj_init(klass, flags, wb_protected, objspace, obj);

    return obj;
}

NOINLINE(static VALUE newobj_slowpath_wb_protected(VALUE klass, VALUE flags,
                                                   rb_objspace_t *objspace, size_t heap_idx));
NOINLINE(static VALUE newobj_slowpath_wb_unprotected(VALUE klass, VALUE flags,
                                                     rb_objspace_t *objspace, size_t heap_idx));

static VALUE
newobj_slowpath_wb_protected(VALUE klass, VALUE flags, rb_objspace_t *objspace, size_t heap_idx)
{
    return newobj_slowpath(klass, flags, objspace, TRUE, heap_idx);
}

static VALUE
newobj_slowpath_wb_unprotected(VALUE klass, VALUE flags, rb_objspace_t *objspace, size_t heap_idx)
{
    return newobj_slowpath(klass, flags, objspace, FALSE, heap_idx);
}

VALUE
rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, bool wb_protected, size_t alloc_size, size_t *actual_alloc_size)
{
    VALUE obj;
    rb_objspace_t *objspace = objspace_ptr;

    /* per-Ractor cache は無い。引数は他の GC 実装（例: MMTk）との ABI 互換のため残す。 */
    (void)cache_ptr;

    RB_DEBUG_COUNTER_INC(obj_newobj);
    (void)RB_DEBUG_COUNTER_INC_IF(obj_newobj_wb_unprotected, !wb_protected);

    if (RB_UNLIKELY(stress_to_class)) {
        if (rb_hash_lookup2(stress_to_class, klass, Qundef) != Qundef) {
            rb_memerror();
        }
    }

    size_t heap_idx = heap_idx_for_size(alloc_size);
    *actual_alloc_size = heap_slot_size((unsigned char)heap_idx);

    if (!RB_UNLIKELY(during_gc || ruby_gc_stressful) &&
            wb_protected) {
        obj = newobj_alloc(objspace, heap_idx);
        newobj_init(klass, flags, wb_protected, objspace, obj);
    }
    else {
        RB_DEBUG_COUNTER_INC(obj_newobj_slowpath);

        obj = wb_protected ?
          newobj_slowpath_wb_protected(klass, flags, objspace, heap_idx) :
          newobj_slowpath_wb_unprotected(klass, flags, objspace, heap_idx);
    }

    return obj;
}

static int
ptr_in_page_body_p(const void *ptr, const void *memb)
{
    struct heap_page *page = *(struct heap_page **)memb;
    uintptr_t p_body = (uintptr_t)page->body;

    if ((uintptr_t)ptr >= p_body) {
        return (uintptr_t)ptr < (p_body + HEAP_PAGE_SIZE) ? 0 : 1;
    }
    else {
        return -1;
    }
}

PUREFUNC(static inline struct heap_page *heap_page_for_ptr(rb_objspace_t *objspace, uintptr_t ptr);)
static inline struct heap_page *
heap_page_for_ptr(rb_objspace_t *objspace, uintptr_t ptr)
{
    struct heap_page **res;

    if (ptr < (uintptr_t)heap_pages_lomem ||
            ptr > (uintptr_t)heap_pages_himem) {
        return NULL;
    }

    res = bsearch((void *)ptr, rb_darray_ref(objspace->heap_pages.sorted, 0),
                  rb_darray_size(objspace->heap_pages.sorted), sizeof(struct heap_page *),
                  ptr_in_page_body_p);

    if (res) {
        return *res;
    }
    else {
        return NULL;
    }
}

PUREFUNC(static inline bool is_pointer_to_heap(rb_objspace_t *objspace, const void *ptr);)
static inline bool
is_pointer_to_heap(rb_objspace_t *objspace, const void *ptr)
{
    register uintptr_t p = (uintptr_t)ptr;
    register struct heap_page *page;

    RB_DEBUG_COUNTER_INC(gc_isptr_trial);

    if (p < heap_pages_lomem || p > heap_pages_himem) return FALSE;
    RB_DEBUG_COUNTER_INC(gc_isptr_range);

    if (p % sizeof(VALUE) != 0) return FALSE;
    RB_DEBUG_COUNTER_INC(gc_isptr_align);

    page = heap_page_for_ptr(objspace, (uintptr_t)ptr);
    if (page) {
        RB_DEBUG_COUNTER_INC(gc_isptr_maybe);
        if (heap_page_in_global_empty_pages_pool(objspace, page)) {
            return FALSE;
        }
        else {
            if (p < page->start) return FALSE;
            if (p >= page->start + (page->total_slots * page->slot_size)) return FALSE;
            if ((p - page->start) % page->slot_size != 0) return FALSE;

            return TRUE;
        }
    }
    return FALSE;
}

bool
rb_gc_impl_live_object_p(void *objspace_ptr, const void *ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    /* Whether ptr refers to a live object. is_pointer_to_heap is the
     * address-only check; T_NONE, T_MOVED, and T_ZOMBIE slots are valid heap
     * addresses but not live objects. */
    if (!is_pointer_to_heap(objspace, ptr)) return false;

    VALUE obj = (VALUE)ptr;
    bool live = false;
    asan_unpoisoning_object(obj) {
        switch (BUILTIN_TYPE(obj)) {
          case T_NONE:
          case T_MOVED:
          case T_ZOMBIE:
            break;
          default:
            live = true;
            break;
        }
    }
    return live;
}

#define ZOMBIE_OBJ_KEPT_FLAGS (FL_FINALIZE)

void
rb_gc_impl_make_zombie(void *objspace_ptr, VALUE obj, void (*dfree)(void *), void *data)
{
    rb_objspace_t *objspace = objspace_ptr;

    struct RZombie *zombie = RZOMBIE(obj);
    zombie->flags = T_ZOMBIE | (zombie->flags & ZOMBIE_OBJ_KEPT_FLAGS);
    zombie->dfree = dfree;
    zombie->data = data;
    VALUE prev, next = heap_pages_deferred_final;
    do {
        zombie->next = prev = next;
        next = RUBY_ATOMIC_VALUE_CAS(heap_pages_deferred_final, prev, obj);
    } while (next != prev);

    struct heap_page *page = GET_HEAP_PAGE(obj);
    page->final_slots++;
    page->heap->final_slots_count++;
}

typedef int each_obj_callback(void *, void *, size_t, void *);
typedef int each_page_callback(struct heap_page *, void *);

struct each_obj_data {
    rb_objspace_t *objspace;
    bool reenable_incremental;

    /* shareable を持つページだけを訪れる。foreign な Ractor の objspace を、その隔離
     * された heap の残りに触れずに、所有する shareable のためだけに歩くのに使う。 */
    bool shareable_only;

    /* foreign な objspace を、停止中の lazy sweep を落ち着かせずに歩く場合に立てる
     * （落ち着かせると所有者の obj_free/dfree がこのスレッドで走る）。sweep が free 寸前の
     * オブジェクトは飛ばす。未 sweep ページでは unmarked = dead だから。 */
    bool skip_unswept_dead;

    each_obj_callback *each_obj_callback;
    each_page_callback *each_page_callback;
    void *data;

    struct heap_page **pages[HEAP_COUNT];
    size_t pages_counts[HEAP_COUNT];
};

static VALUE
objspace_each_objects_ensure(VALUE arg)
{
    struct each_obj_data *data = (struct each_obj_data *)arg;
    rb_objspace_t *objspace = data->objspace;

    /* Reenable incremental GC */
    if (data->reenable_incremental) {
        objspace->flags.dont_incremental = FALSE;
    }

    for (int i = 0; i < HEAP_COUNT; i++) {
        struct heap_page **pages = data->pages[i];
        free(pages);
    }

    return Qnil;
}

static VALUE
objspace_each_objects_try(VALUE arg)
{
    struct each_obj_data *data = (struct each_obj_data *)arg;
    rb_objspace_t *objspace = data->objspace;

    /* Copy pages from all heaps to their respective buffers. */
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        size_t size = heap->total_pages * sizeof(struct heap_page *);

        struct heap_page **pages = malloc(size);
        if (!pages) rb_memerror();

        /* Set up pages buffer by iterating over all pages in the current eden
         * heap. This will be a snapshot of the state of the heap before we
         * call the callback over each page that exists in this buffer. Thus it
         * is safe for the callback to allocate objects without possibly entering
         * an infinite loop. */
        struct heap_page *page = 0;
        size_t pages_count = 0;
        ccan_list_for_each(&heap->pages, page, page_node) {
            pages[pages_count] = page;
            pages_count++;
        }
        data->pages[i] = pages;
        data->pages_counts[i] = pages_count;
        GC_ASSERT(pages_count == heap->total_pages);
    }

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        size_t pages_count = data->pages_counts[i];
        struct heap_page **pages = data->pages[i];

        struct heap_page *page = ccan_list_top(&heap->pages, struct heap_page, page_node);
        for (size_t i = 0; i < pages_count; i++) {
            /* If we have reached the end of the linked list then there are no
             * more pages, so break. */
            if (page == NULL) break;

            /* If this page does not match the one in the buffer, then move to
             * the next page in the buffer. */
            if (pages[i] != page) continue;

            uintptr_t pstart = (uintptr_t)page->start;
            uintptr_t pend = pstart + (page->total_slots * heap->slot_size);

            if (data->shareable_only) {
                /* ページ全体ではなく shareable を 1 個ずつ（1 slot 範囲で）callback へ渡す。
                 * foreign な Ractor の objspace の walk は、その Ractor の unshareable を
                 * 決して露出してはならない。呼び出し側は自分の Ractor の構造で走っており
                 * 安全に検査できないため。 */
                if (page->has_shareable_objects) {
                    /* この walk は foreign な objspace 上（barrier 下）で走り、所有者の停止中
                     * lazy sweep を落ち着かせてはならない。落ち着かせると所有者の
                     * obj_free/dfree がこのスレッド・この Ractor の identity で走る
                     * （誤った per-Ractor 表、foreign T_DATA dfree）。そこで gc_rest せず、
                     * sweep が free 寸前のオブジェクトを飛ばす。未 sweep ページでは unmarked が
                     * dead で shareable bit が未 bulk-clear なだけ。callback に渡すと復活させて
                     * しまう（barrier 解除直後に所有者の sweep が free する参照を渡すなど）。 */
                    const bool page_unswept = is_lazy_sweeping(objspace) && page->flags.before_sweep;
                    int planes = CEILDIV(page->total_slots, BITS_BITLENGTH);
                    uintptr_t base = pstart;
                    bool stop = false;
                    for (int j = 0; j < planes && !stop; j++) {
                        bits_t bits = page->shareable_bits[j];
                        uintptr_t slot = base;
                        while (bits) {
                            if ((bits & 1) && data->each_obj_callback &&
                                !(page_unswept && !RVALUE_MARKED(objspace, (VALUE)slot)) &&
                                (*data->each_obj_callback)((void *)slot, (void *)(slot + heap->slot_size),
                                                           heap->slot_size, data->data)) {
                                stop = true;
                                break;
                            }
                            slot += heap->slot_size;
                            bits >>= 1;
                        }
                        base += BITS_BITLENGTH * heap->slot_size;
                    }
                    if (stop) break;
                }
            }
            else if (data->skip_unswept_dead &&
                     is_lazy_sweeping(objspace) && page->flags.before_sweep) {
                /* sweep 保留中の foreign ページ。生きたオブジェクトを 1 slot ずつ渡し、
                 * barrier 解除直後に所有者の sweep が free する unmarked(dead) を飛ばす。 */
                bool stop = false;
                for (uintptr_t slot = pstart; slot < pend; slot += heap->slot_size) {
                    if (!RVALUE_MARKED(objspace, (VALUE)slot)) continue;
                    if (data->each_obj_callback &&
                        (*data->each_obj_callback)((void *)slot, (void *)(slot + heap->slot_size),
                                                   heap->slot_size, data->data)) {
                        stop = true;
                        break;
                    }
                }
                if (stop) break;
            }
            else {
                if (data->each_obj_callback &&
                    (*data->each_obj_callback)((void *)pstart, (void *)pend, heap->slot_size, data->data)) {
                    break;
                }
                if (data->each_page_callback &&
                    (*data->each_page_callback)(page, data->data)) {
                    break;
                }
            }

            page = ccan_list_next(&heap->pages, page, page_node);
        }
    }

    return Qnil;
}

static void
objspace_each_exec(bool protected, struct each_obj_data *each_obj_data)
{
    /* Disable incremental GC */
    rb_objspace_t *objspace = each_obj_data->objspace;
    bool reenable_incremental = FALSE;
    if (protected) {
        reenable_incremental = !objspace->flags.dont_incremental;

        gc_rest(objspace);
        objspace->flags.dont_incremental = TRUE;
    }

    each_obj_data->reenable_incremental = reenable_incremental;
    memset(&each_obj_data->pages, 0, sizeof(each_obj_data->pages));
    memset(&each_obj_data->pages_counts, 0, sizeof(each_obj_data->pages_counts));
    rb_ensure(objspace_each_objects_try, (VALUE)each_obj_data,
              objspace_each_objects_ensure, (VALUE)each_obj_data);
}

static void
objspace_each_objects(rb_objspace_t *objspace, each_obj_callback *callback, void *data, bool protected)
{
    struct each_obj_data each_obj_data = {
        .objspace = objspace,
        .each_obj_callback = callback,
        .each_page_callback = NULL,
        .data = data,
    };
    objspace_each_exec(protected, &each_obj_data);
}

void
rb_gc_impl_each_objects(void *objspace_ptr, each_obj_callback *callback, void *data)
{
    objspace_each_objects(objspace_ptr, callback, data, TRUE);
}

/* rb_gc_impl_each_objects と同様だが、shareable を持つページだけを訪れる。foreign な
 * Ractor の shareable に、その heap の残りを歩かず到達するのに使う。 */
void
rb_gc_impl_each_objects_shareable(void *objspace_ptr, each_obj_callback *callback, void *data)
{
    struct each_obj_data each_obj_data = {
        .objspace = objspace_ptr,
        .shareable_only = true,
        .each_obj_callback = callback,
        .each_page_callback = NULL,
        .data = data,
    };
    /* protected にしない。objspace は別 Ractor のもの（呼び出し側が barrier を保持）。
     * protected 経路は gc_rest してしまい、所有者の停止中 lazy sweep（obj_free / dfree）が
     * walk スレッド・walker の Ractor identity で走る（誤った per-Ractor 表、foreign T_DATA
     * dfree）。所有者は停止中でページリストは安定。walk 自体が dead で未 sweep の
     * オブジェクトを飛ばす（objspace_each_objects_try の shareable_only 分岐）。walker 自身の
     * incremental GC 状態は触らない。これは walker の objspace ではないため。 */
    objspace_each_exec(FALSE, &each_obj_data);
}

/* foreign な Ractor の objspace の全オブジェクト（unshareable 含む）を歩く。barrier を
 * 保持し callback が純 C（heap dump / メモリ計上）な呼び出し側専用。上の shareable walk と
 * 同様、所有者の停止中 lazy sweep は落ち着かせず、dead で未 sweep のオブジェクトは
 * walk で飛ばす（skip_unswept_dead）。 */
void
rb_gc_impl_each_objects_foreign(void *objspace_ptr, each_obj_callback *callback, void *data)
{
    struct each_obj_data each_obj_data = {
        .objspace = objspace_ptr,
        .skip_unswept_dead = true,
        .each_obj_callback = callback,
        .each_page_callback = NULL,
        .data = data,
    };
    objspace_each_exec(FALSE, &each_obj_data);
}

#if GC_CAN_COMPILE_COMPACTION
static void
objspace_each_pages(rb_objspace_t *objspace, each_page_callback *callback, void *data, bool protected)
{
    struct each_obj_data each_obj_data = {
        .objspace = objspace,
        .each_obj_callback = NULL,
        .each_page_callback = callback,
        .data = data,
    };
    objspace_each_exec(protected, &each_obj_data);
}
#endif

VALUE
rb_gc_impl_define_finalizer(void *objspace_ptr, VALUE obj, VALUE block)
{
    rb_objspace_t *objspace = objspace_ptr;
    VALUE table;
    st_data_t data;

    GC_ASSERT(!OBJ_FROZEN(obj));

    /* finalizer の登録・表・実行はすべてそのオブジェクトの objspace に属する。他 Ractor の
     * オブジェクト（shareable も含む）への finalizer 定義は拒否する。所有者の sweep が参照
     * しない表に載ってしまうため。 */
    if (GET_HEAP_OBJSPACE(obj) != objspace) {
        rb_raise(rb_eRactorIsolationError,
                 "can not define a finalizer for an object of another Ractor");
    }

    RBASIC(obj)->flags |= FL_FINALIZE;

    unsigned int lev = RB_GC_VM_LOCK();

    if (st_lookup(finalizer_table, obj, &data)) {
        table = (VALUE)data;
        VALUE dup_table = rb_ary_dup(table);

        RB_GC_VM_UNLOCK(lev);
        /* avoid duplicate block, table is usually small */
        {
            long len = RARRAY_LEN(table);
            long i;

            for (i = 0; i < len; i++) {
                VALUE recv = RARRAY_AREF(dup_table, i);
                if (rb_equal(recv, block)) { // can't be called with VM lock held
                    return recv;
                }
            }
        }
        lev = RB_GC_VM_LOCK();
        RB_GC_GUARD(dup_table);

        rb_ary_push(table, block);
    }
    else {
        table = rb_ary_new3(2, rb_obj_id(obj), block);
        rb_obj_hide(table);
        st_add_direct(finalizer_table, obj, table);
    }

    RB_GC_VM_UNLOCK(lev);

    return block;
}

void
rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    GC_ASSERT(!OBJ_FROZEN(obj));

    /* define と対称。 */
    if (GET_HEAP_OBJSPACE(obj) != objspace) {
        rb_raise(rb_eRactorIsolationError,
                 "can not undefine a finalizer of an object of another Ractor");
    }

    st_data_t data = obj;

    int lev = RB_GC_VM_LOCK();
    st_delete(finalizer_table, &data, 0);
    RB_GC_VM_UNLOCK(lev);

    FL_UNSET(obj, FL_FINALIZE);
}

void
rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj)
{
    /* finalizer は objspace をまたがない。他 Ractor のオブジェクトの複製は finalizer 無しで
     * 始まる（in-tree に跨ぐ呼び出しは無く、public な rb_gc_copy_finalizer C API を守る）。
     * 同一 objspace の複製は従来通り。表アクセスは VM lock 下で行う。 */
    rb_objspace_t *objspace = objspace_ptr;
    VALUE table;
    st_data_t data;

    if (!FL_TEST(obj, FL_FINALIZE)) return;
    if (GET_HEAP_OBJSPACE(obj) != objspace) return;

    int lev = RB_GC_VM_LOCK();
    if (RB_LIKELY(st_lookup(finalizer_table, obj, &data))) {
        table = rb_ary_dup((VALUE)data);
        RARRAY_ASET(table, 0, rb_obj_id(dest));
        st_insert(finalizer_table, dest, table);
        FL_SET(dest, FL_FINALIZE);
    }
    else {
        rb_bug("rb_gc_copy_finalizer: FL_FINALIZE set but not found in finalizer_table: %s", rb_obj_info(obj));
    }
    RB_GC_VM_UNLOCK(lev);
}

static VALUE
get_final(long i, void *data)
{
    VALUE table = (VALUE)data;

    return RARRAY_AREF(table, i + 1);
}

static unsigned int
run_final(rb_objspace_t *objspace, VALUE zombie, unsigned int lev)
{
    if (RZOMBIE(zombie)->dfree) {
        RZOMBIE(zombie)->dfree(RZOMBIE(zombie)->data);
    }

    st_data_t key = (st_data_t)zombie;
    if (FL_TEST_RAW(zombie, FL_FINALIZE)) {
        FL_UNSET(zombie, FL_FINALIZE);
        st_data_t table;
        if (st_delete(finalizer_table, &key, &table)) {
            RB_GC_VM_UNLOCK(lev);
            rb_gc_run_obj_finalizer(RARRAY_AREF(table, 0), RARRAY_LEN(table) - 1, get_final, (void *)table);
            lev = RB_GC_VM_LOCK();
        }
        else {
            rb_bug("FL_FINALIZE flag is set, but finalizers are not found");
        }
    }
    else {
        GC_ASSERT(!st_lookup(finalizer_table, key, NULL));
    }
    return lev;
}

static void
finalize_list(rb_objspace_t *objspace, VALUE zombie)
{
    while (zombie) {
        VALUE next_zombie;
        struct heap_page *page;
        rb_asan_unpoison_object(zombie, false);
        next_zombie = RZOMBIE(zombie)->next;
        page = GET_HEAP_PAGE(zombie);

        unsigned int lev = RB_GC_VM_LOCK();

        lev = run_final(objspace, zombie, lev);
        {
            GC_ASSERT(BUILTIN_TYPE(zombie) == T_ZOMBIE);
            GC_ASSERT(page->heap->final_slots_count > 0);
            GC_ASSERT(page->final_slots > 0);

            page->heap->final_slots_count--;
            page->final_slots--;
            page->free_slots++;
            RVALUE_AGE_SET_BITMAP(zombie, 0);
            heap_page_add_free_region(objspace, page, zombie);
            page->heap->total_freed_objects++;
        }
        RB_GC_VM_UNLOCK(lev);

        zombie = next_zombie;
    }
}

static void
finalize_deferred_heap_pages(rb_objspace_t *objspace)
{
    VALUE zombie;
    while ((zombie = RUBY_ATOMIC_VALUE_EXCHANGE(heap_pages_deferred_final, 0)) != 0) {
        finalize_list(objspace, zombie);
    }
}

static void
finalize_deferred(rb_objspace_t *objspace)
{
    rb_gc_set_pending_interrupt();
    finalize_deferred_heap_pages(objspace);
    rb_gc_unset_pending_interrupt();
}

static void
gc_finalize_deferred(void *dmy)
{
    /* 全 objspace で 1 つの postponed job を共有する（preregistration 表は約 32 個しか
     * 持てず Ractor は次々生成される）。deferred finalizer は job を起動したスレッドの
     * objspace、つまり現在のものに属する。 */
    rb_objspace_t *objspace = rb_gc_get_objspace();
    if (RUBY_ATOMIC_EXCHANGE(finalizing, 1)) return;

    finalize_deferred(objspace);
    RUBY_ATOMIC_SET(finalizing, 0);
}

static void
gc_finalize_deferred_register(rb_objspace_t *objspace)
{
    /* この objspace の所有者 Ractor で gc_finalize_deferred を enqueue する。global GC は
     * foreign な objspace の finalizer を deferred でき、それは driver ではなく所有者側で
     * 実行しなければならない。 */
    rb_gc_trigger_finalize_deferred(objspace, objspace->finalize_deferred_pjob);
}

static int pop_mark_stack(mark_stack_t *stack, VALUE *data);

static void
gc_abort(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (is_incremental_marking(objspace)) {
        /* Remove all objects from the mark stack. */
        VALUE obj;
        while (pop_mark_stack(&objspace->mark_stack, &obj));

        objspace->flags.during_incremental_marking = FALSE;
    }

    if (is_lazy_sweeping(objspace)) {
        objspace->sweeping_heap_count = 0;
        for (int i = 0; i < HEAP_COUNT; i++) {
            rb_heap_t *heap = &heaps[i];

            heap->sweeping_page = NULL;
            struct heap_page *page = NULL;

            ccan_list_for_each(&heap->pages, page, page_node) {
                page->flags.before_sweep = false;
            }
        }
    }

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        rgengc_mark_and_rememberset_clear(objspace, heap);
    }

    gc_mode_set(objspace, gc_mode_none);
}

void
rb_gc_impl_shutdown_free_objects(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    for (size_t i = 0; i < rb_darray_size(objspace->heap_pages.sorted); i++) {
        struct heap_page *page = rb_darray_get(objspace->heap_pages.sorted, i);
        short stride = page->slot_size;

        uintptr_t p = (uintptr_t)page->start;
        uintptr_t pend = p + page->total_slots * stride;
        for (; p < pend; p += stride) {
            VALUE vp = (VALUE)p;
            asan_unpoisoning_object(vp) {
                if (RB_BUILTIN_TYPE(vp) != T_NONE) {
                    rb_gc_obj_free_vm_weak_references(vp);
                    if (rb_gc_obj_free(objspace, vp)) {
                        RBASIC(vp)->flags = 0;
                    }
                }
            }
        }
    }
}

static int
rb_gc_impl_shutdown_call_finalizer_i(st_data_t key, st_data_t val, st_data_t _data)
{
    VALUE obj = (VALUE)key;
    VALUE table = (VALUE)val;

    GC_ASSERT(RB_FL_TEST(obj, FL_FINALIZE));
    GC_ASSERT(RB_BUILTIN_TYPE(val) == T_ARRAY);

    rb_gc_run_obj_finalizer(RARRAY_AREF(table, 0), RARRAY_LEN(table) - 1, get_final, (void *)table);

    FL_UNSET(obj, FL_FINALIZE);

    return ST_DELETE;
}

void
rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

#if RGENGC_CHECK_MODE >= 2
    gc_verify_internal_consistency(objspace);
#endif

    /* prohibit incremental GC */
    objspace->flags.dont_incremental = 1;

    if (RUBY_ATOMIC_EXCHANGE(finalizing, 1)) {
        /* Abort incremental marking and lazy sweeping to speed up shutdown. */
        gc_abort(objspace);
        dont_gc_on();
        return;
    }

    while (finalizer_table->num_entries) {
        st_foreach(finalizer_table, rb_gc_impl_shutdown_call_finalizer_i, 0);
    }

    /* run finalizers */
    finalize_deferred(objspace);
    GC_ASSERT(heap_pages_deferred_final == 0);

    /* Abort incremental marking and lazy sweeping to speed up shutdown. */
    gc_abort(objspace);

    /* prohibit GC because force T_DATA finalizers can break an object graph consistency */
    dont_gc_on();

    /* running data/file finalizers are part of garbage collection */
    unsigned int lock_lev;
    gc_enter(objspace, gc_enter_event_finalizer, &lock_lev);

    /* run data/file object's finalizers */
    for (size_t i = 0; i < rb_darray_size(objspace->heap_pages.sorted); i++) {
        struct heap_page *page = rb_darray_get(objspace->heap_pages.sorted, i);
        short stride = page->slot_size;

        uintptr_t p = (uintptr_t)page->start;
        uintptr_t pend = p + page->total_slots * stride;
        for (; p < pend; p += stride) {
            VALUE vp = (VALUE)p;
            asan_unpoisoning_object(vp) {
                if (rb_gc_shutdown_call_finalizer_p(vp)) {
                    rb_gc_obj_free_vm_weak_references(vp);
                    if (rb_gc_obj_free(objspace, vp)) {
                        RBASIC(vp)->flags = 0;
                    }
                }
            }
        }
    }

    gc_exit(objspace, gc_enter_event_finalizer, &lock_lev);

    finalize_deferred_heap_pages(objspace);

    st_free_table(finalizer_table);
    finalizer_table = 0;
    RUBY_ATOMIC_SET(finalizing, 0);
}

void
rb_gc_impl_each_object(void *objspace_ptr, void (*func)(VALUE obj, void *data), void *data)
{
    rb_objspace_t *objspace = objspace_ptr;

    for (size_t i = 0; i < rb_darray_size(objspace->heap_pages.sorted); i++) {
        struct heap_page *page = rb_darray_get(objspace->heap_pages.sorted, i);
        short stride = page->slot_size;

        uintptr_t p = (uintptr_t)page->start;
        uintptr_t pend = p + page->total_slots * stride;
        for (; p < pend; p += stride) {
            VALUE obj = (VALUE)p;

            asan_unpoisoning_object(obj) {
                func(obj, data);
            }
        }
    }
}

/*
  ------------------------ Garbage Collection ------------------------
*/

/* Sweeping */

static size_t
objspace_available_slots(rb_objspace_t *objspace)
{
    size_t total_slots = 0;
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        total_slots += heap->total_slots;
    }
    return total_slots;
}

static size_t
objspace_live_slots(rb_objspace_t *objspace)
{
    return total_allocated_objects(objspace) - total_freed_objects(objspace) - total_final_slots_count(objspace);
}

static size_t
objspace_free_slots(rb_objspace_t *objspace)
{
    return objspace_available_slots(objspace) - objspace_live_slots(objspace) - total_final_slots_count(objspace);
}

static void
gc_setup_mark_bits(struct heap_page *page)
{
    /* copy oldgen bitmap to mark bitmap */
    memcpy(&page->mark_bits[0], &page->uncollectible_bits[0], HEAP_PAGE_BITMAP_SIZE);
}

static int gc_is_moveable_obj(rb_objspace_t *objspace, VALUE obj);
static VALUE gc_move(rb_objspace_t *objspace, VALUE scan, VALUE free, struct heap_page *src_page, struct heap_page *dest_page);

#if defined(_WIN32)
enum {HEAP_PAGE_LOCK = PAGE_NOACCESS, HEAP_PAGE_UNLOCK = PAGE_READWRITE};

static BOOL
protect_page_body(struct heap_page_body *body, DWORD protect)
{
    DWORD old_protect;
    return VirtualProtect(body, HEAP_PAGE_SIZE, protect, &old_protect) != 0;
}
#elif defined(__wasi__)
// wasi-libc's mprotect emulation does not support PROT_NONE
enum {HEAP_PAGE_LOCK, HEAP_PAGE_UNLOCK};
#define protect_page_body(body, protect) 1
#else
enum {HEAP_PAGE_LOCK = PROT_NONE, HEAP_PAGE_UNLOCK = PROT_READ | PROT_WRITE};
#define protect_page_body(body, protect) !mprotect((body), HEAP_PAGE_SIZE, (protect))
#endif

static void
lock_page_body(rb_objspace_t *objspace, struct heap_page_body *body)
{
    if (!protect_page_body(body, HEAP_PAGE_LOCK)) {
        rb_bug("Couldn't protect page %p, errno: %s", (void *)body, strerror(errno));
    }
    else {
        gc_report(5, objspace, "Protecting page in move %p\n", (void *)body);
    }
}

static void
unlock_page_body(rb_objspace_t *objspace, struct heap_page_body *body)
{
    if (!protect_page_body(body, HEAP_PAGE_UNLOCK)) {
        rb_bug("Couldn't unprotect page %p, errno: %s", (void *)body, strerror(errno));
    }
    else {
        gc_report(5, objspace, "Unprotecting page in move %p\n", (void *)body);
    }
}

static uintptr_t
heap_page_alloc_slot_from_region(struct heap_page *free_page)
{
    asan_unlock_freelist(free_page);
    struct free_region *region = free_page->free_region;
    asan_lock_freelist(free_page);

    if (region == NULL) {
        return 0;
    }

    rb_asan_unpoison_object((VALUE)region, false);
    GC_ASSERT(RB_TYPE_P((VALUE)region, T_NONE));
    uintptr_t dest = (uintptr_t)region;
    uintptr_t region_end = region->end;
    struct free_region *next = region->next;

    uintptr_t new_start = dest + free_page->slot_size;

    asan_unlock_freelist(free_page);
    if (new_start < region_end) {
        VALUE next_start = (VALUE)new_start;
        rb_asan_unpoison_object(next_start, false);
        struct free_region *new_region = (struct free_region *)new_start;
        new_region->flags = 0;
        new_region->end = region_end;
        new_region->next = next;
        rb_asan_poison_object(next_start);
        free_page->free_region = new_region;
    }
    else {
        free_page->free_region = next;
    }
    asan_lock_freelist(free_page);

    return dest;
}

static bool
try_move(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *free_page, VALUE src)
{
    GC_ASSERT(gc_is_moveable_obj(objspace, src));

    struct heap_page *src_page = GET_HEAP_PAGE(src);
    if (!free_page) {
        return false;
    }

    /* We should return true if either src is successfully moved, or src is
     * unmoveable. A false return will cause the sweeping cursor to be
     * incremented to the next page, and src will attempt to move again */
    GC_ASSERT(RVALUE_MARKED(objspace, src));

    uintptr_t dest_slot = heap_page_alloc_slot_from_region(free_page);
    if (dest_slot == 0) {
        return false;
    }
    VALUE dest = (VALUE)dest_slot;

    GC_ASSERT(RB_BUILTIN_TYPE(dest) == T_NONE);

    if (src_page->slot_size > free_page->slot_size) {
        objspace->rcompactor.moved_down_count_table[BUILTIN_TYPE(src)]++;
    }
    else if (free_page->slot_size > src_page->slot_size) {
        objspace->rcompactor.moved_up_count_table[BUILTIN_TYPE(src)]++;
    }
    objspace->rcompactor.moved_count_table[BUILTIN_TYPE(src)]++;
    objspace->rcompactor.total_moved++;

    gc_move(objspace, src, dest, src_page, free_page);
    gc_pin(objspace, src);
    free_page->free_slots--;

    return true;
}

static void
gc_unprotect_pages(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *cursor = heap->compact_cursor;

    while (cursor) {
        unlock_page_body(objspace, cursor->body);
        cursor = ccan_list_next(&heap->pages, cursor, page_node);
    }
}

static void gc_update_references(rb_objspace_t *objspace);
static void gc_update_references_heap(rb_objspace_t *objspace);
static void gc_update_references_global(rb_objspace_t *objspace);
#if GC_CAN_COMPILE_COMPACTION
static void invalidate_moved_page(rb_objspace_t *objspace, struct heap_page *page);
#endif

#if defined(__MINGW32__) || defined(_WIN32)
# define GC_COMPACTION_SUPPORTED 1
#else
/* If not MinGW, Windows, or does not have mmap, we cannot use mprotect for
 * the read barrier, so we must disable compaction. */
# define GC_COMPACTION_SUPPORTED (GC_CAN_COMPILE_COMPACTION && HEAP_PAGE_ALLOC_USE_MMAP)
#endif

#if GC_CAN_COMPILE_COMPACTION
static void
read_barrier_handler(uintptr_t address)
{
    rb_objspace_t *objspace = (rb_objspace_t *)rb_gc_get_objspace();

    struct heap_page_body *page_body = GET_PAGE_BODY(address);

    /* If the page_body is NULL, then mprotect cannot handle it and will crash
     * with "Cannot allocate memory". */
    if (page_body == NULL) {
        rb_bug("read_barrier_handler: segmentation fault at %p", (void *)address);
    }

    int lev = RB_GC_VM_LOCK();
    {
        unlock_page_body(objspace, page_body);

        objspace->profile.read_barrier_faults++;

        invalidate_moved_page(objspace, GET_HEAP_PAGE(address));
    }
    RB_GC_VM_UNLOCK(lev);
}
#endif

#if !GC_CAN_COMPILE_COMPACTION
static void
uninstall_handlers(void)
{
    /* no-op */
}

static void
install_handlers(void)
{
    /* no-op */
}
#elif defined(_WIN32)
static LPTOP_LEVEL_EXCEPTION_FILTER old_handler;
typedef void (*signal_handler)(int);
static signal_handler old_sigsegv_handler;

static LONG WINAPI
read_barrier_signal(EXCEPTION_POINTERS *info)
{
    /* EXCEPTION_ACCESS_VIOLATION is what's raised by access to protected pages */
    if (info->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION) {
        /* > The second array element specifies the virtual address of the inaccessible data.
         * https://docs.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-exception_record
         *
         * Use this address to invalidate the page */
        read_barrier_handler((uintptr_t)info->ExceptionRecord->ExceptionInformation[1]);
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    else {
        return EXCEPTION_CONTINUE_SEARCH;
    }
}

static void
uninstall_handlers(void)
{
    signal(SIGSEGV, old_sigsegv_handler);
    SetUnhandledExceptionFilter(old_handler);
}

static void
install_handlers(void)
{
    /* Remove SEGV handler so that the Unhandled Exception Filter handles it */
    old_sigsegv_handler = signal(SIGSEGV, NULL);
    /* Unhandled Exception Filter has access to the violation address similar
     * to si_addr from sigaction */
    old_handler = SetUnhandledExceptionFilter(read_barrier_signal);
}
#else
static struct sigaction old_sigbus_handler;
static struct sigaction old_sigsegv_handler;

#ifdef HAVE_MACH_TASK_EXCEPTION_PORTS
static exception_mask_t old_exception_masks[32];
static mach_port_t old_exception_ports[32];
static exception_behavior_t old_exception_behaviors[32];
static thread_state_flavor_t old_exception_flavors[32];
static mach_msg_type_number_t old_exception_count;

static void
disable_mach_bad_access_exc(void)
{
    old_exception_count = sizeof(old_exception_masks) / sizeof(old_exception_masks[0]);
    task_swap_exception_ports(
        mach_task_self(), EXC_MASK_BAD_ACCESS,
        MACH_PORT_NULL, EXCEPTION_DEFAULT, 0,
        old_exception_masks, &old_exception_count,
        old_exception_ports, old_exception_behaviors, old_exception_flavors
    );
}

static void
restore_mach_bad_access_exc(void)
{
    for (mach_msg_type_number_t i = 0; i < old_exception_count; i++) {
        task_set_exception_ports(
            mach_task_self(),
            old_exception_masks[i], old_exception_ports[i],
            old_exception_behaviors[i], old_exception_flavors[i]
        );
    }
}
#endif

static void
read_barrier_signal(int sig, siginfo_t *info, void *data)
{
    // setup SEGV/BUS handlers for errors
    struct sigaction prev_sigbus, prev_sigsegv;
    sigaction(SIGBUS, &old_sigbus_handler, &prev_sigbus);
    sigaction(SIGSEGV, &old_sigsegv_handler, &prev_sigsegv);

    // enable SIGBUS/SEGV
    sigset_t set, prev_set;
    sigemptyset(&set);
    sigaddset(&set, SIGBUS);
    sigaddset(&set, SIGSEGV);
    sigprocmask(SIG_UNBLOCK, &set, &prev_set);
#ifdef HAVE_MACH_TASK_EXCEPTION_PORTS
    disable_mach_bad_access_exc();
#endif
    // run handler
    read_barrier_handler((uintptr_t)info->si_addr);

    // reset SEGV/BUS handlers
#ifdef HAVE_MACH_TASK_EXCEPTION_PORTS
    restore_mach_bad_access_exc();
#endif
    sigaction(SIGBUS, &prev_sigbus, NULL);
    sigaction(SIGSEGV, &prev_sigsegv, NULL);
    sigprocmask(SIG_SETMASK, &prev_set, NULL);
}

static void
uninstall_handlers(void)
{
#ifdef HAVE_MACH_TASK_EXCEPTION_PORTS
    restore_mach_bad_access_exc();
#endif
    sigaction(SIGBUS, &old_sigbus_handler, NULL);
    sigaction(SIGSEGV, &old_sigsegv_handler, NULL);
}

static void
install_handlers(void)
{
    struct sigaction action;
    memset(&action, 0, sizeof(struct sigaction));
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = read_barrier_signal;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;

    sigaction(SIGBUS, &action, &old_sigbus_handler);
    sigaction(SIGSEGV, &action, &old_sigsegv_handler);
#ifdef HAVE_MACH_TASK_EXCEPTION_PORTS
    disable_mach_bad_access_exc();
#endif
}
#endif

static void
gc_compact_finish(rb_objspace_t *objspace)
{
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        gc_unprotect_pages(objspace, heap);
    }

    if (!rlgc_global.compacting) uninstall_handlers();

    if (rlgc_global.compacting) {
        /* compacting global GC ではここでこの objspace の heap 参照だけを更新する。
         * move か mark かの判定（RB_GC_MARK_OR_TRAVERSE）は rb_gc_get_objspace()（driver）の
         * during_reference_updating を読むため、rlgc_global_gc がパス全体で全 objspace に
         * その flag を立てる。VM グローバル側（gc_update_references_global）は冪等でないので、
         * rlgc_global_gc が全 objspace の heap 更新後に 1 度だけ実行する。 */
        gc_update_references_heap(objspace);
    }
    else {
        gc_update_references(objspace);
    }
    objspace->profile.compact_count++;

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        heap->compact_cursor = NULL;
        heap->free_pages = NULL;
        heap->compact_cursor_index = 0;
    }

    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->moved_objects = objspace->rcompactor.total_moved - record->moved_objects;
    }
    if (!rlgc_global.compacting) objspace->flags.during_compacting = FALSE;
}

struct gc_sweep_context {
    struct heap_page *page;
    int final_slots;
    int freed_slots;
    int empty_slots;
    /* slot ごとの pinned-free assert から巻き上げた述語。外部呼び出しで sweep ループには
     * 重すぎるため。 */
    unsigned char check_pinned_free;

    struct free_region *free_region;
};

static inline void
gc_sweep_register_free_slot(rb_objspace_t *objspace, struct heap_page *page, struct gc_sweep_context *ctx, uintptr_t p, short slot_size)
{
    rb_asan_unpoison_object(p, false);
    ((struct RBasic *)p)->flags = 0;

    /* free した slot が古い shareable/shref bit を次の生に持ち越さないようにする。実際の
     * クリアは slot ごとではなく gc_sweep_page 末尾で bitmap word ごとに一括で行う。 */

    struct free_region *existing_region = ctx->free_region;
    if (existing_region) rb_asan_unpoison_object((VALUE)existing_region, false);

    if (RB_LIKELY(existing_region && p == existing_region->end)) {
        existing_region->end = p + slot_size;
    }
    else {
        struct free_region *free_region = (struct free_region *)p;
        free_region->end = p + slot_size;
        free_region->next = existing_region;

        ctx->free_region = free_region;
    }

    if (existing_region) rb_asan_poison_object((VALUE)existing_region);
    rb_asan_poison_object(p);
}

static inline void
gc_sweep_plane(rb_objspace_t *objspace, rb_heap_t *heap, uintptr_t p, bits_t bitset, struct gc_sweep_context *ctx)
{
    struct heap_page *sweep_page = ctx->page;
    short slot_size = sweep_page->slot_size;

    do {
        VALUE vp = (VALUE)p;
        GC_ASSERT(vp % sizeof(VALUE) == 0);

        rb_asan_unpoison_object(vp, false);
        if (bitset & 1) {
            switch (BUILTIN_TYPE(vp)) {
              case T_MOVED:
                if (objspace->flags.during_compacting) {
                    /* The sweep cursor shouldn't have made it to any
                     * T_MOVED slots while the compact flag is enabled.
                     * The sweep cursor and compact cursor move in
                     * opposite directions, and when they meet references will
                     * get updated and "during_compacting" should get disabled */
                    rb_bug("T_MOVED shouldn't be seen until compaction is finished");
                }
                gc_report(3, objspace, "page_sweep: %s is freed\n", rb_obj_info(vp));
                ctx->empty_slots++;
                gc_sweep_register_free_slot(objspace, sweep_page, ctx, p, slot_size);
                break;
              case T_ZOMBIE:
                /* already counted */
                break;
              case T_NONE:
                ctx->empty_slots++; /* already freed */
                gc_sweep_register_free_slot(objspace, sweep_page, ctx, p, slot_size);
                break;

              default:
#if RGENGC_CHECK_MODE
                /* local GC は pin された slot を決して free してはならない（global GC は
                 * 可: unified mark は正確で、死んだ shareable こそ回収対象）。CHECK 限定で
                 * shareable/shref bit を読む。bulk clear が free ループ後なのでここではまだ
                 * 有効。release ビルドでは不変条件を信頼する。 */
                if (ctx->check_pinned_free &&
                    (MARKED_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(vp), vp) ||
                     MARKED_IN_BITMAP(GET_HEAP_SHREF_BITS(vp), vp))) {
                    rb_bug("page_sweep: freeing pinned slot %s (shareable=%d shref=%d single_now=%d)",
                           rb_obj_info(vp),
                           (int)!!MARKED_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(vp), vp),
                           (int)!!MARKED_IN_BITMAP(GET_HEAP_SHREF_BITS(vp), vp),
                           (int)rb_gc_single_objspace_p());
                }
#endif
#if RGENGC_CHECK_MODE
                if (!is_full_marking(objspace)) {
                    if (RVALUE_OLD_P(objspace, vp)) rb_bug("page_sweep: %p - old while minor GC.", (void *)p);
                    if (RVALUE_REMEMBERED(objspace, vp)) rb_bug("page_sweep: %p - remembered.", (void *)p);
                }
#endif

#if RGENGC_CHECK_MODE
#define CHECK(x) if (x(objspace, vp) != FALSE) rb_bug("obj_free: " #x "(%s) != FALSE", rb_obj_info(vp))
                CHECK(RVALUE_WB_UNPROTECTED);
                CHECK(RVALUE_MARKED);
                CHECK(RVALUE_MARKING);
                CHECK(RVALUE_UNCOLLECTIBLE);
#undef CHECK
#endif

                if (!rb_gc_obj_needs_cleanup_p(vp)) {
                    (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)p, slot_size);
                    gc_sweep_register_free_slot(objspace, sweep_page, ctx, p, slot_size);
                    gc_report(3, objspace, "page_sweep: %s (fast path) is freed\n", rb_obj_info(vp));
                    ctx->freed_slots++;
                }
                else {
                    gc_report(2, objspace, "page_sweep: free %p\n", (void *)p);

                    rb_gc_obj_free_vm_weak_references(vp);
                    if (rb_gc_obj_free(objspace, vp)) {
                        (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)p, slot_size);
                        gc_sweep_register_free_slot(objspace, sweep_page, ctx, p, slot_size);
                        gc_report(3, objspace, "page_sweep: %s is freed\n", rb_obj_info(vp));
                        ctx->freed_slots++;
                    }
                    else {
                        ctx->final_slots++;
                    }
                }
                break;
            }
        }
        p += slot_size;
        bitset >>= 1;
    } while (bitset);
}

static inline void
gc_sweep_page(rb_objspace_t *objspace, rb_heap_t *heap, struct gc_sweep_context *ctx)
{
    struct heap_page *sweep_page = ctx->page;
    GC_ASSERT(sweep_page->heap == heap);

    uintptr_t p;
    bits_t *bits, bitset;

    gc_report(2, objspace, "page_sweep: start.\n");

#if RGENGC_CHECK_MODE
    if (!objspace->flags.immediate_sweep) {
        GC_ASSERT(sweep_page->flags.before_sweep == TRUE);
    }
#endif
    sweep_page->flags.before_sweep = FALSE;
    sweep_page->free_slots = 0;

    asan_unlock_freelist(sweep_page);
    sweep_page->free_region = NULL;
    asan_lock_freelist(sweep_page);
    ctx->free_region = NULL;

    p = (uintptr_t)sweep_page->start;
    bits = sweep_page->mark_bits;
    short slot_size = sweep_page->slot_size;
    int total_slots = sweep_page->total_slots;
    int bitmap_plane_count = CEILDIV(total_slots, BITS_BITLENGTH);

    int out_of_range_bits = total_slots % BITS_BITLENGTH;
    if (out_of_range_bits != 0) {
        bits[bitmap_plane_count - 1] |= ~(((bits_t)1 << out_of_range_bits) - 1);
    }

    // Clear wb_unprotected and age bits for all unmarked slots
    {
        bits_t *wb_unprotected_bits = sweep_page->wb_unprotected_bits;
        bits_t *age_bits = sweep_page->age_bits;
        for (int i = 0; i < bitmap_plane_count; i++) {
            bits_t unmarked = ~bits[i];
            wb_unprotected_bits[i] &= ~unmarked;
            age_bits[i * 2] &= ~unmarked;
            age_bits[i * 2 + 1] &= ~unmarked;
        }
    }

    /* main の local GC は lock-free だが、VM グローバル weak table から参照される shareable の
     * free（rb_gc_obj_free_vm_weak_references: ci_table / fstring / symbol / cme）はその表を
     * 変更するので、ページの free ループを no-barrier VM lock で囲む。global GC 中は barrier が
     * その表を守るので不要。compacting な local GC は GC 全体の lock を持つので無害に nest する。
     * 非 main Ractor の local GC はそれらの shareable を free しないので取らない。 */
    const bool sweep_needs_vm_lock =
        objspace == rlgc_main_objspace && rb_multi_ractor_p() && !objspace->during_global_gc;
    unsigned int sweep_lock_lev = 0;
    if (sweep_needs_vm_lock) sweep_lock_lev = RB_GC_VM_LOCK_NO_BARRIER();

    for (int i = 0; i < bitmap_plane_count; i++) {
        bitset = ~bits[i];
        if (bitset) {
            gc_sweep_plane(objspace, heap, p, bitset, ctx);
        }
        p += BITS_BITLENGTH * slot_size;
    }

    if (sweep_needs_vm_lock) RB_GC_VM_UNLOCK_NO_BARRIER(sweep_lock_lev);

    /* free した slot の shareable/shref bit を一括クリアする。free（再利用）slot は古い bit を
     * 継いではならないが、生きた shareable は GC をまたいで pin を保つ必要がある。free slot は
     * ちょうど unmarked なので `bits &= mark_bits` で生きた shareable を残し free slot を消す。
     * freelist 公開前に走るので再利用 slot は常に clean。shareable/shref を持たないページは省略。 */
    if (sweep_page->has_shareable_objects || sweep_page->has_shref_objects) {
        bits_t *shareable_bits = sweep_page->shareable_bits;
        bits_t *shref_bits = sweep_page->shref_bits;
        for (int i = 0; i < bitmap_plane_count; i++) {
            shareable_bits[i] &= bits[i];
            shref_bits[i] &= bits[i];
        }
    }

    asan_unlock_freelist(sweep_page);
    sweep_page->free_region = ctx->free_region;
    asan_lock_freelist(sweep_page);

    if (!heap->compact_cursor) {
        gc_setup_mark_bits(sweep_page);
    }

#if GC_PROFILE_MORE_DETAIL
    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->removing_objects += ctx->final_slots + ctx->freed_slots;
        record->empty_objects += ctx->empty_slots;
    }
#endif
    if (0) fprintf(stderr, "gc_sweep_page(%"PRIdSIZE"): total_slots: %d, freed_slots: %d, empty_slots: %d, final_slots: %d\n",
                   rb_gc_count(),
                   sweep_page->total_slots,
                   ctx->freed_slots, ctx->empty_slots, ctx->final_slots);

    sweep_page->free_slots += ctx->freed_slots + ctx->empty_slots;
    sweep_page->heap->total_freed_objects += ctx->freed_slots;

    if (heap_pages_deferred_final && !finalizing) {
        gc_finalize_deferred_register(objspace);
    }

#if RGENGC_CHECK_MODE
    int region_slots = 0;
    asan_unlock_freelist(sweep_page);
    struct free_region *region = sweep_page->free_region;
    while (region) {
        rb_asan_unpoison_object((VALUE)region, false);
        GC_ASSERT(RB_TYPE_P((VALUE)region, T_NONE));
        uintptr_t region_start = (uintptr_t)region;
        uintptr_t region_end = region->end;
        struct free_region *next = region->next;
        rb_asan_poison_object((VALUE)region);

        GC_ASSERT(region_end > region_start);
        GC_ASSERT((region_end - region_start) % slot_size == 0);
        region_slots += (int)((region_end - region_start) / slot_size);

        region = next;
    }
    asan_lock_freelist(sweep_page);
    if (region_slots != sweep_page->free_slots) {
        rb_bug("inconsistent free region slots: expected %d but was %d", sweep_page->free_slots, region_slots);
    }
#endif

    gc_report(2, objspace, "page_sweep: end.\n");
}

static const char *
gc_mode_name(enum gc_mode mode)
{
    switch (mode) {
      case gc_mode_none: return "none";
      case gc_mode_marking: return "marking";
      case gc_mode_sweeping: return "sweeping";
      case gc_mode_compacting: return "compacting";
      default: rb_bug("gc_mode_name: unknown mode: %d", (int)mode);
    }
}

static void
gc_mode_transition(rb_objspace_t *objspace, enum gc_mode mode)
{
#if RGENGC_CHECK_MODE
    enum gc_mode prev_mode = gc_mode(objspace);
    switch (prev_mode) {
      case gc_mode_none:
        /* global GC は全 objspace を 1 つの heap として mark する（driver 上の mark_roots）
         * ので、個々の objspace の mode はその mark 中 `none` のまま。barrier 内の sweep が
         * その後 none -> sweeping と正当に遷移する。 */
        GC_ASSERT(mode == gc_mode_marking ||
                  (objspace->during_global_gc && mode == gc_mode_sweeping));
        break;
      case gc_mode_marking:  GC_ASSERT(mode == gc_mode_sweeping); break;
      case gc_mode_sweeping: GC_ASSERT(mode == gc_mode_none || mode == gc_mode_compacting); break;
      case gc_mode_compacting: GC_ASSERT(mode == gc_mode_none); break;
    }
#endif
    if (0) fprintf(stderr, "gc_mode_transition: %s->%s\n", gc_mode_name(gc_mode(objspace)), gc_mode_name(mode));
    gc_mode_set(objspace, mode);
}

static void
heap_page_flush_alloc_regions(struct heap_page *page, rb_heap_t *heap)
{
    struct free_region *chain = heap->alloc_next_region;

    if (heap->alloc_cursor < heap->alloc_cursor_end) {
        VALUE start = (VALUE)heap->alloc_cursor;
        rb_asan_unpoison_object(start, false);
        struct free_region *remnant = (struct free_region *)start;
        remnant->flags = 0;
        remnant->end = heap->alloc_cursor_end;
        remnant->next = chain;
        rb_asan_poison_object(start);
        chain = remnant;
    }

    if (chain) {
        asan_unlock_freelist(page);
        if (page->free_region) {
            struct free_region *p = page->free_region;
            rb_asan_unpoison_object((VALUE)p, false);
            while (p->next) {
                struct free_region *prev = p;
                p = p->next;
                rb_asan_poison_object((VALUE)prev);
                rb_asan_unpoison_object((VALUE)p, false);
            }
            p->next = chain;
            rb_asan_poison_object((VALUE)p);
        }
        else {
            page->free_region = chain;
        }
        asan_lock_freelist(page);
    }
}

static void
gc_sweep_start_heap(rb_objspace_t *objspace, rb_heap_t *heap)
{
    heap->sweeping_page = ccan_list_top(&heap->pages, struct heap_page, page_node);
    if (heap->sweeping_page) {
        objspace->sweeping_heap_count++;
    }
    heap->free_pages = NULL;
    heap->pooled_pages = NULL;
    if (!objspace->flags.immediate_sweep) {
        struct heap_page *page = NULL;

        ccan_list_for_each(&heap->pages, page, page_node) {
            page->flags.before_sweep = TRUE;
        }
    }
}

#if GC_CAN_COMPILE_COMPACTION
static void gc_sort_heap_by_compare_func(rb_objspace_t *objspace, gc_compact_compare_func compare_func);
static int compare_pinned_slots(const void *left, const void *right, void *d);
#endif

/* 現在の割り当てページ/freelist をページに返し、sweeper が一貫した heap を見るようにする。 */
static void
heap_alloc_state_clear(rb_objspace_t *objspace)
{
    objspace->incremental_mark_step_allocated_slots = 0;

    for (size_t heap_idx = 0; heap_idx < HEAP_COUNT; heap_idx++) {
        rb_heap_t *heap = &heaps[heap_idx];

        struct heap_page *page = heap->alloc_using_page;
        RUBY_DEBUG_LOG("heap alloc_using_page:%p cursor:%p", (void *)page, (void *)heap->alloc_cursor);

        if (page) {
            heap_page_flush_alloc_regions(page, heap);
        }

        heap->alloc_using_page = NULL;
        heap->alloc_cursor = 0;
        heap->alloc_cursor_end = 0;
        heap->alloc_next_region = NULL;
    }
}

static void
gc_sweep_freeobj_hooks_page(rb_objspace_t *objspace, struct heap_page *page)
{
    bits_t *bits = page->mark_bits;
    uintptr_t p = (uintptr_t)page->start;
    short slot_size = page->slot_size;
    int total_slots = page->total_slots;
    int bitmap_plane_count = CEILDIV(total_slots, BITS_BITLENGTH);

    int out_of_range_bits = total_slots % BITS_BITLENGTH;
    bits_t last_plane_mask = (out_of_range_bits != 0)
        ? ~(((bits_t)1 << out_of_range_bits) - 1)
        : 0;

    for (int j = 0; j < bitmap_plane_count; j++) {
        bits_t bitset = ~bits[j];
        if (j == bitmap_plane_count - 1) {
            bitset &= ~last_plane_mask;
        }

        uintptr_t pp = p;
        while (bitset) {
            if (bitset & 1) {
                VALUE vp = (VALUE)pp;
                asan_unpoisoning_object(vp) {
                    switch (BUILTIN_TYPE(vp)) {
                      case T_NONE:
                      case T_ZOMBIE:
                      case T_MOVED:
                        break;
                      default:
                        rb_gc_event_hook(vp, RUBY_INTERNAL_EVENT_FREEOBJ);
                        break;
                    }
                }
            }
            pp += slot_size;
            bitset >>= 1;
        }
        p += BITS_BITLENGTH * slot_size;
    }
}

static void
gc_sweep_freeobj_hooks(rb_objspace_t *objspace)
{
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        struct heap_page *page = NULL;

        ccan_list_for_each(&heap->pages, page, page_node) {
            gc_sweep_freeobj_hooks_page(objspace, page);
        }
    }
}

static int
gc_sweep_weak_table_i(VALUE val, void *data)
{
    rb_objspace_t *objspace = data;
    if (RB_SPECIAL_CONST_P(val)) return ST_CONTINUE;
    if (RVALUE_MARKED(objspace, val)) return ST_CONTINUE;
    return ST_DELETE;
}

static void
gc_sweep_start(rb_objspace_t *objspace)
{
    gc_mode_transition(objspace, gc_mode_sweeping);
    objspace->rincgc.pooled_slots = 0;

    if (RB_UNLIKELY(objspace->hook_events & RUBY_INTERNAL_EVENT_FREEOBJ)) {
        gc_sweep_freeobj_hooks(objspace);
    }

    for (int table = 0; table < RB_GC_VM_WEAK_TABLE_COUNT; table++) {
        if (!rb_gc_vm_weak_table_essential_p(table)) continue;
        rb_gc_vm_weak_table_foreach(
            gc_sweep_weak_table_i,
            NULL,
            objspace,
            true,
            table
        );
    }

#if GC_CAN_COMPILE_COMPACTION
    if (objspace->flags.during_compacting) {
        gc_sort_heap_by_compare_func(
            objspace,
            objspace->rcompactor.compare_func ? objspace->rcompactor.compare_func : compare_pinned_slots
        );
    }
#endif

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        gc_sweep_start_heap(objspace, heap);

        /* We should call gc_sweep_finish_heap for size pools with no pages. */
        if (heap->sweeping_page == NULL) {
            GC_ASSERT(heap->total_pages == 0);
            GC_ASSERT(heap->total_slots == 0);
            gc_sweep_finish_heap(objspace, heap);
        }
    }

    heap_alloc_state_clear(objspace);
}

static void
gc_sweep_finish_heap(rb_objspace_t *objspace, rb_heap_t *heap)
{
    size_t total_slots = heap->total_slots;
    size_t swept_slots = heap->freed_slots + heap->empty_slots;

    size_t init_slots = gc_params.heap_init_bytes / heap->slot_size;
    size_t min_free_slots = (size_t)(MAX(total_slots, init_slots) * gc_params.heap_free_slots_min_ratio);

    if (swept_slots < min_free_slots &&
            /* The heap is a growth heap if it freed more slots than had empty slots. */
            ((heap->empty_slots == 0 && total_slots > 0) || heap->freed_slots > heap->empty_slots)) {
        /* If we don't have enough slots and we have pages on the tomb heap, move
        * pages from the tomb heap to the eden heap. This may prevent page
        * creation thrashing (frequently allocating and deallocting pages) and
        * GC thrashing (running GC more frequently than required). */
        struct heap_page *resurrected_page;
        while (swept_slots < min_free_slots &&
                (resurrected_page = heap_page_resurrect(objspace))) {
            heap_add_page(objspace, heap, resurrected_page);
            heap_add_freepage(heap, resurrected_page);

            swept_slots += resurrected_page->free_slots;
        }

        if (swept_slots < min_free_slots) {
            /* Grow this heap if we are in a major GC or if we haven't run at least
             * RVALUE_OLD_AGE minor GC since the last major GC. */
            if (is_full_marking(objspace) ||
                    objspace->profile.count - objspace->rgengc.last_major_gc < RVALUE_OLD_AGE) {
                if (objspace->heap_pages.allocatable_bytes < min_free_slots * heap->slot_size) {
                    heap_allocatable_bytes_expand(objspace, heap, swept_slots, heap->total_slots, heap->slot_size);
                }
            }
            else if (swept_slots < min_free_slots * 7 / 8 &&
                     objspace->heap_pages.allocatable_bytes < (min_free_slots * 7 / 8 - swept_slots) * heap->slot_size) {
                gc_needs_major_flags |= GPR_FLAG_MAJOR_BY_NOFREE;
                heap->force_major_gc_count++;
            }
        }
    }
}

static void
gc_sweep_finish(rb_objspace_t *objspace)
{
    gc_report(1, objspace, "gc_sweep_finish\n");

    gc_prof_set_heap_info(objspace);
    heap_pages_free_unused_pages(objspace);

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];

        heap->freed_slots = 0;
        heap->empty_slots = 0;

        if (!will_be_incremental_marking(objspace)) {
            struct heap_page *end_page = heap->free_pages;
            if (end_page) {
                while (end_page->free_next) end_page = end_page->free_next;
                end_page->free_next = heap->pooled_pages;
            }
            else {
                heap->free_pages = heap->pooled_pages;
            }
            heap->pooled_pages = NULL;
            objspace->rincgc.pooled_slots = 0;
        }
    }

    gc_event_hook_objspace(objspace, RUBY_INTERNAL_EVENT_GC_END_SWEEP);
    gc_mode_transition(objspace, gc_mode_none);
}

static int
gc_sweep_step(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *sweep_page = heap->sweeping_page;
    int swept_slots = 0;
    int pooled_slots = 0;
    int sweep_budget = GC_INCREMENTAL_SWEEP_BYTES / heap->slot_size;
    int pool_budget = GC_INCREMENTAL_SWEEP_POOL_BYTES / heap->slot_size;

    if (sweep_page == NULL) return FALSE;

#if GC_ENABLE_LAZY_SWEEP
    gc_prof_sweep_timer_start(objspace);
#endif

    /* slot ごとの pinned-free assert 用（gc_sweep_context 参照）。このサイクルの mark が
     * pinned walk を実行したときだけ検査する。現在の world 状態で判定すると誤発火する。
     * single-world サイクルは死んだ shareable を正当に unmarked のまま残し、その sweep が
     * 途中で multi-objspace に切り替わりうるため。global GC の正確な mark は pin しないので
     * 自動的に対象外。 */
    const unsigned char check_pinned_free = objspace->rlgc.last_cycle_pinned;

    do {
        RUBY_DEBUG_LOG("sweep_page:%p", (void *)sweep_page);

        struct gc_sweep_context ctx = {
            .page = sweep_page,
            .final_slots = 0,
            .freed_slots = 0,
            .empty_slots = 0,
            .check_pinned_free = check_pinned_free,
        };
        gc_sweep_page(objspace, heap, &ctx);
        int free_slots = ctx.freed_slots + ctx.empty_slots;

        RUBY_DTRACE_GC_HOOK(SWEEP_PAGE, ctx.page->slot_size, ctx.final_slots, ctx.freed_slots, ctx.empty_slots);

        heap->sweeping_page = ccan_list_next(&heap->pages, sweep_page, page_node);

        if (free_slots == sweep_page->total_slots) {
            /* There are no living objects, so move this page to the global empty pages. */
            heap_unlink_page(objspace, heap, sweep_page);

            sweep_page->start = 0;
            sweep_page->total_slots = 0;
            sweep_page->slot_size = 0;
            sweep_page->heap = NULL;
            sweep_page->free_slots = 0;

            asan_unlock_freelist(sweep_page);
            sweep_page->free_region = NULL;
            asan_lock_freelist(sweep_page);

            asan_poison_memory_region(sweep_page->body, HEAP_PAGE_SIZE);

            objspace->empty_pages_count++;
            sweep_page->free_next = objspace->empty_pages;
            objspace->empty_pages = sweep_page;
        }
        else if (free_slots > 0) {
            heap->freed_slots += ctx.freed_slots;
            heap->empty_slots += ctx.empty_slots;

            if (pooled_slots < pool_budget) {
                heap_add_poolpage(objspace, heap, sweep_page);
                pooled_slots += free_slots;
            }
            else {
                heap_add_freepage(heap, sweep_page);
                swept_slots += free_slots;
                if (swept_slots > sweep_budget) {
                    break;
                }
            }
        }
        else {
            sweep_page->free_next = NULL;
        }
    } while ((sweep_page = heap->sweeping_page));

    if (!heap->sweeping_page) {
        objspace->sweeping_heap_count--;
        GC_ASSERT(objspace->sweeping_heap_count >= 0);
        gc_sweep_finish_heap(objspace, heap);

        if (!has_sweeping_pages(objspace)) {
            gc_sweep_finish(objspace);
        }
    }

#if GC_ENABLE_LAZY_SWEEP
    gc_prof_sweep_timer_stop(objspace);
#endif

    return heap->free_pages != NULL;
}

static void
gc_sweep_rest(rb_objspace_t *objspace)
{
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];

        while (heap->sweeping_page) {
            gc_sweep_step(objspace, heap);
        }
    }
}

static void
gc_sweep_continue(rb_objspace_t *objspace, rb_heap_t *sweep_heap)
{
    GC_ASSERT(dont_gc_val() == FALSE || objspace->profile.latest_gc_info & GPR_FLAG_METHOD);
    if (!GC_ENABLE_LAZY_SWEEP) return;

    gc_sweeping_enter(objspace);

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        if (gc_sweep_step(objspace, heap)) {
            GC_ASSERT(heap->free_pages != NULL);
        }
        else if (heap == sweep_heap) {
            if (objspace->empty_pages_count > 0 || objspace->heap_pages.allocatable_bytes > 0) {
                /* [Bug #21548]
                 *
                 * If this heap is the heap we want to sweep, but we weren't able
                 * to free any slots, but we also either have empty pages or could
                 * allocate new pages, then we want to preemptively claim a page
                 * because it's possible that sweeping another heap will call
                 * gc_sweep_finish_heap, which may use up all of the
                 * empty/allocatable pages. If other heaps are not finished sweeping
                 * then we do not finish this GC and we will end up triggering a new
                 * GC cycle during this GC phase. */
                heap_page_allocate_and_initialize(objspace, heap);

                GC_ASSERT(heap->free_pages != NULL);
            }
            else {
                /* Not allowed to create a new page so finish sweeping. */
                gc_sweep_rest(objspace);
                GC_ASSERT(gc_mode(objspace) == gc_mode_none);
                break;
            }
        }
    }

    gc_sweeping_exit(objspace);
}

static void
gc_sweep_step_for_malloc(rb_objspace_t *objspace)
{
    GC_ASSERT(is_lazy_sweeping(objspace));

    unsigned int lock_lev;
    gc_enter(objspace, gc_enter_event_continue, &lock_lev);

    gc_sweeping_enter(objspace);

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        gc_sweep_step(objspace, heap);
    }

    gc_sweeping_exit(objspace);

    gc_exit(objspace, gc_enter_event_continue, &lock_lev);
}

static bool rlgc_global_pointer_to_heap_p(const void *ptr);

VALUE
rb_gc_impl_location(void *objspace_ptr, VALUE value)
{
    rb_objspace_t *objspace = objspace_ptr;
    VALUE destination;

    /* 別 objspace の heap への参照は local(single-objspace) compaction では移動しない
     * （所有 objspace だけが動かす）ので、そのような foreign 参照はそのまま残す。ただし
     * compacting global GC は barrier 下で全 objspace を動かすので cross-objspace 参照も動く。
     * その場合は全 objspace の heap を調べて forwarding を辿る。 */
    if (RB_UNLIKELY(objspace->during_global_gc)
            ? !rlgc_global_pointer_to_heap_p((void *)value)
            : !is_pointer_to_heap(objspace_ptr, (void *)value)) {
        return value;
    }

    asan_unpoisoning_object(value) {
        if (BUILTIN_TYPE(value) == T_MOVED) {
            destination = (VALUE)RMOVED(value)->destination;
            GC_ASSERT(BUILTIN_TYPE(destination) != T_NONE);
        }
        else {
            destination = value;
        }
    }

    return destination;
}

#if GC_CAN_COMPILE_COMPACTION
static void
invalidate_moved_plane(rb_objspace_t *objspace, struct heap_page *page, uintptr_t p, bits_t bitset)
{
    if (bitset) {
        do {
            if (bitset & 1) {
                VALUE forwarding_object = (VALUE)p;
                VALUE object;

                if (BUILTIN_TYPE(forwarding_object) == T_MOVED) {
                    GC_ASSERT(RVALUE_PINNED(objspace, forwarding_object));
                    GC_ASSERT(!RVALUE_MARKED(objspace, forwarding_object));

                    CLEAR_IN_BITMAP(GET_HEAP_PINNED_BITS(forwarding_object), forwarding_object);

                    object = rb_gc_impl_location(objspace, forwarding_object);
                    gc_move(objspace, object, forwarding_object, GET_HEAP_PAGE(object), page);
                    /* forwarding_object is now our actual object, and "object"
                     * is the free slot for the original page */

                    struct heap_page *orig_page = GET_HEAP_PAGE(object);
                    orig_page->free_slots++;
                    RVALUE_AGE_SET_BITMAP(object, 0);
                    heap_page_add_free_region(objspace, orig_page, object);

                    GC_ASSERT(RVALUE_MARKED(objspace, forwarding_object));
                    GC_ASSERT(BUILTIN_TYPE(forwarding_object) != T_MOVED);
                    GC_ASSERT(BUILTIN_TYPE(forwarding_object) != T_NONE);
                }
            }
            p += page->slot_size;
            bitset >>= 1;
        } while (bitset);
    }
}

static void
invalidate_moved_page(rb_objspace_t *objspace, struct heap_page *page)
{
    int i;
    bits_t *mark_bits, *pin_bits;
    bits_t bitset;
    short slot_size = page->slot_size;
    int total_slots = page->total_slots;
    int bitmap_plane_count = CEILDIV(total_slots, BITS_BITLENGTH);

    mark_bits = page->mark_bits;
    pin_bits = page->pinned_bits;

    uintptr_t p = page->start;

    for (i=0; i < bitmap_plane_count; i++) {
        /* Moved objects are pinned but never marked. We reuse the pin bits
         * to indicate there is a moved object in this slot. */
        bitset = pin_bits[i] & ~mark_bits[i];
        invalidate_moved_plane(objspace, page, p, bitset);
        p += BITS_BITLENGTH * slot_size;
    }
}
#endif

static void
gc_compact_start(rb_objspace_t *objspace)
{
    struct heap_page *page = NULL;
    gc_mode_transition(objspace, gc_mode_compacting);

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        ccan_list_for_each(&heap->pages, page, page_node) {
            page->flags.before_sweep = TRUE;
        }

        heap->compact_cursor = ccan_list_tail(&heap->pages, struct heap_page, page_node);
        heap->compact_cursor_index = 0;
    }

    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->moved_objects = objspace->rcompactor.total_moved;
    }

    memset(objspace->rcompactor.considered_count_table, 0, T_MASK * sizeof(size_t));
    memset(objspace->rcompactor.moved_count_table, 0, T_MASK * sizeof(size_t));
    memset(objspace->rcompactor.moved_up_count_table, 0, T_MASK * sizeof(size_t));
    memset(objspace->rcompactor.moved_down_count_table, 0, T_MASK * sizeof(size_t));

    /* Set up read barrier for pages containing MOVED objects */
    /* compacting global GC は read barrier を全 objspace 分まとめて 1 度だけ設置する。 */
    if (!rlgc_global.compacting) install_handlers();
}

static void gc_sweep_compact(rb_objspace_t *objspace);

static void
gc_sweep(rb_objspace_t *objspace)
{
    gc_sweeping_enter(objspace);

    const unsigned int immediate_sweep = objspace->flags.immediate_sweep;

    gc_report(1, objspace, "gc_sweep: immediate: %d\n", immediate_sweep);

    gc_sweep_start(objspace);
    if (objspace->flags.during_compacting) {
        rb_hrtime_t compact_start_time = gc_prof_enabled(objspace) ? rb_hrtime_now() : 0;
        gc_sweep_compact(objspace);
        if (gc_prof_enabled(objspace)) {
            rb_hrtime_t compact_wall_time = elapsed_hrtime_from(compact_start_time);
            gc_profile_record *record = gc_prof_record(objspace);
            record->gc_compact_wall_time = rb_hrtime_add(record->gc_compact_wall_time,
                    compact_wall_time);
            objspace->profile.gc_sweep_excluded_wall_time = rb_hrtime_add(
                    objspace->profile.gc_sweep_excluded_wall_time,
                    compact_wall_time);
        }
    }

    if (immediate_sweep) {
#if !GC_ENABLE_LAZY_SWEEP
        gc_prof_sweep_timer_start(objspace);
#endif
        gc_sweep_rest(objspace);
#if !GC_ENABLE_LAZY_SWEEP
        gc_prof_sweep_timer_stop(objspace);
#endif
    }
    else {

        /* Sweep every size pool. */
        for (int i = 0; i < HEAP_COUNT; i++) {
            rb_heap_t *heap = &heaps[i];
            gc_sweep_step(objspace, heap);
        }
    }

    gc_sweeping_exit(objspace);
}

/* Marking - Marking stack */

static stack_chunk_t *
stack_chunk_alloc(void)
{
    stack_chunk_t *res;

    res = malloc(sizeof(stack_chunk_t));
    if (!res)
        rb_memerror();

    return res;
}

static inline int
is_mark_stack_empty(mark_stack_t *stack)
{
    return stack->chunk == NULL;
}

static size_t
mark_stack_size(mark_stack_t *stack)
{
    size_t size = stack->index;
    stack_chunk_t *chunk = stack->chunk ? stack->chunk->next : NULL;

    while (chunk) {
        size += stack->limit;
        chunk = chunk->next;
    }
    return size;
}

static void
add_stack_chunk_cache(mark_stack_t *stack, stack_chunk_t *chunk)
{
    chunk->next = stack->cache;
    stack->cache = chunk;
    stack->cache_size++;
}

static void
shrink_stack_chunk_cache(mark_stack_t *stack)
{
    stack_chunk_t *chunk;

    if (stack->unused_cache_size > (stack->cache_size/2)) {
        chunk = stack->cache;
        stack->cache = stack->cache->next;
        stack->cache_size--;
        free(chunk);
    }
    stack->unused_cache_size = stack->cache_size;
}

static void
push_mark_stack_chunk(mark_stack_t *stack)
{
    stack_chunk_t *next;

    GC_ASSERT(stack->index == stack->limit);

    if (stack->cache_size > 0) {
        next = stack->cache;
        stack->cache = stack->cache->next;
        stack->cache_size--;
        if (stack->unused_cache_size > stack->cache_size)
            stack->unused_cache_size = stack->cache_size;
    }
    else {
        next = stack_chunk_alloc();
    }
    next->next = stack->chunk;
    stack->chunk = next;
    stack->index = 0;
}

static void
pop_mark_stack_chunk(mark_stack_t *stack)
{
    stack_chunk_t *prev;

    prev = stack->chunk->next;
    GC_ASSERT(stack->index == 0);
    add_stack_chunk_cache(stack, stack->chunk);
    stack->chunk = prev;
    stack->index = stack->limit;
}

static void
mark_stack_chunk_list_free(stack_chunk_t *chunk)
{
    stack_chunk_t *next = NULL;

    while (chunk != NULL) {
        next = chunk->next;
        free(chunk);
        chunk = next;
    }
}

static void
free_stack_chunks(mark_stack_t *stack)
{
    mark_stack_chunk_list_free(stack->chunk);
}

static void
mark_stack_free_cache(mark_stack_t *stack)
{
    mark_stack_chunk_list_free(stack->cache);
    stack->cache_size = 0;
    stack->unused_cache_size = 0;
}

static void
push_mark_stack(mark_stack_t *stack, VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
      case T_FLOAT:
      case T_STRING:
      case T_REGEXP:
      case T_ARRAY:
      case T_HASH:
      case T_STRUCT:
      case T_BIGNUM:
      case T_FILE:
      case T_DATA:
      case T_MATCH:
      case T_COMPLEX:
      case T_RATIONAL:
      case T_TRUE:
      case T_FALSE:
      case T_SYMBOL:
      case T_IMEMO:
      case T_ICLASS:
        if (stack->index == stack->limit) {
            push_mark_stack_chunk(stack);
        }
        stack->chunk->data[stack->index++] = obj;
        return;

      case T_NONE:
      case T_NIL:
      case T_FIXNUM:
      case T_MOVED:
      case T_ZOMBIE:
      case T_UNDEF:
      case T_MASK:
        rb_bug("push_mark_stack() called for broken object");
        break;

      case T_NODE:
        rb_bug("push_mark_stack: unexpected T_NODE object");
        break;
    }

    rb_bug("rb_gc_mark(): unknown data type 0x%x(%p) %s",
            BUILTIN_TYPE(obj), (void *)obj,
            is_pointer_to_heap((rb_objspace_t *)rb_gc_get_objspace(), (void *)obj) ? "corrupted object" : "non object");
}

static int
pop_mark_stack(mark_stack_t *stack, VALUE *data)
{
    if (is_mark_stack_empty(stack)) {
        return FALSE;
    }
    if (stack->index == 1) {
        *data = stack->chunk->data[--stack->index];
        pop_mark_stack_chunk(stack);
    }
    else {
        *data = stack->chunk->data[--stack->index];
    }
    return TRUE;
}

static void
init_mark_stack(mark_stack_t *stack)
{
    int i;

    MEMZERO(stack, mark_stack_t, 1);
    stack->index = stack->limit = STACK_CHUNK_SIZE;

    for (i=0; i < 4; i++) {
        add_stack_chunk_cache(stack, stack_chunk_alloc());
    }
    stack->unused_cache_size = stack->cache_size;
}

/* Marking */

static void
rgengc_check_relation(rb_objspace_t *objspace, VALUE obj)
{
    if (objspace->rgengc.parent_object_old_p) {
        if (RVALUE_WB_UNPROTECTED(objspace, obj) || !RVALUE_OLD_P(objspace, obj)) {
            rgengc_remember(objspace, objspace->rgengc.parent_object);
        }
    }
}

static inline int
gc_mark_set(rb_objspace_t *objspace, VALUE obj)
{
    if (RVALUE_MARKED(objspace, obj)) return 0;
    MARK_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj);
    return 1;
}

static void
gc_aging(rb_objspace_t *objspace, VALUE obj)
{
    /* Disable aging if Major GC's are disabled. This will prevent longish lived
     * objects filling up the heap at the expense of marking many more objects.
     *
     * We should always pre-warm our process when disabling majors, by running
     * GC manually several times so that most objects likely to become oldgen
     * are already oldgen.
     */
    if(!gc_config_full_mark_val)
        return;

    struct heap_page *page = GET_HEAP_PAGE(obj);

    GC_ASSERT(RVALUE_MARKING(objspace, obj) == FALSE);
    check_rvalue_consistency(objspace, obj);

    if (!RVALUE_PAGE_WB_UNPROTECTED(page, obj)) {
        if (!RVALUE_OLD_P(objspace, obj)) {
            int t = BUILTIN_TYPE(obj);
            if (t == T_CLASS || t == T_MODULE || t == T_ICLASS) {
                gc_report(3, objspace, "gc_aging: YOUNG class: %s\n", rb_obj_info(obj));
                RVALUE_AGE_SET(obj, RVALUE_OLD_AGE);
                RVALUE_OLD_UNCOLLECTIBLE_SET(objspace, obj);
            }
            else {
                gc_report(3, objspace, "gc_aging: YOUNG: %s\n", rb_obj_info(obj));
                RVALUE_AGE_INC(objspace, obj);
            }
        }
        else if (is_full_marking(objspace)) {
            GC_ASSERT(RVALUE_PAGE_UNCOLLECTIBLE(page, obj) == FALSE);
            RVALUE_PAGE_OLD_UNCOLLECTIBLE_SET(objspace, page, obj);
        }
    }
    check_rvalue_consistency(objspace, obj);

    objspace->marked_slots++;
}

static void
gc_grey(rb_objspace_t *objspace, VALUE obj)
{
#if RGENGC_CHECK_MODE
    if (RVALUE_MARKED(objspace, obj) == FALSE) rb_bug("gc_grey: %s is not marked.", rb_obj_info(obj));
    if (RVALUE_MARKING(objspace, obj) == TRUE) rb_bug("gc_grey: %s is marking/remembered.", rb_obj_info(obj));
#endif

    if (is_incremental_marking(objspace)) {
        MARK_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj);
    }

    if (RB_FL_TEST_RAW(obj, RUBY_FL_WEAK_REFERENCE)) {
        rb_darray_append_without_gc(&objspace->weak_references, obj);
    }

    push_mark_stack(&objspace->mark_stack, obj);
}

static inline void
gc_mark_check_t_none(rb_objspace_t *objspace, VALUE obj)
{
    if (RB_UNLIKELY(BUILTIN_TYPE(obj) == T_NONE)) {
        enum {info_size = 256};
        char obj_info_buf[info_size];
        rb_raw_obj_info(obj_info_buf, info_size, obj);

        char parent_obj_info_buf[info_size];
        rb_raw_obj_info(parent_obj_info_buf, info_size, objspace->rgengc.parent_object);

        rb_bug("try to mark T_NONE object (obj: %s, parent: %s)", obj_info_buf, parent_obj_info_buf);
    }
}

static void
gc_mark(rb_objspace_t *objspace, VALUE obj)
{
    GC_ASSERT(during_gc);
    GC_ASSERT(!objspace->flags.during_reference_updating);

    /* 別 objspace には決して踏み込まない。foreign なオブジェクトはここでは生きた葉で、
     * その生死は所有者（または global GC）の担当。この GC からその bitmap を触るのは不健全。
     * global GC ではこの制限を外す。全員停止しており、bit はオブジェクト自身のページにある
     * ので cross-objspace の書き込みも正しい場所に着く。 */
    if (RB_UNLIKELY(GET_HEAP_OBJSPACE(obj) != objspace) && !objspace->during_global_gc) {
        return;
    }

    if (RB_UNLIKELY(objspace->during_global_gc)) {
        /* shareable -> unshareable のエッジすべてで shref を再計算する（同一/cross-objspace
         * とも）。clear パスが全 shref bit を消し、以降は write barrier が維持する。 */
        VALUE parent = objspace->rgengc.parent_object;
        if (!UNDEF_P(parent) && parent != Qfalse &&
            RB_FL_TEST_RAW(parent, RUBY_FL_SHAREABLE) &&
            !RB_FL_TEST_RAW(obj, RUBY_FL_SHAREABLE)) {
            struct heap_page *page = GET_HEAP_PAGE(obj);
            _MARK_IN_BITMAP(page->shref_bits, page, obj);
            page->has_shref_objects = TRUE;
        }
    }

    rgengc_check_relation(objspace, obj);
    if (!gc_mark_set(objspace, obj)) return; /* already marked */

    if (0) { // for debug GC marking miss
        RUBY_DEBUG_LOG("%p (%s) parent:%p (%s)",
                        (void *)obj, obj_type_name(obj),
                        (void *)objspace->rgengc.parent_object, obj_type_name(objspace->rgengc.parent_object));
    }

    gc_mark_check_t_none(objspace, obj);

    gc_aging(objspace, obj);
    gc_grey(objspace, obj);
}

static inline void
gc_pin(rb_objspace_t *objspace, VALUE obj)
{
    GC_ASSERT(!SPECIAL_CONST_P(obj));

    /* foreign なページの pinned bit は決して書かない（global GC は可: 全員停止中）。 */
    if (RB_UNLIKELY(GET_HEAP_OBJSPACE(obj) != objspace) && !objspace->during_global_gc) return;

    if (RB_UNLIKELY(objspace->flags.during_compacting)) {
        if (RB_LIKELY(during_gc)) {
            if (!RVALUE_PINNED(objspace, obj)) {
                GC_ASSERT(GET_HEAP_PAGE(obj)->pinned_slots <= GET_HEAP_PAGE(obj)->total_slots);
                GET_HEAP_PAGE(obj)->pinned_slots++;
                MARK_IN_BITMAP(GET_HEAP_PINNED_BITS(obj), obj);
            }
        }
    }
}

static inline void
gc_mark_and_pin(rb_objspace_t *objspace, VALUE obj)
{
    gc_pin(objspace, obj);
    gc_mark(objspace, obj);
}

void
rb_gc_impl_mark_and_move(void *objspace_ptr, VALUE *ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (RB_UNLIKELY(objspace->flags.during_reference_updating)) {
        GC_ASSERT(objspace->flags.during_compacting);
        GC_ASSERT(during_gc);

        VALUE destination = rb_gc_impl_location(objspace, *ptr);
        if (destination != *ptr) {
            *ptr = destination;
        }
    }
    else {
        gc_mark(objspace, *ptr);
    }
}

void
rb_gc_impl_mark(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    gc_mark(objspace, obj);
}

void
rb_gc_impl_mark_and_pin(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    gc_mark_and_pin(objspace, obj);
}

/* global GC が保守的に走査するワードはどの objspace を指すか分からないので、driver が持つ
 * 全 objspace のスナップショットに対して所属を判定する（bit は gc_mark/gc_pin 経由で
 * 所有者のページに着く）。 */
static bool
rlgc_global_pointer_to_heap_p(const void *ptr)
{
    for (size_t i = 0; i < rlgc_global.count; i++) {
        if (is_pointer_to_heap(rlgc_global.list[i], ptr)) return true;
    }
    return false;
}

void
rb_gc_impl_mark_maybe(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    (void)VALGRIND_MAKE_MEM_DEFINED(&obj, sizeof(obj));

    if (RB_UNLIKELY(objspace->during_global_gc)
            ? rlgc_global_pointer_to_heap_p((void *)obj)
            : is_pointer_to_heap(objspace, (void *)obj)) {
        asan_unpoisoning_object(obj) {
            /* Garbage can live on the stack, so do not mark or pin */
            switch (BUILTIN_TYPE(obj)) {
              case T_ZOMBIE:
              case T_NONE:
                break;
              default:
                gc_mark_and_pin(objspace, obj);
                break;
            }
        }
    }
}

static int
pin_value(st_data_t key, st_data_t value, st_data_t data)
{
    rb_gc_impl_mark_and_pin((void *)data, (VALUE)value);

    return ST_CONTINUE;
}

static inline void
gc_mark_set_parent_raw(rb_objspace_t *objspace, VALUE obj, bool old_p)
{
    asan_unpoison_memory_region(&objspace->rgengc.parent_object, sizeof(objspace->rgengc.parent_object), false);
    asan_unpoison_memory_region(&objspace->rgengc.parent_object_old_p, sizeof(objspace->rgengc.parent_object_old_p), false);
    objspace->rgengc.parent_object = obj;
    objspace->rgengc.parent_object_old_p = old_p;
}

static inline void
gc_mark_set_parent(rb_objspace_t *objspace, VALUE obj)
{
    gc_mark_set_parent_raw(objspace, obj, RVALUE_OLD_P(objspace, obj));
}

static inline void
gc_mark_set_parent_invalid(rb_objspace_t *objspace)
{
    asan_poison_memory_region(&objspace->rgengc.parent_object, sizeof(objspace->rgengc.parent_object));
    asan_poison_memory_region(&objspace->rgengc.parent_object_old_p, sizeof(objspace->rgengc.parent_object_old_p));
}

static void rlgc_pinned_roots_mark(rb_objspace_t *objspace, rb_heap_t *heap);

static void
mark_roots(rb_objspace_t *objspace, const char **categoryp)
{
#define MARK_CHECKPOINT(category) do { \
    if (categoryp) *categoryp = category; \
} while (0)

    /* shareable/shref の pin はここではなく mark の最後（gc_marks_finish）で走る。全走査後
     * なら通常 mark が届かなかったものだけを触れるので安価で、かつそれが retention 指標に
     * なる。 */

    MARK_CHECKPOINT("objspace");
    gc_mark_set_parent_raw(objspace, Qundef, false);

    if (objspace->during_global_gc) {
        /* 全 objspace の finalizer 表（zombie も含む）を pin する。
         * （finalizer_table はローカルの "objspace" に対するマクロ。） */
        rb_objspace_t *const driver = objspace;
        for (size_t i = 0; i < rlgc_global.count; i++) {
            rb_objspace_t *objspace = rlgc_global.list[i];
            if (finalizer_table != NULL) {
                st_foreach(finalizer_table, pin_value, (st_data_t)driver);
            }
        }
    }
    else if (finalizer_table != NULL) {
        st_foreach(finalizer_table, pin_value, (st_data_t)objspace);
    }

    if (stress_to_class) rb_gc_mark(stress_to_class);

    rb_gc_save_machine_context();
    rb_gc_mark_roots(objspace, categoryp);
    gc_mark_set_parent_invalid(objspace);
}

static void
gc_mark_children(rb_objspace_t *objspace, VALUE obj)
{
    gc_mark_set_parent(objspace, obj);
    rb_gc_mark_children(objspace, obj);
    gc_mark_set_parent_invalid(objspace);
}

/**
 * incremental: 0 -> not incremental (do all)
 * incremental: n -> mark at most `n' objects
 */
static inline int
gc_mark_stacked_objects(rb_objspace_t *objspace, int incremental, size_t count)
{
    mark_stack_t *mstack = &objspace->mark_stack;
    VALUE obj;
    size_t marked_slots_at_the_beginning = objspace->marked_slots;
    size_t popped_count = 0;

    while (pop_mark_stack(mstack, &obj)) {
        if (obj == Qundef) continue; /* skip */

        if (RGENGC_CHECK_MODE && !RVALUE_MARKED(objspace, obj)) {
            rb_bug("gc_mark_stacked_objects: %s is not marked.", rb_obj_info(obj));
        }
        gc_mark_children(objspace, obj);

        popped_count++;

        if (incremental) {
            if (RGENGC_CHECK_MODE && !RVALUE_MARKING(objspace, obj)) {
                rb_bug("gc_mark_stacked_objects: incremental, but marking bit is 0");
            }
            CLEAR_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj);

            if (popped_count + (objspace->marked_slots - marked_slots_at_the_beginning) > count) {
                break;
            }
        }
        else {
            /* just ignore marking bits */
        }
    }

    RUBY_DTRACE_GC_HOOK(MARK_STACKED_OBJECTS, popped_count);

    if (RGENGC_CHECK_MODE >= 3) gc_verify_internal_consistency(objspace);

    if (is_mark_stack_empty(mstack)) {
        shrink_stack_chunk_cache(mstack);
        return TRUE;
    }
    else {
        return FALSE;
    }
}

static int
gc_mark_stacked_objects_incremental(rb_objspace_t *objspace, size_t count)
{
    return gc_mark_stacked_objects(objspace, TRUE, count);
}

static int
gc_mark_stacked_objects_all(rb_objspace_t *objspace)
{
    return gc_mark_stacked_objects(objspace, FALSE, 0);
}

#if RGENGC_CHECK_MODE >= 4

#define MAKE_ROOTSIG(obj) (((VALUE)(obj) << 1) | 0x01)
#define IS_ROOTSIG(obj)   ((VALUE)(obj) & 0x01)
#define GET_ROOTSIG(obj)  ((const char *)((VALUE)(obj) >> 1))

struct reflist {
    VALUE *list;
    int pos;
    int size;
};

static struct reflist *
reflist_create(VALUE obj)
{
    struct reflist *refs = xmalloc(sizeof(struct reflist));
    refs->size = 1;
    refs->list = ALLOC_N(VALUE, refs->size);
    refs->list[0] = obj;
    refs->pos = 1;
    return refs;
}

static void
reflist_destruct(struct reflist *refs)
{
    xfree(refs->list);
    xfree(refs);
}

static void
reflist_add(struct reflist *refs, VALUE obj)
{
    if (refs->pos == refs->size) {
        refs->size *= 2;
        SIZED_REALLOC_N(refs->list, VALUE, refs->size, refs->size/2);
    }

    refs->list[refs->pos++] = obj;
}

static void
reflist_dump(struct reflist *refs)
{
    int i;
    for (i=0; i<refs->pos; i++) {
        VALUE obj = refs->list[i];
        if (IS_ROOTSIG(obj)) { /* root */
            fprintf(stderr, "<root@%s>", GET_ROOTSIG(obj));
        }
        else {
            fprintf(stderr, "<%s>", rb_obj_info(obj));
        }
        if (i+1 < refs->pos) fprintf(stderr, ", ");
    }
}

static int
reflist_referred_from_machine_context(struct reflist *refs)
{
    int i;
    for (i=0; i<refs->pos; i++) {
        VALUE obj = refs->list[i];
        if (IS_ROOTSIG(obj) && strcmp(GET_ROOTSIG(obj), "machine_context") == 0) return 1;
    }
    return 0;
}

struct allrefs {
    rb_objspace_t *objspace;
    /* a -> obj1
     * b -> obj1
     * c -> obj1
     * c -> obj2
     * d -> obj3
     * #=> {obj1 => [a, b, c], obj2 => [c, d]}
     */
    struct st_table *references;
    const char *category;
    VALUE root_obj;
    mark_stack_t mark_stack;
};

static int
allrefs_add(struct allrefs *data, VALUE obj)
{
    struct reflist *refs;
    st_data_t r;

    if (st_lookup(data->references, obj, &r)) {
        refs = (struct reflist *)r;
        reflist_add(refs, data->root_obj);
        return 0;
    }
    else {
        refs = reflist_create(data->root_obj);
        st_insert(data->references, obj, (st_data_t)refs);
        return 1;
    }
}

static void
allrefs_i(VALUE obj, void *ptr)
{
    struct allrefs *data = (struct allrefs *)ptr;

    if (allrefs_add(data, obj)) {
        push_mark_stack(&data->mark_stack, obj);
    }
}

static void
allrefs_roots_i(VALUE obj, void *ptr)
{
    struct allrefs *data = (struct allrefs *)ptr;
    if (strlen(data->category) == 0) rb_bug("!!!");
    data->root_obj = MAKE_ROOTSIG(data->category);

    if (allrefs_add(data, obj)) {
        push_mark_stack(&data->mark_stack, obj);
    }
}
#define PUSH_MARK_FUNC_DATA(v) do { \
    struct gc_mark_func_data_struct *prev_mark_func_data = GET_VM()->gc.mark_func_data; \
    GET_VM()->gc.mark_func_data = (v);

#define POP_MARK_FUNC_DATA() GET_VM()->gc.mark_func_data = prev_mark_func_data;} while (0)

static st_table *
objspace_allrefs(rb_objspace_t *objspace)
{
    struct allrefs data;
    struct gc_mark_func_data_struct mfd;
    VALUE obj;
    int prev_dont_gc = dont_gc_val();
    dont_gc_on();

    data.objspace = objspace;
    data.references = st_init_numtable();
    init_mark_stack(&data.mark_stack);

    mfd.mark_func = allrefs_roots_i;
    mfd.data = &data;

    /* traverse root objects */
    PUSH_MARK_FUNC_DATA(&mfd);
    GET_VM()->gc.mark_func_data = &mfd;
    mark_roots(objspace, &data.category);
    POP_MARK_FUNC_DATA();

    /* traverse rest objects reachable from root objects */
    while (pop_mark_stack(&data.mark_stack, &obj)) {
        rb_objspace_reachable_objects_from(data.root_obj = obj, allrefs_i, &data);
    }
    free_stack_chunks(&data.mark_stack);

    dont_gc_set(prev_dont_gc);
    return data.references;
}

static int
objspace_allrefs_destruct_i(st_data_t key, st_data_t value, st_data_t ptr)
{
    struct reflist *refs = (struct reflist *)value;
    reflist_destruct(refs);
    return ST_CONTINUE;
}

static void
objspace_allrefs_destruct(struct st_table *refs)
{
    st_foreach(refs, objspace_allrefs_destruct_i, 0);
    st_free_table(refs);
}

#if RGENGC_CHECK_MODE >= 5
static int
allrefs_dump_i(st_data_t k, st_data_t v, st_data_t ptr)
{
    VALUE obj = (VALUE)k;
    struct reflist *refs = (struct reflist *)v;
    fprintf(stderr, "[allrefs_dump_i] %s <- ", rb_obj_info(obj));
    reflist_dump(refs);
    fprintf(stderr, "\n");
    return ST_CONTINUE;
}

static void
allrefs_dump(rb_objspace_t *objspace)
{
    VALUE size = objspace->rgengc.allrefs_table->num_entries;
    fprintf(stderr, "[all refs] (size: %"PRIuVALUE")\n", size);
    st_foreach(objspace->rgengc.allrefs_table, allrefs_dump_i, 0);
}
#endif

static int
gc_check_after_marks_i(st_data_t k, st_data_t v, st_data_t ptr)
{
    VALUE obj = k;
    struct reflist *refs = (struct reflist *)v;
    rb_objspace_t *objspace = (rb_objspace_t *)ptr;

    /* object should be marked or oldgen */
    if (!RVALUE_MARKED(objspace, obj)) {
        fprintf(stderr, "gc_check_after_marks_i: %s is not marked and not oldgen.\n", rb_obj_info(obj));
        fprintf(stderr, "gc_check_after_marks_i: %p is referred from ", (void *)obj);
        reflist_dump(refs);

        if (reflist_referred_from_machine_context(refs)) {
            fprintf(stderr, " (marked from machine stack).\n");
            /* marked from machine context can be false positive */
        }
        else {
            objspace->rgengc.error_count++;
            fprintf(stderr, "\n");
        }
    }
    return ST_CONTINUE;
}

static void
gc_marks_check(rb_objspace_t *objspace, st_foreach_callback_func *checker_func, const char *checker_name)
{
    MALLOC_COUNTERS_LOCK(objspace);
    struct gc_malloc_bytes saved_malloc = {
        .malloc            = gc_counter_load_relaxed(&objspace->malloc_counters.counters.malloc),
        .free              = gc_counter_load_relaxed(&objspace->malloc_counters.counters.free),
        .malloc_at_last_gc = gc_counter_load_relaxed(&objspace->malloc_counters.counters.malloc_at_last_gc),
        .free_at_last_gc   = gc_counter_load_relaxed(&objspace->malloc_counters.counters.free_at_last_gc),
    };
#if RGENGC_ESTIMATE_OLDMALLOC
    struct gc_malloc_bytes saved_oldmalloc = {
        .malloc            = gc_counter_load_relaxed(&objspace->malloc_counters.oldcounters.malloc),
        .free              = gc_counter_load_relaxed(&objspace->malloc_counters.oldcounters.free),
        .malloc_at_last_gc = gc_counter_load_relaxed(&objspace->malloc_counters.oldcounters.malloc_at_last_gc),
        .free_at_last_gc   = gc_counter_load_relaxed(&objspace->malloc_counters.oldcounters.free_at_last_gc),
    };
#endif
    MALLOC_COUNTERS_UNLOCK(objspace);
    VALUE already_disabled = rb_objspace_gc_disable(objspace);

    objspace->rgengc.allrefs_table = objspace_allrefs(objspace);

    if (checker_func) {
        st_foreach(objspace->rgengc.allrefs_table, checker_func, (st_data_t)objspace);
    }

    if (objspace->rgengc.error_count > 0) {
#if RGENGC_CHECK_MODE >= 5
        allrefs_dump(objspace);
#endif
        if (checker_name) rb_bug("%s: GC has problem.", checker_name);
    }

    objspace_allrefs_destruct(objspace->rgengc.allrefs_table);
    objspace->rgengc.allrefs_table = 0;

    if (already_disabled == Qfalse) rb_objspace_gc_enable(objspace);
    MALLOC_COUNTERS_LOCK(objspace);
    gc_counter_store_release(&objspace->malloc_counters.counters.malloc,            saved_malloc.malloc);
    gc_counter_store_release(&objspace->malloc_counters.counters.free,              saved_malloc.free);
    gc_counter_store_release(&objspace->malloc_counters.counters.malloc_at_last_gc, saved_malloc.malloc_at_last_gc);
    gc_counter_store_release(&objspace->malloc_counters.counters.free_at_last_gc,   saved_malloc.free_at_last_gc);
#if RGENGC_ESTIMATE_OLDMALLOC
    gc_counter_store_release(&objspace->malloc_counters.oldcounters.malloc,            saved_oldmalloc.malloc);
    gc_counter_store_release(&objspace->malloc_counters.oldcounters.free,              saved_oldmalloc.free);
    gc_counter_store_release(&objspace->malloc_counters.oldcounters.malloc_at_last_gc, saved_oldmalloc.malloc_at_last_gc);
    gc_counter_store_release(&objspace->malloc_counters.oldcounters.free_at_last_gc,   saved_oldmalloc.free_at_last_gc);
#endif
    MALLOC_COUNTERS_UNLOCK(objspace);
}
#endif /* RGENGC_CHECK_MODE >= 4 */

struct verify_internal_consistency_struct {
    rb_objspace_t *objspace;
    int err_count;
    size_t live_object_count;
    size_t zombie_object_count;

    VALUE parent;
    bool parent_shareable;
    size_t old_object_count;
    size_t remembered_shady_count;
};

static bool verify_pointer_in_any_heap_p(const void *ptr);

static void
check_generation_i(const VALUE child, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;
    const VALUE parent = data->parent;

    if (RGENGC_CHECK_MODE) GC_ASSERT(RVALUE_OLD_P(data->objspace, parent));

    /* cross-objspace のエッジは shareable/shref の仕組みで生かされ、この objspace の
     * remembered set では管理しない。 */
    if (GET_HEAP_OBJSPACE(child) != data->objspace) return;

    /* multi-Ractor モードに入ると shareable の世界は remembered set ではなく pin/shref で
     * 管理される。mark 末尾の pinned walk が local サイクルごとに全 shareable（とその shref
     * された子）を再 mark し、global GC は世代状態を作り直す。よって端点のどちらかが
     * shareable なら世代間 O->Y 不変条件は成り立たない。これは old な constcache / cc_table /
     * interned string が young(global GC 後)な core class を指す典型的な偽陽性。判定は
     * 瞬間的な単一 objspace 数ではなく rb_multi_ractor_p()（一度 multi 化すると恒久）で行い、
     * multi-Ractor プログラムの一時的な ractor.cnt==1 の窓も被覆する。multi 化しない
     * プログラムは従来の厳密検査のまま。残余リスクは ASAN が拾う。 */
    if (rb_multi_ractor_p() &&
        (MARKED_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(parent), parent) ||
         MARKED_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(child), child))) {
        return;
    }

    if (!RVALUE_OLD_P(data->objspace, child)) {
        if (!RVALUE_REMEMBERED(data->objspace, parent) &&
            !RVALUE_REMEMBERED(data->objspace, child) &&
            !RVALUE_UNCOLLECTIBLE(data->objspace, child)) {
            fprintf(stderr, "verify_internal_consistency_reachable_i: WB miss (O->Y) %s -> %s\n", rb_obj_info(parent), rb_obj_info(child));
            data->err_count++;
        }
    }
}

static void
check_color_i(const VALUE child, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;
    const VALUE parent = data->parent;

    if (!RVALUE_WB_UNPROTECTED(data->objspace, parent) && RVALUE_WHITE_P(data->objspace, child)) {
        fprintf(stderr, "verify_internal_consistency_reachable_i: WB miss (B->W) - %s -> %s\n",
                rb_obj_info(parent), rb_obj_info(child));
        data->err_count++;
    }
}

static void
check_children_i(const VALUE child, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;

    /* fast path: この objspace の子（エッジの 99.99%）。 */
    if (RB_LIKELY(is_pointer_to_heap(data->objspace, (void *)child))) {
        if (check_rvalue_consistency_force(data->objspace, child, FALSE) != 0) {
            fprintf(stderr, "check_children_i: %s has error (referenced from %s)",
                    rb_obj_info(child), rb_obj_info(data->parent));
            data->err_count++;
        }
        return;
    }

    /* 残りの cross-objspace 検査は全 objspace のページを走査する
     * （verify_pointer_in_any_heap_p）。これは world 停止時のみ健全で、mid-local-GC の
     * verify では他 Ractor が lock-free に割り当て・ページ構造を変更し競合する（SEGV）。
     * その場合はスキップし、次の world 停止 verify が再検査する。 */
    if (!rlgc_verify_world_stopped) return;

    /* 非 heap の child がこの callback に来るのは、stale なフィールドを素の rb_gc_mark で
     * たどった場合だけ（兄弟 struct が先に free された、生きているが到達不能な wrapper の
     * dmark でのみ観測）。中断せず報告し継続する。対象先頭ワード（fault-safe に読む。
     * unmap されているかも）で原因フィールドを soak をまたいで特定するため。 */
    if (!verify_pointer_in_any_heap_p((void *)child)) {
        /* 併合途中はグラフが流動的で、一時的な非 heap エッジは想定内。併合後に再検査する。 */
        if (rlgc_during_absorb) return;
        VALUE w[2] = {0, 0};
        bool readable = false;
#ifndef _WIN32
        int fd = open("/proc/self/mem", O_RDONLY);
        if (fd >= 0) {
            if (pread(fd, w, sizeof(w), (off_t)child) == (ssize_t)sizeof(w)) {
                readable = true;
            }
            close(fd);
        }
#endif
        /* parent が Thread wrapper なら、フィールドを raw ポインタ一致で特定する（stale な
         * 対象を参照しない）。rb_obj_is_kind_of ではなく直接のクラスポインタ比較を使う。
         * parent は stale フィールドで到達した任意のオブジェクト（class ヘッダ無しの T_IMEMO
         * call-cache や、absorb 中で klass 自体が stale な T_DATA）でありうるため。直接比較は
         * それらに一致しないだけで済む（本物の Thread wrapper のフィールド名を出せればよい）。 */
        const char *field = "?";
        if (RB_TYPE_P(data->parent, T_DATA) &&
            RBASIC_CLASS(data->parent) == rb_cThread) {
            const rb_thread_t *pth = rb_thread_ptr(data->parent);
            if (child == (VALUE)pth->ractor) field = "th->ractor";
            else if (child == (VALUE)pth->root_fiber) field = "th->root_fiber";
            else if (child == (VALUE)pth->ec) field = "th->ec";
            else if (child == (VALUE)pth->nt) field = "th->nt";
        }
        fprintf(stderr, "VERIFY-NOTE: non-heap child %p (from %s field=%s) readable=%d w0=%p w1=%p\n",
                (void *)child, rb_obj_info(data->parent), field, (int)readable,
                (void *)w[0], (void *)w[1]);
        return;
    }

    if (GET_HEAP_OBJSPACE(child) != data->objspace) {
        /* 合法な cross-objspace エッジは shareable から始まるか、child の shref bit に
         * 記録されたもの（所有者の local GC をまたいで生かされる in-flight の send/move
         * payload。root_scope_check_i も同じ記録を尊重する）だけ。unshareable な parent が
         * 未記録の foreign unshareable child を持つと双方の local GC から不可視になる。
         * 例外は box の top_self（全スレッドの th->top_self が指し、プロセス存続中 VM 恒久）。
         * global GC 中はスキップ。全 shref bit を消し in-flight payload は再 pin で生かすので
         * shref 免除は発火せず、unified な正確 STW mark でこの不変条件自体が無意味になる。 */
        if (!data->parent_shareable &&
            child != rb_vm_top_self() &&
            !MARKED_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(child), child) &&
            !MARKED_IN_BITMAP(GET_HEAP_SHREF_BITS(child), child) &&
            !rb_gc_impl_during_global_gc_p(data->objspace) &&
            !rb_gc_current_ractor_materializing_p() &&
            !rlgc_during_absorb) {
            fprintf(stderr, "check_children_i: containment violation: "
                    "unshareable %s (objspace %p) -> foreign unshareable %s (objspace %p)\n",
                    rb_obj_info(data->parent), (void *)data->objspace,
                    rb_obj_info(child), (void *)GET_HEAP_OBJSPACE(child));
            data->err_count++;
        }

        /* 残りの per-objspace 健全性ルールは所有者の担当。 */
        return;
    }
}

struct verify_any_heap_query {
    const void *ptr;
    bool found;
};

static void
verify_pointer_in_any_heap_i(void *os, void *data)
{
    struct verify_any_heap_query *q = data;
    if (!q->found && is_pointer_to_heap((rb_objspace_t *)os, q->ptr)) {
        q->found = true;
    }
}

/* Whether a heap slot currently holds a live object. Returns false for empty
 * (T_NONE), moved (T_MOVED), and zombie (T_ZOMBIE) slots, and for garbage
 * objects about to be swept. */
static bool
gc_slot_live_object_p(rb_objspace_t *objspace, VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
      case T_NONE:
      case T_MOVED:
      case T_ZOMBIE:
        return false;
      default:
        return !rb_gc_impl_garbage_object_p(objspace, obj);
    }
}

/* verifier 専用: ptr がいずれかの objspace の生きた slot を指すか。呼び出し元は VM lock と
 * barrier を持つので列挙は安定。 */
static bool
verify_pointer_in_any_heap_p(const void *ptr)
{
    struct verify_any_heap_query q = { .ptr = ptr, .found = false };
    rb_gc_vm_each_objspace(verify_pointer_in_any_heap_i, &q);
    return q.found;
}

/* 呼び出し元 Ractor の exact root は、shareable・自 objspace のオブジェクト・shref 記録された
 * in-flight payload だけを指せる。免除は保守的なマシンスキャン（stale slot。走査 Ractor 自身の
 * GC しか root にしない）と、設計上 cross-root される VM グローバル容器（全 objspace が走査し
 * marker が foreign entry を飛ばす）。 */
static void
root_scope_check_i(const char *category, VALUE obj, void *ptr)
{
    struct verify_internal_consistency_struct *data = ptr;

    if (RB_SPECIAL_CONST_P(obj)) return;
    /* この検査は全 objspace を走査する（verify_pointer_in_any_heap_p）ので world 停止時のみ
     * 健全。mid-local-GC の verify は他 Ractor の lock-free 割り当てと競合する。 */
    if (!rlgc_verify_world_stopped) return;
    /* 併合途中は VM グローバル root 表が未併合の src を指す（一時的な非 heap/foreign root）。
     * 併合後に再検査する。 */
    if (rlgc_during_absorb) return;
    if (strcmp(category, "machine_context") == 0 ||
        strcmp(category, "vm_registered_objects") == 0 ||
        strcmp(category, "end_proc") == 0 ||
        strcmp(category, "trap_list") == 0 ||
        /* VM 単一の registered-globals リストは全 Ractor の root 走査が保守的に舐める
         * （slot が別 objspace の値を持ちうる）。rb_gc_mark_maybe が自 objspace の値へ
         * 自己フィルタするので、ここに現れる foreign entry は設計通りでリークではない。 */
        strcmp(category, "registered_globals") == 0) {
        return;
    }

    if (!verify_pointer_in_any_heap_p((void *)obj)) {
        fprintf(stderr, "root_scope_check_i: root category \"%s\" names a non-heap pointer %p\n",
                category, (void *)obj);
        data->err_count++;
        return;
    }

    if (GET_HEAP_OBJSPACE(obj) == data->objspace) return;
    if (MARKED_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(obj), obj)) return;
    if (MARKED_IN_BITMAP(GET_HEAP_SHREF_BITS(obj), obj)) return;
    if (obj == rb_vm_top_self()) return;  /* VM-permanent (see check_children_i) */
    /* receive が materialize 中の送信側常駐スナップショットは sync.in_flight_materializing
     * で root 化される。複製の間だけ有効な foreign-unshareable root（check_children_i 参照）。 */
    if (rb_gc_current_ractor_materializing_p()) return;

    fprintf(stderr, "root_scope_check_i: root category \"%s\" names a foreign "
            "unshareable without a shref record: %s (owner %p, self %p)\n",
            category, rb_obj_info(obj),
            (void *)GET_HEAP_OBJSPACE(obj), (void *)data->objspace);
    data->err_count++;
}

static int
verify_internal_consistency_i(void *page_start, void *page_end, size_t stride,
                              struct verify_internal_consistency_struct *data)
{
    VALUE obj;
    rb_objspace_t *objspace = data->objspace;

    for (obj = (VALUE)page_start; obj != (VALUE)page_end; obj += stride) {
        asan_unpoisoning_object(obj) {
            bool sh_bit = MARKED_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(obj), obj) != 0;
            bool sr_bit = MARKED_IN_BITMAP(GET_HEAP_SHREF_BITS(obj), obj) != 0;

            if (gc_slot_live_object_p(objspace, obj)) {
                /* count objects */
                data->live_object_count++;
                data->parent = obj;
                data->parent_shareable = sh_bit;

                /* bitmap 不変条件: ページの shareable bit は FL_SHAREABLE と正確に一致し、
                 * shref 記録は unshareable しか指さない。 */
                if (sh_bit != !!RB_OBJ_SHAREABLE_P(obj)) {
                    fprintf(stderr, "verify_internal_consistency_i: shareable bit %d "
                            "disagrees with FL_SHAREABLE on %s\n", (int)sh_bit, rb_obj_info(obj));
                    data->err_count++;
                }
                if (sr_bit && sh_bit) {
                    fprintf(stderr, "verify_internal_consistency_i: shref bit on a shareable: %s\n",
                            rb_obj_info(obj));
                    data->err_count++;
                }

                /* Normally, we don't expect T_MOVED objects to be in the heap.
                * But they can stay alive on the stack, */
                if (!gc_object_moved_p(objspace, obj)) {
                    /* moved slots don't have children */
                    rb_objspace_reachable_objects_from(obj, check_children_i, (void *)data);
                }

                /* check health of children */
                if (RVALUE_OLD_P(objspace, obj)) data->old_object_count++;
                if (RVALUE_WB_UNPROTECTED(objspace, obj) && RVALUE_UNCOLLECTIBLE(objspace, obj)) data->remembered_shady_count++;

                if (!is_marking(objspace) && RVALUE_OLD_P(objspace, obj)) {
                    /* reachable objects from an oldgen object should be old or (young with remember) */
                    data->parent = obj;
                    rb_objspace_reachable_objects_from(obj, check_generation_i, (void *)data);
                }

                if (!is_marking(objspace) && rb_gc_obj_shareable_p(obj)) {
                    rb_gc_verify_shareable(obj);
                }

                if (is_incremental_marking(objspace)) {
                    if (RVALUE_BLACK_P(objspace, obj)) {
                        /* reachable objects from black objects should be black or grey objects */
                        data->parent = obj;
                        rb_objspace_reachable_objects_from(obj, check_color_i, (void *)data);
                    }
                }
            }
            else {
                /* free した slot は古い pin bit を次の生に持ち越してはならない（lazy に
                 * 未 sweep な dead オブジェクトは sweep が来るまで正当に保持する）。 */
                if (BUILTIN_TYPE(obj) == T_NONE && (sh_bit || sr_bit)) {
                    fprintf(stderr, "verify_internal_consistency_i: T_NONE slot carries "
                            "shareable=%d shref=%d bits\n", (int)sh_bit, (int)sr_bit);
                    data->err_count++;
                }

                if (BUILTIN_TYPE(obj) == T_ZOMBIE) {
                    data->zombie_object_count++;

                    if ((RBASIC(obj)->flags & ~ZOMBIE_OBJ_KEPT_FLAGS) != T_ZOMBIE) {
                        fprintf(stderr, "verify_internal_consistency_i: T_ZOMBIE has extra flags set: %s\n",
                                rb_obj_info(obj));
                        data->err_count++;
                    }

                    if (!!FL_TEST(obj, FL_FINALIZE) != !!st_is_member(finalizer_table, obj)) {
                        fprintf(stderr, "verify_internal_consistency_i: FL_FINALIZE %s but %s finalizer_table: %s\n",
                                FL_TEST(obj, FL_FINALIZE) ? "set" : "not set", st_is_member(finalizer_table, obj) ? "in" : "not in",
                                rb_obj_info(obj));
                        data->err_count++;
                    }
                }
            }
        }
    }

    return 0;
}

static int
gc_verify_heap_page(rb_objspace_t *objspace, struct heap_page *page, VALUE obj)
{
    unsigned int has_remembered_shady = FALSE;
    unsigned int has_remembered_old = FALSE;
    int remembered_old_objects = 0;
    int free_objects = 0;
    int zombie_objects = 0;

    short slot_size = page->slot_size;
    uintptr_t start = (uintptr_t)page->start;
    uintptr_t end = start + page->total_slots * slot_size;

    for (uintptr_t ptr = start; ptr < end; ptr += slot_size) {
        VALUE val = (VALUE)ptr;
        asan_unpoisoning_object(val) {
            enum ruby_value_type type = BUILTIN_TYPE(val);

            if (type == T_NONE) free_objects++;
            if (type == T_ZOMBIE) zombie_objects++;
            if (RVALUE_PAGE_UNCOLLECTIBLE(page, val) && RVALUE_PAGE_WB_UNPROTECTED(page, val)) {
                has_remembered_shady = TRUE;
            }
            if (RVALUE_PAGE_MARKING(page, val)) {
                has_remembered_old = TRUE;
                remembered_old_objects++;
            }
        }
    }

    if (!is_incremental_marking(objspace) &&
        page->flags.has_remembered_objects == FALSE && has_remembered_old == TRUE) {

        for (uintptr_t ptr = start; ptr < end; ptr += slot_size) {
            VALUE val = (VALUE)ptr;
            if (RVALUE_PAGE_MARKING(page, val)) {
                fprintf(stderr, "marking -> %s\n", rb_obj_info(val));
            }
        }
        rb_bug("page %p's has_remembered_objects should be false, but there are remembered old objects (%d). %s",
               (void *)page, remembered_old_objects, obj ? rb_obj_info(obj) : "");
    }

    if (page->flags.has_uncollectible_wb_unprotected_objects == FALSE && has_remembered_shady == TRUE) {
        rb_bug("page %p's has_remembered_shady should be false, but there are remembered shady objects. %s",
               (void *)page, obj ? rb_obj_info(obj) : "");
    }

    if (0) {
        /* free_slots may not equal to free_objects */
        if (page->free_slots != free_objects) {
            rb_bug("page %p's free_slots should be %d, but %d", (void *)page, page->free_slots, free_objects);
        }
    }
    if (page->final_slots != zombie_objects) {
        rb_bug("page %p's final_slots should be %d, but %d", (void *)page, page->final_slots, zombie_objects);
    }

    return remembered_old_objects;
}

static int
gc_verify_heap_pages_(rb_objspace_t *objspace, struct ccan_list_head *head)
{
    int remembered_old_objects = 0;
    struct heap_page *page = 0;

    ccan_list_for_each(head, page, page_node) {
        asan_unlock_freelist(page);
        struct free_region *region = page->free_region;
        while (region) {
            VALUE vp = (VALUE)region;
            rb_asan_unpoison_object(vp, false);
            if (BUILTIN_TYPE(vp) != T_NONE) {
                fprintf(stderr, "free region head expected to be T_NONE but was: %s\n", rb_obj_info(vp));
            }
            struct free_region *next = region->next;
            rb_asan_poison_object(vp);
            region = next;
        }
        asan_lock_freelist(page);

        if (page->flags.has_remembered_objects == FALSE) {
            remembered_old_objects += gc_verify_heap_page(objspace, page, Qfalse);
        }
    }

    return remembered_old_objects;
}

static int
gc_verify_heap_pages(rb_objspace_t *objspace)
{
    int remembered_old_objects = 0;
    for (int i = 0; i < HEAP_COUNT; i++) {
        remembered_old_objects += gc_verify_heap_pages_(objspace, &((&heaps[i])->pages));
    }
    return remembered_old_objects;
}

static void
gc_verify_internal_consistency_(rb_objspace_t *objspace)
{
    struct verify_internal_consistency_struct data = {0};

    data.objspace = objspace;
    gc_report(5, objspace, "gc_verify_internal_consistency: start\n");

    /* check relations */
    for (size_t i = 0; i < rb_darray_size(objspace->heap_pages.sorted); i++) {
        struct heap_page *page = rb_darray_get(objspace->heap_pages.sorted, i);
        short slot_size = page->slot_size;

        uintptr_t start = (uintptr_t)page->start;
        uintptr_t end = start + page->total_slots * slot_size;

        verify_internal_consistency_i((void *)start, (void *)end, slot_size, &data);
    }

    /* 呼び出し元 Ractor の root scoping を検査する（walk は現在の objspace を root にするので、
     * それが検査対象のときだけ）。global GC 中はスキップ。rb_gc_mark_roots が global_gc=true で
     * 全 Ractor の root と main 限定の VM グローバル容器を意図的にまたぎ、unified な正確 mark が
     * 正当に foreign オブジェクトへ届くので、この検査の objspace 封じ込め不変条件は適用されない。 */
    if (!rb_gc_single_objspace_p() && objspace == rb_gc_get_objspace() &&
        !rb_gc_impl_during_global_gc_p(objspace)) {
        rb_objspace_reachable_objects_from_root(root_scope_check_i, &data);
    }

    if (data.err_count != 0) {
#if RGENGC_CHECK_MODE >= 5
        objspace->rgengc.error_count = data.err_count;
        gc_marks_check(objspace, NULL, NULL);
        allrefs_dump(objspace);
#endif
        rb_bug("gc_verify_internal_consistency: found internal inconsistency.");
    }

    /* check heap_page status */
    gc_verify_heap_pages(objspace);

    /* check counters */

    if (!is_lazy_sweeping(objspace) &&
            !finalizing &&
            !rb_gc_multi_ractor_p()) {
        if (objspace_live_slots(objspace) != data.live_object_count) {
            fprintf(stderr, "heap_pages_final_slots: %"PRIdSIZE", total_freed_objects: %"PRIdSIZE"\n",
                    total_final_slots_count(objspace), total_freed_objects(objspace));
            rb_bug("inconsistent live slot number: expect %"PRIuSIZE", but %"PRIuSIZE".",
                   objspace_live_slots(objspace), data.live_object_count);
        }
    }

    if (!is_marking(objspace)) {
        if (objspace->rgengc.old_objects != data.old_object_count) {
            rb_bug("inconsistent old slot number: expect %"PRIuSIZE", but %"PRIuSIZE".",
                   objspace->rgengc.old_objects, data.old_object_count);
        }
        if (objspace->rgengc.uncollectible_wb_unprotected_objects != data.remembered_shady_count) {
            rb_bug("inconsistent number of wb unprotected objects: expect %"PRIuSIZE", but %"PRIuSIZE".",
                   objspace->rgengc.uncollectible_wb_unprotected_objects, data.remembered_shady_count);
        }
    }

    if (!finalizing) {
        size_t list_count = 0;

        {
            VALUE z = heap_pages_deferred_final;
            while (z) {
                list_count++;
                z = RZOMBIE(z)->next;
            }
        }

        if (total_final_slots_count(objspace) != data.zombie_object_count ||
            total_final_slots_count(objspace) != list_count) {

            rb_bug("inconsistent finalizing object count:\n"
                    "  expect %"PRIuSIZE"\n"
                    "  but    %"PRIuSIZE" zombies\n"
                    "  heap_pages_deferred_final list has %"PRIuSIZE" items.",
                    total_final_slots_count(objspace),
                    data.zombie_object_count,
                    list_count);
        }
    }

    gc_report(5, objspace, "gc_verify_internal_consistency: OK\n");
}

/* `during_gc` マクロは裸の識別子を `objspace->flags.during_gc` に展開するので、foreign な
 * objspace のフラグは直接書けない。これらのヘルパは `objspace` 引数経由でアクセスする。 */
static inline unsigned int
gc_during_gc_get(const rb_objspace_t *objspace)
{
    return during_gc;
}

static inline void
gc_during_gc_set(rb_objspace_t *objspace, unsigned int v)
{
    during_gc = v;
}

/* 検査対象の objspace と現在の Ractor の objspace の両方で during_gc を一時的にクリアして
 * 整合性検査を走らせる。検査が使う rb_objspace_reachable_objects_from() は objspace_ptr では
 * なく現在の Ractor の objspace（rb_gc_get_objspace()）で判定する。global GC では driver が
 * foreign な os の per-objspace verify を走らせるため、driver 側の during_gc も消す必要がある
 * （cur == objspace のときは no-op）。 */
static void
gc_verify_internal_consistency_body(rb_objspace_t *objspace)
{
    const unsigned int prev_during_gc = during_gc;
    during_gc = FALSE; // stop gc here

    rb_objspace_t *const cur = rb_gc_get_objspace();
    const unsigned int prev_cur_during_gc = (cur != objspace) ? gc_during_gc_get(cur) : 0;
    if (cur != objspace) gc_during_gc_set(cur, FALSE);
    {
        gc_verify_internal_consistency_(objspace);
    }
    if (cur != objspace) gc_during_gc_set(cur, prev_cur_during_gc);
    during_gc = prev_during_gc;
}

static void
gc_verify_internal_consistency(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    /* GC の途中で呼ばれた（この objspace で during_gc が既に立つ）ときは VM lock も barrier も
     * 取らない。非 main の local GC は VM lock を持たず、ここで待つと GC の途中で保留中の
     * global barrier に合流してしまい（GC 中は VM lock を取ってはならない）、global GC が
     * この objspace の during_gc を消して local mark が歩行中の heap を sweep しかねない。
     * barrier も不要。objspace は single-writer でこの verify は所有者スレッドで同期的に走り、
     * 全 objspace に during_gc を立てる global driver は既に lock と barrier を持つ。 */
    if (during_gc) {
        /* world が止まるのは global GC の driver がこれを走らせるとき（barrier 保持）だけ。
         * 非 main の worker GC は他 Ractor を止めない。 */
        const bool prev_ws = rlgc_verify_world_stopped;
        rlgc_verify_world_stopped = rb_gc_impl_during_global_gc_p(objspace);
        gc_verify_internal_consistency_body(objspace);
        rlgc_verify_world_stopped = prev_ws;
        return;
    }

    unsigned int lev = RB_GC_VM_LOCK();
    {
        rb_gc_vm_barrier(); // stop other ractors
        const bool prev_ws = rlgc_verify_world_stopped;
        rlgc_verify_world_stopped = true;   // barrier 保持中なので全 objspace 走査は健全
        gc_verify_internal_consistency_body(objspace);
        rlgc_verify_world_stopped = prev_ws;
    }
    RB_GC_VM_UNLOCK(lev);
}

static void
heap_move_pooled_pages_to_free_pages(rb_heap_t *heap)
{
    if (heap->pooled_pages) {
        if (heap->free_pages) {
            struct heap_page *free_pages_tail = heap->free_pages;
            while (free_pages_tail->free_next) {
                free_pages_tail = free_pages_tail->free_next;
            }
            free_pages_tail->free_next = heap->pooled_pages;
        }
        else {
            heap->free_pages = heap->pooled_pages;
        }

        heap->pooled_pages = NULL;
    }
}

static int
gc_remember_unprotected(rb_objspace_t *objspace, VALUE obj)
{
    struct heap_page *page = GET_HEAP_PAGE(obj);
    bits_t *uncollectible_bits = &page->uncollectible_bits[0];

    if (!MARKED_IN_BITMAP(uncollectible_bits, obj)) {
        page->flags.has_uncollectible_wb_unprotected_objects = TRUE;
        MARK_IN_BITMAP(uncollectible_bits, obj);
        /* RVALUE_PAGE_OLD_UNCOLLECTIBLE_SET と同様、そのオブジェクトの objspace に数える。 */
        page->objspace->rgengc.uncollectible_wb_unprotected_objects++;

#if RGENGC_PROFILE > 0
        objspace->profile.total_remembered_shady_object_count++;
#if RGENGC_PROFILE >= 2
        objspace->profile.remembered_shady_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
#endif
        return TRUE;
    }
    else {
        return FALSE;
    }
}

static inline void
gc_marks_wb_unprotected_objects_plane(rb_objspace_t *objspace, uintptr_t p, bits_t bits, short slot_size)
{
    if (bits) {
        do {
            if (bits & 1) {
                gc_report(2, objspace, "gc_marks_wb_unprotected_objects: marked shady: %s\n", rb_obj_info((VALUE)p));
                GC_ASSERT(RVALUE_WB_UNPROTECTED(objspace, (VALUE)p));
                GC_ASSERT(RVALUE_MARKED(objspace, (VALUE)p));
                gc_mark_children(objspace, (VALUE)p);
            }
            p += slot_size;
            bits >>= 1;
        } while (bits);
    }
}

static void
gc_marks_wb_unprotected_objects(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page = 0;

    ccan_list_for_each(&heap->pages, page, page_node) {
        bits_t *mark_bits = page->mark_bits;
        bits_t *wbun_bits = page->wb_unprotected_bits;
        uintptr_t p = page->start;
        short slot_size = page->slot_size;
        int total_slots = page->total_slots;
        int bitmap_plane_count = CEILDIV(total_slots, BITS_BITLENGTH);
        size_t j;

        for (j=0; j<(size_t)bitmap_plane_count; j++) {
            bits_t bits = mark_bits[j] & wbun_bits[j];
            gc_marks_wb_unprotected_objects_plane(objspace, p, bits, slot_size);
            p += BITS_BITLENGTH * slot_size;
        }
    }

    gc_mark_stacked_objects_all(objspace);
}

void
rb_gc_impl_declare_weak_references(void *objspace_ptr, VALUE obj)
{
    FL_SET_RAW(obj, RUBY_FL_WEAK_REFERENCE);
}

bool
rb_gc_impl_handle_weak_references_alive_p(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    /* local GC は foreign なオブジェクトの生死を判定できないので生存扱いにする（所有者
     * または global GC が判定する。global GC の unified mark は正確で全てを判定できる）。 */
    if (RB_UNLIKELY(GET_HEAP_OBJSPACE(obj) != objspace) && !objspace->during_global_gc) return true;

    bool marked = RVALUE_MARKED(objspace, obj);

    if (marked) {
        rgengc_check_relation(objspace, obj);
    }

    return marked;
}

static void
gc_update_weak_references(rb_objspace_t *objspace)
{
    VALUE *obj_ptr;
    rb_darray_foreach(objspace->weak_references, i, obj_ptr) {
        gc_mark_set_parent(objspace, *obj_ptr);
        rb_gc_handle_weak_references(*obj_ptr);
        gc_mark_set_parent_invalid(objspace);
    }

    size_t capa = rb_darray_capa(objspace->weak_references);
    size_t size = rb_darray_size(objspace->weak_references);

    objspace->profile.weak_references_count = size;

    rb_darray_clear(objspace->weak_references);

    /* If the darray has capacity for more than four times the amount used, we
     * shrink it down to half of that capacity. */
    if (capa > size * 4) {
        rb_darray_resize_capa_without_gc(&objspace->weak_references, size * 2);
    }
}

static void
gc_marks_finish(rb_objspace_t *objspace)
{
    /* finish incremental GC */
    if (is_incremental_marking(objspace)) {
        if (RGENGC_CHECK_MODE && is_mark_stack_empty(&objspace->mark_stack) == 0) {
            rb_bug("gc_marks_finish: mark stack is not empty (%"PRIdSIZE").",
                   mark_stack_size(&objspace->mark_stack));
        }

        mark_roots(objspace, NULL);
        while (gc_mark_stacked_objects_incremental(objspace, INT_MAX) == false);

#if RGENGC_CHECK_MODE >= 2
        if (gc_verify_heap_pages(objspace) != 0) {
            rb_bug("gc_marks_finish (incremental): there are remembered old objects.");
        }
#endif

        objspace->flags.during_incremental_marking = FALSE;
        /* check children of all marked wb-unprotected objects */
        for (int i = 0; i < HEAP_COUNT; i++) {
            gc_marks_wb_unprotected_objects(objspace, &heaps[i]);
        }
    }

    /* 通常 mark が届かなかった shareable と shref を pin する。local GC は shareable
     * （他 objspace が持ちうる）も shref（foreign な shareable が指す）も決して free しては
     * ならない。全走査後に走るので pin 数は retention 指標（global GC だけが回収できる
     * garbage の上限）になる。global GC は pin しない（unified mark が正確な到達可能性）。
     * （RGENGC_CHECK_MODE >= 4 の allrefs 比較はこの pin を模さず誤検出するので注意。） */
    objspace->rlgc.last_cycle_pinned = 0;
    if (!rb_gc_single_objspace_p() && !objspace->during_global_gc) {
        objspace->rlgc.last_cycle_pinned = 1;
        size_t marked_before = objspace->marked_slots;
        gc_mark_set_parent_raw(objspace, Qundef, false);
        for (int i = 0; i < HEAP_COUNT; i++) {
            rlgc_pinned_roots_mark(objspace, &heaps[i]);
        }
        /* そしてそれらが生かすもの全て。 */
        gc_mark_stacked_objects_all(objspace);
        objspace->rlgc.stalled_shareables = objspace->marked_slots - marked_before;
    }

    gc_update_weak_references(objspace);

#if RGENGC_CHECK_MODE >= 4
    during_gc = FALSE;
    gc_marks_check(objspace, gc_check_after_marks_i, "after_marks");
    during_gc = TRUE;
#endif

    {
        const unsigned long r_mul = objspace->live_ractor_cache_count > 8 ? 8 : objspace->live_ractor_cache_count; // upto 8

        size_t total_slots = objspace_available_slots(objspace);
        size_t sweep_slots = total_slots - objspace->marked_slots; /* will be swept slots */
        size_t max_free_slots = (size_t)(total_slots * gc_params.heap_free_slots_max_ratio);
        size_t min_free_slots = (size_t)(total_slots * gc_params.heap_free_slots_min_ratio);
        if (min_free_slots < gc_params.heap_free_slots * r_mul) {
            min_free_slots = gc_params.heap_free_slots * r_mul;
        }

        int full_marking = is_full_marking(objspace);

        GC_ASSERT(objspace_available_slots(objspace) >= objspace->marked_slots);

        /* Setup freeable slots. */
        size_t total_init_slots = 0;
        for (int i = 0; i < HEAP_COUNT; i++) {
            total_init_slots += (gc_params.heap_init_bytes / heaps[i].slot_size) * r_mul;
        }

        if (max_free_slots < total_init_slots) {
            max_free_slots = total_init_slots;
        }

        /* Approximate freeable pages using the average slots-per-pages across all heaps */
        if (sweep_slots > max_free_slots) {
            size_t excess_slots = sweep_slots - max_free_slots;
            size_t total_heap_pages = heap_eden_total_pages(objspace);
            heap_pages_freeable_pages = total_heap_pages > 0
                ? excess_slots * total_heap_pages / total_slots
                : 0;
        }
        else {
            heap_pages_freeable_pages = 0;
        }

        if (objspace->heap_pages.allocatable_bytes == 0 && sweep_slots < min_free_slots) {
            if (!full_marking && sweep_slots < min_free_slots * 7 / 8) {
                if (objspace->profile.count - objspace->rgengc.last_major_gc < RVALUE_OLD_AGE) {
                    full_marking = TRUE;
                }
                else {
                    gc_report(1, objspace, "gc_marks_finish: next is full GC!!)\n");
                    gc_needs_major_flags |= GPR_FLAG_MAJOR_BY_NOFREE;
                }
            }

            if (full_marking) {
                heap_allocatable_bytes_expand(objspace, NULL, sweep_slots, total_slots, heaps[0].slot_size);
            }
        }

        if (full_marking) {
            /* See the comment about RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR */
            const double r = gc_params.oldobject_limit_factor;
            objspace->rgengc.uncollectible_wb_unprotected_objects_limit = MAX(
                (size_t)(objspace->rgengc.uncollectible_wb_unprotected_objects * r),
                (size_t)(objspace->rgengc.old_objects * gc_params.uncollectible_wb_unprotected_objects_limit_ratio)
            );
            objspace->rgengc.old_objects_limit = (size_t)(objspace->rgengc.old_objects * r);
        }

        if (objspace->rgengc.uncollectible_wb_unprotected_objects > objspace->rgengc.uncollectible_wb_unprotected_objects_limit) {
            gc_needs_major_flags |= GPR_FLAG_MAJOR_BY_SHADY;
        }
        if (objspace->rgengc.old_objects > objspace->rgengc.old_objects_limit) {
            gc_needs_major_flags |= GPR_FLAG_MAJOR_BY_OLDGEN;
        }

        gc_report(1, objspace, "gc_marks_finish (marks %"PRIdSIZE" objects, "
                  "old %"PRIdSIZE" objects, total %"PRIdSIZE" slots, "
                   "sweep %"PRIdSIZE" slots, allocatable %"PRIdSIZE" bytes, next GC: %s)\n",
                  objspace->marked_slots, objspace->rgengc.old_objects, objspace_available_slots(objspace), sweep_slots, objspace->heap_pages.allocatable_bytes,
                  gc_needs_major_flags ? "major" : "minor");
    }

    // TODO: refactor so we don't need to call this
    rb_ractor_finish_marking();

    gc_event_hook_objspace(objspace, RUBY_INTERNAL_EVENT_GC_END_MARK);
}

static bool
gc_compact_heap_cursors_met_p(rb_heap_t *heap)
{
    return heap->sweeping_page == heap->compact_cursor;
}


static rb_heap_t *
gc_compact_destination_pool(rb_objspace_t *objspace, rb_heap_t *src_pool, VALUE obj)
{
    size_t obj_size = rb_gc_obj_optimal_size(obj);
    if (obj_size == 0) {
        return src_pool;
    }

    GC_ASSERT(rb_gc_impl_size_allocatable_p(obj_size));

    size_t idx = heap_idx_for_size(obj_size);

    return &heaps[idx];
}

static bool
gc_compact_move(rb_objspace_t *objspace, rb_heap_t *heap, VALUE src)
{
    GC_ASSERT(BUILTIN_TYPE(src) != T_MOVED);
    GC_ASSERT(gc_is_moveable_obj(objspace, src));

    rb_heap_t *dest_pool = gc_compact_destination_pool(objspace, heap, src);
    if (gc_compact_heap_cursors_met_p(dest_pool)) {
        return dest_pool != heap;
    }

    while (!try_move(objspace, dest_pool, dest_pool->free_pages, src)) {
        struct gc_sweep_context ctx = {
            .page = dest_pool->sweeping_page,
            .final_slots = 0,
            .freed_slots = 0,
            .empty_slots = 0,
        };

        /* The page of src could be partially compacted, so it may contain
         * T_MOVED. Sweeping a page may read objects on this page, so we
         * need to lock the page. */
        lock_page_body(objspace, GET_PAGE_BODY(src));
        gc_sweep_page(objspace, dest_pool, &ctx);
        unlock_page_body(objspace, GET_PAGE_BODY(src));

        if (dest_pool->sweeping_page->free_slots > 0) {
            heap_add_freepage(dest_pool, dest_pool->sweeping_page);
        }

        dest_pool->sweeping_page = ccan_list_next(&dest_pool->pages, dest_pool->sweeping_page, page_node);
        if (gc_compact_heap_cursors_met_p(dest_pool)) {
            return dest_pool != heap;
        }
    }

    return true;
}

static bool
gc_compact_plane(rb_objspace_t *objspace, rb_heap_t *heap, uintptr_t p, bits_t bitset, struct heap_page *page)
{
    short slot_size = page->slot_size;

    do {
        VALUE vp = (VALUE)p;
        GC_ASSERT(vp % sizeof(VALUE) == 0);

        if (bitset & 1) {
            objspace->rcompactor.considered_count_table[BUILTIN_TYPE(vp)]++;

            if (gc_is_moveable_obj(objspace, vp)) {
                if (!gc_compact_move(objspace, heap, vp)) {
                    //the cursors met. bubble up
                    return false;
                }
            }
        }
        p += slot_size;
        bitset >>= 1;
    } while (bitset);

    return true;
}

// Iterate up all the objects in page, moving them to where they want to go
static bool
gc_compact_page(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    GC_ASSERT(page == heap->compact_cursor);

    bits_t *mark_bits, *pin_bits;
    bits_t bitset;
    uintptr_t p = page->start;
    short slot_size = page->slot_size;
    int total_slots = page->total_slots;
    int bitmap_plane_count = CEILDIV(total_slots, BITS_BITLENGTH);

    mark_bits = page->mark_bits;
    pin_bits = page->pinned_bits;

    for (int j = 0; j < bitmap_plane_count; j++) {
        // objects that can be moved are marked and not pinned
        bitset = (mark_bits[j] & ~pin_bits[j]);
        if (bitset) {
            if (!gc_compact_plane(objspace, heap, (uintptr_t)p, bitset, page))
                return false;
        }
        p += BITS_BITLENGTH * slot_size;
    }

    return true;
}

static bool
gc_compact_all_compacted_p(rb_objspace_t *objspace)
{
    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];

        if (heap->total_pages > 0 &&
                !gc_compact_heap_cursors_met_p(heap)) {
            return false;
        }
    }

    return true;
}

/* compaction の move 相。この objspace の可動オブジェクトを再配置し T_MOVED の forwarding を
 * 残すが、参照はまだ更新しない。global GC は全 objspace を更新する前にこれを全 objspace に
 * 対して呼ぶ（2 相）ので、移動済みオブジェクトへの cross-objspace 参照は全 objspace の
 * forwarding が揃ってから 1 度だけ書き換えられる。 */
static void
gc_compact_relocate(rb_objspace_t *objspace)
{
    gc_compact_start(objspace);

    while (!gc_compact_all_compacted_p(objspace)) {
        for (int i = 0; i < HEAP_COUNT; i++) {
            rb_heap_t *heap = &heaps[i];

            if (gc_compact_heap_cursors_met_p(heap)) {
                continue;
            }

            struct heap_page *start_page = heap->compact_cursor;

            if (!gc_compact_page(objspace, heap, start_page)) {
                lock_page_body(objspace, start_page->body);

                continue;
            }

            // If we get here, we've finished moving all objects on the compact_cursor page
            // So we can lock it and move the cursor on to the next one.
            lock_page_body(objspace, start_page->body);
            heap->compact_cursor = ccan_list_prev(&heap->pages, heap->compact_cursor, page_node);
        }
    }
}

static void
gc_sweep_compact(rb_objspace_t *objspace)
{
    gc_compact_relocate(objspace);
    /* compacting global GC は finish（参照更新）を、全 objspace の再配置後の第 2 相へ遅延する。 */
    if (!rlgc_global.compacting) {
        gc_compact_finish(objspace);
    }
}

static void
gc_marks_rest(rb_objspace_t *objspace)
{
    gc_report(1, objspace, "gc_marks_rest\n");

    for (int i = 0; i < HEAP_COUNT; i++) {
        (&heaps[i])->pooled_pages = NULL;
    }

    if (is_incremental_marking(objspace)) {
        while (gc_mark_stacked_objects_incremental(objspace, INT_MAX) == FALSE);
    }
    else {
        gc_mark_stacked_objects_all(objspace);
    }

    gc_marks_finish(objspace);
}

static bool
gc_marks_step(rb_objspace_t *objspace, size_t slots)
{
    bool marking_finished = false;

    GC_ASSERT(is_marking(objspace));
    if (gc_mark_stacked_objects_incremental(objspace, slots)) {
        gc_marks_finish(objspace);

        marking_finished = true;
    }

    return marking_finished;
}

static bool
gc_marks_continue(rb_objspace_t *objspace, rb_heap_t *heap)
{
    GC_ASSERT(dont_gc_val() == FALSE || objspace->profile.latest_gc_info & GPR_FLAG_METHOD);
    bool marking_finished = true;

    gc_marking_enter(objspace);

    if (heap->free_pages) {
        gc_report(2, objspace, "gc_marks_continue: has pooled pages");

        marking_finished = gc_marks_step(objspace, objspace->rincgc.step_slots);
    }
    else {
        gc_report(2, objspace, "gc_marks_continue: no more pooled pages (stack depth: %"PRIdSIZE").\n",
                  mark_stack_size(&objspace->mark_stack));
        heap->force_incremental_marking_finish_count++;
        gc_marks_rest(objspace);
    }

    gc_marking_exit(objspace);

    return marking_finished;
}

/* この objspace の root として次を mark する。
 * - 全 shareable: 唯一の参照を他 objspace が持つことがあり local GC からは見えない。
 *   sweep で飛ばすのではなく mark することで世代不変条件を保つ（pin されたオブジェクトも
 *   通常の生存オブジェクトと同様に age/promote する）。shareable の死は global GC だけが判定。
 * - 全 shref（shareable から参照される unshareable）: 参照元の shareable は他 objspace や
 *   in-flight のメッセージキューにありうる。write barrier が維持する。
 * VM が単一 Ractor の間はスキップ。local GC が全世界 GC となり shareable も通常通り死ねる。 */
static void
rlgc_pinned_roots_mark(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page = NULL;

    /* mark_roots より前に走るので、前回 GC が残した poison ではなく有効な（なし）parent を
     * rgengc_check_relation に与える。 */
    gc_mark_set_parent_raw(objspace, Qundef, false);

    /* local GC は shareable を決して free も traverse もしない。その unshareable な子は
     * shref bit で生かす。よって:
     *   - shareable: mark bit を立てるだけ（old オブジェクト同様）で sweep に残させ、traverse
     *     はしない。
     *   - shref（shareable から参照される unshareable）: mark かつ traverse する。remembered な
     *     old->young 対象と同様で、これが無いと参照元の shareable が歩かれず到達不能に見える。
     * GC 間でオブジェクトが shareable になりうるので、前回の sweep でなく mark 開始時に走る。 */
    ccan_list_for_each(&heap->pages, page, page_node) {
        if (!(page->has_shareable_objects | page->has_shref_objects)) continue;

        uintptr_t p = page->start;
        short slot_size = page->slot_size;
        int total_slots = page->total_slots;
        int bitmap_plane_count = CEILDIV(total_slots, BITS_BITLENGTH);

        for (int j = 0; j < bitmap_plane_count; j++) {
            bits_t sr_bits = page->shref_bits[j];
            /* 通常 mark が未 mark で残した pin だけがここで要処理。既 mark（traversal で到達、
             * あるいは old で事前 mark）は gc_mark_set で no-op になるので訪れず飛ばす。 */
            bits_t bitset = (page->shareable_bits[j] | sr_bits) & ~page->mark_bits[j];
            uintptr_t pp = p;
            while (bitset) {
                if (bitset & 1) {
                    VALUE obj = (VALUE)pp;
                    asan_unpoisoning_object(obj) {
                        switch (BUILTIN_TYPE(obj)) {
                          case T_NONE:
                          case T_ZOMBIE:
                          case T_MOVED:
                            /* dead な slot（finalizer 待ちの zombie など）は root でない。 */
                            break;
                          default:
                            gc_report(2, objspace, "rlgc_pinned_roots_mark: mark %s\n", rb_obj_info(obj));
                            if (sr_bits & 1) {
                                gc_mark(objspace, obj);          /* shref: root + traverse */
                            }
                            else if (gc_mark_set(objspace, obj)) {
                                gc_aging(objspace, obj);         /* shareable: mark, no traverse */
                            }
                            break;
                        }
                    }
                }
                pp += slot_size;
                bitset >>= 1;
                sr_bits >>= 1;
            }
            p += BITS_BITLENGTH * slot_size;
        }
    }
}

static void
gc_marks_start(rb_objspace_t *objspace, int full_mark)
{
    /* start marking */
    gc_report(1, objspace, "gc_marks_start: (%s)\n", full_mark ? "full" : "minor");
    gc_mode_transition(objspace, gc_mode_marking);

    if (full_mark) {
        size_t incremental_marking_steps = (objspace->rincgc.pooled_slots / INCREMENTAL_MARK_STEP_ALLOCATIONS) + 1;
        objspace->rincgc.step_slots = (objspace->marked_slots * 2) / incremental_marking_steps;

        if (0) fprintf(stderr, "objspace->marked_slots: %"PRIdSIZE", "
                       "objspace->rincgc.pooled_page_num: %"PRIdSIZE", "
                       "objspace->rincgc.step_slots: %"PRIdSIZE", \n",
                       objspace->marked_slots, objspace->rincgc.pooled_slots, objspace->rincgc.step_slots);
        objspace->flags.during_minor_gc = FALSE;
        if (ruby_enable_autocompact && rb_gc_single_objspace_p()) {
            objspace->flags.during_compacting |= TRUE;
        }
        objspace->profile.major_gc_count++;
        objspace->rgengc.uncollectible_wb_unprotected_objects = 0;
        objspace->rgengc.old_objects = 0;
        objspace->rgengc.last_major_gc = objspace->profile.count;
        objspace->marked_slots = 0;

        for (int i = 0; i < HEAP_COUNT; i++) {
            rb_heap_t *heap = &heaps[i];
            rgengc_mark_and_rememberset_clear(objspace, heap);
            heap_move_pooled_pages_to_free_pages(heap);

            if (objspace->flags.during_compacting) {
                struct heap_page *page = NULL;

                ccan_list_for_each(&heap->pages, page, page_node) {
                    page->pinned_slots = 0;
                }
            }
        }
    }
    else {
        objspace->flags.during_minor_gc = TRUE;
        objspace->marked_slots =
          objspace->rgengc.old_objects + objspace->rgengc.uncollectible_wb_unprotected_objects; /* uncollectible objects are marked already */
        objspace->profile.minor_gc_count++;

        for (int i = 0; i < HEAP_COUNT; i++) {
            rgengc_rememberset_mark(objspace, &heaps[i]);
        }
    }

    mark_roots(objspace, NULL);

    gc_report(1, objspace, "gc_marks_start: (%s) end, stack in %"PRIdSIZE"\n",
              full_mark ? "full" : "minor", mark_stack_size(&objspace->mark_stack));
}

static bool
gc_marks(rb_objspace_t *objspace, int full_mark)
{
    gc_marking_enter(objspace);

    bool marking_finished = false;

    /* setup marking */

    gc_marks_start(objspace, full_mark);
    if (!is_incremental_marking(objspace)) {
        gc_marks_rest(objspace);
        marking_finished = true;
    }

#if RGENGC_PROFILE > 0
    if (gc_prof_record(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->old_objects = objspace->rgengc.old_objects;
    }
#endif

    gc_marking_exit(objspace);

    return marking_finished;
}

/* RGENGC */

static void
gc_report_body(int level, rb_objspace_t *objspace, const char *fmt, ...)
{
    if (level <= RGENGC_DEBUG) {
        char buf[1024];
        FILE *out = stderr;
        va_list args;
        const char *status = " ";

        if (during_gc) {
            status = is_full_marking(objspace) ? "+" : "-";
        }
        else {
            if (is_lazy_sweeping(objspace)) {
                status = "S";
            }
            if (is_incremental_marking(objspace)) {
                status = "M";
            }
        }

        va_start(args, fmt);
        vsnprintf(buf, 1024, fmt, args);
        va_end(args);

        fprintf(out, "%s|", status);
        fputs(buf, out);
    }
}

/* bit operations */

static int
rgengc_remembersetbits_set(rb_objspace_t *objspace, VALUE obj)
{
    struct heap_page *page = GET_HEAP_PAGE(obj);
    bits_t *bits = &page->remembered_bits[0];

    /* atomic。lock-free write barrier は任意の Ractor スレッドから、所有者の GC や同じ word の
     * 他 writer と並行して shareable を remember する。bit を先に立ててからページフラグを立てる。
     * これにより、bit を drain する前にフラグを消す並行 rgengc_rememberset_mark は、remember
     * 直後のオブジェクトを飛ばさずページを再走査対象として残す。 */
    const bool newly = gc_bitmap_atomic_set(bits, page, obj);
    page->flags.has_remembered_objects = TRUE;
    return newly ? TRUE : FALSE;
}

/* wb, etc */

/* return FALSE if already remembered */
static int
rgengc_remember(rb_objspace_t *objspace, VALUE obj)
{
    gc_report(6, objspace, "rgengc_remember: %s %s\n", rb_obj_info(obj),
              RVALUE_REMEMBERED(objspace, obj) ? "was already remembered" : "is remembered now");

    check_rvalue_consistency(objspace, obj);

    if (RGENGC_CHECK_MODE) {
        if (RVALUE_WB_UNPROTECTED(objspace, obj)) rb_bug("rgengc_remember: %s is not wb protected.", rb_obj_info(obj));
    }

#if RGENGC_PROFILE > 0
    if (!RVALUE_REMEMBERED(objspace, obj)) {
        if (RVALUE_WB_UNPROTECTED(objspace, obj) == 0) {
            objspace->profile.total_remembered_normal_object_count++;
#if RGENGC_PROFILE >= 2
            objspace->profile.remembered_normal_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
        }
    }
#endif /* RGENGC_PROFILE > 0 */

    return rgengc_remembersetbits_set(objspace, obj);
}

#ifndef PROFILE_REMEMBERSET_MARK
#define PROFILE_REMEMBERSET_MARK 0
#endif

static inline void
rgengc_rememberset_mark_plane(rb_objspace_t *objspace, uintptr_t p, bits_t bitset, short slot_size)
{
    if (bitset) {
        do {
            if (bitset & 1) {
                VALUE obj = (VALUE)p;
                gc_report(2, objspace, "rgengc_rememberset_mark: mark %s\n", rb_obj_info(obj));
                GC_ASSERT(RVALUE_UNCOLLECTIBLE(objspace, obj));
                GC_ASSERT(RVALUE_OLD_P(objspace, obj) || RVALUE_WB_UNPROTECTED(objspace, obj));

                gc_mark_children(objspace, obj);

                if (RB_FL_TEST_RAW(obj, RUBY_FL_WEAK_REFERENCE)) {
                    rb_darray_append_without_gc(&objspace->weak_references, obj);
                }
            }
            p += slot_size;
            bitset >>= 1;
        } while (bitset);
    }
}

static void
rgengc_rememberset_mark(rb_objspace_t *objspace, rb_heap_t *heap)
{
    size_t j;
    struct heap_page *page = 0;
#if PROFILE_REMEMBERSET_MARK
    int has_old = 0, has_shady = 0, has_both = 0, skip = 0;
#endif
    gc_report(1, objspace, "rgengc_rememberset_mark: start\n");

    ccan_list_for_each(&heap->pages, page, page_node) {
        if (page->flags.has_remembered_objects | page->flags.has_uncollectible_wb_unprotected_objects) {
            uintptr_t p = page->start;
            short slot_size = page->slot_size;
            int total_slots = page->total_slots;
            int bitmap_plane_count = CEILDIV(total_slots, BITS_BITLENGTH);
            bits_t bitset, bits[HEAP_PAGE_BITMAP_LIMIT];
            bits_t *remembered_bits = page->remembered_bits;
            bits_t *uncollectible_bits = page->uncollectible_bits;
            bits_t *wb_unprotected_bits = page->wb_unprotected_bits;
#if PROFILE_REMEMBERSET_MARK
            if (page->flags.has_remembered_objects && page->flags.has_uncollectible_wb_unprotected_objects) has_both++;
            else if (page->flags.has_remembered_objects) has_old++;
            else if (page->flags.has_uncollectible_wb_unprotected_objects) has_shady++;
#endif
            /* bit を drain する前に has_remembered_objects を消す。並行する lock-free write
             * barrier（他 Ractor がこのページの shareable を remember）は bit を先に、フラグを後に
             * 立てるので、先にフラグを消せば、その set が割り込んでもページを再走査対象に残せる。
             * word ごとの drain は atomic な読み取り兼クリアなので、割り込んだ set は失われない
             * （0 化された word に着く）。 */
            page->flags.has_remembered_objects = FALSE;
            for (j=0; j < (size_t)bitmap_plane_count; j++) {
                bits[j] = RUBY_ATOMIC_SIZE_EXCHANGE(*(volatile size_t *)&remembered_bits[j], 0)
                          | (uncollectible_bits[j] & wb_unprotected_bits[j]);
            }

            for (j=0; j < (size_t)bitmap_plane_count; j++) {
                bitset = bits[j];
                rgengc_rememberset_mark_plane(objspace, p, bitset, slot_size);
                p += BITS_BITLENGTH * slot_size;
            }
        }
#if PROFILE_REMEMBERSET_MARK
        else {
            skip++;
        }
#endif
    }

#if PROFILE_REMEMBERSET_MARK
    fprintf(stderr, "%d\t%d\t%d\t%d\n", has_both, has_old, has_shady, skip);
#endif
    gc_report(1, objspace, "rgengc_rememberset_mark: finished\n");
}

static void
rgengc_mark_and_rememberset_clear(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page = 0;

    ccan_list_for_each(&heap->pages, page, page_node) {
        memset(&page->mark_bits[0],       0, HEAP_PAGE_BITMAP_SIZE);
        memset(&page->uncollectible_bits[0], 0, HEAP_PAGE_BITMAP_SIZE);
        memset(&page->marking_bits[0],    0, HEAP_PAGE_BITMAP_SIZE);
        /* 素の memset は並行 write barrier の remember を失いうるが、他 Ractor のスレッドから
         * remember されうるのは shareable だけで、shareable は remembered bit に関係なく毎回の
         * local mark（rlgc_pinned_roots_mark）で再 mark される。かつこの clear が先立つ major は
         * どのみち全体を再走査する。 */
        memset(&page->remembered_bits[0], 0, HEAP_PAGE_BITMAP_SIZE);
        memset(&page->pinned_bits[0],     0, HEAP_PAGE_BITMAP_SIZE);
        page->flags.has_uncollectible_wb_unprotected_objects = FALSE;
        page->flags.has_remembered_objects = FALSE;
    }
}

/* RGENGC: APIs */

NOINLINE(static void gc_writebarrier_generational(VALUE a, VALUE b, rb_objspace_t *objspace));

static void
gc_writebarrier_generational(VALUE a, VALUE b, rb_objspace_t *objspace)
{
    if (RGENGC_CHECK_MODE) {
        if (!RVALUE_OLD_P(objspace, a)) rb_bug("gc_writebarrier_generational: %s is not an old object.", rb_obj_info(a));
        if ( RVALUE_OLD_P(objspace, b)) rb_bug("gc_writebarrier_generational: %s is an old object.", rb_obj_info(b));
        if (is_incremental_marking(objspace)) rb_bug("gc_writebarrier_generational: called while incremental marking: %s -> %s", rb_obj_info(a), rb_obj_info(b));
    }

    /* a を mark して remember する（既定動作）。
     * lock なし。remembered bit の set は atomic（rgengc_remembersetbits_set）で、並行する
     * local GC や他 Ractor の write barrier が競合しうるのはそこだけ。 */
    if (!RVALUE_REMEMBERED(objspace, a)) {
        rgengc_remember(objspace, a);

        gc_report(1, objspace, "gc_writebarrier_generational: %s (remembered) -> %s\n", rb_obj_info(a), rb_obj_info(b));
    }

    check_rvalue_consistency(objspace, a);
    check_rvalue_consistency(objspace, b);
}

static void
gc_mark_from(rb_objspace_t *objspace, VALUE obj, VALUE parent)
{
    gc_mark_set_parent(objspace, parent);
    rgengc_check_relation(objspace, obj);
    if (gc_mark_set(objspace, obj) != FALSE) {
        gc_aging(objspace, obj);
        gc_grey(objspace, obj);
    }
    gc_mark_set_parent_invalid(objspace);
}

NOINLINE(static void gc_writebarrier_incremental(VALUE a, VALUE b, rb_objspace_t *objspace));

static void
gc_writebarrier_incremental(VALUE a, VALUE b, rb_objspace_t *objspace)
{
    gc_report(2, objspace, "gc_writebarrier_incremental: [LG] %p -> %s\n", (void *)a, rb_obj_info(b));

    if (RVALUE_BLACK_P(objspace, a)) {
        if (RVALUE_WHITE_P(objspace, b)) {
            if (!RVALUE_WB_UNPROTECTED(objspace, a)) {
                gc_report(2, objspace, "gc_writebarrier_incremental: [IN] %p -> %s\n", (void *)a, rb_obj_info(b));
                gc_mark_from(objspace, b, a);
            }
        }
        else if (RVALUE_OLD_P(objspace, a) && !RVALUE_OLD_P(objspace, b)) {
            rgengc_remember(objspace, a);
        }

        if (RB_UNLIKELY(objspace->flags.during_compacting)) {
            MARK_IN_BITMAP(GET_HEAP_PINNED_BITS(b), b);
        }
    }
}

void
rb_gc_impl_writebarrier(void *objspace_ptr, VALUE a, VALUE b)
{
    rb_objspace_t *objspace = objspace_ptr;

#if RGENGC_CHECK_MODE
    if (SPECIAL_CONST_P(a)) rb_bug("rb_gc_writebarrier: a is special const: %"PRIxVALUE, a);
    if (SPECIAL_CONST_P(b)) rb_bug("rb_gc_writebarrier: b is special const: %"PRIxVALUE, b);
#else
    RBIMPL_ASSERT_OR_ASSUME(!SPECIAL_CONST_P(a));
    RBIMPL_ASSERT_OR_ASSUME(!SPECIAL_CONST_P(b));
#endif

    GC_ASSERT(!during_gc);
    GC_ASSERT(RB_BUILTIN_TYPE(a) != T_NONE);
    GC_ASSERT(RB_BUILTIN_TYPE(a) != T_MOVED);
    GC_ASSERT(RB_BUILTIN_TYPE(a) != T_ZOMBIE);
    GC_ASSERT(RB_BUILTIN_TYPE(b) != T_NONE);
    GC_ASSERT(RB_BUILTIN_TYPE(b) != T_MOVED);
    GC_ASSERT(RB_BUILTIN_TYPE(b) != T_ZOMBIE);

    /* shareable が unshareable を参照した。b を shref として記録し、所有者の local GC が
     * root 扱いするようにする（parent は他 objspace にありうるしそこで traverse されない）。
     * この store は b の所有者しか行えないので b のページは現在の Ractor のもの。素の store。 */
    if (RB_UNLIKELY(RB_FL_TEST_RAW(a, RUBY_FL_SHAREABLE)) &&
            !RB_FL_TEST_RAW(b, RUBY_FL_SHAREABLE)) {
        struct heap_page *bpage = GET_HEAP_PAGE(b);
        if (!_MARKED_IN_BITMAP(bpage->shref_bits, bpage, b)) {
            _MARK_IN_BITMAP(bpage->shref_bits, bpage, b);
            bpage->has_shref_objects = TRUE;
        }
    }

  retry:
    if (!is_incremental_marking(objspace)) {
        /* 世代間 barrier は同一 objspace の old->young エッジだけが対象。foreign な a/b の old bit は
         * 他 objspace 所有で並行変更され読むのが危険なので、multi-Ractor 時のみ locality を先に検査する
         * (foreign な a は shareable で shref が既に b を生かすため remember は不要)。単一 Ractor は foreign 無し。 */
        if ((rb_multi_ractor_p() &&
                (GET_HEAP_OBJSPACE(a) != objspace || GET_HEAP_OBJSPACE(b) != objspace)) ||
                !RVALUE_OLD_P(objspace, a) || RVALUE_OLD_P(objspace, b)) {
            // do nothing
        }
        else {
            gc_writebarrier_generational(a, b, objspace);
        }
    }
    else {
        /* slow path。lock なし。incremental marking はプロセスが単一 objspace の間しか走らない
         * （multi-objspace では無効）ので、所有 Ractor の GVL が既にこの barrier を自身の GC に
         * 対して直列化している。 */
        if (is_incremental_marking(objspace)) {
            gc_writebarrier_incremental(a, b, objspace);
        }
        else {
            goto retry;
        }
    }
    return;
}

void
rb_gc_impl_obj_became_shareable(void *objspace_ptr, VALUE obj)
{
    /* オブジェクトが shareable になるのは所有者スレッド上なので、このページ更新は
     * single-writer。 */
    struct heap_page *page = GET_HEAP_PAGE(obj);
    if (_MARKED_IN_BITMAP(page->shareable_bits, page, obj)) return;
    _MARK_IN_BITMAP(page->shareable_bits, page, obj);
    page->has_shareable_objects = TRUE;
    page->objspace->rlgc.shareable_objects++;

    /* unshareable だった頃の shref 記録はもう不要（shareable pin が覆う）。shref は
     * unshareable しか指さない。shref の writer も所有者スレッドなので素の clear でよい。 */
    if (_MARKED_IN_BITMAP(page->shref_bits, page, obj)) {
        _CLEAR_IN_BITMAP(page->shref_bits, page, obj);
    }
}

void
rb_gc_impl_pin_in_flight_message(void *objspace_ptr, VALUE obj)
{
    if (RB_FL_TEST_RAW(obj, RUBY_FL_SHAREABLE)) return; /* pinned anyway */

    /* payload のページは送信側が所有するので素の store でよい。 */
    struct heap_page *page = GET_HEAP_PAGE(obj);
    if (!_MARKED_IN_BITMAP(page->shref_bits, page, obj)) {
        _MARK_IN_BITMAP(page->shref_bits, page, obj);
        page->has_shref_objects = TRUE;
    }
}

void
rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    /* shareable は決して WB-unprotect されない。shref 維持は s->u の全 store が write barrier を
     * 通ることに依存し、これで wb_unprotected_bits は single-writer に保たれる（所有者スレッド
     * だけが自分の unshareable を unprotect できる）。 */
    GC_ASSERT(!RB_FL_TEST_RAW(obj, RUBY_FL_SHAREABLE));

    if (RVALUE_WB_UNPROTECTED(objspace, obj)) {
        return;
    }
    else {
        gc_report(2, objspace, "rb_gc_writebarrier_unprotect: %s %s\n", rb_obj_info(obj),
                  RVALUE_REMEMBERED(objspace, obj) ? " (already remembered)" : "");

        /* lock なし。上の assert により obj は現在の Ractor の unshareable なので、ここで触る
         * bit（wb_unprotected, uncollectible, age）はすべて所有ページ上で single-writer。
         * RVALUE_DEMOTE 内の remembered bit clear は word を共有する foreign writer に対し atomic。 */
        if (RVALUE_OLD_P(objspace, obj)) {
            gc_report(1, objspace, "rb_gc_writebarrier_unprotect: %s\n", rb_obj_info(obj));
            RVALUE_DEMOTE(objspace, obj);
            gc_mark_set(objspace, obj);
            gc_remember_unprotected(objspace, obj);

#if RGENGC_PROFILE
            objspace->profile.total_shade_operation_count++;
#if RGENGC_PROFILE >= 2
            objspace->profile.shade_operation_count_types[BUILTIN_TYPE(obj)]++;
#endif /* RGENGC_PROFILE >= 2 */
#endif /* RGENGC_PROFILE */
        }
        else {
            RVALUE_AGE_RESET(obj);
        }

        RB_DEBUG_COUNTER_INC(obj_wb_unprotect);
        MARK_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(obj), obj);
    }
}

void
rb_gc_impl_copy_attributes(void *objspace_ptr, VALUE dest, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (RVALUE_WB_UNPROTECTED(objspace, obj)) {
        rb_gc_impl_writebarrier_unprotect(objspace, dest);
    }
    rb_gc_impl_copy_finalizer(objspace, dest, obj);
}

const char *
rb_gc_impl_active_gc_name(void)
{
    return "default";
}

void
rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    gc_report(1, objspace, "rb_gc_writebarrier_remember: %s\n", rb_obj_info(obj));

    /* lock なし。理由は rb_gc_impl_writebarrier と同じ。remember は atomic な bitmap set で、
     * incremental 分岐は単一 objspace でしか走らず Ractor の GVL が自身の GC に対し直列化する。 */
    if (is_incremental_marking(objspace)) {
        if (RVALUE_BLACK_P(objspace, obj)) {
            gc_grey(objspace, obj);
        }
    }
    else if (RVALUE_OLD_P(objspace, obj)) {
        rgengc_remember(objspace, obj);
    }
}

struct rb_gc_object_metadata_names {
    // Must be ID only
    ID ID_wb_protected, ID_age, ID_old, ID_uncollectible, ID_marking,
        ID_marked, ID_pinned, ID_remembered, ID_object_id, ID_shareable;
};

#define RB_GC_OBJECT_METADATA_ENTRY_COUNT (sizeof(struct rb_gc_object_metadata_names) / sizeof(ID))
static struct rb_gc_object_metadata_entry object_metadata_entries[RB_GC_OBJECT_METADATA_ENTRY_COUNT + 1];

struct rb_gc_object_metadata_entry *
rb_gc_impl_object_metadata(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;
    size_t n = 0;
    static struct rb_gc_object_metadata_names names;

    if (!names.ID_marked) {
#define I(s) names.ID_##s = rb_intern(#s)
        I(wb_protected);
        I(age);
        I(old);
        I(uncollectible);
        I(marking);
        I(marked);
        I(pinned);
        I(remembered);
        I(object_id);
        I(shareable);
#undef I
    }

#define SET_ENTRY(na, v) do { \
    GC_ASSERT(n <= RB_GC_OBJECT_METADATA_ENTRY_COUNT); \
    object_metadata_entries[n].name = names.ID_##na; \
    object_metadata_entries[n].val = v; \
    n++; \
} while (0)

    if (!RVALUE_WB_UNPROTECTED(objspace, obj)) SET_ENTRY(wb_protected, Qtrue);
    SET_ENTRY(age, INT2FIX(RVALUE_AGE_GET(obj)));
    if (RVALUE_OLD_P(objspace, obj)) SET_ENTRY(old, Qtrue);
    if (RVALUE_UNCOLLECTIBLE(objspace, obj)) SET_ENTRY(uncollectible, Qtrue);
    if (RVALUE_MARKING(objspace, obj)) SET_ENTRY(marking, Qtrue);
    if (RVALUE_MARKED(objspace, obj)) SET_ENTRY(marked, Qtrue);
    if (RVALUE_PINNED(objspace, obj)) SET_ENTRY(pinned, Qtrue);
    if (RVALUE_REMEMBERED(objspace, obj)) SET_ENTRY(remembered, Qtrue);
    if (rb_obj_id_p(obj)) SET_ENTRY(object_id, rb_obj_id(obj));
    if (FL_TEST(obj, FL_SHAREABLE)) SET_ENTRY(shareable, Qtrue);

    object_metadata_entries[n].name = 0;
    object_metadata_entries[n].val = 0;
#undef SET_ENTRY

    return object_metadata_entries;
}

void *
rb_gc_impl_ractor_cache_alloc(void *objspace_ptr, void *ractor)
{
    rb_objspace_t *objspace = objspace_ptr;

    /* per-Ractor cache は無い。heap 成長ヒューリスティック用に Ractor 数だけ数え、NULL を返す
     * （gc.c は保持するだけ）。NULL cache の一部 teardown が free 呼び出しを飛ばすためカウントは
     * 過大方向へずれうるが、上限付き r_mul ヒューリスティックにしか使われない。 */
    objspace->live_ractor_cache_count++;

    return NULL;
}

void
rb_gc_impl_ractor_cache_free(void *objspace_ptr, void *cache)
{
    rb_objspace_t *objspace = objspace_ptr;

    GC_ASSERT(cache == NULL);

    /* cache_alloc は生成側 Ractor の objspace（Ractor.new 時の rb_gc_get_objspace()）で走り、
     * cache_free は終了する Ractor 自身の objspace で走る。別 objspace なのでこの per-objspace
     * カウンタは一方でインクリメント、他方でデクリメントされ、ここで underflow しうる
     * （cache_alloc の過大ずれの裏）。
     * 上限付き r_mul ヒューリスティックにしか使わないので assert せず clamp する。 */
    if (objspace->live_ractor_cache_count > 0) {
        objspace->live_ractor_cache_count--;
    }
}

static void
heap_ready_to_gc(rb_objspace_t *objspace, rb_heap_t *heap)
{
    if (!heap->free_pages) {
        if (!heap_page_allocate_and_initialize(objspace, heap)) {
            objspace->heap_pages.allocatable_bytes = HEAP_PAGE_SIZE;
            heap_page_allocate_and_initialize(objspace, heap);
        }
    }
}

static int
ready_to_gc(rb_objspace_t *objspace)
{
    if (rb_gc_gc_disabled_global_p() || dont_gc_val() || during_gc) {
        for (int i = 0; i < HEAP_COUNT; i++) {
            rb_heap_t *heap = &heaps[i];
            heap_ready_to_gc(objspace, heap);
        }
        return FALSE;
    }
    else {
        return TRUE;
    }
}

static void
gc_reset_malloc_info(rb_objspace_t *objspace, bool full_mark)
{
    gc_prof_set_malloc_info(objspace);
    {
        int64_t inc = gc_malloc_counters_increase(objspace, &objspace->malloc_counters.counters);
        gc_malloc_counters_snapshot(objspace, &objspace->malloc_counters.counters);
        size_t old_limit = malloc_limit;

        /* A net-negative `inc` (more freed than malloc'd since last GC) is
         * treated the same as "allocated less than malloc_limit".
         * This matches what we were doing pre-monotonic counters, but is it right? */
        if (inc > 0 && (size_t)inc > malloc_limit) {
            malloc_limit = (size_t)((size_t)inc * gc_params.malloc_limit_growth_factor);
            if (malloc_limit > gc_params.malloc_limit_max) {
                malloc_limit = gc_params.malloc_limit_max;
            }
        }
        else {
            malloc_limit = (size_t)(malloc_limit * 0.98); /* magic number */
            if (malloc_limit < gc_params.malloc_limit_min) {
                malloc_limit = gc_params.malloc_limit_min;
            }
        }

        if (0) {
            if (old_limit != malloc_limit) {
                fprintf(stderr, "[%"PRIuSIZE"] malloc_limit: %"PRIuSIZE" -> %"PRIuSIZE"\n",
                        rb_gc_count(), old_limit, malloc_limit);
            }
            else {
                fprintf(stderr, "[%"PRIuSIZE"] malloc_limit: not changed (%"PRIuSIZE")\n",
                        rb_gc_count(), malloc_limit);
            }
        }
    }

    /* reset oldmalloc info */
#if RGENGC_ESTIMATE_OLDMALLOC
    if (!full_mark) {
        /* Don't snapshot on minor GC: oldmalloc_increase is meant to
         * accumulate across minor GCs and only reset at major GC. */
        int64_t oldmalloc_increase = gc_malloc_counters_increase(objspace, &objspace->malloc_counters.oldcounters);
        if (oldmalloc_increase > 0 &&
            (uint64_t)oldmalloc_increase > objspace->rgengc.oldmalloc_increase_limit) {
            gc_needs_major_flags |= GPR_FLAG_MAJOR_BY_OLDMALLOC;
            objspace->rgengc.oldmalloc_increase_limit =
              (size_t)(objspace->rgengc.oldmalloc_increase_limit * gc_params.oldmalloc_limit_growth_factor);

            if (objspace->rgengc.oldmalloc_increase_limit > gc_params.oldmalloc_limit_max) {
                objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_max;
            }
        }

        if (0) fprintf(stderr, "%"PRIdSIZE"\t%d\t%"PRId64"\t%"PRIuSIZE"\t%"PRIdSIZE"\n",
                       rb_gc_count(),
                       gc_needs_major_flags,
                       oldmalloc_increase,
                       objspace->rgengc.oldmalloc_increase_limit,
                       gc_params.oldmalloc_limit_max);
    }
    else {
        gc_malloc_counters_snapshot(objspace, &objspace->malloc_counters.oldcounters);

        if ((objspace->profile.latest_gc_info & GPR_FLAG_MAJOR_BY_OLDMALLOC) == 0) {
            objspace->rgengc.oldmalloc_increase_limit =
              (size_t)(objspace->rgengc.oldmalloc_increase_limit / ((gc_params.oldmalloc_limit_growth_factor - 1)/10 + 1));
            if (objspace->rgengc.oldmalloc_increase_limit < gc_params.oldmalloc_limit_min) {
                objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_min;
            }
        }
    }
#endif
}

static void rlgc_global_gc(rb_objspace_t *driver, bool compact);

/* この回収は global でなければならないか。local GC は shareable も zombie objspace も回収
 * できないので、それらが限界を超えたら global GC だけが前進する。入力はすべてこの objspace
 * 自身のもの。 */
static bool
rlgc_global_wanted_p(rb_objspace_t *objspace)
{
    if (rb_gc_single_objspace_p()) return false;
    if (objspace->rlgc.shareable_objects > objspace->rlgc.shareable_objects_limit) return true;
    /* zombie は heap ページを保持する。global サイクルはその garbage を回収し、disown された
     * ものは merge が shell を回収する。 */
    if (rb_gc_vm_zombie_total_pages() >= RLGC_ZOMBIE_PAGES_TRIGGER) return true;
    /* retention。自分の root から到達不能な shareable（mark 末尾の pin で数える）が、前回の
     * global サイクルの survivor 数（shareable_objects_limit = survivors x 2, floor 付き）の
     * 規模まで溜まった。 */
    if (objspace->rlgc.stalled_shareables > objspace->rlgc.shareable_objects_limit / 2) return true;
    return false;
}

static int
garbage_collect(rb_objspace_t *objspace, unsigned int reason)
{
    int ret;

    /* 外側の VM lock は取らない。gc_enter が各経路に必要なものを取る（非 main の local GC は
     * 無し、main は no-barrier VM lock、global サイクルは lock + barrier）。2 つの Ractor が同時に
     * global GC を選んでも 2 サイクルが連続で走るだけで、2 回目は無駄仕事であって誤りではない。 */
#if GC_PROFILE_MORE_DETAIL
    objspace->profile.prepare_time = getrusage_time();
#endif

    gc_rest(objspace);

#if GC_PROFILE_MORE_DETAIL
    objspace->profile.prepare_time = getrusage_time() - objspace->profile.prepare_time;
#endif

    /* global か local かの判定は、全入口（割り当て slow path も含む）が通る唯一の地点である
     * gc_start の先頭に置く。 */
    ret = gc_start(objspace, reason);

    return ret;
}

static int
gc_start(rb_objspace_t *objspace, unsigned int reason)
{
    unsigned int do_full_mark = !!(reason & GPR_FLAG_FULL_MARK);

    if (!rb_darray_size(objspace->heap_pages.sorted)) return TRUE; /* heap is not ready */
    if (!(reason & GPR_FLAG_METHOD) && !ready_to_gc(objspace)) return TRUE; /* GC is not allowed */

    /* すべての local GC 入口が、代わりに global サイクルが要るかを問う。garbage_collect を
     * 通らず直接 gc_start に来る割り当て slow path も含む。dead shareable / 滞留 retention /
     * zombie ページを回収できるのは global サイクルだけで、明示・malloc 起因の GC だけで
     * 判定すると割り当て駆動のワークロードが全閾値をすり抜けてしまう。 */
    if (rlgc_global_wanted_p(objspace)) {
        rlgc_global_gc(objspace, false);
        return TRUE;
    }

    rb_gc_initialize_vm_context(&objspace->vm_context);

    GC_ASSERT(gc_mode(objspace) == gc_mode_none, "gc_mode is %s\n", gc_mode_name(gc_mode(objspace)));
    GC_ASSERT(!is_lazy_sweeping(objspace));
    GC_ASSERT(!is_incremental_marking(objspace));

    /* reason may be clobbered, later, so keep set immediate_sweep here */
    objspace->flags.immediate_sweep = !!(reason & GPR_FLAG_IMMEDIATE_SWEEP);

    if (ruby_gc_stressful) {
        int flag = FIXNUM_P(ruby_gc_stress_mode) ? FIX2INT(ruby_gc_stress_mode) : 0;

        if ((flag & (1 << gc_stress_no_major)) == 0) {
            do_full_mark = TRUE;
        }

        objspace->flags.immediate_sweep = !(flag & (1<<gc_stress_no_immediate_sweep));
    }

    if (gc_needs_major_flags) {
        reason |= gc_needs_major_flags;
        do_full_mark = TRUE;
    }

    /* if major gc has been disabled, never do a full mark */
    if (!gc_config_full_mark_val) {
        do_full_mark = FALSE;
    }
    gc_needs_major_flags = GPR_FLAG_NONE;

    if (do_full_mark && (reason & GPR_FLAG_MAJOR_MASK) == 0) {
        reason |= GPR_FLAG_MAJOR_BY_FORCE; /* GC by CAPI, METHOD, and so on. */
    }

    if (objspace->flags.dont_incremental ||
            reason & GPR_FLAG_IMMEDIATE_MARK ||
            ruby_gc_stressful ||
            /* 複数 objspace がある間は incremental marking をしない。incremental step の
             * 合間に、この objspace の root 走査が通り過ぎた後で他 Ractor がオブジェクトを
             * 生成・共有しうるため。 */
            !rb_gc_single_objspace_p()) {
        objspace->flags.during_incremental_marking = FALSE;
    }
    else {
        objspace->flags.during_incremental_marking = do_full_mark;
    }

    /* 明示的な compaction 有効化（GC.compact）。
     * compaction はオブジェクトを動かすので、per-Ractor objspace（cross-objspace 参照、
     * shareable 不動の不変条件、ページ常駐 bitmap）と相容れない。単一 objspace でのみ走る。 */
    if (do_full_mark && ruby_enable_autocompact && rb_gc_single_objspace_p()) {
        objspace->flags.during_compacting = TRUE;
#if RGENGC_CHECK_MODE
        objspace->rcompactor.compare_func = ruby_autocompact_compare_func;
#endif
    }
    else {
        objspace->flags.during_compacting = !!(reason & GPR_FLAG_COMPACT);
    }

    if (!GC_ENABLE_LAZY_SWEEP || objspace->flags.dont_incremental) {
        objspace->flags.immediate_sweep = TRUE;
    }

    if (objspace->flags.immediate_sweep) reason |= GPR_FLAG_IMMEDIATE_SWEEP;

    /* during_compacting が決まってから enter する（gc_local_gc_holds_vm_lock が読む）。 */
    unsigned int lock_lev;
    gc_enter(objspace, gc_enter_event_start, &lock_lev);

    gc_report(1, objspace, "gc_start(reason: %x) => %u, %d, %d\n",
              reason,
              do_full_mark, !is_incremental_marking(objspace), objspace->flags.immediate_sweep);

    RB_DEBUG_COUNTER_INC(gc_count);

    if (reason & GPR_FLAG_MAJOR_MASK) {
        (void)RB_DEBUG_COUNTER_INC_IF(gc_major_nofree, reason & GPR_FLAG_MAJOR_BY_NOFREE);
        (void)RB_DEBUG_COUNTER_INC_IF(gc_major_oldgen, reason & GPR_FLAG_MAJOR_BY_OLDGEN);
        (void)RB_DEBUG_COUNTER_INC_IF(gc_major_shady,  reason & GPR_FLAG_MAJOR_BY_SHADY);
        (void)RB_DEBUG_COUNTER_INC_IF(gc_major_force,  reason & GPR_FLAG_MAJOR_BY_FORCE);
#if RGENGC_ESTIMATE_OLDMALLOC
        (void)RB_DEBUG_COUNTER_INC_IF(gc_major_oldmalloc, reason & GPR_FLAG_MAJOR_BY_OLDMALLOC);
#endif
    }
    else {
        (void)RB_DEBUG_COUNTER_INC_IF(gc_minor_newobj, reason & GPR_FLAG_NEWOBJ);
        (void)RB_DEBUG_COUNTER_INC_IF(gc_minor_malloc, reason & GPR_FLAG_MALLOC);
        (void)RB_DEBUG_COUNTER_INC_IF(gc_minor_method, reason & GPR_FLAG_METHOD);
        (void)RB_DEBUG_COUNTER_INC_IF(gc_minor_capi,   reason & GPR_FLAG_CAPI);
        (void)RB_DEBUG_COUNTER_INC_IF(gc_minor_stress, reason & GPR_FLAG_STRESS);
    }

    objspace->profile.count++;
    objspace->profile.latest_gc_info = reason;
    objspace->profile.total_allocated_objects_at_gc_start = total_allocated_objects(objspace);
    objspace->profile.heap_used_at_gc_start = rb_darray_size(objspace->heap_pages.sorted);
    objspace->profile.heap_total_slots_at_gc_start = objspace_available_slots(objspace);
    objspace->profile.weak_references_count = 0;
    gc_prof_setup_new_record(objspace, reason);
    gc_reset_malloc_info(objspace, do_full_mark);

    gc_event_hook_objspace(objspace, RUBY_INTERNAL_EVENT_GC_START);

    GC_ASSERT(during_gc);

    gc_prof_timer_start(objspace);
    {
        if (gc_marks(objspace, do_full_mark)) {
            gc_sweep(objspace);
        }
    }
    gc_prof_timer_stop(objspace);

    gc_exit(objspace, gc_enter_event_start, &lock_lev);

    /* verify は GC の後の独立したステップとして行う（during_gc がクリアされた本物の
     * safepoint）。GC 途中で verify すると GC-safe でなく barrier VM lock を取る
     * rb_objspace_reachable_objects_from を呼び、他 Ractor の global GC barrier に合流して
     * この途中の heap を壊させてしまう。 */
#if RGENGC_CHECK_MODE >= 2
    gc_verify_internal_consistency(objspace);
#endif
    return TRUE;
}

static void
gc_rest(rb_objspace_t *objspace)
{
    if (is_incremental_marking(objspace) || is_lazy_sweeping(objspace)) {
        unsigned int lock_lev;
        gc_enter(objspace, gc_enter_event_rest, &lock_lev);

        if (is_incremental_marking(objspace)) {
            gc_marking_enter(objspace);
            gc_marks_rest(objspace);
            gc_marking_exit(objspace);

            gc_sweep(objspace);
        }

        if (is_lazy_sweeping(objspace)) {
            gc_sweeping_enter(objspace);
            gc_sweep_rest(objspace);
            gc_sweeping_exit(objspace);
        }

        gc_exit(objspace, gc_enter_event_rest, &lock_lev);

        if (RGENGC_CHECK_MODE >= 2) gc_verify_internal_consistency(objspace); /* after GC, see gc_start */
    }
}

struct objspace_and_reason {
    rb_objspace_t *objspace;
    unsigned int reason;
};

static void
gc_current_status_fill(rb_objspace_t *objspace, char *buff)
{
    int i = 0;
    if (is_marking(objspace)) {
        buff[i++] = 'M';
        if (is_full_marking(objspace))        buff[i++] = 'F';
        if (is_incremental_marking(objspace)) buff[i++] = 'I';
    }
    else if (is_sweeping(objspace)) {
        buff[i++] = 'S';
        if (is_lazy_sweeping(objspace))      buff[i++] = 'L';
    }
    else {
        buff[i++] = 'N';
    }
    buff[i] = '\0';
}

static const char *
gc_current_status(rb_objspace_t *objspace)
{
    static char buff[0x10];
    gc_current_status_fill(objspace, buff);
    return buff;
}

#if PRINT_ENTER_EXIT_TICK

static tick_t last_exit_tick;
static tick_t enter_tick;
static int enter_count = 0;
static char last_gc_status[0x10];

static inline void
gc_record(rb_objspace_t *objspace, int direction, const char *event)
{
    if (direction == 0) { /* enter */
        enter_count++;
        enter_tick = tick();
        gc_current_status_fill(objspace, last_gc_status);
    }
    else { /* exit */
        tick_t exit_tick = tick();
        char current_gc_status[0x10];
        gc_current_status_fill(objspace, current_gc_status);
#if 1
        /* [last mutator time] [gc time] [event] */
        fprintf(stderr, "%"PRItick"\t%"PRItick"\t%s\t[%s->%s|%c]\n",
                enter_tick - last_exit_tick,
                exit_tick - enter_tick,
                event,
                last_gc_status, current_gc_status,
                (objspace->profile.latest_gc_info & GPR_FLAG_MAJOR_MASK) ? '+' : '-');
        last_exit_tick = exit_tick;
#else
        /* [enter_tick] [gc time] [event] */
        fprintf(stderr, "%"PRItick"\t%"PRItick"\t%s\t[%s->%s|%c]\n",
                enter_tick,
                exit_tick - enter_tick,
                event,
                last_gc_status, current_gc_status,
                (objspace->profile.latest_gc_info & GPR_FLAG_MAJOR_MASK) ? '+' : '-');
#endif
    }
}
#else /* PRINT_ENTER_EXIT_TICK */
static inline void
gc_record(rb_objspace_t *objspace, int direction, const char *event)
{
    /* null */
}
#endif /* PRINT_ENTER_EXIT_TICK */

static const char *
gc_enter_event_cstr(enum gc_enter_event event)
{
    switch (event) {
      case gc_enter_event_start: return "start";
      case gc_enter_event_continue: return "continue";
      case gc_enter_event_rest: return "rest";
      case gc_enter_event_finalizer: return "finalizer";
      case gc_enter_event_global: return "global";
    }
    return NULL;
}

static void
gc_enter_count(enum gc_enter_event event)
{
    switch (event) {
      case gc_enter_event_start:          RB_DEBUG_COUNTER_INC(gc_enter_start); break;
      case gc_enter_event_continue:       RB_DEBUG_COUNTER_INC(gc_enter_continue); break;
      case gc_enter_event_rest:           RB_DEBUG_COUNTER_INC(gc_enter_rest); break;
      case gc_enter_event_finalizer:      RB_DEBUG_COUNTER_INC(gc_enter_finalizer); break;
      case gc_enter_event_global:         RB_DEBUG_COUNTER_INC(gc_enter_start); break;
    }
}

static bool current_process_time(struct timespec *ts);

static void
gc_clock_start(struct timespec *ts)
{
    if (!current_process_time(ts)) {
        ts->tv_sec = 0;
        ts->tv_nsec = 0;
    }
}

static unsigned long long
gc_clock_end(struct timespec *ts)
{
    struct timespec end_time;

    if ((ts->tv_sec > 0 || ts->tv_nsec > 0) &&
            current_process_time(&end_time) &&
            end_time.tv_sec >= ts->tv_sec) {
        return (unsigned long long)(end_time.tv_sec - ts->tv_sec) * (1000 * 1000 * 1000) +
                    (end_time.tv_nsec - ts->tv_nsec);
    }

    return 0;
}

/* 非 global の local GC が実行の間じゅう no-barrier VM lock を保持するか。main の通常 local GC は
 * lock-free で、main の compaction か JIT 有効時だけ保持する（理由は本体コメント参照）。 */
static inline bool
gc_local_gc_holds_vm_lock(const rb_objspace_t *objspace)
{
    /* main の local GC は gc_enter レベルでは lock-free。VM グローバル weak table を触る有界な
     * 窓（mark 内の rb_vm_mark 共有表、sweep 内の rb_gc_obj_free_vm_weak_references）でのみ
     * no-barrier VM lock を取る。compaction は gc_enter で別途 barrier lock を取る。ここでは
     * JIT 有効時に GC 全体で lock を保持する。一般 mark が shareable iseq の payload で
     * rb_yjit_iseq_mark / rb_zjit_iseq_mark に届き、他 Ractor の並行 JIT コンパイルから排他する
     * 必要があるため（rb_iseq_mark_and_move がそこで VM lock を assert する）。 */
    return objspace == rlgc_main_objspace &&
           (objspace->flags.during_compacting || rb_yjit_enabled_p || rb_zjit_enabled_p);
}

static inline void
gc_enter(rb_objspace_t *objspace, enum gc_enter_event event, unsigned int *lock_lev)
{
    /* local GC は所有者スレッドで走り、VM lock も barrier も取らない。containment により heap は
     * single-writer で、cross-objspace の bitmap 書き込みは atomic。例外は 2 つ。
     *
     * - global GC は world を止める（VM lock + barrier）。GC には safepoint が無く、スレッドは
     *   gc_exit 後にしか合流しないので、barrier は暗黙に全 in-flight local GC を待つ。
     * - main objspace の local GC は VM lock 下で変更される VM グローバル root（rb_vm_mark）も
     *   歩くので、barrier を上げずに lock を取る。非 main はそのまま走る。ここで VM lock を待つ
     *   スレッドは自身の GC 開始「前」に保留中の global barrier へ合流し、途中では合流しない。
     *
     * 従って GC の内部では VM lock を取ってはならない。待ち手が GC 途中で保留 barrier に合流し、
     * 途中の heap を global GC に晒すため。GC 経路が触る共有構造は独自の native mutex（id2ref、
     * registered globals、generic fields）か page-pool lock を使う。
     *
     * RGENGC_CHECK_MODE では非 main の local GC も no-barrier VM lock を取る
     * （gc_local_gc_holds_vm_lock）。mid-collection verify が全 objspace を反復し
     * （rb_gc_vm_each_objspace が lock を要する）、GC 全体で lock を保持することで global GC の
     * 割り込みとこの objspace の during_gc の mark 途中クリアを防ぐ。lock は safepoint で取り
     * 途中では取らないので保留 barrier に途中合流しない。production（CHECK_MODE off）は
     * lock-free のまま。 */
    *lock_lev = 0;

    RUBY_DTRACE_GC_HOOK(ENTER, event);

    if (objspace->profile.run) {
        switch (event) {
          case gc_enter_event_start:
          case gc_enter_event_continue:
          case gc_enter_event_rest:
            objspace->profile.gc_pause_start_time = rb_hrtime_now();
            break;
          case gc_enter_event_finalizer:
          case gc_enter_event_global:
            break;
        }
    }
    switch (event) {
      case gc_enter_event_global:
        *lock_lev = RB_GC_VM_LOCK();
        // stop other ractors
        rb_gc_vm_barrier();
        break;
      case gc_enter_event_finalizer:
        /* shutdown finalizer は VM グローバル表（fstring/symbol）を読み thread-safe でない
         * T_DATA を free するので、no-barrier VM lock を取る。 */
        *lock_lev = RB_GC_VM_LOCK_NO_BARRIER();
        break;
      default:
        objspace->flags.gc_lock_barrier = FALSE;
        if (objspace->flags.during_compacting) {
            /* compaction はオブジェクトを再配置し全 Ractor の JIT / グローバル参照を書き換える
             * ので world を止める。barrier VM lock を取る。rb_gc_vm_barrier は単一 Ractor では
             * no-op かつ再入可能なので、move 中の内側 barrier 要求はこれに畳まれ gc_exit が終える。 */
            *lock_lev = RB_GC_VM_LOCK();
            rb_gc_vm_barrier();
            objspace->flags.gc_lock_barrier = TRUE;
        }
        else if (gc_local_gc_holds_vm_lock(objspace)) {
            *lock_lev = RB_GC_VM_LOCK_NO_BARRIER();
        }
        break;
    }

    if (objspace->profile.gc_pause_start_time) {
        objspace->profile.gc_stw_start_time = rb_hrtime_now();
        objspace->profile.gc_stop_time = rb_hrtime_sub(
                objspace->profile.gc_stw_start_time,
                objspace->profile.gc_pause_start_time);
    }

    gc_enter_count(event);
    if (RB_UNLIKELY(during_gc != 0)) rb_bug("during_gc != 0");
    if (RGENGC_CHECK_MODE >= 3) gc_verify_internal_consistency(objspace);

    during_gc = TRUE;
    RUBY_DEBUG_LOG("%s (%s)",gc_enter_event_cstr(event), gc_current_status(objspace));
    gc_report(1, objspace, "gc_enter: %s [%s]\n", gc_enter_event_cstr(event), gc_current_status(objspace));
    gc_record(objspace, 0, gc_enter_event_cstr(event));

    gc_event_hook_objspace(objspace, RUBY_INTERNAL_EVENT_GC_ENTER);
}

static inline void
gc_exit(rb_objspace_t *objspace, enum gc_enter_event event, unsigned int *lock_lev)
{
    GC_ASSERT(during_gc != 0);

    RUBY_DTRACE_GC_HOOK(EXIT, event);

    gc_event_hook_objspace(objspace, RUBY_INTERNAL_EVENT_GC_EXIT);

    if (objspace->profile.gc_pause_start_time) {
        if (gc_prof_enabled(objspace)) {
            rb_hrtime_t now = rb_hrtime_now();
            gc_profile_record *record = gc_prof_record(objspace);
            record->gc_pause_time = rb_hrtime_add(record->gc_pause_time,
                    rb_hrtime_sub(now, objspace->profile.gc_pause_start_time));
            record->gc_stop_time = rb_hrtime_add(record->gc_stop_time,
                    objspace->profile.gc_stop_time);
            record->gc_stw_time = rb_hrtime_add(record->gc_stw_time,
                    rb_hrtime_sub(now, objspace->profile.gc_stw_start_time));
        }
        objspace->profile.gc_pause_start_time = 0;
        objspace->profile.gc_stw_start_time = 0;
        objspace->profile.gc_stop_time = 0;
    }

    gc_record(objspace, 1, gc_enter_event_cstr(event));
    RUBY_DEBUG_LOG("%s (%s)", gc_enter_event_cstr(event), gc_current_status(objspace));
    gc_report(1, objspace, "gc_exit: %s [%s]\n", gc_enter_event_cstr(event), gc_current_status(objspace));
    during_gc = FALSE;

    switch (event) {
      case gc_enter_event_global:
        RB_GC_VM_UNLOCK(*lock_lev);
        break;
      case gc_enter_event_finalizer:
        RB_GC_VM_UNLOCK_NO_BARRIER(*lock_lev);
        break;
      default:
        if (*lock_lev != 0) {
            if (objspace->flags.gc_lock_barrier) {
                objspace->flags.gc_lock_barrier = FALSE;
                RB_GC_VM_UNLOCK(*lock_lev);
            }
            else {
                RB_GC_VM_UNLOCK_NO_BARRIER(*lock_lev);
            }
        }
        break;
    }
}

#ifndef MEASURE_GC
#define MEASURE_GC (objspace->flags.measure_gc)
#endif

static void
gc_marking_enter(rb_objspace_t *objspace)
{
    GC_ASSERT(during_gc != 0);

    gc_prof_mark_timer_start(objspace);

    if (gc_prof_enabled(objspace)) {
        objspace->profile.gc_mark_phase_wall_start_time = rb_hrtime_now();
    }

    if (MEASURE_GC) {
        gc_clock_start(&objspace->profile.marking_start_time);
    }

    rb_gc_initialize_vm_context(&objspace->vm_context);
}

static void
gc_marking_exit(rb_objspace_t *objspace)
{
    GC_ASSERT(during_gc != 0);

    if (MEASURE_GC) {
        objspace->profile.marking_time_ns += gc_clock_end(&objspace->profile.marking_start_time);
    }

    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->gc_mark_wall_time = rb_hrtime_add(record->gc_mark_wall_time,
                elapsed_hrtime_from(objspace->profile.gc_mark_phase_wall_start_time));
    }

    gc_prof_mark_timer_stop(objspace);
}

static void
gc_sweeping_enter(rb_objspace_t *objspace)
{
    GC_ASSERT(during_gc != 0);

    if (gc_prof_enabled(objspace)) {
        objspace->profile.gc_sweep_phase_wall_start_time = rb_hrtime_now();
        objspace->profile.gc_sweep_excluded_wall_time = 0;
    }

    if (MEASURE_GC) {
        gc_clock_start(&objspace->profile.sweeping_start_time);
    }

    rb_gc_initialize_vm_context(&objspace->vm_context);
}

static void
gc_sweeping_exit(rb_objspace_t *objspace)
{
    GC_ASSERT(during_gc != 0);

    if (MEASURE_GC) {
        objspace->profile.sweeping_time_ns += gc_clock_end(&objspace->profile.sweeping_start_time);
    }

    if (gc_prof_enabled(objspace)) {
        rb_hrtime_t sweep_wall_time = elapsed_hrtime_from(objspace->profile.gc_sweep_phase_wall_start_time);
        gc_profile_record *record = gc_prof_record(objspace);
        sweep_wall_time = rb_hrtime_sub(sweep_wall_time,
                objspace->profile.gc_sweep_excluded_wall_time);
        record->gc_sweep_wall_time = rb_hrtime_add(record->gc_sweep_wall_time,
                sweep_wall_time);
        objspace->profile.gc_sweep_excluded_wall_time = 0;
    }
}

static void *
gc_with_gvl(void *ptr)
{
    struct objspace_and_reason *oar = (struct objspace_and_reason *)ptr;
    return (void *)(VALUE)garbage_collect(oar->objspace, oar->reason);
}

int ruby_thread_has_gvl_p(void);

static int
garbage_collect_with_gvl(rb_objspace_t *objspace, unsigned int reason)
{
    if (rb_gc_gc_disabled_global_p() || dont_gc_val()) {
        return TRUE;
    }
    else if (!ruby_native_thread_p()) {
        return TRUE;
    }
    else if (!ruby_thread_has_gvl_p()) {
        void *ret;
        struct objspace_and_reason oar;
        oar.objspace = objspace;
        oar.reason = reason;
        ret = rb_thread_call_with_gvl(gc_with_gvl, (void *)&oar);

        return !!ret;
    }
    else {
        return garbage_collect(objspace, reason);
    }
}

static int
gc_set_candidate_object_i(void *vstart, void *vend, size_t stride, void *data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;

    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        asan_unpoisoning_object(v) {
            switch (BUILTIN_TYPE(v)) {
              case T_NONE:
              case T_ZOMBIE:
                break;
              default:
                rb_gc_prepare_heap_process_object(v);
                if (!RVALUE_OLD_P(objspace, v) && !RVALUE_WB_UNPROTECTED(objspace, v)) {
                    RVALUE_AGE_SET_CANDIDATE(objspace, v);
                }
            }
        }
    }

    return 0;
}

bool
rb_gc_impl_during_global_gc_p(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;
    return objspace->during_global_gc != 0;
}


/* obj が shareable から参照される unshareable として記録されているか。verifier 用で、整合性
 * 検査は write barrier がここに記録したときだけ shareable -> unshareable エッジを許容する。 */
bool
rb_gc_impl_shref_marked_p(void *objspace_ptr, VALUE obj)
{
    return MARKED_IN_BITMAP(GET_HEAP_SHREF_BITS(obj), obj) != 0;
}

/* 現在の heap ページ数（zombie ledger のページ計上に使う）。 */
size_t
rb_gc_impl_heap_page_count(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;
    return rb_darray_size(objspace->heap_pages.sorted);
}

static void
rlgc_global_objspaces_i(void *os, void *data)
{
    if (rlgc_global.count == rlgc_global.capa) {
        size_t new_capa = rlgc_global.capa ? rlgc_global.capa * 2 : 16;
        struct rb_objspace **new_list = realloc(rlgc_global.list, new_capa * sizeof(*new_list));
        if (new_list == NULL) rb_bug("rlgc_global_objspaces_i: realloc failed");
        rlgc_global.list = new_list;
        rlgc_global.capa = new_capa;
    }
    rlgc_global.list[rlgc_global.count++] = os;
}

static void
rlgc_clear_shref_bits(rb_objspace_t *objspace)
{
    for (int i = 0; i < HEAP_COUNT; i++) {
        struct heap_page *page = NULL;
        ccan_list_for_each(&heaps[i].pages, page, page_node) {
            memset(&page->shref_bits[0], 0, HEAP_PAGE_BITMAP_SIZE);
            page->has_shref_objects = FALSE;
        }
    }
}

/* global GC: すべての Ractor を停止させ、全 objspace を 1 つの heap として clear/mark/sweep
 * する。shareable を free でき、cross-objspace な到達可能性を正確に判定できる唯一の collector。 */
/* global GC の generic_fields weak pass。
 * per-Ractor 表（unshareable）と global 表（shareable）に分かれた generic_fields を、
 * unified な mark fixpoint の後・sweep の前に処理する。local GC は per-object の
 * rb_mark_generic_ivar で表を引くが、global GC の driver は GET_RACTOR()≠owner なので
 * per-object 引きが壊れる。そこで global GC では per-object mark を止め
 * （rb_mark_generic_ivar は during_global_gc で即 return する）、ここで全表を舐める。
 * weak-KEY: live(marked) な key の val（fields_obj = strong child）だけを mark し、
 * dead な key の entry は drain する。val の mark が新たな key を live 化しうるので
 * fixpoint まで繰り返す。 */
struct rlgc_genfields_mark_arg {
    rb_objspace_t *objspace;
    bool progress;
};

static int
rlgc_genfields_mark_i(VALUE key, VALUE val, void *arg)
{
    struct rlgc_genfields_mark_arg *a = (struct rlgc_genfields_mark_arg *)arg;
    if (RB_SPECIAL_CONST_P(val) || !RVALUE_MARKED_BITMAP(key)) {
        return ST_CONTINUE;
    }
    /* host(key) を parent にして old(key)→young(val) の世代間エッジを remembered set に
     * 記録する。val が既に mark 済みでも必ず記録する: owner Ractor の保守的マシンスタック
     * 走査（や ec->gen_fields_cache）が生まれたての fields_obj を weak pass より前に parent
     * 無しで mark し得るため、mark 有無で分岐すると key が remember されず、次の minor GC が
     * old key を走査せず young val を取りこぼす（CHECK verifier の "WB miss (O->Y)"）。
     * gc_mark は already-marked の早期 return より前に rgengc_check_relation を呼ぶので、
     * 無条件に呼べば両ケースを被覆する。 */
    bool newly = !RVALUE_MARKED_BITMAP(val);
    gc_mark_set_parent(a->objspace, key);
    gc_mark(a->objspace, val);
    if (newly) a->progress = true;
    return ST_CONTINUE;
}

static bool
rlgc_genfields_dead_p(VALUE key)
{
    return RVALUE_MARKED_BITMAP(key) == 0;
}

static void
rlgc_global_mark_generic_fields(rb_objspace_t *driver)
{
    struct rlgc_genfields_mark_arg arg = { driver, false };
    do {
        arg.progress = false;
        /* 各エントリの mark で parent=key を張る（rlgc_genfields_mark_i）。世代間 WB を
         * 正しく記録するため。foreach 後は gc_mark_stacked_objects_all が自分で per-obj の
         * parent を張るので、その前に parent を invalid に戻しておく（poison 契約）。 */
        rb_gc_vm_generic_fields_mark_foreach(rlgc_genfields_mark_i, &arg);
        gc_mark_set_parent_invalid(driver);
        if (arg.progress) {
            gc_mark_stacked_objects_all(driver);
        }
    } while (arg.progress);

    rb_gc_vm_generic_fields_drain_dead(rlgc_genfields_dead_p);
}

static void
rlgc_global_gc(rb_objspace_t *driver, bool compact)
{
    unsigned int lock_lev;
    gc_enter(driver, gc_enter_event_global, &lock_lev);

    GC_ASSERT(is_mark_stack_empty(&driver->mark_stack));

    /* driver が持つ全 objspace（zombie 含む）のスナップショット。 */
    rlgc_global.count = 0;
    rb_gc_vm_each_objspace(rlgc_global_objspaces_i, NULL);

    /* step 3 で lazy sweep を落ち着かせる前に、全 objspace を global GC 中と印す。その settle は
     * 他 Ractor の objspace の残り garbage を driver スレッドで free するが、foreign オブジェクトの
     * weak 参照 free（rb_free_generic_ivar）は「global GC 進行中」を見て、per-Ractor generic_fields
     * の削除を driver 自身の表に誤って解決せず weak-pass drain へ遅延する必要があるため。 */
    rlgc_global.active = true;
    for (size_t i = 0; i < rlgc_global.count; i++) {
        rlgc_global.list[i]->during_global_gc = 1;
    }

    /* step 3: 全 objspace の lazy sweep を落ち着かせ、下の clear より前に mark bit の意味を
     * 確定させる。（during_gc はローカルの "objspace" に対するマクロ。）objspace が GC 中は
     * rb_gc_get_ec() が objspace->vm_context 経由で解決するので、全員分を初期化する
     * （driver スレッドが全員の phase を走らせる）。 */
    for (size_t i = 0; i < rlgc_global.count; i++) {
        rb_objspace_t *objspace = rlgc_global.list[i];
        /* ここではどの objspace も incremental mark の途中ではありえない。incremental mark は
         * 単一 objspace でしか走らず、単一→複数遷移（vm_insert_ractor0）が落ち着かせる。gray
         * stack がスナップショットを保持したまま step 5 で flag を消すと所有者の GC 状態機械を壊す。 */
        GC_ASSERT(!is_incremental_marking(objspace));
        GC_ASSERT(is_mark_stack_empty(&objspace->mark_stack));
        rb_gc_initialize_vm_context(&objspace->vm_context);
        if (objspace != driver) during_gc = TRUE;
        gc_sweep_rest(objspace);
    }

    /* step 5: 全 objspace の mark / remembered set / 世代カウンタ / shref をクリアする
     * （1 つでも漏らすと stale な mark bit で UAF）。（heaps はローカルの "objspace" のマクロ。） */
    for (size_t i = 0; i < rlgc_global.count; i++) {
        rb_objspace_t *objspace = rlgc_global.list[i];
        objspace->flags.during_minor_gc = FALSE;
        objspace->flags.during_incremental_marking = FALSE;
        /* unified mark は正確で pin しない。下の per-objspace sweep は stale な local サイクルに
         * 対して再チェックしてはならない。 */
        objspace->rlgc.last_cycle_pinned = 0;
        /* stalled_shareables は local サイクルの pinned-roots pass（gc_marks_finish）だけが書く。
         * 一度 retention trigger を踏むと gc_start が全入口を global サイクルへ短絡し、これを下げ
         * うる local pass は二度と走らない。survivor が limit を縮め、stale なカウントが勝ち続け、
         * objspace は永久に STW global GC を回し続ける。この global サイクルが滞留 shareable を
         * 回収/pin するのでカウントを 0 から再開する。 */
        objspace->rlgc.stalled_shareables = 0;
        objspace->rgengc.uncollectible_wb_unprotected_objects = 0;
        objspace->rgengc.old_objects = 0;
        objspace->rgengc.last_major_gc = objspace->profile.count;
        objspace->marked_slots = 0;
        for (int h = 0; h < HEAP_COUNT; h++) {
            rb_heap_t *heap = &heaps[h];
            rgengc_mark_and_rememberset_clear(objspace, heap);
            heap_move_pooled_pages_to_free_pages(heap);
        }
        rlgc_clear_shref_bits(objspace);
    }
    driver->profile.major_gc_count++;

    /* compacting global GC: mark の前に全 objspace で compaction を有効にする。unified な保守的
     * root 走査が各 Ractor のマシンスタック参照先を pin し（gc_pin は during_compacting の間だけ
     * pinned bit を立てる）、step 9 の per-objspace sweep が再配置するように。move 相はそこで
     * 走り、rlgc_global.compacting が参照更新相を下の phase 2 へ遅延する（2 相、cross-objspace 安全）。 */
    rlgc_global.compacting = compact;
    if (compact) {
        for (size_t i = 0; i < rlgc_global.count; i++) {
            rb_objspace_t *objspace = rlgc_global.list[i];
            objspace->flags.during_compacting = TRUE;
            /* gc_marks_start は compacting な local GC 用に各ページの pinned_slots をリセットするが、
             * global GC は gc_marks_start を飛ばすのでここでリセットする。step 5 で pinned_bits は
             * 既にクリア済みで、続く保守的 mark がマシンスタック参照先を再 pin（gc_pin）する。 */
            for (int h = 0; h < HEAP_COUNT; h++) {
                struct heap_page *page = NULL;
                ccan_list_for_each(&heaps[h].pages, page, page_node) {
                    page->pinned_slots = 0;
                }
            }
        }
    }

    /* steps 6-7: 全 Ractor の root（gc.c が全部歩き in-flight payload を再 pin する）、続いて
     * 1 回の unified で正確な mark。 */
    mark_roots(driver, NULL);
    gc_mark_stacked_objects_all(driver);

    /* mark fixpoint の後、generic_fields の weak pass を走らせる。
     * live key の val（fields_obj）を mark（＋その先を drain）し、dead key の entry を
     * drain する。per-object の rb_mark_generic_ivar は global GC 中は no-op なので、
     * ここが唯一の generic_fields の mark 経路である。 */
    rlgc_global_mark_generic_fields(driver);

    /* step 8 */
    gc_update_weak_references(driver);

    /* このサイクルの全 Ractor root pass が削除済みの ractor-local key を各 storage から一掃した。
     * barrier 内のうちに key の struct を解放する（local GC は決してできない。
     * rb_ractor_finish_marking 参照）。 */
    rb_ractor_finish_marking();

    /* step 9: barrier 内で全 objspace を lazy でなく sweep する。dead な shareable はここで回収し、
     * 空きページは pool に戻る。 */
    if (!compact) {
        for (size_t i = 0; i < rlgc_global.count; i++) {
            rb_objspace_t *os = rlgc_global.list[i];
            unsigned int prev_immediate = os->flags.immediate_sweep;
            os->flags.immediate_sweep = TRUE;
            gc_sweep(os);
            os->flags.immediate_sweep = prev_immediate;
        }
    }
    else {
        /* compacting global GC は、単一 objspace の move -> 参照更新 -> free の流れを barrier 下で
         * 全 objspace に一様に適用する。これは per-objspace ではなく全 objspace をまたぐ 3 pass で
         * 走らせねばならない。(a) 参照更新は全 objspace の forwarding を見る必要があり（参照が別
         * objspace の移動済みオブジェクトを指しうる）、(b) ある objspace の移動元ページの free は
         * 全 objspace の更新完了まで待たねばならない（さもないと別 objspace の更新が free 済みの
         * T_MOVED を読む）ため。read barrier は pass 全体で 1 度だけ設置する。 */
        install_handlers();

        /* pass 1 (move): 全 objspace を再配置し T_MOVED forwarding を残す。 */
        for (size_t i = 0; i < rlgc_global.count; i++) {
            rb_objspace_t *os = rlgc_global.list[i];
            gc_sweeping_enter(os);
            gc_sweep_start(os);        /* mode を sweeping へ、compaction 用に heap を整列 */
            gc_compact_relocate(os);   /* mode を compacting へ、move */
        }

        /* pass 2 (update): 全 forwarding pointer が揃ったので全 objspace の参照を更新する
         * （cross-objspace 参照も解決する）。gc_compact_finish はページの unprotect と
         * during_compacting のクリアも行う。move か mark かの判定は rb_gc_get_objspace() の
         * during_reference_updating を読むので、pass 用に全 objspace に立てる。 */
        for (size_t i = 0; i < rlgc_global.count; i++) {
            rlgc_global.list[i]->flags.during_reference_updating = TRUE;
        }
        rb_gc_before_updating_jit_code();
        for (size_t i = 0; i < rlgc_global.count; i++) {
            gc_compact_finish(rlgc_global.list[i]);
        }
        /* 参照更新の VM グローバル / weak-table 側は 1 度だけ走る（各 objspace の heap 側は
         * 上の gc_compact_finish で既に走った）。 */
        gc_update_references_global(driver);
        rb_gc_after_updating_jit_code();
        for (size_t i = 0; i < rlgc_global.count; i++) {
            rlgc_global.list[i]->flags.during_reference_updating = FALSE;
            rlgc_global.list[i]->flags.during_compacting = FALSE;
        }
        rlgc_global.compacting = false;
        uninstall_handlers();

        /* pass 3 (free): 全 objspace を page-sweep し、dead オブジェクトと空になった移動元
         * ページを free する。during_compacting はクリア済みなので sweep は T_MOVED を通常通り
         * 扱う。 */
        for (size_t i = 0; i < rlgc_global.count; i++) {
            rb_objspace_t *os = rlgc_global.list[i];
            gc_sweep_rest(os);
            gc_sweeping_exit(os);
        }
    }
    rlgc_global.compacting = false;

    /* global GC は独自の unified mark+sweep を走らせ、次サイクルの heap 成長予算
     * （allocatable_bytes）を用意する gc_marks_finish を呼ばない。global sweep 後も heap が満杯の
     * objspace（例: 大きな受信コピーを materialize 途中の Ractor で、その live graph を global GC が
     * 回収できない）は free ページも empty ページも無く allocatable_bytes == 0 になり、次の割り当てで
     * newobj_refill の「major GC 後に新ページを作れない」に当たる。ここで詰まった objspace 全てに
     * gc_marks_finish と同様に成長予算を与える。 */
    for (size_t i = 0; i < rlgc_global.count; i++) {
        rb_objspace_t *objspace = rlgc_global.list[i];
        if (objspace->heap_pages.allocatable_bytes != 0 || objspace->empty_pages_count != 0) {
            continue;
        }
        bool stuck = false;
        for (int h = 0; h < HEAP_COUNT; h++) {
            if (heaps[h].free_pages == NULL) { stuck = true; break; }
        }
        if (stuck) {
            heap_allocatable_bytes_expand(objspace, NULL, 0,
                    objspace_available_slots(objspace), heaps[0].slot_size);
        }
    }

    /* 生き残った shareable を数え直し（sweep が既に dead を shareable_bits から畳んだ）、
     * 各 trigger limit をリセットする。 */
    for (size_t i = 0; i < rlgc_global.count; i++) {
        rb_objspace_t *objspace = rlgc_global.list[i];
        size_t survivors = 0;
        for (int h = 0; h < HEAP_COUNT; h++) {
            struct heap_page *page = NULL;
            ccan_list_for_each(&heaps[h].pages, page, page_node) {
                if (!page->has_shareable_objects) continue;
                for (int j = 0; j < HEAP_PAGE_BITMAP_LIMIT; j++) {
                    survivors += rb_popcount_intptr(page->shareable_bits[j]);
                }
            }
        }
        objspace->rlgc.shareable_objects = survivors;
        size_t new_limit = (size_t)(survivors * RLGC_SHAREABLE_LIMIT_FACTOR);
        if (new_limit < RLGC_SHAREABLE_LIMIT_MIN) new_limit = RLGC_SHAREABLE_LIMIT_MIN;
        objspace->rlgc.shareable_objects_limit = new_limit;
    }
    driver->profile.count++;

    /* step 10 */
    for (size_t i = 0; i < rlgc_global.count; i++) {
        rb_objspace_t *objspace = rlgc_global.list[i];
        objspace->during_global_gc = 0;
        if (objspace != driver) during_gc = FALSE;
    }
    rlgc_global.active = false;

    /* garbage が消えた今、zombie ledger を測り直す。barrier 内なのでエントリは安定。これが
     * 無いと、どの pass も merge しない joinable(slotted) zombie の retire 時の stale な数値で
     * 上のページ trigger が発火し続ける。 */
    rb_gc_vm_refresh_zombie_pages();

    /* 上の sweep が未 join の Ractor オブジェクトを回収した場合、ractor_free がその zombie ledger
     * エントリを disown し merge を main Ractor へ postponed job として投げている。objspace は
     * main が次の safepoint で absorb するまで ledger に列挙可能なまま残る。 */

    gc_exit(driver, gc_enter_event_global, &lock_lev);
}

static int
rlgc_absorb_finalizer_i(st_data_t key, st_data_t val, st_data_t data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;
    st_insert(finalizer_table, key, val);
    return ST_CONTINUE;
}

/* 死んだ Ractor の objspace を dst へ併合する。呼び出し元は VM lock を保持し、src はもう所有者
 * スレッドを持たず、dst は呼び出しスレッド自身の objspace（join/value 時の継承）か全員停止中の
 * main（global GC の継承）なので、single-writer 規則が全体で成り立つ。ページは丸ごと移す。その
 * オブジェクト bit はオブジェクトを表し objspace を表さないのでそのまま残り、dst の次回回収は
 * full mark を強制して併合後の世代状態を作り直す。 */
static void
rlgc_objspace_absorb(rb_objspace_t *dst, rb_objspace_t *src)
{
    GC_ASSERT(dst != src);

    /* グラフが流動的な間は cross-objspace verifier 検査を抑止する（rlgc_during_absorb 参照）。 */
    const bool prev_absorb = rlgc_during_absorb;
    rlgc_during_absorb = true;

    /* まず dst を落ち着かせる。lazy sweep カーソルが heap リストを歩いている最中にページを
     * 追加すると、併合ページを src の stale mark bit で sweep して生きたオブジェクトを free
     * してしまう。gc_rest は進行中の incremental mark も完了させる。半 mark の heap にページを
     * 継ぐとそのサイクルの sweep が src の stale bit で走りうる。（通常は既に落ち着いている。
     * vm_insert_ractor0 の単一→複数 settle により、absorb すべき zombie が居る間 incremental な
     * objspace は無い。） */
    gc_rest(dst);

    /* src を落ち着かせる。lazy sweep も進行中の割り当てページも無い状態にする。 */
    {
        rb_objspace_t *objspace = src;
        during_gc = TRUE;
        gc_sweep_rest(objspace);
        during_gc = FALSE;
        heap_alloc_state_clear(objspace);
        /* gc_sweep_finish は sweep 済みページを来るべき incremental mark 用に "pooled" のまま残す
         * （will_be_incremental_marking）。src は incremental mark を走らせない（併合寸前で dst の
         * 次回回収は full 強制）ので、今 src の free リストへ返す。global GC の settle
         * （rlgc_global_gc step 3）と同様で、下のページ併合が前提とする pooled_pages == NULL を
         * 回復する。 */
        for (int h = 0; h < HEAP_COUNT; h++) {
            heap_move_pooled_pages_to_free_pages(&heaps[h]);
        }
    }

    /* ここから先の併合は dst の GC を走らせてはならない。下の finalizer st_insert は dst の表を
     * resize しうるが、st.c の malloc は ruby_xmalloc で、その resize は malloc 計上の閾値を越える。
     * ここで GC が走ると、src の切り離された finalizer エントリがこの C フレームからしか到達不能
     * （未 mark）なうちに走り、未転送の finalizer proc を dangling VALUE へ sweep してしまう。
     * ページ/darray の移動は alloc 無し（_without_gc）なので disable の代償は無く、splice 全体を
     * dst 自身の collector に対し atomic にする。（上の 2 つの settle は意図的に回収を走らせるので
     * この窓の外に置く。） */
    const bool dst_gc_was_enabled = rb_gc_impl_gc_enabled_p(dst);
    if (dst_gc_was_enabled) rb_gc_impl_gc_disable(dst, false);

    /* size pool ごとにページを引き渡す。（"heaps" はローカル objspace のマクロなので、配列は
     * スコープ付きローカル経由で取る。） */
    rb_heap_t *dst_heaps;
    rb_heap_t *src_heaps;
    {
        rb_objspace_t *objspace = dst;
        dst_heaps = heaps;
    }
    {
        rb_objspace_t *objspace = src;
        src_heaps = heaps;
    }
    for (int h = 0; h < HEAP_COUNT; h++) {
        rb_heap_t *dheap = &dst_heaps[h];
        rb_heap_t *sheap = &src_heaps[h];
        struct heap_page *page = NULL;

        GC_ASSERT(sheap->sweeping_page == NULL);
        GC_ASSERT(sheap->pooled_pages == NULL);

        ccan_list_for_each(&sheap->pages, page, page_node) {
            page->objspace = dst;
            page->heap = dheap;
        }
        ccan_list_append_list(&dheap->pages, &sheap->pages);

        /* free ページのチェーンを末尾に連結する。 */
        if (sheap->free_pages) {
            struct heap_page **tail = &dheap->free_pages;
            while (*tail) tail = &(*tail)->free_next;
            *tail = sheap->free_pages;
            sheap->free_pages = NULL;
        }

        dheap->total_pages += sheap->total_pages;
        dheap->total_slots += sheap->total_slots;
        dheap->total_allocated_pages += sheap->total_allocated_pages;
        dheap->total_allocated_objects += sheap->total_allocated_objects;
        dheap->total_freed_objects += sheap->total_freed_objects;
        dheap->final_slots_count += sheap->final_slots_count;
    }

    /* empty ページを再所有して連結する。 */
    for (struct heap_page *page = src->empty_pages; page; page = page->free_next) {
        page->objspace = dst;
    }
    if (src->empty_pages) {
        struct heap_page **tail = &dst->empty_pages;
        while (*tail) tail = &(*tail)->free_next;
        *tail = src->empty_pages;
        dst->empty_pages_count += src->empty_pages_count;
        src->empty_pages = NULL;
        src->empty_pages_count = 0;
    }

    /* objspace 全体のページ管理情報。 */
    {
        rb_objspace_t *objspace = dst; /* for the heap_pages_* macros */
        struct heap_page *page = NULL;
        size_t srcn = rb_darray_size(src->heap_pages.sorted);
        for (size_t i = 0; i < srcn; i++) {
            page = rb_darray_get(src->heap_pages.sorted, i);
            uintptr_t body = (uintptr_t)page->body;
            uintptr_t start = body + sizeof(struct heap_page_header);
            uintptr_t end = body + HEAP_PAGE_SIZE;

            /* 配列はページの body アドレス順を保たねばならない。保守的検索
             * （heap_page_for_ptr）が body 範囲で bsearch し、剥がされた empty ページは
             * start == 0 なので page->start で比較すると順序が崩れ live ページを取りこぼす
             * （すると global GC が登録された root を mark できず sweep してしまう）。 */
            size_t lo = 0;
            size_t hi = rb_darray_size(objspace->heap_pages.sorted);
            while (lo < hi) {
                size_t mid = (lo + hi) / 2;
                struct heap_page *mid_page = rb_darray_get(objspace->heap_pages.sorted, mid);
                if ((uintptr_t)mid_page->body < body) lo = mid + 1;
                else hi = mid;
            }
            rb_darray_insert_without_gc(&objspace->heap_pages.sorted, hi, page);

            if (heap_pages_lomem == 0 || heap_pages_lomem > start) heap_pages_lomem = start;
            if (heap_pages_himem < end) heap_pages_himem = end;
        }
        objspace->heap_pages.allocated_pages += src->heap_pages.allocated_pages;
        objspace->heap_pages.freed_pages += src->heap_pages.freed_pages;
        rb_darray_free_without_gc(src->heap_pages.sorted);
        src->heap_pages.sorted = NULL;
    }

    /* finalizer: 表のエントリを移し、死んだ Ractor の deferred zombie は今後 dst の
     * スレッドが実行する。 */
    {
        st_table *src_finalizers;
        {
            rb_objspace_t *objspace = src;
            src_finalizers = finalizer_table;
            finalizer_table = NULL;
        }
        if (src_finalizers) {
            rb_objspace_t *objspace = dst;
            if (finalizer_table == NULL) {
                finalizer_table = src_finalizers;
            }
            else {
                st_foreach(src_finalizers, rlgc_absorb_finalizer_i, (st_data_t)dst);
                st_free_table(src_finalizers);
            }
        }
    }
    {
        VALUE src_deferred = RUBY_ATOMIC_VALUE_EXCHANGE(src->heap_pages.deferred_final, 0);
        if (src_deferred) {
            VALUE tail_obj = src_deferred;
            while (RZOMBIE(tail_obj)->next) tail_obj = RZOMBIE(tail_obj)->next;
            VALUE prev;
            do {
                prev = dst->heap_pages.deferred_final;
                RZOMBIE(tail_obj)->next = prev;
            } while (RUBY_ATOMIC_VALUE_CAS(dst->heap_pages.deferred_final, prev, src_deferred) != prev);
            /* これらの zombie を実行する所有者が居なかった（register の owner walk は死んだ
             * Ractor を見落とす）。この merge は dst が実行するので dst の job を予約する。
             * さもないと dst の次回 GC まで待つ。 */
            rb_postponed_job_trigger(dst->finalize_deferred_pjob);
        }
    }

    /* dst に引き継ぐカウンタ。 */
    dst->rgengc.old_objects += src->rgengc.old_objects;
    dst->rgengc.uncollectible_wb_unprotected_objects += src->rgengc.uncollectible_wb_unprotected_objects;
    dst->rlgc.shareable_objects += src->rlgc.shareable_objects;

    /* 併合ページは src 基準の mark/age 状態を持つので、dst の世界観は次回回収で作り直す。 */
    dst->rgengc.need_major_gc |= GPR_FLAG_MAJOR_BY_FORCE;

    /* src の未処理 malloc 圧は xmalloc したバッファと共に移る。後の free は dst に計上される
     * ので、この移送が無いと dst は自 heap を過小評価し GC を遅らせる。dst は live なので、
     * gc_counter_add が atomic でない箇所ではそのカウンタ lock を取る。 */
    {
        int64_t inc = gc_malloc_counters_increase(src, &src->malloc_counters.counters);
#if RGENGC_ESTIMATE_OLDMALLOC
        int64_t oldinc = gc_malloc_counters_increase(src, &src->malloc_counters.oldcounters);
#endif
        MALLOC_COUNTERS_LOCK(dst);
        if (inc > 0) gc_counter_add(&dst->malloc_counters.counters.malloc, (size_t)inc);
#if RGENGC_ESTIMATE_OLDMALLOC
        if (oldinc > 0) gc_counter_add(&dst->malloc_counters.oldcounters.malloc, (size_t)oldinc);
#endif
        MALLOC_COUNTERS_UNLOCK(dst);
    }

    /* shell を free する（rb_gc_impl_objspace_free と同様）。 */
    free(src->profile.records);
    free_stack_chunks(&src->mark_stack);
    mark_stack_free_cache(&src->mark_stack);
    GC_ASSERT(rb_darray_size(src->weak_references) == 0);
    rb_darray_free_without_gc(src->weak_references);
#ifdef MALLOC_COUNTERS_NEED_LOCK
    rb_native_mutex_destroy(&src->malloc_counters.lock);
#endif
    free(src);

    if (dst_gc_was_enabled) rb_gc_impl_gc_enable(dst);

    rlgc_during_absorb = prev_absorb;
}

void
rb_gc_impl_objspace_absorb(void *dst_ptr, void *src_ptr)
{
    rlgc_objspace_absorb(dst_ptr, src_ptr);
}

void
rb_gc_impl_start(void *objspace_ptr, bool full_mark, bool immediate_mark, bool immediate_sweep, bool compact)
{
    rb_objspace_t *objspace = objspace_ptr;
    unsigned int reason = (GPR_FLAG_FULL_MARK |
                           GPR_FLAG_IMMEDIATE_MARK |
                           GPR_FLAG_IMMEDIATE_SWEEP |
                           GPR_FLAG_METHOD);

    int full_marking_p = gc_config_full_mark_val;
    gc_config_full_mark_set(TRUE);

    /* compaction はオブジェクトを動かす。複数 objspace では global GC の barrier が全 Ractor を
     * 止めるので、全 objspace をまたいで再配置と 2 相の参照更新を安全に行える（下で compact=true
     * で呼ぶ rlgc_global_gc）。単一 objspace の compaction は通常の local 経路
     * （garbage_collect -> during_compacting 付き gc_start）を通る。 */

    /* For now, compact implies full mark / sweep, so ignore other flags */
    if (compact) {
        GC_ASSERT(GC_COMPACTION_SUPPORTED);

        reason |= GPR_FLAG_COMPACT;
    }
    else {
        if (!full_mark)       reason &= ~GPR_FLAG_FULL_MARK;
        if (!immediate_mark)  reason &= ~GPR_FLAG_IMMEDIATE_MARK;
        if (!immediate_sweep) reason &= ~GPR_FLAG_IMMEDIATE_SWEEP;
    }

    /* 複数 objspace での明示的な full な GC.start は global GC を走らせる。shareable と
     * cross-objspace の garbage を回収できる唯一の collector だから。 */
    if (!rb_gc_single_objspace_p() && (reason & GPR_FLAG_FULL_MARK)) {
        rlgc_global_gc(objspace, compact);
        gc_finalize_deferred(objspace);
        gc_config_full_mark_set(full_marking_p);
        return;
    }

    garbage_collect(objspace, reason);
    gc_finalize_deferred(objspace);

    gc_config_full_mark_set(full_marking_p);
}

void
rb_gc_impl_prepare_heap(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    size_t orig_total_slots = objspace_available_slots(objspace);
    size_t orig_allocatable_bytes = objspace->heap_pages.allocatable_bytes;

    rb_gc_impl_each_objects(objspace, gc_set_candidate_object_i, objspace_ptr);

    double orig_max_free_slots = gc_params.heap_free_slots_max_ratio;
    /* Ensure that all empty pages are moved onto empty_pages. */
    gc_params.heap_free_slots_max_ratio = 0.0;
    rb_gc_impl_start(objspace, true, true, true, true);
    gc_params.heap_free_slots_max_ratio = orig_max_free_slots;

    objspace->heap_pages.allocatable_bytes = 0;
    heap_pages_freeable_pages = objspace->empty_pages_count;
    heap_pages_free_unused_pages(objspace_ptr);
    GC_ASSERT(heap_pages_freeable_pages == 0);
    GC_ASSERT(objspace->empty_pages_count == 0);
    objspace->heap_pages.allocatable_bytes = orig_allocatable_bytes;

    size_t total_slots = objspace_available_slots(objspace);
    if (orig_total_slots > total_slots) {
        objspace->heap_pages.allocatable_bytes += (orig_total_slots - total_slots) * heaps[0].slot_size;
    }

#if defined(HAVE_MALLOC_TRIM) && !defined(RUBY_ALTERNATIVE_MALLOC_HEADER)
    malloc_trim(0);
#endif
}

static int
gc_is_moveable_obj(rb_objspace_t *objspace, VALUE obj)
{
    GC_ASSERT(!SPECIAL_CONST_P(obj));

    switch (BUILTIN_TYPE(obj)) {
      case T_NONE:
      case T_MOVED:
      case T_ZOMBIE:
        return FALSE;
      case T_SYMBOL:
      case T_STRING:
      case T_OBJECT:
      case T_FLOAT:
      case T_IMEMO:
      case T_ARRAY:
      case T_BIGNUM:
      case T_ICLASS:
      case T_MODULE:
      case T_REGEXP:
      case T_DATA:
      case T_MATCH:
      case T_STRUCT:
      case T_HASH:
      case T_FILE:
      case T_COMPLEX:
      case T_RATIONAL:
      case T_NODE:
      case T_CLASS:
        if (FL_TEST_RAW(obj, FL_FINALIZE)) {
            /* The finalizer table is a numtable. It looks up objects by address.
             * We can't mark the keys in the finalizer table because that would
             * prevent the objects from being collected.  This check prevents
             * objects that are keys in the finalizer table from being moved
             * without directly pinning them. */
            GC_ASSERT(st_is_member(finalizer_table, obj));

            return FALSE;
        }
        GC_ASSERT(RVALUE_MARKED(objspace, obj));
        GC_ASSERT(!RVALUE_PINNED(objspace, obj));

        return TRUE;

      default:
        rb_bug("gc_is_moveable_obj: unreachable (%d)", (int)BUILTIN_TYPE(obj));
        break;
    }

    return FALSE;
}

void rb_mv_generic_ivar(VALUE src, VALUE dst);

static VALUE
gc_move(rb_objspace_t *objspace, VALUE src, VALUE dest, struct heap_page *src_page, struct heap_page *dest_page)
{
    size_t src_slot_size = src_page->slot_size;
    size_t slot_size = dest_page->slot_size;

    int marked;
    int wb_unprotected;
    int uncollectible;
    int age;

    gc_report(4, objspace, "Moving object: %p -> %p\n", (void *)src, (void *)dest);

    GC_ASSERT(BUILTIN_TYPE(src) != T_NONE);
    GC_ASSERT(!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(dest), dest));

    GC_ASSERT(!RVALUE_MARKING(objspace, src));

    /* Save off bits for current object. */
    marked = RVALUE_MARKED(objspace, src);
    wb_unprotected = RVALUE_WB_UNPROTECTED(objspace, src);
    uncollectible = RVALUE_UNCOLLECTIBLE(objspace, src);
    bool remembered = RVALUE_REMEMBERED(objspace, src);
    /* pin bit はオブジェクトと共に移動する。単一 objspace の compaction でこれを失うと、
     * multi-objspace 化した際に pin が黙って解除され、local GC が cross-Ractor 参照される
     * method entry や shref 対象を free しうる。 */
    bool shareable = MARKED_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(src), src) != 0;
    bool shref = MARKED_IN_BITMAP(GET_HEAP_SHREF_BITS(src), src) != 0;
    age = RVALUE_AGE_GET(src);

    /* Clear bits for eventual T_MOVED */
    CLEAR_IN_BITMAP(GET_HEAP_MARK_BITS(src), src);
    CLEAR_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(src), src);
    CLEAR_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS(src), src);
    CLEAR_IN_BITMAP(GET_HEAP_PAGE(src)->remembered_bits, src);
    CLEAR_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(src), src);
    CLEAR_IN_BITMAP(GET_HEAP_SHREF_BITS(src), src);

    /* Move the object */
    memcpy((void *)dest, (void *)src, MIN(src_slot_size, slot_size));

    if (src_slot_size != slot_size) {
        rb_gc_obj_changed_slot_size(dest, slot_size - RVALUE_OVERHEAD);
    }

    if (RVALUE_OVERHEAD > 0) {
        void *dest_overhead = (void *)(((uintptr_t)dest) + slot_size - RVALUE_OVERHEAD);
        void *src_overhead = (void *)(((uintptr_t)src) + src_slot_size - RVALUE_OVERHEAD);

        memcpy(dest_overhead, src_overhead, RVALUE_OVERHEAD);
    }

    memset((void *)src, 0, src_slot_size);
    RVALUE_AGE_SET_BITMAP(src, 0);

    /* Set bits for object in new location */
    if (remembered) {
        MARK_IN_BITMAP(GET_HEAP_PAGE(dest)->remembered_bits, dest);
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_PAGE(dest)->remembered_bits, dest);
    }

    if (marked) {
        MARK_IN_BITMAP(GET_HEAP_MARK_BITS(dest), dest);
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_MARK_BITS(dest), dest);
    }

    if (wb_unprotected) {
        MARK_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(dest), dest);
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(dest), dest);
    }

    if (uncollectible) {
        MARK_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS(dest), dest);
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS(dest), dest);
    }

    if (shareable) {
        MARK_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(dest), dest);
        GET_HEAP_PAGE(dest)->has_shareable_objects = TRUE;
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_SHAREABLE_BITS(dest), dest);
    }

    if (shref) {
        MARK_IN_BITMAP(GET_HEAP_SHREF_BITS(dest), dest);
        GET_HEAP_PAGE(dest)->has_shref_objects = TRUE;
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_SHREF_BITS(dest), dest);
    }

    RVALUE_AGE_SET(dest, age);

    /* A re-embedded object (rb_gc_obj_changed_slot_size) references its
     * former fields_obj's contents directly; the write-barrier history
     * lived on the discarded fields_obj, so remember the object. */
    if (src_slot_size != slot_size && age >= RVALUE_OLD_AGE && !remembered) {
        rgengc_remember(objspace, dest);
    }

    /* Assign forwarding address */
    RMOVED(src)->flags = T_MOVED;
    RMOVED(src)->dummy = Qundef;
    RMOVED(src)->destination = dest;
    GC_ASSERT(BUILTIN_TYPE(dest) != T_NONE);

    GET_HEAP_PAGE(src)->heap->total_freed_objects++;
    GET_HEAP_PAGE(dest)->heap->total_allocated_objects++;

    return src;
}

#if GC_CAN_COMPILE_COMPACTION
static int
compare_pinned_slots(const void *left, const void *right, void *dummy)
{
    struct heap_page *left_page;
    struct heap_page *right_page;

    left_page = *(struct heap_page * const *)left;
    right_page = *(struct heap_page * const *)right;

    return left_page->pinned_slots - right_page->pinned_slots;
}

static int
compare_free_slots(const void *left, const void *right, void *dummy)
{
    struct heap_page *left_page;
    struct heap_page *right_page;

    left_page = *(struct heap_page * const *)left;
    right_page = *(struct heap_page * const *)right;

    return left_page->free_slots - right_page->free_slots;
}

static void
gc_sort_heap_by_compare_func(rb_objspace_t *objspace, gc_compact_compare_func compare_func)
{
    for (int j = 0; j < HEAP_COUNT; j++) {
        rb_heap_t *heap = &heaps[j];

        size_t total_pages = heap->total_pages;
        size_t size = rb_size_mul_or_raise(total_pages, sizeof(struct heap_page *), rb_eRuntimeError);
        struct heap_page *page = 0, **page_list = malloc(size);
        size_t i = 0;

        heap->free_pages = NULL;
        ccan_list_for_each(&heap->pages, page, page_node) {
            page_list[i++] = page;
            GC_ASSERT(page);
        }

        GC_ASSERT((size_t)i == total_pages);

        /* Sort the heap so "filled pages" are first. `heap_add_page` adds to the
         * head of the list, so empty pages will end up at the start of the heap */
        ruby_qsort(page_list, total_pages, sizeof(struct heap_page *), compare_func, NULL);

        /* Reset the eden heap */
        ccan_list_head_init(&heap->pages);

        for (i = 0; i < total_pages; i++) {
            ccan_list_add(&heap->pages, &page_list[i]->page_node);
            if (page_list[i]->free_slots != 0) {
                heap_add_freepage(heap, page_list[i]);
            }
        }

        free(page_list);
    }
}
#endif

void
rb_gc_impl_register_pinning_obj(void *objspace_ptr, VALUE obj)
{
    /* no-op */
}

bool
rb_gc_impl_object_moved_p(void *objspace_ptr, VALUE obj)
{
    return gc_object_moved_p(objspace_ptr, obj);
}

static int
gc_ref_update(void *vstart, void *vend, size_t stride, rb_objspace_t *objspace, struct heap_page *page)
{
    VALUE v = (VALUE)vstart;

    page->flags.has_uncollectible_wb_unprotected_objects = FALSE;
    page->flags.has_remembered_objects = FALSE;

    /* For each object on the page */
    for (; v != (VALUE)vend; v += stride) {
        asan_unpoisoning_object(v) {
            switch (BUILTIN_TYPE(v)) {
              case T_NONE:
              case T_MOVED:
              case T_ZOMBIE:
                break;
              default:
                if (RVALUE_WB_UNPROTECTED(objspace, v)) {
                    page->flags.has_uncollectible_wb_unprotected_objects = TRUE;
                }
                if (RVALUE_REMEMBERED(objspace, v)) {
                    page->flags.has_remembered_objects = TRUE;
                }
                if (page->flags.before_sweep) {
                    if (RVALUE_MARKED(objspace, v)) {
                        rb_gc_update_object_references(objspace, v);
                    }
                }
                else {
                    rb_gc_update_object_references(objspace, v);
                }
            }
        }
    }

    return 0;
}

static int
gc_update_references_weak_table_i(VALUE obj, void *data)
{
    int ret;
    asan_unpoisoning_object(obj) {
        ret = BUILTIN_TYPE(obj) == T_MOVED ? ST_REPLACE : ST_CONTINUE;
    }
    return ret;
}

static int
gc_update_references_weak_table_replace_i(VALUE *obj, void *data)
{
    *obj = rb_gc_location(*obj);

    return ST_CONTINUE;
}

/* 参照更新の per-objspace 側。この objspace の heap オブジェクトを歩き、移動した参照を
 * 書き換える（T_MOVED forwarding を cross-objspace に辿る）。compacting global GC は
 * これを全 objspace に対して実行する。 */
static void
gc_update_references_heap(rb_objspace_t *objspace)
{
    struct heap_page *page = NULL;

    for (int i = 0; i < HEAP_COUNT; i++) {
        bool should_set_mark_bits = TRUE;
        rb_heap_t *heap = &heaps[i];

        ccan_list_for_each(&heap->pages, page, page_node) {
            uintptr_t start = (uintptr_t)page->start;
            uintptr_t end = start + (page->total_slots * heap->slot_size);

            gc_ref_update((void *)start, (void *)end, heap->slot_size, objspace, page);
            if (page == heap->sweeping_page) {
                should_set_mark_bits = FALSE;
            }
            if (should_set_mark_bits) {
                gc_setup_mark_bits(page);
            }
        }
    }
}

/* 参照更新の VM グローバル側。finalizer 表、全 Ractor の VM root、weak 表。これらは
 * プロセス共通なので、compacting global GC は per-objspace ではなく（各 objspace の heap 側の
 * 後に）1 度だけ実行する。rb_gc_update_vm_references / weak 表の mark_and_move は冪等でなく、
 * さもないと更新済みオブジェクトを再 push してしまうため。 */
static void
gc_update_references_global(rb_objspace_t *objspace)
{
    gc_update_table_refs(finalizer_table);

    rb_gc_update_vm_references((void *)objspace);

    for (int table = 0; table < RB_GC_VM_WEAK_TABLE_COUNT; table++) {
        rb_gc_vm_weak_table_foreach(
            gc_update_references_weak_table_i,
            gc_update_references_weak_table_replace_i,
            NULL,
            false,
            table
        );
    }
}

static void
gc_update_references(rb_objspace_t *objspace)
{
    objspace->flags.during_reference_updating = true;

    rb_gc_before_updating_jit_code();

    gc_update_references_heap(objspace);
    gc_update_references_global(objspace);

    rb_gc_after_updating_jit_code();

    objspace->flags.during_reference_updating = false;
}

#if GC_CAN_COMPILE_COMPACTION
static void
root_obj_check_moved_i(const char *category, VALUE obj, void *data)
{
    rb_objspace_t *objspace = data;

    if (gc_object_moved_p(objspace, obj)) {
        rb_bug("ROOT %s points to MOVED: %p -> %s", category, (void *)obj, rb_obj_info(rb_gc_impl_location(objspace, obj)));
    }
}

static void
reachable_object_check_moved_i(VALUE ref, void *data)
{
    VALUE parent = (VALUE)data;
    if (gc_object_moved_p(rb_gc_get_objspace(), ref)) {
        rb_bug("Object %s points to MOVED: %p -> %s", rb_obj_info(parent), (void *)ref, rb_obj_info(rb_gc_impl_location(rb_gc_get_objspace(), ref)));
    }
}

static int
heap_check_moved_i(void *vstart, void *vend, size_t stride, void *data)
{
    rb_objspace_t *objspace = data;

    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        if (gc_object_moved_p(objspace, v)) {
            /* Moved object still on the heap, something may have a reference. */
        }
        else {
            asan_unpoisoning_object(v) {
                switch (BUILTIN_TYPE(v)) {
                  case T_NONE:
                  case T_ZOMBIE:
                    break;
                  default:
                    if (!rb_gc_impl_garbage_object_p(objspace, v)) {
                        rb_objspace_reachable_objects_from(v, reachable_object_check_moved_i, (void *)v);
                    }
                }
            }
        }
    }

    return 0;
}
#endif

bool
rb_gc_impl_during_gc_p(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    return during_gc;
}

#if RGENGC_PROFILE >= 2

static const char*
type_name(int type, VALUE obj)
{
    switch ((enum ruby_value_type)type) {
      case RUBY_T_NONE:     return "T_NONE";
      case RUBY_T_OBJECT:   return "T_OBJECT";
      case RUBY_T_CLASS:    return "T_CLASS";
      case RUBY_T_MODULE:   return "T_MODULE";
      case RUBY_T_FLOAT:    return "T_FLOAT";
      case RUBY_T_STRING:   return "T_STRING";
      case RUBY_T_REGEXP:   return "T_REGEXP";
      case RUBY_T_ARRAY:    return "T_ARRAY";
      case RUBY_T_HASH:     return "T_HASH";
      case RUBY_T_STRUCT:   return "T_STRUCT";
      case RUBY_T_BIGNUM:   return "T_BIGNUM";
      case RUBY_T_FILE:     return "T_FILE";
      case RUBY_T_DATA:     return "T_DATA";
      case RUBY_T_MATCH:    return "T_MATCH";
      case RUBY_T_COMPLEX:  return "T_COMPLEX";
      case RUBY_T_RATIONAL: return "T_RATIONAL";
      case RUBY_T_NIL:      return "T_NIL";
      case RUBY_T_TRUE:     return "T_TRUE";
      case RUBY_T_FALSE:    return "T_FALSE";
      case RUBY_T_SYMBOL:   return "T_SYMBOL";
      case RUBY_T_FIXNUM:   return "T_FIXNUM";
      case RUBY_T_UNDEF:    return "T_UNDEF";
      case RUBY_T_IMEMO:    return "T_IMEMO";
      case RUBY_T_NODE:     return "T_NODE";
      case RUBY_T_ICLASS:   return "T_ICLASS";
      case RUBY_T_ZOMBIE:   return "T_ZOMBIE";
      case RUBY_T_MOVED:    return "T_MOVED";
      default:              return "unknown";
    }
}

static void
gc_count_add_each_types(VALUE hash, const char *name, const size_t *types)
{
    VALUE result = rb_hash_new_with_size(T_MASK);
    int i;
    for (i=0; i<T_MASK; i++) {
        const char *type = type_name(i, 0);
        rb_hash_aset(result, ID2SYM(rb_intern(type)), SIZET2NUM(types[i]));
    }
    rb_hash_aset(hash, ID2SYM(rb_intern(name)), result);
}
#endif

size_t
rb_gc_impl_gc_count(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    return objspace->profile.count;
}

static VALUE
gc_info_decode(rb_objspace_t *objspace, const VALUE hash_or_key, const unsigned int orig_flags)
{
    static VALUE sym_major_by = Qnil, sym_gc_by, sym_immediate_sweep, sym_have_finalizer, sym_state, sym_need_major_by;
    static VALUE sym_nofree, sym_oldgen, sym_shady, sym_force, sym_stress;
#if RGENGC_ESTIMATE_OLDMALLOC
    static VALUE sym_oldmalloc;
#endif
    static VALUE sym_newobj, sym_malloc, sym_method, sym_capi;
    static VALUE sym_none, sym_marking, sym_sweeping;
    static VALUE sym_weak_references_count;
    VALUE hash = Qnil, key = Qnil;
    VALUE major_by, need_major_by;
    unsigned int flags = orig_flags ? orig_flags : objspace->profile.latest_gc_info;

    if (SYMBOL_P(hash_or_key)) {
        key = hash_or_key;
    }
    else if (RB_TYPE_P(hash_or_key, T_HASH)) {
        hash = hash_or_key;
    }
    else {
        rb_bug("gc_info_decode: non-hash or symbol given");
    }

    if (NIL_P(sym_major_by)) {
#define S(s) sym_##s = ID2SYM(rb_intern_const(#s))
        S(major_by);
        S(gc_by);
        S(immediate_sweep);
        S(have_finalizer);
        S(state);
        S(need_major_by);

        S(stress);
        S(nofree);
        S(oldgen);
        S(shady);
        S(force);
#if RGENGC_ESTIMATE_OLDMALLOC
        S(oldmalloc);
#endif
        S(newobj);
        S(malloc);
        S(method);
        S(capi);

        S(none);
        S(marking);
        S(sweeping);

        S(weak_references_count);
#undef S
    }

#define SET(name, attr) \
    if (key == sym_##name) \
        return (attr); \
    else if (hash != Qnil) \
        rb_hash_aset(hash, sym_##name, (attr));

    major_by =
      (flags & GPR_FLAG_MAJOR_BY_NOFREE) ? sym_nofree :
      (flags & GPR_FLAG_MAJOR_BY_OLDGEN) ? sym_oldgen :
      (flags & GPR_FLAG_MAJOR_BY_SHADY)  ? sym_shady :
      (flags & GPR_FLAG_MAJOR_BY_FORCE)  ? sym_force :
#if RGENGC_ESTIMATE_OLDMALLOC
      (flags & GPR_FLAG_MAJOR_BY_OLDMALLOC) ? sym_oldmalloc :
#endif
      Qnil;
    SET(major_by, major_by);

    if (orig_flags == 0) { /* set need_major_by only if flags not set explicitly */
        unsigned int need_major_flags = gc_needs_major_flags;
        need_major_by =
            (need_major_flags & GPR_FLAG_MAJOR_BY_NOFREE) ? sym_nofree :
            (need_major_flags & GPR_FLAG_MAJOR_BY_OLDGEN) ? sym_oldgen :
            (need_major_flags & GPR_FLAG_MAJOR_BY_SHADY)  ? sym_shady :
            (need_major_flags & GPR_FLAG_MAJOR_BY_FORCE)  ? sym_force :
#if RGENGC_ESTIMATE_OLDMALLOC
            (need_major_flags & GPR_FLAG_MAJOR_BY_OLDMALLOC) ? sym_oldmalloc :
#endif
            Qnil;
        SET(need_major_by, need_major_by);
    }

    SET(gc_by,
        (flags & GPR_FLAG_NEWOBJ) ? sym_newobj :
        (flags & GPR_FLAG_MALLOC) ? sym_malloc :
        (flags & GPR_FLAG_METHOD) ? sym_method :
        (flags & GPR_FLAG_CAPI)   ? sym_capi :
        (flags & GPR_FLAG_STRESS) ? sym_stress :
        Qnil
    );

    SET(have_finalizer, (flags & GPR_FLAG_HAVE_FINALIZE) ? Qtrue : Qfalse);
    SET(immediate_sweep, (flags & GPR_FLAG_IMMEDIATE_SWEEP) ? Qtrue : Qfalse);

    if (orig_flags == 0) {
        SET(state, gc_mode(objspace) == gc_mode_none ? sym_none :
                   gc_mode(objspace) == gc_mode_marking ? sym_marking : sym_sweeping);
    }

    SET(weak_references_count, LONG2FIX(objspace->profile.weak_references_count));
#undef SET

    if (!NIL_P(key)) {
        // Matched key should return above
        return Qundef;
    }

    return hash;
}

VALUE
rb_gc_impl_latest_gc_info(void *objspace_ptr, VALUE key)
{
    rb_objspace_t *objspace = objspace_ptr;

    return gc_info_decode(objspace, key, 0);
}


enum gc_stat_sym {
    gc_stat_sym_count,
    gc_stat_sym_time,
    gc_stat_sym_marking_time,
    gc_stat_sym_sweeping_time,
    gc_stat_sym_heap_allocated_pages,
    gc_stat_sym_heap_empty_pages,
    gc_stat_sym_heap_allocatable_bytes,
    gc_stat_sym_heap_available_slots,
    gc_stat_sym_heap_live_slots,
    gc_stat_sym_heap_free_slots,
    gc_stat_sym_heap_final_slots,
    gc_stat_sym_heap_marked_slots,
    gc_stat_sym_heap_eden_pages,
    gc_stat_sym_total_allocated_pages,
    gc_stat_sym_total_freed_pages,
    gc_stat_sym_total_allocated_objects,
    gc_stat_sym_total_freed_objects,
    gc_stat_sym_total_malloc_bytes,
    gc_stat_sym_total_free_bytes,
    gc_stat_sym_malloc_increase_bytes,
    gc_stat_sym_malloc_increase_bytes_limit,
    gc_stat_sym_minor_gc_count,
    gc_stat_sym_major_gc_count,
    gc_stat_sym_compact_count,
    gc_stat_sym_read_barrier_faults,
    gc_stat_sym_total_moved_objects,
    gc_stat_sym_remembered_wb_unprotected_objects,
    gc_stat_sym_remembered_wb_unprotected_objects_limit,
    gc_stat_sym_old_objects,
    gc_stat_sym_old_objects_limit,
#if RGENGC_ESTIMATE_OLDMALLOC
    gc_stat_sym_oldmalloc_increase_bytes,
    gc_stat_sym_oldmalloc_increase_bytes_limit,
#endif
#if RGENGC_PROFILE
    gc_stat_sym_total_generated_normal_object_count,
    gc_stat_sym_total_generated_shady_object_count,
    gc_stat_sym_total_shade_operation_count,
    gc_stat_sym_total_promoted_count,
    gc_stat_sym_total_remembered_normal_object_count,
    gc_stat_sym_total_remembered_shady_object_count,
#endif
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
        S(marking_time),
        S(sweeping_time),
        S(heap_allocated_pages);
        S(heap_empty_pages);
        S(heap_allocatable_bytes);
        S(heap_available_slots);
        S(heap_live_slots);
        S(heap_free_slots);
        S(heap_final_slots);
        S(heap_marked_slots);
        S(heap_eden_pages);
        S(total_allocated_pages);
        S(total_freed_pages);
        S(total_allocated_objects);
        S(total_freed_objects);
        S(total_malloc_bytes);
        S(total_free_bytes);
        S(malloc_increase_bytes);
        S(malloc_increase_bytes_limit);
        S(minor_gc_count);
        S(major_gc_count);
        S(compact_count);
        S(read_barrier_faults);
        S(total_moved_objects);
        S(remembered_wb_unprotected_objects);
        S(remembered_wb_unprotected_objects_limit);
        S(old_objects);
        S(old_objects_limit);
#if RGENGC_ESTIMATE_OLDMALLOC
        S(oldmalloc_increase_bytes);
        S(oldmalloc_increase_bytes_limit);
#endif
#if RGENGC_PROFILE
        S(total_generated_normal_object_count);
        S(total_generated_shady_object_count);
        S(total_shade_operation_count);
        S(total_promoted_count);
        S(total_remembered_normal_object_count);
        S(total_remembered_shady_object_count);
#endif /* RGENGC_PROFILE */
#undef S
    }
}

static uint64_t
ns_to_ms(uint64_t ns)
{
    return ns / (1000 * 1000);
}

static void malloc_increase_local_flush(rb_objspace_t *objspace);

VALUE
rb_gc_impl_stat(void *objspace_ptr, VALUE hash_or_sym)
{
    rb_objspace_t *objspace = objspace_ptr;
    VALUE hash = Qnil, key = Qnil;

    setup_gc_stat_symbols();

    malloc_increase_local_flush(objspace);

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
#define SET64(name, attr) \
    if (key == gc_stat_symbols[gc_stat_sym_##name]) \
        return ULL2NUM(attr); \
    else if (hash != Qnil) \
        rb_hash_aset(hash, gc_stat_symbols[gc_stat_sym_##name], ULL2NUM(attr));

    SET(count, objspace->profile.count);
    SET(time, (size_t)ns_to_ms(objspace->profile.marking_time_ns + objspace->profile.sweeping_time_ns)); // TODO: UINT64T2NUM
    SET(marking_time, (size_t)ns_to_ms(objspace->profile.marking_time_ns));
    SET(sweeping_time, (size_t)ns_to_ms(objspace->profile.sweeping_time_ns));

    {
        uint64_t total_malloc = (uint64_t)gc_counter_load_relaxed(&objspace->malloc_counters.counters.malloc);
        uint64_t total_free   = (uint64_t)gc_counter_load_relaxed(&objspace->malloc_counters.counters.free);
        SET64(total_malloc_bytes, total_malloc);
        SET64(total_free_bytes, total_free);
    }

    /* implementation dependent counters (small / fixnum-safe) */
    SET(heap_allocated_pages, rb_darray_size(objspace->heap_pages.sorted));
    SET(heap_empty_pages, objspace->empty_pages_count)
    SET(heap_allocatable_bytes, objspace->heap_pages.allocatable_bytes);
    SET(heap_eden_pages, heap_eden_total_pages(objspace));
    SET(total_allocated_pages, objspace->heap_pages.allocated_pages);
    SET(total_freed_pages, objspace->heap_pages.freed_pages);
    SET(malloc_increase_bytes, gc_malloc_counters_increase_unsigned(objspace, &objspace->malloc_counters.counters));
    SET(malloc_increase_bytes_limit, malloc_limit);
    SET(minor_gc_count, objspace->profile.minor_gc_count);
    SET(major_gc_count, objspace->profile.major_gc_count);
    SET(compact_count, objspace->profile.compact_count);
    SET(read_barrier_faults, objspace->profile.read_barrier_faults);
    SET(total_moved_objects, objspace->rcompactor.total_moved);
    SET(remembered_wb_unprotected_objects, objspace->rgengc.uncollectible_wb_unprotected_objects);
    SET(remembered_wb_unprotected_objects_limit, objspace->rgengc.uncollectible_wb_unprotected_objects_limit);
    SET(old_objects, objspace->rgengc.old_objects);
    SET(old_objects_limit, objspace->rgengc.old_objects_limit);
#if RGENGC_ESTIMATE_OLDMALLOC
    SET(oldmalloc_increase_bytes, gc_malloc_counters_increase_unsigned(objspace, &objspace->malloc_counters.oldcounters));
    SET(oldmalloc_increase_bytes_limit, objspace->rgengc.oldmalloc_increase_limit);
#endif

    SET(total_allocated_objects, total_allocated_objects(objspace));
    SET(total_freed_objects, total_freed_objects(objspace));
    SET(heap_available_slots, objspace_available_slots(objspace));
    SET(heap_live_slots, objspace_live_slots(objspace));
    SET(heap_free_slots, objspace_free_slots(objspace));
    SET(heap_final_slots, total_final_slots_count(objspace));
    SET(heap_marked_slots, objspace->marked_slots);

#if RGENGC_PROFILE
    SET(total_generated_normal_object_count, objspace->profile.total_generated_normal_object_count);
    SET(total_generated_shady_object_count, objspace->profile.total_generated_shady_object_count);
    SET(total_shade_operation_count, objspace->profile.total_shade_operation_count);
    SET(total_promoted_count, objspace->profile.total_promoted_count);
    SET(total_remembered_normal_object_count, objspace->profile.total_remembered_normal_object_count);
    SET(total_remembered_shady_object_count, objspace->profile.total_remembered_shady_object_count);
#endif /* RGENGC_PROFILE */
#undef SET
#undef SET64

    if (!NIL_P(key)) {
        // Matched key should return above
        return Qundef;
    }

#if defined(RGENGC_PROFILE) && RGENGC_PROFILE >= 2
    if (hash != Qnil) {
        gc_count_add_each_types(hash, "generated_normal_object_count_types", objspace->profile.generated_normal_object_count_types);
        gc_count_add_each_types(hash, "generated_shady_object_count_types", objspace->profile.generated_shady_object_count_types);
        gc_count_add_each_types(hash, "shade_operation_count_types", objspace->profile.shade_operation_count_types);
        gc_count_add_each_types(hash, "promoted_types", objspace->profile.promoted_types);
        gc_count_add_each_types(hash, "remembered_normal_object_count_types", objspace->profile.remembered_normal_object_count_types);
        gc_count_add_each_types(hash, "remembered_shady_object_count_types", objspace->profile.remembered_shady_object_count_types);
    }
#endif

    return hash;
}

enum gc_stat_heap_sym {
    gc_stat_heap_sym_slot_size,
    gc_stat_heap_sym_heap_live_slots,
    gc_stat_heap_sym_heap_free_slots,
    gc_stat_heap_sym_heap_final_slots,
    gc_stat_heap_sym_heap_eden_pages,
    gc_stat_heap_sym_heap_eden_slots,
    gc_stat_heap_sym_total_allocated_pages,
    gc_stat_heap_sym_force_major_gc_count,
    gc_stat_heap_sym_force_incremental_marking_finish_count,
    gc_stat_heap_sym_heap_allocatable_slots,
    gc_stat_heap_sym_total_allocated_objects,
    gc_stat_heap_sym_total_freed_objects,
    gc_stat_heap_sym_last
};

static VALUE gc_stat_heap_symbols[gc_stat_heap_sym_last];

static void
setup_gc_stat_heap_symbols(void)
{
    if (gc_stat_heap_symbols[0] == 0) {
#define S(s) gc_stat_heap_symbols[gc_stat_heap_sym_##s] = ID2SYM(rb_intern_const(#s))
        S(slot_size);
        S(heap_live_slots);
        S(heap_free_slots);
        S(heap_final_slots);
        S(heap_eden_pages);
        S(heap_eden_slots);
        S(heap_allocatable_slots);
        S(total_allocated_pages);
        S(force_major_gc_count);
        S(force_incremental_marking_finish_count);
        S(total_allocated_objects);
        S(total_freed_objects);
#undef S
    }
}

static VALUE
stat_one_heap(rb_objspace_t *objspace, rb_heap_t *heap, VALUE hash, VALUE key)
{
#define SET(name, attr) \
    if (key == gc_stat_heap_symbols[gc_stat_heap_sym_##name]) \
        return SIZET2NUM(attr); \
    else if (hash != Qnil) \
        rb_hash_aset(hash, gc_stat_heap_symbols[gc_stat_heap_sym_##name], SIZET2NUM(attr));

    SET(slot_size, heap->slot_size);
    SET(heap_live_slots, heap->total_allocated_objects - heap->total_freed_objects - heap->final_slots_count);
    SET(heap_free_slots, heap->total_slots - (heap->total_allocated_objects - heap->total_freed_objects));
    SET(heap_final_slots, heap->final_slots_count);
    SET(heap_eden_pages, heap->total_pages);
    SET(heap_eden_slots, heap->total_slots);
    SET(heap_allocatable_slots, objspace->heap_pages.allocatable_bytes / heap->slot_size);
    SET(total_allocated_pages, heap->total_allocated_pages);
    SET(force_major_gc_count, heap->force_major_gc_count);
    SET(force_incremental_marking_finish_count, heap->force_incremental_marking_finish_count);
    SET(total_allocated_objects, heap->total_allocated_objects);
    SET(total_freed_objects, heap->total_freed_objects);
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
    rb_objspace_t *objspace = objspace_ptr;

    setup_gc_stat_heap_symbols();

    if (NIL_P(heap_name)) {
        if (!RB_TYPE_P(hash_or_sym, T_HASH)) {
            rb_bug("non-hash given");
        }

        for (int i = 0; i < HEAP_COUNT; i++) {
            VALUE hash = rb_hash_aref(hash_or_sym, INT2FIX(i));
            if (NIL_P(hash)) {
                hash = rb_hash_new();
                rb_hash_aset(hash_or_sym, INT2FIX(i), hash);
            }

            stat_one_heap(objspace, &heaps[i], hash, Qnil);
        }
    }
    else if (FIXNUM_P(heap_name)) {
        int heap_idx = FIX2INT(heap_name);

        if (heap_idx < 0 || heap_idx >= HEAP_COUNT) {
            rb_raise(rb_eArgError, "size pool index out of range");
        }

        if (SYMBOL_P(hash_or_sym)) {
            return stat_one_heap(objspace, &heaps[heap_idx], Qnil, hash_or_sym);
        }
        else if (RB_TYPE_P(hash_or_sym, T_HASH)) {
            return stat_one_heap(objspace, &heaps[heap_idx], hash_or_sym, Qnil);
        }
        else {
            rb_bug("non-hash or symbol given");
        }
    }
    else {
        rb_bug("heap_name must be nil or an Integer");
    }

    return hash_or_sym;
}

/* I could include internal.h for this, but doing so undefines some Array macros
 * necessary for initialising objects, and I don't want to include all the array
 * headers to get them back
 * TODO: Investigate why RARRAY_AREF gets undefined in internal.h
 */
#ifndef RBOOL
#define RBOOL(v) (v ? Qtrue : Qfalse)
#endif

VALUE
rb_gc_impl_config_get(void *objspace_ptr)
{
#define sym(name) ID2SYM(rb_intern_const(name))
    rb_objspace_t *objspace = objspace_ptr;
    VALUE hash = rb_hash_new();

    rb_hash_aset(hash, sym("rgengc_allow_full_mark"), RBOOL(gc_config_full_mark_val));

    return hash;
}

static int
gc_config_set_key(VALUE key, VALUE value, VALUE data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;
    if (rb_sym2id(key) == rb_intern("rgengc_allow_full_mark")) {
        gc_rest(objspace);
        gc_config_full_mark_set(RTEST(value));
    }
    return ST_CONTINUE;
}

void
rb_gc_impl_config_set(void *objspace_ptr, VALUE hash)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (!RB_TYPE_P(hash, T_HASH)) {
        rb_raise(rb_eArgError, "expected keyword arguments");
    }

    rb_hash_foreach(hash, gc_config_set_key, (st_data_t)objspace);
}

VALUE
rb_gc_impl_stress_get(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;
    return ruby_gc_stress_mode;
}

void
rb_gc_impl_stress_set(void *objspace_ptr, VALUE flag)
{
    rb_objspace_t *objspace = objspace_ptr;

    objspace->flags.gc_stressful = RTEST(flag);
    objspace->gc_stress_mode = flag;
}

static int
get_envparam_size(const char *name, size_t *default_value, size_t lower_bound)
{
    const char *ptr = getenv(name);
    ssize_t val;

    if (ptr != NULL && *ptr) {
        size_t unit = 0;
        char *end;
#if SIZEOF_SIZE_T == SIZEOF_LONG_LONG
        val = strtoll(ptr, &end, 0);
#else
        val = strtol(ptr, &end, 0);
#endif
        switch (*end) {
          case 'k': case 'K':
            unit = 1024;
            ++end;
            break;
          case 'm': case 'M':
            unit = 1024*1024;
            ++end;
            break;
          case 'g': case 'G':
            unit = 1024*1024*1024;
            ++end;
            break;
        }
        while (*end && isspace((unsigned char)*end)) end++;
        if (*end) {
            if (RTEST(ruby_verbose)) fprintf(stderr, "invalid string for %s: %s\n", name, ptr);
            return 0;
        }
        if (unit > 0) {
            if (val < -(ssize_t)(SIZE_MAX / 2 / unit) || (ssize_t)(SIZE_MAX / 2 / unit) < val) {
                if (RTEST(ruby_verbose)) fprintf(stderr, "%s=%s is ignored because it overflows\n", name, ptr);
                return 0;
            }
            val *= unit;
        }
        if (val > 0 && (size_t)val > lower_bound) {
            if (RTEST(ruby_verbose)) {
                fprintf(stderr, "%s=%"PRIdSIZE" (default value: %"PRIuSIZE")\n", name, val, *default_value);
            }
            *default_value = (size_t)val;
            return 1;
        }
        else {
            if (RTEST(ruby_verbose)) {
                fprintf(stderr, "%s=%"PRIdSIZE" (default value: %"PRIuSIZE") is ignored because it must be greater than %"PRIuSIZE".\n",
                        name, val, *default_value, lower_bound);
            }
            return 0;
        }
    }
    return 0;
}

static int
get_envparam_double(const char *name, double *default_value, double lower_bound, double upper_bound, int accept_zero)
{
    const char *ptr = getenv(name);
    double val;

    if (ptr != NULL && *ptr) {
        char *end;
        val = strtod(ptr, &end);
        if (!*ptr || *end) {
            if (RTEST(ruby_verbose)) fprintf(stderr, "invalid string for %s: %s\n", name, ptr);
            return 0;
        }

        if (accept_zero && val == 0.0) {
            goto accept;
        }
        else if (val <= lower_bound) {
            if (RTEST(ruby_verbose)) {
                fprintf(stderr, "%s=%f (default value: %f) is ignored because it must be greater than %f.\n",
                        name, val, *default_value, lower_bound);
            }
        }
        else if (upper_bound != 0.0 && /* ignore upper_bound if it is 0.0 */
                 val > upper_bound) {
            if (RTEST(ruby_verbose)) {
                fprintf(stderr, "%s=%f (default value: %f) is ignored because it must be lower than %f.\n",
                        name, val, *default_value, upper_bound);
            }
        }
        else {
            goto accept;
        }
    }
    return 0;

  accept:
    if (RTEST(ruby_verbose)) fprintf(stderr, "%s=%f (default value: %f)\n", name, val, *default_value);
    *default_value = val;
    return 1;
}

/*
 * GC tuning environment variables
 *
 * * RUBY_GC_HEAP_FREE_SLOTS
 *   - Prepare at least this amount of slots after GC.
 *   - Allocate slots if there are not enough slots.
 * * RUBY_GC_HEAP_GROWTH_FACTOR (new from 2.1)
 *   - Allocate slots by this factor.
 *   - (next slots number) = (current slots number) * (this factor)
 * * RUBY_GC_HEAP_GROWTH_MAX_BYTES (was RUBY_GC_HEAP_GROWTH_MAX_SLOTS)
 *   - Allocation rate is limited to this number of bytes.
 * * RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO (new from 2.4)
 *   - Allocate additional pages when the number of free slots is
 *     lower than the value (total_slots * (this ratio)).
 * * RUBY_GC_HEAP_FREE_SLOTS_GOAL_RATIO (new from 2.4)
 *   - Allocate slots to satisfy this formula:
 *       free_slots = total_slots * goal_ratio
 *   - In other words, prepare (total_slots * goal_ratio) free slots.
 *   - if this value is 0.0, then use RUBY_GC_HEAP_GROWTH_FACTOR directly.
 * * RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO (new from 2.4)
 *   - Allow to free pages when the number of free slots is
 *     greater than the value (total_slots * (this ratio)).
 * * RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR (new from 2.1.1)
 *   - Do full GC when the number of old objects is more than R * N
 *     where R is this factor and
 *           N is the number of old objects just after last full GC.
 *
 *  * obsolete
 *    * RUBY_FREE_MIN       -> RUBY_GC_HEAP_FREE_SLOTS (from 2.1)
 *    * RUBY_HEAP_MIN_SLOTS -> RUBY_GC_HEAP_INIT_SLOTS (from 2.1) -> RUBY_GC_HEAP_INIT_BYTES
 *
 * * RUBY_GC_MALLOC_LIMIT
 * * RUBY_GC_MALLOC_LIMIT_MAX (new from 2.1)
 * * RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR (new from 2.1)
 *
 * * RUBY_GC_OLDMALLOC_LIMIT (new from 2.1)
 * * RUBY_GC_OLDMALLOC_LIMIT_MAX (new from 2.1)
 * * RUBY_GC_OLDMALLOC_LIMIT_GROWTH_FACTOR (new from 2.1)
 */

void
rb_gc_impl_set_params(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;
    /* RUBY_GC_HEAP_FREE_SLOTS */
    if (get_envparam_size("RUBY_GC_HEAP_FREE_SLOTS", &gc_params.heap_free_slots, 0)) {
        /* ok */
    }

    get_envparam_size("RUBY_GC_HEAP_INIT_BYTES", &gc_params.heap_init_bytes, 0);

    get_envparam_double("RUBY_GC_HEAP_GROWTH_FACTOR", &gc_params.growth_factor, 1.0, 0.0, FALSE);
    get_envparam_size  ("RUBY_GC_HEAP_GROWTH_MAX_BYTES", &gc_params.growth_max_bytes, 0);
    get_envparam_double("RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO", &gc_params.heap_free_slots_min_ratio,
                        0.0, 1.0, FALSE);
    get_envparam_double("RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO", &gc_params.heap_free_slots_max_ratio,
                        gc_params.heap_free_slots_min_ratio, 1.0, FALSE);
    get_envparam_double("RUBY_GC_HEAP_FREE_SLOTS_GOAL_RATIO", &gc_params.heap_free_slots_goal_ratio,
                        gc_params.heap_free_slots_min_ratio, gc_params.heap_free_slots_max_ratio, TRUE);
    get_envparam_double("RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR", &gc_params.oldobject_limit_factor, 0.0, 0.0, TRUE);
    get_envparam_double("RUBY_GC_HEAP_REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO", &gc_params.uncollectible_wb_unprotected_objects_limit_ratio, 0.0, 0.0, TRUE);

    if (get_envparam_size("RUBY_GC_MALLOC_LIMIT", &gc_params.malloc_limit_min, 0)) {
        malloc_limit = gc_params.malloc_limit_min;
    }
    get_envparam_size  ("RUBY_GC_MALLOC_LIMIT_MAX", &gc_params.malloc_limit_max, 0);
    if (!gc_params.malloc_limit_max) { /* ignore max-check if 0 */
        gc_params.malloc_limit_max = SIZE_MAX;
    }
    get_envparam_double("RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR", &gc_params.malloc_limit_growth_factor, 1.0, 0.0, FALSE);

#if RGENGC_ESTIMATE_OLDMALLOC
    if (get_envparam_size("RUBY_GC_OLDMALLOC_LIMIT", &gc_params.oldmalloc_limit_min, 0)) {
        objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_min;
    }
    get_envparam_size  ("RUBY_GC_OLDMALLOC_LIMIT_MAX", &gc_params.oldmalloc_limit_max, 0);
    get_envparam_double("RUBY_GC_OLDMALLOC_LIMIT_GROWTH_FACTOR", &gc_params.oldmalloc_limit_growth_factor, 1.0, 0.0, FALSE);
#endif
}

static inline size_t
objspace_malloc_size(rb_objspace_t *objspace, void *ptr, size_t hint)
{
#ifdef HAVE_MALLOC_USABLE_SIZE
    if (!hint) {
        hint = malloc_usable_size(ptr);
    }
#endif
    return hint;
}

enum memop_type {
    MEMOP_TYPE_MALLOC  = 0,
    MEMOP_TYPE_FREE,
    MEMOP_TYPE_REALLOC
};

static inline void
atomic_sub_nounderflow(size_t *var, size_t sub)
{
    if (sub == 0) return;

    while (1) {
        size_t val = *var;
        if (val < sub) sub = val;
        if (RUBY_ATOMIC_SIZE_CAS(*var, val, val-sub) == val) break;
    }
}

#define gc_stress_full_mark_after_malloc_p() \
    (FIXNUM_P(ruby_gc_stress_mode) && (FIX2LONG(ruby_gc_stress_mode) & (1<<gc_stress_full_mark_after_malloc)))

static void
objspace_malloc_gc_stress(rb_objspace_t *objspace)
{
    if (ruby_gc_stressful && ruby_native_thread_p()) {
        unsigned int reason = (GPR_FLAG_IMMEDIATE_MARK | GPR_FLAG_IMMEDIATE_SWEEP |
                               GPR_FLAG_STRESS | GPR_FLAG_MALLOC);

        if (gc_stress_full_mark_after_malloc_p()) {
            reason |= GPR_FLAG_FULL_MARK;
        }
        garbage_collect_with_gvl(objspace, reason);
    }
}

static void
malloc_increase_commit(rb_objspace_t *objspace, size_t new_size, size_t old_size)
{
    if (new_size > old_size) {
        size_t delta = new_size - old_size;
        MALLOC_COUNTERS_LOCK(objspace);
        gc_counter_add(&objspace->malloc_counters.counters.malloc, delta);
#if RGENGC_ESTIMATE_OLDMALLOC
        gc_counter_add(&objspace->malloc_counters.oldcounters.malloc, delta);
#endif
        MALLOC_COUNTERS_UNLOCK(objspace);
    }
    else if (old_size > new_size) {
        size_t delta = old_size - new_size;
        MALLOC_COUNTERS_LOCK(objspace);
        gc_counter_add(&objspace->malloc_counters.counters.free, delta);
#if RGENGC_ESTIMATE_OLDMALLOC
        gc_counter_add(&objspace->malloc_counters.oldcounters.free, delta);
#endif
        MALLOC_COUNTERS_UNLOCK(objspace);
    }
}

#if USE_MALLOC_INCREASE_LOCAL
static void
malloc_increase_local_flush(rb_objspace_t *objspace)
{
    int delta = malloc_increase_local;
    if (delta == 0) return;

    malloc_increase_local = 0;
    if (delta > 0) {
        malloc_increase_commit(objspace, (size_t)delta, 0);
    }
    else {
        malloc_increase_commit(objspace, 0, (size_t)(-delta));
    }
}
#else
static void
malloc_increase_local_flush(rb_objspace_t *objspace)
{
}
#endif

static inline bool
objspace_malloc_increase_report(rb_objspace_t *objspace, void *mem, size_t new_size, size_t old_size, enum memop_type type, bool gc_allowed)
{
    if (0) fprintf(stderr, "increase - ptr: %p, type: %s, new_size: %"PRIdSIZE", old_size: %"PRIdSIZE"\n",
                   mem,
                   type == MEMOP_TYPE_MALLOC  ? "malloc" :
                   type == MEMOP_TYPE_FREE    ? "free  " :
                   type == MEMOP_TYPE_REALLOC ? "realloc": "error",
                   new_size, old_size);
    return false;
}

static bool
objspace_malloc_increase_body(rb_objspace_t *objspace, void *mem, size_t new_size, size_t old_size, enum memop_type type, bool gc_allowed)
{
#if USE_MALLOC_INCREASE_LOCAL
    if (new_size < GC_MALLOC_INCREASE_LOCAL_THRESHOLD &&
        old_size < GC_MALLOC_INCREASE_LOCAL_THRESHOLD) {
        malloc_increase_local += (int)new_size - (int)old_size;

        if (malloc_increase_local >= GC_MALLOC_INCREASE_LOCAL_THRESHOLD ||
            malloc_increase_local <= -GC_MALLOC_INCREASE_LOCAL_THRESHOLD) {
            malloc_increase_local_flush(objspace);
        }
    }
    else {
        malloc_increase_local_flush(objspace);
        malloc_increase_commit(objspace, new_size, old_size);
    }
#else
    malloc_increase_commit(objspace, new_size, old_size);
#endif

    if (type == MEMOP_TYPE_MALLOC && gc_allowed) {
      retry:
        if (malloc_increase > malloc_limit && ruby_native_thread_p() && !dont_gc_val() && !rb_gc_gc_disabled_global_p()) {
            if (ruby_thread_has_gvl_p() && is_lazy_sweeping(objspace)) {
                gc_sweep_step_for_malloc(objspace); /* sweeping frees may reduce malloc_increase */
                goto retry;
            }
            garbage_collect_with_gvl(objspace, GPR_FLAG_MALLOC);
        }
    }

#if MALLOC_ALLOCATED_SIZE
    if (new_size >= old_size) {
        RUBY_ATOMIC_SIZE_ADD(objspace->malloc_params.allocated_size, new_size - old_size);
    }
    else {
        size_t dec_size = old_size - new_size;

#if MALLOC_ALLOCATED_SIZE_CHECK
        size_t allocated_size = objspace->malloc_params.allocated_size;
        if (allocated_size < dec_size) {
            rb_bug("objspace_malloc_increase: underflow malloc_params.allocated_size.");
        }
#endif
        atomic_sub_nounderflow(&objspace->malloc_params.allocated_size, dec_size);
    }

    switch (type) {
      case MEMOP_TYPE_MALLOC:
        RUBY_ATOMIC_SIZE_INC(objspace->malloc_params.allocations);
        break;
      case MEMOP_TYPE_FREE:
        {
            size_t allocations = objspace->malloc_params.allocations;
            if (allocations > 0) {
                atomic_sub_nounderflow(&objspace->malloc_params.allocations, 1);
            }
#if MALLOC_ALLOCATED_SIZE_CHECK
            else {
                GC_ASSERT(objspace->malloc_params.allocations > 0);
            }
#endif
        }
        break;
      case MEMOP_TYPE_REALLOC: /* ignore */ break;
    }
#endif
    return true;
}

#define objspace_malloc_increase(...) \
    for (bool malloc_increase_done = objspace_malloc_increase_report(__VA_ARGS__); \
         !malloc_increase_done; \
         malloc_increase_done = objspace_malloc_increase_body(__VA_ARGS__))

struct malloc_obj_info { /* 4 words */
    size_t size;
};

static inline size_t
objspace_malloc_prepare(rb_objspace_t *objspace, size_t size)
{
    if (size == 0) size = 1;

#if CALC_EXACT_MALLOC_SIZE
    size += sizeof(struct malloc_obj_info);
#endif

    return size;
}

static bool
malloc_during_gc_p(rb_objspace_t *objspace)
{
    /* malloc is not allowed during GC when we're not using multiple ractors
     * (since ractors can run while another thread is sweeping) and when we
     * have the GVL (since if we don't have the GVL, we'll try to acquire the
     * GVL which will block and ensure the other thread finishes GC). */
    return during_gc && !dont_gc_val() && !rb_gc_multi_ractor_p() && ruby_thread_has_gvl_p();
}

static inline void *
objspace_malloc_fixup(rb_objspace_t *objspace, void *mem, size_t size, bool gc_allowed)
{
    size = objspace_malloc_size(objspace, mem, size);
    objspace_malloc_increase(objspace, mem, size, 0, MEMOP_TYPE_MALLOC, gc_allowed) {}

#if CALC_EXACT_MALLOC_SIZE
    {
        struct malloc_obj_info *info = mem;
        info->size = size;
        mem = info + 1;
    }
#endif

    return mem;
}

#if defined(__GNUC__) && RUBY_DEBUG
#define RB_BUG_INSTEAD_OF_RB_MEMERROR 1
#endif

#ifndef RB_BUG_INSTEAD_OF_RB_MEMERROR
# define RB_BUG_INSTEAD_OF_RB_MEMERROR 0
#endif

#define GC_MEMERROR(...) \
    ((RB_BUG_INSTEAD_OF_RB_MEMERROR+0) ? rb_bug("" __VA_ARGS__) : (void)0)

#define TRY_WITH_GC(siz, expr) do {                          \
        const gc_profile_record_flag gpr =                   \
            GPR_FLAG_FULL_MARK           |                   \
            GPR_FLAG_IMMEDIATE_MARK      |                   \
            GPR_FLAG_IMMEDIATE_SWEEP     |                   \
            GPR_FLAG_MALLOC;                                 \
        objspace_malloc_gc_stress(objspace);                 \
                                                             \
        if (RB_LIKELY((expr))) {                             \
            /* Success on 1st try */                         \
        }                                                    \
        else if (gc_allowed && !garbage_collect_with_gvl(objspace, gpr)) { \
            /* @shyouhei thinks this doesn't happen */       \
            GC_MEMERROR("TRY_WITH_GC: could not GC");        \
        }                                                    \
        else if ((expr)) {                                   \
            /* Success on 2nd try */                         \
        }                                                    \
        else {                                               \
            GC_MEMERROR("TRY_WITH_GC: could not allocate:"   \
                        "%"PRIdSIZE" bytes for %s",          \
                        siz, # expr);                        \
        }                                                    \
    } while (0)

static void
check_malloc_not_in_gc(rb_objspace_t *objspace, const char *msg)
{
    if (RB_UNLIKELY(malloc_during_gc_p(objspace))) {
        dont_gc_on();
        during_gc = false;
        rb_bug("Cannot %s during GC", msg);
    }
}

void
rb_gc_impl_free(void *objspace_ptr, void *ptr, size_t old_size)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (!ptr) {
        /*
         * ISO/IEC 9899 says "If ptr is a null pointer, no action occurs" since
         * its first version.  We would better follow.
         */
        return;
    }
#if CALC_EXACT_MALLOC_SIZE
    struct malloc_obj_info *info = (struct malloc_obj_info *)ptr - 1;
#if VERIFY_FREE_SIZE
    if (!info->size) {
        rb_bug("buffer %p has no recorded size. Was it allocated with ruby_mimalloc? If so it should be freed with ruby_mimfree", ptr);
    }

    if (old_size && (old_size + sizeof(struct malloc_obj_info)) != info->size) {
        rb_bug("buffer %p freed with old_size=%zu, but was allocated with size=%zu", ptr, old_size, info->size - sizeof(struct malloc_obj_info));
    }
#endif
    ptr = info;
    old_size = info->size;
#endif
    old_size = objspace_malloc_size(objspace, ptr, old_size);

    objspace_malloc_increase(objspace, ptr, 0, old_size, MEMOP_TYPE_FREE, true) {
        free(ptr);
        ptr = NULL;
        RB_DEBUG_COUNTER_INC(heap_xfree);
    }
}

void *
rb_gc_impl_malloc(void *objspace_ptr, size_t size, bool gc_allowed)
{
    rb_objspace_t *objspace = objspace_ptr;
    check_malloc_not_in_gc(objspace, "malloc");

    void *mem;

    size = objspace_malloc_prepare(objspace, size);
    TRY_WITH_GC(size, mem = malloc(size));
    RB_DEBUG_COUNTER_INC(heap_xmalloc);
    if (!mem) return mem;
    return objspace_malloc_fixup(objspace, mem, size, gc_allowed);
}

void *
rb_gc_impl_calloc(void *objspace_ptr, size_t size, bool gc_allowed)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (RB_UNLIKELY(malloc_during_gc_p(objspace))) {
        rb_warn("calloc during GC detected, this could cause crashes if it triggers another GC");
#if RGENGC_CHECK_MODE || RUBY_DEBUG
        rb_bug("Cannot calloc during GC");
#endif
    }

    void *mem;

    size = objspace_malloc_prepare(objspace, size);
    TRY_WITH_GC(size, mem = calloc1(size));
    if (!mem) return mem;
    return objspace_malloc_fixup(objspace, mem, size, gc_allowed);
}

void *
rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size, bool gc_allowed)
{
    rb_objspace_t *objspace = objspace_ptr;

    check_malloc_not_in_gc(objspace, "realloc");

    void *mem;

    if (!ptr) return rb_gc_impl_malloc(objspace, new_size, gc_allowed);

    /*
     * The behavior of realloc(ptr, 0) is implementation defined.
     * Therefore we don't use realloc(ptr, 0) for portability reason.
     * see http://www.open-std.org/jtc1/sc22/wg14/www/docs/dr_400.htm
     */
    if (new_size == 0) {
        if ((mem = rb_gc_impl_malloc(objspace, 0, gc_allowed)) != NULL) {
            /*
             * - OpenBSD's malloc(3) man page says that when 0 is passed, it
             *   returns a non-NULL pointer to an access-protected memory page.
             *   The returned pointer cannot be read / written at all, but
             *   still be a valid argument of free().
             *
             *   https://man.openbsd.org/malloc.3
             *
             * - Linux's malloc(3) man page says that it _might_ perhaps return
             *   a non-NULL pointer when its argument is 0.  That return value
             *   is safe (and is expected) to be passed to free().
             *
             *   https://man7.org/linux/man-pages/man3/malloc.3.html
             *
             * - As I read the implementation jemalloc's malloc() returns fully
             *   normal 16 bytes memory region when its argument is 0.
             *
             * - As I read the implementation musl libc's malloc() returns
             *   fully normal 32 bytes memory region when its argument is 0.
             *
             * - Other malloc implementations can also return non-NULL.
             */
            rb_gc_impl_free(objspace, ptr, old_size);
            return mem;
        }
        else {
            /*
             * It is dangerous to return NULL here, because that could lead to
             * RCE.  Fallback to 1 byte instead of zero.
             *
             * https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2019-11932
             */
            new_size = 1;
        }
    }

#if CALC_EXACT_MALLOC_SIZE
    {
        struct malloc_obj_info *info = (struct malloc_obj_info *)ptr - 1;
        new_size += sizeof(struct malloc_obj_info);
        ptr = info;
#if VERIFY_FREE_SIZE
        if (old_size && (old_size + sizeof(struct malloc_obj_info)) != info->size) {
            rb_bug("buffer %p realloced with old_size=%zu, but was allocated with size=%zu", ptr, old_size, info->size - sizeof(struct malloc_obj_info));
        }
#endif
        old_size = info->size;
    }
#endif

    old_size = objspace_malloc_size(objspace, ptr, old_size);
    TRY_WITH_GC(new_size, mem = RB_GNUC_EXTENSION_BLOCK(realloc(ptr, new_size)));
    if (!mem) return mem;
    new_size = objspace_malloc_size(objspace, mem, new_size);

#if CALC_EXACT_MALLOC_SIZE
    {
        struct malloc_obj_info *info = mem;
        info->size = new_size;
        mem = info + 1;
    }
#endif

    objspace_malloc_increase(objspace, mem, new_size, old_size, MEMOP_TYPE_REALLOC, gc_allowed);

    RB_DEBUG_COUNTER_INC(heap_xrealloc);
    return mem;
}

void
rb_gc_impl_adjust_memory_usage(void *objspace_ptr, ssize_t diff)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (diff > 0) {
        objspace_malloc_increase(objspace, 0, diff, 0, MEMOP_TYPE_REALLOC, true);
    }
    else if (diff < 0) {
        objspace_malloc_increase(objspace, 0, 0, -diff, MEMOP_TYPE_REALLOC, true);
    }
}

// TODO: move GC profiler stuff back into gc.c
/*
  ------------------------------ GC profiler ------------------------------
*/

#define GC_PROFILE_RECORD_DEFAULT_SIZE 100
#define GC_PROFILE_RECORD_DEFAULT_MAX_RECORDS 4096
#define GC_PROFILE_RECORD_UNBOUNDED 0

static bool
current_process_time(struct timespec *ts)
{
#if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_PROCESS_CPUTIME_ID)
    {
        static int try_clock_gettime = 1;
        if (try_clock_gettime && clock_gettime(CLOCK_PROCESS_CPUTIME_ID, ts) == 0) {
            return true;
        }
        else {
            try_clock_gettime = 0;
        }
    }
#endif

#ifdef RUSAGE_SELF
    {
        struct rusage usage;
        struct timeval time;
        if (getrusage(RUSAGE_SELF, &usage) == 0) {
            time = usage.ru_utime;
            ts->tv_sec = time.tv_sec;
            ts->tv_nsec = (int32_t)time.tv_usec * 1000;
            return true;
        }
    }
#endif

#ifdef _WIN32
    {
        FILETIME creation_time, exit_time, kernel_time, user_time;
        ULARGE_INTEGER ui;

        if (GetProcessTimes(GetCurrentProcess(),
                            &creation_time, &exit_time, &kernel_time, &user_time) != 0) {
            memcpy(&ui, &user_time, sizeof(FILETIME));
#define PER100NSEC (uint64_t)(1000 * 1000 * 10)
            ts->tv_nsec = (long)(ui.QuadPart % PER100NSEC);
            ts->tv_sec  = (time_t)(ui.QuadPart / PER100NSEC);
            return true;
        }
    }
#endif

    return false;
}

static double
getrusage_time(void)
{
    struct timespec ts;
    if (current_process_time(&ts)) {
        return ts.tv_sec + ts.tv_nsec * 1e-9;
    }
    else {
        return 0.0;
    }
}

static inline double
hrtime_to_sec(rb_hrtime_t time)
{
    return (double)time / (double)RB_HRTIME_PER_SEC;
}

static inline rb_hrtime_t
elapsed_hrtime_from(rb_hrtime_t start)
{
    return rb_hrtime_sub(rb_hrtime_now(), start);
}


static inline size_t
gc_profile_record_count(rb_objspace_t *objspace)
{
    return objspace->profile.record_count;
}

static inline size_t
gc_profile_record_index(rb_objspace_t *objspace, size_t logical_index)
{
    if (objspace->profile.max_records != GC_PROFILE_RECORD_UNBOUNDED &&
            objspace->profile.record_count == objspace->profile.size) {
        return (objspace->profile.next_index + logical_index) % objspace->profile.size;
    }
    else {
        return logical_index;
    }
}

static void
gc_profile_records_free(rb_objspace_t *objspace)
{
    void *p = objspace->profile.records;
    objspace->profile.records = NULL;
    objspace->profile.size = 0;
    objspace->profile.next_index = 0;
    objspace->profile.record_count = 0;
    objspace->profile.current_record = 0;
    free(p);
}

static inline void
gc_prof_setup_new_record(rb_objspace_t *objspace, unsigned int reason)
{
    if (objspace->profile.run) {
        size_t index;
        gc_profile_record *record;

        if (objspace->profile.max_records == GC_PROFILE_RECORD_UNBOUNDED) {
            index = objspace->profile.record_count++;
            objspace->profile.next_index = objspace->profile.record_count;

            if (!objspace->profile.records) {
                objspace->profile.size = GC_PROFILE_RECORD_DEFAULT_SIZE;
                objspace->profile.records = malloc(xmalloc2_size(sizeof(gc_profile_record), objspace->profile.size));
            }
            if (index >= objspace->profile.size) {
                void *ptr;
                objspace->profile.size += 1000;
                ptr = realloc(objspace->profile.records, xmalloc2_size(sizeof(gc_profile_record), objspace->profile.size));
                if (!ptr) rb_memerror();
                objspace->profile.records = ptr;
            }
        }
        else {
            if (!objspace->profile.records) {
                objspace->profile.size = objspace->profile.max_records;
                objspace->profile.records = malloc(xmalloc2_size(sizeof(gc_profile_record), objspace->profile.size));
            }
            index = objspace->profile.next_index;
            objspace->profile.next_index = (objspace->profile.next_index + 1) % objspace->profile.size;
            if (objspace->profile.record_count < objspace->profile.size) {
                objspace->profile.record_count++;
            }
        }

        if (!objspace->profile.records) {
            rb_bug("gc_profile malloc or realloc miss");
        }
        record = objspace->profile.current_record = &objspace->profile.records[index];
        MEMZERO(record, gc_profile_record, 1);

        /* setup before-GC parameter */
        record->flags = reason | (ruby_gc_stressful ? GPR_FLAG_STRESS : 0);
        record->sequence = objspace->profile.record_sequence++;
        record->gc_invoke_wall_time = rb_hrtime_sub(rb_hrtime_now(),
                objspace->profile.invoke_wall_time);
#if MALLOC_ALLOCATED_SIZE
        record->allocated_size = malloc_allocated_size;
#endif
#if GC_PROFILE_MORE_DETAIL && GC_PROFILE_DETAIL_MEMORY
#ifdef RUSAGE_SELF
        {
            struct rusage usage;
            if (getrusage(RUSAGE_SELF, &usage) == 0) {
                record->maxrss = usage.ru_maxrss;
                record->minflt = usage.ru_minflt;
                record->majflt = usage.ru_majflt;
            }
        }
#endif
#endif
    }
}

static inline void
gc_prof_timer_start(rb_objspace_t *objspace)
{
    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
#if GC_PROFILE_MORE_DETAIL
        record->prepare_time = objspace->profile.prepare_time;
#endif
        record->gc_time = 0;
        record->gc_invoke_time = getrusage_time();
        objspace->profile.gc_wall_start_time = rb_hrtime_now();
    }
}

static double
elapsed_time_from(double time)
{
    double now = getrusage_time();
    if (now > time) {
        return now - time;
    }
    else {
        return 0;
    }
}

static inline void
gc_prof_timer_stop(rb_objspace_t *objspace)
{
    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->gc_time = elapsed_time_from(record->gc_invoke_time);
        record->gc_invoke_time -= objspace->profile.invoke_time;
        record->gc_wall_time = elapsed_hrtime_from(objspace->profile.gc_wall_start_time);
    }
}

static inline void
gc_prof_mark_timer_start(rb_objspace_t *objspace)
{
    RUBY_DTRACE_GC_HOOK(MARK_BEGIN);
#if GC_PROFILE_MORE_DETAIL
    if (gc_prof_enabled(objspace)) {
        gc_prof_record(objspace)->gc_mark_time = getrusage_time();
    }
#endif
}

static inline void
gc_prof_mark_timer_stop(rb_objspace_t *objspace)
{
    RUBY_DTRACE_GC_HOOK(MARK_END);
#if GC_PROFILE_MORE_DETAIL
    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->gc_mark_time = elapsed_time_from(record->gc_mark_time);
    }
#endif
}

static inline void
gc_prof_sweep_timer_start(rb_objspace_t *objspace)
{
    RUBY_DTRACE_GC_HOOK(SWEEP_BEGIN);
    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);

        if (record->gc_time > 0 || GC_PROFILE_MORE_DETAIL) {
            objspace->profile.gc_sweep_start_time = getrusage_time();
            objspace->profile.gc_sweep_wall_start_time = rb_hrtime_now();
        }
    }
}

static inline void
gc_prof_sweep_timer_stop(rb_objspace_t *objspace)
{
    RUBY_DTRACE_GC_HOOK(SWEEP_END);

    if (gc_prof_enabled(objspace)) {
        double sweep_time;
        gc_profile_record *record = gc_prof_record(objspace);

        if (record->gc_time > 0) {
            sweep_time = elapsed_time_from(objspace->profile.gc_sweep_start_time);
            /* need to accumulate GC time for lazy sweep after gc() */
            record->gc_time += sweep_time;
            record->gc_wall_time = rb_hrtime_add(record->gc_wall_time,
                    elapsed_hrtime_from(objspace->profile.gc_sweep_wall_start_time));
        }
        else if (GC_PROFILE_MORE_DETAIL) {
            sweep_time = elapsed_time_from(objspace->profile.gc_sweep_start_time);
        }

#if GC_PROFILE_MORE_DETAIL
        record->gc_sweep_time += sweep_time;
        if (heap_pages_deferred_final) record->flags |= GPR_FLAG_HAVE_FINALIZE;
#endif
        if (heap_pages_deferred_final) objspace->profile.latest_gc_info |= GPR_FLAG_HAVE_FINALIZE;
    }
}

static inline void
gc_prof_set_malloc_info(rb_objspace_t *objspace)
{
#if GC_PROFILE_MORE_DETAIL
    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->allocate_increase = malloc_increase;
        record->allocate_limit = malloc_limit;
    }
#endif
}

static inline void
gc_prof_set_heap_info(rb_objspace_t *objspace)
{
    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);

        /* Sum across all size pools since each has a different slot size. */
        size_t total = 0;
        size_t use_size = 0;
        size_t total_size = 0;
        for (int i = 0; i < HEAP_COUNT; i++) {
            rb_heap_t *heap = &heaps[i];
            size_t heap_live = heap->total_allocated_objects - heap->total_freed_objects - heap->final_slots_count;
            total += heap->total_slots;
            use_size += heap_live * heap->slot_size;
            total_size += heap->total_slots * heap->slot_size;
        }

#if GC_PROFILE_MORE_DETAIL
        size_t live = objspace->profile.total_allocated_objects_at_gc_start - total_freed_objects(objspace);
        record->heap_use_pages = objspace->profile.heap_used_at_gc_start;
        record->heap_live_objects = live;
        record->heap_free_objects = total - live;
#endif

        record->heap_total_objects = total;
        record->heap_use_size = use_size;
        record->heap_total_size = total_size;
    }
}

/*
 *  call-seq:
 *    GC::Profiler.clear          -> nil
 *
 *  Clears the \GC profiler data.
 *
 */

static VALUE
gc_profile_clear(VALUE _)
{
    rb_objspace_t *objspace = rb_gc_get_objspace();
    gc_profile_records_free(objspace);
    return Qnil;
}

/*
 *  call-seq:
 *     GC::Profiler.configure(max_records: 4096) -> nil
 *
 *  Configures how many raw profile records are retained by
 *  GC::Profiler.raw_data.
 *
 *  The profiler keeps at most +max_records+ records in a bounded ring buffer.
 *  When the buffer is full, newer GC records overwrite the oldest retained
 *  records.  The default limit is 4096 records.
 *
 *  Pass +nil+ to restore the historical unbounded behavior:
 *
 *    GC::Profiler.configure(max_records: nil)
 *
 *  Changing +max_records+ clears existing raw profile data.  This method does
 *  not enable or disable the profiler; use GC::Profiler.enable and
 *  GC::Profiler.disable for that.
 */

static VALUE
gc_profile_configure(int argc, VALUE *argv, VALUE _)
{
    static ID keywords[1] = {0};
    VALUE options, max_records;
    rb_objspace_t *objspace = rb_gc_get_objspace();

    if (!keywords[0]) {
        keywords[0] = rb_intern("max_records");
    }

    rb_scan_args_kw(rb_keyword_given_p(), argc, argv, ":", &options);
    rb_get_kwargs(options, keywords, 0, 1, &max_records);

    if (max_records == Qundef) {
        return Qnil;
    }
    else if (NIL_P(max_records)) {
        objspace->profile.max_records = GC_PROFILE_RECORD_UNBOUNDED;
    }
    else {
        long value = NUM2LONG(max_records);
        if (value <= 0) {
            rb_raise(rb_eArgError, "max_records must be positive or nil");
        }
        objspace->profile.max_records = (size_t)value;
    }

    gc_profile_records_free(objspace);
    return Qnil;
}

/*
 *  call-seq:
 *     GC::Profiler.raw_data(limit: nil, since: nil) -> [Hash, ...]
 *
 *  Returns an Array of retained raw profile data Hashes ordered from earliest
 *  to latest by +:GC_INVOKE_TIME+.  +limit:+ returns at most the newest
 *  retained records.  +since:+ returns records with +:GC_SEQUENCE+ greater
 *  than the given sequence.
 *
 *  For example:
 *
 *    [
 *	{
 *	   :GC_TIME=>1.3000000000000858e-05,
 *	   :GC_INVOKE_TIME=>0.010634999999999999,
 *	   :GC_WALL_TIME=>1.4000000000000001e-05,
 *	   :GC_INVOKE_WALL_TIME=>0.010640000000000000,
 *	   :GC_PAUSE_TIME=>1.5000000000000000e-05,
 *	   :GC_STOP_TIME=>1.0000000000000000e-06,
 *	   :GC_STW_TIME=>1.4000000000000001e-05,
 *	   :GC_MARK_WALL_TIME=>9.0000000000000002e-06,
 *	   :GC_SWEEP_WALL_TIME=>5.0000000000000004e-06,
 *	   :GC_COMPACT_WALL_TIME=>0.0000000000000000e+00,
 *	   :HEAP_USE_SIZE=>289640,
 *	   :HEAP_TOTAL_SIZE=>588960,
 *	   :HEAP_TOTAL_OBJECTS=>14724,
 *	   :GC_IS_MARKED=>false
 *	},
 *      # ...
 *    ]
 *
 *  The keys mean:
 *
 *  +:GC_SEQUENCE+::
 *	Monotonically increasing sequence number for this profiler record.
 *  +:GC_TIME+::
 *	CPU time elapsed in seconds for this GC run.  This is process CPU time,
 *	not elapsed wall-clock time.
 *  +:GC_INVOKE_TIME+::
 *	CPU time elapsed in seconds from startup to when the GC was invoked.
 *  +:GC_WALL_TIME+::
 *	Monotonic wall-clock counterpart to +:GC_TIME+ for this GC record.
 *	This does not include time spent stopping other ractors before the VM
 *	enters GC.  Use the phase wall-clock fields below for mark, sweep, and
 *	compaction attribution.
 *  +:GC_INVOKE_WALL_TIME+::
 *	Monotonic wall-clock time elapsed in seconds from startup to when the GC
 *	was invoked.
 *  +:GC_PAUSE_TIME+::
 *	Monotonic wall-clock time elapsed in seconds while user execution was
 *	blocked by this GC entry, including time to stop other ractors.  This
 *	may include time from incremental marking or lazy sweeping continuation
 *	charged to this record.
 *  +:GC_STOP_TIME+::
 *	Monotonic wall-clock time elapsed in seconds stopping other ractors.
 *  +:GC_STW_TIME+::
 *	Monotonic wall-clock time elapsed in seconds after other ractors have
 *	stopped and before the VM exits GC.
 *  +:GC_MARK_WALL_TIME+::
 *	Monotonic wall-clock time elapsed in seconds spent marking for this GC
 *	record, accumulated across incremental marking continuations.
 *  +:GC_SWEEP_WALL_TIME+::
 *	Monotonic wall-clock time elapsed in seconds spent sweeping for this GC
 *	record, accumulated across lazy sweeping continuations.  This does not
 *	include compaction time, which is reported separately as
 *	+:GC_COMPACT_WALL_TIME+.
 *  +:GC_COMPACT_WALL_TIME+::
 *	Monotonic wall-clock time elapsed in seconds spent compacting for this GC
 *	record, or +0.0+ if this GC did not compact.
 *  +:HEAP_USE_SIZE+::
 *	Total bytes of heap used
 *  +:HEAP_TOTAL_SIZE+::
 *	Total size of heap in bytes
 *  +:HEAP_TOTAL_OBJECTS+::
 *	Total number of objects
 *  +:GC_IS_MARKED+::
 *	Returns +true+ if the GC is in mark phase
 *
 *  The wall-clock timing fields relate to each other as follows:
 *
 *    GC_PAUSE_TIME == GC_STOP_TIME + GC_STW_TIME
 *
 *  +:GC_MARK_WALL_TIME+, +:GC_SWEEP_WALL_TIME+, and +:GC_COMPACT_WALL_TIME+
 *  report separate phase timings and must not be added to +:GC_WALL_TIME+.
 *
 *  +:GC_WALL_TIME+ is the wall-clock counterpart to +:GC_TIME+ and is nested
 *  inside +:GC_STW_TIME+, so it must not be added to +:GC_STW_TIME+.  The difference
 *  +GC_STW_TIME - GC_WALL_TIME+ is VM overhead inside the stopped interval
 *  (GC event hooks, bookkeeping, consistency checks, and continuation work).
 *
 *  If ruby was built with +GC_PROFILE_MORE_DETAIL+, you will also have access
 *  to the following hash keys:
 *
 *  +:GC_MARK_TIME+::
 *  +:GC_SWEEP_TIME+::
 *  +:ALLOCATE_INCREASE+::
 *  +:ALLOCATE_LIMIT+::
 *  +:HEAP_USE_PAGES+::
 *  +:HEAP_LIVE_OBJECTS+::
 *  +:HEAP_FREE_OBJECTS+::
 *  +:HAVE_FINALIZE+::
 *
 */

static VALUE
gc_profile_record_get(int argc, VALUE *argv, VALUE _)
{
    static ID keywords[2] = {0};
    VALUE prof, options, limit_value, since_value;
    VALUE gc_profile = rb_ary_new();
    size_t i, count, matching = 0, skip = 0, limit = SIZE_MAX, since = 0;
    bool use_since = false;
    rb_objspace_t *objspace = rb_gc_get_objspace();

    if (!keywords[0]) {
        keywords[0] = rb_intern("limit");
        keywords[1] = rb_intern("since");
    }

    rb_scan_args_kw(rb_keyword_given_p(), argc, argv, ":", &options);
    VALUE values[2] = {Qundef, Qundef};
    rb_get_kwargs(options, keywords, 0, 2, values);
    limit_value = values[0];
    since_value = values[1];

    if (limit_value != Qundef && !NIL_P(limit_value)) {
        long value = NUM2LONG(limit_value);
        if (value < 0) {
            rb_raise(rb_eArgError, "limit must be non-negative");
        }
        limit = (size_t)value;
    }
    if (since_value != Qundef && !NIL_P(since_value)) {
        long value = NUM2LONG(since_value);
        if (value < 0) {
            rb_raise(rb_eArgError, "since must be non-negative");
        }
        since = (size_t)value;
        use_since = true;
    }

    if (!objspace->profile.run) {
        return Qnil;
    }

    count = gc_profile_record_count(objspace);
    for (i = 0; i < count; i++) {
        gc_profile_record *record = &objspace->profile.records[gc_profile_record_index(objspace, i)];
        if (!use_since || record->sequence > since) {
            matching++;
        }
    }
    if (limit < matching) {
        skip = matching - limit;
    }

    for (i = 0; i < count; i++) {
        gc_profile_record *record = &objspace->profile.records[gc_profile_record_index(objspace, i)];
        if (use_since && record->sequence <= since) {
            continue;
        }
        if (skip > 0) {
            skip--;
            continue;
        }

        prof = rb_hash_new();
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_FLAGS")), gc_info_decode(objspace, rb_hash_new(), record->flags));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_SEQUENCE")), SIZET2NUM(record->sequence));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_TIME")), DBL2NUM(record->gc_time));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_INVOKE_TIME")), DBL2NUM(record->gc_invoke_time));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_WALL_TIME")),
                DBL2NUM(hrtime_to_sec(record->gc_wall_time)));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_INVOKE_WALL_TIME")),
                DBL2NUM(hrtime_to_sec(record->gc_invoke_wall_time)));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_PAUSE_TIME")),
                DBL2NUM(hrtime_to_sec(record->gc_pause_time)));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_STOP_TIME")),
                DBL2NUM(hrtime_to_sec(record->gc_stop_time)));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_STW_TIME")),
                DBL2NUM(hrtime_to_sec(record->gc_stw_time)));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_MARK_WALL_TIME")),
                DBL2NUM(hrtime_to_sec(record->gc_mark_wall_time)));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_SWEEP_WALL_TIME")),
                DBL2NUM(hrtime_to_sec(record->gc_sweep_wall_time)));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_COMPACT_WALL_TIME")),
                DBL2NUM(hrtime_to_sec(record->gc_compact_wall_time)));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_USE_SIZE")), SIZET2NUM(record->heap_use_size));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_TOTAL_SIZE")), SIZET2NUM(record->heap_total_size));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_TOTAL_OBJECTS")), SIZET2NUM(record->heap_total_objects));
        rb_hash_aset(prof, ID2SYM(rb_intern("MOVED_OBJECTS")), SIZET2NUM(record->moved_objects));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_IS_MARKED")), Qtrue);
#if GC_PROFILE_MORE_DETAIL
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_MARK_TIME")), DBL2NUM(record->gc_mark_time));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_SWEEP_TIME")), DBL2NUM(record->gc_sweep_time));
        rb_hash_aset(prof, ID2SYM(rb_intern("ALLOCATE_INCREASE")), SIZET2NUM(record->allocate_increase));
        rb_hash_aset(prof, ID2SYM(rb_intern("ALLOCATE_LIMIT")), SIZET2NUM(record->allocate_limit));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_USE_PAGES")), SIZET2NUM(record->heap_use_pages));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_LIVE_OBJECTS")), SIZET2NUM(record->heap_live_objects));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_FREE_OBJECTS")), SIZET2NUM(record->heap_free_objects));

        rb_hash_aset(prof, ID2SYM(rb_intern("REMOVING_OBJECTS")), SIZET2NUM(record->removing_objects));
        rb_hash_aset(prof, ID2SYM(rb_intern("EMPTY_OBJECTS")), SIZET2NUM(record->empty_objects));

        rb_hash_aset(prof, ID2SYM(rb_intern("HAVE_FINALIZE")), (record->flags & GPR_FLAG_HAVE_FINALIZE) ? Qtrue : Qfalse);
#endif

#if RGENGC_PROFILE > 0
        rb_hash_aset(prof, ID2SYM(rb_intern("OLD_OBJECTS")), SIZET2NUM(record->old_objects));
        rb_hash_aset(prof, ID2SYM(rb_intern("REMEMBERED_NORMAL_OBJECTS")), SIZET2NUM(record->remembered_normal_objects));
        rb_hash_aset(prof, ID2SYM(rb_intern("REMEMBERED_SHADY_OBJECTS")), SIZET2NUM(record->remembered_shady_objects));
#endif
        rb_ary_push(gc_profile, prof);
    }

    return gc_profile;
}

#if GC_PROFILE_MORE_DETAIL
#define MAJOR_REASON_MAX 0x10

static char *
gc_profile_dump_major_reason(unsigned int flags, char *buff)
{
    unsigned int reason = flags & GPR_FLAG_MAJOR_MASK;
    int i = 0;

    if (reason == GPR_FLAG_NONE) {
        buff[0] = '-';
        buff[1] = 0;
    }
    else {
#define C(x, s) \
  if (reason & GPR_FLAG_MAJOR_BY_##x) { \
      buff[i++] = #x[0]; \
      if (i >= MAJOR_REASON_MAX) rb_bug("gc_profile_dump_major_reason: overflow"); \
      buff[i] = 0; \
  }
        C(NOFREE, N);
        C(OLDGEN, O);
        C(SHADY,  S);
#if RGENGC_ESTIMATE_OLDMALLOC
        C(OLDMALLOC, M);
#endif
#undef C
    }
    return buff;
}
#endif



static void
gc_profile_dump_on(VALUE out, VALUE (*append)(VALUE, VALUE))
{
    rb_objspace_t *objspace = rb_gc_get_objspace();
    size_t count = gc_profile_record_count(objspace);
#ifdef MAJOR_REASON_MAX
    char reason_str[MAJOR_REASON_MAX];
#endif

    if (objspace->profile.run && count /* > 1 */) {
        size_t i;
        const gc_profile_record *record;

        append(out, rb_sprintf("GC %"PRIuSIZE" invokes.\n", objspace->profile.count));
        append(out, rb_str_new_cstr("Index    Invoke Time(sec)       Use Size(byte)     Total Size(byte)         Total Object                    GC Time(ms)\n"));

        for (i = 0; i < count; i++) {
            record = &objspace->profile.records[gc_profile_record_index(objspace, i)];
            append(out, rb_sprintf("%5"PRIuSIZE" %19.3f %20"PRIuSIZE" %20"PRIuSIZE" %20"PRIuSIZE" %30.20f\n",
                                   i+1, record->gc_invoke_time, record->heap_use_size,
                                   record->heap_total_size, record->heap_total_objects, record->gc_time*1000));
        }

#if GC_PROFILE_MORE_DETAIL
        const char *str = "\n\n" \
                                    "More detail.\n" \
                                    "Prepare Time = Previously GC's rest sweep time\n"
                                    "Index Flags          Allocate Inc.  Allocate Limit"
#if CALC_EXACT_MALLOC_SIZE
                                    "  Allocated Size"
#endif
                                    "  Use Page     Mark Time(ms)    Sweep Time(ms)  Prepare Time(ms)  LivingObj    FreeObj RemovedObj   EmptyObj"
#if RGENGC_PROFILE
                                    " OldgenObj RemNormObj RemShadObj"
#endif
#if GC_PROFILE_DETAIL_MEMORY
                                    " MaxRSS(KB) MinorFLT MajorFLT"
#endif
                                    "\n";
        append(out, rb_str_new_cstr(str));

        for (i = 0; i < count; i++) {
            record = &objspace->profile.records[gc_profile_record_index(objspace, i)];
            append(out, rb_sprintf("%5"PRIuSIZE" %4s/%c/%6s%c %13"PRIuSIZE" %15"PRIuSIZE
#if CALC_EXACT_MALLOC_SIZE
                                   " %15"PRIuSIZE
#endif
                                   " %9"PRIuSIZE" %17.12f %17.12f %17.12f %10"PRIuSIZE" %10"PRIuSIZE" %10"PRIuSIZE" %10"PRIuSIZE
#if RGENGC_PROFILE
                                   "%10"PRIuSIZE" %10"PRIuSIZE" %10"PRIuSIZE
#endif
#if GC_PROFILE_DETAIL_MEMORY
                                   "%11ld %8ld %8ld"
#endif

                                   "\n",
                                   i+1,
                                   gc_profile_dump_major_reason(record->flags, reason_str),
                                   (record->flags & GPR_FLAG_HAVE_FINALIZE) ? 'F' : '.',
                                   (record->flags & GPR_FLAG_NEWOBJ) ? "NEWOBJ" :
                                   (record->flags & GPR_FLAG_MALLOC) ? "MALLOC" :
                                   (record->flags & GPR_FLAG_METHOD) ? "METHOD" :
                                   (record->flags & GPR_FLAG_CAPI)   ? "CAPI__" : "??????",
                                   (record->flags & GPR_FLAG_STRESS) ? '!' : ' ',
                                   record->allocate_increase, record->allocate_limit,
#if CALC_EXACT_MALLOC_SIZE
                                   record->allocated_size,
#endif
                                   record->heap_use_pages,
                                   record->gc_mark_time*1000,
                                   record->gc_sweep_time*1000,
                                   record->prepare_time*1000,

                                   record->heap_live_objects,
                                   record->heap_free_objects,
                                   record->removing_objects,
                                   record->empty_objects
#if RGENGC_PROFILE
                                   ,
                                   record->old_objects,
                                   record->remembered_normal_objects,
                                   record->remembered_shady_objects
#endif
#if GC_PROFILE_DETAIL_MEMORY
                                   ,
                                   record->maxrss / 1024,
                                   record->minflt,
                                   record->majflt
#endif

                       ));
        }
#endif
    }
}

/*
 *  call-seq:
 *     GC::Profiler.result  -> String
 *
 *  Returns a profile data report such as:
 *
 *    GC 1 invokes.
 *    Index    Invoke Time(sec)       Use Size(byte)     Total Size(byte)         Total Object                    GC time(ms)
 *        1               0.012               159240               212940                10647         0.00000000000001530000
 */

static VALUE
gc_profile_result(VALUE _)
{
    VALUE str = rb_str_buf_new(0);
    gc_profile_dump_on(str, rb_str_buf_append);
    return str;
}

/*
 *  call-seq:
 *     GC::Profiler.report
 *     GC::Profiler.report(io)
 *
 *  Writes the GC::Profiler.result to <tt>$stdout</tt> or the given IO object.
 *
 */

static VALUE
gc_profile_report(int argc, VALUE *argv, VALUE self)
{
    VALUE out;

    out = (!rb_check_arity(argc, 0, 1) ? rb_stdout : argv[0]);
    gc_profile_dump_on(out, rb_io_write);

    return Qnil;
}

/*
 *  call-seq:
 *     GC::Profiler.total_time	-> float
 *
 *  The total time used for garbage collection in seconds
 */

static VALUE
gc_profile_total_time(VALUE self)
{
    double time = 0;
    rb_objspace_t *objspace = rb_gc_get_objspace();

    if (objspace->profile.run && gc_profile_record_count(objspace) > 0) {
        size_t i;
        size_t count = gc_profile_record_count(objspace);

        for (i = 0; i < count; i++) {
            time += objspace->profile.records[gc_profile_record_index(objspace, i)].gc_time;
        }
    }
    return DBL2NUM(time);
}

/*
 *  call-seq:
 *    GC::Profiler.enabled?	-> true or false
 *
 *  The current status of \GC profile mode.
 */

static VALUE
gc_profile_enable_get(VALUE self)
{
    rb_objspace_t *objspace = rb_gc_get_objspace();
    return objspace->profile.run ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    GC::Profiler.enable	-> nil
 *
 *  Starts the \GC profiler.
 *
 */

static VALUE
gc_profile_enable(VALUE _)
{
    rb_objspace_t *objspace = rb_gc_get_objspace();
    objspace->profile.run = TRUE;
    objspace->profile.current_record = 0;
    return Qnil;
}

/*
 *  call-seq:
 *    GC::Profiler.disable	-> nil
 *
 *  Stops the \GC profiler.
 *
 */

static VALUE
gc_profile_disable(VALUE _)
{
    rb_objspace_t *objspace = rb_gc_get_objspace();

    objspace->profile.run = FALSE;
    objspace->profile.current_record = 0;
    return Qnil;
}

static void
rb_gc_verify_internal_consistency(void)
{
    gc_verify_internal_consistency(rb_gc_get_objspace());
}

/*
 *  call-seq:
 *     GC.verify_internal_consistency                  -> nil
 *
 *  Verify internal consistency.
 *
 *  This method is implementation specific.
 *  Now this method checks generational consistency
 *  if RGenGC is supported.
 */
static VALUE
gc_verify_internal_consistency_m(VALUE dummy)
{
    rb_gc_verify_internal_consistency();
    return Qnil;
}

#if GC_CAN_COMPILE_COMPACTION
/*
 *  call-seq:
 *     GC.auto_compact = flag
 *
 *  Updates automatic compaction mode.
 *
 *  When enabled, the compactor will execute on every major collection.
 *
 *  Enabling compaction will degrade performance on major collections.
 */
static VALUE
gc_set_auto_compact(VALUE _, VALUE v)
{
    GC_ASSERT(GC_COMPACTION_SUPPORTED);

    ruby_enable_autocompact = RTEST(v);

#if RGENGC_CHECK_MODE
    ruby_autocompact_compare_func = NULL;

    if (SYMBOL_P(v)) {
        ID id = RB_SYM2ID(v);
        if (id == rb_intern("empty")) {
            ruby_autocompact_compare_func = compare_free_slots;
        }
    }
#endif

    return v;
}
#else
#  define gc_set_auto_compact rb_f_notimplement
#endif

#if GC_CAN_COMPILE_COMPACTION
/*
 *  call-seq:
 *     GC.auto_compact    -> true or false
 *
 *  Returns whether or not automatic compaction has been enabled.
 */
static VALUE
gc_get_auto_compact(VALUE _)
{
    return ruby_enable_autocompact ? Qtrue : Qfalse;
}
#else
#  define gc_get_auto_compact rb_f_notimplement
#endif

#if GC_CAN_COMPILE_COMPACTION
/*
 *  call-seq:
 *     GC.latest_compact_info -> hash
 *
 * Returns information about object moved in the most recent \GC compaction.
 *
 * The returned +hash+ contains the following keys:
 *
 * [considered]
 *   Hash containing the type of the object as the key and the number of
 *   objects of that type that were considered for movement.
 * [moved]
 *   Hash containing the type of the object as the key and the number of
 *   objects of that type that were actually moved.
 * [moved_up]
 *   Hash containing the type of the object as the key and the number of
 *   objects of that type that were increased in size.
 * [moved_down]
 *   Hash containing the type of the object as the key and the number of
 *   objects of that type that were decreased in size.
 *
 * Some objects can't be moved (due to pinning) so these numbers can be used to
 * calculate compaction efficiency.
 */
static VALUE
gc_compact_stats(VALUE self)
{
    rb_objspace_t *objspace = rb_gc_get_objspace();
    VALUE h = rb_hash_new();
    VALUE considered = rb_hash_new();
    VALUE moved = rb_hash_new();
    VALUE moved_up = rb_hash_new();
    VALUE moved_down = rb_hash_new();

    for (size_t i = 0; i < T_MASK; i++) {
        if (objspace->rcompactor.considered_count_table[i]) {
            rb_hash_aset(considered, type_sym(i), SIZET2NUM(objspace->rcompactor.considered_count_table[i]));
        }

        if (objspace->rcompactor.moved_count_table[i]) {
            rb_hash_aset(moved, type_sym(i), SIZET2NUM(objspace->rcompactor.moved_count_table[i]));
        }

        if (objspace->rcompactor.moved_up_count_table[i]) {
            rb_hash_aset(moved_up, type_sym(i), SIZET2NUM(objspace->rcompactor.moved_up_count_table[i]));
        }

        if (objspace->rcompactor.moved_down_count_table[i]) {
            rb_hash_aset(moved_down, type_sym(i), SIZET2NUM(objspace->rcompactor.moved_down_count_table[i]));
        }
    }

    rb_hash_aset(h, ID2SYM(rb_intern("considered")), considered);
    rb_hash_aset(h, ID2SYM(rb_intern("moved")), moved);
    rb_hash_aset(h, ID2SYM(rb_intern("moved_up")), moved_up);
    rb_hash_aset(h, ID2SYM(rb_intern("moved_down")), moved_down);

    return h;
}
#else
#  define gc_compact_stats rb_f_notimplement
#endif

#if GC_CAN_COMPILE_COMPACTION
/*
 *  call-seq:
 *     GC.compact -> hash
 *
 * This function compacts objects together in Ruby's heap. It eliminates
 * unused space (or fragmentation) in the heap by moving objects in to that
 * unused space.
 *
 * The returned +hash+ contains statistics about the objects that were moved;
 * see GC.latest_compact_info.
 *
 * This method is only expected to work on CRuby.
 *
 * To test whether \GC compaction is supported, use the idiom:
 *
 *   GC.respond_to?(:compact)
 */
static VALUE
gc_compact(VALUE self)
{
    rb_objspace_t *objspace = rb_gc_get_objspace();
    int full_marking_p = gc_config_full_mark_val;
    gc_config_full_mark_set(TRUE);

    /* Run GC with compaction enabled */
    rb_gc_impl_start(rb_gc_get_objspace(), true, true, true, true);
    gc_config_full_mark_set(full_marking_p);

    return gc_compact_stats(self);
}
#else
#  define gc_compact rb_f_notimplement
#endif

#if GC_CAN_COMPILE_COMPACTION
struct desired_compaction_pages_i_data {
    rb_objspace_t *objspace;
    size_t required_slots[HEAP_COUNT];
};

static int
desired_compaction_pages_i(struct heap_page *page, void *data)
{
    struct desired_compaction_pages_i_data *tdata = data;
    rb_objspace_t *objspace = tdata->objspace;
    VALUE vstart = (VALUE)page->start;
    VALUE vend = vstart + (VALUE)(page->total_slots * page->heap->slot_size);


    for (VALUE v = vstart; v != vend; v += page->heap->slot_size) {
        asan_unpoisoning_object(v) {
            /* skip T_NONEs; they won't be moved */
            if (BUILTIN_TYPE(v) != T_NONE) {
                rb_heap_t *dest_pool = gc_compact_destination_pool(objspace, page->heap, v);
                size_t dest_pool_idx = dest_pool - heaps;
                tdata->required_slots[dest_pool_idx]++;
            }
        }
    }

    return 0;
}

/* call-seq:
 *    GC.verify_compaction_references(toward: nil, double_heap: false) -> hash
 *
 * Verify compaction reference consistency.
 *
 * This method is implementation specific.  During compaction, objects that
 * were moved are replaced with T_MOVED objects.  No object should have a
 * reference to a T_MOVED object after compaction.
 *
 * This function expands the heap to ensure room to move all objects,
 * compacts the heap to make sure everything moves, updates all references,
 * then performs a full \GC.  If any object contains a reference to a T_MOVED
 * object, that object should be pushed on the mark stack, and will
 * make a SEGV.
 */
static VALUE
gc_verify_compaction_references(int argc, VALUE* argv, VALUE self)
{
    static ID keywords[3] = {0};
    if (!keywords[0]) {
        keywords[0] = rb_intern("toward");
        keywords[1] = rb_intern("double_heap");
        keywords[2] = rb_intern("expand_heap");
    }

    VALUE options;
    rb_scan_args_kw(rb_keyword_given_p(), argc, argv, ":", &options);

    VALUE arguments[3] = { Qnil, Qfalse, Qfalse };
    int kwarg_count = rb_get_kwargs(options, keywords, 0, 3, arguments);
    bool toward_empty = kwarg_count > 0 && SYMBOL_P(arguments[0]) && SYM2ID(arguments[0]) == rb_intern("empty");
    bool expand_heap = (kwarg_count > 1 && RTEST(arguments[1])) || (kwarg_count > 2 && RTEST(arguments[2]));

    rb_objspace_t *objspace = rb_gc_get_objspace();

    /* compaction は per-Ractor objspace では走らない（rb_gc_impl_start 参照）。検証全体を
     * （heap 拡張と moved-reference walk も含め）GC.compact と同様に素の full GC へ降格する。 */
    if (!rb_gc_single_objspace_p()) {
        rb_gc_impl_start(objspace, true, true, true, false);
        return gc_compact_stats(self);
    }

    /* Clear the heap. */
    rb_gc_impl_start(objspace, true, true, true, false);

    unsigned int lev = RB_GC_VM_LOCK();
    {
        gc_rest(objspace);

        /* if both double_heap and expand_heap are set, expand_heap takes precedence */
        if (expand_heap) {
            struct desired_compaction_pages_i_data desired_compaction = {
                .objspace = objspace,
                .required_slots = {0},
            };
            /* Work out how many objects want to be in each size pool, taking account of moves */
            objspace_each_pages(objspace, desired_compaction_pages_i, &desired_compaction, TRUE);

            /* Find out which pool has the most pages */
            size_t max_existing_pages = 0;
            for (int i = 0; i < HEAP_COUNT; i++) {
                rb_heap_t *heap = &heaps[i];
                max_existing_pages = MAX(max_existing_pages, heap->total_pages);
            }

            /* Add pages to each size pool so that compaction is guaranteed to move every object */
            for (int i = 0; i < HEAP_COUNT; i++) {
                rb_heap_t *heap = &heaps[i];

                size_t pages_to_add = 0;
                /*
                 * Step 1: Make sure every pool has the same number of pages, by adding empty pages
                 * to smaller pools. This is required to make sure the compact cursor can advance
                 * through all of the pools in `gc_sweep_compact` without hitting the "sweep &
                 * compact cursors met" condition on some pools before fully compacting others
                 */
                pages_to_add += max_existing_pages - heap->total_pages;
                /*
                 * Step 2: Now add additional free pages to each size pool sufficient to hold all objects
                 * that want to be in that size pool, whether moved into it or moved within it
                 */
                objspace->heap_pages.allocatable_bytes = desired_compaction.required_slots[i] * heap->slot_size;
                while (objspace->heap_pages.allocatable_bytes > 0) {
                    heap_page_allocate_and_initialize(objspace, heap);
                }
                /*
                 * Step 3: Add two more pages so that the compact & sweep cursors will meet _after_ all objects
                 * have been moved, and not on the last iteration of the `gc_sweep_compact` loop
                 */
                pages_to_add += 2;

                for (; pages_to_add > 0; pages_to_add--) {
                    heap_page_allocate_and_initialize_force(objspace, heap);
                }
            }
        }

        if (toward_empty) {
            objspace->rcompactor.compare_func = compare_free_slots;
        }
    }
    RB_GC_VM_UNLOCK(lev);

    rb_gc_impl_start(rb_gc_get_objspace(), true, true, true, true);

    rb_objspace_reachable_objects_from_root(root_obj_check_moved_i, objspace);
    objspace_each_objects(objspace, heap_check_moved_i, objspace, TRUE);

    objspace->rcompactor.compare_func = NULL;

    return gc_compact_stats(self);
}
#else
# define gc_verify_compaction_references rb_f_notimplement
#endif

void
rb_gc_impl_objspace_free(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (is_lazy_sweeping(objspace))
        rb_bug("lazy sweeping underway when freeing object space");

    free(objspace->profile.records);
    objspace->profile.records = NULL;

    for (size_t i = 0; i < rb_darray_size(objspace->heap_pages.sorted); i++) {
        heap_page_free(objspace, rb_darray_get(objspace->heap_pages.sorted, i));
    }
    rb_darray_free_without_gc(objspace->heap_pages.sorted);
    heap_pages_lomem = 0;
    heap_pages_himem = 0;

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];
        heap->total_pages = 0;
        heap->total_slots = 0;
    }

    free_stack_chunks(&objspace->mark_stack);
    mark_stack_free_cache(&objspace->mark_stack);

    rb_darray_free_without_gc(objspace->weak_references);

#ifdef MALLOC_COUNTERS_NEED_LOCK
    rb_native_mutex_destroy(&objspace->malloc_counters.lock);
#endif

    free(objspace);
}

#if MALLOC_ALLOCATED_SIZE
/*
 *  call-seq:
 *     GC.malloc_allocated_size -> Integer
 *
 *  Returns the size of memory allocated by malloc().
 *
 *  Only available if ruby was built with +CALC_EXACT_MALLOC_SIZE+.
 */

static VALUE
gc_malloc_allocated_size(VALUE self)
{
    rb_objspace_t *objspace = (rb_objspace_t *)rb_gc_get_objspace();
    return ULL2NUM(objspace->malloc_params.allocated_size);
}

/*
 *  call-seq:
 *     GC.malloc_allocations -> Integer
 *
 *  Returns the number of malloc() allocations.
 *
 *  Only available if ruby was built with +CALC_EXACT_MALLOC_SIZE+.
 */

static VALUE
gc_malloc_allocations(VALUE self)
{
    rb_objspace_t *objspace = (rb_objspace_t *)rb_gc_get_objspace();
    return ULL2NUM(objspace->malloc_params.allocations);
}
#endif

void
rb_gc_impl_before_fork(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    objspace->fork_vm_lock_lev = RB_GC_VM_LOCK();
    rb_gc_vm_barrier();
}

void
rb_gc_impl_after_fork(void *objspace_ptr, rb_pid_t pid)
{
    rb_objspace_t *objspace = objspace_ptr;

    RB_GC_VM_UNLOCK(objspace->fork_vm_lock_lev);
    objspace->fork_vm_lock_lev = 0;

    if (pid == 0) { /* child process */
        heap_alloc_state_clear(objspace);
        /* fork した Ractor が子プロセスの main Ractor になる。 */
        rlgc_main_objspace = objspace;
    }
}

VALUE rb_ident_hash_new_with_size(st_index_t size);

#if GC_DEBUG_STRESS_TO_CLASS
/*
 *  call-seq:
 *    GC.add_stress_to_class(class[, ...])
 *
 *  Raises NoMemoryError when allocating an instance of the given classes.
 *
 */
static VALUE
rb_gcdebug_add_stress_to_class(int argc, VALUE *argv, VALUE self)
{
    rb_objspace_t *objspace = rb_gc_get_objspace();

    if (!stress_to_class) {
        set_stress_to_class(rb_ident_hash_new_with_size(argc));
    }

    for (int i = 0; i < argc; i++) {
        VALUE klass = argv[i];
        rb_hash_aset(stress_to_class, klass, Qtrue);
    }

    return self;
}

/*
 *  call-seq:
 *    GC.remove_stress_to_class(class[, ...])
 *
 *  No longer raises NoMemoryError when allocating an instance of the
 *  given classes.
 *
 */
static VALUE
rb_gcdebug_remove_stress_to_class(int argc, VALUE *argv, VALUE self)
{
    rb_objspace_t *objspace = rb_gc_get_objspace();

    if (stress_to_class) {
        for (int i = 0; i < argc; ++i) {
            rb_hash_delete(stress_to_class, argv[i]);
        }

        if (rb_hash_size(stress_to_class) == 0) {
            stress_to_class = 0;
        }
    }

    return Qnil;
}
#endif

void *
rb_gc_impl_objspace_alloc(void)
{
    global_objspace_init();

    rb_objspace_t *objspace = calloc1(sizeof(rb_objspace_t));

    return objspace;
}

void
rb_gc_impl_objspace_init(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    gc_config_full_mark_set(TRUE);

    objspace->flags.measure_gc = true;
    malloc_limit = gc_params.malloc_limit_min;
    objspace->rlgc.shareable_objects_limit = RLGC_SHAREABLE_LIMIT_MIN;
#ifdef MALLOC_COUNTERS_NEED_LOCK
    rb_native_mutex_initialize(&objspace->malloc_counters.lock);
#endif
    /* 全 objspace で共有する。preregister は (func, data) で重複排除する。 */
    objspace->finalize_deferred_pjob = rb_postponed_job_preregister(0, gc_finalize_deferred, NULL);
    if (objspace->finalize_deferred_pjob == POSTPONED_JOB_HANDLE_INVALID) {
        rb_bug("Could not preregister postponed job for GC");
    }

    /* A standard RVALUE (RBasic + embedded VALUEs + debug overhead) must fit
     * in at least one pool.  In debug builds RVALUE_OVERHEAD can push this
     * beyond the 48-byte pool into the 64-byte pool, which is fine. */
    GC_ASSERT(rb_gc_impl_size_allocatable_p(sizeof(struct RBasic) + sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX])));

    for (int i = 0; i < HEAP_COUNT; i++) {
        rb_heap_t *heap = &heaps[i];

        heap->slot_size = pool_slot_sizes[i];

        ccan_list_head_init(&heap->pages);
    }

    if (rlgc_main_objspace == NULL) {
        /* 起動時の単一スレッド。最初の objspace は main のもの。プロセス共通の定数はここで
         * 1 度だけ計算する。後の objspace_init（Ractor 生成）が同じ値でも書き直すと、他スレッドの
         * lock-free な読み取りと競合する。 */
        rlgc_main_objspace = objspace;

        init_size_to_heap_idx();

#if defined(INIT_HEAP_PAGE_ALLOC_USE_MMAP)
        /* Need to determine if we can use mmap at runtime. */
        heap_page_alloc_use_mmap = INIT_HEAP_PAGE_ALLOC_USE_MMAP;
#endif
        gc_params.heap_init_bytes = GC_HEAP_INIT_BYTES;
    }

    rb_darray_make_without_gc(&objspace->heap_pages.sorted, 0);
    rb_darray_make_without_gc(&objspace->weak_references, 0);

#if RGENGC_ESTIMATE_OLDMALLOC
    objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_min;
#endif

    init_mark_stack(&objspace->mark_stack);

    objspace->profile.invoke_time = getrusage_time();
    objspace->profile.invoke_wall_time = rb_hrtime_now();
    objspace->profile.max_records = GC_PROFILE_RECORD_DEFAULT_MAX_RECORDS;
    finalizer_table = st_init_numtable();
}

void
rb_gc_impl_init(void)
{
    VALUE gc_constants = rb_hash_new();
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("DEBUG")), GC_DEBUG ? Qtrue : Qfalse);
    /* Minimum slot size that fits a standard RVALUE */
    size_t rvalue_pool = 0;
    for (size_t i = 0; i < HEAP_COUNT; i++) {
        if (pool_slot_sizes[i] >= RVALUE_SLOT_SIZE) { rvalue_pool = pool_slot_sizes[i]; break; }
    }
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_SIZE")), SIZET2NUM(rvalue_pool - RVALUE_OVERHEAD));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RBASIC_SIZE")), SIZET2NUM(sizeof(struct RBasic)));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_OVERHEAD")), SIZET2NUM(RVALUE_OVERHEAD));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_BITMAP_SIZE")), SIZET2NUM(HEAP_PAGE_BITMAP_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_SIZE")), SIZET2NUM(HEAP_PAGE_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_COUNT")), LONG2FIX(HEAP_COUNT));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVARGC_MAX_ALLOCATE_SIZE")), SIZET2NUM(rb_gc_impl_max_allocation_size()));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_OLD_AGE")), LONG2FIX(RVALUE_OLD_AGE));
    if (RB_BUG_INSTEAD_OF_RB_MEMERROR+0) {
        rb_hash_aset(gc_constants, ID2SYM(rb_intern("RB_BUG_INSTEAD_OF_RB_MEMERROR")), Qtrue);
    }
    OBJ_FREEZE(gc_constants);
    /* Internal constants in the garbage collector. */
    rb_define_const(rb_mGC, "INTERNAL_CONSTANTS", gc_constants);

    if (GC_COMPACTION_SUPPORTED) {
        rb_define_singleton_method(rb_mGC, "compact", gc_compact, 0);
        rb_define_singleton_method(rb_mGC, "auto_compact", gc_get_auto_compact, 0);
        rb_define_singleton_method(rb_mGC, "auto_compact=", gc_set_auto_compact, 1);
        rb_define_singleton_method(rb_mGC, "latest_compact_info", gc_compact_stats, 0);
        rb_define_singleton_method(rb_mGC, "verify_compaction_references", gc_verify_compaction_references, -1);
    }
    else {
        rb_define_singleton_method(rb_mGC, "compact", rb_f_notimplement, 0);
        rb_define_singleton_method(rb_mGC, "auto_compact", rb_f_notimplement, 0);
        rb_define_singleton_method(rb_mGC, "auto_compact=", rb_f_notimplement, 1);
        rb_define_singleton_method(rb_mGC, "latest_compact_info", rb_f_notimplement, 0);
        rb_define_singleton_method(rb_mGC, "verify_compaction_references", rb_f_notimplement, -1);
    }

#if GC_DEBUG_STRESS_TO_CLASS
    rb_define_singleton_method(rb_mGC, "add_stress_to_class", rb_gcdebug_add_stress_to_class, -1);
    rb_define_singleton_method(rb_mGC, "remove_stress_to_class", rb_gcdebug_remove_stress_to_class, -1);
#endif

    /* internal methods */
    rb_define_singleton_method(rb_mGC, "verify_internal_consistency", gc_verify_internal_consistency_m, 0);

#if MALLOC_ALLOCATED_SIZE
    rb_define_singleton_method(rb_mGC, "malloc_allocated_size", gc_malloc_allocated_size, 0);
    rb_define_singleton_method(rb_mGC, "malloc_allocations", gc_malloc_allocations, 0);
#endif

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
     *    pp GC::Profiler.raw_data
     *
     *    GC::Profiler.disable
     *
     *  GC::Profiler.raw_data returns one Hash per GC run, including CPU time
     *  fields such as +:GC_TIME+ and wall-clock fields such as +:GC_WALL_TIME+,
     *  +:GC_PAUSE_TIME+, +:GC_STOP_TIME+, and +:GC_STW_TIME+.  +:GC_WALL_TIME+
     *  is the wall-clock counterpart to +:GC_TIME+, while +:GC_PAUSE_TIME+
     *  measures how long user execution was blocked by the GC entry.
     *
     *  See also GC.count, GC.malloc_allocated_size and GC.malloc_allocations
     */
    VALUE rb_mProfiler = rb_define_module_under(rb_mGC, "Profiler");
    rb_define_singleton_method(rb_mProfiler, "enabled?", gc_profile_enable_get, 0);
    rb_define_singleton_method(rb_mProfiler, "enable", gc_profile_enable, 0);
    rb_define_singleton_method(rb_mProfiler, "raw_data", gc_profile_record_get, -1);
    rb_define_singleton_method(rb_mProfiler, "disable", gc_profile_disable, 0);
    rb_define_singleton_method(rb_mProfiler, "clear", gc_profile_clear, 0);
    rb_define_singleton_method(rb_mProfiler, "configure", gc_profile_configure, -1);
    rb_define_singleton_method(rb_mProfiler, "result", gc_profile_result, 0);
    rb_define_singleton_method(rb_mProfiler, "report", gc_profile_report, -1);
    rb_define_singleton_method(rb_mProfiler, "total_time", gc_profile_total_time, 0);

    {
        VALUE opts;
        /* \GC build options */
        rb_define_const(rb_mGC, "OPTS", opts = rb_ary_new());
#define OPT(o) if (o) rb_ary_push(opts, rb_interned_str(#o, sizeof(#o) - 1))
        OPT(GC_DEBUG);
        OPT(USE_RGENGC);
        OPT(RGENGC_DEBUG);
        OPT(RGENGC_CHECK_MODE);
        OPT(RGENGC_PROFILE);
        OPT(RGENGC_ESTIMATE_OLDMALLOC);
        OPT(GC_PROFILE_MORE_DETAIL);
        OPT(GC_ENABLE_LAZY_SWEEP);
        OPT(CALC_EXACT_MALLOC_SIZE);
        OPT(MALLOC_ALLOCATED_SIZE);
        OPT(MALLOC_ALLOCATED_SIZE_CHECK);
        OPT(GC_PROFILE_DETAIL_MEMORY);
        OPT(GC_COMPACTION_SUPPORTED);
#undef OPT
        OBJ_FREEZE(opts);
    }
}
