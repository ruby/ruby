/************************************************

  eval.c -

  $Author$
  $Date$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "node.h"
#include "env.h"
#include "rubysig.h"

#include <stdio.h>
#include <setjmp.h>
#include "st.h"
#include "dln.h"

#ifndef HAVE_STRING_H
char *strrchr _((const char*,const char));
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef __BEOS__
#include <net/socket.h>
#endif

#ifdef USE_CWGUSI
#include <sys/stat.h>
#include <sys/errno.h>
#include <compat.h>
#endif

#ifdef __MACOS__
#include "macruby_private.h"
#endif

#ifndef setjmp
#ifdef HAVE__SETJMP
#define setjmp(env) _setjmp(env)
#define longjmp(env,val) _longjmp(env,val)
#endif
#endif

VALUE rb_cProc;
static VALUE rb_cBinding;
static VALUE proc_call _((VALUE,VALUE));
static VALUE rb_f_binding _((VALUE));
static void rb_f_END _((void));
static VALUE rb_f_iterator_p _((void));
static VALUE block_pass _((VALUE,NODE*));
static VALUE rb_cMethod;
static VALUE method_proc _((VALUE));

static int scope_vmode;
#define SCOPE_PUBLIC    0
#define SCOPE_PRIVATE   1
#define SCOPE_PROTECTED 2
#define SCOPE_MODFUNC   5
#define SCOPE_MASK      7
#define SCOPE_SET(f)  do {scope_vmode=(f);} while(0)
#define SCOPE_TEST(f) (scope_vmode&(f))

static void print_undef _((VALUE, ID)) NORETURN;
static void
print_undef(klass, id)
    VALUE klass;
    ID id;
{
    rb_raise(rb_eNameError, "undefined method `%s' for %s `%s'",
	     rb_id2name(id), 
	     (TYPE(klass) == T_MODULE)?"module":"class",
	     rb_class2name(klass));
}


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

void
rb_clear_cache()
{
    struct cache_entry *ent, *end;

    ent = cache; end = ent + CACHE_SIZE;
    while (ent < end) {
	ent->mid = 0;
	ent++;
    }
}

static void
rb_clear_cache_by_id(id)
    ID id;
{
    struct cache_entry *ent, *end;

    ent = cache; end = ent + CACHE_SIZE;
    while (ent < end) {
	if (ent->mid == id) {
	    ent->mid = 0;
	}
	ent++;
    }
}

void
rb_add_method(klass, mid, node, noex)
    VALUE klass;
    ID mid;
    NODE *node;
    int noex;
{
    NODE *body;

    if (NIL_P(klass)) klass = rb_cObject;
    if (klass == rb_cObject) {
	rb_secure(4);
    }
    body = NEW_METHOD(node, noex);
    st_insert(RCLASS(klass)->m_tbl, mid, body);
}

static NODE*
search_method(klass, id, origin)
    VALUE klass, *origin;
    ID id;
{
    NODE *body;

    if (!klass) return 0;
    while (!st_lookup(RCLASS(klass)->m_tbl, id, &body)) {
	klass = RCLASS(klass)->super;
	if (!klass) return 0;
    }

    if (origin) *origin = klass;
    return body;
}

static NODE*
rb_get_method_body(klassp, idp, noexp)
    VALUE *klassp;
    ID *idp;
    int *noexp;
{
    ID id = *idp;
    VALUE klass = *klassp;
    VALUE origin;
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

    /* store in cache */
    ent = cache + EXPR1(klass, id);
    ent->klass  = klass;
    ent->noex   = body->nd_noex;
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

    if (noexp) *noexp = ent->noex;
    return body;
}

void
rb_alias(klass, name, def)
    VALUE klass;
    ID name, def;
{
    VALUE origin;
    NODE *orig, *body;

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
    body = orig->nd_body;
    if (nd_type(body) == NODE_FBODY) { /* was alias */
	def = body->nd_mid;
	origin = body->nd_orig;
	body = body->nd_head;
    }

    st_insert(RCLASS(klass)->m_tbl, name,
	      NEW_METHOD(NEW_FBODY(body, def, origin), orig->nd_noex));
}

static void
remove_method(klass, mid)
    VALUE klass;
    ID mid;
{
    NODE *body;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    if (!st_delete(RCLASS(klass)->m_tbl, &mid, &body)) {
	rb_raise(rb_eNameError, "method `%s' not defined in %s",
		 rb_id2name(mid), rb_class2name(klass));
    }
    rb_clear_cache_by_id(mid);
}

void
rb_remove_method(klass, name)
    VALUE klass;
    const char *name;
{
    remove_method(klass, rb_intern(name));
}

void
rb_disable_super(klass, name)
    VALUE klass;
    const char *name;
{
    VALUE origin;
    NODE *body;
    ID mid = rb_intern(name);

    body = search_method(klass, mid, &origin);
    if (!body || !body->nd_body) {
	print_undef(klass, mid);
    }
    if (origin == klass) {
	body->nd_noex |= NOEX_UNDEF;
    }
    else {
	rb_clear_cache_by_id(mid);
	rb_add_method(ruby_class, mid, 0, NOEX_UNDEF);
    }
}

void
rb_enable_super(klass, name)
    VALUE klass;
    const char *name;
{
    VALUE origin;
    NODE *body;
    ID mid = rb_intern(name);

    body = search_method(klass, mid, &origin);
    if (!body) {
	print_undef(klass, mid);
    }
    if (!body->nd_body) {
	remove_method(klass, mid);
    }
    else {
	body->nd_noex &= ~NOEX_UNDEF;
    }
}

static void
rb_export_method(klass, name, noex)
    VALUE klass;
    ID name;
    ID noex;
{
    NODE *body;
    VALUE origin;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    body = search_method(klass, name, &origin);
    if (!body && TYPE(klass) == T_MODULE) {
	body = search_method(rb_cObject, name, &origin);
    }
    if (!body) {
	print_undef(klass, name);
    }
    if (body->nd_noex != noex) {
	if (klass == origin) {
	    body->nd_noex = noex;
	}
	else {
	    rb_clear_cache_by_id(name);
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

    if (!ex) noex = NOEX_PUBLIC;
    else {
	if (SCOPE_TEST(SCOPE_PRIVATE)) {
	    noex = NOEX_PRIVATE;
	    rb_warning("private attribute?");
	}
	else if (SCOPE_TEST(SCOPE_PROTECTED)) {
	    noex = NOEX_PROTECTED;
	}
	else {
	    noex = NOEX_PUBLIC;
	}
    }

    name = rb_id2name(id);
    if (!name) {
	rb_raise(rb_eArgError, "argument needs to be symbol or string");
    }
    buf = ALLOCA_N(char,strlen(name)+2);
    sprintf(buf, "@%s", name);
    attriv = rb_intern(buf);
    if (read) {
	rb_add_method(klass, id, NEW_IVAR(attriv), noex);
	rb_funcall(klass, rb_intern("method_added"), 1, INT2FIX(id));
    }
    sprintf(buf, "%s=", name);
    id = rb_intern(buf);
    if (write) {
	rb_add_method(klass, id, NEW_ATTRSET(attriv), noex);
	rb_funcall(klass, rb_intern("method_added"), 1, INT2FIX(id));
    }
}

static ID init, eqq, each, aref, aset, match, missing;
VALUE ruby_errinfo = Qnil;
extern NODE *ruby_eval_tree_begin;
extern NODE *ruby_eval_tree;
extern int ruby_nerrs;

static VALUE rb_eLocalJumpError;
static VALUE rb_eSysStackError;

extern VALUE ruby_top_self;

struct FRAME *ruby_frame;
struct SCOPE *ruby_scope;
static struct FRAME *top_frame;
static struct SCOPE *top_scope;

#define PUSH_FRAME() {			\
    struct FRAME _frame;		\
    _frame.prev = ruby_frame;		\
    _frame.tmp  = 0;			\
    _frame.file = ruby_sourcefile;	\
    _frame.line = ruby_sourceline;	\
    _frame.iter = ruby_iter->iter;	\
    _frame.cbase = ruby_frame->cbase;	\
    _frame.argc = 0;			\
    _frame.argv = 0;			\
    _frame.flags = FRAME_ALLOCA;	\
    ruby_frame = &_frame;		\

#define POP_FRAME()  			\
    ruby_sourcefile = _frame.file;	\
    ruby_sourceline = _frame.line;	\
    ruby_frame = _frame.prev; }

struct BLOCK {
    NODE *var;
    NODE *body;
    VALUE self;
    struct FRAME frame;
    struct SCOPE *scope;
    VALUE klass;
    struct tag *tag;
    int iter;
    int vmode;
    int flags;
    struct RVarmap *d_vars;
    VALUE orig_thread;
    struct BLOCK *prev;
};

#define BLOCK_D_SCOPE 1
#define BLOCK_DYNAMIC 2

static struct BLOCK *ruby_block;

#define PUSH_BLOCK(v,b) {		\
    struct BLOCK _block;		\
    _block.tag = prot_tag;		\
    _block.var = v;			\
    _block.body = b;			\
    _block.self = self;			\
    _block.frame = *ruby_frame;		\
    _block.klass = ruby_class;		\
    _block.frame.file = ruby_sourcefile;\
    _block.frame.line = ruby_sourceline;\
    _block.scope = ruby_scope;		\
    _block.prev = ruby_block;		\
    _block.iter = ruby_iter->iter;	\
    _block.vmode = scope_vmode;		\
    _block.flags = BLOCK_D_SCOPE;	\
    _block.d_vars = ruby_dyna_vars;	\
    ruby_block = &_block;

#define POP_BLOCK() 			\
   ruby_block = _block.prev; 		\
}

#define PUSH_BLOCK2(b) {		\
    struct BLOCK * volatile _old;	\
    _old = ruby_block;			\
    ruby_block = b;

#define POP_BLOCK2() 			\
   ruby_block = _old;	 		\
}

struct RVarmap *ruby_dyna_vars;
#define PUSH_VARS() {			\
    struct RVarmap * volatile _old;	\
    _old = ruby_dyna_vars;		\
    ruby_dyna_vars = 0;

#define POP_VARS()			\
    ruby_dyna_vars = _old;		\
}

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
dvar_asgn(id, value, push)
    ID id;
    VALUE value;
    int push;
{
    struct RVarmap *vars = ruby_dyna_vars;

    while (vars) {
	if (push && vars->id == 0) {
	    rb_dvar_push(id, value);
	    return;
	}
	if (vars->id == id) {
	    vars->val = value;
	    return;
	}
	vars = vars->next;
    }

    vars = 0;
    if (ruby_dyna_vars && ruby_dyna_vars->id == 0) {
	vars = ruby_dyna_vars;
	ruby_dyna_vars = ruby_dyna_vars->next;
    }
    rb_dvar_push(id, value);
    if (vars) {
	vars->next = ruby_dyna_vars;
	ruby_dyna_vars = vars;
    }
}

void
rb_dvar_asgn(id, value)
    ID id;
    VALUE value;
{
    dvar_asgn(id, value, 0);
}

static void
dvar_asgn_push(id, value)
    ID id;
    VALUE value;
{
    struct RVarmap* vars = 0;

    if (ruby_dyna_vars && ruby_dyna_vars->id == 0) {
	vars = ruby_dyna_vars;
	ruby_dyna_vars = ruby_dyna_vars->next;
    }
    dvar_asgn(id, value, 1);
    if (vars) {
	vars->next = ruby_dyna_vars;
	ruby_dyna_vars = vars;
    }
}

struct iter {
    int iter;
    struct iter *prev;
};
static struct iter *ruby_iter;

#define ITER_NOT 0
#define ITER_PRE 1
#define ITER_CUR 2

#define PUSH_ITER(i) {			\
    struct iter _iter;			\
    _iter.prev = ruby_iter;		\
    _iter.iter = (i);			\
    ruby_iter = &_iter;			\

#define POP_ITER()			\
    ruby_iter = _iter.prev;		\
}

struct tag {
    jmp_buf buf;
    struct FRAME *frame;
    struct iter *iter;
    ID tag;
    VALUE retval;
    struct SCOPE *scope;
    int dst;
    struct tag *prev;
};
static struct tag *prot_tag;

#define PUSH_TAG(ptag) {		\
    struct tag _tag;			\
    _tag.retval = Qnil;			\
    _tag.frame = ruby_frame;		\
    _tag.iter = ruby_iter;		\
    _tag.prev = prot_tag;		\
    _tag.retval = Qnil;			\
    _tag.scope = ruby_scope;		\
    _tag.tag = ptag;			\
    _tag.dst = 0;			\
    prot_tag = &_tag;

#define PROT_NONE   0
#define PROT_FUNC   -1
#define PROT_THREAD -2

#define EXEC_TAG()    setjmp(prot_tag->buf)

#define JUMP_TAG(st) {			\
    ruby_frame = prot_tag->frame;	\
    ruby_iter = prot_tag->iter;		\
    longjmp(prot_tag->buf,(st));	\
}

#define POP_TAG()			\
    if (_tag.prev)			\
        _tag.prev->retval = _tag.retval;\
    prot_tag = _tag.prev;		\
}

#define POP_TMPTAG()			\
    prot_tag = _tag.prev;		\
}

#define TAG_RETURN	0x1
#define TAG_BREAK	0x2
#define TAG_NEXT	0x3
#define TAG_RETRY	0x4
#define TAG_REDO	0x5
#define TAG_RAISE	0x6
#define TAG_THROW	0x7
#define TAG_FATAL	0x8
#define TAG_MASK	0xf

VALUE ruby_class;
static VALUE ruby_wrapper;	/* security wrapper */

#define PUSH_CLASS() {			\
    VALUE _class = ruby_class;		\

#define POP_CLASS() ruby_class = _class; }

#define PUSH_SCOPE() {			\
    volatile int _vmode = scope_vmode;	\
    struct SCOPE * volatile _old;	\
    NEWOBJ(_scope, struct SCOPE);	\
    OBJSETUP(_scope, 0, T_SCOPE);	\
    _scope->local_tbl = 0;		\
    _scope->local_vars = 0;		\
    _scope->flag = 0;			\
    _old = ruby_scope;			\
    ruby_scope = _scope;		\
    scope_vmode = SCOPE_PUBLIC;

#define SCOPE_DONT_RECYCLE FL_USER2
#define POP_SCOPE() 			\
    if (FL_TEST(ruby_scope, SCOPE_DONT_RECYCLE)) {\
	FL_SET(_old, SCOPE_DONT_RECYCLE);\
    }					\
    else {				\
	if (ruby_scope->flag == SCOPE_ALLOCA) {\
	    ruby_scope->local_vars = 0;	\
	    ruby_scope->local_tbl  = 0;	\
	    if (ruby_scope != top_scope)\
		rb_gc_force_recycle((VALUE)ruby_scope);\
	}				\
	else {				\
	    ruby_scope->flag |= SCOPE_NOSTACK;\
	}				\
    }					\
    ruby_scope = _old;			\
    scope_vmode = _vmode;		\
}

static VALUE rb_eval _((VALUE,NODE*));
static VALUE eval _((VALUE,VALUE,VALUE,char*,int));
static NODE *compile _((VALUE, char*, int));
static VALUE rb_yield_0 _((VALUE, VALUE, VALUE, int));

static VALUE rb_call _((VALUE,VALUE,ID,int,VALUE*,int));
static VALUE module_setup _((VALUE,NODE*));

static VALUE massign _((VALUE,NODE*,VALUE,int));
static void assign _((VALUE,NODE*,VALUE,int));

static int safe_level = 0;
/* safe-level:
   0 - strings from streams/environment/ARGV are tainted (default)
   1 - no dangerous operation by tainted string
   2 - process/file operations prohibited
   3 - all genetated strings are tainted
   4 - no global (non-tainted) variable modification/no direct output
*/

int
rb_safe_level()
{
    return safe_level;
}

void
rb_set_safe_level(level)
    int level;
{
    if (level > safe_level) {
	safe_level = level;
    }
}

static VALUE
safe_getter()
{
    return INT2FIX(safe_level);
}

static void
safe_setter(val)
    VALUE val;
{
    int level = NUM2INT(val);

    if (level < safe_level) {
	rb_raise(rb_eSecurityError, "tried to downgrade safe level from %d to %d",
		 safe_level, level);
    }
    safe_level = level;
}

void
rb_check_safe_str(x)
    VALUE x;
{
    if (TYPE(x)!= T_STRING) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected String)",
		 rb_class2name(CLASS_OF(x)));
    }
    if (OBJ_TAINTED(x)) {
	if (safe_level > 0){
	    rb_raise(rb_eSecurityError, "Insecure operation - %s",
		     rb_id2name(ruby_frame->last_func));
	}
    }
}

void
rb_secure(level)
    int level;
{
    if (level <= safe_level) {
	rb_raise(rb_eSecurityError, "Insecure operation `%s' for level %d",
		 rb_id2name(ruby_frame->last_func), safe_level);
    }
}

static VALUE trace_func = 0;
static void call_trace_func _((char*,char*,int,VALUE,ID,VALUE));

static void
error_pos()
{
    if (ruby_sourcefile) {
	if (ruby_frame->last_func) {
	    fprintf(stderr, "%s:%d:in `%s'", ruby_sourcefile, ruby_sourceline,
		    rb_id2name(ruby_frame->last_func));
	}
	else {
	    fprintf(stderr, "%s:%d", ruby_sourcefile, ruby_sourceline);
	}
    }
}

static VALUE
get_backtrace(info)
    VALUE info;
{
    if (NIL_P(info)) return Qnil;
    return rb_funcall(info, rb_intern("backtrace"), 0);
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
    VALUE errat;
    VALUE eclass;
    char *einfo;
    int elen;

    if (NIL_P(ruby_errinfo)) return;

    PUSH_TAG(PROT_NONE);
    if (EXEC_TAG() == 0) {
	errat = get_backtrace(ruby_errinfo);
    }
    else {
	errat = Qnil;
    }
    POP_TAG();
    if (!NIL_P(errat)) {
	VALUE mesg = RARRAY(errat)->ptr[0];

	if (NIL_P(mesg)) error_pos();
	else {
	    fwrite(RSTRING(mesg)->ptr, 1, RSTRING(mesg)->len, stderr);
	}
    }

    eclass = CLASS_OF(ruby_errinfo);
    PUSH_TAG(PROT_NONE);
    if (EXEC_TAG() == 0) {
	einfo = str2cstr(rb_obj_as_string(ruby_errinfo), &elen);
    }
    else {
	einfo = "";
	elen = 0;
    }
    POP_TAG();
    if (eclass == rb_eRuntimeError && elen == 0) {
	fprintf(stderr, ": unhandled exception\n");
    }
    else {
	VALUE epath;

	epath = rb_class_path(eclass);
	if (elen == 0) {
	    fprintf(stderr, ": ");
	    fwrite(RSTRING(epath)->ptr, 1, RSTRING(epath)->len, stderr);
	    putc('\n', stderr);
	}
	else {
	    char *tail  = 0;
	    int len = elen;

	    if (RSTRING(epath)->ptr[0] == '#') epath = 0;
	    if (tail = strchr(einfo, '\n')) {
		len = tail - einfo;
		tail++;		/* skip newline */
	    }
	    fprintf(stderr, ": ");
	    fwrite(einfo, 1, len, stderr);
	    if (epath) {
		fprintf(stderr, " (");
		fwrite(RSTRING(epath)->ptr, 1, RSTRING(epath)->len, stderr);
		fprintf(stderr, ")\n");
	    }
	    if (tail) {
		fwrite(tail, 1, elen-len-1, stderr);
		putc('\n', stderr);
	    }
	}
    }

    if (!NIL_P(errat)) {
	int i;
	struct RArray *ep = RARRAY(errat);

#define TRACE_MAX (TRACE_HEAD+TRACE_TAIL+5)
#define TRACE_HEAD 8
#define TRACE_TAIL 5

	ep = RARRAY(errat);
	for (i=1; i<ep->len; i++) {
	    if (TYPE(ep->ptr[i]) == T_STRING) {
		fprintf(stderr, "\tfrom %s\n", RSTRING(ep->ptr[i])->ptr);
	    }
	    if (i == TRACE_HEAD && ep->len > TRACE_MAX) {
		fprintf(stderr, "\t ... %ld levels...\n",
			ep->len - TRACE_HEAD - TRACE_TAIL);
		i = ep->len - TRACE_TAIL;
	    }
	}
    }
}

#if !defined(NT) && !defined(__MACOS__)
extern char **environ;
#endif
char **rb_origenviron;

void rb_call_inits _((void));
void Init_stack _((void*));
void Init_heap _((void));
void Init_ext _((void));

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

    ruby_frame = top_frame = &frame;
    ruby_iter = &iter;

#ifdef __MACOS__
    rb_origenviron = 0;
#else
    rb_origenviron = environ;
#endif

    Init_stack(0);
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
	ruby_frame->cbase = (VALUE)rb_node_newnode(NODE_CREF,rb_cObject,0,0);
	rb_define_global_const("TOPLEVEL_BINDING", rb_f_binding(ruby_top_self));
#ifdef __MACOS__
	_macruby_init();
#endif
	ruby_prog_init();
    }
    POP_TAG();
    if (state) error_print();
    POP_SCOPE();
    ruby_scope = top_scope;
}

static int ext_init = 0;

void
ruby_options(argc, argv)
    int argc;
    char **argv;
{
    int state;

    PUSH_TAG(PROT_NONE)
    if ((state = EXEC_TAG()) == 0) {
	ruby_process_options(argc, argv);
	ext_init = 1;	/* Init_ext() called in ruby_process_options */
    }
    POP_TAG();
    if (state) {
	trace_func = 0;
	error_print();
	exit(1);
    }
}

static VALUE
eval_node(self)
    VALUE self;
{
    NODE *beg_tree, *tree;

    beg_tree = ruby_eval_tree_begin;
    tree = ruby_eval_tree;
    if (beg_tree) {
	ruby_eval_tree_begin = 0;
	rb_eval(self, beg_tree);
    }

    if (!tree) return Qnil;
    ruby_eval_tree = 0;

    return rb_eval(self, tree);
}

int ruby_in_eval;

static void rb_thread_cleanup _((void));
static void rb_thread_wait_other_threads _((void));

static int exit_status;

static void
call_required_libraries()
{
    NODE *save;

    ruby_sourcefile = 0;
    if (!ext_init) Init_ext();
    save = ruby_eval_tree;
    ruby_require_libraries();
    ruby_eval_tree = save;
}

void
ruby_run()
{
    int state;
    static int ex;
    volatile NODE *tmp;

    if (ruby_nerrs > 0) exit(ruby_nerrs);

    Init_stack(&tmp);
    PUSH_TAG(PROT_NONE);
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	call_required_libraries();
	eval_node(ruby_top_self);
    }
    POP_ITER();
    POP_TAG();

    if (state && !ex) ex = state;
    PUSH_TAG(PROT_NONE);
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	rb_trap_exit();
	rb_thread_cleanup();
	rb_thread_wait_other_threads();
    }
    else {
	ex = state;
    }
    POP_ITER();
    POP_TAG();

    switch (ex & 0xf) {
      case 0:
	ex = 0;
	break;

      case TAG_RETURN:
	error_pos();
	fprintf(stderr, ": unexpected return\n");
	ex = 1;
	break;
      case TAG_NEXT:
	error_pos();
	fprintf(stderr, ": unexpected next\n");
	ex = 1;
	break;
      case TAG_BREAK:
	error_pos();
	fprintf(stderr, ": unexpected break\n");
	ex = 1;
	break;
      case TAG_REDO:
	error_pos();
	fprintf(stderr, ": unexpected redo\n");
	ex = 1;
	break;
      case TAG_RETRY:
	error_pos();
	fprintf(stderr, ": retry outside of rescue clause\n");
	ex = 1;
	break;
      case TAG_RAISE:
      case TAG_FATAL:
	if (rb_obj_is_kind_of(ruby_errinfo, rb_eSystemExit)) {
	    ex = exit_status;
	}
	else {
	    error_print();
	    ex = 1;
	}
	break;
      default:
	rb_bug("Unknown longjmp status %d", ex);
	break;
    }
    rb_exec_end_proc();
    rb_gc_call_finalizer_at_exit();
    exit(ex);
}

static void
compile_error(at)
    const char *at;
{
    VALUE str;
    char *mesg;
    int len;

    mesg = str2cstr(ruby_errinfo, &len);
    ruby_nerrs = 0;
    str = rb_str_new2("compile error");
    if (at) {
	rb_str_cat(str, " in ", 4);
	rb_str_cat(str, at, strlen(at));
    }
    rb_str_cat(str, "\n", 1);
    rb_str_cat(str, mesg, len);
    rb_exc_raise(rb_exc_new3(rb_eSyntaxError, str));
}

VALUE
rb_eval_string(str)
    const char *str;
{
    VALUE v;
    char *oldsrc = ruby_sourcefile;

    ruby_sourcefile = "(eval)";
    v = eval(ruby_top_self, rb_str_new2(str), Qnil, 0, 0);
    ruby_sourcefile = oldsrc;

    return v;
}

VALUE
rb_eval_string_protect(str, state)
    const char *str;
    int *state;
{
    VALUE result;		/* OK */
    int status;

    PUSH_TAG(PROT_NONE);
    if ((status = EXEC_TAG()) == 0) {
	result = rb_eval_string(str);
    }
    POP_TAG();
    if (state) {
	*state = status;
    }
    if (status != 0) {
	return Qnil;
    }

    return result;
}

VALUE
rb_eval_string_wrap(str, state)
    const char *str;
    int *state;
{
    int status;
    VALUE self = ruby_top_self;
    VALUE val;

    PUSH_CLASS();
    ruby_class = ruby_wrapper = rb_module_new();
    ruby_top_self = rb_obj_clone(ruby_top_self);
    rb_extend_object(self, ruby_class);

    val = rb_eval_string_protect(str, &status);
    ruby_top_self = self;

    POP_CLASS();
    if (state) {
	*state = status;
    }
    else if (status) {
	JUMP_TAG(status);
    }
    return val;
}

VALUE
rb_eval_cmd(cmd, arg)
    VALUE cmd, arg;
{
    int state;
    VALUE val;			/* OK */
    struct SCOPE *saved_scope;
    volatile int safe = safe_level;

    if (TYPE(cmd) != T_STRING) {
	return rb_funcall2(cmd, rb_intern("call"),
			   RARRAY(arg)->len, RARRAY(arg)->ptr);
    }

    PUSH_CLASS();
    PUSH_TAG(PROT_NONE);
    saved_scope = ruby_scope;
    ruby_scope = top_scope;

    ruby_class = rb_cObject;
    if (OBJ_TAINTED(cmd)) {
	safe_level = 4;
    }

    if ((state = EXEC_TAG()) == 0) {
	val = eval(ruby_top_self, cmd, Qnil, 0, 0);
    }

    if (FL_TEST(ruby_scope, SCOPE_DONT_RECYCLE))
	FL_SET(saved_scope, SCOPE_DONT_RECYCLE);
    ruby_scope = saved_scope;
    safe_level = safe;
    POP_TAG();
    POP_CLASS();

    switch (state) {
      case 0:
	break;
      case TAG_RETURN:
	rb_raise(rb_eLocalJumpError, "unexpected return");
	break;
      case TAG_NEXT:
	rb_raise(rb_eLocalJumpError, "unexpected next");
	break;
      case TAG_BREAK:
	rb_raise(rb_eLocalJumpError, "unexpected break");
	break;
      case TAG_REDO:
	rb_raise(rb_eLocalJumpError, "unexpected redo");
	break;
      case TAG_RETRY:
	rb_raise(rb_eLocalJumpError, "retry outside of rescue clause");
	break;
      default:
	JUMP_TAG(state);
	break;
    }
    return val;
}

static VALUE
rb_trap_eval(cmd, sig)
    VALUE cmd;
    int sig;
{
    int state;
    VALUE val;			/* OK */

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	val = rb_eval_cmd(cmd, rb_ary_new3(1, INT2FIX(sig)));
    }
    POP_TAG();
    if (state) {
	rb_trap_immediate = 0;
	JUMP_TAG(state);
    }
    return val;
}

static VALUE
superclass(self, node)
    VALUE self;
    NODE *node;
{
    VALUE val;			/* OK */
    int state;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	val = rb_eval(self, node);
    }
    POP_TAG();
    if (state) {
      superclass_error:
	switch (nd_type(node)) {
	  case NODE_COLON2:
	    rb_raise(rb_eTypeError, "undefined superclass `%s'",
		     rb_id2name(node->nd_mid));
	  case NODE_CVAR:
	    rb_raise(rb_eTypeError, "undefined superclass `%s'",
		     rb_id2name(node->nd_vid));
	  default:
	    rb_raise(rb_eTypeError, "superclass undefined");
	}
	JUMP_TAG(state);
    }
    if (TYPE(val) != T_CLASS) goto superclass_error;
    if (FL_TEST(val, FL_SINGLETON)) {
	rb_raise(rb_eTypeError, "can't make subclass of virtual class");
    }

    return val;
}

static VALUE
ev_const_defined(cref, id)
    NODE *cref;
    ID id;
{
    NODE *cbase = cref;

    while (cbase && cbase->nd_clss != rb_cObject) {
	struct RClass *klass = RCLASS(cbase->nd_clss);

	if (klass->iv_tbl &&
	    st_lookup(klass->iv_tbl, id, 0)) {
	    return Qtrue;
	}
	cbase = cbase->nd_next;
    }
    return rb_const_defined(cref->nd_clss, id);
}

static VALUE
ev_const_get(cref, id)
    NODE *cref;
    ID id;
{
    NODE *cbase = cref;
    VALUE result;

    while (cbase && cbase->nd_clss != rb_cObject) {
	struct RClass *klass = RCLASS(cbase->nd_clss);

	if (klass->iv_tbl &&
	    st_lookup(klass->iv_tbl, id, &result)) {
	    return result;
	}
	cbase = cbase->nd_next;
    }
    return rb_const_get(cref->nd_clss, id);
}

static VALUE
rb_mod_nesting()
{
    NODE *cbase = (NODE*)ruby_frame->cbase;
    VALUE ary = rb_ary_new();

    while (cbase && cbase->nd_clss != rb_cObject) {
	rb_ary_push(ary, cbase->nd_clss);
	cbase = cbase->nd_next;
    }
    return ary;
}

static VALUE
rb_mod_s_constants()
{
    NODE *cbase = (NODE*)ruby_frame->cbase;
    VALUE ary = rb_ary_new();

    while (cbase && cbase->nd_clss != rb_cObject) {
	rb_mod_const_at(cbase->nd_clss, ary);
	cbase = cbase->nd_next;
    }

    rb_mod_const_of(((NODE*)ruby_frame->cbase)->nd_clss, ary);
    return ary;
}

static VALUE
rb_mod_remove_method(mod, name)
    VALUE mod, name;
{
    remove_method(mod, rb_to_id(name));
    return mod;
}

static VALUE
rb_mod_undef_method(mod, name)
    VALUE mod, name;
{
    ID id = rb_to_id(name);

    rb_add_method(mod, id, 0, NOEX_PUBLIC);
    rb_clear_cache_by_id(id);
    return mod;
}

static VALUE
rb_mod_alias_method(mod, newname, oldname)
    VALUE mod, newname, oldname;
{
    ID id = rb_to_id(newname);

    rb_alias(mod, id, rb_to_id(oldname));
    rb_clear_cache_by_id(id);
    return mod;
}

#ifdef C_ALLOCA
# define TMP_PROTECT NODE * volatile tmp__protect_tmp=0
# define TMP_ALLOC(n)							\
    (tmp__protect_tmp = rb_node_newnode(NODE_ALLOCA,			\
			     ALLOC_N(VALUE,n),tmp__protect_tmp,n),	\
     (void*)tmp__protect_tmp->nd_head)
#else
# define TMP_PROTECT typedef int foobazzz
# define TMP_ALLOC(n) ALLOCA_N(VALUE,n)
#endif

#define SETUP_ARGS(anode) {\
    NODE *n = anode;\
    if (!n) {\
	argc = 0;\
	argv = 0;\
    }\
    else if (nd_type(n) == NODE_ARRAY) {\
	argc=n->nd_alen;\
        if (argc > 0) {\
	    char *file = ruby_sourcefile;\
	    int line = ruby_sourceline;\
            int i;\
	    n = anode;\
	    argv = TMP_ALLOC(argc);\
	    for (i=0;i<argc;i++) {\
		argv[i] = rb_eval(self,n->nd_head);\
		n=n->nd_next;\
	    }\
	    ruby_sourcefile = file;\
	    ruby_sourceline = line;\
        }\
        else {\
	    argc = 0;\
	    argv = 0;\
        }\
    }\
    else {\
        VALUE args = rb_eval(self,n);\
	char *file = ruby_sourcefile;\
	int line = ruby_sourceline;\
	if (TYPE(args) != T_ARRAY)\
	    args = rb_Array(args);\
        argc = RARRAY(args)->len;\
	argv = ALLOCA_N(VALUE, argc);\
	MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);\
	ruby_sourcefile = file;\
	ruby_sourceline = line;\
    }\
}

#define BEGIN_CALLARGS {\
    struct BLOCK *tmp_block = ruby_block;\
    if (ruby_iter->iter == ITER_PRE) {\
	ruby_block = ruby_block->prev;\
    }\
    PUSH_ITER(ITER_NOT);

#define END_CALLARGS \
    ruby_block = tmp_block;\
    POP_ITER();\
}

#define MATCH_DATA ruby_scope->local_vars[node->nd_cnt]

static char* is_defined _((VALUE, NODE*, char*));

static char*
arg_defined(self, node, buf, type)
    VALUE self;
    NODE *node;
    char *buf;
    char *type;
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
    
static char*
is_defined(self, node, buf)
    VALUE self;
    NODE *node;			/* OK */
    char *buf;
{
    VALUE val;			/* OK */
    int state;

    switch (nd_type(node)) {
      case NODE_SUPER:
      case NODE_ZSUPER:
	if (ruby_frame->last_func == 0) return 0;
	else if (ruby_frame->last_class == 0) return 0;
	else if (rb_method_boundp(RCLASS(ruby_frame->last_class)->super,
				  ruby_frame->last_func, 0)) {
	    if (nd_type(node) == NODE_SUPER) {
		return arg_defined(self, node->nd_args, buf, "super");
	    }
	    return "super";
	}
	break;

      case NODE_VCALL:
      case NODE_FCALL:
	val = CLASS_OF(self);
	goto check_bound;

      case NODE_CALL:
	if (!is_defined(self, node->nd_recv, buf)) return 0;
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    val = rb_eval(self, node->nd_recv);
	    val = CLASS_OF(val);
	}
	POP_TAG();
	if (state) {
	    ruby_errinfo = Qnil;
	    return 0;
	}
      check_bound:
	if (rb_method_boundp(val, node->nd_mid, nd_type(node)== NODE_CALL)) {
	    return arg_defined(self, node->nd_args, buf, "method");
	}
	break;

      case NODE_MATCH2:
      case NODE_MATCH3:
	return "method";

      case NODE_YIELD:
	if (rb_iterator_p()) {
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
      case NODE_MASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_DASGN_PUSH:
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_CASGN:
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

      case NODE_CVAR:
	if (ev_const_defined((NODE*)ruby_frame->cbase, node->nd_vid)) {
	    return "constant";
	}
	break;

      case NODE_COLON2:
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    val = rb_eval(self, node->nd_head);
	}
	POP_TAG();
	if (state) {
	    ruby_errinfo = Qnil;
	    return 0;
	}
	else {
	    switch (TYPE(val)) {
	      case T_CLASS:
	      case T_MODULE:
		if (rb_const_defined_at(val, node->nd_mid))
		    return "constant";
	      default:
		if (rb_method_boundp(val, node->nd_mid, 1)) {
		    return "method";
		}
	    }
	}
	break;

      case NODE_NTH_REF:
	if (rb_reg_nth_defined(node->nd_nth, MATCH_DATA)) {
	    sprintf(buf, "$%d", node->nd_nth);
	    return buf;
	}
	break;

      case NODE_BACK_REF:
	if (rb_reg_nth_defined(0, MATCH_DATA)) {
	    sprintf(buf, "$%c", node->nd_nth);
	    return buf;
	}
	break;

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

static VALUE
rb_obj_is_block(block)
    VALUE block;
{
    if (TYPE(block) == T_DATA && RDATA(block)->dfree == blk_free) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
rb_obj_is_proc(proc)
    VALUE proc;
{
    if (rb_obj_is_block(proc) && rb_obj_is_kind_of(proc, rb_cProc)) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
set_trace_func(obj, trace)
    VALUE obj, trace;
{
    if (NIL_P(trace)) {
	trace_func = 0;
	return Qnil;
    }
    if (!rb_obj_is_proc(trace)) {
	rb_raise(rb_eTypeError, "trace_func needs to be Proc");
    }
    return trace_func = trace;
}

static void
call_trace_func(event, file, line, self, id, klass)
    char *event;
    char *file;
    int line;
    VALUE self;
    ID id;
    VALUE klass;		/* OK */
{
    int state;
    volatile VALUE trace;
    struct FRAME *prev;
    char *file_save = ruby_sourcefile;
    int line_save = ruby_sourceline;
    VALUE srcfile;

    if (!trace_func) return;

    trace = trace_func;
    trace_func = 0;
    rb_thread_critical++;

    prev = ruby_frame;
    PUSH_FRAME();
    *ruby_frame = *prev;
    ruby_frame->prev = prev;

    if (file) {
	ruby_frame->line = ruby_sourceline = line;
	ruby_frame->file = ruby_sourcefile = file;
    }
    if (klass) {
	if (TYPE(klass) == T_ICLASS) {
	    klass = RBASIC(klass)->klass;
	}
	else if (FL_TEST(klass, FL_SINGLETON)) {
	    klass = self;
	}
    }
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	srcfile = rb_str_new2(ruby_sourcefile?ruby_sourcefile:"(ruby)");
	proc_call(trace, rb_ary_new3(6, rb_str_new2(event),
				     srcfile,
				     INT2FIX(ruby_sourceline),
				     INT2FIX(id),
				     self?rb_f_binding(self):Qnil,
				     klass));
    }
    POP_TMPTAG();		/* do not propagate retval */
    POP_FRAME();

    rb_thread_critical--;
    if (!trace_func) trace_func = trace;
    ruby_sourceline = line_save;
    ruby_sourcefile = file_save;
    if (state) JUMP_TAG(state);
}

static void return_check _((void));
#define return_value(v) prot_tag->retval = (v)

static VALUE
rb_eval(self, node)
    VALUE self;
    NODE * volatile node;
{
    int state;
    volatile VALUE result = Qnil;

#define RETURN(v) { result = (v); goto finish; }

  again:
    if (!node) RETURN(Qnil);

    switch (nd_type(node)) {
      case NODE_BLOCK:
	while (node->nd_next) {
	    rb_eval(self, node->nd_head);
	    node = node->nd_next;
	}
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
	result = rb_reg_match2(node->nd_head->nd_lit);
	break;

	/* nodes for speed-up(literal match) */
      case NODE_MATCH2:
	result = rb_reg_match(rb_eval(self,node->nd_recv),
			   rb_eval(self,node->nd_value));
	break;

	/* nodes for speed-up(literal match) */
      case NODE_MATCH3:
        {
	    VALUE r = rb_eval(self,node->nd_recv);
	    VALUE l = rb_eval(self,node->nd_value);
	    if (TYPE(r) == T_STRING) {
		result = rb_reg_match(l, r);
	    }
	    else {
		result = rb_funcall(r, match, 1, l);
	    }
	}
	break;

	/* node for speed-up(top-level loop for -n/-p) */
      case NODE_OPT_N:
	PUSH_TAG(PROT_NONE);
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
	ruby_sourceline = nd_line(node);
	if (RTEST(rb_eval(self, node->nd_cond))) {
	    node = node->nd_body;
	}
	else {
	    node = node->nd_else;
	}
	goto again;

      case NODE_CASE:
	{
	    VALUE val;

	    val = rb_eval(self, node->nd_head);
	    node = node->nd_body;
	    while (node) {
		NODE *tag;

		if (nd_type(node) != NODE_WHEN) {
		    goto again;
		}
		tag = node->nd_head;
		while (tag) {
		    if (trace_func) {
			call_trace_func("line", tag->nd_file, nd_line(tag),
					self, ruby_frame->last_func, 0);	
		    }
		    ruby_sourcefile = tag->nd_file;
		    ruby_sourceline = nd_line(tag);
		    if (nd_type(tag->nd_head) == NODE_WHEN) {
			VALUE v = rb_eval(self, tag->nd_head->nd_head);
			int i;

			if (TYPE(v) != T_ARRAY) v = rb_Array(v);
			for (i=0; i<RARRAY(v)->len; i++) {
			    if (RTEST(rb_funcall2(RARRAY(v)->ptr[i], eqq, 1, &val))){
				node = node->nd_body;
				goto again;
			    }
			}
			tag = tag->nd_next;
			continue;
		    }
		    if (RTEST(rb_funcall2(rb_eval(self, tag->nd_head), eqq, 1, &val))) {
			node = node->nd_body;
			goto again;
		    }
		    tag = tag->nd_next;
		}
		node = node->nd_next;
	    }
	}
	RETURN(Qnil);

      case NODE_WHILE:
	PUSH_TAG(PROT_NONE);
	switch (state = EXEC_TAG()) {
	  case 0:
	    ruby_sourceline = nd_line(node);
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
	    state = 0;
	  default:
	    break;
	}
      while_out:
	POP_TAG();
	if (state) JUMP_TAG(state);
	RETURN(Qnil);

      case NODE_UNTIL:
	PUSH_TAG(PROT_NONE);
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
	    state = 0;
	  default:
	    break;
	}
      until_out:
	POP_TAG();
	if (state) JUMP_TAG(state);
	RETURN(Qnil);

      case NODE_BLOCK_PASS:
	result = block_pass(self, node);
	break;

      case NODE_ITER:
      case NODE_FOR:
	{
	  iter_retry:
	    PUSH_BLOCK(node->nd_var, node->nd_body);
	    PUSH_TAG(PROT_FUNC);

	    state = EXEC_TAG();
	    if (state == 0) {
		if (nd_type(node) == NODE_ITER) {
		    PUSH_ITER(ITER_PRE);
		    result = rb_eval(self, node->nd_iter);
		    POP_ITER();
		}
		else {
		    VALUE recv;
		    char *file = ruby_sourcefile;
		    int line = ruby_sourceline;

		    _block.flags &= ~BLOCK_D_SCOPE;
		    recv = rb_eval(self, node->nd_iter);
		    PUSH_ITER(ITER_PRE);
		    ruby_sourcefile = file;
		    ruby_sourceline = line;
		    result = rb_call(CLASS_OF(recv),recv,each,0,0,0);
		    POP_ITER();
		}
	    }
	    else if (_block.tag->dst == state) {
		state &= TAG_MASK;
		if (state == TAG_RETURN) {
		    result = prot_tag->retval;
		}
	    }
	    POP_TAG();
	    POP_BLOCK();
	    switch (state) {
	      case 0:
		break;

	      case TAG_RETRY:
		goto iter_retry;

	      case TAG_BREAK:
		result = Qnil;
		break;
	      case TAG_RETURN:
		return_value(result);
		/* fall through */
	      default:
		JUMP_TAG(state);
	    }
	}
	break;

      case NODE_BREAK:
	JUMP_TAG(TAG_BREAK);
	break;

      case NODE_NEXT:
	JUMP_TAG(TAG_NEXT);
	break;

      case NODE_REDO:
	JUMP_TAG(TAG_REDO);
	break;

      case NODE_RETRY:
	JUMP_TAG(TAG_RETRY);
	break;

      case NODE_RESTARGS:
	result = rb_eval(self, node->nd_head);
	if (TYPE(result) != T_ARRAY) {
	    result = rb_Array(result);
	}
	break;

      case NODE_YIELD:
	if (node->nd_stts) {
	    result = rb_eval(self, node->nd_stts);
	    if (nd_type(node->nd_stts) == NODE_RESTARGS &&
		RARRAY(result)->len == 1)
	    {
		result = RARRAY(result)->ptr[0];
	    }
	}
	else {
	    result = Qnil;
	}
	result = rb_yield_0(result, 0, 0, Qfalse);
	break;

      case NODE_RESCUE:
      retry_entry:
        {
	    volatile VALUE e_info = ruby_errinfo;

	    PUSH_TAG(PROT_NONE);
	    if ((state = EXEC_TAG()) == 0) {
		result = rb_eval(self, node->nd_head);
	    }
	    POP_TAG();
	    if (state == TAG_RAISE) {
		NODE * volatile resq = node->nd_resq;

		while (resq) {
		    if (handle_rescue(self, resq)) {
			state = 0;
			PUSH_TAG(PROT_NONE);
			if ((state = EXEC_TAG()) == 0) {
			    result = rb_eval(self, resq->nd_body);
			}
			POP_TAG();
			if (state == TAG_RETRY) {
			    state = 0;
			    goto retry_entry;
			}
			if (state != TAG_RAISE) {
			    ruby_errinfo = e_info;
			}
			break;
		    }
		    resq = resq->nd_head; /* next rescue */
		}
	    }
	    else if (node->nd_else) { /* else clause given */
		if (!state) {	/* no exception raised */
		    result = rb_eval(self, node->nd_else);
		}
	    }
	    if (state) JUMP_TAG(state);
	}
        break;

      case NODE_ENSURE:
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    result = rb_eval(self, node->nd_head);
	}
	POP_TAG();
	if (node->nd_ensr) {
	    VALUE retval = prot_tag->retval; /* save retval */

	    rb_eval(self, node->nd_ensr);
	    return_value(retval);
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
	result = rb_range_new(rb_eval(self, node->nd_beg),
			      rb_eval(self, node->nd_end),
			      nd_type(node) == NODE_DOT3);
	if (node->nd_state) break;
	if (nd_type(node->nd_beg) == NODE_LIT && FIXNUM_P(node->nd_beg->nd_lit) &&
	    nd_type(node->nd_end) == NODE_LIT && FIXNUM_P(node->nd_end->nd_lit))
	{
	    nd_set_type(node, NODE_LIT);
	    node->nd_lit = result;
	}
	else {
	    node->nd_state = 1;
	}
	break;

      case NODE_FLIP2:		/* like AWK */
	if (ruby_scope->local_vars == 0) {
	    rb_bug("unexpected local variable");
	}
	if (!RTEST(ruby_scope->local_vars[node->nd_cnt])) {
	    if (RTEST(rb_eval(self, node->nd_beg))) {
		ruby_scope->local_vars[node->nd_cnt] = 
		    RTEST(rb_eval(self, node->nd_end))?Qfalse:Qtrue;
		result = Qtrue;
	    }
	    else {
		result = Qfalse;
	    }
	}
	else {
	    if (RTEST(rb_eval(self, node->nd_end))) {
		ruby_scope->local_vars[node->nd_cnt] = Qfalse;
	    }
	    result = Qtrue;
	}
	break;

      case NODE_FLIP3:		/* like SED */
	if (ruby_scope->local_vars == 0) {
	    rb_bug("unexpected local variable");
	}
	if (!RTEST(ruby_scope->local_vars[node->nd_cnt])) {
	    result = RTEST(rb_eval(self, node->nd_beg));
	    ruby_scope->local_vars[node->nd_cnt] = result;
	}
	else {
	    if (RTEST(rb_eval(self, node->nd_end))) {
		ruby_scope->local_vars[node->nd_cnt] = Qfalse;
	    }
	    result = Qtrue;
	}
	break;

      case NODE_RETURN:
	if (node->nd_stts) {
 	    return_value(rb_eval(self, node->nd_stts));
 	}
	else {
	    return_value(Qnil);
	}
	return_check();
	JUMP_TAG(TAG_RETURN);
	break;

      case NODE_ARGSCAT:
	result = rb_ary_concat(rb_eval(self, node->nd_head),
			       rb_eval(self, node->nd_body));
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

	    result = rb_call(CLASS_OF(recv),recv,node->nd_mid,argc,argv,0);
	}
	break;

      case NODE_FCALL:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    TMP_PROTECT;

	    BEGIN_CALLARGS;
	    SETUP_ARGS(node->nd_args);
	    END_CALLARGS;

	    result = rb_call(CLASS_OF(self),self,node->nd_mid,argc,argv,1);
	}
	break;

      case NODE_VCALL:
	result = rb_call(CLASS_OF(self),self,node->nd_mid,0,0,2);
	break;

      case NODE_SUPER:
      case NODE_ZSUPER:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    TMP_PROTECT;

	    if (ruby_frame->last_class == 0) {	
		rb_raise(rb_eNameError, "superclass method `%s' disabled",
			 rb_id2name(ruby_frame->last_func));
	    }
	    if (nd_type(node) == NODE_ZSUPER) {
		argc = ruby_frame->argc;
		argv = ruby_frame->argv;
	    }
	    else {
		BEGIN_CALLARGS;
		SETUP_ARGS(node->nd_args);
		END_CALLARGS;
	    }

	    PUSH_ITER(ruby_iter->iter?ITER_PRE:ITER_NOT);
	    result = rb_call(RCLASS(ruby_frame->last_class)->super,
			     ruby_frame->self, ruby_frame->last_func,
			     argc, argv, 3);
	    POP_ITER();
	}
	break;

      case NODE_SCOPE:
	{
	    struct FRAME frame;

	    frame = *ruby_frame;
	    frame.tmp = ruby_frame;
	    ruby_frame = &frame;

	    PUSH_SCOPE();
	    PUSH_TAG(PROT_NONE);
	    if (node->nd_rval) ruby_frame->cbase = node->nd_rval;
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
	    if (state) JUMP_TAG(state);
	}
	break;

      case NODE_OP_ASGN1:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    VALUE recv, val;
	    NODE *rval;
	    TMP_PROTECT;

	    recv = rb_eval(self, node->nd_recv);
	    rval = node->nd_args->nd_head;
	    SETUP_ARGS(node->nd_args->nd_next);
	    val = rb_funcall2(recv, aref, argc-1, argv);
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
		val = rb_funcall(val, node->nd_mid, 1, rb_eval(self, rval));
	    }
	    argv[argc-1] = val;
	    val = rb_funcall2(recv, aset, argc, argv);
	    result = val;
	}
	break;

      case NODE_OP_ASGN2:
	{
	    ID id = node->nd_next->nd_vid;
	    VALUE recv, val;

	    recv = rb_eval(self, node->nd_recv);
	    val = rb_funcall(recv, id, 0);
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
		val = rb_funcall(val, node->nd_next->nd_mid, 1,
				 rb_eval(self, node->nd_value));
	    }

	    rb_funcall2(recv, node->nd_next->nd_aid, 1, &val);
	    result = val;
	}
	break;

      case NODE_OP_ASGN_AND:
	result = rb_eval(self, node->nd_head);
	if (RTEST(result)) {
	    result = rb_eval(self, node->nd_value);
	}
	break;

      case NODE_OP_ASGN_OR:
	result = rb_eval(self, node->nd_head);
	if (!RTEST(result)) {
	    result = rb_eval(self, node->nd_value);
	}
	break;

      case NODE_MASGN:
	result = massign(self, node, rb_eval(self, node->nd_value),0);
	break;

      case NODE_LASGN:
	if (ruby_scope->local_vars == 0)
	    rb_bug("unexpected local variable assignment");
	result = rb_eval(self, node->nd_value);
	ruby_scope->local_vars[node->nd_cnt] = result;
	break;

      case NODE_DASGN:
	result = rb_eval(self, node->nd_value);
	rb_dvar_asgn(node->nd_vid, result);
	break;

      case NODE_DASGN_PUSH:
	result = rb_eval(self, node->nd_value);
	dvar_asgn_push(node->nd_vid, result);
	break;

      case NODE_GASGN:
	result = rb_eval(self, node->nd_value);
	rb_gvar_set(node->nd_entry, result);
	break;

      case NODE_IASGN:
	result = rb_eval(self, node->nd_value);
	rb_ivar_set(self, node->nd_vid, result);
	break;

      case NODE_CASGN:
	if (NIL_P(ruby_class)) {
	    rb_raise(rb_eTypeError, "no class/module to define constant");
	}
	result = rb_eval(self, node->nd_value);
	/* check for static scope constants */
	if (RTEST(ruby_verbose) &&
	    ev_const_defined((NODE*)ruby_frame->cbase, node->nd_vid)) {
	    rb_warn("already initialized constant %s",
		       rb_id2name(node->nd_vid));
	}
	rb_const_set(ruby_class, node->nd_vid, result);
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

      case NODE_CVAR:
	result = ev_const_get((NODE*)ruby_frame->cbase, node->nd_vid);
	break;

      case NODE_BLOCK_ARG:
	if (ruby_scope->local_vars == 0)
	    rb_bug("unexpected block argument");
	if (rb_iterator_p()) {
	    result = rb_f_lambda();
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
	    switch (TYPE(klass)) {
	      case T_CLASS:
	      case T_MODULE:
		break;
	      default:
		return rb_funcall(klass, node->nd_mid, 0, 0);
	    }
	    result = rb_const_get_at(klass, node->nd_mid);
	}
	break;

      case NODE_COLON3:
	result = rb_const_get_at(rb_cObject, node->nd_mid);
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
	    int i;

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

      case NODE_DSTR:
      case NODE_DXSTR:
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
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
		      case NODE_EVSTR:
			ruby_sourceline = nd_line(node);
			ruby_in_eval++;
			list->nd_head = compile(list->nd_head->nd_lit,
						ruby_sourcefile,
						ruby_sourceline);
			ruby_eval_tree = 0;
			ruby_in_eval--;
			if (ruby_nerrs > 0) {
			    compile_error("string expansion");
			}
			/* fall through */
		      default:
			str2 = rb_eval(self, list->nd_head);
			str2 = rb_obj_as_string(str2);
			break;
		    }
		    rb_str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
		    if (OBJ_TAINTED(str2)) OBJ_TAINT(str);
		}
		list = list->nd_next;
	    }
	    switch (nd_type(node)) {
	      case NODE_DREGX:
		result = rb_reg_new(RSTRING(str)->ptr, RSTRING(str)->len,
				 node->nd_cflag);
		break;
	      case NODE_DREGX_ONCE:	/* regexp expand once */
		result = rb_reg_new(RSTRING(str)->ptr, RSTRING(str)->len,
				 node->nd_cflag);
		nd_set_type(node, NODE_LIT);
		node->nd_lit = result;
		break;
	      case NODE_DXSTR:
		result = rb_funcall(self, '`', 1, str);
		break;
	      default:
		result = str;
		break;
	    }
	}
	break;

      case NODE_XSTR:
	result = rb_funcall(self, '`', 1, node->nd_lit);
	break;

      case NODE_LIT:
	result = node->nd_lit;
	break;

      case NODE_ATTRSET:
	if (ruby_frame->argc != 1)
	    rb_raise(rb_eArgError, "wrong # of arguments(%d for 1)",
		     ruby_frame->argc);
	result = rb_ivar_set(self, node->nd_vid, ruby_frame->argv[0]);
	break;

      case NODE_DEFN:
	if (node->nd_defn) {
	    NODE *body;
	    VALUE origin;
	    int noex;

	    if (NIL_P(ruby_class)) {
		rb_raise(rb_eTypeError, "no class to add method");
	    }
	    if (ruby_class == rb_cObject && node->nd_mid == init) {
		rb_warn("re-defining Object#initialize may cause infinite loop");
	    }
	    body = search_method(ruby_class, node->nd_mid, &origin);
	    if (body) {
		if (origin == ruby_class) {
		    if (safe_level >= 4) {
			rb_raise(rb_eSecurityError, "re-defining method prohibited");
		    }
		    if (RTEST(ruby_verbose)) {
			rb_warning("discarding old %s", rb_id2name(node->nd_mid));
		    }
		}
		rb_clear_cache_by_id(node->nd_mid);
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
	    if (body && origin == ruby_class && body->nd_noex & NOEX_UNDEF) {
		noex |= NOEX_UNDEF;
	    }
	    rb_add_method(ruby_class, node->nd_mid, node->nd_defn, noex);
	    if (scope_vmode == SCOPE_MODFUNC) {
		rb_add_method(rb_singleton_class(ruby_class),
			      node->nd_mid, node->nd_defn, NOEX_PUBLIC);
		rb_funcall(ruby_class, rb_intern("singleton_method_added"),
			   1, INT2FIX(node->nd_mid));
	    }
	    if (FL_TEST(ruby_class, FL_SINGLETON)) {
		rb_funcall(rb_iv_get(ruby_class, "__attached__"),
			   rb_intern("singleton_method_added"),
			   1, INT2FIX(node->nd_mid));
	    }
	    else {
		rb_funcall(ruby_class, rb_intern("method_added"),
			   1, INT2FIX(node->nd_mid));
	    }
	    result = Qnil;
	}
	break;

      case NODE_DEFS:
	if (node->nd_defn) {
	    VALUE recv = rb_eval(self, node->nd_recv);
	    VALUE klass;
	    NODE *body = 0;

	    if (rb_special_const_p(recv)) {
		rb_raise(rb_eTypeError,
			 "can't define method \"%s\" for %s",
			 rb_id2name(node->nd_mid),
			 rb_class2name(CLASS_OF(recv)));
	    }

	    if (rb_safe_level() >= 4 && !FL_TEST(recv, FL_TAINT)) {
		rb_raise(rb_eSecurityError, "can't define singleton method");
	    }
	    klass = rb_singleton_class(recv);
	    if (st_lookup(RCLASS(klass)->m_tbl, node->nd_mid, &body)) {
		if (safe_level >= 4) {
		    rb_raise(rb_eSecurityError, "re-defining method prohibited");
		}
		if (RTEST(ruby_verbose)) {
		    rb_warning("redefine %s", rb_id2name(node->nd_mid));
		}
	    }
	    rb_clear_cache_by_id(node->nd_mid);
	    rb_add_method(klass, node->nd_mid, node->nd_defn, 
			  NOEX_PUBLIC|(body?body->nd_noex&NOEX_UNDEF:0));
	    rb_funcall(recv, rb_intern("singleton_method_added"),
		       1, INT2FIX(node->nd_mid));
	    result = Qnil;
	}
	break;

      case NODE_UNDEF:
	{
	    VALUE origin;
	    NODE *body;

	    if (NIL_P(ruby_class)) {
		rb_raise(rb_eTypeError, "no class to undef method");
	    }
	    if (ruby_class == rb_cObject) {
		rb_secure(4);
	    }
	    body = search_method(ruby_class, node->nd_mid, &origin);
	    if (!body || !body->nd_body) {
		char *s0 = " class";
		VALUE klass = ruby_class;

		if (FL_TEST(ruby_class, FL_SINGLETON)) {
		    VALUE obj = rb_iv_get(ruby_class, "__attached__");
		    switch (TYPE(obj)) {
		      case T_MODULE:
		      case T_CLASS:
			klass = obj;
			s0 = "";
		    }
		}
		else if (TYPE(klass) == T_MODULE) {
		    s0 = " module";
		}
		rb_raise(rb_eNameError, "undefined method `%s' for%s `%s'",
			 rb_id2name(node->nd_mid),s0,rb_class2name(klass));
	    }
	    rb_clear_cache_by_id(node->nd_mid);
	    rb_add_method(ruby_class, node->nd_mid, 0, NOEX_PUBLIC);
	    result = Qnil;
	}
	break;

      case NODE_ALIAS:
	if (NIL_P(ruby_class)) {
	    rb_raise(rb_eTypeError, "no class to make alias");
	}
	rb_alias(ruby_class, node->nd_new, node->nd_old);
	rb_funcall(ruby_class, rb_intern("method_added"),
		   1, INT2FIX(node->nd_mid));
	result = Qnil;
	break;

      case NODE_VALIAS:
	rb_alias_variable(node->nd_new, node->nd_old);
	result = Qnil;
	break;

      case NODE_CLASS:
	{
	    VALUE super, klass, tmp;

	    if (NIL_P(ruby_class)) {
		rb_raise(rb_eTypeError, "no outer class/module");
	    }
	    if (node->nd_super) {
		super = superclass(self, node->nd_super);
	    }
	    else {
		super = 0;
	    }

	    klass = 0;
	    if (rb_const_defined_at(ruby_class, node->nd_cname) &&
		(ruby_class != rb_cObject || !rb_autoload_defined(node->nd_cname))) {
		klass = rb_const_get_at(ruby_class, node->nd_cname);
	    }
	    if (ruby_wrapper && rb_const_defined_at(rb_cObject, node->nd_cname)) {
		klass = rb_const_get_at(rb_cObject, node->nd_cname);
	    }
	    if (klass) {
		if (TYPE(klass) != T_CLASS) {
		    rb_raise(rb_eTypeError, "%s is not a class",
			     rb_id2name(node->nd_cname));
		}
		if (super) {
		    tmp = RCLASS(klass)->super;
		    if (FL_TEST(tmp, FL_SINGLETON)) {
			tmp = RCLASS(tmp)->super;
		    }
		    while (TYPE(tmp) == T_ICLASS) {
			tmp = RCLASS(tmp)->super;
		    }
		    if (tmp != super) {
			rb_raise(rb_eTypeError, "superclass mismatch for %s",
				 rb_id2name(node->nd_cname));
		    }
		}
		if (safe_level >= 4) {
		    rb_raise(rb_eSecurityError, "extending class prohibited");
		}
		rb_clear_cache();
	    }
	    else {
		if (!super) super = rb_cObject;
		klass = rb_define_class_id(node->nd_cname, super);
		rb_const_set(ruby_class, node->nd_cname, klass);
		rb_set_class_path(klass,ruby_class,rb_id2name(node->nd_cname));
	    }
	    if (ruby_wrapper) {
		rb_extend_object(klass, ruby_wrapper);
		rb_include_module(klass, ruby_wrapper);
	    }

	    result = module_setup(klass, node->nd_body);
	}
	break;

      case NODE_MODULE:
	{
	    VALUE module;

	    if (NIL_P(ruby_class)) {
		rb_raise(rb_eTypeError, "no outer class/module");
	    }
	    module = 0;
	    if (rb_const_defined_at(ruby_class, node->nd_cname) &&
		(ruby_class != rb_cObject ||
		 !rb_autoload_defined(node->nd_cname))) {
		module = rb_const_get_at(ruby_class, node->nd_cname);
	    }
	    if (ruby_wrapper && rb_const_defined_at(rb_cObject, node->nd_cname)) {
		module = rb_const_get_at(rb_cObject, node->nd_cname);
	    }
	    if (module) {
		if (TYPE(module) != T_MODULE) {
		    rb_raise(rb_eTypeError, "%s is not a module",
			     rb_id2name(node->nd_cname));
		}
		if (safe_level >= 4) {
		    rb_raise(rb_eSecurityError, "extending module prohibited");
		}
	    }
	    else {
		module = rb_define_module_id(node->nd_cname);
		rb_const_set(ruby_class, node->nd_cname, module);
		rb_set_class_path(module,ruby_class,rb_id2name(node->nd_cname));
	    }
	    if (ruby_wrapper) {
		rb_extend_object(module, ruby_wrapper);
		rb_include_module(module, ruby_wrapper);
	    }

	    result = module_setup(module, node->nd_body);
	}
	break;

      case NODE_SCLASS:
	{
	    VALUE klass;

	    klass = rb_eval(self, node->nd_recv);
	    if (rb_special_const_p(klass)) {
		rb_raise(rb_eTypeError, "no virtual class for %s",
			 rb_class2name(CLASS_OF(klass)));
	    }
	    if (FL_TEST(CLASS_OF(klass), FL_SINGLETON)) {
		rb_clear_cache();
	    }
	    klass = rb_singleton_class(klass);
	    if (ruby_wrapper) {
		rb_extend_object(klass, ruby_wrapper);
		rb_include_module(klass, ruby_wrapper);
	    }
	    
	    result = module_setup(klass, node->nd_body);
	}
	break;

      case NODE_DEFINED:
	{
	    char buf[20];
	    char *desc = is_defined(self, node->nd_head, buf);

	    if (desc) result = rb_str_new2(desc);
	    else result = Qnil;
	}
	break;

    case NODE_NEWLINE:
	ruby_sourcefile = node->nd_file;
	ruby_sourceline = node->nd_nth;
	if (trace_func) {
	    call_trace_func("line", ruby_sourcefile, ruby_sourceline,
			    self, ruby_frame->last_func, 0);	
	}
	node = node->nd_next;
	goto again;

      default:
	rb_bug("unknown node type %d", nd_type(node));
    }
  finish:
    CHECK_INTS;
    return result;
}

static VALUE
module_setup(module, node)
    VALUE module;
    NODE * volatile node;
{
    int state;
    struct FRAME frame;
    VALUE result;		/* OK */
    char *file = ruby_sourcefile;
    int line = ruby_sourceline;
    TMP_PROTECT;

    frame = *ruby_frame;
    frame.tmp = ruby_frame;
    ruby_frame = &frame;

    /* fill c-ref */
    node->nd_clss = module;
    node = node->nd_body;

    PUSH_CLASS();
    ruby_class = module;
    PUSH_SCOPE();
    PUSH_VARS();

    if (node->nd_rval) ruby_frame->cbase = node->nd_rval;
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

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	if (trace_func) {
	    call_trace_func("class", file, line,
			    ruby_class, ruby_frame->last_func, 0);
	}
	result = rb_eval(ruby_class, node->nd_next);
    }
    POP_TAG();
    POP_VARS();
    POP_SCOPE();
    POP_CLASS();

    ruby_frame = frame.tmp;
    if (trace_func) {
	call_trace_func("end", file, line, 0, ruby_frame->last_func, 0);
    }
    if (state) JUMP_TAG(state);

    return result;
}

int
rb_respond_to(obj, id)
    VALUE obj;
    ID id;
{
    if (rb_method_boundp(CLASS_OF(obj), id, 0)) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
rb_obj_respond_to(argc, argv, obj)
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

static VALUE
rb_mod_method_defined(mod, mid)
    VALUE mod, mid;
{
    if (rb_method_boundp(mod, rb_to_id(mid), 1)) {
	return Qtrue;
    }
    return Qfalse;
}

void
rb_exit(status)
    int status;
{
    if (prot_tag) {
	exit_status = status;
	rb_exc_raise(rb_exc_new(rb_eSystemExit, 0, 0));
    }
    rb_exec_end_proc();
    rb_gc_call_finalizer_at_exit();
    exit(status);
}

static VALUE
rb_f_exit(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE status;
    int istatus;

    rb_secure(4);
    if (rb_scan_args(argc, argv, "01", &status) == 1) {
	istatus = NUM2INT(status);
    }
    else {
	istatus = 0;
    }
    rb_exit(istatus);
    return Qnil;		/* not reached */
}

static void
rb_abort()
{
    if (ruby_errinfo) {
	error_print();
    }
    rb_exit(1);
}

static VALUE
rb_f_abort()
{
    rb_secure(4);
    rb_abort();
    return Qnil;		/* not reached */
}

void
rb_iter_break()
{
    JUMP_TAG(TAG_BREAK);
}

static void rb_longjmp _((int, VALUE)) NORETURN;
static VALUE make_backtrace _((void));

static void
rb_longjmp(tag, mesg)
    int tag;
    VALUE mesg;
{
    VALUE at;

    if (NIL_P(mesg)) mesg = ruby_errinfo;
    if (NIL_P(mesg)) {
	mesg = rb_exc_new(rb_eRuntimeError, 0, 0);
    }

    if (ruby_sourcefile && !NIL_P(mesg)) {
	at = get_backtrace(mesg);
	if (NIL_P(at)) {
	    at = make_backtrace();
	    set_backtrace(mesg, at);
	}
    }
    if (!NIL_P(mesg)) {
	ruby_errinfo = mesg;
    }

    if (RTEST(ruby_debug) && !NIL_P(ruby_errinfo)
	&& !rb_obj_is_kind_of(ruby_errinfo, rb_eSystemExit)) {
	fprintf(stderr, "Exception `%s' at %s:%d\n",
		rb_class2name(CLASS_OF(ruby_errinfo)),
		ruby_sourcefile, ruby_sourceline);
    }

    rb_trap_restore_mask();
    if (trace_func && tag != TAG_FATAL) {
	call_trace_func("raise", ruby_sourcefile, ruby_sourceline,
			ruby_frame->self, ruby_frame->last_func, 0);
    }
    if (!prot_tag) {
	error_print();
    }
    JUMP_TAG(tag);
}

void
rb_exc_raise(mesg)
    VALUE mesg;
{
    rb_longjmp(TAG_RAISE, mesg);
}

void
rb_exc_fatal(mesg)
    VALUE mesg;
{
    rb_longjmp(TAG_FATAL, mesg);
}

void
rb_interrupt()
{
    rb_raise(rb_eInterrupt, "");
}

static VALUE
rb_f_raise(argc, argv)
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
	rb_raise(rb_eArgError, "wrong # of arguments");
	break;
    }
    if (argc > 0) {
	if (!rb_obj_is_kind_of(mesg, rb_eException))
	    rb_raise(rb_eTypeError, "exception object expected");
	set_backtrace(mesg, (argc>2)?argv[2]:Qnil);
    }

    PUSH_FRAME();		/* fake frame */
    *ruby_frame = *_frame.prev->prev;
    rb_longjmp(TAG_RAISE, mesg);
    POP_FRAME();

    return Qnil;		/* not reached */
}

void
rb_jump_tag(tag)
    int tag;
{
    JUMP_TAG(tag);
}

int
rb_iterator_p()
{
    if (ruby_frame->iter) return Qtrue;
    return Qfalse;
}

static VALUE
rb_f_iterator_p()
{
    if (ruby_frame->prev && ruby_frame->prev->iter) return Qtrue;
    return Qfalse;
}

static VALUE
rb_yield_0(val, self, klass, acheck)
    VALUE val, self, klass;	/* OK */
    int acheck;
{
    NODE *node;
    volatile VALUE result = Qnil;
    struct BLOCK *block;
    struct SCOPE *old_scope;
    struct FRAME frame;
    int state;
    static unsigned serial = 1;

    if (!ruby_frame->iter || !ruby_block) {
	rb_raise(rb_eLocalJumpError, "yield called out of iterator");
    }

    PUSH_VARS();
    PUSH_CLASS();
    block = ruby_block;
    frame = block->frame;
    frame.prev = ruby_frame;
    ruby_frame = &(frame);
    old_scope = ruby_scope;
    ruby_scope = block->scope;
    ruby_block = block->prev;
    if (block->flags & BLOCK_D_SCOPE) {
	/* put place holder for dynamic (in-block) local variables */
	ruby_dyna_vars = new_dvar(0, 0, block->d_vars);
    }
    else {
	/* FOR does not introduce new scope */
	ruby_dyna_vars = block->d_vars;
    }
    ruby_class = klass?klass:block->klass;
    if (!self) self = block->self;
    node = block->body;
    if (block->var) {
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    if (nd_type(block->var) == NODE_MASGN)
		massign(self, block->var, val, acheck);
	    else
		assign(self, block->var, val, acheck);
	}
	POP_TAG();
	if (state) goto pop_state;
    }
    PUSH_ITER(block->iter);
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
      redo:
	if (!node) {
	    result = Qnil;
	}
	else if (nd_type(node) == NODE_CFUNC) {
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
	    goto redo;
	  case TAG_NEXT:
	    state = 0;
	    result = Qnil;
	    break;
	  case TAG_BREAK:
	  case TAG_RETURN:
	    state |= (serial++ << 8);
	    state |= 0x10;
	    block->tag->dst = state; 
	    break;
	  default:
	    break;
	}
    }
    POP_TAG();
  pop_state:
    POP_ITER();
    POP_CLASS();
    POP_VARS();
    ruby_block = block;
    ruby_frame = ruby_frame->prev;
    if (FL_TEST(ruby_scope, SCOPE_DONT_RECYCLE))
	FL_SET(old_scope, SCOPE_DONT_RECYCLE);
    ruby_scope = old_scope;
    if (state) JUMP_TAG(state);
    return result;
}

VALUE
rb_yield(val)
    VALUE val;
{
    return rb_yield_0(val, 0, 0, Qfalse);
}

static VALUE
rb_f_loop()
{
    for (;;) { rb_yield_0(Qnil, 0, 0, Qfalse); }
}

static VALUE
massign(self, node, val, check)
    VALUE self;
    NODE *node;
    VALUE val;
    int check;
{
    NODE *list;
    int i = 0, len;

    list = node->nd_head;

    if (TYPE(val) != T_ARRAY) {
	val = rb_Array(val);
    }
    len = RARRAY(val)->len;
    for (i=0; list && i<len; i++) {
	assign(self, list->nd_head, RARRAY(val)->ptr[i], check);
	list = list->nd_next;
    }
    if (check && list) goto arg_error;
    if (node->nd_args) {
	if (node->nd_args == (NODE*)-1) {
	    /* ignore rest args */
	}
	else if (!list && i<len) {
	    assign(self, node->nd_args, rb_ary_new4(len-i, RARRAY(val)->ptr+i), check);
	}
	else {
	    assign(self, node->nd_args, rb_ary_new2(0), check);
	}
    }

    while (list) {
	i++;
	assign(self, list->nd_head, Qnil, check);
	list = list->nd_next;
    }
    return val;

  arg_error:
    while (list) {
	i++;
	list = list->nd_next;
    }
    rb_raise(rb_eArgError, "wrong # of arguments (%d for %d)", len, i);
}

static void
assign(self, lhs, val, check)
    VALUE self;
    NODE *lhs;
    VALUE val;
    int check;
{
    switch (nd_type(lhs)) {
      case NODE_GASGN:
	rb_gvar_set(lhs->nd_entry, val);
	break;

      case NODE_IASGN:
	rb_ivar_set(self, lhs->nd_vid, val);
	break;

      case NODE_LASGN:
	if (ruby_scope->local_vars == 0)
	    rb_bug("unexpected iterator variable assignment");
	ruby_scope->local_vars[lhs->nd_cnt] = val;
	break;

      case NODE_DASGN:
	rb_dvar_asgn(lhs->nd_vid, val);
	break;

      case NODE_DASGN_PUSH:
	dvar_asgn_push(lhs->nd_vid, val);
	break;

      case NODE_CASGN:
	rb_const_set(ruby_class, lhs->nd_vid, val);
	break;

      case NODE_MASGN:
	massign(self, lhs, val, check);
	break;

      case NODE_CALL:
	{
	    VALUE recv;
	    recv = rb_eval(self, lhs->nd_recv);
	    if (!lhs->nd_args) {
		/* attr set */
		rb_call(CLASS_OF(recv), recv, lhs->nd_mid, 1, &val, 0);
	    }
	    else {
		/* array set */
		VALUE args;

		args = rb_eval(self, lhs->nd_args);
		rb_ary_push(args, val);
		rb_call(CLASS_OF(recv), recv, lhs->nd_mid,
			RARRAY(args)->len, RARRAY(args)->ptr, 0);
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
    VALUE (*it_proc)(), (*bl_proc)();
    VALUE data1, data2;
{
    int state;
    volatile VALUE retval = Qnil;
    NODE *node = NEW_CFUNC(bl_proc, data2);
    VALUE self = ruby_top_self;

  iter_retry:
    PUSH_ITER(ITER_PRE);
    PUSH_BLOCK(0, node);
    PUSH_TAG(PROT_NONE);

    state = EXEC_TAG();
    if (state == 0) {
	retval = (*it_proc)(data1);
    }
    if (ruby_block->tag->dst == state) {
	state &= TAG_MASK;
	if (state == TAG_RETURN) {
	    retval = prot_tag->retval;
	}
    }
    POP_TAG();
    POP_BLOCK();
    POP_ITER();

    switch (state) {
      case 0:
	break;

      case TAG_RETRY:
	goto iter_retry;

      case TAG_BREAK:
	retval = Qnil;
	break;

      case TAG_RETURN:
	return_value(retval);
	/* fall through */
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
	if (rb_obj_is_kind_of(ruby_errinfo, argv[0])) return 1;
	argv++;
    }
    return 0;
}

VALUE
rb_rescue(b_proc, data1, r_proc, data2)
    VALUE (*b_proc)(), (*r_proc)();
    VALUE data1, data2;
{
    int state;
    volatile VALUE result;
    volatile VALUE e_info = ruby_errinfo;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
      retry_entry:
	result = (*b_proc)(data1);
    }
    else if (state == TAG_RAISE && rb_obj_is_kind_of(ruby_errinfo, rb_eStandardError)) {
	if (r_proc) {
	    PUSH_TAG(PROT_NONE);
	    if ((state = EXEC_TAG()) == 0) {
		result = (*r_proc)(data2, ruby_errinfo);
	    }
	    POP_TAG();
	    if (state == TAG_RETRY) {
		state = 0;
		goto retry_entry;
	    }
	}
	else {
	    result = Qnil;
	    state = 0;
	}
	if (state == 0) {
	    ruby_errinfo = e_info;
	}
    }
    POP_TAG();
    if (state) JUMP_TAG(state);

    return result;
}

VALUE
rb_protect(proc, data, state)
    VALUE (*proc)();
    VALUE data;
    int *state;
{
    VALUE result;		/* OK */
    int status;

    PUSH_TAG(PROT_NONE);
    if ((status = EXEC_TAG()) == 0) {
	result = (*proc)(data);
    }
    POP_TAG();
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
    VALUE (*e_proc)();
    VALUE data1, data2;
{
    int state;
    volatile VALUE result = Qnil;
    VALUE retval;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	result = (*b_proc)(data1);
    }
    POP_TAG();
    retval = prot_tag->retval;	/* save retval */
    (*e_proc)(data2);
    return_value(retval);

    if (state) JUMP_TAG(state);
    return result;
}

VALUE
rb_with_disable_interrupt(proc, data)
    VALUE (*proc)();
    VALUE data;
{
    VALUE result;		/* OK */
    int status;

    DEFER_INTS;
    PUSH_TAG(PROT_NONE);
    if ((status = EXEC_TAG()) == 0) {
	result = (*proc)(data);
    }
    POP_TAG();
    ALLOW_INTS;
    if (status) JUMP_TAG(status);

    return result;
}

static int last_call_status;

#define CSTAT_PRIV  1
#define CSTAT_PROT  2
#define CSTAT_VCALL 4

static VALUE
rb_f_missing(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    ID    id;
    volatile VALUE d = 0;
    char *format = 0;
    char *desc = "";
    const char *mname;
    char *file = ruby_sourcefile;
    int   line = ruby_sourceline;

    if (argc == 0 || (id = NUM2INT(argv[0]),  mname = rb_id2name(id)) == 0) {
	rb_raise(rb_eArgError, "no id given");
    }
    argc--; argv++;

    switch (TYPE(obj)) {
      case T_NIL:
	format = "undefined method `%s' for nil";
	break;
      case T_TRUE:
	format = "undefined method `%s' for true";
	break;
      case T_FALSE:
	format = "undefined method `%s' for false";
	break;
      case T_OBJECT:
	d = rb_any_to_s(obj);
	break;
      default:
	d = rb_inspect(obj);
	break;
    }
    if (d) {
	if (last_call_status & CSTAT_PRIV) {
	    format = "private method `%s' called for %s%s%s";
	}
	if (last_call_status & CSTAT_PROT) {
	    format = "protected method `%s' called for %s%s%s";
	}
	else if (last_call_status & CSTAT_VCALL) {
	    if (('a' <= mname[0] && mname[0] <= 'z') || mname[0] == '_') {
		format = "undefined local variable or method `%s' for %s%s%s";
	    }
	}
	if (!format) {
	    format = "undefined method `%s' for %s%s%s";
	}
	if (RSTRING(d)->len > 65) {
	    d = rb_any_to_s(obj);
	}
	desc = RSTRING(d)->ptr;
    }

    ruby_sourcefile = file;
    ruby_sourceline = line;
    PUSH_FRAME();		/* fake frame */
    *ruby_frame = *_frame.prev->prev;

    rb_raise(rb_eNameError, format, mname,
	     desc, desc[0]=='#'?"":":",
	     desc[0]=='#'?"":rb_class2name(CLASS_OF(obj)));
    POP_FRAME();

    return Qnil;		/* not reached */
}

static VALUE
rb_undefined(obj, id, argc, argv, call_status)
    VALUE obj;
    ID    id;
    int   argc;
    VALUE*argv;
    int   call_status;
{
    VALUE *nargv;

    nargv = ALLOCA_N(VALUE, argc+1);
    nargv[0] = INT2FIX(id);
    MEMCPY(nargv+1, argv, VALUE, argc);

    last_call_status = call_status;

    return rb_funcall2(obj, missing, argc+1, nargv);
}

#ifdef DJGPP
# define STACK_LEVEL_MAX 65535
#else
#ifdef __human68k__
extern int _stacksize;
# define STACK_LEVEL_MAX (_stacksize - 4096)
#else
# define STACK_LEVEL_MAX 655300
#endif
#endif
extern VALUE *rb_gc_stack_start;
static int
stack_length()
{
    VALUE pos;

#ifdef sparc
    return rb_gc_stack_start - &pos + 0x80;
#else
    return (&pos < rb_gc_stack_start) ? rb_gc_stack_start - &pos
	                              : &pos - rb_gc_stack_start;
#endif
}

static VALUE
call_cfunc(func, recv, len, argc, argv)
    VALUE (*func)();
    VALUE recv;
    int len, argc;
    VALUE *argv;
{
    if (len >= 0 && argc != len) {
	rb_raise(rb_eArgError, "wrong # of arguments(%d for %d)",
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
	rb_raise(rb_eArgError, "too many arguments(%d)", len);
	break;
    }
    return Qnil;		/* not reached */
}

static VALUE
rb_call0(klass, recv, id, argc, argv, body, nosuper)
    VALUE klass, recv;
    ID    id;
    int argc;			/* OK */
    VALUE *argv;		/* OK */
    NODE *body;			/* OK */
    int nosuper;
{
    NODE *b2;		/* OK */
    volatile VALUE result = Qnil;
    int itr;
    static int tick;
    TMP_PROTECT;

    switch (ruby_iter->iter) {
      case ITER_PRE:
	itr = ITER_CUR;
	break;
      case ITER_CUR:
      default:
	itr = ITER_NOT;
	break;
    }

    if ((++tick & 0x3ff) == 0) {
	CHECK_INTS;		/* better than nothing */
	if (stack_length() > STACK_LEVEL_MAX) {
	    rb_raise(rb_eSysStackError, "stack level too deep");
	}
    }
    PUSH_ITER(itr);
    PUSH_FRAME();

    ruby_frame->last_func = id;
    ruby_frame->last_class = nosuper?0:klass;
    ruby_frame->self = recv;
    ruby_frame->argc = argc;
    ruby_frame->argv = argv;

    switch (nd_type(body)) {
      case NODE_CFUNC:
	{
	    int len = body->nd_argc;

	    if (len < -2) {
		rb_bug("bad argc(%d) specified for `%s(%s)'",
		       len, rb_class2name(klass), rb_id2name(id));
	    }
	    if (trace_func) {
		int state;
		char *file = ruby_frame->prev->file;
		int line = ruby_frame->prev->line;
		if (!file) {
		    file = ruby_sourcefile;
		    line = ruby_sourceline;
		}

		call_trace_func("c-call", 0, 0, recv, id, klass);
		PUSH_TAG(PROT_FUNC);
		if ((state = EXEC_TAG()) == 0) {
		    result = call_cfunc(body->nd_cfnc, recv, len, argc, argv);
		}
		POP_TAG();
		call_trace_func("c-return", 0, 0, recv, id, klass);
		if (state) JUMP_TAG(state);
	    }
	    else {
		result = call_cfunc(body->nd_cfnc, recv, len, argc, argv);
	    }
	}
	break;

	/* for re-scoped/renamed method */
      case NODE_ZSUPER:
	/* for attr get/set */
      case NODE_ATTRSET:
      case NODE_IVAR:
	result = rb_eval(recv, body);
	break;

      default:
	{
	    int state;
	    VALUE *local_vars;	/* OK */

	    PUSH_SCOPE();

	    if (body->nd_rval) ruby_frame->cbase = body->nd_rval;
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

	    PUSH_VARS();
	    PUSH_TAG(PROT_FUNC);

	    if ((state = EXEC_TAG()) == 0) {
		NODE *node = 0;
		int i;

		if (nd_type(body) == NODE_ARGS) {
		    node = body;
		    body = 0;
		}
		else if (nd_type(body) == NODE_BLOCK) {
		    node = body->nd_head;
		    body = body->nd_next;
		}
		if (node) {
		    if (nd_type(node) != NODE_ARGS) {
			rb_bug("no argument-node");
		    }

		    i = node->nd_cnt;
		    if (i > argc) {
			rb_raise(rb_eArgError, "wrong # of arguments(%d for %d)",
				 argc, i);
		    }
		    if (node->nd_rest == -1) {
			int opt = i;
			NODE *optnode = node->nd_opt;

			while (optnode) {
			    opt++;
			    optnode = optnode->nd_next;
			}
			if (opt < argc) {
			    rb_raise(rb_eArgError, "wrong # of arguments(%d for %d)",
				     argc, opt);
			}
			ruby_frame->argc = opt;
			ruby_frame->argv = local_vars+2;
		    }

		    if (local_vars) {
			if (i > 0) {
			    /* +2 for $_ and $~ */
			    MEMCPY(local_vars+2, argv, VALUE, i);
			}
			argv += i; argc -= i;
			if (node->nd_opt) {
			    NODE *opt = node->nd_opt;

			    while (opt && argc) {
				assign(recv, opt->nd_head, *argv, 1);
				argv++; argc--;
				opt = opt->nd_next;
			    }
			    rb_eval(recv, opt);
			}
			if (node->nd_rest >= 0) {
			    if (argc > 0)
				local_vars[node->nd_rest]=rb_ary_new4(argc,argv);
			    else
				local_vars[node->nd_rest]=rb_ary_new2(0);
			}
		    }
		}

		if (trace_func) {
		    call_trace_func("call", b2->nd_file, nd_line(b2),
				    recv, ruby_frame->last_func, 0);
		}
		result = rb_eval(recv, body);
	    }
	    else if (state == TAG_RETURN) {
		result = prot_tag->retval;
		state = 0;
	    }
	    POP_TAG();
	    POP_VARS();
	    POP_SCOPE();
	    if (trace_func) {
		char *file = ruby_frame->prev->file;
		int line = ruby_frame->prev->line;
		if (!file) {
		    file = ruby_sourcefile;
		    line = ruby_sourceline;
		}
		call_trace_func("return", file, line, recv,
				ruby_frame->last_func, klass);
	    }
	    switch (state) {
	      case 0:
		break;

	      case TAG_NEXT:
		rb_raise(rb_eLocalJumpError, "unexpected next");
		break;
	      case TAG_BREAK:
		rb_raise(rb_eLocalJumpError, "unexpected break");
		break;
	      case TAG_REDO:
		rb_raise(rb_eLocalJumpError, "unexpected redo");
		break;
	      case TAG_RETRY:
		if (!rb_iterator_p()) {
		    rb_raise(rb_eLocalJumpError, "retry outside of rescue clause");
		}
	      default:
		JUMP_TAG(state);
	    }
	}
    }
    POP_FRAME();
    POP_ITER();
    return result;
}

static VALUE
rb_call(klass, recv, mid, argc, argv, scope)
    VALUE klass, recv;
    ID    mid;
    int argc;			/* OK */
    VALUE *argv;		/* OK */
    int scope;
{
    NODE  *body;		/* OK */
    int    noex;
    ID     id = mid;
    struct cache_entry *ent;

    /* is it in the method cache? */
    ent = cache + EXPR1(klass, mid);
    if (ent->mid == mid && ent->klass == klass) {
	if (!ent->method)
	    return rb_undefined(recv, mid, argc, argv, scope==2?CSTAT_VCALL:0);
	klass = ent->origin;
	id    = ent->mid0;
	noex  = ent->noex;
	body  = ent->method;
    }
    else if ((body = rb_get_method_body(&klass, &id, &noex)) == 0) {
	if (scope == 3) {
	    rb_raise(rb_eNameError, "super: no superclass method `%s'",
		     rb_id2name(mid));
	}
	return rb_undefined(recv, mid, argc, argv, scope==2?CSTAT_VCALL:0);
    }

    if (mid != missing) {
	/* receiver specified form for private method */
	if ((noex & NOEX_PRIVATE) && scope == 0)
	    return rb_undefined(recv, mid, argc, argv, CSTAT_PRIV);

	/* self must be kind of a specified form for private method */
	if ((noex & NOEX_PROTECTED)) {
	    VALUE defined_class = klass;
	    while (TYPE(defined_class) == T_ICLASS)
		defined_class = RBASIC(defined_class)->klass;
	    if (!rb_obj_is_kind_of(ruby_frame->self, defined_class))
		return rb_undefined(recv, mid, argc, argv, CSTAT_PROT);
	}
    }

    return rb_call0(klass, recv, id, argc, argv, body, noex & NOEX_UNDEF);
}

VALUE
rb_apply(recv, mid, args)
    VALUE recv;
    ID mid;
    VALUE args;
{
    int argc;
    VALUE *argv;

    argc = RARRAY(args)->len;
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, 1);
}

static VALUE
rb_f_send(argc, argv, recv)
    int argc;
    VALUE *argv;
    VALUE recv;
{
    VALUE vid;

    if (argc == 0) rb_raise(rb_eArgError, "no method name given");

    vid = *argv++; argc--;
    PUSH_ITER(rb_iterator_p()?ITER_PRE:ITER_NOT);
    vid = rb_call(CLASS_OF(recv), recv, rb_to_id(vid), argc, argv, 1);
    POP_ITER();

    return vid;
}


#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif

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
    VALUE *argv;

    if (n > 0) {
	int i;

	argv = ALLOCA_N(VALUE, n);

	va_init_list(ar, n);
	for (i=0;i<n;i++) {
	    argv[i] = va_arg(ar, VALUE);
	}
	va_end(ar);
    }
    else {
	argv = 0;
    }

    return rb_call(CLASS_OF(recv), recv, mid, n, argv, 1);
}

VALUE
rb_funcall2(recv, mid, argc, argv)
    VALUE recv;
    ID mid;
    int argc;
    VALUE *argv;
{
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, 1);
}

VALUE
rb_funcall3(recv, mid, argc, argv)
    VALUE recv;
    ID mid;
    int argc;
    VALUE *argv;
{
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, 0);
}

VALUE
rb_call_super(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE result;

    if (ruby_frame->last_class == 0) {	
	rb_raise(rb_eNameError, "superclass method `%s' must be enabled by rb_enable_super()",
		 rb_id2name(ruby_frame->last_func));
    }

    PUSH_ITER(ruby_iter->iter?ITER_PRE:ITER_NOT);
    result = rb_call(RCLASS(ruby_frame->last_class)->super,
		     ruby_frame->self, ruby_frame->last_func,
		     argc, argv, 3);
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

    ary = rb_ary_new();
    if (lev < 0) {
	if (frame->last_func) {
	    snprintf(buf, BUFSIZ, "%s:%d:in `%s'",
		     ruby_sourcefile, ruby_sourceline,
		     rb_id2name(frame->last_func));
	}
	else {
	    snprintf(buf, BUFSIZ, "%s:%d", ruby_sourcefile, ruby_sourceline);
	}
	rb_ary_push(ary, rb_str_new2(buf));
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
    while (frame && frame->file) {
	if (frame->prev && frame->prev->last_func) {
	    snprintf(buf, BUFSIZ, "%s:%d:in `%s'",
		     frame->file, frame->line,
		     rb_id2name(frame->prev->last_func));
	}
	else {
	    snprintf(buf, BUFSIZ, "%s:%d", frame->file, frame->line);
	}
	rb_ary_push(ary, rb_str_new2(buf));
	frame = frame->prev;
    }

    return ary;
}

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
    if (lev < 0) rb_raise(rb_eArgError, "negative level(%d)", lev);

    return backtrace(lev);
}

void
rb_backtrace()
{
    int i, lev;
    VALUE ary;

    lev = INT2FIX(0);
    ary = backtrace(-1);
    for (i=0; i<RARRAY(ary)->len; i++) {
	printf("\tfrom %s\n", RSTRING(RARRAY(ary)->ptr[i])->ptr);
    }
}

static VALUE
make_backtrace()
{
    VALUE lev;

    lev = INT2FIX(0);
    return backtrace(-1);
}

ID
rb_frame_last_func()
{
    return ruby_frame->last_func;
}

static NODE*
compile(src, file, line)
    VALUE src;
    char *file;
    int line;
{
    NODE *node;

    Check_Type(src, T_STRING);
    node = rb_compile_string(file, src, line);

    if (ruby_nerrs == 0) return node;
    return 0;
}

static VALUE
eval(self, src, scope, file, line)
    VALUE self, src, scope;
    char *file;
    int line;
{
    struct BLOCK *data;
    volatile VALUE result = Qnil;
    struct SCOPE * volatile old_scope;
    struct BLOCK * volatile old_block;
    struct RVarmap * volatile old_d_vars;
    int volatile old_vmode;
    struct FRAME frame;
    char *filesave = ruby_sourcefile;
    int linesave = ruby_sourceline;
    volatile int iter = ruby_frame->iter;
    int state;

    if (file == 0) {
	file = ruby_sourcefile;
	line = ruby_sourceline;
    }
    if (!NIL_P(scope)) {
	if (!rb_obj_is_block(scope)) {
	    rb_raise(rb_eTypeError, "wrong argument type %s (expected Proc/Binding)",
		     rb_class2name(CLASS_OF(scope)));
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
	old_d_vars = ruby_dyna_vars;
	ruby_dyna_vars = data->d_vars;
	old_vmode = scope_vmode;
	scope_vmode = data->vmode;

	self = data->self;
	ruby_frame->iter = data->iter;
    }
    else {
	if (ruby_frame->prev) {
	    ruby_frame->iter = ruby_frame->prev->iter;
	}
    }
    PUSH_CLASS();
    ruby_class = ((NODE*)ruby_frame->cbase)->nd_clss;

    ruby_in_eval++;
    if (TYPE(ruby_class) == T_ICLASS) {
	ruby_class = RBASIC(ruby_class)->klass;
    }
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	DEFER_INTS;
	compile(src, file, line);
	if (ruby_nerrs > 0) {
	    compile_error(0);
	}
	result = eval_node(self);
	ALLOW_INTS;
    }
    POP_TAG();
    POP_CLASS();
    ruby_in_eval--;
    if (!NIL_P(scope)) {
	ruby_frame = frame.tmp;
	if (FL_TEST(ruby_scope, SCOPE_DONT_RECYCLE))
	    FL_SET(old_scope, SCOPE_DONT_RECYCLE);
	ruby_scope = old_scope;
	ruby_block = old_block;
	ruby_dyna_vars = old_d_vars;
	data->vmode = scope_vmode; /* write back visibility mode */
	scope_vmode = old_vmode;
    }
    else {
	ruby_frame->iter = iter;
    }
    ruby_sourcefile = filesave;
    ruby_sourceline = linesave;
    if (state) {
	if (state == TAG_RAISE) {
	    VALUE err;
	    VALUE errat;

	    errat = get_backtrace(ruby_errinfo);
	    if (strcmp(file, "(eval)") == 0) {
		if (ruby_sourceline > 1) {
		    err = RARRAY(errat)->ptr[0];
		    rb_str_cat(err, ": ", 2);
		    rb_str_concat(err, ruby_errinfo);
		}
		else {
		    err = rb_str_dup(ruby_errinfo);
		}
		errat = Qnil;
		rb_exc_raise(rb_exc_new3(CLASS_OF(ruby_errinfo), err));
	    }
	    rb_exc_raise(ruby_errinfo);
	}
	JUMP_TAG(state);
    }

    return result;
}

static VALUE
rb_f_eval(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE src, scope, vfile, vline, val;
    char *file = "(eval)";
    int line = 1;

    rb_scan_args(argc, argv, "13", &src, &scope, &vfile, &vline);
    if (argc >= 3) {
	Check_Type(vfile, T_STRING);
	file = RSTRING(vfile)->ptr;
    }
    if (argc >= 4) {
	line = NUM2INT(vline);
    }

    Check_SafeStr(src);
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
exec_under(func, under, args)
    VALUE (*func)();
    VALUE under;
    void *args;
{
    VALUE val;			/* OK */
    int state;
    int mode;
    VALUE cbase = ruby_frame->cbase;

    PUSH_CLASS();
    ruby_class = under;
    PUSH_FRAME();
    ruby_frame->last_func = _frame.prev->last_func;
    ruby_frame->last_class = _frame.prev->last_class;
    ruby_frame->argc = _frame.prev->argc;
    ruby_frame->argv = _frame.prev->argv;
    if (RNODE(ruby_frame->cbase)->nd_clss != under) {
	ruby_frame->cbase = (VALUE)rb_node_newnode(NODE_CREF,under,0,ruby_frame->cbase);
    }
    mode = scope_vmode;
    SCOPE_SET(SCOPE_PUBLIC);
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	val = (*func)(args);
    }
    POP_TAG();
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

    Check_SafeStr(src);
    args[0] = self;
    args[1] = src;
    args[2] = (VALUE)file;
    args[3] = (VALUE)line;
    return exec_under(eval_under_i, under, args);
}

static VALUE
yield_under_i(self)
    VALUE self;
{
    if (ruby_block->flags & BLOCK_DYNAMIC) {
	struct BLOCK * volatile old_block = ruby_block;
	struct BLOCK block;
	volatile VALUE cbase = ruby_block->frame.cbase;
	/* cbase should be pointed from volatile local variable */
	/* to be protected from GC. 				*/
	VALUE result;
	int state;

	block = *ruby_block;
	/* copy the block to avoid modifying global data. */
	block.frame.cbase = ruby_frame->cbase;
	ruby_block = &block;

	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    result = rb_yield_0(self, self, ruby_class, Qfalse);
	}
	POP_TAG();
	ruby_block = old_block;
	if (state) JUMP_TAG(state);
	
	return result;
    }
    /* static block, no need to restore */
    ruby_block->frame.cbase = ruby_frame->cbase;
    return rb_yield_0(self, self, ruby_class, Qfalse);
}

/* block eval under the class/module context */
static VALUE
yield_under(under, self)
    VALUE under, self;
{
    if (rb_safe_level() >= 4 && !FL_TEST(self, FL_TAINT))
	rb_raise(rb_eSecurityError, "Insecure: can't eval");
    return exec_under(yield_under_i, under, self);
}

static VALUE
specific_eval(argc, argv, klass, self)
    int argc;
    VALUE *argv;
    VALUE klass, self;
{
    char *file = "(eval)";
    int   line = 1;
    int   iter = rb_iterator_p();

    if (argc > 0) {
	Check_SafeStr(argv[0]);
	if (argc > 3) {
	    rb_raise(rb_eArgError, "wrong # of arguments: %s(src) or %s{..}",
		     rb_id2name(ruby_frame->last_func),
		     rb_id2name(ruby_frame->last_func));
	}
	if (argc > 1) file = STR2CSTR(argv[1]);
	if (argc > 2) line = NUM2INT(argv[2]);
    }
    else if (!iter) {
	rb_raise(rb_eArgError, "block not supplied");
    }

    if (iter) {
	return yield_under(klass, self);
    }
    else {
	return eval_under(klass, self, argv[0], file, line);
    }
}

VALUE
rb_obj_instance_eval(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE klass;

    if (rb_special_const_p(self)) {
	klass = Qnil;
    }
    else {
	klass = rb_singleton_class(self);
    }

    return specific_eval(argc, argv, klass, self);
}

static VALUE
rb_mod_module_eval(argc, argv, mod)
    int argc;
    VALUE *argv;
    VALUE mod;
{
    return specific_eval(argc, argv, mod, mod);
}

VALUE rb_load_path;

static int
is_absolute_path(path)
    const char *path;
{
    if (path[0] == '/') return 1;
# if defined DOSISH
    if (path[0] == '\\') return 1;
    if (strlen(path) > 2 && path[1] == ':') return 1;
# endif
    return 0;
}

#ifdef __MACOS__
static int
is_macos_native_path(path)
    const char *path;
{
    if (strchr(path, ':')) return 1;
    return 0;
}
#endif

static char*
find_file(file)
    char *file;
{
    extern VALUE rb_load_path;
    volatile VALUE vpath;
    char *path;

#ifdef __MACOS__
    if (is_macos_native_path(file)) {
	FILE *f = fopen(file, "r");

	if (f == NULL) return 0;
	fclose(f);
	return file;
    }
#endif

    if (is_absolute_path(file)) {
	FILE *f = fopen(file, "r");

	if (f == NULL) return 0;
	fclose(f);
	return file;
    }

    if (file[0] == '~') {
	VALUE argv[1];
	argv[0] = rb_str_new2(file);
	file = STR2CSTR(rb_file_s_expand_path(1, argv));
    }

    if (rb_load_path) {
	int i;

	Check_Type(rb_load_path, T_ARRAY);
	vpath = rb_ary_new();
	for (i=0;i<RARRAY(rb_load_path)->len;i++) {
	    VALUE str = RARRAY(rb_load_path)->ptr[i];
	    Check_SafeStr(str);
	    if (RSTRING(str)->len > 0) {
		rb_ary_push(vpath, str);
	    }
	}
	vpath = rb_ary_join(vpath, rb_str_new2(PATH_SEP));
	path = STR2CSTR(vpath);
	if (safe_level >= 2 && !rb_path_check(path)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe path %s", path);
	}
    }
    else {
	path = 0;
    }
    file = dln_find_file(file, path);
    if (file) {
	FILE *f = fopen(file, "r");

	if (f == NULL) return 0;
	fclose(f);
	return file;
    }
    return 0;
}

void
rb_load(fname, wrap)
    VALUE fname;
    int wrap;
{
    int state;
    char *file;
    volatile ID last_func;
    volatile VALUE wrapper = 0;
    VALUE self = ruby_top_self;
    TMP_PROTECT;

    if (wrap) {
	Check_Type(fname, T_STRING);
    }
    else {
	Check_SafeStr(fname);
    }
    file = find_file(RSTRING(fname)->ptr);
    if (!file) {
	rb_raise(rb_eLoadError, "No such file to load -- %s", RSTRING(fname)->ptr);
    }

    PUSH_VARS();
    PUSH_CLASS();
    wrapper = ruby_wrapper;
    if (!wrap) {
	rb_secure(4);		/* should alter global state */
	ruby_class = rb_cObject;
	ruby_wrapper = 0;
    }
    else {
	/* load in anonymous module as toplevel */
	ruby_class = ruby_wrapper = rb_module_new();
	self = rb_obj_clone(ruby_top_self);
	rb_extend_object(self, ruby_class);
    }
    PUSH_FRAME();
    ruby_frame->last_func = 0;
    ruby_frame->last_class = 0;
    ruby_frame->self = self;
    ruby_frame->cbase = (VALUE)rb_node_newnode(NODE_CREF,ruby_class,0,0);
    PUSH_SCOPE();
    if (ruby_class == rb_cObject && top_scope->local_tbl) {
	int len = top_scope->local_tbl[0]+1;
	ID *tbl = ALLOC_N(ID, len);
	VALUE *vars = TMP_ALLOC(len);
	*vars++ = 0;
	MEMCPY(tbl, top_scope->local_tbl, ID, len);
	MEMCPY(vars, top_scope->local_vars, VALUE, len-1);
	ruby_scope->local_tbl = tbl;   /* copy toplevel scope */
	ruby_scope->local_vars = vars; /* will not alter toplevel variables */
    }
    /* default visibility is private at loading toplevel */
    SCOPE_SET(SCOPE_PRIVATE);

    PUSH_TAG(PROT_NONE);
    state = EXEC_TAG();
    last_func = ruby_frame->last_func;
    if (state == 0) {
	DEFER_INTS;
	ruby_in_eval++;
	rb_load_file(file);
	ruby_in_eval--;
	if (ruby_nerrs == 0) {
	    eval_node(self);
	}
	ALLOW_INTS;
    }
    ruby_frame->last_func = last_func;
    if (ruby_scope->flag == SCOPE_ALLOCA && ruby_class == rb_cObject) {
	if (ruby_scope->local_tbl) /* toplevel was empty */
	    free(ruby_scope->local_tbl);
    }
    POP_TAG();
    POP_SCOPE();
    POP_FRAME();
    POP_CLASS();
    POP_VARS();
    ruby_wrapper = wrapper;
    if (ruby_nerrs > 0) {
	ruby_nerrs = 0;
	rb_exc_raise(ruby_errinfo);
    }
    if (state) JUMP_TAG(state);
}

void
rb_load_protect(fname, wrap, state)
    VALUE fname;
    int wrap;
    int *state;
{
    int status;

    PUSH_TAG(PROT_NONE);
    if ((status = EXEC_TAG()) == 0) {
	rb_load(fname, wrap);
    }
    POP_TAG();
    if (state) *state = status;
}

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

static VALUE rb_features;

static int
rb_provided(feature)
    const char *feature;
{
    VALUE *p, *pend;
    char *f;
    int len;

    p = RARRAY(rb_features)->ptr;
    pend = p + RARRAY(rb_features)->len;
    while (p < pend) {
	f = STR2CSTR(*p);
	if (strcmp(f, feature) == 0) return Qtrue;
	len = strlen(feature);
	if (strncmp(f, feature, len) == 0
	    && (strcmp(f+len, ".rb") == 0 ||strcmp(f+len, ".so") == 0)) {
	    return Qtrue;
	}
	p++;
    }
    return Qfalse;
}

static int rb_thread_loading _((const char*));
static void rb_thread_loading_done _((const char*));

void
rb_provide(feature)
    const char *feature;
{
    char *buf, *ext;

    if (!rb_provided(feature)) {
	ext = strrchr(feature, '.');
	if (ext && strcmp(DLEXT, ext) == 0) {
	    buf = ALLOCA_N(char, strlen(feature)+4);
	    strcpy(buf, feature);
	    ext = strrchr(buf, '.');
	    strcpy(ext, ".so");
	    feature = buf;
	}
	rb_ary_push(rb_features, rb_str_new2(feature));
    }
}

VALUE
rb_f_require(obj, fname)
    VALUE obj, fname;
{
    char *ext, *file, *feature, *buf; /* OK */
    volatile VALUE load;
    int state;

    rb_secure(4);
    Check_SafeStr(fname);
    if (rb_provided(RSTRING(fname)->ptr))
	return Qfalse;

    ext = strrchr(RSTRING(fname)->ptr, '.');
    if (ext) {
	if (strcmp(".rb", ext) == 0) {
	    feature = file = RSTRING(fname)->ptr;
	    file = find_file(file);
	    if (file) goto load_rb;
	}
	else if (strcmp(".so", ext) == 0 || strcmp(".o", ext) == 0) {
	    file = feature = RSTRING(fname)->ptr;
	    if (strcmp(ext, DLEXT) != 0) {
		buf = ALLOCA_N(char, strlen(file)+sizeof(DLEXT)+1);
		strcpy(buf, feature);
		ext = strrchr(buf, '.');
		strcpy(ext, ".so");
		if (rb_provided(buf)) return Qfalse;
		strcpy(ext, DLEXT);
		file = feature = buf;
		if (rb_provided(feature)) return Qfalse;
	    }
	    file = find_file(file);
	    if (file) goto load_dyna;
	}
	else if (strcmp(DLEXT, ext) == 0) {
	    feature = RSTRING(fname)->ptr;
	    file = find_file(feature);
	    if (file) goto load_dyna;
	}
    }
    buf = ALLOCA_N(char, strlen(RSTRING(fname)->ptr) + 5);
    strcpy(buf, RSTRING(fname)->ptr);
    strcat(buf, ".rb");
    if (find_file(buf)) {
	fname = rb_str_new2(buf);
	feature = buf;
	goto load_rb;
    }
    strcpy(buf, RSTRING(fname)->ptr);
    strcat(buf, DLEXT);
    file = find_file(buf);
    if (file) {
	feature = buf;
	goto load_dyna;
    }
    rb_raise(rb_eLoadError, "No such file to load -- %s",
	     RSTRING(fname)->ptr);

  load_dyna:
    if (rb_thread_loading(feature)) return Qfalse;

    rb_provide(feature);
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	load = rb_str_new2(file);
	file = RSTRING(load)->ptr;
	dln_load(file);
    }
    POP_TAG();
    rb_thread_loading_done(feature);
    if (state) JUMP_TAG(state);

    return Qtrue;

  load_rb:
    if (rb_thread_loading(feature)) return Qfalse;
    rb_provide(feature);

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	rb_load(fname, 0);
    }
    POP_TAG();
    rb_thread_loading_done(feature);
    if (state) JUMP_TAG(state);

    return Qtrue;
}

VALUE
rb_require(fname)
    const char *fname;
{
    return rb_f_require(Qnil, rb_str_new2(fname));
}

static void
set_method_visibility(self, argc, argv, ex)
    VALUE self;
    int argc;
    VALUE *argv;
    ID ex;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_export_method(self, rb_to_id(argv[i]), ex);
    }
}

static VALUE
rb_mod_public(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    if (argc == 0) {
	SCOPE_SET(SCOPE_PUBLIC);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PUBLIC);
    }
    return module;
}

static VALUE
rb_mod_protected(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    if (argc == 0) {
	SCOPE_SET(SCOPE_PROTECTED);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PROTECTED);
    }
    return module;
}

static VALUE
rb_mod_private(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    if (argc == 0) {
	SCOPE_SET(SCOPE_PRIVATE);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    }
    return module;
}

static VALUE
rb_mod_public_method(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PUBLIC);
    return obj;
}

static VALUE
rb_mod_private_method(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PRIVATE);
    return obj;
}

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

static VALUE
rb_mod_modfunc(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    int i;
    ID id;
    NODE *body;

    if (argc == 0) {
	SCOPE_SET(SCOPE_MODFUNC);
	return module;
    }

    set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    for (i=0; i<argc; i++) {
	id = rb_to_id(argv[i]);
	body = search_method(module, id, 0);
	if (body == 0 || body->nd_body == 0) {
	    rb_bug("undefined method `%s'; can't happen", rb_id2name(id));
	}
	rb_clear_cache_by_id(id);
	rb_add_method(rb_singleton_class(module), id, body->nd_body, NOEX_PUBLIC);
	rb_funcall(module, rb_intern("singleton_method_added"), 1, INT2FIX(id));
    }
    return module;
}

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

static VALUE
rb_mod_include(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    int i;

    for (i=0; i<argc; i++) {
	Check_Type(argv[i], T_MODULE);
	rb_funcall(argv[i], rb_intern("append_features"), 1, module);
    }
    return module;
}

void
rb_obj_call_init(obj, argc, argv)
    VALUE obj;
    int argc;
    VALUE *argv;
{
    PUSH_ITER(rb_iterator_p()?ITER_PRE:ITER_NOT);
    rb_funcall2(obj, init, argc, argv);
    POP_ITER();
}

VALUE
rb_class_new_instance(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE obj;

    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_raise(rb_eTypeError, "can't create instance of virtual class");
    }
    obj = rb_obj_alloc(klass);
    rb_obj_call_init(obj, argc, argv);

    return obj;
}

static VALUE
top_include(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_secure(4);
    return rb_mod_include(argc, argv, rb_cObject);
}

void
rb_extend_object(obj, module)
    VALUE obj, module;
{
    rb_include_module(rb_singleton_class(obj), module);
}

static VALUE
rb_mod_extend_object(mod, obj)
    VALUE mod, obj;
{
    rb_extend_object(obj, mod);
    return obj;
}

static VALUE
rb_obj_extend(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    int i;

    for (i=0; i<argc; i++) Check_Type(argv[i], T_MODULE);
    for (i=0; i<argc; i++) {
	rb_funcall(argv[i], rb_intern("extend_object"), 1, obj);
    }
    return obj;
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

VALUE rb_f_global_variables();
VALUE f_instance_variables();

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
	    if (tbl[i] == 0) continue;  /* skip flip states */
	    rb_ary_push(ary, rb_str_new2(rb_id2name(tbl[i])));
	}
    }

    vars = ruby_dyna_vars;
    while (vars) {
	if (vars->id) {
	    rb_ary_push(ary, rb_str_new2(rb_id2name(vars->id)));
	}
	vars = vars->next;
    }

    return ary;
}

static VALUE rb_f_catch _((VALUE,VALUE));
static VALUE rb_f_throw _((int,VALUE*)) NORETURN;

struct end_proc_data {
    void (*func)();
    VALUE data;
    struct end_proc_data *next;
};

static struct end_proc_data *end_procs, *ephemeral_end_procs;

void
rb_set_end_proc(func, data)
    void (*func)();
    VALUE data;
{
    struct end_proc_data *link = ALLOC(struct end_proc_data);
    struct end_proc_data **list;

    if (ruby_wrapper) list = &ephemeral_end_procs;
    else              list = &end_procs;
    link->next = *list;
    link->func = func;
    link->data = data;
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
}

static void
call_end_proc(data)
    VALUE data;
{
    proc_call(data, Qnil);
}

static void
rb_f_END()
{
    PUSH_FRAME();
    ruby_frame->argc = 0;
    rb_set_end_proc(call_end_proc, rb_f_lambda());
    POP_FRAME();
}

static VALUE
rb_f_at_exit()
{
    VALUE proc;

    proc = rb_f_lambda();

    rb_set_end_proc(call_end_proc, proc);
    return proc;
}

void
rb_exec_end_proc()
{
    struct end_proc_data *link;
    int status;

    link = end_procs;
    while (link) {
	rb_protect((VALUE(*)())link->func, link->data, &status);
	link = link->next;
    }
    while (ephemeral_end_procs) {
	link = ephemeral_end_procs;
	ephemeral_end_procs = link->next;
	rb_protect((VALUE(*)())link->func, link->data, &status);
	free(link);
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

    rb_global_variable((VALUE*)&top_scope);
    rb_global_variable((VALUE*)&ruby_eval_tree_begin);

    rb_global_variable((VALUE*)&ruby_eval_tree);
    rb_global_variable((VALUE*)&ruby_dyna_vars);

    rb_define_virtual_variable("$@", errat_getter, errat_setter);
    rb_define_hooked_variable("$!", &ruby_errinfo, 0, errinfo_setter);

    rb_define_global_function("eval", rb_f_eval, -1);
    rb_define_global_function("iterator?", rb_f_iterator_p, 0);
    rb_define_global_function("method_missing", rb_f_missing, -1);
    rb_define_global_function("loop", rb_f_loop, 0);

    rb_define_method(rb_mKernel, "respond_to?", rb_obj_respond_to, -1);

    rb_define_global_function("raise", rb_f_raise, -1);
    rb_define_global_function("fail", rb_f_raise, -1);

    rb_define_global_function("caller", rb_f_caller, -1);

    rb_define_global_function("exit", rb_f_exit, -1);
    rb_define_global_function("abort", rb_f_abort, 0);

    rb_define_global_function("at_exit", rb_f_at_exit, 0);

    rb_define_global_function("catch", rb_f_catch, 1);
    rb_define_global_function("throw", rb_f_throw, -1);
    rb_define_global_function("global_variables", rb_f_global_variables, 0);
    rb_define_global_function("local_variables", rb_f_local_variables, 0);

    rb_define_method(rb_mKernel, "send", rb_f_send, -1);
    rb_define_method(rb_mKernel, "__send__", rb_f_send, -1);
    rb_define_method(rb_mKernel, "instance_eval", rb_obj_instance_eval, -1);

    rb_define_private_method(rb_cModule, "append_features", rb_mod_append_features, 1);
    rb_define_private_method(rb_cModule, "extend_object", rb_mod_extend_object, 1);
    rb_define_private_method(rb_cModule, "include", rb_mod_include, -1);
    rb_define_private_method(rb_cModule, "public", rb_mod_public, -1);
    rb_define_private_method(rb_cModule, "protected", rb_mod_protected, -1);
    rb_define_private_method(rb_cModule, "private", rb_mod_private, -1);
    rb_define_private_method(rb_cModule, "module_function", rb_mod_modfunc, -1);
    rb_define_method(rb_cModule, "method_defined?", rb_mod_method_defined, 1);
    rb_define_method(rb_cModule, "public_class_method", rb_mod_public_method, -1);
    rb_define_method(rb_cModule, "private_class_method", rb_mod_private_method, -1);
    rb_define_method(rb_cModule, "module_eval", rb_mod_module_eval, -1);
    rb_define_method(rb_cModule, "class_eval", rb_mod_module_eval, -1);

    rb_undef_method(rb_cClass, "module_function");

    rb_define_private_method(rb_cModule, "remove_method", rb_mod_remove_method, 1);
    rb_define_private_method(rb_cModule, "undef_method", rb_mod_undef_method, 1);
    rb_define_private_method(rb_cModule, "alias_method", rb_mod_alias_method, 2);

    rb_define_singleton_method(rb_cModule, "nesting", rb_mod_nesting, 0);
    rb_define_singleton_method(rb_cModule, "constants", rb_mod_s_constants, 0);

    rb_define_singleton_method(ruby_top_self, "include", top_include, -1);
    rb_define_singleton_method(ruby_top_self, "public", top_public, -1);
    rb_define_singleton_method(ruby_top_self, "private", top_private, -1);

    rb_define_method(rb_mKernel, "extend", rb_obj_extend, -1);

    rb_define_global_function("trace_var", rb_f_trace_var, -1);
    rb_define_global_function("untrace_var", rb_f_untrace_var, -1);

    rb_define_global_function("set_trace_func", set_trace_func, 1);
    rb_global_variable(&trace_func);

    rb_define_virtual_variable("$SAFE", safe_getter, safe_setter);
}

VALUE rb_f_autoload();

void
Init_load()
{
    rb_load_path = rb_ary_new();
    rb_define_readonly_variable("$:", &rb_load_path);
    rb_define_readonly_variable("$-I", &rb_load_path);
    rb_define_readonly_variable("$LOAD_PATH", &rb_load_path);

    rb_features = rb_ary_new();
    rb_define_readonly_variable("$\"", &rb_features);

    rb_define_global_function("load", rb_f_load, -1);
    rb_define_global_function("require", rb_f_require, 1);
    rb_define_global_function("autoload", rb_f_autoload, 2);
    rb_global_variable(&ruby_wrapper);
}

static void
scope_dup(scope)
    struct SCOPE *scope;
{
    ID *tbl;
    VALUE *vars;

    if (scope->flag & SCOPE_MALLOC) return;

    if (scope->local_tbl) {
	tbl = scope->local_tbl;
	vars = ALLOC_N(VALUE, tbl[0]+1);
	*vars++ = scope->local_vars[-1];
	MEMCPY(vars, scope->local_vars, VALUE, tbl[0]);
	scope->local_vars = vars;
	scope->flag = SCOPE_MALLOC;
    }
    else {
        scope->flag = SCOPE_NOSTACK;
    }
}

static void
blk_mark(data)
    struct BLOCK *data;
{
    while (data) {
	rb_gc_mark_frame(&data->frame);
	rb_gc_mark(data->scope);
	rb_gc_mark(data->var);
	rb_gc_mark(data->body);
	rb_gc_mark(data->self);
	rb_gc_mark(data->d_vars);
	rb_gc_mark(data->klass);
	data = data->prev;
    }
}

static void
blk_free(data)
    struct BLOCK *data;
{
    struct FRAME *frame;
    void *tmp;

    frame = data->frame.prev;
    while (frame) {
	if (frame->argc > 0 && (frame->flags & FRAME_MALLOC))
	    free(frame->argv);
	tmp = frame;
	frame = frame->prev;
	free(tmp);
    }
    while (data) {
	if (data->frame.argc > 0)
	    free(data->frame.argv);
	tmp = data;
	data = data->prev;
	free(tmp);
    }
}

static void
blk_copy_prev(block)
    struct BLOCK *block;
{
    struct BLOCK *tmp;

    while (block->prev) {
	tmp = ALLOC_N(struct BLOCK, 1);
	MEMCPY(tmp, block->prev, struct BLOCK, 1);
	if (tmp->frame.argc > 0) {
	    tmp->frame.argv = ALLOC_N(VALUE, tmp->frame.argc);
	    MEMCPY(tmp->frame.argv, block->prev->frame.argv, VALUE, tmp->frame.argc);
	}
	scope_dup(tmp->scope);
	block->prev = tmp;
	block = tmp;
    }
}

static void
frame_dup(frame)
    struct FRAME *frame;
{
    VALUE *argv;
    struct FRAME *tmp;

    for (;;) {
	if (frame->argc > 0) {
	    argv = ALLOC_N(VALUE, frame->argc);
	    MEMCPY(argv, frame->argv, VALUE, frame->argc);
	    frame->argv = argv;
	    frame->flags = FRAME_MALLOC;
	}
	frame->tmp = 0;		/* should not preserve tmp */
	if (!frame->prev) break;
	tmp = ALLOC(struct FRAME);
	*tmp = *frame->prev;
	frame->prev = tmp;
	frame = tmp;
    }
}

static VALUE
bind_clone(self)
    VALUE self;
{
    struct BLOCK *orig, *data;
    VALUE bind;

    Data_Get_Struct(self, struct BLOCK, orig);
    bind = Data_Make_Struct(rb_cBinding,struct BLOCK,blk_mark,blk_free,data);
    CLONESETUP(bind,self);
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
rb_f_binding(self)
    VALUE self;
{
    struct BLOCK *data;
    VALUE bind;

    PUSH_BLOCK(0,0);
    bind = Data_Make_Struct(rb_cBinding,struct BLOCK,blk_mark,blk_free,data);
    *data = *ruby_block;

    data->orig_thread = rb_thread_current();
    data->iter = rb_f_iterator_p();
    frame_dup(&data->frame);
    if (ruby_frame->prev) {
	data->frame.last_func = ruby_frame->prev->last_func;
	data->frame.last_class = ruby_frame->prev->last_class;
    }

    if (data->iter) {
	blk_copy_prev(data);
    }
    else {
	data->prev = 0;
    }

    scope_dup(data->scope);
    POP_BLOCK();

    return bind;
}

#define PROC_T3    FL_USER1
#define PROC_T4    FL_USER2
#define PROC_T5    (FL_USER1|FL_USER2)
#define PROC_TMASK (FL_USER1|FL_USER2)

static void
proc_save_safe_level(data)
    VALUE data;
{
    if (FL_TEST(data, FL_TAINT)) {
	switch (safe_level) {
	  case 3:
	    FL_SET(data, PROC_T3);
	    break;
	  case 4:
	    FL_SET(data, PROC_T4);
	    break;
	  case 5:
	    FL_SET(data, PROC_T5);
	    break;
	}
    }
}

static void
proc_set_safe_level(data)
    VALUE data;
{
    if (FL_TEST(data, FL_TAINT)) {
	switch (RBASIC(data)->flags & PROC_TMASK) {
	  case PROC_T3:
	    safe_level = 3;
	    break;
	  case PROC_T4:
	    safe_level = 4;
	    break;
	  case PROC_T5:
	    safe_level = 5;
	    break;
	}
    }
}

static VALUE
proc_s_new(klass)
    VALUE klass;
{
    volatile VALUE proc;
    struct BLOCK *data;

    if (!rb_iterator_p() && !rb_f_iterator_p()) {
	rb_raise(rb_eArgError, "tried to create Procedure-Object out of iterator");
    }

    proc = Data_Make_Struct(klass, struct BLOCK, blk_mark, blk_free, data);
    *data = *ruby_block;

    data->orig_thread = rb_thread_current();
    data->iter = data->prev?Qtrue:Qfalse;
    data->tag = 0;		/* should not point into stack */
    frame_dup(&data->frame);
    if (data->iter) {
	blk_copy_prev(data);
    }
    else {
	data->prev = 0;
    }
    data->flags |= BLOCK_DYNAMIC;

    scope_dup(data->scope);
    proc_save_safe_level(proc);

    return proc;
}

VALUE
rb_f_lambda()
{
    return proc_s_new(rb_cProc);
}

static int
blk_orphan(data)
    struct BLOCK *data;
{
    if (data->scope && data->scope != top_scope &&
	(data->scope->flag & SCOPE_NOSTACK)) {
	return 1;
    }
    if (data->orig_thread != rb_thread_current()) {
	return 1;
    }
    return 0;
}

static VALUE
proc_call(proc, args)
    VALUE proc, args;		/* OK */
{
    struct BLOCK * volatile old_block;
    struct BLOCK _block;
    struct BLOCK *data;
    volatile VALUE result = Qnil;
    int state;
    volatile int orphan;
    volatile int safe = safe_level;

    Data_Get_Struct(proc, struct BLOCK, data);
    orphan = blk_orphan(data);

    /* PUSH BLOCK from data */
    old_block = ruby_block;
    _block = *data;
    ruby_block = &_block;
    PUSH_ITER(ITER_CUR);
    ruby_frame->iter = ITER_CUR;

    if (TYPE(args) == T_ARRAY) {
	switch (RARRAY(args)->len) {
	  case 0:
	    args = Qnil;
	    break;
	  case 1:
	    args = RARRAY(args)->ptr[0];
	    break;
	}
    }

    if (orphan) {/* orphan procedure */
	if (rb_iterator_p()) {
	    ruby_block->frame.iter = ITER_CUR;
	}
	else {
	    ruby_block->frame.iter = ITER_NOT;
	}
    }

    PUSH_TAG(PROT_NONE);
    _block.tag = prot_tag;
    state = EXEC_TAG();
    if (state == 0) {
	proc_set_safe_level(proc);
	result = rb_yield_0(args, 0, 0, Qtrue);
    }
    POP_TAG();

    POP_ITER();
    if (ruby_block->tag->dst == state) {
	state &= TAG_MASK;
    }
    ruby_block = old_block;
    safe_level = safe;

    if (state) {
	if (orphan) {/* orphan procedure */
	    switch (state) {
	      case TAG_BREAK:
		rb_raise(rb_eLocalJumpError, "break from proc-closure");
		break;
	      case TAG_RETRY:
		rb_raise(rb_eLocalJumpError, "retry from proc-closure");
		break;
	      case TAG_RETURN:
		rb_raise(rb_eLocalJumpError, "return from proc-closure");
		break;
	    }
	}
	JUMP_TAG(state);
    }
    return result;
}

static VALUE
proc_arity(proc)
    VALUE proc;
{
    struct BLOCK *data;
    NODE *list;
    int n;

    Data_Get_Struct(proc, struct BLOCK, data);
    if (data->var == 0) return INT2FIX(-1);
    switch (nd_type(data->var)) {
      default:
	return INT2FIX(-2);
      case NODE_MASGN:
	list = data->var->nd_head;
	n = 0;
	while (list) {
	    n++;
	    list = list->nd_next;
	}
	if (data->var->nd_args) return INT2FIX(-n-1);
	return INT2FIX(n);
    }
}

static VALUE
block_pass(self, node)
    VALUE self;
    NODE *node;
{
    VALUE block = rb_eval(self, node->nd_body);
    struct BLOCK * volatile old_block;
    struct BLOCK _block;
    struct BLOCK *data;
    volatile VALUE result = Qnil;
    int state;
    volatile int orphan;
    volatile int safe = safe_level;

    if (NIL_P(block)) {
	return rb_eval(self, node->nd_iter);
    }
    if (rb_obj_is_kind_of(block, rb_cMethod)) {
	block = method_proc(block);
    }
    else if (!rb_obj_is_proc(block)) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected Proc)",
		 rb_class2name(CLASS_OF(block)));
    }

    Data_Get_Struct(block, struct BLOCK, data);
    orphan = blk_orphan(data);

    /* PUSH BLOCK from data */
    old_block = ruby_block;
    _block = *data;
    ruby_block = &_block;
    PUSH_ITER(ITER_PRE);
    ruby_frame->iter = ITER_PRE;

    PUSH_TAG(PROT_NONE);
    _block.tag = prot_tag;
    state = EXEC_TAG();
    if (state == 0) {
	proc_set_safe_level(block);
	result = rb_eval(self, node->nd_iter);
    }
    POP_TAG();
    POP_ITER();
    if (_block.tag->dst == state) {
	if (orphan) {
	    state &= TAG_MASK;
	}
	else {
	    struct BLOCK *ptr = old_block;

	    while (ptr) {
		if (ptr->scope == _block.scope) {
		    ptr->tag->dst = state;
		    break;
		}
		ptr = ptr->prev;
	    }
	}
    }
    ruby_block = old_block;
    safe_level = safe;

    if (state) {
	switch (state) {
	  case TAG_BREAK:
	    rb_raise(rb_eLocalJumpError, "break from proc-closure");
	    break;
	  case TAG_RETRY:
	    rb_raise(rb_eLocalJumpError, "retry from proc-closure");
	    break;
	  case TAG_RETURN:
	    rb_raise(rb_eLocalJumpError, "return from proc-closure");
	    break;
	}
	JUMP_TAG(state);
    }
    return result;
}

struct METHOD {
    VALUE klass, oklass;
    VALUE recv;
    ID id, oid;
    NODE *body;
};

static void
bm_mark(data)
    struct METHOD *data;
{
    rb_gc_mark(data->oklass);
    rb_gc_mark(data->klass);
    rb_gc_mark(data->recv);
    rb_gc_mark(data->body);
}

static VALUE
rb_obj_method(obj, vid)
    VALUE obj;
    VALUE vid;
{
    VALUE method;
    VALUE klass = CLASS_OF(obj);
    ID id;
    NODE *body;
    int noex;
    struct METHOD *data;

    id = rb_to_id(vid);

  again:
    if ((body = rb_get_method_body(&klass, &id, &noex)) == 0) {
	return rb_undefined(obj, rb_to_id(vid), 0, 0, 0);
    }

    if (nd_type(body) == NODE_ZSUPER) {
	klass = RCLASS(klass)->super;
	goto again;
    }

    method = Data_Make_Struct(rb_cMethod, struct METHOD, bm_mark, free, data);
    data->klass = klass;
    data->recv = obj;
    data->id = id;
    data->body = body;
    data->oklass = CLASS_OF(obj);
    data->oid = rb_to_id(vid);
    if (FL_TEST(obj, FL_TAINT)) {
	FL_SET(method, FL_TAINT);
    }

    return method;
}

static VALUE
method_call(argc, argv, method)
    int argc;
    VALUE *argv;
    VALUE method;
{
    VALUE result;
    struct METHOD *data;
    int state;
    volatile int safe = safe_level;

    Data_Get_Struct(method, struct METHOD, data);
    PUSH_ITER(rb_iterator_p()?ITER_PRE:ITER_NOT);
    PUSH_TAG(PROT_NONE);
    if (FL_TEST(data->recv, FL_TAINT) || FL_TEST(method, FL_TAINT)) {
	FL_SET(method, FL_TAINT);
	if (safe_level < 4) safe_level = 4;
    }
    if ((state = EXEC_TAG()) == 0) {
	result = rb_call0(data->klass, data->recv, data->id,
			  argc, argv, data->body, 0);
    }
    POP_TAG();
    POP_ITER();
    safe_level = safe;
    if (state) JUMP_TAG(state);
    return result;
}

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
      default:
	body = body->nd_next;	/* skip NODE_SCOPE */
	if (nd_type(body) == NODE_BLOCK)
	    body = body->nd_head;
	if (!body) return INT2FIX(0);
	n = body->nd_cnt;
	if (body->nd_opt || body->nd_rest >= 0)
	    n = -n-1;
	return INT2FIX(n);
    }
}

static VALUE
method_inspect(method)
    VALUE method;
{
    struct METHOD *data;
    VALUE str;
    const char *s;

    Data_Get_Struct(method, struct METHOD, data);
    str = rb_str_new2("#<");
    s = rb_class2name(CLASS_OF(method));
    rb_str_cat(str, s, strlen(s));
    rb_str_cat(str, ": ", 2);
    s = rb_class2name(data->oklass);
    rb_str_cat(str, s, strlen(s));
    rb_str_cat(str, "#", 1);
    s = rb_id2name(data->oid);
    rb_str_cat(str, s, strlen(s));
    rb_str_cat(str, ">", 1);

    return str;
}

static VALUE
mproc()
{
    VALUE proc;

    /* emulate ruby's method call */
    PUSH_ITER(ITER_CUR);
    PUSH_FRAME();
    proc = rb_f_lambda();
    POP_FRAME();
    POP_ITER();

    return proc;
}

static VALUE
mcall(args, method)
    VALUE args, method;
{
    if (NIL_P(args)) {
	return method_call(0, 0, method);
    }
    if (TYPE(args) == T_ARRAY) {
	return method_call(RARRAY(args)->len, RARRAY(args)->ptr, method);
    }
    return method_call(1, &args, method);
}

static VALUE
method_proc(method)
    VALUE method;
{
    return rb_iterate(mproc, 0, mcall, method);
}

void
Init_Proc()
{
    rb_eLocalJumpError = rb_define_class("LocalJumpError", rb_eStandardError);
    rb_eSysStackError = rb_define_class("SystemStackError", rb_eStandardError);

    rb_cProc = rb_define_class("Proc", rb_cObject);
    rb_define_singleton_method(rb_cProc, "new", proc_s_new, 0);

    rb_define_method(rb_cProc, "call", proc_call, -2);
    rb_define_method(rb_cProc, "arity", proc_arity, 0);
    rb_define_method(rb_cProc, "[]", proc_call, -2);
    rb_define_global_function("proc", rb_f_lambda, 0);
    rb_define_global_function("lambda", rb_f_lambda, 0);
    rb_define_global_function("binding", rb_f_binding, 0);
    rb_cBinding = rb_define_class("Binding", rb_cObject);
    rb_undef_method(CLASS_OF(rb_cBinding), "new");
    rb_define_method(rb_cBinding, "clone", bind_clone, 0);

    rb_cMethod = rb_define_class("Method", rb_cObject);
    rb_undef_method(CLASS_OF(rb_cMethod), "new");
    rb_define_method(rb_cMethod, "call", method_call, -1);
    rb_define_method(rb_cMethod, "[]", method_call, -1);
    rb_define_method(rb_cMethod, "arity", method_arity, 0);
    rb_define_method(rb_cMethod, "inspect", method_inspect, 0);
    rb_define_method(rb_cMethod, "to_s", method_inspect, 0);
    rb_define_method(rb_cMethod, "to_proc", method_proc, 0);
    rb_define_method(rb_mKernel, "method", rb_obj_method, 1);
}

static VALUE rb_eThreadError;

int rb_thread_pending = 0;

VALUE rb_cThread;

#include <sys/types.h>
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
#ifndef NT
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif /* NT */
#endif
#include <signal.h>
#include <errno.h>

#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif

extern VALUE rb_last_status;

enum thread_status {
    THREAD_RUNNABLE,
    THREAD_STOPPED,
    THREAD_TO_KILL,
    THREAD_KILLED,
};

#define WAIT_FD		(1<<0)
#define WAIT_TIME	(1<<1)
#define WAIT_JOIN	(1<<2)

/* +infty, for this purpose */
#define DELAY_INFTY 1E30

typedef struct thread * rb_thread_t;

struct thread {
    struct thread *next, *prev;
    jmp_buf context;

    VALUE result;

    int   stk_len;
    int   stk_max;
    VALUE*stk_ptr;
    VALUE*stk_pos;

    struct FRAME *frame;
    struct SCOPE *scope;
    struct RVarmap *dyna_vars;
    struct BLOCK *block;
    struct iter *iter;
    struct tag *tag;
    VALUE klass;
    VALUE wrapper;

    int flags;		/* misc. states (vmode/rb_trap_immediate/raised) */

    char *file;
    int   line;

    VALUE errinfo;
    VALUE last_status;
    VALUE last_line;
    VALUE last_match;

    int safe;

    enum thread_status status;
    int wait_for;
    int fd;
    double delay;
    rb_thread_t join;

    int abort;

    st_table *locals;

    VALUE thread;
};

#define THREAD_RAISED 0x200

static rb_thread_t main_thread;
static rb_thread_t curr_thread = 0;

static int num_waiting_on_fd = 0;
static int num_waiting_on_timer = 0;
static int num_waiting_on_join = 0;

#define FOREACH_THREAD_FROM(f,x) x = f; do { x = x->next;
#define END_FOREACH_FROM(f,x) } while (x != f)

#define FOREACH_THREAD(x) FOREACH_THREAD_FROM(curr_thread,x)
#define END_FOREACH(x)    END_FOREACH_FROM(curr_thread,x)

/* Return the current time as a floating-point number */
static double
timeofday()
{
    struct timeval tv;
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

    rb_gc_mark(th->scope);
    rb_gc_mark(th->dyna_vars);
    rb_gc_mark(th->errinfo);
    rb_gc_mark(th->last_line);
    rb_gc_mark(th->last_match);
    rb_mark_tbl(th->locals);

    /* mark data in copied stack */
    if (th == curr_thread) return;
    if (th->status == THREAD_KILLED) return;
    if (th->stk_len == 0) return;  /* stack not active, no need to mark. */
    if (th->stk_ptr) {
	rb_gc_mark_locations(th->stk_ptr, th->stk_ptr+th->stk_len);
#if defined(THINK_C) || defined(__human68k__)
	rb_gc_mark_locations(th->stk_ptr+2, th->stk_ptr+th->stk_len+2);
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

void
rb_gc_mark_threads()
{
    rb_thread_t th;

    if (!curr_thread) return;
    FOREACH_THREAD(th) {
	rb_gc_mark(th->thread);
    } END_FOREACH(th);
}

static void
thread_free(th)
    rb_thread_t th;
{
    if (th->stk_ptr) free(th->stk_ptr);
    th->stk_ptr = 0;
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
    if (TYPE(data) != T_DATA || RDATA(data)->dfree != thread_free) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected Thread)",
		 rb_class2name(CLASS_OF(data)));
    }
    return (rb_thread_t)RDATA(data)->data;
}

static int   th_raise_argc;
static VALUE th_raise_argv[2];
static char *th_raise_file;
static int   th_raise_line;
static VALUE th_cmd;
static int   th_sig;
static char *th_signm;

#define RESTORE_NORMAL		1
#define RESTORE_FATAL		2
#define RESTORE_INTERRUPT	3
#define RESTORE_TRAP		4
#define RESTORE_RAISE		5
#define RESTORE_SIGNAL		6

static void
rb_thread_save_context(th)
    rb_thread_t th;
{
    VALUE v;

    int len = stack_length();
    th->stk_len = 0;
    th->stk_pos = (rb_gc_stack_start<(VALUE*)&v)?rb_gc_stack_start
				                :rb_gc_stack_start - len;
    if (len > th->stk_max)  {
	REALLOC_N(th->stk_ptr, VALUE, len);
	th->stk_max = len;
    }
    th->stk_len = len;
    FLUSH_REGISTER_WINDOWS; 
    MEMCPY(th->stk_ptr, th->stk_pos, VALUE, th->stk_len);

    th->frame = ruby_frame;
    th->scope = ruby_scope;
    th->klass = ruby_class;
    th->wrapper = ruby_wrapper;
    th->dyna_vars = ruby_dyna_vars;
    th->block = ruby_block;
    th->flags = scope_vmode | (rb_trap_immediate<<8);
    th->iter = ruby_iter;
    th->tag = prot_tag;
    th->errinfo = ruby_errinfo;
    th->last_status = rb_last_status;
    th->last_line = rb_lastline_get();
    th->last_match = rb_backref_get();
    th->safe = safe_level;

    th->file = ruby_sourcefile;
    th->line = ruby_sourceline;
}

static int
thread_switch(n)
    int n;
{
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
	rb_trap_eval(th_cmd, th_sig);
	errno = EINTR;
	break;
      case RESTORE_RAISE:
	ruby_frame->last_func = 0;
	ruby_sourcefile = th_raise_file;
	ruby_sourceline = th_raise_line;
	rb_f_raise(th_raise_argc, th_raise_argv);
	break;
      case RESTORE_SIGNAL:
	rb_raise(rb_eSignal, "SIG%s", th_signm);
	break;
      case RESTORE_NORMAL:
      default:
	return 1;
    }
}

#define THREAD_SAVE_CONTEXT(th) \
    (rb_thread_save_context(th),thread_switch(setjmp((th)->context)))

static void rb_thread_restore_context _((rb_thread_t,int));

static void
stack_extend(th, exit)
    rb_thread_t th;
    int exit;
{
    VALUE space[1024];

    memset(space, 0, 1);	/* prevent array from optimization */
    rb_thread_restore_context(th, exit);
}

static void
rb_thread_restore_context(th, exit)
    rb_thread_t th;
    int exit;
{
    VALUE v;
    static rb_thread_t tmp;
    static int ex;

    if (!th->stk_ptr) rb_bug("unsaved context");

    if (&v < rb_gc_stack_start) {
	/* Stack grows downward */
	if (&v > th->stk_pos) stack_extend(th, exit);
    }
    else {
	/* Stack grows upward */
	if (&v < th->stk_pos + th->stk_len) stack_extend(th, exit);
    }

    ruby_frame = th->frame;
    ruby_scope = th->scope;
    ruby_class = th->klass;
    ruby_wrapper = th->wrapper;
    ruby_dyna_vars = th->dyna_vars;
    ruby_block = th->block;
    scope_vmode = th->flags&SCOPE_MASK;
    rb_trap_immediate = (th->flags&0x100)?1:0;
    ruby_iter = th->iter;
    prot_tag = th->tag;
    ruby_errinfo = th->errinfo;
    rb_last_status = th->last_status;
    safe_level = th->safe;

    ruby_sourcefile = th->file;
    ruby_sourceline = th->line;

    tmp = th;
    ex = exit;
    FLUSH_REGISTER_WINDOWS;
    MEMCPY(tmp->stk_pos, tmp->stk_ptr, VALUE, tmp->stk_len);

    rb_lastline_set(tmp->last_line);
    rb_backref_set(tmp->last_match);

    longjmp(tmp->context, ex);
}

static void
rb_thread_ready(th)
    rb_thread_t th;
{
    /* The thread is no longer waiting on anything */
    if (th->wait_for & WAIT_FD) {
	num_waiting_on_fd--;
    }
    if (th->wait_for & WAIT_TIME) {
	num_waiting_on_timer--;
    }
    if (th->wait_for & WAIT_JOIN) {
	num_waiting_on_join--;
    }
    th->wait_for = 0;
    th->status = THREAD_RUNNABLE;
}

static void
rb_thread_remove()
{
    rb_thread_ready(curr_thread);
    curr_thread->status = THREAD_KILLED;
    curr_thread->prev->next = curr_thread->next;
    curr_thread->next->prev = curr_thread->prev;
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
	if ((th->wait_for & WAIT_FD) && th->fd == fd) {
	    th_raise_argc = 1;
	    th_raise_argv[0] = rb_exc_new2(rb_eIOError, "stream closed");
	    th_raise_file = ruby_sourcefile;
	    th_raise_line = ruby_sourceline;
	    curr_thread = th;
	    rb_thread_ready(th);
	    rb_thread_restore_context(curr_thread, RESTORE_RAISE);
	}
    }
    END_FOREACH(th);
}

static void
rb_thread_deadlock()
{
#if 1
    curr_thread = main_thread;
    th_raise_argc = 1;
    th_raise_argv[0] = rb_exc_new2(rb_eFatal, "Thread: deadlock");
    th_raise_file = ruby_sourcefile;
    th_raise_line = ruby_sourceline;
    rb_thread_restore_context(main_thread, RESTORE_RAISE);
#else
    static int invoked = 0;

    if (invoked) return;
    invoked = 1;
    rb_prohibit_interrupt = 1;
    ruby_errinfo = rb_exc_new2(rb_eFatal, "Thread: deadlock");
    set_backtrace(ruby_errinfo, make_backtrace());
    rb_abort();
#endif
}

void
rb_thread_schedule()
{
    rb_thread_t next;		/* OK */
    rb_thread_t th;
    rb_thread_t curr;

  select_err:
    rb_thread_pending = 0;
    if (curr_thread == curr_thread->next
	&& curr_thread->status == THREAD_RUNNABLE)
	return;

    next = 0;
    curr = curr_thread;		/* starting thread */

    while (curr->status == THREAD_KILLED) {
	curr = curr->prev;
    }

    FOREACH_THREAD_FROM(curr, th) {
       if (th->status != THREAD_STOPPED && th->status != THREAD_KILLED) {
           next = th;
           break;
       }
    }
    END_FOREACH_FROM(curr, th); 

    if (num_waiting_on_join) {
	FOREACH_THREAD_FROM(curr, th) {
	    if ((th->wait_for&WAIT_JOIN) && rb_thread_dead(th->join)) {
		th->join = 0;
		th->wait_for &= ~WAIT_JOIN;
		th->status = THREAD_RUNNABLE;
		num_waiting_on_join--;
		if (!next) next = th;
	    }
	}
	END_FOREACH_FROM(curr, th);
    }

    if (num_waiting_on_fd > 0 || num_waiting_on_timer > 0) {
	fd_set readfds;
	struct timeval delay_tv, *delay_ptr;
	double delay, now;	/* OK */
	int n, max;

	do {
	    max = 0;
	    FD_ZERO(&readfds);
	    if (num_waiting_on_fd > 0) {
		FOREACH_THREAD_FROM(curr, th) {
		    if (th->wait_for & WAIT_FD) {
			FD_SET(th->fd, &readfds);
			if (th->fd > max) max = th->fd;
		    }
		}
		END_FOREACH_FROM(curr, th);
	    }

	    delay = DELAY_INFTY;
	    if (num_waiting_on_timer > 0) {
		now = timeofday();
		FOREACH_THREAD_FROM(curr, th) {
		    if (th->wait_for & WAIT_TIME) {
			if (th->delay <= now) {
			    th->delay = 0.0;
			    th->wait_for &= ~WAIT_TIME;
			    th->status = THREAD_RUNNABLE;
			    num_waiting_on_timer--;
			    if (!next) next = th;
			} else if (th->delay < delay) {
			    delay = th->delay;
			}
		    }
		}
		END_FOREACH_FROM(curr, th);
	    }
	    /* Do the select if needed */
	    if (num_waiting_on_fd > 0 || !next) {
		/* Convert delay to a timeval */
		/* If a thread is runnable, just poll */
		if (next) {
		    delay_tv.tv_sec = 0;
		    delay_tv.tv_usec = 0;
		    delay_ptr = &delay_tv;
		}
		else if (delay == DELAY_INFTY) {
		    delay_ptr = 0;
		}
		else {
		    delay -= now;
		    delay_tv.tv_sec = (unsigned int)delay;
		    delay_tv.tv_usec = (long)((delay-(double)delay_tv.tv_sec)*1e6);
		    delay_ptr = &delay_tv;
		}

		n = select(max+1, &readfds, 0, 0, delay_ptr);
		if (n < 0) {
		    if (rb_trap_pending) rb_trap_exec();
		    switch (errno) {
		      case EBADF:
		      case ENOMEM:
			n = 0;
			break;
		      default:
			goto select_err;
		    }
		}
		if (n > 0) {
		    /* Some descriptors are ready. 
		       Make the corresponding threads runnable. */
		    FOREACH_THREAD_FROM(curr, th) {
			if ((th->wait_for&WAIT_FD)
			    && FD_ISSET(th->fd, &readfds)) {
			    /* Wake up only one thread per fd. */
			    FD_CLR(th->fd, &readfds);
			    th->status = THREAD_RUNNABLE;
			    th->fd = 0;
			    th->wait_for &= ~WAIT_FD;
			    num_waiting_on_fd--;
			    if (!next) next = th; /* Found one. */
			}
		    }
		    END_FOREACH_FROM(curr, th);
		}
	    }
	    /* The delays for some of the threads should have expired.
	       Go through the loop once more, to check the delays. */
	} while (!next && delay != DELAY_INFTY);
    }

    if (!next) {
	curr_thread->file = ruby_sourcefile;
	curr_thread->line = ruby_sourceline;
	FOREACH_THREAD_FROM(curr, th) {
	    fprintf(stderr, "%s:%d:deadlock 0x%lx: %d:%d %s\n", 
		    th->file, th->line, th->thread, th->status,
		    th->wait_for, th==main_thread?"(main)":"");
	    if (th->status == THREAD_STOPPED) {
		next = th;
	    }
	}
	END_FOREACH_FROM(curr, th);
	/* raise fatal error to main thread */
	rb_thread_deadlock();
	rb_thread_ready(next);
	next->status = THREAD_TO_KILL;
    }
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
	/* execute ensure-clause if any */
	rb_thread_restore_context(next, RESTORE_FATAL);
    }
    rb_thread_restore_context(next, RESTORE_NORMAL);
}

void
rb_thread_wait_fd(fd)
    int fd;
{
    if (curr_thread == curr_thread->next) return;

    curr_thread->status = THREAD_STOPPED;
    curr_thread->fd = fd;
    num_waiting_on_fd++;
    curr_thread->wait_for |= WAIT_FD;
    rb_thread_schedule();
}

int
rb_thread_fd_writable(fd)
    int fd;
{
    struct timeval zero;
    fd_set fds;

    if (curr_thread == curr_thread->next) return 1;

    zero.tv_sec = zero.tv_usec = 0;
    for (;;) {
	FD_ZERO(&fds);
	FD_SET(fd, &fds);
	if (select(fd+1, 0, &fds, 0, &zero) == 1) return 0;
	rb_thread_schedule();
    }
}

void
rb_thread_wait_for(time)
    struct timeval time;
{
    double date;

    if (curr_thread == curr_thread->next) {
	int n;
#ifndef linux
	double d, limit;
	limit = timeofday()+(double)time.tv_sec+(double)time.tv_usec*1e-6;
#endif
	for (;;) {
	    TRAP_BEG;
	    n = select(0, 0, 0, 0, &time);
	    TRAP_END;
	    if (n == 0) return;

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
    num_waiting_on_timer++;
    curr_thread->wait_for |= WAIT_TIME;
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
    double limit;
    struct timeval zero;
    fd_set r, *rp, w, *wp, x, *xp;
    int n;

    if (!read && !write && !except) {
	if (!timeout) {
	    rb_thread_sleep_forever();
	    return 0;
	}
	rb_thread_wait_for(*timeout);
	return 0;
    }

    if (timeout) {
	limit = timeofday()+
	    (double)timeout->tv_sec+(double)timeout->tv_usec*1e-6;
    }

    if (curr_thread == curr_thread->next) { /* no other thread */
#ifndef linux
	struct timeval tv, *tvp = timeout;

	if (timeout) {
	    tv = *timeout;
	    tvp = &tv;
	}
	for (;;) {
	    TRAP_BEG;
	    n = select(max, read, write, except, tvp);
	    TRAP_END;
	    if (n < 0 && errno == EINTR) {
		if (timeout) {
		    double d = timeofday() - limit;

		    tv.tv_sec = (unsigned int)d;
		    tv.tv_usec = (long)((d-(double)tv.tv_sec)*1e6);
		}
		continue;
	    }
	    return n;
	}
#else
	for (;;) {
	    TRAP_BEG;
	    n = select(max, read, write, except, timeout);
	    TRAP_END;
	    if (n < 0 && errno == EINTR) {
		continue;
	    }
	    return n;
	}
#endif

    }

    for (;;) {
	zero.tv_sec = zero.tv_usec = 0;
	if (read) {rp = &r; r = *read;} else {rp = 0;}
	if (write) {wp = &w; w = *write;} else {wp = 0;}
	if (except) {xp = &x; x = *except;} else {xp = 0;}
	n = select(max, rp, wp, xp, &zero);
	if (n > 0) {
	    /* write back fds */
	    if (read) {*read = r;}
	    if (write) {*write = w;}
	    if (except) {*except = x;}
	    return n;
	}
	if (n < 0 && errno != EINTR) {
	    return n;
	}
	if (timeout) {
	    if (timeout->tv_sec == 0 && timeout->tv_usec == 0) return 0;
	    if (limit <= timeofday()) return 0;
	}

        rb_thread_schedule();
	CHECK_INTS;
    }
}

static VALUE
rb_thread_join(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (!rb_thread_dead(th)) {
	if (th == curr_thread)
	    rb_raise(rb_eThreadError, "recursive join");
	if ((th->wait_for & WAIT_JOIN) && th->join == curr_thread)
	    rb_raise(rb_eThreadError, "Thread#join: deadlock - mutual join");
	curr_thread->status = THREAD_STOPPED;
	curr_thread->join = th;
	num_waiting_on_join++;
	curr_thread->wait_for |= WAIT_JOIN;
	rb_thread_schedule();
    }

    if (!NIL_P(th->errinfo) && (th->flags & THREAD_RAISED)) {
	VALUE oldbt = get_backtrace(th->errinfo);
	VALUE errat = make_backtrace();

	if (TYPE(oldbt) == T_ARRAY && RARRAY(oldbt)->len > 0) {
	    rb_ary_unshift(errat, rb_ary_entry(oldbt, 0));
	}
	set_backtrace(th->errinfo, errat);
	rb_exc_raise(th->errinfo);
    }

    return thread;
}

static VALUE
rb_thread_s_join(dmy, thread)	/* will be removed in 1.4 */
    VALUE dmy;
    VALUE thread;
{
    rb_warn("Thread::join is obsolete; use Thread#join instead");
    return rb_thread_join(thread);
}

VALUE
rb_thread_current()
{
    return curr_thread->thread;
}

VALUE
rb_thread_main()
{
    return main_thread->thread;
}

VALUE
rb_thread_wakeup(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (th->status == THREAD_KILLED)
	rb_raise(rb_eThreadError, "killed thread");
    rb_thread_ready(th);

    return thread;
}

VALUE
rb_thread_run(thread)
    VALUE thread;
{
    rb_thread_wakeup(thread);
    if (!rb_thread_critical) rb_thread_schedule();

    return thread;
}

static VALUE
rb_thread_kill(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (th->status == THREAD_TO_KILL || th->status == THREAD_KILLED)
	return thread; 
    if (th == th->next || th == main_thread) rb_exit(0);

    rb_thread_ready(th);
    th->status = THREAD_TO_KILL;
    rb_thread_schedule();
    return Qnil;		/* not reached */
}

static VALUE
rb_thread_s_kill(obj, th)
    VALUE obj, th;
{
    return rb_thread_kill(th);
}

static VALUE
rb_thread_exit()
{
    return rb_thread_kill(curr_thread->thread);
}

static VALUE
rb_thread_pass()
{
    rb_thread_schedule();
    return Qnil;
}

VALUE
rb_thread_stop()
{
    rb_thread_critical = 0;
    if (curr_thread == curr_thread->next) {
	rb_raise(rb_eThreadError, "stopping only thread");
    }
    curr_thread->status = THREAD_STOPPED;
    rb_thread_schedule();

    return Qnil;
}

struct timeval rb_time_timeval();

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
    if (curr_thread == curr_thread->next) {
	TRAP_BEG;
	sleep((32767L<<16)+32767);
	TRAP_END;
	return;
    }

    num_waiting_on_timer++;
    curr_thread->delay = DELAY_INFTY;
    curr_thread->wait_for |= WAIT_TIME;
    curr_thread->status = THREAD_STOPPED;
    rb_thread_schedule();
}

static int thread_abort;

static VALUE
rb_thread_s_abort_exc()
{
    return thread_abort?Qtrue:Qfalse;
}

static VALUE
rb_thread_s_abort_exc_set(self, val)
    VALUE self, val;
{
    thread_abort = RTEST(val);
    return val;
}

static VALUE
rb_thread_abort_exc(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    return th->abort?Qtrue:Qfalse;
}

static VALUE
rb_thread_abort_exc_set(thread, val)
    VALUE thread, val;
{
    rb_thread_t th = rb_thread_check(thread);

    th->abort = RTEST(val);
    return val;
}

#define THREAD_ALLOC(th) do {\
    th = ALLOC(struct thread);\
\
    th->status = 0;\
    th->result = 0;\
    th->errinfo = Qnil;\
\
    th->stk_ptr = 0;\
    th->stk_len = 0;\
    th->stk_max = 0;\
    th->wait_for = 0;\
    th->fd = 0;\
    th->delay = 0.0;\
    th->join = 0;\
\
    th->frame = 0;\
    th->scope = 0;\
    th->klass = 0;\
    th->wrapper = 0;\
    th->dyna_vars = 0;\
    th->block = 0;\
    th->iter = 0;\
    th->tag = 0;\
    th->errinfo = 0;\
    th->last_status = 0;\
    th->last_line = 0;\
    th->last_match = 0;\
    th->abort = 0;\
    th->locals = 0;\
} while(0)

static rb_thread_t
rb_thread_alloc(klass)
    VALUE klass;
{
    rb_thread_t th;

    THREAD_ALLOC(th);
    th->thread = Data_Wrap_Struct(klass, thread_mark, thread_free, th);

    if (curr_thread) {
	th->prev = curr_thread;
	curr_thread->next->prev = th;
	th->next = curr_thread->next;
	curr_thread->next = th;
    }
    else {
	curr_thread = th->prev = th->next = th;
	th->status = THREAD_RUNNABLE;
    }

    return th;
}

#if defined(HAVE_SETITIMER) && !defined(__BOW__)
static void
catch_timer(sig)
    int sig;
{
#if !defined(POSIX_SIGNAL) && !defined(BSD_SIGNAL)
    signal(sig, catch_timer);
#endif
    if (!rb_thread_critical) {
	if (rb_trap_immediate) {
	    rb_thread_schedule();
	}
	else rb_thread_pending = 1;
    }
}
#else
int rb_thread_tick = THREAD_TICK;
#endif

static VALUE rb_thread_raise _((int, VALUE*, VALUE));

#define SCOPE_SHARED  FL_USER1

#if defined(HAVE_SETITIMER) && !defined(__BOW__)
static int thread_init = 0;

void
rb_thread_start_timer()
{
    struct itimerval tval;

    if (!thread_init) return;
    tval.it_interval.tv_sec = 0;
    tval.it_interval.tv_usec = 50000;
    tval.it_value = tval.it_interval;
    setitimer(ITIMER_VIRTUAL, &tval, NULL);
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
}
#endif

static VALUE
rb_thread_create_0(fn, arg, klass)
    VALUE (*fn)();
    void *arg;
    VALUE klass;
{
    rb_thread_t th = rb_thread_alloc(klass);
    volatile VALUE thread = th->thread;
    enum thread_status status;
    int state;

#if defined(HAVE_SETITIMER) && !defined(__BOW__)
    if (!thread_init) {
#ifdef POSIX_SIGNAL
	posix_signal(SIGVTALRM, catch_timer);
#else
	signal(SIGVTALRM, catch_timer);
#endif

	thread_init = 1;
	rb_thread_start_timer();
    }
#endif

    if (ruby_block) {
	blk_copy_prev(ruby_block);
    }
    FL_SET(ruby_scope, SCOPE_SHARED);
    if (THREAD_SAVE_CONTEXT(curr_thread)) {
	return thread;
    }

    PUSH_TAG(PROT_THREAD);
    if ((state = EXEC_TAG()) == 0) {
	if (THREAD_SAVE_CONTEXT(th) == 0) {
	    curr_thread = th;
	    th->result = (*fn)(arg, th);
	}
    }
    POP_TAG();
    status = th->status;
    rb_thread_remove();
    if (state && status != THREAD_TO_KILL && !NIL_P(ruby_errinfo)) {
	th->flags |= THREAD_RAISED;
	if (state == TAG_FATAL) { 
	    /* fatal error within this thread, need to stop whole script */
	    main_thread->errinfo = ruby_errinfo;
	    rb_thread_cleanup();
	}
	else if (rb_obj_is_kind_of(ruby_errinfo, rb_eSystemExit)) {
	    /* delegate exception to main_thread */
	    rb_thread_raise(1, &ruby_errinfo, main_thread->thread);
	}
	else if (thread_abort || th->abort || RTEST(ruby_debug)) {
	    VALUE err = rb_exc_new(rb_eSystemExit, 0, 0);
	    error_print();
	    /* exit on main_thread */
	    rb_thread_raise(1, &err, main_thread->thread);
	}
	else {
	    th->errinfo = ruby_errinfo;
	}
    }
    rb_thread_schedule();
    return 0;			/* not reached */
}

VALUE
rb_thread_create(fn, arg)
    VALUE (*fn)();
    void *arg;
{
    return rb_thread_create_0(fn, arg, rb_cThread);
}

int
rb_thread_scope_shared_p()
{
    return FL_TEST(ruby_scope, SCOPE_SHARED);
}

static VALUE
rb_thread_yield(arg, th) 
    int arg;
    rb_thread_t th;
{
    scope_dup(ruby_block->scope);
    return rb_yield_0(th->thread, 0, 0, Qfalse);
}

static VALUE
rb_thread_start(klass)
    VALUE klass;
{
    if (!rb_iterator_p()) {
	rb_raise(rb_eThreadError, "must be called as iterator");
    }
    return rb_thread_create_0(rb_thread_yield, 0, klass);
}

static VALUE
rb_thread_value(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    rb_thread_join(thread);

    return th->result;
}

static VALUE
rb_thread_status(thread)
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (rb_thread_dead(th)) {
	if (!NIL_P(th->errinfo) && (th->flags & THREAD_RAISED))
	    return Qnil;
	return Qfalse;
    }

    return Qtrue;
}

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
    /* wait other threads to terminate */
    while (curr_thread != curr_thread->next) {
	rb_thread_schedule();
    }
}

static void
rb_thread_cleanup()
{
    rb_thread_t th;

    if (curr_thread != curr_thread->next->prev) {
	curr_thread = curr_thread->prev;
    }

    FOREACH_THREAD(th) {
	if (th != curr_thread && th->status != THREAD_KILLED) {
	    rb_thread_ready(th);
	    th->status = THREAD_TO_KILL;
	}
    }
    END_FOREACH(th);
}

int rb_thread_critical;

static VALUE
rb_thread_get_critical()
{
    return rb_thread_critical?Qtrue:Qfalse;
}

static VALUE
rb_thread_set_critical(obj, val)
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
    if (THREAD_SAVE_CONTEXT(curr_thread)) {
	return;
    }
    curr_thread = main_thread;
    rb_thread_restore_context(curr_thread, RESTORE_INTERRUPT);
}

void
rb_thread_signal_raise(sig)
    char *sig;
{
    if (sig == 0) return;	/* should not happen */
    rb_thread_critical = 0;
    if (curr_thread == main_thread) {
	rb_thread_ready(curr_thread);
	rb_raise(rb_eSignal, "SIG%s", sig);
    }
    rb_thread_ready(main_thread);
    if (THREAD_SAVE_CONTEXT(curr_thread)) {
	return;
    }
    th_signm = sig;
    curr_thread = main_thread;
    rb_thread_restore_context(curr_thread, RESTORE_SIGNAL);
}

void
rb_thread_trap_eval(cmd, sig)
    VALUE cmd;
    int sig;
{
    rb_thread_critical = 0;
    if (!rb_thread_dead(curr_thread)) {
	rb_thread_ready(curr_thread);
	rb_trap_eval(cmd, sig);
	return;
    }
    rb_thread_ready(main_thread);
    if (THREAD_SAVE_CONTEXT(curr_thread)) {
	return;
    }
    th_cmd = cmd;
    th_sig = sig;
    curr_thread = main_thread;
    rb_thread_restore_context(curr_thread, RESTORE_TRAP);
}

static VALUE
rb_thread_raise(argc, argv, thread)
    int argc;
    VALUE *argv;
    VALUE thread;
{
    rb_thread_t th = rb_thread_check(thread);

    if (rb_thread_dead(th)) return thread;
    if (curr_thread == th) {
	rb_f_raise(argc, argv);
    }

    if (curr_thread->status != THREAD_KILLED)
	rb_thread_save_context(curr_thread);
    if (thread_switch(setjmp(curr_thread->context))) {
	return thread;
    }

    rb_scan_args(argc, argv, "11", &th_raise_argv[0], &th_raise_argv[1]);
    rb_thread_ready(th);
    curr_thread = th;

    th_raise_argc = argc;
    th_raise_file = ruby_sourcefile;
    th_raise_line = ruby_sourceline;
    rb_thread_restore_context(curr_thread, RESTORE_RAISE);
    return Qnil;		/* not reached */
}

static st_table *loading_tbl;

static int
rb_thread_loading(feature)
    const char *feature;
{
    if (!loading_tbl) {
	loading_tbl = st_init_strtable();
    }
    if (!rb_provided(feature)) {
	st_insert(loading_tbl, feature, 0);
	return Qfalse; /* need to load */
    }
    while (st_lookup(loading_tbl, feature, 0)) {
	CHECK_INTS;
	rb_thread_schedule();
    }
    return Qtrue;
}

static void
rb_thread_loading_done(feature)
    const char *feature;
{
    if (loading_tbl) {
	st_delete(loading_tbl, &feature, 0);
    }
}

VALUE
rb_thread_local_aref(thread, id)
    VALUE thread;
    ID id;
{
    rb_thread_t th;
    VALUE val;

    th = rb_thread_check(thread);
    if (!th->locals) return Qnil;
    if (st_lookup(th->locals, id, &val)) {
	return val;
    }
    return Qnil;
}

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

    if (safe_level >= 4 && !FL_TEST(thread, FL_TAINT))
	rb_raise(rb_eSecurityError, "Insecure: can't modify thread values");

    if (!th->locals) {
	th->locals = st_init_numtable();
    }
    if (NIL_P(val)) {
	st_delete(th->locals, &id, 0);
	return Qnil;
    }
    st_insert(th->locals, id, val);

    return val;
}

static VALUE
rb_thread_aset(thread, id, val)
    VALUE thread, id, val;
{
    return rb_thread_local_aset(thread, rb_to_id(id), val);
}

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

static VALUE rb_cContinuation;

static VALUE
rb_callcc(self)
    VALUE self;
{
    volatile VALUE cont;
    rb_thread_t th;
    struct tag *tag;

    THREAD_ALLOC(th);
    th->thread = cont = Data_Wrap_Struct(rb_cContinuation, thread_mark,
					 thread_free, th);

    FL_SET(ruby_scope, SCOPE_DONT_RECYCLE);
    for (tag=prot_tag; tag; tag=tag->prev) {
	scope_dup(tag->scope);
    }
    th->prev = 0;
    th->next = curr_thread;
    if (THREAD_SAVE_CONTEXT(th)) {
	return th->result;
    }
    else {
	return rb_yield(th->thread);
    }
}

static VALUE
rb_continuation_call(argc, argv, cont)
    int argc;
    VALUE *argv;
    VALUE cont;
{
    rb_thread_t th = rb_thread_check(cont);

    if (th->next != curr_thread) {
	rb_raise(rb_eRuntimeError, "continuation called across threads");
    }
    switch (argc) {
    case 0:
	th->result = Qnil;
	break;
    case 1:
	th->result = *argv;
	break;
    default:
	th->result = rb_ary_new4(argc, argv);
	break;
    }
    rb_thread_restore_context(th, RESTORE_NORMAL);
    return Qnil;
}

void
Init_Thread()
{
    rb_eThreadError = rb_define_class("ThreadError", rb_eStandardError);
    rb_cThread = rb_define_class("Thread", rb_cObject);

    rb_define_singleton_method(rb_cThread, "new", rb_thread_start, 0);
    rb_define_singleton_method(rb_cThread, "start", rb_thread_start, 0);
    rb_define_singleton_method(rb_cThread, "fork", rb_thread_start, 0);

    rb_define_singleton_method(rb_cThread, "stop", rb_thread_stop, 0);
    rb_define_singleton_method(rb_cThread, "kill", rb_thread_s_kill, 1);
    rb_define_singleton_method(rb_cThread, "exit", rb_thread_exit, 0);
    rb_define_singleton_method(rb_cThread, "pass", rb_thread_pass, 0);
    rb_define_singleton_method(rb_cThread, "join", rb_thread_s_join, 1);
    rb_define_singleton_method(rb_cThread, "current", rb_thread_current, 0);
    rb_define_singleton_method(rb_cThread, "main", rb_thread_main, 0);

    rb_define_singleton_method(rb_cThread, "critical", rb_thread_get_critical, 0);
    rb_define_singleton_method(rb_cThread, "critical=", rb_thread_set_critical, 1);

    rb_define_singleton_method(rb_cThread, "abort_on_exception", rb_thread_s_abort_exc, 0);
    rb_define_singleton_method(rb_cThread, "abort_on_exception=", rb_thread_s_abort_exc_set, 1);

    rb_define_method(rb_cThread, "run", rb_thread_run, 0);
    rb_define_method(rb_cThread, "wakeup", rb_thread_wakeup, 0);
    rb_define_method(rb_cThread, "exit", rb_thread_kill, 0);
    rb_define_method(rb_cThread, "value", rb_thread_value, 0);
    rb_define_method(rb_cThread, "status", rb_thread_status, 0);
    rb_define_method(rb_cThread, "join", rb_thread_join, 0);
    rb_define_method(rb_cThread, "alive?", rb_thread_status, 0);
    rb_define_method(rb_cThread, "stop?", rb_thread_stop_p, 0);
    rb_define_method(rb_cThread, "raise", rb_thread_raise, -1);

    rb_define_method(rb_cThread, "abort_on_exception", rb_thread_abort_exc, 0);
    rb_define_method(rb_cThread, "abort_on_exception=", rb_thread_abort_exc_set, 1);

    rb_define_method(rb_cThread, "[]", rb_thread_aref, 1);
    rb_define_method(rb_cThread, "[]=", rb_thread_aset, 2);
    rb_define_method(rb_cThread, "key?", rb_thread_key_p, 1);

    /* allocate main thread */
    main_thread = rb_thread_alloc(rb_cThread);

    rb_cContinuation = rb_define_class("Continuation", rb_cObject);
    rb_undef_method(CLASS_OF(rb_cContinuation), "new");
    rb_define_method(rb_cContinuation, "call", rb_continuation_call, -1);
    rb_define_global_function("callcc", rb_callcc, 0);
}

static VALUE
rb_f_catch(dmy, tag)
    VALUE dmy, tag;
{
    int state;
    ID t;
    VALUE val;			/* OK */

    t = rb_to_id(tag);
    PUSH_TAG(t);
    if ((state = EXEC_TAG()) == 0) {
	val = rb_yield_0(tag, 0, 0, Qfalse);
    }
    else if (state == TAG_THROW && t == prot_tag->dst) {
	val = prot_tag->retval;
	state = 0;
    }
    POP_TAG();
    if (state) JUMP_TAG(state);

    return val;
}

static VALUE
catch_i(tag)
    ID tag;
{
    return rb_funcall(Qnil, rb_intern("catch"), 1, INT2FIX(tag));
}

VALUE
rb_catch(tag, proc, data)
    const char *tag;
    VALUE (*proc)();
    VALUE data;
{
    return rb_iterate(catch_i, rb_intern(tag), proc, data);
}

static VALUE
rb_f_throw(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE tag, value;
    ID t;
    struct tag *tt = prot_tag;

    rb_scan_args(argc, argv, "11", &tag, &value);
    t = rb_to_id(tag);

    while (tt) {
	if (tt->tag == t) {
	    tt->dst = t;
	    break;
	}
	if (tt->tag == PROT_THREAD) {
	    rb_raise(rb_eThreadError, "uncaught throw `%s' in thread 0x%x",
		     rb_id2name(t),
		     curr_thread);
	}
	tt = tt->prev;
    }
    if (!tt) {
	rb_raise(rb_eNameError, "uncaught throw `%s'", rb_id2name(t));
    }
    return_value(value);
    rb_trap_restore_mask();
    JUMP_TAG(TAG_THROW);
    /* not reached */
}

void
rb_throw(tag, val)
    const char *tag;
    VALUE val;
{
    VALUE argv[2];
    ID t = rb_intern(tag);

    argv[0] = INT2FIX(t);
    argv[1] = val;
    rb_f_throw(2, argv);
}

static void
return_check()
{
    struct tag *tt = prot_tag;

    while (tt) {
	if (tt->tag == PROT_FUNC) {
	    break;
	}
	if (tt->tag == PROT_THREAD) {
	    rb_raise(rb_eThreadError, "return from within thread 0x%x",
		     curr_thread);
	}
	tt = tt->prev;
    }
}

