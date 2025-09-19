#ifndef INTERNAL_JIT_CONT_H                                /*-*-C-*-vi:se ft=c:*/

#include "iseq.h"

/* cont.c */
void rb_jit_cont_init(void);
void rb_jit_cont_each_iseq(rb_iseq_callback callback, void *data);
void rb_jit_cont_finish(void);

#endif /* INTERNAL_JIT_CONT_H */
