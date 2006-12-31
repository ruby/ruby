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


#if YARV_THREAD_MODEL == 2

extern yarv_thread_t *yarvCurrentThread;
extern yarv_vm_t *theYarvVM;

static inline VALUE
yarv_get_current_running_thread_value(void)
{
    return yarvCurrentThread->self;
}

static inline yarv_thread_t *
yarv_get_current_running_thread(void)
{
    return yarvCurrentThread;
}

#define GET_VM()     theYarvVM
#define GET_THREAD() yarvCurrentThread

static inline void
yarv_set_current_running_thread_raw(yarv_thread_t *th)
{
    yarvCurrentThread = th;
}

static inline void
yarv_set_current_running_thread(yarv_thread_t *th)
{
    yarv_set_current_running_thread_raw(th);
    th->vm->running_thread = th;
}

#else
#error "unsupported thread model"
#endif

void rb_vm_change_state();

VALUE th_invoke_yield(yarv_thread_t *th, int argc, VALUE *argv);

VALUE th_call0(yarv_thread_t *th, VALUE klass, VALUE recv,
	       VALUE id, ID oid, int argc, const VALUE *argv,
	       NODE * body, int nosuper);

VALUE *yarv_svar(int);

VALUE th_call_super(yarv_thread_t *th, int argc, const VALUE *argv);

VALUE yarv_backtrace(int lev);

VALUE yarvcore_eval_parsed(NODE *node, VALUE file);

VALUE th_invoke_proc(yarv_thread_t *th, yarv_proc_t *proc,
		     VALUE self, int argc, VALUE *argv);
VALUE th_make_proc(yarv_thread_t *th, yarv_control_frame_t *cfp,
		   yarv_block_t *block);
VALUE th_make_env_object(yarv_thread_t *th, yarv_control_frame_t *cfp);
VALUE yarvcore_eval(VALUE self, VALUE str, VALUE file, VALUE line);

int yarv_block_given_p(void);

VALUE yarv_load(char *);
VALUE yarv_obj_is_proc(VALUE);
int th_get_sourceline(yarv_control_frame_t *);
VALUE th_backtrace(yarv_thread_t *, int);
void yarv_bug(void);

#endif
