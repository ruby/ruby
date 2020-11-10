#ifndef RUBY_EVAL_INTERN_H
#define RUBY_EVAL_INTERN_H

#include "ruby/ruby.h"
#include "vm_core.h"

static inline void
vm_passed_block_handler_set(rb_execution_context_t *ec, VALUE block_handler)
{
    vm_block_handler_verify(block_handler);
    ec->passed_block_handler = block_handler;
}

static inline void
pass_passed_block_handler(rb_execution_context_t *ec)
{
    VALUE block_handler = rb_vm_frame_block_handler(ec->cfp);
    vm_passed_block_handler_set(ec, block_handler);
    VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_PASSED);
}

#define PASS_PASSED_BLOCK_HANDLER_EC(ec) pass_passed_block_handler(ec)
#define PASS_PASSED_BLOCK_HANDLER() pass_passed_block_handler(GET_EC())

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
	      (rb_ec_raised_set(GET_EC(), RAISED_STACKOVERFLOW), \
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

#define EC_PUSH_TAG(ec) do { \
  rb_execution_context_t * const _ec = (ec); \
  struct rb_vm_tag _tag; \
  _tag.state = TAG_NONE; \
  _tag.tag = Qundef; \
  _tag.prev = _ec->tag; \
  _tag.lock_rec = rb_ec_vm_lock_rec(_ec); \

#define EC_POP_TAG() \
  _ec->tag = _tag.prev; \
} while (0)

#define EC_TMPPOP_TAG() \
  _ec->tag = _tag.prev

#define EC_REPUSH_TAG() (void)(_ec->tag = &_tag)

#if defined __GNUC__ && __GNUC__ == 4 && (__GNUC_MINOR__ >= 6 && __GNUC_MINOR__ <= 8) || __clang__
/* This macro prevents GCC 4.6--4.8 from emitting maybe-uninitialized warnings.
 * This macro also prevents Clang from dumping core in EC_EXEC_TAG().
 * (I confirmed Clang 4.0.1 and 5.0.0.)
 */
# define VAR_FROM_MEMORY(var) __extension__(*(__typeof__(var) volatile *)&(var))
# define VAR_INITIALIZED(var) ((var) = VAR_FROM_MEMORY(var))
# define VAR_NOCLOBBERED(var) volatile var
#else
# define VAR_FROM_MEMORY(var) (var)
# define VAR_INITIALIZED(var) ((void)&(var))
# define VAR_NOCLOBBERED(var) var
#endif

static inline void
rb_ec_vm_lock_rec_check(const rb_execution_context_t *ec, unsigned int recorded_lock_rec)
{
    unsigned int current_lock_rec = rb_ec_vm_lock_rec(ec);
    if (current_lock_rec != recorded_lock_rec) {
        rb_ec_vm_lock_rec_release(ec, recorded_lock_rec, current_lock_rec);
    }
}

/* clear ec->tag->state, and return the value */
static inline int
rb_ec_tag_state(const rb_execution_context_t *ec)
{
    struct rb_vm_tag *tag = ec->tag;
    enum ruby_tag_type state = tag->state;
    tag->state = TAG_NONE;
    rb_ec_vm_lock_rec_check(ec, tag->lock_rec);
    return state;
}

NORETURN(static inline void rb_ec_tag_jump(const rb_execution_context_t *ec, enum ruby_tag_type st));
static inline void
rb_ec_tag_jump(const rb_execution_context_t *ec, enum ruby_tag_type st)
{
    ec->tag->state = st;
    ruby_longjmp(ec->tag->buf, 1);
}

/*
  setjmp() in assignment expression rhs is undefined behavior
  [ISO/IEC 9899:1999] 7.13.1.1
*/
#define EC_EXEC_TAG() \
    (ruby_setjmp(_tag.buf) ? rb_ec_tag_state(VAR_FROM_MEMORY(_ec)) : (EC_REPUSH_TAG(), 0))

#define EC_JUMP_TAG(ec, st) rb_ec_tag_jump(ec, st)

#define INTERNAL_EXCEPTION_P(exc) FIXNUM_P(exc)

/* CREF operators */

#define CREF_FL_PUSHED_BY_EVAL IMEMO_FL_USER1
#define CREF_FL_OMOD_SHARED    IMEMO_FL_USER2

static inline VALUE
CREF_CLASS(const rb_cref_t *cref)
{
    return cref->klass;
}

static inline rb_cref_t *
CREF_NEXT(const rb_cref_t *cref)
{
    return cref->next;
}

static inline const rb_scope_visibility_t *
CREF_SCOPE_VISI(const rb_cref_t *cref)
{
    return &cref->scope_visi;
}

static inline VALUE
CREF_REFINEMENTS(const rb_cref_t *cref)
{
    return cref->refinements;
}

static inline void
CREF_REFINEMENTS_SET(rb_cref_t *cref, VALUE refs)
{
    RB_OBJ_WRITE(cref, &cref->refinements, refs);
}

static inline int
CREF_PUSHED_BY_EVAL(const rb_cref_t *cref)
{
    return cref->flags & CREF_FL_PUSHED_BY_EVAL;
}

static inline void
CREF_PUSHED_BY_EVAL_SET(rb_cref_t *cref)
{
    cref->flags |= CREF_FL_PUSHED_BY_EVAL;
}

static inline int
CREF_OMOD_SHARED(const rb_cref_t *cref)
{
    return cref->flags & CREF_FL_OMOD_SHARED;
}

static inline void
CREF_OMOD_SHARED_SET(rb_cref_t *cref)
{
    cref->flags |= CREF_FL_OMOD_SHARED;
}

static inline void
CREF_OMOD_SHARED_UNSET(rb_cref_t *cref)
{
    cref->flags &= ~CREF_FL_OMOD_SHARED;
}

enum {
    RAISED_EXCEPTION = 1,
    RAISED_STACKOVERFLOW = 2,
    RAISED_NOMEMORY = 4
};
#define rb_ec_raised_set(ec, f)   ((ec)->raised_flag |= (f))
#define rb_ec_raised_reset(ec, f) ((ec)->raised_flag &= ~(f))
#define rb_ec_raised_p(ec, f)    (((ec)->raised_flag & (f)) != 0)
#define rb_ec_raised_clear(ec)    ((ec)->raised_flag = 0)
int rb_ec_set_raised(rb_execution_context_t *ec);
int rb_ec_reset_raised(rb_execution_context_t *ec);
int rb_ec_stack_check(rb_execution_context_t *ec);

VALUE rb_f_eval(int argc, const VALUE *argv, VALUE self);
VALUE rb_make_exception(int argc, const VALUE *argv);

NORETURN(void rb_method_name_error(VALUE, VALUE));

NORETURN(void rb_fiber_start(void));

NORETURN(void rb_print_undef(VALUE, ID, rb_method_visibility_t));
NORETURN(void rb_print_undef_str(VALUE, VALUE));
NORETURN(void rb_print_inaccessible(VALUE, ID, rb_method_visibility_t));
NORETURN(void rb_vm_localjump_error(const char *,VALUE, int));
NORETURN(void rb_vm_jump_tag_but_local_jump(int));

VALUE rb_vm_make_jump_tag_but_local_jump(int state, VALUE val);
rb_cref_t *rb_vm_cref(void);
rb_cref_t *rb_vm_cref_replace_with_duplicated_cref(void);
VALUE rb_vm_call_cfunc(VALUE recv, VALUE (*func)(VALUE), VALUE arg, VALUE block_handler, VALUE filename);
void rb_vm_set_progname(VALUE filename);
VALUE rb_vm_cbase(void);

/* vm_backtrace.c */
VALUE rb_ec_backtrace_object(const rb_execution_context_t *ec);
VALUE rb_ec_backtrace_str_ary(const rb_execution_context_t *ec, long lev, long n);
VALUE rb_ec_backtrace_location_ary(const rb_execution_context_t *ec, long lev, long n, bool skip_internal);

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
