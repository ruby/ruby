/************************************************

  eval.c -

  $Author: matz $
  $Date: 1995/01/12 08:54:45 $
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "ident.h"
#include "env.h"
#include "node.h"

#include <stdio.h>
#include <setjmp.h>
#include "st.h"
#include "dln.h"

#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strchr();
#endif

#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#else
char *getenv();
#endif

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

    if (class == Qnil) class = (struct RClass*)C_Object;
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
    int pos, i;
    ID id = *idp;
    struct RClass *class = *classp;
    NODE *body;
    struct RClass *origin;
    struct cache_entry *ent;

    if ((body = search_method(class, id, &origin)) == Qnil) {
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

VALUE
rb_method_boundp(class, id)
    struct RClass *class;
    ID id;
{
    if (rb_get_method_body(&class, &id, 0))
	return TRUE;
    return FALSE;
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

#define PUSH_SELF(s) {			\
    VALUE __saved_self__ = Qself;	\
    Qself = s;				\

#define POP_SELF() Qself = __saved_self__; }

struct ENVIRON *the_env, *top_env;
struct SCOPE   *the_scope, *top_scope;

#define PUSH_ENV() {			\
    struct ENVIRON _env;		\
    _env.prev = the_env;		\
    the_env = &_env;			\

#define POP_ENV()  the_env = _env.prev; }

struct BLOCK {
    NODE *var;
    NODE *body;
    VALUE self;
    struct ENVIRON env;
    struct SCOPE *scope;
    int level;
    VALUE block;
    int iter;
    struct BLOCK *prev;
} *the_block;

#define PUSH_BLOCK(v,b) {		\
    struct BLOCK _block;		\
    _block.level = tag_level;		\
    _block.var=v;			\
    _block.body = b;			\
    _block.self = Qself;		\
    _block.env = *the_env;		\
    _block.scope = the_scope;		\
    _block.block = Qnil;		\
    _block.prev = the_block;		\
    the_block = &_block;		\

#define PUSH_BLOCK2(b) {		\
    b->prev = the_block;		\
    the_block = b;			\

#define POP_BLOCK() the_block = the_block->prev; }

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
    struct ENVIRON *env;
    struct iter *iter;
    struct tag *prev;
} *prot_tag;

#define PUSH_TAG() {			\
    struct tag _tag;			\
    _tag.level= ++tag_level;		\
    _tag.self = Qself;			\
    _tag.env = the_env;			\
    _tag.iter = iter;			\
    _tag.prev = prot_tag;		\
    prot_tag = &_tag;			\

#define EXEC_TAG()    (setjmp(prot_tag->buf))
#define JUMP_TAG(val) {			\
    Qself = prot_tag->self;		\
    the_env = prot_tag->env;		\
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

#define POP_SCOPE() the_scope = _old; }

static VALUE rb_eval();
static VALUE Feval();

static VALUE rb_call();
VALUE rb_apply();
VALUE rb_xstring();
void rb_fail();

static void module_setup();

static VALUE masign();
static void asign();

static VALUE last_val;

extern VALUE rb_stderr;

extern int   sourceline;
extern char *sourcefile;

VALUE
rb_self()
{
    return Qself;
}

static ID last_func;
static void
error_print()
{
    if (errat) {
	fwrite(RSTRING(errat)->ptr, 1, RSTRING(errat)->len, stderr);
	if (last_func) {
	    fprintf(stderr, ":in method `%s': ", rb_id2name(last_func));
	}
	else {
	    fprintf(stderr, ": ");
	}
    }

    if (errstr) {
	fwrite(RSTRING(errstr)->ptr, 1, RSTRING(errstr)->len, stderr);
    }
    else {
	fprintf(stderr, "unhandled failure.\n");
    }
    rb_trap_exit();
    exit(1);
}

void
ruby_init(argc, argv, envp)
    int argc;
    char **argv, **envp;
{
    int state;
    static struct ENVIRON env;
    the_env = top_env = &env;

    init_heap();
    PUSH_SCOPE();
    the_scope->local_vars = Qnil;
    the_scope->local_tbl  = Qnil;
    top_scope = the_scope;

    PUSH_TAG();
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	rb_call_inits();
	the_class = (struct RClass*)C_Object;
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
	PUSH_TAG();
	error_print();
	POP_TAG();
    }
}

VALUE rb_readonly_hook();

static VALUE
Eval()
{
    VALUE result;
    NODE *tree;
    int   state;

    if (!eval_tree) return Qnil;

    tree = eval_tree;
    eval_tree = Qnil;
    sourcefile = tree->file;

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	result = rb_eval(tree);
    }
    POP_TAG();
    if (state) JUMP_TAG(state);

    return result;
}

ruby_run()
{
    int state;

    if (nerrs > 0) exit(nerrs);

    init_stack();
    rb_define_variable("$!", &errstr, Qnil, Qnil, 0);
    errat = Qnil;		/* clear for execution */

    PUSH_TAG();
    PUSH_ITER(ITER_NOT);
    if ((state = EXEC_TAG()) == 0) {
	Eval();
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
	PUSH_TAG();
	error_print();
	POP_TAG();
	break;
      case TAG_EXIT:
	rb_trap_exit();
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
    VALUE result;

    lex_setsrc("(eval)", str, strlen(str));
    eval_tree = Qnil;
    yyparse();
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
rb_trap_eval(cmd)
    VALUE cmd;
{
    int state;
    struct SCOPE *saved_scope;

    PUSH_SELF(TopSelf);
    PUSH_CLASS();
    PUSH_TAG();
    saved_scope = the_scope;
    the_scope = top_scope;

    the_class = (struct RClass*)C_Object;

    if ((state = EXEC_TAG()) == 0) {
	Feval(Qself, cmd);
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
#ifdef SAFE_SIGHANDLE
	trap_immediate = 0;
#endif
	JUMP_TAG(state);
	break;
    }
}

#define SETUP_ARGS do {\
    NODE *n = node->nd_args;\
    if (!n) {\
	argc = 0;\
	argv = Qnil;\
    }\
    else if (/*nd_type(n) == NODE_LIST ||*/ nd_type(n) == NODE_ARRAY) {\
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
    }\
    else {\
        VALUE args = rb_eval(n);\
	if (TYPE(args) != T_ARRAY)\
	    args = rb_to_a(args);\
        argc = RARRAY(args)->len;\
	argv = ALLOCA_N(VALUE, argc);\
	MEMCPY(argv, RARRAY(args)->ptr, VALUE, argc);\
    }\
} while (0)

static VALUE
rb_eval(node)
    register NODE *node;
{
    int   state;
    int   go_out;
    VALUE result;

  again:
    if (node == Qnil) return Qnil;

    sourceline = node->line;

#ifdef SAFE_SIGHANDLE
    {
	extern int trap_pending;

	if (trap_pending) {
	    rb_trap_exec();
	}
    }
#endif

    switch (nd_type(node)) {
      case NODE_BLOCK:
	while (node->nd_next) {
	    rb_eval(node->nd_head);
	    node = node->nd_next;
	}
	node = node->nd_head;
	goto again;

      case NODE_SELF:
	return Qself;

      case NODE_NIL:
	return Qnil;

      case NODE_IF:
	if (rb_eval(node->nd_cond)) {
	    node = node->nd_body;
	}
	else {
	    node = node->nd_else;
	}
	if (node) goto again;
	return Qnil;

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
			    return rb_eval(node->nd_body);
			}
			tag = tag->nd_next;
		    }
		}
		else {
		    return rb_eval(node);
		}
		node = node->nd_next;
	    }
	}
	return Qnil;

      case NODE_WHILE:
	PUSH_TAG();
	switch (state = EXEC_TAG()) {
	  case 0:
	  while_cont:
	    while (rb_eval(node->nd_cond)) {
	      while_redo:
		rb_eval(node->nd_body);
	    }
	    go_out = 0;
	    break;
	  case TAG_REDO:
	    goto while_redo;
	  case TAG_CONTINUE:
	    goto while_cont;
	  default:
	    go_out = 1;
	    break;
	  case TAG_BREAK:
	    go_out = 0;
	    break;
	}
      while_out:
	POP_TAG();
	if (go_out) JUMP_TAG(state);
	return Qnil;

      case NODE_WHILE2:
	PUSH_TAG();
	switch (state = EXEC_TAG()) {
	  case 0:
	  while2_cont:
	    do {
	      while2_redo:
		rb_eval(node->nd_body);
	    } while (rb_eval(node->nd_cond));
	    go_out = 0;
	    break;
	  case TAG_REDO:
	    goto while2_redo;
	  case TAG_CONTINUE:
	    goto while2_cont;
	  default:
	    go_out = 1;
	  case TAG_BREAK:
	    break;
	}
      while2_out:
	POP_TAG();
	if (go_out) JUMP_TAG(state);
	return Qnil;

      case NODE_ITER:
      case NODE_FOR:
	{
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
		    result = rb_call(CLASS_OF(recv),recv,each,0,Qnil,0);
		    POP_ITER();
		}
	    }
	    POP_TAG();
	    POP_BLOCK();
	    switch (state) {
	      case 0:
		break;
	      case IN_BLOCK|TAG_BREAK:
		if (target_level != tag_level) {
		    JUMP_TAG(state);
		}
		result = Qnil;
		break;
	      case IN_BLOCK|TAG_RETRY:
	      case IN_BLOCK|TAG_RETURN:
		if (target_level == tag_level) {
		    state &= ~IN_BLOCK;
		}
		/* fall through */
	      default:
		JUMP_TAG(state);
	    }
	}
	return result;

      case NODE_FAIL:
	{
	    VALUE mesg = rb_eval(node->nd_stts);
	    if (mesg) Check_Type(mesg, T_STRING);
	    rb_fail(mesg);
	    return Qnil;	/* not reached */
	}

      case NODE_YIELD:
	{
	    VALUE val;

	    val = rb_eval(node->nd_stts);
	    result = rb_yield(val);
	}
	return result;

      case NODE_BEGIN:
	PUSH_TAG();
	switch (state = EXEC_TAG()) {
	  case 0:
	  retry_entry:
	    result = rb_eval(node->nd_head);
	    break;

	  case TAG_FAIL:
	    if (node->nd_resq) {
		if (node->nd_resq == (NODE*)1) {
		    state = 0;
		}
		else {
		    PUSH_TAG();
		    state = EXEC_TAG();
		    if (state == 0) result = rb_eval(node->nd_resq);
		    POP_TAG();
		    if (state == TAG_RETRY) {
			goto retry_entry;
		    }
		}
		if (state == 0) {
		    errstr = errat = Qnil;
		    last_func = 0;
		}
	    }
	    break;
	}
	POP_TAG();

	/* ensure clause */
	rb_eval(node->nd_ensr);

	if (state != 0) {
	    JUMP_TAG(state);
	}
	return result;

      case NODE_AND:
	if ((result = rb_eval(node->nd_1st)) == Qnil) return result;
	node = node->nd_2nd;
	goto again;

      case NODE_OR:
	if ((result = rb_eval(node->nd_1st)) != Qnil) return result;
	node = node->nd_2nd;
	goto again;

      case NODE_NOT:
	if (rb_eval(node->nd_body)) return FALSE;
	return TRUE;

      case NODE_DOT3:
	if (node->nd_state == 0) {
	    if (rb_eval(node->nd_beg)) {
		node->nd_state = 1;
		return TRUE;
	    }
	    return FALSE;
	}
	else {
	    if (rb_eval(node->nd_end)) {
		node->nd_state = 0;
	    }
	    return TRUE;
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
	    return rb_call(CLASS_OF(recv),recv,node->nd_mid,argc,argv,0);
	}
	break;

      case NODE_FCALL:
	{
	    int argc; VALUE *argv; /* used in SETUP_ARGS */

	    PUSH_ITER(ITER_NOT);
	    SETUP_ARGS;
	    POP_ITER();
	    return rb_call(CLASS_OF(Qself),Qself,node->nd_mid,argc,argv,1);
	}
	break;

      case NODE_SUPER:
      case NODE_ZSUPER:
	{
	    int i;
	    int argc; VALUE *argv; /* used in SETUP_ARGS */

	    if (nd_type(node) == NODE_ZSUPER) {
		argc = the_env->argc;
		argv = the_env->argv;
	    }
	    else {
		PUSH_ITER(ITER_NOT);
		SETUP_ARGS;
		POP_ITER();
	    }

	    PUSH_ITER(iter->iter?ITER_PRE:ITER_NOT);
	    result = rb_call(the_env->last_class->super, Qself,
			     the_env->last_func, argc, argv, 1);
	    POP_ITER();
	}
	return result;

      case NODE_SCOPE:
	{
	    VALUE result;

	    PUSH_SCOPE();
	    PUSH_TAG();
	    if (node->nd_cnt > 0) {
		the_scope->local_vars = ALLOCA_N(VALUE, node->nd_cnt);
		MEMZERO(the_scope->local_vars, VALUE, node->nd_cnt);
		the_scope->local_tbl = node->nd_tbl;
	    }
	    else {
		the_scope->local_vars = Qnil;
		the_scope->local_tbl  = Qnil;
	    }
	    if ((state = EXEC_TAG()) == 0) {
		result = rb_eval(node->nd_body);
	    }
	    POP_TAG();
	    if (!(the_scope->flags & SCOPE_MALLOCED)) {
		the_scope->local_vars = Qnil;
		the_scope->local_tbl  = Qnil;
	    }
	    POP_SCOPE();
	    if (state != 0) JUMP_TAG(state);

	    return result;
	}

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
	    return val;
	}

      case NODE_OP_ASGN2:
	{
	    ID id = node->nd_aid;
	    VALUE recv, val;

	    recv = rb_funcall(rb_eval(node->nd_recv), id, 0);

	    id &= ~ID_SCOPE_MASK;
	    id |= ID_ATTRSET;

	    val = rb_eval(node->nd_value);
	    rb_funcall(recv, id, 1, val);
	    return val;
	}

      case NODE_MASGN:
	{
	    VALUE val = rb_eval(node->nd_value);
	    return masign(node, val);
	}

      case NODE_LASGN:
	if (the_scope->local_vars == Qnil)
	    Bug("unexpected local variable asignment");
	return the_scope->local_vars[node->nd_cnt] = rb_eval(node->nd_value);

      case NODE_GASGN:
	{
	    VALUE val;

	    val = rb_eval(node->nd_value);
	    rb_gvar_set(node->nd_entry, val);
	    return val;
	}
      case NODE_IASGN:
	{
	    VALUE val;

	    val = rb_eval(node->nd_value);
	    rb_ivar_set(node->nd_vid, val);
	    return val;
	}
      case NODE_CASGN:
	{
	    VALUE val;

	    val = rb_eval(node->nd_value);
	    rb_const_set(the_class, node->nd_vid, val);
	    return val;
	}
	break;

      case NODE_LVAR:
	if (the_scope->local_vars == Qnil)
	    Bug("unexpected local variable");
	return the_scope->local_vars[node->nd_cnt];

      case NODE_LVAR2:
	if (the_scope->flags & SCOPE_MALLOCED) {
	    ID id = node->nd_vid, *tbl = the_scope->local_tbl;
	    int i, len = tbl[0];

	    tbl++;
	    for (i=0; i<len; i++) {
		if (id == tbl[i]) break;
	    }
	    if (i<len) {
		return the_scope->local_vars[i];
	    }
	}
	Warning("local var %s not initialized", rb_id2name(node->nd_vid));
	return Qnil;

      case NODE_GVAR:
	return rb_gvar_get(node->nd_entry);
      case NODE_IVAR:
	return rb_ivar_get(node->nd_vid);

      case NODE_CVAR:
	{
	    VALUE val;

	    val = rb_const_get(node->nd_rval->nd_clss, node->nd_vid);
	    nd_set_type(node, NODE_CONST);
	    node->nd_cval = val;
	    return val;
	}

      case NODE_CONST:
	return node->nd_cval;

      case NODE_NTH_REF:
	return re_nth_match(node->nd_nth);

      case NODE_HASH:
	{
	    NODE *list;
	    VALUE hash = hash_new();
	    VALUE key, val;

	    list = node->nd_head;
	    while (list) {
		key = rb_eval(list->nd_head);
		list = list->nd_next;
		if (list == Qnil)
		    Bug("odd number list for Hash");
		val = rb_eval(list->nd_head);
		list = list->nd_next;
		Fhash_aset(hash, key, val);
	    }
	    return hash;
	}
	break;

      case NODE_ZARRAY:		/* zero length list */
	return ary_new();

      case NODE_ARRAY:
	{
	    VALUE ary;
	    int i;
	    NODE *list;

	    i = node->nd_alen;
	    ary = ary_new2(i);
	    for (i=0;node;node=node->nd_next) {
		RARRAY(ary)->ptr[i++] = rb_eval(node->nd_head);
		RARRAY(ary)->len = i;
	    }

	    return ary;
	}
	break;

      case NODE_STR:
	return str_new3(node->nd_lit);

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
		VALUE re = regexp_new(RSTRING(str)->ptr, RSTRING(str)->len,
				      node->nd_cflag);
		return re;
	    }
	    if (nd_type(node) == NODE_XSTR2) {
		return rb_xstring(str);
	    }
	    return str;
	}

      case NODE_XSTR:
	return rb_xstring(node->nd_lit);

      case NODE_LIT:
	return node->nd_lit;

      case NODE_ATTRSET:
	if (the_env->argc != 1)
	    Fail("Wrong # of arguments(%d for 1)", the_env->argc);
	return rb_ivar_set(node->nd_vid, the_env->argv[0]);

      case NODE_DEFN:
	if (node->nd_defn) {
	    NODE *body;
	    VALUE origin;
	    int noex;

	    body = search_method(the_class, node->nd_mid, &origin);
	    if (verbose && origin != (VALUE)the_class
		&& body->nd_noex != node->nd_noex) {
		Warning("change method %s's scope", rb_id2name(node->nd_mid));
	    }

	    if (body) noex = body->nd_noex;
	    else      noex = node->nd_noex; /* default(1 for toplevel) */

	    rb_add_method(the_class, node->nd_mid, node->nd_defn, noex);
	}
	return Qnil;

      case NODE_DEFS:
	if (node->nd_defn) {
	    VALUE recv = rb_eval(node->nd_recv);

	    if (recv == Qnil) {
		Fail("Can't define method \"%s\" for nil",
		     rb_id2name(node->nd_mid));
	    }
	    rb_funcall(recv, rb_intern("single_method_added"),
		       1, INT2FIX(node->nd_mid));
	    rb_add_method(rb_single_class(recv),node->nd_mid,node->nd_defn,
			  NOEX_PUBLIC);
	}
	return Qnil;

      case NODE_UNDEF:
	rb_add_method(the_class, node->nd_mid, Qnil, NOEX_PUBLIC);
	return Qnil;

      case NODE_ALIAS:
	rb_alias(the_class, node->nd_new, node->nd_old);
	return Qnil;

      case NODE_CLASS:
	{
	    VALUE super, class;
	    struct RClass *tmp;

	    if (node->nd_super) {
		super = rb_const_get(the_class, node->nd_super);
		if (super == Qnil) {
		    Fail("undefined superclass %s",
			 rb_id2name(node->nd_super));
		}
	    }
	    else {
		super = Qnil;
	    }

	    if (rb_const_bound(the_class, node->nd_cname)) {
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
			Fail("%s's superclass differs",
			     rb_id2name(node->nd_cname));
		}
		Warning("extending class %s", rb_id2name(node->nd_cname));
	    }
	    else {
		if (super == Qnil) super = C_Object;
		class = rb_define_class_id(node->nd_cname, super);
		rb_const_set(the_class, node->nd_cname, class);
		rb_set_class_path(class,the_class,rb_id2name(node->nd_cname));
	    }

	    module_setup(class, node->nd_body);
	    return class;
	}

      case NODE_MODULE:
	{
	    VALUE module;

	    if (rb_const_bound(the_class, node->nd_cname)) {
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
	    return module;
	}

      default:
	Bug("unknown node type %d", nd_type(node));
    }
    return Qnil;		/* not reached */
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
    PUSH_TAG();

    if (node->nd_cnt > 0) {
	the_scope->local_vars = ALLOCA_N(VALUE, node->nd_cnt);
	MEMZERO(the_scope->local_vars, VALUE, node->nd_cnt);
	the_scope->local_tbl = node->nd_tbl;
    }
    else {
	the_scope->local_vars = Qnil;
	the_scope->local_tbl  = Qnil;
    }

    if ((state = EXEC_TAG()) == 0) {
	rb_eval(node->nd_body);
    }

    POP_TAG();
    if (!(the_scope->flags & SCOPE_MALLOCED)) {
	the_scope->local_vars = Qnil;
	the_scope->local_tbl  = Qnil;
    }
    if (state != 0) JUMP_TAG(state);
    POP_SCOPE();
    POP_SELF();
    POP_CLASS();
    if (state) JUMP_TAG(state);
}

VALUE
obj_responds_to(obj, msg)
    VALUE obj;
    struct RString *msg;
{
    ID id;

    if (FIXNUM_P(msg)) {
	id = FIX2INT(msg);
    }
    else {
	Check_Type(msg, T_STRING);
	id = rb_intern(msg->ptr);
    }

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
    exit(FIX2UINT(last_val));
}

static VALUE
Fexit(argc, argv, obj)
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

    if (errat == Qnil || sourcefile) {
	if (the_env->last_func) {
	    last_func = the_env->last_func;
	}
	sprintf(buf, "%s:%d", sourcefile, sourceline);
	errat = str_new2(buf);
    }

    if (mesg) {
	if (RSTRING(mesg)->ptr[RSTRING(mesg)->len - 1] == '\n') {
	    errstr = mesg;
	}
	else {
	    errstr = str_clone(mesg);
	    str_cat(errstr, "\n", 1);
	}
    }

    if (prot_tag->level == 0) error_print();
    JUMP_TAG(TAG_FAIL);
}

VALUE
iterator_p()
{
    if (iter->iter) return TRUE;
    return FALSE;
}

static VALUE
Fiterator_p()
{
    if (iter->prev && iter->prev->iter) return TRUE;
    return FALSE;
}

VALUE
rb_yield(val)
    VALUE val;
{
    struct BLOCK *block;
    NODE *node;
    int   state;
    VALUE result;
    struct ENVIRON *old_env;
    struct SCOPE   *old_scope;

    if (!iterator_p()) {
	Fail("yield called out of iterator");
    }

    block = the_block;
    old_env = the_env;
    the_env = &(block->env);
    old_scope = the_scope;
    the_scope = block->scope;
    the_block = block->prev;
    if (block->var) {
	if (nd_type(block->var) == NODE_MASGN)
	    masign(block->var, val);
	else
	    asign(block->var, val);
    }

    PUSH_ITER(block->iter);
    PUSH_SELF(block->self);
    PUSH_TAG();
    node = block->body;
    switch (state = EXEC_TAG()) {
      redo:
      case 0:
	if (nd_type(node) == NODE_CFUNC) {
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
      case TAG_RETRY:
      case TAG_BREAK:
      case TAG_RETURN:
	target_level = block->level;
	state = IN_BLOCK|state;
	break;
    }
    POP_TAG();
    POP_SELF();
    POP_ITER();
    the_block = block;
    the_env = old_env;
    the_scope = old_scope;
    if (state) JUMP_TAG(state);

    return result;
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
	rb_ivar_set(lhs->nd_vid, val);
	break;

      case NODE_LASGN:
	if (the_scope->local_vars == Qnil)
	    Bug("unexpected iterator variable asignment");
	the_scope->local_vars[lhs->nd_cnt] = val;
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
    char *data1, *data2;
{
    int   state;
    VALUE retval;
    NODE *node = NEW_CFUNC(bl_proc, data2);
    struct BLOCK block;

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
      case IN_BLOCK|TAG_BREAK:
	if (target_level != tag_level) {
	    JUMP_TAG(state);
	}
	retval = Qnil;
	break;
      case IN_BLOCK|TAG_RETRY:
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
rb_resque(b_proc, data1, r_proc, data2)
    VALUE (*b_proc)(), (*r_proc)();
    char *data1, *data2;
{
    int   state;
    int   go_out;
    VALUE result;

    PUSH_TAG();
    switch (state = EXEC_TAG()) {
      case 0:
      retry_entry:
	result = (*b_proc)(data1);
	go_out = 0;
	break;

      case TAG_FAIL:
	if (r_proc) {
	    PUSH_TAG();
	    state = EXEC_TAG();
	    if (state == 0) {
		result = (*r_proc)(data2);
	    }
	    POP_TAG();
	    switch (state) {
	      case TAG_RETRY:
		goto retry_entry;
	      case 0:
		go_out = 0;
		break;
	      default:
		go_out = 1;
		break;
	    }
	}
	if (state == 0) {
	    errstr = errat = Qnil;
	}
	break;

      default:
	go_out = 1;
	break;
    }
    POP_TAG();
    if (go_out) JUMP_TAG(state);

    return result;
}

VALUE
rb_ensure(b_proc, data1, e_proc, data2)
    VALUE (*b_proc)(), (*e_proc)();
    char *data1, *data2;
{
    int   state;
    VALUE result;

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
Fmissing(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE desc;
    ID    id;
    char *format;
    struct ENVIRON *env;

    id = FIX2INT(argv[0]);
    argc--; argv++;

    desc = obj_as_string(obj);
    if (RSTRING(desc)->len > 160) {
	desc = Fkrn_to_s(obj);
    }
    if (last_noex)
	format = "method `%s' not available for \"%s\"(%s)";
    else
	format = "undefined method `%s' for \"%s\"(%s)";

    /* fake environment */
    PUSH_ENV();
    env = the_env->prev;
    MEMCPY(the_env, env->prev, struct ENVIRON, 1);
    the_env->prev = env;

    Fail(format,
	 rb_id2name(id),
	 RSTRING(desc)->ptr,
	 rb_class2name(CLASS_OF(obj)));
    POP_ENV();
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

    argc;
    nargv = ALLOCA_N(VALUE, argc+1);
    nargv[0] = INT2FIX(id);
    MEMCPY(nargv+1, argv, VALUE, argc);

    last_noex = noex;

    return rb_funcall2(obj, rb_intern("method_missing"), argc+1, nargv);
}

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
    VALUE  result;
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

	if ((body = rb_get_method_body(&class, &id, &noex)) == Qnil) {
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

    PUSH_ITER(itr);
    PUSH_SELF(recv);
    PUSH_ENV();
    the_env->last_func = mid;
    the_env->last_class = class;
    the_env->argc = argc;
    the_env->argv = argv;

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
	return rb_eval(body);

      default:
	{
	    int    state;
	    VALUE *local_vars;

	    sourcefile = body->file;
	    PUSH_SCOPE();

	    if (body->nd_cnt > 0) {
		local_vars = ALLOCA_N(VALUE, body->nd_cnt);
		MEMZERO(local_vars, VALUE, body->nd_cnt);
		the_scope->local_tbl = body->nd_tbl;
		the_scope->local_vars = local_vars;
	    }
	    else {
		local_vars = the_scope->local_vars = Qnil;
		the_scope->local_tbl  = Qnil;
	    }
	    body = body->nd_body;

	    if (nd_type(body) == NODE_BLOCK) {
		NODE *node = body->nd_head;
		NODE *local;
		int i;

		if (nd_type(node) != NODE_ARGS) {
		    Bug("no argument-node");
		}

		body = body->nd_next;
		i = node->nd_cnt;
		if (i > argc || (node->nd_rest == -1 && i < argc))
		    Fail("Wrong # of arguments(%d for %d)", argc, i);

		if (local_vars) {
		    if (i > 0) {
			MEMCPY(local_vars, argv, VALUE, i);
		    }
		    if (node->nd_rest >= 0) {
			if (argc == 0)
			    local_vars[node->nd_rest] = ary_new();
			else
			    local_vars[node->nd_rest] = ary_new4(argc-i, argv+i);
		    }
		}
	    }
	    PUSH_TAG();
	    state = EXEC_TAG();
	    if (state == 0) {
		result = rb_eval(body);
	    }
	    POP_TAG();
	    if (!(the_scope->flags & SCOPE_MALLOCED)) {
		the_scope->local_vars = Qnil;
		the_scope->local_tbl  = Qnil;
	    }
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
	      case TAG_RETRY:
		Fatal("retry outside of resque clause");
		break;
	      case TAG_RETURN:
		result = last_val;
		break;
	      default:
		JUMP_TAG(state);
	    }
	}
    }
    POP_ENV();
    POP_SELF();
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
Fapply(argc, argv, recv)
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
	argv = Qnil;
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

int rb_in_eval = 0;

static VALUE
Feval(obj, src)
    VALUE obj;
    struct RString *src;
{
    VALUE result;
    int state;
    NODE *node;
    char *oldsrc = sourcefile;

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
	eval_tree = Qnil;
	yyparse();
	sourcefile = oldsrc;
	if (nerrs == 0) {
	    result = Eval(0);
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
Fload(obj, fname)
    VALUE obj;
    struct RString *fname;
{
    int state, in_eval = rb_in_eval;
    NODE *node;
    char *file;

    Check_Type(fname, T_STRING);
    file = find_file(fname->ptr);
    if (!file) Fail("No such file to load -- %s", file);

    PUSH_SELF(TopSelf);
    PUSH_TAG();
    PUSH_CLASS();
    the_class = (struct RClass*)C_Object;
    the_scope->local_vars = top_scope->local_vars;
    the_scope->local_tbl = top_scope->local_tbl;
    rb_in_eval = 1;
    state = EXEC_TAG();
    if (state == 0) {
	rb_load_file(file);
	if (nerrs == 0) {
	    Eval(0);
	}
    }
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

static VALUE rb_loadfiles;

Frequire(obj, fname)
    VALUE obj;
    struct RString *fname;
{
    char *file;
    VALUE *p, *pend;

    Check_Type(fname, T_STRING);
    file = find_file(fname->ptr);
    if (!file) {
	char *buf = ALLOCA_N(char, strlen(fname->ptr) + 4);
	sprintf(buf, "%s.rb", fname->ptr);
	file = find_file(buf);
#ifdef USE_DL
	if (!file) {
	    sprintf(buf, "%s%s", fname->ptr, DLEXT);
	    file = find_file(buf);
	}
#endif
	if (!file) Fail("No such file to load -- %s", file);
    }

    p = RARRAY(rb_loadfiles)->ptr;
    pend = p + RARRAY(rb_loadfiles)->len;
    while (p < pend) {
	Check_Type(*p, T_STRING);
	if (strcmp(RSTRING(*p)->ptr, file) == 0) return FALSE;
    }
    fname = (struct RString*)str_new2(file);
    ary_push(rb_loadfiles, fname);
    file = fname->ptr;

#ifdef USE_DL
    {
	int len = strlen(file), extsiz = sizeof(DLEXT);

	if (len > extsiz) {
	    int i;
	    for (i=1;i<extsiz;i++) {
		if (file[len-i] != DLEXT[extsiz-i-1]) break;
	    }
	    if (i==extsiz) {
		static int rb_dln_init = 0;
		extern char *rb_dln_argv0;

		if (rb_dln_init == 0 && dln_init(rb_dln_argv0) == -1) {
		    Fail("%s: %s", rb_dln_argv0, dln_strerror());
		}

		if (dln_load(file) == -1)
		    Fail(dln_strerror());

		return TRUE;
	    }
	}
    }
#endif
    return Fload(obj, fname);
}

#ifndef RUBY_LIB
#define RUBY_LIB "/usr/local/lib/ruby:."
#endif

#define RUBY_LIB_SEP ':'

static void
addpath(path)
    char *path;
{
    char *p, *s;

    if (path == Qnil) return;

    p = s = path;
    while (*p) {
	while (*p == RUBY_LIB_SEP) p++;
	if (s = strchr(p, RUBY_LIB_SEP)) {
	    ary_push(rb_load_path, str_new(p, (int)(s-p)));
	    p = s + 1;
	}
	else {
	    ary_push(rb_load_path, str_new2(p));
	    break;
	}
    }
}

static VALUE
Fmod_include(argc, argv, module)
    int argc;
    VALUE *argv;
    struct RClass *module;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_include_module(module, argv[i]);
    }
    return (VALUE)module;
}

static VALUE
Ftop_include(argc, argv)
{
    return Fmod_include(argc, argv, C_Object);
}

static VALUE
Fobj_extend(argc, argv, obj)
{
    return Fmod_include(argc, argv, rb_single_class(obj));
}

void
rb_extend_object(obj, module)
    VALUE obj, module;
{
    rb_include_module(rb_single_class(obj), module);
}

extern VALUE C_Kernel;
extern VALUE C_Module;

Init_eval()
{
    match = rb_intern("=~");
    each = rb_intern("each");

    aref = rb_intern("[]");
    aset = rb_intern("[]=");

    rb_global_variable(&top_scope);
    rb_global_variable(&eval_tree);
    rb_define_private_method(C_Kernel, "exit", Fexit, -1);
    rb_define_private_method(C_Kernel, "eval", Feval, 1);
    rb_define_private_method(C_Kernel, "iterator_p", Fiterator_p, 0);
    rb_define_method(C_Kernel, "apply", Fapply, -1);
    rb_define_method(C_Kernel, "method_missing", Fmissing, -1);

    rb_define_method(C_Module, "include", Fmod_include, -1);
    rb_define_method(CLASS_OF(TopSelf), "include", Ftop_include, -1);
    rb_define_method(C_Object, "extend", Fobj_extend, -1);
}

Init_load()
{
    char *path;

    rb_load_path = ary_new();
    rb_define_variable("$:", &rb_load_path, Qnil, rb_readonly_hook, 0);
    rb_define_variable("$LOAD_PATH", &rb_load_path, Qnil, rb_readonly_hook, 0);

    rb_loadfiles = ary_new();
    rb_define_variable("$\"", &rb_load_path, Qnil, rb_readonly_hook, 0);
    rb_define_variable("$LOAD_FILES", &rb_load_path, Qnil, rb_readonly_hook,0);
    addpath(getenv("RUBYLIB"));
    addpath(RUBY_LIB);

    rb_define_private_method(C_Kernel, "load", Fload, 1);
    rb_define_private_method(C_Kernel, "require", Frequire, 1);
}

void
scope_dup(scope)
    struct SCOPE *scope;
{
    ID *tbl;
    VALUE *vars;

    if (scope->flags & SCOPE_MALLOCED) return;
    if (!scope->local_tbl) return;

    tbl = scope->local_tbl;
    scope->local_tbl = ALLOC_N(ID, tbl[0]+1);
    MEMCPY(scope->local_tbl, tbl, ID, tbl[0]+1);
    vars = scope->local_vars;
    scope->local_vars = ALLOC_N(VALUE, tbl[0]);
    MEMCPY(scope->local_vars, vars, VALUE, tbl[0]);
    scope->flags |= SCOPE_MALLOCED;
}

VALUE C_Block;
static ID blkdata;

static void
blk_mark(data)
    struct BLOCK *data;
{
    gc_mark_env(&data->env);
    gc_mark(data->scope);
    gc_mark(data->var);
    gc_mark(data->body);
    gc_mark(data->self);
}

static void
blk_free(data)
    struct BLOCK *data;
{
    free(data->env.argv);
}

static VALUE
Sblk_new(class)
{
    VALUE blk;
    struct BLOCK *data;
    struct SCOPE *scope;

    if (!iterator_p() && !Fiterator_p()) {
	Fail("tryed to create Block out of iterator");
    }

    if (the_block->block) return the_block->block;
    blk = obj_alloc(class);

    if (!blkdata) blkdata = rb_intern("blk");
    Make_Data_Struct(blk, blkdata, struct BLOCK, Qnil, blk_free, data);
    MEMCPY(data, the_block, struct BLOCK, 1);

    data->env.argv = ALLOC_N(VALUE, data->env.argc);
    MEMCPY(data->env.argv, the_block->env.argv, VALUE, data->env.argc);

    scope_dup(data->scope);

    the_block->block = blk;
    return blk;
}

VALUE
block_new()
{
    return Sblk_new(C_Block);
}

static VALUE
Fblk_call(blk, args)
    VALUE blk, args;
{
    struct BLOCK *data;
    VALUE result;
    int state;

    switch (RARRAY(args)->len) {
      case 0:
	args = Qnil;
	break;
      case 1:
	args = RARRAY(args)->ptr[0];
	break;
    }

    Get_Data_Struct(blk, blkdata, struct BLOCK, data);

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
      case TAG_RETRY:
      case IN_BLOCK|TAG_RETRY:
	Fail("retry from block-closure");
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

Init_Block()
{
    C_Block  = rb_define_class("Block", C_Object);

    rb_define_single_method(C_Block, "new", Sblk_new, 0);

    rb_define_method(C_Block, "call", Fblk_call, -2);
}
