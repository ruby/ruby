
#ifndef RUBY_EVAL_INTERN_H
#define RUBY_EVAL_INTERN_H

#define PASS_PASSED_BLOCK() \
  (GET_THREAD()->passed_block = \
   GC_GUARDED_PTR_REF((rb_block_t *)GET_THREAD()->cfp->lfp[0]))

#include "ruby/ruby.h"
#include "ruby/node.h"
#include "ruby/util.h"
#include "ruby/signal.h"
#include "vm_core.h"

#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#ifndef EXIT_SUCCESS
#define EXIT_SUCCESS 0
#endif
#ifndef EXIT_FAILURE
#define EXIT_FAILURE 1
#endif

#include <stdio.h>
#include <setjmp.h>

#include "ruby/st.h"
#include "dln.h"

#ifdef __APPLE__
#include <crt_externs.h>
#endif

/* Make alloca work the best possible way.  */
#ifdef __GNUC__
# ifndef atarist
#  ifndef alloca
#   define alloca __builtin_alloca
#  endif
# endif	/* atarist */
#else
# ifdef HAVE_ALLOCA_H
#  include <alloca.h>
# else
#  ifdef _AIX
#pragma alloca
#  else
#   ifndef alloca		/* predefined by HP cc +Olibcalls */
void *alloca();
#   endif
#  endif /* AIX */
# endif	/* HAVE_ALLOCA_H */
#endif /* __GNUC__ */

#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif

#ifndef HAVE_STRING_H
char *strrchr(const char *, const char);
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef __BEOS__
#include <net/socket.h>
#endif

#ifdef __MACOS__
#include "macruby_private.h"
#endif

#ifdef __VMS
#include "vmsruby_private.h"
#endif

#if !defined(setjmp) && defined(HAVE__SETJMP) && !defined(sigsetjmp) && !defined(HAVE_SIGSETJMP)
#define ruby_setjmp(env) _setjmp(env)
#define ruby_longjmp(env,val) _longjmp(env,val)
#else
#define ruby_setjmp(env) setjmp(env)
#define ruby_longjmp(env,val) longjmp(env,val)
#endif

#include <sys/types.h>
#include <signal.h>
#include <errno.h>

#if defined(__VMS)
#pragma nostandard
#endif

#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif

/*
  Solaris sys/select.h switches select to select_large_fdset to support larger
  file descriptors if FD_SETSIZE is larger than 1024 on 32bit environment.
  But Ruby doesn't change FD_SETSIZE because fd_set is allocated dynamically.
  So following definition is required to use select_large_fdset.
*/
#ifdef HAVE_SELECT_LARGE_FDSET
#define select(n, r, w, e, t) select_large_fdset(n, r, w, e, t)
#endif

#ifdef HAVE_SYS_PARAM_H
#include <sys/param.h>
#endif

#include <sys/stat.h>

#define SAVE_ROOT_JMPBUF(th, stmt) do \
  if (ruby_setjmp((th)->root_jmpbuf) == 0) { \
      stmt; \
  } \
  else { \
      rb_fiber_start(); \
  } while (0)

#define TH_PUSH_TAG(th) do { \
  rb_thread_t * const _th = th; \
  struct rb_vm_tag _tag; \
  _tag.tag = 0; \
  _tag.prev = _th->tag; \
  _th->tag = &_tag;

#define TH_POP_TAG() \
  _th->tag = _tag.prev; \
} while (0)

#define TH_POP_TAG2() \
  _th->tag = _tag.prev

#define PUSH_TAG() TH_PUSH_TAG(GET_THREAD())
#define POP_TAG()      TH_POP_TAG()

#define TH_EXEC_TAG() \
  (FLUSH_REGISTER_WINDOWS, ruby_setjmp(_th->tag->buf))

#define EXEC_TAG() \
  TH_EXEC_TAG()

#define TH_JUMP_TAG(th, st) do { \
  ruby_longjmp(th->tag->buf,(st)); \
} while (0)

#define JUMP_TAG(st) TH_JUMP_TAG(GET_THREAD(), st)

#define TAG_RETURN	0x1
#define TAG_BREAK	0x2
#define TAG_NEXT	0x3
#define TAG_RETRY	0x4
#define TAG_REDO	0x5
#define TAG_RAISE	0x6
#define TAG_THROW	0x7
#define TAG_FATAL	0x8
#define TAG_MASK	0xf

#define NEW_THROW_OBJECT(val, pt, st) \
  ((VALUE)NEW_NODE(NODE_LIT, (val), (pt), (st)))
#define SET_THROWOBJ_CATCH_POINT(obj, val) \
  (RNODE((obj))->u2.value = (val))
#define SET_THROWOBJ_STATE(obj, val) \
  (RNODE((obj))->u3.value = (val))

#define GET_THROWOBJ_VAL(obj)         ((VALUE)RNODE((obj))->u1.value)
#define GET_THROWOBJ_CATCH_POINT(obj) ((VALUE*)RNODE((obj))->u2.value)
#define GET_THROWOBJ_STATE(obj)       ((int)RNODE((obj))->u3.value)

#define SCOPE_TEST(f) \
  (ruby_cref()->nd_visi & (f))

#define SCOPE_CHECK(f) \
  (ruby_cref()->nd_visi == (f))

#define SCOPE_SET(f)  \
{ \
  ruby_cref()->nd_visi = (f); \
}

#define CHECK_STACK_OVERFLOW(cfp, margin) do \
  if (((VALUE *)(cfp)->sp) + (margin) + sizeof(rb_control_frame_t) >= ((VALUE *)cfp)) { \
      rb_exc_raise(sysstack_error); \
  } \
while (0)

void rb_thread_cleanup(void);
void rb_thread_wait_other_threads(void);

int thread_set_raised(rb_thread_t *th);
int thread_reset_raised(rb_thread_t *th);

VALUE rb_f_eval(int argc, VALUE *argv, VALUE self);
VALUE rb_make_exception(int argc, VALUE *argv);

NORETURN(void rb_fiber_start(void));

NORETURN(void rb_raise_jump(VALUE));
NORETURN(void rb_print_undef(VALUE, ID, int));
NORETURN(void vm_localjump_error(const char *, VALUE, int));
NORETURN(void vm_jump_tag_but_local_jump(int, VALUE));

NODE *vm_get_cref(rb_thread_t *th, rb_iseq_t *iseq, rb_control_frame_t *cfp);
NODE *vm_cref_push(rb_thread_t *th, VALUE, int);
NODE *vm_set_special_cref(rb_thread_t *th, VALUE *lfp, NODE * cref_stack);
VALUE vm_make_jump_tag_but_local_jump(int state, VALUE val);

static rb_control_frame_t *
vm_get_ruby_level_cfp(rb_thread_t *th, rb_control_frame_t *cfp)
{
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	    return cfp;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

static inline NODE *
ruby_cref()
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = vm_get_ruby_level_cfp(th, th->cfp);
    return vm_get_cref(th, cfp->iseq, cfp);
}

VALUE vm_get_cbase(rb_thread_t *th);
VALUE rb_obj_is_proc(VALUE);
void rb_vm_check_redefinition_opt_method(NODE *node);
VALUE rb_vm_call_cfunc(VALUE recv, VALUE (*func)(VALUE), VALUE arg, rb_block_t *blockptr, VALUE filename);
void rb_thread_terminate_all(void);
void rb_vm_set_eval_stack(rb_thread_t *, VALUE iseq);
VALUE rb_vm_top_self();

#define ruby_cbase() vm_get_cbase(GET_THREAD())

#endif /* RUBY_EVAL_INTERN_H */
