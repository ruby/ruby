/**********************************************************************

  transient_heap.h - declarations of transient_heap related APIs.

  Copyright (C) 2018 Koichi Sasada

**********************************************************************/

#ifndef RUBY_TRANSIENT_HEAP_H
#define RUBY_TRANSIENT_HEAP_H

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

/* for debug API */
void rb_transient_heap_dump(void);
void rb_transient_heap_verify(void);
int  rb_transient_heap_managed_ptr_p(const void *ptr);

/* evacuate functions */
void rb_ary_transient_heap_evacuate(VALUE ary, int promote);
void rb_obj_transient_heap_evacuate(VALUE ary, int promote);

#endif
