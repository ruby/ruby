/************************************************

  gc.c -

  $Author: matz $
  $Date: 1995/01/12 08:54:47 $
  created at: Tue Oct  5 09:44:46 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "env.h"
#include "st.h"
#include "node.h"
#include <stdio.h>
#include <setjmp.h>

void *malloc();
void *calloc();
void *realloc();

void gc();
void gc_mark();

void *
xmalloc(size)
    unsigned long size;
{
    void *mem;

    if (size == 0) size = 1;
    mem = malloc(size);
    if (mem == Qnil) {
	gc();
	mem = malloc(size);
	if (mem == Qnil)
	    Fatal("failed to allocate memory");
    }

    return mem;
}

void *
xcalloc(n, size)
    unsigned long n, size;
{
    void *mem;

    mem = xmalloc(n * size);
    memset(mem, 0, n * size);

    return mem;
}

void *
xrealloc(ptr, size)
    void *ptr;
    unsigned long size;
{
    void *mem;

    mem = realloc(ptr, size);
    if (mem == Qnil) {
	gc();
	mem = realloc(ptr, size);
	if (mem == Qnil)
	    Fatal("failed to allocate memory(realloc)");
    }

    return mem;
}

/* The way of garbage collecting which allows use of the cstack is due to */
/* Scheme In One Defun, but in C this time.

 *			  COPYRIGHT (c) 1989 BY				    *
 *	  PARADIGM ASSOCIATES INCORPORATED, CAMBRIDGE, MASSACHUSETTS.	    *
 *			   ALL RIGHTS RESERVED				    *

Permission to use, copy, modify, distribute and sell this software
and its documentation for any purpose and without fee is hereby
granted, provided that the above copyright notice appear in all copies
and that both that copyright notice and this permission notice appear
in supporting documentation, and that the name of Paradigm Associates
Inc not be used in advertising or publicity pertaining to distribution
of the software without specific, written prior permission.

PARADIGM DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE, INCLUDING
ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO EVENT SHALL
PARADIGM BE LIABLE FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR
ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS
SOFTWARE.

gjc@paradigm.com

Paradigm Associates Inc		 Phone: 617-492-6079
29 Putnam Ave, Suite 6
Cambridge, MA 02138
*/

#ifdef sparc
#define FLUSH_REGISTER_WINDOWS asm("ta 3")
#else
#define FLUSH_REGISTER_WINDOWS /* empty */
#endif

static int dont_gc;

VALUE
Sgc_enable()
{
    int old = dont_gc;

    dont_gc = Qnil;
    return old;
}

VALUE
Sgc_disable()
{
    int old = dont_gc;

    dont_gc = TRUE;
    return old;
}

#include <sys/types.h>
#include <sys/times.h>

static
Fgc_begin()
{
    return Qnil;
}

static
Fgc_end()
{
    return Qnil;
}

VALUE M_GC;

static struct gc_list {
    int n;
    VALUE *varptr;
    struct gc_list *next;
} *Global_List = Qnil;

void
rb_global_variable(var)
    VALUE *var;
{
    struct gc_list *tmp;

    tmp = (struct gc_list*)xmalloc(sizeof(struct gc_list));
    tmp->next = Global_List;
    tmp->varptr = var;
    tmp->n = 1;
    Global_List = tmp;
}

typedef struct RVALUE {
    union {
	struct {
	    UINT flag;		/* always 0 for freed obj */
	    struct RVALUE *next;
	} free;
	struct RBasic  basic;
	struct RObject object;
	struct RClass  class;
	struct RFloat  flonum;
	struct RString string;
	struct RArray  array;
	struct RRegexp regexp;
	struct RDict   dict;
	struct RData   data;
	struct RStruct rstruct;
	struct RBignum bignum;
	struct RNode   node;
	struct RCons   cons;
	struct SCOPE   scope;
    } as;
} RVALUE;

RVALUE *freelist = Qnil;

#define HEAPS_INCREMENT 10
static RVALUE **heaps;
static int heaps_length = 0;
static int heaps_used   = 0;

#define HEAP_SLOTS 10000
#define FREE_MIN  512

static void
add_heap()
{
    RVALUE *p, *pend;

    if (heaps_used == heaps_length) {
	/* Realloc heaps */
	heaps_length += HEAPS_INCREMENT;
	heaps = (heaps_used)?
	    (RVALUE**)realloc(heaps, heaps_length*sizeof(RVALUE)):
	    (RVALUE**)malloc(heaps_length*sizeof(RVALUE));
	if (heaps == Qnil) Fatal("can't alloc memory");
    }

    p = heaps[heaps_used++] = (RVALUE*)malloc(sizeof(RVALUE)*HEAP_SLOTS);
    if (p == Qnil) Fatal("can't alloc memory");
    pend = p + HEAP_SLOTS;

    while (p < pend) {
	p->as.free.flag = 0;
	p->as.free.next = freelist;
	freelist = p;
	p++;
    }
}

struct RBasic *
newobj()
{
    struct RBasic *obj;
    if (freelist) {
      retry:
	obj = (struct RBasic*)freelist;
	freelist = freelist->as.free.next;
	memset(obj, 0, sizeof(RVALUE));
	return obj;
    }
    if (dont_gc) add_heap();
    else gc();

    goto retry;
}

VALUE
data_new(datap, dfree, dmark)
    VALUE *datap;
    void (*dfree)();
    void (*dmark)();
{
    extern VALUE C_Data;
    struct RData *data = (struct RData*)newobj();

    OBJSETUP(data, C_Data, T_DATA);
    data->data = datap;
    data->dfree = dfree;
    data->dmark = dmark;

    return (VALUE)data;
}

extern st_table *rb_class_tbl;
static VALUE *stack_start_ptr;

static long
looks_pointerp(p)
    register RVALUE *p;
{
    register RVALUE *heap_org;
    register long i, j, n;

    /* if p looks as a SCM pointer mark location */
    for (i=0; i < heaps_used; i++) {
	heap_org = heaps[i];
	if (heap_org <= p && p < heap_org + HEAP_SLOTS
	    && ((((char*)p)-((char*)heap_org))%sizeof(RVALUE)) == 0)
	    return TRUE;
    }
    return FALSE;
}

static void
mark_locations_array(x, n)
    VALUE *x;
    long n;
{
    int j;
    VALUE p;

    for(j=0;j<n;++j) {
	p = x[j];
	if (looks_pointerp(p)) {
	    gc_mark(p);
	}
    }
}

static void
mark_locations(start, end)
    VALUE *start, *end;
{
    VALUE *tmp;
    long n;

    if (start > end) {
	tmp = start;
	start = end;
	end = tmp;
    }
    n = end - start;
    mark_locations_array(start,n);
}

static
mark_entry(key, value)
    ID key;
    VALUE value;
{
    gc_mark(value);
    return ST_CONTINUE;
}

static
mark_tbl(tbl)
    st_table *tbl;
{
    st_foreach(tbl, mark_entry, 0);
}

static
mark_dicentry(key, value)
    ID key;
    VALUE value;
{
    gc_mark(key);
    gc_mark(value);
    return ST_CONTINUE;
}

static
mark_dict(tbl)
    st_table *tbl;
{
    st_foreach(tbl, mark_dicentry, 0);
}

void
gc_mark_maybe(obj)
    void *obj;
{
    if (looks_pointerp(obj)) {
	gc_mark(obj);
    }
}

void
gc_mark(obj)
    register RVALUE *obj;
{
  Top:
    if (obj == Qnil) return;	/* nil not marked */
    if (FIXNUM_P(obj)) return;	/* fixnum not marked */
    if (obj->as.basic.flags == 0) return; /* free cell */
    if (obj->as.basic.flags & FL_MARK) return; /* marked */

    obj->as.basic.flags |= FL_MARK;

    switch (obj->as.basic.flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	Bug("gc_mark() called for broken object");
	break;

      case T_NODE:
	if (looks_pointerp(obj->as.node.u1.node)) {
	    gc_mark(obj->as.node.u1.node);
	}
	if (looks_pointerp(obj->as.node.u2.node)) {
	    gc_mark(obj->as.node.u2.node);
	}
	if (looks_pointerp(obj->as.node.u3.node)) {
	    obj = (RVALUE*)obj->as.node.u3.node;
	    goto Top;
	}
	return;			/* no need to mark class. */
    }

    gc_mark(obj->as.basic.class);
    switch (obj->as.basic.flags & T_MASK) {
      case T_ICLASS:
	gc_mark(obj->as.class.super);
	if (obj->as.class.iv_tbl) mark_tbl(obj->as.class.iv_tbl);
	mark_tbl(obj->as.class.m_tbl);
	break;

      case T_CLASS:
	gc_mark(obj->as.class.super);
      case T_MODULE:
	mark_tbl(obj->as.class.m_tbl);
	if (obj->as.class.iv_tbl) mark_tbl(obj->as.class.iv_tbl);
	break;

      case T_ARRAY:
	{
	    int i, len = obj->as.array.len;
	    VALUE *ptr = obj->as.array.ptr;

	    for (i=0; i < len; i++)
		gc_mark(ptr[i]);
	}
	break;

      case T_DICT:
	mark_dict(obj->as.dict.tbl);
	break;

      case T_STRING:
	if (obj->as.string.orig) gc_mark(obj->as.string.orig);
	break;

      case T_DATA:
	if (obj->as.data.dmark) (*obj->as.data.dmark)(DATA_PTR(obj));
	break;

      case T_OBJECT:
	if (obj->as.object.iv_tbl) mark_tbl(obj->as.object.iv_tbl);
	break;

      case T_REGEXP:
      case T_FLOAT:
      case T_BIGNUM:
	break;

      case T_STRUCT:
	{
	    int i, len = obj->as.rstruct.len;
	    struct kv_pair *ptr = obj->as.rstruct.tbl;

	    for (i=0; i < len; i++)
		gc_mark(ptr[i].value);
	}
	break;

      case T_SCOPE:
	{
	    struct SCOPE *scope = (struct SCOPE*)obj;
	    if (scope->local_vars)
		mark_locations_array(scope->local_vars, scope->local_tbl[0]);
	}
	break;

      case T_CONS:
	gc_mark(obj->as.cons.car);
	obj = (RVALUE*)obj->as.cons.cdr;
	goto Top;

      default:
	Bug("gc_mark(): unknown data type %d", obj->as.basic.flags & T_MASK);
    }
}

#define MIN_FREE_OBJ 512

static void obj_free();

static void
gc_sweep()
{
    int freed = 0;
    int  i;

    freelist = Qnil;
    for (i = 0; i < heaps_used; i++) {
	RVALUE *p, *pend;
	RVALUE *nfreelist;
	int n = 0;

	nfreelist = freelist;
	p = heaps[i]; pend = p + HEAP_SLOTS;

	while (p < pend) {
	    if (!(p->as.basic.flags & FL_MARK)) {
		if (p->as.basic.flags) obj_free(p);
		p->as.free.flag = 0;
		p->as.free.next = nfreelist;
		nfreelist = p;
		n++;
	    }
	    else
		RBASIC(p)->flags &= ~FL_MARK;
	    p++;
	}
	freed += n;
	freelist = nfreelist;
    }
    if (freed < FREE_MIN) {
	add_heap();
    }
}

static void
obj_free(obj)
    RVALUE *obj;
{
    switch (obj->as.basic.flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	Bug("obj_free() called for broken object");
	break;
    }

    switch (obj->as.basic.flags & T_MASK) {
      case T_OBJECT:
	if (obj->as.object.iv_tbl) st_free_table(obj->as.object.iv_tbl);
	break;
      case T_MODULE:
      case T_CLASS:
	rb_clear_cache2(obj);
	st_free_table(obj->as.class.m_tbl);
	if (obj->as.object.iv_tbl) st_free_table(obj->as.object.iv_tbl);
	break;
      case T_STRING:
	if (obj->as.string.orig == Qnil) free(obj->as.string.ptr);
	break;
      case T_ARRAY:
	free(obj->as.array.ptr);
	break;
      case T_DICT:
	st_free_table(obj->as.dict.tbl);
	break;
      case T_REGEXP:
	reg_free(obj->as.regexp.ptr);
	free(obj->as.regexp.str);
	break;
      case T_DATA:
	if (obj->as.data.dfree) (*obj->as.data.dfree)(DATA_PTR(obj));
	free(DATA_PTR(obj));
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
      case T_FLOAT:
      case T_CONS:
	break;
      case T_STRUCT:
	free(obj->as.rstruct.name);
	free(obj->as.rstruct.tbl);
	break;
      case T_BIGNUM:
	free(obj->as.bignum.digits);
	break;
      case T_NODE:
	if (nd_type(obj) == NODE_SCOPE && obj->as.node.nd_tbl) {
	    free(obj->as.node.nd_tbl);
	}
	return;			/* no need to free iv_tbl */

      case T_SCOPE:
	{
	    struct SCOPE *scope = (struct SCOPE*)obj;
	    if (scope->local_vars)
		free(scope->local_vars);
	    if (scope->local_tbl)
		free(scope->local_tbl);
	}
	break;

      default:
	Bug("gc_sweep(): unknown data type %d", obj->as.basic.flags & T_MASK);
    }
}

void
gc_mark_env(env)
    struct ENVIRON *env;
{
    mark_locations_array(env->argv, env->argc);
}

void
gc()
{
    struct gc_list *list;
    struct ENVIRON *env;
    int i, max;
    jmp_buf save_regs_gc_mark;
    VALUE stack_end;

    if (dont_gc) return;
    dont_gc++;

#ifdef C_ALLOCA
    alloca(0);
#endif

    /* mark env stack */
    for (env = the_env; env; env = env->prev) {
	gc_mark_env(env);
    }

    FLUSH_REGISTER_WINDOWS;
    /* This assumes that all registers are saved into the jmp_buf */
    setjmp(save_regs_gc_mark);
    mark_locations((VALUE*)save_regs_gc_mark,
		   (VALUE*)(((char*)save_regs_gc_mark)+sizeof(save_regs_gc_mark)));
    mark_locations(stack_start_ptr, (VALUE*) &stack_end);
#if defined(THINK_C)
    mark_locations((VALUE*)((char*)stack_start_ptr + 2),
		   (VALUE*)((char*)&stack_end + 2));
#endif

    /* mark protected global variables */
    for (list = Global_List; list; list = list->next) {
	gc_mark(*list->varptr);
    }

    gc_mark_global_tbl();
    mark_tbl(rb_class_tbl);

    gc_mark_trap_list();

    gc_sweep();
    dont_gc--;
}

void
init_stack()
{
    VALUE start;

    stack_start_ptr = &start;
}

void
init_heap()
{
    init_stack();
    add_heap();
}

Init_GC()
{
    M_GC = rb_define_module("GC");
    rb_define_single_method(M_GC, "start", gc, 0);
    rb_define_single_method(M_GC, "enable", Sgc_enable, 0);
    rb_define_single_method(M_GC, "disable", Sgc_disable, 0);
    rb_define_method(M_GC, "garbage_collect", gc, 0);
}
