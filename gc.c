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

#ifdef HAVE_VALGRIND_MEMCHECK_H
# include <valgrind/memcheck.h>
# ifndef VALGRIND_MAKE_MEM_DEFINED
#  define VALGRIND_MAKE_MEM_DEFINED(p, n) VALGRIND_MAKE_READABLE((p), (n))
# endif
# ifndef VALGRIND_MAKE_MEM_UNDEFINED
#  define VALGRIND_MAKE_MEM_UNDEFINED(p, n) VALGRIND_MAKE_WRITABLE((p), (n))
# endif
#else
# define VALGRIND_MAKE_MEM_DEFINED(p, n) 0
# define VALGRIND_MAKE_MEM_UNDEFINED(p, n) 0
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

#ifndef GC_MALLOC_LIMIT
#define GC_MALLOC_LIMIT 8000000
#endif
#define HEAP_MIN_SLOTS 10000
#define FREE_MIN  4096
#define HEAP_GROWTH_FACTOR 1.8

typedef struct {
    unsigned int initial_malloc_limit;
    unsigned int initial_heap_min_slots;
    unsigned int initial_free_min;
    double initial_growth_factor;
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
    VALUE gc_stress;
#endif
} ruby_gc_params_t;

static ruby_gc_params_t initial_params = {
    GC_MALLOC_LIMIT,
    HEAP_MIN_SLOTS,
    FREE_MIN,
    HEAP_GROWTH_FACTOR,
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
    FALSE,
#endif
};

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
 * 2: enable bits check (for debugging)
 * 3: show all references
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

#else /* USE_RGENGC */
#define RGENGC_DEBUG       0
#define RGENGC_CHECK_MODE  0
#define RGENGC_PROFILE     0
#endif

#ifndef GC_PROFILE_MORE_DETAIL
#define GC_PROFILE_MORE_DETAIL 0
#endif
#ifndef GC_ENABLE_LAZY_SWEEP
#define GC_ENABLE_LAZY_SWEEP   1
#endif
#ifndef CALC_EXACT_MALLOC_SIZE
#define CALC_EXACT_MALLOC_SIZE 0
#endif

typedef enum {
    GPR_FLAG_NONE            = 0x000,
    /* major reason */
    GPR_FLAG_MAJOR_BY_NOFREE = 0x001,
    GPR_FLAG_MAJOR_BY_OLDGEN = 0x002,
    GPR_FLAG_MAJOR_BY_SHADY  = 0x004,
    GPR_FLAG_MAJOR_BY_RESCAN = 0x008,
    GPR_FLAG_MAJOR_BY_STRESS = 0x010,
    GPR_FLAG_MAJOR_MASK      = 0x01f,

    /* gc reason */
    GPR_FLAG_NEWOBJ          = 0x020,
    GPR_FLAG_MALLOC          = 0x040,
    GPR_FLAG_METHOD          = 0x080,
    GPR_FLAG_CAPI            = 0x100,
    GPR_FLAG_STRESS          = 0x200,

    /* others */
    GPR_FLAG_IMMEDIATE_SWEEP = 0x400,
    GPR_FLAG_HAVE_FINALIZE   = 0x800

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

    size_t heap_use_slots;
    size_t heap_live_objects;
    size_t heap_free_objects;

    size_t allocate_increase;
    size_t allocate_limit;
#if CALC_EXACT_MALLOC_SIZE
    size_t allocated_size;
#endif

    double prepare_time;
    size_t removing_objects;
    size_t empty_objects;
#endif

#if RGENGC_PROFILE > 0
    size_t oldgen_objects;
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
#ifdef GC_DEBUG
    const char *file;
    int   line;
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

struct heap_slot_header {
    struct heap_slot *slot;
};

struct heap_slot_body {
    struct heap_slot_header header;
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

typedef struct rb_objspace {
    struct {
	size_t limit;
	size_t increase;
	size_t increase2;
#if CALC_EXACT_MALLOC_SIZE
	size_t allocated_size;
	size_t allocations;
#endif
    } malloc_params;
    struct {
	size_t increment;
	struct heap_slot *slots;
	struct heap_slot *sweep_slots;
	struct heap_slot *free_slots;
	struct heap_slot *using_slot;
	struct heap_slot **sorted;
	size_t length;
	size_t used;
	RVALUE *range[2];
	size_t free_num;
	size_t free_min;
	size_t final_num;
	size_t do_heap_free;
    } heap;
    struct {
	int dont_gc;
	int dont_lazy_sweep;
	int during_gc;
	rb_atomic_t finalizing;
    } flags;
    struct {
	st_table *table;
	RVALUE *deferred;
    } final;
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
#ifdef RGENGC_PROFILE
	size_t generated_normal_object_count;
	size_t generated_shady_object_count;
	size_t shade_operation_count;
	size_t promote_operation_count;
	size_t remembered_normal_object_count;
	size_t remembered_shady_object_count;

#if RGENGC_PROFILE >= 2
	size_t generated_normal_object_count_types[RUBY_T_MASK];
	size_t generated_shady_object_count_types[RUBY_T_MASK];
	size_t shade_operation_count_types[RUBY_T_MASK];
	size_t promote_operation_count_types[RUBY_T_MASK];
	size_t remembered_normal_object_count_types[RUBY_T_MASK];
	size_t remembered_shady_object_count_types[RUBY_T_MASK];
#endif
#endif /* RGENGC_PROFILE */
#endif /* USE_RGENGC */

	/* temporary profiling space */
	double gc_sweep_start_time;
	size_t total_allocated_object_num_at_gc_start;
	size_t heap_used_at_gc_start;
    } profile;
    struct gc_list *global_list;
    size_t count;
    size_t total_allocated_object_num;
    size_t total_freed_object_num;
    rb_event_flag_t hook_events; /* this place may be affinity with memory cache */
    VALUE gc_stress;
    RVALUE *freelist;

    struct mark_func_data_struct {
	void *data;
	void (*mark_func)(VALUE v, void *data);
    } *mark_func_data;

#if USE_RGENGC
    struct {
	int during_minor_gc;
	int parent_object_is_promoted;

	/* for check mode */
	VALUE parent_object;
	unsigned int  monitor_level;
	st_table *monitored_object_table;

	int need_major_gc;
	size_t remembered_shady_object_count;
	size_t remembered_shady_object_limit;
	size_t oldgen_object_count;
	size_t oldgen_object_limit;
#if RGENGC_CHECK_MODE >= 2
	int have_saved_bitmaps;
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
    HEAP_OBJ_LIMIT = (unsigned int)((HEAP_SIZE - sizeof(struct heap_slot_header))/sizeof(struct RVALUE)),
    HEAP_BITMAP_LIMIT = CEILDIV(CEILDIV(HEAP_SIZE, sizeof(struct RVALUE)), BITS_BITLENGTH),
    HEAP_BITMAP_SIZE = ( BITS_SIZE * HEAP_BITMAP_LIMIT),
    HEAP_BITMAP_PLANES = USE_RGENGC ? 3 : 1 /* RGENGC: mark bits, rememberset bits and oldgen bits */
};

struct heap_slot {
    struct heap_slot_body *body;
    RVALUE *start;
    size_t limit;

    RVALUE *freelist;
    struct heap_slot *next;
    struct heap_slot *prev;
    struct heap_slot *free_next;

    bits_t mark_bits[HEAP_BITMAP_LIMIT];
#if USE_RGENGC
    bits_t rememberset_bits[HEAP_BITMAP_LIMIT];
    bits_t oldgen_bits[HEAP_BITMAP_LIMIT];
#if RGENGC_CHECK_MODE >= 2
    bits_t saved_mark_bits[HEAP_BITMAP_LIMIT];
    bits_t saved_rememberset_bits[HEAP_BITMAP_LIMIT];
    bits_t saved_oldgen_bits[HEAP_BITMAP_LIMIT];
#endif
#endif
};

#define GET_SLOT_BODY(x)             ((struct heap_slot_body *)((bits_t)(x) & ~(HEAP_ALIGN_MASK)))
#define GET_SLOT_HEADER(x)           (&GET_SLOT_BODY(x)->header)
#define GET_HEAP_SLOT(x)             (GET_SLOT_HEADER(x)->slot)
#define GET_HEAP_MARK_BITS(x)        (&GET_HEAP_SLOT(x)->mark_bits[0])
#define GET_HEAP_REMEMBERSET_BITS(x) (&GET_HEAP_SLOT(x)->rememberset_bits[0])
#define GET_HEAP_OLDGEN_BITS(x)      (&GET_HEAP_SLOT(x)->oldgen_bits[0])
#define NUM_IN_SLOT(p)               (((bits_t)(p) & HEAP_ALIGN_MASK)/sizeof(RVALUE))
#define BITMAP_INDEX(p)              (NUM_IN_SLOT(p) / BITS_BITLENGTH )
#define BITMAP_OFFSET(p)             (NUM_IN_SLOT(p) & (BITS_BITLENGTH-1))
#define BITMAP_BIT(p)                ((bits_t)1 << BITMAP_OFFSET(p))
/* Bitmap Operations */
#define MARKED_IN_BITMAP(bits, p)    ((bits)[BITMAP_INDEX(p)] & BITMAP_BIT(p))
#define MARK_IN_BITMAP(bits, p)      ((bits)[BITMAP_INDEX(p)] = (bits)[BITMAP_INDEX(p)] | BITMAP_BIT(p))
#define CLEAR_IN_BITMAP(bits, p)     ((bits)[BITMAP_INDEX(p)] = (bits)[BITMAP_INDEX(p)] & ~BITMAP_BIT(p))

/* Aliases */
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
#define rb_objspace (*GET_VM()->objspace)
#define ruby_initial_gc_stress	initial_params.gc_stress
VALUE *ruby_initial_gc_stress_ptr = &ruby_initial_gc_stress;
#else
static rb_objspace_t rb_objspace = {{GC_MALLOC_LIMIT}};
VALUE *ruby_initial_gc_stress_ptr = &rb_objspace.gc_stress;
#endif

#define malloc_limit		objspace->malloc_params.limit
#define malloc_increase 	objspace->malloc_params.increase
#define malloc_increase2 	objspace->malloc_params.increase2
#define malloc_allocated_size 	objspace->malloc_params.allocated_size
#define heap_slots		objspace->heap.slots
#define heap_length		objspace->heap.length
#define heap_used		objspace->heap.used
#define lomem			objspace->heap.range[0]
#define himem			objspace->heap.range[1]
#define heap_inc		objspace->heap.increment
#define dont_gc 		objspace->flags.dont_gc
#define during_gc		objspace->flags.during_gc
#define finalizing		objspace->flags.finalizing
#define finalizer_table 	objspace->final.table
#define deferred_final_list	objspace->final.deferred
#define global_List		objspace->global_list
#define ruby_gc_stress		objspace->gc_stress
#define initial_malloc_limit	initial_params.initial_malloc_limit
#define initial_heap_min_slots	initial_params.initial_heap_min_slots
#define initial_free_min	initial_params.initial_free_min
#define initial_growth_factor	initial_params.initial_growth_factor
#define monitor_level           objspace->rgengc.monitor_level
#define monitored_object_table  objspace->rgengc.monitored_object_table

#define is_lazy_sweeping(objspace) ((objspace)->heap.sweep_slots != 0)

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
extern st_table *rb_class_tbl;
int ruby_disable_gc_stress = 0;

void rb_gcdebug_print_obj_condition(VALUE obj);

static void rb_objspace_call_finalizer(rb_objspace_t *objspace);
static VALUE define_final0(VALUE obj, VALUE block);
VALUE rb_define_final(VALUE obj, VALUE block);
VALUE rb_undefine_final(VALUE obj);
static void run_final(rb_objspace_t *objspace, VALUE obj);

static void negative_size_allocation_error(const char *);
static void *aligned_malloc(size_t, size_t);
static void aligned_free(void *);

static void init_mark_stack(mark_stack_t *stack);

static VALUE lazy_sweep_enable(void);
static int ready_to_gc(rb_objspace_t *objspace);
static int garbage_collect(rb_objspace_t *, int full_mark, int immediate_sweep, int reason);
static int garbage_collect_body(rb_objspace_t *, int full_mark, int immediate_sweep, int reason);
static int gc_lazy_sweep(rb_objspace_t *objspace);
static void gc_rest_sweep(rb_objspace_t *objspace);

static void gc_mark_stacked_objects(rb_objspace_t *);
static void gc_mark(rb_objspace_t *objspace, VALUE ptr);
static void gc_mark_maybe(rb_objspace_t *objspace, VALUE ptr);
static void gc_mark_children(rb_objspace_t *objspace, VALUE ptr);

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

#define rgengc_report if (RGENGC_DEBUG) rgengc_report_body
static void rgengc_report_body(int level, rb_objspace_t *objspace, const char *fmt, ...);
static const char * type_name(int type, VALUE obj);
static const char *obj_type_name(VALUE obj);

#if USE_RGENGC
static int rgengc_remembered(rb_objspace_t *objspace, VALUE obj);
static int rgengc_remember(rb_objspace_t *objspace, VALUE obj);
static void rgengc_mark_and_rememberset_clear(rb_objspace_t *objspace);
static void rgengc_rememberset_mark(rb_objspace_t *objspace);

#define FL_TEST2(x,f)         ((RGENGC_CHECK_MODE && SPECIAL_CONST_P(x)) ? (rb_bug("FL_TEST2: SPECIAL_CONST"), 0) : FL_TEST_RAW((x),(f)) != 0)
#define FL_SET2(x,f)          do {if (RGENGC_CHECK_MODE && SPECIAL_CONST_P(x)) rb_bug("FL_SET2: SPECIAL_CONST");   RBASIC(x)->flags |= (f);} while (0)
#define FL_UNSET2(x,f)        do {if (RGENGC_CHECK_MODE && SPECIAL_CONST_P(x)) rb_bug("FL_UNSET2: SPECIAL_CONST"); RBASIC(x)->flags &= ~(f);} while (0)

#define RVALUE_SHADY(obj)    (!FL_TEST2((check_bitmap_consistency((VALUE)obj)), FL_WB_PROTECTED))
#define RVALUE_PROMOTED(obj) FL_TEST2(check_bitmap_consistency((VALUE)obj), FL_OLDGEN)

#define RVALUE_PROMOTED_FROM_BITMAP(x) MARKED_IN_BITMAP(GET_HEAP_OLDGEN_BITS(x),x)

static inline VALUE
check_bitmap_consistency(VALUE obj)
{
#if RUBY_CHECK_MODE > 0
    int oldgen_bitmap = MARKED_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj), obj) != 0;

    if (FL_TEST2((obj), FL_OLDGEN) != oldgen_bitmap) {
	rb_bug("check_bitmap_consistency: oldgen flag of %p (%s) is %d, but bitmap is %d",
	       (void *)obj, obj_type_name(obj), FL_TEST2((obj), FL_OLDGEN), oldgen_bitmap);
    }
    if (FL_TEST2((obj), FL_WB_PROTECTED)) {
	/* non-shady */
    }
    else {
	/* shady */
	if (oldgen_bitmap) {
	    rb_bug("check_bitmap_consistency: %p (%s) is shady, but bitmap specifies oldgen",
		   (void *)obj, obj_type_name(obj));
	}
    }
#endif
    return obj;
}

static inline void
RVALUE_PROMOTE(VALUE obj)
{
    check_bitmap_consistency(obj);
    MARK_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj), obj);
    FL_SET2(obj, FL_OLDGEN);
#if RGENGC_PROFILE >= 1
    {
	rb_objspace_t *objspace = &rb_objspace;
	objspace->profile.promote_operation_count++;
#if RGENGC_PROFILE >= 2
	objspace->profile.promote_operation_count_types[BUILTIN_TYPE(obj)]++;
#endif
    }
#endif
}

static inline int
is_before_sweep(VALUE obj)
{
    struct heap_slot *slot;
    rb_objspace_t *objspace = &rb_objspace;
    if (is_lazy_sweeping(objspace)) {
	slot = objspace->heap.sweep_slots;
	while (slot) {
	    if (slot->body == GET_SLOT_BODY(obj)) {
		return TRUE;
	    }
	    slot = slot->next;
	}
    }
    return FALSE;
}

static inline void
RVALUE_DEMOTE(VALUE obj)
{
    check_bitmap_consistency(obj);
    FL_UNSET2(obj, FL_OLDGEN);
    CLEAR_IN_BITMAP(GET_HEAP_OLDGEN_BITS(obj), obj);
}
#endif

/*
  --------------------------- ObjectSpace -----------------------------
*/

#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
rb_objspace_t *
rb_objspace_alloc(void)
{
    rb_objspace_t *objspace = malloc(sizeof(rb_objspace_t));
    memset(objspace, 0, sizeof(*objspace));
    malloc_limit = initial_malloc_limit;
    ruby_gc_stress = ruby_initial_gc_stress;

    return objspace;
}
#endif

#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
static void free_stack_chunks(mark_stack_t *);
static void free_heap_slot(rb_objspace_t *objspace, struct heap_slot *slot);

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
    if (objspace->heap.sorted) {
	size_t i;
	for (i = 0; i < heap_used; ++i) {
	    free_heap_slot(objspace, objspace->heap.sorted[i]);
	}
	free(objspace->heap.sorted);
	heap_used = 0;
	heap_slots = 0;
    }
    free_stack_chunks(&objspace->mark_stack);
    free(objspace);
}
#endif

static void
heap_allocate_sorted_array(rb_objspace_t *objspace, size_t next_heap_length)
{
    struct heap_slot **p;
    size_t size;

    size = next_heap_length * sizeof(struct heap_slot *);

    if (heap_used > 0) {
	p = (struct heap_slot **)realloc(objspace->heap.sorted, size);
	if (p) objspace->heap.sorted = p;
    }
    else {
	p = objspace->heap.sorted = (struct heap_slot **)malloc(size);
    }

    if (p == 0) {
	during_gc = 0;
	rb_memerror();
    }
}

static inline void
heap_slot_add_freeobj(rb_objspace_t *objspace, struct heap_slot *slot, VALUE obj)
{
    RVALUE *p = (RVALUE *)obj;
    p->as.free.flags = 0;
    p->as.free.next = slot->freelist;
    slot->freelist = p;
    rgengc_report(3, objspace, "heap_slot_add_freeobj: %p (%s) is added to freelist\n", p, obj_type_name(obj));
}

static inline void
heap_add_freeslot(rb_objspace_t *objspace, struct heap_slot *slot)
{
    if (slot->freelist) {
	slot->free_next = objspace->heap.free_slots;
	objspace->heap.free_slots = slot;
    }
}

static void
heap_assign_slot(rb_objspace_t *objspace)
{
    RVALUE *start, *end, *p;
    struct heap_slot *slot;
    struct heap_slot_body *slot_body = 0;
    size_t hi, lo, mid;
    size_t limit = HEAP_OBJ_LIMIT;

    /* assign heap_slot body (contains heap_slot_header and RVALUEs) */
    slot_body = (struct heap_slot_body *)aligned_malloc(HEAP_ALIGN, HEAP_SIZE);
    if (slot_body == 0) {
	during_gc = 0;
	rb_memerror();
    }

    /* assign heap_slot entry */
    slot = (struct heap_slot *)malloc(sizeof(struct heap_slot));
    if (slot == 0) {
	aligned_free(slot_body);
	during_gc = 0;
	rb_memerror();
    }
    MEMZERO((void*)slot, struct heap_slot, 1);

    slot->body = slot_body;

    slot->next = objspace->heap.slots;
    if (objspace->heap.slots) objspace->heap.slots->prev = slot;
    objspace->heap.slots = slot;

    /* adjust obj_limit (object number available in this slot) */
    start = (RVALUE*)((VALUE)slot_body + sizeof(struct heap_slot_header));
    if ((VALUE)start % sizeof(RVALUE) != 0) {
	int delta = (int)(sizeof(RVALUE) - ((VALUE)start % sizeof(RVALUE)));
	start = (RVALUE*)((VALUE)start + delta);
	limit = (HEAP_SIZE - (size_t)((VALUE)start - (VALUE)slot_body))/sizeof(RVALUE);
    }
    end = start + limit;

    /* setup objspace->heap.sorted */
    lo = 0;
    hi = heap_used;
    while (lo < hi) {
	struct heap_slot *mid_slot;

	mid = (lo + hi) / 2;
	mid_slot = objspace->heap.sorted[mid];
	if (mid_slot->body < slot_body) {
	    lo = mid + 1;
	}
	else if (mid_slot->body > slot_body) {
	    hi = mid;
	}
	else {
	    rb_bug("same heap slot is allocated: %p at %"PRIuVALUE, (void *)slot_body, (VALUE)mid);
	}
    }
    if (hi < heap_used) {
	MEMMOVE(&objspace->heap.sorted[hi+1], &objspace->heap.sorted[hi], struct heap_slot_header*, heap_used - hi);
    }

    /* setup slot */
    slot->start = start;
    slot->limit = limit;
    slot_body->header.slot = objspace->heap.sorted[hi] = slot;

    if (lomem == 0 || lomem > start) lomem = start;
    if (himem < end) himem = end;
    heap_used++;

    for (p = start; p != end; p++) {
	rgengc_report(3, objspace, "assign_heap_slot: %p is added to freelist\n");
	heap_slot_add_freeobj(objspace, slot, (VALUE)p);
    }

    heap_add_freeslot(objspace, slot);
}

static void
heap_add_slots(rb_objspace_t *objspace, size_t add)
{
    size_t i;
    size_t next_heap_length;

    next_heap_length = heap_used + add;

    if (next_heap_length > heap_length) {
	heap_allocate_sorted_array(objspace, next_heap_length);
        heap_length = next_heap_length;
    }

    for (i = 0; i < add; i++) {
	heap_assign_slot(objspace);
    }
    heap_inc = 0;
}

static void
heap_init(rb_objspace_t *objspace)
{
    heap_add_slots(objspace, HEAP_MIN_SLOTS / HEAP_OBJ_LIMIT);
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

static void
heap_set_increment(rb_objspace_t *objspace)
{
    size_t next_heap_length = (size_t)(heap_used * initial_growth_factor);

    if (next_heap_length == heap_used) {
        next_heap_length++;
    }

    heap_inc = next_heap_length - heap_used;

    rgengc_report(5, objspace, "heap_set_increment: heap_length: %d, next_heap_length: %d, heap_inc: %d\n",
		  heap_length, next_heap_length, heap_inc);

    if (next_heap_length > heap_length) {
	heap_allocate_sorted_array(objspace, next_heap_length);
	heap_length = next_heap_length;
    }
}

static int
heap_increment(rb_objspace_t *objspace)
{
    rgengc_report(5, objspace, "heap_increment: heap_inc: %d\n", heap_inc);

    if (heap_inc > 0) {
        heap_assign_slot(objspace);
	heap_inc--;
	return TRUE;
    }
    return FALSE;
}

static struct heap_slot *
heap_prepare_freeslot(rb_objspace_t *objspace)
{
    if (!GC_ENABLE_LAZY_SWEEP && objspace->flags.dont_lazy_sweep) {
	if (heap_increment(objspace) == 0 &&
	    garbage_collect(objspace, FALSE, TRUE, GPR_FLAG_NEWOBJ) == 0) {
	    goto err;
	}
	goto ok;
    }

    if (!ready_to_gc(objspace)) return objspace->heap.free_slots;

    during_gc++;

    if ((is_lazy_sweeping(objspace) && gc_lazy_sweep(objspace)) ||
	heap_increment(objspace)) {
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
    return objspace->heap.free_slots;
}

static inline struct heap_slot *
heap_get_freeslot(rb_objspace_t *objspace)
{
    struct heap_slot *slot;

    slot = objspace->heap.free_slots;
    while (slot == NULL) {
	slot = heap_prepare_freeslot(objspace);
    }
    objspace->heap.free_slots = slot->free_next;

    return slot;
}

static inline VALUE
heap_get_freeobj(rb_objspace_t *objspace)
{
    RVALUE *p = objspace->freelist;

    while (UNLIKELY(p == NULL)) {
	struct heap_slot *slot = heap_get_freeslot(objspace);
	objspace->heap.using_slot = slot;
	p = objspace->freelist = slot->freelist;
	slot->freelist = NULL;
    }
    objspace->freelist = p->as.free.next;

    return (VALUE)p;
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

    obj = heap_get_freeobj(objspace);

    /* OBJSETUP */
    RBASIC(obj)->flags = flags;
    RBASIC_SET_CLASS(obj, klass);
    if (rb_safe_level() >= 3) FL_SET((obj), FL_TAINT);
    RANY(obj)->as.values.v1 = v1;
    RANY(obj)->as.values.v2 = v2;
    RANY(obj)->as.values.v3 = v3;

#ifdef GC_DEBUG
    RANY(obj)->file = rb_sourcefile();
    RANY(obj)->line = rb_sourceline();
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
    if (RVALUE_PROMOTED(obj)) rb_bug("newobj: %p (%s) is promoted.\n", (void *)obj, obj_type_name(obj));
    if (rgengc_remembered(objspace, (VALUE)obj)) rb_bug("newobj: %p (%s) is remembered.\n", (void *)obj, obj_type_name(obj));
#endif

    objspace->total_allocated_object_num++;
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
    NODE *n = (NODE *)newobj_of(0, T_NODE, a0, a1, a2);
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
    return newobj_of(klass, T_DATA | type->flags, (VALUE)type, (VALUE)1, (VALUE)datap);
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
    register struct heap_slot *slot;
    register size_t hi, lo, mid;

    if (p < lomem || p > himem) return FALSE;
    if ((VALUE)p % sizeof(RVALUE) != 0) return FALSE;

    /* check if p looks like a pointer using bsearch*/
    lo = 0;
    hi = heap_used;
    while (lo < hi) {
	mid = (lo + hi) / 2;
	slot = objspace->heap.sorted[mid];
	if (slot->start <= p) {
	    if (p < slot->start + slot->limit) {
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
rb_free_m_table(st_table *tbl)
{
    st_foreach(tbl, free_method_entry_i, 0);
    st_free_table(tbl);
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

static void
unlink_heap_slot(rb_objspace_t *objspace, struct heap_slot *slot)
{
    if (slot->prev)
        slot->prev->next = slot->next;
    if (slot->next)
        slot->next->prev = slot->prev;
    if (heap_slots == slot)
        heap_slots = slot->next;
    if (objspace->heap.sweep_slots == slot)
        objspace->heap.sweep_slots = slot->next;
    slot->prev = NULL;
    slot->next = NULL;
}

static void
free_heap_slot(rb_objspace_t *objspace, struct heap_slot *slot)
{
    aligned_free(slot->body);
    free(slot);
}

static void
free_unused_slots(rb_objspace_t *objspace)
{
    size_t i, j;

    for (i = j = 1; j < heap_used; i++) {
	struct heap_slot *slot = objspace->heap.sorted[i];

	if (slot->limit == 0) {
	    free_heap_slot(objspace, slot);
	    heap_used--;
	}
	else {
	    if (i != j) {
		objspace->heap.sorted[j] = slot;
	    }
	    j++;
	}
    }
}

static inline void
make_deferred(RVALUE *p)
{
    p->as.basic.flags = T_ZOMBIE;
}

static inline void
make_io_deferred(RVALUE *p)
{
    rb_io_t *fptr = p->as.file.fptr;
    make_deferred(p);
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
	rb_clear_cache_by_class((VALUE)obj);
        if (RCLASS_M_TBL(obj)) {
            rb_free_m_table(RCLASS_M_TBL(obj));
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
        xfree(RANY(obj)->as.klass.ptr);
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
	    if (RTYPEDDATA_P(obj)) {
		RDATA(obj)->dfree = RANY(obj)->as.typeddata.type->function.dfree;
	    }
	    if (RANY(obj)->as.data.dfree == (RUBY_DATA_FUNC)-1) {
		xfree(DATA_PTR(obj));
	    }
	    else if (RANY(obj)->as.data.dfree) {
		make_deferred(RANY(obj));
		return 1;
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
	    make_io_deferred(RANY(obj));
	    return 1;
	}
	break;
      case T_RATIONAL:
      case T_COMPLEX:
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
	xfree(RANY(obj)->as.klass.ptr);
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
    heap_init(&rb_objspace);
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
    struct heap_slot_body *last_body = 0;
    struct heap_slot *slot;
    RVALUE *pstart, *pend;
    rb_objspace_t *objspace = &rb_objspace;
    struct each_obj_args *args = (struct each_obj_args *)arg;
    volatile VALUE v;

    i = 0;
    while (i < heap_used) {
	while (0 < i && last_body < objspace->heap.sorted[i-1]->body)
	    i--;
	while (i < heap_used && objspace->heap.sorted[i]->body <= last_body)
	    i++;
	if (heap_used <= i)
	  break;

	slot = objspace->heap.sorted[i];
	last_body = slot->body;

	pstart = slot->start;
	pend = pstart + slot->limit;

	for (; pstart != pend; pstart++) {
	    if (pstart->as.basic.flags) {
		v = (VALUE)pstart; /* acquire to save this object */
		break;
	    }
	}
	if (pstart != pend) {
	    if ((*args->callback)(pstart, pend, sizeof(RVALUE), args->data)) {
		break;
	    }
	}
    }
    RB_GC_GUARD(v);

    return Qnil;
}

/*
 * rb_objspace_each_objects() is special C API to walk through
 * Ruby object space.  This C API is too difficult to use it.
 * To be frank, you should not use it. Or you need to read the
 * source code of this function and understand what this function does.
 *
 * 'callback' will be called several times (the number of heap slot,
 * at current implementation) with:
 *   vstart: a pointer to the first living object of the heap_slot.
 *   vend: a pointer to next to the valid heap_slot area.
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
 * Note: 'vstart' is not a top of heap_slot.  This point the first
 *       living object to grasp at least one object to avoid GC issue.
 *       This means that you can not walk through all Ruby object slot
 *       including freed object slot.
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

    gc_rest_sweep(objspace);
    objspace->flags.dont_lazy_sweep = TRUE;

    args.callback = callback;
    args.data = data;
    rb_ensure(objspace_each_objects, (VALUE)&args, lazy_sweep_enable, Qnil);
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
    return rb_undefine_final(obj);
}

VALUE
rb_undefine_final(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;
    st_data_t data = obj;
    rb_check_frozen(obj);
    st_delete(finalizer_table, &data, 0);
    FL_UNSET(obj, FL_FINALIZE);
    return obj;
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
    rb_check_frozen(obj);
    if (argc == 1) {
	block = rb_block_proc();
    }
    else if (!rb_respond_to(block, rb_intern("call"))) {
	rb_raise(rb_eArgError, "wrong type argument %s (should be callable)",
		 rb_obj_classname(block));
    }

    return define_final0(obj, block);
}

static VALUE
define_final0(VALUE obj, VALUE block)
{
    rb_objspace_t *objspace = &rb_objspace;
    VALUE table;
    st_data_t data;

    if (!FL_ABLE(obj)) {
	rb_raise(rb_eArgError, "cannot define finalizer for %s",
		 rb_obj_classname(obj));
    }
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
rb_define_final(VALUE obj, VALUE block)
{
    rb_check_frozen(obj);
    if (!rb_respond_to(block, rb_intern("call"))) {
	rb_raise(rb_eArgError, "wrong type argument %s (should be callable)",
		 rb_obj_classname(block));
    }
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

    objspace->heap.final_num--;

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
	run_final(objspace, (VALUE)p);
	objspace->total_freed_object_num++;
	if (!FL_TEST(p, FL_SINGLETON)) { /* not freeing page */
	    heap_slot_add_freeobj(objspace, GET_HEAP_SLOT(p), (VALUE)p);
	    objspace->heap.free_num++;
	}
	else {
	    struct heap_slot *slot = (struct heap_slot *)(VALUE)RDATA(p)->dmark;
	    slot->limit--;
	}
	p = tmp;
    }
}

static void
finalize_deferred(rb_objspace_t *objspace)
{
    RVALUE *p = deferred_final_list;
    deferred_final_list = 0;

    if (p) {
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
gc_finalize_deferred_register()
{
    rb_postponed_job_register_one(0, gc_finalize_deferred, 0);
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
    RVALUE *final_list = 0;
    size_t i;

    gc_rest_sweep(objspace);

    if (ATOMIC_EXCHANGE(finalizing, 1)) return;

    /* run finalizers */
    finalize_deferred(objspace);
    assert(deferred_final_list == 0);

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
    for (i = 0; i < heap_used; i++) {
	p = objspace->heap.sorted[i]->start; pend = p + objspace->heap.sorted[i]->limit;
	while (p < pend) {
	    if (BUILTIN_TYPE(p) == T_DATA &&
		DATA_PTR(p) && RANY(p)->as.data.dfree &&
		!rb_obj_is_thread((VALUE)p) &&
		!rb_obj_is_mutex((VALUE)p) &&
		!rb_obj_is_fiber((VALUE)p)) {
		p->as.free.flags = 0;
		if (RTYPEDDATA_P(p)) {
		    RDATA(p)->dfree = RANY(p)->as.typeddata.type->function.dfree;
		}
		if (RANY(p)->as.data.dfree == (RUBY_DATA_FUNC)-1) {
		    xfree(DATA_PTR(p));
		}
		else if (RANY(p)->as.data.dfree) {
		    make_deferred(RANY(p));
		    RANY(p)->as.free.next = final_list;
		    final_list = p;
		}
	    }
	    else if (BUILTIN_TYPE(p) == T_FILE) {
		if (RANY(p)->as.file.fptr) {
		    make_io_deferred(RANY(p));
		    RANY(p)->as.free.next = final_list;
		    final_list = p;
		}
	    }
	    p++;
	}
    }
    during_gc = 0;
    if (final_list) {
	finalize_list(objspace, final_list);
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
is_swept_object(rb_objspace_t *objspace, VALUE ptr)
{
    struct heap_slot *slot = objspace->heap.sweep_slots;

    while (slot) {
	if ((VALUE)slot->start <= ptr && ptr < (VALUE)(slot->start + slot->limit))
	    return FALSE;
	slot = slot->next;
    }
    return TRUE;
}

static inline int
is_dead_object(rb_objspace_t *objspace, VALUE ptr)
{
    if (!is_lazy_sweeping(objspace) || MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(ptr), ptr))
	return FALSE;
    if (!is_swept_object(objspace, ptr))
	return TRUE;
    return FALSE;
}

static inline int
is_live_object(rb_objspace_t *objspace, VALUE ptr)
{
    if (BUILTIN_TYPE(ptr) == 0) return FALSE;
    if (RBASIC(ptr)->klass == 0) return FALSE;
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
    return is_markable_object(&rb_objspace, obj);
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

    for (i = 0; i < heap_used; i++) {
	struct heap_slot *slot = objspace->heap.sorted[i];
	RVALUE *p, *pend;

	p = slot->start; pend = p + slot->limit;
	for (;p < pend; p++) {
	    if (p->as.basic.flags) {
		counts[BUILTIN_TYPE(p)]++;
	    }
	    else {
		freed++;
	    }
	}
	total += slot->limit;
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
objspace_live_num(rb_objspace_t *objspace)
{
    return objspace->total_allocated_object_num - objspace->total_freed_object_num;
}

static void
gc_setup_mark_bits(struct heap_slot *slot)
{
#if USE_RGENGC
    /* copy oldgen bitmap to mark bitmap */
    memcpy(&slot->mark_bits[0], &slot->oldgen_bits[0], HEAP_BITMAP_SIZE);
#else
    /* clear mark bitmap */
    memset(&slot->mark_bits[0], 0, HEAP_BITMAP_SIZE);
#endif
}

static inline void
gc_slot_sweep(rb_objspace_t *objspace, struct heap_slot *sweep_slot)
{
    int i;
    size_t empty_num = 0, freed_num = 0, final_num = 0;
    RVALUE *p, *pend,*offset;
    RVALUE *final = deferred_final_list;
    int deferred;
    bits_t *bits, bitset;

    rgengc_report(1, objspace, "slot_sweep: start.\n");

    p = sweep_slot->start; pend = p + sweep_slot->limit;
    offset = p - NUM_IN_SLOT(p);
    bits = GET_HEAP_MARK_BITS(p);

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
			rgengc_report(3, objspace, "slot_sweep: free %p (%s)\n", p, obj_type_name((VALUE)p));
#if USE_RGENGC && RGENGC_CHECK_MODE
			if (objspace->rgengc.during_minor_gc && RVALUE_PROMOTED(p)) rb_bug("slot_sweep: %p (%s) is promoted.\n", p, obj_type_name((VALUE)p));
			if (rgengc_remembered(objspace, (VALUE)p)) rb_bug("slot_sweep: %p (%s) is remembered.\n", p, obj_type_name((VALUE)p));
#endif
			if ((deferred = obj_free(objspace, (VALUE)p)) || (FL_TEST(p, FL_FINALIZE))) {
			    if (!deferred) {
				p->as.free.flags = T_ZOMBIE;
				RDATA(p)->dfree = 0;
			    }
			    p->as.free.next = deferred_final_list;
			    deferred_final_list = p;
			    assert(BUILTIN_TYPE(p) == T_ZOMBIE);
			    final_num++;
			}
			else {
			    (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
			    heap_slot_add_freeobj(objspace, sweep_slot, (VALUE)p);
			    rgengc_report(3, objspace, "slot_sweep: %p (%s) is added to freelist\n", p, obj_type_name((VALUE)p));
			    freed_num++;
			}
		    }
		    else {
			empty_num++;
		    }
		}
		p++;
		bitset >>= 1;
	    } while (bitset);
	}
    }

    gc_setup_mark_bits(sweep_slot);

#if GC_PROFILE_MORE_DETAIL
    if (objspace->profile.run) {
	gc_profile_record *record = gc_prof_record(objspace);
	record->removing_objects += final_num + freed_num;
	record->empty_objects += empty_num;
    }
#endif

    if (final_num + freed_num + empty_num == sweep_slot->limit &&
	objspace->heap.free_num > objspace->heap.do_heap_free) {
        RVALUE *pp;

        for (pp = deferred_final_list; pp != final; pp = pp->as.free.next) {
	    RDATA(pp)->dmark = (void (*)(void *))(VALUE)sweep_slot;
            pp->as.free.flags |= FL_SINGLETON; /* freeing page mark */
        }
        sweep_slot->limit = final_num;
        unlink_heap_slot(objspace, sweep_slot);
    }
    else {
	if (freed_num + empty_num > 0) {
	    heap_add_freeslot(objspace, sweep_slot);
	}
	else {
	    sweep_slot->free_next = NULL;
	}
	objspace->heap.free_num += freed_num + empty_num;
    }
    objspace->total_freed_object_num += freed_num;
    objspace->heap.final_num += final_num;

    if (deferred_final_list && !finalizing) {
        rb_thread_t *th = GET_THREAD();
        if (th) {
	    gc_finalize_deferred_register();
        }
    }

    rgengc_report(1, objspace, "slot_sweep: end.\n");
}

#if defined(__GNUC__) && __GNUC__ == 4 && __GNUC_MINOR__ == 4
__attribute__((noinline))
#endif
static void
gc_before_sweep(rb_objspace_t *objspace)
{
    rgengc_report(1, objspace, "before_gc_sweep\n");

    objspace->heap.do_heap_free = (size_t)((heap_used * HEAP_OBJ_LIMIT) * 0.65);
    objspace->heap.free_min = (size_t)((heap_used * HEAP_OBJ_LIMIT)  * 0.2);
    if (objspace->heap.free_min < initial_free_min) {
        objspace->heap.free_min = initial_free_min;
	if (objspace->heap.do_heap_free < initial_free_min)
	    objspace->heap.do_heap_free = initial_free_min;
    }
    objspace->heap.sweep_slots = heap_slots;
    objspace->heap.free_num = 0;
    objspace->heap.free_slots = NULL;

    if (objspace->heap.using_slot) {
	objspace->heap.using_slot->freelist = objspace->freelist;
	objspace->heap.using_slot = NULL;
    }
    objspace->freelist = NULL;

    malloc_increase2 += ATOMIC_SIZE_EXCHANGE(malloc_increase,0);

    /* sweep unlinked method entries */
    if (GET_VM()->unlinked_method_entry_list) {
	rb_sweep_method_entry(GET_VM());
    }
}

static void
gc_after_sweep(rb_objspace_t *objspace)
{
    size_t inc;

    rgengc_report(1, objspace, "after_gc_sweep: objspace->heap.free_num: %d, objspace->heap.free_min: %d\n",
		  objspace->heap.free_num, objspace->heap.free_min);

    if (objspace->heap.free_num < objspace->heap.free_min) {
	heap_set_increment(objspace);
	heap_increment(objspace);

#if USE_RGENGC
	if (objspace->rgengc.remembered_shady_object_count + objspace->rgengc.oldgen_object_count > (heap_length * HEAP_OBJ_LIMIT) / 2) {
	    /* if [oldgen]+[remembered shady] > [all object count]/2, then do major GC */
	    objspace->rgengc.need_major_gc = TRUE;
	}
#endif
    }

    gc_prof_set_malloc_info(objspace);
    gc_prof_set_heap_info(objspace);

    inc = ATOMIC_SIZE_EXCHANGE(malloc_increase, 0);
    inc += malloc_increase2;
    malloc_increase2 = 0;

    if (inc > malloc_limit) {
	malloc_limit +=
	  (size_t)((inc - malloc_limit) * (double)objspace_live_num(objspace) / (heap_used * HEAP_OBJ_LIMIT));
	if (malloc_limit < initial_malloc_limit) malloc_limit = initial_malloc_limit;
    }

    free_unused_slots(objspace);

    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_END, 0 /* TODO: pass minor/immediate flag? */);
}

static int
gc_lazy_sweep(rb_objspace_t *objspace)
{
    struct heap_slot *slot, *next;
    int result = FALSE;

    gc_prof_sweep_timer_start(objspace);

    heap_increment(objspace);

    slot = objspace->heap.sweep_slots;

    while (slot) {
	objspace->heap.sweep_slots = next = slot->next;

	gc_slot_sweep(objspace, slot);

	if (!next) gc_after_sweep(objspace);

	if (objspace->heap.free_slots) {
            result = TRUE;
	    break;
        }

	slot = next;
    }

    gc_prof_sweep_timer_stop(objspace);

    return result;
}

static void
gc_rest_sweep(rb_objspace_t *objspace)
{
    if (is_lazy_sweeping(objspace)) {
	during_gc++;
	while (is_lazy_sweeping(objspace)) {
	    gc_lazy_sweep(objspace);
	}
	during_gc = 0;
    }
}

static void
gc_sweep(rb_objspace_t *objspace, int immediate_sweep)
{
    if (immediate_sweep) {
	struct heap_slot *next;
	gc_prof_sweep_timer_start(objspace);
	gc_before_sweep(objspace);

	while (objspace->heap.sweep_slots) {
	    next = objspace->heap.sweep_slots->next;
	    gc_slot_sweep(objspace, objspace->heap.sweep_slots);
	    objspace->heap.sweep_slots = next;
	}

	gc_after_sweep(objspace);
	gc_prof_sweep_timer_stop(objspace);
    }
    else {
	gc_before_sweep(objspace);
	gc_lazy_sweep(objspace);
    }

    if (!objspace->heap.free_slots) {
	/* there is no free after slot_sweep() */
	heap_set_increment(objspace);
	if (!heap_increment(objspace)) { /* can't allocate additional free objects */
	    during_gc = 0;
	    rb_memerror();
	}
    }
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
is_mark_stask_empty(mark_stack_t *stack)
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
    if (is_mark_stask_empty(stack)) {
        return FALSE;
    }
    if (stack->index == 1) {
        *data = stack->chunk->data[--stack->index];
        pop_mark_stack_chunk(stack);
        return TRUE;
    }
    *data = stack->chunk->data[--stack->index];
    return TRUE;
}

static void
init_mark_stack(mark_stack_t *stack)
{
    int i;

    push_mark_stack_chunk(stack);
    stack->limit = STACK_CHUNK_SIZE;

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
mark_m_tbl(rb_objspace_t *objspace, st_table *tbl)
{
    struct mark_tbl_arg arg;
    if (!tbl) return;
    arg.objspace = objspace;
    st_foreach(tbl, mark_method_entry_i, (st_data_t)&arg);
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

static int
gc_marked(rb_objspace_t *objspace, VALUE ptr)
{
    register bits_t *bits = GET_HEAP_MARK_BITS(ptr);
    if (MARKED_IN_BITMAP(bits, ptr)) return 1;
    return 0;
}

static int
gc_mark_ptr(rb_objspace_t *objspace, VALUE ptr)
{
    register bits_t *bits = GET_HEAP_MARK_BITS(ptr);
    if (gc_marked(objspace, ptr)) return 0;
    MARK_IN_BITMAP(bits, ptr);
    return 1;
}

static void
rgengc_check_shady(rb_objspace_t *objspace, VALUE obj)
{
#if USE_RGENGC
#if RGENGC_CHECK_MODE >= 2
#define SAVED_OLD(x) MARKED_IN_BITMAP(GET_HEAP_SLOT(x)->saved_oldgen_bits, (x))
#define SAVED_REM(x) MARKED_IN_BITMAP(GET_HEAP_SLOT(x)->saved_rememberset_bits, (x))
    VALUE parent = objspace->rgengc.parent_object;

    if (objspace->rgengc.have_saved_bitmaps && !monitor_level) {
	/* check WB sanity */
	if (!SAVED_OLD(obj) &&                          /* obj is young object (newly created or shady) */
	    (!FIXNUM_P(parent) && SAVED_OLD(parent)) && /* parent was old */
	    !SAVED_REM(parent) &&                       /* parent was not remembered */
	    !SAVED_REM(obj)) {                          /* obj was not remembered */
	    fprintf(stderr, "rgengc_check_shady: !!! WB miss: %p (%s) -> %p (%s)\n",
		    (void *)parent, obj_type_name(parent),
		    (void *)obj, obj_type_name(obj));
	    if(!st_lookup(monitored_object_table, (st_data_t)obj, NULL)) {
		st_insert(monitored_object_table, (st_data_t)obj, 1);
	    }
	}
    } else if (monitor_level) {
	st_data_t v;
	if (st_lookup(monitored_object_table, (st_data_t)obj, &v)) {
	    if (v == monitor_level) {
		if (FIXNUM_P(parent)) {
		    fprintf(stderr, "rgengc_check_shady: %14s [line %d] -> %p (%s) %d\n",
			    "",FIX2INT(parent), (void *)obj, obj_type_name(obj),monitor_level);
		}
		else {
		    if (st_lookup(monitored_object_table, (st_data_t)parent, &v)) {
			if(parent == obj) {
			    /* skip self reference infomation */
			}
			else
			    fprintf(stderr, "rgengc_check_shady: %14u %p (%-8s) -> %p (%-8s) %d\n",(unsigned int)v,
				    (void *)parent, obj_type_name(parent), (void *)obj, obj_type_name(obj),monitor_level);
		    } else {
			char const *marker = NULL;
			if (SAVED_REM(parent)) {
			    if (SAVED_OLD(parent))
				marker = "REMEMBERED OLD";
			    else
				marker = "REMEMBERED";
			} else {
			    if (SAVED_OLD(parent))
				marker = "!!!!!!!!!!!!! NO REMEMBERED OLD !!!!!!!!!!!!! ";
			    else {
				marker = "NO PROMOTED";
				st_insert(monitored_object_table, (st_data_t)parent, v+1);
			    }
			}
			fprintf(stderr, "rgengc_check_shady: %-14s %p (%-8s) -> %p (%-8s) %d\n",
				marker,
				(void *)parent, obj_type_name(parent), (void *)obj, obj_type_name(obj),monitor_level);
		    }
		}
	    }
	}
    }
#undef SAVED_OLD
#undef SAVED_REM
#endif /* RGENGC_CHECK_MODE >= 2 */

    if (objspace->rgengc.parent_object_is_promoted && RVALUE_SHADY(obj)) {
	if (rgengc_remember(objspace, obj)) {
	    objspace->rgengc.remembered_shady_object_count++;
	}
    }
#endif
}

static void
gc_mark(rb_objspace_t *objspace, VALUE ptr)
{
    if (!is_markable_object(objspace, ptr)) return;

    if (LIKELY(objspace->mark_func_data == 0)) {
	rgengc_check_shady(objspace, ptr);
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

static void
gc_mark_children(rb_objspace_t *objspace, VALUE ptr)
{
    register RVALUE *obj = RANY(ptr);

#if RGENGC_CHECK_MODE >= 2
    objspace->rgengc.parent_object = (VALUE)ptr;
#endif

    goto marking;		/* skip */

  again:
    if (LIKELY(objspace->mark_func_data == 0)) {
	obj = RANY(ptr);
	if (!is_markable_object(objspace, ptr)) return;
	rgengc_check_shady(objspace, ptr);
	if (!gc_mark_ptr(objspace, ptr)) return;  /* already marked */
#if RGENGC_CHECK_MODE >= 2
	objspace->rgengc.parent_object = (VALUE)ptr;
#endif
    }
    else {
	gc_mark(objspace, ptr);
	return;
    }

#if USE_RGENGC
    if (RGENGC_CHECK_MODE && RVALUE_SHADY(obj) && RVALUE_PROMOTED(obj)) {
	rb_bug("gc_mark_children: (0) %p (%s) is shady and promoted.\n", (void *)obj, obj_type_name((VALUE)obj));
    }
#endif /* USE_RGENGC */

  marking:

#if USE_RGENGC
    if (LIKELY(objspace->mark_func_data == 0)) {
	if (RGENGC_CHECK_MODE && RVALUE_SHADY(obj) && RVALUE_PROMOTED(obj)) {
	    rb_bug("gc_mark_children: (1) %p (%s) is shady and promoted.\n", (void *)obj, obj_type_name((VALUE)obj));
	}

	/* minor/major common */
	if (!RVALUE_SHADY(obj)) {
	    objspace->rgengc.parent_object_is_promoted = TRUE;

	    if (!RVALUE_PROMOTED(obj)) {
		RVALUE_PROMOTE((VALUE)obj); /* non-shady object can be promoted to OLDGEN object */
		rgengc_report(3, objspace, "gc_mark_children: promote %p (%s).\n", (void *)obj, obj_type_name((VALUE)obj));

		objspace->rgengc.oldgen_object_count++;
	    }
	    else if (!objspace->rgengc.during_minor_gc) { /* major/full GC */
		objspace->rgengc.oldgen_object_count++;
	    }
	}
	else {
	    rgengc_report(3, objspace, "gc_mark_children: do not promote shady %p (%s).\n", (void *)obj, obj_type_name((VALUE)obj));
	    objspace->rgengc.parent_object_is_promoted = FALSE;
	}

	if (RGENGC_CHECK_MODE && RVALUE_SHADY(obj) && RVALUE_PROMOTED(obj)) {
	    rb_bug("gc_mark_children: (2) %p (%s) is shady and promoted.\n", (void *)obj, obj_type_name((VALUE)obj));
	}
    }
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
	    gc_mark(objspace, (VALUE)obj->as.node.u1.node);
	    ptr = (VALUE)obj->as.node.u3.node;
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
	mark_m_tbl(objspace, RCLASS_M_TBL(obj));
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
	    const VALUE *ptr = RARRAY_RAWPTR(obj);
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
	    const VALUE *ptr = RSTRUCT_RAWPTR(obj);

	    while (len--) {
		gc_mark(objspace, *ptr++);
	    }
	}
	break;

      default:
#ifdef GC_DEBUG
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
        gc_mark_children(objspace, obj);
    }
    shrink_stack_chunk_cache(mstack);
}

static void
gc_marks_body(rb_objspace_t *objspace, int minor_gc)
{
    struct gc_list *list;
    rb_thread_t *th = GET_THREAD();

    /* start marking */
    rgengc_report(1, objspace, "gc_marks_body: start (%s)\n", minor_gc ? "minor" : "major");

#if USE_RGENGC
    objspace->rgengc.parent_object_is_promoted = FALSE;
    objspace->rgengc.parent_object = Qundef;
    objspace->rgengc.during_minor_gc = minor_gc;

    if (objspace->rgengc.during_minor_gc) {
	objspace->profile.minor_gc_count++;
	rgengc_rememberset_mark(objspace);
    }
    else {
	objspace->profile.major_gc_count++;
	rgengc_mark_and_rememberset_clear(objspace);
    }
#endif

#if RGENGC_CHECK_MODE > 1
#define MARK_CHECKPOINT do {objspace->rgengc.parent_object = INT2FIX(__LINE__);} while (0)
#else
#define MARK_CHECKPOINT
#endif

    MARK_CHECKPOINT;
    SET_STACK_END;
    th->vm->self ? rb_gc_mark(th->vm->self) : rb_vm_mark(th->vm);

    MARK_CHECKPOINT;
    mark_tbl(objspace, finalizer_table);

    MARK_CHECKPOINT;
    mark_current_machine_context(objspace, th);

    MARK_CHECKPOINT;
    rb_gc_mark_symbols();

    MARK_CHECKPOINT;
    rb_gc_mark_encodings();

    /* mark protected global variables */
    MARK_CHECKPOINT;
    for (list = global_List; list; list = list->next) {
	rb_gc_mark_maybe(*list->varptr);
    }

    MARK_CHECKPOINT;
    rb_mark_end_proc();

    MARK_CHECKPOINT;
    rb_gc_mark_global_tbl();

    MARK_CHECKPOINT;
    mark_tbl(objspace, rb_class_tbl);

    /* mark generic instance variables for special constants */
    MARK_CHECKPOINT;
    rb_mark_generic_ivar_tbl();

    MARK_CHECKPOINT;
    rb_gc_mark_parser();

    MARK_CHECKPOINT;
    rb_gc_mark_unlinked_live_method_entries(th->vm);

    /* marking-loop */
    gc_mark_stacked_objects(objspace);

#undef MARK_CHECKPOINT

    /* cleanup */
    rgengc_report(1, objspace, "gc_marks_body: end (%s)\n", minor_gc ? "minor" : "major");
}

#if RGENGC_CHECK_MODE >= 2

static void
gc_oldgen_bitmap2flag(struct heap_slot *slot)
{
    bits_t *oldgen_bits = &slot->oldgen_bits[0];
    RVALUE *p = slot->start;
    RVALUE *pend = p + slot->limit;

    while (p < pend) {
	if (MARKED_IN_BITMAP(oldgen_bits, p)) FL_SET2(p, FL_OLDGEN);
	else                                  FL_UNSET2(p, FL_OLDGEN);
	p++;
    }
}

static bits_t *
gc_export_bitmaps(rb_objspace_t *objspace)
{
    bits_t *exported_bitmaps = (bits_t *)malloc(HEAP_BITMAP_SIZE * heap_used * 3);
    size_t i;

    if (exported_bitmaps == 0) rb_bug("gc_store_bitmaps: not enough memory to test.\n");

    for (i=0; i<heap_used; i++) {
	struct heap_slot *slot = objspace->heap.sorted[i];

	memcpy(&exported_bitmaps[(3*i+0)*HEAP_BITMAP_LIMIT], &slot->mark_bits[0],        HEAP_BITMAP_SIZE);
	memcpy(&exported_bitmaps[(3*i+1)*HEAP_BITMAP_LIMIT], &slot->rememberset_bits[0], HEAP_BITMAP_SIZE);
	memcpy(&exported_bitmaps[(3*i+2)*HEAP_BITMAP_LIMIT], &slot->oldgen_bits[0],      HEAP_BITMAP_SIZE);
    }

    return exported_bitmaps;
}

static void
gc_restore_exported_bitmaps(rb_objspace_t *objspace, bits_t *exported_bitmaps)
{
    size_t i;

    for (i=0; i<heap_used; i++) {
	struct heap_slot *slot = objspace->heap.sorted[i];

	/* restore bitmaps */
	memcpy(&slot->mark_bits[0],        &exported_bitmaps[(3*i+0)*HEAP_BITMAP_LIMIT], HEAP_BITMAP_SIZE);
	memcpy(&slot->rememberset_bits[0], &exported_bitmaps[(3*i+1)*HEAP_BITMAP_LIMIT], HEAP_BITMAP_SIZE);
	memcpy(&slot->oldgen_bits[0],      &exported_bitmaps[(3*i+2)*HEAP_BITMAP_LIMIT], HEAP_BITMAP_SIZE);

	/* restore oldgen flags */
	gc_oldgen_bitmap2flag(slot);
    }
}

static void
gc_free_exported_bitmaps(rb_objspace_t *objspace, bits_t *exported_bitmaps)
{
    free(exported_bitmaps);
}

static void
gc_save_bitmaps(rb_objspace_t *objspace)
{
    size_t i;

    for (i=0; i<heap_used; i++) {
	struct heap_slot *slot = objspace->heap.sorted[i];

	/* save bitmaps */
	memcpy(&slot->saved_mark_bits[0],        &slot->mark_bits[0],        HEAP_BITMAP_SIZE);
	memcpy(&slot->saved_rememberset_bits[0], &slot->rememberset_bits[0], HEAP_BITMAP_SIZE);
	memcpy(&slot->saved_oldgen_bits[0],      &slot->oldgen_bits[0],      HEAP_BITMAP_SIZE);
    }

    objspace->rgengc.have_saved_bitmaps = TRUE;
}

static void
gc_load_bitmaps(rb_objspace_t *objspace)
{
    size_t i;

    for (i=0; i<heap_used; i++) {
	struct heap_slot *slot = objspace->heap.sorted[i];

	/* load bitmaps */
	memcpy(&slot->mark_bits[0],        &slot->saved_mark_bits[0],        HEAP_BITMAP_SIZE);
	memcpy(&slot->rememberset_bits[0], &slot->saved_rememberset_bits[0], HEAP_BITMAP_SIZE);
	memcpy(&slot->oldgen_bits[0],      &slot->saved_oldgen_bits[0],      HEAP_BITMAP_SIZE);

	gc_oldgen_bitmap2flag(slot);
    }
}

static void
gc_marks_test(rb_objspace_t *objspace)
{
    bits_t *exported_bitmaps;
    size_t i;
    size_t stored_oldgen, stored_shady;
    /*
     * Now, we have 2 types bitmaps:
     *   saved_bitmap:    before minor marking
     *   exported_bitmap: after minor marking
     */


    if(!monitored_object_table)
	monitored_object_table = st_init_numtable();
    gc_save_bitmaps(objspace);

    rgengc_report(1, objspace, "gc_marks_test: minor gc\n");
    {
	gc_marks_body(objspace, TRUE);
    }
    exported_bitmaps = gc_export_bitmaps(objspace);

    rgengc_report(1, objspace, "gc_marks_test: test-full-gc\n");

    /* run major (full) gc with temporary mark/rememberset */
    stored_oldgen = objspace->rgengc.oldgen_object_count;
    stored_shady = objspace->rgengc.remembered_shady_object_count;
    {
	gc_marks_body(objspace, FALSE);
    }
    objspace->rgengc.during_minor_gc = TRUE;
    objspace->rgengc.oldgen_object_count = stored_oldgen;
    objspace->rgengc.remembered_shady_object_count = stored_shady;

    /* check */
    for (i=0; i<heap_used; i++) {
	bits_t *minor_mark_bits = &exported_bitmaps[(3*i+0)*HEAP_BITMAP_LIMIT];
	bits_t *major_mark_bits = objspace->heap.sorted[i]->mark_bits;
	RVALUE *p = objspace->heap.sorted[i]->start;
	RVALUE *pend = p + objspace->heap.sorted[i]->limit;

	while (p < pend) {
	    if (MARKED_IN_BITMAP(major_mark_bits, p) &&  /* should be lived */
		!MARKED_IN_BITMAP(minor_mark_bits, p)) { /* not marked -> BUG! */
		fprintf(stderr, "gc_marks_test: %p (%s) is living, but not marked && not promoted.\n", p, obj_type_name((VALUE)p));
		st_insert(monitored_object_table, (st_data_t)p, 1);
	    }
	    p++;
	}
    }

    if (monitored_object_table->num_entries) {
	if (RGENGC_CHECK_MODE >= 3) {
	    st_index_t old_num;
	    do {
		old_num = monitored_object_table->num_entries;
		monitor_level ++;
		fprintf(stderr, "!!!! restart major gc for get more information !!!!\n");
		gc_load_bitmaps(objspace);
		gc_marks_body(objspace, FALSE);
	    } while (old_num != monitored_object_table->num_entries);
	}
	rb_bug("WriteBarrier Error\n");
    }
    else {
	gc_restore_exported_bitmaps(objspace, exported_bitmaps);
	gc_free_exported_bitmaps(objspace, exported_bitmaps);
	objspace->rgengc.have_saved_bitmaps = FALSE;
    }
}
#endif /* RGENGC_CHECK_MODE >= 2 */

static void
gc_marks(rb_objspace_t *objspace, int minor_gc)
{
    struct mark_func_data_struct *prev_mark_func_data;

    gc_prof_mark_timer_start(objspace);
    {
	/* setup marking */
	prev_mark_func_data = objspace->mark_func_data;
	objspace->mark_func_data = 0;

#if USE_RGENGC
	if (minor_gc == FALSE) { /* major/full GC */
	    objspace->rgengc.remembered_shady_object_count = 0;
	    objspace->rgengc.oldgen_object_count = 0;

	    gc_marks_body(objspace, FALSE);

	    /* Do full GC if old/remembered_shady object counts is greater than counts two times at last full GC counts */
	    objspace->rgengc.remembered_shady_object_limit = objspace->rgengc.remembered_shady_object_count * 2;
	    objspace->rgengc.oldgen_object_limit = objspace->rgengc.oldgen_object_count * 2;
	}
	else { /* minor GC */
#if RGENGC_CHECK_MODE >= 2
	    gc_marks_test(objspace);
#else
	    gc_marks_body(objspace, TRUE);
#endif
	}

#if RGENGC_PROFILE > 0
    if (gc_prof_record(objspace)) {
	gc_profile_record *record = gc_prof_record(objspace);
	record->oldgen_objects = objspace->rgengc.oldgen_object_count;
    }
#endif

#else /* USE_RGENGC */
	gc_marks_body(objspace, FALSE);
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
		  RVALUE_SHADY(obj) ? "shady" : "non-shady",
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
	    if (!RVALUE_SHADY(obj)) {
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
	}
    }

    return rgengc_remembersetbits_set(objspace, obj);
}

static int
rgengc_remembered(rb_objspace_t *objspace, VALUE obj)
{
    int result = rgengc_remembersetbits_get(objspace, obj);
    check_bitmap_consistency(obj);
    rgengc_report(6, objspace, "gc_remembered: %p (%s) => %d\n", (void *)obj, obj_type_name(obj), result);
    return result;
}

static void
rgengc_rememberset_mark(rb_objspace_t *objspace)
{
    size_t i, j;
    RVALUE *p, *offset;
    bits_t *bits, bitset;

#if RGENGC_PROFILE > 0
    size_t shady_object_count = 0, clear_count = 0;
#endif

    for (i=0; i<heap_used; i++) {
	p = objspace->heap.sorted[i]->start;
	bits = GET_HEAP_REMEMBERSET_BITS(p);

	offset = p - NUM_IN_SLOT(p);

	for (j=0; j < HEAP_BITMAP_LIMIT; j++) {
	    if (bits[j]) {
		p = offset  + j * BITS_BITLENGTH;
		bitset = bits[j];
		do {
		    if (bitset & 1) {
			rgengc_report(2, objspace, "rgengc_rememberset_mark: mark %p (%s)\n", p, obj_type_name((VALUE)p));

			gc_mark_ptr(objspace, (VALUE)p);
			gc_mark_children(objspace, (VALUE) p);

			if (!RVALUE_SHADY(p)) {
			    rgengc_report(2, objspace, "rgengc_rememberset_mark: clear %p (%s)\n", p, obj_type_name((VALUE)p));
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
		    }
		    p++;
		    bitset >>= 1;
		} while (bitset);
	    }
	}
    }

    rgengc_report(2, objspace, "rgengc_rememberset_mark: finished");

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
rgengc_mark_and_rememberset_clear(rb_objspace_t *objspace)
{
    size_t i;

    for (i=0; i<heap_used; i++) {
	struct heap_slot *slot = objspace->heap.sorted[i];
	memset(&slot->mark_bits[0],        0, HEAP_BITMAP_SIZE);
	memset(&slot->rememberset_bits[0], 0, HEAP_BITMAP_SIZE);
    }
}

/* RGENGC: APIs */

void
rb_gc_writebarrier(VALUE a, VALUE b)
{
    rb_objspace_t *objspace = &rb_objspace;
    int type;

    if (RGENGC_CHECK_MODE) {
	if (!RVALUE_PROMOTED(a)) rb_bug("rb_gc_wb: referer object %p (%s) is not promoted.\n", (void *)a, obj_type_name(a));
	if (RVALUE_PROMOTED(b)) rb_bug("rb_gc_wb: refered object %p (%s) is promoted.\n", (void *)b, obj_type_name(b));
    }

    if (!rgengc_remembered(objspace, a)) {
        type = BUILTIN_TYPE(a);
        /* TODO: 2 << 16 is just a magic number. */
        if ((type == T_ARRAY && RARRAY_LEN(a) >= 2 << 16) ||
            (type == T_HASH  && RHASH_SIZE(a) >= 2 << 16)) {
            if (!rgengc_remembered(objspace, b)) {
                rgengc_report(2, objspace, "rb_gc_wb: %p (%s) -> %p (%s)\n",
                              (void *)a, obj_type_name(a), (void *)b, obj_type_name(b));
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

void
rb_gc_writebarrier_unprotect_promoted(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;

    if (RGENGC_CHECK_MODE) {
	if (!RVALUE_PROMOTED(obj)) rb_bug("rb_gc_writebarrier_unprotect_promoted: called on non-promoted object");
	if (!RVALUE_SHADY(obj)) rb_bug("rb_gc_writebarrier_unprotect_promoted: called on non-shady object");
    }

    rgengc_report(2, objspace, "rb_gc_writebarrier_unprotect_promoted: %p (%s)%s\n", (void *)obj, obj_type_name(obj),
		  rgengc_remembered(objspace, obj) ? " (already remembered)" : "");

    RVALUE_DEMOTE(obj);

    rgengc_remember(objspace, obj);
    objspace->rgengc.remembered_shady_object_count++;

#if RGENGC_PROFILE
    objspace->profile.shade_operation_count++;
#if RGENGC_PROFILE >= 2
    objspace->profile.shade_operation_count_types[BUILTIN_TYPE(obj)]++;
#endif /* RGENGC_PROFILE >= 2 */
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

/* GC */

void
rb_gc_force_recycle(VALUE p)
{
    rb_objspace_t *objspace = &rb_objspace;

#if USE_RGENGC
    CLEAR_IN_BITMAP(GET_HEAP_REMEMBERSET_BITS(p), p);
    CLEAR_IN_BITMAP(GET_HEAP_OLDGEN_BITS(p), p);
    if (!is_before_sweep(p)) {
	CLEAR_IN_BITMAP(GET_HEAP_MARK_BITS(p), p);
    }
#endif

    objspace->total_freed_object_num++;
    heap_slot_add_freeobj(objspace, GET_HEAP_SLOT(p), p);

    if (!MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(p), p)) {
	objspace->heap.free_num++;
    }
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

#if USE_RGENGC
    else {
	if (full_mark)
	    reason |= GPR_FLAG_MAJOR_BY_NOFREE;
	if (objspace->rgengc.need_major_gc) {
	    objspace->rgengc.need_major_gc = FALSE;
	    reason |= GPR_FLAG_MAJOR_BY_RESCAN;
	}
	if (objspace->rgengc.remembered_shady_object_count > objspace->rgengc.remembered_shady_object_limit)
	    reason |= GPR_FLAG_MAJOR_BY_SHADY;
	if (objspace->rgengc.oldgen_object_count > objspace->rgengc.oldgen_object_limit)
	    reason |= GPR_FLAG_MAJOR_BY_OLDGEN;

	if (!GC_ENABLE_LAZY_SWEEP || objspace->flags.dont_lazy_sweep) {
	    immediate_sweep = TRUE;
	}
    }
#endif

    if(immediate_sweep)
	reason |= GPR_FLAG_IMMEDIATE_SWEEP;

    if (GC_NOTIFY) fprintf(stderr, "start garbage_collect(%d, %d, %d)\n", full_mark, immediate_sweep, reason);

    objspace->count++;
    gc_event_hook(objspace, RUBY_INTERNAL_EVENT_GC_START, 0 /* TODO: pass minor/immediate flag? */);

    objspace->profile.total_allocated_object_num_at_gc_start = objspace->total_allocated_object_num;
    objspace->profile.heap_used_at_gc_start = heap_used;

    gc_prof_setup_new_record(objspace, reason);
    gc_prof_timer_start(objspace);
    {
	assert(during_gc > 0);
	gc_marks(objspace, (reason & GPR_FLAG_MAJOR_MASK) ? FALSE : TRUE);
	gc_sweep(objspace, immediate_sweep);
	during_gc = 0;
    }
    gc_prof_timer_stop(objspace);

    if (GC_NOTIFY) fprintf(stderr, "end garbage_collect()\n");
    return TRUE;
}

static int
ready_to_gc(rb_objspace_t *objspace)
{
    if (dont_gc || during_gc) {
	if (!objspace->freelist && !objspace->heap.free_slots) {
            if (!heap_increment(objspace)) {
		heap_set_increment(objspace);
                heap_increment(objspace);
            }
	}
	return FALSE;
    }
    return TRUE;
}

static int
garbage_collect(rb_objspace_t *objspace, int full_mark, int immediate_sweep, int reason)
{
    if (!heap_slots) {
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
 *     gc.garbage_collect           -> nil
 *     ObjectSpace.garbage_collect  -> nil
 *
 *  Initiates garbage collection, unless manually disabled.
 *
 */

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
    garbage_collect(objspace, TRUE, TRUE, GPR_FLAG_METHOD);
    if (!finalizing) finalize_deferred(objspace);
    free_unused_slots(objspace);
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
    return rb_objspace.count;
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

/*
 *  call-seq:
 *     GC.stat -> Hash
 *
 *  Returns a Hash containing information about the GC.
 *
 *  The hash includes information about internal statistics about GC such as:
 *
 *	{
 *	    :count=>0,
 *	    :heap_used=>12,
 *     	    :heap_length=>12,
 *     	    :heap_increment=>0,
 *     	    :heap_live_num=>7539,
 *     	    :heap_free_num=>88,
 *     	    :heap_final_num=>0,
 *     	    :total_allocated_object=>7630,
 *     	    :total_freed_object=>88
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
    rb_objspace_t *objspace = &rb_objspace;
    VALUE hash;
    static VALUE sym_count;
    static VALUE sym_heap_used, sym_heap_length, sym_heap_increment;
    static VALUE sym_heap_live_num, sym_heap_free_num, sym_heap_final_num;
    static VALUE sym_total_allocated_object, sym_total_freed_object;
#if USE_RGENGC
    static VALUE sym_minor_gc_count, sym_major_gc_count;
#if RGENGC_PROFILE
    static VALUE sym_generated_normal_object_count, sym_generated_shady_object_count;
    static VALUE sym_shade_operation_count, sym_promote_operation_count;
    static VALUE sym_remembered_normal_object_count, sym_remembered_shady_object_count;
#endif /* RGENGC_PROFILE */
#endif /* USE_RGENGC */

    if (sym_count == 0) {
#define S(s) sym_##s = ID2SYM(rb_intern_const(#s))
	S(count);
	S(heap_used);
	S(heap_length);
	S(heap_increment);
	S(heap_live_num);
	S(heap_free_num);
	S(heap_final_num);
	S(total_allocated_object);
	S(total_freed_object);
#if USE_RGENGC
	S(minor_gc_count);
	S(major_gc_count);
#if RGENGC_PROFILE
	S(generated_normal_object_count);
	S(generated_shady_object_count);
	S(shade_operation_count);
	S(promote_operation_count);
	S(remembered_normal_object_count);
	S(remembered_shady_object_count);
#endif /* USE_RGENGC */
#endif /* RGENGC_PROFILE */
#undef S
    }

    if (rb_scan_args(argc, argv, "01", &hash) == 1) {
	if (!RB_TYPE_P(hash, T_HASH)) {
	    rb_raise(rb_eTypeError, "non-hash given");
	}
    }

    if (hash == Qnil) {
        hash = rb_hash_new();
    }

    rb_hash_aset(hash, sym_count, SIZET2NUM(objspace->count));
    /* implementation dependent counters */
    rb_hash_aset(hash, sym_heap_used, SIZET2NUM(objspace->heap.used));
    rb_hash_aset(hash, sym_heap_length, SIZET2NUM(objspace->heap.length));
    rb_hash_aset(hash, sym_heap_increment, SIZET2NUM(objspace->heap.increment));
    rb_hash_aset(hash, sym_heap_live_num, SIZET2NUM(objspace_live_num(objspace)));
    rb_hash_aset(hash, sym_heap_free_num, SIZET2NUM(objspace->heap.free_num));
    rb_hash_aset(hash, sym_heap_final_num, SIZET2NUM(objspace->heap.final_num));
    rb_hash_aset(hash, sym_total_allocated_object, SIZET2NUM(objspace->total_allocated_object_num));
    rb_hash_aset(hash, sym_total_freed_object, SIZET2NUM(objspace->total_freed_object_num));
#if USE_RGENGC
    rb_hash_aset(hash, sym_minor_gc_count, SIZET2NUM(objspace->profile.minor_gc_count));
    rb_hash_aset(hash, sym_major_gc_count, SIZET2NUM(objspace->profile.major_gc_count));
#if RGENGC_PROFILE
    rb_hash_aset(hash, sym_generated_normal_object_count, SIZET2NUM(objspace->profile.generated_normal_object_count));
    rb_hash_aset(hash, sym_generated_shady_object_count, SIZET2NUM(objspace->profile.generated_shady_object_count));
    rb_hash_aset(hash, sym_shade_operation_count, SIZET2NUM(objspace->profile.shade_operation_count));
    rb_hash_aset(hash, sym_promote_operation_count, SIZET2NUM(objspace->profile.promote_operation_count));
    rb_hash_aset(hash, sym_remembered_normal_object_count, SIZET2NUM(objspace->profile.remembered_normal_object_count));
    rb_hash_aset(hash, sym_remembered_shady_object_count, SIZET2NUM(objspace->profile.remembered_shady_object_count));
#if RGENGC_PROFILE >= 2
    {
	gc_count_add_each_types(hash, "generated_normal_object_count_types", objspace->profile.generated_normal_object_count_types);
	gc_count_add_each_types(hash, "generated_shady_object_count_types", objspace->profile.generated_shady_object_count_types);
	gc_count_add_each_types(hash, "shade_operation_count_types", objspace->profile.shade_operation_count_types);
	gc_count_add_each_types(hash, "promote_operation_count_types", objspace->profile.promote_operation_count_types);
	gc_count_add_each_types(hash, "remembered_normal_object_count_types", objspace->profile.remembered_normal_object_count_types);
	gc_count_add_each_types(hash, "remembered_shady_object_count_types", objspace->profile.remembered_shady_object_count_types);
    }
#endif
#endif /* RGENGC_PROFILE */
#endif /* USE_RGENGC */

    return hash;
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

    dont_gc = TRUE;
    return old ? Qtrue : Qfalse;
}

void
rb_gc_set_params(void)
{
    char *malloc_limit_ptr, *heap_min_slots_ptr, *free_min_ptr, *growth_factor_ptr;

    if (rb_safe_level() > 0) return;

    malloc_limit_ptr = getenv("RUBY_GC_MALLOC_LIMIT");
    if (malloc_limit_ptr != NULL) {
	int malloc_limit_i = atoi(malloc_limit_ptr);
	if (RTEST(ruby_verbose))
	    fprintf(stderr, "malloc_limit=%d (%d)\n",
		    malloc_limit_i, initial_malloc_limit);
	if (malloc_limit_i > 0) {
	    initial_malloc_limit = malloc_limit_i;
	}
    }

    heap_min_slots_ptr = getenv("RUBY_HEAP_MIN_SLOTS");
    if (heap_min_slots_ptr != NULL) {
	int heap_min_slots_i = atoi(heap_min_slots_ptr);
	if (RTEST(ruby_verbose))
	    fprintf(stderr, "heap_min_slots=%d (%d)\n",
		    heap_min_slots_i, initial_heap_min_slots);
	if (heap_min_slots_i > 0) {
	    size_t min_size;
	    rb_objspace_t *objspace = &rb_objspace;

	    initial_heap_min_slots = heap_min_slots_i;
	    min_size = initial_heap_min_slots / HEAP_OBJ_LIMIT;

	    if (min_size > heap_used) {
		heap_add_slots(objspace, min_size - heap_used);
	    }
	}
    }

    growth_factor_ptr = getenv("RUBY_HEAP_SLOTS_GROWTH_FACTOR");
    if (growth_factor_ptr != NULL) {
	double growth_factor_f = strtod(growth_factor_ptr, NULL);
	if (RTEST(ruby_verbose))
	    fprintf(stderr, "heap_slots_growth_factor=%f (%f)\n",
		    growth_factor_f, initial_growth_factor);
	if (growth_factor_f > 1) {
	    initial_growth_factor = growth_factor_f;
	}
    }

    free_min_ptr = getenv("RUBY_FREE_MIN");
    if (free_min_ptr != NULL) {
	int free_min_i = atoi(free_min_ptr);
	if (RTEST(ruby_verbose))
	    fprintf(stderr, "free_min=%d (%d)\n", free_min_i, initial_free_min);
	if (free_min_i > 0) {
	    initial_free_min = free_min_i;
	}
    }
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

/*
  ------------------------ Extended allocator ------------------------
*/

static void vm_xfree(rb_objspace_t *objspace, void *ptr);

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
	(rb_thread_raised_p(th, RAISED_NOMEMORY) && rb_safe_level() < 4)) {
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

#if defined(_DEBUG) || defined(GC_DEBUG)
    /* alignment must be a power of 2 */
    assert((alignment - 1) & alignment == 0);
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
vm_malloc_prepare(rb_objspace_t *objspace, size_t size)
{
    if ((ssize_t)size < 0) {
	negative_size_allocation_error("negative allocation size (or too big)");
    }
    if (size == 0) size = 1;

#if CALC_EXACT_MALLOC_SIZE
    size += sizeof(size_t);
#endif

    ATOMIC_SIZE_ADD(malloc_increase, size);
    if ((ruby_gc_stress && !ruby_disable_gc_stress) ||
	malloc_increase > malloc_limit) {
	garbage_collect_with_gvl(objspace, 0, 0, GPR_FLAG_MALLOC);
    }

    return size;
}

static inline void *
vm_malloc_fixup(rb_objspace_t *objspace, void *mem, size_t size)
{
#if CALC_EXACT_MALLOC_SIZE
    ATOMIC_SIZE_ADD(objspace->malloc_params.allocated_size, size);
    ATOMIC_SIZE_INC(objspace->malloc_params.allocations);
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
vm_xmalloc(rb_objspace_t *objspace, size_t size)
{
    void *mem;

    size = vm_malloc_prepare(objspace, size);
    TRY_WITH_GC(mem = malloc(size));
    return vm_malloc_fixup(objspace, mem, size);
}

static void *
vm_xrealloc(rb_objspace_t *objspace, void *ptr, size_t size)
{
    void *mem;
#if CALC_EXACT_MALLOC_SIZE
    size_t oldsize;
#endif

    if ((ssize_t)size < 0) {
	negative_size_allocation_error("negative re-allocation size");
    }

    if (!ptr) return vm_xmalloc(objspace, size);

    /*
     * The behavior of realloc(ptr, 0) is implementation defined.
     * Therefore we don't use realloc(ptr, 0) for portability reason.
     * see http://www.open-std.org/jtc1/sc22/wg14/www/docs/dr_400.htm
     */
    if (size == 0) {
	vm_xfree(objspace, ptr);
	return 0;
    }
    if (ruby_gc_stress && !ruby_disable_gc_stress)
	garbage_collect_with_gvl(objspace, 0, 0, GPR_FLAG_MALLOC);

#if CALC_EXACT_MALLOC_SIZE
    size += sizeof(size_t);
    ptr = (size_t *)ptr - 1;
    oldsize = ((size_t *)ptr)[0];
#endif

    mem = realloc(ptr, size);
    if (!mem) {
	if (garbage_collect_with_gvl(objspace, 1, 1, GPR_FLAG_MALLOC)) {
	    mem = realloc(ptr, size);
	}
	if (!mem) {
	    ruby_memerror();
        }
    }
    ATOMIC_SIZE_ADD(malloc_increase, size);

#if CALC_EXACT_MALLOC_SIZE
    ATOMIC_SIZE_ADD(objspace->malloc_params.allocated_size, size - oldsize);
    ((size_t *)mem)[0] = size;
    mem = (size_t *)mem + 1;
#endif

    return mem;
}

static void
vm_xfree(rb_objspace_t *objspace, void *ptr)
{
#if CALC_EXACT_MALLOC_SIZE
    size_t size;
    ptr = ((size_t *)ptr) - 1;
    size = ((size_t*)ptr)[0];
    if (size) {
	ATOMIC_SIZE_SUB(objspace->malloc_params.allocated_size, size);
	ATOMIC_SIZE_DEC(objspace->malloc_params.allocations);
    }
#endif

    free(ptr);
}

void *
ruby_xmalloc(size_t size)
{
    return vm_xmalloc(&rb_objspace, size);
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
    return vm_xmalloc(&rb_objspace, xmalloc2_size(n, size));
}

static void *
vm_xcalloc(rb_objspace_t *objspace, size_t count, size_t elsize)
{
    void *mem;
    size_t size;

    size = xmalloc2_size(count, elsize);
    size = vm_malloc_prepare(objspace, size);

    TRY_WITH_GC(mem = calloc(1, size));
    return vm_malloc_fixup(objspace, mem, size);
}

void *
ruby_xcalloc(size_t n, size_t size)
{
    return vm_xcalloc(&rb_objspace, n, size);
}

void *
ruby_xrealloc(void *ptr, size_t size)
{
    return vm_xrealloc(&rb_objspace, ptr, size);
}

void *
ruby_xrealloc2(void *ptr, size_t n, size_t size)
{
    size_t len = size * n;
    if (n != 0 && size != len / n) {
	rb_raise(rb_eArgError, "realloc: possible integer overflow");
    }
    return ruby_xrealloc(ptr, len);
}

void
ruby_xfree(void *x)
{
    if (x)
	vm_xfree(&rb_objspace, x);
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

#if CALC_EXACT_MALLOC_SIZE
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

static int
wmap_mark_map(st_data_t key, st_data_t val, st_data_t arg)
{
    gc_mark_ptr((rb_objspace_t *)arg, (VALUE)val);
    return ST_CONTINUE;
}

static void
wmap_mark(void *ptr)
{
    struct weakmap *w = ptr;
    if (w->obj2wmap) st_foreach(w->obj2wmap, wmap_mark_map, (st_data_t)&rb_objspace);
    rb_gc_mark(w->final);
}

static int
wmap_free_map(st_data_t key, st_data_t val, st_data_t arg)
{
    rb_ary_resize((VALUE)val, 0);
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

size_t rb_ary_memsize(VALUE ary);
static int
wmap_memsize_map(st_data_t key, st_data_t val, st_data_t arg)
{
    *(size_t *)arg += rb_ary_memsize((VALUE)val);
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
    }
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
    VALUE wmap, ary;
    if (!existing) return ST_STOP;
    wmap = (VALUE)arg, ary = (VALUE)*value;
    rb_ary_delete_same(ary, wmap);
    if (!RARRAY_LEN(ary)) return ST_DELETE;
    return ST_CONTINUE;
}

static VALUE
wmap_finalize(VALUE self, VALUE objid)
{
    st_data_t orig, wmap, data;
    VALUE obj, rids;
    long i;
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    /* Get reference from object id. */
    obj = obj_id_to_ref(objid);

    /* obj is original referenced object and/or weak reference. */
    orig = (st_data_t)obj;
    if (st_delete(w->obj2wmap, &orig, &data)) {
	rids = (VALUE)data;
	for (i = 0; i < RARRAY_LEN(rids); ++i) {
	    wmap = (st_data_t)RARRAY_AREF(rids, i);
	    st_delete(w->wmap2obj, &wmap, NULL);
	}
    }

    wmap = (st_data_t)obj;
    if (st_delete(w->wmap2obj, &wmap, &orig)) {
	wmap = (st_data_t)obj;
	st_update(w->obj2wmap, orig, wmap_final_func, wmap);
    }
    return self;
}

/* Creates a weak reference from the given key to the given value */
static VALUE
wmap_aset(VALUE self, VALUE wmap, VALUE orig)
{
    st_data_t data;
    VALUE rids;
    struct weakmap *w;

    TypedData_Get_Struct(self, struct weakmap, &weakmap_type, w);
    rb_define_final(orig, w->final);
    rb_define_final(wmap, w->final);
    if (st_lookup(w->obj2wmap, (st_data_t)orig, &data)) {
	rids = (VALUE)data;
    }
    else {
	rids = rb_ary_tmp_new(1);
	st_insert(w->obj2wmap, (st_data_t)orig, (st_data_t)rids);
    }
    rb_ary_push(rids, wmap);
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


/*
  ------------------------------ GC profiler ------------------------------
*/

#define GC_PROFILE_RECORD_DEFAULT_SIZE 100

static double
getrusage_time(void)
{
#if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_PROCESS_CPUTIME_ID)
    struct timespec ts;

    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) == 0) {
        return ts.tv_sec + ts.tv_nsec * 1e-9;
    }
    return 0.0;
#elif defined RUSAGE_SELF
    struct rusage usage;
    struct timeval time;
    getrusage(RUSAGE_SELF, &usage);
    time = usage.ru_utime;
    return time.tv_sec + time.tv_usec * 1e-6;
#elif defined _WIN32
    FILETIME creation_time, exit_time, kernel_time, user_time;
    ULARGE_INTEGER ui;
    LONG_LONG q;
    double t;

    if (GetProcessTimes(GetCurrentProcess(),
			&creation_time, &exit_time, &kernel_time, &user_time) == 0)
    {
	return 0.0;
    }
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
#else
    return 0.0;
#endif
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
#if CALC_EXACT_MALLOC_SIZE
	record->allocated_size = malloc_allocated_size;
#endif
    }
}

static inline void
gc_prof_timer_start(rb_objspace_t *objspace)
{
    if (objspace->profile.run) {
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
    if (objspace->profile.run) {
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
    if (objspace->profile.run) {
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
    if (objspace->profile.run) {
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
    if (objspace->profile.run) {
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

    if (objspace->profile.run) {
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
	if (deferred_final_list) record->flags |= GPR_FLAG_HAVE_FINALIZE;
#endif
    }
}

static inline void
gc_prof_set_malloc_info(rb_objspace_t *objspace)
{
#if GC_PROFILE_MORE_DETAIL
    if (objspace->profile.run) {
        gc_profile_record *record = gc_prof_record(objspace);
	record->allocate_increase = malloc_increase + malloc_increase2;
	record->allocate_limit = malloc_limit;
    }
#endif
}

static inline void
gc_prof_set_heap_info(rb_objspace_t *objspace)
{
    if (objspace->profile.run) {
	gc_profile_record *record = gc_prof_record(objspace);
	size_t live = objspace->profile.total_allocated_object_num_at_gc_start - objspace->total_freed_object_num;
	size_t total = objspace->profile.heap_used_at_gc_start * HEAP_OBJ_LIMIT;

#if GC_PROFILE_MORE_DETAIL
	record->heap_use_slots = objspace->profile.heap_used_at_gc_start;
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

static VALUE
gc_profile_flags(int flags)
{
    VALUE result = rb_ary_new();
    rb_ary_push(result, ID2SYM(rb_intern(flags & GPR_FLAG_MAJOR_MASK ? "major_gc" : "minor_gc")));
    if (flags & GPR_FLAG_HAVE_FINALIZE) rb_ary_push(result, ID2SYM(rb_intern("HAVE_FINALIZE")));
    if (flags & GPR_FLAG_NEWOBJ)        rb_ary_push(result, ID2SYM(rb_intern("CAUSED_BY_NEWOBJ")));
    if (flags & GPR_FLAG_MALLOC)        rb_ary_push(result, ID2SYM(rb_intern("CAUSED_BY_MALLOC")));
    if (flags & GPR_FLAG_METHOD)        rb_ary_push(result, ID2SYM(rb_intern("CAUSED_BY_METHOD")));
    if (flags & GPR_FLAG_STRESS)        rb_ary_push(result, ID2SYM(rb_intern("CAUSED_BY_STRESS")));
    return result;
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
 *  +:HEAP_USE_SLOTS+::
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
	rb_hash_aset(prof, ID2SYM(rb_intern("GC_FLAGS")), gc_profile_flags(record->flags));
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
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_USE_SLOTS")), SIZET2NUM(record->heap_use_slots));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_LIVE_OBJECTS")), SIZET2NUM(record->heap_live_objects));
        rb_hash_aset(prof, ID2SYM(rb_intern("HEAP_FREE_OBJECTS")), SIZET2NUM(record->heap_free_objects));

	rb_hash_aset(prof, ID2SYM(rb_intern("REMOVING_OBJECTS")), SIZET2NUM(record->removing_objects));
	rb_hash_aset(prof, ID2SYM(rb_intern("EMPTY_OBJECTS")), SIZET2NUM(record->empty_objects));

	rb_hash_aset(prof, ID2SYM(rb_intern("HAVE_FINALIZE")), (record->flags & GPR_FLAG_HAVE_FINALIZE) ? Qtrue : Qfalse);
#endif

#if RGENGC_PROFILE > 0
	rb_hash_aset(prof, ID2SYM(rb_intern("OLDGEN_OBJECTS")), SIZET2NUM(record->oldgen_objects));
	rb_hash_aset(prof, ID2SYM(rb_intern("REMEMBED_NORMAL_OBJECTS")), SIZET2NUM(record->remembered_normal_objects));
	rb_hash_aset(prof, ID2SYM(rb_intern("REMEMBED_SHADY_OBJECTS")), SIZET2NUM(record->remembered_shady_objects));
#endif
	rb_ary_push(gc_profile, prof);
    }

    return gc_profile;
}

static void
gc_profile_dump_on(VALUE out, VALUE (*append)(VALUE, VALUE))
{
    rb_objspace_t *objspace = &rb_objspace;
    size_t count = objspace->profile.next_index;

    if (objspace->profile.run && count /* > 1 */) {
	size_t i;
	const gc_profile_record *record;

	append(out, rb_sprintf("GC %"PRIuSIZE" invokes.\n", objspace->count));
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
				    "Index Flags       Allocate Inc.  Allocate Limit"
#if CALC_EXACT_MALLOC_SIZE
				    "  Allocated Size"
#endif
				    "  Use Slot     Mark Time(ms)    Sweep Time(ms)  Prepare Time(ms)  LivingObj    FreeObj RemovedObj   EmptyObj"
#if RGENGC_PROFILE
				    " OldgenObj RemNormObj RemShadObj"
#endif
				    "\n"));

	for (i = 0; i < count; i++) {
	    record = &objspace->profile.records[i];
	    append(out, rb_sprintf("%5"PRIdSIZE" %c/%c/%6s%c %13"PRIuSIZE" %15"PRIuSIZE
#if CALC_EXACT_MALLOC_SIZE
				   " %15"PRIuSIZE
#endif
				   " %9"PRIuSIZE" %17.12f %17.12f %17.12f %10"PRIuSIZE" %10"PRIuSIZE" %10"PRIuSIZE" %10"PRIuSIZE
#if RGENGC_PROFILE
				   "%10"PRIuSIZE" %10"PRIuSIZE" %10"PRIuSIZE
#endif
				   "\n",
				   i+1,
				   "-+O3S567R9abcdef!"[record->flags & GPR_FLAG_MAJOR_MASK], /* Stress,Rescan,Shady,Oldgen,NoFree */
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
				   record->heap_use_slots,
				   record->gc_mark_time*1000,
				   record->gc_sweep_time*1000,
				   record->prepare_time*1000,

				   record->heap_live_objects,
				   record->heap_free_objects,
				   record->removing_objects,
				   record->empty_objects
#if RGENGC_PROFILE
				   ,
				   record->oldgen_objects,
				   record->remembered_normal_objects,
				   record->remembered_shady_objects
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
	size_t count = objspace->profile.next_index - 1;

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
    gc_rest_sweep(objspace);
    objspace->profile.run = TRUE;
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

#ifdef GC_DEBUG

void
rb_gcdebug_print_obj_condition(VALUE obj)
{
    rb_objspace_t *objspace = &rb_objspace;

    if (is_pointer_to_heap(objspace, (void *)obj)) {
        fprintf(stderr, "pointer to heap?: true\n");
    }
    else {
        fprintf(stderr, "pointer to heap?: false\n");
        return;
    }
    fprintf(stderr, "marked?: %s\n",
            MARKED_IN_BITMAP(GET_HEAP_MARK_BITS(obj), obj) ? "true" : "false");
    if (is_lazy_sweeping(objspace)) {
        fprintf(stderr, "lazy sweeping?: true\n");
        fprintf(stderr, "swept?: %s\n",
                is_swept_object(objspace, obj) ? "done" : "not yet");
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
    rb_define_final(obj, rb_proc_new(gcdebug_sential, (VALUE)name));
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

    rb_mGC = rb_define_module("GC");
    rb_define_singleton_method(rb_mGC, "start", rb_gc_start, 0);
    rb_define_singleton_method(rb_mGC, "enable", rb_gc_enable, 0);
    rb_define_singleton_method(rb_mGC, "disable", rb_gc_disable, 0);
    rb_define_singleton_method(rb_mGC, "stress", gc_stress_get, 0);
    rb_define_singleton_method(rb_mGC, "stress=", gc_stress_set, 1);
    rb_define_singleton_method(rb_mGC, "count", gc_count, 0);
    rb_define_singleton_method(rb_mGC, "stat", gc_stat, -1);
    rb_define_method(rb_mGC, "garbage_collect", rb_gc_start, 0);

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
    rb_define_module_function(rb_mObjSpace, "garbage_collect", rb_gc_start, 0);

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
	rb_define_private_method(rb_cWeakMap, "finalize", wmap_finalize, 1);
    }

#if CALC_EXACT_MALLOC_SIZE
    rb_define_singleton_method(rb_mGC, "malloc_allocated_size", gc_malloc_allocated_size, 0);
    rb_define_singleton_method(rb_mGC, "malloc_allocations", gc_malloc_allocations, 0);
#endif
}
