#include <sys/mman.h>
#include <unistd.h>

#include "ruby/atomic.h"
#include "ruby/debug.h"
#include "ccan/list/list.h"
#include "darray.h"
#include "internal/sanitizers.h"

/*===== FORWARD DECLARATIONS FROM gc.c */

unsigned int rb_gc_vm_lock(void);
void         rb_gc_vm_unlock(unsigned int lev);
unsigned int rb_gc_cr_lock(void);
void         rb_gc_cr_unlock(unsigned int lev);
size_t       rb_size_mul_or_raise(size_t x, size_t y, VALUE exc);
void         rb_gc_run_obj_finalizer(VALUE objid, long count, VALUE (*callback)(long i, void *data), void *data);
void         rb_gc_set_pending_interrupt(void);
void         rb_gc_unset_pending_interrupt(void);
bool         rb_gc_obj_free(void *objspace, VALUE obj);
const char * rb_obj_info(VALUE obj);
bool         rb_gc_shutdown_call_finalizer_p(VALUE obj);

VALUE        rb_gc_impl_object_id(void *objspace_ptr, VALUE obj);

#ifdef HAVE_MALLOC_USABLE_SIZE
# include <malloc.h>
# define malloc_size(ptr) malloc_usable_size(ptr)
#else
# include <malloc/malloc.h>
#endif

#ifndef RUBY_DEBUG_LOG
# define RUBY_DEBUG_LOG(...)
#endif

#define GC_ASSERT RUBY_ASSERT

#ifndef HEAP_PAGE_ALIGN_LOG
/* default tiny heap size: 64KiB */
#define HEAP_PAGE_ALIGN_LOG 16
#endif

#ifndef MAX
# define MAX(a, b) (((a) > (b)) ? (a) : (b))
#endif
#ifndef MIN
# define MIN(a, b) (((a) < (b)) ? (a) : (b))
#endif
#define roomof(x, y) (((x) + (y) - 1) / (y))
#define CEILDIV(i, mod) roomof(i, mod)

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

/* ===== HEAP & ALLOCATION STRUCTURES */

#ifndef OBJ_SIZE_MULTIPLES
# define OBJ_SIZE_MULTIPLES 5
#endif

#define BASE_SLOT_SIZE (sizeof(struct RBasic) + sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX]))

struct heap_page_header {
    struct heap_page *page;
};

struct heap_page_body {
    struct heap_page_header header;
};

typedef struct rb_objspace {
    struct {
        size_t limit;
        size_t increase;
    } malloc_params;

    struct {
        unsigned int has_newobj_hook: 1;
    } flags;

    rb_event_flag_t hook_events;
    unsigned long long next_object_id;

    struct heap_page *free_page_cache[OBJ_SIZE_MULTIPLES];

    struct {
        size_t allocatable_pages;
        size_t total_allocated_pages;
        size_t total_allocated_objects;
        size_t empty_slots;

        struct heap_page *free_pages;
        struct ccan_list_head pages;
        size_t total_pages;
        size_t total_slots;
    } heap;

    struct {
        rb_atomic_t finalizing;
    } atomic_flags;

    struct {
        struct heap_page **sorted;
        size_t allocated_pages;
        size_t allocatable_pages;
        size_t sorted_length;
        uintptr_t range[2];
        size_t freeable_pages;

        /* final */
        size_t final_slots;
        VALUE deferred_final;
    } heap_pages;

    st_table *finalizer_table;
    st_table *id_to_obj_tbl;
    st_table *obj_to_id_tbl;

    rb_postponed_job_handle_t finalize_deferred_pjob;
    unsigned long live_ractor_cache_count;
} rb_objspace_t;

struct free_slot {
    VALUE flags;		/* always 0 for freed obj */
    struct free_slot *next;
};

typedef struct heap_page {
    short slot_size;
    short total_slots;
    short free_slots;
    short final_slots;

    struct heap_page *free_next;
    uintptr_t start;
    struct free_slot *freelist;
    struct ccan_list_node page_node;
} rb_heap_page_t;

struct RZombie {
    struct RBasic basic;
    VALUE next;
    void (*dfree)(void *);
    void *data;
};

#define RZOMBIE(o) ((struct RZombie *)(o))
enum {
    HEAP_PAGE_ALIGN = (1UL << HEAP_PAGE_ALIGN_LOG),
    HEAP_PAGE_ALIGN_MASK = (~(~0UL << HEAP_PAGE_ALIGN_LOG)),
    HEAP_PAGE_SIZE = HEAP_PAGE_ALIGN,
    HEAP_PAGE_OBJ_LIMIT = (unsigned int)((HEAP_PAGE_SIZE - sizeof(struct heap_page_header)) / BASE_SLOT_SIZE),
};
#define HEAP_PAGE_ALIGN (1 << HEAP_PAGE_ALIGN_LOG)
#define HEAP_PAGE_SIZE HEAP_PAGE_ALIGN
#define GET_PAGE_BODY(x)   ((struct heap_page_body *)((uintptr_t)(x) & ~(HEAP_PAGE_ALIGN_MASK)))
#define GET_PAGE_HEADER(x) (&GET_PAGE_BODY(x)->header)
#define GET_HEAP_PAGE(x)   (GET_PAGE_HEADER(x)->page)
#define NUM_IN_PAGE(p)   (((uintptr_t)(p) & HEAP_PAGE_ALIGN_MASK) / BASE_SLOT_SIZE)

#define malloc_increase 	  objspace->malloc_params.increase
#define heap_pages_sorted         objspace->heap_pages.sorted
#define heap_allocated_pages      objspace->heap_pages.allocated_pages
#define heap_pages_sorted_length  objspace->heap_pages.sorted_length
#define heap_pages_lomem	  objspace->heap_pages.range[0]
#define heap_pages_himem	  objspace->heap_pages.range[1]
#define heap_pages_final_slots    objspace->heap_pages.final_slots
#define heap_pages_deferred_final objspace->heap_pages.deferred_final
#define finalizing		  objspace->atomic_flags.finalizing
#define finalizer_table 	  objspace->finalizer_table

#if SIZEOF_LONG == SIZEOF_VOIDP
# define obj_id_to_ref(objid) ((objid) ^ FIXNUM_FLAG) /* unset FIXNUM_FLAG */
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
# define obj_id_to_ref(objid) (FIXNUM_P(objid) ? \
   ((objid) ^ FIXNUM_FLAG) : (NUM2PTR(objid) << 1))
#else
# error not supported
#endif

#ifdef RUBY_DEBUG
# ifndef RNOGC_DEBUG
#  define RNOGC_DEBUG 0
# endif
#endif

# define gc_report(objspace, ...) \
    if (!(RUBY_DEBUG && RNOGC_DEBUG)) {} else gc_report_body(objspace, __VA_ARGS__)

PRINTF_ARGS(static void gc_report_body(rb_objspace_t *objspace, const char *fmt, ...), 2, 3);

static void gc_finalize_deferred(void *dmy);

static void
asan_lock_freelist(struct heap_page *page)
{
    asan_poison_memory_region(&page->freelist, sizeof(struct free_list *));
}

static void
asan_unlock_freelist(struct heap_page *page)
{
    asan_unpoison_memory_region(&page->freelist, sizeof(struct free_list *), false);
}

#define asan_unpoisoning_object(obj) \
    for (void *poisoned = asan_unpoison_object_temporary(obj), \
              *unpoisoning = &poisoned; /* flag to loop just once */ \
         unpoisoning; \
         unpoisoning = asan_poison_object_restore(obj, poisoned))

static inline void *
calloc1(size_t n)
{
    return calloc(1, n);
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

#define OBJ_ID_INCREMENT (BASE_SLOT_SIZE)

static const struct st_hash_type object_id_hash_type = {
    object_id_cmp,
    object_id_hash,
};

/* garbage objects will be collected soon. */
static void
heap_pages_expand_sorted_to(rb_objspace_t *objspace, size_t next_length)
{
    struct heap_page **sorted;
    size_t size = rb_size_mul_or_raise(next_length, sizeof(struct heap_page *), rb_eRuntimeError);

    gc_report(objspace, "heap_pages_expand_sorted: next_length: %"PRIdSIZE", size: %"PRIdSIZE"\n",
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
    size_t next_length = objspace->heap.allocatable_pages +
        objspace->heap.total_pages;

    if (next_length > heap_pages_sorted_length) {
        heap_pages_expand_sorted_to(objspace, next_length);
    }

    GC_ASSERT(objspace->heap.allocatable_pages + objspace->heap.total_pages <= heap_pages_sorted_length);
    GC_ASSERT(objspace->heap_pages.allocated_pages <= heap_pages_sorted_length);
}

static inline void
heap_page_add_freeobj(rb_objspace_t *objspace, struct heap_page *page, VALUE obj)
{
    asan_unpoison_object(obj, false);
    asan_unlock_freelist(page);

    struct free_slot *slot = (struct free_slot *)obj;
    slot->flags = 0;
    slot->next = page->freelist;
    page->freelist = slot;

    asan_lock_freelist(page);
    asan_poison_object(obj);
    gc_report(objspace, "heap_page_add_freeobj: add %p to freelist\n", (void *)obj);
}

static inline void
heap_add_freepage(rb_objspace_t *objspace, struct heap_page *page)
{
    asan_unlock_freelist(page);
    GC_ASSERT(page->free_slots != 0);
    GC_ASSERT(page->freelist != NULL);

    page->free_next = objspace->heap.free_pages;
    objspace->heap.free_pages = page;

    RUBY_DEBUG_LOG("page:%p freelist:%p", (void *)page, (void *)page->freelist);

    asan_lock_freelist(page);
}

static void
gc_aligned_free(void *ptr, size_t size)
{
#if defined(HAVE_POSIX_MEMALIGN) || defined(HAVE_MEMALIGN)
    free(ptr);
#else
    free(((void**)ptr)[-1]);
#endif
}

static void
heap_page_body_free(struct heap_page_body *page_body)
{
    GC_ASSERT((uintptr_t)page_body % HEAP_PAGE_ALIGN == 0);

    if (HEAP_PAGE_ALLOC_USE_MMAP) {
#ifdef HAVE_MMAP
        GC_ASSERT(HEAP_PAGE_SIZE % sysconf(_SC_PAGE_SIZE) == 0);
        if (munmap(page_body, HEAP_PAGE_SIZE)) {
            rb_bug("heap_page_body_free: munmap failed");
        }
#endif
    }
    else {
        gc_aligned_free(page_body, HEAP_PAGE_SIZE);
    }
}

static void *
gc_aligned_malloc(size_t alignment, size_t size)
{
    /* alignment must be a power of 2 */
    GC_ASSERT(((alignment - 1) & alignment) == 0);
    GC_ASSERT(alignment % sizeof(void*) == 0);

    void *res;

#if defined(HAVE_POSIX_MEMALIGN)
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

static struct heap_page_body *
heap_page_body_allocate(void)
{
    struct heap_page_body *page_body;

    if (HEAP_PAGE_ALLOC_USE_MMAP) {
#ifdef HAVE_MMAP
        GC_ASSERT(HEAP_PAGE_ALIGN % sysconf(_SC_PAGE_SIZE) == 0);

        char *ptr = mmap(NULL, HEAP_PAGE_ALIGN + HEAP_PAGE_SIZE,
                         PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (ptr == MAP_FAILED) {
            return NULL;
        }

        char *aligned = ptr + HEAP_PAGE_ALIGN;
        aligned -= ((VALUE)aligned & (HEAP_PAGE_ALIGN - 1));
        GC_ASSERT(aligned > ptr);
        GC_ASSERT(aligned <= ptr + HEAP_PAGE_ALIGN);

        size_t start_out_of_range_size = aligned - ptr;
        GC_ASSERT(start_out_of_range_size % sysconf(_SC_PAGE_SIZE) == 0);
        if (start_out_of_range_size > 0) {
            if (munmap(ptr, start_out_of_range_size)) {
                rb_bug("heap_page_body_allocate: munmap failed for start");
            }
        }

        size_t end_out_of_range_size = HEAP_PAGE_ALIGN - start_out_of_range_size;
        GC_ASSERT(end_out_of_range_size % sysconf(_SC_PAGE_SIZE) == 0);
        if (end_out_of_range_size > 0) {
            if (munmap(aligned + HEAP_PAGE_SIZE, end_out_of_range_size)) {
                rb_bug("heap_page_body_allocate: munmap failed for end");
            }
        }

        page_body = (struct heap_page_body *)aligned;
#endif
    }
    else {
        page_body = gc_aligned_malloc(HEAP_PAGE_ALIGN, HEAP_PAGE_SIZE);
    }

    GC_ASSERT((uintptr_t)page_body % HEAP_PAGE_ALIGN == 0);

    return page_body;
}

static struct heap_page *
heap_page_allocate(rb_objspace_t *objspace, size_t slot_size)
{
    uintptr_t start, end, p;
    struct heap_page *page;
    uintptr_t hi, lo, mid;
    size_t stride = slot_size;
    unsigned int limit = (unsigned int)((HEAP_PAGE_SIZE - sizeof(struct heap_page_header)))/(int)stride;

    /* assign heap_page body (contains heap_page_header and RVALUEs) */
    struct heap_page_body *page_body = heap_page_body_allocate();
    if (page_body == 0) {
        rb_memerror();
    }

    /* assign heap_page entry */
    page = calloc1(sizeof(struct heap_page));
    if (page == 0) {
        heap_page_body_free(page_body);
        rb_memerror();
    }

    /* adjust obj_limit (object number available in this page) */
    start = (uintptr_t)((VALUE)page_body + sizeof(struct heap_page_header));

    if (start % BASE_SLOT_SIZE != 0) {
        int delta = BASE_SLOT_SIZE - (start % BASE_SLOT_SIZE);
        start = start + delta;
        GC_ASSERT(NUM_IN_PAGE(start) == 0 || NUM_IN_PAGE(start) == 1);

        /* Find a num in page that is evenly divisible by `stride`.
         * This is to ensure that objects are aligned with bit planes.
         * In other words, ensure there are an even number of objects
         * per bit plane. */
        if (NUM_IN_PAGE(start) == 1) {
            start += stride - BASE_SLOT_SIZE;
        }

        GC_ASSERT(NUM_IN_PAGE(start) * BASE_SLOT_SIZE % stride == 0);

        limit = (HEAP_PAGE_SIZE - (int)(start - (uintptr_t)page_body))/(int)stride;
    }
    end = start + (limit * (int)stride);

    /* setup heap_pages_sorted */
    lo = 0;
    hi = (uintptr_t)heap_allocated_pages;
    while (lo < hi) {
        struct heap_page *mid_page;

        mid = (lo + hi) / 2;
        mid_page = heap_pages_sorted[mid];
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

    if (hi < (uintptr_t)heap_allocated_pages) {
        MEMMOVE(&heap_pages_sorted[hi+1], &heap_pages_sorted[hi], struct heap_page_header*, heap_allocated_pages - hi);
    }

    heap_pages_sorted[hi] = page;
    heap_allocated_pages++;

    GC_ASSERT(objspace->heap.total_pages + objspace->heap.allocatable_pages <= heap_pages_sorted_length);
    GC_ASSERT(heap_allocated_pages <= heap_pages_sorted_length);

    objspace->heap.total_allocated_pages++;

    if (heap_allocated_pages > heap_pages_sorted_length) {
        rb_bug("heap_page_allocate: allocated(%"PRIdSIZE") > sorted(%"PRIdSIZE")",
               heap_allocated_pages, heap_pages_sorted_length);
    }

    if (heap_pages_lomem == 0 || heap_pages_lomem > start) heap_pages_lomem = start;
    if (heap_pages_himem < end) heap_pages_himem = end;

    page->start = start;
    page->total_slots = limit;
    page->slot_size = slot_size;
    page_body->header.page = page;

    for (p = start; p != end; p += stride) {
        gc_report(objspace, "assign_heap_page: %p is added to freelist\n", (void *)p);
        heap_page_add_freeobj(objspace, page, (VALUE)p);
    }
    page->free_slots = limit;

    asan_lock_freelist(page);
    return page;
}

static struct heap_page *
heap_page_create(rb_objspace_t *objspace, size_t slot_size)
{
    objspace->heap.allocatable_pages--;
    return heap_page_allocate(objspace, slot_size);
}

static void
heap_add_page(rb_objspace_t *objspace, struct heap_page *page)
{
    ccan_list_add_tail(&objspace->heap.pages, &page->page_node);
    objspace->heap.total_pages++;
    objspace->heap.total_slots += page->total_slots;
}

static rb_heap_page_t *
heap_assign_page(rb_objspace_t *objspace, size_t slot_size)
{
    struct heap_page *page = heap_page_create(objspace, slot_size);
    heap_add_page(objspace, page);
    heap_add_freepage(objspace, page);

    return page;
}

static rb_heap_page_t *
heap_increment(rb_objspace_t *objspace, size_t slot_size)
{
    rb_heap_page_t *page = NULL;
    if (objspace->heap.allocatable_pages > 0) {
        gc_report(objspace, "heap_increment: heap_pages_sorted_length: %"PRIdSIZE", "
                  "heap_pages_inc: %"PRIdSIZE", heap->total_pages: %"PRIdSIZE"\n",
                  heap_pages_sorted_length, objspace->heap.allocatable_pages, objspace->heap.total_pages);

        GC_ASSERT(objspace->heap.allocatable_pages + objspace->heap.total_pages <= heap_pages_sorted_length);
        GC_ASSERT(heap_allocated_pages <= heap_pages_sorted_length);

        page = heap_assign_page(objspace, slot_size);
    }
    return page;
}

static inline size_t
goal_allocatable_pages_count(rb_objspace_t *objspace)
{
    size_t allocated_pages = objspace->heap.total_allocated_pages;
    size_t allocatable_pages = objspace->heap.allocatable_pages;

    if (allocated_pages / allocatable_pages >= 0.75) {
        allocatable_pages = allocatable_pages * 2;
    }
    return allocatable_pages;
}

static rb_heap_page_t *
heap_prepare(rb_objspace_t *objspace, size_t slot_size)
{
    rb_heap_page_t *page = NULL;
    size_t extend_page_count = goal_allocatable_pages_count(objspace);
    if (extend_page_count > objspace->heap.allocatable_pages) {
        objspace->heap.allocatable_pages = extend_page_count;
        heap_pages_expand_sorted(objspace);
    }
    GC_ASSERT(objspace->heap.allocatable_pages > 0);
    page = heap_increment(objspace, slot_size);
    GC_ASSERT(objspace->heap.free_pages != NULL);

    return page;
}

static inline size_t
valid_object_sizes_ordered_idx(unsigned char pool_id)
{
    GC_ASSERT(pool_id < OBJ_SIZE_MULTIPLES);
    return (1 << pool_id) * BASE_SLOT_SIZE;
}

bool
rb_gc_impl_size_allocatable_p(size_t size)
{
    return size <= valid_object_sizes_ordered_idx(OBJ_SIZE_MULTIPLES - 1);
}

static inline VALUE
newobj_fill(VALUE obj, VALUE v1, VALUE v2, VALUE v3)
{
    VALUE *p = (VALUE *)obj;
    p[2] = v1;
    p[3] = v2;
    p[4] = v3;
    return obj;
}

static inline size_t
page_slot_size_idx_for_size(size_t size)
{
    size_t slot_count = CEILDIV(size, BASE_SLOT_SIZE);
    size_t ordered_object_size_idx = 64 - nlz_int64(slot_count - 1);

    if (ordered_object_size_idx >= OBJ_SIZE_MULTIPLES) {
        rb_bug("page_slot_size_idx_for_size: allocation size too large "
               "(size=%"PRIuSIZE"u, ordered_object_size_idx=%"PRIuSIZE"u)",
               size, ordered_object_size_idx);
    }

    return ordered_object_size_idx;
}


static size_t valid_object_sizes[OBJ_SIZE_MULTIPLES + 1] = { 0 };

size_t *
rb_gc_impl_size_pool_sizes(void)
{
    if (valid_object_sizes[0] == 0) {
        for (unsigned char i = 0; i < OBJ_SIZE_MULTIPLES; i++) {
            valid_object_sizes[i] = valid_object_sizes_ordered_idx(i);
        }
    }

    return valid_object_sizes;
}

static VALUE
newobj_alloc(rb_objspace_t *objspace, size_t cache_idx, size_t slot_size)
{
    unsigned int lev = rb_gc_cr_lock();

    GC_ASSERT(objspace->free_page_cache[cache_idx]);
    struct heap_page *page = objspace->free_page_cache[cache_idx];

    if (page->free_slots == 0) {
        page = heap_prepare(objspace, slot_size);
        objspace->free_page_cache[cache_idx] = page;
    }

    struct free_slot *obj = page->freelist;
    GC_ASSERT(RB_TYPE_P((VALUE)obj, T_NONE));

    page->freelist = obj->next;
    page->free_slots--;
    rb_gc_cr_unlock(lev);

    objspace->heap.total_allocated_objects++;
    return (VALUE)obj;
}

static int
ptr_in_page_body_p(const void *ptr, const void *memb)
{
    struct heap_page *page = *(struct heap_page **)memb;
    uintptr_t p_body = (uintptr_t)GET_PAGE_BODY(page->start);

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

    res = bsearch((void *)ptr, heap_pages_sorted,
                  (size_t)heap_allocated_pages, sizeof(struct heap_page *),
                  ptr_in_page_body_p);

    if (res) {
        return *res;
    }
    else {
        return NULL;
    }
}

#define ZOMBIE_OBJ_KEPT_FLAGS (FL_SEEN_OBJ_ID | FL_FINALIZE)

typedef int each_obj_callback(void *, void *, size_t, void *);
typedef int each_page_callback(struct heap_page *, void *);

struct each_obj_data {
    rb_objspace_t *objspace;
    bool reenable_incremental;

    each_obj_callback *each_obj_callback;
    each_page_callback *each_page_callback;
    void *data;

    struct heap_page **pages;
    size_t pages_count;
};

static VALUE
objspace_each_objects_ensure(VALUE arg)
{
    struct each_obj_data *data = (struct each_obj_data *)arg;
    free(data->pages);
    return Qnil;
}

static VALUE
objspace_each_objects_try(VALUE arg)
{
    struct each_obj_data *data = (struct each_obj_data *)arg;
    rb_objspace_t *objspace = data->objspace;

    size_t size = objspace->heap.total_pages * sizeof(rb_heap_page_t *);
    rb_heap_page_t **pages = malloc(size);
    if (!pages) rb_memerror();

    rb_heap_page_t *page = NULL;
    size_t pages_count = 0;
    ccan_list_for_each(&objspace->heap.pages, page, page_node) {
        pages[pages_count] = page;
        pages_count++;
    }

    data->pages = pages;
    data->pages_count = pages_count;

    GC_ASSERT(pages_count == data->pages_count &&
              pages_count == objspace->heap.total_pages);

    page = ccan_list_top(&objspace->heap.pages, struct heap_page, page_node);

    for (size_t i = 0; i < pages_count; i++) {
        /* If we have reached the end of the linked list then there are no
         * more pages, so break. */
        if (page == NULL) break;

        /* If this page does not match the one in the buffer, then move to
         * the next page in the buffer. */
        if (data->pages[i] != page) continue;

        uintptr_t pstart = (uintptr_t)page->start;
        uintptr_t pend = pstart + (page->total_slots * page->slot_size);

        if (data->each_obj_callback &&
                (*data->each_obj_callback)((void *)pstart, (void *)pend, page->slot_size, data->data)) {
            break;
        }
        if (data->each_page_callback &&
                (*data->each_page_callback)(page, data->data)) {
            break;
        }

        page = ccan_list_next(&objspace->heap.pages, page, page_node);
    }

    return Qnil;
}

static void
objspace_each_exec(bool protected, struct each_obj_data *each_obj_data)
{
    each_obj_data->reenable_incremental = FALSE;
    memset(&each_obj_data->pages, 0, sizeof(each_obj_data->pages));
    memset(&each_obj_data->pages_count, 0, sizeof(each_obj_data->pages_count));
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

static VALUE
get_final(long i, void *data)
{
    VALUE table = (VALUE)data;

    return RARRAY_AREF(table, i);
}

static void
run_final(rb_objspace_t *objspace, VALUE zombie)
{
    if (RZOMBIE(zombie)->dfree) {
        RZOMBIE(zombie)->dfree(RZOMBIE(zombie)->data);
    }

    st_data_t key = (st_data_t)zombie;
    if (FL_TEST_RAW(zombie, FL_FINALIZE)) {
        FL_UNSET(zombie, FL_FINALIZE);
        st_data_t table;
        if (st_delete(finalizer_table, &key, &table)) {
            rb_gc_run_obj_finalizer(rb_gc_impl_object_id(objspace, zombie), RARRAY_LEN(table), get_final, (void *)table);
        }
        else {
            rb_bug("FL_FINALIZE flag is set, but finalizers are not found");
        }
    }
    else {
        GC_ASSERT(!st_lookup(finalizer_table, key, NULL));
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

        int lev = rb_gc_vm_lock();
        {
            GC_ASSERT(BUILTIN_TYPE(zombie) == T_ZOMBIE);
            GC_ASSERT(heap_pages_final_slots > 0);
            GC_ASSERT(page->final_slots > 0);

            heap_pages_final_slots--;
            page->final_slots--;
            page->free_slots++;
            heap_page_add_freeobj(objspace, page, zombie);
        }
        rb_gc_vm_unlock(lev);

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
    rb_objspace_t *objspace = dmy;
    if (RUBY_ATOMIC_EXCHANGE(finalizing, 1)) return;

    finalize_deferred(objspace);
    RUBY_ATOMIC_SET(finalizing, 0);
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

static void
gc_report_body(rb_objspace_t *objspace, const char *fmt, ...)
{
    char buf[1024];
    FILE *out = stderr;
    va_list args;
    const char *status = " ";

    va_start(args, fmt);
    vsnprintf(buf, 1024, fmt, args);
    va_end(args);

    fprintf(out, "%s|", status);
    fputs(buf, out);
}

enum gc_stat_sym {
    gc_stat_sym_heap_allocated_pages,
    gc_stat_sym_heap_sorted_length,
    gc_stat_sym_heap_allocatable_pages,
    gc_stat_sym_heap_available_slots,
    gc_stat_sym_heap_live_slots,
    gc_stat_sym_heap_free_slots,
    gc_stat_sym_heap_final_slots,
    gc_stat_sym_heap_eden_pages,
    gc_stat_sym_total_allocated_pages,
    gc_stat_sym_total_allocated_objects,
    gc_stat_sym_malloc_increase_bytes,
    gc_stat_sym_last
};

static VALUE gc_stat_symbols[gc_stat_sym_last];

static void
setup_gc_stat_symbols(void)
{
    if (gc_stat_symbols[0] == 0) {
#define S(s) gc_stat_symbols[gc_stat_sym_##s] = ID2SYM(rb_intern_const(#s))
        S(heap_allocated_pages);
        S(heap_sorted_length);
        S(heap_allocatable_pages);
        S(heap_available_slots);
        S(heap_live_slots);
        S(heap_free_slots);
        S(heap_final_slots);
        S(heap_eden_pages);
        S(total_allocated_pages);
        S(total_allocated_objects);
        S(malloc_increase_bytes);
#undef S
    }
}

static size_t
objspace_live_slots(rb_objspace_t *objspace)
{
    return objspace->heap.total_allocated_objects - heap_pages_final_slots;
}

static size_t
objspace_free_slots(rb_objspace_t *objspace)
{
    return objspace->heap.total_slots - objspace_live_slots(objspace) - heap_pages_final_slots;
}

enum gc_stat_heap_sym {
    gc_stat_heap_sym_heap_allocatable_pages,
    gc_stat_heap_sym_heap_eden_pages,
    gc_stat_heap_sym_heap_eden_slots,
    gc_stat_heap_sym_total_allocated_pages,
    gc_stat_heap_sym_force_incremental_marking_finish_count,
    gc_stat_heap_sym_total_allocated_objects,
    gc_stat_heap_sym_last
};

static VALUE gc_stat_heap_symbols[gc_stat_heap_sym_last];

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

static bool
objspace_malloc_increase_body(rb_objspace_t *objspace, void *mem, size_t new_size, size_t old_size, enum memop_type type)
{
    if (new_size > old_size) {
        RUBY_ATOMIC_SIZE_ADD(malloc_increase, new_size - old_size);
    }
    else {
        atomic_sub_nounderflow(&malloc_increase, old_size - new_size);
    }

    return true;
}

#define objspace_malloc_increase(...) \
    for (bool malloc_increase_done = false; \
         !malloc_increase_done; \
         malloc_increase_done = objspace_malloc_increase_body(__VA_ARGS__))

static inline void *
objspace_malloc_fixup(rb_objspace_t *objspace, void *mem, size_t size)
{
    size = malloc_size(mem);
    objspace_malloc_increase(objspace, mem, size, 0, MEMOP_TYPE_MALLOC) {}
    return mem;
}

#if defined(__GNUC__) && RUBY_DEBUG
#define RB_BUG_INSTEAD_OF_RB_MEMERROR 1
#endif

#ifndef RB_BUG_INSTEAD_OF_RB_MEMERROR
# define RB_BUG_INSTEAD_OF_RB_MEMERROR 0
#endif

#define GC_MEMERROR(...) \
    ((RB_BUG_INSTEAD_OF_RB_MEMERROR+0) ? rb_bug("" __VA_ARGS__) : rb_memerror())

/* ===== PUBLIC API FUNCTIONS */

void rb_gc_impl_set_event_hook(void *objspace_ptr, const rb_event_flag_t event)
{
    rb_objspace_t *objspace = objspace_ptr;
    objspace->hook_events = event & RUBY_INTERNAL_EVENT_OBJSPACE_MASK;
    objspace->flags.has_newobj_hook = !!(objspace->hook_events & RUBY_INTERNAL_EVENT_NEWOBJ);
}

VALUE
rb_gc_impl_object_id_to_ref(void *objspace_ptr, VALUE object_id)
{
    rb_objspace_t *objspace = objspace_ptr;

    VALUE obj;
    if (st_lookup(objspace->id_to_obj_tbl, object_id, &obj)) {
        return obj;
    }

    if (rb_funcall(object_id, rb_intern(">="), 1, ULL2NUM(objspace->next_object_id))) {
        rb_raise(rb_eRangeError, "%+"PRIsVALUE" is not id value", rb_funcall(object_id, rb_intern("to_s"), 1, INT2FIX(10)));
    }
    else {
        rb_raise(rb_eRangeError, "%+"PRIsVALUE" is recycled object", rb_funcall(object_id, rb_intern("to_s"), 1, INT2FIX(10)));
    }
}

VALUE
rb_gc_impl_object_id(void *objspace_ptr, VALUE obj)
{
    VALUE id;
    rb_objspace_t *objspace = objspace_ptr;

    unsigned int lev = rb_gc_vm_lock();
    if (st_lookup(objspace->obj_to_id_tbl, (st_data_t)obj, &id)) {
        GC_ASSERT(FL_TEST(obj, FL_SEEN_OBJ_ID));
    }
    else {
        GC_ASSERT(!FL_TEST(obj, FL_SEEN_OBJ_ID));

        id = ULL2NUM(objspace->next_object_id);
        objspace->next_object_id += OBJ_ID_INCREMENT;

        st_insert(objspace->obj_to_id_tbl, (st_data_t)obj, (st_data_t)id);
        st_insert(objspace->id_to_obj_tbl, (st_data_t)id, (st_data_t)obj);
        FL_SET(obj, FL_SEEN_OBJ_ID);
    }
    rb_gc_vm_unlock(lev);

    return id;
}

/* TODO: This function bakes internal implementation detail into the Interface.
 * This needs to be removed.
 */
size_t
rb_gc_impl_size_pool_id_for_size(void *objspace_ptr, size_t size)
{
    return page_slot_size_idx_for_size(size);
}

VALUE
rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, VALUE klass, VALUE flags, VALUE v1, VALUE v2, VALUE v3, bool wb_protected, size_t alloc_size)
{
    rb_objspace_t *objspace = objspace_ptr;

    size_t *public_slot_sizes = rb_gc_impl_size_pool_sizes();

    size_t cache_slot_idx = page_slot_size_idx_for_size(alloc_size);
    VALUE obj = newobj_alloc(objspace, cache_slot_idx, public_slot_sizes[cache_slot_idx]);

    RBASIC(obj)->flags = flags;
    *((VALUE *)&RBASIC(obj)->klass) = klass;

    gc_report(objspace, "newobj: %s\n", rb_obj_info(obj));

    RUBY_DEBUG_LOG("obj:%p (%s)", (void *)obj, rb_obj_info(obj));

    return newobj_fill(obj, v1, v2, v3);
}

bool
rb_gc_impl_pointer_to_heap_p(void *objspace_ptr, const void *ptr)
{
    rb_objspace_t *objspace = objspace_ptr;
    register uintptr_t p = (uintptr_t)ptr;
    register struct heap_page *page;

    if (p < heap_pages_lomem || p > heap_pages_himem) return FALSE;
    if (p % BASE_SLOT_SIZE != 0) return FALSE;
    page = heap_page_for_ptr(objspace, (uintptr_t)ptr);
    if (page) {
        if (p < page->start) return FALSE;
        if (p >= page->start + (page->total_slots * page->slot_size)) return FALSE;
        if ((NUM_IN_PAGE(p) * BASE_SLOT_SIZE) % page->slot_size != 0) return FALSE;

        return TRUE;
    }
    return FALSE;
}

void
rb_gc_impl_make_zombie(void *objspace_ptr, VALUE obj, void (*dfree)(void *), void *data)
{
    rb_objspace_t *objspace = objspace_ptr;

    struct RZombie *zombie = RZOMBIE(obj);
    zombie->basic.flags = T_ZOMBIE | (zombie->basic.flags & ZOMBIE_OBJ_KEPT_FLAGS);
    zombie->dfree = dfree;
    zombie->data = data;
    VALUE prev, next = heap_pages_deferred_final;
    do {
        zombie->next = prev = next;
        next = RUBY_ATOMIC_VALUE_CAS(heap_pages_deferred_final, prev, obj);
    } while (next != prev);

    struct heap_page *page = GET_HEAP_PAGE(obj);
    page->final_slots++;
    heap_pages_final_slots++;
}

void
rb_gc_impl_each_objects(void *objspace_ptr, each_obj_callback *callback, void *data)
{
    objspace_each_objects(objspace_ptr, callback, data, TRUE);
}

VALUE
rb_gc_impl_define_finalizer(void *objspace_ptr, VALUE obj, VALUE block)
{
    rb_objspace_t *objspace = objspace_ptr;
    VALUE table;
    st_data_t data;

    RBASIC(obj)->flags |= FL_FINALIZE;

    if (st_lookup(finalizer_table, obj, &data)) {
        table = (VALUE)data;

        /* avoid duplicate block, table is usually small */
        {
            long len = RARRAY_LEN(table);
            long i;

            for (i = 0; i < len; i++) {
                VALUE recv = RARRAY_AREF(table, i);
                if (rb_equal(recv, block)) {
                    block = recv;
                    goto end;
                }
            }
        }

        rb_ary_push(table, block);
    }
    else {
        table = rb_ary_new3(1, block);
        *(VALUE *)&RBASIC(table)->klass = 0;
        st_add_direct(finalizer_table, obj, table);
    }
  end:
    block = rb_ary_new3(2, INT2FIX(0), block);
    OBJ_FREEZE(block);
    return block;
}

VALUE
rb_gc_impl_undefine_finalizer(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;
    st_data_t data = obj;
    rb_check_frozen(obj);
    st_delete(finalizer_table, &data, 0);
    FL_UNSET(obj, FL_FINALIZE);
    return obj;
}

VALUE
rb_gc_impl_get_finalizers(void *objspace_ptr, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (FL_TEST(obj, FL_FINALIZE)) {
        st_data_t data;
        if (st_lookup(finalizer_table, obj, &data)) {
            return (VALUE)data;
        }
    }

    return Qnil;
}

void
rb_gc_impl_copy_finalizer(void *objspace_ptr, VALUE dest, VALUE obj)
{
    rb_objspace_t *objspace = objspace_ptr;
    VALUE table;
    st_data_t data;

    if (!FL_TEST(obj, FL_FINALIZE)) return;

    if (RB_LIKELY(st_lookup(finalizer_table, obj, &data))) {
        table = (VALUE)data;
        st_insert(finalizer_table, dest, table);
        FL_SET(dest, FL_FINALIZE);
    }
    else {
        rb_bug("rb_gc_copy_finalizer: FL_FINALIZE set but not found in finalizer_table: %s", rb_obj_info(obj));
    }
}

void
rb_gc_impl_shutdown_free_objects(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    for (size_t i = 0; i < heap_allocated_pages; i++) {
        struct heap_page *page = heap_pages_sorted[i];
        short stride = page->slot_size;

        uintptr_t p = (uintptr_t)page->start;
        uintptr_t pend = p + page->total_slots * stride;
        for (; p < pend; p += stride) {
            VALUE vp = (VALUE)p;
            switch (BUILTIN_TYPE(vp)) {
              case T_NONE:
              case T_SYMBOL:
                break;
              default:
                rb_gc_obj_free(objspace, vp);
                break;
            }
        }
    }
}

void
rb_gc_impl_shutdown_call_finalizer(void *objspace_ptr)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (RUBY_ATOMIC_EXCHANGE(finalizing, 1)) return;

    /* run finalizers */
    finalize_deferred(objspace);
    GC_ASSERT(heap_pages_deferred_final == 0);

    /* force to run finalizer */
    while (finalizer_table->num_entries) {
        struct force_finalize_list *list = 0;
        st_foreach(finalizer_table, force_chain_object, (st_data_t)&list);
        while (list) {
            struct force_finalize_list *curr = list;

            st_data_t obj = (st_data_t)curr->obj;
            st_delete(finalizer_table, &obj, 0);
            FL_UNSET(curr->obj, FL_FINALIZE);

            rb_gc_run_obj_finalizer(rb_gc_impl_object_id(objspace, curr->obj), RARRAY_LEN(curr->table), get_final, (void *)curr->table);

            list = curr->next;
            xfree(curr);
        }
    }

    /* run data/file object's finalizers */
    for (size_t i = 0; i < heap_allocated_pages; i++) {
        struct heap_page *page = heap_pages_sorted[i];
        short stride = page->slot_size;

        uintptr_t p = (uintptr_t)page->start;
        uintptr_t pend = p + page->total_slots * stride;
        for (; p < pend; p += stride) {
            VALUE vp = (VALUE)p;
            void *poisoned = asan_unpoison_object_temporary(vp);

            if (rb_gc_shutdown_call_finalizer_p(vp)) {
                rb_gc_obj_free(objspace, vp);
            }

            if (poisoned) {
                GC_ASSERT(BUILTIN_TYPE(vp) == T_NONE);
                asan_poison_object(vp);
            }
        }
    }

    finalize_deferred_heap_pages(objspace);

    st_free_table(finalizer_table);
    finalizer_table = 0;
    RUBY_ATOMIC_SET(finalizing, 0);
}

void
rb_gc_impl_each_object(void *objspace_ptr, void (*func)(VALUE obj, void *data), void *data)
{
    rb_objspace_t *objspace = objspace_ptr;

    for (size_t i = 0; i < heap_allocated_pages; i++) {
        struct heap_page *page = heap_pages_sorted[i];
        short stride = page->slot_size;

        uintptr_t p = (uintptr_t)page->start;
        uintptr_t pend = p + page->total_slots * stride;
        for (; p < pend; p += stride) {
            VALUE obj = (VALUE)p;

            void *poisoned = asan_unpoison_object_temporary(obj);

            func(obj, data);

            if (poisoned) {
                GC_ASSERT(BUILTIN_TYPE(obj) == T_NONE);
                asan_poison_object(obj);
            }
        }
    }
}

size_t
rb_gc_impl_stat(void *objspace_ptr, VALUE hash_or_sym)
{
    rb_objspace_t *objspace = objspace_ptr;
    VALUE hash = Qnil, key = Qnil;

    setup_gc_stat_symbols();

    if (RB_TYPE_P(hash_or_sym, T_HASH)) {
        hash = hash_or_sym;
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

    /* implementation dependent counters */
    SET(heap_allocated_pages, heap_allocated_pages);
    SET(heap_sorted_length, heap_pages_sorted_length);
    SET(heap_allocatable_pages, objspace->heap.allocatable_pages);
    SET(heap_available_slots, objspace->heap.total_slots);
    SET(heap_live_slots, objspace_live_slots(objspace));
    SET(heap_free_slots, objspace_free_slots(objspace));
    SET(heap_final_slots, heap_pages_final_slots);
    SET(heap_eden_pages, objspace->heap.total_pages);
    SET(total_allocated_pages, objspace->heap.total_allocated_pages);
    SET(total_allocated_objects, objspace->heap.total_allocated_objects);
    SET(malloc_increase_bytes, malloc_increase);
#undef SET

    if (!NIL_P(key)) { /* matched key should return above */
        rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(key));
    }

    return 0;
}

int
rb_gc_impl_heap_count(void *objspace_ptr)
{
    return 1;
}

static void
setup_gc_stat_heap_symbols(void)
{
    if (gc_stat_heap_symbols[0] == 0) {
#define S(s) gc_stat_heap_symbols[gc_stat_heap_sym_##s] = ID2SYM(rb_intern_const(#s))
        S(heap_allocatable_pages);
        S(heap_eden_pages);
        S(heap_eden_slots);
        S(total_allocated_pages);
        S(total_allocated_objects);
#undef S
    }
}

size_t
rb_gc_impl_stat_heap(void *objspace_ptr, int _, VALUE hash_or_sym)
{
    rb_objspace_t *objspace = objspace_ptr;
    VALUE hash = Qnil, key = Qnil;

    setup_gc_stat_heap_symbols();

    if (RB_TYPE_P(hash_or_sym, T_HASH)) {
        hash = hash_or_sym;
    }
    else if (SYMBOL_P(hash_or_sym)) {
        key = hash_or_sym;
    }
    else {
        rb_raise(rb_eTypeError, "non-hash or symbol argument");
    }

#define SET(name, attr) \
    if (key == gc_stat_heap_symbols[gc_stat_heap_sym_##name]) \
        return attr; \
    else if (hash != Qnil) \
        rb_hash_aset(hash, gc_stat_heap_symbols[gc_stat_heap_sym_##name], SIZET2NUM(attr));

    SET(heap_allocatable_pages, objspace->heap.allocatable_pages);
    SET(heap_eden_pages, objspace->heap.total_pages);
    SET(heap_eden_slots, objspace->heap.total_slots);
    SET(total_allocated_pages, objspace->heap.total_allocated_pages);
    SET(total_allocated_objects, objspace->heap.total_allocated_objects);
#undef SET

    if (!NIL_P(key)) { /* matched key should return above */
        rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(key));
    }

    return 0;
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
    old_size = malloc_size(ptr);

    objspace_malloc_increase(objspace, ptr, 0, old_size, MEMOP_TYPE_FREE) {
        free(ptr);
        ptr = NULL;
    }
}

void *
rb_gc_impl_malloc(void *objspace_ptr, size_t size)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (size == 0) size = 1;
    void *mem = malloc(size);
    return objspace_malloc_fixup(objspace, mem, size);
}

void *
rb_gc_impl_calloc(void *objspace_ptr, size_t size)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (size == 0) size = 1;
    void *mem = calloc1(size);
    return objspace_malloc_fixup(objspace, mem, size);
}

void *
rb_gc_impl_realloc(void *objspace_ptr, void *ptr, size_t new_size, size_t old_size)
{
    rb_objspace_t *objspace = objspace_ptr;
    void *mem;

    if (!ptr) return rb_gc_impl_malloc(objspace, new_size);

    if (new_size == 0) {
        if ((mem = rb_gc_impl_malloc(objspace, 0)) != NULL) {
            rb_gc_impl_free(objspace, ptr, old_size);
            return mem;
        }
        else {
            new_size = 1;
        }
    }

    old_size = malloc_size(ptr);
    mem = RB_GNUC_EXTENSION_BLOCK(realloc(ptr, new_size));
    new_size = malloc_size(mem);

    objspace_malloc_increase(objspace, mem, new_size, old_size, MEMOP_TYPE_REALLOC);

    return mem;
}

void
rb_gc_impl_adjust_memory_usage(void *objspace_ptr, ssize_t diff)
{
    rb_objspace_t *objspace = objspace_ptr;

    if (diff > 0) {
        objspace_malloc_increase(objspace, 0, diff, 0, MEMOP_TYPE_REALLOC);
    }
    else if (diff < 0) {
        objspace_malloc_increase(objspace, 0, 0, -diff, MEMOP_TYPE_REALLOC);
    }
}

void *
rb_gc_impl_objspace_alloc(void)
{
    rb_objspace_t *objspace = calloc1(sizeof(rb_objspace_t));
    return objspace;
}

void
rb_gc_impl_objspace_init(void *objspace_ptr)
{

#if defined(INIT_HEAP_PAGE_ALLOC_USE_MMAP)
    /* Need to determine if we can use mmap at runtime. */
    heap_page_alloc_use_mmap = INIT_HEAP_PAGE_ALLOC_USE_MMAP;
#endif

    rb_objspace_t *objspace = objspace_ptr;

    objspace->finalize_deferred_pjob = rb_postponed_job_preregister(0, gc_finalize_deferred, objspace);
    if (objspace->finalize_deferred_pjob == POSTPONED_JOB_HANDLE_INVALID) {
        rb_bug("Could not preregister postponed job for GC");
    }

    ccan_list_head_init(&objspace->heap.pages);

    objspace->next_object_id = OBJ_ID_INCREMENT;
    objspace->id_to_obj_tbl = st_init_table(&object_id_hash_type);
    objspace->obj_to_id_tbl = st_init_numtable();

    objspace->heap.allocatable_pages = OBJ_SIZE_MULTIPLES * 10;
    heap_pages_expand_sorted(objspace);

    for (int i = 0; i < OBJ_SIZE_MULTIPLES; i++) {
        rb_heap_page_t *page = heap_prepare(objspace, (1 << i) * BASE_SLOT_SIZE);
        objspace->free_page_cache[i] = page;
    }

    finalizer_table = st_init_numtable();
}

size_t
rb_gc_impl_obj_slot_size(VALUE obj)
{
    return GET_HEAP_PAGE(obj)->slot_size;
}

/* ===== PUBLIC: GC INITIALIZER */
void
rb_gc_impl_init(void)
{
    VALUE gc_constants = rb_hash_new();
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("BASE_SLOT_SIZE")), SIZET2NUM(BASE_SLOT_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_OBJ_LIMIT")), SIZET2NUM(HEAP_PAGE_OBJ_LIMIT));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_BITMAP_SIZE")), SIZET2NUM(0));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("HEAP_PAGE_SIZE")), SIZET2NUM(HEAP_PAGE_SIZE));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("OBJ_SIZE_MULTIPLES")), LONG2FIX(OBJ_SIZE_MULTIPLES));
    rb_hash_aset(gc_constants, ID2SYM(rb_intern("RVARGC_MAX_ALLOCATE_SIZE")),
            LONG2FIX(valid_object_sizes_ordered_idx(OBJ_SIZE_MULTIPLES - 1)));
    if (RB_BUG_INSTEAD_OF_RB_MEMERROR+0) {
        rb_hash_aset(gc_constants, ID2SYM(rb_intern("RB_BUG_INSTEAD_OF_RB_MEMERROR")), Qtrue);
    }
    OBJ_FREEZE(gc_constants);
    /* Internal constants in the garbage collector. */
    rb_define_const(rb_mGC, "INTERNAL_CONSTANTS", gc_constants);

    /* internal methods */
    rb_define_singleton_method(rb_mGC, "verify_internal_consistency", rb_f_notimplement, 0);

    VALUE rb_mProfiler = rb_define_module_under(rb_mGC, "Profiler");
    rb_define_singleton_method(rb_mProfiler, "enabled?", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mProfiler, "enable", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mProfiler, "raw_data", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mProfiler, "disable", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mProfiler, "clear", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mProfiler, "result", rb_f_notimplement, 0);
    rb_define_singleton_method(rb_mProfiler, "report", rb_f_notimplement, -1);
    rb_define_singleton_method(rb_mProfiler, "total_time", rb_f_notimplement, 0);

    {
        VALUE opts;
        rb_define_const(rb_mGC, "OPTS", opts = rb_ary_new());
        OBJ_FREEZE(opts);
    }
}

size_t rb_gc_impl_obj_flags(void *objspace, VALUE obj, ID* f, size_t max) { return 0; }
size_t rb_gc_impl_gc_count(void *objspace)                                { return 0; }
void * rb_gc_impl_ractor_cache_alloc(void *objspace)                      { return NULL; }
VALUE rb_gc_impl_stress_get(void *objspace)                               { return Qfalse; }
VALUE rb_gc_impl_get_profile_total_time(void *objspace)                   { return Qnil; }
VALUE rb_gc_impl_get_measure_total_time(void *objspace)                   { return Qfalse; }
VALUE rb_gc_impl_location(void *objspace_ptr, VALUE value)                { return value; }
VALUE rb_gc_impl_latest_gc_info(void *objspace_ptr, VALUE key)            { return Qnil; }
VALUE rb_gc_impl_set_measure_total_time(void *objspace, VALUE f)          { return f; }
bool rb_gc_impl_object_moved_p(void *objspace, VALUE obj)                 { return FALSE; }
bool rb_gc_impl_during_gc_p(void *objspace)                               { return FALSE; }
bool rb_gc_impl_gc_enabled_p(void *objspace)                              { return FALSE; }
bool rb_gc_impl_garbage_object_p(void *objspace, VALUE ptr)               { return false; }

/* ===== UNUSED PUBLIC API FUNCTIONS */

void rb_gc_impl_stress_set(void *objspace_ptr, VALUE flag)                { /* nop */ }
void rb_gc_impl_set_params(void *objspace_ptr)                            { /* nop */ }
void rb_gc_impl_gc_enable(void *objspace_ptr)                             { /* nop */ }
void rb_gc_impl_gc_disable(void *objspace_ptr, bool finish_current)       { /* nop */ }
void rb_gc_impl_initial_stress_set(VALUE flag)                            { /* nop */ }
void rb_gc_impl_mark_and_move(void *objspace_ptr, VALUE *ptr)             { /* nop */ }
void rb_gc_impl_mark(void *objspace_ptr, VALUE obj)                       { /* nop */ }
void rb_gc_impl_mark_and_pin(void *objspace_ptr, VALUE obj)               { /* nop */ }
void rb_gc_impl_mark_maybe(void *objspace_ptr, VALUE obj)                 { /* nop */ }
void rb_gc_impl_mark_weak(void *objspace_ptr, VALUE *ptr)                 { /* nop */ }
void rb_gc_impl_remove_weak(void *objspace_ptr, VALUE parent, VALUE *ptr) { /* nop */ }
void rb_gc_impl_writebarrier(void *objspace_ptr, VALUE a, VALUE b)        { /* nop */ }
void rb_gc_impl_writebarrier_unprotect(void *objspace_ptr, VALUE obj)     { /* nop */ }
void rb_gc_impl_copy_attributes(void *objspace_ptr, VALUE des, VALUE obj) { /* nop */ }
void rb_gc_impl_writebarrier_remember(void *objspace_ptr, VALUE obj)      { /* nop */ }
void rb_gc_impl_ractor_cache_free(void *objspace_ptr, void *cache)        { /* nop */ }
void rb_gc_impl_prepare_heap(void *objspace_ptr)                          { /* nop */ }
void rb_gc_impl_start(void *objspace_ptr, bool f, bool m, bool s, bool c) { /* nop */ }
void rb_gc_impl_objspace_free(void *objspace_ptr)                         { /* nop */ }
void rb_gc_impl_objspace_mark(void *objspace_ptr)                         { /* nop */ }
