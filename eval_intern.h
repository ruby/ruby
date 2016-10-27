#ifndef RUBY_EVAL_INTERN_H
#define RUBY_EVAL_INTERN_H

#include "ruby/ruby.h"
#include "vm_core.h"

#define PASS_PASSED_BLOCK_TH(th) do { \
    (th)->passed_block = rb_vm_control_frame_block_ptr(th->cfp); \
    (th)->cfp->flag |= VM_FRAME_FLAG_PASSED; \
} while (0)

#define PASS_PASSED_BLOCK() do { \
    rb_thread_t * const __th__ = GET_THREAD(); \
    PASS_PASSED_BLOCK_TH(__th__); \
} while (0)

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

#ifdef __APPLE__
# ifdef HAVE_CRT_EXTERNS_H
#  include <crt_externs.h>
# else
#  include "missing/crt_externs.h"
# endif
#endif

#ifndef HAVE_STRING_H
char *strrchr(const char *, const char);
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_NET_SOCKET_H
#include <net/socket.h>
#endif

#define ruby_setjmp(env) RUBY_SETJMP(env)
#define ruby_longjmp(env,val) RUBY_LONGJMP((env),(val))
#ifdef __CYGWIN__
# ifndef _setjmp
int _setjmp(jmp_buf);
# endif
# ifndef _longjmp
NORETURN(void _longjmp(jmp_buf, int));
# endif
#endif

#include <sys/types.h>
#include <signal.h>
#include <errno.h>

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
#define select(n, r, w, e, t) select_large_fdset((n), (r), (w), (e), (t))
extern int select_large_fdset(int, fd_set *, fd_set *, fd_set *, struct timeval *);
#endif

#ifdef HAVE_SYS_PARAM_H
#include <sys/param.h>
#endif

#include <sys/stat.h>

#ifdef _MSC_VER
#define SAVE_ROOT_JMPBUF_BEFORE_STMT \
    __try {
#define SAVE_ROOT_JMPBUF_AFTER_STMT \
    } \
    __except (GetExceptionCode() == EXCEPTION_STACK_OVERFLOW ? \
	      (rb_thread_raised_set(GET_THREAD(), RAISED_STACKOVERFLOW), \
	       raise(SIGSEGV), \
	       EXCEPTION_EXECUTE_HANDLER) : \
	      EXCEPTION_CONTINUE_SEARCH) { \
	/* never reaches here */ \
    }
#elif defined(__MINGW32__)
LONG WINAPI rb_w32_stack_overflow_handler(struct _EXCEPTION_POINTERS *);
#define SAVE_ROOT_JMPBUF_BEFORE_STMT \
    do { \
	PVOID _handler = AddVectoredExceptionHandler(1, rb_w32_stack_overflow_handler);

#define SAVE_ROOT_JMPBUF_AFTER_STMT \
	RemoveVectoredExceptionHandler(_handler); \
    } while (0);
#else
#define SAVE_ROOT_JMPBUF_BEFORE_STMT
#define SAVE_ROOT_JMPBUF_AFTER_STMT
#endif

#define SAVE_ROOT_JMPBUF(th, stmt) do \
  if (ruby_setjmp((th)->root_jmpbuf) == 0) { \
      SAVE_ROOT_JMPBUF_BEFORE_STMT \
      stmt; \
      SAVE_ROOT_JMPBUF_AFTER_STMT \
  } \
  else { \
      rb_fiber_start(); \
  } while (0)

#define TH_PUSH_TAG(th) do { \
  rb_thread_t * const _th = (th); \
  struct rb_vm_tag _tag; \
  _tag.tag = Qundef; \
  _tag.prev = _th->tag;

#define TH_POP_TAG() \
  _th->tag = _tag.prev; \
} while (0)

#define TH_TMPPOP_TAG() \
  _th->tag = _tag.prev

#define TH_REPUSH_TAG() (void)(_th->tag = &_tag)

#define PUSH_TAG() TH_PUSH_TAG(GET_THREAD())
#define POP_TAG()      TH_POP_TAG()

#if defined __GNUC__ && __GNUC__ == 4 && (__GNUC_MINOR__ >= 6 && __GNUC_MINOR__ <= 8)
# define VAR_FROM_MEMORY(var) __extension__(*(__typeof__(var) volatile *)&(var))
# define VAR_INITIALIZED(var) ((var) = VAR_FROM_MEMORY(var))
#else
# define VAR_FROM_MEMORY(var) (var)
# define VAR_INITIALIZED(var) ((void)&(var))
#endif

/* clear th->state, and return the value */
static inline int
rb_threadptr_tag_state(rb_thread_t *th)
{
    int state = th->state;
    th->state = 0;
    return state;
}

NORETURN(static inline void rb_threadptr_tag_jump(rb_thread_t *, int));
static inline void
rb_threadptr_tag_jump(rb_thread_t *th, int st)
{
    th->state = st;
    ruby_longjmp(th->tag->buf, 1);
}

/*
  setjmp() in assignment expression rhs is undefined behavior
  [ISO/IEC 9899:1999] 7.13.1.1
*/
#define TH_EXEC_TAG() \
    (ruby_setjmp(_tag.buf) ? rb_threadptr_tag_state(VAR_FROM_MEMORY(_th)) : (TH_REPUSH_TAG(), 0))

#define EXEC_TAG() \
  TH_EXEC_TAG()

#define TH_JUMP_TAG(th, st) rb_threadptr_tag_jump(th, st)

#define JUMP_TAG(st) TH_JUMP_TAG(GET_THREAD(), (st))

#define INTERNAL_EXCEPTION_P(exc) FIXNUM_P(exc)

enum ruby_tag_type {
    RUBY_TAG_RETURN	= 0x1,
    RUBY_TAG_BREAK	= 0x2,
    RUBY_TAG_NEXT	= 0x3,
    RUBY_TAG_RETRY	= 0x4,
    RUBY_TAG_REDO	= 0x5,
    RUBY_TAG_RAISE	= 0x6,
    RUBY_TAG_THROW	= 0x7,
    RUBY_TAG_FATAL	= 0x8,
    RUBY_TAG_MASK	= 0xf
};
#define TAG_RETURN	RUBY_TAG_RETURN
#define TAG_BREAK	RUBY_TAG_BREAK
#define TAG_NEXT	RUBY_TAG_NEXT
#define TAG_RETRY	RUBY_TAG_RETRY
#define TAG_REDO	RUBY_TAG_REDO
#define TAG_RAISE	RUBY_TAG_RAISE
#define TAG_THROW	RUBY_TAG_THROW
#define TAG_FATAL	RUBY_TAG_FATAL
#define TAG_MASK	RUBY_TAG_MASK

#define NEW_THROW_OBJECT(val, pt, st) \
  ((VALUE)rb_node_newnode(NODE_LIT, (VALUE)(val), (VALUE)(pt), (VALUE)(st)))
#define SET_THROWOBJ_CATCH_POINT(obj, val) \
  (RNODE((obj))->u2.value = (val))
#define SET_THROWOBJ_STATE(obj, val) \
  (RNODE((obj))->u3.value = (val))

#define GET_THROWOBJ_VAL(obj)         ((VALUE)RNODE((obj))->u1.value)
#define GET_THROWOBJ_CATCH_POINT(obj) ((rb_control_frame_t*)RNODE((obj))->u2.value)
#define GET_THROWOBJ_STATE(obj)       ((int)RNODE((obj))->u3.value)

#define SCOPE_TEST(f)  (rb_vm_cref()->nd_visi & (f))
#define SCOPE_CHECK(f) (rb_vm_cref()->nd_visi == (f))
#define SCOPE_SET(f)   (rb_vm_cref()->nd_visi = (f))

void rb_thread_cleanup(void);
void rb_thread_wait_other_threads(void);

enum {
    RAISED_EXCEPTION = 1,
    RAISED_STACKOVERFLOW = 2,
    RAISED_NOMEMORY = 4
};
int rb_threadptr_set_raised(rb_thread_t *th);
int rb_threadptr_reset_raised(rb_thread_t *th);
#define rb_thread_raised_set(th, f)   ((th)->raised_flag |= (f))
#define rb_thread_raised_reset(th, f) ((th)->raised_flag &= ~(f))
#define rb_thread_raised_p(th, f)     (((th)->raised_flag & (f)) != 0)
#define rb_thread_raised_clear(th)    ((th)->raised_flag = 0)

VALUE rb_f_eval(int argc, const VALUE *argv, VALUE self);
VALUE rb_make_exception(int argc, const VALUE *argv);

NORETURN(void rb_method_name_error(VALUE, VALUE));

NORETURN(void rb_fiber_start(void));

NORETURN(void rb_print_undef(VALUE, ID, int));
NORETURN(void rb_print_undef_str(VALUE, VALUE));
NORETURN(void rb_print_inaccessible(VALUE, ID, int));
NORETURN(void rb_vm_localjump_error(const char *,VALUE, int));
NORETURN(void rb_vm_jump_tag_but_local_jump(int));
NORETURN(void rb_raise_method_missing(rb_thread_t *th, int argc, const VALUE *argv,
				      VALUE obj, int call_status));

VALUE rb_vm_make_jump_tag_but_local_jump(int state, VALUE val);
NODE *rb_vm_cref(void);
VALUE rb_vm_call_cfunc(VALUE recv, VALUE (*func)(VALUE), VALUE arg, const rb_block_t *blockptr, VALUE filename);
void rb_vm_set_progname(VALUE filename);
void rb_thread_terminate_all(void);
VALUE rb_vm_top_self();
VALUE rb_vm_cbase(void);

#ifndef CharNext		/* defined as CharNext[AW] on Windows. */
# ifdef HAVE_MBLEN
#  define CharNext(p) ((p) + mblen((p), RUBY_MBCHAR_MAXSIZE))
# else
#  define CharNext(p) ((p) + 1)
# endif
#endif

#if defined DOSISH || defined __CYGWIN__
static inline void
translit_char(char *p, int from, int to)
{
    while (*p) {
	if ((unsigned char)*p == from)
	    *p = to;
	p = CharNext(p);
    }
}
#endif

#endif /* RUBY_EVAL_INTERN_H */
