/************************************************

  gc.c -

  $Author$
  $Date$
  created at: Tue Oct  5 09:44:46 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "sig.h"
#include "st.h"
#include "node.h"
#include "env.h"
#include "re.h"
#include <stdio.h>
#include <setjmp.h>

#ifndef setjmp
#ifdef HAVE__SETJMP
#define setjmp(env) _setjmp(env)
#define longjmp(env,val) _longjmp(env,val)
#endif
#endif

#ifdef C_ALLOCA
void *alloca();
#endif

static void run_final();

#ifndef GC_MALLOC_LIMIT
#if defined(MSDOS) || defined(__human68k__)
#define GC_MALLOC_LIMIT 200000
#else
#define GC_MALLOC_LIMIT 400000
#endif
#endif

static unsigned long malloc_memories = 0;

void *
xmalloc(size)
    unsigned long size;
{
    void *mem;

    if (size == 0) size = 1;
    malloc_memories += size;
    if (malloc_memories > GC_MALLOC_LIMIT) {
	gc_gc();
    }
    mem = malloc(size);
    if (!mem) {
	gc_gc();
	mem = malloc(size);
	if (!mem)
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

    if (!ptr) return xmalloc(size);
    mem = realloc(ptr, size);
    if (!mem) {
	gc_gc();
	mem = realloc(ptr, size);
	if (!mem)
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

extern int rb_in_compile;
static int dont_gc;

VALUE
gc_s_enable()
{
    int old = dont_gc;

    dont_gc = FALSE;
    return old;
}

VALUE
gc_s_disable()
{
    int old = dont_gc;

    dont_gc = TRUE;
    return old;
}

VALUE mGC;

static struct gc_list {
    VALUE *varptr;
    struct gc_list *next;
} *Global_List = 0;

void
rb_global_variable(var)
    VALUE *var;
{
    struct gc_list *tmp;

    tmp = ALLOC(struct gc_list);
    tmp->next = Global_List;
    tmp->varptr = var;
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
	struct RHash   hash;
	struct RData   data;
	struct RStruct rstruct;
	struct RBignum bignum;
	struct RFile   file;
	struct RNode   node;
	struct RMatch  match;
	struct RVarmap varmap; 
	struct SCOPE   scope;
    } as;
} RVALUE;

RVALUE *freelist = 0;

#define HEAPS_INCREMENT 10
static RVALUE **heaps;
static int heaps_length = 0;
static int heaps_used   = 0;

#define HEAP_SLOTS 10000
#define FREE_MIN  512

static RVALUE *himem, *lomem;

static void
add_heap()
{
    RVALUE *p, *pend;

    if (heaps_used == heaps_length) {
	/* Realloc heaps */
	heaps_length += HEAPS_INCREMENT;
	heaps = (heaps_used>0)?
	    (RVALUE**)realloc(heaps, heaps_length*sizeof(RVALUE)):
	    (RVALUE**)malloc(heaps_length*sizeof(RVALUE));
	if (heaps == 0) Fatal("can't alloc memory");
    }

    p = heaps[heaps_used++] = (RVALUE*)malloc(sizeof(RVALUE)*HEAP_SLOTS);
    if (p == 0) Fatal("can't alloc memory");
    pend = p + HEAP_SLOTS;
    if (lomem == 0 || lomem > p) lomem = p;
    if (himem < pend) himem = pend;

    while (p < pend) {
	p->as.free.flag = 0;
	p->as.free.next = freelist;
	freelist = p;
	p++;
    }
}
#define RANY(o) ((RVALUE*)(o))

VALUE
rb_newobj()
{
    VALUE obj;

    if (freelist) {
      retry:
	obj = (VALUE)freelist;
	freelist = freelist->as.free.next;
	return obj;
    }
    if (dont_gc) add_heap();
    else gc_gc();

    goto retry;
}

VALUE
data_object_alloc(class, datap, dmark, dfree)
    VALUE class;
    void *datap;
    void (*dfree)();
    void (*dmark)();
{
    NEWOBJ(data, struct RData);
    OBJSETUP(data, class, T_DATA);
    data->data = datap;
    data->dfree = dfree;
    data->dmark = dmark;

    return (VALUE)data;
}

extern st_table *rb_class_tbl;
VALUE *gc_stack_start;

static int
looks_pointerp(ptr)
    void *ptr;
{
    register RVALUE *p = RANY(ptr);
    register RVALUE *heap_org;
    register long i;

    if (p < lomem || p > himem) return FALSE;

    /* check if p looks like a pointer */
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
    while (n--) {
	if (looks_pointerp(*x)) {
	    gc_mark(*x);
	}
	x++;
    }
}

void
gc_mark_locations(start, end)
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

static int
mark_entry(key, value)
    ID key;
    VALUE value;
{
    gc_mark(value);
    return ST_CONTINUE;
}

static void
mark_tbl(tbl)
    st_table *tbl;
{
    if (!tbl) return;
    st_foreach(tbl, mark_entry, 0);
}

static int
mark_hashentry(key, value)
    ID key;
    VALUE value;
{
    gc_mark(key);
    gc_mark(value);
    return ST_CONTINUE;
}

static void
mark_hash(tbl)
    st_table *tbl;
{
    if (!tbl) return;
    st_foreach(tbl, mark_hashentry, 0);
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
gc_mark(ptr)
    void *ptr;
{
    register RVALUE *obj = RANY(ptr);

  Top:
    if (FIXNUM_P(obj)) return;	/* fixnum not marked */
    if (rb_special_const_p((VALUE)obj)) return; /* special const not marked */
    if (obj->as.basic.flags == 0) return; /* free cell */
    if (obj->as.basic.flags & FL_MARK) return; /* marked */

    obj->as.basic.flags |= FL_MARK;

    switch (obj->as.basic.flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	Bug("gc_mark() called for broken object");
	break;

      case T_NODE:
	switch (nd_type(obj)) {
	  case NODE_IF:		/* 1,2,3 */
	  case NODE_FOR:
	  case NODE_ITER:
	  case NODE_CREF:
	    gc_mark(obj->as.node.u2.node);
	    /* fall through */
	  case NODE_BLOCK:	/* 1,3 */
	  case NODE_ARRAY:
	  case NODE_DSTR:
	  case NODE_DXSTR:
	  case NODE_EVSTR:
	  case NODE_DREGX:
	  case NODE_DREGX_ONCE:
	  case NODE_FBODY:
	  case NODE_CALL:
#ifdef C_ALLOCA
	  case NODE_ALLOCA:
#endif
	    gc_mark(obj->as.node.u1.node);
	    /* fall through */
	  case NODE_SUPER:	/* 3 */
	  case NODE_FCALL:
	  case NODE_NEWLINE:
	    obj = RANY(obj->as.node.u3.node);
	    goto Top;

	  case NODE_WHILE:	/* 1,2 */
	  case NODE_UNTIL:
	  case NODE_MATCH2:
	  case NODE_MATCH3:
	    gc_mark(obj->as.node.u1.node);
	    /* fall through */
	  case NODE_METHOD:	/* 2 */
	  case NODE_NOT:
	    obj = RANY(obj->as.node.u2.node);
	    goto Top;

	  case NODE_HASH:	/* 1 */
	  case NODE_LIT:
	  case NODE_STR:
	  case NODE_XSTR:
	  case NODE_DEFINED:
	  case NODE_MATCH:
	    obj = RANY(obj->as.node.u1.node);
	    goto Top;

	  case NODE_SCOPE:	/* 2,3 */
	    gc_mark(obj->as.node.u3.node);
	    obj = RANY(obj->as.node.u2.node);
	    goto Top;

	  case NODE_ZARRAY:	/* - */
	  case NODE_CFUNC:
	  case NODE_VCALL:
	  case NODE_GVAR:
	  case NODE_LVAR:
	  case NODE_DVAR:
	  case NODE_IVAR:
	  case NODE_CVAR:
	  case NODE_NTH_REF:
	  case NODE_BACK_REF:
	  case NODE_ALIAS:
	  case NODE_VALIAS:
	  case NODE_UNDEF:
	  case NODE_SELF:
	  case NODE_NIL:
	  case NODE_POSTEXE:
	    break;

	  default:
	    if (looks_pointerp(obj->as.node.u1.node)) {
		gc_mark(obj->as.node.u1.node);
	    }
	    if (looks_pointerp(obj->as.node.u2.node)) {
		gc_mark(obj->as.node.u2.node);
	    }
	    if (looks_pointerp(obj->as.node.u3.node)) {
		obj = RANY(obj->as.node.u3.node);
		goto Top;
	    }
	}
	return;			/* no need to mark class. */
    }

    gc_mark(obj->as.basic.class);
    switch (obj->as.basic.flags & T_MASK) {
      case T_ICLASS:
	gc_mark(obj->as.class.super);
	mark_tbl(obj->as.class.iv_tbl);
	mark_tbl(obj->as.class.m_tbl);
	break;

      case T_CLASS:
      case T_MODULE:
	gc_mark(obj->as.class.super);
	mark_tbl(obj->as.class.m_tbl);
	mark_tbl(obj->as.class.iv_tbl);
	break;

      case T_ARRAY:
	{
	    int i, len = obj->as.array.len;
	    VALUE *ptr = obj->as.array.ptr;

	    for (i=0; i < len; i++)
		gc_mark(*ptr++);
	}
	break;

      case T_HASH:
	mark_hash(obj->as.hash.tbl);
	break;

      case T_STRING:
	if (obj->as.string.orig) {
	    obj = RANY(obj->as.string.orig);
	    goto Top;
	}
	break;

      case T_DATA:
	if (obj->as.data.dmark) (*obj->as.data.dmark)(DATA_PTR(obj));
	break;

      case T_OBJECT:
	mark_tbl(obj->as.object.iv_tbl);
	break;

      case T_FILE:
      case T_REGEXP:
      case T_FLOAT:
      case T_BIGNUM:
	break;

      case T_MATCH:
	if (obj->as.match.str) {
	    obj = RANY(obj->as.match.str);
	    goto Top;
	}
	break;

      case T_VARMAP:
	gc_mark(obj->as.varmap.val);
	obj = RANY(obj->as.varmap.next);
	goto Top;
	break;

      case T_SCOPE:
	if (obj->as.scope.local_vars) {
	    int n = obj->as.scope.local_tbl[0]+1;
	    VALUE *vars = &obj->as.scope.local_vars[-1];

	    while (n--) {
		gc_mark_maybe(*vars);
		vars++;
	    }
	}
	break;

      case T_STRUCT:
	{
	    int i, len = obj->as.rstruct.len;
	    VALUE *ptr = obj->as.rstruct.ptr;

	    for (i=0; i < len; i++)
		gc_mark(*ptr++);
	}
	break;

      default:
	Bug("gc_mark(): unknown data type 0x%x(0x%x) %s",
	    obj->as.basic.flags & T_MASK, obj,
	    looks_pointerp(obj)?"corrupted object":"non object");
    }
}

#define MIN_FREE_OBJ 512

static void obj_free();

static void
gc_sweep()
{
    RVALUE *p, *pend;
    int freed = 0;
    int  i;

    if (rb_in_compile) {
	for (i = 0; i < heaps_used; i++) {
	    p = heaps[i]; pend = p + HEAP_SLOTS;
	    while (p < pend) {
		if (!(p->as.basic.flags&FL_MARK) && BUILTIN_TYPE(p) == T_NODE)
		    gc_mark(p);
		p++;
	    }
	}
    }

    freelist = 0;
    for (i = 0; i < heaps_used; i++) {
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

void
gc_force_recycle(p)
    VALUE p;
{
    RANY(p)->as.free.flag = 0;
    RANY(p)->as.free.next = freelist;
    freelist = RANY(p);
}

static int need_call_final = 0;

static void
obj_free(obj)
    VALUE obj;
{
    switch (RANY(obj)->as.basic.flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
      case T_TRUE:
      case T_FALSE:
	Bug("obj_free() called for broken object");
	break;
    }

    if (need_call_final) {
	run_final(obj);
    }
    switch (RANY(obj)->as.basic.flags & T_MASK) {
      case T_OBJECT:
	if (RANY(obj)->as.object.iv_tbl) {
	    st_free_table(RANY(obj)->as.object.iv_tbl);
	}
	break;
      case T_MODULE:
      case T_CLASS:
	rb_clear_cache();
	st_free_table(RANY(obj)->as.class.m_tbl);
	if (RANY(obj)->as.object.iv_tbl) {
	    st_free_table(RANY(obj)->as.object.iv_tbl);
	}
	break;
      case T_STRING:
	if (!RANY(obj)->as.string.orig) free(RANY(obj)->as.string.ptr);
	break;
      case T_ARRAY:
	if (RANY(obj)->as.array.ptr) free(RANY(obj)->as.array.ptr);
	break;
      case T_HASH:
	st_free_table(RANY(obj)->as.hash.tbl);
	break;
      case T_REGEXP:
	reg_free(RANY(obj)->as.regexp.ptr);
	free(RANY(obj)->as.regexp.str);
	break;
      case T_DATA:
	if (RANY(obj)->as.data.dfree && DATA_PTR(obj))
	    (*RANY(obj)->as.data.dfree)(DATA_PTR(obj));
	break;
      case T_MATCH:
	re_free_registers(RANY(obj)->as.match.regs);
	free(RANY(obj)->as.match.regs);
	break;
      case T_FILE:
	io_fptr_finalize(RANY(obj)->as.file.fptr);
	free(RANY(obj)->as.file.fptr);
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
	break;

      case T_FLOAT:
      case T_VARMAP:
	break;

      case T_BIGNUM:
	if (RANY(obj)->as.bignum.digits) free(RANY(obj)->as.bignum.digits);
	break;
      case T_NODE:
	if (nd_type(obj) == NODE_SCOPE && RANY(obj)->as.node.u1.tbl) {
	    free(RANY(obj)->as.node.u1.tbl);
	}
	return;			/* no need to free iv_tbl */

      case T_SCOPE:
	if (RANY(obj)->as.scope.local_vars) {
	    VALUE *vars = RANY(obj)->as.scope.local_vars-1;
	    if (vars[0] == 0)
		free(RANY(obj)->as.scope.local_tbl);
	    if (RANY(obj)->as.scope.flag&SCOPE_MALLOC)
		free(vars);
	}
	break;

      case T_STRUCT:
	free(RANY(obj)->as.rstruct.ptr);
	break;

      default:
	Bug("gc_sweep(): unknown data type %d", RANY(obj)->as.basic.flags & T_MASK);
    }
}

void
gc_mark_frame(frame)
    struct FRAME *frame;
{
    int n = frame->argc;
    VALUE *tbl = frame->argv;

    while (n--) {
	gc_mark_maybe(*tbl);
	tbl++;
    }
    gc_mark(frame->cbase);
}

#ifdef __GNUC__
#if defined(__human68k__) || defined(DJGPP)
#if defined(__human68k__)
typedef unsigned long rb_jmp_buf[8];
__asm__ (".even
_rb_setjmp:
	move.l	4(sp),a0
	movem.l	d3-d7/a3-a5,(a0)
	moveq.l	#0,d0
	rts");
#else
#if defined(DJGPP)
typedef unsigned long rb_jmp_buf[6];
__asm__ (".align 4
_rb_setjmp:
	pushl	%ebp
	movl	%esp,%ebp
	movl	8(%ebp),%ebp
	movl	%eax,(%ebp)
	movl	%ebx,4(%ebp)
	movl	%ecx,8(%ebp)
	movl	%edx,12(%ebp)
	movl	%esi,16(%ebp)
	movl	%edi,20(%ebp)
	popl	%ebp
	xorl	%eax,%eax
	ret");
#endif
#endif
int rb_setjmp (rb_jmp_buf);
#define jmp_buf rb_jmp_buf
#define setjmp rb_setjmp
#endif /* __human68k__ or DJGPP */
#endif /* __GNUC__ */

void
gc_gc()
{
    struct gc_list *list;
    struct FRAME *frame;
    jmp_buf save_regs_gc_mark;
    VALUE stack_end;

    if (dont_gc) return;
    dont_gc++;

    malloc_memories = 0;
#ifdef C_ALLOCA
    alloca(0);
#endif

    /* mark frame stack */
    for (frame = the_frame; frame; frame = frame->prev) {
	gc_mark_frame(frame);
    }
    gc_mark(the_scope);
    gc_mark(the_dyna_vars);

    FLUSH_REGISTER_WINDOWS;
    /* This assumes that all registers are saved into the jmp_buf */
    setjmp(save_regs_gc_mark);
    mark_locations_array((VALUE*)&save_regs_gc_mark, sizeof(save_regs_gc_mark) / sizeof(VALUE *));
    gc_mark_locations(gc_stack_start, (VALUE*)&stack_end);
#if defined(THINK_C) || defined(__human68k__)
#ifndef __human68k__
    mark_locations_array((VALUE*)((char*)save_regs_gc_mark+2),
			 sizeof(save_regs_gc_mark) / sizeof(VALUE *));
#endif
    gc_mark_locations((VALUE*)((char*)gc_stack_start + 2),
		   (VALUE*)((char*)&stack_end + 2));
#endif

#ifdef THREAD
    gc_mark_threads();
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

static VALUE
gc_method()
{
    gc_gc();
    return Qnil;
}

void
init_stack()
{
#ifdef __human68k__
    extern void *_SEND;
    gc_stack_start = _SEND;
#else
    VALUE start;

    gc_stack_start = &start;
#endif
}

void
init_heap()
{
    init_stack();
    add_heap();
}

static VALUE
os_live_obj()
{
    int i;
    int n = 0;

    for (i = 0; i < heaps_used; i++) {
	RVALUE *p, *pend;

	p = heaps[i]; pend = p + HEAP_SLOTS;
	for (;p < pend; p++) {
	    if (p->as.basic.flags) {
		switch (TYPE(p)) {
		  case T_ICLASS:
		  case T_VARMAP:
		  case T_SCOPE:
		  case T_NODE:
		    continue;
		  case T_CLASS:
		    if (FL_TEST(p, FL_SINGLETON)) continue;
		  default:
		    rb_yield((VALUE)p);
		    n++;
		}
	    }
	}
    }

    return INT2FIX(n);
}

static VALUE
os_obj_of(of)
    VALUE of;
{
    int i;
    int n = 0;

    for (i = 0; i < heaps_used; i++) {
	RVALUE *p, *pend;

	p = heaps[i]; pend = p + HEAP_SLOTS;
	for (;p < pend; p++) {
	    if (p->as.basic.flags) {
		switch (TYPE(p)) {
		  case T_ICLASS:
		  case T_VARMAP:
		  case T_SCOPE:
		  case T_NODE:
		    continue;
		  case T_CLASS:
		    if (FL_TEST(p, FL_SINGLETON)) continue;
		  default:
		    if (obj_is_kind_of((VALUE)p, of)) {
			rb_yield((VALUE)p);
			n++;
		    }
		}
	    }
	}
    }

    return INT2FIX(n);
}

static VALUE
os_each_obj(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE of;

    if (rb_scan_args(argc, argv, "01", &of) == 0) {
	return os_live_obj();
    }
    else {
	return os_obj_of(of);
    }
}

static VALUE finalizers;

static VALUE
add_final(os, proc)
    VALUE os, proc;
{
    extern VALUE cProc;

    if (!obj_is_kind_of(proc, cProc)) {
	ArgError("wrong type argument %s (Proc required)",
		  rb_class2name(CLASS_OF(proc)));
    }
    ary_push(finalizers, proc);
    return proc;
}

static VALUE
rm_final(os, proc)
    VALUE os, proc;
{
    ary_delete(finalizers, proc);
    return proc;
}

static VALUE
finals()
{
    return finalizers;
}

static VALUE
call_final(os, obj)
    VALUE os, obj;
{
    need_call_final = 1;
    FL_SET(obj, FL_FINALIZE);
    return obj;
}

static void
run_final(obj)
    VALUE obj;
{
    int i;

    if (!FL_TEST(obj, FL_FINALIZE)) return;

    obj = INT2NUM((int)obj);	/* make obj into id */
    for (i=0; i<RARRAY(finalizers)->len; i++) {
	rb_eval_cmd(RARRAY(finalizers)->ptr[i], ary_new3(1,obj));
    }
}

void
gc_call_finalizer_at_exit()
{
    RVALUE *p, *pend;
    int i;

    for (i = 0; i < heaps_used; i++) {
	p = heaps[i]; pend = p + HEAP_SLOTS;
	while (p < pend) {
	    run_final(p);
	    if (BUILTIN_TYPE(p) == T_DATA &&
		DATA_PTR(p) &&
		RANY(p)->as.data.dfree)
		(*RANY(p)->as.data.dfree)(DATA_PTR(p));
	    p++;
	}
    }
}

static VALUE
id2ref(obj, id)
    VALUE obj, id;
{
    INT ptr = NUM2INT(id);

    if (FIXNUM_P(ptr)) return (VALUE)ptr;
    if (!looks_pointerp(ptr)) {
	IndexError("0x%x is not the id value", ptr);
    }
    if (RANY(ptr)->as.free.flag == 0) {
	IndexError("0x%x is recycled object", ptr);
    }
    return (VALUE)ptr;
}

extern VALUE cModule;

void
Init_GC()
{
    VALUE mObSpace;

    mGC = rb_define_module("GC");
    rb_define_singleton_method(mGC, "start", gc_method, 0);
    rb_define_singleton_method(mGC, "enable", gc_s_enable, 0);
    rb_define_singleton_method(mGC, "disable", gc_s_disable, 0);
    rb_define_method(mGC, "garbage_collect", gc_method, 0);

    mObSpace = rb_define_module("ObjectSpace");
    rb_define_module_function(mObSpace, "each_object", os_each_obj, -1);
    rb_define_module_function(mObSpace, "garbage_collect", gc_method, 0);
    rb_define_module_function(mObSpace, "add_finalizer", add_final, 1);
    rb_define_module_function(mObSpace, "remove_finalizer", rm_final, 1);
    rb_define_module_function(mObSpace, "finalizers", finals, 0);
    rb_define_module_function(mObSpace, "call_finalizer", call_final, 1);
    rb_define_module_function(mObSpace, "id2ref", id2ref, 1);

    rb_global_variable(&finalizers);
    finalizers = ary_new();
}
