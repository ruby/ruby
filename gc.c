/**********************************************************************

  gc.c -

  $Author$
  created at: Tue Oct  5 09:44:46 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/st.h"
#include "ruby/re.h"
#include "ruby/io.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "ruby/debug.h"
#include "eval_intern.h"
#include "vm_core.h"
#include "internal.h"
#include "gc.h"
#include "constant.h"
#include "ruby_atomic.h"
#include "probes.h"
#include <stdio.h>
#include <stdarg.h>
#include <setjmp.h>
#include <sys/types.h>
#include <assert.h>

#ifndef __has_feature
# define __has_feature(x) 0
#endif

#ifndef HAVE_MALLOC_USABLE_SIZE
# ifdef _WIN32
#   define HAVE_MALLOC_USABLE_SIZE
#   define malloc_usable_size(a) _msize(a)
# elif defined HAVE_MALLOC_SIZE
#   define HAVE_MALLOC_USABLE_SIZE
#   define malloc_usable_size(a) malloc_size(a)
# endif
#endif
#ifdef HAVE_MALLOC_USABLE_SIZE
# ifdef HAVE_MALLOC_H
#  include <malloc.h>
# elif defined(HAVE_MALLOC_NP_H)
#  include <malloc_np.h>
# elif defined(HAVE_MALLOC_MALLOC_H)
#  include <malloc/malloc.h>
# endif
#endif

#if /* is ASAN enabled? */ \
    __has_feature(address_sanitizer) /* Clang */ || \
    defined(__SANITIZE_ADDRESS__)  /* GCC 4.8.x */
  #define ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS \
        __attribute__((no_address_safety_analysis)) \
        __attribute__((noinline))
#else
  #define ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS
#endif

#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif

#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif
#if defined(__native_client__) && defined(NACL_NEWLIB)
# include "nacl/resource.h"
# undef HAVE_POSIX_MEMALIGN
# undef HAVE_MEMALIGN

#endif

#if defined _WIN32 || defined __CYGWIN__
#include <windows.h>
#elif defined(HAVE_POSIX_MEMALIGN)
#elif defined(HAVE_MEMALIGN)
#include <malloc.h>
#endif

#define rb_setjmp(env) RUBY_SETJMP(env)
#define rb_jmp_buf rb_jmpbuf_t

#if defined(HAVE_RB_GC_GUARDED_PTR) && HAVE_RB_GC_GUARDED_PTR
volatile VALUE *
rb_gc_guarded_ptr(volatile VALUE *ptr)
{
    return ptr;
}
#endif

#ifndef GC_HEAP_FREE_SLOTS
#define GC_HEAP_FREE_SLOTS  4096
#endif
#ifndef GC_HEAP_INIT_SLOTS
#define GC_HEAP_INIT_SLOTS 10000
#endif
#ifndef GC_HEAP_GROWTH_FACTOR
#define GC_HEAP_GROWTH_FACTOR 1.8
#endif
#ifndef GC_HEAP_GROWTH_MAX_SLOTS
#define GC_HEAP_GROWTH_MAX_SLOTS 0 /* 0 is disable */
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

typedef struct {
    unsigned int heap_init_slots;
    unsigned int heap_free_slots;
    double growth_factor;
    unsigned int growth_max_slots;
    unsigned int malloc_limit_min;
    unsigned int malloc_limit_max;
    double malloc_limit_growth_factor;
    unsigned int oldmalloc_limit_min;
    unsigned int oldmalloc_limit_max;
    double oldmalloc_limit_growth_factor;
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
    VALUE gc_stress;
#endif
} ruby_gc_params_t;

static ruby_gc_params_t gc_params = {
    GC_HEAP_FREE_SLOTS,
    GC_HEAP_INIT_SLOTS,
    GC_HEAP_GROWTH_FACTOR,
    GC_HEAP_GROWTH_MAX_SLOTS,
    GC_MALLOC_LIMIT_MIN,
    GC_MALLOC_LIMIT_MAX,
    GC_MALLOC_LIMIT_GROWTH_FACTOR,
    GC_OLDMALLOC_LIMIT_MIN,
    GC_OLDMALLOC_LIMIT_MAX,
    GC_OLDMALLOC_LIMIT_GROWTH_FACTOR,
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
    FALSE,
#endif
};

/* GC_DEBUG:
 *  enable to embed GC debugging information.
 */
#ifndef GC_DEBUG
#define GC_DEBUG 0
#endif

#if USE_RGENGC
/* RGENGC_DEBUG:
 * 1: basic information
 * 2: remember set operation
 * 3: mark
 * 4:
 * 5: sweep
 */
#ifndef RGENGC_DEBUG
#define RGENGC_DEBUG       0
#endif

/* RGENGC_CHECK_MODE
 * 0: disable all assertions
 * 1: enable assertions (to debug RGenGC)
 * 2: enable generational bits check (for debugging)
 * 3: enable livness check
 * 4: show all references
 */
#ifndef RGENGC_CHECK_MODE
#define RGENGC_CHECK_MODE  0
#endif

/* RGENGC_PROFILE
 * 0: disable RGenGC profiling
 * 1: enable profiling for basic information
 * 2: enable profiling for each types
 */
#ifndef RGENGC_PROFILE
#define RGENGC_PROFILE     0
#endif

/* RGENGC_THREEGEN
 * Enable/disable three gen GC.
 * 0: Infant gen -> Old gen
 * 1: Infant gen -> Young -> Old gen
 */
#ifndef RGENGC_THREEGEN
#define RGENGC_THREEGEN    0
#endif

/* RGENGC_ESTIMATE_OLDMALLOC
 * Enable/disable to estimate increase size of malloc'ed size by old objects.
 * If estimation exceeds threashold, then will invoke full GC.
 * 0: disable estimation.
 * 1: enable estimation.
 */
#ifndef RGENGC_ESTIMATE_OLDMALLOC
#define RGENGC_ESTIMATE_OLDMALLOC 1
#endif

#else /* USE_RGENGC */

#define RGENGC_DEBUG       0
#define RGENGC_CHECK_MODE  0
#define RGENGC_PROFILE     0
#define RGENGC_THREEGEN    0
#define RGENGC_ESTIMATE_OLDMALLOC 0

#endif /* USE_RGENGC */

#ifndef GC_PROFILE_MORE_DETAIL
#define GC_PROFILE_MORE_DETAIL 0
#endif
#ifndef GC_PROFILE_DETAIL_MEMORY
#define GC_PROFILE_DETAIL_MEMORY 0
#endif
#ifndef GC_ENABLE_LAZY_SWEEP
#define GC_ENABLE_LAZY_SWEEP   1
#endif
#ifndef CALC_EXACT_MALLOC_SIZE
#define CALC_EXACT_MALLOC_SIZE 0
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

typedef enum {
    GPR_FLAG_NONE               = 0x000,
    /* major reason */
    GPR_FLAG_MAJOR_BY_NOFREE    = 0x001,
    GPR_FLAG_MAJOR_BY_OLDGEN    = 0x002,
    GPR_FLAG_MAJOR_BY_SHADY     = 0x004,
    GPR_FLAG_MAJOR_BY_RESCAN    = 0x008,
    GPR_FLAG_MAJOR_BY_STRESS    = 0x010,
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
    GPR_FLAG_HAVE_FINALIZE     = 0x4000
} gc_profile_record_flag;

typedef struct gc_profile_record {
    int flags;

    double gc_time;
    double gc_invoke_time;

    size_t heap_total_objects;
    size_t heap_use_size;
    size_t heap_total_size;

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

#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__CYGWIN__)
#pragma pack(push, 1) /* magic for reducing sizeof(RVALUE): 24 -> 20 */
#endif

typedef struct RVALUE {
    union {
	struct {
	    VALUE flags;		/* always 0 for freed obj */
	    struct RVALUE *next;
	} free;
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
	struct RNode   node;
	struct RMatch  match;
	struct RRational rational;
	struct RComplex complex;
	struct {
	    struct RBasic basic;
	    VALUE v1;
	    VALUE v2;
	    VALUE v3;
	} values;
    } as;
#if GC_DEBUG
    const char *file;
    VALUE line;
#endif
} RVALUE;

#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__CYGWIN__)
#pragma pack(pop)
#endif

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
    size_t index;
    size_t limit;
    size_t cache_size;
    size_t unused_cache_size;
} mark_stack_t;

typedef struct rb_heap_struct {
    struct heap_page *pages;
    struct heap_page *free_pages;
    struct heap_page *using_page;
    struct heap_page *sweep_pages;
    RVALUE *freelist;
    size_t page_length;      /* total page count in a heap */
    size_t total_slots;      /* total slot count (page_length * HEAP_OBJ_LIMIT) */
} rb_heap_t;

typedef struct rb_objspace {
    struct {
	size_t limit;
	size_t increase;
#if MALLOC_ALLOCATED_SIZE
	size_t allocated_size;
	size_t allocations;
#endif
    } malloc_params;

    rb_heap_t eden_heap;
    rb_heap_t tomb_heap; /* heap for zombies and ghosts */

    struct {
	struct heap_page **sorted;
	size_t used;
	size_t length;
	RVALUE *range[2];

	size_t limit;
	size_t increment;

	size_t swept_slots;
	size_t min_free_slots;
	size_t max_free_slots;

	/* final */
	size_t final_slots;
	RVALUE *deferred_final;
    } heap_pages;

    struct {
	int dont_gc;
	int dont_lazy_sweep;
	int during_gc;
	rb_atomic_t finalizing;
    } flags;
    st_table *finalizer_table;
    mark_stack_t mark_stack;
    struct {
	int run;
	gc_profile_record *records;
	gc_profile_record *current_record;
	size_t next_index;
	size_t size;

#if GC_PROFILE_MORE_DETAIL
	double prepare_time;
#endif
	double invoke_time;

#if USE_RGENGC
	size_t minor_gc_count;
	size_t major_gc_count;
#if RGENGC_PROFILE > 0
	size_t generated_normal_object_count;
	size_t generated_shady_object_count;
	size_t shade_operation_count;
	size_t promote_infant_count;
#if RGENGC_THREEGEN
	size_t promote_young_count;
#endif
	size_t remembered_normal_object_count;
	size_t remembered_shady_object_count;

#if RGENGC_PROFILE >= 2
	size_t generated_normal_object_count_types[RUBY_T_MASK];
	size_t generated_shady_object_count_types[RUBY_T_MASK];
	size_t shade_operation_count_types[RUBY_T_MASK];
	size_t promote_infant_types[RUBY_T_MASK];
#if RGENGC_THREEGEN
	size_t promote_young_types[RUBY_T_MASK];
#endif
	size_t remembered_normal_object_count_types[RUBY_T_MASK];
	size_t remembered_shady_object_count_types[RUBY_T_MASK];
#endif
#endif /* RGENGC_PROFILE */
#endif /* USE_RGENGC */

	/* temporary profiling space */
	double gc_sweep_start_time;
	size_t total_allocated_object_num_at_gc_start;
	size_t heap_used_at_gc_start;

	/* basic statistics */
	size_t count;
	size_t total_allocated_object_num;
	size_t total_freed_object_num;
	int latest_gc_info;
    } profile;
    struct gc_list *global_list;
    rb_event_flag_t hook_events; /* this place may be affinity with memory cache */
    VALUE gc_stress;

    struct mark_func_data_struct {
	void *data;
	void (*mark_func)(VALUE v, void *data);
    } *mark_func_data;

#if USE_RGENGC
    struct {
	int during_minor_gc;
	int parent_object_is_old;

	int need_major_gc;
	size_t remembered_shady_object_count;
	size_t remembered_shady_object_limit;
	size_t old_object_count;
	size_t old_object_limit;
#if RGENGC_THREEGEN
	size_t young_object_count;
#endif

#if RGENGC_ESTIMATE_OLDMALLOC
	size_t oldmalloc_increase;
	size_t oldmalloc_increase_limit;
#endif

#if RGENGC_CHECK_MODE >= 2
	struct st_table *allrefs_table;
	size_t error_count;
#endif
    } rgengc;
#endif /* USE_RGENGC */
} rb_objspace_t;


#ifndef HEAP_ALIGN_LOG
/* default tiny heap size: 16KB */
#define HEAP_ALIGN_LOG 14
#endif
#define CEILDIV(i, mod) (((i) + (mod) - 1)/(mod))
enum {
    HEAP_ALIGN = (1UL << HEAP_ALIGN_LOG),
    HEAP_ALIGN_MASK = (~(~0UL << HEAP_ALIGN_LOG)),
    REQUIRED_SIZE_BY_MALLOC = (sizeof(size_t) * 5),
    HEAP_SIZE = (HEAP_ALIGN - REQUIRED_SIZE_BY_MALLOC),
    HEAP_OBJ_LIMIT = (unsigned int)((HEAP_SIZE - sizeof(struct heap_page_header))/sizeof(struct RVALUE)),
    HEAP_BITMAP_LIMIT = CEILDIV(CEILDIV(HEAP_SIZE, sizeof(struct RVALUE)), BITS_BITLENGTH),
    HEAP_BITMAP_SIZE = ( BITS_SIZE * HEAP_BITMAP_LIMIT),
    HEAP_BITMAP_PLANES = USE_RGENGC ? 3 : 1 /* RGENGC: mark bits, rememberset bits and oldgen bits */
};

struct heap_page {
    struct heap_page_body *body;
    RVALUE *freelist;
    RVALUE *start;
    size_t final_slots;
    size_t limit;
    struct heap_page *next;
    struct heap_page *prev;
    struct heap_page *free_next;
    rb_heap_t *heap;
    int before_sweep;

    bits_t mark_bits[HEAP_BITMAP_LIMIT];
#if USE_RGENGC
    bits_t rememberset_bits[HEAP_BITMAP_LIMIT];
    bits_t oldgen_bits[HEAP_BITMAP_LIMIT];
#endif
};

#define GET_PAGE_BODY(x)             ((struct heap_page_body *)((bits_t)(x) & ~(HEAP_ALIGN_MASK)))
#define GET_PAGE_HEADER(x)           (&GET_PAGE_BODY(x)->header)
#define GET_HEAP_PAGE(x)             (GET_PAGE_HEADER(x)->page)
#define GET_HEAP_MARK_BITS(x)        (&GET_HEAP_PAGE(x)->mark_bits[0])
#define GET_HEAP_REMEMBERSET_BITS(x) (&GET_HEAP_PAGE(x)->rememberset_bits[0])
#define GET_HEAP_OLDGEN_BITS(x)      (&GET_HEAP_PAGE(x)->oldgen_bits[0])
#define NUM_IN_PAGE(p)               (((bits_t)(p) & HEAP_ALIGN_MASK)/sizeof(RVALUE))
#define BITMAP_INDEX(p)              (NUM_IN_PAGE(p) / BITS_BITLENGTH )
#define BITMAP_OFFSET(p)             (NUM_IN_PAGE(p) & (BITS_BITLENGTH-1))
#define BITMAP_BIT(p)                ((bits_t)1 << BITMAP_OFFSET(p))
/* Bitmap Operations */
#define MARKED_IN_BITMAP(bits, p)    ((bits)[BITMAP_INDEX(p)] & BITMAP_BIT(p))
#define MARK_IN_BITMAP(bits, p)      ((bits)[BITMAP_INDEX(p)] = (bits)[BITMAP_INDEX(p)] | BITMAP_BIT(p))
#define CLEAR_IN_BITMAP(bits, p)     ((bits)[BITMAP_INDEX(p)] = (bits)[BITMAP_INDEX(p)] & ~BITMAP_BIT(p))

/* Aliases */
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
#define rb_objspace (*GET_VM()->objspace)
#define ruby_initial_gc_stress	gc_params.gc_stress
VALUE *ruby_initial_gc_stress_ptr = &ruby_initial_gc_stress;
#else
static rb_objspace_t rb_objspace = {{GC_MALLOC_LIMIT_MIN}};
VALUE *ruby_initial_gc_stress_ptr = &rb_objspace.gc_stress;
#endif

#define malloc_limit		objspace->malloc_params.limit
#define malloc_increase 	objspace->malloc_params.increase
#define malloc_allocated_size 	objspace->malloc_params.allocated_size
#define heap_pages_sorted       objspace->heap_pages.sorted
#define heap_pages_used         objspace->heap_pages.used
#define heap_pages_length       objspace->heap_pages.length
#define heap_pages_lomem	objspace->heap_pages.range[0]
#define heap_pages_himem	objspace->heap_pages.range[1]
#define heap_pages_swept_slots	objspace->heap_pages.swept_slots
#define heap_pages_increment	objspace->heap_pages.increment
#define heap_pages_min_free_slots	objspace->heap_pages.min_free_slots
#define heap_pages_max_free_slots	objspace->heap_pages.max_free_slots
#define heap_pages_final_slots		objspace->heap_pages.final_slots
#define heap_pages_deferred_final	objspace->heap_pages.deferred_final
#define heap_eden               (&objspace->eden_heap)
#define heap_tomb               (&objspace->tomb_heap)
#define dont_gc 		objspace->flags.dont_gc
#define during_gc		objspace->flags.during_gc
#define finalizing		objspace->flags.finalizing
#define finalizer_table 	objspace->finalizer_table
#define global_List		objspace->global_list
#define ruby_gc_stress		objspace->gc_stress
#define monitor_level           objspace->rgengc.monitor_level
#define monitored_object_table  objspace->rgengc.monitored_object_table

#define is_lazy_sweeping(heap) ((heap)->sweep_pages != 0)
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

#define nomem_error GET_VM()->special_exceptions[ruby_error_nomemory]

int ruby_gc_debug_indent = 0;
VALUE rb_mGC;
int ruby_disable_gc_stress = 0;

void rb_gcdebug_print_obj_condition(VALUE obj);

static void rb_objspace_call_finalizer(rb_objspace_t *objspace);
static VALUE define_final0(VALUE obj, VALUE block);

static void negative_size_allocation_error(const char *);
static void *aligned_malloc(size_t, size_t);
static void aligned_free(void *);

static void init_mark_stack(mark_stack_t *stack);

static VALUE lazy_sweep_enable(void);
static int ready_to_gc(rb_objspace_t *objspace);
static int heap_ready_to_gc(rb_objspace_t *objspace, rb_heap_t *heap);
static int garbage_collect(rb_objspace_t *, int full_mark, int immediate_sweep, int reason);
static int garbage_collect_body(rb_objspace_t *, int full_mark, int immediate_sweep, int reason);
static int gc_heap_lazy_sweep(rb_objspace_t *objspace, rb_heap_t *heap);
static void gc_rest_sweep(rb_objspace_t *objspace);
static void gc_heap_rest_sweep(rb_objspace_t *objspace, rb_heap_t *heap);

static void gc_mark_stacked_objects(rb_objspace_t *);
static void gc_mark(rb_objspace_t *objspace, VALUE ptr);
static void gc_mark_maybe(rb_objspace_t *objspace, VALUE ptr);
static void gc_mark_children(rb_objspace_t *objspace, VALUE ptr);

static size_t obj_memsize_of(VALUE obj, int use_tdata);

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

#define gc_prof_record(objspace) (objspace)->profile.current_record
#define gc_prof_enabled(objspace) ((objspace)->profile.run && (objspace)->profile.current_record)

#define rgengc_report if (RGENGC_DEBUG) rgengc_report_body
static void rgengc_report_body(int level, rb_objspace_t *objspace, const char *fmt, ...);
static const char * type_name(int type, VALUE obj);
static const char *obj_type_name(VALUE obj);

#if USE_RGENGC
static int rgengc_remembered(rb_objspace_t *objspace, VALUE obj);
static int rgengc_remember(rb_objspace_t *objspace, VALUE obj);
static void rgengc_mark_and_rememberset_clear(rb_objspace_t *objspace, rb_heap_t *heap);
static void rgengc_rememberset_mark(rb_objspace_t *objspace, rb_heap_t *heap);

#define FL_TEST2(x,f)         ((RGENGC_CHECK_MODE && SPECIAL_CONST_P(x)) ? (rb_bug("FL_TEST2: SPECIAL_CONST"), 0) : FL_TEST_RAW((x),(f)) != 0)
#define FL_SET2(x,f)          do {if (RGENGC_CHECK_MODE && SPECIAL_CONST_P(x)) rb_bug("FL_SET2: SPECIAL_CONST");   RBASIC(x)->flags |= (f);} while (0)
#define FL_UNSET2(x,f)        do {if (RGENGC_CHECK_MODE && SPECIAL_CONST_P(x)) rb_bug("FL_UNSET2: SPECIAL_CONST"); RBASIC(x)->flags &= ~(f);} while (0)

#define RVALUE_WB_PROTECTED_RAW(obj)     FL_TEST2((obj), FL_WB_PROTECTED)
#define RVALUE_WB_PROTECTED(obj)         RVALUE_WB_PROTECTED_RAW(check_gen_consistency((VALUE)obj))

#define RVALUE_OLDGEN_BITMAP(obj) MARKED_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj), (obj))

static inline int is_pointer_to_heap(rb_objspace_t *objspace, void *ptr);
static inline int gc_marked(rb_objspace_t *objspace, VALUE ptr);

static inline VALUE
check_gen_consistency(VALUE obj)
{
    if (RGENGC_CHECK_MODE > 0) {
	int old_flag = RVALUE_OLDGEN_BITMAP(obj) != 0;
	int promoted_flag = FL_TEST2(obj, FL_PROMOTED);
	rb_objspace_t *objspace = &rb_objspace;

	obj_memsize_of((VALUE)obj, FALSE);

	if (!is_pointer_to_heap(objspace, (void *)obj)) {
	    rb_bug("check_gen_consistency: %p (%s) is not Ruby object.", (void *)obj, obj_type_name(obj));
	}

	if (promoted_flag) {
	    if (!RVALUE_WB_PROTECTED_RAW(obj)) {
		const char *type = old_flag ? "old" : "young";
		rb_bug("check_gen_consistency: %p (%s) is not WB protected, but %s object.", (void *)obj, obj_type_name(obj), type);
	    }

#if !RGENGC_THREEGEN
	    if (!old_flag) {
		rb_bug("check_gen_consistency: %p (%s) is not infant, but is not old (on 2gen).", (void *)obj, obj_type_name(obj));
	    }
#endif

	    if (old_flag && objspace->rgengc.during_minor_gc && !gc_marked(objspace, obj)) {
		rb_bug("check_gen_consistency: %p (%s) is old, but is not marked while minor marking.", (void *)obj, obj_type_name(obj));
	    }
	}
	else {
	    if (old_flag) {
		rb_bug("check_gen_consistency: %p (%s) is not infant, but is old.", (void *)obj, obj_type_name(obj));
	    }
	}
    }
    return obj;
}

static inline VALUE
RVALUE_INFANT_P(VALUE obj)
{
    check_gen_consistency(obj);
    return !FL_TEST2(obj, FL_PROMOTED);
}

static inline VALUE
RVALUE_OLD_BITMAP_P(VALUE obj)
{
    check_gen_consistency(obj);
    return (RVALUE_OLDGEN_BITMAP(obj) != 0);
}

static inline VALUE
RVALUE_OLD_P(VALUE obj)
{
    check_gen_consistency(obj);
#if RGENGC_THREEGEN
    return FL_TEST2(obj, FL_PROMOTED) && RVALUE_OLD_BITMAP_P(obj);
#else
    return FL_TEST2(obj, FL_PROMOTED);
#endif
}

static inline VALUE
RVALUE_PROMOTED_P(VALUE obj)
{
    check_gen_consistency(obj);
    return FL_TEST2(obj, FL_PROMOTED);
}

static inline void
RVALUE_PROMOTE_INFANT(VALUE obj)
{
    check_gen_consistency(obj);
    if (RGENGC_CHECK_MODE && !RVALUE_INFANT_P(obj)) rb_bug("RVALUE_PROMOTE_INFANT: %p (%s) is not infant object.", (void *)obj, obj_type_name(obj));
    FL_SET2(obj, FL_PROMOTED);
#if !RGENGC_THREEGEN
    MARK_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj), obj);
#endif
    check_gen_consistency(obj);

#if RGENGC_PROFILE >= 1
    {
	rb_objspace_t *objspace = &rb_objspace;
	objspace->profile.promote_infant_count++;

#if RGENGC_PROFILE >= 2
	objspace->profile.promote_infant_types[BUILTIN_TYPE(obj)]++;
#endif
    }
#endif
}

#if RGENGC_THREEGEN
/*
 * Two gen: Infant -> Old.
 * Three gen: Infant -> Young -> Old.
 */
static inline VALUE
RVALUE_YOUNG_P(VALUE obj)
{
    check_gen_consistency(obj);
    return FL_TEST2(obj, FL_PROMOTED) && (RVALUE_OLDGEN_BITMAP(obj) == 0);
}

static inline void
RVALUE_PROMOTE_YOUNG(VALUE obj)
{
    check_gen_consistency(obj);
    if (RGENGC_CHECK_MODE && !RVALUE_YOUNG_P(obj)) rb_bug("RVALUE_PROMOTE_YOUNG: %p (%s) is not young object.", (void *)obj, obj_type_name(obj));
    MARK_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj), obj);
    check_gen_consistency(obj);

#if RGENGC_PROFILE >= 1
    {
	rb_objspace_t *objspace = &rb_objspace;
	objspace->profile.promote_young_count++;
#if RGENGC_PROFILE >= 2
	objspace->profile.promote_young_types[BUILTIN_TYPE(obj)]++;
#endif
    }
#endif
}

static inline void
RVALUE_DEMOTE_FROM_YOUNG(VALUE obj)
{
    if (RGENGC_CHECK_MODE && !RVALUE_YOUNG_P(obj))
      rb_bug("RVALUE_DEMOTE_FROM_YOUNG: %p (%s) is not young object.", (void *)obj, obj_type_name(obj));

    check_gen_consistency(obj);
    FL_UNSET2(obj, FL_PROMOTED);
    check_gen_consistency(obj);
}
#endif

static inline void
RVALUE_DEMOTE_FROM_OLD(VALUE obj)
{
    if (RGENGC_CHECK_MODE && !RVALUE_OLD_P(obj))
      rb_bug("RVALUE_DEMOTE_FROM_OLD: %p (%s) is not old object.", (void *)obj, obj_type_name(obj));

    check_gen_consistency(obj);
    FL_UNSET2(obj, FL_PROMOTED);
    CLEAR_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj), obj);
    check_gen_consistency(obj);
}

#endif /* USE_RGENGC */

/*
  --------------------------- ObjectSpace -----------------------------
*/

#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
rb_objspace_t *
rb_objspace_alloc(void)
{
    rb_objspace_t *objspace = malloc(sizeof(rb_objspace_t));
    memset(objspace, 0, sizeof(*objspace));
    ruby_gc_stress = ruby_initial_gc_stress;

    malloc_limit = gc_params.malloc_limit_min;

    return objspace;
}
#endif

#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
static void free_stack_chunks(mark_stack_t *);
static void heap_page_free(rb_objspace_t *objspace, struct heap_page *page);

void
rb_objspace_free(rb_objspace_t *objspace)
{
    gc_rest_sweep(objspace);

    if (objspace->profile.records) {
	free(objspace->profile.records);
	objspace->profile.records = 0;
    }

    if (global_List) {
	struct gc_list *list, *next;
	for (list = global_List; list; list = next) {
	    next = list->next;
	    xfree(list);
	}
    }
    if (heap_pages_sorted) {
	size_t i;
	for (i = 0; i < heap_pages_used; ++i) {
	    heap_page_free(objspace, heap_pages_sorted[i]);
	}
	free(heap_pages_sorted);
	heap_pages_used = 0;
	heap_pages_length = 0;
	heap_pages_lomem = 0;
	heap_pages_himem = 0;

	objspace->eden_heap.page_length = 0;
	objspace->eden_heap.total_slots = 0;
	objspace->eden_heap.pages = NULL;
    }
    free_stack_chunks(&objspace->mark_stack);
    free(objspace);
}
#endif

static void
heap_pages_expand_sorted(rb_objspace_t *objspace)
{
    size_t next_length = heap_pages_increment;
    next_length += heap_eden->page_length;
    next_length += heap_tomb->page_length;

    if (next_length > heap_pages_length) {
	struct heap_page **sorted;
	size_t size = next_length * sizeof(struct heap_page *);

	rgengc_report(3, objspace, "heap_pages_expand_sorted: next_length: %d, size: %d\n", (int)next_length, (int)size);

	if (heap_pages_length > 0) {
	    sorted = (struct heap_page **)realloc(heap_pages_sorted, size);
	    if (sorted) heap_pages_sorted = sorted;
	}
	else {
	    sorted = heap_pages_sorted = (struct heap_page **)malloc(size);
	}

	if (sorted == 0) {
	    during_gc = 0;
	    rb_memerror();
	}

	heap_pages_length = next_length;
    }
}

static inline void
heap_page_add_freeobj(rb_objspace_t *objspace, struct heap_page *page, VALUE obj)
{
    RVALUE *p = (RVALUE *)obj;
    p->as.free.flags = 0;
    p->as.free.next = page->freelist;
    page->freelist = p;
    rgengc_report(3, objspace, "heap_page_add_freeobj: %p (%s) is added to freelist\n", p, obj_type_name(obj));
}

static inline void
heap_add_freepage(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    if (page->freelist) {
	page->free_next = heap->free_pages;
	heap->free_pages = page;
    }
}

static void
heap_unlink_page(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    if (page->prev) page->prev->next = page->next;
    if (page->next) page->next->prev = page->prev;
    if (heap->pages == page) heap->pages = page->next;
    page->prev = NULL;
    page->next = NULL;
    page->heap = NULL;
    heap->page_length--;
    heap->total_slots -= page->limit;
}

static void
heap_page_free(rb_objspace_t *objspace, struct heap_page *page)
{
    heap_pages_used--;
    aligned_free(page->body);
    free(page);
}

static void
heap_pages_free_unused_pages(rb_objspace_t *objspace)
{
    size_t i, j;

    for (i = j = 1; j < heap_pages_used; i++) {
	struct heap_page *page = heap_pages_sorted[i];

	if (page->heap == heap_tomb && page->final_slots == 0) {
	    if (heap_pages_swept_slots - page->limit > heap_pages_max_free_slots) {
		if (0) fprintf(stderr, "heap_pages_free_unused_pages: %d free page %p, heap_pages_swept_slots: %d, heap_pages_max_free_slots: %d\n",
			       (int)i, page, (int)heap_pages_swept_slots, (int)heap_pages_max_free_slots);
		heap_pages_swept_slots -= page->limit;
		heap_unlink_page(objspace, heap_tomb, page);
		heap_page_free(objspace, page);
		continue;
	    }
	    else {
		/* fprintf(stderr, "heap_pages_free_unused_pages: remain!!\n"); */
	    }
	}
	if (i != j) {
	    heap_pages_sorted[j] = page;
	}
	j++;
    }
    assert(j == heap_pages_used);
}

static struct heap_page *
heap_page_allocate(rb_objspace_t *objspace)
{
    RVALUE *start, *end, *p;
    struct heap_page *page;
    struct heap_page_body *page_body = 0;
    size_t hi, lo, mid;
    size_t limit = HEAP_OBJ_LIMIT;

    /* assign heap_page body (contains heap_page_header and RVALUEs) */
    page_body = (struct heap_page_body *)aligned_malloc(HEAP_ALIGN, HEAP_SIZE);
    if (page_body == 0) {
	during_gc = 0;
	rb_memerror();
    }

    /* assign heap_page entry */
    page = (struct heap_page *)malloc(sizeof(struct heap_page));
    if (page == 0) {
	aligned_free(page_body);
	during_gc = 0;
	rb_memerror();
    }
    MEMZERO((void*)page, struct heap_page, 1);

    page->body = page_body;

    /* setup heap_pages_sorted */
    lo = 0;
    hi = heap_pages_used;
    while (lo < hi) {
	struct heap_page *mid_page;

	mid = (lo + hi) / 2;
	mid_page = heap_pages_sorted[mid];
	if (mid_page->body < page_body) {
	    lo = mid + 1;
	}
	else if (mid_page->body > page_body) {
	    hi = mid;
	}
	else {
	    rb_bug("same heap page is allocated: %p at %"PRIuVALUE, (void *)page_body, (VALUE)mid);
	}
    }
    if (hi < heap_pages_used) {
	MEMMOVE(&heap_pages_sorted[hi+1], &heap_pages_sorted[hi], struct heap_page_header*, heap_pages_used - hi);
    }

    heap_pages_sorted[hi] = page;

    heap_pages_used++;
    assert(heap_pages_used <= heap_pages_length);

    /* adjust obj_limit (object number available in this page) */
    start = (RVALUE*)((VALUE)page_body + sizeof(struct heap_page_header));
    if ((VALUE)start % sizeof(RVALUE) != 0) {
	int delta = (int)(sizeof(RVALUE) - ((VALUE)start % sizeof(RVALUE)));
	start = (RVALUE*)((VALUE)start + delta);
	limit = (HEAP_SIZE - (size_t)((VALUE)start - (VALUE)page_body))/sizeof(RVALUE);
    }
    end = start + limit;

    if (heap_pages_lomem == 0 || heap_pages_lomem > start) heap_pages_lomem = start;
    if (heap_pages_himem < end) heap_pages_himem = end;

    page->start = start;
    page->limit = limit;
    page_body->header.page = page;

    for (p = start; p != end; p++) {
	rgengc_report(3, objspace, "assign_heap_page: %p is added to freelist\n");
	heap_page_add_freeobj(objspace, page, (VALUE)p);
    }

    return page;
}

static struct heap_page *
heap_page_resurrect(rb_objspace_t *objspace)
{
    struct heap_page *page;

    if ((page = heap_tomb->pages) != NULL) {
	heap_unlink_page(objspace, heap_tomb, page);
	return page;
    }
    return NULL;
}

static struct heap_page *
heap_page_create(rb_objspace_t *objspace)
{
    struct heap_page *page = heap_page_resurrect(objspace);
    const char *method = "recycle";
    if (page == NULL) {
	page = heap_page_allocate(objspace);
	method = "allocate";
    }
    if (0) fprintf(stderr, "heap_page_create: %s - %p, heap_pages_used: %d, heap_pages_used: %d, tomb->page_length: %d\n",
		   method, page, (int)heap_pages_length, (int)heap_pages_used, (int)heap_tomb->page_length);
    return page;
}

static void
heap_add_page(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *page)
{
    page->heap = heap;
    page->next = heap->pages;
    if (heap->pages) heap->pages->prev = page;
    heap->pages = page;
    heap->page_length++;
    heap->total_slots += page->limit;
}

static void
heap_assign_page(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page = heap_page_create(objspace);
    heap_add_page(objspace, heap, page);
    heap_add_freepage(objspace, heap, page);
}

static void
heap_add_pages(rb_objspace_t *objspace, rb_heap_t *heap, size_t add)
{
    size_t i;

    heap_pages_increment = add;
    heap_pages_expand_sorted(objspace);
    for (i = 0; i < add; i++) {
	heap_assign_page(objspace, heap);
    }
    heap_pages_increment = 0;
}

static void
heap_set_increment(rb_objspace_t *objspace, size_t minimum_limit)
{
    size_t used = heap_pages_used - heap_tomb->page_length;
    size_t next_used_limit = (size_t)(used * gc_params.growth_factor);
    if (gc_params.growth_max_slots > 0) {
	size_t max_used_limit = (size_t)(used + gc_params.growth_max_slots/HEAP_OBJ_LIMIT);
	if (next_used_limit > max_used_limit) next_used_limit = max_used_limit;
    }
    if (next_used_limit == heap_pages_used) next_used_limit++;

    if (next_used_limit < minimum_limit) {
	next_used_limit = minimum_limit;
    }

    heap_pages_increment = next_used_limit - used;
    heap_pages_expand_sorted(objspace);

    if (0) fprintf(stderr, "heap_set_increment: heap_pages_length: %d, heap_pages_used: %d, heap_pages_increment: %d, next_used_limit: %d\n",
		   (int)heap_pages_length, (int)heap_pages_used, (int)heap_pages_increment, (int)next_used_limit);
}

static int
heap_increment(rb_objspace_t *objspace, rb_heap_t *heap)
{
    rgengc_report(5, objspace, "heap_increment: heap_pages_length: %d, heap_pages_inc: %d, heap->page_length: %d\n",
		  (int)heap_pages_length, (int)heap_pages_increment, (int)heap->page_length);

    if (heap_pages_increment > 0) {
	heap_pages_increment--;
	heap_assign_page(objspace, heap);
	return TRUE;
    }
    return FALSE;
}

static struct heap_page *
heap_prepare_freepage(rb_objspace_t *objspace, rb_heap_t *heap)
{
    if (!GC_ENABLE_LAZY_SWEEP && objspace->flags.dont_lazy_sweep) {
	if (heap_increment(objspace, heap) == 0 &&
	    garbage_collect(objspace, FALSE, TRUE, GPR_FLAG_NEWOBJ) == 0) {
	    goto err;
	}
	goto ok;
    }

    if (!heap_ready_to_gc(objspace, heap)) return heap->free_pages;

    during_gc++;

    if ((is_lazy_sweeping(heap) && gc_heap_lazy_sweep(objspace, heap)) || heap_increment(objspace, heap)) {
	goto ok;
    }

#if GC_PROFILE_MORE_DETAIL
    objspace->profile.prepare_time = 0;
#endif
    if (garbage_collect_body(objspace, 0, 0, GPR_FLAG_NEWOBJ) == 0) {
      err:
	during_gc = 0;
	rb_memerror();
    }
  ok:
    during_gc = 0;
    return heap->free_pages;
}

static RVALUE *
heap_get_freeobj_from_next_freepage(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page;
    RVALUE *p;

    page = heap->free_pages;
    while (page == NULL) {
	page = heap_prepare_freepage(objspace, heap);
    }
    heap->free_pages = page->free_next;
    heap->using_page = page;

    p = page->freelist;
    page->freelist = NULL;

    return p;
}

static inline VALUE
heap_get_freeobj(rb_objspace_t *objspace, rb_heap_t *heap)
{
    RVALUE *p = heap->freelist;

    while (1) {
	if (p) {
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
}

static void
gc_event_hook_body(rb_objspace_t *objspace, const rb_event_flag_t event, VALUE data)
{
    rb_thread_t *th = GET_THREAD();
    EXEC_EVENT_HOOK(th, event, th->cfp->self, 0, 0, data);
}

#define gc_event_hook(objspace, event, data) do { \
    if (UNLIKELY((objspace)->hook_events & (event))) { \
	gc_event_hook_body((objspace), (event), (data)); \
    } \
} while (0)

static VALUE
newobj_of(VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE obj;

    if (UNLIKELY(during_gc)) {
	dont_gc = 1;
	during_gc = 0;
	rb_bug("object allocation during garbage collection phase");
    }

    if (UNLIKELY(ruby_gc_stress && !ruby_disable_gc_stress)) {
	if (!garbage_collect(objspace, FALSE, FALSE, GPR_FLAG_NEWOBJ)) {
	    during_gc = 0;
	    rb_memerror();
	}
    }

    obj = heap_get_freeobj(objspace, heap_eden);

    /* OBJSETUP */
    RBASIC(obj)->flags = flags;
    RBASIC_SET_CLASS_RAW(obj, klass);
    if (rb_safe_level() >= 3) FL_SET((obj), FL_TAINT);
    RANY(obj)->as.values.v1 = v1;
    RANY(obj)->as.values.v2 = v2;
    RANY(obj)->as.values.v3 = v3;

#if GC_DEBUG
    RANY(obj)->file = rb_sourcefile();
    RANY(obj)->line = rb_sourceline();
    assert(!SPECIAL_CONST_P(obj)); /* check alignment */
#endif

#if RGENGC_PROFILE
    if (flags & FL_WB_PROTECTED) {
	objspace->profile.generated_normal_object_count++;
#if RGENGC_PROFILE >= 2
	objspace->profile.generated_normal_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
    }
    else {
	objspace->profile.generated_shady_object_count++;
#if RGENGC_PROFILE >= 2
	objspace->profile.generated_shady_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
    }
#endif

    rgengc_report(5, objspace, "newobj: %p (%s)\n", (void *)obj, obj_type_name(obj));

#if USE_RGENGC && RGENGC_CHECK_MODE
    if (RVALUE_PROMOTED_P(obj)) rb_bug("newobj: %p (%s) is promoted.\n", (void *)obj, obj_type_name(obj));
    if (rgengc_remembered(objspace, (VALUE)obj)) rb_bug("newobj: %p (%s) is remembered.\n", (void *)obj, obj_type_name(obj));
#endif

    objspace->profile.total_allocated_object_num++;
    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_NEWOBJ, obj);

    return obj;
}

VALUE
rb_newobj(void)
{
    return newobj_of(0, T_NONE, 0, 0, 0);
}

VALUE
rb_newobj_of(VALUE klass, VALUE flags)
{
    return newobj_of(klass, flags, 0, 0, 0);
}

NODE*
rb_node_newnode(enum node_type type, VALUE a0, VALUE a1, VALUE a2)
{
    VALUE flags = (RGENGC_WB_PROTECTED_NODE_CREF && type == NODE_CREF ? FL_WB_PROTECTED : 0);
    NODE *n = (NODE *)newobj_of(0, T_NODE | flags, a0, a1, a2);
    nd_set_type(n, type);
    return n;
}

VALUE
rb_data_object_alloc(VALUE klass, void *datap, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    if (klass) Check_Type(klass, T_CLASS);
    return newobj_of(klass, T_DATA, (VALUE)dmark, (VALUE)dfree, (VALUE)datap);
}

VALUE
rb_data_typed_object_alloc(VALUE klass, void *datap, const rb_data_type_t *type)
{
    if (klass) Check_Type(klass, T_CLASS);
    return newobj_of(klass, T_DATA | (type->flags & ~T_MASK), (VALUE)type, (VALUE)1, (VALUE)datap);
}

size_t
rb_objspace_data_type_memsize(VALUE obj)
{
    if (RTYPEDDATA_P(obj) && RTYPEDDATA_TYPE(obj)->function.dsize) {
	return RTYPEDDATA_TYPE(obj)->function.dsize(RTYPEDDATA_DATA(obj));
    }
    else {
	return 0;
    }
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

static inline int
is_pointer_to_heap(rb_objspace_t *objspace, void *ptr)
{
    register RVALUE *p = RANY(ptr);
    register struct heap_page *page;
    register size_t hi, lo, mid;

    if (p < heap_pages_lomem || p > heap_pages_himem) return FALSE;
    if ((VALUE)p % sizeof(RVALUE) != 0) return FALSE;

    /* check if p looks like a pointer using bsearch*/
    lo = 0;
    hi = heap_pages_used;
    while (lo < hi) {
	mid = (lo + hi) / 2;
	page = heap_pages_sorted[mid];
	if (page->start <= p) {
	    if (p < page->start + page->limit) {
		return TRUE;
	    }
	    lo = mid + 1;
	}
	else {
	    hi = mid;
	}
    }
    return FALSE;
}

static int
free_method_entry_i(ID key, rb_method_entry_t *me, st_data_t data)
{
    if (!me->mark) {
	rb_free_method_entry(me);
    }
    return ST_CONTINUE;
}

void
rb_free_m_tbl(st_table *tbl)
{
    st_foreach(tbl, free_method_entry_i, 0);
    st_free_table(tbl);
}

void
rb_free_m_tbl_wrapper(struct method_table_wrapper *wrapper)
{
    if (wrapper->tbl) {
	rb_free_m_tbl(wrapper->tbl);
    }
    xfree(wrapper);
}

static int
free_const_entry_i(ID key, rb_const_entry_t *ce, st_data_t data)
{
    xfree(ce);
    return ST_CONTINUE;
}

void
rb_free_const_table(st_table *tbl)
{
    st_foreach(tbl, free_const_entry_i, 0);
    st_free_table(tbl);
}

static inline void
make_deferred(rb_objspace_t *objspace,RVALUE *p)
{
    p->as.basic.flags = T_ZOMBIE;
    p->as.free.next = heap_pages_deferred_final;
    heap_pages_deferred_final = p;
}

static inline void
make_io_deferred(rb_objspace_t *objspace,RVALUE *p)
{
    rb_io_t *fptr = p->as.file.fptr;
    make_deferred(objspace, p);
    p->as.data.dfree = (void (*)(void*))rb_io_fptr_finalize;
    p->as.data.data = fptr;
}

static int
obj_free(rb_objspace_t *objspace, VALUE obj)
{
    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_FREEOBJ, obj);

    switch (BUILTIN_TYPE(obj)) {
      case T_NIL:
      case T_FIXNUM:
      case T_TRUE:
      case T_FALSE:
	rb_bug("obj_free() called for broken object");
	break;
    }

    if (FL_TEST(obj, FL_EXIVAR)) {
	rb_free_generic_ivar((VALUE)obj);
	FL_UNSET(obj, FL_EXIVAR);
    }

#if USE_RGENGC
    if (MARKED_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj),obj))
	CLEAR_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj),obj);
#endif

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
	if (!(RANY(obj)->as.basic.flags & ROBJECT_EMBED) &&
            RANY(obj)->as.object.as.heap.ivptr) {
	    xfree(RANY(obj)->as.object.as.heap.ivptr);
	}
	break;
      case T_MODULE:
      case T_CLASS:
        if (RCLASS_M_TBL_WRAPPER(obj)) {
            rb_free_m_tbl_wrapper(RCLASS_M_TBL_WRAPPER(obj));
        }
	if (RCLASS_IV_TBL(obj)) {
	    st_free_table(RCLASS_IV_TBL(obj));
	}
	if (RCLASS_CONST_TBL(obj)) {
	    rb_free_const_table(RCLASS_CONST_TBL(obj));
	}
	if (RCLASS_IV_INDEX_TBL(obj)) {
	    st_free_table(RCLASS_IV_INDEX_TBL(obj));
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
	break;
      case T_STRING:
	rb_str_free(obj);
	break;
      case T_ARRAY:
	rb_ary_free(obj);
	break;
      case T_HASH:
	if (RANY(obj)->as.hash.ntbl) {
	    st_free_table(RANY(obj)->as.hash.ntbl);
	}
	break;
      case T_REGEXP:
	if (RANY(obj)->as.regexp.ptr) {
	    onig_free(RANY(obj)->as.regexp.ptr);
	}
	break;
      case T_DATA:
	if (DATA_PTR(obj)) {
	    int free_immediately = FALSE;

	    if (RTYPEDDATA_P(obj)) {
		free_immediately = (RANY(obj)->as.typeddata.type->flags & RUBY_TYPED_FREE_IMMEDIATELY) != 0;
		RDATA(obj)->dfree = RANY(obj)->as.typeddata.type->function.dfree;
		if (0 && free_immediately == 0) /* to expose non-free-immediate T_DATA */
		    fprintf(stderr, "not immediate -> %s\n", RANY(obj)->as.typeddata.type->wrap_struct_name);
	    }
	    if (RANY(obj)->as.data.dfree == RUBY_DEFAULT_FREE) {
		xfree(DATA_PTR(obj));
	    }
	    else if (RANY(obj)->as.data.dfree) {
		if (free_immediately) {
		    (RDATA(obj)->dfree)(DATA_PTR(obj));
		}
		else {
		    make_deferred(objspace, RANY(obj));
		    return 1;
		}
	    }
	}
	break;
      case T_MATCH:
	if (RANY(obj)->as.match.rmatch) {
            struct rmatch *rm = RANY(obj)->as.match.rmatch;
	    onig_region_free(&rm->regs, 0);
            if (rm->char_offset)
		xfree(rm->char_offset);
	    xfree(rm);
	}
	break;
      case T_FILE:
	if (RANY(obj)->as.file.fptr) {
	    make_io_deferred(objspace, RANY(obj));
	    return 1;
	}
	break;
      case T_RATIONAL:
      case T_COMPLEX:
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
	if (RCLASS_EXT(obj)->subclasses) {
	    rb_class_detach_subclasses(obj);
	    RCLASS_EXT(obj)->subclasses = NULL;
	}
	rb_class_remove_from_module_subclasses(obj);
	rb_class_remove_from_super_subclasses(obj);
	xfree(RANY(obj)->as.klass.ptr);
	RANY(obj)->as.klass.ptr = NULL;
	break;

      case T_FLOAT:
	break;

      case T_BIGNUM:
	if (!(RBASIC(obj)->flags & RBIGNUM_EMBED_FLAG) && RBIGNUM_DIGITS(obj)) {
	    xfree(RBIGNUM_DIGITS(obj));
	}
	break;
      case T_NODE:
	switch (nd_type(obj)) {
	  case NODE_SCOPE:
	    if (RANY(obj)->as.node.u1.tbl) {
		xfree(RANY(obj)->as.node.u1.tbl);
	    }
	    break;
	  case NODE_ARGS:
	    if (RANY(obj)->as.node.u3.args) {
		xfree(RANY(obj)->as.node.u3.args);
	    }
	    break;
	  case NODE_ALLOCA:
	    xfree(RANY(obj)->as.node.u1.node);
	    break;
	}
	break;			/* no need to free iv_tbl */

      case T_STRUCT:
	if ((RBASIC(obj)->flags & RSTRUCT_EMBED_LEN_MASK) == 0 &&
	    RANY(obj)->as.rstruct.as.heap.ptr) {
	    xfree((void *)RANY(obj)->as.rstruct.as.heap.ptr);
	}
	break;

      default:
	rb_bug("gc_sweep(): unknown data type 0x%x(%p) 0x%"PRIxVALUE,
	       BUILTIN_TYPE(obj), (void*)obj, RBASIC(obj)->flags);
    }

    return 0;
}

void
Init_heap(void)
{
    rb_objspace_t *objspace = &rb_objspace;

#if RGENGC_ESTIMATE_OLDMALLOC
    objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_min;
#endif

    heap_add_pages(objspace, heap_eden, gc_params.heap_init_slots / HEAP_OBJ_LIMIT);

    init_mark_stack(&objspace->mark_stack);

#ifdef USE_SIGALTSTACK
    {
	/* altstack of another threads are allocated in another place */
	rb_thread_t *th = GET_THREAD();
	void *tmp = th->altstack;
	th->altstack = malloc(rb_sigaltstack_size());
	free(tmp); /* free previously allocated area */
    }
#endif

    objspace->profile.invoke_time = getrusage_time();
    finalizer_table = st_init_numtable();
}

typedef int each_obj_callback(void *, void *, size_t, void *);

struct each_obj_args {
    each_obj_callback *callback;
    void *data;
};

static VALUE
objspace_each_objects(VALUE arg)
{
    size_t i;
    struct heap_page_body *last_body = 0;
    struct heap_page *page;
    RVALUE *pstart, *pend;
    rb_objspace_t *objspace = &rb_objspace;
    struct each_obj_args *args = (struct each_obj_args *)arg;

    i = 0;
    while (i < heap_pages_used) {
	while (0 < i && last_body < heap_pages_sorted[i-1]->body)              i--;
	while (i < heap_pages_used && heap_pages_sorted[i]->body <= last_body) i++;
	if (heap_pages_used <= i) break;

	page = heap_pages_sorted[i];
	last_body = page->body;

	pstart = page->start;
	pend = pstart + page->limit;

	if ((*args->callback)(pstart, pend, sizeof(RVALUE), args->data)) {
	    break;
	}
    }

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
    struct each_obj_args args;
    rb_objspace_t *objspace = &rb_objspace;
    int prev_dont_lazy_sweep = objspace->flags.dont_lazy_sweep;

    gc_rest_sweep(objspace);
    objspace->flags.dont_lazy_sweep = TRUE;

    args.callback = callback;
    args.data = data;

    if (prev_dont_lazy_sweep) {
	objspace_each_objects((VALUE)&args);
    }
    else {
	rb_ensure(objspace_each_objects, (VALUE)&args, lazy_sweep_enable, Qnil);
    }
}

struct os_each_struct {
    size_t num;
    VALUE of;
};

static int
internal_object_p(VALUE obj)
{
    RVALUE *p = (RVALUE *)obj;

    if (p->as.basic.flags) {
	switch (BUILTIN_TYPE(p)) {
	  case T_NONE:
	  case T_ICLASS:
	  case T_NODE:
	  case T_ZOMBIE:
	    break;
	  case T_CLASS:
	    if (FL_TEST(p, FL_SINGLETON))
	      break;
	  default:
	    if (!p->as.basic.klass) break;
	    return 0;
	}
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
		rb_yield(v);
		oes->num++;
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
 *     ObjectSpace.each_object([module]) {|obj| ... } -> fixnum
 *     ObjectSpace.each_object([module])              -> an_enumerator
 *
 *  Calls the block once for each living, nonimmediate object in this
 *  Ruby process. If <i>module</i> is specified, calls the block
 *  for only those classes or modules that match (or are a subclass of)
 *  <i>module</i>. Returns the number of objects found. Immediate
 *  objects (<code>Fixnum</code>s, <code>Symbol</code>s
 *  <code>true</code>, <code>false</code>, and <code>nil</code>) are
 *  never returned. In the example below, <code>each_object</code>
 *  returns both the numbers we defined and several constants defined in
 *  the <code>Math</code> module.
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

    if (argc == 0) {
	of = 0;
    }
    else {
	rb_scan_args(argc, argv, "01", &of);
    }
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
    if (!rb_obj_respond_to(block, rb_intern("call"), TRUE)) {
	rb_raise(rb_eArgError, "wrong type argument %s (should be callable)",
		 rb_obj_classname(block));
    }
}
static void
should_be_finalizable(VALUE obj)
{
    rb_check_frozen(obj);
    if (!FL_ABLE(obj)) {
	rb_raise(rb_eArgError, "cannot define finalizer for %s",
		 rb_obj_classname(obj));
    }
}

/*
 *  call-seq:
 *     ObjectSpace.define_finalizer(obj, aProc=proc())
 *
 *  Adds <i>aProc</i> as a finalizer, to be called after <i>obj</i>
 *  was destroyed.
 *
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

    return define_final0(obj, block);
}

static VALUE
define_final0(VALUE obj, VALUE block)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE table;
    st_data_t data;

    RBASIC(obj)->flags |= FL_FINALIZE;

    block = rb_ary_new3(2, INT2FIX(rb_safe_level()), block);
    OBJ_FREEZE(block);

    if (st_lookup(finalizer_table, obj, &data)) {
	table = (VALUE)data;
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
run_single_final(VALUE arg)
{
    VALUE *args = (VALUE *)arg;
    rb_eval_cmd(args[0], args[1], (int)args[2]);
    return Qnil;
}

static void
run_finalizer(rb_objspace_t *objspace, VALUE obj, VALUE table)
{
    long i;
    int status;
    VALUE args[3];
    VALUE objid = nonspecial_obj_id(obj);

    if (RARRAY_LEN(table) > 0) {
	args[1] = rb_obj_freeze(rb_ary_new3(1, objid));
    }
    else {
	args[1] = 0;
    }

    args[2] = (VALUE)rb_safe_level();
    for (i=0; i<RARRAY_LEN(table); i++) {
	VALUE final = RARRAY_AREF(table, i);
	args[0] = RARRAY_AREF(final, 1);
	args[2] = FIX2INT(RARRAY_AREF(final, 0));
	status = 0;
	rb_protect(run_single_final, (VALUE)args, &status);
	if (status)
	    rb_set_errinfo(Qnil);
    }
}

static void
run_final(rb_objspace_t *objspace, VALUE obj)
{
    RUBY_DATA_FUNC free_func = 0;
    st_data_t key, table;

    heap_pages_final_slots--;

    RBASIC_CLEAR_CLASS(obj);

    if (RTYPEDDATA_P(obj)) {
	free_func = RTYPEDDATA_TYPE(obj)->function.dfree;
    }
    else {
	free_func = RDATA(obj)->dfree;
    }
    if (free_func) {
	(*free_func)(DATA_PTR(obj));
    }

    key = (st_data_t)obj;
    if (st_delete(finalizer_table, &key, &table)) {
	run_finalizer(objspace, obj, (VALUE)table);
    }
}

static void
finalize_list(rb_objspace_t *objspace, RVALUE *p)
{
    while (p) {
	RVALUE *tmp = p->as.free.next;
	struct heap_page *page = GET_HEAP_PAGE(p);

	run_final(objspace, (VALUE)p);
	objspace->profile.total_freed_object_num++;

	page->final_slots--;
	heap_page_add_freeobj(objspace, GET_HEAP_PAGE(p), (VALUE)p);
	heap_pages_swept_slots++;

	p = tmp;
    }
}

static void
finalize_deferred(rb_objspace_t *objspace)
{
    RVALUE *p;

    while ((p = ATOMIC_PTR_EXCHANGE(heap_pages_deferred_final, 0)) != 0) {
	finalize_list(objspace, p);
    }
}

static void
gc_finalize_deferred(void *dmy)
{
    rb_objspace_t *objspace = &rb_objspace;
    if (ATOMIC_EXCHANGE(finalizing, 1)) return;
    finalize_deferred(objspace);
    ATOMIC_SET(finalizing, 0);
}

/* TODO: to keep compatibility, maybe unused. */
void
rb_gc_finalize_deferred(void)
{
    gc_finalize_deferred(0);
}

static void
gc_finalize_deferred_register(void)
{
    if (rb_postponed_job_register_one(0, gc_finalize_deferred, 0) == 0) {
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

void
rb_gc_call_finalizer_at_exit(void)
{
    rb_objspace_call_finalizer(&rb_objspace);
}

static void
rb_objspace_call_finalizer(rb_objspace_t *objspace)
{
    RVALUE *p, *pend;
    size_t i;

    gc_rest_sweep(objspace);

    if (ATOMIC_EXCHANGE(finalizing, 1)) return;

    /* run finalizers */
    finalize_deferred(objspace);
    assert(heap_pages_deferred_final == 0);

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

    /* finalizers are part of garbage collection */
    during_gc++;

    /* run data object's finalizers */
    for (i = 0; i < heap_pages_used; i++) {
	p = heap_pages_sorted[i]->start; pend = p + heap_pages_sorted[i]->limit;
	while (p < pend) {
	    switch (BUILTIN_TYPE(p)) {
	      case T_DATA:
		if (!DATA_PTR(p) || !RANY(p)->as.data.dfree) break;
		if (rb_obj_is_thread((VALUE)p)) break;
		if (rb_obj_is_mutex((VALUE)p)) break;
		if (rb_obj_is_fiber((VALUE)p)) break;
		p->as.free.flags = 0;
		if (RTYPEDDATA_P(p)) {
		    RDATA(p)->dfree = RANY(p)->as.typeddata.type->function.dfree;
		}
		if (RANY(p)->as.data.dfree == (RUBY_DATA_FUNC)-1) {
		    xfree(DATA_PTR(p));
		}
		else if (RANY(p)->as.data.dfree) {
		    make_deferred(objspace, RANY(p));
		}
		break;
	      case T_FILE:
		if (RANY(p)->as.file.fptr) {
		    make_io_deferred(objspace, RANY(p));
		}
		break;
	    }
	    p++;
	}
    }
    during_gc = 0;
    if (heap_pages_deferred_final) {
	finalize_list(objspace, heap_pages_deferred_final);
    }

    st_free_table(finalizer_table);
    finalizer_table = 0;
    ATOMIC_SET(finalizing, 0);
}

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
    return page->before_sweep ? FALSE : TRUE;
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

static inline int
is_dead_object(rb_objspace_t *objspace, VALUE ptr)
{
    if (!is_lazy_sweeping(heap_eden) || MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(ptr), ptr)) return FALSE;
    if (!is_swept_object(objspace, ptr)) return TRUE;
    return FALSE;
}

static inline int
is_live_object(rb_objspace_t *objspace, VALUE ptr)
{
    switch (BUILTIN_TYPE(ptr)) {
      case 0: case T_ZOMBIE:
	return FALSE;
    }
    if (is_dead_object(objspace, ptr)) return FALSE;
    return TRUE;
}

static inline int
is_markable_object(rb_objspace_t *objspace, VALUE obj)
{
    if (rb_special_const_p(obj)) return 0; /* special const is not markable */

    if (RGENGC_CHECK_MODE) {
	if (!is_pointer_to_heap(objspace, (void *)obj)) rb_bug("is_markable_object: %p is not pointer to heap", (void *)obj);
	if (BUILTIN_TYPE(obj) == T_NONE)   rb_bug("is_markable_object: %p is T_NONE", (void *)obj);
	if (BUILTIN_TYPE(obj) == T_ZOMBIE) rb_bug("is_markable_object: %p is T_ZOMBIE", (void *)obj);
    }

    return 1;
}

int
rb_objspace_markable_object_p(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;
    return is_markable_object(objspace, obj) && is_live_object(objspace, obj);
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
id2ref(VALUE obj, VALUE objid)
{
#if SIZEOF_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULONG(x)
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULL(x)
#endif
    rb_objspace_t *objspace = &rb_objspace;
    VALUE ptr;
    void *p0;

    ptr = NUM2PTR(objid);
    p0 = (void *)ptr;

    if (ptr == Qtrue) return Qtrue;
    if (ptr == Qfalse) return Qfalse;
    if (ptr == Qnil) return Qnil;
    if (FIXNUM_P(ptr)) return (VALUE)ptr;
    if (FLONUM_P(ptr)) return (VALUE)ptr;
    ptr = obj_id_to_ref(objid);

    if ((ptr % sizeof(RVALUE)) == (4 << 2)) {
        ID symid = ptr / sizeof(RVALUE);
        if (rb_id2name(symid) == 0)
	    rb_raise(rb_eRangeError, "%p is not symbol id value", p0);
	return ID2SYM(symid);
    }

    if (!is_id_value(objspace, ptr)) {
	rb_raise(rb_eRangeError, "%p is not id value", p0);
    }
    if (!is_live_object(objspace, ptr)) {
	rb_raise(rb_eRangeError, "%p is recycled object", p0);
    }
    return (VALUE)ptr;
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
 *  The same number will be returned on all calls to +id+ for a given object,
 *  and no two active objects will share an id.
 *
 *  Object#object_id is a different concept from the +:name+ notation, which
 *  returns the symbol id of +name+.
 *
 *  Replaces the deprecated Object#id.
 */

/*
 *  call-seq:
 *     obj.hash    -> fixnum
 *
 *  Generates a Fixnum hash value for this object.
 *
 *  This function must have the property that <code>a.eql?(b)</code> implies
 *  <code>a.hash == b.hash</code>.
 *
 *  The hash value is used by Hash class.
 *
 *  Any hash value that exceeds the capacity of a Fixnum will be truncated
 *  before being used.
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
    if (SYMBOL_P(obj)) {
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
    return nonspecial_obj_id(obj);
}

size_t rb_str_memsize(VALUE);
size_t rb_ary_memsize(VALUE);
size_t rb_io_memsize(const rb_io_t *);
size_t rb_generic_ivar_memsize(VALUE);
#include "regint.h"

static size_t
obj_memsize_of(VALUE obj, int use_tdata)
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
	if (!(RBASIC(obj)->flags & ROBJECT_EMBED) &&
	    ROBJECT(obj)->as.heap.ivptr) {
	    size += ROBJECT(obj)->as.heap.numiv * sizeof(VALUE);
	}
	break;
      case T_MODULE:
      case T_CLASS:
	if (RCLASS_M_TBL_WRAPPER(obj)) {
	    size += sizeof(struct method_table_wrapper);
	}
	if (RCLASS_M_TBL(obj)) {
	    size += st_memsize(RCLASS_M_TBL(obj));
	}
	if (RCLASS_EXT(obj)) {
	    if (RCLASS_IV_TBL(obj)) {
		size += st_memsize(RCLASS_IV_TBL(obj));
	    }
	    if (RCLASS_IV_INDEX_TBL(obj)) {
		size += st_memsize(RCLASS_IV_INDEX_TBL(obj));
	    }
	    if (RCLASS(obj)->ptr->iv_tbl) {
		size += st_memsize(RCLASS(obj)->ptr->iv_tbl);
	    }
	    if (RCLASS(obj)->ptr->const_tbl) {
		size += st_memsize(RCLASS(obj)->ptr->const_tbl);
	    }
	    size += sizeof(rb_classext_t);
	}
	break;
      case T_STRING:
	size += rb_str_memsize(obj);
	break;
      case T_ARRAY:
	size += rb_ary_memsize(obj);
	break;
      case T_HASH:
	if (RHASH(obj)->ntbl) {
	    size += st_memsize(RHASH(obj)->ntbl);
	}
	break;
      case T_REGEXP:
	if (RREGEXP(obj)->ptr) {
	    size += onig_memsize(RREGEXP(obj)->ptr);
	}
	break;
      case T_DATA:
	if (use_tdata) size += rb_objspace_data_type_memsize(obj);
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
      case T_ICLASS:
	/* iClass shares table with the module */
	break;

      case T_FLOAT:
	break;

      case T_BIGNUM:
	if (!(RBASIC(obj)->flags & RBIGNUM_EMBED_FLAG) && RBIGNUM_DIGITS(obj)) {
	    size += RBIGNUM_LEN(obj) * sizeof(BDIGIT);
	}
	break;
      case T_NODE:
	switch (nd_type(obj)) {
	  case NODE_SCOPE:
	    if (RNODE(obj)->u1.tbl) {
		/* TODO: xfree(RANY(obj)->as.node.u1.tbl); */
	    }
	    break;
	  case NODE_ALLOCA:
	    /* TODO: xfree(RANY(obj)->as.node.u1.node); */
	    ;
	}
	break;			/* no need to free iv_tbl */

      case T_STRUCT:
	if ((RBASIC(obj)->flags & RSTRUCT_EMBED_LEN_MASK) == 0 &&
	    RSTRUCT(obj)->as.heap.ptr) {
	    size += sizeof(VALUE) * RSTRUCT_LEN(obj);
	}
	break;

      case T_ZOMBIE:
	break;

      default:
	rb_bug("objspace/memsize_of(): unknown data type 0x%x(%p)",
	       BUILTIN_TYPE(obj), (void*)obj);
    }

    return size;
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

/*
 *  call-seq:
 *     ObjectSpace.count_objects([result_hash]) -> hash
 *
 *  Counts objects for each type.
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
 *  If the optional argument +result_hash+ is given,
 *  it is overwritten and returned. This is intended to avoid probe effect.
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
    VALUE hash;

    if (rb_scan_args(argc, argv, "01", &hash) == 1) {
        if (!RB_TYPE_P(hash, T_HASH))
            rb_raise(rb_eTypeError, "non-hash given");
    }

    for (i = 0; i <= T_MASK; i++) {
        counts[i] = 0;
    }

    for (i = 0; i < heap_pages_used; i++) {
	struct heap_page *page = heap_pages_sorted[i];
	RVALUE *p, *pend;

	p = page->start; pend = p + page->limit;
	for (;p < pend; p++) {
	    if (p->as.basic.flags) {
		counts[BUILTIN_TYPE(p)]++;
	    }
	    else {
		freed++;
	    }
	}
	total += page->limit;
    }

    if (hash == Qnil) {
        hash = rb_hash_new();
    }
    else if (!RHASH_EMPTY_P(hash)) {
        st_foreach(RHASH_TBL_RAW(hash), set_zero, hash);
    }
    rb_hash_aset(hash, ID2SYM(rb_intern("TOTAL")), SIZET2NUM(total));
    rb_hash_aset(hash, ID2SYM(rb_intern("FREE")), SIZET2NUM(freed));

    for (i = 0; i <= T_MASK; i++) {
        VALUE type;
        switch (i) {
#define COUNT_TYPE(t) case (t): type = ID2SYM(rb_intern(#t)); break;
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
	    COUNT_TYPE(T_UNDEF);
	    COUNT_TYPE(T_NODE);
	    COUNT_TYPE(T_ICLASS);
	    COUNT_TYPE(T_ZOMBIE);
#undef COUNT_TYPE
          default:              type = INT2NUM(i); break;
        }
        if (counts[i])
            rb_hash_aset(hash, type, SIZET2NUM(counts[i]));
    }

    return hash;
}

/*
  ------------------------ Garbage Collection ------------------------
*/

/* Sweeping */

static VALUE
lazy_sweep_enable(void)
{
    rb_objspace_t *objspace = &rb_objspace;

    objspace->flags.dont_lazy_sweep = FALSE;
    return Qnil;
}

static size_t
objspace_live_slot(rb_objspace_t *objspace)
{
    return objspace->profile.total_allocated_object_num - objspace->profile.total_freed_object_num;
}

static size_t
objspace_total_slot(rb_objspace_t *objspace)
{
    return heap_eden->total_slots + heap_tomb->total_slots;
}

static size_t
objspace_free_slot(rb_objspace_t *objspace)
{
    return objspace_total_slot(objspace) - (objspace_live_slot(objspace) - heap_pages_final_slots);
}

static void
gc_setup_mark_bits(struct heap_page *page)
{
#if USE_RGENGC
    /* copy oldgen bitmap to mark bitmap */
    memcpy(&page->mark_bits[0], &page->oldgen_bits[0], HEAP_BITMAP_SIZE);
#else
    /* clear mark bitmap */
    memset(&page->mark_bits[0], 0, HEAP_BITMAP_SIZE);
#endif
}

static inline void
gc_page_sweep(rb_objspace_t *objspace, rb_heap_t *heap, struct heap_page *sweep_page)
{
    int i;
    size_t empty_slots = 0, freed_slots = 0, final_slots = 0;
    RVALUE *p, *pend,*offset;
    bits_t *bits, bitset;

    rgengc_report(1, objspace, "page_sweep: start.\n");

    sweep_page->before_sweep = 0;

    p = sweep_page->start; pend = p + sweep_page->limit;
    offset = p - NUM_IN_PAGE(p);
    bits = sweep_page->mark_bits;

    /* create guard : fill 1 out-of-range */
    bits[BITMAP_INDEX(p)] |= BITMAP_BIT(p)-1;
    bits[BITMAP_INDEX(pend)] |= ~(BITMAP_BIT(pend) - 1);

    for (i=0; i < HEAP_BITMAP_LIMIT; i++) {
	bitset = ~bits[i];
	if (bitset) {
	    p = offset  + i * BITS_BITLENGTH;
	    do {
		if ((bitset & 1) && BUILTIN_TYPE(p) != T_ZOMBIE) {
		    if (p->as.basic.flags) {
			rgengc_report(3, objspace, "page_sweep: free %p (%s)\n", p, obj_type_name((VALUE)p));
#if USE_RGENGC && RGENGC_CHECK_MODE
			if (objspace->rgengc.during_minor_gc && RVALUE_OLD_P((VALUE)p)) rb_bug("page_sweep: %p (%s) is old while minor GC.\n", p, obj_type_name((VALUE)p));
			if (rgengc_remembered(objspace, (VALUE)p)) rb_bug("page_sweep: %p (%s) is remembered.\n", p, obj_type_name((VALUE)p));
#endif
			if (obj_free(objspace, (VALUE)p)) {
			    final_slots++;
			}
			else if (FL_TEST(p, FL_FINALIZE)) {
			    RDATA(p)->dfree = 0;
			    make_deferred(objspace,p);
			    final_slots++;
			}
			else {
			    (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
			    heap_page_add_freeobj(objspace, sweep_page, (VALUE)p);
			    rgengc_report(3, objspace, "page_sweep: %p (%s) is added to freelist\n", p, obj_type_name((VALUE)p));
			    freed_slots++;
			}
		    }
		    else {
			empty_slots++;
		    }
		}
		p++;
		bitset >>= 1;
	    } while (bitset);
	}
    }

    gc_setup_mark_bits(sweep_page);

#if GC_PROFILE_MORE_DETAIL
    if (gc_prof_enabled(objspace)) {
	gc_profile_record *record = gc_prof_record(objspace);
	record->removing_objects += final_slots + freed_slots;
	record->empty_objects += empty_slots;
    }
#endif

    if (final_slots + freed_slots + empty_slots == sweep_page->limit) {
	/* there are no living objects -> move this page to tomb heap */
	heap_unlink_page(objspace, heap, sweep_page);
	heap_add_page(objspace, heap_tomb, sweep_page);
    }
    else {
	if (freed_slots + empty_slots > 0) {
	    heap_add_freepage(objspace, heap, sweep_page);
	}
	else {
	    sweep_page->free_next = NULL;
	}
    }
    heap_pages_swept_slots += freed_slots + empty_slots;
    objspace->profile.total_freed_object_num += freed_slots;
    heap_pages_final_slots += final_slots;
    sweep_page->final_slots = final_slots;

    if (0) fprintf(stderr, "gc_page_sweep(%d): freed?: %d, limt: %d, freed_slots: %d, empty_slots: %d, final_slots: %d\n",
		   (int)rb_gc_count(),
		   final_slots + freed_slots + empty_slots == sweep_page->limit,
		   (int)sweep_page->limit, (int)freed_slots, (int)empty_slots, (int)final_slots);

    if (heap_pages_deferred_final && !finalizing) {
        rb_thread_t *th = GET_THREAD();
        if (th) {
	    gc_finalize_deferred_register();
        }
    }

    rgengc_report(1, objspace, "page_sweep: end.\n");
}

/* allocate additional minimum page to work */
static void
gc_heap_prepare_minimum_pages(rb_objspace_t *objspace, rb_heap_t *heap)
{
    if (!heap->free_pages) {
	/* there is no free after page_sweep() */
	heap_set_increment(objspace, 0);
	if (!heap_increment(objspace, heap)) { /* can't allocate additional free objects */
	    during_gc = 0;
	    rb_memerror();
	}
    }
}

static void
gc_before_heap_sweep(rb_objspace_t *objspace, rb_heap_t *heap)
{
    heap->sweep_pages = heap->pages;
    heap->free_pages = NULL;

    if (heap->using_page) {
	RVALUE **p = &heap->using_page->freelist;
	while (*p) {
	    p = &(*p)->as.free.next;
	}
	*p = heap->freelist;
	heap->using_page = NULL;
    }
    heap->freelist = NULL;
}

#if defined(__GNUC__) && __GNUC__ == 4 && __GNUC_MINOR__ == 4
__attribute__((noinline))
#endif
static void
gc_before_sweep(rb_objspace_t *objspace)
{
    rb_heap_t *heap;
    size_t total_limit_slot;

    rgengc_report(1, objspace, "gc_before_sweep\n");

    /* sweep unlinked method entries */
    if (GET_VM()->unlinked_method_entry_list) {
	rb_sweep_method_entry(GET_VM());
    }

    heap_pages_swept_slots = 0;
    total_limit_slot = objspace_total_slot(objspace);

    heap_pages_min_free_slots = (size_t)(total_limit_slot * 0.30);
    if (heap_pages_min_free_slots < gc_params.heap_free_slots) {
	heap_pages_min_free_slots = gc_params.heap_free_slots;
    }
    heap_pages_max_free_slots = (size_t)(total_limit_slot * 0.80);
    if (heap_pages_max_free_slots < gc_params.heap_init_slots) {
	heap_pages_max_free_slots = gc_params.heap_init_slots;
    }
    if (0) fprintf(stderr, "heap_pages_min_free_slots: %d, heap_pages_max_free_slots: %d\n",
		   (int)heap_pages_min_free_slots, (int)heap_pages_max_free_slots);

    heap = heap_eden;
    gc_before_heap_sweep(objspace, heap);

    gc_prof_set_malloc_info(objspace);

    /* reset malloc info */
    if (0) fprintf(stderr, "%d\t%d\t%d\n", (int)rb_gc_count(), (int)malloc_increase, (int)malloc_limit);

    {
	size_t inc = ATOMIC_SIZE_EXCHANGE(malloc_increase, 0);
	size_t old_limit = malloc_limit;

	if (inc > malloc_limit) {
	    malloc_limit = (size_t)(inc * gc_params.malloc_limit_growth_factor);
	    if (gc_params.malloc_limit_max > 0 && /* ignore max-check if 0 */
		malloc_limit > gc_params.malloc_limit_max) {
		malloc_limit = inc;
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
    if (objspace->rgengc.during_minor_gc) {
	if (objspace->rgengc.oldmalloc_increase > objspace->rgengc.oldmalloc_increase_limit) {
	    objspace->rgengc.need_major_gc = GPR_FLAG_MAJOR_BY_OLDMALLOC;;
	    objspace->rgengc.oldmalloc_increase_limit =
	      (size_t)(objspace->rgengc.oldmalloc_increase_limit * gc_params.oldmalloc_limit_growth_factor);

	    if (objspace->rgengc.oldmalloc_increase_limit > gc_params.oldmalloc_limit_max) {
		objspace->rgengc.oldmalloc_increase_limit = gc_params.oldmalloc_limit_max;
	    }
	}

	if (0) fprintf(stderr, "%d\t%d\t%u\t%u\t%d\n", (int)rb_gc_count(), objspace->rgengc.need_major_gc,
		       (unsigned int)objspace->rgengc.oldmalloc_increase,
		       (unsigned int)objspace->rgengc.oldmalloc_increase_limit,
		       (unsigned int)gc_params.oldmalloc_limit_max);
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

static void
gc_after_sweep(rb_objspace_t *objspace)
{
    rb_heap_t *heap = heap_eden;

    rgengc_report(1, objspace, "after_gc_sweep: heap->total_slots: %d, heap->swept_slots: %d, min_free_slots: %d\n",
		  (int)heap->total_slots, (int)heap_pages_swept_slots, (int)heap_pages_min_free_slots);

    if (heap_pages_swept_slots < heap_pages_min_free_slots) {
	heap_set_increment(objspace, (heap_pages_min_free_slots - heap_pages_swept_slots) / HEAP_OBJ_LIMIT);
	heap_increment(objspace, heap);

#if USE_RGENGC
	if (objspace->rgengc.remembered_shady_object_count + objspace->rgengc.old_object_count > (heap_pages_length * HEAP_OBJ_LIMIT) / 2) {
	    /* if [old]+[remembered shady] > [all object count]/2, then do major GC */
	    objspace->rgengc.need_major_gc = GPR_FLAG_MAJOR_BY_RESCAN;
	}
#endif
    }

    gc_prof_set_heap_info(objspace);

    heap_pages_free_unused_pages(objspace);

    /* if heap_pages has unused pages, then assign them to increment */
    if (heap_pages_increment < heap_tomb->page_length) {
	heap_pages_increment = heap_tomb->page_length;
	heap_pages_expand_sorted(objspace);
    }

#if RGENGC_PROFILE > 0
    if (0) {
	fprintf(stderr, "%d\t%d\t%d\t%d\t%d\t%d\t%d\n",
		(int)rb_gc_count(),
		(int)objspace->profile.major_gc_count,
		(int)objspace->profile.minor_gc_count,
		(int)objspace->profile.promote_infant_count,
#if RGENGC_THREEGEN
		(int)objspace->profile.promote_young_count,
#else
		0,
#endif
		(int)objspace->profile.remembered_normal_object_count,
		(int)objspace->rgengc.remembered_shady_object_count);
    }
#endif

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_END_SWEEP, 0);
}

static int
gc_heap_lazy_sweep(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page = heap->sweep_pages, *next;
    int result = FALSE;

    if (page == NULL) return FALSE;

#if GC_ENABLE_LAZY_SWEEP
    gc_prof_sweep_timer_start(objspace);
#endif

    while (page) {
	heap->sweep_pages = next = page->next;

	gc_page_sweep(objspace, heap, page);

	if (!next) gc_after_sweep(objspace);

	if (heap->free_pages) {
            result = TRUE;
	    break;
        }

	page = next;
    }

#if GC_ENABLE_LAZY_SWEEP
    gc_prof_sweep_timer_stop(objspace);
#endif

    return result;
}

static void
gc_heap_rest_sweep(rb_objspace_t *objspace, rb_heap_t *heap)
{
    if (is_lazy_sweeping(heap)) {
	during_gc++;
	while (is_lazy_sweeping(heap)) {
	    gc_heap_lazy_sweep(objspace, heap);
	}
	during_gc = 0;
    }
}

static void
gc_rest_sweep(rb_objspace_t *objspace)
{
    rb_heap_t *heap = heap_eden; /* lazy sweep only for eden */
    gc_heap_rest_sweep(objspace, heap);
}

static void
gc_sweep(rb_objspace_t *objspace, int immediate_sweep)
{
    if (immediate_sweep) {
#if !GC_ENABLE_LAZY_SWEEP
	gc_prof_sweep_timer_start(objspace);
#endif
	gc_before_sweep(objspace);
	gc_heap_rest_sweep(objspace, heap_eden);
#if !GC_ENABLE_LAZY_SWEEP
	gc_prof_sweep_timer_stop(objspace);
#endif
    }
    else {
	struct heap_page *page;
	gc_before_sweep(objspace);
	page = heap_eden->sweep_pages;
	while (page) {
	    page->before_sweep = 1;
	    page = page->next;
	}
	gc_heap_lazy_sweep(objspace, heap_eden);
    }

    gc_heap_prepare_minimum_pages(objspace, heap_eden);
}

/* Marking - Marking stack */

static void push_mark_stack(mark_stack_t *, VALUE);
static int pop_mark_stack(mark_stack_t *, VALUE *);
static void shrink_stack_chunk_cache(mark_stack_t *stack);

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

    assert(stack->index == stack->limit);
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
    assert(stack->index == 0);
    add_stack_chunk_cache(stack, stack->chunk);
    stack->chunk = prev;
    stack->index = stack->limit;
}

#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
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
#endif

static void
push_mark_stack(mark_stack_t *stack, VALUE data)
{
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

static void
init_mark_stack(mark_stack_t *stack)
{
    int i;

    if (0) push_mark_stack_chunk(stack);
    stack->index = stack->limit = STACK_CHUNK_SIZE;

    for (i=0; i < 4; i++) {
        add_stack_chunk_cache(stack, stack_chunk_alloc());
    }
    stack->unused_cache_size = stack->cache_size;
}

/* Marking */

#ifdef __ia64
#define SET_STACK_END (SET_MACHINE_STACK_END(&th->machine_stack_end), th->machine_register_stack_end = rb_ia64_bsp())
#else
#define SET_STACK_END SET_MACHINE_STACK_END(&th->machine_stack_end)
#endif

#define STACK_START (th->machine_stack_start)
#define STACK_END (th->machine_stack_end)
#define STACK_LEVEL_MAX (th->machine_stack_maxsize/sizeof(VALUE))

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
    rb_thread_t *th = GET_THREAD();
    SET_STACK_END;
    if (p) *p = STACK_UPPER(STACK_END, STACK_START, STACK_END);
    return STACK_LENGTH;
}

#if !(defined(POSIX_SIGNAL) && defined(SIGSEGV) && defined(HAVE_SIGALTSTACK))
static int
stack_check(int water_mark)
{
    int ret;
    rb_thread_t *th = GET_THREAD();
    SET_STACK_END;
    ret = STACK_LENGTH > STACK_LEVEL_MAX - water_mark;
#ifdef __ia64
    if (!ret) {
        ret = (VALUE*)rb_ia64_bsp() - th->machine_register_stack_start >
              th->machine_register_stack_maxsize/sizeof(VALUE) - water_mark;
    }
#endif
    return ret;
}
#endif

#define STACKFRAME_FOR_CALL_CFUNC 512

int
ruby_stack_check(void)
{
#if defined(POSIX_SIGNAL) && defined(SIGSEGV) && defined(HAVE_SIGALTSTACK)
    return 0;
#else
    return stack_check(STACKFRAME_FOR_CALL_CFUNC);
#endif
}

ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS
static void
mark_locations_array(rb_objspace_t *objspace, register VALUE *x, register long n)
{
    VALUE v;
    while (n--) {
        v = *x;
	gc_mark_maybe(objspace, v);
	x++;
    }
}

static void
gc_mark_locations(rb_objspace_t *objspace, VALUE *start, VALUE *end)
{
    long n;

    if (end <= start) return;
    n = end - start;
    mark_locations_array(objspace, start, n);
}

void
rb_gc_mark_locations(VALUE *start, VALUE *end)
{
    gc_mark_locations(&rb_objspace, start, end);
}

#define rb_gc_mark_locations(start, end) gc_mark_locations(objspace, (start), (end))

struct mark_tbl_arg {
    rb_objspace_t *objspace;
};

static int
mark_entry(st_data_t key, st_data_t value, st_data_t data)
{
    struct mark_tbl_arg *arg = (void*)data;
    gc_mark(arg->objspace, (VALUE)value);
    return ST_CONTINUE;
}

static void
mark_tbl(rb_objspace_t *objspace, st_table *tbl)
{
    struct mark_tbl_arg arg;
    if (!tbl || tbl->num_entries == 0) return;
    arg.objspace = objspace;
    st_foreach(tbl, mark_entry, (st_data_t)&arg);
}

static int
mark_key(st_data_t key, st_data_t value, st_data_t data)
{
    struct mark_tbl_arg *arg = (void*)data;
    gc_mark(arg->objspace, (VALUE)key);
    return ST_CONTINUE;
}

static void
mark_set(rb_objspace_t *objspace, st_table *tbl)
{
    struct mark_tbl_arg arg;
    if (!tbl) return;
    arg.objspace = objspace;
    st_foreach(tbl, mark_key, (st_data_t)&arg);
}

void
rb_mark_set(st_table *tbl)
{
    mark_set(&rb_objspace, tbl);
}

static int
mark_keyvalue(st_data_t key, st_data_t value, st_data_t data)
{
    struct mark_tbl_arg *arg = (void*)data;
    gc_mark(arg->objspace, (VALUE)key);
    gc_mark(arg->objspace, (VALUE)value);
    return ST_CONTINUE;
}

static void
mark_hash(rb_objspace_t *objspace, st_table *tbl)
{
    struct mark_tbl_arg arg;
    if (!tbl) return;
    arg.objspace = objspace;
    st_foreach(tbl, mark_keyvalue, (st_data_t)&arg);
}

void
rb_mark_hash(st_table *tbl)
{
    mark_hash(&rb_objspace, tbl);
}

static void
mark_method_entry(rb_objspace_t *objspace, const rb_method_entry_t *me)
{
    const rb_method_definition_t *def = me->def;

    gc_mark(objspace, me->klass);
  again:
    if (!def) return;
    switch (def->type) {
      case VM_METHOD_TYPE_ISEQ:
	gc_mark(objspace, def->body.iseq->self);
	break;
      case VM_METHOD_TYPE_BMETHOD:
	gc_mark(objspace, def->body.proc);
	break;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	gc_mark(objspace, def->body.attr.location);
	break;
      case VM_METHOD_TYPE_REFINED:
	if (def->body.orig_me) {
	    def = def->body.orig_me->def;
	    goto again;
	}
	break;
      default:
	break; /* ignore */
    }
}

void
rb_mark_method_entry(const rb_method_entry_t *me)
{
    mark_method_entry(&rb_objspace, me);
}

static int
mark_method_entry_i(ID key, const rb_method_entry_t *me, st_data_t data)
{
    struct mark_tbl_arg *arg = (void*)data;
    mark_method_entry(arg->objspace, me);
    return ST_CONTINUE;
}

static void
mark_m_tbl_wrapper(rb_objspace_t *objspace, struct method_table_wrapper *wrapper)
{
    struct mark_tbl_arg arg;
    if (!wrapper || !wrapper->tbl) return;
    if (LIKELY(objspace->mark_func_data == 0)) {
	/* prevent multiple marking during same GC cycle,
	 * since m_tbl is shared between several T_ICLASS */
	size_t serial = rb_gc_count();
	if (wrapper->serial == serial) return;
	wrapper->serial = serial;
    }
    arg.objspace = objspace;
    st_foreach(wrapper->tbl, mark_method_entry_i, (st_data_t)&arg);
}

static int
mark_const_entry_i(ID key, const rb_const_entry_t *ce, st_data_t data)
{
    struct mark_tbl_arg *arg = (void*)data;
    gc_mark(arg->objspace, ce->value);
    gc_mark(arg->objspace, ce->file);
    return ST_CONTINUE;
}

static void
mark_const_tbl(rb_objspace_t *objspace, st_table *tbl)
{
    struct mark_tbl_arg arg;
    if (!tbl) return;
    arg.objspace = objspace;
    st_foreach(tbl, mark_const_entry_i, (st_data_t)&arg);
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
mark_current_machine_context(rb_objspace_t *objspace, rb_thread_t *th)
{
    union {
	rb_jmp_buf j;
	VALUE v[sizeof(rb_jmp_buf) / sizeof(VALUE)];
    } save_regs_gc_mark;
    VALUE *stack_start, *stack_end;

    FLUSH_REGISTER_WINDOWS;
    /* This assumes that all registers are saved into the jmp_buf (and stack) */
    rb_setjmp(save_regs_gc_mark.j);

    GET_STACK_BOUNDS(stack_start, stack_end, 1);

    mark_locations_array(objspace, save_regs_gc_mark.v, numberof(save_regs_gc_mark.v));

    rb_gc_mark_locations(stack_start, stack_end);
#ifdef __ia64
    rb_gc_mark_locations(th->machine_register_stack_start, th->machine_register_stack_end);
#endif
#if defined(__mc68000__)
    mark_locations_array(objspace, (VALUE*)((char*)STACK_END + 2),
			 (STACK_START - STACK_END));
#endif
}

void
rb_gc_mark_machine_stack(rb_thread_t *th)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE *stack_start, *stack_end;

    GET_STACK_BOUNDS(stack_start, stack_end, 0);
    rb_gc_mark_locations(stack_start, stack_end);
#ifdef __ia64
    rb_gc_mark_locations(th->machine_register_stack_start, th->machine_register_stack_end);
#endif
}

void
rb_mark_tbl(st_table *tbl)
{
    mark_tbl(&rb_objspace, tbl);
}

static void
gc_mark_maybe(rb_objspace_t *objspace, VALUE obj)
{
    (void)VALGRIND_MAKE_MEM_DEFINED(&obj, sizeof(obj));
    if (is_pointer_to_heap(objspace, (void *)obj)) {
	int type = BUILTIN_TYPE(obj);
	if (type != T_ZOMBIE && type != T_NONE) {
	    gc_mark(objspace, obj);
	}
    }
}

void
rb_gc_mark_maybe(VALUE obj)
{
    gc_mark_maybe(&rb_objspace, obj);
}

static inline int
gc_marked(rb_objspace_t *objspace, VALUE ptr)
{
    register bits_t *bits = GET_HEAP_MARK_BITS(ptr);
    if (MARKED_IN_BITMAP(bits, ptr)) return 1;
    return 0;
}

static inline int
gc_mark_ptr(rb_objspace_t *objspace, VALUE ptr)
{
    register bits_t *bits = GET_HEAP_MARK_BITS(ptr);
    if (gc_marked(objspace, ptr)) return 0;
    MARK_IN_BITMAP(bits, ptr);
    return 1;
}

static void
rgengc_check_relation(rb_objspace_t *objspace, VALUE obj)
{
#if USE_RGENGC
    if (objspace->rgengc.parent_object_is_old) {
	if (!RVALUE_WB_PROTECTED(obj)) {
	    if (rgengc_remember(objspace, obj)) {
		objspace->rgengc.remembered_shady_object_count++;
	    }
	}
#if RGENGC_THREEGEN
	else {
	    if (gc_marked(objspace, obj)) {
		if (!RVALUE_OLD_P(obj)) {
		    /* An object pointed from an OLD object should be OLD. */
		    rgengc_remember(objspace, obj);
		}
	    }
	    else {
		if (RVALUE_INFANT_P(obj)) {
		    RVALUE_PROMOTE_INFANT(obj);
		}
	    }
	}
#endif
    }
#endif
}

static void
gc_mark(rb_objspace_t *objspace, VALUE ptr)
{
    if (!is_markable_object(objspace, ptr)) return;

    if (LIKELY(objspace->mark_func_data == 0)) {
	rgengc_check_relation(objspace, ptr);
	if (!gc_mark_ptr(objspace, ptr)) return; /* already marked */
	push_mark_stack(&objspace->mark_stack, ptr);
    }
    else {
	objspace->mark_func_data->mark_func(ptr, objspace->mark_func_data->data);
    }
}

void
rb_gc_mark(VALUE ptr)
{
    gc_mark(&rb_objspace, ptr);
}

/* resurrect non-marked `obj' if obj is before swept */

void
rb_gc_resurrect(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;

    if (is_lazy_sweeping(heap_eden) &&
	!gc_marked(objspace, obj) &&
	!is_swept_object(objspace, obj)) {
	gc_mark_ptr(objspace, obj);
    }
}

static void
gc_mark_children(rb_objspace_t *objspace, VALUE ptr)
{
    register RVALUE *obj = RANY(ptr);

    goto marking;		/* skip */

  again:
    if (LIKELY(objspace->mark_func_data == 0)) {
	obj = RANY(ptr);
	if (!is_markable_object(objspace, ptr)) return;
	rgengc_check_relation(objspace, ptr);
	if (!gc_mark_ptr(objspace, ptr)) return;  /* already marked */
    }
    else {
	gc_mark(objspace, ptr);
	return;
    }

  marking:

#if USE_RGENGC
    check_gen_consistency((VALUE)obj);

    if (LIKELY(objspace->mark_func_data == 0)) {
	/* minor/major common */
	if (RVALUE_WB_PROTECTED(obj)) {
	    if (RVALUE_INFANT_P((VALUE)obj)) {
		/* infant -> young */
		RVALUE_PROMOTE_INFANT((VALUE)obj);
#if RGENGC_THREEGEN
		/* infant -> young */
		objspace->rgengc.young_object_count++;
		objspace->rgengc.parent_object_is_old = FALSE;
#else
		/* infant -> old */
		objspace->rgengc.old_object_count++;
		objspace->rgengc.parent_object_is_old = TRUE;
#endif
		rgengc_report(3, objspace, "gc_mark_children: promote infant -> young %p (%s).\n", (void *)obj, obj_type_name((VALUE)obj));
	    }
	    else {
		objspace->rgengc.parent_object_is_old = TRUE;

#if RGENGC_THREEGEN
		if (RVALUE_YOUNG_P((VALUE)obj)) {
		    /* young -> old */
		    RVALUE_PROMOTE_YOUNG((VALUE)obj);
		    objspace->rgengc.old_object_count++;
		    rgengc_report(3, objspace, "gc_mark_children: promote young -> old %p (%s).\n", (void *)obj, obj_type_name((VALUE)obj));
		}
		else {
#endif
		    if (!objspace->rgengc.during_minor_gc) {
			/* major/full GC */
			objspace->rgengc.old_object_count++;
		    }
#if RGENGC_THREEGEN
		}
#endif
	    }
	}
	else {
	    rgengc_report(3, objspace, "gc_mark_children: do not promote non-WB-protected %p (%s).\n", (void *)obj, obj_type_name((VALUE)obj));
	    objspace->rgengc.parent_object_is_old = FALSE;
	}
    }

    check_gen_consistency((VALUE)obj);
#endif /* USE_RGENGC */

    if (FL_TEST(obj, FL_EXIVAR)) {
	rb_mark_generic_ivar(ptr);
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_NIL:
      case T_FIXNUM:
	rb_bug("rb_gc_mark() called for broken object");
	break;

      case T_NODE:
	switch (nd_type(obj)) {
	  case NODE_IF:		/* 1,2,3 */
	  case NODE_FOR:
	  case NODE_ITER:
	  case NODE_WHEN:
	  case NODE_MASGN:
	  case NODE_RESCUE:
	  case NODE_RESBODY:
	  case NODE_CLASS:
	  case NODE_BLOCK_PASS:
	    gc_mark(objspace, (VALUE)obj->as.node.u2.node);
	    /* fall through */
	  case NODE_BLOCK:	/* 1,3 */
	  case NODE_ARRAY:
	  case NODE_DSTR:
	  case NODE_DXSTR:
	  case NODE_DREGX:
	  case NODE_DREGX_ONCE:
	  case NODE_ENSURE:
	  case NODE_CALL:
	  case NODE_DEFS:
	  case NODE_OP_ASGN1:
	    gc_mark(objspace, (VALUE)obj->as.node.u1.node);
	    /* fall through */
	  case NODE_SUPER:	/* 3 */
	  case NODE_FCALL:
	  case NODE_DEFN:
	  case NODE_ARGS_AUX:
	    ptr = (VALUE)obj->as.node.u3.node;
	    goto again;

	  case NODE_WHILE:	/* 1,2 */
	  case NODE_UNTIL:
	  case NODE_AND:
	  case NODE_OR:
	  case NODE_CASE:
	  case NODE_SCLASS:
	  case NODE_DOT2:
	  case NODE_DOT3:
	  case NODE_FLIP2:
	  case NODE_FLIP3:
	  case NODE_MATCH2:
	  case NODE_MATCH3:
	  case NODE_OP_ASGN_OR:
	  case NODE_OP_ASGN_AND:
	  case NODE_MODULE:
	  case NODE_ALIAS:
	  case NODE_VALIAS:
	  case NODE_ARGSCAT:
	    gc_mark(objspace, (VALUE)obj->as.node.u1.node);
	    /* fall through */
	  case NODE_GASGN:	/* 2 */
	  case NODE_LASGN:
	  case NODE_DASGN:
	  case NODE_DASGN_CURR:
	  case NODE_IASGN:
	  case NODE_IASGN2:
	  case NODE_CVASGN:
	  case NODE_COLON3:
	  case NODE_OPT_N:
	  case NODE_EVSTR:
	  case NODE_UNDEF:
	  case NODE_POSTEXE:
	    ptr = (VALUE)obj->as.node.u2.node;
	    goto again;

	  case NODE_HASH:	/* 1 */
	  case NODE_LIT:
	  case NODE_STR:
	  case NODE_XSTR:
	  case NODE_DEFINED:
	  case NODE_MATCH:
	  case NODE_RETURN:
	  case NODE_BREAK:
	  case NODE_NEXT:
	  case NODE_YIELD:
	  case NODE_COLON2:
	  case NODE_SPLAT:
	  case NODE_TO_ARY:
	    ptr = (VALUE)obj->as.node.u1.node;
	    goto again;

	  case NODE_SCOPE:	/* 2,3 */
	  case NODE_CDECL:
	  case NODE_OPT_ARG:
	    gc_mark(objspace, (VALUE)obj->as.node.u3.node);
	    ptr = (VALUE)obj->as.node.u2.node;
	    goto again;

	  case NODE_ARGS:	/* custom */
	    {
		struct rb_args_info *args = obj->as.node.u3.args;
		if (args) {
		    if (args->pre_init)    gc_mark(objspace, (VALUE)args->pre_init);
		    if (args->post_init)   gc_mark(objspace, (VALUE)args->post_init);
		    if (args->opt_args)    gc_mark(objspace, (VALUE)args->opt_args);
		    if (args->kw_args)     gc_mark(objspace, (VALUE)args->kw_args);
		    if (args->kw_rest_arg) gc_mark(objspace, (VALUE)args->kw_rest_arg);
		}
	    }
	    ptr = (VALUE)obj->as.node.u2.node;
	    goto again;

	  case NODE_ZARRAY:	/* - */
	  case NODE_ZSUPER:
	  case NODE_VCALL:
	  case NODE_GVAR:
	  case NODE_LVAR:
	  case NODE_DVAR:
	  case NODE_IVAR:
	  case NODE_CVAR:
	  case NODE_NTH_REF:
	  case NODE_BACK_REF:
	  case NODE_REDO:
	  case NODE_RETRY:
	  case NODE_SELF:
	  case NODE_NIL:
	  case NODE_TRUE:
	  case NODE_FALSE:
	  case NODE_ERRINFO:
	  case NODE_BLOCK_ARG:
	    break;
	  case NODE_ALLOCA:
	    mark_locations_array(objspace,
				 (VALUE*)obj->as.node.u1.value,
				 obj->as.node.u3.cnt);
	    gc_mark(objspace, (VALUE)obj->as.node.u2.node);
	    break;

	  case NODE_CREF:
	    gc_mark(objspace, obj->as.node.nd_refinements);
	    gc_mark(objspace, (VALUE)obj->as.node.nd_clss);
	    ptr = (VALUE)obj->as.node.nd_next;
	    goto again;

	  default:		/* unlisted NODE */
	    gc_mark_maybe(objspace, (VALUE)obj->as.node.u1.node);
	    gc_mark_maybe(objspace, (VALUE)obj->as.node.u2.node);
	    gc_mark_maybe(objspace, (VALUE)obj->as.node.u3.node);
	}
	return;			/* no need to mark class. */
    }

    gc_mark(objspace, obj->as.basic.klass);
    switch (BUILTIN_TYPE(obj)) {
      case T_ICLASS:
      case T_CLASS:
      case T_MODULE:
	mark_m_tbl_wrapper(objspace, RCLASS_M_TBL_WRAPPER(obj));
	if (!RCLASS_EXT(obj)) break;
	mark_tbl(objspace, RCLASS_IV_TBL(obj));
	mark_const_tbl(objspace, RCLASS_CONST_TBL(obj));
	ptr = RCLASS_SUPER((VALUE)obj);
	goto again;

      case T_ARRAY:
	if (FL_TEST(obj, ELTS_SHARED)) {
	    ptr = obj->as.array.as.heap.aux.shared;
	    goto again;
	}
	else {
	    long i, len = RARRAY_LEN(obj);
	    const VALUE *ptr = RARRAY_CONST_PTR(obj);
	    for (i=0; i < len; i++) {
		gc_mark(objspace, *ptr++);
	    }
	}
	break;

      case T_HASH:
	mark_hash(objspace, obj->as.hash.ntbl);
	ptr = obj->as.hash.ifnone;
	goto again;

      case T_STRING:
#define STR_ASSOC FL_USER3   /* copied from string.c */
	if (FL_TEST(obj, RSTRING_NOEMBED) && FL_ANY(obj, ELTS_SHARED|STR_ASSOC)) {
	    ptr = obj->as.string.as.heap.aux.shared;
	    goto again;
	}
	break;

      case T_DATA:
	if (RTYPEDDATA_P(obj)) {
	    RUBY_DATA_FUNC mark_func = obj->as.typeddata.type->function.dmark;
	    if (mark_func) (*mark_func)(DATA_PTR(obj));
	}
	else {
	    if (obj->as.data.dmark) (*obj->as.data.dmark)(DATA_PTR(obj));
	}
	break;

      case T_OBJECT:
        {
            long i, len = ROBJECT_NUMIV(obj);
	    VALUE *ptr = ROBJECT_IVPTR(obj);
            for (i  = 0; i < len; i++) {
		gc_mark(objspace, *ptr++);
            }
        }
	break;

      case T_FILE:
        if (obj->as.file.fptr) {
            gc_mark(objspace, obj->as.file.fptr->pathv);
            gc_mark(objspace, obj->as.file.fptr->tied_io_for_writing);
            gc_mark(objspace, obj->as.file.fptr->writeconv_asciicompat);
            gc_mark(objspace, obj->as.file.fptr->writeconv_pre_ecopts);
            gc_mark(objspace, obj->as.file.fptr->encs.ecopts);
            gc_mark(objspace, obj->as.file.fptr->write_lock);
        }
        break;

      case T_REGEXP:
        ptr = obj->as.regexp.src;
        goto again;

      case T_FLOAT:
      case T_BIGNUM:
	break;

      case T_MATCH:
	gc_mark(objspace, obj->as.match.regexp);
	if (obj->as.match.str) {
	    ptr = obj->as.match.str;
	    goto again;
	}
	break;

      case T_RATIONAL:
	gc_mark(objspace, obj->as.rational.num);
	ptr = obj->as.rational.den;
	goto again;

      case T_COMPLEX:
	gc_mark(objspace, obj->as.complex.real);
	ptr = obj->as.complex.imag;
	goto again;

      case T_STRUCT:
	{
	    long len = RSTRUCT_LEN(obj);
	    const VALUE *ptr = RSTRUCT_CONST_PTR(obj);

	    while (len--) {
		gc_mark(objspace, *ptr++);
	    }
	}
	break;

      default:
#if GC_DEBUG
	rb_gcdebug_print_obj_condition((VALUE)obj);
#endif
	if (BUILTIN_TYPE(obj) == T_NONE)   rb_bug("rb_gc_mark(): %p is T_NONE", (void *)obj);
	if (BUILTIN_TYPE(obj) == T_ZOMBIE) rb_bug("rb_gc_mark(): %p is T_ZOMBIE", (void *)obj);
	rb_bug("rb_gc_mark(): unknown data type 0x%x(%p) %s",
	       BUILTIN_TYPE(obj), (void *)obj,
	       is_pointer_to_heap(objspace, obj) ? "corrupted object" : "non object");
    }
}

static void
gc_mark_stacked_objects(rb_objspace_t *objspace)
{
    mark_stack_t *mstack = &objspace->mark_stack;
    VALUE obj = 0;

    if (!mstack->index) return;
    while (pop_mark_stack(mstack, &obj)) {
	if (RGENGC_CHECK_MODE > 0 && !gc_marked(objspace, obj)) {
	    rb_bug("gc_mark_stacked_objects: %p (%s) is infant, but not marked.", (void *)obj, obj_type_name(obj));
	}
        gc_mark_children(objspace, obj);
    }
    shrink_stack_chunk_cache(mstack);
}

#ifndef RGENGC_PRINT_TICK
#define RGENGC_PRINT_TICK 0
#endif
/* the following code is only for internal tuning. */

/* Source code to use RDTSC is quoted and modified from
 * http://www.mcs.anl.gov/~kazutomo/rdtsc.html
 * written by Kazutomo Yoshii <kazutomo@mcs.anl.gov>
 */

#if RGENGC_PRINT_TICK
#if defined(__GNUC__) && defined(__i386__)
typedef unsigned long long tick_t;

static inline tick_t
tick(void)
{
    unsigned long long int x;
    __asm__ __volatile__ ("rdtsc" : "=A" (x));
    return x;
}

#elif defined(__GNUC__) && defined(__x86_64__)
typedef unsigned long long tick_t;

static __inline__ tick_t
tick(void)
{
    unsigned long hi, lo;
    __asm__ __volatile__ ("rdtsc" : "=a"(lo), "=d"(hi));
    return ((unsigned long long)lo)|( ((unsigned long long)hi)<<32);
}

#elif defined(_WIN32) && defined(_MSC_VER)
#include <intrin.h>
typedef unsigned __int64 tick_t;

static inline tick_t
tick(void)
{
    return __rdtsc();
}

#else /* use clock */
typedef clock_t tick_t;
static inline tick_t
tick(void)
{
    return clock();
}
#endif

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

#endif /* RGENGC_PRINT_TICK */

static void
gc_mark_roots(rb_objspace_t *objspace, int full_mark, const char **categoryp)
{
    struct gc_list *list;
    rb_thread_t *th = GET_THREAD();
    if (categoryp) *categoryp = "xxx";

#if RGENGC_PRINT_TICK
    tick_t start_tick = tick();
    int tick_count = 0;
    const char *prev_category = 0;

    if (mark_ticks_categories[0] == 0) {
	atexit(show_mark_ticks);
    }
#endif

#if RGENGC_PRINT_TICK
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
#else /* RGENGC_PRINT_TICK */
#define MARK_CHECKPOINT_PRINT_TICK(category)
#endif

#define MARK_CHECKPOINT(category) do { \
    if (categoryp) *categoryp = category; \
    MARK_CHECKPOINT_PRINT_TICK(category); \
} while (0)

    MARK_CHECKPOINT("vm");
    SET_STACK_END;
    th->vm->self ? rb_gc_mark(th->vm->self) : rb_vm_mark(th->vm);

    MARK_CHECKPOINT("finalizers");
    mark_tbl(objspace, finalizer_table);

    MARK_CHECKPOINT("machine_context");
    mark_current_machine_context(objspace, th);

    MARK_CHECKPOINT("symbols");
#if USE_RGENGC
    objspace->rgengc.parent_object_is_old = TRUE;
    rb_gc_mark_symbols(full_mark);
    objspace->rgengc.parent_object_is_old = FALSE;
#else
    rb_gc_mark_symbols(full_mark);
#endif

    MARK_CHECKPOINT("encodings");
    rb_gc_mark_encodings();

    /* mark protected global variables */
    MARK_CHECKPOINT("global_list");
    for (list = global_List; list; list = list->next) {
	rb_gc_mark_maybe(*list->varptr);
    }

    MARK_CHECKPOINT("end_proc");
    rb_mark_end_proc();

    MARK_CHECKPOINT("global_tbl");
    rb_gc_mark_global_tbl();

    /* mark generic instance variables for special constants */
    MARK_CHECKPOINT("generic_ivars");
    rb_mark_generic_ivar_tbl();

    MARK_CHECKPOINT("parser");
    rb_gc_mark_parser();

    MARK_CHECKPOINT("live_method_entries");
    rb_gc_mark_unlinked_live_method_entries(th->vm);

    MARK_CHECKPOINT("finish");
#undef MARK_CHECKPOINT
}

static void
gc_marks_body(rb_objspace_t *objspace, int full_mark)
{
    /* start marking */
    rgengc_report(1, objspace, "gc_marks_body: start (%s)\n", full_mark ? "full" : "minor");

#if USE_RGENGC
    objspace->rgengc.parent_object_is_old = FALSE;
    objspace->rgengc.during_minor_gc = full_mark ? FALSE : TRUE;

    if (objspace->rgengc.during_minor_gc) {
	objspace->profile.minor_gc_count++;
	rgengc_rememberset_mark(objspace, heap_eden);
    }
    else {
	objspace->profile.major_gc_count++;
	rgengc_mark_and_rememberset_clear(objspace, heap_eden);
    }
#endif
    gc_mark_roots(objspace, full_mark, 0);
    gc_mark_stacked_objects(objspace);

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_END_MARK, 0);
    rgengc_report(1, objspace, "gc_marks_body: end (%s)\n", full_mark ? "full" : "minor");
}

struct verify_internal_consistency_struct {
    rb_objspace_t *objspace;
    int err_count;
    VALUE parent;
};

#if USE_RGENGC
static void
verify_internal_consistency_reachable_i(VALUE child, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;

    assert(RVALUE_OLD_P(data->parent));

    if (!RVALUE_OLD_P(child)) {
	if (!MARKED_IN_BITMAP(GET_HEAP_PAGE(data->parent)->rememberset_bits, data->parent) &&
	    !MARKED_IN_BITMAP(GET_HEAP_PAGE(child)->rememberset_bits, child)) {
	    fprintf(stderr, "verify_internal_consistency_reachable_i: WB miss %p (%s) -> %p (%s)\n",
		    (void *)data->parent, obj_type_name(data->parent),
		    (void *)child, obj_type_name(child));
	    data->err_count++;
	}
    }
}

static int
verify_internal_consistency_i(void *page_start, void *page_end, size_t stride, void *ptr)
{
    struct verify_internal_consistency_struct *data = (struct verify_internal_consistency_struct *)ptr;
    VALUE v;

    for (v = (VALUE)page_start; v != (VALUE)page_end; v += stride) {
	if (is_live_object(data->objspace, v)) {
	    if (RVALUE_OLD_P(v)) {
		data->parent = v;
		/* reachable objects from an oldgen object should be old or (young with remember) */
		rb_objspace_reachable_objects_from(v, verify_internal_consistency_reachable_i, (void *)data);
	    }
	}
    }

    return 0;
}
#endif /* USE_RGENGC */

/*
 *  call-seq:
 *     GC.verify_internal_consistency                  -> nil
 *
 *  Verify internal consistency.
 *
 *  This method is implementation specific.
 *  Now this method checks generatioanl consistency
 *  if RGenGC is supported.
 */
static VALUE
gc_verify_internal_consistency(VALUE self)
{
    struct verify_internal_consistency_struct data;
    data.objspace = &rb_objspace;
    data.err_count = 0;

#if USE_RGENGC
    {
	struct each_obj_args eo_args;
	eo_args.callback = verify_internal_consistency_i;
	eo_args.data = (void *)&data;
	objspace_each_objects((VALUE)&eo_args);
    }
#endif
    if (data.err_count != 0) {
	rb_bug("gc_verify_internal_consistency: found internal consistency.\n");
    }
    return Qnil;
}

#if RGENGC_CHECK_MODE >= 3

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
	    fprintf(stderr, "<%p@%s>", (void *)obj, obj_type_name(obj));
	}
	if (i+1 < refs->pos) fprintf(stderr, ", ");
    }
}

#if RGENGC_CHECK_MODE >= 3
static int
reflist_refered_from_machine_context(struct reflist *refs)
{
    int i;
    for (i=0; i<refs->pos; i++) {
	VALUE obj = refs->list[i];
	if (IS_ROOTSIG(obj) && strcmp(GET_ROOTSIG(obj), "machine_context") == 0) return 1;
    }
    return 0;
}
#endif

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
};

static int
allrefs_add(struct allrefs *data, VALUE obj)
{
    struct reflist *refs;

    if (st_lookup(data->references, obj, (st_data_t *)&refs)) {
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
	push_mark_stack(&data->objspace->mark_stack, obj);
    }
}

static void
allrefs_roots_i(VALUE obj, void *ptr)
{
    struct allrefs *data = (struct allrefs *)ptr;
    if (strlen(data->category) == 0) rb_bug("!!!");
    data->root_obj = MAKE_ROOTSIG(data->category);

    if (allrefs_add(data, obj)) {
	push_mark_stack(&data->objspace->mark_stack, obj);
    }
}

static st_table *
objspace_allrefs(rb_objspace_t *objspace)
{
    struct allrefs data;
    struct mark_func_data_struct mfd;
    VALUE obj;

    data.objspace = objspace;
    data.references = st_init_numtable();

    mfd.mark_func = allrefs_roots_i;
    mfd.data = &data;

    /* traverse root objects */
    objspace->mark_func_data = &mfd;
    gc_mark_roots(objspace, TRUE, &data.category);
    objspace->mark_func_data = 0;

    /* traverse rest objects reachable from root objects */
    while (pop_mark_stack(&objspace->mark_stack, &obj)) {
	rb_objspace_reachable_objects_from(data.root_obj = obj, allrefs_i, &data);
    }
    shrink_stack_chunk_cache(&objspace->mark_stack);

    return data.references;
}

static int
objspaec_allrefs_destruct_i(st_data_t key, st_data_t value, void *ptr)
{
    struct reflist *refs = (struct reflist *)value;
    reflist_destruct(refs);
    return ST_CONTINUE;
}

static void
objspace_allrefs_destruct(struct st_table *refs)
{
    st_foreach(refs, objspaec_allrefs_destruct_i, 0);
    st_free_table(refs);
}

#if RGENGC_CHECK_MODE >= 4
static int
allrefs_dump_i(st_data_t k, st_data_t v, st_data_t ptr)
{
    VALUE obj = (VALUE)k;
    struct reflist *refs = (struct reflist *)v;
    fprintf(stderr, "[allrefs_dump_i] %p (%s%s%s%s) <- ",
	    (void *)obj, obj_type_name(obj),
	    RVALUE_OLD_P(obj)        ? "[O]" : "[Y]",
	    RVALUE_WB_PROTECTED(obj) ? "[W]" : "",
	    MARKED_IN_BITMAP(GET_HEAP_REMEMBERSET_BITS(obj), obj) ? "[R]" : "");
    reflist_dump(refs);
    fprintf(stderr, "\n");
    return ST_CONTINUE;
}

static void
allrefs_dump(rb_objspace_t *objspace)
{
    fprintf(stderr, "[all refs] (size: %d)\n", (int)objspace->rgengc.allrefs_table->num_entries);
    st_foreach(objspace->rgengc.allrefs_table, allrefs_dump_i, 0);
}
#endif

#if RGENGC_CHECK_MODE >= 3
static int
gc_check_after_marks_i(st_data_t k, st_data_t v, void *ptr)
{
    VALUE obj = k;
    struct reflist *refs = (struct reflist *)v;
    rb_objspace_t *objspace = (rb_objspace_t *)ptr;

    /* object should be marked or oldgen */
    if (!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj)) {
	fprintf(stderr, "gc_check_after_marks_i: %p (%s) is not marked and not oldgen.\n", (void *)obj, obj_type_name(obj));
	fprintf(stderr, "gc_check_after_marks_i: %p is referred from ", (void *)obj);
	reflist_dump(refs);

	if (reflist_refered_from_machine_context(refs)) {
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
#endif

static void
gc_marks_check(rb_objspace_t *objspace, int (*checker_func)(ANYARGS), const char *checker_name)
{

    size_t saved_malloc_increase = objspace->malloc_params.increase;
#if RGENGC_ESTIMATE_OLDMALLOC
    size_t saved_oldmalloc_increase = objspace->rgengc.oldmalloc_increase;
#endif
    VALUE already_disabled = rb_gc_disable();

    objspace->rgengc.allrefs_table = objspace_allrefs(objspace);
    st_foreach(objspace->rgengc.allrefs_table, checker_func, (st_data_t)objspace);

    if (objspace->rgengc.error_count > 0) {
#if RGENGC_CHECK_MODE >= 4
	allrefs_dump(objspace);
#endif
	rb_bug("%s: GC has problem.", checker_name);
    }

    objspace_allrefs_destruct(objspace->rgengc.allrefs_table);
    objspace->rgengc.allrefs_table = 0;

    if (already_disabled == Qfalse) rb_gc_enable();
    objspace->malloc_params.increase = saved_malloc_increase;
#if RGENGC_ESTIMATE_OLDMALLOC
    objspace->rgengc.oldmalloc_increase = saved_oldmalloc_increase;
#endif
}

#endif /* RGENGC_CHECK_MODE >= 2 */

static void
gc_marks(rb_objspace_t *objspace, int full_mark)
{
    struct mark_func_data_struct *prev_mark_func_data;

    gc_prof_mark_timer_start(objspace);
    {
	/* setup marking */
	prev_mark_func_data = objspace->mark_func_data;
	objspace->mark_func_data = 0;

#if USE_RGENGC

#if RGENGC_CHECK_MODE >= 2
	gc_verify_internal_consistency(Qnil);
#endif
	if (full_mark == TRUE) { /* major/full GC */
	    objspace->rgengc.remembered_shady_object_count = 0;
	    objspace->rgengc.old_object_count = 0;
#if RGENGC_THREEGEN
	    objspace->rgengc.young_object_count = 0;
#endif

	    gc_marks_body(objspace, TRUE);

	    /* Do full GC if old/remembered_shady object counts is greater than counts two times at last full GC counts */
	    objspace->rgengc.remembered_shady_object_limit = objspace->rgengc.remembered_shady_object_count * 2;
	    objspace->rgengc.old_object_limit = objspace->rgengc.old_object_count * 2;
	}
	else { /* minor GC */
	    gc_marks_body(objspace, FALSE);
	}

#if RGENGC_PROFILE > 0
	if (gc_prof_record(objspace)) {
	    gc_profile_record *record = gc_prof_record(objspace);
	    record->old_objects = objspace->rgengc.old_object_count;
	}
#endif

#if RGENGC_CHECK_MODE >= 3
	gc_marks_check(objspace, gc_check_after_marks_i, "after_marks");
#endif

#else /* USE_RGENGC */
	gc_marks_body(objspace, TRUE);
#endif

	objspace->mark_func_data = prev_mark_func_data;
    }
    gc_prof_mark_timer_stop(objspace);
}

/* RGENGC */

static void
rgengc_report_body(int level, rb_objspace_t *objspace, const char *fmt, ...)
{
    if (level <= RGENGC_DEBUG) {
	char buf[1024];
	FILE *out = stderr;
	va_list args;
	const char *status = " ";

#if USE_RGENGC
	if (during_gc) {
	    status = objspace->rgengc.during_minor_gc ? "-" : "+";
	}
#endif

	va_start(args, fmt);
	vsnprintf(buf, 1024, fmt, args);
	va_end(args);

	fprintf(out, "%s|", status);
	fputs(buf, out);
    }
}

#if USE_RGENGC

/* bit operations */

static int
rgengc_remembersetbits_get(rb_objspace_t *objspace, VALUE obj)
{
    bits_t *bits = GET_HEAP_REMEMBERSET_BITS(obj);
    return MARKED_IN_BITMAP(bits, obj) ? 1 : 0;
}

static int
rgengc_remembersetbits_set(rb_objspace_t *objspace, VALUE obj)
{
    bits_t *bits = GET_HEAP_REMEMBERSET_BITS(obj);
    if (MARKED_IN_BITMAP(bits, obj)) {
	return FALSE;
    }
    else {
	MARK_IN_BITMAP(bits, obj);
	return TRUE;
    }
}

/* wb, etc */

/* return FALSE if already remembered */
static int
rgengc_remember(rb_objspace_t *objspace, VALUE obj)
{
    rgengc_report(2, objspace, "rgengc_remember: %p (%s, %s) %s\n", (void *)obj, obj_type_name(obj),
		  RVALUE_WB_PROTECTED(obj) ? "WB-protected" : "non-WB-protected",
		  rgengc_remembersetbits_get(objspace, obj) ? "was already remembered" : "is remembered now");

#if RGENGC_CHECK_MODE > 0
    {
	switch (BUILTIN_TYPE(obj)) {
	  case T_NONE:
	  case T_ZOMBIE:
	    rb_bug("rgengc_remember: should not remember %p (%s)\n",
		   (void *)obj, obj_type_name(obj));
	  default:
	    ;
	}
    }
#endif

    if (RGENGC_PROFILE) {
	if (!rgengc_remembered(objspace, obj)) {
#if RGENGC_PROFILE > 0
	    if (RVALUE_WB_PROTECTED(obj)) {
		objspace->profile.remembered_normal_object_count++;
#if RGENGC_PROFILE >= 2
		objspace->profile.remembered_normal_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
	    }
	    else {
		objspace->profile.remembered_shady_object_count++;
#if RGENGC_PROFILE >= 2
		objspace->profile.remembered_shady_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
	    }
#endif /* RGENGC_PROFILE > 0 */
	}
    }

    return rgengc_remembersetbits_set(objspace, obj);
}

static int
rgengc_remembered(rb_objspace_t *objspace, VALUE obj)
{
    int result = rgengc_remembersetbits_get(objspace, obj);
    check_gen_consistency(obj);
    rgengc_report(6, objspace, "gc_remembered: %p (%s) => %d\n", (void *)obj, obj_type_name(obj), result);
    return result;
}

static void
rgengc_rememberset_mark(rb_objspace_t *objspace, rb_heap_t *heap)
{
    size_t j;
    RVALUE *p, *offset;
    bits_t *bits, bitset;
    struct heap_page *page = heap->pages;

#if RGENGC_PROFILE > 0
    size_t shady_object_count = 0, clear_count = 0;
#endif

    while (page) {
	p = page->start;
	bits = page->rememberset_bits;
	offset = p - NUM_IN_PAGE(p);

	for (j=0; j < HEAP_BITMAP_LIMIT; j++) {
	    if (bits[j]) {
		p = offset  + j * BITS_BITLENGTH;
		bitset = bits[j];
		do {
		    if (bitset & 1) {
			/* mark before RVALUE_PROMOTE_... */
			gc_mark_ptr(objspace, (VALUE)p);

			if (RVALUE_WB_PROTECTED(p)) {
			    rgengc_report(2, objspace, "rgengc_rememberset_mark: clear %p (%s)\n", p, obj_type_name((VALUE)p));
#if RGENGC_THREEGEN
			    if (RVALUE_INFANT_P((VALUE)p)) RVALUE_PROMOTE_INFANT((VALUE)p);
			    if (RVALUE_YOUNG_P((VALUE)p)) RVALUE_PROMOTE_YOUNG((VALUE)p);
#endif
			    CLEAR_IN_BITMAP(bits, p);
#if RGENGC_PROFILE > 0
			    clear_count++;
#endif
			}
			else {
#if RGENGC_PROFILE > 0
			    shady_object_count++;
#endif
			}

			rgengc_report(2, objspace, "rgengc_rememberset_mark: mark %p (%s)\n", p, obj_type_name((VALUE)p));
			gc_mark_children(objspace, (VALUE) p);
		    }
		    p++;
		    bitset >>= 1;
		} while (bitset);
	    }
	}
	page = page->next;
    }

    rgengc_report(2, objspace, "rgengc_rememberset_mark: finished\n");

#if RGENGC_PROFILE > 0
    rgengc_report(2, objspace, "rgengc_rememberset_mark: clear_count: %"PRIdSIZE", shady_object_count: %"PRIdSIZE"\n", clear_count, shady_object_count);
    if (gc_prof_record(objspace)) {
	gc_profile_record *record = gc_prof_record(objspace);
	record->remembered_normal_objects = clear_count;
	record->remembered_shady_objects = shady_object_count;
    }
#endif
}

static void
rgengc_mark_and_rememberset_clear(rb_objspace_t *objspace, rb_heap_t *heap)
{
    struct heap_page *page = heap->pages;

    while (page) {
	memset(&page->mark_bits[0],        0, HEAP_BITMAP_SIZE);
	memset(&page->rememberset_bits[0], 0, HEAP_BITMAP_SIZE);
	page = page->next;
    }
}

/* RGENGC: APIs */

void
rb_gc_writebarrier(VALUE a, VALUE b)
{
    if (RGENGC_CHECK_MODE) {
	if (!RVALUE_PROMOTED_P(a)) rb_bug("rb_gc_writebarrier: referer object %p (%s) is not promoted.\n", (void *)a, obj_type_name(a));
    }

    if (!RVALUE_OLD_P(b) && RVALUE_OLD_BITMAP_P(a)) {
	rb_objspace_t *objspace = &rb_objspace;

	if (!rgengc_remembered(objspace, a)) {
	    int type = BUILTIN_TYPE(a);
	    /* TODO: 2 << 16 is just a magic number. */
	    if ((type == T_ARRAY && RARRAY_LEN(a) >= 2 << 16) ||
		(type == T_HASH  && RHASH_SIZE(a) >= 2 << 16)) {
		if (!rgengc_remembered(objspace, b)) {
		    rgengc_report(2, objspace, "rb_gc_wb: %p (%s) -> %p (%s)\n", (void *)a, obj_type_name(a), (void *)b, obj_type_name(b));
		    rgengc_remember(objspace, b);
		}
	    }
	    else {
		rgengc_report(2, objspace, "rb_gc_wb: %p (%s) -> %p (%s)\n",
			      (void *)a, obj_type_name(a), (void *)b, obj_type_name(b));
		rgengc_remember(objspace, a);
	    }
	}
    }
}

void
rb_gc_writebarrier_unprotect_promoted(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;

    if (RGENGC_CHECK_MODE) {
	if (!RVALUE_PROMOTED_P(obj)) rb_bug("rb_gc_writebarrier_unprotect_promoted: called on non-promoted object");
	if (!RVALUE_WB_PROTECTED(obj)) rb_bug("rb_gc_writebarrier_unprotect_promoted: called on shady object");
    }

    rgengc_report(0, objspace, "rb_gc_writebarrier_unprotect_promoted: %p (%s)%s\n", (void *)obj, obj_type_name(obj),
		  rgengc_remembered(objspace, obj) ? " (already remembered)" : "");

    if (RVALUE_OLD_P(obj)) {
	RVALUE_DEMOTE_FROM_OLD(obj);

	rgengc_remember(objspace, obj);
	objspace->rgengc.remembered_shady_object_count++;

#if RGENGC_PROFILE
	objspace->profile.shade_operation_count++;
#if RGENGC_PROFILE >= 2
	objspace->profile.shade_operation_count_types[BUILTIN_TYPE(obj)]++;
#endif /* RGENGC_PROFILE >= 2 */
#endif /* RGENGC_PROFILE */
    }
#if RGENGC_THREEGEN
    else {
	RVALUE_DEMOTE_FROM_YOUNG(obj);
    }
#endif
}

void
rb_gc_writebarrier_remember_promoted(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;
    rgengc_remember(objspace, obj);
}

static st_table *rgengc_unprotect_logging_table;

static int
rgengc_unprotect_logging_exit_func_i(st_data_t key, st_data_t val)
{
    fprintf(stderr, "%s\t%d\n", (char *)key, (int)val);
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

    if (OBJ_WB_PROTECTED(obj)) {
	char buff[0x100];
	st_data_t cnt = 1;
	char *ptr = buff;

	snprintf(ptr, 0x100 - 1, "%s|%s:%d", obj_type_name(obj), filename, line);

	if (st_lookup(rgengc_unprotect_logging_table, (st_data_t)ptr, &cnt)) {
	    cnt++;
	}
	else {
	    ptr = (char *)malloc(strlen(buff) + 1);
	    strcpy(ptr, buff);
	}
	st_insert(rgengc_unprotect_logging_table, (st_data_t)ptr, cnt);
    }
}

#endif /* USE_RGENGC */

/* RGENGC analysis information */

VALUE
rb_obj_rgengc_writebarrier_protected_p(VALUE obj)
{
    return OBJ_WB_PROTECTED(obj) ? Qtrue : Qfalse;
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
#if USE_RGENGC
    static ID ID_wb_protected, ID_old, ID_remembered;
#if RGENGC_THREEGEN
    static ID ID_young, ID_infant;
#endif
#endif

    if (!ID_marked) {
#define I(s) ID_##s = rb_intern(#s);
	I(marked);
#if USE_RGENGC
	I(wb_protected);
	I(old);
	I(remembered);
#if RGENGC_THREEGEN
	I(young);
	I(infant);
#endif
#endif
#undef I
    }

#if USE_RGENGC
    if (OBJ_WB_PROTECTED(obj) && n<max)
	flags[n++] = ID_wb_protected;
    if (RVALUE_OLD_P(obj) && n<max)
	flags[n++] = ID_old;
#if RGENGC_THREEGEN
    if (RVALUE_YOUNG_P(obj) && n<max)
	flags[n++] = ID_young;
    if (RVALUE_INFANT_P(obj) && n<max)
	flags[n++] = ID_infant;
#endif
    if (MARKED_IN_BITMAP(GET_HEAP_REMEMBERSET_BITS(obj), obj) && n<max)
	flags[n++] = ID_remembered;
#endif
    if (MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj) && n<max)
	flags[n++] = ID_marked;

    return n;
}

/* GC */

void
rb_gc_force_recycle(VALUE p)
{
    rb_objspace_t *objspace = &rb_objspace;

#if USE_RGENGC
    CLEAR_IN_BITMAP(GET_HEAP_REMEMBERSET_BITS(p), p);
    CLEAR_IN_BITMAP(GET_HEAP_OLDGEN_BITS(p), p);
    if (!GET_HEAP_PAGE(p)->before_sweep) {
	CLEAR_IN_BITMAP(GET_HEAP_MARK_BITS(p), p);
    }
#endif

    objspace->profile.total_freed_object_num++;
    heap_page_add_freeobj(objspace, GET_HEAP_PAGE(p), p);

    /* Disable counting swept_slots because there are no meaning.
     * if (!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(p), p)) {
     *   objspace->heap.swept_slots++;
     * }
     */
}

void
rb_gc_register_mark_object(VALUE obj)
{
    VALUE ary = GET_THREAD()->vm->mark_object_ary;
    rb_ary_push(ary, obj);
}

void
rb_gc_register_address(VALUE *addr)
{
    rb_objspace_t *objspace = &rb_objspace;
    struct gc_list *tmp;

    tmp = ALLOC(struct gc_list);
    tmp->next = global_List;
    tmp->varptr = addr;
    global_List = tmp;
}

void
rb_gc_unregister_address(VALUE *addr)
{
    rb_objspace_t *objspace = &rb_objspace;
    struct gc_list *tmp = global_List;

    if (tmp->varptr == addr) {
	global_List = tmp->next;
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

static int
garbage_collect_body(rb_objspace_t *objspace, int full_mark, int immediate_sweep, int reason)
{
    if (ruby_gc_stress && !ruby_disable_gc_stress) {
	int flag = FIXNUM_P(ruby_gc_stress) ? FIX2INT(ruby_gc_stress) : 0;

	if (flag & 0x01)
	    reason &= ~GPR_FLAG_MAJOR_MASK;
	else
	    reason |= GPR_FLAG_MAJOR_BY_STRESS;
	immediate_sweep = !(flag & 0x02);
    }
    else {
	if (!GC_ENABLE_LAZY_SWEEP || objspace->flags.dont_lazy_sweep) {
	    immediate_sweep = TRUE;
	}
#if USE_RGENGC
	if (full_mark) {
	    reason |= GPR_FLAG_MAJOR_BY_NOFREE;
	}
	if (objspace->rgengc.need_major_gc) {
	    reason |= objspace->rgengc.need_major_gc;
	    objspace->rgengc.need_major_gc = GPR_FLAG_NONE;
	}
	if (objspace->rgengc.remembered_shady_object_count > objspace->rgengc.remembered_shady_object_limit) {
	    reason |= GPR_FLAG_MAJOR_BY_SHADY;
	}
	if (objspace->rgengc.old_object_count > objspace->rgengc.old_object_limit) {
	    reason |= GPR_FLAG_MAJOR_BY_OLDGEN;
	}
#endif
    }

    if (immediate_sweep) reason |= GPR_FLAG_IMMEDIATE_SWEEP;
    full_mark = (reason & GPR_FLAG_MAJOR_MASK) ? TRUE : FALSE;

    if (GC_NOTIFY)  fprintf(stderr, "start garbage_collect(%d, %d, %d)\n", full_mark, immediate_sweep, reason);

    objspace->profile.count++;
    objspace->profile.latest_gc_info = reason;

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_START, 0 /* TODO: pass minor/immediate flag? */);

    objspace->profile.total_allocated_object_num_at_gc_start = objspace->profile.total_allocated_object_num;
    objspace->profile.heap_used_at_gc_start = heap_pages_used;

    gc_prof_setup_new_record(objspace, reason);
    gc_prof_timer_start(objspace);
    {
	if (during_gc == 0) {
	    rb_bug("during_gc should not be 0. RUBY_INTERNAL_EVENT_GC_START user should not cause GC in events.");
	}
	gc_marks(objspace, full_mark);
	gc_sweep(objspace, immediate_sweep);
	during_gc = 0;
    }
    gc_prof_timer_stop(objspace);

    if (GC_NOTIFY) fprintf(stderr, "end garbage_collect()\n");
    return TRUE;
}

static int
heap_ready_to_gc(rb_objspace_t *objspace, rb_heap_t *heap)
{
    if (dont_gc || during_gc) {
	if (!heap->freelist && !heap->free_pages) {
	    if (!heap_increment(objspace, heap)) {
		heap_set_increment(objspace, 0);
                heap_increment(objspace, heap);
            }
	}
	return FALSE;
    }
    return TRUE;
}

static int
ready_to_gc(rb_objspace_t *objspace)
{
    return heap_ready_to_gc(objspace, heap_eden);
}

static int
garbage_collect(rb_objspace_t *objspace, int full_mark, int immediate_sweep, int reason)
{
    if (!heap_pages_used) {
	during_gc = 0;
	return FALSE;
    }
    if (!ready_to_gc(objspace)) {
	during_gc = 0;
	return TRUE;
    }

#if GC_PROFILE_MORE_DETAIL
    objspace->profile.prepare_time = getrusage_time();
#endif
    gc_rest_sweep(objspace);
#if GC_PROFILE_MORE_DETAIL
    objspace->profile.prepare_time = getrusage_time() - objspace->profile.prepare_time;
#endif

    during_gc++;

    return garbage_collect_body(objspace, full_mark, immediate_sweep, reason);
}

struct objspace_and_reason {
    rb_objspace_t *objspace;
    int reason;
    int full_mark;
    int immediate_sweep;
};

static void *
gc_with_gvl(void *ptr)
{
    struct objspace_and_reason *oar = (struct objspace_and_reason *)ptr;
    return (void *)(VALUE)garbage_collect(oar->objspace, oar->full_mark, oar->immediate_sweep, oar->reason);
}

static int
garbage_collect_with_gvl(rb_objspace_t *objspace, int full_mark, int immediate_sweep, int reason)
{
    if (dont_gc) return TRUE;
    if (ruby_thread_has_gvl_p()) {
	return garbage_collect(objspace, full_mark, immediate_sweep, reason);
    }
    else {
	if (ruby_native_thread_p()) {
	    struct objspace_and_reason oar;
	    oar.objspace = objspace;
	    oar.reason = reason;
	    oar.full_mark = full_mark;
	    oar.immediate_sweep = immediate_sweep;
	    return (int)(VALUE)rb_thread_call_with_gvl(gc_with_gvl, (void *)&oar);
	}
	else {
	    /* no ruby thread */
	    fprintf(stderr, "[FATAL] failed to allocate memory\n");
	    exit(EXIT_FAILURE);
	}
    }
}

int
rb_garbage_collect(void)
{
    return garbage_collect(&rb_objspace, TRUE, TRUE, GPR_FLAG_CAPI);
}

#undef Init_stack

void
Init_stack(volatile VALUE *addr)
{
    ruby_init_stack(addr);
}

/*
 *  call-seq:
 *     GC.start                     -> nil
 *     GC.garbage_collect           -> nil
 *     ObjectSpace.garbage_collect  -> nil
 *     GC.start(full_mark: false)   -> nil
 *
 *  Initiates garbage collection, unless manually disabled.
 *
 *  This method is defined with keyword arguments that default to true:
 *
 *     def GC.start(full_mark: true, immediate_sweep: true) end
 *
 *  Use full_mark: false to perform a minor GC.
 *  Use immediate_sweep: false to defer sweeping (use lazy sweep).
 *
 *  Note: These keyword arguments are implementation and version dependent. They
 *  are not guaranteed to be future-compatible, and may be ignored if the
 *  underlying implementation does not support them.
 */

static VALUE
gc_start_internal(int argc, VALUE *argv, VALUE self)
{
    rb_objspace_t *objspace = &rb_objspace;
    int full_mark = TRUE, immediate_sweep = TRUE;
    VALUE opt = Qnil;
    static ID keyword_ids[2];

    rb_scan_args(argc, argv, "0:", &opt);

    if (!NIL_P(opt)) {
	VALUE kwvals[2];

	if (!keyword_ids[0]) {
	    keyword_ids[0] = rb_intern("full_mark");
	    keyword_ids[1] = rb_intern("immediate_sweep");
	}

	rb_get_kwargs(opt, keyword_ids, 0, 2, kwvals);

	if (kwvals[0] != Qundef)
	    full_mark = RTEST(kwvals[0]);
	if (kwvals[1] != Qundef)
	    immediate_sweep = RTEST(kwvals[1]);
    }

    garbage_collect(objspace, full_mark, immediate_sweep, GPR_FLAG_METHOD);
    if (!finalizing) finalize_deferred(objspace);

    return Qnil;
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
    garbage_collect(objspace, TRUE, TRUE, GPR_FLAG_CAPI);
    if (!finalizing) finalize_deferred(objspace);
}

int
rb_during_gc(void)
{
    rb_objspace_t *objspace = &rb_objspace;
    return during_gc;
}

#if RGENGC_PROFILE >= 2
static void
gc_count_add_each_types(VALUE hash, const char *name, const size_t *types)
{
    VALUE result = rb_hash_new();
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

/*
 *  call-seq:
 *     GC.count -> Integer
 *
 *  The number of times GC occurred.
 *
 *  It returns the number of times GC occurred since the process started.
 *
 */

static VALUE
gc_count(VALUE self)
{
    return SIZET2NUM(rb_gc_count());
}

static VALUE
gc_info_decode(int flags, VALUE hash_or_key)
{
    static VALUE sym_major_by = Qnil, sym_gc_by, sym_immediate_sweep, sym_have_finalizer;
    static VALUE sym_nofree, sym_oldgen, sym_shady, sym_rescan, sym_stress;
#if RGENGC_ESTIMATE_OLDMALLOC
    static VALUE sym_oldmalloc;
#endif
    static VALUE sym_newobj, sym_malloc, sym_method, sym_capi;
    VALUE hash = Qnil, key = Qnil;
    VALUE major_by;

    if (SYMBOL_P(hash_or_key))
	key = hash_or_key;
    else if (RB_TYPE_P(hash_or_key, T_HASH))
	hash = hash_or_key;
    else
	rb_raise(rb_eTypeError, "non-hash or symbol given");

    if (sym_major_by == Qnil) {
#define S(s) sym_##s = ID2SYM(rb_intern_const(#s))
	S(major_by);
	S(gc_by);
	S(immediate_sweep);
	S(have_finalizer);
	S(nofree);
	S(oldgen);
	S(shady);
	S(rescan);
	S(stress);
#if RGENGC_ESTIMATE_OLDMALLOC
	S(oldmalloc);
#endif
	S(newobj);
	S(malloc);
	S(method);
	S(capi);
#undef S
    }

#define SET(name, attr) \
    if (key == sym_##name) \
	return (attr); \
    else if (hash != Qnil) \
	rb_hash_aset(hash, sym_##name, (attr));

    major_by =
      (flags & GPR_FLAG_MAJOR_BY_OLDGEN) ? sym_oldgen :
      (flags & GPR_FLAG_MAJOR_BY_SHADY)  ? sym_shady :
      (flags & GPR_FLAG_MAJOR_BY_RESCAN) ? sym_rescan :
      (flags & GPR_FLAG_MAJOR_BY_STRESS) ? sym_stress :
#if RGENGC_ESTIMATE_OLDMALLOC
      (flags & GPR_FLAG_MAJOR_BY_OLDMALLOC) ? sym_oldmalloc :
#endif
      (flags & GPR_FLAG_MAJOR_BY_NOFREE) ? sym_nofree :
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
#undef SET

    if (key != Qnil) /* matched key should return above */
	rb_raise(rb_eArgError, "unknown key: %s", RSTRING_PTR(rb_id2str(SYM2ID(key))));

    return hash;
}

VALUE
rb_gc_latest_gc_info(VALUE key)
{
    rb_objspace_t *objspace = &rb_objspace;
    return gc_info_decode(objspace->profile.latest_gc_info, key);
}

/*
 *  call-seq:
 *     GC.latest_gc_info -> {:gc_by=>:newobj}
 *     GC.latest_gc_info(hash) -> hash
 *     GC.latest_gc_info(:major_by) -> :malloc
 *
 *  Returns information about the most recent garbage collection.
 */

static VALUE
gc_latest_gc_info(int argc, VALUE *argv, VALUE self)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE arg = Qnil;

    if (rb_scan_args(argc, argv, "01", &arg) == 1) {
	if (!SYMBOL_P(arg) && !RB_TYPE_P(arg, T_HASH)) {
	    rb_raise(rb_eTypeError, "non-hash or symbol given");
	}
    }

    if (arg == Qnil)
        arg = rb_hash_new();

    return gc_info_decode(objspace->profile.latest_gc_info, arg);
}

static VALUE
gc_stat_internal(VALUE hash_or_sym, size_t *out)
{
    static VALUE sym_count;
    static VALUE sym_heap_used, sym_heap_length, sym_heap_increment;
    static VALUE sym_heap_live_slot, sym_heap_free_slot, sym_heap_final_slot, sym_heap_swept_slot;
    static VALUE sym_heap_eden_page_length, sym_heap_tomb_page_length;
    static VALUE sym_total_allocated_object, sym_total_freed_object;
    static VALUE sym_malloc_increase, sym_malloc_limit;
#if USE_RGENGC
    static VALUE sym_minor_gc_count, sym_major_gc_count;
    static VALUE sym_remembered_shady_object, sym_remembered_shady_object_limit;
    static VALUE sym_old_object, sym_old_object_limit;
#if RGENGC_ESTIMATE_OLDMALLOC
    static VALUE sym_oldmalloc_increase, sym_oldmalloc_limit;
#endif
#if RGENGC_PROFILE
    static VALUE sym_generated_normal_object_count, sym_generated_shady_object_count;
    static VALUE sym_shade_operation_count, sym_promote_infant_count, sym_promote_young_count;
    static VALUE sym_remembered_normal_object_count, sym_remembered_shady_object_count;
#endif /* RGENGC_PROFILE */
#endif /* USE_RGENGC */

    rb_objspace_t *objspace = &rb_objspace;
    VALUE hash = Qnil, key = Qnil;

    if (RB_TYPE_P(hash_or_sym, T_HASH))
	hash = hash_or_sym;
    else if (SYMBOL_P(hash_or_sym) && out)
	key = hash_or_sym;
    else
	rb_raise(rb_eTypeError, "non-hash or symbol argument");

    if (sym_count == 0) {
#define S(s) sym_##s = ID2SYM(rb_intern_const(#s))
	S(count);
	S(heap_used);
	S(heap_length);
	S(heap_increment);
	S(heap_live_slot);
	S(heap_free_slot);
	S(heap_final_slot);
	S(heap_swept_slot);
	S(heap_eden_page_length);
	S(heap_tomb_page_length);
	S(total_allocated_object);
	S(total_freed_object);
	S(malloc_increase);
	S(malloc_limit);
#if USE_RGENGC
	S(minor_gc_count);
	S(major_gc_count);
	S(remembered_shady_object);
	S(remembered_shady_object_limit);
	S(old_object);
	S(old_object_limit);
#if RGENGC_ESTIMATE_OLDMALLOC
	S(oldmalloc_increase);
	S(oldmalloc_limit);
#endif
#if RGENGC_PROFILE
	S(generated_normal_object_count);
	S(generated_shady_object_count);
	S(shade_operation_count);
	S(promote_infant_count);
	S(promote_young_count);
	S(remembered_normal_object_count);
	S(remembered_shady_object_count);
#endif /* USE_RGENGC */
#endif /* RGENGC_PROFILE */
#undef S
    }

#define SET(name, attr) \
    if (key == sym_##name) \
	return (*out = attr, Qnil); \
    else if (hash != Qnil) \
	rb_hash_aset(hash, sym_##name, SIZET2NUM(attr));

    SET(count, objspace->profile.count);

    /* implementation dependent counters */
    SET(heap_used, heap_pages_used);
    SET(heap_length, heap_pages_length);
    SET(heap_increment, heap_pages_increment);
    SET(heap_live_slot, objspace_live_slot(objspace));
    SET(heap_free_slot, objspace_free_slot(objspace));
    SET(heap_final_slot, heap_pages_final_slots);
    SET(heap_swept_slot, heap_pages_swept_slots);
    SET(heap_eden_page_length, heap_eden->page_length);
    SET(heap_tomb_page_length, heap_tomb->page_length);
    SET(total_allocated_object, objspace->profile.total_allocated_object_num);
    SET(total_freed_object, objspace->profile.total_freed_object_num);
    SET(malloc_increase, malloc_increase);
    SET(malloc_limit, malloc_limit);
#if USE_RGENGC
    SET(minor_gc_count, objspace->profile.minor_gc_count);
    SET(major_gc_count, objspace->profile.major_gc_count);
    SET(remembered_shady_object, objspace->rgengc.remembered_shady_object_count);
    SET(remembered_shady_object_limit, objspace->rgengc.remembered_shady_object_limit);
    SET(old_object, objspace->rgengc.old_object_count);
    SET(old_object_limit, objspace->rgengc.old_object_limit);
#if RGENGC_ESTIMATE_OLDMALLOC
    SET(oldmalloc_increase, objspace->rgengc.oldmalloc_increase);
    SET(oldmalloc_limit, objspace->rgengc.oldmalloc_increase_limit);
#endif

#if RGENGC_PROFILE
    SET(generated_normal_object_count, objspace->profile.generated_normal_object_count);
    SET(generated_shady_object_count, objspace->profile.generated_shady_object_count);
    SET(shade_operation_count, objspace->profile.shade_operation_count);
    SET(promote_infant_count, objspace->profile.promote_infant_count);
#if RGENGC_THREEGEN
    SET(promote_young_count, objspace->profile.promote_young_count);
#endif
    SET(remembered_normal_object_count, objspace->profile.remembered_normal_object_count);
    SET(remembered_shady_object_count, objspace->profile.remembered_shady_object_count);
#endif /* RGENGC_PROFILE */
#endif /* USE_RGENGC */
#undef SET

    if (key != Qnil) /* matched key should return above */
	rb_raise(rb_eArgError, "unknown key: %s", RSTRING_PTR(rb_id2str(SYM2ID(key))));

#if defined(RGENGC_PROFILE) && RGENGC_PROFILE >= 2
    if (hash != Qnil) {
	gc_count_add_each_types(hash, "generated_normal_object_count_types", objspace->profile.generated_normal_object_count_types);
	gc_count_add_each_types(hash, "generated_shady_object_count_types", objspace->profile.generated_shady_object_count_types);
	gc_count_add_each_types(hash, "shade_operation_count_types", objspace->profile.shade_operation_count_types);
	gc_count_add_each_types(hash, "promote_infant_types", objspace->profile.promote_infant_types);
#if RGENGC_THREEGEN
	gc_count_add_each_types(hash, "promote_young_types", objspace->profile.promote_young_types);
#endif
	gc_count_add_each_types(hash, "remembered_normal_object_count_types", objspace->profile.remembered_normal_object_count_types);
	gc_count_add_each_types(hash, "remembered_shady_object_count_types", objspace->profile.remembered_shady_object_count_types);
    }
#endif

    return hash;
}

/*
 *  call-seq:
 *     GC.stat -> Hash
 *     GC.stat(hash) -> hash
 *     GC.stat(:key) -> Numeric
 *
 *  Returns a Hash containing information about the GC.
 *
 *  The hash includes information about internal statistics about GC such as:
 *
 *	{
 *          :count=>2,
 *          :heap_used=>9,
 *          :heap_length=>11,
 *          :heap_increment=>2,
 *          :heap_live_slot=>6836,
 *          :heap_free_slot=>519,
 *          :heap_final_slot=>0,
 *          :heap_swept_slot=>818,
 *          :total_allocated_object=>7674,
 *          :total_freed_object=>838,
 *          :malloc_increase=>181034,
 *          :malloc_limit=>16777216,
 *          :minor_gc_count=>2,
 *          :major_gc_count=>0,
 *          :remembered_shady_object=>55,
 *          :remembered_shady_object_limit=>0,
 *          :old_object=>2422,
 *          :old_object_limit=>0,
 *          :oldmalloc_increase=>277386,
 *          :oldmalloc_limit=>16777216
 *	}
 *
 *  The contents of the hash are implementation specific and may be changed in
 *  the future.
 *
 *  This method is only expected to work on C Ruby.
 *
 */

static VALUE
gc_stat(int argc, VALUE *argv, VALUE self)
{
    VALUE arg = Qnil;

    if (rb_scan_args(argc, argv, "01", &arg) == 1) {
	if (SYMBOL_P(arg)) {
	    size_t value = 0;
	    gc_stat_internal(arg, &value);
	    return SIZET2NUM(value);
	} else if (!RB_TYPE_P(arg, T_HASH)) {
	    rb_raise(rb_eTypeError, "non-hash or symbol given");
	}
    }

    if (arg == Qnil) {
        arg = rb_hash_new();
    }
    gc_stat_internal(arg, 0);
    return arg;
}

size_t
rb_gc_stat(VALUE key)
{
    if (SYMBOL_P(key)) {
	size_t value = 0;
	gc_stat_internal(key, &value);
	return value;
    } else {
	gc_stat_internal(key, 0);
	return 0;
    }
}

/*
 *  call-seq:
 *    GC.stress	    -> fixnum, true or false
 *
 *  Returns current status of GC stress mode.
 */

static VALUE
gc_stress_get(VALUE self)
{
    rb_objspace_t *objspace = &rb_objspace;
    return ruby_gc_stress;
}

/*
 *  call-seq:
 *    GC.stress = bool          -> bool
 *
 *  Updates the GC stress mode.
 *
 *  When stress mode is enabled, the GC is invoked at every GC opportunity:
 *  all memory and object allocations.
 *
 *  Enabling stress mode will degrade performance, it is only for debugging.
 */

static VALUE
gc_stress_set(VALUE self, VALUE flag)
{
    rb_objspace_t *objspace = &rb_objspace;
    rb_secure(2);
    ruby_gc_stress = FIXNUM_P(flag) ? flag : (RTEST(flag) ? Qtrue : Qfalse);
    return flag;
}

/*
 *  call-seq:
 *     GC.enable    -> true or false
 *
 *  Enables garbage collection, returning +true+ if garbage
 *  collection was previously disabled.
 *
 *     GC.disable   #=> false
 *     GC.enable    #=> true
 *     GC.enable    #=> false
 *
 */

VALUE
rb_gc_enable(void)
{
    rb_objspace_t *objspace = &rb_objspace;
    int old = dont_gc;

    dont_gc = FALSE;
    return old ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     GC.disable    -> true or false
 *
 *  Disables garbage collection, returning +true+ if garbage
 *  collection was already disabled.
 *
 *     GC.disable   #=> false
 *     GC.disable   #=> true
 *
 */

VALUE
rb_gc_disable(void)
{
    rb_objspace_t *objspace = &rb_objspace;
    int old = dont_gc;

    gc_rest_sweep(objspace);

    dont_gc = TRUE;
    return old ? Qtrue : Qfalse;
}

static int
get_envparam_int(const char *name, unsigned int *default_value, int lower_bound)
{
    char *ptr = getenv(name);
    int val;

    if (ptr != NULL) {
	val = atoi(ptr);
	if (val > lower_bound) {
	    if (RTEST(ruby_verbose)) fprintf(stderr, "%s=%d (%d)\n", name, val, *default_value);
	    *default_value = val;
	    return 1;
	}
	else {
	    if (RTEST(ruby_verbose)) fprintf(stderr, "%s=%d (%d), but ignored because lower than %d\n", name, val, *default_value, lower_bound);
	}
    }
    return 0;
}

static int
get_envparam_double(const char *name, double *default_value, double lower_bound)
{
    char *ptr = getenv(name);
    double val;

    if (ptr != NULL) {
	val = strtod(ptr, NULL);
	if (val > lower_bound) {
	    if (RTEST(ruby_verbose)) fprintf(stderr, "%s=%f (%f)\n", name, val, *default_value);
	    *default_value = val;
	    return 1;
	}
	else {
	    if (RTEST(ruby_verbose)) fprintf(stderr, "%s=%f (%f), but ignored because lower than %f\n", name, val, *default_value, lower_bound);
	}
    }
    return 0;
}

static void
gc_set_initial_pages(void)
{
    size_t min_pages;
    rb_objspace_t *objspace = &rb_objspace;

    min_pages = gc_params.heap_init_slots / HEAP_OBJ_LIMIT;
    if (min_pages > heap_eden->page_length) {
	heap_add_pages(objspace, heap_eden, min_pages - heap_eden->page_length);
    }
}

/*
 * GC tuning environment variables
 *
 * * RUBY_GC_HEAP_INIT_SLOTS
 *   - Initial allocation slots.
 * * RUBY_GC_HEAP_FREE_SLOTS
 *   - Prepare at least this ammount of slots after GC.
 *   - Allocate slots if there are not enough slots.
 * * RUBY_GC_HEAP_GROWTH_FACTOR (new from 2.1)
 *   - Allocate slots by this factor.
 *   - (next slots number) = (current slots number) * (this factor)
 * * RUBY_GC_HEAP_GROWTH_MAX_SLOTS (new from 2.1)
 *   - Allocation rate is limited to this factor.
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
ruby_gc_set_params(int safe_level)
{
    if (safe_level > 0) return;

    /* RUBY_GC_HEAP_FREE_SLOTS */
    if (get_envparam_int   ("RUBY_FREE_MIN", &gc_params.heap_free_slots, 0)) {
	rb_warn("RUBY_FREE_MIN is obsolete. Use RUBY_GC_HEAP_FREE_SLOTS instead.");
    }
    get_envparam_int   ("RUBY_GC_HEAP_FREE_SLOTS", &gc_params.heap_free_slots, 0);

    /* RUBY_GC_HEAP_INIT_SLOTS */
    if (get_envparam_int("RUBY_HEAP_MIN_SLOTS", &gc_params.heap_init_slots, 0)) {
	rb_warn("RUBY_HEAP_MIN_SLOTS is obsolete. Use RUBY_GC_HEAP_INIT_SLOTS instead.");
	gc_set_initial_pages();
    }
    if (get_envparam_int("RUBY_GC_HEAP_INIT_SLOTS", &gc_params.heap_init_slots, 0)) {
	gc_set_initial_pages();
    }

    get_envparam_double("RUBY_GC_HEAP_GROWTH_FACTOR", &gc_params.growth_factor, 1.0);
    get_envparam_int   ("RUBY_GC_HEAP_GROWTH_MAX_SLOTS", &gc_params.growth_max_slots, 0);

    get_envparam_int("RUBY_GC_MALLOC_LIMIT", &gc_params.malloc_limit_min, 0);
    get_envparam_int("RUBY_GC_MALLOC_LIMIT_MAX", &gc_params.malloc_limit_max, 0);
    get_envparam_double("RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR", &gc_params.malloc_limit_growth_factor, 1.0);

#ifdef RGENGC_ESTIMATE_OLDMALLOC
    get_envparam_int("RUBY_GC_OLDMALLOC_LIMIT", &gc_params.oldmalloc_limit_min, 0);
    get_envparam_int("RUBY_GC_OLDMALLOC_LIMIT_MAX", &gc_params.oldmalloc_limit_max, 0);
    get_envparam_double("RUBY_GC_OLDMALLOC_LIMIT_GROWTH_FACTOR", &gc_params.oldmalloc_limit_growth_factor, 1.0);
#endif
}

void
rb_gc_set_params(void)
{
    ruby_gc_set_params(rb_safe_level());
}

void
rb_objspace_reachable_objects_from(VALUE obj, void (func)(VALUE, void *), void *data)
{
    rb_objspace_t *objspace = &rb_objspace;

    if (is_markable_object(objspace, obj)) {
	struct mark_func_data_struct mfd;
	mfd.mark_func = func;
	mfd.data = data;
	objspace->mark_func_data = &mfd;
	gc_mark_children(objspace, obj);
	objspace->mark_func_data = 0;
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
    struct root_objects_data data;
    struct mark_func_data_struct mfd;

    data.func = func;
    data.data = passing_data;

    mfd.mark_func = root_objects_from;
    mfd.data = &data;

    objspace->mark_func_data = &mfd;
    {
	gc_mark_roots(objspace, TRUE, &data.category);
    }
    objspace->mark_func_data = 0;
}

/*
  ------------------------ Extended allocator ------------------------
*/

static void objspace_xfree(rb_objspace_t *objspace, void *ptr, size_t size);

static void *
negative_size_allocation_error_with_gvl(void *ptr)
{
    rb_raise(rb_eNoMemError, "%s", (const char *)ptr);
    return 0; /* should not be reached */
}

static void
negative_size_allocation_error(const char *msg)
{
    if (ruby_thread_has_gvl_p()) {
	rb_raise(rb_eNoMemError, "%s", msg);
    }
    else {
	if (ruby_native_thread_p()) {
	    rb_thread_call_with_gvl(negative_size_allocation_error_with_gvl, (void *)msg);
	}
	else {
	    fprintf(stderr, "[FATAL] %s\n", msg);
	    exit(EXIT_FAILURE);
	}
    }
}

static void *
ruby_memerror_body(void *dummy)
{
    rb_memerror();
    return 0;
}

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
	    exit(EXIT_FAILURE);
	}
    }
}

void
rb_memerror(void)
{
    rb_thread_t *th = GET_THREAD();
    if (!nomem_error ||
	rb_thread_raised_p(th, RAISED_NOMEMORY)) {
	fprintf(stderr, "[FATAL] failed to allocate memory\n");
	exit(EXIT_FAILURE);
    }
    if (rb_thread_raised_p(th, RAISED_NOMEMORY)) {
	rb_thread_raised_clear(th);
	GET_THREAD()->errinfo = nomem_error;
	JUMP_TAG(TAG_RAISE);
    }
    rb_thread_raised_set(th, RAISED_NOMEMORY);
    rb_exc_raise(nomem_error);
}

static void *
aligned_malloc(size_t alignment, size_t size)
{
    void *res;

#if defined __MINGW32__
    res = __mingw_aligned_malloc(size, alignment);
#elif defined _WIN32 && !defined __CYGWIN__
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

#if defined(_DEBUG) || GC_DEBUG
    /* alignment must be a power of 2 */
    assert(((alignment - 1) & alignment) == 0);
    assert(alignment % sizeof(void*) == 0);
#endif
    return res;
}

static void
aligned_free(void *ptr)
{
#if defined __MINGW32__
    __mingw_aligned_free(ptr);
#elif defined _WIN32 && !defined __CYGWIN__
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
    MEMOP_TYPE_MALLOC  = 1,
    MEMOP_TYPE_FREE    = 2,
    MEMOP_TYPE_REALLOC = 3
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
	if (ruby_gc_stress && !ruby_disable_gc_stress) {
	    garbage_collect_with_gvl(objspace, FALSE, TRUE, GPR_FLAG_MALLOC);
	}
	else {
	  retry:
	    if (malloc_increase > malloc_limit) {
		if (ruby_thread_has_gvl_p() && is_lazy_sweeping(heap_eden)) {
		    gc_rest_sweep(objspace); /* rest_sweep can reduce malloc_increase */
		    goto retry;
		}
		garbage_collect_with_gvl(objspace, FALSE, TRUE, GPR_FLAG_MALLOC);
	    }
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
	atomic_sub_nounderflow(objspace->malloc_params.allocated_size, dec_size);
    }

    if (0) fprintf(stderr, "incraese - ptr: %p, type: %s, new_size: %d, old_size: %d\n",
		   mem,
		   type == MEMOP_TYPE_MALLOC  ? "malloc" :
		   type == MEMOP_TYPE_FREE    ? "free  " :
		   type == MEMOP_TYPE_REALLOC ? "realloc": "error",
		   (int)new_size, (int)old_size);

    switch (type) {
      case MEMOP_TYPE_MALLOC:
	ATOMIC_SIZE_INC(objspace->malloc_params.allocations);
	break;
      case MEMOP_TYPE_FREE:
	{
	    size_t allocations = objspace->malloc_params.allocations;
	    if (allocations > 0) {
		atomic_sub_nounderflow(objspace->malloc_params.allocations, 1);
	    }
#if MALLOC_ALLOCATED_SIZE_CHECK
	    else {
		assert(objspace->malloc_params.allocations > 0);
	    }
#endif
	}
	break;
      case MEMOP_TYPE_REALLOC: /* ignore */ break;
    }
#endif
}

static inline size_t
objspace_malloc_prepare(rb_objspace_t *objspace, size_t size)
{
    if ((ssize_t)size < 0) {
	negative_size_allocation_error("negative allocation size (or too big)");
    }
    if (size == 0) size = 1;

#if CALC_EXACT_MALLOC_SIZE
    size += sizeof(size_t);
#endif

    return size;
}

static inline void *
objspace_malloc_fixup(rb_objspace_t *objspace, void *mem, size_t size)
{
#if CALC_EXACT_MALLOC_SIZE
    ((size_t *)mem)[0] = size;
    mem = (size_t *)mem + 1;
#endif

    return mem;
}

#define TRY_WITH_GC(alloc) do { \
	if (!(alloc) && \
	    (!garbage_collect_with_gvl(objspace, 1, 1, GPR_FLAG_MALLOC) || /* full mark && immediate sweep */ \
	     !(alloc))) { \
	    ruby_memerror(); \
	} \
    } while (0)

static void *
objspace_xmalloc(rb_objspace_t *objspace, size_t size)
{
    void *mem;

    size = objspace_malloc_prepare(objspace, size);
    TRY_WITH_GC(mem = malloc(size));
    size = objspace_malloc_size(objspace, mem, size);
    objspace_malloc_increase(objspace, mem, size, 0, MEMOP_TYPE_MALLOC);
    return objspace_malloc_fixup(objspace, mem, size);
}

static void *
objspace_xrealloc(rb_objspace_t *objspace, void *ptr, size_t new_size, size_t old_size)
{
    void *mem;

    if ((ssize_t)new_size < 0) {
	negative_size_allocation_error("negative re-allocation size");
    }

    if (!ptr) return objspace_xmalloc(objspace, new_size);

    /*
     * The behavior of realloc(ptr, 0) is implementation defined.
     * Therefore we don't use realloc(ptr, 0) for portability reason.
     * see http://www.open-std.org/jtc1/sc22/wg14/www/docs/dr_400.htm
     */
    if (new_size == 0) {
	objspace_xfree(objspace, ptr, old_size);
	return 0;
    }

#if CALC_EXACT_MALLOC_SIZE
    new_size += sizeof(size_t);
    ptr = (size_t *)ptr - 1;
    oldsize = ((size_t *)ptr)[0];
#endif

    old_size = objspace_malloc_size(objspace, ptr, old_size);
    TRY_WITH_GC(mem = realloc(ptr, new_size));
    new_size = objspace_malloc_size(objspace, mem, new_size);

#if CALC_EXACT_MALLOC_SIZE
    ((size_t *)mem)[0] = new_size;
    mem = (size_t *)mem + 1;
#endif

    objspace_malloc_increase(objspace, mem, new_size, old_size, MEMOP_TYPE_REALLOC);

    return mem;
}

static void
objspace_xfree(rb_objspace_t *objspace, void *ptr, size_t old_size)
{
#if CALC_EXACT_MALLOC_SIZE
    ptr = ((size_t *)ptr) - 1;
    oldsize = ((size_t*)ptr)[0];
#endif
    old_size = objspace_malloc_size(objspace, ptr, old_size);

    free(ptr);

    objspace_malloc_increase(objspace, ptr, 0, old_size, MEMOP_TYPE_FREE);
}

void *
ruby_xmalloc(size_t size)
{
    return objspace_xmalloc(&rb_objspace, size);
}

static inline size_t
xmalloc2_size(size_t n, size_t size)
{
    size_t len = size * n;
    if (n != 0 && size != len / n) {
	rb_raise(rb_eArgError, "malloc: possible integer overflow");
    }
    return len;
}

void *
ruby_xmalloc2(size_t n, size_t size)
{
    return objspace_xmalloc(&rb_objspace, xmalloc2_size(n, size));
}

static void *
objspace_xcalloc(rb_objspace_t *objspace, size_t count, size_t elsize)
{
    void *mem;
    size_t size;

    size = xmalloc2_size(count, elsize);
    size = objspace_malloc_prepare(objspace, size);

    TRY_WITH_GC(mem = calloc(1, size));
    return objspace_malloc_fixup(objspace, mem, size);
}

void *
ruby_xcalloc(size_t n, size_t size)
{
    return objspace_xcalloc(&rb_objspace, n, size);
}

#ifdef ruby_sized_xrealloc
#undef ruby_sized_xrealloc
#endif
void *
ruby_sized_xrealloc(void *ptr, size_t new_size, size_t old_size)
{
    return objspace_xrealloc(&rb_objspace, ptr, new_size, old_size);
}

void *
ruby_xrealloc(void *ptr, size_t new_size)
{
    return ruby_sized_xrealloc(ptr, new_size, 0);
}

#ifdef ruby_sized_xrealloc2
#undef ruby_sized_xrealloc2
#endif
void *
ruby_sized_xrealloc2(void *ptr, size_t n, size_t size, size_t old_n)
{
    size_t len = size * n;
    if (n != 0 && size != len / n) {
	rb_raise(rb_eArgError, "realloc: possible integer overflow");
    }
    return objspace_xrealloc(&rb_objspace, ptr, len, old_n * size);
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
    if (x) {
	objspace_xfree(&rb_objspace, x, size);
    }
}

void
ruby_xfree(void *x)
{
    ruby_sized_xfree(x, 0);
}

/* Mimic ruby_xmalloc, but need not rb_objspace.
 * should return pointer suitable for ruby_xfree
 */
void *
ruby_mimmalloc(size_t size)
{
    void *mem;
#if CALC_EXACT_MALLOC_SIZE
    size += sizeof(size_t);
#endif
    mem = malloc(size);
#if CALC_EXACT_MALLOC_SIZE
    /* set 0 for consistency of allocated_size/allocations */
    ((size_t *)mem)[0] = 0;
    mem = (size_t *)mem + 1;
#endif
    return mem;
}

void
ruby_mimfree(void *ptr)
{
    size_t *mem = (size_t *)ptr;
#if CALC_EXACT_MALLOC_SIZE
    mem = mem - 1;
#endif
    free(mem);
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
wmap_mark(void *ptr)
{
    struct weakmap *w = ptr;
#if WMAP_DELETE_DEAD_OBJECT_IN_MARK
    if (w->obj2wmap) st_foreach(w->obj2wmap, wmap_mark_map, (st_data_t)&rb_objspace);
#endif
    rb_gc_mark(w->final);
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
    if (!w) return 0;
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
    },
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
wmap_allocate(VALUE klass)
{
    struct weakmap *w;
    VALUE obj = TypedData_Make_Struct(klass, struct weakmap, &weakmap_type, w);
    w->obj2wmap = st_init_numtable();
    w->wmap2obj = st_init_numtable();
    w->final = rb_obj_method(obj, ID2SYM(rb_intern("finalize")));
    return obj;
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
	ptr = ruby_sized_xrealloc2(ptr, j, sizeof(VALUE), i);
	ptr[0] = j;
	*value = (st_data_t)ptr;
    }
    return ST_CONTINUE;
}

static VALUE
wmap_finalize(VALUE self, VALUE objid)
{
    st_data_t orig, wmap, data;
    VALUE obj, *rids, i, size;
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    /* Get reference from object id. */
    obj = obj_id_to_ref(objid);

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
    OBJ_INFECT(str, k);
    OBJ_INFECT(str, v);

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
    if (is_id_value(objspace, obj) && is_live_object(objspace, obj)) {
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
    if (is_id_value(objspace, obj) && is_live_object(objspace, obj)) {
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
    if (is_id_value(objspace, obj) && is_live_object(objspace, obj)) {
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
    if (is_id_value(objspace, obj) && is_live_object(objspace, obj)) {
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
    if (is_id_value(objspace, obj) && is_live_object(objspace, obj)) {
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
	ptr = ruby_sized_xrealloc2(ptr, size + 1, sizeof(VALUE), size);
    }
    else {
	optr = 0;
	size = 1;
	ptr = ruby_xmalloc2(2, sizeof(VALUE));
    }
    ptr[0] = size;
    ptr[size] = (VALUE)arg;
    if (ptr == optr) return ST_STOP;
    *val = (st_data_t)ptr;
    return ST_CONTINUE;
}

/* Creates a weak reference from the given key to the given value */
static VALUE
wmap_aset(VALUE self, VALUE wmap, VALUE orig)
{
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    should_be_finalizable(orig);
    should_be_finalizable(wmap);
    define_final0(orig, w->final);
    define_final0(wmap, w->final);
    st_update(w->obj2wmap, (st_data_t)orig, wmap_aset_update, wmap);
    st_insert(w->wmap2obj, (st_data_t)wmap, (st_data_t)orig);
    return nonspecial_obj_id(orig);
}

/* Retrieves a weakly referenced object with the given key */
static VALUE
wmap_aref(VALUE self, VALUE wmap)
{
    st_data_t data;
    VALUE obj;
    struct weakmap *w;
    rb_objspace_t *objspace = &rb_objspace;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    if (!st_lookup(w->wmap2obj, (st_data_t)wmap, &data)) return Qnil;
    obj = (VALUE)data;
    if (!is_id_value(objspace, obj)) return Qnil;
    if (!is_live_object(objspace, obj)) return Qnil;
    return obj;
}

/* Returns +true+ if +key+ is registered */
static VALUE
wmap_has_key(VALUE self, VALUE key)
{
    return NIL_P(wmap_aref(self, key)) ? Qfalse : Qtrue;
}

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
	    objspace->profile.records = malloc(sizeof(gc_profile_record) * objspace->profile.size);
	}
	if (index >= objspace->profile.size) {
	    objspace->profile.size += 1000;
	    objspace->profile.records = realloc(objspace->profile.records, sizeof(gc_profile_record) * objspace->profile.size);
	}
	if (!objspace->profile.records) {
	    rb_bug("gc_profile malloc or realloc miss");
	}
	record = objspace->profile.current_record = &objspace->profile.records[objspace->profile.next_index - 1];
	MEMZERO(record, gc_profile_record, 1);

	/* setup before-GC parameter */
	record->flags = reason | ((ruby_gc_stress && !ruby_disable_gc_stress) ? GPR_FLAG_STRESS : 0);
#if MALLOC_ALLOCATED_SIZE
	record->allocated_size = malloc_allocated_size;
#endif
#if GC_PROFILE_DETAIL_MEMORY
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

static inline void
gc_prof_mark_timer_start(rb_objspace_t *objspace)
{
    if (RUBY_DTRACE_GC_MARK_BEGIN_ENABLED()) {
	RUBY_DTRACE_GC_MARK_BEGIN();
    }
#if GC_PROFILE_MORE_DETAIL
    if (gc_prof_enabled(objspace)) {
	gc_prof_record(objspace)->gc_mark_time = getrusage_time();
    }
#endif
}

static inline void
gc_prof_mark_timer_stop(rb_objspace_t *objspace)
{
    if (RUBY_DTRACE_GC_MARK_END_ENABLED()) {
	RUBY_DTRACE_GC_MARK_END();
    }
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
    if (RUBY_DTRACE_GC_SWEEP_BEGIN_ENABLED()) {
	RUBY_DTRACE_GC_SWEEP_BEGIN();
    }
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
    if (RUBY_DTRACE_GC_SWEEP_END_ENABLED()) {
	RUBY_DTRACE_GC_SWEEP_END();
    }

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
	size_t live = objspace->profile.total_allocated_object_num_at_gc_start - objspace->profile.total_freed_object_num;
	size_t total = objspace->profile.heap_used_at_gc_start * HEAP_OBJ_LIMIT;

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
gc_profile_clear(void)
{
    rb_objspace_t *objspace = &rb_objspace;
    if (GC_PROFILE_RECORD_DEFAULT_SIZE * 2 < objspace->profile.size) {
        objspace->profile.size = GC_PROFILE_RECORD_DEFAULT_SIZE * 2;
        objspace->profile.records = realloc(objspace->profile.records, sizeof(gc_profile_record) * objspace->profile.size);
        if (!objspace->profile.records) {
            rb_memerror();
        }
    }
    MEMZERO(objspace->profile.records, gc_profile_record, objspace->profile.size);
    objspace->profile.next_index = 0;
    objspace->profile.current_record = 0;
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
gc_profile_record_get(void)
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
	rb_hash_aset(prof, ID2SYM(rb_intern("GC_FLAGS")), gc_info_decode(record->flags, rb_hash_new()));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_TIME")), DBL2NUM(record->gc_time));
        rb_hash_aset(prof, ID2SYM(rb_intern("GC_INVOKE_TIME")), DBL2NUM(record->gc_invoke_time));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_USE_SIZE")), SIZET2NUM(record->heap_use_size));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_TOTAL_SIZE")), SIZET2NUM(record->heap_total_size));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_TOTAL_OBJECTS")), SIZET2NUM(record->heap_total_objects));
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
	rb_hash_aset(prof, ID2SYM(rb_intern("REMEMBED_NORMAL_OBJECTS")), SIZET2NUM(record->remembered_normal_objects));
	rb_hash_aset(prof, ID2SYM(rb_intern("REMEMBED_SHADY_OBJECTS")), SIZET2NUM(record->remembered_shady_objects));
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
	C(RESCAN, R);
	C(STRESS, T);
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
	    append(out, rb_sprintf("%5"PRIdSIZE" %19.3f %20"PRIuSIZE" %20"PRIuSIZE" %20"PRIuSIZE" %30.20f\n",
				   i+1, record->gc_invoke_time, record->heap_use_size,
				   record->heap_total_size, record->heap_total_objects, record->gc_time*1000));
	}

#if GC_PROFILE_MORE_DETAIL
	append(out, rb_str_new_cstr("\n\n" \
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
				    "\n"));

	for (i = 0; i < count; i++) {
	    record = &objspace->profile.records[i];
	    append(out, rb_sprintf("%5"PRIdSIZE" %4s/%c/%6s%c %13"PRIuSIZE" %15"PRIuSIZE
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
gc_profile_result(void)
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

    if (argc == 0) {
	out = rb_stdout;
    }
    else {
	rb_scan_args(argc, argv, "01", &out);
    }
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
gc_profile_enable(void)
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
gc_profile_disable(void)
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
	    TYPE_NAME(T_NODE);
	    TYPE_NAME(T_ICLASS);
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

#if GC_DEBUG

void
rb_gcdebug_print_obj_condition(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;

    fprintf(stderr, "created at: %s:%d\n", RSTRING_PTR(RANY(obj)->file), FIX2INT(RANY(obj)->line));

    if (is_pointer_to_heap(objspace, (void *)obj)) {
        fprintf(stderr, "pointer to heap?: true\n");
    }
    else {
        fprintf(stderr, "pointer to heap?: false\n");
        return;
    }

    fprintf(stderr, "marked?      : %s\n", MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj) ? "true" : "false");
#if USE_RGENGC
#if RGENGC_THREEGEN
    fprintf(stderr, "young?       : %s\n", RVALUE_YOUNG_P(obj) ? "true" : "false");
#endif
    fprintf(stderr, "old?         : %s\n", RVALUE_OLD_P(obj) ? "true" : "false");
    fprintf(stderr, "WB-protected?: %s\n", RVALUE_WB_PROTECTED(obj) ? "true" : "false");
    fprintf(stderr, "remembered?  : %s\n", MARKED_IN_BITMAP(GET_HEAP_REMEMBERSET_BITS(obj), obj) ? "true" : "false");
#endif

    if (is_lazy_sweeping(heap_eden)) {
        fprintf(stderr, "lazy sweeping?: true\n");
        fprintf(stderr, "swept?: %s\n", is_swept_object(objspace, obj) ? "done" : "not yet");
    }
    else {
        fprintf(stderr, "lazy sweeping?: false\n");
    }
}

static VALUE
gcdebug_sential(VALUE obj, VALUE name)
{
    fprintf(stderr, "WARNING: object %s(%p) is inadvertently collected\n", (char *)name, (void *)obj);
    return Qnil;
}

void
rb_gcdebug_sentinel(VALUE obj, const char *name)
{
    rb_define_finalizer(obj, rb_proc_new(gcdebug_sential, (VALUE)name));
}
#endif /* GC_DEBUG */

/*
 * Document-module: ObjectSpace
 *
 *  The ObjectSpace module contains a number of routines
 *  that interact with the garbage collection facility and allow you to
 *  traverse all living objects with an iterator.
 *
 *  ObjectSpace also provides support for object finalizers, procs that will be
 *  called when a specific object is about to be destroyed by garbage
 *  collection.
 *
 *     a = "A"
 *     b = "B"
 *
 *     ObjectSpace.define_finalizer(a, proc {|id| puts "Finalizer one on #{id}" })
 *     ObjectSpace.define_finalizer(b, proc {|id| puts "Finalizer two on #{id}" })
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

/*
 *  The GC module provides an interface to Ruby's mark and
 *  sweep garbage collection mechanism.
 *
 *  Some of the underlying methods are also available via the ObjectSpace
 *  module.
 *
 *  You may obtain information about the operation of the GC through
 *  GC::Profiler.
 */

void
Init_GC(void)
{
    VALUE rb_mObjSpace;
    VALUE rb_mProfiler;
    VALUE gc_constants;

    rb_mGC = rb_define_module("GC");
    rb_define_singleton_method(rb_mGC, "start", gc_start_internal, -1);
    rb_define_singleton_method(rb_mGC, "enable", rb_gc_enable, 0);
    rb_define_singleton_method(rb_mGC, "disable", rb_gc_disable, 0);
    rb_define_singleton_method(rb_mGC, "stress", gc_stress_get, 0);
    rb_define_singleton_method(rb_mGC, "stress=", gc_stress_set, 1);
    rb_define_singleton_method(rb_mGC, "count", gc_count, 0);
    rb_define_singleton_method(rb_mGC, "stat", gc_stat, -1);
    rb_define_singleton_method(rb_mGC, "latest_gc_info", gc_latest_gc_info, -1);
    rb_define_method(rb_mGC, "garbage_collect", gc_start_internal, -1);

    gc_constants = rb_hash_new();
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVALUE_SIZE")), SIZET2NUM(sizeof(RVALUE)));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_OBJ_LIMIT")), SIZET2NUM(HEAP_OBJ_LIMIT));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_BITMAP_SIZE")), SIZET2NUM(HEAP_BITMAP_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_BITMAP_PLANES")), SIZET2NUM(HEAP_BITMAP_PLANES));
    OBJ_FREEZE(gc_constants);
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
    rb_define_module_function(rb_mObjSpace, "garbage_collect", gc_start_internal, -1);

    rb_define_module_function(rb_mObjSpace, "define_finalizer", define_final, -1);
    rb_define_module_function(rb_mObjSpace, "undefine_finalizer", undefine_final, 1);

    rb_define_module_function(rb_mObjSpace, "_id2ref", id2ref, 1);

    nomem_error = rb_exc_new3(rb_eNoMemError,
			      rb_obj_freeze(rb_str_new2("failed to allocate memory")));
    OBJ_TAINT(nomem_error);
    OBJ_FREEZE(nomem_error);

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
	rb_define_private_method(rb_cWeakMap, "finalize", wmap_finalize, 1);
	rb_include_module(rb_cWeakMap, rb_mEnumerable);
    }

    /* internal methods */
    rb_define_singleton_method(rb_mGC, "verify_internal_consistency", gc_verify_internal_consistency, 0);
#if MALLOC_ALLOCATED_SIZE
    rb_define_singleton_method(rb_mGC, "malloc_allocated_size", gc_malloc_allocated_size, 0);
    rb_define_singleton_method(rb_mGC, "malloc_allocations", gc_malloc_allocations, 0);
#endif

    /* ::GC::OPTS, which shows GC build options */
    {
	VALUE opts;
	rb_define_const(rb_mGC, "OPTS", opts = rb_ary_new());
#define OPT(o) if (o) rb_ary_push(opts, rb_str_new2(#o))
	OPT(GC_DEBUG);
	OPT(USE_RGENGC);
	OPT(RGENGC_DEBUG);
	OPT(RGENGC_CHECK_MODE);
	OPT(RGENGC_PROFILE);
	OPT(RGENGC_THREEGEN);
	OPT(RGENGC_ESTIMATE_OLDMALLOC);
	OPT(GC_PROFILE_MORE_DETAIL);
	OPT(GC_ENABLE_LAZY_SWEEP);
	OPT(CALC_EXACT_MALLOC_SIZE);
	OPT(MALLOC_ALLOCATED_SIZE);
	OPT(MALLOC_ALLOCATED_SIZE_CHECK);
	OPT(GC_PROFILE_DETAIL_MEMORY);
#undef OPT
    }
}
