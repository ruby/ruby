/**********************************************************************

  yarv.h -

  $Author$
  $Date$

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/


#include <ruby.h>
#include <node.h>
#include "yarvcore.h"

#ifndef _YARV_H_INCLUDED_
#define _YARV_H_INCLUDED_


VALUE yarv_yield(VALUE val);

/* original API */

#if YARVEXT
RUBY_EXTERN int yarvIsWorking;
#define IS_YARV_WORKING() (yarvIsWorking)
#define SET_YARV_START()  (yarvIsWorking = 1)
#define SET_YARV_STOP()   (yarvIsWorking = 0)
#else
#define IS_YARV_WORKING() 1
#define SET_YARV_START()
#define SET_YARV_STOP()
#endif


#if RUBY_VM_THREAD_MODEL == 2

extern rb_thead_t *yarvCurrentThread;
extern rb_vm_t *theYarvVM;

static inline VALUE
yarv_get_current_running_thread_value(void)
{
    return yarvCurrentThread->self;
}

static inline rb_thead_t *
yarv_get_current_running_thread(void)
{
    return yarvCurrentThread;
}

#define GET_VM()     theYarvVM
#define GET_THREAD() yarvCurrentThread

static inline void
rb_thread_set_current_raw(rb_thead_t *th)
{
    yarvCurrentThread = th;
}

static inline void
rb_thread_set_current(rb_thead_t *th)
{
    rb_thread_set_current_raw(th);
    th->vm->running_thread = th;
}

#else
#error "unsupported thread model"
#endif

void rb_vm_change_state();

VALUE th_invoke_yield(rb_thead_t *th, int argc, VALUE *argv);

VALUE th_call0(rb_thead_t *th, VALUE klass, VALUE recv,
	       VALUE id, ID oid, int argc, const VALUE *argv,
	       NODE * body, int nosuper);

VALUE *yarv_svar(int);

VALUE th_call_super(rb_thead_t *th, int argc, const VALUE *argv);

VALUE yarv_backtrace(int lev);

VALUE yarvcore_eval_parsed(NODE *node, VALUE file);

VALUE th_invoke_proc(rb_thead_t *th, rb_proc_t *proc,
		     VALUE self, int argc, VALUE *argv);
VALUE th_make_proc(rb_thead_t *th, rb_control_frame_t *cfp,
		   rb_block_t *block);
VALUE th_make_env_object(rb_thead_t *th, rb_control_frame_t *cfp);
VALUE yarvcore_eval(VALUE self, VALUE str, VALUE file, VALUE line);

int yarv_block_given_p(void);

VALUE yarv_load(char *);
int th_get_sourceline(rb_control_frame_t *);
VALUE th_backtrace(rb_thead_t *, int);
void yarv_bug(void);

#endif
