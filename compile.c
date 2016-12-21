/**********************************************************************

  compile.c - ruby node tree -> VM instruction sequence

  $Author$
  created at: 04/01/01 03:42:15 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "internal.h"
#include "ruby/re.h"
#include "encindex.h"
#include <math.h>

#define USE_INSN_STACK_INCREASE 1
#include "vm_core.h"
#include "iseq.h"
#include "insns.inc"
#include "insns_info.inc"
#include "id_table.h"
#include "gc.h"

#ifdef HAVE_DLADDR
# include <dlfcn.h>
#endif

#undef RUBY_UNTYPED_DATA_WARNING
#define RUBY_UNTYPED_DATA_WARNING 0

#define FIXNUM_INC(n, i) ((n)+(INT2FIX(i)&~FIXNUM_FLAG))
#define FIXNUM_OR(n, i) ((n)|INT2FIX(i))

typedef struct iseq_link_element {
    enum {
	ISEQ_ELEMENT_NONE,
	ISEQ_ELEMENT_LABEL,
	ISEQ_ELEMENT_INSN,
	ISEQ_ELEMENT_ADJUST
    } type;
    struct iseq_link_element *next;
    struct iseq_link_element *prev;
} LINK_ELEMENT;

typedef struct iseq_link_anchor {
    LINK_ELEMENT anchor;
    LINK_ELEMENT *last;
} LINK_ANCHOR;

typedef enum {
    LABEL_RESCUE_NONE,
    LABEL_RESCUE_BEG,
    LABEL_RESCUE_END,
    LABEL_RESCUE_TYPE_MAX
} LABEL_RESCUE_TYPE;

typedef struct iseq_label_data {
    LINK_ELEMENT link;
    int label_no;
    int position;
    int sc_state;
    int sp;
    int refcnt;
    unsigned int set: 1;
    unsigned int rescued: 2;
} LABEL;

typedef struct iseq_insn_data {
    LINK_ELEMENT link;
    enum ruby_vminsn_type insn_id;
    unsigned int line_no;
    int operand_size;
    int sc_state;
    VALUE *operands;
} INSN;

typedef struct iseq_adjust_data {
    LINK_ELEMENT link;
    LABEL *label;
    int line_no;
} ADJUST;

struct ensure_range {
    LABEL *begin;
    LABEL *end;
    struct ensure_range *next;
};

struct iseq_compile_data_ensure_node_stack {
    NODE *ensure_node;
    struct iseq_compile_data_ensure_node_stack *prev;
    struct ensure_range *erange;
};

/**
 * debug function(macro) interface depend on CPDEBUG
 * if it is less than 0, runtime option is in effect.
 *
 * debug level:
 *  0: no debug output
 *  1: show node type
 *  2: show node important parameters
 *  ...
 *  5: show other parameters
 * 10: show every AST array
 */

#ifndef CPDEBUG
#define CPDEBUG 0
#endif

#if CPDEBUG >= 0
#define compile_debug CPDEBUG
#else
#define compile_debug ISEQ_COMPILE_DATA(iseq)->option->debug_level
#endif

#if CPDEBUG

#define compile_debug_print_indent(level) \
    ruby_debug_print_indent((level), compile_debug, gl_node_level * 2)

#define debugp(header, value) (void) \
  (compile_debug_print_indent(1) && \
   ruby_debug_print_value(1, compile_debug, (header), (value)))

#define debugi(header, id)  (void) \
  (compile_debug_print_indent(1) && \
   ruby_debug_print_id(1, compile_debug, (header), (id)))

#define debugp_param(header, value)  (void) \
  (compile_debug_print_indent(1) && \
   ruby_debug_print_value(1, compile_debug, (header), (value)))

#define debugp_verbose(header, value)  (void) \
  (compile_debug_print_indent(2) && \
   ruby_debug_print_value(2, compile_debug, (header), (value)))

#define debugp_verbose_node(header, value)  (void) \
  (compile_debug_print_indent(10) && \
   ruby_debug_print_value(10, compile_debug, (header), (value)))

#define debug_node_start(node)  ((void) \
  (compile_debug_print_indent(1) && \
   (ruby_debug_print_node(1, CPDEBUG, "", (NODE *)(node)), gl_node_level)), \
   gl_node_level++)

#define debug_node_end()  gl_node_level --

#else

static inline ID
r_id(ID id)
{
    return id;
}

static inline VALUE
r_value(VALUE value)
{
    return value;
}

#define debugi(header, id)                 r_id(id)
#define debugp(header, value)              r_value(value)
#define debugp_verbose(header, value)      r_value(value)
#define debugp_verbose_node(header, value) r_value(value)
#define debugp_param(header, value)        r_value(value)
#define debug_node_start(node)             ((void)0)
#define debug_node_end()                   ((void)0)
#endif

#if CPDEBUG > 1 || CPDEBUG < 0
#define printf ruby_debug_printf
#define debugs if (compile_debug_print_indent(1)) ruby_debug_printf
#define debug_compile(msg, v) ((void)(compile_debug_print_indent(1) && fputs((msg), stderr)), (v))
#else
#define debugs                             if(0)printf
#define debug_compile(msg, v) (v)
#endif

#define LVAR_ERRINFO (1)

/* create new label */
#define NEW_LABEL(l) new_label_body(iseq, (l))

#define iseq_path(iseq) ((iseq)->body->location.path)
#define iseq_absolute_path(iseq) ((iseq)->body->location.absolute_path)

#define NEW_ISEQ(node, name, type, line_no) \
  new_child_iseq(iseq, (node), rb_fstring(name), 0, (type), (line_no))

#define NEW_CHILD_ISEQ(node, name, type, line_no) \
  new_child_iseq(iseq, (node), rb_fstring(name), iseq, (type), (line_no))

/* add instructions */
#define ADD_SEQ(seq1, seq2) \
  APPEND_LIST((seq1), (seq2))

/* add an instruction */
#define ADD_INSN(seq, line, insn) \
  ADD_ELEM((seq), (LINK_ELEMENT *) new_insn_body(iseq, (line), BIN(insn), 0))

/* insert an instruction before prev */
#define INSERT_BEFORE_INSN(prev, line, insn) \
  INSERT_ELEM_PREV(&(prev)->link, (LINK_ELEMENT *) new_insn_body(iseq, (line), BIN(insn), 0))

/* add an instruction with some operands (1, 2, 3, 5) */
#define ADD_INSN1(seq, line, insn, op1) \
  ADD_ELEM((seq), (LINK_ELEMENT *) \
           new_insn_body(iseq, (line), BIN(insn), 1, (VALUE)(op1)))

/* insert an instruction with some operands (1, 2, 3, 5) before prev */
#define INSERT_BEFORE_INSN1(prev, line, insn, op1) \
  INSERT_ELEM_PREV(&(prev)->link, (LINK_ELEMENT *) \
           new_insn_body(iseq, (line), BIN(insn), 1, (VALUE)(op1)))

#define LABEL_REF(label) ((label)->refcnt++)

/* add an instruction with label operand (alias of ADD_INSN1) */
#define ADD_INSNL(seq, line, insn, label) (ADD_INSN1(seq, line, insn, label), LABEL_REF(label))

#define ADD_INSN2(seq, line, insn, op1, op2) \
  ADD_ELEM((seq), (LINK_ELEMENT *) \
           new_insn_body(iseq, (line), BIN(insn), 2, (VALUE)(op1), (VALUE)(op2)))

#define ADD_INSN3(seq, line, insn, op1, op2, op3) \
  ADD_ELEM((seq), (LINK_ELEMENT *) \
           new_insn_body(iseq, (line), BIN(insn), 3, (VALUE)(op1), (VALUE)(op2), (VALUE)(op3)))

/* Specific Insn factory */
#define ADD_SEND(seq, line, id, argc) \
  ADD_SEND_R((seq), (line), (id), (argc), NULL, (VALUE)INT2FIX(0), NULL)

#define ADD_SEND_WITH_FLAG(seq, line, id, argc, flag) \
  ADD_SEND_R((seq), (line), (id), (argc), NULL, (VALUE)(flag), NULL)

#define ADD_SEND_WITH_BLOCK(seq, line, id, argc, block) \
  ADD_SEND_R((seq), (line), (id), (argc), (block), (VALUE)INT2FIX(0), NULL)

#define ADD_CALL_RECEIVER(seq, line) \
  ADD_INSN((seq), (line), putself)

#define ADD_CALL(seq, line, id, argc) \
  ADD_SEND_R((seq), (line), (id), (argc), NULL, (VALUE)INT2FIX(VM_CALL_FCALL), NULL)

#define ADD_CALL_WITH_BLOCK(seq, line, id, argc, block) \
  ADD_SEND_R((seq), (line), (id), (argc), (block), (VALUE)INT2FIX(VM_CALL_FCALL), NULL)

#define ADD_SEND_R(seq, line, id, argc, block, flag, keywords) \
  ADD_ELEM((seq), (LINK_ELEMENT *) new_insn_send(iseq, (line), (id), (VALUE)(argc), (block), (VALUE)(flag), (keywords)))

#define ADD_TRACE(seq, line, event) \
  do { \
      if ((event) == RUBY_EVENT_LINE && ISEQ_COVERAGE(iseq) && \
	  (line) > 0 && \
	  (line) != ISEQ_COMPILE_DATA(iseq)->last_coverable_line) { \
	  RARRAY_ASET(ISEQ_COVERAGE(iseq), (line) - 1, INT2FIX(0)); \
	  ISEQ_COMPILE_DATA(iseq)->last_coverable_line = (line); \
	  ADD_INSN1((seq), (line), trace, INT2FIX(RUBY_EVENT_COVERAGE)); \
      } \
      if (ISEQ_COMPILE_DATA(iseq)->option->trace_instruction) { \
	  ADD_INSN1((seq), (line), trace, INT2FIX(event)); \
      } \
  } while (0)

#define ADD_GETLOCAL(seq, line, idx, level) \
  do { \
      ADD_INSN2((seq), (line), getlocal, INT2FIX((idx) + VM_ENV_DATA_SIZE - 1), INT2FIX(level)); \
  } while (0)

#define ADD_SETLOCAL(seq, line, idx, level) \
  do { \
      ADD_INSN2((seq), (line), setlocal, INT2FIX((idx) + VM_ENV_DATA_SIZE - 1), INT2FIX(level)); \
  } while (0)

/* add label */
#define ADD_LABEL(seq, label) \
  ADD_ELEM((seq), (LINK_ELEMENT *) (label))

#define APPEND_LABEL(seq, before, label) \
  APPEND_ELEM((seq), (before), (LINK_ELEMENT *) (label))

#define ADD_ADJUST(seq, line, label) \
  ADD_ELEM((seq), (LINK_ELEMENT *) new_adjust_body(iseq, (label), (line)))

#define ADD_ADJUST_RESTORE(seq, label) \
  ADD_ELEM((seq), (LINK_ELEMENT *) new_adjust_body(iseq, (label), -1))

#define ADD_CATCH_ENTRY(type, ls, le, iseqv, lc) do {				\
    VALUE _e = rb_ary_new3(5, (type),						\
			   (VALUE)(ls) | 1, (VALUE)(le) | 1,			\
			   (VALUE)(iseqv), (VALUE)(lc) | 1);			\
    if (ls) LABEL_REF(ls);							\
    if (le) LABEL_REF(le);							\
    if (lc) LABEL_REF(lc);							\
    rb_ary_push(ISEQ_COMPILE_DATA(iseq)->catch_table_ary, freeze_hide_obj(_e));	\
} while (0)

/* compile node */
#define COMPILE(anchor, desc, node) \
  (debug_compile("== " desc "\n", \
                 iseq_compile_each(iseq, (anchor), (node), 0)))

/* compile node, this node's value will be popped */
#define COMPILE_POPPED(anchor, desc, node)    \
  (debug_compile("== " desc "\n", \
                 iseq_compile_each(iseq, (anchor), (node), 1)))

/* compile node, which is popped when 'popped' is true */
#define COMPILE_(anchor, desc, node, popped)  \
  (debug_compile("== " desc "\n", \
                 iseq_compile_each(iseq, (anchor), (node), (popped))))

#define COMPILE_RECV(anchor, desc, node) \
    (private_recv_p(node) ? \
     (ADD_INSN(anchor, nd_line(node), putself), VM_CALL_FCALL) : \
     (COMPILE(anchor, desc, node->nd_recv), 0))

#define OPERAND_AT(insn, idx) \
  (((INSN*)(insn))->operands[(idx)])

#define INSN_OF(insn) \
  (((INSN*)(insn))->insn_id)

#define IS_INSN(link) ((link)->type == ISEQ_ELEMENT_INSN)
#define IS_LABEL(link) ((link)->type == ISEQ_ELEMENT_LABEL)
#define IS_ADJUST(link) ((link)->type == ISEQ_ELEMENT_ADJUST)
#define IS_INSN_ID(iobj, insn) (INSN_OF(iobj) == BIN(insn))

/* error */
typedef void (*compile_error_func)(rb_iseq_t *, int, const char *, ...);

static void
append_compile_error(rb_iseq_t *iseq, int line, const char *fmt, ...)
{
    VALUE err_info = ISEQ_COMPILE_DATA(iseq)->err_info;
    VALUE file = iseq->body->location.path;
    VALUE err = err_info;
    va_list args;

    va_start(args, fmt);
    err = rb_syntax_error_append(err, file, line, -1, NULL, fmt, args);
    va_end(args);
    if (NIL_P(err_info)) {
	RB_OBJ_WRITE(iseq, &ISEQ_COMPILE_DATA(iseq)->err_info, err);
	rb_set_errinfo(err);
    }
}

static void
compile_bug(rb_iseq_t *iseq, int line, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    rb_report_bug_valist(iseq->body->location.path, line, fmt, args);
    va_end(args);
    abort();
}

NOINLINE(static compile_error_func prepare_compile_error(rb_iseq_t *iseq));

static compile_error_func
prepare_compile_error(rb_iseq_t *iseq)
{
    if (compile_debug) return &compile_bug;
    return &append_compile_error;
}

#define COMPILE_ERROR prepare_compile_error(iseq)

#define ERROR_ARGS_AT(n) iseq, nd_line(n),
#define ERROR_ARGS ERROR_ARGS_AT(node)

#define EXPECT_NODE(prefix, node, ndtype) \
do { \
    NODE *error_node = (node); \
    enum node_type error_type = nd_type(error_node); \
    if (error_type != (ndtype)) { \
	compile_bug(ERROR_ARGS_AT(error_node) \
		    prefix ": " #ndtype " is expected, but %s", \
		    ruby_node_name(error_type)); \
    } \
} while (0)

#define EXPECT_NODE_NONULL(prefix, parent, ndtype) \
do { \
    compile_bug(ERROR_ARGS_AT(parent) \
		prefix ": must be " #ndtype ", but 0"); \
} while (0)

#define UNKNOWN_NODE(prefix, node) \
do { \
    NODE *error_node = (node); \
    compile_bug(ERROR_ARGS_AT(error_node) prefix ": unknown node (%s)", \
		ruby_node_name(nd_type(error_node))); \
} while (0)

#define COMPILE_OK 1
#define COMPILE_NG 0


/* leave name uninitialized so that compiler warn if INIT_ANCHOR is
 * missing */
#define DECL_ANCHOR(name) \
    LINK_ANCHOR name[1] = {{{0,},}}
#define INIT_ANCHOR(name) \
    (name->last = &name->anchor)

static inline VALUE
freeze_hide_obj(VALUE obj)
{
    OBJ_FREEZE(obj);
    RBASIC_CLEAR_CLASS(obj);
    return obj;
}

#include "optinsn.inc"
#if OPT_INSTRUCTIONS_UNIFICATION
#include "optunifs.inc"
#endif

/* for debug */
#if CPDEBUG < 0
#define ISEQ_ARG iseq,
#define ISEQ_ARG_DECLARE rb_iseq_t *iseq,
#else
#define ISEQ_ARG
#define ISEQ_ARG_DECLARE
#endif

#if CPDEBUG
#define gl_node_level ISEQ_COMPILE_DATA(iseq)->node_level
#endif

static void dump_disasm_list(LINK_ELEMENT *elem);

static int insn_data_length(INSN *iobj);
static int calc_sp_depth(int depth, INSN *iobj);

static INSN *new_insn_body(rb_iseq_t *iseq, int line_no, enum ruby_vminsn_type insn_id, int argc, ...);
static LABEL *new_label_body(rb_iseq_t *iseq, long line);
static ADJUST *new_adjust_body(rb_iseq_t *iseq, LABEL *label, int line);

static int iseq_compile_each(rb_iseq_t *iseq, LINK_ANCHOR *const anchor, NODE *n, int);
static int iseq_setup(rb_iseq_t *iseq, LINK_ANCHOR *const anchor);
static int iseq_optimize(rb_iseq_t *iseq, LINK_ANCHOR *const anchor);
static int iseq_insns_unification(rb_iseq_t *iseq, LINK_ANCHOR *const anchor);

static int iseq_set_local_table(rb_iseq_t *iseq, const ID *tbl);
static int iseq_set_exception_local_table(rb_iseq_t *iseq);
static int iseq_set_arguments(rb_iseq_t *iseq, LINK_ANCHOR *const anchor, NODE *node);

static int iseq_set_sequence_stackcaching(rb_iseq_t *iseq, LINK_ANCHOR *const anchor);
static int iseq_set_sequence(rb_iseq_t *iseq, LINK_ANCHOR *const anchor);
static int iseq_set_exception_table(rb_iseq_t *iseq);
static int iseq_set_optargs_table(rb_iseq_t *iseq);

/*
 * To make Array to LinkedList, use link_anchor
 */

static void
verify_list(ISEQ_ARG_DECLARE const char *info, LINK_ANCHOR *const anchor)
{
#if CPDEBUG
    int flag = 0;
    LINK_ELEMENT *list, *plist;

    if (!compile_debug) return;

    list = anchor->anchor.next;
    plist = &anchor->anchor;
    while (list) {
	if (plist != list->prev) {
	    flag += 1;
	}
	plist = list;
	list = list->next;
    }

    if (anchor->last != plist && anchor->last != 0) {
	flag |= 0x70000;
    }

    if (flag != 0) {
	rb_bug("list verify error: %08x (%s)", flag, info);
    }
#endif
}
#if CPDEBUG < 0
#define verify_list(info, anchor) verify_list(iseq, (info), (anchor))
#endif

/*
 * elem1, elem2 => elem1, elem2, elem
 */
static void
ADD_ELEM(ISEQ_ARG_DECLARE LINK_ANCHOR *const anchor, LINK_ELEMENT *elem)
{
    elem->prev = anchor->last;
    anchor->last->next = elem;
    anchor->last = elem;
    verify_list("add", anchor);
}

/*
 * elem1, before, elem2 => elem1, before, elem, elem2
 */
static void
APPEND_ELEM(ISEQ_ARG_DECLARE LINK_ANCHOR *const anchor, LINK_ELEMENT *before, LINK_ELEMENT *elem)
{
    elem->prev = before;
    elem->next = before->next;
    elem->next->prev = elem;
    before->next = elem;
    if (before == anchor->last) anchor->last = elem;
    verify_list("add", anchor);
}
#if CPDEBUG < 0
#define ADD_ELEM(anchor, elem) ADD_ELEM(iseq, (anchor), (elem))
#define APPEND_ELEM(anchor, before, elem) APPEND_ELEM(iseq, (anchor), (before), (elem))
#endif

static int
iseq_add_mark_object(const rb_iseq_t *iseq, VALUE v)
{
    if (!SPECIAL_CONST_P(v)) {
	rb_iseq_add_mark_object(iseq, v);
    }
    return COMPILE_OK;
}

#define ruby_sourcefile		RSTRING_PTR(iseq->body->location.path)

static int
iseq_add_mark_object_compile_time(const rb_iseq_t *iseq, VALUE v)
{
    if (!SPECIAL_CONST_P(v)) {
	rb_ary_push(ISEQ_COMPILE_DATA(iseq)->mark_ary, v);
    }
    return COMPILE_OK;
}

static int
validate_label(st_data_t name, st_data_t label, st_data_t arg)
{
    rb_iseq_t *iseq = (rb_iseq_t *)arg;
    LABEL *lobj = (LABEL *)label;
    if (!lobj->link.next) {
	do {
	    COMPILE_ERROR(iseq, lobj->position,
			  "%"PRIsVALUE": undefined label",
			  rb_id2str((ID)name));
	} while (0);
    }
    return ST_CONTINUE;
}

static void
validate_labels(rb_iseq_t *iseq, st_table *labels_table)
{
    st_foreach(labels_table, validate_label, (st_data_t)iseq);
    st_free_table(labels_table);
    if (!NIL_P(ISEQ_COMPILE_DATA(iseq)->err_info)) {
	rb_exc_raise(ISEQ_COMPILE_DATA(iseq)->err_info);
    }
}

VALUE
rb_iseq_compile_node(rb_iseq_t *iseq, NODE *node)
{
    DECL_ANCHOR(ret);
    INIT_ANCHOR(ret);

    if (node == 0) {
	COMPILE(ret, "nil", node);
	iseq_set_local_table(iseq, 0);
    }
    else if (nd_type(node) == NODE_SCOPE) {
	/* iseq type of top, method, class, block */
	iseq_set_local_table(iseq, node->nd_tbl);
	iseq_set_arguments(iseq, ret, node->nd_args);

	switch (iseq->body->type) {
	  case ISEQ_TYPE_BLOCK:
	    {
		LABEL *start = ISEQ_COMPILE_DATA(iseq)->start_label = NEW_LABEL(0);
		LABEL *end = ISEQ_COMPILE_DATA(iseq)->end_label = NEW_LABEL(0);

		start->rescued = LABEL_RESCUE_BEG;
		end->rescued = LABEL_RESCUE_END;

		ADD_TRACE(ret, FIX2INT(iseq->body->location.first_lineno), RUBY_EVENT_B_CALL);
		ADD_LABEL(ret, start);
		COMPILE(ret, "block body", node->nd_body);
		ADD_LABEL(ret, end);
		ADD_TRACE(ret, nd_line(node), RUBY_EVENT_B_RETURN);

		/* wide range catch handler must put at last */
		ADD_CATCH_ENTRY(CATCH_TYPE_REDO, start, end, 0, start);
		ADD_CATCH_ENTRY(CATCH_TYPE_NEXT, start, end, 0, end);
		break;
	    }
	  case ISEQ_TYPE_CLASS:
	    {
		ADD_TRACE(ret, FIX2INT(iseq->body->location.first_lineno), RUBY_EVENT_CLASS);
		COMPILE(ret, "scoped node", node->nd_body);
		ADD_TRACE(ret, nd_line(node), RUBY_EVENT_END);
		break;
	    }
	  case ISEQ_TYPE_METHOD:
	    {
		ADD_TRACE(ret, FIX2INT(iseq->body->location.first_lineno), RUBY_EVENT_CALL);
		COMPILE(ret, "scoped node", node->nd_body);
		ADD_TRACE(ret, nd_line(node), RUBY_EVENT_RETURN);
		break;
	    }
	  default: {
	    COMPILE(ret, "scoped node", node->nd_body);
	    break;
	  }
	}
    }
    else if (RB_TYPE_P((VALUE)node, T_IMEMO)) {
	const struct vm_ifunc *ifunc = (struct vm_ifunc *)node;
	/* user callback */
	(*ifunc->func)(iseq, ret, ifunc->data);
    }
    else {
	switch (iseq->body->type) {
	  case ISEQ_TYPE_METHOD:
	  case ISEQ_TYPE_CLASS:
	  case ISEQ_TYPE_BLOCK:
	  case ISEQ_TYPE_EVAL:
	  case ISEQ_TYPE_MAIN:
	  case ISEQ_TYPE_TOP:
	    COMPILE_ERROR(ERROR_ARGS "compile/should not be reached: %s:%d",
			  __FILE__, __LINE__);
	    return COMPILE_NG;
	  case ISEQ_TYPE_RESCUE:
	    iseq_set_exception_local_table(iseq);
	    COMPILE(ret, "rescue", node);
	    break;
	  case ISEQ_TYPE_ENSURE:
	    iseq_set_exception_local_table(iseq);
	    COMPILE_POPPED(ret, "ensure", node);
	    break;
	  case ISEQ_TYPE_DEFINED_GUARD:
	    iseq_set_exception_local_table(iseq);
	    COMPILE(ret, "defined guard", node);
	    break;
	  default:
	    compile_bug(ERROR_ARGS "unknown scope");
	}
    }

    if (iseq->body->type == ISEQ_TYPE_RESCUE || iseq->body->type == ISEQ_TYPE_ENSURE) {
	ADD_GETLOCAL(ret, 0, LVAR_ERRINFO, 0);
	ADD_INSN1(ret, 0, throw, INT2FIX(0) /* continue throw */ );
    }
    else {
	ADD_INSN(ret, ISEQ_COMPILE_DATA(iseq)->last_line, leave);
    }

#if SUPPORT_JOKE
    if (ISEQ_COMPILE_DATA(iseq)->labels_table) {
	st_table *labels_table = ISEQ_COMPILE_DATA(iseq)->labels_table;
	ISEQ_COMPILE_DATA(iseq)->labels_table = 0;
	validate_labels(iseq, labels_table);
    }
#endif
    return iseq_setup(iseq, ret);
}

int
rb_iseq_translate_threaded_code(rb_iseq_t *iseq)
{
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
    const void * const *table = rb_vm_get_insns_address_table();
    unsigned int i;
    VALUE *encoded = (VALUE *)iseq->body->iseq_encoded;

    for (i = 0; i < iseq->body->iseq_size; /* */ ) {
	int insn = (int)iseq->body->iseq_encoded[i];
	int len = insn_len(insn);
	encoded[i] = (VALUE)table[insn];
	i += len;
    }
#endif
    return COMPILE_OK;
}

#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
static int
rb_vm_insn_addr2insn(const void *addr) /* cold path */
{
    int insn;
    const void * const *table = rb_vm_get_insns_address_table();

    for (insn = 0; insn < VM_INSTRUCTION_SIZE; insn++) {
	if (table[insn] == addr) {
	    return insn;
	}
    }
    rb_bug("rb_vm_insn_addr2insn: invalid insn address: %p", addr);
}
#endif

VALUE *
rb_iseq_original_iseq(const rb_iseq_t *iseq) /* cold path */
{
    VALUE *original_code;

    if (ISEQ_ORIGINAL_ISEQ(iseq)) return ISEQ_ORIGINAL_ISEQ(iseq);
    original_code = ISEQ_ORIGINAL_ISEQ_ALLOC(iseq, iseq->body->iseq_size);
    MEMCPY(original_code, iseq->body->iseq_encoded, VALUE, iseq->body->iseq_size);

#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
    {
	unsigned int i;

	for (i = 0; i < iseq->body->iseq_size; /* */ ) {
	    const void *addr = (const void *)original_code[i];
	    const int insn = rb_vm_insn_addr2insn(addr);

	    original_code[i] = insn;
	    i += insn_len(insn);
	}
    }
#endif
    return original_code;
}

/*********************************************/
/* definition of data structure for compiler */
/*********************************************/

/*
 * On 32-bit SPARC, GCC by default generates SPARC V7 code that may require
 * 8-byte word alignment. On the other hand, Oracle Solaris Studio seems to
 * generate SPARCV8PLUS code with unaligned memory access instructions.
 * That is why the STRICT_ALIGNMENT is defined only with GCC.
 */
#if defined(__sparc) && SIZEOF_VOIDP == 4 && defined(__GNUC__)
  #define STRICT_ALIGNMENT
#endif

#ifdef STRICT_ALIGNMENT
  #if defined(HAVE_TRUE_LONG_LONG) && SIZEOF_LONG_LONG > SIZEOF_VALUE
    #define ALIGNMENT_SIZE SIZEOF_LONG_LONG
  #else
    #define ALIGNMENT_SIZE SIZEOF_VALUE
  #endif
  #define PADDING_SIZE_MAX    ((size_t)((ALIGNMENT_SIZE) - 1))
  #define ALIGNMENT_SIZE_MASK PADDING_SIZE_MAX
  /* Note: ALIGNMENT_SIZE == (2 ** N) is expected. */
#else
  #define PADDING_SIZE_MAX 0
#endif /* STRICT_ALIGNMENT */

#ifdef STRICT_ALIGNMENT
/* calculate padding size for aligned memory access */
static size_t
calc_padding(void *ptr, size_t size)
{
    size_t mis;
    size_t padding = 0;

    mis = (size_t)ptr & ALIGNMENT_SIZE_MASK;
    if (mis > 0) {
        padding = ALIGNMENT_SIZE - mis;
    }
/*
 * On 32-bit sparc or equivalents, when a single VALUE is requested
 * and padding == sizeof(VALUE), it is clear that no padding is needed.
 */
#if ALIGNMENT_SIZE > SIZEOF_VALUE
    if (size == sizeof(VALUE) && padding == sizeof(VALUE)) {
        padding = 0;
    }
#endif

    return padding;
}
#endif /* STRICT_ALIGNMENT */

static void *
compile_data_alloc(rb_iseq_t *iseq, size_t size)
{
    void *ptr = 0;
    struct iseq_compile_data_storage *storage =
	ISEQ_COMPILE_DATA(iseq)->storage_current;
#ifdef STRICT_ALIGNMENT
    size_t padding = calc_padding((void *)&storage->buff[storage->pos], size);
#else
    const size_t padding = 0; /* expected to be optimized by compiler */
#endif /* STRICT_ALIGNMENT */

    if (size >= INT_MAX - padding) rb_memerror();
    if (storage->pos + size + padding > storage->size) {
	unsigned int alloc_size = storage->size;

	while (alloc_size < size + PADDING_SIZE_MAX) {
	    if (alloc_size >= INT_MAX / 2) rb_memerror();
	    alloc_size *= 2;
	}
	storage->next = (void *)ALLOC_N(char, alloc_size +
					SIZEOF_ISEQ_COMPILE_DATA_STORAGE);
	storage = ISEQ_COMPILE_DATA(iseq)->storage_current = storage->next;
	storage->next = 0;
	storage->pos = 0;
	storage->size = alloc_size;
#ifdef STRICT_ALIGNMENT
        padding = calc_padding((void *)&storage->buff[storage->pos], size);
#endif /* STRICT_ALIGNMENT */
    }

#ifdef STRICT_ALIGNMENT
    storage->pos += (int)padding;
#endif /* STRICT_ALIGNMENT */

    ptr = (void *)&storage->buff[storage->pos];
    storage->pos += (int)size;
    return ptr;
}

static INSN *
compile_data_alloc_insn(rb_iseq_t *iseq)
{
    return (INSN *)compile_data_alloc(iseq, sizeof(INSN));
}

static LABEL *
compile_data_alloc_label(rb_iseq_t *iseq)
{
    return (LABEL *)compile_data_alloc(iseq, sizeof(LABEL));
}

static ADJUST *
compile_data_alloc_adjust(rb_iseq_t *iseq)
{
    return (ADJUST *)compile_data_alloc(iseq, sizeof(ADJUST));
}

/*
 * elem1, elemX => elem1, elem2, elemX
 */
static void
INSERT_ELEM_NEXT(LINK_ELEMENT *elem1, LINK_ELEMENT *elem2)
{
    elem2->next = elem1->next;
    elem2->prev = elem1;
    elem1->next = elem2;
    if (elem2->next) {
	elem2->next->prev = elem2;
    }
}

/*
 * elem1, elemX => elemX, elem2, elem1
 */
static void
INSERT_ELEM_PREV(LINK_ELEMENT *elem1, LINK_ELEMENT *elem2)
{
    elem2->prev = elem1->prev;
    elem2->next = elem1;
    elem1->prev = elem2;
    if (elem2->prev) {
	elem2->prev->next = elem2;
    }
}

#if 0
/*
 * elemX, elem1, elemY => elemX, elem2, elemY
 */
static void
REPLACE_ELEM(LINK_ELEMENT *elem1, LINK_ELEMENT *elem2)
{
    elem2->prev = elem1->prev;
    elem2->next = elem1->next;
    if (elem1->prev) {
	elem1->prev->next = elem2;
    }
    if (elem1->next) {
	elem1->next->prev = elem2;
    }
}
#endif

static void
REMOVE_ELEM(LINK_ELEMENT *elem)
{
    elem->prev->next = elem->next;
    if (elem->next) {
	elem->next->prev = elem->prev;
    }
}

static LINK_ELEMENT *
FIRST_ELEMENT(LINK_ANCHOR *const anchor)
{
    return anchor->anchor.next;
}

static LINK_ELEMENT *
LAST_ELEMENT(LINK_ANCHOR *const anchor)
{
    return anchor->last;
}

static LINK_ELEMENT *
POP_ELEMENT(ISEQ_ARG_DECLARE LINK_ANCHOR *const anchor)
{
    LINK_ELEMENT *elem = anchor->last;
    anchor->last = anchor->last->prev;
    anchor->last->next = 0;
    verify_list("pop", anchor);
    return elem;
}
#if CPDEBUG < 0
#define POP_ELEMENT(anchor) POP_ELEMENT(iseq, (anchor))
#endif

static int
LIST_SIZE_ZERO(LINK_ANCHOR *const anchor)
{
    if (anchor->anchor.next == 0) {
	return 1;
    }
    else {
	return 0;
    }
}

/*
 * anc1: e1, e2, e3
 * anc2: e4, e5
 *#=>
 * anc1: e1, e2, e3, e4, e5
 * anc2: e4, e5 (broken)
 */
static void
APPEND_LIST(ISEQ_ARG_DECLARE LINK_ANCHOR *const anc1, LINK_ANCHOR *const anc2)
{
    if (anc2->anchor.next) {
	anc1->last->next = anc2->anchor.next;
	anc2->anchor.next->prev = anc1->last;
	anc1->last = anc2->last;
    }
    verify_list("append", anc1);
}
#if CPDEBUG < 0
#define APPEND_LIST(anc1, anc2) APPEND_LIST(iseq, (anc1), (anc2))
#endif

/*
 * anc1: e1, e2, e3
 * anc2: e4, e5
 *#=>
 * anc1: e4, e5, e1, e2, e3
 * anc2: e4, e5 (broken)
 */
static void
INSERT_LIST(ISEQ_ARG_DECLARE LINK_ANCHOR *const anc1, LINK_ANCHOR *const anc2)
{
    if (anc2->anchor.next) {
	LINK_ELEMENT *first = anc1->anchor.next;
	anc1->anchor.next = anc2->anchor.next;
	anc1->anchor.next->prev = &anc1->anchor;
	anc2->last->next = first;
	if (first) {
	    first->prev = anc2->last;
	}
	else {
	    anc1->last = anc2->last;
	}
    }

    verify_list("append", anc1);
}
#if CPDEBUG < 0
#define INSERT_LIST(anc1, anc2) INSERT_LIST(iseq, (anc1), (anc2))
#endif

#if CPDEBUG && 0
static void
debug_list(ISEQ_ARG_DECLARE LINK_ANCHOR *const anchor)
{
    LINK_ELEMENT *list = FIRST_ELEMENT(anchor);
    printf("----\n");
    printf("anch: %p, frst: %p, last: %p\n", &anchor->anchor,
	   anchor->anchor.next, anchor->last);
    while (list) {
	printf("curr: %p, next: %p, prev: %p, type: %d\n", list, list->next,
	       list->prev, FIX2INT(list->type));
	list = list->next;
    }
    printf("----\n");

    dump_disasm_list(anchor->anchor.next);
    verify_list("debug list", anchor);
}
#if CPDEBUG < 0
#define debug_list(anc) debug_list(iseq, (anc))
#endif
#endif

static LABEL *
new_label_body(rb_iseq_t *iseq, long line)
{
    LABEL *labelobj = compile_data_alloc_label(iseq);

    labelobj->link.type = ISEQ_ELEMENT_LABEL;
    labelobj->link.next = 0;

    labelobj->label_no = ISEQ_COMPILE_DATA(iseq)->label_no++;
    labelobj->sc_state = 0;
    labelobj->sp = -1;
    labelobj->refcnt = 0;
    labelobj->set = 0;
    labelobj->rescued = LABEL_RESCUE_NONE;
    return labelobj;
}

static ADJUST *
new_adjust_body(rb_iseq_t *iseq, LABEL *label, int line)
{
    ADJUST *adjust = compile_data_alloc_adjust(iseq);
    adjust->link.type = ISEQ_ELEMENT_ADJUST;
    adjust->link.next = 0;
    adjust->label = label;
    adjust->line_no = line;
    if (label) LABEL_REF(label);
    return adjust;
}

static INSN *
new_insn_core(rb_iseq_t *iseq, int line_no,
	      int insn_id, int argc, VALUE *argv)
{
    INSN *iobj = compile_data_alloc_insn(iseq);
    /* printf("insn_id: %d, line: %d\n", insn_id, line_no); */

    iobj->link.type = ISEQ_ELEMENT_INSN;
    iobj->link.next = 0;
    iobj->insn_id = insn_id;
    iobj->line_no = line_no;
    iobj->operands = argv;
    iobj->operand_size = argc;
    iobj->sc_state = 0;
    return iobj;
}

static INSN *
new_insn_body(rb_iseq_t *iseq, int line_no, enum ruby_vminsn_type insn_id, int argc, ...)
{
    VALUE *operands = 0;
    va_list argv;
    if (argc > 0) {
	int i;
	va_init_list(argv, argc);
	operands = (VALUE *)compile_data_alloc(iseq, sizeof(VALUE) * argc);
	for (i = 0; i < argc; i++) {
	    VALUE v = va_arg(argv, VALUE);
	    operands[i] = v;
	}
	va_end(argv);
    }
    return new_insn_core(iseq, line_no, insn_id, argc, operands);
}

static struct rb_call_info *
new_callinfo(rb_iseq_t *iseq, ID mid, int argc, unsigned int flag, struct rb_call_info_kw_arg *kw_arg, int has_blockiseq)
{
    size_t size = kw_arg != NULL ? sizeof(struct rb_call_info_with_kwarg) : sizeof(struct rb_call_info);
    struct rb_call_info *ci = (struct rb_call_info *)compile_data_alloc(iseq, size);
    struct rb_call_info_with_kwarg *ci_kw = (struct rb_call_info_with_kwarg *)ci;

    ci->mid = mid;
    ci->flag = flag;
    ci->orig_argc = argc;

    if (kw_arg) {
	ci->flag |= VM_CALL_KWARG;
	ci_kw->kw_arg = kw_arg;
	ci->orig_argc += kw_arg->keyword_len;
	iseq->body->ci_kw_size++;
    }
    else {
	iseq->body->ci_size++;
    }

    if (!(ci->flag & (VM_CALL_ARGS_SPLAT | VM_CALL_ARGS_BLOCKARG)) &&
	kw_arg == NULL && !has_blockiseq) {
	ci->flag |= VM_CALL_ARGS_SIMPLE;
    }
    return ci;
}

static INSN *
new_insn_send(rb_iseq_t *iseq, int line_no, ID id, VALUE argc, const rb_iseq_t *blockiseq, VALUE flag, struct rb_call_info_kw_arg *keywords)
{
    VALUE *operands = (VALUE *)compile_data_alloc(iseq, sizeof(VALUE) * 3);
    operands[0] = (VALUE)new_callinfo(iseq, id, FIX2INT(argc), FIX2INT(flag), keywords, blockiseq != NULL);
    operands[1] = Qfalse; /* cache */
    operands[2] = (VALUE)blockiseq;
    return new_insn_core(iseq, line_no, BIN(send), 3, operands);
}

static rb_iseq_t *
new_child_iseq(rb_iseq_t *iseq, NODE *node,
	       VALUE name, const rb_iseq_t *parent, enum iseq_type type, int line_no)
{
    rb_iseq_t *ret_iseq;

    debugs("[new_child_iseq]> ---------------------------------------\n");
    ret_iseq = rb_iseq_new_with_opt(node, name,
				    iseq_path(iseq), iseq_absolute_path(iseq),
				    INT2FIX(line_no), parent, type, ISEQ_COMPILE_DATA(iseq)->option);
    debugs("[new_child_iseq]< ---------------------------------------\n");
    iseq_add_mark_object(iseq, (VALUE)ret_iseq);
    return ret_iseq;
}

static int
iseq_setup(rb_iseq_t *iseq, LINK_ANCHOR *const anchor)
{
    /* debugs("[compile step 2] (iseq_array_to_linkedlist)\n"); */

    if (compile_debug > 5)
	dump_disasm_list(FIRST_ELEMENT(anchor));

    debugs("[compile step 3.1 (iseq_optimize)]\n");
    iseq_optimize(iseq, anchor);

    if (compile_debug > 5)
	dump_disasm_list(FIRST_ELEMENT(anchor));

    if (ISEQ_COMPILE_DATA(iseq)->option->instructions_unification) {
	debugs("[compile step 3.2 (iseq_insns_unification)]\n");
	iseq_insns_unification(iseq, anchor);
	if (compile_debug > 5)
	    dump_disasm_list(FIRST_ELEMENT(anchor));
    }

    if (ISEQ_COMPILE_DATA(iseq)->option->stack_caching) {
	debugs("[compile step 3.3 (iseq_set_sequence_stackcaching)]\n");
	iseq_set_sequence_stackcaching(iseq, anchor);
	if (compile_debug > 5)
	    dump_disasm_list(FIRST_ELEMENT(anchor));
    }

    debugs("[compile step 4.1 (iseq_set_sequence)]\n");
    if (!iseq_set_sequence(iseq, anchor)) return COMPILE_NG;
    if (compile_debug > 5)
	dump_disasm_list(FIRST_ELEMENT(anchor));

    debugs("[compile step 4.2 (iseq_set_exception_table)]\n");
    if (!iseq_set_exception_table(iseq)) return COMPILE_NG;

    debugs("[compile step 4.3 (set_optargs_table)] \n");
    if (!iseq_set_optargs_table(iseq)) return COMPILE_NG;

    debugs("[compile step 5 (iseq_translate_threaded_code)] \n");
    if (!rb_iseq_translate_threaded_code(iseq)) return COMPILE_NG;

    if (compile_debug > 1) {
	VALUE str = rb_iseq_disasm(iseq);
	printf("%s\n", StringValueCStr(str));
    }
    debugs("[compile step: finish]\n");

    return COMPILE_OK;
}

static int
iseq_set_exception_local_table(rb_iseq_t *iseq)
{
    /* TODO: every id table is same -> share it.
     * Current problem is iseq_free().
     */
    ID id_dollar_bang;
    ID *ids = (ID *)ALLOC_N(ID, 1);

    CONST_ID(id_dollar_bang, "#$!");
    iseq->body->local_table_size = 1;
    ids[0] = id_dollar_bang;
    iseq->body->local_table = ids;
    return COMPILE_OK;
}

static int
get_lvar_level(const rb_iseq_t *iseq)
{
    int lev = 0;
    while (iseq != iseq->body->local_iseq) {
	lev++;
	iseq = iseq->body->parent_iseq;
    }
    return lev;
}

static int
get_dyna_var_idx_at_raw(const rb_iseq_t *iseq, ID id)
{
    unsigned int i;

    for (i = 0; i < iseq->body->local_table_size; i++) {
	if (iseq->body->local_table[i] == id) {
	    return (int)i;
	}
    }
    return -1;
}

static int
get_local_var_idx(const rb_iseq_t *iseq, ID id)
{
    int idx = get_dyna_var_idx_at_raw(iseq->body->local_iseq, id);

    if (idx < 0) {
	rb_bug("get_local_var_idx: %d", idx);
    }

    return idx;
}

static int
get_dyna_var_idx(const rb_iseq_t *iseq, ID id, int *level, int *ls)
{
    int lv = 0, idx = -1;

    while (iseq) {
	idx = get_dyna_var_idx_at_raw(iseq, id);
	if (idx >= 0) {
	    break;
	}
	iseq = iseq->body->parent_iseq;
	lv++;
    }

    if (idx < 0) {
	rb_bug("get_dyna_var_idx: -1");
    }

    *level = lv;
    *ls = iseq->body->local_table_size;
    return idx;
}

static void
iseq_calc_param_size(rb_iseq_t *iseq)
{
    if (iseq->body->param.flags.has_opt ||
	iseq->body->param.flags.has_post ||
	iseq->body->param.flags.has_rest ||
	iseq->body->param.flags.has_block ||
	iseq->body->param.flags.has_kw ||
	iseq->body->param.flags.has_kwrest) {

	if (iseq->body->param.flags.has_block) {
	    iseq->body->param.size = iseq->body->param.block_start + 1;
	}
	else if (iseq->body->param.flags.has_kwrest) {
	    iseq->body->param.size = iseq->body->param.keyword->rest_start + 1;
	}
	else if (iseq->body->param.flags.has_kw) {
	    iseq->body->param.size = iseq->body->param.keyword->bits_start + 1;
	}
	else if (iseq->body->param.flags.has_post) {
	    iseq->body->param.size = iseq->body->param.post_start + iseq->body->param.post_num;
	}
	else if (iseq->body->param.flags.has_rest) {
	    iseq->body->param.size = iseq->body->param.rest_start + 1;
	}
	else if (iseq->body->param.flags.has_opt) {
	    iseq->body->param.size = iseq->body->param.lead_num + iseq->body->param.opt_num;
	}
	else {
	    rb_bug("unreachable");
	}
    }
    else {
	iseq->body->param.size = iseq->body->param.lead_num;
    }
}

static void
iseq_set_arguments_keywords(rb_iseq_t *iseq, LINK_ANCHOR *const optargs,
			    const struct rb_args_info *args)
{
    NODE *node = args->kw_args;
    struct rb_iseq_param_keyword *keyword;
    const VALUE default_values = rb_ary_tmp_new(1);
    const VALUE complex_mark = rb_str_tmp_new(0);
    int kw = 0, rkw = 0, di = 0, i;

    iseq->body->param.flags.has_kw = TRUE;
    iseq->body->param.keyword = keyword = ZALLOC_N(struct rb_iseq_param_keyword, 1);
    keyword->bits_start = get_dyna_var_idx_at_raw(iseq, args->kw_rest_arg->nd_vid);

    while (node) {
	NODE *val_node = node->nd_body->nd_value;
	VALUE dv;

	if (val_node == (NODE *)-1) {
	    ++rkw;
	}
	else {
	    switch (nd_type(val_node)) {
	      case NODE_LIT:
		dv = val_node->nd_lit;
		iseq_add_mark_object(iseq, dv);
		break;
	      case NODE_NIL:
		dv = Qnil;
		break;
	      case NODE_TRUE:
		dv = Qtrue;
		break;
	      case NODE_FALSE:
		dv = Qfalse;
		break;
	      default:
		COMPILE_POPPED(optargs, "kwarg", node); /* nd_type(node) == NODE_KW_ARG */
		dv = complex_mark;
	    }

	    keyword->num = ++di;
	    rb_ary_push(default_values, dv);
	}

	kw++;
	node = node->nd_next;
    }

    keyword->num = kw;

    if (args->kw_rest_arg->nd_cflag != 0) {
	keyword->rest_start =  get_dyna_var_idx_at_raw(iseq, args->kw_rest_arg->nd_cflag);
	iseq->body->param.flags.has_kwrest = TRUE;
    }
    keyword->required_num = rkw;
    keyword->table = &iseq->body->local_table[keyword->bits_start - keyword->num];

    {
	VALUE *dvs = ALLOC_N(VALUE, RARRAY_LEN(default_values));

	for (i = 0; i < RARRAY_LEN(default_values); i++) {
	    VALUE dv = RARRAY_AREF(default_values, i);
	    if (dv == complex_mark) dv = Qundef;
	    dvs[i] = dv;
	}

	keyword->default_values = dvs;
    }
}

static int
iseq_set_arguments(rb_iseq_t *iseq, LINK_ANCHOR *const optargs, NODE *node_args)
{
    debugs("iseq_set_arguments: %s\n", node_args ? "" : "0");

    if (node_args) {
	struct rb_args_info *args = node_args->nd_ainfo;
	ID rest_id = 0;
	int last_comma = 0;
	ID block_id = 0;

	EXPECT_NODE("iseq_set_arguments", node_args, NODE_ARGS);

	iseq->body->param.lead_num = (int)args->pre_args_num;
	if (iseq->body->param.lead_num > 0) iseq->body->param.flags.has_lead = TRUE;
	debugs("  - argc: %d\n", iseq->body->param.lead_num);

	rest_id = args->rest_arg;
	if (rest_id == 1) {
	    last_comma = 1;
	    rest_id = 0;
	}
	block_id = args->block_arg;

	if (args->first_post_arg) {
	    iseq->body->param.post_start = get_dyna_var_idx_at_raw(iseq, args->first_post_arg);
	    iseq->body->param.post_num = args->post_args_num;
	    iseq->body->param.flags.has_post = TRUE;
	}

	if (args->opt_args) {
	    NODE *node = args->opt_args;
	    LABEL *label;
	    VALUE labels = rb_ary_tmp_new(1);
	    VALUE *opt_table;
	    int i = 0, j;

	    while (node) {
		label = NEW_LABEL(nd_line(node));
		rb_ary_push(labels, (VALUE)label | 1);
		ADD_LABEL(optargs, label);
		COMPILE_POPPED(optargs, "optarg", node->nd_body);
		node = node->nd_next;
		i += 1;
	    }

	    /* last label */
	    label = NEW_LABEL(nd_line(node_args));
	    rb_ary_push(labels, (VALUE)label | 1);
	    ADD_LABEL(optargs, label);

	    opt_table = ALLOC_N(VALUE, i+1);

	    MEMCPY(opt_table, RARRAY_CONST_PTR(labels), VALUE, i+1);
	    for (j = 0; j < i+1; j++) {
		opt_table[j] &= ~1;
	    }
	    rb_ary_clear(labels);

	    iseq->body->param.flags.has_opt = TRUE;
	    iseq->body->param.opt_num = i;
	    iseq->body->param.opt_table = opt_table;
	}

	if (args->kw_args) {
	    iseq_set_arguments_keywords(iseq, optargs, args);
	}
	else if (args->kw_rest_arg) {
	    struct rb_iseq_param_keyword *keyword = ZALLOC_N(struct rb_iseq_param_keyword, 1);
	    keyword->rest_start = get_dyna_var_idx_at_raw(iseq, args->kw_rest_arg->nd_vid);
	    iseq->body->param.keyword = keyword;
	    iseq->body->param.flags.has_kwrest = TRUE;
	}

	if (args->pre_init) { /* m_init */
	    COMPILE_POPPED(optargs, "init arguments (m)", args->pre_init);
	}
	if (args->post_init) { /* p_init */
	    COMPILE_POPPED(optargs, "init arguments (p)", args->post_init);
	}

	if (rest_id) {
	    iseq->body->param.rest_start = get_dyna_var_idx_at_raw(iseq, rest_id);
	    iseq->body->param.flags.has_rest = TRUE;
	    assert(iseq->body->param.rest_start != -1);

	    if (iseq->body->param.post_start == 0) { /* TODO: why that? */
		iseq->body->param.post_start = iseq->body->param.rest_start + 1;
	    }
	}

	if (block_id) {
	    iseq->body->param.block_start = get_dyna_var_idx_at_raw(iseq, block_id);
	    iseq->body->param.flags.has_block = TRUE;
	}

	iseq_calc_param_size(iseq);

	if (iseq->body->type == ISEQ_TYPE_BLOCK) {
	    if (iseq->body->param.flags.has_opt    == FALSE &&
		iseq->body->param.flags.has_post   == FALSE &&
		iseq->body->param.flags.has_rest   == FALSE &&
		iseq->body->param.flags.has_kw     == FALSE &&
		iseq->body->param.flags.has_kwrest == FALSE) {

		if (iseq->body->param.lead_num == 1 && last_comma == 0) {
		    /* {|a|} */
		    iseq->body->param.flags.ambiguous_param0 = TRUE;
		}
	    }
	}
    }

    return COMPILE_OK;
}

static int
iseq_set_local_table(rb_iseq_t *iseq, const ID *tbl)
{
    unsigned int size;

    if (tbl) {
	size = (unsigned int)*tbl;
	tbl++;
    }
    else {
	size = 0;
    }

    if (size > 0) {
	ID *ids = (ID *)ALLOC_N(ID, size);
	MEMCPY(ids, tbl, ID, size);
	iseq->body->local_table = ids;
    }
    iseq->body->local_table_size = size;

    debugs("iseq_set_local_table: %u\n", iseq->body->local_table_size);
    return COMPILE_OK;
}

static int
cdhash_cmp(VALUE val, VALUE lit)
{
    if (val == lit) return 0;
    if (SPECIAL_CONST_P(lit)) {
	return val != lit;
    }
    if (SPECIAL_CONST_P(val) || BUILTIN_TYPE(val) != BUILTIN_TYPE(lit)) {
	return -1;
    }
    if (BUILTIN_TYPE(lit) == T_STRING) {
	return rb_str_hash_cmp(lit, val);
    }
    return !rb_eql(lit, val);
}

static st_index_t
cdhash_hash(VALUE a)
{
    if (SPECIAL_CONST_P(a)) return (st_index_t)a;
    if (RB_TYPE_P(a, T_STRING)) return rb_str_hash(a);
    {
	VALUE hval = rb_hash(a);
	return (st_index_t)FIX2LONG(hval);
    }
}

static const struct st_hash_type cdhash_type = {
    cdhash_cmp,
    cdhash_hash,
};

struct cdhash_set_label_struct {
    VALUE hash;
    int pos;
    int len;
};

static int
cdhash_set_label_i(VALUE key, VALUE val, void *ptr)
{
    struct cdhash_set_label_struct *data = (struct cdhash_set_label_struct *)ptr;
    LABEL *lobj = (LABEL *)(val & ~1);
    rb_hash_aset(data->hash, key, INT2FIX(lobj->position - (data->pos+data->len)));
    return ST_CONTINUE;
}


static inline VALUE
get_ivar_ic_value(rb_iseq_t *iseq,ID id)
{
    VALUE val;
    struct rb_id_table *tbl = ISEQ_COMPILE_DATA(iseq)->ivar_cache_table;
    if (tbl) {
	if (rb_id_table_lookup(tbl,id,&val)) {
	    return val;
	}
    }
    else {
	tbl = rb_id_table_create(1);
	ISEQ_COMPILE_DATA(iseq)->ivar_cache_table = tbl;
    }
    val = INT2FIX(iseq->body->is_size++);
    rb_id_table_insert(tbl,id,val);
    return val;
}

/**
  ruby insn object list -> raw instruction sequence
 */
static int
iseq_set_sequence(rb_iseq_t *iseq, LINK_ANCHOR *const anchor)
{
    struct iseq_line_info_entry *line_info_table;
    unsigned int last_line = 0;
    LINK_ELEMENT *list;
    VALUE *generated_iseq;

    int insn_num, code_index, line_info_index, sp, stack_max = 0, line = 0;

    /* fix label position */
    list = FIRST_ELEMENT(anchor);
    insn_num = code_index = 0;
    while (list) {
	switch (list->type) {
	  case ISEQ_ELEMENT_INSN:
	    {
		INSN *iobj = (INSN *)list;
		line = iobj->line_no;
		code_index += insn_data_length(iobj);
		insn_num++;
		break;
	    }
	  case ISEQ_ELEMENT_LABEL:
	    {
		LABEL *lobj = (LABEL *)list;
		lobj->position = code_index;
		lobj->set = TRUE;
		break;
	    }
	  case ISEQ_ELEMENT_NONE:
	    {
		/* ignore */
		break;
	    }
	  case ISEQ_ELEMENT_ADJUST:
	    {
		ADJUST *adjust = (ADJUST *)list;
		if (adjust->line_no != -1) {
		    code_index += 2 /* insn + 1 operand */;
		    insn_num++;
		}
		break;
	    }
	  default:
	    dump_disasm_list(FIRST_ELEMENT(anchor));
	    dump_disasm_list(list);
	    COMPILE_ERROR(iseq, line, "error: set_sequence");
	    return COMPILE_NG;
	}
	list = list->next;
    }

    /* make instruction sequence */
    generated_iseq = ALLOC_N(VALUE, code_index);
    line_info_table = ALLOC_N(struct iseq_line_info_entry, insn_num);
    iseq->body->is_entries = ZALLOC_N(union iseq_inline_storage_entry, iseq->body->is_size);
    iseq->body->ci_entries = (struct rb_call_info *)ruby_xmalloc(sizeof(struct rb_call_info) * iseq->body->ci_size +
								 sizeof(struct rb_call_info_with_kwarg) * iseq->body->ci_kw_size);
    iseq->body->cc_entries = ZALLOC_N(struct rb_call_cache, iseq->body->ci_size + iseq->body->ci_kw_size);

    ISEQ_COMPILE_DATA(iseq)->ci_index = ISEQ_COMPILE_DATA(iseq)->ci_kw_index = 0;

    list = FIRST_ELEMENT(anchor);
    line_info_index = code_index = sp = 0;

    while (list) {
	switch (list->type) {
	  case ISEQ_ELEMENT_INSN:
	    {
		int j, len, insn;
		const char *types;
		VALUE *operands;
		INSN *iobj = (INSN *)list;

		/* update sp */
		sp = calc_sp_depth(sp, iobj);
		if (sp > stack_max) {
		    stack_max = sp;
		}

		/* fprintf(stderr, "insn: %-16s, sp: %d\n", insn_name(iobj->insn_id), sp); */
		operands = iobj->operands;
		insn = iobj->insn_id;
		generated_iseq[code_index] = insn;
		types = insn_op_types(insn);
		len = insn_len(insn);

		/* operand check */
		if (iobj->operand_size != len - 1) {
		    /* printf("operand size miss! (%d, %d)\n", iobj->operand_size, len); */
		    dump_disasm_list(list);
		    xfree(generated_iseq);
		    xfree(line_info_table);
		    COMPILE_ERROR(iseq, iobj->line_no,
				  "operand size miss! (%d for %d)",
				  iobj->operand_size, len - 1);
		    return COMPILE_NG;
		}

		for (j = 0; types[j]; j++) {
		    char type = types[j];
		    /* printf("--> [%c - (%d-%d)]\n", type, k, j); */
		    switch (type) {
		      case TS_OFFSET:
			{
			    /* label(destination position) */
			    LABEL *lobj = (LABEL *)operands[j];
			    if (!lobj->set) {
				COMPILE_ERROR(iseq, iobj->line_no,
					      "unknown label");
				return COMPILE_NG;
			    }
			    if (lobj->sp == -1) {
				lobj->sp = sp;
			    }
			    generated_iseq[code_index + 1 + j] = lobj->position - (code_index + len);
			    break;
			}
		      case TS_CDHASH:
			{
			    VALUE map = operands[j];
			    struct cdhash_set_label_struct data;
                            data.hash = map;
                            data.pos = code_index;
                            data.len = len;
			    rb_hash_foreach(map, cdhash_set_label_i, (VALUE)&data);

			    rb_hash_rehash(map);
			    freeze_hide_obj(map);
			    generated_iseq[code_index + 1 + j] = map;
			    break;
			}
		      case TS_LINDEX:
		      case TS_NUM:	/* ulong */
			generated_iseq[code_index + 1 + j] = FIX2INT(operands[j]);
			break;
		      case TS_ISEQ:	/* iseq */
			{
			    VALUE v = operands[j];
			    generated_iseq[code_index + 1 + j] = v;
			    break;
			}
		      case TS_VALUE:	/* VALUE */
			{
			    VALUE v = operands[j];
			    generated_iseq[code_index + 1 + j] = v;
			    /* to mark ruby object */
			    iseq_add_mark_object(iseq, v);
			    break;
			}
		      case TS_IC: /* inline cache */
			{
			    unsigned int ic_index = FIX2UINT(operands[j]);
			    IC ic = (IC)&iseq->body->is_entries[ic_index];
			    if (UNLIKELY(ic_index >= iseq->body->is_size)) {
				rb_bug("iseq_set_sequence: ic_index overflow: index: %d, size: %d", ic_index, iseq->body->is_size);
			    }
			    generated_iseq[code_index + 1 + j] = (VALUE)ic;
			    break;
			}
		      case TS_CALLINFO: /* call info */
			{
			    struct rb_call_info *base_ci = (struct rb_call_info *)operands[j];
			    struct rb_call_info *ci;

			    if (base_ci->flag & VM_CALL_KWARG) {
				struct rb_call_info_with_kwarg *ci_kw_entries = (struct rb_call_info_with_kwarg *)&iseq->body->ci_entries[iseq->body->ci_size];
				struct rb_call_info_with_kwarg *ci_kw = &ci_kw_entries[ISEQ_COMPILE_DATA(iseq)->ci_kw_index++];
				*ci_kw = *((struct rb_call_info_with_kwarg *)base_ci);
				ci = (struct rb_call_info *)ci_kw;
				assert(ISEQ_COMPILE_DATA(iseq)->ci_kw_index <= iseq->body->ci_kw_size);
			    }
			    else {
				ci = &iseq->body->ci_entries[ISEQ_COMPILE_DATA(iseq)->ci_index++];
				*ci = *base_ci;
				assert(ISEQ_COMPILE_DATA(iseq)->ci_index <= iseq->body->ci_size);
			    }

			    generated_iseq[code_index + 1 + j] = (VALUE)ci;
			    break;
			}
		      case TS_CALLCACHE:
			{
			    struct rb_call_cache *cc = &iseq->body->cc_entries[ISEQ_COMPILE_DATA(iseq)->ci_index + ISEQ_COMPILE_DATA(iseq)->ci_kw_index - 1];
			    generated_iseq[code_index + 1 + j] = (VALUE)cc;
			    break;
			}
		      case TS_ID: /* ID */
			generated_iseq[code_index + 1 + j] = SYM2ID(operands[j]);
			break;
		      case TS_GENTRY:
			{
			    struct rb_global_entry *entry =
				(struct rb_global_entry *)(operands[j] & (~1));
			    generated_iseq[code_index + 1 + j] = (VALUE)entry;
			}
			break;
		      case TS_FUNCPTR:
			generated_iseq[code_index + 1 + j] = operands[j];
			break;
		      default:
			xfree(generated_iseq);
			xfree(line_info_table);
			COMPILE_ERROR(iseq, iobj->line_no,
				      "unknown operand type: %c", type);
			return COMPILE_NG;
		    }
		}
		if (last_line != iobj->line_no) {
		    line_info_table[line_info_index].line_no = last_line = iobj->line_no;
		    line_info_table[line_info_index].position = code_index;
		    line_info_index++;
		}
		code_index += len;
		break;
	    }
	  case ISEQ_ELEMENT_LABEL:
	    {
		LABEL *lobj = (LABEL *)list;
		if (lobj->sp == -1) {
		    lobj->sp = sp;
		}
		else {
		    sp = lobj->sp;
		}
		break;
	    }
	  case ISEQ_ELEMENT_ADJUST:
	    {
		ADJUST *adjust = (ADJUST *)list;
		int orig_sp = sp;

		if (adjust->label) {
		    sp = adjust->label->sp;
		}
		else {
		    sp = 0;
		}

		if (adjust->line_no != -1) {
		    if (orig_sp - sp > 0) {
			if (last_line != (unsigned int)adjust->line_no) {
			    line_info_table[line_info_index].line_no = last_line = adjust->line_no;
			    line_info_table[line_info_index].position = code_index;
			    line_info_index++;
			}
			generated_iseq[code_index++] = BIN(adjuststack);
			generated_iseq[code_index++] = orig_sp - sp;
		    }
		    else if (orig_sp - sp == 0) {
			/* jump to next insn */
			if (last_line != (unsigned int)adjust->line_no) {
			    line_info_table[line_info_index].line_no = last_line = adjust->line_no;
			    line_info_table[line_info_index].position = code_index;
			    line_info_index++;
			}
			generated_iseq[code_index++] = BIN(nop);
			generated_iseq[code_index++] = BIN(nop);
		    }
		    else {
			compile_bug(iseq, adjust->line_no,
				    "iseq_set_sequence: adjust bug %d < %d",
				    orig_sp, sp);
		    }
		}
		break;
	    }
	  default:
	    /* ignore */
	    break;
	}
	list = list->next;
    }

    iseq->body->iseq_encoded = (void *)generated_iseq;
    iseq->body->iseq_size = code_index;
    iseq->body->stack_max = stack_max;

    REALLOC_N(line_info_table, struct iseq_line_info_entry, line_info_index);
    iseq->body->line_info_table = line_info_table;
    iseq->body->line_info_size = line_info_index;

    return COMPILE_OK;
}

static int
label_get_position(LABEL *lobj)
{
    return lobj->position;
}

static int
label_get_sp(LABEL *lobj)
{
    return lobj->sp;
}

static int
iseq_set_exception_table(rb_iseq_t *iseq)
{
    const VALUE *tptr, *ptr;
    unsigned int tlen, i;
    struct iseq_catch_table_entry *entry;

    tlen = (int)RARRAY_LEN(ISEQ_COMPILE_DATA(iseq)->catch_table_ary);
    tptr = RARRAY_CONST_PTR(ISEQ_COMPILE_DATA(iseq)->catch_table_ary);

    if (tlen > 0) {
	struct iseq_catch_table *table = xmalloc(iseq_catch_table_bytes(tlen));
	table->size = tlen;

	for (i = 0; i < table->size; i++) {
	    ptr = RARRAY_CONST_PTR(tptr[i]);
	    entry = &table->entries[i];
	    entry->type = (enum catch_type)(ptr[0] & 0xffff);
	    entry->start = label_get_position((LABEL *)(ptr[1] & ~1));
	    entry->end = label_get_position((LABEL *)(ptr[2] & ~1));
	    entry->iseq = (rb_iseq_t *)ptr[3];

	    /* register iseq as mark object */
	    if (entry->iseq != 0) {
		iseq_add_mark_object(iseq, (VALUE)entry->iseq);
	    }

	    /* stack depth */
	    if (ptr[4]) {
		LABEL *lobj = (LABEL *)(ptr[4] & ~1);
		entry->cont = label_get_position(lobj);
		entry->sp = label_get_sp(lobj);

		/* TODO: Dirty Hack!  Fix me */
		if (entry->type == CATCH_TYPE_RESCUE ||
		    entry->type == CATCH_TYPE_BREAK ||
		    entry->type == CATCH_TYPE_NEXT) {
		    entry->sp--;
		}
	    }
	    else {
		entry->cont = 0;
	    }
	}
	iseq->body->catch_table = table;
	RB_OBJ_WRITE(iseq, &ISEQ_COMPILE_DATA(iseq)->catch_table_ary, 0); /* free */
    }
    else {
	iseq->body->catch_table = NULL;
    }

    return COMPILE_OK;
}

/*
 * set optional argument table
 *   def foo(a, b=expr1, c=expr2)
 *   =>
 *    b:
 *      expr1
 *    c:
 *      expr2
 */
static int
iseq_set_optargs_table(rb_iseq_t *iseq)
{
    int i;
    VALUE *opt_table = (VALUE *)iseq->body->param.opt_table;

    if (iseq->body->param.flags.has_opt) {
	for (i = 0; i < iseq->body->param.opt_num + 1; i++) {
	    opt_table[i] = label_get_position((LABEL *)opt_table[i]);
	}
    }
    return COMPILE_OK;
}

static LINK_ELEMENT *
get_destination_insn(INSN *iobj)
{
    LABEL *lobj = (LABEL *)OPERAND_AT(iobj, 0);
    LINK_ELEMENT *list;

    list = lobj->link.next;
    while (list) {
	if (IS_INSN(list) || IS_ADJUST(list)) {
	    break;
	}
	list = list->next;
    }
    return list;
}

static LINK_ELEMENT *
get_next_insn(INSN *iobj)
{
    LINK_ELEMENT *list = iobj->link.next;

    while (list) {
	if (IS_INSN(list) || IS_ADJUST(list)) {
	    return list;
	}
	list = list->next;
    }
    return 0;
}

static LINK_ELEMENT *
get_prev_insn(INSN *iobj)
{
    LINK_ELEMENT *list = iobj->link.prev;

    while (list) {
	if (IS_INSN(list) || IS_ADJUST(list)) {
	    return list;
	}
	list = list->prev;
    }
    return 0;
}

static void
unref_destination(INSN *iobj, int pos)
{
    LABEL *lobj = (LABEL *)OPERAND_AT(iobj, pos);
    --lobj->refcnt;
    if (!lobj->refcnt) REMOVE_ELEM(&lobj->link);
}

static void
replace_destination(INSN *dobj, INSN *nobj)
{
    VALUE n = OPERAND_AT(nobj, 0);
    LABEL *dl = (LABEL *)OPERAND_AT(dobj, 0);
    LABEL *nl = (LABEL *)n;
    --dl->refcnt;
    ++nl->refcnt;
    OPERAND_AT(dobj, 0) = n;
    if (!dl->refcnt) REMOVE_ELEM(&dl->link);
}

static int
remove_unreachable_chunk(rb_iseq_t *iseq, LINK_ELEMENT *i)
{
    int removed = 0;
    while (i) {
	if (IS_INSN(i)) {
	    struct rb_iseq_constant_body *body = iseq->body;
	    VALUE insn = INSN_OF(i);
	    int pos, len = insn_len(insn);
	    for (pos = 0; pos < len; ++pos) {
		switch (insn_op_types(insn)[pos]) {
		  case TS_OFFSET:
		    unref_destination((INSN *)i, pos);
		    break;
		  case TS_CALLINFO:
		    if (((struct rb_call_info *)OPERAND_AT(i, pos))->flag & VM_CALL_KWARG)
			--(body->ci_kw_size);
		    else
			--(body->ci_size);
		    break;
		}
	    }
	}
	else if (IS_LABEL(i)) {
	    if (((LABEL *)i)->refcnt > 0) break;
	}
	else break;
	REMOVE_ELEM(i);
	removed = 1;
	i = i->next;
    }
    return removed;
}

static int
iseq_peephole_optimize(rb_iseq_t *iseq, LINK_ELEMENT *list, const int do_tailcallopt)
{
    INSN *iobj = (INSN *)list;
  again:
    if (IS_INSN_ID(iobj, jump)) {
	INSN *niobj, *diobj, *piobj;
	/*
	 *  useless jump elimination:
	 *     jump LABEL1
	 *     ...
	 *   LABEL1:
	 *     jump LABEL2
	 *
	 *   => in this case, first jump instruction should jump to
	 *      LABEL2 directly
	 */
	diobj = (INSN *)get_destination_insn(iobj);
	niobj = (INSN *)get_next_insn(iobj);

	if (diobj == niobj) {
	    /*
	     *   jump LABEL
	     *  LABEL:
	     * =>
	     *   LABEL:
	     */
	    unref_destination(iobj, 0);
	    REMOVE_ELEM(&iobj->link);
	}
	else if (iobj != diobj && IS_INSN_ID(diobj, jump) &&
		 OPERAND_AT(iobj, 0) != OPERAND_AT(diobj, 0)) {
	    replace_destination(iobj, diobj);
	    remove_unreachable_chunk(iseq, iobj->link.next);
	    goto again;
	}
	else if (IS_INSN_ID(diobj, leave)) {
	    /*
	     *  jump LABEL
	     *  ...
	     * LABEL:
	     *  leave
	     * =>
	     *  leave
	     *  ...
	     * LABEL:
	     *  leave
	     */
	    INSN *popiobj = new_insn_core(iseq, iobj->line_no,
					  BIN(pop), 0, 0);
	    /* replace */
	    unref_destination(iobj, 0);
	    iobj->insn_id = BIN(leave);
	    iobj->operand_size = 0;
	    INSERT_ELEM_NEXT(&iobj->link, &popiobj->link);
	    goto again;
	}
	/*
	 * useless jump elimination (if/unless destination):
	 *   if   L1
	 *   jump L2
	 * L1:
	 *   ...
	 * L2:
	 *
	 * ==>
	 *   unless L2
	 * L1:
	 *   ...
	 * L2:
	 */
	else if ((piobj = (INSN *)get_prev_insn(iobj)) != 0 &&
		 (IS_INSN_ID(piobj, branchif) ||
		  IS_INSN_ID(piobj, branchunless))) {
	    if (niobj == (INSN *)get_destination_insn(piobj)) {
		piobj->insn_id = (IS_INSN_ID(piobj, branchif))
		  ? BIN(branchunless) : BIN(branchif);
		replace_destination(piobj, iobj);
		REMOVE_ELEM(&iobj->link);
	    }
	}
	else if (remove_unreachable_chunk(iseq, iobj->link.next)) {
	    goto again;
	}
    }

    if (IS_INSN_ID(iobj, leave)) {
	remove_unreachable_chunk(iseq, iobj->link.next);
    }

    if (IS_INSN_ID(iobj, branchif) ||
	IS_INSN_ID(iobj, branchnil) ||
	IS_INSN_ID(iobj, branchunless)) {
	/*
	 *   if L1
	 *   ...
	 * L1:
	 *   jump L2
	 * =>
	 *   if L2
	 */
	INSN *nobj = (INSN *)get_destination_insn(iobj);
	INSN *pobj = (INSN *)iobj->link.prev;
	int prev_dup = 0;
	if (pobj) {
	    if (!IS_INSN(&pobj->link))
		pobj = 0;
	    else if (IS_INSN_ID(pobj, dup))
		prev_dup = 1;
	}

	for (;;) {
	    if (IS_INSN_ID(nobj, jump)) {
		replace_destination(iobj, nobj);
	    }
	    else if (prev_dup && IS_INSN_ID(nobj, dup) &&
		     !!(nobj = (INSN *)nobj->link.next) &&
		     /* basic blocks, with no labels in the middle */
		     nobj->insn_id == iobj->insn_id) {
		/*
		 *   dup
		 *   if L1
		 *   ...
		 * L1:
		 *   dup
		 *   if L2
		 * =>
		 *   dup
		 *   if L2
		 *   ...
		 * L1:
		 *   dup
		 *   if L2
		 */
		replace_destination(iobj, nobj);
	    }
	    else if (pobj) {
		/*
		 *   putnil
		 *   if L1
		 * =>
		 *   # nothing
		 *
		 *   putobject true
		 *   if L1
		 * =>
		 *   jump L1
		 *
		 *   putstring ".."
		 *   if L1
		 * =>
		 *   jump L1
		 *
		 *   putstring ".."
		 *   dup
		 *   if L1
		 * =>
		 *   putstring ".."
		 *   jump L1
		 *
		 */
		int cond;
		if (prev_dup && IS_INSN(pobj->link.prev)) {
		    pobj = (INSN *)pobj->link.prev;
		}
		if (IS_INSN_ID(pobj, putobject)) {
		    cond = (IS_INSN_ID(iobj, branchif) ?
			    OPERAND_AT(pobj, 0) != Qfalse :
			    IS_INSN_ID(iobj, branchunless) ?
			    OPERAND_AT(pobj, 0) == Qfalse :
			    FALSE);
		}
		else if (IS_INSN_ID(pobj, putstring)) {
		    cond = IS_INSN_ID(iobj, branchif);
		}
		else if (IS_INSN_ID(pobj, putnil)) {
		    cond = !IS_INSN_ID(iobj, branchif);
		}
		else break;
		REMOVE_ELEM(iobj->link.prev);
		if (cond) {
		    iobj->insn_id = BIN(jump);
		    goto again;
		}
		else {
		    unref_destination(iobj, 0);
		    REMOVE_ELEM(&iobj->link);
		}
		break;
	    }
	    else break;
	    nobj = (INSN *)get_destination_insn(nobj);
	}
    }

    if (IS_INSN_ID(iobj, pop)) {
	/*
	 *  putself / putnil / putobject obj / putstring "..."
	 *  pop
	 * =>
	 *  # do nothing
	 */
	LINK_ELEMENT *prev = iobj->link.prev;
	if (IS_INSN(prev)) {
	    enum ruby_vminsn_type previ = ((INSN *)prev)->insn_id;
	    if (previ == BIN(putobject) || previ == BIN(putnil) ||
		previ == BIN(putself) || previ == BIN(putstring)) {
		/* just push operand or static value and pop soon, no
		 * side effects */
		REMOVE_ELEM(prev);
		REMOVE_ELEM(&iobj->link);
	    }
	}
    }

    if (IS_INSN_ID(iobj, newarray) ||
	IS_INSN_ID(iobj, duparray) ||
	IS_INSN_ID(iobj, expandarray) ||
	IS_INSN_ID(iobj, concatarray) ||
	IS_INSN_ID(iobj, splatarray) ||
	0) {
	/*
	 *  newarray N
	 *  splatarray
	 * =>
	 *  newarray N
	 * newarray always puts an array
	 */
	LINK_ELEMENT *next = iobj->link.next;
	if (IS_INSN(next) && IS_INSN_ID(next, splatarray)) {
	    /* remove splatarray following always-array insn */
	    REMOVE_ELEM(next);
	}
    }

    if (do_tailcallopt &&
	(IS_INSN_ID(iobj, send) ||
	 IS_INSN_ID(iobj, opt_aref_with) ||
	 IS_INSN_ID(iobj, opt_aset_with) ||
	 IS_INSN_ID(iobj, invokesuper))) {
	/*
	 *  send ...
	 *  leave
	 * =>
	 *  send ..., ... | VM_CALL_TAILCALL, ...
	 *  leave # unreachable
	 */
	INSN *piobj = NULL;
	if (iobj->link.next) {
	    LINK_ELEMENT *next = iobj->link.next;
	    do {
		if (!IS_INSN(next)) {
		    next = next->next;
		    continue;
		}
		switch (INSN_OF(next)) {
		  case BIN(nop):
		  /*case BIN(trace):*/
		    next = next->next;
		    break;
		  case BIN(jump):
		    /* if cond
		     *   return tailcall
		     * end
		     */
		    next = get_destination_insn((INSN *)next);
		    break;
		  case BIN(leave):
		    piobj = iobj;
		  default:
		    next = NULL;
		    break;
		}
	    } while (next);
	}

	if (piobj) {
	    struct rb_call_info *ci = (struct rb_call_info *)piobj->operands[0];
	    if (IS_INSN_ID(piobj, send) || IS_INSN_ID(piobj, invokesuper)) {
		if (piobj->operands[2] == 0) { /* no blockiseq */
		    ci->flag |= VM_CALL_TAILCALL;
		}
	    }
	    else {
		ci->flag |= VM_CALL_TAILCALL;
	    }
	}
    }

    #define IS_TRACE_LINE(insn) \
	(IS_INSN_ID(insn, trace) && \
	 OPERAND_AT(insn, 0) == INT2FIX(RUBY_EVENT_LINE))
    if (IS_TRACE_LINE(iobj) && iobj->link.prev && IS_INSN(iobj->link.prev)) {
	INSN *piobj = (INSN *)iobj->link.prev;
	if (IS_TRACE_LINE(piobj)) {
	    REMOVE_ELEM(iobj->link.prev);
	}
    }

    return COMPILE_OK;
}

static int
insn_set_specialized_instruction(rb_iseq_t *iseq, INSN *iobj, int insn_id)
{
    iobj->insn_id = insn_id;
    iobj->operand_size = insn_len(insn_id) - 1;

    if (insn_id == BIN(opt_neq)) {
	VALUE *old_operands = iobj->operands;
	iobj->operand_size = 4;
	iobj->operands = (VALUE *)compile_data_alloc(iseq, iobj->operand_size * sizeof(VALUE));
	iobj->operands[0] = old_operands[0];
	iobj->operands[1] = Qfalse; /* CALL_CACHE */
	iobj->operands[2] = (VALUE)new_callinfo(iseq, idEq, 1, 0, NULL, FALSE);
	iobj->operands[3] = Qfalse; /* CALL_CACHE */
    }

    return COMPILE_OK;
}

static int
iseq_specialized_instruction(rb_iseq_t *iseq, INSN *iobj)
{
    if (IS_INSN_ID(iobj, newarray) && iobj->link.next &&
	IS_INSN(iobj->link.next)) {
	/*
	 *   [a, b, ...].max/min -> a, b, c, opt_newarray_max/min
	 */
	INSN *niobj = (INSN *)iobj->link.next;
	if (IS_INSN_ID(niobj, send)) {
	    struct rb_call_info *ci = (struct rb_call_info *)OPERAND_AT(niobj, 0);
	    if ((ci->flag & VM_CALL_ARGS_SIMPLE) && ci->orig_argc == 0) {
		switch (ci->mid) {
		  case idMax:
		    iobj->insn_id = BIN(opt_newarray_max);
		    REMOVE_ELEM(&niobj->link);
		    return COMPILE_OK;
		  case idMin:
		    iobj->insn_id = BIN(opt_newarray_min);
		    REMOVE_ELEM(&niobj->link);
		    return COMPILE_OK;
		}
	    }
	}
    }

    if (IS_INSN_ID(iobj, send)) {
	struct rb_call_info *ci = (struct rb_call_info *)OPERAND_AT(iobj, 0);
	const rb_iseq_t *blockiseq = (rb_iseq_t *)OPERAND_AT(iobj, 2);

#define SP_INSN(opt) insn_set_specialized_instruction(iseq, iobj, BIN(opt_##opt))
	if (ci->flag & VM_CALL_ARGS_SIMPLE) {
	    switch (ci->orig_argc) {
	      case 0:
		switch (ci->mid) {
		  case idLength: SP_INSN(length); return COMPILE_OK;
		  case idSize:	 SP_INSN(size);	  return COMPILE_OK;
		  case idEmptyP: SP_INSN(empty_p);return COMPILE_OK;
		  case idSucc:	 SP_INSN(succ);	  return COMPILE_OK;
		  case idNot:	 SP_INSN(not);	  return COMPILE_OK;
		}
		break;
	      case 1:
		switch (ci->mid) {
		  case idPLUS:	 SP_INSN(plus);	  return COMPILE_OK;
		  case idMINUS:	 SP_INSN(minus);  return COMPILE_OK;
		  case idMULT:	 SP_INSN(mult);	  return COMPILE_OK;
		  case idDIV:	 SP_INSN(div);	  return COMPILE_OK;
		  case idMOD:	 SP_INSN(mod);	  return COMPILE_OK;
		  case idEq:	 SP_INSN(eq);	  return COMPILE_OK;
		  case idNeq:	 SP_INSN(neq);	  return COMPILE_OK;
		  case idLT:	 SP_INSN(lt);	  return COMPILE_OK;
		  case idLE:	 SP_INSN(le);	  return COMPILE_OK;
		  case idGT:	 SP_INSN(gt);	  return COMPILE_OK;
		  case idGE:	 SP_INSN(ge);	  return COMPILE_OK;
		  case idLTLT:	 SP_INSN(ltlt);	  return COMPILE_OK;
		  case idAREF:	 SP_INSN(aref);	  return COMPILE_OK;
		}
		break;
	      case 2:
		switch (ci->mid) {
		  case idASET:	 SP_INSN(aset);	  return COMPILE_OK;
		}
		break;
	    }
	}

	if ((ci->flag & VM_CALL_ARGS_BLOCKARG) == 0 && blockiseq == NULL) {
	    iobj->insn_id = BIN(opt_send_without_block);
	    iobj->operand_size = insn_len(iobj->insn_id) - 1;
	}
    }
#undef SP_INSN

    return COMPILE_OK;
}

static inline int
tailcallable_p(rb_iseq_t *iseq)
{
    switch (iseq->body->type) {
      case ISEQ_TYPE_TOP:
      case ISEQ_TYPE_EVAL:
      case ISEQ_TYPE_MAIN:
	/* not tail callable because cfp will be over popped */
      case ISEQ_TYPE_RESCUE:
      case ISEQ_TYPE_ENSURE:
	/* rescue block can't tail call because of errinfo */
	return FALSE;
      default:
	return TRUE;
    }
}

static int
iseq_optimize(rb_iseq_t *iseq, LINK_ANCHOR *const anchor)
{
    LINK_ELEMENT *list;
    const int do_peepholeopt = ISEQ_COMPILE_DATA(iseq)->option->peephole_optimization;
    const int do_tailcallopt = tailcallable_p(iseq) &&
	ISEQ_COMPILE_DATA(iseq)->option->tailcall_optimization;
    const int do_si = ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction;
    const int do_ou = ISEQ_COMPILE_DATA(iseq)->option->operands_unification;
    int rescue_level = 0;
    int tailcallopt = do_tailcallopt;

    list = FIRST_ELEMENT(anchor);

    while (list) {
	if (IS_INSN(list)) {
	    if (do_peepholeopt) {
		iseq_peephole_optimize(iseq, list, tailcallopt);
	    }
	    if (do_si) {
		iseq_specialized_instruction(iseq, (INSN *)list);
	    }
	    if (do_ou) {
		insn_operands_unification((INSN *)list);
	    }
	}
	if (IS_LABEL(list)) {
	    switch (((LABEL *)list)->rescued) {
	      case LABEL_RESCUE_BEG:
		rescue_level++;
		tailcallopt = FALSE;
		break;
	      case LABEL_RESCUE_END:
		if (!--rescue_level) tailcallopt = do_tailcallopt;
		break;
	    }
	}
	list = list->next;
    }
    return COMPILE_OK;
}

#if OPT_INSTRUCTIONS_UNIFICATION
static INSN *
new_unified_insn(rb_iseq_t *iseq,
		 int insn_id, int size, LINK_ELEMENT *seq_list)
{
    INSN *iobj = 0;
    LINK_ELEMENT *list = seq_list;
    int i, argc = 0;
    VALUE *operands = 0, *ptr = 0;


    /* count argc */
    for (i = 0; i < size; i++) {
	iobj = (INSN *)list;
	argc += iobj->operand_size;
	list = list->next;
    }

    if (argc > 0) {
	ptr = operands =
	    (VALUE *)compile_data_alloc(iseq, sizeof(VALUE) * argc);
    }

    /* copy operands */
    list = seq_list;
    for (i = 0; i < size; i++) {
	iobj = (INSN *)list;
	MEMCPY(ptr, iobj->operands, VALUE, iobj->operand_size);
	ptr += iobj->operand_size;
	list = list->next;
    }

    return new_insn_core(iseq, iobj->line_no, insn_id, argc, operands);
}
#endif

/*
 * This scheme can get more performance if do this optimize with
 * label address resolving.
 * It's future work (if compile time was bottle neck).
 */
static int
iseq_insns_unification(rb_iseq_t *iseq, LINK_ANCHOR *const anchor)
{
#if OPT_INSTRUCTIONS_UNIFICATION
    LINK_ELEMENT *list;
    INSN *iobj, *niobj;
    int id, k;
    intptr_t j;

    list = FIRST_ELEMENT(anchor);
    while (list) {
	if (IS_INSN(list)) {
	    iobj = (INSN *)list;
	    id = iobj->insn_id;
	    if (unified_insns_data[id] != 0) {
		const int *const *entry = unified_insns_data[id];
		for (j = 1; j < (intptr_t)entry[0]; j++) {
		    const int *unified = entry[j];
		    LINK_ELEMENT *li = list->next;
		    for (k = 2; k < unified[1]; k++) {
			if (!IS_INSN(li) ||
			    ((INSN *)li)->insn_id != unified[k]) {
			    goto miss;
			}
			li = li->next;
		    }
		    /* matched */
		    niobj =
			new_unified_insn(iseq, unified[0], unified[1] - 1,
					 list);

		    /* insert to list */
		    niobj->link.prev = (LINK_ELEMENT *)iobj->link.prev;
		    niobj->link.next = li;
		    if (li) {
			li->prev = (LINK_ELEMENT *)niobj;
		    }

		    list->prev->next = (LINK_ELEMENT *)niobj;
		    list = (LINK_ELEMENT *)niobj;
		    break;
		  miss:;
		}
	    }
	}
	list = list->next;
    }
#endif
    return COMPILE_OK;
}

#if OPT_STACK_CACHING

#define SC_INSN(insn, stat) sc_insn_info[(insn)][(stat)]
#define SC_NEXT(insn)       sc_insn_next[(insn)]

#include "opt_sc.inc"

static int
insn_set_sc_state(rb_iseq_t *iseq, INSN *iobj, int state)
{
    int nstate;
    int insn_id;

    insn_id = iobj->insn_id;
    iobj->insn_id = SC_INSN(insn_id, state);
    nstate = SC_NEXT(iobj->insn_id);

    if (insn_id == BIN(jump) ||
	insn_id == BIN(branchif) || insn_id == BIN(branchunless)) {
	LABEL *lobj = (LABEL *)OPERAND_AT(iobj, 0);

	if (lobj->sc_state != 0) {
	    if (lobj->sc_state != nstate) {
		dump_disasm_list((LINK_ELEMENT *)iobj);
		dump_disasm_list((LINK_ELEMENT *)lobj);
		printf("\n-- %d, %d\n", lobj->sc_state, nstate);
		COMPILE_ERROR(iseq, iobj->line_no,
			      "insn_set_sc_state error\n");
		return COMPILE_NG;
	    }
	}
	else {
	    lobj->sc_state = nstate;
	}
	if (insn_id == BIN(jump)) {
	    nstate = SCS_XX;
	}
    }
    else if (insn_id == BIN(leave)) {
	nstate = SCS_XX;
    }

    return nstate;
}

static int
label_set_sc_state(LABEL *lobj, int state)
{
    if (lobj->sc_state != 0) {
	if (lobj->sc_state != state) {
	    state = lobj->sc_state;
	}
    }
    else {
	lobj->sc_state = state;
    }

    return state;
}


#endif

static int
iseq_set_sequence_stackcaching(rb_iseq_t *iseq, LINK_ANCHOR *const anchor)
{
#if OPT_STACK_CACHING
    LINK_ELEMENT *list;
    int state, insn_id;

    /* initialize */
    state = SCS_XX;
    list = FIRST_ELEMENT(anchor);
    /* dump_disasm_list(list); */

    /* for each list element */
    while (list) {
      redo_point:
	switch (list->type) {
	  case ISEQ_ELEMENT_INSN:
	    {
		INSN *iobj = (INSN *)list;
		insn_id = iobj->insn_id;

		/* dump_disasm_list(list); */

		switch (insn_id) {
		  case BIN(nop):
		    {
			/* exception merge point */
			if (state != SCS_AX) {
			    INSN *rpobj =
				new_insn_body(iseq, 0, BIN(reput), 0);

			    /* replace this insn */
			    REPLACE_ELEM(list, (LINK_ELEMENT *)rpobj);
			    list = (LINK_ELEMENT *)rpobj;
			    goto redo_point;
			}
			break;
		    }
		  case BIN(swap):
		    {
			if (state == SCS_AB || state == SCS_BA) {
			    state = (state == SCS_AB ? SCS_BA : SCS_AB);

			    REMOVE_ELEM(list);
			    list = list->next;
			    goto redo_point;
			}
			break;
		    }
		  case BIN(pop):
		    {
			switch (state) {
			  case SCS_AX:
			  case SCS_BX:
			    state = SCS_XX;
			    break;
			  case SCS_AB:
			    state = SCS_AX;
			    break;
			  case SCS_BA:
			    state = SCS_BX;
			    break;
			  case SCS_XX:
			    goto normal_insn;
			  default:
			    COMPILE_ERROR(iseq, iobj->line_no,
					  "unreachable");
			    return COMPILE_NG;
			}
			/* remove useless pop */
			REMOVE_ELEM(list);
			list = list->next;
			goto redo_point;
		    }
		  default:;
		    /* none */
		}		/* end of switch */
	      normal_insn:
		state = insn_set_sc_state(iseq, iobj, state);
		break;
	    }
	  case ISEQ_ELEMENT_LABEL:
	    {
		LABEL *lobj;
		lobj = (LABEL *)list;

		state = label_set_sc_state(lobj, state);
	    }
	  default:
	    break;
	}
	list = list->next;
    }
#endif
    return COMPILE_OK;
}

static int
compile_dstr_fragments(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *node, int *cntp)
{
    NODE *list = node->nd_next;
    VALUE lit = node->nd_lit;
    LINK_ELEMENT *first_lit = 0;
    int cnt = 0;

    debugp_param("nd_lit", lit);
    if (!NIL_P(lit)) {
	cnt++;
	if (!RB_TYPE_P(lit, T_STRING)) {
	    compile_bug(ERROR_ARGS "dstr: must be string: %s",
			rb_builtin_type_name(TYPE(lit)));
	}
	lit = node->nd_lit = rb_fstring(lit);
	ADD_INSN1(ret, nd_line(node), putobject, lit);
	if (RSTRING_LEN(lit) == 0) first_lit = LAST_ELEMENT(ret);
    }

    while (list) {
	node = list->nd_head;
	if (nd_type(node) == NODE_STR) {
	    node->nd_lit = rb_fstring(node->nd_lit);
	    ADD_INSN1(ret, nd_line(node), putobject, node->nd_lit);
	    lit = Qnil;
	}
	else {
	    COMPILE(ret, "each string", node);
	}
	cnt++;
	list = list->nd_next;
    }
    if (NIL_P(lit) && first_lit) {
	REMOVE_ELEM(first_lit);
	--cnt;
    }
    *cntp = cnt;

    return COMPILE_OK;
}

static int
compile_dstr(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *node)
{
    int cnt;
    compile_dstr_fragments(iseq, ret, node, &cnt);
    ADD_INSN1(ret, nd_line(node), concatstrings, INT2FIX(cnt));
    return COMPILE_OK;
}

static int
compile_dregx(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *node)
{
    int cnt;
    compile_dstr_fragments(iseq, ret, node, &cnt);
    ADD_INSN2(ret, nd_line(node), toregexp, INT2FIX(node->nd_cflag), INT2FIX(cnt));
    return COMPILE_OK;
}

static int
compile_flip_flop(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *node, int again,
		  LABEL *then_label, LABEL *else_label)
{
    const int line = nd_line(node);
    LABEL *lend = NEW_LABEL(line);
    rb_num_t cnt = ISEQ_FLIP_CNT_INCREMENT(iseq->body->local_iseq)
	+ VM_SVAR_FLIPFLOP_START;
    VALUE key = INT2FIX(cnt);

    ADD_INSN2(ret, line, getspecial, key, INT2FIX(0));
    ADD_INSNL(ret, line, branchif, lend);

    /* *flip == 0 */
    COMPILE(ret, "flip2 beg", node->nd_beg);
    ADD_INSNL(ret, line, branchunless, else_label);
    ADD_INSN1(ret, line, putobject, Qtrue);
    ADD_INSN1(ret, line, setspecial, key);
    if (!again) {
	ADD_INSNL(ret, line, jump, then_label);
    }

    /* *flip == 1 */
    ADD_LABEL(ret, lend);
    COMPILE(ret, "flip2 end", node->nd_end);
    ADD_INSNL(ret, line, branchunless, then_label);
    ADD_INSN1(ret, line, putobject, Qfalse);
    ADD_INSN1(ret, line, setspecial, key);
    ADD_INSNL(ret, line, jump, then_label);

    return COMPILE_OK;
}

static int
compile_branch_condition(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *cond,
			 LABEL *then_label, LABEL *else_label)
{
    switch (nd_type(cond)) {
      case NODE_AND:
	{
	    LABEL *label = NEW_LABEL(nd_line(cond));
	    compile_branch_condition(iseq, ret, cond->nd_1st, label,
				     else_label);
	    ADD_LABEL(ret, label);
	    compile_branch_condition(iseq, ret, cond->nd_2nd, then_label,
				     else_label);
	    break;
	}
      case NODE_OR:
	{
	    LABEL *label = NEW_LABEL(nd_line(cond));
	    compile_branch_condition(iseq, ret, cond->nd_1st, then_label,
				     label);
	    ADD_LABEL(ret, label);
	    compile_branch_condition(iseq, ret, cond->nd_2nd, then_label,
				     else_label);
	    break;
	}
      case NODE_LIT:		/* NODE_LIT is always not true */
      case NODE_TRUE:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_XSTR:
      case NODE_DXSTR:
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
      case NODE_DSYM:
      case NODE_ARRAY:
      case NODE_ZARRAY:
      case NODE_HASH:
      case NODE_LAMBDA:
      case NODE_DEFN:
      case NODE_DEFS:
	/* printf("useless condition eliminate (%s)\n",  ruby_node_name(nd_type(cond))); */
	ADD_INSNL(ret, nd_line(cond), jump, then_label);
	break;
      case NODE_FALSE:
      case NODE_NIL:
	/* printf("useless condition eliminate (%s)\n", ruby_node_name(nd_type(cond))); */
	ADD_INSNL(ret, nd_line(cond), jump, else_label);
	break;
      case NODE_FLIP2:
	compile_flip_flop(iseq, ret, cond, TRUE, then_label, else_label);
	break;
      case NODE_FLIP3:
	compile_flip_flop(iseq, ret, cond, FALSE, then_label, else_label);
	break;
      default:
	COMPILE(ret, "branch condition", cond);
	ADD_INSNL(ret, nd_line(cond), branchunless, else_label);
	ADD_INSNL(ret, nd_line(cond), jump, then_label);
	break;
    }
    return COMPILE_OK;
}

static int
compile_array_keyword_arg(rb_iseq_t *iseq, LINK_ANCHOR *const ret,
			  const NODE *const root_node,
			  struct rb_call_info_kw_arg **const kw_arg_ptr)
{
    if (kw_arg_ptr == NULL) return FALSE;

    if (nd_type(root_node) == NODE_HASH && root_node->nd_head && nd_type(root_node->nd_head) == NODE_ARRAY) {
	NODE *node = root_node->nd_head;

	while (node) {
	    NODE *key_node = node->nd_head;

	    assert(nd_type(node) == NODE_ARRAY);
	    if (key_node && nd_type(key_node) == NODE_LIT && RB_TYPE_P(key_node->nd_lit, T_SYMBOL)) {
		/* can be keywords */
	    }
	    else {
		return FALSE;
	    }
	    node = node->nd_next; /* skip value node */
	    node = node->nd_next;
	}

	/* may be keywords */
	node = root_node->nd_head;
	{
	    int len = (int)node->nd_alen / 2;
	    struct rb_call_info_kw_arg *kw_arg  = (struct rb_call_info_kw_arg *)ruby_xmalloc(sizeof(struct rb_call_info_kw_arg) + sizeof(VALUE) * (len - 1));
	    VALUE *keywords = kw_arg->keywords;
	    int i = 0;
	    kw_arg->keyword_len = len;

	    *kw_arg_ptr = kw_arg;

	    for (i=0; node != NULL; i++, node = node->nd_next->nd_next) {
		NODE *key_node = node->nd_head;
		NODE *val_node = node->nd_next->nd_head;
		keywords[i] = key_node->nd_lit;
		COMPILE(ret, "keyword values", val_node);
	    }
	    assert(i == len);
	    return TRUE;
	}
    }
    return FALSE;
}

enum compile_array_type_t {
    COMPILE_ARRAY_TYPE_ARRAY,
    COMPILE_ARRAY_TYPE_HASH,
    COMPILE_ARRAY_TYPE_ARGS
};

static inline int
static_literal_node_p(NODE *node)
{
    node = node->nd_head;
    switch (nd_type(node)) {
      case NODE_LIT:
      case NODE_NIL:
      case NODE_TRUE:
      case NODE_FALSE:
	return TRUE;
      default:
	return FALSE;
    }
}

static inline VALUE
static_literal_value(NODE *node)
{
    node = node->nd_head;
    switch (nd_type(node)) {
      case NODE_NIL:
	return Qnil;
      case NODE_TRUE:
	return Qtrue;
      case NODE_FALSE:
	return Qfalse;
      default:
	return node->nd_lit;
    }
}

static int
compile_array_(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE* node_root,
	       enum compile_array_type_t type, struct rb_call_info_kw_arg **keywords_ptr, int popped)
{
    NODE *node = node_root;
    int line = (int)nd_line(node);
    int len = 0;

    if (nd_type(node) == NODE_ZARRAY) {
	if (!popped) {
	    switch (type) {
	      case COMPILE_ARRAY_TYPE_ARRAY: ADD_INSN1(ret, line, newarray, INT2FIX(0)); break;
	      case COMPILE_ARRAY_TYPE_HASH: ADD_INSN1(ret, line, newhash, INT2FIX(0)); break;
	      case COMPILE_ARRAY_TYPE_ARGS: /* do nothing */ break;
	    }
	}
    }
    else {
	int opt_p = 1;
	int first = 1, i;

	while (node) {
	    NODE *start_node = node, *end_node;
	    NODE *kw = 0;
	    const int max = 0x100;
	    DECL_ANCHOR(anchor);
	    INIT_ANCHOR(anchor);

	    for (i=0; i<max && node; i++, len++, node = node->nd_next) {
		if (CPDEBUG > 0) {
		    EXPECT_NODE("compile_array", node, NODE_ARRAY);
		}

		if (type != COMPILE_ARRAY_TYPE_ARRAY && !node->nd_head) {
		    kw = node->nd_next;
		    node = 0;
		    if (kw) {
			opt_p = 0;
			node = kw->nd_next;
			kw = kw->nd_head;
		    }
		    break;
		}
		if (opt_p && !static_literal_node_p(node)) {
		    opt_p = 0;
		}

		if (type == COMPILE_ARRAY_TYPE_ARGS && node->nd_next == NULL /* last node */ && compile_array_keyword_arg(iseq, anchor, node->nd_head, keywords_ptr)) {
		    len--;
		}
		else {
		    COMPILE_(anchor, "array element", node->nd_head, popped);
		}
	    }

	    if (opt_p && type != COMPILE_ARRAY_TYPE_ARGS) {
		if (!popped) {
		    VALUE ary = rb_ary_tmp_new(i);

		    end_node = node;
		    node = start_node;

		    while (node != end_node) {
			rb_ary_push(ary, static_literal_value(node));
			node = node->nd_next;
		    }
		    while (node && node->nd_next &&
			   static_literal_node_p(node) &&
			   static_literal_node_p(node->nd_next)) {
			VALUE elem[2];
			elem[0] = static_literal_value(node);
			elem[1] = static_literal_value(node->nd_next);
			rb_ary_cat(ary, elem, 2);
			node = node->nd_next->nd_next;
			len++;
		    }

		    OBJ_FREEZE(ary);

		    iseq_add_mark_object_compile_time(iseq, ary);

		    if (first) {
			first = 0;
			if (type == COMPILE_ARRAY_TYPE_ARRAY) {
			    ADD_INSN1(ret, line, duparray, ary);
			}
			else { /* COMPILE_ARRAY_TYPE_HASH */
			    ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
			    ADD_INSN1(ret, line, putobject, ary);
			    ADD_SEND(ret, line, id_core_hash_from_ary, INT2FIX(1));
			}
		    }
		    else {
			if (type == COMPILE_ARRAY_TYPE_ARRAY) {
			    ADD_INSN1(ret, line, putobject, ary);
			    ADD_INSN(ret, line, concatarray);
			}
			else {
#if 0
			    ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
			    ADD_INSN1(ret, line, putobject, ary);
			    ADD_SEND(ret, line, id_core_hash_merge_ary, INT2FIX(1));
			    /* wrong number of arguments -----------------------^ */
#else
			    compile_bug(ERROR_ARGS "core#hash_merge_ary");
#endif
			}
		    }
		}
	    }
	    else {
		if (!popped) {
		    switch (type) {
		      case COMPILE_ARRAY_TYPE_ARRAY:
			ADD_INSN1(anchor, line, newarray, INT2FIX(i));

			if (first) {
			    first = 0;
			}
			else {
			    ADD_INSN(anchor, line, concatarray);
			}

			APPEND_LIST(ret, anchor);
			break;
		      case COMPILE_ARRAY_TYPE_HASH:
			if (i > 0) {
			    if (first) {
				ADD_INSN1(anchor, line, newhash, INT2FIX(i));
				APPEND_LIST(ret, anchor);
			    }
			    else {
				ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
				ADD_INSN(ret, line, swap);
				APPEND_LIST(ret, anchor);
				ADD_SEND(ret, line, id_core_hash_merge_ptr, INT2FIX(i + 1));
			    }
			}
			if (kw) {
			    VALUE nhash = (i > 0 || !first) ? INT2FIX(2) : INT2FIX(1);
			    ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
			    if (i > 0 || !first) ADD_INSN(ret, line, swap);
			    COMPILE(ret, "keyword splat", kw);
			    ADD_SEND(ret, line, id_core_hash_merge_kwd, nhash);
			    if (nhash == INT2FIX(1)) ADD_SEND(ret, line, rb_intern("dup"), INT2FIX(0));
			}
			first = 0;
			break;
		      case COMPILE_ARRAY_TYPE_ARGS:
			APPEND_LIST(ret, anchor);
			break;
		    }
		}
		else {
		    /* popped */
		    APPEND_LIST(ret, anchor);
		}
	    }
	}
    }
    return len;
}

static VALUE
compile_array(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE* node_root, enum compile_array_type_t type)
{
    return compile_array_(iseq, ret, node_root, type, NULL, 0);
}

static VALUE
case_when_optimizable_literal(NODE *node)
{
    switch (nd_type(node)) {
      case NODE_LIT: {
	VALUE v = node->nd_lit;
	double ival;
	if (RB_TYPE_P(v, T_FLOAT) &&
	    modf(RFLOAT_VALUE(v), &ival) == 0.0) {
	    return FIXABLE(ival) ? LONG2FIX((long)ival) : rb_dbl2big(ival);
	}
	if (SYMBOL_P(v) || rb_obj_is_kind_of(v, rb_cNumeric)) {
	    return v;
	}
	break;
      }
      case NODE_NIL:
	return Qnil;
      case NODE_TRUE:
	return Qtrue;
      case NODE_FALSE:
	return Qfalse;
      case NODE_STR:
	return node->nd_lit = rb_fstring(node->nd_lit);
    }
    return Qundef;
}

static int
when_vals(rb_iseq_t *iseq, LINK_ANCHOR *const cond_seq, NODE *vals,
	  LABEL *l1, int only_special_literals, VALUE literals)
{
    while (vals) {
	NODE* val = vals->nd_head;
	VALUE lit = case_when_optimizable_literal(val);

	if (lit == Qundef) {
	    only_special_literals = 0;
	}
	else {
	    if (rb_hash_lookup(literals, lit) != Qnil) {
		rb_compile_warning(ruby_sourcefile, nd_line(val),
				   "duplicated when clause is ignored");
	    }
	    else {
		rb_hash_aset(literals, lit, (VALUE)(l1) | 1);
	    }
	}

	ADD_INSN(cond_seq, nd_line(val), dup); /* dup target */

	if (nd_type(val) == NODE_STR) {
	    val->nd_lit = rb_fstring(val->nd_lit);
	    debugp_param("nd_lit", val->nd_lit);
	    ADD_INSN1(cond_seq, nd_line(val), putobject, val->nd_lit);
	}
	else {
	    COMPILE(cond_seq, "when cond", val);
	}

	ADD_INSN1(cond_seq, nd_line(vals), checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_CASE));
	ADD_INSNL(cond_seq, nd_line(val), branchif, l1);
	vals = vals->nd_next;
    }
    return only_special_literals;
}

static int
compile_massign_lhs(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_ATTRASGN: {
	INSN *iobj;
	struct rb_call_info *ci;
	VALUE dupidx;
	int line = nd_line(node);

	COMPILE_POPPED(ret, "masgn lhs (NODE_ATTRASGN)", node);

	iobj = (INSN *)get_prev_insn((INSN *)LAST_ELEMENT(ret)); /* send insn */
	ci = (struct rb_call_info *)iobj->operands[0];
	ci->orig_argc += 1;
	dupidx = INT2FIX(ci->orig_argc);

	INSERT_BEFORE_INSN1(iobj, line, topn, dupidx);
	if (ci->flag & VM_CALL_ARGS_SPLAT) {
	    --ci->orig_argc;
	    INSERT_BEFORE_INSN1(iobj, line, newarray, INT2FIX(1));
	    INSERT_BEFORE_INSN(iobj, line, concatarray);
	}
	ADD_INSN(ret, line, pop);	/* result */
	break;
      }
      case NODE_MASGN: {
	DECL_ANCHOR(anchor);
	INIT_ANCHOR(anchor);
	COMPILE_POPPED(anchor, "nest masgn lhs", node);
	REMOVE_ELEM(FIRST_ELEMENT(anchor));
	ADD_SEQ(ret, anchor);
	break;
      }
      default: {
	DECL_ANCHOR(anchor);
	INIT_ANCHOR(anchor);
	COMPILE_POPPED(anchor, "masgn lhs", node);
	REMOVE_ELEM(FIRST_ELEMENT(anchor));
	ADD_SEQ(ret, anchor);
      }
    }

    return COMPILE_OK;
}

static void
compile_massign_opt_lhs(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *lhsn)
{
    if (lhsn) {
	compile_massign_opt_lhs(iseq, ret, lhsn->nd_next);
	compile_massign_lhs(iseq, ret, lhsn->nd_head);
    }
}

static int
compile_massign_opt(rb_iseq_t *iseq, LINK_ANCHOR *const ret,
		    NODE *rhsn, NODE *orig_lhsn)
{
    VALUE mem[64];
    const int memsize = numberof(mem);
    int memindex = 0;
    int llen = 0, rlen = 0;
    int i;
    NODE *lhsn = orig_lhsn;

#define MEMORY(v) { \
    int i; \
    if (memindex == memsize) return 0; \
    for (i=0; i<memindex; i++) { \
	if (mem[i] == (v)) return 0; \
    } \
    mem[memindex++] = (v); \
}

    if (rhsn == 0 || nd_type(rhsn) != NODE_ARRAY) {
	return 0;
    }

    while (lhsn) {
	NODE *ln = lhsn->nd_head;
	switch (nd_type(ln)) {
	  case NODE_LASGN:
	    MEMORY(ln->nd_vid);
	    break;
	  case NODE_DASGN:
	  case NODE_DASGN_CURR:
	  case NODE_IASGN:
	  case NODE_IASGN2:
	  case NODE_CVASGN:
	    MEMORY(ln->nd_vid);
	    break;
	  default:
	    return 0;
	}
	lhsn = lhsn->nd_next;
	llen++;
    }

    while (rhsn) {
	if (llen <= rlen) {
	    COMPILE_POPPED(ret, "masgn val (popped)", rhsn->nd_head);
	}
	else {
	    COMPILE(ret, "masgn val", rhsn->nd_head);
	}
	rhsn = rhsn->nd_next;
	rlen++;
    }

    if (llen > rlen) {
	for (i=0; i<llen-rlen; i++) {
	    ADD_INSN(ret, nd_line(orig_lhsn), putnil);
	}
    }

    compile_massign_opt_lhs(iseq, ret, orig_lhsn);
    return 1;
}

static void
adjust_stack(rb_iseq_t *iseq, LINK_ANCHOR *const ret, int line, int rlen, int llen)
{
    if (rlen < llen) {
	do {ADD_INSN(ret, line, putnil);} while (++rlen < llen);
    }
    else if (rlen > llen) {
	do {ADD_INSN(ret, line, pop);} while (--rlen > llen);
    }
}

static int
compile_massign(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *node, int popped)
{
    NODE *rhsn = node->nd_value;
    NODE *splatn = node->nd_args;
    NODE *lhsn = node->nd_head;
    int lhs_splat = (splatn && (VALUE)splatn != (VALUE)-1) ? 1 : 0;

    if (!popped || splatn || !compile_massign_opt(iseq, ret, rhsn, lhsn)) {
	int llen = 0;
	int expand = 1;
	DECL_ANCHOR(lhsseq);

	INIT_ANCHOR(lhsseq);

	while (lhsn) {
	    compile_massign_lhs(iseq, lhsseq, lhsn->nd_head);
	    llen += 1;
	    lhsn = lhsn->nd_next;
	}

	COMPILE(ret, "normal masgn rhs", rhsn);

	if (!popped) {
	    ADD_INSN(ret, nd_line(node), dup);
	}
	else if (!lhs_splat) {
	    INSN *last = (INSN*)ret->last;
	    if (IS_INSN(&last->link) &&
		IS_INSN_ID(last, newarray) &&
		last->operand_size == 1) {
		int rlen = FIX2INT(OPERAND_AT(last, 0));
		/* special case: assign to aset or attrset */
		if (llen == 2) {
		    POP_ELEMENT(ret);
		    adjust_stack(iseq, ret, nd_line(node), rlen, llen);
		    ADD_INSN(ret, nd_line(node), swap);
		    expand = 0;
		}
		else if (llen > 2 && llen != rlen) {
		    POP_ELEMENT(ret);
		    adjust_stack(iseq, ret, nd_line(node), rlen, llen);
		    ADD_INSN1(ret, nd_line(node), reverse, INT2FIX(llen));
		    expand = 0;
		}
		else if (llen > 2) {
		    last->insn_id = BIN(reverse);
		    expand = 0;
		}
	    }
	}
	if (expand) {
	    ADD_INSN2(ret, nd_line(node), expandarray,
		      INT2FIX(llen), INT2FIX(lhs_splat));
	}
	ADD_SEQ(ret, lhsseq);

	if (lhs_splat) {
	    if (nd_type(splatn) == NODE_POSTARG) {
		/*a, b, *r, p1, p2 */
		NODE *postn = splatn->nd_2nd;
		NODE *restn = splatn->nd_1st;
		int num = (int)postn->nd_alen;
		int flag = 0x02 | (((VALUE)restn == (VALUE)-1) ? 0x00 : 0x01);

		ADD_INSN2(ret, nd_line(splatn), expandarray,
			  INT2FIX(num), INT2FIX(flag));

		if ((VALUE)restn != (VALUE)-1) {
		    compile_massign_lhs(iseq, ret, restn);
		}
		while (postn) {
		    compile_massign_lhs(iseq, ret, postn->nd_head);
		    postn = postn->nd_next;
		}
	    }
	    else {
		/* a, b, *r */
		compile_massign_lhs(iseq, ret, splatn);
	    }
	}
    }
    return COMPILE_OK;
}

static int
compile_colon2(rb_iseq_t *iseq, NODE *node,
	       LINK_ANCHOR *const pref, LINK_ANCHOR *const body)
{
    switch (nd_type(node)) {
      case NODE_CONST:
	debugi("compile_colon2 - colon", node->nd_vid);
	ADD_INSN1(body, nd_line(node), getconstant, ID2SYM(node->nd_vid));
	break;
      case NODE_COLON3:
	debugi("compile_colon2 - colon3", node->nd_mid);
	ADD_INSN(body, nd_line(node), pop);
	ADD_INSN1(body, nd_line(node), putobject, rb_cObject);
	ADD_INSN1(body, nd_line(node), getconstant, ID2SYM(node->nd_mid));
	break;
      case NODE_COLON2:
	compile_colon2(iseq, node->nd_head, pref, body);
	debugi("compile_colon2 - colon2", node->nd_mid);
	ADD_INSN1(body, nd_line(node), getconstant, ID2SYM(node->nd_mid));
	break;
      default:
	COMPILE(pref, "const colon2 prefix", node);
	break;
    }
    return COMPILE_OK;
}

static VALUE
compile_cpath(LINK_ANCHOR *const ret, rb_iseq_t *iseq, NODE *cpath)
{
    if (nd_type(cpath) == NODE_COLON3) {
	/* toplevel class ::Foo */
	ADD_INSN1(ret, nd_line(cpath), putobject, rb_cObject);
	return Qfalse;
    }
    else if (cpath->nd_head) {
	/* Bar::Foo */
	COMPILE(ret, "nd_else->nd_head", cpath->nd_head);
	return Qfalse;
    }
    else {
	/* class at cbase Foo */
	ADD_INSN1(ret, nd_line(cpath), putspecialobject,
		  INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
	return Qtrue;
    }
}

#define private_recv_p(node) (nd_type((node)->nd_recv) == NODE_SELF)

#define defined_expr defined_expr0
static int
defined_expr(rb_iseq_t *iseq, LINK_ANCHOR *const ret,
	     NODE *node, LABEL **lfinish, VALUE needstr)
{
    enum defined_type expr_type = 0;
    enum node_type type;

    switch (type = nd_type(node)) {

	/* easy literals */
      case NODE_NIL:
	expr_type = DEFINED_NIL;
	break;
      case NODE_SELF:
	expr_type = DEFINED_SELF;
	break;
      case NODE_TRUE:
	expr_type = DEFINED_TRUE;
	break;
      case NODE_FALSE:
	expr_type = DEFINED_FALSE;
	break;

      case NODE_ARRAY:{
	NODE *vals = node;

	do {
	    defined_expr(iseq, ret, vals->nd_head, lfinish, Qfalse);

	    if (!lfinish[1]) {
		lfinish[1] = NEW_LABEL(nd_line(node));
	    }
	    ADD_INSNL(ret, nd_line(node), branchunless, lfinish[1]);
	} while ((vals = vals->nd_next) != NULL);
      }
      case NODE_STR:
      case NODE_LIT:
      case NODE_ZARRAY:
      case NODE_AND:
      case NODE_OR:
      default:
	expr_type = DEFINED_EXPR;
	break;

	/* variables */
      case NODE_LVAR:
      case NODE_DVAR:
	expr_type = DEFINED_LVAR;
	break;

      case NODE_IVAR:
	ADD_INSN(ret, nd_line(node), putnil);
	ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_IVAR),
		  ID2SYM(node->nd_vid), needstr);
	return 1;

      case NODE_GVAR:
	ADD_INSN(ret, nd_line(node), putnil);
	ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_GVAR),
		  ID2SYM(node->nd_entry->id), needstr);
	return 1;

      case NODE_CVAR:
	ADD_INSN(ret, nd_line(node), putnil);
	ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_CVAR),
		  ID2SYM(node->nd_vid), needstr);
	return 1;

      case NODE_CONST:
	ADD_INSN(ret, nd_line(node), putnil);
	ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_CONST),
		  ID2SYM(node->nd_vid), needstr);
	return 1;
      case NODE_COLON2:
	if (!lfinish[1]) {
	    lfinish[1] = NEW_LABEL(nd_line(node));
	}
	defined_expr(iseq, ret, node->nd_head, lfinish, Qfalse);
	ADD_INSNL(ret, nd_line(node), branchunless, lfinish[1]);

	if (rb_is_const_id(node->nd_mid)) {
	    COMPILE(ret, "defined/colon2#nd_head", node->nd_head);
	    ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_CONST),
		      ID2SYM(node->nd_mid), needstr);
	}
	else {
	    COMPILE(ret, "defined/colon2#nd_head", node->nd_head);
	    ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_METHOD),
		      ID2SYM(node->nd_mid), needstr);
	}
	return 1;
      case NODE_COLON3:
	ADD_INSN1(ret, nd_line(node), putobject, rb_cObject);
	ADD_INSN3(ret, nd_line(node), defined,
		  INT2FIX(DEFINED_CONST), ID2SYM(node->nd_mid), needstr);
	return 1;

	/* method dispatch */
      case NODE_CALL:
      case NODE_VCALL:
      case NODE_FCALL:
      case NODE_ATTRASGN:{
	const int explicit_receiver =
	    (type == NODE_CALL ||
	     (type == NODE_ATTRASGN && !private_recv_p(node)));

	if (!lfinish[1]) {
	    lfinish[1] = NEW_LABEL(nd_line(node));
	}
	if (node->nd_args) {
	    defined_expr(iseq, ret, node->nd_args, lfinish, Qfalse);
	    ADD_INSNL(ret, nd_line(node), branchunless, lfinish[1]);
	}
	if (explicit_receiver) {
	    defined_expr(iseq, ret, node->nd_recv, lfinish, Qfalse);
	    ADD_INSNL(ret, nd_line(node), branchunless, lfinish[1]);
	    COMPILE(ret, "defined/recv", node->nd_recv);
	    ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_METHOD),
		      ID2SYM(node->nd_mid), needstr);
	}
	else {
	    ADD_INSN(ret, nd_line(node), putself);
	    ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_FUNC),
		      ID2SYM(node->nd_mid), needstr);
	}
	return 1;
      }

      case NODE_YIELD:
	ADD_INSN(ret, nd_line(node), putnil);
	ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_YIELD), 0,
		  needstr);
	return 1;

      case NODE_BACK_REF:
      case NODE_NTH_REF:
	ADD_INSN(ret, nd_line(node), putnil);
	ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_REF),
		  INT2FIX((node->nd_nth << 1) | (type == NODE_BACK_REF)),
		  needstr);
	return 1;

      case NODE_SUPER:
      case NODE_ZSUPER:
	ADD_INSN(ret, nd_line(node), putnil);
	ADD_INSN3(ret, nd_line(node), defined, INT2FIX(DEFINED_ZSUPER), 0,
		  needstr);
	return 1;

      case NODE_OP_ASGN1:
      case NODE_OP_ASGN2:
      case NODE_OP_ASGN_OR:
      case NODE_OP_ASGN_AND:
      case NODE_MASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_DASGN_CURR:
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_CDECL:
      case NODE_CVDECL:
      case NODE_CVASGN:
	expr_type = DEFINED_ASGN;
	break;
    }

    if (expr_type) {
	if (needstr != Qfalse) {
	    VALUE str = rb_iseq_defined_string(expr_type);
	    ADD_INSN1(ret, nd_line(node), putobject, str);
	}
	else {
	    ADD_INSN1(ret, nd_line(node), putobject, Qtrue);
	}
	return 1;
    }
    return 0;
}
#undef defined_expr

static int
defined_expr(rb_iseq_t *iseq, LINK_ANCHOR *const ret,
	     NODE *node, LABEL **lfinish, VALUE needstr)
{
    LINK_ELEMENT *lcur = ret->last;
    int done = defined_expr0(iseq, ret, node, lfinish, needstr);
    if (lfinish[1]) {
	int line = nd_line(node);
	LABEL *lstart = NEW_LABEL(line);
	LABEL *lend = NEW_LABEL(line);
	const rb_iseq_t *rescue = NEW_CHILD_ISEQ(NEW_NIL(),
						 rb_str_concat(rb_str_new2
							       ("defined guard in "),
							       iseq->body->location.label),
						 ISEQ_TYPE_DEFINED_GUARD, 0);
	lstart->rescued = LABEL_RESCUE_BEG;
	lend->rescued = LABEL_RESCUE_END;
	APPEND_LABEL(ret, lcur, lstart);
	ADD_LABEL(ret, lend);
	ADD_CATCH_ENTRY(CATCH_TYPE_RESCUE, lstart, lend, rescue, lfinish[1]);
    }
    return done;
}

static VALUE
make_name_for_block(const rb_iseq_t *orig_iseq)
{
    int level = 1;
    const rb_iseq_t *iseq = orig_iseq;

    if (orig_iseq->body->parent_iseq != 0) {
	while (orig_iseq->body->local_iseq != iseq) {
	    if (iseq->body->type == ISEQ_TYPE_BLOCK) {
		level++;
	    }
	    iseq = iseq->body->parent_iseq;
	}
    }

    if (level == 1) {
	return rb_sprintf("block in %"PRIsVALUE, iseq->body->location.label);
    }
    else {
	return rb_sprintf("block (%d levels) in %"PRIsVALUE, level, iseq->body->location.label);
    }
}

static void
push_ensure_entry(rb_iseq_t *iseq,
		  struct iseq_compile_data_ensure_node_stack *enl,
		  struct ensure_range *er, NODE *node)
{
    enl->ensure_node = node;
    enl->prev = ISEQ_COMPILE_DATA(iseq)->ensure_node_stack;	/* prev */
    enl->erange = er;
    ISEQ_COMPILE_DATA(iseq)->ensure_node_stack = enl;
}

static void
add_ensure_range(rb_iseq_t *iseq, struct ensure_range *erange,
		 LABEL *lstart, LABEL *lend)
{
    struct ensure_range *ne =
	compile_data_alloc(iseq, sizeof(struct ensure_range));

    while (erange->next != 0) {
	erange = erange->next;
    }
    ne->next = 0;
    ne->begin = lend;
    ne->end = erange->end;
    erange->end = lstart;

    erange->next = ne;
}

static void
add_ensure_iseq(LINK_ANCHOR *const ret, rb_iseq_t *iseq, int is_return)
{
    struct iseq_compile_data_ensure_node_stack *enlp =
	ISEQ_COMPILE_DATA(iseq)->ensure_node_stack;
    struct iseq_compile_data_ensure_node_stack *prev_enlp = enlp;
    DECL_ANCHOR(ensure);

    INIT_ANCHOR(ensure);
    while (enlp) {
	if (enlp->erange != 0) {
	    DECL_ANCHOR(ensure_part);
	    LABEL *lstart = NEW_LABEL(0);
	    LABEL *lend = NEW_LABEL(0);
	    INIT_ANCHOR(ensure_part);

	    add_ensure_range(iseq, enlp->erange, lstart, lend);

	    ISEQ_COMPILE_DATA(iseq)->ensure_node_stack = enlp->prev;
	    ADD_LABEL(ensure_part, lstart);
	    COMPILE_POPPED(ensure_part, "ensure part", enlp->ensure_node);
	    ADD_LABEL(ensure_part, lend);
	    ADD_SEQ(ensure, ensure_part);
	}
	else {
	    if (!is_return) {
		break;
	    }
	}
	enlp = enlp->prev;
    }
    ISEQ_COMPILE_DATA(iseq)->ensure_node_stack = prev_enlp;
    ADD_SEQ(ret, ensure);
}

static VALUE
setup_args(rb_iseq_t *iseq, LINK_ANCHOR *const args, NODE *argn,
	   unsigned int *flag, struct rb_call_info_kw_arg **keywords)
{
    VALUE argc = INT2FIX(0);
    int nsplat = 0;
    DECL_ANCHOR(arg_block);
    DECL_ANCHOR(args_splat);

    INIT_ANCHOR(arg_block);
    INIT_ANCHOR(args_splat);
    if (argn && nd_type(argn) == NODE_BLOCK_PASS) {
	COMPILE(arg_block, "block", argn->nd_body);
	*flag |= VM_CALL_ARGS_BLOCKARG;
	argn = argn->nd_head;
    }

  setup_argn:
    if (argn) {
	switch (nd_type(argn)) {
	  case NODE_SPLAT: {
	    COMPILE(args, "args (splat)", argn->nd_head);
	    ADD_INSN1(args, nd_line(argn), splatarray, nsplat ? Qtrue : Qfalse);
	    argc = INT2FIX(1);
	    nsplat++;
	    *flag |= VM_CALL_ARGS_SPLAT;
	    break;
	  }
	  case NODE_ARGSCAT:
	  case NODE_ARGSPUSH: {
	    int next_is_array = (nd_type(argn->nd_head) == NODE_ARRAY);
	    DECL_ANCHOR(tmp);

	    INIT_ANCHOR(tmp);
	    COMPILE(tmp, "args (cat: splat)", argn->nd_body);
	    if (nd_type(argn) == NODE_ARGSCAT) {
		ADD_INSN1(tmp, nd_line(argn), splatarray, nsplat ? Qtrue : Qfalse);
	    }
	    else {
		ADD_INSN1(tmp, nd_line(argn), newarray, INT2FIX(1));
	    }
	    INSERT_LIST(args_splat, tmp);
	    nsplat++;
	    *flag |= VM_CALL_ARGS_SPLAT;

	    if (next_is_array) {
		argc = INT2FIX(compile_array(iseq, args, argn->nd_head, COMPILE_ARRAY_TYPE_ARGS) + 1);
	    }
	    else {
		argn = argn->nd_head;
		goto setup_argn;
	    }
	    break;
	  }
	  case NODE_ARRAY:
	    {
		argc = INT2FIX(compile_array_(iseq, args, argn, COMPILE_ARRAY_TYPE_ARGS, keywords, FALSE));
		break;
	    }
	  default: {
	    UNKNOWN_NODE("setup_arg", argn);
	  }
	}
    }

    if (nsplat > 1) {
	int i;
	for (i=1; i<nsplat; i++) {
	    ADD_INSN(args_splat, nd_line(args), concatarray);
	}
    }

    if (!LIST_SIZE_ZERO(args_splat)) {
	ADD_SEQ(args, args_splat);
    }

    if (*flag & VM_CALL_ARGS_BLOCKARG) {
	ADD_SEQ(args, arg_block);
    }
    return argc;
}

static VALUE
build_postexe_iseq(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *body)
{
    int line = nd_line(body);
    VALUE argc = INT2FIX(0);
    const rb_iseq_t *block = NEW_CHILD_ISEQ(body, make_name_for_block(iseq->body->parent_iseq), ISEQ_TYPE_BLOCK, line);

    ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
    ADD_CALL_WITH_BLOCK(ret, line, id_core_set_postexe, argc, block);
    iseq_set_local_table(iseq, 0);
    return Qnil;
}

static void
compile_named_capture_assign(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *node)
{
    NODE *vars;
    LINK_ELEMENT *last;
    int line = nd_line(node);
    LABEL *fail_label = NEW_LABEL(line), *end_label = NEW_LABEL(line);

#if !(defined(NAMED_CAPTURE_BY_SVAR) && NAMED_CAPTURE_BY_SVAR-0)
    ADD_INSN1(ret, line, getglobal, ((VALUE)rb_global_entry(idBACKREF) | 1));
#else
    ADD_INSN2(ret, line, getspecial, INT2FIX(1) /* '~' */, INT2FIX(0));
#endif
    ADD_INSN(ret, line, dup);
    ADD_INSNL(ret, line, branchunless, fail_label);

    for (vars = node; vars; vars = vars->nd_next) {
	INSN *cap;
	if (vars->nd_next) {
	    ADD_INSN(ret, line, dup);
	}
	last = ret->last;
	COMPILE_POPPED(ret, "capture", vars->nd_head);
	last = last->next; /* putobject :var */
	cap = new_insn_send(iseq, line, idAREF, INT2FIX(1),
			    NULL, INT2FIX(0), NULL);
	INSERT_ELEM_PREV(last->next, (LINK_ELEMENT *)cap);
#if !defined(NAMED_CAPTURE_SINGLE_OPT) || NAMED_CAPTURE_SINGLE_OPT-0
	if (!vars->nd_next && vars == node) {
	    /* only one name */
	    DECL_ANCHOR(nom);

	    INIT_ANCHOR(nom);
	    ADD_INSNL(nom, line, jump, end_label);
	    ADD_LABEL(nom, fail_label);
# if 0				/* $~ must be MatchData or nil */
	    ADD_INSN(nom, line, pop);
	    ADD_INSN(nom, line, putnil);
# endif
	    ADD_LABEL(nom, end_label);
	    (nom->last->next = cap->link.next)->prev = nom->last;
	    (cap->link.next = nom->anchor.next)->prev = &cap->link;
	    return;
	}
#endif
    }
    ADD_INSNL(ret, line, jump, end_label);
    ADD_LABEL(ret, fail_label);
    ADD_INSN(ret, line, pop);
    for (vars = node; vars; vars = vars->nd_next) {
	last = ret->last;
	COMPILE_POPPED(ret, "capture", vars->nd_head);
	last = last->next; /* putobject :var */
	((INSN*)last)->insn_id = BIN(putnil);
	((INSN*)last)->operand_size = 0;
    }
    ADD_LABEL(ret, end_label);
}

static int
number_literal_p(NODE *n)
{
    return (n && nd_type(n) == NODE_LIT && RB_INTEGER_TYPE_P(n->nd_lit));
}

/**
  compile each node

  self:  InstructionSequence
  node:  Ruby compiled node
  popped: This node will be popped
 */
static int
iseq_compile_each(rb_iseq_t *iseq, LINK_ANCHOR *const ret, NODE *node, int popped)
{
    enum node_type type;
    LINK_ELEMENT *saved_last_element = 0;
    int line;

    if (node == 0) {
	if (!popped) {
	    debugs("node: NODE_NIL(implicit)\n");
	    ADD_INSN(ret, ISEQ_COMPILE_DATA(iseq)->last_line, putnil);
	}
	return COMPILE_OK;
    }

    line = (int)nd_line(node);

    if (ISEQ_COMPILE_DATA(iseq)->last_line == line) {
	/* ignore */
    }
    else {
	if (node->flags & NODE_FL_NEWLINE) {
	    ISEQ_COMPILE_DATA(iseq)->last_line = line;
	    ADD_TRACE(ret, line, RUBY_EVENT_LINE);
	    saved_last_element = ret->last;
	}
    }

    debug_node_start(node);

    type = nd_type(node);

    switch (type) {
      case NODE_BLOCK:{
	while (node && nd_type(node) == NODE_BLOCK) {
	    COMPILE_(ret, "BLOCK body", node->nd_head,
		     (node->nd_next == 0 && popped == 0) ? 0 : 1);
	    node = node->nd_next;
	}
	if (node) {
	    COMPILE_(ret, "BLOCK next", node->nd_next, popped);
	}
	break;
      }
      case NODE_IF:{
	DECL_ANCHOR(cond_seq);
	DECL_ANCHOR(then_seq);
	DECL_ANCHOR(else_seq);
	LABEL *then_label, *else_label, *end_label;

	INIT_ANCHOR(cond_seq);
	INIT_ANCHOR(then_seq);
	INIT_ANCHOR(else_seq);
	then_label = NEW_LABEL(line);
	else_label = NEW_LABEL(line);
	end_label = NEW_LABEL(line);

	compile_branch_condition(iseq, cond_seq, node->nd_cond,
				 then_label, else_label);
	COMPILE_(then_seq, "then", node->nd_body, popped);
	COMPILE_(else_seq, "else", node->nd_else, popped);

	ADD_SEQ(ret, cond_seq);

	ADD_LABEL(ret, then_label);
	ADD_SEQ(ret, then_seq);
	ADD_INSNL(ret, line, jump, end_label);

	ADD_LABEL(ret, else_label);
	ADD_SEQ(ret, else_seq);

	ADD_LABEL(ret, end_label);

	break;
      }
      case NODE_CASE:{
	NODE *vals;
	NODE *tempnode = node;
	LABEL *endlabel, *elselabel;
	DECL_ANCHOR(head);
	DECL_ANCHOR(body_seq);
	DECL_ANCHOR(cond_seq);
	int only_special_literals = 1;
	VALUE literals = rb_hash_new();

	INIT_ANCHOR(head);
	INIT_ANCHOR(body_seq);
	INIT_ANCHOR(cond_seq);

	rb_hash_tbl_raw(literals)->type = &cdhash_type;

	if (node->nd_head == 0) {
	    COMPILE_(ret, "when", node->nd_body, popped);
	    break;
	}
	COMPILE(head, "case base", node->nd_head);

	node = node->nd_body;
	type = nd_type(node);
	line = nd_line(node);

	if (type != NODE_WHEN) {
	    COMPILE_ERROR(ERROR_ARGS "NODE_CASE: unexpected node. must be NODE_WHEN, but %s", ruby_node_name(type));
	    debug_node_end();
	    return COMPILE_NG;
	}

	endlabel = NEW_LABEL(line);
	elselabel = NEW_LABEL(line);

	ADD_SEQ(ret, head);	/* case VAL */

	while (type == NODE_WHEN) {
	    LABEL *l1;

	    l1 = NEW_LABEL(line);
	    ADD_LABEL(body_seq, l1);
	    ADD_INSN(body_seq, line, pop);
	    COMPILE_(body_seq, "when body", node->nd_body, popped);
	    ADD_INSNL(body_seq, line, jump, endlabel);

	    vals = node->nd_head;
	    if (vals) {
		switch (nd_type(vals)) {
		  case NODE_ARRAY:
		    only_special_literals = when_vals(iseq, cond_seq, vals, l1, only_special_literals, literals);
		    break;
		  case NODE_SPLAT:
		  case NODE_ARGSCAT:
		  case NODE_ARGSPUSH:
		    only_special_literals = 0;
		    ADD_INSN (cond_seq, nd_line(vals), dup);
		    COMPILE(cond_seq, "when/cond splat", vals);
		    ADD_INSN1(cond_seq, nd_line(vals), checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_CASE | VM_CHECKMATCH_ARRAY));
		    ADD_INSNL(cond_seq, nd_line(vals), branchif, l1);
		    break;
		  default:
		    UNKNOWN_NODE("NODE_CASE", vals);
		}
	    }
	    else {
		EXPECT_NODE_NONULL("NODE_CASE", node, NODE_ARRAY);
	    }

	    node = node->nd_next;
	    if (!node) {
		break;
	    }
	    type = nd_type(node);
	    line = nd_line(node);
	}
	/* else */
	if (node) {
	    ADD_LABEL(cond_seq, elselabel);
	    ADD_INSN(cond_seq, line, pop);
	    COMPILE_(cond_seq, "else", node, popped);
	    ADD_INSNL(cond_seq, line, jump, endlabel);
	}
	else {
	    debugs("== else (implicit)\n");
	    ADD_LABEL(cond_seq, elselabel);
	    ADD_INSN(cond_seq, nd_line(tempnode), pop);
	    if (!popped) {
		ADD_INSN(cond_seq, nd_line(tempnode), putnil);
	    }
	    ADD_INSNL(cond_seq, nd_line(tempnode), jump, endlabel);
	}

	if (only_special_literals) {
	    iseq_add_mark_object(iseq, literals);

	    ADD_INSN(ret, nd_line(tempnode), dup);
	    ADD_INSN2(ret, nd_line(tempnode), opt_case_dispatch, literals, elselabel);
	    LABEL_REF(elselabel);
	}

	ADD_SEQ(ret, cond_seq);
	ADD_SEQ(ret, body_seq);
	ADD_LABEL(ret, endlabel);
	break;
      }
      case NODE_WHEN:{
	NODE *vals;
	NODE *val;
	NODE *orig_node = node;
	LABEL *endlabel;
	DECL_ANCHOR(body_seq);

	INIT_ANCHOR(body_seq);
	endlabel = NEW_LABEL(line);

	while (node && nd_type(node) == NODE_WHEN) {
	    LABEL *l1 = NEW_LABEL(line = nd_line(node));
	    ADD_LABEL(body_seq, l1);
	    COMPILE_(body_seq, "when", node->nd_body, popped);
	    ADD_INSNL(body_seq, line, jump, endlabel);

	    vals = node->nd_head;
	    if (!vals) {
		compile_bug(ERROR_ARGS "NODE_WHEN: must be NODE_ARRAY, but 0");
	    }
	    switch (nd_type(vals)) {
	      case NODE_ARRAY:
		while (vals) {
		    val = vals->nd_head;
		    COMPILE(ret, "when2", val);
		    ADD_INSNL(ret, nd_line(val), branchif, l1);
		    vals = vals->nd_next;
		}
		break;
	      case NODE_SPLAT:
	      case NODE_ARGSCAT:
	      case NODE_ARGSPUSH:
		ADD_INSN(ret, nd_line(vals), putnil);
		COMPILE(ret, "when2/cond splat", vals);
		ADD_INSN1(ret, nd_line(vals), checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_WHEN | VM_CHECKMATCH_ARRAY));
		ADD_INSNL(ret, nd_line(vals), branchif, l1);
		break;
	      default:
		UNKNOWN_NODE("NODE_WHEN", vals);
	    }
	    node = node->nd_next;
	}
	/* else */
	COMPILE_(ret, "else", node, popped);
	ADD_INSNL(ret, nd_line(orig_node), jump, endlabel);

	ADD_SEQ(ret, body_seq);
	ADD_LABEL(ret, endlabel);

	break;
      }
      case NODE_OPT_N:
      case NODE_WHILE:
      case NODE_UNTIL:{
	LABEL *prev_start_label = ISEQ_COMPILE_DATA(iseq)->start_label;
	LABEL *prev_end_label = ISEQ_COMPILE_DATA(iseq)->end_label;
	LABEL *prev_redo_label = ISEQ_COMPILE_DATA(iseq)->redo_label;
	int prev_loopval_popped = ISEQ_COMPILE_DATA(iseq)->loopval_popped;

	struct iseq_compile_data_ensure_node_stack enl;

	LABEL *next_label = ISEQ_COMPILE_DATA(iseq)->start_label = NEW_LABEL(line);	/* next  */
	LABEL *redo_label = ISEQ_COMPILE_DATA(iseq)->redo_label = NEW_LABEL(line);	/* redo  */
	LABEL *break_label = ISEQ_COMPILE_DATA(iseq)->end_label = NEW_LABEL(line);	/* break */
	LABEL *end_label = NEW_LABEL(line);
	LABEL *adjust_label = NEW_LABEL(line);

	LABEL *next_catch_label = NEW_LABEL(line);
	LABEL *tmp_label = NULL;

	ISEQ_COMPILE_DATA(iseq)->loopval_popped = 0;
	push_ensure_entry(iseq, &enl, 0, 0);

	if (type == NODE_OPT_N || node->nd_state == 1) {
	    ADD_INSNL(ret, line, jump, next_label);
	}
	else {
	    tmp_label = NEW_LABEL(line);
	    ADD_INSNL(ret, line, jump, tmp_label);
	}
	ADD_LABEL(ret, adjust_label);
	ADD_INSN(ret, line, putnil);
	ADD_LABEL(ret, next_catch_label);
	ADD_INSN(ret, line, pop);
	ADD_INSNL(ret, line, jump, next_label);
	if (tmp_label) ADD_LABEL(ret, tmp_label);

	ADD_LABEL(ret, redo_label);
	COMPILE_POPPED(ret, "while body", node->nd_body);
	ADD_LABEL(ret, next_label);	/* next */

	if (type == NODE_WHILE) {
	    compile_branch_condition(iseq, ret, node->nd_cond,
				     redo_label, end_label);
	}
	else if (type == NODE_UNTIL) {
	    /* until */
	    compile_branch_condition(iseq, ret, node->nd_cond,
				     end_label, redo_label);
	}
	else {
	    ADD_CALL_RECEIVER(ret, line);
	    ADD_CALL(ret, line, idGets, INT2FIX(0));
	    ADD_INSNL(ret, line, branchif, redo_label);
	    /* opt_n */
	}

	ADD_LABEL(ret, end_label);
	ADD_ADJUST_RESTORE(ret, adjust_label);

	if (node->nd_state == Qundef) {
	    /* ADD_INSN(ret, line, putundef); */
	    compile_bug(ERROR_ARGS "unsupported: putundef");
	}
	else {
	    ADD_INSN(ret, line, putnil);
	}

	ADD_LABEL(ret, break_label);	/* break */

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}

	ADD_CATCH_ENTRY(CATCH_TYPE_BREAK, redo_label, break_label,
			0, break_label);
	ADD_CATCH_ENTRY(CATCH_TYPE_NEXT, redo_label, break_label, 0,
			next_catch_label);
	ADD_CATCH_ENTRY(CATCH_TYPE_REDO, redo_label, break_label, 0,
			ISEQ_COMPILE_DATA(iseq)->redo_label);

	ISEQ_COMPILE_DATA(iseq)->start_label = prev_start_label;
	ISEQ_COMPILE_DATA(iseq)->end_label = prev_end_label;
	ISEQ_COMPILE_DATA(iseq)->redo_label = prev_redo_label;
	ISEQ_COMPILE_DATA(iseq)->loopval_popped = prev_loopval_popped;
	ISEQ_COMPILE_DATA(iseq)->ensure_node_stack = ISEQ_COMPILE_DATA(iseq)->ensure_node_stack->prev;
	break;
      }
      case NODE_FOR:
	if (node->nd_var) {
	    /* massign to var in "for"
	     * args.length == 1 && Array === (tmp = args[0]) ? tmp : args
	     */
	    NODE *var = node->nd_var;
	    LABEL *not_single = NEW_LABEL(nd_line(var));
	    LABEL *not_ary = NEW_LABEL(nd_line(var));
	    COMPILE(ret, "for var", var);
	    ADD_INSN(ret, line, dup);
	    ADD_CALL(ret, line, idLength, INT2FIX(0));
	    ADD_INSN1(ret, line, putobject, INT2FIX(1));
	    ADD_CALL(ret, line, idEq, INT2FIX(1));
	    ADD_INSNL(ret, line, branchunless, not_single);
	    ADD_INSN(ret, line, dup);
	    ADD_INSN1(ret, line, putobject, INT2FIX(0));
	    ADD_CALL(ret, line, idAREF, INT2FIX(1));
	    ADD_INSN1(ret, line, putobject, rb_cArray);
	    ADD_INSN1(ret, line, topn, INT2FIX(1));
	    ADD_CALL(ret, line, idEqq, INT2FIX(1));
	    ADD_INSNL(ret, line, branchunless, not_ary);
	    ADD_INSN(ret, line, swap);
	    ADD_LABEL(ret, not_ary);
	    ADD_INSN(ret, line, pop);
	    ADD_LABEL(ret, not_single);
	    break;
	}
      case NODE_ITER:{
	const rb_iseq_t *prevblock = ISEQ_COMPILE_DATA(iseq)->current_block;
	LABEL *retry_label = NEW_LABEL(line);
	LABEL *retry_end_l = NEW_LABEL(line);

	ADD_LABEL(ret, retry_label);
	if (nd_type(node) == NODE_FOR) {
	    COMPILE(ret, "iter caller (for)", node->nd_iter);

	    ISEQ_COMPILE_DATA(iseq)->current_block = NEW_CHILD_ISEQ(node->nd_body, make_name_for_block(iseq),
							       ISEQ_TYPE_BLOCK, line);
	    ADD_SEND_WITH_BLOCK(ret, line, idEach, INT2FIX(0), ISEQ_COMPILE_DATA(iseq)->current_block);
	}
	else {
	    ISEQ_COMPILE_DATA(iseq)->current_block = NEW_CHILD_ISEQ(node->nd_body, make_name_for_block(iseq),
							       ISEQ_TYPE_BLOCK, line);
	    COMPILE(ret, "iter caller", node->nd_iter);
	}
	ADD_LABEL(ret, retry_end_l);

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}

	ISEQ_COMPILE_DATA(iseq)->current_block = prevblock;

	ADD_CATCH_ENTRY(CATCH_TYPE_BREAK, retry_label, retry_end_l, 0, retry_end_l);

	break;
      }
      case NODE_BREAK:{
	unsigned long level = 0;

	if (ISEQ_COMPILE_DATA(iseq)->redo_label != 0) {
	    /* while/until */
	    LABEL *splabel = NEW_LABEL(0);
	    ADD_LABEL(ret, splabel);
	    ADD_ADJUST(ret, line, ISEQ_COMPILE_DATA(iseq)->redo_label);
	    COMPILE_(ret, "break val (while/until)", node->nd_stts, ISEQ_COMPILE_DATA(iseq)->loopval_popped);
	    add_ensure_iseq(ret, iseq, 0);
	    ADD_INSNL(ret, line, jump, ISEQ_COMPILE_DATA(iseq)->end_label);
	    ADD_ADJUST_RESTORE(ret, splabel);

	    if (!popped) {
		ADD_INSN(ret, line, putnil);
	    }
	}
	else if (iseq->body->type == ISEQ_TYPE_BLOCK) {
	  break_by_insn:
	    /* escape from block */
	    COMPILE(ret, "break val (block)", node->nd_stts);
	    ADD_INSN1(ret, line, throw, INT2FIX(level | TAG_BREAK));
	    if (popped) {
		ADD_INSN(ret, line, pop);
	    }
	}
	else if (iseq->body->type == ISEQ_TYPE_EVAL) {
	  break_in_eval:
	    COMPILE_ERROR(ERROR_ARGS "Can't escape from eval with break");
	    debug_node_end();
	    return COMPILE_NG;
	}
	else {
	    const rb_iseq_t *ip = iseq->body->parent_iseq;

	    while (ip) {
		if (!ISEQ_COMPILE_DATA(ip)) {
		    ip = 0;
		    break;
		}

		level++;
		if (ISEQ_COMPILE_DATA(ip)->redo_label != 0) {
		    level = VM_THROW_NO_ESCAPE_FLAG;
		    goto break_by_insn;
		}
		else if (ip->body->type == ISEQ_TYPE_BLOCK) {
		    level <<= VM_THROW_LEVEL_SHIFT;
		    goto break_by_insn;
		}
		else if (ip->body->type == ISEQ_TYPE_EVAL) {
		    goto break_in_eval;
		}

		ip = ip->body->parent_iseq;
	    }
	    COMPILE_ERROR(ERROR_ARGS "Invalid break");
	    debug_node_end();
	    return COMPILE_NG;
	}
	break;
      }
      case NODE_NEXT:{
	unsigned long level = 0;

	if (ISEQ_COMPILE_DATA(iseq)->redo_label != 0) {
	    LABEL *splabel = NEW_LABEL(0);
	    debugs("next in while loop\n");
	    ADD_LABEL(ret, splabel);
	    COMPILE(ret, "next val/valid syntax?", node->nd_stts);
	    add_ensure_iseq(ret, iseq, 0);
	    ADD_ADJUST(ret, line, ISEQ_COMPILE_DATA(iseq)->redo_label);
	    ADD_INSNL(ret, line, jump, ISEQ_COMPILE_DATA(iseq)->start_label);
	    ADD_ADJUST_RESTORE(ret, splabel);
	    if (!popped) {
		ADD_INSN(ret, line, putnil);
	    }
	}
	else if (ISEQ_COMPILE_DATA(iseq)->end_label) {
	    LABEL *splabel = NEW_LABEL(0);
	    debugs("next in block\n");
	    ADD_LABEL(ret, splabel);
	    ADD_ADJUST(ret, line, ISEQ_COMPILE_DATA(iseq)->start_label);
	    COMPILE(ret, "next val", node->nd_stts);
	    add_ensure_iseq(ret, iseq, 0);
	    ADD_INSNL(ret, line, jump, ISEQ_COMPILE_DATA(iseq)->end_label);
	    ADD_ADJUST_RESTORE(ret, splabel);

	    if (!popped) {
		ADD_INSN(ret, line, putnil);
	    }
	}
	else if (iseq->body->type == ISEQ_TYPE_EVAL) {
	  next_in_eval:
	    COMPILE_ERROR(ERROR_ARGS "Can't escape from eval with next");
	}
	else {
	    const rb_iseq_t *ip = iseq;

	    while (ip) {
		if (!ISEQ_COMPILE_DATA(ip)) {
		    ip = 0;
		    break;
		}

		level = VM_THROW_NO_ESCAPE_FLAG;
		if (ISEQ_COMPILE_DATA(ip)->redo_label != 0) {
		    /* while loop */
		    break;
		}
		else if (ip->body->type == ISEQ_TYPE_BLOCK) {
		    break;
		}
		else if (ip->body->type == ISEQ_TYPE_EVAL) {
		    goto next_in_eval;
		}

		ip = ip->body->parent_iseq;
	    }
	    if (ip != 0) {
		COMPILE(ret, "next val", node->nd_stts);
		ADD_INSN1(ret, line, throw, INT2FIX(level | TAG_NEXT));

		if (popped) {
		    ADD_INSN(ret, line, pop);
		}
	    }
	    else {
		COMPILE_ERROR(ERROR_ARGS "Invalid next");
	    }
	}
	break;
      }
      case NODE_REDO:{
	if (ISEQ_COMPILE_DATA(iseq)->redo_label) {
	    LABEL *splabel = NEW_LABEL(0);
	    debugs("redo in while");
	    ADD_LABEL(ret, splabel);
	    ADD_ADJUST(ret, line, ISEQ_COMPILE_DATA(iseq)->redo_label);
	    add_ensure_iseq(ret, iseq, 0);
	    ADD_INSNL(ret, line, jump, ISEQ_COMPILE_DATA(iseq)->redo_label);
	    ADD_ADJUST_RESTORE(ret, splabel);
	    if (!popped) {
		ADD_INSN(ret, line, putnil);
	    }
	}
	else if (iseq->body->type == ISEQ_TYPE_EVAL) {
	  redo_in_eval:
	    COMPILE_ERROR(ERROR_ARGS "Can't escape from eval with redo");
	}
	else if (ISEQ_COMPILE_DATA(iseq)->start_label) {
	    LABEL *splabel = NEW_LABEL(0);

	    debugs("redo in block");
	    ADD_LABEL(ret, splabel);
	    add_ensure_iseq(ret, iseq, 0);
	    ADD_ADJUST(ret, line, ISEQ_COMPILE_DATA(iseq)->start_label);
	    ADD_INSNL(ret, line, jump, ISEQ_COMPILE_DATA(iseq)->start_label);
	    ADD_ADJUST_RESTORE(ret, splabel);

	    if (!popped) {
		ADD_INSN(ret, line, putnil);
	    }
	}
	else {
	    const rb_iseq_t *ip = iseq;
	    const unsigned long level = VM_THROW_NO_ESCAPE_FLAG;

	    while (ip) {
		if (!ISEQ_COMPILE_DATA(ip)) {
		    ip = 0;
		    break;
		}

		if (ISEQ_COMPILE_DATA(ip)->redo_label != 0) {
		    break;
		}
		else if (ip->body->type == ISEQ_TYPE_BLOCK) {
		    break;
		}
		else if (ip->body->type == ISEQ_TYPE_EVAL) {
		    goto redo_in_eval;
		}

		ip = ip->body->parent_iseq;
	    }
	    if (ip != 0) {
		ADD_INSN(ret, line, putnil);
		ADD_INSN1(ret, line, throw, INT2FIX(level | TAG_REDO));

		if (popped) {
		    ADD_INSN(ret, line, pop);
		}
	    }
	    else {
		COMPILE_ERROR(ERROR_ARGS "Invalid redo");
	    }
	}
	break;
      }
      case NODE_RETRY:{
	if (iseq->body->type == ISEQ_TYPE_RESCUE) {
	    ADD_INSN(ret, line, putnil);
	    ADD_INSN1(ret, line, throw, INT2FIX(TAG_RETRY));

	    if (popped) {
		ADD_INSN(ret, line, pop);
	    }
	}
	else {
	    COMPILE_ERROR(ERROR_ARGS "Invalid retry");
	}
	break;
      }
      case NODE_BEGIN:{
	COMPILE_(ret, "NODE_BEGIN", node->nd_body, popped);
	break;
      }
      case NODE_RESCUE:{
	LABEL *lstart = NEW_LABEL(line);
	LABEL *lend = NEW_LABEL(line);
	LABEL *lcont = NEW_LABEL(line);
	const rb_iseq_t *rescue = NEW_CHILD_ISEQ(node->nd_resq,
						 rb_str_concat(rb_str_new2("rescue in "), iseq->body->location.label),
						 ISEQ_TYPE_RESCUE, line);

	lstart->rescued = LABEL_RESCUE_BEG;
	lend->rescued = LABEL_RESCUE_END;
	ADD_LABEL(ret, lstart);
	COMPILE(ret, "rescue head", node->nd_head);
	ADD_LABEL(ret, lend);
	if (node->nd_else) {
	    ADD_INSN(ret, line, pop);
	    COMPILE(ret, "rescue else", node->nd_else);
	}
	ADD_INSN(ret, line, nop);
	ADD_LABEL(ret, lcont);

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}

	/* register catch entry */
	ADD_CATCH_ENTRY(CATCH_TYPE_RESCUE, lstart, lend, rescue, lcont);
	ADD_CATCH_ENTRY(CATCH_TYPE_RETRY, lend, lcont, 0, lstart);
	break;
      }
      case NODE_RESBODY:{
	NODE *resq = node;
	NODE *narg;
	LABEL *label_miss, *label_hit;

	while (resq) {
	    label_miss = NEW_LABEL(line);
	    label_hit = NEW_LABEL(line);

	    narg = resq->nd_args;
	    if (narg) {
		switch (nd_type(narg)) {
		  case NODE_ARRAY:
		    while (narg) {
			ADD_GETLOCAL(ret, line, LVAR_ERRINFO, 0);
			COMPILE(ret, "rescue arg", narg->nd_head);
			ADD_INSN1(ret, line, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_RESCUE));
			ADD_INSNL(ret, line, branchif, label_hit);
			narg = narg->nd_next;
		    }
		    break;
		  case NODE_SPLAT:
		  case NODE_ARGSCAT:
		  case NODE_ARGSPUSH:
		    ADD_GETLOCAL(ret, line, LVAR_ERRINFO, 0);
		    COMPILE(ret, "rescue/cond splat", narg);
		    ADD_INSN1(ret, line, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_RESCUE | VM_CHECKMATCH_ARRAY));
		    ADD_INSNL(ret, line, branchif, label_hit);
		    break;
		  default:
		    UNKNOWN_NODE("NODE_RESBODY", narg);
		}
	    }
	    else {
		ADD_GETLOCAL(ret, line, LVAR_ERRINFO, 0);
		ADD_INSN1(ret, line, putobject, rb_eStandardError);
		ADD_INSN1(ret, line, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_RESCUE));
		ADD_INSNL(ret, line, branchif, label_hit);
	    }
	    ADD_INSNL(ret, line, jump, label_miss);
	    ADD_LABEL(ret, label_hit);
	    COMPILE(ret, "resbody body", resq->nd_body);
	    if (ISEQ_COMPILE_DATA(iseq)->option->tailcall_optimization) {
		ADD_INSN(ret, line, nop);
	    }
	    ADD_INSN(ret, line, leave);
	    ADD_LABEL(ret, label_miss);
	    resq = resq->nd_head;
	}
	break;
      }
      case NODE_ENSURE:{
	DECL_ANCHOR(ensr);
	const rb_iseq_t *ensure = NEW_CHILD_ISEQ(node->nd_ensr,
						 rb_str_concat(rb_str_new2 ("ensure in "), iseq->body->location.label),
						 ISEQ_TYPE_ENSURE, line);
	LABEL *lstart = NEW_LABEL(line);
	LABEL *lend = NEW_LABEL(line);
	LABEL *lcont = NEW_LABEL(line);
	LINK_ELEMENT *last;
	int last_leave = 0;
	struct ensure_range er;
	struct iseq_compile_data_ensure_node_stack enl;
	struct ensure_range *erange;

	INIT_ANCHOR(ensr);
	COMPILE_POPPED(ensr, "ensure ensr", node->nd_ensr);
	last = ensr->last;
	last_leave = last && IS_INSN(last) && IS_INSN_ID(last, leave);
	if (!popped && last_leave)
	    popped = 1;

	er.begin = lstart;
	er.end = lend;
	er.next = 0;
	push_ensure_entry(iseq, &enl, &er, node->nd_ensr);

	ADD_LABEL(ret, lstart);
	COMPILE_(ret, "ensure head", node->nd_head, popped);
	ADD_LABEL(ret, lend);
	if (ensr->anchor.next == 0) {
	    ADD_INSN(ret, line, nop);
	}
	else {
	    ADD_SEQ(ret, ensr);
	}
	ADD_LABEL(ret, lcont);
	if (last_leave) ADD_INSN(ret, line, pop);

	erange = ISEQ_COMPILE_DATA(iseq)->ensure_node_stack->erange;
	if (lstart->link.next != &lend->link) {
	    while (erange) {
		ADD_CATCH_ENTRY(CATCH_TYPE_ENSURE, erange->begin, erange->end,
				ensure, lcont);
		erange = erange->next;
	    }
	}

	ISEQ_COMPILE_DATA(iseq)->ensure_node_stack = enl.prev;
	break;
      }

      case NODE_AND:
      case NODE_OR:{
	LABEL *end_label = NEW_LABEL(line);
	COMPILE(ret, "nd_1st", node->nd_1st);
	if (!popped) {
	    ADD_INSN(ret, line, dup);
	}
	if (type == NODE_AND) {
	    ADD_INSNL(ret, line, branchunless, end_label);
	}
	else {
	    ADD_INSNL(ret, line, branchif, end_label);
	}
	if (!popped) {
	    ADD_INSN(ret, line, pop);
	}
	COMPILE_(ret, "nd_2nd", node->nd_2nd, popped);
	ADD_LABEL(ret, end_label);
	break;
      }

      case NODE_MASGN:{
	compile_massign(iseq, ret, node, popped);
	break;
      }

      case NODE_LASGN:{
	ID id = node->nd_vid;
	int idx = iseq->body->local_iseq->body->local_table_size - get_local_var_idx(iseq, id);

	debugs("lvar: %"PRIsVALUE" idx: %d\n", rb_id2str(id), idx);
	COMPILE(ret, "rvalue", node->nd_value);

	if (!popped) {
	    ADD_INSN(ret, line, dup);
	}
	ADD_SETLOCAL(ret, line, idx, get_lvar_level(iseq));
	break;
      }
      case NODE_DASGN:
      case NODE_DASGN_CURR:{
	int idx, lv, ls;
	COMPILE(ret, "dvalue", node->nd_value);
	debugi("dassn id", rb_id2str(node->nd_vid) ? node->nd_vid : '*');

	if (!popped) {
	    ADD_INSN(ret, line, dup);
	}

	idx = get_dyna_var_idx(iseq, node->nd_vid, &lv, &ls);

	if (idx < 0) {
	    compile_bug(ERROR_ARGS "NODE_DASGN(_CURR): unknown id (%"PRIsVALUE")",
			rb_id2str(node->nd_vid));
	}
	ADD_SETLOCAL(ret, line, ls - idx, lv);
	break;
      }
      case NODE_GASGN:{
	COMPILE(ret, "lvalue", node->nd_value);

	if (!popped) {
	    ADD_INSN(ret, line, dup);
	}
	ADD_INSN1(ret, line, setglobal,
		  ((VALUE)node->nd_entry | 1));
	break;
      }
      case NODE_IASGN:
      case NODE_IASGN2:{
	COMPILE(ret, "lvalue", node->nd_value);
	if (!popped) {
	    ADD_INSN(ret, line, dup);
	}
	ADD_INSN2(ret, line, setinstancevariable,
		  ID2SYM(node->nd_vid),
		  get_ivar_ic_value(iseq,node->nd_vid));
	break;
      }
      case NODE_CDECL:{
	COMPILE(ret, "lvalue", node->nd_value);

	if (!popped) {
	    ADD_INSN(ret, line, dup);
	}

	if (node->nd_vid) {
	    ADD_INSN1(ret, line, putspecialobject,
		      INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
	    ADD_INSN1(ret, line, setconstant, ID2SYM(node->nd_vid));
	}
	else {
	    compile_cpath(ret, iseq, node->nd_else);
	    ADD_INSN1(ret, line, setconstant, ID2SYM(node->nd_else->nd_mid));
	}
	break;
      }
      case NODE_CVASGN:{
	COMPILE(ret, "cvasgn val", node->nd_value);
	if (!popped) {
	    ADD_INSN(ret, line, dup);
	}
	ADD_INSN1(ret, line, setclassvariable,
		  ID2SYM(node->nd_vid));
	break;
      }
      case NODE_OP_ASGN1: {
	DECL_ANCHOR(args);
	VALUE argc;
	unsigned int flag = 0;
	unsigned int asgnflag = 0;
	ID id = node->nd_mid;
	int boff = 0;

	/*
	 * a[x] (op)= y
	 *
	 * nil       # nil
	 * eval a    # nil a
	 * eval x    # nil a x
	 * dupn 2    # nil a x a x
	 * send :[]  # nil a x a[x]
	 * eval y    # nil a x a[x] y
	 * send op   # nil a x ret
	 * setn 3    # ret a x ret
	 * send []=  # ret ?
	 * pop       # ret
	 */

	/*
	 * nd_recv[nd_args->nd_body] (nd_mid)= nd_args->nd_head;
	 * NODE_OP_ASGN nd_recv
	 *              nd_args->nd_head
	 *              nd_args->nd_body
	 *              nd_mid
	 */

	if (!popped) {
	    ADD_INSN(ret, line, putnil);
	}
	asgnflag = COMPILE_RECV(ret, "NODE_OP_ASGN1 recv", node);
	switch (nd_type(node->nd_args->nd_head)) {
	  case NODE_ZARRAY:
	    argc = INT2FIX(0);
	    break;
	  case NODE_BLOCK_PASS:
	    boff = 1;
	  default:
	    INIT_ANCHOR(args);
	    argc = setup_args(iseq, args, node->nd_args->nd_head, &flag, NULL);
	    ADD_SEQ(ret, args);
	}
	ADD_INSN1(ret, line, dupn, FIXNUM_INC(argc, 1 + boff));
	ADD_SEND_WITH_FLAG(ret, line, idAREF, argc, INT2FIX(flag));
	flag |= asgnflag;

	if (id == 0 || id == 1) {
	    /* 0: or, 1: and
	       a[x] ||= y

	       unless/if a[x]
	       a[x]= y
	       else
	       nil
	       end
	    */
	    LABEL *label = NEW_LABEL(line);
	    LABEL *lfin = NEW_LABEL(line);

	    ADD_INSN(ret, line, dup);
	    if (id == 0) {
		/* or */
		ADD_INSNL(ret, line, branchif, label);
	    }
	    else {
		/* and */
		ADD_INSNL(ret, line, branchunless, label);
	    }
	    ADD_INSN(ret, line, pop);

	    COMPILE(ret, "NODE_OP_ASGN1 args->body: ", node->nd_args->nd_body);
	    if (!popped) {
		ADD_INSN1(ret, line, setn, FIXNUM_INC(argc, 2+boff));
	    }
	    if (flag & VM_CALL_ARGS_SPLAT) {
		ADD_INSN1(ret, line, newarray, INT2FIX(1));
		if (boff > 0) {
		    ADD_INSN1(ret, line, dupn, INT2FIX(3));
		    ADD_INSN(ret, line, swap);
		    ADD_INSN(ret, line, pop);
		}
		ADD_INSN(ret, line, concatarray);
		if (boff > 0) {
		    ADD_INSN1(ret, line, setn, INT2FIX(3));
		    ADD_INSN(ret, line, pop);
		    ADD_INSN(ret, line, pop);
		}
		ADD_SEND_WITH_FLAG(ret, line, idASET, argc, INT2FIX(flag));
	    }
	    else {
		if (boff > 0)
		    ADD_INSN(ret, line, swap);
		ADD_SEND_WITH_FLAG(ret, line, idASET, FIXNUM_INC(argc, 1), INT2FIX(flag));
	    }
	    ADD_INSN(ret, line, pop);
	    ADD_INSNL(ret, line, jump, lfin);
	    ADD_LABEL(ret, label);
	    if (!popped) {
		ADD_INSN1(ret, line, setn, FIXNUM_INC(argc, 2+boff));
	    }
	    ADD_INSN1(ret, line, adjuststack, FIXNUM_INC(argc, 2+boff));
	    ADD_LABEL(ret, lfin);
	}
	else {
	    COMPILE(ret, "NODE_OP_ASGN1 args->body: ", node->nd_args->nd_body);
	    ADD_SEND(ret, line, id, INT2FIX(1));
	    if (!popped) {
		ADD_INSN1(ret, line, setn, FIXNUM_INC(argc, 2+boff));
	    }
	    if (flag & VM_CALL_ARGS_SPLAT) {
		ADD_INSN1(ret, line, newarray, INT2FIX(1));
		if (boff > 0) {
		    ADD_INSN1(ret, line, dupn, INT2FIX(3));
		    ADD_INSN(ret, line, swap);
		    ADD_INSN(ret, line, pop);
		}
		ADD_INSN(ret, line, concatarray);
		if (boff > 0) {
		    ADD_INSN1(ret, line, setn, INT2FIX(3));
		    ADD_INSN(ret, line, pop);
		    ADD_INSN(ret, line, pop);
		}
		ADD_SEND_WITH_FLAG(ret, line, idASET, argc, INT2FIX(flag));
	    }
	    else {
		if (boff > 0)
		    ADD_INSN(ret, line, swap);
		ADD_SEND_WITH_FLAG(ret, line, idASET, FIXNUM_INC(argc, 1), INT2FIX(flag));
	    }
	    ADD_INSN(ret, line, pop);
	}

	break;
      }
      case NODE_OP_ASGN2:{
	ID atype = node->nd_next->nd_mid;
	ID vid = node->nd_next->nd_vid, aid = rb_id_attrset(vid);
	VALUE asgnflag;
	LABEL *lfin = NEW_LABEL(line);
	LABEL *lcfin = NEW_LABEL(line);
	LABEL *lskip = 0;
	/*
	  class C; attr_accessor :c; end
	  r = C.new
	  r.a &&= v # asgn2

	  eval r    # r
	  dup       # r r
	  eval r.a  # r o

	  # or
	  dup       # r o o
	  if lcfin  # r o
	  pop       # r
	  eval v    # r v
	  swap      # v r
	  topn 1    # v r v
	  send a=   # v ?
	  jump lfin # v ?

	  lcfin:      # r o
	  swap      # o r

	  lfin:       # o ?
	  pop       # o

	  # and
	  dup       # r o o
	  unless lcfin
	  pop       # r
	  eval v    # r v
	  swap      # v r
	  topn 1    # v r v
	  send a=   # v ?
	  jump lfin # v ?

	  # others
	  eval v    # r o v
	  send ??   # r w
	  send a=   # w

	*/

	asgnflag = COMPILE_RECV(ret, "NODE_OP_ASGN2#recv", node);
	if (node->nd_next->nd_aid) {
	    lskip = NEW_LABEL(line);
	    ADD_INSN(ret, line, dup);
	    ADD_INSNL(ret, line, branchnil, lskip);
	}
	ADD_INSN(ret, line, dup);
	ADD_SEND(ret, line, vid, INT2FIX(0));

	if (atype == 0 || atype == 1) {	/* 0: OR or 1: AND */
	    ADD_INSN(ret, line, dup);
	    if (atype == 0) {
		ADD_INSNL(ret, line, branchif, lcfin);
	    }
	    else {
		ADD_INSNL(ret, line, branchunless, lcfin);
	    }
	    ADD_INSN(ret, line, pop);
	    COMPILE(ret, "NODE_OP_ASGN2 val", node->nd_value);
	    ADD_INSN(ret, line, swap);
	    ADD_INSN1(ret, line, topn, INT2FIX(1));
	    ADD_SEND_WITH_FLAG(ret, line, aid, INT2FIX(1), INT2FIX(asgnflag));
	    ADD_INSNL(ret, line, jump, lfin);

	    ADD_LABEL(ret, lcfin);
	    ADD_INSN(ret, line, swap);

	    ADD_LABEL(ret, lfin);
	    ADD_INSN(ret, line, pop);
	    if (lskip) {
		ADD_LABEL(ret, lskip);
	    }
	    if (popped) {
		/* we can apply more optimize */
		ADD_INSN(ret, line, pop);
	    }
	}
	else {
	    COMPILE(ret, "NODE_OP_ASGN2 val", node->nd_value);
	    ADD_SEND(ret, line, atype, INT2FIX(1));
	    if (!popped) {
		ADD_INSN(ret, line, swap);
		ADD_INSN1(ret, line, topn, INT2FIX(1));
	    }
	    ADD_SEND_WITH_FLAG(ret, line, aid, INT2FIX(1), INT2FIX(asgnflag));
	    ADD_INSN(ret, line, pop);
	    if (lskip) {
		ADD_LABEL(ret, lskip);
	    }
	}
	break;
      }
      case NODE_OP_CDECL: {
	LABEL *lfin = 0;
	LABEL *lassign = 0;
	ID mid;

	switch (nd_type(node->nd_head)) {
	  case NODE_COLON3:
	    ADD_INSN1(ret, line, putobject, rb_cObject);
	    break;
	  case NODE_COLON2:
	    COMPILE(ret, "NODE_OP_CDECL/colon2#nd_head", node->nd_head->nd_head);
	    break;
	  default:
	    COMPILE_ERROR(ERROR_ARGS "%s: invalid node in NODE_OP_CDECL",
			  ruby_node_name(nd_type(node->nd_head)));
	    debug_node_end();
	    return COMPILE_NG;
	}
	mid = node->nd_head->nd_mid;
	/* cref */
	if (node->nd_aid == 0) {
	    lassign = NEW_LABEL(line);
	    ADD_INSN(ret, line, dup); /* cref cref */
	    ADD_INSN3(ret, line, defined, INT2FIX(DEFINED_CONST),
		      ID2SYM(mid), Qfalse); /* cref bool */
	    ADD_INSNL(ret, line, branchunless, lassign); /* cref */
	}
	ADD_INSN(ret, line, dup); /* cref cref */
	ADD_INSN1(ret, line, getconstant, ID2SYM(mid)); /* cref obj */

	if (node->nd_aid == 0 || node->nd_aid == 1) {
	    lfin = NEW_LABEL(line);
	    if (!popped) ADD_INSN(ret, line, dup); /* cref [obj] obj */
	    if (node->nd_aid == 0)
		ADD_INSNL(ret, line, branchif, lfin);
	    else
		ADD_INSNL(ret, line, branchunless, lfin);
	    /* cref [obj] */
	    if (!popped) ADD_INSN(ret, line, pop); /* cref */
	    if (lassign) ADD_LABEL(ret, lassign);
	    COMPILE(ret, "NODE_OP_CDECL#nd_value", node->nd_value);
	    /* cref value */
	    if (popped)
		ADD_INSN1(ret, line, topn, INT2FIX(1)); /* cref value cref */
	    else {
		ADD_INSN1(ret, line, dupn, INT2FIX(2)); /* cref value cref value */
		ADD_INSN(ret, line, swap); /* cref value value cref */
	    }
	    ADD_INSN1(ret, line, setconstant, ID2SYM(mid)); /* cref [value] */
	    ADD_LABEL(ret, lfin);			    /* cref [value] */
	    if (!popped) ADD_INSN(ret, line, swap); /* [value] cref */
	    ADD_INSN(ret, line, pop); /* [value] */
	}
	else {
	    COMPILE(ret, "NODE_OP_CDECL#nd_value", node->nd_value);
	    /* cref obj value */
	    ADD_CALL(ret, line, node->nd_aid, INT2FIX(1));
	    /* cref value */
	    ADD_INSN(ret, line, swap); /* value cref */
	    if (!popped) {
		ADD_INSN1(ret, line, topn, INT2FIX(1)); /* value cref value */
		ADD_INSN(ret, line, swap); /* value value cref */
	    }
	    ADD_INSN1(ret, line, setconstant, ID2SYM(mid));
	}
	break;
      }
      case NODE_OP_ASGN_AND:
      case NODE_OP_ASGN_OR:{
	LABEL *lfin = NEW_LABEL(line);
	LABEL *lassign;

	if (nd_type(node) == NODE_OP_ASGN_OR) {
	    LABEL *lfinish[2];
	    lfinish[0] = lfin;
	    lfinish[1] = 0;
	    defined_expr(iseq, ret, node->nd_head, lfinish, Qfalse);
	    lassign = lfinish[1];
	    if (!lassign) {
		lassign = NEW_LABEL(line);
	    }
	    ADD_INSNL(ret, line, branchunless, lassign);
	}
	else {
	    lassign = NEW_LABEL(line);
	}

	COMPILE(ret, "NODE_OP_ASGN_AND/OR#nd_head", node->nd_head);
	ADD_INSN(ret, line, dup);

	if (nd_type(node) == NODE_OP_ASGN_AND) {
	    ADD_INSNL(ret, line, branchunless, lfin);
	}
	else {
	    ADD_INSNL(ret, line, branchif, lfin);
	}

	ADD_INSN(ret, line, pop);
	ADD_LABEL(ret, lassign);
	COMPILE(ret, "NODE_OP_ASGN_AND/OR#nd_value", node->nd_value);
	ADD_LABEL(ret, lfin);

	if (popped) {
	    /* we can apply more optimize */
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_CALL:
	/* optimization shortcut
	 *   "literal".freeze -> opt_str_freeze("literal")
	 */
	if (node->nd_recv && nd_type(node->nd_recv) == NODE_STR &&
	    node->nd_mid == idFreeze && node->nd_args == NULL &&
	    ISEQ_COMPILE_DATA(iseq)->current_block == NULL &&
	    ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction) {
	    VALUE str = rb_fstring(node->nd_recv->nd_lit);
	    iseq_add_mark_object(iseq, str);
	    ADD_INSN1(ret, line, opt_str_freeze, str);
	    if (popped) {
		ADD_INSN(ret, line, pop);
	    }
	    break;
	}
	/* optimization shortcut
	 *   obj["literal"] -> opt_aref_with(obj, "literal")
	 */
	if (node->nd_mid == idAREF && !private_recv_p(node) && node->nd_args &&
	    nd_type(node->nd_args) == NODE_ARRAY && node->nd_args->nd_alen == 1 &&
	    nd_type(node->nd_args->nd_head) == NODE_STR &&
	    ISEQ_COMPILE_DATA(iseq)->current_block == NULL &&
	    ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction) {
	    VALUE str = rb_fstring(node->nd_args->nd_head->nd_lit);
	    node->nd_args->nd_head->nd_lit = str;
	    COMPILE(ret, "recv", node->nd_recv);
	    ADD_INSN3(ret, line, opt_aref_with,
		      new_callinfo(iseq, idAREF, 1, 0, NULL, FALSE),
		      NULL/* CALL_CACHE */, str);
	    if (popped) {
		ADD_INSN(ret, line, pop);
	    }
	    break;
	}
      case NODE_QCALL:
      case NODE_FCALL:
      case NODE_VCALL:{		/* VCALL: variable or call */
	/*
	  call:  obj.method(...)
	  fcall: func(...)
	  vcall: func
	*/
	DECL_ANCHOR(recv);
	DECL_ANCHOR(args);
	LABEL *lskip = 0;
	ID mid = node->nd_mid;
	VALUE argc;
	unsigned int flag = 0;
	struct rb_call_info_kw_arg *keywords = NULL;
	const rb_iseq_t *parent_block = ISEQ_COMPILE_DATA(iseq)->current_block;
	ISEQ_COMPILE_DATA(iseq)->current_block = NULL;

	INIT_ANCHOR(recv);
	INIT_ANCHOR(args);
#if SUPPORT_JOKE
	if (nd_type(node) == NODE_VCALL) {
	    ID id_bitblt;
	    ID id_answer;

	    CONST_ID(id_bitblt, "bitblt");
	    CONST_ID(id_answer, "the_answer_to_life_the_universe_and_everything");

	    if (mid == id_bitblt) {
		ADD_INSN(ret, line, bitblt);
		break;
	    }
	    else if (mid == id_answer) {
		ADD_INSN(ret, line, answer);
		break;
	    }
	}
	/* only joke */
	{
	    ID goto_id;
	    ID label_id;

	    CONST_ID(goto_id, "__goto__");
	    CONST_ID(label_id, "__label__");

	    if (nd_type(node) == NODE_FCALL &&
		(mid == goto_id || mid == label_id)) {
		LABEL *label;
		st_data_t data;
		st_table *labels_table = ISEQ_COMPILE_DATA(iseq)->labels_table;
		ID label_name;

		if (!labels_table) {
		    labels_table = st_init_numtable();
		    ISEQ_COMPILE_DATA(iseq)->labels_table = labels_table;
		}
		if (nd_type(node->nd_args->nd_head) == NODE_LIT &&
		    SYMBOL_P(node->nd_args->nd_head->nd_lit)) {

		    label_name = SYM2ID(node->nd_args->nd_head->nd_lit);
		    if (!st_lookup(labels_table, (st_data_t)label_name, &data)) {
			label = NEW_LABEL(line);
			label->position = line;
			st_insert(labels_table, (st_data_t)label_name, (st_data_t)label);
		    }
		    else {
			label = (LABEL *)data;
		    }
		}
		else {
		    COMPILE_ERROR(ERROR_ARGS "invalid goto/label format");
		}


		if (mid == goto_id) {
		    ADD_INSNL(ret, line, jump, label);
		}
		else {
		    ADD_LABEL(ret, label);
		}
		break;
	    }
	}
#endif
	/* receiver */
	if (type == NODE_CALL || type == NODE_QCALL) {
	    COMPILE(recv, "recv", node->nd_recv);
	    if (type == NODE_QCALL) {
		lskip = NEW_LABEL(line);
		ADD_INSN(recv, line, dup);
		ADD_INSNL(recv, line, branchnil, lskip);
	    }
	}
	else if (type == NODE_FCALL || type == NODE_VCALL) {
	    ADD_CALL_RECEIVER(recv, line);
	}

	/* args */
	if (nd_type(node) != NODE_VCALL) {
	    argc = setup_args(iseq, args, node->nd_args, &flag, &keywords);
	}
	else {
	    argc = INT2FIX(0);
	}

	ADD_SEQ(ret, recv);
	ADD_SEQ(ret, args);

	debugp_param("call args argc", argc);
	debugp_param("call method", ID2SYM(mid));

	switch (nd_type(node)) {
	  case NODE_VCALL:
	    flag |= VM_CALL_VCALL;
	    /* VCALL is funcall, so fall through */
	  case NODE_FCALL:
	    flag |= VM_CALL_FCALL;
	}

	ADD_SEND_R(ret, line, mid, argc, parent_block, INT2FIX(flag), keywords);

	if (lskip) {
	    ADD_LABEL(ret, lskip);
	}
	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_SUPER:
      case NODE_ZSUPER:{
	DECL_ANCHOR(args);
	int argc;
	unsigned int flag = 0;
	struct rb_call_info_kw_arg *keywords = NULL;
	const rb_iseq_t *parent_block = ISEQ_COMPILE_DATA(iseq)->current_block;

	INIT_ANCHOR(args);
	ISEQ_COMPILE_DATA(iseq)->current_block = NULL;
	if (nd_type(node) == NODE_SUPER) {
	    VALUE vargc = setup_args(iseq, args, node->nd_args, &flag, &keywords);
	    argc = FIX2INT(vargc);
	}
	else {
	    /* NODE_ZSUPER */
	    int i;
	    const rb_iseq_t *liseq = iseq->body->local_iseq;
	    int lvar_level = get_lvar_level(iseq);

	    argc = liseq->body->param.lead_num;

	    /* normal arguments */
	    for (i = 0; i < liseq->body->param.lead_num; i++) {
		int idx = liseq->body->local_table_size - i;
		ADD_GETLOCAL(args, line, idx, lvar_level);
	    }

	    if (liseq->body->param.flags.has_opt) {
		/* optional arguments */
		int j;
		for (j = 0; j < liseq->body->param.opt_num; j++) {
		    int idx = liseq->body->local_table_size - (i + j);
		    ADD_GETLOCAL(args, line, idx, lvar_level);
		}
		i += j;
		argc = i;
	    }
	    if (liseq->body->param.flags.has_rest) {
		/* rest argument */
		int idx = liseq->body->local_table_size - liseq->body->param.rest_start;
		ADD_GETLOCAL(args, line, idx, lvar_level);

		argc = liseq->body->param.rest_start + 1;
		flag |= VM_CALL_ARGS_SPLAT;
	    }
	    if (liseq->body->param.flags.has_post) {
		/* post arguments */
		int post_len = liseq->body->param.post_num;
		int post_start = liseq->body->param.post_start;

		if (liseq->body->param.flags.has_rest) {
		    int j;
		    for (j=0; j<post_len; j++) {
			int idx = liseq->body->local_table_size - (post_start + j);
			ADD_GETLOCAL(args, line, idx, lvar_level);
		    }
		    ADD_INSN1(args, line, newarray, INT2FIX(j));
		    ADD_INSN (args, line, concatarray);
		    /* argc is settled at above */
		}
		else {
		    int j;
		    for (j=0; j<post_len; j++) {
			int idx = liseq->body->local_table_size - (post_start + j);
			ADD_GETLOCAL(args, line, idx, lvar_level);
		    }
		    argc = post_len + post_start;
		}
	    }

	    if (liseq->body->param.flags.has_kw) { /* TODO: support keywords */
		int local_size = liseq->body->local_table_size;
		argc++;

		ADD_INSN1(args, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));

		if (liseq->body->param.flags.has_kwrest) {
		    int idx = liseq->body->local_table_size - liseq->body->param.keyword->rest_start;
		    ADD_GETLOCAL(args, line, idx, lvar_level);
		    ADD_SEND (args, line, rb_intern("dup"), INT2FIX(0));
		}
		else {
		    ADD_INSN1(args, line, newhash, INT2FIX(0));
		}
		for (i = 0; i < liseq->body->param.keyword->num; ++i) {
		    ID id = liseq->body->param.keyword->table[i];
		    int idx = local_size - get_local_var_idx(liseq, id);
		    ADD_INSN1(args, line, putobject, ID2SYM(id));
		    ADD_GETLOCAL(args, line, idx, lvar_level);
		}
		ADD_SEND(args, line, id_core_hash_merge_ptr, INT2FIX(i * 2 + 1));
		if (liseq->body->param.flags.has_rest) {
		    ADD_INSN1(args, line, newarray, INT2FIX(1));
		    ADD_INSN (args, line, concatarray);
		    --argc;
		}
	    }
	    else if (liseq->body->param.flags.has_kwrest) {
		int idx = liseq->body->local_table_size - liseq->body->param.keyword->rest_start;
		ADD_GETLOCAL(args, line, idx, lvar_level);

		ADD_SEND (args, line, rb_intern("dup"), INT2FIX(0));
		if (liseq->body->param.flags.has_rest) {
		    ADD_INSN1(args, line, newarray, INT2FIX(1));
		    ADD_INSN (args, line, concatarray);
		}
		else {
		    argc++;
		}
	    }
	}

	/* dummy receiver */
	ADD_INSN1(ret, line, putobject, nd_type(node) == NODE_ZSUPER ? Qfalse : Qtrue);
	ADD_SEQ(ret, args);
	ADD_INSN3(ret, line, invokesuper,
		  new_callinfo(iseq, 0, argc, flag | VM_CALL_SUPER | VM_CALL_FCALL, keywords, parent_block != NULL),
		  Qnil, /* CALL_CACHE */
		  parent_block);

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_ARRAY:{
	compile_array_(iseq, ret, node, COMPILE_ARRAY_TYPE_ARRAY, NULL, popped);
	break;
      }
      case NODE_ZARRAY:{
	if (!popped) {
	    ADD_INSN1(ret, line, newarray, INT2FIX(0));
	}
	break;
      }
      case NODE_VALUES:{
	NODE *n = node;
	while (n) {
	    COMPILE(ret, "values item", n->nd_head);
	    n = n->nd_next;
	}
	ADD_INSN1(ret, line, newarray, INT2FIX(node->nd_alen));
	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_HASH:{
	DECL_ANCHOR(list);
	int type = node->nd_head ? nd_type(node->nd_head) : NODE_ZARRAY;

	INIT_ANCHOR(list);
	switch (type) {
	  case NODE_ARRAY:
	    compile_array(iseq, list, node->nd_head, COMPILE_ARRAY_TYPE_HASH);
	    ADD_SEQ(ret, list);
	    break;

	  case NODE_ZARRAY:
	    ADD_INSN1(ret, line, newhash, INT2FIX(0));
	    break;

	  default:
	    compile_bug(ERROR_ARGS_AT(node->nd_head) "can't make hash with this node: %s",
			ruby_node_name(type));
	}

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_RETURN:{
	rb_iseq_t *is = iseq;

	if (is) {
	    enum iseq_type type = is->body->type;
	    const rb_iseq_t *parent_iseq = is->body->parent_iseq;
	    enum iseq_type parent_type = parent_iseq ? parent_iseq->body->type : type;

	    if (type == ISEQ_TYPE_TOP || type == ISEQ_TYPE_MAIN ||
		((type == ISEQ_TYPE_RESCUE || type == ISEQ_TYPE_ENSURE) &&
		 (parent_type == ISEQ_TYPE_TOP || parent_type == ISEQ_TYPE_MAIN))) {
		ADD_INSN(ret, line, putnil);
		ADD_INSN(ret, line, leave);
	    }
	    else {
		LABEL *splabel = 0;

		if (type == ISEQ_TYPE_METHOD) {
		    splabel = NEW_LABEL(0);
		    ADD_LABEL(ret, splabel);
		    ADD_ADJUST(ret, line, 0);
		}

		COMPILE(ret, "return nd_stts (return val)", node->nd_stts);

		if (type == ISEQ_TYPE_METHOD) {
		    add_ensure_iseq(ret, iseq, 1);
		    ADD_TRACE(ret, line, RUBY_EVENT_RETURN);
		    ADD_INSN(ret, line, leave);
		    ADD_ADJUST_RESTORE(ret, splabel);

		    if (!popped) {
			ADD_INSN(ret, line, putnil);
		    }
		}
		else {
		    ADD_INSN1(ret, line, throw, INT2FIX(TAG_RETURN));
		    if (popped) {
			ADD_INSN(ret, line, pop);
		    }
		}
	    }
	}
	break;
      }
      case NODE_YIELD:{
	DECL_ANCHOR(args);
	VALUE argc;
	unsigned int flag = 0;
	struct rb_call_info_kw_arg *keywords = NULL;

	INIT_ANCHOR(args);
	if (iseq->body->type == ISEQ_TYPE_TOP) {
	    COMPILE_ERROR(ERROR_ARGS "Invalid yield");
	    debug_node_end();
	    return COMPILE_NG;
	}

	if (node->nd_head) {
	    argc = setup_args(iseq, args, node->nd_head, &flag, &keywords);
	}
	else {
	    argc = INT2FIX(0);
	}

	ADD_SEQ(ret, args);
	ADD_INSN1(ret, line, invokeblock, new_callinfo(iseq, 0, FIX2INT(argc), flag, keywords, FALSE));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_LVAR:{
	if (!popped) {
	    ID id = node->nd_vid;
	    int idx = iseq->body->local_iseq->body->local_table_size - get_local_var_idx(iseq, id);

	    debugs("id: %"PRIsVALUE" idx: %d\n", rb_id2str(id), idx);
	    ADD_GETLOCAL(ret, line, idx, get_lvar_level(iseq));
	}
	break;
      }
      case NODE_DVAR:{
	int lv, idx, ls;
	debugi("nd_vid", node->nd_vid);
	if (!popped) {
	    idx = get_dyna_var_idx(iseq, node->nd_vid, &lv, &ls);
	    if (idx < 0) {
		compile_bug(ERROR_ARGS "unknown dvar (%"PRIsVALUE")",
			    rb_id2str(node->nd_vid));
	    }
	    ADD_GETLOCAL(ret, line, ls - idx, lv);
	}
	break;
      }
      case NODE_GVAR:{
	ADD_INSN1(ret, line, getglobal,
		  ((VALUE)node->nd_entry | 1));
	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_IVAR:{
	debugi("nd_vid", node->nd_vid);
	if (!popped) {
	    ADD_INSN2(ret, line, getinstancevariable,
		      ID2SYM(node->nd_vid),
		      get_ivar_ic_value(iseq,node->nd_vid));
	}
	break;
      }
      case NODE_CONST:{
	debugi("nd_vid", node->nd_vid);

	if (ISEQ_COMPILE_DATA(iseq)->option->inline_const_cache) {
	    LABEL *lend = NEW_LABEL(line);
	    int ic_index = iseq->body->is_size++;

	    ADD_INSN2(ret, line, getinlinecache, lend, INT2FIX(ic_index));
	    ADD_INSN1(ret, line, getconstant, ID2SYM(node->nd_vid));
	    ADD_INSN1(ret, line, setinlinecache, INT2FIX(ic_index));
	    ADD_LABEL(ret, lend);
	}
	else {
	    ADD_INSN(ret, line, putnil);
	    ADD_INSN1(ret, line, getconstant, ID2SYM(node->nd_vid));
	}

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_CVAR:{
	if (!popped) {
	    ADD_INSN1(ret, line, getclassvariable,
		      ID2SYM(node->nd_vid));
	}
	break;
      }
      case NODE_NTH_REF:{
        if (!popped) {
	    if (!node->nd_nth) {
		ADD_INSN(ret, line, putnil);
		break;
	    }
	    ADD_INSN2(ret, line, getspecial, INT2FIX(1) /* '~'  */,
		      INT2FIX(node->nd_nth << 1));
	}
	break;
      }
      case NODE_BACK_REF:{
	if (!popped) {
	    ADD_INSN2(ret, line, getspecial, INT2FIX(1) /* '~' */,
		      INT2FIX(0x01 | (node->nd_nth << 1)));
	}
	break;
      }
      case NODE_MATCH:
      case NODE_MATCH2:
      case NODE_MATCH3:{
	DECL_ANCHOR(recv);
	DECL_ANCHOR(val);

	INIT_ANCHOR(recv);
	INIT_ANCHOR(val);
	switch (nd_type(node)) {
	  case NODE_MATCH:
	    ADD_INSN1(recv, line, putobject, node->nd_lit);
	    ADD_INSN2(val, line, getspecial, INT2FIX(0),
		      INT2FIX(0));
	    break;
	  case NODE_MATCH2:
	    COMPILE(recv, "receiver", node->nd_recv);
	    COMPILE(val, "value", node->nd_value);
	    break;
	  case NODE_MATCH3:
	    COMPILE(recv, "receiver", node->nd_value);
	    COMPILE(val, "value", node->nd_recv);
	    break;
	}

	if (ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction) {
	    /* TODO: detect by node */
	    if (recv->last == recv->anchor.next &&
		INSN_OF(recv->last) == BIN(putobject) &&
		nd_type(node) == NODE_MATCH2) {
		ADD_SEQ(ret, val);
		ADD_INSN1(ret, line, opt_regexpmatch1,
			  OPERAND_AT(recv->last, 0));
	    }
	    else {
		ADD_SEQ(ret, recv);
		ADD_SEQ(ret, val);
		ADD_INSN2(ret, line, opt_regexpmatch2, new_callinfo(iseq, idEqTilde, 1, 0, NULL, FALSE), Qnil);
	    }
	}
	else {
	    ADD_SEQ(ret, recv);
	    ADD_SEQ(ret, val);
	    ADD_SEND(ret, line, idEqTilde, INT2FIX(1));
	}

	if (node->nd_args) {
	    compile_named_capture_assign(iseq, ret, node->nd_args);
	}

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_LIT:{
	debugp_param("lit", node->nd_lit);
	if (!popped) {
	    ADD_INSN1(ret, line, putobject, node->nd_lit);
	}
	break;
      }
      case NODE_STR:{
	debugp_param("nd_lit", node->nd_lit);
	if (!popped) {
	    node->nd_lit = rb_fstring(node->nd_lit);
	    if (!ISEQ_COMPILE_DATA(iseq)->option->frozen_string_literal) {
		ADD_INSN1(ret, line, putstring, node->nd_lit);
	    }
	    else {
		if (ISEQ_COMPILE_DATA(iseq)->option->debug_frozen_string_literal || RTEST(ruby_debug)) {
		    VALUE debug_info = rb_ary_new_from_args(2, iseq->body->location.path, INT2FIX(line));
		    VALUE str = rb_str_dup(node->nd_lit);
		    rb_ivar_set(str, id_debug_created_info, rb_obj_freeze(debug_info));
		    ADD_INSN1(ret, line, putobject, rb_obj_freeze(str));
		    iseq_add_mark_object_compile_time(iseq, str);
		}
		else {
		    ADD_INSN1(ret, line, putobject, node->nd_lit);
		}
	    }
	}
	break;
      }
      case NODE_DSTR:{
	compile_dstr(iseq, ret, node);

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	else {
	    if (ISEQ_COMPILE_DATA(iseq)->option->frozen_string_literal) {
		VALUE debug_info = Qnil;
		if (ISEQ_COMPILE_DATA(iseq)->option->debug_frozen_string_literal || RTEST(ruby_debug)) {
		    debug_info = rb_ary_new_from_args(2, iseq->body->location.path, INT2FIX(line));
		    iseq_add_mark_object_compile_time(iseq, rb_obj_freeze(debug_info));
		}
		ADD_INSN1(ret, line, freezestring, debug_info);
	    }
	}
	break;
      }
      case NODE_XSTR:{
	node->nd_lit = rb_fstring(node->nd_lit);
	ADD_CALL_RECEIVER(ret, line);
	ADD_INSN1(ret, line, putobject, node->nd_lit);
	ADD_CALL(ret, line, idBackquote, INT2FIX(1));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_DXSTR:{
	ADD_CALL_RECEIVER(ret, line);
	compile_dstr(iseq, ret, node);
	ADD_CALL(ret, line, idBackquote, INT2FIX(1));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_EVSTR:{
	COMPILE(ret, "nd_body", node->nd_body);

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	else {
	    ADD_INSN(ret, line, tostring);
	}
	break;
      }
      case NODE_DREGX:{
	compile_dregx(iseq, ret, node);

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_DREGX_ONCE:{
	int ic_index = iseq->body->is_size++;
	NODE *dregx_node = NEW_NODE(NODE_DREGX, node->u1.value, node->u2.value, node->u3.value);
	NODE *block_node = NEW_NODE(NODE_SCOPE, 0, dregx_node, 0);
	const rb_iseq_t * block_iseq = NEW_CHILD_ISEQ(block_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, line);

	ADD_INSN2(ret, line, once, block_iseq, INT2FIX(ic_index));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_ARGSCAT:{
	if (popped) {
	    COMPILE(ret, "argscat head", node->nd_head);
	    ADD_INSN1(ret, line, splatarray, Qfalse);
	    ADD_INSN(ret, line, pop);
	    COMPILE(ret, "argscat body", node->nd_body);
	    ADD_INSN1(ret, line, splatarray, Qfalse);
	    ADD_INSN(ret, line, pop);
	}
	else {
	    COMPILE(ret, "argscat head", node->nd_head);
	    COMPILE(ret, "argscat body", node->nd_body);
	    ADD_INSN(ret, line, concatarray);
	}
	break;
      }
      case NODE_ARGSPUSH:{
	if (popped) {
	    COMPILE(ret, "arsgpush head", node->nd_head);
	    ADD_INSN1(ret, line, splatarray, Qfalse);
	    ADD_INSN(ret, line, pop);
	    COMPILE_(ret, "argspush body", node->nd_body, popped);
	}
	else {
	    COMPILE(ret, "arsgpush head", node->nd_head);
	    COMPILE_(ret, "argspush body", node->nd_body, popped);
	    ADD_INSN1(ret, line, newarray, INT2FIX(1));
	    ADD_INSN(ret, line, concatarray);
	}
	break;
      }
      case NODE_SPLAT:{
	COMPILE(ret, "splat", node->nd_head);
	ADD_INSN1(ret, line, splatarray, Qtrue);

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_DEFN:{
	const rb_iseq_t *method_iseq = NEW_ISEQ(node->nd_defn,
						rb_id2str(node->nd_mid),
						ISEQ_TYPE_METHOD, line);

	debugp_param("defn/iseq", rb_iseqw_new(method_iseq));

	ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
	ADD_INSN1(ret, line, putobject, ID2SYM(node->nd_mid));
	ADD_INSN1(ret, line, putiseq, method_iseq);
	ADD_SEND (ret, line, id_core_define_method, INT2FIX(2));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}

	break;
      }
      case NODE_DEFS:{
	const rb_iseq_t * singleton_method = NEW_ISEQ(node->nd_defn,
						      rb_id2str(node->nd_mid),
						      ISEQ_TYPE_METHOD, line);

	debugp_param("defs/iseq", rb_iseqw_new(singleton_method));

	ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
	COMPILE(ret, "defs: recv", node->nd_recv);
	ADD_INSN1(ret, line, putobject, ID2SYM(node->nd_mid));
	ADD_INSN1(ret, line, putiseq, singleton_method);
	ADD_SEND (ret, line, id_core_define_singleton_method, INT2FIX(3));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_ALIAS:{
	ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
	ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CBASE));
	COMPILE(ret, "alias arg1", node->u1.node);
	COMPILE(ret, "alias arg2", node->u2.node);
	ADD_SEND(ret, line, id_core_set_method_alias, INT2FIX(3));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_VALIAS:{
	ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
	ADD_INSN1(ret, line, putobject, ID2SYM(node->u1.id));
	ADD_INSN1(ret, line, putobject, ID2SYM(node->u2.id));
	ADD_SEND(ret, line, id_core_set_variable_alias, INT2FIX(2));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_UNDEF:{
	ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
	ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CBASE));
	COMPILE(ret, "undef arg", node->u2.node);
	ADD_SEND(ret, line, id_core_undef_method, INT2FIX(2));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_CLASS:{
	const rb_iseq_t *class_iseq = NEW_CHILD_ISEQ(node->nd_body,
						     rb_sprintf("<class:%"PRIsVALUE">", rb_id2str(node->nd_cpath->nd_mid)),
						     ISEQ_TYPE_CLASS, line);
	VALUE noscope = compile_cpath(ret, iseq, node->nd_cpath);
	int flags = VM_DEFINECLASS_TYPE_CLASS;

	if (!noscope) flags |= VM_DEFINECLASS_FLAG_SCOPED;
	if (node->nd_super) flags |= VM_DEFINECLASS_FLAG_HAS_SUPERCLASS;
	COMPILE(ret, "super", node->nd_super);
	ADD_INSN3(ret, line, defineclass, ID2SYM(node->nd_cpath->nd_mid), class_iseq, INT2FIX(flags));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_MODULE:{
        const rb_iseq_t *module_iseq = NEW_CHILD_ISEQ(node->nd_body,
						      rb_sprintf("<module:%"PRIsVALUE">", rb_id2str(node->nd_cpath->nd_mid)),
						      ISEQ_TYPE_CLASS, line);
	VALUE noscope = compile_cpath(ret, iseq, node->nd_cpath);
	int flags = VM_DEFINECLASS_TYPE_MODULE;

	if (!noscope) flags |= VM_DEFINECLASS_FLAG_SCOPED;
	ADD_INSN (ret, line, putnil); /* dummy */
	ADD_INSN3(ret, line, defineclass, ID2SYM(node->nd_cpath->nd_mid), module_iseq, INT2FIX(flags));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_SCLASS:{
	ID singletonclass;
	const rb_iseq_t *singleton_class = NEW_ISEQ(node->nd_body, rb_str_new2("singleton class"),
						    ISEQ_TYPE_CLASS, line);

	COMPILE(ret, "sclass#recv", node->nd_recv);
	ADD_INSN (ret, line, putnil);
	CONST_ID(singletonclass, "singletonclass");
	ADD_INSN3(ret, line, defineclass,
		  ID2SYM(singletonclass), singleton_class,
		  INT2FIX(VM_DEFINECLASS_TYPE_SINGLETON_CLASS));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_COLON2:{
	if (rb_is_const_id(node->nd_mid)) {
	    /* constant */
	    LABEL *lend = NEW_LABEL(line);
	    int ic_index = iseq->body->is_size++;

	    DECL_ANCHOR(pref);
	    DECL_ANCHOR(body);

	    INIT_ANCHOR(pref);
	    INIT_ANCHOR(body);
	    compile_colon2(iseq, node, pref, body);
	    if (LIST_SIZE_ZERO(pref)) {
		if (ISEQ_COMPILE_DATA(iseq)->option->inline_const_cache) {
		    ADD_INSN2(ret, line, getinlinecache, lend, INT2FIX(ic_index));
		}
		else {
		    ADD_INSN(ret, line, putnil);
		}

		ADD_SEQ(ret, body);

		if (ISEQ_COMPILE_DATA(iseq)->option->inline_const_cache) {
		    ADD_INSN1(ret, line, setinlinecache, INT2FIX(ic_index));
		    ADD_LABEL(ret, lend);
		}
	    }
	    else {
		ADD_SEQ(ret, pref);
		ADD_SEQ(ret, body);
	    }
	}
	else {
	    /* function call */
	    ADD_CALL_RECEIVER(ret, line);
	    COMPILE(ret, "colon2#nd_head", node->nd_head);
	    ADD_CALL(ret, line, node->nd_mid, INT2FIX(1));
	}
	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_COLON3:{
	LABEL *lend = NEW_LABEL(line);
	int ic_index = iseq->body->is_size++;

	debugi("colon3#nd_mid", node->nd_mid);

	/* add cache insn */
	if (ISEQ_COMPILE_DATA(iseq)->option->inline_const_cache) {
	    ADD_INSN2(ret, line, getinlinecache, lend, INT2FIX(ic_index));
	    ADD_INSN(ret, line, pop);
	}

	ADD_INSN1(ret, line, putobject, rb_cObject);
	ADD_INSN1(ret, line, getconstant, ID2SYM(node->nd_mid));

	if (ISEQ_COMPILE_DATA(iseq)->option->inline_const_cache) {
	    ADD_INSN1(ret, line, setinlinecache, INT2FIX(ic_index));
	    ADD_LABEL(ret, lend);
	}

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_DOT2:
      case NODE_DOT3:{
	int excl = type == NODE_DOT3;
	VALUE flag = INT2FIX(excl);
	NODE *b = node->nd_beg;
	NODE *e = node->nd_end;
	if (number_literal_p(b) && number_literal_p(e)) {
	    if (!popped) {
		VALUE val = rb_range_new(b->nd_lit, e->nd_lit, excl);
		iseq_add_mark_object_compile_time(iseq, val);
		ADD_INSN1(ret, line, putobject, val);
	    }
	    break;
	}
	COMPILE(ret, "min", (NODE *) node->nd_beg);
	COMPILE(ret, "max", (NODE *) node->nd_end);
	if (popped) {
	    ADD_INSN(ret, line, pop);
	    ADD_INSN(ret, line, pop);
	}
	else {
	    ADD_INSN1(ret, line, newrange, flag);
	}
	break;
      }
      case NODE_FLIP2:
      case NODE_FLIP3:{
	LABEL *lend = NEW_LABEL(line);
	LABEL *ltrue = NEW_LABEL(line);
	LABEL *lfalse = NEW_LABEL(line);
	compile_branch_condition(iseq, ret, node, ltrue, lfalse);
	ADD_INSNL(ret, line, jump, lend);
	ADD_LABEL(ret, ltrue);
	ADD_INSN1(ret, line, putobject, Qtrue);
	ADD_INSNL(ret, line, jump, lend);
	ADD_LABEL(ret, lfalse);
	ADD_INSN1(ret, line, putobject, Qfalse);
	ADD_LABEL(ret, lend);
	break;
      }
      case NODE_SELF:{
	if (!popped) {
	    ADD_INSN(ret, line, putself);
	}
	break;
      }
      case NODE_NIL:{
	if (!popped) {
	    ADD_INSN(ret, line, putnil);
	}
	break;
      }
      case NODE_TRUE:{
	if (!popped) {
	    ADD_INSN1(ret, line, putobject, Qtrue);
	}
	break;
      }
      case NODE_FALSE:{
	if (!popped) {
	    ADD_INSN1(ret, line, putobject, Qfalse);
	}
	break;
      }
      case NODE_ERRINFO:{
	if (!popped) {
	    if (iseq->body->type == ISEQ_TYPE_RESCUE) {
		ADD_GETLOCAL(ret, line, LVAR_ERRINFO, 0);
	    }
	    else {
		const rb_iseq_t *ip = iseq;
		int level = 0;
		while (ip) {
		    if (ip->body->type == ISEQ_TYPE_RESCUE) {
			break;
		    }
		    ip = ip->body->parent_iseq;
		    level++;
		}
		if (ip) {
		    ADD_GETLOCAL(ret, line, LVAR_ERRINFO, level);
		}
		else {
		    ADD_INSN(ret, line, putnil);
		}
	    }
	}
	break;
      }
      case NODE_DEFINED:{
	if (popped) break;
	if (!node->nd_head) {
	    VALUE str = rb_iseq_defined_string(DEFINED_NIL);
	    ADD_INSN1(ret, nd_line(node), putobject, str);
	}
	else {
	    LABEL *lfinish[2];
	    lfinish[0] = NEW_LABEL(line);
	    lfinish[1] = 0;
	    ADD_INSN(ret, line, putnil);
	    defined_expr(iseq, ret, node->nd_head, lfinish, Qtrue);
	    ADD_INSN(ret, line, swap);
	    ADD_INSN(ret, line, pop);
	    if (lfinish[1]) {
		ADD_LABEL(ret, lfinish[1]);
	    }
	    ADD_LABEL(ret, lfinish[0]);
	}
	break;
      }
      case NODE_POSTEXE:{
	/* compiled to:
	 *   ONCE{ rb_mRubyVMFrozenCore::core#set_postexe{ ... } }
	 */
	int is_index = iseq->body->is_size++;
	const rb_iseq_t *once_iseq = NEW_CHILD_ISEQ((NODE *)IFUNC_NEW(build_postexe_iseq, node->nd_body, 0),
						    make_name_for_block(iseq), ISEQ_TYPE_BLOCK, line);

	ADD_INSN2(ret, line, once, once_iseq, INT2FIX(is_index));

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_KW_ARG:
	{
	    LABEL *end_label = NEW_LABEL(nd_line(node));
	    NODE *default_value = node->nd_body->nd_value;

	    if (default_value == (NODE *)-1) {
		/* required argument. do nothing */
		compile_bug(ERROR_ARGS "unreachable");
	    }
	    else if (nd_type(default_value) == NODE_LIT ||
		     nd_type(default_value) == NODE_NIL ||
		     nd_type(default_value) == NODE_TRUE ||
		     nd_type(default_value) == NODE_FALSE) {
		compile_bug(ERROR_ARGS "unreachable");
	    }
	    else {
		/* if keywordcheck(_kw_bits, nth_keyword)
		 *   kw = default_value
		 * end
		 */
		int kw_bits_idx = iseq->body->local_table_size - iseq->body->param.keyword->bits_start;
		int keyword_idx = iseq->body->param.keyword->num;

		ADD_INSN2(ret, line, checkkeyword, INT2FIX(kw_bits_idx + VM_ENV_DATA_SIZE - 1), INT2FIX(keyword_idx));
		ADD_INSNL(ret, line, branchif, end_label);
		COMPILE_POPPED(ret, "keyword default argument", node->nd_body);
		ADD_LABEL(ret, end_label);
	    }

	    break;
	}
      case NODE_DSYM:{
	compile_dstr(iseq, ret, node);
	if (!popped) {
	    ADD_SEND(ret, line, idIntern, INT2FIX(0));
	}
	else {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      case NODE_ATTRASGN:{
	DECL_ANCHOR(recv);
	DECL_ANCHOR(args);
	unsigned int flag = 0;
	ID mid = node->nd_mid;
	LABEL *lskip = 0;
	VALUE argc;

	/* optimization shortcut
	 *   obj["literal"] = value -> opt_aset_with(obj, "literal", value)
	 */
	if (mid == idASET && !private_recv_p(node) && node->nd_args &&
	    nd_type(node->nd_args) == NODE_ARRAY && node->nd_args->nd_alen == 2 &&
	    nd_type(node->nd_args->nd_head) == NODE_STR &&
	    ISEQ_COMPILE_DATA(iseq)->current_block == NULL &&
	    ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction)
	{
	    VALUE str = rb_fstring(node->nd_args->nd_head->nd_lit);
	    node->nd_args->nd_head->nd_lit = str;
	    iseq_add_mark_object(iseq, str);
	    COMPILE(ret, "recv", node->nd_recv);
	    COMPILE(ret, "value", node->nd_args->nd_next->nd_head);
	    if (!popped) {
		ADD_INSN(ret, line, swap);
		ADD_INSN1(ret, line, topn, INT2FIX(1));
	    }
	    ADD_INSN3(ret, line, opt_aset_with,
		      new_callinfo(iseq, idASET, 2, 0, NULL, FALSE),
		      NULL/* CALL_CACHE */, str);
	    ADD_INSN(ret, line, pop);
	    break;
	}

	INIT_ANCHOR(recv);
	INIT_ANCHOR(args);
	argc = setup_args(iseq, args, node->nd_args, &flag, NULL);

	flag |= COMPILE_RECV(recv, "recv", node);

	debugp_param("argc", argc);
	debugp_param("nd_mid", ID2SYM(mid));

	if (!rb_is_attrset_id(mid)) {
	    /* safe nav attr */
	    mid = rb_id_attrset(mid);
	    ADD_INSN(recv, line, dup);
	    lskip = NEW_LABEL(line);
	    ADD_INSNL(recv, line, branchnil, lskip);
	}
	if (!popped) {
	    ADD_INSN(ret, line, putnil);
	    ADD_SEQ(ret, recv);
	    ADD_SEQ(ret, args);

	    if (flag & VM_CALL_ARGS_BLOCKARG) {
		ADD_INSN1(ret, line, topn, INT2FIX(1));
		if (flag & VM_CALL_ARGS_SPLAT) {
		    ADD_INSN1(ret, line, putobject, INT2FIX(-1));
		    ADD_SEND(ret, line, idAREF, INT2FIX(1));
		}
		ADD_INSN1(ret, line, setn, FIXNUM_INC(argc, 3));
		ADD_INSN (ret, line, pop);
	    }
	    else if (flag & VM_CALL_ARGS_SPLAT) {
		ADD_INSN(ret, line, dup);
		ADD_INSN1(ret, line, putobject, INT2FIX(-1));
		ADD_SEND(ret, line, idAREF, INT2FIX(1));
		ADD_INSN1(ret, line, setn, FIXNUM_INC(argc, 2));
		ADD_INSN (ret, line, pop);
	    }
	    else {
		ADD_INSN1(ret, line, setn, FIXNUM_INC(argc, 1));
	    }
	}
	else {
	    ADD_SEQ(ret, recv);
	    ADD_SEQ(ret, args);
	}
	ADD_SEND_WITH_FLAG(ret, line, mid, argc, INT2FIX(flag));
	if (lskip) ADD_LABEL(ret, lskip);
	ADD_INSN(ret, line, pop);

	break;
      }
      case NODE_PRELUDE:{
	const rb_compile_option_t *orig_opt = ISEQ_COMPILE_DATA(iseq)->option;
	if (node->nd_orig) {
	    rb_compile_option_t new_opt = *orig_opt;
	    rb_iseq_make_compile_option(&new_opt, node->nd_orig);
	    ISEQ_COMPILE_DATA(iseq)->option = &new_opt;
	}
	COMPILE_POPPED(ret, "prelude", node->nd_head);
	COMPILE_(ret, "body", node->nd_body, popped);
	ISEQ_COMPILE_DATA(iseq)->option = orig_opt;
	break;
      }
      case NODE_LAMBDA:{
	/* compile same as lambda{...} */
	const rb_iseq_t *block = NEW_CHILD_ISEQ(node->nd_body, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, line);
	VALUE argc = INT2FIX(0);

	ADD_INSN1(ret, line, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
	ADD_CALL_WITH_BLOCK(ret, line, idLambda, argc, block);

	if (popped) {
	    ADD_INSN(ret, line, pop);
	}
	break;
      }
      default:
	UNKNOWN_NODE("iseq_compile_each", node);
	return COMPILE_NG;
    }

    /* check & remove redundant trace(line) */
    if (saved_last_element &&
	ret->last == saved_last_element &&
	((INSN *)saved_last_element)->insn_id == BIN(trace)) {
	POP_ELEMENT(ret);
    }

    debug_node_end();
    return COMPILE_OK;
}

/***************************/
/* instruction information */
/***************************/

static int
insn_data_length(INSN *iobj)
{
    return insn_len(iobj->insn_id);
}

static int
calc_sp_depth(int depth, INSN *insn)
{
    return insn_stack_increase(depth, insn->insn_id, insn->operands);
}

static VALUE
opobj_inspect(VALUE obj)
{
    struct RBasic *r = (struct RBasic *) obj;
    if (!SPECIAL_CONST_P(r)  && r->klass == 0) {
	switch (BUILTIN_TYPE(r)) {
	  case T_STRING:
	    obj = rb_str_new_cstr(RSTRING_PTR(obj));
	    break;
	  case T_ARRAY:
	    obj = rb_ary_dup(obj);
	    break;
	}
    }
    return rb_inspect(obj);
}



static VALUE
insn_data_to_s_detail(INSN *iobj)
{
    VALUE str = rb_sprintf("%-20s ", insn_name(iobj->insn_id));

    if (iobj->operands) {
	const char *types = insn_op_types(iobj->insn_id);
	int j;

	for (j = 0; types[j]; j++) {
	    char type = types[j];

	    switch (type) {
	      case TS_OFFSET:	/* label(destination position) */
		{
		    LABEL *lobj = (LABEL *)OPERAND_AT(iobj, j);
		    rb_str_catf(str, "<L%03d>", lobj->label_no);
		    break;
		}
		break;
	      case TS_ISEQ:	/* iseq */
		{
		    rb_iseq_t *iseq = (rb_iseq_t *)OPERAND_AT(iobj, j);
		    VALUE val = Qnil;
		    if (0 && iseq) { /* TODO: invalidate now */
			val = (VALUE)iseq;
		    }
		    rb_str_concat(str, opobj_inspect(val));
		}
		break;
	      case TS_LINDEX:
	      case TS_NUM:	/* ulong */
	      case TS_VALUE:	/* VALUE */
		{
		    VALUE v = OPERAND_AT(iobj, j);
		    rb_str_concat(str, opobj_inspect(v));
		    break;
		}
	      case TS_ID:	/* ID */
		rb_str_concat(str, opobj_inspect(OPERAND_AT(iobj, j)));
		break;
	      case TS_GENTRY:
		{
		    struct rb_global_entry *entry = (struct rb_global_entry *)
		      (OPERAND_AT(iobj, j) & (~1));
		    rb_str_append(str, rb_id2str(entry->id));
		    break;
		}
	      case TS_IC:	/* inline cache */
		rb_str_catf(str, "<ic:%d>", FIX2INT(OPERAND_AT(iobj, j)));
		break;
	      case TS_CALLINFO: /* call info */
		{
		    struct rb_call_info *ci = (struct rb_call_info *)OPERAND_AT(iobj, j);
		    rb_str_cat2(str, "<callinfo:");
		    if (ci->mid) rb_str_catf(str, "%"PRIsVALUE, rb_id2str(ci->mid));
		    rb_str_catf(str, ", %d>", ci->orig_argc);
		    break;
		}
	      case TS_CALLCACHE: /* call cache */
		{
		    rb_str_catf(str, "<call cache>");
		    break;
		}
	      case TS_CDHASH:	/* case/when condition cache */
		rb_str_cat2(str, "<ch>");
		break;
	      case TS_FUNCPTR:
		{
		    rb_insn_func_t func = (rb_insn_func_t)OPERAND_AT(iobj, j);
#ifdef HAVE_DLADDR
		    Dl_info info;
		    if (dladdr(func, &info) && info.dli_sname) {
			rb_str_cat2(str, info.dli_sname);
			break;
		    }
#endif
		    rb_str_catf(str, "<%p>", func);
		}
		break;
	      default:{
		rb_raise(rb_eSyntaxError, "unknown operand type: %c", type);
	      }
	    }
	    if (types[j + 1]) {
		rb_str_cat2(str, ", ");
	    }
	}
    }
    return str;
}

static void
dump_disasm_list(struct iseq_link_element *link)
{
    int pos = 0;
    INSN *iobj;
    LABEL *lobj;
    VALUE str;

    printf("-- raw disasm--------\n");

    while (link) {
	switch (link->type) {
	  case ISEQ_ELEMENT_INSN:
	    {
		iobj = (INSN *)link;
		str = insn_data_to_s_detail(iobj);
		printf("%04d %-65s(%4u)\n", pos, StringValueCStr(str), iobj->line_no);
		pos += insn_data_length(iobj);
		break;
	    }
	  case ISEQ_ELEMENT_LABEL:
	    {
		lobj = (LABEL *)link;
		printf("<L%03d>\n", lobj->label_no);
		break;
	    }
	  case ISEQ_ELEMENT_NONE:
	    {
		printf("[none]\n");
		break;
	    }
	  case ISEQ_ELEMENT_ADJUST:
	    {
		ADJUST *adjust = (ADJUST *)link;
		printf("adjust: [label: %d]\n", adjust->label ? adjust->label->label_no : -1);
		break;
	    }
	  default:
	    /* ignore */
	    rb_raise(rb_eSyntaxError, "dump_disasm_list error: %ld\n", FIX2LONG(link->type));
	}
	link = link->next;
    }
    printf("---------------------\n");
    fflush(stdout);
}

const char *
rb_insns_name(int i)
{
    return insn_name_info[i];
}

VALUE
rb_insns_name_array(void)
{
    VALUE ary = rb_ary_new();
    int i;
    for (i = 0; i < numberof(insn_name_info); i++) {
	rb_ary_push(ary, rb_fstring(rb_str_new2(insn_name_info[i])));
    }
    return rb_obj_freeze(ary);
}

static LABEL *
register_label(rb_iseq_t *iseq, struct st_table *labels_table, VALUE obj)
{
    LABEL *label = 0;
    st_data_t tmp;
    obj = rb_convert_type(obj, T_SYMBOL, "Symbol", "to_sym");

    if (st_lookup(labels_table, obj, &tmp) == 0) {
	label = NEW_LABEL(0);
	st_insert(labels_table, obj, (st_data_t)label);
    }
    else {
	label = (LABEL *)tmp;
    }
    LABEL_REF(label);
    return label;
}

static VALUE
get_exception_sym2type(VALUE sym)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)
    static VALUE symRescue, symEnsure, symRetry;
    static VALUE symBreak, symRedo, symNext;

    if (symRescue == 0) {
	symRescue = ID2SYM(rb_intern("rescue"));
	symEnsure = ID2SYM(rb_intern("ensure"));
	symRetry  = ID2SYM(rb_intern("retry"));
	symBreak  = ID2SYM(rb_intern("break"));
	symRedo   = ID2SYM(rb_intern("redo"));
	symNext   = ID2SYM(rb_intern("next"));
    }

    if (sym == symRescue) return CATCH_TYPE_RESCUE;
    if (sym == symEnsure) return CATCH_TYPE_ENSURE;
    if (sym == symRetry)  return CATCH_TYPE_RETRY;
    if (sym == symBreak)  return CATCH_TYPE_BREAK;
    if (sym == symRedo)   return CATCH_TYPE_REDO;
    if (sym == symNext)   return CATCH_TYPE_NEXT;
    rb_raise(rb_eSyntaxError, "invalid exception symbol: %+"PRIsVALUE, sym);
    return 0;
}

static int
iseq_build_from_ary_exception(rb_iseq_t *iseq, struct st_table *labels_table,
		     VALUE exception)
{
    int i;

    for (i=0; i<RARRAY_LEN(exception); i++) {
	const rb_iseq_t *eiseq;
	VALUE v, type;
	const VALUE *ptr;
	LABEL *lstart, *lend, *lcont;
	unsigned int sp;

	v = rb_convert_type(RARRAY_AREF(exception, i), T_ARRAY,
					 "Array", "to_ary");
	if (RARRAY_LEN(v) != 6) {
	    rb_raise(rb_eSyntaxError, "wrong exception entry");
	}
	ptr  = RARRAY_CONST_PTR(v);
	type = get_exception_sym2type(ptr[0]);
	if (ptr[1] == Qnil) {
	    eiseq = NULL;
	}
	else {
	    eiseq = rb_iseqw_to_iseq(rb_iseq_load(ptr[1], (VALUE)iseq, Qnil));
	}

	lstart = register_label(iseq, labels_table, ptr[2]);
	lend   = register_label(iseq, labels_table, ptr[3]);
	lcont  = register_label(iseq, labels_table, ptr[4]);
	sp     = NUM2UINT(ptr[5]);

	(void)sp;

	ADD_CATCH_ENTRY(type, lstart, lend, eiseq, lcont);

	RB_GC_GUARD(v);
    }
    return COMPILE_OK;
}

static struct st_table *
insn_make_insn_table(void)
{
    struct st_table *table;
    int i;
    table = st_init_numtable();

    for (i=0; i<VM_INSTRUCTION_SIZE; i++) {
	st_insert(table, ID2SYM(rb_intern(insn_name(i))), i);
    }

    return table;
}

static const rb_iseq_t *
iseq_build_load_iseq(const rb_iseq_t *iseq, VALUE op)
{
    VALUE iseqw;
    const rb_iseq_t *loaded_iseq;

    if (RB_TYPE_P(op, T_ARRAY)) {
	iseqw = rb_iseq_load(op, (VALUE)iseq, Qnil);
    }
    else if (CLASS_OF(op) == rb_cISeq) {
	iseqw = op;
    }
    else {
	rb_raise(rb_eSyntaxError, "ISEQ is required");
    }

    loaded_iseq = rb_iseqw_to_iseq(iseqw);
    iseq_add_mark_object(iseq, (VALUE)loaded_iseq);
    return loaded_iseq;
}

static VALUE
iseq_build_callinfo_from_hash(rb_iseq_t *iseq, VALUE op)
{
    ID mid = 0;
    int orig_argc = 0;
    unsigned int flag = 0;
    struct rb_call_info_kw_arg *kw_arg = 0;

    if (!NIL_P(op)) {
	VALUE vmid = rb_hash_aref(op, ID2SYM(rb_intern("mid")));
	VALUE vflag = rb_hash_aref(op, ID2SYM(rb_intern("flag")));
	VALUE vorig_argc = rb_hash_aref(op, ID2SYM(rb_intern("orig_argc")));
	VALUE vkw_arg = rb_hash_aref(op, ID2SYM(rb_intern("kw_arg")));

	if (!NIL_P(vmid)) mid = SYM2ID(vmid);
	if (!NIL_P(vflag)) flag = NUM2UINT(vflag);
	if (!NIL_P(vorig_argc)) orig_argc = FIX2INT(vorig_argc);

	if (!NIL_P(vkw_arg)) {
	    int i;
	    int len = RARRAY_LENINT(vkw_arg);
	    size_t n = rb_call_info_kw_arg_bytes(len);

	    kw_arg = xmalloc(n);
	    kw_arg->keyword_len = len;
	    for (i = 0; i < len; i++) {
		VALUE kw = RARRAY_AREF(vkw_arg, i);
		SYM2ID(kw);	/* make immortal */
		kw_arg->keywords[i] = kw;
	    }
	}
    }

    return (VALUE)new_callinfo(iseq, mid, orig_argc, flag, kw_arg, (flag & VM_CALL_ARGS_SIMPLE) == 0);
}

static int
iseq_build_from_ary_body(rb_iseq_t *iseq, LINK_ANCHOR *const anchor,
			 VALUE body, VALUE labels_wrapper)
{
    /* TODO: body should be frozen */
    const VALUE *ptr = RARRAY_CONST_PTR(body);
    long i, len = RARRAY_LEN(body);
    struct st_table *labels_table = DATA_PTR(labels_wrapper);
    int j;
    int line_no = 0;
    int ret = COMPILE_OK;

    /*
     * index -> LABEL *label
     */
    static struct st_table *insn_table;

    if (insn_table == 0) {
	insn_table = insn_make_insn_table();
    }

    for (i=0; i<len; i++) {
	VALUE obj = ptr[i];

	if (SYMBOL_P(obj)) {
	    LABEL *label = register_label(iseq, labels_table, obj);
	    ADD_LABEL(anchor, label);
	}
	else if (FIXNUM_P(obj)) {
	    line_no = NUM2INT(obj);
	}
	else if (RB_TYPE_P(obj, T_ARRAY)) {
	    VALUE *argv = 0;
	    int argc = RARRAY_LENINT(obj) - 1;
	    st_data_t insn_id;
	    VALUE insn;

	    insn = (argc < 0) ? Qnil : RARRAY_AREF(obj, 0);
	    if (st_lookup(insn_table, (st_data_t)insn, &insn_id) == 0) {
		/* TODO: exception */
		COMPILE_ERROR(iseq, line_no,
			      "unknown instruction: %+"PRIsVALUE, insn);
		ret = COMPILE_NG;
		break;
	    }

	    if (argc != insn_len((VALUE)insn_id)-1) {
		COMPILE_ERROR(iseq, line_no,
			      "operand size mismatch");
		ret = COMPILE_NG;
		break;
	    }

	    if (argc > 0) {
		argv = compile_data_alloc(iseq, sizeof(VALUE) * argc);
		for (j=0; j<argc; j++) {
		    VALUE op = rb_ary_entry(obj, j+1);
		    switch (insn_op_type((VALUE)insn_id, j)) {
		      case TS_OFFSET: {
			LABEL *label = register_label(iseq, labels_table, op);
			argv[j] = (VALUE)label;
			break;
		      }
		      case TS_LINDEX:
		      case TS_NUM:
			(void)NUM2INT(op);
			argv[j] = op;
			break;
		      case TS_VALUE:
			argv[j] = op;
			iseq_add_mark_object(iseq, op);
			break;
		      case TS_ISEQ:
			{
			    if (op != Qnil) {
				argv[j] = (VALUE)iseq_build_load_iseq(iseq, op);
			    }
			    else {
				argv[j] = 0;
			    }
			}
			break;
		      case TS_GENTRY:
			op = rb_convert_type(op, T_SYMBOL, "Symbol", "to_sym");
			argv[j] = (VALUE)rb_global_entry(SYM2ID(op));
			break;
		      case TS_IC:
			argv[j] = op;
			if (NUM2UINT(op) >= iseq->body->is_size) {
			    iseq->body->is_size = NUM2INT(op) + 1;
			}
			break;
		      case TS_CALLINFO:
			argv[j] = iseq_build_callinfo_from_hash(iseq, op);
			break;
		      case TS_CALLCACHE:
			argv[j] = Qfalse;
			break;
		      case TS_ID:
			argv[j] = rb_convert_type(op, T_SYMBOL,
						  "Symbol", "to_sym");
			break;
		      case TS_CDHASH:
			{
			    int i;
			    VALUE map = rb_hash_new();

			    rb_hash_tbl_raw(map)->type = &cdhash_type;
			    op = rb_convert_type(op, T_ARRAY, "Array", "to_ary");
			    for (i=0; i<RARRAY_LEN(op); i+=2) {
				VALUE key = RARRAY_AREF(op, i);
				VALUE sym = RARRAY_AREF(op, i+1);
				LABEL *label =
				  register_label(iseq, labels_table, sym);
				rb_hash_aset(map, key, (VALUE)label | 1);
			    }
			    RB_GC_GUARD(op);
			    argv[j] = map;
			    rb_iseq_add_mark_object(iseq, map);
			}
			break;
		      case TS_FUNCPTR:
			{
#if SIZEOF_VALUE <= SIZEOF_LONG
			    long funcptr = NUM2LONG(op);
#else
			    LONG_LONG funcptr = NUM2LL(op);
#endif
			    argv[j] = (VALUE)funcptr;
			}
			break;
		      default:
			rb_raise(rb_eSyntaxError, "unknown operand: %c", insn_op_type((VALUE)insn_id, j));
		    }
		}
	    }
	    ADD_ELEM(anchor,
		     (LINK_ELEMENT*)new_insn_core(iseq, line_no,
						  (enum ruby_vminsn_type)insn_id, argc, argv));
	}
	else {
	    rb_raise(rb_eTypeError, "unexpected object for instruction");
	}
    }
    DATA_PTR(labels_wrapper) = 0;
    validate_labels(iseq, labels_table);
    if (!ret) return ret;
    return iseq_setup(iseq, anchor);
}

#define CHECK_ARRAY(v)   rb_convert_type((v), T_ARRAY, "Array", "to_ary")
#define CHECK_SYMBOL(v)  rb_convert_type((v), T_SYMBOL, "Symbol", "to_sym")

static int
int_param(int *dst, VALUE param, VALUE sym)
{
    VALUE val = rb_hash_aref(param, sym);
    switch (TYPE(val)) {
      case T_NIL:
	return FALSE;
      case T_FIXNUM:
	*dst = FIX2INT(val);
	return TRUE;
      default:
	rb_raise(rb_eTypeError, "invalid %+"PRIsVALUE" Fixnum: %+"PRIsVALUE,
		 sym, val);
    }
    return FALSE;
}

static const struct rb_iseq_param_keyword *
iseq_build_kw(rb_iseq_t *iseq, VALUE params, VALUE keywords)
{
    int i, j;
    int len = RARRAY_LENINT(keywords);
    int default_len;
    VALUE key, sym, default_val;
    VALUE *dvs;
    ID *ids;
    struct rb_iseq_param_keyword *keyword = ZALLOC(struct rb_iseq_param_keyword);

    iseq->body->param.flags.has_kw = TRUE;

    keyword->num = len;
#define SYM(s) ID2SYM(rb_intern(#s))
    (void)int_param(&keyword->bits_start, params, SYM(kwbits));
    i = keyword->bits_start - keyword->num;
    ids = (VALUE *)&iseq->body->local_table[i];
#undef SYM

    /* required args */
    for (i = 0; i < len; i++) {
	VALUE val = RARRAY_AREF(keywords, i);

	if (!SYMBOL_P(val)) {
	    goto default_values;
	}
	ids[i] = SYM2ID(val);
	keyword->required_num++;
    }

  default_values: /* note: we intentionally preserve `i' from previous loop */
    default_len = len - i;
    if (default_len == 0) {
	return keyword;
    }

    dvs = ALLOC_N(VALUE, default_len);

    for (j = 0; i < len; i++, j++) {
	key = RARRAY_AREF(keywords, i);
	CHECK_ARRAY(key);

	switch (RARRAY_LEN(key)) {
	  case 1:
	    sym = RARRAY_AREF(key, 0);
	    default_val = Qundef;
	    break;
	  case 2:
	    sym = RARRAY_AREF(key, 0);
	    default_val = RARRAY_AREF(key, 1);
	    break;
	  default:
	    rb_raise(rb_eTypeError, "keyword default has unsupported len %+"PRIsVALUE, key);
	}
	ids[i] = SYM2ID(sym);
	dvs[j] = default_val;
    }

    keyword->table = ids;
    keyword->default_values = dvs;

    return keyword;
}

void
rb_iseq_build_from_ary(rb_iseq_t *iseq, VALUE misc, VALUE locals, VALUE params,
			 VALUE exception, VALUE body)
{
#define SYM(s) ID2SYM(rb_intern(#s))
    int i, len;
    ID *tbl;
    struct st_table *labels_table = st_init_numtable();
    VALUE labels_wrapper = Data_Wrap_Struct(0, 0, st_free_table, labels_table);
    VALUE arg_opt_labels = rb_hash_aref(params, SYM(opt));
    VALUE keywords = rb_hash_aref(params, SYM(keyword));
    VALUE sym_arg_rest = ID2SYM(rb_intern("#arg_rest"));
    DECL_ANCHOR(anchor);
    INIT_ANCHOR(anchor);

    len = RARRAY_LENINT(locals);
    iseq->body->local_table_size = len;
    iseq->body->local_table = tbl = len > 0 ? (ID *)ALLOC_N(ID, iseq->body->local_table_size) : NULL;

    for (i = 0; i < len; i++) {
	VALUE lv = RARRAY_AREF(locals, i);

	if (sym_arg_rest == lv) {
	    tbl[i] = 0;
	}
	else {
	    tbl[i] = FIXNUM_P(lv) ? (ID)FIX2LONG(lv) : SYM2ID(CHECK_SYMBOL(lv));
	}
    }

    /*
     * we currently ignore misc params,
     * local_size, stack_size and param.size are all calculated
     */

#define INT_PARAM(F) int_param(&iseq->body->param.F, params, SYM(F))
    if (INT_PARAM(lead_num)) {
	iseq->body->param.flags.has_lead = TRUE;
    }
    if (INT_PARAM(post_num)) iseq->body->param.flags.has_post = TRUE;
    if (INT_PARAM(post_start)) iseq->body->param.flags.has_post = TRUE;
    if (INT_PARAM(rest_start)) iseq->body->param.flags.has_rest = TRUE;
    if (INT_PARAM(block_start)) iseq->body->param.flags.has_block = TRUE;
#undef INT_PARAM

    switch (TYPE(arg_opt_labels)) {
      case T_ARRAY:
	len = RARRAY_LENINT(arg_opt_labels);
	iseq->body->param.flags.has_opt = !!(len - 1 >= 0);

	if (iseq->body->param.flags.has_opt) {
	    VALUE *opt_table = ALLOC_N(VALUE, len);

	    for (i = 0; i < len; i++) {
		VALUE ent = RARRAY_AREF(arg_opt_labels, i);
		LABEL *label = register_label(iseq, labels_table, ent);
		opt_table[i] = (VALUE)label;
	    }

	    iseq->body->param.opt_num = len - 1;
	    iseq->body->param.opt_table = opt_table;
	}
      case T_NIL:
	break;
      default:
	rb_raise(rb_eTypeError, ":opt param is not an array: %+"PRIsVALUE,
		 arg_opt_labels);
    }

    switch (TYPE(keywords)) {
      case T_ARRAY:
	iseq->body->param.keyword = iseq_build_kw(iseq, params, keywords);
      case T_NIL:
	break;
      default:
	rb_raise(rb_eTypeError, ":keywords param is not an array: %+"PRIsVALUE,
		 keywords);
    }

    if (Qtrue == rb_hash_aref(params, SYM(ambiguous_param0))) {
	iseq->body->param.flags.ambiguous_param0 = TRUE;
    }

    if (int_param(&i, params, SYM(kwrest))) {
	struct rb_iseq_param_keyword *keyword = (struct rb_iseq_param_keyword *)iseq->body->param.keyword;
	if (keyword == NULL) {
	    iseq->body->param.keyword = keyword = ZALLOC(struct rb_iseq_param_keyword);
	}
	keyword->rest_start = i;
	iseq->body->param.flags.has_kwrest = TRUE;
    }
#undef SYM
    iseq_calc_param_size(iseq);

    /* exception */
    iseq_build_from_ary_exception(iseq, labels_table, exception);

    /* body */
    iseq_build_from_ary_body(iseq, anchor, body, labels_wrapper);
}

/* for parser */

int
rb_dvar_defined(ID id, const struct rb_block *base_block)
{
    const rb_iseq_t *iseq;

    if (base_block && (iseq = vm_block_iseq(base_block)) != NULL) {
	while (iseq->body->type == ISEQ_TYPE_BLOCK ||
	       iseq->body->type == ISEQ_TYPE_RESCUE ||
	       iseq->body->type == ISEQ_TYPE_ENSURE ||
	       iseq->body->type == ISEQ_TYPE_EVAL ||
	       iseq->body->type == ISEQ_TYPE_MAIN
	       ) {
	    unsigned int i;

	    for (i = 0; i < iseq->body->local_table_size; i++) {
		if (iseq->body->local_table[i] == id) {
		    return 1;
		}
	    }
	    iseq = iseq->body->parent_iseq;
	}
    }
    return 0;
}

int
rb_local_defined(ID id, const struct rb_block *base_block)
{
    const rb_iseq_t *iseq;

    if (base_block && (iseq = vm_block_iseq(base_block)) != NULL) {
	unsigned int i;
	iseq = iseq->body->local_iseq;

	for (i=0; i<iseq->body->local_table_size; i++) {
	    if (iseq->body->local_table[i] == id) {
		return 1;
	    }
	}
    }
    return 0;
}

static int
caller_location(VALUE *path, VALUE *absolute_path)
{
    const rb_thread_t *const th = GET_THREAD();
    const rb_control_frame_t *const cfp =
	rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp) {
	int line = rb_vm_get_sourceline(cfp);
	*path = cfp->iseq->body->location.path;
	*absolute_path = cfp->iseq->body->location.absolute_path;
	return line;
    }
    else {
	*path = rb_fstring_cstr("<compiled>");
	*absolute_path = *path;
	return 1;
    }
}

typedef struct {
    VALUE arg;
    rb_insn_func_t func;
    int line;
} accessor_args;

static const rb_iseq_t *
method_for_self(VALUE name, VALUE arg, rb_insn_func_t func,
		VALUE (*build)(rb_iseq_t *, LINK_ANCHOR *, VALUE))
{
    VALUE path, absolute_path;
    accessor_args acc;

    acc.arg = arg;
    acc.func = func;
    acc.line = caller_location(&path, &absolute_path);
    return rb_iseq_new_with_opt((NODE *)IFUNC_NEW(build, (VALUE)&acc, 0),
				rb_sym2str(name), path, absolute_path,
				INT2FIX(acc.line), 0, ISEQ_TYPE_METHOD, 0);
}

static VALUE
for_self_aref(rb_iseq_t *iseq, LINK_ANCHOR *const ret, VALUE a)
{
    const accessor_args *const args = (void *)a;
    const int line = args->line;

    iseq_set_local_table(iseq, 0);
    iseq->body->param.lead_num = 0;
    iseq->body->param.size = 0;

    ADD_INSN1(ret, line, putobject, args->arg);
    ADD_INSN1(ret, line, opt_call_c_function, (VALUE)args->func);
    return Qnil;
}

static VALUE
for_self_aset(rb_iseq_t *iseq, LINK_ANCHOR *const ret, VALUE a)
{
    const accessor_args *const args = (void *)a;
    const int line = args->line;
    static const ID vars[] = {1, idUScore};

    iseq_set_local_table(iseq, vars);
    iseq->body->param.lead_num = 1;
    iseq->body->param.size = 1;

    ADD_GETLOCAL(ret, line, numberof(vars)-1, 0);
    ADD_INSN1(ret, line, putobject, args->arg);
    ADD_INSN1(ret, line, opt_call_c_function, (VALUE)args->func);
    ADD_INSN(ret, line, pop);
    return Qnil;
}

/*
 * func (index) -> (value)
 */
const rb_iseq_t *
rb_method_for_self_aref(VALUE name, VALUE arg, rb_insn_func_t func)
{
    return method_for_self(name, arg, func, for_self_aref);
}

/*
 * func (index, value) -> (index, value)
 */
const rb_iseq_t *
rb_method_for_self_aset(VALUE name, VALUE arg, rb_insn_func_t func)
{
    return method_for_self(name, arg, func, for_self_aset);
}

/* ISeq binary format */

typedef unsigned int ibf_offset_t;
#define IBF_OFFSET(ptr) ((ibf_offset_t)(VALUE)(ptr))

struct ibf_header {
    char magic[4]; /* YARB */
    unsigned int major_version;
    unsigned int minor_version;
    unsigned int size;
    unsigned int extra_size;

    unsigned int iseq_list_size;
    unsigned int id_list_size;
    unsigned int object_list_size;

    ibf_offset_t iseq_list_offset;
    ibf_offset_t id_list_offset;
    ibf_offset_t object_list_offset;
};

struct ibf_id_entry {
    enum {
	ibf_id_enc_ascii,
	ibf_id_enc_utf8,
	ibf_id_enc_other
    } enc : 2;
    char body[1];
};

struct ibf_dump {
    VALUE str;
    VALUE iseq_list;      /* [iseq0 offset, ...] */
    VALUE obj_list;       /* [objs] */
    st_table *iseq_table; /* iseq -> iseq number */
    st_table *id_table;   /* id -> id number */
};

rb_iseq_t * iseq_alloc(void);

struct ibf_load {
    const char *buff;
    const struct ibf_header *header;
    ID *id_list;     /* [id0, ...] */
    VALUE iseq_list; /* [iseq0, ...] */
    VALUE obj_list;  /* [obj0, ...] */
    VALUE loader_obj;
    VALUE str;
    rb_iseq_t *iseq;
};

static ibf_offset_t
ibf_dump_pos(struct ibf_dump *dump)
{
    return (unsigned int)rb_str_strlen(dump->str);
}

static ibf_offset_t
ibf_dump_write(struct ibf_dump *dump, const void *buff, unsigned long size)
{
    ibf_offset_t pos = ibf_dump_pos(dump);
    rb_str_cat(dump->str, (const char *)buff, size);
    /* TODO: overflow check */
    return pos;
}

static void
ibf_dump_overwrite(struct ibf_dump *dump, void *buff, unsigned int size, long offset)
{
    VALUE str = dump->str;
    char *ptr = RSTRING_PTR(str);
    if ((unsigned long)(size + offset) > (unsigned long)RSTRING_LEN(str))
	rb_bug("ibf_dump_overwrite: overflow");
    memcpy(ptr + offset, buff, size);
}

static void *
ibf_load_alloc(const struct ibf_load *load, ibf_offset_t offset, int size)
{
    void *buff = ruby_xmalloc(size);
    memcpy(buff, load->buff + offset, size);
    return buff;
}

#define IBF_W(b, type, n) (type *)(VALUE)ibf_dump_write(dump, (b), sizeof(type) * (n))
#define IBF_WV(variable)   ibf_dump_write(dump, &(variable), sizeof(variable))
#define IBF_WP(b, type, n) ibf_dump_write(dump, (b), sizeof(type) * (n))
#define IBF_R(val, type, n) (type *)ibf_load_alloc(load, IBF_OFFSET(val), sizeof(type) * (n))

static int
ibf_table_lookup(struct st_table *table, st_data_t key)
{
    st_data_t val;

    if (st_lookup(table, key, &val)) {
	return (int)val;
    }
    else {
	return -1;
    }
}

static int
ibf_table_index(struct st_table *table, st_data_t key)
{
    int index = ibf_table_lookup(table, key);

    if (index < 0) { /* not found */
	index = (int)table->num_entries;
	st_insert(table, key, (st_data_t)index);
    }

    return index;
}

/* dump/load generic */

static VALUE ibf_load_object(const struct ibf_load *load, VALUE object_index);
static rb_iseq_t *ibf_load_iseq(const struct ibf_load *load, const rb_iseq_t *index_iseq);

static VALUE
ibf_dump_object(struct ibf_dump *dump, VALUE obj)
{
    long index = RARRAY_LEN(dump->obj_list);
    long i;
    for (i=0; i<index; i++) {
	if (RARRAY_AREF(dump->obj_list, i) == obj) return (VALUE)i; /* dedup */
    }
    rb_ary_push(dump->obj_list, obj);
    return (VALUE)index;
}

static VALUE
ibf_dump_id(struct ibf_dump *dump, ID id)
{
    return (VALUE)ibf_table_index(dump->id_table, (st_data_t)id);
}

static ID
ibf_load_id(const struct ibf_load *load, const ID id_index)
{
    ID id;

    if (id_index == 0) {
	id = 0;
    }
    else {
	id = load->id_list[(long)id_index];

	if (id == 0) {
	    long *indices = (long *)(load->buff + load->header->id_list_offset);
	    VALUE str = ibf_load_object(load, indices[id_index]);
	    id = NIL_P(str) ? 0 : rb_intern_str(str); /* str == nil -> internal junk id */
	    load->id_list[(long)id_index] = id;
	}
    }

    return id;
}

/* dump/load: code */

static VALUE
ibf_dump_callinfo(struct ibf_dump *dump, const struct rb_call_info *ci)
{
    return (ci->flag & VM_CALL_KWARG) ? Qtrue : Qfalse;
}

static ibf_offset_t ibf_dump_iseq_each(struct ibf_dump *dump, const rb_iseq_t *iseq);

static rb_iseq_t *
ibf_dump_iseq(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    if (iseq == NULL) {
	return (rb_iseq_t *)-1;
    }
    else {
	int iseq_index = ibf_table_lookup(dump->iseq_table, (st_data_t)iseq);
	if (iseq_index < 0) {
	    iseq_index = ibf_table_index(dump->iseq_table, (st_data_t)iseq);
	    rb_ary_store(dump->iseq_list, iseq_index, LONG2NUM(ibf_dump_iseq_each(dump, rb_iseq_check(iseq))));
	}
	return (rb_iseq_t *)(VALUE)iseq_index;
    }
}

static VALUE
ibf_dump_gentry(struct ibf_dump *dump, const struct rb_global_entry *entry)
{
    return (VALUE)ibf_dump_id(dump, entry->id);
}

static VALUE
ibf_load_gentry(const struct ibf_load *load, const struct rb_global_entry *entry)
{
    ID gid = ibf_load_id(load, (ID)(VALUE)entry);
    return (VALUE)rb_global_entry(gid);
}

static VALUE *
ibf_dump_code(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    const int iseq_size = iseq->body->iseq_size;
    int code_index;
    VALUE *code;
    const VALUE *orig_code = rb_iseq_original_iseq(iseq);

    code = ALLOCA_N(VALUE, iseq_size);

    for (code_index=0; code_index<iseq_size;) {
	const VALUE insn = orig_code[code_index];
	const char *types = insn_op_types(insn);
	int op_index;

	code[code_index++] = (VALUE)insn;

	for (op_index=0; types[op_index]; op_index++, code_index++) {
	    VALUE op = orig_code[code_index];
	    switch (types[op_index]) {
	      case TS_CDHASH:
	      case TS_VALUE:
		code[code_index] = ibf_dump_object(dump, op);
		break;
	      case TS_ISEQ:
		code[code_index] = (VALUE)ibf_dump_iseq(dump, (const rb_iseq_t *)op);
		break;
	      case TS_IC:
		{
		    unsigned int i;
		    for (i=0; i<iseq->body->is_size; i++) {
			if (op == (VALUE)&iseq->body->is_entries[i]) {
			    break;
			}
		    }
		    code[code_index] = i;
		}
		break;
	      case TS_CALLINFO:
		code[code_index] = ibf_dump_callinfo(dump, (const struct rb_call_info *)op);
		break;
	      case TS_CALLCACHE:
		code[code_index] = 0;
		break;
	      case TS_ID:
		code[code_index] = ibf_dump_id(dump, (ID)op);
		break;
	      case TS_GENTRY:
		code[code_index] = ibf_dump_gentry(dump, (const struct rb_global_entry *)op);
		break;
	      case TS_FUNCPTR:
		rb_raise(rb_eRuntimeError, "TS_FUNCPTR is not supported");
		break;
	      default:
		code[code_index] = op;
		break;
	    }
	}
	assert(insn_len(insn) == op_index+1);
    }

    return IBF_W(code, VALUE, iseq_size);
}

static VALUE *
ibf_load_code(const struct ibf_load *load, const rb_iseq_t *iseq, const struct rb_iseq_constant_body *body)
{
    const int iseq_size = body->iseq_size;
    int code_index;
    VALUE *code = IBF_R(body->iseq_encoded, VALUE, iseq_size);

    struct rb_call_info *ci_entries = iseq->body->ci_entries;
    struct rb_call_info_with_kwarg *ci_kw_entries = (struct rb_call_info_with_kwarg *)&iseq->body->ci_entries[iseq->body->ci_size];
    struct rb_call_cache *cc_entries = iseq->body->cc_entries;
    union iseq_inline_storage_entry *is_entries = iseq->body->is_entries;

    for (code_index=0; code_index<iseq_size;) {
	const VALUE insn = code[code_index++];
	const char *types = insn_op_types(insn);
	int op_index;

	for (op_index=0; types[op_index]; op_index++, code_index++) {
	    VALUE op = code[code_index];

	    switch (types[op_index]) {
	      case TS_CDHASH:
	      case TS_VALUE:
		code[code_index] = ibf_load_object(load, op);
		break;
	      case TS_ISEQ:
		code[code_index] = (VALUE)ibf_load_iseq(load, (const rb_iseq_t *)op);
		break;
	      case TS_IC:
		code[code_index] = (VALUE)&is_entries[(int)op];
		break;
	      case TS_CALLINFO:
		code[code_index] = op ? (VALUE)ci_kw_entries++ : (VALUE)ci_entries++; /* op is Qtrue (kw) or Qfalse (!kw) */
		break;
	      case TS_CALLCACHE:
		code[code_index] = (VALUE)cc_entries++;
		break;
	      case TS_ID:
		code[code_index] = ibf_load_id(load, (ID)op);
		break;
	      case TS_GENTRY:
		code[code_index] = ibf_load_gentry(load, (const struct rb_global_entry *)op);
		break;
	      case TS_FUNCPTR:
		rb_raise(rb_eRuntimeError, "TS_FUNCPTR is not supported");
		break;
	      default:
		/* code[code_index] = op; */
		break;
	    }
	}
	assert(insn_len(insn) == op_index+1);
    };


    return code;
}

static VALUE *
ibf_dump_param_opt_table(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    int opt_num = iseq->body->param.opt_num;

    if (opt_num > 0) {
	return IBF_W(iseq->body->param.opt_table, VALUE, opt_num + 1);
    }
    else {
	return NULL;
    }
}

static VALUE *
ibf_load_param_opt_table(const struct ibf_load *load, const struct rb_iseq_constant_body *body)
{
    int opt_num = body->param.opt_num;

    if (opt_num > 0) {
	ibf_offset_t offset = IBF_OFFSET(body->param.opt_table);
	VALUE *table = ALLOC_N(VALUE, opt_num+1);
	MEMCPY(table, load->buff + offset, VALUE, opt_num+1);
	return table;
    }
    else {
	return NULL;
    }
}

static struct rb_iseq_param_keyword *
ibf_dump_param_keyword(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    const struct rb_iseq_param_keyword *kw = iseq->body->param.keyword;

    if (kw) {
	struct rb_iseq_param_keyword dump_kw = *kw;
	int dv_num = kw->num - kw->required_num;
	ID *ids = kw->num > 0 ? ALLOCA_N(ID, kw->num) : NULL;
	VALUE *dvs = dv_num > 0 ? ALLOCA_N(VALUE, dv_num) : NULL;
	int i;

	for (i=0; i<kw->num; i++) ids[i] = (ID)ibf_dump_id(dump, kw->table[i]);
	for (i=0; i<dv_num; i++) dvs[i] = (VALUE)ibf_dump_object(dump, kw->default_values[i]);

	dump_kw.table = IBF_W(ids, ID, kw->num);
	dump_kw.default_values = IBF_W(dvs, VALUE, dv_num);
	return IBF_W(&dump_kw, struct rb_iseq_param_keyword, 1);
    }
    else {
	return NULL;
    }
}

static const struct rb_iseq_param_keyword *
ibf_load_param_keyword(const struct ibf_load *load, const struct rb_iseq_constant_body *body)
{
    if (body->param.keyword) {
	struct rb_iseq_param_keyword *kw = IBF_R(body->param.keyword, struct rb_iseq_param_keyword, 1);
	ID *ids = IBF_R(kw->table, ID, kw->num);
	int dv_num = kw->num - kw->required_num;
	VALUE *dvs = IBF_R(kw->default_values, VALUE, dv_num);
	int i;

	for (i=0; i<kw->num; i++) {
	    ids[i] = ibf_load_id(load, ids[i]);
	}
	for (i=0; i<dv_num; i++) {
	    dvs[i] = ibf_load_object(load, dvs[i]);
	}

	kw->table = ids;
	kw->default_values = dvs;
	return kw;
    }
    else {
	return NULL;
    }
}

static struct iseq_line_info_entry *
ibf_dump_line_info_table(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    return IBF_W(iseq->body->line_info_table, struct iseq_line_info_entry, iseq->body->line_info_size);
}

static struct iseq_line_info_entry *
ibf_load_line_info_table(const struct ibf_load *load, const struct rb_iseq_constant_body *body)
{
    return IBF_R(body->line_info_table, struct iseq_line_info_entry, body->line_info_size);
}

static ID *
ibf_dump_local_table(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    const int size = iseq->body->local_table_size;
    ID *table = ALLOCA_N(ID, size);
    int i;

    for (i=0; i<size; i++) {
	table[i] = ibf_dump_id(dump, iseq->body->local_table[i]);
    }

    return IBF_W(table, ID, size);
}

static ID *
ibf_load_local_table(const struct ibf_load *load, const struct rb_iseq_constant_body *body)
{
    const int size = body->local_table_size;

    if (size > 0) {
	ID *table = IBF_R(body->local_table, ID, size);
	int i;

	for (i=0; i<size; i++) {
	    table[i] = ibf_load_id(load, table[i]);
	}
	return table;
    }
    else {
	return NULL;
    }
}

static struct iseq_catch_table *
ibf_dump_catch_table(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    const struct iseq_catch_table *table = iseq->body->catch_table;

    if (table) {
	int byte_size = iseq_catch_table_bytes(iseq->body->catch_table->size);
	struct iseq_catch_table *dump_table = (struct iseq_catch_table *)ALLOCA_N(char, byte_size);
	unsigned int i;
	dump_table->size = table->size;
	for (i=0; i<table->size; i++) {
	    dump_table->entries[i] = table->entries[i];
	    dump_table->entries[i].iseq = ibf_dump_iseq(dump, table->entries[i].iseq);
	}
	return (struct iseq_catch_table *)(VALUE)ibf_dump_write(dump, dump_table, byte_size);
    }
    else {
	return NULL;
    }
}

static struct iseq_catch_table *
ibf_load_catch_table(const struct ibf_load *load, const struct rb_iseq_constant_body *body)
{
    if (body->catch_table) {
	struct iseq_catch_table *table;
	unsigned int i;
	unsigned int size;
	size = *(unsigned int *)(load->buff + IBF_OFFSET(body->catch_table));
	table = ibf_load_alloc(load, IBF_OFFSET(body->catch_table), iseq_catch_table_bytes(size));
	for (i=0; i<size; i++) {
	    table->entries[i].iseq = ibf_load_iseq(load, table->entries[i].iseq);
	}
	return table;
    }
    else {
	return NULL;
    }
}

static struct rb_call_info *
ibf_dump_ci_entries(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    const unsigned int ci_size = iseq->body->ci_size;
    const unsigned int ci_kw_size = iseq->body->ci_kw_size;
    const struct rb_call_info *ci_entries = iseq->body->ci_entries;
    struct rb_call_info *dump_ci_entries;
    struct rb_call_info_with_kwarg *dump_ci_kw_entries;
    int byte_size = ci_size * sizeof(struct rb_call_info) +
                    ci_kw_size * sizeof(struct rb_call_info_with_kwarg);
    unsigned int i;

    dump_ci_entries = (struct rb_call_info *)ALLOCA_N(char, byte_size);
    dump_ci_kw_entries = (struct rb_call_info_with_kwarg *)&dump_ci_entries[ci_size];
    memcpy(dump_ci_entries, ci_entries, byte_size);

    for (i=0; i<ci_size; i++) { /* conver ID for each ci */
	dump_ci_entries[i].mid = ibf_dump_id(dump, dump_ci_entries[i].mid);
    }
    for (i=0; i<ci_kw_size; i++) {
	const struct rb_call_info_kw_arg *kw_arg = dump_ci_kw_entries[i].kw_arg;
	int j;
	VALUE *keywords = ALLOCA_N(VALUE, kw_arg->keyword_len);
	for (j=0; j<kw_arg->keyword_len; j++) {
	    keywords[j] = (VALUE)ibf_dump_object(dump, kw_arg->keywords[j]); /* kw_arg->keywords[n] is Symbol */
	}
	dump_ci_kw_entries[i].kw_arg = (struct rb_call_info_kw_arg *)(VALUE)ibf_dump_write(dump, &kw_arg->keyword_len, sizeof(int));
	ibf_dump_write(dump, keywords, sizeof(VALUE) * kw_arg->keyword_len);

	dump_ci_kw_entries[i].ci.mid = ibf_dump_id(dump, dump_ci_kw_entries[i].ci.mid);
    }
    return (struct rb_call_info *)(VALUE)ibf_dump_write(dump, dump_ci_entries, byte_size);
}

static struct rb_call_info *
ibf_load_ci_entries(const struct ibf_load *load, const struct rb_iseq_constant_body *body)
{
    unsigned int i;
    const unsigned int ci_size = body->ci_size;
    const unsigned int ci_kw_size = body->ci_kw_size;
    struct rb_call_info *ci_entries = ibf_load_alloc(load, IBF_OFFSET(body->ci_entries),
						     sizeof(struct rb_call_info) * body->ci_size +
						     sizeof(struct rb_call_info_with_kwarg) * body->ci_kw_size);
    struct rb_call_info_with_kwarg *ci_kw_entries = (struct rb_call_info_with_kwarg *)&ci_entries[ci_size];

    for (i=0; i<ci_size; i++) {
	ci_entries[i].mid = ibf_load_id(load, ci_entries[i].mid);
    }
    for (i=0; i<ci_kw_size; i++) {
	int j;
	ibf_offset_t kw_arg_offset = IBF_OFFSET(ci_kw_entries[i].kw_arg);
	const int keyword_len = *(int *)(load->buff + kw_arg_offset);
	const VALUE *keywords = (VALUE *)(load->buff + kw_arg_offset + sizeof(int));
	struct rb_call_info_kw_arg *kw_arg = ruby_xmalloc(sizeof(struct rb_call_info_kw_arg) + sizeof(VALUE) * (keyword_len - 1));
	kw_arg->keyword_len = keyword_len;
	for (j=0; j<kw_arg->keyword_len; j++) {
	    kw_arg->keywords[j] = (VALUE)ibf_load_object(load, keywords[j]);
	}
	ci_kw_entries[i].kw_arg = kw_arg;
	ci_kw_entries[i].ci.mid = ibf_load_id(load, ci_kw_entries[i].ci.mid);
    }

    return ci_entries;
}

static ibf_offset_t
ibf_dump_iseq_each(struct ibf_dump *dump, const rb_iseq_t *iseq)
{
    struct rb_iseq_constant_body dump_body;
    dump_body = *iseq->body;

    dump_body.location.path = ibf_dump_object(dump, dump_body.location.path);
    dump_body.location.absolute_path = ibf_dump_object(dump, dump_body.location.absolute_path);
    dump_body.location.base_label = ibf_dump_object(dump, dump_body.location.base_label);
    dump_body.location.label = ibf_dump_object(dump, dump_body.location.label);

    dump_body.iseq_encoded =    ibf_dump_code(dump, iseq);
    dump_body.param.opt_table = ibf_dump_param_opt_table(dump, iseq);
    dump_body.param.keyword =   ibf_dump_param_keyword(dump, iseq);
    dump_body.line_info_table = ibf_dump_line_info_table(dump, iseq);
    dump_body.local_table =     ibf_dump_local_table(dump, iseq);
    dump_body.catch_table =     ibf_dump_catch_table(dump, iseq);
    dump_body.parent_iseq =     ibf_dump_iseq(dump, iseq->body->parent_iseq);
    dump_body.local_iseq =      ibf_dump_iseq(dump, iseq->body->local_iseq);
    dump_body.is_entries =      NULL;
    dump_body.ci_entries =      ibf_dump_ci_entries(dump, iseq);
    dump_body.cc_entries =      NULL;
    dump_body.mark_ary =        ISEQ_FLIP_CNT(iseq);

    return ibf_dump_write(dump, &dump_body, sizeof(dump_body));
}

static VALUE
ibf_load_location_str(const struct ibf_load *load, VALUE str_index)
{
    VALUE str = ibf_load_object(load, str_index);
    if (str != Qnil) {
	str = rb_fstring(str);
    }
    return str;
}

static void
ibf_load_iseq_each(const struct ibf_load *load, rb_iseq_t *iseq, ibf_offset_t offset)
{
    struct rb_iseq_constant_body *load_body = iseq->body = ZALLOC(struct rb_iseq_constant_body);
    const struct rb_iseq_constant_body *body = (struct rb_iseq_constant_body *)(load->buff + offset);

    /* memcpy(load_body, load->buff + offset, sizeof(*load_body)); */
    load_body->type = body->type;
    load_body->stack_max = body->stack_max;
    load_body->iseq_size = body->iseq_size;
    load_body->param = body->param;
    load_body->local_table_size = body->local_table_size;
    load_body->is_size = body->is_size;
    load_body->ci_size = body->ci_size;
    load_body->ci_kw_size = body->ci_kw_size;
    load_body->line_info_size = body->line_info_size;

    RB_OBJ_WRITE(iseq, &load_body->mark_ary, iseq_mark_ary_create((int)body->mark_ary));

    RB_OBJ_WRITE(iseq, &load_body->location.path,          ibf_load_location_str(load, body->location.path));
    RB_OBJ_WRITE(iseq, &load_body->location.absolute_path, ibf_load_location_str(load, body->location.absolute_path));
    RB_OBJ_WRITE(iseq, &load_body->location.base_label,    ibf_load_location_str(load, body->location.base_label));
    RB_OBJ_WRITE(iseq, &load_body->location.label,         ibf_load_location_str(load, body->location.label));
    load_body->location.first_lineno = body->location.first_lineno;

    load_body->is_entries      = ZALLOC_N(union iseq_inline_storage_entry, body->is_size);
    load_body->ci_entries      = ibf_load_ci_entries(load, body);
    load_body->cc_entries      = ZALLOC_N(struct rb_call_cache, body->ci_size + body->ci_kw_size);
    load_body->param.opt_table = ibf_load_param_opt_table(load, body);
    load_body->param.keyword   = ibf_load_param_keyword(load, body);
    load_body->line_info_table = ibf_load_line_info_table(load, body);
    load_body->local_table     = ibf_load_local_table(load, body);
    load_body->catch_table     = ibf_load_catch_table(load, body);
    load_body->parent_iseq     = ibf_load_iseq(load, body->parent_iseq);
    load_body->local_iseq      = ibf_load_iseq(load, body->local_iseq);

    load_body->iseq_encoded    = ibf_load_code(load, iseq, body);

    rb_iseq_translate_threaded_code(iseq);
}


static void
ibf_dump_iseq_list(struct ibf_dump *dump, struct ibf_header *header)
{
    const long size = RARRAY_LEN(dump->iseq_list);
    ibf_offset_t *list = ALLOCA_N(ibf_offset_t, size);
    long i;

    for (i=0; i<size; i++) {
	list[i] = (ibf_offset_t)NUM2LONG(rb_ary_entry(dump->iseq_list, i));
    }

    header->iseq_list_offset = ibf_dump_write(dump, list, sizeof(ibf_offset_t) * size);
    header->iseq_list_size = (unsigned int)size;
}

struct ibf_dump_id_list_i_arg {
    struct ibf_dump *dump;
    long *list;
    int current_i;
};

static int
ibf_dump_id_list_i(st_data_t key, st_data_t val, st_data_t ptr)
{
    struct ibf_dump_id_list_i_arg *arg = (struct ibf_dump_id_list_i_arg *)ptr;
    int i = (int)val;
    ID id = (ID)key;
    assert(arg->current_i == i);
    arg->current_i++;

    if (rb_id2name(id)) {
	arg->list[i] = (long)ibf_dump_object(arg->dump, rb_id2str(id));
    }
    else {
	arg->list[i] = 0;
    }

    return ST_CONTINUE;
}

static void
ibf_dump_id_list(struct ibf_dump *dump, struct ibf_header *header)
{
    const long size = dump->id_table->num_entries;
    struct ibf_dump_id_list_i_arg arg;
    arg.list = ALLOCA_N(long, size);
    arg.dump = dump;
    arg.current_i = 0;

    st_foreach(dump->id_table, ibf_dump_id_list_i, (st_data_t)&arg);

    header->id_list_offset = ibf_dump_write(dump, arg.list, sizeof(long) * size);
    header->id_list_size = (unsigned int)size;
}

#define IBF_OBJECT_INTERNAL FL_PROMOTED0

/*
 * Binary format
 * - ibf_object_header
 * - ibf_object_xxx (xxx is type)
 */

struct ibf_object_header {
    unsigned int type: 5;
    unsigned int special_const: 1;
    unsigned int frozen: 1;
    unsigned int internal: 1;
};

enum ibf_object_class_index {
    IBF_OBJECT_CLASS_OBJECT,
    IBF_OBJECT_CLASS_ARRAY,
    IBF_OBJECT_CLASS_STANDARD_ERROR
};

struct ibf_object_string {
    long encindex;
    long len;
    char ptr[1];
};

struct ibf_object_regexp {
    long srcstr;
    char option;
};

struct ibf_object_array {
    long len;
    long ary[1];
};

struct ibf_object_hash {
    long len;
    long keyval[1];
};

struct ibf_object_struct_range {
    long class_index;
    long len;
    long beg;
    long end;
    int excl;
};

struct ibf_object_bignum {
    ssize_t slen;
    BDIGIT digits[1];
};

enum ibf_object_data_type {
    IBF_OBJECT_DATA_ENCODING
};

struct ibf_object_complex_rational {
    long a, b;
};

struct ibf_object_symbol {
    long str;
};

#define IBF_OBJHEADER(offset)     (struct ibf_object_header *)(load->buff + (offset))
#define IBF_OBJBODY(type, offset) (type *)(load->buff + sizeof(struct ibf_object_header) + (offset))

static void
ibf_dump_object_unsupported(struct ibf_dump *dump, VALUE obj)
{
    rb_obj_info_dump(obj);
    rb_bug("ibf_dump_object_unsupported: unsupported");
}

static VALUE
ibf_load_object_unsupported(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    rb_bug("unsupported");
    return Qnil;
}

static void
ibf_dump_object_class(struct ibf_dump *dump, VALUE obj)
{
    enum ibf_object_class_index cindex;
    if (obj == rb_cObject) {
	cindex = IBF_OBJECT_CLASS_OBJECT;
    }
    else if (obj == rb_cArray) {
	cindex = IBF_OBJECT_CLASS_ARRAY;
    }
    else if (obj == rb_eStandardError) {
	cindex = IBF_OBJECT_CLASS_STANDARD_ERROR;
    }
    else {
	rb_obj_info_dump(obj);
	rb_p(obj);
	rb_bug("unsupported class");
    }
    ibf_dump_write(dump, &cindex, sizeof(cindex));
}

static VALUE
ibf_load_object_class(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    enum ibf_object_class_index *cindexp = IBF_OBJBODY(enum ibf_object_class_index, offset);
    enum ibf_object_class_index cindex = *cindexp;

    switch (cindex) {
      case IBF_OBJECT_CLASS_OBJECT:
	return rb_cObject;
      case IBF_OBJECT_CLASS_ARRAY:
	return rb_cArray;
      case IBF_OBJECT_CLASS_STANDARD_ERROR:
	return rb_eStandardError;
    }

    rb_bug("ibf_load_object_class: unknown class (%d)", (int)cindex);
}


static void
ibf_dump_object_float(struct ibf_dump *dump, VALUE obj)
{
    double dbl = RFLOAT_VALUE(obj);
    ibf_dump_write(dump, &dbl, sizeof(dbl));
}

static VALUE
ibf_load_object_float(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    double *dblp = IBF_OBJBODY(double, offset);
    return DBL2NUM(*dblp);
}

static void
ibf_dump_object_string(struct ibf_dump *dump, VALUE obj)
{
    long encindex = (long)rb_enc_get_index(obj);
    long len = RSTRING_LEN(obj);
    const char *ptr = RSTRING_PTR(obj);

    if (encindex > RUBY_ENCINDEX_BUILTIN_MAX) {
	rb_encoding *enc = rb_enc_from_index((int)encindex);
	const char *enc_name = rb_enc_name(enc);
	encindex = RUBY_ENCINDEX_BUILTIN_MAX + ibf_dump_object(dump, rb_str_new2(enc_name));
    }

    IBF_WV(encindex);
    IBF_WV(len);
    IBF_WP(ptr, char, len);
}

static VALUE
ibf_load_object_string(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    const struct ibf_object_string *string = IBF_OBJBODY(struct ibf_object_string, offset);
    VALUE str = rb_str_new(string->ptr, string->len);
    int encindex = (int)string->encindex;

    if (encindex > RUBY_ENCINDEX_BUILTIN_MAX) {
	VALUE enc_name_str = ibf_load_object(load, encindex - RUBY_ENCINDEX_BUILTIN_MAX);
	encindex = rb_enc_find_index(RSTRING_PTR(enc_name_str));
    }
    rb_enc_associate_index(str, encindex);

    if (header->internal) rb_obj_hide(str);
    if (header->frozen)   str = rb_fstring(str);

    return str;
}

static void
ibf_dump_object_regexp(struct ibf_dump *dump, VALUE obj)
{
    struct ibf_object_regexp regexp;
    regexp.srcstr = RREGEXP_SRC(obj);
    regexp.option = (char)rb_reg_options(obj);
    regexp.srcstr = (long)ibf_dump_object(dump, regexp.srcstr);
    IBF_WV(regexp);
}

static VALUE
ibf_load_object_regexp(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    const struct ibf_object_regexp *regexp = IBF_OBJBODY(struct ibf_object_regexp, offset);
    VALUE srcstr = ibf_load_object(load, regexp->srcstr);
    VALUE reg = rb_reg_compile(srcstr, (int)regexp->option, NULL, 0);

    if (header->internal) rb_obj_hide(reg);
    if (header->frozen)   rb_obj_freeze(reg);

    return reg;
}

static void
ibf_dump_object_array(struct ibf_dump *dump, VALUE obj)
{
    long i, len = (int)RARRAY_LEN(obj);
    IBF_WV(len);
    for (i=0; i<len; i++) {
	long index = (long)ibf_dump_object(dump, RARRAY_AREF(obj, i));
	IBF_WV(index);
    }
}

static VALUE
ibf_load_object_array(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    const struct ibf_object_array *array = IBF_OBJBODY(struct ibf_object_array, offset);
    VALUE ary = rb_ary_new_capa(array->len);
    int i;

    for (i=0; i<array->len; i++) {
	rb_ary_push(ary, ibf_load_object(load, array->ary[i]));
    }

    if (header->internal) rb_obj_hide(ary);
    if (header->frozen)   rb_obj_freeze(ary);

    return ary;
}

static int
ibf_dump_object_hash_i(st_data_t key, st_data_t val, st_data_t ptr)
{
    struct ibf_dump *dump = (struct ibf_dump *)ptr;
    long key_index = (long)ibf_dump_object(dump, (VALUE)key);
    long val_index = (long)ibf_dump_object(dump, (VALUE)val);
    IBF_WV(key_index);
    IBF_WV(val_index);
    return ST_CONTINUE;
}

static void
ibf_dump_object_hash(struct ibf_dump *dump, VALUE obj)
{
    long len = RHASH_SIZE(obj);
    IBF_WV(len);
    if (len > 0) st_foreach(RHASH(obj)->ntbl, ibf_dump_object_hash_i, (st_data_t)dump);
}

static VALUE
ibf_load_object_hash(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    const struct ibf_object_hash *hash = IBF_OBJBODY(struct ibf_object_hash, offset);
    VALUE obj = rb_hash_new();
    int i;

    for (i=0; i<hash->len; i++) {
	VALUE key = ibf_load_object(load, hash->keyval[i*2  ]);
	VALUE val = ibf_load_object(load, hash->keyval[i*2+1]);
	rb_hash_aset(obj, key, val);
    }
    rb_hash_rehash(obj);

    if (header->internal) rb_obj_hide(obj);
    if (header->frozen)   rb_obj_freeze(obj);

    return obj;
}

static void
ibf_dump_object_struct(struct ibf_dump *dump, VALUE obj)
{
    if (rb_obj_is_kind_of(obj, rb_cRange)) {
	struct ibf_object_struct_range range;
	VALUE beg, end;
	range.len = 3;
	range.class_index = 0;

	rb_range_values(obj, &beg, &end, &range.excl);
	range.beg = (long)ibf_dump_object(dump, beg);
	range.end = (long)ibf_dump_object(dump, end);

	IBF_WV(range);
    }
    else {
	rb_bug("ibf_dump_object_struct: unsupported class");
    }
}

static VALUE
ibf_load_object_struct(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    const struct ibf_object_struct_range *range = IBF_OBJBODY(struct ibf_object_struct_range, offset);
    VALUE beg = ibf_load_object(load, range->beg);
    VALUE end = ibf_load_object(load, range->end);
    VALUE obj = rb_range_new(beg, end, range->excl);
    if (header->internal) rb_obj_hide(obj);
    if (header->frozen)   rb_obj_freeze(obj);
    return obj;
}

static void
ibf_dump_object_bignum(struct ibf_dump *dump, VALUE obj)
{
    ssize_t len = BIGNUM_LEN(obj);
    ssize_t slen = BIGNUM_SIGN(obj) > 0 ? len : len * -1;
    BDIGIT *d = BIGNUM_DIGITS(obj);

    IBF_WV(slen);
    IBF_WP(d, BDIGIT, len);
}

static VALUE
ibf_load_object_bignum(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    const struct ibf_object_bignum *bignum = IBF_OBJBODY(struct ibf_object_bignum, offset);
    int sign = bignum->slen > 0;
    ssize_t len = sign > 0 ? bignum->slen : -1 * bignum->slen;
    VALUE obj = rb_integer_unpack(bignum->digits, len * 2, 2, 0,
				  INTEGER_PACK_LITTLE_ENDIAN | (sign == 0 ? INTEGER_PACK_NEGATIVE : 0));
    if (header->internal) rb_obj_hide(obj);
    if (header->frozen)   rb_obj_freeze(obj);
    return obj;
}

static void
ibf_dump_object_data(struct ibf_dump *dump, VALUE obj)
{
    if (rb_data_is_encoding(obj)) {
	rb_encoding *enc = rb_to_encoding(obj);
	const char *name = rb_enc_name(enc);
	enum ibf_object_data_type type = IBF_OBJECT_DATA_ENCODING;
	long len = strlen(name) + 1;
	IBF_WV(type);
	IBF_WV(len);
	IBF_WP(name, char, strlen(name) + 1);
    }
    else {
	ibf_dump_object_unsupported(dump, obj);
    }
}

static VALUE
ibf_load_object_data(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    const enum ibf_object_data_type *typep = IBF_OBJBODY(enum ibf_object_data_type, offset);
    /* const long *lenp = IBF_OBJBODY(long, offset + sizeof(enum ibf_object_data_type)); */
    const char *data = IBF_OBJBODY(char, offset + sizeof(enum ibf_object_data_type) + sizeof(long));

    switch (*typep) {
      case IBF_OBJECT_DATA_ENCODING:
	{
	    VALUE encobj = rb_enc_from_encoding(rb_enc_find(data));
	    return encobj;
	}
    }

    return ibf_load_object_unsupported(load, header, offset);
}

static void
ibf_dump_object_complex_rational(struct ibf_dump *dump, VALUE obj)
{
    long real = (long)ibf_dump_object(dump, RCOMPLEX(obj)->real);
    long imag = (long)ibf_dump_object(dump, RCOMPLEX(obj)->imag);

    IBF_WV(real);
    IBF_WV(imag);
}

static VALUE
ibf_load_object_complex_rational(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    const struct ibf_object_complex_rational *nums = IBF_OBJBODY(struct ibf_object_complex_rational, offset);
    VALUE a = ibf_load_object(load, nums->a);
    VALUE b = ibf_load_object(load, nums->b);
    VALUE obj = header->type == T_COMPLEX ?
      rb_complex_new(a, b) : rb_rational_new(a, b);

    if (header->internal) rb_obj_hide(obj);
    if (header->frozen)   rb_obj_freeze(obj);
    return obj;
}

static void
ibf_dump_object_symbol(struct ibf_dump *dump, VALUE obj)
{
    VALUE str = rb_sym2str(obj);
    long str_index = (long)ibf_dump_object(dump, str);
    IBF_WV(str_index);
}

static VALUE
ibf_load_object_symbol(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t offset)
{
    /* const struct ibf_object_header *header = IBF_OBJHEADER(offset); */
    const struct ibf_object_symbol *symbol = IBF_OBJBODY(struct ibf_object_symbol, offset);
    VALUE str = ibf_load_object(load, symbol->str);
    ID id = rb_intern_str(str);
    return ID2SYM(id);
}

typedef void (*ibf_dump_object_function)(struct ibf_dump *dump, VALUE obj);
static ibf_dump_object_function dump_object_functions[RUBY_T_MASK+1] = {
    ibf_dump_object_unsupported, /* T_NONE */
    ibf_dump_object_unsupported, /* T_OBJECT */
    ibf_dump_object_class,       /* T_CLASS */
    ibf_dump_object_unsupported, /* T_MODULE */
    ibf_dump_object_float,       /* T_FLOAT */
    ibf_dump_object_string,      /* T_STRING */
    ibf_dump_object_regexp,      /* T_REGEXP */
    ibf_dump_object_array,       /* T_ARRAY */
    ibf_dump_object_hash,        /* T_HASH */
    ibf_dump_object_struct,      /* T_STRUCT */
    ibf_dump_object_bignum,      /* T_BIGNUM */
    ibf_dump_object_unsupported, /* T_FILE */
    ibf_dump_object_data,        /* T_DATA */
    ibf_dump_object_unsupported, /* T_MATCH */
    ibf_dump_object_complex_rational, /* T_COMPLEX */
    ibf_dump_object_complex_rational, /* T_RATIONAL */
    ibf_dump_object_unsupported, /* 0x10 */
    ibf_dump_object_unsupported, /* 0x11 T_NIL */
    ibf_dump_object_unsupported, /* 0x12 T_TRUE */
    ibf_dump_object_unsupported, /* 0x13 T_FALSE */
    ibf_dump_object_symbol,      /* 0x14 T_SYMBOL */
    ibf_dump_object_unsupported, /* T_FIXNUM */
    ibf_dump_object_unsupported, /* T_UNDEF */
    ibf_dump_object_unsupported, /* 0x17 */
    ibf_dump_object_unsupported, /* 0x18 */
    ibf_dump_object_unsupported, /* 0x19 */
    ibf_dump_object_unsupported, /* T_IMEMO 0x1a */
    ibf_dump_object_unsupported, /* T_NODE 0x1b */
    ibf_dump_object_unsupported, /* T_ICLASS 0x1c */
    ibf_dump_object_unsupported, /* T_ZOMBIE 0x1d */
    ibf_dump_object_unsupported, /* 0x1e */
    ibf_dump_object_unsupported  /* 0x1f */
};

static ibf_offset_t
lbf_dump_object_object(struct ibf_dump *dump, VALUE obj)
{
    struct ibf_object_header obj_header;
    ibf_offset_t current_offset = ibf_dump_pos(dump);
    obj_header.type = TYPE(obj);

    if (SPECIAL_CONST_P(obj)) {
	if (RB_TYPE_P(obj, T_SYMBOL) ||
	    RB_TYPE_P(obj, T_FLOAT)) {
	    obj_header.internal = FALSE;
	    goto dump_object;
	}
	obj_header.special_const = TRUE;
	obj_header.frozen = TRUE;
	obj_header.internal = TRUE;
	IBF_WV(obj_header);
	IBF_WV(obj);
    }
    else {
	obj_header.internal = (RBASIC_CLASS(obj) == 0) ? TRUE : FALSE;
      dump_object:
	obj_header.special_const = FALSE;
	obj_header.frozen = FL_TEST(obj, FL_FREEZE) ? TRUE : FALSE;
	IBF_WV(obj_header);
	(*dump_object_functions[obj_header.type])(dump, obj);
    }

    return current_offset;
}

typedef VALUE (*ibf_load_object_function)(const struct ibf_load *load, const struct ibf_object_header *header, ibf_offset_t);
static ibf_load_object_function load_object_functions[RUBY_T_MASK+1] = {
    ibf_load_object_unsupported, /* T_NONE */
    ibf_load_object_unsupported, /* T_OBJECT */
    ibf_load_object_class,       /* T_CLASS */
    ibf_load_object_unsupported, /* T_MODULE */
    ibf_load_object_float,       /* T_FLOAT */
    ibf_load_object_string,      /* T_STRING */
    ibf_load_object_regexp,      /* T_REGEXP */
    ibf_load_object_array,       /* T_ARRAY */
    ibf_load_object_hash,        /* T_HASH */
    ibf_load_object_struct,      /* T_STRUCT */
    ibf_load_object_bignum,      /* T_BIGNUM */
    ibf_load_object_unsupported, /* T_FILE */
    ibf_load_object_data,        /* T_DATA */
    ibf_load_object_unsupported, /* T_MATCH */
    ibf_load_object_complex_rational, /* T_COMPLEX */
    ibf_load_object_complex_rational, /* T_RATIONAL */
    ibf_load_object_unsupported, /* 0x10 */
    ibf_load_object_unsupported, /* T_NIL */
    ibf_load_object_unsupported, /* T_TRUE */
    ibf_load_object_unsupported, /* T_FALSE */
    ibf_load_object_symbol,
    ibf_load_object_unsupported, /* T_FIXNUM */
    ibf_load_object_unsupported, /* T_UNDEF */
    ibf_load_object_unsupported, /* 0x17 */
    ibf_load_object_unsupported, /* 0x18 */
    ibf_load_object_unsupported, /* 0x19 */
    ibf_load_object_unsupported, /* T_IMEMO 0x1a */
    ibf_load_object_unsupported, /* T_NODE 0x1b */
    ibf_load_object_unsupported, /* T_ICLASS 0x1c */
    ibf_load_object_unsupported, /* T_ZOMBIE 0x1d */
    ibf_load_object_unsupported, /* 0x1e */
    ibf_load_object_unsupported  /* 0x1f */
};

static VALUE
ibf_load_object(const struct ibf_load *load, VALUE object_index)
{
    if (object_index == 0) {
	return Qnil;
    }
    else if (object_index >= load->header->object_list_size) {
	rb_raise(rb_eIndexError, "object index out of range: %"PRIdVALUE, object_index);
    }
    else {
	VALUE obj = rb_ary_entry(load->obj_list, (long)object_index);
	if (obj == Qnil) { /* TODO: avoid multiple Qnil load */
	    ibf_offset_t *offsets = (ibf_offset_t *)(load->header->object_list_offset + load->buff);
	    ibf_offset_t offset = offsets[object_index];
	    const struct ibf_object_header *header = IBF_OBJHEADER(offset);

	    if (header->special_const) {
		VALUE *vp = IBF_OBJBODY(VALUE, offset);
		obj = *vp;
	    }
	    else {
		obj = (*load_object_functions[header->type])(load, header, offset);
	    }

	    rb_ary_store(load->obj_list, (long)object_index, obj);
	}
	iseq_add_mark_object(load->iseq, obj);
	return obj;
    }
}

static void
ibf_dump_object_list(struct ibf_dump *dump, struct ibf_header *header)
{
    VALUE list = rb_ary_tmp_new(RARRAY_LEN(dump->obj_list));
    int i, size;

    for (i=0; i<RARRAY_LEN(dump->obj_list); i++) {
	VALUE obj = RARRAY_AREF(dump->obj_list, i);
	ibf_offset_t offset = lbf_dump_object_object(dump, obj);
	rb_ary_push(list, UINT2NUM(offset));
    }
    size = i;
    header->object_list_offset = ibf_dump_pos(dump);

    for (i=0; i<size; i++) {
	ibf_offset_t offset = NUM2UINT(RARRAY_AREF(list, i));
	IBF_WV(offset);
    }

    header->object_list_size = size;
}

static void
ibf_dump_mark(void *ptr)
{
    struct ibf_dump *dump = (struct ibf_dump *)ptr;
    rb_gc_mark(dump->str);
    rb_gc_mark(dump->iseq_list);
    rb_gc_mark(dump->obj_list);
}

static void
ibf_dump_free(void *ptr)
{
    struct ibf_dump *dump = (struct ibf_dump *)ptr;
    if (dump->iseq_table) {
	st_free_table(dump->iseq_table);
	dump->iseq_table = 0;
    }
    if (dump->id_table) {
	st_free_table(dump->id_table);
	dump->id_table = 0;
    }
    ruby_xfree(dump);
}

static size_t
ibf_dump_memsize(const void *ptr)
{
    struct ibf_dump *dump = (struct ibf_dump *)ptr;
    size_t size = sizeof(*dump);
    if (dump->iseq_table) size += st_memsize(dump->iseq_table);
    if (dump->id_table) size += st_memsize(dump->id_table);
    return size;
}

static const rb_data_type_t ibf_dump_type = {
    "ibf_dump",
    {ibf_dump_mark, ibf_dump_free, ibf_dump_memsize,},
    0, 0, RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY
};

static void
ibf_dump_setup(struct ibf_dump *dump, VALUE dumper_obj)
{
    RB_OBJ_WRITE(dumper_obj, &dump->str, rb_str_new(0, 0));
    RB_OBJ_WRITE(dumper_obj, &dump->iseq_list, rb_ary_tmp_new(0));
    RB_OBJ_WRITE(dumper_obj, &dump->obj_list, rb_ary_tmp_new(1));
    rb_ary_push(dump->obj_list, Qnil); /* 0th is nil */
    dump->iseq_table = st_init_numtable(); /* need free */
    dump->id_table = st_init_numtable();   /* need free */

    ibf_table_index(dump->id_table, 0); /* id_index:0 is 0 */
}

VALUE
iseq_ibf_dump(const rb_iseq_t *iseq, VALUE opt)
{
    struct ibf_dump *dump;
    struct ibf_header header = {{0}};
    VALUE dump_obj;
    VALUE str;

    if (iseq->body->parent_iseq != NULL ||
	iseq->body->local_iseq != iseq) {
	rb_raise(rb_eRuntimeError, "should be top of iseq");
    }
    if (RTEST(ISEQ_COVERAGE(iseq))) {
	rb_raise(rb_eRuntimeError, "should not compile with coverage");
    }

    dump_obj = TypedData_Make_Struct(0, struct ibf_dump, &ibf_dump_type, dump);
    ibf_dump_setup(dump, dump_obj);

    ibf_dump_write(dump, &header, sizeof(header));
    ibf_dump_write(dump, RUBY_PLATFORM, strlen(RUBY_PLATFORM) + 1);
    ibf_dump_iseq(dump, iseq);

    header.magic[0] = 'Y'; /* YARB */
    header.magic[1] = 'A';
    header.magic[2] = 'R';
    header.magic[3] = 'B';
    header.major_version = ISEQ_MAJOR_VERSION;
    header.minor_version = ISEQ_MINOR_VERSION;
    ibf_dump_iseq_list(dump, &header);
    ibf_dump_id_list(dump, &header);
    ibf_dump_object_list(dump, &header);
    header.size = ibf_dump_pos(dump);

    if (RTEST(opt)) {
	VALUE opt_str = opt;
	const char *ptr = StringValuePtr(opt_str);
	header.extra_size = RSTRING_LENINT(opt_str);
	ibf_dump_write(dump, ptr, header.extra_size);
    }
    else {
	header.extra_size = 0;
    }

    ibf_dump_overwrite(dump, &header, sizeof(header), 0);

    str = dump->str;
    ibf_dump_free(dump);
    DATA_PTR(dump_obj) = NULL;
    RB_GC_GUARD(dump_obj);
    return str;
}

static const ibf_offset_t *
ibf_iseq_list(const struct ibf_load *load)
{
    return (ibf_offset_t *)(load->buff + load->header->iseq_list_offset);
}

void
ibf_load_iseq_complete(rb_iseq_t *iseq)
{
    struct ibf_load *load = RTYPEDDATA_DATA(iseq->aux.loader.obj);
    rb_iseq_t *prev_src_iseq = load->iseq;
    load->iseq = iseq;
    ibf_load_iseq_each(load, iseq, ibf_iseq_list(load)[iseq->aux.loader.index]);
    ISEQ_COMPILE_DATA(iseq) = NULL;
    FL_UNSET(iseq, ISEQ_NOT_LOADED_YET);
    load->iseq = prev_src_iseq;
}

#if USE_LAZY_LOAD
const rb_iseq_t *
rb_iseq_complete(const rb_iseq_t *iseq)
{
    ibf_load_iseq_complete((rb_iseq_t *)iseq);
    return iseq;
}
#endif

static rb_iseq_t *
ibf_load_iseq(const struct ibf_load *load, const rb_iseq_t *index_iseq)
{
    int iseq_index = (int)(VALUE)index_iseq;

    if (iseq_index == -1) {
	return NULL;
    }
    else {
	VALUE iseqv = rb_ary_entry(load->iseq_list, iseq_index);

	if (iseqv != Qnil) {
	    return (rb_iseq_t *)iseqv;
	}
	else {
	    rb_iseq_t *iseq = iseq_imemo_alloc();
	    FL_SET(iseq, ISEQ_NOT_LOADED_YET);
	    iseq->aux.loader.obj = load->loader_obj;
	    iseq->aux.loader.index = iseq_index;
	    rb_ary_store(load->iseq_list, iseq_index, (VALUE)iseq);

#if !USE_LAZY_LOAD
	    ibf_load_iseq_complete(iseq);
#endif /* !USE_LAZY_LOAD */

	    if (load->iseq) {
		iseq_add_mark_object(load->iseq, (VALUE)iseq);
	    }
	    return iseq;
	}
    }
}

static void
ibf_load_setup(struct ibf_load *load, VALUE loader_obj, VALUE str)
{
    rb_check_safe_obj(str);

    if (RSTRING_LENINT(str) < (int)sizeof(struct ibf_header)) {
	rb_raise(rb_eRuntimeError, "broken binary format");
    }
    RB_OBJ_WRITE(loader_obj, &load->str, str);
    load->loader_obj = loader_obj;
    load->buff = StringValuePtr(str);
    load->header = (struct ibf_header *)load->buff;
    RB_OBJ_WRITE(loader_obj, &load->iseq_list, rb_ary_tmp_new(0));
    RB_OBJ_WRITE(loader_obj, &load->obj_list, rb_ary_tmp_new(0));
    load->id_list = ZALLOC_N(ID, load->header->id_list_size);
    load->iseq = NULL;

    if (RSTRING_LENINT(str) < (int)load->header->size) {
	rb_raise(rb_eRuntimeError, "broken binary format");
    }
    if (strncmp(load->header->magic, "YARB", 4) != 0) {
	rb_raise(rb_eRuntimeError, "unknown binary format");
    }
    if (load->header->major_version != ISEQ_MAJOR_VERSION ||
	load->header->minor_version != ISEQ_MINOR_VERSION) {
	rb_raise(rb_eRuntimeError, "unmatched version file (%u.%u for %u.%u)",
		 load->header->major_version, load->header->minor_version, ISEQ_MAJOR_VERSION, ISEQ_MINOR_VERSION);
    }
    if (strcmp(load->buff + sizeof(struct ibf_header), RUBY_PLATFORM) != 0) {
	rb_raise(rb_eRuntimeError, "unmatched platform");
    }
}

static void
ibf_loader_mark(void *ptr)
{
    if (ptr) {
	struct ibf_load *load = (struct ibf_load *)ptr;
	rb_gc_mark(load->str);
	rb_gc_mark(load->iseq_list);
	rb_gc_mark(load->obj_list);
    }
}

static void
ibf_loader_free(void *ptr)
{
    if (ptr) {
	struct ibf_load *load = (struct ibf_load *)ptr;
	ruby_xfree(load->id_list);
	ruby_xfree(load);
    }
}

static size_t
ibf_loader_memsize(const void *ptr)
{
    struct ibf_load *load = (struct ibf_load *)ptr;
    return sizeof(struct ibf_load) + load->header->id_list_size * sizeof(ID);
}

static const rb_data_type_t ibf_load_type = {
    "ibf_loader",
    {ibf_loader_mark, ibf_loader_free, ibf_loader_memsize,},
    0, 0, RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY
};

const rb_iseq_t *
iseq_ibf_load(VALUE str)
{
    struct ibf_load *load;
    const rb_iseq_t *iseq;
    VALUE loader_obj = TypedData_Make_Struct(0, struct ibf_load, &ibf_load_type, load);

    ibf_load_setup(load, loader_obj, str);
    iseq = ibf_load_iseq(load, 0);

    RB_GC_GUARD(loader_obj);
    return iseq;
}

VALUE
iseq_ibf_load_extra_data(VALUE str)
{
    struct ibf_load *load;
    VALUE loader_obj = TypedData_Make_Struct(0, struct ibf_load, &ibf_load_type, load);
    VALUE extra_str;

    ibf_load_setup(load, loader_obj, str);
    extra_str = rb_str_new(load->buff + load->header->size, load->header->extra_size);
    RB_GC_GUARD(loader_obj);
    return extra_str;
}
