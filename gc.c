/************************************************

  gc.c -

  $Author: matz $
  $Date: 1994/12/19 08:39:19 $
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

struct RVALUE {
    union {
	struct {
	    UINT flag;		/* always 0 for freed obj */
	    struct RVALUE *next;
	} free;
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
    } as;
} *freelist = Qnil;

struct heap_block {
    struct heap_block *next;
    struct RVALUE *beg;
    struct RVALUE *end;
    struct RVALUE body[1];
} *heap_link = Qnil;

#define SEG_SLOTS 10000
#define SEG_SIZE  (SEG_SLOTS*sizeof(struct RVALUE))

static int heap_size;

static void
add_heap()
{
    struct heap_block *block;
    struct RVALUE *p, *pend;

    block = (struct heap_block*)malloc(sizeof(*block) + SEG_SIZE);
    if (block == Qnil) Fatal("cant alloc memory");
    block->next = heap_link;
    block->beg = &block->body[0];
    block->end = block->beg + SEG_SLOTS;
    p = block->beg; pend = block->end;
    while (p < pend) {
	p->as.free.flag = 0;
	p->as.free.next = freelist;
	freelist = p;
	p++;
    }
    heap_link = block;
    heap_size += SEG_SLOTS;
}

struct RBasic *
newobj()
{
    struct RBasic *obj;
    if (heap_link == Qnil) add_heap();
    if (freelist) {
      retry:
	obj = (struct RBasic*)freelist;
	freelist = freelist->as.free.next;
	obj->flags = 0;
	obj->iv_tbl = Qnil;
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
    struct RVALUE *p;
{
    struct heap_block *heap = heap_link;

    if (FIXNUM_P(p)) return FALSE;
    while (heap) {
	if (heap->beg <= p && p < heap->end
	    && ((((char*)p)-((char*)heap->beg))%sizeof(struct RVALUE)) == 0)
	    return TRUE;
	heap = heap->next;
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
    register struct RBasic *obj;
{
    if (obj == Qnil) return;
    if (FIXNUM_P(obj)) return;
    if (obj->flags & FL_MARK) return;

    obj->flags |= FL_MARK;

    switch (obj->flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	Bug("gc_mark() called for broken object");
	break;
    }

    switch (obj->flags & T_MASK) {
      case T_ICLASS:
	gc_mark(RCLASS(obj)->super);
	if (RCLASS(obj)->c_tbl) mark_tbl(RCLASS(obj)->c_tbl);
	mark_tbl(RCLASS(obj)->m_tbl);
	break;

      case T_CLASS:
	gc_mark(RCLASS(obj)->super);
      case T_MODULE:
	if (RCLASS(obj)->c_tbl) mark_tbl(RCLASS(obj)->c_tbl);
	mark_tbl(RCLASS(obj)->m_tbl);
	gc_mark(RBASIC(obj)->class);
	break;

      case T_ARRAY:
	{
	    int i, len = RARRAY(obj)->len;
	    VALUE *ptr = RARRAY(obj)->ptr;

	    for (i=0; i < len; i++)
		gc_mark(ptr[i]);
	}
	break;

      case T_DICT:
	mark_dict(RDICT(obj)->tbl);
	break;

      case T_STRING:
	if (RSTRING(obj)->orig) gc_mark(RSTRING(obj)->orig);
	break;

      case T_DATA:
	if (RDATA(obj)->dmark) (*RDATA(obj)->dmark)(DATA_PTR(obj));
	break;

      case T_OBJECT:
      case T_REGEXP:
      case T_FLOAT:
      case T_BIGNUM:
	break;

      case T_STRUCT:
	{
	    int i, len = RSTRUCT(obj)->len;
	    struct kv_pair *ptr = RSTRUCT(obj)->tbl;

	    for (i=0; i < len; i++)
		gc_mark(ptr[i].value);
	}
	break;

      case T_CONS:
	gc_mark(RCONS(obj)->car);
	gc_mark(RCONS(obj)->cdr);
	break;

      case T_NODE:
	gc_mark_maybe(RNODE(obj)->u1.node);
	gc_mark_maybe(RNODE(obj)->u2.node);
	gc_mark_maybe(RNODE(obj)->u3.node);
	return;			/* no need to mark class & tbl */

      default:
	Bug("gc_mark(): unknown data type %d", obj->flags & T_MASK);
    }
    if (obj->iv_tbl) mark_tbl(obj->iv_tbl);
    gc_mark(obj->class);
}

#define MIN_FREE_OBJ 512

static void obj_free();

static void
gc_sweep()
{
    struct heap_block *heap = heap_link;
    int freed = 0;

    freelist = Qnil;
    while (heap) {
	struct RVALUE *p, *pend;
	struct RVALUE *nfreelist;
	int n = 0;

	nfreelist = freelist;
	p = heap->beg; pend = heap->end;
	while (p < pend) {
	    
	    if (!(RBASIC(p)->flags & FL_MARK)) {
		if (RBASIC(p)->flags) obj_free(p);
		p->as.free.flag = 0;
		p->as.free.next = nfreelist;
		nfreelist = p;
		n++;
	    }
	    RBASIC(p)->flags &= ~FL_MARK;
	    p++;
	}
	if (n == SEG_SLOTS) {
	    struct heap_block *link = heap_link;
	    if (heap != link) {
		while (link) {
		    if (link->next && link->next == heap) {
			link->next = heap->next;
			break;
		    }
		    link = link->next;
		}
		if (link == Qnil) {
		    Bug("non-existing heap at 0x%x", heap);
		}
	    }
	    free(heap);
	    heap_size -= SEG_SLOTS;
	    heap = link;
	}
	else {
	    freed += n;
	    freelist = nfreelist;
	}
	heap = heap->next;
    }
    if (freed < heap_size/4) {
	add_heap();
    }
}

static void
obj_free(obj)
    struct RBasic *obj;
{
    switch (obj->flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	Bug("obj_free() called for broken object");
	break;
    }

    switch (obj->flags & T_MASK) {
      case T_OBJECT:
	break;
      case T_MODULE:
      case T_CLASS:
	rb_clear_cache2(obj);
	st_free_table(RCLASS(obj)->m_tbl);
	if (RCLASS(obj)->c_tbl)
	    st_free_table(RCLASS(obj)->c_tbl);
	break;
      case T_STRING:
	if (RSTRING(obj)->orig == Qnil) free(RSTRING(obj)->ptr);
	break;
      case T_ARRAY:
	free(RARRAY(obj)->ptr);
	break;
      case T_DICT:
	st_free_table(RDICT(obj)->tbl);
	break;
      case T_REGEXP:
	reg_free(RREGEXP(obj)->ptr);
	free(RREGEXP(obj)->str);
	break;
      case T_DATA:
	if (RDATA(obj)->dfree) (*RDATA(obj)->dfree)(DATA_PTR(obj));
	free(DATA_PTR(obj));
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
      case T_FLOAT:
	break;
      case T_STRUCT:
	free(RSTRUCT(obj)->name);
	free(RSTRUCT(obj)->tbl);
	break;
      case T_BIGNUM:
	free(RBIGNUM(obj)->digits);
	break;
      case T_NODE:
	if (nd_type(obj) == NODE_SCOPE && RNODE(obj)->nd_tbl) {
	    free(RNODE(obj)->nd_tbl);
	}
	return;			/* no need to free iv_tbl */
      default:
	Bug("gc_sweep(): unknown data type %d", obj->flags & T_MASK);
    }
    if (obj->iv_tbl) st_free_table(obj->iv_tbl);
}

void
gc_mark_scope(scope)
    struct SCOPE *scope;
{
    if (scope->local_vars && scope->var_ary == Qnil)
	mark_locations_array(scope->local_vars, scope->local_tbl[0]);
    gc_mark(scope->var_ary);
}

void
gc()
{
    struct gc_list *list;
    struct ENVIRON *env;
    struct SCOPE *scope;
    int i, max;
    jmp_buf save_regs_gc_mark;
    VALUE stack_end;

    if (dont_gc) return;
    dont_gc++;

    /* mark scope stack */
    for (scope = the_scope; scope; scope = scope->prev) {
	gc_mark_scope(scope);
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

Init_stack()
{
    VALUE start;

    stack_start_ptr = &start;
}

Init_GC()
{
    M_GC = rb_define_module("GC");
    rb_define_single_method(M_GC, "start", gc, 0);
    rb_define_single_method(M_GC, "enable", Sgc_enable, 0);
    rb_define_single_method(M_GC, "disable", Sgc_disable, 0);
    rb_define_method(M_GC, "garbage_collect", gc, 0);
}
