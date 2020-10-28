#ifndef RUBY_THREAD_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_THREAD_H 1
/**
 * @file
 * @author     $Author: matz $
 * @date       Tue Jul 10 17:35:43 JST 2012
 * @copyright  Copyright (C) 2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/intern.h"
#include "ruby/internal/dllexport.h"

/* flags for rb_nogvl */
#define RB_NOGVL_INTR_FAIL       (0x1)
#define RB_NOGVL_UBF_ASYNC_SAFE  (0x2)

RBIMPL_SYMBOL_EXPORT_BEGIN()

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

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_THREAD_H */
