/*
 * Thread from eval.c
 */

#include "eval_intern.h"

#ifdef __ia64__
#if defined(__FreeBSD__)
/*
 * FreeBSD/ia64 currently does not have a way for a process to get the
 * base address for the RSE backing store, so hardcode it.
 */
#define __libc_ia64_register_backing_store_base (4ULL<<61)
#else
#if defined(HAVE_UNWIND_H) && defined(HAVE__UNW_CREATECONTEXTFORSELF)
#include <unwind.h>
#else
#pragma weak __libc_ia64_register_backing_store_base
extern unsigned long __libc_ia64_register_backing_store_base;
#endif
#endif
#endif

/* Windows SEH refers data on the stack. */
#undef SAVE_WIN32_EXCEPTION_LIST
#if defined _WIN32 || defined __CYGWIN__
#if defined __CYGWIN__
typedef unsigned long DWORD;
#endif

static inline DWORD
win32_get_exception_list()
{
    DWORD p;
# if defined _MSC_VER
#   ifdef _M_IX86
#   define SAVE_WIN32_EXCEPTION_LIST
#   if _MSC_VER >= 1310
    /* warning: unsafe assignment to fs:0 ... this is ok */
#     pragma warning(disable: 4733)
#   endif
    __asm mov eax, fs:[0];
    __asm mov p, eax;
#   endif
# elif defined __GNUC__
#   ifdef __i386__
#   define SAVE_WIN32_EXCEPTION_LIST
  __asm__("movl %%fs:0,%0":"=r"(p));
#   endif
# elif defined __BORLANDC__
#   define SAVE_WIN32_EXCEPTION_LIST
    __emit__(0x64, 0xA1, 0, 0, 0, 0);	/* mov eax, fs:[0] */
    p = _EAX;
# endif
    return p;
}

static inline void
win32_set_exception_list(p)
    DWORD p;
{
# if defined _MSC_VER
#   ifdef _M_IX86
    __asm mov eax, p;
    __asm mov fs:[0], eax;
#   endif
# elif defined __GNUC__
#   ifdef __i386__
    __asm__("movl %0,%%fs:0"::"r"(p));
#   endif
# elif defined __BORLANDC__
    _EAX = p;
    __emit__(0x64, 0xA3, 0, 0, 0, 0);	/* mov fs:[0], eax */
# endif
}

#if !defined SAVE_WIN32_EXCEPTION_LIST && !defined _WIN32_WCE
# error unsupported platform
#endif
#endif

int rb_thread_pending = 0;

VALUE rb_cThread;

extern VALUE rb_last_status;

#define WAIT_FD		(1<<0)
#define WAIT_SELECT	(1<<1)
#define WAIT_TIME	(1<<2)
#define WAIT_JOIN	(1<<3)
#define WAIT_PID	(1<<4)

/* +infty, for this purpose */
#define DELAY_INFTY 1E30


#ifdef NFDBITS
void
rb_fd_init(fds)
    volatile rb_fdset_t *fds;
{
    fds->maxfd = 0;
    fds->fdset = ALLOC(fd_set);
    FD_ZERO(fds->fdset);
}

void
rb_fd_term(fds)
    rb_fdset_t *fds;
{
    if (fds->fdset)
	free(fds->fdset);
    fds->maxfd = 0;
    fds->fdset = 0;
}

void
rb_fd_zero(fds)
    rb_fdset_t *fds;
{
    if (fds->fdset) {
	MEMZERO(fds->fdset, fd_mask, howmany(fds->maxfd, NFDBITS));
	FD_ZERO(fds->fdset);
    }
}

static void
rb_fd_resize(n, fds)
    int n;
    rb_fdset_t *fds;
{
    int m = howmany(n + 1, NFDBITS) * sizeof(fd_mask);
    int o = howmany(fds->maxfd, NFDBITS) * sizeof(fd_mask);

    if (m < sizeof(fd_set))
	m = sizeof(fd_set);
    if (o < sizeof(fd_set))
	o = sizeof(fd_set);

    if (m > o) {
	fds->fdset = realloc(fds->fdset, m);
	memset((char *)fds->fdset + o, 0, m - o);
    }
    if (n >= fds->maxfd)
	fds->maxfd = n + 1;
}

void
rb_fd_set(n, fds)
    int n;
    rb_fdset_t *fds;
{
    rb_fd_resize(n, fds);
    FD_SET(n, fds->fdset);
}

void
rb_fd_clr(n, fds)
    int n;
    rb_fdset_t *fds;
{
    if (n >= fds->maxfd)
	return;
    FD_CLR(n, fds->fdset);
}

int
rb_fd_isset(n, fds)
    int n;
    const rb_fdset_t *fds;
{
    if (n >= fds->maxfd)
	return 0;
    return FD_ISSET(n, fds->fdset);
}

void
rb_fd_copy(dst, src, max)
    rb_fdset_t *dst;
    const fd_set *src;
    int max;
{
    int size = howmany(max, NFDBITS) * sizeof(fd_mask);

    if (size < sizeof(fd_set))
	size = sizeof(fd_set);
    dst->maxfd = max;
    dst->fdset = realloc(dst->fdset, size);
    memcpy(dst->fdset, src, size);
}

int
rb_fd_select(n, readfds, writefds, exceptfds, timeout)
    int n;
    rb_fdset_t *readfds, *writefds, *exceptfds;
    struct timeval *timeout;
{
    rb_fd_resize(n - 1, readfds);
    rb_fd_resize(n - 1, writefds);
    rb_fd_resize(n - 1, exceptfds);
    return select(n, rb_fd_ptr(readfds), rb_fd_ptr(writefds),
		  rb_fd_ptr(exceptfds), timeout);
}

#undef FD_ZERO
#undef FD_SET
#undef FD_CLR
#undef FD_ISSET

#define FD_ZERO(f)	rb_fd_zero(f)
#define FD_SET(i, f)	rb_fd_set(i, f)
#define FD_CLR(i, f)	rb_fd_clr(i, f)
#define FD_ISSET(i, f)	rb_fd_isset(i, f)

#endif

/* typedef struct thread * rb_thread_t; */

struct thread {
    /* obsolete */
    struct thread *next, *prev;
    rb_jmpbuf_t context;
#ifdef SAVE_WIN32_EXCEPTION_LIST
    DWORD win32_exception_list;
#endif

    VALUE result;

    long stk_len;
    long stk_max;
    VALUE *stk_ptr;
    VALUE *stk_pos;
#ifdef __ia64__
    VALUE *bstr_ptr;
    long bstr_len;
#endif

    struct FRAME *frame;
    struct SCOPE *scope;
    struct RVarmap *dyna_vars;
    struct BLOCK *block;
    struct iter *iter;
    struct tag *tag;
    VALUE klass;
    VALUE wrapper;
    NODE *cref;
    struct ruby_env *anchor;

    int flags;			/* misc. states (vmode/rb_trap_immediate/raised) */

    NODE *node;

    int tracing;
    VALUE errinfo;
    VALUE last_status;
    VALUE last_line;
    VALUE last_match;

    int safe;

    enum yarv_thread_status status;
    int wait_for;
    int fd;
    rb_fdset_t readfds;
    rb_fdset_t writefds;
    rb_fdset_t exceptfds;
    int select_value;
    double delay;
    rb_thread_t join;

    int abort;
    int priority;
    VALUE thgroup;

    st_table *locals;

    VALUE thread;
};

#define THREAD_RAISED 0x200	/* temporary flag */
#define THREAD_TERMINATING 0x400	/* persistent flag */
#define THREAD_FLAGS_MASK  0x400	/* mask for persistent flags */

#define FOREACH_THREAD_FROM(f,x) x = f; do { x = x->next;
#define END_FOREACH_FROM(f,x) } while (x != f)

#define FOREACH_THREAD(x) FOREACH_THREAD_FROM(curr_thread,x)
#define END_FOREACH(x)    END_FOREACH_FROM(curr_thread,x)

struct thread_status_t {
    NODE *node;

    int tracing;
    VALUE errinfo;
    VALUE last_status;
    VALUE last_line;
    VALUE last_match;

    int safe;

    enum yarv_thread_status status;
    int wait_for;
    int fd;
    rb_fdset_t readfds;
    rb_fdset_t writefds;
    rb_fdset_t exceptfds;
    int select_value;
    double delay;
    rb_thread_t join;
};

#define THREAD_COPY_STATUS(src, dst) (void)(	\
    (dst)->node = (src)->node,			\
						\
    (dst)->tracing = (src)->tracing,		\
    (dst)->errinfo = (src)->errinfo,		\
    (dst)->last_status = (src)->last_status,	\
    (dst)->last_line = (src)->last_line,	\
    (dst)->last_match = (src)->last_match,	\
						\
    (dst)->safe = (src)->safe,			\
						\
    (dst)->status = (src)->status,		\
    (dst)->wait_for = (src)->wait_for,		\
    (dst)->fd = (src)->fd,			\
    (dst)->readfds = (src)->readfds,		\
    (dst)->writefds = (src)->writefds,		\
    (dst)->exceptfds = (src)->exceptfds,	\
    rb_fd_init(&(src)->readfds),		\
    rb_fd_init(&(src)->writefds),		\
    rb_fd_init(&(src)->exceptfds),		\
    (dst)->select_value = (src)->select_value,	\
    (dst)->delay = (src)->delay,		\
    (dst)->join = (src)->join,			\
    0)

int
thread_set_raised(yarv_thread_t *th)
{
    if (th->raised_flag) {
	return 1;
    }
    th->raised_flag = 1;
    return 0;
}

int
thread_reset_raised(yarv_thread_t *th)
{
    if (th->raised_flag == 0) {
	return 0;
    }
    th->raised_flag = 0;
    return 1;
}

void
rb_thread_fd_close(fd)
    int fd;
{
    // TODO: fix me
}

VALUE
rb_thread_current()
{
    return GET_THREAD()->self;
}

static rb_thread_t
rb_thread_alloc(klass)
    VALUE klass;
{
    UNSUPPORTED(rb_thread_alloc);
    return 0;
}

static VALUE
rb_thread_start_0(fn, arg, th)
    VALUE (*fn) ();
    void *arg;
    rb_thread_t th;
{
    rb_bug("unsupported: rb_thread_start_0");
    return 0;			/* not reached */
}

VALUE
rb_thread_create(VALUE (*fn) (), void *arg)
{
    Init_stack((VALUE *)&arg);
    return rb_thread_start_0(fn, arg, rb_thread_alloc(rb_cThread));
}

/*
 *  call-seq:
 *     Thread.new([arg]*) {|args| block }   => thread
 *  
 *  Creates and runs a new thread to execute the instructions given in
 *  <i>block</i>. Any arguments passed to <code>Thread::new</code> are passed
 *  into the block.
 *     
 *     x = Thread.new { sleep 0.1; print "x"; print "y"; print "z" }
 *     a = Thread.new { print "a"; print "b"; sleep 0.2; print "c" }
 *     x.join # Let the threads finish before
 *     a.join # main thread exits...
 *     
 *  <em>produces:</em>
 *     
 *     abxyzc
 */

/*
 *  call-seq:
 *     Thread.new([arg]*) {|args| block }   => thread
 *  
 *  Creates and runs a new thread to execute the instructions given in
 *  <i>block</i>. Any arguments passed to <code>Thread::new</code> are passed
 *  into the block.
 *     
 *     x = Thread.new { sleep 0.1; print "x"; print "y"; print "z" }
 *     a = Thread.new { print "a"; print "b"; sleep 0.2; print "c" }
 *     x.join # Let the threads finish before
 *     a.join # main thread exits...
 *     
 *  <em>produces:</em>
 *     
 *     abxyzc
 */

/*
 *  call-seq:
 *     Thread.start([args]*) {|args| block }   => thread
 *     Thread.fork([args]*) {|args| block }    => thread
 *  
 *  Basically the same as <code>Thread::new</code>. However, if class
 *  <code>Thread</code> is subclassed, then calling <code>start</code> in that
 *  subclass will not invoke the subclass's <code>initialize</code> method.
 */

int rb_thread_critical;


/*
 *  call-seq:
 *     Thread.critical   => true or false
 *  
 *  Returns the status of the global ``thread critical'' condition.
 */


/*
 *  call-seq:
 *     Thread.critical= boolean   => true or false
 *  
 *  Sets the status of the global ``thread critical'' condition and returns
 *  it. When set to <code>true</code>, prohibits scheduling of any existing
 *  thread. Does not block new threads from being created and run. Certain
 *  thread operations (such as stopping or killing a thread, sleeping in the
 *  current thread, and raising an exception) may cause a thread to be scheduled
 *  even when in a critical section.  <code>Thread::critical</code> is not
 *  intended for daily use: it is primarily there to support folks writing
 *  threading libraries.
 */


/*
 *  Document-class: Continuation
 *
 *  Continuation objects are generated by
 *  <code>Kernel#callcc</code>. They hold a return address and execution
 *  context, allowing a nonlocal return to the end of the
 *  <code>callcc</code> block from anywhere within a program.
 *  Continuations are somewhat analogous to a structured version of C's
 *  <code>setjmp/longjmp</code> (although they contain more state, so
 *  you might consider them closer to threads).
 *     
 *  For instance:
 *     
 *     arr = [ "Freddie", "Herbie", "Ron", "Max", "Ringo" ]
 *     callcc{|$cc|}
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
 *  This (somewhat contrived) example allows the inner loop to abandon
 *  processing early:
 *     
 *     callcc {|cont|
 *       for i in 0..4
 *         print "\n#{i}: "
 *         for j in i*5...(i+1)*5
 *           cont.call() if j == 17
 *           printf "%3d", j
 *         end
 *       end
 *     }
 *     print "\n"
 *     
 *  <em>produces:</em>
 *     
 *     0:   0  1  2  3  4
 *     1:   5  6  7  8  9
 *     2:  10 11 12 13 14
 *     3:  15 16
 */

VALUE rb_cCont;

/*
 *  call-seq:
 *     callcc {|cont| block }   =>  obj
 *  
 *  Generates a <code>Continuation</code> object, which it passes to the
 *  associated block. Performing a <em>cont</em><code>.call</code> will
 *  cause the <code>callcc</code> to return (as will falling through the
 *  end of the block). The value returned by the <code>callcc</code> is
 *  the value of the block, or the value passed to
 *  <em>cont</em><code>.call</code>. See class <code>Continuation</code>
 *  for more details. Also see <code>Kernel::throw</code> for
 *  an alternative mechanism for unwinding a call stack.
 */

static VALUE
rb_callcc(self)
    VALUE self;
{
    UNSUPPORTED(rb_callcc);
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
rb_cont_call(argc, argv, cont)
    int argc;
    VALUE *argv;
    VALUE cont;
{
    UNSUPPORTED(rb_cont_call);
}


/* variables for recursive traversals */
static ID recursive_key;


/*
 *  +Thread+ encapsulates the behavior of a thread of
 *  execution, including the main thread of the Ruby script.
 *     
 *  In the descriptions of the methods in this class, the parameter _sym_
 *  refers to a symbol, which is either a quoted string or a
 *  +Symbol+ (such as <code>:name</code>).
 */

void
Init_Thread()
{
    recursive_key = rb_intern("__recursive_key__");
    rb_eThreadError = rb_define_class("ThreadError", rb_eStandardError);
    rb_cCont = rb_define_class("Continuation", rb_cObject);
}

static VALUE
recursive_check(obj)
    VALUE obj;
{
    VALUE hash = rb_thread_local_aref(rb_thread_current(), recursive_key);

    if (NIL_P(hash) || TYPE(hash) != T_HASH) {
	return Qfalse;
    }
    else {
	VALUE list = rb_hash_aref(hash, ID2SYM(rb_frame_this_func()));

	if (NIL_P(list) || TYPE(list) != T_ARRAY)
	    return Qfalse;
	return rb_ary_includes(list, rb_obj_id(obj));
    }
}

static void
recursive_push(obj)
    VALUE obj;
{
    VALUE hash = rb_thread_local_aref(rb_thread_current(), recursive_key);
    VALUE list, sym;

    sym = ID2SYM(rb_frame_this_func());
    if (NIL_P(hash) || TYPE(hash) != T_HASH) {
	hash = rb_hash_new();
	rb_thread_local_aset(rb_thread_current(), recursive_key, hash);
	list = Qnil;
    }
    else {
	list = rb_hash_aref(hash, sym);
    }
    if (NIL_P(list) || TYPE(list) != T_ARRAY) {
	list = rb_ary_new();
	rb_hash_aset(hash, sym, list);
    }
    rb_ary_push(list, rb_obj_id(obj));
}

static void
recursive_pop()
{
    VALUE hash = rb_thread_local_aref(rb_thread_current(), recursive_key);
    VALUE list, sym;

    sym = ID2SYM(rb_frame_this_func());
    if (NIL_P(hash) || TYPE(hash) != T_HASH) {
	VALUE symname;
	VALUE thrname;
	symname = rb_inspect(sym);
	thrname = rb_inspect(rb_thread_current());

	rb_raise(rb_eTypeError, "invalid inspect_tbl hash for %s in %s",
		 StringValuePtr(symname), StringValuePtr(thrname));
    }
    list = rb_hash_aref(hash, sym);
    if (NIL_P(list) || TYPE(list) != T_ARRAY) {
	VALUE symname = rb_inspect(sym);
	VALUE thrname = rb_inspect(rb_thread_current());
	rb_raise(rb_eTypeError, "invalid inspect_tbl list for %s in %s",
		 StringValuePtr(symname), StringValuePtr(thrname));
    }
    rb_ary_pop(list);
}

VALUE
rb_exec_recursive(VALUE (*func) (VALUE, VALUE, int), VALUE obj, VALUE arg)
{
    if (recursive_check(obj)) {
	return (*func) (obj, arg, Qtrue);
    }
    else {
	VALUE result = Qundef;
	int state;

	recursive_push(obj);
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    result = (*func) (obj, arg, Qfalse);
	}
	POP_TAG();
	recursive_pop();
	if (state)
	    JUMP_TAG(state);
	return result;
    }
}

/* flush_register_windows must not be inlined because flushrs doesn't flush
 * current frame in register stack. */
#ifdef __ia64__
void
flush_register_windows(void)
{
    __asm__("flushrs");
}
#endif
