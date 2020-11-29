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

#include <signal.h>

#define sighandler_t ruby_sighandler_t

#ifndef _WIN32
#include <unistd.h>
#include <sys/mman.h>
#endif

#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>

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
#  include RUBY_ALTERNATIVE_MALLOC_HEADER
# elif HAVE_MALLOC_H
#  include <malloc.h>
# elif defined(HAVE_MALLOC_NP_H)
#  include <malloc_np.h>
# elif defined(HAVE_MALLOC_MALLOC_H)
#  include <malloc/malloc.h>
# endif
#endif

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

#include "constant.h"
#include "debug_counter.h"
#include "eval_intern.h"
#include "gc.h"
#include "id_table.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/complex.h"
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
#include "mjit.h"
#include "probes.h"
#include "regint.h"
#include "ruby/debug.h"
#include "ruby/io.h"
#include "ruby/re.h"
#include "ruby/st.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "ruby_assert.h"
#include "ruby_atomic.h"
#include "symbol.h"
#include "transient_heap.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "vm_callinfo.h"
#include "ractor_core.h"

#include "builtin.h"

#define rb_setjmp(env) RUBY_SETJMP(env)
#define rb_jmp_buf rb_jmpbuf_t
#undef rb_data_object_wrap

static inline struct rbimpl_size_mul_overflow_tag
size_add_overflow(size_t x, size_t y)
{
    size_t z;
    bool p;
#if 0

#elif __has_builtin(__builtin_add_overflow)
    p = __builtin_add_overflow(x, y, &z);

#elif defined(DSIZE_T)
    RB_GNUC_EXTENSION DSIZE_T dx = x;
    RB_GNUC_EXTENSION DSIZE_T dy = y;
    RB_GNUC_EXTENSION DSIZE_T dz = dx + dy;
    p = dz > SIZE_MAX;
    z = (size_t)dz;

#else
    z = x + y;
    p = z < y;

#endif
    return (struct rbimpl_size_mul_overflow_tag) { p, z, };
}

static inline struct rbimpl_size_mul_overflow_tag
size_mul_add_overflow(size_t x, size_t y, size_t z) /* x * y + z */
{
    struct rbimpl_size_mul_overflow_tag t = rbimpl_size_mul_overflow(x, y);
    struct rbimpl_size_mul_overflow_tag u = size_add_overflow(t.right, z);
    return (struct rbimpl_size_mul_overflow_tag) { t.left || u.left, u.right };
}

static inline struct rbimpl_size_mul_overflow_tag
size_mul_add_mul_overflow(size_t x, size_t y, size_t z, size_t w) /* x * y + z * w */
{
    struct rbimpl_size_mul_overflow_tag t = rbimpl_size_mul_overflow(x, y);
    struct rbimpl_size_mul_overflow_tag u = rbimpl_size_mul_overflow(z, w);
    struct rbimpl_size_mul_overflow_tag v = size_add_overflow(t.right, u.right);
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
            x, y, SIZE_MAX);
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
            x, y, z, SIZE_MAX);
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
            x, y, z, w, SIZE_MAX);
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

#ifndef GC_HEAP_INIT_SLOTS
#define GC_HEAP_INIT_SLOTS 10000
#endif
#ifndef GC_HEAP_FREE_SLOTS
#define GC_HEAP_FREE_SLOTS  4096
#endif
#ifndef GC_HEAP_GROWTH_FACTOR
#define GC_HEAP_GROWTH_FACTOR 1.8
#endif
#ifndef GC_HEAP_GROWTH_MAX_SLOTS
#define GC_HEAP_GROWTH_MAX_SLOTS 0 /* 0 is disable */
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

#ifndef PRINT_MEASURE_LINE
#define PRINT_MEASURE_LINE 0
#endif
#ifndef PRINT_ENTER_EXIT_TICK
#define PRINT_ENTER_EXIT_TICK 0
#endif
#ifndef PRINT_ROOT_TICKS
#define PRINT_ROOT_TICKS 0
#endif

#define USE_TICK_T                 (PRINT_ENTER_EXIT_TICK || PRINT_MEASURE_LINE || PRINT_ROOT_TICKS)
#define TICK_TYPE 1

typedef struct {
    size_t heap_init_slots;
    size_t heap_free_slots;
    double growth_factor;
    size_t growth_max_slots;

    double heap_free_slots_min_ratio;
    double heap_free_slots_goal_ratio;
    double heap_free_slots_max_ratio;
    double oldobject_limit_factor;

    size_t malloc_limit_min;
    size_t malloc_limit_max;
    double malloc_limit_growth_factor;

    size_t oldmalloc_limit_min;
    size_t oldmalloc_limit_max;
    double oldmalloc_limit_growth_factor;

    VALUE gc_stress;
} ruby_gc_params_t;

static ruby_gc_params_t gc_params = {
    GC_HEAP_INIT_SLOTS,
    GC_HEAP_FREE_SLOTS,
    GC_HEAP_GROWTH_FACTOR,
    GC_HEAP_GROWTH_MAX_SLOTS,

    GC_HEAP_FREE_SLOTS_MIN_RATIO,
    GC_HEAP_FREE_SLOTS_GOAL_RATIO,
    GC_HEAP_FREE_SLOTS_MAX_RATIO,
    GC_HEAP_OLDOBJECT_LIMIT_FACTOR,

    GC_MALLOC_LIMIT_MIN,
    GC_MALLOC_LIMIT_MAX,
    GC_MALLOC_LIMIT_GROWTH_FACTOR,

    GC_OLDMALLOC_LIMIT_MIN,
    GC_OLDMALLOC_LIMIT_MAX,
    GC_OLDMALLOC_LIMIT_GROWTH_FACTOR,

    FALSE,
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

/* RGENGC_CHECK_MODE
 * 0: disable all assertions
 * 1: enable assertions (to debug RGenGC)
 * 2: enable internal consistency check at each GC (for debugging)
 * 3: enable internal consistency check at each GC steps (for debugging)
 * 4: enable liveness check
 * 5: show all references
 */
#ifndef RGENGC_CHECK_MODE
#define RGENGC_CHECK_MODE  0
#endif

// Note: using RUBY_ASSERT_WHEN() extend a macro in expr (info by nobu).
#define GC_ASSERT(expr) RUBY_ASSERT_MESG_WHEN(RGENGC_CHECK_MODE > 0, expr, #expr)

/* RGENGC_OLD_NEWOBJ_CHECK
 * 0:  disable all assertions
 * >0: make a OLD object when new object creation.
 *
 * Make one OLD object per RGENGC_OLD_NEWOBJ_CHECK WB protected objects creation.
 */
#ifndef RGENGC_OLD_NEWOBJ_CHECK
#define RGENGC_OLD_NEWOBJ_CHECK 0
#endif

/* RGENGC_PROFILE
 * 0: disable RGenGC profiling
 * 1: enable profiling for basic information
 * 2: enable profiling for each types
 */
#ifndef RGENGC_PROFILE
#define RGENGC_PROFILE     1
#endif

/* RGENGC_ESTIMATE_OLDMALLOC
 * Enable/disable to estimate increase size of malloc'ed size by old objects.
 * If estimation exceeds threshold, then will invoke full GC.
 * 0: disable estimation.
 * 1: enable estimation.
 */
#ifndef RGENGC_ESTIMATE_OLDMALLOC
#define RGENGC_ESTIMATE_OLDMALLOC 1
#endif

/* RGENGC_FORCE_MAJOR_GC
 * Force major/full GC if this macro is not 0.
 */
#ifndef RGENGC_FORCE_MAJOR_GC
#define RGENGC_FORCE_MAJOR_GC 0
#endif

#ifndef GC_PROFILE_MORE_DETAIL
#define GC_PROFILE_MORE_DETAIL 0
#endif
#ifndef GC_PROFILE_DETAIL_MEMORY
#define GC_PROFILE_DETAIL_MEMORY 0
#endif
#ifndef GC_ENABLE_INCREMENTAL_MARK
#define GC_ENABLE_INCREMENTAL_MARK USE_RINCGC
#endif
#ifndef GC_ENABLE_LAZY_SWEEP
#define GC_ENABLE_LAZY_SWEEP   1
#endif
#ifndef CALC_EXACT_MALLOC_SIZE
#define CALC_EXACT_MALLOC_SIZE USE_GC_MALLOC_OBJ_INFO_DETAILS
#endif
#if defined(HAVE_MALLOC_USABLE_SIZE) || CALC_EXACT_MALLOC_SIZE > 0
#ifndef MALLOC_ALLOCATED_SIZE
#define MALLOC_ALLOCATED_SIZE 0
#endif
#else
#define MALLOC_ALLOCATED_SIZE 0
#endif
#ifndef MALLOC_ALLOCATED_SIZE_CHECK
#define MALLOC_ALLOCATED_SIZE_CHECK 0
#endif

#ifndef GC_DEBUG_STRESS_TO_CLASS
#define GC_DEBUG_STRESS_TO_CLASS 0
#endif

#ifndef RGENGC_OBJ_INFO
#define RGENGC_OBJ_INFO (RGENGC_DEBUG | RGENGC_CHECK_MODE)
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
    int flags;

    double gc_time;
    double gc_invoke_time;

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

#define FL_FROM_FREELIST FL_USER0

struct RMoved {
    VALUE flags;
    VALUE dummy;
    VALUE destination;
};

#define RMOVED(obj) ((struct RMoved *)(obj))

#if defined(_MSC_VER) || defined(__CYGWIN__)
#pragma pack(push, 1) /* magic for reducing sizeof(RVALUE): 24 -> 20 */
#endif

typedef struct RVALUE {
    union {
	struct {
	    VALUE flags;		/* always 0 for freed obj */
	    struct RVALUE *next;
	} free;
        struct RMoved  moved;
	struct RBasic  basic;
	struct RObject object;
	struct RClass  klass;
	struct RFloat  flonum;
	struct RString string;
	struct RArray  array;
	struct RRegexp regexp;
	struct RHash   hash;
	struct RData   data;
	struct RTypedData   typeddata;
	struct RStruct rstruct;
	struct RBignum bignum;
	struct RFile   file;
	struct RMatch  match;
	struct RRational rational;
	struct RComplex complex;
	union {
	    rb_cref_t cref;
	    struct vm_svar svar;
	    struct vm_throw_data throw_data;
	    struct vm_ifunc ifunc;
	    struct MEMO memo;
	    struct rb_method_entry_struct ment;
	    const rb_iseq_t iseq;
	    rb_env_t env;
	    struct rb_imemo_tmpbuf_struct alloc;
	    rb_ast_t ast;
	} imemo;
	struct {
	    struct RBasic basic;
	    VALUE v1;
	    VALUE v2;
	    VALUE v3;
	} values;
    } as;
#if GC_DEBUG
    const char *file;
    int line;
#endif
} RVALUE;

#if defined(_MSC_VER) || defined(__CYGWIN__)
#pragma pack(pop)
#endif

typedef uintptr_t bits_t;
enum {
    BITS_SIZE = sizeof(bits_t),
    BITS_BITLENGTH = ( BITS_SIZE * CHAR_BIT )
};
#define popcount_bits rb_popcount_intptr

struct heap_page_header {
    struct heap_page *page;
};

struct heap_page_body {
    struct heap_page_header header;
    /* char gap[];      */
    /* RVALUE values[]; */
};

struct gc_list {
    VALUE *varptr;
    struct gc_list *next;
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

typedef struct rb_heap_struct {
    RVALUE *freelist;

    struct heap_page *free_pages;
    struct heap_page *using_page;
    struct list_head pages;
    struct heap_page *sweeping_page; /* iterator for .pages */
    struct heap_page *compact_cursor;
    size_t compact_cursor_index;
#if GC_ENABLE_INCREMENTAL_MARK
    struct heap_page *pooled_pages;
#endif
    size_t total_pages;      /* total page count in a heap */
    size_t total_slots;      /* total slot count (about total_pages * HEAP_PAGE_OBJ_LIMIT) */
} rb_heap_t;

enum gc_mode {
    gc_mode_none,
    gc_mode_marking,
    gc_mode_sweeping
};

typedef struct rb_objspace {
    struct {
	size_t limit;
	size_t increase;
#if MALLOC_ALLOCATED_SIZE
	size_t allocated_size;
	size_t allocations;
#endif
    } malloc_params;

    struct {
	unsigned int mode : 2;
	unsigned int immediate_sweep : 1;
	unsigned int dont_gc : 1;
	unsigned int dont_incremental : 1;
	unsigned int during_gc : 1;
        unsigned int during_compacting : 2;
	unsigned int gc_stressful: 1;
	unsigned int has_hook: 1;
	unsigned int during_minor_gc : 1;
#if GC_ENABLE_INCREMENTAL_MARK
	unsigned int during_incremental_marking : 1;
#endif
    } flags;

    rb_event_flag_t hook_events;
    size_t total_allocated_objects;
    VALUE next_object_id;

    rb_heap_t eden_heap;
    rb_heap_t tomb_heap; /* heap for zombies and ghosts */

    struct {
	rb_atomic_t finalizing;
    } atomic_flags;

    mark_stack_t mark_stack;
    size_t marked_slots;

    struct {
	struct heap_page **sorted;
	size_t allocated_pages;
	size_t allocatable_pages;
	size_t sorted_length;
	RVALUE *range[2];
	size_t freeable_pages;

	/* final */
	size_t final_slots;
	VALUE deferred_final;
    } heap_pages;

    st_table *finalizer_table;

    struct {
	int run;
	int latest_gc_info;
	gc_profile_record *records;
	gc_profile_record *current_record;
	size_t next_index;
	size_t size;

#if GC_PROFILE_MORE_DETAIL
	double prepare_time;
#endif
	double invoke_time;

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
	size_t total_allocated_objects_at_gc_start;
	size_t heap_used_at_gc_start;

	/* basic statistics */
	size_t count;
	size_t total_freed_objects;
	size_t total_allocated_pages;
	size_t total_freed_pages;
    } profile;
    struct gc_list *global_list;

    VALUE gc_stress_mode;

    struct {
	VALUE parent_object;
	int need_major_gc;
	size_t last_major_gc;
	size_t uncollectible_wb_unprotected_objects;
	size_t uncollectible_wb_unprotected_objects_limit;
	size_t old_objects;
	size_t old_objects_limit;

#if RGENGC_ESTIMATE_OLDMALLOC
	size_t oldmalloc_increase;
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
        size_t total_moved;
    } rcompactor;

#if GC_ENABLE_INCREMENTAL_MARK
    struct {
	size_t pooled_slots;
	size_t step_slots;
    } rincgc;
#endif

    st_table *id_to_obj_tbl;
    st_table *obj_to_id_tbl;

#if GC_DEBUG_STRESS_TO_CLASS
    VALUE stress_to_class;
#endif
} rb_objspace_t;


/* default tiny heap size: 16KB */
#define HEAP_PAGE_ALIGN_LOG 14
#define CEILDIV(i, mod) (((i) + (mod) - 1)/(mod))
enum {
    HEAP_PAGE_ALIGN = (1UL << HEAP_PAGE_ALIGN_LOG),
    HEAP_PAGE_ALIGN_MASK = (~(~0UL << HEAP_PAGE_ALIGN_LOG)),
    HEAP_PAGE_SIZE = HEAP_PAGE_ALIGN,
    HEAP_PAGE_OBJ_LIMIT = (unsigned int)((HEAP_PAGE_SIZE - sizeof(struct heap_page_header))/sizeof(struct RVALUE)),
    HEAP_PAGE_BITMAP_LIMIT = CEILDIV(CEILDIV(HEAP_PAGE_SIZE, sizeof(struct RVALUE)), BITS_BITLENGTH),
    HEAP_PAGE_BITMAP_SIZE = (BITS_SIZE * HEAP_PAGE_BITMAP_LIMIT),
    HEAP_PAGE_BITMAP_PLANES = 4 /* RGENGC: mark, unprotected, uncollectible, marking */
};

struct heap_page {
    short total_slots;
    short free_slots;
    short pinned_slots;
    short final_slots;
    struct {
	unsigned int before_sweep : 1;
	unsigned int has_remembered_objects : 1;
	unsigned int has_uncollectible_shady_objects : 1;
	unsigned int in_tomb : 1;
    } flags;

    struct heap_page *free_next;
    RVALUE *start;
    RVALUE *freelist;
    struct list_node page_node;

    bits_t wb_unprotected_bits[HEAP_PAGE_BITMAP_LIMIT];
    /* the following three bitmaps are cleared at the beginning of full GC */
    bits_t mark_bits[HEAP_PAGE_BITMAP_LIMIT];
    bits_t uncollectible_bits[HEAP_PAGE_BITMAP_LIMIT];
    bits_t marking_bits[HEAP_PAGE_BITMAP_LIMIT];

    /* If set, the object is not movable */
    bits_t pinned_bits[HEAP_PAGE_BITMAP_LIMIT];
};

#define GET_PAGE_BODY(x)   ((struct heap_page_body *)((bits_t)(x) & ~(HEAP_PAGE_ALIGN_MASK)))
#define GET_PAGE_HEADER(x) (&GET_PAGE_BODY(x)->header)
#define GET_HEAP_PAGE(x)   (GET_PAGE_HEADER(x)->page)

#define NUM_IN_PAGE(p)   (((bits_t)(p) & HEAP_PAGE_ALIGN_MASK)/sizeof(RVALUE))
#define BITMAP_INDEX(p)  (NUM_IN_PAGE(p) / BITS_BITLENGTH )
#define BITMAP_OFFSET(p) (NUM_IN_PAGE(p) & (BITS_BITLENGTH-1))
#define BITMAP_BIT(p)    ((bits_t)1 << BITMAP_OFFSET(p))

/* Bitmap Operations */
#define MARKED_IN_BITMAP(bits, p)    ((bits)[BITMAP_INDEX(p)] & BITMAP_BIT(p))
#define MARK_IN_BITMAP(bits, p)      ((bits)[BITMAP_INDEX(p)] = (bits)[BITMAP_INDEX(p)] | BITMAP_BIT(p))
#define CLEAR_IN_BITMAP(bits, p)     ((bits)[BITMAP_INDEX(p)] = (bits)[BITMAP_INDEX(p)] & ~BITMAP_BIT(p))

/* getting bitmap */
#define GET_HEAP_MARK_BITS(x)           (&GET_HEAP_PAGE(x)->mark_bits[0])
#define GET_HEAP_PINNED_BITS(x)         (&GET_HEAP_PAGE(x)->pinned_bits[0])
#define GET_HEAP_UNCOLLECTIBLE_BITS(x)  (&GET_HEAP_PAGE(x)->uncollectible_bits[0])
#define GET_HEAP_WB_UNPROTECTED_BITS(x) (&GET_HEAP_PAGE(x)->wb_unprotected_bits[0])
#define GET_HEAP_MARKING_BITS(x)        (&GET_HEAP_PAGE(x)->marking_bits[0])

/* Aliases */
#define rb_objspace (*rb_objspace_of(GET_VM()))
#define rb_objspace_of(vm) ((vm)->objspace)

#define ruby_initial_gc_stress	gc_params.gc_stress

VALUE *ruby_initial_gc_stress_ptr = &ruby_initial_gc_stress;

#define malloc_limit		objspace->malloc_params.limit
#define malloc_increase 	objspace->malloc_params.increase
#define malloc_allocated_size 	objspace->malloc_params.allocated_size
#define heap_pages_sorted       objspace->heap_pages.sorted
#define heap_allocated_pages    objspace->heap_pages.allocated_pages
#define heap_pages_sorted_length objspace->heap_pages.sorted_length
#define heap_pages_lomem	objspace->heap_pages.range[0]
#define heap_pages_himem	objspace->heap_pages.range[1]
#define heap_allocatable_pages	objspace->heap_pages.allocatable_pages
#define heap_pages_freeable_pages	objspace->heap_pages.freeable_pages
#define heap_pages_final_slots		objspace->heap_pages.final_slots
#define heap_pages_deferred_final	objspace->heap_pages.deferred_final
#define heap_eden               (&objspace->eden_heap)
#define heap_tomb               (&objspace->tomb_heap)
#define during_gc		objspace->flags.during_gc
#define finalizing		objspace->atomic_flags.finalizing
#define finalizer_table 	objspace->finalizer_table
#define global_list		objspace->global_list
#define ruby_gc_stressful	objspace->flags.gc_stressful
#define ruby_gc_stress_mode     objspace->gc_stress_mode
#if GC_DEBUG_STRESS_TO_CLASS
#define stress_to_class         objspace->stress_to_class
#else
#define stress_to_class         0
#endif

#if 0
#define dont_gc_on()          (fprintf(stderr, "dont_gc_on@%s:%d\n",      __FILE__, __LINE__), objspace->flags.dont_gc = 1)
#define dont_gc_off()         (fprintf(stderr, "dont_gc_off@%s:%d\n",     __FILE__, __LINE__), objspace->flags.dont_gc = 0)
#define dont_gc_set(b)        (fprintf(stderr, "dont_gc_set(%d)@%s:%d\n", __FILE__, __LINE__), (int)b), objspace->flags.dont_gc = (b))
#define dont_gc_val()         (objspace->flags.dont_gc)
#else
#define dont_gc_on()          (objspace->flags.dont_gc = 1)
#define dont_gc_off()         (objspace->flags.dont_gc = 0)
#define dont_gc_set(b)        (((int)b), objspace->flags.dont_gc = (b))
#define dont_gc_val()         (objspace->flags.dont_gc)
#endif

static inline enum gc_mode
gc_mode_verify(enum gc_mode mode)
{
#if RGENGC_CHECK_MODE > 0
    switch (mode) {
      case gc_mode_none:
      case gc_mode_marking:
      case gc_mode_sweeping:
	break;
      default:
	rb_bug("gc_mode_verify: unreachable (%d)", (int)mode);
    }
#endif
    return mode;
}

#define gc_mode(objspace)                gc_mode_verify((enum gc_mode)(objspace)->flags.mode)
#define gc_mode_set(objspace, mode)      ((objspace)->flags.mode = (unsigned int)gc_mode_verify(mode))

#define is_marking(objspace)             (gc_mode(objspace) == gc_mode_marking)
#define is_sweeping(objspace)            (gc_mode(objspace) == gc_mode_sweeping)
#define is_full_marking(objspace)        ((objspace)->flags.during_minor_gc == FALSE)
#if GC_ENABLE_INCREMENTAL_MARK
#define is_incremental_marking(objspace) ((objspace)->flags.during_incremental_marking != FALSE)
#else
#define is_incremental_marking(objspace) FALSE
#endif
#if GC_ENABLE_INCREMENTAL_MARK
#define will_be_incremental_marking(objspace) ((objspace)->rgengc.need_major_gc != GPR_FLAG_NONE)
#else
#define will_be_incremental_marking(objspace) FALSE
#endif
#define has_sweeping_pages(heap)         ((heap)->sweeping_page != 0)
#define is_lazy_sweeping(heap)           (GC_ENABLE_LAZY_SWEEP && has_sweeping_pages(heap))

#if SIZEOF_LONG == SIZEOF_VOIDP
# define nonspecial_obj_id(obj) (VALUE)((SIGNED_VALUE)(obj)|FIXNUM_FLAG)
# define obj_id_to_ref(objid) ((objid) ^ FIXNUM_FLAG) /* unset FIXNUM_FLAG */
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
# define nonspecial_obj_id(obj) LL2NUM((SIGNED_VALUE)(obj) / 2)
# define obj_id_to_ref(objid) (FIXNUM_P(objid) ? \
   ((objid) ^ FIXNUM_FLAG) : (NUM2PTR(objid) << 1))
#else
# error not supported
#endif

#define RANY(o) ((RVALUE*)(o))

struct RZombie {
    struct RBasic basic;
    VALUE next;
    void (*dfree)(void *);
    void *data;
};

#define RZOMBIE(o) ((struct RZombie *)(o))

#define nomem_error GET_VM()->special_exceptions[ruby_error_nomemory]

#if RUBY_MARK_FREE_DEBUG
int ruby_gc_debug_indent = 0;
#endif
VALUE rb_mGC;
int ruby_disable_gc = 0;
int ruby_enable_autocompact = 0;

void rb_iseq_mark(const rb_iseq_t *iseq);
void rb_iseq_update_references(rb_iseq_t *iseq);
void rb_iseq_free(const rb_iseq_t *iseq);
size_t rb_iseq_memsize(const rb_iseq_t *iseq);
void rb_vm_update_references(void *ptr);

void rb_gcdebug_print_obj_condition(VALUE obj);

static VALUE define_final0(VALUE obj, VALUE block);

NORETURN(static void *gc_vraise(void *ptr));
NORETURN(static void gc_raise(VALUE exc, const char *fmt, ...));
NORETURN(static void negative_size_allocation_error(const char *));

static void init_mark_stack(mark_stack_t *stack);

static int ready_to_gc(rb_objspace_t *objspace);

static int garbage_collect(rb_objspace_t *, int reason);

static int  gc_start(rb_objspace_t *objspace, int reason);
static void gc_rest(rb_objspace_t *objspace);
static inline void gc_enter(rb_objspace_t *objspace, const char *event, unsigned int *lock_lev);
static inline void gc_exit(rb_objspace_t *objspace, const char *event, unsigned int *lock_lev);

static void gc_marks(rb_objspace_t *objspace, int full_mark);
static void gc_marks_start(rb_objspace_t *objspace, int full);
static int  gc_marks_finish(rb_objspace_t *objspace);
static void gc_marks_rest(rb_objspace_t *objspace);
static void gc_marks_step(rb_objspace_t *objspace, size_t slots);
static void gc_marks_continue(rb_objspace_t *objspace, rb_heap_t *heap);

static void gc_sweep(rb_objspace_t *objspace);
static void gc_sweep_start(rb_objspace_t *objspace);
static void gc_sweep_finish(rb_objspace_t *objspace);
static int  gc_sweep_step(rb_objspace_t *objspace, rb_heap_t *heap);
static void gc_sweep_rest(rb_objspace_t *objspace);
static void gc_sweep_continue(rb_objspace_t *objspace, rb_heap_t *heap);

static inline void gc_mark(rb_objspace_t *objspace, VALUE ptr);
static inline void gc_pin(rb_objspace_t *objspace, VALUE ptr);
static inline void gc_mark_and_pin(rb_objspace_t *objspace, VALUE ptr);
static void gc_mark_ptr(rb_objspace_t *objspace, VALUE ptr);
NO_SANITIZE("memory", static void gc_mark_maybe(rb_objspace_t *objspace, VALUE ptr));
static void gc_mark_children(rb_objspace_t *objspace, VALUE ptr);

static int gc_mark_stacked_objects_incremental(rb_objspace_t *, size_t count);
static int gc_mark_stacked_objects_all(rb_objspace_t *);
static void gc_grey(rb_objspace_t *objspace, VALUE ptr);

static inline int gc_mark_set(rb_objspace_t *objspace, VALUE obj);
NO_SANITIZE("memory", static inline int is_pointer_to_heap(rb_objspace_t *objspace, void *ptr));

static void   push_mark_stack(mark_stack_t *, VALUE);
static int    pop_mark_stack(mark_stack_t *, VALUE *);
static size_t mark_stack_size(mark_stack_t *stack);
static void   shrink_stack_chunk_cache(mark_stack_t *stack);

static size_t obj_memsize_of(VALUE obj, int use_all_types);
static void gc_verify_internal_consistency(rb_objspace_t *objspace);
static int gc_verify_heap_page(rb_objspace_t *objspace, struct heap_page *page, VALUE obj);
static int gc_verify_heap_pages(rb_objspace_t *objspace);

static void gc_stress_set(rb_objspace_t *objspace, VALUE flag);
static VALUE gc_disable_no_rest(rb_objspace_t *);

static double getrusage_time(void);
static inline void gc_prof_setup_new_record(rb_objspace_t *objspace, int reason);
static inline void gc_prof_timer_start(rb_objspace_t *);
static inline void gc_prof_timer_stop(rb_objspace_t *);
static inline void gc_prof_mark_timer_start(rb_objspace_t *);
static inline void gc_prof_mark_timer_stop(rb_objspace_t *);
static inline void gc_prof_sweep_timer_start(rb_objspace_t *);
static inline void gc_prof_sweep_timer_stop(rb_objspace_t *);
static inline void gc_prof_set_malloc_info(rb_objspace_t *);
static inline void gc_prof_set_heap_info(rb_objspace_t *);

#define TYPED_UPDATE_IF_MOVED(_objspace, _type, _thing) do { \
    if (gc_object_moved_p(_objspace, (VALUE)_thing)) { \
       *((_type *)(&_thing)) = (_type)RMOVED((_thing))->destination; \
    } \
} while (0)

#define UPDATE_IF_MOVED(_objspace, _thing) TYPED_UPDATE_IF_MOVED(_objspace, VALUE, _thing)

#define gc_prof_record(objspace) (objspace)->profile.current_record
#define gc_prof_enabled(objspace) ((objspace)->profile.run && (objspace)->profile.current_record)

#ifdef HAVE_VA_ARGS_MACRO
# define gc_report(level, objspace, ...) \
    if (!RGENGC_DEBUG_ENABLED(level)) {} else gc_report_body(level, objspace, __VA_ARGS__)
#else
# define gc_report if (!RGENGC_DEBUG_ENABLED(0)) {} else gc_report_body
#endif
PRINTF_ARGS(static void gc_report_body(int level, rb_objspace_t *objspace, const char *fmt, ...), 3, 4);
static const char *obj_info(VALUE obj);

/*
 * 1 - TSC (H/W Time Stamp Counter)
 * 2 - getrusage
 */
#ifndef TICK_TYPE
#define TICK_TYPE 1
#endif

#if USE_TICK_T

#if TICK_TYPE == 1
/* the following code is only for internal tuning. */

/* Source code to use RDTSC is quoted and modified from
 * http://www.mcs.anl.gov/~kazutomo/rdtsc.html
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

#elif defined(__powerpc64__) && GCC_VERSION_SINCE(4,8,0)
typedef unsigned long long tick_t;
#define PRItick "llu"

static __inline__ tick_t
tick(void)
{
    unsigned long long val = __builtin_ppc_get_timebase();
    return val;
}

#elif defined(__aarch64__) &&  defined(__GNUC__)
typedef unsigned long tick_t;
#define PRItick "lu"

static __inline__ tick_t
tick(void)
{
    unsigned long val;
    __asm__ __volatile__ ("mrs %0, cntvct_el0", : "=r" (val));
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

#elif TICK_TYPE == 2
typedef double tick_t;
#define PRItick "4.9f"

static inline tick_t
tick(void)
{
    return getrusage_time();
}
#else /* TICK_TYPE */
#error "choose tick type"
#endif /* TICK_TYPE */

#define MEASURE_LINE(expr) do { \
    volatile tick_t start_time = tick(); \
    volatile tick_t end_time; \
    expr; \
    end_time = tick(); \
    fprintf(stderr, "0\t%"PRItick"\t%s\n", end_time - start_time, #expr); \
} while (0)

#else /* USE_TICK_T */
#define MEASURE_LINE(expr) expr
#endif /* USE_TICK_T */

#define FL_CHECK2(name, x, pred) \
    ((RGENGC_CHECK_MODE && SPECIAL_CONST_P(x)) ? \
     (rb_bug(name": SPECIAL_CONST (%p)", (void *)(x)), 0) : (pred))
#define FL_TEST2(x,f)  FL_CHECK2("FL_TEST2",  x, FL_TEST_RAW((x),(f)) != 0)
#define FL_SET2(x,f)   FL_CHECK2("FL_SET2",   x, RBASIC(x)->flags |= (f))
#define FL_UNSET2(x,f) FL_CHECK2("FL_UNSET2", x, RBASIC(x)->flags &= ~(f))

#define RVALUE_MARK_BITMAP(obj)           MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), (obj))
#define RVALUE_PIN_BITMAP(obj)            MARKED_IN_BITMAP(GET_HEAP_PINNED_BITS(obj), (obj))
#define RVALUE_PAGE_MARKED(page, obj)     MARKED_IN_BITMAP((page)->mark_bits, (obj))

#define RVALUE_WB_UNPROTECTED_BITMAP(obj) MARKED_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(obj), (obj))
#define RVALUE_UNCOLLECTIBLE_BITMAP(obj)  MARKED_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS(obj), (obj))
#define RVALUE_MARKING_BITMAP(obj)        MARKED_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), (obj))

#define RVALUE_PAGE_WB_UNPROTECTED(page, obj) MARKED_IN_BITMAP((page)->wb_unprotected_bits, (obj))
#define RVALUE_PAGE_UNCOLLECTIBLE(page, obj)  MARKED_IN_BITMAP((page)->uncollectible_bits, (obj))
#define RVALUE_PAGE_MARKING(page, obj)        MARKED_IN_BITMAP((page)->marking_bits, (obj))

#define RVALUE_OLD_AGE   3
#define RVALUE_AGE_SHIFT 5 /* FL_PROMOTED0 bit */

static int rgengc_remembered(rb_objspace_t *objspace, VALUE obj);
static int rgengc_remembered_sweep(rb_objspace_t *objspace, VALUE obj);
static int rgengc_remember(rb_objspace_t *objspace, VALUE obj);
static void rgengc_mark_and_rememberset_clear(rb_objspace_t *objspace, rb_heap_t *heap);
static void rgengc_rememberset_mark(rb_objspace_t *objspace, rb_heap_t *heap);

static inline int
RVALUE_FLAGS_AGE(VALUE flags)
{
    return (int)((flags & (FL_PROMOTED0 | FL_PROMOTED1)) >> RVALUE_AGE_SHIFT);
}

static int
check_rvalue_consistency_force(const VALUE obj, int terminate)
{
    rb_objspace_t *objspace = &rb_objspace;
    int err = 0;

    if (SPECIAL_CONST_P(obj)) {
        fprintf(stderr, "check_rvalue_consistency: %p is a special const.\n", (void *)obj);
        err++;
    }
    else if (!is_pointer_to_heap(objspace, (void *)obj)) {
        /* check if it is in tomb_pages */
        struct heap_page *page = NULL;
        list_for_each(&heap_tomb->pages, page, page_node) {
            if (&page->start[0] <= (RVALUE *)obj &&
                (RVALUE *)obj < &page->start[page->total_slots]) {
                fprintf(stderr, "check_rvalue_consistency: %p is in a tomb_heap (%p).\n",
                        (void *)obj, (void *)page);
                err++;
                goto skip;
            }
        }
        bp();
        fprintf(stderr, "check_rvalue_consistency: %p is not a Ruby object.\n", (void *)obj);
        err++;
      skip:
        ;
    }
    else {
        const int wb_unprotected_bit = RVALUE_WB_UNPROTECTED_BITMAP(obj) != 0;
        const int uncollectible_bit = RVALUE_UNCOLLECTIBLE_BITMAP(obj) != 0;
        const int mark_bit = RVALUE_MARK_BITMAP(obj) != 0;
        const int marking_bit = RVALUE_MARKING_BITMAP(obj) != 0, remembered_bit = marking_bit;
        const int age = RVALUE_FLAGS_AGE(RBASIC(obj)->flags);

        if (GET_HEAP_PAGE(obj)->flags.in_tomb) {
            fprintf(stderr, "check_rvalue_consistency: %s is in tomb page.\n", obj_info(obj));
            err++;
        }
        if (BUILTIN_TYPE(obj) == T_NONE) {
            fprintf(stderr, "check_rvalue_consistency: %s is T_NONE.\n", obj_info(obj));
            err++;
        }
        if (BUILTIN_TYPE(obj) == T_ZOMBIE) {
            fprintf(stderr, "check_rvalue_consistency: %s is T_ZOMBIE.\n", obj_info(obj));
            err++;
        }

        obj_memsize_of((VALUE)obj, FALSE);

        /* check generation
         *
         * OLD == age == 3 && old-bitmap && mark-bit (except incremental marking)
         */
        if (age > 0 && wb_unprotected_bit) {
            fprintf(stderr, "check_rvalue_consistency: %s is not WB protected, but age is %d > 0.\n", obj_info(obj), age);
            err++;
        }

        if (!is_marking(objspace) && uncollectible_bit && !mark_bit) {
            fprintf(stderr, "check_rvalue_consistency: %s is uncollectible, but is not marked while !gc.\n", obj_info(obj));
            err++;
        }

        if (!is_full_marking(objspace)) {
            if (uncollectible_bit && age != RVALUE_OLD_AGE && !wb_unprotected_bit) {
                fprintf(stderr, "check_rvalue_consistency: %s is uncollectible, but not old (age: %d) and not WB unprotected.\n",
                        obj_info(obj), age);
                err++;
            }
            if (remembered_bit && age != RVALUE_OLD_AGE) {
                fprintf(stderr, "check_rvalue_consistency: %s is remembered, but not old (age: %d).\n",
                        obj_info(obj), age);
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
                fprintf(stderr, "check_rvalue_consistency: %s is marking, but not marked.\n", obj_info(obj));
                err++;
            }
        }
    }

    if (err > 0 && terminate) {
        rb_bug("check_rvalue_consistency_force: there is %d errors.", err);
    }

    return err;
}

#if RGENGC_CHECK_MODE == 0
static inline VALUE
check_rvalue_consistency(const VALUE obj)
{
    return obj;
}
#else
static VALUE
check_rvalue_consistency(const VALUE obj)
{
    check_rvalue_consistency_force(obj, TRUE);
    return obj;
}
#endif

static inline int
gc_object_moved_p(rb_objspace_t * objspace, VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        return FALSE;
    }
    else {
        void *poisoned = asan_poisoned_object_p(obj);
        asan_unpoison_object(obj, false);

        int ret =  BUILTIN_TYPE(obj) == T_MOVED;
        /* Re-poison slot if it's not the one we want */
        if (poisoned) {
            GC_ASSERT(BUILTIN_TYPE(obj) == T_NONE);
            asan_poison_object(obj);
        }
        return ret;
    }
}

static inline int
RVALUE_MARKED(VALUE obj)
{
    check_rvalue_consistency(obj);
    return RVALUE_MARK_BITMAP(obj) != 0;
}

static inline int
RVALUE_PINNED(VALUE obj)
{
    check_rvalue_consistency(obj);
    return RVALUE_PIN_BITMAP(obj) != 0;
}

static inline int
RVALUE_WB_UNPROTECTED(VALUE obj)
{
    check_rvalue_consistency(obj);
    return RVALUE_WB_UNPROTECTED_BITMAP(obj) != 0;
}

static inline int
RVALUE_MARKING(VALUE obj)
{
    check_rvalue_consistency(obj);
    return RVALUE_MARKING_BITMAP(obj) != 0;
}

static inline int
RVALUE_REMEMBERED(VALUE obj)
{
    check_rvalue_consistency(obj);
    return RVALUE_MARKING_BITMAP(obj) != 0;
}

static inline int
RVALUE_UNCOLLECTIBLE(VALUE obj)
{
    check_rvalue_consistency(obj);
    return RVALUE_UNCOLLECTIBLE_BITMAP(obj) != 0;
}

static inline int
RVALUE_OLD_P_RAW(VALUE obj)
{
    const VALUE promoted = FL_PROMOTED0 | FL_PROMOTED1;
    return (RBASIC(obj)->flags & promoted) == promoted;
}

static inline int
RVALUE_OLD_P(VALUE obj)
{
    check_rvalue_consistency(obj);
    return RVALUE_OLD_P_RAW(obj);
}

#if RGENGC_CHECK_MODE || GC_DEBUG
static inline int
RVALUE_AGE(VALUE obj)
{
    check_rvalue_consistency(obj);
    return RVALUE_FLAGS_AGE(RBASIC(obj)->flags);
}
#endif

static inline void
RVALUE_PAGE_OLD_UNCOLLECTIBLE_SET(rb_objspace_t *objspace, struct heap_page *page, VALUE obj)
{
    MARK_IN_BITMAP(&page->uncollectible_bits[0], obj);
    objspace->rgengc.old_objects++;
    rb_transient_heap_promote(obj);

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

static inline VALUE
RVALUE_FLAGS_AGE_SET(VALUE flags, int age)
{
    flags &= ~(FL_PROMOTED0 | FL_PROMOTED1);
    flags |= (age << RVALUE_AGE_SHIFT);
    return flags;
}

/* set age to age+1 */
static inline void
RVALUE_AGE_INC(rb_objspace_t *objspace, VALUE obj)
{
    VALUE flags = RBASIC(obj)->flags;
    int age = RVALUE_FLAGS_AGE(flags);

    if (RGENGC_CHECK_MODE && age == RVALUE_OLD_AGE) {
	rb_bug("RVALUE_AGE_INC: can not increment age of OLD object %s.", obj_info(obj));
    }

    age++;
    RBASIC(obj)->flags = RVALUE_FLAGS_AGE_SET(flags, age);

    if (age == RVALUE_OLD_AGE) {
	RVALUE_OLD_UNCOLLECTIBLE_SET(objspace, obj);
    }
    check_rvalue_consistency(obj);
}

/* set age to RVALUE_OLD_AGE */
static inline void
RVALUE_AGE_SET_OLD(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(obj);
    GC_ASSERT(!RVALUE_OLD_P(obj));

    RBASIC(obj)->flags = RVALUE_FLAGS_AGE_SET(RBASIC(obj)->flags, RVALUE_OLD_AGE);
    RVALUE_OLD_UNCOLLECTIBLE_SET(objspace, obj);

    check_rvalue_consistency(obj);
}

/* set age to RVALUE_OLD_AGE - 1 */
static inline void
RVALUE_AGE_SET_CANDIDATE(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(obj);
    GC_ASSERT(!RVALUE_OLD_P(obj));

    RBASIC(obj)->flags = RVALUE_FLAGS_AGE_SET(RBASIC(obj)->flags, RVALUE_OLD_AGE - 1);

    check_rvalue_consistency(obj);
}

static inline void
RVALUE_DEMOTE_RAW(rb_objspace_t *objspace, VALUE obj)
{
    RBASIC(obj)->flags = RVALUE_FLAGS_AGE_SET(RBASIC(obj)->flags, 0);
    CLEAR_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS(obj), obj);
}

static inline void
RVALUE_DEMOTE(rb_objspace_t *objspace, VALUE obj)
{
    check_rvalue_consistency(obj);
    GC_ASSERT(RVALUE_OLD_P(obj));

    if (!is_incremental_marking(objspace) && RVALUE_REMEMBERED(obj)) {
	CLEAR_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj);
    }

    RVALUE_DEMOTE_RAW(objspace, obj);

    if (RVALUE_MARKED(obj)) {
	objspace->rgengc.old_objects--;
    }

    check_rvalue_consistency(obj);
}

static inline void
RVALUE_AGE_RESET_RAW(VALUE obj)
{
    RBASIC(obj)->flags = RVALUE_FLAGS_AGE_SET(RBASIC(obj)->flags, 0);
}

static inline void
RVALUE_AGE_RESET(VALUE obj)
{
    check_rvalue_consistency(obj);
    GC_ASSERT(!RVALUE_OLD_P(obj));

    RVALUE_AGE_RESET_RAW(obj);
    check_rvalue_consistency(obj);
}

static inline int
RVALUE_BLACK_P(VALUE obj)
{
    return RVALUE_MARKED(obj) && !RVALUE_MARKING(obj);
}

#if 0
static inline int
RVALUE_GREY_P(VALUE obj)
{
    return RVALUE_MARKED(obj) && RVALUE_MARKING(obj);
}
#endif

static inline int
RVALUE_WHITE_P(VALUE obj)
{
    return RVALUE_MARKED(obj) == FALSE;
}

/*
  --------------------------- ObjectSpace -----------------------------
*/

static inline void *
calloc1(size_t n)
{
    return calloc(1, n);
}

rb_objspace_t *
rb_objspace_alloc(void)
{
    rb_objspace_t *objspace = calloc1(sizeof(rb_objspace_t));
    malloc_limit = gc_params.malloc_limit_min;
    list_head_init(&objspace->eden_heap.pages);
    list_head_init(&objspace->tomb_heap.pages);
    dont_gc_on();

    return objspace;
}

static void free_stack_chunks(mark_stack_t *);
static void heap_page_free(rb_objspace_t *objspace, struct heap_page *page);

void
rb_objspace_free(rb_objspace_t *objspace)
{
    if (is_lazy_sweeping(heap_eden))
	rb_bug("lazy sweeping underway when freeing object space");

    if (objspace->profile.records) {
	free(objspace->profile.records);
	objspace->profile.records = 0;
    }

    if (global_list) {
	struct gc_list *list, *next;
	for (list = global_list; list; list = next) {
	    next = list->next;
	    xfree(list);
	}
    }
    if (heap_pages_sorted) {
	size_t i;
	for (i = 0; i < heap_allocated_pages; ++i) {
	    heap_page_free(objspace, heap_pages_sorted[i]);
	}
	free(heap_pages_sorted);
	heap_allocated_pages = 0;
	heap_pages_sorted_length = 0;
	heap_pages_lomem = 0;
	heap_pages_himem = 0;

	objspace->eden_heap.total_pages = 0;
	objspace->eden_heap.total_slots = 0;
    }
    st_free_table(objspace->id_to_obj_tbl);
    st_free_table(objspace->obj_to_id_tbl);
    free_stack_chunks(&objspace->mark_stack);
    free(objspace);
}

static void
heap_pages_expand_sorted_to(rb_objspace_t *objspace, size_t next_length)
{
    struct heap_page **sorted;
    size_t size = size_mul_or_raise(next_length, sizeof(struct heap_page *), rb_eRuntimeError);

    gc_report(3, objspace, "heap_pages_expand_sorted: next_length: %"PRIdSIZE", size: %"PRIdSIZE"\n",
              next_length, size);

    if (heap_pages_sorted_length > 0) {
	sorted = (struct heap_page **)realloc(heap_pages_sorted, size);
	if (sorted) heap_pages_sorted = sorted;
    }
    else {
	sorted = heap_pages_sorted = (struct heap_page **)malloc(size);
    }

    if (sorted == 0) {
	rb_memerror();
    }

    heap_pages_sorted_length = next_length;
}

static void
heap_pages_expand_sorted(rb_objspace_t *objspace)
{
    /* usually heap_allocatable_pages + heap_eden->total_pages == heap_pages_sorted_length
     * because heap_allocatable_pages contains heap_tomb->total_pages (recycle heap_tomb pages).
     * however, if there are pages which do not have empty slots, then try to create new pages
     * so that the additional allocatable_pages counts (heap_tomb->total_pages) are added.
     */
    size_t next_length = heap_allocatable_pages;
    next_length += heap_eden->total_pages;
    next_length += heap_tomb->total_pages;

    if (next_length > heap_pages_sorted_length) {
	heap_pages_expand_sorted_to(objspace, next_length);
    }

    GC_ASSERT(heap_allocatable_pages + heap_eden->total_pages <= heap_pages_sorted_length);
    GC_ASSERT(heap_allocated_pages <= heap_pages_sorted_length);
}

static void
heap_allocatable_pages_set(rb_objspace_t *objspace, size_t s)
{
    heap_allocatable_pages = s;
    heap_pages_expand_sorted(objspace);
}


static inline void
heap_page_add_freeobj(rb_objspace_t *objspace, struct heap_page *page, VALUE obj)
{
    RVALUE *p = (RVALUE *)obj;
    asan_unpoison_memory_region(&page->freelist, sizeof(RVALUE*), false);

    p->as.free.flags = 0;
    p->as.free.next = page->freelist;
    page->freelist = p;
    asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));

    if (RGENGC_CHECK_MODE &&
        /* obj should belong to page */
        !(&page->start[0] <= (RVALUE *)obj &&
          (RVALUE *)obj   <  &page->start[page->total_slots] &&
          obj % sizeof(RVALUE) == 0)) {
        rb_bug("heap_page_add_freeobj: %p is not rvalue.", (void *)p);
    }

    asan_poison_object(obj);

    gc_report(3, objspace, "heap_page_add_freeobj: add %p to freelist\n", (void *)obj);
}

static inline void
heap_add_freepage(rb_heap_t *heap, struct heap_page *page)
{
    asan_unpoison_memory_region(&page->freelist, sizeof(RVALUE*), false);
    GC_ASSERT(page->free_slots != 0);
    if (page->freelist) {
	page->free_next = heap->free_pages;
	heap->free_pages = page;
    }
    asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));
}

#if GC_ENABLE_INCREMENTAL_MARK
static inline int
heap_add_poolpage(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    asan_unpoison_memory_region(&page->freelist, sizeof(RVALUE*), false);
    if (page->freelist) {
	page->free_next = heap->pooled_pages;
	heap->pooled_pages = page;
	objspace->rincgc.pooled_slots += page->free_slots;
        asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));

	return TRUE;
    }
    else {
        asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));

	return FALSE;
    }
}
#endif

static void
heap_unlink_page(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    list_del(&page->page_node);
    heap->total_pages--;
    heap->total_slots -= page->total_slots;
}

static void rb_aligned_free(void *ptr);

static void
heap_page_free(rb_objspace_t *objspace, struct heap_page *page)
{
    heap_allocated_pages--;
    objspace->profile.total_freed_pages++;
    rb_aligned_free(GET_PAGE_BODY(page->start));
    free(page);
}

static void
heap_pages_free_unused_pages(rb_objspace_t *objspace)
{
    size_t i, j;

    if (!list_empty(&heap_tomb->pages)) {
	for (i = j = 1; j < heap_allocated_pages; i++) {
	    struct heap_page *page = heap_pages_sorted[i];

	    if (page->flags.in_tomb && page->free_slots == page->total_slots) {
		heap_unlink_page(objspace, heap_tomb, page);
		heap_page_free(objspace, page);
	    }
	    else {
		if (i != j) {
		    heap_pages_sorted[j] = page;
		}
		j++;
	    }
	}

        struct heap_page *hipage = heap_pages_sorted[heap_allocated_pages - 1];
        RVALUE *himem = hipage->start + hipage->total_slots;
        GC_ASSERT(himem <= heap_pages_himem);
        heap_pages_himem = himem;

	GC_ASSERT(j == heap_allocated_pages);
    }
}

static struct heap_page *
heap_page_allocate(rb_objspace_t *objspace)
{
    RVALUE *start, *end, *p;
    struct heap_page *page;
    struct heap_page_body *page_body = 0;
    size_t hi, lo, mid;
    int limit = HEAP_PAGE_OBJ_LIMIT;

    /* assign heap_page body (contains heap_page_header and RVALUEs) */
    page_body = (struct heap_page_body *)rb_aligned_malloc(HEAP_PAGE_ALIGN, HEAP_PAGE_SIZE);
    if (page_body == 0) {
	rb_memerror();
    }

    /* assign heap_page entry */
    page = calloc1(sizeof(struct heap_page));
    if (page == 0) {
        rb_aligned_free(page_body);
	rb_memerror();
    }

    /* adjust obj_limit (object number available in this page) */
    start = (RVALUE*)((VALUE)page_body + sizeof(struct heap_page_header));
    if ((VALUE)start % sizeof(RVALUE) != 0) {
	int delta = (int)(sizeof(RVALUE) - ((VALUE)start % sizeof(RVALUE)));
	start = (RVALUE*)((VALUE)start + delta);
	limit = (HEAP_PAGE_SIZE - (int)((VALUE)start - (VALUE)page_body))/(int)sizeof(RVALUE);
    }
    end = start + limit;

    /* setup heap_pages_sorted */
    lo = 0;
    hi = heap_allocated_pages;
    while (lo < hi) {
	struct heap_page *mid_page;

	mid = (lo + hi) / 2;
	mid_page = heap_pages_sorted[mid];
	if (mid_page->start < start) {
	    lo = mid + 1;
	}
	else if (mid_page->start > start) {
	    hi = mid;
	}
	else {
	    rb_bug("same heap page is allocated: %p at %"PRIuVALUE, (void *)page_body, (VALUE)mid);
	}
    }

    if (hi < heap_allocated_pages) {
	MEMMOVE(&heap_pages_sorted[hi+1], &heap_pages_sorted[hi], struct heap_page_header*, heap_allocated_pages - hi);
    }

    heap_pages_sorted[hi] = page;

    heap_allocated_pages++;

    GC_ASSERT(heap_eden->total_pages + heap_allocatable_pages <= heap_pages_sorted_length);
    GC_ASSERT(heap_eden->total_pages + heap_tomb->total_pages == heap_allocated_pages - 1);
    GC_ASSERT(heap_allocated_pages <= heap_pages_sorted_length);

    objspace->profile.total_allocated_pages++;

    if (heap_allocated_pages > heap_pages_sorted_length) {
	rb_bug("heap_page_allocate: allocated(%"PRIdSIZE") > sorted(%"PRIdSIZE")",
	       heap_allocated_pages, heap_pages_sorted_length);
    }

    if (heap_pages_lomem == 0 || heap_pages_lomem > start) heap_pages_lomem = start;
    if (heap_pages_himem < end) heap_pages_himem = end;

    page->start = start;
    page->total_slots = limit;
    page_body->header.page = page;

    for (p = start; p != end; p++) {
	gc_report(3, objspace, "assign_heap_page: %p is added to freelist\n", (void *)p);
	heap_page_add_freeobj(objspace, page, (VALUE)p);
    }
    page->free_slots = limit;

    asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));
    return page;
}

static struct heap_page *
heap_page_resurrect(rb_objspace_t *objspace)
{
    struct heap_page *page = 0, *next;

    list_for_each_safe(&heap_tomb->pages, page, next, page_node) {
        asan_unpoison_memory_region(&page->freelist, sizeof(RVALUE*), false);
	if (page->freelist != NULL) {
	    heap_unlink_page(objspace, heap_tomb, page);
            asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));
	    return page;
	}
    }

    return NULL;
}

static struct heap_page *
heap_page_create(rb_objspace_t *objspace)
{
    struct heap_page *page;
    const char *method = "recycle";

    heap_allocatable_pages--;

    page = heap_page_resurrect(objspace);

    if (page == NULL) {
	page = heap_page_allocate(objspace);
	method = "allocate";
    }
    if (0) fprintf(stderr, "heap_page_create: %s - %p, "
                   "heap_allocated_pages: %"PRIdSIZE", "
                   "heap_allocated_pages: %"PRIdSIZE", "
                   "tomb->total_pages: %"PRIdSIZE"\n",
                   method, (void *)page, heap_pages_sorted_length, heap_allocated_pages, heap_tomb->total_pages);
    return page;
}

static void
heap_add_page(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    page->flags.in_tomb = (heap == heap_tomb);
    list_add(&heap->pages, &page->page_node);
    heap->total_pages++;
    heap->total_slots += page->total_slots;
}

static void
heap_assign_page(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page = heap_page_create(objspace);
    heap_add_page(objspace, heap, page);
    heap_add_freepage(heap, page);
}

static void
heap_add_pages(rb_objspace_t *objspace, rb_heap_t *heap, size_t add)
{
    size_t i;

    heap_allocatable_pages_set(objspace, add);

    for (i = 0; i < add; i++) {
	heap_assign_page(objspace, heap);
    }

    GC_ASSERT(heap_allocatable_pages == 0);
}

static size_t
heap_extend_pages(rb_objspace_t *objspace, size_t free_slots, size_t total_slots)
{
    double goal_ratio = gc_params.heap_free_slots_goal_ratio;
    size_t used = heap_allocated_pages + heap_allocatable_pages;
    size_t next_used;

    if (goal_ratio == 0.0) {
	next_used = (size_t)(used * gc_params.growth_factor);
    }
    else {
	/* Find `f' where free_slots = f * total_slots * goal_ratio
	 * => f = (total_slots - free_slots) / ((1 - goal_ratio) * total_slots)
	 */
	double f = (double)(total_slots - free_slots) / ((1 - goal_ratio) * total_slots);

	if (f > gc_params.growth_factor) f = gc_params.growth_factor;
	if (f < 1.0) f = 1.1;

	next_used = (size_t)(f * used);

	if (0) {
	    fprintf(stderr,
		    "free_slots(%8"PRIuSIZE")/total_slots(%8"PRIuSIZE")=%1.2f,"
		    " G(%1.2f), f(%1.2f),"
		    " used(%8"PRIuSIZE") => next_used(%8"PRIuSIZE")\n",
		    free_slots, total_slots, free_slots/(double)total_slots,
		    goal_ratio, f, used, next_used);
	}
    }

    if (gc_params.growth_max_slots > 0) {
	size_t max_used = (size_t)(used + gc_params.growth_max_slots/HEAP_PAGE_OBJ_LIMIT);
	if (next_used > max_used) next_used = max_used;
    }

    return next_used - used;
}

static void
heap_set_increment(rb_objspace_t *objspace, size_t additional_pages)
{
    size_t used = heap_eden->total_pages;
    size_t next_used_limit = used + additional_pages;

    if (next_used_limit == heap_allocated_pages) next_used_limit++;

    heap_allocatable_pages_set(objspace, next_used_limit - used);

    gc_report(1, objspace, "heap_set_increment: heap_allocatable_pages is %"PRIdSIZE"\n",
              heap_allocatable_pages);
}

static int
heap_increment(rb_objspace_t *objspace, rb_heap_t *heap)
{
    if (heap_allocatable_pages > 0) {
	gc_report(1, objspace, "heap_increment: heap_pages_sorted_length: %"PRIdSIZE", "
                  "heap_pages_inc: %"PRIdSIZE", heap->total_pages: %"PRIdSIZE"\n",
		  heap_pages_sorted_length, heap_allocatable_pages, heap->total_pages);

	GC_ASSERT(heap_allocatable_pages + heap_eden->total_pages <= heap_pages_sorted_length);
	GC_ASSERT(heap_allocated_pages <= heap_pages_sorted_length);

	heap_assign_page(objspace, heap);
	return TRUE;
    }
    return FALSE;
}

static void
heap_prepare(rb_objspace_t *objspace, rb_heap_t *heap)
{
    GC_ASSERT(heap->free_pages == NULL);

    if (is_lazy_sweeping(heap)) {
	gc_sweep_continue(objspace, heap);
    }
    else if (is_incremental_marking(objspace)) {
	gc_marks_continue(objspace, heap);
    }

    if (heap->free_pages == NULL &&
	(will_be_incremental_marking(objspace) || heap_increment(objspace, heap) == FALSE) &&
	gc_start(objspace, GPR_FLAG_NEWOBJ) == FALSE) {
	rb_memerror();
    }
}

static RVALUE *
heap_get_freeobj_from_next_freepage(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page;
    RVALUE *p;

    while (heap->free_pages == NULL) {
	heap_prepare(objspace, heap);
    }
    page = heap->free_pages;
    heap->free_pages = page->free_next;
    heap->using_page = page;

    GC_ASSERT(page->free_slots != 0);
    asan_unpoison_memory_region(&page->freelist, sizeof(RVALUE*), false);
    p = page->freelist;
    page->freelist = NULL;
    asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));
    page->free_slots = 0;
    asan_unpoison_object((VALUE)p, true);
    return p;
}

static inline VALUE
heap_get_freeobj_head(rb_objspace_t *objspace, rb_heap_t *heap)
{
    RVALUE *p = heap->freelist;
    if (LIKELY(p != NULL)) {
        heap->freelist = p->as.free.next;
    }
    asan_unpoison_object((VALUE)p, true);
    return (VALUE)p;
}

static inline VALUE
heap_get_freeobj(rb_objspace_t *objspace, rb_heap_t *heap)
{
    RVALUE *p = heap->freelist;

    while (1) {
	if (LIKELY(p != NULL)) {
            asan_unpoison_object((VALUE)p, true);
	    heap->freelist = p->as.free.next;
	    return (VALUE)p;
	}
	else {
	    p = heap_get_freeobj_from_next_freepage(objspace, heap);
	}
    }
}

void
rb_objspace_set_event_hook(const rb_event_flag_t event)
{
    rb_objspace_t *objspace = &rb_objspace;
    objspace->hook_events = event & RUBY_INTERNAL_EVENT_OBJSPACE_MASK;
    objspace->flags.has_hook = (objspace->hook_events != 0);
}

static void
gc_event_hook_body(rb_execution_context_t *ec, rb_objspace_t *objspace, const rb_event_flag_t event, VALUE data)
{
    const VALUE *pc = ec->cfp->pc;
    if (pc && VM_FRAME_RUBYFRAME_P(ec->cfp)) {
        /* increment PC because source line is calculated with PC-1 */
        ec->cfp->pc++;
    }
    EXEC_EVENT_HOOK(ec, event, ec->cfp->self, 0, 0, 0, data);
    ec->cfp->pc = pc;
}

#define gc_event_hook_available_p(objspace) ((objspace)->flags.has_hook)
#define gc_event_hook_needed_p(objspace, event) ((objspace)->hook_events & (event))

#define gc_event_hook(objspace, event, data) do { \
    if (UNLIKELY(gc_event_hook_needed_p(objspace, event))) { \
	gc_event_hook_body(GET_EC(), (objspace), (event), (data)); \
    } \
} while (0)

static inline VALUE
newobj_init(VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, int wb_protected, rb_objspace_t *objspace, VALUE obj)
{
#if !__has_feature(memory_sanitizer)
    GC_ASSERT(BUILTIN_TYPE(obj) == T_NONE);
    GC_ASSERT((flags & FL_WB_PROTECTED) == 0);
#endif

    /* OBJSETUP */
    struct RVALUE buf = {
        .as = {
            .values =  {
                .basic = {
                    .flags = flags,
                    .klass = klass,
                },
                .v1 = v1,
                .v2 = v2,
                .v3 = v3,
            },
        },
    };
    MEMCPY(RANY(obj), &buf, RVALUE, 1);

#if RACTOR_CHECK_MODE
    rb_ractor_setup_belonging(obj);
#endif

#if RGENGC_CHECK_MODE
    GC_ASSERT(RVALUE_MARKED(obj) == FALSE);
    GC_ASSERT(RVALUE_MARKING(obj) == FALSE);
    GC_ASSERT(RVALUE_OLD_P(obj) == FALSE);
    GC_ASSERT(RVALUE_WB_UNPROTECTED(obj) == FALSE);

    if (flags & FL_PROMOTED1) {
        if (RVALUE_AGE(obj) != 2) rb_bug("newobj: %s of age (%d) != 2.", obj_info(obj), RVALUE_AGE(obj));
    }
    else {
        if (RVALUE_AGE(obj) > 0) rb_bug("newobj: %s of age (%d) > 0.", obj_info(obj), RVALUE_AGE(obj));
    }
    if (rgengc_remembered(objspace, (VALUE)obj)) rb_bug("newobj: %s is remembered.", obj_info(obj));
#endif

    if (UNLIKELY(wb_protected == FALSE)) {
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
    objspace->total_allocated_objects++;

#if GC_DEBUG
    RANY(obj)->file = rb_source_location_cstr(&RANY(obj)->line);
    GC_ASSERT(!SPECIAL_CONST_P(obj)); /* check alignment */
#endif

    gc_report(5, objspace, "newobj: %s\n", obj_info(obj));

#if RGENGC_OLD_NEWOBJ_CHECK > 0
    {
        static int newobj_cnt = RGENGC_OLD_NEWOBJ_CHECK;

        if (!is_incremental_marking(objspace) &&
            flags & FL_WB_PROTECTED &&   /* do not promote WB unprotected objects */
            ! RB_TYPE_P(obj, T_ARRAY)) { /* array.c assumes that allocated objects are new */
            if (--newobj_cnt == 0) {
                newobj_cnt = RGENGC_OLD_NEWOBJ_CHECK;

                gc_mark_set(objspace, obj);
                RVALUE_AGE_SET_OLD(objspace, obj);

                rb_gc_writebarrier_remember(obj);
            }
        }
    }
#endif
    check_rvalue_consistency(obj);
    return obj;
}

static inline VALUE
newobj_slowpath(VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, rb_objspace_t *objspace, int wb_protected)
{
    VALUE obj;

    if (UNLIKELY(during_gc || ruby_gc_stressful)) {
        if (during_gc) {
            dont_gc_on();
            during_gc = 0;
            rb_bug("object allocation during garbage collection phase");
        }

        if (ruby_gc_stressful) {
            if (!garbage_collect(objspace, GPR_FLAG_NEWOBJ)) {
                rb_memerror();
            }
        }
    }

    obj = heap_get_freeobj(objspace, heap_eden);

    newobj_init(klass, flags, v1, v2, v3, wb_protected, objspace, obj);
    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_NEWOBJ, obj);
    return obj;
}

NOINLINE(static VALUE newobj_slowpath_wb_protected(VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, rb_objspace_t *objspace));
NOINLINE(static VALUE newobj_slowpath_wb_unprotected(VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, rb_objspace_t *objspace));

static VALUE
newobj_slowpath_wb_protected(VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, rb_objspace_t *objspace)
{
    return newobj_slowpath(klass, flags, v1, v2, v3, objspace, TRUE);
}

static VALUE
newobj_slowpath_wb_unprotected(VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, rb_objspace_t *objspace)
{
    return newobj_slowpath(klass, flags, v1, v2, v3, objspace, FALSE);
}

static inline VALUE
newobj_of(VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, int wb_protected)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE obj;

    RB_VM_LOCK_ENTER();
    {

        RB_DEBUG_COUNTER_INC(obj_newobj);
        (void)RB_DEBUG_COUNTER_INC_IF(obj_newobj_wb_unprotected, !wb_protected);

#if GC_DEBUG_STRESS_TO_CLASS
        if (UNLIKELY(stress_to_class)) {
            long i, cnt = RARRAY_LEN(stress_to_class);
            for (i = 0; i < cnt; ++i) {
                if (klass == RARRAY_AREF(stress_to_class, i)) rb_memerror();
            }
        }
#endif
        if (!(during_gc ||
              ruby_gc_stressful ||
              gc_event_hook_available_p(objspace)) &&
            (obj = heap_get_freeobj_head(objspace, heap_eden)) != Qfalse) {
            newobj_init(klass, flags, v1, v2, v3, wb_protected, objspace, obj);
        }
        else {
            RB_DEBUG_COUNTER_INC(obj_newobj_slowpath);
            obj = wb_protected ?
              newobj_slowpath_wb_protected(klass, flags, v1, v2, v3, objspace) :
            newobj_slowpath_wb_unprotected(klass, flags, v1, v2, v3, objspace);
        }
    }
    RB_VM_LOCK_LEAVE();

    return obj;
}

VALUE
rb_wb_unprotected_newobj_of(VALUE klass, VALUE flags)
{
    GC_ASSERT((flags & FL_WB_PROTECTED) == 0);
    return newobj_of(klass, flags, 0, 0, 0, FALSE);
}

VALUE
rb_wb_protected_newobj_of(VALUE klass, VALUE flags)
{
    GC_ASSERT((flags & FL_WB_PROTECTED) == 0);
    return newobj_of(klass, flags, 0, 0, 0, TRUE);
}

/* for compatibility */

VALUE
rb_newobj(void)
{
    return newobj_of(0, T_NONE, 0, 0, 0, FALSE);
}

VALUE
rb_newobj_of(VALUE klass, VALUE flags)
{
    if ((flags & RUBY_T_MASK) == T_OBJECT) {
        return newobj_of(klass, (flags | ROBJECT_EMBED) & ~FL_WB_PROTECTED , Qundef, Qundef, Qundef, flags & FL_WB_PROTECTED);
    } else {
        return newobj_of(klass, flags & ~FL_WB_PROTECTED, 0, 0, 0, flags & FL_WB_PROTECTED);
    }
}

#define UNEXPECTED_NODE(func) \
    rb_bug(#func"(): GC does not handle T_NODE 0x%x(%p) 0x%"PRIxVALUE, \
	   BUILTIN_TYPE(obj), (void*)(obj), RBASIC(obj)->flags)

const char *
rb_imemo_name(enum imemo_type type)
{
    // put no default case to get a warning if an imemo type is missing
    switch (type) {
#define IMEMO_NAME(x) case imemo_##x: return #x;
        IMEMO_NAME(env);
        IMEMO_NAME(cref);
        IMEMO_NAME(svar);
        IMEMO_NAME(throw_data);
        IMEMO_NAME(ifunc);
        IMEMO_NAME(memo);
        IMEMO_NAME(ment);
        IMEMO_NAME(iseq);
        IMEMO_NAME(tmpbuf);
        IMEMO_NAME(ast);
        IMEMO_NAME(parser_strterm);
        IMEMO_NAME(callinfo);
        IMEMO_NAME(callcache);
#undef IMEMO_NAME
    }
    return "unknown";
}

#undef rb_imemo_new

VALUE
rb_imemo_new(enum imemo_type type, VALUE v1, VALUE v2, VALUE v3, VALUE v0)
{
    VALUE flags = T_IMEMO | (type << FL_USHIFT);
    return newobj_of(v0, flags, v1, v2, v3, TRUE);
}

static VALUE
rb_imemo_tmpbuf_new(VALUE v1, VALUE v2, VALUE v3, VALUE v0)
{
    VALUE flags = T_IMEMO | (imemo_tmpbuf << FL_USHIFT);
    return newobj_of(v0, flags, v1, v2, v3, FALSE);
}

static VALUE
rb_imemo_tmpbuf_auto_free_maybe_mark_buffer(void *buf, size_t cnt)
{
    return rb_imemo_tmpbuf_new((VALUE)buf, 0, (VALUE)cnt, 0);
}

rb_imemo_tmpbuf_t *
rb_imemo_tmpbuf_parser_heap(void *buf, rb_imemo_tmpbuf_t *old_heap, size_t cnt)
{
    return (rb_imemo_tmpbuf_t *)rb_imemo_tmpbuf_new((VALUE)buf, (VALUE)old_heap, (VALUE)cnt, 0);
}

static size_t
imemo_memsize(VALUE obj)
{
    size_t size = 0;
    switch (imemo_type(obj)) {
      case imemo_ment:
        size += sizeof(RANY(obj)->as.imemo.ment.def);
        break;
      case imemo_iseq:
        size += rb_iseq_memsize((rb_iseq_t *)obj);
        break;
      case imemo_env:
        size += RANY(obj)->as.imemo.env.env_size * sizeof(VALUE);
        break;
      case imemo_tmpbuf:
        size += RANY(obj)->as.imemo.alloc.cnt * sizeof(VALUE);
        break;
      case imemo_ast:
        size += rb_ast_memsize(&RANY(obj)->as.imemo.ast);
        break;
      case imemo_cref:
      case imemo_svar:
      case imemo_throw_data:
      case imemo_ifunc:
      case imemo_memo:
      case imemo_parser_strterm:
        break;
      default:
        /* unreachable */
        break;
    }
    return size;
}

#if IMEMO_DEBUG
VALUE
rb_imemo_new_debug(enum imemo_type type, VALUE v1, VALUE v2, VALUE v3, VALUE v0, const char *file, int line)
{
    VALUE memo = rb_imemo_new(type, v1, v2, v3, v0);
    fprintf(stderr, "memo %p (type: %d) @ %s:%d\n", (void *)memo, imemo_type(memo), file, line);
    return memo;
}
#endif

VALUE
rb_class_allocate_instance(VALUE klass)
{
    VALUE flags = T_OBJECT | ROBJECT_EMBED;
    return newobj_of(klass, flags, Qundef, Qundef, Qundef, RGENGC_WB_PROTECTED_OBJECT);
}

VALUE
rb_data_object_wrap(VALUE klass, void *datap, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    RUBY_ASSERT_ALWAYS(dfree != (RUBY_DATA_FUNC)1);
    if (klass) Check_Type(klass, T_CLASS);
    return newobj_of(klass, T_DATA, (VALUE)dmark, (VALUE)dfree, (VALUE)datap, FALSE);
}

VALUE
rb_data_object_zalloc(VALUE klass, size_t size, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    VALUE obj = rb_data_object_wrap(klass, 0, dmark, dfree);
    DATA_PTR(obj) = xcalloc(1, size);
    return obj;
}

VALUE
rb_data_typed_object_wrap(VALUE klass, void *datap, const rb_data_type_t *type)
{
    RUBY_ASSERT_ALWAYS(type);
    if (klass) Check_Type(klass, T_CLASS);
    return newobj_of(klass, T_DATA, (VALUE)type, (VALUE)1, (VALUE)datap, type->flags & RUBY_FL_WB_PROTECTED);
}

VALUE
rb_data_typed_object_zalloc(VALUE klass, size_t size, const rb_data_type_t *type)
{
    VALUE obj = rb_data_typed_object_wrap(klass, 0, type);
    DATA_PTR(obj) = xcalloc(1, size);
    return obj;
}

size_t
rb_objspace_data_type_memsize(VALUE obj)
{
    if (RTYPEDDATA_P(obj)) {
	const rb_data_type_t *type = RTYPEDDATA_TYPE(obj);
	const void *ptr = RTYPEDDATA_DATA(obj);
	if (ptr && type->function.dsize) {
	    return type->function.dsize(ptr);
	}
    }
    return 0;
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

PUREFUNC(static inline int is_pointer_to_heap(rb_objspace_t *objspace, void *ptr);)
static inline int
is_pointer_to_heap(rb_objspace_t *objspace, void *ptr)
{
    register RVALUE *p = RANY(ptr);
    register struct heap_page *page;
    register size_t hi, lo, mid;

    RB_DEBUG_COUNTER_INC(gc_isptr_trial);

    if (p < heap_pages_lomem || p > heap_pages_himem) return FALSE;
    RB_DEBUG_COUNTER_INC(gc_isptr_range);

    if ((VALUE)p % sizeof(RVALUE) != 0) return FALSE;
    RB_DEBUG_COUNTER_INC(gc_isptr_align);

    /* check if p looks like a pointer using bsearch*/
    lo = 0;
    hi = heap_allocated_pages;
    while (lo < hi) {
	mid = (lo + hi) / 2;
	page = heap_pages_sorted[mid];
	if (page->start <= p) {
	    if (p < page->start + page->total_slots) {
                RB_DEBUG_COUNTER_INC(gc_isptr_maybe);

                if (page->flags.in_tomb) {
                    return FALSE;
                }
                else {
                    return TRUE;
                }
	    }
	    lo = mid + 1;
	}
	else {
	    hi = mid;
	}
    }
    return FALSE;
}

static enum rb_id_table_iterator_result
free_const_entry_i(VALUE value, void *data)
{
    rb_const_entry_t *ce = (rb_const_entry_t *)value;
    xfree(ce);
    return ID_TABLE_CONTINUE;
}

void
rb_free_const_table(struct rb_id_table *tbl)
{
    rb_id_table_foreach_values(tbl, free_const_entry_i, 0);
    rb_id_table_free(tbl);
}

static int
free_iv_index_tbl_free_i(st_data_t key, st_data_t value, st_data_t data)
{
    xfree((void *)value);
    return ST_CONTINUE;
}

static void
iv_index_tbl_free(struct st_table *tbl)
{
    st_foreach(tbl, free_iv_index_tbl_free_i, 0);
}

// alive: if false, target pointers can be freed already.
//        To check it, we need objspace parameter.
static void
vm_ccs_free(struct rb_class_cc_entries *ccs, int alive, rb_objspace_t *objspace, VALUE klass)
{
    if (ccs->entries) {
        for (int i=0; i<ccs->len; i++) {
            const struct rb_callcache *cc = ccs->entries[i].cc;
            if (!alive) {
                void *ptr = asan_poisoned_object_p((VALUE)cc);
                asan_unpoison_object((VALUE)cc, false);
                // ccs can be free'ed.
                if (is_pointer_to_heap(objspace, (void *)cc) &&
                    IMEMO_TYPE_P(cc, imemo_callcache) &&
                    cc->klass == klass) {
                    // OK. maybe target cc.
                }
                else {
                    if (ptr) {
                        asan_poison_object((VALUE)cc);
                    }
                    continue;
                }
                if (ptr) {
                    asan_poison_object((VALUE)cc);
                }
            }
            vm_cc_invalidate(cc);
        }
        ruby_xfree(ccs->entries);
    }
    ruby_xfree(ccs);
}

void
rb_vm_ccs_free(struct rb_class_cc_entries *ccs)
{
    RB_DEBUG_COUNTER_INC(ccs_free);
    vm_ccs_free(ccs, TRUE, NULL, Qundef);
}

struct cc_tbl_i_data {
    rb_objspace_t *objspace;
    VALUE klass;
    bool alive;
};

static enum rb_id_table_iterator_result
cc_table_mark_i(ID id, VALUE ccs_ptr, void *data_ptr)
{
    struct cc_tbl_i_data *data = data_ptr;
    struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)ccs_ptr;
    VM_ASSERT(vm_ccs_p(ccs));
    VM_ASSERT(id == ccs->cme->called_id);

    if (METHOD_ENTRY_INVALIDATED(ccs->cme)) {
        rb_vm_ccs_free(ccs);
        return ID_TABLE_DELETE;
    }
    else {
        gc_mark(data->objspace, (VALUE)ccs->cme);

        for (int i=0; i<ccs->len; i++) {
            VM_ASSERT(data->klass == ccs->entries[i].cc->klass);
            VM_ASSERT(ccs->cme == vm_cc_cme(ccs->entries[i].cc));

            gc_mark(data->objspace, (VALUE)ccs->entries[i].ci);
            gc_mark(data->objspace, (VALUE)ccs->entries[i].cc);
        }
        return ID_TABLE_CONTINUE;
    }
}

static void
cc_table_mark(rb_objspace_t *objspace, VALUE klass)
{
    struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);
    if (cc_tbl) {
        struct cc_tbl_i_data data = {
            .objspace = objspace,
            .klass = klass,
        };
        rb_id_table_foreach(cc_tbl, cc_table_mark_i, &data);
    }
}

static enum rb_id_table_iterator_result
cc_table_free_i(VALUE ccs_ptr, void *data_ptr)
{
    struct cc_tbl_i_data *data = data_ptr;
    struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)ccs_ptr;
    VM_ASSERT(vm_ccs_p(ccs));
    vm_ccs_free(ccs, data->alive, data->objspace, data->klass);
    return ID_TABLE_CONTINUE;
}

static void
cc_table_free(rb_objspace_t *objspace, VALUE klass, bool alive)
{
    struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);

    if (cc_tbl) {
        struct cc_tbl_i_data data = {
            .objspace = objspace,
            .klass = klass,
            .alive = alive,
        };
        rb_id_table_foreach_values(cc_tbl, cc_table_free_i, &data);
        rb_id_table_free(cc_tbl);
    }
}

void
rb_cc_table_free(VALUE klass)
{
    cc_table_free(&rb_objspace, klass, TRUE);
}

static inline void
make_zombie(rb_objspace_t *objspace, VALUE obj, void (*dfree)(void *), void *data)
{
    struct RZombie *zombie = RZOMBIE(obj);
    zombie->basic.flags = T_ZOMBIE | (zombie->basic.flags & FL_SEEN_OBJ_ID);
    zombie->dfree = dfree;
    zombie->data = data;
    zombie->next = heap_pages_deferred_final;
    heap_pages_deferred_final = (VALUE)zombie;

    struct heap_page *page = GET_HEAP_PAGE(obj);
    page->final_slots++;
    heap_pages_final_slots++;
}

static inline void
make_io_zombie(rb_objspace_t *objspace, VALUE obj)
{
    rb_io_t *fptr = RANY(obj)->as.file.fptr;
    make_zombie(objspace, obj, (void (*)(void*))rb_io_fptr_finalize, fptr);
}

static void
obj_free_object_id(rb_objspace_t *objspace, VALUE obj)
{
    st_data_t o = (st_data_t)obj, id;

    GC_ASSERT(FL_TEST(obj, FL_SEEN_OBJ_ID));
    FL_UNSET(obj, FL_SEEN_OBJ_ID);

    if (st_delete(objspace->obj_to_id_tbl, &o, &id)) {
        GC_ASSERT(id);
        st_delete(objspace->id_to_obj_tbl, &id, NULL);
    }
    else {
        rb_bug("Object ID seen, but not in mapping table: %s\n", obj_info(obj));
    }
}

static int
obj_free(rb_objspace_t *objspace, VALUE obj)
{
    RB_DEBUG_COUNTER_INC(obj_free);

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_FREEOBJ, obj);

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

    if (FL_TEST(obj, FL_EXIVAR)) {
	rb_free_generic_ivar((VALUE)obj);
	FL_UNSET(obj, FL_EXIVAR);
    }

    if (FL_TEST(obj, FL_SEEN_OBJ_ID) && !FL_TEST(obj, FL_FINALIZE)) {
        obj_free_object_id(objspace, obj);
    }

    if (RVALUE_WB_UNPROTECTED(obj)) CLEAR_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(obj), obj);

#if RGENGC_CHECK_MODE
#define CHECK(x) if (x(obj) != FALSE) rb_bug("obj_free: " #x "(%s) != FALSE", obj_info(obj))
	CHECK(RVALUE_WB_UNPROTECTED);
	CHECK(RVALUE_MARKED);
	CHECK(RVALUE_MARKING);
	CHECK(RVALUE_UNCOLLECTIBLE);
#undef CHECK
#endif

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        if (RANY(obj)->as.basic.flags & ROBJECT_EMBED) {
            RB_DEBUG_COUNTER_INC(obj_obj_embed);
        }
        else if (ROBJ_TRANSIENT_P(obj)) {
            RB_DEBUG_COUNTER_INC(obj_obj_transient);
        }
        else {
            xfree(RANY(obj)->as.object.as.heap.ivptr);
            RB_DEBUG_COUNTER_INC(obj_obj_ptr);
        }
        break;
      case T_MODULE:
      case T_CLASS:
        mjit_remove_class_serial(RCLASS_SERIAL(obj));
	rb_id_table_free(RCLASS_M_TBL(obj));
        cc_table_free(objspace, obj, FALSE);
	if (RCLASS_IV_TBL(obj)) {
	    st_free_table(RCLASS_IV_TBL(obj));
	}
	if (RCLASS_CONST_TBL(obj)) {
	    rb_free_const_table(RCLASS_CONST_TBL(obj));
	}
	if (RCLASS_IV_INDEX_TBL(obj)) {
            iv_index_tbl_free(RCLASS_IV_INDEX_TBL(obj));
	}
	if (RCLASS_EXT(obj)->subclasses) {
	    if (BUILTIN_TYPE(obj) == T_MODULE) {
		rb_class_detach_module_subclasses(obj);
	    }
	    else {
		rb_class_detach_subclasses(obj);
	    }
	    RCLASS_EXT(obj)->subclasses = NULL;
	}
	rb_class_remove_from_module_subclasses(obj);
	rb_class_remove_from_super_subclasses(obj);
	if (RANY(obj)->as.klass.ptr)
	    xfree(RANY(obj)->as.klass.ptr);
	RANY(obj)->as.klass.ptr = NULL;

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
        if (/* RHASH_AR_TABLE_P(obj) */ !FL_TEST_RAW(obj, RHASH_ST_TABLE_FLAG)) {
            struct ar_table_struct *tab = RHASH(obj)->as.ar;

            if (tab) {
                if (RHASH_TRANSIENT_P(obj)) {
                    RB_DEBUG_COUNTER_INC(obj_hash_transient);
                }
                else {
                    ruby_xfree(tab);
                }
            }
        }
        else {
            GC_ASSERT(RHASH_ST_TABLE_P(obj));
            st_free_table(RHASH(obj)->as.st);
        }
	break;
      case T_REGEXP:
	if (RANY(obj)->as.regexp.ptr) {
	    onig_free(RANY(obj)->as.regexp.ptr);
            RB_DEBUG_COUNTER_INC(obj_regexp_ptr);
	}
	break;
      case T_DATA:
	if (DATA_PTR(obj)) {
	    int free_immediately = FALSE;
	    void (*dfree)(void *);
	    void *data = DATA_PTR(obj);

	    if (RTYPEDDATA_P(obj)) {
		free_immediately = (RANY(obj)->as.typeddata.type->flags & RUBY_TYPED_FREE_IMMEDIATELY) != 0;
		dfree = RANY(obj)->as.typeddata.type->function.dfree;
		if (0 && free_immediately == 0) {
		    /* to expose non-free-immediate T_DATA */
		    fprintf(stderr, "not immediate -> %s\n", RANY(obj)->as.typeddata.type->wrap_struct_name);
		}
	    }
	    else {
		dfree = RANY(obj)->as.data.dfree;
	    }

	    if (dfree) {
		if (dfree == RUBY_DEFAULT_FREE) {
		    xfree(data);
                    RB_DEBUG_COUNTER_INC(obj_data_xfree);
		}
		else if (free_immediately) {
		    (*dfree)(data);
                    RB_DEBUG_COUNTER_INC(obj_data_imm_free);
		}
		else {
		    make_zombie(objspace, obj, dfree, data);
                    RB_DEBUG_COUNTER_INC(obj_data_zombie);
		    return 1;
		}
	    }
            else {
                RB_DEBUG_COUNTER_INC(obj_data_empty);
            }
	}
	break;
      case T_MATCH:
	if (RANY(obj)->as.match.rmatch) {
            struct rmatch *rm = RANY(obj)->as.match.rmatch;
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
            if (rm->char_offset)
		xfree(rm->char_offset);
	    xfree(rm);

            RB_DEBUG_COUNTER_INC(obj_match_ptr);
	}
	break;
      case T_FILE:
	if (RANY(obj)->as.file.fptr) {
	    make_io_zombie(objspace, obj);
            RB_DEBUG_COUNTER_INC(obj_file_ptr);
	    return 1;
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
	/* Basically , T_ICLASS shares table with the module */
        if (RICLASS_OWNS_M_TBL_P(obj)) {
            /* Method table is not shared for origin iclasses of classes */
            rb_id_table_free(RCLASS_M_TBL(obj));
        }
	if (RCLASS_CALLABLE_M_TBL(obj) != NULL) {
	    rb_id_table_free(RCLASS_CALLABLE_M_TBL(obj));
	}
	if (RCLASS_EXT(obj)->subclasses) {
	    rb_class_detach_subclasses(obj);
	    RCLASS_EXT(obj)->subclasses = NULL;
	}
        cc_table_free(objspace, obj, FALSE);
	rb_class_remove_from_module_subclasses(obj);
	rb_class_remove_from_super_subclasses(obj);
	xfree(RANY(obj)->as.klass.ptr);
	RANY(obj)->as.klass.ptr = NULL;

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
            RANY(obj)->as.rstruct.as.heap.ptr == NULL) {
            RB_DEBUG_COUNTER_INC(obj_struct_embed);
        }
        else if (RSTRUCT_TRANSIENT_P(obj)) {
            RB_DEBUG_COUNTER_INC(obj_struct_transient);
        }
        else {
            xfree((void *)RANY(obj)->as.rstruct.as.heap.ptr);
            RB_DEBUG_COUNTER_INC(obj_struct_ptr);
	}
	break;

      case T_SYMBOL:
	{
            rb_gc_free_dsymbol(obj);
            RB_DEBUG_COUNTER_INC(obj_symbol);
	}
	break;

      case T_IMEMO:
	switch (imemo_type(obj)) {
	  case imemo_ment:
	    rb_free_method_entry(&RANY(obj)->as.imemo.ment);
            RB_DEBUG_COUNTER_INC(obj_imemo_ment);
	    break;
	  case imemo_iseq:
	    rb_iseq_free(&RANY(obj)->as.imemo.iseq);
            RB_DEBUG_COUNTER_INC(obj_imemo_iseq);
	    break;
	  case imemo_env:
	    GC_ASSERT(VM_ENV_ESCAPED_P(RANY(obj)->as.imemo.env.ep));
	    xfree((VALUE *)RANY(obj)->as.imemo.env.env);
            RB_DEBUG_COUNTER_INC(obj_imemo_env);
	    break;
	  case imemo_tmpbuf:
	    xfree(RANY(obj)->as.imemo.alloc.ptr);
            RB_DEBUG_COUNTER_INC(obj_imemo_tmpbuf);
	    break;
	  case imemo_ast:
	    rb_ast_free(&RANY(obj)->as.imemo.ast);
            RB_DEBUG_COUNTER_INC(obj_imemo_ast);
	    break;
          case imemo_cref:
            RB_DEBUG_COUNTER_INC(obj_imemo_cref);
            break;
          case imemo_svar:
            RB_DEBUG_COUNTER_INC(obj_imemo_svar);
            break;
          case imemo_throw_data:
            RB_DEBUG_COUNTER_INC(obj_imemo_throw_data);
            break;
          case imemo_ifunc:
            RB_DEBUG_COUNTER_INC(obj_imemo_ifunc);
            break;
          case imemo_memo:
            RB_DEBUG_COUNTER_INC(obj_imemo_memo);
            break;
          case imemo_parser_strterm:
            RB_DEBUG_COUNTER_INC(obj_imemo_parser_strterm);
            break;
          case imemo_callinfo:
            RB_DEBUG_COUNTER_INC(obj_imemo_callinfo);
            break;
          case imemo_callcache:
            RB_DEBUG_COUNTER_INC(obj_imemo_callcache);
            break;
	  default:
            /* unreachable */
	    break;
	}
	return 0;

      default:
	rb_bug("gc_sweep(): unknown data type 0x%x(%p) 0x%"PRIxVALUE,
	       BUILTIN_TYPE(obj), (void*)obj, RBASIC(obj)->flags);
    }

    if (FL_TEST(obj, FL_FINALIZE)) {
        make_zombie(objspace, obj, 0, 0);
	return 1;
    }
    else {
	return 0;
    }
}


#define OBJ_ID_INCREMENT (sizeof(RVALUE) / 2)
#define OBJ_ID_INITIAL (OBJ_ID_INCREMENT * 2)

static int
object_id_cmp(st_data_t x, st_data_t y)
{
    if (RB_TYPE_P(x, T_BIGNUM)) {
        return !rb_big_eql(x, y);
    } else {
        return x != y;
    }
}

static st_index_t
object_id_hash(st_data_t n)
{
    if (RB_TYPE_P(n, T_BIGNUM)) {
        return FIX2LONG(rb_big_hash(n));
    } else {
        return st_numhash(n);
    }
}
static const struct st_hash_type object_id_hash_type = {
    object_id_cmp,
    object_id_hash,
};

void
Init_heap(void)
{
    rb_objspace_t *objspace = &rb_objspace;

#if defined(HAVE_SYSCONF) && defined(_SC_PAGE_SIZE)
    /* If Ruby's heap pages are not a multiple of the system page size, we
     * cannot use mprotect for the read barrier, so we must disable automatic
     * compaction. */
    int pagesize;
    pagesize = (int)sysconf(_SC_PAGE_SIZE);
    if ((HEAP_PAGE_SIZE % pagesize) != 0) {
        ruby_enable_autocompact = 0;
    }
#endif

    objspace->next_object_id = INT2FIX(OBJ_ID_INITIAL);
    objspace->id_to_obj_tbl = st_init_table(&object_id_hash_type);
    objspace->obj_to_id_tbl = st_init_numtable();

#if RGENGC_ESTIMATE_OLDMALLOC
    objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_min;
#endif

    heap_add_pages(objspace, heap_eden, gc_params.heap_init_slots / HEAP_PAGE_OBJ_LIMIT);
    init_mark_stack(&objspace->mark_stack);

    objspace->profile.invoke_time = getrusage_time();
    finalizer_table = st_init_numtable();
}

void
Init_gc_stress(void)
{
    rb_objspace_t *objspace = &rb_objspace;

    gc_stress_set(objspace, ruby_initial_gc_stress);
}

typedef int each_obj_callback(void *, void *, size_t, void *);

static void objspace_each_objects(rb_objspace_t *objspace, each_obj_callback *callback, void *data);
static void objspace_reachable_objects_from_root(rb_objspace_t *, void (func)(const char *, VALUE, void *), void *);

struct each_obj_args {
    rb_objspace_t *objspace;
    each_obj_callback *callback;
    void *data;
};

static void
objspace_each_objects_without_setup(rb_objspace_t *objspace, each_obj_callback *callback, void *data)
{
    size_t i;
    struct heap_page *page;
    RVALUE *pstart = NULL, *pend;

    i = 0;
    while (i < heap_allocated_pages) {
	while (0 < i && pstart < heap_pages_sorted[i-1]->start)              i--;
	while (i < heap_allocated_pages && heap_pages_sorted[i]->start <= pstart) i++;
	if (heap_allocated_pages <= i) break;

	page = heap_pages_sorted[i];

	pstart = page->start;
	pend = pstart + page->total_slots;

        if ((*callback)(pstart, pend, sizeof(RVALUE), data)) {
	    break;
	}
    }
}

static VALUE
objspace_each_objects_protected(VALUE arg)
{
    struct each_obj_args *args = (struct each_obj_args *)arg;
    objspace_each_objects_without_setup(args->objspace, args->callback, args->data);
    return Qnil;
}

static VALUE
incremental_enable(VALUE _)
{
    rb_objspace_t *objspace = &rb_objspace;

    objspace->flags.dont_incremental = FALSE;
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
 *   int
 *   sample_callback(void *vstart, void *vend, int stride, void *data) {
 *     VALUE v = (VALUE)vstart;
 *     for (; v != (VALUE)vend; v += stride) {
 *       if (RBASIC(v)->flags) { // liveness check
 *       // do something with live object 'v'
 *     }
 *     return 0; // continue to iteration
 *   }
 *
 * Note: 'vstart' is not a top of heap_page.  This point the first
 *       living object to grasp at least one object to avoid GC issue.
 *       This means that you can not walk through all Ruby object page
 *       including freed object page.
 *
 * Note: On this implementation, 'stride' is same as sizeof(RVALUE).
 *       However, there are possibilities to pass variable values with
 *       'stride' with some reasons.  You must use stride instead of
 *       use some constant value in the iteration.
 */
void
rb_objspace_each_objects(each_obj_callback *callback, void *data)
{
    objspace_each_objects(&rb_objspace, callback, data);
}

static void
objspace_each_objects(rb_objspace_t *objspace, each_obj_callback *callback, void *data)
{
    int prev_dont_incremental = objspace->flags.dont_incremental;

    gc_rest(objspace);
    objspace->flags.dont_incremental = TRUE;

    if (prev_dont_incremental) {
        objspace_each_objects_without_setup(objspace, callback, data);
    }
    else {
        struct each_obj_args args = {objspace, callback, data};
        rb_ensure(objspace_each_objects_protected, (VALUE)&args, incremental_enable, Qnil);
    }
}

void
rb_objspace_each_objects_without_setup(each_obj_callback *callback, void *data)
{
    objspace_each_objects_without_setup(&rb_objspace, callback, data);
}

struct os_each_struct {
    size_t num;
    VALUE of;
};

static int
internal_object_p(VALUE obj)
{
    RVALUE *p = (RVALUE *)obj;
    void *ptr = __asan_region_is_poisoned(p, SIZEOF_VALUE);
    asan_unpoison_object(obj, false);
    bool used_p = p->as.basic.flags;

    if (used_p) {
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
	    if (!p->as.basic.klass) break;
	    if (FL_TEST(obj, FL_SINGLETON)) {
		return rb_singleton_class_internal_p(obj);
	    }
	    return 0;
	  default:
	    if (!p->as.basic.klass) break;
	    return 0;
	}
    }
    if (ptr || ! used_p) {
        asan_poison_object(obj);
    }
    return 1;
}

int
rb_objspace_internal_object_p(VALUE obj)
{
    return internal_object_p(obj);
}

static int
os_obj_of_i(void *vstart, void *vend, size_t stride, void *data)
{
    struct os_each_struct *oes = (struct os_each_struct *)data;
    RVALUE *p = (RVALUE *)vstart, *pend = (RVALUE *)vend;

    for (; p != pend; p++) {
	volatile VALUE v = (VALUE)p;
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
    rb_objspace_t *objspace = &rb_objspace;
    st_data_t data = obj;
    rb_check_frozen(obj);
    st_delete(finalizer_table, &data, 0);
    FL_UNSET(obj, FL_FINALIZE);
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
    should_be_finalizable(obj);
    if (argc == 1) {
	block = rb_block_proc();
    }
    else {
	should_be_callable(block);
    }

    if (rb_callable_receiver(block) == obj) {
        rb_warn("finalizer references object to be finalized");
    }

    return define_final0(obj, block);
}

static VALUE
define_final0(VALUE obj, VALUE block)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE table;
    st_data_t data;

    RBASIC(obj)->flags |= FL_FINALIZE;

    block = rb_ary_new3(2, INT2FIX(0), block);
    OBJ_FREEZE(block);

    if (st_lookup(finalizer_table, obj, &data)) {
	table = (VALUE)data;

	/* avoid duplicate block, table is usually small */
	{
	    long len = RARRAY_LEN(table);
	    long i;

            for (i = 0; i < len; i++) {
                VALUE recv = RARRAY_AREF(table, i);
                if (rb_funcall(recv, idEq, 1, block)) {
                    return recv;
		}
	    }
	}

	rb_ary_push(table, block);
    }
    else {
	table = rb_ary_new3(1, block);
	RBASIC_CLEAR_CLASS(table);
	st_add_direct(finalizer_table, obj, table);
    }
    return block;
}

VALUE
rb_define_finalizer(VALUE obj, VALUE block)
{
    should_be_finalizable(obj);
    should_be_callable(block);
    return define_final0(obj, block);
}

void
rb_gc_copy_finalizer(VALUE dest, VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE table;
    st_data_t data;

    if (!FL_TEST(obj, FL_FINALIZE)) return;
    if (st_lookup(finalizer_table, obj, &data)) {
	table = (VALUE)data;
	st_insert(finalizer_table, dest, table);
    }
    FL_SET(dest, FL_FINALIZE);
}

static VALUE
run_single_final(VALUE final, VALUE objid)
{
    const VALUE cmd = RARRAY_AREF(final, 1);
    return rb_check_funcall(cmd, idCall, 1, &objid);
}

static void
run_finalizer(rb_objspace_t *objspace, VALUE obj, VALUE table)
{
    long i;
    enum ruby_tag_type state;
    volatile struct {
	VALUE errinfo;
	VALUE objid;
	rb_control_frame_t *cfp;
	long finished;
    } saved;
    rb_execution_context_t * volatile ec = GET_EC();
#define RESTORE_FINALIZER() (\
	ec->cfp = saved.cfp, \
	rb_set_errinfo(saved.errinfo))

    saved.errinfo = rb_errinfo();
    saved.objid = rb_obj_id(obj);
    saved.cfp = ec->cfp;
    saved.finished = 0;

    EC_PUSH_TAG(ec);
    state = EC_EXEC_TAG();
    if (state != TAG_NONE) {
	++saved.finished;	/* skip failed finalizer */
    }
    for (i = saved.finished;
	 RESTORE_FINALIZER(), i<RARRAY_LEN(table);
	 saved.finished = ++i) {
	run_single_final(RARRAY_AREF(table, i), saved.objid);
    }
    EC_POP_TAG();
#undef RESTORE_FINALIZER
}

static void
run_final(rb_objspace_t *objspace, VALUE zombie)
{
    st_data_t key, table;

    if (RZOMBIE(zombie)->dfree) {
	RZOMBIE(zombie)->dfree(RZOMBIE(zombie)->data);
    }

    key = (st_data_t)zombie;
    if (st_delete(finalizer_table, &key, &table)) {
	run_finalizer(objspace, zombie, (VALUE)table);
    }
}

static void
finalize_list(rb_objspace_t *objspace, VALUE zombie)
{
    while (zombie) {
        VALUE next_zombie;
        struct heap_page *page;
        asan_unpoison_object(zombie, false);
        next_zombie = RZOMBIE(zombie)->next;
        page = GET_HEAP_PAGE(zombie);

	run_final(objspace, zombie);

        GC_ASSERT(BUILTIN_TYPE(zombie) == T_ZOMBIE);
        if (FL_TEST(zombie, FL_SEEN_OBJ_ID)) {
            obj_free_object_id(objspace, zombie);
        }

	RZOMBIE(zombie)->basic.flags = 0;
        GC_ASSERT(heap_pages_final_slots > 0);
        GC_ASSERT(page->final_slots > 0);
        heap_pages_final_slots--;
	page->final_slots--;
	page->free_slots++;
	heap_page_add_freeobj(objspace, GET_HEAP_PAGE(zombie), zombie);

	objspace->profile.total_freed_objects++;

	zombie = next_zombie;
    }
}

static void
finalize_deferred(rb_objspace_t *objspace)
{
    VALUE zombie;

    while ((zombie = ATOMIC_VALUE_EXCHANGE(heap_pages_deferred_final, 0)) != 0) {
	finalize_list(objspace, zombie);
    }
}

static void
gc_finalize_deferred(void *dmy)
{
    rb_objspace_t *objspace = dmy;
    if (ATOMIC_EXCHANGE(finalizing, 1)) return;
    finalize_deferred(objspace);
    ATOMIC_SET(finalizing, 0);
}

static void
gc_finalize_deferred_register(rb_objspace_t *objspace)
{
    if (rb_postponed_job_register_one(0, gc_finalize_deferred, objspace) == 0) {
	rb_bug("gc_finalize_deferred_register: can't register finalizer.");
    }
}

struct force_finalize_list {
    VALUE obj;
    VALUE table;
    struct force_finalize_list *next;
};

static int
force_chain_object(st_data_t key, st_data_t val, st_data_t arg)
{
    struct force_finalize_list **prev = (struct force_finalize_list **)arg;
    struct force_finalize_list *curr = ALLOC(struct force_finalize_list);
    curr->obj = key;
    curr->table = val;
    curr->next = *prev;
    *prev = curr;
    return ST_CONTINUE;
}

bool rb_obj_is_main_ractor(VALUE gv);

void
rb_objspace_call_finalizer(rb_objspace_t *objspace)
{
    RVALUE *p, *pend;
    size_t i;

#if RGENGC_CHECK_MODE >= 2
    gc_verify_internal_consistency(objspace);
#endif
    gc_rest(objspace);

    if (ATOMIC_EXCHANGE(finalizing, 1)) return;

    /* run finalizers */
    finalize_deferred(objspace);
    GC_ASSERT(heap_pages_deferred_final == 0);

    gc_rest(objspace);
    /* prohibit incremental GC */
    objspace->flags.dont_incremental = 1;

    /* force to run finalizer */
    while (finalizer_table->num_entries) {
	struct force_finalize_list *list = 0;
	st_foreach(finalizer_table, force_chain_object, (st_data_t)&list);
	while (list) {
	    struct force_finalize_list *curr = list;
	    st_data_t obj = (st_data_t)curr->obj;
	    run_finalizer(objspace, curr->obj, curr->table);
	    st_delete(finalizer_table, &obj, 0);
	    list = curr->next;
	    xfree(curr);
	}
    }

    /* prohibit GC because force T_DATA finalizers can break an object graph consistency */
    dont_gc_on();

    /* running data/file finalizers are part of garbage collection */
    unsigned int lock_lev;
    gc_enter(objspace, "rb_objspace_call_finalizer", &lock_lev);

    /* run data/file object's finalizers */
    for (i = 0; i < heap_allocated_pages; i++) {
	p = heap_pages_sorted[i]->start; pend = p + heap_pages_sorted[i]->total_slots;
	while (p < pend) {
            VALUE vp = (VALUE)p;
            void *poisoned = asan_poisoned_object_p(vp);
            asan_unpoison_object(vp, false);
            switch (BUILTIN_TYPE(vp)) {
	      case T_DATA:
		if (!DATA_PTR(p) || !RANY(p)->as.data.dfree) break;
                if (rb_obj_is_thread(vp)) break;
                if (rb_obj_is_mutex(vp)) break;
                if (rb_obj_is_fiber(vp)) break;
                if (rb_obj_is_main_ractor(vp)) break;
                if (RTYPEDDATA_P(vp)) {
		    RDATA(p)->dfree = RANY(p)->as.typeddata.type->function.dfree;
		}
                p->as.free.flags = 0;
		if (RANY(p)->as.data.dfree == RUBY_DEFAULT_FREE) {
		    xfree(DATA_PTR(p));
		}
		else if (RANY(p)->as.data.dfree) {
                    make_zombie(objspace, vp, RANY(p)->as.data.dfree, RANY(p)->as.data.data);
		}
		break;
	      case T_FILE:
		if (RANY(p)->as.file.fptr) {
                    make_io_zombie(objspace, vp);
		}
		break;
              default:
                break;
	    }
            if (poisoned) {
                GC_ASSERT(BUILTIN_TYPE(vp) == T_NONE);
                asan_poison_object(vp);
            }
	    p++;
	}
    }

    gc_exit(objspace, "rb_objspace_call_finalizer", &lock_lev);

    if (heap_pages_deferred_final) {
	finalize_list(objspace, heap_pages_deferred_final);
    }

    st_free_table(finalizer_table);
    finalizer_table = 0;
    ATOMIC_SET(finalizing, 0);
}

PUREFUNC(static inline int is_id_value(rb_objspace_t *objspace, VALUE ptr));
static inline int
is_id_value(rb_objspace_t *objspace, VALUE ptr)
{
    if (!is_pointer_to_heap(objspace, (void *)ptr)) return FALSE;
    if (BUILTIN_TYPE(ptr) > T_FIXNUM) return FALSE;
    if (BUILTIN_TYPE(ptr) == T_ICLASS) return FALSE;
    return TRUE;
}

static inline int
heap_is_swept_object(rb_objspace_t *objspace, rb_heap_t *heap, VALUE ptr)
{
    struct heap_page *page = GET_HEAP_PAGE(ptr);
    return page->flags.before_sweep ? FALSE : TRUE;
}

static inline int
is_swept_object(rb_objspace_t *objspace, VALUE ptr)
{
    if (heap_is_swept_object(objspace, heap_eden, ptr)) {
	return TRUE;
    }
    else {
	return FALSE;
    }
}

/* garbage objects will be collected soon. */
static inline int
is_garbage_object(rb_objspace_t *objspace, VALUE ptr)
{
    if (!is_lazy_sweeping(heap_eden) ||
	is_swept_object(objspace, ptr) ||
	MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(ptr), ptr)) {

	return FALSE;
    }
    else {
	return TRUE;
    }
}

static inline int
is_live_object(rb_objspace_t *objspace, VALUE ptr)
{
    switch (BUILTIN_TYPE(ptr)) {
      case T_NONE:
      case T_MOVED:
      case T_ZOMBIE:
	return FALSE;
      default:
        break;
    }

    if (!is_garbage_object(objspace, ptr)) {
	return TRUE;
    }
    else {
	return FALSE;
    }
}

static inline int
is_markable_object(rb_objspace_t *objspace, VALUE obj)
{
    if (rb_special_const_p(obj)) return FALSE; /* special const is not markable */
    check_rvalue_consistency(obj);
    return TRUE;
}

int
rb_objspace_markable_object_p(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;
    return is_markable_object(objspace, obj) && is_live_object(objspace, obj);
}

int
rb_objspace_garbage_object_p(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;
    return is_garbage_object(objspace, obj);
}

static VALUE
id2ref_obj_tbl(rb_objspace_t *objspace, VALUE objid)
{
    VALUE orig;
    if (st_lookup(objspace->id_to_obj_tbl, objid, &orig)) {
        return orig;
    }
    else {
        return Qundef;
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
 */

static VALUE
id2ref(VALUE objid)
{
#if SIZEOF_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULONG(x)
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULL(x)
#endif
    rb_objspace_t *objspace = &rb_objspace;
    VALUE ptr;
    VALUE orig;
    void *p0;

    objid = rb_to_int(objid);
    if (FIXNUM_P(objid) || rb_big_size(objid) <= SIZEOF_VOIDP) {
        ptr = NUM2PTR(objid);
        if (ptr == Qtrue) return Qtrue;
        if (ptr == Qfalse) return Qfalse;
        if (ptr == Qnil) return Qnil;
        if (FIXNUM_P(ptr)) return (VALUE)ptr;
        if (FLONUM_P(ptr)) return (VALUE)ptr;

        ptr = obj_id_to_ref(objid);
        if ((ptr % sizeof(RVALUE)) == (4 << 2)) {
            ID symid = ptr / sizeof(RVALUE);
            p0 = (void *)ptr;
            if (rb_id2str(symid) == 0)
                rb_raise(rb_eRangeError, "%p is not symbol id value", p0);
            return ID2SYM(symid);
        }
    }

    if ((orig = id2ref_obj_tbl(objspace, objid)) != Qundef &&
        is_live_object(objspace, orig)) {
        return orig;
    }

    if (rb_int_ge(objid, objspace->next_object_id)) {
        rb_raise(rb_eRangeError, "%+"PRIsVALUE" is not id value", rb_int2str(objid, 10));
    } else {
        rb_raise(rb_eRangeError, "%+"PRIsVALUE" is recycled object", rb_int2str(objid, 10));
    }
}

static VALUE
os_id2ref(VALUE os, VALUE objid)
{
    return id2ref(objid);
}

static VALUE
rb_find_object_id(VALUE obj, VALUE (*get_heap_object_id)(VALUE))
{
    if (STATIC_SYM_P(obj)) {
        return (SYM2ID(obj) * sizeof(RVALUE) + (4 << 2)) | FIXNUM_FLAG;
    }
    else if (FLONUM_P(obj)) {
#if SIZEOF_LONG == SIZEOF_VOIDP
        return LONG2NUM((SIGNED_VALUE)obj);
#else
        return LL2NUM((SIGNED_VALUE)obj);
#endif
    }
    else if (SPECIAL_CONST_P(obj)) {
        return LONG2NUM((SIGNED_VALUE)obj);
    }

    return get_heap_object_id(obj);
}

static VALUE
cached_object_id(VALUE obj)
{
    VALUE id;
    rb_objspace_t *objspace = &rb_objspace;

    if (st_lookup(objspace->obj_to_id_tbl, (st_data_t)obj, &id)) {
        GC_ASSERT(FL_TEST(obj, FL_SEEN_OBJ_ID));
        return id;
    }
    else {
        GC_ASSERT(!FL_TEST(obj, FL_SEEN_OBJ_ID));

        id = objspace->next_object_id;
        objspace->next_object_id = rb_int_plus(id, INT2FIX(OBJ_ID_INCREMENT));

        VALUE already_disabled = rb_gc_disable_no_rest();
        st_insert(objspace->obj_to_id_tbl, (st_data_t)obj, (st_data_t)id);
        st_insert(objspace->id_to_obj_tbl, (st_data_t)id, (st_data_t)obj);
        if (already_disabled == Qfalse) rb_objspace_gc_enable(objspace);
        FL_SET(obj, FL_SEEN_OBJ_ID);

        return id;
    }
}

static VALUE
nonspecial_obj_id_(VALUE obj)
{
    return nonspecial_obj_id(obj);
}


VALUE
rb_memory_id(VALUE obj)
{
    return rb_find_object_id(obj, nonspecial_obj_id_);
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
    /*
     *                32-bit VALUE space
     *          MSB ------------------------ LSB
     *  false   00000000000000000000000000000000
     *  true    00000000000000000000000000000010
     *  nil     00000000000000000000000000000100
     *  undef   00000000000000000000000000000110
     *  symbol  ssssssssssssssssssssssss00001110
     *  object  oooooooooooooooooooooooooooooo00        = 0 (mod sizeof(RVALUE))
     *  fixnum  fffffffffffffffffffffffffffffff1
     *
     *                    object_id space
     *                                       LSB
     *  false   00000000000000000000000000000000
     *  true    00000000000000000000000000000010
     *  nil     00000000000000000000000000000100
     *  undef   00000000000000000000000000000110
     *  symbol   000SSSSSSSSSSSSSSSSSSSSSSSSSSS0        S...S % A = 4 (S...S = s...s * A + 4)
     *  object   oooooooooooooooooooooooooooooo0        o...o % A = 0
     *  fixnum  fffffffffffffffffffffffffffffff1        bignum if required
     *
     *  where A = sizeof(RVALUE)/4
     *
     *  sizeof(RVALUE) is
     *  20 if 32-bit, double is 4-byte aligned
     *  24 if 32-bit, double is 8-byte aligned
     *  40 if 64-bit
     */

    return rb_find_object_id(obj, cached_object_id);
}

static enum rb_id_table_iterator_result
cc_table_memsize_i(VALUE ccs_ptr, void *data_ptr)
{
    size_t *total_size = data_ptr;
    struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)ccs_ptr;
    *total_size += sizeof(*ccs);
    *total_size += sizeof(ccs->entries[0]) * ccs->capa;
    return ID_TABLE_CONTINUE;
}

static size_t
cc_table_memsize(struct rb_id_table *cc_table)
{
    size_t total = rb_id_table_memsize(cc_table);
    rb_id_table_foreach_values(cc_table, cc_table_memsize_i, &total);
    return total;
}

static size_t
obj_memsize_of(VALUE obj, int use_all_types)
{
    size_t size = 0;

    if (SPECIAL_CONST_P(obj)) {
	return 0;
    }

    if (FL_TEST(obj, FL_EXIVAR)) {
	size += rb_generic_ivar_memsize(obj);
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
	if (!(RBASIC(obj)->flags & ROBJECT_EMBED)) {
	    size += ROBJECT_NUMIV(obj) * sizeof(VALUE);
	}
	break;
      case T_MODULE:
      case T_CLASS:
	if (RCLASS_EXT(obj)) {
            if (RCLASS_M_TBL(obj)) {
                size += rb_id_table_memsize(RCLASS_M_TBL(obj));
            }
	    if (RCLASS_IV_TBL(obj)) {
		size += st_memsize(RCLASS_IV_TBL(obj));
	    }
	    if (RCLASS_IV_INDEX_TBL(obj)) {
                // TODO: more correct value
		size += st_memsize(RCLASS_IV_INDEX_TBL(obj));
	    }
	    if (RCLASS(obj)->ptr->iv_tbl) {
		size += st_memsize(RCLASS(obj)->ptr->iv_tbl);
	    }
	    if (RCLASS(obj)->ptr->const_tbl) {
		size += rb_id_table_memsize(RCLASS(obj)->ptr->const_tbl);
	    }
            if (RCLASS_CC_TBL(obj)) {
                size += cc_table_memsize(RCLASS_CC_TBL(obj));
            }
	    size += sizeof(rb_classext_t);
	}
	break;
      case T_ICLASS:
        if (RICLASS_OWNS_M_TBL_P(obj)) {
	    if (RCLASS_M_TBL(obj)) {
		size += rb_id_table_memsize(RCLASS_M_TBL(obj));
	    }
	}
        if (RCLASS_EXT(obj) && RCLASS_CC_TBL(obj)) {
            size += cc_table_memsize(RCLASS_CC_TBL(obj));
        }
	break;
      case T_STRING:
	size += rb_str_memsize(obj);
	break;
      case T_ARRAY:
	size += rb_ary_memsize(obj);
	break;
      case T_HASH:
        if (RHASH_AR_TABLE_P(obj)) {
            if (RHASH_AR_TABLE(obj) != NULL) {
                size_t rb_hash_ar_table_size();
                size += rb_hash_ar_table_size();
            }
	}
        else {
            VM_ASSERT(RHASH_ST_TABLE(obj) != NULL);
            size += st_memsize(RHASH_ST_TABLE(obj));
        }
	break;
      case T_REGEXP:
	if (RREGEXP_PTR(obj)) {
	    size += onig_memsize(RREGEXP_PTR(obj));
	}
	break;
      case T_DATA:
	if (use_all_types) size += rb_objspace_data_type_memsize(obj);
	break;
      case T_MATCH:
	if (RMATCH(obj)->rmatch) {
            struct rmatch *rm = RMATCH(obj)->rmatch;
	    size += onig_region_memsize(&rm->regs);
	    size += sizeof(struct rmatch_offset) * rm->char_offset_num_allocated;
	    size += sizeof(struct rmatch);
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
        size += imemo_memsize(obj);
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

    return size + sizeof(RVALUE);
}

size_t
rb_obj_memsize_of(VALUE obj)
{
    return obj_memsize_of(obj, TRUE);
}

static int
set_zero(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE k = (VALUE)key;
    VALUE hash = (VALUE)arg;
    rb_hash_aset(hash, k, INT2FIX(0));
    return ST_CONTINUE;
}

static VALUE
type_sym(size_t type)
{
    switch (type) {
#define COUNT_TYPE(t) case (t): return ID2SYM(rb_intern(#t)); break;
        COUNT_TYPE(T_NONE);
        COUNT_TYPE(T_OBJECT);
        COUNT_TYPE(T_CLASS);
        COUNT_TYPE(T_MODULE);
        COUNT_TYPE(T_FLOAT);
        COUNT_TYPE(T_STRING);
        COUNT_TYPE(T_REGEXP);
        COUNT_TYPE(T_ARRAY);
        COUNT_TYPE(T_HASH);
        COUNT_TYPE(T_STRUCT);
        COUNT_TYPE(T_BIGNUM);
        COUNT_TYPE(T_FILE);
        COUNT_TYPE(T_DATA);
        COUNT_TYPE(T_MATCH);
        COUNT_TYPE(T_COMPLEX);
        COUNT_TYPE(T_RATIONAL);
        COUNT_TYPE(T_NIL);
        COUNT_TYPE(T_TRUE);
        COUNT_TYPE(T_FALSE);
        COUNT_TYPE(T_SYMBOL);
        COUNT_TYPE(T_FIXNUM);
        COUNT_TYPE(T_IMEMO);
        COUNT_TYPE(T_UNDEF);
        COUNT_TYPE(T_NODE);
        COUNT_TYPE(T_ICLASS);
        COUNT_TYPE(T_ZOMBIE);
        COUNT_TYPE(T_MOVED);
#undef COUNT_TYPE
        default:              return SIZET2NUM(type); break;
    }
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
    rb_objspace_t *objspace = &rb_objspace;
    size_t counts[T_MASK+1];
    size_t freed = 0;
    size_t total = 0;
    size_t i;
    VALUE hash = Qnil;

    if (rb_check_arity(argc, 0, 1) == 1) {
        hash = argv[0];
        if (!RB_TYPE_P(hash, T_HASH))
            rb_raise(rb_eTypeError, "non-hash given");
    }

    for (i = 0; i <= T_MASK; i++) {
        counts[i] = 0;
    }

    for (i = 0; i < heap_allocated_pages; i++) {
	struct heap_page *page = heap_pages_sorted[i];
	RVALUE *p, *pend;

	p = page->start; pend = p + page->total_slots;
	for (;p < pend; p++) {
            VALUE vp = (VALUE)p;
            void *poisoned = asan_poisoned_object_p(vp);
            asan_unpoison_object(vp, false);
	    if (p->as.basic.flags) {
                counts[BUILTIN_TYPE(vp)]++;
	    }
	    else {
		freed++;
	    }
            if (poisoned) {
                GC_ASSERT(BUILTIN_TYPE(vp) == T_NONE);
                asan_poison_object(vp);
            }
	}
	total += page->total_slots;
    }

    if (hash == Qnil) {
        hash = rb_hash_new();
    }
    else if (!RHASH_EMPTY_P(hash)) {
        rb_hash_stlike_foreach(hash, set_zero, hash);
    }
    rb_hash_aset(hash, ID2SYM(rb_intern("TOTAL")), SIZET2NUM(total));
    rb_hash_aset(hash, ID2SYM(rb_intern("FREE")), SIZET2NUM(freed));

    for (i = 0; i <= T_MASK; i++) {
        VALUE type = type_sym(i);
        if (counts[i])
            rb_hash_aset(hash, type, SIZET2NUM(counts[i]));
    }

    return hash;
}

/*
  ------------------------ Garbage Collection ------------------------
*/

/* Sweeping */

static size_t
objspace_available_slots(rb_objspace_t *objspace)
{
    return heap_eden->total_slots + heap_tomb->total_slots;
}

static size_t
objspace_live_slots(rb_objspace_t *objspace)
{
    return (objspace->total_allocated_objects - objspace->profile.total_freed_objects) - heap_pages_final_slots;
}

static size_t
objspace_free_slots(rb_objspace_t *objspace)
{
    return objspace_available_slots(objspace) - objspace_live_slots(objspace) - heap_pages_final_slots;
}

static void
gc_setup_mark_bits(struct heap_page *page)
{
    /* copy oldgen bitmap to mark bitmap */
    memcpy(&page->mark_bits[0], &page->uncollectible_bits[0], HEAP_PAGE_BITMAP_SIZE);
}

static int gc_is_moveable_obj(rb_objspace_t *objspace, VALUE obj);
static VALUE gc_move(rb_objspace_t *objspace, VALUE scan, VALUE free);

static void
lock_page_body(rb_objspace_t *objspace, struct heap_page_body *body)
{
    /* If this is an explicit compaction (GC.compact), we don't need a read
     * barrier, so just return early. */
    if (objspace->flags.during_compacting >> 1) {
        return;
    }
#if defined(_WIN32)
    DWORD old_protect;

    if (!VirtualProtect(body, HEAP_PAGE_SIZE, PAGE_NOACCESS, &old_protect)) {
#else
    if(mprotect(body, HEAP_PAGE_SIZE, PROT_NONE)) {
#endif
        rb_bug("Couldn't protect page %p", (void *)body);
    } else {
        gc_report(5, objspace, "Protecting page in move %p\n", (void *)body);
    }
}

static void
unlock_page_body(rb_objspace_t *objspace, struct heap_page_body *body)
{
    /* If this is an explicit compaction (GC.compact), we don't need a read
     * barrier, so just return early. */
    if (objspace->flags.during_compacting >> 1) {
        return;
    }
#if defined(_WIN32)
    DWORD old_protect;

    if (!VirtualProtect(body, HEAP_PAGE_SIZE, PAGE_READWRITE, &old_protect)) {
#else
    if(mprotect(body, HEAP_PAGE_SIZE, PROT_READ | PROT_WRITE)) {
#endif
        rb_bug("Couldn't unprotect page %p", (void *)body);
    } else {
        gc_report(5, objspace, "Unprotecting page in move %p\n", (void *)body);
    }
}

static short
try_move(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *sweep_page, VALUE dest)
{
    struct heap_page * cursor = heap->compact_cursor;
    char from_freelist = 0;

    GC_ASSERT(!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(dest), dest));

    /* T_NONE objects came from the free list.  If the object is *not* a
     * T_NONE, it is an object that just got freed but hasn't been
     * added to the freelist yet */

    if (BUILTIN_TYPE(dest) == T_NONE) {
        from_freelist = 1;
    }

    while(1) {
        size_t index = heap->compact_cursor_index;

        bits_t *mark_bits = cursor->mark_bits;
        bits_t *pin_bits = cursor->pinned_bits;
        RVALUE * p = cursor->start;
        RVALUE * offset = p - NUM_IN_PAGE(p);

        /* Find an object to move and move it. Movable objects must be
         * marked, so we iterate using the marking bitmap */
        for (size_t i = index; i < HEAP_PAGE_BITMAP_LIMIT; i++) {
            bits_t bits = mark_bits[i] & ~pin_bits[i];

            if (bits) {
                p = offset + i * BITS_BITLENGTH;

                do {
                    if (bits & 1) {
                        /* We're trying to move "p" */
                        objspace->rcompactor.considered_count_table[BUILTIN_TYPE((VALUE)p)]++;

                        if (gc_is_moveable_obj(objspace, (VALUE)p)) {
                            /* We were able to move "p" */
                            objspace->rcompactor.moved_count_table[BUILTIN_TYPE((VALUE)p)]++;
                            objspace->rcompactor.total_moved++;
                            gc_move(objspace, (VALUE)p, dest);
                            gc_pin(objspace, (VALUE)p);
                            heap->compact_cursor_index = i;
                            if (from_freelist) {
                                FL_SET((VALUE)p, FL_FROM_FREELIST);
                            }

                            return 1;
                        }
                    }
                    p++;
                    bits >>= 1;
                } while (bits);
            }
        }

        /* We couldn't find a movable object on the compact cursor, so lets
         * move to the next page (previous page since we are traveling in the
         * opposite direction of the sweep cursor) and look there. */

        struct heap_page * next;

        next = list_prev(&heap->pages, cursor, page_node);

        /* Protect the current cursor since it probably has T_MOVED slots. */
        lock_page_body(objspace, GET_PAGE_BODY(cursor->start));

        heap->compact_cursor = next;
        heap->compact_cursor_index = 0;
        cursor = next;

        // Cursors have met, lets quit.  We set `heap->compact_cursor` equal
        // to `heap->sweeping_page` so we know how far to iterate through
        // the heap when unprotecting pages.
        if (next == sweep_page) {
            break;
        }
    }

    return 0;
}

static void
gc_unprotect_pages(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *cursor = heap->compact_cursor;

    while(cursor) {
        unlock_page_body(objspace, GET_PAGE_BODY(cursor->start));
        cursor = list_next(&heap->pages, cursor, page_node);
    }
}

static void gc_update_references(rb_objspace_t * objspace, rb_heap_t *heap);
static void invalidate_moved_page(rb_objspace_t *objspace, struct heap_page *page);

static void read_barrier_handler(intptr_t address)
{
    VALUE obj;
    rb_objspace_t * objspace = &rb_objspace;

    address -= address % sizeof(RVALUE);

    obj = (VALUE)address;

    RB_VM_LOCK_ENTER();
    {
        unlock_page_body(objspace, GET_PAGE_BODY(obj));

        objspace->profile.read_barrier_faults++;

        invalidate_moved_page(objspace, GET_HEAP_PAGE(obj));
    }
    RB_VM_LOCK_LEAVE();
}

#if defined(_WIN32)
LPTOP_LEVEL_EXCEPTION_FILTER old_handler;
typedef void (*signal_handler)(int);
static signal_handler old_sigsegv_handler;

static LONG WINAPI read_barrier_signal(EXCEPTION_POINTERS * info)
{
    /* EXCEPTION_ACCESS_VIOLATION is what's raised by access to protected pages */
    if (info->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION) {
        /* > The second array element specifies the virtual address of the inaccessible data.
         * https://docs.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-exception_record
         *
         * Use this address to invalidate the page */
        read_barrier_handler((intptr_t)info->ExceptionRecord->ExceptionInformation[1]);
        return EXCEPTION_CONTINUE_EXECUTION;
    } else {
        return EXCEPTION_CONTINUE_SEARCH;
    }
}

static void uninstall_handlers(void)
{
    signal(SIGSEGV, old_sigsegv_handler);
    SetUnhandledExceptionFilter(old_handler);
}

static void install_handlers(void)
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

static void
read_barrier_signal(int sig, siginfo_t * info, void * data)
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

    // run handler
    read_barrier_handler((intptr_t)info->si_addr);

    // reset SEGV/BUS handlers
    sigaction(SIGBUS, &prev_sigbus, NULL);
    sigaction(SIGSEGV, &prev_sigsegv, NULL);
    sigprocmask(SIG_SETMASK, &prev_set, NULL);
}

static void uninstall_handlers(void)
{
    sigaction(SIGBUS, &old_sigbus_handler, NULL);
    sigaction(SIGSEGV, &old_sigsegv_handler, NULL);
}

static void install_handlers(void)
{
    struct sigaction action;
    memset(&action, 0, sizeof(struct sigaction));
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = read_barrier_signal;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;

    sigaction(SIGBUS, &action, &old_sigbus_handler);
    sigaction(SIGSEGV, &action, &old_sigsegv_handler);
}
#endif

static void
revert_stack_objects(VALUE stack_obj, void *ctx)
{
    rb_objspace_t * objspace = (rb_objspace_t*)ctx;

    if (BUILTIN_TYPE(stack_obj) == T_MOVED) {
        /* For now we'll revert the whole page if the object made it to the
         * stack.  I think we can change this to move just the one object
         * back though */
        invalidate_moved_page(objspace, GET_HEAP_PAGE(stack_obj));
    }
}

static void
check_stack_for_moved(rb_objspace_t *objspace)
{
    rb_execution_context_t *ec = GET_EC();
    rb_vm_t *vm = rb_ec_vm_ptr(ec);
    rb_vm_each_stack_value(vm, revert_stack_objects, (void*)objspace);
}

static void
gc_compact_finish(rb_objspace_t *objspace, rb_heap_t *heap)
{
    GC_ASSERT(heap->sweeping_page == heap->compact_cursor);

    /* If this is an explicit compaction (GC.compact), no read barrier was set
     * so we don't need to unprotect pages or uninstall the SEGV handler */
    if (!(objspace->flags.during_compacting >> 1)) {
        gc_unprotect_pages(objspace, heap);
        uninstall_handlers();
    }

    /* The mutator is allowed to run during incremental sweeping. T_MOVED
     * objects can get pushed on the stack and when the compaction process
     * finishes up, it may remove the read barrier before anything has a
     * chance to read from the T_MOVED address. To fix this, we scan the stack
     * then revert any moved objects that made it to the stack. */
    check_stack_for_moved(objspace);

    gc_update_references(objspace, heap);
    heap->compact_cursor = NULL;
    heap->compact_cursor_index = 0;
    objspace->profile.compact_count++;
    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->moved_objects = objspace->rcompactor.total_moved - record->moved_objects;
    }
    rb_clear_constant_cache();
    objspace->flags.during_compacting = FALSE;
}

static int
gc_fill_swept_page(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *sweep_page, int *freed_slots, int *empty_slots)
{
    /* Find any pinned but not marked objects and try to fill those slots */
    int i;
    int moved_slots = 0;
    int finished_compacting = 0;
    bits_t *mark_bits, *pin_bits;
    bits_t bitset;
    RVALUE *p, *offset;

    mark_bits = sweep_page->mark_bits;
    pin_bits = sweep_page->pinned_bits;

    p = sweep_page->start;
    offset = p - NUM_IN_PAGE(p);

    struct heap_page * cursor = heap->compact_cursor;

    unlock_page_body(objspace, GET_PAGE_BODY(cursor->start));

    for (i=0; i < HEAP_PAGE_BITMAP_LIMIT; i++) {
        /* *Want to move* objects are pinned but not marked. */
        bitset = pin_bits[i] & ~mark_bits[i];

        if (bitset) {
            p = offset + i * BITS_BITLENGTH;
            do {
                if (bitset & 1) {
                    VALUE dest = (VALUE)p;

                    GC_ASSERT(MARKED_IN_BITMAP(GET_HEAP_PINNED_BITS(dest), dest));
                    GC_ASSERT(!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(dest), dest));

                    CLEAR_IN_BITMAP(GET_HEAP_PINNED_BITS(dest), dest);

                    if (finished_compacting) {
                        if (BUILTIN_TYPE(dest) == T_NONE) {
                            (*empty_slots)++;
                        } else {
                            (*freed_slots)++;
                        }
                        (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)dest, sizeof(RVALUE));
                        heap_page_add_freeobj(objspace, sweep_page, dest);
                    } else {
                        /* Zombie slots don't get marked, but we can't reuse
                         * their memory until they have their finalizers run.*/
                        if (BUILTIN_TYPE(dest) != T_ZOMBIE) {
                            if(!try_move(objspace, heap, sweep_page, dest)) {
                                finished_compacting = 1;
                                (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
                                gc_report(5, objspace, "Quit compacting, couldn't find an object to move\n");
                                if (BUILTIN_TYPE(dest) == T_NONE) {
                                    (*empty_slots)++;
                                } else {
                                    (*freed_slots)++;
                                }
                                heap_page_add_freeobj(objspace, sweep_page, dest);
                                gc_report(3, objspace, "page_sweep: %s is added to freelist\n", obj_info(dest));
                            } else {
                                moved_slots++;
                            }
                        }
                    }
                }
                p++;
                bitset >>= 1;
            } while (bitset);
        }
    }

    lock_page_body(objspace, GET_PAGE_BODY(heap->compact_cursor->start));

    return finished_compacting;
}

static inline int
gc_page_sweep(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *sweep_page)
{
    int i;
    int empty_slots = 0, freed_slots = 0, final_slots = 0;
    int was_compacting = 0;
    RVALUE *p, *offset;
    bits_t *bits, bitset;

    gc_report(2, objspace, "page_sweep: start.\n");

    if (heap->compact_cursor) {
        if (sweep_page == heap->compact_cursor) {
            /* The compaction cursor and sweep page met, so we need to quit compacting */
            gc_report(5, objspace, "Quit compacting, mark and compact cursor met\n");
            gc_compact_finish(objspace, heap);
        } else {
            /* We anticipate filling the page, so NULL out the freelist. */
            asan_unpoison_memory_region(&sweep_page->freelist, sizeof(RVALUE*), false);
            sweep_page->freelist = 0;
            asan_poison_memory_region(&sweep_page->freelist, sizeof(RVALUE*));
            was_compacting = 1;
        }
    }

    sweep_page->flags.before_sweep = FALSE;

    p = sweep_page->start;
    offset = p - NUM_IN_PAGE(p);
    bits = sweep_page->mark_bits;

    /* create guard : fill 1 out-of-range */
    bits[BITMAP_INDEX(p)] |= BITMAP_BIT(p)-1;

    int out_of_range_bits = (NUM_IN_PAGE(p) + sweep_page->total_slots) % BITS_BITLENGTH;
    if (out_of_range_bits != 0) { // sizeof(RVALUE) == 64
        bits[BITMAP_INDEX(p) + sweep_page->total_slots / BITS_BITLENGTH] |= ~(((bits_t)1 << out_of_range_bits) - 1);
    }

    for (i=0; i < HEAP_PAGE_BITMAP_LIMIT; i++) {
	bitset = ~bits[i];
	if (bitset) {
	    p = offset  + i * BITS_BITLENGTH;
	    do {
                VALUE vp = (VALUE)p;
                asan_unpoison_object(vp, false);
		if (bitset & 1) {
                    switch (BUILTIN_TYPE(vp)) {
		      default: /* majority case */
                        gc_report(2, objspace, "page_sweep: free %p\n", (void *)p);
#if RGENGC_CHECK_MODE
                        if (!is_full_marking(objspace)) {
                            if (RVALUE_OLD_P(vp)) rb_bug("page_sweep: %p - old while minor GC.", (void *)p);
                            if (rgengc_remembered_sweep(objspace, vp)) rb_bug("page_sweep: %p - remembered.", (void *)p);
                        }
#endif
                        if (obj_free(objspace, vp)) {
                            final_slots++;
                        }
                        else {
                            if (heap->compact_cursor) {
                                /* We *want* to fill this slot */
                                MARK_IN_BITMAP(GET_HEAP_PINNED_BITS(vp), vp);
                            } else {
                                (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
                                heap_page_add_freeobj(objspace, sweep_page, vp);
                                gc_report(3, objspace, "page_sweep: %s is added to freelist\n", obj_info(vp));
                                freed_slots++;
                            }

                        }
                        break;

			/* minor cases */
		      case T_MOVED:
                        if (objspace->flags.during_compacting) {
                            /* The sweep cursor shouldn't have made it to any
                             * T_MOVED slots while the compact flag is enabled.
                             * The sweep cursor and compact cursor move in
                             * opposite directions, and when they meet references will
                             * get updated and "during_compacting" should get disabled */
                            rb_bug("T_MOVED shouldn't be seen until compaction is finished\n");
                        }
                        gc_report(3, objspace, "page_sweep: %s is added to freelist\n", obj_info(vp));
                        if (FL_TEST(vp, FL_FROM_FREELIST)) {
                            empty_slots++;
                        } else {
                            freed_slots++;
                        }
                        heap_page_add_freeobj(objspace, sweep_page, vp);
                        break;
		      case T_ZOMBIE:
			/* already counted */
			break;
		      case T_NONE:
                        if (heap->compact_cursor) {
                            /* We *want* to fill this slot */
                            MARK_IN_BITMAP(GET_HEAP_PINNED_BITS(vp), vp);
                        } else {
                            /* When we started sweeping this page, we were in
                             * compacting mode and nulled the free list for
                             * the page. But compaction finished, so we need to
                             * put any T_NONE slots back on the freelist. */
                            if (was_compacting) {
                                heap_page_add_freeobj(objspace, sweep_page, vp);
                            }
                            empty_slots++; /* already freed */
                        }
			break;
		    }
		}
		p++;
		bitset >>= 1;
	    } while (bitset);
	}
    }

    if (heap->compact_cursor) {
        if (gc_fill_swept_page(objspace, heap, sweep_page, &freed_slots, &empty_slots)) {
            gc_compact_finish(objspace, heap);
        }
    }

    if (!heap->compact_cursor) {
        gc_setup_mark_bits(sweep_page);
    }

#if GC_PROFILE_MORE_DETAIL
    if (gc_prof_enabled(objspace)) {
	gc_profile_record *record = gc_prof_record(objspace);
	record->removing_objects += final_slots + freed_slots;
	record->empty_objects += empty_slots;
    }
#endif
    if (0) fprintf(stderr, "gc_page_sweep(%"PRIdSIZE"): total_slots: %d, freed_slots: %d, empty_slots: %d, final_slots: %d\n",
		   rb_gc_count(),
		   sweep_page->total_slots,
		   freed_slots, empty_slots, final_slots);

    sweep_page->free_slots = freed_slots + empty_slots;
    objspace->profile.total_freed_objects += freed_slots;

    if (heap_pages_deferred_final && !finalizing) {
        rb_thread_t *th = GET_THREAD();
        if (th) {
	    gc_finalize_deferred_register(objspace);
        }
    }

    gc_report(2, objspace, "page_sweep: end.\n");

    return freed_slots + empty_slots;
}

/* allocate additional minimum page to work */
static void
gc_heap_prepare_minimum_pages(rb_objspace_t *objspace, rb_heap_t *heap)
{
    if (!heap->free_pages && heap_increment(objspace, heap) == FALSE) {
	/* there is no free after page_sweep() */
	heap_set_increment(objspace, 1);
	if (!heap_increment(objspace, heap)) { /* can't allocate additional free objects */
	    rb_memerror();
	}
    }
}

static const char *
gc_mode_name(enum gc_mode mode)
{
    switch (mode) {
      case gc_mode_none: return "none";
      case gc_mode_marking: return "marking";
      case gc_mode_sweeping: return "sweeping";
      default: rb_bug("gc_mode_name: unknown mode: %d", (int)mode);
    }
}

static void
gc_mode_transition(rb_objspace_t *objspace, enum gc_mode mode)
{
#if RGENGC_CHECK_MODE
    enum gc_mode prev_mode = gc_mode(objspace);
    switch (prev_mode) {
      case gc_mode_none:     GC_ASSERT(mode == gc_mode_marking); break;
      case gc_mode_marking:  GC_ASSERT(mode == gc_mode_sweeping); break;
      case gc_mode_sweeping: GC_ASSERT(mode == gc_mode_none); break;
    }
#endif
    if (0) fprintf(stderr, "gc_mode_transition: %s->%s\n", gc_mode_name(gc_mode(objspace)), gc_mode_name(mode));
    gc_mode_set(objspace, mode);
}

static void
gc_sweep_start_heap(rb_objspace_t *objspace, rb_heap_t *heap)
{
    heap->sweeping_page = list_top(&heap->pages, struct heap_page, page_node);
    heap->free_pages = NULL;
#if GC_ENABLE_INCREMENTAL_MARK
    heap->pooled_pages = NULL;
    objspace->rincgc.pooled_slots = 0;
#endif
    if (heap->using_page) {
        struct heap_page *page = heap->using_page;
        asan_unpoison_memory_region(&page->freelist, sizeof(RVALUE*), false);

        RVALUE **p = &page->freelist;
	while (*p) {
	    p = &(*p)->as.free.next;
	}
	*p = heap->freelist;
        asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));
	heap->using_page = NULL;
    }
    heap->freelist = NULL;
}

#if defined(__GNUC__) && __GNUC__ == 4 && __GNUC_MINOR__ == 4
__attribute__((noinline))
#endif
static void
gc_sweep_start(rb_objspace_t *objspace)
{
    gc_mode_transition(objspace, gc_mode_sweeping);
    gc_sweep_start_heap(objspace, heap_eden);
}

static void
gc_sweep_finish(rb_objspace_t *objspace)
{
    gc_report(1, objspace, "gc_sweep_finish\n");

    gc_prof_set_heap_info(objspace);
    heap_pages_free_unused_pages(objspace);

    /* if heap_pages has unused pages, then assign them to increment */
    if (heap_allocatable_pages < heap_tomb->total_pages) {
	heap_allocatable_pages_set(objspace, heap_tomb->total_pages);
    }

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_END_SWEEP, 0);
    gc_mode_transition(objspace, gc_mode_none);

#if RGENGC_CHECK_MODE >= 2
    gc_verify_internal_consistency(objspace);
#endif
}

static int
gc_sweep_step(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *sweep_page = heap->sweeping_page;
    int unlink_limit = 3;
#if GC_ENABLE_INCREMENTAL_MARK
    int need_pool = will_be_incremental_marking(objspace) ? TRUE : FALSE;

    gc_report(2, objspace, "gc_sweep_step (need_pool: %d)\n", need_pool);
#else
    gc_report(2, objspace, "gc_sweep_step\n");
#endif

    if (sweep_page == NULL) return FALSE;

#if GC_ENABLE_LAZY_SWEEP
    gc_prof_sweep_timer_start(objspace);
#endif

    do {
	int free_slots = gc_page_sweep(objspace, heap, sweep_page);
	heap->sweeping_page = list_next(&heap->pages, sweep_page, page_node);

	if (sweep_page->final_slots + free_slots == sweep_page->total_slots &&
	    heap_pages_freeable_pages > 0 &&
	    unlink_limit > 0) {
	    heap_pages_freeable_pages--;
	    unlink_limit--;
	    /* there are no living objects -> move this page to tomb heap */
	    heap_unlink_page(objspace, heap, sweep_page);
	    heap_add_page(objspace, heap_tomb, sweep_page);
	}
	else if (free_slots > 0) {
#if GC_ENABLE_INCREMENTAL_MARK
	    if (need_pool) {
		if (heap_add_poolpage(objspace, heap, sweep_page)) {
		    need_pool = FALSE;
		}
	    }
	    else {
		heap_add_freepage(heap, sweep_page);
		break;
	    }
#else
	    heap_add_freepage(heap, sweep_page);
	    break;
#endif
	}
	else {
	    sweep_page->free_next = NULL;
	}
    } while ((sweep_page = heap->sweeping_page));

    if (!heap->sweeping_page) {
	gc_sweep_finish(objspace);
    }

#if GC_ENABLE_LAZY_SWEEP
    gc_prof_sweep_timer_stop(objspace);
#endif

    return heap->free_pages != NULL;
}

static void
gc_sweep_rest(rb_objspace_t *objspace)
{
    rb_heap_t *heap = heap_eden; /* lazy sweep only for eden */

    while (has_sweeping_pages(heap)) {
	gc_sweep_step(objspace, heap);
    }
}

static void
gc_sweep_continue(rb_objspace_t *objspace, rb_heap_t *heap)
{
    GC_ASSERT(dont_gc_val() == FALSE);
    if (!GC_ENABLE_LAZY_SWEEP) return;

    unsigned int lock_lev;
    gc_enter(objspace, "sweep_continue", &lock_lev);
    if (objspace->rgengc.need_major_gc == GPR_FLAG_NONE && heap_increment(objspace, heap)) {
	gc_report(3, objspace, "gc_sweep_continue: success heap_increment().\n");
    }
    gc_sweep_step(objspace, heap);
    gc_exit(objspace, "sweep_continue", &lock_lev);
}

static void
invalidate_moved_page(rb_objspace_t *objspace, struct heap_page *page)
{
    int i;
    int empty_slots = 0, freed_slots = 0;
    bits_t *mark_bits, *pin_bits;
    bits_t bitset;
    RVALUE *p, *offset;

    mark_bits = page->mark_bits;
    pin_bits = page->pinned_bits;

    p = page->start;
    offset = p - NUM_IN_PAGE(p);

    for (i=0; i < HEAP_PAGE_BITMAP_LIMIT; i++) {
        /* Moved objects are pinned but never marked. We reuse the pin bits
         * to indicate there is a moved object in this slot. */
        bitset = pin_bits[i] & ~mark_bits[i];

        if (bitset) {
            p = offset + i * BITS_BITLENGTH;
            do {
                if (bitset & 1) {
                    VALUE forwarding_object = (VALUE)p;
                    VALUE object;

                    if (BUILTIN_TYPE(forwarding_object) == T_MOVED) {
                        GC_ASSERT(MARKED_IN_BITMAP(GET_HEAP_PINNED_BITS(forwarding_object), forwarding_object));
                        GC_ASSERT(!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(forwarding_object), forwarding_object));

                        CLEAR_IN_BITMAP(GET_HEAP_PINNED_BITS(forwarding_object), forwarding_object);

                        object = rb_gc_location(forwarding_object);

                        if (FL_TEST(forwarding_object, FL_FROM_FREELIST)) {
                            empty_slots++; /* already freed */
                        } else {
                            freed_slots++;
                        }

                        gc_move(objspace, object, forwarding_object);
                        /* forwarding_object is now our actual object, and "object"
                         * is the free slot for the original page */
                        heap_page_add_freeobj(objspace, GET_HEAP_PAGE(object), object);

                        GC_ASSERT(MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(forwarding_object), forwarding_object));
                        GC_ASSERT(BUILTIN_TYPE(forwarding_object) != T_MOVED);
                        GC_ASSERT(BUILTIN_TYPE(forwarding_object) != T_NONE);
                    }
                }
                p++;
                bitset >>= 1;
            } while (bitset);
        }
    }

    page->free_slots += (empty_slots + freed_slots);
    objspace->profile.total_freed_objects += freed_slots;
}

static void
gc_compact_start(rb_objspace_t *objspace, rb_heap_t *heap)
{
    heap->compact_cursor = list_tail(&heap->pages, struct heap_page, page_node);
    heap->compact_cursor_index = 0;

    if (gc_prof_enabled(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->moved_objects = objspace->rcompactor.total_moved;
    }

    memset(objspace->rcompactor.considered_count_table, 0, T_MASK * sizeof(size_t));
    memset(objspace->rcompactor.moved_count_table, 0, T_MASK * sizeof(size_t));

    /* If this is an explicit compaction (GC.compact), we don't need a read
     * barrier, so just return early. */
    if (objspace->flags.during_compacting >> 1) {
        return;
    }

    /* Set up read barrier for pages containing MOVED objects */
    install_handlers();
}

static void
gc_sweep(rb_objspace_t *objspace)
{
    const unsigned int immediate_sweep = objspace->flags.immediate_sweep;

    gc_report(1, objspace, "gc_sweep: immediate: %d\n", immediate_sweep);

    if (immediate_sweep) {
#if !GC_ENABLE_LAZY_SWEEP
	gc_prof_sweep_timer_start(objspace);
#endif
	gc_sweep_start(objspace);
        if (objspace->flags.during_compacting) {
            struct heap_page *page = NULL;

            list_for_each(&heap_eden->pages, page, page_node) {
                page->flags.before_sweep = TRUE;
            }

            gc_compact_start(objspace, heap_eden);
        }

	gc_sweep_rest(objspace);
#if !GC_ENABLE_LAZY_SWEEP
	gc_prof_sweep_timer_stop(objspace);
#endif
    }
    else {
	struct heap_page *page = NULL;
	gc_sweep_start(objspace);

        if (ruby_enable_autocompact && is_full_marking(objspace)) {
            gc_compact_start(objspace, heap_eden);
        }

        list_for_each(&heap_eden->pages, page, page_node) {
            page->flags.before_sweep = TRUE;
        }
	gc_sweep_step(objspace, heap_eden);
    }

    gc_heap_prepare_minimum_pages(objspace, heap_eden);
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
free_stack_chunks(mark_stack_t *stack)
{
    stack_chunk_t *chunk = stack->chunk;
    stack_chunk_t *next = NULL;

    while (chunk != NULL) {
        next = chunk->next;
        free(chunk);
        chunk = next;
    }
}

static void
push_mark_stack(mark_stack_t *stack, VALUE data)
{
    VALUE obj = data;
    switch (BUILTIN_TYPE(obj)) {
      case T_NIL:
      case T_FIXNUM:
      case T_MOVED:
	rb_bug("push_mark_stack() called for broken object");
	break;

      case T_NODE:
	UNEXPECTED_NODE(push_mark_stack);
        break;

      default:
        break;
    }

    if (stack->index == stack->limit) {
        push_mark_stack_chunk(stack);
    }
    stack->chunk->data[stack->index++] = data;
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

#if GC_ENABLE_INCREMENTAL_MARK
static int
invalidate_mark_stack_chunk(stack_chunk_t *chunk, int limit, VALUE obj)
{
    int i;
    for (i=0; i<limit; i++) {
	if (chunk->data[i] == obj) {
	    chunk->data[i] = Qundef;
	    return TRUE;
	}
    }
    return FALSE;
}

static void
invalidate_mark_stack(mark_stack_t *stack, VALUE obj)
{
    stack_chunk_t *chunk = stack->chunk;
    int limit = stack->index;

    while (chunk) {
	if (invalidate_mark_stack_chunk(chunk, limit, obj)) return;
	chunk = chunk->next;
	limit = stack->limit;
    }
    rb_bug("invalid_mark_stack: unreachable");
}
#endif

static void
init_mark_stack(mark_stack_t *stack)
{
    int i;

    MEMZERO(stack, mark_stack_t, 1);
    stack->index = stack->limit = STACK_CHUNK_SIZE;
    stack->cache_size = 0;

    for (i=0; i < 4; i++) {
        add_stack_chunk_cache(stack, stack_chunk_alloc());
    }
    stack->unused_cache_size = stack->cache_size;
}

/* Marking */

#define SET_STACK_END SET_MACHINE_STACK_END(&ec->machine.stack_end)

#define STACK_START (ec->machine.stack_start)
#define STACK_END (ec->machine.stack_end)
#define STACK_LEVEL_MAX (ec->machine.stack_maxsize/sizeof(VALUE))

#ifdef __EMSCRIPTEN__
#undef STACK_GROW_DIRECTION
#define STACK_GROW_DIRECTION 1
#endif

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
#if PREVENT_STACK_OVERFLOW
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

MJIT_FUNC_EXPORTED int
rb_ec_stack_check(rb_execution_context_t *ec)
{
    return stack_check(ec, STACKFRAME_FOR_CALL_CFUNC);
}

int
ruby_stack_check(void)
{
    return stack_check(GET_EC(), STACKFRAME_FOR_CALL_CFUNC);
}

ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS(static void mark_locations_array(rb_objspace_t *objspace, register const VALUE *x, register long n));
static void
mark_locations_array(rb_objspace_t *objspace, register const VALUE *x, register long n)
{
    VALUE v;
    while (n--) {
        v = *x;
        gc_mark_maybe(objspace, v);
	x++;
    }
}

static void
gc_mark_locations(rb_objspace_t *objspace, const VALUE *start, const VALUE *end)
{
    long n;

    if (end <= start) return;
    n = end - start;
    mark_locations_array(objspace, start, n);
}

void
rb_gc_mark_locations(const VALUE *start, const VALUE *end)
{
    gc_mark_locations(&rb_objspace, start, end);
}

static void
gc_mark_values(rb_objspace_t *objspace, long n, const VALUE *values)
{
    long i;

    for (i=0; i<n; i++) {
        gc_mark(objspace, values[i]);
    }
}

void
rb_gc_mark_values(long n, const VALUE *values)
{
    long i;
    rb_objspace_t *objspace = &rb_objspace;

    for (i=0; i<n; i++) {
        gc_mark_and_pin(objspace, values[i]);
    }
}

static void
gc_mark_stack_values(rb_objspace_t *objspace, long n, const VALUE *values)
{
    long i;

    for (i=0; i<n; i++) {
        if (is_markable_object(objspace, values[i])) {
            gc_mark_and_pin(objspace, values[i]);
        }
    }
}

void
rb_gc_mark_vm_stack_values(long n, const VALUE *values)
{
    rb_objspace_t *objspace = &rb_objspace;
    gc_mark_stack_values(objspace, n, values);
}

static int
mark_value(st_data_t key, st_data_t value, st_data_t data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;
    gc_mark(objspace, (VALUE)value);
    return ST_CONTINUE;
}

static int
mark_value_pin(st_data_t key, st_data_t value, st_data_t data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;
    gc_mark_and_pin(objspace, (VALUE)value);
    return ST_CONTINUE;
}

static void
mark_tbl_no_pin(rb_objspace_t *objspace, st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;
    st_foreach(tbl, mark_value, (st_data_t)objspace);
}

static void
mark_tbl(rb_objspace_t *objspace, st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;
    st_foreach(tbl, mark_value_pin, (st_data_t)objspace);
}

static int
mark_key(st_data_t key, st_data_t value, st_data_t data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;
    gc_mark_and_pin(objspace, (VALUE)key);
    return ST_CONTINUE;
}

static void
mark_set(rb_objspace_t *objspace, st_table *tbl)
{
    if (!tbl) return;
    st_foreach(tbl, mark_key, (st_data_t)objspace);
}

static int
pin_value(st_data_t key, st_data_t value, st_data_t data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;
    gc_mark_and_pin(objspace, (VALUE)value);
    return ST_CONTINUE;
}

static void
mark_finalizer_tbl(rb_objspace_t *objspace, st_table *tbl)
{
    if (!tbl) return;
    st_foreach(tbl, pin_value, (st_data_t)objspace);
}

void
rb_mark_set(st_table *tbl)
{
    mark_set(&rb_objspace, tbl);
}

static int
mark_keyvalue(st_data_t key, st_data_t value, st_data_t data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;

    gc_mark(objspace, (VALUE)key);
    gc_mark(objspace, (VALUE)value);
    return ST_CONTINUE;
}

static int
pin_key_pin_value(st_data_t key, st_data_t value, st_data_t data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;

    gc_mark_and_pin(objspace, (VALUE)key);
    gc_mark_and_pin(objspace, (VALUE)value);
    return ST_CONTINUE;
}

static int
pin_key_mark_value(st_data_t key, st_data_t value, st_data_t data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;

    gc_mark_and_pin(objspace, (VALUE)key);
    gc_mark(objspace, (VALUE)value);
    return ST_CONTINUE;
}

static void
mark_hash(rb_objspace_t *objspace, VALUE hash)
{
    if (rb_hash_compare_by_id_p(hash)) {
        rb_hash_stlike_foreach(hash, pin_key_mark_value, (st_data_t)objspace);
    }
    else {
        rb_hash_stlike_foreach(hash, mark_keyvalue, (st_data_t)objspace);
    }

    if (RHASH_AR_TABLE_P(hash)) {
        if (LIKELY(during_gc) && RHASH_TRANSIENT_P(hash)) {
            rb_transient_heap_mark(hash, RHASH_AR_TABLE(hash));
        }
    }
    else {
        VM_ASSERT(!RHASH_TRANSIENT_P(hash));
    }
    gc_mark(objspace, RHASH(hash)->ifnone);
}

static void
mark_st(rb_objspace_t *objspace, st_table *tbl)
{
    if (!tbl) return;
    st_foreach(tbl, pin_key_pin_value, (st_data_t)objspace);
}

void
rb_mark_hash(st_table *tbl)
{
    mark_st(&rb_objspace, tbl);
}

static void
mark_method_entry(rb_objspace_t *objspace, const rb_method_entry_t *me)
{
    const rb_method_definition_t *def = me->def;

    gc_mark(objspace, me->owner);
    gc_mark(objspace, me->defined_class);

    if (def) {
	switch (def->type) {
	  case VM_METHOD_TYPE_ISEQ:
	    if (def->body.iseq.iseqptr) gc_mark(objspace, (VALUE)def->body.iseq.iseqptr);
	    gc_mark(objspace, (VALUE)def->body.iseq.cref);
	    break;
	  case VM_METHOD_TYPE_ATTRSET:
	  case VM_METHOD_TYPE_IVAR:
	    gc_mark(objspace, def->body.attr.location);
	    break;
	  case VM_METHOD_TYPE_BMETHOD:
            gc_mark(objspace, def->body.bmethod.proc);
            if (def->body.bmethod.hooks) rb_hook_list_mark(def->body.bmethod.hooks);
	    break;
	  case VM_METHOD_TYPE_ALIAS:
	    gc_mark(objspace, (VALUE)def->body.alias.original_me);
	    return;
	  case VM_METHOD_TYPE_REFINED:
	    gc_mark(objspace, (VALUE)def->body.refined.orig_me);
	    gc_mark(objspace, (VALUE)def->body.refined.owner);
	    break;
	  case VM_METHOD_TYPE_CFUNC:
	  case VM_METHOD_TYPE_ZSUPER:
	  case VM_METHOD_TYPE_MISSING:
	  case VM_METHOD_TYPE_OPTIMIZED:
	  case VM_METHOD_TYPE_UNDEF:
	  case VM_METHOD_TYPE_NOTIMPLEMENTED:
	    break;
	}
    }
}

static enum rb_id_table_iterator_result
mark_method_entry_i(VALUE me, void *data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;

    gc_mark(objspace, me);
    return ID_TABLE_CONTINUE;
}

static void
mark_m_tbl(rb_objspace_t *objspace, struct rb_id_table *tbl)
{
    if (tbl) {
	rb_id_table_foreach_values(tbl, mark_method_entry_i, objspace);
    }
}

static enum rb_id_table_iterator_result
mark_const_entry_i(VALUE value, void *data)
{
    const rb_const_entry_t *ce = (const rb_const_entry_t *)value;
    rb_objspace_t *objspace = data;

    gc_mark(objspace, ce->value);
    gc_mark(objspace, ce->file);
    return ID_TABLE_CONTINUE;
}

static void
mark_const_tbl(rb_objspace_t *objspace, struct rb_id_table *tbl)
{
    if (!tbl) return;
    rb_id_table_foreach_values(tbl, mark_const_entry_i, objspace);
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

static void mark_stack_locations(rb_objspace_t *objspace, const rb_execution_context_t *ec,
				 const VALUE *stack_start, const VALUE *stack_end);

static void
mark_current_machine_context(rb_objspace_t *objspace, rb_execution_context_t *ec)
{
    union {
	rb_jmp_buf j;
	VALUE v[sizeof(rb_jmp_buf) / sizeof(VALUE)];
    } save_regs_gc_mark;
    VALUE *stack_start, *stack_end;

    FLUSH_REGISTER_WINDOWS;
    memset(&save_regs_gc_mark, 0, sizeof(save_regs_gc_mark));
    /* This assumes that all registers are saved into the jmp_buf (and stack) */
    rb_setjmp(save_regs_gc_mark.j);

    /* SET_STACK_END must be called in this function because
     * the stack frame of this function may contain
     * callee save registers and they should be marked. */
    SET_STACK_END;
    GET_STACK_BOUNDS(stack_start, stack_end, 1);

    mark_locations_array(objspace, save_regs_gc_mark.v, numberof(save_regs_gc_mark.v));

    mark_stack_locations(objspace, ec, stack_start, stack_end);
}

void
rb_gc_mark_machine_stack(const rb_execution_context_t *ec)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE *stack_start, *stack_end;

    GET_STACK_BOUNDS(stack_start, stack_end, 0);
    mark_stack_locations(objspace, ec, stack_start, stack_end);
}

static void
mark_stack_locations(rb_objspace_t *objspace, const rb_execution_context_t *ec,
		     const VALUE *stack_start, const VALUE *stack_end)
{

    gc_mark_locations(objspace, stack_start, stack_end);

#if defined(__mc68000__)
    gc_mark_locations(objspace,
		      (VALUE*)((char*)stack_start + 2),
		      (VALUE*)((char*)stack_end - 2));
#endif
}

void
rb_mark_tbl(st_table *tbl)
{
    mark_tbl(&rb_objspace, tbl);
}

void
rb_mark_tbl_no_pin(st_table *tbl)
{
    mark_tbl_no_pin(&rb_objspace, tbl);
}

static void
gc_mark_maybe(rb_objspace_t *objspace, VALUE obj)
{
    (void)VALGRIND_MAKE_MEM_DEFINED(&obj, sizeof(obj));

    if (is_pointer_to_heap(objspace, (void *)obj)) {
        void *ptr = __asan_region_is_poisoned((void *)obj, SIZEOF_VALUE);
        asan_unpoison_object(obj, false);

        /* Garbage can live on the stack, so do not mark or pin */
        switch (BUILTIN_TYPE(obj)) {
          case T_ZOMBIE:
          case T_NONE:
            break;
          default:
            gc_mark_and_pin(objspace, obj);
            break;
        }

        if (ptr) {
            GC_ASSERT(BUILTIN_TYPE(obj) == T_NONE);
            asan_poison_object(obj);
        }
    }
}

void
rb_gc_mark_maybe(VALUE obj)
{
    gc_mark_maybe(&rb_objspace, obj);
}

static inline int
gc_mark_set(rb_objspace_t *objspace, VALUE obj)
{
    if (RVALUE_MARKED(obj)) return 0;
    MARK_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj);
    return 1;
}

static int
gc_remember_unprotected(rb_objspace_t *objspace, VALUE obj)
{
    struct heap_page *page = GET_HEAP_PAGE(obj);
    bits_t *uncollectible_bits = &page->uncollectible_bits[0];

    if (!MARKED_IN_BITMAP(uncollectible_bits, obj)) {
	page->flags.has_uncollectible_shady_objects = TRUE;
	MARK_IN_BITMAP(uncollectible_bits, obj);
	objspace->rgengc.uncollectible_wb_unprotected_objects++;

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

static void
rgengc_check_relation(rb_objspace_t *objspace, VALUE obj)
{
    const VALUE old_parent = objspace->rgengc.parent_object;

    if (old_parent) { /* parent object is old */
	if (RVALUE_WB_UNPROTECTED(obj)) {
	    if (gc_remember_unprotected(objspace, obj)) {
		gc_report(2, objspace, "relation: (O->S) %s -> %s\n", obj_info(old_parent), obj_info(obj));
	    }
	}
	else {
	    if (!RVALUE_OLD_P(obj)) {
		if (RVALUE_MARKED(obj)) {
		    /* An object pointed from an OLD object should be OLD. */
		    gc_report(2, objspace, "relation: (O->unmarked Y) %s -> %s\n", obj_info(old_parent), obj_info(obj));
		    RVALUE_AGE_SET_OLD(objspace, obj);
		    if (is_incremental_marking(objspace)) {
			if (!RVALUE_MARKING(obj)) {
			    gc_grey(objspace, obj);
			}
		    }
		    else {
			rgengc_remember(objspace, obj);
		    }
		}
		else {
		    gc_report(2, objspace, "relation: (O->Y) %s -> %s\n", obj_info(old_parent), obj_info(obj));
		    RVALUE_AGE_SET_CANDIDATE(objspace, obj);
		}
	    }
	}
    }

    GC_ASSERT(old_parent == objspace->rgengc.parent_object);
}

static void
gc_grey(rb_objspace_t *objspace, VALUE obj)
{
#if RGENGC_CHECK_MODE
    if (RVALUE_MARKED(obj) == FALSE) rb_bug("gc_grey: %s is not marked.", obj_info(obj));
    if (RVALUE_MARKING(obj) == TRUE) rb_bug("gc_grey: %s is marking/remembered.", obj_info(obj));
#endif

#if GC_ENABLE_INCREMENTAL_MARK
    if (is_incremental_marking(objspace)) {
	MARK_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj);
    }
#endif

    push_mark_stack(&objspace->mark_stack, obj);
}

static void
gc_aging(rb_objspace_t *objspace, VALUE obj)
{
    struct heap_page *page = GET_HEAP_PAGE(obj);

    GC_ASSERT(RVALUE_MARKING(obj) == FALSE);
    check_rvalue_consistency(obj);

    if (!RVALUE_PAGE_WB_UNPROTECTED(page, obj)) {
	if (!RVALUE_OLD_P(obj)) {
	    gc_report(3, objspace, "gc_aging: YOUNG: %s\n", obj_info(obj));
	    RVALUE_AGE_INC(objspace, obj);
	}
	else if (is_full_marking(objspace)) {
	    GC_ASSERT(RVALUE_PAGE_UNCOLLECTIBLE(page, obj) == FALSE);
	    RVALUE_PAGE_OLD_UNCOLLECTIBLE_SET(objspace, page, obj);
	}
    }
    check_rvalue_consistency(obj);

    objspace->marked_slots++;
}

NOINLINE(static void gc_mark_ptr(rb_objspace_t *objspace, VALUE obj));
static void reachable_objects_from_callback(VALUE obj);

static void
gc_mark_ptr(rb_objspace_t *objspace, VALUE obj)
{
    if (LIKELY(during_gc)) {
	rgengc_check_relation(objspace, obj);
	if (!gc_mark_set(objspace, obj)) return; /* already marked */
        if (RB_TYPE_P(obj, T_NONE)) {
            rp(obj);
            rb_bug("try to mark T_NONE object"); /* check here will help debugging */
        }
	gc_aging(objspace, obj);
	gc_grey(objspace, obj);
    }
    else {
        reachable_objects_from_callback(obj);
    }
}

static inline void
gc_pin(rb_objspace_t *objspace, VALUE obj)
{
    GC_ASSERT(is_markable_object(objspace, obj));
    if (UNLIKELY(objspace->flags.during_compacting)) {
        if (LIKELY(during_gc)) {
            MARK_IN_BITMAP(GET_HEAP_PINNED_BITS(obj), obj);
        }
    }
}

static inline void
gc_mark_and_pin(rb_objspace_t *objspace, VALUE obj)
{
    if (!is_markable_object(objspace, obj)) return;
    gc_pin(objspace, obj);
    gc_mark_ptr(objspace, obj);
}

static inline void
gc_mark(rb_objspace_t *objspace, VALUE obj)
{
    if (!is_markable_object(objspace, obj)) return;
    gc_mark_ptr(objspace, obj);
}

void
rb_gc_mark_movable(VALUE ptr)
{
    gc_mark(&rb_objspace, ptr);
}

void
rb_gc_mark(VALUE ptr)
{
    gc_mark_and_pin(&rb_objspace, ptr);
}

/* CAUTION: THIS FUNCTION ENABLE *ONLY BEFORE* SWEEPING.
 * This function is only for GC_END_MARK timing.
 */

int
rb_objspace_marked_object_p(VALUE obj)
{
    return RVALUE_MARKED(obj) ? TRUE : FALSE;
}

static inline void
gc_mark_set_parent(rb_objspace_t *objspace, VALUE obj)
{
    if (RVALUE_OLD_P(obj)) {
	objspace->rgengc.parent_object = obj;
    }
    else {
	objspace->rgengc.parent_object = Qfalse;
    }
}

static void
gc_mark_imemo(rb_objspace_t *objspace, VALUE obj)
{
    switch (imemo_type(obj)) {
      case imemo_env:
	{
	    const rb_env_t *env = (const rb_env_t *)obj;
	    GC_ASSERT(VM_ENV_ESCAPED_P(env->ep));
            gc_mark_values(objspace, (long)env->env_size, env->env);
	    VM_ENV_FLAGS_SET(env->ep, VM_ENV_FLAG_WB_REQUIRED);
            gc_mark(objspace, (VALUE)rb_vm_env_prev_env(env));
	    gc_mark(objspace, (VALUE)env->iseq);
	}
	return;
      case imemo_cref:
	gc_mark(objspace, RANY(obj)->as.imemo.cref.klass);
	gc_mark(objspace, (VALUE)RANY(obj)->as.imemo.cref.next);
	gc_mark(objspace, RANY(obj)->as.imemo.cref.refinements);
	return;
      case imemo_svar:
	gc_mark(objspace, RANY(obj)->as.imemo.svar.cref_or_me);
	gc_mark(objspace, RANY(obj)->as.imemo.svar.lastline);
	gc_mark(objspace, RANY(obj)->as.imemo.svar.backref);
	gc_mark(objspace, RANY(obj)->as.imemo.svar.others);
	return;
      case imemo_throw_data:
	gc_mark(objspace, RANY(obj)->as.imemo.throw_data.throw_obj);
	return;
      case imemo_ifunc:
	gc_mark_maybe(objspace, (VALUE)RANY(obj)->as.imemo.ifunc.data);
	return;
      case imemo_memo:
	gc_mark(objspace, RANY(obj)->as.imemo.memo.v1);
	gc_mark(objspace, RANY(obj)->as.imemo.memo.v2);
	gc_mark_maybe(objspace, RANY(obj)->as.imemo.memo.u3.value);
	return;
      case imemo_ment:
	mark_method_entry(objspace, &RANY(obj)->as.imemo.ment);
	return;
      case imemo_iseq:
	rb_iseq_mark((rb_iseq_t *)obj);
	return;
      case imemo_tmpbuf:
	{
	    const rb_imemo_tmpbuf_t *m = &RANY(obj)->as.imemo.alloc;
	    do {
		rb_gc_mark_locations(m->ptr, m->ptr + m->cnt);
	    } while ((m = m->next) != NULL);
	}
	return;
      case imemo_ast:
	rb_ast_mark(&RANY(obj)->as.imemo.ast);
	return;
      case imemo_parser_strterm:
	rb_strterm_mark(obj);
	return;
      case imemo_callinfo:
        return;
      case imemo_callcache:
        {
            const struct rb_callcache *cc = (const struct rb_callcache *)obj;
            // should not mark klass here
            gc_mark(objspace, (VALUE)vm_cc_cme(cc));
        }
        return;
#if VM_CHECK_MODE > 0
      default:
	VM_UNREACHABLE(gc_mark_imemo);
#endif
    }
}

static void
gc_mark_children(rb_objspace_t *objspace, VALUE obj)
{
    register RVALUE *any = RANY(obj);
    gc_mark_set_parent(objspace, obj);

    if (FL_TEST(obj, FL_EXIVAR)) {
	rb_mark_generic_ivar(obj);
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_FLOAT:
      case T_BIGNUM:
      case T_SYMBOL:
        /* Not immediates, but does not have references and singleton
         * class */
        return;

      case T_NIL:
      case T_FIXNUM:
	rb_bug("rb_gc_mark() called for broken object");
	break;

      case T_NODE:
	UNEXPECTED_NODE(rb_gc_mark);
	break;

      case T_IMEMO:
	gc_mark_imemo(objspace, obj);
	return;

      default:
        break;
    }

    gc_mark(objspace, any->as.basic.klass);

    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
      case T_MODULE:
        if (RCLASS_SUPER(obj)) {
            gc_mark(objspace, RCLASS_SUPER(obj));
        }
	if (!RCLASS_EXT(obj)) break;

        mark_m_tbl(objspace, RCLASS_M_TBL(obj));
        cc_table_mark(objspace, obj);
        mark_tbl_no_pin(objspace, RCLASS_IV_TBL(obj));
	mark_const_tbl(objspace, RCLASS_CONST_TBL(obj));
	break;

      case T_ICLASS:
        if (RICLASS_OWNS_M_TBL_P(obj)) {
	    mark_m_tbl(objspace, RCLASS_M_TBL(obj));
	}
        if (RCLASS_SUPER(obj)) {
            gc_mark(objspace, RCLASS_SUPER(obj));
        }
	if (!RCLASS_EXT(obj)) break;
	mark_m_tbl(objspace, RCLASS_CALLABLE_M_TBL(obj));
        cc_table_mark(objspace, obj);
	break;

      case T_ARRAY:
        if (FL_TEST(obj, ELTS_SHARED)) {
            VALUE root = any->as.array.as.heap.aux.shared_root;
            gc_mark(objspace, root);
	}
	else {
	    long i, len = RARRAY_LEN(obj);
            const VALUE *ptr = RARRAY_CONST_PTR_TRANSIENT(obj);
	    for (i=0; i < len; i++) {
                gc_mark(objspace, ptr[i]);
	    }

            if (LIKELY(during_gc)) {
                if (!FL_TEST_RAW(obj, RARRAY_EMBED_FLAG) &&
                    RARRAY_TRANSIENT_P(obj)) {
                    rb_transient_heap_mark(obj, ptr);
                }
            }
        }
	break;

      case T_HASH:
        mark_hash(objspace, obj);
	break;

      case T_STRING:
	if (STR_SHARED_P(obj)) {
	    gc_mark(objspace, any->as.string.as.heap.aux.shared);
	}
	break;

      case T_DATA:
	{
	    void *const ptr = DATA_PTR(obj);
	    if (ptr) {
		RUBY_DATA_FUNC mark_func = RTYPEDDATA_P(obj) ?
		    any->as.typeddata.type->function.dmark :
		    any->as.data.dmark;
		if (mark_func) (*mark_func)(ptr);
	    }
	}
	break;

      case T_OBJECT:
        {
            const VALUE * const ptr = ROBJECT_IVPTR(obj);

            uint32_t i, len = ROBJECT_NUMIV(obj);
            for (i  = 0; i < len; i++) {
                gc_mark(objspace, ptr[i]);
            }

            if (LIKELY(during_gc) &&
                    ROBJ_TRANSIENT_P(obj)) {
                rb_transient_heap_mark(obj, ptr);
            }
        }
	break;

      case T_FILE:
        if (any->as.file.fptr) {
            gc_mark(objspace, any->as.file.fptr->self);
            gc_mark(objspace, any->as.file.fptr->pathv);
            gc_mark(objspace, any->as.file.fptr->tied_io_for_writing);
            gc_mark(objspace, any->as.file.fptr->writeconv_asciicompat);
            gc_mark(objspace, any->as.file.fptr->writeconv_pre_ecopts);
            gc_mark(objspace, any->as.file.fptr->encs.ecopts);
            gc_mark(objspace, any->as.file.fptr->write_lock);
        }
        break;

      case T_REGEXP:
        gc_mark(objspace, any->as.regexp.src);
	break;

      case T_MATCH:
	gc_mark(objspace, any->as.match.regexp);
	if (any->as.match.str) {
	    gc_mark(objspace, any->as.match.str);
	}
	break;

      case T_RATIONAL:
	gc_mark(objspace, any->as.rational.num);
	gc_mark(objspace, any->as.rational.den);
	break;

      case T_COMPLEX:
	gc_mark(objspace, any->as.complex.real);
	gc_mark(objspace, any->as.complex.imag);
	break;

      case T_STRUCT:
	{
            long i;
            const long len = RSTRUCT_LEN(obj);
            const VALUE * const ptr = RSTRUCT_CONST_PTR(obj);

            for (i=0; i<len; i++) {
                gc_mark(objspace, ptr[i]);
            }

            if (LIKELY(during_gc) &&
                RSTRUCT_TRANSIENT_P(obj)) {
                rb_transient_heap_mark(obj, ptr);
            }
	}
	break;

      default:
#if GC_DEBUG
	rb_gcdebug_print_obj_condition((VALUE)obj);
#endif
        if (BUILTIN_TYPE(obj) == T_MOVED)   rb_bug("rb_gc_mark(): %p is T_MOVED", (void *)obj);
	if (BUILTIN_TYPE(obj) == T_NONE)   rb_bug("rb_gc_mark(): %p is T_NONE", (void *)obj);
	if (BUILTIN_TYPE(obj) == T_ZOMBIE) rb_bug("rb_gc_mark(): %p is T_ZOMBIE", (void *)obj);
	rb_bug("rb_gc_mark(): unknown data type 0x%x(%p) %s",
	       BUILTIN_TYPE(obj), (void *)any,
	       is_pointer_to_heap(objspace, any) ? "corrupted object" : "non object");
    }
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
#if GC_ENABLE_INCREMENTAL_MARK
    size_t marked_slots_at_the_beginning = objspace->marked_slots;
    size_t popped_count = 0;
#endif

    while (pop_mark_stack(mstack, &obj)) {
	if (obj == Qundef) continue; /* skip */

	if (RGENGC_CHECK_MODE && !RVALUE_MARKED(obj)) {
	    rb_bug("gc_mark_stacked_objects: %s is not marked.", obj_info(obj));
	}
        gc_mark_children(objspace, obj);

#if GC_ENABLE_INCREMENTAL_MARK
	if (incremental) {
	    if (RGENGC_CHECK_MODE && !RVALUE_MARKING(obj)) {
		rb_bug("gc_mark_stacked_objects: incremental, but marking bit is 0");
	    }
	    CLEAR_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj);
	    popped_count++;

	    if (popped_count + (objspace->marked_slots - marked_slots_at_the_beginning) > count) {
		break;
	    }
	}
	else {
	    /* just ignore marking bits */
	}
#endif
    }

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

#if PRINT_ROOT_TICKS
#define MAX_TICKS 0x100
static tick_t mark_ticks[MAX_TICKS];
static const char *mark_ticks_categories[MAX_TICKS];

static void
show_mark_ticks(void)
{
    int i;
    fprintf(stderr, "mark ticks result:\n");
    for (i=0; i<MAX_TICKS; i++) {
	const char *category = mark_ticks_categories[i];
	if (category) {
	    fprintf(stderr, "%s\t%8lu\n", category, (unsigned long)mark_ticks[i]);
	}
	else {
	    break;
	}
    }
}

#endif /* PRINT_ROOT_TICKS */

static void
gc_mark_roots(rb_objspace_t *objspace, const char **categoryp)
{
    struct gc_list *list;
    rb_execution_context_t *ec = GET_EC();
    rb_vm_t *vm = rb_ec_vm_ptr(ec);

#if PRINT_ROOT_TICKS
    tick_t start_tick = tick();
    int tick_count = 0;
    const char *prev_category = 0;

    if (mark_ticks_categories[0] == 0) {
	atexit(show_mark_ticks);
    }
#endif

    if (categoryp) *categoryp = "xxx";

    objspace->rgengc.parent_object = Qfalse;

#if PRINT_ROOT_TICKS
#define MARK_CHECKPOINT_PRINT_TICK(category) do { \
    if (prev_category) { \
	tick_t t = tick(); \
	mark_ticks[tick_count] = t - start_tick; \
	mark_ticks_categories[tick_count] = prev_category; \
	tick_count++; \
    } \
    prev_category = category; \
    start_tick = tick(); \
} while (0)
#else /* PRINT_ROOT_TICKS */
#define MARK_CHECKPOINT_PRINT_TICK(category)
#endif

#define MARK_CHECKPOINT(category) do { \
    if (categoryp) *categoryp = category; \
    MARK_CHECKPOINT_PRINT_TICK(category); \
} while (0)

    MARK_CHECKPOINT("vm");
    SET_STACK_END;
    rb_vm_mark(vm);
    if (vm->self) gc_mark(objspace, vm->self);

    MARK_CHECKPOINT("finalizers");
    mark_finalizer_tbl(objspace, finalizer_table);

    MARK_CHECKPOINT("machine_context");
    mark_current_machine_context(objspace, ec);

    /* mark protected global variables */
    MARK_CHECKPOINT("global_list");
    for (list = global_list; list; list = list->next) {
        gc_mark_maybe(objspace, *list->varptr);
    }

    MARK_CHECKPOINT("end_proc");
    rb_mark_end_proc();

    MARK_CHECKPOINT("global_tbl");
    rb_gc_mark_global_tbl();

    MARK_CHECKPOINT("object_id");
    rb_gc_mark(objspace->next_object_id);
    mark_tbl_no_pin(objspace, objspace->obj_to_id_tbl); /* Only mark ids */

    if (stress_to_class) rb_gc_mark(stress_to_class);

    MARK_CHECKPOINT("finish");
#undef MARK_CHECKPOINT
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
	    fprintf(stderr, "<%s>", obj_info(obj));
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

static st_table *
objspace_allrefs(rb_objspace_t *objspace)
{
    struct allrefs data;
    struct mark_func_data_struct mfd;
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
    objspace->mark_func_data = &mfd;
    gc_mark_roots(objspace, &data.category);
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
    fprintf(stderr, "[allrefs_dump_i] %s <- ", obj_info(obj));
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
    if (!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj)) {
	fprintf(stderr, "gc_check_after_marks_i: %s is not marked and not oldgen.\n", obj_info(obj));
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
    size_t saved_malloc_increase = objspace->malloc_params.increase;
#if RGENGC_ESTIMATE_OLDMALLOC
    size_t saved_oldmalloc_increase = objspace->rgengc.oldmalloc_increase;
#endif
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
    objspace->malloc_params.increase = saved_malloc_increase;
#if RGENGC_ESTIMATE_OLDMALLOC
    objspace->rgengc.oldmalloc_increase = saved_oldmalloc_increase;
#endif
}
#endif /* RGENGC_CHECK_MODE >= 4 */

struct verify_internal_consistency_struct {
    rb_objspace_t *objspace;
    int err_count;
    size_t live_object_count;
    size_t zombie_object_count;

    VALUE parent;
    size_t old_object_count;
    size_t remembered_shady_count;
};

static void
check_generation_i(const VALUE child, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;
    const VALUE parent = data->parent;

    if (RGENGC_CHECK_MODE) GC_ASSERT(RVALUE_OLD_P(parent));

    if (!RVALUE_OLD_P(child)) {
	if (!RVALUE_REMEMBERED(parent) &&
	    !RVALUE_REMEMBERED(child) &&
	    !RVALUE_UNCOLLECTIBLE(child)) {
	    fprintf(stderr, "verify_internal_consistency_reachable_i: WB miss (O->Y) %s -> %s\n", obj_info(parent), obj_info(child));
	    data->err_count++;
	}
    }
}

static void
check_color_i(const VALUE child, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;
    const VALUE parent = data->parent;

    if (!RVALUE_WB_UNPROTECTED(parent) && RVALUE_WHITE_P(child)) {
	fprintf(stderr, "verify_internal_consistency_reachable_i: WB miss (B->W) - %s -> %s\n",
		obj_info(parent), obj_info(child));
	data->err_count++;
    }
}

static void
check_children_i(const VALUE child, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;
    if (check_rvalue_consistency_force(child, FALSE) != 0) {
        fprintf(stderr, "check_children_i: %s has error (referenced from %s)",
                obj_info(child), obj_info(data->parent));
        rb_print_backtrace(); /* C backtrace will help to debug */

        data->err_count++;
    }
}

static int
verify_internal_consistency_i(void *page_start, void *page_end, size_t stride, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;
    VALUE obj;
    rb_objspace_t *objspace = data->objspace;

    for (obj = (VALUE)page_start; obj != (VALUE)page_end; obj += stride) {
        void *poisoned = asan_poisoned_object_p(obj);
        asan_unpoison_object(obj, false);

	if (is_live_object(objspace, obj)) {
	    /* count objects */
	    data->live_object_count++;
            data->parent = obj;

            /* Normally, we don't expect T_MOVED objects to be in the heap.
             * But they can stay alive on the stack, */
            if (!gc_object_moved_p(objspace, obj)) {
                /* moved slots don't have children */
                rb_objspace_reachable_objects_from(obj, check_children_i, (void *)data);
            }

	    /* check health of children */
	    if (RVALUE_OLD_P(obj)) data->old_object_count++;
	    if (RVALUE_WB_UNPROTECTED(obj) && RVALUE_UNCOLLECTIBLE(obj)) data->remembered_shady_count++;

	    if (!is_marking(objspace) && RVALUE_OLD_P(obj)) {
		/* reachable objects from an oldgen object should be old or (young with remember) */
		data->parent = obj;
		rb_objspace_reachable_objects_from(obj, check_generation_i, (void *)data);
	    }

	    if (is_incremental_marking(objspace)) {
		if (RVALUE_BLACK_P(obj)) {
		    /* reachable objects from black objects should be black or grey objects */
		    data->parent = obj;
		    rb_objspace_reachable_objects_from(obj, check_color_i, (void *)data);
		}
	    }
	}
	else {
	    if (BUILTIN_TYPE(obj) == T_ZOMBIE) {
		GC_ASSERT((RBASIC(obj)->flags & ~FL_SEEN_OBJ_ID) == T_ZOMBIE);
		data->zombie_object_count++;
	    }
	}
        if (poisoned) {
            GC_ASSERT(BUILTIN_TYPE(obj) == T_NONE);
            asan_poison_object(obj);
        }
    }

    return 0;
}

static int
gc_verify_heap_page(rb_objspace_t *objspace, struct heap_page *page, VALUE obj)
{
    int i;
    unsigned int has_remembered_shady = FALSE;
    unsigned int has_remembered_old = FALSE;
    int remembered_old_objects = 0;
    int free_objects = 0;
    int zombie_objects = 0;

    for (i=0; i<page->total_slots; i++) {
	VALUE val = (VALUE)&page->start[i];
        void *poisoned = asan_poisoned_object_p(val);
        asan_unpoison_object(val, false);

	if (RBASIC(val) == 0) free_objects++;
	if (BUILTIN_TYPE(val) == T_ZOMBIE) zombie_objects++;
	if (RVALUE_PAGE_UNCOLLECTIBLE(page, val) && RVALUE_PAGE_WB_UNPROTECTED(page, val)) {
	    has_remembered_shady = TRUE;
	}
	if (RVALUE_PAGE_MARKING(page, val)) {
	    has_remembered_old = TRUE;
	    remembered_old_objects++;
	}

        if (poisoned) {
            GC_ASSERT(BUILTIN_TYPE(val) == T_NONE);
            asan_poison_object(val);
        }
    }

    if (!is_incremental_marking(objspace) &&
	page->flags.has_remembered_objects == FALSE && has_remembered_old == TRUE) {

	for (i=0; i<page->total_slots; i++) {
	    VALUE val = (VALUE)&page->start[i];
	    if (RVALUE_PAGE_MARKING(page, val)) {
		fprintf(stderr, "marking -> %s\n", obj_info(val));
	    }
	}
	rb_bug("page %p's has_remembered_objects should be false, but there are remembered old objects (%d). %s",
	       (void *)page, remembered_old_objects, obj ? obj_info(obj) : "");
    }

    if (page->flags.has_uncollectible_shady_objects == FALSE && has_remembered_shady == TRUE) {
	rb_bug("page %p's has_remembered_shady should be false, but there are remembered shady objects. %s",
	       (void *)page, obj ? obj_info(obj) : "");
    }

    if (0) {
	/* free_slots may not equal to free_objects */
	if (page->free_slots != free_objects) {
	    rb_bug("page %p's free_slots should be %d, but %d\n", (void *)page, page->free_slots, free_objects);
	}
    }
    if (page->final_slots != zombie_objects) {
	rb_bug("page %p's final_slots should be %d, but %d\n", (void *)page, page->final_slots, zombie_objects);
    }

    return remembered_old_objects;
}

static int
gc_verify_heap_pages_(rb_objspace_t *objspace, struct list_head *head)
{
    int remembered_old_objects = 0;
    struct heap_page *page = 0;

    list_for_each(head, page, page_node) {
        asan_unpoison_memory_region(&page->freelist, sizeof(RVALUE*), false);
        RVALUE *p = page->freelist;
        while (p) {
            VALUE vp = (VALUE)p;
            VALUE prev = vp;
            asan_unpoison_object(vp, false);
            if (BUILTIN_TYPE(vp) != T_NONE) {
                fprintf(stderr, "freelist slot expected to be T_NONE but was: %s\n", obj_info(vp));
            }
            p = p->as.free.next;
            asan_poison_object(prev);
        }
        asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));

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
    remembered_old_objects += gc_verify_heap_pages_(objspace, &heap_eden->pages);
    remembered_old_objects += gc_verify_heap_pages_(objspace, &heap_tomb->pages);
    return remembered_old_objects;
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
    ASSERT_vm_locking();
    gc_verify_internal_consistency(&rb_objspace);
    return Qnil;
}

static void
gc_verify_internal_consistency_(rb_objspace_t *objspace)
{
    struct verify_internal_consistency_struct data = {0};

    data.objspace = objspace;
    gc_report(5, objspace, "gc_verify_internal_consistency: start\n");

    /* check relations */

    objspace_each_objects_without_setup(objspace, verify_internal_consistency_i, &data);

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

    if (!is_lazy_sweeping(heap_eden) && !finalizing) {
	if (objspace_live_slots(objspace) != data.live_object_count) {
	    fprintf(stderr, "heap_pages_final_slots: %"PRIdSIZE", "
                    "objspace->profile.total_freed_objects: %"PRIdSIZE"\n",
		    heap_pages_final_slots, objspace->profile.total_freed_objects);
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

	if (heap_pages_final_slots != data.zombie_object_count ||
	    heap_pages_final_slots != list_count) {

	    rb_bug("inconsistent finalizing object count:\n"
		   "  expect %"PRIuSIZE"\n"
		   "  but    %"PRIuSIZE" zombies\n"
		   "  heap_pages_deferred_final list has %"PRIuSIZE" items.",
		   heap_pages_final_slots,
		   data.zombie_object_count,
		   list_count);
	}
    }

    gc_report(5, objspace, "gc_verify_internal_consistency: OK\n");
}

static void
gc_verify_internal_consistency(rb_objspace_t *objspace)
{
    unsigned int prev_during_gc = during_gc;
    during_gc = FALSE; // stop gc here
    {
        gc_verify_internal_consistency_(objspace);
    }
    during_gc = prev_during_gc;
}

void
rb_gc_verify_internal_consistency(void)
{
    gc_verify_internal_consistency(&rb_objspace);
}

static VALUE
gc_verify_transient_heap_internal_consistency(VALUE dmy)
{
    rb_transient_heap_verify();
    return Qnil;
}

/* marks */

static void
gc_marks_start(rb_objspace_t *objspace, int full_mark)
{
    /* start marking */
    gc_report(1, objspace, "gc_marks_start: (%s)\n", full_mark ? "full" : "minor");
    gc_mode_transition(objspace, gc_mode_marking);

    if (full_mark) {
#if GC_ENABLE_INCREMENTAL_MARK
	objspace->rincgc.step_slots = (objspace->marked_slots * 2) / ((objspace->rincgc.pooled_slots / HEAP_PAGE_OBJ_LIMIT) + 1);

	if (0) fprintf(stderr, "objspace->marked_slots: %"PRIdSIZE", "
                       "objspace->rincgc.pooled_page_num: %"PRIdSIZE", "
                       "objspace->rincgc.step_slots: %"PRIdSIZE", \n",
                       objspace->marked_slots, objspace->rincgc.pooled_slots, objspace->rincgc.step_slots);
#endif
	objspace->flags.during_minor_gc = FALSE;
        if (ruby_enable_autocompact) {
            objspace->flags.during_compacting |= TRUE;
        }
	objspace->profile.major_gc_count++;
	objspace->rgengc.uncollectible_wb_unprotected_objects = 0;
	objspace->rgengc.old_objects = 0;
	objspace->rgengc.last_major_gc = objspace->profile.count;
	objspace->marked_slots = 0;
	rgengc_mark_and_rememberset_clear(objspace, heap_eden);
    }
    else {
	objspace->flags.during_minor_gc = TRUE;
	objspace->marked_slots =
	  objspace->rgengc.old_objects + objspace->rgengc.uncollectible_wb_unprotected_objects; /* uncollectible objects are marked already */
	objspace->profile.minor_gc_count++;
	rgengc_rememberset_mark(objspace, heap_eden);
    }

    gc_mark_roots(objspace, NULL);

    gc_report(1, objspace, "gc_marks_start: (%s) end, stack in %"PRIdSIZE"\n",
              full_mark ? "full" : "minor", mark_stack_size(&objspace->mark_stack));
}

#if GC_ENABLE_INCREMENTAL_MARK
static void
gc_marks_wb_unprotected_objects(rb_objspace_t *objspace)
{
    struct heap_page *page = 0;

    list_for_each(&heap_eden->pages, page, page_node) {
	bits_t *mark_bits = page->mark_bits;
	bits_t *wbun_bits = page->wb_unprotected_bits;
	RVALUE *p = page->start;
	RVALUE *offset = p - NUM_IN_PAGE(p);
	size_t j;

	for (j=0; j<HEAP_PAGE_BITMAP_LIMIT; j++) {
	    bits_t bits = mark_bits[j] & wbun_bits[j];

	    if (bits) {
		p = offset  + j * BITS_BITLENGTH;

		do {
		    if (bits & 1) {
			gc_report(2, objspace, "gc_marks_wb_unprotected_objects: marked shady: %s\n", obj_info((VALUE)p));
			GC_ASSERT(RVALUE_WB_UNPROTECTED((VALUE)p));
			GC_ASSERT(RVALUE_MARKED((VALUE)p));
			gc_mark_children(objspace, (VALUE)p);
		    }
		    p++;
		    bits >>= 1;
		} while (bits);
	    }
	}
    }

    gc_mark_stacked_objects_all(objspace);
}

static struct heap_page *
heap_move_pooled_pages_to_free_pages(rb_heap_t *heap)
{
    struct heap_page *page = heap->pooled_pages;

    if (page) {
	heap->pooled_pages = page->free_next;
        heap_add_freepage(heap, page);
    }

    return page;
}
#endif

static int
gc_marks_finish(rb_objspace_t *objspace)
{
#if GC_ENABLE_INCREMENTAL_MARK
    /* finish incremental GC */
    if (is_incremental_marking(objspace)) {
	if (heap_eden->pooled_pages) {
	    heap_move_pooled_pages_to_free_pages(heap_eden);
	    gc_report(1, objspace, "gc_marks_finish: pooled pages are exists. retry.\n");
	    return FALSE; /* continue marking phase */
	}

	if (RGENGC_CHECK_MODE && is_mark_stack_empty(&objspace->mark_stack) == 0) {
	    rb_bug("gc_marks_finish: mark stack is not empty (%"PRIdSIZE").",
                   mark_stack_size(&objspace->mark_stack));
	}

	gc_mark_roots(objspace, 0);

	if (is_mark_stack_empty(&objspace->mark_stack) == FALSE) {
	    gc_report(1, objspace, "gc_marks_finish: not empty (%"PRIdSIZE"). retry.\n",
                      mark_stack_size(&objspace->mark_stack));
	    return FALSE;
	}

#if RGENGC_CHECK_MODE >= 2
	if (gc_verify_heap_pages(objspace) != 0) {
	    rb_bug("gc_marks_finish (incremental): there are remembered old objects.");
	}
#endif

	objspace->flags.during_incremental_marking = FALSE;
	/* check children of all marked wb-unprotected objects */
	gc_marks_wb_unprotected_objects(objspace);
    }
#endif /* GC_ENABLE_INCREMENTAL_MARK */

#if RGENGC_CHECK_MODE >= 2
    gc_verify_internal_consistency(objspace);
#endif

    if (is_full_marking(objspace)) {
	/* See the comment about RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR */
	const double r = gc_params.oldobject_limit_factor;
	objspace->rgengc.uncollectible_wb_unprotected_objects_limit = (size_t)(objspace->rgengc.uncollectible_wb_unprotected_objects * r);
	objspace->rgengc.old_objects_limit = (size_t)(objspace->rgengc.old_objects * r);
    }

#if RGENGC_CHECK_MODE >= 4
    gc_marks_check(objspace, gc_check_after_marks_i, "after_marks");
#endif

    {
	/* decide full GC is needed or not */
	rb_heap_t *heap = heap_eden;
	size_t total_slots = heap_allocatable_pages * HEAP_PAGE_OBJ_LIMIT + heap->total_slots;
	size_t sweep_slots = total_slots - objspace->marked_slots; /* will be swept slots */
	size_t max_free_slots = (size_t)(total_slots * gc_params.heap_free_slots_max_ratio);
	size_t min_free_slots = (size_t)(total_slots * gc_params.heap_free_slots_min_ratio);
	int full_marking = is_full_marking(objspace);

	GC_ASSERT(heap->total_slots >= objspace->marked_slots);

	/* setup free-able page counts */
	if (max_free_slots < gc_params.heap_init_slots) max_free_slots = gc_params.heap_init_slots;

	if (sweep_slots > max_free_slots) {
	    heap_pages_freeable_pages = (sweep_slots - max_free_slots) / HEAP_PAGE_OBJ_LIMIT;
	}
	else {
	    heap_pages_freeable_pages = 0;
	}

	/* check free_min */
	if (min_free_slots < gc_params.heap_free_slots) min_free_slots = gc_params.heap_free_slots;

	if (sweep_slots < min_free_slots) {
	    if (!full_marking) {
		if (objspace->profile.count - objspace->rgengc.last_major_gc < RVALUE_OLD_AGE) {
		    full_marking = TRUE;
		    /* do not update last_major_gc, because full marking is not done. */
                    /* goto increment; */
		}
		else {
		    gc_report(1, objspace, "gc_marks_finish: next is full GC!!)\n");
		    objspace->rgengc.need_major_gc |= GPR_FLAG_MAJOR_BY_NOFREE;
		}
	    }
            if (full_marking) {
              /* increment: */
		gc_report(1, objspace, "gc_marks_finish: heap_set_increment!!\n");
		heap_set_increment(objspace, heap_extend_pages(objspace, sweep_slots, total_slots));
		heap_increment(objspace, heap);
	    }
	}

	if (full_marking) {
	    /* See the comment about RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR */
	    const double r = gc_params.oldobject_limit_factor;
	    objspace->rgengc.uncollectible_wb_unprotected_objects_limit = (size_t)(objspace->rgengc.uncollectible_wb_unprotected_objects * r);
	    objspace->rgengc.old_objects_limit = (size_t)(objspace->rgengc.old_objects * r);
	}

	if (objspace->rgengc.uncollectible_wb_unprotected_objects > objspace->rgengc.uncollectible_wb_unprotected_objects_limit) {
	    objspace->rgengc.need_major_gc |= GPR_FLAG_MAJOR_BY_SHADY;
	}
	if (objspace->rgengc.old_objects > objspace->rgengc.old_objects_limit) {
	    objspace->rgengc.need_major_gc |= GPR_FLAG_MAJOR_BY_OLDGEN;
	}
	if (RGENGC_FORCE_MAJOR_GC) {
	    objspace->rgengc.need_major_gc = GPR_FLAG_MAJOR_BY_FORCE;
	}

	gc_report(1, objspace, "gc_marks_finish (marks %"PRIdSIZE" objects, "
                  "old %"PRIdSIZE" objects, total %"PRIdSIZE" slots, "
                  "sweep %"PRIdSIZE" slots, increment: %"PRIdSIZE", next GC: %s)\n",
                  objspace->marked_slots, objspace->rgengc.old_objects, heap->total_slots, sweep_slots, heap_allocatable_pages,
		  objspace->rgengc.need_major_gc ? "major" : "minor");
    }

    rb_transient_heap_finish_marking();

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_END_MARK, 0);

    return TRUE;
}

static void
gc_marks_step(rb_objspace_t *objspace, size_t slots)
{
#if GC_ENABLE_INCREMENTAL_MARK
    GC_ASSERT(is_marking(objspace));

    if (gc_mark_stacked_objects_incremental(objspace, slots)) {
	if (gc_marks_finish(objspace)) {
	    /* finish */
	    gc_sweep(objspace);
	}
    }
    if (0) fprintf(stderr, "objspace->marked_slots: %"PRIdSIZE"\n", objspace->marked_slots);
#endif
}

static void
gc_marks_rest(rb_objspace_t *objspace)
{
    gc_report(1, objspace, "gc_marks_rest\n");

#if GC_ENABLE_INCREMENTAL_MARK
    heap_eden->pooled_pages = NULL;
#endif

    if (is_incremental_marking(objspace)) {
	do {
	    while (gc_mark_stacked_objects_incremental(objspace, INT_MAX) == FALSE);
	} while (gc_marks_finish(objspace) == FALSE);
    }
    else {
	gc_mark_stacked_objects_all(objspace);
	gc_marks_finish(objspace);
    }

    /* move to sweep */
    gc_sweep(objspace);
}

static void
gc_marks_continue(rb_objspace_t *objspace, rb_heap_t *heap)
{
    GC_ASSERT(dont_gc_val() == FALSE);
#if GC_ENABLE_INCREMENTAL_MARK

    unsigned int lock_lev;
    gc_enter(objspace, "marks_continue", &lock_lev);

    int slots = 0;
    const char *from;

    if (heap->pooled_pages) {
        while (heap->pooled_pages && slots < HEAP_PAGE_OBJ_LIMIT) {
            struct heap_page *page = heap_move_pooled_pages_to_free_pages(heap);
            slots += page->free_slots;
        }
        from = "pooled-pages";
    }
    else if (heap_increment(objspace, heap)) {
        slots = heap->free_pages->free_slots;
        from = "incremented-pages";
    }

    if (slots > 0) {
        gc_report(2, objspace, "gc_marks_continue: provide %d slots from %s.\n",
                  slots, from);
        gc_marks_step(objspace, objspace->rincgc.step_slots);
    }
    else {
        gc_report(2, objspace, "gc_marks_continue: no more pooled pages (stack depth: %"PRIdSIZE").\n",
                  mark_stack_size(&objspace->mark_stack));
        gc_marks_rest(objspace);
    }

    gc_exit(objspace, "marks_continue", &lock_lev);
#endif
}

static void
gc_marks(rb_objspace_t *objspace, int full_mark)
{
    gc_prof_mark_timer_start(objspace);

    /* setup marking */

    gc_marks_start(objspace, full_mark);
    if (!is_incremental_marking(objspace)) {
        gc_marks_rest(objspace);
    }

#if RGENGC_PROFILE > 0
    if (gc_prof_record(objspace)) {
        gc_profile_record *record = gc_prof_record(objspace);
        record->old_objects = objspace->rgengc.old_objects;
    }
#endif
    gc_prof_mark_timer_stop(objspace);
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
	    if (is_lazy_sweeping(heap_eden)) {
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
rgengc_remembersetbits_get(rb_objspace_t *objspace, VALUE obj)
{
    return RVALUE_REMEMBERED(obj);
}

static int
rgengc_remembersetbits_set(rb_objspace_t *objspace, VALUE obj)
{
    struct heap_page *page = GET_HEAP_PAGE(obj);
    bits_t *bits = &page->marking_bits[0];

    GC_ASSERT(!is_incremental_marking(objspace));

    if (MARKED_IN_BITMAP(bits, obj)) {
	return FALSE;
    }
    else {
	page->flags.has_remembered_objects = TRUE;
	MARK_IN_BITMAP(bits, obj);
	return TRUE;
    }
}

/* wb, etc */

/* return FALSE if already remembered */
static int
rgengc_remember(rb_objspace_t *objspace, VALUE obj)
{
    gc_report(6, objspace, "rgengc_remember: %s %s\n", obj_info(obj),
	      rgengc_remembersetbits_get(objspace, obj) ? "was already remembered" : "is remembered now");

    check_rvalue_consistency(obj);

    if (RGENGC_CHECK_MODE) {
	if (RVALUE_WB_UNPROTECTED(obj)) rb_bug("rgengc_remember: %s is not wb protected.", obj_info(obj));
    }

#if RGENGC_PROFILE > 0
    if (!rgengc_remembered(objspace, obj)) {
	if (RVALUE_WB_UNPROTECTED(obj) == 0) {
	    objspace->profile.total_remembered_normal_object_count++;
#if RGENGC_PROFILE >= 2
	    objspace->profile.remembered_normal_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
	}
    }
#endif /* RGENGC_PROFILE > 0 */

    return rgengc_remembersetbits_set(objspace, obj);
}

static int
rgengc_remembered_sweep(rb_objspace_t *objspace, VALUE obj)
{
    int result = rgengc_remembersetbits_get(objspace, obj);
    check_rvalue_consistency(obj);
    return result;
}

static int
rgengc_remembered(rb_objspace_t *objspace, VALUE obj)
{
    gc_report(6, objspace, "rgengc_remembered: %s\n", obj_info(obj));
    return rgengc_remembered_sweep(objspace, obj);
}

#ifndef PROFILE_REMEMBERSET_MARK
#define PROFILE_REMEMBERSET_MARK 0
#endif

static void
rgengc_rememberset_mark(rb_objspace_t *objspace, rb_heap_t *heap)
{
    size_t j;
    struct heap_page *page = 0;
#if PROFILE_REMEMBERSET_MARK
    int has_old = 0, has_shady = 0, has_both = 0, skip = 0;
#endif
    gc_report(1, objspace, "rgengc_rememberset_mark: start\n");

    list_for_each(&heap->pages, page, page_node) {
	if (page->flags.has_remembered_objects | page->flags.has_uncollectible_shady_objects) {
	    RVALUE *p = page->start;
	    RVALUE *offset = p - NUM_IN_PAGE(p);
	    bits_t bitset, bits[HEAP_PAGE_BITMAP_LIMIT];
	    bits_t *marking_bits = page->marking_bits;
	    bits_t *uncollectible_bits = page->uncollectible_bits;
	    bits_t *wb_unprotected_bits = page->wb_unprotected_bits;
#if PROFILE_REMEMBERSET_MARK
	    if (page->flags.has_remembered_objects && page->flags.has_uncollectible_shady_objects) has_both++;
	    else if (page->flags.has_remembered_objects) has_old++;
	    else if (page->flags.has_uncollectible_shady_objects) has_shady++;
#endif
	    for (j=0; j<HEAP_PAGE_BITMAP_LIMIT; j++) {
		bits[j] = marking_bits[j] | (uncollectible_bits[j] & wb_unprotected_bits[j]);
		marking_bits[j] = 0;
	    }
	    page->flags.has_remembered_objects = FALSE;

	    for (j=0; j < HEAP_PAGE_BITMAP_LIMIT; j++) {
		bitset = bits[j];

		if (bitset) {
		    p = offset  + j * BITS_BITLENGTH;

		    do {
			if (bitset & 1) {
			    VALUE obj = (VALUE)p;
			    gc_report(2, objspace, "rgengc_rememberset_mark: mark %s\n", obj_info(obj));
			    GC_ASSERT(RVALUE_UNCOLLECTIBLE(obj));
			    GC_ASSERT(RVALUE_OLD_P(obj) || RVALUE_WB_UNPROTECTED(obj));

			    gc_mark_children(objspace, obj);
			}
			p++;
			bitset >>= 1;
		    } while (bitset);
		}
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

    list_for_each(&heap->pages, page, page_node) {
	memset(&page->mark_bits[0],       0, HEAP_PAGE_BITMAP_SIZE);
	memset(&page->uncollectible_bits[0], 0, HEAP_PAGE_BITMAP_SIZE);
        memset(&page->marking_bits[0],    0, HEAP_PAGE_BITMAP_SIZE);
        memset(&page->pinned_bits[0],     0, HEAP_PAGE_BITMAP_SIZE);
	page->flags.has_uncollectible_shady_objects = FALSE;
	page->flags.has_remembered_objects = FALSE;
    }
}

/* RGENGC: APIs */

NOINLINE(static void gc_writebarrier_generational(VALUE a, VALUE b, rb_objspace_t *objspace));

static void
gc_writebarrier_generational(VALUE a, VALUE b, rb_objspace_t *objspace)
{
    if (RGENGC_CHECK_MODE) {
	if (!RVALUE_OLD_P(a)) rb_bug("gc_writebarrier_generational: %s is not an old object.", obj_info(a));
	if ( RVALUE_OLD_P(b)) rb_bug("gc_writebarrier_generational: %s is an old object.", obj_info(b));
	if (is_incremental_marking(objspace)) rb_bug("gc_writebarrier_generational: called while incremental marking: %s -> %s", obj_info(a), obj_info(b));
    }

#if 1
    /* mark `a' and remember (default behavior) */
    if (!rgengc_remembered(objspace, a)) {
	rgengc_remember(objspace, a);
	gc_report(1, objspace, "gc_writebarrier_generational: %s (remembered) -> %s\n", obj_info(a), obj_info(b));
    }
#else
    /* mark `b' and remember */
    MARK_IN_BITMAP(GET_HEAP_MARK_BITS(b), b);
    if (RVALUE_WB_UNPROTECTED(b)) {
	gc_remember_unprotected(objspace, b);
    }
    else {
	RVALUE_AGE_SET_OLD(objspace, b);
	rgengc_remember(objspace, b);
    }

    gc_report(1, objspace, "gc_writebarrier_generational: %s -> %s (remembered)\n", obj_info(a), obj_info(b));
#endif

    check_rvalue_consistency(a);
    check_rvalue_consistency(b);
}

#if GC_ENABLE_INCREMENTAL_MARK
static void
gc_mark_from(rb_objspace_t *objspace, VALUE obj, VALUE parent)
{
    gc_mark_set_parent(objspace, parent);
    rgengc_check_relation(objspace, obj);
    if (gc_mark_set(objspace, obj) == FALSE) return;
    gc_aging(objspace, obj);
    gc_grey(objspace, obj);
}

NOINLINE(static void gc_writebarrier_incremental(VALUE a, VALUE b, rb_objspace_t *objspace));

static void
gc_writebarrier_incremental(VALUE a, VALUE b, rb_objspace_t *objspace)
{
    gc_report(2, objspace, "gc_writebarrier_incremental: [LG] %p -> %s\n", (void *)a, obj_info(b));

    if (RVALUE_BLACK_P(a)) {
	if (RVALUE_WHITE_P(b)) {
	    if (!RVALUE_WB_UNPROTECTED(a)) {
		gc_report(2, objspace, "gc_writebarrier_incremental: [IN] %p -> %s\n", (void *)a, obj_info(b));
		gc_mark_from(objspace, b, a);
	    }
	}
	else if (RVALUE_OLD_P(a) && !RVALUE_OLD_P(b)) {
	    if (!RVALUE_WB_UNPROTECTED(b)) {
		gc_report(1, objspace, "gc_writebarrier_incremental: [GN] %p -> %s\n", (void *)a, obj_info(b));
		RVALUE_AGE_SET_OLD(objspace, b);

		if (RVALUE_BLACK_P(b)) {
		    gc_grey(objspace, b);
		}
	    }
	    else {
		gc_report(1, objspace, "gc_writebarrier_incremental: [LL] %p -> %s\n", (void *)a, obj_info(b));
		gc_remember_unprotected(objspace, b);
	    }
	}

        if (UNLIKELY(objspace->flags.during_compacting)) {
            MARK_IN_BITMAP(GET_HEAP_PINNED_BITS(b), b);
        }
    }
}
#else
#define gc_writebarrier_incremental(a, b, objspace)
#endif

void
rb_gc_writebarrier(VALUE a, VALUE b)
{
    rb_objspace_t *objspace = &rb_objspace;
    bool retry;

    if (RGENGC_CHECK_MODE && SPECIAL_CONST_P(a)) rb_bug("rb_gc_writebarrier: a is special const");
    if (RGENGC_CHECK_MODE && SPECIAL_CONST_P(b)) rb_bug("rb_gc_writebarrier: b is special const");

  retry_:
    retry = false;
    if (!is_incremental_marking(objspace)) {
        if (!RVALUE_OLD_P(a) || RVALUE_OLD_P(b)) {
            // do nothing
        }
        else {
            RB_VM_LOCK_ENTER(); // can change GC state
            {
                if (!is_incremental_marking(objspace)) {
                    if (!RVALUE_OLD_P(a) || RVALUE_OLD_P(b)) {
                        // do nothing
                    }
                    else {
                        gc_writebarrier_generational(a, b, objspace);
                    }
                }
                else {
                    retry = true;
                }
            }
            RB_VM_LOCK_LEAVE();
        }
    }
    else { /* slow path */
        RB_VM_LOCK_ENTER(); // can change GC state
        {
            if (is_incremental_marking(objspace)) {
                gc_writebarrier_incremental(a, b, objspace);
            }
            else {
                retry = true;
            }
        }
        RB_VM_LOCK_LEAVE();
    }
    if (retry) goto retry_;

    return;
}

void
rb_gc_writebarrier_unprotect(VALUE obj)
{
    if (RVALUE_WB_UNPROTECTED(obj)) {
	return;
    }
    else {
	rb_objspace_t *objspace = &rb_objspace;

	gc_report(2, objspace, "rb_gc_writebarrier_unprotect: %s %s\n", obj_info(obj),
		  rgengc_remembered(objspace, obj) ? " (already remembered)" : "");

	if (RVALUE_OLD_P(obj)) {
	    gc_report(1, objspace, "rb_gc_writebarrier_unprotect: %s\n", obj_info(obj));
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

/*
 * remember `obj' if needed.
 */
MJIT_FUNC_EXPORTED void
rb_gc_writebarrier_remember(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;

    gc_report(1, objspace, "rb_gc_writebarrier_remember: %s\n", obj_info(obj));

    if (is_incremental_marking(objspace)) {
	if (RVALUE_BLACK_P(obj)) {
	    gc_grey(objspace, obj);
	}
    }
    else {
	if (RVALUE_OLD_P(obj)) {
	    rgengc_remember(objspace, obj);
	}
    }
}

static st_table *rgengc_unprotect_logging_table;

static int
rgengc_unprotect_logging_exit_func_i(st_data_t key, st_data_t val, st_data_t arg)
{
    fprintf(stderr, "%s\t%"PRIuVALUE"\n", (char *)key, (VALUE)val);
    return ST_CONTINUE;
}

static void
rgengc_unprotect_logging_exit_func(void)
{
    st_foreach(rgengc_unprotect_logging_table, rgengc_unprotect_logging_exit_func_i, 0);
}

void
rb_gc_unprotect_logging(void *objptr, const char *filename, int line)
{
    VALUE obj = (VALUE)objptr;

    if (rgengc_unprotect_logging_table == 0) {
	rgengc_unprotect_logging_table = st_init_strtable();
	atexit(rgengc_unprotect_logging_exit_func);
    }

    if (RVALUE_WB_UNPROTECTED(obj) == 0) {
	char buff[0x100];
	st_data_t cnt = 1;
	char *ptr = buff;

	snprintf(ptr, 0x100 - 1, "%s|%s:%d", obj_info(obj), filename, line);

	if (st_lookup(rgengc_unprotect_logging_table, (st_data_t)ptr, &cnt)) {
	    cnt++;
	}
	else {
	    ptr = (strdup)(buff);
	    if (!ptr) rb_memerror();
	}
	st_insert(rgengc_unprotect_logging_table, (st_data_t)ptr, cnt);
    }
}

void
rb_copy_wb_protected_attribute(VALUE dest, VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;

    if (RVALUE_WB_UNPROTECTED(obj) && !RVALUE_WB_UNPROTECTED(dest)) {
	if (!RVALUE_OLD_P(dest)) {
	    MARK_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(dest), dest);
	    RVALUE_AGE_RESET_RAW(dest);
	}
	else {
	    RVALUE_DEMOTE(objspace, dest);
	}
    }

    check_rvalue_consistency(dest);
}

/* RGENGC analysis information */

VALUE
rb_obj_rgengc_writebarrier_protected_p(VALUE obj)
{
    return RVALUE_WB_UNPROTECTED(obj) ? Qfalse : Qtrue;
}

VALUE
rb_obj_rgengc_promoted_p(VALUE obj)
{
    return OBJ_PROMOTED(obj) ? Qtrue : Qfalse;
}

size_t
rb_obj_gc_flags(VALUE obj, ID* flags, size_t max)
{
    size_t n = 0;
    static ID ID_marked;
    static ID ID_wb_protected, ID_old, ID_marking, ID_uncollectible, ID_pinned;

    if (!ID_marked) {
#define I(s) ID_##s = rb_intern(#s);
	I(marked);
	I(wb_protected);
	I(old);
	I(marking);
	I(uncollectible);
        I(pinned);
#undef I
    }

    if (RVALUE_WB_UNPROTECTED(obj) == 0 && n<max)                   flags[n++] = ID_wb_protected;
    if (RVALUE_OLD_P(obj) && n<max)                                 flags[n++] = ID_old;
    if (RVALUE_UNCOLLECTIBLE(obj) && n<max)                         flags[n++] = ID_uncollectible;
    if (MARKED_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj) && n<max) flags[n++] = ID_marking;
    if (MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj) && n<max)    flags[n++] = ID_marked;
    if (MARKED_IN_BITMAP(GET_HEAP_PINNED_BITS(obj), obj) && n<max)  flags[n++] = ID_pinned;
    return n;
}

/* GC */

void
rb_gc_force_recycle(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;
    RB_VM_LOCK_ENTER();
    {
        int is_old = RVALUE_OLD_P(obj);

        gc_report(2, objspace, "rb_gc_force_recycle: %s\n", obj_info(obj));

        if (is_old) {
            if (RVALUE_MARKED(obj)) {
                objspace->rgengc.old_objects--;
            }
        }
        CLEAR_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS(obj), obj);
        CLEAR_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(obj), obj);
        CLEAR_IN_BITMAP(GET_HEAP_PINNED_BITS(obj), obj);

#if GC_ENABLE_INCREMENTAL_MARK
        if (is_incremental_marking(objspace)) {
            if (MARKED_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj)) {
                invalidate_mark_stack(&objspace->mark_stack, obj);
                CLEAR_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj);
            }
            CLEAR_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj);
        }
        else {
#endif
            if (is_old || !GET_HEAP_PAGE(obj)->flags.before_sweep) {
                CLEAR_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj);
            }
            CLEAR_IN_BITMAP(GET_HEAP_MARKING_BITS(obj), obj);
#if GC_ENABLE_INCREMENTAL_MARK
        }
#endif

        objspace->profile.total_freed_objects++;

        heap_page_add_freeobj(objspace, GET_HEAP_PAGE(obj), obj);

        /* Disable counting swept_slots because there are no meaning.
         * if (!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(p), p)) {
         *   objspace->heap.swept_slots++;
         * }
         */
    }
    RB_VM_LOCK_LEAVE();
}

#ifndef MARK_OBJECT_ARY_BUCKET_SIZE
#define MARK_OBJECT_ARY_BUCKET_SIZE 1024
#endif

void
rb_gc_register_mark_object(VALUE obj)
{
    RB_VM_LOCK_ENTER();
    {
        VALUE ary_ary = GET_VM()->mark_object_ary;
        VALUE ary = rb_ary_last(0, 0, ary_ary);

        if (ary == Qnil || RARRAY_LEN(ary) >= MARK_OBJECT_ARY_BUCKET_SIZE) {
            ary = rb_ary_tmp_new(MARK_OBJECT_ARY_BUCKET_SIZE);
            rb_ary_push(ary_ary, ary);
        }

        rb_ary_push(ary, obj);
    }
    RB_VM_LOCK_LEAVE();
}

void
rb_gc_register_address(VALUE *addr)
{
    rb_objspace_t *objspace = &rb_objspace;
    struct gc_list *tmp;

    tmp = ALLOC(struct gc_list);
    tmp->next = global_list;
    tmp->varptr = addr;
    global_list = tmp;
}

void
rb_gc_unregister_address(VALUE *addr)
{
    rb_objspace_t *objspace = &rb_objspace;
    struct gc_list *tmp = global_list;

    if (tmp->varptr == addr) {
	global_list = tmp->next;
	xfree(tmp);
	return;
    }
    while (tmp->next) {
	if (tmp->next->varptr == addr) {
	    struct gc_list *t = tmp->next;

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

#define GC_NOTIFY 0

enum {
    gc_stress_no_major,
    gc_stress_no_immediate_sweep,
    gc_stress_full_mark_after_malloc,
    gc_stress_max
};

#define gc_stress_full_mark_after_malloc_p() \
    (FIXNUM_P(ruby_gc_stress_mode) && (FIX2LONG(ruby_gc_stress_mode) & (1<<gc_stress_full_mark_after_malloc)))

static void
heap_ready_to_gc(rb_objspace_t *objspace, rb_heap_t *heap)
{
    if (!heap->freelist && !heap->free_pages) {
	if (!heap_increment(objspace, heap)) {
	    heap_set_increment(objspace, 1);
	    heap_increment(objspace, heap);
	}
    }
}

static int
ready_to_gc(rb_objspace_t *objspace)
{
    if (dont_gc_val() || during_gc || ruby_disable_gc) {
	heap_ready_to_gc(objspace, heap_eden);
	return FALSE;
    }
    else {
	return TRUE;
    }
}

static void
gc_reset_malloc_info(rb_objspace_t *objspace)
{
    gc_prof_set_malloc_info(objspace);
    {
	size_t inc = ATOMIC_SIZE_EXCHANGE(malloc_increase, 0);
	size_t old_limit = malloc_limit;

	if (inc > malloc_limit) {
	    malloc_limit = (size_t)(inc * gc_params.malloc_limit_growth_factor);
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
    if (!is_full_marking(objspace)) {
	if (objspace->rgengc.oldmalloc_increase > objspace->rgengc.oldmalloc_increase_limit) {
	    objspace->rgengc.need_major_gc |= GPR_FLAG_MAJOR_BY_OLDMALLOC;
	    objspace->rgengc.oldmalloc_increase_limit =
	      (size_t)(objspace->rgengc.oldmalloc_increase_limit * gc_params.oldmalloc_limit_growth_factor);

	    if (objspace->rgengc.oldmalloc_increase_limit > gc_params.oldmalloc_limit_max) {
		objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_max;
	    }
	}

	if (0) fprintf(stderr, "%"PRIdSIZE"\t%d\t%"PRIuSIZE"\t%"PRIuSIZE"\t%"PRIdSIZE"\n",
		       rb_gc_count(),
		       objspace->rgengc.need_major_gc,
		       objspace->rgengc.oldmalloc_increase,
		       objspace->rgengc.oldmalloc_increase_limit,
		       gc_params.oldmalloc_limit_max);
    }
    else {
	/* major GC */
	objspace->rgengc.oldmalloc_increase = 0;

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

static int
garbage_collect(rb_objspace_t *objspace, int reason)
{
    int ret;

    RB_VM_LOCK_ENTER();
    {
#if GC_PROFILE_MORE_DETAIL
        objspace->profile.prepare_time = getrusage_time();
#endif

        gc_rest(objspace);

#if GC_PROFILE_MORE_DETAIL
        objspace->profile.prepare_time = getrusage_time() - objspace->profile.prepare_time;
#endif

        ret = gc_start(objspace, reason);
    }
    RB_VM_LOCK_LEAVE();

    return ret;
}

static int
gc_start(rb_objspace_t *objspace, int reason)
{
    unsigned int do_full_mark = !!((unsigned)reason & GPR_FLAG_FULL_MARK);
    unsigned int immediate_mark = (unsigned)reason & GPR_FLAG_IMMEDIATE_MARK;

    /* reason may be clobbered, later, so keep set immediate_sweep here */
    objspace->flags.immediate_sweep = !!((unsigned)reason & GPR_FLAG_IMMEDIATE_SWEEP);

    /* Explicitly enable compaction (GC.compact) */
    objspace->flags.during_compacting = (!!((unsigned)reason & GPR_FLAG_COMPACT) << 1);

    if (!heap_allocated_pages) return FALSE; /* heap is not ready */
    if (!(reason & GPR_FLAG_METHOD) && !ready_to_gc(objspace)) return TRUE; /* GC is not allowed */

    GC_ASSERT(gc_mode(objspace) == gc_mode_none);
    GC_ASSERT(!is_lazy_sweeping(heap_eden));
    GC_ASSERT(!is_incremental_marking(objspace));

    unsigned int lock_lev;
    gc_enter(objspace, "gc_start", &lock_lev);

#if RGENGC_CHECK_MODE >= 2
    gc_verify_internal_consistency(objspace);
#endif

    if (ruby_gc_stressful) {
	int flag = FIXNUM_P(ruby_gc_stress_mode) ? FIX2INT(ruby_gc_stress_mode) : 0;

	if ((flag & (1<<gc_stress_no_major)) == 0) {
	    do_full_mark = TRUE;
	}

	objspace->flags.immediate_sweep = !(flag & (1<<gc_stress_no_immediate_sweep));
    }
    else {
	if (objspace->rgengc.need_major_gc) {
	    reason |= objspace->rgengc.need_major_gc;
	    do_full_mark = TRUE;
	}
	else if (RGENGC_FORCE_MAJOR_GC) {
	    reason = GPR_FLAG_MAJOR_BY_FORCE;
	    do_full_mark = TRUE;
	}

	objspace->rgengc.need_major_gc = GPR_FLAG_NONE;
    }

    if (do_full_mark && (reason & GPR_FLAG_MAJOR_MASK) == 0) {
	reason |= GPR_FLAG_MAJOR_BY_FORCE; /* GC by CAPI, METHOD, and so on. */
    }

#if GC_ENABLE_INCREMENTAL_MARK
    if (!GC_ENABLE_INCREMENTAL_MARK || objspace->flags.dont_incremental || immediate_mark) {
	objspace->flags.during_incremental_marking = FALSE;
    }
    else {
	objspace->flags.during_incremental_marking = do_full_mark;
    }
#endif

    if (!GC_ENABLE_LAZY_SWEEP || objspace->flags.dont_incremental) {
	objspace->flags.immediate_sweep = TRUE;
    }

    if (objspace->flags.immediate_sweep) reason |= GPR_FLAG_IMMEDIATE_SWEEP;

    gc_report(1, objspace, "gc_start(reason: %d) => %u, %d, %d\n",
	      reason,
	      do_full_mark, !is_incremental_marking(objspace), objspace->flags.immediate_sweep);

#if USE_DEBUG_COUNTER
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
#endif

    objspace->profile.count++;
    objspace->profile.latest_gc_info = reason;
    objspace->profile.total_allocated_objects_at_gc_start = objspace->total_allocated_objects;
    objspace->profile.heap_used_at_gc_start = heap_allocated_pages;
    gc_prof_setup_new_record(objspace, reason);
    gc_reset_malloc_info(objspace);
    rb_transient_heap_start_marking(do_full_mark);

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_START, 0 /* TODO: pass minor/immediate flag? */);
    GC_ASSERT(during_gc);

    gc_prof_timer_start(objspace);
    {
	gc_marks(objspace, do_full_mark);
    }
    gc_prof_timer_stop(objspace);

    gc_exit(objspace, "gc_start", &lock_lev);
    return TRUE;
}

static void
gc_rest(rb_objspace_t *objspace)
{
    int marking = is_incremental_marking(objspace);
    int sweeping = is_lazy_sweeping(heap_eden);

    if (marking || sweeping) {
        unsigned int lock_lev;
	gc_enter(objspace, "gc_rest", &lock_lev);

        if (RGENGC_CHECK_MODE >= 2) gc_verify_internal_consistency(objspace);

	if (is_incremental_marking(objspace)) {
            gc_marks_rest(objspace);
        }
	if (is_lazy_sweeping(heap_eden)) {
	    gc_sweep_rest(objspace);
	}
	gc_exit(objspace, "gc_rest", &lock_lev);
    }
}

struct objspace_and_reason {
    rb_objspace_t *objspace;
    int reason;
};

static void
gc_current_status_fill(rb_objspace_t *objspace, char *buff)
{
    int i = 0;
    if (is_marking(objspace)) {
	buff[i++] = 'M';
	if (is_full_marking(objspace))        buff[i++] = 'F';
#if GC_ENABLE_INCREMENTAL_MARK
	if (is_incremental_marking(objspace)) buff[i++] = 'I';
#endif
    }
    else if (is_sweeping(objspace)) {
	buff[i++] = 'S';
	if (is_lazy_sweeping(heap_eden))      buff[i++] = 'L';
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

static inline void
gc_enter(rb_objspace_t *objspace, const char *event, unsigned int *lock_lev)
{
    // stop other ractors

    RB_VM_LOCK_ENTER_LEV(lock_lev);
    rb_vm_barrier();

    GC_ASSERT(during_gc == 0);
    if (RGENGC_CHECK_MODE >= 3) gc_verify_internal_consistency(objspace);

    mjit_gc_start_hook();

    during_gc = TRUE;
    RUBY_DEBUG_LOG("%s (%s)", event, gc_current_status(objspace));
    gc_report(1, objspace, "gc_enter: %s [%s]\n", event, gc_current_status(objspace));
    gc_record(objspace, 0, event);
    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_ENTER, 0); /* TODO: which parameter should be passed? */
}

static inline void
gc_exit(rb_objspace_t *objspace, const char *event, unsigned int *lock_lev)
{
    GC_ASSERT(during_gc != 0);

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_EXIT, 0); /* TODO: which parameter should be passsed? */
    gc_record(objspace, 1, event);
    RUBY_DEBUG_LOG("%s (%s)", event, gc_current_status(objspace));
    gc_report(1, objspace, "gc_exit: %s [%s]\n", event, gc_current_status(objspace));
    during_gc = FALSE;

    mjit_gc_exit_hook();
    RB_VM_LOCK_LEAVE_LEV(lock_lev);
}

static void *
gc_with_gvl(void *ptr)
{
    struct objspace_and_reason *oar = (struct objspace_and_reason *)ptr;
    return (void *)(VALUE)garbage_collect(oar->objspace, oar->reason);
}

static int
garbage_collect_with_gvl(rb_objspace_t *objspace, int reason)
{
    if (dont_gc_val()) return TRUE;
    if (ruby_thread_has_gvl_p()) {
	return garbage_collect(objspace, reason);
    }
    else {
	if (ruby_native_thread_p()) {
	    struct objspace_and_reason oar;
	    oar.objspace = objspace;
	    oar.reason = reason;
	    return (int)(VALUE)rb_thread_call_with_gvl(gc_with_gvl, (void *)&oar);
	}
	else {
	    /* no ruby thread */
	    fprintf(stderr, "[FATAL] failed to allocate memory\n");
	    exit(EXIT_FAILURE);
	}
    }
}

static VALUE
gc_start_internal(rb_execution_context_t *ec, VALUE self, VALUE full_mark, VALUE immediate_mark, VALUE immediate_sweep, VALUE compact)
{
    rb_objspace_t *objspace = &rb_objspace;
    int reason = GPR_FLAG_FULL_MARK |
                 GPR_FLAG_IMMEDIATE_MARK |
                 GPR_FLAG_IMMEDIATE_SWEEP |
                 GPR_FLAG_METHOD;

    /* For now, compact implies full mark / sweep, so ignore other flags */
    if (RTEST(compact)) {
        reason |= GPR_FLAG_COMPACT;
    } else {
        if (!RTEST(full_mark))       reason &= ~GPR_FLAG_FULL_MARK;
        if (!RTEST(immediate_mark))  reason &= ~GPR_FLAG_IMMEDIATE_MARK;
        if (!RTEST(immediate_sweep)) reason &= ~GPR_FLAG_IMMEDIATE_SWEEP;
    }

    garbage_collect(objspace, reason);
    gc_finalize_deferred(objspace);

    return Qnil;
}

static int
gc_is_moveable_obj(rb_objspace_t *objspace, VALUE obj)
{
    GC_ASSERT(!SPECIAL_CONST_P(obj));

    switch (BUILTIN_TYPE(obj)) {
      case T_NONE:
      case T_NIL:
      case T_MOVED:
      case T_ZOMBIE:
        return FALSE;
      case T_SYMBOL:
        if (DYNAMIC_SYM_P(obj) && (RSYMBOL(obj)->id & ~ID_SCOPE_MASK)) {
            return FALSE;
        }
        /* fall through */
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
        if (FL_TEST(obj, FL_FINALIZE)) {
            /* The finalizer table is a numtable. It looks up objects by address.
             * We can't mark the keys in the finalizer table because that would
             * prevent the objects from being collected.  This check prevents
             * objects that are keys in the finalizer table from being moved
             * without directly pinning them. */
            if (st_is_member(finalizer_table, obj)) {
                return FALSE;
            }
        }
        GC_ASSERT(RVALUE_MARKED(obj));
        GC_ASSERT(!RVALUE_PINNED(obj));

        return TRUE;

      default:
        rb_bug("gc_is_moveable_obj: unreachable (%d)", (int)BUILTIN_TYPE(obj));
        break;
    }

    return FALSE;
}

static VALUE
gc_move(rb_objspace_t *objspace, VALUE scan, VALUE free)
{
    int marked;
    int wb_unprotected;
    int uncollectible;
    int marking;
    RVALUE *dest = (RVALUE *)free;
    RVALUE *src = (RVALUE *)scan;

    gc_report(4, objspace, "Moving object: %p -> %p\n", (void*)scan, (void *)free);

    GC_ASSERT(BUILTIN_TYPE(scan) != T_NONE);
    GC_ASSERT(!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(free), free));

    /* Save off bits for current object. */
    marked = rb_objspace_marked_object_p((VALUE)src);
    wb_unprotected = RVALUE_WB_UNPROTECTED((VALUE)src);
    uncollectible = RVALUE_UNCOLLECTIBLE((VALUE)src);
    marking = RVALUE_MARKING((VALUE)src);

    /* Clear bits for eventual T_MOVED */
    CLEAR_IN_BITMAP(GET_HEAP_MARK_BITS((VALUE)src), (VALUE)src);
    CLEAR_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS((VALUE)src), (VALUE)src);
    CLEAR_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS((VALUE)src), (VALUE)src);
    CLEAR_IN_BITMAP(GET_HEAP_MARKING_BITS((VALUE)src), (VALUE)src);

    if (FL_TEST((VALUE)src, FL_EXIVAR)) {
        /* Same deal as below. Generic ivars are held in st tables.
         * Resizing the table could cause a GC to happen and we can't allow it */
        VALUE already_disabled = rb_gc_disable_no_rest();
        rb_mv_generic_ivar((VALUE)src, (VALUE)dest);
        if (already_disabled == Qfalse) rb_objspace_gc_enable(objspace);
    }

    st_data_t srcid = (st_data_t)src, id;

    /* If the source object's object_id has been seen, we need to update
     * the object to object id mapping. */
    if (st_lookup(objspace->obj_to_id_tbl, srcid, &id)) {
        gc_report(4, objspace, "Moving object with seen id: %p -> %p\n", (void *)src, (void *)dest);
        /* inserting in the st table can cause the GC to run. We need to
         * prevent re-entry in to the GC since `gc_move` is running in the GC,
         * so temporarily disable the GC around the st table mutation */
        VALUE already_disabled = rb_gc_disable_no_rest();
        st_delete(objspace->obj_to_id_tbl, &srcid, 0);
        st_insert(objspace->obj_to_id_tbl, (st_data_t)dest, id);
        if (already_disabled == Qfalse) rb_objspace_gc_enable(objspace);
    }

    /* Move the object */
    memcpy(dest, src, sizeof(RVALUE));
    memset(src, 0, sizeof(RVALUE));

    /* Set bits for object in new location */
    if (marking) {
        MARK_IN_BITMAP(GET_HEAP_MARKING_BITS((VALUE)dest), (VALUE)dest);
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_MARKING_BITS((VALUE)dest), (VALUE)dest);
    }

    if (marked) {
        MARK_IN_BITMAP(GET_HEAP_MARK_BITS((VALUE)dest), (VALUE)dest);
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_MARK_BITS((VALUE)dest), (VALUE)dest);
    }

    if (wb_unprotected) {
        MARK_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS((VALUE)dest), (VALUE)dest);
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS((VALUE)dest), (VALUE)dest);
    }

    if (uncollectible) {
        MARK_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS((VALUE)dest), (VALUE)dest);
    }
    else {
        CLEAR_IN_BITMAP(GET_HEAP_UNCOLLECTIBLE_BITS((VALUE)dest), (VALUE)dest);
    }

    /* Assign forwarding address */
    src->as.moved.flags = T_MOVED;
    src->as.moved.dummy = Qundef;
    src->as.moved.destination = (VALUE)dest;
    GC_ASSERT(BUILTIN_TYPE((VALUE)dest) != T_NONE);

    return (VALUE)src;
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
gc_sort_heap_by_empty_slots(rb_objspace_t *objspace)
{
    size_t total_pages = heap_eden->total_pages;
    size_t size = size_mul_or_raise(total_pages, sizeof(struct heap_page *), rb_eRuntimeError);
    struct heap_page *page = 0, **page_list = malloc(size);
    size_t i = 0;

    list_for_each(&heap_eden->pages, page, page_node) {
        page_list[i++] = page;
        assert(page != NULL);
    }
    assert(total_pages > 0);
    assert((size_t)i == total_pages);

    /* Sort the heap so "filled pages" are first. `heap_add_page` adds to the
     * head of the list, so empty pages will end up at the start of the heap */
    ruby_qsort(page_list, total_pages, sizeof(struct heap_page *), compare_free_slots, NULL);

    /* Reset the eden heap */
    list_head_init(&objspace->eden_heap.pages);
    heap_eden->free_pages = NULL;

    for (i = 0; i < total_pages; i++) {
        list_add(&heap_eden->pages, &page_list[i]->page_node);
        if (page_list[i]->free_slots != 0) {
            heap_add_freepage(heap_eden, page_list[i]);
        }
    }

    free(page_list);
}

static void
gc_ref_update_array(rb_objspace_t * objspace, VALUE v)
{
    long i, len;

    if (FL_TEST(v, ELTS_SHARED))
        return;

    len = RARRAY_LEN(v);
    if (len > 0) {
        VALUE *ptr = (VALUE *)RARRAY_CONST_PTR_TRANSIENT(v);
        for (i = 0; i < len; i++) {
            UPDATE_IF_MOVED(objspace, ptr[i]);
        }
    }
}

static void
gc_ref_update_object(rb_objspace_t * objspace, VALUE v)
{
    VALUE *ptr = ROBJECT_IVPTR(v);

    uint32_t i, len = ROBJECT_NUMIV(v);
    for (i = 0; i < len; i++) {
        UPDATE_IF_MOVED(objspace, ptr[i]);
    }
}

static int
hash_replace_ref(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    rb_objspace_t *objspace = (rb_objspace_t *)argp;

    if (gc_object_moved_p(objspace, (VALUE)*key)) {
        *key = rb_gc_location((VALUE)*key);
    }

    if (gc_object_moved_p(objspace, (VALUE)*value)) {
        *value = rb_gc_location((VALUE)*value);
    }

    return ST_CONTINUE;
}

static int
hash_foreach_replace(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    rb_objspace_t *objspace;

    objspace = (rb_objspace_t *)argp;

    if (gc_object_moved_p(objspace, (VALUE)key)) {
        return ST_REPLACE;
    }

    if (gc_object_moved_p(objspace, (VALUE)value)) {
        return ST_REPLACE;
    }
    return ST_CONTINUE;
}

static int
hash_replace_ref_value(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    rb_objspace_t *objspace = (rb_objspace_t *)argp;

    if (gc_object_moved_p(objspace, (VALUE)*value)) {
        *value = rb_gc_location((VALUE)*value);
    }

    return ST_CONTINUE;
}

static int
hash_foreach_replace_value(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    rb_objspace_t *objspace;

    objspace = (rb_objspace_t *)argp;

    if (gc_object_moved_p(objspace, (VALUE)value)) {
        return ST_REPLACE;
    }
    return ST_CONTINUE;
}

static void
gc_update_tbl_refs(rb_objspace_t * objspace, st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;

    if (st_foreach_with_replace(tbl, hash_foreach_replace_value, hash_replace_ref_value, (st_data_t)objspace)) {
        rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

static void
gc_update_table_refs(rb_objspace_t * objspace, st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;

    if (st_foreach_with_replace(tbl, hash_foreach_replace, hash_replace_ref, (st_data_t)objspace)) {
        rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

/* Update MOVED references in an st_table */
void
rb_gc_update_tbl_refs(st_table *ptr)
{
    rb_objspace_t *objspace = &rb_objspace;
    gc_update_table_refs(objspace, ptr);
}

static void
gc_ref_update_hash(rb_objspace_t * objspace, VALUE v)
{
    rb_hash_stlike_foreach_with_replace(v, hash_foreach_replace, hash_replace_ref, (st_data_t)objspace);
}

static void
gc_ref_update_method_entry(rb_objspace_t *objspace, rb_method_entry_t *me)
{
    rb_method_definition_t *def = me->def;

    UPDATE_IF_MOVED(objspace, me->owner);
    UPDATE_IF_MOVED(objspace, me->defined_class);

    if (def) {
        switch (def->type) {
          case VM_METHOD_TYPE_ISEQ:
            if (def->body.iseq.iseqptr) {
                TYPED_UPDATE_IF_MOVED(objspace, rb_iseq_t *, def->body.iseq.iseqptr);
            }
            TYPED_UPDATE_IF_MOVED(objspace, rb_cref_t *, def->body.iseq.cref);
            break;
          case VM_METHOD_TYPE_ATTRSET:
          case VM_METHOD_TYPE_IVAR:
            UPDATE_IF_MOVED(objspace, def->body.attr.location);
            break;
          case VM_METHOD_TYPE_BMETHOD:
            UPDATE_IF_MOVED(objspace, def->body.bmethod.proc);
            break;
          case VM_METHOD_TYPE_ALIAS:
            TYPED_UPDATE_IF_MOVED(objspace, struct rb_method_entry_struct *, def->body.alias.original_me);
            return;
          case VM_METHOD_TYPE_REFINED:
            TYPED_UPDATE_IF_MOVED(objspace, struct rb_method_entry_struct *, def->body.refined.orig_me);
            UPDATE_IF_MOVED(objspace, def->body.refined.owner);
            break;
          case VM_METHOD_TYPE_CFUNC:
          case VM_METHOD_TYPE_ZSUPER:
          case VM_METHOD_TYPE_MISSING:
          case VM_METHOD_TYPE_OPTIMIZED:
          case VM_METHOD_TYPE_UNDEF:
          case VM_METHOD_TYPE_NOTIMPLEMENTED:
            break;
        }
    }
}

static void
gc_update_values(rb_objspace_t *objspace, long n, VALUE *values)
{
    long i;

    for (i=0; i<n; i++) {
        UPDATE_IF_MOVED(objspace, values[i]);
    }
}

static void
gc_ref_update_imemo(rb_objspace_t *objspace, VALUE obj)
{
    switch (imemo_type(obj)) {
      case imemo_env:
        {
            rb_env_t *env = (rb_env_t *)obj;
            TYPED_UPDATE_IF_MOVED(objspace, rb_iseq_t *, env->iseq);
            UPDATE_IF_MOVED(objspace, env->ep[VM_ENV_DATA_INDEX_ENV]);
            gc_update_values(objspace, (long)env->env_size, (VALUE *)env->env);
        }
        break;
      case imemo_cref:
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.cref.klass);
        TYPED_UPDATE_IF_MOVED(objspace, struct rb_cref_struct *, RANY(obj)->as.imemo.cref.next);
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.cref.refinements);
        break;
      case imemo_svar:
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.svar.cref_or_me);
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.svar.lastline);
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.svar.backref);
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.svar.others);
        break;
      case imemo_throw_data:
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.throw_data.throw_obj);
        break;
      case imemo_ifunc:
        break;
      case imemo_memo:
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.memo.v1);
        UPDATE_IF_MOVED(objspace, RANY(obj)->as.imemo.memo.v2);
        break;
      case imemo_ment:
        gc_ref_update_method_entry(objspace, &RANY(obj)->as.imemo.ment);
        break;
      case imemo_iseq:
        rb_iseq_update_references((rb_iseq_t *)obj);
        break;
      case imemo_ast:
        rb_ast_update_references((rb_ast_t *)obj);
        break;
      case imemo_callcache:
        {
            const struct rb_callcache *cc = (const struct rb_callcache *)obj;
            if (cc->klass) {
                UPDATE_IF_MOVED(objspace, cc->klass);
                if (!is_live_object(objspace, cc->klass)) {
                    *((VALUE *)(&cc->klass)) = (VALUE)0;
                }
            }

            if (cc->cme_) {
                TYPED_UPDATE_IF_MOVED(objspace, struct rb_callable_method_entry_struct *, cc->cme_);
                if (!is_live_object(objspace, (VALUE)cc->cme_)) {
                    *((struct rb_callable_method_entry_struct **)(&cc->cme_)) = (struct rb_callable_method_entry_struct *)0;
                }
            }
        }
        break;
      case imemo_parser_strterm:
      case imemo_tmpbuf:
      case imemo_callinfo:
        break;
      default:
        rb_bug("not reachable %d", imemo_type(obj));
        break;
    }
}

static enum rb_id_table_iterator_result
check_id_table_move(ID id, VALUE value, void *data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;

    if (gc_object_moved_p(objspace, (VALUE)value)) {
        return ID_TABLE_REPLACE;
    }

    return ID_TABLE_CONTINUE;
}

/* Returns the new location of an object, if it moved.  Otherwise returns
 * the existing location. */
VALUE
rb_gc_location(VALUE value)
{

    VALUE destination;

    if (!SPECIAL_CONST_P(value)) {
        void *poisoned = asan_poisoned_object_p(value);
        asan_unpoison_object(value, false);

        if (BUILTIN_TYPE(value) == T_MOVED) {
            destination = (VALUE)RMOVED(value)->destination;
            GC_ASSERT(BUILTIN_TYPE(destination) != T_NONE);
        }
        else {
            destination = value;
        }

        /* Re-poison slot if it's not the one we want */
        if (poisoned) {
            GC_ASSERT(BUILTIN_TYPE(value) == T_NONE);
            asan_poison_object(value);
        }
    }
    else {
        destination = value;
    }

    return destination;
}

static enum rb_id_table_iterator_result
update_id_table(ID *key, VALUE * value, void *data, int existing)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;

    if (gc_object_moved_p(objspace, (VALUE)*value)) {
        *value = rb_gc_location((VALUE)*value);
    }

    return ID_TABLE_CONTINUE;
}

static void
update_m_tbl(rb_objspace_t *objspace, struct rb_id_table *tbl)
{
    if (tbl) {
        rb_id_table_foreach_with_replace(tbl, check_id_table_move, update_id_table, objspace);
    }
}

static enum rb_id_table_iterator_result
update_cc_tbl_i(ID id, VALUE ccs_ptr, void *data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;
    struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)ccs_ptr;
    VM_ASSERT(vm_ccs_p(ccs));

    if (gc_object_moved_p(objspace, (VALUE)ccs->cme)) {
        ccs->cme = (const rb_callable_method_entry_t *)rb_gc_location((VALUE)ccs->cme);
    }

    for (int i=0; i<ccs->len; i++) {
        if (gc_object_moved_p(objspace, (VALUE)ccs->entries[i].ci)) {
            ccs->entries[i].ci = (struct rb_callinfo *)rb_gc_location((VALUE)ccs->entries[i].ci);
        }
        if (gc_object_moved_p(objspace, (VALUE)ccs->entries[i].cc)) {
            ccs->entries[i].cc = (struct rb_callcache *)rb_gc_location((VALUE)ccs->entries[i].cc);
        }
    }

    // do not replace
    return ID_TABLE_CONTINUE;
}

static void
update_cc_tbl(rb_objspace_t *objspace, VALUE klass)
{
    struct rb_id_table *tbl = RCLASS_CC_TBL(klass);
    if (tbl) {
        rb_id_table_foreach_with_replace(tbl, update_cc_tbl_i, 0, objspace);
    }
}

static enum rb_id_table_iterator_result
update_const_table(VALUE value, void *data)
{
    rb_const_entry_t *ce = (rb_const_entry_t *)value;
    rb_objspace_t * objspace = (rb_objspace_t *)data;

    if (gc_object_moved_p(objspace, ce->value)) {
        ce->value = rb_gc_location(ce->value);
    }

    if (gc_object_moved_p(objspace, ce->file)) {
        ce->file = rb_gc_location(ce->file);
    }

    return ID_TABLE_CONTINUE;
}

static void
update_const_tbl(rb_objspace_t *objspace, struct rb_id_table *tbl)
{
    if (!tbl) return;
    rb_id_table_foreach_values(tbl, update_const_table, objspace);
}

static void
update_subclass_entries(rb_objspace_t *objspace, rb_subclass_entry_t *entry)
{
    while (entry) {
        UPDATE_IF_MOVED(objspace, entry->klass);
        entry = entry->next;
    }
}

static int
update_iv_index_tbl_i(st_data_t key, st_data_t value, st_data_t arg)
{
    rb_objspace_t *objspace = (rb_objspace_t *)arg;
    struct rb_iv_index_tbl_entry *ent = (struct rb_iv_index_tbl_entry *)value;
    UPDATE_IF_MOVED(objspace, ent->class_value);
    return ST_CONTINUE;
}

static void
update_class_ext(rb_objspace_t *objspace, rb_classext_t *ext)
{
    UPDATE_IF_MOVED(objspace, ext->origin_);
    UPDATE_IF_MOVED(objspace, ext->refined_class);
    update_subclass_entries(objspace, ext->subclasses);

    // ext->iv_index_tbl
    if (ext->iv_index_tbl) {
        st_foreach(ext->iv_index_tbl, update_iv_index_tbl_i, (st_data_t)objspace);
    }
}

static void
gc_update_object_references(rb_objspace_t *objspace, VALUE obj)
{
    RVALUE *any = RANY(obj);

    gc_report(4, objspace, "update-refs: %p ->\n", (void *)obj);

    switch (BUILTIN_TYPE(obj)) {
      case T_CLASS:
      case T_MODULE:
        if (RCLASS_SUPER((VALUE)obj)) {
            UPDATE_IF_MOVED(objspace, RCLASS(obj)->super);
        }
        if (!RCLASS_EXT(obj)) break;
        update_m_tbl(objspace, RCLASS_M_TBL(obj));
        update_cc_tbl(objspace, obj);

        gc_update_tbl_refs(objspace, RCLASS_IV_TBL(obj));

        update_class_ext(objspace, RCLASS_EXT(obj));
        update_const_tbl(objspace, RCLASS_CONST_TBL(obj));
        break;

      case T_ICLASS:
        if (FL_TEST(obj, RICLASS_IS_ORIGIN) &&
                !FL_TEST(obj, RICLASS_ORIGIN_SHARED_MTBL)) {
            update_m_tbl(objspace, RCLASS_M_TBL(obj));
        }
        if (RCLASS_SUPER((VALUE)obj)) {
            UPDATE_IF_MOVED(objspace, RCLASS(obj)->super);
        }
        if (!RCLASS_EXT(obj)) break;
        if (RCLASS_IV_TBL(obj)) {
            gc_update_tbl_refs(objspace, RCLASS_IV_TBL(obj));
        }
        update_class_ext(objspace, RCLASS_EXT(obj));
        update_m_tbl(objspace, RCLASS_CALLABLE_M_TBL(obj));
        update_cc_tbl(objspace, obj);
        break;

      case T_IMEMO:
        gc_ref_update_imemo(objspace, obj);
        return;

      case T_NIL:
      case T_FIXNUM:
      case T_NODE:
      case T_MOVED:
      case T_NONE:
        /* These can't move */
        return;

      case T_ARRAY:
        if (FL_TEST(obj, ELTS_SHARED)) {
            UPDATE_IF_MOVED(objspace, any->as.array.as.heap.aux.shared_root);
        }
        else {
            gc_ref_update_array(objspace, obj);
        }
        break;

      case T_HASH:
        gc_ref_update_hash(objspace, obj);
        UPDATE_IF_MOVED(objspace, any->as.hash.ifnone);
        break;

      case T_STRING:
        if (STR_SHARED_P(obj)) {
            UPDATE_IF_MOVED(objspace, any->as.string.as.heap.aux.shared);
        }
        break;

      case T_DATA:
        /* Call the compaction callback, if it exists */
        {
            void *const ptr = DATA_PTR(obj);
            if (ptr) {
                if (RTYPEDDATA_P(obj)) {
                    RUBY_DATA_FUNC compact_func = any->as.typeddata.type->function.dcompact;
                    if (compact_func) (*compact_func)(ptr);
                }
            }
        }
        break;

      case T_OBJECT:
        gc_ref_update_object(objspace, obj);
        break;

      case T_FILE:
        if (any->as.file.fptr) {
            UPDATE_IF_MOVED(objspace, any->as.file.fptr->self);
            UPDATE_IF_MOVED(objspace, any->as.file.fptr->pathv);
            UPDATE_IF_MOVED(objspace, any->as.file.fptr->tied_io_for_writing);
            UPDATE_IF_MOVED(objspace, any->as.file.fptr->writeconv_asciicompat);
            UPDATE_IF_MOVED(objspace, any->as.file.fptr->writeconv_pre_ecopts);
            UPDATE_IF_MOVED(objspace, any->as.file.fptr->encs.ecopts);
            UPDATE_IF_MOVED(objspace, any->as.file.fptr->write_lock);
        }
        break;
      case T_REGEXP:
        UPDATE_IF_MOVED(objspace, any->as.regexp.src);
        break;

      case T_SYMBOL:
        if (DYNAMIC_SYM_P((VALUE)any)) {
            UPDATE_IF_MOVED(objspace, RSYMBOL(any)->fstr);
        }
        break;

      case T_FLOAT:
      case T_BIGNUM:
        break;

      case T_MATCH:
        UPDATE_IF_MOVED(objspace, any->as.match.regexp);

        if (any->as.match.str) {
            UPDATE_IF_MOVED(objspace, any->as.match.str);
        }
        break;

      case T_RATIONAL:
        UPDATE_IF_MOVED(objspace, any->as.rational.num);
        UPDATE_IF_MOVED(objspace, any->as.rational.den);
        break;

      case T_COMPLEX:
        UPDATE_IF_MOVED(objspace, any->as.complex.real);
        UPDATE_IF_MOVED(objspace, any->as.complex.imag);

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
#if GC_DEBUG
        rb_gcdebug_print_obj_condition((VALUE)obj);
        rb_obj_info_dump(obj);
        rb_bug("unreachable");
#endif
        break;

    }

    UPDATE_IF_MOVED(objspace, RBASIC(obj)->klass);

    gc_report(4, objspace, "update-refs: %p <-\n", (void *)obj);
}

static int
gc_ref_update(void *vstart, void *vend, size_t stride, rb_objspace_t * objspace, struct heap_page *page)
{
    VALUE v = (VALUE)vstart;
    asan_unpoison_memory_region(&page->freelist, sizeof(RVALUE*), false);
    asan_poison_memory_region(&page->freelist, sizeof(RVALUE*));
    page->flags.has_uncollectible_shady_objects = FALSE;
    page->flags.has_remembered_objects = FALSE;

    /* For each object on the page */
    for (; v != (VALUE)vend; v += stride) {
        void *poisoned = asan_poisoned_object_p(v);
        asan_unpoison_object(v, false);

        switch (BUILTIN_TYPE(v)) {
          case T_NONE:
          case T_MOVED:
          case T_ZOMBIE:
            break;
          default:
            if (RVALUE_WB_UNPROTECTED(v)) {
                page->flags.has_uncollectible_shady_objects = TRUE;
            }
            if (RVALUE_PAGE_MARKING(page, v)) {
                page->flags.has_remembered_objects = TRUE;
            }
            if (page->flags.before_sweep) {
                if (RVALUE_MARKED(v)) {
                    gc_update_object_references(objspace, v);
                }
            } else {
                gc_update_object_references(objspace, v);
            }
        }

        if (poisoned) {
            asan_poison_object(v);
        }
    }

    return 0;
}

extern rb_symbols_t ruby_global_symbols;
#define global_symbols ruby_global_symbols

static void
gc_update_references(rb_objspace_t * objspace, rb_heap_t *heap)
{
    rb_execution_context_t *ec = GET_EC();
    rb_vm_t *vm = rb_ec_vm_ptr(ec);
    short should_set_mark_bits = 1;

    struct heap_page *page = NULL;

    list_for_each(&heap->pages, page, page_node) {
        gc_ref_update(page->start, page->start + page->total_slots, sizeof(RVALUE), objspace, page);
        if (page == heap->sweeping_page) {
            should_set_mark_bits = 0;
        }
        if (should_set_mark_bits) {
            gc_setup_mark_bits(page);
        }
    }
    rb_vm_update_references(vm);
    rb_transient_heap_update_references();
    rb_gc_update_global_tbl();
    global_symbols.ids = rb_gc_location(global_symbols.ids);
    global_symbols.dsymbol_fstr_hash = rb_gc_location(global_symbols.dsymbol_fstr_hash);
    gc_update_tbl_refs(objspace, objspace->obj_to_id_tbl);
    gc_update_table_refs(objspace, objspace->id_to_obj_tbl);
    gc_update_table_refs(objspace, global_symbols.str_sym);
    gc_update_table_refs(objspace, finalizer_table);
}

static VALUE type_sym(size_t type);

static VALUE
gc_compact_stats(rb_execution_context_t *ec, VALUE self)
{
    size_t i;
    rb_objspace_t *objspace = &rb_objspace;
    VALUE h = rb_hash_new();
    VALUE considered = rb_hash_new();
    VALUE moved = rb_hash_new();

    for (i=0; i<T_MASK; i++) {
        if(objspace->rcompactor.considered_count_table[i]) {
            rb_hash_aset(considered, type_sym(i), SIZET2NUM(objspace->rcompactor.considered_count_table[i]));
        }

        if(objspace->rcompactor.moved_count_table[i]) {
            rb_hash_aset(moved, type_sym(i), SIZET2NUM(objspace->rcompactor.moved_count_table[i]));
        }
    }

    rb_hash_aset(h, ID2SYM(rb_intern("considered")), considered);
    rb_hash_aset(h, ID2SYM(rb_intern("moved")), moved);

    return h;
}

static void
root_obj_check_moved_i(const char *category, VALUE obj, void *data)
{
    if (gc_object_moved_p(&rb_objspace, obj)) {
        rb_bug("ROOT %s points to MOVED: %p -> %s\n", category, (void *)obj, obj_info(rb_gc_location(obj)));
    }
}

static void
reachable_object_check_moved_i(VALUE ref, void *data)
{
    VALUE parent = (VALUE)data;
    if (gc_object_moved_p(&rb_objspace, ref)) {
        rb_bug("Object %s points to MOVED: %p -> %s\n", obj_info(parent), (void *)ref, obj_info(rb_gc_location(ref)));
    }
}

static int
heap_check_moved_i(void *vstart, void *vend, size_t stride, void *data)
{
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        if (gc_object_moved_p(&rb_objspace, v)) {
            /* Moved object still on the heap, something may have a reference. */
        }
        else {
            void *poisoned = asan_poisoned_object_p(v);
            asan_unpoison_object(v, false);

            switch (BUILTIN_TYPE(v)) {
              case T_NONE:
              case T_ZOMBIE:
                break;
              default:
                if (!rb_objspace_garbage_object_p(v)) {
                    rb_objspace_reachable_objects_from(v, reachable_object_check_moved_i, (void *)v);
                }
            }

            if (poisoned) {
                GC_ASSERT(BUILTIN_TYPE(v) == T_NONE);
                asan_poison_object(v);
            }
        }
    }

    return 0;
}

static VALUE
gc_compact(rb_execution_context_t *ec, VALUE self)
{
    /* Clear the heap. */
    gc_start_internal(ec, self, Qtrue, Qtrue, Qtrue, Qfalse);

    /* At this point, all references are live and the mutator is not allowed
     * to run, so we don't need a read barrier. */
    gc_start_internal(ec, self, Qtrue, Qtrue, Qtrue, Qtrue);

    return gc_compact_stats(ec, self);
}

static VALUE
gc_verify_compaction_references(rb_execution_context_t *ec, VALUE self, VALUE double_heap, VALUE toward_empty)
{
    rb_objspace_t *objspace = &rb_objspace;

    /* Clear the heap. */
    gc_start_internal(ec, self, Qtrue, Qtrue, Qtrue, Qfalse);

    RB_VM_LOCK_ENTER();
    {
        gc_rest(objspace);

        if (RTEST(double_heap)) {
            heap_add_pages(objspace, heap_eden, heap_allocated_pages);
        }

        if (RTEST(toward_empty)) {
            gc_sort_heap_by_empty_slots(objspace);
        }
    }
    RB_VM_LOCK_LEAVE();

    gc_start_internal(ec, self, Qtrue, Qtrue, Qtrue, Qtrue);

    objspace_reachable_objects_from_root(objspace, root_obj_check_moved_i, NULL);
    objspace_each_objects(objspace, heap_check_moved_i, NULL);

    return gc_compact_stats(ec, self);
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
    rb_objspace_t *objspace = &rb_objspace;
    int reason = GPR_DEFAULT_REASON;
    garbage_collect(objspace, reason);
}

int
rb_during_gc(void)
{
    rb_objspace_t *objspace = &rb_objspace;
    return during_gc;
}

#if RGENGC_PROFILE >= 2

static const char *type_name(int type, VALUE obj);

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
rb_gc_count(void)
{
    return rb_objspace.profile.count;
}

static VALUE
gc_count(rb_execution_context_t *ec, VALUE self)
{
    return SIZET2NUM(rb_gc_count());
}

static VALUE
gc_info_decode(rb_objspace_t *objspace, const VALUE hash_or_key, const int orig_flags)
{
    static VALUE sym_major_by = Qnil, sym_gc_by, sym_immediate_sweep, sym_have_finalizer, sym_state;
    static VALUE sym_nofree, sym_oldgen, sym_shady, sym_force, sym_stress;
#if RGENGC_ESTIMATE_OLDMALLOC
    static VALUE sym_oldmalloc;
#endif
    static VALUE sym_newobj, sym_malloc, sym_method, sym_capi;
    static VALUE sym_none, sym_marking, sym_sweeping;
    VALUE hash = Qnil, key = Qnil;
    VALUE major_by;
    VALUE flags = orig_flags ? orig_flags : objspace->profile.latest_gc_info;

    if (SYMBOL_P(hash_or_key)) {
        key = hash_or_key;
    }
    else if (RB_TYPE_P(hash_or_key, T_HASH)) {
        hash = hash_or_key;
    }
    else {
        rb_raise(rb_eTypeError, "non-hash or symbol given");
    }

    if (sym_major_by == Qnil) {
#define S(s) sym_##s = ID2SYM(rb_intern_const(#s))
        S(major_by);
        S(gc_by);
        S(immediate_sweep);
        S(have_finalizer);
        S(state);

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
#undef SET

    if (!NIL_P(key)) {/* matched key should return above */
        rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(key));
    }

    return hash;
}

VALUE
rb_gc_latest_gc_info(VALUE key)
{
    rb_objspace_t *objspace = &rb_objspace;
    return gc_info_decode(objspace, key, 0);
}

static VALUE
gc_latest_gc_info(rb_execution_context_t *ec, VALUE self, VALUE arg)
{
    rb_objspace_t *objspace = &rb_objspace;

    if (NIL_P(arg)) {
        arg = rb_hash_new();
    }
    else if (!SYMBOL_P(arg) && !RB_TYPE_P(arg, T_HASH)) {
        rb_raise(rb_eTypeError, "non-hash or symbol given");
    }

    return gc_info_decode(objspace, arg, 0);
}

enum gc_stat_sym {
    gc_stat_sym_count,
    gc_stat_sym_heap_allocated_pages,
    gc_stat_sym_heap_sorted_length,
    gc_stat_sym_heap_allocatable_pages,
    gc_stat_sym_heap_available_slots,
    gc_stat_sym_heap_live_slots,
    gc_stat_sym_heap_free_slots,
    gc_stat_sym_heap_final_slots,
    gc_stat_sym_heap_marked_slots,
    gc_stat_sym_heap_eden_pages,
    gc_stat_sym_heap_tomb_pages,
    gc_stat_sym_total_allocated_pages,
    gc_stat_sym_total_freed_pages,
    gc_stat_sym_total_allocated_objects,
    gc_stat_sym_total_freed_objects,
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

enum gc_stat_compat_sym {
    gc_stat_compat_sym_gc_stat_heap_used,
    gc_stat_compat_sym_heap_eden_page_length,
    gc_stat_compat_sym_heap_tomb_page_length,
    gc_stat_compat_sym_heap_increment,
    gc_stat_compat_sym_heap_length,
    gc_stat_compat_sym_heap_live_slot,
    gc_stat_compat_sym_heap_free_slot,
    gc_stat_compat_sym_heap_final_slot,
    gc_stat_compat_sym_heap_swept_slot,
    gc_stat_compat_sym_remembered_shady_object,
    gc_stat_compat_sym_remembered_shady_object_limit,
    gc_stat_compat_sym_old_object,
    gc_stat_compat_sym_old_object_limit,
    gc_stat_compat_sym_total_allocated_object,
    gc_stat_compat_sym_total_freed_object,
    gc_stat_compat_sym_malloc_increase,
    gc_stat_compat_sym_malloc_limit,
#if RGENGC_ESTIMATE_OLDMALLOC
    gc_stat_compat_sym_oldmalloc_increase,
    gc_stat_compat_sym_oldmalloc_limit,
#endif
    gc_stat_compat_sym_last
};

static VALUE gc_stat_symbols[gc_stat_sym_last];
static VALUE gc_stat_compat_symbols[gc_stat_compat_sym_last];
static VALUE gc_stat_compat_table;

static void
setup_gc_stat_symbols(void)
{
    if (gc_stat_symbols[0] == 0) {
#define S(s) gc_stat_symbols[gc_stat_sym_##s] = ID2SYM(rb_intern_const(#s))
	S(count);
	S(heap_allocated_pages);
	S(heap_sorted_length);
	S(heap_allocatable_pages);
	S(heap_available_slots);
	S(heap_live_slots);
	S(heap_free_slots);
	S(heap_final_slots);
	S(heap_marked_slots);
	S(heap_eden_pages);
	S(heap_tomb_pages);
	S(total_allocated_pages);
	S(total_freed_pages);
	S(total_allocated_objects);
	S(total_freed_objects);
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
#define S(s) gc_stat_compat_symbols[gc_stat_compat_sym_##s] = ID2SYM(rb_intern_const(#s))
	S(gc_stat_heap_used);
	S(heap_eden_page_length);
	S(heap_tomb_page_length);
	S(heap_increment);
	S(heap_length);
	S(heap_live_slot);
	S(heap_free_slot);
	S(heap_final_slot);
	S(heap_swept_slot);
	S(remembered_shady_object);
	S(remembered_shady_object_limit);
	S(old_object);
	S(old_object_limit);
	S(total_allocated_object);
	S(total_freed_object);
	S(malloc_increase);
	S(malloc_limit);
#if RGENGC_ESTIMATE_OLDMALLOC
	S(oldmalloc_increase);
	S(oldmalloc_limit);
#endif
#undef S

	{
	    VALUE table = gc_stat_compat_table = rb_hash_new();
	    rb_obj_hide(table);
	    rb_gc_register_mark_object(table);

	    /* compatibility layer for Ruby 2.1 */
#define OLD_SYM(s) gc_stat_compat_symbols[gc_stat_compat_sym_##s]
#define NEW_SYM(s) gc_stat_symbols[gc_stat_sym_##s]
	    rb_hash_aset(table, OLD_SYM(gc_stat_heap_used), NEW_SYM(heap_allocated_pages));
	    rb_hash_aset(table, OLD_SYM(heap_eden_page_length), NEW_SYM(heap_eden_pages));
	    rb_hash_aset(table, OLD_SYM(heap_tomb_page_length), NEW_SYM(heap_tomb_pages));
	    rb_hash_aset(table, OLD_SYM(heap_increment), NEW_SYM(heap_allocatable_pages));
	    rb_hash_aset(table, OLD_SYM(heap_length), NEW_SYM(heap_sorted_length));
	    rb_hash_aset(table, OLD_SYM(heap_live_slot), NEW_SYM(heap_live_slots));
	    rb_hash_aset(table, OLD_SYM(heap_free_slot), NEW_SYM(heap_free_slots));
	    rb_hash_aset(table, OLD_SYM(heap_final_slot), NEW_SYM(heap_final_slots));
	    rb_hash_aset(table, OLD_SYM(remembered_shady_object), NEW_SYM(remembered_wb_unprotected_objects));
	    rb_hash_aset(table, OLD_SYM(remembered_shady_object_limit), NEW_SYM(remembered_wb_unprotected_objects_limit));
	    rb_hash_aset(table, OLD_SYM(old_object), NEW_SYM(old_objects));
	    rb_hash_aset(table, OLD_SYM(old_object_limit), NEW_SYM(old_objects_limit));
	    rb_hash_aset(table, OLD_SYM(total_allocated_object), NEW_SYM(total_allocated_objects));
	    rb_hash_aset(table, OLD_SYM(total_freed_object), NEW_SYM(total_freed_objects));
	    rb_hash_aset(table, OLD_SYM(malloc_increase), NEW_SYM(malloc_increase_bytes));
	    rb_hash_aset(table, OLD_SYM(malloc_limit), NEW_SYM(malloc_increase_bytes_limit));
#if RGENGC_ESTIMATE_OLDMALLOC
	    rb_hash_aset(table, OLD_SYM(oldmalloc_increase), NEW_SYM(oldmalloc_increase_bytes));
	    rb_hash_aset(table, OLD_SYM(oldmalloc_limit), NEW_SYM(oldmalloc_increase_bytes_limit));
#endif
#undef OLD_SYM
#undef NEW_SYM
	    rb_obj_freeze(table);
	}
    }
}

static VALUE
compat_key(VALUE key)
{
    VALUE new_key = rb_hash_lookup(gc_stat_compat_table, key);

    if (!NIL_P(new_key)) {
	static int warned = 0;
	if (warned == 0) {
	    rb_warn("GC.stat keys were changed from Ruby 2.1. "
		    "In this case, you refer to obsolete `%"PRIsVALUE"' (new key is `%"PRIsVALUE"'). "
		    "Please check <https://bugs.ruby-lang.org/issues/9924> for more information.",
		    key, new_key);
	    warned = 1;
	}
    }

    return new_key;
}

static VALUE
default_proc_for_compat_func(RB_BLOCK_CALL_FUNC_ARGLIST(hash, _))
{
    VALUE key, new_key;

    Check_Type(hash, T_HASH);
    rb_check_arity(argc, 2, 2);
    key = argv[1];

    if ((new_key = compat_key(key)) != Qnil) {
	return rb_hash_lookup(hash, new_key);
    }

    return Qnil;
}

static size_t
gc_stat_internal(VALUE hash_or_sym)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE hash = Qnil, key = Qnil;

    setup_gc_stat_symbols();

    if (RB_TYPE_P(hash_or_sym, T_HASH)) {
	hash = hash_or_sym;

	if (NIL_P(RHASH_IFNONE(hash))) {
	    static VALUE default_proc_for_compat = 0;
	    if (default_proc_for_compat == 0) { /* TODO: it should be */
		default_proc_for_compat = rb_proc_new(default_proc_for_compat_func, Qnil);
		rb_gc_register_mark_object(default_proc_for_compat);
	    }
	    rb_hash_set_default_proc(hash, default_proc_for_compat);
	}
    }
    else if (SYMBOL_P(hash_or_sym)) {
	key = hash_or_sym;
    }
    else {
	rb_raise(rb_eTypeError, "non-hash or symbol argument");
    }

#define SET(name, attr) \
    if (key == gc_stat_symbols[gc_stat_sym_##name]) \
	return attr; \
    else if (hash != Qnil) \
	rb_hash_aset(hash, gc_stat_symbols[gc_stat_sym_##name], SIZET2NUM(attr));

  again:
    SET(count, objspace->profile.count);

    /* implementation dependent counters */
    SET(heap_allocated_pages, heap_allocated_pages);
    SET(heap_sorted_length, heap_pages_sorted_length);
    SET(heap_allocatable_pages, heap_allocatable_pages);
    SET(heap_available_slots, objspace_available_slots(objspace));
    SET(heap_live_slots, objspace_live_slots(objspace));
    SET(heap_free_slots, objspace_free_slots(objspace));
    SET(heap_final_slots, heap_pages_final_slots);
    SET(heap_marked_slots, objspace->marked_slots);
    SET(heap_eden_pages, heap_eden->total_pages);
    SET(heap_tomb_pages, heap_tomb->total_pages);
    SET(total_allocated_pages, objspace->profile.total_allocated_pages);
    SET(total_freed_pages, objspace->profile.total_freed_pages);
    SET(total_allocated_objects, objspace->total_allocated_objects);
    SET(total_freed_objects, objspace->profile.total_freed_objects);
    SET(malloc_increase_bytes, malloc_increase);
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
    SET(oldmalloc_increase_bytes, objspace->rgengc.oldmalloc_increase);
    SET(oldmalloc_increase_bytes_limit, objspace->rgengc.oldmalloc_increase_limit);
#endif

#if RGENGC_PROFILE
    SET(total_generated_normal_object_count, objspace->profile.total_generated_normal_object_count);
    SET(total_generated_shady_object_count, objspace->profile.total_generated_shady_object_count);
    SET(total_shade_operation_count, objspace->profile.total_shade_operation_count);
    SET(total_promoted_count, objspace->profile.total_promoted_count);
    SET(total_remembered_normal_object_count, objspace->profile.total_remembered_normal_object_count);
    SET(total_remembered_shady_object_count, objspace->profile.total_remembered_shady_object_count);
#endif /* RGENGC_PROFILE */
#undef SET

    if (!NIL_P(key)) { /* matched key should return above */
	VALUE new_key;
	if ((new_key = compat_key(key)) != Qnil) {
	    key = new_key;
	    goto again;
	}
	rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(key));
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

    return 0;
}

static VALUE
gc_stat(rb_execution_context_t *ec, VALUE self, VALUE arg) // arg is (nil || hash || symbol)
{
    if (NIL_P(arg)) {
        arg = rb_hash_new();
    }
    else if (SYMBOL_P(arg)) {
        size_t value = gc_stat_internal(arg);
        return SIZET2NUM(value);
    }
    else if (RB_TYPE_P(arg, T_HASH)) {
        // ok
    }
    else {
        rb_raise(rb_eTypeError, "non-hash or symbol given");
    }

    gc_stat_internal(arg);
    return arg;
}

size_t
rb_gc_stat(VALUE key)
{
    if (SYMBOL_P(key)) {
	size_t value = gc_stat_internal(key);
	return value;
    }
    else {
	gc_stat_internal(key);
	return 0;
    }
}

static VALUE
gc_stress_get(rb_execution_context_t *ec, VALUE self)
{
    rb_objspace_t *objspace = &rb_objspace;
    return ruby_gc_stress_mode;
}

static void
gc_stress_set(rb_objspace_t *objspace, VALUE flag)
{
    objspace->flags.gc_stressful = RTEST(flag);
    objspace->gc_stress_mode = flag;
}

static VALUE
gc_stress_set_m(rb_execution_context_t *ec, VALUE self, VALUE flag)
{
    rb_objspace_t *objspace = &rb_objspace;
    gc_stress_set(objspace, flag);
    return flag;
}

VALUE
rb_gc_enable(void)
{
    rb_objspace_t *objspace = &rb_objspace;
    return rb_objspace_gc_enable(objspace);
}

VALUE
rb_objspace_gc_enable(rb_objspace_t *objspace)
{
    int old = dont_gc_val();

    dont_gc_off();
    return old ? Qtrue : Qfalse;
}

static VALUE
gc_enable(rb_execution_context_t *ec, VALUE _)
{
    return rb_gc_enable();
}

VALUE
rb_gc_disable_no_rest(void)
{
    rb_objspace_t *objspace = &rb_objspace;
    return gc_disable_no_rest(objspace);
}

static VALUE
gc_disable_no_rest(rb_objspace_t *objspace)
{
    int old = dont_gc_val();
    dont_gc_on();
    return old ? Qtrue : Qfalse;
}

VALUE
rb_gc_disable(void)
{
    rb_objspace_t *objspace = &rb_objspace;
    return rb_objspace_gc_disable(objspace);
}

VALUE
rb_objspace_gc_disable(rb_objspace_t *objspace)
{
    gc_rest(objspace);
    return gc_disable_no_rest(objspace);
}

static VALUE
gc_disable(rb_execution_context_t *ec, VALUE _)
{
    return rb_gc_disable();
}

static VALUE
gc_set_auto_compact(rb_execution_context_t *ec, VALUE _, VALUE v)
{
#if defined(HAVE_SYSCONF) && defined(_SC_PAGE_SIZE)
    /* If Ruby's heap pages are not a multiple of the system page size, we
     * cannot use mprotect for the read barrier, so we must disable automatic
     * compaction. */
    int pagesize;
    pagesize = (int)sysconf(_SC_PAGE_SIZE);
    if ((HEAP_PAGE_SIZE % pagesize) != 0) {
        rb_raise(rb_eNotImpError, "Automatic compaction isn't available on this platform");
    }
#endif
    ruby_enable_autocompact = RTEST(v);
    return v;
}

static VALUE
gc_get_auto_compact(rb_execution_context_t *ec, VALUE _)
{
    return ruby_enable_autocompact ? Qtrue : Qfalse;
}

static int
get_envparam_size(const char *name, size_t *default_value, size_t lower_bound)
{
    char *ptr = getenv(name);
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
    char *ptr = getenv(name);
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

static void
gc_set_initial_pages(void)
{
    size_t min_pages;
    rb_objspace_t *objspace = &rb_objspace;

    min_pages = gc_params.heap_init_slots / HEAP_PAGE_OBJ_LIMIT;
    if (min_pages > heap_eden->total_pages) {
	heap_add_pages(objspace, heap_eden, min_pages - heap_eden->total_pages);
    }
}

/*
 * GC tuning environment variables
 *
 * * RUBY_GC_HEAP_INIT_SLOTS
 *   - Initial allocation slots.
 * * RUBY_GC_HEAP_FREE_SLOTS
 *   - Prepare at least this amount of slots after GC.
 *   - Allocate slots if there are not enough slots.
 * * RUBY_GC_HEAP_GROWTH_FACTOR (new from 2.1)
 *   - Allocate slots by this factor.
 *   - (next slots number) = (current slots number) * (this factor)
 * * RUBY_GC_HEAP_GROWTH_MAX_SLOTS (new from 2.1)
 *   - Allocation rate is limited to this number of slots.
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
 *    * RUBY_HEAP_MIN_SLOTS -> RUBY_GC_HEAP_INIT_SLOTS (from 2.1)
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
ruby_gc_set_params(void)
{
    /* RUBY_GC_HEAP_FREE_SLOTS */
    if (get_envparam_size("RUBY_GC_HEAP_FREE_SLOTS", &gc_params.heap_free_slots, 0)) {
	/* ok */
    }
    else if (get_envparam_size("RUBY_FREE_MIN", &gc_params.heap_free_slots, 0)) {
	rb_warn("RUBY_FREE_MIN is obsolete. Use RUBY_GC_HEAP_FREE_SLOTS instead.");
    }

    /* RUBY_GC_HEAP_INIT_SLOTS */
    if (get_envparam_size("RUBY_GC_HEAP_INIT_SLOTS", &gc_params.heap_init_slots, 0)) {
	gc_set_initial_pages();
    }
    else if (get_envparam_size("RUBY_HEAP_MIN_SLOTS", &gc_params.heap_init_slots, 0)) {
	rb_warn("RUBY_HEAP_MIN_SLOTS is obsolete. Use RUBY_GC_HEAP_INIT_SLOTS instead.");
	gc_set_initial_pages();
    }

    get_envparam_double("RUBY_GC_HEAP_GROWTH_FACTOR", &gc_params.growth_factor, 1.0, 0.0, FALSE);
    get_envparam_size  ("RUBY_GC_HEAP_GROWTH_MAX_SLOTS", &gc_params.growth_max_slots, 0);
    get_envparam_double("RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO", &gc_params.heap_free_slots_min_ratio,
			0.0, 1.0, FALSE);
    get_envparam_double("RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO", &gc_params.heap_free_slots_max_ratio,
			gc_params.heap_free_slots_min_ratio, 1.0, FALSE);
    get_envparam_double("RUBY_GC_HEAP_FREE_SLOTS_GOAL_RATIO", &gc_params.heap_free_slots_goal_ratio,
			gc_params.heap_free_slots_min_ratio, gc_params.heap_free_slots_max_ratio, TRUE);
    get_envparam_double("RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR", &gc_params.oldobject_limit_factor, 0.0, 0.0, TRUE);

    get_envparam_size  ("RUBY_GC_MALLOC_LIMIT", &gc_params.malloc_limit_min, 0);
    get_envparam_size  ("RUBY_GC_MALLOC_LIMIT_MAX", &gc_params.malloc_limit_max, 0);
    if (!gc_params.malloc_limit_max) { /* ignore max-check if 0 */
        gc_params.malloc_limit_max = SIZE_MAX;
    }
    get_envparam_double("RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR", &gc_params.malloc_limit_growth_factor, 1.0, 0.0, FALSE);

#if RGENGC_ESTIMATE_OLDMALLOC
    if (get_envparam_size("RUBY_GC_OLDMALLOC_LIMIT", &gc_params.oldmalloc_limit_min, 0)) {
	rb_objspace_t *objspace = &rb_objspace;
	objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_min;
    }
    get_envparam_size  ("RUBY_GC_OLDMALLOC_LIMIT_MAX", &gc_params.oldmalloc_limit_max, 0);
    get_envparam_double("RUBY_GC_OLDMALLOC_LIMIT_GROWTH_FACTOR", &gc_params.oldmalloc_limit_growth_factor, 1.0, 0.0, FALSE);
#endif
}

static void
reachable_objects_from_callback(VALUE obj)
{
    rb_ractor_t *cr = GET_RACTOR();
    cr->mfd->mark_func(obj, cr->mfd->data);
}

void
rb_objspace_reachable_objects_from(VALUE obj, void (func)(VALUE, void *), void *data)
{
    rb_objspace_t *objspace = &rb_objspace;

    if (during_gc) rb_bug("rb_objspace_reachable_objects_from() is not supported while during_gc == true");

    if (is_markable_object(objspace, obj)) {
        rb_ractor_t *cr = GET_RACTOR();
        struct gc_mark_func_data_struct mfd = {
            .mark_func = func,
            .data = data,
        }, *prev_mfd = cr->mfd;

        cr->mfd = &mfd;
	gc_mark_children(objspace, obj);
        cr->mfd = prev_mfd;
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
    rb_objspace_t *objspace = &rb_objspace;
    objspace_reachable_objects_from_root(objspace, func, passing_data);
}

static void
objspace_reachable_objects_from_root(rb_objspace_t *objspace, void (func)(const char *category, VALUE, void *), void *passing_data)
{
    if (during_gc) rb_bug("objspace_reachable_objects_from_root() is not supported while during_gc == true");

    rb_ractor_t *cr = GET_RACTOR();
    struct root_objects_data data = {
        .func = func,
        .data = passing_data,
    };
    struct gc_mark_func_data_struct mfd = {
        .mark_func = root_objects_from,
        .data = &data,
    }, *prev_mfd = cr->mfd;

    cr->mfd = &mfd;
    gc_mark_roots(objspace, &data.category);
    cr->mfd = prev_mfd;
}

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

static void objspace_xfree(rb_objspace_t *objspace, void *ptr, size_t size);

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
    exit(EXIT_FAILURE);
}

void
rb_memerror(void)
{
    rb_execution_context_t *ec = GET_EC();
    rb_objspace_t *objspace = rb_objspace_of(rb_ec_vm_ptr(ec));
    VALUE exc;

    if (0) {
        // Print out pid, sleep, so you can attach debugger to see what went wrong:
        fprintf(stderr, "rb_memerror pid=%"PRI_PIDT_PREFIX"d\n", getpid());
        sleep(60);
    }

    if (during_gc) {
        // TODO: OMG!! How to implement it?
        gc_exit(objspace, "rb_memerror", NULL);
    }

    exc = nomem_error;
    if (!exc ||
	rb_ec_raised_p(ec, RAISED_NOMEMORY)) {
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

void *
rb_aligned_malloc(size_t alignment, size_t size)
{
    void *res;

#if defined __MINGW32__
    res = __mingw_aligned_malloc(size, alignment);
#elif defined _WIN32
    void *_aligned_malloc(size_t, size_t);
    res = _aligned_malloc(size, alignment);
#elif defined(HAVE_POSIX_MEMALIGN)
    if (posix_memalign(&res, alignment, size) == 0) {
        return res;
    }
    else {
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

    /* alignment must be a power of 2 */
    GC_ASSERT(((alignment - 1) & alignment) == 0);
    GC_ASSERT(alignment % sizeof(void*) == 0);
    return res;
}

static void
rb_aligned_free(void *ptr)
{
#if defined __MINGW32__
    __mingw_aligned_free(ptr);
#elif defined _WIN32
    _aligned_free(ptr);
#elif defined(HAVE_MEMALIGN) || defined(HAVE_POSIX_MEMALIGN)
    free(ptr);
#else
    free(((void**)ptr)[-1]);
#endif
}

static inline size_t
objspace_malloc_size(rb_objspace_t *objspace, void *ptr, size_t hint)
{
#ifdef HAVE_MALLOC_USABLE_SIZE
    return malloc_usable_size(ptr);
#else
    return hint;
#endif
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
	if (ATOMIC_SIZE_CAS(*var, val, val-sub) == val) break;
    }
}

static void
objspace_malloc_gc_stress(rb_objspace_t *objspace)
{
    if (ruby_gc_stressful && ruby_native_thread_p()) {
        int reason = GPR_FLAG_IMMEDIATE_MARK | GPR_FLAG_IMMEDIATE_SWEEP |
                                     GPR_FLAG_STRESS | GPR_FLAG_MALLOC;

        if (gc_stress_full_mark_after_malloc_p()) {
            reason |= GPR_FLAG_FULL_MARK;
        }
        garbage_collect_with_gvl(objspace, reason);
    }
}

static void
objspace_malloc_increase(rb_objspace_t *objspace, void *mem, size_t new_size, size_t old_size, enum memop_type type)
{
    if (new_size > old_size) {
	ATOMIC_SIZE_ADD(malloc_increase, new_size - old_size);
#if RGENGC_ESTIMATE_OLDMALLOC
	ATOMIC_SIZE_ADD(objspace->rgengc.oldmalloc_increase, new_size - old_size);
#endif
    }
    else {
	atomic_sub_nounderflow(&malloc_increase, old_size - new_size);
#if RGENGC_ESTIMATE_OLDMALLOC
	atomic_sub_nounderflow(&objspace->rgengc.oldmalloc_increase, old_size - new_size);
#endif
    }

    if (type == MEMOP_TYPE_MALLOC) {
      retry:
	if (malloc_increase > malloc_limit && ruby_native_thread_p() && !dont_gc_val()) {
	    if (ruby_thread_has_gvl_p() && is_lazy_sweeping(heap_eden)) {
		gc_rest(objspace); /* gc_rest can reduce malloc_increase */
		goto retry;
	    }
	    garbage_collect_with_gvl(objspace, GPR_FLAG_MALLOC);
	}
    }

#if MALLOC_ALLOCATED_SIZE
    if (new_size >= old_size) {
	ATOMIC_SIZE_ADD(objspace->malloc_params.allocated_size, new_size - old_size);
    }
    else {
	size_t dec_size = old_size - new_size;
	size_t allocated_size = objspace->malloc_params.allocated_size;

#if MALLOC_ALLOCATED_SIZE_CHECK
	if (allocated_size < dec_size) {
	    rb_bug("objspace_malloc_increase: underflow malloc_params.allocated_size.");
	}
#endif
	atomic_sub_nounderflow(&objspace->malloc_params.allocated_size, dec_size);
    }

    if (0) fprintf(stderr, "increase - ptr: %p, type: %s, new_size: %"PRIdSIZE", old_size: %"PRIdSIZE"\n",
		   mem,
		   type == MEMOP_TYPE_MALLOC  ? "malloc" :
		   type == MEMOP_TYPE_FREE    ? "free  " :
		   type == MEMOP_TYPE_REALLOC ? "realloc": "error",
		   new_size, old_size);

    switch (type) {
      case MEMOP_TYPE_MALLOC:
	ATOMIC_SIZE_INC(objspace->malloc_params.allocations);
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
}

struct malloc_obj_info { /* 4 words */
    size_t size;
#if USE_GC_MALLOC_OBJ_INFO_DETAILS
    size_t gen;
    const char *file;
    size_t line;
#endif
};

#if USE_GC_MALLOC_OBJ_INFO_DETAILS
const char *ruby_malloc_info_file;
int ruby_malloc_info_line;
#endif

static inline size_t
objspace_malloc_prepare(rb_objspace_t *objspace, size_t size)
{
    if (size == 0) size = 1;

#if CALC_EXACT_MALLOC_SIZE
    size += sizeof(struct malloc_obj_info);
#endif

    return size;
}

static inline void *
objspace_malloc_fixup(rb_objspace_t *objspace, void *mem, size_t size)
{
    size = objspace_malloc_size(objspace, mem, size);
    objspace_malloc_increase(objspace, mem, size, 0, MEMOP_TYPE_MALLOC);

#if CALC_EXACT_MALLOC_SIZE
    {
        struct malloc_obj_info *info = mem;
        info->size = size;
#if USE_GC_MALLOC_OBJ_INFO_DETAILS
        info->gen = objspace->profile.count;
        info->file = ruby_malloc_info_file;
        info->line = info->file ? ruby_malloc_info_line : 0;
#endif
        mem = info + 1;
    }
#endif

    return mem;
}

#if defined(__GNUC__) && RUBY_DEBUG
#define RB_BUG_INSTEAD_OF_RB_MEMERROR
#endif

#ifdef RB_BUG_INSTEAD_OF_RB_MEMERROR
#define TRY_WITH_GC(siz, expr) do {                          \
        const gc_profile_record_flag gpr =                   \
            GPR_FLAG_FULL_MARK           |                   \
            GPR_FLAG_IMMEDIATE_MARK      |                   \
            GPR_FLAG_IMMEDIATE_SWEEP     |                   \
            GPR_FLAG_MALLOC;                                 \
        objspace_malloc_gc_stress(objspace);                 \
                                                             \
        if (LIKELY((expr))) {                                \
            /* Success on 1st try */                         \
        }                                                    \
        else if (!garbage_collect_with_gvl(objspace, gpr)) { \
            /* @shyouhei thinks this doesn't happen */       \
            rb_bug("TRY_WITH_GC: could not GC");             \
        }                                                    \
        else if ((expr)) {                                   \
            /* Success on 2nd try */                         \
        }                                                    \
        else {                                               \
            rb_bug("TRY_WITH_GC: could not allocate:"        \
                   "%"PRIdSIZE" bytes for %s",               \
                   siz, # expr);                             \
        }                                                    \
    } while (0)
#else
#define TRY_WITH_GC(siz, alloc) do { \
        objspace_malloc_gc_stress(objspace); \
	if (!(alloc) && \
            (!garbage_collect_with_gvl(objspace, GPR_FLAG_FULL_MARK | \
                GPR_FLAG_IMMEDIATE_MARK | GPR_FLAG_IMMEDIATE_SWEEP | \
                GPR_FLAG_MALLOC) || \
	     !(alloc))) { \
	    ruby_memerror(); \
	} \
    } while (0)
#endif

/* these shouldn't be called directly.
 * objspace_* functions do not check allocation size.
 */
static void *
objspace_xmalloc0(rb_objspace_t *objspace, size_t size)
{
    void *mem;

    size = objspace_malloc_prepare(objspace, size);
    TRY_WITH_GC(size, mem = malloc(size));
    RB_DEBUG_COUNTER_INC(heap_xmalloc);
    return objspace_malloc_fixup(objspace, mem, size);
}

static inline size_t
xmalloc2_size(const size_t count, const size_t elsize)
{
    return size_mul_or_raise(count, elsize, rb_eArgError);
}

static void *
objspace_xrealloc(rb_objspace_t *objspace, void *ptr, size_t new_size, size_t old_size)
{
    void *mem;

    if (!ptr) return objspace_xmalloc0(objspace, new_size);

    /*
     * The behavior of realloc(ptr, 0) is implementation defined.
     * Therefore we don't use realloc(ptr, 0) for portability reason.
     * see http://www.open-std.org/jtc1/sc22/wg14/www/docs/dr_400.htm
     */
    if (new_size == 0) {
        if ((mem = objspace_xmalloc0(objspace, 0)) != NULL) {
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
             *   http://man7.org/linux/man-pages/man3/malloc.3.html
             *
             * - As I read the implementation jemalloc's malloc() returns fully
             *   normal 16 bytes memory region when its argument is 0.
             *
             * - As I read the implementation musl libc's malloc() returns
             *   fully normal 32 bytes memory region when its argument is 0.
             *
             * - Other malloc implementations can also return non-NULL.
             */
            objspace_xfree(objspace, ptr, old_size);
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
        old_size = info->size;
    }
#endif

    old_size = objspace_malloc_size(objspace, ptr, old_size);
    TRY_WITH_GC(new_size, mem = realloc(ptr, new_size));
    new_size = objspace_malloc_size(objspace, mem, new_size);

#if CALC_EXACT_MALLOC_SIZE
    {
        struct malloc_obj_info *info = mem;
        info->size = new_size;
        mem = info + 1;
    }
#endif

    objspace_malloc_increase(objspace, mem, new_size, old_size, MEMOP_TYPE_REALLOC);

    RB_DEBUG_COUNTER_INC(heap_xrealloc);
    return mem;
}

#if CALC_EXACT_MALLOC_SIZE && USE_GC_MALLOC_OBJ_INFO_DETAILS

#define MALLOC_INFO_GEN_SIZE 100
#define MALLOC_INFO_SIZE_SIZE 10
static size_t malloc_info_gen_cnt[MALLOC_INFO_GEN_SIZE];
static size_t malloc_info_gen_size[MALLOC_INFO_GEN_SIZE];
static size_t malloc_info_size[MALLOC_INFO_SIZE_SIZE+1];
static st_table *malloc_info_file_table;

static int
mmalloc_info_file_i(st_data_t key, st_data_t val, st_data_t dmy)
{
    const char *file = (void *)key;
    const size_t *data = (void *)val;

    fprintf(stderr, "%s\t%"PRIdSIZE"\t%"PRIdSIZE"\n", file, data[0], data[1]);

    return ST_CONTINUE;
}

__attribute__((destructor))
void
rb_malloc_info_show_results(void)
{
    int i;

    fprintf(stderr, "* malloc_info gen statistics\n");
    for (i=0; i<MALLOC_INFO_GEN_SIZE; i++) {
        if (i == MALLOC_INFO_GEN_SIZE-1) {
            fprintf(stderr, "more\t%"PRIdSIZE"\t%"PRIdSIZE"\n", malloc_info_gen_cnt[i], malloc_info_gen_size[i]);
        }
        else {
            fprintf(stderr, "%d\t%"PRIdSIZE"\t%"PRIdSIZE"\n", i, malloc_info_gen_cnt[i], malloc_info_gen_size[i]);
        }
    }

    fprintf(stderr, "* malloc_info size statistics\n");
    for (i=0; i<MALLOC_INFO_SIZE_SIZE; i++) {
        int s = 16 << i;
        fprintf(stderr, "%d\t%"PRIdSIZE"\n", s, malloc_info_size[i]);
    }
    fprintf(stderr, "more\t%"PRIdSIZE"\n", malloc_info_size[i]);

    if (malloc_info_file_table) {
        fprintf(stderr, "* malloc_info file statistics\n");
        st_foreach(malloc_info_file_table, mmalloc_info_file_i, 0);
    }
}
#else
void
rb_malloc_info_show_results(void)
{
}
#endif

static void
objspace_xfree(rb_objspace_t *objspace, void *ptr, size_t old_size)
{
    if (!ptr) {
        /*
         * ISO/IEC 9899 says "If ptr is a null pointer, no action occurs" since
         * its first version.  We would better follow.
         */
        return;
    }
#if CALC_EXACT_MALLOC_SIZE
    struct malloc_obj_info *info = (struct malloc_obj_info *)ptr - 1;
    ptr = info;
    old_size = info->size;

#if USE_GC_MALLOC_OBJ_INFO_DETAILS
    {
        int gen = (int)(objspace->profile.count - info->gen);
        int gen_index = gen >= MALLOC_INFO_GEN_SIZE ? MALLOC_INFO_GEN_SIZE-1 : gen;
        int i;

        malloc_info_gen_cnt[gen_index]++;
        malloc_info_gen_size[gen_index] += info->size;

        for (i=0; i<MALLOC_INFO_SIZE_SIZE; i++) {
            size_t s = 16 << i;
            if (info->size <= s) {
                malloc_info_size[i]++;
                goto found;
            }
        }
        malloc_info_size[i]++;
      found:;

        {
            st_data_t key = (st_data_t)info->file, d;
            size_t *data;

            if (malloc_info_file_table == NULL) {
                malloc_info_file_table = st_init_numtable_with_size(1024);
            }
            if (st_lookup(malloc_info_file_table, key, &d)) {
                /* hit */
                data = (size_t *)d;
            }
            else {
                data = malloc(xmalloc2_size(2, sizeof(size_t)));
                if (data == NULL) rb_bug("objspace_xfree: can not allocate memory");
                data[0] = data[1] = 0;
                st_insert(malloc_info_file_table, key, (st_data_t)data);
            }
            data[0] ++;
            data[1] += info->size;
        };
        if (0 && gen >= 2) {         /* verbose output */
            if (info->file) {
                fprintf(stderr, "free - size:%"PRIdSIZE", gen:%d, pos: %s:%"PRIdSIZE"\n",
                        info->size, gen, info->file, info->line);
            }
            else {
                fprintf(stderr, "free - size:%"PRIdSIZE", gen:%d\n",
                        info->size, gen);
            }
        }
    }
#endif
#endif
    old_size = objspace_malloc_size(objspace, ptr, old_size);

    free(ptr);
    RB_DEBUG_COUNTER_INC(heap_xfree);

    objspace_malloc_increase(objspace, ptr, 0, old_size, MEMOP_TYPE_FREE);
}

static void *
ruby_xmalloc0(size_t size)
{
    return objspace_xmalloc0(&rb_objspace, size);
}

void *
ruby_xmalloc_body(size_t size)
{
    if ((ssize_t)size < 0) {
	negative_size_allocation_error("too large allocation size");
    }
    return ruby_xmalloc0(size);
}

void
ruby_malloc_size_overflow(size_t count, size_t elsize)
{
    rb_raise(rb_eArgError,
	     "malloc: possible integer overflow (%"PRIuSIZE"*%"PRIuSIZE")",
	     count, elsize);
}

void *
ruby_xmalloc2_body(size_t n, size_t size)
{
    return objspace_xmalloc0(&rb_objspace, xmalloc2_size(n, size));
}

static void *
objspace_xcalloc(rb_objspace_t *objspace, size_t size)
{
    void *mem;

    size = objspace_malloc_prepare(objspace, size);
    TRY_WITH_GC(size, mem = calloc1(size));
    return objspace_malloc_fixup(objspace, mem, size);
}

void *
ruby_xcalloc_body(size_t n, size_t size)
{
    return objspace_xcalloc(&rb_objspace, xmalloc2_size(n, size));
}

#ifdef ruby_sized_xrealloc
#undef ruby_sized_xrealloc
#endif
void *
ruby_sized_xrealloc(void *ptr, size_t new_size, size_t old_size)
{
    if ((ssize_t)new_size < 0) {
	negative_size_allocation_error("too large allocation size");
    }

    return objspace_xrealloc(&rb_objspace, ptr, new_size, old_size);
}

void *
ruby_xrealloc_body(void *ptr, size_t new_size)
{
    return ruby_sized_xrealloc(ptr, new_size, 0);
}

#ifdef ruby_sized_xrealloc2
#undef ruby_sized_xrealloc2
#endif
void *
ruby_sized_xrealloc2(void *ptr, size_t n, size_t size, size_t old_n)
{
    size_t len = xmalloc2_size(n, size);
    return objspace_xrealloc(&rb_objspace, ptr, len, old_n * size);
}

void *
ruby_xrealloc2_body(void *ptr, size_t n, size_t size)
{
    return ruby_sized_xrealloc2(ptr, n, size, 0);
}

#ifdef ruby_sized_xfree
#undef ruby_sized_xfree
#endif
void
ruby_sized_xfree(void *x, size_t size)
{
    if (x) {
	objspace_xfree(&rb_objspace, x, size);
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
#if USE_GC_MALLOC_OBJ_INFO_DETAILS
        info->gen = 0;
        info->file = NULL;
        info->line = 0;
#endif
        mem = info + 1;
    }
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

void *
rb_alloc_tmp_buffer_with_count(volatile VALUE *store, size_t size, size_t cnt)
{
    void *ptr;
    VALUE imemo;
    rb_imemo_tmpbuf_t *tmpbuf;

    /* Keep the order; allocate an empty imemo first then xmalloc, to
     * get rid of potential memory leak */
    imemo = rb_imemo_tmpbuf_auto_free_maybe_mark_buffer(NULL, 0);
    *store = imemo;
    ptr = ruby_xmalloc0(size);
    tmpbuf = (rb_imemo_tmpbuf_t *)imemo;
    tmpbuf->ptr = ptr;
    tmpbuf->cnt = cnt;
    return ptr;
}

void *
rb_alloc_tmp_buffer(volatile VALUE *store, long len)
{
    long cnt;

    if (len < 0 || (cnt = (long)roomof(len, sizeof(VALUE))) < 0) {
	rb_raise(rb_eArgError, "negative buffer size (or size too big)");
    }

    return rb_alloc_tmp_buffer_with_count(store, len, cnt);
}

void
rb_free_tmp_buffer(volatile VALUE *store)
{
    rb_imemo_tmpbuf_t *s = (rb_imemo_tmpbuf_t*)ATOMIC_VALUE_EXCHANGE(*store, 0);
    if (s) {
	void *ptr = ATOMIC_PTR_EXCHANGE(s->ptr, 0);
	s->cnt = 0;
	ruby_xfree(ptr);
    }
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
    return UINT2NUM(rb_objspace.malloc_params.allocated_size);
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
    return UINT2NUM(rb_objspace.malloc_params.allocations);
}
#endif

void
rb_gc_adjust_memory_usage(ssize_t diff)
{
    rb_objspace_t *objspace = &rb_objspace;
    if (diff > 0) {
	objspace_malloc_increase(objspace, 0, diff, 0, MEMOP_TYPE_REALLOC);
    }
    else if (diff < 0) {
	objspace_malloc_increase(objspace, 0, 0, -diff, MEMOP_TYPE_REALLOC);
    }
}

/*
  ------------------------------ WeakMap ------------------------------
*/

struct weakmap {
    st_table *obj2wmap;		/* obj -> [ref,...] */
    st_table *wmap2obj;		/* ref -> obj */
    VALUE final;
};

#define WMAP_DELETE_DEAD_OBJECT_IN_MARK 0

#if WMAP_DELETE_DEAD_OBJECT_IN_MARK
static int
wmap_mark_map(st_data_t key, st_data_t val, st_data_t arg)
{
    rb_objspace_t *objspace = (rb_objspace_t *)arg;
    VALUE obj = (VALUE)val;
    if (!is_live_object(objspace, obj)) return ST_DELETE;
    return ST_CONTINUE;
}
#endif

static void
wmap_compact(void *ptr)
{
    struct weakmap *w = ptr;
    if (w->wmap2obj) rb_gc_update_tbl_refs(w->wmap2obj);
    if (w->obj2wmap) rb_gc_update_tbl_refs(w->obj2wmap);
    w->final = rb_gc_location(w->final);
}

static void
wmap_mark(void *ptr)
{
    struct weakmap *w = ptr;
#if WMAP_DELETE_DEAD_OBJECT_IN_MARK
    if (w->obj2wmap) st_foreach(w->obj2wmap, wmap_mark_map, (st_data_t)&rb_objspace);
#endif
    rb_gc_mark_movable(w->final);
}

static int
wmap_free_map(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE *ptr = (VALUE *)val;
    ruby_sized_xfree(ptr, (ptr[0] + 1) * sizeof(VALUE));
    return ST_CONTINUE;
}

static void
wmap_free(void *ptr)
{
    struct weakmap *w = ptr;
    st_foreach(w->obj2wmap, wmap_free_map, 0);
    st_free_table(w->obj2wmap);
    st_free_table(w->wmap2obj);
}

static int
wmap_memsize_map(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE *ptr = (VALUE *)val;
    *(size_t *)arg += (ptr[0] + 1) * sizeof(VALUE);
    return ST_CONTINUE;
}

static size_t
wmap_memsize(const void *ptr)
{
    size_t size;
    const struct weakmap *w = ptr;
    size = sizeof(*w);
    size += st_memsize(w->obj2wmap);
    size += st_memsize(w->wmap2obj);
    st_foreach(w->obj2wmap, wmap_memsize_map, (st_data_t)&size);
    return size;
}

static const rb_data_type_t weakmap_type = {
    "weakmap",
    {
	wmap_mark,
	wmap_free,
	wmap_memsize,
        wmap_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

extern const struct st_hash_type rb_hashtype_ident;
static VALUE wmap_finalize(RB_BLOCK_CALL_FUNC_ARGLIST(objid, self));

static VALUE
wmap_allocate(VALUE klass)
{
    struct weakmap *w;
    VALUE obj = TypedData_Make_Struct(klass, struct weakmap, &weakmap_type, w);
    w->obj2wmap = st_init_table(&rb_hashtype_ident);
    w->wmap2obj = st_init_table(&rb_hashtype_ident);
    w->final = rb_func_lambda_new(wmap_finalize, obj, 1, 1);
    return obj;
}

static int
wmap_live_p(rb_objspace_t *objspace, VALUE obj)
{
    if (!FL_ABLE(obj)) return TRUE;
    if (!is_id_value(objspace, obj)) return FALSE;
    if (!is_live_object(objspace, obj)) return FALSE;
    return TRUE;
}

static int
wmap_final_func(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    VALUE wmap, *ptr, size, i, j;
    if (!existing) return ST_STOP;
    wmap = (VALUE)arg, ptr = (VALUE *)*value;
    for (i = j = 1, size = ptr[0]; i <= size; ++i) {
	if (ptr[i] != wmap) {
	    ptr[j++] = ptr[i];
	}
    }
    if (j == 1) {
	ruby_sized_xfree(ptr, i * sizeof(VALUE));
	return ST_DELETE;
    }
    if (j < i) {
        SIZED_REALLOC_N(ptr, VALUE, j + 1, i);
	ptr[0] = j;
	*value = (st_data_t)ptr;
    }
    return ST_CONTINUE;
}

/* :nodoc: */
static VALUE
wmap_finalize(RB_BLOCK_CALL_FUNC_ARGLIST(objid, self))
{
    st_data_t orig, wmap, data;
    VALUE obj, *rids, i, size;
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    /* Get reference from object id. */
    if ((obj = id2ref_obj_tbl(&rb_objspace, objid)) == Qundef) {
        rb_bug("wmap_finalize: objid is not found.");
    }

    /* obj is original referenced object and/or weak reference. */
    orig = (st_data_t)obj;
    if (st_delete(w->obj2wmap, &orig, &data)) {
	rids = (VALUE *)data;
	size = *rids++;
	for (i = 0; i < size; ++i) {
	    wmap = (st_data_t)rids[i];
	    st_delete(w->wmap2obj, &wmap, NULL);
	}
	ruby_sized_xfree((VALUE *)data, (size + 1) * sizeof(VALUE));
    }

    wmap = (st_data_t)obj;
    if (st_delete(w->wmap2obj, &wmap, &orig)) {
	wmap = (st_data_t)obj;
	st_update(w->obj2wmap, orig, wmap_final_func, wmap);
    }
    return self;
}

struct wmap_iter_arg {
    rb_objspace_t *objspace;
    VALUE value;
};

static int
wmap_inspect_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE str = (VALUE)arg;
    VALUE k = (VALUE)key, v = (VALUE)val;

    if (RSTRING_PTR(str)[0] == '#') {
	rb_str_cat2(str, ", ");
    }
    else {
	rb_str_cat2(str, ": ");
	RSTRING_PTR(str)[0] = '#';
    }
    k = SPECIAL_CONST_P(k) ? rb_inspect(k) : rb_any_to_s(k);
    rb_str_append(str, k);
    rb_str_cat2(str, " => ");
    v = SPECIAL_CONST_P(v) ? rb_inspect(v) : rb_any_to_s(v);
    rb_str_append(str, v);

    return ST_CONTINUE;
}

static VALUE
wmap_inspect(VALUE self)
{
    VALUE str;
    VALUE c = rb_class_name(CLASS_OF(self));
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    str = rb_sprintf("-<%"PRIsVALUE":%p", c, (void *)self);
    if (w->wmap2obj) {
	st_foreach(w->wmap2obj, wmap_inspect_i, str);
    }
    RSTRING_PTR(str)[0] = '#';
    rb_str_cat2(str, ">");
    return str;
}

static int
wmap_each_i(st_data_t key, st_data_t val, st_data_t arg)
{
    rb_objspace_t *objspace = (rb_objspace_t *)arg;
    VALUE obj = (VALUE)val;
    if (wmap_live_p(objspace, obj)) {
	rb_yield_values(2, (VALUE)key, obj);
    }
    return ST_CONTINUE;
}

/* Iterates over keys and objects in a weakly referenced object */
static VALUE
wmap_each(VALUE self)
{
    struct weakmap *w;
    rb_objspace_t *objspace = &rb_objspace;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    st_foreach(w->wmap2obj, wmap_each_i, (st_data_t)objspace);
    return self;
}

static int
wmap_each_key_i(st_data_t key, st_data_t val, st_data_t arg)
{
    rb_objspace_t *objspace = (rb_objspace_t *)arg;
    VALUE obj = (VALUE)val;
    if (wmap_live_p(objspace, obj)) {
	rb_yield((VALUE)key);
    }
    return ST_CONTINUE;
}

/* Iterates over keys and objects in a weakly referenced object */
static VALUE
wmap_each_key(VALUE self)
{
    struct weakmap *w;
    rb_objspace_t *objspace = &rb_objspace;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    st_foreach(w->wmap2obj, wmap_each_key_i, (st_data_t)objspace);
    return self;
}

static int
wmap_each_value_i(st_data_t key, st_data_t val, st_data_t arg)
{
    rb_objspace_t *objspace = (rb_objspace_t *)arg;
    VALUE obj = (VALUE)val;
    if (wmap_live_p(objspace, obj)) {
	rb_yield(obj);
    }
    return ST_CONTINUE;
}

/* Iterates over keys and objects in a weakly referenced object */
static VALUE
wmap_each_value(VALUE self)
{
    struct weakmap *w;
    rb_objspace_t *objspace = &rb_objspace;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    st_foreach(w->wmap2obj, wmap_each_value_i, (st_data_t)objspace);
    return self;
}

static int
wmap_keys_i(st_data_t key, st_data_t val, st_data_t arg)
{
    struct wmap_iter_arg *argp = (struct wmap_iter_arg *)arg;
    rb_objspace_t *objspace = argp->objspace;
    VALUE ary = argp->value;
    VALUE obj = (VALUE)val;
    if (wmap_live_p(objspace, obj)) {
	rb_ary_push(ary, (VALUE)key);
    }
    return ST_CONTINUE;
}

/* Iterates over keys and objects in a weakly referenced object */
static VALUE
wmap_keys(VALUE self)
{
    struct weakmap *w;
    struct wmap_iter_arg args;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    args.objspace = &rb_objspace;
    args.value = rb_ary_new();
    st_foreach(w->wmap2obj, wmap_keys_i, (st_data_t)&args);
    return args.value;
}

static int
wmap_values_i(st_data_t key, st_data_t val, st_data_t arg)
{
    struct wmap_iter_arg *argp = (struct wmap_iter_arg *)arg;
    rb_objspace_t *objspace = argp->objspace;
    VALUE ary = argp->value;
    VALUE obj = (VALUE)val;
    if (wmap_live_p(objspace, obj)) {
	rb_ary_push(ary, obj);
    }
    return ST_CONTINUE;
}

/* Iterates over values and objects in a weakly referenced object */
static VALUE
wmap_values(VALUE self)
{
    struct weakmap *w;
    struct wmap_iter_arg args;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    args.objspace = &rb_objspace;
    args.value = rb_ary_new();
    st_foreach(w->wmap2obj, wmap_values_i, (st_data_t)&args);
    return args.value;
}

static int
wmap_aset_update(st_data_t *key, st_data_t *val, st_data_t arg, int existing)
{
    VALUE size, *ptr, *optr;
    if (existing) {
	size = (ptr = optr = (VALUE *)*val)[0];
	++size;
        SIZED_REALLOC_N(ptr, VALUE, size + 1, size);
    }
    else {
	optr = 0;
	size = 1;
	ptr = ruby_xmalloc0(2 * sizeof(VALUE));
    }
    ptr[0] = size;
    ptr[size] = (VALUE)arg;
    if (ptr == optr) return ST_STOP;
    *val = (st_data_t)ptr;
    return ST_CONTINUE;
}

/* Creates a weak reference from the given key to the given value */
static VALUE
wmap_aset(VALUE self, VALUE key, VALUE value)
{
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    if (FL_ABLE(value)) {
        define_final0(value, w->final);
    }
    if (FL_ABLE(key)) {
        define_final0(key, w->final);
    }

    st_update(w->obj2wmap, (st_data_t)value, wmap_aset_update, key);
    st_insert(w->wmap2obj, (st_data_t)key, (st_data_t)value);
    return nonspecial_obj_id(value);
}

/* Retrieves a weakly referenced object with the given key */
static VALUE
wmap_lookup(VALUE self, VALUE key)
{
    st_data_t data;
    VALUE obj;
    struct weakmap *w;
    rb_objspace_t *objspace = &rb_objspace;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    if (!st_lookup(w->wmap2obj, (st_data_t)key, &data)) return Qundef;
    obj = (VALUE)data;
    if (!wmap_live_p(objspace, obj)) return Qundef;
    return obj;
}

/* Retrieves a weakly referenced object with the given key */
static VALUE
wmap_aref(VALUE self, VALUE key)
{
    VALUE obj = wmap_lookup(self, key);
    return obj != Qundef ? obj : Qnil;
}

/* Returns +true+ if +key+ is registered */
static VALUE
wmap_has_key(VALUE self, VALUE key)
{
    return wmap_lookup(self, key) == Qundef ? Qfalse : Qtrue;
}

/* Returns the number of referenced objects */
static VALUE
wmap_size(VALUE self)
{
    struct weakmap *w;
    st_index_t n;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    n = w->wmap2obj->num_entries;
#if SIZEOF_ST_INDEX_T <= SIZEOF_LONG
    return ULONG2NUM(n);
#else
    return ULL2NUM(n);
#endif
}

/*
  ------------------------------ GC profiler ------------------------------
*/

#define GC_PROFILE_RECORD_DEFAULT_SIZE 100

/* return sec in user time */
static double
getrusage_time(void)
{
#if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_PROCESS_CPUTIME_ID)
    {
        static int try_clock_gettime = 1;
        struct timespec ts;
        if (try_clock_gettime && clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) == 0) {
            return ts.tv_sec + ts.tv_nsec * 1e-9;
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
            return time.tv_sec + time.tv_usec * 1e-6;
        }
    }
#endif

#ifdef _WIN32
    {
	FILETIME creation_time, exit_time, kernel_time, user_time;
	ULARGE_INTEGER ui;
	LONG_LONG q;
	double t;

	if (GetProcessTimes(GetCurrentProcess(),
			    &creation_time, &exit_time, &kernel_time, &user_time) != 0) {
	    memcpy(&ui, &user_time, sizeof(FILETIME));
	    q = ui.QuadPart / 10L;
	    t = (DWORD)(q % 1000000L) * 1e-6;
	    q /= 1000000L;
#ifdef __GNUC__
	    t += q;
#else
	    t += (double)(DWORD)(q >> 16) * (1 << 16);
	    t += (DWORD)q & ~(~0 << 16);
#endif
	    return t;
	}
    }
#endif

    return 0.0;
}

static inline void
gc_prof_setup_new_record(rb_objspace_t *objspace, int reason)
{
    if (objspace->profile.run) {
	size_t index = objspace->profile.next_index;
	gc_profile_record *record;

	/* create new record */
	objspace->profile.next_index++;

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
	if (!objspace->profile.records) {
	    rb_bug("gc_profile malloc or realloc miss");
	}
	record = objspace->profile.current_record = &objspace->profile.records[objspace->profile.next_index - 1];
	MEMZERO(record, gc_profile_record, 1);

	/* setup before-GC parameter */
	record->flags = reason | (ruby_gc_stressful ? GPR_FLAG_STRESS : 0);
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
    }
}

#define RUBY_DTRACE_GC_HOOK(name) \
    do {if (RUBY_DTRACE_GC_##name##_ENABLED()) RUBY_DTRACE_GC_##name();} while (0)
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
	size_t live = objspace->profile.total_allocated_objects_at_gc_start - objspace->profile.total_freed_objects;
	size_t total = objspace->profile.heap_used_at_gc_start * HEAP_PAGE_OBJ_LIMIT;

#if GC_PROFILE_MORE_DETAIL
	record->heap_use_pages = objspace->profile.heap_used_at_gc_start;
	record->heap_live_objects = live;
	record->heap_free_objects = total - live;
#endif

	record->heap_total_objects = total;
	record->heap_use_size = live * sizeof(RVALUE);
	record->heap_total_size = total * sizeof(RVALUE);
    }
}

/*
 *  call-seq:
 *    GC::Profiler.clear          -> nil
 *
 *  Clears the GC profiler data.
 *
 */

static VALUE
gc_profile_clear(VALUE _)
{
    rb_objspace_t *objspace = &rb_objspace;
    void *p = objspace->profile.records;
    objspace->profile.records = NULL;
    objspace->profile.size = 0;
    objspace->profile.next_index = 0;
    objspace->profile.current_record = 0;
    if (p) {
        free(p);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     GC::Profiler.raw_data	-> [Hash, ...]
 *
 *  Returns an Array of individual raw profile data Hashes ordered
 *  from earliest to latest by +:GC_INVOKE_TIME+.
 *
 *  For example:
 *
 *    [
 *	{
 *	   :GC_TIME=>1.3000000000000858e-05,
 *	   :GC_INVOKE_TIME=>0.010634999999999999,
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
 *  +:GC_TIME+::
 *	Time elapsed in seconds for this GC run
 *  +:GC_INVOKE_TIME+::
 *	Time elapsed in seconds from startup to when the GC was invoked
 *  +:HEAP_USE_SIZE+::
 *	Total bytes of heap used
 *  +:HEAP_TOTAL_SIZE+::
 *	Total size of heap in bytes
 *  +:HEAP_TOTAL_OBJECTS+::
 *	Total number of objects
 *  +:GC_IS_MARKED+::
 *	Returns +true+ if the GC is in mark phase
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
gc_profile_record_get(VALUE _)
{
    VALUE prof;
    VALUE gc_profile = rb_ary_new();
    size_t i;
    rb_objspace_t *objspace = (&rb_objspace);

    if (!objspace->profile.run) {
	return Qnil;
    }

    for (i =0; i < objspace->profile.next_index; i++) {
	gc_profile_record *record = &objspace->profile.records[i];

	prof = rb_hash_new();
	rb_hash_aset(prof, ID2SYM(rb_intern("GC_FLAGS")), gc_info_decode(0, rb_hash_new(), record->flags));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_TIME")), DBL2NUM(record->gc_time));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_INVOKE_TIME")), DBL2NUM(record->gc_invoke_time));
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
gc_profile_dump_major_reason(int flags, char *buff)
{
    int reason = flags & GPR_FLAG_MAJOR_MASK;
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
    rb_objspace_t *objspace = &rb_objspace;
    size_t count = objspace->profile.next_index;
#ifdef MAJOR_REASON_MAX
    char reason_str[MAJOR_REASON_MAX];
#endif

    if (objspace->profile.run && count /* > 1 */) {
	size_t i;
	const gc_profile_record *record;

	append(out, rb_sprintf("GC %"PRIuSIZE" invokes.\n", objspace->profile.count));
	append(out, rb_str_new_cstr("Index    Invoke Time(sec)       Use Size(byte)     Total Size(byte)         Total Object                    GC Time(ms)\n"));

	for (i = 0; i < count; i++) {
	    record = &objspace->profile.records[i];
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
	    record = &objspace->profile.records[i];
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
    rb_objspace_t *objspace = &rb_objspace;

    if (objspace->profile.run && objspace->profile.next_index > 0) {
	size_t i;
	size_t count = objspace->profile.next_index;

	for (i = 0; i < count; i++) {
	    time += objspace->profile.records[i].gc_time;
	}
    }
    return DBL2NUM(time);
}

/*
 *  call-seq:
 *    GC::Profiler.enabled?	-> true or false
 *
 *  The current status of GC profile mode.
 */

static VALUE
gc_profile_enable_get(VALUE self)
{
    rb_objspace_t *objspace = &rb_objspace;
    return objspace->profile.run ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    GC::Profiler.enable	-> nil
 *
 *  Starts the GC profiler.
 *
 */

static VALUE
gc_profile_enable(VALUE _)
{
    rb_objspace_t *objspace = &rb_objspace;
    objspace->profile.run = TRUE;
    objspace->profile.current_record = 0;
    return Qnil;
}

/*
 *  call-seq:
 *    GC::Profiler.disable	-> nil
 *
 *  Stops the GC profiler.
 *
 */

static VALUE
gc_profile_disable(VALUE _)
{
    rb_objspace_t *objspace = &rb_objspace;

    objspace->profile.run = FALSE;
    objspace->profile.current_record = 0;
    return Qnil;
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

/* from array.c */
# define ARY_SHARED_P(ary) \
    (GC_ASSERT(!FL_TEST((ary), ELTS_SHARED) || !FL_TEST((ary), RARRAY_EMBED_FLAG)), \
     FL_TEST((ary),ELTS_SHARED)!=0)
# define ARY_EMBED_P(ary) \
    (GC_ASSERT(!FL_TEST((ary), ELTS_SHARED) || !FL_TEST((ary), RARRAY_EMBED_FLAG)), \
     FL_TEST((ary), RARRAY_EMBED_FLAG)!=0)

static void
rb_raw_iseq_info(char *buff, const int buff_size, const rb_iseq_t *iseq)
{
    if (buff_size > 0 && iseq->body && iseq->body->location.label && !RB_TYPE_P(iseq->body->location.pathobj, T_MOVED)) {
	VALUE path = rb_iseq_path(iseq);
	VALUE n = iseq->body->location.first_lineno;
        snprintf(buff, buff_size, " %s@%s:%d",
		 RSTRING_PTR(iseq->body->location.label),
		 RSTRING_PTR(path),
		 n ? FIX2INT(n) : 0 );
    }
}

bool rb_ractor_p(VALUE rv);

static int
str_len_no_raise(VALUE str)
{
    long len = RSTRING_LEN(str);
    if (len < 0) return 0;
    if (len > INT_MAX) return INT_MAX;
    return (int)len;
}

const char *
rb_raw_obj_info(char *buff, const int buff_size, VALUE obj)
{
    int pos = 0;
    void *poisoned = asan_poisoned_object_p(obj);
    asan_unpoison_object(obj, false);

#define BUFF_ARGS buff + pos, buff_size - pos
#define APPENDF(f) if ((pos += snprintf f) >= buff_size) goto end
    if (SPECIAL_CONST_P(obj)) {
        APPENDF((BUFF_ARGS, "%s", obj_type_name(obj)));

        if (FIXNUM_P(obj)) {
            APPENDF((BUFF_ARGS, " %ld", FIX2LONG(obj)));
        }
        else if (SYMBOL_P(obj)) {
            APPENDF((BUFF_ARGS, " %s", rb_id2name(SYM2ID(obj))));
        }
    }
    else {
#define TF(c) ((c) != 0 ? "true" : "false")
#define C(c, s) ((c) != 0 ? (s) : " ")
	const int type = BUILTIN_TYPE(obj);
	const int age = RVALUE_FLAGS_AGE(RBASIC(obj)->flags);

        if (is_pointer_to_heap(&rb_objspace, (void *)obj)) {
            APPENDF((BUFF_ARGS, "%p [%d%s%s%s%s%s] %s ",
                     (void *)obj, age,
                     C(RVALUE_UNCOLLECTIBLE_BITMAP(obj),  "L"),
                     C(RVALUE_MARK_BITMAP(obj),           "M"),
                     C(RVALUE_PIN_BITMAP(obj),            "P"),
                     C(RVALUE_MARKING_BITMAP(obj),        "R"),
                     C(RVALUE_WB_UNPROTECTED_BITMAP(obj), "U"),
                     obj_type_name(obj)));
        }
        else {
            /* fake */
            APPENDF((BUFF_ARGS, "%p [%dXXXX] %s",
                     (void *)obj, age,
                     obj_type_name(obj)));
        }

	if (internal_object_p(obj)) {
	    /* ignore */
	}
	else if (RBASIC(obj)->klass == 0) {
            APPENDF((BUFF_ARGS, "(temporary internal)"));
	}
	else {
            if (RTEST(RBASIC(obj)->klass)) {
            VALUE class_path = rb_class_path_cached(RBASIC(obj)->klass);
	    if (!NIL_P(class_path)) {
                APPENDF((BUFF_ARGS, "(%s)", RSTRING_PTR(class_path)));
	    }
            }
	}

#if GC_DEBUG
        APPENDF((BUFF_ARGS, "@%s:%d", RANY(obj)->file, RANY(obj)->line));
#endif

	switch (type) {
	  case T_NODE:
	    UNEXPECTED_NODE(rb_raw_obj_info);
	    break;
	  case T_ARRAY:
            if (FL_TEST(obj, ELTS_SHARED)) {
                APPENDF((BUFF_ARGS, "shared -> %s",
                         rb_obj_info(RARRAY(obj)->as.heap.aux.shared_root)));
            }
            else if (FL_TEST(obj, RARRAY_EMBED_FLAG)) {
                APPENDF((BUFF_ARGS, "[%s%s] len: %ld (embed)",
                         C(ARY_EMBED_P(obj),  "E"),
                         C(ARY_SHARED_P(obj), "S"),
                         RARRAY_LEN(obj)));
            }
            else {
                APPENDF((BUFF_ARGS, "[%s%s%s] len: %ld, capa:%ld ptr:%p",
                         C(ARY_EMBED_P(obj),  "E"),
                         C(ARY_SHARED_P(obj), "S"),
                         C(RARRAY_TRANSIENT_P(obj), "T"),
                         RARRAY_LEN(obj),
                         ARY_EMBED_P(obj) ? -1L : RARRAY(obj)->as.heap.aux.capa,
                         (void *)RARRAY_CONST_PTR_TRANSIENT(obj)));
            }
	    break;
	  case T_STRING: {
            APPENDF((BUFF_ARGS, "%.*s", str_len_no_raise(obj), RSTRING_PTR(obj)));
	    break;
	  }
          case T_SYMBOL: {
              VALUE fstr = RSYMBOL(obj)->fstr;
              ID id = RSYMBOL(obj)->id;
              if (RB_TYPE_P(fstr, T_STRING)) {
                  APPENDF((BUFF_ARGS, ":%s id:%d", RSTRING_PTR(fstr), (unsigned int)id));
              }
              else {
                  APPENDF((BUFF_ARGS, "(%p) id:%d", (void *)fstr, (unsigned int)id));
              }
              break;
          }
          case T_MOVED: {
            APPENDF((BUFF_ARGS, "-> %p", (void*)rb_gc_location(obj)));
            break;
          }
          case T_HASH: {
              APPENDF((BUFF_ARGS, "[%c%c] %"PRIdSIZE,
                       RHASH_AR_TABLE_P(obj) ? 'A' : 'S',
                       RHASH_TRANSIENT_P(obj) ? 'T' : ' ',
                       RHASH_SIZE(obj)));
              break;
          }
          case T_CLASS:
          case T_MODULE:
            {
                VALUE class_path = rb_class_path_cached(obj);
                if (!NIL_P(class_path)) {
                    APPENDF((BUFF_ARGS, "%s", RSTRING_PTR(class_path)));
                }
                else {
                    APPENDF((BUFF_ARGS, "(annon)"));
                }
                break;
            }
          case T_ICLASS:
            {
                VALUE class_path = rb_class_path_cached(RBASIC_CLASS(obj));
                if (!NIL_P(class_path)) {
                    APPENDF((BUFF_ARGS, "src:%s", RSTRING_PTR(class_path)));
                }
                break;
            }
          case T_OBJECT:
            {
                uint32_t len = ROBJECT_NUMIV(obj);

                if (RANY(obj)->as.basic.flags & ROBJECT_EMBED) {
                    APPENDF((BUFF_ARGS, "(embed) len:%d", len));
                }
                else {
                    VALUE *ptr = ROBJECT_IVPTR(obj);
                    APPENDF((BUFF_ARGS, "len:%d ptr:%p", len, (void *)ptr));
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
                    APPENDF((BUFF_ARGS, "r:%d", r->id));
                }
            }
	    else {
		const char * const type_name = rb_objspace_data_type_name(obj);
		if (type_name) {
                    APPENDF((BUFF_ARGS, "%s", type_name));
		}
	    }
	    break;
	  }
	  case T_IMEMO: {
            APPENDF((BUFF_ARGS, "<%s> ", rb_imemo_name(imemo_type(obj))));

	    switch (imemo_type(obj)) {
	      case imemo_ment: {
		const rb_method_entry_t *me = &RANY(obj)->as.imemo.ment;
		if (me->def) {
                    APPENDF((BUFF_ARGS, ":%s (%s%s%s%s) type:%s alias:%d owner:%p defined_class:%p",
			     rb_id2name(me->called_id),
                             METHOD_ENTRY_VISI(me) == METHOD_VISI_PUBLIC ?  "pub" :
                             METHOD_ENTRY_VISI(me) == METHOD_VISI_PRIVATE ? "pri" : "pro",
                             METHOD_ENTRY_COMPLEMENTED(me) ? ",cmp" : "",
                             METHOD_ENTRY_CACHED(me) ? ",cc" : "",
                             METHOD_ENTRY_INVALIDATED(me) ? ",inv" : "",
                             rb_method_type_name(me->def->type),
                             me->def->alias_count,
                             (void *)me->owner, // obj_info(me->owner),
                             (void *)me->defined_class)); //obj_info(me->defined_class)));

                    if (me->def->type == VM_METHOD_TYPE_ISEQ) {
                        // APPENDF((BUFF_ARGS, " (iseq:%p)", (void *)me->def->body.iseq.iseqptr));
                        APPENDF((BUFF_ARGS, " (iseq:%s)", obj_info((VALUE)me->def->body.iseq.iseqptr)));
                    }
		}
		else {
                    APPENDF((BUFF_ARGS, "%s", rb_id2name(me->called_id)));
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
                    APPENDF((BUFF_ARGS, "(mid:%s, flag:%x argc:%d, kwarg:%s)",
                             rb_id2name(vm_ci_mid(ci)),
                             vm_ci_flag(ci),
                             vm_ci_argc(ci),
                             vm_ci_kwarg(ci) ? "available" : "NULL"));
                    break;
                }
              case imemo_callcache:
                {
                    const struct rb_callcache *cc = (const struct rb_callcache *)obj;
                    VALUE class_path = cc->klass ? rb_class_path_cached(cc->klass) : Qnil;

                    APPENDF((BUFF_ARGS, "(klass:%s, cme:%s (%p) call:%p",
                             NIL_P(class_path) ? "??" : RSTRING_PTR(class_path),
                             vm_cc_cme(cc) ? rb_id2name(vm_cc_cme(cc)->called_id) : "<NULL>",
                             (void *)vm_cc_cme(cc), (void *)vm_cc_call(cc)));
                    break;
                }
	      default:
		break;
	    }
	  }
	  default:
	    break;
	}
#undef TF
#undef C
    }
  end:
    if (poisoned) {
        asan_poison_object(obj);
    }

    return buff;
#undef APPENDF
#undef BUFF_ARGS
}

#if RGENGC_OBJ_INFO
#define OBJ_INFO_BUFFERS_NUM  10
#define OBJ_INFO_BUFFERS_SIZE 0x100
static int obj_info_buffers_index = 0;
static char obj_info_buffers[OBJ_INFO_BUFFERS_NUM][OBJ_INFO_BUFFERS_SIZE];

static const char *
obj_info(VALUE obj)
{
    const int index = obj_info_buffers_index++;
    char *const buff = &obj_info_buffers[index][0];

    if (obj_info_buffers_index >= OBJ_INFO_BUFFERS_NUM) {
	obj_info_buffers_index = 0;
    }

    return rb_raw_obj_info(buff, OBJ_INFO_BUFFERS_SIZE, obj);
}
#else
static const char *
obj_info(VALUE obj)
{
    return obj_type_name(obj);
}
#endif

MJIT_FUNC_EXPORTED const char *
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

MJIT_FUNC_EXPORTED void
rb_obj_info_dump_loc(VALUE obj, const char *file, int line, const char *func)
{
    char buff[0x100];
    fprintf(stderr, "<OBJ_INFO:%s@%s:%d> %s\n", func, file, line, rb_raw_obj_info(buff, 0x100, obj));
}

#if GC_DEBUG

void
rb_gcdebug_print_obj_condition(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;

    fprintf(stderr, "created at: %s:%d\n", RANY(obj)->file, RANY(obj)->line);

    if (BUILTIN_TYPE(obj) == T_MOVED) {
        fprintf(stderr, "moved?: true\n");
    }
    else {
        fprintf(stderr, "moved?: false\n");
    }
    if (is_pointer_to_heap(objspace, (void *)obj)) {
        fprintf(stderr, "pointer to heap?: true\n");
    }
    else {
        fprintf(stderr, "pointer to heap?: false\n");
        return;
    }

    fprintf(stderr, "marked?      : %s\n", MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj) ? "true" : "false");
    fprintf(stderr, "pinned?      : %s\n", MARKED_IN_BITMAP(GET_HEAP_PINNED_BITS(obj), obj) ? "true" : "false");
    fprintf(stderr, "age?         : %d\n", RVALUE_AGE(obj));
    fprintf(stderr, "old?         : %s\n", RVALUE_OLD_P(obj) ? "true" : "false");
    fprintf(stderr, "WB-protected?: %s\n", RVALUE_WB_UNPROTECTED(obj) ? "false" : "true");
    fprintf(stderr, "remembered?  : %s\n", RVALUE_REMEMBERED(obj) ? "true" : "false");

    if (is_lazy_sweeping(heap_eden)) {
        fprintf(stderr, "lazy sweeping?: true\n");
        fprintf(stderr, "swept?: %s\n", is_swept_object(objspace, obj) ? "done" : "not yet");
    }
    else {
        fprintf(stderr, "lazy sweeping?: false\n");
    }
}

static VALUE
gcdebug_sentinel(RB_BLOCK_CALL_FUNC_ARGLIST(obj, name))
{
    fprintf(stderr, "WARNING: object %s(%p) is inadvertently collected\n", (char *)name, (void *)obj);
    return Qnil;
}

void
rb_gcdebug_sentinel(VALUE obj, const char *name)
{
    rb_define_finalizer(obj, rb_proc_new(gcdebug_sentinel, (VALUE)name));
}

#endif /* GC_DEBUG */

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
    rb_objspace_t *objspace = &rb_objspace;

    if (!stress_to_class) {
	stress_to_class = rb_ary_tmp_new(argc);
    }
    rb_ary_cat(stress_to_class, argv, argc);
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
    rb_objspace_t *objspace = &rb_objspace;
    int i;

    if (stress_to_class) {
	for (i = 0; i < argc; ++i) {
	    rb_ary_delete_same(stress_to_class, argv[i]);
	}
	if (RARRAY_LEN(stress_to_class) == 0) {
	    stress_to_class = 0;
	}
    }
    return Qnil;
}
#endif

/*
 * Document-module: ObjectSpace
 *
 *  The ObjectSpace module contains a number of routines
 *  that interact with the garbage collection facility and allow you to
 *  traverse all living objects with an iterator.
 *
 *  ObjectSpace also provides support for object finalizers, procs that will be
 *  called when a specific object is about to be destroyed by garbage
 *  collection. See the documentation for
 *  <code>ObjectSpace.define_finalizer</code> for important information on
 *  how to use this method correctly.
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

/*
 *  Document-class: ObjectSpace::WeakMap
 *
 *  An ObjectSpace::WeakMap object holds references to
 *  any objects, but those objects can get garbage collected.
 *
 *  This class is mostly used internally by WeakRef, please use
 *  +lib/weakref.rb+ for the public interface.
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
    VALUE rb_mObjSpace;
    VALUE rb_mProfiler;
    VALUE gc_constants;

    rb_mGC = rb_define_module("GC");

    gc_constants = rb_hash_new();
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("DEBUG")), GC_DEBUG ? Qtrue : Qfalse);
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_SIZE")), SIZET2NUM(sizeof(RVALUE)));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_OBJ_LIMIT")), SIZET2NUM(HEAP_PAGE_OBJ_LIMIT));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_BITMAP_SIZE")), SIZET2NUM(HEAP_PAGE_BITMAP_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_BITMAP_PLANES")), SIZET2NUM(HEAP_PAGE_BITMAP_PLANES));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_SIZE")), SIZET2NUM(HEAP_PAGE_SIZE));
    OBJ_FREEZE(gc_constants);
    /* internal constants */
    rb_define_const(rb_mGC, "INTERNAL_CONSTANTS", gc_constants);

    rb_mProfiler = rb_define_module_under(rb_mGC, "Profiler");
    rb_define_singleton_method(rb_mProfiler, "enabled?", gc_profile_enable_get, 0);
    rb_define_singleton_method(rb_mProfiler, "enable", gc_profile_enable, 0);
    rb_define_singleton_method(rb_mProfiler, "raw_data", gc_profile_record_get, 0);
    rb_define_singleton_method(rb_mProfiler, "disable", gc_profile_disable, 0);
    rb_define_singleton_method(rb_mProfiler, "clear", gc_profile_clear, 0);
    rb_define_singleton_method(rb_mProfiler, "result", gc_profile_result, 0);
    rb_define_singleton_method(rb_mProfiler, "report", gc_profile_report, -1);
    rb_define_singleton_method(rb_mProfiler, "total_time", gc_profile_total_time, 0);

    rb_mObjSpace = rb_define_module("ObjectSpace");

    rb_define_module_function(rb_mObjSpace, "each_object", os_each_obj, -1);

    rb_define_module_function(rb_mObjSpace, "define_finalizer", define_final, -1);
    rb_define_module_function(rb_mObjSpace, "undefine_finalizer", undefine_final, 1);

    rb_define_module_function(rb_mObjSpace, "_id2ref", os_id2ref, 1);

    rb_vm_register_special_exception(ruby_error_nomemory, rb_eNoMemError, "failed to allocate memory");

    rb_define_method(rb_cBasicObject, "__id__", rb_obj_id, 0);
    rb_define_method(rb_mKernel, "object_id", rb_obj_id, 0);

    rb_define_module_function(rb_mObjSpace, "count_objects", count_objects, -1);

    {
	VALUE rb_cWeakMap = rb_define_class_under(rb_mObjSpace, "WeakMap", rb_cObject);
	rb_define_alloc_func(rb_cWeakMap, wmap_allocate);
	rb_define_method(rb_cWeakMap, "[]=", wmap_aset, 2);
	rb_define_method(rb_cWeakMap, "[]", wmap_aref, 1);
	rb_define_method(rb_cWeakMap, "include?", wmap_has_key, 1);
	rb_define_method(rb_cWeakMap, "member?", wmap_has_key, 1);
	rb_define_method(rb_cWeakMap, "key?", wmap_has_key, 1);
	rb_define_method(rb_cWeakMap, "inspect", wmap_inspect, 0);
	rb_define_method(rb_cWeakMap, "each", wmap_each, 0);
	rb_define_method(rb_cWeakMap, "each_pair", wmap_each, 0);
	rb_define_method(rb_cWeakMap, "each_key", wmap_each_key, 0);
	rb_define_method(rb_cWeakMap, "each_value", wmap_each_value, 0);
	rb_define_method(rb_cWeakMap, "keys", wmap_keys, 0);
	rb_define_method(rb_cWeakMap, "values", wmap_values, 0);
	rb_define_method(rb_cWeakMap, "size", wmap_size, 0);
	rb_define_method(rb_cWeakMap, "length", wmap_size, 0);
	rb_include_module(rb_cWeakMap, rb_mEnumerable);
    }

    /* internal methods */
    rb_define_singleton_method(rb_mGC, "verify_internal_consistency", gc_verify_internal_consistency_m, 0);
    rb_define_singleton_method(rb_mGC, "verify_transient_heap_internal_consistency", gc_verify_transient_heap_internal_consistency, 0);
#if MALLOC_ALLOCATED_SIZE
    rb_define_singleton_method(rb_mGC, "malloc_allocated_size", gc_malloc_allocated_size, 0);
    rb_define_singleton_method(rb_mGC, "malloc_allocations", gc_malloc_allocations, 0);
#endif

#if GC_DEBUG_STRESS_TO_CLASS
    rb_define_singleton_method(rb_mGC, "add_stress_to_class", rb_gcdebug_add_stress_to_class, -1);
    rb_define_singleton_method(rb_mGC, "remove_stress_to_class", rb_gcdebug_remove_stress_to_class, -1);
#endif

    {
	VALUE opts;
	/* GC build options */
	rb_define_const(rb_mGC, "OPTS", opts = rb_ary_new());
#define OPT(o) if (o) rb_ary_push(opts, rb_fstring_lit(#o))
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
#undef OPT
	OBJ_FREEZE(opts);
    }
}

#ifdef ruby_xmalloc
#undef ruby_xmalloc
#endif
#ifdef ruby_xmalloc2
#undef ruby_xmalloc2
#endif
#ifdef ruby_xcalloc
#undef ruby_xcalloc
#endif
#ifdef ruby_xrealloc
#undef ruby_xrealloc
#endif
#ifdef ruby_xrealloc2
#undef ruby_xrealloc2
#endif

void *
ruby_xmalloc(size_t size)
{
#if USE_GC_MALLOC_OBJ_INFO_DETAILS
    ruby_malloc_info_file = __FILE__;
    ruby_malloc_info_line = __LINE__;
#endif
    return ruby_xmalloc_body(size);
}

void *
ruby_xmalloc2(size_t n, size_t size)
{
#if USE_GC_MALLOC_OBJ_INFO_DETAILS
    ruby_malloc_info_file = __FILE__;
    ruby_malloc_info_line = __LINE__;
#endif
    return ruby_xmalloc2_body(n, size);
}

void *
ruby_xcalloc(size_t n, size_t size)
{
#if USE_GC_MALLOC_OBJ_INFO_DETAILS
    ruby_malloc_info_file = __FILE__;
    ruby_malloc_info_line = __LINE__;
#endif
    return ruby_xcalloc_body(n, size);
}

void *
ruby_xrealloc(void *ptr, size_t new_size)
{
#if USE_GC_MALLOC_OBJ_INFO_DETAILS
    ruby_malloc_info_file = __FILE__;
    ruby_malloc_info_line = __LINE__;
#endif
    return ruby_xrealloc_body(ptr, new_size);
}

void *
ruby_xrealloc2(void *ptr, size_t n, size_t new_size)
{
#if USE_GC_MALLOC_OBJ_INFO_DETAILS
    ruby_malloc_info_file = __FILE__;
    ruby_malloc_info_line = __LINE__;
#endif
    return ruby_xrealloc2_body(ptr, n, new_size);
}
