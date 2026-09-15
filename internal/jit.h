#ifndef INTERNAL_JIT_H                                     /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_JIT_H

#include "iseq.h"

typedef void (*rb_iseq_callback)(const rb_iseq_t *, void *);

/* cont.c */
void rb_jit_cont_init(void);
void rb_jit_cont_each_iseq(rb_iseq_callback callback, void *data);
void rb_jit_cont_finish(void);

/* jit.c */
void rb_jit_for_each_iseq(rb_iseq_callback callback, void *data);

#endif /* INTERNAL_JIT_H */
