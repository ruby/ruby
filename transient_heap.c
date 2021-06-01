/**********************************************************************

  transient_heap.c - implement transient_heap.

  Copyright (C) 2018 Koichi Sasada

**********************************************************************/

#include "debug_counter.h"
#include "gc.h"
#include "internal.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/sanitizers.h"
#include "internal/static_assert.h"
#include "internal/struct.h"
#include "internal/variable.h"
#include "ruby/debug.h"
#include "ruby/ruby.h"
#include "ruby_assert.h"
#include "transient_heap.h"
#include "vm_debug.h"
#include "vm_sync.h"

#if USE_TRANSIENT_HEAP /* USE_TRANSIENT_HEAP */
/*
 * 1: enable assertions
 * 2: enable verify all transient heaps
 */
#ifndef TRANSIENT_HEAP_CHECK_MODE
#define TRANSIENT_HEAP_CHECK_MODE 0
#endif
#define TH_ASSERT(expr) RUBY_ASSERT_MESG_WHEN(TRANSIENT_HEAP_CHECK_MODE > 0, expr, #expr)

/*
 * 1: show events
 * 2: show dump at events
 * 3: show all operations
 */
#define TRANSIENT_HEAP_DEBUG 0

/* For Debug: Provide blocks infinitely.
 * This mode generates blocks unlimitedly
 * and prohibit access free'ed blocks to check invalid access.
 */
#define TRANSIENT_HEAP_DEBUG_INFINITE_BLOCK 0

#if TRANSIENT_HEAP_DEBUG_INFINITE_BLOCK
#include <sys/mman.h>
#include <errno.h>
#endif

/* For Debug: Prohibit promoting to malloc space.
 */
#define TRANSIENT_HEAP_DEBUG_DONT_PROMOTE 0

/* size configuration */
#define TRANSIENT_HEAP_PROMOTED_DEFAULT_SIZE 1024

                                          /*  K      M */
#define TRANSIENT_HEAP_BLOCK_SIZE  (1024 *   32       ) /* 32KB int16_t */
#define TRANSIENT_HEAP_TOTAL_SIZE  (1024 * 1024 *   32) /* 32 MB */
#define TRANSIENT_HEAP_ALLOC_MAX   (1024 *    2       ) /* 2 KB */
#define TRANSIENT_HEAP_BLOCK_NUM   (TRANSIENT_HEAP_TOTAL_SIZE / TRANSIENT_HEAP_BLOCK_SIZE)
#define TRANSIENT_HEAP_USABLE_SIZE (TRANSIENT_HEAP_BLOCK_SIZE - sizeof(struct transient_heap_block_header))

#define TRANSIENT_HEAP_ALLOC_MAGIC 0xfeab
#define TRANSIENT_HEAP_ALLOC_ALIGN RUBY_ALIGNOF(void *)

#define TRANSIENT_HEAP_ALLOC_MARKING_LAST -1
#define TRANSIENT_HEAP_ALLOC_MARKING_FREE -2

enum transient_heap_status {
    transient_heap_none,
    transient_heap_marking,
    transient_heap_escaping
};

struct transient_heap_block {
    struct transient_heap_block_header {
        int16_t index;
        int16_t last_marked_index;
        int16_t objects;
        struct transient_heap_block *next_block;
    } info;
    char buff[TRANSIENT_HEAP_USABLE_SIZE];
};

struct transient_heap {
    struct transient_heap_block *using_blocks;
    struct transient_heap_block *marked_blocks;
    struct transient_heap_block *free_blocks;
    int total_objects;
    int total_marked_objects;
    int total_blocks;
    enum transient_heap_status status;

    VALUE *promoted_objects;
    int promoted_objects_size;
    int promoted_objects_index;

    struct transient_heap_block *arena;
    int arena_index; /* increment only */
};

struct transient_alloc_header {
    uint16_t magic;
    uint16_t size;
    int16_t next_marked_index;
    int16_t dummy;
    VALUE obj;
};

static struct transient_heap global_transient_heap;

static void  transient_heap_promote_add(struct transient_heap* theap, VALUE obj);
static const void *transient_heap_ptr(VALUE obj, int error);
static int   transient_header_managed_ptr_p(struct transient_heap* theap, const void *ptr);

#define ROUND_UP(v, a)  (((size_t)(v) + (a) - 1) & ~((a) - 1))

static void
transient_heap_block_dump(struct transient_heap* theap, struct transient_heap_block *block)
{
    int i=0, n=0;

    while (i<block->info.index) {
        void *ptr = &block->buff[i];
        struct transient_alloc_header *header = ptr;
        fprintf(stderr, "%4d %8d %p size:%4d next:%4d %s\n", n, i, ptr, header->size, header->next_marked_index, rb_obj_info(header->obj));
        i += header->size;
        n++;
    }
}

static void
transient_heap_blocks_dump(struct transient_heap* theap, struct transient_heap_block *block, const char *type_str)
{
    while (block) {
        fprintf(stderr, "- transient_heap_dump: %s:%p index:%d objects:%d last_marked_index:%d next:%p\n",
                type_str, (void *)block, block->info.index, block->info.objects, block->info.last_marked_index, (void *)block->info.next_block);

        transient_heap_block_dump(theap, block);
        block = block->info.next_block;
    }
}

static void
transient_heap_dump(struct transient_heap* theap)
{
    fprintf(stderr, "transient_heap_dump objects:%d marked_objects:%d blocks:%d\n", theap->total_objects, theap->total_marked_objects, theap->total_blocks);
    transient_heap_blocks_dump(theap, theap->using_blocks, "using_blocks");
    transient_heap_blocks_dump(theap, theap->marked_blocks, "marked_blocks");
    transient_heap_blocks_dump(theap, theap->free_blocks, "free_blocks");
}

/* Debug: dump all transient_heap blocks */
void
rb_transient_heap_dump(void)
{
    transient_heap_dump(&global_transient_heap);
}

#if TRANSIENT_HEAP_CHECK_MODE >= 2
ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS(static void transient_heap_ptr_check(struct transient_heap *theap, VALUE obj));
static void
transient_heap_ptr_check(struct transient_heap *theap, VALUE obj)
{
    if (obj != Qundef) {
        const void *ptr = transient_heap_ptr(obj, FALSE);
        TH_ASSERT(ptr == NULL || transient_header_managed_ptr_p(theap, ptr));
    }
}

ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS(static int transient_heap_block_verify(struct transient_heap *theap, struct transient_heap_block *block));
static int
transient_heap_block_verify(struct transient_heap *theap, struct transient_heap_block *block)
{
    int i=0, n=0;
    struct transient_alloc_header *header;

    while (i<block->info.index) {
        header = (void *)&block->buff[i];
        TH_ASSERT(header->magic == TRANSIENT_HEAP_ALLOC_MAGIC);
        transient_heap_ptr_check(theap, header->obj);
        n ++;
        i += header->size;
    }
    TH_ASSERT(block->info.objects == n);

    return n;
}

static int
transient_heap_blocks_verify(struct transient_heap *theap, struct transient_heap_block *blocks, int *block_num_ptr)
{
    int n = 0;
    struct transient_heap_block *block = blocks;
    while (block) {
        n += transient_heap_block_verify(theap, block);
        *block_num_ptr += 1;
        block = block->info.next_block;
    }

    return n;
}
#endif

static void
transient_heap_verify(struct transient_heap *theap)
{
#if TRANSIENT_HEAP_CHECK_MODE >= 2
    int n=0, block_num=0;

    n += transient_heap_blocks_verify(theap, theap->using_blocks, &block_num);
    n += transient_heap_blocks_verify(theap, theap->marked_blocks, &block_num);

    TH_ASSERT(n == theap->total_objects);
    TH_ASSERT(n >= theap->total_marked_objects);
    TH_ASSERT(block_num == theap->total_blocks);
#endif
}

/* Debug: check assertions for all transient_heap blocks */
void
rb_transient_heap_verify(void)
{
    transient_heap_verify(&global_transient_heap);
}

static struct transient_heap*
transient_heap_get(void)
{
    struct transient_heap* theap = &global_transient_heap;
    transient_heap_verify(theap);
    return theap;
}

static void
reset_block(struct transient_heap_block *block)
{
    __msan_allocated_memory(block, sizeof block);
    block->info.index = 0;
    block->info.objects = 0;
    block->info.last_marked_index = TRANSIENT_HEAP_ALLOC_MARKING_LAST;
    block->info.next_block = NULL;
    __asan_poison_memory_region(&block->buff, sizeof block->buff);
}

static void
connect_to_free_blocks(struct transient_heap *theap, struct transient_heap_block *block)
{
    block->info.next_block = theap->free_blocks;
    theap->free_blocks = block;
}

static void
connect_to_using_blocks(struct transient_heap *theap, struct transient_heap_block *block)
{
    block->info.next_block = theap->using_blocks;
    theap->using_blocks = block;
}

#if 0
static void
connect_to_marked_blocks(struct transient_heap *theap, struct transient_heap_block *block)
{
    block->info.next_block = theap->marked_blocks;
    theap->marked_blocks = block;
}
#endif

static void
append_to_marked_blocks(struct transient_heap *theap, struct transient_heap_block *append_blocks)
{
    if (theap->marked_blocks) {
        struct transient_heap_block *block = theap->marked_blocks, *last_block = NULL;
        while (block) {
            last_block = block;
            block = block->info.next_block;
        }

        TH_ASSERT(last_block->info.next_block == NULL);
        last_block->info.next_block = append_blocks;
    }
    else {
        theap->marked_blocks = append_blocks;
    }
}

static struct transient_heap_block *
transient_heap_block_alloc(struct transient_heap* theap)
{
    struct transient_heap_block *block;
#if TRANSIENT_HEAP_DEBUG_INFINITE_BLOCK
    block = mmap(NULL, TRANSIENT_HEAP_BLOCK_SIZE, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS,
                 -1, 0);
    if (block == MAP_FAILED) rb_bug("transient_heap_block_alloc: err:%d\n", errno);
#else
    if (theap->arena == NULL) {
        theap->arena = rb_aligned_malloc(TRANSIENT_HEAP_BLOCK_SIZE, TRANSIENT_HEAP_TOTAL_SIZE);
        if (theap->arena == NULL) {
             rb_bug("transient_heap_block_alloc: failed\n");
        }
    }

    TH_ASSERT(theap->arena_index < TRANSIENT_HEAP_BLOCK_NUM);
    block = &theap->arena[theap->arena_index++];
    TH_ASSERT(((intptr_t)block & (TRANSIENT_HEAP_BLOCK_SIZE - 1)) == 0);
#endif
    reset_block(block);

    TH_ASSERT(((intptr_t)block->buff & (TRANSIENT_HEAP_ALLOC_ALIGN-1)) == 0);
    if (0) fprintf(stderr, "transient_heap_block_alloc: %4d %p\n", theap->total_blocks, (void *)block);
    return block;
}


static struct transient_heap_block *
transient_heap_allocatable_block(struct transient_heap* theap)
{
    struct transient_heap_block *block;

#if TRANSIENT_HEAP_DEBUG_INFINITE_BLOCK
    block = transient_heap_block_alloc(theap);
    theap->total_blocks++;
#else
    /* get one block from free_blocks */
    block = theap->free_blocks;
    if (block) {
        theap->free_blocks = block->info.next_block;
        block->info.next_block = NULL;
        theap->total_blocks++;
    }
#endif

    return block;
}

static struct transient_alloc_header *
transient_heap_allocatable_header(struct transient_heap* theap, size_t size)
{
    struct transient_heap_block *block = theap->using_blocks;

    while (block) {
        TH_ASSERT(block->info.index <= (int16_t)TRANSIENT_HEAP_USABLE_SIZE);

        if (TRANSIENT_HEAP_USABLE_SIZE - block->info.index >= size) {
            struct transient_alloc_header *header = (void *)&block->buff[block->info.index];
            block->info.index += size;
            block->info.objects++;
            return header;
        }
        else {
            block = transient_heap_allocatable_block(theap);
            if (block) connect_to_using_blocks(theap, block);
        }
    }

    return NULL;
}

void *
rb_transient_heap_alloc(VALUE obj, size_t req_size)
{
    // only on single main ractor
    if (ruby_single_main_ractor == NULL) return NULL;

    void *ret;
    struct transient_heap* theap = transient_heap_get();
    size_t size = ROUND_UP(req_size + sizeof(struct transient_alloc_header), TRANSIENT_HEAP_ALLOC_ALIGN);

    TH_ASSERT(RB_TYPE_P(obj, T_ARRAY)  ||
              RB_TYPE_P(obj, T_OBJECT) ||
              RB_TYPE_P(obj, T_STRUCT) ||
              RB_TYPE_P(obj, T_HASH)); /* supported types */

    if (size > TRANSIENT_HEAP_ALLOC_MAX) {
        if (TRANSIENT_HEAP_DEBUG >= 3) fprintf(stderr, "rb_transient_heap_alloc: [too big: %ld] %s\n", (long)size, rb_obj_info(obj));
        ret = NULL;
    }
#if TRANSIENT_HEAP_DEBUG_DONT_PROMOTE == 0
    else if (RB_OBJ_PROMOTED_RAW(obj)) {
        if (TRANSIENT_HEAP_DEBUG >= 3)  fprintf(stderr, "rb_transient_heap_alloc: [promoted object] %s\n", rb_obj_info(obj));
        ret = NULL;
    }
#else
    else if (RBASIC_CLASS(obj) == 0) {
        if (TRANSIENT_HEAP_DEBUG >= 3)  fprintf(stderr, "rb_transient_heap_alloc: [hidden object] %s\n", rb_obj_info(obj));
        ret = NULL;
    }
#endif
    else {
        struct transient_alloc_header *header = transient_heap_allocatable_header(theap, size);
        if (header) {
            void *ptr;

            /* header is poisoned to prevent buffer overflow, should
             * unpoison first... */
            asan_unpoison_memory_region(header, sizeof *header, true);

            header->size = size;
            header->magic = TRANSIENT_HEAP_ALLOC_MAGIC;
            header->next_marked_index = TRANSIENT_HEAP_ALLOC_MARKING_FREE;
            header->obj = obj; /* TODO: can we eliminate it? */

            /* header is fixed; shall poison again */
            asan_poison_memory_region(header, sizeof *header);
            ptr = header + 1;

            theap->total_objects++; /* statistics */

#if TRANSIENT_HEAP_DEBUG_DONT_PROMOTE
            if (RB_OBJ_PROMOTED_RAW(obj)) {
                transient_heap_promote_add(theap, obj);
            }
#endif
            if (TRANSIENT_HEAP_DEBUG >= 3) fprintf(stderr, "rb_transient_heap_alloc: header:%p ptr:%p size:%d obj:%s\n", (void *)header, ptr, (int)size, rb_obj_info(obj));

            RB_DEBUG_COUNTER_INC(theap_alloc);

            /* ptr is set up; OK to unpoison. */
            asan_unpoison_memory_region(ptr, size - sizeof *header, true);
            ret = ptr;
        }
        else {
            if (TRANSIENT_HEAP_DEBUG >= 3) fprintf(stderr, "rb_transient_heap_alloc: [no enough space: %ld] %s\n", (long)size, rb_obj_info(obj));
            RB_DEBUG_COUNTER_INC(theap_alloc_fail);
            ret = NULL;
        }
    }

    return ret;
}

void
Init_TransientHeap(void)
{
    int i, block_num;
    struct transient_heap* theap = transient_heap_get();

#if TRANSIENT_HEAP_DEBUG_INFINITE_BLOCK
    block_num = 0;
#else
    TH_ASSERT(TRANSIENT_HEAP_BLOCK_SIZE * TRANSIENT_HEAP_BLOCK_NUM == TRANSIENT_HEAP_TOTAL_SIZE);
    block_num = TRANSIENT_HEAP_BLOCK_NUM;
#endif
    for (i=0; i<block_num; i++) {
        connect_to_free_blocks(theap, transient_heap_block_alloc(theap));
    }
    theap->using_blocks = transient_heap_allocatable_block(theap);

    theap->promoted_objects_size = TRANSIENT_HEAP_PROMOTED_DEFAULT_SIZE;
    theap->promoted_objects_index = 0;
    /* should not use ALLOC_N to be free from GC */
    theap->promoted_objects = malloc(sizeof(VALUE) * theap->promoted_objects_size);
    STATIC_ASSERT(
        integer_overflow,
        sizeof(VALUE) <= SIZE_MAX / TRANSIENT_HEAP_PROMOTED_DEFAULT_SIZE);
    if (theap->promoted_objects == NULL) rb_bug("Init_TransientHeap: malloc failed.");
}

static struct transient_heap_block *
blocks_alloc_header_to_block(struct transient_heap *theap, struct transient_heap_block *blocks, struct transient_alloc_header *header)
{
    struct transient_heap_block *block = blocks;

    while (block) {
        if (block->buff <= (char *)header && (char *)header < block->buff + TRANSIENT_HEAP_USABLE_SIZE) {
            return block;
        }
        block = block->info.next_block;
    }

    return NULL;
}

static struct transient_heap_block *
alloc_header_to_block_verbose(struct transient_heap *theap, struct transient_alloc_header *header)
{
    struct transient_heap_block *block;

    if ((block = blocks_alloc_header_to_block(theap, theap->marked_blocks, header)) != NULL) {
        if (TRANSIENT_HEAP_DEBUG >= 3) fprintf(stderr, "alloc_header_to_block: found in marked_blocks\n");
        return block;
    }
    else if ((block = blocks_alloc_header_to_block(theap, theap->using_blocks, header)) != NULL) {
        if (TRANSIENT_HEAP_DEBUG >= 3) fprintf(stderr, "alloc_header_to_block: found in using_blocks\n");
        return block;
    }
    else {
        return NULL;
    }
}

static struct transient_alloc_header *
ptr_to_alloc_header(const void *ptr)
{
    struct transient_alloc_header *header = (void *)ptr;
    header -= 1;
    return header;
}

static int
transient_header_managed_ptr_p(struct transient_heap* theap, const void *ptr)
{
    if (alloc_header_to_block_verbose(theap, ptr_to_alloc_header(ptr))) {
        return TRUE;
    }
    else {
        return FALSE;
    }
}


int
rb_transient_heap_managed_ptr_p(const void *ptr)
{
    return transient_header_managed_ptr_p(transient_heap_get(), ptr);
}

static struct transient_heap_block *
alloc_header_to_block(struct transient_heap *theap, struct transient_alloc_header *header)
{
    struct transient_heap_block *block;
#if TRANSIENT_HEAP_DEBUG_INFINITE_BLOCK
    block = alloc_header_to_block_verbose(theap, header);
    if (block == NULL) {
        transient_heap_dump(theap);
        rb_bug("alloc_header_to_block: not found in mark_blocks (%p)\n", header);
    }
#else
    block = (void *)((intptr_t)header & ~(TRANSIENT_HEAP_BLOCK_SIZE-1));
    TH_ASSERT(block == alloc_header_to_block_verbose(theap, header));
#endif
    return block;
}

void
rb_transient_heap_mark(VALUE obj, const void *ptr)
{
    ASSERT_vm_locking();

    struct transient_alloc_header *header = ptr_to_alloc_header(ptr);
    asan_unpoison_memory_region(header, sizeof *header, false);
    if (header->magic != TRANSIENT_HEAP_ALLOC_MAGIC) rb_bug("rb_transient_heap_mark: wrong header, %s (%p)", rb_obj_info(obj), ptr);
    if (TRANSIENT_HEAP_DEBUG >= 3) fprintf(stderr, "rb_transient_heap_mark: %s (%p)\n", rb_obj_info(obj), ptr);

#if TRANSIENT_HEAP_CHECK_MODE > 0
    {
        struct transient_heap* theap = transient_heap_get();
        TH_ASSERT(theap->status == transient_heap_marking);
        TH_ASSERT(transient_header_managed_ptr_p(theap, ptr));

        if (header->magic != TRANSIENT_HEAP_ALLOC_MAGIC) {
            transient_heap_dump(theap);
            rb_bug("rb_transient_heap_mark: magic is broken");
        }
        else if (header->obj != obj) {
            // transient_heap_dump(theap);
            rb_bug("rb_transient_heap_mark: unmatch (%s is stored, but %s is given)\n",
                   rb_obj_info(header->obj), rb_obj_info(obj));
        }
    }
#endif

    if (header->next_marked_index != TRANSIENT_HEAP_ALLOC_MARKING_FREE) {
        /* already marked */
        return;
    }
    else {
        struct transient_heap* theap = transient_heap_get();
        struct transient_heap_block *block = alloc_header_to_block(theap, header);
        __asan_unpoison_memory_region(&block->info, sizeof block->info);
        header->next_marked_index = block->info.last_marked_index;
        block->info.last_marked_index = (int)((char *)header - block->buff);
        theap->total_marked_objects++;

        transient_heap_verify(theap);
    }
}

ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS(static const void *transient_heap_ptr(VALUE obj, int error));
static const void *
transient_heap_ptr(VALUE obj, int error)
{
    const void *ptr = NULL;

    switch (BUILTIN_TYPE(obj)) {
      case T_ARRAY:
        if (RARRAY_TRANSIENT_P(obj)) {
            TH_ASSERT(!FL_TEST_RAW(obj, RARRAY_EMBED_FLAG));
            ptr = RARRAY(obj)->as.heap.ptr;
        }
        break;
      case T_OBJECT:
        if (ROBJ_TRANSIENT_P(obj)) {
            ptr = ROBJECT_IVPTR(obj);
        }
        break;
      case T_STRUCT:
        if (RSTRUCT_TRANSIENT_P(obj)) {
            ptr = rb_struct_const_heap_ptr(obj);
        }
        break;
      case T_HASH:
        if (RHASH_TRANSIENT_P(obj)) {
            TH_ASSERT(RHASH_AR_TABLE_P(obj));
            ptr = (VALUE *)(RHASH(obj)->as.ar);
        }
        else {
            ptr = NULL;
        }
        break;
      default:
        if (error) {
            rb_bug("transient_heap_ptr: unknown obj %s\n", rb_obj_info(obj));
        }
    }

    return ptr;
}

static void
transient_heap_promote_add(struct transient_heap* theap, VALUE obj)
{
    if (TRANSIENT_HEAP_DEBUG >= 3) fprintf(stderr, "rb_transient_heap_promote: %s\n", rb_obj_info(obj));

    if (TRANSIENT_HEAP_DEBUG_DONT_PROMOTE) {
        /* duplicate check */
        int i;
        for (i=0; i<theap->promoted_objects_index; i++) {
            if (theap->promoted_objects[i] == obj) return;
        }
    }

    if (theap->promoted_objects_size <= theap->promoted_objects_index) {
        theap->promoted_objects_size *= 2;
        if (TRANSIENT_HEAP_DEBUG >= 1) fprintf(stderr, "rb_transient_heap_promote: expand table to %d\n", theap->promoted_objects_size);
        if (UNLIKELY((size_t)theap->promoted_objects_size > SIZE_MAX / sizeof(VALUE))) {
            /* realloc failure due to integer overflow */
            theap->promoted_objects = NULL;
        }
        else {
            theap->promoted_objects = realloc(theap->promoted_objects, theap->promoted_objects_size * sizeof(VALUE));
        }
        if (theap->promoted_objects == NULL) rb_bug("rb_transient_heap_promote: realloc failed");
    }
    theap->promoted_objects[theap->promoted_objects_index++] = obj;
}

void
rb_transient_heap_promote(VALUE obj)
{
    ASSERT_vm_locking();

    if (transient_heap_ptr(obj, FALSE)) {
        struct transient_heap* theap = transient_heap_get();
        transient_heap_promote_add(theap, obj);
    }
    else {
        /* ignore */
    }
}

static struct transient_alloc_header *
alloc_header(struct transient_heap_block* block, int index)
{
    return (void *)&block->buff[index];
}

static void
transient_heap_reset(void)
{
    ASSERT_vm_locking();

    struct transient_heap* theap = transient_heap_get();
    struct transient_heap_block* block;

    if (TRANSIENT_HEAP_DEBUG >= 1) fprintf(stderr, "!! transient_heap_reset\n");

    block = theap->marked_blocks;
    while (block) {
        struct transient_heap_block *next_block = block->info.next_block;
        theap->total_objects -= block->info.objects;
#if TRANSIENT_HEAP_DEBUG_INFINITE_BLOCK
        if (madvise(block, TRANSIENT_HEAP_BLOCK_SIZE, MADV_DONTNEED) != 0) {
            rb_bug("madvise err:%d", errno);
        }
        if (mprotect(block, TRANSIENT_HEAP_BLOCK_SIZE, PROT_NONE) != 0) {
            rb_bug("mprotect err:%d", errno);
        }
#else
        reset_block(block);
        connect_to_free_blocks(theap, block);
#endif
        theap->total_blocks--;
        block = next_block;
    }

    if (TRANSIENT_HEAP_DEBUG >= 1) fprintf(stderr, "!! transient_heap_reset block_num:%d\n", theap->total_blocks);

    theap->marked_blocks = NULL;
    theap->total_marked_objects = 0;
}

static void
transient_heap_block_evacuate(struct transient_heap* theap, struct transient_heap_block* block)
{
    int marked_index = block->info.last_marked_index;
    block->info.last_marked_index = TRANSIENT_HEAP_ALLOC_MARKING_LAST;

    while (marked_index >= 0) {
        struct transient_alloc_header *header = alloc_header(block, marked_index);
        asan_unpoison_memory_region(header, sizeof *header, true);
        VALUE obj = header->obj;
        TH_ASSERT(header->magic == TRANSIENT_HEAP_ALLOC_MAGIC);
        if (header->magic != TRANSIENT_HEAP_ALLOC_MAGIC) rb_bug("transient_heap_block_evacuate: wrong header %p %s\n", (void *)header, rb_obj_info(obj));

        if (TRANSIENT_HEAP_DEBUG >= 3) fprintf(stderr, " * transient_heap_block_evacuate %p %s\n", (void *)header, rb_obj_info(obj));

        if (obj != Qnil) {
            RB_DEBUG_COUNTER_INC(theap_evacuate);

            switch (BUILTIN_TYPE(obj)) {
              case T_ARRAY:
                rb_ary_transient_heap_evacuate(obj, !TRANSIENT_HEAP_DEBUG_DONT_PROMOTE);
                break;
              case T_OBJECT:
                rb_obj_transient_heap_evacuate(obj, !TRANSIENT_HEAP_DEBUG_DONT_PROMOTE);
                break;
              case T_STRUCT:
                rb_struct_transient_heap_evacuate(obj, !TRANSIENT_HEAP_DEBUG_DONT_PROMOTE);
                break;
              case T_HASH:
                rb_hash_transient_heap_evacuate(obj, !TRANSIENT_HEAP_DEBUG_DONT_PROMOTE);
                break;
              default:
                rb_bug("unsupported: %s\n", rb_obj_info(obj));
            }
            header->obj = Qundef; /* for debug */
        }
        marked_index = header->next_marked_index;
        asan_poison_memory_region(header, sizeof *header);
    }
}

#if USE_RUBY_DEBUG_LOG
static const char *
transient_heap_status_cstr(enum transient_heap_status status)
{
    switch (status) {
      case transient_heap_none: return "none";
      case transient_heap_marking: return "marking";
      case transient_heap_escaping: return "escaping";
    }
    UNREACHABLE_RETURN(NULL);
}
#endif

static void
transient_heap_update_status(struct transient_heap* theap, enum transient_heap_status status)
{
    RUBY_DEBUG_LOG("%s -> %s",
                   transient_heap_status_cstr(theap->status),
                   transient_heap_status_cstr(status));

    TH_ASSERT(theap->status != status);
    theap->status = status;
}

static void
transient_heap_evacuate(void *dmy)
{
    struct transient_heap* theap = transient_heap_get();

    if (theap->total_marked_objects == 0) return;
    if (ruby_single_main_ractor == NULL) rb_bug("not single ractor mode");
    if (theap->status == transient_heap_marking) {
        if (TRANSIENT_HEAP_DEBUG >= 1) fprintf(stderr, "!! transient_heap_evacuate: skip while transient_heap_marking\n");
    }
    else {
        VALUE gc_disabled = rb_gc_disable_no_rest();
        {
            struct transient_heap_block* block;

            RUBY_DEBUG_LOG("start gc_disabled:%d", RTEST(gc_disabled));

            if (TRANSIENT_HEAP_DEBUG >= 1) {
                int i;
                fprintf(stderr, "!! transient_heap_evacuate start total_blocks:%d\n", theap->total_blocks);
                if (TRANSIENT_HEAP_DEBUG >= 4) {
                    for (i=0; i<theap->promoted_objects_index; i++) fprintf(stderr, "%4d %s\n", i, rb_obj_info(theap->promoted_objects[i]));
                }
            }
            if (TRANSIENT_HEAP_DEBUG >= 2) transient_heap_dump(theap);

            TH_ASSERT(theap->status == transient_heap_none);
            transient_heap_update_status(theap, transient_heap_escaping);

            /* evacuate from marked blocks */
            block = theap->marked_blocks;
            while (block) {
                transient_heap_block_evacuate(theap, block);
                block = block->info.next_block;
            }

            /* evacuate from using blocks
           only affect incremental marking */
            block = theap->using_blocks;
            while (block) {
                transient_heap_block_evacuate(theap, block);
                block = block->info.next_block;
            }

            /* all objects in marked_objects are escaped. */
            transient_heap_reset();

            if (TRANSIENT_HEAP_DEBUG > 0) {
                fprintf(stderr, "!! transient_heap_evacuate end total_blocks:%d\n", theap->total_blocks);
            }

            transient_heap_verify(theap);
            transient_heap_update_status(theap, transient_heap_none);
        }
        if (gc_disabled != Qtrue) rb_gc_enable();
        RUBY_DEBUG_LOG("finish", 0);
    }
}

void
rb_transient_heap_evacuate(void)
{
    transient_heap_evacuate(NULL);
}

static void
clear_marked_index(struct transient_heap_block* block)
{
    int marked_index = block->info.last_marked_index;

    while (marked_index != TRANSIENT_HEAP_ALLOC_MARKING_LAST) {
        struct transient_alloc_header *header = alloc_header(block, marked_index);
        /* header is poisoned to prevent buffer overflow, should
         * unpoison first... */
        asan_unpoison_memory_region(header, sizeof *header, false);
        TH_ASSERT(marked_index != TRANSIENT_HEAP_ALLOC_MARKING_FREE);
        if (0) fprintf(stderr, "clear_marked_index - block:%p mark_index:%d\n", (void *)block, marked_index);

        marked_index = header->next_marked_index;
        header->next_marked_index = TRANSIENT_HEAP_ALLOC_MARKING_FREE;
    }

    block->info.last_marked_index = TRANSIENT_HEAP_ALLOC_MARKING_LAST;
}

static void
blocks_clear_marked_index(struct transient_heap_block* block)
{
    while (block) {
        clear_marked_index(block);
        block = block->info.next_block;
    }
}

static void
transient_heap_block_update_refs(struct transient_heap* theap, struct transient_heap_block* block)
{
    int marked_index = block->info.last_marked_index;

    while (marked_index >= 0) {
        struct transient_alloc_header *header = alloc_header(block, marked_index);

        asan_unpoison_memory_region(header, sizeof *header, false);

        header->obj = rb_gc_location(header->obj);

        marked_index = header->next_marked_index;
        asan_poison_memory_region(header, sizeof *header);
    }
}

static void
transient_heap_blocks_update_refs(struct transient_heap* theap, struct transient_heap_block *block, const char *type_str)
{
    while (block) {
        transient_heap_block_update_refs(theap, block);
        block = block->info.next_block;
    }
}

void
rb_transient_heap_update_references(void)
{
    ASSERT_vm_locking();

    struct transient_heap* theap = transient_heap_get();
    int i;

    transient_heap_blocks_update_refs(theap, theap->using_blocks, "using_blocks");
    transient_heap_blocks_update_refs(theap, theap->marked_blocks, "marked_blocks");

    for (i=0; i<theap->promoted_objects_index; i++) {
        VALUE obj = theap->promoted_objects[i];
        theap->promoted_objects[i] = rb_gc_location(obj);
    }
}

void
rb_transient_heap_start_marking(int full_marking)
{
    ASSERT_vm_locking();
    RUBY_DEBUG_LOG("full?:%d", full_marking);

    struct transient_heap* theap = transient_heap_get();

    if (TRANSIENT_HEAP_DEBUG >= 1) fprintf(stderr, "!! rb_transient_heap_start_marking objects:%d blocks:%d promoted:%d full_marking:%d\n",
                                           theap->total_objects, theap->total_blocks, theap->promoted_objects_index, full_marking);
    if (TRANSIENT_HEAP_DEBUG >= 2) transient_heap_dump(theap);

    blocks_clear_marked_index(theap->marked_blocks);
    blocks_clear_marked_index(theap->using_blocks);

    if (theap->using_blocks) {
        if (theap->using_blocks->info.objects > 0) {
            append_to_marked_blocks(theap, theap->using_blocks);
            theap->using_blocks = NULL;
        }
        else {
            append_to_marked_blocks(theap, theap->using_blocks->info.next_block);
            theap->using_blocks->info.next_block = NULL;
        }
    }

    if (theap->using_blocks == NULL) {
        theap->using_blocks = transient_heap_allocatable_block(theap);
    }

    TH_ASSERT(theap->status == transient_heap_none);
    transient_heap_update_status(theap, transient_heap_marking);
    theap->total_marked_objects = 0;

    if (full_marking) {
        theap->promoted_objects_index = 0;
    }
    else { /* mark promoted objects */
        int i;
        for (i=0; i<theap->promoted_objects_index; i++) {
            VALUE obj = theap->promoted_objects[i];
            const void *ptr = transient_heap_ptr(obj, TRUE);
            if (ptr) {
                rb_transient_heap_mark(obj, ptr);
            }
        }
    }

    transient_heap_verify(theap);
}

void
rb_transient_heap_finish_marking(void)
{
    ASSERT_vm_locking();
    RUBY_DEBUG_LOG("", 0);

    struct transient_heap* theap = transient_heap_get();

    RUBY_DEBUG_LOG("objects:%d, marked:%d",
                   theap->total_objects,
                   theap->total_marked_objects);
    if (TRANSIENT_HEAP_DEBUG >= 2) transient_heap_dump(theap);

    TH_ASSERT(theap->total_objects >= theap->total_marked_objects);

    TH_ASSERT(theap->status == transient_heap_marking);
    transient_heap_update_status(theap, transient_heap_none);

    if (theap->total_marked_objects > 0) {
        if (TRANSIENT_HEAP_DEBUG >= 1) fprintf(stderr, "-> rb_transient_heap_finish_marking register escape func.\n");
        rb_postponed_job_register_one(0, transient_heap_evacuate, NULL);
    }
    else {
        transient_heap_reset();
    }

    transient_heap_verify(theap);
}
#endif /* USE_TRANSIENT_HEAP */
