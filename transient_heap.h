/**********************************************************************

  transient_heap.h - declarations of transient_heap related APIs.

  Copyright (C) 2018 Koichi Sasada

**********************************************************************/

#ifndef RUBY_TRANSIENT_HEAP_H
#define RUBY_TRANSIENT_HEAP_H

#include "internal.h"

#if USE_TRANSIENT_HEAP

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
        int16_t size; /* sizeof(block) = TRANSIENT_HEAP_BLOCK_SIZE - sizeof(struct transient_heap_block_header) */
        int16_t index;
        int16_t last_marked_index;
        int16_t objects;
        struct transient_heap_block *next_block;
    } info;
    char buff[TRANSIENT_HEAP_BLOCK_SIZE - sizeof(struct transient_heap_block_header)];
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

/* public API */

/* Allocate req_size bytes from transient_heap.
   Allocated memories are free-ed when next GC
   if this memory is not marked by `rb_transient_heap_mark()`.
 */
void *rb_transient_heap_alloc(VALUE obj, size_t req_size);

/* If `obj` uses a memory pointed by `ptr` from transient_heap,
   you need to call `rb_transient_heap_mark(obj, ptr)`
   to assert liveness of `obj` (and ptr). */
void  rb_transient_heap_mark(VALUE obj, const void *ptr);

/* used by gc.c */
void rb_transient_heap_promote(VALUE obj);
void rb_transient_heap_start_marking(int full_marking);
void rb_transient_heap_finish_marking(void);
void rb_transient_heap_update_references(void);

/* for debug API */
void rb_transient_heap_dump(void);
void rb_transient_heap_verify(void);
int  rb_transient_heap_managed_ptr_p(const void *ptr);

/* evacuate functions for each type */
void rb_ary_transient_heap_evacuate(VALUE ary, int promote);
void rb_obj_transient_heap_evacuate(VALUE obj, int promote);
void rb_hash_transient_heap_evacuate(VALUE hash, int promote);
void rb_struct_transient_heap_evacuate(VALUE st, int promote);

#else /* USE_TRANSIENT_HEAP */

#define rb_transient_heap_alloc(o, s) NULL
#define rb_transient_heap_verify() ((void)0)
#define rb_transient_heap_promote(obj) ((void)0)
#define rb_transient_heap_start_marking(full_marking) ((void)0)
#define rb_transient_heap_update_references() ((void)0)
#define rb_transient_heap_finish_marking() ((void)0)
#define rb_transient_heap_mark(obj, ptr) ((void)0)

#define rb_ary_transient_heap_evacuate(x, y) ((void)0)
#define rb_obj_transient_heap_evacuate(x, y) ((void)0)
#define rb_hash_transient_heap_evacuate(x, y) ((void)0)
#define rb_struct_transient_heap_evacuate(x, y) ((void)0)

#endif /* USE_TRANSIENT_HEAP */
#endif
