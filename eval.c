/************************************************

  eval.c -

  $Author: matz $
  $Date: 1995/01/12 08:54:45 $
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "env.h"
#include "node.h"
#include "sig.h"

#include <stdio.h>
#include <setjmp.h>
#include "st.h"
#include "dln.h"

#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strchr();
char *strrchr();
#endif

VALUE cProc;
static VALUE proc_call();

static void rb_clear_cache_body();
static void rb_clear_cache_entry();

/* #define TEST	/* prints cache miss */
#ifdef TEST
#include <stdio.h>
#endif

#define CACHE_SIZE 0x200
#define CACHE_MASK 0x1ff
#define EXPR1(c,m) ((((int)(c)>>3)^(m))&CACHE_MASK)

struct cache_entry {		/* method hash table. */
    ID mid;			/* method's id */
    struct RClass *class;	/* receiver's class */
    struct RClass *origin;	/* where method defined  */
    int nargs;			/* # of args */
    NODE *method;
    int noex;
};

static struct cache_entry cache[CACHE_SIZE];

void
rb_add_method(class, mid, node, noex)
    struct RClass *class;
    ID mid;
    NODE *node;
    int noex;
{
    NODE *body;

    if (class == Qnil) class = (struct RClass*)cObject;
    if (st_lookup(class->m_tbl, mid, &body)) {
	Warning("redefine %s", rb_id2name(mid));
	rb_clear_cache_body(body);
    }
    else {
	rb_clear_cache_entry(class, mid);
    }
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
	if (class == Qnil) return Qnil;
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

    if ((body = search_method(class, id, &origin)) == FALSE) {
	return Qnil;
    }
    if (body->nd_body == Qnil) return Qnil;

    ent = cache + EXPR1(class, id);
#ifdef TEST
    if (ent->mid != 0) {
	fprintf(stderr, "0x%x 0x%x %x\n", class, id, EXPR1(class, id));
    }
#endif
    /* store in cache */
    ent->class  = class;
    ent->noex   = body->nd_noex;
    body = body->nd_body;
    if (nd_type(body) == NODE_FBODY) {
	*classp = ent->origin = (struct RClass*)body->nd_orig;
	*idp = ent->mid = body->nd_mid;
	body = ent->method = body->nd_head;
    }
    else {
	*classp = ent->origin = origin;
	ent->mid = id;
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
    NODE *body, *old;

    if (name == def) return;
    body = search_method(class, def, &origin);
    if (body == Qnil || body->nd_body == Qnil) {
	Fail("undefined method `%s' for class `%s'",
	     rb_id2name(def), rb_class2name(class));
    }

    if (st_lookup(class->m_tbl, name, &old)) {
	Warning("redefine %s", rb_id2name(name));
	rb_clear_cache_body(body);
    }
    else {
	rb_clear_cache_entry(class, name);
    }

    st_insert(class->m_tbl, name,
	      NEW_METHOD(NEW_FBODY(body->nd_body, def, origin),
			 body->nd_noex));
}

void
rb_export_method(class, name, noex)
    struct RClass *class;
    ID name;
    int noex;
{
    NODE *body;
    struct RClass *origin;

    body = search_method(class, name, &origin);
    if (body == Qnil) {
	Fail("undefined method `%s' for class `%s'",
	     rb_id2name(name), rb_class2name(class));
    }
    if (body->nd_noex != noex) {
	if (class == origin) {
	    body->nd_noex = noex;
	}
	else {
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

VALUE
rb_method_boundp(class, id)
    struct RClass *class;
    ID id;
{
    return method_boundp(class, id, 0);
}

static void
rb_clear_cache_body(body)
    NODE *body;
{
    struct cache_entry *ent, *end;

    ent = cache; end = ent + CACHE_SIZE;
    while (ent < end) {
	if (ent->method == body) {
	    ent->class = Qnil;
	    ent->mid = Qnil;
	}
	ent++;
    }
}

static void
rb_clear_cache_entry(class, mid)
    struct RClass *class;
    ID mid;
{
    struct cache_entry *ent;

    /* is it in the method cache? */
    ent = cache + EXPR1(class, mid);
    if (ent->mid == mid && ent->class == class) {
	ent->class = Qnil;
	ent->mid = Qnil;
    }
}

void
rb_clear_cache(class)
    struct RClass *class;
{
    struct cache_entry *ent, *end;

    ent = cache; end = ent + CACHE_SIZE;
    while (ent < end) {
	if (ent->origin == class) {
	    ent->class = Qnil;
	    ent->mid = Qnil;
	}
	ent++;
    }
}

static ID match, each, aref, aset;
VALUE errstr, errat;
extern NODE *eval_tree;
extern int nerrs;

extern VALUE TopSelf;
VALUE Qself;

#define PUSH_SELF(s) {				\
    VALUE __saved_self__ = Qself;		\
    Qself = s;					\

#define POP_SELF() Qself = __saved_self__; }

struct FRAME *the_frame;
struct SCOPE *the_scope;
static struct FRAME *top_frame;
static struct SCOPE   *top_scope;

#define PUSH_FRAME() {			\
    struct FRAME _frame;		\
    _frame.prev = the_frame;		\
    _frame.file = sourcefile;		\
    _frame.line = sourceline;		\
    the_frame = &_frame;		\

#define POP_FRAME()  the_frame = _frame.prev; }

struct BLOCK {
    NODE *var;
    NODE *body;
    VALUE self;
    struct FRAME frame;
    struct SCOPE *scope;
    int level;
    int iter;
    struct RVarmap *d_vars;
    struct BLOCK *prev;
} *the_block;

#define PUSH_BLOCK(v,b) {		\
    struct BLOCK _block;		\
    _block.level = tag_level;		\
    _block.var = v;			\
    _block.body = b;			\
    _block.self = Qself;		\
    _block.frame = *the_frame;		\
    _block.frame.file = sourcefile;	\
    _block.frame.line = sourceline;	\
    _block.scope = the_scope;		\
    _block.d_vars = the_dyna_vars;	\
    _block.prev = the_block;		\
    _block.iter = iter->iter;		\
    the_block = &_block;		\

#define PUSH_BLOCK2(b) {		\
    b->prev = the_block;		\
    the_block = b;			\

#define POP_BLOCK() the_block = the_block->prev; }

struct RVarmap *the_dyna_vars;
#define PUSH_VARS() {			\
    struct RVarmap *_old;		\
    _old = the_dyna_vars;

#define POP_VARS() the_dyna_vars = _old; }

VALUE
dyna_var_ref(id)
    ID id;
{
    struct RVarmap *vars = the_dyna_vars;

    while (vars) {
	if (vars->id == id) return vars->val;
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
	    return;
	}
	vars = vars->next;
    }
    {
	NEWOBJ(_vars, struct RVarmap);
	OBJSETUP(_vars, Qnil, T_VARMAP);
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
} *iter;

#define ITER_NOT 0
#define ITER_PRE 1
#define ITER_CUR 2

#define PUSH_ITER(i) {			\
    struct iter _iter;			\
    _iter.prev = iter;			\
    _iter.iter = (i);			\
    iter = &_iter;			\

#define POP_ITER()			\
    iter = _iter.prev;			\
}

static int tag_level, target_level;
static struct tag {
    int level;
    jmp_buf buf;
    struct gc_list *gclist;
    VALUE self;
    struct FRAME *frame;
    struct iter *iter;
    struct tag *prev;
} *prot_tag;

#define PUSH_TAG() {			\
    struct tag _tag;			\
    _tag.level= ++tag_level;		\
    _tag.self = Qself;			\
    _tag.frame = the_frame;		\
    _tag.iter = iter;			\
    _tag.prev = prot_tag;		\
    prot_tag = &_tag;			\

#define EXEC_TAG()    (setjmp(prot_tag->buf))

#define JUMP_TAG(val) {			\
    Qself = prot_tag->self;		\
    the_frame = prot_tag->frame;	\
    iter = prot_tag->iter;		\
    longjmp(prot_tag->buf,(val));	\
}

#define POP_TAG()			\
    tag_level--;			\
    prot_tag = _tag.prev;		\
}

#define TAG_RETURN	1
#define TAG_BREAK	2
#define TAG_CONTINUE	3
#define TAG_RETRY	4
#define TAG_REDO	5
#define TAG_FAIL	6
#define TAG_EXIT	7

#define IN_BLOCK   0x08

struct RClass *the_class;
struct class_link {
    struct RClass *class;
    struct class_link *prev;
} *class_link;

#define PUSH_CLASS() {			\
    struct class_link _link;		\
    _link.class = the_class;		\
    _link.prev = class_link;		\
    class_link = &_link			\

#define POP_CLASS()			\
    the_class = class_link->class;	\
    class_link = _link.prev; }

#define PUSH_SCOPE() {			\
    struct SCOPE *_old;			\
    NEWOBJ(_scope, struct SCOPE);	\
    OBJSETUP(_scope, Qnil, T_SCOPE);	\
    _old = the_scope;			\
    the_scope = _scope;			\

#define POP_SCOPE() \
    if (the_scope->flag == SCOPE_ALLOCA) {\
	the_scope->local_vars = 0;\
	the_scope->local_tbl  = 0;\
    }\
    the_scope = _old;\
}

static VALUE rb_eval();
static VALUE f_eval();

static VALUE rb_call();
VALUE rb_apply();
VALUE rb_xstring();
void rb_fail();

VALUE rb_rescue();

static void module_setup();

static VALUE masign();
static void asign();

static VALUE last_val;

extern VALUE rb_stderr;

extern int   sourceline;
extern char *sourcefile;

static ID last_func;
static void
error_print(last_func)
    ID last_func;
{
    if (errat) {
	fwrite(RSTRING(errat)->ptr, 1, RSTRING(errat)->len, stderr);
	if (last_func) {
	    fprintf(stderr, ":in `%s': ", rb_id2name(last_func));
	}
	else {
	    fprintf(stderr, ": ");
	}
    }

    if (errstr) {
	fwrite(RSTRING(errstr)->ptr, 1, RSTRING(errstr)->len, stderr);
	if (RSTRING(errstr)->ptr[RSTRING(errstr)->len - 1] != '\n') {
	    putc('\n', stderr);
	}
    }
    else {
	fprintf(stderr, "unhandled failure.\n");
    }
}

extern char **environ;
char **origenviron;

void
ruby_init(argc, argv, envp)
    int argc;
    char **argv, **envp;
{
    int state;
    static struct FRAME frame;
    the_frame = top_frame = &frame;

    origenviron = environ;
#ifdef NT
    NtInitialize(&argc, &argv);
#endif

    init_heap();
    PUSH_SCOPE();
    the_scope->local_vars = 0;
    the_scope->local_tbl  = 0;
    top_scope = the_scope;

    PUSH_TAG();
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	rb_call_inits();
	the_class = (struct RClass*)cObject;
	ruby_options(argc, argv, envp);
    }
    POP_ITER();
    POP_TAG();
    POP_SCOPE();
    the_scope = top_scope;

    if (state == TAG_EXIT) {
	rb_trap_exit();
	exit(FIX2UINT(last_val));
    }
    if (state) {
	error_print(last_func);
    }
}

static VALUE
Eval()
{
    VALUE result = Qnil;
    NODE *tree;
    int   state;

    if (!eval_tree) return Qnil;

    tree = eval_tree;
    eval_tree = 0;

    result = rb_eval(tree);
    return result;
}

void
ruby_run()
{
    int state;

    if (nerrs > 0) exit(nerrs);

    init_stack();
    rb_define_variable("$!", &errstr);
    errat = Qnil;		/* clear for execution */

    PUSH_TAG();
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	Eval();
	rb_trap_exit();
    }
    POP_ITER();
    POP_TAG();

    switch (state) {
      case 0:
	break;
      case TAG_RETURN:
	Fatal("unexpected return");
	break;
      case TAG_CONTINUE:
	Fatal("unexpected continue");
	break;
      case TAG_BREAK:
	Fatal("unexpected break");
	break;
      case TAG_REDO:
	Fatal("unexpected redo");
	break;
      case TAG_RETRY:
	Fatal("retry outside of protect clause");
	break;
      case TAG_FAIL:
	error_print(last_func);
	exit(1);
	break;
      case TAG_EXIT:
	exit(FIX2UINT(last_val));
	break;
      default:
	Bug("Unknown longjmp status %d", state);
	break;
    }
    exit(0);
}

static void
syntax_error()
{
    VALUE mesg;

    mesg = errstr;
    nerrs = 0;
    errstr = str_new2("syntax error in eval():\n");
    str_cat(errstr, RSTRING(mesg)->ptr, RSTRING(mesg)->len);
    rb_fail(errstr);
}

VALUE
rb_eval_string(str)
    char *str;
{
    char *oldsrc = sourcefile;

    lex_setsrc("(eval)", str, strlen(str));
    eval_tree = 0;
    PUSH_VARS();
    yyparse();
    POP_VARS();
    sourcefile = oldsrc;
    if (nerrs == 0) {
	return Eval();
    }
    else {
	syntax_error();
    }
    return Qnil;		/* not reached */
}

void
rb_eval_cmd(cmd, arg)
    VALUE cmd, arg;
{
    int state;
    struct SCOPE *saved_scope;

    if (TYPE(cmd) != T_STRING) {
	if (TYPE(cmd) == T_OBJECT
	    && obj_is_kind_of(cmd, cProc)) {
	    proc_call(cmd, arg);
	    return;
	}
    }

    PUSH_SELF(TopSelf);
    PUSH_CLASS();
    PUSH_TAG();
    saved_scope = the_scope;
    the_scope = top_scope;

    the_class = (struct RClass*)cObject;

    if ((state = EXEC_TAG()) == 0) {
	f_eval(Qself, cmd);
    }

    the_scope = saved_scope;
    POP_TAG();
    POP_CLASS();
    POP_SELF();

    switch (state) {
      case 0:
	break;
      case TAG_RETURN:
	Fatal("unexpected return");
	break;
      case TAG_CONTINUE:
	Fatal("unexpected continue");
	break;
      case TAG_BREAK:
	Fatal("unexpected break");
	break;
      case TAG_REDO:
	Fatal("unexpected redo");
	break;
      case TAG_RETRY:
	Fatal("retry outside of protect clause");
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
#ifdef SAFE_SIGHANDLE
    int state;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	rb_eval_cmd(cmd, ary_new3(1, INT2FIX(sig)));
    }
    POP_TAG();
    if (state) {
	trap_immediate = 0;
	JUMP_TAG(state);
    }
#else
    rb_eval_cmd(cmd, ary_new3(1, INT2FIX(sig)));
#endif
}

#define SETUP_ARGS {\
    NODE *n = node->nd_args;\
    if (!n) {\
	argc = 0;\
	argv = 0;\
    }\
    else if (nd_type(n) == NODE_ARRAY) {\
	argc=n->nd_alen;\
        if (argc > 0) {\
            int i;\
	    n = node->nd_args;\
	    argv = ALLOCA_N(VALUE,argc);\
	    for (i=0;i<argc;i++) {\
		argv[i] = rb_eval(n->nd_head);\
		n=n->nd_next;\
	    }\
        }\
        else {\
	    argc = 0;\
	    argv = 0;\
        }\
    }\
    else {\
        VALUE args = rb_eval(n);\
	if (TYPE(args) != T_ARRAY)\
	    args = rb_to_a(args);\
        argc = RARRAY(args)->len;\
	argv = ALLOCA_N(VALUE, argc);\
	MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);\
    }\
}

#define RETURN(v) do { result = (v); goto finish; } while (0)

static VALUE
rb_eval(node)
    register NODE *node;
{
    int   state;
    VALUE result = Qnil;

  again:
    if (node == Qnil) RETURN(Qnil);

    sourceline = node->line;
    sourcefile = node->file;

    switch (nd_type(node)) {
      case NODE_BLOCK:
	while (node) {
	    result = rb_eval(node->nd_head);
	    node = node->nd_next;
	}
	break;

      case NODE_SELF:
	RETURN(Qself);

      case NODE_NIL:
	RETURN(Qnil);

      case NODE_IF:
	if (rb_eval(node->nd_cond)) {
	    node = node->nd_body;
	}
	else {
	    node = node->nd_else;
	}
	if (node) goto again;
	RETURN(Qnil);

      case NODE_CASE:
	{
	    VALUE val;

	    val = rb_eval(node->nd_head);
	    node = node->nd_body;
	    while (node) {
		if (nd_type(node) == NODE_WHEN) {
		    NODE *tag = node->nd_head;

		    while (tag) {
			if (rb_funcall(rb_eval(tag->nd_head), match, 1, val)){
			    RETURN(rb_eval(node->nd_body));
			}
			tag = tag->nd_next;
		    }
		}
		else {
		    RETURN(rb_eval(node));
		}
		node = node->nd_next;
	    }
	}
	RETURN(Qnil);

      case NODE_WHILE:
	PUSH_TAG();
	switch (state = EXEC_TAG()) {
	  case 0:
	  while_cont:
	    while (rb_eval(node->nd_cond)) {
	      while_redo:
		rb_eval(node->nd_body);
	    }
	    break;
	  case TAG_REDO:
	    state = 0;
	    goto while_redo;
	  case TAG_CONTINUE:
	    state = 0;
	    goto while_cont;
	  default:
	    break;
	}
	POP_TAG();
	switch (state) {
	  case 0:
	  case TAG_BREAK:
	    break;
	  default:
	    JUMP_TAG(state);
	    break;
	}
	RETURN(Qnil);

      case NODE_WHILE2:
	PUSH_TAG();
	switch (state = EXEC_TAG()) {
	  case 0:
	  while2_cont:
	    do {
	      while2_redo:
		rb_eval(node->nd_body);
	    } while (rb_eval(node->nd_cond));
	    break;
	  case TAG_REDO:
	    state = 0;
	    goto while2_redo;
	  case TAG_CONTINUE:
	    state = 0;
	    goto while2_cont;
	  default:
	  case TAG_BREAK:
	    break;
	}
	POP_TAG();
	switch (state) {
	  case 0:
	  case TAG_BREAK:
	    break;
	  default:
	    JUMP_TAG(state);
	}
	RETURN(Qnil);

      case NODE_ITER:
      case NODE_FOR:
	{
	  iter_retry:
	    PUSH_BLOCK(node->nd_var, node->nd_body);
	    PUSH_TAG();

	    state = EXEC_TAG();
	    if (state == 0) {
		if (nd_type(node) == NODE_ITER) {
		    PUSH_ITER(ITER_PRE);
		    result = rb_eval(node->nd_iter);
		    POP_ITER();
		}
		else {
		    VALUE recv;

		    recv = rb_eval(node->nd_iter);
		    PUSH_ITER(ITER_PRE);
		    result = rb_call(CLASS_OF(recv),recv,each,0,0,0);
		    POP_ITER();
		}
	    }
	    POP_TAG();
	    POP_BLOCK();
	    switch (state) {
	      case 0:
		break;

	      case TAG_RETRY:
		goto iter_retry;

	      case IN_BLOCK|TAG_BREAK:
		if (target_level != tag_level) {
		    JUMP_TAG(state);
		}
		result = Qnil;
		break;
	      case IN_BLOCK|TAG_RETURN:
		if (target_level == tag_level) {
		    state &= ~IN_BLOCK;
		}
		/* fall through */
	      default:
		JUMP_TAG(state);
	    }
	}
	break;

      case NODE_FAIL:
	{
	    VALUE mesg = rb_eval(node->nd_stts);
	    if (mesg) Check_Type(mesg, T_STRING);
	    rb_fail(mesg);
	}
	break;

      case NODE_YIELD:
	result = rb_yield(rb_eval(node->nd_stts));
	break;

      case NODE_BEGIN:
	if (node->nd_resq == Qnil && node->nd_ensr == Qnil) {
	    node = node->nd_head;
	    goto again;
	}
	else {
	    VALUE (*r_proc)();

	    if (node->nd_resq == (NODE*)1) {
		r_proc = 0;
	    }
	    else {
		r_proc = rb_eval;
	    }
	    if (node->nd_ensr) {
		PUSH_TAG();
		if ((state = EXEC_TAG()) == 0) {
		    result = rb_rescue(rb_eval, node->nd_head, r_proc, node->nd_resq);
		}
		POP_TAG();
		/* ensure clause */
		rb_eval(node->nd_ensr);
		if (state) {
		    JUMP_TAG(state);
		}
	    }
	    else {
		result = rb_rescue(rb_eval, node->nd_head, r_proc, node->nd_resq);
	    }
	}
	break;

      case NODE_AND:
	if ((result = rb_eval(node->nd_1st)) == FALSE) RETURN(result);
	node = node->nd_2nd;
	goto again;

      case NODE_OR:
	if ((result = rb_eval(node->nd_1st)) != FALSE) RETURN(result);
	node = node->nd_2nd;
	goto again;

      case NODE_NOT:
	if (rb_eval(node->nd_body)) result = FALSE;
	else result = TRUE;
	break;

      case NODE_DOT2:
      case NODE_DOT3:
	RETURN(range_new(rb_eval(node->nd_beg), rb_eval(node->nd_end)));

      case NODE_FLIP2:		/* like AWK */
	if (node->nd_state == 0) {
	    if (rb_eval(node->nd_beg)) {
		node->nd_state = rb_eval(node->nd_end)?0:1;
		result = TRUE;
	    }
	    result = FALSE;
	}
	else {
	    if (rb_eval(node->nd_end)) {
		node->nd_state = 0;
	    }
	    result = TRUE;
	}
	break;

      case NODE_FLIP3:		/* like SED */
	if (node->nd_state == 0) {
	    if (rb_eval(node->nd_beg)) {
		node->nd_state = 1;
		result = TRUE;
	    }
	    result = FALSE;
	}
	else {
	    if (rb_eval(node->nd_end)) {
		node->nd_state = 0;
	    }
	    result = TRUE;
	}
	break;

      case NODE_BREAK:
	JUMP_TAG(TAG_BREAK);
	break;

      case NODE_CONTINUE:
	JUMP_TAG(TAG_CONTINUE);
	break;

      case NODE_REDO:
	JUMP_TAG(TAG_REDO);
	break;

      case NODE_RETRY:
	JUMP_TAG(TAG_RETRY);
	break;

      case NODE_RETURN:
	if (node->nd_stts) last_val = rb_eval(node->nd_stts);
	JUMP_TAG(TAG_RETURN);
	break;

      case NODE_CALL:
	{
	    VALUE recv;
	    int argc; VALUE *argv; /* used in SETUP_ARGS */

	    PUSH_ITER(ITER_NOT);
	    recv = rb_eval(node->nd_recv);
	    SETUP_ARGS;
	    POP_ITER();
	    result = rb_call(CLASS_OF(recv),recv,node->nd_mid,argc,argv,0);
	}
	break;

      case NODE_FCALL:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */

	    PUSH_ITER(ITER_NOT);
	    SETUP_ARGS;
	    POP_ITER();
	    result = rb_call(CLASS_OF(Qself),Qself,node->nd_mid,argc,argv,1);
	}
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
		SETUP_ARGS;
		POP_ITER();
	    }

	    PUSH_ITER(iter->iter?ITER_PRE:ITER_NOT);
	    result = rb_call(the_frame->last_class->super, Qself,
			     the_frame->last_func, argc, argv, 1);
	    POP_ITER();
	}
	break;

      case NODE_SCOPE:
	{
	    PUSH_SCOPE();
	    PUSH_TAG();
	    if (node->nd_cnt > 0) {
		the_scope->local_vars = ALLOCA_N(VALUE, node->nd_cnt);
		MEMZERO(the_scope->local_vars, VALUE, node->nd_cnt);
		the_scope->local_tbl = node->nd_tbl;
	    }
	    else {
		the_scope->local_vars = 0;
		the_scope->local_tbl  = 0;
	    }
	    if ((state = EXEC_TAG()) == 0) {
		result = rb_eval(node->nd_body);
	    }
	    POP_TAG();
	    POP_SCOPE();
	    if (state != 0) JUMP_TAG(state);
	}
	break;

      case NODE_OP_ASGN1:
	{
	    VALUE recv, args, val;
	    NODE *rval;

	    recv = rb_eval(node->nd_recv);
	    rval = node->nd_args->nd_head;

	    args = rb_eval(node->nd_args->nd_next);
	    val = rb_apply(recv, aref, args);
	    val = rb_funcall(val, node->nd_mid, 1, rb_eval(rval));
	    ary_push(args, val);
	    rb_apply(recv, aset, args);
	    result = val;
	}
	break;

      case NODE_OP_ASGN2:
	{
	    ID id = node->nd_aid;
	    VALUE recv, val;

	    recv = rb_funcall(rb_eval(node->nd_recv), id, 0);

	    id = id_attrset(id);

	    val = rb_eval(node->nd_value);
	    rb_funcall(recv, id, 1, val);
	    result = val;
	}
	break;

      case NODE_MASGN:
	result = masign(node, rb_eval(node->nd_value));
	break;

      case NODE_LASGN:
	if (the_scope->local_vars == 0)
	    Bug("unexpected local variable asignment");
	result = the_scope->local_vars[node->nd_cnt] = rb_eval(node->nd_value);
	break;

      case NODE_DASGN:
	result = dyna_var_asgn(node->nd_vid, rb_eval(node->nd_value));
	break;

      case NODE_GASGN:
	{
	    VALUE val;

	    val = rb_eval(node->nd_value);
	    rb_gvar_set(node->nd_entry, val);
	    result = val;
	}
	break;

      case NODE_IASGN:
	{
	    VALUE val;

	    val = rb_eval(node->nd_value);
	    rb_ivar_set(Qself, node->nd_vid, val);
	    result = val;
	}
	break;

      case NODE_CASGN:
	{
	    VALUE val;

	    val = rb_eval(node->nd_value);
	    rb_const_set(the_class, node->nd_vid, val);
	    result = val;
	}
	break;

      case NODE_LVAR:
	if (the_scope->local_vars == 0)
	    Bug("unexpected local variable");
	result = the_scope->local_vars[node->nd_cnt];
	break;

      case NODE_DVAR:
	result = dyna_var_ref(node->nd_vid);
	break;

      case NODE_GVAR:
	result = rb_gvar_get(node->nd_entry);
	break;

      case NODE_IVAR:
	result = rb_ivar_get(Qself, node->nd_vid);
	break;

      case NODE_CVAR:
	{
	    VALUE val;

	    val = rb_const_get(node->nd_rval->nd_clss, node->nd_vid);
	    nd_set_type(node, NODE_CONST);
	    node->nd_cval = val;
	    result = val;
	}
	break;

      case NODE_CONST:
	result = node->nd_cval;
	break;

      case NODE_COLON2:
	{
	    VALUE cls;

	    cls = rb_eval(node->nd_head);
	    switch (TYPE(cls)) {
	      case T_CLASS:
	      case T_MODULE:
		break;
	      default:
		Check_Type(cls, T_CLASS);
		break;
	    }
	    result = rb_const_get(cls, node->nd_mid);
	}
	break;

#define MATCH_DATA the_scope->local_vars[node->nd_cnt]
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
		key = rb_eval(list->nd_head);
		list = list->nd_next;
		if (list == 0)
		    Bug("odd number list for Hash");
		val = rb_eval(list->nd_head);
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
		RARRAY(ary)->ptr[i++] = rb_eval(node->nd_head);
		RARRAY(ary)->len = i;
	    }

	    result = ary;
	}
	break;

      case NODE_STR:
	result = str_new3(node->nd_lit);
	break;

      case NODE_STR2:
      case NODE_XSTR2:
      case NODE_DREGX:
	{
	    VALUE str, str2;
	    NODE *list = node->nd_next;

	    str = str_new3(node->nd_lit);
	    while (list) {
		if (nd_type(list->nd_head) == NODE_STR) {
		    str2 = list->nd_head->nd_lit;
		}
		else {
		    str2 = rb_eval(list->nd_head);
		}
		if (str2) {
		    str2 = obj_as_string(str2);
		    str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
		}
		list = list->nd_next;
	    }
	    if (nd_type(node) == NODE_DREGX) {
		VALUE re = reg_new(RSTRING(str)->ptr, RSTRING(str)->len,
				   node->nd_cflag);
		result = re;
	    }
	    else if (nd_type(node) == NODE_XSTR2) {
		result = rb_xstring(str);
	    }
	    else {
		result = str;
	    }
	}
	break;

      case NODE_XSTR:
	result = rb_xstring(node->nd_lit);
	break;

      case NODE_LIT:
	result = node->nd_lit;
	break;

      case NODE_ATTRSET:
	if (the_frame->argc != 1)
	    Fail("Wrong # of arguments(%d for 1)", the_frame->argc);
	result = rb_ivar_set(Qself, node->nd_vid, the_frame->argv[0]);
	break;

      case NODE_DEFN:
	if (node->nd_defn) {
	    NODE *body;
	    VALUE origin;
	    int noex;

	    body = search_method(the_class, node->nd_mid, &origin);
	    if (body && verbose && origin != (VALUE)the_class
		&& body->nd_noex != node->nd_noex) {
		Warning("change method %s's scope", rb_id2name(node->nd_mid));
	    }

	    if (body) noex = body->nd_noex;
	    else      noex = node->nd_noex; /* default(1 for toplevel) */

	    rb_add_method(the_class, node->nd_mid, node->nd_defn, noex);
	    result = Qnil;
	}
	break;

      case NODE_DEFS:
	if (node->nd_defn) {
	    VALUE recv = rb_eval(node->nd_recv);

	    if (recv == Qnil) {
		Fail("Can't define method \"%s\" for nil",
		     rb_id2name(node->nd_mid));
	    }
	    rb_funcall(recv, rb_intern("singleton_method_added"),
		       1, INT2FIX(node->nd_mid));
	    rb_add_method(rb_singleton_class(recv),node->nd_mid,node->nd_defn,
			  NOEX_PUBLIC);
	    result = Qnil;
	}
	break;

      case NODE_UNDEF:
	rb_add_method(the_class, node->nd_mid, Qnil, NOEX_PUBLIC);
	result = Qnil;
	break;

      case NODE_ALIAS:
	rb_alias(the_class, node->nd_new, node->nd_old);
	result = Qnil;
	break;

      case NODE_CLASS:
	{
	    VALUE super, class;
	    struct RClass *tmp;

	    if (node->nd_super) {
		super = rb_eval(node->nd_super);
		if (super == Qnil || TYPE(super) != T_CLASS) {
		    Fail("superclass undefined");
		}
	    }
	    else {
		super = Qnil;
	    }

	    if (rb_const_defined(the_class, node->nd_cname)) {
		class = rb_const_get(the_class, node->nd_cname);
		if (super) {
		    if (TYPE(class) != T_CLASS)
			Fail("%s is not a class", rb_id2name(node->nd_cname));
		    tmp = RCLASS(class)->super;
		    while (FL_TEST(tmp, FL_SINGLE)) {
			tmp = RCLASS(tmp)->super;
		    }
		    while (TYPE(tmp) == T_ICLASS) {
			tmp = RCLASS(tmp)->super;
		    }
		    if (tmp != RCLASS(super))
			Fail("superclass mismatch for %s",
			     rb_id2name(node->nd_cname));
		}
		Warning("extending class %s", rb_id2name(node->nd_cname));
	    }
	    else {
		if (super == Qnil) super = cObject;
		class = rb_define_class_id(node->nd_cname, super);
		rb_const_set(the_class, node->nd_cname, class);
		rb_set_class_path(class,the_class,rb_id2name(node->nd_cname));
	    }

	    module_setup(class, node->nd_body);
	    result = class;
	}
	break;

      case NODE_MODULE:
	{
	    VALUE module;

	    if (rb_const_defined(the_class, node->nd_cname)) {
		module = rb_const_get(the_class, node->nd_cname);
		if (TYPE(module) != T_MODULE)
		    Fail("%s is not a module", rb_id2name(node->nd_cname));
		Warning("extending module %s", rb_id2name(node->nd_cname));
	    }
	    else {
		module = rb_define_module_id(node->nd_cname);
		rb_const_set(the_class, node->nd_cname, module);
		rb_set_class_path(module,the_class,rb_id2name(node->nd_cname));
	    }

	    module_setup(module, node->nd_body);
	    result = module;
	}
	break;

      case NODE_DEFINED:
	{
	    VALUE obj;

	    node = node->nd_head;
	    switch (nd_type(node)) {
	      case NODE_SUPER:
	      case NODE_ZSUPER:
		if (the_frame->last_func == 0) result = FALSE;
		else {
		    result = method_boundp(the_frame->last_class->super,
					   the_frame->last_func, 1);
		}
		break;
		
	      case NODE_FCALL:
		obj = CLASS_OF(Qself);
		goto check_bound;

	      case NODE_CALL:
		PUSH_TAG();
		if ((state = EXEC_TAG()) == 0) {
		    obj = rb_eval(node->nd_recv);
		}
		POP_TAG();
		if (state == TAG_FAIL) {
		    result = FALSE;
		    break;
		}
		else {
		    if (state) JUMP_TAG(state);
		    obj = CLASS_OF(obj);
		  check_bound:
		    if (method_boundp(obj, node->nd_mid,
				      nd_type(node)== NODE_CALL)) {
			result = TRUE;
		    }
		    else result = FALSE;
		}
		break;

	      case NODE_YIELD:
		result = iterator_p();
		break;

	      case NODE_BREAK:
	      case NODE_CONTINUE:
	      case NODE_REDO:
	      case NODE_RETRY:

	      case NODE_SELF:
	      case NODE_NIL:
	      case NODE_FAIL:
	      case NODE_ATTRSET:
	      case NODE_DEFINED:

	      case NODE_OP_ASGN1:
	      case NODE_OP_ASGN2:
	      case NODE_MASGN:
	      case NODE_LASGN:
	      case NODE_DASGN:
	      case NODE_GASGN:
	      case NODE_IASGN:
	      case NODE_CASGN:
	      case NODE_LVAR:
	      case NODE_DVAR:
		result = TRUE;
		break;

	      case NODE_GVAR:
		result = rb_gvar_defined(node->nd_entry);
		break;

	      case NODE_IVAR:
		result = rb_ivar_defined(node->nd_vid);
		break;

	      case NODE_CVAR:
		result = rb_const_defined(node->nd_rval->nd_clss, node->nd_vid);
		break;

	      case NODE_CONST:
		result = TRUE;
		break;

	      case NODE_COLON2:
		PUSH_TAG();
		if ((state = EXEC_TAG()) == 0) {
		    obj = rb_eval(node->nd_head);
		}
		POP_TAG();
		if (state == TAG_FAIL) result = FALSE;
		else {
		    if (state) JUMP_TAG(state);
		    result = rb_const_defined(obj, node->nd_mid);
		}
		break;

	      case NODE_NTH_REF:
		result = reg_nth_defined(node->nd_nth, MATCH_DATA);
		break;

	      case NODE_BACK_REF:
		result = reg_nth_defined(0, MATCH_DATA);
		break;

	      default:
		PUSH_TAG();
		if ((state = EXEC_TAG()) == 0) {
		    rb_eval(node);
		}
		POP_TAG();
		if (state == TAG_FAIL) result = FALSE;
		else {
		    if (state) JUMP_TAG(state);
		    result = TRUE;
		}
	    }
	}
	break;

      default:
	Bug("unknown node type %d", nd_type(node));
    }
  finish:
#ifdef SAFE_SIGHANDLE
    if (trap_pending) {
	rb_trap_exec();
    }
#endif
    return result;		/* not reached */
}

static void
module_setup(module, node)
    VALUE module;
    NODE *node;
{
    int state;

    /* fill c-ref */
    node->nd_clss = module;
    node = node->nd_body;

    PUSH_CLASS();
    the_class = (struct RClass*)module;
    PUSH_SELF((VALUE)the_class);
    PUSH_SCOPE();

    if (node->nd_cnt > 0) {
	the_scope->local_vars = ALLOCA_N(VALUE, node->nd_cnt);
	MEMZERO(the_scope->local_vars, VALUE, node->nd_cnt);
	the_scope->local_tbl = node->nd_tbl;
    }
    else {
	the_scope->local_vars = 0;
	the_scope->local_tbl  = 0;
    }

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	rb_eval(node->nd_body);
    }
    POP_TAG();
    POP_SCOPE();
    POP_SELF();
    POP_CLASS();
    if (state) JUMP_TAG(state);
}

VALUE
rb_responds_to(obj, id)
    VALUE obj;
    ID id;
{
    if (rb_method_boundp(CLASS_OF(obj), id)) {
	return TRUE;
    }
    return FALSE;
}

void
rb_exit(status)
    int status;
{
    last_val = INT2FIX(status);
    if (prot_tag)
	JUMP_TAG(TAG_EXIT);
    rb_trap_exit();
    exit(FIX2UINT(last_val));
}

static VALUE
f_exit(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE status;

    if (rb_scan_args(argc, argv, "01", &status) == 1) {
	Need_Fixnum(status);
    }
    else {
	status = INT2FIX(0);
    }
    last_val = status;
    JUMP_TAG(TAG_EXIT);

    return Qnil;		/* not reached */
}

void
rb_break()
{
    JUMP_TAG(TAG_BREAK);
}

void
rb_redo()
{
    JUMP_TAG(TAG_REDO);
}

void
rb_retry()
{
    JUMP_TAG(TAG_RETRY);
}

void
rb_fail(mesg)
    VALUE mesg;
{
    char buf[BUFSIZ];

    if (errat == Qnil && mesg == Qnil) {
	errstr = Qnil;
    }

    if (errat == Qnil && sourcefile) {
	if (the_frame->last_func) {
	    last_func = the_frame->last_func;
	}
	sprintf(buf, "%s:%d", sourcefile, sourceline);
	errat = str_new2(buf);
    }

    if (mesg) {
	errstr = mesg;
    }
    if (prot_tag->level == 0) error_print(last_func);
    JUMP_TAG(TAG_FAIL);
}

VALUE
iterator_p()
{
    if (iter->iter) return TRUE;
    return FALSE;
}

static VALUE
f_iterator_p()
{
    if (iter->prev && iter->prev->iter) return TRUE;
    return FALSE;
}

VALUE
rb_yield_0(val, self)
    VALUE val, self;
{
    struct BLOCK *block;
    NODE *node;
    int   state;
    VALUE result = Qnil;
    struct SCOPE *old_scope;
    struct FRAME frame;

    if (!iterator_p()) {
	Fail("yield called out of iterator");
    }

    PUSH_VARS();
    block = the_block;
    frame = block->frame;
    frame.prev = the_frame;
    the_frame = &(frame);
    old_scope = the_scope;
    the_scope = block->scope;
    the_block = block->prev;
    the_dyna_vars = block->d_vars;
    if (block->var) {
	if (nd_type(block->var) == NODE_MASGN)
	    masign(block->var, val);
	else
	    asign(block->var, val);
    }
    node = block->body;

    PUSH_ITER(block->iter);
    PUSH_SELF(self?self:block->self);
    PUSH_TAG();
    switch (state = EXEC_TAG()) {
      redo:
      case 0:
	if (!node) {
	    result = Qnil;
	}
	else if (nd_type(node) == NODE_CFUNC) {
	    result = (*node->nd_cfnc)(val,node->nd_argc);
	}
	else {
	    result = rb_eval(node);
	}
	break;
      case TAG_REDO:
	goto redo;
      case TAG_CONTINUE:
	state = 0;
	break;
      case TAG_BREAK:
      case TAG_RETURN:
	target_level = block->level;
	state = IN_BLOCK|state;
	break;
      default:
	break;
    }
    POP_TAG();
    POP_SELF();
    POP_ITER();
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
    return Qnil;
}

static VALUE
masign(node, val)
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
	    asign(list->nd_head, RARRAY(val)->ptr[i]);
	    list = list->nd_next;
	}
	if (node->nd_args) {
	    if (!list && i<len) {
		asign(node->nd_args, ary_new4(len-i, RARRAY(val)->ptr+i));
	    }
	    else {
		asign(node->nd_args, Qnil);
	    }
	}
    }
    else if (node->nd_args) {
	asign(node->nd_args, Qnil);
    }
    while (list) {
	asign(list->nd_head, Qnil);
	list = list->nd_next;
    }
    return val;
}

static void
asign(lhs, val)
    NODE *lhs;
    VALUE val;
{
    switch (nd_type(lhs)) {
      case NODE_GASGN:
	rb_gvar_set(lhs->nd_entry, val);
	break;

      case NODE_IASGN:
	rb_ivar_set(Qself, lhs->nd_vid, val);
	break;

      case NODE_LASGN:
	if (the_scope->local_vars == 0)
	    Bug("unexpected iterator variable asignment");
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
	    recv = rb_eval(lhs->nd_recv);
	    if (lhs->nd_args->nd_head == Qnil) {
		/* attr set */
		rb_funcall(recv, lhs->nd_mid, 1, val);
	    }
	    else {
		/* array set */
		VALUE args;

		args = rb_eval(lhs->nd_args);
		RARRAY(args)->ptr[RARRAY(args)->len-1] = val;
		rb_apply(recv, lhs->nd_mid, args);
	    }
	}
	break;

      default:
	Bug("bug in variable asignment");
	break;
    }
}

VALUE
rb_iterate(it_proc, data1, bl_proc, data2)
    VALUE (*it_proc)(), (*bl_proc)();
    void *data1, *data2;
{
    int   state;
    VALUE retval = Qnil;
    NODE *node = NEW_CFUNC(bl_proc, data2);

  iter_retry:
    PUSH_ITER(ITER_PRE);
    PUSH_BLOCK(Qnil, node);
    PUSH_TAG();

    state = EXEC_TAG();
    if (state == 0) {
	retval = (*it_proc)(data1);
    }

    POP_TAG();
    POP_BLOCK();
    POP_ITER();

    switch (state) {
      case 0:
	break;

      case TAG_RETRY:
	goto iter_retry;

      case IN_BLOCK|TAG_BREAK:
	if (target_level != tag_level) {
	    JUMP_TAG(state);
	}
	retval = Qnil;
	break;

      case IN_BLOCK|TAG_RETURN:
	if (target_level == tag_level) {
	    state &= ~IN_BLOCK;
	}
	/* fall through */
      default:
	JUMP_TAG(state);
    }

    return retval;
}

VALUE
rb_rescue(b_proc, data1, r_proc, data2)
    VALUE (*b_proc)(), (*r_proc)();
    void *data1, *data2;
{
    int   state;
    VALUE result = Qnil;
    volatile SIGHANDLE handle;

    PUSH_TAG();
    switch (state = EXEC_TAG()) {
      case 0:
	handle = sig_beg();
      retry_entry:
	result = (*b_proc)(data1);
	break;

      case TAG_FAIL:
	sig_end(handle);
	if (r_proc) {
	    PUSH_TAG();
	    state = EXEC_TAG();
	    if (state == 0) {
		result = (*r_proc)(data2);
	    }
	    POP_TAG();
	    if (state == TAG_RETRY) {
		goto retry_entry;
	    }
	}
	else {
	    state = 0;
	}
	if (state == 0) {
	    errat = Qnil;
	    last_func = 0;
	}
	break;

      default:
	sig_end(handle);
	break;
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
    int   state;
    VALUE result = Qnil;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	result = (*b_proc)(data1);
    }
    POP_TAG();

    (*e_proc)(data2);
    if (state != 0) {
	JUMP_TAG(state);
    }
    return result;
}

static int last_noex;

static VALUE
f_missing(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE desc;
    ID    id;
    char *format;
    struct FRAME *frame;

    id = FIX2INT(argv[0]);
    argc--; argv++;

    if (TYPE(obj) == T_STRING) {
	desc = krn_inspect(obj);
    }
    else {
	desc = obj_as_string(obj);
    }
    if (last_noex)
	format = "method `%s' not available for %s(%s)";
    else
	format = "undefined method `%s' for %s(%s)";

    /* fake frame */
    PUSH_FRAME();
    frame = the_frame->prev;
    *the_frame = *frame->prev;
    the_frame->prev = frame;

    Fail(format,
	 rb_id2name(id),
	 RSTRING(desc)->ptr,
	 rb_class2name(CLASS_OF(obj)));
    POP_FRAME();
}

static VALUE
rb_undefined(obj, id, argc, argv, noex)
    VALUE obj;
    ID    id;
    int   argc;
    VALUE*argv;
    int   noex;
{
    VALUE *nargv;

    nargv = ALLOCA_N(VALUE, argc+1);
    nargv[0] = INT2FIX(id);
    MEMCPY(nargv+1, argv, VALUE, argc);

    last_noex = noex;

    return rb_funcall2(obj, rb_intern("method_missing"), argc+1, nargv);
}

#define STACK_LEVEL_MAX 10000
static int stack_level;

static VALUE
rb_call(class, recv, mid, argc, argv, scope)
    struct RClass *class;
    VALUE recv;
    ID    mid;
    int argc;
    VALUE *argv;
    int scope;
{
    NODE  *body;
    int    noex;
    VALUE  result = Qnil;
    struct cache_entry *ent;
    int itr;
    enum node_type type;

    /* is it in the method cache? */
    ent = cache + EXPR1(class, mid);
    if (ent->mid == mid && ent->class == class) {
	class = ent->origin;
	mid   = ent->mid;
	body  = ent->method;
	noex  = ent->noex;
    }
    else {
	ID id = mid;

	if ((body = rb_get_method_body(&class, &id, &noex)) == FALSE) {
	    return rb_undefined(recv, mid, argc, argv, 0);
	}
	mid = id;
    }

    switch (noex) {
      case NOEX_PUBLIC:
	break;
      case NOEX_PRIVATE:
	if (scope == 0)		/* receiver specified */
	    return rb_undefined(recv, mid, argc, argv, 1);
	break;
    }

    switch (iter->iter) {
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
	/* for re-scoped method */
	return rb_call(class->super, recv, mid, argc, argv, scope?scope:1);
    }

    if (stack_level++ > STACK_LEVEL_MAX)
	Fail("stack level too deep");

    PUSH_ITER(itr);
    PUSH_SELF(recv);
    PUSH_FRAME();
    the_frame->last_func = mid;
    the_frame->last_class = class;
    the_frame->argc = argc;
    the_frame->argv = argv;

    switch (type) {
      case NODE_CFUNC:
	{
	    int len = body->nd_argc;

	    if (len >= 0 && argc != len) {
		Fail("Wrong # of arguments(%d for %d)", argc, len);
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
			len, rb_class2name(class), rb_id2name(mid));
		}
		else {
		    Fail("too many arguments(%d)", len);
		}
		break;
	    }
	}
	break;

	/* for attr get/set */
      case NODE_ATTRSET:
      case NODE_IVAR:
	result = rb_eval(body);
	break;

      default:
	{
	    int    state;
	    VALUE *local_vars;

	    PUSH_SCOPE();

	    if (body->nd_cnt > 0) {
		local_vars = ALLOCA_N(VALUE, body->nd_cnt);
		MEMZERO(local_vars, VALUE, body->nd_cnt);
		the_scope->local_tbl = body->nd_tbl;
		the_scope->local_vars = local_vars;
	    }
	    else {
		local_vars = the_scope->local_vars = 0;
		the_scope->local_tbl  = 0;
	    }
	    body = body->nd_body;

	    PUSH_TAG();
	    state = EXEC_TAG();
	    if (state == 0) {
		if (nd_type(body) == NODE_BLOCK) {
		    NODE *node = body->nd_head;
		    int i;

		    if (nd_type(node) != NODE_ARGS) {
			Bug("no argument-node");
		    }

		    body = body->nd_next;
		    i = node->nd_cnt;
		    if (i > argc
			|| (node->nd_rest == -1
			    && i+(node->nd_opt?node->nd_opt->nd_alen:0)<argc)){
			Fail("Wrong # of arguments(%d for %d)", argc, i);
		    }

		    if (local_vars) {
			if (i > 0) {
			    MEMCPY(local_vars, argv, VALUE, i);
			}
			argv += i; argc -= i;
			if (node->nd_opt) {
			    NODE *opt = node->nd_opt;

			    while (opt && argc) {
				asign(opt->nd_head, *argv);
				argv++; argc--;
				opt = opt->nd_next;
			    }
			    rb_eval(opt);
			}
			if (node->nd_rest >= 0) {
			    if (argc > 0)
				local_vars[node->nd_rest]=ary_new4(argc,argv);
			    else
				local_vars[node->nd_rest] = ary_new2(0);
			}
		    }
		}
		else if (nd_type(body) == NODE_ARGS) {
		    body = 0;
		}
		result = rb_eval(body);
	    }
	    POP_TAG();
	    POP_SCOPE();
	    switch (state) {
	      case 0:
		break;
	      case TAG_CONTINUE:
		Fatal("unexpected continue");
		break;
	      case TAG_BREAK:
		Fatal("unexpected break");
		break;
	      case TAG_REDO:
		Fatal("unexpected redo");
		break;
	      case TAG_RETURN:
		result = last_val;
		break;
	      case TAG_RETRY:
		if (!iterator_p()) {
		    Fatal("retry outside of rescue clause");
		}
	      default:
		stack_level--;
		JUMP_TAG(state);
	    }
	}
    }
    POP_FRAME();
    POP_SELF();
    POP_ITER();
    stack_level--;
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

    if (argc == 0) Fail("no method name given");

    vid = argv[0]; argc--; argv++;
    if (TYPE(vid) == T_STRING) {
	mid = rb_intern(RSTRING(vid)->ptr);
    }
    else {
	mid = NUM2INT(vid);
    }
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, 1);
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
f_caller(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE level;
    struct FRAME *frame = the_frame;
    int lev, n;
    char buf[BUFSIZ];

    rb_scan_args(argc, argv, "01", &level);
    if (level == Qnil) lev = 1;
    else lev = NUM2INT(level);
    n = lev;
    if (n < 0) Fail("negative level(%d)", n);
    else {
	while (n-- > 0) {
	    frame = frame->prev;
	    if (!frame) return Qnil;
	}
	if (!frame->file) return Qnil;
	if (frame->prev && frame->prev->last_func) {
	    sprintf(buf, "%s:%d:in `%s'",
		    frame->file, frame->line,
		    rb_id2name(frame->prev->last_func));
	}
	else {
	    sprintf(buf, "%s:%d", frame->file, frame->line);
	}
    }
    return str_new2(buf);
}

void
rb_backtrace()
{
    VALUE c, lev;
    int n = 0;

    lev = INT2FIX(n);
    while (c = f_caller(1, &lev)) {
	printf("%s\n", RSTRING(c)->ptr);
	n++;
	lev = INT2FIX(n);
    }
}

ID
rb_frame_last_func()
{
    return the_frame->last_func;
}

int rb_in_eval = 0;

static VALUE
f_eval(obj, src)
    VALUE obj;
    struct RString *src;
{
    VALUE result = Qnil;
    int state;
    NODE *node;

    Check_Type(src, T_STRING);
    PUSH_TAG();
    rb_in_eval = 1;
    node = eval_tree;

    PUSH_CLASS();
    if (TYPE(the_class) == T_ICLASS) {
	the_class = (struct RClass*)RBASIC(the_class)->class;
    }

    if ((state = EXEC_TAG()) == 0) {
	lex_setsrc("(eval)", src->ptr, src->len);
	eval_tree = 0;
	PUSH_VARS();
	yyparse();
	POP_VARS();
	if (nerrs == 0) {
	    result = Eval();
	}
    }
    eval_tree = node;
    POP_CLASS();
    POP_TAG();
    if (state) JUMP_TAG(state);

    if (nerrs > 0) {
	syntax_error();
    }

    return result;
}

VALUE rb_load_path;

char *dln_find_file();

static char*
find_file(file)
    char *file;
{
    extern VALUE rb_load_path;
    VALUE sep, vpath;
    char *path;

    if (file[0] == '/') return file;

    if (rb_load_path) {
	Check_Type(rb_load_path, T_ARRAY);
	sep = str_new2(":");
	vpath = ary_join(rb_load_path, sep);
	path = RSTRING(vpath)->ptr;
	sep = Qnil;
    }
    else {
	path = Qnil;
    }

    return dln_find_file(file, path);
}

VALUE
f_load(obj, fname)
    VALUE obj;
    struct RString *fname;
{
    int state, in_eval = rb_in_eval;
    char *file, *src;

    Check_Type(fname, T_STRING);
    file = find_file(fname->ptr);
    if (!file) Fail("No such file to load -- %s", fname->ptr);

    PUSH_SELF(TopSelf);
    PUSH_TAG();
    PUSH_CLASS();
    the_class = (struct RClass*)cObject;
    PUSH_SCOPE();
    the_scope->local_vars = top_scope->local_vars;
    the_scope->local_tbl = top_scope->local_tbl;
    rb_in_eval = 1;
    state = EXEC_TAG();
    if (state == 0) {
	rb_load_file(file);
	if (nerrs == 0) {
	    Eval();
	}
    }
    top_scope->flag = the_scope->flag;
    POP_SCOPE();
    POP_CLASS();
    POP_TAG();
    POP_SELF();
    rb_in_eval = in_eval;
    if (nerrs > 0) {
	rb_fail(errstr);
    }
    if (state) JUMP_TAG(state);

    return TRUE;
}

static VALUE rb_features;

static VALUE
rb_provided(feature)
    char *feature;
{
    VALUE *p, *pend;
    char *f;
    int len;

    p = RARRAY(rb_features)->ptr;
    pend = p + RARRAY(rb_features)->len;
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

void
rb_provide(feature)
    char *feature;
{
    if (!rb_provided(feature))
	ary_push(rb_features, str_new2(feature));
}

VALUE
f_require(obj, fname)
    VALUE obj;
    struct RString *fname;
{
    char *ext, *file, *feature, *buf;
    VALUE load;

    Check_Type(fname, T_STRING);
    if (rb_provided(fname->ptr)) return FALSE;

    ext = strrchr(fname->ptr, '.');
    if (ext) {
	if (strcmp(".rb", ext) == 0) {
	    feature = file = fname->ptr;
	    file = find_file(file);
	    if (file) goto rb_load;
	}
	else if (strcmp(".o", ext) == 0) {
	    feature = fname->ptr;
	    if (strcmp(".o", DLEXT) != 0) {
		buf = ALLOCA_N(char, strlen(fname->ptr) + 3);
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
    buf = ALLOCA_N(char, strlen(fname->ptr) + 4);
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
    Fail("No such file to load -- %s", fname->ptr);

  dyna_load:
    load = str_new2(file);
    file = RSTRING(load)->ptr;
    dln_load(file);
    rb_provide(feature);
    return TRUE;

  rb_load:
    f_load(obj, fname);
    rb_provide(feature);
    return TRUE;
}

static void
set_method_visibility(argc, argv, ex)
    int argc;
    VALUE *argv;
    int ex;
{
    VALUE self = Qself;
    int i;
    ID id;

    for (i=0; i<argc; i++) {
	if (FIXNUM_P(argv[i])) {
	    id = FIX2INT(argv[i]);
	}
	else {
	    Check_Type(argv[i], T_STRING);
	    id = rb_intern(RSTRING(argv[i])->ptr);
	}
	rb_export_method(self, id, ex);
    }
}

static VALUE
mod_public(argc, argv)
    int argc;
    VALUE *argv;
{
    set_method_visibility(argc, argv, NOEX_PUBLIC);
    return Qnil;
}

static VALUE
mod_private(argc, argv)
    int argc;
    VALUE *argv;
{
    set_method_visibility(argc, argv, NOEX_PRIVATE);
    return Qnil;
}

static VALUE
mod_modfunc(argc, argv, module)
    int argc;
    VALUE *argv;
    VALUE module;
{
    int i;
    ID id;
    NODE *body, *old;

    set_method_visibility(argc, argv, NOEX_PRIVATE);
    for (i=0; i<argc; i++) {
	if (FIXNUM_P(argv[i])) {
	    id = FIX2INT(argv[i]);
	}
	else {
	    Check_Type(argv[i], T_STRING);
	    id = rb_intern(RSTRING(argv[i])->ptr);
	}
	body = search_method(module, id, 0);
	if (body == 0 || body->nd_body == 0) {
	    Fail("undefined method `%s' for module `%s'",
		 rb_id2name(id), rb_class2name(module));
	}
	rb_add_method(rb_singleton_class(module), id, body->nd_body, NOEX_PUBLIC);
    }
    return Qnil;
}

static VALUE
mod_include(argc, argv, module)
    int argc;
    VALUE *argv;
    struct RClass *module;
{
    int i;

    for (i=0; i<argc; i++) {
	Check_Type(argv[i], T_MODULE);
	rb_include_module(module, argv[i]);
    }
    return (VALUE)module;
}

static VALUE
top_include(argc, argv)
    int argc;
    VALUE *argv;
{
    return mod_include(argc, argv, cObject);
}

static VALUE
obj_extend(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    return mod_include(argc, argv, rb_singleton_class(obj));
}

void
rb_extend_object(obj, module)
    VALUE obj, module;
{
    rb_include_module(rb_singleton_class(obj), module);
}

extern VALUE cKernel;
extern VALUE cModule;

VALUE f_trace_var();
VALUE f_untrace_var();

void
Init_eval()
{
    match = rb_intern("=~");
    each = rb_intern("each");

    aref = rb_intern("[]");
    aset = rb_intern("[]=");

    rb_global_variable(&top_scope);
    rb_global_variable(&eval_tree);
    rb_global_variable(&the_dyna_vars);
    rb_define_private_method(cKernel, "exit", f_exit, -1);
    rb_define_private_method(cKernel, "eval", f_eval, 1);
    rb_define_private_method(cKernel, "iterator?", f_iterator_p, 0);
    rb_define_private_method(cKernel, "method_missing", f_missing, -1);
    rb_define_private_method(cKernel, "loop", f_loop, 0);
    rb_define_private_method(cKernel, "caller", f_caller, -1);

    rb_define_method(cKernel, "send", f_send, -1);

    rb_define_method(cModule, "include", mod_include, -1);
    rb_define_method(cModule, "public", mod_public, -1);
    rb_define_method(cModule, "private", mod_private, -1);
    rb_define_method(cModule, "module_function", mod_modfunc, -1);

    rb_define_method(CLASS_OF(TopSelf), "include", top_include, -1);
    rb_define_method(cObject, "extend", obj_extend, -1);

    rb_define_private_method(cKernel, "trace_var", f_trace_var, -1);
    rb_define_private_method(cKernel, "untrace_var", f_untrace_var, 1);
}

VALUE f_autoload();

void
Init_load()
{
    rb_load_path = ary_new();
    rb_define_readonly_variable("$:", &rb_load_path);
    rb_define_readonly_variable("$LOAD_PATH", &rb_load_path);

    rb_features = ary_new();
    rb_define_readonly_variable("$\"", &rb_features);

    rb_define_private_method(cKernel, "load", f_load, 1);
    rb_define_private_method(cKernel, "require", f_require, 1);
    rb_define_private_method(cKernel, "autoload", f_autoload, 2);
}

static void
scope_dup(scope)
    struct SCOPE *scope;
{
    ID *tbl;
    VALUE *vars;

    if (scope->flag == SCOPE_MALLOC) return;

    if (scope->local_tbl) {
	tbl = scope->local_tbl;
	scope->local_tbl = ALLOC_N(ID, tbl[0]+1);
	MEMCPY(scope->local_tbl, tbl, ID, tbl[0]+1);
	vars = scope->local_vars;
	scope->local_vars = ALLOC_N(VALUE, tbl[0]);
	MEMCPY(scope->local_vars, vars, VALUE, tbl[0]);
	scope->flag = SCOPE_MALLOC;
    }
}

static ID blkdata;

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
proc_s_new(class)
    VALUE class;
{
    VALUE proc;
    struct BLOCK *data;

    if (!iterator_p() && !f_iterator_p()) {
	Fail("tryed to create Procedure-Object out of iterator");
    }

    proc = obj_alloc(class);

    if (!blkdata) blkdata = rb_intern("blk");
    Make_Data_Struct(proc, blkdata, struct BLOCK, blk_mark, blk_free, data);
    MEMCPY(data, the_block, struct BLOCK, 1);

    data->frame.argv = ALLOC_N(VALUE, data->frame.argc);
    MEMCPY(data->frame.argv, the_block->frame.argv, VALUE, data->frame.argc);

    scope_dup(data->scope);

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
    VALUE result = Qnil;
    int state;

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

    Get_Data_Struct(proc, blkdata, struct BLOCK, data);

    /* PUSH BLOCK from data */
    PUSH_BLOCK2(data);
    PUSH_ITER(ITER_CUR);
    PUSH_TAG();

    state = EXEC_TAG();
    if (state == 0) {
	result = rb_yield(args);
    }
    POP_TAG();

    POP_ITER();
    POP_BLOCK();

    switch (state) {
      case 0:
	break;
      case TAG_BREAK:
      case IN_BLOCK|TAG_BREAK:
	Fail("break from block-closure");
	break;
      case TAG_RETURN:
      case IN_BLOCK|TAG_RETURN:
	Fail("return from block-closure");
	break;
      default:
	JUMP_TAG(state);
    }

    return result;
}

void
Init_Proc()
{
    cProc  = rb_define_class("Proc", cObject);

    rb_define_singleton_method(cProc, "new", proc_s_new, 0);

    rb_define_method(cProc, "call", proc_call, -2);
    rb_define_private_method(cKernel, "lambda", f_lambda, 0);
    rb_define_private_method(cKernel, "proc", f_lambda, 0);
}
