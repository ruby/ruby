/**********************************************************************

  thread.h -

  $Author: matz $
  created at: Tue Jul 10 17:35:43 JST 2012

  Copyright (C) 2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_THREAD_H
#define RUBY_THREAD_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include "ruby/intern.h"

/* flags for rb_nogvl */
#define RB_NOGVL_INTR_FAIL       (0x1)
#define RB_NOGVL_UBF_ASYNC_SAFE  (0x2)

RUBY_SYMBOL_EXPORT_BEGIN

void *rb_thread_call_with_gvl(void *(*func)(void *), void *data1);

void *rb_thread_call_without_gvl(void *(*func)(void *), void *data1,
				 rb_unblock_function_t *ubf, void *data2);
void *rb_thread_call_without_gvl2(void *(*func)(void *), void *data1,
				  rb_unblock_function_t *ubf, void *data2);

/*
 * XXX: unstable/unapproved - out-of-tree code should NOT not depend
 * on this until it hits Ruby 2.6.1
 */
void *rb_nogvl(void *(*func)(void *), void *data1,
               rb_unblock_function_t *ubf, void *data2,
               int flags);

#define RUBY_CALL_WO_GVL_FLAG_SKIP_CHECK_INTS_AFTER 0x01
#define RUBY_CALL_WO_GVL_FLAG_SKIP_CHECK_INTS_

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_THREAD_H */
