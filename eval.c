/************************************************

  eval.c -

  $Author$
  $Date$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-1997 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "node.h"
#include "env.h"
#include "sig.h"

#include <stdio.h>
#include <setjmp.h>
#include "st.h"
#include "dln.h"

#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strrchr();
#endif

#ifndef setjmp
#ifdef HAVE__SETJMP
#define setjmp(env) _setjmp(env)
#define longjmp(env,val) _longjmp(env,val)
#endif
#endif

extern VALUE cData;
VALUE cProc;
static VALUE proc_call();
static VALUE f_binding();

#define CACHE_SIZE 0x200
#define CACHE_MASK 0x1ff
#define EXPR1(c,m) ((((int)(c)>>3)^(m))&CACHE_MASK)

struct cache_entry {		/* method hash table. */
    ID mid;			/* method's id */
    ID mid0;			/* method's original id */
    struct RClass *class;	/* receiver's class */
    struct RClass *origin;	/* where method defined  */
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

void
rb_add_method(class, mid, node, noex)
    struct RClass *class;
    ID mid;
    NODE *node;
    int noex;
{
    NODE *body;

    if (NIL_P(class)) class = (struct RClass*)cObject;
    body = NEW_METHOD(node, noex);
    st_insert(class->m_tbl, mid, body);
}

static NODE*
search_method(class, id, origin)
    struct RClass *class, **origin;
    ID id;
{
    NODE *body;

    while (!st_lookup(class->m_tbl, id, &body)) {
	class = class->super;
	if (!class) return 0;
    }

    if (origin) *origin = class;
    return body;
}

static NODE*
rb_get_method_body(classp, idp, noexp)
    struct RClass **classp;
    ID *idp;
    int *noexp;
{
    ID id = *idp;
    struct RClass *class = *classp;
    NODE *body;
    struct RClass *origin;
    struct cache_entry *ent;

    if ((body = search_method(class, id, &origin)) == 0) {
	return 0;
    }
    if (!body->nd_body) return 0;

    /* store in cache */
    ent = cache + EXPR1(class, id);
    ent->class  = class;
    ent->noex   = body->nd_noex;
    body = body->nd_body;
    if (nd_type(body) == NODE_FBODY) {
	ent->mid = id;
	*classp = ent->origin = (struct RClass*)body->nd_orig;
	*idp = ent->mid0 = body->nd_mid;
	body = ent->method = body->nd_head;
    }
    else {
	*classp = ent->origin = origin;
	ent->mid = ent->mid0 = id;
	ent->method = body;
    }

    if (noexp) *noexp = ent->noex;
    return body;
}

void
rb_alias(class, name, def)
    struct RClass *class;
    ID name, def;
{
    struct RClass *origin;
    NODE *orig, *body;

    if (name == def) return;
    orig = search_method(class, def, &origin);
    if (!orig || !orig->nd_body) {
	if (TYPE(class) == T_MODULE) {
	    orig = search_method(cObject, def, &origin);
	}
    }
    if (!orig || !orig->nd_body) {
	NameError("undefined method `%s' for `%s'",
		  rb_id2name(def), rb_class2name((VALUE)class));
    }
    body = orig->nd_body;
    if (nd_type(body) == NODE_FBODY) { /* was alias */
	body = body->nd_head;
	def = body->nd_mid;
	origin = (struct RClass*)body->nd_orig;
    }

    st_insert(class->m_tbl, name,
	      NEW_METHOD(NEW_FBODY(body, def, origin), orig->nd_noex));
}

static void
rb_export_method(class, name, noex)
    struct RClass *class;
    ID name;
    int noex;
{
    NODE *body;
    struct RClass *origin;

    body = search_method(class, name, &origin);
    if (!body && TYPE(class) == T_MODULE) {
	body = search_method(cObject, name, &origin);
    }
    if (!body) {
	NameError("undefined method `%s' for `%s'",
		  rb_id2name(name), rb_class2name((VALUE)class));
    }
    if (body->nd_noex != noex) {
	if (class == origin) {
	    body->nd_noex = noex;
	}
	else {
	    rb_clear_cache();
	    rb_add_method(class, name, NEW_ZSUPER(), noex);
	}
    }
}

static VALUE
method_boundp(class, id, ex)
    struct RClass *class;
    ID id;
    int ex;
{
    int noex;

    if (rb_get_method_body(&class, &id, &noex)) {
	if (ex && noex == NOEX_PRIVATE)
	    return FALSE;
	return TRUE;
    }
    return FALSE;
}

int
rb_method_boundp(class, id, priv)
    VALUE class;
    ID id;
    int priv;
{
    if (method_boundp(class, id, priv?NOEX_PRIVATE:NOEX_PUBLIC))
	return TRUE;
    return FALSE;
}

static ID init, eqq, each, aref, aset;
VALUE errinfo = Qnil, errat = Qnil;
extern NODE *eval_tree;
extern int nerrs;

extern VALUE mKernel;
extern VALUE cModule;
extern VALUE cClass;
extern VALUE eFatal;
extern VALUE eGlobalExit;
extern VALUE eInterrupt;
extern VALUE eSystemExit;
extern VALUE eException;
extern VALUE eRuntimeError;
extern VALUE eSyntaxError;
static VALUE eLocalJumpError;
extern VALUE eSecurityError;

extern VALUE TopSelf;

struct FRAME *the_frame;
struct SCOPE *the_scope;
static struct FRAME *top_frame;
static struct SCOPE *top_scope;

#define PUSH_FRAME() {			\
    struct FRAME _frame;		\
    _frame.prev = the_frame;		\
    _frame.file = sourcefile;		\
    _frame.line = sourceline;		\
    _frame.iter = the_iter->iter;	\
    _frame.cbase = the_frame->cbase;	\
    the_frame = &_frame;		\

#define POP_FRAME()  the_frame = _frame.prev; }

struct BLOCK {
    NODE *var;
    NODE *body;
    VALUE self;
    struct FRAME frame;
    struct SCOPE *scope;
    struct RClass *class;
    int level;
    int iter;
    struct RVarmap *d_vars;
#ifdef THREAD
    VALUE orig_thread;
#endif
    struct BLOCK *prev;
} *the_block;

#define PUSH_BLOCK(v,b) {		\
    struct BLOCK _block;		\
    _block.level = (int)prot_tag;	\
    _block.var = v;			\
    _block.body = b;			\
    _block.self = self;			\
    _block.frame = *the_frame;		\
    _block.class = the_class;		\
    _block.frame.file = sourcefile;	\
    _block.frame.line = sourceline;	\
    _block.scope = the_scope;		\
    _block.d_vars = the_dyna_vars;	\
    _block.prev = the_block;		\
    _block.iter = the_iter->iter;	\
    the_block = &_block;		\

#define PUSH_BLOCK2(b) {		\
    struct BLOCK _block;		\
    _block = *b;			\
    _block.prev = the_block;		\
    the_block = &_block;

#define POP_BLOCK() 			\
   the_block = the_block->prev; 	\
}

struct RVarmap *the_dyna_vars;
#define PUSH_VARS() {			\
    struct RVarmap *_old;		\
    _old = the_dyna_vars;		\
    the_dyna_vars = 0;

#define POP_VARS()			\
    the_dyna_vars = _old;		\
}

VALUE
dyna_var_defined(id)
    ID id;
{
    struct RVarmap *vars = the_dyna_vars;

    while (vars) {
	if (vars->id == id) return TRUE;
	vars = vars->next;
    }
    return FALSE;
}

VALUE
dyna_var_ref(id)
    ID id;
{
    struct RVarmap *vars = the_dyna_vars;

    while (vars) {
	if (vars->id == id) {
	    return vars->val;
	}
	vars = vars->next;
    }
    return Qnil;
}

VALUE
dyna_var_asgn(id, value)
    ID id;
    VALUE value;
{
    struct RVarmap *vars = the_dyna_vars;

    while (vars) {
	if (vars->id == id) {
	    vars->val = value;
	    return value;
	}
	vars = vars->next;
    }
    {
	NEWOBJ(_vars, struct RVarmap);
	OBJSETUP(_vars, 0, T_VARMAP);
	_vars->id = id;
	_vars->val = value;
	_vars->next = the_dyna_vars;
	the_dyna_vars = _vars;
    }
    return value;
}

static struct iter {
    int iter;
    struct iter *prev;
} *the_iter;

#define ITER_NOT 0
#define ITER_PRE 1
#define ITER_CUR 2

#define PUSH_ITER(i) {			\
    struct iter _iter;			\
    _iter.prev = the_iter;		\
    _iter.iter = (i);			\
    the_iter = &_iter;			\

#define POP_ITER()			\
    the_iter = _iter.prev;		\
}

static struct tag {
    jmp_buf buf;
    struct FRAME *frame;
    struct iter *iter;
    struct tag *prev;
} *prot_tag;

#define PUSH_TAG() {			\
    struct tag _tag;			\
    _tag.frame = the_frame;		\
    _tag.iter = the_iter;		\
    _tag.prev = prot_tag;		\
    prot_tag = &_tag;

#define EXEC_TAG()    ((NODE*)setjmp(prot_tag->buf))

#define JUMP_TAG(st) {			\
    the_frame = prot_tag->frame;	\
    the_iter = prot_tag->iter;		\
    longjmp(prot_tag->buf,(int)(st));	\
}

#define JUMP_TAG3(val,data1,data2) \
    JUMP_TAG(node_newnode(NODE_TAG,(val),(data1),(data2)))

#define JUMP_TAG2(val,data) JUMP_TAG3((val),(data),0)

#define POP_TAG()			\
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

#define IN_BLOCK       0x10

struct RClass *the_class;

#define PUSH_CLASS() {			\
    struct RClass *_class = the_class;	\

#define POP_CLASS() the_class = _class; }

#define PUSH_SCOPE() {			\
    struct SCOPE *_old;			\
    NEWOBJ(_scope, struct SCOPE);	\
    OBJSETUP(_scope, 0, T_SCOPE);	\
    _scope->local_tbl = 0;		\
    _scope->local_vars = 0;		\
    _scope->flag = 0;			\
    _old = the_scope;			\
    the_scope = _scope;			\

#define POP_SCOPE() \
    if (the_scope->flag == SCOPE_ALLOCA) {\
	the_scope->local_vars = 0;\
	the_scope->local_tbl  = 0;\
	if (the_scope != top_scope)\
            gc_force_recycle(the_scope);\
    }\
    else {\
        the_scope->flag |= SCOPE_NOSTACK;\
    }\
    the_scope = _old;\
}

static VALUE rb_eval();
static VALUE eval();
static NODE *compile();

static VALUE rb_call();
VALUE rb_apply();
VALUE rb_funcall2();

static VALUE module_setup();

static VALUE massign();
static void assign();

static int safe_level = 0;
/* safe-level:
   0 - strings from streams/environment/ARGV are tainted (default)
   1 - no dangerous operation by tainted string
   2 - some process operations prohibited
   3 - all genetated strings are tainted
   4 - no global variable value modification/no direct output
   5 - no instance variable value modification
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
	Raise(eSecurityError, "tried to downgrade safe level from %d to %d",
	      safe_level, level);
    }
    safe_level = level;
}

void
rb_check_safe_str(x)
    VALUE x;
{
    if (TYPE(x)!= T_STRING) {
	TypeError("wrong argument type %s (expected String)",
		  rb_class2name(CLASS_OF(x)));
    }
    if (rb_safe_level() > 0 && str_tainted(x)) {
	Raise(eSecurityError, "Insecure operation - %s",
	      rb_id2name(the_frame->last_func));
    }
}

void
rb_secure(level)
    int level;
{
    if (level <= safe_level) {
	Raise(eSecurityError, "Insecure operation `%s' for level %d",
	      rb_id2name(the_frame->last_func), level);
    }
}

extern int   sourceline;
extern char *sourcefile;

static VALUE trace_func = 0;
static void call_trace_func();

static void
error_pos()
{
    if (sourcefile) {
	if (the_frame->last_func) {
	    fprintf(stderr, "%s:%d:in `%s'", sourcefile, sourceline,
		    rb_id2name(the_frame->last_func));
	}
	else {
	    fprintf(stderr, "%s:%d", sourcefile, sourceline);
	}
    }
}

static void
error_print()
{
    VALUE eclass;

    if (NIL_P(errinfo)) return;

    if (!NIL_P(errat)) {
	VALUE mesg = Qnil;

	switch (TYPE(errat)) {
	  case T_STRING:
	    mesg = errat;
	    errat = Qnil;
	    break;
	  case T_ARRAY:
	    mesg = RARRAY(errat)->ptr[0];
	    break;
	}
	if (NIL_P(mesg)) error_pos();
	else {
	    fwrite(RSTRING(mesg)->ptr, 1, RSTRING(mesg)->len, stderr);
	}
    }

    eclass = CLASS_OF(errinfo);
    if (eclass == eRuntimeError && RSTRING(errinfo)->len == 0) {
	fprintf(stderr, ": unhandled exception\n");
    }
    else {
	PUSH_TAG();
	if (EXEC_TAG() == 0) {
	    VALUE epath = rb_class_path(eclass);
	    if (RSTRING(epath)->ptr[0] != '#') {
		fprintf(stderr, ": ");
		fwrite(RSTRING(epath)->ptr, 1, RSTRING(epath)->len, stderr);
	    }
	}
	POP_TAG();

	if (RSTRING(errinfo)->len > 0) {
	    fprintf(stderr, ": ");
	    fwrite(RSTRING(errinfo)->ptr, 1, RSTRING(errinfo)->len, stderr);
	}
	if (RSTRING(errinfo)->ptr[RSTRING(errinfo)->len - 1] != '\n') {
	    putc('\n', stderr);
	}
    }

    if (!NIL_P(errat)) {
	int i;
	struct RArray *ep = RARRAY(errat);

#define TRACE_MAX (TRACE_HEAD+TRACE_TAIL+5)
#define TRACE_HEAD 8
#define TRACE_TAIL 5

	for (i=1; i<ep->len; i++) {
	    fprintf(stderr, "\tfrom %s\n", RSTRING(ep->ptr[i])->ptr);
	    if (i == TRACE_HEAD && ep->len > TRACE_MAX) {
		fprintf(stderr, "\t ... %d levels...\n",
			ep->len - TRACE_HEAD - TRACE_TAIL);
		i = ep->len - TRACE_TAIL;
	    }
	}
    }
}

#ifndef NT
extern char **environ;
#endif
char **origenviron;

void
ruby_init()
{
    static struct FRAME frame;
    static struct iter iter;
    NODE *state;

    the_frame = top_frame = &frame;
    the_iter = &iter;

    origenviron = environ;

    init_heap();
    PUSH_SCOPE();
    the_scope->local_vars = 0;
    the_scope->local_tbl  = 0;
    top_scope = the_scope;

    PUSH_TAG()
    if ((state = EXEC_TAG()) == 0) {
	rb_call_inits();
	the_class = (struct RClass*)cObject;
	the_frame->cbase = (VALUE)node_newnode(NODE_CREF,cObject,0,0);
	rb_define_global_const("TOPLEVEL_BINDING", f_binding(TopSelf));
	ruby_prog_init();
    }
    POP_TAG();
    if (state) error_print();
    POP_SCOPE();
    the_scope = top_scope;
}

static int ext_init = 0;

void
ruby_options(argc, argv)
    int argc;
    char **argv;
{
    NODE *state;

    PUSH_TAG()
    if ((state = EXEC_TAG()) == 0) {
	NODE *save;

	Init_ext();
	ext_init = 1;
	ruby_process_options(argc, argv);
	save = eval_tree;
	rb_require_modules();
	eval_tree = save;
    }
    POP_TAG();
    if (state) {
	error_print();
	exit(1);
    }
}

static VALUE
eval_node(self)
    VALUE self;
{
    VALUE result = Qnil;
    NODE *tree;

    if (!eval_tree) return Qnil;

    tree = eval_tree;
    eval_tree = 0;

    result = rb_eval(self, tree);
    return result;
}

int rb_in_eval;

#ifdef THREAD
static void thread_cleanup();
static void thread_wait_other_threads();
static VALUE thread_current();
#endif

static int exit_status;

void
ruby_run()
{
    NODE *state;
    static NODE *ex;

    if (nerrs > 0) exit(nerrs);

    init_stack();
    errat = Qnil;		/* clear for execution */

    PUSH_TAG();
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	if (!ext_init) Init_ext();
	eval_node(TopSelf);
    }
    POP_ITER();
    POP_TAG();

    if (state && !ex) ex = state;
    PUSH_TAG();
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	rb_trap_exit();
#ifdef THREAD
	thread_cleanup();
	thread_wait_other_threads();
#endif
    }
    else {
	ex = state;
    }
    POP_ITER();
    POP_TAG();

    if (!ex) {
	exit(0);
    }

    switch (ex->nd_tag) {
      case IN_BLOCK|TAG_RETURN:
      case TAG_RETURN:
	error_pos();
	fprintf(stderr, "unexpected return\n");
	exit(1);
	break;
      case TAG_NEXT:
	error_pos();
	fprintf(stderr, "unexpected next\n");
	exit(1);
	break;
      case IN_BLOCK|TAG_BREAK:
      case TAG_BREAK:
	error_pos();
	fprintf(stderr, "unexpected break\n");
	exit(1);
	break;
      case TAG_REDO:
	error_pos();
	fprintf(stderr, "unexpected redo\n");
	exit(1);
	break;
      case TAG_RETRY:
	error_pos();
	fprintf(stderr, "retry outside of rescue clause\n");
	exit(1);
	break;
      case TAG_RAISE:
      case TAG_FATAL:
	if (obj_is_kind_of(errinfo, eSystemExit)) {
	    exit(exit_status);
	}
	error_print();
	exit(1);
	break;
      case TAG_THROW:
	error_pos();
	fprintf(stderr, "uncaught throw `%s'\n", rb_id2name(ex->nd_tlev));
	exit(1);
	break;
      default:
	Bug("Unknown longjmp status %d", ex->nd_tag);
	break;
    }
}

static void
compile_error(at)
    char *at;
{
    VALUE mesg;

    mesg = errinfo;
    nerrs = 0;
    errinfo = exc_new2(eSyntaxError, "compile error in ");
    str_cat(errinfo, at, strlen(at));
    str_cat(errinfo, ":\n", 2);
    str_cat(errinfo, RSTRING(mesg)->ptr, RSTRING(mesg)->len);
    rb_raise(errinfo);
}

VALUE
rb_eval_string(str)
    char *str;
{
    VALUE v;
    char *oldsrc = sourcefile;

    sourcefile = "(eval)";
    v = eval(TopSelf, str_new2(str), Qnil);
    sourcefile = oldsrc;

    return v;
}

void
rb_eval_cmd(cmd, arg)
    VALUE cmd, arg;
{
    NODE *state;
    struct SCOPE *saved_scope;
    volatile int safe = rb_safe_level();

    if (TYPE(cmd) != T_STRING) {
	if (obj_is_kind_of(cmd, cProc)) {
	    proc_call(cmd, arg);
	    return;
	}
    }

    PUSH_CLASS();
    PUSH_TAG();
    saved_scope = the_scope;
    the_scope = top_scope;

    the_class = (struct RClass*)cObject;
    if (str_tainted(cmd)) {
	safe_level = 5;
    }

    if ((state = EXEC_TAG()) == 0) {
	eval(TopSelf, cmd, Qnil);
    }

    the_scope = saved_scope;
    safe_level = safe;
    POP_TAG();
    POP_CLASS();

    if (state == 0) return;
    switch (state->nd_tag) {
      case TAG_RETURN:
	Raise(eLocalJumpError, "unexpected return");
	break;
      case TAG_NEXT:
	Raise(eLocalJumpError, "unexpected next");
	break;
      case TAG_BREAK:
	Raise(eLocalJumpError, "unexpected break");
	break;
      case TAG_REDO:
	Raise(eLocalJumpError, "unexpected redo");
	break;
      case TAG_RETRY:
	Raise(eLocalJumpError, "retry outside of rescue clause");
	break;
      default:
	JUMP_TAG(state);
	break;
    }
}

void
rb_trap_eval(cmd, sig)
    VALUE cmd;
    int sig;
{
    NODE *state;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	rb_eval_cmd(cmd, ary_new3(1, INT2FIX(sig)));
    }
    POP_TAG();
    if (state) {
	trap_immediate = 0;
	JUMP_TAG(state);
    }
}

static VALUE
superclass(self, node)
    VALUE self;
    NODE *node;
{
    VALUE val = 0;
    NODE *state;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	val = rb_eval(self, node);
    }
    POP_TAG();
    if (state) {
	if (state->nd_tag == TAG_RAISE) {
	  superclass_error:
	    switch (nd_type(node)) {
	      case NODE_COLON2:
		TypeError("undefined superclass `%s'", rb_id2name(node->nd_mid));
	      case NODE_CVAR:
		TypeError("undefined superclass `%s'", rb_id2name(node->nd_vid));
	      default:
		TypeError("superclass undefined");
	    }
	}
	JUMP_TAG(state);
    }
    if (TYPE(val) != T_CLASS) goto superclass_error;
    if (FL_TEST(val, FL_SINGLETON)) {
	TypeError("can't make subclass of virtual class");
    }

    return val;
}

static VALUE
ev_const_defined(cref, id)
    NODE *cref;
    ID id;
{
    NODE *cbase = cref;

    while (cbase && cbase->nd_clss != cObject) {
	struct RClass *class = RCLASS(cbase->nd_clss);

	if (class->iv_tbl &&
	    st_lookup(class->iv_tbl, id, 0)) {
	    return TRUE;
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

    while (cbase && cbase->nd_clss != cObject) {
	struct RClass *class = RCLASS(cbase->nd_clss);

	if (class->iv_tbl &&
	    st_lookup(class->iv_tbl, id, &result)) {
	    return result;
	}
	cbase = cbase->nd_next;
    }
    return rb_const_get(cref->nd_clss, id);
}

#define SETUP_ARGS(anode) {\
    NODE *n = anode;\
    if (!n) {\
	argc = 0;\
	argv = 0;\
    }\
    else if (nd_type(n) == NODE_ARRAY) {\
	argc=n->nd_alen;\
        if (argc > 0) {\
            int i;\
	    int line = sourceline;\
	    n = anode;\
	    argv = ALLOCA_N(VALUE,argc);\
	    for (i=0;i<argc;i++) {\
		argv[i] = rb_eval(self,n->nd_head);\
		n=n->nd_next;\
	    }\
	    sourcefile = anode->file;\
	    sourceline = line;\
        }\
        else {\
	    argc = 0;\
	    argv = 0;\
        }\
    }\
    else {\
        VALUE args = rb_eval(self,n);\
	int line = sourceline;\
	if (TYPE(args) != T_ARRAY)\
	    args = rb_to_a(args);\
        argc = RARRAY(args)->len;\
	argv = ALLOCA_N(VALUE, argc);\
	MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);\
	sourcefile = anode->file;\
	sourceline = line;\
    }\
}

int
rb_test_false_or_nil(v)
    VALUE v;
{
    return (v != Qnil) && (v != FALSE);
}

#define MATCH_DATA the_scope->local_vars[node->nd_cnt]

static char*
is_defined(self, node, buf)
    VALUE self;
    NODE *node;			/* OK */
    char *buf;
{
    VALUE val;			/* OK */
    NODE *state;

    node = node->nd_head;

    switch (nd_type(node)) {
      case NODE_SUPER:
      case NODE_ZSUPER:
	if (the_frame->last_func == 0) return 0;
	else if (method_boundp(the_frame->last_class->super,
			       the_frame->last_func, 1)) {
	    return "super";
	}
	break;

      case NODE_FCALL:
      case NODE_VCALL:
	val = CLASS_OF(self);
	goto check_bound;

      case NODE_CALL:
	PUSH_TAG();
	if ((state = EXEC_TAG()) == 0) {
	    val = rb_eval(self, node->nd_recv);
	    val = CLASS_OF(val);
	}
	POP_TAG();
	if (state) {
	    return 0;
	}
      check_bound:
	if (method_boundp(val, node->nd_mid,
			  nd_type(node)== NODE_CALL)) {
	    return "method";
	}
	break;

      case NODE_YIELD:
	if (iterator_p()) {
	    return "yield";
	}
	break;

      case NODE_SELF:
	return "self";

      case NODE_NIL:
	return "nil";

      case NODE_ATTRSET:
      case NODE_OP_ASGN1:
      case NODE_OP_ASGN2:
      case NODE_MASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_CASGN:
	return "assignment";

      case NODE_LVAR:
      case NODE_DVAR:
	return "local-variable";

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
	if (ev_const_defined(the_frame->cbase, node->nd_vid)) {
	    return "constant";
	}
	break;

      case NODE_COLON2:
	PUSH_TAG();
	if ((state = EXEC_TAG()) == 0) {
	    val = rb_eval(self, node->nd_head);
	}
	POP_TAG();
	if (state) {
	    return 0;
	}
	else {
	    switch (TYPE(val)) {
	      case T_CLASS:
	      case T_MODULE:
		if (rb_const_defined_at(val, node->nd_mid))
		    return "constant";
	    }
	}
	break;

      case NODE_NTH_REF:
	if (reg_nth_defined(node->nd_nth, MATCH_DATA)) {
	    sprintf(buf, "$%d", node->nd_nth);
	    return buf;
	}
	break;

      case NODE_BACK_REF:
	if (reg_nth_defined(0, MATCH_DATA)) {
	    sprintf(buf, "$%c", node->nd_nth);
	    return buf;
	}
	break;

      default:
	PUSH_TAG();
	if ((state = EXEC_TAG()) == 0) {
	    rb_eval(self, node);
	}
	POP_TAG();
	if (!state) {
	    return "expression";
	}
	break;
    }
    return 0;
}

static int handle_rescue();
VALUE rb_yield_0();

static void blk_free();

static VALUE
set_trace_func(obj, trace)
    VALUE obj;
    struct RData *trace;
{
    if (NIL_P(trace)) {
	trace_func = 0;
	return Qnil;
    }
    if (TYPE(trace) != T_DATA || trace->dfree != blk_free) {
	TypeError("trace_func needs to be Proc");
    }
    return trace_func = (VALUE)trace;
}

static void
call_trace_func(event, file, line, self, id)
    char *event;
    char *file;
    int line;
    VALUE self;
    ID id;
{
    NODE *state;
    volatile VALUE trace;
    struct FRAME *prev;

    if (!trace_func) return;

    trace = trace_func;
    trace_func = 0;
#ifdef THREAD
    thread_critical++;
#endif

    prev = the_frame;
    PUSH_FRAME();
    *the_frame = *_frame.prev;
    the_frame->prev = prev;

    the_frame->line = sourceline = line;
    the_frame->file = sourcefile = file;
    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	proc_call(trace, ary_new3(5, str_new2(event),
				  str_new2(sourcefile),
				  INT2FIX(sourceline),
				  INT2FIX(id),
				  self?f_binding(self):Qnil));
    }
    POP_TAG();
    POP_FRAME();

#ifdef THREAD
    thread_critical--;
#endif
    if (!trace_func) trace_func = trace;
    if (state) JUMP_TAG(state);
}

static VALUE
rb_eval(self, node)
    VALUE self;
    NODE * volatile node;
{
    NODE *state;
    volatile VALUE result = Qnil;

#define RETURN(v) { result = (v); goto finish; }

  again:
    if (!node) RETURN(Qnil);

#if 0
    sourceline = nd_line(node);
    sourcefile = node->file;
#endif
    switch (nd_type(node)) {
      case NODE_BLOCK:
	while (node) {
	    result = rb_eval(self, node->nd_head);
	    node = node->nd_next;
	}
	break;

	/* begin .. end without clauses */
      case NODE_BEGIN:
	node = node->nd_body;
	goto again;

	/* nodes for speed-up(default match) */
      case NODE_MATCH:
	result = reg_match2(node->nd_head->nd_lit);
	break;

	/* nodes for speed-up(top-level loop for -n/-p) */
      case NODE_OPT_N:
	while (!NIL_P(f_gets())) {
	    rb_eval(self, node->nd_body);
	}
	RETURN(Qnil);

      case NODE_SELF:
	RETURN(self);

      case NODE_NIL:
	RETURN(Qnil);

      case NODE_IF:
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
			call_trace_func("line", tag->file, nd_line(tag),
					self, the_frame->last_func);	
		    }
		    if (RTEST(rb_funcall2(rb_eval(self, tag->nd_head),eqq,1,&val))){
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
	PUSH_TAG();
	if ((state = EXEC_TAG()) == 0) {
	    if (node->nd_state && !RTEST(rb_eval(self, node->nd_cond)))
		goto while_out;
	    do {
	      while_redo:
		rb_eval(self, node->nd_body);
	      while_next:
		;
	    } while (RTEST(rb_eval(self, node->nd_cond)));
	}
	else {
	    switch  (state->nd_tag) {
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
	}
      while_out:
	POP_TAG();
	if (state) {
	    JUMP_TAG(state);
	}
	RETURN(Qnil);

      case NODE_UNTIL:
	PUSH_TAG();
	if ((state = EXEC_TAG()) == 0) {
	    if (node->nd_state && RTEST(rb_eval(self, node->nd_cond)))
		goto until_out;
	    do {
	      until_redo:
		rb_eval(self, node->nd_body);
	      until_next:
		;
	    } while (!RTEST(rb_eval(self, node->nd_cond)));
	}
	else {
	    switch  (state->nd_tag) {
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
	}
      until_out:
	POP_TAG();
	if (state) {
	    JUMP_TAG(state);
	}
	RETURN(Qnil);

      case NODE_ITER:
      case NODE_FOR:
	{
	    int tag_level;

	  iter_retry:
	    PUSH_BLOCK(node->nd_var, node->nd_body);
	    PUSH_TAG();

	    state = EXEC_TAG();
	    if (state == 0) {
		if (nd_type(node) == NODE_ITER) {
		    PUSH_ITER(ITER_PRE);
		    result = rb_eval(self, node->nd_iter);
		    POP_ITER();
		}
		else {
		    VALUE recv;
		    int line = sourceline;

		    recv = rb_eval(self, node->nd_iter);
		    PUSH_ITER(ITER_PRE);
		    sourcefile = node->file;
		    sourceline = line;
		    result = rb_call(CLASS_OF(recv),recv,each,0,0,0);
		    POP_ITER();
		}
	    }
	    POP_TAG();
	    tag_level = the_block->level;
	    POP_BLOCK();
	    if (state == 0) break;
	    switch (state->nd_tag) {
	      case TAG_RETRY:
		goto iter_retry;

	      case IN_BLOCK|TAG_BREAK:
		if (state->nd_tlev != tag_level) {
		    JUMP_TAG(state);
		}
		result = Qnil;
		break;
	      case IN_BLOCK|TAG_RETURN:
		if (state->nd_tlev == tag_level) {
		    state->nd_tag &= ~IN_BLOCK;
		}
		/* fall through */
	      default:
		JUMP_TAG(state);
	    }
	}
	break;

      case NODE_YIELD:
	result = rb_yield_0(rb_eval(self, node->nd_stts), 0);
	break;

      case NODE_RESCUE:
      retry_entry:
        {
	    volatile VALUE e_info = errinfo, e_at = errat;

	    PUSH_TAG();
	    if ((state = EXEC_TAG()) == 0) {
		result = rb_eval(self, node->nd_head);
	    }
	    POP_TAG();
	    if (state) {
		if (state->nd_tag == TAG_RAISE) {
		    NODE * volatile resq = node->nd_resq;
		    while (resq) {
			if (handle_rescue(self, resq)) {
			    state = 0;
			    PUSH_TAG();
			    if ((state = EXEC_TAG()) == 0) {
				result = rb_eval(self, resq->nd_body);
			    }
			    POP_TAG();
			    if (state == 0) {
				errinfo = e_info;
				errat = e_at;
			    }
			    else if (state->nd_tag == TAG_RETRY) {
				state = 0;
				goto retry_entry;
			    }
			    break;
			}
			resq = resq->nd_head; /* next rescue */
		    }
		}
		if (state) {
		    JUMP_TAG(state);
		}
	    }
	}
        break;

      case NODE_ENSURE:
	PUSH_TAG();
	if ((state = EXEC_TAG()) == 0) {
	    result = rb_eval(self, node->nd_head);
	}
	POP_TAG();
	rb_eval(self, node->nd_ensr);
	if (state) {
	    JUMP_TAG(state);
	}
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
	if (RTEST(rb_eval(self, node->nd_body))) result = FALSE;
	else result = TRUE;
	break;

      case NODE_DOT2:
      case NODE_DOT3:
	RETURN(range_new(rb_eval(self, node->nd_beg), rb_eval(self, node->nd_end)));

      case NODE_FLIP2:		/* like AWK */
	if (node->nd_state == 0) {
	    if (RTEST(rb_eval(self, node->nd_beg))) {
		node->nd_state = rb_eval(self, node->nd_end)?0:1;
		result = TRUE;
	    }
	    else {
		result = FALSE;
	    }
	}
	else {
	    if (RTEST(rb_eval(self, node->nd_end))) {
		node->nd_state = 0;
	    }
	    result = TRUE;
	}
	break;

      case NODE_FLIP3:		/* like SED */
	if (node->nd_state == 0) {
	    if (RTEST(rb_eval(self, node->nd_beg))) {
		node->nd_state = 1;
		result = TRUE;
	    }
	    result = FALSE;
	}
	else {
	    if (RTEST(rb_eval(self, node->nd_end))) {
		node->nd_state = 0;
	    }
	    result = TRUE;
	}
	break;

      case NODE_RETURN:
	JUMP_TAG2(TAG_RETURN,(node->nd_stts)?rb_eval(self, node->nd_stts):Qnil);
	break;

      case NODE_CALL:
	{
	    VALUE recv;
	    int argc; VALUE *argv; /* used in SETUP_ARGS */

	    PUSH_ITER(ITER_NOT);
	    recv = rb_eval(self, node->nd_recv);
	    SETUP_ARGS(node->nd_args);
	    POP_ITER();
	    result = rb_call(CLASS_OF(recv),recv,node->nd_mid,argc,argv,0);
	}
	break;

      case NODE_FCALL:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */

	    PUSH_ITER(ITER_NOT);
	    SETUP_ARGS(node->nd_args);
	    POP_ITER();
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

	    if (nd_type(node) == NODE_ZSUPER) {
		argc = the_frame->argc;
		argv = the_frame->argv;
	    }
	    else {
		PUSH_ITER(ITER_NOT);
		SETUP_ARGS(node->nd_args);
		POP_ITER();
	    }

	    PUSH_ITER(the_iter->iter?ITER_PRE:ITER_NOT);
	    result = rb_call(the_frame->last_class->super, self,
			     the_frame->last_func, argc, argv, 1);
	    POP_ITER();
	}
	break;

      case NODE_SCOPE:
	{
	    VALUE save = the_frame->cbase;

	    PUSH_SCOPE();
	    PUSH_TAG();
	    if (node->nd_rval) the_frame->cbase = (VALUE)node->nd_rval;
	    if (node->nd_tbl) {
		VALUE *vars = ALLOCA_N(VALUE, node->nd_tbl[0]+1);
		*vars++ = (VALUE)node;
		the_scope->local_vars = vars;
		memclear(the_scope->local_vars, node->nd_tbl[0]);
		the_scope->local_tbl = node->nd_tbl;
	    }
	    else {
		the_scope->local_vars = 0;
		the_scope->local_tbl  = 0;
	    }
	    if ((state = EXEC_TAG()) == 0) {
		result = rb_eval(self, node->nd_body);
	    }
	    POP_TAG();
	    POP_SCOPE();
	    the_frame->cbase = save;
	    if (state) JUMP_TAG(state);
	}
	break;

      case NODE_OP_ASGN1:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    VALUE recv, val;
	    NODE *rval;

	    recv = rb_eval(self, node->nd_recv);
	    rval = node->nd_args->nd_head;
	    SETUP_ARGS(node->nd_args->nd_next);
	    val = rb_funcall2(recv, aref, argc-1, argv);
	    val = rb_funcall(val, node->nd_mid, 1, rb_eval(self, rval));
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

	    val = rb_funcall(val, node->nd_next->nd_mid, 1,
			     rb_eval(self, node->nd_value));

	    rb_funcall2(recv, id_attrset(id), 1, &val);
	    result = val;
	}
	break;

      case NODE_MASGN:
	result = massign(self, node, rb_eval(self, node->nd_value));
	break;

      case NODE_LASGN:
	if (the_scope->local_vars == 0)
	    Bug("unexpected local variable assignment");
	the_scope->local_vars[node->nd_cnt] = rb_eval(self, node->nd_value);
	result = the_scope->local_vars[node->nd_cnt];
	break;

      case NODE_DASGN:
	result = dyna_var_asgn(node->nd_vid, rb_eval(self, node->nd_value));
	break;

      case NODE_GASGN:
	{
	    VALUE val;

	    val = rb_eval(self, node->nd_value);
	    rb_gvar_set(node->nd_entry, val);
	    result = val;
	}
	break;

      case NODE_IASGN:
	{
	    VALUE val;

	    val = rb_eval(self, node->nd_value);
	    rb_ivar_set(self, node->nd_vid, val);
	    result = val;
	}
	break;

      case NODE_CASGN:
	{
	    VALUE val;

	    val = rb_eval(self, node->nd_value);
	    /* check for static scope constants */
	    if (verbose && ev_const_defined(the_frame->cbase, node->nd_vid)) {
		Warning("already initialized constant %s",
			rb_id2name(node->nd_vid));
	    }
	    rb_const_set(the_class, node->nd_vid, val);
	    result = val;
	}
	break;

      case NODE_LVAR:
	if (the_scope->local_vars == 0) {
	    Bug("unexpected local variable");
	}
	result = the_scope->local_vars[node->nd_cnt];
	break;

      case NODE_DVAR:
	result = dyna_var_ref(node->nd_vid);
	break;

      case NODE_GVAR:
	result = rb_gvar_get(node->nd_entry);
	break;

      case NODE_IVAR:
	result = rb_ivar_get(self, node->nd_vid);
	break;

      case NODE_CVAR:
	result = ev_const_get(the_frame->cbase, node->nd_vid);
	break;

      case NODE_COLON2:
	{
	    VALUE cls;

	    cls = rb_eval(self, node->nd_head);
	    switch (TYPE(cls)) {
	      case T_CLASS:
	      case T_MODULE:
		break;
	      default:
		Check_Type(cls, T_CLASS);
		break;
	    }
	    result = rb_const_get_at(cls, node->nd_mid);
	}
	break;

      case NODE_NTH_REF:
	result = reg_nth_match(node->nd_nth, MATCH_DATA);
	break;

      case NODE_BACK_REF:
	switch (node->nd_nth) {
	  case '&':
	    result = reg_last_match(MATCH_DATA);
	    break;
	  case '`':
	    result = reg_match_pre(MATCH_DATA);
	    break;
	  case '\'':
	    result = reg_match_post(MATCH_DATA);
	    break;
	  case '+':
	    result = reg_match_last(MATCH_DATA);
	    break;
	  default:
	    Bug("unexpected back-ref");
	}
	break;

      case NODE_HASH:
	{
	    NODE *list;
	    VALUE hash = hash_new();
	    VALUE key, val;

	    list = node->nd_head;
	    while (list) {
		key = rb_eval(self, list->nd_head);
		list = list->nd_next;
		if (list == 0)
		    Bug("odd number list for Hash");
		val = rb_eval(self, list->nd_head);
		list = list->nd_next;
		hash_aset(hash, key, val);
	    }
	    result = hash;
	}
	break;

      case NODE_ZARRAY:		/* zero length list */
	result = ary_new();
	break;

      case NODE_ARRAY:
	{
	    VALUE ary;
	    int i;

	    i = node->nd_alen;
	    ary = ary_new2(i);
	    for (i=0;node;node=node->nd_next) {
		RARRAY(ary)->ptr[i++] = rb_eval(self, node->nd_head);
		RARRAY(ary)->len = i;
	    }

	    result = ary;
	}
	break;

      case NODE_STR:
	result = str_new3(node->nd_lit);
	break;

      case NODE_DSTR:
      case NODE_DXSTR:
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
	{
	    VALUE str, str2;
	    NODE *list = node->nd_next;

	    str = str_new3(node->nd_lit);
	    while (list) {
		if (nd_type(list->nd_head) == NODE_STR) {
		    str2 = list->nd_head->nd_lit;
		}
		else {
		    if (nd_type(list->nd_head) == NODE_EVSTR) {
			rb_in_eval++;
			list->nd_head = compile(list->nd_head->nd_lit);
			rb_in_eval--;
			if (nerrs > 0) {
			    compile_error("string expand");
			}
		    }
		    str2 = rb_eval(self, list->nd_head);
		    str2 = obj_as_string(str2);
		}
		if (str2) {
		    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
		}
		list = list->nd_next;
	    }
	    switch (nd_type(node)) {
	      case NODE_DREGX:
		result = reg_new(RSTRING(str)->ptr, RSTRING(str)->len,
				 node->nd_cflag);
		break;
	      case NODE_DREGX_ONCE:	/* regexp expand once */
		result = reg_new(RSTRING(str)->ptr, RSTRING(str)->len,
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
	if (the_frame->argc != 1)
	    ArgError("Wrong # of arguments(%d for 1)", the_frame->argc);
	result = rb_ivar_set(self, node->nd_vid, the_frame->argv[0]);
	break;

      case NODE_DEFN:
	if (node->nd_defn) {
	    NODE *body;
	    VALUE origin;
	    int noex;

	    body = search_method(the_class, node->nd_mid, &origin);
	    if (body) {
		if (origin == (VALUE)the_class) {
		    Warning("redefine %s", rb_id2name(node->nd_mid));
		}
		rb_clear_cache();
	    }

	    if (body) noex = body->nd_noex;
	    else      noex = node->nd_noex; /* default(1 for toplevel) */

	    rb_add_method(the_class, node->nd_mid, node->nd_defn, noex);
	    result = Qnil;
	}
	break;

      case NODE_DEFS:
	if (node->nd_defn) {
	    VALUE recv = rb_eval(self, node->nd_recv);
	    VALUE class;
	    NODE *body;

	    if (FIXNUM_P(recv)) {
		TypeError("Can't define method \"%s\" for Fixnum",
			  rb_id2name(node->nd_mid));
	    }
	    if (NIL_P(recv)) {
		TypeError("Can't define method \"%s\" for nil",
			  rb_id2name(node->nd_mid));
	    }
	    if (rb_special_const_p(recv)) {
		TypeError("Can't define method \"%s\" for special constants",
			  rb_id2name(node->nd_mid));
	    }

	    class = rb_singleton_class(recv);
	    if (st_lookup(RCLASS(class)->m_tbl, node->nd_mid, &body)) {
		Warning("redefine %s", rb_id2name(node->nd_mid));
	    }
	    rb_clear_cache();
	    rb_funcall(recv, rb_intern("singleton_method_added"),
		       1, INT2FIX(node->nd_mid));
	    rb_add_method(class, node->nd_mid, node->nd_defn, NOEX_PUBLIC);
	    result = Qnil;
	}
	break;

      case NODE_UNDEF:
	{
	    struct RClass *origin;
	    NODE *body;

	    body = search_method(the_class, node->nd_mid, &origin);
	    if (!body || !body->nd_body) {
		NameError("undefined method `%s' for class `%s'",
			  rb_id2name(node->nd_mid), rb_class2name((VALUE)the_class));
	    }
	    rb_clear_cache();
	    rb_add_method(the_class, node->nd_mid, 0, NOEX_PUBLIC);
	    result = Qnil;
	}
	break;

      case NODE_ALIAS:
	rb_alias(the_class, node->nd_new, node->nd_old);
	result = Qnil;
	break;

      case NODE_VALIAS:
	rb_alias_variable(node->nd_new, node->nd_old);
	result = Qnil;
	break;

      case NODE_CLASS:
	{
	    VALUE super, class;
	    struct RClass *tmp;

	    if (node->nd_super) {
		super = superclass(self, node->nd_super);
	    }
	    else {
		super = 0;
	    }

	    if (rb_const_defined_at(the_class, node->nd_cname) &&
		((VALUE)the_class != cObject ||
		 !rb_autoload_defined(node->nd_cname))) {

		class = rb_const_get_at(the_class, node->nd_cname);
		if (TYPE(class) != T_CLASS) {
		    TypeError("%s is not a class", rb_id2name(node->nd_cname));
		}
		if (super) {
		    tmp = RCLASS(class)->super;
		    if (FL_TEST(tmp, FL_SINGLETON)) {
			tmp = RCLASS(tmp)->super;
		    }
		    while (TYPE(tmp) == T_ICLASS) {
			tmp = RCLASS(tmp)->super;
		    }
		    if (tmp != RCLASS(super)) {
			TypeError("superclass mismatch for %s",
				  rb_id2name(node->nd_cname));
		    }
		}
		if (safe_level >= 4) {
		    Raise(eSecurityError, "extending class prohibited");
		}
		rb_clear_cache();
		Warning("extending class %s", rb_id2name(node->nd_cname));
	    }
	    else {
		if (!super) super = cObject;
		class = rb_define_class_id(node->nd_cname, super);
		rb_const_set(the_class, node->nd_cname, class);
		rb_set_class_path(class,the_class,rb_id2name(node->nd_cname));
	    }

	    result = module_setup(class, node->nd_body);
	}
	break;

      case NODE_MODULE:
	{
	    VALUE module;

	    if (rb_const_defined_at(the_class, node->nd_cname) &&
		((VALUE)the_class != cObject ||
		 !rb_autoload_defined(node->nd_cname))) {

		module = rb_const_get_at(the_class, node->nd_cname);
		if (TYPE(module) != T_MODULE) {
		    TypeError("%s is not a module", rb_id2name(node->nd_cname));
		}
		if (safe_level >= 4) {
		    Raise(eSecurityError, "extending module prohibited");
		}
		Warning("extending module %s", rb_id2name(node->nd_cname));
	    }
	    else {
		module = rb_define_module_id(node->nd_cname);
		rb_const_set(the_class, node->nd_cname, module);
		rb_set_class_path(module,the_class,rb_id2name(node->nd_cname));
	    }

	    result = module_setup(module, node->nd_body);
	}
	break;

      case NODE_SCLASS:
	{
	    VALUE class;

	    class = rb_eval(self, node->nd_recv);
	    if (FIXNUM_P(class)) {
		TypeError("No virtual class for Fixnums");
	    }
	    if (NIL_P(class)) {
		TypeError("No virtual class for nil");
	    }
	    if (rb_special_const_p(class)) {
		TypeError("No virtual class for special constants");
	    }
	    if (FL_TEST(CLASS_OF(class), FL_SINGLETON)) {
		rb_clear_cache();
	    }
	    class = rb_singleton_class(class);

	    result = module_setup(class, node->nd_body);
	}
	break;

      case NODE_DEFINED:
	{
	    char buf[20];
	    char *desc = is_defined(self, node, buf);

	    if (desc) result = str_new2(desc);
	    else result = FALSE;
	}
	break;

    case NODE_NEWLINE:
	sourcefile = node->file;
	sourceline = node->nd_nth;
	if (trace_func) {
	    call_trace_func("line", sourcefile, sourceline,
			    self, the_frame->last_func);	
	}
	node = node->nd_next;
	goto again;

      default:
	Bug("unknown node type %d", nd_type(node));
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
    NODE *state;
    VALUE save = the_frame->cbase;
    VALUE result;		/* OK */

    /* fill c-ref */
    node->nd_clss = module;
    node = node->nd_body;

    PUSH_CLASS();
    the_class = (struct RClass*)module;
    PUSH_SCOPE();

    if (node->nd_rval) the_frame->cbase = node->nd_rval;
    if (node->nd_tbl) {
	VALUE *vars = ALLOCA_N(VALUE, node->nd_tbl[0]+1);
	*vars++ = (VALUE)node;
	the_scope->local_vars = vars;
	memclear(the_scope->local_vars, node->nd_tbl[0]);
	the_scope->local_tbl = node->nd_tbl;
    }
    else {
	the_scope->local_vars = 0;
	the_scope->local_tbl  = 0;
    }

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	if (trace_func) {
	    call_trace_func("class", node->file, nd_line(node),
			    the_class, the_frame->last_func);
	}
	result = rb_eval((VALUE)the_class, node->nd_body);
    }
    POP_TAG();
    POP_SCOPE();
    POP_CLASS();
    the_frame->cbase = save;
    if (trace_func) {
	call_trace_func("end", node->file, nd_line(node), 0,
			the_frame->last_func);
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
	return TRUE;
    }
    return FALSE;
}

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
	return TRUE;
    }
    return FALSE;
}

static VALUE
mod_method_defined(mod, mid)
    VALUE mod, mid;
{
    if (rb_method_boundp(mod, rb_to_id(mid), 1)) {
	return TRUE;
    }
    return FALSE;
}

void
rb_exit(status)
    int status;
{
    if (prot_tag) {
	exit_status = status;
	rb_raise(exc_new(eSystemExit, 0, 0));
    }
    exit(status);
}

static VALUE
f_exit(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE status;

    rb_secure(2);
    if (rb_scan_args(argc, argv, "01", &status) == 1) {
	status = NUM2INT(status);
    }
    else {
	status = 0;
    }
    rb_exit(status);
    /* not reached */
}

static VALUE
f_abort()
{
    rb_secure(2);
    if (errinfo) {
	error_print();
    }
    rb_exit(1);
    /* not reached */
}

void
rb_break()
{
    JUMP_TAG2(TAG_BREAK, 0);
}

static VALUE
f_break()
{
    JUMP_TAG2(TAG_BREAK, 0);
}

static VALUE
f_next()
{
    JUMP_TAG2(TAG_NEXT, 0);
}

static VALUE
f_redo()
{
    JUMP_TAG2(TAG_REDO, 0);
}

static VALUE
f_retry()
{
    JUMP_TAG2(TAG_RETRY, 0);
}

#ifdef __GNUC__
static volatile voidfn rb_longjmp;
#endif

static VALUE make_backtrace();

static void
rb_longjmp(tag, mesg)
    int tag;
    VALUE mesg;
{
    if (NIL_P(errinfo) && NIL_P(mesg)) {
	errinfo = exc_new(eRuntimeError, 0, 0);
    }

    if (sourcefile && (NIL_P(errat) || !NIL_P(mesg))) {
	errat = make_backtrace();
    }

    if (!NIL_P(mesg)) {
	if (obj_is_kind_of(mesg, eGlobalExit)) {
	    errinfo = mesg;
	}
	else {
	    errinfo = exc_new3(eRuntimeError, mesg);
	}
	str_freeze(errinfo);
    }

    JUMP_TAG2(tag, 0);
}

void
rb_raise(mesg)
    VALUE mesg;
{
    rb_longjmp(TAG_RAISE, mesg);
}

void
rb_fatal(mesg)
    VALUE mesg;
{
    rb_longjmp(TAG_FATAL, mesg);
}

void
rb_interrupt()
{
    Raise(eInterrupt, "");
}

static VALUE
f_raise(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE arg1, arg2;
    VALUE etype, mesg;
    int n;

    etype = eRuntimeError;
    mesg = Qnil;
    switch (n = rb_scan_args(argc, argv, "02", &arg1, &arg2)) {
      case 1:
	mesg = arg1;
	break;
      case 2:
	etype = arg1;
	if (obj_is_kind_of(etype, eGlobalExit)) {
	    etype = CLASS_OF(etype);
	}
	else {
	    Check_Type(etype, T_CLASS);
	}
	mesg  = arg2;
	break;
    }

    if (!NIL_P(mesg)) {
	Check_Type(mesg, T_STRING);
	if (n == 2 || !obj_is_kind_of(mesg, eException)) {
	    mesg = exc_new3(etype, mesg);
	}
    }

    PUSH_FRAME();		/* fake frame */
    *the_frame = *_frame.prev->prev;
    rb_raise(mesg);
    POP_FRAME();
}

int
iterator_p()
{
    if (the_frame->iter) return TRUE;
    return FALSE;
}

static VALUE
f_iterator_p()
{
    if (the_frame->prev && the_frame->prev->iter) return TRUE;
    return FALSE;
}

VALUE
rb_yield_0(val, self)
    VALUE val;
    volatile VALUE self;
{
    NODE *node;
    NODE *state;
    volatile VALUE result = Qnil;
    struct BLOCK *block;
    struct SCOPE *old_scope;
    struct FRAME frame;

    if (!iterator_p()) {
	Raise(eLocalJumpError, "yield called out of iterator");
    }

    PUSH_VARS();
    PUSH_CLASS();
    block = the_block;
    frame = block->frame;
    frame.prev = the_frame;
    the_frame = &(frame);
    old_scope = the_scope;
    the_scope = block->scope;
    the_block = block->prev;
    the_dyna_vars = block->d_vars;
    the_class = block->class;
    if (!self) self = block->self;
    node = block->body;
    if (block->var) {
	if (nd_type(block->var) == NODE_MASGN)
	    massign(self, block->var, val);
	else
	    assign(self, block->var, val);
    }
    PUSH_ITER(block->iter);
    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
      redo:
	if (!node) {
	    result = Qnil;
	}
	else if (nd_type(node) == NODE_CFUNC) {
	    result = (*node->nd_cfnc)(val, node->nd_argc, self);
	}
	else {
	    result = rb_eval(self, node);
	}
    }
    else {
	switch (state->nd_tag) {
	  case TAG_REDO:
	    state = 0;
	    goto redo;
	  case TAG_NEXT:
	    state = 0;
	    result = Qnil;
	    break;
	  case TAG_BREAK:
	  case TAG_RETURN:
	    state->nd_tlev = block->level;
	    state->nd_tag = IN_BLOCK|state->nd_tag;
	    break;
	  default:
	    break;
	}
    }
    POP_TAG();
    POP_ITER();
    POP_CLASS();
    POP_VARS();
    the_block = block;
    the_frame = the_frame->prev;
    the_scope = old_scope;
    if (state) JUMP_TAG(state);
    return result;
}

VALUE
rb_yield(val)
    VALUE val;
{
    return rb_yield_0(val, 0);
}

static VALUE
f_loop()
{
    for (;;) { rb_yield(Qnil); }
}

static VALUE
massign(self, node, val)
    VALUE self;
    NODE *node;
    VALUE val;
{
    NODE *list;
    int i, len;

    list = node->nd_head;

    if (val) {
	if (TYPE(val) != T_ARRAY) {
	    val = rb_to_a(val);
	}
	len = RARRAY(val)->len;
	for (i=0; list && i<len; i++) {
	    assign(self, list->nd_head, RARRAY(val)->ptr[i]);
	    list = list->nd_next;
	}
	if (node->nd_args) {
	    if (!list && i<len) {
		assign(self, node->nd_args, ary_new4(len-i, RARRAY(val)->ptr+i));
	    }
	    else {
		assign(self, node->nd_args, ary_new2(0));
	    }
	}
    }
    else if (node->nd_args) {
	assign(self, node->nd_args, Qnil);
    }
    while (list) {
	assign(self, list->nd_head, Qnil);
	list = list->nd_next;
    }
    return val;
}

static void
assign(self, lhs, val)
    VALUE self;
    NODE *lhs;
    VALUE val;
{
    switch (nd_type(lhs)) {
      case NODE_GASGN:
	rb_gvar_set(lhs->nd_entry, val);
	break;

      case NODE_IASGN:
	rb_ivar_set(self, lhs->nd_vid, val);
	break;

      case NODE_LASGN:
	if (the_scope->local_vars == 0)
	    Bug("unexpected iterator variable assignment");
	the_scope->local_vars[lhs->nd_cnt] = val;
	break;

      case NODE_DASGN:
	dyna_var_asgn(lhs->nd_vid, val);
	break;

      case NODE_CASGN:
	rb_const_set(the_class, lhs->nd_vid, val);
	break;

      case NODE_CALL:
	{
	    VALUE recv;
	    recv = rb_eval(self, lhs->nd_recv);
	    if (!lhs->nd_args->nd_head) {
		/* attr set */
		rb_funcall2(recv, lhs->nd_mid, 1, &val);
	    }
	    else {
		/* array set */
		VALUE args;

		args = rb_eval(self, lhs->nd_args);
		RARRAY(args)->ptr[RARRAY(args)->len-1] = val;
		rb_apply(recv, lhs->nd_mid, args);
	    }
	}
	break;

      default:
	Bug("bug in variable assignment");
	break;
    }
}

VALUE
rb_iterate(it_proc, data1, bl_proc, data2)
    VALUE (*it_proc)(), (*bl_proc)();
    void *data1, *data2;
{
    NODE *state;
    volatile VALUE retval = Qnil;
    NODE *node = NEW_CFUNC(bl_proc, data2);
    VALUE self = TopSelf;
    int tag_level;

  iter_retry:
    PUSH_ITER(ITER_PRE);
    PUSH_BLOCK(0, node);
    PUSH_TAG();

    state = EXEC_TAG();
    if (state == 0) {
	retval = (*it_proc)(data1);
    }
    POP_TAG();

    tag_level = the_block->level;
    POP_BLOCK();
    POP_ITER();

    if (state) {
	switch (state->nd_tag) {
	  case TAG_RETRY:
	    goto iter_retry;

	  case IN_BLOCK|TAG_BREAK:
	    if (state->nd_tlev != tag_level) {
		JUMP_TAG(state);
	    }
	    retval = Qnil;
	    break;

	  case IN_BLOCK|TAG_RETURN:
	    if (state->nd_tlev == tag_level) {
		state->nd_tag &= ~IN_BLOCK;
	    }
	    /* fall through */
	  default:
	    JUMP_TAG(state);
	}
    }
    return retval;
}

static int
handle_rescue(self, node)
    VALUE self;
    NODE *node;
{
    int argc; VALUE *argv; /* used in SETUP_ARGS */

    if (!node->nd_args) {
	return obj_is_kind_of(errinfo, eException);
    }

    PUSH_ITER(ITER_NOT);
    SETUP_ARGS(node->nd_args);
    POP_ITER();
    while (argc--) {
	if (!obj_is_kind_of(argv[0], cModule)) {
	    TypeError("class or module required for rescue clause");
	}
	if (obj_is_kind_of(errinfo, argv[0])) return 1;
	argv++;
    }
    return 0;
}

VALUE
rb_rescue(b_proc, data1, r_proc, data2)
    VALUE (*b_proc)(), (*r_proc)();
    void *data1, *data2;
{
    NODE *state;
    volatile VALUE result;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
      retry_entry:
	result = (*b_proc)(data1);
    }
    else {
	if (state->nd_tag == TAG_RAISE) { 
	    if (r_proc) {
		PUSH_TAG();
		if ((state = EXEC_TAG()) == 0) {
		    result = (*r_proc)(data2, errinfo);
		}
		POP_TAG();
		if (state && state->nd_tag == TAG_RETRY) {
		    state = 0;
		    goto retry_entry;
		}
	    }
	    else {
		result = Qnil;
		state = 0;
	    }
	    if (state == 0) {
		errat = Qnil;
	    }
	}
    }
    POP_TAG();
    if (state) JUMP_TAG(state);

    return result;
}

VALUE
rb_ensure(b_proc, data1, e_proc, data2)
    VALUE (*b_proc)(), (*e_proc)();
    void *data1, *data2;
{
    NODE *state;
    volatile VALUE result = Qnil;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	result = (*b_proc)(data1);
    }
    POP_TAG();

    (*e_proc)(data2);
    if (state) {
	JUMP_TAG(state);
    }
    return result;
}

static int last_call_status;
#define CSTAT_NOEX  1
#define CSTAT_VCALL 2

static VALUE
f_missing(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE desc = 0;
    ID    id;
    char *format = 0;
    char *file = sourcefile;
    int   line = sourceline;

    id = FIX2INT(argv[0]);
    argc--; argv++;

    switch (TYPE(obj)) {
      case T_NIL:
	format = "undefined method `%s' for nil";
	break;
      case T_TRUE:
	format = "undefined method `%s' for TRUE";
	break;
      case T_FALSE:
	format = "undefined method `%s' for FALSE";
	break;
      case T_OBJECT:
	desc = obj_as_string(obj);
	break;
      default:
	desc = rb_inspect(obj);
	break;
    }
    if (desc) {
	if (last_call_status & CSTAT_NOEX) {
	    format = "private method `%s' called for %s(%s)";
	}
	else if (iterator_p()) {
	    format = "undefined iterator `%s' for %s(%s)";
	}
	else if (last_call_status & CSTAT_VCALL) {
	    char *mname = rb_id2name(id);

	    if (('a' <= mname[0] && mname[0] <= 'z') || mname[0] == '_') {
		format = "undefined local variable or method `%s' for %s(%s)";
	    }
	}
	if (!format) {
	    format = "undefined method `%s' for %s(%s)";
	}
	if (RSTRING(desc)->len > 65) {
	    desc = any_to_s(obj);
	}
    }

    sourcefile = file;
    sourceline = line;
    PUSH_FRAME();		/* fake frame */
    *the_frame = *_frame.prev->prev;

    NameError(format,
	      rb_id2name(id),
	      desc?(char*)RSTRING(desc)->ptr:"",
	      desc?rb_class2name(CLASS_OF(obj)):"");
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

    return rb_funcall2(obj, rb_intern("method_missing"), argc+1, nargv);
}

#ifdef DJGPP
# define STACK_LEVEL_MAX 65535
#else
#ifdef __human68k__
extern int _stacksize;
# define STACK_LEVEL_MAX (_stacksize - 4096)
#else
# define STACK_LEVEL_MAX 655350
#endif
#endif
extern VALUE *gc_stack_start;
static int
stack_length()
{
    VALUE pos;

#ifdef sparc
    return gc_stack_start - &pos + 0x80;
#else
    return (&pos < gc_stack_start) ? gc_stack_start - &pos
	                           : &pos - gc_stack_start;
#endif
}

static VALUE
rb_call(class, recv, mid, argc, argv, scope)
    struct RClass *class;
    VALUE recv;
    ID    mid;
    int argc;			/* OK */
    VALUE *argv;		/* OK */
    int scope;
{
    NODE *body, *b2;		/* OK */
    int    noex;
    ID     id = mid;
    struct cache_entry *ent;
    volatile VALUE result = Qnil;
    int itr;
    enum node_type type;
    static int tick;

  again:
    /* is it in the method cache? */
    ent = cache + EXPR1(class, mid);
    if (ent->mid == mid && ent->class == class) {
	class = ent->origin;
	id   = ent->mid0;
	noex  = ent->noex;
	body  = ent->method;
    }
    else if ((body = rb_get_method_body(&class, &id, &noex)) == 0) {
	return rb_undefined(recv, mid, argc, argv, scope==2?CSTAT_VCALL:0);
    }

    /* receiver specified form for private method */
    if (noex == NOEX_PRIVATE && scope == 0)
	return rb_undefined(recv, mid, argc, argv, CSTAT_NOEX);

    switch (the_iter->iter) {
      case ITER_PRE:
	itr = ITER_CUR;
	break;
      case ITER_CUR:
      default:
	itr = ITER_NOT;
	break;
    }

    type = nd_type(body);
    if (type == NODE_ZSUPER) {
	/* for re-scoped/renamed method */
	mid = id;
	if (scope == 0) scope = 1;
	if (class->super == 0) {
	    /* origin is the Module, so need to scan superclass hierarchy. */
	    struct RClass *cl = class;

	    class = (struct RClass*)RBASIC(recv)->class;
	    while (class) {
		if (class->m_tbl == cl->m_tbl)
		    break;
		class = class->super;
	    }
	}
	else {
	    class = class->super;
	}
	goto again;
    }

    if ((++tick & 0xfff) == 0 && stack_length() > STACK_LEVEL_MAX)
	Fatal("stack level too deep");

    PUSH_ITER(itr);
    PUSH_FRAME();
    the_frame->last_func = id;
    the_frame->last_class = class;
    the_frame->argc = argc;
    the_frame->argv = argv;

    switch (type) {
      case NODE_CFUNC:
	{
	    int len = body->nd_argc;

	    if (len >= 0 && argc != len) {
		ArgError("Wrong # of arguments(%d for %d)", argc, len);
	    }

	    switch (len) {
	      case -2:
		result = (*body->nd_cfnc)(recv, ary_new4(argc, argv));
		break;
	      case -1:
		result = (*body->nd_cfnc)(argc, argv, recv);
		break;
	      case 0:
		result = (*body->nd_cfnc)(recv);
		break;
	      case 1:
		result = (*body->nd_cfnc)(recv, argv[0]);
		break;
	      case 2:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1]);
		break;
	      case 3:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2]);
		break;
	      case 4:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3]);
		break;
	      case 5:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4]);
		break;
	      case 6:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5]);
		break;
	      case 7:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6]);
		break;
	      case 8:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6], argv[7]);
		break;
	      case 9:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6], argv[7], argv[8]);
		break;
	      case 10:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6], argv[7], argv[8],
					  argv[6], argv[7], argv[8],
					  argv[9]);
		break;
	      case 11:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6], argv[7], argv[8],
					  argv[6], argv[7], argv[8],
					  argv[9], argv[10]);
		break;
	      case 12:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6], argv[7], argv[8],
					  argv[6], argv[7], argv[8],
					  argv[9], argv[10], argv[11]);
		break;
	      case 13:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6], argv[7], argv[8],
					  argv[6], argv[7], argv[8],
					  argv[9], argv[10], argv[11],
					  argv[12]);
		break;
	      case 14:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6], argv[7], argv[8],
					  argv[6], argv[7], argv[8],
					  argv[9], argv[10], argv[11],
					  argv[12], argv[13]);
		break;
	      case 15:
		result = (*body->nd_cfnc)(recv, argv[0], argv[1], argv[2],
					  argv[3], argv[4], argv[5],
					  argv[6], argv[7], argv[8],
					  argv[6], argv[7], argv[8],
					  argv[9], argv[10], argv[11],
					  argv[12], argv[13], argv[14]);
		break;
	      default:
		if (len < 0) {
		    Bug("bad argc(%d) specified for `%s(%s)'",
			len, rb_class2name((VALUE)class), rb_id2name(mid));
		}
		else {
		    ArgError("too many arguments(%d)", len);
		}
		break;
	    }
	}
	break;

	/* for attr get/set */
      case NODE_ATTRSET:
      case NODE_IVAR:
	result = rb_eval(recv, body);
	break;

      default:
	{
	    NODE  *state;
	    VALUE *local_vars;

	    PUSH_SCOPE();

	    if (body->nd_rval) the_frame->cbase = body->nd_rval;
	    if (body->nd_tbl) {
		local_vars = ALLOCA_N(VALUE, body->nd_tbl[0]+1);
		*local_vars++ = (VALUE)body;
		memclear(local_vars, body->nd_tbl[0]);
		the_scope->local_tbl = body->nd_tbl;
		the_scope->local_vars = local_vars;
	    }
	    else {
		local_vars = the_scope->local_vars = 0;
		the_scope->local_tbl  = 0;
	    }
	    b2 = body = body->nd_body;

	    PUSH_TAG();
	    PUSH_VARS();

	    if ((state = EXEC_TAG()) == 0) {
		if (nd_type(body) == NODE_BLOCK) {
		    NODE *node = body->nd_head;
		    int i;

		    if (nd_type(node) != NODE_ARGS) {
			Bug("no argument-node");
		    }

		    body = body->nd_next;
		    i = node->nd_cnt;
		    if (i > argc) {
			ArgError("Wrong # of arguments(%d for %d)", argc, i);
		    }
		    if (node->nd_rest == -1) {
			int opt = argc - i;
			NODE *optnode = node->nd_opt;

			while (optnode) {
			    opt--;
			    optnode = optnode->nd_next;
			}
			if (opt > 0) {
			    ArgError("Wrong # of arguments(%d for %d)",
				     argc, argc-opt);
			}
		    }

		    if (local_vars) {
			if (i > 0) {
			    MEMCPY(local_vars, argv, VALUE, i);
			}
			argv += i; argc -= i;
			if (node->nd_opt) {
			    NODE *opt = node->nd_opt;

			    while (opt && argc) {
				assign(recv, opt->nd_head, *argv);
				argv++; argc--;
				opt = opt->nd_next;
			    }
			    rb_eval(recv, opt);
			}
			if (node->nd_rest >= 0) {
			    if (argc > 0)
				local_vars[node->nd_rest]=ary_new4(argc,argv);
			    else
				local_vars[node->nd_rest]=ary_new2(0);
			}
		    }
		}
		else if (nd_type(body) == NODE_ARGS) {
		    body = 0;
		}
		if (trace_func) {
		    call_trace_func("call", b2->file, nd_line(b2),
				    recv, the_frame->last_func);
		}
		result = rb_eval(recv, body);
	    }
	    POP_VARS();
	    POP_TAG();
	    POP_SCOPE();
	    if (trace_func) {
		char *file = the_frame->prev->file;
		int line = the_frame->prev->line;
		if (!file) {
		    file = sourcefile;
		    line = sourceline;
		}
		call_trace_func("return", file, line, 0, the_frame->last_func);
	    }
	    if (state) {
		switch (state->nd_tag) {
		  case TAG_NEXT:
		    Raise(eLocalJumpError, "unexpected next");
		    break;
		  case TAG_BREAK:
		    Raise(eLocalJumpError, "unexpected break");
		    break;
		  case TAG_REDO:
		    Raise(eLocalJumpError, "unexpected redo");
		    break;
		  case TAG_RETURN:
		    result = state->nd_tval;
		    break;
		  case TAG_RETRY:
		    if (!iterator_p()) {
			Raise(eLocalJumpError, "retry outside of rescue clause");
		    }
		  default:
		    JUMP_TAG(state);
		}
	    }
	}
    }
    POP_FRAME();
    POP_ITER();
    return result;
}

VALUE
rb_apply(recv, mid, args)
    VALUE recv;
    struct RArray *args;
    ID mid;
{
    int argc;
    VALUE *argv;

    argc = RARRAY(args)->len;
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, 1);
}

static VALUE
f_send(argc, argv, recv)
    int argc;
    VALUE *argv;
    VALUE recv;
{
    VALUE vid;
    ID mid;

    if (argc == 0) ArgError("no method name given");

    vid = argv[0]; argc--; argv++;
    if (TYPE(vid) == T_STRING) {
	mid = rb_intern(RSTRING(vid)->ptr);
    }
    else {
	mid = NUM2INT(vid);
    }
    PUSH_ITER(iterator_p()?ITER_PRE:ITER_NOT);
    vid = rb_call(CLASS_OF(recv), recv, mid, argc, argv, 1);
    POP_ITER();

    return vid;
}

#include <varargs.h>

VALUE
rb_funcall(recv, mid, n, va_alist)
    VALUE recv;
    ID mid;
    int n;
    va_dcl
{
    va_list ar;
    VALUE *argv;

    if (n > 0) {
	int i;

	argv = ALLOCA_N(VALUE, n);

	va_start(ar);
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

static VALUE
backtrace(lev)
    int lev;
{
    struct FRAME *frame = the_frame;
    char buf[BUFSIZ];
    VALUE ary;
    int slev = safe_level;

    safe_level = 0;
    ary = ary_new();
    if (lev < 0) {
	if (frame->last_func) {
	    sprintf(buf, "%s:%d:in `%s'", sourcefile, sourceline,
		    rb_id2name(frame->last_func));
	}
	else {
	    sprintf(buf, "%s:%d", sourcefile, sourceline);
	}
	ary_push(ary, str_new2(buf));
    }
    else {
	while (lev-- > 0) {
	    frame = frame->prev;
	    if (!frame) return Qnil;
	}
    }
    while (frame && frame->file) {
	if (frame->prev && frame->prev->last_func) {
	    sprintf(buf, "%s:%d:in `%s'",
		    frame->file, frame->line,
		    rb_id2name(frame->prev->last_func));
	}
	else {
	    sprintf(buf, "%s:%d", frame->file, frame->line);
	}
	ary_push(ary, str_new2(buf));
	frame = frame->prev;
    }
    safe_level = slev;
    return ary;
}

static VALUE
f_caller(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE level;
    int lev;

    rb_scan_args(argc, argv, "01", &level);

    if (NIL_P(level)) lev = 1;
    else lev = NUM2INT(level);
    if (lev < 0) ArgError("negative level(%d)", lev);

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
    return the_frame->last_func;
}

static NODE*
compile(src)
    struct RString *src;
{
    NODE *node;

    Check_Type(src, T_STRING);

    node = compile_string(sourcefile, src->ptr, src->len);

    if (nerrs == 0) return node;
    return 0;
}

static VALUE
eval(self, src, scope)
    VALUE self;
    struct RString *src;
    struct RData *scope;
{
    struct BLOCK *data;
    volatile VALUE result = Qnil;
    NODE *state;
    volatile VALUE old_block;
    volatile VALUE old_scope;
    volatile VALUE old_d_vars;
    struct FRAME frame;
    char *file = sourcefile;
    int line = sourceline;
    volatile int iter = the_frame->iter;

    if (!NIL_P(scope)) {
	if (TYPE(scope) != T_DATA || scope->dfree != blk_free) {
	    TypeError("wrong argument type %s (expected Proc/Binding)",
		      rb_class2name(CLASS_OF(scope)));
	}

	Data_Get_Struct(scope, struct BLOCK, data);

	/* PUSH BLOCK from data */
	frame = data->frame;
	frame.prev = the_frame;
	the_frame = &(frame);
	old_scope = (VALUE)the_scope;
	the_scope = data->scope;
	old_block = (VALUE)the_block;
	the_block = data->prev;
	old_d_vars = (VALUE)the_dyna_vars;
	the_dyna_vars = data->d_vars;

	self = data->self;
	the_frame->iter = data->iter;
    }
    else {
	if (the_frame->prev) {
	    the_frame->iter = the_frame->prev->iter;
	}
    }
    PUSH_CLASS();
    the_class = (struct RClass*)((NODE*)the_frame->cbase)->nd_clss;

    rb_in_eval++;
    if (TYPE(the_class) == T_ICLASS) {
	the_class = (struct RClass*)RBASIC(the_class)->class;
    }
    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	compile(src);
	if (nerrs > 0) {
	    compile_error("eval()");
	}
	result = eval_node(self);
    }
    POP_TAG();
    POP_CLASS();
    rb_in_eval--;
    if (!NIL_P(scope)) {
	the_frame = the_frame->prev;
	the_scope = (struct SCOPE*)old_scope;
	the_block = (struct BLOCK*)old_block;
	the_dyna_vars = (struct RVarmap*)old_d_vars;
    }
    else {
	the_frame->iter = iter;
    }
    if (state) {
	VALUE err ;

	switch (state->nd_tag) {
	  case TAG_RAISE:
	    sourcefile = file;
	    sourceline = line;
	    if (strcmp(sourcefile, "(eval)") == 0) {
		err = errinfo;
		if (sourceline > 1) {
		    err = RARRAY(errat)->ptr[0];
		    str_cat(err, ": ", 2);
		    str_cat(err, RSTRING(errinfo)->ptr, RSTRING(errinfo)->len);
		}
		errat = Qnil;
		rb_raise(exc_new3(CLASS_OF(errinfo), err));
	    }
	    rb_raise(Qnil);
	}
	JUMP_TAG(state);
    }

    return result;
}

static VALUE
f_eval(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE src, scope;

    rb_scan_args(argc, argv, "11", &src, &scope);

    Check_SafeStr(src);
    return eval(self, src, scope);
}

VALUE rb_load_path;

char *dln_find_file();

static char*
find_file(file)
    char *file;
{
    extern VALUE rb_load_path;
    VALUE vpath;
    char *path;

    if (file[0] == '/') return file;
#if defined(MSDOS) || defined(NT) || defined(__human68k__)
    if (file[0] == '\\') return file;
    if (file[1] == ':') return file;
#endif

    if (rb_load_path) {
	int i;

	Check_Type(rb_load_path, T_ARRAY);
	for (i=0;i<RARRAY(rb_load_path)->len;i++) {
	    Check_SafeStr(RARRAY(rb_load_path)->ptr[i]);
	}
#if !defined(MSDOS) && !defined(NT) && !defined(__human68k__)
	vpath = ary_join(rb_load_path, str_new2(":"));
#else
	vpath = ary_join(rb_load_path, str_new2(";"));
#endif
	Check_SafeStr(vpath);
	path = RSTRING(vpath)->ptr;
    }
    else {
	path = 0;
    }

    return dln_find_file(file, path);
}

VALUE
f_load(obj, fname)
    VALUE obj;
    struct RString *fname;
{
    NODE *state;
    char *file;
    volatile ID last_func;

    Check_SafeStr(fname);
    if (fname->ptr[0] == '~') {
	fname = (struct RString*)file_s_expand_path(0, fname);
    }
    file = find_file(fname->ptr);
    if (!file) LoadError("No such file to load -- %s", fname->ptr);

    PUSH_TAG();
    PUSH_CLASS();
    the_class = (struct RClass*)cObject;
    PUSH_SCOPE();
    if (top_scope->local_tbl) {
	int len = top_scope->local_tbl[0]+1;
	ID *tbl = ALLOC_N(ID, len);
	VALUE *vars = ALLOCA_N(VALUE, len);
	*vars++ = 0;
	MEMCPY(tbl, top_scope->local_tbl, ID, len);
	MEMCPY(vars, top_scope->local_vars, ID, len-1);
	the_scope->local_tbl = tbl;
	the_scope->local_vars = vars;
    }

    state = EXEC_TAG();
    last_func = the_frame->last_func;
    the_frame->last_func = 0;
    if (state == 0) {
	rb_in_eval++;
	rb_load_file(file);
	rb_in_eval--;
	if (nerrs == 0) {
	    eval_node(TopSelf);
	}
    }
    the_frame->last_func = last_func;
    if (the_scope->flag == SCOPE_ALLOCA && the_scope->local_tbl) {
	free(the_scope->local_tbl);
    }
    POP_SCOPE();
    POP_CLASS();
    POP_TAG();
    if (nerrs > 0) {
	rb_raise(errinfo);
    }
    if (state) JUMP_TAG(state);

    return TRUE;
}

static VALUE rb_features;

static int
rb_provided(feature)
    char *feature;
{
    struct RArray *features = RARRAY(rb_features);
    VALUE *p, *pend;
    char *f;
    int len;

    p = features->ptr;
    pend = p + features->len;
    while (p < pend) {
	Check_Type(*p, T_STRING);
	f = RSTRING(*p)->ptr;
	if (strcmp(f, feature) == 0) return TRUE;
	len = strlen(feature);
	if (strncmp(f, feature, len) == 0
	    && (strcmp(f+len, ".rb") == 0 ||strcmp(f+len, ".o") == 0)) {
	    return TRUE;
	}
	p++;
    }
    return FALSE;
}

#ifdef THREAD
static int thread_loading();
static void thread_loading_done();
#endif

void
rb_provide(feature)
    char *feature;
{
    char *buf, *ext;

    if (!rb_provided(feature)) {
	ext = strrchr(feature, '.');
	if (strcmp(DLEXT, ext) == 0) {
	    buf = ALLOCA_N(char, strlen(feature)+1);
	    strcpy(buf, feature);
	    ext = strrchr(buf, '.');
	    strcpy(ext, ".o");
	    feature = buf;
	}
	ary_push(rb_features, str_new2(feature));
    }
}

VALUE
f_require(obj, fname)
    VALUE obj;
    struct RString *fname;
{
    char *ext, *file, *feature, *buf;
    volatile VALUE load;

    Check_SafeStr(fname);
    if (rb_provided(fname->ptr))
	return FALSE;

    ext = strrchr(fname->ptr, '.');
    if (ext) {
	if (strcmp(".rb", ext) == 0) {
	    feature = file = fname->ptr;
	    file = find_file(file);
	    if (file) goto rb_load;
	}
	else if (strcmp(".o", ext) == 0) {
	    file = feature = fname->ptr;
	    if (strcmp(".o", DLEXT) != 0) {
		buf = ALLOCA_N(char, strlen(fname->ptr)+sizeof(DLEXT)+1);
		strcpy(buf, feature);
		ext = strrchr(buf, '.');
		strcpy(ext, DLEXT);
		file = find_file(buf);
	    }
	    if (file) goto dyna_load;
	}
	else if (strcmp(DLEXT, ext) == 0) {
	    feature = fname->ptr;
	    file = find_file(feature);
	    if (file) goto dyna_load;
	}
    }
    buf = ALLOCA_N(char, strlen(fname->ptr) + 5);
    sprintf(buf, "%s.rb", fname->ptr);
    file = find_file(buf);
    if (file) {
	fname = (struct RString*)str_new2(file);
	feature = buf;
	goto rb_load;
    }
    sprintf(buf, "%s%s", fname->ptr, DLEXT);
    file = find_file(buf);
    if (file) {
	feature = buf;
	goto dyna_load;
    }
    LoadError("No such file to load -- %s", fname->ptr);

  dyna_load:
#ifdef THREAD
    if (thread_loading(feature)) return FALSE;
    else {
	NODE *state;
	PUSH_TAG();
	if ((state = EXEC_TAG()) == 0) {
#endif
	    load = str_new2(file);
	    file = RSTRING(load)->ptr;
	    dln_load(file);
	    rb_provide(feature);
#ifdef THREAD
	}
	POP_TAG();
	thread_loading_done();
	if (state) JUMP_TAG(state);
    }
#endif
    return TRUE;

  rb_load:
#ifdef THREAD
    if (thread_loading(feature)) return FALSE;
    else {
	NODE *state;
	PUSH_TAG();
	if ((state = EXEC_TAG()) == 0) {
#endif
	    f_load(obj, fname);
	    rb_provide(feature);
#ifdef THREAD
	}
	POP_TAG();
	thread_loading_done();
	if (state) JUMP_TAG(state);
    }
#endif
    return TRUE;
}

static void
set_method_visibility(self, argc, argv, ex)
    VALUE self;
    int argc;
    VALUE *argv;
    int ex;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_export_method(self, rb_to_id(argv[i]), ex);
    }
}

static VALUE
mod_public(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    set_method_visibility(module, argc, argv, NOEX_PUBLIC);
    return module;
}

static VALUE
mod_private(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    return module;
}

static VALUE
mod_public_method(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PUBLIC);
    return obj;
}

static VALUE
mod_private_method(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PRIVATE);
    return obj;
}

static VALUE
mod_modfunc(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    int i;
    ID id;
    NODE *body;

    rb_clear_cache();
    set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    for (i=0; i<argc; i++) {
	id = rb_to_id(argv[i]);
	body = search_method(module, id, 0);
	if (body == 0 || body->nd_body == 0) {
	    NameError("undefined method `%s' for module `%s'",
		      rb_id2name(id), rb_class2name(module));
	}
	rb_add_method(rb_singleton_class(module), id, body->nd_body, NOEX_PUBLIC);
    }
    return module;
}

static VALUE
mod_include(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    int i;

    for (i=0; i<argc; i++) {
	Check_Type(argv[i], T_MODULE);
	rb_include_module(module, argv[i]);
    }
    return module;
}

VALUE
class_s_new(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE obj = obj_alloc(class);

    if (FL_TEST(class, FL_SINGLETON)) {
	TypeError("can't create instance of virtual class");
    }
    obj = obj_alloc(class);
    PUSH_ITER(iterator_p()?ITER_PRE:ITER_NOT);
    rb_funcall2(obj, init, argc, argv);
    POP_ITER();
    return obj;
}


VALUE
class_new_instance(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE obj;

    if (FL_TEST(class, FL_SINGLETON)) {
	TypeError("can't create instance of virtual class");
    }
    obj = obj_alloc(class);
    PUSH_ITER(iterator_p()?ITER_PRE:ITER_NOT);
    rb_funcall2(obj, init, argc, argv);
    POP_ITER();
    return obj;
}

static VALUE
top_include(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_secure(4);
    return mod_include(argc, argv, cObject);
}

void
rb_extend_object(obj, module)
    VALUE obj, module;
{
    rb_include_module(rb_singleton_class(obj), module);
}

static VALUE
mod_extend_object(mod, obj)
    VALUE mod, obj;
{
    rb_extend_object(obj, mod);
    return obj;
}

static VALUE
obj_extend(argc, argv, obj)
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

VALUE f_trace_var();
VALUE f_untrace_var();

extern void rb_str_setter();

static void
errat_setter(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    int i;
    static char *err = "value of $@ must be Array of String";

    if (!NIL_P(val)) {
	if (TYPE(val) != T_ARRAY) {
	    TypeError(err);
	}
	for (i=0;i<RARRAY(val)->len;i++) {
	    if (TYPE(RARRAY(val)->ptr[i]) != T_STRING) {
		TypeError(err);
	    }
	}
    }
    *var = val;
}

static VALUE
f_catch(dmy, tag)
    VALUE dmy, tag;
{
    NODE *state;
    ID t;
    VALUE val;

    t = rb_to_id(tag);
    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	val = rb_yield(tag);
    }
    POP_TAG();
    if (state) {
	if (state->nd_tag == TAG_THROW && state->nd_tlev == t) {
	    return state->nd_tval;
	}
	JUMP_TAG(state);
    }
    return val;
}

static VALUE
f_throw(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE tag, value;
    ID t;

    rb_scan_args(argc, argv, "11", &tag, &value);
    t = rb_to_id(tag);
    JUMP_TAG3(TAG_THROW, value, t);
    /* not reached */
}

void
Init_eval()
{
    init = rb_intern("initialize");
    eqq = rb_intern("===");
    each = rb_intern("each");

    aref = rb_intern("[]");
    aset = rb_intern("[]=");

    rb_global_variable(&top_scope);
    rb_global_variable(&eval_tree);
    rb_global_variable(&the_dyna_vars);

    rb_define_hooked_variable("$@", &errat, 0, errat_setter);
    rb_define_hooked_variable("$!", &errinfo, 0, rb_str_setter);

    rb_define_global_function("eval", f_eval, -1);
    rb_define_global_function("iterator?", f_iterator_p, 0);
    rb_define_global_function("method_missing", f_missing, -1);
    rb_define_global_function("loop", f_loop, 0);

    rb_define_method(mKernel, "respond_to?", obj_respond_to, -1);

    rb_define_global_function("break", f_break, 0);
    rb_define_alias(mKernel,  "break!", "break");
    rb_define_global_function("next", f_next, 0);
    rb_define_alias(mKernel,  "next!", "next");
    rb_define_alias(mKernel,  "continue", "next");
    rb_define_global_function("redo", f_redo, 0);
    rb_define_alias(mKernel,  "redo!", "redo");
    rb_define_global_function("retry", f_retry, 0);
    rb_define_alias(mKernel,  "retry!", "retry");
    rb_define_global_function("raise", f_raise, -1);
    rb_define_alias(mKernel,  "fail", "raise");

    rb_define_global_function("caller", f_caller, -1);

    rb_define_global_function("exit", f_exit, -1);
    rb_define_global_function("abort", f_abort, 0);

    rb_define_global_function("catch", f_catch, 1);
    rb_define_global_function("throw", f_throw, -1);

    rb_define_method(mKernel, "send", f_send, -1);

    rb_define_private_method(cModule, "include", mod_include, -1);
    rb_define_private_method(cModule, "public", mod_public, -1);
    rb_define_private_method(cModule, "private", mod_private, -1);
    rb_define_private_method(cModule, "module_function", mod_modfunc, -1);
    rb_define_method(cModule, "method_defined?", mod_method_defined, 1);
    rb_define_method(cModule, "extend_object", mod_extend_object, 1);
    rb_define_method(cModule, "public_class_method", mod_public_method, -1);
    rb_define_method(cModule, "private_class_method", mod_private_method, -1);

    rb_define_method(CLASS_OF(TopSelf), "include", top_include, -1);
    rb_define_method(mKernel, "extend", obj_extend, -1);

    rb_define_global_function("trace_var", f_trace_var, -1);
    rb_define_global_function("untrace_var", f_untrace_var, -1);

    rb_define_global_function("set_trace_func", set_trace_func, 1);

    rb_define_virtual_variable("$SAFE", safe_getter, safe_setter);
}

VALUE f_autoload();

void
Init_load()
{
    rb_load_path = ary_new();
    rb_define_readonly_variable("$:", &rb_load_path);
    rb_define_readonly_variable("$-I", &rb_load_path);
    rb_define_readonly_variable("$LOAD_PATH", &rb_load_path);

    rb_features = ary_new();
    rb_define_readonly_variable("$\"", &rb_features);

    rb_define_global_function("load", f_load, 1);
    rb_define_global_function("require", f_require, 1);
    rb_define_global_function("autoload", f_autoload, 2);
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
    gc_mark_frame(&data->frame);
    gc_mark(data->scope);
    gc_mark(data->var);
    gc_mark(data->body);
    gc_mark(data->self);
    gc_mark(data->d_vars);
}

static void
blk_free(data)
    struct BLOCK *data;
{
    free(data->frame.argv);
}

static VALUE
f_binding(self)
    VALUE self;
{
    struct BLOCK *data;
    VALUE bind;

    PUSH_BLOCK(0,0);
    bind = Data_Make_Struct(cData, struct BLOCK, blk_mark, blk_free, data);
    MEMCPY(data, the_block, struct BLOCK, 1);

    data->iter = f_iterator_p();
    data->frame.last_func = 0;
    data->frame.argv = ALLOC_N(VALUE, data->frame.argc);
    MEMCPY(data->frame.argv, the_block->frame.argv, VALUE, data->frame.argc);

    scope_dup(data->scope);
    POP_BLOCK();

    return bind;
}

#define PROC_TAINT FL_USER0
#define PROC_T3    FL_USER1
#define PROC_T4    FL_USER2
#define PROC_T5    (FL_USER1|FL_USER2)
#define PROC_TMASK (FL_USER1|FL_USER2)

static VALUE
proc_s_new(class)
    VALUE class;
{
    VALUE proc;
    struct BLOCK *data;

    if (!iterator_p() && !f_iterator_p()) {
	ArgError("tryed to create Procedure-Object out of iterator");
    }

    proc = Data_Make_Struct(class, struct BLOCK, blk_mark, blk_free, data);
    *data = *the_block;

#ifdef THREAD
    data->orig_thread = thread_current();
#endif
    data->iter = f_iterator_p();
    data->frame.argv = ALLOC_N(VALUE, data->frame.argc);
    MEMCPY(data->frame.argv, the_block->frame.argv, VALUE, data->frame.argc);

    scope_dup(data->scope);
    if (safe_level >= 3) {
	FL_SET(proc, PROC_TAINT);
	switch (safe_level) {
	  case 3:
	    FL_SET(proc, PROC_T3);
	    break;
	  case 4:
	    FL_SET(proc, PROC_T4);
	    break;
	  case 5:
	    FL_SET(proc, PROC_T5);
	    break;
	}
    }

    return proc;
}

VALUE
f_lambda()
{
    return proc_s_new(cProc);
}

static VALUE
proc_call(proc, args)
    VALUE proc, args;
{
    struct BLOCK *data;
    volatile VALUE result = Qnil;
    NODE *state;
    int tag_level;
    volatile int orphan;
    volatile int safe = safe_level;

    if (TYPE(args) == T_ARRAY) {
	switch (RARRAY(args)->len) {
	  case 0:
	    args = 0;
	    break;
	  case 1:
	    args = RARRAY(args)->ptr[0];
	    break;
	}
    }

    Data_Get_Struct(proc, struct BLOCK, data);

    if (data->scope && (data->scope->flag & SCOPE_NOSTACK)) {
	orphan = 1;
    }
    else {
#ifdef THREAD
	if (data->orig_thread != thread_current()) {
	    orphan = 1;
	}
	else
#endif
	orphan = 0;
    }
    if (orphan) {/* orphan procedure */
	if (iterator_p()) {
	    data->frame.iter = ITER_CUR;
	}
	else {
	    data->frame.iter = ITER_NOT;
	}
    }

    /* PUSH BLOCK from data */
    PUSH_BLOCK2(data);
    PUSH_ITER(ITER_CUR);
    the_frame->iter = ITER_CUR;
    if (FL_TEST(proc, PROC_TAINT)) {
	switch (RBASIC(proc)->flags & PROC_TMASK) {
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

    PUSH_TAG();
    state = EXEC_TAG();
    if (state == 0) {
	result = rb_yield(args);
    }
    POP_TAG();

    POP_ITER();
    tag_level = the_block->level;
    POP_BLOCK();
    safe_level = safe;

    if (state) {
	if (orphan) {/* orphan procedure */
	    switch (state->nd_tag) {
	      case TAG_BREAK:	/* never happen */
	      case IN_BLOCK|TAG_BREAK:
		if (state->nd_tlev == tag_level)
		    Raise(eLocalJumpError, "break from proc-closure");
		break;
	      case TAG_RETRY:
		Raise(eLocalJumpError, "retry from proc-closure");
		break;
	      case TAG_RETURN:	/* never happen */
	      case IN_BLOCK|TAG_RETURN:
		if (state->nd_tlev == tag_level)
		    Raise(eLocalJumpError, "return from proc-closure");
		break;
	    }
	}
	else if (state->nd_tlev == tag_level) {
	    state->nd_tag &= ~IN_BLOCK;
	}
	JUMP_TAG(state);
    }
    return result;
}

void
Init_Proc()
{
    eLocalJumpError = rb_define_class("LocalJumpError", eException);

    cProc = rb_define_class("Proc", cObject);
    rb_define_singleton_method(cProc, "new", proc_s_new, 0);

    rb_define_method(cProc, "call", proc_call, -2);
    rb_define_global_function("proc", f_lambda, 0);
    rb_define_global_function("lambda", f_lambda, 0);
    rb_define_global_function("binding", f_binding, 0);
}

#ifdef THREAD

static VALUE eThreadError;

int thread_pending = 0;

static VALUE cThread;

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

extern VALUE last_status;

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

typedef struct thread * thread_t;

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
    struct RClass *class;
    struct RVarmap *dyna_vars;
    struct BLOCK *block;
    struct iter *iter;
    struct tag *tag;

    VALUE trace;

    char *file;
    int   line;

    VALUE errat, errinfo;
    VALUE last_status;
    VALUE last_line;
    VALUE last_match;

    int safe;

    enum  thread_status status;
    int wait_for;
    int fd;
    double delay;
    thread_t join;

    int abort;

    VALUE thread;
};

static thread_t curr_thread;
static int num_waiting_on_fd;
static int num_waiting_on_timer;
static int num_waiting_on_join;

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

static thread_t main_thread;

#define ADJ(addr) (void*)(((VALUE*)(addr)-th->stk_pos)+th->stk_ptr)
#define STACK(addr) (th->stk_pos<(addr) && (addr)<th->stk_pos+th->stk_len)

static void
thread_mark(th)
    thread_t th;
{
    struct FRAME *frame;
    struct BLOCK *block;

    gc_mark(th->result);
    if (th->stk_ptr) {
	gc_mark_locations(th->stk_ptr, th->stk_ptr+th->stk_len);
#if defined(THINK_C) || defined(__human68k__)
	gc_mark_locations(th->stk_ptr+2, th->stk_ptr+th->stk_len+2);
#endif
    }
    gc_mark(th->thread);
    if (th->join) gc_mark(th->join->thread);

    gc_mark(th->scope);
    gc_mark(th->dyna_vars);
    gc_mark(th->errat);
    gc_mark(th->errinfo);
    gc_mark(th->last_line);
    gc_mark(th->last_match);

    /* mark data in copied stack */
    frame = th->frame;
    while (frame && frame != top_frame) {
	frame = ADJ(frame);
	if (frame->argv && !STACK(frame->argv)) {
	    gc_mark_frame(frame);
	}
	frame = frame->prev;
    }
    block = th->block;
    while (block) {
	block = ADJ(block);
	if (block->frame.argv && !STACK(block->frame.argv)) {
	    gc_mark_frame(&block->frame);
	}
	block = block->prev;
    }
}

void
gc_mark_threads()
{
    thread_t th;

    FOREACH_THREAD(th) {
	thread_mark(th);
    } END_FOREACH(th);
}

static void
thread_free(th)
    thread_t th;
{
    if (th->stk_ptr) free(th->stk_ptr);
    th->stk_ptr = 0;
}

static thread_t
thread_check(data)
    struct RData *data;
{
    if (TYPE(data) != T_DATA || data->dfree != thread_free) {
	TypeError("wrong argument type %s (expected Thread)",
		  rb_class2name(CLASS_OF(data)));
    }
    return (thread_t)data->data;
}

VALUE lastline_get();
void lastline_set();
VALUE backref_get();
void backref_set();

static void
thread_save_context(th)
    thread_t th;
{
    VALUE v;

    th->stk_len = stack_length();
    th->stk_pos = (gc_stack_start<(VALUE*)&v)?gc_stack_start
				             :gc_stack_start - th->stk_len;
    if (th->stk_len > th->stk_max)  {
	th->stk_max = th->stk_len;
	REALLOC_N(th->stk_ptr, VALUE, th->stk_max);
    }
    FLUSH_REGISTER_WINDOWS;
    MEMCPY(th->stk_ptr, th->stk_pos, VALUE, th->stk_len);

    th->frame = the_frame;
    th->scope = the_scope;
    th->class = the_class;
    th->dyna_vars = the_dyna_vars;
    th->block = the_block;
    th->iter = the_iter;
    th->tag = prot_tag;
    th->errat = errat;
    th->errinfo = errinfo;
    th->last_status = last_status;
    th->last_line = lastline_get();
    th->last_match = backref_get();
    th->safe = safe_level;

    th->trace = trace_func;
    th->file = sourcefile;
    th->line = sourceline;
}

static void thread_restore_context();

static void
stack_extend(th, exit)
    thread_t th;
    int exit;
{
    VALUE space[1024];

    memset(space, 0, 1);	/* prevent array from optimization */
    thread_restore_context(th, exit);
}

static int   th_raise_argc;
static VALUE th_raise_argv[2];
static char *th_raise_file;
static int   th_raise_line;

static void
thread_restore_context(th, exit)
    thread_t th;
    int exit;
{
    VALUE v;
    static thread_t tmp;
    static int ex;

    if (!th->stk_ptr) Bug("unsaved context");

    if (&v < gc_stack_start) {
	/* Stack grows downward */
	if (&v > th->stk_pos) stack_extend(th, exit);
    }
    else {
	/* Stack grows upward */
	if (&v < th->stk_pos + th->stk_len) stack_extend(th, exit);
    }

    the_frame = th->frame;
    the_scope = th->scope;
    the_class = th->class;
    the_dyna_vars = th->dyna_vars;
    the_block = th->block;
    the_iter = th->iter;
    prot_tag = th->tag;
    the_class = th->class;
    errat = th->errat;
    errinfo = th->errinfo;
    last_status = th->last_status;
    safe_level = th->safe;

    trace_func = th->trace;
    sourcefile = th->file;
    sourceline = th->line;

    tmp = th;
    ex = exit;
    FLUSH_REGISTER_WINDOWS;
    MEMCPY(tmp->stk_pos, tmp->stk_ptr, VALUE, tmp->stk_len);

    lastline_set(tmp->last_line);
    backref_set(tmp->last_match);

    switch (ex) {
      case 1:
	JUMP_TAG2(TAG_FATAL, INT2FIX(0));
	break;

      case 2:
	rb_interrupt();
	break;

      case 3:
	the_frame->last_func = 0;
	sourcefile = th_raise_file;
	sourceline = th_raise_line;
	f_raise(th_raise_argc, th_raise_argv);
	break;

      default:
	longjmp(tmp->context, 1);
    }
}

static void
thread_ready(th)
    thread_t th;
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
thread_remove()
{
    thread_ready(curr_thread);
    curr_thread->status = THREAD_KILLED;
    curr_thread->prev->next = curr_thread->next;
    curr_thread->next->prev = curr_thread->prev;
    thread_schedule();
}

static int
thread_dead(th)
    thread_t th;
{
    return th->status == THREAD_KILLED;
}

static void
thread_deadlock()
{
    curr_thread = main_thread;
    th_raise_argc = 1;
    th_raise_argv[0] = exc_new2(eFatal, "Thread: deadlock");
    th_raise_file = sourcefile;
    th_raise_line = sourceline;
    f_abort();
}

void
thread_schedule()
{
    thread_t next;
    thread_t th;
    thread_t curr;

  select_err:
    thread_pending = 0;
    if (curr_thread == curr_thread->next) return;

    next = 0;
    curr = curr_thread;		/* starting thread */

    while (curr->status == THREAD_KILLED) {
	curr = curr->prev;
    }

    FOREACH_THREAD_FROM(curr,th) {
       if (th->status != THREAD_STOPPED && th->status != THREAD_KILLED) {
           next = th;
           break;
       }
    }
    END_FOREACH_FROM(curr,th); 

    if (num_waiting_on_join) {
	curr_thread->file = sourcefile;	
	curr_thread->line = sourceline;	
	FOREACH_THREAD_FROM(curr,th) {
	    if ((th->wait_for & WAIT_JOIN) && thread_dead(th->join)) {
		th->join = 0;
		th->wait_for &= ~WAIT_JOIN;
		th->status = THREAD_RUNNABLE;
		num_waiting_on_join--;
		if (!next) next = th;
	    }
	}
	END_FOREACH_FROM(curr,th);
    }

    if (num_waiting_on_fd > 0 || num_waiting_on_timer > 0) {
	fd_set readfds;
	struct timeval delay_tv, *delay_ptr;
	double delay, now;

	int n, max;

	do {
	    max = 0;
	    FD_ZERO(&readfds);
	    if (num_waiting_on_fd > 0) {
		FOREACH_THREAD_FROM(curr,th) {
		    if (th->wait_for & WAIT_FD) {
			FD_SET(th->fd, &readfds);
			if (th->fd > max) max = th->fd;
		    }
		}
		END_FOREACH_FROM(curr,th);
	    }

	    delay = DELAY_INFTY;
	    if (num_waiting_on_timer > 0) {
		now = timeofday();
		FOREACH_THREAD_FROM(curr,th) {
		    if (th->wait_for & WAIT_TIME) {
			if (th->delay <= now) {
			    th->delay = 0.0;
			    th->wait_for &= ~WAIT_TIME;
			    th->status = THREAD_RUNNABLE;
			    num_waiting_on_timer--;
			    next = th;
			} else if (th->delay < delay) {
			    delay = th->delay;
			}
		    }
		}
		END_FOREACH_FROM(curr,th);
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
		    delay_tv.tv_usec = (delay - (double)delay_tv.tv_sec) * 1e6;
		    delay_ptr = &delay_tv;
		}

		n = select(max+1, &readfds, 0, 0, delay_ptr);
		if (n < 0) {
		    if (trap_pending) rb_trap_exec();
		    goto select_err;
		}
		if (n > 0) {
		    /* Some descriptors are ready. 
		       Make the corresponding threads runnable. */
		    FOREACH_THREAD_FROM(curr,th) {
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
		    END_FOREACH_FROM(curr,th);
		}
	    }
	    /* The delays for some of the threads should have expired.
	       Go through the loop once more, to check the delays. */
	} while (!next && delay != DELAY_INFTY);
    }

    if (!next) {
	FOREACH_THREAD_FROM(curr,th) {
	    fprintf(stderr, "%s:%d:deadlock 0x%x: %d:%d %s\n", 
		    th->file, th->line, th->thread, th->status,
		    th->wait_for, th==main_thread?"(main)":"");
	}
	END_FOREACH_FROM(curr,th);
	/* raise fatal error to main thread */
	thread_deadlock();
    }
    if (next == curr_thread) {
	return;
    }

    /* context switch */
    if (curr == curr_thread) {
	thread_save_context(curr);
	if (setjmp(curr->context)) {
	    return;
	}
    }

    curr_thread = next;
    if (next->status == THREAD_TO_KILL) {
	/* execute ensure-clause if any */
	thread_restore_context(next, 1);
    }
    thread_restore_context(next, 0);
}

void
thread_wait_fd(fd)
    int fd;
{
    if (curr_thread == curr_thread->next) return;

    curr_thread->status = THREAD_STOPPED;
    curr_thread->fd = fd;
    num_waiting_on_fd++;
    curr_thread->wait_for |= WAIT_FD;
    thread_schedule();
}

void
thread_fd_writable(fd)
    int fd;
{
    struct timeval zero;
    fd_set fds;

    if (curr_thread == curr_thread->next) return;

    zero.tv_sec = zero.tv_usec = 0;
    for (;;) {
	FD_ZERO(&fds);
	FD_SET(fd, &fds);
	if (select(fd+1, 0, &fds, 0, &zero) == 1) break;
	thread_schedule();
    }
}

void
thread_wait_for(time)
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
		time.tv_usec += 1e6;
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
    thread_schedule();
}

void thread_sleep_forever();

int
thread_alone()
{
    return curr_thread == curr_thread->next;
}

int
thread_select(max, read, write, except, timeout)
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
	    thread_sleep_forever();
	    return 0;
	}
	thread_wait_for(*timeout);
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
		    tv.tv_usec = (d - (double)tv.tv_sec) * 1e6;
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

        thread_schedule();
	CHECK_INTS;
    }
}

static VALUE
thread_join(dmy, thread)
    VALUE dmy;
    VALUE thread;
{
    thread_t th = thread_check(thread);

    if (thread_dead(th)) return thread;
    if ((th->wait_for & WAIT_JOIN) && th->join == curr_thread)
	Raise(eThreadError, "Thread.join: deadlock");
    curr_thread->status = THREAD_STOPPED;
    curr_thread->join = th;
    num_waiting_on_join++;
    curr_thread->wait_for |= WAIT_JOIN;
    thread_schedule();

    return thread;
}

static VALUE
thread_current()
{
    return curr_thread->thread;
}

static VALUE
thread_main()
{
    return main_thread->thread;
}

static VALUE
thread_wakeup(thread)
    VALUE thread;
{
    thread_t th = thread_check(thread);

    if (th->status == THREAD_KILLED) Raise(eThreadError, "killed thread");
    thread_ready(th);

    return thread;
}

static VALUE
thread_run(thread)
    VALUE thread;
{
    thread_wakeup(thread);
    if (!thread_critical) thread_schedule();

    return thread;
}

static VALUE
thread_kill(thread)
    VALUE thread;
{
    thread_t th = thread_check(thread);

    if (th->status == THREAD_TO_KILL || th->status == THREAD_KILLED)
	return thread; 
    if (th == th->next || th == main_thread) rb_exit(0);

    thread_ready(th);
    th->status = THREAD_TO_KILL;
    thread_schedule();
    return Qnil;		/* not reached */
}

static VALUE
thread_s_kill(obj, th)
    VALUE obj, th;
{
    return thread_kill(th);
}

static VALUE
thread_exit()
{
    return thread_kill(curr_thread->thread);
}

static VALUE
thread_pass()
{
    thread_schedule();
    return Qnil;
}

static VALUE
thread_stop_method(thread)
    VALUE thread;
{
    thread_t th = thread_check(thread);

    thread_critical = 0;
    th->status = THREAD_STOPPED;
    thread_schedule();

    return thread;
}

static VALUE
thread_stop()
{
    thread_stop_method(curr_thread->thread);
    return Qnil;
}

void
thread_sleep(sec)
    int sec;
{
    if (curr_thread == curr_thread->next) {
	TRAP_BEG;
	sleep(sec);
	TRAP_END;
	return;
    }
    thread_wait_for(time_timeval(INT2FIX(sec)));
}

void
thread_sleep_forever()
{
    if (curr_thread == curr_thread->next) {
	TRAP_BEG;
	sleep((32767<<16)+32767);
	TRAP_END;
	return;
    }

    num_waiting_on_timer++;
    curr_thread->delay = DELAY_INFTY;
    curr_thread->wait_for |= WAIT_TIME;
    curr_thread->status = THREAD_STOPPED;
    thread_schedule();
}

static int thread_abort;

static VALUE
thread_s_abort_exc()
{
    return thread_abort?TRUE:FALSE;
}

static VALUE
thread_s_abort_exc_set(self, val)
    VALUE self, val;
{
    thread_abort = RTEST(val);
    return val;
}

static VALUE
thread_abort_exc(thread)
    VALUE thread;
{
    thread_t th = thread_check(thread);

    return th->abort?TRUE:FALSE;
}

static VALUE
thread_abort_exc_set(thread, val)
    VALUE thread, val;
{
    thread_t th = thread_check(thread);

    th->abort = RTEST(val);
    return val;
}

static thread_t
thread_alloc()
{
    thread_t th;

    th = ALLOC(struct thread);
    th->status = THREAD_RUNNABLE;

    th->status = 0;
    th->result = 0;
    th->errinfo = Qnil;
    th->errat = Qnil;

    th->stk_ptr = 0;
    th->stk_len = 0;
    th->stk_max = 0;
    th->wait_for = 0;
    th->fd = 0;
    th->delay = 0.0;
    th->join = 0;

    th->frame = 0;
    th->scope = 0;
    th->class = 0;
    th->dyna_vars = 0;
    th->block = 0;
    th->iter = 0;
    th->tag = 0;
    th->errat = 0;
    th->errinfo = 0;
    th->last_status = 0;
    th->last_line = 0;
    th->last_match = 0;
    th->abort = 0;

    th->thread = data_object_alloc(cThread, th, 0, thread_free);

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
    if (!thread_critical) {
	if (trap_immediate) {
	    trap_immediate = 0;
	    thread_schedule();
	}
	else thread_pending = 1;
    }
}
#else
int thread_tick = THREAD_TICK;
#endif

VALUE
thread_create(fn, arg)
    VALUE (*fn)();
    void *arg;
{
    thread_t th = thread_alloc();
    NODE *state;

#if defined(HAVE_SETITIMER) && !defined(__BOW__)
    static init = 0;

    if (!init) {
	struct itimerval tval;

#ifdef POSIX_SIGNAL
	posix_signal(SIGVTALRM, catch_timer);
#else
	signal(SIGVTALRM, catch_timer);
#endif

	tval.it_interval.tv_sec = 0;
	tval.it_interval.tv_usec = 100000;
	tval.it_value = tval.it_interval;
	setitimer(ITIMER_VIRTUAL, &tval, NULL);

	init = 1;
    }
#endif

    thread_save_context(curr_thread);
    if (setjmp(curr_thread->context)) {
	return th->thread;
    }

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	thread_save_context(th);
	if (setjmp(th->context) == 0) {
	    curr_thread = th;
	    th->result = (*fn)(arg, th);
	}
    }
    POP_TAG();
    if (state) {
	if (state->nd_tag == TAG_THROW) {
	    char *mesg;
	    char *tag = rb_id2name(state->nd_tlev);

	    mesg = ALLOCA_N(char, strlen(tag) + 64);

	    sprintf(mesg, "uncaught throw `%s' in thread 0x%x\n",
		    tag, th->thread);
	    curr_thread->errinfo = exc_new2(eThreadError, mesg);
	    curr_thread->errat = make_backtrace();
	}
	else if (th->status != THREAD_TO_KILL && !NIL_P(errinfo)) {
	    if (state->nd_tag == TAG_FATAL ||
		obj_is_kind_of(errinfo, eSystemExit)) {
		/* fatal error or global exit within this thread */
		/* need to stop whole script */
		main_thread->errat = errat;
		main_thread->errinfo = errinfo;
		thread_cleanup();
	    }
	    else if (thread_abort || curr_thread->abort) {
		f_abort();
	    }
	    else {
		curr_thread->errat = errat;
		curr_thread->errinfo = errinfo;
	    }
	}
    }
    thread_remove();
    return 0;
}

static void
thread_yield(arg, th) 
    int arg;
    thread_t th;
{
    scope_dup(the_block->scope);
    rb_yield(th->thread);
}

static VALUE
thread_start()
{
    if (!iterator_p()) {
	Raise(eThreadError, "must be called as iterator");
    }
    return thread_create(thread_yield, 0);
}

static VALUE
thread_value(thread)
    VALUE thread;
{
    thread_t th = thread_check(thread);

    thread_join(0, thread);
    if (!NIL_P(th->errinfo)) {
	errat = make_backtrace();
	ary_unshift(errat, ary_entry(th->errat, 0));
	sourcefile = 0;		/* kludge to print errat */
	rb_raise(th->errinfo);
    }

    return th->result;
}

static VALUE
thread_status(thread)
    VALUE thread;
{
    thread_t th = thread_check(thread);

    if (thread_dead(th)) {
	if (NIL_P(th->errinfo)) return FALSE;
	return Qnil;
    }

    return TRUE;
}

static VALUE
thread_stopped(thread)
    VALUE thread;
{
    thread_t th = thread_check(thread);

    if (thread_dead(th)) return TRUE;
    if (th->status == THREAD_STOPPED) return TRUE;
    return FALSE;
}

static void
thread_wait_other_threads()
{
    /* wait other threads to terminate */
    while (curr_thread != curr_thread->next) {
	thread_schedule();
    }
}

static void
thread_cleanup()
{
    thread_t th;

    if (curr_thread != curr_thread->next->prev) {
	curr_thread = curr_thread->prev;
    }

    FOREACH_THREAD(th) {
	if (th != curr_thread && th->status != THREAD_KILLED) {
	    th->status = THREAD_TO_KILL;
	    th->wait_for = 0;
	}
    }
    END_FOREACH(th);
}

int thread_critical;

static VALUE
thread_get_critical()
{
    return thread_critical?TRUE:FALSE;
}

static VALUE
thread_set_critical(obj, val)
    VALUE obj, val;
{
    thread_critical = RTEST(val);
    return val;
}

void
thread_interrupt()
{
    thread_critical = 0;
    thread_ready(main_thread);
    if (curr_thread == main_thread) {
	rb_interrupt();
    }
    thread_save_context(curr_thread);
    if (setjmp(curr_thread->context)) {
	return;
    }
    curr_thread = main_thread;
    thread_restore_context(curr_thread, 2);
}

static VALUE
thread_raise(argc, argv, thread)
    int argc;
    VALUE *argv;
    VALUE thread;
{
    thread_t th = thread_check(thread);

    if (thread_dead(th)) return thread;
    if (curr_thread == th) {
	f_raise(argc, argv);
    }

    thread_save_context(curr_thread);
    if (setjmp(curr_thread->context)) {
	return thread;
    }

    rb_scan_args(argc, argv, "11", &th_raise_argv[0], &th_raise_argv[1]);
    thread_ready(th);
    curr_thread = th;

    th_raise_argc = argc;
    th_raise_file = sourcefile;
    th_raise_line = sourceline;
    thread_restore_context(curr_thread, 3);
    return Qnil;		/* not reached */
}

static thread_t loading_thread;
static int loading_nest;

static int
thread_loading(feature)
    char *feature;
{
    if (curr_thread != curr_thread->next && loading_thread) {
	while (loading_thread != curr_thread) {
	    thread_schedule();
	    CHECK_INTS;
	}
	if (rb_provided(feature)) return TRUE; /* no need to load */
    }

    loading_thread = curr_thread;
    loading_nest++;

    return FALSE;
}

static void
thread_loading_done()
{
    if (--loading_nest == 0) {
	loading_thread = 0;
    }
}

void
Init_Thread()
{
    eThreadError = rb_define_class("ThreadError", eException);
    cThread = rb_define_class("Thread", cObject);

    rb_define_singleton_method(cThread, "new", thread_start, 0);
    rb_define_singleton_method(cThread, "start", thread_start, 0);
    rb_define_singleton_method(cThread, "fork", thread_start, 0);

    rb_define_singleton_method(cThread, "stop", thread_stop, 0);
    rb_define_singleton_method(cThread, "kill", thread_s_kill, 1);
    rb_define_singleton_method(cThread, "exit", thread_exit, 0);
    rb_define_singleton_method(cThread, "pass", thread_pass, 0);
    rb_define_singleton_method(cThread, "join", thread_join, 1);
    rb_define_singleton_method(cThread, "current", thread_current, 0);
    rb_define_singleton_method(cThread, "main", thread_main, 0);

    rb_define_singleton_method(cThread, "critical", thread_get_critical, 0);
    rb_define_singleton_method(cThread, "critical=", thread_set_critical, 1);

    rb_define_singleton_method(cThread, "abort_on_exception", thread_s_abort_exc, 0);
    rb_define_singleton_method(cThread, "abort_on_exception=", thread_s_abort_exc_set, 1);

    rb_define_method(cThread, "run", thread_run, 0);
    rb_define_method(cThread, "wakeup", thread_wakeup, 0);
    rb_define_method(cThread, "stop", thread_stop_method, 0);
    rb_define_method(cThread, "exit", thread_kill, 0);
    rb_define_method(cThread, "value", thread_value, 0);
    rb_define_method(cThread, "status", thread_status, 0);
    rb_define_method(cThread, "alive?", thread_status, 0);
    rb_define_method(cThread, "stop?", thread_stopped, 0);
    rb_define_method(cThread, "raise", thread_raise, -1);

    rb_define_method(cThread, "abort_on_exception", thread_abort_exc, 0);
    rb_define_method(cThread, "abort_on_exception=", thread_abort_exc_set, 1);

    /* allocate main thread */
    main_thread = thread_alloc();
}
#endif
