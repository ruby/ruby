#ifndef INTERNAL_PROC_H /* -*- C -*- */
#define INTERNAL_PROC_H
/**
 * @file
 * @brief      Internal header for Proc.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/ruby.h"          /* for rb_block_call_func_t */
#include "ruby/st.h"            /* for st_index_t */
struct rb_block;                /* in vm_core.h */
struct rb_iseq_struct;          /* in vm_core.h */

/* proc.c */
VALUE rb_proc_location(VALUE self);
st_index_t rb_hash_proc(st_index_t hash, VALUE proc);
int rb_block_arity(void);
int rb_block_min_max_arity(int *max);
VALUE rb_func_lambda_new(rb_block_call_func_t func, VALUE val, int min_argc, int max_argc);
VALUE rb_block_to_s(VALUE self, const struct rb_block *block, const char *additional_info);

MJIT_SYMBOL_EXPORT_BEGIN
VALUE rb_func_proc_new(rb_block_call_func_t func, VALUE val);
VALUE rb_iseq_location(const struct rb_iseq_struct *iseq);
VALUE rb_sym_to_proc(VALUE sym);
MJIT_SYMBOL_EXPORT_END

#endif /* INTERNAL_PROC_H */
