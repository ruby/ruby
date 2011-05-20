/**********************************************************************

  eval.c -

  $Author$
  $Date$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "node.h"
#include "env.h"
#include "util.h"
#include "rubysig.h"

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
# endif /* atarist */
#else
# ifdef HAVE_ALLOCA_H
#  include <alloca.h>
# else
#  ifndef _AIX
#   ifndef alloca /* predefined by HP cc +Olibcalls */
void *alloca ();
#   endif
#  endif /* AIX */
# endif /* HAVE_ALLOCA_H */
#endif /* __GNUC__ */

#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif

#ifndef HAVE_STRING_H
char *strrchr _((const char*,const char));
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#include <time.h>

#if defined(HAVE_FCNTL_H) || defined(_WIN32)
#include <fcntl.h>
#elif defined(HAVE_SYS_FCNTL_H)
#include <sys/fcntl.h>
#endif
#ifdef __CYGWIN__
#include <io.h>
#endif

#if defined(__BEOS__) && !defined(BONE)
#include <net/socket.h>
#endif

#ifdef __MACOS__
#include "macruby_private.h"
#endif

#ifdef __VMS
#include "vmsruby_private.h"
#endif

#if STACK_GROW_DIRECTION > 0
# define STACK_UPPER(x, a, b) a
#elif STACK_GROW_DIRECTION < 0
# define STACK_UPPER(x, a, b) b
#else
int rb_stack_growup_p _((VALUE *addr));
# define STACK_UPPER(x, a, b) (rb_stack_growup_p(x) ? a : b)
#endif

#ifdef USE_CONTEXT

NORETURN(static void rb_jump_context(rb_jmpbuf_t, int));
static inline void
rb_jump_context(env, val)
    rb_jmpbuf_t env;
    int val;
{
    env->status = val;
    setcontext(&env->context);
    abort();			/* ensure noreturn */
}
/*
 * PRE_GETCONTEXT and POST_GETCONTEXT is a magic for getcontext, gcc,
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
 * So setjmp calls before and after the getcontext call makes the code
 * somewhat safe.
 * It fix the problem on IA64.
 * It is not required that setjmp is called at run time, since the problem is
 * register usage.
 *
 * Since the magic setjmp is not enough for SPARC,
 * inline asm is used to prohibit registers in register windows.
 *
 * Since the problem is fixed at gcc 4.0.3, the magic is applied only for
 * prior versions of gcc.
 * http://gcc.gnu.org/bugzilla/show_bug.cgi?id=21957
 * http://gcc.gnu.org/bugzilla/show_bug.cgi?id=22127
 */
#  define GCC_VERSION_BEFORE(major, minor, patchlevel) \
    (defined(__GNUC__) && !defined(__INTEL_COMPILER) && \
     ((__GNUC__ < (major)) ||  \
      (__GNUC__ == (major) && __GNUC_MINOR__ < (minor)) || \
      (__GNUC__ == (major) && __GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ < (patchlevel))))
#  if GCC_VERSION_BEFORE(4,0,3) && (defined(sparc) || defined(__sparc__))
#    ifdef __pic__
/*
 * %l7 is excluded for PIC because it is PIC register.
 * http://lists.freebsd.org/pipermail/freebsd-sparc64/2006-January/003739.html
 */
#      define PRE_GETCONTEXT \
	 ({ __asm__ volatile ("" : : :  \
	    "%o0", "%o1", "%o2", "%o3", "%o4", "%o5", "%o7", \
	    "%l0", "%l1", "%l2", "%l3", "%l4", "%l5", "%l6", \
	    "%i0", "%i1", "%i2", "%i3", "%i4", "%i5", "%i7"); })
#    else
#      define PRE_GETCONTEXT \
	 ({ __asm__ volatile ("" : : :  \
	    "%o0", "%o1", "%o2", "%o3", "%o4", "%o5", "%o7", \
	    "%l0", "%l1", "%l2", "%l3", "%l4", "%l5", "%l6", "%l7", \
	    "%i0", "%i1", "%i2", "%i3", "%i4", "%i5", "%i7"); })
#    endif
#    define POST_GETCONTEXT PRE_GETCONTEXT
#  elif GCC_VERSION_BEFORE(4,0,3) && defined(__ia64)
static jmp_buf function_call_may_return_twice_jmp_buf;
int function_call_may_return_twice_false_1 = 0;
int function_call_may_return_twice_false_2 = 0;
#    define PRE_GETCONTEXT \
       (function_call_may_return_twice_false_1 ? \
        setjmp(function_call_may_return_twice_jmp_buf) : \
        0)
#    define POST_GETCONTEXT \
       (function_call_may_return_twice_false_2 ? \
        setjmp(function_call_may_return_twice_jmp_buf) : \
        0)
#  elif defined(__FreeBSD__) && __FreeBSD__ < 7
/*
 * workaround for FreeBSD/i386 getcontext/setcontext bug.
 * clear the carry flag by (0 ? ... : ...).
 * FreeBSD PR 92110 http://www.freebsd.org/cgi/query-pr.cgi?pr=92110
 * [ruby-dev:28263]
 */
static int volatile freebsd_clear_carry_flag = 0;
#    define PRE_GETCONTEXT \
       (freebsd_clear_carry_flag ? (freebsd_clear_carry_flag = 0) : 0)
#  endif
#  ifndef PRE_GETCONTEXT
#    define PRE_GETCONTEXT 0
#  endif
#  ifndef POST_GETCONTEXT
#    define POST_GETCONTEXT 0
#  endif
#  define ruby_longjmp(env, val) rb_jump_context(env, val)
#  define ruby_setjmp(just_before_setjmp, j) ((j)->status = 0, \
     (just_before_setjmp), \
     PRE_GETCONTEXT, \
     getcontext(&(j)->context), \
     POST_GETCONTEXT, \
     (j)->status)
#else
#  define ruby_setjmp(just_before_setjmp, env) \
     ((just_before_setjmp), RUBY_SETJMP(env))
#  define ruby_longjmp(env,val) RUBY_LONGJMP(env,val)
#  ifdef __CYGWIN__
#    ifndef _setjmp
int _setjmp _((jmp_buf));
#    endif
#    ifndef _longjmp
NORETURN(void _longjmp _((jmp_buf, int)));
#    endif
#  endif
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

#include <sys/stat.h>

VALUE rb_cProc;
VALUE rb_cBinding;
static VALUE proc_invoke _((VALUE,VALUE,VALUE,VALUE));
static VALUE rb_f_binding _((VALUE));
static void rb_f_END _((void));
static VALUE rb_f_block_given_p _((void));
static VALUE block_pass _((VALUE,NODE*));
static void eval_check_tick _((void));

VALUE rb_cMethod;
static VALUE method_call _((int, VALUE*, VALUE));
VALUE rb_cUnboundMethod;
static VALUE umethod_bind _((VALUE, VALUE));
static VALUE rb_mod_define_method _((int, VALUE*, VALUE));
NORETURN(static void rb_raise_jump _((VALUE)));
static VALUE rb_make_exception _((int argc, VALUE *argv));

static int scope_vmode;
#define SCOPE_PUBLIC    0
#define SCOPE_PRIVATE   1
#define SCOPE_PROTECTED 2
#define SCOPE_MODFUNC   5
#define SCOPE_MASK      7
#define SCOPE_SET(f)  (scope_vmode=(f))
#define SCOPE_TEST(f) (scope_vmode&(f))

VALUE (*ruby_sandbox_save)_((rb_thread_t));
VALUE (*ruby_sandbox_restore)_((rb_thread_t));
NODE* ruby_current_node;
int ruby_safe_level = 0;
/* safe-level:
   0 - strings from streams/environment/ARGV are tainted (default)
   1 - no dangerous operation by tainted value
   2 - process/file operations prohibited
   3 - all generated objects are tainted
   4 - no global (non-tainted) variable modification/no direct output
*/

static VALUE safe_getter _((void));
static void safe_setter _((VALUE val));

void
rb_secure(level)
    int level;
{
    if (level <= ruby_safe_level) {
	if (ruby_frame->last_func) {
	    rb_raise(rb_eSecurityError, "Insecure operation `%s' at level %d",
		     rb_id2name(ruby_frame->last_func), ruby_safe_level);
	}
	else {
	    rb_raise(rb_eSecurityError, "Insecure operation at level %d", ruby_safe_level);
	}
    }
}

void
rb_secure_update(obj)
    VALUE obj;
{
    if (!OBJ_TAINTED(obj)) rb_secure(4);
}

void
rb_check_safe_obj(x)
    VALUE x;
{
    if (ruby_safe_level > 0 && OBJ_TAINTED(x)){
	if (ruby_frame->last_func) {
	    rb_raise(rb_eSecurityError, "Insecure operation - %s",
		     rb_id2name(ruby_frame->last_func));
	}
	else {
	    rb_raise(rb_eSecurityError, "Insecure operation: -r");
	}
    }
    rb_secure(4);
}

void
rb_check_safe_str(x)
    VALUE x;
{
    rb_check_safe_obj(x);
    if (TYPE(x)!= T_STRING) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected String)",
		 rb_obj_classname(x));
    }
}

NORETURN(static void print_undef _((VALUE, ID)));
static void
print_undef(klass, id)
    VALUE klass;
    ID id;
{
    rb_name_error(id, "undefined method `%s' for %s `%s'",
		  rb_id2name(id),
		  (TYPE(klass) == T_MODULE) ? "module" : "class",
		  rb_class2name(klass));
}

static ID removed, singleton_removed, undefined, singleton_undefined;

#define CACHE_SIZE 0x800
#define CACHE_MASK 0x7ff
#define EXPR1(c,m) ((((c)>>3)^(m))&CACHE_MASK)

struct cache_entry {		/* method hash table. */
    ID mid;			/* method's id */
    ID mid0;			/* method's original id */
    VALUE klass;		/* receiver's class */
    VALUE origin;		/* where method defined  */
    NODE *method;
    int noex;
};

static struct cache_entry cache[CACHE_SIZE];
static int ruby_running = 0;

void
rb_clear_cache()
{
   struct cache_entry *ent, *end;

    if (!ruby_running) return;
    ent = cache; end = ent + CACHE_SIZE;
    while (ent < end) {
	ent->mid = 0;
	ent++;
    }
}

static void
rb_clear_cache_for_undef(klass, id)
    VALUE klass;
    ID id;
{
    struct cache_entry *ent, *end;

    if (!ruby_running) return;
    ent = cache; end = ent + CACHE_SIZE;
    while (ent < end) {
	if (ent->mid == id &&
	    (ent->klass == klass ||
	     RCLASS(ent->origin)->m_tbl == RCLASS(klass)->m_tbl)) {
	    ent->mid = 0;
	}
	ent++;
    }
}

static void
rb_clear_cache_by_id(id)
    ID id;
{
    struct cache_entry *ent, *end;

    if (!ruby_running) return;
    ent = cache; end = ent + CACHE_SIZE;
    while (ent < end) {
	if (ent->mid == id) {
	    ent->mid = 0;
	}
	ent++;
    }
}

void
rb_clear_cache_by_class(klass)
    VALUE klass;
{
    struct cache_entry *ent, *end;

    if (!ruby_running) return;
    ent = cache; end = ent + CACHE_SIZE;
    while (ent < end) {
	if (ent->klass == klass || ent->origin == klass) {
	    ent->mid = 0;
	}
	ent++;
    }
}

static ID init, eqq, each, aref, aset, match, missing;
static ID added, singleton_added;
static ID __id__, __send__, respond_to;

#define NOEX_TAINTED 8
#define NOEX_SAFE(n) ((n) >> 4)
#define NOEX_WITH(n, v) ((n) | (v) << 4)
#define NOEX_WITH_SAFE(n) NOEX_WITH(n, ruby_safe_level)

void
rb_add_method(klass, mid, node, noex)
    VALUE klass;
    ID mid;
    NODE *node;
    int noex;
{
    NODE *body;

    if (NIL_P(klass)) klass = rb_cObject;
    if (ruby_safe_level >= 4 && (klass == rb_cObject || !OBJ_TAINTED(klass))) {
	rb_raise(rb_eSecurityError, "Insecure: can't define method");
    }
    if (!FL_TEST(klass, FL_SINGLETON) &&
	node && nd_type(node) != NODE_ZSUPER &&
	(mid == rb_intern("initialize" )|| mid == rb_intern("initialize_copy"))) {
	noex = NOEX_PRIVATE | noex;
    }
    else if (FL_TEST(klass, FL_SINGLETON) && node && nd_type(node) == NODE_CFUNC &&
	     mid == rb_intern("allocate")) {
	rb_warn("defining %s.allocate is deprecated; use rb_define_alloc_func()",
		rb_class2name(rb_iv_get(klass, "__attached__")));
	mid = ID_ALLOCATOR;
    }
    if (OBJ_FROZEN(klass)) rb_error_frozen("class/module");
    rb_clear_cache_by_id(mid);
    body = NEW_METHOD(node, NOEX_WITH_SAFE(noex));
    st_insert(RCLASS(klass)->m_tbl, mid, (st_data_t)body);
    if (node && mid != ID_ALLOCATOR && ruby_running) {
	if (FL_TEST(klass, FL_SINGLETON)) {
	    rb_funcall(rb_iv_get(klass, "__attached__"), singleton_added, 1, ID2SYM(mid));
	}
	else {
	    rb_funcall(klass, added, 1, ID2SYM(mid));
	}
    }
}

void
rb_define_alloc_func(klass, func)
    VALUE klass;
    VALUE (*func) _((VALUE));
{
    Check_Type(klass, T_CLASS);
    rb_add_method(rb_singleton_class(klass), ID_ALLOCATOR, NEW_CFUNC(func, 0),
		  NOEX_PRIVATE);
}

void
rb_undef_alloc_func(klass)
    VALUE klass;
{
    Check_Type(klass, T_CLASS);
    rb_add_method(rb_singleton_class(klass), ID_ALLOCATOR, 0, NOEX_UNDEF);
}

static NODE*
search_method(klass, id, origin)
    VALUE klass, *origin;
    ID id;
{
    st_data_t body;

    if (!klass) return 0;
    while (!st_lookup(RCLASS(klass)->m_tbl, id, &body)) {
	klass = RCLASS(klass)->super;
	if (!klass) return 0;
    }

    if (origin) *origin = klass;
    return (NODE *)body;
}

static NODE*
rb_get_method_body(klassp, idp, noexp)
    VALUE *klassp;
    ID *idp;
    int *noexp;
{
    ID id = *idp;
    VALUE klass = *klassp;
    VALUE origin = 0;
    NODE * volatile body;
    struct cache_entry *ent;

    if ((body = search_method(klass, id, &origin)) == 0 || !body->nd_body) {
	/* store empty info in cache */
	ent = cache + EXPR1(klass, id);
	ent->klass  = klass;
	ent->origin = klass;
	ent->mid = ent->mid0 = id;
	ent->noex   = 0;
	ent->method = 0;

	return 0;
    }

    if (ruby_running) {
	/* store in cache */
	ent = cache + EXPR1(klass, id);
	ent->klass  = klass;
	ent->noex   = body->nd_noex;
	if (noexp) *noexp = body->nd_noex;
	body = body->nd_body;
	if (nd_type(body) == NODE_FBODY) {
	    ent->mid = id;
	    *klassp = body->nd_orig;
	    ent->origin = body->nd_orig;
	    *idp = ent->mid0 = body->nd_mid;
	    body = ent->method = body->nd_head;
	}
	else {
	    *klassp = origin;
	    ent->origin = origin;
	    ent->mid = ent->mid0 = id;
	    ent->method = body;
	}
    }
    else {
	if (noexp) *noexp = body->nd_noex;
	body = body->nd_body;
	if (nd_type(body) == NODE_FBODY) {
	    *klassp = body->nd_orig;
	    *idp = body->nd_mid;
	    body = body->nd_head;
	}
	else {
	    *klassp = origin;
	}
    }

    return body;
}

NODE*
rb_method_node(klass, id)
    VALUE klass;
    ID id;
{
    int noex;

    return rb_get_method_body(&klass, &id, &noex);
}

static void
remove_method(klass, mid)
    VALUE klass;
    ID mid;
{
    st_data_t data;
    NODE *body = 0;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    if (ruby_safe_level >= 4 && !OBJ_TAINTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't remove method");
    }
    if (OBJ_FROZEN(klass)) rb_error_frozen("class/module");
    if (mid == __id__ || mid == __send__ || mid == init) {
	rb_warn("removing `%s' may cause serious problem", rb_id2name(mid));
    }
    if (st_lookup(RCLASS(klass)->m_tbl, mid, &data)) {
	body = (NODE *)data;
	if (!body || !body->nd_body) body = 0;
	else {
	    st_delete(RCLASS(klass)->m_tbl, &mid, &data);
	}
    }
    if (!body) {
	rb_name_error(mid, "method `%s' not defined in %s",
		      rb_id2name(mid), rb_class2name(klass));
    }
    rb_clear_cache_for_undef(klass, mid);
    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_funcall(rb_iv_get(klass, "__attached__"), singleton_removed, 1, ID2SYM(mid));
    }
    else {
	rb_funcall(klass, removed, 1, ID2SYM(mid));
    }
}

void
rb_remove_method(klass, name)
    VALUE klass;
    const char *name;
{
    remove_method(klass, rb_intern(name));
}

/*
 *  call-seq:
 *     remove_method(symbol)   => self
 *
 *  Removes the method identified by _symbol_ from the current
 *  class. For an example, see <code>Module.undef_method</code>.
 */

static VALUE
rb_mod_remove_method(argc, argv, mod)
    int argc;
    VALUE *argv;
    VALUE mod;
{
    int i;

    for (i=0; i<argc; i++) {
	remove_method(mod, rb_to_id(argv[i]));
    }
    return mod;
}

#undef rb_disable_super
#undef rb_enable_super

void
rb_disable_super(klass, name)
    VALUE klass;
    const char *name;
{
    /* obsolete - no use */
}

void
rb_enable_super(klass, name)
    VALUE klass;
    const char *name;
{
    rb_warn("rb_enable_super() is obsolete");
}

static void
rb_export_method(klass, name, noex)
    VALUE klass;
    ID name;
    ID noex;
{
    NODE *body;
    VALUE origin = 0;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    body = search_method(klass, name, &origin);
    if (!body && TYPE(klass) == T_MODULE) {
	body = search_method(rb_cObject, name, &origin);
    }
    if (!body || !body->nd_body) {
	print_undef(klass, name);
    }
    if (body->nd_noex != noex) {
	if (klass == origin) {
	    body->nd_noex = noex;
	}
	else {
	    rb_add_method(klass, name, NEW_ZSUPER(), noex);
	}
    }
}

int
rb_method_boundp(klass, id, ex)
    VALUE klass;
    ID id;
    int ex;
{
    struct cache_entry *ent;
    int noex;

    /* is it in the method cache? */
    ent = cache + EXPR1(klass, id);
    if (ent->mid == id && ent->klass == klass) {
	if (ex && (ent->noex & NOEX_PRIVATE))
	    return Qfalse;
	if (!ent->method) return Qfalse;
	return Qtrue;
    }
    if (rb_get_method_body(&klass, &id, &noex)) {
	if (ex && (noex & NOEX_PRIVATE))
	    return Qfalse;
	return Qtrue;
    }
    return Qfalse;
}

void
rb_attr(klass, id, read, write, ex)
    VALUE klass;
    ID id;
    int read, write, ex;
{
    const char *name;
    char *buf;
    ID attriv;
    int noex;
    size_t len;

    if (!ex) noex = NOEX_PUBLIC;
    else {
	if (SCOPE_TEST(SCOPE_PRIVATE)) {
	    noex = NOEX_PRIVATE;
	    rb_warning((scope_vmode == SCOPE_MODFUNC) ?
		       "attribute accessor as module_function" :
		       "private attribute?");
	}
	else if (SCOPE_TEST(SCOPE_PROTECTED)) {
	    noex = NOEX_PROTECTED;
	}
	else {
	    noex = NOEX_PUBLIC;
	}
    }

    if (!rb_is_local_id(id) && !rb_is_const_id(id)) {
	rb_name_error(id, "invalid attribute name `%s'", rb_id2name(id));
    }
    name = rb_id2name(id);
    if (!name) {
	rb_raise(rb_eArgError, "argument needs to be symbol or string");
    }
    len = strlen(name)+2;
    buf = ALLOCA_N(char,len);
    snprintf(buf, len, "@%s", name);
    attriv = rb_intern(buf);
    if (read) {
	rb_add_method(klass, id, NEW_IVAR(attriv), noex);
    }
    if (write) {
	rb_add_method(klass, rb_id_attrset(id), NEW_ATTRSET(attriv), noex);
    }
}

extern int ruby_in_compile;

VALUE ruby_errinfo = Qnil;
extern NODE *ruby_eval_tree_begin;
extern NODE *ruby_eval_tree;
extern int ruby_nerrs;

VALUE rb_eLocalJumpError;
VALUE rb_eSysStackError;

extern VALUE ruby_top_self;

struct FRAME *ruby_frame;
struct SCOPE *ruby_scope;
static struct FRAME *top_frame;
static struct SCOPE *top_scope;

static unsigned long frame_unique = 0;

#define PUSH_FRAME() do {		\
    volatile struct FRAME _frame;	\
    _frame.prev = ruby_frame;		\
    _frame.tmp  = 0;			\
    _frame.node = ruby_current_node;	\
    _frame.iter = ruby_iter->iter;	\
    _frame.argc = 0;			\
    _frame.flags = 0;			\
    _frame.uniq = frame_unique++;	\
    ruby_frame = (struct FRAME *)&_frame

#define POP_FRAME()  			\
    ruby_current_node = _frame.node;	\
    ruby_frame = _frame.prev;		\
} while (0)

struct BLOCK {
    NODE *var;
    NODE *body;
    VALUE self;
    struct FRAME frame;
    struct SCOPE *scope;
    VALUE klass;
    NODE *cref;
    int iter;
    int vmode;
    int flags;
    int uniq;
    struct RVarmap *dyna_vars;
    VALUE orig_thread;
    VALUE wrapper;
    VALUE block_obj;
    struct BLOCK *outer;
    struct BLOCK *prev;
};

#define BLOCK_D_SCOPE 1
#define BLOCK_LAMBDA  2

static struct BLOCK *ruby_block;
static unsigned long block_unique = 1;

#define PUSH_BLOCK(v,b) do {		\
    struct BLOCK _block;		\
    _block.var = (v);			\
    _block.body = (b);			\
    _block.self = self;			\
    _block.frame = *ruby_frame;		\
    _block.klass = ruby_class;		\
    _block.cref = ruby_cref;		\
    _block.frame.node = ruby_current_node;\
    _block.scope = ruby_scope;		\
    _block.prev = ruby_block;		\
    _block.outer = ruby_block;		\
    _block.iter = ruby_iter->iter;	\
    _block.vmode = scope_vmode;		\
    _block.flags = BLOCK_D_SCOPE;	\
    _block.dyna_vars = ruby_dyna_vars;	\
    _block.wrapper = ruby_wrapper;	\
    _block.block_obj = 0;		\
    _block.uniq = (b)?block_unique++:0; \
    if (b) {				\
	prot_tag->blkid = _block.uniq;  \
    }                                   \
    ruby_block = &_block

#define POP_BLOCK() \
   ruby_block = _block.prev; \
} while (0)

struct RVarmap *ruby_dyna_vars;
#define PUSH_VARS() do { \
    struct RVarmap * volatile _old; \
    _old = ruby_dyna_vars; \
    ruby_dyna_vars = 0

#define POP_VARS() \
    if (_old && (ruby_scope->flags & SCOPE_DONT_RECYCLE)) {\
	if (RBASIC(_old)->flags) /* unless it's already recycled */ \
	    FL_SET(_old, DVAR_DONT_RECYCLE); \
    }\
    ruby_dyna_vars = _old; \
} while (0)

#define DVAR_DONT_RECYCLE FL_USER2

#define DMETHOD_P() (ruby_frame->flags & FRAME_DMETH)

static struct RVarmap*
new_dvar(id, value, prev)
    ID id;
    VALUE value;
    struct RVarmap *prev;
{
    NEWOBJ(vars, struct RVarmap);
    OBJSETUP(vars, 0, T_VARMAP);
    vars->id = id;
    vars->val = value;
    vars->next = prev;

    return vars;
}

VALUE
rb_dvar_defined(id)
    ID id;
{
    struct RVarmap *vars = ruby_dyna_vars;

    while (vars) {
	if (vars->id == id) return Qtrue;
	vars = vars->next;
    }
    return Qfalse;
}

VALUE
rb_dvar_curr(id)
    ID id;
{
    struct RVarmap *vars = ruby_dyna_vars;

    while (vars) {
	if (vars->id == 0) break;
	if (vars->id == id) return Qtrue;
	vars = vars->next;
    }
    return Qfalse;
}

VALUE
rb_dvar_ref(id)
    ID id;
{
    struct RVarmap *vars = ruby_dyna_vars;

    while (vars) {
	if (vars->id == id) {
	    return vars->val;
	}
	vars = vars->next;
    }
    return Qnil;
}

void
rb_dvar_push(id, value)
    ID id;
    VALUE value;
{
    ruby_dyna_vars = new_dvar(id, value, ruby_dyna_vars);
}

static void
dvar_asgn_internal(id, value, curr)
    ID id;
    VALUE value;
    int curr;
{
    int n = 0;
    struct RVarmap *vars = ruby_dyna_vars;

    while (vars) {
	if (curr && vars->id == 0) {
	    /* first null is a dvar header */
	    n++;
	    if (n == 2) break;
	}
	if (vars->id == id) {
	    vars->val = value;
	    return;
	}
	vars = vars->next;
    }
    if (!ruby_dyna_vars) {
	ruby_dyna_vars = new_dvar(id, value, 0);
    }
    else {
	vars = new_dvar(id, value, ruby_dyna_vars->next);
	ruby_dyna_vars->next = vars;
    }
}

static inline void
dvar_asgn(id, value)
    ID id;
    VALUE value;
{
    dvar_asgn_internal(id, value, 0);
}

static inline void
dvar_asgn_curr(id, value)
    ID id;
    VALUE value;
{
    dvar_asgn_internal(id, value, 1);
}

VALUE *
rb_svar(cnt)
    int cnt;
{
    struct RVarmap *vars = ruby_dyna_vars;
    ID id;

    if (!ruby_scope->local_tbl) return NULL;
    if (cnt >= ruby_scope->local_tbl[0]) return NULL;
    id = ruby_scope->local_tbl[cnt+1];
    while (vars) {
	if (vars->id == id) return &vars->val;
	vars = vars->next;
    }
    if (ruby_scope->local_vars == 0) return NULL;
    return &ruby_scope->local_vars[cnt];
}

struct iter {
    int iter;
    struct iter *prev;
};
static struct iter *ruby_iter;

#define ITER_NOT 0
#define ITER_PRE 1
#define ITER_CUR 2
#define ITER_PAS 3

#define PUSH_ITER(i) do {		\
    struct iter _iter;			\
    _iter.prev = ruby_iter;		\
    _iter.iter = (i);			\
    ruby_iter = &_iter

#define POP_ITER()			\
    ruby_iter = _iter.prev;		\
} while (0)

struct tag {
    rb_jmpbuf_t buf;
    struct FRAME *frame;
    struct iter *iter;
    VALUE tag;
    VALUE retval;
    struct SCOPE *scope;
    VALUE dst;
    struct tag *prev;
    int blkid;
};
static struct tag *prot_tag;

#define PUSH_TAG(ptag) do {		\
    struct tag _tag;			\
    _tag.retval = Qnil;			\
    _tag.frame = ruby_frame;		\
    _tag.iter = ruby_iter;		\
    _tag.prev = prot_tag;		\
    _tag.scope = ruby_scope;		\
    _tag.tag = ptag;			\
    _tag.dst = 0;			\
    _tag.blkid = 0;			\
    prot_tag = &_tag

#define PROT_NONE   Qfalse	/* 0 */
#define PROT_THREAD Qtrue	/* 2 */
#define PROT_FUNC   INT2FIX(0)	/* 1 */
#define PROT_LOOP   INT2FIX(1)	/* 3 */
#define PROT_LAMBDA INT2FIX(2)	/* 5 */
#define PROT_YIELD  INT2FIX(3)	/* 7 */

#define EXEC_TAG()    ruby_setjmp(((void)0), prot_tag->buf)

#define JUMP_TAG(st) do {		\
    ruby_frame = prot_tag->frame;	\
    ruby_iter = prot_tag->iter;		\
    ruby_longjmp(prot_tag->buf,(st));	\
} while (0)

#define POP_TAG()			\
    prot_tag = _tag.prev;		\
} while (0)

#define TAG_DST() (_tag.dst == (VALUE)ruby_frame->uniq)

#define TAG_RETURN	0x1
#define TAG_BREAK	0x2
#define TAG_NEXT	0x3
#define TAG_RETRY	0x4
#define TAG_REDO	0x5
#define TAG_RAISE	0x6
#define TAG_THROW	0x7
#define TAG_FATAL	0x8
#define TAG_THREAD	0xa
#define TAG_MASK	0xf

VALUE ruby_class;
static VALUE ruby_wrapper;	/* security wrapper */

#define PUSH_CLASS(c) do {		\
    volatile VALUE _class = ruby_class;	\
    ruby_class = (c)

#define POP_CLASS() ruby_class = _class; \
} while (0)

NODE *ruby_cref = 0;
NODE *ruby_top_cref;
#define PUSH_CREF(c) ruby_cref = NEW_CREF(c,ruby_cref)
#define POP_CREF() ruby_cref = ruby_cref->nd_next

#define PUSH_SCOPE() do {		\
    volatile int _vmode = scope_vmode;	\
    struct SCOPE * volatile _old;	\
    NEWOBJ(_scope, struct SCOPE);	\
    OBJSETUP(_scope, 0, T_SCOPE);	\
    _scope->local_tbl = 0;		\
    _scope->local_vars = 0;		\
    _scope->flags = 0;			\
    _old = ruby_scope;			\
    ruby_scope = _scope;		\
    scope_vmode = SCOPE_PUBLIC

rb_thread_t rb_curr_thread;
rb_thread_t rb_main_thread;
#define main_thread rb_main_thread
#define curr_thread rb_curr_thread

static void scope_dup _((struct SCOPE *));

#define POP_SCOPE() 			\
    if (ruby_scope->flags & SCOPE_DONT_RECYCLE) {\
	if (_old) scope_dup(_old);	\
    }					\
    if (!(ruby_scope->flags & SCOPE_MALLOC)) {\
	ruby_scope->local_vars = 0;	\
	ruby_scope->local_tbl  = 0;	\
	if (!(ruby_scope->flags & SCOPE_DONT_RECYCLE) && \
	    ruby_scope != top_scope) {	\
	    rb_gc_force_recycle((VALUE)ruby_scope);\
	}				\
    }					\
    ruby_scope->flags |= SCOPE_NOSTACK;	\
    ruby_scope = _old;			\
    scope_vmode = _vmode;		\
} while (0)

struct ruby_env {
    struct ruby_env *prev;
    struct FRAME *frame;
    struct SCOPE *scope;
    struct BLOCK *block;
    struct iter *iter;
    struct tag *tag;
    NODE *cref;
};

static void push_thread_anchor _((struct ruby_env *));
static void pop_thread_anchor _((struct ruby_env *));

#define PUSH_ANCHOR() PUSH_TAG(PROT_NONE);	 \
    do {					 \
	struct ruby_env _interp;		 \
	push_thread_anchor(&_interp);
#define POP_ANCHOR()				 \
	pop_thread_anchor(&_interp);		 \
    } while (0);				 \
    POP_TAG()

static VALUE rb_eval _((VALUE,NODE*));
static VALUE eval _((VALUE,VALUE,VALUE,const char*,int));
static NODE *compile _((VALUE, const char*, int));

static VALUE rb_yield_0 _((VALUE, VALUE, VALUE, int, int));

#define YIELD_LAMBDA_CALL 1
#define YIELD_PROC_CALL   2
#define YIELD_PUBLIC_DEF  4
#define YIELD_FUNC_AVALUE 1
#define YIELD_FUNC_SVALUE 2
#define YIELD_FUNC_LAMBDA 3

static VALUE rb_call _((VALUE,VALUE,ID,int,const VALUE*,int,VALUE));
static VALUE module_setup _((VALUE,NODE*));

static VALUE massign _((VALUE,NODE*,VALUE,int));
static void assign _((VALUE,NODE*,VALUE,int));

typedef struct event_hook {
    rb_event_hook_func_t func;
    rb_event_t events;
    struct event_hook *next;
} rb_event_hook_t;

static rb_event_hook_t *event_hooks;

#define EXEC_EVENT_HOOK(event, node, self, id, klass) \
    do { \
	rb_event_hook_t *hook = event_hooks; \
        rb_event_hook_func_t hook_func; \
        rb_event_t events; \
	\
	while (hook) { \
            hook_func = hook->func; \
            events = hook->events; \
            hook = hook->next; \
	    if (events & event) \
		(*hook_func)(event, node, self, id, klass); \
	} \
    } while (0)

static VALUE trace_func = 0;
static int tracing = 0;
static void call_trace_func _((rb_event_t,NODE*,VALUE,ID,VALUE));

#if 0
#define SET_CURRENT_SOURCE() (ruby_sourcefile = ruby_current_node->nd_file, \
			      ruby_sourceline = nd_line(ruby_current_node))
#else
#define SET_CURRENT_SOURCE() ((void)0)
#endif

void
ruby_set_current_source()
{
    if (ruby_current_node) {
	ruby_sourcefile = ruby_current_node->nd_file;
	ruby_sourceline = nd_line(ruby_current_node);
    }
}

static void
#ifdef HAVE_STDARG_PROTOTYPES
warn_printf(const char *fmt, ...)
#else
warn_printf(fmt, va_alist)
    const char *fmt;
    va_dcl
#endif
{
    char buf[BUFSIZ];
    va_list args;

    va_init_list(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);
    rb_write_error(buf);
}

#define warn_print(x) rb_write_error(x)
#define warn_print2(x,l) rb_write_error2(x,l)

static void
error_pos()
{
    ruby_set_current_source();
    if (ruby_sourcefile) {
	if (ruby_frame->last_func) {
	    warn_printf("%s:%d:in `%s'", ruby_sourcefile, ruby_sourceline,
			rb_id2name(ruby_frame->orig_func));
	}
	else if (ruby_sourceline == 0) {
	    warn_printf("%s", ruby_sourcefile);
	}
	else {
	    warn_printf("%s:%d", ruby_sourcefile, ruby_sourceline);
	}
    }
}

VALUE rb_check_backtrace(VALUE);

static VALUE
get_backtrace(info)
    VALUE info;
{
    if (NIL_P(info)) return Qnil;
    info = rb_funcall(info, rb_intern("backtrace"), 0);
    if (NIL_P(info)) return Qnil;
    return rb_check_backtrace(info);
}

static void
set_backtrace(info, bt)
    VALUE info, bt;
{
    rb_funcall(info, rb_intern("set_backtrace"), 1, bt);
}

static void
error_print()
{
    VALUE errat = Qnil;		/* OK */
    volatile VALUE eclass, e;
    const char *einfo;
    long elen;

    if (NIL_P(ruby_errinfo)) return;

    PUSH_TAG(PROT_NONE);
    if (EXEC_TAG() == 0) {
	errat = get_backtrace(ruby_errinfo);
    }
    else {
	errat = Qnil;
    }
    if (EXEC_TAG()) goto error;
    if (NIL_P(errat)){
	ruby_set_current_source();
	if (!ruby_sourcefile)
	    warn_printf("%d", ruby_sourceline);
	else if (!ruby_sourceline)
	    warn_printf("%s", ruby_sourcefile);
	else
	    warn_printf("%s:%d", ruby_sourcefile, ruby_sourceline);
    }
    else if (RARRAY(errat)->len == 0) {
	error_pos();
    }
    else {
	VALUE mesg = RARRAY(errat)->ptr[0];

	if (NIL_P(mesg)) error_pos();
	else {
	    warn_print2(RSTRING(mesg)->ptr, RSTRING(mesg)->len);
	}
    }

    eclass = CLASS_OF(ruby_errinfo);
    if (EXEC_TAG() == 0) {
  	e = rb_funcall(ruby_errinfo, rb_intern("message"), 0, 0);
 	StringValue(e);
	einfo = RSTRING(e)->ptr;
	elen = RSTRING(e)->len;
    }
    else {
	einfo = "";
	elen = 0;
    }
    if (EXEC_TAG()) goto error;
    if (eclass == rb_eRuntimeError && elen == 0) {
	warn_print(": unhandled exception\n");
    }
    else {
	VALUE epath;

	epath = rb_class_name(eclass);
	if (elen == 0) {
	    warn_print(": ");
	    warn_print2(RSTRING(epath)->ptr, RSTRING(epath)->len);
	    warn_print("\n");
	}
	else {
	    char *tail  = 0;
	    long len = elen;

	    if (RSTRING(epath)->ptr[0] == '#') epath = 0;
	    if ((tail = memchr(einfo, '\n', elen)) != 0) {
		len = tail - einfo;
		tail++;		/* skip newline */
	    }
	    warn_print(": ");
	    warn_print2(einfo, len);
	    if (epath) {
		warn_print(" (");
		warn_print2(RSTRING(epath)->ptr, RSTRING(epath)->len);
		warn_print(")\n");
	    }
	    if (tail && elen>len+1) {
		warn_print2(tail, elen-len-1);
		if (einfo[elen-1] != '\n') warn_print2("\n", 1);
	    }
	}
    }

    if (!NIL_P(errat)) {
	long i;
	struct RArray *ep = RARRAY(errat);
        int truncate = eclass == rb_eSysStackError;

#define TRACE_MAX (TRACE_HEAD+TRACE_TAIL+5)
#define TRACE_HEAD 8
#define TRACE_TAIL 5

	ep = RARRAY(errat);
	for (i=1; i<ep->len; i++) {
	    if (TYPE(ep->ptr[i]) == T_STRING) {
		warn_printf("\tfrom %s\n", RSTRING(ep->ptr[i])->ptr);
	    }
	    if (truncate && i == TRACE_HEAD && ep->len > TRACE_MAX) {
		warn_printf("\t ... %ld levels...\n",
			ep->len - TRACE_HEAD - TRACE_TAIL);
		i = ep->len - TRACE_TAIL;
	    }
	}
    }
  error:
    POP_TAG();
}

void rb_call_inits _((void));
void Init_heap _((void));
void Init_ext _((void));

#ifdef HAVE_NATIVETHREAD
static rb_nativethread_t ruby_thid;
int
is_ruby_native_thread() {
    return NATIVETHREAD_EQUAL(ruby_thid, NATIVETHREAD_CURRENT());
}

# ifdef HAVE_NATIVETHREAD_KILL
void
ruby_native_thread_kill(sig)
    int sig;
{
    NATIVETHREAD_KILL(ruby_thid, sig);
}
# endif
#endif

NORETURN(static void rb_thread_start_1 _((void)));

void
ruby_init()
{
    static int initialized = 0;
    static struct FRAME frame;
    static struct iter iter;
    int state;

    if (initialized)
	return;
    initialized = 1;
#ifdef HAVE_NATIVETHREAD
    ruby_thid = NATIVETHREAD_CURRENT();
#endif

    ruby_frame = top_frame = &frame;
    ruby_iter = &iter;

    ruby_init_stack((void*)&state);
    Init_heap();
    PUSH_SCOPE();
    ruby_scope->local_vars = 0;
    ruby_scope->local_tbl  = 0;
    top_scope = ruby_scope;
    /* default visibility is private at toplevel */
    SCOPE_SET(SCOPE_PRIVATE);

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	rb_call_inits();
	ruby_class = rb_cObject;
	ruby_frame->self = ruby_top_self;
	ruby_top_cref = NEW_CREF(rb_cObject, 0);
	ruby_cref = ruby_top_cref;
	rb_define_global_const("TOPLEVEL_BINDING", rb_f_binding(ruby_top_self));
#ifdef __MACOS__
	_macruby_init();
#elif defined(__VMS)
	_vmsruby_init();
#endif
	ruby_prog_init();
	ALLOW_INTS;
    }
    POP_TAG();
    if (state) {
	error_print();
	exit(EXIT_FAILURE);
    }
    POP_SCOPE();
    ruby_scope = top_scope;
    top_scope->flags &= ~SCOPE_NOSTACK;
    ruby_running = 1;
}

static VALUE
eval_node(self, node)
    VALUE self;
    NODE *node;
{
    NODE *beg_tree = ruby_eval_tree_begin;

    ruby_eval_tree_begin = 0;
    if (beg_tree) {
	rb_eval(self, beg_tree);
    }

    if (!node) return Qnil;
    return rb_eval(self, node);
}

int ruby_in_eval;

int rb_thread_join _((VALUE, double));

static void rb_thread_cleanup _((void));
static void rb_thread_wait_other_threads _((void));

static int thread_no_ensure _((void));

static VALUE exception_error;
static VALUE sysstack_error;

static int
sysexit_status(err)
    VALUE err;
{
    VALUE st = rb_iv_get(err, "status");
    return NUM2INT(st);
}

static int
error_handle(ex)
    int ex;
{
    int status = EXIT_FAILURE;
    rb_thread_t th = curr_thread;

    if (rb_thread_set_raised(th))
	return EXIT_FAILURE;
    switch (ex & TAG_MASK) {
      case 0:
	status = EXIT_SUCCESS;
	break;

      case TAG_RETURN:
	error_pos();
	warn_print(": unexpected return\n");
	break;
      case TAG_NEXT:
	error_pos();
	warn_print(": unexpected next\n");
	break;
      case TAG_BREAK:
	error_pos();
	warn_print(": unexpected break\n");
	break;
      case TAG_REDO:
	error_pos();
	warn_print(": unexpected redo\n");
	break;
      case TAG_RETRY:
	error_pos();
	warn_print(": retry outside of rescue clause\n");
	break;
      case TAG_THROW:
	if (prot_tag && prot_tag->frame && prot_tag->frame->node) {
	    NODE *tag = prot_tag->frame->node;
	    warn_printf("%s:%d: uncaught throw\n",
		    tag->nd_file, nd_line(tag));
	}
	else {
	    error_pos();
	    warn_printf(": unexpected throw\n");
	}
	break;
      case TAG_RAISE:
      case TAG_FATAL:
	if (rb_obj_is_kind_of(ruby_errinfo, rb_eSystemExit)) {
	    status = sysexit_status(ruby_errinfo);
	}
	else if (rb_obj_is_instance_of(ruby_errinfo, rb_eSignal)) {
	    /* no message when exiting by signal */
	}
	else {
	    error_print();
	}
	break;
      default:
	rb_bug("Unknown longjmp status %d", ex);
	break;
    }
    rb_thread_reset_raised(th);
    return status;
}

void
ruby_options(argc, argv)
    int argc;
    char **argv;
{
    int state;

    ruby_init_stack((void*)&state);
    PUSH_ANCHOR();
    if ((state = EXEC_TAG()) == 0) {
	ruby_process_options(argc, argv);
    }
    else {
	if (state == TAG_THREAD) {
	    rb_thread_start_1();
	}
	trace_func = 0;
	tracing = 0;
	exit(error_handle(state));
    }
    POP_ANCHOR();
}

void rb_exec_end_proc _((void));

static void
ruby_finalize_0()
{
    PUSH_TAG(PROT_NONE);
    if (EXEC_TAG() == 0) {
	rb_trap_exit();
    }
    POP_TAG();
    rb_exec_end_proc();
}

static void
ruby_finalize_1()
{
    signal(SIGINT, SIG_DFL);
    ruby_errinfo = 0;
    rb_gc_call_finalizer_at_exit();
    trace_func = 0;
    tracing = 0;
}

void
ruby_finalize()
{
    ruby_finalize_0();
    ruby_finalize_1();
}

int
ruby_cleanup(ex)
    int ex;
{
    int state;
    volatile VALUE errs[2];
    int nerr;

    errs[1] = ruby_errinfo;
    ruby_safe_level = 0;
    ruby_init_stack(&errs[STACK_UPPER(errs, 0, 1)]);
    PUSH_ANCHOR();
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	ruby_finalize_0();
	errs[0] = ruby_errinfo;
	rb_thread_cleanup();
	rb_thread_wait_other_threads();
    }
    else if (state == TAG_THREAD) {
	rb_thread_start_1();
    }
    else if (ex == 0) {
	ex = state;
    }
    POP_ITER();
    ruby_errinfo = errs[1];
    ex = error_handle(ex);
    ruby_finalize_1();
    POP_ANCHOR();

    for (nerr = 0; nerr < sizeof(errs) / sizeof(errs[0]); ++nerr) {
	VALUE err = errs[nerr];

	if (!RTEST(err)) continue;

	if (rb_obj_is_kind_of(err, rb_eSystemExit)) {
	    return sysexit_status(err);
	}
	else if (rb_obj_is_kind_of(err, rb_eSignal)) {
	    VALUE sig = rb_iv_get(err, "signo");
	    ruby_default_signal(NUM2INT(sig));
	}
	else if (ex == 0) {
	    ex = 1;
	}
    }

#if EXIT_SUCCESS != 0 || EXIT_FAILURE != 1
    switch (ex) {
#if EXIT_SUCCESS != 0
      case 0: return EXIT_SUCCESS;
#endif
#if EXIT_FAILURE != 1
      case 1: return EXIT_FAILURE;
#endif
    }
#endif

    return ex;
}

static int
ruby_exec_internal()
{
    int state;

    PUSH_ANCHOR();
    PUSH_ITER(ITER_NOT);
    /* default visibility is private at toplevel */
    SCOPE_SET(SCOPE_PRIVATE);
    if ((state = EXEC_TAG()) == 0) {
	eval_node(ruby_top_self, ruby_eval_tree);
    }
    else if (state == TAG_THREAD) {
	rb_thread_start_1();
    }
    POP_ITER();
    POP_ANCHOR();
    return state;
}

void
ruby_stop(ex)
    int ex;
{
    exit(ruby_cleanup(ex));
}

int
ruby_exec()
{
    volatile VALUE tmp;

    ruby_init_stack(&tmp);
    return ruby_exec_internal();
}

void
ruby_run()
{
    int state;
    static int ex;

    if (ruby_nerrs > 0) exit(EXIT_FAILURE);
    state = ruby_exec();
    if (state && !ex) ex = state;
    ruby_stop(ex);
}

static void
compile_error(at)
    const char *at;
{
    VALUE str;

    ruby_nerrs = 0;
    str = rb_str_buf_new2("compile error");
    if (at) {
	rb_str_buf_cat2(str, " in ");
	rb_str_buf_cat2(str, at);
    }
    rb_str_buf_cat(str, "\n", 1);
    if (!NIL_P(ruby_errinfo)) {
	rb_str_append(str, rb_obj_as_string(ruby_errinfo));
    }
    rb_exc_raise(rb_exc_new3(rb_eSyntaxError, str));
}

VALUE
rb_eval_string(str)
    const char *str;
{
    VALUE v;
    NODE *oldsrc = ruby_current_node;

    ruby_current_node = 0;
    ruby_sourcefile = rb_source_filename("(eval)");
    v = eval(ruby_top_self, rb_str_new2(str), Qnil, 0, 0);
    ruby_current_node = oldsrc;

    return v;
}

VALUE
rb_eval_string_protect(str, state)
    const char *str;
    int *state;
{
    return rb_protect((VALUE (*)_((VALUE)))rb_eval_string, (VALUE)str, state);
}

VALUE
rb_eval_string_wrap(str, state)
    const char *str;
    int *state;
{
    int status;
    VALUE self = ruby_top_self;
    VALUE wrapper = ruby_wrapper;
    VALUE val;

    PUSH_CLASS(ruby_wrapper = rb_module_new());
    ruby_top_self = rb_obj_clone(ruby_top_self);
    rb_extend_object(ruby_top_self, ruby_wrapper);
    PUSH_FRAME();
    ruby_frame->last_func = 0;
    ruby_frame->last_class = 0;
    ruby_frame->self = self;
    PUSH_CREF(ruby_wrapper);
    PUSH_SCOPE();

    val = rb_eval_string_protect(str, &status);
    ruby_top_self = self;

    POP_SCOPE();
    POP_FRAME();
    POP_CLASS();
    ruby_wrapper = wrapper;
    if (state) {
	*state = status;
    }
    else if (status) {
	JUMP_TAG(status);
    }
    return val;
}

NORETURN(static void localjump_error(const char*, VALUE, int));
static void
localjump_error(mesg, value, reason)
    const char *mesg;
    VALUE value;
    int reason;
{
    VALUE exc = rb_exc_new2(rb_eLocalJumpError, mesg);
    ID id;

    rb_iv_set(exc, "@exit_value", value);
    switch (reason) {
      case TAG_BREAK:
	id = rb_intern("break"); break;
      case TAG_REDO:
	id = rb_intern("redo"); break;
      case TAG_RETRY:
	id = rb_intern("retry"); break;
      case TAG_NEXT:
	id = rb_intern("next"); break;
      case TAG_RETURN:
	id = rb_intern("return"); break;
      default:
	id = rb_intern("noreason"); break;
    }
    rb_iv_set(exc, "@reason", ID2SYM(id));
    rb_exc_raise(exc);
}

/*
 * call_seq:
 *   local_jump_error.exit_value  => obj
 *
 * Returns the exit value associated with this +LocalJumpError+.
 */
static VALUE
localjump_xvalue(exc)
    VALUE exc;
{
    return rb_iv_get(exc, "@exit_value");
}

/*
 * call-seq:
 *    local_jump_error.reason   => symbol
 *
 * The reason this block was terminated:
 * :break, :redo, :retry, :next, :return, or :noreason.
 */

static VALUE
localjump_reason(exc)
    VALUE exc;
{
    return rb_iv_get(exc, "@reason");
}

NORETURN(static void jump_tag_but_local_jump _((int,VALUE)));
static void
jump_tag_but_local_jump(state, val)
    int state;
    VALUE val;
{

    if (val == Qundef) val = prot_tag->retval;
    switch (state) {
      case 0:
	break;
      case TAG_RETURN:
	localjump_error("unexpected return", val, state);
	break;
      case TAG_BREAK:
	localjump_error("unexpected break", val, state);
	break;
      case TAG_NEXT:
	localjump_error("unexpected next", val, state);
	break;
      case TAG_REDO:
	localjump_error("unexpected redo", Qnil, state);
	break;
      case TAG_RETRY:
	localjump_error("retry outside of rescue clause", Qnil, state);
	break;
      default:
	break;
    }
    JUMP_TAG(state);
}

VALUE
rb_eval_cmd(cmd, arg, level)
    VALUE cmd, arg;
    int level;
{
    int state;
    VALUE val = Qnil;		/* OK */
    struct SCOPE *saved_scope;
    volatile int safe = ruby_safe_level;

    if (OBJ_TAINTED(cmd)) {
	level = 4;
    }
    if (TYPE(cmd) != T_STRING) {
	PUSH_ITER(ITER_NOT);
	PUSH_TAG(PROT_NONE);
	ruby_safe_level = level;
	if ((state = EXEC_TAG()) == 0) {
	    val = rb_funcall2(cmd, rb_intern("call"), RARRAY(arg)->len, RARRAY(arg)->ptr);
	}
	ruby_safe_level = safe;
	POP_TAG();
	POP_ITER();
	if (state) JUMP_TAG(state);
	return val;
    }

    saved_scope = ruby_scope;
    ruby_scope = top_scope;
    PUSH_FRAME();
    ruby_frame->last_func = 0;
    ruby_frame->last_class = 0;
    ruby_frame->self = ruby_top_self;
    PUSH_CREF(ruby_wrapper ? ruby_wrapper : rb_cObject);

    ruby_safe_level = level;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	val = eval(ruby_top_self, cmd, Qnil, 0, 0);
    }
    if (ruby_scope->flags & SCOPE_DONT_RECYCLE)
	scope_dup(saved_scope);
    ruby_scope = saved_scope;
    ruby_safe_level = safe;
    POP_TAG();
    POP_FRAME();

    if (state) jump_tag_but_local_jump(state, val);
    return val;
}

#define ruby_cbase (ruby_cref->nd_clss)

static VALUE
ev_const_defined(cref, id, self)
    NODE *cref;
    ID id;
    VALUE self;
{
    NODE *cbase = cref;
    VALUE result;

    while (cbase && cbase->nd_next) {
	struct RClass *klass = RCLASS(cbase->nd_clss);

	if (!NIL_P(klass)) {
	    if (klass->iv_tbl && st_lookup(klass->iv_tbl, id, &result)) {
		if (result == Qundef && NIL_P(rb_autoload_p((VALUE)klass, id))) {
		    return Qfalse;
		}
		return Qtrue;
	    }
	}
	cbase = cbase->nd_next;
    }
    return rb_const_defined(cref->nd_clss, id);
}

static VALUE
ev_const_get(cref, id, self)
    NODE *cref;
    ID id;
    VALUE self;
{
    NODE *cbase = cref;
    VALUE result;

    while (cbase && cbase->nd_next) {
	VALUE klass = cbase->nd_clss;

	if (!NIL_P(klass)) {
	    while (RCLASS(klass)->iv_tbl &&
		   st_lookup(RCLASS(klass)->iv_tbl, id, &result)) {
		if (result == Qundef) {
		    if (!RTEST(rb_autoload_load(klass, id))) break;
		    continue;
		}
		return result;
	    }
	}
	cbase = cbase->nd_next;
    }
    return rb_const_get(NIL_P(cref->nd_clss) ? CLASS_OF(self): cref->nd_clss, id);
}

static VALUE
cvar_cbase()
{
    NODE *cref = ruby_cref;

    while (cref && cref->nd_next && (NIL_P(cref->nd_clss) || FL_TEST(cref->nd_clss, FL_SINGLETON))) {
	cref = cref->nd_next;
	if (!cref->nd_next) {
	    rb_warn("class variable access from toplevel singleton method");
	}
    }
    if (NIL_P(cref->nd_clss)) {
	rb_raise(rb_eTypeError, "no class variables available");
    }
    return cref->nd_clss;
}

/*
 *  call-seq:
 *     Module.nesting    => array
 *
 *  Returns the list of +Modules+ nested at the point of call.
 *
 *     module M1
 *       module M2
 *         $a = Module.nesting
 *       end
 *     end
 *     $a           #=> [M1::M2, M1]
 *     $a[0].name   #=> "M1::M2"
 */

static VALUE
rb_mod_nesting()
{
    NODE *cbase = ruby_cref;
    VALUE ary = rb_ary_new();

    while (cbase && cbase->nd_next) {
	if (!NIL_P(cbase->nd_clss)) rb_ary_push(ary, cbase->nd_clss);
	cbase = cbase->nd_next;
    }
    if (ruby_wrapper && RARRAY(ary)->len == 0) {
	rb_ary_push(ary, ruby_wrapper);
    }
    return ary;
}

/*
 *  call-seq:
 *     Module.constants   => array
 *
 *  Returns an array of the names of all constants defined in the
 *  system. This list includes the names of all modules and classes.
 *
 *     p Module.constants.sort[1..5]
 *
 *  <em>produces:</em>
 *
 *     ["ARGV", "ArgumentError", "Array", "Bignum", "Binding"]
 */

static VALUE
rb_mod_s_constants()
{
    NODE *cbase = ruby_cref;
    void *data = 0;

    while (cbase) {
	if (!NIL_P(cbase->nd_clss)) {
	    data = rb_mod_const_at(cbase->nd_clss, data);
	}
	cbase = cbase->nd_next;
    }

    if (!NIL_P(ruby_cbase)) {
	data = rb_mod_const_of(ruby_cbase, data);
    }
    return rb_const_list(data);
}

void
rb_frozen_class_p(klass)
    VALUE klass;
{
    const char *desc = "something(?!)";

    if (OBJ_FROZEN(klass)) {
	if (FL_TEST(klass, FL_SINGLETON))
	    desc = "object";
	else {
	    switch (TYPE(klass)) {
	      case T_MODULE:
	      case T_ICLASS:
		desc = "module"; break;
	      case T_CLASS:
		desc = "class"; break;
	    }
	}
	rb_error_frozen(desc);
    }
}

void
rb_undef(klass, id)
    VALUE klass;
    ID id;
{
    VALUE origin;
    NODE *body;

    if (ruby_cbase == rb_cObject && klass == rb_cObject) {
	rb_secure(4);
    }
    if (ruby_safe_level >= 4 && !OBJ_TAINTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't undef `%s'", rb_id2name(id));
    }
    rb_frozen_class_p(klass);
    if (id == __id__ || id == __send__ || id == init) {
	rb_warn("undefining `%s' may cause serious problem", rb_id2name(id));
    }
    body = search_method(klass, id, &origin);
    if (!body || !body->nd_body) {
	const char *s0 = " class";
	VALUE c = klass;

	if (FL_TEST(c, FL_SINGLETON)) {
	    VALUE obj = rb_iv_get(klass, "__attached__");

	    switch (TYPE(obj)) {
	      case T_MODULE:
	      case T_CLASS:
		c = obj;
		s0 = "";
	    }
	}
	else if (TYPE(c) == T_MODULE) {
	    s0 = " module";
	}
	rb_name_error(id, "undefined method `%s' for%s `%s'",
		      rb_id2name(id),s0,rb_class2name(c));
    }
    rb_add_method(klass, id, 0, NOEX_PUBLIC);
    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_funcall(rb_iv_get(klass, "__attached__"),
		   singleton_undefined, 1, ID2SYM(id));
    }
    else {
	rb_funcall(klass, undefined, 1, ID2SYM(id));
    }
}

/*
 *  call-seq:
 *     undef_method(symbol)    => self
 *
 *  Prevents the current class from responding to calls to the named
 *  method. Contrast this with <code>remove_method</code>, which deletes
 *  the method from the particular class; Ruby will still search
 *  superclasses and mixed-in modules for a possible receiver.
 *
 *     class Parent
 *       def hello
 *         puts "In parent"
 *       end
 *     end
 *     class Child < Parent
 *       def hello
 *         puts "In child"
 *       end
 *     end
 *
 *
 *     c = Child.new
 *     c.hello
 *
 *
 *     class Child
 *       remove_method :hello  # remove from child, still in parent
 *     end
 *     c.hello
 *
 *
 *     class Child
 *       undef_method :hello   # prevent any calls to 'hello'
 *     end
 *     c.hello
 *
 *  <em>produces:</em>
 *
 *     In child
 *     In parent
 *     prog.rb:23: undefined method `hello' for #<Child:0x401b3bb4> (NoMethodError)
 */

static VALUE
rb_mod_undef_method(argc, argv, mod)
    int argc;
    VALUE *argv;
    VALUE mod;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_undef(mod, rb_to_id(argv[i]));
    }
    return mod;
}

void
rb_alias(klass, name, def)
    VALUE klass;
    ID name, def;
{
    VALUE origin = 0;
    NODE *orig, *body, *node;
    VALUE singleton = 0;
    st_data_t data;

    rb_frozen_class_p(klass);
    if (name == def) return;
    if (klass == rb_cObject) {
	rb_secure(4);
    }
    orig = search_method(klass, def, &origin);
    if (!orig || !orig->nd_body) {
	if (TYPE(klass) == T_MODULE) {
	    orig = search_method(rb_cObject, def, &origin);
	}
    }
    if (!orig || !orig->nd_body) {
	print_undef(klass, def);
    }
    if (FL_TEST(klass, FL_SINGLETON)) {
	singleton = rb_iv_get(klass, "__attached__");
    }
    body = orig->nd_body;
    orig->nd_cnt++;
    if (nd_type(body) == NODE_FBODY) { /* was alias */
	def = body->nd_mid;
	origin = body->nd_orig;
	body = body->nd_head;
    }

    rb_clear_cache_by_id(name);
    if (RTEST(ruby_verbose) && st_lookup(RCLASS(klass)->m_tbl, name, &data)) {
	node = (NODE *)data;
	if (node->nd_cnt == 0 && node->nd_body) {
	    rb_warning("discarding old %s", rb_id2name(name));
	}
    }
    st_insert(RCLASS(klass)->m_tbl, name,
	      (st_data_t)NEW_METHOD(NEW_FBODY(body, def, origin),
				    NOEX_WITH_SAFE(orig->nd_noex)));

    if (!ruby_running) return;

    if (singleton) {
	rb_funcall(singleton, singleton_added, 1, ID2SYM(name));
    }
    else {
	rb_funcall(klass, added, 1, ID2SYM(name));
    }
}

/*
 *  call-seq:
 *     alias_method(new_name, old_name)   => self
 *
 *  Makes <i>new_name</i> a new copy of the method <i>old_name</i>. This can
 *  be used to retain access to methods that are overridden.
 *
 *     module Mod
 *       alias_method :orig_exit, :exit
 *       def exit(code=0)
 *         puts "Exiting with code #{code}"
 *         orig_exit(code)
 *       end
 *     end
 *     include Mod
 *     exit(99)
 *
 *  <em>produces:</em>
 *
 *     Exiting with code 99
 */

static VALUE
rb_mod_alias_method(mod, newname, oldname)
    VALUE mod, newname, oldname;
{
    rb_alias(mod, rb_to_id(newname), rb_to_id(oldname));
    return mod;
}

NODE *
rb_copy_node_scope(node, rval)
    NODE *node;
    NODE *rval;
{
    NODE *copy = NEW_NODE(NODE_SCOPE,0,rval,node->nd_next);

    if (node->nd_tbl) {
	copy->nd_tbl = ALLOC_N(ID, node->nd_tbl[0]+1);
	MEMCPY(copy->nd_tbl, node->nd_tbl, ID, node->nd_tbl[0]+1);
    }
    else {
	copy->nd_tbl = 0;
    }
    return copy;
}

#ifdef C_ALLOCA
# define TMP_PROTECT NODE * volatile tmp__protect_tmp=0
# define TMP_ALLOC(n)							\
    (tmp__protect_tmp = NEW_NODE(NODE_ALLOCA,				\
				 ALLOC_N(VALUE,n),tmp__protect_tmp,n),	\
     (void*)tmp__protect_tmp->nd_head)
#else
# define TMP_PROTECT typedef int foobazzz
# define TMP_ALLOC(n) ALLOCA_N(VALUE,n)
#endif

#define SETUP_ARGS0(anode,extra) do {\
    NODE *n = anode;\
    if (!n) {\
	argc = 0;\
	argv = 0;\
    }\
    else if (nd_type(n) == NODE_ARRAY) {\
	argc=anode->nd_alen;\
	if (argc > 0) {\
	    int i;\
	    n = anode;\
	    argv = TMP_ALLOC(argc+extra);\
	    for (i=0;i<argc;i++) {\
		argv[i] = rb_eval(self,n->nd_head);\
		n=n->nd_next;\
	    }\
	}\
	else {\
	    argc = 0;\
	    argv = 0;\
	}\
    }\
    else {\
	VALUE args = rb_eval(self,n);\
	if (TYPE(args) != T_ARRAY)\
	    args = rb_ary_to_ary(args);\
	argc = RARRAY(args)->len;\
	argv = TMP_ALLOC(argc+extra);\
	MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);\
    }\
} while (0)

#define SETUP_ARGS(anode) SETUP_ARGS0(anode,0)

#define BEGIN_CALLARGS do {\
    struct BLOCK *tmp_block = ruby_block;\
    int tmp_iter = ruby_iter->iter;\
    switch (tmp_iter) {\
      case ITER_PRE:\
	if (ruby_block) ruby_block = ruby_block->outer;\
      case ITER_PAS:\
	tmp_iter = ITER_NOT;\
    }\
    PUSH_ITER(tmp_iter)

#define END_CALLARGS \
    ruby_block = tmp_block;\
    POP_ITER();\
} while (0)

#define MATCH_DATA *rb_svar(node->nd_cnt)

static const char* is_defined _((VALUE, NODE*, char*));

static const char*
arg_defined(self, node, buf, type)
    VALUE self;
    NODE *node;
    char *buf;
    const char *type;
{
    int argc;
    int i;

    if (!node) return type;	/* no args */
    if (nd_type(node) == NODE_ARRAY) {
	argc=node->nd_alen;
	if (argc > 0) {
	    for (i=0;i<argc;i++) {
		if (!is_defined(self, node->nd_head, buf))
		    return 0;
		node = node->nd_next;
	    }
	}
    }
    else if (!is_defined(self, node, buf)) {
	return 0;
    }
    return type;
}

static const char*
is_defined(self, node, buf)
    VALUE self;
    NODE *node;			/* OK */
    char *buf;
{
    VALUE val;			/* OK */
    volatile VALUE vval;
    int state;

  again:
    if (!node) return "expression";
    switch (nd_type(node)) {
      case NODE_SUPER:
      case NODE_ZSUPER:
	if (ruby_frame->last_func == 0) return 0;
	else if (ruby_frame->last_class == 0) return 0;
	val = ruby_frame->last_class;
	if (rb_method_boundp(RCLASS(val)->super, ruby_frame->orig_func, 0)) {
	    if (nd_type(node) == NODE_SUPER) {
		return arg_defined(self, node->nd_args, buf, "super");
	    }
	    return "super";
	}
	break;

      case NODE_VCALL:
      case NODE_FCALL:
	val = self;
	goto check_bound;

      case NODE_ATTRASGN:
	val = self;
	if (node->nd_recv == (NODE *)1) goto check_bound;
      case NODE_CALL:
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    vval = rb_eval(self, node->nd_recv);
	}
	POP_TAG();
	if (state) {
	    ruby_errinfo = Qnil;
	    return 0;
	}
	val = vval;
      check_bound:
	{
	    int call = nd_type(node)==NODE_CALL;

	    val = CLASS_OF(val);
	    if (call) {
		int noex;
		ID id = node->nd_mid;

		if (!rb_get_method_body(&val, &id, &noex))
		    break;
		if ((noex & NOEX_PRIVATE))
		    break;
		if ((noex & NOEX_PROTECTED) &&
		    !rb_obj_is_kind_of(self, rb_class_real(val)))
		    break;
	    }
	    else if (!rb_method_boundp(val, node->nd_mid, call))
		break;
	    return arg_defined(self, node->nd_args, buf,
			       nd_type(node) == NODE_ATTRASGN ?
			       "assignment" : "method");
	}
	break;

      case NODE_MATCH2:
      case NODE_MATCH3:
	return "method";

      case NODE_YIELD:
	if (rb_block_given_p()) {
	    return "yield";
	}
	break;

      case NODE_SELF:
	return "self";

      case NODE_NIL:
	return "nil";

      case NODE_TRUE:
	return "true";

      case NODE_FALSE:
	return "false";

      case NODE_ATTRSET:
      case NODE_OP_ASGN1:
      case NODE_OP_ASGN2:
      case NODE_OP_ASGN_OR:
      case NODE_OP_ASGN_AND:
      case NODE_MASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_DASGN_CURR:
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_CDECL:
      case NODE_CVDECL:
      case NODE_CVASGN:
	return "assignment";

      case NODE_LVAR:
	return "local-variable";
      case NODE_DVAR:
	return "local-variable(in-block)";

      case NODE_GVAR:
	if (rb_gvar_defined(node->nd_entry)) {
	    return "global-variable";
	}
	break;

      case NODE_IVAR:
	if (rb_ivar_defined(self, node->nd_vid)) {
	    return "instance-variable";
	}
	break;

      case NODE_CONST:
	if (ev_const_defined(ruby_cref, node->nd_vid, self)) {
	    return "constant";
	}
	break;

      case NODE_CVAR:
	if (rb_cvar_defined(cvar_cbase(), node->nd_vid)) {
	    return "class variable";
	}
	break;

      case NODE_COLON2:
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    vval = rb_eval(self, node->nd_head);
	}
	POP_TAG();
	if (state) {
	    ruby_errinfo = Qnil;
	    return 0;
	}
	else {
	    val = vval;
	    switch (TYPE(val)) {
	      case T_CLASS:
	      case T_MODULE:
		if (rb_const_defined_from(val, node->nd_mid))
		    return "constant";
		break;
	      default:
		if (rb_method_boundp(CLASS_OF(val), node->nd_mid, 1)) {
		    return "method";
		}
	    }
	}
	break;

      case NODE_COLON3:
	if (rb_const_defined_from(rb_cObject, node->nd_mid)) {
	    return "constant";
	}
	break;

      case NODE_NTH_REF:
	if (RTEST(rb_reg_nth_defined(node->nd_nth, MATCH_DATA))) {
	    sprintf(buf, "$%d", (int)node->nd_nth);
	    return buf;
	}
	break;

      case NODE_BACK_REF:
	if (RTEST(rb_reg_nth_defined(0, MATCH_DATA))) {
	    sprintf(buf, "$%c", (char)node->nd_nth);
	    return buf;
	}
	break;

      case NODE_NEWLINE:
	node = node->nd_next;
	goto again;

      default:
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    rb_eval(self, node);
	}
	POP_TAG();
	if (!state) {
	    return "expression";
	}
	ruby_errinfo = Qnil;
	break;
    }
    return 0;
}

static int handle_rescue _((VALUE,NODE*));

static void blk_free();

VALUE
rb_obj_is_proc(proc)
    VALUE proc;
{
    if (TYPE(proc) == T_DATA && RDATA(proc)->dfree == (RUBY_DATA_FUNC)blk_free) {
	return Qtrue;
    }
    return Qfalse;
}

static void thread_deliver_event _((rb_event_hook_func_t,rb_event_t));

const rb_event_t rb_event_all = RUBY_EVENT_ALL;

void
rb_add_event_hook(func, events)
    rb_event_hook_func_t func;
    rb_event_t events;
{
    rb_event_hook_t *hook;

    hook = ALLOC(rb_event_hook_t);
    hook->func = func;
    hook->events = events;
    hook->next = event_hooks;
    event_hooks = hook;
    if (events & RUBY_EVENT_THREAD_INIT) {
	thread_deliver_event(func, RUBY_EVENT_THREAD_INIT);
    }
}

int
rb_remove_event_hook(func)
    rb_event_hook_func_t func;
{
    rb_event_hook_t *prev, *hook;

    prev = NULL;
    hook = event_hooks;
    while (hook) {
	if (hook->func == func) {
	    if (prev) {
		prev->next = hook->next;
	    }
	    else {
		event_hooks = hook->next;
	    }
	    xfree(hook);
	    return 0;
	}
	prev = hook;
	hook = hook->next;
    }
    return -1;
}

#if defined __APPLE__ && defined __MACH__ && defined RUBY_ENABLE_MACOSX_UNOFFICIAL_THREADSWITCH
typedef struct threadswitch_hook {
    rb_threadswitch_hook_func_t func;
    struct threadswitch_hook *next;
} rb_threadswitch_hook_t;

static rb_threadswitch_hook_t *threadswitch_hooks;

static void
call_threadswitch_hook(event, node, thread, mid, klass)
    rb_event_t event;
    NODE *node;
    VALUE thread;
    ID mid;
    VALUE klass;
{
    rb_threadswitch_hook_t *hook = threadswitch_hooks;
    rb_threadswitch_event_t thevent = event >> RUBY_THREADSWITCH_SHIFT;

    for (; hook; hook = hook->next) {
	(*hook->func)(thevent, thread);
    }
}

void *
rb_add_threadswitch_hook(func)
    rb_threadswitch_hook_func_t func;
{
    rb_threadswitch_hook_t *hook;
    int new_hook = !threadswitch_hooks;

    rb_warn("rb_add_threadswitch_hook is not an official API; use rb_add_event_hook");

    hook = ALLOC(rb_threadswitch_hook_t);
    hook->func = func;
    hook->next = threadswitch_hooks;
    threadswitch_hooks = hook;
    if (new_hook) {
	rb_add_event_hook(call_threadswitch_hook, RUBY_EVENT_THREAD_ALL);
    }

    return hook;
}

void
rb_remove_threadswitch_hook(handle)
    void *handle;
{
    rb_threadswitch_hook_t **hook_p, *hook;

    for (hook_p = &threadswitch_hooks; *hook_p; hook_p = &hook->next) {
	hook = *hook_p;
	if (hook == (rb_threadswitch_hook_t*)handle) {
	    *hook_p = hook->next;
	    xfree(hook);
	    if (!threadswitch_hooks) {
		rb_remove_event_hook(call_threadswitch_hook);
	    }
	    break;
	}
    }
}
#endif

/*
 *  call-seq:
 *     set_trace_func(proc)    => proc
 *     set_trace_func(nil)     => nil
 *
 *  Establishes _proc_ as the handler for tracing, or disables
 *  tracing if the parameter is +nil+. _proc_ takes up
 *  to six parameters: an event name, a filename, a line number, an
 *  object id, a binding, and the name of a class. _proc_ is
 *  invoked whenever an event occurs. Events are: <code>c-call</code>
 *  (call a C-language routine), <code>c-return</code> (return from a
 *  C-language routine), <code>call</code> (call a Ruby method),
 *  <code>class</code> (start a class or module definition),
 *  <code>end</code> (finish a class or module definition),
 *  <code>line</code> (execute code on a new line), <code>raise</code>
 *  (raise an exception), and <code>return</code> (return from a Ruby
 *  method). Tracing is disabled within the context of _proc_.
 *
 *      class Test
 *	def test
 *	  a = 1
 *	  b = 2
 *	end
 *      end
 *
 *      set_trace_func proc { |event, file, line, id, binding, classname|
 *	   printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname
 *      }
 *      t = Test.new
 *      t.test
 *
 *	  line prog.rb:11               false
 *      c-call prog.rb:11        new    Class
 *      c-call prog.rb:11 initialize   Object
 *    c-return prog.rb:11 initialize   Object
 *    c-return prog.rb:11        new    Class
 *	  line prog.rb:12               false
 *  	  call prog.rb:2        test     Test
 *	  line prog.rb:3        test     Test
 *	  line prog.rb:4        test     Test
 *      return prog.rb:4        test     Test
 */


static VALUE
set_trace_func(obj, trace)
    VALUE obj, trace;
{
    rb_event_hook_t *hook;

    rb_secure(4);
    if (NIL_P(trace)) {
	trace_func = 0;
	rb_remove_event_hook(call_trace_func);
	return Qnil;
    }
    if (!rb_obj_is_proc(trace)) {
	rb_raise(rb_eTypeError, "trace_func needs to be Proc");
    }
    trace_func = trace;
    for (hook = event_hooks; hook; hook = hook->next) {
	if (hook->func == call_trace_func)
	    return trace;
    }
    rb_add_event_hook(call_trace_func, RUBY_EVENT_ALL);
    return trace;
}

static const char *
get_event_name(rb_event_t event)
{
    switch (event) {
      case RUBY_EVENT_LINE:
	return "line";
      case RUBY_EVENT_CLASS:
	return "class";
      case RUBY_EVENT_END:
	return "end";
      case RUBY_EVENT_CALL:
	return "call";
      case RUBY_EVENT_RETURN:
	return "return";
      case RUBY_EVENT_C_CALL:
	return "c-call";
      case RUBY_EVENT_C_RETURN:
	return "c-return";
      case RUBY_EVENT_RAISE:
	return "raise";
      case RUBY_EVENT_THREAD_INIT:
	return "thread-init";
      case RUBY_EVENT_THREAD_FREE:
	return "thread-free";
      case RUBY_EVENT_THREAD_SAVE:
	return "thread-save";
      case RUBY_EVENT_THREAD_RESTORE:
	return "thread-restore";
      default:
	return "unknown";
    }
}

static void
call_trace_func(event, node, self, id, klass)
    rb_event_t event;
    NODE *node;
    VALUE self;
    ID id;
    VALUE klass;		/* OK */
{
    int state, raised;
    struct FRAME *prev;
    NODE *node_save;
    VALUE srcfile;
    const char *event_name;
    rb_thread_t th = curr_thread;

    if (!trace_func) return;
    if (tracing) return;
    if (ruby_in_compile) return;
    if (id == ID_ALLOCATOR) return;

    if (!(node_save = ruby_current_node)) {
	node_save = NEW_NEWLINE(0);
    }
    tracing = 1;
    prev = ruby_frame;
    PUSH_FRAME();
    *ruby_frame = *prev;
    ruby_frame->prev = prev;
    ruby_frame->iter = 0;	/* blocks not available anyway */

    if (node) {
	ruby_current_node = node;
	ruby_frame->node = node;
	ruby_sourcefile = node->nd_file;
	ruby_sourceline = nd_line(node);
    }
    if (klass) {
	if (TYPE(klass) == T_ICLASS) {
	    klass = RBASIC(klass)->klass;
	}
	else if (FL_TEST(klass, FL_SINGLETON)) {
	    klass = rb_iv_get(klass, "__attached__");
	}
    }
    PUSH_TAG(PROT_NONE);
    raised = rb_thread_reset_raised(th);
    if ((state = EXEC_TAG()) == 0) {
	srcfile = rb_str_new2(ruby_sourcefile?ruby_sourcefile:"(ruby)");
	event_name = get_event_name(event);
	proc_invoke(trace_func, rb_ary_new3(6, rb_str_new2(event_name),
					    srcfile,
					    INT2FIX(ruby_sourceline),
					    id?ID2SYM(id):Qnil,
					    self?rb_f_binding(self):Qnil,
					    klass),
		    Qundef, 0);
    }
    if (raised) rb_thread_set_raised(th);
    POP_TAG();
    POP_FRAME();

    tracing = 0;
    ruby_current_node = node_save;
    SET_CURRENT_SOURCE();
    if (state) {
	trace_func = 0;
	rb_remove_event_hook(call_trace_func);
	JUMP_TAG(state);
    }
}

static VALUE
avalue_to_svalue(v)
    VALUE v;
{
    VALUE tmp, top;

    tmp = rb_check_array_type(v);
    if (NIL_P(tmp)) {
	return v;
    }
    if (RARRAY(tmp)->len == 0) {
	return Qundef;
    }
    if (RARRAY(tmp)->len == 1) {
	top = rb_check_array_type(RARRAY(tmp)->ptr[0]);
	if (NIL_P(top)) {
	    return RARRAY(tmp)->ptr[0];
	}
	if (RARRAY(top)->len > 1) {
	    return v;
	}
	return top;
    }
    return tmp;
}

static VALUE
svalue_to_avalue(v)
    VALUE v;
{
    VALUE tmp, top;

    if (v == Qundef) return rb_ary_new2(0);
    tmp = rb_check_array_type(v);
    if (NIL_P(tmp)) {
	return rb_ary_new3(1, v);
    }
    if (RARRAY(tmp)->len == 1) {
	top = rb_check_array_type(RARRAY(tmp)->ptr[0]);
	if (!NIL_P(top) && RARRAY(top)->len > 1) {
	    return tmp;
	}
	return rb_ary_new3(1, v);
    }
    return tmp;
}

static VALUE
svalue_to_mrhs(v, lhs)
    VALUE v;
    NODE *lhs;
{
    VALUE tmp;

    if (v == Qundef) return rb_ary_new2(0);
    tmp = rb_check_array_type(v);
    if (NIL_P(tmp)) {
	return rb_ary_new3(1, v);
    }
    /* no lhs means splat lhs only */
    if (!lhs) {
	return rb_ary_new3(1, v);
    }
    return tmp;
}

static VALUE
avalue_splat(v)
    VALUE v;
{
    if (RARRAY(v)->len == 0) {
	return Qundef;
    }
    if (RARRAY(v)->len == 1) {
	return RARRAY(v)->ptr[0];
    }
    return v;
}

#if 1
VALUE
rb_Array(val)
    VALUE val;
{
    VALUE tmp = rb_check_array_type(val);

    if (NIL_P(tmp)) {
	/* hack to avoid invoke Object#to_a */
	VALUE origin;
	ID id = rb_intern("to_a");

	if (search_method(CLASS_OF(val), id, &origin) &&
	    RCLASS(origin)->m_tbl != RCLASS(rb_mKernel)->m_tbl) { /* exclude Kernel#to_a */
	    val = rb_funcall(val, id, 0);
	    if (TYPE(val) != T_ARRAY) {
		rb_raise(rb_eTypeError, "`to_a' did not return Array");
	    }
	    return val;
	}
	else {
	    return rb_ary_new3(1, val);
	}
    }
    return tmp;
}
#endif

static VALUE
splat_value(v)
    VALUE v;
{
    if (NIL_P(v)) return rb_ary_new3(1, Qnil);
    return rb_Array(v);
}

static VALUE
class_prefix(self, cpath)
    VALUE self;
    NODE *cpath;
{
    if (!cpath) {
	rb_bug("class path missing");
    }
    if (cpath->nd_head) {
	VALUE c = rb_eval(self, cpath->nd_head);
	switch (TYPE(c)) {
	  case T_CLASS:
	  case T_MODULE:
	    break;
	  default:
	    rb_raise(rb_eTypeError, "%s is not a class/module",
		     RSTRING(rb_obj_as_string(c))->ptr);
	}
	return c;
    }
    else if (nd_type(cpath) == NODE_COLON2) {
	return ruby_cbase;
    }
    else if (ruby_wrapper) {
	return ruby_wrapper;
    }
    else {
	return rb_cObject;
    }
}

#define return_value(v) do {\
  if ((prot_tag->retval = (v)) == Qundef) {\
    prot_tag->retval = Qnil;\
  }\
} while (0)

NORETURN(static void return_jump _((VALUE)));
NORETURN(static void break_jump _((VALUE)));
NORETURN(static void next_jump _((VALUE)));
NORETURN(static void unknown_node _((NODE * volatile)));

static void
unknown_node(node)
    NODE *volatile node;
{
    ruby_current_node = 0;
    if (node->flags == 0) {
        rb_bug("terminated node (0x%lx)", node);
    }
    else if (BUILTIN_TYPE(node) != T_NODE) {
        rb_bug("not a node 0x%02lx (0x%lx)", BUILTIN_TYPE(node), node);
    }
    else {
        rb_bug("unknown node type %d (0x%lx)", nd_type(node), node);
    }
}

static VALUE
rb_eval(self, n)
    VALUE self;
    NODE *n;
{
    NODE * volatile contnode = 0;
    NODE * volatile node = n;
    int state;
    volatile VALUE result = Qnil;
    st_data_t data;

#define RETURN(v) do { \
    result = (v); \
    goto finish; \
} while (0)

    eval_check_tick();
  again:
    if (!node) RETURN(Qnil);

    ruby_current_node = node;
    switch (nd_type(node)) {
      case NODE_BLOCK:
	if (contnode) {
	    result = rb_eval(self, node);
	    break;
	}
	contnode = node->nd_next;
	node = node->nd_head;
	goto again;

      case NODE_POSTEXE:
	rb_f_END();
	nd_set_type(node, NODE_NIL); /* exec just once */
	result = Qnil;
	break;

	/* begin .. end without clauses */
      case NODE_BEGIN:
	node = node->nd_body;
	goto again;

	/* nodes for speed-up(default match) */
      case NODE_MATCH:
	result = rb_reg_match2(node->nd_lit);
	break;

	/* nodes for speed-up(literal match) */
      case NODE_MATCH2:
	{
	    VALUE l = rb_eval(self,node->nd_recv);
	    VALUE r = rb_eval(self,node->nd_value);
	    result = rb_reg_match(l, r);
	}
	break;

	/* nodes for speed-up(literal match) */
      case NODE_MATCH3:
	{
	    VALUE r = rb_eval(self,node->nd_recv);
	    VALUE l = rb_eval(self,node->nd_value);
	    if (TYPE(l) == T_STRING) {
		result = rb_reg_match(r, l);
	    }
	    else {
		result = rb_funcall(l, match, 1, r);
	    }
	}
	break;

	/* node for speed-up(top-level loop for -n/-p) */
      case NODE_OPT_N:
	PUSH_TAG(PROT_LOOP);
	switch (state = EXEC_TAG()) {
	  case 0:
	  opt_n_next:
	    while (!NIL_P(rb_gets())) {
	      opt_n_redo:
		rb_eval(self, node->nd_body);
	    }
	    break;

	  case TAG_REDO:
	    state = 0;
	    goto opt_n_redo;
	  case TAG_NEXT:
	    state = 0;
	    goto opt_n_next;
	  case TAG_BREAK:
	    state = 0;
	  default:
	    break;
	}
	POP_TAG();
	if (state) JUMP_TAG(state);
	RETURN(Qnil);

      case NODE_SELF:
	RETURN(self);

      case NODE_NIL:
	RETURN(Qnil);

      case NODE_TRUE:
	RETURN(Qtrue);

      case NODE_FALSE:
	RETURN(Qfalse);

      case NODE_IF:
	if (RTEST(rb_eval(self, node->nd_cond))) {
	    EXEC_EVENT_HOOK(RUBY_EVENT_LINE, node, self,
			    ruby_frame->last_func,
			    ruby_frame->last_class);
	    node = node->nd_body;
	}
	else {
	    EXEC_EVENT_HOOK(RUBY_EVENT_LINE, node, self,
			    ruby_frame->last_func,
			    ruby_frame->last_class);
	    node = node->nd_else;
	}
	goto again;

      case NODE_WHEN:
	for (; node; node = node->nd_next) {
	    NODE *tag;

	    if (nd_type(node) != NODE_WHEN) goto again;
	    for (tag = node->nd_head; tag; tag = tag->nd_next) {
		EXEC_EVENT_HOOK(RUBY_EVENT_LINE, tag, self,
				ruby_frame->last_func,
				ruby_frame->last_class);
		if (tag->nd_head && nd_type(tag->nd_head) == NODE_WHEN) {
		    VALUE v = rb_eval(self, tag->nd_head->nd_head);
		    long i;

		    if (TYPE(v) != T_ARRAY) v = rb_ary_to_ary(v);
		    for (i=0; i<RARRAY(v)->len; i++) {
			if (RTEST(RARRAY(v)->ptr[i])) {
			    node = node->nd_body;
			    goto again;
			}
		    }
		    continue;
		}
		if (RTEST(rb_eval(self, tag->nd_head))) {
		    node = node->nd_body;
		    goto again;
		}
	    }
	}
	RETURN(Qnil);

      case NODE_CASE:
	{
	    VALUE val = rb_eval(self, node->nd_head);

	    for (node = node->nd_body; node; node = node->nd_next) {
		NODE *tag;

		if (nd_type(node) != NODE_WHEN) goto again;
		for (tag = node->nd_head; tag; tag = tag->nd_next) {
		    EXEC_EVENT_HOOK(RUBY_EVENT_LINE, tag, self,
				    ruby_frame->last_func,
				    ruby_frame->last_class);
		    if (tag->nd_head && nd_type(tag->nd_head) == NODE_WHEN) {
			VALUE v = rb_eval(self, tag->nd_head->nd_head);
			long i;

			if (TYPE(v) != T_ARRAY) v = rb_ary_to_ary(v);
			for (i=0; i<RARRAY(v)->len; i++) {
			    if (RTEST(rb_funcall2(RARRAY(v)->ptr[i], eqq, 1, &val))){
				node = node->nd_body;
				goto again;
			    }
			}
			continue;
		    }
		    if (RTEST(rb_funcall2(rb_eval(self, tag->nd_head), eqq, 1, &val))) {
			node = node->nd_body;
			goto again;
		    }
		}
	    }
	}
	RETURN(Qnil);

      case NODE_WHILE:
	PUSH_TAG(PROT_LOOP);
	result = Qnil;
	switch (state = EXEC_TAG()) {
	  case 0:
	    if (node->nd_state && !RTEST(rb_eval(self, node->nd_cond)))
		goto while_out;
	    do {
	      while_redo:
		rb_eval(self, node->nd_body);
	      while_next:
		;
	    } while (RTEST(rb_eval(self, node->nd_cond)));
	    break;

	  case TAG_REDO:
	    state = 0;
	    goto while_redo;
	  case TAG_NEXT:
	    state = 0;
	    goto while_next;
	  case TAG_BREAK:
	    if (TAG_DST()) {
		state = 0;
		result = prot_tag->retval;
	    }
	    /* fall through */
	  default:
	    break;
	}
      while_out:
	POP_TAG();
	if (state) JUMP_TAG(state);
	RETURN(result);

      case NODE_UNTIL:
	PUSH_TAG(PROT_LOOP);
	result = Qnil;
	switch (state = EXEC_TAG()) {
	  case 0:
	    if (node->nd_state && RTEST(rb_eval(self, node->nd_cond)))
		goto until_out;
	    do {
	      until_redo:
		rb_eval(self, node->nd_body);
	      until_next:
		;
	    } while (!RTEST(rb_eval(self, node->nd_cond)));
	    break;

	  case TAG_REDO:
	    state = 0;
	    goto until_redo;
	  case TAG_NEXT:
	    state = 0;
	    goto until_next;
	  case TAG_BREAK:
	    if (TAG_DST()) {
		state = 0;
		result = prot_tag->retval;
	    }
	    /* fall through */
	  default:
	    break;
	}
      until_out:
	POP_TAG();
	if (state) JUMP_TAG(state);
	RETURN(result);

      case NODE_BLOCK_PASS:
	result = block_pass(self, node);
	break;

      case NODE_ITER:
      case NODE_FOR:
	{
	    PUSH_TAG(PROT_LOOP);
	    PUSH_BLOCK(node->nd_var, node->nd_body);

	    state = EXEC_TAG();
	    if (state == 0) {
	      iter_retry:
		PUSH_ITER(ITER_PRE);
		if (nd_type(node) == NODE_ITER) {
		    result = rb_eval(self, node->nd_iter);
		}
		else {
		    VALUE recv;

		    _block.flags &= ~BLOCK_D_SCOPE;
		    BEGIN_CALLARGS;
		    recv = rb_eval(self, node->nd_iter);
		    END_CALLARGS;
		    ruby_current_node = node;
		    SET_CURRENT_SOURCE();
		    result = rb_call(CLASS_OF(recv),recv,each,0,0,0,self);
		}
		POP_ITER();
	    }
	    else if (state == TAG_BREAK && TAG_DST()) {
		result = prot_tag->retval;
		state = 0;
	    }
	    else if (state == TAG_RETRY) {
		state = 0;
		goto iter_retry;
	    }
	    POP_BLOCK();
	    POP_TAG();
	    switch (state) {
	      case 0:
		break;
	      default:
		JUMP_TAG(state);
	    }
	}
	break;

      case NODE_BREAK:
	break_jump(rb_eval(self, node->nd_stts));
	break;

      case NODE_NEXT:
	CHECK_INTS;
	next_jump(rb_eval(self, node->nd_stts));
	break;

      case NODE_REDO:
	CHECK_INTS;
	JUMP_TAG(TAG_REDO);
	break;

      case NODE_RETRY:
	CHECK_INTS;
	JUMP_TAG(TAG_RETRY);
	break;

      case NODE_SPLAT:
	result = splat_value(rb_eval(self, node->nd_head));
	break;

      case NODE_TO_ARY:
	result = rb_ary_to_ary(rb_eval(self, node->nd_head));
	break;

      case NODE_SVALUE:
	result = avalue_splat(rb_eval(self, node->nd_head));
	if (result == Qundef) result = Qnil;
	break;

      case NODE_YIELD:
	if (node->nd_head) {
	    result = rb_eval(self, node->nd_head);
	    ruby_current_node = node;
	}
	else {
	    result = Qundef;	/* no arg */
	}
	SET_CURRENT_SOURCE();
	result = rb_yield_0(result, 0, 0, 0, node->nd_state);
	break;

      case NODE_RESCUE:
	{
	    volatile VALUE e_info = ruby_errinfo;
	    volatile int rescuing = 0;

	    PUSH_TAG(PROT_NONE);
	    if ((state = EXEC_TAG()) == 0) {
	      retry_entry:
		result = rb_eval(self, node->nd_head);
	    }
	    else if (rescuing) {
		if (rescuing < 0) {
		    /* in rescue argument, just reraise */
		}
		else if (state == TAG_RETRY) {
		    rescuing = state = 0;
		    ruby_errinfo = e_info;
		    goto retry_entry;
		}
		else if (state != TAG_RAISE) {
		    result = prot_tag->retval;
		}
	    }
	    else if (state == TAG_RAISE) {
		NODE *resq = node->nd_resq;

		rescuing = -1;
		while (resq) {
		    ruby_current_node = resq;
		    if (handle_rescue(self, resq)) {
			state = 0;
			rescuing = 1;
			result = rb_eval(self, resq->nd_body);
			break;
		    }
		    resq = resq->nd_head; /* next rescue */
		}
	    }
	    else {
		result = prot_tag->retval;
	    }
	    POP_TAG();
	    if (state != TAG_RAISE && state != TAG_FATAL) {
		ruby_errinfo = e_info;
	    }
	    if (state) {
		JUMP_TAG(state);
	    }
	    /* no exception raised */
	    if (!rescuing && (node = node->nd_else)) { /* else clause given */
		goto again;
	    }
	}
	break;

      case NODE_ENSURE:
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    result = rb_eval(self, node->nd_head);
	}
	POP_TAG();
	if (node->nd_ensr && !thread_no_ensure()) {
	    VALUE retval = prot_tag->retval; /* save retval */
	    VALUE errinfo = ruby_errinfo;

	    rb_eval(self, node->nd_ensr);
	    return_value(retval);
	    ruby_errinfo = errinfo;
	}
	if (state) JUMP_TAG(state);
	break;

      case NODE_AND:
	result = rb_eval(self, node->nd_1st);
	if (!RTEST(result)) break;
	node = node->nd_2nd;
	goto again;

      case NODE_OR:
	result = rb_eval(self, node->nd_1st);
	if (RTEST(result)) break;
	node = node->nd_2nd;
	goto again;

      case NODE_NOT:
	if (RTEST(rb_eval(self, node->nd_body))) result = Qfalse;
	else result = Qtrue;
	break;

      case NODE_DOT2:
      case NODE_DOT3:
        {
	    VALUE beg = rb_eval(self, node->nd_beg);
	    VALUE end = rb_eval(self, node->nd_end);
	    result = rb_range_new(beg, end, nd_type(node) == NODE_DOT3);
	}
	break;

      case NODE_FLIP2:		/* like AWK */
	{
	    VALUE *flip = rb_svar(node->nd_cnt);
	    if (!flip) rb_bug("unexpected local variable");
	    if (!RTEST(*flip)) {
		if (RTEST(rb_eval(self, node->nd_beg))) {
		    *flip = RTEST(rb_eval(self, node->nd_end))?Qfalse:Qtrue;
		    result = Qtrue;
		}
		else {
		    result = Qfalse;
		}
	    }
	    else {
		if (RTEST(rb_eval(self, node->nd_end))) {
		    *flip = Qfalse;
		}
		result = Qtrue;
	    }
	}
	break;

      case NODE_FLIP3:		/* like SED */
	{
	    VALUE *flip = rb_svar(node->nd_cnt);
	    if (!flip) rb_bug("unexpected local variable");
	    if (!RTEST(*flip)) {
		result = RTEST(rb_eval(self, node->nd_beg)) ? Qtrue : Qfalse;
		*flip = result;
	    }
	    else {
		if (RTEST(rb_eval(self, node->nd_end))) {
		    *flip = Qfalse;
		}
		result = Qtrue;
	    }
	}
	break;

      case NODE_RETURN:
	return_jump(rb_eval(self, node->nd_stts));
	break;

      case NODE_ARGSCAT:
	{
	    VALUE args = rb_eval(self, node->nd_head);
	    result = rb_ary_concat(args, splat_value(rb_eval(self, node->nd_body)));
	}
	break;

      case NODE_ARGSPUSH:
	{
	    VALUE args = rb_ary_dup(rb_eval(self, node->nd_head));
	    result = rb_ary_push(args, rb_eval(self, node->nd_body));
	}
	break;

      case NODE_ATTRASGN:
	{
	    VALUE recv;
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    int scope;
	    TMP_PROTECT;

	    BEGIN_CALLARGS;
	    if (node->nd_recv == (NODE *)1) {
		recv = self;
		scope = 1;
	    }
	    else {
		recv = rb_eval(self, node->nd_recv);
		scope = 0;
	    }
	    SETUP_ARGS(node->nd_args);
	    END_CALLARGS;

	    ruby_current_node = node;
	    SET_CURRENT_SOURCE();
	    rb_call(CLASS_OF(recv),recv,node->nd_mid,argc,argv,scope,self);
	    result = argv[argc-1];
	}
	break;

      case NODE_CALL:
	{
	    VALUE recv;
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    TMP_PROTECT;

	    BEGIN_CALLARGS;
	    recv = rb_eval(self, node->nd_recv);
	    SETUP_ARGS(node->nd_args);
	    END_CALLARGS;

	    ruby_current_node = node;
	    SET_CURRENT_SOURCE();
	    result = rb_call(CLASS_OF(recv),recv,node->nd_mid,argc,argv,0,self);
	}
	break;

      case NODE_FCALL:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    TMP_PROTECT;

	    BEGIN_CALLARGS;
	    SETUP_ARGS(node->nd_args);
	    END_CALLARGS;

	    ruby_current_node = node;
	    SET_CURRENT_SOURCE();
	    result = rb_call(CLASS_OF(self),self,node->nd_mid,argc,argv,1,self);
	}
	break;

      case NODE_VCALL:
	SET_CURRENT_SOURCE();
	result = rb_call(CLASS_OF(self),self,node->nd_mid,0,0,2,self);
	break;

      case NODE_SUPER:
      case NODE_ZSUPER:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    TMP_PROTECT;

	    if (ruby_frame->last_class == 0) {
		if (ruby_frame->last_func) {
		    rb_name_error(ruby_frame->last_func,
				  "superclass method `%s' disabled",
				  rb_id2name(ruby_frame->orig_func));
		}
		else {
		    rb_raise(rb_eNoMethodError, "super called outside of method");
		}
	    }
	    if (nd_type(node) == NODE_ZSUPER) {
		argc = ruby_frame->argc;
		if (argc && DMETHOD_P()) {
		    if (TYPE(RBASIC(ruby_scope)->klass) != T_ARRAY ||
			RARRAY(RBASIC(ruby_scope)->klass)->len != argc) {
			rb_raise(rb_eRuntimeError,
				 "super: specify arguments explicitly");
		    }
		    argv = RARRAY(RBASIC(ruby_scope)->klass)->ptr;
		}
		else if (ruby_frame->flags & FRAME_REST_ARG) {
		    VALUE rest = ruby_scope->local_vars[argc+2];

		    /* check if T_ARRAY */;
		    argv = TMP_ALLOC(argc + RARRAY(rest)->len);
		    MEMCPY(argv, ruby_scope->local_vars+2, VALUE, argc);
		    MEMCPY(argv+argc, RARRAY(rest)->ptr, VALUE, RARRAY(rest)->len);
		    argc += RARRAY(rest)->len;
		}
		else if (!ruby_scope->local_vars) {
		    argc = 0;
		    argv = 0;
		}
		else {
		    argv = ruby_scope->local_vars + 2;
		}
	    }
	    else {
		BEGIN_CALLARGS;
		SETUP_ARGS(node->nd_args);
		END_CALLARGS;
		ruby_current_node = node;
	    }

	    SET_CURRENT_SOURCE();
	    result = rb_call_super(argc, argv);
	}
	break;

      case NODE_SCOPE:
	{
	    struct FRAME frame;
	    NODE *saved_cref = 0;

	    frame = *ruby_frame;
	    frame.tmp = ruby_frame;
	    ruby_frame = &frame;

	    PUSH_SCOPE();
	    PUSH_TAG(PROT_NONE);
	    if (node->nd_rval) {
		saved_cref = ruby_cref;
		ruby_cref = (NODE*)node->nd_rval;
	    }
	    if (node->nd_tbl) {
		VALUE *vars = ALLOCA_N(VALUE, node->nd_tbl[0]+1);
		*vars++ = (VALUE)node;
		ruby_scope->local_vars = vars;
		rb_mem_clear(ruby_scope->local_vars, node->nd_tbl[0]);
		ruby_scope->local_tbl = node->nd_tbl;
	    }
	    else {
		ruby_scope->local_vars = 0;
		ruby_scope->local_tbl  = 0;
	    }
	    if ((state = EXEC_TAG()) == 0) {
		result = rb_eval(self, node->nd_next);
	    }
	    POP_TAG();
	    POP_SCOPE();
	    ruby_frame = frame.tmp;
	    if (saved_cref)
		ruby_cref = saved_cref;
	    if (state) JUMP_TAG(state);
	}
	break;

      case NODE_OP_ASGN1:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    VALUE recv, val, tmp;
	    NODE *rval;
	    TMP_PROTECT;

	    recv = rb_eval(self, node->nd_recv);
	    rval = node->nd_args->nd_head;
	    SETUP_ARGS0(node->nd_args->nd_body, 1);
	    val = rb_funcall3(recv, aref, argc, argv);
	    switch (node->nd_mid) {
	    case 0: /* OR */
	      if (RTEST(val)) RETURN(val);
	      val = rb_eval(self, rval);
	      break;
	    case 1: /* AND */
	      if (!RTEST(val)) RETURN(val);
	      val = rb_eval(self, rval);
	      break;
	    default:
	      tmp = rb_eval(self, rval);
	      val = rb_funcall3(val, node->nd_mid, 1, &tmp);
	    }
	    argv[argc] = val;
	    rb_funcall2(recv, aset, argc+1, argv);
	    result = val;
	}
	break;

      case NODE_OP_ASGN2:
	{
	    ID id = node->nd_next->nd_vid;
	    VALUE recv, val, tmp;

	    recv = rb_eval(self, node->nd_recv);
	    val = rb_funcall3(recv, id, 0, 0);
	    switch (node->nd_next->nd_mid) {
	    case 0: /* OR */
	      if (RTEST(val)) RETURN(val);
	      val = rb_eval(self, node->nd_value);
	      break;
	    case 1: /* AND */
	      if (!RTEST(val)) RETURN(val);
	      val = rb_eval(self, node->nd_value);
	      break;
	    default:
	      tmp = rb_eval(self, node->nd_value);
	      val = rb_funcall3(val, node->nd_next->nd_mid, 1, &tmp);
	    }

	    rb_funcall2(recv, node->nd_next->nd_aid, 1, &val);
	    result = val;
	}
	break;

      case NODE_OP_ASGN_AND:
	result = rb_eval(self, node->nd_head);
	if (!RTEST(result)) break;
	node = node->nd_value;
	goto again;

      case NODE_OP_ASGN_OR:
	if ((node->nd_aid && !is_defined(self, node->nd_head, 0)) ||
	    !RTEST(result = rb_eval(self, node->nd_head))) {
	    node = node->nd_value;
	    goto again;
	}
	break;

      case NODE_MASGN:
	result = massign(self, node, rb_eval(self, node->nd_value), 0);
	break;

      case NODE_LASGN:
	if (ruby_scope->local_vars == 0)
	    rb_bug("unexpected local variable assignment");
	result = rb_eval(self, node->nd_value);
	ruby_scope->local_vars[node->nd_cnt] = result;
	break;

      case NODE_DASGN:
	result = rb_eval(self, node->nd_value);
	dvar_asgn(node->nd_vid, result);
	break;

      case NODE_DASGN_CURR:
	result = rb_eval(self, node->nd_value);
	dvar_asgn_curr(node->nd_vid, result);
	break;

      case NODE_GASGN:
	result = rb_eval(self, node->nd_value);
	rb_gvar_set(node->nd_entry, result);
	break;

      case NODE_IASGN:
	result = rb_eval(self, node->nd_value);
	rb_ivar_set(self, node->nd_vid, result);
	break;

      case NODE_CDECL:
	result = rb_eval(self, node->nd_value);
	if (node->nd_vid == 0) {
	    rb_const_set(class_prefix(self, node->nd_else), node->nd_else->nd_mid, result);
	}
	else {
	    rb_const_set(ruby_cbase, node->nd_vid, result);
	}
	break;

      case NODE_CVDECL:
	if (NIL_P(ruby_cbase)) {
	    rb_raise(rb_eTypeError, "no class/module to define class variable");
	}
	result = rb_eval(self, node->nd_value);
	rb_cvar_set(cvar_cbase(), node->nd_vid, result, Qtrue);
	break;

      case NODE_CVASGN:
	result = rb_eval(self, node->nd_value);
	rb_cvar_set(cvar_cbase(), node->nd_vid, result, Qfalse);
	break;

      case NODE_LVAR:
	if (ruby_scope->local_vars == 0) {
	    rb_bug("unexpected local variable");
	}
	result = ruby_scope->local_vars[node->nd_cnt];
	break;

      case NODE_DVAR:
	result = rb_dvar_ref(node->nd_vid);
	break;

      case NODE_GVAR:
	result = rb_gvar_get(node->nd_entry);
	break;

      case NODE_IVAR:
	result = rb_ivar_get(self, node->nd_vid);
	break;

      case NODE_CONST:
	result = ev_const_get(ruby_cref, node->nd_vid, self);
	break;

      case NODE_CVAR:
	result = rb_cvar_get(cvar_cbase(), node->nd_vid);
	break;

      case NODE_BLOCK_ARG:
	if (ruby_scope->local_vars == 0)
	    rb_bug("unexpected block argument");
	if (rb_block_given_p()) {
	    result = rb_block_proc();
	    ruby_scope->local_vars[node->nd_cnt] = result;
	}
	else {
	    result = Qnil;
	}
	break;

      case NODE_COLON2:
	{
	    VALUE klass;

	    klass = rb_eval(self, node->nd_head);
	    if (rb_is_const_id(node->nd_mid)) {
		switch (TYPE(klass)) {
		  case T_CLASS:
		  case T_MODULE:
		    result = rb_const_get_from(klass, node->nd_mid);
		    break;
		  default:
		    rb_raise(rb_eTypeError, "%s is not a class/module",
			     RSTRING(rb_obj_as_string(klass))->ptr);
		    break;
		}
	    }
	    else {
		result = rb_funcall(klass, node->nd_mid, 0, 0);
	    }
	}
	break;

      case NODE_COLON3:
	result = rb_const_get_from(rb_cObject, node->nd_mid);
	break;

      case NODE_NTH_REF:
	result = rb_reg_nth_match(node->nd_nth, MATCH_DATA);
	break;

      case NODE_BACK_REF:
	switch (node->nd_nth) {
	  case '&':
	    result = rb_reg_last_match(MATCH_DATA);
	    break;
	  case '`':
	    result = rb_reg_match_pre(MATCH_DATA);
	    break;
	  case '\'':
	    result = rb_reg_match_post(MATCH_DATA);
	    break;
	  case '+':
	    result = rb_reg_match_last(MATCH_DATA);
	    break;
	  default:
	    rb_bug("unexpected back-ref");
	}
	break;

      case NODE_HASH:
	{
	    NODE *list;
	    VALUE hash = rb_hash_new();
	    VALUE key, val;

	    list = node->nd_head;
	    while (list) {
		key = rb_eval(self, list->nd_head);
		list = list->nd_next;
		if (list == 0)
		    rb_bug("odd number list for Hash");
		val = rb_eval(self, list->nd_head);
		list = list->nd_next;
		rb_hash_aset(hash, key, val);
	    }
	    result = hash;
	}
	break;

      case NODE_ZARRAY:		/* zero length list */
	result = rb_ary_new();
	break;

      case NODE_ARRAY:
	{
	    VALUE ary;
	    long i;

	    i = node->nd_alen;
	    ary = rb_ary_new2(i);
	    for (i=0;node;node=node->nd_next) {
		RARRAY(ary)->ptr[i++] = rb_eval(self, node->nd_head);
		RARRAY(ary)->len = i;
	    }

	    result = ary;
	}
	break;

      case NODE_STR:
	result = rb_str_new3(node->nd_lit);
	break;

      case NODE_EVSTR:
	result = rb_obj_as_string(rb_eval(self, node->nd_body));
	break;

      case NODE_DSTR:
      case NODE_DXSTR:
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
      case NODE_DSYM:
	{
	    VALUE str, str2;
	    NODE *list = node->nd_next;

	    str = rb_str_new3(node->nd_lit);
	    while (list) {
		if (list->nd_head) {
		    switch (nd_type(list->nd_head)) {
		      case NODE_STR:
			str2 = list->nd_head->nd_lit;
			break;
		      default:
			str2 = rb_eval(self, list->nd_head);
			break;
		    }
		    rb_str_append(str, str2);
		    OBJ_INFECT(str, str2);
		}
		list = list->nd_next;
	    }
	    switch (nd_type(node)) {
	      case NODE_DREGX:
		result = rb_reg_new(RSTRING(str)->ptr, RSTRING(str)->len,
				    node->nd_cflag);
		RB_GC_GUARD(str); /* ensure str is not GC'd in rb_reg_new */
		break;
	      case NODE_DREGX_ONCE:	/* regexp expand once */
		result = rb_reg_new(RSTRING(str)->ptr, RSTRING(str)->len,
				    node->nd_cflag);
		nd_set_type(node, NODE_LIT);
		RB_GC_GUARD(str); /* ensure str is not GC'd in rb_reg_new */
		node->nd_lit = result;
		break;
	      case NODE_LIT:
		/* other thread may replace NODE_DREGX_ONCE to NODE_LIT */
		goto again;
	      case NODE_DXSTR:
		result = rb_funcall(self, '`', 1, str);
		break;
	      case NODE_DSYM:
		result = rb_str_intern(str);
		break;
	      default:
		result = str;
		break;
	    }
	}
	break;

      case NODE_XSTR:
	result = rb_funcall(self, '`', 1, rb_str_new3(node->nd_lit));
	break;

      case NODE_LIT:
	result = node->nd_lit;
	break;

      case NODE_DEFN:
	if (node->nd_defn) {
	    NODE *body,  *defn;
	    VALUE origin = 0;
	    int noex;

	    if (NIL_P(ruby_class)) {
		rb_raise(rb_eTypeError, "no class/module to add method");
	    }
	    if (ruby_class == rb_cObject && node->nd_mid == init) {
		rb_warn("redefining Object#initialize may cause infinite loop");
	    }
	    if (node->nd_mid == __id__ || node->nd_mid == __send__) {
		rb_warn("redefining `%s' may cause serious problem",
			rb_id2name(node->nd_mid));
	    }
	    rb_frozen_class_p(ruby_class);
	    body = search_method(ruby_class, node->nd_mid, &origin);
	    if (body){
		if (RTEST(ruby_verbose) && ruby_class == origin && body->nd_cnt == 0 && body->nd_body) {
		    rb_warning("method redefined; discarding old %s", rb_id2name(node->nd_mid));
		}
	    }

	    if (SCOPE_TEST(SCOPE_PRIVATE) || node->nd_mid == init) {
		noex = NOEX_PRIVATE;
	    }
	    else if (SCOPE_TEST(SCOPE_PROTECTED)) {
		noex = NOEX_PROTECTED;
	    }
	    else {
		noex = NOEX_PUBLIC;
	    }
	    if (body && origin == ruby_class && body->nd_body == 0) {
		noex |= NOEX_NOSUPER;
	    }

	    defn = rb_copy_node_scope(node->nd_defn, ruby_cref);
	    rb_add_method(ruby_class, node->nd_mid, defn, noex);
	    if (scope_vmode == SCOPE_MODFUNC) {
		rb_add_method(rb_singleton_class(ruby_class),
			      node->nd_mid, defn, NOEX_PUBLIC);
	    }
	    result = Qnil;
	}
	break;

      case NODE_DEFS:
	if (node->nd_defn) {
	    VALUE recv = rb_eval(self, node->nd_recv);
	    VALUE klass;
	    NODE *body = 0, *defn;

	    if (ruby_safe_level >= 4 && !OBJ_TAINTED(recv)) {
		rb_raise(rb_eSecurityError, "Insecure: can't define singleton method");
	    }
	    if (FIXNUM_P(recv) || SYMBOL_P(recv)) {
		rb_raise(rb_eTypeError,
			 "can't define singleton method \"%s\" for %s",
			 rb_id2name(node->nd_mid),
			 rb_obj_classname(recv));
	    }

	    if (OBJ_FROZEN(recv)) rb_error_frozen("object");
	    klass = rb_singleton_class(recv);
	    if (st_lookup(RCLASS(klass)->m_tbl, node->nd_mid, &data)) {
		body = (NODE *)data;
		if (ruby_safe_level >= 4) {
		    rb_raise(rb_eSecurityError, "redefining method prohibited");
		}
		if (RTEST(ruby_verbose)) {
		    rb_warning("redefine %s", rb_id2name(node->nd_mid));
		}
	    }
	    defn = rb_copy_node_scope(node->nd_defn, ruby_cref);
	    rb_add_method(klass, node->nd_mid, defn,
			  NOEX_PUBLIC|(body?body->nd_noex&NOEX_UNDEF:0));
	    result = Qnil;
	}
	break;

      case NODE_UNDEF:
	if (NIL_P(ruby_class)) {
	    rb_raise(rb_eTypeError, "no class to undef method");
	}
	rb_undef(ruby_class, rb_to_id(rb_eval(self, node->u2.node)));
	result = Qnil;
	break;

      case NODE_ALIAS:
	if (NIL_P(ruby_class)) {
	    rb_raise(rb_eTypeError, "no class to make alias");
	}
	rb_alias(ruby_class, rb_to_id(rb_eval(self, node->u1.node)),
		             rb_to_id(rb_eval(self, node->u2.node)));
	result = Qnil;
	break;

      case NODE_VALIAS:
	rb_alias_variable(node->u1.id, node->u2.id);
	result = Qnil;
	break;

      case NODE_CLASS:
	{
	    VALUE super, klass, tmp, cbase;
	    ID cname;
	    int gen = Qfalse;

	    cbase = class_prefix(self, node->nd_cpath);
	    cname = node->nd_cpath->nd_mid;

	    if (NIL_P(ruby_cbase)) {
		rb_raise(rb_eTypeError, "no outer class/module");
	    }
	    if (node->nd_super) {
	       super = rb_eval(self, node->nd_super);
	       rb_check_inheritable(super);
	    }
	    else {
		super = 0;
	    }

	    if (rb_const_defined_at(cbase, cname)) {
		klass = rb_const_get_at(cbase, cname);
		if (TYPE(klass) != T_CLASS) {
		    rb_raise(rb_eTypeError, "%s is not a class",
			     rb_id2name(cname));
		}
		if (super) {
		    tmp = rb_class_real(RCLASS(klass)->super);
		    if (tmp != super) {
			rb_raise(rb_eTypeError, "superclass mismatch for class %s",
				 rb_id2name(cname));
		    }
		    super = 0;
		}
		if (ruby_safe_level >= 4) {
		    rb_raise(rb_eSecurityError, "extending class prohibited");
		}
	    }
	    else {
		if (!super) super = rb_cObject;
		klass = rb_define_class_id(cname, super);
		rb_set_class_path(klass, cbase, rb_id2name(cname));
		rb_const_set(cbase, cname, klass);
		gen = Qtrue;
	    }
	    if (ruby_wrapper) {
		rb_extend_object(klass, ruby_wrapper);
		rb_include_module(klass, ruby_wrapper);
	    }
	    if (super && gen) {
		rb_class_inherited(super, klass);
	    }
	    result = module_setup(klass, node);
	}
	break;

      case NODE_MODULE:
	{
	    VALUE module, cbase;
	    ID cname;

	    if (NIL_P(ruby_cbase)) {
		rb_raise(rb_eTypeError, "no outer class/module");
	    }
	    cbase = class_prefix(self, node->nd_cpath);
	    cname = node->nd_cpath->nd_mid;
	    if (rb_const_defined_at(cbase, cname)) {
		module = rb_const_get_at(cbase, cname);
		if (TYPE(module) != T_MODULE) {
		    rb_raise(rb_eTypeError, "%s is not a module",
			     rb_id2name(cname));
		}
		if (ruby_safe_level >= 4) {
		    rb_raise(rb_eSecurityError, "extending module prohibited");
		}
	    }
	    else {
		module = rb_define_module_id(cname);
		rb_set_class_path(module, cbase, rb_id2name(cname));
		rb_const_set(cbase, cname, module);
	    }
	    if (ruby_wrapper) {
		rb_extend_object(module, ruby_wrapper);
		rb_include_module(module, ruby_wrapper);
	    }

	    result = module_setup(module, node);
	}
	break;

      case NODE_SCLASS:
	{
	    VALUE klass;

	    result = rb_eval(self, node->nd_recv);
	    if (FIXNUM_P(result) || SYMBOL_P(result)) {
		rb_raise(rb_eTypeError, "no virtual class for %s",
			 rb_obj_classname(result));
	    }
	    if (ruby_safe_level >= 4 && !OBJ_TAINTED(result))
		rb_raise(rb_eSecurityError, "Insecure: can't extend object");
	    klass = rb_singleton_class(result);

	    if (ruby_wrapper) {
		rb_extend_object(klass, ruby_wrapper);
		rb_include_module(klass, ruby_wrapper);
	    }

	    result = module_setup(klass, node);
	}
	break;

      case NODE_DEFINED:
	{
	    char buf[20];
	    const char *desc = is_defined(self, node->nd_head, buf);

	    if (desc) result = rb_str_new2(desc);
	    else result = Qnil;
	}
	break;

      case NODE_NEWLINE:
	EXEC_EVENT_HOOK(RUBY_EVENT_LINE, node, self,
			ruby_frame->last_func,
			ruby_frame->last_class);
	node = node->nd_next;
	goto again;

      default:
	unknown_node(node);
    }
  finish:
    CHECK_INTS;
    if (contnode) {
	node = contnode;
	contnode = 0;
	goto again;
    }
    return result;
}

static VALUE
module_setup(module, n)
    VALUE module;
    NODE *n;
{
    NODE * volatile node = n->nd_body;
    int state;
    struct FRAME frame;
    VALUE result = Qnil;	/* OK */
    TMP_PROTECT;

    frame = *ruby_frame;
    frame.tmp = ruby_frame;
    ruby_frame = &frame;

    PUSH_CLASS(module);
    PUSH_SCOPE();
    PUSH_VARS();

    if (node->nd_tbl) {
	VALUE *vars = TMP_ALLOC(node->nd_tbl[0]+1);
	*vars++ = (VALUE)node;
	ruby_scope->local_vars = vars;
	rb_mem_clear(ruby_scope->local_vars, node->nd_tbl[0]);
	ruby_scope->local_tbl = node->nd_tbl;
    }
    else {
	ruby_scope->local_vars = 0;
	ruby_scope->local_tbl  = 0;
    }

    PUSH_CREF(module);
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	EXEC_EVENT_HOOK(RUBY_EVENT_CLASS, n, ruby_cbase,
			ruby_frame->last_func, ruby_frame->last_class);
	result = rb_eval(ruby_cbase, node->nd_next);
    }
    POP_TAG();
    POP_CREF();
    POP_VARS();
    POP_SCOPE();
    POP_CLASS();

    ruby_frame = frame.tmp;
    EXEC_EVENT_HOOK(RUBY_EVENT_END, n, 0,
		    ruby_frame->last_func, ruby_frame->last_class);
    if (state) JUMP_TAG(state);

    return result;
}

static NODE *basic_respond_to = 0;

int
rb_obj_respond_to(obj, id, priv)
    VALUE obj;
    ID id;
    int priv;
{
    VALUE klass = CLASS_OF(obj);

    if (rb_method_node(klass, respond_to) == basic_respond_to) {
	return rb_method_boundp(klass, id, !priv);
    }
    else {
	VALUE args[2];
	int n = 0;
	args[n++] = ID2SYM(id);
	if (priv) args[n++] = Qtrue;
	return RTEST(rb_funcall2(obj, respond_to, n, args));
    }
}

int
rb_respond_to(obj, id)
    VALUE obj;
    ID id;
{
    return rb_obj_respond_to(obj, id, Qfalse);
}

/*
 *  call-seq:
 *     obj.respond_to?(symbol, include_private=false) => true or false
 *
 *  Returns +true+> if _obj_ responds to the given
 *  method. Private methods are included in the search only if the
 *  optional second parameter evaluates to +true+.
 */

static VALUE
obj_respond_to(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE mid, priv;
    ID id;

    rb_scan_args(argc, argv, "11", &mid, &priv);
    id = rb_to_id(mid);
    if (rb_method_boundp(CLASS_OF(obj), id, !RTEST(priv))) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.method_defined?(symbol)    => true or false
 *
 *  Returns +true+ if the named method is defined by
 *  _mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors). Public and protected methods are matched.
 *
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1    #=> true
 *     C.method_defined? "method1"   #=> true
 *     C.method_defined? "method2"   #=> true
 *     C.method_defined? "method3"   #=> true
 *     C.method_defined? "method4"   #=> false
 */

static VALUE
rb_mod_method_defined(mod, mid)
    VALUE mod, mid;
{
    return rb_method_boundp(mod, rb_to_id(mid), 1);
}

#define VISI_CHECK(x,f) (((x)&NOEX_MASK) == (f))

/*
 *  call-seq:
 *     mod.public_method_defined?(symbol)   => true or false
 *
 *  Returns +true+ if the named public method is defined by
 *  _mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors).
 *
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       protected
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1           #=> true
 *     C.public_method_defined? "method1"   #=> true
 *     C.public_method_defined? "method2"   #=> false
 *     C.method_defined? "method2"          #=> true
 */

static VALUE
rb_mod_public_method_defined(mod, mid)
    VALUE mod, mid;
{
    ID id = rb_to_id(mid);
    int noex;

    if (rb_get_method_body(&mod, &id, &noex)) {
	if (VISI_CHECK(noex, NOEX_PUBLIC))
	    return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.private_method_defined?(symbol)    => true or false
 *
 *  Returns +true+ if the named private method is defined by
 *  _ mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors).
 *
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       private
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1            #=> true
 *     C.private_method_defined? "method1"   #=> false
 *     C.private_method_defined? "method2"   #=> true
 *     C.method_defined? "method2"           #=> false
 */

static VALUE
rb_mod_private_method_defined(mod, mid)
    VALUE mod, mid;
{
    ID id = rb_to_id(mid);
    int noex;

    if (rb_get_method_body(&mod, &id, &noex)) {
	if (VISI_CHECK(noex, NOEX_PRIVATE))
	    return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.protected_method_defined?(symbol)   => true or false
 *
 *  Returns +true+ if the named protected method is defined
 *  by _mod_ (or its included modules and, if _mod_ is a
 *  class, its ancestors).
 *
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       protected
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1              #=> true
 *     C.protected_method_defined? "method1"   #=> false
 *     C.protected_method_defined? "method2"   #=> true
 *     C.method_defined? "method2"             #=> true
 */

static VALUE
rb_mod_protected_method_defined(mod, mid)
    VALUE mod, mid;
{
    ID id = rb_to_id(mid);
    int noex;

    if (rb_get_method_body(&mod, &id, &noex)) {
	if (VISI_CHECK(noex, NOEX_PROTECTED))
	    return Qtrue;
    }
    return Qfalse;
}

NORETURN(static VALUE terminate_process _((int, VALUE)));
static VALUE
terminate_process(status, mesg)
    int status;
    VALUE mesg;
{
    VALUE args[2];
    args[0] = INT2NUM(status);
    args[1] = mesg;

    rb_exc_raise(rb_class_new_instance(2, args, rb_eSystemExit));
}

void
rb_exit(status)
    int status;
{
    if (prot_tag) {
	terminate_process(status, rb_str_new("exit", 4));
    }
    ruby_finalize();
    exit(status);
}


/*
 *  call-seq:
 *     exit(integer=0)
 *     Kernel::exit(integer=0)
 *     Process::exit(integer=0)
 *
 *  Initiates the termination of the Ruby script by raising the
 *  <code>SystemExit</code> exception. This exception may be caught. The
 *  optional parameter is used to return a status code to the invoking
 *  environment.
 *
 *     begin
 *       exit
 *       puts "never get here"
 *     rescue SystemExit
 *       puts "rescued a SystemExit exception"
 *     end
 *     puts "after begin block"
 *
 *  <em>produces:</em>
 *
 *     rescued a SystemExit exception
 *     after begin block
 *
 *  Just prior to termination, Ruby executes any <code>at_exit</code> functions
 *  (see Kernel::at_exit) and runs any object finalizers (see
 *  ObjectSpace::define_finalizer).
 *
 *     at_exit { puts "at_exit function" }
 *     ObjectSpace.define_finalizer("string",  proc { puts "in finalizer" })
 *     exit
 *
 *  <em>produces:</em>
 *
 *     at_exit function
 *     in finalizer
 */

VALUE
rb_f_exit(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE status;
    int istatus;

    rb_secure(4);
    if (rb_scan_args(argc, argv, "01", &status) == 1) {
	switch (status) {
	  case Qtrue:
	    istatus = EXIT_SUCCESS;
	    break;
	  case Qfalse:
	    istatus = EXIT_FAILURE;
	    break;
	  default:
	    istatus = NUM2INT(status);
#if EXIT_SUCCESS != 0
	    if (istatus == 0) istatus = EXIT_SUCCESS;
#endif
	    break;
	}
    }
    else {
	istatus = EXIT_SUCCESS;
    }
    rb_exit(istatus);
    return Qnil;		/* not reached */
}


/*
 *  call-seq:
 *     abort
 *     Kernel::abort
 *     Process::abort
 *
 *  Terminate execution immediately, effectively by calling
 *  <code>Kernel.exit(1)</code>. If _msg_ is given, it is written
 *  to STDERR prior to terminating.
 */

VALUE
rb_f_abort(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_secure(4);
    if (argc == 0) {
	if (!NIL_P(ruby_errinfo)) {
	    error_print();
	}
	rb_exit(EXIT_FAILURE);
    }
    else {
	VALUE mesg;

	rb_scan_args(argc, argv, "1", &mesg);
	StringValue(mesg);
	rb_io_puts(1, &mesg, rb_stderr);
	terminate_process(EXIT_FAILURE, mesg);
    }
    return Qnil;		/* not reached */
}

void
rb_iter_break()
{
    break_jump(Qnil);
}

NORETURN(static void rb_longjmp _((int, VALUE)));
static VALUE make_backtrace _((void));

static void
rb_longjmp(tag, mesg)
    int tag;
    VALUE mesg;
{
    VALUE at;
    rb_thread_t th = curr_thread;

    if (rb_thread_set_raised(th)) {
	ruby_errinfo = exception_error;
	rb_thread_reset_raised(th);
	JUMP_TAG(TAG_FATAL);
    }
    if (NIL_P(mesg)) mesg = ruby_errinfo;
    if (NIL_P(mesg)) {
	mesg = rb_exc_new(rb_eRuntimeError, 0, 0);
    }

    ruby_set_current_source();
    if (ruby_sourcefile && !NIL_P(mesg)) {
	at = get_backtrace(mesg);
	if (NIL_P(at)) {
	    at = make_backtrace();
	    if (OBJ_FROZEN(mesg)) {
		mesg = rb_obj_dup(mesg);
	    }
	    set_backtrace(mesg, at);
	}
    }
    if (!NIL_P(mesg)) {
	ruby_errinfo = mesg;
    }

    if (RTEST(ruby_debug) && !NIL_P(ruby_errinfo)
	&& !rb_obj_is_kind_of(ruby_errinfo, rb_eSystemExit)) {
	VALUE e = ruby_errinfo;
	int status;

	PUSH_TAG(PROT_NONE);
	if ((status = EXEC_TAG()) == 0) {
	    StringValue(e);
	    warn_printf("Exception `%s' at %s:%d - %s\n",
			rb_obj_classname(ruby_errinfo),
			ruby_sourcefile, ruby_sourceline,
			RSTRING(e)->ptr);
	}
	POP_TAG();
	if (status == TAG_FATAL && ruby_errinfo == exception_error) {
	    ruby_errinfo = mesg;
	}
	else if (status) {
	    rb_thread_reset_raised(th);
	    JUMP_TAG(status);
	}
    }

    rb_trap_restore_mask();
    if (tag != TAG_FATAL) {
	EXEC_EVENT_HOOK(RUBY_EVENT_RAISE, ruby_current_node,
			ruby_frame->self,
			ruby_frame->last_func,
			ruby_frame->last_class);
    }
    if (!prot_tag) {
	error_print();
    }
    rb_thread_raised_clear(th);
    JUMP_TAG(tag);
}

void
rb_exc_jump(mesg)
    VALUE mesg;
{
    rb_thread_raised_clear(rb_curr_thread);
    ruby_errinfo = mesg;
    JUMP_TAG(TAG_RAISE);
}

void
rb_exc_raise(mesg)
    VALUE mesg;
{
    mesg = rb_make_exception(1, &mesg);
    rb_longjmp(TAG_RAISE, mesg);
}

void
rb_exc_fatal(mesg)
    VALUE mesg;
{
    mesg = rb_make_exception(1, &mesg);
    rb_longjmp(TAG_FATAL, mesg);
}

void
rb_interrupt()
{
    static const char fmt[1] = {'\0'};
    rb_raise(rb_eInterrupt, fmt);
}

/*
 *  call-seq:
 *     raise
 *     raise(string)
 *     raise(exception [, string [, array]])
 *     fail
 *     fail(string)
 *     fail(exception [, string [, array]])
 *
 *  With no arguments, raises the exception in <code>$!</code> or raises
 *  a <code>RuntimeError</code> if <code>$!</code> is +nil+.
 *  With a single +String+ argument, raises a
 *  +RuntimeError+ with the string as a message. Otherwise,
 *  the first parameter should be the name of an +Exception+
 *  class (or an object that returns an +Exception+ object when sent
 *  an +exception+ message). The optional second parameter sets the
 *  message associated with the exception, and the third parameter is an
 *  array of callback information. Exceptions are caught by the
 *  +rescue+ clause of <code>begin...end</code> blocks.
 *
 *     raise "Failed to create socket"
 *     raise ArgumentError, "No parameters", caller
 */

static VALUE
rb_f_raise(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_raise_jump(rb_make_exception(argc, argv));
    return Qnil;		/* not reached */
}

static VALUE
rb_make_exception(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE mesg;
    ID exception;
    int n;

    mesg = Qnil;
    switch (argc) {
      case 0:
	mesg = Qnil;
	break;
      case 1:
	if (NIL_P(argv[0])) break;
	if (TYPE(argv[0]) == T_STRING) {
	    mesg = rb_exc_new3(rb_eRuntimeError, argv[0]);
	    break;
	}
	n = 0;
	goto exception_call;

      case 2:
      case 3:
	n = 1;
      exception_call:
	exception = rb_intern("exception");
	if (!rb_respond_to(argv[0], exception)) {
	    rb_raise(rb_eTypeError, "exception class/object expected");
	}
	mesg = rb_funcall(argv[0], exception, n, argv[1]);
	break;
      default:
	rb_raise(rb_eArgError, "wrong number of arguments");
	break;
    }
    if (argc > 0) {
	if (!rb_obj_is_kind_of(mesg, rb_eException))
	    rb_raise(rb_eTypeError, "exception object expected");
	if (argc>2)
	    set_backtrace(mesg, argv[2]);
    }

    return mesg;
}

static void
rb_raise_jump(mesg)
    VALUE mesg;
{
    if (ruby_frame != top_frame) {
	PUSH_FRAME();		/* fake frame */
	*ruby_frame = *_frame.prev->prev;
	rb_longjmp(TAG_RAISE, mesg);
	POP_FRAME();
    }
    rb_longjmp(TAG_RAISE, mesg);
}

void
rb_jump_tag(tag)
    int tag;
{
    JUMP_TAG(tag);
}

int
rb_block_given_p()
{
    if (ruby_frame->iter == ITER_CUR && ruby_block)
	return Qtrue;
    return Qfalse;
}

int
rb_iterator_p()
{
    return rb_block_given_p();
}

/*
 *  call-seq:
 *     block_given?   => true or false
 *     iterator?      => true or false
 *
 *  Returns <code>true</code> if <code>yield</code> would execute a
 *  block in the current context. The <code>iterator?</code> form
 *  is mildly deprecated.
 *
 *     def try
 *       if block_given?
 *         yield
 *       else
 *         "no block"
 *       end
 *     end
 *     try                  #=> "no block"
 *     try { "hello" }      #=> "hello"
 *     try do "hello" end   #=> "hello"
 */


static VALUE
rb_f_block_given_p()
{
    if (ruby_frame->prev && ruby_frame->prev->iter == ITER_CUR && ruby_block)
	return Qtrue;
    return Qfalse;
}

VALUE rb_eThreadError;

NORETURN(static void proc_jump_error(int, VALUE));
static void
proc_jump_error(state, result)
    int state;
    VALUE result;
{
    char mesg[32];
    const char *statement;

    switch (state) {
      case TAG_BREAK:
	statement = "break"; break;
      case TAG_RETURN:
	statement = "return"; break;
      case TAG_RETRY:
	statement = "retry"; break;
      default:
	statement = "local-jump"; break; /* should not happen */
    }
    snprintf(mesg, sizeof mesg, "%s from proc-closure", statement);
    localjump_error(mesg, result, state);
}

static void
return_jump(retval)
    VALUE retval;
{
    struct tag *tt = prot_tag;
    int yield = Qfalse;

    if (retval == Qundef) retval = Qnil;
    while (tt) {
	if (tt->tag == PROT_YIELD) {
	    yield = Qtrue;
	    tt = tt->prev;
	}
	if (tt->tag == PROT_FUNC && tt->frame->uniq == ruby_frame->uniq) {
	    tt->dst = (VALUE)ruby_frame->uniq;
	    tt->retval = retval;
	    JUMP_TAG(TAG_RETURN);
	}
	if (tt->tag == PROT_LAMBDA && !yield) {
	    tt->dst = (VALUE)tt->frame->uniq;
	    tt->retval = retval;
	    JUMP_TAG(TAG_RETURN);
	}
	if (tt->tag == PROT_THREAD) {
	    rb_raise(rb_eThreadError, "return can't jump across threads");
	}
	tt = tt->prev;
    }
    localjump_error("unexpected return", retval, TAG_RETURN);
}

static void
break_jump(retval)
    VALUE retval;
{
    struct tag *tt = prot_tag;

    if (retval == Qundef) retval = Qnil;
    while (tt) {
	switch (tt->tag) {
	  case PROT_THREAD:
	  case PROT_YIELD:
	  case PROT_LOOP:
	  case PROT_LAMBDA:
	    tt->dst = (VALUE)tt->frame->uniq;
	    tt->retval = retval;
	    JUMP_TAG(TAG_BREAK);
	    break;
	  case PROT_FUNC:
	    tt = 0;
	    continue;
	  default:
	    break;
	}
	tt = tt->prev;
    }
    localjump_error("unexpected break", retval, TAG_BREAK);
}

static void
next_jump(retval)
    VALUE retval;
{
    struct tag *tt = prot_tag;

    if (retval == Qundef) retval = Qnil;
    while (tt) {
	switch (tt->tag) {
	  case PROT_THREAD:
	  case PROT_YIELD:
	  case PROT_LOOP:
	  case PROT_LAMBDA:
	  case PROT_FUNC:
	    tt->dst = (VALUE)tt->frame->uniq;
	    tt->retval = retval;
	    JUMP_TAG(TAG_NEXT);
	    break;
	  default:
	    break;
	}
	tt = tt->prev;
    }
    localjump_error("unexpected next", retval, TAG_NEXT);
}

void
rb_need_block()
{
    if (!rb_block_given_p()) {
	localjump_error("no block given", Qnil, 0);
    }
}

static VALUE
rb_yield_0(val, self, klass, flags, avalue)
    VALUE val, self, klass;	/* OK */
    int flags, avalue;
{
    NODE *node, *var;
    volatile VALUE result = Qnil;
    volatile VALUE old_cref;
    volatile VALUE old_wrapper;
    struct BLOCK * volatile block;
    struct SCOPE * volatile old_scope;
    int old_vmode;
    struct FRAME frame;
    NODE *cnode = ruby_current_node;
    int lambda = flags & YIELD_LAMBDA_CALL;
    int state;

    rb_need_block();

    PUSH_VARS();
    block = ruby_block;
    frame = block->frame;
    frame.prev = ruby_frame;
    frame.node = cnode;
    ruby_frame = &(frame);
    old_cref = (VALUE)ruby_cref;
    ruby_cref = block->cref;
    old_wrapper = ruby_wrapper;
    ruby_wrapper = block->wrapper;
    old_scope = ruby_scope;
    ruby_scope = block->scope;
    old_vmode = scope_vmode;
    scope_vmode = (flags & YIELD_PUBLIC_DEF) ? SCOPE_PUBLIC : block->vmode;
    ruby_block = block->prev;
    if (block->flags & BLOCK_D_SCOPE) {
	/* put place holder for dynamic (in-block) local variables */
	ruby_dyna_vars = new_dvar(0, 0, block->dyna_vars);
    }
    else {
	/* FOR does not introduce new scope */
	ruby_dyna_vars = block->dyna_vars;
    }
    PUSH_CLASS(klass ? klass : block->klass);
    if (!klass) {
	self = block->self;
    }
    node = block->body;
    var = block->var;

    if (var) {
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    NODE *bvar = NULL;
	  block_var:
	    if (var == (NODE*)1) { /* no parameter || */
		if (lambda && RARRAY(val)->len != 0) {
		    rb_raise(rb_eArgError, "wrong number of arguments (%ld for 0)",
			     RARRAY(val)->len);
		}
	    }
	    else if (var == (NODE*)2) {
		if (TYPE(val) == T_ARRAY && RARRAY(val)->len != 0) {
		    rb_raise(rb_eArgError, "wrong number of arguments (%ld for 0)",
			     RARRAY(val)->len);
		}
	    }
	    else if (!bvar && nd_type(var) == NODE_BLOCK_PASS) {
		bvar = var->nd_body;
		var = var->nd_args;
		goto block_var;
	    }
	    else if (nd_type(var) == NODE_MASGN) {
		if (!avalue) {
		    val = svalue_to_mrhs(val, var->nd_head);
		}
		massign(self, var, val, lambda);
	    }
	    else {
		int len = 0;
		if (avalue) {
		    len = RARRAY(val)->len;
		    if (len == 0) {
			goto zero_arg;
		    }
		    if (len == 1) {
			val = RARRAY(val)->ptr[0];
		    }
		    else {
			goto multi_values;
		    }
		}
		else if (val == Qundef) {
		  zero_arg:
		    val = Qnil;
		  multi_values:
		    {
			ruby_current_node = var;
			rb_warn("multiple values for a block parameter (%d for 1)\n\tfrom %s:%d",
				len, cnode->nd_file, nd_line(cnode));
			ruby_current_node = cnode;
		    }
		}
		assign(self, var, val, lambda);
	    }
	    if (bvar) {
		VALUE blk;
		if (flags & YIELD_PROC_CALL)
		    blk = block->block_obj;
		else
		    blk = rb_block_proc();
		assign(self, bvar, blk, 0);
	    }
	}
	POP_TAG();
	if (state) goto pop_state;
    }
    if (!node) {
	state = 0;
	goto pop_state;
    }
    ruby_current_node = node;

    PUSH_ITER(block->iter);
    PUSH_TAG(lambda ? PROT_NONE : PROT_YIELD);
    if ((state = EXEC_TAG()) == 0) {
      redo:
	if (nd_type(node) == NODE_CFUNC || nd_type(node) == NODE_IFUNC) {
	    switch (node->nd_state) {
	      case YIELD_FUNC_LAMBDA:
		if (!avalue) {
		    val = (val == Qundef) ? rb_ary_new2(0) : rb_ary_new3(1, val);
		}
		break;
	      case YIELD_FUNC_AVALUE:
		if (!avalue) {
		    val = svalue_to_avalue(val);
		}
		break;
	      default:
		if (avalue) {
		    val = avalue_to_svalue(val);
		}
		if (val == Qundef && node->nd_state != YIELD_FUNC_SVALUE)
		    val = Qnil;
	    }
	    result = (*node->nd_cfnc)(val, node->nd_tval, self);
	}
	else {
	    result = rb_eval(self, node);
	}
    }
    else {
	switch (state) {
	  case TAG_REDO:
	    state = 0;
	    CHECK_INTS;
	    goto redo;
	  case TAG_NEXT:
	    if (!lambda) {
		state = 0;
		result = prot_tag->retval;
	    }
	    break;
	  case TAG_BREAK:
	    if (TAG_DST()) {
		result = prot_tag->retval;
	    }
	    else {
		lambda = Qtrue;	/* just pass TAG_BREAK */
	    }
	    break;
	  default:
	    break;
	}
    }
    POP_TAG();
    POP_ITER();
  pop_state:
    POP_CLASS();
    if (ruby_dyna_vars && (block->flags & BLOCK_D_SCOPE) &&
	!FL_TEST(ruby_dyna_vars, DVAR_DONT_RECYCLE)) {
	struct RVarmap *vars = ruby_dyna_vars;

	if (ruby_dyna_vars->id == 0) {
	    vars = ruby_dyna_vars->next;
	    rb_gc_force_recycle((VALUE)ruby_dyna_vars);
	    while (vars && vars->id != 0 && vars != block->dyna_vars) {
		struct RVarmap *tmp = vars->next;
		rb_gc_force_recycle((VALUE)vars);
		vars = tmp;
	    }
	}
    }
    POP_VARS();
    ruby_block = block;
    ruby_frame = ruby_frame->prev;
    ruby_cref = (NODE*)old_cref;
    ruby_wrapper = old_wrapper;
    if (ruby_scope->flags & SCOPE_DONT_RECYCLE)
	scope_dup(old_scope);
    ruby_scope = old_scope;
    scope_vmode = old_vmode;
    switch (state) {
      case 0:
	break;
      case TAG_BREAK:
	if (!lambda) {
	    struct tag *tt = prot_tag;

	    while (tt) {
		if (tt->tag == PROT_LOOP && tt->blkid == ruby_block->uniq) {
		    tt->dst = (VALUE)tt->frame->uniq;
		    tt->retval = result;
		    JUMP_TAG(TAG_BREAK);
		}
		tt = tt->prev;
	    }
	    proc_jump_error(TAG_BREAK, result);
	}
	/* fall through */
      default:
	JUMP_TAG(state);
	break;
    }
    ruby_current_node = cnode;
    return result;
}

VALUE
rb_yield(val)
    VALUE val;
{
    return rb_yield_0(val, 0, 0, 0, Qfalse);
}

VALUE
#ifdef HAVE_STDARG_PROTOTYPES
rb_yield_values(int n, ...)
#else
rb_yield_values(n, va_alist)
    int n;
    va_dcl
#endif
{
    va_list args;
    VALUE ary;

    if (n == 0) {
	return rb_yield_0(Qundef, 0, 0, 0, Qfalse);
    }
    ary = rb_ary_new2(n);
    va_init_list(args, n);
    while (n--) {
	rb_ary_push(ary, va_arg(args, VALUE));
    }
    va_end(args);
    return rb_yield_0(ary, 0, 0, 0, Qtrue);
}

VALUE
rb_yield_splat(values)
    VALUE values;
{
    int avalue = Qfalse;

    if (TYPE(values) == T_ARRAY) {
	if (RARRAY(values)->len == 0) {
	    values = Qundef;
	}
	else {
	    avalue = Qtrue;
	}
    }
    return rb_yield_0(values, 0, 0, 0, avalue);
}

static VALUE
loop_i()
{
    for (;;) {
	rb_yield_0(Qundef, 0, 0, 0, Qfalse);
	CHECK_INTS;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     loop {|| block }
 *
 *  Repeatedly executes the block.
 *
 *     loop do
 *       print "Input: "
 *       line = gets
 *       break if !line or line =~ /^qQ/
 *       # ...
 *     end
 *
 *  StopIteration raised in the block breaks the loop.
 */

static VALUE
rb_f_loop(self)
    VALUE self;
{
    RETURN_ENUMERATOR(self, 0, 0);
    rb_rescue2(loop_i, (VALUE)0, 0, 0, rb_eStopIteration, (VALUE)0);
    return Qnil;		/* dummy */
}

static VALUE
massign(self, node, val, pcall)
    VALUE self;
    NODE *node;
    VALUE val;
    int pcall;
{
    NODE *list;
    long i = 0, len;

    len = RARRAY(val)->len;
    list = node->nd_head;
    for (; list && i<len; i++) {
	assign(self, list->nd_head, RARRAY(val)->ptr[i], pcall);
	list = list->nd_next;
    }
    if (pcall && list) goto arg_error;
    if (node->nd_args) {
	if ((long)(node->nd_args) == -1) {
	    /* no check for mere `*' */
	}
	else if (!list && i<len) {
	    assign(self, node->nd_args, rb_ary_new4(len-i, RARRAY(val)->ptr+i), pcall);
	}
	else {
	    assign(self, node->nd_args, rb_ary_new2(0), pcall);
	}
    }
    else if (pcall && i < len) {
	goto arg_error;
    }

    while (list) {
	i++;
	assign(self, list->nd_head, Qnil, pcall);
	list = list->nd_next;
    }
    return val;

  arg_error:
    while (list) {
	i++;
	list = list->nd_next;
    }
    rb_raise(rb_eArgError, "wrong number of arguments (%ld for %ld)", len, i);
}

static void
assign(self, lhs, val, pcall)
    VALUE self;
    NODE *lhs;
    VALUE val;
    int pcall;
{
    ruby_current_node = lhs;
    if (val == Qundef) {
	rb_warning("assigning void value");
	val = Qnil;
    }
    switch (nd_type(lhs)) {
      case NODE_GASGN:
	rb_gvar_set(lhs->nd_entry, val);
	break;

      case NODE_IASGN:
	rb_ivar_set(self, lhs->nd_vid, val);
	break;

      case NODE_LASGN:
	if (ruby_scope->local_vars == 0)
	    rb_bug("unexpected local variable assignment");
	ruby_scope->local_vars[lhs->nd_cnt] = val;
	break;

      case NODE_DASGN:
	dvar_asgn(lhs->nd_vid, val);
	break;

      case NODE_DASGN_CURR:
	dvar_asgn_curr(lhs->nd_vid, val);
	break;

      case NODE_CDECL:
	if (lhs->nd_vid == 0) {
	    rb_const_set(class_prefix(self, lhs->nd_else), lhs->nd_else->nd_mid, val);
	}
	else {
	    rb_const_set(ruby_cbase, lhs->nd_vid, val);
	}
	break;

      case NODE_CVDECL:
	if (RTEST(ruby_verbose) && FL_TEST(ruby_cbase, FL_SINGLETON)) {
	    rb_warn("declaring singleton class variable");
	}
	rb_cvar_set(cvar_cbase(), lhs->nd_vid, val, Qtrue);
	break;

      case NODE_CVASGN:
	rb_cvar_set(cvar_cbase(), lhs->nd_vid, val, Qfalse);
	break;

      case NODE_MASGN:
	massign(self, lhs, svalue_to_mrhs(val, lhs->nd_head), pcall);
	break;

      case NODE_CALL:
      case NODE_ATTRASGN:
	{
	    VALUE recv;
	    int scope;
	    if (lhs->nd_recv == (NODE *)1) {
		recv = self;
		scope = 1;
	    }
	    else {
		recv = rb_eval(self, lhs->nd_recv);
		scope = 0;
	    }
	    if (!lhs->nd_args) {
		/* attr set */
		ruby_current_node = lhs;
		SET_CURRENT_SOURCE();
		rb_call(CLASS_OF(recv), recv, lhs->nd_mid, 1, &val, scope, self);
	    }
	    else {
		/* array set */
		VALUE args;

		args = rb_eval(self, lhs->nd_args);
		rb_ary_push(args, val);
		ruby_current_node = lhs;
		SET_CURRENT_SOURCE();
		rb_call(CLASS_OF(recv), recv, lhs->nd_mid,
			RARRAY(args)->len, RARRAY(args)->ptr, scope, self);
	    }
	}
	break;

      default:
	rb_bug("bug in variable assignment");
	break;
    }
}

VALUE
rb_iterate(it_proc, data1, bl_proc, data2)
    VALUE (*it_proc) _((VALUE)), (*bl_proc)(ANYARGS);
    VALUE data1, data2;
{
    int state;
    volatile VALUE retval = Qnil;
    NODE *node = NEW_IFUNC(bl_proc, data2);
    VALUE self = ruby_top_self;

    PUSH_TAG(PROT_LOOP);
    PUSH_BLOCK(0, node);
    PUSH_ITER(ITER_PRE);
    state = EXEC_TAG();
    if (state == 0) {
  iter_retry:
	retval = (*it_proc)(data1);
    }
    else if (state == TAG_BREAK && TAG_DST()) {
	retval = prot_tag->retval;
	state = 0;
    }
    else if (state == TAG_RETRY) {
	state = 0;
	goto iter_retry;
    }
    POP_ITER();
    POP_BLOCK();
    POP_TAG();

    switch (state) {
      case 0:
	break;
      default:
	JUMP_TAG(state);
    }
    return retval;
}

static int
handle_rescue(self, node)
    VALUE self;
    NODE *node;
{
    int argc; VALUE *argv; /* used in SETUP_ARGS */
    TMP_PROTECT;

    if (!node->nd_args) {
	return rb_obj_is_kind_of(ruby_errinfo, rb_eStandardError);
    }

    BEGIN_CALLARGS;
    SETUP_ARGS(node->nd_args);
    END_CALLARGS;

    while (argc--) {
	if (!rb_obj_is_kind_of(argv[0], rb_cModule)) {
	    rb_raise(rb_eTypeError, "class or module required for rescue clause");
	}
	if (RTEST(rb_funcall(*argv, eqq, 1, ruby_errinfo))) return 1;
	argv++;
    }
    return 0;
}

VALUE
#ifdef HAVE_STDARG_PROTOTYPES
rb_rescue2(VALUE (*b_proc)(ANYARGS), VALUE data1, VALUE (*r_proc)(ANYARGS), VALUE data2, ...)
#else
rb_rescue2(b_proc, data1, r_proc, data2, va_alist)
    VALUE (*b_proc)(ANYARGS), (*r_proc)(ANYARGS);
    VALUE data1, data2;
    va_dcl
#endif
{
    int state;
    volatile VALUE result;
    volatile VALUE e_info = ruby_errinfo;
    volatile int handle = Qfalse;
    VALUE eclass;
    va_list args;

    PUSH_TAG(PROT_NONE);
    switch (state = EXEC_TAG()) {
      case TAG_RETRY:
	if (!handle) break;
	handle = Qfalse;
	state = 0;
	ruby_errinfo = Qnil;
      case 0:
	result = (*b_proc)(data1);
	break;
      case TAG_RAISE:
	if (handle) break;
	handle = Qfalse;
	va_init_list(args, data2);
	while ((eclass = va_arg(args, VALUE)) != 0) {
	    if (rb_obj_is_kind_of(ruby_errinfo, eclass)) {
		handle = Qtrue;
		break;
	    }
	}
	va_end(args);

	if (handle) {
	    state = 0;
	    if (r_proc) {
		result = (*r_proc)(data2, ruby_errinfo);
	    }
	    else {
		result = Qnil;
	    }
	    ruby_errinfo = e_info;
	}
    }
    POP_TAG();
    if (state) JUMP_TAG(state);

    return result;
}

VALUE
rb_rescue(b_proc, data1, r_proc, data2)
    VALUE (*b_proc)(), (*r_proc)();
    VALUE data1, data2;
{
    return rb_rescue2(b_proc, data1, r_proc, data2, rb_eStandardError, (VALUE)0);
}

static VALUE cont_protect;

VALUE
rb_protect(proc, data, state)
    VALUE (*proc) _((VALUE));
    VALUE data;
    int *state;
{
    VALUE result = Qnil;	/* OK */
    int status;

    PUSH_ANCHOR();
    cont_protect = (VALUE)rb_node_newnode(NODE_MEMO, cont_protect, 0, 0);
    if ((status = EXEC_TAG()) == 0) {
	result = (*proc)(data);
    }
    else if (status == TAG_THREAD) {
	rb_thread_start_1();
    }
    cont_protect = ((NODE *)cont_protect)->u1.value;
    POP_ANCHOR();
    if (state) {
	*state = status;
    }
    if (status != 0) {
	return Qnil;
    }

    return result;
}

VALUE
rb_ensure(b_proc, data1, e_proc, data2)
    VALUE (*b_proc)();
    VALUE data1;
    VALUE (*e_proc)();
    VALUE data2;
{
    int state;
    volatile VALUE result = Qnil;
    VALUE retval;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	result = (*b_proc)(data1);
    }
    POP_TAG();
    retval = prot_tag ? prot_tag->retval : Qnil;	/* save retval */
    if (!thread_no_ensure()) {
	(*e_proc)(data2);
    }
    if (prot_tag) return_value(retval);
    if (state) JUMP_TAG(state);
    return result;
}

VALUE
rb_with_disable_interrupt(proc, data)
    VALUE (*proc)();
    VALUE data;
{
    VALUE result = Qnil;	/* OK */
    int status;

    DEFER_INTS;
    {
	int thr_critical = rb_thread_critical;

	rb_thread_critical = Qtrue;
	PUSH_TAG(PROT_NONE);
	if ((status = EXEC_TAG()) == 0) {
	    result = (*proc)(data);
	}
	POP_TAG();
	rb_thread_critical = thr_critical;
    }
    ENABLE_INTS;
    if (status) JUMP_TAG(status);

    return result;
}

static void
stack_check()
{
    rb_thread_t th = rb_curr_thread;

    if (!rb_thread_raised_p(th, RAISED_STACKOVERFLOW) && ruby_stack_check()) {
	rb_thread_raised_set(th, RAISED_STACKOVERFLOW);
	rb_exc_raise(sysstack_error);
    }
}

static void
eval_check_tick()
{
    static int tick;
    if ((++tick & 0xff) == 0) {
	CHECK_INTS;		/* better than nothing */
	stack_check();
	rb_gc_finalize_deferred();
    }
}

static int last_call_status;

#define CSTAT_PRIV  1
#define CSTAT_PROT  2
#define CSTAT_VCALL 4
#define CSTAT_SUPER 8

/*
 *  call-seq:
 *     obj.method_missing(symbol [, *args] )   => result
 *
 *  Invoked by Ruby when <i>obj</i> is sent a message it cannot handle.
 *  <i>symbol</i> is the symbol for the method called, and <i>args</i>
 *  are any arguments that were passed to it. By default, the interpreter
 *  raises an error when this method is called. However, it is possible
 *  to override the method to provide more dynamic behavior.
 *  The example below creates
 *  a class <code>Roman</code>, which responds to methods with names
 *  consisting of roman numerals, returning the corresponding integer
 *  values.
 *
 *     class Roman
 *       def romanToInt(str)
 *         # ...
 *       end
 *       def method_missing(methId)
 *         str = methId.id2name
 *         romanToInt(str)
 *       end
 *     end
 *
 *     r = Roman.new
 *     r.iv      #=> 4
 *     r.xxiii   #=> 23
 *     r.mm      #=> 2000
 */

static VALUE
rb_method_missing(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    ID id;
    VALUE exc = rb_eNoMethodError;
    const char *format = 0;
    NODE *cnode = ruby_current_node;

    if (argc == 0 || !SYMBOL_P(argv[0])) {
	rb_raise(rb_eArgError, "no id given");
    }

    stack_check();

    id = SYM2ID(argv[0]);

    if (last_call_status & CSTAT_PRIV) {
	format = "private method `%s' called for %s";
    }
    else if (last_call_status & CSTAT_PROT) {
	format = "protected method `%s' called for %s";
    }
    else if (last_call_status & CSTAT_VCALL) {
	format = "undefined local variable or method `%s' for %s";
	exc = rb_eNameError;
    }
    else if (last_call_status & CSTAT_SUPER) {
	format = "super: no superclass method `%s' for %s";
    }
    if (!format) {
	format = "undefined method `%s' for %s";
    }

    ruby_current_node = cnode;
    {
	int n = 0;
	VALUE args[3];

	args[n++] = rb_funcall(rb_const_get(exc, rb_intern("message")), '!',
			       3, rb_str_new2(format), obj, argv[0]);
	args[n++] = argv[0];
	if (exc == rb_eNoMethodError) {
	    args[n++] = rb_ary_new4(argc-1, argv+1);
	}
	exc = rb_class_new_instance(n, args, exc);
	ruby_frame = ruby_frame->prev; /* pop frame for "method_missing" */
	rb_exc_raise(exc);
    }

    return Qnil;		/* not reached */
}

static VALUE
method_missing(obj, id, argc, argv, call_status)
    VALUE obj;
    ID    id;
    int   argc;
    const VALUE *argv;
    int   call_status;
{
    VALUE *nargv;

    last_call_status = call_status;

    if (id == missing) {
	PUSH_FRAME();
	rb_method_missing(argc, argv, obj);
	POP_FRAME();
    }
    else if (id == ID_ALLOCATOR) {
	rb_raise(rb_eTypeError, "allocator undefined for %s", rb_class2name(obj));
    }
    if (argc < 0) {
	VALUE tmp;

	argc = -argc-1;
	tmp = splat_value(argv[argc]);
	nargv = ALLOCA_N(VALUE, argc + RARRAY(tmp)->len + 1);
	MEMCPY(nargv+1, argv, VALUE, argc);
	MEMCPY(nargv+1+argc, RARRAY(tmp)->ptr, VALUE, RARRAY(tmp)->len);
	argc += RARRAY(tmp)->len;
    }
    else {
	nargv = ALLOCA_N(VALUE, argc+1);
	MEMCPY(nargv+1, argv, VALUE, argc);
    }
    nargv[0] = ID2SYM(id);
    return rb_funcall2(obj, missing, argc+1, nargv);
}

static inline VALUE
call_cfunc(func, recv, len, argc, argv)
    VALUE (*func)();
    VALUE recv;
    int len, argc;
    VALUE *argv;
{
    if (len >= 0 && argc != len) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
		 argc, len);
    }

    switch (len) {
      case -2:
	return (*func)(recv, rb_ary_new4(argc, argv));
	break;
      case -1:
	return (*func)(argc, argv, recv);
	break;
      case 0:
	return (*func)(recv);
	break;
      case 1:
	return (*func)(recv, argv[0]);
	break;
      case 2:
	return (*func)(recv, argv[0], argv[1]);
	break;
      case 3:
	return (*func)(recv, argv[0], argv[1], argv[2]);
	break;
      case 4:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3]);
	break;
      case 5:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4]);
	break;
      case 6:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5]);
	break;
      case 7:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6]);
	break;
      case 8:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6], argv[7]);
	break;
      case 9:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6], argv[7], argv[8]);
	break;
      case 10:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6], argv[7], argv[8], argv[9]);
	break;
      case 11:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
	break;
      case 12:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6], argv[7], argv[8], argv[9],
		       argv[10], argv[11]);
	break;
      case 13:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6], argv[7], argv[8], argv[9], argv[10],
		       argv[11], argv[12]);
	break;
      case 14:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6], argv[7], argv[8], argv[9], argv[10],
		       argv[11], argv[12], argv[13]);
	break;
      case 15:
	return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4],
		       argv[5], argv[6], argv[7], argv[8], argv[9], argv[10],
		       argv[11], argv[12], argv[13], argv[14]);
	break;
      default:
	rb_raise(rb_eArgError, "too many arguments (%d)", len);
	break;
    }
    return Qnil;		/* not reached */
}

static VALUE
rb_call0(klass, recv, id, oid, argc, argv, body, flags)
    VALUE klass, recv;
    ID    id;
    ID    oid;
    int argc;			/* OK */
    VALUE *argv;		/* OK */
    NODE * volatile body;
    int flags;
{
    NODE *b2;		/* OK */
    volatile VALUE result = Qnil;
    int itr;
    TMP_PROTECT;
    volatile int safe = -1;

    if (NOEX_SAFE(flags) > ruby_safe_level && NOEX_SAFE(flags) > 2) {
	rb_raise(rb_eSecurityError, "calling insecure method: %s",
		 rb_id2name(id));
    }
    switch (ruby_iter->iter) {
      case ITER_PRE:
      case ITER_PAS:
	itr = ITER_CUR;
	break;
      case ITER_CUR:
      default:
	itr = ITER_NOT;
	break;
    }

    eval_check_tick();
    if (argc < 0) {
	VALUE tmp;
	VALUE *nargv;

	argc = -argc-1;
	tmp = splat_value(argv[argc]);
	nargv = TMP_ALLOC(argc + RARRAY(tmp)->len);
	MEMCPY(nargv, argv, VALUE, argc);
	MEMCPY(nargv+argc, RARRAY(tmp)->ptr, VALUE, RARRAY(tmp)->len);
	argc += RARRAY(tmp)->len;
	argv = nargv;
    }
    PUSH_ITER(itr);
    PUSH_FRAME();

    ruby_frame->last_func = id;
    ruby_frame->orig_func = oid;
    ruby_frame->last_class = (flags & NOEX_NOSUPER)?0:klass;
    ruby_frame->self = recv;
    ruby_frame->argc = argc;
    ruby_frame->flags = 0;

    switch (nd_type(body)) {
      case NODE_CFUNC:
	{
	    int len = body->nd_argc;

	    if (len < -2) {
		rb_bug("bad argc (%d) specified for `%s(%s)'",
		       len, rb_class2name(klass), rb_id2name(id));
	    }
	    if (event_hooks) {
		int state;

		EXEC_EVENT_HOOK(RUBY_EVENT_C_CALL, ruby_current_node,
				recv, id, klass);
		PUSH_TAG(PROT_FUNC);
		if ((state = EXEC_TAG()) == 0) {
		    result = call_cfunc(body->nd_cfnc, recv, len, argc, argv);
		}
		POP_TAG();
		ruby_current_node = ruby_frame->node;
		EXEC_EVENT_HOOK(RUBY_EVENT_C_RETURN, ruby_current_node,
				recv, id, klass);
		if (state) JUMP_TAG(state);
	    }
	    else {
		result = call_cfunc(body->nd_cfnc, recv, len, argc, argv);
	    }
	}
	break;

	/* for attr get/set */
      case NODE_IVAR:
	if (argc != 0) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)", argc);
	}
	result = rb_attr_get(recv, body->nd_vid);
	break;

      case NODE_ATTRSET:
	if (argc != 1)
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", argc);
	result = rb_ivar_set(recv, body->nd_vid, argv[0]);
	break;

      case NODE_ZSUPER:
	result = rb_call_super(argc, argv);
	break;

      case NODE_DMETHOD:
	result = method_call(argc, argv, umethod_bind(body->nd_cval, recv));
	break;

      case NODE_BMETHOD:
	ruby_frame->flags |= FRAME_DMETH;
	if (event_hooks) {
	    struct BLOCK *data;
	    Data_Get_Struct(body->nd_cval, struct BLOCK, data);
	    EXEC_EVENT_HOOK(RUBY_EVENT_CALL, data->body, recv, id, klass);
	}
	result = proc_invoke(body->nd_cval, rb_ary_new4(argc, argv), recv, klass);
	if (event_hooks) {
	    EXEC_EVENT_HOOK(RUBY_EVENT_RETURN, ruby_current_node, recv, id, klass);
	}
	break;

      case NODE_SCOPE:
	{
	    int state;
	    VALUE *local_vars;	/* OK */
	    NODE *saved_cref = 0;

	    PUSH_SCOPE();
	    if (body->nd_rval) {
		saved_cref = ruby_cref;
		ruby_cref = (NODE*)body->nd_rval;
	    }
	    PUSH_CLASS(ruby_cbase);
	    if (body->nd_tbl) {
		local_vars = TMP_ALLOC(body->nd_tbl[0]+1);
		*local_vars++ = (VALUE)body;
		rb_mem_clear(local_vars, body->nd_tbl[0]);
		ruby_scope->local_tbl = body->nd_tbl;
		ruby_scope->local_vars = local_vars;
	    }
	    else {
		local_vars = ruby_scope->local_vars = 0;
		ruby_scope->local_tbl  = 0;
	    }
	    b2 = body = body->nd_next;

	    if (NOEX_SAFE(flags) > ruby_safe_level) {
		safe = ruby_safe_level;
		ruby_safe_level = NOEX_SAFE(flags);
	    }
	    PUSH_VARS();
	    PUSH_TAG(PROT_FUNC);
	    if ((state = EXEC_TAG()) == 0) {
		NODE *node = 0;
		int i, nopt = 0;

		if (nd_type(body) == NODE_ARGS) {
		    node = body;
		    body = 0;
		}
		else if (nd_type(body) == NODE_BLOCK) {
		    node = body->nd_head;
		    body = body->nd_next;
		}
		if (node) {
                    if (nd_type(node) == NODE_FCALL) {
                        eval_node(recv, node);
                    }
		    else if (nd_type(node) != NODE_ARGS) {
			rb_bug("no argument-node");
		    }

		    i = node->nd_cnt;
		    if (i > argc) {
			rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
				 argc, i);
		    }
		    if (!node->nd_rest) {
			NODE *optnode = node->nd_opt;

			nopt = i;
			while (optnode) {
			    nopt++;
			    optnode = optnode->nd_next;
			}
			if (nopt < argc) {
			    rb_raise(rb_eArgError,
				     "wrong number of arguments (%d for %d)",
				     argc, nopt);
			}
		    }
		    if (local_vars) {
			if (i > 0) {
			    /* +2 for $_ and $~ */
			    MEMCPY(local_vars+2, argv, VALUE, i);
			}
		    }
		    argv += i; argc -= i;
		    if (node->nd_opt) {
			NODE *opt = node->nd_opt;

			while (opt && argc) {
			    assign(recv, opt->nd_head, *argv, 1);
			    argv++; argc--;
			    ++i;
			    opt = opt->nd_next;
			}
			if (opt) {
			    rb_eval(recv, opt);
			    while (opt) {
				opt = opt->nd_next;
				++i;
			    }
			}
		    }
		    if (!node->nd_rest) {
			i = nopt;
		    }
		    else {
			VALUE v;

			if (argc > 0) {
			    v = rb_ary_new4(argc,argv);
			    i = -i - 1;
			}
			else {
			    ruby_frame->flags |= FRAME_REST_ARG;
			    v = rb_ary_new2(0);
			}
			assign(recv, node->nd_rest, v, 1);
		    }
		    ruby_frame->argc = i;
		}
		if (event_hooks) {
		    EXEC_EVENT_HOOK(RUBY_EVENT_CALL, b2, recv, id, klass);
		}
		result = rb_eval(recv, body);
	    }
	    else if (state == TAG_RETURN && TAG_DST()) {
		result = prot_tag->retval;
		state = 0;
	    }
	    POP_TAG();
	    if (event_hooks) {
		EXEC_EVENT_HOOK(RUBY_EVENT_RETURN, ruby_current_node, recv, id, klass);
	    }
	    POP_VARS();
	    POP_CLASS();
	    POP_SCOPE();
	    ruby_cref = saved_cref;
	    if (safe >= 0) ruby_safe_level = safe;
	    switch (state) {
	      case 0:
		break;

	      case TAG_BREAK:
	      case TAG_RETURN:
		JUMP_TAG(state);
		break;

	      case TAG_RETRY:
		if (rb_block_given_p()) JUMP_TAG(state);
		/* fall through */
	      default:
		jump_tag_but_local_jump(state, result);
		break;
	    }
	}
	break;

      default:
	unknown_node(body);
	break;
    }
    POP_FRAME();
    POP_ITER();
    return result;
}

static VALUE
rb_call(klass, recv, mid, argc, argv, scope, self)
    VALUE klass, recv;
    ID    mid;
    int argc;			/* OK */
    const VALUE *argv;		/* OK */
    int scope;
    VALUE self;
{
    NODE  *body;		/* OK */
    int    noex;
    ID     id = mid;
    struct cache_entry *ent;

    if (!klass) {
	rb_raise(rb_eNotImpError, "method `%s' called on terminated object (0x%lx)",
		 rb_id2name(mid), recv);
    }
    /* is it in the method cache? */
    ent = cache + EXPR1(klass, mid);
    if (ent->mid == mid && ent->klass == klass) {
	if (!ent->method)
	    goto nomethod;
	klass = ent->origin;
	id    = ent->mid0;
	noex  = ent->noex;
	body  = ent->method;
    }
    else if ((body = rb_get_method_body(&klass, &id, &noex)) == 0) {
      nomethod:
	if (scope == 3) {
	    return method_missing(recv, mid, argc, argv, CSTAT_SUPER);
	}
	return method_missing(recv, mid, argc, argv, scope==2?CSTAT_VCALL:0);
    }

    if (mid != missing && scope == 0) {
	/* receiver specified form for private method */
	if (noex & NOEX_PRIVATE)
	    return method_missing(recv, mid, argc, argv, CSTAT_PRIV);

	/* self must be kind of a specified form for protected method */
	if (noex & NOEX_PROTECTED) {
	    VALUE defined_class = klass;

	    if (self == Qundef) self = ruby_frame->self;
	    if (TYPE(defined_class) == T_ICLASS) {
		defined_class = RBASIC(defined_class)->klass;
	    }
	    if (!rb_obj_is_kind_of(self, rb_class_real(defined_class)))
		return method_missing(recv, mid, argc, argv, CSTAT_PROT);
	}
    }

    return rb_call0(klass, recv, mid, id, argc, argv, body, noex);
}

VALUE
rb_apply(recv, mid, args)
    VALUE recv;
    ID mid;
    VALUE args;
{
    int argc;
    VALUE *argv;

    argc = RARRAY(args)->len; /* Assigns LONG, but argc is INT */
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, 1, Qundef);
}

/*
 *  call-seq:
 *     obj.send(symbol [, args...])        => obj
 *     obj.__send__(symbol [, args...])    => obj
 *
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified. You can use <code>\_\_send__</code> if the name
 *  +send+ clashes with an existing method in _obj_.
 *
 *     class Klass
 *       def hello(*args)
 *         "Hello " + args.join(' ')
 *       end
 *     end
 *     k = Klass.new
 *     k.send :hello, "gentle", "readers"   #=> "Hello gentle readers"
 */

static VALUE
rb_f_send(argc, argv, recv)
    int argc;
    VALUE *argv;
    VALUE recv;
{
    VALUE vid;

    if (argc == 0) rb_raise(rb_eArgError, "no method name given");

    vid = *argv++; argc--;
    PUSH_ITER(rb_block_given_p()?ITER_PRE:ITER_NOT);
    vid = rb_call(CLASS_OF(recv), recv, rb_to_id(vid), argc, argv, 1, Qundef);
    POP_ITER();

    return vid;
}

static VALUE
vafuncall(recv, mid, n, ar)
    VALUE recv;
    ID mid;
    int n;
    va_list *ar;
{
    VALUE *argv;

    if (n > 0) {
	long i;

	argv = ALLOCA_N(VALUE, n);

	for (i=0;i<n;i++) {
	    argv[i] = va_arg(*ar, VALUE);
	}
	va_end(*ar);
    }
    else {
	argv = 0;
    }

    return rb_call(CLASS_OF(recv), recv, mid, n, argv, 1, Qundef);
}

VALUE
#ifdef HAVE_STDARG_PROTOTYPES
rb_funcall(VALUE recv, ID mid, int n, ...)
#else
rb_funcall(recv, mid, n, va_alist)
    VALUE recv;
    ID mid;
    int n;
    va_dcl
#endif
{
    va_list ar;
    va_init_list(ar, n);

    return vafuncall(recv, mid, n, &ar);
}

VALUE
#ifdef HAVE_STDARG_PROTOTYPES
rb_funcall_rescue(VALUE recv, ID mid, int n, ...)
#else
rb_funcall_rescue(recv, mid, n, va_alist)
    VALUE recv;
    ID mid;
    int n;
    va_dcl
#endif
{
    VALUE result = Qnil;	/* OK */
    int status;
    va_list ar;

    va_init_list(ar, n);

    PUSH_TAG(PROT_NONE);
    if ((status = EXEC_TAG()) == 0) {
	result = vafuncall(recv, mid, n, &ar);
    }
    POP_TAG();
    switch (status) {
      case 0:
	return result;
      case TAG_RAISE:
	return Qundef;
      default:
	JUMP_TAG(status);
    }
}

VALUE
rb_funcall2(recv, mid, argc, argv)
    VALUE recv;
    ID mid;
    int argc;
    const VALUE *argv;
{
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, 1, Qundef);
}

VALUE
rb_funcall3(recv, mid, argc, argv)
    VALUE recv;
    ID mid;
    int argc;
    const VALUE *argv;
{
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, 0, Qundef);
}

VALUE
rb_call_super(argc, argv)
    int argc;
    const VALUE *argv;
{
    VALUE result, self, klass;

    if (ruby_frame->last_class == 0) {
	rb_name_error(ruby_frame->last_func, "calling `super' from `%s' is prohibited",
		      rb_id2name(ruby_frame->orig_func));
    }

    self = ruby_frame->self;
    klass = ruby_frame->last_class;
    if (RCLASS(klass)->super == 0) {
	return method_missing(self, ruby_frame->orig_func, argc, argv, CSTAT_SUPER);
    }

    PUSH_ITER(ruby_iter->iter ? ITER_PRE : ITER_NOT);
    result = rb_call(RCLASS(klass)->super, self, ruby_frame->orig_func, argc, argv, 3, Qundef);
    POP_ITER();

    return result;
}

static VALUE
backtrace(lev)
    int lev;
{
    struct FRAME *frame = ruby_frame;
    char buf[BUFSIZ];
    VALUE ary;
    NODE *n;

    ary = rb_ary_new();
    if (frame->last_func == ID_ALLOCATOR) {
	frame = frame->prev;
    }
    if (lev < 0) {
	ruby_set_current_source();
	if (frame->last_func) {
	    snprintf(buf, BUFSIZ, "%s:%d:in `%s'",
		     ruby_sourcefile, ruby_sourceline,
		     rb_id2name(frame->last_func));
	}
	else if (ruby_sourceline == 0) {
	    snprintf(buf, BUFSIZ, "%s", ruby_sourcefile);
	}
	else {
	    snprintf(buf, BUFSIZ, "%s:%d", ruby_sourcefile, ruby_sourceline);
	}
	rb_ary_push(ary, rb_str_new2(buf));
	if (lev < -1) return ary;
    }
    else {
	while (lev-- > 0) {
	    frame = frame->prev;
	    if (!frame) {
		ary = Qnil;
		break;
	    }
	}
    }
    for (; frame && (n = frame->node); frame = frame->prev) {
	if (frame->prev && frame->prev->last_func) {
	    if (frame->prev->node == n) {
		if (frame->prev->last_func == frame->last_func) continue;
	    }
	    snprintf(buf, BUFSIZ, "%s:%d:in `%s'",
		     n->nd_file, nd_line(n),
		     rb_id2name(frame->prev->last_func));
	}
	else {
	    snprintf(buf, BUFSIZ, "%s:%d", n->nd_file, nd_line(n));
	}
	rb_ary_push(ary, rb_str_new2(buf));
    }

    return ary;
}

/*
 *  call-seq:
 *     caller(start=1)    => array
 *
 *  Returns the current execution stack---an array containing strings in
 *  the form ``<em>file:line</em>'' or ``<em>file:line: in
 *  `method'</em>''. The optional _start_ parameter
 *  determines the number of initial stack entries to omit from the
 *  result.
 *
 *     def a(skip)
 *       caller(skip)
 *     end
 *     def b(skip)
 *       a(skip)
 *     end
 *     def c(skip)
 *       b(skip)
 *     end
 *     c(0)   #=> ["prog:2:in `a'", "prog:5:in `b'", "prog:8:in `c'", "prog:10"]
 *     c(1)   #=> ["prog:5:in `b'", "prog:8:in `c'", "prog:11"]
 *     c(2)   #=> ["prog:8:in `c'", "prog:12"]
 *     c(3)   #=> ["prog:13"]
 */

static VALUE
rb_f_caller(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE level;
    int lev;

    rb_scan_args(argc, argv, "01", &level);

    if (NIL_P(level)) lev = 1;
    else lev = NUM2INT(level);
    if (lev < 0) rb_raise(rb_eArgError, "negative level (%d)", lev);

    return backtrace(lev);
}

void
rb_backtrace()
{
    long i;
    VALUE ary;

    ary = backtrace(-1);
    for (i=0; i<RARRAY(ary)->len; i++) {
	printf("\tfrom %s\n", RSTRING(RARRAY(ary)->ptr[i])->ptr);
    }
}

static VALUE
make_backtrace()
{
    return backtrace(-1);
}

ID
rb_frame_last_func()
{
    return ruby_frame->last_func;
}

ID
rb_frame_this_func()
{
    return ruby_frame->orig_func;
}

static NODE*
compile(src, file, line)
    VALUE src;
    const char *file;
    int line;
{
    NODE *node;
    int critical;

    ruby_nerrs = 0;
    StringValue(src);
    critical = rb_thread_critical;
    rb_thread_critical = Qtrue;
    node = rb_compile_string(file, src, line);
    rb_thread_critical = critical;

    if (ruby_nerrs == 0) return node;
    return 0;
}

static VALUE
eval(self, src, scope, file, line)
    VALUE self, src, scope;
    const char *file;
    int line;
{
    struct BLOCK *data = NULL;
    volatile VALUE result = Qnil;
    struct SCOPE * volatile old_scope;
    struct BLOCK * volatile old_block;
    struct RVarmap * volatile old_dyna_vars;
    VALUE volatile old_cref;
    int volatile old_vmode;
    volatile VALUE old_wrapper;
    struct FRAME frame;
    NODE *nodesave = ruby_current_node;
    volatile int iter = ruby_frame->iter;
    volatile int safe = ruby_safe_level;
    int state;

    if (!NIL_P(scope)) {
	if (!rb_obj_is_proc(scope)) {
	    rb_raise(rb_eTypeError, "wrong argument type %s (expected Proc/Binding)",
		     rb_obj_classname(scope));
	}

	Data_Get_Struct(scope, struct BLOCK, data);
	/* PUSH BLOCK from data */
	frame = data->frame;
	frame.tmp = ruby_frame;	/* gc protection */
	ruby_frame = &(frame);
	old_scope = ruby_scope;
	ruby_scope = data->scope;
	old_block = ruby_block;
	ruby_block = data->prev;
	old_dyna_vars = ruby_dyna_vars;
	ruby_dyna_vars = data->dyna_vars;
	old_vmode = scope_vmode;
	scope_vmode = data->vmode;
	old_cref = (VALUE)ruby_cref;
	ruby_cref = data->cref;
	old_wrapper = ruby_wrapper;
	ruby_wrapper = data->wrapper;
	if ((file == 0 || (line == 1 && strcmp(file, "(eval)") == 0)) && data->frame.node) {
	    file = data->frame.node->nd_file;
	    if (!file) file = "__builtin__";
	    line = nd_line(data->frame.node);
	}

	self = data->self;
	ruby_frame->iter = data->iter;
    }
    else {
	if (ruby_frame->prev) {
	    ruby_frame->iter = ruby_frame->prev->iter;
	}
    }
    if (file == 0) {
	ruby_set_current_source();
	file = ruby_sourcefile;
	line = ruby_sourceline;
    }
    PUSH_CLASS(data ? data->klass : ruby_class);
    ruby_in_eval++;
    if (TYPE(ruby_class) == T_ICLASS) {
	ruby_class = RBASIC(ruby_class)->klass;
    }
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	NODE *node;

	ruby_safe_level = 0;
	result = ruby_errinfo;
	ruby_errinfo = Qnil;
	node = compile(src, file, line);
	ruby_safe_level = safe;
	if (ruby_nerrs > 0) {
	    compile_error(0);
	}
	if (!NIL_P(result)) ruby_errinfo = result;
	result = eval_node(self, node);
    }
    POP_TAG();
    POP_CLASS();
    ruby_in_eval--;
    if (!NIL_P(scope)) {
	int dont_recycle = ruby_scope->flags & SCOPE_DONT_RECYCLE;

	ruby_wrapper = old_wrapper;
	ruby_cref  = (NODE*)old_cref;
	ruby_frame = frame.tmp;
	ruby_scope = old_scope;
	ruby_block = old_block;
	ruby_dyna_vars = old_dyna_vars;
	data->vmode = scope_vmode; /* write back visibility mode */
	scope_vmode = old_vmode;
	if (dont_recycle) {
	    struct tag *tag;
	    struct RVarmap *vars;

	    scope_dup(ruby_scope);
	    for (tag=prot_tag; tag; tag=tag->prev) {
		scope_dup(tag->scope);
	    }
	    for (vars = ruby_dyna_vars; vars; vars = vars->next) {
		FL_SET(vars, DVAR_DONT_RECYCLE);
	    }
	}
    }
    else {
	ruby_frame->iter = iter;
    }
    ruby_current_node = nodesave;
    ruby_set_current_source();
    if (state) {
	if (state == TAG_RAISE) {
	    if (strcmp(file, "(eval)") == 0) {
		VALUE mesg, errat, bt2;
		ID id_mesg;

		id_mesg = rb_intern("mesg");
		errat = get_backtrace(ruby_errinfo);
		mesg = rb_attr_get(ruby_errinfo, id_mesg);
		if (!NIL_P(errat) && TYPE(errat) == T_ARRAY &&
		    (bt2 = backtrace(-2), RARRAY_LEN(bt2) > 0)) {
		    if (!NIL_P(mesg) && TYPE(mesg) == T_STRING) {
			if (OBJ_FROZEN(mesg)) {
			    VALUE m = rb_str_cat(rb_str_dup(RARRAY_PTR(errat)[0]), ": ", 2);
			    rb_ivar_set(ruby_errinfo, id_mesg, rb_str_append(m, mesg));
			}
			else {
			    rb_str_update(mesg, 0, 0, rb_str_new2(": "));
			    rb_str_update(mesg, 0, 0, RARRAY_PTR(errat)[0]);
			}
		    }
		    RARRAY_PTR(errat)[0] = RARRAY_PTR(bt2)[0];
		}
	    }
	    rb_exc_raise(ruby_errinfo);
	}
	JUMP_TAG(state);
    }

    return result;
}

VALUE
rb_eval_prelude(src, name)
    VALUE src;
    const char *name;
{
    return eval(ruby_top_self, src, Qnil, name, 1);
}

/*
 *  call-seq:
 *     eval(string [, binding [, filename [,lineno]]])  => obj
 *
 *  Evaluates the Ruby expression(s) in <em>string</em>. If
 *  <em>binding</em> is given, the evaluation is performed in its
 *  context. The binding may be a <code>Binding</code> object or a
 *  <code>Proc</code> object. If the optional <em>filename</em> and
 *  <em>lineno</em> parameters are present, they will be used when
 *  reporting syntax errors.
 *
 *     def getBinding(str)
 *       return binding
 *     end
 *     str = "hello"
 *     eval "str + ' Fred'"                      #=> "hello Fred"
 *     eval "str + ' Fred'", getBinding("bye")   #=> "bye Fred"
 */

static VALUE
rb_f_eval(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE src, scope, vfile, vline;
    const char *file = "(eval)";
    int line = 1;

    rb_scan_args(argc, argv, "13", &src, &scope, &vfile, &vline);
    if (ruby_safe_level >= 4) {
	StringValue(src);
	if (!NIL_P(scope) && !OBJ_TAINTED(scope)) {
	    rb_raise(rb_eSecurityError, "Insecure: can't modify trusted binding");
	}
    }
    else {
	SafeStringValue(src);
    }
    if (argc >= 3) {
	StringValue(vfile);
    }
    if (argc >= 4) {
	line = NUM2INT(vline);
    }

    if (!NIL_P(vfile)) file = RSTRING(vfile)->ptr;
    if (NIL_P(scope) && ruby_frame->prev) {
	struct FRAME *prev;
	VALUE val;

	prev = ruby_frame;
	PUSH_FRAME();
	*ruby_frame = *prev->prev;
	ruby_frame->prev = prev;
	val = eval(self, src, scope, file, line);
	POP_FRAME();

	return val;
    }
    return eval(self, src, scope, file, line);
}

/* function to call func under the specified class/module context */
static VALUE
exec_under(func, under, cbase, args)
    VALUE (*func)();
    VALUE under, cbase;
    void *args;
{
    VALUE val = Qnil;		/* OK */
    int state;
    int mode;
    struct FRAME *f = ruby_frame;

    PUSH_CLASS(under);
    PUSH_FRAME();
    ruby_frame->self = f->self;
    ruby_frame->last_func = f->last_func;
    ruby_frame->orig_func = f->orig_func;
    ruby_frame->last_class = f->last_class;
    ruby_frame->argc = f->argc;
    if (cbase) {
	PUSH_CREF(cbase);
    }

    mode = scope_vmode;
    SCOPE_SET(SCOPE_PUBLIC);
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	val = (*func)(args);
    }
    POP_TAG();
    if (cbase) POP_CREF();
    SCOPE_SET(mode);
    POP_FRAME();
    POP_CLASS();
    if (state) JUMP_TAG(state);

    return val;
}

static VALUE
eval_under_i(args)
    VALUE *args;
{
    struct FRAME *f = ruby_frame;

    if (f && (f = f->prev) && (f = f->prev)) {
	ruby_frame = f;
    }
    return eval(args[0], args[1], Qnil, (char*)args[2], (int)args[3]);
}

/* string eval under the class/module context */
static VALUE
eval_under(under, self, src, file, line)
    VALUE under, self, src;
    const char *file;
    int line;
{
    VALUE args[4];

    if (ruby_safe_level >= 4) {
	StringValue(src);
    }
    else {
	SafeStringValue(src);
    }
    args[0] = self;
    args[1] = src;
    args[2] = (VALUE)file;
    args[3] = (VALUE)line;
    return exec_under(eval_under_i, under, under, args);
}

static VALUE
yield_under_i(self)
    VALUE self;
{
    return rb_yield_0(self, self, ruby_class, YIELD_PUBLIC_DEF, Qfalse);
}

static VALUE
yield_args_under_i(vinfo)
    VALUE vinfo;
{
    VALUE *info = (VALUE *)vinfo;

    return rb_yield_0(info[0], info[1], ruby_class, YIELD_PUBLIC_DEF, Qtrue);
}

/* block eval under the class/module context */
static VALUE
yield_under(under, self, args)
    VALUE under, self, args;
{
    if (args == Qundef) {
	return exec_under(yield_under_i, under, 0, self);
    }
    else {
	VALUE info[2];

	info[0] = args;
	info[1] = self;
	return exec_under(yield_args_under_i, under, 0, (VALUE)info);
    }
}

static VALUE
specific_eval(argc, argv, klass, self)
    int argc;
    VALUE *argv;
    VALUE klass, self;
{
    if (rb_block_given_p()) {
	if (argc > 0) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)", argc);
	}
	return yield_under(klass, self, Qundef);
    }
    else {
	const char *file = "(eval)";
	int   line = 1;

	if (argc == 0) {
	    rb_raise(rb_eArgError, "block not supplied");
	}
	else {
	    if (ruby_safe_level >= 4) {
		StringValue(argv[0]);
	    }
	    else {
		SafeStringValue(argv[0]);
	    }
	    if (argc > 3) {
		rb_raise(rb_eArgError, "wrong number of arguments: %s(src) or %s{..}",
			 rb_id2name(ruby_frame->last_func),
			 rb_id2name(ruby_frame->last_func));
	    }
	    if (argc > 2) line = NUM2INT(argv[2]);
	    if (argc > 1) {
		file = StringValuePtr(argv[1]);
	    }
	}
	return eval_under(klass, self, argv[0], file, line);
    }
}

/*
 *  call-seq:
 *     obj.instance_eval(string [, filename [, lineno]] )   => obj
 *     obj.instance_eval {| | block }                       => obj
 *
 *  Evaluates a string containing Ruby source code, or the given block,
 *  within the context of the receiver (_obj_). In order to set the
 *  context, the variable +self+ is set to _obj_ while
 *  the code is executing, giving the code access to _obj_'s
 *  instance variables. In the version of <code>instance_eval</code>
 *  that takes a +String+, the optional second and third
 *  parameters supply a filename and starting line number that are used
 *  when reporting compilation errors.
 *
 *     class Klass
 *       def initialize
 *         @secret = 99
 *       end
 *     end
 *     k = Klass.new
 *     k.instance_eval { @secret }   #=> 99
 */

VALUE
rb_obj_instance_eval(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE klass;

    if (SPECIAL_CONST_P(self)) {
	klass = Qnil;
    }
    else {
	klass = rb_singleton_class(self);
    }
    return specific_eval(argc, argv, klass, self);
}

/*
 *  call-seq:
 *     obj.instance_exec(arg...) {|var...| block }                       => obj
 *
 *  Executes the given block within the context of the receiver
 *  (_obj_). In order to set the context, the variable +self+ is set
 *  to _obj_ while the code is executing, giving the code access to
 *  _obj_'s instance variables.  Arguments are passed as block parameters.
 *
 *     class KlassWithSecret
 *       def initialize
 *         @secret = 99
 *       end
 *     end
 *     k = KlassWithSecret.new
 *     k.instance_exec(5) {|x| @secret+x }   #=> 104
 */

VALUE
rb_obj_instance_exec(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE klass;

    if (SPECIAL_CONST_P(self)) {
	klass = Qnil;
    }
    else {
	klass = rb_singleton_class(self);
    }
    return yield_under(klass, self, rb_ary_new4(argc, argv));
}

/*
 *  call-seq:
 *     mod.class_eval(string [, filename [, lineno]])  => obj
 *     mod.module_eval {|| block }                     => obj
 *
 *  Evaluates the string or block in the context of _mod_. This can
 *  be used to add methods to a class. <code>module_eval</code> returns
 *  the result of evaluating its argument. The optional _filename_
 *  and _lineno_ parameters set the text for error messages.
 *
 *     class Thing
 *     end
 *     a = %q{def hello() "Hello there!" end}
 *     Thing.module_eval(a)
 *     puts Thing.new.hello()
 *     Thing.module_eval("invalid code", "dummy", 123)
 *
 *  <em>produces:</em>
 *
 *     Hello there!
 *     dummy:123:in `module_eval': undefined local variable
 *         or method `code' for Thing:Class
 */

VALUE
rb_mod_module_eval(argc, argv, mod)
    int argc;
    VALUE *argv;
    VALUE mod;
{
    return specific_eval(argc, argv, mod, mod);
}

/*
 *  call-seq:
 *     mod.module_exec(arg...) {|var...| block }       => obj
 *     mod.class_exec(arg...) {|var...| block }        => obj
 *
 *  Evaluates the given block in the context of the class/module.
 *  The method defined in the block will belong to the receiver.
 *
 *     class Thing
 *     end
 *     Thing.class_exec{
 *       def hello() "Hello there!" end
 *     }
 *     puts Thing.new.hello()
 *
 *  <em>produces:</em>
 *
 *     Hello there!
 */

VALUE
rb_mod_module_exec(argc, argv, mod)
    int argc;
    VALUE *argv;
    VALUE mod;
{
    return yield_under(mod, mod, rb_ary_new4(argc, argv));
}

VALUE rb_load_path;

NORETURN(static void load_failed _((VALUE)));

void
rb_load(fname, wrap)
    VALUE fname;
    int wrap;
{
    VALUE tmp;
    int state;
    volatile int prohibit_int = rb_prohibit_interrupt;
    volatile ID last_func;
    volatile VALUE wrapper = ruby_wrapper;
    volatile VALUE self = ruby_top_self;
    NODE *volatile last_node;
    NODE *saved_cref = ruby_cref;

    if (wrap && ruby_safe_level >= 4) {
	StringValue(fname);
    }
    else {
	SafeStringValue(fname);
    }
    fname = rb_str_new4(fname);
    tmp = rb_find_file(fname);
    if (!tmp) {
	load_failed(fname);
    }
    fname = tmp;

    ruby_errinfo = Qnil;	/* ensure */
    PUSH_VARS();
    PUSH_CLASS(ruby_wrapper);
    ruby_cref = ruby_top_cref;
    if (!wrap) {
	rb_secure(4);		/* should alter global state */
	ruby_class = rb_cObject;
	ruby_wrapper = 0;
    }
    else {
	/* load in anonymous module as toplevel */
	ruby_class = ruby_wrapper = rb_module_new();
	self = rb_obj_clone(ruby_top_self);
	rb_extend_object(self, ruby_wrapper);
	PUSH_CREF(ruby_wrapper);
    }
    PUSH_ITER(ITER_NOT);
    PUSH_FRAME();
    ruby_frame->last_func = 0;
    ruby_frame->orig_func = 0;
    ruby_frame->last_class = 0;
    ruby_frame->self = self;
    PUSH_SCOPE();
    /* default visibility is private at loading toplevel */
    SCOPE_SET(SCOPE_PRIVATE);
    PUSH_TAG(PROT_NONE);
    state = EXEC_TAG();
    last_func = ruby_frame->last_func;
    last_node = ruby_current_node;
    if (!ruby_current_node && ruby_sourcefile) {
	last_node = NEW_NEWLINE(0);
    }
    ruby_current_node = 0;
    if (state == 0) {
	NODE *node;
	volatile int critical;

	DEFER_INTS;
	ruby_in_eval++;
	critical = rb_thread_critical;
	rb_thread_critical = Qtrue;
	rb_load_file(RSTRING(fname)->ptr);
	ruby_in_eval--;
	node = ruby_eval_tree;
	rb_thread_critical = critical;
	ALLOW_INTS;
	if (ruby_nerrs == 0) {
	    eval_node(self, node);
	}
    }
    ruby_frame->last_func = last_func;
    ruby_current_node = last_node;
    ruby_sourcefile = 0;
    ruby_set_current_source();
    if (ruby_scope->flags == SCOPE_ALLOCA && ruby_class == rb_cObject) {
	if (ruby_scope->local_tbl) /* toplevel was empty */
	    free(ruby_scope->local_tbl);
    }
    POP_TAG();
    rb_prohibit_interrupt = prohibit_int;
    ruby_cref = saved_cref;
    POP_SCOPE();
    POP_FRAME();
    POP_ITER();
    POP_CLASS();
    POP_VARS();
    ruby_wrapper = wrapper;
    if (ruby_nerrs > 0) {
	ruby_nerrs = 0;
	rb_exc_raise(ruby_errinfo);
    }
    if (state) jump_tag_but_local_jump(state, Qundef);
    if (!NIL_P(ruby_errinfo))	/* exception during load */
	rb_exc_raise(ruby_errinfo);
}

void
rb_load_protect(fname, wrap, state)
    VALUE fname;
    int wrap;
    int *state;
{
    int status;

    PUSH_ANCHOR();
    if ((status = EXEC_TAG()) == 0) {
	rb_load(fname, wrap);
    }
    else if (status == TAG_THREAD) {
	rb_thread_start_1();
    }
    POP_ANCHOR();
    if (state) *state = status;
}

/*
 *  call-seq:
 *     load(filename, wrap=false)   => true
 *
 *  Loads and executes the Ruby
 *  program in the file _filename_. If the filename does not
 *  resolve to an absolute path, the file is searched for in the library
 *  directories listed in <code>$:</code>. If the optional _wrap_
 *  parameter is +true+, the loaded script will be executed
 *  under an anonymous module, protecting the calling program's global
 *  namespace. In no circumstance will any local variables in the loaded
 *  file be propagated to the loading environment.
 */


static VALUE
rb_f_load(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname, wrap;

    rb_scan_args(argc, argv, "11", &fname, &wrap);
    rb_load(fname, RTEST(wrap));
    return Qtrue;
}

VALUE ruby_dln_librefs;
static VALUE rb_features;
static st_table *loading_tbl;

#define IS_SOEXT(e) (strcmp(e, ".so") == 0 || strcmp(e, ".o") == 0)
#ifdef DLEXT2
#define IS_DLEXT(e) (strcmp(e, DLEXT) == 0 || strcmp(e, DLEXT2) == 0)
#else
#define IS_DLEXT(e) (strcmp(e, DLEXT) == 0)
#endif


static const char *const loadable_ext[] = {
    ".rb", DLEXT,
#ifdef DLEXT2
    DLEXT2,
#endif
    0
};

static int rb_feature_p _((const char **, const char *, int));
static int search_required _((VALUE, VALUE *, VALUE *));

static int
rb_feature_p(ftptr, ext, rb)
    const char **ftptr, *ext;
    int rb;
{
    VALUE v;
    const char *f, *e, *feature = *ftptr;
    long i, len, elen;

    if (ext) {
	len = ext - feature;
	elen = strlen(ext);
    }
    else {
	len = strlen(feature);
	elen = 0;
    }
    for (i = 0; i < RARRAY_LEN(rb_features); ++i) {
	v = RARRAY_PTR(rb_features)[i];
	f = StringValuePtr(v);
	if (RSTRING_LEN(v) < len || strncmp(f, feature, len) != 0)
	    continue;
	if (!*(e = f + len)) {
	    if (ext) continue;
	    *ftptr = 0;
	    return 'u';
	}
	if (*e != '.') continue;
	if ((!rb || !ext) && (IS_SOEXT(e) || IS_DLEXT(e))) {
	    *ftptr = 0;
	    return 's';
	}
	if ((rb || !ext) && (strcmp(e, ".rb") == 0)) {
	    *ftptr = 0;
	    return 'r';
	}
    }
    if (loading_tbl) {
	if (st_lookup(loading_tbl, (st_data_t)feature, (st_data_t *)ftptr)) {
	    if (!ext) return 'u';
	    return strcmp(ext, ".rb") ? 's' : 'r';
	}
	else {
	    char *buf;

	    if (ext && *ext) return 0;
	    buf = ALLOCA_N(char, len + DLEXT_MAXLEN + 1);
	    MEMCPY(buf, feature, char, len);
	    for (i = 0; (e = loadable_ext[i]) != 0; i++) {
		strncpy(buf + len, e, DLEXT_MAXLEN + 1);
		if (st_lookup(loading_tbl, (st_data_t)buf, (st_data_t *)ftptr)) {
		    return i ? 's' : 'r';
		}
	    }
	}
    }
    return 0;
}
#define rb_feature_p(feature, ext, rb) rb_feature_p(&feature, ext, rb)

int
rb_provided(feature)
    const char *feature;
{
    const char *ext = strrchr(feature, '.');

    if (ext && !strchr(ext, '/')) {
	if (strcmp(".rb", ext) == 0) {
	    if (rb_feature_p(feature, ext, Qtrue)) return Qtrue;
	    return Qfalse;
	}
	else if (IS_SOEXT(ext) || IS_DLEXT(ext)) {
	    if (rb_feature_p(feature, ext, Qfalse)) return Qtrue;
	    return Qfalse;
	}
    }
    if (rb_feature_p(feature, feature + strlen(feature), Qtrue))
	return Qtrue;

    return Qfalse;
}

static void
rb_provide_feature(feature)
    VALUE feature;
{
    rb_ary_push(rb_features, feature);
}

void
rb_provide(feature)
    const char *feature;
{
    rb_provide_feature(rb_str_new2(feature));
}

static char *
load_lock(ftptr)
    const char *ftptr;
{
    st_data_t th;

    if (!loading_tbl ||
	!st_lookup(loading_tbl, (st_data_t)ftptr, &th))
    {
	/* loading ruby library should be serialized. */
	if (!loading_tbl) {
	    loading_tbl = st_init_strtable();
	}
	/* partial state */
	ftptr = ruby_strdup(ftptr);
	st_insert(loading_tbl, (st_data_t)ftptr, (st_data_t)curr_thread);
	return (char *)ftptr;
    }
    do {
	rb_thread_t owner = (rb_thread_t)th;
	if (owner == curr_thread) return 0;
	rb_thread_join(owner->thread, -1.0);
    } while (st_lookup(loading_tbl, (st_data_t)ftptr, &th));
    return 0;
}

static void
load_unlock(const char *ftptr)
{
    if (ftptr) {
	st_data_t key = (st_data_t)ftptr;

	if (st_delete(loading_tbl, &key, 0)) {
	    free((char *)key);
	}
    }
}

/*
 *  call-seq:
 *     require(string)    => true or false
 *
 *  Ruby tries to load the library named _string_, returning
 *  +true+ if successful. If the filename does not resolve to
 *  an absolute path, it will be searched for in the directories listed
 *  in <code>$:</code>. If the file has the extension ``.rb'', it is
 *  loaded as a source file; if the extension is ``.so'', ``.o'', or
 *  ``.dll'', or whatever the default shared library extension is on
 *  the current platform, Ruby loads the shared library as a Ruby
 *  extension. Otherwise, Ruby tries adding ``.rb'', ``.so'', and so on
 *  to the name. The name of the loaded feature is added to the array in
 *  <code>$"</code>. A feature will not be loaded if it's name already
 *  appears in <code>$"</code>. However, the file name is not converted
 *  to an absolute path, so that ``<code>require 'a';require
 *  './a'</code>'' will load <code>a.rb</code> twice.
 *
 *     require "my-library.rb"
 *     require "db-driver"
 */

VALUE
rb_f_require(obj, fname)
    VALUE obj, fname;
{
    return rb_require_safe(fname, ruby_safe_level);
}

static int
search_required(fname, featurep, path)
    VALUE fname, *featurep, *path;
{
    VALUE tmp;
    const char *ext, *ftptr;
    int type;

    if (*(ftptr = RSTRING_PTR(fname)) == '~') {
	fname = rb_file_expand_path(fname, Qnil);
	ftptr = RSTRING_PTR(fname);
    }
    *featurep = fname;
    *path = 0;
    ext = strrchr(ftptr, '.');
    if (ext && !strchr(ext, '/')) {
	if (strcmp(".rb", ext) == 0) {
	    if (rb_feature_p(ftptr, ext, Qtrue)) {
		if (ftptr) *path = rb_str_new2(ftptr);
		return 'r';
	    }
	    if ((*path = rb_find_file(fname)) != 0) return 'r';
	    return 0;
	}
	else if (IS_SOEXT(ext)) {
	    if (rb_feature_p(ftptr, ext, Qfalse)) {
		if (ftptr) *path = rb_str_new2(ftptr);
		return 's';
	    }
	    tmp = rb_str_new(RSTRING_PTR(fname), ext-RSTRING_PTR(fname));
	    *featurep = tmp;
#ifdef DLEXT2
	    OBJ_FREEZE(tmp);
	    if (rb_find_file_ext(&tmp, loadable_ext+1)) {
		*featurep = tmp;
		*path = rb_find_file(tmp);
		return 's';
	    }
#else
	    rb_str_cat2(tmp, DLEXT);
	    OBJ_FREEZE(tmp);
	    if ((*path = rb_find_file(tmp)) != 0) {
		return 's';
	    }
#endif
	}
	else if (IS_DLEXT(ext)) {
	    if (rb_feature_p(ftptr, ext, Qfalse)) {
		if (ftptr) *path = rb_str_new2(ftptr);
		return 's';
	    }
	    if ((*path = rb_find_file(fname)) != 0) return 's';
	}
    }
    tmp = fname;
    type = rb_find_file_ext(&tmp, loadable_ext);
    *featurep = tmp;
    switch (type) {
      case 0:
	type = rb_feature_p(ftptr, 0, Qfalse);
	if (type && ftptr) *path = rb_str_new2(ftptr);
	return type;

      default:
	ext = strrchr(ftptr = RSTRING(tmp)->ptr, '.');
	if (!rb_feature_p(ftptr, ext, !--type))
	    *path = rb_find_file(tmp);
	else if (ftptr)
	    *path = rb_str_new2(ftptr);
    }
    return type ? 's' : 'r';
}

static void
load_failed(fname)
    VALUE fname;
{
    rb_raise(rb_eLoadError, "no such file to load -- %s", RSTRING(fname)->ptr);
}

VALUE
rb_require_safe(fname, safe)
    VALUE fname;
    int safe;
{
    VALUE result = Qnil;
    volatile VALUE errinfo = ruby_errinfo;
    int state;
    struct {
	NODE *node;
	ID func;
	int vmode, safe;
    } volatile saved;
    char *volatile ftptr = 0;

    if (OBJ_TAINTED(fname)) {
	rb_check_safe_obj(fname);
    }
    StringValue(fname);
    fname = rb_str_new4(fname);
    saved.vmode = scope_vmode;
    saved.node = ruby_current_node;
    saved.func = ruby_frame->last_func;
    saved.safe = ruby_safe_level;
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	VALUE feature, path;
	long handle;
	int found;

	ruby_safe_level = safe;
	found = search_required(fname, &feature, &path);
	if (found) {
	    if (!path || !(ftptr = load_lock(RSTRING_PTR(feature)))) {
		result = Qfalse;
	    }
	    else {
		ruby_safe_level = 0;
		switch (found) {
		  case 'r':
		    rb_load(path, 0);
		    break;

		  case 's':
		    ruby_current_node = 0;
		    ruby_sourcefile = rb_source_filename(RSTRING(path)->ptr);
		    ruby_sourceline = 0;
		    ruby_frame->last_func = 0;
		    SCOPE_SET(SCOPE_PUBLIC);
		    handle = (long)dln_load(RSTRING(path)->ptr);
		    rb_ary_push(ruby_dln_librefs, LONG2NUM(handle));
		    break;
		}
		rb_provide_feature(feature);
		result = Qtrue;
	    }
	}
    }
    POP_TAG();
    ruby_current_node = saved.node;
    ruby_set_current_source();
    ruby_frame->last_func = saved.func;
    SCOPE_SET(saved.vmode);
    ruby_safe_level = saved.safe;
    load_unlock(ftptr);
    if (state) JUMP_TAG(state);
    if (NIL_P(result)) {
	load_failed(fname);
    }
    ruby_errinfo = errinfo;

    return result;
}

VALUE
rb_require(fname)
    const char *fname;
{
    VALUE fn = rb_str_new2(fname);
    OBJ_FREEZE(fn);
    return rb_require_safe(fn, ruby_safe_level);
}

void
ruby_init_ext(name, init)
    const char *name;
    void (*init) _((void));
{
    ruby_current_node = 0;
    ruby_sourcefile = rb_source_filename(name);
    ruby_sourceline = 0;
    ruby_frame->last_func = 0;
    ruby_frame->orig_func = 0;
    SCOPE_SET(SCOPE_PUBLIC);
    if (load_lock(name)) {
	(*init)();
	rb_provide(name);
	load_unlock(name);
    }
}

static void
secure_visibility(self)
    VALUE self;
{
    if (ruby_safe_level >= 4 && !OBJ_TAINTED(self)) {
	rb_raise(rb_eSecurityError, "Insecure: can't change method visibility");
    }
}

static void
set_method_visibility(self, argc, argv, ex)
    VALUE self;
    int argc;
    VALUE *argv;
    ID ex;
{
    int i;

    secure_visibility(self);
    for (i=0; i<argc; i++) {
	rb_export_method(self, rb_to_id(argv[i]), ex);
    }
    rb_clear_cache_by_class(self);
}

/*
 *  call-seq:
 *     public                 => self
 *     public(symbol, ...)    => self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 */

static VALUE
rb_mod_public(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(SCOPE_PUBLIC);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PUBLIC);
    }
    return module;
}

/*
 *  call-seq:
 *     protected                => self
 *     protected(symbol, ...)   => self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to protected. With arguments, sets the named methods
 *  to have protected visibility.
 */

static VALUE
rb_mod_protected(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(SCOPE_PROTECTED);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PROTECTED);
    }
    return module;
}

/*
 *  call-seq:
 *     private                 => self
 *     private(symbol, ...)    => self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to private. With arguments, sets the named methods
 *  to have private visibility.
 *
 *     module Mod
 *       def a()  end
 *       def b()  end
 *       private
 *       def c()  end
 *       private :a
 *     end
 *     Mod.private_instance_methods   #=> ["a", "c"]
 */

static VALUE
rb_mod_private(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(SCOPE_PRIVATE);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    }
    return module;
}

/*
 *  call-seq:
 *     mod.public_class_method(symbol, ...)    => mod
 *
 *  Makes a list of existing class methods public.
 */

static VALUE
rb_mod_public_method(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PUBLIC);
    return obj;
}

/*
 *  call-seq:
 *     mod.private_class_method(symbol, ...)   => mod
 *
 *  Makes existing class methods private. Often used to hide the default
 *  constructor <code>new</code>.
 *
 *     class SimpleSingleton  # Not thread safe
 *       private_class_method :new
 *       def SimpleSingleton.create(*args, &block)
 *         @me = new(*args, &block) if ! @me
 *         @me
 *       end
 *     end
 */

static VALUE
rb_mod_private_method(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PRIVATE);
    return obj;
}

/*
 *  call-seq:
 *     public
 *     public(symbol, ...)
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 */

static VALUE
top_public(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_mod_public(argc, argv, rb_cObject);
}

static VALUE
top_private(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_mod_private(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     module_function(symbol, ...)    => self
 *
 *  Creates module functions for the named methods. These functions may
 *  be called with the module as a receiver, and also become available
 *  as instance methods to classes that mix in the module. Module
 *  functions are copies of the original, and so may be changed
 *  independently. The instance-method versions are made private. If
 *  used with no arguments, subsequently defined methods become module
 *  functions.
 *
 *     module Mod
 *       def one
 *         "This is one"
 *       end
 *       module_function :one
 *     end
 *     class Cls
 *       include Mod
 *       def callOne
 *         one
 *       end
 *     end
 *     Mod.one     #=> "This is one"
 *     c = Cls.new
 *     c.callOne   #=> "This is one"
 *     module Mod
 *       def one
 *         "This is the new one"
 *       end
 *     end
 *     Mod.one     #=> "This is one"
 *     c.callOne   #=> "This is the new one"
 */

static VALUE
rb_mod_modfunc(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    int i;
    ID id;
    NODE *body;

    if (TYPE(module) != T_MODULE) {
	rb_raise(rb_eTypeError, "module_function must be called for modules");
    }

    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(SCOPE_MODFUNC);
	return module;
    }

    set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    for (i=0; i<argc; i++) {
	VALUE m = module;

	id = rb_to_id(argv[i]);
	for (;;) {
	    body = search_method(m, id, &m);
	    if (body == 0) {
		body = search_method(rb_cObject, id, &m);
	    }
	    if (body == 0 || body->nd_body == 0) {
		print_undef(module, id);
	    }
	    if (nd_type(body->nd_body) != NODE_ZSUPER) {
		break;		/* normal case: need not to follow 'super' link */
	    }
	    m = RCLASS(m)->super;
	    if (!m) break;
	}
	rb_add_method(rb_singleton_class(module), id, body->nd_body, NOEX_PUBLIC);
    }
    return module;
}

/*
 *  call-seq:
 *     append_features(mod)   => mod
 *
 *  When this module is included in another, Ruby calls
 *  <code>append_features</code> in this module, passing it the
 *  receiving module in _mod_. Ruby's default implementation is
 *  to add the constants, methods, and module variables of this module
 *  to _mod_ if this module has not already been added to
 *  _mod_ or one of its ancestors. See also <code>Module#include</code>.
 */

static VALUE
rb_mod_append_features(module, include)
    VALUE module, include;
{
    switch (TYPE(include)) {
      case T_CLASS:
      case T_MODULE:
	break;
      default:
	Check_Type(include, T_CLASS);
	break;
    }
    rb_include_module(include, module);

    return module;
}

/*
 *  call-seq:
 *     include(module, ...)    => self
 *
 *  Invokes <code>Module.append_features</code> on each parameter in turn.
 */

static VALUE
rb_mod_include(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    int i;

    for (i=0; i<argc; i++) Check_Type(argv[i], T_MODULE);
    while (argc--) {
	rb_funcall(argv[argc], rb_intern("append_features"), 1, module);
	rb_funcall(argv[argc], rb_intern("included"), 1, module);
    }
    return module;
}

void
rb_obj_call_init(obj, argc, argv)
    VALUE obj;
    int argc;
    VALUE *argv;
{
    PUSH_ITER(rb_block_given_p()?ITER_PRE:ITER_NOT);
    rb_funcall2(obj, init, argc, argv);
    POP_ITER();
}

void
rb_extend_object(obj, module)
    VALUE obj, module;
{
    rb_include_module(rb_singleton_class(obj), module);
}

/*
 *  call-seq:
 *     extend_object(obj)    => obj
 *
 *  Extends the specified object by adding this module's constants and
 *  methods (which are added as singleton methods). This is the callback
 *  method used by <code>Object#extend</code>.
 *
 *     module Picky
 *       def Picky.extend_object(o)
 *         if String === o
 *           puts "Can't add Picky to a String"
 *         else
 *           puts "Picky added to #{o.class}"
 *           super
 *         end
 *       end
 *     end
 *     (s = Array.new).extend Picky  # Call Object.extend
 *     (s = "quick brown fox").extend Picky
 *
 *  <em>produces:</em>
 *
 *     Picky added to Array
 *     Can't add Picky to a String
 */

static VALUE
rb_mod_extend_object(mod, obj)
    VALUE mod, obj;
{
    rb_extend_object(obj, mod);
    return obj;
}

/*
 *  call-seq:
 *     obj.extend(module, ...)    => obj
 *
 *  Adds to _obj_ the instance methods from each module given as a
 *  parameter.
 *
 *     module Mod
 *       def hello
 *         "Hello from Mod.\n"
 *       end
 *     end
 *
 *     class Klass
 *       def hello
 *         "Hello from Klass.\n"
 *       end
 *     end
 *
 *     k = Klass.new
 *     k.hello         #=> "Hello from Klass.\n"
 *     k.extend(Mod)   #=> #<Klass:0x401b3bc8>
 *     k.hello         #=> "Hello from Mod.\n"
 */

static VALUE
rb_obj_extend(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    int i;

    if (argc == 0) {
	rb_raise(rb_eArgError, "wrong number of arguments (0 for 1)");
    }
    for (i=0; i<argc; i++) Check_Type(argv[i], T_MODULE);
    while (argc--) {
	rb_funcall(argv[argc], rb_intern("extend_object"), 1, obj);
	rb_funcall(argv[argc], rb_intern("extended"), 1, obj);
    }
    return obj;
}

/*
 *  call-seq:
 *     include(module, ...)   => self
 *
 *  Invokes <code>Module.append_features</code>
 *  on each parameter in turn. Effectively adds the methods and constants
 *  in each module to the receiver.
 */

static VALUE
top_include(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    rb_secure(4);
    if (ruby_wrapper) {
	rb_warning("main#include in the wrapped load is effective only in wrapper module");
	return rb_mod_include(argc, argv, ruby_wrapper);
    }
    return rb_mod_include(argc, argv, rb_cObject);
}

VALUE rb_f_trace_var();
VALUE rb_f_untrace_var();

static void
errinfo_setter(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    if (!NIL_P(val) && !rb_obj_is_kind_of(val, rb_eException)) {
	rb_raise(rb_eTypeError, "assigning non-exception to $!");
    }
    *var = val;
}

static VALUE
errat_getter(id)
    ID id;
{
    return get_backtrace(ruby_errinfo);
}

static void
errat_setter(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    if (NIL_P(ruby_errinfo)) {
	rb_raise(rb_eArgError, "$! not set");
    }
    set_backtrace(ruby_errinfo, val);
}

/*
 *  call-seq:
 *     local_variables    => array
 *
 *  Returns the names of the current local variables.
 *
 *     fred = 1
 *     for i in 1..10
 *        # ...
 *     end
 *     local_variables   #=> ["fred", "i"]
 */

static VALUE
rb_f_local_variables()
{
    ID *tbl;
    int n, i;
    VALUE ary = rb_ary_new();
    struct RVarmap *vars;

    tbl = ruby_scope->local_tbl;
    if (tbl) {
	n = *tbl++;
	for (i=2; i<n; i++) {	/* skip first 2 ($_ and $~) */
	    if (!rb_is_local_id(tbl[i])) continue; /* skip flip states */
	    rb_ary_push(ary, rb_str_new2(rb_id2name(tbl[i])));
	}
    }

    vars = ruby_dyna_vars;
    while (vars) {
	if (vars->id && rb_is_local_id(vars->id)) { /* skip $_, $~ and flip states */
	    rb_ary_push(ary, rb_str_new2(rb_id2name(vars->id)));
	}
	vars = vars->next;
    }

    return ary;
}

static VALUE rb_f_catch _((VALUE,VALUE));
NORETURN(static VALUE rb_f_throw _((int,VALUE*)));

struct end_proc_data {
    void (*func)();
    VALUE data;
    int safe;
    struct end_proc_data *next;
};

static struct end_proc_data *end_procs, *ephemeral_end_procs, *tmp_end_procs;

void
rb_set_end_proc(func, data)
    void (*func) _((VALUE));
    VALUE data;
{
    struct end_proc_data *link = ALLOC(struct end_proc_data);
    struct end_proc_data **list;

    if (ruby_wrapper) list = &ephemeral_end_procs;
    else              list = &end_procs;
    link->next = *list;
    link->func = func;
    link->data = data;
    link->safe = ruby_safe_level;
    *list = link;
}

void
rb_mark_end_proc()
{
    struct end_proc_data *link;

    link = end_procs;
    while (link) {
	rb_gc_mark(link->data);
	link = link->next;
    }
    link = ephemeral_end_procs;
    while (link) {
	rb_gc_mark(link->data);
	link = link->next;
    }
    link = tmp_end_procs;
    while (link) {
	rb_gc_mark(link->data);
	link = link->next;
    }
}

static void call_end_proc _((VALUE data));

static void
call_end_proc(data)
    VALUE data;
{
    PUSH_ITER(ITER_NOT);
    PUSH_FRAME();
    ruby_frame->self = ruby_frame->prev->self;
    ruby_frame->node = 0;
    ruby_frame->last_func = 0;
    ruby_frame->last_class = 0;
    proc_invoke(data, rb_ary_new2(0), Qundef, 0);
    POP_FRAME();
    POP_ITER();
}

static void
rb_f_END()
{
    PUSH_FRAME();
    ruby_frame->argc = 0;
    ruby_frame->iter = ITER_CUR;
    rb_set_end_proc(call_end_proc, rb_block_proc());
    POP_FRAME();
}

/*
 *  call-seq:
 *     at_exit { block } -> proc
 *
 *  Converts _block_ to a +Proc+ object (and therefore
 *  binds it at the point of call) and registers it for execution when
 *  the program exits. If multiple handlers are registered, they are
 *  executed in reverse order of registration.
 *
 *     def do_at_exit(str1)
 *       at_exit { print str1 }
 *     end
 *     at_exit { puts "cruel world" }
 *     do_at_exit("goodbye ")
 *     exit
 *
 *  <em>produces:</em>
 *
 *     goodbye cruel world
 */

static VALUE
rb_f_at_exit()
{
    VALUE proc;

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "called without a block");
    }
    proc = rb_block_proc();
    rb_set_end_proc(call_end_proc, proc);
    return proc;
}

void
rb_exec_end_proc()
{
    struct end_proc_data *link, *tmp;
    int status;
    volatile int safe = ruby_safe_level;

    while (ephemeral_end_procs) {
	tmp_end_procs = link = ephemeral_end_procs;
	ephemeral_end_procs = 0;
	while (link) {
	    PUSH_TAG(PROT_NONE);
	    if ((status = EXEC_TAG()) == 0) {
		ruby_safe_level = link->safe;
		(*link->func)(link->data);
	    }
	    POP_TAG();
	    if (status) {
		error_handle(status);
	    }
	    tmp = link;
	    tmp_end_procs = link = link->next;
	    free(tmp);
	}
    }
    while (end_procs) {
	tmp_end_procs = link = end_procs;
	end_procs = 0;
	while (link) {
	    PUSH_TAG(PROT_NONE);
	    if ((status = EXEC_TAG()) == 0) {
		ruby_safe_level = link->safe;
		(*link->func)(link->data);
	    }
	    POP_TAG();
	    if (status) {
		error_handle(status);
	    }
	    tmp = link;
	    tmp_end_procs = link = link->next;
	    free(tmp);
	}
    }
    ruby_safe_level = safe;
}

/*
 *  call-seq:
 *     __method__         => symbol
 *
 *  Returns the name of the current method as a Symbol.
 *  If called from inside of an aliased method it will return the original
 *  nonaliased name.
 *  If called outside of a method, it returns <code>nil</code>.
 *
 *    def foo
 *      __method__
 *    end
 *    alias bar foo
 *
 *    foo                # => :foo
 *    bar                # => :foo
 *
 */

static VALUE
rb_f_method_name()
{
    struct FRAME* prev = ruby_frame->prev;
    if (prev && prev->orig_func) {
	return ID2SYM(prev->orig_func);
    }
    else {
	return Qnil;
    }
}

void
Init_eval()
{
    init = rb_intern("initialize");
    eqq = rb_intern("===");
    each = rb_intern("each");

    aref = rb_intern("[]");
    aset = rb_intern("[]=");
    match = rb_intern("=~");
    missing = rb_intern("method_missing");
    added = rb_intern("method_added");
    singleton_added = rb_intern("singleton_method_added");
    removed = rb_intern("method_removed");
    singleton_removed = rb_intern("singleton_method_removed");
    undefined = rb_intern("method_undefined");
    singleton_undefined = rb_intern("singleton_method_undefined");

    __id__ = rb_intern("__id__");
    __send__ = rb_intern("__send__");

    rb_global_variable((void *)&top_scope);
    rb_global_variable((void *)&ruby_eval_tree_begin);

    rb_global_variable((void *)&ruby_eval_tree);
    rb_global_variable((void *)&ruby_dyna_vars);

    rb_define_virtual_variable("$@", errat_getter, errat_setter);
    rb_define_hooked_variable("$!", &ruby_errinfo, 0, errinfo_setter);

    rb_define_global_function("eval", rb_f_eval, -1);
    rb_define_global_function("iterator?", rb_f_block_given_p, 0);
    rb_define_global_function("block_given?", rb_f_block_given_p, 0);
    rb_define_global_function("method_missing", rb_method_missing, -1);
    rb_define_global_function("loop", rb_f_loop, 0);

    rb_define_method(rb_mKernel, "respond_to?", obj_respond_to, -1);
    respond_to   = rb_intern("respond_to?");
    rb_global_variable((void *)&basic_respond_to);
    basic_respond_to = rb_method_node(rb_cObject, respond_to);

    rb_define_global_function("raise", rb_f_raise, -1);
    rb_define_global_function("fail", rb_f_raise, -1);

    rb_define_global_function("caller", rb_f_caller, -1);

    rb_define_global_function("exit", rb_f_exit, -1);
    rb_define_global_function("abort", rb_f_abort, -1);

    rb_define_global_function("at_exit", rb_f_at_exit, 0);

    rb_define_global_function("catch", rb_f_catch, 1);
    rb_define_global_function("throw", rb_f_throw, -1);
    rb_define_global_function("global_variables", rb_f_global_variables, 0); /* in variable.c */
    rb_define_global_function("local_variables", rb_f_local_variables, 0);

    rb_define_global_function("__method__", rb_f_method_name, 0);

    rb_define_method(rb_mKernel, "send", rb_f_send, -1);
    rb_define_method(rb_mKernel, "__send__", rb_f_send, -1);
    rb_define_method(rb_mKernel, "instance_eval", rb_obj_instance_eval, -1);
    rb_define_method(rb_mKernel, "instance_exec", rb_obj_instance_exec, -1);

    rb_define_private_method(rb_cModule, "append_features", rb_mod_append_features, 1);
    rb_define_private_method(rb_cModule, "extend_object", rb_mod_extend_object, 1);
    rb_define_private_method(rb_cModule, "include", rb_mod_include, -1);
    rb_define_private_method(rb_cModule, "public", rb_mod_public, -1);
    rb_define_private_method(rb_cModule, "protected", rb_mod_protected, -1);
    rb_define_private_method(rb_cModule, "private", rb_mod_private, -1);
    rb_define_private_method(rb_cModule, "module_function", rb_mod_modfunc, -1);
    rb_define_method(rb_cModule, "method_defined?", rb_mod_method_defined, 1);
    rb_define_method(rb_cModule, "public_method_defined?", rb_mod_public_method_defined, 1);
    rb_define_method(rb_cModule, "private_method_defined?", rb_mod_private_method_defined, 1);
    rb_define_method(rb_cModule, "protected_method_defined?", rb_mod_protected_method_defined, 1);
    rb_define_method(rb_cModule, "public_class_method", rb_mod_public_method, -1);
    rb_define_method(rb_cModule, "private_class_method", rb_mod_private_method, -1);
    rb_define_method(rb_cModule, "module_eval", rb_mod_module_eval, -1);
    rb_define_method(rb_cModule, "module_exec", rb_mod_module_exec, -1);
    rb_define_method(rb_cModule, "class_eval", rb_mod_module_eval, -1);
    rb_define_method(rb_cModule, "class_exec", rb_mod_module_exec, -1);

    rb_undef_method(rb_cClass, "module_function");

    rb_define_private_method(rb_cModule, "remove_method", rb_mod_remove_method, -1);
    rb_define_private_method(rb_cModule, "undef_method", rb_mod_undef_method, -1);
    rb_define_private_method(rb_cModule, "alias_method", rb_mod_alias_method, 2);
    rb_define_private_method(rb_cModule, "define_method", rb_mod_define_method, -1);

    rb_define_singleton_method(rb_cModule, "nesting", rb_mod_nesting, 0);
    rb_define_singleton_method(rb_cModule, "constants", rb_mod_s_constants, 0);

    rb_define_singleton_method(ruby_top_self, "include", top_include, -1);
    rb_define_singleton_method(ruby_top_self, "public", top_public, -1);
    rb_define_singleton_method(ruby_top_self, "private", top_private, -1);

    rb_define_method(rb_mKernel, "extend", rb_obj_extend, -1);

    rb_define_global_function("trace_var", rb_f_trace_var, -1); /* in variable.c */
    rb_define_global_function("untrace_var", rb_f_untrace_var, -1); /* in variable.c */

    rb_define_global_function("set_trace_func", set_trace_func, 1);
    rb_global_variable(&trace_func);

    rb_define_virtual_variable("$SAFE", safe_getter, safe_setter);
}

/*
 *  call-seq:
 *     mod.autoload(name, filename)   => nil
 *
 *  Registers _filename_ to be loaded (using <code>Kernel::require</code>)
 *  the first time that _name_ (which may be a <code>String</code> or
 *  a symbol) is accessed in the namespace of _mod_.
 *
 *     module A
 *     end
 *     A.autoload(:B, "b")
 *     A::B.doit            # autoloads "b"
 */

static VALUE
rb_mod_autoload(mod, sym, file)
    VALUE mod;
    VALUE sym;
    VALUE file;
{
    ID id = rb_to_id(sym);

    SafeStringValue(file);
    rb_autoload(mod, id, RSTRING(file)->ptr);
    return Qnil;
}

/*
 *  call-seq:
 *     mod.autoload?(name)   => String or nil
 *
 *  Returns _filename_ to be loaded if _name_ is registered as
 *  +autoload+ in the namespace of _mod_.
 *
 *     module A
 *     end
 *     A.autoload(:B, "b")
 *     A.autoload?(:B)            # => "b"
 */

static VALUE
rb_mod_autoload_p(mod, sym)
    VALUE mod, sym;
{
    return rb_autoload_p(mod, rb_to_id(sym));
}

/*
 *  call-seq:
 *     autoload(module, filename)   => nil
 *
 *  Registers _filename_ to be loaded (using <code>Kernel::require</code>)
 *  the first time that _module_ (which may be a <code>String</code> or
 *  a symbol) is accessed.
 *
 *     autoload(:MyModule, "/usr/local/lib/modules/my_module.rb")
 */

static VALUE
rb_f_autoload(obj, sym, file)
    VALUE obj;
    VALUE sym;
    VALUE file;
{
    if (NIL_P(ruby_cbase)) {
	rb_raise(rb_eTypeError, "no class/module for autoload target");
    }
    return rb_mod_autoload(ruby_cbase, sym, file);
}

/*
 *  call-seq:
 *     autoload?(name)   => String or nil
 *
 *  Returns _filename_ to be loaded if _name_ is registered as
 *  +autoload+.
 *
 *     autoload(:B, "b")
 *     autoload?(:B)            # => "b"
 */

static VALUE
rb_f_autoload_p(obj, sym)
    VALUE obj;
    VALUE sym;
{
    /* use ruby_cbase as same as rb_f_autoload. */
    if (NIL_P(ruby_cbase)) {
	return Qfalse;
    }
    return rb_mod_autoload_p(ruby_cbase, sym);
}

void
Init_load()
{
    rb_define_readonly_variable("$:", &rb_load_path);
    rb_define_readonly_variable("$-I", &rb_load_path);
    rb_define_readonly_variable("$LOAD_PATH", &rb_load_path);
    rb_load_path = rb_ary_new();

    rb_define_readonly_variable("$\"", &rb_features);
    rb_define_readonly_variable("$LOADED_FEATURES", &rb_features);
    rb_features = rb_ary_new();

    rb_define_global_function("load", rb_f_load, -1);
    rb_define_global_function("require", rb_f_require, 1);
    rb_define_method(rb_cModule, "autoload",  rb_mod_autoload,   2);
    rb_define_method(rb_cModule, "autoload?", rb_mod_autoload_p, 1);
    rb_define_global_function("autoload",  rb_f_autoload,   2);
    rb_define_global_function("autoload?", rb_f_autoload_p, 1);
    rb_global_variable(&ruby_wrapper);

    rb_global_variable(&ruby_dln_librefs);
    ruby_dln_librefs = rb_ary_new();
}

static void
scope_dup(scope)
    struct SCOPE *scope;
{
    ID *tbl;
    VALUE *vars;

    scope->flags |= SCOPE_DONT_RECYCLE;
    if (scope->flags & SCOPE_MALLOC) return;

    if (scope->local_tbl) {
	tbl = scope->local_tbl;
	vars = ALLOC_N(VALUE, tbl[0]+1);
	*vars++ = scope->local_vars[-1];
	MEMCPY(vars, scope->local_vars, VALUE, tbl[0]);
	scope->local_vars = vars;
	scope->flags |= SCOPE_MALLOC;
    }
}

static void
blk_mark(data)
    struct BLOCK *data;
{
    while (data) {
	rb_gc_mark_frame(&data->frame);
	rb_gc_mark((VALUE)data->scope);
	rb_gc_mark((VALUE)data->var);
	rb_gc_mark((VALUE)data->body);
	rb_gc_mark((VALUE)data->self);
	rb_gc_mark((VALUE)data->dyna_vars);
	rb_gc_mark((VALUE)data->cref);
	rb_gc_mark(data->wrapper);
	rb_gc_mark(data->block_obj);
	data = data->prev;
    }
}

static void
frame_free(frame)
    struct FRAME *frame;
{
    struct FRAME *tmp;

    frame = frame->prev;
    while (frame) {
	tmp = frame;
	frame = frame->prev;
	free(tmp);
    }
}

static void
blk_free(data)
    struct BLOCK *data;
{
    void *tmp;

    while (data) {
	frame_free(&data->frame);
	tmp = data;
	data = data->prev;
	free(tmp);
    }
}

static void
frame_dup(frame)
    struct FRAME *frame;
{
    struct FRAME *tmp;

    for (;;) {
	frame->tmp = 0;		/* should not preserve tmp */
	if (!frame->prev) break;
	tmp = ALLOC(struct FRAME);
	*tmp = *frame->prev;
	frame->prev = tmp;
	frame = tmp;
    }
}


static void
blk_copy_prev(block)
    struct BLOCK *block;
{
    struct BLOCK *tmp;
    struct RVarmap* vars;

    while (block->prev) {
	tmp = ALLOC_N(struct BLOCK, 1);
	MEMCPY(tmp, block->prev, struct BLOCK, 1);
	scope_dup(tmp->scope);
	frame_dup(&tmp->frame);

	for (vars = tmp->dyna_vars; vars; vars = vars->next) {
	    if (FL_TEST(vars, DVAR_DONT_RECYCLE)) break;
	    FL_SET(vars, DVAR_DONT_RECYCLE);
	}

	block->prev = tmp;
	block = tmp;
    }
}


static void
blk_dup(dup, orig)
    struct BLOCK *dup, *orig;
{
    MEMCPY(dup, orig, struct BLOCK, 1);
    frame_dup(&dup->frame);

    if (dup->iter) {
	blk_copy_prev(dup);
    }
    else {
	dup->prev = 0;
    }
}

/*
 * MISSING: documentation
 */

static VALUE
proc_clone(self)
    VALUE self;
{
    struct BLOCK *orig, *data;
    VALUE bind;

    Data_Get_Struct(self, struct BLOCK, orig);
    bind = Data_Make_Struct(rb_obj_class(self),struct BLOCK,blk_mark,blk_free,data);
    CLONESETUP(bind, self);
    blk_dup(data, orig);

    return bind;
}

/*
 * MISSING: documentation
 */

#define PROC_TSHIFT (FL_USHIFT+1)
#define PROC_TMASK  (FL_USER1|FL_USER2|FL_USER3)
#define PROC_TMAX   (PROC_TMASK >> PROC_TSHIFT)

static int proc_get_safe_level(VALUE);

static VALUE
proc_dup(self)
    VALUE self;
{
    struct BLOCK *orig, *data;
    VALUE bind;
    int safe = proc_get_safe_level(self);

    Data_Get_Struct(self, struct BLOCK, orig);
    bind = Data_Make_Struct(rb_obj_class(self),struct BLOCK,blk_mark,blk_free,data);
    blk_dup(data, orig);
    if (safe > PROC_TMAX) safe = PROC_TMAX;
    FL_SET(bind, (safe << PROC_TSHIFT) & PROC_TMASK);

    return bind;
}

VALUE
rb_block_dup(self, klass, cref)
    VALUE self, klass, cref;
{
    struct BLOCK *block;
    VALUE obj = proc_dup(self);
    Data_Get_Struct(obj, struct BLOCK, block);
    block->klass = klass;
    block->cref = NEW_NODE(nd_type(block->cref), cref, block->cref->u2.node,
			   block->cref->u3.node);
    return obj;
}

/*
 *  call-seq:
 *     binding -> a_binding
 *
 *  Returns a +Binding+ object, describing the variable and
 *  method bindings at the point of call. This object can be used when
 *  calling +eval+ to execute the evaluated command in this
 *  environment. Also see the description of class +Binding+.
 *
 *     def getBinding(param)
 *       return binding
 *     end
 *     b = getBinding("hello")
 *     eval("param", b)   #=> "hello"
 */

static VALUE
rb_f_binding(self)
    VALUE self;
{
    struct BLOCK *data, *p;
    struct RVarmap *vars;
    VALUE bind;

    PUSH_BLOCK(0,0);
    bind = Data_Make_Struct(rb_cBinding,struct BLOCK,blk_mark,blk_free,data);
    *data = *ruby_block;

    data->orig_thread = rb_thread_current();
    data->wrapper = ruby_wrapper;
    data->iter = rb_f_block_given_p();
    frame_dup(&data->frame);
    if (ruby_frame->prev) {
	data->frame.last_func = ruby_frame->prev->last_func;
	data->frame.last_class = ruby_frame->prev->last_class;
	data->frame.orig_func = ruby_frame->prev->orig_func;
    }

    if (data->iter) {
	blk_copy_prev(data);
    }
    else {
	data->prev = 0;
    }

    for (p = data; p; p = p->prev) {
	for (vars = p->dyna_vars; vars; vars = vars->next) {
	    if (FL_TEST(vars, DVAR_DONT_RECYCLE)) break;
	    FL_SET(vars, DVAR_DONT_RECYCLE);
	}
    }
    scope_dup(data->scope);
    POP_BLOCK();

    return bind;
}

/*
 *  call-seq:
 *     binding.eval(string [, filename [,lineno]])  => obj
 *
 *  Evaluates the Ruby expression(s) in <em>string</em>, in the
 *  <em>binding</em>'s context.  If the optional <em>filename</em> and
 *  <em>lineno</em> parameters are present, they will be used when
 *  reporting syntax errors.
 *
 *     def getBinding(param)
 *       return binding
 *     end
 *     b = getBinding("hello")
 *     b.eval("param")   #=> "hello"
 */

static VALUE
bind_eval(argc, argv, bindval)
    int argc;
    VALUE *argv;
    VALUE bindval;
{
    VALUE args[4];

    rb_scan_args(argc, argv, "12", &args[0], &args[2], &args[3]);
    args[1] = bindval;
    return rb_f_eval(argc+1, args, Qnil /* self will be searched in eval */);
}

#define SAFE_LEVEL_MAX PROC_TMASK

static void
proc_save_safe_level(data)
    VALUE data;
{
    int safe = ruby_safe_level;
    if (safe > PROC_TMAX) safe = PROC_TMAX;
    FL_SET(data, (safe << PROC_TSHIFT) & PROC_TMASK);
}

static int
proc_get_safe_level(data)
    VALUE data;
{
    return (RBASIC(data)->flags & PROC_TMASK) >> PROC_TSHIFT;
}

static void
proc_set_safe_level(data)
    VALUE data;
{
    ruby_safe_level = proc_get_safe_level(data);
}

static VALUE
proc_alloc(klass, proc)
    VALUE klass;
    int proc;
{
    volatile VALUE block;
    struct BLOCK *data, *p;
    struct RVarmap *vars;

    if (!rb_block_given_p() && !rb_f_block_given_p()) {
	rb_raise(rb_eArgError, "tried to create Proc object without a block");
    }
    if (proc && !rb_block_given_p()) {
	rb_warn("tried to create Proc object without a block");
    }

    if (!proc && ruby_block->block_obj) {
	VALUE obj = ruby_block->block_obj;
	if (CLASS_OF(obj) != klass) {
	    obj = proc_clone(obj);
	    RBASIC(obj)->klass = klass;
	}
	return obj;
    }
    block = Data_Make_Struct(klass, struct BLOCK, blk_mark, blk_free, data);
    *data = *ruby_block;

    data->orig_thread = rb_thread_current();
    data->wrapper = ruby_wrapper;
    data->iter = data->prev?Qtrue:Qfalse;
    data->block_obj = block;
    frame_dup(&data->frame);
    if (data->iter) {
	blk_copy_prev(data);
    }
    else {
	data->prev = 0;
    }

    for (p = data; p; p = p->prev) {
	for (vars = p->dyna_vars; vars; vars = vars->next) {
	    if (FL_TEST(vars, DVAR_DONT_RECYCLE)) break;
	    FL_SET(vars, DVAR_DONT_RECYCLE);
	}
    }
    scope_dup(data->scope);
    proc_save_safe_level(block);
    if (proc) {
	data->flags |= BLOCK_LAMBDA;
    }
    else {
	ruby_block->block_obj = block;
    }

    return block;
}

/*
 *  call-seq:
 *     Proc.new {|...| block } => a_proc
 *     Proc.new                => a_proc
 *
 *  Creates a new <code>Proc</code> object, bound to the current
 *  context. <code>Proc::new</code> may be called without a block only
 *  within a method with an attached block, in which case that block is
 *  converted to the <code>Proc</code> object.
 *
 *     def proc_from
 *       Proc.new
 *     end
 *     proc = proc_from { "hello" }
 *     proc.call   #=> "hello"
 */

static VALUE
proc_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE block = proc_alloc(klass, Qfalse);

    rb_obj_call_init(block, argc, argv);
    return block;
}

VALUE
rb_block_proc()
{
    return proc_alloc(rb_cProc, Qfalse);
}

VALUE
rb_f_lambda()
{
    rb_warn("rb_f_lambda() is deprecated; use rb_block_proc() instead");
    return proc_alloc(rb_cProc, Qtrue);
}

/*
 * call-seq:
 *   proc   { |...| block }  => a_proc
 *   lambda { |...| block }  => a_proc
 *
 * Equivalent to <code>Proc.new</code>, except the resulting Proc objects
 * check the number of parameters passed when called.
 */

static VALUE
proc_lambda()
{
    return proc_alloc(rb_cProc, Qtrue);
}

static int
block_orphan(data)
    struct BLOCK *data;
{
    if (data->scope->flags & SCOPE_NOSTACK) {
	return 1;
    }
    if (data->orig_thread != rb_thread_current()) {
	return 1;
    }
    return 0;
}

static VALUE
proc_invoke(proc, args, self, klass)
    VALUE proc, args;		/* OK */
    VALUE self, klass;
{
    struct BLOCK * volatile old_block;
    struct BLOCK _block;
    struct BLOCK *data;
    volatile VALUE result = Qundef;
    int state;
    volatile int safe = ruby_safe_level;
    volatile VALUE old_wrapper = ruby_wrapper;
    volatile int pcall, avalue = Qtrue;
    volatile VALUE tmp = args;
    VALUE bvar = Qnil;

    if (rb_block_given_p() && ruby_frame->last_func) {
	if (klass != ruby_frame->last_class)
	    klass = rb_obj_class(proc);
	bvar = rb_block_proc();
    }

    Data_Get_Struct(proc, struct BLOCK, data);
    pcall = (data->flags & BLOCK_LAMBDA) ? YIELD_LAMBDA_CALL : 0;
    if (!pcall && RARRAY(args)->len == 1) {
	avalue = Qfalse;
	args = RARRAY(args)->ptr[0];
    }

    PUSH_VARS();
    ruby_wrapper = data->wrapper;
    ruby_dyna_vars = data->dyna_vars;
    /* PUSH BLOCK from data */
    old_block = ruby_block;
    _block = *data;
    _block.block_obj = bvar;
    if (self != Qundef) _block.frame.self = self;
    if (klass) _block.frame.last_class = klass;
    _block.frame.argc = RARRAY(tmp)->len;
    _block.frame.flags = ruby_frame->flags;
    if (_block.frame.argc && DMETHOD_P()) {
        NEWOBJ(scope, struct SCOPE);
        OBJSETUP(scope, tmp, T_SCOPE);
        scope->local_tbl = _block.scope->local_tbl;
        scope->local_vars = _block.scope->local_vars;
        scope->flags |= SCOPE_CLONE | (_block.scope->flags & SCOPE_MALLOC);
        _block.scope = scope;
    }
    /* modify current frame */
    ruby_block = &_block;
    PUSH_ITER(ITER_CUR);
    ruby_frame->iter = ITER_CUR;
    PUSH_TAG(pcall ? PROT_LAMBDA : PROT_NONE);
    state = EXEC_TAG();
    if (state == 0) {
	proc_set_safe_level(proc);
	result = rb_yield_0(args, self, (self!=Qundef)?CLASS_OF(self):0,
			    pcall | YIELD_PROC_CALL, avalue);
    }
    else if (TAG_DST()) {
	result = prot_tag->retval;
    }
    POP_TAG();
    POP_ITER();
    ruby_block = old_block;
    ruby_wrapper = old_wrapper;
    POP_VARS();
    ruby_safe_level = safe;

    switch (state) {
      case 0:
	break;
      case TAG_RETRY:
	proc_jump_error(TAG_RETRY, Qnil); /* xxx */
	JUMP_TAG(state);
	break;
      case TAG_NEXT:
      case TAG_BREAK:
	if (!pcall && result != Qundef) {
	    proc_jump_error(state, result);
	}
      case TAG_RETURN:
	if (result != Qundef) {
	    if (pcall) break;
	    return_jump(result);
	}
      default:
	JUMP_TAG(state);
    }
    return result;
}

/* CHECKME: are the argument checking semantics correct? */

/*
 *  call-seq:
 *     prc.call(params,...)   => obj
 *     prc[params,...]        => obj
 *
 *  Invokes the block, setting the block's parameters to the values in
 *  <i>params</i> using something close to method calling semantics.
 *  Generates a warning if multiple values are passed to a proc that
 *  expects just one (previously this silently converted the parameters
 *  to an array).
 *
 *  For procs created using <code>Kernel.proc</code>, generates an
 *  error if the wrong number of parameters
 *  are passed to a proc with multiple parameters. For procs created using
 *  <code>Proc.new</code>, extra parameters are silently discarded.
 *
 *  Returns the value of the last expression evaluated in the block. See
 *  also <code>Proc#yield</code>.
 *
 *     a_proc = Proc.new {|a, *b| b.collect {|i| i*a }}
 *     a_proc.call(9, 1, 2, 3)   #=> [9, 18, 27]
 *     a_proc[9, 1, 2, 3]        #=> [9, 18, 27]
 *     a_proc = Proc.new {|a,b| a}
 *     a_proc.call(1,2,3)
 *
 *  <em>produces:</em>
 *
 *     prog.rb:5: wrong number of arguments (3 for 2) (ArgumentError)
 *     	from prog.rb:4:in `call'
 *     	from prog.rb:5
 */

/*
 *  call-seq:
 *     prc === obj   => obj
 *
 *  Invokes the block, with <i>obj</i> as the block's parameter.  It is
 *  to allow a proc object to be a target of when clause in the case statement.
 */

VALUE
rb_proc_call(proc, args)
    VALUE proc, args;		/* OK */
{
    return proc_invoke(proc, args, Qundef, 0);
}

static VALUE bmcall _((VALUE, VALUE));
static VALUE method_arity _((VALUE));

/*
 *  call-seq:
 *     prc.arity -> fixnum
 *
 *  Returns the number of arguments that would not be ignored. If the block
 *  is declared to take no arguments, returns 0. If the block is known
 *  to take exactly n arguments, returns n. If the block has optional
 *  arguments, return -n-1, where n is the number of mandatory
 *  arguments. A <code>proc</code> with no argument declarations
 *  is the same a block declaring <code>||</code> as its arguments.
 *
 *     Proc.new {}.arity          #=> -1
 *     Proc.new {||}.arity        #=>  0
 *     Proc.new {|a|}.arity       #=>  1
 *     Proc.new {|a,b|}.arity     #=>  2
 *     Proc.new {|a,b,c|}.arity   #=>  3
 *     Proc.new {|*a|}.arity      #=> -1
 *     Proc.new {|a,*b|}.arity    #=> -2
 */

static VALUE
proc_arity(proc)
    VALUE proc;
{
    struct BLOCK *data;
    NODE *var, *list;
    int n;

    Data_Get_Struct(proc, struct BLOCK, data);
    var = data->var;
    if (var == 0) {
	if (data->body && nd_type(data->body) == NODE_IFUNC &&
	    data->body->nd_cfnc == bmcall) {
	    return method_arity(data->body->nd_tval);
	}
	return INT2FIX(-1);
    }
    if (var == (NODE*)1) return INT2FIX(0);
    if (var == (NODE*)2) return INT2FIX(0);
    if (nd_type(var) == NODE_BLOCK_ARG) {
	var = var->nd_args;
	if (var == (NODE*)1) return INT2FIX(0);
	if (var == (NODE*)2) return INT2FIX(0);
    }
    switch (nd_type(var)) {
      default:
	return INT2FIX(1);
      case NODE_MASGN:
	list = var->nd_head;
	n = 0;
	while (list) {
	    n++;
	    list = list->nd_next;
	}
	if (var->nd_args) return INT2FIX(-n-1);
	return INT2FIX(n);
    }
}

/*
 * call-seq:
 *   prc == other_proc   =>  true or false
 *
 * Return <code>true</code> if <i>prc</i> is the same object as
 * <i>other_proc</i>, or if they are both procs with the same body.
 */

static VALUE
proc_eq(self, other)
    VALUE self, other;
{
    struct BLOCK *data, *data2;

    if (self == other) return Qtrue;
    if (TYPE(other) != T_DATA) return Qfalse;
    if (RDATA(other)->dmark != (RUBY_DATA_FUNC)blk_mark) return Qfalse;
    if (CLASS_OF(self) != CLASS_OF(other)) return Qfalse;
    Data_Get_Struct(self, struct BLOCK, data);
    Data_Get_Struct(other, struct BLOCK, data2);
    if (data->body != data2->body) return Qfalse;
    if (data->var != data2->var) return Qfalse;
    if (data->scope != data2->scope) return Qfalse;
    if (data->dyna_vars != data2->dyna_vars) return Qfalse;
    if (data->flags != data2->flags) return Qfalse;

    return Qtrue;
}

/*
 * call-seq:
 *   prc.to_s   => string
 *
 * Shows the unique identifier for this proc, along with
 * an indication of where the proc was defined.
 */

static VALUE
proc_to_s(self)
    VALUE self;
{
    struct BLOCK *data;
    NODE *node;
    const char *cname = rb_obj_classname(self);
    const int w = (sizeof(VALUE) * CHAR_BIT) / 4;
    long len = strlen(cname)+6+w; /* 6:tags 16:addr */
    VALUE str;

    Data_Get_Struct(self, struct BLOCK, data);
    if ((node = data->frame.node) || (node = data->body)) {
	len += strlen(node->nd_file) + 2 + (SIZEOF_LONG*CHAR_BIT-NODE_LSHIFT)/3;
	str = rb_str_new(0, len);
	snprintf(RSTRING(str)->ptr, len+1,
		 "#<%s:0x%.*lx@%s:%d>", cname, w, (VALUE)data->body,
		 node->nd_file, nd_line(node));
    }
    else {
	str = rb_str_new(0, len);
	snprintf(RSTRING(str)->ptr, len+1,
		 "#<%s:0x%.*lx>", cname, w, (VALUE)data->body);
    }
    RSTRING(str)->len = strlen(RSTRING(str)->ptr);
    if (OBJ_TAINTED(self)) OBJ_TAINT(str);

    return str;
}

/*
 *  call-seq:
 *     prc.to_proc -> prc
 *
 *  Part of the protocol for converting objects to <code>Proc</code>
 *  objects. Instances of class <code>Proc</code> simply return
 *  themselves.
 */

static VALUE
proc_to_self(self)
    VALUE self;
{
    return self;
}

/*
 *  call-seq:
 *     prc.binding    => binding
 *
 *  Returns the binding associated with <i>prc</i>. Note that
 *  <code>Kernel#eval</code> accepts either a <code>Proc</code> or a
 *  <code>Binding</code> object as its second parameter.
 *
 *     def fred(param)
 *       proc {}
 *     end
 *
 *     b = fred(99)
 *     eval("param", b.binding)   #=> 99
 *     eval("param", b)           #=> 99
 */

static VALUE
proc_binding(proc)
    VALUE proc;
{
    struct BLOCK *orig, *data;
    VALUE bind;

    Data_Get_Struct(proc, struct BLOCK, orig);
    bind = Data_Make_Struct(rb_cBinding,struct BLOCK,blk_mark,blk_free,data);
    MEMCPY(data, orig, struct BLOCK, 1);
    frame_dup(&data->frame);

    if (data->iter) {
	blk_copy_prev(data);
    }
    else {
	data->prev = 0;
    }

    return bind;
}

static VALUE
rb_block_pass(func, arg, proc)
    VALUE (*func) _((VALUE));
    VALUE arg;
    VALUE proc;
{
    VALUE b;
    struct BLOCK * volatile old_block;
    struct BLOCK _block;
    struct BLOCK *data;
    volatile VALUE result = Qnil;
    int state;
    volatile int orphan;
    volatile int safe = ruby_safe_level;

    if (NIL_P(proc)) {
	PUSH_ITER(ITER_NOT);
	result = (*func)(arg);
	POP_ITER();
	return result;
    }
    if (!rb_obj_is_proc(proc)) {
	b = rb_check_convert_type(proc, T_DATA, "Proc", "to_proc");
	if (!rb_obj_is_proc(b)) {
	    rb_raise(rb_eTypeError, "wrong argument type %s (expected Proc)",
		     rb_obj_classname(proc));
	}
	proc = b;
    }

    if (ruby_safe_level >= 1 && OBJ_TAINTED(proc) &&
	ruby_safe_level > proc_get_safe_level(proc)) {
	rb_raise(rb_eSecurityError, "Insecure: tainted block value");
    }

    if (ruby_block && ruby_block->block_obj == proc) {
	PUSH_ITER(ITER_PAS);
	result = (*func)(arg);
	POP_ITER();
	return result;
    }

    Data_Get_Struct(proc, struct BLOCK, data);
    orphan = block_orphan(data);

    /* PUSH BLOCK from data */
    old_block = ruby_block;
    _block = *data;
    _block.outer = ruby_block;
    if (orphan) _block.uniq = block_unique++;
    ruby_block = &_block;
    PUSH_ITER(ITER_PRE);
    if (ruby_frame->iter == ITER_NOT)
	ruby_frame->iter = ITER_PRE;

    PUSH_TAG(PROT_LOOP);
    state = EXEC_TAG();
    if (state == 0) {
      retry:
	proc_set_safe_level(proc);
	if (safe > ruby_safe_level)
	    ruby_safe_level = safe;
	result = (*func)(arg);
    }
    else if (state == TAG_BREAK && TAG_DST()) {
	result = prot_tag->retval;
	state = 0;
    }
    else if (state == TAG_RETRY) {
	state = 0;
	goto retry;
    }
    POP_TAG();
    POP_ITER();
    ruby_block = old_block;
    ruby_safe_level = safe;

    switch (state) {/* escape from orphan block */
      case 0:
	break;
      case TAG_RETURN:
	if (orphan) {
	    proc_jump_error(state, prot_tag->retval);
	}
      default:
	JUMP_TAG(state);
    }

    return result;
}

struct block_arg {
    VALUE self;
    NODE *iter;
};

static VALUE
call_block(arg)
    struct block_arg *arg;
{
    return rb_eval(arg->self, arg->iter);
}

static VALUE
block_pass(self, node)
    VALUE self;
    NODE *node;
{
    struct block_arg arg;
    arg.self = self;
    arg.iter = node->nd_iter;
    return rb_block_pass((VALUE (*)_((VALUE)))call_block,
			 (VALUE)&arg, rb_eval(self, node->nd_body));
}

struct METHOD {
    VALUE klass, rklass;
    VALUE recv;
    ID id, oid;
    int safe_level;
    NODE *body;
};

static void
bm_mark(data)
    struct METHOD *data;
{
    rb_gc_mark(data->rklass);
    rb_gc_mark(data->klass);
    rb_gc_mark(data->recv);
    rb_gc_mark((VALUE)data->body);
}

static VALUE
mnew(klass, obj, id, mklass)
    VALUE klass, obj, mklass;
    ID id;
{
    VALUE method;
    NODE *body;
    int noex;
    struct METHOD *data;
    VALUE rklass = klass;
    ID oid = id;

  again:
    if ((body = rb_get_method_body(&klass, &oid, &noex)) == 0) {
	print_undef(rklass, id);
    }

    if (nd_type(body) == NODE_ZSUPER) {
	klass = RCLASS(klass)->super;
	goto again;
    }

    while (rklass != klass &&
	   (FL_TEST(rklass, FL_SINGLETON) || TYPE(rklass) == T_ICLASS)) {
	rklass = RCLASS(rklass)->super;
    }
    if (TYPE(klass) == T_ICLASS) klass = RBASIC(klass)->klass;
    method = Data_Make_Struct(mklass, struct METHOD, bm_mark, free, data);
    data->klass = klass;
    data->recv = obj;
    data->id = id;
    data->body = body;
    data->rklass = rklass;
    data->oid = oid;
    data->safe_level = NOEX_WITH_SAFE(noex);
    OBJ_INFECT(method, klass);

    return method;
}


/**********************************************************************
 *
 * Document-class : Method
 *
 *  Method objects are created by <code>Object#method</code>, and are
 *  associated with a particular object (not just with a class). They
 *  may be used to invoke the method within the object, and as a block
 *  associated with an iterator. They may also be unbound from one
 *  object (creating an <code>UnboundMethod</code>) and bound to
 *  another.
 *
 *     class Thing
 *       def square(n)
 *         n*n
 *       end
 *     end
 *     thing = Thing.new
 *     meth  = thing.method(:square)
 *
 *     meth.call(9)                 #=> 81
 *     [ 1, 2, 3 ].collect(&meth)   #=> [1, 4, 9]
 *
 */

/*
 * call-seq:
 *   meth == other_meth  => true or false
 *
 * Two method objects are equal if that are bound to the same
 * object and contain the same body.
 */


static VALUE
method_eq(method, other)
    VALUE method, other;
{
    struct METHOD *m1, *m2;

    if (TYPE(other) != T_DATA || RDATA(other)->dmark != (RUBY_DATA_FUNC)bm_mark)
	return Qfalse;
    if (CLASS_OF(method) != CLASS_OF(other))
	return Qfalse;

    Data_Get_Struct(method, struct METHOD, m1);
    Data_Get_Struct(other, struct METHOD, m2);

    if (m1->klass != m2->klass || m1->rklass != m2->rklass ||
	m1->recv != m2->recv || m1->body != m2->body)
	return Qfalse;

    return Qtrue;
}

/*
 *  call-seq:
 *     meth.unbind    => unbound_method
 *
 *  Dissociates <i>meth</i> from it's current receiver. The resulting
 *  <code>UnboundMethod</code> can subsequently be bound to a new object
 *  of the same class (see <code>UnboundMethod</code>).
 */

static VALUE
method_unbind(obj)
    VALUE obj;
{
    VALUE method;
    struct METHOD *orig, *data;

    Data_Get_Struct(obj, struct METHOD, orig);
    method = Data_Make_Struct(rb_cUnboundMethod, struct METHOD, bm_mark, free, data);
    data->klass = orig->klass;
    data->recv = Qundef;
    data->id = orig->id;
    data->body = orig->body;
    data->rklass = orig->rklass;
    data->oid = orig->oid;
    OBJ_INFECT(method, obj);

    return method;
}

/*
 *  call-seq:
 *     meth.receiver    => object
 *
 *  Returns the bound receiver of the method object.
 */

static VALUE
method_receiver(obj)
    VALUE obj;
{
    struct METHOD *data;

    Data_Get_Struct(obj, struct METHOD, data);
    return data->recv;
}

/*
 *  call-seq:
 *     meth.name    => string
 *
 *  Returns the name of the method.
 */

static VALUE
method_name(obj)
    VALUE obj;
{
    struct METHOD *data;

    Data_Get_Struct(obj, struct METHOD, data);
    return rb_str_new2(rb_id2name(data->id));
}

/*
 *  call-seq:
 *     meth.owner    => class_or_module
 *
 *  Returns the class or module that defines the method.
 */

static VALUE
method_owner(obj)
    VALUE obj;
{
    struct METHOD *data;

    Data_Get_Struct(obj, struct METHOD, data);
    return data->klass;
}

/*
 *  call-seq:
 *     obj.method(sym)    => method
 *
 *  Looks up the named method as a receiver in <i>obj</i>, returning a
 *  <code>Method</code> object (or raising <code>NameError</code>). The
 *  <code>Method</code> object acts as a closure in <i>obj</i>'s object
 *  instance, so instance variables and the value of <code>self</code>
 *  remain available.
 *
 *     class Demo
 *       def initialize(n)
 *         @iv = n
 *       end
 *       def hello()
 *         "Hello, @iv = #{@iv}"
 *       end
 *     end
 *
 *     k = Demo.new(99)
 *     m = k.method(:hello)
 *     m.call   #=> "Hello, @iv = 99"
 *
 *     l = Demo.new('Fred')
 *     m = l.method("hello")
 *     m.call   #=> "Hello, @iv = Fred"
 */

VALUE
rb_obj_method(obj, vid)
    VALUE obj;
    VALUE vid;
{
    return mnew(CLASS_OF(obj), obj, rb_to_id(vid), rb_cMethod);
}

/*
 *  call-seq:
 *     mod.instance_method(symbol)   => unbound_method
 *
 *  Returns an +UnboundMethod+ representing the given
 *  instance method in _mod_.
 *
 *     class Interpreter
 *       def do_a() print "there, "; end
 *       def do_d() print "Hello ";  end
 *       def do_e() print "!\n";     end
 *       def do_v() print "Dave";    end
 *       Dispatcher = {
 *        ?a => instance_method(:do_a),
 *        ?d => instance_method(:do_d),
 *        ?e => instance_method(:do_e),
 *        ?v => instance_method(:do_v)
 *       }
 *       def interpret(string)
 *         string.each_byte {|b| Dispatcher[b].bind(self).call }
 *       end
 *     end
 *
 *
 *     interpreter = Interpreter.new
 *     interpreter.interpret('dave')
 *
 *  <em>produces:</em>
 *
 *     Hello there, Dave!
 */

static VALUE
rb_mod_method(mod, vid)
    VALUE mod;
    VALUE vid;
{
    return mnew(mod, Qundef, rb_to_id(vid), rb_cUnboundMethod);
}

/*
 * MISSING: documentation
 */

static VALUE
method_clone(self)
    VALUE self;
{
    VALUE clone;
    struct METHOD *orig, *data;

    Data_Get_Struct(self, struct METHOD, orig);
    clone = Data_Make_Struct(CLASS_OF(self),struct METHOD, bm_mark, free, data);
    CLONESETUP(clone, self);
    *data = *orig;

    return clone;
}

VALUE
rb_method_dup(self, klass, cref)
    VALUE self;
    VALUE klass;
    VALUE cref;
{
    VALUE clone;
    struct METHOD *orig, *data;

    Data_Get_Struct(self, struct METHOD, orig);
    clone = Data_Make_Struct(CLASS_OF(self),struct METHOD, bm_mark, free, data);
    *data = *orig;
    data->rklass = klass;
    if (data->body->nd_rval) {
	NODE *tmp = NEW_NODE(nd_type(data->body->u2.node), cref,
			     data->body->u2.node->u2.node,
			     data->body->u2.node->u3.node);
	data->body = NEW_NODE(nd_type(data->body), data->body->u1.node, tmp,
			      data->body->u3.node);
    }
    return clone;
}

/*
 *  call-seq:
 *     meth.call(args, ...)    => obj
 *     meth[args, ...]         => obj
 *
 *  Invokes the <i>meth</i> with the specified arguments, returning the
 *  method's return value.
 *
 *     m = 12.method("+")
 *     m.call(3)    #=> 15
 *     m.call(20)   #=> 32
 */

static VALUE
method_call(argc, argv, method)
    int argc;
    VALUE *argv;
    VALUE method;
{
    VALUE result = Qnil;	/* OK */
    struct METHOD *data;
    int safe;

    Data_Get_Struct(method, struct METHOD, data);
    if (data->recv == Qundef) {
	rb_raise(rb_eTypeError, "can't call unbound method; bind first");
    }
    if (OBJ_TAINTED(method)) {
        safe = NOEX_WITH(data->safe_level, 4)|NOEX_TAINTED;
    }
    else {
	safe = data->safe_level;
    }
    PUSH_ITER(rb_block_given_p()?ITER_PRE:ITER_NOT);
    result = rb_call0(data->klass,data->recv,data->id,data->oid,argc,argv,data->body,safe);
    POP_ITER();
    return result;
}

/**********************************************************************
 *
 * Document-class: UnboundMethod
 *
 *  Ruby supports two forms of objectified methods. Class
 *  <code>Method</code> is used to represent methods that are associated
 *  with a particular object: these method objects are bound to that
 *  object. Bound method objects for an object can be created using
 *  <code>Object#method</code>.
 *
 *  Ruby also supports unbound methods; methods objects that are not
 *  associated with a particular object. These can be created either by
 *  calling <code>Module#instance_method</code> or by calling
 *  <code>unbind</code> on a bound method object. The result of both of
 *  these is an <code>UnboundMethod</code> object.
 *
 *  Unbound methods can only be called after they are bound to an
 *  object. That object must be be a kind_of? the method's original
 *  class.
 *
 *     class Square
 *       def area
 *         @side * @side
 *       end
 *       def initialize(side)
 *         @side = side
 *       end
 *     end
 *
 *     area_un = Square.instance_method(:area)
 *
 *     s = Square.new(12)
 *     area = area_un.bind(s)
 *     area.call   #=> 144
 *
 *  Unbound methods are a reference to the method at the time it was
 *  objectified: subsequent changes to the underlying class will not
 *  affect the unbound method.
 *
 *     class Test
 *       def test
 *         :original
 *       end
 *     end
 *     um = Test.instance_method(:test)
 *     class Test
 *       def test
 *         :modified
 *       end
 *     end
 *     t = Test.new
 *     t.test            #=> :modified
 *     um.bind(t).call   #=> :original
 *
 */

/*
 *  call-seq:
 *     umeth.bind(obj) -> method
 *
 *  Bind <i>umeth</i> to <i>obj</i>. If <code>Klass</code> was the class
 *  from which <i>umeth</i> was obtained,
 *  <code>obj.kind_of?(Klass)</code> must be true.
 *
 *     class A
 *       def test
 *         puts "In test, class = #{self.class}"
 *       end
 *     end
 *     class B < A
 *     end
 *     class C < B
 *     end
 *
 *
 *     um = B.instance_method(:test)
 *     bm = um.bind(C.new)
 *     bm.call
 *     bm = um.bind(B.new)
 *     bm.call
 *     bm = um.bind(A.new)
 *     bm.call
 *
 *  <em>produces:</em>
 *
 *     In test, class = C
 *     In test, class = B
 *     prog.rb:16:in `bind': bind argument must be an instance of B (TypeError)
 *     	from prog.rb:16
 */

static VALUE
umethod_bind(method, recv)
    VALUE method, recv;
{
    struct METHOD *data, *bound;
    VALUE rklass = CLASS_OF(recv);

    Data_Get_Struct(method, struct METHOD, data);
    if (data->rklass != rklass) {
	if (TYPE(data->rklass) == T_MODULE) {
	    st_table *m_tbl = RCLASS(data->rklass)->m_tbl;
	    while (RCLASS(rklass)->m_tbl != m_tbl) {
		rklass = RCLASS(rklass)->super;
		if (!rklass) goto not_instace;
	    }
	}
	else if (!rb_obj_is_kind_of(recv, data->rklass)) {
	    if (FL_TEST(data->rklass, FL_SINGLETON)) {
		rb_raise(rb_eTypeError, "singleton method bound for a different object");
	    } else {
	      not_instace:
		rb_raise(rb_eTypeError, "bind argument must be an instance of %s",
			 rb_class2name(data->rklass));
	    }
	}
    }

    method = Data_Make_Struct(rb_cMethod,struct METHOD,bm_mark,free,bound);
    *bound = *data;
    bound->recv = recv;
    bound->rklass = rklass;

    return method;
}

/*
 *  call-seq:
 *     meth.arity    => fixnum
 *
 *  Returns an indication of the number of arguments accepted by a
 *  method. Returns a nonnegative integer for methods that take a fixed
 *  number of arguments. For Ruby methods that take a variable number of
 *  arguments, returns -n-1, where n is the number of required
 *  arguments. For methods written in C, returns -1 if the call takes a
 *  variable number of arguments.
 *
 *     class C
 *       def one;    end
 *       def two(a); end
 *       def three(*a);  end
 *       def four(a, b); end
 *       def five(a, b, *c);    end
 *       def six(a, b, *c, &d); end
 *     end
 *     c = C.new
 *     c.method(:one).arity     #=> 0
 *     c.method(:two).arity     #=> 1
 *     c.method(:three).arity   #=> -1
 *     c.method(:four).arity    #=> 2
 *     c.method(:five).arity    #=> -3
 *     c.method(:six).arity     #=> -3
 *
 *     "cat".method(:size).arity      #=> 0
 *     "cat".method(:replace).arity   #=> 1
 *     "cat".method(:squeeze).arity   #=> -1
 *     "cat".method(:count).arity     #=> -1
 */

static VALUE
method_arity(method)
    VALUE method;
{
    struct METHOD *data;
    NODE *body;
    int n;

    Data_Get_Struct(method, struct METHOD, data);

    body = data->body;
    switch (nd_type(body)) {
      case NODE_CFUNC:
	if (body->nd_argc < 0) return INT2FIX(-1);
	return INT2FIX(body->nd_argc);
      case NODE_ZSUPER:
	return INT2FIX(-1);
      case NODE_ATTRSET:
	return INT2FIX(1);
      case NODE_IVAR:
	return INT2FIX(0);
      case NODE_BMETHOD:
	return proc_arity(body->nd_cval);
      case NODE_DMETHOD:
	return method_arity(body->nd_cval);
      case NODE_SCOPE:
	body = body->nd_next;	/* skip NODE_SCOPE */
	if (nd_type(body) == NODE_BLOCK)
	    body = body->nd_head;
	if (!body) return INT2FIX(0);
	n = body->nd_cnt;
	if (body->nd_opt || body->nd_rest)
	    n = -n-1;
	return INT2FIX(n);
      default:
	rb_raise(rb_eArgError, "invalid node 0x%x", nd_type(body));
   }
}

/*
 *  call-seq:
 *   meth.to_s      =>  string
 *   meth.inspect   =>  string
 *
 *  Show the name of the underlying method.
 *
 *    "cat".method(:count).inspect   #=> "#<Method: String#count>"
 */

static VALUE
method_inspect(method)
    VALUE method;
{
    struct METHOD *data;
    VALUE str;
    const char *s;
    const char *sharp = "#";

    Data_Get_Struct(method, struct METHOD, data);
    str = rb_str_buf_new2("#<");
    s = rb_obj_classname(method);
    rb_str_buf_cat2(str, s);
    rb_str_buf_cat2(str, ": ");

    if (FL_TEST(data->klass, FL_SINGLETON)) {
	VALUE v = rb_iv_get(data->klass, "__attached__");

	if (data->recv == Qundef) {
	    rb_str_buf_append(str, rb_inspect(data->klass));
	}
	else if (data->recv == v) {
	    rb_str_buf_append(str, rb_inspect(v));
	    sharp = ".";
	}
	else {
	    rb_str_buf_append(str, rb_inspect(data->recv));
	    rb_str_buf_cat2(str, "(");
	    rb_str_buf_append(str, rb_inspect(v));
	    rb_str_buf_cat2(str, ")");
	    sharp = ".";
	}
    }
    else {
	rb_str_buf_cat2(str, rb_class2name(data->rklass));
	if (data->rklass != data->klass) {
	    rb_str_buf_cat2(str, "(");
	    rb_str_buf_cat2(str, rb_class2name(data->klass));
	    rb_str_buf_cat2(str, ")");
	}
    }
    rb_str_buf_cat2(str, sharp);
    rb_str_buf_cat2(str, rb_id2name(data->id));
    rb_str_buf_cat2(str, ">");

    return str;
}

static VALUE
mproc(method)
    VALUE method;
{
    VALUE proc;

    /* emulate ruby's method call */
    PUSH_ITER(ITER_CUR);
    PUSH_FRAME();
    proc = rb_block_proc();
    POP_FRAME();
    POP_ITER();

    return proc;
}

static VALUE
bmcall(args, method)
    VALUE args, method;
{
    volatile VALUE a;
    VALUE ret;

    a = svalue_to_avalue(args);
    ret = method_call(RARRAY(a)->len, RARRAY(a)->ptr, method);
    a = Qnil; /* prevent tail call */
    return ret;
}

VALUE
rb_proc_new(func, val)
    VALUE (*func)(ANYARGS);	/* VALUE yieldarg[, VALUE procarg] */
    VALUE val;
{
    struct BLOCK *data;
    VALUE proc = rb_iterate((VALUE(*)_((VALUE)))mproc, 0, func, val);

    Data_Get_Struct(proc, struct BLOCK, data);
    data->body->nd_state = YIELD_FUNC_LAMBDA;
    data->flags |= BLOCK_LAMBDA;
    return proc;
}

/*
 *  call-seq:
 *     meth.to_proc    => prc
 *
 *  Returns a <code>Proc</code> object corresponding to this method.
 */

static VALUE
method_proc(method)
    VALUE method;
{
    VALUE proc;
    struct METHOD *mdata;
    struct BLOCK *bdata;

    proc = rb_iterate((VALUE(*)_((VALUE)))mproc, 0, bmcall, method);
    Data_Get_Struct(method, struct METHOD, mdata);
    Data_Get_Struct(proc, struct BLOCK, bdata);
    bdata->body->nd_file = mdata->body->nd_file;
    nd_set_line(bdata->body, nd_line(mdata->body));
    bdata->body->nd_state = YIELD_FUNC_SVALUE;

    return proc;
}

static VALUE
rb_obj_is_method(m)
    VALUE m;
{
    if (TYPE(m) == T_DATA && RDATA(m)->dmark == (RUBY_DATA_FUNC)bm_mark) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     define_method(symbol, method)     => new_method
 *     define_method(symbol) { block }   => proc
 *
 *  Defines an instance method in the receiver. The _method_
 *  parameter can be a +Proc+, a +Method+ or an +UnboundMethod+ object.
 *  If a block is specified, it is used as the method body. This block
 *  is evaluated using <code>instance_eval</code>, a point that is
 *  tricky to demonstrate because <code>define_method</code> is private.
 *  (This is why we resort to the +send+ hack in this example.)
 *
 *     class A
 *       def fred
 *         puts "In Fred"
 *       end
 *       def create_method(name, &block)
 *         self.class.send(:define_method, name, &block)
 *       end
 *       define_method(:wilma) { puts "Charge it!" }
 *     end
 *     class B < A
 *       define_method(:barney, instance_method(:fred))
 *     end
 *     a = B.new
 *     a.barney
 *     a.wilma
 *     a.create_method(:betty) { p self }
 *     a.betty
 *
 *  <em>produces:</em>
 *
 *     In Fred
 *     Charge it!
 *     #<B:0x401b39e8>
 */

static VALUE
rb_mod_define_method(argc, argv, mod)
    int argc;
    VALUE *argv;
    VALUE mod;
{
    ID id;
    VALUE body, orig;
    NODE *node;
    int noex;

    if (argc == 1) {
	id = rb_to_id(argv[0]);
	body = proc_lambda();
    }
    else if (argc == 2) {
	id = rb_to_id(argv[0]);
	body = argv[1];
	if (!rb_obj_is_method(body) && !rb_obj_is_proc(body)) {
	    rb_raise(rb_eTypeError, "wrong argument type %s (expected Proc/Method)",
		     rb_obj_classname(body));
	}
    }
    else {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", argc);
    }
    orig = body;
    if (RDATA(body)->dmark == (RUBY_DATA_FUNC)bm_mark) {
	node = NEW_DMETHOD(method_unbind(body));
    }
    else if (RDATA(body)->dmark == (RUBY_DATA_FUNC)blk_mark) {
	struct BLOCK *block;

	body = proc_clone(body);
	Data_Get_Struct(body, struct BLOCK, block);
	block->frame.last_func = id;
	block->frame.orig_func = id;
	block->frame.last_class = mod;
	node = NEW_BMETHOD(body);
    }
    else {
	/* type error */
	rb_raise(rb_eTypeError, "wrong argument type (expected Proc/Method)");
    }

    noex = NOEX_PUBLIC;
    if (ruby_cbase == mod) {
	if (SCOPE_TEST(SCOPE_PRIVATE)) {
	    noex = NOEX_PRIVATE;
	}
	else if (SCOPE_TEST(SCOPE_PROTECTED)) {
	    noex = NOEX_PROTECTED;
	}
    }
    rb_add_method(mod, id, node, noex);
    return orig;
}

/*
 *  <code>Proc</code> objects are blocks of code that have been bound to
 *  a set of local variables. Once bound, the code may be called in
 *  different contexts and still access those variables.
 *
 *     def gen_times(factor)
 *       return Proc.new {|n| n*factor }
 *     end
 *
 *     times3 = gen_times(3)
 *     times5 = gen_times(5)
 *
 *     times3.call(12)               #=> 36
 *     times5.call(5)                #=> 25
 *     times3.call(times5.call(4))   #=> 60
 *
 */

void
Init_Proc()
{
    rb_eLocalJumpError = rb_define_class("LocalJumpError", rb_eStandardError);
    rb_define_method(rb_eLocalJumpError, "exit_value", localjump_xvalue, 0);
    rb_define_method(rb_eLocalJumpError, "reason", localjump_reason, 0);

    rb_global_variable(&exception_error);
    exception_error = rb_exc_new3(rb_eFatal,
				  rb_obj_freeze(rb_str_new2("exception reentered")));
    OBJ_TAINT(exception_error);
    OBJ_FREEZE(exception_error);

    rb_eSysStackError = rb_define_class("SystemStackError", rb_eStandardError);
    rb_global_variable(&sysstack_error);
    sysstack_error = rb_exc_new3(rb_eSysStackError,
				 rb_obj_freeze(rb_str_new2("stack level too deep")));
    OBJ_TAINT(sysstack_error);
    OBJ_FREEZE(sysstack_error);

    rb_cProc = rb_define_class("Proc", rb_cObject);
    rb_undef_alloc_func(rb_cProc);
    rb_define_singleton_method(rb_cProc, "new", proc_s_new, -1);

    rb_define_method(rb_cProc, "clone", proc_clone, 0);
    rb_define_method(rb_cProc, "dup", proc_dup, 0);
    rb_define_method(rb_cProc, "call", rb_proc_call, -2);
    rb_define_method(rb_cProc, "arity", proc_arity, 0);
    rb_define_method(rb_cProc, "[]", rb_proc_call, -2);
    rb_define_method(rb_cProc, "===", rb_proc_call, -2);
    rb_define_method(rb_cProc, "==", proc_eq, 1);
    rb_define_method(rb_cProc, "to_s", proc_to_s, 0);
    rb_define_method(rb_cProc, "to_proc", proc_to_self, 0);
    rb_define_method(rb_cProc, "binding", proc_binding, 0);

    rb_define_global_function("proc", proc_lambda, 0);
    rb_define_global_function("lambda", proc_lambda, 0);

    rb_cMethod = rb_define_class("Method", rb_cObject);
    rb_undef_alloc_func(rb_cMethod);
    rb_undef_method(CLASS_OF(rb_cMethod), "new");
    rb_define_method(rb_cMethod, "==", method_eq, 1);
    rb_define_method(rb_cMethod, "clone", method_clone, 0);
    rb_define_method(rb_cMethod, "call", method_call, -1);
    rb_define_method(rb_cMethod, "[]", method_call, -1);
    rb_define_method(rb_cMethod, "arity", method_arity, 0);
    rb_define_method(rb_cMethod, "inspect", method_inspect, 0);
    rb_define_method(rb_cMethod, "to_s", method_inspect, 0);
    rb_define_method(rb_cMethod, "to_proc", method_proc, 0);
    rb_define_method(rb_cMethod, "receiver", method_receiver, 0);
    rb_define_method(rb_cMethod, "name", method_name, 0);
    rb_define_method(rb_cMethod, "owner", method_owner, 0);
    rb_define_method(rb_cMethod, "unbind", method_unbind, 0);
    rb_define_method(rb_mKernel, "method", rb_obj_method, 1);

    rb_cUnboundMethod = rb_define_class("UnboundMethod", rb_cObject);
    rb_undef_alloc_func(rb_cUnboundMethod);
    rb_undef_method(CLASS_OF(rb_cUnboundMethod), "new");
    rb_define_method(rb_cUnboundMethod, "==", method_eq, 1);
    rb_define_method(rb_cUnboundMethod, "clone", method_clone, 0);
    rb_define_method(rb_cUnboundMethod, "arity", method_arity, 0);
    rb_define_method(rb_cUnboundMethod, "inspect", method_inspect, 0);
    rb_define_method(rb_cUnboundMethod, "to_s", method_inspect, 0);
    rb_define_method(rb_cUnboundMethod, "name", method_name, 0);
    rb_define_method(rb_cUnboundMethod, "owner", method_owner, 0);
    rb_define_method(rb_cUnboundMethod, "bind", umethod_bind, 1);
    rb_define_method(rb_cModule, "instance_method", rb_mod_method, 1);
}

/*
 *  Objects of class <code>Binding</code> encapsulate the execution
 *  context at some particular place in the code and retain this context
 *  for future use. The variables, methods, value of <code>self</code>,
 *  and possibly an iterator block that can be accessed in this context
 *  are all retained. Binding objects can be created using
 *  <code>Kernel#binding</code>, and are made available to the callback
 *  of <code>Kernel#set_trace_func</code>.
 *
 *  These binding objects can be passed as the second argument of the
 *  <code>Kernel#eval</code> method, establishing an environment for the
 *  evaluation.
 *
 *     class Demo
 *       def initialize(n)
 *         @secret = n
 *       end
 *       def getBinding
 *         return binding()
 *       end
 *     end
 *
 *     k1 = Demo.new(99)
 *     b1 = k1.getBinding
 *     k2 = Demo.new(-3)
 *     b2 = k2.getBinding
 *
 *     eval("@secret", b1)   #=> 99
 *     eval("@secret", b2)   #=> -3
 *     eval("@secret")       #=> nil
 *
 *  Binding objects have no class-specific methods.
 *
 */

void
Init_Binding()
{
    rb_cBinding = rb_define_class("Binding", rb_cObject);
    rb_undef_alloc_func(rb_cBinding);
    rb_undef_method(CLASS_OF(rb_cBinding), "new");
    rb_define_method(rb_cBinding, "clone", proc_clone, 0);
    rb_define_method(rb_cBinding, "dup", proc_dup, 0);
    rb_define_method(rb_cBinding, "eval", bind_eval, -1);
    rb_define_global_function("binding", rb_f_binding, 0);
}

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
    __asm__("movl %%fs:0,%0" : "=r"(p));
#   endif
# elif defined __BORLANDC__
#   define SAVE_WIN32_EXCEPTION_LIST
    __emit__(0x64, 0xA1, 0, 0, 0, 0); /* mov eax, fs:[0] */
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
    __asm__("movl %0,%%fs:0" :: "r"(p));
#   endif
# elif defined __BORLANDC__
    _EAX = p;
    __emit__(0x64, 0xA3, 0, 0, 0, 0); /* mov fs:[0], eax */
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
#define WAIT_DONE	(1<<5)

/* +infty, for this purpose */
#define DELAY_INFTY 1E30

#if !defined HAVE_PAUSE
# if defined _WIN32 && !defined __CYGWIN__
#  define pause() Sleep(INFINITE)
# else
#  define pause() sleep(0x7fffffff)
# endif
#endif

#define THREAD_TERMINATING 0x400 /* persistent flag */
#define THREAD_NO_ENSURE   0x800 /* persistent flag */
#define THREAD_FLAGS_MASK 0xfc00 /* mask for persistent flags */

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

    enum rb_thread_status status;
    int wait_for;
    int fd;
    fd_set readfds;
    fd_set writefds;
    fd_set exceptfds;
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
    (dst)->select_value = (src)->select_value,	\
    (dst)->delay = (src)->delay,		\
    (dst)->join = (src)->join,			\
    0)

int
rb_thread_set_raised(th)
    rb_thread_t th;
{
    if (th->flags & RAISED_EXCEPTION) {
	return 1;
    }
    th->flags |= RAISED_EXCEPTION;
    return 0;
}

int
rb_thread_reset_raised(th)
    rb_thread_t th;
{
    if (!(th->flags & RAISED_EXCEPTION)) {
	return 0;
    }
    th->flags &= ~RAISED_EXCEPTION;
    return 1;
}

static int
thread_no_ensure()
{
    return ((curr_thread->flags & THREAD_NO_ENSURE) == THREAD_NO_ENSURE);
}

static void rb_thread_ready _((rb_thread_t));

static VALUE run_trap_eval _((VALUE));
static VALUE
run_trap_eval(arg)
    VALUE arg;
{
    VALUE *p = (VALUE *)arg;
    return rb_eval_cmd(p[0], p[1], (int)p[2]);
}

static VALUE
rb_trap_eval(cmd, sig, safe)
    VALUE cmd;
    int sig, safe;
{
    int state;
    VALUE val = Qnil;		/* OK */
    volatile struct thread_status_t save;
    VALUE arg[3];

    arg[0] = cmd;
    arg[1] = rb_ary_new3(1, INT2FIX(sig));
    arg[2] = (VALUE)safe;
    THREAD_COPY_STATUS(curr_thread, &save);
    rb_thread_ready(curr_thread);
    PUSH_ITER(ITER_NOT);
    val = rb_protect(run_trap_eval, (VALUE)&arg, &state);
    POP_ITER();
    THREAD_COPY_STATUS(&save, curr_thread);

    if (state) {
	rb_trap_immediate = 0;
	rb_thread_ready(curr_thread);
	JUMP_TAG(state);
    }

    if (curr_thread->status == THREAD_STOPPED) {
	rb_thread_schedule();
    }
    errno = EINTR;

    return val;
}

static const char *
thread_status_name(status)
    enum rb_thread_status status;
{
    switch (status) {
      case THREAD_RUNNABLE:
	return "run";
      case THREAD_STOPPED:
	return "sleep";
      case THREAD_TO_KILL:
	return "aborting";
      case THREAD_KILLED:
	return "dead";
      default:
	return "unknown";
    }
}

/* $SAFE accessor */
void
rb_set_safe_level(level)
    int level;
{
    if (level > ruby_safe_level) {
	if (level > SAFE_LEVEL_MAX) level = SAFE_LEVEL_MAX;
	ruby_safe_level = level;
	curr_thread->safe = level;
    }
}

static VALUE
safe_getter()
{
    return INT2NUM(ruby_safe_level);
}

static void
safe_setter(val)
    VALUE val;
{
    int level = NUM2INT(val);

    if (level < ruby_safe_level) {
	rb_raise(rb_eSecurityError, "tried to downgrade safe level from %d to %d",
		 ruby_safe_level, level);
    }
    if (level > SAFE_LEVEL_MAX) level = SAFE_LEVEL_MAX;
    ruby_safe_level = level;
    curr_thread->safe = level;
}

/* Return the current time as a floating-point number */
static double
timeofday()
{
    struct timeval tv;
#ifdef CLOCK_MONOTONIC
    struct timespec tp;

    if (clock_gettime(CLOCK_MONOTONIC, &tp) == 0) {
	return (double)tp.tv_sec + (double)tp.tv_nsec * 1e-9;
    }
#endif
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec * 1e-6;
}

#define STACK(addr) (th->stk_pos<(VALUE*)(addr) && (VALUE*)(addr)<th->stk_pos+th->stk_len)
#define ADJ(addr) (void*)(STACK(addr)?(((VALUE*)(addr)-th->stk_pos)+th->stk_ptr):(VALUE*)(addr))
static void
thread_mark(th)
    rb_thread_t th;
{
    struct FRAME *frame;
    struct BLOCK *block;

    rb_gc_mark(th->result);
    rb_gc_mark(th->thread);
    if (th->join) rb_gc_mark(th->join->thread);

    rb_gc_mark(th->klass);
    rb_gc_mark(th->wrapper);
    rb_gc_mark((VALUE)th->cref);

    rb_gc_mark((VALUE)th->scope);
    rb_gc_mark((VALUE)th->dyna_vars);
    rb_gc_mark(th->errinfo);
    rb_gc_mark(th->last_status);
    rb_gc_mark(th->last_line);
    rb_gc_mark(th->last_match);
    rb_mark_tbl(th->locals);
    rb_gc_mark(th->thgroup);
    rb_gc_mark_maybe(th->sandbox);

    /* mark data in copied stack */
    if (th == curr_thread) return;
    if (th->status == THREAD_KILLED) return;
    if (th->stk_len == 0) return;  /* stack not active, no need to mark. */
    if (th->stk_ptr) {
	rb_gc_mark_locations(th->stk_ptr, th->stk_ptr+th->stk_len);
#if defined(THINK_C) || defined(__human68k__)
	rb_gc_mark_locations(th->stk_ptr+2, th->stk_ptr+th->stk_len+2);
#endif
#ifdef __ia64
	if (th->bstr_ptr) {
            rb_gc_mark_locations(th->bstr_ptr, th->bstr_ptr+th->bstr_len);
	}
#endif
    }
    frame = th->frame;
    while (frame && frame != top_frame) {
	frame = ADJ(frame);
	rb_gc_mark_frame(frame);
	if (frame->tmp) {
	    struct FRAME *tmp = frame->tmp;

	    while (tmp && tmp != top_frame) {
		tmp = ADJ(tmp);
		rb_gc_mark_frame(tmp);
		tmp = tmp->prev;
	    }
	}
	frame = frame->prev;
    }
    block = th->block;
    while (block) {
	block = ADJ(block);
	rb_gc_mark_frame(&block->frame);
	block = block->prev;
    }
}

static struct {
    rb_thread_t thread;
    VALUE proc, arg;
} new_thread;

static int
mark_loading_thread(key, value, lev)
    ID key;
    VALUE value;
    int lev;
{
    rb_gc_mark(((rb_thread_t)value)->thread);
    return ST_CONTINUE;
}

void
rb_gc_mark_threads()
{
    rb_thread_t th;

    /* static global mark */
    rb_gc_mark((VALUE)ruby_cref);

    if (!curr_thread) return;
    rb_gc_mark(main_thread->thread);
    rb_gc_mark(curr_thread->thread);
    FOREACH_THREAD_FROM(main_thread, th) {
	switch (th->status) {
	  case THREAD_TO_KILL:
	  case THREAD_RUNNABLE:
	    break;
	  case THREAD_STOPPED:
	    if (th->wait_for) break;
	  default:
	    continue;
	}
	rb_gc_mark(th->thread);
    } END_FOREACH_FROM(main_thread, th);
    if (new_thread.thread) {
	rb_gc_mark(new_thread.thread->thread);
	rb_gc_mark(new_thread.proc);
	rb_gc_mark(new_thread.arg);
    }
    if (loading_tbl) st_foreach(loading_tbl, mark_loading_thread, 0);
}

void
rb_gc_abort_threads()
{
    rb_thread_t th;

    if (!main_thread)
        return;

    FOREACH_THREAD_FROM(main_thread, th) {
	if (FL_TEST(th->thread, FL_MARK)) continue;
	if (th->status == THREAD_STOPPED) {
	    th->status = THREAD_TO_KILL;
	    rb_gc_mark(th->thread);
	}
    } END_FOREACH_FROM(main_thread, th);
}

static void
thread_deliver_event(func, event)
    rb_event_hook_func_t func;
    rb_event_t event;
{
    rb_thread_t th;

    FOREACH_THREAD(th) {
	(*func)(event, 0, th->thread, 0, RBASIC(th->thread)->klass);
    } END_FOREACH(th);
}

static inline void
stack_free(th)
    rb_thread_t th;
{
    EXEC_EVENT_HOOK(RUBY_EVENT_THREAD_FREE, 0,
		    th->thread, 0, RBASIC(th->thread)->klass);

    if (th->stk_ptr) free(th->stk_ptr);
    th->stk_ptr = 0;
#ifdef __ia64
    if (th->bstr_ptr) free(th->bstr_ptr);
    th->bstr_ptr = 0;
#endif
}

static void
thread_free(th)
    rb_thread_t th;
{
    stack_free(th);
    if (th->locals) st_free_table(th->locals);
    if (th->status != THREAD_KILLED) {
	if (th->prev) th->prev->next = th->next;
	if (th->next) th->next->prev = th->prev;
    }
    if (th != main_thread) free(th);
}

static rb_thread_t
rb_thread_check(data)
    VALUE data;
{
    if (TYPE(data) != T_DATA || RDATA(data)->dmark != (RUBY_DATA_FUNC)thread_mark) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected Thread)",
		 rb_obj_classname(data));
    }
    return (rb_thread_t)RDATA(data)->data;
}

static VALUE rb_thread_raise _((int, VALUE*, rb_thread_t));

static VALUE th_raise_exception;
static NODE *th_raise_node;
static VALUE th_cmd;
static int   th_sig, th_safe;

#define RESTORE_NORMAL		1
#define RESTORE_FATAL		2
#define RESTORE_INTERRUPT	3
#define RESTORE_TRAP		4
#define RESTORE_RAISE		5
#define RESTORE_SIGNAL		6
#define RESTORE_EXIT		7

extern VALUE *rb_gc_stack_start;
#ifdef __ia64
extern VALUE *rb_gc_register_stack_start;
#endif

static void
rb_thread_save_context(th)
    rb_thread_t th;
{
    VALUE *pos;
    size_t len;
    static VALUE tval;

    EXEC_EVENT_HOOK(RUBY_EVENT_THREAD_SAVE, th->node,
		    th->thread, 0, RBASIC(th->thread)->klass);

    len = ruby_stack_length(&pos);
    th->stk_len = 0;
    th->stk_pos = pos;
    if (len > th->stk_max) {
	VALUE *ptr = realloc(th->stk_ptr, sizeof(VALUE) * len);
	if (!ptr) rb_memerror();
	th->stk_ptr = ptr;
	th->stk_max = len;
    }
    th->stk_len = len;
    FLUSH_REGISTER_WINDOWS;
    MEMCPY(th->stk_ptr, th->stk_pos, VALUE, th->stk_len);
#ifdef __ia64
    th->bstr_pos = rb_gc_register_stack_start;
    len = (VALUE*)rb_ia64_bsp() - th->bstr_pos;
    th->bstr_len = 0;
    if (len > th->bstr_max) {
        VALUE *ptr = realloc(th->bstr_ptr, sizeof(VALUE) * len);
        if (!ptr) rb_memerror();
        th->bstr_ptr = ptr;
        th->bstr_max = len;
    }
    th->bstr_len = len;
    rb_ia64_flushrs();
    MEMCPY(th->bstr_ptr, th->bstr_pos, VALUE, th->bstr_len);
#endif
#ifdef SAVE_WIN32_EXCEPTION_LIST
    th->win32_exception_list = win32_get_exception_list();
#endif

    th->frame = ruby_frame;
    th->scope = ruby_scope;
    ruby_scope->flags |= SCOPE_DONT_RECYCLE;
    th->klass = ruby_class;
    th->wrapper = ruby_wrapper;
    th->cref = ruby_cref;
    th->dyna_vars = ruby_dyna_vars;
    th->block = ruby_block;
    th->flags &= THREAD_FLAGS_MASK;
    th->flags |= (rb_trap_immediate<<8) | scope_vmode;
    th->iter = ruby_iter;
    th->tag = prot_tag;
    th->tracing = tracing;
    th->errinfo = ruby_errinfo;
    th->last_status = rb_last_status;
    tval = rb_lastline_get();
    rb_lastline_set(th->last_line);
    th->last_line = tval;
    tval = rb_backref_get();
    rb_backref_set(th->last_match);
    th->last_match = tval;
    th->safe = ruby_safe_level;

    th->node = ruby_current_node;
    if (ruby_sandbox_save != NULL) {
	ruby_sandbox_save(th);
    }
}

static int
rb_thread_switch(n)
    int n;
{
    rb_trap_immediate = (curr_thread->flags&0x100)?1:0;
    switch (n) {
      case 0:
	return 0;
      case RESTORE_FATAL:
	JUMP_TAG(TAG_FATAL);
	break;
      case RESTORE_INTERRUPT:
	rb_interrupt();
	break;
      case RESTORE_TRAP:
	rb_trap_eval(th_cmd, th_sig, th_safe);
	break;
      case RESTORE_RAISE:
	ruby_frame->last_func = 0;
	ruby_current_node = th_raise_node;
	rb_raise_jump(th_raise_exception);
	break;
      case RESTORE_SIGNAL:
	rb_thread_signal_raise(th_sig);
	break;
      case RESTORE_EXIT:
	ruby_errinfo = th_raise_exception;
	ruby_current_node = th_raise_node;
	if (!rb_obj_is_kind_of(ruby_errinfo, rb_eSystemExit)) {
	    terminate_process(EXIT_FAILURE, ruby_errinfo);
	}
	rb_exc_raise(th_raise_exception);
	break;
      case RESTORE_NORMAL:
      default:
	break;
    }
    return 1;
}

#define THREAD_SAVE_CONTEXT(th) \
    (rb_thread_switch(ruby_setjmp(rb_thread_save_context(th), (th)->context)))

NORETURN(static void rb_thread_restore_context _((rb_thread_t,int)));
NORETURN(NOINLINE(static void rb_thread_restore_context_0(rb_thread_t,int)));
NORETURN(NOINLINE(static void stack_extend(rb_thread_t, int)));

static void
rb_thread_restore_context_0(rb_thread_t th, int exit)
{
    static rb_thread_t tmp;
    static int ex;
    static VALUE tval;

    rb_trap_immediate = 0;	/* inhibit interrupts from here */
    if (ruby_sandbox_restore != NULL) {
	ruby_sandbox_restore(th);
    }
    ruby_frame = th->frame;
    ruby_scope = th->scope;
    ruby_class = th->klass;
    ruby_wrapper = th->wrapper;
    ruby_cref = th->cref;
    ruby_dyna_vars = th->dyna_vars;
    ruby_block = th->block;
    scope_vmode = th->flags&SCOPE_MASK;
    ruby_iter = th->iter;
    prot_tag = th->tag;
    tracing = th->tracing;
    ruby_errinfo = th->errinfo;
    rb_last_status = th->last_status;
    ruby_safe_level = th->safe;

    ruby_current_node = th->node;

#ifdef SAVE_WIN32_EXCEPTION_LIST
    win32_set_exception_list(th->win32_exception_list);
#endif
    tmp = th;
    ex = exit;
    FLUSH_REGISTER_WINDOWS;
    MEMCPY(tmp->stk_pos, tmp->stk_ptr, VALUE, tmp->stk_len);
#ifdef __ia64
    MEMCPY(tmp->bstr_pos, tmp->bstr_ptr, VALUE, tmp->bstr_len);
#endif

    tval = rb_lastline_get();
    rb_lastline_set(tmp->last_line);
    tmp->last_line = tval;
    tval = rb_backref_get();
    rb_backref_set(tmp->last_match);
    tmp->last_match = tval;

    ruby_longjmp(tmp->context, ex);
}

#ifdef __ia64
#define C(a) rse_##a##0, rse_##a##1, rse_##a##2, rse_##a##3, rse_##a##4
#define E(a) rse_##a##0= rse_##a##1= rse_##a##2= rse_##a##3= rse_##a##4
static volatile int C(a), C(b), C(c), C(d), C(e);
static volatile int C(f), C(g), C(h), C(i), C(j);
static volatile int C(k), C(l), C(m), C(n), C(o);
static volatile int C(p), C(q), C(r), C(s), C(t);
int rb_dummy_false = 0;
NORETURN(NOINLINE(static void register_stack_extend(rb_thread_t, int, VALUE *)));
static void
register_stack_extend(rb_thread_t th, int exit, VALUE *curr_bsp)
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
    if (curr_bsp < th->bstr_pos+th->bstr_len) {
        register_stack_extend(th, exit, (VALUE*)rb_ia64_bsp());
    }
    stack_extend(th, exit);
}
#undef C
#undef E
#endif

static void
stack_extend(rb_thread_t th, int exit)
{
#define STACK_PAD_SIZE 1024
    volatile VALUE space[STACK_PAD_SIZE];
#ifdef HAVE_ALLOCA
    volatile VALUE *sp = space;
#endif

#if !STACK_GROW_DIRECTION
    if (space < rb_gc_stack_start) {
        /* Stack grows downward */
#endif
#if STACK_GROW_DIRECTION <= 0
	if (space > th->stk_pos) {
# ifdef HAVE_ALLOCA
	    sp = ALLOCA_N(VALUE, &space[0] - th->stk_pos);
# else
	    stack_extend(th, exit);
# endif
	}
#endif
#if !STACK_GROW_DIRECTION
    }
    else {
        /* Stack grows upward */
#endif
#if STACK_GROW_DIRECTION >= 0
	if (&space[STACK_PAD_SIZE] < th->stk_pos + th->stk_len) {
# ifdef HAVE_ALLOCA
	    sp = ALLOCA_N(VALUE, th->stk_pos + th->stk_len - &space[STACK_PAD_SIZE]);
# else
	    stack_extend(th, exit);
# endif
	}
#endif
#if !STACK_GROW_DIRECTION
    }
#endif
    rb_thread_restore_context_0(th, exit);
}
#ifdef __ia64
#define stack_extend(th, exit) register_stack_extend(th, exit, (VALUE*)rb_ia64_bsp())
#endif

static void
rb_thread_restore_context(th, exit)
    rb_thread_t th;
    int exit;
{
    if (!th->stk_ptr) rb_bug("unsaved context");
    EXEC_EVENT_HOOK(RUBY_EVENT_THREAD_RESTORE, th->node,
		    th->thread, 0, RBASIC(th->thread)->klass);
    stack_extend(th, exit);
}

static void
rb_thread_ready(th)
    rb_thread_t th;
{
    th->wait_for = 0;
    if (th->status != THREAD_TO_KILL) {
	th->status = THREAD_RUNNABLE;
    }
}

static void
rb_thread_die(th)
    rb_thread_t th;
{
    th->thgroup = 0;
    th->status = THREAD_KILLED;
    stack_free(th);
}

static void
rb_thread_remove(th)
    rb_thread_t th;
{
    if (th->status == THREAD_KILLED) return;

    rb_thread_ready(th);
    rb_thread_die(th);
    th->prev->next = th->next;
    th->next->prev = th->prev;

#if defined(_THREAD_SAFE) || defined(HAVE_SETITIMER)
    /* if this is the last ruby thread, stop timer signals */
    if (th->next == th->prev && th->next == main_thread) {
	rb_thread_stop_timer();
    }
#endif
}

static int
rb_thread_dead(th)
    rb_thread_t th;
{
    return th->status == THREAD_KILLED;
}

void
rb_thread_fd_close(fd)
    int fd;
{
    rb_thread_t th;

    FOREACH_THREAD(th) {
	if (((th->wait_for & WAIT_FD) && fd == th->fd) ||
	    ((th->wait_for & WAIT_SELECT) && (fd < th->fd) &&
	     (FD_ISSET(fd, &th->readfds) ||
	      FD_ISSET(fd, &th->writefds) ||
	      FD_ISSET(fd, &th->exceptfds)))) {
	    VALUE exc = rb_exc_new2(rb_eIOError, "stream closed");
	    rb_thread_raise(1, &exc, th);
	}
    }
    END_FOREACH(th);
}

NORETURN(static void rb_thread_main_jump _((VALUE, int)));
static void
rb_thread_main_jump(err, tag)
    VALUE err;
    int tag;
{
    curr_thread = main_thread;
    th_raise_exception = err;
    th_raise_node = ruby_current_node;
    rb_thread_restore_context(main_thread, tag);
}

NORETURN(static void rb_thread_deadlock _((void)));
static void
rb_thread_deadlock()
{
    char msg[21+SIZEOF_LONG*2];
    VALUE e;

    sprintf(msg, "Thread(0x%lx): deadlock", curr_thread->thread);
    e = rb_exc_new2(rb_eFatal, msg);
    if (curr_thread == main_thread) {
	rb_exc_raise(e);
    }
    rb_thread_main_jump(e, RESTORE_RAISE);
}

static void
copy_fds(dst, src, max)
    fd_set *dst, *src;
    int max;
{
    int n = 0;
    int i;

    for (i=0; i<=max; i++) {
	if (FD_ISSET(i, src)) {
	    n = i;
	    FD_SET(i, dst);
	}
    }
}

static int
match_fds(dst, src, max)
    fd_set *dst, *src;
    int max;
{
    int i;

    for (i=0; i<=max; i++) {
	if (FD_ISSET(i, src) && FD_ISSET(i, dst)) {
	    return Qtrue;
	}
    }
    return Qfalse;
}

static int
intersect_fds(src, dst, max)
    fd_set *src, *dst;
    int max;
{
    int i, n = 0;

    for (i=0; i<=max; i++) {
	if (FD_ISSET(i, dst)) {
	    if (FD_ISSET(i, src)) {
		/* Wake up only one thread per fd. */
		FD_CLR(i, src);
		n++;
	    }
	    else {
		FD_CLR(i, dst);
	    }
	}
    }
    return n;
}

static int
find_bad_fds(dst, src, max)
    fd_set *dst, *src;
    int max;
{
    int i, test = Qfalse;

    for (i=0; i<=max; i++) {
	if (FD_ISSET(i, src) && !FD_ISSET(i, dst)) {
	    FD_CLR(i, src);
	    test = Qtrue;
	}
    }
    return test;
}

void
rb_thread_schedule()
{
    rb_thread_t next;		/* OK */
    rb_thread_t th;
    rb_thread_t curr;
    int found = 0;

    fd_set readfds;
    fd_set writefds;
    fd_set exceptfds;
    struct timeval delay_tv, *delay_ptr;
    double delay, now;	/* OK */
    int n, max;
    int need_select = 0;
    int select_timeout = 0;

#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
	rb_bug("cross-thread violation on rb_thread_schedule()");
    }
#endif
    rb_thread_pending = 0;
    rb_gc_finalize_deferred();
    if (curr_thread == curr_thread->next
	&& curr_thread->status == THREAD_RUNNABLE)
	return;

    next = 0;
    curr = curr_thread;		/* starting thread */

    while (curr->status == THREAD_KILLED) {
	curr = curr->prev;
    }

  again:
    max = -1;
    FD_ZERO(&readfds);
    FD_ZERO(&writefds);
    FD_ZERO(&exceptfds);
    delay = DELAY_INFTY;
    now = -1.0;

    FOREACH_THREAD_FROM(curr, th) {
        th->wait_for &= ~WAIT_DONE;
	if (!found && th->status <= THREAD_RUNNABLE) {
	    found = 1;
	}
	if (th->status != THREAD_STOPPED) continue;
	if (th->wait_for & WAIT_JOIN) {
	    if (rb_thread_dead(th->join)) {
		th->status = THREAD_RUNNABLE;
		found = 1;
	    }
	}
	if (th->wait_for & WAIT_FD) {
	    FD_SET(th->fd, &readfds);
	    if (max < th->fd) max = th->fd;
	    need_select = 1;
	}
	if (th->wait_for & WAIT_SELECT) {
	    copy_fds(&readfds, &th->readfds, th->fd);
	    copy_fds(&writefds, &th->writefds, th->fd);
	    copy_fds(&exceptfds, &th->exceptfds, th->fd);
	    if (max < th->fd) max = th->fd;
	    need_select = 1;
	    if (th->wait_for & WAIT_TIME) {
		select_timeout = 1;
	    }
	    th->select_value = 0;
	}
	if (th->wait_for & WAIT_TIME) {
	    double th_delay;

	    if (now < 0.0) now = timeofday();
	    th_delay = th->delay - now;
	    if (th_delay <= 0.0) {
                if (th->wait_for & WAIT_SELECT) {
                    need_select = 1;
                }
                else {
                    th->status = THREAD_RUNNABLE;
                }
		found = 1;
	    }
	    else if (th_delay < delay) {
		delay = th_delay;
		need_select = 1;
	    }
	    else if (th->delay == DELAY_INFTY) {
		need_select = 1;
	    }
	}
    }
    END_FOREACH_FROM(curr, th);

    /* Do the select if needed */
    if (need_select) {
	/* Convert delay to a timeval */
	/* If a thread is runnable, just poll */
	if (found) {
	    delay_tv.tv_sec = 0;
	    delay_tv.tv_usec = 0;
	    delay_ptr = &delay_tv;
	}
	else if (delay == DELAY_INFTY) {
	    delay_ptr = 0;
	}
	else {
	    delay_tv.tv_sec = delay;
	    delay_tv.tv_usec = (delay - (double)delay_tv.tv_sec)*1e6;
	    delay_ptr = &delay_tv;
	}

	n = select(max+1, &readfds, &writefds, &exceptfds, delay_ptr);
	if (n < 0) {
	    int e = errno;

	    if (rb_trap_pending) rb_trap_exec();
	    if (e == EINTR) goto again;
#ifdef ERESTART
	    if (e == ERESTART) goto again;
#endif
            if (e == EBADF) {
                int badfd = -1;
                int fd;
#ifndef _WIN32
                int dummy;
#endif
                for (fd = 0; fd <= max; fd++) {
                    if ((FD_ISSET(fd, &readfds) ||
                         FD_ISSET(fd, &writefds) ||
                         FD_ISSET(fd, &exceptfds)) &&
#ifndef _WIN32
                        fcntl(fd, F_GETFD, &dummy) == -1 &&
#else
			rb_w32_get_osfhandle(fd) == -1 &&
#endif
                        errno == EBADF) {
                        badfd = fd;
                        break;
                    }
                }
                if (badfd != -1) {
                    FOREACH_THREAD_FROM(curr, th) {
                        if (th->wait_for & WAIT_FD) {
                            if (th->fd == badfd) {
                                found = 1;
                                th->status = THREAD_RUNNABLE;
                                th->fd = 0;
                                break;
                            }
                        }
                        if (th->wait_for & WAIT_SELECT) {
                            if (FD_ISSET(badfd, &th->readfds) ||
                                FD_ISSET(badfd, &th->writefds) ||
                                FD_ISSET(badfd, &th->exceptfds)) {
                                found = 1;
                                th->status = THREAD_RUNNABLE;
                                th->select_value = -EBADF;
                                break;
                            }
                        }
                    }
                    END_FOREACH_FROM(curr, th);
                }
            }
            else {
                FOREACH_THREAD_FROM(curr, th) {
                    if (th->wait_for & WAIT_SELECT) {
                        int v = 0;

                        v |= find_bad_fds(&readfds, &th->readfds, th->fd);
                        v |= find_bad_fds(&writefds, &th->writefds, th->fd);
                        v |= find_bad_fds(&exceptfds, &th->exceptfds, th->fd);
                        if (v) {
                            th->select_value = n;
                            n = max;
                        }
                    }
                }
                END_FOREACH_FROM(curr, th);
            }
	}
 	if (select_timeout && n == 0) {
 	    if (now < 0.0) now = timeofday();
 	    FOREACH_THREAD_FROM(curr, th) {
 		if (((th->wait_for&(WAIT_SELECT|WAIT_TIME)) == (WAIT_SELECT|WAIT_TIME)) &&
		    th->delay <= now) {
 		    th->status = THREAD_RUNNABLE;
 		    th->wait_for = 0;
 		    th->select_value = 0;
 		    found = 1;
		    intersect_fds(&readfds, &th->readfds, max);
		    intersect_fds(&writefds, &th->writefds, max);
		    intersect_fds(&exceptfds, &th->exceptfds, max);
		}
	    }
	    END_FOREACH_FROM(curr, th);
	}
	if (n > 0) {
	    now = -1.0;
	    /* Some descriptors are ready.
             * The corresponding threads are runnable as next.
             * Mark them with WAIT_DONE.
             * Don't change the status to runnable here because
             * threads which don't run next should not be changed.
             */
	    FOREACH_THREAD_FROM(curr, th) {
		if ((th->wait_for&WAIT_FD) && FD_ISSET(th->fd, &readfds)) {
                    th->wait_for |= WAIT_DONE;
		    found = 1;
		}
		if ((th->wait_for&WAIT_SELECT) &&
		    (match_fds(&readfds, &th->readfds, max) ||
		     match_fds(&writefds, &th->writefds, max) ||
		     match_fds(&exceptfds, &th->exceptfds, max))) {
                    th->wait_for |= WAIT_DONE;
                    found = 1;
		}
	    }
	    END_FOREACH_FROM(curr, th);
	}
	/* The delays for some of the threads should have expired.
	   Go through the loop once more, to check the delays. */
	if (!found && delay != DELAY_INFTY)
	    goto again;
    }

    FOREACH_THREAD_FROM(curr, th) {
	if (th->status == THREAD_TO_KILL) {
	    next = th;
	    break;
	}
	if ((th->status == THREAD_RUNNABLE || (th->wait_for & WAIT_DONE)) && th->stk_ptr) {
	    if (!next || next->priority < th->priority) {
	        next = th;
            }
	}
    }
    END_FOREACH_FROM(curr, th);

    if (next && (next->wait_for & WAIT_DONE)) {
        next->status = THREAD_RUNNABLE;
        if (next->wait_for&WAIT_FD) {
            next->fd = 0;
        }
        else { /* next->wait_for&WAIT_SELECT */
            n = intersect_fds(&readfds, &next->readfds, max) +
                intersect_fds(&writefds, &next->writefds, max) +
                intersect_fds(&exceptfds, &next->exceptfds, max);
            next->select_value = n;
        }
        next->wait_for = 0;
    }

    if (!next) {
	/* raise fatal error to main thread */
	curr_thread->node = ruby_current_node;
	if (curr->next == curr) {
	    TRAP_BEG;
	    pause();
	    TRAP_END;
	}
	FOREACH_THREAD_FROM(curr, th) {
            int wait_for = th->wait_for & ~WAIT_DONE;
	    warn_printf("deadlock 0x%lx: %s:",
			th->thread, thread_status_name(th->status));
	    if (wait_for & WAIT_FD) warn_printf("F(%d)", th->fd);
	    if (wait_for & WAIT_SELECT) warn_printf("S");
	    if (wait_for & WAIT_TIME) warn_printf("T(%f)", th->delay);
	    if (wait_for & WAIT_JOIN)
		warn_printf("J(0x%lx)", th->join ? th->join->thread : 0);
	    if (wait_for & WAIT_PID) warn_printf("P");
	    if (!wait_for) warn_printf("-");
	    warn_printf(" %s - %s:%d\n",
			th==main_thread ? "(main)" : "",
			th->node->nd_file, nd_line(th->node));
	}
	END_FOREACH_FROM(curr, th);
	next = main_thread;
	rb_thread_ready(next);
	next->status = THREAD_TO_KILL;
	if (!rb_thread_dead(curr_thread)) {
	    rb_thread_save_context(curr_thread);
	}
	rb_thread_deadlock();
    }
    next->wait_for = 0;
    if (next->status == THREAD_RUNNABLE && next == curr_thread) {
	return;
    }

    /* context switch */
    if (curr == curr_thread) {
	if (THREAD_SAVE_CONTEXT(curr)) {
	    return;
	}
    }

    curr_thread = next;
    if (next->status == THREAD_TO_KILL) {
	if (!(next->flags & THREAD_TERMINATING)) {
	    next->flags |= THREAD_TERMINATING;
	    /* terminate; execute ensure-clause if any */
	    rb_thread_restore_context(next, RESTORE_FATAL);
	}
    }
    rb_thread_restore_context(next, RESTORE_NORMAL);
}

void
rb_thread_wait_fd(fd)
    int fd;
{
    if (rb_thread_critical) return;
    if (ruby_in_compile) return;
    if (curr_thread == curr_thread->next) return;
    if (curr_thread->status == THREAD_TO_KILL) return;

    curr_thread->status = THREAD_STOPPED;
    curr_thread->fd = fd;
    curr_thread->wait_for = WAIT_FD;
    rb_thread_schedule();
}

int
rb_thread_fd_writable(fd)
    int fd;
{
    if (rb_thread_critical) return Qtrue;
    if (curr_thread == curr_thread->next) return Qtrue;
    if (curr_thread->status == THREAD_TO_KILL) return Qtrue;
    if (curr_thread->status == THREAD_KILLED) return Qtrue;

    curr_thread->status = THREAD_STOPPED;
    FD_ZERO(&curr_thread->readfds);
    FD_ZERO(&curr_thread->writefds);
    FD_SET(fd, &curr_thread->writefds);
    FD_ZERO(&curr_thread->exceptfds);
    curr_thread->fd = fd+1;
    curr_thread->wait_for = WAIT_SELECT;
    rb_thread_schedule();
    return Qfalse;
}

void
rb_thread_wait_for(time)
    struct timeval time;
{
    double date;

    if (rb_thread_critical ||
	curr_thread == curr_thread->next ||
	curr_thread->status == THREAD_TO_KILL) {
	int n;
	int thr_critical = rb_thread_critical;
#ifndef linux
	double d, limit;
	limit = timeofday()+(double)time.tv_sec+(double)time.tv_usec*1e-6;
#endif
	for (;;) {
	    rb_thread_critical = Qtrue;
	    TRAP_BEG;
	    n = select(0, 0, 0, 0, &time);
	    rb_thread_critical = thr_critical;
	    TRAP_END;
	    if (n == 0) return;
	    if (n < 0) {
		switch (errno) {
		  case EINTR:
#ifdef ERESTART
		  case ERESTART:
#endif
		    break;
		  default:
		    rb_sys_fail("sleep");
		}
	    }
#ifndef linux
	    d = limit - timeofday();

	    time.tv_sec = (int)d;
	    time.tv_usec = (int)((d - (int)d)*1e6);
	    if (time.tv_usec < 0) {
		time.tv_usec += (long)1e6;
		time.tv_sec -= 1;
	    }
	    if (time.tv_sec < 0) return;
#endif
	}
    }

    date = timeofday() + (double)time.tv_sec + (double)time.tv_usec*1e-6;
    curr_thread->status = THREAD_STOPPED;
    curr_thread->delay = date;
    curr_thread->wait_for = WAIT_TIME;
    rb_thread_schedule();
}

void rb_thread_sleep_forever _((void));

int
rb_thread_alone()
{
    return curr_thread == curr_thread->next;
}

int
rb_thread_select(max, read, write, except, timeout)
    int max;
    fd_set *read, *write, *except;
    struct timeval *timeout;
{
#ifndef linux
    double limit = 0;
#endif
    int n;

    if (!read && !write && !except) {
	if (!timeout) {
	    rb_thread_sleep_forever();
	    return 0;
	}
	rb_thread_wait_for(*timeout);
	return 0;
    }

#ifndef linux
    if (timeout) {
	limit = timeofday()+
	    (double)timeout->tv_sec+(double)timeout->tv_usec*1e-6;
    }
#endif

    if (rb_thread_critical ||
	curr_thread == curr_thread->next ||
	curr_thread->status == THREAD_TO_KILL) {
#ifndef linux
	struct timeval tv, *tvp = timeout;

	if (timeout) {
	    tv = *timeout;
	    tvp = &tv;
	}
#else
	struct timeval *const tvp = timeout;
#endif
	for (;;) {
	    TRAP_BEG;
	    n = select(max, read, write, except, tvp);
	    TRAP_END;
	    if (n < 0) {
		switch (errno) {
		  case EINTR:
#ifdef ERESTART
		  case ERESTART:
#endif
#ifndef linux
		    if (timeout) {
			double d = limit - timeofday();

			tv.tv_sec = (unsigned int)d;
			tv.tv_usec = (long)((d-(double)tv.tv_sec)*1e6);
			if (tv.tv_sec < 0)  tv.tv_sec = 0;
			if (tv.tv_usec < 0) tv.tv_usec = 0;
		    }
#endif
		    continue;
		  default:
		    break;
		}
	    }
	    return n;
	}
    }

    curr_thread->status = THREAD_STOPPED;
    if (read) curr_thread->readfds = *read;
    else FD_ZERO(&curr_thread->readfds);
    if (write) curr_thread->writefds = *write;
    else FD_ZERO(&curr_thread->writefds);
    if (except) curr_thread->exceptfds = *except;
    else FD_ZERO(&curr_thread->exceptfds);
    curr_thread->fd = max;
    curr_thread->wait_for = WAIT_SELECT;
    if (timeout) {
	curr_thread->delay = timeofday() +
	    (double)timeout->tv_sec + (double)timeout->tv_usec*1e-6;
	curr_thread->wait_for |= WAIT_TIME;
    }
    rb_thread_schedule();
    if (read) *read = curr_thread->readfds;
    if (write) *write = curr_thread->writefds;
    if (except) *except = curr_thread->exceptfds;
    if (curr_thread->select_value < 0) {
        errno = -curr_thread->select_value;
        return -1;
    }
    return curr_thread->select_value;
}

static int rb_thread_join0 _((rb_thread_t, double));

static int
rb_thread_join0(th, limit)
    rb_thread_t th;
    double limit;
{
    enum rb_thread_status last_status = THREAD_RUNNABLE;

    if (rb_thread_critical) rb_thread_deadlock();
    if (!rb_thread_dead(th)) {
	if (th == curr_thread)
	    rb_raise(rb_eThreadError, "thread 0x%lx tried to join itself",
		     th->thread);
	if ((th->wait_for & WAIT_JOIN) && th->join == curr_thread)
	    rb_raise(rb_eThreadError, "Thread#join: deadlock 0x%lx - mutual join(0x%lx)",
		     curr_thread->thread, th->thread);
	if (curr_thread->status == THREAD_TO_KILL)
	    last_status = THREAD_TO_KILL;
	if (limit == 0) return Qfalse;
	curr_thread->status = THREAD_STOPPED;
	curr_thread->join = th;
	curr_thread->wait_for = WAIT_JOIN;
	curr_thread->delay = timeofday() + limit;
	if (limit < DELAY_INFTY) curr_thread->wait_for |= WAIT_TIME;
	rb_thread_schedule();
	curr_thread->status = last_status;
	if (!rb_thread_dead(th)) return Qfalse;
    }

    if (!NIL_P(th->errinfo) && (th->flags & RAISED_EXCEPTION)) {
	VALUE oldbt = get_backtrace(th->errinfo);
	VALUE errat = make_backtrace();
	VALUE errinfo = rb_obj_dup(th->errinfo);

	if (TYPE(oldbt) == T_ARRAY && RARRAY(oldbt)->len > 0) {
	    rb_ary_unshift(errat, rb_ary_entry(oldbt, 0));
	}
	set_backtrace(errinfo, errat);
	rb_exc_raise(errinfo);
    }

    return Qtrue;
}

int
rb_thread_join(thread, limit)
    VALUE thread;
    double limit;
{
    if (limit < 0) limit = DELAY_INFTY;
    return rb_thread_join0(rb_thread_check(thread), limit);
}

void
rb_thread_set_join(thread, join)
    VALUE thread, join;
{
    rb_thread_t th = rb_thread_check(thread);
    rb_thread_t jth = rb_thread_check(join);
    th->wait_for = WAIT_JOIN;
    th->join = jth;
}


/*
 *  call-seq:
 *     thr.join          => thr
 *     thr.join(limit)   => thr
 *
 *  The calling thread will suspend execution and run <i>thr</i>. Does not
 *  return until <i>thr</i> exits or until <i>limit</i> seconds have passed. If
 *  the time limit expires, <code>nil</code> will be returned, otherwise
 *  <i>thr</i> is returned.
 *
 *  Any threads not joined will be killed when the main program exits.  If
 *  <i>thr</i> had previously raised an exception and the
 *  <code>abort_on_exception</code> and <code>$DEBUG</code> flags are not set
 *  (so the exception has not yet been processed) it will be processed at this
 *  time.
 *
 *     a = Thread.new { print "a"; sleep(10); print "b"; print "c" }
 *     x = Thread.new { print "x"; Thread.pass; print "y"; print "z" }
 *     x.join # Let x thread finish, a will be killed on exit.
 *
 *  <em>produces:</em>
 *
 *     axyz
 *
 *  The following example illustrates the <i>limit</i> parameter.
 *
 *     y = Thread.new { 4.times { sleep 0.1; puts 'tick... ' }}
 *     puts "Waiting" until y.join(0.15)
 *
 *  <em>produces:</em>
 *
 *     tick...
 *     Waiting
 *     tick...
 *     Waitingtick...
 *
 *
 *     tick...
 */

static VALUE
rb_thread_join_m(argc, argv, thread)
    int argc;
    VALUE *argv;
    VALUE thread;
{
    VALUE limit;
    double delay = DELAY_INFTY;

    rb_scan_args(argc, argv, "01", &limit);
    if (!NIL_P(limit)) delay = rb_num2dbl(limit);
    if (!rb_thread_join0(rb_thread_check(thread), delay))
	return Qnil;
    return thread;
}


/*
 *  call-seq:
 *     Thread.current   => thread
 *
 *  Returns the currently executing thread.
 *
 *     Thread.current   #=> #<Thread:0x401bdf4c run>
 */

VALUE
rb_thread_current()
{
    return curr_thread->thread;
}


/*
 *  call-seq:
 *     Thread.main   => thread
 *
 *  Returns the main thread for the process.
 *
 *     Thread.main   #=> #<Thread:0x401bdf4c run>
 */

VALUE
rb_thread_main()
{
    return main_thread->thread;
}


/*
 *  call-seq:
 *     Thread.list   => array
 *
 *  Returns an array of <code>Thread</code> objects for all threads that are
 *  either runnable or stopped.
 *
 *     Thread.new { sleep(200) }
 *     Thread.new { 1000000.times {|i| i*i } }
 *     Thread.new { Thread.stop }
 *     Thread.list.each {|t| p t}
 *
 *  <em>produces:</em>
 *
 *     #<Thread:0x401b3e84 sleep>
 *     #<Thread:0x401b3f38 run>
 *     #<Thread:0x401b3fb0 sleep>
 *     #<Thread:0x401bdf4c run>
 */

VALUE
rb_thread_list()
{
    rb_thread_t th;
    VALUE ary = rb_ary_new();

    FOREACH_THREAD(th) {
	switch (th->status) {
	  case THREAD_RUNNABLE:
	  case THREAD_STOPPED:
	  case THREAD_TO_KILL:
	    rb_ary_push(ary, th->thread);
	  default:
	    break;
	}
    }
    END_FOREACH(th);

    return ary;
}


/*
 *  call-seq:
 *     thr.wakeup   => thr
 *
 *  Marks <i>thr</i> as eligible for scheduling (it may still remain blocked on
 *  I/O, however). Does not invoke the scheduler (see <code>Thread#run</code>).
 *
 *     c = Thread.new { Thread.stop; puts "hey!" }
 *     c.wakeup
 *
 *  <em>produces:</em>
 *
 *     hey!
 */

VALUE
rb_thread_wakeup(thread)
    VALUE thread;
{
    if (!RTEST(rb_thread_wakeup_alive(thread)))
	rb_raise(rb_eThreadError, "killed thread");
    return thread;
}

VALUE
rb_thread_wakeup_alive(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (th->status == THREAD_KILLED)
	return Qnil;
    rb_thread_ready(th);

    return thread;
}


/*
 *  call-seq:
 *     thr.run   => thr
 *
 *  Wakes up <i>thr</i>, making it eligible for scheduling. If not in a critical
 *  section, then invokes the scheduler.
 *
 *     a = Thread.new { puts "a"; Thread.stop; puts "c" }
 *     Thread.pass
 *     puts "Got here"
 *     a.run
 *     a.join
 *
 *  <em>produces:</em>
 *
 *     a
 *     Got here
 *     c
 */

VALUE
rb_thread_run(thread)
    VALUE thread;
{
    rb_thread_wakeup(thread);
    if (!rb_thread_critical) rb_thread_schedule();

    return thread;
}


static void
rb_kill_thread(th, flags)
    rb_thread_t th;
    int flags;
{
    if (th != curr_thread && th->safe < 4) {
	rb_secure(4);
    }
    if (th->status == THREAD_TO_KILL || th->status == THREAD_KILLED)
	return;
    if (th == th->next || th == main_thread) rb_exit(EXIT_SUCCESS);

    rb_thread_ready(th);
    th->flags |= flags;
    th->status = THREAD_TO_KILL;
    if (!rb_thread_critical) rb_thread_schedule();
}


/*
 *  call-seq:
 *     thr.exit        => thr
 *     thr.kill        => thr
 *     thr.terminate   => thr
 *
 *  Terminates <i>thr</i> and schedules another thread to be run, returning
 *  the terminated <code>Thread</code>.  If this is the main thread, or the
 *  last thread, exits the process.
 */

VALUE
rb_thread_kill(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    rb_kill_thread(th, 0);
    return thread;
}


/*
 *  call-seq:
 *     thr.exit!        => thr
 *     thr.kill!        => thr
 *     thr.terminate!   => thr
 *
 *  Terminates <i>thr</i> without calling ensure clauses and schedules
 *  another thread to be run, returning the terminated <code>Thread</code>.
 *  If this is the main thread, or the last thread, exits the process.
 *
 *  See <code>Thread#exit</code> for the safer version.
 */

static VALUE
rb_thread_kill_bang(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);
    rb_kill_thread(th, THREAD_NO_ENSURE);
    return thread;
}

/*
 *  call-seq:
 *     Thread.kill(thread)   => thread
 *
 *  Causes the given <em>thread</em> to exit (see <code>Thread::exit</code>).
 *
 *     count = 0
 *     a = Thread.new { loop { count += 1 } }
 *     sleep(0.1)       #=> 0
 *     Thread.kill(a)   #=> #<Thread:0x401b3d30 dead>
 *     count            #=> 93947
 *     a.alive?         #=> false
 */

static VALUE
rb_thread_s_kill(obj, th)
    VALUE obj, th;
{
    return rb_thread_kill(th);
}


/*
 *  call-seq:
 *     Thread.exit   => thread
 *
 *  Terminates the currently running thread and schedules another thread to be
 *  run. If this thread is already marked to be killed, <code>exit</code>
 *  returns the <code>Thread</code>. If this is the main thread, or the last
 *  thread, exit the process.
 */

static VALUE
rb_thread_exit()
{
    return rb_thread_kill(curr_thread->thread);
}


/*
 *  call-seq:
 *     Thread.pass   => nil
 *
 *  Invokes the thread scheduler to pass execution to another thread.
 *
 *     a = Thread.new { print "a"; Thread.pass;
 *                      print "b"; Thread.pass;
 *                      print "c" }
 *     b = Thread.new { print "x"; Thread.pass;
 *                      print "y"; Thread.pass;
 *                      print "z" }
 *     a.join
 *     b.join
 *
 *  <em>produces:</em>
 *
 *     axbycz
 */

static VALUE
rb_thread_pass()
{
    rb_thread_schedule();
    return Qnil;
}


/*
 *  call-seq:
 *     Thread.stop   => nil
 *
 *  Stops execution of the current thread, putting it into a ``sleep'' state,
 *  and schedules execution of another thread. Resets the ``critical'' condition
 *  to <code>false</code>.
 *
 *     a = Thread.new { print "a"; Thread.stop; print "c" }
 *     Thread.pass
 *     print "b"
 *     a.run
 *     a.join
 *
 *  <em>produces:</em>
 *
 *     abc
 */

VALUE
rb_thread_stop()
{
    enum rb_thread_status last_status = THREAD_RUNNABLE;

    rb_thread_critical = 0;
    if (curr_thread == curr_thread->next) {
	rb_raise(rb_eThreadError, "stopping only thread\n\tnote: use sleep to stop forever");
    }
    if (curr_thread->status == THREAD_TO_KILL)
	last_status = THREAD_TO_KILL;
    curr_thread->status = THREAD_STOPPED;
    rb_thread_schedule();
    curr_thread->status = last_status;

    return Qnil;
}

struct timeval rb_time_timeval();

void
rb_thread_polling()
{
    if (curr_thread != curr_thread->next) {
	curr_thread->status = THREAD_STOPPED;
	curr_thread->delay = timeofday() + (double)0.06;
	curr_thread->wait_for = WAIT_TIME;
	rb_thread_schedule();
    }
}

void
rb_thread_sleep(sec)
    int sec;
{
    if (curr_thread == curr_thread->next) {
	TRAP_BEG;
	sleep(sec);
	TRAP_END;
	return;
    }
    rb_thread_wait_for(rb_time_timeval(INT2FIX(sec)));
}

void
rb_thread_sleep_forever()
{
    int thr_critical = rb_thread_critical;
    if (curr_thread == curr_thread->next ||
	curr_thread->status == THREAD_TO_KILL) {
	rb_thread_critical = Qtrue;
	TRAP_BEG;
	pause();
	rb_thread_critical = thr_critical;
	TRAP_END;
	return;
    }

    curr_thread->delay = DELAY_INFTY;
    curr_thread->wait_for = WAIT_TIME;
    curr_thread->status = THREAD_STOPPED;
    rb_thread_schedule();
}


/*
 *  call-seq:
 *     thr.priority   => integer
 *
 *  Returns the priority of <i>thr</i>. Default is inherited from the
 *  current thread which creating the new thread, or zero for the
 *  initial main thread; higher-priority threads will run before
 *  lower-priority threads.
 *
 *     Thread.current.priority   #=> 0
 */

static VALUE
rb_thread_priority(thread)
    VALUE thread;
{
    return INT2NUM(rb_thread_check(thread)->priority);
}


/*
 *  call-seq:
 *     thr.priority= integer   => thr
 *
 *  Sets the priority of <i>thr</i> to <i>integer</i>. Higher-priority threads
 *  will run before lower-priority threads.
 *
 *     count1 = count2 = 0
 *     a = Thread.new do
 *           loop { count1 += 1 }
 *         end
 *     a.priority = -1
 *
 *     b = Thread.new do
 *           loop { count2 += 1 }
 *         end
 *     b.priority = -2
 *     sleep 1   #=> 1
 *     Thread.critical = 1
 *     count1    #=> 622504
 *     count2    #=> 5832
 */

static VALUE
rb_thread_priority_set(thread, prio)
    VALUE thread, prio;
{
    rb_thread_t th;

    rb_secure(4);
    th = rb_thread_check(thread);

    th->priority = NUM2INT(prio);
    rb_thread_schedule();
    return prio;
}


/*
 *  call-seq:
 *     thr.safe_level   => integer
 *
 *  Returns the safe level in effect for <i>thr</i>. Setting thread-local safe
 *  levels can help when implementing sandboxes which run insecure code.
 *
 *     thr = Thread.new { $SAFE = 3; sleep }
 *     Thread.current.safe_level   #=> 0
 *     thr.safe_level              #=> 3
 */

static VALUE
rb_thread_safe_level(thread)
    VALUE thread;
{
    rb_thread_t th;

    th = rb_thread_check(thread);
    if (th == curr_thread) {
	return INT2NUM(ruby_safe_level);
    }
    return INT2NUM(th->safe);
}

static int ruby_thread_abort;
static VALUE thgroup_default;


/*
 *  call-seq:
 *     Thread.abort_on_exception   => true or false
 *
 *  Returns the status of the global ``abort on exception'' condition.  The
 *  default is <code>false</code>. When set to <code>true</code>, or if the
 *  global <code>$DEBUG</code> flag is <code>true</code> (perhaps because the
 *  command line option <code>-d</code> was specified) all threads will abort
 *  (the process will <code>exit(0)</code>) if an exception is raised in any
 *  thread. See also <code>Thread::abort_on_exception=</code>.
 */

static VALUE
rb_thread_s_abort_exc()
{
    return ruby_thread_abort?Qtrue:Qfalse;
}


/*
 *  call-seq:
 *     Thread.abort_on_exception= boolean   => true or false
 *
 *  When set to <code>true</code>, all threads will abort if an exception is
 *  raised. Returns the new state.
 *
 *     Thread.abort_on_exception = true
 *     t1 = Thread.new do
 *       puts  "In new thread"
 *       raise "Exception from thread"
 *     end
 *     sleep(1)
 *     puts "not reached"
 *
 *  <em>produces:</em>
 *
 *     In new thread
 *     prog.rb:4: Exception from thread (RuntimeError)
 *     	from prog.rb:2:in `initialize'
 *     	from prog.rb:2:in `new'
 *     	from prog.rb:2
 */

static VALUE
rb_thread_s_abort_exc_set(self, val)
    VALUE self, val;
{
    rb_secure(4);
    ruby_thread_abort = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     thr.abort_on_exception   => true or false
 *
 *  Returns the status of the thread-local ``abort on exception'' condition for
 *  <i>thr</i>. The default is <code>false</code>. See also
 *  <code>Thread::abort_on_exception=</code>.
 */

static VALUE
rb_thread_abort_exc(thread)
    VALUE thread;
{
    return rb_thread_check(thread)->abort?Qtrue:Qfalse;
}


/*
 *  call-seq:
 *     thr.abort_on_exception= boolean   => true or false
 *
 *  When set to <code>true</code>, causes all threads (including the main
 *  program) to abort if an exception is raised in <i>thr</i>. The process will
 *  effectively <code>exit(0)</code>.
 */

static VALUE
rb_thread_abort_exc_set(thread, val)
    VALUE thread, val;
{
    rb_secure(4);
    rb_thread_check(thread)->abort = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     thr.group   => thgrp or nil
 *
 *  Returns the <code>ThreadGroup</code> which contains <i>thr</i>, or nil if
 *  the thread is not a member of any group.
 *
 *     Thread.main.group   #=> #<ThreadGroup:0x4029d914>
 */

VALUE
rb_thread_group(thread)
    VALUE thread;
{
    VALUE group = rb_thread_check(thread)->thgroup;
    if (!group) {
	group = Qnil;
    }
    return group;
}

#ifdef __ia64
# define IA64_INIT(x) x
#else
# define IA64_INIT(x)
#endif

#define THREAD_ALLOC(th) do {\
    th = ALLOC(struct rb_thread);\
\
    th->next = 0;\
    th->prev = 0;\
\
    th->status = THREAD_RUNNABLE;\
    th->result = 0;\
    th->flags = 0;\
\
    th->stk_ptr = 0;\
    th->stk_len = 0;\
    th->stk_max = 0;\
    th->wait_for = 0;\
    IA64_INIT(th->bstr_ptr = 0);\
    IA64_INIT(th->bstr_len = 0);\
    IA64_INIT(th->bstr_max = 0);\
    FD_ZERO(&th->readfds);\
    FD_ZERO(&th->writefds);\
    FD_ZERO(&th->exceptfds);\
    th->delay = 0.0;\
    th->join = 0;\
\
    th->frame = 0;\
    th->scope = 0;\
    th->klass = 0;\
    th->wrapper = 0;\
    th->cref = ruby_cref;\
    th->dyna_vars = ruby_dyna_vars;\
    th->block = 0;\
    th->iter = 0;\
    th->tag = 0;\
    th->tracing = 0;\
    th->errinfo = Qnil;\
    th->last_status = 0;\
    th->last_line = 0;\
    th->last_match = Qnil;\
    th->abort = 0;\
    th->priority = 0;\
    th->thgroup = thgroup_default;\
    th->locals = 0;\
    th->thread = 0;\
    th->anchor = 0;\
    if (curr_thread == 0) {\
	th->sandbox = Qnil;\
    } else {\
	th->sandbox = curr_thread->sandbox;\
    }\
} while (0)

static rb_thread_t
rb_thread_alloc(klass)
    VALUE klass;
{
    rb_thread_t th;
    struct RVarmap *vars;

    THREAD_ALLOC(th);
    th->thread = Data_Wrap_Struct(klass, thread_mark, thread_free, th);

    EXEC_EVENT_HOOK(RUBY_EVENT_THREAD_INIT, ruby_current_node,
		    th->thread, 0, RBASIC(th->thread)->klass);

    for (vars = th->dyna_vars; vars; vars = vars->next) {
	if (FL_TEST(vars, DVAR_DONT_RECYCLE)) break;
	FL_SET(vars, DVAR_DONT_RECYCLE);
    }
    return th;
}

#if defined(HAVE_SETITIMER) || defined(_THREAD_SAFE)
static int thread_init;
#endif

#if defined(POSIX_SIGNAL)
#define CATCH_VTALRM() posix_signal(SIGVTALRM, catch_timer)
#else
#define CATCH_VTALRM() signal(SIGVTALRM, catch_timer)
#endif

#if defined(_THREAD_SAFE)
static void
catch_timer(sig)
    int sig;
{
#if !defined(POSIX_SIGNAL) && !defined(BSD_SIGNAL)
    signal(sig, catch_timer);
#endif
    /* cause EINTR */
}

#define PER_NANO 1000000000

static struct timespec *
get_ts(struct timespec *to, long ns)
{
    struct timeval tv;

#ifdef CLOCK_REALTIME
    if (clock_gettime(CLOCK_REALTIME, to) != 0)
#endif
    {
	gettimeofday(&tv, NULL);
	to->tv_sec = tv.tv_sec;
	to->tv_nsec = tv.tv_usec * 1000;
    }
    if ((to->tv_nsec += ns) >= PER_NANO) {
	to->tv_sec += to->tv_nsec / PER_NANO;
	to->tv_nsec %= PER_NANO;
    }
    return to;
}

static struct timer_thread {
    pthread_cond_t cond;
    pthread_mutex_t lock;
    pthread_t thread;
} time_thread = {PTHREAD_COND_INITIALIZER, PTHREAD_MUTEX_INITIALIZER};

static int timer_stopping;

#define safe_mutex_lock(lock) \
    pthread_mutex_lock(lock); \
    pthread_cleanup_push((void (*)_((void *)))pthread_mutex_unlock, lock)

static void*
thread_timer(dummy)
    void *dummy;
{
    struct timer_thread *running = ((void **)dummy)[0];
    pthread_cond_t *start = ((void **)dummy)[1];
    struct timespec to;
    int err;

    sigset_t all_signals;

    sigfillset(&all_signals);
    pthread_sigmask(SIG_BLOCK, &all_signals, 0);

    safe_mutex_lock(&running->lock);
    pthread_cond_signal(start);

#define WAIT_FOR_10MS() \
    pthread_cond_timedwait(&running->cond, &running->lock, get_ts(&to, PER_NANO/100))
    while ((err = WAIT_FOR_10MS()) == EINTR || err == ETIMEDOUT) {
	if (timer_stopping)
	    break;

	if (!rb_thread_critical) {
	    rb_thread_pending = 1;
	    if (rb_trap_immediate) {
		pthread_kill(ruby_thid, SIGVTALRM);
	    }
	}
    }

    pthread_cleanup_pop(1);

    return NULL;
}

void
rb_thread_start_timer()
{
    void *args[2];
    static pthread_cond_t start = PTHREAD_COND_INITIALIZER;

    if (thread_init) return;
    if (rb_thread_alone()) return;
    CATCH_VTALRM();
    args[0] = &time_thread;
    args[1] = &start;
    safe_mutex_lock(&time_thread.lock);
    if (pthread_create(&time_thread.thread, 0, thread_timer, args) == 0) {
	thread_init = 1;
	pthread_cond_wait(&start, &time_thread.lock);
    }
    pthread_cleanup_pop(1);
}

void
rb_thread_stop_timer()
{
    if (!thread_init) return;
    safe_mutex_lock(&time_thread.lock);
    timer_stopping = 1;
    pthread_cond_signal(&time_thread.cond);
    thread_init = 0;
    pthread_cleanup_pop(1);
    pthread_join(time_thread.thread, NULL);
    timer_stopping = 0;
}
#elif defined(HAVE_SETITIMER)
static void
catch_timer(sig)
    int sig;
{
#if !defined(POSIX_SIGNAL) && !defined(BSD_SIGNAL)
    signal(sig, catch_timer);
#endif
    if (!rb_thread_critical) {
	rb_thread_pending = 1;
    }
    /* cause EINTR */
}

void
rb_thread_start_timer()
{
    struct itimerval tval;

    if (thread_init) return;
    if (rb_thread_alone()) return;
    CATCH_VTALRM();
    tval.it_interval.tv_sec = 0;
    tval.it_interval.tv_usec = 10000;
    tval.it_value = tval.it_interval;
    setitimer(ITIMER_VIRTUAL, &tval, NULL);
    thread_init = 1;
}

void
rb_thread_stop_timer()
{
    struct itimerval tval;

    if (!thread_init) return;
    tval.it_interval.tv_sec = 0;
    tval.it_interval.tv_usec = 0;
    tval.it_value = tval.it_interval;
    setitimer(ITIMER_VIRTUAL, &tval, NULL);
    thread_init = 0;
}
#else  /* !(_THREAD_SAFE || HAVE_SETITIMER) */
int rb_thread_tick = THREAD_TICK;
#endif

#if defined(HAVE_SETITIMER) || defined(_THREAD_SAFE)
#define START_TIMER() (thread_init ? (void)0 : rb_thread_start_timer())
#define STOP_TIMER() (rb_thread_stop_timer())
#else
#define START_TIMER() ((void)0)
#define STOP_TIMER() ((void)0)
#endif

NORETURN(static void rb_thread_terminated _((rb_thread_t, int, enum rb_thread_status)));
static VALUE rb_thread_yield _((VALUE, rb_thread_t));

static void
push_thread_anchor(ip)
    struct ruby_env *ip;
{
    ip->tag = prot_tag;
    ip->frame = ruby_frame;
    ip->block = ruby_block;
    ip->scope = ruby_scope;
    ip->iter = ruby_iter;
    ip->cref = ruby_cref;
    ip->prev = curr_thread->anchor;
    curr_thread->anchor = ip;
}

static void
pop_thread_anchor(ip)
    struct ruby_env *ip;
{
    curr_thread->anchor = ip->prev;
}

static void
thread_insert(th)
    rb_thread_t th;
{
    if (!th->next) {
	/* merge in thread list */
	th->prev = curr_thread;
	curr_thread->next->prev = th;
	th->next = curr_thread->next;
	curr_thread->next = th;
	th->priority = curr_thread->priority;
	th->thgroup = curr_thread->thgroup;
    }
}

static VALUE
rb_thread_start_0(fn, arg, th)
    VALUE (*fn)();
    void *arg;
    rb_thread_t th;
{
    volatile rb_thread_t th_save = th;
    volatile VALUE thread = th->thread;
    struct BLOCK *volatile saved_block = 0;
    enum rb_thread_status status;
    int state;

    if (OBJ_FROZEN(curr_thread->thgroup)) {
	rb_raise(rb_eThreadError,
		 "can't start a new thread (frozen ThreadGroup)");
    }

    if (THREAD_SAVE_CONTEXT(curr_thread)) {
	return thread;
    }

    if (fn == rb_thread_yield && curr_thread->anchor) {
	struct ruby_env *ip = curr_thread->anchor;
	new_thread.thread = th;
	new_thread.proc = rb_block_proc();
	new_thread.arg = (VALUE)arg;
	th->anchor = ip;
	thread_insert(th);
	curr_thread = th;
	ruby_longjmp((prot_tag = ip->tag)->buf, TAG_THREAD);
    }

    if (ruby_block) {		/* should nail down higher blocks */
	struct BLOCK dummy;

	dummy.prev = ruby_block;
	blk_copy_prev(&dummy);
	saved_block = ruby_block = dummy.prev;
    }
    scope_dup(ruby_scope);

    thread_insert(th);
    START_TIMER();

    PUSH_TAG(PROT_THREAD);
    if ((state = EXEC_TAG()) == 0) {
	if (THREAD_SAVE_CONTEXT(th) == 0) {
	    curr_thread = th;
	    th->result = (*fn)(arg, th);
	}
	th = th_save;
    }
    else if (TAG_DST()) {
	th = th_save;
	th->result = prot_tag->retval;
    }
    POP_TAG();
    status = th->status;

    if (th == main_thread) ruby_stop(state);
    rb_thread_remove(th);

    if (saved_block) {
	blk_free(saved_block);
    }

    rb_thread_terminated(th, state, status);
    return 0;			/* not reached */
}

static void
rb_thread_terminated(th, state, status)
    rb_thread_t th;
    int state;
    enum rb_thread_status status;
{
    if (state && status != THREAD_TO_KILL && !NIL_P(ruby_errinfo)) {
	th->flags |= RAISED_EXCEPTION;
	if (state == TAG_FATAL) {
	    /* fatal error within this thread, need to stop whole script */
	    main_thread->errinfo = ruby_errinfo;
	    rb_thread_cleanup();
	}
	else if (rb_obj_is_kind_of(ruby_errinfo, rb_eSystemExit)) {
	    if (th->safe >= 4) {
		char buf[32];

		sprintf(buf, "Insecure exit at level %d", th->safe);
		th->errinfo = rb_exc_new2(rb_eSecurityError, buf);
	    }
	    else {
		/* delegate exception to main_thread */
		rb_thread_main_jump(ruby_errinfo, RESTORE_RAISE);
	    }
	}
	else if (th->safe < 4 && (ruby_thread_abort || th->abort || RTEST(ruby_debug))) {
	    /* exit on main_thread */
	    error_print();
	    rb_thread_main_jump(ruby_errinfo, RESTORE_EXIT);
	}
	else {
	    th->errinfo = ruby_errinfo;
	}
    }
    rb_thread_schedule();
    ruby_stop(0);		/* last thread termination */
}

static VALUE
rb_thread_yield_0(arg)
    VALUE arg;
{
    return rb_thread_yield(arg, curr_thread);
}

static void
rb_thread_start_1()
{
    rb_thread_t th = new_thread.thread;
    volatile rb_thread_t th_save = th;
    VALUE proc = new_thread.proc;
    VALUE arg = new_thread.arg;
    struct ruby_env *ip = th->anchor;
    enum rb_thread_status status;
    int state;

    ruby_frame = ip->frame;
    ruby_block = ip->block;
    ruby_scope = ip->scope;
    ruby_iter = ip->iter;
    ruby_cref = ip->cref;
    ruby_dyna_vars = ((struct BLOCK *)DATA_PTR(proc))->dyna_vars;
    PUSH_FRAME();
    *ruby_frame = *ip->frame;
    ruby_frame->prev = ip->frame;
    ruby_frame->iter = ITER_CUR;
    START_TIMER();
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	if (THREAD_SAVE_CONTEXT(th) == 0) {
	    new_thread.thread = 0;
	    curr_thread = th;
	    th->result = rb_block_pass(rb_thread_yield_0, arg, proc);
	}
	th = th_save;
    }
    else if (TAG_DST()) {
	th = th_save;
	th->result = prot_tag->retval;
    }
    POP_TAG();
    POP_FRAME();
    status = th->status;

    if (th == main_thread) ruby_stop(state);
    rb_thread_remove(th);
    rb_thread_terminated(th, state, status);
}

VALUE
rb_thread_create(fn, arg)
    VALUE (*fn)();
    void *arg;
{
    ruby_init_stack((void *)&arg);
    return rb_thread_start_0(fn, arg, rb_thread_alloc(rb_cThread));
}

static VALUE
rb_thread_yield(arg, th)
    VALUE arg;
    rb_thread_t th;
{
    const ID *tbl;

    scope_dup(ruby_block->scope);

    tbl = ruby_scope->local_tbl;
    if (tbl) {
	int n = *tbl++;
	for (tbl += 2, n -= 2; n > 0; --n) { /* skip first 2 ($_ and $~) */
	    ID id = *tbl++;
	    if (id != 0 && !rb_is_local_id(id))  /* push flip states */
		rb_dvar_push(id, Qfalse);
	}
    }
    rb_dvar_push('_', Qnil);
    rb_dvar_push('~', Qnil);
    ruby_block->dyna_vars = ruby_dyna_vars;

    return rb_yield_0(arg, 0, 0, YIELD_LAMBDA_CALL, Qtrue);
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

static VALUE
rb_thread_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    rb_thread_t th = rb_thread_alloc(klass);
    volatile VALUE *pos;

    pos = th->stk_pos;
    rb_obj_call_init(th->thread, argc, argv);
    if (th->stk_pos == 0) {
	rb_raise(rb_eThreadError, "uninitialized thread - check `%s#initialize'",
		 rb_class2name(klass));
    }

    return th->thread;
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

static VALUE
rb_thread_initialize(thread, args)
    VALUE thread, args;
{
    rb_thread_t th;

    if (!rb_block_given_p()) {
	rb_raise(rb_eThreadError, "must be called with a block");
    }
    th = rb_thread_check(thread);
    if (th->stk_max) {
	NODE *node = th->node;
	if (!node) {
	    rb_raise(rb_eThreadError, "already initialized thread");
	}
	rb_raise(rb_eThreadError, "already initialized thread - %s:%d",
		 node->nd_file, nd_line(node));
    }
    return rb_thread_start_0(rb_thread_yield, args, th);
}


/*
 *  call-seq:
 *     Thread.start([args]*) {|args| block }   => thread
 *     Thread.fork([args]*) {|args| block }    => thread
 *
 *  Basically the same as <code>Thread::new</code>. However, if class
 *  <code>Thread</code> is subclassed, then calling <code>start</code> in that
 *  subclass will not invoke the subclass's <code>initialize</code> method.
 */

static VALUE
rb_thread_start(klass, args)
    VALUE klass, args;
{
    if (!rb_block_given_p()) {
	rb_raise(rb_eThreadError, "must be called with a block");
    }
    return rb_thread_start_0(rb_thread_yield, args, rb_thread_alloc(klass));
}


/*
 *  call-seq:
 *     thr.value   => obj
 *
 *  Waits for <i>thr</i> to complete (via <code>Thread#join</code>) and returns
 *  its value.
 *
 *     a = Thread.new { 2 + 2 }
 *     a.value   #=> 4
 */

static VALUE
rb_thread_value(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    while (!rb_thread_join0(th, DELAY_INFTY));

    return th->result;
}


/*
 *  call-seq:
 *     thr.status   => string, false or nil
 *
 *  Returns the status of <i>thr</i>: ``<code>sleep</code>'' if <i>thr</i> is
 *  sleeping or waiting on I/O, ``<code>run</code>'' if <i>thr</i> is executing,
 *  ``<code>aborting</code>'' if <i>thr</i> is aborting, <code>false</code> if
 *  <i>thr</i> terminated normally, and <code>nil</code> if <i>thr</i>
 *  terminated with an exception.
 *
 *     a = Thread.new { raise("die now") }
 *     b = Thread.new { Thread.stop }
 *     c = Thread.new { Thread.exit }
 *     d = Thread.new { sleep }
 *     Thread.critical = true
 *     d.kill                  #=> #<Thread:0x401b3678 aborting>
 *     a.status                #=> nil
 *     b.status                #=> "sleep"
 *     c.status                #=> false
 *     d.status                #=> "aborting"
 *     Thread.current.status   #=> "run"
 */

static VALUE
rb_thread_status(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (rb_thread_dead(th)) {
	if (!NIL_P(th->errinfo) && (th->flags & RAISED_EXCEPTION))
	    return Qnil;
	return Qfalse;
    }

    return rb_str_new2(thread_status_name(th->status));
}


/*
 *  call-seq:
 *     thr.alive?   => true or false
 *
 *  Returns <code>true</code> if <i>thr</i> is running or sleeping.
 *
 *     thr = Thread.new { }
 *     thr.join                #=> #<Thread:0x401b3fb0 dead>
 *     Thread.current.alive?   #=> true
 *     thr.alive?              #=> false
 */

VALUE
rb_thread_alive_p(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (rb_thread_dead(th)) return Qfalse;
    return Qtrue;
}


/*
 *  call-seq:
 *     thr.stop?   => true or false
 *
 *  Returns <code>true</code> if <i>thr</i> is dead or sleeping.
 *
 *     a = Thread.new { Thread.stop }
 *     b = Thread.current
 *     a.stop?   #=> true
 *     b.stop?   #=> false
 */

static VALUE
rb_thread_stop_p(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (rb_thread_dead(th)) return Qtrue;
    if (th->status == THREAD_STOPPED) return Qtrue;
    return Qfalse;
}

static void
rb_thread_wait_other_threads()
{
    rb_thread_t th;
    int found;

    /* wait other threads to terminate */
    while (curr_thread != curr_thread->next) {
	found = 0;
	FOREACH_THREAD(th) {
	    if (th != curr_thread && th->status != THREAD_STOPPED) {
		found = 1;
		break;
	    }
	}
	END_FOREACH(th);
	if (!found) return;
	rb_thread_schedule();
    }
}

static void
rb_thread_cleanup()
{
    rb_thread_t curr, th;

    curr = curr_thread;
    while (curr->status == THREAD_KILLED) {
	curr = curr->prev;
    }

    FOREACH_THREAD_FROM(curr, th) {
	if (th->status != THREAD_KILLED) {
	    rb_thread_ready(th);
	    if (th != main_thread) {
		th->thgroup = 0;
		th->priority = 0;
		th->status = THREAD_TO_KILL;
		RDATA(th->thread)->dfree = NULL;
	    }
	}
    }
    END_FOREACH_FROM(curr, th);
}

int rb_thread_critical;


/*
 *  call-seq:
 *     Thread.critical   => true or false
 *
 *  Returns the status of the global ``thread critical'' condition.
 */

static VALUE
rb_thread_critical_get()
{
    return rb_thread_critical?Qtrue:Qfalse;
}


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

static VALUE
rb_thread_critical_set(obj, val)
    VALUE obj, val;
{
    rb_thread_critical = RTEST(val);
    return val;
}

void
rb_thread_interrupt()
{
    rb_thread_critical = 0;
    rb_thread_ready(main_thread);
    if (curr_thread == main_thread) {
	rb_interrupt();
    }
    if (!rb_thread_dead(curr_thread)) {
	if (THREAD_SAVE_CONTEXT(curr_thread)) {
	    return;
	}
    }
    curr_thread = main_thread;
    rb_thread_restore_context(curr_thread, RESTORE_INTERRUPT);
}

void
rb_thread_signal_raise(sig)
    int sig;
{
    rb_thread_critical = 0;
    if (curr_thread == main_thread) {
	VALUE argv[1];

	rb_thread_ready(curr_thread);
	argv[0] = INT2FIX(sig);
	rb_exc_raise(rb_class_new_instance(1, argv, rb_eSignal));
    }
    rb_thread_ready(main_thread);
    if (!rb_thread_dead(curr_thread)) {
	if (THREAD_SAVE_CONTEXT(curr_thread)) {
	    return;
	}
    }
    th_sig = sig;
    curr_thread = main_thread;
    rb_thread_restore_context(curr_thread, RESTORE_SIGNAL);
}

void
rb_thread_trap_eval(cmd, sig, safe)
    VALUE cmd;
    int sig, safe;
{
    rb_thread_critical = 0;
    if (curr_thread == main_thread) {
	rb_trap_eval(cmd, sig, safe);
	return;
    }
    if (!rb_thread_dead(curr_thread)) {
	if (THREAD_SAVE_CONTEXT(curr_thread)) {
	    return;
	}
    }
    th_cmd = cmd;
    th_sig = sig;
    th_safe = safe;
    curr_thread = main_thread;
    rb_thread_restore_context(curr_thread, RESTORE_TRAP);
}

void
rb_thread_signal_exit()
{
    VALUE args[2];

    rb_thread_critical = 0;
    if (curr_thread == main_thread) {
	rb_thread_ready(curr_thread);
	rb_exit(EXIT_SUCCESS);
    }
    args[0] = INT2NUM(EXIT_SUCCESS);
    args[1] = rb_str_new2("exit");
    rb_thread_ready(main_thread);
    if (!rb_thread_dead(curr_thread)) {
	if (THREAD_SAVE_CONTEXT(curr_thread)) {
	    return;
	}
    }
    rb_thread_main_jump(rb_class_new_instance(2, args, rb_eSystemExit),
			RESTORE_EXIT);
}

static VALUE
rb_thread_raise(argc, argv, th)
    int argc;
    VALUE *argv;
    rb_thread_t th;
{
    volatile rb_thread_t th_save = th;
    VALUE exc;

    if (!th->next) {
	rb_raise(rb_eArgError, "unstarted thread");
    }
    if (rb_thread_dead(th)) return Qnil;
    exc = rb_make_exception(argc, argv);
    if (curr_thread == th) {
	rb_raise_jump(exc);
    }

    if (!rb_thread_dead(curr_thread)) {
	if (THREAD_SAVE_CONTEXT(curr_thread)) {
	    return th_save->thread;
	}
    }

    rb_thread_ready(th);
    curr_thread = th;

    th_raise_exception = exc;
    th_raise_node = ruby_current_node;
    rb_thread_restore_context(curr_thread, RESTORE_RAISE);
    return Qnil;		/* not reached */
}


/*
 *  call-seq:
 *     thr.raise(exception)
 *
 *  Raises an exception (see <code>Kernel::raise</code>) from <i>thr</i>. The
 *  caller does not have to be <i>thr</i>.
 *
 *     Thread.abort_on_exception = true
 *     a = Thread.new { sleep(200) }
 *     a.raise("Gotcha")
 *
 *  <em>produces:</em>
 *
 *     prog.rb:3: Gotcha (RuntimeError)
 *     	from prog.rb:2:in `initialize'
 *     	from prog.rb:2:in `new'
 *     	from prog.rb:2
 */

static VALUE
rb_thread_raise_m(argc, argv, thread)
    int argc;
    VALUE *argv;
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (ruby_safe_level > th->safe) {
	rb_secure(4);
    }
    rb_thread_raise(argc, argv, th);
    return Qnil;		/* not reached */
}

VALUE
rb_thread_local_aref(thread, id)
    VALUE thread;
    ID id;
{
    rb_thread_t th;
    VALUE val;

    th = rb_thread_check(thread);
    if (ruby_safe_level >= 4 && th != curr_thread) {
	rb_raise(rb_eSecurityError, "Insecure: thread locals");
    }
    if (!th->locals) return Qnil;
    if (st_lookup(th->locals, id, &val)) {
	return val;
    }
    return Qnil;
}


/*
 *  call-seq:
 *      thr[sym]   => obj or nil
 *
 *  Attribute Reference---Returns the value of a thread-local variable, using
 *  either a symbol or a string name. If the specified variable does not exist,
 *  returns <code>nil</code>.
 *
 *     a = Thread.new { Thread.current["name"] = "A"; Thread.stop }
 *     b = Thread.new { Thread.current[:name]  = "B"; Thread.stop }
 *     c = Thread.new { Thread.current["name"] = "C"; Thread.stop }
 *     Thread.list.each {|x| puts "#{x.inspect}: #{x[:name]}" }
 *
 *  <em>produces:</em>
 *
 *     #<Thread:0x401b3b3c sleep>: C
 *     #<Thread:0x401b3bc8 sleep>: B
 *     #<Thread:0x401b3c68 sleep>: A
 *     #<Thread:0x401bdf4c run>:
 */

static VALUE
rb_thread_aref(thread, id)
    VALUE thread, id;
{
    return rb_thread_local_aref(thread, rb_to_id(id));
}

VALUE
rb_thread_local_aset(thread, id, val)
    VALUE thread;
    ID id;
    VALUE val;
{
    rb_thread_t th = rb_thread_check(thread);

    if (ruby_safe_level >= 4 && th != curr_thread) {
	rb_raise(rb_eSecurityError, "Insecure: can't modify thread locals");
    }
    if (OBJ_FROZEN(thread)) rb_error_frozen("thread locals");

    if (!th->locals) {
	th->locals = st_init_numtable();
    }
    if (NIL_P(val)) {
	st_delete(th->locals, (st_data_t*)&id, 0);
	return Qnil;
    }
    st_insert(th->locals, id, val);

    return val;
}


/*
 *  call-seq:
 *      thr[sym] = obj   => obj
 *
 *  Attribute Assignment---Sets or creates the value of a thread-local variable,
 *  using either a symbol or a string. See also <code>Thread#[]</code>.
 */

static VALUE
rb_thread_aset(thread, id, val)
    VALUE thread, id, val;
{
    return rb_thread_local_aset(thread, rb_to_id(id), val);
}


/*
 *  call-seq:
 *     thr.key?(sym)   => true or false
 *
 *  Returns <code>true</code> if the given string (or symbol) exists as a
 *  thread-local variable.
 *
 *     me = Thread.current
 *     me[:oliver] = "a"
 *     me.key?(:oliver)    #=> true
 *     me.key?(:stanley)   #=> false
 */

static VALUE
rb_thread_key_p(thread, id)
    VALUE thread, id;
{
    rb_thread_t th = rb_thread_check(thread);

    if (!th->locals) return Qfalse;
    if (st_lookup(th->locals, rb_to_id(id), 0))
	return Qtrue;
    return Qfalse;
}

static int
thread_keys_i(key, value, ary)
    ID key;
    VALUE value, ary;
{
    rb_ary_push(ary, ID2SYM(key));
    return ST_CONTINUE;
}


/*
 *  call-seq:
 *     thr.keys   => array
 *
 *  Returns an an array of the names of the thread-local variables (as Symbols).
 *
 *     thr = Thread.new do
 *       Thread.current[:cat] = 'meow'
 *       Thread.current["dog"] = 'woof'
 *     end
 *     thr.join   #=> #<Thread:0x401b3f10 dead>
 *     thr.keys   #=> [:dog, :cat]
 */

static VALUE
rb_thread_keys(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);
    VALUE ary = rb_ary_new();

    if (th->locals) {
	st_foreach(th->locals, thread_keys_i, ary);
    }
    return ary;
}

/*
 * call-seq:
 *   thr.inspect   => string
 *
 * Dump the name, id, and status of _thr_ to a string.
 */

static VALUE
rb_thread_inspect(thread)
    VALUE thread;
{
    const char *cname = rb_obj_classname(thread);
    rb_thread_t th = rb_thread_check(thread);
    const char *status = thread_status_name(th->status);
    VALUE str;
    size_t len = strlen(cname)+7+16+9+1;

    str = rb_str_new(0, len); /* 7:tags 16:addr 9:status 1:nul */
    snprintf(RSTRING(str)->ptr, len, "#<%s:0x%lx %s>", cname, thread, status);
    RSTRING(str)->len = strlen(RSTRING(str)->ptr);
    OBJ_INFECT(str, thread);

    return str;
}

void
rb_thread_atfork()
{
    rb_thread_t th;

    rb_reset_random_seed();
    if (rb_thread_alone()) return;
    FOREACH_THREAD(th) {
	if (th != curr_thread) {
	    rb_thread_die(th);
	}
    }
    END_FOREACH(th);
    main_thread = curr_thread;
    curr_thread->next = curr_thread;
    curr_thread->prev = curr_thread;
    STOP_TIMER();
}


static void
cc_purge(cc)
    rb_thread_t cc;
{
    /* free continuation's stack if it has just died */
    if (NIL_P(cc->thread)) return;
    if (rb_thread_check(cc->thread)->status == THREAD_KILLED) {
	cc->thread = Qnil;
	rb_thread_die(cc);  /* can't possibly activate this stack */
    }
}

static void
cc_mark(cc)
    rb_thread_t cc;
{
    /* mark this continuation's stack only if its parent thread is still alive */
    cc_purge(cc);
    thread_mark(cc);
}

static rb_thread_t
rb_cont_check(data)
    VALUE data;
{
    if (TYPE(data) != T_DATA || RDATA(data)->dmark != (RUBY_DATA_FUNC)cc_mark) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected Continuation)",
		 rb_obj_classname(data));
    }
    return (rb_thread_t)RDATA(data)->data;
}

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
    volatile VALUE cont;
    rb_thread_t th;
    volatile rb_thread_t th_save;
    struct tag *tag;
    struct RVarmap *vars;

    THREAD_ALLOC(th);
    /* must finish th initialization before any possible gc.
     * brent@mbari.org */
    th->thread = curr_thread->thread;
    th->thgroup = cont_protect;
    cont = Data_Wrap_Struct(rb_cCont, cc_mark, thread_free, th);

    scope_dup(ruby_scope);
    for (tag=prot_tag; tag; tag=tag->prev) {
	scope_dup(tag->scope);
    }

    for (vars = ruby_dyna_vars; vars; vars = vars->next) {
	if (FL_TEST(vars, DVAR_DONT_RECYCLE)) break;
	FL_SET(vars, DVAR_DONT_RECYCLE);
    }
    th_save = th;
    if (THREAD_SAVE_CONTEXT(th)) {
	return th_save->result;
    }
    else {
	return rb_yield(cont);
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
rb_cont_call(argc, argv, cont)
    int argc;
    VALUE *argv;
    VALUE cont;
{
    rb_thread_t th = rb_cont_check(cont);

    if (th->thread != curr_thread->thread) {
	rb_raise(rb_eRuntimeError, "continuation called across threads");
    }
    if (th->thgroup != cont_protect) {
	rb_raise(rb_eRuntimeError, "continuation called across trap");
    }
    switch (argc) {
      case 0:
	th->result = Qnil;
	break;
      case 1:
	th->result = argv[0];
	break;
      default:
	th->result = rb_ary_new4(argc, argv);
	break;
    }

    rb_thread_restore_context(th, RESTORE_NORMAL);
    return Qnil;
}

void
Init_Cont()
{
    rb_cCont = rb_define_class("Continuation", rb_cObject);
    rb_undef_alloc_func(rb_cCont);
    rb_undef_method(CLASS_OF(rb_cCont), "new");
    rb_define_method(rb_cCont, "call", rb_cont_call, -1);
    rb_define_method(rb_cCont, "[]", rb_cont_call, -1);
    rb_define_global_function("callcc", rb_callcc, 0);
    rb_global_variable(&cont_protect);
    rb_provide("continuation.so");
}

struct thgroup {
    int enclosed;
    VALUE group;
};


/*
 * Document-class: ThreadGroup
 *
 *  <code>ThreadGroup</code> provides a means of keeping track of a number of
 *  threads as a group. A <code>Thread</code> can belong to only one
 *  <code>ThreadGroup</code> at a time; adding a thread to a new group will
 *  remove it from any previous group.
 *
 *  Newly created threads belong to the same group as the thread from which they
 *  were created.
 */

static VALUE thgroup_s_alloc _((VALUE));
static VALUE
thgroup_s_alloc(klass)
    VALUE klass;
{
    VALUE group;
    struct thgroup *data;

    group = Data_Make_Struct(klass, struct thgroup, 0, free, data);
    data->enclosed = 0;
    data->group = group;

    return group;
}


/*
 *  call-seq:
 *     thgrp.list   => array
 *
 *  Returns an array of all existing <code>Thread</code> objects that belong to
 *  this group.
 *
 *     ThreadGroup::Default.list   #=> [#<Thread:0x401bdf4c run>]
 */

static VALUE
thgroup_list(group)
    VALUE group;
{
    struct thgroup *data;
    rb_thread_t th;
    VALUE ary;

    Data_Get_Struct(group, struct thgroup, data);
    ary = rb_ary_new();

    FOREACH_THREAD(th) {
	if (th->thgroup == data->group) {
	    rb_ary_push(ary, th->thread);
	}
    }
    END_FOREACH(th);

    return ary;
}


/*
 *  call-seq:
 *     thgrp.enclose   => thgrp
 *
 *  Prevents threads from being added to or removed from the receiving
 *  <code>ThreadGroup</code>. New threads can still be started in an enclosed
 *  <code>ThreadGroup</code>.
 *
 *     ThreadGroup::Default.enclose        #=> #<ThreadGroup:0x4029d914>
 *     thr = Thread::new { Thread.stop }   #=> #<Thread:0x402a7210 sleep>
 *     tg = ThreadGroup::new               #=> #<ThreadGroup:0x402752d4>
 *     tg.add thr
 *
 *  <em>produces:</em>
 *
 *     ThreadError: can't move from the enclosed thread group
 */

static VALUE
thgroup_enclose(group)
    VALUE group;
{
    struct thgroup *data;

    Data_Get_Struct(group, struct thgroup, data);
    data->enclosed = 1;

    return group;
}


/*
 *  call-seq:
 *     thgrp.enclosed?   => true or false
 *
 *  Returns <code>true</code> if <em>thgrp</em> is enclosed. See also
 *  ThreadGroup#enclose.
 */

static VALUE
thgroup_enclosed_p(group)
    VALUE group;
{
    struct thgroup *data;

    Data_Get_Struct(group, struct thgroup, data);
    if (data->enclosed) return Qtrue;
    return Qfalse;
}


/*
 *  call-seq:
 *     thgrp.add(thread)   => thgrp
 *
 *  Adds the given <em>thread</em> to this group, removing it from any other
 *  group to which it may have previously belonged.
 *
 *     puts "Initial group is #{ThreadGroup::Default.list}"
 *     tg = ThreadGroup.new
 *     t1 = Thread.new { sleep }
 *     t2 = Thread.new { sleep }
 *     puts "t1 is #{t1}"
 *     puts "t2 is #{t2}"
 *     tg.add(t1)
 *     puts "Initial group now #{ThreadGroup::Default.list}"
 *     puts "tg group now #{tg.list}"
 *
 *  <em>produces:</em>
 *
 *     Initial group is #<Thread:0x401bdf4c>
 *     t1 is #<Thread:0x401b3c90>
 *     t2 is #<Thread:0x401b3c18>
 *     Initial group now #<Thread:0x401b3c18>#<Thread:0x401bdf4c>
 *     tg group now #<Thread:0x401b3c90>
 */

static VALUE
thgroup_add(group, thread)
    VALUE group, thread;
{
    rb_thread_t th;
    struct thgroup *data;

    rb_secure(4);
    th = rb_thread_check(thread);

    if (OBJ_FROZEN(group)) {
      rb_raise(rb_eThreadError, "can't move to the frozen thread group");
    }
    Data_Get_Struct(group, struct thgroup, data);
    if (data->enclosed) {
	rb_raise(rb_eThreadError, "can't move to the enclosed thread group");
    }

    if (!th->thgroup) {
	return Qnil;
    }
    if (OBJ_FROZEN(th->thgroup)) {
	rb_raise(rb_eThreadError, "can't move from the frozen thread group");
    }
    Data_Get_Struct(th->thgroup, struct thgroup, data);
    if (data->enclosed) {
	rb_raise(rb_eThreadError, "can't move from the enclosed thread group");
    }

    th->thgroup = group;
    return group;
}


/* variables for recursive traversals */
static ID recursive_key;

static VALUE
recursive_check(hash, obj)
    VALUE hash;
    VALUE obj;
{
    if (NIL_P(hash) || TYPE(hash) != T_HASH) {
	return Qfalse;
    }
    else {
	VALUE list = rb_hash_aref(hash, ID2SYM(rb_frame_last_func()));

	if (NIL_P(list) || TYPE(list) != T_HASH)
	    return Qfalse;
	if (NIL_P(rb_hash_lookup(list, obj)))
	    return Qfalse;
	return Qtrue;
    }
}

static VALUE
recursive_push(hash, obj)
    VALUE hash;
    VALUE obj;
{
    VALUE list, sym;

    sym = ID2SYM(rb_frame_last_func());
    if (NIL_P(hash) || TYPE(hash) != T_HASH) {
	hash = rb_hash_new();
	OBJ_TAINT(hash);
	rb_thread_local_aset(rb_thread_current(), recursive_key, hash);
	list = Qnil;
    }
    else {
	list = rb_hash_aref(hash, sym);
    }
    if (NIL_P(list) || TYPE(list) != T_HASH) {
	list = rb_hash_new();
	OBJ_TAINT(list);
	rb_hash_aset(hash, sym, list);
    }
    rb_hash_aset(list, obj, Qtrue);
    return hash;
}

static void
recursive_pop(hash, obj)
    VALUE hash;
    VALUE obj;
{
    VALUE list, sym;

    sym = ID2SYM(rb_frame_last_func());
    if (NIL_P(hash) || TYPE(hash) != T_HASH) {
	VALUE symname;
	VALUE thrname;
	symname = rb_inspect(sym);
	thrname = rb_inspect(rb_thread_current());

	rb_raise(rb_eTypeError, "invalid inspect_tbl hash for %s in %s",
		 StringValuePtr(symname), StringValuePtr(thrname));
    }
    list = rb_hash_aref(hash, sym);
    if (NIL_P(list) || TYPE(list) != T_HASH) {
	VALUE symname = rb_inspect(sym);
	VALUE thrname = rb_inspect(rb_thread_current());
	rb_raise(rb_eTypeError, "invalid inspect_tbl list for %s in %s",
		 StringValuePtr(symname), StringValuePtr(thrname));
    }
    rb_hash_delete(list, obj);
}

VALUE
rb_exec_recursive(func, obj, arg)
    VALUE (*func) _((VALUE, VALUE, int));
    VALUE obj;
    VALUE arg;
{
    VALUE hash = rb_thread_local_aref(rb_thread_current(), recursive_key);
    VALUE objid = rb_obj_id(obj);

    if (recursive_check(hash, objid)) {
	return (*func) (obj, arg, Qtrue);
    }
    else {
	VALUE result = Qundef;
	int state;

	hash = recursive_push(hash, objid);
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    result = (*func) (obj, arg, Qfalse);
	}
	POP_TAG();
	recursive_pop(hash, objid);
	if (state)
	    JUMP_TAG(state);
	return result;
    }
}


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
    VALUE cThGroup;

    recursive_key = rb_intern("__recursive_key__");
    rb_eThreadError = rb_define_class("ThreadError", rb_eStandardError);
    rb_cThread = rb_define_class("Thread", rb_cObject);
    rb_undef_alloc_func(rb_cThread);

    rb_define_singleton_method(rb_cThread, "new", rb_thread_s_new, -1);
    rb_define_method(rb_cThread, "initialize", rb_thread_initialize, -2);
    rb_define_singleton_method(rb_cThread, "start", rb_thread_start, -2);
    rb_define_singleton_method(rb_cThread, "fork", rb_thread_start, -2);

    rb_define_singleton_method(rb_cThread, "stop", rb_thread_stop, 0);
    rb_define_singleton_method(rb_cThread, "kill", rb_thread_s_kill, 1);
    rb_define_singleton_method(rb_cThread, "exit", rb_thread_exit, 0);
    rb_define_singleton_method(rb_cThread, "pass", rb_thread_pass, 0);
    rb_define_singleton_method(rb_cThread, "current", rb_thread_current, 0);
    rb_define_singleton_method(rb_cThread, "main", rb_thread_main, 0);
    rb_define_singleton_method(rb_cThread, "list", rb_thread_list, 0);

    rb_define_singleton_method(rb_cThread, "critical", rb_thread_critical_get, 0);
    rb_define_singleton_method(rb_cThread, "critical=", rb_thread_critical_set, 1);

    rb_define_singleton_method(rb_cThread, "abort_on_exception", rb_thread_s_abort_exc, 0);
    rb_define_singleton_method(rb_cThread, "abort_on_exception=", rb_thread_s_abort_exc_set, 1);

    rb_define_method(rb_cThread, "run", rb_thread_run, 0);
    rb_define_method(rb_cThread, "wakeup", rb_thread_wakeup, 0);
    rb_define_method(rb_cThread, "kill", rb_thread_kill, 0);
    rb_define_method(rb_cThread, "terminate", rb_thread_kill, 0);
    rb_define_method(rb_cThread, "exit", rb_thread_kill, 0);
    rb_define_method(rb_cThread, "kill!", rb_thread_kill_bang, 0);
    rb_define_method(rb_cThread, "terminate!", rb_thread_kill_bang, 0);
    rb_define_method(rb_cThread, "exit!", rb_thread_kill_bang, 0);
    rb_define_method(rb_cThread, "value", rb_thread_value, 0);
    rb_define_method(rb_cThread, "status", rb_thread_status, 0);
    rb_define_method(rb_cThread, "join", rb_thread_join_m, -1);
    rb_define_method(rb_cThread, "alive?", rb_thread_alive_p, 0);
    rb_define_method(rb_cThread, "stop?", rb_thread_stop_p, 0);
    rb_define_method(rb_cThread, "raise", rb_thread_raise_m, -1);

    rb_define_method(rb_cThread, "abort_on_exception", rb_thread_abort_exc, 0);
    rb_define_method(rb_cThread, "abort_on_exception=", rb_thread_abort_exc_set, 1);

    rb_define_method(rb_cThread, "priority", rb_thread_priority, 0);
    rb_define_method(rb_cThread, "priority=", rb_thread_priority_set, 1);
    rb_define_method(rb_cThread, "safe_level", rb_thread_safe_level, 0);
    rb_define_method(rb_cThread, "group", rb_thread_group, 0);

    rb_define_method(rb_cThread, "[]", rb_thread_aref, 1);
    rb_define_method(rb_cThread, "[]=", rb_thread_aset, 2);
    rb_define_method(rb_cThread, "key?", rb_thread_key_p, 1);
    rb_define_method(rb_cThread, "keys", rb_thread_keys, 0);

    rb_define_method(rb_cThread, "inspect", rb_thread_inspect, 0);

    cThGroup = rb_define_class("ThreadGroup", rb_cObject);
    rb_define_alloc_func(cThGroup, thgroup_s_alloc);
    rb_define_method(cThGroup, "list", thgroup_list, 0);
    rb_define_method(cThGroup, "enclose", thgroup_enclose, 0);
    rb_define_method(cThGroup, "enclosed?", thgroup_enclosed_p, 0);
    rb_define_method(cThGroup, "add", thgroup_add, 1);
    rb_global_variable(&thgroup_default);
    thgroup_default = rb_obj_alloc(cThGroup);
    rb_define_const(cThGroup, "Default", thgroup_default);

    /* allocate main thread */
    main_thread = rb_thread_alloc(rb_cThread);
    curr_thread = main_thread->prev = main_thread->next = main_thread;
}

/*
 *  call-seq:
 *     catch(symbol) {| | block }  > obj
 *
 *  +catch+ executes its block. If a +throw+ is
 *  executed, Ruby searches up its stack for a +catch+ block
 *  with a tag corresponding to the +throw+'s
 *  _symbol_. If found, that block is terminated, and
 *  +catch+ returns the value given to +throw+. If
 *  +throw+ is not called, the block terminates normally, and
 *  the value of +catch+ is the value of the last expression
 *  evaluated. +catch+ expressions may be nested, and the
 *  +throw+ call need not be in lexical scope.
 *
 *     def routine(n)
 *       puts n
 *       throw :done if n <= 0
 *       routine(n-1)
 *     end
 *
 *
 *     catch(:done) { routine(3) }
 *
 *  <em>produces:</em>
 *
 *     3
 *     2
 *     1
 *     0
 */

static VALUE
rb_f_catch(dmy, tag)
    VALUE dmy, tag;
{
    int state;
    VALUE val = Qnil;		/* OK */

    tag = ID2SYM(rb_to_id(tag));
    PUSH_TAG(tag);
    if ((state = EXEC_TAG()) == 0) {
	val = rb_yield_0(tag, 0, 0, 0, Qfalse);
    }
    else if (state == TAG_THROW && tag == prot_tag->dst) {
	val = prot_tag->retval;
	state = 0;
    }
    POP_TAG();
    if (state) JUMP_TAG(state);

    return val;
}

static VALUE
catch_i(tag)
    VALUE tag;
{
    return rb_funcall(Qnil, rb_intern("catch"), 1, tag);
}

VALUE
rb_catch(tag, func, data)
    const char *tag;
    VALUE (*func)();
    VALUE data;
{
    return rb_iterate((VALUE(*)_((VALUE)))catch_i, ID2SYM(rb_intern(tag)), func, data);
}

/*
 *  call-seq:
 *     throw(symbol [, obj])
 *
 *  Transfers control to the end of the active +catch+ block
 *  waiting for _symbol_. Raises +NameError+ if there
 *  is no +catch+ block for the symbol. The optional second
 *  parameter supplies a return value for the +catch+ block,
 *  which otherwise defaults to +nil+. For examples, see
 *  <code>Kernel::catch</code>.
 */

static VALUE
rb_f_throw(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE tag, value;
    struct tag *tt = prot_tag;

    rb_scan_args(argc, argv, "11", &tag, &value);
    tag = ID2SYM(rb_to_id(tag));

    while (tt) {
	if (tt->tag == tag) {
	    tt->dst = tag;
	    tt->retval = value;
	    break;
	}
	if (tt->tag == PROT_THREAD) {
	    rb_raise(rb_eThreadError, "uncaught throw `%s' in thread 0x%lx",
		     rb_id2name(SYM2ID(tag)),
		     curr_thread);
	}
	tt = tt->prev;
    }
    if (!tt) {
	rb_name_error(SYM2ID(tag), "uncaught throw `%s'", rb_id2name(SYM2ID(tag)));
    }
    rb_trap_restore_mask();
    JUMP_TAG(TAG_THROW);
#ifndef __GNUC__
    return Qnil; 		/* not reached */
#endif
}

void
rb_throw(tag, val)
    const char *tag;
    VALUE val;
{
    VALUE argv[2];

    argv[0] = ID2SYM(rb_intern(tag));
    argv[1] = val;
    rb_f_throw(2, argv);
}
