#ifndef RUBY_TRANSIENT_HEAP_H
#define RUBY_TRANSIENT_HEAP_H
/**********************************************************************

  transient_heap.h - declarations of transient_heap related APIs.

  Copyright (C) 2018 Koichi Sasada

**********************************************************************/

#include "internal.h"

#if USE_TRANSIENT_HEAP

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
