/**********************************************************************

  gc.c -

  $Author$
  created at: Tue Oct  5 09:44:46 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/signal.h"
#include "ruby/st.h"
#include "ruby/node.h"
#include "ruby/re.h"
#include "ruby/io.h"
#include "ruby/util.h"
#include "eval_intern.h"
#include "vm_core.h"
#include "gc.h"
#include <stdio.h>
#include <setjmp.h>
#include <sys/types.h>

#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif

#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif

#if defined _WIN32 || defined __CYGWIN__
#include <windows.h>
#endif

#ifdef HAVE_VALGRIND_MEMCHECK_H
# include <valgrind/memcheck.h>
# ifndef VALGRIND_MAKE_MEM_DEFINED
#  define VALGRIND_MAKE_MEM_DEFINED(p, n) VALGRIND_MAKE_READABLE(p, n)
# endif
# ifndef VALGRIND_MAKE_MEM_UNDEFINED
#  define VALGRIND_MAKE_MEM_UNDEFINED(p, n) VALGRIND_MAKE_WRITABLE(p, n)
# endif
#else
# define VALGRIND_MAKE_MEM_DEFINED(p, n) /* empty */
# define VALGRIND_MAKE_MEM_UNDEFINED(p, n) /* empty */
#endif

int rb_io_fptr_finalize(struct rb_io_t*);

#define rb_setjmp(env) RUBY_SETJMP(env)
#define rb_jmp_buf rb_jmpbuf_t

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
#  ifdef _AIX
 #pragma alloca
#  else
#   ifndef alloca /* predefined by HP cc +Olibcalls */
void *alloca ();
#   endif
#  endif /* AIX */
# endif /* HAVE_ALLOCA_H */
#endif /* __GNUC__ */

#ifndef GC_MALLOC_LIMIT
#if defined(MSDOS) || defined(__human68k__)
#define GC_MALLOC_LIMIT 200000
#else
#define GC_MALLOC_LIMIT 8000000
#endif
#endif

static unsigned long malloc_increase = 0;
static unsigned long malloc_limit = GC_MALLOC_LIMIT;
static VALUE nomem_error;

static int dont_gc;
static int during_gc;
static int need_call_final = 0;
static st_table *finalizer_table = 0;

#define MARK_STACK_MAX 1024
static VALUE mark_stack[MARK_STACK_MAX];
static VALUE *mark_stack_ptr;
static int mark_stack_overflow;

int ruby_gc_debug_indent = 0;

#undef GC_DEBUG

#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__CYGWIN__)
#pragma pack(push, 1) /* magic for reducing sizeof(RVALUE): 24 -> 20 */
#endif

typedef struct RVALUE {
    union {
	struct {
	    VALUE flags;		/* always 0 for freed obj */
	    struct RVALUE *next;
	} free;
	struct RBasic  basic;
	struct RObject object;
	struct RClass  klass;
	struct RFloat  flonum;
	struct RString string;
	struct RArray  array;
	struct RRegexp regexp;
	struct RHash   hash;
	struct RData   data;
	struct RStruct rstruct;
	struct RBignum bignum;
	struct RFile   file;
	struct RNode   node;
	struct RMatch  match;
	struct RRational rational;
	struct RComplex complex;
    } as;
#ifdef GC_DEBUG
    char *file;
    int   line;
#endif
} RVALUE;

#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__CYGWIN__)
#pragma pack(pop)
#endif

static RVALUE *freelist = 0;
static RVALUE *deferred_final_list = 0;

#define HEAPS_INCREMENT 10
static struct heaps_slot {
    void *membase;
    RVALUE *slot;
    int limit;
} *heaps;
static int heaps_length = 0;
static int heaps_used   = 0;

#define HEAP_MIN_SLOTS 10000
static int heap_slots = HEAP_MIN_SLOTS;

#define FREE_MIN  4096

static RVALUE *himem, *lomem;

extern st_table *rb_class_tbl;
VALUE *rb_gc_stack_start = 0;
#ifdef __ia64
VALUE *rb_gc_register_stack_start = 0;
#endif

int ruby_gc_stress = 0;


#ifdef DJGPP
/* set stack size (http://www.delorie.com/djgpp/v2faq/faq15_9.html) */
unsigned int _stklen = 0x180000; /* 1.5 kB */
#endif

#if defined(DJGPP) || defined(_WIN32_WCE)
size_t rb_gc_stack_maxsize = 65535*sizeof(VALUE);
#else
size_t rb_gc_stack_maxsize = 655300*sizeof(VALUE);
#endif



static void run_final(VALUE obj);
static int garbage_collect(void);

void
rb_global_variable(VALUE *var)
{
    rb_gc_register_address(var);
}

void
rb_memerror(void)
{
    rb_thread_t *th = GET_THREAD();
    if (!nomem_error ||
	(rb_thread_raised_p(th, RAISED_NOMEMORY) && rb_safe_level() < 4)) {
	fprintf(stderr, "[FATAL] failed to allocate memory\n");
	exit(1);
    }
    rb_thread_raised_set(th, RAISED_NOMEMORY);
    rb_exc_raise(nomem_error);
}

/*
 *  call-seq:
 *    GC.stress                 => true or false
 *
 *  returns current status of GC stress mode.
 */

static VALUE
gc_stress_get(VALUE self)
{
    return ruby_gc_stress ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    GC.stress = bool          => bool
 *
 *  updates GC stress mode.
 *
 *  When GC.stress = true, GC is invoked for all GC opportunity:
 *  all memory and object allocation.
 *
 *  Since it makes Ruby very slow, it is only for debugging.
 */

static VALUE
gc_stress_set(VALUE self, VALUE bool)
{
    rb_secure(2);
    ruby_gc_stress = RTEST(bool);
    return bool;
}

void *
ruby_xmalloc(size_t size)
{
    void *mem;

    if (size < 0) {
	rb_raise(rb_eNoMemError, "negative allocation size (or too big)");
    }
    if (size == 0) size = 1;
    malloc_increase += size;

    if (ruby_gc_stress || malloc_increase > malloc_limit) {
	garbage_collect();
    }
    RUBY_CRITICAL(mem = malloc(size));
    if (!mem) {
	if (garbage_collect()) {
	    RUBY_CRITICAL(mem = malloc(size));
	}
	if (!mem) {
	    rb_memerror();
	}
    }

    return mem;
}

void *
ruby_xmalloc2(size_t n, size_t size)
{
    long len = size * n;
    if (n != 0 && size != len / n) {
	rb_raise(rb_eArgError, "malloc: possible integer overflow");
    }
    return ruby_xmalloc(len);
}

void *
ruby_xcalloc(size_t n, size_t size)
{
    void *mem;

    mem = ruby_xmalloc2(n, size);
    memset(mem, 0, n * size);

    return mem;
}

void *
ruby_xrealloc(void *ptr, size_t size)
{
    void *mem;

    if (size < 0) {
	rb_raise(rb_eArgError, "negative re-allocation size");
    }
    if (!ptr) return ruby_xmalloc(size);
    if (size == 0) size = 1;
    malloc_increase += size;
    if (ruby_gc_stress) garbage_collect();
    RUBY_CRITICAL(mem = realloc(ptr, size));
    if (!mem) {
	if (garbage_collect()) {
	    RUBY_CRITICAL(mem = realloc(ptr, size));
	}
	if (!mem) {
	    rb_memerror();
        }
    }

    return mem;
}

void *
ruby_xrealloc2(void *ptr, size_t n, size_t size)
{
    size_t len = size * n;
    if (n != 0 && size != len / n) {
	rb_raise(rb_eArgError, "realloc: possible integer overflow");
    }
    return ruby_xrealloc(ptr, len);
}

void
ruby_xfree(void *x)
{
    if (x)
	RUBY_CRITICAL(free(x));
}


/*
 *  call-seq:
 *     GC.enable    => true or false
 *
 *  Enables garbage collection, returning <code>true</code> if garbage
 *  collection was previously disabled.
 *
 *     GC.disable   #=> false
 *     GC.enable    #=> true
 *     GC.enable    #=> false
 *
 */

VALUE
rb_gc_enable(void)
{
    int old = dont_gc;

    dont_gc = Qfalse;
    return old;
}

/*
 *  call-seq:
 *     GC.disable    => true or false
 *
 *  Disables garbage collection, returning <code>true</code> if garbage
 *  collection was already disabled.
 *
 *     GC.disable   #=> false
 *     GC.disable   #=> true
 *
 */

VALUE
rb_gc_disable(void)
{
    int old = dont_gc;

    dont_gc = Qtrue;
    return old;
}

VALUE rb_mGC;

static struct gc_list {
    VALUE *varptr;
    struct gc_list *next;
} *global_List = 0;

void
rb_gc_register_address(VALUE *addr)
{
    struct gc_list *tmp;

    tmp = ALLOC(struct gc_list);
    tmp->next = global_List;
    tmp->varptr = addr;
    global_List = tmp;
}

void
rb_register_mark_object(VALUE obj)
{
    VALUE ary = GET_THREAD()->vm->mark_object_ary;
    rb_ary_push(ary, obj);
}

void
rb_gc_unregister_address(VALUE *addr)
{
    struct gc_list *tmp = global_List;

    if (tmp->varptr == addr) {
	global_List = tmp->next;
	RUBY_CRITICAL(free(tmp));
	return;
    }
    while (tmp->next) {
	if (tmp->next->varptr == addr) {
	    struct gc_list *t = tmp->next;

	    tmp->next = tmp->next->next;
	    RUBY_CRITICAL(free(t));
	    break;
	}
	tmp = tmp->next;
    }
}

static void
add_heap(void)
{
    RVALUE *p, *pend, *membase;
    long hi, lo, mid;

    if (heaps_used == heaps_length) {
	/* Realloc heaps */
	struct heaps_slot *p;
	int length;

	heaps_length += HEAPS_INCREMENT;
	length = heaps_length*sizeof(struct heaps_slot);
	RUBY_CRITICAL(
	    if (heaps_used > 0) {
		p = (struct heaps_slot *)realloc(heaps, length);
		if (p) heaps = p;
	    }
	    else {
		p = heaps = (struct heaps_slot *)malloc(length);
	    });
	if (p == 0) rb_memerror();
    }

    for (;;) {
	RUBY_CRITICAL(p = (RVALUE*)malloc(sizeof(RVALUE)*(heap_slots+1)));
	if (p == 0) {
	    if (heap_slots == HEAP_MIN_SLOTS) {
		rb_memerror();
	    }
	    heap_slots = HEAP_MIN_SLOTS;
	}
	else {
	    break;
	}
    }

    lo = 0;
    hi = heaps_used;
    while (lo < hi) {
	mid = (lo + hi) / 2;
	membase = heaps[mid].membase;
	if (membase < p) {
	    lo = mid + 1;
	}
	else if (membase > p) {
	    hi = mid;
	}
	else {
	    rb_bug("same heap slot is allocated: %p at %ld", p, mid);
	}
    }

    membase = p;
    if ((VALUE)p % sizeof(RVALUE) == 0)
	heap_slots += 1;
    else
	p = (RVALUE*)((VALUE)p + sizeof(RVALUE) - ((VALUE)p % sizeof(RVALUE)));
    if (hi < heaps_used) {
	MEMMOVE(&heaps[hi+1], &heaps[hi], struct heaps_slot, heaps_used - hi);
    }
    heaps[hi].membase = membase;
    heaps[hi].slot = p;
    heaps[hi].limit = heap_slots;
    pend = p + heap_slots;
    if (lomem == 0 || lomem > p) lomem = p;
    if (himem < pend) himem = pend;
    heaps_used++;
    heap_slots *= 1.8;

    while (p < pend) {
	p->as.free.flags = 0;
	p->as.free.next = freelist;
	freelist = p;
	p++;
    }
}

#define RANY(o) ((RVALUE*)(o))

static VALUE
rb_newobj_from_heap(void)
{
    VALUE obj;

    if (ruby_gc_stress || !freelist) {
	if(!garbage_collect()) {
	    rb_memerror();
	}
    }

    obj = (VALUE)freelist;
    freelist = freelist->as.free.next;

    MEMZERO((void*)obj, RVALUE, 1);
#ifdef GC_DEBUG
    RANY(obj)->file = rb_sourcefile();
    RANY(obj)->line = rb_sourceline();
#endif
    return obj;
}

#if USE_VALUE_CACHE
static VALUE
rb_fill_value_cache(rb_thread_t *th)
{
    int i;
    VALUE rv;

    /* LOCK */
    for (i=0; i<RUBY_VM_VALUE_CACHE_SIZE; i++) {
	VALUE v = rb_newobj_from_heap();

	th->value_cache[i] = v;
	RBASIC(v)->flags = FL_MARK;
    }
    th->value_cache_ptr = &th->value_cache[0];
    rv = rb_newobj_from_heap();
    /* UNLOCK */
    return rv;
}
#endif

VALUE
rb_newobj(void)
{
#if USE_VALUE_CACHE
    rb_thread_t *th = GET_THREAD();
    VALUE v = *th->value_cache_ptr;

    if (v) {
	RBASIC(v)->flags = 0;
	th->value_cache_ptr++;
    }
    else {
	v = rb_fill_value_cache(th);
    }

#if defined(GC_DEBUG)
    printf("cache index: %d, v: %p, th: %p\n",
	   th->value_cache_ptr - th->value_cache, v, th);
#endif
    return v;
#else
    return rb_newobj_from_heap();
#endif
}

NODE*
rb_node_newnode(enum node_type type, VALUE a0, VALUE a1, VALUE a2)
{
    NODE *n = (NODE*)rb_newobj();

    n->flags |= T_NODE;
    nd_set_type(n, type);

    n->u1.value = a0;
    n->u2.value = a1;
    n->u3.value = a2;

    return n;
}

VALUE
rb_data_object_alloc(VALUE klass, void *datap, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    NEWOBJ(data, struct RData);
    if (klass) Check_Type(klass, T_CLASS);
    OBJSETUP(data, klass, T_DATA);
    data->data = datap;
    data->dfree = dfree;
    data->dmark = dmark;

    return (VALUE)data;
}

#ifdef __ia64
#define SET_STACK_END (SET_MACHINE_STACK_END(&th->machine_stack_end), th->machine_register_stack_end = rb_ia64_bsp())
#else
#define SET_STACK_END SET_MACHINE_STACK_END(&th->machine_stack_end)
#endif

#define STACK_START (th->machine_stack_start)
#define STACK_END (th->machine_stack_end)
#define STACK_LEVEL_MAX (th->machine_stack_maxsize/sizeof(VALUE))

#if STACK_GROW_DIRECTION < 0
# define STACK_LENGTH  (STACK_START - STACK_END)
#elif STACK_GROW_DIRECTION > 0
# define STACK_LENGTH  (STACK_END - STACK_START + 1)
#else
# define STACK_LENGTH  ((STACK_END < STACK_START) ? STACK_START - STACK_END\
                                           : STACK_END - STACK_START + 1)
#endif
#if STACK_GROW_DIRECTION > 0
# define STACK_UPPER(x, a, b) a
#elif STACK_GROW_DIRECTION < 0
# define STACK_UPPER(x, a, b) b
#else
static int grow_direction;
static int
stack_grow_direction(VALUE *addr)
{
    rb_thread_t *th = GET_THREAD();
    SET_STACK_END;

    if (STACK_END > addr) return grow_direction = 1;
    return grow_direction = -1;
}
# define stack_growup_p(x) ((grow_direction ? grow_direction : stack_grow_direction(x)) > 0)
# define STACK_UPPER(x, a, b) (stack_growup_p(x) ? a : b)
#endif

#define GC_WATER_MARK 512

int
ruby_stack_length(VALUE **p)
{
    rb_thread_t *th = GET_THREAD();
    SET_STACK_END;
    if (p) *p = STACK_UPPER(STACK_END, STACK_START, STACK_END);
    return STACK_LENGTH;
}

int
ruby_stack_check(void)
{
    int ret;
    rb_thread_t *th = GET_THREAD();
    SET_STACK_END;
    ret = STACK_LENGTH > STACK_LEVEL_MAX + GC_WATER_MARK;
#ifdef __ia64
    if (!ret) {
        ret = (VALUE*)rb_ia64_bsp() - th->machine_register_stack_start >
              th->machine_register_stack_maxsize/sizeof(VALUE) + GC_WATER_MARK;
    }
#endif
    return ret;
}

static void
init_mark_stack(void)
{
    mark_stack_overflow = 0;
    mark_stack_ptr = mark_stack;
}

#define MARK_STACK_EMPTY (mark_stack_ptr == mark_stack)

static st_table *source_filenames;

char *
rb_source_filename(const char *f)
{
    st_data_t name;

    if (!st_lookup(source_filenames, (st_data_t)f, &name)) {
	long len = strlen(f) + 1;
	char *ptr = ALLOC_N(char, len + 1);

	name = (st_data_t)ptr;
	*ptr++ = 0;
	MEMCPY(ptr, f, char, len);
	st_add_direct(source_filenames, (st_data_t)ptr, name);
	return ptr;
    }
    return (char *)name + 1;
}

void
rb_mark_source_filename(char *f)
{
    if (f) {
	f[-1] = 1;
    }
}

static int
sweep_source_filename(char *key, char *value)
{
    if (*value) {
	*value = 0;
	return ST_CONTINUE;
    }
    else {
	free(value);
	return ST_DELETE;
    }
}

static void gc_mark(VALUE ptr, int lev);
static void gc_mark_children(VALUE ptr, int lev);

static void
gc_mark_all(void)
{
    RVALUE *p, *pend;
    int i;

    init_mark_stack();
    for (i = 0; i < heaps_used; i++) {
	p = heaps[i].slot; pend = p + heaps[i].limit;
	while (p < pend) {
	    if ((p->as.basic.flags & FL_MARK) &&
		(p->as.basic.flags != FL_MARK)) {
		gc_mark_children((VALUE)p, 0);
	    }
	    p++;
	}
    }
}

static void
gc_mark_rest(void)
{
    VALUE tmp_arry[MARK_STACK_MAX];
    VALUE *p;

    p = (mark_stack_ptr - mark_stack) + tmp_arry;
    MEMCPY(tmp_arry, mark_stack, VALUE, p - tmp_arry);

    init_mark_stack();
    while (p != tmp_arry) {
	p--;
	gc_mark_children(*p, 0);
    }
}

static inline int
is_pointer_to_heap(void *ptr)
{
    register RVALUE *p = RANY(ptr);
    register struct heaps_slot *heap;
    register long hi, lo, mid;

    if (p < lomem || p > himem) return Qfalse;
    if ((VALUE)p % sizeof(RVALUE) != 0) return Qfalse;

    /* check if p looks like a pointer using bsearch*/
    lo = 0;
    hi = heaps_used;
    while (lo < hi) {
	mid = (lo + hi) / 2;
	heap = &heaps[mid];
	if (heap->slot <= p) {
	    if (p < heap->slot + heap->limit)
		return Qtrue;
	    lo = mid + 1;
	}
	else {
	    hi = mid;
	}
    }
    return Qfalse;
}

static void
mark_locations_array(register VALUE *x, register long n)
{
    VALUE v;
    while (n--) {
        v = *x;
        VALGRIND_MAKE_MEM_DEFINED(&v, sizeof(v));
	if (is_pointer_to_heap((void *)v)) {
	    gc_mark(v, 0);
	}
	x++;
    }
}

void
rb_gc_mark_locations(VALUE *start, VALUE *end)
{
    long n;

    n = end - start;
    mark_locations_array(start,n);
}

static int
mark_entry(ID key, VALUE value, int lev)
{
    gc_mark(value, lev);
    return ST_CONTINUE;
}

static void
mark_tbl(st_table *tbl, int lev)
{
    if (!tbl) return;
    st_foreach(tbl, mark_entry, lev);
}

void
rb_mark_tbl(st_table *tbl)
{
    mark_tbl(tbl, 0);
}

static int
mark_key(VALUE key, VALUE value, int lev)
{
    gc_mark(key, lev);
    return ST_CONTINUE;
}

static void
mark_set(st_table *tbl, int lev)
{
    if (!tbl) return;
    st_foreach(tbl, mark_key, lev);
}

void
rb_mark_set(st_table *tbl)
{
    mark_set(tbl, 0);
}

static int
mark_keyvalue(VALUE key, VALUE value, int lev)
{
    gc_mark(key, lev);
    gc_mark(value, lev);
    return ST_CONTINUE;
}

static void
mark_hash(st_table *tbl, int lev)
{
    if (!tbl) return;
    st_foreach(tbl, mark_keyvalue, lev);
}

void
rb_mark_hash(st_table *tbl)
{
    mark_hash(tbl, 0);
}

void
rb_gc_mark_maybe(VALUE obj)
{
    if (is_pointer_to_heap((void *)obj)) {
	gc_mark(obj, 0);
    }
}

#define GC_LEVEL_MAX 250

static void
gc_mark(VALUE ptr, int lev)
{
    register RVALUE *obj;

    obj = RANY(ptr);
    if (rb_special_const_p(ptr)) return; /* special const not marked */
    if (obj->as.basic.flags == 0) return;       /* free cell */
    if (obj->as.basic.flags & FL_MARK) return;  /* already marked */
    obj->as.basic.flags |= FL_MARK;

    if (lev > GC_LEVEL_MAX || (lev == 0 && ruby_stack_check())) {
	if (!mark_stack_overflow) {
	    if (mark_stack_ptr - mark_stack < MARK_STACK_MAX) {
		*mark_stack_ptr = ptr;
		mark_stack_ptr++;
	    }
	    else {
		mark_stack_overflow = 1;
	    }
	}
	return;
    }
    gc_mark_children(ptr, lev+1);
}

void
rb_gc_mark(VALUE ptr)
{
    gc_mark(ptr, 0);
}

static void
gc_mark_children(VALUE ptr, int lev)
{
    register RVALUE *obj = RANY(ptr);

    goto marking;		/* skip */

  again:
    obj = RANY(ptr);
    if (rb_special_const_p(ptr)) return; /* special const not marked */
    if (obj->as.basic.flags == 0) return;       /* free cell */
    if (obj->as.basic.flags & FL_MARK) return;  /* already marked */
    obj->as.basic.flags |= FL_MARK;

  marking:
    if (FL_TEST(obj, FL_EXIVAR)) {
	rb_mark_generic_ivar(ptr);
    }

    switch (obj->as.basic.flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	rb_bug("rb_gc_mark() called for broken object");
	break;

      case T_NODE:
	rb_mark_source_filename(obj->as.node.nd_file);
	switch (nd_type(obj)) {
	  case NODE_IF:		/* 1,2,3 */
	  case NODE_FOR:
	  case NODE_ITER:
	  case NODE_WHEN:
	  case NODE_MASGN:
	  case NODE_RESCUE:
	  case NODE_RESBODY:
	  case NODE_CLASS:
	  case NODE_BLOCK_PASS:
	    gc_mark((VALUE)obj->as.node.u2.node, lev);
	    /* fall through */
	  case NODE_BLOCK:	/* 1,3 */
	  case NODE_OPTBLOCK:
	  case NODE_ARRAY:
	  case NODE_DSTR:
	  case NODE_DXSTR:
	  case NODE_DREGX:
	  case NODE_DREGX_ONCE:
	  case NODE_ENSURE:
	  case NODE_CALL:
	  case NODE_DEFS:
	  case NODE_OP_ASGN1:
	  case NODE_ARGS:
	    gc_mark((VALUE)obj->as.node.u1.node, lev);
	    /* fall through */
	  case NODE_SUPER:	/* 3 */
	  case NODE_FCALL:
	  case NODE_DEFN:
	  case NODE_ARGS_AUX:
	    ptr = (VALUE)obj->as.node.u3.node;
	    goto again;

	  case NODE_METHOD:	/* 1,2 */
	  case NODE_WHILE:
	  case NODE_UNTIL:
	  case NODE_AND:
	  case NODE_OR:
	  case NODE_CASE:
	  case NODE_SCLASS:
	  case NODE_DOT2:
	  case NODE_DOT3:
	  case NODE_FLIP2:
	  case NODE_FLIP3:
	  case NODE_MATCH2:
	  case NODE_MATCH3:
	  case NODE_OP_ASGN_OR:
	  case NODE_OP_ASGN_AND:
	  case NODE_MODULE:
	  case NODE_ALIAS:
	  case NODE_VALIAS:
	  case NODE_ARGSCAT:
	    gc_mark((VALUE)obj->as.node.u1.node, lev);
	    /* fall through */
	  case NODE_FBODY:	/* 2 */
	  case NODE_GASGN:
	  case NODE_LASGN:
	  case NODE_DASGN:
	  case NODE_DASGN_CURR:
	  case NODE_IASGN:
	  case NODE_IASGN2:
	  case NODE_CVASGN:
	  case NODE_COLON3:
	  case NODE_OPT_N:
	  case NODE_EVSTR:
	  case NODE_UNDEF:
	  case NODE_POSTEXE:
	    ptr = (VALUE)obj->as.node.u2.node;
	    goto again;

	  case NODE_HASH:	/* 1 */
	  case NODE_LIT:
	  case NODE_STR:
	  case NODE_XSTR:
	  case NODE_DEFINED:
	  case NODE_MATCH:
	  case NODE_RETURN:
	  case NODE_BREAK:
	  case NODE_NEXT:
	  case NODE_YIELD:
	  case NODE_COLON2:
	  case NODE_SPLAT:
	  case NODE_TO_ARY:
	    ptr = (VALUE)obj->as.node.u1.node;
	    goto again;

	  case NODE_SCOPE:	/* 2,3 */
	  case NODE_CDECL:
	  case NODE_OPT_ARG:
	    gc_mark((VALUE)obj->as.node.u3.node, lev);
	    ptr = (VALUE)obj->as.node.u2.node;
	    goto again;

	  case NODE_ZARRAY:	/* - */
	  case NODE_ZSUPER:
	  case NODE_CFUNC:
	  case NODE_VCALL:
	  case NODE_GVAR:
	  case NODE_LVAR:
	  case NODE_DVAR:
	  case NODE_IVAR:
	  case NODE_CVAR:
	  case NODE_NTH_REF:
	  case NODE_BACK_REF:
	  case NODE_REDO:
	  case NODE_RETRY:
	  case NODE_SELF:
	  case NODE_NIL:
	  case NODE_TRUE:
	  case NODE_FALSE:
	  case NODE_ERRINFO:
	  case NODE_ATTRSET:
	  case NODE_BLOCK_ARG:
	    break;
	  case NODE_ALLOCA:
	    mark_locations_array((VALUE*)obj->as.node.u1.value,
				 obj->as.node.u3.cnt);
	    ptr = (VALUE)obj->as.node.u2.node;
	    goto again;

	  default:		/* unlisted NODE */
	    if (is_pointer_to_heap(obj->as.node.u1.node)) {
		gc_mark((VALUE)obj->as.node.u1.node, lev);
	    }
	    if (is_pointer_to_heap(obj->as.node.u2.node)) {
		gc_mark((VALUE)obj->as.node.u2.node, lev);
	    }
	    if (is_pointer_to_heap(obj->as.node.u3.node)) {
		gc_mark((VALUE)obj->as.node.u3.node, lev);
	    }
	}
	return;			/* no need to mark class. */
    }

    gc_mark(obj->as.basic.klass, lev);
    switch (obj->as.basic.flags & T_MASK) {
      case T_ICLASS:
      case T_CLASS:
      case T_MODULE:
	mark_tbl(RCLASS_M_TBL(obj), lev);
	mark_tbl(RCLASS_IV_TBL(obj), lev);
	ptr = RCLASS_SUPER(obj);
	goto again;

      case T_ARRAY:
	if (FL_TEST(obj, ELTS_SHARED)) {
	    ptr = obj->as.array.aux.shared;
	    goto again;
	}
	else {
	    long i, len = RARRAY_LEN(obj);
	    VALUE *ptr = RARRAY_PTR(obj);
	    for (i=0; i < len; i++) {
		gc_mark(*ptr++, lev);
	    }
	}
	break;

      case T_HASH:
	mark_hash(obj->as.hash.ntbl, lev);
	ptr = obj->as.hash.ifnone;
	goto again;

      case T_STRING:
#define STR_ASSOC FL_USER3   /* copied from string.c */
	if (FL_TEST(obj, RSTRING_NOEMBED) && FL_ANY(obj, ELTS_SHARED|STR_ASSOC)) {
	    ptr = obj->as.string.as.heap.aux.shared;
	    goto again;
	}
	break;

      case T_DATA:
	if (obj->as.data.dmark) (*obj->as.data.dmark)(DATA_PTR(obj));
	break;

      case T_OBJECT:
        {
            long i, len = ROBJECT_NUMIV(obj);
	    VALUE *ptr = ROBJECT_IVPTR(obj);
            for (i  = 0; i < len; i++) {
		gc_mark(*ptr++, lev);
            }
        }
	break;

      case T_FILE:
        if (obj->as.file.fptr)
            gc_mark(obj->as.file.fptr->tied_io_for_writing, lev);
        break;

      case T_REGEXP:
      case T_FLOAT:
      case T_BIGNUM:
      case T_BLOCK:
	break;

      case T_MATCH:
	gc_mark(obj->as.match.regexp, lev);
	if (obj->as.match.str) {
	    ptr = obj->as.match.str;
	    goto again;
	}
	break;

      case T_RATIONAL:
	gc_mark(obj->as.rational.num, lev);
	gc_mark(obj->as.rational.den, lev);
	break;

      case T_COMPLEX:
	gc_mark(obj->as.complex.real, lev);
	gc_mark(obj->as.complex.image, lev);
	break;

      case T_STRUCT:
	{
	    long len = RSTRUCT_LEN(obj);
	    VALUE *ptr = RSTRUCT_PTR(obj);

	    while (len--) {
		gc_mark(*ptr++, lev);
	    }
	}
	break;

      case T_VALUES:
	{
            rb_gc_mark(RVALUES(obj)->v1);
            rb_gc_mark(RVALUES(obj)->v2);
            ptr = RVALUES(obj)->v3;
            goto again;
	}
	break;

      default:
	rb_bug("rb_gc_mark(): unknown data type 0x%lx(%p) %s",
	       obj->as.basic.flags & T_MASK, obj,
	       is_pointer_to_heap(obj) ? "corrupted object" : "non object");
    }
}

static void obj_free(VALUE);

static void
finalize_list(RVALUE *p)
{
    while (p) {
	RVALUE *tmp = p->as.free.next;
	run_final((VALUE)p);
	if (!FL_TEST(p, FL_SINGLETON)) { /* not freeing page */
            VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
	    p->as.free.flags = 0;
	    p->as.free.next = freelist;
	    freelist = p;
	}
	p = tmp;
    }
}

static void
free_unused_heaps(void)
{
    int i, j;

    for (i = j = 1; j < heaps_used; i++) {
	if (heaps[i].limit == 0) {
	    free(heaps[i].membase);
	    heaps_used--;
	}
	else {
	    if (i != j) {
		heaps[j] = heaps[i];
	    }
	    j++;
	}
    }
}

void rb_gc_abort_threads(void);

static void
gc_sweep(void)
{
    RVALUE *p, *pend, *final_list;
    int freed = 0;
    int i;
    unsigned long live = 0;
    unsigned long free_min = 0;

    for (i = 0; i < heaps_used; i++) {
        free_min += heaps[i].limit;
    }
    free_min = free_min * 0.2;
    if (free_min < FREE_MIN)
        free_min = FREE_MIN;

    if (source_filenames) {
        st_foreach(source_filenames, sweep_source_filename, 0);
    }

    freelist = 0;
    final_list = deferred_final_list;
    deferred_final_list = 0;
    for (i = 0; i < heaps_used; i++) {
	int n = 0;
	RVALUE *free = freelist;
	RVALUE *final = final_list;

	p = heaps[i].slot; pend = p + heaps[i].limit;
	while (p < pend) {
	    if (!(p->as.basic.flags & FL_MARK)) {
		if (p->as.basic.flags) {
		    obj_free((VALUE)p);
		}
		if (need_call_final && FL_TEST(p, FL_FINALIZE)) {
		    p->as.free.flags = FL_MARK; /* remain marked */
		    p->as.free.next = final_list;
		    final_list = p;
		}
		else {
                    VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
		    p->as.free.flags = 0;
		    p->as.free.next = freelist;
		    freelist = p;
		}
		n++;
	    }
	    else if (RBASIC(p)->flags == FL_MARK) {
		/* objects to be finalized */
		/* do nothing remain marked */
	    }
	    else {
		RBASIC(p)->flags &= ~FL_MARK;
		live++;
	    }
	    p++;
	}
	if (n == heaps[i].limit && freed > free_min) {
	    RVALUE *pp;

	    heaps[i].limit = 0;
	    for (pp = final_list; pp != final; pp = pp->as.free.next) {
		p->as.free.flags |= FL_SINGLETON; /* freeing page mark */
	    }
	    freelist = free;	/* cancel this page from freelist */
	}
	else {
	    freed += n;
	}
    }
    if (malloc_increase > malloc_limit) {
	malloc_limit += (malloc_increase - malloc_limit) * (double)live / (live + freed);
	if (malloc_limit < GC_MALLOC_LIMIT) malloc_limit = GC_MALLOC_LIMIT;
    }
    malloc_increase = 0;
    if (freed < free_min) {
	add_heap();
    }
    during_gc = 0;

    /* clear finalization list */
    if (final_list) {
	deferred_final_list = final_list;
	return;
    }
    free_unused_heaps();
}

void
rb_gc_force_recycle(VALUE p)
{
    VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
    RANY(p)->as.free.flags = 0;
    RANY(p)->as.free.next = freelist;
    freelist = RANY(p);
}

static void
obj_free(VALUE obj)
{
    switch (RANY(obj)->as.basic.flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
      case T_TRUE:
      case T_FALSE:
	rb_bug("obj_free() called for broken object");
	break;
    }

    if (FL_TEST(obj, FL_EXIVAR)) {
	rb_free_generic_ivar((VALUE)obj);
    }

    switch (RANY(obj)->as.basic.flags & T_MASK) {
      case T_OBJECT:
	if (!(RANY(obj)->as.basic.flags & ROBJECT_EMBED) &&
            RANY(obj)->as.object.as.heap.ivptr) {
	    RUBY_CRITICAL(free(RANY(obj)->as.object.as.heap.ivptr));
	}
	break;
      case T_MODULE:
      case T_CLASS:
	rb_clear_cache_by_class((VALUE)obj);
	st_free_table(RCLASS_M_TBL(obj));
	if (RCLASS_IV_TBL(obj)) {
	    st_free_table(RCLASS_IV_TBL(obj));
	}
	if (RCLASS_IV_INDEX_TBL(obj)) {
	    st_free_table(RCLASS_IV_INDEX_TBL(obj));
	}
        RUBY_CRITICAL(free(RANY(obj)->as.klass.ptr));
	break;
      case T_STRING:
	rb_str_free(obj);
	break;
      case T_ARRAY:
	rb_ary_free(obj);
	break;
      case T_HASH:
	if (RANY(obj)->as.hash.ntbl) {
	    st_free_table(RANY(obj)->as.hash.ntbl);
	}
	break;
      case T_REGEXP:
	if (RANY(obj)->as.regexp.ptr) {
	    onig_free(RANY(obj)->as.regexp.ptr);
	}
	if (RANY(obj)->as.regexp.str) {
	    RUBY_CRITICAL(free(RANY(obj)->as.regexp.str));
	}
	break;
      case T_DATA:
	if (DATA_PTR(obj)) {
	    if ((long)RANY(obj)->as.data.dfree == -1) {
		RUBY_CRITICAL(free(DATA_PTR(obj)));
	    }
	    else if (RANY(obj)->as.data.dfree) {
		(*RANY(obj)->as.data.dfree)(DATA_PTR(obj));
	    }
	}
	break;
      case T_MATCH:
	if (RANY(obj)->as.match.rmatch) {
            struct rmatch *rm = RANY(obj)->as.match.rmatch;
	    onig_region_free(&rm->regs, 0);
            if (rm->char_offset)
                RUBY_CRITICAL(free(rm->char_offset));
	    RUBY_CRITICAL(free(rm));
	}
	break;
      case T_FILE:
	if (RANY(obj)->as.file.fptr) {
	    rb_io_fptr_finalize(RANY(obj)->as.file.fptr);
	}
	break;
      case T_RATIONAL:
      case T_COMPLEX:
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
	break;

      case T_FLOAT:
      case T_BLOCK:
	break;
      case T_VALUES:
	break;

      case T_BIGNUM:
	if (!(RBASIC(obj)->flags & RBIGNUM_EMBED_FLAG) && RBIGNUM_DIGITS(obj)) {
	    RUBY_CRITICAL(free(RBIGNUM_DIGITS(obj)));
	}
	break;
      case T_NODE:
	switch (nd_type(obj)) {
	  case NODE_SCOPE:
	    if (RANY(obj)->as.node.u1.tbl) {
		RUBY_CRITICAL(free(RANY(obj)->as.node.u1.tbl));
	    }
	    break;
	  case NODE_ALLOCA:
	    RUBY_CRITICAL(free(RANY(obj)->as.node.u1.node));
	    break;
	}
	return;			/* no need to free iv_tbl */

      case T_STRUCT:
	if ((RBASIC(obj)->flags & RSTRUCT_EMBED_LEN_MASK) == 0 &&
	    RANY(obj)->as.rstruct.as.heap.ptr) {
	    RUBY_CRITICAL(free(RANY(obj)->as.rstruct.as.heap.ptr));
	}
	break;

      default:
	rb_bug("gc_sweep(): unknown data type 0x%lx(%p)",
	       RANY(obj)->as.basic.flags & T_MASK, (void*)obj);
    }
}

#ifdef __GNUC__
#if defined(__human68k__) || defined(DJGPP)
#undef rb_setjmp
#undef rb_jmp_buf
#if defined(__human68k__)
typedef unsigned long rb_jmp_buf[8];
__asm__ (".even\n\
_rb_setjmp:\n\
	move.l	4(sp),a0\n\
	movem.l	d3-d7/a3-a5,(a0)\n\
	moveq.l	#0,d0\n\
	rts");
#else
#if defined(DJGPP)
typedef unsigned long rb_jmp_buf[6];
__asm__ (".align 4\n\
_rb_setjmp:\n\
	pushl	%ebp\n\
	movl	%esp,%ebp\n\
	movl	8(%ebp),%ebp\n\
	movl	%eax,(%ebp)\n\
	movl	%ebx,4(%ebp)\n\
	movl	%ecx,8(%ebp)\n\
	movl	%edx,12(%ebp)\n\
	movl	%esi,16(%ebp)\n\
	movl	%edi,20(%ebp)\n\
	popl	%ebp\n\
	xorl	%eax,%eax\n\
	ret");
#endif
#endif
int rb_setjmp (rb_jmp_buf);
#endif /* __human68k__ or DJGPP */
#endif /* __GNUC__ */

#define GC_NOTIFY 0

void rb_vm_mark(void *ptr);

static void
mark_current_machine_context(rb_thread_t *th)
{
    rb_jmp_buf save_regs_gc_mark;
    VALUE *stack_start, *stack_end;

    SET_STACK_END;
#if STACK_GROW_DIRECTION < 0
    stack_start = th->machine_stack_end;
    stack_end = th->machine_stack_start;
#elif STACK_GROW_DIRECTION > 0
    stack_start = th->machine_stack_start;
    stack_end = th->machine_stack_end + 1;
#else
    if (th->machine_stack_end < th->machine_stack_start) {
        stack_start = th->machine_stack_end;
        stack_end = th->machine_stack_start;
    }
    else {
        stack_start = th->machine_stack_start;
        stack_end = th->machine_stack_end + 1;
    }
#endif

    FLUSH_REGISTER_WINDOWS;
    /* This assumes that all registers are saved into the jmp_buf (and stack) */
    rb_setjmp(save_regs_gc_mark);
    mark_locations_array((VALUE*)save_regs_gc_mark,
			 sizeof(save_regs_gc_mark) / sizeof(VALUE));

    mark_locations_array(stack_start, stack_end - stack_start);
#ifdef __ia64
    mark_locations_array(th->machine_register_stack_start,
			 th->machine_register_stack_end - th->machine_register_stack_start);
#endif
#if defined(__human68k__) || defined(__mc68000__)
    mark_locations_array((VALUE*)((char*)STACK_END + 2),
			 (STACK_START - STACK_END));
#endif
}

void rb_gc_mark_encodings(void);

static int
garbage_collect(void)
{
    struct gc_list *list;
    rb_thread_t *th = GET_THREAD();

    if (GC_NOTIFY) printf("start garbage_collect()\n");

    if (!heaps) {
	return Qfalse;
    }

    if (dont_gc || during_gc) {
	if (!freelist) {
	    add_heap();
	}
	return Qtrue;
    }
    during_gc++;

    SET_STACK_END;

    init_mark_stack();

    th->vm->self ? rb_gc_mark(th->vm->self) : rb_vm_mark(th->vm);

    if (finalizer_table) {
	mark_tbl(finalizer_table, 0);
    }

    mark_current_machine_context(th);

    rb_gc_mark_threads();
    rb_gc_mark_symbols();
    rb_gc_mark_encodings();

    /* mark protected global variables */
    for (list = global_List; list; list = list->next) {
	rb_gc_mark_maybe(*list->varptr);
    }
    rb_mark_end_proc();
    rb_gc_mark_global_tbl();

    rb_mark_tbl(rb_class_tbl);
    rb_gc_mark_trap_list();

    /* mark generic instance variables for special constants */
    rb_mark_generic_ivar_tbl();

    rb_gc_mark_parser();

    /* gc_mark objects whose marking are not completed*/
    while (!MARK_STACK_EMPTY) {
	if (mark_stack_overflow) {
	    gc_mark_all();
	}
	else {
	    gc_mark_rest();
	}
    }

    gc_sweep();
    if (GC_NOTIFY) printf("end garbage_collect()\n");
    return Qtrue;
}

int
rb_garbage_collect(void)
{
    return garbage_collect();
}

void
rb_gc_mark_machine_stack(rb_thread_t *th)
{
#if STACK_GROW_DIRECTION < 0
    rb_gc_mark_locations(th->machine_stack_end, th->machine_stack_start);
#elif STACK_GROW_DIRECTION > 0
    rb_gc_mark_locations(th->machine_stack_start, th->machine_stack_end);
#else
    if (th->machine_stack_start < th->machine_stack_end) {
	rb_gc_mark_locations(th->machine_stack_start, th->machine_stack_end);
    }
    else {
	rb_gc_mark_locations(th->machine_stack_end, th->machine_stack_start);
    }
#endif
#ifdef __ia64
    rb_gc_mark_locations(th->machine_register_stack_start, th->machine_register_stack_end);
#endif
}


void
rb_gc(void)
{
    garbage_collect();
    rb_gc_finalize_deferred();
}

/*
 *  call-seq:
 *     GC.start                     => nil
 *     gc.garbage_collect           => nil
 *     ObjectSpace.garbage_collect  => nil
 *
 *  Initiates garbage collection, unless manually disabled.
 *
 */

VALUE
rb_gc_start(void)
{
    rb_gc();
    return Qnil;
}

void
ruby_set_stack_size(size_t size)
{
    rb_gc_stack_maxsize = size;
}

void
Init_stack(VALUE *addr)
{
#ifdef __ia64
    if (rb_gc_register_stack_start == 0) {
# if defined(__FreeBSD__)
        /*
         * FreeBSD/ia64 currently does not have a way for a process to get the
         * base address for the RSE backing store, so hardcode it.
         */
        rb_gc_register_stack_start = (4ULL<<61);
# elif defined(HAVE___LIBC_IA64_REGISTER_BACKING_STORE_BASE)
#  pragma weak __libc_ia64_register_backing_store_base
        extern unsigned long __libc_ia64_register_backing_store_base;
        rb_gc_register_stack_start = (VALUE*)__libc_ia64_register_backing_store_base;
# endif
    }
    {
        VALUE *bsp = (VALUE*)rb_ia64_bsp();
        if (rb_gc_register_stack_start == 0 ||
            bsp < rb_gc_register_stack_start) {
            rb_gc_register_stack_start = bsp;
        }
    }
#endif
#if defined(_WIN32) || defined(__CYGWIN__)
    MEMORY_BASIC_INFORMATION m;
    memset(&m, 0, sizeof(m));
    VirtualQuery(&m, &m, sizeof(m));
    rb_gc_stack_start =
	STACK_UPPER((VALUE *)&m, (VALUE *)m.BaseAddress,
		    (VALUE *)((char *)m.BaseAddress + m.RegionSize) - 1);
#elif defined(STACK_END_ADDRESS)
    {
        extern void *STACK_END_ADDRESS;
        rb_gc_stack_start = STACK_END_ADDRESS;
    }
#else
    if (!addr) addr = (VALUE *)&addr;
    STACK_UPPER(&addr, addr, ++addr);
    if (rb_gc_stack_start) {
	if (STACK_UPPER(&addr,
			rb_gc_stack_start > addr,
			rb_gc_stack_start < addr))
	    rb_gc_stack_start = addr;
	return;
    }
    rb_gc_stack_start = addr;
#endif
#ifdef HAVE_GETRLIMIT
    {
	struct rlimit rlim;

	if (getrlimit(RLIMIT_STACK, &rlim) == 0) {
	    unsigned int space = rlim.rlim_cur/5;

	    if (space > 1024*1024) space = 1024*1024;
	    rb_gc_stack_maxsize = rlim.rlim_cur - space;
	}
    }
#endif
}

void ruby_init_stack(VALUE *addr
#ifdef __ia64
    , void *bsp
#endif
    )
{
    if (!rb_gc_stack_start ||
        STACK_UPPER(&addr,
                    rb_gc_stack_start > addr,
                    rb_gc_stack_start < addr)) {
        rb_gc_stack_start = addr;
    }
#ifdef __ia64
    if (!rb_gc_register_stack_start ||
        (VALUE*)bsp < rb_gc_register_stack_start) {
        rb_gc_register_stack_start = (VALUE*)bsp;
    }
#endif
#ifdef HAVE_GETRLIMIT
    {
	struct rlimit rlim;

	if (getrlimit(RLIMIT_STACK, &rlim) == 0) {
	    unsigned int space = rlim.rlim_cur/5;

	    if (space > 1024*1024) space = 1024*1024;
	    rb_gc_stack_maxsize = rlim.rlim_cur - space;
	}
    }
#elif defined _WIN32
    {
	MEMORY_BASIC_INFORMATION mi;
	DWORD size;
	DWORD space;

	if (VirtualQuery(&mi, &mi, sizeof(mi))) {
	    size = (char *)mi.BaseAddress - (char *)mi.AllocationBase;
	    space = size / 5;
	    if (space > 1024*1024) space = 1024*1024;
            rb_gc_stack_maxsize = size - space;
	}
    }
#endif
}

/*
 * Document-class: ObjectSpace
 *
 *  The <code>ObjectSpace</code> module contains a number of routines
 *  that interact with the garbage collection facility and allow you to
 *  traverse all living objects with an iterator.
 *
 *  <code>ObjectSpace</code> also provides support for object
 *  finalizers, procs that will be called when a specific object is
 *  about to be destroyed by garbage collection.
 *
 *     include ObjectSpace
 *
 *
 *     a = "A"
 *     b = "B"
 *     c = "C"
 *
 *
 *     define_finalizer(a, proc {|id| puts "Finalizer one on #{id}" })
 *     define_finalizer(a, proc {|id| puts "Finalizer two on #{id}" })
 *     define_finalizer(b, proc {|id| puts "Finalizer three on #{id}" })
 *
 *  <em>produces:</em>
 *
 *     Finalizer three on 537763470
 *     Finalizer one on 537763480
 *     Finalizer two on 537763480
 *
 */

void
Init_heap(void)
{
    if (!rb_gc_stack_start) {
	Init_stack(0);
    }
    add_heap();
}

static VALUE
os_obj_of(VALUE of)
{
    int i;
    int n = 0;

    for (i = 0; i < heaps_used; i++) {
	RVALUE *p, *pend;

	p = heaps[i].slot; pend = p + heaps[i].limit;
	for (;p < pend; p++) {
	    if (p->as.basic.flags) {
		switch (BUILTIN_TYPE(p)) {
		  case T_NONE:
		  case T_ICLASS:
		  case T_NODE:
		  case T_VALUES:
		    continue;
		  case T_CLASS:
		    if (FL_TEST(p, FL_SINGLETON)) continue;
		  default:
		    if (!p->as.basic.klass) continue;
		    if (!of || rb_obj_is_kind_of((VALUE)p, of)) {
			rb_yield((VALUE)p);
			n++;
		    }
		}
	    }
	}
    }

    return INT2FIX(n);
}

/*
 *  call-seq:
 *     ObjectSpace.each_object([module]) {|obj| ... } => fixnum
 *
 *  Calls the block once for each living, nonimmediate object in this
 *  Ruby process. If <i>module</i> is specified, calls the block
 *  for only those classes or modules that match (or are a subclass of)
 *  <i>module</i>. Returns the number of objects found. Immediate
 *  objects (<code>Fixnum</code>s, <code>Symbol</code>s
 *  <code>true</code>, <code>false</code>, and <code>nil</code>) are
 *  never returned. In the example below, <code>each_object</code>
 *  returns both the numbers we defined and several constants defined in
 *  the <code>Math</code> module.
 *
 *     a = 102.7
 *     b = 95       # Won't be returned
 *     c = 12345678987654321
 *     count = ObjectSpace.each_object(Numeric) {|x| p x }
 *     puts "Total count: #{count}"
 *
 *  <em>produces:</em>
 *
 *     12345678987654321
 *     102.7
 *     2.71828182845905
 *     3.14159265358979
 *     2.22044604925031e-16
 *     1.7976931348623157e+308
 *     2.2250738585072e-308
 *     Total count: 7
 *
 */

static VALUE
os_each_obj(int argc, VALUE *argv, VALUE os)
{
    VALUE of;

    rb_secure(4);
    if (argc == 0) {
	of = 0;
    }
    else {
	rb_scan_args(argc, argv, "01", &of);
    }
    RETURN_ENUMERATOR(os, 1, &of);
    return os_obj_of(of);
}

static VALUE finalizers;

/* deprecated
 */

static VALUE
add_final(VALUE os, VALUE block)
{
    rb_warn("ObjectSpace::add_finalizer is deprecated; use define_finalizer");
    if (!rb_respond_to(block, rb_intern("call"))) {
	rb_raise(rb_eArgError, "wrong type argument %s (should be callable)",
		 rb_obj_classname(block));
    }
    rb_ary_push(finalizers, block);
    return block;
}

/*
 * deprecated
 */
static VALUE
rm_final(VALUE os, VALUE block)
{
    rb_warn("ObjectSpace::remove_finalizer is deprecated; use undefine_finalizer");
    rb_ary_delete(finalizers, block);
    return block;
}

/*
 * deprecated
 */
static VALUE
finals(void)
{
    rb_warn("ObjectSpace::finalizers is deprecated");
    return finalizers;
}

/*
 * deprecated
 */

static VALUE
call_final(VALUE os, VALUE obj)
{
    rb_warn("ObjectSpace::call_finalizer is deprecated; use define_finalizer");
    need_call_final = 1;
    FL_SET(obj, FL_FINALIZE);
    return obj;
}

/*
 *  call-seq:
 *     ObjectSpace.undefine_finalizer(obj)
 *
 *  Removes all finalizers for <i>obj</i>.
 *
 */

static VALUE
undefine_final(VALUE os, VALUE obj)
{
    if (finalizer_table) {
	st_delete(finalizer_table, (st_data_t*)&obj, 0);
    }
    return obj;
}

/*
 *  call-seq:
 *     ObjectSpace.define_finalizer(obj, aProc=proc())
 *
 *  Adds <i>aProc</i> as a finalizer, to be called after <i>obj</i>
 *  was destroyed.
 *
 */

static VALUE
define_final(int argc, VALUE *argv, VALUE os)
{
    VALUE obj, block, table;

    rb_scan_args(argc, argv, "11", &obj, &block);
    if (argc == 1) {
	block = rb_block_proc();
    }
    else if (!rb_respond_to(block, rb_intern("call"))) {
	rb_raise(rb_eArgError, "wrong type argument %s (should be callable)",
		 rb_obj_classname(block));
    }
    need_call_final = 1;
    FL_SET(obj, FL_FINALIZE);

    block = rb_ary_new3(2, INT2FIX(rb_safe_level()), block);

    if (!finalizer_table) {
	finalizer_table = st_init_numtable();
    }
    if (st_lookup(finalizer_table, obj, &table)) {
	rb_ary_push(table, block);
    }
    else {
	st_add_direct(finalizer_table, obj, rb_ary_new3(1, block));
    }
    return block;
}

void
rb_gc_copy_finalizer(VALUE dest, VALUE obj)
{
    VALUE table;

    if (!finalizer_table) return;
    if (!FL_TEST(obj, FL_FINALIZE)) return;
    if (st_lookup(finalizer_table, obj, &table)) {
	st_insert(finalizer_table, dest, table);
    }
    FL_SET(dest, FL_FINALIZE);
}

static VALUE
run_single_final(VALUE arg)
{
    VALUE *args = (VALUE *)arg;
    rb_eval_cmd(args[0], args[1], (int)args[2]);
    return Qnil;
}

static void
run_final(VALUE obj)
{
    long i;
    int status, critical_save = rb_thread_critical;
    VALUE args[3], table, objid;

    objid = rb_obj_id(obj);	/* make obj into id */
    rb_thread_critical = Qtrue;
    args[1] = 0;
    if (RARRAY_LEN(finalizers) > 0) {
	args[1] = rb_obj_freeze(rb_ary_new3(1, objid));
    }
    args[2] = (VALUE)rb_safe_level();
    for (i=0; i<RARRAY_LEN(finalizers); i++) {
	args[0] = RARRAY_PTR(finalizers)[i];
	rb_protect(run_single_final, (VALUE)args, &status);
    }
    if (finalizer_table && st_delete(finalizer_table, (st_data_t*)&obj, &table)) {
	if (!args[1] && RARRAY_LEN(table) > 0) {
	    args[1] = rb_obj_freeze(rb_ary_new3(1, objid));
	}
	for (i=0; i<RARRAY_LEN(table); i++) {
	    VALUE final = RARRAY_PTR(table)[i];
	    args[0] = RARRAY_PTR(final)[1];
	    args[2] = FIX2INT(RARRAY_PTR(final)[0]);
	    rb_protect(run_single_final, (VALUE)args, &status);
	}
    }
    rb_thread_critical = critical_save;
}

void
rb_gc_finalize_deferred(void)
{
    RVALUE *p = deferred_final_list;

    during_gc++;
    deferred_final_list = 0;
    if (p) {
	finalize_list(p);
    }
    free_unused_heaps();
    during_gc = 0;
}

void
rb_gc_call_finalizer_at_exit(void)
{
    RVALUE *p, *pend;
    int i;

    /* finalizers are part of garbage collection */
    during_gc++;
    /* run finalizers */
    if (need_call_final) {
	p = deferred_final_list;
	deferred_final_list = 0;
	finalize_list(p);
	for (i = 0; i < heaps_used; i++) {
	    p = heaps[i].slot; pend = p + heaps[i].limit;
	    while (p < pend) {
		if (FL_TEST(p, FL_FINALIZE)) {
		    FL_UNSET(p, FL_FINALIZE);
		    p->as.basic.klass = 0;
		    run_final((VALUE)p);
		}
		p++;
	    }
	}
    }
    /* run data object's finalizers */
    for (i = 0; i < heaps_used; i++) {
	p = heaps[i].slot; pend = p + heaps[i].limit;
	while (p < pend) {
	    if (BUILTIN_TYPE(p) == T_DATA &&
		DATA_PTR(p) && RANY(p)->as.data.dfree &&
		RANY(p)->as.basic.klass != rb_cThread) {
		p->as.free.flags = 0;
		if ((long)RANY(p)->as.data.dfree == -1) {
		    RUBY_CRITICAL(free(DATA_PTR(p)));
		}
		else if (RANY(p)->as.data.dfree) {
		    (*RANY(p)->as.data.dfree)(DATA_PTR(p));
		}
                VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
	    }
	    else if (BUILTIN_TYPE(p) == T_FILE) {
		if (rb_io_fptr_finalize(RANY(p)->as.file.fptr)) {
		    p->as.free.flags = 0;
                    VALGRIND_MAKE_MEM_UNDEFINED((void*)p, sizeof(RVALUE));
		}
	    }
	    p++;
	}
    }
    during_gc = 0;
}

/*
 *  call-seq:
 *     ObjectSpace._id2ref(object_id) -> an_object
 *
 *  Converts an object id to a reference to the object. May not be
 *  called on an object id passed as a parameter to a finalizer.
 *
 *     s = "I am a string"                    #=> "I am a string"
 *     r = ObjectSpace._id2ref(s.object_id)   #=> "I am a string"
 *     r == s                                 #=> true
 *
 */

static VALUE
id2ref(VALUE obj, VALUE objid)
{
#if SIZEOF_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULONG(x)
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULL(x)
#endif
    VALUE ptr;
    void *p0;

    rb_secure(4);
    ptr = NUM2PTR(objid);
    p0 = (void *)ptr;

    if (ptr == Qtrue) return Qtrue;
    if (ptr == Qfalse) return Qfalse;
    if (ptr == Qnil) return Qnil;
    if (FIXNUM_P(ptr)) return (VALUE)ptr;
    ptr = objid ^ FIXNUM_FLAG;	/* unset FIXNUM_FLAG */

    if ((ptr % sizeof(RVALUE)) == (4 << 2)) {
        ID symid = ptr / sizeof(RVALUE);
        if (rb_id2name(symid) == 0)
	    rb_raise(rb_eRangeError, "%p is not symbol id value", p0);
	return ID2SYM(symid);
    }

    if (!is_pointer_to_heap((void *)ptr) ||
	BUILTIN_TYPE(ptr) >= T_VALUES || BUILTIN_TYPE(ptr) == T_ICLASS) {
	rb_raise(rb_eRangeError, "%p is not id value", p0);
    }
    if (BUILTIN_TYPE(ptr) == 0 || RBASIC(ptr)->klass == 0) {
	rb_raise(rb_eRangeError, "%p is recycled object", p0);
    }
    return (VALUE)ptr;
}

/*
 *  Document-method: __id__
 *  Document-method: object_id
 *
 *  call-seq:
 *     obj.__id__       => fixnum
 *     obj.object_id    => fixnum
 *
 *  Returns an integer identifier for <i>obj</i>. The same number will
 *  be returned on all calls to <code>id</code> for a given object, and
 *  no two active objects will share an id.
 *  <code>Object#object_id</code> is a different concept from the
 *  <code>:name</code> notation, which returns the symbol id of
 *  <code>name</code>. Replaces the deprecated <code>Object#id</code>.
 */

/*
 *  call-seq:
 *     obj.hash    => fixnum
 *
 *  Generates a <code>Fixnum</code> hash value for this object. This
 *  function must have the property that <code>a.eql?(b)</code> implies
 *  <code>a.hash == b.hash</code>. The hash value is used by class
 *  <code>Hash</code>. Any hash value that exceeds the capacity of a
 *  <code>Fixnum</code> will be truncated before being used.
 */

VALUE
rb_obj_id(VALUE obj)
{
    /*
     *                32-bit VALUE space
     *          MSB ------------------------ LSB
     *  false   00000000000000000000000000000000
     *  true    00000000000000000000000000000010
     *  nil     00000000000000000000000000000100
     *  undef   00000000000000000000000000000110
     *  symbol  ssssssssssssssssssssssss00001110
     *  object  oooooooooooooooooooooooooooooo00        = 0 (mod sizeof(RVALUE))
     *  fixnum  fffffffffffffffffffffffffffffff1
     *
     *                    object_id space
     *                                       LSB
     *  false   00000000000000000000000000000000
     *  true    00000000000000000000000000000010
     *  nil     00000000000000000000000000000100
     *  undef   00000000000000000000000000000110
     *  symbol   000SSSSSSSSSSSSSSSSSSSSSSSSSSS0        S...S % A = 4 (S...S = s...s * A + 4)
     *  object   oooooooooooooooooooooooooooooo0        o...o % A = 0
     *  fixnum  fffffffffffffffffffffffffffffff1        bignum if required
     *
     *  where A = sizeof(RVALUE)/4
     *
     *  sizeof(RVALUE) is
     *  20 if 32-bit, double is 4-byte aligned
     *  24 if 32-bit, double is 8-byte aligned
     *  40 if 64-bit
     */
    if (TYPE(obj) == T_SYMBOL) {
        return (SYM2ID(obj) * sizeof(RVALUE) + (4 << 2)) | FIXNUM_FLAG;
    }
    if (SPECIAL_CONST_P(obj)) {
        return LONG2NUM((SIGNED_VALUE)obj);
    }
    return (VALUE)((SIGNED_VALUE)obj|FIXNUM_FLAG);
}

/*
 *  call-seq:
 *     ObjectSpace.count_objects([result_hash]) -> hash
 *
 *  Counts objects for each type.
 *
 *  It returns a hash as:
 *  {:TOTAL=>10000, :FREE=>3011, :T_OBJECT=>6, :T_CLASS=>404, ...}
 *
 *  If the optional argument, result_hash, is given,
 *  it is overwritten and returned.
 *  This is intended to avoid probe effect.
 *
 *  The contents of the returned hash is implementation defined.
 *  It may be changed in future.
 *
 *  This method is not expected to work except C Ruby.
 *
 */

static VALUE
count_objects(int argc, VALUE *argv, VALUE os)
{
    long counts[T_MASK+1];
    long freed = 0;
    long total = 0;
    int i;
    VALUE hash;

    if (rb_scan_args(argc, argv, "01", &hash) == 1) {
        if (TYPE(hash) != T_HASH)
            rb_raise(rb_eTypeError, "non-hash given");
    }

    for (i = 0; i <= T_MASK; i++) {
        counts[i] = 0;
    }

    for (i = 0; i < heaps_used; i++) {
        RVALUE *p, *pend;

        p = heaps[i].slot; pend = p + heaps[i].limit;
        for (;p < pend; p++) {
            if (p->as.basic.flags) {
                counts[BUILTIN_TYPE(p)]++;
            }
            else {
                freed++;
            }
        }
        total += heaps[i].limit;
    }

    if (hash == Qnil)
        hash = rb_hash_new();
    rb_hash_aset(hash, ID2SYM(rb_intern("TOTAL")), LONG2NUM(total));
    rb_hash_aset(hash, ID2SYM(rb_intern("FREE")), LONG2NUM(freed));
    for (i = 0; i <= T_MASK; i++) {
        VALUE type;
        switch (i) {
          case T_NONE:          type = ID2SYM(rb_intern("T_NONE")); break;
          case T_NIL:           type = ID2SYM(rb_intern("T_NIL")); break;
          case T_OBJECT:        type = ID2SYM(rb_intern("T_OBJECT")); break;
          case T_CLASS:         type = ID2SYM(rb_intern("T_CLASS")); break;
          case T_ICLASS:        type = ID2SYM(rb_intern("T_ICLASS")); break;
          case T_MODULE:        type = ID2SYM(rb_intern("T_MODULE")); break;
          case T_FLOAT:         type = ID2SYM(rb_intern("T_FLOAT")); break;
          case T_STRING:        type = ID2SYM(rb_intern("T_STRING")); break;
          case T_REGEXP:        type = ID2SYM(rb_intern("T_REGEXP")); break;
          case T_ARRAY:         type = ID2SYM(rb_intern("T_ARRAY")); break;
          case T_FIXNUM:        type = ID2SYM(rb_intern("T_FIXNUM")); break;
          case T_HASH:          type = ID2SYM(rb_intern("T_HASH")); break;
          case T_STRUCT:        type = ID2SYM(rb_intern("T_STRUCT")); break;
          case T_BIGNUM:        type = ID2SYM(rb_intern("T_BIGNUM")); break;
          case T_FILE:          type = ID2SYM(rb_intern("T_FILE")); break;
          case T_TRUE:          type = ID2SYM(rb_intern("T_TRUE")); break;
          case T_FALSE:         type = ID2SYM(rb_intern("T_FALSE")); break;
          case T_DATA:          type = ID2SYM(rb_intern("T_DATA")); break;
          case T_MATCH:         type = ID2SYM(rb_intern("T_MATCH")); break;
          case T_SYMBOL:        type = ID2SYM(rb_intern("T_SYMBOL")); break;
          case T_VALUES:        type = ID2SYM(rb_intern("T_VALUES")); break;
          case T_BLOCK:         type = ID2SYM(rb_intern("T_BLOCK")); break;
          case T_UNDEF:         type = ID2SYM(rb_intern("T_UNDEF")); break;
          case T_NODE:          type = ID2SYM(rb_intern("T_NODE")); break;
          default:              type = INT2NUM(i); break;
        }
        if (counts[i])
            rb_hash_aset(hash, type, LONG2NUM(counts[i]));
    }

    return hash;
}

/*
 *  The <code>GC</code> module provides an interface to Ruby's mark and
 *  sweep garbage collection mechanism. Some of the underlying methods
 *  are also available via the <code>ObjectSpace</code> module.
 */

void
Init_GC(void)
{
    VALUE rb_mObSpace;

    rb_mGC = rb_define_module("GC");
    rb_define_singleton_method(rb_mGC, "start", rb_gc_start, 0);
    rb_define_singleton_method(rb_mGC, "enable", rb_gc_enable, 0);
    rb_define_singleton_method(rb_mGC, "disable", rb_gc_disable, 0);
    rb_define_singleton_method(rb_mGC, "stress", gc_stress_get, 0);
    rb_define_singleton_method(rb_mGC, "stress=", gc_stress_set, 1);
    rb_define_method(rb_mGC, "garbage_collect", rb_gc_start, 0);

    rb_mObSpace = rb_define_module("ObjectSpace");
    rb_define_module_function(rb_mObSpace, "each_object", os_each_obj, -1);
    rb_define_module_function(rb_mObSpace, "garbage_collect", rb_gc_start, 0);
    rb_define_module_function(rb_mObSpace, "add_finalizer", add_final, 1);
    rb_define_module_function(rb_mObSpace, "remove_finalizer", rm_final, 1);
    rb_define_module_function(rb_mObSpace, "finalizers", finals, 0);
    rb_define_module_function(rb_mObSpace, "call_finalizer", call_final, 1);

    rb_define_module_function(rb_mObSpace, "define_finalizer", define_final, -1);
    rb_define_module_function(rb_mObSpace, "undefine_finalizer", undefine_final, 1);

    rb_define_module_function(rb_mObSpace, "_id2ref", id2ref, 1);

    rb_gc_register_address(&rb_mObSpace);
    rb_global_variable(&finalizers);
    rb_gc_unregister_address(&rb_mObSpace);
    finalizers = rb_ary_new();

    source_filenames = st_init_strtable();

    rb_global_variable(&nomem_error);
    nomem_error = rb_exc_new2(rb_eNoMemError, "failed to allocate memory");

    rb_define_method(rb_mKernel, "hash", rb_obj_id, 0);
    rb_define_method(rb_mKernel, "__id__", rb_obj_id, 0);
    rb_define_method(rb_mKernel, "object_id", rb_obj_id, 0);

    rb_define_module_function(rb_mObSpace, "count_objects", count_objects, -1);
}
