
#ifndef EVAL_INTERN_H_INCLUDED
#define EVAL_INTERN_H_INCLUDED

#define PASS_PASSED_BLOCK() \
  (GET_THREAD()->passed_block = \
   GC_GUARDED_PTR_REF((yarv_block_t *)GET_THREAD()->cfp->lfp[0]))


#define UNSUPPORTED(func) \
{ \
  int *a = 0; \
  fprintf(stderr, "%s", "-- unsupported: " #func "\n"); fflush(stderr); \
  *a = 0; \
  rb_bug("unsupported: " #func); \
}

#include "ruby.h"
#include "node.h"
#include "util.h"
#include "rubysig.h"
#include "yarv.h"

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

#include "st.h"
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
char *strrchr _((const char *, const char));
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

#ifdef USE_CONTEXT

NORETURN(static void rb_jump_context(rb_jmpbuf_t, int));
static inline void
rb_jump_context(rb_jmpbuf_t env, int val)
{
    env->status = val;
    setcontext(&env->context);
    abort();			/* ensure noreturn */
}

/*
 * FUNCTION_CALL_MAY_RETURN_TWICE is a magic for getcontext, gcc,
 * IA64 register stack and SPARC register window combination problem.
 *
 * Assume following code sequence.
 * 
 * 1. set a register in the register stack/window such as r32/l0.
 * 2. call getcontext.
 * 3. use the register.
 * 4. update the register for other use.
 * 5. call setcontext indirectly (or directly).
 *
 * This code should be run as 1->2->3->4->5->3->4.
 * But after second getcontext return (second 3),
 * the register is broken (updated).
 * It's because getcontext/setcontext doesn't preserve the content of the
 * register stack/window.
 *
 * setjmp also doesn't preserve the content of the register stack/window.
 * But it has not the problem because gcc knows setjmp may return twice.
 * gcc detects setjmp and generates setjmp safe code.
 *
 * So setjmp call before getcontext call makes the code somewhat safe.
 * It fix the problem on IA64.
 * It is not required that setjmp is called at run time, since the problem is
 * register usage.
 *
 * Since the magic setjmp is not enough for SPARC,
 * inline asm is used to prohibit registers in register windows.
 */
#if defined (__GNUC__) && (defined(sparc) || defined(__sparc__))
#define FUNCTION_CALL_MAY_RETURN_TWICE \
 ({ __asm__ volatile ("" : : :  \
    "%o0", "%o1", "%o2", "%o3", "%o4", "%o5", "%o7", \
    "%l0", "%l1", "%l2", "%l3", "%l4", "%l5", "%l6", "%l7", \
    "%i0", "%i1", "%i2", "%i3", "%i4", "%i5", "%i7"); })
#else
extern jmp_buf function_call_may_return_twice_jmp_buf;
extern int function_call_may_return_twice_false;
#define FUNCTION_CALL_MAY_RETURN_TWICE \
  (function_call_may_return_twice_false ? \
   setjmp(function_call_may_return_twice_jmp_buf) : \
   0)
#endif
#define ruby_longjmp(env, val) rb_jump_context(env, val)
#define ruby_setjmp(j) ((j)->status = 0, \
    FUNCTION_CALL_MAY_RETURN_TWICE, \
    getcontext(&(j)->context), \
    (j)->status)
#else
#if !defined(setjmp) && defined(HAVE__SETJMP)
#define ruby_setjmp(env) _setjmp(env)
#define ruby_longjmp(env,val) _longjmp(env,val)
#else
#define ruby_setjmp(env) setjmp(env)
#define ruby_longjmp(env,val) longjmp(env,val)
#endif
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

#define TH_PUSH_TAG(th) do { \
  yarv_thread_t * const _th = th; \
  struct yarv_tag _tag; \
  _tag.tag = 0; \
  _tag.prev = _th->tag; \
  _th->tag = &_tag;

#define TH_POP_TAG() \
  _th->tag = _tag.prev; \
} while (0)

#define TH_POP_TAG2() \
  _th->tag = _tag.prev

#define PUSH_TAG(ptag) TH_PUSH_TAG(GET_THREAD())
#define POP_TAG()      TH_POP_TAG()
#define POP_TAG_INIT() } while (0)

#define PUSH_THREAD_TAG() \
  PUSH_TAG(PROT_THREAD)

#define POP_THREAD_TAG()  \
  POP_TAG()

#define PROT_NONE   Qfalse	/* 0 */
#define PROT_THREAD Qtrue	/* 2 */
#define PROT_FUNC   INT2FIX(0)	/* 1 */
#define PROT_LOOP   INT2FIX(1)	/* 3 */
#define PROT_LAMBDA INT2FIX(2)	/* 5 */
#define PROT_YIELD  INT2FIX(3)	/* 7 */
#define PROT_TOP    INT2FIX(4)	/* 9 */

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
#define TAG_CONTCALL	0x9
#define TAG_THREAD	0xa
#define TAG_MASK	0xf

#define SCOPE_TEST(f) \
  (ruby_cref()->nd_visi & (f))

#define SCOPE_CHECK(f) \
  (ruby_cref()->nd_visi == (f))

#define SCOPE_SET(f)  \
{ \
  ruby_cref()->nd_visi = (f); \
}

struct ruby_env {
    struct ruby_env *prev;
    struct FRAME *frame;
    struct SCOPE *scope;
    struct BLOCK *block;
    struct iter *iter;
    struct tag *tag;
    NODE *cref;
};

typedef struct thread *rb_thread_t;

extern VALUE rb_cBinding;
extern VALUE rb_eThreadError;
extern VALUE rb_eLocalJumpError;
extern VALUE rb_eSysStackError;
extern VALUE exception_error;
extern VALUE sysstack_error;


void rb_thread_cleanup _((void));
void rb_thread_wait_other_threads _((void));

int thread_set_raised(yarv_thread_t *th);
int thread_reset_raised(yarv_thread_t *th);

VALUE rb_f_eval(int argc, VALUE *argv, VALUE self);
VALUE rb_make_exception _((int argc, VALUE *argv));

NORETURN(void rb_raise_jump _((VALUE)));
NORETURN(void print_undef _((VALUE, ID)));
NORETURN(void th_localjump_error(const char *, VALUE, int));
NORETURN(void th_jump_tag_but_local_jump(int, VALUE));

rb_thread_t rb_vm_curr_thread();
VALUE th_compile(yarv_thread_t *th, VALUE str, VALUE file, VALUE line);

NODE *th_get_cref(yarv_thread_t *th, yarv_iseq_t *iseq, yarv_control_frame_t *cfp);
NODE *th_cref_push(yarv_thread_t *th, VALUE, int);
NODE *th_set_special_cref(yarv_thread_t *th, VALUE *lfp, NODE * cref_stack);

static yarv_control_frame_t *
th_get_ruby_level_cfp(yarv_thread_t *th, yarv_control_frame_t *cfp)
{
    yarv_iseq_t *iseq = 0;
    while (!YARV_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	if (YARV_NORMAL_ISEQ_P(cfp->iseq)) {
	    iseq = cfp->iseq;
	    break;
	}
	cfp = YARV_PREVIOUS_CONTROL_FRAME(cfp);
    }
    if (!iseq) {
	return 0;
    }
    return cfp;
}

static NODE *
ruby_cref()
{
    yarv_thread_t *th = GET_THREAD();
    yarv_control_frame_t *cfp = th_get_ruby_level_cfp(th, th->cfp);
    return th_get_cref(th, cfp->iseq, cfp);
}

VALUE th_get_cbase(yarv_thread_t *th);

#define ruby_cbase() th_get_cbase(GET_THREAD())

#endif /* EVAL_INTERN_H_INCLUDED */
