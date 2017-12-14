/**********************************************************************

  parse.y -

  $Author$
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

%{

#if !YYPURE
# error needs pure parser
#endif
#ifndef PARSER_DEBUG
#define PARSER_DEBUG 0
#endif
#define YYDEBUG 1
#define YYERROR_VERBOSE 1
#define YYSTACK_USE_ALLOCA 0
#define YYLTYPE rb_code_range_t
#define YYLTYPE_IS_DECLARED 1

#include "ruby/ruby.h"
#include "ruby/st.h"
#include "ruby/encoding.h"
#include "internal.h"
#include "node.h"
#include "parse.h"
#include "symbol.h"
#include "regenc.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include "probes.h"

#ifndef WARN_PAST_SCOPE
# define WARN_PAST_SCOPE 0
#endif

#define TAB_WIDTH 8

#define YYMALLOC(size)		rb_parser_malloc(parser, (size))
#define YYREALLOC(ptr, size)	rb_parser_realloc(parser, (ptr), (size))
#define YYCALLOC(nelem, size)	rb_parser_calloc(parser, (nelem), (size))
#define YYFREE(ptr)		rb_parser_free(parser, (ptr))
#define YYFPRINTF		rb_parser_printf
#define YY_LOCATION_PRINT(File, Loc) \
     rb_parser_printf(parser, "%d.%d-%d.%d", \
		      (Loc).first_loc.lineno, (Loc).first_loc.column,\
		      (Loc).last_loc.lineno, (Loc).last_loc.column)
#define YYLLOC_DEFAULT(Current, Rhs, N)					\
    do									\
      if (N)								\
	{								\
	  (Current).first_loc = YYRHSLOC(Rhs, 1).first_loc;		\
	  (Current).last_loc  = YYRHSLOC(Rhs, N).last_loc;		\
	}								\
      else								\
	RUBY_SET_YYLLOC_OF_NONE(Current);				\
    while (0)

#define RUBY_SET_YYLLOC_FROM_STRTERM_HEREDOC(Current)			\
    rb_parser_set_location_from_strterm_heredoc(parser, &lex_strterm->u.heredoc, &(Current))
#define RUBY_SET_YYLLOC_OF_NONE(Current)					\
    rb_parser_set_location_of_none(parser, &(Current))
#define RUBY_SET_YYLLOC(Current)					\
    rb_parser_set_location(parser, &(Current))

#undef malloc
#undef realloc
#undef calloc
#undef free
#define malloc	YYMALLOC
#define realloc	YYREALLOC
#define calloc	YYCALLOC
#define free	YYFREE

enum lex_state_bits {
    EXPR_BEG_bit,		/* ignore newline, +/- is a sign. */
    EXPR_END_bit,		/* newline significant, +/- is an operator. */
    EXPR_ENDARG_bit,		/* ditto, and unbound braces. */
    EXPR_ENDFN_bit,		/* ditto, and unbound braces. */
    EXPR_ARG_bit,		/* newline significant, +/- is an operator. */
    EXPR_CMDARG_bit,		/* newline significant, +/- is an operator. */
    EXPR_MID_bit,		/* newline significant, +/- is an operator. */
    EXPR_FNAME_bit,		/* ignore newline, no reserved words. */
    EXPR_DOT_bit,		/* right after `.' or `::', no reserved words. */
    EXPR_CLASS_bit,		/* immediate after `class', no here document. */
    EXPR_LABEL_bit,		/* flag bit, label is allowed. */
    EXPR_LABELED_bit,		/* flag bit, just after a label. */
    EXPR_FITEM_bit,		/* symbol literal as FNAME. */
    EXPR_MAX_STATE
};
/* examine combinations */
enum lex_state_e {
#define DEF_EXPR(n) EXPR_##n = (1 << EXPR_##n##_bit)
    DEF_EXPR(BEG),
    DEF_EXPR(END),
    DEF_EXPR(ENDARG),
    DEF_EXPR(ENDFN),
    DEF_EXPR(ARG),
    DEF_EXPR(CMDARG),
    DEF_EXPR(MID),
    DEF_EXPR(FNAME),
    DEF_EXPR(DOT),
    DEF_EXPR(CLASS),
    DEF_EXPR(LABEL),
    DEF_EXPR(LABELED),
    DEF_EXPR(FITEM),
    EXPR_VALUE = EXPR_BEG,
    EXPR_BEG_ANY  =  (EXPR_BEG | EXPR_MID | EXPR_CLASS),
    EXPR_ARG_ANY  =  (EXPR_ARG | EXPR_CMDARG),
    EXPR_END_ANY  =  (EXPR_END | EXPR_ENDARG | EXPR_ENDFN)
};
#define IS_lex_state_for(x, ls)	((x) & (ls))
#define IS_lex_state_all_for(x, ls) (((x) & (ls)) == (ls))
#define IS_lex_state(ls)	IS_lex_state_for(lex_state, (ls))
#define IS_lex_state_all(ls)	IS_lex_state_all_for(lex_state, (ls))

# define SET_LEX_STATE(ls) \
    (lex_state = \
     (yydebug ? \
      rb_parser_trace_lex_state(parser, lex_state, (ls), __LINE__) : \
      (enum lex_state_e)(ls)))

typedef VALUE stack_type;

# define SHOW_BITSTACK(stack, name) (yydebug ? rb_parser_show_bitstack(parser, stack, name, __LINE__) : (void)0)
# define BITSTACK_PUSH(stack, n) (((stack) = ((stack)<<1)|((n)&1)), SHOW_BITSTACK(stack, #stack"(push)"))
# define BITSTACK_POP(stack)	 (((stack) = (stack) >> 1), SHOW_BITSTACK(stack, #stack"(pop)"))
# define BITSTACK_LEXPOP(stack)	 (((stack) = ((stack) >> 1) | ((stack) & 1)), SHOW_BITSTACK(stack, #stack"(lexpop)"))
# define BITSTACK_SET_P(stack)	 (SHOW_BITSTACK(stack, #stack), (stack)&1)
# define BITSTACK_SET(stack, n)	 ((stack)=(n), SHOW_BITSTACK(stack, #stack"(set)"))

#define COND_PUSH(n)	BITSTACK_PUSH(cond_stack, (n))
#define COND_POP()	BITSTACK_POP(cond_stack)
#define COND_LEXPOP()	BITSTACK_LEXPOP(cond_stack)
#define COND_P()	BITSTACK_SET_P(cond_stack)
#define COND_SET(n)	BITSTACK_SET(cond_stack, (n))

#define CMDARG_PUSH(n)	BITSTACK_PUSH(cmdarg_stack, (n))
#define CMDARG_POP()	BITSTACK_POP(cmdarg_stack)
#define CMDARG_LEXPOP()	BITSTACK_LEXPOP(cmdarg_stack)
#define CMDARG_P()	BITSTACK_SET_P(cmdarg_stack)
#define CMDARG_SET(n)	BITSTACK_SET(cmdarg_stack, (n))

struct vtable {
    ID *tbl;
    int pos;
    int capa;
    struct vtable *prev;
};

struct local_vars {
    struct vtable *args;
    struct vtable *vars;
    struct vtable *used;
# if WARN_PAST_SCOPE
    struct vtable *past;
# endif
    struct local_vars *prev;
    stack_type cmdargs;
};

#define DVARS_INHERIT ((void*)1)
#define DVARS_TOPSCOPE NULL
#define DVARS_SPECIAL_P(tbl) (!POINTER_P(tbl))
#define POINTER_P(val) ((VALUE)(val) & ~(VALUE)3)

typedef struct token_info {
    const char *token;
    int linenum;
    int column;
    int nonspc;
    struct token_info *next;
} token_info;

typedef struct rb_strterm_struct rb_strterm_t;

/*
    Structure of Lexer Buffer:

 lex_pbeg      tokp         lex_p        lex_pend
    |           |              |            |
    |-----------+--------------+------------|
                |<------------>|
                     token
*/
struct parser_params {
    rb_imemo_alloc_t *heap;

    YYSTYPE *lval;

    struct {
	rb_strterm_t *strterm;
	VALUE (*gets)(struct parser_params*,VALUE);
	VALUE input;
	VALUE prevline;
	VALUE lastline;
	VALUE nextline;
	const char *pbeg;
	const char *pcur;
	const char *pend;
	const char *ptok;
	long gets_ptr;
	enum lex_state_e state;
	int paren_nest;
	int lpar_beg;
	int brace_nest;
    } lex;
    stack_type cond_stack;
    stack_type cmdarg_stack;
    int tokidx;
    int toksiz;
    int tokline;
    int heredoc_end;
    int heredoc_indent;
    int heredoc_line_indent;
    char *tokenbuf;
    struct local_vars *lvtbl;
    int line_count;
    int ruby_sourceline;	/* current line no. */
    char *ruby_sourcefile; /* current source file */
    VALUE ruby_sourcefile_string;
    rb_encoding *enc;
    token_info *token_info;
    VALUE compile_option;

    VALUE debug_buffer;
    VALUE debug_output;

    ID cur_arg;

    rb_ast_t *ast;

    unsigned int command_start:1;
    unsigned int eofp: 1;
    unsigned int ruby__end__seen: 1;
    unsigned int yydebug: 1;
    unsigned int has_shebang: 1;
    unsigned int in_defined: 1;
    unsigned int in_main: 1;
    unsigned int in_kwarg: 1;
    unsigned int in_def: 1;
    unsigned int in_class: 1;
    unsigned int token_seen: 1;
    unsigned int token_info_enabled: 1;
# if WARN_PAST_SCOPE
    unsigned int past_scope_enabled: 1;
# endif
    unsigned int error_p: 1;
    unsigned int cr_seen: 1;

#ifndef RIPPER
    /* Ruby core only */

    unsigned int do_print: 1;
    unsigned int do_loop: 1;
    unsigned int do_chomp: 1;
    unsigned int do_split: 1;

    NODE *eval_tree_begin;
    NODE *eval_tree;
    VALUE error_buffer;
    VALUE debug_lines;
    VALUE coverage;
    const struct rb_block *base_block;
#else
    /* Ripper only */

    VALUE delayed;
    int delayed_line;
    int delayed_col;

    VALUE value;
    VALUE result;
    VALUE parsing_thread;
#endif
};

#define intern_cstr(n,l,en) rb_intern3(n,l,en)

#define STR_NEW(p,n) rb_enc_str_new((p),(n),current_enc)
#define STR_NEW0() rb_enc_str_new(0,0,current_enc)
#define STR_NEW2(p) rb_enc_str_new((p),strlen(p),current_enc)
#define STR_NEW3(p,n,e,func) parser_str_new((p),(n),(e),(func),current_enc)
#define TOK_INTERN() intern_cstr(tok(), toklen(), current_enc)

static int parser_yyerror(struct parser_params*, const char*);
#define yyerror0(msg) parser_yyerror(parser, (msg))
#define yyerror(yylloc, parser, msg) yyerror0(msg)
#define token_flush(p) ((p)->lex.ptok = (p)->lex.pcur)

#define lex_strterm		(parser->lex.strterm)
#define lex_state		(parser->lex.state)
#define cond_stack		(parser->cond_stack)
#define cmdarg_stack		(parser->cmdarg_stack)
#define paren_nest		(parser->lex.paren_nest)
#define lpar_beg		(parser->lex.lpar_beg)
#define brace_nest		(parser->lex.brace_nest)
#define in_def			(parser->in_def)
#define in_class		(parser->in_class)
#define in_main 		(parser->in_main)
#define in_defined		(parser->in_defined)
#define tokenbuf		(parser->tokenbuf)
#define tokidx			(parser->tokidx)
#define toksiz			(parser->toksiz)
#define tokline 		(parser->tokline)
#define lex_input		(parser->lex.input)
#define lex_prevline		(parser->lex.prevline)
#define lex_lastline		(parser->lex.lastline)
#define lex_nextline		(parser->lex.nextline)
#define lex_pbeg		(parser->lex.pbeg)
#define lex_p			(parser->lex.pcur)
#define lex_pend		(parser->lex.pend)
#define heredoc_end		(parser->heredoc_end)
#define heredoc_indent		(parser->heredoc_indent)
#define heredoc_line_indent	(parser->heredoc_line_indent)
#define command_start		(parser->command_start)
#define lex_gets_ptr		(parser->lex.gets_ptr)
#define lex_gets		(parser->lex.gets)
#define lvtbl			(parser->lvtbl)
#define ruby__end__seen 	(parser->ruby__end__seen)
#define ruby_sourceline 	(parser->ruby_sourceline)
#define ruby_sourcefile 	(parser->ruby_sourcefile)
#define ruby_sourcefile_string	(parser->ruby_sourcefile_string)
#define current_enc		(parser->enc)
#define current_arg		(parser->cur_arg)
#define yydebug 		(parser->yydebug)
#ifdef RIPPER
#define compile_for_eval	(0)
#else
#define compile_for_eval	(parser->base_block != 0 && !in_main)
#define ruby_eval_tree		(parser->eval_tree)
#define ruby_eval_tree_begin	(parser->eval_tree_begin)
#define ruby_debug_lines	(parser->debug_lines)
#define ruby_coverage		(parser->coverage)
#endif
#define tokp			lex.ptok

#define token_column		((int)(parser->tokp - lex_pbeg))

#define CALL_Q_P(q) ((q) == TOKEN2VAL(tANDDOT))
#define NODE_CALL_Q(q) (CALL_Q_P(q) ? NODE_QCALL : NODE_CALL)
#define NEW_QCALL(q,r,m,a) NEW_NODE(NODE_CALL_Q(q),r,m,a)

#define lambda_beginning_p() (lpar_beg && lpar_beg == paren_nest)

static enum yytokentype yylex(YYSTYPE*, YYLTYPE*, struct parser_params*);

#ifndef RIPPER
static inline void
rb_discard_node_gen(struct parser_params *parser, NODE *n)
{
    rb_ast_delete_node(parser->ast, n);
}
#define rb_discard_node(n) rb_discard_node_gen(parser, (n))
#endif

static inline void
add_mark_object_gen(struct parser_params *parser, VALUE obj)
{
    if (!SPECIAL_CONST_P(obj)
#ifdef RIPPER
	&& !RB_TYPE_P(obj, T_NODE) /* Ripper jumbles NODE objects and other objects... */
#endif
    ) {
	rb_ast_add_mark_object(parser->ast, obj);
    }
}
#define add_mark_object(obj) add_mark_object_gen(parser, (obj))

static NODE* node_newnode(struct parser_params *, enum node_type, VALUE, VALUE, VALUE);
#define rb_node_newnode(type, a1, a2, a3) node_newnode(parser, (type), (a1), (a2), (a3))

#ifndef RIPPER
static inline void
set_line_body(NODE *body, int line)
{
    if (!body) return;
    switch (nd_type(body)) {
      case NODE_RESCUE:
      case NODE_ENSURE:
	nd_set_line(body, line);
    }
}

#define yyparse ruby_yyparse

static NODE *cond_gen(struct parser_params*,NODE*,int,const YYLTYPE*);
#define cond(node,location) cond_gen(parser, (node), FALSE, location)
#define method_cond(node,location) cond_gen(parser, (node), TRUE, location)
static NODE *new_nil_gen(struct parser_params*,const YYLTYPE*);
#define new_nil(location) new_nil_gen(parser,location)
static NODE *new_if_gen(struct parser_params*,NODE*,NODE*,NODE*,const YYLTYPE*);
#define new_if(cc,left,right,location) new_if_gen(parser, (cc), (left), (right), (location))
static NODE *new_unless_gen(struct parser_params*,NODE*,NODE*,NODE*,const YYLTYPE*);
#define new_unless(cc,left,right,location) new_unless_gen(parser, (cc), (left), (right), (location))
static NODE *logop_gen(struct parser_params*,enum node_type,NODE*,NODE*,const YYLTYPE*,const YYLTYPE*);
#define logop(id,node1,node2,op_loc,location) \
    logop_gen(parser, ((id)==idAND||(id)==idANDOP)?NODE_AND:NODE_OR, \
	      (node1), (node2), (op_loc), (location))

static NODE *newline_node(NODE*);
static void fixpos(NODE*,NODE*);

static int value_expr_gen(struct parser_params*,NODE*);
static void void_expr_gen(struct parser_params*,NODE*);
static NODE *remove_begin(NODE*);
static NODE *remove_begin_all(NODE*);
#define value_expr(node) value_expr_gen(parser, (node) = remove_begin(node))
#define void_expr0(node) void_expr_gen(parser, (node))
#define void_expr(node) void_expr0((node) = remove_begin(node))
static void void_stmts_gen(struct parser_params*,NODE*);
#define void_stmts(node) void_stmts_gen(parser, (node))
static void reduce_nodes_gen(struct parser_params*,NODE**);
#define reduce_nodes(n) reduce_nodes_gen(parser,(n))
static void block_dup_check_gen(struct parser_params*,NODE*,NODE*);
#define block_dup_check(n1,n2) block_dup_check_gen(parser,(n1),(n2))

static NODE *block_append_gen(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
#define block_append(h,t,location) block_append_gen(parser,(h),(t),(location))
static NODE *list_append_gen(struct parser_params*,NODE*,NODE*);
#define list_append(l,i) list_append_gen(parser,(l),(i))
static NODE *list_concat(NODE*,NODE*);
static NODE *arg_append_gen(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
#define arg_append(h,t,location) arg_append_gen(parser,(h),(t),(location))
static NODE *arg_concat_gen(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
#define arg_concat(h,t,location) arg_concat_gen(parser,(h),(t),(location))
static NODE *literal_concat_gen(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
#define literal_concat(h,t,location) literal_concat_gen(parser,(h),(t),(location))
static int literal_concat0(struct parser_params *, VALUE, VALUE);
static NODE *new_evstr_gen(struct parser_params*,NODE*,const YYLTYPE*);
#define new_evstr(n, location) new_evstr_gen(parser,(n),(location))
static NODE *evstr2dstr_gen(struct parser_params*,NODE*);
#define evstr2dstr(n) evstr2dstr_gen(parser,(n))
static NODE *splat_array(NODE*);

static NODE *call_bin_op_gen(struct parser_params*,NODE*,ID,NODE*,const YYLTYPE*,const YYLTYPE*);
#define call_bin_op(recv,id,arg1,op_loc,location) call_bin_op_gen(parser, (recv),(id),(arg1),(op_loc),(location))
static NODE *call_uni_op_gen(struct parser_params*,NODE*,ID,const YYLTYPE*,const YYLTYPE*);
#define call_uni_op(recv,id,op_loc,location) call_uni_op_gen(parser, (recv),(id),(op_loc),(location))
static NODE *new_qcall_gen(struct parser_params* parser, ID atype, NODE *recv, ID mid, NODE *args, const YYLTYPE *location);
#define new_qcall(q,r,m,a,location) new_qcall_gen(parser,q,r,m,a,location)
#define new_command_qcall(q,r,m,a,location) new_qcall_gen(parser,q,r,m,a,location)
static NODE *new_command_gen(struct parser_params*parser, NODE *m, NODE *a) {m->nd_args = a; return m;}
#define new_command(m,a) new_command_gen(parser, m, a)
static NODE *method_add_block_gen(struct parser_params*parser, NODE *m, NODE *b) {b->nd_iter = m; return b;}
#define method_add_block(m,b) method_add_block_gen(parser, m, b)

static NODE *new_args_gen(struct parser_params*,NODE*,NODE*,ID,NODE*,NODE*,const YYLTYPE*);
#define new_args(f,o,r,p,t,location) new_args_gen(parser, (f),(o),(r),(p),(t),(location))
static NODE *new_args_tail_gen(struct parser_params*,NODE*,ID,ID,const YYLTYPE*);
#define new_args_tail(k,kr,b,location) new_args_tail_gen(parser, (k),(kr),(b),(location))
static NODE *new_kw_arg_gen(struct parser_params *parser, NODE *k, const YYLTYPE *location);
#define new_kw_arg(k,location) new_kw_arg_gen(parser, k, location)

static VALUE negate_lit_gen(struct parser_params*, VALUE);
#define negate_lit(lit) negate_lit_gen(parser, lit)
static NODE *ret_args_gen(struct parser_params*,NODE*);
#define ret_args(node) ret_args_gen(parser, (node))
static NODE *arg_blk_pass(NODE*,NODE*);
static NODE *new_yield_gen(struct parser_params*,NODE*,const YYLTYPE*);
#define new_yield(node,location) new_yield_gen(parser, (node), (location))
static NODE *dsym_node_gen(struct parser_params*,NODE*,const YYLTYPE*);
#define dsym_node(node,location) dsym_node_gen(parser, (node), (location))

static NODE *gettable_gen(struct parser_params*,ID,const YYLTYPE*);
#define gettable(id,location) gettable_gen(parser,(id),(location))
static NODE *assignable_gen(struct parser_params*,ID,NODE*,const YYLTYPE*);
#define assignable(id,node,location) assignable_gen(parser, (id), (node), (location))

static NODE *aryset_gen(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
#define aryset(node1,node2,location) aryset_gen(parser, (node1), (node2), (location))
static NODE *attrset_gen(struct parser_params*,NODE*,ID,ID,const YYLTYPE*);
#define attrset(node,q,id,location) attrset_gen(parser, (node), (q), (id), (location))

static void rb_backref_error_gen(struct parser_params*,NODE*);
#define rb_backref_error(n) rb_backref_error_gen(parser,(n))
static NODE *node_assign_gen(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
#define node_assign(node1, node2, location) node_assign_gen(parser, (node1), (node2), (location))

static NODE *new_op_assign_gen(struct parser_params *parser, NODE *lhs, ID op, NODE *rhs, const YYLTYPE *location);
#define new_op_assign(lhs, op, rhs, location) new_op_assign_gen(parser, (lhs), (op), (rhs), (location))
static NODE *new_attr_op_assign_gen(struct parser_params *parser, NODE *lhs, ID atype, ID attr, ID op, NODE *rhs, const YYLTYPE *location);
#define new_attr_op_assign(lhs, type, attr, op, rhs, location) new_attr_op_assign_gen(parser, (lhs), (type), (attr), (op), (rhs), (location))
static NODE *new_const_op_assign_gen(struct parser_params *parser, NODE *lhs, ID op, NODE *rhs, const YYLTYPE *location);
#define new_const_op_assign(lhs, op, rhs, location) new_const_op_assign_gen(parser, (lhs), (op), (rhs), (location))

static NODE *const_path_field_gen(struct parser_params *parser, NODE *head, ID mid, const YYLTYPE *location);
#define const_path_field(w, n, location) const_path_field_gen(parser, w, n, location)
#define top_const_field(n) NEW_COLON3(n)
static NODE *const_decl_gen(struct parser_params *parser, NODE* path, const YYLTYPE *location);
#define const_decl(path, location) const_decl_gen(parser, path, location)

#define var_field(n) (n)
#define backref_assign_error(n, a, location) (rb_backref_error(n), new_begin(0, location))

static NODE *opt_arg_append(NODE*, NODE*);
static NODE *kwd_append(NODE*, NODE*);

static NODE *new_hash_gen(struct parser_params *parser, NODE *hash, const YYLTYPE *location);
#define new_hash(hash, location) new_hash_gen(parser, (hash), location)

static NODE *new_defined_gen(struct parser_params *parser, NODE *expr, const YYLTYPE *location);
#define new_defined(expr, location) new_defined_gen(parser, expr, location)

static NODE *new_regexp_gen(struct parser_params *, NODE *, int, const YYLTYPE *);
#define new_regexp(node, opt, location) new_regexp_gen(parser, node, opt, location)

static NODE *new_lit_gen(struct parser_params *parser, VALUE sym, const YYLTYPE *location);
#define new_lit(sym, location) new_lit_gen(parser, sym, location)

static NODE *new_list_gen(struct parser_params *parser, NODE *item, const YYLTYPE *location);
#define new_list(item, location) new_list_gen(parser, item, location)

static NODE *new_str_gen(struct parser_params *parser, VALUE str, const YYLTYPE *location);
#define new_str(s,location) new_str_gen(parser, s, location)

static NODE *new_dvar_gen(struct parser_params *parser, ID id, const YYLTYPE *location);
#define new_dvar(id, location) new_dvar_gen(parser, id, location)

static NODE *new_resbody_gen(struct parser_params *parser, NODE *exc_list, NODE *stmt, NODE *rescue, const YYLTYPE *location);
#define new_resbody(e,s,r,location) new_resbody_gen(parser, (e),(s),(r),(location))

static NODE *new_errinfo_gen(struct parser_params *parser, const YYLTYPE *location);
#define new_errinfo(location) new_errinfo_gen(parser, location)

static NODE *new_call_gen(struct parser_params *parser, NODE *recv, ID mid, NODE *args, const YYLTYPE *location);
#define new_call(recv,mid,args,location) new_call_gen(parser, recv,mid,args,location)

static NODE *new_fcall_gen(struct parser_params *parser, ID mid, NODE *args, const YYLTYPE *location);
#define new_fcall(mid,args,location) new_fcall_gen(parser, mid, args, location)

static NODE *new_for_gen(struct parser_params *parser, NODE *var, NODE *iter, NODE *body, const YYLTYPE *location);
#define new_for(var,iter,body,location) new_for_gen(parser, var, iter, body, location)

static NODE *new_gvar_gen(struct parser_params *parser, ID id, const YYLTYPE *location);
#define new_gvar(id, location) new_gvar_gen(parser, id, location)

static NODE *new_lvar_gen(struct parser_params *parser, ID id, const YYLTYPE *location);
#define new_lvar(id, location) new_lvar_gen(parser, id, location)

static NODE *new_dstr_gen(struct parser_params *parser, VALUE str, const YYLTYPE *location);
#define new_dstr(s, location) new_dstr_gen(parser, s, location)

static NODE *new_rescue_gen(struct parser_params *parser, NODE *b, NODE *res, NODE *e, const YYLTYPE *location);
#define new_rescue(b,res,e,location) new_rescue_gen(parser,b,res,e,location)

static NODE *new_undef_gen(struct parser_params *parser, NODE *i, const YYLTYPE *location);
#define new_undef(i, location) new_undef_gen(parser, i, location)

static NODE *nd_set_loc(NODE *nd, const YYLTYPE *location);
static NODE *new_zarray_gen(struct parser_params *parser, const YYLTYPE *location);
#define new_zarray(location) new_zarray_gen(parser, location)
#define make_array(ary, location) ((ary) ? (nd_set_loc(ary, location), ary) : new_zarray(location))

static NODE *new_ivar_gen(struct parser_params *parser, ID id, const YYLTYPE *location);
#define new_ivar(id, location) new_ivar_gen(parser,id,location)

static NODE *new_postarg_gen(struct parser_params *parser, NODE *i, NODE *v, const YYLTYPE *location);
#define new_postarg(i,v,location) new_postarg_gen(parser,i,v,location)

static NODE *new_cdecl_gen(struct parser_params *parser, ID v, NODE *val, NODE *path, const YYLTYPE *location);
#define new_cdecl(v,val,path,location) new_cdecl_gen(parser,v,val,path,location)

static NODE *new_scope_gen(struct parser_params *parser, NODE *a, NODE *b, const YYLTYPE *location);
#define new_scope(a,b,location) new_scope_gen(parser,a,b,location)

static NODE *new_begin_gen(struct parser_params *parser, NODE *b, const YYLTYPE *location);
#define new_begin(b,location) new_begin_gen(parser,b,location)

static NODE *new_masgn_gen(struct parser_params *parser, NODE *l, NODE *r, const YYLTYPE *location);
#define new_masgn(l,r,location) new_masgn_gen(parser,l,r,location)

static NODE *new_xstring_gen(struct parser_params *, NODE *, const YYLTYPE *location);
#define new_xstring(node, location) new_xstring_gen(parser, node, location)
#define new_string1(str) (str)

static NODE *new_body_gen(struct parser_params *parser, NODE *param, NODE *stmt, const YYLTYPE *location);
#define new_brace_body(param, stmt, location) new_body_gen(parser, param, stmt, location)
#define new_do_body(param, stmt, location) new_body_gen(parser, param, stmt, location)

static NODE *match_op_gen(struct parser_params*,NODE*,NODE*,const YYLTYPE*,const YYLTYPE*);
#define match_op(node1,node2,op_loc,location) match_op_gen(parser, (node1), (node2), (op_loc), (location))

static ID  *local_tbl_gen(struct parser_params*);
#define local_tbl() local_tbl_gen(parser)

static VALUE reg_compile_gen(struct parser_params*, VALUE, int);
#define reg_compile(str,options) reg_compile_gen(parser, (str), (options))
static void reg_fragment_setenc_gen(struct parser_params*, VALUE, int);
#define reg_fragment_setenc(str,options) reg_fragment_setenc_gen(parser, (str), (options))
static int reg_fragment_check_gen(struct parser_params*, VALUE, int);
#define reg_fragment_check(str,options) reg_fragment_check_gen(parser, (str), (options))
static NODE *reg_named_capture_assign_gen(struct parser_params* parser, VALUE regexp, const YYLTYPE *location);
#define reg_named_capture_assign(regexp,location) reg_named_capture_assign_gen(parser,(regexp),location)

static NODE *parser_heredoc_dedent(struct parser_params*,NODE*);
# define heredoc_dedent(str) parser_heredoc_dedent(parser, (str))

#define get_id(id) (id)
#define get_value(val) (val)
#else  /* RIPPER */
#define NODE_RIPPER NODE_CDECL

static inline VALUE
ripper_new_yylval_gen(struct parser_params *parser, ID a, VALUE b, VALUE c)
{
    add_mark_object(b);
    add_mark_object(c);
    return (VALUE)NEW_CDECL(a, b, c);
}
#define ripper_new_yylval(a, b, c) ripper_new_yylval_gen(parser, a, b, c)

static inline int
ripper_is_node_yylval(VALUE n)
{
    return RB_TYPE_P(n, T_NODE) && nd_type(RNODE(n)) == NODE_RIPPER;
}

#define value_expr(node) ((void)(node))
#define remove_begin(node) (node)
#define rb_dvar_defined(id, base) 0
#define rb_local_defined(id, base) 0
static ID ripper_get_id(VALUE);
#define get_id(id) ripper_get_id(id)
static VALUE ripper_get_value(VALUE);
#define get_value(val) ripper_get_value(val)
static VALUE assignable_gen(struct parser_params*,VALUE);
#define assignable(lhs,node,location) assignable_gen(parser, (lhs))
static int id_is_var_gen(struct parser_params *parser, ID id);
#define id_is_var(id) id_is_var_gen(parser, (id))

#define method_cond(node,location) (node)
#define call_bin_op(recv,id,arg1,op_loc,location) dispatch3(binary, (recv), STATIC_ID2SYM(id), (arg1))
#define match_op(node1,node2,op_loc,location) call_bin_op((node1), idEqTilde, (node2), op_loc, location)
#define call_uni_op(recv,id,op_loc,location) dispatch2(unary, STATIC_ID2SYM(id), (recv))
#define logop(id,node1,node2,op_loc,location) call_bin_op((node1), (id), (node2), op_loc, location)
#define node_assign(node1, node2, location) dispatch2(assign, (node1), (node2))
static VALUE new_qcall_gen(struct parser_params *parser, VALUE q, VALUE r, VALUE m, VALUE a);
#define new_qcall(q,r,m,a,location) new_qcall_gen(parser, (r), (q), (m), (a))
#define new_command_qcall(q,r,m,a,location) dispatch4(command_call, (r), (q), (m), (a))
#define new_command_call(q,r,m,a) dispatch4(command_call, (r), (q), (m), (a))
#define new_command(m,a) dispatch2(command, (m), (a));

#define new_nil(location) Qnil
static VALUE new_op_assign_gen(struct parser_params *parser, VALUE lhs, VALUE op, VALUE rhs);
#define new_op_assign(lhs, op, rhs, location) new_op_assign_gen(parser, (lhs), (op), (rhs))
static VALUE new_attr_op_assign_gen(struct parser_params *parser, VALUE lhs, VALUE type, VALUE attr, VALUE op, VALUE rhs);
#define new_attr_op_assign(lhs, type, attr, op, rhs, location) new_attr_op_assign_gen(parser, (lhs), (type), (attr), (op), (rhs))
#define new_const_op_assign(lhs, op, rhs, location) new_op_assign(lhs, op, rhs, location)

static VALUE new_regexp_gen(struct parser_params *, VALUE, VALUE);
#define new_regexp(node, opt, location) new_regexp_gen(parser, node, opt)

static VALUE new_xstring_gen(struct parser_params *, VALUE);
#define new_xstring(str, location) new_xstring_gen(parser, str)
#define new_string1(str) dispatch1(string_literal, str)

#define new_brace_body(param, stmt, location) dispatch2(brace_block, escape_Qundef(param), stmt)
#define new_do_body(param, stmt, location) dispatch2(do_block, escape_Qundef(param), stmt)

#define const_path_field(w, n, location) dispatch2(const_path_field, (w), (n))
#define top_const_field(n) dispatch1(top_const_field, (n))
static VALUE const_decl_gen(struct parser_params *parser, VALUE path);
#define const_decl(path, location) const_decl_gen(parser, path)

static VALUE var_field_gen(struct parser_params *parser, VALUE a);
#define var_field(a) var_field_gen(parser, (a))
static VALUE assign_error_gen(struct parser_params *parser, VALUE a);
#define assign_error(a) assign_error_gen(parser, (a))
#define backref_assign_error(n, a, location) assign_error(a)

#define block_dup_check(n1,n2) ((void)(n1), (void)(n2))
#define fixpos(n1,n2) ((void)(n1), (void)(n2))
#undef nd_set_line
#define nd_set_line(n,l) ((void)(n))

static VALUE parser_reg_compile(struct parser_params*, VALUE, int, VALUE *);

#endif /* !RIPPER */

/* forward declaration */
typedef struct rb_strterm_heredoc_struct rb_strterm_heredoc_t;

RUBY_SYMBOL_EXPORT_BEGIN
VALUE rb_parser_reg_compile(struct parser_params* parser, VALUE str, int options);
int rb_reg_fragment_setenc(struct parser_params*, VALUE, int);
enum lex_state_e rb_parser_trace_lex_state(struct parser_params *, enum lex_state_e, enum lex_state_e, int);
VALUE rb_parser_lex_state_name(enum lex_state_e state);
void rb_parser_show_bitstack(struct parser_params *, stack_type, const char *, int);
PRINTF_ARGS(void rb_parser_fatal(struct parser_params *parser, const char *fmt, ...), 2, 3);
void rb_parser_set_location_from_strterm_heredoc(struct parser_params *parser, rb_strterm_heredoc_t *here, YYLTYPE *yylloc);
void rb_parser_set_location_of_none(struct parser_params *parser, YYLTYPE *yylloc);
void rb_parser_set_location(struct parser_params *parser, YYLTYPE *yylloc);
RUBY_SYMBOL_EXPORT_END

static ID formal_argument_gen(struct parser_params*, ID);
#define formal_argument(id) formal_argument_gen(parser, (id))
static ID shadowing_lvar_gen(struct parser_params*,ID);
#define shadowing_lvar(name) shadowing_lvar_gen(parser, (name))
static void new_bv_gen(struct parser_params*,ID);
#define new_bv(id) new_bv_gen(parser, (id))

static void local_push_gen(struct parser_params*,int);
#define local_push(top) local_push_gen(parser,(top))
static void local_pop_gen(struct parser_params*);
#define local_pop() local_pop_gen(parser)
static void local_var_gen(struct parser_params*, ID);
#define local_var(id) local_var_gen(parser, (id))
static void arg_var_gen(struct parser_params*, ID);
#define arg_var(id) arg_var_gen(parser, (id))
static int  local_id_gen(struct parser_params*, ID, ID **);
#define local_id_ref(id, vidp) local_id_gen(parser, (id), &(vidp))
#define local_id(id) local_id_gen(parser, (id), NULL)
static ID   internal_id_gen(struct parser_params*);
#define internal_id() internal_id_gen(parser)

static const struct vtable *dyna_push_gen(struct parser_params *);
#define dyna_push() dyna_push_gen(parser)
static void dyna_pop_gen(struct parser_params*, const struct vtable *);
#define dyna_pop(node) dyna_pop_gen(parser, (node))
static int dyna_in_block_gen(struct parser_params*);
#define dyna_in_block() dyna_in_block_gen(parser)
#define dyna_var(id) local_var(id)
static int dvar_defined_gen(struct parser_params*, ID, ID**);
#define dvar_defined_ref(id, vidp) dvar_defined_gen(parser, (id), &(vidp))
#define dvar_defined(id) dvar_defined_gen(parser, (id), NULL)
static int dvar_curr_gen(struct parser_params*,ID);
#define dvar_curr(id) dvar_curr_gen(parser, (id))

static int lvar_defined_gen(struct parser_params*, ID);
#define lvar_defined(id) lvar_defined_gen(parser, (id))

#ifdef RIPPER
# define METHOD_NOT idNOT
#else
# define METHOD_NOT '!'
#endif

#define RE_OPTION_ONCE (1<<16)
#define RE_OPTION_ENCODING_SHIFT 8
#define RE_OPTION_ENCODING(e) (((e)&0xff)<<RE_OPTION_ENCODING_SHIFT)
#define RE_OPTION_ENCODING_IDX(o) (((o)>>RE_OPTION_ENCODING_SHIFT)&0xff)
#define RE_OPTION_ENCODING_NONE(o) ((o)&RE_OPTION_ARG_ENCODING_NONE)
#define RE_OPTION_MASK  0xff
#define RE_OPTION_ARG_ENCODING_NONE 32

/* structs for managing terminator of string literal and heredocment */
typedef struct rb_strterm_literal_struct {
    union {
	VALUE dummy;
	long nest;
    } u0;
    union {
	VALUE dummy;
	long func;	    /* STR_FUNC_* (e.g., STR_FUNC_ESCAPE and STR_FUNC_EXPAND) */
    } u1;
    union {
	VALUE dummy;
	long paren;	    /* '(' of `%q(...)` */
    } u2;
    union {
	VALUE dummy;
	long term;	    /* ')' of `%q(...)` */
    } u3;
} rb_strterm_literal_t;

struct rb_strterm_heredoc_struct {
    SIGNED_VALUE sourceline;
    VALUE term;		/* `"END"` of `<<"END"` */
    VALUE lastline;	/* the string of line that contains `<<"END"` */
    union {
	VALUE dummy;
	long lastidx;	/* the column of `<<"END"` */
    } u3;
};

#define STRTERM_HEREDOC IMEMO_FL_USER0

struct rb_strterm_struct {
    VALUE flags;
    union {
	rb_strterm_literal_t literal;
	rb_strterm_heredoc_t heredoc;
    } u;
};

#ifndef RIPPER
void
rb_strterm_mark(VALUE obj)
{
    rb_strterm_t *strterm = (rb_strterm_t*)obj;
    if (RBASIC(obj)->flags & STRTERM_HEREDOC) {
	rb_strterm_heredoc_t *heredoc = &strterm->u.heredoc;
	rb_gc_mark(heredoc->term);
	rb_gc_mark(heredoc->lastline);
    }
}
#endif

#define TOKEN2ID(tok) ( \
    tTOKEN_LOCAL_BEGIN<(tok)&&(tok)<tTOKEN_LOCAL_END ? TOKEN2LOCALID(tok) : \
    tTOKEN_INSTANCE_BEGIN<(tok)&&(tok)<tTOKEN_INSTANCE_END ? TOKEN2INSTANCEID(tok) : \
    tTOKEN_GLOBAL_BEGIN<(tok)&&(tok)<tTOKEN_GLOBAL_END ? TOKEN2GLOBALID(tok) : \
    tTOKEN_CONST_BEGIN<(tok)&&(tok)<tTOKEN_CONST_END ? TOKEN2CONSTID(tok) : \
    tTOKEN_CLASS_BEGIN<(tok)&&(tok)<tTOKEN_CLASS_END ? TOKEN2CLASSID(tok) : \
    tTOKEN_ATTRSET_BEGIN<(tok)&&(tok)<tTOKEN_ATTRSET_END ? TOKEN2ATTRSETID(tok) : \
    ((tok) / ((tok)<tPRESERVED_ID_END && ((tok)>=128 || rb_ispunct(tok)))))

/****** Ripper *******/

#ifdef RIPPER
#define RIPPER_VERSION "0.1.0"

static inline VALUE intern_sym(const char *name);

#include "eventids1.c"
#include "eventids2.c"

static VALUE ripper_dispatch0(struct parser_params*,ID);
static VALUE ripper_dispatch1(struct parser_params*,ID,VALUE);
static VALUE ripper_dispatch2(struct parser_params*,ID,VALUE,VALUE);
static VALUE ripper_dispatch3(struct parser_params*,ID,VALUE,VALUE,VALUE);
static VALUE ripper_dispatch4(struct parser_params*,ID,VALUE,VALUE,VALUE,VALUE);
static VALUE ripper_dispatch5(struct parser_params*,ID,VALUE,VALUE,VALUE,VALUE,VALUE);
static VALUE ripper_dispatch7(struct parser_params*,ID,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE);
static void ripper_error_gen(struct parser_params *parser);
#define ripper_error() ripper_error_gen(parser)

#define dispatch0(n)            ripper_dispatch0(parser, TOKEN_PASTE(ripper_id_, n))
#define dispatch1(n,a)          ripper_dispatch1(parser, TOKEN_PASTE(ripper_id_, n), (a))
#define dispatch2(n,a,b)        ripper_dispatch2(parser, TOKEN_PASTE(ripper_id_, n), (a), (b))
#define dispatch3(n,a,b,c)      ripper_dispatch3(parser, TOKEN_PASTE(ripper_id_, n), (a), (b), (c))
#define dispatch4(n,a,b,c,d)    ripper_dispatch4(parser, TOKEN_PASTE(ripper_id_, n), (a), (b), (c), (d))
#define dispatch5(n,a,b,c,d,e)  ripper_dispatch5(parser, TOKEN_PASTE(ripper_id_, n), (a), (b), (c), (d), (e))
#define dispatch7(n,a,b,c,d,e,f,g) ripper_dispatch7(parser, TOKEN_PASTE(ripper_id_, n), (a), (b), (c), (d), (e), (f), (g))

#define yyparse ripper_yyparse

#define ID2VAL(id) STATIC_ID2SYM(id)
#define TOKEN2VAL(t) ID2VAL(TOKEN2ID(t))
#define KWD2EID(t, v) ripper_new_yylval(keyword_##t, get_value(v), 0)

#define arg_new() dispatch0(args_new)
#define arg_add(l,a) dispatch2(args_add, (l), (a))
#define arg_add_star(l,a) dispatch2(args_add_star, (l), (a))
#define arg_add_block(l,b) dispatch2(args_add_block, (l), (b))
#define arg_add_optblock(l,b) ((b)==Qundef? (l) : dispatch2(args_add_block, (l), (b)))
#define bare_assoc(v) dispatch1(bare_assoc_hash, (v))
#define arg_add_assocs(l,b) arg_add((l), bare_assoc(b))

#define args2mrhs(a) dispatch1(mrhs_new_from_args, (a))
#define mrhs_new() dispatch0(mrhs_new)
#define mrhs_add(l,a) dispatch2(mrhs_add, (l), (a))
#define mrhs_add_star(l,a) dispatch2(mrhs_add_star, (l), (a))

#define mlhs_new() dispatch0(mlhs_new)
#define mlhs_add(l,a) dispatch2(mlhs_add, (l), (a))
#define mlhs_add_star(l,a) dispatch2(mlhs_add_star, (l), (a))
#define mlhs_add_post(l,a) dispatch2(mlhs_add_post, (l), (a))

#define params_new(pars, opts, rest, pars2, kws, kwrest, blk) \
        dispatch7(params, (pars), (opts), (rest), (pars2), (kws), (kwrest), (blk))

#define blockvar_new(p,v) dispatch2(block_var, (p), (v))

#define method_optarg(m,a) ((a)==Qundef ? (m) : dispatch2(method_add_arg,(m),(a)))
#define method_arg(m,a) dispatch2(method_add_arg,(m),(a))
#define method_add_block(m,b) dispatch2(method_add_block, (m), (b))

#define escape_Qundef(x) ((x)==Qundef ? Qnil : (x))

static inline VALUE
new_args_gen(struct parser_params *parser, VALUE f, VALUE o, VALUE r, VALUE p, VALUE tail)
{
    NODE *t = (NODE *)tail;
    VALUE k = t->u1.value, kr = t->u2.value, b = t->u3.value;
    return params_new(f, o, r, p, k, kr, escape_Qundef(b));
}
#define new_args(f,o,r,p,t,location) new_args_gen(parser, (f),(o),(r),(p),(t))

static inline VALUE
new_args_tail_gen(struct parser_params *parser, VALUE k, VALUE kr, VALUE b)
{
    NODE *t = rb_node_newnode(NODE_ARGS_AUX, k, kr, b);
    add_mark_object(k);
    add_mark_object(kr);
    add_mark_object(b);
    return (VALUE)t;
}
#define new_args_tail(k,kr,b,location) new_args_tail_gen(parser, (k),(kr),(b))

#define new_defined(expr,location) dispatch1(defined, (expr))

static VALUE parser_heredoc_dedent(struct parser_params*,VALUE);
# define heredoc_dedent(str) parser_heredoc_dedent(parser, (str))

#define FIXME 0

#else
#define ID2VAL(id) ((VALUE)(id))
#define TOKEN2VAL(t) ID2VAL(t)
#define KWD2EID(t, v) keyword_##t
#endif /* RIPPER */

#ifndef RIPPER
# define Qnone 0
# define Qnull 0
# define ifndef_ripper(x) (x)
#else
# define Qnone Qnil
# define Qnull Qundef
# define ifndef_ripper(x)
#endif

# define rb_warn0(fmt)         WARN_CALL(WARN_ARGS(fmt, 1))
# define rb_warn1(fmt,a)       WARN_CALL(WARN_ARGS(fmt, 2), (a))
# define rb_warn2(fmt,a,b)     WARN_CALL(WARN_ARGS(fmt, 3), (a), (b))
# define rb_warn3(fmt,a,b,c)   WARN_CALL(WARN_ARGS(fmt, 4), (a), (b), (c))
# define rb_warn4(fmt,a,b,c,d) WARN_CALL(WARN_ARGS(fmt, 5), (a), (b), (c), (d))
# define rb_warning0(fmt)         WARNING_CALL(WARNING_ARGS(fmt, 1))
# define rb_warning1(fmt,a)       WARNING_CALL(WARNING_ARGS(fmt, 2), (a))
# define rb_warning2(fmt,a,b)     WARNING_CALL(WARNING_ARGS(fmt, 3), (a), (b))
# define rb_warning3(fmt,a,b,c)   WARNING_CALL(WARNING_ARGS(fmt, 4), (a), (b), (c))
# define rb_warning4(fmt,a,b,c,d) WARNING_CALL(WARNING_ARGS(fmt, 5), (a), (b), (c), (d))
# define rb_warn0L(l,fmt)         WARN_CALL(WARN_ARGS_L(l, fmt, 1))
# define rb_warn1L(l,fmt,a)       WARN_CALL(WARN_ARGS_L(l, fmt, 2), (a))
# define rb_warn2L(l,fmt,a,b)     WARN_CALL(WARN_ARGS_L(l, fmt, 3), (a), (b))
# define rb_warn3L(l,fmt,a,b,c)   WARN_CALL(WARN_ARGS_L(l, fmt, 4), (a), (b), (c))
# define rb_warn4L(l,fmt,a,b,c,d) WARN_CALL(WARN_ARGS_L(l, fmt, 5), (a), (b), (c), (d))
# define rb_warning0L(l,fmt)         WARNING_CALL(WARNING_ARGS_L(l, fmt, 1))
# define rb_warning1L(l,fmt,a)       WARNING_CALL(WARNING_ARGS_L(l, fmt, 2), (a))
# define rb_warning2L(l,fmt,a,b)     WARNING_CALL(WARNING_ARGS_L(l, fmt, 3), (a), (b))
# define rb_warning3L(l,fmt,a,b,c)   WARNING_CALL(WARNING_ARGS_L(l, fmt, 4), (a), (b), (c))
# define rb_warning4L(l,fmt,a,b,c,d) WARNING_CALL(WARNING_ARGS_L(l, fmt, 5), (a), (b), (c), (d))
#ifdef RIPPER
static ID id_warn, id_warning, id_gets;
# define WARN_S_L(s,l) STR_NEW(s,l)
# define WARN_S(s) STR_NEW2(s)
# define WARN_I(i) INT2NUM(i)
# define WARN_ID(i) rb_id2str(i)
# define PRIsWARN "s"
# define WARN_ARGS(fmt,n) parser->value, id_warn, n, rb_usascii_str_new_lit(fmt)
# define WARN_ARGS_L(l,fmt,n) WARN_ARGS(fmt,n)
# ifdef HAVE_VA_ARGS_MACRO
# define WARN_CALL(...) rb_funcall(__VA_ARGS__)
# else
# define WARN_CALL rb_funcall
# endif
# define WARNING_ARGS(fmt,n) parser->value, id_warning, n, rb_usascii_str_new_lit(fmt)
# define WARNING_ARGS_L(l, fmt,n) WARNING_ARGS(fmt,n)
# ifdef HAVE_VA_ARGS_MACRO
# define WARNING_CALL(...) rb_funcall(__VA_ARGS__)
# else
# define WARNING_CALL rb_funcall
# endif
PRINTF_ARGS(static void ripper_compile_error(struct parser_params*, const char *fmt, ...), 2, 3);
# define compile_error ripper_compile_error
# define PARSER_ARG parser,
#else
# define WARN_S_L(s,l) s
# define WARN_S(s) s
# define WARN_I(i) i
# define WARN_ID(i) rb_id2name(i)
# define PRIsWARN PRIsVALUE
# define WARN_ARGS(fmt,n) WARN_ARGS_L(ruby_sourceline,fmt,n)
# define WARN_ARGS_L(l,fmt,n) ruby_sourcefile, (l), (fmt)
# define WARN_CALL rb_compile_warn
# define WARNING_ARGS(fmt,n) WARN_ARGS(fmt,n)
# define WARNING_ARGS_L(l,fmt,n) WARN_ARGS_L(l,fmt,n)
# define WARNING_CALL rb_compile_warning
PRINTF_ARGS(static void parser_compile_error(struct parser_params*, const char *fmt, ...), 2, 3);
# define compile_error parser_compile_error
# define PARSER_ARG parser,
#endif

/* Older versions of Yacc set YYMAXDEPTH to a very low value by default (150,
   for instance).  This is too low for Ruby to parse some files, such as
   date/format.rb, therefore bump the value up to at least Bison's default. */
#ifdef OLD_YACC
#ifndef YYMAXDEPTH
#define YYMAXDEPTH 10000
#endif
#endif

static void token_info_push_gen(struct parser_params*, const char *token, size_t len);
static void token_info_pop_gen(struct parser_params*, const char *token, size_t len);
#define token_info_push(token) token_info_push_gen(parser, (token), rb_strlen_lit(token))
#define token_info_pop(token) token_info_pop_gen(parser, (token), rb_strlen_lit(token))
%}

%pure-parser
%lex-param {struct parser_params *parser}
%parse-param {struct parser_params *parser}

%union {
    VALUE val;
    NODE *node;
    ID id;
    int num;
    const struct vtable *vars;
    struct rb_strterm_struct *strterm;
}

%token <id>
	keyword_class
	keyword_module
	keyword_def
	keyword_undef
	keyword_begin
	keyword_rescue
	keyword_ensure
	keyword_end
	keyword_if
	keyword_unless
	keyword_then
	keyword_elsif
	keyword_else
	keyword_case
	keyword_when
	keyword_while
	keyword_until
	keyword_for
	keyword_break
	keyword_next
	keyword_redo
	keyword_retry
	keyword_in
	keyword_do
	keyword_do_cond
	keyword_do_block
	keyword_do_LAMBDA
	keyword_return
	keyword_yield
	keyword_super
	keyword_self
	keyword_nil
	keyword_true
	keyword_false
	keyword_and
	keyword_or
	keyword_not
	modifier_if
	modifier_unless
	modifier_while
	modifier_until
	modifier_rescue
	keyword_alias
	keyword_defined
	keyword_BEGIN
	keyword_END
	keyword__LINE__
	keyword__FILE__
	keyword__ENCODING__

%token <id>   tIDENTIFIER tFID tGVAR tIVAR tCONSTANT tCVAR tLABEL
%token <node> tINTEGER tFLOAT tRATIONAL tIMAGINARY tSTRING_CONTENT tCHAR
%token <node> tNTH_REF tBACK_REF
%token <num>  tREGEXP_END

%type <node> singleton strings string string1 xstring regexp
%type <node> string_contents xstring_contents regexp_contents string_content
%type <node> words symbols symbol_list qwords qsymbols word_list qword_list qsym_list word
%type <node> literal numeric simple_numeric dsym cpath
%type <node> top_compstmt top_stmts top_stmt
%type <node> bodystmt compstmt stmts stmt_or_begin stmt expr arg primary command command_call method_call
%type <node> expr_value arg_value primary_value fcall rel_expr
%type <node> if_tail opt_else case_body cases opt_rescue exc_list exc_var opt_ensure
%type <node> args call_args opt_call_args
%type <node> paren_args opt_paren_args args_tail opt_args_tail block_args_tail opt_block_args_tail
%type <node> command_args aref_args opt_block_arg block_arg var_ref var_lhs
%type <node> command_rhs arg_rhs
%type <node> command_asgn mrhs mrhs_arg superclass block_call block_command
%type <node> f_block_optarg f_block_opt
%type <node> f_arglist f_args f_arg f_arg_item f_optarg f_marg f_marg_list f_margs
%type <node> assoc_list assocs assoc undef_list backref string_dvar for_var
%type <node> block_param opt_block_param block_param_def f_opt
%type <node> f_kwarg f_kw f_block_kwarg f_block_kw
%type <node> bv_decls opt_bv_decl bvar
%type <node> lambda f_larglist lambda_body brace_body do_body
%type <node> brace_block cmd_brace_block do_block lhs none fitem
%type <node> mlhs mlhs_head mlhs_basic mlhs_item mlhs_node mlhs_post mlhs_inner
%type <id>   fsym keyword_variable user_variable sym symbol operation operation2 operation3
%type <id>   cname fname op f_rest_arg f_block_arg opt_f_block_arg f_norm_arg f_bad_arg
%type <id>   f_kwrest f_label f_arg_asgn call_op call_op2 reswords relop
/*%%%*/
/*%
%type <val> program then do
%*/
%token END_OF_INPUT 0	"end-of-input"
%token tUPLUS		RUBY_TOKEN(UPLUS)  "unary+"
%token tUMINUS		RUBY_TOKEN(UMINUS) "unary-"
%token tPOW		RUBY_TOKEN(POW)    "**"
%token tCMP		RUBY_TOKEN(CMP)    "<=>"
%token tEQ		RUBY_TOKEN(EQ)     "=="
%token tEQQ		RUBY_TOKEN(EQQ)    "==="
%token tNEQ		RUBY_TOKEN(NEQ)    "!="
%token tGEQ		RUBY_TOKEN(GEQ)    ">="
%token tLEQ		RUBY_TOKEN(LEQ)    "<="
%token tANDOP		RUBY_TOKEN(ANDOP)  "&&"
%token tOROP		RUBY_TOKEN(OROP)   "||"
%token tMATCH		RUBY_TOKEN(MATCH)  "=~"
%token tNMATCH		RUBY_TOKEN(NMATCH) "!~"
%token tDOT2		RUBY_TOKEN(DOT2)   ".."
%token tDOT3		RUBY_TOKEN(DOT3)   "..."
%token tAREF		RUBY_TOKEN(AREF)   "[]"
%token tASET		RUBY_TOKEN(ASET)   "[]="
%token tLSHFT		RUBY_TOKEN(LSHFT)  "<<"
%token tRSHFT		RUBY_TOKEN(RSHFT)  ">>"
%token tANDDOT		RUBY_TOKEN(ANDDOT) "&."
%token tCOLON2		RUBY_TOKEN(COLON2) "::"
%token tCOLON3		":: at EXPR_BEG"
%token <id> tOP_ASGN	/* +=, -=  etc. */
%token tASSOC		"=>"
%token tLPAREN		"("
%token tLPAREN_ARG	"( arg"
%token tRPAREN		")"
%token tLBRACK		"["
%token tLBRACE		"{"
%token tLBRACE_ARG	"{ arg"
%token tSTAR		"*"
%token tDSTAR		"**arg"
%token tAMPER		"&"
%token tLAMBDA		"->"
%token tSYMBEG tSTRING_BEG tXSTRING_BEG tREGEXP_BEG tWORDS_BEG tQWORDS_BEG tSYMBOLS_BEG tQSYMBOLS_BEG
%token tSTRING_DBEG tSTRING_DEND tSTRING_DVAR tSTRING_END tLAMBEG tLABEL_END

/*
 *	precedence table
 */

%nonassoc tLOWEST
%nonassoc tLBRACE_ARG

%nonassoc  modifier_if modifier_unless modifier_while modifier_until
%left  keyword_or keyword_and
%right keyword_not
%nonassoc keyword_defined
%right '=' tOP_ASGN
%left modifier_rescue
%right '?' ':'
%nonassoc tDOT2 tDOT3
%left  tOROP
%left  tANDOP
%nonassoc  tCMP tEQ tEQQ tNEQ tMATCH tNMATCH
%left  '>' tGEQ '<' tLEQ
%left  '|' '^'
%left  '&'
%left  tLSHFT tRSHFT
%left  '+' '-'
%left  '*' '/' '%'
%right tUMINUS_NUM tUMINUS
%right tPOW
%right '!' '~' tUPLUS

%token tLAST_TOKEN

%%
program		:  {
			SET_LEX_STATE(EXPR_BEG);
		    /*%%%*/
			local_push(compile_for_eval || in_main);
		    /*%
			local_push(0);
		    %*/
		    }
		  top_compstmt
		    {
		    /*%%%*/
			if ($2 && !compile_for_eval) {
			    /* last expression should not be void */
			    if (nd_type($2) != NODE_BLOCK) void_expr($2);
			    else {
				NODE *node = $2;
				while (node->nd_next) {
				    node = node->nd_next;
				}
				void_expr(node->nd_head);
			    }
			}
			ruby_eval_tree = new_scope(0, block_append(ruby_eval_tree, $2, &@$), &@$);
		    /*%
			$$ = $2;
			parser->result = dispatch1(program, $$);
		    %*/
			local_pop();
		    }
		;

top_compstmt	: top_stmts opt_terms
		    {
		    /*%%%*/
			void_stmts($1);
		    /*%
		    %*/
			$$ = $1;
		    }
		;

top_stmts	: none
                    {
		    /*%%%*/
			$$ = new_begin(0, &@$);
		    /*%
			$$ = dispatch2(stmts_add, dispatch0(stmts_new),
						  dispatch0(void_stmt));
		    %*/
		    }
		| top_stmt
		    {
		    /*%%%*/
			$$ = newline_node($1);
		    /*%
			$$ = dispatch2(stmts_add, dispatch0(stmts_new), $1);
		    %*/
		    }
		| top_stmts terms top_stmt
		    {
		    /*%%%*/
			$$ = block_append($1, newline_node($3), &@$);
		    /*%
			$$ = dispatch2(stmts_add, $1, $3);
		    %*/
		    }
		| error top_stmt
		    {
			$$ = remove_begin($2);
		    }
		;

top_stmt	: stmt
		| keyword_BEGIN
		    {
		    /*%%%*/
			/* local_push(0); */
		    /*%
		    %*/
		    }
		  '{' top_compstmt '}'
		    {
		    /*%%%*/
			ruby_eval_tree_begin = block_append(ruby_eval_tree_begin,
							    new_begin($4, &@$), &@$);
			/* NEW_PREEXE($4)); */
			/* local_pop(); */
			$$ = new_begin(0, &@$);
		    /*%
			$$ = dispatch1(BEGIN, $4);
		    %*/
		    }
		;

bodystmt	: compstmt
		  opt_rescue
		  opt_else
		  opt_ensure
		    {
		    /*%%%*/
			$$ = $1;
			if ($2) {
			    $$ = new_rescue($1, $2, $3, &@$);
			}
			else if ($3) {
			    rb_warn0("else without rescue is useless");
			    $$ = block_append($$, $3, &@$);
			}
			if ($4) {
			    if ($$) {
				$$ = NEW_ENSURE($$, $4);
				$$->nd_loc = @$;
			    }
			    else {
				NODE *nil = NEW_NIL();
				nil->nd_loc = @$;
				$$ = block_append($4, nil, &@$);
			    }
			}
			fixpos($$, $1);
		    /*%
			$$ = dispatch4(bodystmt,
				       escape_Qundef($1),
				       escape_Qundef($2),
				       escape_Qundef($3),
				       escape_Qundef($4));
		    %*/
		    }
		;

compstmt	: stmts opt_terms
		    {
		    /*%%%*/
			void_stmts($1);
		    /*%
		    %*/
			$$ = $1;
		    }
		;

stmts		: none
                    {
		    /*%%%*/
			$$ = new_begin(0, &@$);
		    /*%
			$$ = dispatch2(stmts_add, dispatch0(stmts_new),
						  dispatch0(void_stmt));
		    %*/
		    }
		| stmt_or_begin
		    {
		    /*%%%*/
			$$ = newline_node($1);
		    /*%
			$$ = dispatch2(stmts_add, dispatch0(stmts_new), $1);
		    %*/
		    }
		| stmts terms stmt_or_begin
		    {
		    /*%%%*/
			$$ = block_append($1, newline_node($3), &@$);
		    /*%
			$$ = dispatch2(stmts_add, $1, $3);
		    %*/
		    }
		| error stmt
		    {
			$$ = remove_begin($2);
		    }
		;

stmt_or_begin	: stmt
                    {
			$$ = $1;
		    }
                | keyword_BEGIN
		    {
			yyerror0("BEGIN is permitted only at toplevel");
		    /*%%%*/
			/* local_push(0); */
		    /*%
		    %*/
		    }
		  '{' top_compstmt '}'
		    {
		    /*%%%*/
			ruby_eval_tree_begin = block_append(ruby_eval_tree_begin,
							    $4, &@$);
			/* NEW_PREEXE($4)); */
			/* local_pop(); */
			$$ = new_begin(0, &@$);
		    /*%
			$$ = dispatch1(BEGIN, $4);
		    %*/
		    }
		;

stmt		: keyword_alias fitem {SET_LEX_STATE(EXPR_FNAME|EXPR_FITEM);} fitem
		    {
		    /*%%%*/
			$$ = NEW_ALIAS($2, $4);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(alias, $2, $4);
		    %*/
		    }
		| keyword_alias tGVAR tGVAR
		    {
		    /*%%%*/
			$$ = NEW_VALIAS($2, $3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(var_alias, $2, $3);
		    %*/
		    }
		| keyword_alias tGVAR tBACK_REF
		    {
		    /*%%%*/
			char buf[2];
			buf[0] = '$';
			buf[1] = (char)$3->nd_nth;
			$$ = NEW_VALIAS($2, rb_intern2(buf, 2));
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(var_alias, $2, $3);
		    %*/
		    }
		| keyword_alias tGVAR tNTH_REF
		    {
		    /*%%%*/
			yyerror0("can't make alias for the number variables");
			$$ = new_begin(0, &@$);
		    /*%
			$$ = dispatch2(var_alias, $2, $3);
			$$ = dispatch1(alias_error, $$);
			ripper_error();
		    %*/
		    }
		| keyword_undef undef_list
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(undef, $2);
		    %*/
		    }
		| stmt modifier_if expr_value
		    {
		    /*%%%*/
			$$ = new_if($3, remove_begin($1), 0, &@$);
			fixpos($$, $3);
		    /*%
			$$ = dispatch2(if_mod, $3, $1);
		    %*/
		    }
		| stmt modifier_unless expr_value
		    {
		    /*%%%*/
			$$ = new_unless($3, remove_begin($1), 0, &@$);
			fixpos($$, $3);
		    /*%
			$$ = dispatch2(unless_mod, $3, $1);
		    %*/
		    }
		| stmt modifier_while expr_value
		    {
		    /*%%%*/
			if ($1 && nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_WHILE(cond($3, &@3), $1->nd_body, 0);
			}
			else {
			    $$ = NEW_WHILE(cond($3, &@3), $1, 1);
			}
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(while_mod, $3, $1);
		    %*/
		    }
		| stmt modifier_until expr_value
		    {
		    /*%%%*/
			if ($1 && nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_UNTIL(cond($3, &@3), $1->nd_body, 0);
			}
			else {
			    $$ = NEW_UNTIL(cond($3, &@3), $1, 1);
			}
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(until_mod, $3, $1);
		    %*/
		    }
		| stmt modifier_rescue stmt
		    {
		    /*%%%*/
			NODE *resq;
			YYLTYPE location;
			location.first_loc = @2.first_loc;
			location.last_loc = @3.last_loc;
			resq = new_resbody(0, remove_begin($3), 0, &location);
			$$ = new_rescue(remove_begin($1), resq, 0, &@$);
		    /*%
			$$ = dispatch2(rescue_mod, $1, $3);
		    %*/
		    }
		| keyword_END '{' compstmt '}'
		    {
			if (in_def) {
			    rb_warn0("END in method; use at_exit");
			}
		    /*%%%*/
			{
			    NODE *scope = NEW_NODE(
				NODE_SCOPE, 0 /* tbl */, $3 /* body */, 0 /* args */);
			    $$ = NEW_POSTEXE(scope);
			    scope->nd_loc = @$;
			    $$->nd_loc = @$;
			}
		    /*%
			$$ = dispatch1(END, $3);
		    %*/
		    }
		| command_asgn
		| mlhs '=' command_call
		    {
		    /*%%%*/
			value_expr($3);
			$$ = node_assign($1, $3, &@$);
		    /*%
			$$ = dispatch2(massign, $1, $3);
		    %*/
		    }
		| lhs '=' mrhs
		    {
			value_expr($3);
			$$ = node_assign($1, $3, &@$);
		    }
		| mlhs '=' mrhs_arg
		    {
		    /*%%%*/
			$$ = node_assign($1, $3, &@$);
		    /*%
			$$ = dispatch2(massign, $1, $3);
		    %*/
		    }
		| expr
		;

command_asgn	: lhs '=' command_rhs
		    {
			value_expr($3);
			$$ = node_assign($1, $3, &@$);
		    }
		| var_lhs tOP_ASGN command_rhs
		    {
			value_expr($3);
			$$ = new_op_assign($1, $2, $3, &@$);
		    }
		| primary_value '[' opt_call_args rbracket tOP_ASGN command_rhs
		    {
		    /*%%%*/
			NODE *args;

			value_expr($6);
			$3 = make_array($3, &@3);
			args = arg_concat($3, $6, &@$);
			if ($5 == tOROP) {
			    $5 = 0;
			}
			else if ($5 == tANDOP) {
			    $5 = 1;
			}
			$$ = NEW_OP_ASGN1($1, $5, args);
			fixpos($$, $1);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(aref_field, $1, escape_Qundef($3));
			$$ = dispatch3(opassign, $$, $5, $6);
		    %*/
		    }
		| primary_value call_op tIDENTIFIER tOP_ASGN command_rhs
		    {
			value_expr($5);
			$$ = new_attr_op_assign($1, $2, $3, $4, $5, &@$);
		    }
		| primary_value call_op tCONSTANT tOP_ASGN command_rhs
		    {
			value_expr($5);
			$$ = new_attr_op_assign($1, $2, $3, $4, $5, &@$);
		    }
		| primary_value tCOLON2 tCONSTANT tOP_ASGN command_rhs
		    {
		    /*%%%*/
			YYLTYPE location;
			location.first_loc = @1.first_loc;
			location.last_loc = @3.last_loc;
		    /*%
		    %*/
			$$ = const_path_field($1, $3, &location);
			$$ = new_const_op_assign($$, $4, $5, &@$);
		    }
		| primary_value tCOLON2 tIDENTIFIER tOP_ASGN command_rhs
		    {
			value_expr($5);
			$$ = new_attr_op_assign($1, ID2VAL(idCOLON2), $3, $4, $5, &@$);
		    }
		| backref tOP_ASGN command_rhs
		    {
			$1 = var_field($1);
			$$ = backref_assign_error($1, node_assign($1, $3, &@$), &@$);
		    }
		;

command_rhs	: command_call   %prec tOP_ASGN
		    {
		    /*%%%*/
			value_expr($1);
			$$ = $1;
		    /*%
		    %*/
		    }
		| command_call modifier_rescue stmt
		    {
		    /*%%%*/
			YYLTYPE location;
			location.first_loc = @2.first_loc;
			location.last_loc = @3.last_loc;
			value_expr($1);
			$$ = new_rescue($1, new_resbody(0, remove_begin($3), 0, &location), 0, &@$);
		    /*%
			$$ = dispatch2(rescue_mod, $1, $3);
		    %*/
		    }
		| command_asgn
		;

expr		: command_call
		| expr keyword_and expr
		    {
			$$ = logop(idAND, $1, $3, &@2, &@$);
		    }
		| expr keyword_or expr
		    {
			$$ = logop(idOR, $1, $3, &@2, &@$);
		    }
		| keyword_not opt_nl expr
		    {
			$$ = call_uni_op(method_cond($3, &@3), METHOD_NOT, &@1, &@$);
		    }
		| '!' command_call
		    {
			$$ = call_uni_op(method_cond($2, &@2), '!', &@1, &@$);
		    }
		| arg
		;

expr_value	: expr
		    {
		    /*%%%*/
			value_expr($1);
			$$ = $1;
			if (!$$) $$ = NEW_NIL();
		    /*%
			$$ = $1;
		    %*/
		    }
		;

command_call	: command
		| block_command
		;

block_command	: block_call
		| block_call call_op2 operation2 command_args
		    {
			$$ = new_qcall($2, $1, $3, $4, &@$);
		    }
		;

cmd_brace_block	: tLBRACE_ARG
		    {
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*%
		    %*/
		    }
		  brace_body '}'
		    {
			$$ = $3;
		    /*%%%*/
			$3->nd_body->nd_loc.first_loc = @1.first_loc;
			$3->nd_body->nd_loc.last_loc = @4.last_loc;
			nd_set_line($$, $<num>2);
		    /*% %*/
		    }
		;

fcall		: operation
		    {
		    /*%%%*/
			$$ = new_fcall($1, 0, &@$);
			nd_set_line($$, tokline);
		    /*%
		    %*/
		    }
		;

command		: fcall command_args       %prec tLOWEST
		    {
		    /*%%%*/
			$$ = $1;
			$$->nd_args = $2;
			nd_set_last_loc($1, nd_last_loc($2));
		    /*%
			$$ = dispatch2(command, $1, $2);
		    %*/
		    }
		| fcall command_args cmd_brace_block
		    {
			block_dup_check($2,$3);
			$$ = new_command($1, $2);
			$$ = method_add_block($$, $3);
			fixpos($$, $1);
		    /*%%%*/
			$$->nd_loc = @$;
			nd_set_last_loc($1, nd_last_loc($2));
		    /*%
		    %*/
		    }
		| primary_value call_op operation2 command_args	%prec tLOWEST
		    {
			$$ = new_command_qcall($2, $1, $3, $4, &@$);
			fixpos($$, $1);
		    }
		| primary_value call_op operation2 command_args cmd_brace_block
		    {
			block_dup_check($4,$5);
			$$ = new_command_qcall($2, $1, $3, $4, &@$);
			$$ = method_add_block($$, $5);
			fixpos($$, $1);
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		   }
		| primary_value tCOLON2 operation2 command_args	%prec tLOWEST
		    {
			$$ = new_command_qcall(ID2VAL(idCOLON2), $1, $3, $4, &@$);
			fixpos($$, $1);
		    }
		| primary_value tCOLON2 operation2 command_args cmd_brace_block
		    {
			block_dup_check($4,$5);
			$$ = new_command_qcall(ID2VAL(idCOLON2), $1, $3, $4, &@$);
			$$ = method_add_block($$, $5);
			fixpos($$, $1);
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		   }
		| keyword_super command_args
		    {
		    /*%%%*/
			$$ = NEW_SUPER($2);
			fixpos($$, $2);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(super, $2);
		    %*/
		    }
		| keyword_yield command_args
		    {
		    /*%%%*/
			$$ = new_yield($2, &@$);
			fixpos($$, $2);
		    /*%
			$$ = dispatch1(yield, $2);
		    %*/
		    }
		| k_return call_args
		    {
		    /*%%%*/
			$$ = NEW_RETURN(ret_args($2));
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(return, $2);
		    %*/
		    }
		| keyword_break call_args
		    {
		    /*%%%*/
			$$ = NEW_BREAK(ret_args($2));
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(break, $2);
		    %*/
		    }
		| keyword_next call_args
		    {
		    /*%%%*/
			$$ = NEW_NEXT(ret_args($2));
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(next, $2);
		    %*/
		    }
		;

mlhs		: mlhs_basic
		| tLPAREN mlhs_inner rparen
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(mlhs_paren, $2);
		    %*/
		    }
		;

mlhs_inner	: mlhs_basic
		| tLPAREN mlhs_inner rparen
		    {
		    /*%%%*/
			$$ = new_masgn(new_list($2, &@$), 0, &@$);
		    /*%
			$$ = dispatch1(mlhs_paren, $2);
		    %*/
		    }
		;

mlhs_basic	: mlhs_head
		    {
		    /*%%%*/
			$$ = new_masgn($1, 0, &@$);
		    /*%
			$$ = $1;
		    %*/
		    }
		| mlhs_head mlhs_item
		    {
		    /*%%%*/
			$$ = new_masgn(list_append($1,$2), 0, &@$);
		    /*%
			$$ = mlhs_add($1, $2);
		    %*/
		    }
		| mlhs_head tSTAR mlhs_node
		    {
		    /*%%%*/
			$$ = new_masgn($1, $3, &@$);
		    /*%
			$$ = mlhs_add_star($1, $3);
		    %*/
		    }
		| mlhs_head tSTAR mlhs_node ',' mlhs_post
		    {
		    /*%%%*/
			$$ = new_masgn($1, new_postarg($3,$5,&@$), &@$);
		    /*%
			$1 = mlhs_add_star($1, $3);
			$$ = mlhs_add_post($1, $5);
		    %*/
		    }
		| mlhs_head tSTAR
		    {
		    /*%%%*/
			$$ = new_masgn($1, NODE_SPECIAL_NO_NAME_REST, &@$);
		    /*%
			$$ = mlhs_add_star($1, Qnil);
		    %*/
		    }
		| mlhs_head tSTAR ',' mlhs_post
		    {
		    /*%%%*/
			$$ = new_masgn($1, new_postarg(NODE_SPECIAL_NO_NAME_REST, $4, &@$), &@$);
		    /*%
			$1 = mlhs_add_star($1, Qnil);
			$$ = mlhs_add_post($1, $4);
		    %*/
		    }
		| tSTAR mlhs_node
		    {
		    /*%%%*/
			$$ = new_masgn(0, $2, &@$);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), $2);
		    %*/
		    }
		| tSTAR mlhs_node ',' mlhs_post
		    {
		    /*%%%*/
			$$ = new_masgn(0, new_postarg($2,$4,&@$), &@$);
		    /*%
			$2 = mlhs_add_star(mlhs_new(), $2);
			$$ = mlhs_add_post($2, $4);
		    %*/
		    }
		| tSTAR
		    {
		    /*%%%*/
			$$ = new_masgn(0, NODE_SPECIAL_NO_NAME_REST, &@$);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), Qnil);
		    %*/
		    }
		| tSTAR ',' mlhs_post
		    {
		    /*%%%*/
			$$ = new_masgn(0, new_postarg(NODE_SPECIAL_NO_NAME_REST, $3, &@$), &@$);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), Qnil);
			$$ = mlhs_add_post($$, $3);
		    %*/
		    }
		;

mlhs_item	: mlhs_node
		| tLPAREN mlhs_inner rparen
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(mlhs_paren, $2);
		    %*/
		    }
		;

mlhs_head	: mlhs_item ','
		    {
		    /*%%%*/
			$$ = new_list($1, &@1);
		    /*%
			$$ = mlhs_add(mlhs_new(), $1);
		    %*/
		    }
		| mlhs_head mlhs_item ','
		    {
		    /*%%%*/
			$$ = list_append($1, $2);
		    /*%
			$$ = mlhs_add($1, $2);
		    %*/
		    }
		;

mlhs_post	: mlhs_item
		    {
		    /*%%%*/
			$$ = new_list($1, &@$);
		    /*%
			$$ = mlhs_add(mlhs_new(), $1);
		    %*/
		    }
		| mlhs_post ',' mlhs_item
		    {
		    /*%%%*/
			$$ = list_append($1, $3);
		    /*%
			$$ = mlhs_add($1, $3);
		    %*/
		    }
		;

mlhs_node	: user_variable
		    {
			$$ = assignable(var_field($1), 0, &@$);
		    }
		| keyword_variable
		    {
			$$ = assignable(var_field($1), 0, &@$);
		    }
		| primary_value '[' opt_call_args rbracket
		    {
		    /*%%%*/
			$$ = aryset($1, $3, &@$);
		    /*%
			$$ = dispatch2(aref_field, $1, escape_Qundef($3));
		    %*/
		    }
		| primary_value call_op tIDENTIFIER
		    {
		    /*%%%*/
			$$ = attrset($1, $2, $3, &@$);
		    /*%
			$$ = dispatch3(field, $1, $2, $3);
		    %*/
		    }
		| primary_value tCOLON2 tIDENTIFIER
		    {
		    /*%%%*/
			$$ = attrset($1, idCOLON2, $3, &@$);
		    /*%
			$$ = dispatch2(const_path_field, $1, $3);
		    %*/
		    }
		| primary_value call_op tCONSTANT
		    {
		    /*%%%*/
			$$ = attrset($1, $2, $3, &@$);
		    /*%
			$$ = dispatch3(field, $1, $2, $3);
		    %*/
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
			$$ = const_decl(const_path_field($1, $3, &@$), &@$);
		    }
		| tCOLON3 tCONSTANT
		    {
			$$ = const_decl(top_const_field($2), &@$);
		    }
		| backref
		    {
			$1 = var_field($1);
			$$ = backref_assign_error($1, $1, &@$);
		    }
		;

lhs		: user_variable
		    {
			$$ = assignable(var_field($1), 0, &@$);
		    /*%%%*/
			if (!$$) $$ = new_begin(0, &@$);
		    /*%
		    %*/
		    }
		| keyword_variable
		    {
			$$ = assignable(var_field($1), 0, &@$);
		    /*%%%*/
			if (!$$) $$ = new_begin(0, &@$);
		    /*%
		    %*/
		    }
		| primary_value '[' opt_call_args rbracket
		    {
		    /*%%%*/
			$$ = aryset($1, $3, &@$);
		    /*%
			$$ = dispatch2(aref_field, $1, escape_Qundef($3));
		    %*/
		    }
		| primary_value call_op tIDENTIFIER
		    {
		    /*%%%*/
			$$ = attrset($1, $2, $3, &@$);
		    /*%
			$$ = dispatch3(field, $1, $2, $3);
		    %*/
		    }
		| primary_value tCOLON2 tIDENTIFIER
		    {
		    /*%%%*/
			$$ = attrset($1, idCOLON2, $3, &@$);
		    /*%
			$$ = dispatch3(field, $1, ID2VAL(idCOLON2), $3);
		    %*/
		    }
		| primary_value call_op tCONSTANT
		    {
		    /*%%%*/
			$$ = attrset($1, $2, $3, &@$);
		    /*%
			$$ = dispatch3(field, $1, $2, $3);
		    %*/
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
			$$ = const_decl(const_path_field($1, $3, &@$), &@$);
		    }
		| tCOLON3 tCONSTANT
		    {
			$$ = const_decl(top_const_field($2), &@$);
		    }
		| backref
		    {
			$1 = var_field($1);
			$$ = backref_assign_error($1, $1, &@$);
		    }
		;

cname		: tIDENTIFIER
		    {
		    /*%%%*/
			yyerror0("class/module name must be CONSTANT");
		    /*%
			$$ = dispatch1(class_name_error, $1);
			ripper_error();
		    %*/
		    }
		| tCONSTANT
		;

cpath		: tCOLON3 cname
		    {
		    /*%%%*/
			$$ = NEW_COLON3($2);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(top_const_ref, $2);
		    %*/
		    }
		| cname
		    {
		    /*%%%*/
			$$ = NEW_COLON2(0, $$);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(const_ref, $1);
		    %*/
		    }
		| primary_value tCOLON2 cname
		    {
		    /*%%%*/
			$$ = NEW_COLON2($1, $3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(const_path_ref, $1, $3);
		    %*/
		    }
		;

fname		: tIDENTIFIER
		| tCONSTANT
		| tFID
		| op
		    {
			SET_LEX_STATE(EXPR_ENDFN);
			$$ = $1;
		    }
		| reswords
		    {
			SET_LEX_STATE(EXPR_ENDFN);
			$$ = $1;
		    }
		;

fsym		: fname
		| symbol
		;

fitem		: fsym
		    {
		    /*%%%*/
			$$ = new_lit(ID2SYM($1), &@$);
		    /*%
			$$ = dispatch1(symbol_literal, $1);
		    %*/
		    }
		| dsym
		;

undef_list	: fitem
		    {
		    /*%%%*/
			$$ = new_undef($1, &@$);
		    /*%
			$$ = rb_ary_new3(1, get_value($1));
		    %*/
		    }
		| undef_list ',' {SET_LEX_STATE(EXPR_FNAME|EXPR_FITEM);} fitem
		    {
		    /*%%%*/
			NODE *undef = new_undef($4, &@$);
			$$ = block_append($1, undef, &@$);
		    /*%
			rb_ary_push($1, get_value($4));
		    %*/
		    }
		;

op		: '|'		{ ifndef_ripper($$ = '|'); }
		| '^'		{ ifndef_ripper($$ = '^'); }
		| '&'		{ ifndef_ripper($$ = '&'); }
		| tCMP		{ ifndef_ripper($$ = tCMP); }
		| tEQ		{ ifndef_ripper($$ = tEQ); }
		| tEQQ		{ ifndef_ripper($$ = tEQQ); }
		| tMATCH	{ ifndef_ripper($$ = tMATCH); }
		| tNMATCH	{ ifndef_ripper($$ = tNMATCH); }
		| '>'		{ ifndef_ripper($$ = '>'); }
		| tGEQ		{ ifndef_ripper($$ = tGEQ); }
		| '<'		{ ifndef_ripper($$ = '<'); }
		| tLEQ		{ ifndef_ripper($$ = tLEQ); }
		| tNEQ		{ ifndef_ripper($$ = tNEQ); }
		| tLSHFT	{ ifndef_ripper($$ = tLSHFT); }
		| tRSHFT	{ ifndef_ripper($$ = tRSHFT); }
		| '+'		{ ifndef_ripper($$ = '+'); }
		| '-'		{ ifndef_ripper($$ = '-'); }
		| '*'		{ ifndef_ripper($$ = '*'); }
		| tSTAR		{ ifndef_ripper($$ = '*'); }
		| '/'		{ ifndef_ripper($$ = '/'); }
		| '%'		{ ifndef_ripper($$ = '%'); }
		| tPOW		{ ifndef_ripper($$ = tPOW); }
		| tDSTAR	{ ifndef_ripper($$ = tDSTAR); }
		| '!'		{ ifndef_ripper($$ = '!'); }
		| '~'		{ ifndef_ripper($$ = '~'); }
		| tUPLUS	{ ifndef_ripper($$ = tUPLUS); }
		| tUMINUS	{ ifndef_ripper($$ = tUMINUS); }
		| tAREF		{ ifndef_ripper($$ = tAREF); }
		| tASET		{ ifndef_ripper($$ = tASET); }
		| '`'		{ ifndef_ripper($$ = '`'); }
		;

reswords	: keyword__LINE__ | keyword__FILE__ | keyword__ENCODING__
		| keyword_BEGIN | keyword_END
		| keyword_alias | keyword_and | keyword_begin
		| keyword_break | keyword_case | keyword_class | keyword_def
		| keyword_defined | keyword_do | keyword_else | keyword_elsif
		| keyword_end | keyword_ensure | keyword_false
		| keyword_for | keyword_in | keyword_module | keyword_next
		| keyword_nil | keyword_not | keyword_or | keyword_redo
		| keyword_rescue | keyword_retry | keyword_return | keyword_self
		| keyword_super | keyword_then | keyword_true | keyword_undef
		| keyword_when | keyword_yield | keyword_if | keyword_unless
		| keyword_while | keyword_until
		;

arg		: lhs '=' arg_rhs
		    {
			$$ = node_assign($1, $3, &@$);
		    }
		| var_lhs tOP_ASGN arg_rhs
		    {
			$$ = new_op_assign($1, $2, $3, &@$);
		    }
		| primary_value '[' opt_call_args rbracket tOP_ASGN arg_rhs
		    {
		    /*%%%*/
			NODE *args;

			value_expr($6);
			$3 = make_array($3, &@3);
			if (nd_type($3) == NODE_BLOCK_PASS) {
			    args = NEW_ARGSCAT($3, $6);
			    args->nd_loc = @$;
			}
			else {
			    args = arg_concat($3, $6, &@$);
			}
			if ($5 == tOROP) {
			    $5 = 0;
			}
			else if ($5 == tANDOP) {
			    $5 = 1;
			}
			$$ = NEW_OP_ASGN1($1, $5, args);
			fixpos($$, $1);
			$$->nd_loc = @$;
		    /*%
			$1 = dispatch2(aref_field, $1, escape_Qundef($3));
			$$ = dispatch3(opassign, $1, $5, $6);
		    %*/
		    }
		| primary_value call_op tIDENTIFIER tOP_ASGN arg_rhs
		    {
			value_expr($5);
			$$ = new_attr_op_assign($1, $2, $3, $4, $5, &@$);
		    }
		| primary_value call_op tCONSTANT tOP_ASGN arg_rhs
		    {
			value_expr($5);
			$$ = new_attr_op_assign($1, $2, $3, $4, $5, &@$);
		    }
		| primary_value tCOLON2 tIDENTIFIER tOP_ASGN arg_rhs
		    {
			value_expr($5);
			$$ = new_attr_op_assign($1, ID2VAL(idCOLON2), $3, $4, $5, &@$);
		    }
		| primary_value tCOLON2 tCONSTANT tOP_ASGN arg_rhs
		    {
		    /*%%%*/
			YYLTYPE location;
			location.first_loc = @1.first_loc;
			location.last_loc = @3.last_loc;
		    /*%
		    %*/
			$$ = const_path_field($1, $3, &location);
			$$ = new_const_op_assign($$, $4, $5, &@$);
		    }
		| tCOLON3 tCONSTANT tOP_ASGN arg_rhs
		    {
			$$ = top_const_field($2);
			$$ = new_const_op_assign($$, $3, $4, &@$);
		    }
		| backref tOP_ASGN arg_rhs
		    {
			$1 = var_field($1);
			$$ = backref_assign_error($1, new_op_assign($1, $2, $3, &@$), &@$);
		    }
		| arg tDOT2 arg
		    {
		    /*%%%*/
			value_expr($1);
			value_expr($3);
			$$ = NEW_DOT2($1, $3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(dot2, $1, $3);
		    %*/
		    }
		| arg tDOT3 arg
		    {
		    /*%%%*/
			value_expr($1);
			value_expr($3);
			$$ = NEW_DOT3($1, $3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(dot3, $1, $3);
		    %*/
		    }
		| arg '+' arg
		    {
			$$ = call_bin_op($1, '+', $3, &@2, &@$);
		    }
		| arg '-' arg
		    {
			$$ = call_bin_op($1, '-', $3, &@2, &@$);
		    }
		| arg '*' arg
		    {
			$$ = call_bin_op($1, '*', $3, &@2, &@$);
		    }
		| arg '/' arg
		    {
			$$ = call_bin_op($1, '/', $3, &@2, &@$);
		    }
		| arg '%' arg
		    {
			$$ = call_bin_op($1, '%', $3, &@2, &@$);
		    }
		| arg tPOW arg
		    {
			$$ = call_bin_op($1, idPow, $3, &@2, &@$);
		    }
		| tUMINUS_NUM simple_numeric tPOW arg
		    {
			$$ = call_uni_op(call_bin_op($2, idPow, $4, &@2, &@$), idUMinus, &@1, &@$);
		    }
		| tUPLUS arg
		    {
			$$ = call_uni_op($2, idUPlus, &@1, &@$);
		    }
		| tUMINUS arg
		    {
			$$ = call_uni_op($2, idUMinus, &@1, &@$);
		    }
		| arg '|' arg
		    {
			$$ = call_bin_op($1, '|', $3, &@2, &@$);
		    }
		| arg '^' arg
		    {
			$$ = call_bin_op($1, '^', $3, &@2, &@$);
		    }
		| arg '&' arg
		    {
			$$ = call_bin_op($1, '&', $3, &@2, &@$);
		    }
		| arg tCMP arg
		    {
			$$ = call_bin_op($1, idCmp, $3, &@2, &@$);
		    }
		| rel_expr   %prec tCMP
		| arg tEQ arg
		    {
			$$ = call_bin_op($1, idEq, $3, &@2, &@$);
		    }
		| arg tEQQ arg
		    {
			$$ = call_bin_op($1, idEqq, $3, &@2, &@$);
		    }
		| arg tNEQ arg
		    {
			$$ = call_bin_op($1, idNeq, $3, &@2, &@$);
		    }
		| arg tMATCH arg
		    {
			$$ = match_op($1, $3, &@2, &@$);
		    }
		| arg tNMATCH arg
		    {
			$$ = call_bin_op($1, idNeqTilde, $3, &@2, &@$);
		    }
		| '!' arg
		    {
			$$ = call_uni_op(method_cond($2, &@2), '!', &@1, &@$);
		    }
		| '~' arg
		    {
			$$ = call_uni_op($2, '~', &@1, &@$);
		    }
		| arg tLSHFT arg
		    {
			$$ = call_bin_op($1, idLTLT, $3, &@2, &@$);
		    }
		| arg tRSHFT arg
		    {
			$$ = call_bin_op($1, idGTGT, $3, &@2, &@$);
		    }
		| arg tANDOP arg
		    {
			$$ = logop(idANDOP, $1, $3, &@2, &@$);
		    }
		| arg tOROP arg
		    {
			$$ = logop(idOROP, $1, $3, &@2, &@$);
		    }
		| keyword_defined opt_nl {in_defined = 1;} arg
		    {
			in_defined = 0;
			$$ = new_defined($4, &@$);
		    }
		| arg '?' arg opt_nl ':' arg
		    {
		    /*%%%*/
			value_expr($1);
			$$ = new_if($1, $3, $6, &@$);
			fixpos($$, $1);
		    /*%
			$$ = dispatch3(ifop, $1, $3, $6);
		    %*/
		    }
		| primary
		    {
			$$ = $1;
		    }
		;

relop		: '>'  {$$ = '>';}
		| '<'  {$$ = '<';}
		| tGEQ {$$ = idGE;}
		| tLEQ {$$ = idLE;}
		;

rel_expr	: arg relop arg   %prec '>'
		    {
			$$ = call_bin_op($1, $2, $3, &@2, &@$);
		    }
		| rel_expr relop arg   %prec '>'
		    {
			rb_warning1("comparison '%s' after comparison", WARN_ID($2));
			$$ = call_bin_op($1, $2, $3, &@2, &@$);
		    }
		;

arg_value	: arg
		    {
		    /*%%%*/
			value_expr($1);
			$$ = $1;
			if (!$$) $$ = NEW_NIL();
		    /*%
			$$ = $1;
		    %*/
		    }
		;

aref_args	: none
		| args trailer
		    {
			$$ = $1;
		    }
		| args ',' assocs trailer
		    {
		    /*%%%*/
			$$ = $3 ? arg_append($1, new_hash($3, &@3), &@$) : $1;
		    /*%
			$$ = arg_add_assocs($1, $3);
		    %*/
		    }
		| assocs trailer
		    {
		    /*%%%*/
			$$ = $1 ? new_list(new_hash($1, &@1), &@$) : 0;
		    /*%
			$$ = arg_add_assocs(arg_new(), $1);
		    %*/
		    }
		;

arg_rhs 	: arg   %prec tOP_ASGN
		    {
		    /*%%%*/
			value_expr($1);
			$$ = $1;
		    /*%
		    %*/
		    }
		| arg modifier_rescue arg
		    {
		    /*%%%*/
			YYLTYPE location;
			location.first_loc = @2.first_loc;
			location.last_loc = @3.last_loc;
			value_expr($1);
			$$ = new_rescue($1, new_resbody(0, remove_begin($3), 0, &location), 0, &@$);
		    /*%
			$$ = dispatch2(rescue_mod, $1, $3);
		    %*/
		    }
		;

paren_args	: '(' opt_call_args rparen
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(arg_paren, escape_Qundef($2));
		    %*/
		    }
		;

opt_paren_args	: none
		| paren_args
		;

opt_call_args	: none
		| call_args
		| args ','
		    {
		      $$ = $1;
		    }
		| args ',' assocs ','
		    {
		    /*%%%*/
			$$ = $3 ? arg_append($1, new_hash($3, &@3), &@$) : $1;
		    /*%
			$$ = arg_add_assocs($1, $3);
		    %*/
		    }
		| assocs ','
		    {
		    /*%%%*/
			$$ = $1 ? new_list(new_hash($1, &@1), &@1) : 0;
		    /*%
			$$ = arg_add_assocs(arg_new(), $1);
		    %*/
		    }
		;

call_args	: command
		    {
		    /*%%%*/
			value_expr($1);
			$$ = new_list($1, &@$);
		    /*%
			$$ = arg_add(arg_new(), $1);
		    %*/
		    }
		| args opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_blk_pass($1, $2);
		    /*%
			$$ = arg_add_optblock($1, $2);
		    %*/
		    }
		| assocs opt_block_arg
		    {
		    /*%%%*/
			$$ = $1 ? new_list(new_hash($1, &@1), &@1) : 0;
			$$ = arg_blk_pass($$, $2);
		    /*%
			$$ = arg_add_assocs(arg_new(), $1);
			$$ = arg_add_optblock($$, $2);
		    %*/
		    }
		| args ',' assocs opt_block_arg
		    {
		    /*%%%*/
			$$ = $3 ? arg_append($1, new_hash($3, &@3), &@$) : $1;
			$$ = arg_blk_pass($$, $4);
		    /*%
			$$ = arg_add_optblock(arg_add_assocs($1, $3), $4);
		    %*/
		    }
		| block_arg
		    /*%c%*/
		    /*%c
		    {
			$$ = arg_add_block(arg_new(), $1);
		    }
		    %*/
		;

command_args	:   {
			$<val>$ = cmdarg_stack;
			CMDARG_PUSH(1);
		    }
		  call_args
		    {
			/* CMDARG_POP() */
			CMDARG_SET($<val>1);
			$$ = $2;
		    }
		;

block_arg	: tAMPER arg_value
		    {
		    /*%%%*/
			$$ = NEW_BLOCK_PASS($2);
			$$->nd_loc = @$;
		    /*%
			$$ = $2;
		    %*/
		    }
		;

opt_block_arg	: ',' block_arg
		    {
			$$ = $2;
		    }
		| none
		    {
			$$ = 0;
		    }
		;

args		: arg_value
		    {
		    /*%%%*/
			$$ = new_list($1, &@$);
		    /*%
			$$ = arg_add(arg_new(), $1);
		    %*/
		    }
		| tSTAR arg_value
		    {
		    /*%%%*/
			$$ = NEW_SPLAT($2);
			$$->nd_loc = @$;
		    /*%
			$$ = arg_add_star(arg_new(), $2);
		    %*/
		    }
		| args ',' arg_value
		    {
		    /*%%%*/
			NODE *n1;
			if ((n1 = splat_array($1)) != 0) {
			    $$ = list_append(n1, $3);
			}
			else {
			    $$ = arg_append($1, $3, &@$);
			}
		    /*%
			$$ = arg_add($1, $3);
		    %*/
		    }
		| args ',' tSTAR arg_value
		    {
		    /*%%%*/
			NODE *n1;
			if ((nd_type($4) == NODE_ARRAY) && (n1 = splat_array($1)) != 0) {
			    $$ = list_concat(n1, $4);
			}
			else {
			    $$ = arg_concat($1, $4, &@$);
			}
		    /*%
			$$ = arg_add_star($1, $4);
		    %*/
		    }
		;

mrhs_arg	: mrhs
		| arg_value
		;

mrhs		: args ',' arg_value
		    {
		    /*%%%*/
			NODE *n1;
			if ((n1 = splat_array($1)) != 0) {
			    $$ = list_append(n1, $3);
			}
			else {
			    $$ = arg_append($1, $3, &@$);
			}
		    /*%
			$$ = mrhs_add(args2mrhs($1), $3);
		    %*/
		    }
		| args ',' tSTAR arg_value
		    {
		    /*%%%*/
			NODE *n1;
			if (nd_type($4) == NODE_ARRAY &&
			    (n1 = splat_array($1)) != 0) {
			    $$ = list_concat(n1, $4);
			}
			else {
			    $$ = arg_concat($1, $4, &@$);
			}
		    /*%
			$$ = mrhs_add_star(args2mrhs($1), $4);
		    %*/
		    }
		| tSTAR arg_value
		    {
		    /*%%%*/
			$$ = NEW_SPLAT($2);
			$$->nd_loc = @$;
		    /*%
			$$ = mrhs_add_star(mrhs_new(), $2);
		    %*/
		    }
		;

primary		: literal
		| strings
		| xstring
		| regexp
		| words
		| qwords
		| symbols
		| qsymbols
		| var_ref
		| backref
		| tFID
		    {
		    /*%%%*/
			$$ = new_fcall($1, 0, &@$);
		    /*%
			$$ = method_arg(dispatch1(fcall, $1), arg_new());
		    %*/
		    }
		| k_begin
		    {
			$<val>1 = cmdarg_stack;
			CMDARG_SET(0);
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*%
		    %*/
		    }
		  bodystmt
		  k_end
		    {
			CMDARG_SET($<val>1);
		    /*%%%*/
			if ($3 == NULL) {
			    $$ = NEW_NIL();
			    $$->nd_loc = @$;
			}
			else {
			    set_line_body($3, $<num>2);
			    $$ = new_begin($3, &@$);
			}
			nd_set_line($$, $<num>2);
		    /*%
			$$ = dispatch1(begin, $3);
		    %*/
		    }
		| tLPAREN_ARG {SET_LEX_STATE(EXPR_ENDARG);} rparen
		    {
		    /*%%%*/
			$$ = new_begin(0, &@$);
		    /*%
			$$ = dispatch1(paren, 0);
		    %*/
		    }
		| tLPAREN_ARG
		    {
			$<val>1 = cmdarg_stack;
			CMDARG_SET(0);
		    }
		  stmt {SET_LEX_STATE(EXPR_ENDARG);} rparen
		    {
			CMDARG_SET($<val>1);
		    /*%%%*/
			$$ = $3;
		    /*%
			$$ = dispatch1(paren, $3);
		    %*/
		    }
		| tLPAREN compstmt ')'
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(paren, $2);
		    %*/
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
		    /*%%%*/
			$$ = NEW_COLON2($1, $3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(const_path_ref, $1, $3);
		    %*/
		    }
		| tCOLON3 tCONSTANT
		    {
		    /*%%%*/
			$$ = NEW_COLON3($2);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(top_const_ref, $2);
		    %*/
		    }
		| tLBRACK aref_args ']'
		    {
		    /*%%%*/
			$$ = make_array($2, &@$);
		    /*%
			$$ = dispatch1(array, escape_Qundef($2));
		    %*/
		    }
		| tLBRACE assoc_list '}'
		    {
		    /*%%%*/
			$$ = new_hash($2, &@$);
			$$->nd_alen = TRUE;
		    /*%
			$$ = dispatch1(hash, escape_Qundef($2));
		    %*/
		    }
		| k_return
		    {
		    /*%%%*/
			$$ = NEW_RETURN(0);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch0(return0);
		    %*/
		    }
		| keyword_yield '(' call_args rparen
		    {
		    /*%%%*/
			$$ = new_yield($3, &@$);
		    /*%
			$$ = dispatch1(yield, dispatch1(paren, $3));
		    %*/
		    }
		| keyword_yield '(' rparen
		    {
		    /*%%%*/
			$$ = NEW_YIELD(0);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(yield, dispatch1(paren, arg_new()));
		    %*/
		    }
		| keyword_yield
		    {
		    /*%%%*/
			$$ = NEW_YIELD(0);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch0(yield0);
		    %*/
		    }
		| keyword_defined opt_nl '(' {in_defined = 1;} expr rparen
		    {
			in_defined = 0;
			$$ = new_defined($5, &@$);
		    }
		| keyword_not '(' expr rparen
		    {
			$$ = call_uni_op(method_cond($3, &@3), METHOD_NOT, &@1, &@$);
		    }
		| keyword_not '(' rparen
		    {
			$$ = call_uni_op(method_cond(new_nil(&@2), &@2), METHOD_NOT, &@1, &@$);
		    }
		| fcall brace_block
		    {
		    /*%%%*/
			$2->nd_iter = $1;
			$2->nd_loc = @$;
			$$ = $2;
		    /*%
			$$ = method_arg(dispatch1(fcall, $1), arg_new());
			$$ = method_add_block($$, $2);
		    %*/
		    }
		| method_call
		| method_call brace_block
		    {
		    /*%%%*/
			block_dup_check($1->nd_args, $2);
			$2->nd_iter = $1;
			$2->nd_loc = @$;
			$$ = $2;
		    /*%
			$$ = method_add_block($1, $2);
		    %*/
		    }
		| tLAMBDA lambda
		    {
			$$ = $2;
		    }
		| k_if expr_value then
		  compstmt
		  if_tail
		  k_end
		    {
		    /*%%%*/
			$$ = new_if($2, $4, $5, &@$);
			fixpos($$, $2);
		    /*%
			$$ = dispatch3(if, $2, $4, escape_Qundef($5));
		    %*/
		    }
		| k_unless expr_value then
		  compstmt
		  opt_else
		  k_end
		    {
		    /*%%%*/
			$$ = new_unless($2, $4, $5, &@$);
			fixpos($$, $2);
		    /*%
			$$ = dispatch3(unless, $2, $4, escape_Qundef($5));
		    %*/
		    }
		| k_while {COND_PUSH(1);} expr_value do {COND_POP();}
		  compstmt
		  k_end
		    {
		    /*%%%*/
			$$ = NEW_WHILE(cond($3, &@3), $6, 1);
			fixpos($$, $3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(while, $3, $6);
		    %*/
		    }
		| k_until {COND_PUSH(1);} expr_value do {COND_POP();}
		  compstmt
		  k_end
		    {
		    /*%%%*/
			$$ = NEW_UNTIL(cond($3, &@3), $6, 1);
			fixpos($$, $3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(until, $3, $6);
		    %*/
		    }
		| k_case expr_value opt_terms
		  case_body
		  k_end
		    {
		    /*%%%*/
			$$ = NEW_CASE($2, $4);
			fixpos($$, $2);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(case, $2, $4);
		    %*/
		    }
		| k_case opt_terms case_body k_end
		    {
		    /*%%%*/
			$$ = NEW_CASE2($3);
			nd_set_line($3, $<num>1);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(case, Qnil, $3);
		    %*/
		    }
		| k_for for_var keyword_in
		  {COND_PUSH(1);}
		  expr_value do
		  {COND_POP();}
		  compstmt
		  k_end
		    {
		    /*%%%*/
			/*
			 *  for a, b, c in e
			 *  #=>
			 *  e.each{|*x| a, b, c = x}
			 *
			 *  for a in e
			 *  #=>
			 *  e.each{|x| a, = x}
			 */
			ID id = internal_id();
			ID *tbl = ALLOC_N(ID, 2);
			NODE *m = NEW_ARGS_AUX(0, 0);
			NODE *args, *scope;

			switch (nd_type($2)) {
			  case NODE_MASGN:
			    m->nd_next = node_assign($2, new_for(new_dvar(id, &@2), 0, 0, &@2), &@2);
			    args = new_args(m, 0, id, 0, new_args_tail(0, 0, 0, &@2), &@2);
			    break;
			  case NODE_LASGN:
			  case NODE_DASGN:
			  case NODE_DASGN_CURR:
			    $2->nd_value = new_dvar(id, &@2);
			    m->nd_plen = 1;
			    m->nd_next = $2;
			    args = new_args(m, 0, 0, 0, new_args_tail(0, 0, 0, &@2), &@2);
			    break;
			  default:
			    {
				NODE *masgn = new_masgn(new_list($2, &@2), 0, &@2);
				m->nd_next = node_assign(masgn, new_dvar(id, &@2), &@2);
				args = new_args(m, 0, id, 0, new_args_tail(0, 0, 0, &@2), &@2);
				break;
			    }
			}
			add_mark_object((VALUE)rb_imemo_alloc_new((VALUE)tbl, 0, 0, 0));
			scope = NEW_NODE(NODE_SCOPE, tbl, $8, args);
			scope->nd_loc = @$;
			tbl[0] = 1; tbl[1] = id;
			$$ = new_for(0, $5, scope, &@$);
			fixpos($$, $2);
		    /*%
			$$ = dispatch3(for, $2, $5, $8);
		    %*/
		    }
		| k_class cpath superclass
		    {
			if (in_def)
			    yyerror0("class definition in method body");
			$<num>1 = in_class;
			in_class = 1;
			local_push(0);
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*%
		    %*/
		    }
		  bodystmt
		  k_end
		    {
		    /*%%%*/
			$$ = NEW_CLASS($2, $5, $3);
			$$->nd_body->nd_loc = @5;
			set_line_body($5, $<num>4);
			nd_set_line($$, $<num>4);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch3(class, $2, $3, $5);
		    %*/
			local_pop();
			in_class = $<num>1 & 1;
		    }
		| k_class tLSHFT expr
		    {
			$<num>$ = (in_class << 1) | in_def;
			in_def = 0;
			in_class = 0;
			local_push(0);
		    }
		  term
		  bodystmt
		  k_end
		    {
		    /*%%%*/
			$$ = NEW_SCLASS($3, $6);
			$$->nd_body->nd_loc = @6;
			set_line_body($6, nd_line($3));
			fixpos($$, $3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(sclass, $3, $6);
		    %*/
			local_pop();
			in_def = $<num>4 & 1;
			in_class = ($<num>4 >> 1) & 1;
		    }
		| k_module cpath
		    {
			if (in_def)
			    yyerror0("module definition in method body");
			$<num>1 = in_class;
			in_class = 1;
			local_push(0);
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*%
		    %*/
		    }
		  bodystmt
		  k_end
		    {
		    /*%%%*/
			$$ = NEW_MODULE($2, $4);
			$$->nd_body->nd_loc = @4;
			set_line_body($4, $<num>3);
			nd_set_line($$, $<num>3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch2(module, $2, $4);
		    %*/
			local_pop();
			in_class = $<num>1 & 1;
		    }
		| k_def fname
		    {
			local_push(0);
			$<id>$ = current_arg;
			current_arg = 0;
		    }
		    {
			$<num>$ = in_def;
			in_def = 1;
		    }
		  f_arglist
		  bodystmt
		  k_end
		    {
		    /*%%%*/
			NODE *body = remove_begin($6);
			reduce_nodes(&body);
			$$ = NEW_DEFN($2, $5, body, METHOD_VISI_PRIVATE);
			$$->nd_defn->nd_loc = @$;
			set_line_body(body, $<num>1);
			nd_set_line($$, $<num>1);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch3(def, $2, $5, $6);
		    %*/
			local_pop();
			in_def = $<num>4 & 1;
			current_arg = $<id>3;
		    }
		| k_def singleton dot_or_colon {SET_LEX_STATE(EXPR_FNAME);} fname
		    {
			$<num>4 = in_def;
			in_def = 1;
			SET_LEX_STATE(EXPR_ENDFN|EXPR_LABEL); /* force for args */
			local_push(0);
			$<id>$ = current_arg;
			current_arg = 0;
		    }
		  f_arglist
		  bodystmt
		  k_end
		    {
		    /*%%%*/
			NODE *body = remove_begin($8);
			reduce_nodes(&body);
			$$ = NEW_DEFS($2, $5, $7, body);
			$$->nd_defn->nd_loc = @$;
			set_line_body(body, $<num>1);
			nd_set_line($$, $<num>1);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch5(defs, $2, $<val>3, $5, $7, $8);
		    %*/
			local_pop();
			in_def = $<num>4 & 1;
			current_arg = $<id>6;
		    }
		| keyword_break
		    {
		    /*%%%*/
			$$ = NEW_BREAK(0);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(break, arg_new());
		    %*/
		    }
		| keyword_next
		    {
		    /*%%%*/
			$$ = NEW_NEXT(0);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(next, arg_new());
		    %*/
		    }
		| keyword_redo
		    {
		    /*%%%*/
			$$ = NEW_REDO();
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch0(redo);
		    %*/
		    }
		| keyword_retry
		    {
		    /*%%%*/
			$$ = NEW_RETRY();
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch0(retry);
		    %*/
		    }
		;

primary_value	: primary
		    {
		    /*%%%*/
			value_expr($1);
			$$ = $1;
			if (!$$) $$ = NEW_NIL();
		    /*%
			$$ = $1;
		    %*/
		    }
		;

k_begin		: keyword_begin
		    {
			token_info_push("begin");
		    }
		;

k_if		: keyword_if
		    {
			token_info_push("if");
		    }
		;

k_unless	: keyword_unless
		    {
			token_info_push("unless");
		    }
		;

k_while		: keyword_while
		    {
			token_info_push("while");
		    }
		;

k_until		: keyword_until
		    {
			token_info_push("until");
		    }
		;

k_case		: keyword_case
		    {
			token_info_push("case");
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*%
		    %*/
		    }
		;

k_for		: keyword_for
		    {
			token_info_push("for");
		    }
		;

k_class		: keyword_class
		    {
			token_info_push("class");
		    }
		;

k_module	: keyword_module
		    {
			token_info_push("module");
		    }
		;

k_def		: keyword_def
		    {
			token_info_push("def");
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*%
		    %*/
		    }
		;

k_end		: keyword_end
		    {
			token_info_pop("end");
		    }
		;

k_return	: keyword_return
		    {
			if (in_class && !in_def && !dyna_in_block())
			    yyerror0("Invalid return in class/module body");
		    }
		;

then		: term
		    /*%c%*/
		    /*%c
		    { $$ = Qnil; }
		    %*/
		| keyword_then
		| term keyword_then
		    /*%c%*/
		    /*%c
		    { $$ = $2; }
		    %*/
		;

do		: term
		    /*%c%*/
		    /*%c
		    { $$ = Qnil; }
		    %*/
		| keyword_do_cond
		;

if_tail		: opt_else
		| keyword_elsif expr_value then
		  compstmt
		  if_tail
		    {
		    /*%%%*/
			$$ = new_if($2, $4, $5, &@$);
			fixpos($$, $2);
		    /*%
			$$ = dispatch3(elsif, $2, $4, escape_Qundef($5));
		    %*/
		    }
		;

opt_else	: none
		| keyword_else compstmt
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(else, $2);
		    %*/
		    }
		;

for_var		: lhs
		| mlhs
		;

f_marg		: f_norm_arg
		    {
			$$ = assignable($1, 0, &@$);
		    /*%%%*/
		    /*%
		    %*/
		    }
		| tLPAREN f_margs rparen
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(mlhs_paren, $2);
		    %*/
		    }
		;

f_marg_list	: f_marg
		    {
		    /*%%%*/
			$$ = new_list($1, &@$);
		    /*%
			$$ = mlhs_add(mlhs_new(), $1);
		    %*/
		    }
		| f_marg_list ',' f_marg
		    {
		    /*%%%*/
			$$ = list_append($1, $3);
		    /*%
			$$ = mlhs_add($1, $3);
		    %*/
		    }
		;

f_margs		: f_marg_list
		    {
		    /*%%%*/
			$$ = new_masgn($1, 0, &@$);
		    /*%
			$$ = $1;
		    %*/
		    }
		| f_marg_list ',' tSTAR f_norm_arg
		    {
			$$ = assignable($4, 0, &@$);
		    /*%%%*/
			$$ = new_masgn($1, $$, &@$);
		    /*%
			$$ = mlhs_add_star($1, $$);
		    %*/
		    }
		| f_marg_list ',' tSTAR f_norm_arg ',' f_marg_list
		    {
			$$ = assignable($4, 0, &@$);
		    /*%%%*/
			$$ = new_masgn($1, new_postarg($$, $6, &@$), &@$);
		    /*%
			$$ = mlhs_add_star($1, $$);
			$$ = mlhs_add_post($$, $6);
		    %*/
		    }
		| f_marg_list ',' tSTAR
		    {
		    /*%%%*/
			$$ = new_masgn($1, NODE_SPECIAL_NO_NAME_REST, &@$);
		    /*%
			$$ = mlhs_add_star($1, Qnil);
		    %*/
		    }
		| f_marg_list ',' tSTAR ',' f_marg_list
		    {
		    /*%%%*/
			$$ = new_masgn($1, new_postarg(NODE_SPECIAL_NO_NAME_REST, $5, &@$), &@$);
		    /*%
			$$ = mlhs_add_star($1, Qnil);
			$$ = mlhs_add_post($$, $5);
		    %*/
		    }
		| tSTAR f_norm_arg
		    {
			$$ = assignable($2, 0, &@$);
		    /*%%%*/
			$$ = new_masgn(0, $$, &@$);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), $$);
		    %*/
		    }
		| tSTAR f_norm_arg ',' f_marg_list
		    {
			$$ = assignable($2, 0, &@$);
		    /*%%%*/
			$$ = new_masgn(0, new_postarg($$, $4, &@$), &@$);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), $$);
			$$ = mlhs_add_post($$, $4);
		    %*/
		    }
		| tSTAR
		    {
		    /*%%%*/
			$$ = new_masgn(0, NODE_SPECIAL_NO_NAME_REST, &@$);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), Qnil);
		    %*/
		    }
		| tSTAR ',' f_marg_list
		    {
		    /*%%%*/
			$$ = new_masgn(0, new_postarg(NODE_SPECIAL_NO_NAME_REST, $3, &@$), &@$);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), Qnil);
			$$ = mlhs_add_post($$, $3);
		    %*/
		    }
		;


block_args_tail	: f_block_kwarg ',' f_kwrest opt_f_block_arg
		    {
			$$ = new_args_tail($1, $3, $4, &@3);
		    }
		| f_block_kwarg opt_f_block_arg
		    {
			$$ = new_args_tail($1, Qnone, $2, &@1);
		    }
		| f_kwrest opt_f_block_arg
		    {
			$$ = new_args_tail(Qnone, $1, $2, &@1);
		    }
		| f_block_arg
		    {
			$$ = new_args_tail(Qnone, Qnone, $1, &@1);
		    }
		;

opt_block_args_tail : ',' block_args_tail
		    {
			$$ = $2;
		    }
		| /* none */
		    {
			$$ = new_args_tail(Qnone, Qnone, Qnone, &@0);
		    }
		;

block_param	: f_arg ',' f_block_optarg ',' f_rest_arg opt_block_args_tail
		    {
			$$ = new_args($1, $3, $5, Qnone, $6, &@$);
		    }
		| f_arg ',' f_block_optarg ',' f_rest_arg ',' f_arg opt_block_args_tail
		    {
			$$ = new_args($1, $3, $5, $7, $8, &@$);
		    }
		| f_arg ',' f_block_optarg opt_block_args_tail
		    {
			$$ = new_args($1, $3, Qnone, Qnone, $4, &@$);
		    }
		| f_arg ',' f_block_optarg ',' f_arg opt_block_args_tail
		    {
			$$ = new_args($1, $3, Qnone, $5, $6, &@$);
		    }
                | f_arg ',' f_rest_arg opt_block_args_tail
		    {
			$$ = new_args($1, Qnone, $3, Qnone, $4, &@$);
		    }
		| f_arg ','
		    {
			$$ = new_args($1, Qnone, 1, Qnone, new_args_tail(Qnone, Qnone, Qnone, &@1), &@$);
		    /*%%%*/
		    /*%
                        dispatch1(excessed_comma, $$);
		    %*/
		    }
		| f_arg ',' f_rest_arg ',' f_arg opt_block_args_tail
		    {
			$$ = new_args($1, Qnone, $3, $5, $6, &@$);
		    }
		| f_arg opt_block_args_tail
		    {
			$$ = new_args($1, Qnone, Qnone, Qnone, $2, &@$);
		    }
		| f_block_optarg ',' f_rest_arg opt_block_args_tail
		    {
			$$ = new_args(Qnone, $1, $3, Qnone, $4, &@$);
		    }
		| f_block_optarg ',' f_rest_arg ',' f_arg opt_block_args_tail
		    {
			$$ = new_args(Qnone, $1, $3, $5, $6, &@$);
		    }
		| f_block_optarg opt_block_args_tail
		    {
			$$ = new_args(Qnone, $1, Qnone, Qnone, $2, &@$);
		    }
		| f_block_optarg ',' f_arg opt_block_args_tail
		    {
			$$ = new_args(Qnone, $1, Qnone, $3, $4, &@$);
		    }
		| f_rest_arg opt_block_args_tail
		    {
			$$ = new_args(Qnone, Qnone, $1, Qnone, $2, &@$);
		    }
		| f_rest_arg ',' f_arg opt_block_args_tail
		    {
			$$ = new_args(Qnone, Qnone, $1, $3, $4, &@$);
		    }
		| block_args_tail
		    {
			$$ = new_args(Qnone, Qnone, Qnone, Qnone, $1, &@$);
		    }
		;

opt_block_param	: none
		| block_param_def
		    {
			command_start = TRUE;
		    }
		;

block_param_def	: '|' opt_bv_decl '|'
		    {
			current_arg = 0;
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = blockvar_new(params_new(Qnil,Qnil,Qnil,Qnil,Qnil,Qnil,Qnil),
                                          escape_Qundef($2));
		    %*/
		    }
		| tOROP
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = blockvar_new(params_new(Qnil,Qnil,Qnil,Qnil,Qnil,Qnil,Qnil),
                                          Qnil);
		    %*/
		    }
		| '|' block_param opt_bv_decl '|'
		    {
			current_arg = 0;
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = blockvar_new(escape_Qundef($2), escape_Qundef($3));
		    %*/
		    }
		;


opt_bv_decl	: opt_nl
		    {
		      $$ = 0;
		    }
		| opt_nl ';' bv_decls opt_nl
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = $3;
		    %*/
		    }
		;

bv_decls	: bvar
		    /*%c%*/
		    /*%c
		    {
			$$ = rb_ary_new3(1, get_value($1));
		    }
		    %*/
		| bv_decls ',' bvar
		    /*%c%*/
		    /*%c
		    {
			rb_ary_push($1, get_value($3));
		    }
		    %*/
		;

bvar		: tIDENTIFIER
		    {
			new_bv(get_id($1));
		    /*%%%*/
		    /*%
			$$ = get_value($1);
		    %*/
		    }
		| f_bad_arg
		    {
			$$ = 0;
		    }
		;

lambda		:   {
			$<vars>$ = dyna_push();
		    }
		    {
			$<num>$ = lpar_beg;
			lpar_beg = ++paren_nest;
		    }
		  f_larglist
		    {
			$<num>$ = ruby_sourceline;
		    }
		    {
			$<val>$ = cmdarg_stack;
			CMDARG_SET(0);
		    }
		  lambda_body
		    {
			lpar_beg = $<num>2;
			CMDARG_SET($<val>5);
			CMDARG_LEXPOP();
		    /*%%%*/
			$$ = NEW_LAMBDA($3, $6);
			nd_set_line($$, $<num>4);
			$$->nd_loc = @$;
			$$->nd_body->nd_loc = @$;
		    /*%
			$$ = dispatch2(lambda, $3, $6);
		    %*/
			dyna_pop($<vars>1);
		    }
		;

f_larglist	: '(' f_args opt_bv_decl ')'
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(paren, $2);
		    %*/
		    }
		| f_args
		    {
			$$ = $1;
		    }
		;

lambda_body	: tLAMBEG compstmt '}'
		    {
			token_info_pop("}");
			$$ = $2;
		    }
		| keyword_do_LAMBDA compstmt k_end
		    {
			$$ = $2;
		    }
		;

do_block	: keyword_do_block
		    {
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*% %*/
		    }
		  do_body keyword_end
		    {
			$$ = $3;
		    /*%%%*/
			$3->nd_body->nd_loc.first_loc = @1.first_loc;
			$3->nd_body->nd_loc.last_loc = @4.last_loc;
			nd_set_line($$, $<num>2);
		    /*% %*/
		    }
		;

block_call	: command do_block
		    {
		    /*%%%*/
			if (nd_type($1) == NODE_YIELD) {
			    compile_error(PARSER_ARG "block given to yield");
			}
			else {
			    block_dup_check($1->nd_args, $2);
			}
			$2->nd_iter = $1;
			$2->nd_loc = @$;
			$$ = $2;
			fixpos($$, $1);
		    /*%
			$$ = method_add_block($1, $2);
		    %*/
		    }
		| block_call call_op2 operation2 opt_paren_args
		    {
			$$ = new_qcall($2, $1, $3, $4, &@$);
		    }
		| block_call call_op2 operation2 opt_paren_args brace_block
		    {
		    /*%%%*/
			block_dup_check($4, $5);
			$5->nd_iter = new_command_qcall($2, $1, $3, $4, &@$);
			$5->nd_loc = @$;
			$$ = $5;
			fixpos($$, $1);
		    /*%
			$$ = dispatch4(command_call, $1, $2, $3, $4);
			$$ = method_add_block($$, $5);
		    %*/
		    }
		| block_call call_op2 operation2 command_args do_block
		    {
		    /*%%%*/
			block_dup_check($4, $5);
			$5->nd_iter = new_command_qcall($2, $1, $3, $4, &@$);
			$5->nd_loc = @$;
			$$ = $5;
			fixpos($$, $1);
		    /*%
			$$ = dispatch4(command_call, $1, $2, $3, $4);
			$$ = method_add_block($$, $5);
		    %*/
		    }
		;

method_call	: fcall paren_args
		    {
		    /*%%%*/
			$$ = $1;
			$$->nd_args = $2;
			nd_set_last_loc($1, @2.last_loc);
		    /*%
			$$ = method_arg(dispatch1(fcall, $1), $2);
		    %*/
		    }
		| primary_value call_op operation2
		    {
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*% %*/
		    }
		  opt_paren_args
		    {
			$$ = new_qcall($2, $1, $3, $5, &@$);
			nd_set_line($$, $<num>4);
		    }
		| primary_value tCOLON2 operation2
		    {
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*% %*/
		    }
		  paren_args
		    {
			$$ = new_qcall(ID2VAL(idCOLON2), $1, $3, $5, &@$);
			nd_set_line($$, $<num>4);
		    }
		| primary_value tCOLON2 operation3
		    {
			$$ = new_qcall(ID2VAL(idCOLON2), $1, $3, Qnull, &@$);
		    }
		| primary_value call_op
		    {
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*% %*/
		    }
		  paren_args
		    {
			$$ = new_qcall($2, $1, ID2VAL(idCall), $4, &@$);
			nd_set_line($$, $<num>3);
		    }
		| primary_value tCOLON2
		    {
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*% %*/
		    }
		  paren_args
		    {
			$$ = new_qcall(ID2VAL(idCOLON2), $1, ID2VAL(idCall), $4, &@$);
			nd_set_line($$, $<num>3);
		    }
		| keyword_super paren_args
		    {
		    /*%%%*/
			$$ = NEW_SUPER($2);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(super, $2);
		    %*/
		    }
		| keyword_super
		    {
		    /*%%%*/
			$$ = NEW_ZSUPER();
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch0(zsuper);
		    %*/
		    }
		| primary_value '[' opt_call_args rbracket
		    {
		    /*%%%*/
			if ($1 && nd_type($1) == NODE_SELF)
			    $$ = new_fcall(tAREF, $3, &@$);
			else
			    $$ = new_call($1, tAREF, $3, &@$);
			fixpos($$, $1);
		    /*%
			$$ = dispatch2(aref, $1, escape_Qundef($3));
		    %*/
		    }
		;

brace_block	: '{'
		    {
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*% %*/
		    }
		  brace_body '}'
		    {
			$$ = $3;
		    /*%%%*/
			$3->nd_body->nd_loc.first_loc = @1.first_loc;
			$3->nd_body->nd_loc.last_loc = @4.last_loc;
			nd_set_line($$, $<num>2);
		    /*% %*/
		    }
		| keyword_do
		    {
		    /*%%%*/
			$<num>$ = ruby_sourceline;
		    /*% %*/
		    }
		  do_body keyword_end
		    {
			$$ = $3;
		    /*%%%*/
			$3->nd_body->nd_loc.first_loc = @1.first_loc;
			$3->nd_body->nd_loc.last_loc = @4.last_loc;
			nd_set_line($$, $<num>2);
		    /*% %*/
		    }
		;

brace_body	: {$<vars>$ = dyna_push();}
		  {$<val>$ = cmdarg_stack >> 1; CMDARG_SET(0);}
		  opt_block_param compstmt
		    {
			$$ = new_brace_body($3, $4, &@$);
			dyna_pop($<vars>1);
			CMDARG_SET($<val>2);
		    }
		;

do_body 	: {$<vars>$ = dyna_push();}
		  {$<val>$ = cmdarg_stack; CMDARG_SET(0);}
		  opt_block_param bodystmt
		    {
			$$ = new_do_body($3, $4, &@$);
			dyna_pop($<vars>1);
			CMDARG_SET($<val>2);
		    }
		;

case_body	: keyword_when args then
		  compstmt
		  cases
		    {
		    /*%%%*/
			$$ = NEW_WHEN($2, $4, $5);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch3(when, $2, $4, escape_Qundef($5));
		    %*/
		    }
		;

cases		: opt_else
		| case_body
		;

opt_rescue	: keyword_rescue exc_list exc_var then
		  compstmt
		  opt_rescue
		    {
		    /*%%%*/
			if ($3) {
			    YYLTYPE location;
			    location.first_loc = @3.first_loc;
			    location.last_loc = @5.last_loc;
			    $3 = node_assign($3, new_errinfo(&@3), &@3);
			    $5 = block_append($3, $5, &location);
			}
			$$ = new_resbody($2, $5, $6, &@$);
			fixpos($$, $2?$2:$5);
		    /*%
			$$ = dispatch4(rescue,
				       escape_Qundef($2),
				       escape_Qundef($3),
				       escape_Qundef($5),
				       escape_Qundef($6));
		    %*/
		    }
		| none
		;

exc_list	: arg_value
		    {
		    /*%%%*/
			$$ = new_list($1, &@$);
		    /*%
			$$ = rb_ary_new3(1, get_value($1));
		    %*/
		    }
		| mrhs
		    {
		    /*%%%*/
			if (!($$ = splat_array($1))) $$ = $1;
		    /*%
			$$ = $1;
		    %*/
		    }
		| none
		;

exc_var		: tASSOC lhs
		    {
			$$ = $2;
		    }
		| none
		;

opt_ensure	: keyword_ensure compstmt
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(ensure, $2);
		    %*/
		    }
		| none
		;

literal		: numeric
		| symbol
		    {
		    /*%%%*/
			$$ = new_lit(ID2SYM($1), &@$);
		    /*%
			$$ = dispatch1(symbol_literal, $1);
		    %*/
		    }
		| dsym
		;

strings		: string
		    {
		    /*%%%*/
			NODE *node = $1;
			if (!node) {
			    node = new_str(STR_NEW0(), &@$);
			}
			else {
			    node = evstr2dstr(node);
			}
			$$ = node;
		    /*%
			$$ = $1;
		    %*/
		    }
		;

string		: tCHAR
		    {
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		    }
		| string1
		| string string1
		    {
		    /*%%%*/
			$$ = literal_concat($1, $2, &@$);
		    /*%
			$$ = dispatch2(string_concat, $1, $2);
		    %*/
		    }
		;

string1		: tSTRING_BEG string_contents tSTRING_END
		    {
			$$ = new_string1(heredoc_dedent($2));
		    /*%%%*/
			if ($$) nd_set_loc($$, &@$);
		    /*%
		    %*/
		    }
		;

xstring		: tXSTRING_BEG xstring_contents tSTRING_END
		    {
			$$ = new_xstring(heredoc_dedent($2), &@$);
		    }
		;

regexp		: tREGEXP_BEG regexp_contents tREGEXP_END
		    {
			$$ = new_regexp($2, $3, &@$);
		    }
		;

words		: tWORDS_BEG ' ' word_list tSTRING_END
		    {
		    /*%%%*/
			$$ = make_array($3, &@$);
		    /*%
			$$ = dispatch1(array, $3);
		    %*/
		    }
		;

word_list	: /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = dispatch0(words_new);
		    %*/
		    }
		| word_list word ' '
		    {
		    /*%%%*/
			$$ = list_append($1, evstr2dstr($2));
		    /*%
			$$ = dispatch2(words_add, $1, $2);
		    %*/
		    }
		;

word		: string_content
		    /*%c%*/
		    /*%c
		    {
			$$ = dispatch0(word_new);
			$$ = dispatch2(word_add, $$, $1);
		    }
		    %*/
		| word string_content
		    {
		    /*%%%*/
			$$ = literal_concat($1, $2, &@$);
		    /*%
			$$ = dispatch2(word_add, $1, $2);
		    %*/
		    }
		;

symbols 	: tSYMBOLS_BEG ' ' symbol_list tSTRING_END
		    {
		    /*%%%*/
			$$ = make_array($3, &@$);
		    /*%
			$$ = dispatch1(array, $3);
		    %*/
		    }
		;

symbol_list	: /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = dispatch0(symbols_new);
		    %*/
		    }
		| symbol_list word ' '
		    {
		    /*%%%*/
			$2 = evstr2dstr($2);
			if (nd_type($2) == NODE_DSTR) {
			    nd_set_type($2, NODE_DSYM);
			}
			else {
			    nd_set_type($2, NODE_LIT);
			    add_mark_object($2->nd_lit = rb_str_intern($2->nd_lit));
			}
			$$ = list_append($1, $2);
		    /*%
			$$ = dispatch2(symbols_add, $1, $2);
		    %*/
		    }
		;

qwords		: tQWORDS_BEG ' ' qword_list tSTRING_END
		    {
		    /*%%%*/
			$$ = make_array($3, &@$);
		    /*%
			$$ = dispatch1(array, $3);
		    %*/
		    }
		;

qsymbols	: tQSYMBOLS_BEG ' ' qsym_list tSTRING_END
		    {
		    /*%%%*/
			$$ = make_array($3, &@$);
		    /*%
			$$ = dispatch1(array, $3);
		    %*/
		    }
		;

qword_list	: /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = dispatch0(qwords_new);
		    %*/
		    }
		| qword_list tSTRING_CONTENT ' '
		    {
		    /*%%%*/
			$2->nd_loc = @2;
			$$ = list_append($1, $2);
		    /*%
			$$ = dispatch2(qwords_add, $1, $2);
		    %*/
		    }
		;

qsym_list	: /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = dispatch0(qsymbols_new);
		    %*/
		    }
		| qsym_list tSTRING_CONTENT ' '
		    {
		    /*%%%*/
			VALUE lit;
			lit = $2->nd_lit;
			nd_set_type($2, NODE_LIT);
			add_mark_object($2->nd_lit = ID2SYM(rb_intern_str(lit)));
			$2->nd_loc = @2;
			$$ = list_append($1, $2);
		    /*%
			$$ = dispatch2(qsymbols_add, $1, $2);
		    %*/
		    }
		;

string_contents : /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = dispatch0(string_content);
		    %*/
		    }
		| string_contents string_content
		    {
		    /*%%%*/
			$$ = literal_concat($1, $2, &@$);
		    /*%
			$$ = dispatch2(string_add, $1, $2);
		    %*/
		    }
		;

xstring_contents: /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = dispatch0(xstring_new);
		    %*/
		    }
		| xstring_contents string_content
		    {
		    /*%%%*/
			$$ = literal_concat($1, $2, &@$);
		    /*%
			$$ = dispatch2(xstring_add, $1, $2);
		    %*/
		    }
		;

regexp_contents: /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = ripper_new_yylval(0, dispatch0(regexp_new), 0);
		    %*/
		    }
		| regexp_contents string_content
		    {
		    /*%%%*/
			NODE *head = $1, *tail = $2;
			if (!head) {
			    $$ = tail;
			}
			else if (!tail) {
			    $$ = head;
			}
			else {
			    switch (nd_type(head)) {
			      case NODE_STR:
				nd_set_type(head, NODE_DSTR);
				break;
			      case NODE_DSTR:
				break;
			      default:
				head = list_append(new_dstr(Qnil, &@$), head);
				break;
			    }
			    $$ = list_append(head, tail);
			}
		    /*%
			VALUE s1 = 1, s2 = 0, n1 = $1, n2 = $2;
			if (ripper_is_node_yylval(n1)) {
			    s1 = RNODE(n1)->nd_cval;
			    n1 = RNODE(n1)->nd_rval;
			}
			if (ripper_is_node_yylval(n2)) {
			    s2 = RNODE(n2)->nd_cval;
			    n2 = RNODE(n2)->nd_rval;
			}
			$$ = dispatch2(regexp_add, n1, n2);
			if (!s1 && s2) {
			    $$ = ripper_new_yylval(0, $$, s2);
			}
		    %*/
		    }
		;

string_content	: tSTRING_CONTENT
		    {
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		    }
		| tSTRING_DVAR
		    {
			/* need to backup lex_strterm so that a string literal `%&foo,#$&,bar&` can be parsed */
			$<strterm>$ = lex_strterm;
			lex_strterm = 0;
			SET_LEX_STATE(EXPR_BEG);
		    }
		  string_dvar
		    {
			lex_strterm = $<strterm>2;
		    /*%%%*/
			$$ = NEW_EVSTR($3);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(string_dvar, $3);
		    %*/
		    }
		| tSTRING_DBEG
		    {
			$<val>1 = cond_stack;
			$<val>$ = cmdarg_stack;
			COND_SET(0);
			CMDARG_SET(0);
		    }
		    {
			/* need to backup lex_strterm so that a string literal `%!foo,#{ !0 },bar!` can be parsed */
			$<strterm>$ = lex_strterm;
			lex_strterm = 0;
		    }
		    {
			$<num>$ = lex_state;
			SET_LEX_STATE(EXPR_BEG);
		    }
		    {
			$<num>$ = brace_nest;
			brace_nest = 0;
		    }
		    {
			$<num>$ = heredoc_indent;
			heredoc_indent = 0;
		    }
		  compstmt tSTRING_DEND
		    {
			COND_SET($<val>1);
			CMDARG_SET($<val>2);
			lex_strterm = $<strterm>3;
			SET_LEX_STATE($<num>4);
			brace_nest = $<num>5;
			heredoc_indent = $<num>6;
			heredoc_line_indent = -1;
		    /*%%%*/
			if ($7) $7->flags &= ~NODE_FL_NEWLINE;
			$$ = new_evstr($7, &@$);
		    /*%
			$$ = dispatch1(string_embexpr, $7);
		    %*/
		    }
		;

string_dvar	: tGVAR
		    {
		    /*%%%*/
			$$ = new_gvar($1, &@$);
		    /*%
			$$ = dispatch1(var_ref, $1);
		    %*/
		    }
		| tIVAR
		    {
		    /*%%%*/
			$$ = new_ivar($1, &@$);
		    /*%
			$$ = dispatch1(var_ref, $1);
		    %*/
		    }
		| tCVAR
		    {
		    /*%%%*/
			$$ = NEW_CVAR($1);
			$$->nd_loc = @$;
		    /*%
			$$ = dispatch1(var_ref, $1);
		    %*/
		    }
		| backref
		;

symbol		: tSYMBEG sym
		    {
			SET_LEX_STATE(EXPR_END|EXPR_ENDARG);
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(symbol, $2);
		    %*/
		    }
		;

sym		: fname
		| tIVAR
		| tGVAR
		| tCVAR
		;

dsym		: tSYMBEG xstring_contents tSTRING_END
		    {
			SET_LEX_STATE(EXPR_END|EXPR_ENDARG);
		    /*%%%*/
			$$ = dsym_node($2, &@$);
		    /*%
			$$ = dispatch1(dyna_symbol, $2);
		    %*/
		    }
		;

numeric 	: simple_numeric
		| tUMINUS_NUM simple_numeric   %prec tLOWEST
		    {
		    /*%%%*/
			$$ = $2;
			add_mark_object($$->nd_lit = negate_lit($$->nd_lit));
		    /*%
			$$ = dispatch2(unary, ID2VAL(idUMinus), $2);
		    %*/
		    }
		;

simple_numeric	: tINTEGER
		    {
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		    }
		| tFLOAT
		    {
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		    }
		| tRATIONAL
		    {
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		    }
		| tIMAGINARY
		    {
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		    }
		;

user_variable	: tIDENTIFIER
		| tIVAR
		| tGVAR
		| tCONSTANT
		| tCVAR
		;

keyword_variable: keyword_nil {$$ = KWD2EID(nil, $1);}
		| keyword_self {$$ = KWD2EID(self, $1);}
		| keyword_true {$$ = KWD2EID(true, $1);}
		| keyword_false {$$ = KWD2EID(false, $1);}
		| keyword__FILE__ {$$ = KWD2EID(_FILE__, $1);}
		| keyword__LINE__ {$$ = KWD2EID(_LINE__, $1);}
		| keyword__ENCODING__ {$$ = KWD2EID(_ENCODING__, $1);}
		;

var_ref		: user_variable
		    {
		    /*%%%*/
			if (!($$ = gettable($1, &@$))) $$ = new_begin(0, &@$);
		    /*%
			if (id_is_var(get_id($1))) {
			    $$ = dispatch1(var_ref, $1);
			}
			else {
			    $$ = dispatch1(vcall, $1);
			}
		    %*/
		    }
		| keyword_variable
		    {
		    /*%%%*/
			if (!($$ = gettable($1, &@$))) $$ = new_begin(0, &@$);
		    /*%
			$$ = dispatch1(var_ref, $1);
		    %*/
		    }
		;

var_lhs		: user_variable
		    {
			$$ = assignable(var_field($1), 0, &@$);
		    }
		| keyword_variable
		    {
			$$ = assignable(var_field($1), 0, &@$);
		    }
		;

backref		: tNTH_REF
		    {
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		    }
		| tBACK_REF
		    {
		    /*%%%*/
			$$->nd_loc = @$;
		    /*%
		    %*/
		    }
		;

superclass	: '<'
		    {
			SET_LEX_STATE(EXPR_BEG);
			command_start = TRUE;
		    }
		  expr_value term
		    {
			$$ = $3;
		    }
		| /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = Qnil;
		    %*/
		    }
		;

f_arglist	: '(' f_args rparen
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(paren, $2);
		    %*/
			SET_LEX_STATE(EXPR_BEG);
			command_start = TRUE;
		    }
		|   {
			$<num>$ = parser->in_kwarg;
			parser->in_kwarg = 1;
			SET_LEX_STATE(lex_state|EXPR_LABEL); /* force for args */
		    }
		    f_args term
		    {
			parser->in_kwarg = !!$<num>1;
			$$ = $2;
			SET_LEX_STATE(EXPR_BEG);
			command_start = TRUE;
		    }
		;

args_tail	: f_kwarg ',' f_kwrest opt_f_block_arg
		    {
			$$ = new_args_tail($1, $3, $4, &@3);
		    }
		| f_kwarg opt_f_block_arg
		    {
			$$ = new_args_tail($1, Qnone, $2, &@1);
		    }
		| f_kwrest opt_f_block_arg
		    {
			$$ = new_args_tail(Qnone, $1, $2, &@1);
		    }
		| f_block_arg
		    {
			$$ = new_args_tail(Qnone, Qnone, $1, &@1);
		    }
		;

opt_args_tail	: ',' args_tail
		    {
			$$ = $2;
		    }
		| /* none */
		    {
			$$ = new_args_tail(Qnone, Qnone, Qnone, &@0);
		    }
		;

f_args		: f_arg ',' f_optarg ',' f_rest_arg opt_args_tail
		    {
			$$ = new_args($1, $3, $5, Qnone, $6, &@$);
		    }
		| f_arg ',' f_optarg ',' f_rest_arg ',' f_arg opt_args_tail
		    {
			$$ = new_args($1, $3, $5, $7, $8, &@$);
		    }
		| f_arg ',' f_optarg opt_args_tail
		    {
			$$ = new_args($1, $3, Qnone, Qnone, $4, &@$);
		    }
		| f_arg ',' f_optarg ',' f_arg opt_args_tail
		    {
			$$ = new_args($1, $3, Qnone, $5, $6, &@$);
		    }
		| f_arg ',' f_rest_arg opt_args_tail
		    {
			$$ = new_args($1, Qnone, $3, Qnone, $4, &@$);
		    }
		| f_arg ',' f_rest_arg ',' f_arg opt_args_tail
		    {
			$$ = new_args($1, Qnone, $3, $5, $6, &@$);
		    }
		| f_arg opt_args_tail
		    {
			$$ = new_args($1, Qnone, Qnone, Qnone, $2, &@$);
		    }
		| f_optarg ',' f_rest_arg opt_args_tail
		    {
			$$ = new_args(Qnone, $1, $3, Qnone, $4, &@$);
		    }
		| f_optarg ',' f_rest_arg ',' f_arg opt_args_tail
		    {
			$$ = new_args(Qnone, $1, $3, $5, $6, &@$);
		    }
		| f_optarg opt_args_tail
		    {
			$$ = new_args(Qnone, $1, Qnone, Qnone, $2, &@$);
		    }
		| f_optarg ',' f_arg opt_args_tail
		    {
			$$ = new_args(Qnone, $1, Qnone, $3, $4, &@$);
		    }
		| f_rest_arg opt_args_tail
		    {
			$$ = new_args(Qnone, Qnone, $1, Qnone, $2, &@$);
		    }
		| f_rest_arg ',' f_arg opt_args_tail
		    {
			$$ = new_args(Qnone, Qnone, $1, $3, $4, &@$);
		    }
		| args_tail
		    {
			$$ = new_args(Qnone, Qnone, Qnone, Qnone, $1, &@$);
		    }
		| /* none */
		    {
			$$ = new_args_tail(Qnone, Qnone, Qnone, &@0);
			$$ = new_args(Qnone, Qnone, Qnone, Qnone, $$, &@0);
		    }
		;

f_bad_arg	: tCONSTANT
		    {
		    /*%%%*/
			yyerror0("formal argument cannot be a constant");
			$$ = 0;
		    /*%
			$$ = dispatch1(param_error, $1);
			ripper_error();
		    %*/
		    }
		| tIVAR
		    {
		    /*%%%*/
			yyerror0("formal argument cannot be an instance variable");
			$$ = 0;
		    /*%
			$$ = dispatch1(param_error, $1);
			ripper_error();
		    %*/
		    }
		| tGVAR
		    {
		    /*%%%*/
			yyerror0("formal argument cannot be a global variable");
			$$ = 0;
		    /*%
			$$ = dispatch1(param_error, $1);
			ripper_error();
		    %*/
		    }
		| tCVAR
		    {
		    /*%%%*/
			yyerror0("formal argument cannot be a class variable");
			$$ = 0;
		    /*%
			$$ = dispatch1(param_error, $1);
			ripper_error();
		    %*/
		    }
		;

f_norm_arg	: f_bad_arg
		| tIDENTIFIER
		    {
			formal_argument(get_id($1));
			$$ = $1;
		    }
		;

f_arg_asgn	: f_norm_arg
		    {
			ID id = get_id($1);
			arg_var(id);
			current_arg = id;
			$$ = $1;
		    }
		;

f_arg_item	: f_arg_asgn
		    {
			current_arg = 0;
		    /*%%%*/
			$$ = NEW_ARGS_AUX($1, 1);
		    /*%
			$$ = get_value($1);
		    %*/
		    }
		| tLPAREN f_margs rparen
		    {
			ID tid = internal_id();
		    /*%%%*/
			YYLTYPE location;
			location.first_loc = @2.first_loc;
			location.last_loc = @2.first_loc;
		    /*%
		    %*/
			arg_var(tid);
		    /*%%%*/
			if (dyna_in_block()) {
			    $2->nd_value = new_dvar(tid, &location);
			}
			else {
			    $2->nd_value = new_lvar(tid, &location);
			}
			$$ = NEW_ARGS_AUX(tid, 1);
			$$->nd_next = $2;
		    /*%
			$$ = dispatch1(mlhs_paren, $2);
		    %*/
		    }
		;

f_arg		: f_arg_item
		    /*%c%*/
		    /*%c
		    {
			$$ = rb_ary_new3(1, get_value($1));
		    }
		    c%*/
		| f_arg ',' f_arg_item
		    {
		    /*%%%*/
			$$ = $1;
			$$->nd_plen++;
			$$->nd_next = block_append($$->nd_next, $3->nd_next, &@$);
			rb_discard_node($3);
		    /*%
			$$ = rb_ary_push($1, get_value($3));
		    %*/
		    }
		;


f_label 	: tLABEL
		    {
			ID id = get_id($1);
			arg_var(formal_argument(id));
			current_arg = id;
			$$ = $1;
		    }
		;

f_kw		: f_label arg_value
		    {
			current_arg = 0;
			$$ = assignable($1, $2, &@$);
		    /*%%%*/
			$$ = new_kw_arg($$, &@$);
		    /*%
			$$ = rb_assoc_new(get_value($$), get_value($2));
		    %*/
		    }
		| f_label
		    {
			current_arg = 0;
			$$ = assignable($1, NODE_SPECIAL_REQUIRED_KEYWORD, &@$);
		    /*%%%*/
			$$ = new_kw_arg($$, &@$);
		    /*%
			$$ = rb_assoc_new(get_value($$), 0);
		    %*/
		    }
		;

f_block_kw	: f_label primary_value
		    {
			$$ = assignable($1, $2, &@$);
		    /*%%%*/
			$$ = new_kw_arg($$, &@$);
		    /*%
			$$ = rb_assoc_new(get_value($$), get_value($2));
		    %*/
		    }
		| f_label
		    {
			$$ = assignable($1, NODE_SPECIAL_REQUIRED_KEYWORD, &@$);
		    /*%%%*/
			$$ = new_kw_arg($$, &@$);
		    /*%
			$$ = rb_assoc_new(get_value($$), 0);
		    %*/
		    }
		;

f_block_kwarg	: f_block_kw
		    {
		    /*%%%*/
			$$ = $1;
		    /*%
			$$ = rb_ary_new3(1, get_value($1));
		    %*/
		    }
		| f_block_kwarg ',' f_block_kw
		    {
		    /*%%%*/
			$$ = kwd_append($1, $3);
		    /*%
			$$ = rb_ary_push($1, get_value($3));
		    %*/
		    }
		;


f_kwarg		: f_kw
		    {
		    /*%%%*/
			$$ = $1;
		    /*%
			$$ = rb_ary_new3(1, get_value($1));
		    %*/
		    }
		| f_kwarg ',' f_kw
		    {
		    /*%%%*/
			$$ = kwd_append($1, $3);
		    /*%
			$$ = rb_ary_push($1, get_value($3));
		    %*/
		    }
		;

kwrest_mark	: tPOW
		| tDSTAR
		;

f_kwrest	: kwrest_mark tIDENTIFIER
		    {
			shadowing_lvar(get_id($2));
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(kwrest_param, $2);
		    %*/
		    }
		| kwrest_mark
		    {
		    /*%%%*/
			$$ = internal_id();
			arg_var($$);
		    /*%
			$$ = dispatch1(kwrest_param, Qnil);
		    %*/
		    }
		;

f_opt		: f_arg_asgn '=' arg_value
		    {
			current_arg = 0;
			$$ = assignable($1, $3, &@$);
		    /*%%%*/
			$$ = NEW_OPT_ARG(0, $$);
			$$->nd_loc = @$;
		    /*%
			$$ = rb_assoc_new(get_value($$), get_value($3));
		    %*/
		    }
		;

f_block_opt	: f_arg_asgn '=' primary_value
		    {
			current_arg = 0;
			$$ = assignable($1, $3, &@$);
		    /*%%%*/
			$$ = NEW_OPT_ARG(0, $$);
			$$->nd_loc = @$;
		    /*%
			$$ = rb_assoc_new(get_value($$), get_value($3));
		    %*/
		    }
		;

f_block_optarg	: f_block_opt
		    {
		    /*%%%*/
			$$ = $1;
		    /*%
			$$ = rb_ary_new3(1, get_value($1));
		    %*/
		    }
		| f_block_optarg ',' f_block_opt
		    {
		    /*%%%*/
			$$ = opt_arg_append($1, $3);
		    /*%
			$$ = rb_ary_push($1, get_value($3));
		    %*/
		    }
		;

f_optarg	: f_opt
		    {
		    /*%%%*/
			$$ = $1;
		    /*%
			$$ = rb_ary_new3(1, get_value($1));
		    %*/
		    }
		| f_optarg ',' f_opt
		    {
		    /*%%%*/
			$$ = opt_arg_append($1, $3);
		    /*%
			$$ = rb_ary_push($1, get_value($3));
		    %*/
		    }
		;

restarg_mark	: '*'
		| tSTAR
		;

f_rest_arg	: restarg_mark tIDENTIFIER
		    {
		    /*%%%*/
			if (!is_local_id($2))
			    yyerror0("rest argument must be local variable");
		    /*% %*/
			arg_var(shadowing_lvar(get_id($2)));
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(rest_param, $2);
		    %*/
		    }
		| restarg_mark
		    {
		    /*%%%*/
			$$ = internal_id();
			arg_var($$);
		    /*%
			$$ = dispatch1(rest_param, Qnil);
		    %*/
		    }
		;

blkarg_mark	: '&'
		| tAMPER
		;

f_block_arg	: blkarg_mark tIDENTIFIER
		    {
		    /*%%%*/
			if (!is_local_id($2))
			    yyerror0("block argument must be local variable");
			else if (!dyna_in_block() && local_id($2))
			    yyerror0("duplicated block argument name");
		    /*% %*/
			arg_var(shadowing_lvar(get_id($2)));
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(blockarg, $2);
		    %*/
		    }
		;

opt_f_block_arg	: ',' f_block_arg
		    {
			$$ = $2;
		    }
		| none
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = Qundef;
		    %*/
		    }
		;

singleton	: var_ref
		    {
		    /*%%%*/
			value_expr($1);
			$$ = $1;
			if (!$$) $$ = NEW_NIL();
		    /*%
			$$ = $1;
		    %*/
		    }
		| '(' {SET_LEX_STATE(EXPR_BEG);} expr rparen
		    {
		    /*%%%*/
			if ($3 == 0) {
			    yyerror0("can't define singleton method for ().");
			}
			else {
			    switch (nd_type($3)) {
			      case NODE_STR:
			      case NODE_DSTR:
			      case NODE_XSTR:
			      case NODE_DXSTR:
			      case NODE_DREGX:
			      case NODE_LIT:
			      case NODE_ARRAY:
			      case NODE_ZARRAY:
				yyerror0("can't define singleton method for literals");
				break;
			      default:
				value_expr($3);
				break;
			    }
			}
			$$ = $3;
		    /*%
			$$ = dispatch1(paren, $3);
		    %*/
		    }
		;

assoc_list	: none
		| assocs trailer
		    {
		    /*%%%*/
			$$ = $1;
		    /*%
			$$ = dispatch1(assoclist_from_args, $1);
		    %*/
		    }
		;

assocs		: assoc
		    /*%c%*/
		    /*%c
		    {
			$$ = rb_ary_new3(1, get_value($1));
		    }
		    %*/
		| assocs ',' assoc
		    {
		    /*%%%*/
			NODE *assocs = $1;
			NODE *tail = $3;
			if (!assocs) {
			    assocs = tail;
			}
			else if (tail) {
			    if (assocs->nd_head &&
				!tail->nd_head && nd_type(tail->nd_next) == NODE_ARRAY &&
				nd_type(tail->nd_next->nd_head) == NODE_HASH) {
				/* DSTAR */
				tail = tail->nd_next->nd_head->nd_head;
			    }
			    assocs = list_concat(assocs, tail);
			}
			$$ = assocs;
		    /*%
			$$ = rb_ary_push($1, get_value($3));
		    %*/
		    }
		;

assoc		: arg_value tASSOC arg_value
		    {
		    /*%%%*/
			if (nd_type($1) == NODE_STR) {
			    nd_set_type($1, NODE_LIT);
			    add_mark_object($1->nd_lit = rb_fstring($1->nd_lit));
			}
			$$ = list_append(new_list($1, &@$), $3);
		    /*%
			$$ = dispatch2(assoc_new, $1, $3);
		    %*/
		    }
		| tLABEL arg_value
		    {
		    /*%%%*/
			$$ = list_append(new_list(new_lit(ID2SYM($1), &@1), &@$), $2);
		    /*%
			$$ = dispatch2(assoc_new, $1, $2);
		    %*/
		    }
		| tSTRING_BEG string_contents tLABEL_END arg_value
		    {
		    /*%%%*/
			YYLTYPE location;
			location.first_loc = @1.first_loc;
			location.last_loc = @3.last_loc;
			$$ = list_append(new_list(dsym_node($2, &location), &location), $4);
		    /*%
			$$ = dispatch2(assoc_new, dispatch1(dyna_symbol, $2), $4);
		    %*/
		    }
		| tDSTAR arg_value
		    {
		    /*%%%*/
			if (nd_type($2) == NODE_HASH &&
			    !($2->nd_head && $2->nd_head->nd_alen))
			    $$ = 0;
			else
			    $$ = list_append(new_list(0, &@$), $2);
		    /*%
			$$ = dispatch1(assoc_splat, $2);
		    %*/
		    }
		;

operation	: tIDENTIFIER
		| tCONSTANT
		| tFID
		;

operation2	: tIDENTIFIER
		| tCONSTANT
		| tFID
		| op
		;

operation3	: tIDENTIFIER
		| tFID
		| op
		;

dot_or_colon	: '.'
		| tCOLON2
		;

call_op 	: '.'
		    {
			$$ = TOKEN2VAL('.');
		    }
		| tANDDOT
		    {
			$$ = ID2VAL(idANDDOT);
		    }
		;

call_op2	: call_op
		| tCOLON2
		    {
			$$ = ID2VAL(idCOLON2);
		    }
		;

opt_terms	: /* none */
		| terms
		;

opt_nl		: /* none */
		| '\n'
		;

rparen		: opt_nl ')'
		;

rbracket	: opt_nl ']'
		;

trailer		: /* none */
		| '\n'
		| ','
		;

term		: ';' {yyerrok;token_flush(parser);}
		| '\n' {token_flush(parser);}
		;

terms		: term
		| terms ';' {yyerrok;}
		;

none		: /* none */
		    {
			$$ = Qnull;
		    }
		;
%%
# undef parser
# undef yylex
# undef yylval
# define yylval  (*parser->lval)

static int parser_regx_options(struct parser_params*);
static int parser_tokadd_string(struct parser_params*,int,int,int,long*,rb_encoding**);
static void parser_tokaddmbc(struct parser_params *parser, int c, rb_encoding *enc);
static enum yytokentype parser_parse_string(struct parser_params*,rb_strterm_literal_t*);
static enum yytokentype parser_here_document(struct parser_params*,rb_strterm_heredoc_t*);


# define nextc()                      parser_nextc(parser)
# define pushback(c)                  parser_pushback(parser, (c))
# define newtok()                     parser_newtok(parser)
# define tokspace(n)                  parser_tokspace(parser, (n))
# define tokadd(c)                    parser_tokadd(parser, (c))
# define tok_hex(numlen)              parser_tok_hex(parser, (numlen))
# define read_escape(flags,e)         parser_read_escape(parser, (flags), (e))
# define tokadd_escape(e)             parser_tokadd_escape(parser, (e))
# define regx_options()               parser_regx_options(parser)
# define tokadd_string(f,t,p,n,e)     parser_tokadd_string(parser,(f),(t),(p),(n),(e))
# define parse_string(n)              parser_parse_string(parser,(n))
# define tokaddmbc(c, enc)            parser_tokaddmbc(parser, (c), (enc))
# define here_document(n)             parser_here_document(parser,(n))
# define heredoc_identifier()         parser_heredoc_identifier(parser)
# define heredoc_restore(n)           parser_heredoc_restore(parser,(n))
# define whole_match_p(e,l,i)         parser_whole_match_p(parser,(e),(l),(i))
# define number_literal_suffix(f)     parser_number_literal_suffix(parser, (f))
# define set_number_literal(v, t, f)  parser_set_number_literal(parser, (v), (t), (f))
# define set_integer_literal(v, f)    parser_set_integer_literal(parser, (v), (f))

#ifndef RIPPER
# define set_yylval_str(x) (yylval.node = NEW_STR(x))
# define set_yylval_num(x) (yylval.num = (x))
# define set_yylval_id(x)  (yylval.id = (x))
# define set_yylval_name(x)  (yylval.id = (x))
# define set_yylval_literal(x) (yylval.node = NEW_LIT(x))
# define set_yylval_node(x) (yylval.node = (x))
# define yylval_id() (yylval.id)
#else
static inline VALUE
ripper_yylval_id_gen(struct parser_params *parser, ID x)
{
    return ripper_new_yylval(x, ID2SYM(x), 0);
}
#define ripper_yylval_id(x) ripper_yylval_id_gen(parser, x)
# define set_yylval_str(x) (yylval.val = (x))
# define set_yylval_num(x) (yylval.val = ripper_new_yylval((x), 0, 0))
# define set_yylval_id(x)  (void)(x)
# define set_yylval_name(x) (void)(yylval.val = ripper_yylval_id(x))
# define set_yylval_literal(x) (void)(x)
# define set_yylval_node(x) (void)(x)
# define yylval_id() yylval.id
#endif

#ifndef RIPPER
#define literal_flush(p) (parser->tokp = (p))
#define dispatch_scan_event(t) ((void)0)
#define dispatch_delayed_token(t) ((void)0)
#define has_delayed_token() (0)
#else
#define literal_flush(p) ((void)0)

#define yylval_rval (*(RB_TYPE_P(yylval.val, T_NODE) ? &yylval.node->nd_rval : &yylval.val))

static inline VALUE
intern_sym(const char *name)
{
    ID id = rb_intern_const(name);
    return ID2SYM(id);
}

static int
ripper_has_scan_event(struct parser_params *parser)
{

    if (lex_p < parser->tokp) rb_raise(rb_eRuntimeError, "lex_p < tokp");
    return lex_p > parser->tokp;
}

static VALUE
ripper_scan_event_val(struct parser_params *parser, int t)
{
    VALUE str = STR_NEW(parser->tokp, lex_p - parser->tokp);
    VALUE rval = ripper_dispatch1(parser, ripper_token2eventid(t), str);
    token_flush(parser);
    return rval;
}

static void
ripper_dispatch_scan_event(struct parser_params *parser, int t)
{
    if (!ripper_has_scan_event(parser)) return;
    add_mark_object(yylval_rval = ripper_scan_event_val(parser, t));
}
#define dispatch_scan_event(t) ripper_dispatch_scan_event(parser, t)

static void
ripper_dispatch_delayed_token(struct parser_params *parser, int t)
{
    int saved_line = ruby_sourceline;
    const char *saved_tokp = parser->tokp;

    ruby_sourceline = parser->delayed_line;
    parser->tokp = lex_pbeg + parser->delayed_col;
    add_mark_object(yylval_rval = ripper_dispatch1(parser, ripper_token2eventid(t), parser->delayed));
    parser->delayed = Qnil;
    ruby_sourceline = saved_line;
    parser->tokp = saved_tokp;
}
#define dispatch_delayed_token(t) ripper_dispatch_delayed_token(parser, t)
#define has_delayed_token() (!NIL_P(parser->delayed))
#endif /* RIPPER */

#include "ruby/regex.h"
#include "ruby/util.h"

#define parser_encoding_name()  (current_enc->name)
#define parser_mbclen()  mbclen((lex_p-1),lex_pend,current_enc)
#define is_identchar(p,e,enc) (rb_enc_isalnum((unsigned char)(*(p)),(enc)) || (*(p)) == '_' || !ISASCII(*(p)))
#define parser_is_identchar() (!parser->eofp && is_identchar((lex_p-1),lex_pend,current_enc))

#define parser_isascii() ISASCII(*(lex_p-1))

static int
token_info_get_column(struct parser_params *parser, const char *pend)
{
    int column = 1;
    const char *p;
    for (p = lex_pbeg; p < pend; p++) {
	if (*p == '\t') {
	    column = (((column - 1) / TAB_WIDTH) + 1) * TAB_WIDTH;
	}
	column++;
    }
    return column;
}

static int
token_info_has_nonspaces(struct parser_params *parser, const char *pend)
{
    const char *p;
    for (p = lex_pbeg; p < pend; p++) {
	if (*p != ' ' && *p != '\t') {
	    return 1;
	}
    }
    return 0;
}

static void
token_info_push_gen(struct parser_params *parser, const char *token, size_t len)
{
    token_info *ptinfo;
    const char *t = lex_p - len;

    if (!parser->token_info_enabled) return;
    ptinfo = ALLOC(token_info);
    ptinfo->token = token;
    ptinfo->linenum = ruby_sourceline;
    ptinfo->column = token_info_get_column(parser, t);
    ptinfo->nonspc = token_info_has_nonspaces(parser, t);
    ptinfo->next = parser->token_info;

    parser->token_info = ptinfo;
}

static void
token_info_pop_gen(struct parser_params *parser, const char *token, size_t len)
{
    int linenum;
    token_info *ptinfo = parser->token_info;
    const char *t = lex_p - len;

    if (!ptinfo) return;
    parser->token_info = ptinfo->next;
    linenum = ruby_sourceline;
    if (parser->token_info_enabled &&
	linenum != ptinfo->linenum && !ptinfo->nonspc &&
	!token_info_has_nonspaces(parser, t) &&
	token_info_get_column(parser, t) != ptinfo->column) {
	rb_warn3L(linenum,
		  "mismatched indentations at '%s' with '%s' at %d",
		  WARN_S(token), WARN_S(ptinfo->token), WARN_I(ptinfo->linenum));
    }

    xfree(ptinfo);
}

static int
parser_precise_mbclen(struct parser_params *parser, const char *p)
{
    int len = rb_enc_precise_mbclen(p, lex_pend, current_enc);
    if (!MBCLEN_CHARFOUND_P(len)) {
	compile_error(PARSER_ARG "invalid multibyte char (%s)", parser_encoding_name());
	return -1;
    }
    return len;
}

static int
parser_yyerror(struct parser_params *parser, const char *msg)
{
#ifndef RIPPER
    const int max_line_margin = 30;
    const char *p, *pe;
    const char *pre = "", *post = "", *pend;
    const char *code = "", *caret = "", *newline = "";
    const char *lim;
    char *buf;
    long len;
    int i;

    pend = lex_pend;
    if (pend > lex_pbeg && pend[-1] == '\n') {
	if (--pend > lex_pbeg && pend[-1] == '\r') --pend;
    }

    p = pe = lex_p < pend ? lex_p : pend;
    lim = p - lex_pbeg > max_line_margin ? p - max_line_margin : lex_pbeg;
    while ((lim < p) && (*(p-1) != '\n')) p--;

    lim = pend - pe > max_line_margin ? pe + max_line_margin : pend;
    while ((pe < lim) && (*pe != '\n')) pe++;

    len = pe - p;
    if (len > 4) {
	char *p2;

	if (p > lex_pbeg) {
	    p = rb_enc_prev_char(lex_pbeg, p, lex_p, rb_enc_get(lex_lastline));
	    if (p > lex_pbeg) pre = "...";
	}
	if (pe < pend) {
	    pe = rb_enc_prev_char(lex_p, pe, pend, rb_enc_get(lex_lastline));
	    if (pe < pend) post = "...";
	}
	len = pe - p;
	lim = lex_p < pend ? lex_p : pend;
	i = (int)(lim - p);
	buf = ALLOCA_N(char, i+2);
	code = p;
	caret = p2 = buf;
	pe = (parser->tokp < lim ? parser->tokp : lim);
	if (p <= pe) {
	    while (p < pe) {
		*p2++ = *p++ == '\t' ? '\t' : ' ';
	    }
	    *p2++ = '^';
	    p++;
	}
	if (lim > p) {
	    memset(p2, '~', (lim - p));
	    p2 += (lim - p);
	}
	*p2 = '\0';
	newline = "\n";
    }
    else {
	len = 0;
    }
    compile_error(PARSER_ARG "%s%s""%s%.*s%s%s""%s%s",
		  msg, newline,
		  pre, (int)len, code, post, newline,
		  pre, caret);
#else
    dispatch1(parse_error, STR_NEW2(msg));
    ripper_error();
#endif /* !RIPPER */
    return 0;
}

static int
vtable_size(const struct vtable *tbl)
{
    if (POINTER_P(tbl)) {
	return tbl->pos;
    }
    else {
	return 0;
    }
}

static struct vtable *
vtable_alloc_gen(struct parser_params *parser, int line, struct vtable *prev)
{
    struct vtable *tbl = ALLOC(struct vtable);
    tbl->pos = 0;
    tbl->capa = 8;
    tbl->tbl = ALLOC_N(ID, tbl->capa);
    tbl->prev = prev;
#ifndef RIPPER
    if (yydebug) {
	rb_parser_printf(parser, "vtable_alloc:%d: %p\n", line, tbl);
    }
#endif
    return tbl;
}
#define vtable_alloc(prev) vtable_alloc_gen(parser, __LINE__, prev)

static void
vtable_free_gen(struct parser_params *parser, int line, const char *name,
		struct vtable *tbl)
{
#ifndef RIPPER
    if (yydebug) {
	rb_parser_printf(parser, "vtable_free:%d: %s(%p)\n", line, name, tbl);
    }
#endif
    if (POINTER_P(tbl)) {
	if (tbl->tbl) {
	    xfree(tbl->tbl);
	}
	xfree(tbl);
    }
}
#define vtable_free(tbl) vtable_free_gen(parser, __LINE__, #tbl, tbl)

static void
vtable_add_gen(struct parser_params *parser, int line, const char *name,
	       struct vtable *tbl, ID id)
{
#ifndef RIPPER
    if (yydebug) {
	rb_parser_printf(parser, "vtable_add:%d: %s(%p), %s\n",
			 line, name, tbl, rb_id2name(id));
    }
#endif
    if (!POINTER_P(tbl)) {
	rb_parser_fatal(parser, "vtable_add: vtable is not allocated (%p)", (void *)tbl);
	return;
    }
    if (tbl->pos == tbl->capa) {
	tbl->capa = tbl->capa * 2;
	REALLOC_N(tbl->tbl, ID, tbl->capa);
    }
    tbl->tbl[tbl->pos++] = id;
}
#define vtable_add(tbl, id) vtable_add_gen(parser, __LINE__, #tbl, tbl, id)

#ifndef RIPPER
static void
vtable_pop_gen(struct parser_params *parser, int line, const char *name,
	       struct vtable *tbl, int n)
{
    if (yydebug) {
	rb_parser_printf(parser, "vtable_pop:%d: %s(%p), %d\n",
			 line, name, tbl, n);
    }
    if (tbl->pos < n) {
	rb_parser_fatal(parser, "vtable_pop: unreachable (%d < %d)", tbl->pos, n);
	return;
    }
    tbl->pos -= n;
}
#define vtable_pop(tbl, n) vtable_pop_gen(parser, __LINE__, #tbl, tbl, n)
#endif

static int
vtable_included(const struct vtable * tbl, ID id)
{
    int i;

    if (POINTER_P(tbl)) {
	for (i = 0; i < tbl->pos; i++) {
	    if (tbl->tbl[i] == id) {
		return i+1;
	    }
	}
    }
    return 0;
}

static void parser_prepare(struct parser_params *parser);

#ifndef RIPPER
static NODE *parser_append_options(struct parser_params *parser, NODE *node);

static VALUE
debug_lines(VALUE fname)
{
    ID script_lines;
    CONST_ID(script_lines, "SCRIPT_LINES__");
    if (rb_const_defined_at(rb_cObject, script_lines)) {
	VALUE hash = rb_const_get_at(rb_cObject, script_lines);
	if (RB_TYPE_P(hash, T_HASH)) {
	    VALUE lines = rb_ary_new();
	    rb_hash_aset(hash, fname, lines);
	    return lines;
	}
    }
    return 0;
}

static VALUE
coverage(VALUE fname, int n)
{
    VALUE coverages = rb_get_coverages();
    if (RTEST(coverages) && RBASIC(coverages)->klass == 0) {
	VALUE coverage = rb_default_coverage(n);
	VALUE lines = RARRAY_AREF(coverage, COVERAGE_INDEX_LINES);

	rb_hash_aset(coverages, fname, coverage);

	return lines == Qnil ? Qfalse : lines;
    }
    return 0;
}

static int
e_option_supplied(struct parser_params *parser)
{
    return strcmp(ruby_sourcefile, "-e") == 0;
}

static VALUE
yycompile0(VALUE arg)
{
    int n;
    NODE *tree;
    struct parser_params *parser = (struct parser_params *)arg;
    VALUE cov = Qfalse;

    if (!compile_for_eval && rb_safe_level() == 0) {
	ruby_debug_lines = debug_lines(ruby_sourcefile_string);
	if (ruby_debug_lines && ruby_sourceline > 0) {
	    VALUE str = STR_NEW0();
	    n = ruby_sourceline;
	    do {
		rb_ary_push(ruby_debug_lines, str);
	    } while (--n);
	}

	if (!e_option_supplied(parser)) {
	    ruby_coverage = coverage(ruby_sourcefile_string, ruby_sourceline);
	    cov = Qtrue;
	}
    }

    parser_prepare(parser);
#ifndef RIPPER
#define RUBY_DTRACE_PARSE_HOOK(name) \
    if (RUBY_DTRACE_PARSE_##name##_ENABLED()) { \
	RUBY_DTRACE_PARSE_##name(ruby_sourcefile, ruby_sourceline); \
    }
    RUBY_DTRACE_PARSE_HOOK(BEGIN);
#endif
    n = yyparse((void*)parser);
#ifndef RIPPER
    RUBY_DTRACE_PARSE_HOOK(END);
#endif
    ruby_debug_lines = 0;
    ruby_coverage = 0;

    lex_strterm = 0;
    lex_p = lex_pbeg = lex_pend = 0;
    lex_prevline = lex_lastline = lex_nextline = 0;
    if (parser->error_p) {
	VALUE mesg = parser->error_buffer;
	if (!mesg) {
	    mesg = rb_class_new_instance(0, 0, rb_eSyntaxError);
	}
	rb_set_errinfo(mesg);
	return 0;
    }
    tree = ruby_eval_tree;
    if (!tree) {
	tree = NEW_NIL();
    }
    else {
	VALUE opt = parser->compile_option;
	NODE *prelude;
	NODE *body = parser_append_options(parser, tree->nd_body);
	if (!opt) opt = rb_obj_hide(rb_ident_hash_new());
	rb_hash_aset(opt, rb_sym_intern_ascii_cstr("coverage_enabled"), cov);
	prelude = NEW_PRELUDE(ruby_eval_tree_begin, body, opt);
	add_mark_object(opt);
	prelude->nd_loc = body->nd_loc;
	tree->nd_body = prelude;
    }
    return (VALUE)tree;
}

static NODE*
yycompile(struct parser_params *parser, VALUE fname, int line)
{
    ruby_sourcefile_string = rb_str_new_frozen(fname);
    ruby_sourcefile = RSTRING_PTR(fname);
    ruby_sourceline = line - 1;
    return (NODE *)rb_suppress_tracing(yycompile0, (VALUE)parser);
}
#endif /* !RIPPER */

static rb_encoding *
must_be_ascii_compatible(VALUE s)
{
    rb_encoding *enc = rb_enc_get(s);
    if (!rb_enc_asciicompat(enc)) {
	rb_raise(rb_eArgError, "invalid source encoding");
    }
    return enc;
}

static VALUE
lex_get_str(struct parser_params *parser, VALUE s)
{
    char *beg, *end, *start;
    long len;

    beg = RSTRING_PTR(s);
    len = RSTRING_LEN(s);
    start = beg;
    if (lex_gets_ptr) {
	if (len == lex_gets_ptr) return Qnil;
	beg += lex_gets_ptr;
	len -= lex_gets_ptr;
    }
    end = memchr(beg, '\n', len);
    if (end) len = ++end - beg;
    lex_gets_ptr += len;
    return rb_str_subseq(s, beg - start, len);
}

static VALUE
lex_getline(struct parser_params *parser)
{
    VALUE line = (*lex_gets)(parser, lex_input);
    if (NIL_P(line)) return line;
    must_be_ascii_compatible(line);
#ifndef RIPPER
    if (ruby_debug_lines) {
	rb_enc_associate(line, current_enc);
	rb_ary_push(ruby_debug_lines, line);
    }
    if (ruby_coverage) {
	rb_ary_push(ruby_coverage, Qnil);
    }
#endif
    return line;
}

static const rb_data_type_t parser_data_type;

#ifndef RIPPER
static rb_ast_t*
parser_compile_string(VALUE vparser, VALUE fname, VALUE s, int line)
{
    struct parser_params *parser;
    rb_ast_t *ast;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, parser);
    parser->ast = ast = rb_ast_new();

    lex_gets = lex_get_str;
    lex_gets_ptr = 0;
    lex_input = rb_str_new_frozen(s);
    lex_pbeg = lex_p = lex_pend = 0;

    ast->root = yycompile(parser, fname, line);
    parser->ast = 0;
    RB_GC_GUARD(vparser); /* prohibit tail call optimization */

    return ast;
}

rb_ast_t*
rb_compile_string(const char *f, VALUE s, int line)
{
    must_be_ascii_compatible(s);
    return parser_compile_string(rb_parser_new(), rb_filesystem_str_new_cstr(f), s, line);
}

rb_ast_t*
rb_parser_compile_string(VALUE vparser, const char *f, VALUE s, int line)
{
    return rb_parser_compile_string_path(vparser, rb_filesystem_str_new_cstr(f), s, line);
}

rb_ast_t*
rb_parser_compile_string_path(VALUE vparser, VALUE f, VALUE s, int line)
{
    must_be_ascii_compatible(s);
    return parser_compile_string(vparser, f, s, line);
}

rb_ast_t*
rb_compile_cstr(const char *f, const char *s, int len, int line)
{
    VALUE str = rb_str_new(s, len);
    return parser_compile_string(rb_parser_new(), rb_filesystem_str_new_cstr(f), str, line);
}

rb_ast_t*
rb_parser_compile_cstr(VALUE vparser, const char *f, const char *s, int len, int line)
{
    VALUE str = rb_str_new(s, len);
    return parser_compile_string(vparser, rb_filesystem_str_new_cstr(f), str, line);
}

VALUE rb_io_gets_internal(VALUE io);

static VALUE
lex_io_gets(struct parser_params *parser, VALUE io)
{
    return rb_io_gets_internal(io);
}

rb_ast_t*
rb_compile_file(const char *f, VALUE file, int start)
{
    VALUE vparser = rb_parser_new();

    return rb_parser_compile_file(vparser, f, file, start);
}

rb_ast_t*
rb_parser_compile_file(VALUE vparser, const char *f, VALUE file, int start)
{
    return rb_parser_compile_file_path(vparser, rb_filesystem_str_new_cstr(f), file, start);
}

rb_ast_t*
rb_parser_compile_file_path(VALUE vparser, VALUE fname, VALUE file, int start)
{
    struct parser_params *parser;
    rb_ast_t *ast;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, parser);
    parser->ast = ast = rb_ast_new();

    lex_gets = lex_io_gets;
    lex_input = file;
    lex_pbeg = lex_p = lex_pend = 0;

    ast->root = yycompile(parser, fname, start);
    parser->ast = 0;
    RB_GC_GUARD(vparser); /* prohibit tail call optimization */

    return ast;
}
#endif  /* !RIPPER */

#define STR_FUNC_ESCAPE 0x01
#define STR_FUNC_EXPAND 0x02
#define STR_FUNC_REGEXP 0x04
#define STR_FUNC_QWORDS 0x08
#define STR_FUNC_SYMBOL 0x10
#define STR_FUNC_INDENT 0x20
#define STR_FUNC_LABEL  0x40
#define STR_FUNC_LIST   0x4000
#define STR_FUNC_TERM   0x8000

enum string_type {
    str_label  = STR_FUNC_LABEL,
    str_squote = (0),
    str_dquote = (STR_FUNC_EXPAND),
    str_xquote = (STR_FUNC_EXPAND),
    str_regexp = (STR_FUNC_REGEXP|STR_FUNC_ESCAPE|STR_FUNC_EXPAND),
    str_sword  = (STR_FUNC_QWORDS|STR_FUNC_LIST),
    str_dword  = (STR_FUNC_QWORDS|STR_FUNC_EXPAND|STR_FUNC_LIST),
    str_ssym   = (STR_FUNC_SYMBOL),
    str_dsym   = (STR_FUNC_SYMBOL|STR_FUNC_EXPAND)
};

static VALUE
parser_str_new(const char *p, long n, rb_encoding *enc, int func, rb_encoding *enc0)
{
    VALUE str;

    str = rb_enc_str_new(p, n, enc);
    if (!(func & STR_FUNC_REGEXP) && rb_enc_asciicompat(enc)) {
	if (rb_enc_str_coderange(str) == ENC_CODERANGE_7BIT) {
	}
	else if (enc0 == rb_usascii_encoding() && enc != rb_utf8_encoding()) {
	    rb_enc_associate(str, rb_ascii8bit_encoding());
	}
    }

    return str;
}

#define lex_goto_eol(parser) ((parser)->lex.pcur = (parser)->lex.pend)
#define lex_eol_p() (lex_p >= lex_pend)
#define peek(c) peek_n((c), 0)
#define peek_n(c,n) (lex_p+(n) < lex_pend && (c) == (unsigned char)lex_p[n])
#define peekc() peekc_n(0)
#define peekc_n(n) (lex_p+(n) < lex_pend ? (unsigned char)lex_p[n] : -1)

#ifdef RIPPER
static void
parser_add_delayed_token(struct parser_params *parser, const char *tok, const char *end)
{
    if (tok < end) {
	if (!has_delayed_token()) {
	    parser->delayed = rb_str_buf_new(1024);
	    rb_enc_associate(parser->delayed, current_enc);
	    parser->delayed_line = ruby_sourceline;
	    parser->delayed_col = (int)(tok - lex_pbeg);
	}
	rb_str_buf_cat(parser->delayed, tok, end - tok);
	parser->tokp = end;
    }
}
#define add_delayed_token(tok, end) parser_add_delayed_token(parser, (tok), (end))
#else
#define add_delayed_token(tok, end) ((void)(tok), (void)(end))
#endif

static int
parser_nextline(struct parser_params *parser)
{
    VALUE v = lex_nextline;
    lex_nextline = 0;
    if (!v) {
	if (parser->eofp)
	    return -1;

	if (!lex_input || NIL_P(v = lex_getline(parser))) {
	    parser->eofp = 1;
	    lex_goto_eol(parser);
	    return -1;
	}
	parser->cr_seen = FALSE;
    }
    add_delayed_token(parser->tokp, lex_pend);
    if (heredoc_end > 0) {
	ruby_sourceline = heredoc_end;
	heredoc_end = 0;
    }
    ruby_sourceline++;
    parser->line_count++;
    lex_pbeg = lex_p = RSTRING_PTR(v);
    lex_pend = lex_p + RSTRING_LEN(v);
    token_flush(parser);
    lex_prevline = lex_lastline;
    lex_lastline = v;
    return 0;
}

static int
parser_cr(struct parser_params *parser, int c)
{
    if (peek('\n')) {
	lex_p++;
	c = '\n';
    }
    else if (!parser->cr_seen) {
	parser->cr_seen = TRUE;
	/* carried over with lex_nextline for nextc() */
	rb_warn0("encountered \\r in middle of line, treated as a mere space");
    }
    return c;
}

static inline int
parser_nextc(struct parser_params *parser)
{
    int c;

    if (UNLIKELY((lex_p == lex_pend) || parser->eofp || lex_nextline)) {
	if (parser_nextline(parser)) return -1;
    }
    c = (unsigned char)*lex_p++;
    if (UNLIKELY(c == '\r')) {
	c = parser_cr(parser, c);
    }

    return c;
}

static void
parser_pushback(struct parser_params *parser, int c)
{
    if (c == -1) return;
    lex_p--;
    if (lex_p > lex_pbeg && lex_p[0] == '\n' && lex_p[-1] == '\r') {
	lex_p--;
    }
}

#define was_bol() (lex_p == lex_pbeg + 1)

#define tokfix() (tokenbuf[tokidx]='\0')
#define tok() tokenbuf
#define toklen() tokidx
#define toklast() (tokidx>0?tokenbuf[tokidx-1]:0)

static char*
parser_newtok(struct parser_params *parser)
{
    tokidx = 0;
    tokline = ruby_sourceline;
    if (!tokenbuf) {
	toksiz = 60;
	tokenbuf = ALLOC_N(char, 60);
    }
    if (toksiz > 4096) {
	toksiz = 60;
	REALLOC_N(tokenbuf, char, 60);
    }
    return tokenbuf;
}

static char *
parser_tokspace(struct parser_params *parser, int n)
{
    tokidx += n;

    if (tokidx >= toksiz) {
	do {toksiz *= 2;} while (toksiz < tokidx);
	REALLOC_N(tokenbuf, char, toksiz);
    }
    return &tokenbuf[tokidx-n];
}

static void
parser_tokadd(struct parser_params *parser, int c)
{
    tokenbuf[tokidx++] = (char)c;
    if (tokidx >= toksiz) {
	toksiz *= 2;
	REALLOC_N(tokenbuf, char, toksiz);
    }
}

static int
parser_tok_hex(struct parser_params *parser, size_t *numlen)
{
    int c;

    c = scan_hex(lex_p, 2, numlen);
    if (!*numlen) {
	parser->tokp = lex_p;
	yyerror0("invalid hex escape");
	return 0;
    }
    lex_p += *numlen;
    return c;
}

#define tokcopy(n) memcpy(tokspace(n), lex_p - (n), (n))

static int
parser_tokadd_codepoint(struct parser_params *parser, rb_encoding **encp,
			int regexp_literal, int wide)
{
    size_t numlen;
    int codepoint = scan_hex(lex_p, wide ? lex_pend - lex_p : 4, &numlen);
    literal_flush(lex_p);
    lex_p += numlen;
    if (wide ? (numlen == 0 || numlen > 6) : (numlen < 4))  {
	yyerror0("invalid Unicode escape");
	return wide && numlen > 0;
    }
    if (codepoint > 0x10ffff) {
	yyerror0("invalid Unicode codepoint (too large)");
	return wide;
    }
    if ((codepoint & 0xfffff800) == 0xd800) {
	yyerror0("invalid Unicode codepoint");
	return wide;
    }
    if (regexp_literal) {
	tokcopy((int)numlen);
    }
    else if (codepoint >= 0x80) {
	rb_encoding *utf8 = rb_utf8_encoding();
	if (*encp && utf8 != *encp) {
	    static const char mixed_utf8[] = "UTF-8 mixed within %s source";
	    size_t len = sizeof(mixed_utf8) - 2 + strlen(rb_enc_name(*encp));
	    char *mesg = alloca(len);
	    snprintf(mesg, len, mixed_utf8, rb_enc_name(*encp));
	    yyerror0(mesg);
	    return wide;
	}
	*encp = utf8;
	tokaddmbc(codepoint, *encp);
    }
    else {
	tokadd(codepoint);
    }
    return TRUE;
}

/* return value is for ?\u3042 */
static int
parser_tokadd_utf8(struct parser_params *parser, rb_encoding **encp,
		   int string_literal, int symbol_literal, int regexp_literal)
{
    /*
     * If string_literal is true, then we allow multiple codepoints
     * in \u{}, and add the codepoints to the current token.
     * Otherwise we're parsing a character literal and return a single
     * codepoint without adding it
     */

    const int open_brace = '{', close_brace = '}';

    if (regexp_literal) { tokadd('\\'); tokadd('u'); }

    if (peek(open_brace)) {  /* handle \u{...} form */
	int c, last = nextc();
	if (lex_p >= lex_pend) goto unterminated;
	while (ISSPACE(c = *lex_p) && ++lex_p < lex_pend);
	while (c != close_brace) {
	    if (regexp_literal) tokadd(last);
	    if (!parser_tokadd_codepoint(parser, encp, regexp_literal, TRUE)) {
		break;
	    }
	    while (ISSPACE(c = *lex_p)) {
		if (++lex_p >= lex_pend) goto unterminated;
		last = c;
	    }
	}

	if (c != close_brace) {
	  unterminated:
	    literal_flush(lex_p);
	    yyerror0("unterminated Unicode escape");
	    return 0;
	}

	if (regexp_literal) tokadd(close_brace);
	nextc();
    }
    else {			/* handle \uxxxx form */
	if (!parser_tokadd_codepoint(parser, encp, regexp_literal, FALSE)) {
	    return 0;
	}
    }

    return TRUE;
}

#define ESCAPE_CONTROL 1
#define ESCAPE_META    2

static int
parser_read_escape(struct parser_params *parser, int flags,
		   rb_encoding **encp)
{
    int c;
    size_t numlen;

    switch (c = nextc()) {
      case '\\':	/* Backslash */
	return c;

      case 'n':	/* newline */
	return '\n';

      case 't':	/* horizontal tab */
	return '\t';

      case 'r':	/* carriage-return */
	return '\r';

      case 'f':	/* form-feed */
	return '\f';

      case 'v':	/* vertical tab */
	return '\13';

      case 'a':	/* alarm(bell) */
	return '\007';

      case 'e':	/* escape */
	return 033;

      case '0': case '1': case '2': case '3': /* octal constant */
      case '4': case '5': case '6': case '7':
	pushback(c);
	c = scan_oct(lex_p, 3, &numlen);
	lex_p += numlen;
	return c;

      case 'x':	/* hex constant */
	c = tok_hex(&numlen);
	if (numlen == 0) return 0;
	return c;

      case 'b':	/* backspace */
	return '\010';

      case 's':	/* space */
	return ' ';

      case 'M':
	if (flags & ESCAPE_META) goto eof;
	if ((c = nextc()) != '-') {
	    goto eof;
	}
	if ((c = nextc()) == '\\') {
	    if (peek('u')) goto eof;
	    return read_escape(flags|ESCAPE_META, encp) | 0x80;
	}
	else if (c == -1 || !ISASCII(c)) goto eof;
	else {
	    return ((c & 0xff) | 0x80);
	}

      case 'C':
	if ((c = nextc()) != '-') {
	    goto eof;
	}
      case 'c':
	if (flags & ESCAPE_CONTROL) goto eof;
	if ((c = nextc())== '\\') {
	    if (peek('u')) goto eof;
	    c = read_escape(flags|ESCAPE_CONTROL, encp);
	}
	else if (c == '?')
	    return 0177;
	else if (c == -1 || !ISASCII(c)) goto eof;
	return c & 0x9f;

      eof:
      case -1:
        yyerror0("Invalid escape character syntax");
	pushback(c);
	return '\0';

      default:
	return c;
    }
}

static void
parser_tokaddmbc(struct parser_params *parser, int c, rb_encoding *enc)
{
    int len = rb_enc_codelen(c, enc);
    rb_enc_mbcput(c, tokspace(len), enc);
}

static int
parser_tokadd_escape(struct parser_params *parser, rb_encoding **encp)
{
    int c;
    int flags = 0;
    size_t numlen;

  first:
    switch (c = nextc()) {
      case '\n':
	return 0;		/* just ignore */

      case '0': case '1': case '2': case '3': /* octal constant */
      case '4': case '5': case '6': case '7':
	{
	    ruby_scan_oct(--lex_p, 3, &numlen);
	    if (numlen == 0) goto eof;
	    lex_p += numlen;
	    tokcopy((int)numlen + 1);
	}
	return 0;

      case 'x':	/* hex constant */
	{
	    tok_hex(&numlen);
	    if (numlen == 0) return -1;
	    tokcopy((int)numlen + 2);
	}
	return 0;

      case 'M':
	if (flags & ESCAPE_META) goto eof;
	if ((c = nextc()) != '-') {
	    pushback(c);
	    goto eof;
	}
	tokcopy(3);
	flags |= ESCAPE_META;
	goto escaped;

      case 'C':
	if (flags & ESCAPE_CONTROL) goto eof;
	if ((c = nextc()) != '-') {
	    pushback(c);
	    goto eof;
	}
	tokcopy(3);
	goto escaped;

      case 'c':
	if (flags & ESCAPE_CONTROL) goto eof;
	tokcopy(2);
	flags |= ESCAPE_CONTROL;
      escaped:
	if ((c = nextc()) == '\\') {
	    goto first;
	}
	else if (c == -1) goto eof;
	tokadd(c);
	return 0;

      eof:
      case -1:
        yyerror0("Invalid escape character syntax");
	return -1;

      default:
        tokadd('\\');
	tokadd(c);
    }
    return 0;
}

static int
parser_regx_options(struct parser_params *parser)
{
    int kcode = 0;
    int kopt = 0;
    int options = 0;
    int c, opt, kc;

    newtok();
    while (c = nextc(), ISALPHA(c)) {
        if (c == 'o') {
            options |= RE_OPTION_ONCE;
        }
        else if (rb_char_to_option_kcode(c, &opt, &kc)) {
	    if (kc >= 0) {
		if (kc != rb_ascii8bit_encindex()) kcode = c;
		kopt = opt;
	    }
	    else {
		options |= opt;
	    }
        }
        else {
	    tokadd(c);
        }
    }
    options |= kopt;
    pushback(c);
    if (toklen()) {
	tokfix();
	compile_error(PARSER_ARG "unknown regexp option%s - %s",
		      toklen() > 1 ? "s" : "", tok());
    }
    return options | RE_OPTION_ENCODING(kcode);
}

static void
dispose_string(struct parser_params *parser, VALUE str)
{
    rb_ast_delete_mark_object(parser->ast, str);
    rb_str_free(str);
    rb_gc_force_recycle(str);
}

static int
parser_tokadd_mbchar(struct parser_params *parser, int c)
{
    int len = parser_precise_mbclen(parser, lex_p-1);
    if (len < 0) return -1;
    tokadd(c);
    lex_p += --len;
    if (len > 0) tokcopy(len);
    return c;
}

#define tokadd_mbchar(c) parser_tokadd_mbchar(parser, (c))

static inline int
simple_re_meta(int c)
{
    switch (c) {
      case '$': case '*': case '+': case '.':
      case '?': case '^': case '|':
      case ')': case ']': case '}': case '>':
	return TRUE;
      default:
	return FALSE;
    }
}

static int
parser_update_heredoc_indent(struct parser_params *parser, int c)
{
    if (heredoc_line_indent == -1) {
	if (c == '\n') heredoc_line_indent = 0;
    }
    else {
	if (c == ' ') {
	    heredoc_line_indent++;
	    return TRUE;
	}
	else if (c == '\t') {
	    int w = (heredoc_line_indent / TAB_WIDTH) + 1;
	    heredoc_line_indent = w * TAB_WIDTH;
	    return TRUE;
	}
	else if (c != '\n') {
	    if (heredoc_indent > heredoc_line_indent) {
		heredoc_indent = heredoc_line_indent;
	    }
	    heredoc_line_indent = -1;
	}
    }
    return FALSE;
}

static int
parser_tokadd_string(struct parser_params *parser,
		     int func, int term, int paren, long *nest,
		     rb_encoding **encp)
{
    int c;
    rb_encoding *enc = 0;
    char *errbuf = 0;
    static const char mixed_msg[] = "%s mixed within %s source";

#define mixed_error(enc1, enc2) if (!errbuf) {	\
	size_t len = sizeof(mixed_msg) - 4;	\
	len += strlen(rb_enc_name(enc1));	\
	len += strlen(rb_enc_name(enc2));	\
	errbuf = ALLOCA_N(char, len);		\
	snprintf(errbuf, len, mixed_msg,	\
		 rb_enc_name(enc1),		\
		 rb_enc_name(enc2));		\
	yyerror0(errbuf);			\
    }
#define mixed_escape(beg, enc1, enc2) do {	\
	const char *pos = lex_p;		\
	lex_p = (beg);				\
	mixed_error((enc1), (enc2));		\
	lex_p = pos;				\
    } while (0)

    while ((c = nextc()) != -1) {
	if (heredoc_indent > 0) {
	    parser_update_heredoc_indent(parser, c);
	}

	if (paren && c == paren) {
	    ++*nest;
	}
	else if (c == term) {
	    if (!nest || !*nest) {
		pushback(c);
		break;
	    }
	    --*nest;
	}
	else if ((func & STR_FUNC_EXPAND) && c == '#' && lex_p < lex_pend) {
	    int c2 = *lex_p;
	    if (c2 == '$' || c2 == '@' || c2 == '{') {
		pushback(c);
		break;
	    }
	}
	else if (c == '\\') {
	    literal_flush(lex_p - 1);
	    c = nextc();
	    switch (c) {
	      case '\n':
		if (func & STR_FUNC_QWORDS) break;
		if (func & STR_FUNC_EXPAND) continue;
		tokadd('\\');
		break;

	      case '\\':
		if (func & STR_FUNC_ESCAPE) tokadd(c);
		break;

	      case 'u':
		if ((func & STR_FUNC_EXPAND) == 0) {
		    tokadd('\\');
		    break;
		}
		if (!parser_tokadd_utf8(parser, &enc, term,
					func & STR_FUNC_SYMBOL,
					func & STR_FUNC_REGEXP)) {
		    return -1;
		}
		continue;

	      default:
		if (c == -1) return -1;
		if (!ISASCII(c)) {
		    if ((func & STR_FUNC_EXPAND) == 0) tokadd('\\');
		    goto non_ascii;
		}
		if (func & STR_FUNC_REGEXP) {
		    if (c == term && !simple_re_meta(c)) {
			tokadd(c);
			continue;
		    }
		    pushback(c);
		    if ((c = tokadd_escape(&enc)) < 0)
			return -1;
		    if (enc && enc != *encp) {
			mixed_escape(parser->tokp+2, enc, *encp);
		    }
		    continue;
		}
		else if (func & STR_FUNC_EXPAND) {
		    pushback(c);
		    if (func & STR_FUNC_ESCAPE) tokadd('\\');
		    c = read_escape(0, &enc);
		}
		else if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
		    /* ignore backslashed spaces in %w */
		}
		else if (c != term && !(paren && c == paren)) {
		    tokadd('\\');
		    pushback(c);
		    continue;
		}
	    }
	}
	else if (!parser_isascii()) {
	  non_ascii:
	    if (!enc) {
		enc = *encp;
	    }
	    else if (enc != *encp) {
		mixed_error(enc, *encp);
		continue;
	    }
	    if (tokadd_mbchar(c) == -1) return -1;
	    continue;
	}
	else if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
	    pushback(c);
	    break;
	}
        if (c & 0x80) {
	    if (!enc) {
		enc = *encp;
	    }
	    else if (enc != *encp) {
		mixed_error(enc, *encp);
		continue;
	    }
        }
	tokadd(c);
    }
    if (enc) *encp = enc;
    return c;
}

/* imemo_parser_strterm for literal */
#define NEW_STRTERM(func, term, paren) \
	(rb_strterm_t*)rb_imemo_new(imemo_parser_strterm, (VALUE)(func), (VALUE)(paren), (VALUE)(term), 0)

#ifdef RIPPER
static void
token_flush_string_content(struct parser_params *parser, rb_encoding *enc)
{
    VALUE content = yylval.val;
    if (!ripper_is_node_yylval(content))
	content = ripper_new_yylval(0, 0, content);
    if (has_delayed_token()) {
	ptrdiff_t len = lex_p - parser->tokp;
	if (len > 0) {
	    rb_enc_str_buf_cat(parser->delayed, parser->tokp, len, enc);
	}
	dispatch_delayed_token(tSTRING_CONTENT);
	parser->tokp = lex_p;
	RNODE(content)->nd_rval = yylval.val;
    }
    dispatch_scan_event(tSTRING_CONTENT);
    if (yylval.val != content)
	RNODE(content)->nd_rval = yylval.val;
    yylval.val = content;
}

#define flush_string_content(enc) token_flush_string_content(parser, (enc))
#else
#define flush_string_content(enc) ((void)(enc))
#endif

RUBY_FUNC_EXPORTED const unsigned int ruby_global_name_punct_bits[(0x7e - 0x20 + 31) / 32];
/* this can be shared with ripper, since it's independent from struct
 * parser_params. */
#ifndef RIPPER
#define BIT(c, idx) (((c) / 32 - 1 == idx) ? (1U << ((c) % 32)) : 0)
#define SPECIAL_PUNCT(idx) ( \
	BIT('~', idx) | BIT('*', idx) | BIT('$', idx) | BIT('?', idx) | \
	BIT('!', idx) | BIT('@', idx) | BIT('/', idx) | BIT('\\', idx) | \
	BIT(';', idx) | BIT(',', idx) | BIT('.', idx) | BIT('=', idx) | \
	BIT(':', idx) | BIT('<', idx) | BIT('>', idx) | BIT('\"', idx) | \
	BIT('&', idx) | BIT('`', idx) | BIT('\'', idx) | BIT('+', idx) | \
	BIT('0', idx))
const unsigned int ruby_global_name_punct_bits[] = {
    SPECIAL_PUNCT(0),
    SPECIAL_PUNCT(1),
    SPECIAL_PUNCT(2),
};
#undef BIT
#undef SPECIAL_PUNCT
#endif

static enum yytokentype
parser_peek_variable_name(struct parser_params *parser)
{
    int c;
    const char *p = lex_p;

    if (p + 1 >= lex_pend) return 0;
    c = *p++;
    switch (c) {
      case '$':
	if ((c = *p) == '-') {
	    if (++p >= lex_pend) return 0;
	    c = *p;
	}
	else if (is_global_name_punct(c) || ISDIGIT(c)) {
	    return tSTRING_DVAR;
	}
	break;
      case '@':
	if ((c = *p) == '@') {
	    if (++p >= lex_pend) return 0;
	    c = *p;
	}
	break;
      case '{':
	lex_p = p;
	command_start = TRUE;
	return tSTRING_DBEG;
      default:
	return 0;
    }
    if (!ISASCII(c) || c == '_' || ISALPHA(c))
	return tSTRING_DVAR;
    return 0;
}

#define IS_ARG() IS_lex_state(EXPR_ARG_ANY)
#define IS_END() IS_lex_state(EXPR_END_ANY)
#define IS_BEG() (IS_lex_state(EXPR_BEG_ANY) || IS_lex_state_all(EXPR_ARG|EXPR_LABELED))
#define IS_SPCARG(c) (IS_ARG() && space_seen && !ISSPACE(c))
#define IS_LABEL_POSSIBLE() (\
	(IS_lex_state(EXPR_LABEL|EXPR_ENDFN) && !cmd_state) || \
	IS_ARG())
#define IS_LABEL_SUFFIX(n) (peek_n(':',(n)) && !peek_n(':', (n)+1))
#define IS_AFTER_OPERATOR() IS_lex_state(EXPR_FNAME | EXPR_DOT)

static inline enum yytokentype
parser_string_term(struct parser_params *parser, int func)
{
    lex_strterm = 0;
    if (func & STR_FUNC_REGEXP) {
	set_yylval_num(regx_options());
	dispatch_scan_event(tREGEXP_END);
	SET_LEX_STATE(EXPR_END|EXPR_ENDARG);
	return tREGEXP_END;
    }
    if ((func & STR_FUNC_LABEL) && IS_LABEL_SUFFIX(0)) {
	nextc();
	SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
	return tLABEL_END;
    }
    SET_LEX_STATE(EXPR_END|EXPR_ENDARG);
    return tSTRING_END;
}

static enum yytokentype
parser_parse_string(struct parser_params *parser, rb_strterm_literal_t *quote)
{
    int func = (int)quote->u1.func;
    int term = (int)quote->u3.term;
    int paren = (int)quote->u2.paren;
    int c, space = 0;
    rb_encoding *enc = current_enc;
    VALUE lit;

    if (func & STR_FUNC_TERM) {
	if (func & STR_FUNC_QWORDS) nextc(); /* delayed term */
	SET_LEX_STATE(EXPR_END|EXPR_ENDARG);
	lex_strterm = 0;
	return func & STR_FUNC_REGEXP ? tREGEXP_END : tSTRING_END;
    }
    c = nextc();
    if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
	do {c = nextc();} while (ISSPACE(c));
	space = 1;
    }
    if (func & STR_FUNC_LIST) {
	quote->u1.func &= ~STR_FUNC_LIST;
	space = 1;
    }
    if (c == term && !quote->u0.nest) {
	if (func & STR_FUNC_QWORDS) {
	    quote->u1.func |= STR_FUNC_TERM;
	    pushback(c); /* dispatch the term at tSTRING_END */
	    add_delayed_token(parser->tokp, lex_p);
	    return ' ';
	}
	return parser_string_term(parser, func);
    }
    if (space) {
	pushback(c);
	add_delayed_token(parser->tokp, lex_p);
	return ' ';
    }
    newtok();
    if ((func & STR_FUNC_EXPAND) && c == '#') {
	int t = parser_peek_variable_name(parser);
	if (t) return t;
	tokadd('#');
	c = nextc();
    }
    pushback(c);
    if (tokadd_string(func, term, paren, &quote->u0.nest,
		      &enc) == -1) {
	if (parser->eofp) {
#ifndef RIPPER
# define unterminated_literal(mesg) yyerror0(mesg)
#else
# define unterminated_literal(mesg) compile_error(PARSER_ARG  mesg)
#endif
	    literal_flush(lex_p);
	    if (func & STR_FUNC_REGEXP) {
		unterminated_literal("unterminated regexp meets end of file");
	    }
	    else {
		unterminated_literal("unterminated string meets end of file");
	    }
	    quote->u1.func |= STR_FUNC_TERM;
	}
    }

    tokfix();
    add_mark_object(lit = STR_NEW3(tok(), toklen(), enc, func));
    set_yylval_str(lit);
    flush_string_content(enc);

    return tSTRING_CONTENT;
}

static enum yytokentype
parser_heredoc_identifier(struct parser_params *parser)
{
    int c = nextc(), term, func = 0, term_len = 2; /* length of "<<" */
    enum yytokentype token = tSTRING_BEG;
    long len;
    int newline = 0;
    int indent = 0;

    if (c == '-') {
	c = nextc();
	term_len++;
	func = STR_FUNC_INDENT;
    }
    else if (c == '~') {
	c = nextc();
	term_len++;
	func = STR_FUNC_INDENT;
	indent = INT_MAX;
    }
    switch (c) {
      case '\'':
	term_len++;
	func |= str_squote; goto quoted;
      case '"':
	term_len++;
	func |= str_dquote; goto quoted;
      case '`':
	term_len++;
	token = tXSTRING_BEG;
	func |= str_xquote; goto quoted;

      quoted:
	term_len++;
	newtok();
	tokadd(term_len);
	tokadd(func);
	term = c;
	while ((c = nextc()) != -1 && c != term) {
	    if (tokadd_mbchar(c) == -1) return 0;
	    if (!newline && c == '\n') newline = 1;
	    else if (newline) newline = 2;
	}
	if (c == -1) {
	    compile_error(PARSER_ARG "unterminated here document identifier");
	    return 0;
	}
	switch (newline) {
	  case 1:
	    rb_warn0("here document identifier ends with a newline");
	    if (--tokidx > 0 && tokenbuf[tokidx] == '\r') --tokidx;
	    break;
	  case 2:
	    compile_error(PARSER_ARG "here document identifier across newlines, never match");
	    return -1;
	}
	break;

      default:
	if (!parser_is_identchar()) {
	    pushback(c);
	    if (func & STR_FUNC_INDENT) {
		pushback(indent > 0 ? '~' : '-');
	    }
	    return 0;
	}
	newtok();
	tokadd(term_len);
	tokadd(func |= str_dquote);
	do {
	    if (tokadd_mbchar(c) == -1) return 0;
	} while ((c = nextc()) != -1 && parser_is_identchar());
	pushback(c);
	break;
    }

    tokenbuf[0] = tokenbuf[0] + toklen() - 2;
    tokfix();
    dispatch_scan_event(tHEREDOC_BEG);
    len = lex_p - lex_pbeg;
    lex_goto_eol(parser);

    lex_strterm = (rb_strterm_t*)rb_imemo_new(imemo_parser_strterm,
					      STR_NEW(tok(), toklen()),	/* term */
					      lex_lastline,		/* lastline */
					      len,			/* lastidx */
					      ruby_sourceline);
    lex_strterm->flags |= STRTERM_HEREDOC;

    token_flush(parser);
    heredoc_indent = indent;
    heredoc_line_indent = 0;
    return token;
}

static void
parser_heredoc_restore(struct parser_params *parser, rb_strterm_heredoc_t *here)
{
    VALUE line;

    lex_strterm = 0;
    line = here->lastline;
    lex_lastline = line;
    lex_pbeg = RSTRING_PTR(line);
    lex_pend = lex_pbeg + RSTRING_LEN(line);
    lex_p = lex_pbeg + here->u3.lastidx;
    heredoc_end = ruby_sourceline;
    ruby_sourceline = (int)here->sourceline;
    token_flush(parser);
}

static int
dedent_string(VALUE string, int width)
{
    char *str;
    long len;
    int i, col = 0;

    RSTRING_GETMEM(string, str, len);
    for (i = 0; i < len && col < width; i++) {
	if (str[i] == ' ') {
	    col++;
	}
	else if (str[i] == '\t') {
	    int n = TAB_WIDTH * (col / TAB_WIDTH + 1);
	    if (n > width) break;
	    col = n;
	}
	else {
	    break;
	}
    }
    if (!i) return 0;
    rb_str_modify(string);
    str = RSTRING_PTR(string);
    if (RSTRING_LEN(string) != len)
	rb_fatal("literal string changed: %+"PRIsVALUE, string);
    MEMMOVE(str, str + i, char, len - i);
    rb_str_set_len(string, len - i);
    return i;
}

#ifndef RIPPER
static NODE *
parser_heredoc_dedent(struct parser_params *parser, NODE *root)
{
    NODE *node, *str_node;
    int bol = TRUE;
    int indent = heredoc_indent;

    if (indent <= 0) return root;
    heredoc_indent = 0;
    if (!root) return root;

    node = str_node = root;
    if (nd_type(root) == NODE_ARRAY) str_node = root->nd_head;

    while (str_node) {
	VALUE lit = str_node->nd_lit;
	if (bol) dedent_string(lit, indent);
	bol = TRUE;

	str_node = 0;
	while ((node = node->nd_next) != 0 && nd_type(node) == NODE_ARRAY) {
	    if ((str_node = node->nd_head) != 0) {
		enum node_type type = nd_type(str_node);
		if (type == NODE_STR || type == NODE_DSTR) break;
		bol = FALSE;
		str_node = 0;
	    }
	}
    }
    return root;
}
#else /* RIPPER */
static VALUE
parser_heredoc_dedent(struct parser_params *parser, VALUE array)
{
    int indent = heredoc_indent;

    if (indent <= 0) return array;
    heredoc_indent = 0;
    dispatch2(heredoc_dedent, array, INT2NUM(indent));
    return array;
}

static VALUE
parser_dedent_string(VALUE self, VALUE input, VALUE width)
{
    int wid, col;

    StringValue(input);
    wid = NUM2UINT(width);
    col = dedent_string(input, wid);
    return INT2NUM(col);
}
#endif

static int
parser_whole_match_p(struct parser_params *parser,
    const char *eos, long len, int indent)
{
    const char *p = lex_pbeg;
    long n;

    if (indent) {
	while (*p && ISSPACE(*p)) p++;
    }
    n = lex_pend - (p + len);
    if (n < 0) return FALSE;
    if (n > 0 && p[len] != '\n') {
	if (p[len] != '\r') return FALSE;
	if (n <= 1 || p[len+1] != '\n') return FALSE;
    }
    return strncmp(eos, p, len) == 0;
}

#define NUM_SUFFIX_R   (1<<0)
#define NUM_SUFFIX_I   (1<<1)
#define NUM_SUFFIX_ALL 3

static int
parser_number_literal_suffix(struct parser_params *parser, int mask)
{
    int c, result = 0;
    const char *lastp = lex_p;

    while ((c = nextc()) != -1) {
	if ((mask & NUM_SUFFIX_I) && c == 'i') {
	    result |= (mask & NUM_SUFFIX_I);
	    mask &= ~NUM_SUFFIX_I;
	    /* r after i, rational of complex is disallowed */
	    mask &= ~NUM_SUFFIX_R;
	    continue;
	}
	if ((mask & NUM_SUFFIX_R) && c == 'r') {
	    result |= (mask & NUM_SUFFIX_R);
	    mask &= ~NUM_SUFFIX_R;
	    continue;
	}
	if (!ISASCII(c) || ISALPHA(c) || c == '_') {
	    lex_p = lastp;
	    literal_flush(lex_p);
	    return 0;
	}
	pushback(c);
	if (c == '.') {
	    c = peekc_n(1);
	    if (ISDIGIT(c)) {
		yyerror0("unexpected fraction part after numeric literal");
		lex_p += 2;
		while (parser_is_identchar()) nextc();
	    }
	}
	break;
    }
    return result;
}

static enum yytokentype
parser_set_number_literal(struct parser_params *parser, VALUE v,
			  enum yytokentype type, int suffix)
{
    if (suffix & NUM_SUFFIX_I) {
	v = rb_complex_raw(INT2FIX(0), v);
	type = tIMAGINARY;
    }
    set_yylval_literal(v);
    add_mark_object(v);
    SET_LEX_STATE(EXPR_END|EXPR_ENDARG);
    return type;
}

static int
parser_set_integer_literal(struct parser_params *parser, VALUE v, int suffix)
{
    enum yytokentype type = tINTEGER;
    if (suffix & NUM_SUFFIX_R) {
	v = rb_rational_raw1(v);
	type = tRATIONAL;
    }
    return set_number_literal(v, type, suffix);
}

#ifdef RIPPER
static void
ripper_dispatch_heredoc_end(struct parser_params *parser)
{
    VALUE str;
    if (has_delayed_token())
	dispatch_delayed_token(tSTRING_CONTENT);
    str = STR_NEW(parser->tokp, lex_pend - parser->tokp);
    ripper_dispatch1(parser, ripper_token2eventid(tHEREDOC_END), str);
    lex_goto_eol(parser);
    token_flush(parser);
}

#define dispatch_heredoc_end() ripper_dispatch_heredoc_end(parser)
#else
#define dispatch_heredoc_end() ((void)0)
#endif

static enum yytokentype
parser_here_document(struct parser_params *parser, rb_strterm_heredoc_t *here)
{
    int c, func, indent = 0;
    const char *eos, *p, *pend;
    long len;
    VALUE str = 0;
    rb_encoding *enc = current_enc;

    eos = RSTRING_PTR(here->term);
    len = RSTRING_LEN(here->term) - 2; /* here->term includes term_len and func */
    eos++; /* skip term_len */
    indent = (func = *eos++) & STR_FUNC_INDENT;

    if ((c = nextc()) == -1) {
      error:
	compile_error(PARSER_ARG "can't find string \"%s\" anywhere before EOF", eos);
#ifdef RIPPER
	if (!has_delayed_token()) {
	    dispatch_scan_event(tSTRING_CONTENT);
	}
	else {
	    if (str) {
		rb_str_append(parser->delayed, str);
	    }
	    else if ((len = lex_p - parser->tokp) > 0) {
		if (!(func & STR_FUNC_REGEXP) && rb_enc_asciicompat(enc)) {
		    int cr = ENC_CODERANGE_UNKNOWN;
		    rb_str_coderange_scan_restartable(parser->tokp, lex_p, enc, &cr);
		    if (cr != ENC_CODERANGE_7BIT &&
			current_enc == rb_usascii_encoding() &&
			enc != rb_utf8_encoding()) {
			enc = rb_ascii8bit_encoding();
		    }
		}
		rb_enc_str_buf_cat(parser->delayed, parser->tokp, len, enc);
	    }
	    dispatch_delayed_token(tSTRING_CONTENT);
	}
	lex_goto_eol(parser);
#endif
      restore:
	heredoc_restore(&lex_strterm->u.heredoc);
	lex_strterm = 0;
	return 0;
    }
    if (was_bol() && whole_match_p(eos, len, indent)) {
	dispatch_heredoc_end();
	heredoc_restore(&lex_strterm->u.heredoc);
	lex_strterm = 0;
	SET_LEX_STATE(EXPR_END);
	return tSTRING_END;
    }

    if (!(func & STR_FUNC_EXPAND)) {
	do {
	    p = RSTRING_PTR(lex_lastline);
	    pend = lex_pend;
	    if (pend > p) {
		switch (pend[-1]) {
		  case '\n':
		    if (--pend == p || pend[-1] != '\r') {
			pend++;
			break;
		    }
		  case '\r':
		    --pend;
		}
	    }

	    if (heredoc_indent > 0) {
		long i = 0;
		while (p + i < pend && parser_update_heredoc_indent(parser, p[i]))
		    i++;
		heredoc_line_indent = 0;
	    }

	    if (str)
		rb_str_cat(str, p, pend - p);
	    else
		str = STR_NEW(p, pend - p);
	    if (pend < lex_pend) rb_str_cat(str, "\n", 1);
	    lex_goto_eol(parser);
	    if (heredoc_indent > 0) {
		set_yylval_str(str);
		add_mark_object(str);
		flush_string_content(enc);
		return tSTRING_CONTENT;
	    }
	    if (nextc() == -1) {
		if (str) {
		    dispose_string(parser, str);
		    str = 0;
		}
		goto error;
	    }
	} while (!whole_match_p(eos, len, indent));
    }
    else {
	/*	int mb = ENC_CODERANGE_7BIT, *mbp = &mb;*/
	newtok();
	if (c == '#') {
	    int t = parser_peek_variable_name(parser);
	    if (heredoc_line_indent != -1) {
		if (heredoc_indent > heredoc_line_indent) {
		    heredoc_indent = heredoc_line_indent;
		}
		heredoc_line_indent = -1;
	    }
	    if (t) return t;
	    tokadd('#');
	    c = nextc();
	}
	do {
	    pushback(c);
	    if ((c = tokadd_string(func, '\n', 0, NULL, &enc)) == -1) {
		if (parser->eofp) goto error;
		goto restore;
	    }
	    if (c != '\n') {
		VALUE lit;
	      flush:
		add_mark_object(lit = STR_NEW3(tok(), toklen(), enc, func));
		set_yylval_str(lit);
		flush_string_content(enc);
		return tSTRING_CONTENT;
	    }
	    tokadd(nextc());
	    if (heredoc_indent > 0) {
		lex_goto_eol(parser);
		goto flush;
	    }
	    /*	    if (mbp && mb == ENC_CODERANGE_UNKNOWN) mbp = 0;*/
	    if ((c = nextc()) == -1) goto error;
	} while (!whole_match_p(eos, len, indent));
	str = STR_NEW3(tok(), toklen(), enc, func);
    }
    dispatch_heredoc_end();
#ifdef RIPPER
    str = ripper_new_yylval(ripper_token2eventid(tSTRING_CONTENT),
			    yylval.val, str);
#endif
    heredoc_restore(&lex_strterm->u.heredoc);
    lex_strterm = NEW_STRTERM(func | STR_FUNC_TERM, 0, 0);
    set_yylval_str(str);
    add_mark_object(str);
    return tSTRING_CONTENT;
}

#include "lex.c"

static void
arg_ambiguous_gen(struct parser_params *parser, char c)
{
#ifndef RIPPER
    rb_warning1("ambiguous first argument; put parentheses or a space even after `%c' operator", WARN_I(c));
#else
    dispatch1(arg_ambiguous, rb_usascii_str_new(&c, 1));
#endif
}
#define arg_ambiguous(c) (arg_ambiguous_gen(parser, (c)), 1)

static ID
formal_argument_gen(struct parser_params *parser, ID lhs)
{
    switch (id_type(lhs)) {
      case ID_LOCAL:
	break;
#ifndef RIPPER
      case ID_CONST:
	yyerror0("formal argument cannot be a constant");
	return 0;
      case ID_INSTANCE:
	yyerror0("formal argument cannot be an instance variable");
	return 0;
      case ID_GLOBAL:
	yyerror0("formal argument cannot be a global variable");
	return 0;
      case ID_CLASS:
	yyerror0("formal argument cannot be a class variable");
	return 0;
      default:
	yyerror0("formal argument must be local variable");
	return 0;
#else
      default:
	lhs = dispatch1(param_error, lhs);
	ripper_error();
	return 0;
#endif
    }
    shadowing_lvar(lhs);
    return lhs;
}

static int
lvar_defined_gen(struct parser_params *parser, ID id)
{
    return (dyna_in_block() && dvar_defined(id)) || local_id(id);
}

/* emacsen -*- hack */
static long
parser_encode_length(struct parser_params *parser, const char *name, long len)
{
    long nlen;

    if (len > 5 && name[nlen = len - 5] == '-') {
	if (rb_memcicmp(name + nlen + 1, "unix", 4) == 0)
	    return nlen;
    }
    if (len > 4 && name[nlen = len - 4] == '-') {
	if (rb_memcicmp(name + nlen + 1, "dos", 3) == 0)
	    return nlen;
	if (rb_memcicmp(name + nlen + 1, "mac", 3) == 0 &&
	    !(len == 8 && rb_memcicmp(name, "utf8-mac", len) == 0))
	    /* exclude UTF8-MAC because the encoding named "UTF8" doesn't exist in Ruby */
	    return nlen;
    }
    return len;
}

static void
parser_set_encode(struct parser_params *parser, const char *name)
{
    int idx = rb_enc_find_index(name);
    rb_encoding *enc;
    VALUE excargs[3];

    if (idx < 0) {
	excargs[1] = rb_sprintf("unknown encoding name: %s", name);
      error:
	excargs[0] = rb_eArgError;
	excargs[2] = rb_make_backtrace();
	rb_ary_unshift(excargs[2], rb_sprintf("%"PRIsVALUE":%d", ruby_sourcefile_string, ruby_sourceline));
	rb_exc_raise(rb_make_exception(3, excargs));
    }
    enc = rb_enc_from_index(idx);
    if (!rb_enc_asciicompat(enc)) {
	excargs[1] = rb_sprintf("%s is not ASCII compatible", rb_enc_name(enc));
	goto error;
    }
    parser->enc = enc;
#ifndef RIPPER
    if (ruby_debug_lines) {
	VALUE lines = ruby_debug_lines;
	long i, n = RARRAY_LEN(lines);
	for (i = 0; i < n; ++i) {
	    rb_enc_associate_index(RARRAY_AREF(lines, i), idx);
	}
    }
#endif
}

static int
comment_at_top(struct parser_params *parser)
{
    const char *p = lex_pbeg, *pend = lex_p - 1;
    if (parser->line_count != (parser->has_shebang ? 2 : 1)) return 0;
    while (p < pend) {
	if (!ISSPACE(*p)) return 0;
	p++;
    }
    return 1;
}

typedef long (*rb_magic_comment_length_t)(struct parser_params *parser, const char *name, long len);
typedef void (*rb_magic_comment_setter_t)(struct parser_params *parser, const char *name, const char *val);

static void
magic_comment_encoding(struct parser_params *parser, const char *name, const char *val)
{
    if (!comment_at_top(parser)) {
	return;
    }
    parser_set_encode(parser, val);
}

static int
parser_get_bool(struct parser_params *parser, const char *name, const char *val)
{
    switch (*val) {
      case 't': case 'T':
	if (strcasecmp(val, "true") == 0) {
	    return TRUE;
	}
	break;
      case 'f': case 'F':
	if (strcasecmp(val, "false") == 0) {
	    return FALSE;
	}
	break;
    }
    rb_compile_warning(ruby_sourcefile, ruby_sourceline, "invalid value for %s: %s", name, val);
    return -1;
}

static void
parser_set_token_info(struct parser_params *parser, const char *name, const char *val)
{
    int b = parser_get_bool(parser, name, val);
    if (b >= 0) parser->token_info_enabled = b;
}

static void
parser_set_compile_option_flag(struct parser_params *parser, const char *name, const char *val)
{
    int b;

    if (parser->token_seen) {
	rb_warning1("`%s' is ignored after any tokens", WARN_S(name));
	return;
    }

    b = parser_get_bool(parser, name, val);
    if (b < 0) return;

    if (!parser->compile_option)
	parser->compile_option = rb_obj_hide(rb_ident_hash_new());
    rb_hash_aset(parser->compile_option, ID2SYM(rb_intern(name)),
		 (b ? Qtrue : Qfalse));
}

# if WARN_PAST_SCOPE
static void
parser_set_past_scope(struct parser_params *parser, const char *name, const char *val)
{
    int b = parser_get_bool(parser, name, val);
    if (b >= 0) parser->past_scope_enabled = b;
}
# endif

struct magic_comment {
    const char *name;
    rb_magic_comment_setter_t func;
    rb_magic_comment_length_t length;
};

static const struct magic_comment magic_comments[] = {
    {"coding", magic_comment_encoding, parser_encode_length},
    {"encoding", magic_comment_encoding, parser_encode_length},
    {"frozen_string_literal", parser_set_compile_option_flag},
    {"warn_indent", parser_set_token_info},
# if WARN_PAST_SCOPE
    {"warn_past_scope", parser_set_past_scope},
# endif
};

static const char *
magic_comment_marker(const char *str, long len)
{
    long i = 2;

    while (i < len) {
	switch (str[i]) {
	  case '-':
	    if (str[i-1] == '*' && str[i-2] == '-') {
		return str + i + 1;
	    }
	    i += 2;
	    break;
	  case '*':
	    if (i + 1 >= len) return 0;
	    if (str[i+1] != '-') {
		i += 4;
	    }
	    else if (str[i-1] != '-') {
		i += 2;
	    }
	    else {
		return str + i + 2;
	    }
	    break;
	  default:
	    i += 3;
	    break;
	}
    }
    return 0;
}

static int
parser_magic_comment(struct parser_params *parser, const char *str, long len)
{
    int indicator = 0;
    VALUE name = 0, val = 0;
    const char *beg, *end, *vbeg, *vend;
#define str_copy(_s, _p, _n) ((_s) \
	? (void)(rb_str_resize((_s), (_n)), \
	   MEMCPY(RSTRING_PTR(_s), (_p), char, (_n)), (_s)) \
	: (void)((_s) = STR_NEW((_p), (_n))))

    if (len <= 7) return FALSE;
    if (!!(beg = magic_comment_marker(str, len))) {
	if (!(end = magic_comment_marker(beg, str + len - beg)))
	    return FALSE;
	indicator = TRUE;
	str = beg;
	len = end - beg - 3;
    }

    /* %r"([^\\s\'\":;]+)\\s*:\\s*(\"(?:\\\\.|[^\"])*\"|[^\"\\s;]+)[\\s;]*" */
    while (len > 0) {
	const struct magic_comment *p = magic_comments;
	char *s;
	int i;
	long n = 0;

	for (; len > 0 && *str; str++, --len) {
	    switch (*str) {
	      case '\'': case '"': case ':': case ';':
		continue;
	    }
	    if (!ISSPACE(*str)) break;
	}
	for (beg = str; len > 0; str++, --len) {
	    switch (*str) {
	      case '\'': case '"': case ':': case ';':
		break;
	      default:
		if (ISSPACE(*str)) break;
		continue;
	    }
	    break;
	}
	for (end = str; len > 0 && ISSPACE(*str); str++, --len);
	if (!len) break;
	if (*str != ':') {
	    if (!indicator) return FALSE;
	    continue;
	}

	do str++; while (--len > 0 && ISSPACE(*str));
	if (!len) break;
	if (*str == '"') {
	    for (vbeg = ++str; --len > 0 && *str != '"'; str++) {
		if (*str == '\\') {
		    --len;
		    ++str;
		}
	    }
	    vend = str;
	    if (len) {
		--len;
		++str;
	    }
	}
	else {
	    for (vbeg = str; len > 0 && *str != '"' && *str != ';' && !ISSPACE(*str); --len, str++);
	    vend = str;
	}
	if (indicator) {
	    while (len > 0 && (*str == ';' || ISSPACE(*str))) --len, str++;
	}
	else {
	    while (len > 0 && (ISSPACE(*str))) --len, str++;
	    if (len) return FALSE;
	}

	n = end - beg;
	str_copy(name, beg, n);
	s = RSTRING_PTR(name);
	for (i = 0; i < n; ++i) {
	    if (s[i] == '-') s[i] = '_';
	}
	do {
	    if (STRNCASECMP(p->name, s, n) == 0 && !p->name[n]) {
		n = vend - vbeg;
		if (p->length) {
		    n = (*p->length)(parser, vbeg, n);
		}
		str_copy(val, vbeg, n);
		(*p->func)(parser, p->name, RSTRING_PTR(val));
		break;
	    }
	} while (++p < magic_comments + numberof(magic_comments));
#ifdef RIPPER
	str_copy(val, vbeg, vend - vbeg);
	dispatch2(magic_comment, name, val);
#endif
    }

    return TRUE;
}

static void
set_file_encoding(struct parser_params *parser, const char *str, const char *send)
{
    int sep = 0;
    const char *beg = str;
    VALUE s;

    for (;;) {
	if (send - str <= 6) return;
	switch (str[6]) {
	  case 'C': case 'c': str += 6; continue;
	  case 'O': case 'o': str += 5; continue;
	  case 'D': case 'd': str += 4; continue;
	  case 'I': case 'i': str += 3; continue;
	  case 'N': case 'n': str += 2; continue;
	  case 'G': case 'g': str += 1; continue;
	  case '=': case ':':
	    sep = 1;
	    str += 6;
	    break;
	  default:
	    str += 6;
	    if (ISSPACE(*str)) break;
	    continue;
	}
	if (STRNCASECMP(str-6, "coding", 6) == 0) break;
    }
    for (;;) {
	do {
	    if (++str >= send) return;
	} while (ISSPACE(*str));
	if (sep) break;
	if (*str != '=' && *str != ':') return;
	sep = 1;
	str++;
    }
    beg = str;
    while ((*str == '-' || *str == '_' || ISALNUM(*str)) && ++str < send);
    s = rb_str_new(beg, parser_encode_length(parser, beg, str - beg));
    parser_set_encode(parser, RSTRING_PTR(s));
    rb_str_resize(s, 0);
}

static void
parser_prepare(struct parser_params *parser)
{
    int c = nextc();
    parser->token_info_enabled = !compile_for_eval && RTEST(ruby_verbose);
    switch (c) {
      case '#':
	if (peek('!')) parser->has_shebang = 1;
	break;
      case 0xef:		/* UTF-8 BOM marker */
	if (lex_pend - lex_p >= 2 &&
	    (unsigned char)lex_p[0] == 0xbb &&
	    (unsigned char)lex_p[1] == 0xbf) {
	    parser->enc = rb_utf8_encoding();
	    lex_p += 2;
	    lex_pbeg = lex_p;
	    return;
	}
	break;
      case EOF:
	return;
    }
    pushback(c);
    parser->enc = rb_enc_get(lex_lastline);
}

#ifndef RIPPER
#define ambiguous_operator(tok, op, syn) ( \
    rb_warning0("`"op"' after local variable or literal is interpreted as binary operator"), \
    rb_warning0("even though it seems like "syn""))
#else
#define ambiguous_operator(tok, op, syn) \
    dispatch2(operator_ambiguous, TOKEN2VAL(tok), rb_str_new_cstr(syn))
#endif
#define warn_balanced(tok, op, syn) ((void) \
    (!IS_lex_state_for(last_state, EXPR_CLASS|EXPR_DOT|EXPR_FNAME|EXPR_ENDFN) && \
     space_seen && !ISSPACE(c) && \
     (ambiguous_operator(tok, op, syn), 0)), \
     (enum yytokentype)(tok))

static VALUE
parse_rational(struct parser_params *parser, char *str, int len, int seen_point)
{
    VALUE v;
    char *point = &str[seen_point];
    size_t fraclen = len-seen_point-1;
    memmove(point, point+1, fraclen+1);
    v = rb_cstr_to_inum(str, 10, FALSE);
    return rb_rational_new(v, rb_int_positive_pow(10, fraclen));
}

static int
parse_numeric(struct parser_params *parser, int c)
{
    int is_float, seen_point, seen_e, nondigit;
    int suffix;

    is_float = seen_point = seen_e = nondigit = 0;
    SET_LEX_STATE(EXPR_END);
    newtok();
    if (c == '-' || c == '+') {
	tokadd(c);
	c = nextc();
    }
    if (c == '0') {
#define no_digits() do {yyerror0("numeric literal without digits"); return 0;} while (0)
	int start = toklen();
	c = nextc();
	if (c == 'x' || c == 'X') {
	    /* hexadecimal */
	    c = nextc();
	    if (c != -1 && ISXDIGIT(c)) {
		do {
		    if (c == '_') {
			if (nondigit) break;
			nondigit = c;
			continue;
		    }
		    if (!ISXDIGIT(c)) break;
		    nondigit = 0;
		    tokadd(c);
		} while ((c = nextc()) != -1);
	    }
	    pushback(c);
	    tokfix();
	    if (toklen() == start) {
		no_digits();
	    }
	    else if (nondigit) goto trailing_uc;
	    suffix = number_literal_suffix(NUM_SUFFIX_ALL);
	    return set_integer_literal(rb_cstr_to_inum(tok(), 16, FALSE), suffix);
	}
	if (c == 'b' || c == 'B') {
	    /* binary */
	    c = nextc();
	    if (c == '0' || c == '1') {
		do {
		    if (c == '_') {
			if (nondigit) break;
			nondigit = c;
			continue;
		    }
		    if (c != '0' && c != '1') break;
		    nondigit = 0;
		    tokadd(c);
		} while ((c = nextc()) != -1);
	    }
	    pushback(c);
	    tokfix();
	    if (toklen() == start) {
		no_digits();
	    }
	    else if (nondigit) goto trailing_uc;
	    suffix = number_literal_suffix(NUM_SUFFIX_ALL);
	    return set_integer_literal(rb_cstr_to_inum(tok(), 2, FALSE), suffix);
	}
	if (c == 'd' || c == 'D') {
	    /* decimal */
	    c = nextc();
	    if (c != -1 && ISDIGIT(c)) {
		do {
		    if (c == '_') {
			if (nondigit) break;
			nondigit = c;
			continue;
		    }
		    if (!ISDIGIT(c)) break;
		    nondigit = 0;
		    tokadd(c);
		} while ((c = nextc()) != -1);
	    }
	    pushback(c);
	    tokfix();
	    if (toklen() == start) {
		no_digits();
	    }
	    else if (nondigit) goto trailing_uc;
	    suffix = number_literal_suffix(NUM_SUFFIX_ALL);
	    return set_integer_literal(rb_cstr_to_inum(tok(), 10, FALSE), suffix);
	}
	if (c == '_') {
	    /* 0_0 */
	    goto octal_number;
	}
	if (c == 'o' || c == 'O') {
	    /* prefixed octal */
	    c = nextc();
	    if (c == -1 || c == '_' || !ISDIGIT(c)) {
		no_digits();
	    }
	}
	if (c >= '0' && c <= '7') {
	    /* octal */
	  octal_number:
	    do {
		if (c == '_') {
		    if (nondigit) break;
		    nondigit = c;
		    continue;
		}
		if (c < '0' || c > '9') break;
		if (c > '7') goto invalid_octal;
		nondigit = 0;
		tokadd(c);
	    } while ((c = nextc()) != -1);
	    if (toklen() > start) {
		pushback(c);
		tokfix();
		if (nondigit) goto trailing_uc;
		suffix = number_literal_suffix(NUM_SUFFIX_ALL);
		return set_integer_literal(rb_cstr_to_inum(tok(), 8, FALSE), suffix);
	    }
	    if (nondigit) {
		pushback(c);
		goto trailing_uc;
	    }
	}
	if (c > '7' && c <= '9') {
	  invalid_octal:
	    yyerror0("Invalid octal digit");
	}
	else if (c == '.' || c == 'e' || c == 'E') {
	    tokadd('0');
	}
	else {
	    pushback(c);
	    suffix = number_literal_suffix(NUM_SUFFIX_ALL);
	    return set_integer_literal(INT2FIX(0), suffix);
	}
    }

    for (;;) {
	switch (c) {
	  case '0': case '1': case '2': case '3': case '4':
	  case '5': case '6': case '7': case '8': case '9':
	    nondigit = 0;
	    tokadd(c);
	    break;

	  case '.':
	    if (nondigit) goto trailing_uc;
	    if (seen_point || seen_e) {
		goto decode_num;
	    }
	    else {
		int c0 = nextc();
		if (c0 == -1 || !ISDIGIT(c0)) {
		    pushback(c0);
		    goto decode_num;
		}
		c = c0;
	    }
	    seen_point = toklen();
	    tokadd('.');
	    tokadd(c);
	    is_float++;
	    nondigit = 0;
	    break;

	  case 'e':
	  case 'E':
	    if (nondigit) {
		pushback(c);
		c = nondigit;
		goto decode_num;
	    }
	    if (seen_e) {
		goto decode_num;
	    }
	    nondigit = c;
	    c = nextc();
	    if (c != '-' && c != '+' && !ISDIGIT(c)) {
		pushback(c);
		nondigit = 0;
		goto decode_num;
	    }
	    tokadd(nondigit);
	    seen_e++;
	    is_float++;
	    tokadd(c);
	    nondigit = (c == '-' || c == '+') ? c : 0;
	    break;

	  case '_':	/* `_' in number just ignored */
	    if (nondigit) goto decode_num;
	    nondigit = c;
	    break;

	  default:
	    goto decode_num;
	}
	c = nextc();
    }

  decode_num:
    pushback(c);
    if (nondigit) {
	char tmp[30];
      trailing_uc:
	literal_flush(lex_p - 1);
	snprintf(tmp, sizeof(tmp), "trailing `%c' in number", nondigit);
	yyerror0(tmp);
    }
    tokfix();
    if (is_float) {
	int type = tFLOAT;
	VALUE v;

	suffix = number_literal_suffix(seen_e ? NUM_SUFFIX_I : NUM_SUFFIX_ALL);
	if (suffix & NUM_SUFFIX_R) {
	    type = tRATIONAL;
	    v = parse_rational(parser, tok(), toklen(), seen_point);
	}
	else {
	    double d = strtod(tok(), 0);
	    if (errno == ERANGE) {
		rb_warning1("Float %s out of range", WARN_S(tok()));
		errno = 0;
	    }
	    v = DBL2NUM(d);
	}
	return set_number_literal(v, type, suffix);
    }
    suffix = number_literal_suffix(NUM_SUFFIX_ALL);
    return set_integer_literal(rb_cstr_to_inum(tok(), 10, FALSE), suffix);
}

static enum yytokentype
parse_qmark(struct parser_params *parser, int space_seen)
{
    rb_encoding *enc;
    register int c;
    VALUE lit;

    if (IS_END()) {
	SET_LEX_STATE(EXPR_VALUE);
	return '?';
    }
    c = nextc();
    if (c == -1) {
	compile_error(PARSER_ARG "incomplete character syntax");
	return 0;
    }
    if (rb_enc_isspace(c, current_enc)) {
	if (!IS_ARG()) {
	    int c2 = 0;
	    switch (c) {
	      case ' ':
		c2 = 's';
		break;
	      case '\n':
		c2 = 'n';
		break;
	      case '\t':
		c2 = 't';
		break;
	      case '\v':
		c2 = 'v';
		break;
	      case '\r':
		c2 = 'r';
		break;
	      case '\f':
		c2 = 'f';
		break;
	    }
	    if (c2) {
		rb_warn1("invalid character syntax; use ?\\%c", WARN_I(c2));
	    }
	}
      ternary:
	pushback(c);
	SET_LEX_STATE(EXPR_VALUE);
	return '?';
    }
    newtok();
    enc = current_enc;
    if (!parser_isascii()) {
	if (tokadd_mbchar(c) == -1) return 0;
    }
    else if ((rb_enc_isalnum(c, current_enc) || c == '_') &&
	     lex_p < lex_pend && is_identchar(lex_p, lex_pend, current_enc)) {
	if (space_seen) {
	    const char *start = lex_p - 1, *p = start;
	    do {
		int n = parser_precise_mbclen(parser, p);
		if (n < 0) return -1;
		p += n;
	    } while (p < lex_pend && is_identchar(p, lex_pend, current_enc));
	    rb_warn2("`?' just followed by `%.*s' is interpreted as" \
		     " a conditional operator, put a space after `?'",
		     WARN_I((int)(p - start)), WARN_S_L(start, (p - start)));
	}
	goto ternary;
    }
    else if (c == '\\') {
	if (peek('u')) {
	    nextc();
	    enc = rb_utf8_encoding();
	    if (!parser_tokadd_utf8(parser, &enc, -1, 0, 0))
		return 0;
	}
	else if (!lex_eol_p() && !(c = *lex_p, ISASCII(c))) {
	    nextc();
	    if (tokadd_mbchar(c) == -1) return 0;
	}
	else {
	    c = read_escape(0, &enc);
	    tokadd(c);
	}
    }
    else {
	tokadd(c);
    }
    tokfix();
    add_mark_object(lit = STR_NEW3(tok(), toklen(), enc, 0));
    set_yylval_str(lit);
    SET_LEX_STATE(EXPR_END);
    return tCHAR;
}

static enum yytokentype
parse_percent(struct parser_params *parser, const int space_seen, const enum lex_state_e last_state)
{
    register int c;

    if (IS_BEG()) {
	int term;
	int paren;

	c = nextc();
      quotation:
	if (c == -1 || !ISALNUM(c)) {
	    term = c;
	    c = 'Q';
	}
	else {
	    term = nextc();
	    if (rb_enc_isalnum(term, current_enc) || !parser_isascii()) {
		yyerror0("unknown type of %string");
		return 0;
	    }
	}
	if (c == -1 || term == -1) {
	    compile_error(PARSER_ARG "unterminated quoted string meets end of file");
	    return 0;
	}
	paren = term;
	if (term == '(') term = ')';
	else if (term == '[') term = ']';
	else if (term == '{') term = '}';
	else if (term == '<') term = '>';
	else paren = 0;

	switch (c) {
	  case 'Q':
	    lex_strterm = NEW_STRTERM(str_dquote, term, paren);
	    return tSTRING_BEG;

	  case 'q':
	    lex_strterm = NEW_STRTERM(str_squote, term, paren);
	    return tSTRING_BEG;

	  case 'W':
	    lex_strterm = NEW_STRTERM(str_dword, term, paren);
	    return tWORDS_BEG;

	  case 'w':
	    lex_strterm = NEW_STRTERM(str_sword, term, paren);
	    return tQWORDS_BEG;

	  case 'I':
	    lex_strterm = NEW_STRTERM(str_dword, term, paren);
	    return tSYMBOLS_BEG;

	  case 'i':
	    lex_strterm = NEW_STRTERM(str_sword, term, paren);
	    return tQSYMBOLS_BEG;

	  case 'x':
	    lex_strterm = NEW_STRTERM(str_xquote, term, paren);
	    return tXSTRING_BEG;

	  case 'r':
	    lex_strterm = NEW_STRTERM(str_regexp, term, paren);
	    return tREGEXP_BEG;

	  case 's':
	    lex_strterm = NEW_STRTERM(str_ssym, term, paren);
	    SET_LEX_STATE(EXPR_FNAME|EXPR_FITEM);
	    return tSYMBEG;

	  default:
	    yyerror0("unknown type of %string");
	    return 0;
	}
    }
    if ((c = nextc()) == '=') {
	set_yylval_id('%');
	SET_LEX_STATE(EXPR_BEG);
	return tOP_ASGN;
    }
    if (IS_SPCARG(c) || (IS_lex_state(EXPR_FITEM) && c == 's')) {
	goto quotation;
    }
    SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
    pushback(c);
    return warn_balanced('%', "%%", "string literal");
}

static int
tokadd_ident(struct parser_params *parser, int c)
{
    do {
	if (tokadd_mbchar(c) == -1) return -1;
	c = nextc();
    } while (parser_is_identchar());
    pushback(c);
    return 0;
}

static ID
tokenize_ident(struct parser_params *parser, const enum lex_state_e last_state)
{
    ID ident = TOK_INTERN();

    set_yylval_name(ident);

    return ident;
}

static int
parse_numvar(struct parser_params *parser)
{
    size_t len;
    int overflow;
    unsigned long n = ruby_scan_digits(tok()+1, toklen()-1, 10, &len, &overflow);
    const unsigned long nth_ref_max =
	((FIXNUM_MAX < INT_MAX) ? FIXNUM_MAX : INT_MAX) >> 1;
    /* NTH_REF is left-shifted to be ORed with back-ref flag and
     * turned into a Fixnum, in compile.c */

    if (overflow || n > nth_ref_max) {
	/* compile_error()? */
	rb_warn1("`%s' is too big for a number variable, always nil", WARN_S(tok()));
	return 0;		/* $0 is $PROGRAM_NAME, not NTH_REF */
    }
    else {
	return (int)n;
    }
}

static enum yytokentype
parse_gvar(struct parser_params *parser, const enum lex_state_e last_state)
{
    register int c;

    SET_LEX_STATE(EXPR_END);
    newtok();
    c = nextc();
    switch (c) {
      case '_':		/* $_: last read line string */
	c = nextc();
	if (parser_is_identchar()) {
	    tokadd('$');
	    tokadd('_');
	    break;
	}
	pushback(c);
	c = '_';
	/* fall through */
      case '~':		/* $~: match-data */
      case '*':		/* $*: argv */
      case '$':		/* $$: pid */
      case '?':		/* $?: last status */
      case '!':		/* $!: error string */
      case '@':		/* $@: error position */
      case '/':		/* $/: input record separator */
      case '\\':		/* $\: output record separator */
      case ';':		/* $;: field separator */
      case ',':		/* $,: output field separator */
      case '.':		/* $.: last read line number */
      case '=':		/* $=: ignorecase */
      case ':':		/* $:: load path */
      case '<':		/* $<: reading filename */
      case '>':		/* $>: default output handle */
      case '\"':		/* $": already loaded files */
	tokadd('$');
	tokadd(c);
	goto gvar;

      case '-':
	tokadd('$');
	tokadd(c);
	c = nextc();
	if (parser_is_identchar()) {
	    if (tokadd_mbchar(c) == -1) return 0;
	}
	else {
	    pushback(c);
	    pushback('-');
	    return '$';
	}
      gvar:
	set_yylval_name(TOK_INTERN());
	return tGVAR;

      case '&':		/* $&: last match */
      case '`':		/* $`: string before last match */
      case '\'':		/* $': string after last match */
      case '+':		/* $+: string matches last paren. */
	if (IS_lex_state_for(last_state, EXPR_FNAME)) {
	    tokadd('$');
	    tokadd(c);
	    goto gvar;
	}
	set_yylval_node(NEW_BACK_REF(c));
	return tBACK_REF;

      case '1': case '2': case '3':
      case '4': case '5': case '6':
      case '7': case '8': case '9':
	tokadd('$');
	do {
	    tokadd(c);
	    c = nextc();
	} while (c != -1 && ISDIGIT(c));
	pushback(c);
	if (IS_lex_state_for(last_state, EXPR_FNAME)) goto gvar;
	tokfix();
	set_yylval_node(NEW_NTH_REF(parse_numvar(parser)));
	return tNTH_REF;

      default:
	if (!parser_is_identchar()) {
	    if (c == -1 || ISSPACE(c)) {
		compile_error(PARSER_ARG "`$' without identifiers is not allowed as a global variable name");
	    }
	    else {
		pushback(c);
		compile_error(PARSER_ARG "`$%c' is not allowed as a global variable name", c);
	    }
	    return 0;
	}
      case '0':
	tokadd('$');
    }

    if (tokadd_ident(parser, c)) return 0;
    SET_LEX_STATE(EXPR_END);
    tokenize_ident(parser, last_state);
    return tGVAR;
}

static enum yytokentype
parse_atmark(struct parser_params *parser, const enum lex_state_e last_state)
{
    enum yytokentype result = tIVAR;
    register int c = nextc();

    newtok();
    tokadd('@');
    if (c == '@') {
	result = tCVAR;
	tokadd('@');
	c = nextc();
    }
    if (c == -1 || ISSPACE(c)) {
	if (result == tIVAR) {
	    compile_error(PARSER_ARG "`@' without identifiers is not allowed as an instance variable name");
	}
	else {
	    compile_error(PARSER_ARG "`@@' without identifiers is not allowed as a class variable name");
	}
	return 0;
    }
    else if (ISDIGIT(c) || !parser_is_identchar()) {
	pushback(c);
	if (result == tIVAR) {
	    compile_error(PARSER_ARG "`@%c' is not allowed as an instance variable name", c);
	}
	else {
	    compile_error(PARSER_ARG "`@@%c' is not allowed as a class variable name", c);
	}
	return 0;
    }

    if (tokadd_ident(parser, c)) return 0;
    SET_LEX_STATE(EXPR_END);
    tokenize_ident(parser, last_state);
    return result;
}

static enum yytokentype
parse_ident(struct parser_params *parser, int c, int cmd_state)
{
    enum yytokentype result;
    int mb = ENC_CODERANGE_7BIT;
    const enum lex_state_e last_state = lex_state;
    ID ident;

    do {
	if (!ISASCII(c)) mb = ENC_CODERANGE_UNKNOWN;
	if (tokadd_mbchar(c) == -1) return 0;
	c = nextc();
    } while (parser_is_identchar());
    if ((c == '!' || c == '?') && !peek('=')) {
	result = tFID;
	tokadd(c);
    }
    else if (c == '=' && IS_lex_state(EXPR_FNAME) &&
	     (!peek('~') && !peek('>') && (!peek('=') || (peek_n('>', 1))))) {
	result = tIDENTIFIER;
	tokadd(c);
    }
    else {
	result = tCONSTANT;	/* assume provisionally */
	pushback(c);
    }
    tokfix();

    if (IS_LABEL_POSSIBLE()) {
	if (IS_LABEL_SUFFIX(0)) {
	    SET_LEX_STATE(EXPR_ARG|EXPR_LABELED);
	    nextc();
	    set_yylval_name(TOK_INTERN());
	    return tLABEL;
	}
    }
    if (mb == ENC_CODERANGE_7BIT && !IS_lex_state(EXPR_DOT)) {
	const struct kwtable *kw;

	/* See if it is a reserved word.  */
	kw = rb_reserved_word(tok(), toklen());
	if (kw) {
	    enum lex_state_e state = lex_state;
	    SET_LEX_STATE(kw->state);
	    if (IS_lex_state_for(state, EXPR_FNAME)) {
		set_yylval_name(rb_intern2(tok(), toklen()));
		return kw->id[0];
	    }
	    if (IS_lex_state(EXPR_BEG)) {
		command_start = TRUE;
	    }
	    if (kw->id[0] == keyword_do) {
		if (lambda_beginning_p()) {
		    lpar_beg = 0;
		    --paren_nest;
		    return keyword_do_LAMBDA;
		}
		if (COND_P()) return keyword_do_cond;
		if (CMDARG_P() && !IS_lex_state_for(state, EXPR_CMDARG))
		    return keyword_do_block;
		if (IS_lex_state_for(state, (EXPR_BEG | EXPR_ENDARG)))
		    return keyword_do_block;
		return keyword_do;
	    }
	    if (IS_lex_state_for(state, (EXPR_BEG | EXPR_LABELED)))
		return kw->id[0];
	    else {
		if (kw->id[0] != kw->id[1])
		    SET_LEX_STATE(EXPR_BEG | EXPR_LABEL);
		return kw->id[1];
	    }
	}
    }

    if (IS_lex_state(EXPR_BEG_ANY | EXPR_ARG_ANY | EXPR_DOT)) {
	if (cmd_state) {
	    SET_LEX_STATE(EXPR_CMDARG);
	}
	else {
	    SET_LEX_STATE(EXPR_ARG);
	}
    }
    else if (lex_state == EXPR_FNAME) {
	SET_LEX_STATE(EXPR_ENDFN);
    }
    else {
	SET_LEX_STATE(EXPR_END);
    }

    ident = tokenize_ident(parser, last_state);
    if (result == tCONSTANT && is_local_id(ident)) result = tIDENTIFIER;
    if (!IS_lex_state_for(last_state, EXPR_DOT|EXPR_FNAME) &&
	(result == tIDENTIFIER) && /* not EXPR_FNAME, not attrasgn */
	lvar_defined(ident)) {
	SET_LEX_STATE(EXPR_END|EXPR_LABEL);
    }
    return result;
}

static enum yytokentype
parser_yylex(struct parser_params *parser)
{
    register int c;
    int space_seen = 0;
    int cmd_state;
    int label;
    enum lex_state_e last_state;
    int fallthru = FALSE;
    int token_seen = parser->token_seen;

    if (lex_strterm) {
	if (lex_strterm->flags & STRTERM_HEREDOC) {
	    return here_document(&lex_strterm->u.heredoc);
	}
	else {
	    token_flush(parser);
	    return parse_string(&lex_strterm->u.literal);
	}
    }
    cmd_state = command_start;
    command_start = FALSE;
    parser->token_seen = TRUE;
  retry:
    last_state = lex_state;
#ifndef RIPPER
    token_flush(parser);
#endif
    switch (c = nextc()) {
      case '\0':		/* NUL */
      case '\004':		/* ^D */
      case '\032':		/* ^Z */
      case -1:			/* end of script. */
	return 0;

	/* white spaces */
      case ' ': case '\t': case '\f': case '\r':
      case '\13': /* '\v' */
	space_seen = 1;
#ifdef RIPPER
	while ((c = nextc())) {
	    switch (c) {
	      case ' ': case '\t': case '\f': case '\r':
	      case '\13': /* '\v' */
		break;
	      default:
		goto outofloop;
	    }
	}
      outofloop:
	pushback(c);
	dispatch_scan_event(tSP);
#endif
	goto retry;

      case '#':		/* it's a comment */
	parser->token_seen = token_seen;
	/* no magic_comment in shebang line */
	if (!parser_magic_comment(parser, lex_p, lex_pend - lex_p)) {
	    if (comment_at_top(parser)) {
		set_file_encoding(parser, lex_p, lex_pend);
	    }
	}
	lex_p = lex_pend;
        dispatch_scan_event(tCOMMENT);
        fallthru = TRUE;
	/* fall through */
      case '\n':
	parser->token_seen = token_seen;
	c = (IS_lex_state(EXPR_BEG|EXPR_CLASS|EXPR_FNAME|EXPR_DOT) &&
	     !IS_lex_state(EXPR_LABELED));
	if (c || IS_lex_state_all(EXPR_ARG|EXPR_LABELED)) {
            if (!fallthru) {
                dispatch_scan_event(tIGNORED_NL);
            }
            fallthru = FALSE;
	    if (!c && parser->in_kwarg) {
		goto normal_newline;
	    }
	    goto retry;
	}
	while ((c = nextc())) {
	    switch (c) {
	      case ' ': case '\t': case '\f': case '\r':
	      case '\13': /* '\v' */
		space_seen = 1;
		break;
	      case '&':
	      case '.': {
		dispatch_delayed_token(tIGNORED_NL);
		if (peek('.') == (c == '&')) {
		    pushback(c);
		    dispatch_scan_event(tSP);
		    goto retry;
		}
	      }
	      default:
		--ruby_sourceline;
		lex_nextline = lex_lastline;
	      case -1:		/* EOF no decrement*/
#ifndef RIPPER
		if (lex_prevline && !parser->eofp) lex_lastline = lex_prevline;
		lex_pbeg = RSTRING_PTR(lex_lastline);
		lex_pend = lex_p = lex_pbeg + RSTRING_LEN(lex_lastline);
		pushback(1); /* always pushback */
		parser->tokp = lex_p;
#else
		lex_goto_eol(parser);
		if (c != -1) {
		    parser->tokp = lex_p;
		}
#endif
		goto normal_newline;
	    }
	}
      normal_newline:
	command_start = TRUE;
	SET_LEX_STATE(EXPR_BEG);
	return '\n';

      case '*':
	if ((c = nextc()) == '*') {
	    if ((c = nextc()) == '=') {
                set_yylval_id(tPOW);
		SET_LEX_STATE(EXPR_BEG);
		return tOP_ASGN;
	    }
	    pushback(c);
	    if (IS_SPCARG(c)) {
		rb_warning0("`**' interpreted as argument prefix");
		c = tDSTAR;
	    }
	    else if (IS_BEG()) {
		c = tDSTAR;
	    }
	    else {
		c = warn_balanced((enum ruby_method_ids)tPOW, "**", "argument prefix");
	    }
	}
	else {
	    if (c == '=') {
                set_yylval_id('*');
		SET_LEX_STATE(EXPR_BEG);
		return tOP_ASGN;
	    }
	    pushback(c);
	    if (IS_SPCARG(c)) {
		rb_warning0("`*' interpreted as argument prefix");
		c = tSTAR;
	    }
	    else if (IS_BEG()) {
		c = tSTAR;
	    }
	    else {
		c = warn_balanced('*', "*", "argument prefix");
	    }
	}
	SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
	return c;

      case '!':
	c = nextc();
	if (IS_AFTER_OPERATOR()) {
	    SET_LEX_STATE(EXPR_ARG);
	    if (c == '@') {
		return '!';
	    }
	}
	else {
	    SET_LEX_STATE(EXPR_BEG);
	}
	if (c == '=') {
	    return tNEQ;
	}
	if (c == '~') {
	    return tNMATCH;
	}
	pushback(c);
	return '!';

      case '=':
	if (was_bol()) {
	    /* skip embedded rd document */
	    if (strncmp(lex_p, "begin", 5) == 0 && ISSPACE(lex_p[5])) {
		int first_p = TRUE;

		lex_goto_eol(parser);
		dispatch_scan_event(tEMBDOC_BEG);
		for (;;) {
		    lex_goto_eol(parser);
		    if (!first_p) {
			dispatch_scan_event(tEMBDOC);
		    }
		    first_p = FALSE;
		    c = nextc();
		    if (c == -1) {
			compile_error(PARSER_ARG "embedded document meets end of file");
			return 0;
		    }
		    if (c != '=') continue;
		    if (c == '=' && strncmp(lex_p, "end", 3) == 0 &&
			(lex_p + 3 == lex_pend || ISSPACE(lex_p[3]))) {
			break;
		    }
		}
		lex_goto_eol(parser);
		dispatch_scan_event(tEMBDOC_END);
		goto retry;
	    }
	}

	SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
	if ((c = nextc()) == '=') {
	    if ((c = nextc()) == '=') {
		return tEQQ;
	    }
	    pushback(c);
	    return tEQ;
	}
	if (c == '~') {
	    return tMATCH;
	}
	else if (c == '>') {
	    return tASSOC;
	}
	pushback(c);
	return '=';

      case '<':
	last_state = lex_state;
	c = nextc();
	if (c == '<' &&
	    !IS_lex_state(EXPR_DOT | EXPR_CLASS) &&
	    !IS_END() &&
	    (!IS_ARG() || IS_lex_state(EXPR_LABELED) || space_seen)) {
	    int token = heredoc_identifier();
	    if (token) return token;
	}
	if (IS_AFTER_OPERATOR()) {
	    SET_LEX_STATE(EXPR_ARG);
	}
	else {
	    if (IS_lex_state(EXPR_CLASS))
		command_start = TRUE;
	    SET_LEX_STATE(EXPR_BEG);
	}
	if (c == '=') {
	    if ((c = nextc()) == '>') {
		return tCMP;
	    }
	    pushback(c);
	    return tLEQ;
	}
	if (c == '<') {
	    if ((c = nextc()) == '=') {
                set_yylval_id(tLSHFT);
		SET_LEX_STATE(EXPR_BEG);
		return tOP_ASGN;
	    }
	    pushback(c);
	    return warn_balanced((enum ruby_method_ids)tLSHFT, "<<", "here document");
	}
	pushback(c);
	return '<';

      case '>':
	SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
	if ((c = nextc()) == '=') {
	    return tGEQ;
	}
	if (c == '>') {
	    if ((c = nextc()) == '=') {
                set_yylval_id(tRSHFT);
		SET_LEX_STATE(EXPR_BEG);
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tRSHFT;
	}
	pushback(c);
	return '>';

      case '"':
	label = (IS_LABEL_POSSIBLE() ? str_label : 0);
	lex_strterm = NEW_STRTERM(str_dquote | label, '"', 0);
	return tSTRING_BEG;

      case '`':
	if (IS_lex_state(EXPR_FNAME)) {
	    SET_LEX_STATE(EXPR_ENDFN);
	    return c;
	}
	if (IS_lex_state(EXPR_DOT)) {
	    if (cmd_state)
		SET_LEX_STATE(EXPR_CMDARG);
	    else
		SET_LEX_STATE(EXPR_ARG);
	    return c;
	}
	lex_strterm = NEW_STRTERM(str_xquote, '`', 0);
	return tXSTRING_BEG;

      case '\'':
	label = (IS_LABEL_POSSIBLE() ? str_label : 0);
	lex_strterm = NEW_STRTERM(str_squote | label, '\'', 0);
	return tSTRING_BEG;

      case '?':
	return parse_qmark(parser, space_seen);

      case '&':
	if ((c = nextc()) == '&') {
	    SET_LEX_STATE(EXPR_BEG);
	    if ((c = nextc()) == '=') {
                set_yylval_id(tANDOP);
		SET_LEX_STATE(EXPR_BEG);
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tANDOP;
	}
	else if (c == '=') {
            set_yylval_id('&');
	    SET_LEX_STATE(EXPR_BEG);
	    return tOP_ASGN;
	}
	else if (c == '.') {
	    SET_LEX_STATE(EXPR_DOT);
	    return tANDDOT;
	}
	pushback(c);
	if (IS_SPCARG(c)) {
	    if ((c != ':') ||
		(c = peekc_n(1)) == -1 ||
		!(c == '\'' || c == '"' ||
		  is_identchar((lex_p+1), lex_pend, current_enc))) {
		rb_warning0("`&' interpreted as argument prefix");
	    }
	    c = tAMPER;
	}
	else if (IS_BEG()) {
	    c = tAMPER;
	}
	else {
	    c = warn_balanced('&', "&", "argument prefix");
	}
	SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
	return c;

      case '|':
	if ((c = nextc()) == '|') {
	    SET_LEX_STATE(EXPR_BEG);
	    if ((c = nextc()) == '=') {
                set_yylval_id(tOROP);
		SET_LEX_STATE(EXPR_BEG);
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tOROP;
	}
	if (c == '=') {
            set_yylval_id('|');
	    SET_LEX_STATE(EXPR_BEG);
	    return tOP_ASGN;
	}
	SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG|EXPR_LABEL);
	pushback(c);
	return '|';

      case '+':
	c = nextc();
	if (IS_AFTER_OPERATOR()) {
	    SET_LEX_STATE(EXPR_ARG);
	    if (c == '@') {
		return tUPLUS;
	    }
	    pushback(c);
	    return '+';
	}
	if (c == '=') {
            set_yylval_id('+');
	    SET_LEX_STATE(EXPR_BEG);
	    return tOP_ASGN;
	}
	if (IS_BEG() || (IS_SPCARG(c) && arg_ambiguous('+'))) {
	    SET_LEX_STATE(EXPR_BEG);
	    pushback(c);
	    if (c != -1 && ISDIGIT(c)) {
		return parse_numeric(parser, '+');
	    }
	    return tUPLUS;
	}
	SET_LEX_STATE(EXPR_BEG);
	pushback(c);
	return warn_balanced('+', "+", "unary operator");

      case '-':
	c = nextc();
	if (IS_AFTER_OPERATOR()) {
	    SET_LEX_STATE(EXPR_ARG);
	    if (c == '@') {
		return tUMINUS;
	    }
	    pushback(c);
	    return '-';
	}
	if (c == '=') {
            set_yylval_id('-');
	    SET_LEX_STATE(EXPR_BEG);
	    return tOP_ASGN;
	}
	if (c == '>') {
	    SET_LEX_STATE(EXPR_ENDFN);
	    token_info_push("->");
	    return tLAMBDA;
	}
	if (IS_BEG() || (IS_SPCARG(c) && arg_ambiguous('-'))) {
	    SET_LEX_STATE(EXPR_BEG);
	    pushback(c);
	    if (c != -1 && ISDIGIT(c)) {
		return tUMINUS_NUM;
	    }
	    return tUMINUS;
	}
	SET_LEX_STATE(EXPR_BEG);
	pushback(c);
	return warn_balanced('-', "-", "unary operator");

      case '.':
	SET_LEX_STATE(EXPR_BEG);
	if ((c = nextc()) == '.') {
	    if ((c = nextc()) == '.') {
		return tDOT3;
	    }
	    pushback(c);
	    return tDOT2;
	}
	pushback(c);
	if (c != -1 && ISDIGIT(c)) {
	    yyerror0("no .<digit> floating literal anymore; put 0 before dot");
	}
	SET_LEX_STATE(EXPR_DOT);
	return '.';

      case '0': case '1': case '2': case '3': case '4':
      case '5': case '6': case '7': case '8': case '9':
	return parse_numeric(parser, c);

      case ')':
      case ']':
	paren_nest--;
      case '}':
	COND_LEXPOP();
	CMDARG_LEXPOP();
	if (c == ')')
	    SET_LEX_STATE(EXPR_ENDFN);
	else
	    SET_LEX_STATE(EXPR_END);
	if (c == '}') {
	    if (!brace_nest--) c = tSTRING_DEND;
	}
	return c;

      case ':':
	c = nextc();
	if (c == ':') {
	    if (IS_BEG() || IS_lex_state(EXPR_CLASS) || IS_SPCARG(-1)) {
		SET_LEX_STATE(EXPR_BEG);
		return tCOLON3;
	    }
	    SET_LEX_STATE(EXPR_DOT);
	    return tCOLON2;
	}
	if (IS_END() || ISSPACE(c) || c == '#') {
	    pushback(c);
	    c = warn_balanced(':', ":", "symbol literal");
	    SET_LEX_STATE(EXPR_BEG);
	    return c;
	}
	switch (c) {
	  case '\'':
	    lex_strterm = NEW_STRTERM(str_ssym, c, 0);
	    break;
	  case '"':
	    lex_strterm = NEW_STRTERM(str_dsym, c, 0);
	    break;
	  default:
	    pushback(c);
	    break;
	}
	SET_LEX_STATE(EXPR_FNAME);
	return tSYMBEG;

      case '/':
	if (IS_BEG()) {
	    lex_strterm = NEW_STRTERM(str_regexp, '/', 0);
	    return tREGEXP_BEG;
	}
	if ((c = nextc()) == '=') {
            set_yylval_id('/');
	    SET_LEX_STATE(EXPR_BEG);
	    return tOP_ASGN;
	}
	pushback(c);
	if (IS_SPCARG(c)) {
	    (void)arg_ambiguous('/');
	    lex_strterm = NEW_STRTERM(str_regexp, '/', 0);
	    return tREGEXP_BEG;
	}
	SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
	return warn_balanced('/', "/", "regexp literal");

      case '^':
	if ((c = nextc()) == '=') {
            set_yylval_id('^');
	    SET_LEX_STATE(EXPR_BEG);
	    return tOP_ASGN;
	}
	SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
	pushback(c);
	return '^';

      case ';':
	SET_LEX_STATE(EXPR_BEG);
	command_start = TRUE;
	return ';';

      case ',':
	SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
	return ',';

      case '~':
	if (IS_AFTER_OPERATOR()) {
	    if ((c = nextc()) != '@') {
		pushback(c);
	    }
	    SET_LEX_STATE(EXPR_ARG);
	}
	else {
	    SET_LEX_STATE(EXPR_BEG);
	}
	return '~';

      case '(':
	if (IS_BEG()) {
	    c = tLPAREN;
	}
	else if (!space_seen) {
	    /* foo( ... ) => method call, no ambiguity */
	}
	else if (IS_ARG() || IS_lex_state_all(EXPR_END|EXPR_LABEL)) {
	    c = tLPAREN_ARG;
	}
	else if (IS_lex_state(EXPR_ENDFN) && !lambda_beginning_p()) {
	    rb_warning0("parentheses after method name is interpreted as "
			"an argument list, not a decomposed argument");
	}
	paren_nest++;
	COND_PUSH(0);
	CMDARG_PUSH(0);
	SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
	return c;

      case '[':
	paren_nest++;
	if (IS_AFTER_OPERATOR()) {
	    if ((c = nextc()) == ']') {
		SET_LEX_STATE(EXPR_ARG);
		if ((c = nextc()) == '=') {
		    return tASET;
		}
		pushback(c);
		return tAREF;
	    }
	    pushback(c);
	    SET_LEX_STATE(EXPR_ARG|EXPR_LABEL);
	    return '[';
	}
	else if (IS_BEG()) {
	    c = tLBRACK;
	}
	else if (IS_ARG() && (space_seen || IS_lex_state(EXPR_LABELED))) {
	    c = tLBRACK;
	}
	SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
	COND_PUSH(0);
	CMDARG_PUSH(0);
	return c;

      case '{':
	++brace_nest;
	if (lambda_beginning_p()) {
	    SET_LEX_STATE(EXPR_BEG);
	    lpar_beg = 0;
	    --paren_nest;
	    COND_PUSH(0);
	    CMDARG_PUSH(0);
	    return tLAMBEG;
	}
	if (IS_lex_state(EXPR_LABELED))
	    c = tLBRACE;      /* hash */
	else if (IS_lex_state(EXPR_ARG_ANY | EXPR_END | EXPR_ENDFN))
	    c = '{';          /* block (primary) */
	else if (IS_lex_state(EXPR_ENDARG))
	    c = tLBRACE_ARG;  /* block (expr) */
	else
	    c = tLBRACE;      /* hash */
	COND_PUSH(0);
	CMDARG_PUSH(0);
	SET_LEX_STATE(c == tLBRACE_ARG ? EXPR_BEG : EXPR_BEG|EXPR_LABEL);
	if (c != tLBRACE) command_start = TRUE;
	return c;

      case '\\':
	c = nextc();
	if (c == '\n') {
	    space_seen = 1;
	    dispatch_scan_event(tSP);
	    goto retry; /* skip \\n */
	}
	pushback(c);
	return '\\';

      case '%':
	return parse_percent(parser, space_seen, last_state);

      case '$':
	return parse_gvar(parser, last_state);

      case '@':
	return parse_atmark(parser, last_state);

      case '_':
	if (was_bol() && whole_match_p("__END__", 7, 0)) {
	    ruby__end__seen = 1;
	    parser->eofp = 1;
#ifndef RIPPER
	    return -1;
#else
            lex_goto_eol(parser);
            dispatch_scan_event(k__END__);
            return 0;
#endif
	}
	newtok();
	break;

      default:
	if (!parser_is_identchar()) {
	    compile_error(PARSER_ARG  "Invalid char `\\x%02X' in expression", c);
	    goto retry;
	}

	newtok();
	break;
    }

    return parse_ident(parser, c, cmd_state);
}

static enum yytokentype
yylex(YYSTYPE *lval, YYLTYPE *yylloc, struct parser_params *parser)
{
    enum yytokentype t;

    parser->lval = lval;
    lval->val = Qundef;
    t = parser_yylex(parser);
    if (has_delayed_token())
	dispatch_delayed_token(t);
    else if (t != 0)
	dispatch_scan_event(t);

    if (lex_strterm && (lex_strterm->flags & STRTERM_HEREDOC))
	RUBY_SET_YYLLOC_FROM_STRTERM_HEREDOC(*yylloc);
    else
	RUBY_SET_YYLLOC(*yylloc);

    return t;
}

#define LVAR_USED ((ID)1 << (sizeof(ID) * CHAR_BIT - 1))

static NODE*
node_newnode(struct parser_params *parser, enum node_type type, VALUE a0, VALUE a1, VALUE a2)
{
    NODE *n = rb_ast_newnode(parser->ast);

    rb_node_init(n, type, a0, a1, a2);

    nd_set_line(n, ruby_sourceline);
    /* mark not cared lineno to 0 and column to -1 */
    nd_set_first_lineno(n,  0);
    nd_set_first_column(n, -1);
    nd_set_last_lineno(n,  0);
    nd_set_last_column(n, -1);
    return n;
}

#ifndef RIPPER
static enum node_type
nodetype(NODE *node)			/* for debug */
{
    return (enum node_type)nd_type(node);
}

static int
nodeline(NODE *node)
{
    return nd_line(node);
}

static NODE*
newline_node(NODE *node)
{
    if (node) {
	node = remove_begin(node);
	node->flags |= NODE_FL_NEWLINE;
    }
    return node;
}

static void
fixpos(NODE *node, NODE *orig)
{
    if (!node) return;
    if (!orig) return;
    nd_set_line(node, nd_line(orig));
}

static void
parser_warning(struct parser_params *parser, NODE *node, const char *mesg)
{
    rb_compile_warning(ruby_sourcefile, nd_line(node), "%s", mesg);
}
#define parser_warning(node, mesg) parser_warning(parser, (node), (mesg))

static void
parser_warn(struct parser_params *parser, NODE *node, const char *mesg)
{
    rb_compile_warn(ruby_sourcefile, nd_line(node), "%s", mesg);
}
#define parser_warn(node, mesg) parser_warn(parser, (node), (mesg))

static NODE *
nd_set_loc(NODE *nd, const YYLTYPE *location)
{
    nd->nd_loc = *location;
    nd_set_line(nd, location->first_loc.lineno);
    return nd;
}

static NODE*
block_append_gen(struct parser_params *parser, NODE *head, NODE *tail, const YYLTYPE *location)
{
    NODE *end, *h = head, *nd;

    if (tail == 0) return head;

    if (h == 0) return tail;
    switch (nd_type(h)) {
      case NODE_LIT:
      case NODE_STR:
      case NODE_SELF:
      case NODE_TRUE:
      case NODE_FALSE:
      case NODE_NIL:
	parser_warning(h, "unused literal ignored");
	return tail;
      default:
	h = end = NEW_BLOCK(head);
	end->nd_end = end;
	nd_set_loc(end, location);
	head = end;
	break;
      case NODE_BLOCK:
	end = h->nd_end;
	break;
    }

    nd = end->nd_head;
    switch (nd_type(nd)) {
      case NODE_RETURN:
      case NODE_BREAK:
      case NODE_NEXT:
      case NODE_REDO:
      case NODE_RETRY:
	if (RTEST(ruby_verbose)) {
	    parser_warning(tail, "statement not reached");
	}
	break;

      default:
	break;
    }

    if (nd_type(tail) != NODE_BLOCK) {
	tail = NEW_BLOCK(tail);
	nd_set_loc(tail, location);
	tail->nd_end = tail;
    }
    end->nd_next = tail;
    h->nd_end = tail->nd_end;
    nd_set_last_loc(head, nd_last_loc(tail));
    return head;
}

/* append item to the list */
static NODE*
list_append_gen(struct parser_params *parser, NODE *list, NODE *item)
{
    NODE *last;

    if (list == 0) return new_list(item, &item->nd_loc);
    if (list->nd_next) {
	last = list->nd_next->nd_end;
    }
    else {
	last = list;
    }

    list->nd_alen += 1;
    last->nd_next = new_list(item, &item->nd_loc);
    list->nd_next->nd_end = last->nd_next;

    nd_set_last_loc(list, nd_last_loc(item));

    return list;
}

/* concat two lists */
static NODE*
list_concat(NODE *head, NODE *tail)
{
    NODE *last;

    if (head->nd_next) {
	last = head->nd_next->nd_end;
    }
    else {
	last = head;
    }

    head->nd_alen += tail->nd_alen;
    last->nd_next = tail;
    if (tail->nd_next) {
	head->nd_next->nd_end = tail->nd_next->nd_end;
    }
    else {
	head->nd_next->nd_end = tail;
    }

    nd_set_last_loc(head, nd_last_loc(tail));

    return head;
}

static int
literal_concat0(struct parser_params *parser, VALUE head, VALUE tail)
{
    if (NIL_P(tail)) return 1;
    if (!rb_enc_compatible(head, tail)) {
	compile_error(PARSER_ARG "string literal encodings differ (%s / %s)",
		      rb_enc_name(rb_enc_get(head)),
		      rb_enc_name(rb_enc_get(tail)));
	rb_str_resize(head, 0);
	rb_str_resize(tail, 0);
	return 0;
    }
    rb_str_buf_append(head, tail);
    return 1;
}

/* concat two string literals */
static NODE *
literal_concat_gen(struct parser_params *parser, NODE *head, NODE *tail, const YYLTYPE *location)
{
    enum node_type htype;
    NODE *headlast;
    VALUE lit;

    if (!head) return tail;
    if (!tail) return head;

    htype = nd_type(head);
    if (htype == NODE_EVSTR) {
	NODE *node = new_dstr(STR_NEW0(), location);
	head = list_append(node, head);
	htype = NODE_DSTR;
    }
    if (heredoc_indent > 0) {
	switch (htype) {
	  case NODE_STR:
	    nd_set_type(head, NODE_DSTR);
	  case NODE_DSTR:
	    return list_append(head, tail);
	  default:
	    break;
	}
    }
    switch (nd_type(tail)) {
      case NODE_STR:
	if (htype == NODE_DSTR && (headlast = head->nd_next->nd_end->nd_head) &&
	    nd_type(headlast) == NODE_STR) {
	    htype = NODE_STR;
	    lit = headlast->nd_lit;
	}
	else {
	    lit = head->nd_lit;
	}
	if (htype == NODE_STR) {
	    if (!literal_concat0(parser, lit, tail->nd_lit)) {
	      error:
		rb_discard_node(head);
		rb_discard_node(tail);
		return 0;
	    }
	    rb_discard_node(tail);
	}
	else {
	    list_append(head, tail);
	}
	break;

      case NODE_DSTR:
	if (htype == NODE_STR) {
	    if (!literal_concat0(parser, head->nd_lit, tail->nd_lit))
		goto error;
	    tail->nd_lit = head->nd_lit;
	    rb_discard_node(head);
	    head = tail;
	}
	else if (NIL_P(tail->nd_lit)) {
	  append:
	    head->nd_alen += tail->nd_alen - 1;
	    head->nd_next->nd_end->nd_next = tail->nd_next;
	    head->nd_next->nd_end = tail->nd_next->nd_end;
	    rb_discard_node(tail);
	}
	else if (htype == NODE_DSTR && (headlast = head->nd_next->nd_end->nd_head) &&
		 nd_type(headlast) == NODE_STR) {
	    lit = headlast->nd_lit;
	    if (!literal_concat0(parser, lit, tail->nd_lit))
		goto error;
	    tail->nd_lit = Qnil;
	    goto append;
	}
	else {
	    nd_set_type(tail, NODE_ARRAY);
	    tail->nd_head = new_str(tail->nd_lit, location);
	    list_concat(head, tail);
	}
	break;

      case NODE_EVSTR:
	if (htype == NODE_STR) {
	    nd_set_type(head, NODE_DSTR);
	    head->nd_alen = 1;
	}
	list_append(head, tail);
	break;
    }
    return head;
}

static NODE *
evstr2dstr_gen(struct parser_params *parser, NODE *node)
{
    if (nd_type(node) == NODE_EVSTR) {
	node = list_append(new_dstr(STR_NEW0(), &node->nd_loc), node);
    }
    return node;
}

static NODE *
new_evstr_gen(struct parser_params *parser, NODE *node, const YYLTYPE *location)
{
    NODE *head = node;
    NODE *evstr;

    if (node) {
	switch (nd_type(node)) {
	  case NODE_STR: case NODE_DSTR: case NODE_EVSTR:
	    return node;
	}
    }
    evstr = NEW_EVSTR(head);
    nd_set_loc(evstr, location);
    return evstr;
}

static NODE *
call_bin_op_gen(struct parser_params *parser, NODE *recv, ID id, NODE *arg1,
		const YYLTYPE *op_loc, const YYLTYPE *location)
{
    NODE *expr;
    value_expr(recv);
    value_expr(arg1);
    expr = NEW_OPCALL(recv, id, new_list(arg1, &arg1->nd_loc));
    nd_set_line(expr, op_loc->first_loc.lineno);
    expr->nd_loc = *location;
    return expr;
}

static NODE *
call_uni_op_gen(struct parser_params *parser, NODE *recv, ID id, const YYLTYPE *op_loc, const YYLTYPE *location)
{
    NODE *opcall;
    value_expr(recv);
    opcall = NEW_OPCALL(recv, id, 0);
    opcall->nd_loc = *location;
    nd_set_line(opcall, op_loc->first_loc.lineno);
    return opcall;
}

static NODE *
new_qcall_gen(struct parser_params* parser, ID atype, NODE *recv, ID mid, NODE *args, const YYLTYPE *location)
{
    NODE *qcall = NEW_QCALL(atype, recv, mid, args);
    qcall->nd_loc = *location;
    return qcall;
}

#define nd_once_body(node) (nd_type(node) == NODE_SCOPE ? (node)->nd_body : node)
static NODE*
match_op_gen(struct parser_params *parser, NODE *node1, NODE *node2, const YYLTYPE *op_loc, const YYLTYPE *location)
{
    NODE *n;
    int line = op_loc->first_loc.lineno;

    value_expr(node1);
    value_expr(node2);
    if (node1 && (n = nd_once_body(node1)) != 0) {
	switch (nd_type(n)) {
	  case NODE_DREGX:
	    {
		NODE *match = NEW_MATCH2(node1, node2);
		match->nd_loc = *location;
		nd_set_line(match, line);
		return match;
	    }

	  case NODE_LIT:
	    if (RB_TYPE_P(n->nd_lit, T_REGEXP)) {
		const VALUE lit = n->nd_lit;
		NODE *match = NEW_MATCH2(node1, node2);
		match->nd_args = reg_named_capture_assign(lit, location);
		match->nd_loc = *location;
		nd_set_line(match, line);
		return match;
	    }
	}
    }

    if (node2 && (n = nd_once_body(node2)) != 0) {
        NODE *match3;

	switch (nd_type(n)) {
	  case NODE_LIT:
	    if (!RB_TYPE_P(n->nd_lit, T_REGEXP)) break;
	    /* fallthru */
	  case NODE_DREGX:
	    match3 = NEW_MATCH3(node2, node1);
	    match3->nd_loc = *location;
	    nd_set_line(match3, line);
	    return match3;
	}
    }

    n = new_call(node1, tMATCH, new_list(node2, &node2->nd_loc), location);
    nd_set_line(n, line);
    return n;
}

# if WARN_PAST_SCOPE
static int
past_dvar_p(struct parser_params *parser, ID id)
{
    struct vtable *past = lvtbl->past;
    while (past) {
	if (vtable_included(past, id)) return 1;
	past = past->prev;
    }
    return 0;
}
# endif

static NODE*
gettable_gen(struct parser_params *parser, ID id, const YYLTYPE *location)
{
    ID *vidp = NULL;
    NODE *node;
    switch (id) {
      case keyword_self:
	node = NEW_SELF();
	nd_set_loc(node, location);
	return node;
      case keyword_nil:
	node = NEW_NIL();
	nd_set_loc(node, location);
	return node;
      case keyword_true:
	node = NEW_TRUE();
	nd_set_loc(node, location);
	return node;
      case keyword_false:
	node = NEW_FALSE();
	nd_set_loc(node, location);
	return node;
      case keyword__FILE__:
	node = new_str(rb_str_dup(ruby_sourcefile_string), location);
	return node;
      case keyword__LINE__:
	return new_lit(INT2FIX(tokline), location);
      case keyword__ENCODING__:
	return new_lit(rb_enc_from_encoding(current_enc), location);
    }
    switch (id_type(id)) {
      case ID_LOCAL:
	if (dyna_in_block() && dvar_defined_ref(id, vidp)) {
	    if (id == current_arg) {
		rb_warn1("circular argument reference - %"PRIsWARN, rb_id2str(id));
	    }
	    if (vidp) *vidp |= LVAR_USED;
	    node = new_dvar(id, location);
	    return node;
	}
	if (local_id_ref(id, vidp)) {
	    if (id == current_arg) {
		rb_warn1("circular argument reference - %"PRIsWARN, rb_id2str(id));
	    }
	    if (vidp) *vidp |= LVAR_USED;
	    node = new_lvar(id, location);
	    return node;
	}
# if WARN_PAST_SCOPE
	if (!in_defined && RTEST(ruby_verbose) && past_dvar_p(parser, id)) {
	    rb_warning1("possible reference to past scope - %"PRIsWARN, rb_id2str(id));
	}
# endif
	/* method call without arguments */
	node = NEW_VCALL(id);
	nd_set_loc(node, location);
	return node;
      case ID_GLOBAL:
	node = new_gvar(id, location);
	return node;
      case ID_INSTANCE:
	node = new_ivar(id, location);
	return node;
      case ID_CONST:
	node = NEW_CONST(id);
	nd_set_loc(node, location);
	return node;
      case ID_CLASS:
	node = NEW_CVAR(id);
	nd_set_loc(node, location);
	return node;
    }
    compile_error(PARSER_ARG "identifier %"PRIsVALUE" is not valid to get", rb_id2str(id));
    return 0;
}

static NODE *
opt_arg_append(NODE *opt_list, NODE *opt)
{
    NODE *opts = opt_list;
    opts->nd_loc.last_loc = opt->nd_loc.last_loc;

    while (opts->nd_next) {
	opts = opts->nd_next;
	opts->nd_loc.last_loc = opt->nd_loc.last_loc;
    }
    opts->nd_next = opt;

    return opt_list;
}

static NODE *
kwd_append(NODE *kwlist, NODE *kw)
{
    if (kwlist) {
	NODE *kws = kwlist;
	kws->nd_loc.last_loc = kw->nd_loc.last_loc;
	while (kws->nd_next) {
	    kws = kws->nd_next;
	    kws->nd_loc.last_loc = kw->nd_loc.last_loc;
	}
	kws->nd_next = kw;
    }
    return kwlist;
}

static NODE *
new_defined_gen(struct parser_params *parser, NODE *expr, const YYLTYPE *location)
{
    NODE *defined = NEW_DEFINED(remove_begin_all(expr));
    nd_set_loc(defined, location);
    return defined;
}

static NODE *
new_regexp_gen(struct parser_params *parser, NODE *node, int options, const YYLTYPE *location)
{
    NODE *list, *prev;
    VALUE lit;

    if (!node) {
	return new_lit(reg_compile(STR_NEW0(), options), location);
    }
    switch (nd_type(node)) {
      case NODE_STR:
	{
	    VALUE src = node->nd_lit;
	    nd_set_type(node, NODE_LIT);
	    nd_set_loc(node, location);
	    add_mark_object(node->nd_lit = reg_compile(src, options));
	}
	break;
      default:
	add_mark_object(lit = STR_NEW0());
	node = NEW_NODE(NODE_DSTR, lit, 1, new_list(node, location));
      case NODE_DSTR:
	nd_set_type(node, NODE_DREGX);
	nd_set_loc(node, location);
	node->nd_cflag = options & RE_OPTION_MASK;
	if (!NIL_P(node->nd_lit)) reg_fragment_check(node->nd_lit, options);
	for (list = (prev = node)->nd_next; list; list = list->nd_next) {
	    if (nd_type(list->nd_head) == NODE_STR) {
		VALUE tail = list->nd_head->nd_lit;
		if (reg_fragment_check(tail, options) && prev && !NIL_P(prev->nd_lit)) {
		    VALUE lit = prev == node ? prev->nd_lit : prev->nd_head->nd_lit;
		    if (!literal_concat0(parser, lit, tail)) {
			node = 0;
			break;
		    }
		    rb_str_resize(tail, 0);
		    prev->nd_next = list->nd_next;
		    rb_discard_node(list->nd_head);
		    rb_discard_node(list);
		    list = prev;
		}
		else {
		    prev = list;
		}
	    }
	    else {
		prev = 0;
	    }
	}
	if (!node->nd_next) {
	    VALUE src = node->nd_lit;
	    nd_set_type(node, NODE_LIT);
	    add_mark_object(node->nd_lit = reg_compile(src, options));
	}
	if (options & RE_OPTION_ONCE) {
	    node = NEW_NODE(NODE_SCOPE, 0, node, 0);
	    nd_set_loc(node, location);
	}
	break;
    }
    return node;
}

static NODE *
new_lit_gen(struct parser_params *parser, VALUE sym, const YYLTYPE *location)
{
    NODE *lit = NEW_LIT(sym);
    add_mark_object(sym);
    nd_set_loc(lit, location);
    return lit;
}

static NODE *
new_list_gen(struct parser_params *parser, NODE *item, const YYLTYPE *location)
{
    NODE *list = NEW_LIST(item);
    nd_set_loc(list, location);
    return list;
}

static NODE *
new_str_gen(struct parser_params *parser, VALUE str, const YYLTYPE *location)
{
    NODE *nd_str = NEW_STR(str);
    add_mark_object(str);
    nd_set_loc(nd_str, location);
    return nd_str;
}

static NODE *
new_dvar_gen(struct parser_params *parser, ID id, const YYLTYPE *location)
{
    NODE *dvar = NEW_DVAR(id);
    nd_set_loc(dvar, location);
    return dvar;
}

static NODE *
new_resbody_gen(struct parser_params *parser, NODE *exc_list, NODE *stmt, NODE *rescue, const YYLTYPE *location)
{
    NODE *resbody = NEW_RESBODY(exc_list, stmt, rescue);
    nd_set_loc(resbody, location);
    return resbody;
}

static NODE *
new_errinfo_gen(struct parser_params *parser, const YYLTYPE *location)
{
    NODE *errinfo = NEW_ERRINFO();
    nd_set_loc(errinfo, location);
    return errinfo;
}

static NODE *
new_call_gen(struct parser_params *parser, NODE *recv, ID mid, NODE *args, const YYLTYPE *location)
{
    NODE *call = NEW_CALL(recv, mid, args);
    nd_set_loc(call, location);
    return call;
}

static NODE *
new_fcall_gen(struct parser_params *parser, ID mid, NODE *args, const YYLTYPE *location)
{
    NODE *fcall = NEW_FCALL(mid, args);
    nd_set_loc(fcall, location);
    return fcall;
}

static NODE *
new_for_gen(struct parser_params *parser, NODE *var, NODE *iter, NODE *body, const YYLTYPE *location)
{
    NODE *nd_for = NEW_FOR(var, iter, body);
    nd_set_loc(nd_for, location);
    return nd_for;
}

static NODE *
new_gvar_gen(struct parser_params *parser, ID id, const YYLTYPE *location)
{
    NODE *gvar = NEW_GVAR(id);
    nd_set_loc(gvar, location);
    return gvar;
}

static NODE *
new_lvar_gen(struct parser_params *parser, ID id, const YYLTYPE *location)
{
    NODE *lvar = NEW_LVAR(id);
    nd_set_loc(lvar, location);
    return lvar;
}

static NODE *
new_dstr_gen(struct parser_params *parser, VALUE str, const YYLTYPE *location)
{
    NODE *dstr = NEW_DSTR(str);
    add_mark_object(str);
    nd_set_loc(dstr, location);
    return dstr;
}

static NODE *
new_rescue_gen(struct parser_params *parser, NODE *b, NODE *res, NODE *e, const YYLTYPE *location)
{
    NODE *rescue = NEW_RESCUE(b, res, e);
    nd_set_loc(rescue, location);
    return rescue;
}

static NODE *
new_undef_gen(struct parser_params *parser, NODE *i, const YYLTYPE *location)
{
    NODE *undef = NEW_UNDEF(i);
    nd_set_loc(undef, location);
    return undef;
}

static NODE *
new_zarray_gen(struct parser_params *parser, const YYLTYPE *location)
{
    NODE *zarray = NEW_ZARRAY();
    nd_set_loc(zarray, location);
    return zarray;
}

static NODE *
new_ivar_gen(struct parser_params *parser, ID id, const YYLTYPE *location)
{
    NODE *ivar = NEW_IVAR(id);
    nd_set_loc(ivar, location);
    return ivar;
}

static NODE *
new_postarg_gen(struct parser_params *parser, NODE *i, NODE *v, const YYLTYPE *location)
{
    NODE *postarg = NEW_POSTARG(i, v);
    nd_set_loc(postarg, location);
    return postarg;
}

static NODE *
new_cdecl_gen(struct parser_params *parser, ID v, NODE *val, NODE *path, const YYLTYPE *location)
{
    NODE *nd_cdecl = NEW_CDECL(v, val, path);
    nd_set_loc(nd_cdecl, location);
    return nd_cdecl;
}

static NODE *
new_scope_gen(struct parser_params *parser, NODE *a, NODE *b, const YYLTYPE *location)
{
    NODE *scope = NEW_SCOPE(a, b);
    nd_set_loc(scope, location);
    return scope;
}

static NODE *
new_begin_gen(struct parser_params *parser, NODE *b, const YYLTYPE *location)
{
    NODE *begin = NEW_BEGIN(b);
    nd_set_loc(begin, location);
    return begin;
}

static NODE *
new_masgn_gen(struct parser_params *parser, NODE *l, NODE *r, const YYLTYPE *location)
{
    NODE *masgn = NEW_MASGN(l, r);
    nd_set_loc(masgn, location);
    return masgn;
}


static NODE *
new_kw_arg_gen(struct parser_params *parser, NODE *k, const YYLTYPE *location)
{
    NODE *kw_arg;
    if (!k) return 0;
    kw_arg = NEW_KW_ARG(0, (k));
    nd_set_loc(kw_arg, location);
    return kw_arg;
}

static NODE *
new_xstring_gen(struct parser_params *parser, NODE *node, const YYLTYPE *location)
{
    if (!node) {
	VALUE lit = STR_NEW0();
	NODE *xstr = NEW_XSTR(lit);
	add_mark_object(lit);
	xstr->nd_loc = *location;
	return xstr;
    }
    switch (nd_type(node)) {
      case NODE_STR:
	nd_set_type(node, NODE_XSTR);
	nd_set_loc(node, location);
	break;
      case NODE_DSTR:
	nd_set_type(node, NODE_DXSTR);
	nd_set_loc(node, location);
	break;
      default:
	node = NEW_NODE(NODE_DXSTR, Qnil, 1, new_list(node, location));
	nd_set_loc(node, location);
	break;
    }
    return node;
}

static NODE *
new_body_gen(struct parser_params *parser, NODE *param, NODE *stmt, const YYLTYPE *location)
{
    NODE *iter = NEW_ITER(param, stmt);
    nd_set_loc(iter->nd_body, location);
    nd_set_loc(iter, location);
    return iter;

}
#else  /* !RIPPER */
static int
id_is_var_gen(struct parser_params *parser, ID id)
{
    if (is_notop_id(id)) {
	switch (id & ID_SCOPE_MASK) {
	  case ID_GLOBAL: case ID_INSTANCE: case ID_CONST: case ID_CLASS:
	    return 1;
	  case ID_LOCAL:
	    if (dyna_in_block() && dvar_defined(id)) return 1;
	    if (local_id(id)) return 1;
	    /* method call without arguments */
	    return 0;
	}
    }
    compile_error(PARSER_ARG "identifier %"PRIsVALUE" is not valid to get", rb_id2str(id));
    return 0;
}

static VALUE
new_regexp_gen(struct parser_params *parser, VALUE re, VALUE opt)
{
    VALUE src = 0, err;
    int options = 0;
    if (ripper_is_node_yylval(re)) {
	src = RNODE(re)->nd_cval;
	re = RNODE(re)->nd_rval;
    }
    if (ripper_is_node_yylval(opt)) {
	options = (int)RNODE(opt)->nd_tag;
	opt = RNODE(opt)->nd_rval;
    }
    if (src && NIL_P(parser_reg_compile(parser, src, options, &err))) {
	compile_error(PARSER_ARG "%"PRIsVALUE, err);
    }
    return dispatch2(regexp_literal, re, opt);
}

static VALUE
new_xstring_gen(struct parser_params *parser, VALUE str)
{
    return dispatch1(xstring_literal, str);
}
#endif /* !RIPPER */

#ifndef RIPPER
const char rb_parser_lex_state_names[][13] = {
    "EXPR_BEG",    "EXPR_END",    "EXPR_ENDARG", "EXPR_ENDFN",  "EXPR_ARG",
    "EXPR_CMDARG", "EXPR_MID",    "EXPR_FNAME",  "EXPR_DOT",    "EXPR_CLASS",
    "EXPR_LABEL",  "EXPR_LABELED","EXPR_FITEM",
};

static VALUE
append_lex_state_name(enum lex_state_e state, VALUE buf)
{
    int i, sep = 0;
    unsigned int mask = 1;
    static const char none[] = "EXPR_NONE";

    for (i = 0; i < EXPR_MAX_STATE; ++i, mask <<= 1) {
	if ((unsigned)state & mask) {
	    if (sep) {
		rb_str_cat(buf, "|", 1);
	    }
	    sep = 1;
	    rb_str_cat_cstr(buf, rb_parser_lex_state_names[i]);
	}
    }
    if (!sep) {
	rb_str_cat(buf, none, sizeof(none)-1);
    }
    return buf;
}

static void
flush_debug_buffer(struct parser_params *parser, VALUE out, VALUE str)
{
    VALUE mesg = parser->debug_buffer;

    if (!NIL_P(mesg) && RSTRING_LEN(mesg)) {
	parser->debug_buffer = Qnil;
	rb_io_puts(1, &mesg, out);
    }
    if (!NIL_P(str) && RSTRING_LEN(str)) {
	rb_io_write(parser->debug_output, str);
    }
}

enum lex_state_e
rb_parser_trace_lex_state(struct parser_params *parser, enum lex_state_e from,
			  enum lex_state_e to, int line)
{
    VALUE mesg;
    mesg = rb_str_new_cstr("lex_state: ");
    append_lex_state_name(from, mesg);
    rb_str_cat_cstr(mesg, " -> ");
    append_lex_state_name(to, mesg);
    rb_str_catf(mesg, " at line %d\n", line);
    flush_debug_buffer(parser, parser->debug_output, mesg);
    return to;
}

VALUE
rb_parser_lex_state_name(enum lex_state_e state)
{
    return rb_fstring(append_lex_state_name(state, rb_str_new(0, 0)));
}

static void
append_bitstack_value(stack_type stack, VALUE mesg)
{
    if (stack == 0) {
	rb_str_cat_cstr(mesg, "0");
    }
    else {
	stack_type mask = (stack_type)1U << (CHAR_BIT * sizeof(stack_type) - 1);
	for (; mask && !(stack & mask); mask >>= 1) continue;
	for (; mask; mask >>= 1) rb_str_cat(mesg, stack & mask ? "1" : "0", 1);
    }
}

void
rb_parser_show_bitstack(struct parser_params *parser, stack_type stack,
			const char *name, int line)
{
    VALUE mesg = rb_sprintf("%s: ", name);
    append_bitstack_value(stack, mesg);
    rb_str_catf(mesg, " at line %d\n", line);
    flush_debug_buffer(parser, parser->debug_output, mesg);
}

void
rb_parser_fatal(struct parser_params *parser, const char *fmt, ...)
{
    va_list ap;
    VALUE mesg = rb_str_new_cstr("internal parser error: ");

    va_start(ap, fmt);
    rb_str_vcatf(mesg, fmt, ap);
    va_end(ap);
#ifndef RIPPER
    parser_yyerror(parser, RSTRING_PTR(mesg));
    RB_GC_GUARD(mesg);
#else
    dispatch1(parse_error, mesg);
    ripper_error();
#endif /* !RIPPER */

    mesg = rb_str_new(0, 0);
    append_lex_state_name(lex_state, mesg);
    compile_error(PARSER_ARG "lex_state: %"PRIsVALUE, mesg);
    rb_str_resize(mesg, 0);
    append_bitstack_value(cond_stack, mesg);
    compile_error(PARSER_ARG "cond_stack: %"PRIsVALUE, mesg);
    rb_str_resize(mesg, 0);
    append_bitstack_value(cmdarg_stack, mesg);
    compile_error(PARSER_ARG "cmdarg_stack: %"PRIsVALUE, mesg);
    if (parser->debug_output == rb_stdout)
	parser->debug_output = rb_stderr;
    yydebug = TRUE;
}

void
rb_parser_set_location_from_strterm_heredoc(struct parser_params *parser, rb_strterm_heredoc_t *here, YYLTYPE *yylloc)
{
    const char *eos = RSTRING_PTR(here->term);
    int term_len = (int)eos[0];

    yylloc->first_loc.lineno = (int)here->sourceline;
    yylloc->first_loc.column = (int)(here->u3.lastidx - term_len);
    yylloc->last_loc.lineno  = (int)here->sourceline;
    yylloc->last_loc.column  = (int)(here->u3.lastidx);
}

void
rb_parser_set_location_of_none(struct parser_params *parser, YYLTYPE *yylloc)
{
    yylloc->first_loc.lineno = ruby_sourceline;
    yylloc->first_loc.column = (int)(parser->tokp - lex_pbeg);
    yylloc->last_loc.lineno = ruby_sourceline;
    yylloc->last_loc.column = (int)(parser->tokp - lex_pbeg);
}

void
rb_parser_set_location(struct parser_params *parser, YYLTYPE *yylloc)
{
    yylloc->first_loc.lineno = ruby_sourceline;
    yylloc->first_loc.column = (int)(parser->tokp - lex_pbeg);
    yylloc->last_loc.lineno = ruby_sourceline;
    yylloc->last_loc.column = (int)(lex_p - lex_pbeg);
}
#endif /* !RIPPER */

#ifndef RIPPER
static NODE*
assignable_result0(NODE *node, const YYLTYPE *location)
{
    if (node) {
	nd_set_loc(node, location);
    }
    return node;
}
#endif /* !RIPPER */

#ifdef RIPPER
static VALUE
assignable_gen(struct parser_params *parser, VALUE lhs)
#else
static NODE*
assignable_gen(struct parser_params *parser, ID id, NODE *val, const YYLTYPE *location)
#endif
{
#ifdef RIPPER
    ID id = get_id(lhs);
# define assignable_result(x) (lhs)
# define parser_yyerror(parser, x) (lhs = assign_error_gen(parser, lhs))
#else
# define assignable_result(x) assignable_result0(x, location)
#endif
    if (!id) return assignable_result(0);
    switch (id) {
      case keyword_self:
	yyerror0("Can't change the value of self");
	goto error;
      case keyword_nil:
	yyerror0("Can't assign to nil");
	goto error;
      case keyword_true:
	yyerror0("Can't assign to true");
	goto error;
      case keyword_false:
	yyerror0("Can't assign to false");
	goto error;
      case keyword__FILE__:
	yyerror0("Can't assign to __FILE__");
	goto error;
      case keyword__LINE__:
	yyerror0("Can't assign to __LINE__");
	goto error;
      case keyword__ENCODING__:
	yyerror0("Can't assign to __ENCODING__");
	goto error;
    }
    switch (id_type(id)) {
      case ID_LOCAL:
	if (dyna_in_block()) {
	    if (dvar_curr(id)) {
		return assignable_result(NEW_DASGN_CURR(id, val));
	    }
	    else if (dvar_defined(id)) {
		return assignable_result(NEW_DASGN(id, val));
	    }
	    else if (local_id(id)) {
		return assignable_result(NEW_LASGN(id, val));
	    }
	    else {
		dyna_var(id);
		return assignable_result(NEW_DASGN_CURR(id, val));
	    }
	}
	else {
	    if (!local_id(id)) {
		local_var(id);
	    }
	    return assignable_result(NEW_LASGN(id, val));
	}
	break;
      case ID_GLOBAL:
	return assignable_result(NEW_GASGN(id, val));
      case ID_INSTANCE:
	return assignable_result(NEW_IASGN(id, val));
      case ID_CONST:
	if (!in_def)
	    return assignable_result(new_cdecl(id, val, 0, location));
	yyerror0("dynamic constant assignment");
	break;
      case ID_CLASS:
	return assignable_result(NEW_CVASGN(id, val));
      default:
	compile_error(PARSER_ARG "identifier %"PRIsVALUE" is not valid to set", rb_id2str(id));
    }
  error:
    return assignable_result(0);
#undef assignable_result
#undef parser_yyerror
}

static int
is_private_local_id(ID name)
{
    VALUE s;
    if (name == idUScore) return 1;
    if (!is_local_id(name)) return 0;
    s = rb_id2str(name);
    if (!s) return 0;
    return RSTRING_PTR(s)[0] == '_';
}

static int
shadowing_lvar_0(struct parser_params *parser, ID name)
{
    if (is_private_local_id(name)) return 1;
    if (dyna_in_block()) {
	if (dvar_curr(name)) {
	    yyerror0("duplicated argument name");
	}
	else if (dvar_defined(name) || local_id(name)) {
	    rb_warning1("shadowing outer local variable - %"PRIsWARN, rb_id2str(name));
	    vtable_add(lvtbl->vars, name);
	    if (lvtbl->used) {
		vtable_add(lvtbl->used, (ID)ruby_sourceline | LVAR_USED);
	    }
	    return 0;
	}
    }
    else {
	if (local_id(name)) {
	    yyerror0("duplicated argument name");
	}
    }
    return 1;
}

static ID
shadowing_lvar_gen(struct parser_params *parser, ID name)
{
    shadowing_lvar_0(parser, name);
    return name;
}

static void
new_bv_gen(struct parser_params *parser, ID name)
{
    if (!name) return;
    if (!is_local_id(name)) {
	compile_error(PARSER_ARG "invalid local variable - %"PRIsVALUE,
		      rb_id2str(name));
	return;
    }
    if (!shadowing_lvar_0(parser, name)) return;
    dyna_var(name);
}

#ifndef RIPPER
static NODE *
aryset_gen(struct parser_params *parser, NODE *recv, NODE *idx, const YYLTYPE *location)
{
    NODE *attrasgn = NEW_ATTRASGN(recv, tASET, idx);
    nd_set_loc(attrasgn, location);
    return attrasgn;
}

static void
block_dup_check_gen(struct parser_params *parser, NODE *node1, NODE *node2)
{
    if (node2 && node1 && nd_type(node1) == NODE_BLOCK_PASS) {
	compile_error(PARSER_ARG "both block arg and actual block given");
    }
}

static NODE *
attrset_gen(struct parser_params *parser, NODE *recv, ID atype, ID id, const YYLTYPE *location)
{
    NODE *attrasgn;
    if (!CALL_Q_P(atype)) id = rb_id_attrset(id);
    attrasgn = NEW_ATTRASGN(recv, id, 0);
    nd_set_loc(attrasgn, location);
    return attrasgn;
}

static void
rb_backref_error_gen(struct parser_params *parser, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_NTH_REF:
	compile_error(PARSER_ARG "Can't set variable $%ld", node->nd_nth);
	break;
      case NODE_BACK_REF:
	compile_error(PARSER_ARG "Can't set variable $%c", (int)node->nd_nth);
	break;
    }
}

static NODE *
arg_concat_gen(struct parser_params *parser, NODE *node1, NODE *node2, const YYLTYPE *location)
{
    NODE *argscat;

    if (!node2) return node1;
    switch (nd_type(node1)) {
      case NODE_BLOCK_PASS:
	if (node1->nd_head)
	    node1->nd_head = arg_concat(node1->nd_head, node2, location);
	else
	    node1->nd_head = new_list(node2, location);
	return node1;
      case NODE_ARGSPUSH:
	if (nd_type(node2) != NODE_ARRAY) break;
	node1->nd_body = list_concat(new_list(node1->nd_body, location), node2);
	nd_set_type(node1, NODE_ARGSCAT);
	return node1;
      case NODE_ARGSCAT:
	if (nd_type(node2) != NODE_ARRAY ||
	    nd_type(node1->nd_body) != NODE_ARRAY) break;
	node1->nd_body = list_concat(node1->nd_body, node2);
	return node1;
    }
    argscat = NEW_ARGSCAT(node1, node2);
    nd_set_loc(argscat, location);
    return argscat;
}

static NODE *
arg_append_gen(struct parser_params *parser, NODE *node1, NODE *node2, const YYLTYPE *location)
{
    NODE *argspush;

    if (!node1) return new_list(node2, &node2->nd_loc);
    switch (nd_type(node1))  {
      case NODE_ARRAY:
	return list_append(node1, node2);
      case NODE_BLOCK_PASS:
	node1->nd_head = arg_append(node1->nd_head, node2, location);
	node1->nd_loc.last_loc = node1->nd_head->nd_loc.last_loc;
	return node1;
      case NODE_ARGSPUSH:
	node1->nd_body = list_append(new_list(node1->nd_body, &node1->nd_body->nd_loc), node2);
	node1->nd_loc.last_loc = node1->nd_body->nd_loc.last_loc;
	nd_set_type(node1, NODE_ARGSCAT);
	return node1;
    }
    argspush = NEW_ARGSPUSH(node1, node2);
    nd_set_loc(argspush, location);
    return argspush;
}

static NODE *
splat_array(NODE* node)
{
    if (nd_type(node) == NODE_SPLAT) node = node->nd_head;
    if (nd_type(node) == NODE_ARRAY) return node;
    return 0;
}

static void
mark_lvar_used(struct parser_params *parser, NODE *rhs)
{
    ID *vidp = NULL;
    if (!rhs) return;
    switch (nd_type(rhs)) {
      case NODE_LASGN:
	if (local_id_ref(rhs->nd_vid, vidp)) {
	    if (vidp) *vidp |= LVAR_USED;
	}
	break;
      case NODE_DASGN:
      case NODE_DASGN_CURR:
	if (dvar_defined_ref(rhs->nd_vid, vidp)) {
	    if (vidp) *vidp |= LVAR_USED;
	}
	break;
#if 0
      case NODE_MASGN:
	for (rhs = rhs->nd_head; rhs; rhs = rhs->nd_next) {
	    mark_lvar_used(parser, rhs->nd_head);
	}
	break;
#endif
    }
}

static NODE *
node_assign_gen(struct parser_params *parser, NODE *lhs, NODE *rhs, const YYLTYPE *location)
{
    if (!lhs) return 0;

    switch (nd_type(lhs)) {
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_DASGN_CURR:
      case NODE_MASGN:
      case NODE_CDECL:
      case NODE_CVASGN:
	lhs->nd_value = rhs;
	nd_set_loc(lhs, location);
	break;

      case NODE_ATTRASGN:
	lhs->nd_args = arg_append(lhs->nd_args, rhs, location);
	nd_set_loc(lhs, location);
	break;

      default:
	/* should not happen */
	break;
    }

    return lhs;
}

static int
value_expr_gen(struct parser_params *parser, NODE *node)
{
    int cond = 0;

    if (!node) {
	rb_warning0("empty expression");
    }
    while (node) {
	switch (nd_type(node)) {
	  case NODE_RETURN:
	  case NODE_BREAK:
	  case NODE_NEXT:
	  case NODE_REDO:
	  case NODE_RETRY:
	    if (!cond) yyerror0("void value expression");
	    /* or "control never reach"? */
	    return FALSE;

	  case NODE_BLOCK:
	    while (node->nd_next) {
		node = node->nd_next;
	    }
	    node = node->nd_head;
	    break;

	  case NODE_BEGIN:
	    node = node->nd_body;
	    break;

	  case NODE_IF:
	  case NODE_UNLESS:
	    if (!node->nd_body) {
		node = node->nd_else;
		break;
	    }
	    else if (!node->nd_else) {
		node = node->nd_body;
		break;
	    }
	    if (!value_expr(node->nd_body)) return FALSE;
	    node = node->nd_else;
	    break;

	  case NODE_AND:
	  case NODE_OR:
	    cond = 1;
	    node = node->nd_2nd;
	    break;

	  case NODE_LASGN:
	  case NODE_DASGN:
	  case NODE_DASGN_CURR:
	  case NODE_MASGN:
	    mark_lvar_used(parser, node);
	    return TRUE;

	  default:
	    return TRUE;
	}
    }

    return TRUE;
}

static void
void_expr_gen(struct parser_params *parser, NODE *node)
{
    const char *useless = 0;

    if (!RTEST(ruby_verbose)) return;

    if (!node || !(node = nd_once_body(node))) return;
    switch (nd_type(node)) {
      case NODE_OPCALL:
	switch (node->nd_mid) {
	  case '+':
	  case '-':
	  case '*':
	  case '/':
	  case '%':
	  case tPOW:
	  case tUPLUS:
	  case tUMINUS:
	  case '|':
	  case '^':
	  case '&':
	  case tCMP:
	  case '>':
	  case tGEQ:
	  case '<':
	  case tLEQ:
	  case tEQ:
	  case tNEQ:
	    useless = rb_id2name(node->nd_mid);
	    break;
	}
	break;

      case NODE_LVAR:
      case NODE_DVAR:
      case NODE_GVAR:
      case NODE_IVAR:
      case NODE_CVAR:
      case NODE_NTH_REF:
      case NODE_BACK_REF:
	useless = "a variable";
	break;
      case NODE_CONST:
	useless = "a constant";
	break;
      case NODE_LIT:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_DREGX:
	useless = "a literal";
	break;
      case NODE_COLON2:
      case NODE_COLON3:
	useless = "::";
	break;
      case NODE_DOT2:
	useless = "..";
	break;
      case NODE_DOT3:
	useless = "...";
	break;
      case NODE_SELF:
	useless = "self";
	break;
      case NODE_NIL:
	useless = "nil";
	break;
      case NODE_TRUE:
	useless = "true";
	break;
      case NODE_FALSE:
	useless = "false";
	break;
      case NODE_DEFINED:
	useless = "defined?";
	break;
    }

    if (useless) {
	rb_warn1L(nd_line(node), "possibly useless use of %s in void context", WARN_S(useless));
    }
}

static void
void_stmts_gen(struct parser_params *parser, NODE *node)
{
    if (!RTEST(ruby_verbose)) return;
    if (!node) return;
    if (nd_type(node) != NODE_BLOCK) return;

    for (;;) {
	if (!node->nd_next) return;
	void_expr0(node->nd_head);
	node = node->nd_next;
    }
}

static NODE *
remove_begin(NODE *node)
{
    NODE **n = &node, *n1 = node;
    while (n1 && nd_type(n1) == NODE_BEGIN && n1->nd_body) {
	*n = n1 = n1->nd_body;
    }
    return node;
}

static NODE *
remove_begin_all(NODE *node)
{
    NODE **n = &node, *n1 = node;
    while (n1 && nd_type(n1) == NODE_BEGIN) {
	*n = n1 = n1->nd_body;
    }
    return node;
}

static void
reduce_nodes_gen(struct parser_params *parser, NODE **body)
{
    NODE *node = *body;

    if (!node) {
	*body = NEW_NIL();
	return;
    }
#define subnodes(n1, n2) \
    ((!node->n1) ? (node->n2 ? (body = &node->n2, 1) : 0) : \
     (!node->n2) ? (body = &node->n1, 1) : \
     (reduce_nodes(&node->n1), body = &node->n2, 1))

    while (node) {
	int newline = (int)(node->flags & NODE_FL_NEWLINE);
	switch (nd_type(node)) {
	  end:
	  case NODE_NIL:
	    *body = 0;
	    return;
	  case NODE_RETURN:
	    *body = node = node->nd_stts;
	    if (newline && node) node->flags |= NODE_FL_NEWLINE;
	    continue;
	  case NODE_BEGIN:
	    *body = node = node->nd_body;
	    if (newline && node) node->flags |= NODE_FL_NEWLINE;
	    continue;
	  case NODE_BLOCK:
	    body = &node->nd_end->nd_head;
	    break;
	  case NODE_IF:
	  case NODE_UNLESS:
	    if (subnodes(nd_body, nd_else)) break;
	    return;
	  case NODE_CASE:
	    body = &node->nd_body;
	    break;
	  case NODE_WHEN:
	    if (!subnodes(nd_body, nd_next)) goto end;
	    break;
	  case NODE_ENSURE:
	    if (!subnodes(nd_head, nd_resq)) goto end;
	    break;
	  case NODE_RESCUE:
	    if (node->nd_else) {
		body = &node->nd_resq;
		break;
	    }
	    if (!subnodes(nd_head, nd_resq)) goto end;
	    break;
	  default:
	    return;
	}
	node = *body;
	if (newline && node) node->flags |= NODE_FL_NEWLINE;
    }

#undef subnodes
}

static int
is_static_content(NODE *node)
{
    if (!node) return 1;
    switch (nd_type(node)) {
      case NODE_HASH:
	if (!(node = node->nd_head)) break;
      case NODE_ARRAY:
	do {
	    if (!is_static_content(node->nd_head)) return 0;
	} while ((node = node->nd_next) != 0);
      case NODE_LIT:
      case NODE_STR:
      case NODE_NIL:
      case NODE_TRUE:
      case NODE_FALSE:
      case NODE_ZARRAY:
	break;
      default:
	return 0;
    }
    return 1;
}

static int
assign_in_cond(struct parser_params *parser, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_MASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_DASGN_CURR:
      case NODE_GASGN:
      case NODE_IASGN:
	break;

      default:
	return 0;
    }

    if (!node->nd_value) return 1;
    if (is_static_content(node->nd_value)) {
	/* reports always */
	parser_warn(node->nd_value, "found = in conditional, should be ==");
    }
    return 1;
}

static void
warn_unless_e_option(struct parser_params *parser, NODE *node, const char *str)
{
    if (!e_option_supplied(parser)) parser_warn(node, str);
}

static void
warning_unless_e_option(struct parser_params *parser, NODE *node, const char *str)
{
    if (!e_option_supplied(parser)) parser_warning(node, str);
}

static NODE *cond0(struct parser_params*,NODE*,int,const YYLTYPE*);

static NODE*
range_op(struct parser_params *parser, NODE *node, const YYLTYPE *location)
{
    enum node_type type;

    if (node == 0) return 0;

    type = nd_type(node);
    value_expr(node);
    if (type == NODE_LIT && FIXNUM_P(node->nd_lit)) {
	warn_unless_e_option(parser, node, "integer literal in conditional range");
	return new_call(node, tEQ, new_list(new_gvar(rb_intern("$."), location), location), location);
    }
    return cond0(parser, node, FALSE, location);
}

static int
literal_node(NODE *node)
{
    if (!node) return 1;	/* same as NODE_NIL */
    if (!(node = nd_once_body(node))) return 1;
    switch (nd_type(node)) {
      case NODE_LIT:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_EVSTR:
      case NODE_DREGX:
      case NODE_DSYM:
	return 2;
      case NODE_TRUE:
      case NODE_FALSE:
      case NODE_NIL:
	return 1;
    }
    return 0;
}

static NODE*
cond0(struct parser_params *parser, NODE *node, int method_op, const YYLTYPE *location)
{
    if (node == 0) return 0;
    if (!(node = nd_once_body(node))) return 0;
    assign_in_cond(parser, node);

    switch (nd_type(node)) {
      case NODE_DSTR:
      case NODE_EVSTR:
      case NODE_STR:
	if (!method_op) rb_warn0("string literal in condition");
	break;

      case NODE_DREGX:
	{
	    NODE *match;
	    if (!method_op)
		warning_unless_e_option(parser, node, "regex literal in condition");

	    match = NEW_MATCH2(node, new_gvar(idLASTLINE, location));
	    nd_set_loc(match, location);
	    return match;
	}

      case NODE_AND:
      case NODE_OR:
	node->nd_1st = cond0(parser, node->nd_1st, FALSE, location);
	node->nd_2nd = cond0(parser, node->nd_2nd, FALSE, location);
	break;

      case NODE_DOT2:
      case NODE_DOT3:
	node->nd_beg = range_op(parser, node->nd_beg, location);
	node->nd_end = range_op(parser, node->nd_end, location);
	if (nd_type(node) == NODE_DOT2) nd_set_type(node,NODE_FLIP2);
	else if (nd_type(node) == NODE_DOT3) nd_set_type(node, NODE_FLIP3);
	if (!method_op && !e_option_supplied(parser)) {
	    int b = literal_node(node->nd_beg);
	    int e = literal_node(node->nd_end);
	    if ((b == 1 && e == 1) || (b + e >= 2 && RTEST(ruby_verbose))) {
		parser_warn(node, "range literal in condition");
	    }
	}
	break;

      case NODE_DSYM:
	if (!method_op) parser_warning(node, "literal in condition");
	break;

      case NODE_LIT:
	if (RB_TYPE_P(node->nd_lit, T_REGEXP)) {
	    if (!method_op)
		warn_unless_e_option(parser, node, "regex literal in condition");
	    nd_set_type(node, NODE_MATCH);
	}
	else {
	    if (!method_op)
		parser_warning(node, "literal in condition");
	}
      default:
	break;
    }
    return node;
}

static NODE*
cond_gen(struct parser_params *parser, NODE *node, int method_op, const YYLTYPE *location)
{
    if (node == 0) return 0;
    return cond0(parser, node, method_op, location);
}

static NODE*
new_nil_gen(struct parser_params *parser, const YYLTYPE *location)
{
    NODE *node_nil = NEW_NIL();
    nd_set_loc(node_nil, location);
    return node_nil;
}

static NODE*
new_if_gen(struct parser_params *parser, NODE *cc, NODE *left, NODE *right, const YYLTYPE *location)
{
    NODE *node_if;

    if (!cc) return right;
    cc = cond0(parser, cc, FALSE, location);
    node_if = NEW_IF(cc, left, right);
    nd_set_loc(node_if, location);
    return newline_node(node_if);
}

static NODE*
new_unless_gen(struct parser_params *parser, NODE *cc, NODE *left, NODE *right, const YYLTYPE *location)
{
    NODE *node_unless;

    if (!cc) return right;
    cc = cond0(parser, cc, FALSE, location);
    node_unless = NEW_UNLESS(cc, left, right);
    nd_set_loc(node_unless, location);
    return newline_node(node_unless);
}

static NODE*
logop_gen(struct parser_params *parser, enum node_type type, NODE *left, NODE *right,
	  const YYLTYPE *op_loc, const YYLTYPE *location)
{
    NODE *op;
    value_expr(left);
    if (left && (enum node_type)nd_type(left) == type) {
	NODE *node = left, *second;
	while ((second = node->nd_2nd) != 0 && (enum node_type)nd_type(second) == type) {
	    node = second;
	}
	node->nd_2nd = NEW_NODE(type, second, right, 0);
	node->nd_2nd->nd_loc = *location;
	nd_set_line(node->nd_2nd, op_loc->first_loc.lineno);
	left->nd_loc.last_loc = location->last_loc;
	return left;
    }
    op = NEW_NODE(type, left, right, 0);
    op->nd_loc = *location;
    nd_set_line(op, op_loc->first_loc.lineno);
    return op;
}

static void
no_blockarg(struct parser_params *parser, NODE *node)
{
    if (node && nd_type(node) == NODE_BLOCK_PASS) {
	compile_error(PARSER_ARG "block argument should not be given");
    }
}

static NODE *
ret_args_gen(struct parser_params *parser, NODE *node)
{
    if (node) {
	no_blockarg(parser, node);
	if (nd_type(node) == NODE_ARRAY) {
	    if (node->nd_next == 0) {
		node = node->nd_head;
	    }
	    else {
		nd_set_type(node, NODE_VALUES);
	    }
	}
    }
    return node;
}

static NODE *
new_yield_gen(struct parser_params *parser, NODE *node, const YYLTYPE *location)
{
    NODE *yield;
    if (node) no_blockarg(parser, node);

    yield = NEW_YIELD(node);
    nd_set_loc(yield, location);
    return yield;
}

static VALUE
negate_lit_gen(struct parser_params *parser, VALUE lit)
{
    int type = TYPE(lit);
    switch (type) {
      case T_FIXNUM:
	lit = LONG2FIX(-FIX2LONG(lit));
	break;
      case T_BIGNUM:
	BIGNUM_NEGATE(lit);
	lit = rb_big_norm(lit);
	break;
      case T_RATIONAL:
	RRATIONAL_SET_NUM(lit, negate_lit(RRATIONAL(lit)->num));
	break;
      case T_COMPLEX:
	RCOMPLEX_SET_REAL(lit, negate_lit(RCOMPLEX(lit)->real));
	RCOMPLEX_SET_IMAG(lit, negate_lit(RCOMPLEX(lit)->imag));
	break;
      case T_FLOAT:
#if USE_FLONUM
	if (FLONUM_P(lit)) {
	    lit = DBL2NUM(-RFLOAT_VALUE(lit));
	    break;
	}
#endif
	RFLOAT(lit)->float_value = -RFLOAT_VALUE(lit);
	break;
      default:
	rb_parser_fatal(parser, "unknown literal type (%d) passed to negate_lit", type);
	break;
    }
    return lit;
}

static NODE *
arg_blk_pass(NODE *node1, NODE *node2)
{
    if (node2) {
	node2->nd_head = node1;
	nd_set_first_lineno(node2, nd_first_lineno(node1));
	nd_set_first_column(node2, nd_first_column(node1));
	return node2;
    }
    return node1;
}


static NODE*
new_args_gen(struct parser_params *parser, NODE *m, NODE *o, ID r, NODE *p, NODE *tail, const YYLTYPE *location)
{
    int saved_line = ruby_sourceline;
    struct rb_args_info *args = tail->nd_ainfo;

    args->pre_args_num   = m ? rb_long2int(m->nd_plen) : 0;
    args->pre_init       = m ? m->nd_next : 0;

    args->post_args_num  = p ? rb_long2int(p->nd_plen) : 0;
    args->post_init      = p ? p->nd_next : 0;
    args->first_post_arg = p ? p->nd_pid : 0;

    args->rest_arg       = r;

    args->opt_args       = o;

    ruby_sourceline = saved_line;
    nd_set_loc(tail, location);

    return tail;
}

static NODE*
new_args_tail_gen(struct parser_params *parser, NODE *k, ID kr, ID b, const YYLTYPE *kr_location)
{
    int saved_line = ruby_sourceline;
    struct rb_args_info *args;
    NODE *node;

    args = ZALLOC(struct rb_args_info);
    add_mark_object((VALUE)rb_imemo_alloc_new((VALUE)args, 0, 0, 0));
    node = NEW_NODE(NODE_ARGS, 0, 0, args);
    if (parser->error_p) return node;

    args->block_arg      = b;
    args->kw_args        = k;

    if (k) {
	/*
	 * def foo(k1: 1, kr1:, k2: 2, **krest, &b)
	 * variable order: k1, kr1, k2, &b, internal_id, krest
	 * #=> <reorder>
	 * variable order: kr1, k1, k2, internal_id, krest, &b
	 */
	ID kw_bits;
	NODE *kwn = k;
	struct vtable *required_kw_vars = vtable_alloc(NULL);
	struct vtable *kw_vars = vtable_alloc(NULL);
	int i;

	while (kwn) {
	    NODE *val_node = kwn->nd_body->nd_value;
	    ID vid = kwn->nd_body->nd_vid;

	    if (val_node == NODE_SPECIAL_REQUIRED_KEYWORD) {
		vtable_add(required_kw_vars, vid);
	    }
	    else {
		vtable_add(kw_vars, vid);
	    }

	    kwn = kwn->nd_next;
	}

	kw_bits = internal_id();
	if (kr && is_junk_id(kr)) vtable_pop(lvtbl->args, 1);
	vtable_pop(lvtbl->args, vtable_size(required_kw_vars) + vtable_size(kw_vars) + (b != 0));

	for (i=0; i<vtable_size(required_kw_vars); i++) arg_var(required_kw_vars->tbl[i]);
	for (i=0; i<vtable_size(kw_vars); i++) arg_var(kw_vars->tbl[i]);
	vtable_free(required_kw_vars);
	vtable_free(kw_vars);

	arg_var(kw_bits);
	if (kr) arg_var(kr);
	if (b) arg_var(b);

	args->kw_rest_arg = new_dvar(kr, kr_location);
	args->kw_rest_arg->nd_cflag = kw_bits;
    }
    else if (kr) {
	if (b) vtable_pop(lvtbl->args, 1); /* reorder */
	arg_var(kr);
	if (b) arg_var(b);
	args->kw_rest_arg = new_dvar(kr, kr_location);
    }

    ruby_sourceline = saved_line;
    return node;
}

static NODE*
dsym_node_gen(struct parser_params *parser, NODE *node, const YYLTYPE *location)
{
    VALUE lit;

    if (!node) {
	return new_lit(ID2SYM(idNULL), location);
    }

    switch (nd_type(node)) {
      case NODE_DSTR:
	nd_set_type(node, NODE_DSYM);
	nd_set_loc(node, location);
	break;
      case NODE_STR:
	lit = node->nd_lit;
	add_mark_object(node->nd_lit = ID2SYM(rb_intern_str(lit)));
	nd_set_type(node, NODE_LIT);
	nd_set_loc(node, location);
	break;
      default:
	node = NEW_NODE(NODE_DSYM, Qnil, 1, new_list(node, location));
	nd_set_loc(node, location);
	break;
    }
    return node;
}

static int
append_literal_keys(st_data_t k, st_data_t v, st_data_t h)
{
    NODE *node = (NODE *)v;
    NODE **result = (NODE **)h;
    node->nd_alen = 2;
    node->nd_next->nd_end = node->nd_next;
    node->nd_next->nd_next = 0;
    if (*result)
	list_concat(*result, node);
    else
	*result = node;
    return ST_CONTINUE;
}

static NODE *
remove_duplicate_keys(struct parser_params *parser, NODE *hash, const YYLTYPE *location)
{
    st_table *literal_keys = st_init_numtable_with_size(hash->nd_alen / 2);
    NODE *result = 0;
    while (hash && hash->nd_head && hash->nd_next) {
	NODE *head = hash->nd_head;
	NODE *value = hash->nd_next;
	NODE *next = value->nd_next;
	VALUE key = (VALUE)head;
	st_data_t data;
	if (nd_type(head) == NODE_LIT &&
	    st_lookup(literal_keys, (key = head->nd_lit), &data)) {
	    rb_compile_warn(ruby_sourcefile, nd_line((NODE *)data),
			    "key %+"PRIsVALUE" is duplicated and overwritten on line %d",
			    head->nd_lit, nd_line(head));
	    head = ((NODE *)data)->nd_next;
	    head->nd_head = block_append(head->nd_head, value->nd_head, location);
	}
	else {
	    st_insert(literal_keys, (st_data_t)key, (st_data_t)hash);
	}
	hash = next;
    }
    st_foreach(literal_keys, append_literal_keys, (st_data_t)&result);
    st_free_table(literal_keys);
    if (hash) {
	if (!result) result = hash;
	else list_concat(result, hash);
    }
    return result;
}

static NODE *
new_hash_gen(struct parser_params *parser, NODE *hash, const YYLTYPE *location)
{
    NODE *nd_hash;
    if (hash) hash = remove_duplicate_keys(parser, hash, location);
    nd_hash = NEW_HASH(hash);
    nd_set_loc(nd_hash, location);
    return nd_hash;
}
#endif /* !RIPPER */

#ifndef RIPPER
static NODE *
new_op_assign_gen(struct parser_params *parser, NODE *lhs, ID op, NODE *rhs, const YYLTYPE *location)
{
    NODE *asgn;

    if (lhs) {
	ID vid = lhs->nd_vid;
	YYLTYPE lhs_location = lhs->nd_loc;
	if (op == tOROP) {
	    lhs->nd_value = rhs;
	    nd_set_loc(lhs, location);
	    asgn = NEW_OP_ASGN_OR(gettable(vid, &lhs_location), lhs);
	    nd_set_loc(asgn, location);
	    if (is_notop_id(vid)) {
		switch (id_type(vid)) {
		  case ID_GLOBAL:
		  case ID_INSTANCE:
		  case ID_CLASS:
		    asgn->nd_aid = vid;
		}
	    }
	}
	else if (op == tANDOP) {
	    lhs->nd_value = rhs;
	    nd_set_loc(lhs, location);
	    asgn = NEW_OP_ASGN_AND(gettable(vid, &lhs_location), lhs);
	    nd_set_loc(asgn, location);
	}
	else {
	    asgn = lhs;
	    asgn->nd_value = new_call(gettable(vid, &lhs_location), op, new_list(rhs, &rhs->nd_loc), location);
	    nd_set_loc(asgn, location);
	}
    }
    else {
	asgn = new_begin(0, location);
    }
    return asgn;
}

static NODE *
new_attr_op_assign_gen(struct parser_params *parser, NODE *lhs,
		       ID atype, ID attr, ID op, NODE *rhs, const YYLTYPE *location)
{
    NODE *asgn;

    if (op == tOROP) {
	op = 0;
    }
    else if (op == tANDOP) {
	op = 1;
    }
    asgn = NEW_OP_ASGN2(lhs, CALL_Q_P(atype), attr, op, rhs);
    nd_set_loc(asgn, location);
    fixpos(asgn, lhs);
    return asgn;
}

static NODE *
new_const_op_assign_gen(struct parser_params *parser, NODE *lhs, ID op, NODE *rhs, const YYLTYPE *location)
{
    NODE *asgn;

    if (op == tOROP) {
	op = 0;
    }
    else if (op == tANDOP) {
	op = 1;
    }
    if (lhs) {
	asgn = NEW_OP_CDECL(lhs, op, rhs);
    }
    else {
	asgn = new_begin(0, location);
    }
    fixpos(asgn, lhs);
    nd_set_loc(asgn, location);
    return asgn;
}

static NODE *
const_path_field_gen(struct parser_params *parser, NODE *head, ID mid, const YYLTYPE *location)
{
    NODE *colon2 = NEW_COLON2(head, mid);
    nd_set_loc(colon2, location);
    return colon2;
}

static NODE *
const_decl_gen(struct parser_params *parser, NODE *path, const YYLTYPE *location)
{
    if (in_def) {
	yyerror0("dynamic constant assignment");
    }
    return new_cdecl(0, 0, (path), location);
}
#else
static VALUE
new_op_assign_gen(struct parser_params *parser, VALUE lhs, VALUE op, VALUE rhs)
{
    return dispatch3(opassign, lhs, op, rhs);
}

static VALUE
new_attr_op_assign_gen(struct parser_params *parser, VALUE lhs, VALUE type, VALUE attr, VALUE op, VALUE rhs)
{
    VALUE recv = dispatch3(field, lhs, type, attr);
    return dispatch3(opassign, recv, op, rhs);
}

static VALUE
new_qcall_gen(struct parser_params *parser, VALUE r, VALUE q, VALUE m, VALUE a)
{
    VALUE ret = dispatch3(call, (r), (q), (m));
    return method_optarg(ret, (a));
}

static VALUE
const_decl_gen(struct parser_params *parser, VALUE path)
{
    if (in_def) {
	path = dispatch1(assign_error, path);
	ripper_error();
    }
    return path;
}

static VALUE
assign_error_gen(struct parser_params *parser, VALUE a)
{
    a = dispatch1(assign_error, a);
    ripper_error();
    return a;
}

static VALUE
var_field_gen(struct parser_params *parser, VALUE a)
{
    return ripper_new_yylval(get_id(a), dispatch1(var_field, a), 0);
}
#endif

static void
warn_unused_var(struct parser_params *parser, struct local_vars *local)
{
    int i, cnt;
    ID *v, *u;

    if (!local->used) return;
    v = local->vars->tbl;
    u = local->used->tbl;
    cnt = local->used->pos;
    if (cnt != local->vars->pos) {
	rb_parser_fatal(parser, "local->used->pos != local->vars->pos");
    }
    for (i = 0; i < cnt; ++i) {
	if (!v[i] || (u[i] & LVAR_USED)) continue;
	if (is_private_local_id(v[i])) continue;
	rb_warn1L((int)u[i], "assigned but unused variable - %"PRIsWARN, rb_id2str(v[i]));
    }
}

static void
local_push_gen(struct parser_params *parser, int inherit_dvars)
{
    struct local_vars *local;

    local = ALLOC(struct local_vars);
    local->prev = lvtbl;
    local->args = vtable_alloc(0);
    local->vars = vtable_alloc(inherit_dvars ? DVARS_INHERIT : DVARS_TOPSCOPE);
    local->used = !(inherit_dvars &&
		    (ifndef_ripper(compile_for_eval || e_option_supplied(parser))+0)) &&
	RTEST(ruby_verbose) ? vtable_alloc(0) : 0;
# if WARN_PAST_SCOPE
    local->past = 0;
# endif
    local->cmdargs = cmdarg_stack;
    CMDARG_SET(0);
    lvtbl = local;
}

static void
local_pop_gen(struct parser_params *parser)
{
    struct local_vars *local = lvtbl->prev;
    if (lvtbl->used) {
	warn_unused_var(parser, lvtbl);
	vtable_free(lvtbl->used);
    }
# if WARN_PAST_SCOPE
    while (lvtbl->past) {
	struct vtable *past = lvtbl->past;
	lvtbl->past = past->prev;
	vtable_free(past);
    }
# endif
    vtable_free(lvtbl->args);
    vtable_free(lvtbl->vars);
    CMDARG_SET(lvtbl->cmdargs);
    xfree(lvtbl);
    lvtbl = local;
}

#ifndef RIPPER
static ID*
local_tbl_gen(struct parser_params *parser)
{
    int cnt_args = vtable_size(lvtbl->args);
    int cnt_vars = vtable_size(lvtbl->vars);
    int cnt = cnt_args + cnt_vars;
    int i, j;
    ID *buf;

    if (cnt <= 0) return 0;
    buf = ALLOC_N(ID, cnt + 1);
    MEMCPY(buf+1, lvtbl->args->tbl, ID, cnt_args);
    /* remove IDs duplicated to warn shadowing */
    for (i = 0, j = cnt_args+1; i < cnt_vars; ++i) {
	ID id = lvtbl->vars->tbl[i];
	if (!vtable_included(lvtbl->args, id)) {
	    buf[j++] = id;
	}
    }
    if (--j < cnt) REALLOC_N(buf, ID, (cnt = j) + 1);
    buf[0] = cnt;

    add_mark_object((VALUE)rb_imemo_alloc_new((VALUE)buf, 0, 0, 0));

    return buf;
}
#endif

static void
arg_var_gen(struct parser_params *parser, ID id)
{
    vtable_add(lvtbl->args, id);
}

static void
local_var_gen(struct parser_params *parser, ID id)
{
    vtable_add(lvtbl->vars, id);
    if (lvtbl->used) {
	vtable_add(lvtbl->used, (ID)ruby_sourceline);
    }
}

static int
local_id_gen(struct parser_params *parser, ID id, ID **vidrefp)
{
    struct vtable *vars, *args, *used;

    vars = lvtbl->vars;
    args = lvtbl->args;
    used = lvtbl->used;

    while (vars && POINTER_P(vars->prev)) {
	vars = vars->prev;
	args = args->prev;
	if (used) used = used->prev;
    }

    if (vars && vars->prev == DVARS_INHERIT) {
	return rb_local_defined(id, parser->base_block);
    }
    else if (vtable_included(args, id)) {
	return 1;
    }
    else {
	int i = vtable_included(vars, id);
	if (i && used && vidrefp) *vidrefp = &used->tbl[i-1];
	return i != 0;
    }
}

static const struct vtable *
dyna_push_gen(struct parser_params *parser)
{
    lvtbl->args = vtable_alloc(lvtbl->args);
    lvtbl->vars = vtable_alloc(lvtbl->vars);
    if (lvtbl->used) {
	lvtbl->used = vtable_alloc(lvtbl->used);
    }
    return lvtbl->args;
}

static void
dyna_pop_vtable(struct parser_params *parser, struct vtable **vtblp)
{
    struct vtable *tmp = *vtblp;
    *vtblp = tmp->prev;
# if WARN_PAST_SCOPE
    if (parser->past_scope_enabled) {
	tmp->prev = lvtbl->past;
	lvtbl->past = tmp;
	return;
    }
# endif
    vtable_free(tmp);
}

static void
dyna_pop_1(struct parser_params *parser)
{
    struct vtable *tmp;

    if ((tmp = lvtbl->used) != 0) {
	warn_unused_var(parser, lvtbl);
	lvtbl->used = lvtbl->used->prev;
	vtable_free(tmp);
    }
    dyna_pop_vtable(parser, &lvtbl->args);
    dyna_pop_vtable(parser, &lvtbl->vars);
}

static void
dyna_pop_gen(struct parser_params *parser, const struct vtable *lvargs)
{
    while (lvtbl->args != lvargs) {
	dyna_pop_1(parser);
	if (!lvtbl->args) {
	    struct local_vars *local = lvtbl->prev;
	    xfree(lvtbl);
	    lvtbl = local;
	}
    }
    dyna_pop_1(parser);
}

static int
dyna_in_block_gen(struct parser_params *parser)
{
    return POINTER_P(lvtbl->vars) && lvtbl->vars->prev != DVARS_TOPSCOPE;
}

static int
dvar_defined_gen(struct parser_params *parser, ID id, ID **vidrefp)
{
    struct vtable *vars, *args, *used;
    int i;

    args = lvtbl->args;
    vars = lvtbl->vars;
    used = lvtbl->used;

    while (POINTER_P(vars)) {
	if (vtable_included(args, id)) {
	    return 1;
	}
	if ((i = vtable_included(vars, id)) != 0) {
	    if (used && vidrefp) *vidrefp = &used->tbl[i-1];
	    return 1;
	}
	args = args->prev;
	vars = vars->prev;
	if (!vidrefp) used = 0;
	if (used) used = used->prev;
    }

    if (vars == DVARS_INHERIT) {
        return rb_dvar_defined(id, parser->base_block);
    }

    return 0;
}

static int
dvar_curr_gen(struct parser_params *parser, ID id)
{
    return (vtable_included(lvtbl->args, id) ||
	    vtable_included(lvtbl->vars, id));
}

static void
reg_fragment_enc_error(struct parser_params* parser, VALUE str, int c)
{
    compile_error(PARSER_ARG
        "regexp encoding option '%c' differs from source encoding '%s'",
        c, rb_enc_name(rb_enc_get(str)));
}

#ifndef RIPPER
int
rb_reg_fragment_setenc(struct parser_params* parser, VALUE str, int options)
{
    int c = RE_OPTION_ENCODING_IDX(options);

    if (c) {
	int opt, idx;
	rb_char_to_option_kcode(c, &opt, &idx);
	if (idx != ENCODING_GET(str) &&
	    rb_enc_str_coderange(str) != ENC_CODERANGE_7BIT) {
            goto error;
	}
	ENCODING_SET(str, idx);
    }
    else if (RE_OPTION_ENCODING_NONE(options)) {
        if (!ENCODING_IS_ASCII8BIT(str) &&
            rb_enc_str_coderange(str) != ENC_CODERANGE_7BIT) {
            c = 'n';
            goto error;
        }
	rb_enc_associate(str, rb_ascii8bit_encoding());
    }
    else if (current_enc == rb_usascii_encoding()) {
	if (rb_enc_str_coderange(str) != ENC_CODERANGE_7BIT) {
	    /* raise in re.c */
	    rb_enc_associate(str, rb_usascii_encoding());
	}
	else {
	    rb_enc_associate(str, rb_ascii8bit_encoding());
	}
    }
    return 0;

  error:
    return c;
}

static void
reg_fragment_setenc_gen(struct parser_params* parser, VALUE str, int options)
{
    int c = rb_reg_fragment_setenc(parser, str, options);
    if (c) reg_fragment_enc_error(parser, str, c);
}

static int
reg_fragment_check_gen(struct parser_params* parser, VALUE str, int options)
{
    VALUE err;
    reg_fragment_setenc(str, options);
    err = rb_reg_check_preprocess(str);
    if (err != Qnil) {
        err = rb_obj_as_string(err);
        compile_error(PARSER_ARG "%"PRIsVALUE, err);
	return 0;
    }
    return 1;
}

typedef struct {
    struct parser_params* parser;
    rb_encoding *enc;
    NODE *succ_block;
    const YYLTYPE *location;
} reg_named_capture_assign_t;

static int
reg_named_capture_assign_iter(const OnigUChar *name, const OnigUChar *name_end,
          int back_num, int *back_refs, OnigRegex regex, void *arg0)
{
    reg_named_capture_assign_t *arg = (reg_named_capture_assign_t*)arg0;
    struct parser_params* parser = arg->parser;
    rb_encoding *enc = arg->enc;
    long len = name_end - name;
    const char *s = (const char *)name;
    ID var;
    NODE *node, *succ;

    if (!len || (*name != '_' && ISASCII(*name) && !rb_enc_islower(*name, enc)) ||
	(len < MAX_WORD_LENGTH && rb_reserved_word(s, (int)len)) ||
	!rb_enc_symname2_p(s, len, enc)) {
        return ST_CONTINUE;
    }
    var = intern_cstr(s, len, enc);
    node = node_assign(assignable(var, 0, arg->location), new_lit(ID2SYM(var), arg->location), arg->location);
    succ = arg->succ_block;
    if (!succ) succ = new_begin(0, arg->location);
    succ = block_append(succ, node, arg->location);
    arg->succ_block = succ;
    return ST_CONTINUE;
}

static NODE *
reg_named_capture_assign_gen(struct parser_params* parser, VALUE regexp, const YYLTYPE *location)
{
    reg_named_capture_assign_t arg;

    arg.parser = parser;
    arg.enc = rb_enc_get(regexp);
    arg.succ_block = 0;
    arg.location = location;
    onig_foreach_name(RREGEXP_PTR(regexp), reg_named_capture_assign_iter, &arg);

    if (!arg.succ_block) return 0;
    return arg.succ_block->nd_next;
}

static VALUE
parser_reg_compile(struct parser_params* parser, VALUE str, int options)
{
    reg_fragment_setenc(str, options);
    return rb_parser_reg_compile(parser, str, options);
}

VALUE
rb_parser_reg_compile(struct parser_params* parser, VALUE str, int options)
{
    return rb_reg_compile(str, options & RE_OPTION_MASK, ruby_sourcefile, ruby_sourceline);
}

static VALUE
reg_compile_gen(struct parser_params* parser, VALUE str, int options)
{
    VALUE re;
    VALUE err;

    err = rb_errinfo();
    re = parser_reg_compile(parser, str, options);
    if (NIL_P(re)) {
	VALUE m = rb_attr_get(rb_errinfo(), idMesg);
	rb_set_errinfo(err);
	compile_error(PARSER_ARG "%"PRIsVALUE, m);
	return Qnil;
    }
    return re;
}
#else
static VALUE
parser_reg_compile(struct parser_params* parser, VALUE str, int options, VALUE *errmsg)
{
    VALUE err = rb_errinfo();
    VALUE re;
    int c = rb_reg_fragment_setenc(parser, str, options);
    if (c) reg_fragment_enc_error(parser, str, c);
    re = rb_parser_reg_compile(parser, str, options);
    if (NIL_P(re)) {
	*errmsg = rb_attr_get(rb_errinfo(), idMesg);
	rb_set_errinfo(err);
    }
    return re;
}
#endif

#ifndef RIPPER
void
rb_parser_set_options(VALUE vparser, int print, int loop, int chomp, int split)
{
    struct parser_params *parser;
    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, parser);
    parser->do_print = print;
    parser->do_loop = loop;
    parser->do_chomp = chomp;
    parser->do_split = split;
}

static NODE *
parser_append_options(struct parser_params *parser, NODE *node)
{
    static const YYLTYPE default_location = {{1, 0}, {1, 0}};

    if (parser->do_print) {
	node = block_append(node,
			    new_fcall(rb_intern("print"),
				      NEW_ARRAY(new_gvar(idLASTLINE, &default_location)), &default_location),
			    &default_location);
    }

    if (parser->do_loop) {
	if (parser->do_split) {
	    node = block_append(NEW_GASGN(rb_intern("$F"),
					  new_call(new_gvar(idLASTLINE, &default_location),
						   rb_intern("split"), 0, &default_location)),
				node, &default_location);
	}
	if (parser->do_chomp) {
	    node = block_append(new_call(new_gvar(idLASTLINE, &default_location),
					 rb_intern("chomp!"), 0, &default_location), node, &default_location);
	}

	node = NEW_WHILE(NEW_VCALL(idGets), node, 1);
    }

    return node;
}

void
rb_init_parse(void)
{
    /* just to suppress unused-function warnings */
    (void)nodetype;
    (void)nodeline;
}
#endif /* !RIPPER */

static ID
internal_id_gen(struct parser_params *parser)
{
    ID id = (ID)vtable_size(lvtbl->args) + (ID)vtable_size(lvtbl->vars);
    id += ((tLAST_TOKEN - ID_INTERNAL) >> ID_SCOPE_SHIFT) + 1;
    return ID_STATIC_SYM | ID_INTERNAL | (id << ID_SCOPE_SHIFT);
}

static void
parser_initialize(struct parser_params *parser)
{
    /* note: we rely on TypedData_Make_Struct to set most fields to 0 */
    command_start = TRUE;
    ruby_sourcefile_string = Qnil;
#ifdef RIPPER
    parser->delayed = Qnil;
    parser->result = Qnil;
    parser->parsing_thread = Qnil;
#else
    parser->error_buffer = Qfalse;
#endif
    parser->debug_buffer = Qnil;
    parser->debug_output = rb_stdout;
    parser->enc = rb_utf8_encoding();
}

#ifdef RIPPER
#define parser_mark ripper_parser_mark
#define parser_free ripper_parser_free
#endif

static void
parser_mark(void *ptr)
{
    struct parser_params *parser = (struct parser_params*)ptr;

    rb_gc_mark(lex_input);
    rb_gc_mark(lex_prevline);
    rb_gc_mark(lex_lastline);
    rb_gc_mark(lex_nextline);
    rb_gc_mark(ruby_sourcefile_string);
    rb_gc_mark((VALUE)lex_strterm);
    rb_gc_mark((VALUE)parser->ast);
#ifndef RIPPER
    rb_gc_mark(ruby_debug_lines);
    rb_gc_mark(parser->compile_option);
    rb_gc_mark(parser->error_buffer);
#else
    rb_gc_mark(parser->delayed);
    rb_gc_mark(parser->value);
    rb_gc_mark(parser->result);
    rb_gc_mark(parser->parsing_thread);
#endif
    rb_gc_mark(parser->debug_buffer);
    rb_gc_mark(parser->debug_output);
#ifdef YYMALLOC
    rb_gc_mark((VALUE)parser->heap);
#endif
}

static void
parser_free(void *ptr)
{
    struct parser_params *parser = (struct parser_params*)ptr;
    struct local_vars *local, *prev;

    if (tokenbuf) {
        xfree(tokenbuf);
    }
    for (local = lvtbl; local; local = prev) {
	if (local->vars) xfree(local->vars);
	prev = local->prev;
	xfree(local);
    }
    {
	token_info *ptinfo;
	while ((ptinfo = parser->token_info) != 0) {
	    parser->token_info = ptinfo->next;
	    xfree(ptinfo);
	}
    }
    xfree(ptr);
}

static size_t
parser_memsize(const void *ptr)
{
    struct parser_params *parser = (struct parser_params*)ptr;
    struct local_vars *local;
    size_t size = sizeof(*parser);

    size += toksiz;
    for (local = lvtbl; local; local = local->prev) {
	size += sizeof(*local);
	if (local->vars) size += local->vars->capa * sizeof(ID);
    }
    return size;
}

static const rb_data_type_t parser_data_type = {
#ifndef RIPPER
    "parser",
#else
    "ripper",
#endif
    {
	parser_mark,
	parser_free,
	parser_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#ifndef RIPPER
#undef rb_reserved_word

const struct kwtable *
rb_reserved_word(const char *str, unsigned int len)
{
    return reserved_word(str, len);
}

VALUE
rb_parser_new(void)
{
    struct parser_params *p;
    VALUE parser = TypedData_Make_Struct(0, struct parser_params,
					 &parser_data_type, p);
    parser_initialize(p);
    return parser;
}

VALUE
rb_parser_set_context(VALUE vparser, const struct rb_block *base, int main)
{
    struct parser_params *parser;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, parser);
    parser->error_buffer = main ? Qfalse : Qnil;
    parser->base_block = base;
    in_main = main;
    return vparser;
}
#endif

#ifdef RIPPER
#define rb_parser_end_seen_p ripper_parser_end_seen_p
#define rb_parser_encoding ripper_parser_encoding
#define rb_parser_get_yydebug ripper_parser_get_yydebug
#define rb_parser_set_yydebug ripper_parser_set_yydebug
static VALUE ripper_parser_end_seen_p(VALUE vparser);
static VALUE ripper_parser_encoding(VALUE vparser);
static VALUE ripper_parser_get_yydebug(VALUE self);
static VALUE ripper_parser_set_yydebug(VALUE self, VALUE flag);

/*
 *  call-seq:
 *    ripper.error?   -> Boolean
 *
 *  Return true if parsed source has errors.
 */
static VALUE
ripper_error_p(VALUE vparser)
{
    struct parser_params *parser;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, parser);
    return parser->error_p ? Qtrue : Qfalse;
}
#endif

/*
 *  call-seq:
 *    ripper.end_seen?   -> Boolean
 *
 *  Return true if parsed source ended by +\_\_END\_\_+.
 */
VALUE
rb_parser_end_seen_p(VALUE vparser)
{
    struct parser_params *parser;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, parser);
    return ruby__end__seen ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    ripper.encoding   -> encoding
 *
 *  Return encoding of the source.
 */
VALUE
rb_parser_encoding(VALUE vparser)
{
    struct parser_params *parser;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, parser);
    return rb_enc_from_encoding(current_enc);
}

/*
 *  call-seq:
 *    ripper.yydebug   -> true or false
 *
 *  Get yydebug.
 */
VALUE
rb_parser_get_yydebug(VALUE self)
{
    struct parser_params *parser;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, parser);
    return yydebug ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    ripper.yydebug = flag
 *
 *  Set yydebug.
 */
VALUE
rb_parser_set_yydebug(VALUE self, VALUE flag)
{
    struct parser_params *parser;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, parser);
    yydebug = RTEST(flag);
    return flag;
}

#ifndef RIPPER
#ifdef YYMALLOC
#define HEAPCNT(n, size) ((n) * (size) / sizeof(YYSTYPE))
#define NEWHEAP() rb_imemo_alloc_new(0, (VALUE)parser->heap, 0, 0)
#define ADD2HEAP(n, c, p) ((parser->heap = (n))->ptr = (p), \
			   (n)->cnt = (c), (p))

void *
rb_parser_malloc(struct parser_params *parser, size_t size)
{
    size_t cnt = HEAPCNT(1, size);
    rb_imemo_alloc_t *n = NEWHEAP();
    void *ptr = xmalloc(size);

    return ADD2HEAP(n, cnt, ptr);
}

void *
rb_parser_calloc(struct parser_params *parser, size_t nelem, size_t size)
{
    size_t cnt = HEAPCNT(nelem, size);
    rb_imemo_alloc_t *n = NEWHEAP();
    void *ptr = xcalloc(nelem, size);

    return ADD2HEAP(n, cnt, ptr);
}

void *
rb_parser_realloc(struct parser_params *parser, void *ptr, size_t size)
{
    rb_imemo_alloc_t *n;
    size_t cnt = HEAPCNT(1, size);

    if (ptr && (n = parser->heap) != NULL) {
	do {
	    if (n->ptr == ptr) {
		n->ptr = ptr = xrealloc(ptr, size);
		if (n->cnt) n->cnt = cnt;
		return ptr;
	    }
	} while ((n = n->next) != NULL);
    }
    n = NEWHEAP();
    ptr = xrealloc(ptr, size);
    return ADD2HEAP(n, cnt, ptr);
}

void
rb_parser_free(struct parser_params *parser, void *ptr)
{
    rb_imemo_alloc_t **prev = &parser->heap, *n;

    while ((n = *prev) != NULL) {
	if (n->ptr == ptr) {
	    *prev = n->next;
	    rb_gc_force_recycle((VALUE)n);
	    break;
	}
	prev = &n->next;
    }
    xfree(ptr);
}
#endif

void
rb_parser_printf(struct parser_params *parser, const char *fmt, ...)
{
    va_list ap;
    VALUE mesg = parser->debug_buffer;

    if (NIL_P(mesg)) parser->debug_buffer = mesg = rb_str_new(0, 0);
    va_start(ap, fmt);
    rb_str_vcatf(mesg, fmt, ap);
    va_end(ap);
    if (RSTRING_END(mesg)[-1] == '\n') {
	rb_io_write(parser->debug_output, mesg);
	parser->debug_buffer = Qnil;
    }
}

static void
parser_compile_error(struct parser_params *parser, const char *fmt, ...)
{
    va_list ap;

    rb_io_flush(parser->debug_output);
    parser->error_p = 1;
    va_start(ap, fmt);
    parser->error_buffer =
	rb_syntax_error_append(parser->error_buffer,
			       ruby_sourcefile_string,
			       ruby_sourceline,
			       rb_long2int(lex_p - lex_pbeg),
			       current_enc, fmt, ap);
    va_end(ap);
}
#endif

#ifdef RIPPER
#ifdef RIPPER_DEBUG
extern int rb_is_pointer_to_heap(VALUE);

/* :nodoc: */
static VALUE
ripper_validate_object(VALUE self, VALUE x)
{
    if (x == Qfalse) return x;
    if (x == Qtrue) return x;
    if (x == Qnil) return x;
    if (x == Qundef)
        rb_raise(rb_eArgError, "Qundef given");
    if (FIXNUM_P(x)) return x;
    if (SYMBOL_P(x)) return x;
    if (!rb_is_pointer_to_heap(x))
        rb_raise(rb_eArgError, "invalid pointer: %p", x);
    switch (BUILTIN_TYPE(x)) {
      case T_STRING:
      case T_OBJECT:
      case T_ARRAY:
      case T_BIGNUM:
      case T_FLOAT:
      case T_COMPLEX:
      case T_RATIONAL:
        return x;
      case T_NODE:
	if (nd_type(x) != NODE_RIPPER) {
	    rb_raise(rb_eArgError, "NODE given: %p", x);
	}
	return ((NODE *)x)->nd_rval;
      default:
        rb_raise(rb_eArgError, "wrong type of ruby object: %p (%s)",
                 x, rb_obj_classname(x));
    }
    return x;
}
#endif

#define validate(x) ((x) = get_value(x))

static VALUE
ripper_dispatch0(struct parser_params *parser, ID mid)
{
    return rb_funcall(parser->value, mid, 0);
}

static VALUE
ripper_dispatch1(struct parser_params *parser, ID mid, VALUE a)
{
    validate(a);
    return rb_funcall(parser->value, mid, 1, a);
}

static VALUE
ripper_dispatch2(struct parser_params *parser, ID mid, VALUE a, VALUE b)
{
    validate(a);
    validate(b);
    return rb_funcall(parser->value, mid, 2, a, b);
}

static VALUE
ripper_dispatch3(struct parser_params *parser, ID mid, VALUE a, VALUE b, VALUE c)
{
    validate(a);
    validate(b);
    validate(c);
    return rb_funcall(parser->value, mid, 3, a, b, c);
}

static VALUE
ripper_dispatch4(struct parser_params *parser, ID mid, VALUE a, VALUE b, VALUE c, VALUE d)
{
    validate(a);
    validate(b);
    validate(c);
    validate(d);
    return rb_funcall(parser->value, mid, 4, a, b, c, d);
}

static VALUE
ripper_dispatch5(struct parser_params *parser, ID mid, VALUE a, VALUE b, VALUE c, VALUE d, VALUE e)
{
    validate(a);
    validate(b);
    validate(c);
    validate(d);
    validate(e);
    return rb_funcall(parser->value, mid, 5, a, b, c, d, e);
}

static VALUE
ripper_dispatch7(struct parser_params *parser, ID mid, VALUE a, VALUE b, VALUE c, VALUE d, VALUE e, VALUE f, VALUE g)
{
    validate(a);
    validate(b);
    validate(c);
    validate(d);
    validate(e);
    validate(f);
    validate(g);
    return rb_funcall(parser->value, mid, 7, a, b, c, d, e, f, g);
}

static ID
ripper_get_id(VALUE v)
{
    NODE *nd;
    if (!RB_TYPE_P(v, T_NODE)) return 0;
    nd = (NODE *)v;
    if (nd_type(nd) != NODE_RIPPER) return 0;
    return nd->nd_vid;
}

static VALUE
ripper_get_value(VALUE v)
{
    NODE *nd;
    if (v == Qundef) return Qnil;
    if (!RB_TYPE_P(v, T_NODE)) return v;
    nd = (NODE *)v;
    if (nd_type(nd) != NODE_RIPPER) return Qnil;
    return nd->nd_rval;
}

static void
ripper_error_gen(struct parser_params *parser)
{
    parser->error_p = TRUE;
}

static void
ripper_compile_error(struct parser_params *parser, const char *fmt, ...)
{
    VALUE str;
    va_list args;

    va_start(args, fmt);
    str = rb_vsprintf(fmt, args);
    va_end(args);
    rb_funcall(parser->value, rb_intern("compile_error"), 1, str);
    ripper_error_gen(parser);
}

static VALUE
ripper_lex_get_generic(struct parser_params *parser, VALUE src)
{
    VALUE line = rb_funcallv_public(src, id_gets, 0, 0);
    if (!NIL_P(line) && !RB_TYPE_P(line, T_STRING)) {
	rb_raise(rb_eTypeError,
		 "gets returned %"PRIsVALUE" (expected String or nil)",
		 rb_obj_class(line));
    }
    return line;
}

static VALUE
ripper_lex_io_get(struct parser_params *parser, VALUE src)
{
    return rb_io_gets(src);
}

static VALUE
ripper_s_allocate(VALUE klass)
{
    struct parser_params *p;
    VALUE self = TypedData_Make_Struct(klass, struct parser_params,
				       &parser_data_type, p);
    p->value = self;
    return self;
}

#define ripper_initialized_p(r) ((r)->lex.input != 0)

/*
 *  call-seq:
 *    Ripper.new(src, filename="(ripper)", lineno=1) -> ripper
 *
 *  Create a new Ripper object.
 *  _src_ must be a String, an IO, or an Object which has #gets method.
 *
 *  This method does not starts parsing.
 *  See also Ripper#parse and Ripper.parse.
 */
static VALUE
ripper_initialize(int argc, VALUE *argv, VALUE self)
{
    struct parser_params *parser;
    VALUE src, fname, lineno;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, parser);
    rb_scan_args(argc, argv, "12", &src, &fname, &lineno);
    if (RB_TYPE_P(src, T_FILE)) {
        lex_gets = ripper_lex_io_get;
    }
    else if (rb_respond_to(src, id_gets)) {
        lex_gets = ripper_lex_get_generic;
    }
    else {
        StringValue(src);
        lex_gets = lex_get_str;
    }
    lex_input = src;
    parser->eofp = 0;
    if (NIL_P(fname)) {
        fname = STR_NEW2("(ripper)");
	OBJ_FREEZE(fname);
    }
    else {
	StringValueCStr(fname);
	fname = rb_str_new_frozen(fname);
    }
    parser_initialize(parser);

    ruby_sourcefile_string = fname;
    ruby_sourcefile = RSTRING_PTR(fname);
    ruby_sourceline = NIL_P(lineno) ? 0 : NUM2INT(lineno) - 1;

    return Qnil;
}

struct ripper_args {
    struct parser_params *parser;
    int argc;
    VALUE *argv;
};

static VALUE
ripper_parse0(VALUE parser_v)
{
    struct parser_params *parser;

    TypedData_Get_Struct(parser_v, struct parser_params, &parser_data_type, parser);
    parser_prepare(parser);
    parser->ast = rb_ast_new();
    ripper_yyparse((void*)parser);
    rb_ast_dispose(parser->ast);
    parser->ast = 0;
    return parser->result;
}

static VALUE
ripper_ensure(VALUE parser_v)
{
    struct parser_params *parser;

    TypedData_Get_Struct(parser_v, struct parser_params, &parser_data_type, parser);
    parser->parsing_thread = Qnil;
    return Qnil;
}

/*
 *  call-seq:
 *    ripper.parse
 *
 *  Start parsing and returns the value of the root action.
 */
static VALUE
ripper_parse(VALUE self)
{
    struct parser_params *parser;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, parser);
    if (!ripper_initialized_p(parser)) {
        rb_raise(rb_eArgError, "method called for uninitialized object");
    }
    if (!NIL_P(parser->parsing_thread)) {
        if (parser->parsing_thread == rb_thread_current())
            rb_raise(rb_eArgError, "Ripper#parse is not reentrant");
        else
            rb_raise(rb_eArgError, "Ripper#parse is not multithread-safe");
    }
    parser->parsing_thread = rb_thread_current();
    rb_ensure(ripper_parse0, self, ripper_ensure, self);

    return parser->result;
}

/*
 *  call-seq:
 *    ripper.column   -> Integer
 *
 *  Return column number of current parsing line.
 *  This number starts from 0.
 */
static VALUE
ripper_column(VALUE self)
{
    struct parser_params *parser;
    long col;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, parser);
    if (!ripper_initialized_p(parser)) {
        rb_raise(rb_eArgError, "method called for uninitialized object");
    }
    if (NIL_P(parser->parsing_thread)) return Qnil;
    col = parser->tokp - lex_pbeg;
    return LONG2NUM(col);
}

/*
 *  call-seq:
 *    ripper.filename   -> String
 *
 *  Return current parsing filename.
 */
static VALUE
ripper_filename(VALUE self)
{
    struct parser_params *parser;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, parser);
    if (!ripper_initialized_p(parser)) {
        rb_raise(rb_eArgError, "method called for uninitialized object");
    }
    return ruby_sourcefile_string;
}

/*
 *  call-seq:
 *    ripper.lineno   -> Integer
 *
 *  Return line number of current parsing line.
 *  This number starts from 1.
 */
static VALUE
ripper_lineno(VALUE self)
{
    struct parser_params *parser;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, parser);
    if (!ripper_initialized_p(parser)) {
        rb_raise(rb_eArgError, "method called for uninitialized object");
    }
    if (NIL_P(parser->parsing_thread)) return Qnil;
    return INT2NUM(ruby_sourceline);
}

/*
 *  call-seq:
 *    ripper.state   -> Integer
 *
 *  Return scanner state of current token.
 */
static VALUE
ripper_state(VALUE self)
{
    struct parser_params *parser;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, parser);
    if (!ripper_initialized_p(parser)) {
	rb_raise(rb_eArgError, "method called for uninitialized object");
    }
    if (NIL_P(parser->parsing_thread)) return Qnil;
    return INT2NUM(lex_state);
}

#ifdef RIPPER_DEBUG
/* :nodoc: */
static VALUE
ripper_assert_Qundef(VALUE self, VALUE obj, VALUE msg)
{
    StringValue(msg);
    if (obj == Qundef) {
        rb_raise(rb_eArgError, "%"PRIsVALUE, msg);
    }
    return Qnil;
}

/* :nodoc: */
static VALUE
ripper_value(VALUE self, VALUE obj)
{
    return ULONG2NUM(obj);
}
#endif

static VALUE
ripper_lex_state_name(VALUE self, VALUE state)
{
    return rb_parser_lex_state_name(NUM2INT(state));
}

void
Init_ripper(void)
{
    ripper_init_eventids1();
    ripper_init_eventids2();
    id_warn = rb_intern_const("warn");
    id_warning = rb_intern_const("warning");
    id_gets = rb_intern_const("gets");

    InitVM(ripper);
}

void
InitVM_ripper(void)
{
    VALUE Ripper;

    Ripper = rb_define_class("Ripper", rb_cObject);
    /* version of Ripper */
    rb_define_const(Ripper, "Version", rb_usascii_str_new2(RIPPER_VERSION));
    rb_define_alloc_func(Ripper, ripper_s_allocate);
    rb_define_method(Ripper, "initialize", ripper_initialize, -1);
    rb_define_method(Ripper, "parse", ripper_parse, 0);
    rb_define_method(Ripper, "column", ripper_column, 0);
    rb_define_method(Ripper, "filename", ripper_filename, 0);
    rb_define_method(Ripper, "lineno", ripper_lineno, 0);
    rb_define_method(Ripper, "state", ripper_state, 0);
    rb_define_method(Ripper, "end_seen?", rb_parser_end_seen_p, 0);
    rb_define_method(Ripper, "encoding", rb_parser_encoding, 0);
    rb_define_method(Ripper, "yydebug", rb_parser_get_yydebug, 0);
    rb_define_method(Ripper, "yydebug=", rb_parser_set_yydebug, 1);
    rb_define_method(Ripper, "error?", ripper_error_p, 0);
#ifdef RIPPER_DEBUG
    rb_define_method(rb_mKernel, "assert_Qundef", ripper_assert_Qundef, 2);
    rb_define_method(rb_mKernel, "rawVALUE", ripper_value, 1);
    rb_define_method(rb_mKernel, "validate_object", ripper_validate_object, 1);
#endif

    rb_define_singleton_method(Ripper, "dedent_string", parser_dedent_string, 2);
    rb_define_private_method(Ripper, "dedent_string", parser_dedent_string, 2);

    rb_define_singleton_method(Ripper, "lex_state_name", ripper_lex_state_name, 1);

<% @exprs.each do |expr, desc| -%>
    /* <%=desc%> */
    rb_define_const(Ripper, "<%=expr%>", INT2NUM(<%=expr%>));
<% end %>
    ripper_init_eventids1_table(Ripper);
    ripper_init_eventids2_table(Ripper);

# if 0
    /* Hack to let RDoc document SCRIPT_LINES__ */

    /*
     * When a Hash is assigned to +SCRIPT_LINES__+ the contents of files loaded
     * after the assignment will be added as an Array of lines with the file
     * name as the key.
     */
    rb_define_global_const("SCRIPT_LINES__", Qnil);
#endif

}
#endif /* RIPPER */
