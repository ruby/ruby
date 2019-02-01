/**********************************************************************

  cont.c -

  $Author$
  created at: Thu May 23 09:03:43 2007

  Copyright (C) 2007 Koichi Sasada

**********************************************************************/

#include "internal.h"
#include "vm_core.h"
#include "gc.h"
#include "eval_intern.h"

/* FIBER_USE_NATIVE enables Fiber performance improvement using system
 * dependent method such as make/setcontext on POSIX system or
 * CreateFiber() API on Windows.
 * This hack make Fiber context switch faster (x2 or more).
 * However, it decrease maximum number of Fiber.  For example, on the
 * 32bit POSIX OS, ten or twenty thousands Fiber can be created.
 *
 * Details is reported in the paper "A Fast Fiber Implementation for Ruby 1.9"
 * in Proc. of 51th Programming Symposium, pp.21--28 (2010) (in Japanese).
 */

#if !defined(FIBER_USE_NATIVE)
# if defined(HAVE_GETCONTEXT) && defined(HAVE_SETCONTEXT)
#   if 0
#   elif defined(__NetBSD__)
/* On our experience, NetBSD doesn't support using setcontext() and pthread
 * simultaneously.  This is because pthread_self(), TLS and other information
 * are represented by stack pointer (higher bits of stack pointer).
 * TODO: check such constraint on configure.
 */
#     define FIBER_USE_NATIVE 0
#   elif defined(__sun)
/* On Solaris because resuming any Fiber caused SEGV, for some reason.
 */
#     define FIBER_USE_NATIVE 0
#   elif defined(__ia64)
/* At least, Linux/ia64's getcontext(3) doesn't save register window.
 */
#     define FIBER_USE_NATIVE 0
#   elif defined(__GNU__)
/* GNU/Hurd doesn't fully support getcontext, setcontext, makecontext
 * and swapcontext functions. Disabling their usage till support is
 * implemented. More info at
 * http://darnassus.sceen.net/~hurd-web/open_issues/glibc/#getcontext
 */
#     define FIBER_USE_NATIVE 0
#   else
#     define FIBER_USE_NATIVE 1
#   endif
# elif defined(_WIN32)
#  define FIBER_USE_NATIVE 1
# endif
#endif
#if !defined(FIBER_USE_NATIVE)
#define FIBER_USE_NATIVE 0
#endif

#if FIBER_USE_NATIVE
#ifndef _WIN32
#include <unistd.h>
#include <sys/mman.h>
#include <ucontext.h>
#endif
#define RB_PAGE_SIZE (pagesize)
#define RB_PAGE_MASK (~(RB_PAGE_SIZE - 1))
static long pagesize;
#endif /*FIBER_USE_NATIVE*/

#define CAPTURE_JUST_VALID_VM_STACK 1

enum context_type {
    CONTINUATION_CONTEXT = 0,
    FIBER_CONTEXT = 1,
    ROOT_FIBER_CONTEXT = 2
};

typedef struct rb_context_struct {
    enum context_type type;
    int argc;
    VALUE self;
    VALUE value;
    VALUE *vm_stack;
#ifdef CAPTURE_JUST_VALID_VM_STACK
    size_t vm_stack_slen;  /* length of stack (head of th->stack) */
    size_t vm_stack_clen;  /* length of control frames (tail of th->stack) */
#endif
    struct {
	VALUE *stack;
	VALUE *stack_src;
	size_t stack_size;
#ifdef __ia64
	VALUE *register_stack;
	VALUE *register_stack_src;
	int register_stack_size;
#endif
    } machine;
    rb_thread_t saved_thread; /* selected properties of GET_THREAD() (see cont_save_thread) */
    rb_jmpbuf_t jmpbuf;
    rb_ensure_entry_t *ensure_array;
    rb_ensure_list_t *ensure_list;
} rb_context_t;

enum fiber_status {
    CREATED,
    RUNNING,
    TERMINATED
};

#if FIBER_USE_NATIVE && !defined(_WIN32)
#define MAX_MACHINE_STACK_CACHE  10
static int machine_stack_cache_index = 0;
typedef struct machine_stack_cache_struct {
    void *ptr;
    size_t size;
} machine_stack_cache_t;
static machine_stack_cache_t machine_stack_cache[MAX_MACHINE_STACK_CACHE];
static machine_stack_cache_t terminated_machine_stack;
#endif

struct rb_fiber_struct {
    rb_context_t cont;
    struct rb_fiber_struct *prev;
    enum fiber_status status;
    /* If a fiber invokes "transfer",
     * then this fiber can't "resume" any more after that.
     * You shouldn't mix "transfer" and "resume".
     */
    int transferred;

#if FIBER_USE_NATIVE
#ifdef _WIN32
    void *fib_handle;
#else
    ucontext_t context;
    /* Because context.uc_stack.ss_sp and context.uc_stack.ss_size
     * are not necessarily valid after makecontext() or swapcontext(),
     * they are saved in these variables for later use.
     */
    void *ss_sp;
    size_t ss_size;
#endif
#endif
};

static const rb_data_type_t cont_data_type, fiber_data_type;
static VALUE rb_cContinuation;
static VALUE rb_cFiber;
static VALUE rb_eFiberError;

#define GetContPtr(obj, ptr)  \
    TypedData_Get_Struct((obj), rb_context_t, &cont_data_type, (ptr))

#define GetFiberPtr(obj, ptr)  do {\
    TypedData_Get_Struct((obj), rb_fiber_t, &fiber_data_type, (ptr)); \
    if (!(ptr)) rb_raise(rb_eFiberError, "uninitialized fiber"); \
} while (0)

NOINLINE(static VALUE cont_capture(volatile int *volatile stat));

#define THREAD_MUST_BE_RUNNING(th) do { \
	if (!(th)->tag) rb_raise(rb_eThreadError, "not running thread");	\
    } while (0)

static void
cont_mark(void *ptr)
{
    RUBY_MARK_ENTER("cont");
    if (ptr) {
	rb_context_t *cont = ptr;
	rb_gc_mark(cont->value);

	rb_thread_mark(&cont->saved_thread);
	rb_gc_mark(cont->saved_thread.self);

	if (cont->vm_stack) {
#ifdef CAPTURE_JUST_VALID_VM_STACK
	    rb_gc_mark_locations(cont->vm_stack,
				 cont->vm_stack + cont->vm_stack_slen + cont->vm_stack_clen);
#else
	    rb_gc_mark_locations(cont->vm_stack,
				 cont->vm_stack, cont->saved_thread.stack_size);
#endif
	}

	if (cont->machine.stack) {
	    if (cont->type == CONTINUATION_CONTEXT) {
		/* cont */
		rb_gc_mark_locations(cont->machine.stack,
				     cont->machine.stack + cont->machine.stack_size);
            }
            else {
		/* fiber */
		rb_thread_t *th;
                rb_fiber_t *fib = (rb_fiber_t*)cont;
		GetThreadPtr(cont->saved_thread.self, th);
		if ((th->fiber != fib) && fib->status == RUNNING) {
		    rb_gc_mark_locations(cont->machine.stack,
					 cont->machine.stack + cont->machine.stack_size);
		}
	    }
	}
#ifdef __ia64
	if (cont->machine.register_stack) {
	    rb_gc_mark_locations(cont->machine.register_stack,
				 cont->machine.register_stack + cont->machine.register_stack_size);
	}
#endif
    }
    RUBY_MARK_LEAVE("cont");
}

static void
cont_free(void *ptr)
{
    RUBY_FREE_ENTER("cont");
    if (ptr) {
	rb_context_t *cont = ptr;
	RUBY_FREE_UNLESS_NULL(cont->saved_thread.stack);
#if FIBER_USE_NATIVE
	if (cont->type == CONTINUATION_CONTEXT) {
	    /* cont */
	    ruby_xfree(cont->ensure_array);
	    RUBY_FREE_UNLESS_NULL(cont->machine.stack);
	}
	else {
	    /* fiber */
	    rb_fiber_t *fib = (rb_fiber_t*)cont;
	    const rb_thread_t *const th = GET_THREAD();
#ifdef _WIN32
	    if (th && th->fiber != fib && cont->type != ROOT_FIBER_CONTEXT) {
		/* don't delete root fiber handle */
		if (fib->fib_handle) {
		    DeleteFiber(fib->fib_handle);
		}
	    }
#else /* not WIN32 */
	    if (th && th->fiber != fib) {
                if (fib->ss_sp) {
                    if (cont->type == ROOT_FIBER_CONTEXT) {
			rb_bug("Illegal root fiber parameter");
                    }
		    munmap((void*)fib->ss_sp, fib->ss_size);
		}
	    }
            else {
		/* It may reached here when finalize */
		/* TODO examine whether it is a bug */
                /* rb_bug("cont_free: release self"); */
            }
#endif
	}
#else /* not FIBER_USE_NATIVE */
	ruby_xfree(cont->ensure_array);
	RUBY_FREE_UNLESS_NULL(cont->machine.stack);
#endif
#ifdef __ia64
	RUBY_FREE_UNLESS_NULL(cont->machine.register_stack);
#endif
	RUBY_FREE_UNLESS_NULL(cont->vm_stack);

	/* free rb_cont_t or rb_fiber_t */
	ruby_xfree(ptr);
    }
    RUBY_FREE_LEAVE("cont");
}

static size_t
cont_memsize(const void *ptr)
{
    const rb_context_t *cont = ptr;
    size_t size = 0;

    size = sizeof(*cont);
    if (cont->vm_stack) {
#ifdef CAPTURE_JUST_VALID_VM_STACK
	size_t n = (cont->vm_stack_slen + cont->vm_stack_clen);
#else
	size_t n = cont->saved_thread.stack_size;
#endif
	size += n * sizeof(*cont->vm_stack);
    }

    if (cont->machine.stack) {
	size += cont->machine.stack_size * sizeof(*cont->machine.stack);
    }
#ifdef __ia64
    if (cont->machine.register_stack) {
	size += cont->machine.register_stack_size * sizeof(*cont->machine.register_stack);
    }
#endif
    return size;
}

void
rb_fiber_mark_self(rb_fiber_t *fib)
{
    if (fib)
	rb_gc_mark(fib->cont.self);
}

static void
fiber_mark(void *ptr)
{
    RUBY_MARK_ENTER("cont");
    if (ptr) {
	rb_fiber_t *fib = ptr;
	rb_fiber_mark_self(fib->prev);
	cont_mark(&fib->cont);
    }
    RUBY_MARK_LEAVE("cont");
}

static void
fiber_free(void *ptr)
{
    RUBY_FREE_ENTER("fiber");
    if (ptr) {
	rb_fiber_t *fib = ptr;
	if (fib->cont.type != ROOT_FIBER_CONTEXT &&
	    fib->cont.saved_thread.local_storage) {
	    st_free_table(fib->cont.saved_thread.local_storage);
	}

	cont_free(&fib->cont);
    }
    RUBY_FREE_LEAVE("fiber");
}

static size_t
fiber_memsize(const void *ptr)
{
    const rb_fiber_t *fib = ptr;
    size_t size = 0;

    size = sizeof(*fib);
    if (fib->cont.type != ROOT_FIBER_CONTEXT &&
	fib->cont.saved_thread.local_storage != NULL) {
	size += st_memsize(fib->cont.saved_thread.local_storage);
    }
    size += cont_memsize(&fib->cont);
    return size;
}

VALUE
rb_obj_is_fiber(VALUE obj)
{
    if (rb_typeddata_is_kind_of(obj, &fiber_data_type)) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

static void
cont_save_machine_stack(rb_thread_t *th, rb_context_t *cont)
{
    size_t size;

    SET_MACHINE_STACK_END(&th->machine.stack_end);
#ifdef __ia64
    th->machine.register_stack_end = rb_ia64_bsp();
#endif

    if (th->machine.stack_start > th->machine.stack_end) {
	size = cont->machine.stack_size = th->machine.stack_start - th->machine.stack_end;
	cont->machine.stack_src = th->machine.stack_end;
    }
    else {
	size = cont->machine.stack_size = th->machine.stack_end - th->machine.stack_start;
	cont->machine.stack_src = th->machine.stack_start;
    }

    if (cont->machine.stack) {
	REALLOC_N(cont->machine.stack, VALUE, size);
    }
    else {
	cont->machine.stack = ALLOC_N(VALUE, size);
    }

    FLUSH_REGISTER_WINDOWS;
    MEMCPY(cont->machine.stack, cont->machine.stack_src, VALUE, size);

#ifdef __ia64
    rb_ia64_flushrs();
    size = cont->machine.register_stack_size = th->machine.register_stack_end - th->machine.register_stack_start;
    cont->machine.register_stack_src = th->machine.register_stack_start;
    if (cont->machine.register_stack) {
	REALLOC_N(cont->machine.register_stack, VALUE, size);
    }
    else {
	cont->machine.register_stack = ALLOC_N(VALUE, size);
    }

    MEMCPY(cont->machine.register_stack, cont->machine.register_stack_src, VALUE, size);
#endif
}

static const rb_data_type_t cont_data_type = {
    "continuation",
    {cont_mark, cont_free, cont_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static inline void
cont_save_thread(rb_context_t *cont, rb_thread_t *th)
{
    rb_thread_t *sth = &cont->saved_thread;

    /* save thread context */
    sth->stack = th->stack;
    sth->stack_size = th->stack_size;
    sth->local_storage = th->local_storage;
    sth->cfp = th->cfp;
    sth->safe_level = th->safe_level;
    sth->raised_flag = th->raised_flag;
    sth->state = th->state;
    sth->status = th->status;
    sth->tag = th->tag;
    sth->protect_tag = th->protect_tag;
    sth->errinfo = th->errinfo;
    sth->first_proc = th->first_proc;
    sth->root_lep = th->root_lep;
    sth->root_svar = th->root_svar;
    sth->ensure_list = th->ensure_list;

    sth->trace_arg = th->trace_arg;

    /* saved_thread->machine.stack_(start|end) should be NULL */
    /* because it may happen GC afterward */
    sth->machine.stack_start = 0;
    sth->machine.stack_end = 0;
#ifdef __ia64
    sth->machine.register_stack_start = 0;
    sth->machine.register_stack_end = 0;
#endif
}

static void
cont_init(rb_context_t *cont, rb_thread_t *th)
{
    /* save thread context */
    cont_save_thread(cont, th);
    cont->saved_thread.self = th->self;
    cont->saved_thread.machine.stack_maxsize = th->machine.stack_maxsize;
    cont->saved_thread.fiber = th->fiber;
    cont->saved_thread.local_storage = 0;
    cont->saved_thread.local_storage_recursive_hash = Qnil;
    cont->saved_thread.local_storage_recursive_hash_for_trace = Qnil;
}

static rb_context_t *
cont_new(VALUE klass)
{
    rb_context_t *cont;
    volatile VALUE contval;
    rb_thread_t *th = GET_THREAD();

    THREAD_MUST_BE_RUNNING(th);
    contval = TypedData_Make_Struct(klass, rb_context_t, &cont_data_type, cont);
    cont->self = contval;
    cont_init(cont, th);
    return cont;
}

static VALUE
cont_capture(volatile int *volatile stat)
{
    rb_context_t *volatile cont;
    rb_thread_t *th = GET_THREAD();
    volatile VALUE contval;

    THREAD_MUST_BE_RUNNING(th);
    rb_vm_stack_to_heap(th);
    cont = cont_new(rb_cContinuation);
    contval = cont->self;

#ifdef CAPTURE_JUST_VALID_VM_STACK
    cont->vm_stack_slen = th->cfp->sp - th->stack;
    cont->vm_stack_clen = th->stack + th->stack_size - (VALUE*)th->cfp;
    cont->vm_stack = ALLOC_N(VALUE, cont->vm_stack_slen + cont->vm_stack_clen);
    MEMCPY(cont->vm_stack, th->stack, VALUE, cont->vm_stack_slen);
    MEMCPY(cont->vm_stack + cont->vm_stack_slen, (VALUE*)th->cfp, VALUE, cont->vm_stack_clen);
#else
    cont->vm_stack = ALLOC_N(VALUE, th->stack_size);
    MEMCPY(cont->vm_stack, th->stack, VALUE, th->stack_size);
#endif
    cont->saved_thread.stack = NULL;

    cont_save_machine_stack(th, cont);

    /* backup ensure_list to array for search in another context */
    {
	rb_ensure_list_t *p;
	int size = 0;
	rb_ensure_entry_t *entry;
	for (p=th->ensure_list; p; p=p->next)
	    size++;
	entry = cont->ensure_array = ALLOC_N(rb_ensure_entry_t,size+1);
	for (p=th->ensure_list; p; p=p->next) {
	    if (!p->entry.marker)
		p->entry.marker = rb_ary_tmp_new(0); /* dummy object */
	    *entry++ = p->entry;
	}
	entry->marker = 0;
    }

    if (ruby_setjmp(cont->jmpbuf)) {
	VALUE value;

	VAR_INITIALIZED(cont);
	value = cont->value;
	if (cont->argc == -1) rb_exc_raise(value);
	cont->value = Qnil;
	*stat = 1;
	return value;
    }
    else {
	*stat = 0;
	return contval;
    }
}

static inline void
cont_restore_thread(rb_context_t *cont)
{
    rb_thread_t *th = GET_THREAD(), *sth = &cont->saved_thread;

    /* restore thread context */
    if (cont->type == CONTINUATION_CONTEXT) {
	/* continuation */
	rb_fiber_t *fib;

	th->fiber = sth->fiber;
	fib = th->fiber ? th->fiber : th->root_fiber;

	if (fib && fib->cont.saved_thread.stack) {
	    th->stack_size = fib->cont.saved_thread.stack_size;
	    th->stack = fib->cont.saved_thread.stack;
	}
#ifdef CAPTURE_JUST_VALID_VM_STACK
	MEMCPY(th->stack, cont->vm_stack, VALUE, cont->vm_stack_slen);
	MEMCPY(th->stack + sth->stack_size - cont->vm_stack_clen,
	       cont->vm_stack + cont->vm_stack_slen, VALUE, cont->vm_stack_clen);
#else
	MEMCPY(th->stack, cont->vm_stack, VALUE, sth->stack_size);
#endif
    }
    else {
	/* fiber */
	th->stack = sth->stack;
	sth->stack = NULL;
	th->stack_size = sth->stack_size;
	th->local_storage = sth->local_storage;
	th->local_storage_recursive_hash = sth->local_storage_recursive_hash;
	th->local_storage_recursive_hash_for_trace = sth->local_storage_recursive_hash_for_trace;
	th->fiber = (rb_fiber_t*)cont;
    }

    th->cfp = sth->cfp;
    th->safe_level = sth->safe_level;
    th->raised_flag = sth->raised_flag;
    th->state = sth->state;
    th->status = sth->status;
    th->tag = sth->tag;
    th->protect_tag = sth->protect_tag;
    th->errinfo = sth->errinfo;
    th->first_proc = sth->first_proc;
    th->root_lep = sth->root_lep;
    th->root_svar = sth->root_svar;
    th->ensure_list = sth->ensure_list;
    VM_ASSERT(th->stack != NULL);
    VM_ASSERT(sth->status == THREAD_RUNNABLE);
}

#if FIBER_USE_NATIVE
#ifdef _WIN32
static void
fiber_set_stack_location(void)
{
    rb_thread_t *th = GET_THREAD();
    VALUE *ptr;

    SET_MACHINE_STACK_END(&ptr);
    th->machine.stack_start = (void*)(((VALUE)ptr & RB_PAGE_MASK) + STACK_UPPER((void *)&ptr, 0, RB_PAGE_SIZE));
}

static VOID CALLBACK
fiber_entry(void *arg)
{
    fiber_set_stack_location();
    rb_fiber_start();
}
#else /* _WIN32 */

/*
 * FreeBSD require a first (i.e. addr) argument of mmap(2) is not NULL
 * if MAP_STACK is passed.
 * http://www.FreeBSD.org/cgi/query-pr.cgi?pr=158755
 */
#if defined(MAP_STACK) && !defined(__FreeBSD__) && !defined(__FreeBSD_kernel__)
#define FIBER_STACK_FLAGS (MAP_PRIVATE | MAP_ANON | MAP_STACK)
#else
#define FIBER_STACK_FLAGS (MAP_PRIVATE | MAP_ANON)
#endif

static char*
fiber_machine_stack_alloc(size_t size)
{
    char *ptr;

    if (machine_stack_cache_index > 0) {
	if (machine_stack_cache[machine_stack_cache_index - 1].size == (size / sizeof(VALUE))) {
	    ptr = machine_stack_cache[machine_stack_cache_index - 1].ptr;
	    machine_stack_cache_index--;
	    machine_stack_cache[machine_stack_cache_index].ptr = NULL;
	    machine_stack_cache[machine_stack_cache_index].size = 0;
	}
	else{
            /* TODO handle multiple machine stack size */
	    rb_bug("machine_stack_cache size is not canonicalized");
	}
    }
    else {
	void *page;
	STACK_GROW_DIR_DETECTION;

	errno = 0;
	ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, FIBER_STACK_FLAGS, -1, 0);
	if (ptr == MAP_FAILED) {
	    rb_raise(rb_eFiberError, "can't alloc machine stack to fiber: %s", strerror(errno));
	}

	/* guard page setup */
	page = ptr + STACK_DIR_UPPER(size - RB_PAGE_SIZE, 0);
	if (mprotect(page, RB_PAGE_SIZE, PROT_NONE) < 0) {
	    rb_raise(rb_eFiberError, "mprotect failed");
	}
    }

    return ptr;
}
#endif

static void
fiber_initialize_machine_stack_context(rb_fiber_t *fib, size_t size)
{
    rb_thread_t *sth = &fib->cont.saved_thread;

#ifdef _WIN32
# if defined(_MSC_VER) && _MSC_VER <= 1200
#   define CreateFiberEx(cs, stacksize, flags, entry, param) \
    CreateFiber((stacksize), (entry), (param))
# endif
    fib->fib_handle = CreateFiberEx(size - 1, size, 0, fiber_entry, NULL);
    if (!fib->fib_handle) {
	/* try to release unnecessary fibers & retry to create */
	rb_gc();
	fib->fib_handle = CreateFiberEx(size - 1, size, 0, fiber_entry, NULL);
	if (!fib->fib_handle) {
	    rb_raise(rb_eFiberError, "can't create fiber");
	}
    }
    sth->machine.stack_maxsize = size;
#else /* not WIN32 */
    ucontext_t *context = &fib->context;
    char *ptr;
    STACK_GROW_DIR_DETECTION;

    getcontext(context);
    ptr = fiber_machine_stack_alloc(size);
    context->uc_link = NULL;
    context->uc_stack.ss_sp = ptr;
    context->uc_stack.ss_size = size;
    fib->ss_sp = ptr;
    fib->ss_size = size;
    makecontext(context, rb_fiber_start, 0);
    sth->machine.stack_start = (VALUE*)(ptr + STACK_DIR_UPPER(0, size));
    sth->machine.stack_maxsize = size - RB_PAGE_SIZE;
#endif
#ifdef __ia64
    sth->machine.register_stack_maxsize = sth->machine.stack_maxsize;
#endif
}

NOINLINE(static void fiber_setcontext(rb_fiber_t *newfib, rb_fiber_t *oldfib));

static void
fiber_setcontext(rb_fiber_t *newfib, rb_fiber_t *oldfib)
{
    rb_thread_t *th = GET_THREAD(), *sth = &newfib->cont.saved_thread;

    if (newfib->status != RUNNING) {
	fiber_initialize_machine_stack_context(newfib, th->vm->default_params.fiber_machine_stack_size);
    }

    /* restore thread context */
    cont_restore_thread(&newfib->cont);
    th->machine.stack_maxsize = sth->machine.stack_maxsize;
    if (sth->machine.stack_end && (newfib != oldfib)) {
	rb_bug("fiber_setcontext: sth->machine.stack_end has non zero value");
    }

    /* save  oldfib's machine stack */
    if (oldfib->status != TERMINATED) {
	STACK_GROW_DIR_DETECTION;
	SET_MACHINE_STACK_END(&th->machine.stack_end);
	if (STACK_DIR_UPPER(0, 1)) {
	    oldfib->cont.machine.stack_size = th->machine.stack_start - th->machine.stack_end;
	    oldfib->cont.machine.stack = th->machine.stack_end;
	}
	else {
	    oldfib->cont.machine.stack_size = th->machine.stack_end - th->machine.stack_start;
	    oldfib->cont.machine.stack = th->machine.stack_start;
	}
    }
    /* exchange machine_stack_start between oldfib and newfib */
    oldfib->cont.saved_thread.machine.stack_start = th->machine.stack_start;
    th->machine.stack_start = sth->machine.stack_start;
    /* oldfib->machine.stack_end should be NULL */
    oldfib->cont.saved_thread.machine.stack_end = 0;
#ifndef _WIN32
    if (!newfib->context.uc_stack.ss_sp && th->root_fiber != newfib) {
	rb_bug("non_root_fiber->context.uc_stac.ss_sp should not be NULL");
    }
#endif
    /* swap machine context */
#ifdef _WIN32
    SwitchToFiber(newfib->fib_handle);
#else
    swapcontext(&oldfib->context, &newfib->context);
#endif
}
#endif

NOINLINE(NORETURN(static void cont_restore_1(rb_context_t *)));

static void
cont_restore_1(rb_context_t *cont)
{
    cont_restore_thread(cont);

    /* restore machine stack */
#ifdef _M_AMD64
    {
	/* workaround for x64 SEH */
	jmp_buf buf;
	setjmp(buf);
	((_JUMP_BUFFER*)(&cont->jmpbuf))->Frame =
	    ((_JUMP_BUFFER*)(&buf))->Frame;
    }
#endif
    if (cont->machine.stack_src) {
	FLUSH_REGISTER_WINDOWS;
	MEMCPY(cont->machine.stack_src, cont->machine.stack,
		VALUE, cont->machine.stack_size);
    }

#ifdef __ia64
    if (cont->machine.register_stack_src) {
	MEMCPY(cont->machine.register_stack_src, cont->machine.register_stack,
	       VALUE, cont->machine.register_stack_size);
    }
#endif

    ruby_longjmp(cont->jmpbuf, 1);
}

NORETURN(NOINLINE(static void cont_restore_0(rb_context_t *, VALUE *)));

#ifdef __ia64
#define C(a) rse_##a##0, rse_##a##1, rse_##a##2, rse_##a##3, rse_##a##4
#define E(a) rse_##a##0= rse_##a##1= rse_##a##2= rse_##a##3= rse_##a##4
static volatile int C(a), C(b), C(c), C(d), C(e);
static volatile int C(f), C(g), C(h), C(i), C(j);
static volatile int C(k), C(l), C(m), C(n), C(o);
static volatile int C(p), C(q), C(r), C(s), C(t);
#if 0
{/* the above lines make cc-mode.el confused so much */}
#endif
int rb_dummy_false = 0;
NORETURN(NOINLINE(static void register_stack_extend(rb_context_t *, VALUE *, VALUE *)));
static void
register_stack_extend(rb_context_t *cont, VALUE *vp, VALUE *curr_bsp)
{
    if (rb_dummy_false) {
        /* use registers as much as possible */
        E(a) = E(b) = E(c) = E(d) = E(e) =
        E(f) = E(g) = E(h) = E(i) = E(j) =
        E(k) = E(l) = E(m) = E(n) = E(o) =
        E(p) = E(q) = E(r) = E(s) = E(t) = 0;
        E(a) = E(b) = E(c) = E(d) = E(e) =
        E(f) = E(g) = E(h) = E(i) = E(j) =
        E(k) = E(l) = E(m) = E(n) = E(o) =
        E(p) = E(q) = E(r) = E(s) = E(t) = 0;
    }
    if (curr_bsp < cont->machine.register_stack_src+cont->machine.register_stack_size) {
        register_stack_extend(cont, vp, (VALUE*)rb_ia64_bsp());
    }
    cont_restore_0(cont, vp);
}
#undef C
#undef E
#endif

static void
cont_restore_0(rb_context_t *cont, VALUE *addr_in_prev_frame)
{
    if (cont->machine.stack_src) {
#ifdef HAVE_ALLOCA
#define STACK_PAD_SIZE 1
#else
#define STACK_PAD_SIZE 1024
#endif
	VALUE space[STACK_PAD_SIZE];

#if !STACK_GROW_DIRECTION
	if (addr_in_prev_frame > &space[0]) {
	    /* Stack grows downward */
#endif
#if STACK_GROW_DIRECTION <= 0
	    volatile VALUE *const end = cont->machine.stack_src;
	    if (&space[0] > end) {
# ifdef HAVE_ALLOCA
		volatile VALUE *sp = ALLOCA_N(VALUE, &space[0] - end);
		space[0] = *sp;
# else
		cont_restore_0(cont, &space[0]);
# endif
	    }
#endif
#if !STACK_GROW_DIRECTION
	}
	else {
	    /* Stack grows upward */
#endif
#if STACK_GROW_DIRECTION >= 0
	    volatile VALUE *const end = cont->machine.stack_src + cont->machine.stack_size;
	    if (&space[STACK_PAD_SIZE] < end) {
# ifdef HAVE_ALLOCA
		volatile VALUE *sp = ALLOCA_N(VALUE, end - &space[STACK_PAD_SIZE]);
		space[0] = *sp;
# else
		cont_restore_0(cont, &space[STACK_PAD_SIZE-1]);
# endif
	    }
#endif
#if !STACK_GROW_DIRECTION
	}
#endif
    }
    cont_restore_1(cont);
}
#ifdef __ia64
#define cont_restore_0(cont, vp) register_stack_extend((cont), (vp), (VALUE*)rb_ia64_bsp())
#endif

/*
 *  Document-class: Continuation
 *
 *  Continuation objects are generated by Kernel#callcc,
 *  after having +require+d <i>continuation</i>. They hold
 *  a return address and execution context, allowing a nonlocal return
 *  to the end of the <code>callcc</code> block from anywhere within a
 *  program. Continuations are somewhat analogous to a structured
 *  version of C's <code>setjmp/longjmp</code> (although they contain
 *  more state, so you might consider them closer to threads).
 *
 *  For instance:
 *
 *     require "continuation"
 *     arr = [ "Freddie", "Herbie", "Ron", "Max", "Ringo" ]
 *     callcc{|cc| $cc = cc}
 *     puts(message = arr.shift)
 *     $cc.call unless message =~ /Max/
 *
 *  <em>produces:</em>
 *
 *     Freddie
 *     Herbie
 *     Ron
 *     Max
 *
 *  Also you can call callcc in other methods:
 *
 *     require "continuation"
 *
 *     def g
 *       arr = [ "Freddie", "Herbie", "Ron", "Max", "Ringo" ]
 *       cc = callcc { |cc| cc }
 *       puts arr.shift
 *       return cc, arr.size
 *     end
 *
 *     def f
 *       c, size = g
 *       c.call(c) if size > 1
 *     end
 *
 *     f
 *
 *  This (somewhat contrived) example allows the inner loop to abandon
 *  processing early:
 *
 *     require "continuation"
 *     callcc {|cont|
 *       for i in 0..4
 *         print "\n#{i}: "
 *         for j in i*5...(i+1)*5
 *           cont.call() if j == 17
 *           printf "%3d", j
 *         end
 *       end
 *     }
 *     puts
 *
 *  <em>produces:</em>
 *
 *     0:   0  1  2  3  4
 *     1:   5  6  7  8  9
 *     2:  10 11 12 13 14
 *     3:  15 16
 */

/*
 *  call-seq:
 *     callcc {|cont| block }   ->  obj
 *
 *  Generates a Continuation object, which it passes to
 *  the associated block. You need to <code>require
 *  'continuation'</code> before using this method. Performing a
 *  <em>cont</em><code>.call</code> will cause the #callcc
 *  to return (as will falling through the end of the block). The
 *  value returned by the #callcc is the value of the
 *  block, or the value passed to <em>cont</em><code>.call</code>. See
 *  class Continuation for more details. Also see
 *  Kernel#throw for an alternative mechanism for
 *  unwinding a call stack.
 */

static VALUE
rb_callcc(VALUE self)
{
    volatile int called;
    volatile VALUE val = cont_capture(&called);

    if (called) {
	return val;
    }
    else {
	return rb_yield(val);
    }
}

static VALUE
make_passing_arg(int argc, const VALUE *argv)
{
    switch (argc) {
      case 0:
	return Qnil;
      case 1:
	return argv[0];
      default:
	return rb_ary_new4(argc, argv);
    }
}

/* CAUTION!! : Currently, error in rollback_func is not supported  */
/* same as rb_protect if set rollback_func to NULL */
void
ruby_register_rollback_func_for_ensure(VALUE (*ensure_func)(ANYARGS), VALUE (*rollback_func)(ANYARGS))
{
    st_table **table_p = &GET_VM()->ensure_rollback_table;
    if (UNLIKELY(*table_p == NULL)) {
	*table_p = st_init_numtable();
    }
    st_insert(*table_p, (st_data_t)ensure_func, (st_data_t)rollback_func);
}

static inline VALUE
lookup_rollback_func(VALUE (*ensure_func)(ANYARGS))
{
    st_table *table = GET_VM()->ensure_rollback_table;
    st_data_t val;
    if (table && st_lookup(table, (st_data_t)ensure_func, &val))
	return (VALUE) val;
    return Qundef;
}


static inline void
rollback_ensure_stack(VALUE self,rb_ensure_list_t *current,rb_ensure_entry_t *target)
{
    rb_ensure_list_t *p;
    rb_ensure_entry_t *entry;
    size_t i;
    size_t cur_size;
    size_t target_size;
    size_t base_point;
    VALUE (*func)(ANYARGS);

    cur_size = 0;
    for (p=current; p; p=p->next)
	cur_size++;
    target_size = 0;
    for (entry=target; entry->marker; entry++)
	target_size++;

    /* search common stack point */
    p = current;
    base_point = cur_size;
    while (base_point) {
	if (target_size >= base_point &&
	    p->entry.marker == target[target_size - base_point].marker)
	    break;
	base_point --;
	p = p->next;
    }

    /* rollback function check */
    for (i=0; i < target_size - base_point; i++) {
	if (!lookup_rollback_func(target[i].e_proc)) {
	    rb_raise(rb_eRuntimeError, "continuation called from out of critical rb_ensure scope");
	}
    }
    /* pop ensure stack */
    while (cur_size > base_point) {
	/* escape from ensure block */
	(*current->entry.e_proc)(current->entry.data2);
	current = current->next;
	cur_size--;
    }
    /* push ensure stack */
    while (i--) {
	func = (VALUE (*)(ANYARGS)) lookup_rollback_func(target[i].e_proc);
	if ((VALUE)func != Qundef) {
	    (*func)(target[i].data2);
	}
    }
}

/*
 *  call-seq:
 *     cont.call(args, ...)
 *     cont[args, ...]
 *
 *  Invokes the continuation. The program continues from the end of the
 *  <code>callcc</code> block. If no arguments are given, the original
 *  <code>callcc</code> returns <code>nil</code>. If one argument is
 *  given, <code>callcc</code> returns it. Otherwise, an array
 *  containing <i>args</i> is returned.
 *
 *     callcc {|cont|  cont.call }           #=> nil
 *     callcc {|cont|  cont.call 1 }         #=> 1
 *     callcc {|cont|  cont.call 1, 2, 3 }   #=> [1, 2, 3]
 */

static VALUE
rb_cont_call(int argc, VALUE *argv, VALUE contval)
{
    rb_context_t *cont;
    rb_thread_t *th = GET_THREAD();
    GetContPtr(contval, cont);

    if (cont->saved_thread.self != th->self) {
	rb_raise(rb_eRuntimeError, "continuation called across threads");
    }
    if (cont->saved_thread.protect_tag != th->protect_tag) {
	rb_raise(rb_eRuntimeError, "continuation called across stack rewinding barrier");
    }
    if (cont->saved_thread.fiber) {
	if (th->fiber != cont->saved_thread.fiber) {
	    rb_raise(rb_eRuntimeError, "continuation called across fiber");
	}
    }
    rollback_ensure_stack(contval, th->ensure_list, cont->ensure_array);

    cont->argc = argc;
    cont->value = make_passing_arg(argc, argv);

    /* restore `tracing' context. see [Feature #4347] */
    th->trace_arg = cont->saved_thread.trace_arg;
    cont_restore_0(cont, &contval);
    return Qnil; /* unreachable */
}

/*********/
/* fiber */
/*********/

/*
 *  Document-class: Fiber
 *
 *  Fibers are primitives for implementing light weight cooperative
 *  concurrency in Ruby. Basically they are a means of creating code blocks
 *  that can be paused and resumed, much like threads. The main difference
 *  is that they are never preempted and that the scheduling must be done by
 *  the programmer and not the VM.
 *
 *  As opposed to other stackless light weight concurrency models, each fiber
 *  comes with a stack.  This enables the fiber to be paused from deeply
 *  nested function calls within the fiber block.  See the ruby(1)
 *  manpage to configure the size of the fiber stack(s).
 *
 *  When a fiber is created it will not run automatically. Rather it must
 *  be explicitly asked to run using the <code>Fiber#resume</code> method.
 *  The code running inside the fiber can give up control by calling
 *  <code>Fiber.yield</code> in which case it yields control back to caller
 *  (the caller of the <code>Fiber#resume</code>).
 *
 *  Upon yielding or termination the Fiber returns the value of the last
 *  executed expression
 *
 *  For instance:
 *
 *    fiber = Fiber.new do
 *      Fiber.yield 1
 *      2
 *    end
 *
 *    puts fiber.resume
 *    puts fiber.resume
 *    puts fiber.resume
 *
 *  <em>produces</em>
 *
 *    1
 *    2
 *    FiberError: dead fiber called
 *
 *  The <code>Fiber#resume</code> method accepts an arbitrary number of
 *  parameters, if it is the first call to <code>resume</code> then they
 *  will be passed as block arguments. Otherwise they will be the return
 *  value of the call to <code>Fiber.yield</code>
 *
 *  Example:
 *
 *    fiber = Fiber.new do |first|
 *      second = Fiber.yield first + 2
 *    end
 *
 *    puts fiber.resume 10
 *    puts fiber.resume 14
 *    puts fiber.resume 18
 *
 *  <em>produces</em>
 *
 *    12
 *    14
 *    FiberError: dead fiber called
 *
 */

static const rb_data_type_t fiber_data_type = {
    "fiber",
    {fiber_mark, fiber_free, fiber_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
fiber_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &fiber_data_type, 0);
}

static rb_fiber_t*
fiber_t_alloc(VALUE fibval)
{
    rb_fiber_t *fib;
    rb_thread_t *th = GET_THREAD();

    if (DATA_PTR(fibval) != 0) {
	rb_raise(rb_eRuntimeError, "cannot initialize twice");
    }

    THREAD_MUST_BE_RUNNING(th);
    fib = ZALLOC(rb_fiber_t);
    fib->cont.self = fibval;
    fib->cont.type = FIBER_CONTEXT;
    cont_init(&fib->cont, th);
    fib->prev = NULL;
    fib->status = CREATED;

    DATA_PTR(fibval) = fib;

    return fib;
}

rb_control_frame_t *
rb_vm_push_frame(rb_thread_t *th,
		 const rb_iseq_t *iseq,
		 VALUE type,
		 VALUE self,
		 VALUE specval,
		 VALUE cref_or_me,
		 const VALUE *pc,
		 VALUE *sp,
		 int local_size,
		 int stack_max);

static VALUE
fiber_init(VALUE fibval, VALUE proc)
{
    rb_fiber_t *fib = fiber_t_alloc(fibval);
    rb_context_t *cont = &fib->cont;
    rb_thread_t *th = &cont->saved_thread;
    rb_thread_t *cth = GET_THREAD();

    /* initialize cont */
    cont->vm_stack = 0;

    th->stack = NULL;
    th->stack_size = 0;

    th->stack_size = cth->vm->default_params.fiber_vm_stack_size / sizeof(VALUE);
    th->stack = ALLOC_N(VALUE, th->stack_size);
    th->cfp = (void *)(th->stack + th->stack_size);

    rb_vm_push_frame(th,
		     NULL,
		     VM_FRAME_MAGIC_DUMMY | VM_ENV_FLAG_LOCAL | VM_FRAME_FLAG_FINISH | VM_FRAME_FLAG_CFRAME,
		     Qnil, /* self */
		     VM_BLOCK_HANDLER_NONE,
		     0, /* specval */
		     NULL, /* pc */
		     th->stack, /* sp */
		     0, /* local_size */
		     0);

    th->tag = 0;
    th->local_storage = st_init_numtable();
    th->local_storage_recursive_hash = Qnil;
    th->local_storage_recursive_hash_for_trace = Qnil;

    th->first_proc = proc;

#if !FIBER_USE_NATIVE
    MEMCPY(&cont->jmpbuf, &cth->root_jmpbuf, rb_jmpbuf_t, 1);
#endif

    return fibval;
}

/* :nodoc: */
static VALUE
rb_fiber_init(VALUE fibval)
{
    return fiber_init(fibval, rb_block_proc());
}

VALUE
rb_fiber_new(VALUE (*func)(ANYARGS), VALUE obj)
{
    return fiber_init(fiber_alloc(rb_cFiber), rb_proc_new(func, obj));
}

static void rb_fiber_terminate(rb_fiber_t *fib);

void
rb_fiber_start(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_fiber_t *fib = th->fiber;
    rb_proc_t *proc;
    int state;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	rb_context_t *cont = &VAR_FROM_MEMORY(fib)->cont;
	int argc;
	const VALUE *argv, args = cont->value;
	GetProcPtr(cont->saved_thread.first_proc, proc);
	argv = (argc = cont->argc) > 1 ? RARRAY_CONST_PTR(args) : &args;
	cont->value = Qnil;
	th->errinfo = Qnil;
	th->root_lep = rb_vm_proc_local_ep(cont->saved_thread.first_proc);
	th->root_svar = Qfalse;
	fib->status = RUNNING;

	EXEC_EVENT_HOOK(th, RUBY_EVENT_FIBER_SWITCH, th->self, 0, 0, 0, Qnil);
	cont->value = rb_vm_invoke_proc(th, proc, argc, argv, VM_BLOCK_HANDLER_NONE);
    }
    TH_POP_TAG();

    if (state) {
	if (state == TAG_RAISE || state == TAG_FATAL) {
	    rb_threadptr_pending_interrupt_enque(th, th->errinfo);
	}
	else {
	    VALUE err = rb_vm_make_jump_tag_but_local_jump(state, th->errinfo);
	    if (!NIL_P(err))
		rb_threadptr_pending_interrupt_enque(th, err);
	}
	RUBY_VM_SET_INTERRUPT(th);
    }

    rb_fiber_terminate(fib);
    rb_bug("rb_fiber_start: unreachable");
}

static rb_fiber_t *
root_fiber_alloc(rb_thread_t *th)
{
    rb_fiber_t *fib;
    /* no need to allocate vm stack */
    fib = fiber_t_alloc(fiber_alloc(rb_cFiber));
    fib->cont.type = ROOT_FIBER_CONTEXT;
#if FIBER_USE_NATIVE
#ifdef _WIN32
    fib->fib_handle = ConvertThreadToFiber(0);
#endif
#endif
    fib->status = RUNNING;

    th->root_fiber = th->fiber = fib;
    return fib;
}

static inline rb_fiber_t*
fiber_current(void)
{
    rb_thread_t *th = GET_THREAD();
    if (th->fiber == 0) {
	rb_fiber_t *fib = root_fiber_alloc(th);
	/* Running thread object has stack management responsibility */
	fib->cont.saved_thread.stack = NULL;
    }
    return th->fiber;
}

static inline rb_fiber_t*
return_fiber(void)
{
    rb_fiber_t *fib = fiber_current();
    rb_fiber_t *prev = fib->prev;

    if (!prev) {
	rb_fiber_t *root_fiber = GET_THREAD()->root_fiber;

	if (root_fiber == fib) {
	    rb_raise(rb_eFiberError, "can't yield from root fiber");
	}
	return root_fiber;
    }
    else {
	fib->prev = NULL;
	return prev;
    }
}

VALUE
rb_fiber_current(void)
{
    return fiber_current()->cont.self;
}

static inline VALUE
fiber_store(rb_fiber_t *next_fib, rb_thread_t *th)
{
    rb_fiber_t *fib;

    if (th->fiber) {
	fib = th->fiber;
	cont_save_thread(&fib->cont, th);
    }
    else {
	/* create root fiber */
	fib = root_fiber_alloc(th);
    }

#if FIBER_USE_NATIVE
    fiber_setcontext(next_fib, fib);
    /* restored */
#ifndef _WIN32
    if (terminated_machine_stack.ptr) {
	if (machine_stack_cache_index < MAX_MACHINE_STACK_CACHE) {
	    machine_stack_cache[machine_stack_cache_index].ptr = terminated_machine_stack.ptr;
	    machine_stack_cache[machine_stack_cache_index].size = terminated_machine_stack.size;
	    machine_stack_cache_index++;
	}
	else {
	    if (terminated_machine_stack.ptr != fib->cont.machine.stack) {
		munmap((void*)terminated_machine_stack.ptr, terminated_machine_stack.size * sizeof(VALUE));
	    }
	    else {
		rb_bug("terminated fiber resumed");
	    }
	}
	terminated_machine_stack.ptr = NULL;
	terminated_machine_stack.size = 0;
    }
#endif /* not _WIN32 */
    fib = th->fiber;
    if (fib->cont.argc == -1) rb_exc_raise(fib->cont.value);
    return fib->cont.value;

#else /* FIBER_USE_NATIVE */
    cont_save_machine_stack(th, &fib->cont);
    if (ruby_setjmp(fib->cont.jmpbuf)) {
	/* restored */
	fib = th->fiber;
	if (fib->cont.argc == -1) rb_exc_raise(fib->cont.value);
	if (next_fib->cont.value == Qundef) {
	    cont_restore_0(&next_fib->cont, &next_fib->cont.value);
	    rb_bug("rb_fiber_resume: unreachable");
	}
	return fib->cont.value;
    }
    else {
	VALUE undef = Qundef;
	cont_restore_0(&next_fib->cont, &undef);
	rb_bug("rb_fiber_resume: unreachable");
    }
#endif /* FIBER_USE_NATIVE */
}

static inline VALUE
fiber_switch(rb_fiber_t *fib, int argc, const VALUE *argv, int is_resume)
{
    VALUE value;
    rb_context_t *cont = &fib->cont;
    rb_thread_t *th = GET_THREAD();

    if (th->fiber == fib) {
	/* ignore fiber context switch
         * because destination fiber is same as current fiber
	 */
	return make_passing_arg(argc, argv);
    }

    if (cont->saved_thread.self != th->self) {
	rb_raise(rb_eFiberError, "fiber called across threads");
    }
    else if (cont->saved_thread.protect_tag != th->protect_tag) {
	rb_raise(rb_eFiberError, "fiber called across stack rewinding barrier");
    }
    else if (fib->status == TERMINATED) {
	value = rb_exc_new2(rb_eFiberError, "dead fiber called");

	if (th->fiber->status != TERMINATED) rb_exc_raise(value);

	/* th->fiber is also dead => switch to root fiber */
	/* (this means we're being called from rb_fiber_terminate, */
	/* and the terminated fiber's return_fiber() is already dead) */
	cont = &th->root_fiber->cont;
	cont->argc = -1;
	cont->value = value;
#if FIBER_USE_NATIVE
	fiber_setcontext(th->root_fiber, th->fiber);
#else
	cont_restore_0(cont, &value);
#endif
	/* unreachable */
    }

    if (is_resume) {
	fib->prev = fiber_current();
    }
    else {
	/* restore `tracing' context. see [Feature #4347] */
	th->trace_arg = cont->saved_thread.trace_arg;
    }

    cont->argc = argc;
    cont->value = make_passing_arg(argc, argv);

    value = fiber_store(fib, th);
    RUBY_VM_CHECK_INTS(th);

    EXEC_EVENT_HOOK(th, RUBY_EVENT_FIBER_SWITCH, th->self, 0, 0, 0, Qnil);

    return value;
}

VALUE
rb_fiber_transfer(VALUE fibval, int argc, const VALUE *argv)
{
    rb_fiber_t *fib;
    GetFiberPtr(fibval, fib);
    return fiber_switch(fib, argc, argv, 0);
}

static void
rb_fiber_terminate(rb_fiber_t *fib)
{
    VALUE value = fib->cont.value;
    fib->status = TERMINATED;
#if FIBER_USE_NATIVE && !defined(_WIN32)
    /* Ruby must not switch to other thread until storing terminated_machine_stack */
    terminated_machine_stack.ptr = fib->ss_sp;
    terminated_machine_stack.size = fib->ss_size / sizeof(VALUE);
    fib->ss_sp = NULL;
    fib->context.uc_stack.ss_sp = NULL;
    fib->cont.machine.stack = NULL;
    fib->cont.machine.stack_size = 0;
#endif
    fiber_switch(return_fiber(), 1, &value, 0);
}

VALUE
rb_fiber_resume(VALUE fibval, int argc, const VALUE *argv)
{
    rb_fiber_t *fib;
    GetFiberPtr(fibval, fib);

    if (fib->prev != 0 || fib->cont.type == ROOT_FIBER_CONTEXT) {
	rb_raise(rb_eFiberError, "double resume");
    }
    if (fib->transferred != 0) {
	rb_raise(rb_eFiberError, "cannot resume transferred Fiber");
    }

    return fiber_switch(fib, argc, argv, 1);
}

VALUE
rb_fiber_yield(int argc, const VALUE *argv)
{
    return fiber_switch(return_fiber(), argc, argv, 0);
}

void
rb_fiber_reset_root_local_storage(VALUE thval)
{
    rb_thread_t *th;

    GetThreadPtr(thval, th);
    if (th->root_fiber && th->root_fiber != th->fiber) {
	th->local_storage = th->root_fiber->cont.saved_thread.local_storage;
    }
}

/*
 *  call-seq:
 *     fiber.alive? -> true or false
 *
 *  Returns true if the fiber can still be resumed (or transferred
 *  to). After finishing execution of the fiber block this method will
 *  always return false. You need to <code>require 'fiber'</code>
 *  before using this method.
 */
VALUE
rb_fiber_alive_p(VALUE fibval)
{
    rb_fiber_t *fib;
    GetFiberPtr(fibval, fib);
    return fib->status != TERMINATED ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     fiber.resume(args, ...) -> obj
 *
 *  Resumes the fiber from the point at which the last <code>Fiber.yield</code>
 *  was called, or starts running it if it is the first call to
 *  <code>resume</code>. Arguments passed to resume will be the value of
 *  the <code>Fiber.yield</code> expression or will be passed as block
 *  parameters to the fiber's block if this is the first <code>resume</code>.
 *
 *  Alternatively, when resume is called it evaluates to the arguments passed
 *  to the next <code>Fiber.yield</code> statement inside the fiber's block
 *  or to the block value if it runs to completion without any
 *  <code>Fiber.yield</code>
 */
static VALUE
rb_fiber_m_resume(int argc, VALUE *argv, VALUE fib)
{
    return rb_fiber_resume(fib, argc, argv);
}

/*
 *  call-seq:
 *     fiber.transfer(args, ...) -> obj
 *
 *  Transfer control to another fiber, resuming it from where it last
 *  stopped or starting it if it was not resumed before. The calling
 *  fiber will be suspended much like in a call to
 *  <code>Fiber.yield</code>. You need to <code>require 'fiber'</code>
 *  before using this method.
 *
 *  The fiber which receives the transfer call is treats it much like
 *  a resume call. Arguments passed to transfer are treated like those
 *  passed to resume.
 *
 *  You cannot resume a fiber that transferred control to another one.
 *  This will cause a double resume error. You need to transfer control
 *  back to this fiber before it can yield and resume.
 *
 *  Example:
 *
 *    fiber1 = Fiber.new do
 *      puts "In Fiber 1"
 *      Fiber.yield
 *    end
 *
 *    fiber2 = Fiber.new do
 *      puts "In Fiber 2"
 *      fiber1.transfer
 *      puts "Never see this message"
 *    end
 *
 *    fiber3 = Fiber.new do
 *      puts "In Fiber 3"
 *    end
 *
 *    fiber2.resume
 *    fiber3.resume
 *
 *  <em>produces</em>
 *
 *    In fiber 2
 *    In fiber 1
 *    In fiber 3
 *
 */
static VALUE
rb_fiber_m_transfer(int argc, VALUE *argv, VALUE fibval)
{
    rb_fiber_t *fib;
    GetFiberPtr(fibval, fib);
    fib->transferred = 1;
    return fiber_switch(fib, argc, argv, 0);
}

/*
 *  call-seq:
 *     Fiber.yield(args, ...) -> obj
 *
 *  Yields control back to the context that resumed the fiber, passing
 *  along any arguments that were passed to it. The fiber will resume
 *  processing at this point when <code>resume</code> is called next.
 *  Any arguments passed to the next <code>resume</code> will be the
 *  value that this <code>Fiber.yield</code> expression evaluates to.
 */
static VALUE
rb_fiber_s_yield(int argc, VALUE *argv, VALUE klass)
{
    return rb_fiber_yield(argc, argv);
}

/*
 *  call-seq:
 *     Fiber.current() -> fiber
 *
 *  Returns the current fiber. You need to <code>require 'fiber'</code>
 *  before using this method. If you are not running in the context of
 *  a fiber this method will return the root fiber.
 */
static VALUE
rb_fiber_s_current(VALUE klass)
{
    return rb_fiber_current();
}



/*
 *  Document-class: FiberError
 *
 *  Raised when an invalid operation is attempted on a Fiber, in
 *  particular when attempting to call/resume a dead fiber,
 *  attempting to yield from the root fiber, or calling a fiber across
 *  threads.
 *
 *     fiber = Fiber.new{}
 *     fiber.resume #=> nil
 *     fiber.resume #=> FiberError: dead fiber called
 */

void
Init_Cont(void)
{
#if FIBER_USE_NATIVE
    rb_thread_t *th = GET_THREAD();

#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    pagesize = info.dwPageSize;
#else /* not WIN32 */
    pagesize = sysconf(_SC_PAGESIZE);
#endif
    SET_MACHINE_STACK_END(&th->machine.stack_end);
#endif

    rb_cFiber = rb_define_class("Fiber", rb_cObject);
    rb_define_alloc_func(rb_cFiber, fiber_alloc);
    rb_eFiberError = rb_define_class("FiberError", rb_eStandardError);
    rb_define_singleton_method(rb_cFiber, "yield", rb_fiber_s_yield, -1);
    rb_define_method(rb_cFiber, "initialize", rb_fiber_init, 0);
    rb_define_method(rb_cFiber, "resume", rb_fiber_m_resume, -1);
}

RUBY_SYMBOL_EXPORT_BEGIN

void
ruby_Init_Continuation_body(void)
{
    rb_cContinuation = rb_define_class("Continuation", rb_cObject);
    rb_undef_alloc_func(rb_cContinuation);
    rb_undef_method(CLASS_OF(rb_cContinuation), "new");
    rb_define_method(rb_cContinuation, "call", rb_cont_call, -1);
    rb_define_method(rb_cContinuation, "[]", rb_cont_call, -1);
    rb_define_global_function("callcc", rb_callcc, 0);
}

void
ruby_Init_Fiber_as_Coroutine(void)
{
    rb_define_method(rb_cFiber, "transfer", rb_fiber_m_transfer, -1);
    rb_define_method(rb_cFiber, "alive?", rb_fiber_alive_p, 0);
    rb_define_singleton_method(rb_cFiber, "current", rb_fiber_s_current, 0);
}

RUBY_SYMBOL_EXPORT_END
