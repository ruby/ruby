/************************************************

  eval.c -

  $Author$
  $Date$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "node.h"
#include "env.h"
#include "sig.h"

#include <stdio.h>
#include <setjmp.h>
#include "st.h"
#include "dln.h"

#ifndef HAVE_STRING_H
char *strrchr _((char*,char));
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifndef setjmp
#ifdef HAVE__SETJMP
#define setjmp(env) _setjmp(env)
#define longjmp(env,val) _longjmp(env,val)
#endif
#endif

VALUE cProc;
static VALUE cBinding;
static VALUE proc_call _((VALUE,VALUE));
static VALUE f_binding _((VALUE));
static void f_END _((void));
static VALUE f_iterator_p _((void));
static VALUE block_pass _((VALUE,NODE*));
static VALUE cMethod;
static VALUE method_proc _((VALUE));

static int scope_vmode;
#define SCOPE_PUBLIC    0
#define SCOPE_PRIVATE   1
#define SCOPE_PROTECTED 2
#define SCOPE_MODFUNC   5
#define SCOPE_MASK      7
#define SCOPE_SET(f)  do {scope_vmode=(f);} while(0)
#define SCOPE_TEST(f) (scope_vmode&(f))

#define CACHE_SIZE 0x200
#define CACHE_MASK 0x1ff
#define EXPR1(c,m) ((((int)(c)>>3)^(m))&CACHE_MASK)

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

    if (NIL_P(klass)) klass = cObject;
    body = NEW_METHOD(node, noex);
    st_insert(RCLASS(klass)->m_tbl, mid, body);
}

static NODE*
search_method(klass, id, origin)
    VALUE klass, *origin;
    ID id;
{
    NODE *body;

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
    NODE *body;
    struct cache_entry *ent;

    if ((body = search_method(klass, id, &origin)) == 0) {
	return 0;
    }
    if (!body->nd_body) return 0;

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
    orig = search_method(klass, def, &origin);
    if (!orig || !orig->nd_body) {
	if (TYPE(klass) == T_MODULE) {
	    orig = search_method(cObject, def, &origin);
	}
    }
    if (!orig || !orig->nd_body) {
	NameError("undefined method `%s' for `%s'",
		  rb_id2name(def), rb_class2name(klass));
    }
    body = orig->nd_body;
    if (nd_type(body) == NODE_FBODY) { /* was alias */
	body = body->nd_head;
	def = body->nd_mid;
	origin = body->nd_orig;
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

    if (!st_delete(RCLASS(klass)->m_tbl, &mid, &body)) {
	NameError("method `%s' not defined in %s",
		  rb_id2name(mid), rb_class2name(klass));
    }
    rb_clear_cache_by_id(mid);
}

void
rb_remove_method(klass, name)
    VALUE klass;
    char *name;
{
    remove_method(klass, rb_intern(name));
}

void
rb_disable_super(klass, name)
    VALUE klass;
    char *name;
{
    VALUE origin;
    NODE *body;
    ID mid = rb_intern(name);

    body = search_method(klass, mid, &origin);
    if (!body || !body->nd_body) {
	NameError("undefined method `%s' for `%s'",
		  rb_id2name(mid), rb_class2name(klass));
    }
    if (origin == klass) {
	body->nd_noex |= NOEX_UNDEF;
    }
    else {
	rb_clear_cache_by_id(mid);
	rb_add_method(the_class, mid, 0, NOEX_UNDEF);
    }
}

void
rb_enable_super(klass, name)
    VALUE klass;
    char *name;
{
    VALUE origin;
    NODE *body;
    ID mid = rb_intern(name);

    body = search_method(klass, mid, &origin);
    if (!body || !body->nd_body || origin != klass) {
	NameError("undefined method `%s' for `%s'",
		  rb_id2name(mid), rb_class2name(klass));
    }
    body->nd_noex &= ~NOEX_UNDEF;
}

static void
rb_export_method(klass, name, noex)
    VALUE klass;
    ID name;
    int noex;
{
    NODE *body;
    VALUE origin;

    body = search_method(klass, name, &origin);
    if (!body && TYPE(klass) == T_MODULE) {
	body = search_method(cObject, name, &origin);
    }
    if (!body) {
	NameError("undefined method `%s' for `%s'",
		  rb_id2name(name), rb_class2name(klass));
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

static VALUE
method_boundp(klass, id, ex)
    VALUE klass;
    ID id;
    int ex;
{
    int noex;

    if (rb_get_method_body(&klass, &id, &noex)) {
	if (ex && noex & NOEX_PRIVATE)
	    return FALSE;
	return TRUE;
    }
    return FALSE;
}

int
rb_method_boundp(klass, id, ex)
    VALUE klass;
    ID id;
    int ex;
{
    if (method_boundp(klass, id, ex))
	return TRUE;
    return FALSE;
}

void
rb_attr(klass, id, read, write, ex)
    VALUE klass;
    ID id;
    int read, write, ex;
{
    char *name;
    char *buf;
    ID attr, attreq, attriv;
    int noex;

    if (!ex) noex = NOEX_PUBLIC;
    else {
	if (SCOPE_TEST(SCOPE_PRIVATE)) {
	    noex = NOEX_PRIVATE;
	    Warning("private attribute?");
	}
	else if (SCOPE_TEST(SCOPE_PROTECTED)) {
	    noex = NOEX_PROTECTED;
	}
	else {
	    noex = NOEX_PUBLIC;
	}
    }

    name = rb_id2name(id);
    attr = rb_intern(name);
    buf = ALLOCA_N(char,strlen(name)+2);
    sprintf(buf, "%s=", name);
    attreq = rb_intern(buf);
    sprintf(buf, "@%s", name);
    attriv = rb_intern(buf);
    if (read) {
	rb_add_method(klass, attr, NEW_IVAR(attriv), noex);
    }
    if (write) {
	rb_add_method(klass, attreq, NEW_ATTRSET(attriv), noex);
    }
}

static ID init, eqq, each, aref, aset, match;
VALUE errinfo = Qnil, errat = Qnil;
extern NODE *eval_tree0;
extern NODE *eval_tree;
extern int nerrs;

extern VALUE mKernel;
extern VALUE cModule;
extern VALUE eFatal;
extern VALUE eDefaultRescue;
extern VALUE eStandardError;
extern VALUE eInterrupt;
extern VALUE eSystemExit;
extern VALUE eException;
extern VALUE eRuntimeError;
extern VALUE eSyntaxError;
static VALUE eLocalJumpError;
static VALUE eSysStackError;
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
    VALUE klass;
    struct tag *tag;
    int iter;
    int vmode;
    struct RVarmap *d_vars;
#ifdef THREAD
    VALUE orig_thread;
#endif
    struct BLOCK *prev;
};
static struct BLOCK  *the_block;

#define PUSH_BLOCK(v,b) {		\
    struct BLOCK _block;		\
    _block.tag = prot_tag;		\
    _block.var = v;			\
    _block.body = b;			\
    _block.self = self;			\
    _block.frame = *the_frame;		\
    _block.klass = the_class;		\
    _block.frame.file = sourcefile;	\
    _block.frame.line = sourceline;	\
    _block.scope = the_scope;		\
    _block.d_vars = the_dyna_vars;	\
    _block.prev = the_block;		\
    _block.iter = the_iter->iter;	\
    _block.vmode = scope_vmode;		\
    the_block = &_block;

#define PUSH_BLOCK2(b) {		\
    struct BLOCK _block;		\
    _block = *b;			\
    _block.prev = the_block;		\
    the_block = &_block;

#define POP_BLOCK() 			\
   the_block = _block.prev; 		\
}

struct RVarmap *the_dyna_vars;
#define PUSH_VARS() {			\
    struct RVarmap * volatile _old;	\
    _old = the_dyna_vars;		\
    the_dyna_vars = 0;

#define POP_VARS()			\
    the_dyna_vars = _old;		\
}

static struct RVarmap*
new_dvar(id, value)
    ID id;
    VALUE value;
{
    NEWOBJ(vars, struct RVarmap);
    OBJSETUP(vars, 0, T_VARMAP);
    if (id == 0) {
	vars->id = (ID)value;
	vars->val = 0;
	vars->next = the_dyna_vars;
	the_dyna_vars = vars;
    }
    else if (the_dyna_vars) {
	vars->id = id;
	vars->val = value;
	vars->next = the_dyna_vars->next;
	the_dyna_vars->next = vars;
    }

    return vars;
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
    new_dvar(id, value);
    return value;
}

struct iter {
    int iter;
    struct iter *prev;
};
static struct iter *the_iter;

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

struct tag {
    jmp_buf buf;
    struct FRAME *frame;
    struct iter *iter;
    ID tag;
    VALUE retval;
    ID dst;
    struct tag *prev;
};
static struct tag *prot_tag;

#define PUSH_TAG(ptag) {		\
    struct tag _tag;			\
    _tag.retval = Qnil;			\
    _tag.frame = the_frame;		\
    _tag.iter = the_iter;		\
    _tag.prev = prot_tag;		\
    _tag.retval = Qnil;			\
    _tag.tag = ptag;			\
    _tag.dst = 0;			\
    prot_tag = &_tag;

#define PROT_NONE   0
#define PROT_FUNC   -1
#define PROT_THREAD -2

#define EXEC_TAG()    setjmp(prot_tag->buf)

#define JUMP_TAG(st) {			\
    the_frame = prot_tag->frame;	\
    the_iter = prot_tag->iter;		\
    longjmp(prot_tag->buf,(st));	\
}

#define POP_TAG()			\
    if (_tag.prev)			\
        _tag.prev->retval = _tag.retval;\
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

VALUE the_class;

#define PUSH_CLASS() {		\
    VALUE _class = the_class;	\

#define POP_CLASS() the_class = _class; }

#define PUSH_SCOPE() {			\
    int volatile _vmode = scope_vmode;	\
    struct SCOPE * volatile _old;	\
    NEWOBJ(_scope, struct SCOPE);	\
    OBJSETUP(_scope, 0, T_SCOPE);	\
    _scope->local_tbl = 0;		\
    _scope->local_vars = 0;		\
    _scope->flag = 0;			\
    _old = the_scope;			\
    the_scope = _scope;			\
    scope_vmode = SCOPE_PUBLIC;

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

static VALUE rb_eval _((VALUE,NODE*));
static VALUE eval _((VALUE,VALUE,VALUE,char*,int));
static NODE *compile _((VALUE,char*));

static VALUE rb_call _((VALUE,VALUE,ID,int,VALUE*,int));
static VALUE module_setup _((VALUE,NODE*));

static VALUE massign _((VALUE,NODE*,VALUE));
static void assign _((VALUE,NODE*,VALUE));

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
    if (str_tainted(x)) {
	if (safe_level > 0){
	    Raise(eSecurityError, "Insecure operation - %s",
		  rb_id2name(the_frame->last_func));
	}
	Warning("Insecure operation - %s",
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
static void call_trace_func _((char*,char*,int,VALUE,ID));

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
    VALUE einfo;

    if (NIL_P(errinfo)) return;

    if (!NIL_P(errat)) {
	VALUE mesg = RARRAY(errat)->ptr[0];

	if (NIL_P(mesg)) error_pos();
	else {
	    fwrite(RSTRING(mesg)->ptr, 1, RSTRING(mesg)->len, stderr);
	}
    }

    eclass = CLASS_OF(errinfo);
    einfo = obj_as_string(errinfo);
    if (eclass == eRuntimeError && RSTRING(einfo)->len == 0) {
	fprintf(stderr, ": unhandled exception\n");
    }
    else {
	VALUE epath;

	epath = rb_class_path(eclass);
	if (RSTRING(einfo)->len == 0) {
	    fprintf(stderr, ": ");
	    fwrite(RSTRING(epath)->ptr, 1, RSTRING(epath)->len, stderr);
	    putc('\n', stderr);
	}
	else {
	    UCHAR *tail  = 0;
	    int len = RSTRING(einfo)->len;

	    if (RSTRING(epath)->ptr[0] == '#') epath = 0;
	    if (tail = strchr(RSTRING(einfo)->ptr, '\n')) {
		len = tail - RSTRING(einfo)->ptr;
		tail++;		/* skip newline */
	    }
	    fprintf(stderr, ": ");
	    fwrite(RSTRING(einfo)->ptr, 1, len, stderr);
	    if (epath) {
		fprintf(stderr, " (");
		fwrite(RSTRING(epath)->ptr, 1, RSTRING(epath)->len, stderr);
		fprintf(stderr, ")\n");
	    }
	    if (tail) {
		fwrite(tail, 1, RSTRING(einfo)->len-len-1, stderr);
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

void rb_call_inits _((void));
void init_stack _((void));
void init_heap _((void));
void Init_ext _((void));
void gc_call_finalizer_at_exit _((void));

void
ruby_init()
{
    static struct FRAME frame;
    static struct iter iter;
    int state;

    the_frame = top_frame = &frame;
    the_iter = &iter;

    origenviron = environ;

    init_heap();
    PUSH_SCOPE();
    the_scope->local_vars = 0;
    the_scope->local_tbl  = 0;
    top_scope = the_scope;
    /* default visibility is private at toplevel */
    SCOPE_SET(SCOPE_PRIVATE);

    PUSH_TAG(PROT_NONE)
    if ((state = EXEC_TAG()) == 0) {
	rb_call_inits();
	the_class = cObject;
	the_frame->self = TopSelf;
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
    int state;

    PUSH_TAG(PROT_NONE)
    if ((state = EXEC_TAG()) == 0) {
	NODE *save;

	ruby_process_options(argc, argv);
	ext_init = 1;	/* Init_ext() called in ruby_process_options */
	save = eval_tree;
	eval_tree = 0;
	ruby_require_modules();
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

    if (eval_tree0) {
	tree = eval_tree0;
	eval_tree0 = 0;
	rb_eval(self, tree);
    }

    if (!eval_tree) return Qnil;

    tree = eval_tree;
    eval_tree = 0;

    result = rb_eval(self, tree);
    return result;
}

int rb_in_eval;

#ifdef THREAD
static void thread_cleanup _((void));
static void thread_wait_other_threads _((void));
static VALUE thread_current _((void));
#endif

static int exit_status;

static void exec_end_proc _((void));

void
ruby_run()
{
    int state;
    static int ex;

    if (nerrs > 0) exit(nerrs);

    init_stack();
    errat = Qnil;		/* clear for execution */

    PUSH_TAG(PROT_NONE);
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	if (!ext_init) Init_ext();
	eval_node(TopSelf);
    }
    POP_ITER();
    POP_TAG();

    if (state && !ex) ex = state;
    PUSH_TAG(PROT_NONE);
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	rb_trap_exit();
#ifdef THREAD
	thread_cleanup();
	thread_wait_other_threads();
#endif
	exec_end_proc();
	gc_call_finalizer_at_exit();
    }
    else {
	ex = state;
    }
    POP_ITER();
    POP_TAG();

    switch (ex & 0xf) {
      case 0:
	exit(0);

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
      default:
	Bug("Unknown longjmp status %d", ex);
	break;
    }
}

static void
compile_error(at)
    char *at;
{
    char *mesg;
    int len;

    mesg = str2cstr(errinfo, &len);
    nerrs = 0;
    errinfo = exc_new2(eSyntaxError, "compile error");
    if (at) {
	str_cat(errinfo, " in ", 4);
	str_cat(errinfo, at, strlen(at));
    }
    str_cat(errinfo, "\n", 1);
    str_cat(errinfo, mesg, len);
    rb_raise(errinfo);
}

VALUE
rb_eval_string(str)
    char *str;
{
    VALUE v;
    char *oldsrc = sourcefile;

    sourcefile = "(eval)";
    v = eval(TopSelf, str_new2(str), Qnil, 0, 0);
    sourcefile = oldsrc;

    return v;
}

void
rb_eval_cmd(cmd, arg)
    VALUE cmd, arg;
{
    int state;
    struct SCOPE *saved_scope;
    volatile int safe = rb_safe_level();

    if (TYPE(cmd) != T_STRING) {
	Check_Type(arg, T_ARRAY);
	rb_funcall2(cmd, rb_intern("call"),
		    RARRAY(arg)->len, RARRAY(arg)->ptr);
	return;
    }

    PUSH_CLASS();
    PUSH_TAG(PROT_NONE);
    saved_scope = the_scope;
    the_scope = top_scope;

    the_class = cObject;
    if (str_tainted(cmd)) {
	safe_level = 5;
    }

    if ((state = EXEC_TAG()) == 0) {
	eval(TopSelf, cmd, Qnil, 0, 0);
    }

    the_scope = saved_scope;
    safe_level = safe;
    POP_TAG();
    POP_CLASS();

    switch (state) {
      case 0:
	break;
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
    int state;

    PUSH_TAG(PROT_NONE);
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
    VALUE val = 0;		/* OK */
    int state;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	val = rb_eval(self, node);
    }
    POP_TAG();
    if (state == TAG_RAISE) {
      superclass_error:
	switch (nd_type(node)) {
	  case NODE_COLON2:
	    TypeError("undefined superclass `%s'", rb_id2name(node->nd_mid));
	  case NODE_CVAR:
	    TypeError("undefined superclass `%s'", rb_id2name(node->nd_vid));
	  default:
	    TypeError("superclass undefined");
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
	struct RClass *klass = RCLASS(cbase->nd_clss);

	if (klass->iv_tbl &&
	    st_lookup(klass->iv_tbl, id, 0)) {
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
mod_nesting()
{
    NODE *cbase = (NODE*)the_frame->cbase;
    VALUE ary = ary_new();

    while (cbase && cbase->nd_clss != cObject) {
	ary_push(ary, cbase->nd_clss);
	cbase = cbase->nd_next;
    }
    return ary;
}

static VALUE
mod_s_constants()
{
    NODE *cbase = (NODE*)the_frame->cbase;
    VALUE ary = ary_new();

    while (cbase && cbase->nd_clss != cObject) {
	mod_const_at(cbase->nd_clss, ary);
	cbase = cbase->nd_next;
    }

    mod_const_of(((NODE*)the_frame->cbase)->nd_clss, ary);
    return ary;
}

static VALUE
mod_remove_method(mod, name)
    VALUE mod, name;
{
    remove_method(mod, rb_to_id(name));
    return mod;
}

static VALUE
mod_undef_method(mod, name)
    VALUE mod, name;
{
    ID id = rb_to_id(name);

    rb_add_method(mod, id, 0, NOEX_PUBLIC);
    rb_clear_cache_by_id(id);
    return mod;
}

static VALUE
mod_alias_method(mod, newname, oldname)
    VALUE mod, newname, oldname;
{
    ID id = rb_to_id(newname);

    rb_alias(mod, id, rb_to_id(oldname));
    rb_clear_cache_by_id(id);
    return mod;
}

#if defined(C_ALLOCA) && defined(THREAD)
# define TMP_PROTECT NODE *__protect_tmp=0
# define TMP_ALLOC(type,n)						   \
    (__protect_tmp = node_newnode(NODE_ALLOCA,				   \
			     str_new(0,sizeof(type)*(n)),0,__protect_tmp), \
     (void*)RSTRING(__protect_tmp->nd_head)->ptr)
#else
# define TMP_PROTECT typedef int foobazzz
# define TMP_ALLOC(type,n) ALLOCA_N(type,n)
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
	    char *file = sourcefile;\
	    int line = sourceline;\
            int i;\
	    n = anode;\
	    argv = TMP_ALLOC(VALUE,argc);\
	    for (i=0;i<argc;i++) {\
		argv[i] = rb_eval(self,n->nd_head);\
		n=n->nd_next;\
	    }\
	    sourcefile = file;\
	    sourceline = line;\
        }\
        else {\
	    argc = 0;\
	    argv = 0;\
        }\
    }\
    else {\
        VALUE args = rb_eval(self,n);\
	char *file = sourcefile;\
	int line = sourceline;\
	if (TYPE(args) != T_ARRAY)\
	    args = rb_Array(args);\
        argc = RARRAY(args)->len;\
	argv = ALLOCA_N(VALUE, argc);\
	MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);\
	sourcefile = file;\
	sourceline = line;\
    }\
}

#define MATCH_DATA the_scope->local_vars[node->nd_cnt]

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
	if (the_frame->last_func == 0) return 0;
	else if (method_boundp(RCLASS(the_frame->last_class)->super,
			       the_frame->last_func, 1)) {
	    if (nd_type(node) == NODE_SUPER) {
		return arg_defined(self, node->nd_args, buf, "super");
	    }
	    return "super";
	}
	break;

      case NODE_FCALL:
      case NODE_VCALL:
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
	    return 0;
	}
      check_bound:
	if (method_boundp(val, node->nd_mid, nd_type(node)== NODE_CALL)) {
	    return arg_defined(self, node->nd_args, buf, "method");
	}
	break;

      case NODE_MATCH2:
      case NODE_MATCH3:
	return "method";

      case NODE_YIELD:
	if (iterator_p()) {
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
	if (ev_const_defined(the_frame->cbase, node->nd_vid)) {
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
	PUSH_TAG(PROT_NONE);
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

static int handle_rescue _((VALUE,NODE*));

static void blk_free();

static VALUE
obj_is_block(block)
    VALUE block;
{
    if (TYPE(block) == T_DATA && RDATA(block)->dfree == blk_free) {
	return TRUE;
    }
    return FALSE;
}

static VALUE
obj_is_proc(proc)
    VALUE proc;
{
    if (obj_is_block(proc) && obj_is_kind_of(proc, cProc)) {
	return TRUE;
    }
    return FALSE;
}

static VALUE
set_trace_func(obj, trace)
    VALUE obj, trace;
{
    if (NIL_P(trace)) {
	trace_func = 0;
	return Qnil;
    }
    if (!obj_is_proc(trace)) {
	TypeError("trace_func needs to be Proc");
    }
    return trace_func = trace;
}

static void
call_trace_func(event, file, line, self, id)
    char *event;
    char *file;
    int line;
    VALUE self;
    ID id;
{
    int state;
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
    PUSH_TAG(PROT_NONE);
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
	while (node) {
	    result = rb_eval(self, node->nd_head);
	    node = node->nd_next;
	}
	break;

      case NODE_POSTEXE:
	f_END();
	nd_set_type(node, NODE_NIL); /* exec just once */
	result = Qnil;
	break;

	/* begin .. end without clauses */
      case NODE_BEGIN:
	node = node->nd_body;
	goto again;

	/* nodes for speed-up(default match) */
      case NODE_MATCH:
	result = reg_match2(node->nd_head->nd_lit);
	break;

	/* nodes for speed-up(literal match) */
      case NODE_MATCH2:
	result = reg_match(rb_eval(self,node->nd_recv),
			   rb_eval(self,node->nd_value));
	break;

	/* nodes for speed-up(literal match) */
      case NODE_MATCH3:
        {
	    VALUE r = rb_eval(self,node->nd_recv);
	    VALUE l = rb_eval(self,node->nd_value);
	    if (TYPE(r) == T_STRING) {
		result = reg_match(l, r);
	    }
	    else {
		result = rb_funcall(r, match, 1, l);
	    }
	}
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

      case NODE_TRUE:
	RETURN(TRUE);

      case NODE_FALSE:
	RETURN(FALSE);

      case NODE_IF:
	sourceline = nd_line(node);
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
					self, the_frame->last_func);	
		    }
		    sourceline = nd_line(tag);
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
	PUSH_TAG(PROT_NONE);
	switch (state = EXEC_TAG()) {
	  case 0:
	    sourceline = nd_line(node);
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
	if (state) {
	    JUMP_TAG(state);
	}
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
	if (state) {
	    JUMP_TAG(state);
	}
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
		    char *file = sourcefile;
		    int line = sourceline;

		    recv = rb_eval(self, node->nd_iter);
		    PUSH_ITER(ITER_PRE);
		    sourcefile = file;
		    sourceline = line;
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

      case NODE_YIELD:
	result = rb_yield_0(rb_eval(self, node->nd_stts), 0);
	break;

      case NODE_RESCUE:
      retry_entry:
        {
	    volatile VALUE e_info = errinfo, e_at = errat;

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
			if (state == 0) {
			    errinfo = e_info;
			    errat = e_at;
			}
			else if (state == TAG_RETRY) {
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
	if (node->nd_stts) {
	    return_value(rb_eval(self, node->nd_stts));
	}
	return_check();
	JUMP_TAG(TAG_RETURN);
	break;

      case NODE_CALL:
	{
	    VALUE recv;
	    int argc; VALUE *argv; /* used in SETUP_ARGS */
	    TMP_PROTECT;

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
	    TMP_PROTECT;

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
	    TMP_PROTECT;

	    if (the_frame->last_class == 0) {	
		NameError("superclass method `%s' disabled",
			  rb_id2name(the_frame->last_func));
	    }
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
	    result = rb_call(RCLASS(the_frame->last_class)->super,
			     the_frame->self, the_frame->last_func,
			     argc, argv, 3);
	    POP_ITER();
	}
	break;

      case NODE_SCOPE:
	{
	    VALUE save = the_frame->cbase;

	    PUSH_SCOPE();
	    PUSH_TAG(PROT_NONE);
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
	    TMP_PROTECT;

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
	result = rb_eval(self, node->nd_value);
	the_scope->local_vars[node->nd_cnt] = result;
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
	    if (RTEST(verbose) &&
		ev_const_defined(the_frame->cbase, node->nd_vid)) {
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

      case NODE_BLOCK_ARG:
	if (the_scope->local_vars == 0)
	    Bug("unexpected block argument");
	if (iterator_p()) {
	    result = f_lambda();
	    the_scope->local_vars[node->nd_cnt] = result;
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
		Check_Type(klass, T_CLASS);
		break;
	    }
	    result = rb_const_get_at(klass, node->nd_mid);
	}
	break;

      case NODE_COLON3:
	result = rb_const_get_at(cObject, node->nd_mid);
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
			eval_tree = 0;
			list->nd_head = compile(list->nd_head->nd_lit,0);
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
		if (origin == the_class) {
		    Warning("discarding old %s", rb_id2name(node->nd_mid));
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
	    if (body && origin == the_class && body->nd_noex & NOEX_UNDEF) {
		noex |= NOEX_UNDEF;
	    }
	    rb_add_method(the_class, node->nd_mid, node->nd_defn, noex);
	    if (scope_vmode == SCOPE_MODFUNC) {
		rb_add_method(rb_singleton_class(the_class),
			      node->nd_mid, node->nd_defn, NOEX_PUBLIC);
		rb_funcall(the_class, rb_intern("singleton_method_added"),
			   1, INT2FIX(node->nd_mid));
	    }
	    if (FL_TEST(the_class, FL_SINGLETON)) {
		rb_funcall(rb_iv_get(the_class, "__attached__"),
			   rb_intern("singleton_method_added"),
			   1, INT2FIX(node->nd_mid));
	    }
	    else {
		rb_funcall(the_class, rb_intern("method_added"),
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

	    klass = rb_singleton_class(recv);
	    if (st_lookup(RCLASS(klass)->m_tbl, node->nd_mid, &body)) {
		Warning("redefine %s", rb_id2name(node->nd_mid));
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

	    body = search_method(the_class, node->nd_mid, &origin);
	    if (!body || !body->nd_body) {
		char *s0 = " class";
		VALUE klass = the_class;

		if (FL_TEST(the_class, FL_SINGLETON)) {
		    VALUE obj = rb_iv_get(the_class, "__attached__");
		    switch (TYPE(obj)) {
		      case T_MODULE:
		      case T_CLASS:
			klass = obj;
			s0 = "";
		    }
		}
		NameError("undefined method `%s' for%s `%s'",
			  rb_id2name(node->nd_mid),s0,rb_class2name(klass));
	    }
	    rb_clear_cache_by_id(node->nd_mid);
	    rb_add_method(the_class, node->nd_mid, 0, NOEX_PUBLIC);
	    result = Qnil;
	}
	break;

      case NODE_ALIAS:
	rb_alias(the_class, node->nd_new, node->nd_old);
	rb_funcall(the_class, rb_intern("method_added"),
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

	    if (node->nd_super) {
		super = superclass(self, node->nd_super);
	    }
	    else {
		super = 0;
	    }

	    if (rb_const_defined_at(the_class, node->nd_cname) &&
		(the_class != cObject ||
		 !rb_autoload_defined(node->nd_cname))) {

		klass = rb_const_get_at(the_class, node->nd_cname);
		if (TYPE(klass) != T_CLASS) {
		    TypeError("%s is not a class", rb_id2name(node->nd_cname));
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
			TypeError("superclass mismatch for %s",
				  rb_id2name(node->nd_cname));
		    }
		}
		if (safe_level >= 3) {
		    Raise(eSecurityError, "extending class prohibited");
		}
		rb_clear_cache();
	    }
	    else {
		if (!super) super = cObject;
		klass = rb_define_class_id(node->nd_cname, super);
		rb_const_set(the_class, node->nd_cname, klass);
		rb_set_class_path(klass,the_class,rb_id2name(node->nd_cname));
		obj_call_init(klass);
	    }

	    return module_setup(klass, node->nd_body);
	}
	break;

      case NODE_MODULE:
	{
	    VALUE module;

	    if (rb_const_defined_at(the_class, node->nd_cname) &&
		(the_class != cObject ||
		 !rb_autoload_defined(node->nd_cname))) {

		module = rb_const_get_at(the_class, node->nd_cname);
		if (TYPE(module) != T_MODULE) {
		    TypeError("%s is not a module", rb_id2name(node->nd_cname));
		}
		if (safe_level >= 3) {
		    Raise(eSecurityError, "extending module prohibited");
		}
	    }
	    else {
		module = rb_define_module_id(node->nd_cname);
		rb_const_set(the_class, node->nd_cname, module);
		rb_set_class_path(module,the_class,rb_id2name(node->nd_cname));
		obj_call_init(module);
	    }

	    result = module_setup(module, node->nd_body);
	}
	break;

      case NODE_SCLASS:
	{
	    VALUE klass;

	    klass = rb_eval(self, node->nd_recv);
	    if (FIXNUM_P(klass)) {
		TypeError("No virtual class for Fixnums");
	    }
	    if (NIL_P(klass)) {
		TypeError("No virtual class for nil");
	    }
	    if (rb_special_const_p(klass)) {
		TypeError("No virtual class for special constants");
	    }
	    if (FL_TEST(CLASS_OF(klass), FL_SINGLETON)) {
		rb_clear_cache();
	    }
	    klass = rb_singleton_class(klass);
	    
	    result = module_setup(klass, node->nd_body);
	}
	break;

      case NODE_DEFINED:
	{
	    char buf[20];
	    char *desc = is_defined(self, node->nd_head, buf);

	    if (desc) result = str_new2(desc);
	    else result = FALSE;
	}
	break;

    case NODE_NEWLINE:
	sourcefile = node->nd_file;
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
    int state;
    VALUE save = the_frame->cbase;
    VALUE result;		/* OK */
    char *file = sourcefile;
    int line = sourceline;
    TMP_PROTECT;

    /* fill c-ref */
    node->nd_clss = module;
    node = node->nd_body;

    PUSH_CLASS();
    the_class = module;
    PUSH_SCOPE();

    if (node->nd_rval) the_frame->cbase = node->nd_rval;
    if (node->nd_tbl) {
	VALUE *vars = TMP_ALLOC(VALUE, node->nd_tbl[0]+1);
	*vars++ = (VALUE)node;
	the_scope->local_vars = vars;
	memclear(the_scope->local_vars, node->nd_tbl[0]);
	the_scope->local_tbl = node->nd_tbl;
    }
    else {
	the_scope->local_vars = 0;
	the_scope->local_tbl  = 0;
    }

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	if (trace_func) {
	    call_trace_func("class", file, line,
			    the_class, the_frame->last_func);
	}
	result = rb_eval(the_class, node->nd_body);
    }
    POP_TAG();
    POP_SCOPE();
    POP_CLASS();

    the_frame->cbase = save;
    if (trace_func) {
	call_trace_func("end", file, line, 0, the_frame->last_func);
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
rb_iter_break()
{
    JUMP_TAG(TAG_BREAK);
}

#ifdef __GNUC__
static volatile voidfn rb_longjmp;
#endif

static VALUE make_backtrace _((void));

static VALUE
check_errat(val)
    VALUE val;
{
    int i;
    static char *err = "value of $@ must be Array of String";

    if (!NIL_P(val)) {
	int t = TYPE(val);

	if (t == T_STRING) return ary_new3(1, val);
	if (t != T_ARRAY) {
	    TypeError(err);
	}
	for (i=0;i<RARRAY(val)->len;i++) {
	    if (TYPE(RARRAY(val)->ptr[i]) != T_STRING) {
		TypeError(err);
	    }
	}
    }
    return val;
}

static void
rb_longjmp(tag, mesg, at)
    int tag;
    VALUE mesg, at;
{
    if (NIL_P(errinfo) && NIL_P(mesg)) {
	errinfo = exc_new(eRuntimeError, 0, 0);
    }

    if (debug && !NIL_P(errinfo)) {
	fprintf(stderr, "Exception `%s' at %s:%d\n",
		rb_class2name(CLASS_OF(errinfo)),
		sourcefile, sourceline);
    }
    if (!NIL_P(at)) {
	errat = check_errat(at);
    }
    else if (sourcefile && (NIL_P(errat) || !NIL_P(mesg))) {
	errat = make_backtrace();
    }

    if (!NIL_P(mesg)) {
	errinfo = mesg;
    }

    trap_restore_mask();
    if (trace_func && tag != TAG_FATAL) {
	call_trace_func("raise", sourcefile, sourceline,
			the_frame->self, the_frame->last_func);
    }
    JUMP_TAG(tag);
}

void
rb_raise(mesg)
    VALUE mesg;
{
    rb_longjmp(TAG_RAISE, mesg, Qnil);
}

void
rb_fatal(mesg)
    VALUE mesg;
{
    rb_longjmp(TAG_FATAL, mesg, Qnil);
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
    VALUE arg1, arg2, arg3;
    VALUE etype, mesg;
    int n;

    etype = eRuntimeError;
    mesg = Qnil;
    switch (n = rb_scan_args(argc, argv, "03", &arg1, &arg2, &arg3)) {
      case 1:
	mesg = arg1;
	break;
      case 2:
      case 3:
	etype = arg1;
	mesg = arg2;
	break;
    }

    if (!NIL_P(mesg)) {
	if (n >= 2) {
	    mesg = rb_funcall(etype, rb_intern("new"), 1, mesg);
	}
	else if (TYPE(mesg) == T_STRING) {
	    mesg = exc_new3(eRuntimeError, mesg);
	}
    }

    PUSH_FRAME();		/* fake frame */
    *the_frame = *_frame.prev->prev;
    rb_longjmp(TAG_RAISE, mesg, arg3);
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
    volatile VALUE result = Qnil;
    struct BLOCK *block;
    struct SCOPE *old_scope;
    struct FRAME frame;
    int state;
    static USHORT serial = 1;

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
    the_dyna_vars = new_dvar(0, 0);
    the_dyna_vars->next = block->d_vars;
    the_class = block->klass;
    if (!self) self = block->self;
    node = block->body;
    if (block->var) {
	if (nd_type(block->var) == NODE_MASGN)
	    massign(self, block->var, val);
	else
	    assign(self, block->var, val);
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
	    val = rb_Array(val);
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
    VALUE data1, data2;
{
    int state;
    volatile VALUE retval = Qnil;
    NODE *node = NEW_CFUNC(bl_proc, data2);
    VALUE self = TopSelf;

  iter_retry:
    PUSH_ITER(ITER_PRE);
    PUSH_BLOCK(0, node);
    _block.d_vars = new_dvar(0,0);
    PUSH_TAG(PROT_NONE);

    state = EXEC_TAG();
    if (state == 0) {
	retval = (*it_proc)(data1);
    }
    if (the_block->tag->dst == state) {
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
	return obj_is_kind_of(errinfo, eDefaultRescue);
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
    VALUE data1, data2;
{
    int state;
    volatile VALUE result;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
      retry_entry:
	result = (*b_proc)(data1);
    }
    else if (state == TAG_RAISE && obj_is_kind_of(errinfo, eDefaultRescue)) {
	if (r_proc) {
	    PUSH_TAG(PROT_NONE);
	    if ((state = EXEC_TAG()) == 0) {
		result = (*r_proc)(data2, errinfo);
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
	    errat = Qnil;
	}
    }
    POP_TAG();
    if (state) JUMP_TAG(state);

    return result;
}

VALUE
rb_ensure(b_proc, data1, e_proc, data2)
    VALUE (*b_proc)();
    void (*e_proc)();
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

    if (state) {
	JUMP_TAG(state);
    }
    return result;
}

static int last_call_status;

#define CSTAT_PRIV  1
#define CSTAT_PROT  2
#define CSTAT_VCALL 4

static VALUE
f_missing(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    ID    id;
    VALUE desc = 0;
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
	desc = any_to_s(obj);
	break;
      default:
	desc = rb_inspect(obj);
	break;
    }
    if (desc) {
	if (last_call_status & CSTAT_PRIV) {
	    format = "private method `%s' called for %s";
	}
	if (last_call_status & CSTAT_PROT) {
	    format = "protected method `%s' called for %s";
	}
	else if (iterator_p()) {
	    format = "undefined iterator `%s' for %s";
	}
	else if (last_call_status & CSTAT_VCALL) {
	    char *mname = rb_id2name(id);

	    if (('a' <= mname[0] && mname[0] <= 'z') || mname[0] == '_') {
		format = "undefined local variable or method `%s' for %s";
	    }
	}
	if (!format) {
	    format = "undefined method `%s' for %s";
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
	      desc?(char*)RSTRING(desc)->ptr:"");
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
rb_call0(klass, recv, id, argc, argv, body, nosuper)
    VALUE klass, recv;
    ID    id;
    int argc;			/* OK */
    VALUE *argv;		/* OK */
    NODE *body;
    int nosuper;
{
    NODE *b2;		/* OK */
    volatile VALUE result = Qnil;
    int itr;
    static int tick;
    TMP_PROTECT;

    switch (the_iter->iter) {
      case ITER_PRE:
	itr = ITER_CUR;
	break;
      case ITER_CUR:
      default:
	itr = ITER_NOT;
	break;
    }

    if ((++tick & 0xfff) == 0 && stack_length() > STACK_LEVEL_MAX)
	Raise(eSysStackError, "stack level too deep");

    PUSH_ITER(itr);
    PUSH_FRAME();
    the_frame->last_func = id;
    the_frame->last_class = nosuper?0:klass;
    the_frame->self = recv;
    the_frame->argc = argc;
    the_frame->argv = argv;

    switch (nd_type(body)) {
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
			len, rb_class2name(klass), rb_id2name(id));
		}
		else {
		    ArgError("too many arguments(%d)", len);
		}
		break;
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

	    if (body->nd_rval) the_frame->cbase = body->nd_rval;
	    if (body->nd_tbl) {
		local_vars = TMP_ALLOC(VALUE, body->nd_tbl[0]+1);
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

	    PUSH_TAG(PROT_FUNC);
	    PUSH_VARS();

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
			Bug("no argument-node");
		    }

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
			    /* +2 for $_ and $~ */
			    MEMCPY(local_vars+2, argv, VALUE, i);
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

		if (trace_func) {
		    call_trace_func("call", b2->nd_file, nd_line(b2),
				    recv, the_frame->last_func);
		}
		result = rb_eval(recv, body);
	    }
	    else if (state == TAG_RETURN) {
		result = prot_tag->retval;
		state = 0;
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
	    switch (state) {
	      case 0:
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
		if (!iterator_p()) {
		    Raise(eLocalJumpError, "retry outside of rescue clause");
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
	klass = ent->origin;
	id    = ent->mid0;
	noex  = ent->noex;
	body  = ent->method;
    }
    else if ((body = rb_get_method_body(&klass, &id, &noex)) == 0) {
	if (scope == 3) {
	    NameError("super: no superclass method `%s'", rb_id2name(mid));
	}
	return rb_undefined(recv, mid, argc, argv, scope==2?CSTAT_VCALL:0);
    }

    /* receiver specified form for private method */
    if ((noex & NOEX_PRIVATE) && scope == 0)
	return rb_undefined(recv, mid, argc, argv, CSTAT_PRIV);

    /* self must be kind of a specified form for private method */
    if ((noex & NOEX_PROTECTED) && !obj_is_kind_of(the_frame->self, klass))
	return rb_undefined(recv, mid, argc, argv, CSTAT_PROT);

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
f_send(argc, argv, recv)
    int argc;
    VALUE *argv;
    VALUE recv;
{
    VALUE vid;

    if (argc == 0) ArgError("no method name given");

    vid = *argv++; argc--;
    PUSH_ITER(iterator_p()?ITER_PRE:ITER_NOT);
    vid = rb_call(CLASS_OF(recv), recv, rb_to_id(vid), argc, argv, 1);
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
compile(src, place)
    VALUE src;
    char *place;
{
    NODE *node;

    Check_Type(src, T_STRING);
    if (place == 0) place = sourcefile;
    node = compile_string(place, RSTRING(src)->ptr, RSTRING(src)->len);

    if (nerrs == 0) return node;
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
    char *filesave = sourcefile;
    int linesave = sourceline;
    volatile int iter = the_frame->iter;
    int state;

    if (file == 0) {
	file = sourcefile;
	line = sourceline;
    }
    if (!NIL_P(scope)) {
	if (!obj_is_block(scope)) {
	    TypeError("wrong argument type %s (expected Proc/Binding)",
		      rb_class2name(CLASS_OF(scope)));
	}

	Data_Get_Struct(scope, struct BLOCK, data);

	/* PUSH BLOCK from data */
	frame = data->frame;
	frame.prev = the_frame;
	the_frame = &(frame);
	old_scope = the_scope;
	the_scope = data->scope;
	old_block = the_block;
	the_block = data->prev;
	old_d_vars = the_dyna_vars;
	the_dyna_vars = data->d_vars;
	old_vmode = scope_vmode;
	scope_vmode = data->vmode;

	self = data->self;
	the_frame->iter = data->iter;
    }
    else {
	if (the_frame->prev) {
	    the_frame->iter = the_frame->prev->iter;
	}
    }
    PUSH_CLASS();
    the_class = ((NODE*)the_frame->cbase)->nd_clss;

    rb_in_eval++;
    if (TYPE(the_class) == T_ICLASS) {
	the_class = RBASIC(the_class)->klass;
    }
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	eval_tree = 0;
	compile(src, file);
	if (nerrs > 0) {
	    compile_error(0);
	}
	result = eval_node(self);
    }
    POP_TAG();
    POP_CLASS();
    rb_in_eval--;
    if (!NIL_P(scope)) {
	the_frame = the_frame->prev;
	the_scope = old_scope;
	the_block = old_block;
	the_dyna_vars = old_d_vars;
	data->vmode = scope_vmode; /* write back visibility mode */
	scope_vmode = old_vmode;
    }
    else {
	the_frame->iter = iter;
    }
    sourcefile = filesave;
    sourceline = linesave;
    if (state) {
	VALUE err;

	if (state == TAG_RAISE) {
	    if (strcmp(file, "(eval)") == 0) {
		if (sourceline > 1) {
		    err = RARRAY(errat)->ptr[0];
		    str_cat(err, ": ", 2);
		    str_concat(err, errinfo);
		}
		else {
		    err = str_dup(errinfo);
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
    VALUE src, scope, vfile, vline;
    char *file = "(eval)";
    int line = 0;

    rb_scan_args(argc, argv, "13", &src, &scope, &vfile, &vline);
    if (!NIL_P(vfile)) {
	Check_Type(vfile, T_STRING);
	file = RSTRING(vfile)->ptr;
    }
    if (!NIL_P(vline)) {
	line = NUM2INT(vline);
    }

    Check_SafeStr(src);
    return eval(self, src, scope, file, line);
}

static VALUE
exec_under(func, under, args)
    VALUE (*func)();
    VALUE under;
    void *args;
{
    VALUE val;			/* OK */
    int state;
    int mode;
    VALUE cbase = the_frame->cbase;

    PUSH_CLASS();
    the_class = under;
    PUSH_FRAME();
    the_frame->last_func = _frame.prev->last_func;
    the_frame->last_class = _frame.prev->last_class;
    the_frame->argc = _frame.prev->argc;
    the_frame->argv = _frame.prev->argv;
    the_frame->cbase = (VALUE)node_newnode(NODE_CREF,under,0,cbase);
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
    return eval(args[0], args[1], Qnil, 0, 0);
}

static VALUE
eval_under(under, self, src)
    VALUE under, self, src;
{
    VALUE args[2];

    args[0] = self;
    args[1] = src;
    return exec_under(eval_under_i, under, args);
}

static VALUE
yield_under_i(self)
    VALUE self;
{
    return rb_yield_0(self, self);
}

static VALUE
yield_under(under, self)
    VALUE under, self;
{
    return exec_under(yield_under_i, under, self);
}

static VALUE
obj_instance_eval(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    if (argc == 0) {
	if (!iterator_p()) {
	    ArgError("block not supplied");
	}
    }
    else if (argc == 1) {
	Check_SafeStr(argv[0]);
    }
    else {
	ArgError("Wrong # of arguments: %s(src) or %s{..}",
		 rb_id2name(the_frame->last_func),
		 rb_id2name(the_frame->last_func));
    }

    if (argc == 0) {
	return yield_under(rb_singleton_class(self), self);
    }
    else {
	return eval_under(rb_singleton_class(self), self, argv[0]);
    }
}

static VALUE
mod_module_eval(argc, argv, mod)
    int argc;
    VALUE *argv;
    VALUE mod;
{
    if (argc == 0) {
	if (!iterator_p()) {
	    ArgError("block not supplied");
	}
    }
    else if (argc == 1) {
	Check_SafeStr(argv[0]);
    }
    else {
	ArgError("Wrong # of arguments: %s(src) or %s{..}",
		 rb_id2name(the_frame->last_func),
		 rb_id2name(the_frame->last_func));
    }

    if (argc == 0) {
	return yield_under(mod, mod);
    }
    else {
	return eval_under(mod, mod, argv[0]);
    }
}

VALUE rb_load_path;

static int
is_absolute_path(path)
    char *path;
{
    if (path[0] == '/') return 1;
#if defined(MSDOS) || defined(NT) || defined(__human68k__)
    if (path[0] == '\\') return 1;
    if (strlen(path) > 2 && path[1] == ':') return 1;
#endif
    return 0;
}

static char*
find_file(file)
    char *file;
{
    extern VALUE rb_load_path;
    VALUE vpath;
    char *path;

    if (is_absolute_path(file)) {
	FILE *f = fopen(file, "r");

	if (f == NULL) return 0;
	fclose(f);
	return file;
    }

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
    VALUE obj, fname;
{
    int state;
    char *file;
    volatile ID last_func;
    TMP_PROTECT;

    Check_SafeStr(fname);
    if (RSTRING(fname)->ptr[0] == '~') {
	fname = file_s_expand_path(0, fname);
    }
    file = find_file(RSTRING(fname)->ptr);
    if (!file) LoadError("No such file to load -- %s", RSTRING(fname)->ptr);

    PUSH_TAG(PROT_NONE);
    PUSH_CLASS();
    the_class = cObject;
    PUSH_SCOPE();
    if (top_scope->local_tbl) {
	int len = top_scope->local_tbl[0]+1;
	ID *tbl = ALLOC_N(ID, len);
	VALUE *vars = TMP_ALLOC(VALUE, len);
	*vars++ = 0;
	MEMCPY(tbl, top_scope->local_tbl, ID, len);
	MEMCPY(vars, top_scope->local_vars, ID, len-1);
	the_scope->local_tbl = tbl;
	the_scope->local_vars = vars;
    }
    /* default visibility is private at loading toplevel */
    SCOPE_SET(SCOPE_PRIVATE);

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
    VALUE obj, fname;
{
    char *ext, *file, *feature, *buf; /* OK */
    VALUE load;

    Check_SafeStr(fname);
    if (rb_provided(RSTRING(fname)->ptr))
	return FALSE;

    ext = strrchr(RSTRING(fname)->ptr, '.');
    if (ext) {
	if (strcmp(".rb", ext) == 0) {
	    feature = file = RSTRING(fname)->ptr;
	    file = find_file(file);
	    if (file) goto rb_load;
	}
	else if (strcmp(".o", ext) == 0) {
	    file = feature = RSTRING(fname)->ptr;
	    if (strcmp(".o", DLEXT) != 0) {
		buf = ALLOCA_N(char, strlen(file)+sizeof(DLEXT)+1);
		strcpy(buf, feature);
		ext = strrchr(buf, '.');
		strcpy(ext, DLEXT);
		file = find_file(buf);
	    }
	    if (file) goto dyna_load;
	}
	else if (strcmp(DLEXT, ext) == 0) {
	    feature = RSTRING(fname)->ptr;
	    file = find_file(feature);
	    if (file) goto dyna_load;
	}
    }
    buf = ALLOCA_N(char, strlen(RSTRING(fname)->ptr) + 5);
    sprintf(buf, "%s.rb", RSTRING(fname)->ptr);
    file = find_file(buf);
    if (file) {
	fname = str_new2(file);
	feature = buf;
	goto rb_load;
    }
    sprintf(buf, "%s%s", RSTRING(fname)->ptr, DLEXT);
    file = find_file(buf);
    if (file) {
	feature = buf;
	goto dyna_load;
    }
    LoadError("No such file to load -- %s", RSTRING(fname)->ptr);

  dyna_load:
#ifdef THREAD
    if (thread_loading(feature)) return FALSE;
    else {
	int state;
	PUSH_TAG(PROT_NONE);
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
	int state;
	PUSH_TAG(PROT_NONE);
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
    if (argc == 0) {
	SCOPE_SET(SCOPE_PUBLIC);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PUBLIC);
    }
    return module;
}

static VALUE
mod_protected(argc, argv, module)
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
mod_private(argc, argv, module)
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
top_public(argc, argv)
    int argc;
    VALUE *argv;
{
    return mod_public(argc, argv, cObject);
}

static VALUE
top_private(argc, argv)
    int argc;
    VALUE *argv;
{
    return mod_private(argc, argv, cObject);
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

    if (argc == 0) {
	SCOPE_SET(SCOPE_MODFUNC);
	return module;
    }

    set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    for (i=0; i<argc; i++) {
	id = rb_to_id(argv[i]);
	body = search_method(module, id, 0);
	if (body == 0 || body->nd_body == 0) {
	    NameError("undefined method `%s' for module `%s'",
		      rb_id2name(id), rb_class2name(module));
	}
	rb_clear_cache_by_id(id);
	rb_add_method(rb_singleton_class(module), id, body->nd_body, NOEX_PUBLIC);
    }
    return module;
}

static VALUE
mod_append_features(module, include)
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
mod_include(argc, argv, module)
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
obj_call_init(obj)
    VALUE obj;
{
    PUSH_ITER(iterator_p()?ITER_PRE:ITER_NOT);
    rb_funcall2(obj, init, the_frame->argc, the_frame->argv);
    POP_ITER();
}

VALUE
class_new_instance(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE obj;

    if (FL_TEST(klass, FL_SINGLETON)) {
	TypeError("can't create instance of virtual class");
    }
    obj = obj_alloc(klass);
    obj_call_init(obj);

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
    *var = check_errat(val);
}

VALUE f_global_variables();
VALUE f_instance_variables();

VALUE
f_local_variables()
{
    ID *tbl;
    int n, i;
    VALUE ary = ary_new();
    struct RVarmap *vars;

    tbl = the_scope->local_tbl;
    if (tbl) {
	n = *tbl++;
	for (i=2; i<n; i++) {	/* skip first 2 ($_ and $~) */
	    ary_push(ary, str_new2(rb_id2name(tbl[i])));
	}
    }

    vars = the_dyna_vars;
    while (vars) {
	if (vars->id) {
	    ary_push(ary, str_new2(rb_id2name(vars->id)));
	}
	vars = vars->next;
    }

    return ary;
}

static VALUE f_catch();
static VALUE f_throw();

struct end_proc_data {
    void (*func)();
    VALUE data;
    struct end_proc_data *next;
} *end_proc_data;

void
rb_set_end_proc(func, data)
    void (*func)();
    VALUE data;
{
    struct end_proc_data *link = ALLOC(struct end_proc_data);

    link->next = end_proc_data;
    link->func = func;
    link->data = data;
    rb_global_variable(&link->data);
    end_proc_data = link;
}

static void
call_end_proc(data)
    VALUE data;
{
    proc_call(data, Qnil);
}

static void
f_END()
{
    PUSH_FRAME();
    rb_set_end_proc(call_end_proc, f_lambda());
    POP_FRAME();
}

static VALUE
f_at_exit()
{
    VALUE proc;

    proc = f_lambda();

    rb_set_end_proc(call_end_proc, proc);
    return proc;
}

static void
exec_end_proc()
{
    struct end_proc_data *link = end_proc_data;

    while (link) {
	(*link->func)(link->data);
	link = link->next;
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

    rb_global_variable((VALUE*)&top_scope);
    rb_global_variable((VALUE*)&eval_tree0);
    rb_global_variable((VALUE*)&eval_tree);
    rb_global_variable((VALUE*)&the_dyna_vars);

    rb_define_hooked_variable("$@", &errat, 0, errat_setter);
    rb_define_variable("$!", &errinfo);

    rb_define_global_function("eval", f_eval, -1);
    rb_define_global_function("iterator?", f_iterator_p, 0);
    rb_define_global_function("method_missing", f_missing, -1);
    rb_define_global_function("loop", f_loop, 0);

    rb_define_method(mKernel, "respond_to?", obj_respond_to, -1);

    rb_define_global_function("raise", f_raise, -1);
    rb_define_alias(mKernel,  "fail", "raise");

    rb_define_global_function("caller", f_caller, -1);

    rb_define_global_function("exit", f_exit, -1);
    rb_define_global_function("abort", f_abort, 0);

    rb_define_global_function("at_exit", f_at_exit, 0);

    rb_define_global_function("catch", f_catch, 1);
    rb_define_global_function("throw", f_throw, -1);
    rb_define_global_function("global_variables", f_global_variables, 0);
    rb_define_global_function("local_variables", f_local_variables, 0);

    rb_define_method(mKernel, "send", f_send, -1);
    rb_define_method(mKernel, "__send__", f_send, -1);
    rb_define_method(mKernel, "instance_eval", obj_instance_eval, -1);

    rb_define_private_method(cModule, "append_features", mod_append_features, 1);
    rb_define_private_method(cModule, "extend_object", mod_extend_object, 1);
    rb_define_private_method(cModule, "include", mod_include, -1);
    rb_define_private_method(cModule, "public", mod_public, -1);
    rb_define_private_method(cModule, "protected", mod_protected, -1);
    rb_define_private_method(cModule, "private", mod_private, -1);
    rb_define_private_method(cModule, "module_function", mod_modfunc, -1);
    rb_define_method(cModule, "method_defined?", mod_method_defined, 1);
    rb_define_method(cModule, "public_class_method", mod_public_method, -1);
    rb_define_method(cModule, "private_class_method", mod_private_method, -1);
    rb_define_method(cModule, "module_eval", mod_module_eval, -1);
    rb_define_method(cModule, "class_eval", mod_module_eval, -1);

    rb_define_private_method(cModule, "remove_method", mod_remove_method, 1);
    rb_define_private_method(cModule, "undef_method", mod_undef_method, 1);
    rb_define_private_method(cModule, "alias_method", mod_alias_method, 2);

    rb_define_singleton_method(cModule, "nesting", mod_nesting, 0);
    rb_define_singleton_method(cModule, "constants", mod_s_constants, 0);

    rb_define_singleton_method(TopSelf, "include", top_include, -1);
    rb_define_singleton_method(TopSelf, "public", top_public, -1);
    rb_define_singleton_method(TopSelf, "private", top_private, -1);

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
    while (data) {
	gc_mark_frame(&data->frame);
	gc_mark(data->scope);
	gc_mark(data->var);
	gc_mark(data->body);
	gc_mark(data->self);
	gc_mark(data->d_vars);
	data = data->prev;
    }
}

static void
blk_free(data)
    struct BLOCK *data;
{
    struct BLOCK *tmp;

    while (data) {
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
	tmp->frame.argv = ALLOC_N(VALUE, tmp->frame.argc);
	MEMCPY(tmp->frame.argv, block->frame.argv, VALUE, tmp->frame.argc);
	block->prev = tmp;
	block = tmp;
    }
}


static VALUE
bind_clone(self)
    VALUE self;
{
    struct BLOCK *orig, *data;
    VALUE bind;

    Data_Get_Struct(self, struct BLOCK, orig);
    bind = Data_Make_Struct(self,struct BLOCK,blk_mark,blk_free,data);
    MEMCPY(data, orig, struct BLOCK, 1);
    data->frame.argv = ALLOC_N(VALUE, orig->frame.argc);
    MEMCPY(data->frame.argv, orig->frame.argv, VALUE, orig->frame.argc);

    if (data->iter) {
	blk_copy_prev(data);
    }
    else {
	data->prev = 0;
    }

    return bind;
}

static VALUE
f_binding(self)
    VALUE self;
{
    struct BLOCK *data;
    VALUE bind;

    PUSH_BLOCK(0,0);
    bind = Data_Make_Struct(cBinding,struct BLOCK,blk_mark,blk_free,data);
    MEMCPY(data, the_block, struct BLOCK, 1);

#ifdef THREAD
    data->orig_thread = thread_current();
#endif
    data->iter = f_iterator_p();
    if (the_frame->prev) {
	data->frame.last_func = the_frame->prev->last_func;
    }
    data->frame.argv = ALLOC_N(VALUE, data->frame.argc);
    MEMCPY(data->frame.argv, the_block->frame.argv, VALUE, data->frame.argc);

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

#define PROC_TAINT FL_USER0
#define PROC_T3    FL_USER1
#define PROC_T4    FL_USER2
#define PROC_T5    (FL_USER1|FL_USER2)
#define PROC_TMASK (FL_USER1|FL_USER2)

static VALUE
proc_s_new(klass)
    VALUE klass;
{
    volatile VALUE proc;
    struct BLOCK *data;

    if (!iterator_p() && !f_iterator_p()) {
	ArgError("tryed to create Procedure-Object out of iterator");
    }

    proc = Data_Make_Struct(klass, struct BLOCK, blk_mark, blk_free, data);
    *data = *the_block;

#ifdef THREAD
    data->orig_thread = thread_current();
#endif
    data->iter = data->prev?TRUE:FALSE;
    data->frame.argv = ALLOC_N(VALUE, data->frame.argc);
    MEMCPY(data->frame.argv, the_block->frame.argv, VALUE, data->frame.argc);
    if (data->iter) {
	blk_copy_prev(data);
    }
    else {
	data->prev = 0;
    }

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
    obj_call_init(proc);

    return proc;
}

VALUE
f_lambda()
{
    return proc_s_new(cProc);
}

static int
blk_orphan(data)
    struct BLOCK *data;
{
    if (data->scope && data->scope != top_scope &&
	(data->scope->flag & SCOPE_NOSTACK)) {
	return 1;
    }
#ifdef THREAD
    if (data->orig_thread != thread_current()) {
	return 1;
    }
#endif
    return 0;
}

static VALUE
proc_call(proc, args)
    VALUE proc, args;		/* OK */
{
    struct BLOCK *data;
    volatile VALUE result = Qnil;
    int state;
    volatile int orphan;
    volatile int safe = safe_level;

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

    Data_Get_Struct(proc, struct BLOCK, data);
    orphan = blk_orphan(data);

    /* PUSH BLOCK from data */
    PUSH_BLOCK2(data);
    PUSH_ITER(ITER_CUR);
    the_frame->iter = ITER_CUR;

    if (orphan) {/* orphan procedure */
	if (iterator_p()) {
	    the_block->frame.iter = ITER_CUR;
	}
	else {
	    the_block->frame.iter = ITER_NOT;
	}
    }

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

    PUSH_TAG(PROT_NONE);
    state = EXEC_TAG();
    if (state == 0) {
	result = rb_yield(args);
    }
    POP_TAG();

    POP_ITER();
    if (the_block->tag->dst == state) {
	state &= TAG_MASK;
    }
    POP_BLOCK();
    safe_level = safe;

    if (state) {
	if (orphan) {/* orphan procedure */
	    switch (state) {
	      case TAG_BREAK:
		Raise(eLocalJumpError, "break from proc-closure");
		break;
	      case TAG_RETRY:
		Raise(eLocalJumpError, "retry from proc-closure");
		break;
	      case TAG_RETURN:
		Raise(eLocalJumpError, "return from proc-closure");
		break;
	    }
	}
	JUMP_TAG(state);
    }
    return result;
}

static VALUE
block_pass(self, node)
    VALUE self;
    NODE *node;
{
    VALUE block = rb_eval(self, node->nd_body);
    struct BLOCK *data;
    volatile VALUE result = Qnil;
    int state;
    volatile int orphan;
    volatile int safe = safe_level;

    if (NIL_P(block)) {
	return rb_eval(self, node->nd_iter);
    }
    if (obj_is_kind_of(block, cMethod)) {
	block = method_proc(block);
    }
    else if (!obj_is_proc(block)) {
	TypeError("wrong argument type %s (expected Proc)",
		  rb_class2name(CLASS_OF(block)));
    }

    Data_Get_Struct(block, struct BLOCK, data);
    orphan = blk_orphan(data);

    /* PUSH BLOCK from data */
    PUSH_BLOCK2(data);
    PUSH_ITER(ITER_PRE);
    the_frame->iter = ITER_PRE;
    if (FL_TEST(block, PROC_TAINT)) {
	switch (RBASIC(block)->flags & PROC_TMASK) {
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

    PUSH_TAG(PROT_NONE);
    state = EXEC_TAG();
    if (state == 0) {
	result = rb_eval(self, node->nd_iter);
    }
    POP_TAG();

    POP_ITER();
    if (the_block->tag->dst == state) {
	state &= TAG_MASK;
	orphan = 2;
    }
    POP_BLOCK();
    safe_level = safe;

    if (state) {
	if (orphan == 2) {/* escape from orphan procedure */
	    switch (state) {
	      case TAG_BREAK:
		Raise(eLocalJumpError, "break from proc-closure");
		break;
	      case TAG_RETRY:
		Raise(eLocalJumpError, "retry from proc-closure");
		break;
	      case TAG_RETURN:
		Raise(eLocalJumpError, "return from proc-closure");
		break;
	    }
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
    gc_mark(data->oklass);
    gc_mark(data->klass);
    gc_mark(data->recv);
    gc_mark(data->body);
}

static VALUE
obj_method(obj, vid)
    VALUE obj;
    VALUE vid;
{
    VALUE method;
    VALUE klass = CLASS_OF(obj);
    ID mid, id;
    NODE *body;
    int noex;
    enum node_type type;
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

    method = Data_Make_Struct(cMethod, struct METHOD, bm_mark, free, data);
    data->klass = klass;
    data->recv = obj;
    data->id = id;
    data->body = body;
    data->oklass = CLASS_OF(obj);
    data->oid = rb_to_id(vid);

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

    Data_Get_Struct(method, struct METHOD, data);
    PUSH_ITER(iterator_p()?ITER_PRE:ITER_NOT);
    result = rb_call0(data->klass, data->recv, data->id,
		      argc, argv, data->body, 0);
    POP_ITER();
    return result;
}

static VALUE
method_inspect(method)
    VALUE method;
{
    struct METHOD *data;
    VALUE str;
    char *s;

    Data_Get_Struct(method, struct METHOD, data);
    str = str_new2("#<");
    s = rb_class2name(CLASS_OF(method));
    str_cat(str, s, strlen(s));
    str_cat(str, ": ", 2);
    s = rb_class2name(data->oklass);
    str_cat(str, s, strlen(s));
    str_cat(str, "#", 1);
    s = rb_id2name(data->oid);
    str_cat(str, s, strlen(s));
    str_cat(str, ">", 1);

    return str;
}

static VALUE
mproc()
{
    VALUE proc;

    /* emulate ruby's method call */
    PUSH_ITER(ITER_CUR);
    PUSH_FRAME();
    proc = f_lambda();
    POP_FRAME();
    POP_ITER();

    return proc;
}

static VALUE
mcall(args, method)
    VALUE args, method;
{
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
    eLocalJumpError = rb_define_class("LocalJumpError", eStandardError);
    eSysStackError = rb_define_class("SystemStackError", eStandardError);

    cProc = rb_define_class("Proc", cObject);
    rb_define_singleton_method(cProc, "new", proc_s_new, 0);

    rb_define_method(cProc, "call", proc_call, -2);
    rb_define_global_function("proc", f_lambda, 0);
    rb_define_global_function("lambda", f_lambda, 0);
    rb_define_global_function("binding", f_binding, 0);
    cBinding = rb_define_class("Binding", cObject);
    rb_undef_method(CLASS_OF(cMethod), "new");
    rb_define_method(cBinding, "clone", bind_clone, 0);

    cMethod = rb_define_class("Method", cObject);
    rb_undef_method(CLASS_OF(cMethod), "new");
    rb_define_method(cMethod, "call", method_call, -1);
    rb_define_method(cMethod, "inspect", method_inspect, 0);
    rb_define_method(cMethod, "to_s", method_inspect, 0);
    rb_define_method(cMethod, "to_proc", method_proc, 0);
    rb_define_method(mKernel, "method", obj_method, 1);
}

#ifdef THREAD

static VALUE eThreadError;

int thread_pending = 0;

VALUE cThread;

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
    struct RVarmap *dyna_vars;
    struct BLOCK *block;
    struct iter *iter;
    struct tag *tag;
    VALUE klass;

    VALUE trace;
    int misc;			/* misc. states (vmode/trap_immediate) */

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
    if (th != main_thread) free(th);
}

static thread_t
thread_check(data)
    VALUE data;
{
    if (TYPE(data) != T_DATA || RDATA(data)->dfree != thread_free) {
	TypeError("wrong argument type %s (expected Thread)",
		  rb_class2name(CLASS_OF(data)));
    }
    return (thread_t)RDATA(data)->data;
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
    th->klass = the_class;
    th->dyna_vars = the_dyna_vars;
    th->block = the_block;
    th->misc = scope_vmode | (trap_immediate<<8);
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
static VALUE th_cmd;
static int   th_sig;

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
    the_class = th->klass;
    the_dyna_vars = th->dyna_vars;
    the_block = th->block;
    scope_vmode = th->misc&SCOPE_MASK;
    trap_immediate = th->misc>>8;
    the_iter = th->iter;
    prot_tag = th->tag;
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
	JUMP_TAG(TAG_FATAL);
	break;

      case 2:
	rb_interrupt();
	break;

      case 3:
	rb_trap_eval(th_cmd, th_sig);
	errno = EINTR;
	break;

      case 4:
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
    thread_t next;		/* OK */
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

    FOREACH_THREAD_FROM(curr, th) {
       if (th->status != THREAD_STOPPED && th->status != THREAD_KILLED) {
           next = th;
           break;
       }
    }
    END_FOREACH_FROM(curr, th); 

    if (num_waiting_on_join) {
	FOREACH_THREAD_FROM(curr, th) {
	    if ((th->wait_for&WAIT_JOIN) && thread_dead(th->join)) {
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
			    next = th;
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
	curr_thread->file = sourcefile;
	curr_thread->line = sourceline;
	FOREACH_THREAD_FROM(curr, th) {
	    fprintf(stderr, "%s:%d:deadlock 0x%x: %d:%d %s\n", 
		    th->file, th->line, th->thread, th->status,
		    th->wait_for, th==main_thread?"(main)":"");
	}
	END_FOREACH_FROM(curr, th);
	/* raise fatal error to main thread */
	thread_deadlock();
    }
    if (next->status == THREAD_RUNNABLE && next == curr_thread) {
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
thread_stop()
{
    thread_critical = 0;
    curr_thread->status = THREAD_STOPPED;
    if (curr_thread == curr_thread->next) {
	Raise(eThreadError, "stopping only thread");
    }
    thread_schedule();

    return Qnil;
}

struct timeval time_timeval();

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
    th->klass = 0;
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
    int state;

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

    PUSH_TAG(PROT_THREAD);
    if ((state = EXEC_TAG()) == 0) {
	thread_save_context(th);
	if (setjmp(th->context) == 0) {
	    curr_thread = th;
	    th->result = (*fn)(arg, th);
	}
    }
    POP_TAG();
    if (state && th->status != THREAD_TO_KILL && !NIL_P(errinfo)) {
	if (state == TAG_FATAL || obj_is_kind_of(errinfo, eSystemExit)) {
	    /* fatal error or global exit within this thread */
	    /* need to stop whole script */
	    main_thread->errat = errat;
	    main_thread->errinfo = errinfo;
	    thread_cleanup();
	}
	else if (thread_abort || curr_thread->abort || RTEST(debug)) {
	    f_abort();
	}
	else {
	    curr_thread->errat = errat;
	    curr_thread->errinfo = errinfo;
	}
    }
    thread_remove();
    return 0;
}

static VALUE
thread_yield(arg, th) 
    int arg;
    thread_t th;
{
    scope_dup(the_block->scope);
    return rb_yield(th->thread);
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
thread_stop_p(thread)
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

void
thread_trap_eval(cmd, sig)
    VALUE cmd;
    int sig;
{
    thread_critical = 0;
    if (!thread_dead(curr_thread)) {
	thread_ready(curr_thread);
	rb_trap_eval(cmd, sig);
	return;
    }
    thread_ready(main_thread);
    thread_save_context(curr_thread);
    if (setjmp(curr_thread->context)) {
	return;
    }
    th_cmd = cmd;
    th_sig = sig;
    curr_thread = main_thread;
    thread_restore_context(curr_thread, 3);
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
    thread_restore_context(curr_thread, 4);
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
    eThreadError = rb_define_class("ThreadError", eStandardError);
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
    rb_define_method(cThread, "exit", thread_kill, 0);
    rb_define_method(cThread, "value", thread_value, 0);
    rb_define_method(cThread, "status", thread_status, 0);
    rb_define_method(cThread, "alive?", thread_status, 0);
    rb_define_method(cThread, "stop?", thread_stop_p, 0);
    rb_define_method(cThread, "raise", thread_raise, -1);

    rb_define_method(cThread, "abort_on_exception", thread_abort_exc, 0);
    rb_define_method(cThread, "abort_on_exception=", thread_abort_exc_set, 1);

    /* allocate main thread */
    main_thread = thread_alloc();
}
#endif

static VALUE
f_catch(dmy, tag)
    VALUE dmy, tag;
{
    int state;
    ID t;
    VALUE val;			/* OK */

    t = rb_to_id(tag);
    PUSH_TAG(t);
    if ((state = EXEC_TAG()) == 0) {
	val = rb_yield(tag);
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
f_throw(argc, argv)
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
#ifdef THREAD
	if (tt->tag == PROT_THREAD) {
	    Raise(eThreadError, "uncaught throw `%s' in thread 0x%x",
		  rb_id2name(t),
		  curr_thread);
	}
#endif
	tt = tt->prev;
    }
    if (!tt) {
	NameError("uncaught throw `%s'", rb_id2name(t));
    }
    return_value(value);
    trap_restore_mask();
    JUMP_TAG(TAG_THROW);
    /* not reached */
}

static void
return_check()
{
#ifdef THREAD
    struct tag *tt = prot_tag;

    while (tt) {
	if (tt->tag == PROT_FUNC) {
	    break;
	}
	if (tt->tag == PROT_THREAD) {
	    Raise(eThreadError, "return from within thread 0x%x",
		  curr_thread);
	}
	tt = tt->prev;
    }
#endif
}
