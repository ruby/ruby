/************************************************

  gc.c -

  $Author: matz $
  $Date: 1994/06/27 15:48:27 $
  created at: Tue Oct  5 09:44:46 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "env.h"
#include "st.h"
#include <stdio.h>

void *malloc();
void *calloc();
void *realloc();

struct gc_list *GC_List = Qnil;
static struct gc_list *Global_List = Qnil;
static unsigned long bytes_alloc = 0, gc_threshold = 1000000;

static mark_tbl();

void *
xmalloc(size)
    unsigned long size;
{
    void *mem;

    bytes_alloc += size;
    if (size == 0) size = 1;
    mem = malloc(size);
    if (mem == Qnil) {
	gc();
	bytes_alloc += size;
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
    bzero(mem, n * size);

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

static struct RBasic *object_list = Qnil;
static struct RBasic *literal_list = Qnil;
static unsigned long fl_current = FL_MARK;
static unsigned long fl_old = 0L;

static int dont_gc;

VALUE
Fgc_enable()
{
    int old = dont_gc;

    dont_gc = Qnil;
    return old;
}

VALUE
Fgc_disable()
{
    int old = dont_gc;

    dont_gc = TRUE;
    return old;
}

VALUE
Fgc_threshold(obj)
    VALUE obj;
{
    return INT2FIX(gc_threshold);
}

VALUE
Fgc_set_threshold(obj, val)
    VALUE obj, val;
{
    int old = gc_threshold;

    gc_threshold = NUM2INT(val);
    return INT2FIX(old);
}

#include <sys/types.h>
#include <sys/times.h>

static Fgc_begin()
{
    return Qnil;
}

static Fgc_end()
{
    return Qnil;
}

VALUE M_GC;

static ID start_hook, end_hook;

struct RBasic *
newobj(size)
    unsigned long size;
{
    struct RBasic *obj = Qnil;

    if (bytes_alloc + size > gc_threshold) {
	gc();
    }
    obj = (struct RBasic*)xmalloc(size);
    obj->next = object_list;
    object_list = obj;
    obj->flags = fl_current;
    obj->iv_tbl = Qnil;

    return obj;
}

literalize(obj)
    struct RBasic *obj;
{
    struct RBasic *ptr = object_list;

    if (NIL_P(obj) || FIXNUM_P(obj)) return;

    FL_SET(obj, FL_LITERAL);
    if (ptr == obj) {
	object_list = ptr->next;
	obj->next = literal_list;
	literal_list = obj;

	return;
    }

    while (ptr && ptr->next) {
	if (ptr->next == obj) {
	    ptr->next = obj->next;
	    obj->next = literal_list;
	    literal_list = obj;

	    return;
	}
	ptr = ptr->next;
    }
    Bug("0x%x is not a object.", obj);
}

void
unliteralize(obj)
    struct RBasic *obj;
{
    struct RBasic *ptr = literal_list;

    if (NIL_P(obj) || FIXNUM_P(obj)) return;

    if (!FL_TEST(obj, FL_LITERAL)) return;
    FL_UNSET(obj, FL_LITERAL);

    if (ptr == obj) {
	literal_list = ptr->next;
	goto unlit;
    }

    while (ptr->next) {
	if (ptr->next == obj) {
	    ptr->next = obj->next;
	}
	ptr = ptr->next;
	goto unlit;
    }
    Bug("0x%x is not a literal object.", obj);

  unlit:
    obj->next = object_list;
    object_list = obj;
    obj->flags &= ~FL_MARK;
    obj->flags |= fl_current;
    return;
}

extern st_table *rb_global_tbl;
extern st_table *rb_class_tbl;

gc()
{
    struct gc_list *list;
    struct ENVIRON *env;
    int i, max;

    rb_funcall(M_GC, start_hook, 0, Qnil);

    if (dont_gc) return;
    dont_gc++;
    fl_old = fl_current;
    fl_current = ~fl_current & FL_MARK;

    /* mark env stack */
    for (env = the_env; env; env = env->prev) {
	mark(env->self);
	for (i=1, max=env->argc; i<max; i++) {
	    mark(env->argv[i]);
	}
	if (env->local_vars) {
	    for (i=0, max=env->local_tbl[0]; i<max; i++)
		mark(env->local_vars[i]);
	}
    }

    /* mark protected C variables */
    for (list=GC_List; list; list=list->next) {
	VALUE *v = list->varptr;
	for (i=0, max = list->n; i<max; i++) {
	    mark(*v);
	    v++;
	}
    }

    /* mark protected global variables */
    for (list = Global_List; list; list = list->next) {
	mark(*list->varptr);
    }

    mark_global_tbl();
    mark_tbl(rb_class_tbl);

    mark_trap_list();

    sweep();
    bytes_alloc = 0;
    dont_gc--;

    rb_funcall(M_GC, end_hook, 0, Qnil);
}

static
mark_entry(key, value)
    ID key;
    VALUE value;
{
    mark(value);
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
    mark(key);
    mark(value);
    return ST_CONTINUE;
}

static
mark_dict(tbl)
    st_table *tbl;
{
    st_foreach(tbl, mark_dicentry, 0);
}

mark(obj)
    register struct RBasic *obj;
{
    if (obj == Qnil) return;
    if (FIXNUM_P(obj)) return;
    if ((obj->flags & FL_MARK) == fl_current) return;

    obj->flags &= ~FL_MARK;
    obj->flags |= fl_current;

    switch (obj->flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	Bug("mark() called for broken object");
	break;
    }

    if (obj->iv_tbl) mark_tbl(obj->iv_tbl);
    switch (obj->flags & T_MASK) {
      case T_OBJECT:
	mark(obj->class);
	break;
      case T_ICLASS:
	mark(RCLASS(obj)->super);
	if (RCLASS(obj)->c_tbl) mark_tbl(RCLASS(obj)->c_tbl);
	mark_tbl(RCLASS(obj)->m_tbl);
	break;
      case T_CLASS:
	mark(RCLASS(obj)->super);
      case T_MODULE:
	if (RCLASS(obj)->c_tbl) mark_tbl(RCLASS(obj)->c_tbl);
	mark_tbl(RCLASS(obj)->m_tbl);
	mark(RBASIC(obj)->class);
	break;
      case T_ARRAY:
	{
	    int i, len = RARRAY(obj)->len;
	    VALUE *ptr = RARRAY(obj)->ptr;

	    for (i=0; i < len; i++)
		mark(ptr[i]);
	}
	break;
      case T_DICT:
	mark_dict(RDICT(obj)->tbl);
	break;
      case T_STRING:
	if (RSTRING(obj)->orig) mark(RSTRING(obj)->orig);
	break;
      case T_DATA:
	if (RDATA(obj)->dmark) (*RDATA(obj)->dmark)(DATA_PTR(obj));
	break;
      case T_REGEXP:
      case T_FLOAT:
      case T_METHOD:
      case T_BIGNUM:
	break;
      case T_STRUCT:
	{
	    int i, len = RSTRUCT(obj)->len;
	    struct kv_pair *ptr = RSTRUCT(obj)->tbl;

	    for (i=0; i < len; i++)
		mark(ptr[i].value);
	}
	break;
      default:
	Bug("mark(): unknown data type %d", obj->flags & T_MASK);
    }
}

sweep()
{
    register struct RBasic *link = object_list;
    register struct RBasic *next;

    if (link && (link->flags & FL_MARK) == fl_old) {
	object_list = object_list->next;
	obj_free(link);
	link = object_list;
    }

    while (link && link->next) {
	if ((link->next->flags & FL_MARK) == fl_old) {
	    next = link->next->next;
	    obj_free(link->next);
	    link->next = next;
	    continue;
	}
	link = link->next;
    }
}

static
freemethod(key, body)
    ID key;
    char *body;
{
    freenode(body);
    return ST_CONTINUE;
}

obj_free(obj)
    struct RBasic *obj;
{
    switch (obj->flags & T_MASK) {
      case T_NIL:
      case T_FIXNUM:
	Bug("obj_free() called for broken object");
	break;
    }

    if (obj->iv_tbl) st_free_table(obj->iv_tbl);
    switch (obj->flags & T_MASK) {
      case T_OBJECT:
	break;
      case T_MODULE:
      case T_CLASS:
	st_foreach(RCLASS(obj)->m_tbl, freemethod);
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
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
      case T_FLOAT:
	break;
      case T_METHOD:
	freenode(RMETHOD(obj)->node);
	break;
      case T_STRUCT:
	free(RSTRUCT(obj)->name);
	free(RSTRUCT(obj)->tbl);
	break;
      case T_BIGNUM:
	free(RBIGNUM(obj)->digits);
	break;
      default:
	Bug("sweep(): unknown data type %d", obj->flags & T_MASK);
    }
    free(obj);
}

Init_GC()
{
    M_GC = rb_define_module("GC");
    rb_define_single_method(M_GC, "start", gc, 0);
    rb_define_single_method(M_GC, "enable", Fgc_enable, 0);
    rb_define_single_method(M_GC, "disable", Fgc_disable, 0);
    rb_define_single_method(M_GC, "threshold", Fgc_threshold, 0);
    rb_define_single_method(M_GC, "threshold=", Fgc_set_threshold, 1);
    rb_define_single_method(M_GC, "start_hook", Fgc_begin, 0);
    rb_define_single_method(M_GC, "end_hook", Fgc_end, 0);
    rb_define_func(M_GC, "garbage_collect", gc, 0);

    start_hook = rb_intern("start_hook");
    end_hook = rb_intern("end_hook");
}
