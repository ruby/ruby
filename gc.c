/**********************************************************************

  gc.c -

  $Author$
  $Date$
  created at: Tue Oct  5 09:44:46 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

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

#if !defined(setjmp) && defined(HAVE__SETJMP)
#define setjmp(env) _setjmp(env)
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
#  ifdef _AIX
 #pragma alloca
#  else
#   ifndef alloca /* predefined by HP cc +Olibcalls */
void *alloca ();
#   endif
#  endif /* AIX */
# endif /* HAVE_ALLOCA_H */
#endif /* __GNUC__ */

static void run_final();

#ifndef GC_MALLOC_LIMIT
#if defined(MSDOS) || defined(__human68k__)
#define GC_MALLOC_LIMIT 200000
#else
#define GC_MALLOC_LIMIT 8000000
#endif
#endif

static unsigned long malloc_memories = 0;

static void
mem_error(mesg)
    char *mesg;
{
    static int recurse = 0;

    if (rb_safe_level() >= 4) {
	rb_raise(rb_eNoMemError, mesg);
    }
    if (recurse == 0) {
	recurse++;
	rb_fatal(mesg);
    }
    fprintf(stderr, "[FATAL] failed to allocate memory\n");
    exit(1);
}

void *
ruby_xmalloc(size)
    long size;
{
    void *mem;

    if (size < 0) {
	rb_raise(rb_eNoMemError, "negative allocation size (or too big)");
    }
    if (size == 0) size = 1;
    malloc_memories += size;

    if (malloc_memories > GC_MALLOC_LIMIT) {
	rb_gc();
    }
    RUBY_CRITICAL(mem = malloc(size));
    if (!mem) {
	rb_gc();
	RUBY_CRITICAL(mem = malloc(size));
	if (!mem) {
	    if (size >= 10 * 1024 * 1024) {
		rb_raise(rb_eNoMemError, "tried to allocate too big memory");
	    }
	    mem_error("failed to allocate memory");
	}
    }

    return mem;
}

void *
ruby_xcalloc(n, size)
    long n, size;
{
    void *mem;

    mem = xmalloc(n * size);
    memset(mem, 0, n * size);

    return mem;
}

void *
ruby_xrealloc(ptr, size)
    void *ptr;
    long size;
{
    void *mem;

    if (size < 0) {
	rb_raise(rb_eArgError, "negative re-allocation size");
    }
    if (!ptr) return xmalloc(size);
    if (size == 0) size = 1;
    malloc_memories += size;
    RUBY_CRITICAL(mem = realloc(ptr, size));
    if (!mem) {
	rb_gc();
	RUBY_CRITICAL(mem = realloc(ptr, size));
	if (!mem) {
	    if (size >= 50 * 1024 * 1024) {
		rb_raise(rb_eNoMemError, "tried to re-allocate too big memory");
	    }
	    mem_error("failed to allocate memory(realloc)");
	}
    }

    return mem;
}

void
ruby_xfree(x)
    void *x;
{
    if (x)
	RUBY_CRITICAL(free(x));
}

extern int ruby_in_compile;
static int dont_gc;
static int during_gc;
static int need_call_final = 0;
static st_table *finalizer_table = 0;

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
rb_gc_register_address(addr)
    VALUE *addr;
{
    struct gc_list *tmp;

    tmp = ALLOC(struct gc_list);
    tmp->next = Global_List;
    tmp->varptr = addr;
    Global_List = tmp;
}

void
rb_gc_unregister_address(addr)
    VALUE *addr;
{
    struct gc_list *tmp = Global_List;

    if (tmp->varptr == addr) {
	Global_List = tmp->next;
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

void
rb_global_variable(var)
    VALUE *var;
{
    rb_gc_register_address(var);
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
static RVALUE *deferred_final_list = 0;

#define HEAPS_INCREMENT 10
static RVALUE **heaps;
static int heaps_length = 0;
static int heaps_used   = 0;

#define HEAP_MIN_SLOTS 10000
static int *heaps_limits;
static int heap_slots = HEAP_MIN_SLOTS;

#define FREE_MIN  4096

static RVALUE *himem, *lomem;

static void
add_heap()
{
    RVALUE *p, *pend;

    if (heaps_used == heaps_length) {
	/* Realloc heaps */
	heaps_length += HEAPS_INCREMENT;
	RUBY_CRITICAL(heaps = (heaps_used>0)?
			(RVALUE**)realloc(heaps, heaps_length*sizeof(RVALUE*)):
			(RVALUE**)malloc(heaps_length*sizeof(RVALUE*)));
	if (heaps == 0) mem_error("heaps: can't alloc memory");
	RUBY_CRITICAL(heaps_limits = (heaps_used>0)?
			(int*)realloc(heaps_limits, heaps_length*sizeof(int)):
			(int*)malloc(heaps_length*sizeof(int)));
	if (heaps_limits == 0) mem_error("heaps_limits: can't alloc memory");
    }

    for (;;) {
	RUBY_CRITICAL(p = heaps[heaps_used] = (RVALUE*)malloc(sizeof(RVALUE)*heap_slots));
	heaps_limits[heaps_used] = heap_slots;
	if (p == 0) {
	    if (heap_slots == HEAP_MIN_SLOTS) {
		mem_error("add_heap: can't alloc memory");
	    }
	    heap_slots = HEAP_MIN_SLOTS;
	    continue;
	}
	break;
    }
    pend = p + heap_slots;
    if (lomem == 0 || lomem > p) lomem = p;
    if (himem < pend) himem = pend;
    heaps_used++;
    heap_slots *= 2;

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

    if (!freelist) rb_gc();

    obj = (VALUE)freelist;
    freelist = freelist->as.free.next;
    MEMZERO((void*)obj, RVALUE, 1);
    return obj;
}

VALUE
rb_data_object_alloc(klass, datap, dmark, dfree)
    VALUE klass;
    void *datap;
    RUBY_DATA_FUNC dmark;
    RUBY_DATA_FUNC dfree;
{
    NEWOBJ(data, struct RData);
    OBJSETUP(data, klass, T_DATA);
    data->data = datap;
    data->dfree = dfree;
    data->dmark = dmark;

    return (VALUE)data;
}

extern st_table *rb_class_tbl;
VALUE *rb_gc_stack_start = 0;

static inline int
is_pointer_to_heap(ptr)
    void *ptr;
{
    register RVALUE *p = RANY(ptr);
    register RVALUE *heap_org;
    register long i;

    if (p < lomem || p > himem) return Qfalse;

    /* check if p looks like a pointer */
    for (i=0; i < heaps_used; i++) {
	heap_org = heaps[i];
	if (heap_org <= p && p < heap_org + heaps_limits[i] &&
	    ((((char*)p)-((char*)heap_org))%sizeof(RVALUE)) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

static st_table *source_filenames;

char *
rb_source_filename(f)
    const char *f;
{
    char *name;

    if (!st_lookup(source_filenames, f, &name)) {
	long len = strlen(f) + 1;
	char *ptr = name = ALLOC_N(char, len + 1);
	*ptr++ = 0;
	MEMCPY(ptr, f, char, len);
	st_add_direct(source_filenames, ptr, name);
	return ptr;
    }
    return name + 1;
}

static void
mark_source_filename(f)
    char *f;
{
    if (f) {
	f[-1] = 1;
    }
}

static enum st_retval
sweep_source_filename(key, value)
    char *key, *value;
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

static void
mark_locations_array(x, n)
    register VALUE *x;
    register long n;
{
    while (n--) {
	if (is_pointer_to_heap((void *)*x)) {
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
    n = end - start + 1;
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
    VALUE key;
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
    VALUE obj;
{
    if (is_pointer_to_heap((void *)obj)) {
	rb_gc_mark(obj);
    }
}

void
rb_gc_mark(ptr)
    VALUE ptr;
{
    register RVALUE *obj = RANY(ptr);

  Top:
    if (rb_special_const_p((VALUE)obj)) return; /* special const not marked */
    if (obj->as.basic.flags == 0) return;       /* free cell */
    if (obj->as.basic.flags & FL_MARK) return;  /* already marked */

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
	mark_source_filename(obj->as.node.nd_file);
	switch (nd_type(obj)) {
	  case NODE_IF:		/* 1,2,3 */
	  case NODE_FOR:
	  case NODE_ITER:
	  case NODE_CREF:
	  case NODE_WHEN:
	  case NODE_MASGN:
	  case NODE_RESCUE:
	  case NODE_RESBODY:
	    rb_gc_mark((VALUE)obj->as.node.u2.node);
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
	    rb_gc_mark((VALUE)obj->as.node.u1.node);
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
	  case NODE_DOT2:
	  case NODE_DOT3:
	  case NODE_FLIP2:
	  case NODE_FLIP3:
	  case NODE_MATCH2:
	  case NODE_MATCH3:
	  case NODE_OP_ASGN_OR:
	  case NODE_OP_ASGN_AND:
	    rb_gc_mark((VALUE)obj->as.node.u1.node);
	    /* fall through */
	  case NODE_METHOD:	/* 2 */
	  case NODE_NOT:
	  case NODE_GASGN:
	  case NODE_LASGN:
	  case NODE_DASGN:
	  case NODE_DASGN_CURR:
	  case NODE_IASGN:
	  case NODE_CDECL:
	  case NODE_CVDECL:
	  case NODE_CVASGN:
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
	  case NODE_BREAK:
	  case NODE_NEXT:
	  case NODE_YIELD:
	  case NODE_COLON2:
	  case NODE_ARGS:
	    obj = RANY(obj->as.node.u1.node);
	    goto Top;

	  case NODE_SCOPE:	/* 2,3 */
	  case NODE_CLASS:
	  case NODE_BLOCK_PASS:
	    rb_gc_mark((VALUE)obj->as.node.u3.node);
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
	    if (is_pointer_to_heap(obj->as.node.u1.node)) {
		rb_gc_mark((VALUE)obj->as.node.u1.node);
	    }
	    if (is_pointer_to_heap(obj->as.node.u2.node)) {
		rb_gc_mark((VALUE)obj->as.node.u2.node);
	    }
	    if (is_pointer_to_heap(obj->as.node.u3.node)) {
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
      case T_BLKTAG:
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
	if (obj->as.scope.local_vars && (obj->as.scope.flag & SCOPE_MALLOC)) {
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
	rb_bug("rb_gc_mark(): unknown data type 0x%lx(0x%lx) %s",
	       obj->as.basic.flags & T_MASK, (unsigned long)obj,
	       is_pointer_to_heap(obj) ? "corrupted object" : "non object");
    }
}

static void obj_free _((VALUE));

static void
gc_sweep()
{
    RVALUE *p, *pend, *final_list;
    int freed = 0;
    int i, used = heaps_used;

    if (ruby_in_compile && ruby_parser_stack_on_heap()) {
	/* should not reclaim nodes during compilation
           if yacc's semantic stack is not allocated on machine stack */
	for (i = 0; i < used; i++) {
	    p = heaps[i]; pend = p + heaps_limits[i];
	    while (p < pend) {
		if (!(p->as.basic.flags&FL_MARK) && BUILTIN_TYPE(p) == T_NODE)
		    rb_gc_mark((VALUE)p);
		p++;
	    }
	}
    }

    mark_source_filename(ruby_sourcefile);
    st_foreach(source_filenames, sweep_source_filename, 0);

    freelist = 0;
    final_list = deferred_final_list;
    deferred_final_list = 0;
    for (i = 0; i < used; i++) {
	int n = 0;

	p = heaps[i]; pend = p + heaps_limits[i];
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
    if (final_list) {
	RVALUE *tmp;

	if (rb_prohibit_interrupt || ruby_in_compile) {
	    deferred_final_list = final_list;
	    return;
	}

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
#define STR_NO_ORIG FL_USER2	/* copied from string.c */
	if (!RANY(obj)->as.string.orig || FL_TEST(obj, STR_NO_ORIG)) {
	    RUBY_CRITICAL(free(RANY(obj)->as.string.ptr));
	}
	break;
      case T_ARRAY:
	if (RANY(obj)->as.array.ptr) {
	    RUBY_CRITICAL(free(RANY(obj)->as.array.ptr));
	}
	break;
      case T_HASH:
	if (RANY(obj)->as.hash.tbl) {
	    st_free_table(RANY(obj)->as.hash.tbl);
	}
	break;
      case T_REGEXP:
	if (RANY(obj)->as.regexp.ptr) {
	    re_free_pattern(RANY(obj)->as.regexp.ptr);
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
	if (RANY(obj)->as.match.regs) {
	    re_free_registers(RANY(obj)->as.match.regs);
	    RUBY_CRITICAL(free(RANY(obj)->as.match.regs));
	}
	break;
      case T_FILE:
	if (RANY(obj)->as.file.fptr) {
	    rb_io_fptr_finalize(RANY(obj)->as.file.fptr);
	    RUBY_CRITICAL(free(RANY(obj)->as.file.fptr));
	}
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
	break;

      case T_FLOAT:
      case T_VARMAP:
      case T_BLKTAG:
	break;

      case T_BIGNUM:
	if (RANY(obj)->as.bignum.digits) {
	    RUBY_CRITICAL(free(RANY(obj)->as.bignum.digits));
	}
	break;
      case T_NODE:
	switch (nd_type(obj)) {
	  case NODE_SCOPE:
	    if (RANY(obj)->as.node.u1.tbl) {
		RUBY_CRITICAL(free(RANY(obj)->as.node.u1.tbl));
	    }
	    break;
#ifdef C_ALLOCA
	  case NODE_ALLOCA:
	    RUBY_CRITICAL(free(RANY(obj)->as.node.u1.node));
	    break;
#endif
	}
	return;			/* no need to free iv_tbl */

      case T_SCOPE:
	if (RANY(obj)->as.scope.local_vars &&
            RANY(obj)->as.scope.flag != SCOPE_ALLOCA) {
	    VALUE *vars = RANY(obj)->as.scope.local_vars-1;
	    if (vars[0] == 0)
		RUBY_CRITICAL(free(RANY(obj)->as.scope.local_tbl));
	    if (RANY(obj)->as.scope.flag&SCOPE_MALLOC)
		RUBY_CRITICAL(free(vars));
	}
	break;

      case T_STRUCT:
	if (RANY(obj)->as.rstruct.ptr) {
	    RUBY_CRITICAL(free(RANY(obj)->as.rstruct.ptr));
	}
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
__asm__ (".even\n\
_rb_setjmp:\n\
	move.l	4(sp),a0\n\
	movem.l	d3-d7/a3-a5,(a0)\n\
	moveq.l	#0,d0\n\
	rts");
#ifdef setjmp
#undef setjmp
#endif
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
#define jmp_buf rb_jmp_buf
#define setjmp rb_setjmp
#endif /* __human68k__ or DJGPP */
#endif /* __GNUC__ */

void
rb_gc()
{
    struct gc_list *list;
    struct FRAME * volatile frame; /* gcc 2.7.2.3 -O2 bug??  */
    jmp_buf save_regs_gc_mark;
#ifdef C_ALLOCA
    VALUE stack_end;
    alloca(0);
# define STACK_END (&stack_end)
#else
# if defined(__GNUC__) && (defined(__i386__) || defined(__mc68000__))
    VALUE *stack_end = __builtin_frame_address(0);
# else
    VALUE *stack_end = alloca(1);
# endif
# define STACK_END (stack_end)
#endif

    if (dont_gc || during_gc) {
	if (!freelist || malloc_memories > GC_MALLOC_LIMIT) {
	    malloc_memories = 0;
	    add_heap();
	}
	return;
    }

    malloc_memories = 0;

    if (during_gc) return;
    during_gc++;

    /* mark frame stack */
    for (frame = ruby_frame; frame; frame = frame->prev) {
	rb_gc_mark_frame(frame); 
	if (frame->tmp) {
	    struct FRAME *tmp = frame->tmp;
	    while (tmp) {
		rb_gc_mark_frame(tmp);
		tmp = tmp->prev;
	    }
	}
    }
    rb_gc_mark(ruby_class);
    rb_gc_mark((VALUE)ruby_scope);
    rb_gc_mark((VALUE)ruby_dyna_vars);
    if (finalizer_table) {
	rb_mark_tbl(finalizer_table);
    }

    FLUSH_REGISTER_WINDOWS;
    /* This assumes that all registers are saved into the jmp_buf */
    setjmp(save_regs_gc_mark);
    mark_locations_array((VALUE*)save_regs_gc_mark, sizeof(save_regs_gc_mark) / sizeof(VALUE *));
    rb_gc_mark_locations(rb_gc_stack_start, (VALUE*)STACK_END);
#if defined(__human68k__)
    rb_gc_mark_locations((VALUE*)((char*)rb_gc_stack_start + 2),
			 (VALUE*)((char*)STACK_END + 2));
#endif
    rb_gc_mark_threads();

    /* mark protected global variables */
    for (list = Global_List; list; list = list->next) {
	rb_gc_mark(*list->varptr);
    }
    rb_mark_end_proc();
    rb_gc_mark_global_tbl();

    rb_mark_tbl(rb_class_tbl);
    rb_gc_mark_trap_list();

    /* mark generic instance variables for special constants */
    rb_mark_generic_ivar_tbl();

    rb_gc_mark_parser();

    gc_sweep();
}

static VALUE
gc_start()
{
    rb_gc();
    return Qnil;
}

void
Init_stack(addr)
    VALUE *addr;
{
#if defined(__human68k__)
    extern void *_SEND;
    rb_gc_stack_start = _SEND;
#else
    if (!addr) addr = (VALUE *)&addr;
    rb_gc_stack_start = addr;
#endif
}

void
Init_heap()
{
    if (!rb_gc_stack_start) {
	Init_stack(0);
    }
    add_heap();
}

static VALUE
os_live_obj()
{
    int i;
    int n = 0;

    for (i = 0; i < heaps_used; i++) {
	RVALUE *p, *pend;

	p = heaps[i]; pend = p + heaps_limits[i];
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
		    if (!p->as.basic.klass) continue;
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

	p = heaps[i]; pend = p + heaps_limits[i];
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
		    if (!p->as.basic.klass) continue;
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
    rb_warn("ObjectSpace::add_finalizer is deprecated; use define_finalizer");
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
    rb_warn("ObjectSpace::remove_finalizer is deprecated; use undefine_finalizer");
    rb_ary_delete(finalizers, proc);
    return proc;
}

static VALUE
finals()
{
    rb_warn("ObjectSpace::finalizers is deprecated");
    return finalizers;
}

static VALUE
call_final(os, obj)
    VALUE os, obj;
{
    rb_warn("ObjectSpace::call_final is deprecated; use define_finalizer");
    need_call_final = 1;
    FL_SET(obj, FL_FINALIZE);
    return obj;
}

static VALUE
undefine_final(os, obj)
    VALUE os, obj;
{
    VALUE table;

    if (finalizer_table) {
	st_delete(finalizer_table, &obj, 0);
    }
    return obj;
}

static VALUE
define_final(argc, argv, os)
    int argc;
    VALUE *argv;
    VALUE os;
{
    VALUE obj, proc, table;

    rb_scan_args(argc, argv, "11", &obj, &proc);
    if (argc == 1) {
	proc = rb_f_lambda();
    }
    else if (!rb_obj_is_kind_of(proc, rb_cProc)) {
	rb_raise(rb_eArgError, "wrong type argument %s (Proc required)",
		 rb_class2name(CLASS_OF(proc)));
    }
    need_call_final = 1;
    FL_SET(obj, FL_FINALIZE);

    if (!finalizer_table) {
	finalizer_table = st_init_numtable();
    }
    if (st_lookup(finalizer_table, obj, &table)) {
	rb_ary_push(table, proc);
    }
    else {
	st_add_direct(finalizer_table, obj, rb_ary_new3(1, proc));
    }
    return proc;
}

static VALUE
run_single_final(args)
    VALUE *args;
{
    rb_eval_cmd(args[0], args[1]);
    return Qnil;
}

static void
run_final(obj)
    VALUE obj;
{
    int i, status;
    VALUE args[2], table;

    args[1] = rb_ary_new3(1, rb_obj_id(obj)); /* make obj into id */
    for (i=0; i<RARRAY(finalizers)->len; i++) {
	args[0] = RARRAY(finalizers)->ptr[i];
	rb_protect(run_single_final, (VALUE)args, &status);
    }
    if (finalizer_table && st_delete(finalizer_table, &obj, &table)) {
	for (i=0; i<RARRAY(table)->len; i++) {
	    args[0] = RARRAY(table)->ptr[i];
	    rb_protect(run_single_final, (VALUE)args, &status);
	}
    }
}

void
rb_gc_call_finalizer_at_exit()
{
    RVALUE *p, *pend;
    int i;

    /* run finalizers */
    if (need_call_final) {
	if (deferred_final_list) {
	    p = deferred_final_list;
	    while (p) {
		RVALUE *tmp = p;
		p = p->as.free.next;
		run_final((VALUE)tmp);
	    }
	}
	for (i = 0; i < heaps_used; i++) {
	    p = heaps[i]; pend = p + heaps_limits[i];
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
    /* run data object's finaliers */
    for (i = 0; i < heaps_used; i++) {
	p = heaps[i]; pend = p + heaps_limits[i];
	while (p < pend) {
	    if (BUILTIN_TYPE(p) == T_DATA &&
		DATA_PTR(p) && RANY(p)->as.data.dfree) {
		p->as.free.flag = 0;
		(*RANY(p)->as.data.dfree)(DATA_PTR(p));
	    }
	    else if (BUILTIN_TYPE(p) == T_FILE) {
		p->as.free.flag = 0;
		rb_io_fptr_finalize(RANY(p)->as.file.fptr);
	    }
	    p++;
	}
    }
}

static VALUE
id2ref(obj, id)
    VALUE obj, id;
{
    unsigned long ptr, p0;

    rb_secure(4);
    p0 = ptr = NUM2ULONG(id);
    if (ptr == Qtrue) return Qtrue;
    if (ptr == Qfalse) return Qfalse;
    if (ptr == Qnil) return Qnil;
    if (FIXNUM_P(ptr)) return (VALUE)ptr;
    if (SYMBOL_P(ptr) && rb_id2name(SYM2ID((VALUE)ptr)) != 0) {
	return (VALUE)ptr;
    }

    ptr = id ^ FIXNUM_FLAG;	/* unset FIXNUM_FLAG */
    if (!is_pointer_to_heap((void *)ptr)) {
	rb_raise(rb_eRangeError, "0x%lx is not id value", p0);
    }
    if (BUILTIN_TYPE(ptr) == 0) {
	rb_raise(rb_eRangeError, "0x%lx is recycled object", p0);
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

    rb_define_module_function(rb_mObSpace, "define_finalizer", define_final, -1);
    rb_define_module_function(rb_mObSpace, "undefine_finalizer", undefine_final, 1);

    rb_define_module_function(rb_mObSpace, "_id2ref", id2ref, 1);

    rb_gc_register_address(&rb_mObSpace);
    rb_global_variable(&finalizers);
    rb_gc_unregister_address(&rb_mObSpace);
    finalizers = rb_ary_new();

    source_filenames = st_init_strtable();
}
