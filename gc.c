/************************************************

  gc.c -

  $Author$
  $Date$
  created at: Tue Oct  5 09:44:46 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#define RUBY_NO_INLINE
#include "ruby.h"
#include "rubysig.h"
#include "st.h"
#include "node.h"
#include "env.h"
#include "re.h"
#include <stdio.h>
#include <setjmp.h>

void re_free_registers _((struct re_registers*));
void rb_io_fptr_finalize _((struct OpenFile*));

#ifndef setjmp
#ifdef HAVE__SETJMP
#define setjmp(env) _setjmp(env)
#define longjmp(env,val) _longjmp(env,val)
#endif
#endif

#ifdef C_ALLOCA
#ifndef alloca
void *alloca();
#endif
#endif

static void run_final();

#ifndef GC_MALLOC_LIMIT
#if defined(MSDOS) || defined(__human68k__)
#define GC_MALLOC_LIMIT 100000
#else
#define GC_MALLOC_LIMIT 200000
#endif
#endif
#define GC_NEWOBJ_LIMIT 1000

static unsigned long malloc_memories = 0;
static unsigned long alloc_objects = 0;

void *
xmalloc(size)
    size_t size;
{
    void *mem;

    if (size < 0) {
	rb_raise(rb_eArgError, "negative allocation size (or too big)");
    }
    if (size == 0) size = 1;
    malloc_memories += size;
    if (malloc_memories > GC_MALLOC_LIMIT && alloc_objects > GC_NEWOBJ_LIMIT) {
	rb_gc();
    }
    mem = malloc(size);
    if (!mem) {
	rb_gc();
	mem = malloc(size);
	if (!mem)
	    rb_fatal("failed to allocate memory");
    }

    return mem;
}

void *
xcalloc(n, size)
    size_t n, size;
{
    void *mem;

    mem = xmalloc(n * size);
    memset(mem, 0, n * size);

    return mem;
}

void *
xrealloc(ptr, size)
    void *ptr;
    size_t size;
{
    void *mem;

    if (size < 0) {
	rb_raise(rb_eArgError, "negative re-allocation size");
    }
    if (!ptr) return xmalloc(size);
    if (size == 0) size = 1;
    malloc_memories += size;
    mem = realloc(ptr, size);
    if (!mem) {
	rb_gc();
	mem = realloc(ptr, size);
	if (!mem)
	    rb_fatal("failed to allocate memory(realloc)");
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

extern int ruby_in_compile;
static int dont_gc;
static int during_gc;
static int need_call_final = 0;

static VALUE
gc_enable()
{
    int old = dont_gc;

    dont_gc = Qfalse;
    return old;
}

static VALUE
gc_disable()
{
    int old = dont_gc;

    dont_gc = Qtrue;
    return old;
}

VALUE rb_mGC;

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
	    unsigned long flag;	/* always 0 for freed obj */
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
	struct RVarmap varmap; 
	struct SCOPE   scope;
    } as;
} RVALUE;

static RVALUE *freelist = 0;

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
	if (heaps == 0) rb_fatal("can't alloc memory");
    }

    p = heaps[heaps_used++] = (RVALUE*)malloc(sizeof(RVALUE)*HEAP_SLOTS);
    if (p == 0) rb_fatal("add_heap: can't alloc memory");
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
	alloc_objects++;
	return obj;
    }
    if (dont_gc || during_gc || rb_prohibit_interrupt) add_heap();
    else rb_gc();

    goto retry;
}

VALUE
rb_data_object_alloc(klass, datap, dmark, dfree)
    VALUE klass;
    void *datap;
    void (*dfree)();
    void (*dmark)();
{
    NEWOBJ(data, struct RData);
    OBJSETUP(data, klass, T_DATA);
    data->data = datap;
    data->dfree = dfree;
    data->dmark = dmark;

    return (VALUE)data;
}

extern st_table *rb_class_tbl;
VALUE *rb_gc_stack_start;

#if defined(__GNUC__) && __GNUC__ >= 2
__inline__
#endif
static int
looks_pointerp(ptr)
    void *ptr;
{
    register RVALUE *p = RANY(ptr);
    register RVALUE *heap_org;
    register long i;

    if (p < lomem || p > himem) return Qfalse;

    /* check if p looks like a pointer */
    for (i=0; i < heaps_used; i++) {
	heap_org = heaps[i];
	if (heap_org <= p && p < heap_org + HEAP_SLOTS
	    && ((((char*)p)-((char*)heap_org))%sizeof(RVALUE)) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

static void
mark_locations_array(x, n)
    register VALUE *x;
    register long n;
{
    while (n--) {
	if (looks_pointerp(*x)) {
	    rb_gc_mark(*x);
	}
	x++;
    }
}

void
rb_gc_mark_locations(start, end)
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
    rb_gc_mark(value);
    return ST_CONTINUE;
}

void
rb_mark_tbl(tbl)
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
    rb_gc_mark(key);
    rb_gc_mark(value);
    return ST_CONTINUE;
}

void
rb_mark_hash(tbl)
    st_table *tbl;
{
    if (!tbl) return;
    st_foreach(tbl, mark_hashentry, 0);
}

void
rb_gc_mark_maybe(obj)
    void *obj;
{
    if (looks_pointerp(obj)) {
	rb_gc_mark(obj);
    }
}

void
rb_gc_mark(ptr)
    void *ptr;
{
    register RVALUE *obj = RANY(ptr);

  Top:
    if (FIXNUM_P(obj)) return;	/* fixnum not marked */
    if (rb_special_const_p((VALUE)obj)) return; /* special const not marked */
    if (obj->as.basic.flags == 0) return; /* free cell */
    if (obj->as.basic.flags & FL_MARK) return; /* already marked */

    obj->as.basic.flags |= FL_MARK;

    if (FL_TEST(obj, FL_EXIVAR)) {
	rb_mark_generic_ivar((VALUE)obj);
    }

    switch (obj->as.basic.flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	rb_bug("rb_gc_mark() called for broken object");
	break;

      case T_NODE:
	switch (nd_type(obj)) {
	  case NODE_IF:		/* 1,2,3 */
	  case NODE_FOR:
	  case NODE_ITER:
	  case NODE_CREF:
	  case NODE_WHEN:
	  case NODE_MASGN:
	  case NODE_RESCUE:
	  case NODE_RESBODY:
	    rb_gc_mark(obj->as.node.u2.node);
	    /* fall through */
	  case NODE_BLOCK:	/* 1,3 */
	  case NODE_ARRAY:
	  case NODE_DSTR:
	  case NODE_DXSTR:
	  case NODE_EVSTR:
	  case NODE_DREGX:
	  case NODE_DREGX_ONCE:
	  case NODE_FBODY:
	  case NODE_ENSURE:
	  case NODE_CALL:
	  case NODE_DEFS:
	  case NODE_OP_ASGN1:
	    rb_gc_mark(obj->as.node.u1.node);
	    /* fall through */
	  case NODE_SUPER:	/* 3 */
	  case NODE_FCALL:
	  case NODE_DEFN:
	  case NODE_NEWLINE:
	    obj = RANY(obj->as.node.u3.node);
	    goto Top;

	  case NODE_WHILE:	/* 1,2 */
	  case NODE_UNTIL:
	  case NODE_AND:
	  case NODE_OR:
	  case NODE_CASE:
	  case NODE_SCLASS:
	  case NODE_ARGS:
	  case NODE_DOT2:
	  case NODE_DOT3:
	  case NODE_FLIP2:
	  case NODE_FLIP3:
	  case NODE_MATCH2:
	  case NODE_MATCH3:
	  case NODE_OP_ASGN_OR:
	  case NODE_OP_ASGN_AND:
	    rb_gc_mark(obj->as.node.u1.node);
	    /* fall through */
	  case NODE_METHOD:	/* 2 */
	  case NODE_NOT:
	  case NODE_GASGN:
	  case NODE_LASGN:
	  case NODE_DASGN:
	  case NODE_DASGN_PUSH:
	  case NODE_IASGN:
	  case NODE_CASGN:
	  case NODE_MODULE:
	  case NODE_COLON3:
	  case NODE_OPT_N:
	    obj = RANY(obj->as.node.u2.node);
	    goto Top;

	  case NODE_HASH:	/* 1 */
	  case NODE_LIT:
	  case NODE_STR:
	  case NODE_XSTR:
	  case NODE_DEFINED:
	  case NODE_MATCH:
	  case NODE_RETURN:
	  case NODE_YIELD:
	  case NODE_COLON2:
	    obj = RANY(obj->as.node.u1.node);
	    goto Top;

	  case NODE_SCOPE:	/* 2,3 */
	  case NODE_CLASS:
	  case NODE_BLOCK_PASS:
	    rb_gc_mark(obj->as.node.u3.node);
	    obj = RANY(obj->as.node.u2.node);
	    goto Top;

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
	  case NODE_ALIAS:
	  case NODE_VALIAS:
	  case NODE_BREAK:
	  case NODE_NEXT:
	  case NODE_REDO:
	  case NODE_RETRY:
	  case NODE_UNDEF:
	  case NODE_SELF:
	  case NODE_NIL:
	  case NODE_TRUE:
	  case NODE_FALSE:
	  case NODE_ATTRSET:
	  case NODE_BLOCK_ARG:
	  case NODE_POSTEXE:
	    break;
#ifdef C_ALLOCA
	  case NODE_ALLOCA:
	    mark_locations_array((VALUE*)obj->as.node.u1.value,
				 obj->as.node.u3.cnt);
	    obj = RANY(obj->as.node.u2.node);
	    goto Top;
#endif

	  default:
	    if (looks_pointerp(obj->as.node.u1.node)) {
		rb_gc_mark(obj->as.node.u1.node);
	    }
	    if (looks_pointerp(obj->as.node.u2.node)) {
		rb_gc_mark(obj->as.node.u2.node);
	    }
	    if (looks_pointerp(obj->as.node.u3.node)) {
		obj = RANY(obj->as.node.u3.node);
		goto Top;
	    }
	}
	return;			/* no need to mark class. */
    }

    rb_gc_mark(obj->as.basic.klass);
    switch (obj->as.basic.flags & T_MASK) {
      case T_ICLASS:
      case T_CLASS:
      case T_MODULE:
	rb_gc_mark(obj->as.klass.super);
	rb_mark_tbl(obj->as.klass.m_tbl);
	rb_mark_tbl(obj->as.klass.iv_tbl);
	break;

      case T_ARRAY:
	{
	    int i, len = obj->as.array.len;
	    VALUE *ptr = obj->as.array.ptr;

	    for (i=0; i < len; i++)
		rb_gc_mark(*ptr++);
	}
	break;

      case T_HASH:
	rb_mark_hash(obj->as.hash.tbl);
	rb_gc_mark(obj->as.hash.ifnone);
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
	rb_mark_tbl(obj->as.object.iv_tbl);
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
	rb_gc_mark(obj->as.varmap.val);
	obj = RANY(obj->as.varmap.next);
	goto Top;
	break;

      case T_SCOPE:
	if (obj->as.scope.local_vars) {
	    int n = obj->as.scope.local_tbl[0]+1;
	    VALUE *vars = &obj->as.scope.local_vars[-1];

	    while (n--) {
		rb_gc_mark(*vars);
		vars++;
	    }
	}
	break;

      case T_STRUCT:
	{
	    int i, len = obj->as.rstruct.len;
	    VALUE *ptr = obj->as.rstruct.ptr;

	    for (i=0; i < len; i++)
		rb_gc_mark(*ptr++);
	}
	break;

      default:
	rb_bug("rb_gc_mark(): unknown data type 0x%x(0x%x) %s",
	       obj->as.basic.flags & T_MASK, obj,
	       looks_pointerp(obj)?"corrupted object":"non object");
    }
}

#define MIN_FREE_OBJ 512

static void obj_free _((VALUE));

static void
gc_sweep()
{
    RVALUE *p, *pend, *final_list;
    int freed = 0;
    int i, used = heaps_used;

    if (ruby_in_compile) {
	/* sould not reclaim nodes during compilation */
	for (i = 0; i < used; i++) {
	    p = heaps[i]; pend = p + HEAP_SLOTS;
	    while (p < pend) {
		if (!(p->as.basic.flags&FL_MARK) && BUILTIN_TYPE(p) == T_NODE)
		    rb_gc_mark(p);
		p++;
	    }
	}
    }

    freelist = 0;
    final_list = 0;
    for (i = 0; i < used; i++) {
	int n = 0;

	p = heaps[i]; pend = p + HEAP_SLOTS;
	while (p < pend) {
	    if (!(p->as.basic.flags & FL_MARK)) {
		if (p->as.basic.flags) {
		    obj_free((VALUE)p);
		}
		if (need_call_final && FL_TEST(p, FL_FINALIZE)) {
		    p->as.free.flag = FL_MARK; /* remain marked */
		    p->as.free.next = final_list;
		    final_list = p;
		}
		else {
		    p->as.free.flag = 0;
		    p->as.free.next = freelist;
		    freelist = p;
		}
		n++;
	    }
	    else if (RBASIC(p)->flags == FL_MARK) {
		/* objects to be finalized */
		/* do notning remain marked */
	    }
	    else {
		RBASIC(p)->flags &= ~FL_MARK;
	    }
	    p++;
	}
	freed += n;
    }
    if (freed < FREE_MIN) {
	add_heap();
    }
    during_gc = 0;

    /* clear finalization list */
    if (need_call_final) {
	RVALUE *tmp;

	for (p = final_list; p; p = tmp) {
	    tmp = p->as.free.next;
	    run_final((VALUE)p);
	    p->as.free.flag = 0;
	    p->as.free.next = freelist;
	    freelist = p;
	}
    }
}

void
rb_gc_force_recycle(p)
    VALUE p;
{
    RANY(p)->as.free.flag = 0;
    RANY(p)->as.free.next = freelist;
    freelist = RANY(p);
}

static void
obj_free(obj)
    VALUE obj;
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
	if (RANY(obj)->as.object.iv_tbl) {
	    st_free_table(RANY(obj)->as.object.iv_tbl);
	}
	break;
      case T_MODULE:
      case T_CLASS:
	rb_clear_cache();
	st_free_table(RANY(obj)->as.klass.m_tbl);
	if (RANY(obj)->as.object.iv_tbl) {
	    st_free_table(RANY(obj)->as.object.iv_tbl);
	}
	break;
      case T_STRING:
#define STR_NO_ORIG FL_USER3	/* copied from string.c */
	if (!RANY(obj)->as.string.orig || FL_TEST(obj, STR_NO_ORIG))
	    free(RANY(obj)->as.string.ptr);
	break;
      case T_ARRAY:
	if (RANY(obj)->as.array.ptr) free(RANY(obj)->as.array.ptr);
	break;
      case T_HASH:
	if (RANY(obj)->as.hash.tbl)
	    st_free_table(RANY(obj)->as.hash.tbl);
	break;
      case T_REGEXP:
	if (RANY(obj)->as.regexp.ptr) re_free_pattern(RANY(obj)->as.regexp.ptr);
	if (RANY(obj)->as.regexp.str) free(RANY(obj)->as.regexp.str);
	break;
      case T_DATA:
	if (DATA_PTR(obj)) {
	    if ((long)RANY(obj)->as.data.dfree == -1) {
		free(DATA_PTR(obj));
	    }
	    else if (RANY(obj)->as.data.dfree) {
		(*RANY(obj)->as.data.dfree)(DATA_PTR(obj));
	    }
	}
	break;
      case T_MATCH:
	if (RANY(obj)->as.match.regs)
	    re_free_registers(RANY(obj)->as.match.regs);
	if (RANY(obj)->as.match.regs)
	    free(RANY(obj)->as.match.regs);
	break;
      case T_FILE:
	if (RANY(obj)->as.file.fptr) {
	    rb_io_fptr_finalize(RANY(obj)->as.file.fptr);
	    free(RANY(obj)->as.file.fptr);
	}
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
	switch (nd_type(obj)) {
	  case NODE_SCOPE:
	    if (RANY(obj)->as.node.u1.tbl) {
		free(RANY(obj)->as.node.u1.tbl);
	    }
	    break;
#ifdef C_ALLOCA
	  case NODE_ALLOCA:
	    free(RANY(obj)->as.node.u1.value);
	    break;
#endif
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
	if (RANY(obj)->as.rstruct.ptr)
	    free(RANY(obj)->as.rstruct.ptr);
	break;

      default:
	rb_bug("gc_sweep(): unknown data type %d",
	       RANY(obj)->as.basic.flags & T_MASK);
    }
}

void
rb_gc_mark_frame(frame)
    struct FRAME *frame;
{
    mark_locations_array(frame->argv, frame->argc);
    rb_gc_mark(frame->cbase);
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
rb_gc()
{
    struct gc_list *list;
    struct FRAME *frame;
    jmp_buf save_regs_gc_mark;
    VALUE stack_end;

    alloc_objects = 0;
    malloc_memories = 0;

    if (during_gc) return;
    during_gc++;

#ifdef C_ALLOCA
    alloca(0);
#endif

    /* mark frame stack */
    for (frame = ruby_frame; frame; frame = frame->prev) {
	rb_gc_mark_frame(frame);
    }
    rb_gc_mark(ruby_class);
    rb_gc_mark(ruby_scope);
    rb_gc_mark(ruby_dyna_vars);

    FLUSH_REGISTER_WINDOWS;
    /* This assumes that all registers are saved into the jmp_buf */
    setjmp(save_regs_gc_mark);
    mark_locations_array((VALUE*)&save_regs_gc_mark, sizeof(save_regs_gc_mark) / sizeof(VALUE *));
    rb_gc_mark_locations(rb_gc_stack_start, (VALUE*)&stack_end);
#if defined(THINK_C) || defined(__human68k__)
#ifndef __human68k__
    mark_locations_array((VALUE*)((char*)save_regs_gc_mark+2),
			 sizeof(save_regs_gc_mark) / sizeof(VALUE *));
#endif
    rb_gc_mark_locations((VALUE*)((char*)rb_gc_stack_start + 2),
		   (VALUE*)((char*)&stack_end + 2));
#endif

#ifdef USE_THREAD
    rb_gc_mark_threads();
#endif

    /* mark protected global variables */
    for (list = Global_List; list; list = list->next) {
	rb_gc_mark(*list->varptr);
    }
    rb_gc_mark_global_tbl();

    rb_mark_tbl(rb_class_tbl);
    rb_gc_mark_trap_list();

    /* mark generic instance variables for special constants */
    rb_mark_generic_ivar_tbl();

    gc_sweep();
}

static VALUE
gc_start()
{
    rb_gc();
    return Qnil;
}

void
Init_stack()
{
#ifdef __human68k__
    extern void *_SEND;
    gc_stack_start = _SEND;
#else
    VALUE start;

    rb_gc_stack_start = &start;
#endif
}

void
Init_heap()
{
    Init_stack();
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
		    if (rb_obj_is_kind_of((VALUE)p, of)) {
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
    if (!rb_obj_is_kind_of(proc, rb_cProc)) {
	rb_raise(rb_eArgError, "wrong type argument %s (Proc required)",
		 rb_class2name(CLASS_OF(proc)));
    }
    rb_ary_push(finalizers, proc);
    return proc;
}

static VALUE
rm_final(os, proc)
    VALUE os, proc;
{
    rb_ary_delete(finalizers, proc);
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

    obj = rb_obj_id(obj);	/* make obj into id */
    for (i=0; i<RARRAY(finalizers)->len; i++) {
	rb_eval_cmd(RARRAY(finalizers)->ptr[i], rb_ary_new3(1, obj));
    }
}

void
rb_gc_call_finalizer_at_exit()
{
    RVALUE *p, *pend;
    int i;

    /* run finalizers */
    for (i = 0; i < heaps_used; i++) {
	p = heaps[i]; pend = p + HEAP_SLOTS;
	while (p < pend) {
	    if (FL_TEST(p, FL_FINALIZE))
		run_final((VALUE)p);
	    p++;
	}
    }
    /* run data object's finaliers */
    for (i = 0; i < heaps_used; i++) {
	p = heaps[i]; pend = p + HEAP_SLOTS;
	while (p < pend) {
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
    unsigned long ptr;

    rb_secure(4);
    ptr = NUM2UINT(id);
    if (FIXNUM_P(ptr)) return (VALUE)ptr;
    if (ptr == Qtrue) return Qtrue;
    if (ptr == Qfalse) return Qfalse;
    if (ptr == Qnil) return Qnil;

    ptr = id ^ FIXNUM_FLAG;
    if (!looks_pointerp(ptr)) {
	rb_raise(rb_eIndexError, "0x%x is not id value", ptr);
    }
    if (BUILTIN_TYPE(ptr) == 0) {
	rb_raise(rb_eIndexError, "0x%x is recycled object", ptr);
    }
    return (VALUE)ptr;
}

void
Init_GC()
{
    VALUE rb_mObSpace;

    rb_mGC = rb_define_module("GC");
    rb_define_singleton_method(rb_mGC, "start", gc_start, 0);
    rb_define_singleton_method(rb_mGC, "enable", gc_enable, 0);
    rb_define_singleton_method(rb_mGC, "disable", gc_disable, 0);
    rb_define_method(rb_mGC, "garbage_collect", gc_start, 0);

    rb_mObSpace = rb_define_module("ObjectSpace");
    rb_define_module_function(rb_mObSpace, "each_object", os_each_obj, -1);
    rb_define_module_function(rb_mObSpace, "garbage_collect", gc_start, 0);
    rb_define_module_function(rb_mObSpace, "add_finalizer", add_final, 1);
    rb_define_module_function(rb_mObSpace, "remove_finalizer", rm_final, 1);
    rb_define_module_function(rb_mObSpace, "finalizers", finals, 0);
    rb_define_module_function(rb_mObSpace, "call_finalizer", call_final, 1);
    rb_define_module_function(rb_mObSpace, "_id2ref", id2ref, 1);

    rb_global_variable(&finalizers);
    finalizers = rb_ary_new();
}
