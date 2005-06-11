/**********************************************************************

  parse.y -

  $Author$
  $Date$
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-2004 Yukihiro Matsumoto

**********************************************************************/

%{

#define YYDEBUG 1

#include "ruby.h"
#include "env.h"
#include "intern.h"
#include "node.h"
#include "st.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>

#define ID_SCOPE_SHIFT 3
#define ID_SCOPE_MASK 0x07
#define ID_LOCAL    0x01
#define ID_INSTANCE 0x02
#define ID_GLOBAL   0x03
#define ID_ATTRSET  0x04
#define ID_CONST    0x05
#define ID_CLASS    0x06
#define ID_JUNK     0x07
#define ID_INTERNAL ID_JUNK

#define is_notop_id(id) ((id)>tLAST_TOKEN)
#define is_local_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_LOCAL)
#define is_global_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_GLOBAL)
#define is_instance_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_INSTANCE)
#define is_attrset_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_ATTRSET)
#define is_const_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_CONST)
#define is_class_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_CLASS)
#define is_junk_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_JUNK)

#define is_asgn_or_id(id) ((is_notop_id(id)) && \
	(((id)&ID_SCOPE_MASK) == ID_GLOBAL || \
	 ((id)&ID_SCOPE_MASK) == ID_INSTANCE || \
	 ((id)&ID_SCOPE_MASK) == ID_CLASS))

static int is_valid_lvar _((ID id));

#ifndef RIPPER
char *ruby_sourcefile;		/* current source file */
int   ruby_sourceline;		/* current line no. */
#endif

enum lex_state_e {
    EXPR_BEG,			/* ignore newline, +/- is a sign. */
    EXPR_END,			/* newline significant, +/- is a operator. */
    EXPR_ARG,			/* newline significant, +/- is a operator. */
    EXPR_CMDARG,		/* newline significant, +/- is a operator. */
    EXPR_ENDARG,		/* newline significant, +/- is a operator. */
    EXPR_MID,			/* newline significant, +/- is a operator. */
    EXPR_FNAME,			/* ignore newline, no reserved words. */
    EXPR_DOT,			/* right after `.' or `::', no reserved words. */
    EXPR_CLASS,			/* immediate after `class', no here document. */
    EXPR_VALUE,			/* alike EXPR_BEG but label is disallowed. */
};

# ifdef HAVE_LONG_LONG
typedef unsigned LONG_LONG stack_type;
# else
typedef unsigned long stack_type;
# endif

# define BITSTACK_PUSH(stack, n)	(stack = (stack<<1)|((n)&1))
# define BITSTACK_POP(stack)	(stack = stack >> 1)
# define BITSTACK_LEXPOP(stack)	(stack = (stack >> 1) | (stack & 1))
# define BITSTACK_SET_P(stack)	(stack&1)

#define COND_PUSH(n)	BITSTACK_PUSH(cond_stack, n)
#define COND_POP()	BITSTACK_POP(cond_stack)
#define COND_LEXPOP()	BITSTACK_LEXPOP(cond_stack)
#define COND_P()	BITSTACK_SET_P(cond_stack)

#define CMDARG_PUSH(n)	BITSTACK_PUSH(cmdarg_stack, n)
#define CMDARG_POP()	BITSTACK_POP(cmdarg_stack)
#define CMDARG_LEXPOP()	BITSTACK_LEXPOP(cmdarg_stack)
#define CMDARG_P()	BITSTACK_SET_P(cmdarg_stack)

/* must sync with real YYSTYPE */
union tmpyystype {
    VALUE val;
    NODE *node;
    unsigned long id;
    int num;
    struct RVarmap *vars;
};

struct local_vars {
    ID *tbl;
    int nofree;
    int cnt;
    int dlev;
    int dname_size;
    ID *dnames;
    struct RVarmap* dyna_vars;
    struct local_vars *prev;
};

/*
    Structure of Lexer Buffer:

 lex_pbeg      tokp         lex_p        lex_pend
    |           |              |            |
    |-----------+--------------+------------|
                |<------------>|
                     token
*/
struct parser_params {
    union tmpyystype *parser_yylval;   /* YYSTYPE not defined yet */
    VALUE eofp;

    NODE *parser_lex_strterm;
    enum lex_state_e parser_lex_state;
    stack_type parser_cond_stack;
    stack_type parser_cmdarg_stack;
    int parser_class_nest;
    int parser_in_single;
    int parser_in_def;
    int parser_compile_for_eval;
    VALUE parser_cur_mid;
    int parser_in_defined;
    char *parser_tokenbuf;
    int parser_tokidx;
    int parser_toksiz;
    VALUE parser_lex_input;
    VALUE parser_lex_lastline;
    char *parser_lex_pbeg;
    char *parser_lex_p;
    char *parser_lex_pend;
    int parser_heredoc_end;
    int parser_command_start;
    int parser_lex_gets_ptr;
    VALUE (*parser_lex_gets) _((struct parser_params*,VALUE));
    struct local_vars *parser_lvtbl;
#ifndef RIPPER
    /* Ruby core only */
    NODE *parser_eval_tree_begin;
    NODE *parser_eval_tree;
#else
    /* Ripper only */
    int parser_ruby__end__seen;
    int parser_ruby_sourceline;
    VALUE parser_ruby_sourcefile;
    char *tokp;
    VALUE delayed;
    int delayed_line;
    int delayed_col;

    VALUE value;
    VALUE result;
    VALUE parsing_thread;
    int toplevel_p;
#endif
    int line_count;
    int has_shebang;
};

static int parser_yyerror _((struct parser_params*, const char*));
#define yyerror(msg) parser_yyerror(parser, msg)

#define YYPARSE_PARAM parser_v
#define YYLEX_PARAM parser_v
#define parser ((struct parser_params*)parser_v)

#define ruby_eval_tree		(parser->parser_eval_tree)
#define ruby_eval_tree_begin	(parser->parser_eval_tree_begin)
#define lex_strterm		(parser->parser_lex_strterm)
#define lex_state		(parser->parser_lex_state)
#define cond_stack		(parser->parser_cond_stack)
#define cmdarg_stack		(parser->parser_cmdarg_stack)
#define class_nest		(parser->parser_class_nest)
#define in_single		(parser->parser_in_single)
#define in_def			(parser->parser_in_def)
#define compile_for_eval	(parser->parser_compile_for_eval)
#define cur_mid			(parser->parser_cur_mid)
#define in_defined		(parser->parser_in_defined)
#define tokenbuf		(parser->parser_tokenbuf)
#define tokidx			(parser->parser_tokidx)
#define toksiz			(parser->parser_toksiz)
#define lex_input		(parser->parser_lex_input)
#define lex_lastline		(parser->parser_lex_lastline)
#define lex_pbeg		(parser->parser_lex_pbeg)
#define lex_p			(parser->parser_lex_p)
#define lex_pend		(parser->parser_lex_pend)
#define heredoc_end		(parser->parser_heredoc_end)
#define command_start		(parser->parser_command_start)
#define lex_gets_ptr		(parser->parser_lex_gets_ptr)
#define lex_gets		(parser->parser_lex_gets)
#define lvtbl			(parser->parser_lvtbl)
#ifdef RIPPER
#define ruby__end__seen		(parser->parser_ruby__end__seen)
#define ruby_sourceline		(parser->parser_ruby_sourceline)
#define ruby_sourcefile		(parser->parser_ruby_sourcefile)
#endif

static int yylex _((void*, void*));

#ifndef RIPPER
#define yyparse parser_yyparse
#define yydebug ruby_yydebug

static NODE *cond_gen _((struct parser_params*,NODE*));
#define cond(node) cond_gen(parser, node)
static NODE *logop_gen _((struct parser_params*,enum node_type,NODE*,NODE*));
#define logop(type,node1,node2) logop_gen(parser, type, node1, node2)

static int cond_negative _((NODE**));

static NODE *newline_node _((NODE*));
static void fixpos  _((NODE*,NODE*));

static int value_expr_gen _((struct parser_params*,NODE*));
static void void_expr_gen _((struct parser_params*,NODE*));
static NODE *remove_begin _((NODE*));
#define value_expr(node) value_expr_gen(parser, (node) = remove_begin(node))
#define void_expr(node) void_expr_gen(parser, (node) = remove_begin(node))
static void void_stmts_gen _((struct parser_params*,NODE*));
#define void_stmts(node) void_stmts_gen(parser, node)
static void reduce_nodes _((NODE**));

static NODE *block_append _((NODE*,NODE*));
static NODE *list_append _((NODE*,NODE*));
static NODE *list_concat _((NODE*,NODE*));
static NODE *arg_concat _((NODE*,NODE*));
static NODE *literal_concat _((NODE*,NODE*));
static NODE *new_evstr _((NODE*));
static NODE *evstr2dstr _((NODE*));

static NODE *call_op_gen _((struct parser_params*,NODE*,ID,int,NODE*));
#define call_op(recv,id,narg,arg1) call_op_gen(parser, recv,id,narg,arg1)

static NODE *negate_lit _((NODE*));
static NODE *ret_args _((NODE*));
static NODE *arg_blk_pass _((NODE*,NODE*));
static NODE *new_call _((NODE*,ID,NODE*));
static NODE *new_fcall_gen _((struct parser_params*,ID,NODE*));
#define new_fcall(id,args) new_fcall_gen(parser, id, args)
static NODE *new_super  _((NODE*));
static NODE *new_yield  _((NODE*));

static NODE *gettable_gen _((struct parser_params*,ID));
#define gettable(id) gettable_gen(parser,id)
static NODE *assignable_gen _((struct parser_params*,ID,NODE*));
#define assignable(id,node) assignable_gen(parser, id, node)
static NODE *new_bv_gen _((struct parser_params*,ID,NODE*));
#define new_bv(id,node) new_bv_gen(parser, id, node)
static NODE *aryset_gen _((struct parser_params*,NODE*,NODE*));
#define aryset(node1,node2) aryset_gen(parser, node1, node2)
static NODE *attrset_gen _((struct parser_params*,NODE*,ID));
#define attrset(node,id) attrset_gen(parser, node, id)

static void rb_backref_error _((NODE*));
static NODE *node_assign_gen _((struct parser_params*,NODE*,NODE*));
#define node_assign(node1, node2) node_assign_gen(parser, node1, node2)

static NODE *match_op_gen _((struct parser_params*,NODE*,NODE*));
#define match_op(node1,node2) match_op_gen(parser, node1, node2)

static void local_push_gen _((struct parser_params*,int));
#define local_push(top) local_push_gen(parser,top)
static void local_pop_gen _((struct parser_params*));
#define local_pop() local_pop_gen(parser)
static int  local_append_gen _((struct parser_params*, ID));
#define local_append(id) local_append_gen(parser, id)
static int  local_cnt_gen _((struct parser_params*, ID));
#define local_cnt(id) local_cnt_gen(parser, id)
static int  local_id_gen _((struct parser_params*, ID));
#define local_id(id) local_id_gen(parser, id)
static ID  *local_tbl_gen _((struct parser_params*));
#define local_tbl() local_tbl_gen(parser)
static ID   internal_id _((void));

static struct RVarmap *dyna_push_gen _((struct parser_params*));
#define dyna_push() dyna_push_gen(parser)
static void dyna_pop_gen _((struct parser_params*, struct RVarmap*));
#define dyna_pop(vars) dyna_pop_gen(parser, vars)
static int dyna_in_block_gen _((struct parser_params*));
#define dyna_in_block() dyna_in_block_gen(parser)
static NODE *dyna_init_gen _((struct parser_params*, NODE*, struct RVarmap *));
#define dyna_init(node, pre) dyna_init_gen(parser, node, pre)
static void dyna_var_gen _((struct parser_params*,ID));
#define dyna_var(id) dyna_var_gen(parser, id)
static void dyna_check_gen _((struct parser_params*,ID));
#define dyna_check(id) dyna_check_gen(parser, id)

static void top_local_init_gen _((struct parser_params*));
#define top_local_init() top_local_init_gen(parser)
static void top_local_setup_gen _((struct parser_params*));
#define top_local_setup() top_local_setup_gen(parser)
#else
#define remove_begin(node) (node)
#endif /* !RIPPER */
static int lvar_defined_gen _((struct parser_params*, ID));
#define lvar_defined(id) lvar_defined_gen(parser, id)

#define RE_OPTION_ONCE 0x80

#define NODE_STRTERM NODE_ZARRAY	/* nothing to gc */
#define NODE_HEREDOC NODE_ARRAY 	/* 1, 3 to gc */
#define SIGN_EXTEND(x,n) (((1<<(n)-1)^((x)&~(~0<<(n))))-(1<<(n)-1))
#define nd_func u1.id
#if SIZEOF_SHORT == 2
#define nd_term(node) ((signed short)(node)->u2.id)
#else
#define nd_term(node) SIGN_EXTEND((node)->u2.id, CHAR_BIT*2)
#endif
#define nd_paren(node) (char)((node)->u2.id >> CHAR_BIT*2)
#define nd_nest u3.cnt

/****** Ripper *******/

#ifdef RIPPER
#define RIPPER_VERSION "0.1.0"

#include "eventids1.c"
#include "eventids2.c"
static ID ripper_id_gets;

static VALUE ripper_dispatch0 _((struct parser_params*,ID));
static VALUE ripper_dispatch1 _((struct parser_params*,ID,VALUE));
static VALUE ripper_dispatch2 _((struct parser_params*,ID,VALUE,VALUE));
static VALUE ripper_dispatch3 _((struct parser_params*,ID,VALUE,VALUE,VALUE));
static VALUE ripper_dispatch4 _((struct parser_params*,ID,VALUE,VALUE,VALUE,VALUE));
static VALUE ripper_dispatch5 _((struct parser_params*,ID,VALUE,VALUE,VALUE,VALUE,VALUE));

#define dispatch0(n)            ripper_dispatch0(parser, TOKEN_PASTE(ripper_id_, n))
#define dispatch1(n,a)          ripper_dispatch1(parser, TOKEN_PASTE(ripper_id_, n), a)
#define dispatch2(n,a,b)        ripper_dispatch2(parser, TOKEN_PASTE(ripper_id_, n), a, b)
#define dispatch3(n,a,b,c)      ripper_dispatch3(parser, TOKEN_PASTE(ripper_id_, n), a, b, c)
#define dispatch4(n,a,b,c,d)    ripper_dispatch4(parser, TOKEN_PASTE(ripper_id_, n), a, b, c, d)
#define dispatch5(n,a,b,c,d,e)  ripper_dispatch5(parser, TOKEN_PASTE(ripper_id_, n), a, b, c, d, e)

#define yyparse ripper_yyparse
#define yydebug ripper_yydebug

static VALUE ripper_intern _((const char*));
static VALUE ripper_id2sym _((ID));

#define arg_new() dispatch0(arglist_new)
#define arg_add(l,a) dispatch2(arglist_add, l, a)
#define arg_prepend(l,a) dispatch2(arglist_prepend, l, a)
#define arg_add_star(l,a) dispatch2(arglist_add_star, l, a)
#define arg_add_block(l,b) dispatch2(arglist_add_block, l, b)
#define arg_add_optblock(l,b) ((b)==Qundef? l : dispatch2(arglist_add_block, l, b))
#define bare_assoc(v) dispatch1(bare_assoc_hash, v)
#define arg_add_assocs(l,b) arg_add(l, bare_assoc(b))

#define args2mrhs(a) dispatch1(mrhs_new_from_arglist, a)
#define mrhs_new() dispatch0(mrhs_new)
#define mrhs_add(l,a) dispatch2(mrhs_add, l, a)
#define mrhs_add_star(l,a) dispatch2(mrhs_add_star, l, a)

#define mlhs_new() dispatch0(mlhs_new)
#define mlhs_add(l,a) dispatch2(mlhs_add, l, a)
#define mlhs_add_star(l,a) dispatch2(mlhs_add_star, l, a)

#define blockvar_new(p) dispatch1(blockvar_new, p)
#define blockvar_add_star(l,a) dispatch2(blockvar_add_star, l, a)
#define blockvar_add_block(l,a) dispatch2(blockvar_add_block, l, a)

#define method_optarg(m,a) ((a)==Qundef ? m : dispatch2(method_add_arg,m,a))
#define method_arg(m,a) dispatch2(method_add_arg,m,a)
#define escape_Qundef(x) ((x)==Qundef ? Qnil : (x))

#define FIXME 0

#endif /* RIPPER */

#ifndef RIPPER
# define ifndef_ripper(x) x
#else
# define ifndef_ripper(x)
#endif

#ifndef RIPPER
# define rb_warn0(fmt)    rb_warn(fmt)
# define rb_warnI(fmt,a)  rb_warn(fmt,a)
# define rb_warnS(fmt,a)  rb_warn(fmt,a)
# define rb_warning0(fmt) rb_warning(fmt)
#else
# define rb_warn0(fmt)    ripper_warn0(parser, fmt)
# define rb_warnI(fmt,a)  ripper_warnI(parser, fmt, a)
# define rb_warnS(fmt,a)  ripper_warnS(parser, fmt, a)
# define rb_warning0(fmt) ripper_warning0(parser, fmt)
static void ripper_warn0 _((struct parser_params*, const char*));
static void ripper_warnI _((struct parser_params*, const char*, int));
static void ripper_warnS _((struct parser_params*, const char*, const char*));
static void ripper_warning0 _((struct parser_params*, const char*));
#endif

#ifdef RIPPER
static void ripper_compile_error _((struct parser_params*, const char *fmt, ...));
# define rb_compile_error ripper_compile_error
# define compile_error ripper_compile_error
# define PARSER_ARG parser,
#else
# define compile_error rb_compile_error
# define PARSER_ARG
#endif

#define NEW_BLOCK_VAR(b, v) NEW_NODE(NODE_BLOCK_PASS, 0, b, v)

/* Older versions of Yacc set YYMAXDEPTH to a very low value by default (150,
   for instance).  This is too low for Ruby to parse some files, such as
   date/format.rb, therefore bump the value up to at least Bison's default. */
#ifdef OLD_YACC
#ifndef YYMAXDEPTH
#define YYMAXDEPTH 10000
#endif
#endif

%}

%pure_parser

%union {
    VALUE val;
    NODE *node;
    ID id;
    int num;
    struct RVarmap *vars;
}

/*%%%*/
%token
/*%
%token <val>
%*/
        kCLASS
	kMODULE
	kDEF
	kUNDEF
	kBEGIN
	kRESCUE
	kENSURE
	kEND
	kIF
	kUNLESS
	kTHEN
	kELSIF
	kELSE
	kCASE
	kWHEN
	kWHILE
	kUNTIL
	kFOR
	kBREAK
	kNEXT
	kREDO
	kRETRY
	kIN
	kDO
	kDO_COND
	kDO_BLOCK
	kRETURN
	kYIELD
	kSUPER
	kSELF
	kNIL
	kTRUE
	kFALSE
	kAND
	kOR
	kNOT
	kIF_MOD
	kUNLESS_MOD
	kWHILE_MOD
	kUNTIL_MOD
	kRESCUE_MOD
	kALIAS
	kDEFINED
	klBEGIN
	klEND
	k__LINE__
	k__FILE__

%token <id>   tIDENTIFIER tFID tGVAR tIVAR tCONSTANT tCVAR tLABEL
%token <node> tINTEGER tFLOAT tSTRING_CONTENT
%token <node> tNTH_REF tBACK_REF
%token <num>  tREGEXP_END

%type <node> singleton strings string string1 xstring regexp
%type <node> string_contents xstring_contents string_content
%type <node> words qwords word_list qword_list word
%type <node> literal numeric dsym cpath
%type <node> bodystmt compstmt stmts stmt expr arg primary command command_call method_call
%type <node> expr_value arg_value primary_value
%type <node> if_tail opt_else case_body cases opt_rescue exc_list exc_var opt_ensure
%type <node> args when_args call_args call_args2 open_args paren_args opt_paren_args
%type <node> command_args aref_args opt_block_arg block_arg var_ref var_lhs
%type <node> mrhs superclass block_call block_command
%type <node> f_arglist f_args f_optarg f_opt f_block_arg opt_f_block_arg
%type <node> assoc_list assocs assoc undef_list backref string_dvar
%type <node> for_var block_var opt_block_var block_var_def block_param
%type <node> opt_bv_decl bv_decls bv_decl
%type <node> brace_block cmd_brace_block do_block lhs none fitem
%type <node> mlhs mlhs_head mlhs_basic mlhs_entry mlhs_item mlhs_node
%type <id>   fsym variable sym symbol operation operation2 operation3
%type <id>   cname fname op f_rest_arg
%type <num>  f_norm_arg f_arg
/*%%%*/
/*%
%type <val> program reswords then do dot_or_colon
%*/
%token tUPLUS 		/* unary+ */
%token tUMINUS 		/* unary- */
%token tPOW		/* ** */
%token tCMP  		/* <=> */
%token tEQ  		/* == */
%token tEQQ  		/* === */
%token tNEQ  		/* != */
%token tGEQ  		/* >= */
%token tLEQ  		/* <= */
%token tANDOP tOROP	/* && and || */
%token tMATCH tNMATCH	/* =~ and !~ */
%token tDOT2 tDOT3	/* .. and ... */
%token tAREF tASET	/* [] and []= */
%token tLSHFT tRSHFT	/* << and >> */
%token tCOLON2		/* :: */
%token tCOLON3		/* :: at EXPR_BEG */
%token <id> tOP_ASGN	/* +=, -=  etc. */
%token tASSOC		/* => */
%token tLPAREN		/* ( */
%token tLPAREN_ARG	/* ( */
%token tRPAREN		/* ) */
%token tLBRACK		/* [ */
%token tLBRACE		/* { */
%token tLBRACE_ARG	/* { */
%token tSTAR		/* * */
%token tAMPER		/* & */
%token tSYMBEG tSTRING_BEG tXSTRING_BEG tREGEXP_BEG tWORDS_BEG tQWORDS_BEG
%token tSTRING_DBEG tSTRING_DVAR tSTRING_END

/*
 *	precedence table
 */

%nonassoc tLOWEST
%nonassoc tLBRACE_ARG

%nonassoc  kIF_MOD kUNLESS_MOD kWHILE_MOD kUNTIL_MOD
%left  kOR kAND
%right kNOT
%nonassoc kDEFINED
%right '=' tOP_ASGN
%left kRESCUE_MOD
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
		    /*%%%*/
			lex_state = EXPR_BEG;
			top_local_init();
			if (ruby_class == rb_cObject) class_nest = 0;
                        else class_nest = 1;
		    /*%
		        lex_state = EXPR_BEG;
		        class_nest = !parser->toplevel_p;
		        $$ = Qnil;
		    %*/
		    }
		  compstmt
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
			ruby_eval_tree = block_append(ruby_eval_tree, $2);
                        top_local_setup();
			class_nest = 0;
                    /*%
			class_nest = 0;
                        $$ = $2;
                        parser->result = dispatch1(program, $$);
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
			    $$ = NEW_RESCUE($1, $2, $3);
			}
			else if ($3) {
			    rb_warn("else without rescue is useless");
			    $$ = block_append($$, $3);
			}
			if ($4) {
			    if ($$) {
				$$ = NEW_ENSURE($$, $4);
			    }
			    else {
				$$ = block_append($4, NEW_NIL());
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
		        $$ = $1;
		    /*%
		    	$$ = $1;
		    %*/
		    }
		;

stmts		: none
		    /*%c%*/
		    /*%c
		    {
			$$ = dispatch2(stmts_add, dispatch0(stmts_new),
			                          dispatch0(void_stmt));
		    }
		    %*/
		| stmt
		    {
		    /*%%%*/
			$$ = newline_node(remove_begin($1));
		    /*%
			$$ = dispatch2(stmts_add, dispatch0(stmts_new), $1);
		    %*/
		    }
		| stmts terms stmt
		    {
		    /*%%%*/
			$$ = block_append($1, newline_node(remove_begin($3)));
		    /*%
			$$ = dispatch2(stmts_add, $1, $3);
		    %*/
		    }
		| error stmt
		    {
			$$ = remove_begin($2);
		    }
		;

stmt		: kALIAS fitem {lex_state = EXPR_FNAME;} fitem
		    {
		    /*%%%*/
		        $$ = NEW_ALIAS($2, $4);
		    /*%
			$$ = dispatch2(alias, $2, $4);
		    %*/
		    }
		| kALIAS tGVAR tGVAR
		    {
		    /*%%%*/
		        $$ = NEW_VALIAS($2, $3);
		    /*%
			$$ = dispatch2(var_alias, $2, $3);
		    %*/
		    }
		| kALIAS tGVAR tBACK_REF
		    {
		    /*%%%*/
			char buf[3];

			sprintf(buf, "$%c", (char)$3->nd_nth);
		        $$ = NEW_VALIAS($2, rb_intern(buf));
		    /*%
			$$ = dispatch2(var_alias, $2, $3);
		    %*/
		    }
		| kALIAS tGVAR tNTH_REF
		    {
		    /*%%%*/
		        yyerror("can't make alias for the number variables");
		        $$ = 0;
		    /*%
			$$ = dispatch2(var_alias, $2, $3);
			$$ = dispatch1(alias_error, $$);
		    %*/
		    }
		| kUNDEF undef_list
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(undef, $2);
		    %*/
		    }
		| stmt kIF_MOD expr_value
		    {
		    /*%%%*/
			$$ = NEW_IF(cond($3), $1, 0);
		        fixpos($$, $3);
			if (cond_negative(&$$->nd_cond)) {
		            $$->nd_else = $$->nd_body;
		            $$->nd_body = 0;
			}
		    /*%
			$$ = dispatch2(if_mod, $3, $1);
		    %*/
		    }
		| stmt kUNLESS_MOD expr_value
		    {
		    /*%%%*/
			$$ = NEW_UNLESS(cond($3), $1, 0);
		        fixpos($$, $3);
			if (cond_negative(&$$->nd_cond)) {
		            $$->nd_body = $$->nd_else;
		            $$->nd_else = 0;
			}
		    /*%
		    	$$ = dispatch2(unless_mod, $3, $1);
		    %*/
		    }
		| stmt kWHILE_MOD expr_value
		    {
		    /*%%%*/
			if ($1 && nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_WHILE(cond($3), $1->nd_body, 0);
			}
			else {
			    $$ = NEW_WHILE(cond($3), $1, 1);
			}
			if (cond_negative(&$$->nd_cond)) {
			    nd_set_type($$, NODE_UNTIL);
			}
		    /*%
			$$ = dispatch2(while_mod, $3, $1);
		    %*/
		    }
		| stmt kUNTIL_MOD expr_value
		    {
		    /*%%%*/
			if ($1 && nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_UNTIL(cond($3), $1->nd_body, 0);
			}
			else {
			    $$ = NEW_UNTIL(cond($3), $1, 1);
			}
			if (cond_negative(&$$->nd_cond)) {
			    nd_set_type($$, NODE_WHILE);
			}
		    /*%
			$$ = dispatch2(until_mod, $3, $1);
		    %*/
		    }
		| stmt kRESCUE_MOD stmt
		    {
		    /*%%%*/
			$$ = NEW_RESCUE($1, NEW_RESBODY(0,$3,0), 0);
		    /*%
			$$ = dispatch2(rescue_mod, $3, $1);
		    %*/
		    }
		| klBEGIN
		    {
		    /*%%%*/
			if (in_def || in_single) {
			    yyerror("BEGIN in method");
			}
			local_push(0);
		    /*%
			if (in_def || in_single) {
			    yyerror("BEGIN in method");
			}
		    %*/
		    }
		  '{' compstmt '}'
		    {
		    /*%%%*/
			ruby_eval_tree_begin = block_append(ruby_eval_tree_begin,
						            NEW_PREEXE($4));
		        local_pop();
		        $$ = 0;
		    /*%
			$$ = dispatch1(BEGIN, $4);
		    %*/
		    }
		| klEND '{' compstmt '}'
		    {
		    /*%%%*/
			if (in_def || in_single) {
			    rb_warn("END in method; use at_exit");
			}

			$$ = NEW_ITER(0, NEW_POSTEXE(), $3);
		    /*%
			if (in_def || in_single) {
			    rb_warn0("END in method; use at_exit");
			}
		    	$$ = dispatch1(END, $3);
		    %*/
		    }
		| lhs '=' command_call
		    {
		    /*%%%*/
			$$ = node_assign($1, $3);
		    /*%
		    	$$ = dispatch2(assign, $1, $3);
		    %*/
		    }
		| mlhs '=' command_call
		    {
		    /*%%%*/
			value_expr($3);
			$1->nd_value = ($1->nd_head) ? NEW_TO_ARY($3) : NEW_ARRAY($3);
			$$ = $1;
		    /*%
		    	$$ = dispatch2(massign, $1, $3);
		    %*/
		    }
		| var_lhs tOP_ASGN command_call
		    {
		    /*%%%*/
			value_expr($3);
			if ($1) {
			    ID vid = $1->nd_vid;
			    if ($2 == tOROP) {
				$1->nd_value = $3;
				$$ = NEW_OP_ASGN_OR(gettable(vid), $1);
				if (is_asgn_or_id(vid)) {
				    $$->nd_aid = vid;
				}
			    }
			    else if ($2 == tANDOP) {
				$1->nd_value = $3;
				$$ = NEW_OP_ASGN_AND(gettable(vid), $1);
			    }
			    else {
				$$ = $1;
				$$->nd_value = call_op(gettable(vid),$2,1,$3);
			    }
			}
			else {
			    $$ = 0;
			}
		    /*%
		    	$$ = dispatch3(opassign, $1, $2, $3);
		    %*/
		    }
		| primary_value '[' aref_args ']' tOP_ASGN command_call
		    {
		    /*%%%*/
                        NODE *args;

			value_expr($6);
		        args = NEW_LIST($6);
			if ($3 && nd_type($3) != NODE_ARRAY)
			    $3 = NEW_LIST($3);
			$3 = list_append($3, NEW_NIL());
			list_concat(args, $3);
			if ($5 == tOROP) {
			    $5 = 0;
			}
			else if ($5 == tANDOP) {
			    $5 = 1;
			}
			$$ = NEW_OP_ASGN1($1, $5, args);
		        fixpos($$, $1);
		    /*%
			$$ = dispatch2(aref_field, $1, $3);
		    	$$ = dispatch3(opassign, $$, $5, $6);
		    %*/
		    }
		| primary_value '.' tIDENTIFIER tOP_ASGN command_call
		    {
		    /*%%%*/
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    /*%
                        $$ = dispatch3(field, $1, ripper_id2sym('.'), $3);
			$$ = dispatch3(opassign, $$, $4, $5);
		    %*/
		    }
		| primary_value '.' tCONSTANT tOP_ASGN command_call
		    {
		    /*%%%*/
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    /*%
                        $$ = dispatch3(field, $1, ripper_id2sym('.'), $3);
			$$ = dispatch3(opassign, $$, $4, $5);
		    %*/
		    }
		| primary_value tCOLON2 tIDENTIFIER tOP_ASGN command_call
		    {
		    /*%%%*/
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    /*%
                        $$ = dispatch3(field, $1, ripper_intern("::"), $3);
		    	$$ = dispatch3(opassign, $$, $4, $5);
		    %*/
		    }
		| backref tOP_ASGN command_call
		    {
		    /*%%%*/
		        rb_backref_error($1);
			$$ = 0;
		    /*%
                        $$ = dispatch2(assign, dispatch1(var_field, $1), $3);
		    	$$ = dispatch1(assign_error, $$);
		    %*/
		    }
		| lhs '=' mrhs
		    {
		    /*%%%*/
			$$ = node_assign($1, NEW_SVALUE($3));
		    /*%
		    	$$ = dispatch2(assign, $1, $3);
		    %*/
		    }
		| mlhs '=' arg_value
		    {
		    /*%%%*/
			$1->nd_value = ($1->nd_head) ? NEW_TO_ARY($3) : NEW_ARRAY($3);
			$$ = $1;
		    /*%
		    	dispatch2(massign, $1, $3);
		    %*/
		    }
		| mlhs '=' mrhs
		    {
		    /*%%%*/
			$1->nd_value = $3;
			$$ = $1;
		    /*%
		    	$$ = dispatch2(massign, $1, $3);
		    %*/
		    }
		| expr
		;

expr		: command_call
		| expr kAND expr
		    {
		    /*%%%*/
			$$ = logop(NODE_AND, $1, $3);
		    /*%
		    	$$ = dispatch3(binary, $1, ripper_intern("and"), $3);
		    %*/
		    }
		| expr kOR expr
		    {
		    /*%%%*/
			$$ = logop(NODE_OR, $1, $3);
		    /*%
		    	$$ = dispatch3(binary, $1, ripper_intern("or"), $3);
		    %*/
		    }
		| kNOT expr
		    {
		    /*%%%*/
			$$ = NEW_NOT(cond($2));
		    /*%
		    	$$ = dispatch2(unary, ripper_intern("not"), $2);
		    %*/
		    }
		| '!' command_call
		    {
		    /*%%%*/
			$$ = NEW_NOT(cond($2));
		    /*%
		    	$$ = dispatch2(unary, ID2SYM('!'), $2);
		    %*/
		    }
		| do_block
		    {
			$$ = $1;
			nd_set_type($$, NODE_LAMBDA);
		    }
		| arg
		;

expr_value	: expr
		    {
		    /*%%%*/
			value_expr($$);
			$$ = $1;
		    /*%
		    	$$ = $1;
		    %*/
		    }
		;

command_call	: command
		| block_command
		| kRETURN call_args
		    {
		    /*%%%*/
			$$ = NEW_RETURN(ret_args($2));
		    /*%
		    	$$ = dispatch1(return, $2);
		    %*/
		    }
		| kBREAK call_args
		    {
		    /*%%%*/
			$$ = NEW_BREAK(ret_args($2));
		    /*%
		    	$$ = dispatch1(break, $2);
		    %*/
		    }
		| kNEXT call_args
		    {
		    /*%%%*/
			$$ = NEW_NEXT(ret_args($2));
		    /*%
		    	$$ = dispatch1(next, $2);
		    %*/
		    }
		;

block_command	: block_call
		| block_call '.' operation2 command_args
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
		    /*%
		    	$$ = dispatch3(call, $1, ripper_id2sym('.'), $3);
                        $$ = method_arg($$, $4);
		    %*/
		    }
		| block_call tCOLON2 operation2 command_args
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
		    /*%
		    	$$ = dispatch3(call, $1, ripper_intern("::"), $3);
                        $$ = method_arg($$, $4);
		    %*/
		    }
		;

cmd_brace_block	: tLBRACE_ARG
		    {
		    /*%%%*/
			$<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    /*%
		    %*/
		    }
		  opt_block_var {$<vars>$ = ruby_dyna_vars;}
		  compstmt
		  '}'
		    {
		    /*%%%*/
			$3->nd_body = block_append($3->nd_body,
						   dyna_init($5, $<vars>4));
			$$ = $3;
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    /*%
			$$ = dispatch2(brace_block, escape_Qundef($3), $5);
		    %*/
		    }
		;

command		: operation command_args       %prec tLOWEST
		    {
		    /*%%%*/
			$$ = new_fcall($1, $2);
		        fixpos($$, $2);
		    /*%
		        $$ = dispatch2(command, $1, $2);
		    %*/
		    }
		| operation command_args cmd_brace_block
		    {
		    /*%%%*/
			$$ = new_fcall($1, $2);
			if ($3) {
			    if (nd_type($$) == NODE_BLOCK_PASS) {
				compile_error(PARSER_ARG "both block arg and actual block given");
			    }
			    $3->nd_iter = $$;
			    $$ = $3;
			}
		        fixpos($$, $2);
		    /*%
		        $$ = dispatch2(command, $1, $2);
                        $$ = dispatch2(iter_block, $$, $3);
		    %*/
		    }
		| primary_value '.' operation2 command_args	%prec tLOWEST
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    /*%
			$$ = dispatch4(command_call, $1, ripper_id2sym('.'), $3, $4);
		    %*/
		    }
		| primary_value '.' operation2 command_args cmd_brace_block
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
			if ($5) {
			    if (nd_type($$) == NODE_BLOCK_PASS) {
				compile_error(PARSER_ARG "both block arg and actual block given");
			    }
			    $5->nd_iter = $$;
			    $$ = $5;
			}
		        fixpos($$, $1);
		    /*%
			$$ = dispatch4(command_call, $1, ripper_id2sym('.'), $3, $4);
			$$ = dispatch2(iter_block, $$, $5);
		    %*/
		   }
		| primary_value tCOLON2 operation2 command_args	%prec tLOWEST
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    /*%
			$$ = dispatch4(command_call, $1, ripper_intern("::"), $3, $4);
		    %*/
		    }
		| primary_value tCOLON2 operation2 command_args cmd_brace_block
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
			if ($5) {
			    if (nd_type($$) == NODE_BLOCK_PASS) {
				compile_error(PARSER_ARG "both block arg and actual block given");
			    }
			    $5->nd_iter = $$;
			    $$ = $5;
			}
		        fixpos($$, $1);
		    /*%
			$$ = dispatch4(command_call, $1, ripper_intern("::"), $3, $4);
                        $$ = dispatch2(iter_block, $$, $5);
		    %*/
		   }
		| kSUPER command_args
		    {
		    /*%%%*/
			$$ = new_super($2);
		        fixpos($$, $2);
		    /*%
			$$ = dispatch1(super, $2);
		    %*/
		    }
		| kYIELD command_args
		    {
		    /*%%%*/
			$$ = new_yield($2);
		        fixpos($$, $2);
		    /*%
			$$ = dispatch1(yield, $2);
		    %*/
		    }
		;

mlhs		: mlhs_basic
		| tLPAREN mlhs_entry rparen
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(mlhs_paren, $2);
		    %*/
		    }
		;

mlhs_entry	: mlhs_basic
		| tLPAREN mlhs_entry rparen
		    {
		    /*%%%*/
			$$ = NEW_MASGN(NEW_LIST($2), 0);
		    /*%
			$$ = dispatch1(mlhs_paren, $2);
		    %*/
		    }
		;

mlhs_basic	: mlhs_head
		    {
		    /*%%%*/
			$$ = NEW_MASGN($1, 0);
		    /*%
			$$ = $1;
		    %*/
		    }
		| mlhs_head mlhs_item
		    {
		    /*%%%*/
			$$ = NEW_MASGN(list_append($1,$2), 0);
		    /*%
			$$ = mlhs_add($1, $2);
		    %*/
		    }
		| mlhs_head tSTAR mlhs_node
		    {
		    /*%%%*/
			$$ = NEW_MASGN($1, $3);
		    /*%
			$$ = mlhs_add_star($1, $3);
		    %*/
		    }
		| mlhs_head tSTAR
		    {
		    /*%%%*/
			$$ = NEW_MASGN($1, -1);
		    /*%
			$$ = mlhs_add_star($1, Qnil);
		    %*/
		    }
		| tSTAR mlhs_node
		    {
		    /*%%%*/
			$$ = NEW_MASGN(0, $2);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), $2);
		    %*/
		    }
		| tSTAR
		    {
		    /*%%%*/
			$$ = NEW_MASGN(0, -1);
		    /*%
			$$ = mlhs_add_star(mlhs_new(), Qnil);
		    %*/
		    }
		;

mlhs_item	: mlhs_node
		| tLPAREN mlhs_entry rparen
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
			$$ = NEW_LIST($1);
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

mlhs_node	: variable
		    {
		    /*%%%*/
			$$ = assignable($1, 0);
		    /*%
			$$ = $1;
		    %*/
		    }
		| primary_value '[' aref_args ']'
		    {
		    /*%%%*/
			$$ = aryset($1, $3);
		    /*%
			$$ = dispatch2(aref_field, $1, $3);
		    %*/
		    }
		| primary_value '.' tIDENTIFIER
		    {
		    /*%%%*/
			$$ = attrset($1, $3);
		    /*%
			$$ = dispatch3(field, $1, ripper_id2sym('.'), $3);
		    %*/
		    }
		| primary_value tCOLON2 tIDENTIFIER
		    {
		    /*%%%*/
			$$ = attrset($1, $3);
		    /*%
			$$ = dispatch2(constpath_field, $1, $3);
		    %*/
		    }
		| primary_value '.' tCONSTANT
		    {
		    /*%%%*/
			$$ = attrset($1, $3);
		    /*%
			$$ = dispatch3(field, $1, ripper_id2sym('.'), $3);
		    %*/
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
		    /*%%%*/
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = NEW_CDECL(0, 0, NEW_COLON2($1, $3));
		    /*%
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = dispatch2(constpath_field, $1, $3);
		    %*/
		    }
		| tCOLON3 tCONSTANT
		    {
		    /*%%%*/
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = NEW_CDECL(0, 0, NEW_COLON3($2));
		    /*%
			$$ = dispatch1(topconst_field, $2);
		    %*/
		    }
		| backref
		    {
		    /*%%%*/
		        rb_backref_error($1);
			$$ = 0;
		    /*%
			$$ = dispatch1(var_field, $1);
                        $$ = dispatch1(assign_error, $$);
		    %*/
		    }
		;

lhs		: variable
		    {
		    /*%%%*/
			$$ = assignable($1, 0);
		    /*%
			$$ = dispatch1(var_field, $1);
		    %*/
		    }
		| primary_value '[' aref_args ']'
		    {
		    /*%%%*/
			$$ = aryset($1, $3);
		    /*%
			$$ = dispatch2(aref_field, $1, $3);
		    %*/
		    }
		| primary_value '.' tIDENTIFIER
		    {
		    /*%%%*/
			$$ = attrset($1, $3);
		    /*%
			$$ = dispatch3(field, $1, ripper_id2sym('.'), $3);
		    %*/
		    }
		| primary_value tCOLON2 tIDENTIFIER
		    {
		    /*%%%*/
			$$ = attrset($1, $3);
		    /*%
			$$ = dispatch3(field, $1, ripper_intern("::"), $3);
		    %*/
		    }
		| primary_value '.' tCONSTANT
		    {
		    /*%%%*/
			$$ = attrset($1, $3);
		    /*%
			$$ = dispatch3(field, $1, ripper_id2sym('.'), $3);
		    %*/
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
		    /*%%%*/
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = NEW_CDECL(0, 0, NEW_COLON2($1, $3));
		    /*%
                        $$ = dispatch2(constpath_field, $1, $3);
			if (in_def || in_single) {
			    $$ = dispatch1(assign_error, $$);
			}
		    %*/
		    }
		| tCOLON3 tCONSTANT
		    {
		    /*%%%*/
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = NEW_CDECL(0, 0, NEW_COLON3($2));
		    /*%
                        $$ = dispatch1(topconst_field, $2);
			if (in_def || in_single) {
			    $$ = dispatch1(assign_error, $$);
			}
		    %*/
		    }
		| backref
		    {
		    /*%%%*/
		        rb_backref_error($1);
			$$ = 0;
		    /*%
			$$ = dispatch1(assign_error, $1);
		    %*/
		    }
		;

cname		: tIDENTIFIER
		    {
		    /*%%%*/
			yyerror("class/module name must be CONSTANT");
		    /*%
			$$ = dispatch1(class_name_error, $1);
		    %*/
		    }
		| tCONSTANT
		;

cpath		: tCOLON3 cname
		    {
		    /*%%%*/
			$$ = NEW_COLON3($2);
		    /*%
			$$ = dispatch1(topconst_ref, $2);
		    %*/
		    }
		| cname
		    {
		    /*%%%*/
			$$ = NEW_COLON2(0, $$);
		    /*%
			$$ = dispatch1(const_ref, $1);
		    %*/
		    }
		| primary_value tCOLON2 cname
		    {
		    /*%%%*/
			$$ = NEW_COLON2($1, $3);
		    /*%
			$$ = dispatch2(constpath_ref, $1, $3);
		    %*/
		    }
		;

fname		: tIDENTIFIER
		| tCONSTANT
		| tFID
		| op
		    {
		    /*%%%*/
			lex_state = EXPR_END;
			$$ = $1;
		    /*%
			lex_state = EXPR_END;
			$$ = $1;
		    %*/
		    }
		| reswords
		    {
		    /*%%%*/
			lex_state = EXPR_END;
			$$ = $<id>1;
		    /*%
			lex_state = EXPR_END;
			$$ = $1;
		    %*/
		    }
		;

fsym		: fname
		| symbol
		;

fitem		: fsym
		    {
		    /*%%%*/
			$$ = NEW_LIT(ID2SYM($1));
		    /*%
			$$ = dispatch1(symbol_literal, $1);
		    %*/
		    }
		| dsym
		;

undef_list	: fitem
		    {
		    /*%%%*/
			$$ = NEW_UNDEF($1);
		    /*%
			$$ = rb_ary_new3(1, $1);
		    %*/
		    }
		| undef_list ',' {lex_state = EXPR_FNAME;} fitem
		    {
		    /*%%%*/
			$$ = block_append($1, NEW_UNDEF($4));
		    /*%
			rb_ary_push($1, $4);
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
		| '>'		{ ifndef_ripper($$ = '>'); }
		| tGEQ		{ ifndef_ripper($$ = tGEQ); }
		| '<'		{ ifndef_ripper($$ = '<'); }
		| tLEQ		{ ifndef_ripper($$ = tLEQ); }
		| tLSHFT	{ ifndef_ripper($$ = tLSHFT); }
		| tRSHFT	{ ifndef_ripper($$ = tRSHFT); }
		| '+'		{ ifndef_ripper($$ = '+'); }
		| '-'		{ ifndef_ripper($$ = '-'); }
		| '*'		{ ifndef_ripper($$ = '*'); }
		| tSTAR		{ ifndef_ripper($$ = '*'); }
		| '/'		{ ifndef_ripper($$ = '/'); }
		| '%'		{ ifndef_ripper($$ = '%'); }
		| tPOW		{ ifndef_ripper($$ = tPOW); }
		| '~'		{ ifndef_ripper($$ = '~'); }
		| tUPLUS	{ ifndef_ripper($$ = tUPLUS); }
		| tUMINUS	{ ifndef_ripper($$ = tUMINUS); }
		| tAREF		{ ifndef_ripper($$ = tAREF); }
		| tASET		{ ifndef_ripper($$ = tASET); }
		| '`'		{ ifndef_ripper($$ = '`'); }
		;

reswords	: k__LINE__ | k__FILE__  | klBEGIN | klEND
		| kALIAS | kAND | kBEGIN | kBREAK | kCASE | kCLASS | kDEF
		| kDEFINED | kDO | kELSE | kELSIF | kEND | kENSURE | kFALSE
		| kFOR | kIN | kMODULE | kNEXT | kNIL | kNOT
		| kOR | kREDO | kRESCUE | kRETRY | kRETURN | kSELF | kSUPER
		| kTHEN | kTRUE | kUNDEF | kWHEN | kYIELD
		| kIF_MOD | kUNLESS_MOD | kWHILE_MOD | kUNTIL_MOD | kRESCUE_MOD
		;

arg		: lhs '=' arg
		    {
		    /*%%%*/
			$$ = node_assign($1, $3);
		    /*%
		    	$$ = dispatch2(assign, $1, $3);
		    %*/
		    }
		| lhs '=' arg kRESCUE_MOD arg
		    {
		    /*%%%*/
			$$ = node_assign($1, NEW_RESCUE($3, NEW_RESBODY(0,$5,0), 0));
		    /*%
		    	$$ = dispatch2(assign, $1, dispatch2(rescue_mod,$3,$5));
		    %*/
		    }
		| var_lhs tOP_ASGN arg
		    {
		    /*%%%*/
			value_expr($3);
			if ($1) {
			    ID vid = $1->nd_vid;
			    if ($2 == tOROP) {
				$1->nd_value = $3;
				$$ = NEW_OP_ASGN_OR(gettable(vid), $1);
				if (is_asgn_or_id(vid)) {
				    $$->nd_aid = vid;
				}
			    }
			    else if ($2 == tANDOP) {
				$1->nd_value = $3;
				$$ = NEW_OP_ASGN_AND(gettable(vid), $1);
			    }
			    else {
				$$ = $1;
				$$->nd_value = call_op(gettable(vid),$2,1,$3);
			    }
			}
			else {
			    $$ = 0;
			}
		    /*%
		    	$$ = dispatch3(opassign, $1, $2, $3);
		    %*/
		    }
		| primary_value '[' aref_args ']' tOP_ASGN arg
		    {
		    /*%%%*/
                        NODE *args;

			value_expr($6);
			args = NEW_LIST($6);
			if ($3 && nd_type($3) != NODE_ARRAY)
			    $3 = NEW_LIST($3);
			$3 = list_append($3, NEW_NIL());
			list_concat(args, $3);
			if ($5 == tOROP) {
			    $5 = 0;
			}
			else if ($5 == tANDOP) {
			    $5 = 1;
			}
			$$ = NEW_OP_ASGN1($1, $5, args);
		        fixpos($$, $1);
		    /*%
			$1 = dispatch2(aref_field, $1, $3);
		    	$$ = dispatch3(opassign, $1, $5, $6);
		    %*/
		    }
		| primary_value '.' tIDENTIFIER tOP_ASGN arg
		    {
		    /*%%%*/
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    /*%
			$1 = dispatch3(field, $1, ripper_id2sym('.'), $3);
		    	$$ = dispatch3(opassign, $1, $4, $5);
		    %*/
		    }
		| primary_value '.' tCONSTANT tOP_ASGN arg
		    {
		    /*%%%*/
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    /*%
			$1 = dispatch3(field, $1, ripper_id2sym('.'), $3);
		    	$$ = dispatch3(opassign, $1, $4, $5);
		    %*/
		    }
		| primary_value tCOLON2 tIDENTIFIER tOP_ASGN arg
		    {
		    /*%%%*/
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    /*%
			$1 = dispatch3(field, $1, ripper_intern("::"), $3);
		    	$$ = dispatch3(opassign, $1, $4, $5);
		    %*/
		    }
		| primary_value tCOLON2 tCONSTANT tOP_ASGN arg
		    {
		    /*%%%*/
			yyerror("constant re-assignment");
			$$ = 0;
		    /*%
			$$ = dispatch2(constpath_field, $1, $3);
			$$ = dispatch3(opassign, $$, $4, $5);
                        $$ = dispatch1(assign_error, $$);
		    %*/
		    }
		| tCOLON3 tCONSTANT tOP_ASGN arg
		    {
		    /*%%%*/
			yyerror("constant re-assignment");
			$$ = 0;
		    /*%
			$$ = dispatch1(topconst_field, $2);
			$$ = dispatch3(opassign, $$, $3, $4);
                        $$ = dispatch1(assign_error, $$);
		    %*/
		    }
		| backref tOP_ASGN arg
		    {
		    /*%%%*/
		        rb_backref_error($1);
			$$ = 0;
		    /*%
			$$ = dispatch1(var_field, $1);
			$$ = dispatch3(opassign, $$, $2, $3);
                        $$ = dispatch1(assign_error, $$);
		    %*/
		    }
		| arg tDOT2 arg
		    {
		    /*%%%*/
			value_expr($1);
			value_expr($3);
			if (nd_type($1) == NODE_LIT && FIXNUM_P($1->nd_lit) &&
			    nd_type($3) == NODE_LIT && FIXNUM_P($3->nd_lit)) {
			    $1->nd_lit = rb_range_new($1->nd_lit, $3->nd_lit, Qfalse);
			    $$ = $1;
			}
			else {
			    $$ = NEW_DOT2($1, $3);
			}
		    /*%
			$$ = dispatch2(dot2, $1, $3);
		    %*/
		    }
		| arg tDOT3 arg
		    {
		    /*%%%*/
			value_expr($1);
			value_expr($3);
			if (nd_type($1) == NODE_LIT && FIXNUM_P($1->nd_lit) &&
			    nd_type($3) == NODE_LIT && FIXNUM_P($3->nd_lit)) {
			    $1->nd_lit = rb_range_new($1->nd_lit, $3->nd_lit, Qtrue);
			    $$ = $1;
			}
			else {
			    $$ = NEW_DOT3($1, $3);
			}
		    /*%
			$$ = dispatch2(dot3, $1, $3);
		    %*/
		    }
		| arg '+' arg
		    {
		    /*%%%*/
			$$ = call_op($1, '+', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('+'), $3);
		    %*/
		    }
		| arg '-' arg
		    {
		    /*%%%*/
		        $$ = call_op($1, '-', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('-'), $3);
		    %*/
		    }
		| arg '*' arg
		    {
		    /*%%%*/
		        $$ = call_op($1, '*', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('*'), $3);
		    %*/
		    }
		| arg '/' arg
		    {
		    /*%%%*/
			$$ = call_op($1, '/', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('/'), $3);
		    %*/
		    }
		| arg '%' arg
		    {
		    /*%%%*/
			$$ = call_op($1, '%', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('%'), $3);
		    %*/
		    }
		| arg tPOW arg
		    {
		    /*%%%*/
			$$ = call_op($1, tPOW, 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("**"), $3);
		    %*/
		    }
		| tUMINUS_NUM tINTEGER tPOW arg
		    {
		    /*%%%*/
			$$ = call_op(call_op($2, tPOW, 1, $4), tUMINUS, 0, 0);
		    /*%
			$$ = dispatch3(binary, $2, ripper_intern("**"), $4);
			$$ = dispatch2(unary, ripper_intern("-@"), $$);
		    %*/
		    }
		| tUMINUS_NUM tFLOAT tPOW arg
		    {
		    /*%%%*/
			$$ = call_op(call_op($2, tPOW, 1, $4), tUMINUS, 0, 0);
		    /*%
			$$ = dispatch3(binary, $2, ripper_intern("**"), $4);
			$$ = dispatch2(unary, ripper_intern("-@"), $$);
		    %*/
		    }
		| tUPLUS arg
		    {
		    /*%%%*/
			if ($2 && nd_type($2) == NODE_LIT) {
			    $$ = $2;
			}
			else {
			    $$ = call_op($2, tUPLUS, 0, 0);
			}
		    /*%
			$$ = dispatch2(unary, ripper_intern("+@"), $2);
		    %*/
		    }
		| tUMINUS arg
		    {
		    /*%%%*/
			$$ = call_op($2, tUMINUS, 0, 0);
		    /*%
			$$ = dispatch2(unary, ripper_intern("-@"), $2);
		    %*/
		    }
		| arg '|' arg
		    {
		    /*%%%*/
		        $$ = call_op($1, '|', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('!'), $3);
		    %*/
		    }
		| arg '^' arg
		    {
		    /*%%%*/
			$$ = call_op($1, '^', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('^'), $3);
		    %*/
		    }
		| arg '&' arg
		    {
		    /*%%%*/
			$$ = call_op($1, '&', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('&'), $3);
		    %*/
		    }
		| arg tCMP arg
		    {
		    /*%%%*/
			$$ = call_op($1, tCMP, 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("<=>"), $3);
		    %*/
		    }
		| arg '>' arg
		    {
		    /*%%%*/
			$$ = call_op($1, '>', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('>'), $3);
		    %*/
		    }
		| arg tGEQ arg
		    {
		    /*%%%*/
			$$ = call_op($1, tGEQ, 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern(">="), $3);
		    %*/
		    }
		| arg '<' arg
		    {
		    /*%%%*/
			$$ = call_op($1, '<', 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ID2SYM('<'), $3);
		    %*/
		    }
		| arg tLEQ arg
		    {
		    /*%%%*/
			$$ = call_op($1, tLEQ, 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("<="), $3);
		    %*/
		    }
		| arg tEQ arg
		    {
		    /*%%%*/
			$$ = call_op($1, tEQ, 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("=="), $3);
		    %*/
		    }
		| arg tEQQ arg
		    {
		    /*%%%*/
			$$ = call_op($1, tEQQ, 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("==="), $3);
		    %*/
		    }
		| arg tNEQ arg
		    {
		    /*%%%*/
			$$ = NEW_NOT(call_op($1, tEQ, 1, $3));
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("!="), $3);
		    %*/
		    }
		| arg tMATCH arg
		    {
		    /*%%%*/
			$$ = match_op($1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("=~"), $3);
		    %*/
		    }
		| arg tNMATCH arg
		    {
		    /*%%%*/
			$$ = NEW_NOT(match_op($1, $3));
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("!~"), $3);
		    %*/
		    }
		| '!' arg
		    {
		    /*%%%*/
			$$ = NEW_NOT(cond($2));
		    /*%
			$$ = dispatch2(unary, ID2SYM('!'), $2);
		    %*/
		    }
		| '~' arg
		    {
		    /*%%%*/
			$$ = call_op($2, '~', 0, 0);
		    /*%
			$$ = dispatch2(unary, ID2SYM('~'), $2);
		    %*/
		    }
		| arg tLSHFT arg
		    {
		    /*%%%*/
			$$ = call_op($1, tLSHFT, 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("<<"), $3);
		    %*/
		    }
		| arg tRSHFT arg
		    {
		    /*%%%*/
			$$ = call_op($1, tRSHFT, 1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern(">>"), $3);
		    %*/
		    }
		| arg tANDOP arg
		    {
		    /*%%%*/
			$$ = logop(NODE_AND, $1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("&&"), $3);
		    %*/
		    }
		| arg tOROP arg
		    {
		    /*%%%*/
			$$ = logop(NODE_OR, $1, $3);
		    /*%
			$$ = dispatch3(binary, $1, ripper_intern("||"), $3);
		    %*/
		    }
		| kDEFINED opt_nl {in_defined = 1;} arg
		    {
		    /*%%%*/
		        in_defined = 0;
			$$ = NEW_DEFINED($4);
		    /*%
		        in_defined = 0;
			$$ = dispatch1(defined, $4);
		    %*/
		    }
		| arg '?' arg ':' arg
		    {
		    /*%%%*/
			$$ = NEW_IF(cond($1), $3, $5);
		        fixpos($$, $1);
		    /*%
			$$ = dispatch3(ifop, $1, $3, $5);
		    %*/
		    }
		| primary
		    {
			$$ = $1;
		    }
		;

arg_value	: arg
		    {
		    /*%%%*/
			value_expr($1);
			$$ = $1;
		    /*%
			$$ = $1;
		    %*/
		    }
		;

aref_args	: none
		| command opt_nl
		    {
		    /*%%%*/
		        rb_warn("parenthesize argument(s) for future version");
			$$ = NEW_LIST($1);
		    /*%
		        rb_warn0("parenthesize argument(s) for future version");
			$$ = arg_add(arg_new(), $1);
		    %*/
		    }
		| args trailer
		    {
			$$ = $1;
		    }
		| args ',' tSTAR arg opt_nl
		    {
		    /*%%%*/
			value_expr($4);
			$$ = arg_concat($1, $4);
		    /*%
			$$ = arg_add_star($1, $4);
		    %*/
		    }
		| assocs trailer
		    {
		    /*%%%*/
			$$ = NEW_LIST(NEW_HASH($1));
		    /*%
			$$ = arg_add_assocs(arg_new(), $1);
		    %*/
		    }
		| tSTAR arg opt_nl
		    {
		    /*%%%*/
			value_expr($2);
			$$ = newline_node(NEW_SPLAT($2));
		    /*%
			$$ = arg_add_star(arg_new(), $2);
		    %*/
		    }
		;

paren_args	: '(' none ')'
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(arg_paren, arg_new());
		    %*/
		    }
		| '(' call_args rparen
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(arg_paren, $2);
		    %*/
		    }
		| '(' block_call rparen
		    {
		    /*%%%*/
		        rb_warn("parenthesize argument for future version");
			$$ = NEW_LIST($2);
		    /*%
		        rb_warn0("parenthesize argument for future version");
			$$ = dispatch1(arg_paren, arg_add(arg_new(), $2));
		    %*/
		    }
		| '(' args ',' block_call rparen
		    {
		    /*%%%*/
		        rb_warn("parenthesize argument for future version");
			$$ = list_append($2, $4);
		    /*%
		        rb_warn0("parenthesize argument for future version");
			$$ = dispatch1(arg_paren, arg_add($2, $4));
		    %*/
		    }
		;

opt_paren_args	: none
		| paren_args
		;

call_args	: command
		    {
		    /*%%%*/
		        rb_warn("parenthesize argument(s) for future version");
			$$ = NEW_LIST($1);
		    /*%
		        rb_warn0("parenthesize argument(s) for future version");
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
		| args ',' tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_concat($1, $4);
			$$ = arg_blk_pass($$, $5);
		    /*%
			arg_add_optblock(arg_add_star($1, $4), $5);
		    %*/
		    }
		| assocs opt_block_arg
		    {
		    /*%%%*/
			$$ = NEW_LIST(NEW_HASH($1));
			$$ = arg_blk_pass($$, $2);
		    /*%
			$$ = arg_add_assocs(arg_new(), $1);
			$$ = arg_add_optblock($$, $2);
		    %*/
		    }
		| assocs ',' tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_concat(NEW_LIST(NEW_HASH($1)), $4);
			$$ = arg_blk_pass($$, $5);
		    /*%
			$$ = arg_add_star(arg_add_assocs(arg_new(), $1), $4);
			$$ = arg_add_optblock($$, $5);
		    %*/
		    }
		| args ',' assocs opt_block_arg
		    {
		    /*%%%*/
			$$ = list_append($1, NEW_HASH($3));
			$$ = arg_blk_pass($$, $4);
		    /*%
			$$ = arg_add_optblock(arg_add_assocs($1, $3), $4);
		    %*/
		    }
		| args ',' assocs ',' tSTAR arg opt_block_arg
		    {
		    /*%%%*/
			value_expr($6);
			$$ = arg_concat(list_append($1, NEW_HASH($3)), $6);
			$$ = arg_blk_pass($$, $7);
		    /*%
			$$ = arg_add_star(arg_add_assocs($1, $3), $6);
			$$ = arg_add_optblock($$, $7);
		    %*/
		    }
		| tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_blk_pass(NEW_SPLAT($2), $3);
		    /*%
			$$ = arg_add_optblock(arg_add_star(arg_new(), $2), $3);
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

call_args2	: arg_value ',' args opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_blk_pass(list_concat(NEW_LIST($1),$3), $4);
		    /*%
			$$ = arg_add_optblock(arg_prepend($3, $1), $4);
		    %*/
		    }
		| arg_value ',' block_arg
		    {
		    /*%%%*/
                        $$ = arg_blk_pass($1, $3);
		    /*%
			$$ = arg_add_block(arg_add(arg_new(), $1), $3);
		    %*/
                    }
		| arg_value ',' tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_concat(NEW_LIST($1), $4);
			$$ = arg_blk_pass($$, $5);
		    /*%
			$$ = arg_add_star(arg_add(arg_new(), $1), $4);
			$$ = arg_add_optblock($$, $5);
		    %*/
		    }
		| arg_value ',' args ',' tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_concat(list_concat(NEW_LIST($1),$3), $6);
			$$ = arg_blk_pass($$, $7);
		    /*%
			$$ = arg_add_star(arg_prepend($3, $1), $6);
			$$ = arg_add_optblock($$, $7);
		    %*/
		    }
		| assocs opt_block_arg
		    {
		    /*%%%*/
			$$ = NEW_LIST(NEW_HASH($1));
			$$ = arg_blk_pass($$, $2);
		    /*%
			$$ = arg_add_optblock(arg_add_assocs(arg_new(), $1), $2);
		    %*/
		    }
		| assocs ',' tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_concat(NEW_LIST(NEW_HASH($1)), $4);
			$$ = arg_blk_pass($$, $5);
		    /*%
			$$ = arg_add_star(arg_add_assocs(arg_new(), $1), $4);
			$$ = arg_add_optblock($$, $4);
		    %*/
		    }
		| arg_value ',' assocs opt_block_arg
		    {
		    /*%%%*/
			$$ = list_append(NEW_LIST($1), NEW_HASH($3));
			$$ = arg_blk_pass($$, $4);
		    /*%
			$$ = arg_add_assocs(arg_add(arg_new(), $1), $3);
			$$ = arg_add_optblock($$, $4);
		    %*/
		    }
		| arg_value ',' args ',' assocs opt_block_arg
		    {
		    /*%%%*/
			$$ = list_append(list_concat(NEW_LIST($1),$3), NEW_HASH($5));
			$$ = arg_blk_pass($$, $6);
		    /*%
			$$ = arg_add_assocs(arg_prepend($3, $1), $5);
			$$ = arg_add_optblock($$, $6);
		    %*/
		    }
		| arg_value ',' assocs ',' tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_concat(list_append(NEW_LIST($1), NEW_HASH($3)), $6);
			$$ = arg_blk_pass($$, $7);
		    /*%
			$$ = arg_add_assocs(arg_add(arg_new(), $1), $3);
			$$ = arg_add_star($$, $6);
			$$ = arg_add_optblock($$, $7);
		    %*/
		    }
		| arg_value ',' args ',' assocs ',' tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_concat(list_append(list_concat(NEW_LIST($1), $3), NEW_HASH($5)), $8);
			$$ = arg_blk_pass($$, $9);
		    /*%
			$$ = arg_add_assocs(arg_prepend($3, $1), $5);
			$$ = arg_add_star($$, $8);
			$$ = arg_add_optblock($$, $9);
		    %*/
		    }
		| tSTAR arg_value opt_block_arg
		    {
		    /*%%%*/
			$$ = arg_blk_pass(NEW_SPLAT($2), $3);
		    /*%
			$$ = arg_add_optblock(arg_add_star(arg_new(), $2), $3);
		    %*/
		    }
		| block_arg
		;

command_args	:  {
			$<num>$ = cmdarg_stack;
			CMDARG_PUSH(1);
		    }
		  open_args
		    {
			/* CMDARG_POP() */
		        cmdarg_stack = $<num>1;
			$$ = $2;
		    }
		;

open_args	: call_args
		| tLPAREN_ARG  {lex_state = EXPR_ENDARG;} rparen
		    {
		    /*%%%*/
		        rb_warning("don't put space before argument parentheses");
			$$ = 0;
		    /*%
			$$ = dispatch1(space, dispatch1(arg_paren, arg_new()));
		    %*/
		    }
		| tLPAREN_ARG call_args2 {lex_state = EXPR_ENDARG;} rparen
		    {
		    /*%%%*/
		        rb_warning("don't put space before argument parentheses");
			$$ = $2;
		    /*%
			$$ = dispatch1(space, dispatch1(arg_paren, $2));
		    %*/
		    }
		;

block_arg	: tAMPER arg_value
		    {
		    /*%%%*/
			$$ = NEW_BLOCK_PASS($2);
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
		;

args 		: arg_value
		    {
		    /*%%%*/
			$$ = NEW_LIST($1);
		    /*%
			$$ = arg_add(arg_new(), $1);
		    %*/
		    }
		| args ',' arg_value
		    {
		    /*%%%*/
			$$ = list_append($1, $3);
		    /*%
			$$ = arg_add($1, $3);
		    %*/
		    }
		;

mrhs		: args ',' arg_value
		    {
		    /*%%%*/
			$$ = list_append($1, $3);
		    /*%
			$$ = mrhs_add(args2mrhs($1), $3);
		    %*/
		    }
		| args ',' tSTAR arg_value
		    {
		    /*%%%*/
			$$ = arg_concat($1, $4);
		    /*%
			$$ = mrhs_add_star(args2mrhs($1), $4);
		    %*/
		    }
		| tSTAR arg_value
		    {
		    /*%%%*/
			$$ = NEW_SPLAT($2);
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
		| var_ref
		| backref
		| tFID
		    {
		    /*%%%*/
			$$ = NEW_FCALL($1, 0);
		    /*%
			$$ = method_arg(dispatch1(fcall, $1), arg_new());
		    %*/
		    }
		| kBEGIN
		    {
		    /*%%%*/
			$<num>1 = ruby_sourceline;
		    /*%
		    %*/
		    }
		  bodystmt
		  kEND
		    {
		    /*%%%*/
			if ($3 == NULL) {
			    $$ = NEW_NIL();
			}
			else {
			    if (nd_type($3) == NODE_RESCUE ||
				nd_type($3) == NODE_ENSURE)
				nd_set_line($3, $<num>1);
			    $$ = NEW_BEGIN($3);
			}
			nd_set_line($$, $<num>1);
		    /*%
			$$ = dispatch1(begin, $3);
		    %*/
		    }
		| tLPAREN_ARG expr {lex_state = EXPR_ENDARG;} rparen
		    {
		    /*%%%*/
		        rb_warning("(...) interpreted as grouped expression");
			$$ = $2;
		    /*%
		        rb_warning0("(...) interpreted as grouped expression");
			$$ = dispatch1(paren, $2);
		    %*/
		    }
		| tLPAREN compstmt ')'
		    {
		    /*%%%*/
			if (!$2) $$ = NEW_NIL();
			else $$ = $2;
		    /*%
			$$ = dispatch1(paren, $2);
		    %*/
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
		    /*%%%*/
			$$ = NEW_COLON2($1, $3);
		    /*%
			$$ = dispatch2(constpath_ref, $1, $3);
		    %*/
		    }
		| tCOLON3 tCONSTANT
		    {
		    /*%%%*/
			$$ = NEW_COLON3($2);
		    /*%
			$$ = dispatch1(topconst_ref, $2);
		    %*/
		    }
		| primary_value '[' aref_args ']'
		    {
		    /*%%%*/
			if ($1 && nd_type($1) == NODE_SELF)
			    $$ = NEW_FCALL(tAREF, $3);
			else
			    $$ = NEW_CALL($1, tAREF, $3);
			fixpos($$, $1);
		    /*%
			$$ = dispatch2(aref, $1, $3);
		    %*/
		    }
		| tLBRACK aref_args ']'
		    {
		    /*%%%*/
		        if ($2 == 0) {
			    $$ = NEW_ZARRAY(); /* zero length array*/
			}
			else {
			    $$ = $2;
			}
		    /*%
			$$ = dispatch1(array, escape_Qundef($2));
		    %*/
		    }
		| tLBRACE assoc_list '}'
		    {
		    /*%%%*/
			$$ = NEW_HASH($2);
		    /*%
			$$ = dispatch1(hash, escape_Qundef($2));
		    %*/
		    }
		| tLBRACE
		    {
		    /*%%%*/
			$<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    /*%
		    %*/
		    }
		  block_var_def {$<vars>$ = ruby_dyna_vars;}
		  compstmt
		  '}'
		    {
		    /*%%%*/
			$3->nd_body = block_append($3->nd_body,
						   dyna_init($5, $<vars>4));
			$$ = $3;
		        nd_set_type($3, NODE_LAMBDA);
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    /*%
			$$ = dispatch2(brace_block, escape_Qundef($3), $5);
		    %*/
		    }
		| kRETURN
		    {
		    /*%%%*/
			$$ = NEW_RETURN(0);
		    /*%
			$$ = dispatch0(return0);
		    %*/
		    }
		| kYIELD '(' call_args rparen
		    {
		    /*%%%*/
			$$ = new_yield($3);
		    /*%
			$$ = dispatch1(yield, dispatch1(paren, $3));
		    %*/
		    }
		| kYIELD '(' rparen
		    {
		    /*%%%*/
			$$ = NEW_YIELD(0, Qfalse);
		    /*%
			$$ = dispatch1(yield, dispatch1(paren, arg_new()));
		    %*/
		    }
		| kYIELD
		    {
		    /*%%%*/
			$$ = NEW_YIELD(0, Qfalse);
		    /*%
			$$ = dispatch0(yield0);
		    %*/
		    }
		| kDEFINED opt_nl '(' {in_defined = 1;} expr rparen
		    {
		    /*%%%*/
		        in_defined = 0;
			$$ = NEW_DEFINED($5);
		    /*%
		        in_defined = 0;
			$$ = dispatch1(defined, $5);
		    %*/
		    }
		| operation brace_block
		    {
		    /*%%%*/
			$2->nd_iter = NEW_FCALL($1, 0);
			$$ = $2;
			fixpos($2->nd_iter, $2);
		    /*%
			$$ = method_arg(dispatch1(fcall, $1), arg_new());
			$$ = dispatch2(iter_block, $$, $2);
		    %*/
		    }
		| method_call
		| method_call brace_block
		    {
		    /*%%%*/
			if ($1 && nd_type($1) == NODE_BLOCK_PASS) {
			    compile_error(PARSER_ARG "both block arg and actual block given");
			}
			$2->nd_iter = $1;
			$$ = $2;
		        fixpos($$, $1);
		    /*%
			$$ = dispatch2(iter_block, $1, $2);
		    %*/
		    }
		| kIF expr_value then
		  compstmt
		  if_tail
		  kEND
		    {
		    /*%%%*/
			$$ = NEW_IF(cond($2), $4, $5);
		        fixpos($$, $2);
			if (cond_negative(&$$->nd_cond)) {
		            NODE *tmp = $$->nd_body;
		            $$->nd_body = $$->nd_else;
		            $$->nd_else = tmp;
			}
		    /*%
			$$ = dispatch3(if, $2, $4, escape_Qundef($5));
		    %*/
		    }
		| kUNLESS expr_value then
		  compstmt
		  opt_else
		  kEND
		    {
		    /*%%%*/
			$$ = NEW_UNLESS(cond($2), $4, $5);
		        fixpos($$, $2);
			if (cond_negative(&$$->nd_cond)) {
		            NODE *tmp = $$->nd_body;
		            $$->nd_body = $$->nd_else;
		            $$->nd_else = tmp;
			}
		    /*%
			$$ = dispatch3(unless, $2, $4, escape_Qundef($5));
		    %*/
		    }
		| kWHILE {COND_PUSH(1);} expr_value do {COND_POP();}
		  compstmt
		  kEND
		    {
		    /*%%%*/
			$$ = NEW_WHILE(cond($3), $6, 1);
		        fixpos($$, $3);
			if (cond_negative(&$$->nd_cond)) {
			    nd_set_type($$, NODE_UNTIL);
			}
		    /*%
			$$ = dispatch2(while, $3, $6);
		    %*/
		    }
		| kUNTIL {COND_PUSH(1);} expr_value do {COND_POP();}
		  compstmt
		  kEND
		    {
		    /*%%%*/
			$$ = NEW_UNTIL(cond($3), $6, 1);
		        fixpos($$, $3);
			if (cond_negative(&$$->nd_cond)) {
			    nd_set_type($$, NODE_WHILE);
			}
		    /*%
			$$ = dispatch2(until, $3, $6);
		    %*/
		    }
		| kCASE expr_value opt_terms
		  case_body
		  kEND
		    {
		    /*%%%*/
			$$ = NEW_CASE($2, $4);
		        fixpos($$, $2);
		    /*%
			$$ = dispatch2(case, $2, $4);
		    %*/
		    }
		| kCASE expr_value opt_terms kELSE compstmt kEND
		    {
		    /*%%%*/
			$$ = block_append($2, $5);
		    /*%
		    	$$ = dispatch2(case, $2, dispatch1(else, $5));
		    %*/
		    }
		| kCASE opt_terms case_body kEND
		    {
		    /*%%%*/
			$$ = $3;
		    /*%
			$$ = dispatch2(case, Qnil, $3);
		    %*/
		    }
		| kCASE opt_terms kELSE compstmt kEND
		    {
		    /*%%%*/
			$$ = $4;
		    /*%
			$$ = dispatch2(case, Qnil, dispatch1(else, $4));
		    %*/
		    }
		| kFOR for_var kIN {COND_PUSH(1);} expr_value do {COND_POP();}
		  compstmt
		  kEND
		    {
		    /*%%%*/
			$$ = NEW_FOR($2, $5, $8);
		        fixpos($$, $2);
		    /*%
			$$ = dispatch3(for, $2, $5, $8);
		    %*/
		    }
		| kCLASS cpath superclass
		    {
		    /*%%%*/
			if (in_def || in_single)
			    yyerror("class definition in method body");
			class_nest++;
			local_push(0);
		        $<num>$ = ruby_sourceline;
		    /*%
			if (in_def || in_single)
			    yyerror("class definition in method body");
			class_nest++;
		    %*/
		    }
		  bodystmt
		  kEND
		    {
		    /*%%%*/
		        $$ = NEW_CLASS($2, $5, $3);
		        nd_set_line($$, $<num>4);
		        local_pop();
			class_nest--;
		    /*%
			$$ = dispatch3(class, $2, $3, $5);
			class_nest--;
		    %*/
		    }
		| kCLASS tLSHFT expr
		    {
		    /*%%%*/
			$<num>$ = in_def;
		        in_def = 0;
		    /*%
		        in_def = 0;
		    %*/
		    }
		  term
		    {
		    /*%%%*/
		        $<num>$ = in_single;
		        in_single = 0;
			class_nest++;
			local_push(0);
		    /*%
		        $$ = in_single;
		        in_single = 0;
			class_nest++;
		    %*/
		    }
		  bodystmt
		  kEND
		    {
		    /*%%%*/
		        $$ = NEW_SCLASS($3, $7);
		        fixpos($$, $3);
		        local_pop();
			class_nest--;
		        in_def = $<num>4;
		        in_single = $<num>6;
		    /*%
			$$ = dispatch2(sclass, $3, $7);
			class_nest--;
		        in_def = $<val>4;
		        in_single = $<val>6;
		    %*/
		    }
		| kMODULE cpath
		    {
		    /*%%%*/
			if (in_def || in_single)
			    yyerror("module definition in method body");
			class_nest++;
			local_push(0);
		        $<num>$ = ruby_sourceline;
		    /*%
			if (in_def || in_single)
			    yyerror("module definition in method body");
			class_nest++;
		    %*/
		    }
		  bodystmt
		  kEND
		    {
		    /*%%%*/
		        $$ = NEW_MODULE($2, $4);
		        nd_set_line($$, $<num>3);
		        local_pop();
			class_nest--;
		    /*%
			$$ = dispatch2(module, $2, $4);
			class_nest--;
		    %*/
		    }
		| kDEF fname
		    {
		    /*%%%*/
			$<id>$ = cur_mid;
			cur_mid = $2;
			in_def++;
			local_push(0);
		    /*%
			$<id>$ = cur_mid;
			cur_mid = $2;
			in_def++;
		    %*/
		    }
		  f_arglist
		  bodystmt
		  kEND
		    {
		    /*%%%*/
			NODE *body = remove_begin($5);
			reduce_nodes(&body);
			$$ = NEW_DEFN($2, $4, body, NOEX_PRIVATE);
		        fixpos($$, $4);
		        local_pop();
			in_def--;
			cur_mid = $<id>3;
		    /*%
			$$ = dispatch3(def, $2, $4, $5);
			in_def--;
			cur_mid = $<id>3;
		    %*/
		    }
		| kDEF singleton dot_or_colon {lex_state = EXPR_FNAME;} fname
		    {
		    /*%%%*/
			in_single++;
			local_push(0);
		        lex_state = EXPR_END; /* force for args */
		    /*%
			in_single++;
		        lex_state = EXPR_END;
		    %*/
		    }
		  f_arglist
		  bodystmt
		  kEND
		    {
		    /*%%%*/
			NODE *body = remove_begin($8);
			reduce_nodes(&body);
			$$ = NEW_DEFS($2, $5, $7, body);
		        fixpos($$, $2);
		        local_pop();
			in_single--;
		    /*%
			$$ = dispatch5(defs, $2, $3, $5, $7, $8);
			in_single--;
		    %*/
		    }
		| kBREAK
		    {
		    /*%%%*/
			$$ = NEW_BREAK(0);
		    /*%
			$$ = dispatch1(break, arg_new());
		    %*/
		    }
		| kNEXT
		    {
		    /*%%%*/
			$$ = NEW_NEXT(0);
		    /*%
			$$ = dispatch1(next, arg_new());
		    %*/
		    }
		| kREDO
		    {
		    /*%%%*/
			$$ = NEW_REDO();
		    /*%
			$$ = dispatch0(redo);
		    %*/
		    }
		| kRETRY
		    {
		    /*%%%*/
			$$ = NEW_RETRY();
		    /*%
			$$ = dispatch0(retry);
		    %*/
		    }
		;

primary_value 	: primary
		    {
		    /*%%%*/
			value_expr($1);
			$$ = $1;
		    /*%
			$$ = $1;
		    %*/
		    }
		;

then		: term
		    /*%c%*/
		    /*%c
		    { $$ = Qnil; }
		    %*/
		| ':'
		    /*%c%*/
		    /*%c
		    { $$ = Qnil; }
		    %*/
		| kTHEN
		| term kTHEN
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
		| ':'
		    /*%c%*/
		    /*%c
		    { $$ = Qnil; }
		    %*/
		| kDO_COND
		;

if_tail		: opt_else
		| kELSIF expr_value then
		  compstmt
		  if_tail
		    {
		    /*%%%*/
			$$ = NEW_IF(cond($2), $4, $5);
		        fixpos($$, $2);
		    /*%
			$$ = dispatch3(elsif, $2, $4, escape_Qundef($5));
		    %*/
		    }
		;

opt_else	: none
		| kELSE compstmt
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(else, $2);
		    %*/
		    }
		;

for_var 	: lhs
		| mlhs
		;

block_param	: mlhs_item
		    {
		    /*%%%*/
			$$ = NEW_LIST($1);
		    /*%
			$$ = mlhs_add(mlhs_new(), $1);
		    %*/
		    }
		| block_param ',' mlhs_item
		    {
		    /*%%%*/
			$$ = list_append($1, $3);
		    /*%
		    	$$ = mlhs_add($1, $3);
		    %*/
		    }
		;

block_var	: block_param
		    {
		    /*%%%*/
			if ($1->nd_alen == 1) {
			    $$ = $1->nd_head;
			    rb_gc_force_recycle((VALUE)$1);
			}
			else {
			    $$ = NEW_MASGN($1, 0);
			}
		    /*%
			$$ = blockvar_new($1);
		    %*/
		    }
		| block_param ','
		    {
		    /*%%%*/
			$$ = NEW_MASGN($1, 0);
		    /*%
			$$ = blockvar_new($1);
		    %*/
		    }
		| block_param ',' tAMPER lhs
		    {
		    /*%%%*/
			$$ = NEW_BLOCK_VAR($4, NEW_MASGN($1, 0));
		    /*%
			$$ = blockvar_add_block(blockvar_new($1), $4);
		    %*/
		    }
		| block_param ',' tSTAR lhs ',' tAMPER lhs
		    {
		    /*%%%*/
			$$ = NEW_BLOCK_VAR($7, NEW_MASGN($1, $4));
		    /*%
			$$ = blockvar_add_star(blockvar_new($1), $4);
			$$ = blockvar_add_block($$, $7);
		    %*/
		    }
		| block_param ',' tSTAR ',' tAMPER lhs
		    {
		    /*%%%*/
			$$ = NEW_BLOCK_VAR($6, NEW_MASGN($1, -1));
		    /*%
			$$ = blockvar_add_star(blockvar_new($1), Qnil);
			$$ = blockvar_add_block($$, $6);
		    %*/
		    }
		| block_param ',' tSTAR lhs
		    {
		    /*%%%*/
			$$ = NEW_MASGN($1, $4);
		    /*%
			$$ = blockvar_add_star(blockvar_new($1), $4);
		    %*/
		    }
		| block_param ',' tSTAR
		    {
		    /*%%%*/
			$$ = NEW_MASGN($1, -1);
		    /*%
			$$ = blockvar_add_star(blockvar_new($1), Qnil);
		    %*/
		    }
		| tSTAR lhs ',' tAMPER lhs
		    {
		    /*%%%*/
			$$ = NEW_BLOCK_VAR($5, NEW_MASGN(0, $2));
		    /*%
			$$ = blockvar_add_star(blockvar_new(Qnil), $2);
			$$ = blockvar_add_block($$, $5);
		    %*/
		    }
		| tSTAR ',' tAMPER lhs
		    {
		    /*%%%*/
			$$ = NEW_BLOCK_VAR($4, NEW_MASGN(0, -1));
		    /*%
			$$ = blockvar_add_star(blockvar_new(Qnil), Qnil);
			$$ = blockvar_add_block($$, $4);
		    %*/
		    }
		| tSTAR lhs
		    {
		    /*%%%*/
			$$ = NEW_MASGN(0, $2);
		    /*%
			$$ = blockvar_add_star(blockvar_new(Qnil), $2);
		    %*/
		    }
		| tSTAR
		    {
		    /*%%%*/
			$$ = NEW_MASGN(0, -1);
		    /*%
			$$ = blockvar_add_star(blockvar_new(Qnil), Qnil);
		    %*/
		    }
		| tAMPER lhs
		    {
		    /*%%%*/
			$$ = NEW_BLOCK_VAR($2, (NODE*)1);
		    /*%
			$$ = blockvar_add_block(blockvar_new(Qnil), $2);
		    %*/
		    }
		;

opt_block_var	: none
		    {
		    /*%%%*/
			$$ = NEW_ITER(0, 0, 0);
		    /*%
		    %*/
		    }
		| block_var_def
		;

block_var_def	: '|' opt_bv_decl '|'
		    {
		    /*%%%*/
			$$ = NEW_ITER((NODE*)1, 0, $2);
		    /*%
			$$ = blockvar_new(mlhs_new());
		    %*/
		    }
		| tOROP
		    {
		    /*%%%*/
			$$ = NEW_ITER((NODE*)1, 0, 0);
		    /*%
			$$ = blockvar_new(mlhs_new());
		    %*/
		    }
		| '|' block_var opt_bv_decl '|'
		    {
		    /*%%%*/
			$$ = NEW_ITER($2, 0, $3);
		    /*%
			$$ = blockvar_new($2);
		    %*/
		    }
		;


opt_bv_decl	: none
		| ';' bv_decls
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = FIXME;
		    %*/
		    }
		;

bv_decls	: bv_decl
		    {
		    /*%%%*/
			$$ = $1;
		    /*%
			$$ = FIXME;
		    %*/
		    }
		| bv_decls ',' bv_decl
		    {
		    /*%%%*/
			$$ = block_append($1, $3);
		    /*%
			$$ = FIXME;
		    %*/
		    }
		;

bv_decl		:  tIDENTIFIER
		    {
		    /*%%%*/
                        $$ = new_bv($1, NEW_NIL());
		    /*%
			$$ = FIXME;
		    %*/
		    }
		;

do_block	: kDO_BLOCK
		    {
		    /*%%%*/
		        $<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    /*% %*/
		    }
		  opt_block_var
		    {
		    /*%%%*/
			$<vars>$ = ruby_dyna_vars;
		    /*% %*/
		    }
		  compstmt
		  kEND
		    {
		    /*%%%*/
			$3->nd_body = block_append($3->nd_body,
						   dyna_init($5, $<vars>4));
			$$ = $3;
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    /*%
			$$ = dispatch2(do_block, escape_Qundef($3), $5);
		    %*/
		    }
		;

block_call	: command do_block
		    {
		    /*%%%*/
			if ($1 && nd_type($1) == NODE_BLOCK_PASS) {
			    compile_error(PARSER_ARG "both block arg and actual block given");
			}
			$2->nd_iter = $1;
			$$ = $2;
		        fixpos($$, $1);
		    /*%
			$$ = dispatch2(iter_block, $1, $2);
		    %*/
		    }
		| block_call '.' operation2 opt_paren_args
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
		    /*%
			$$ = dispatch3(call, $1, ripper_id2sym('.'), $3);
			$$ = method_optarg($$, $4);
		    %*/
		    }
		| block_call tCOLON2 operation2 opt_paren_args
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
		    /*%
			$$ = dispatch3(call, $1, ripper_intern("::"), $3);
			$$ = method_optarg($$, $4);
		    %*/
		    }
		;

method_call	: operation paren_args
		    {
		    /*%%%*/
			$$ = new_fcall($1, $2);
		        fixpos($$, $2);
		    /*%
		        $$ = method_arg(dispatch1(fcall, $1), $2);
		    %*/
		    }
		| primary_value '.' operation2 opt_paren_args
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    /*%
			$$ = dispatch3(call, $1, ripper_id2sym('.'), $3);
			$$ = method_optarg($$, $4);
		    %*/
		    }
		| primary_value tCOLON2 operation2 paren_args
		    {
		    /*%%%*/
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    /*%
			$$ = dispatch3(call, $1, ripper_id2sym('.'), $3);
			$$ = method_optarg($$, $4);
		    %*/
		    }
		| primary_value tCOLON2 operation3
		    {
		    /*%%%*/
			$$ = new_call($1, $3, 0);
		    /*%
			$$ = dispatch3(call, $1, ripper_intern("::"), $3);
		    %*/
		    }
		| kSUPER paren_args
		    {
		    /*%%%*/
			$$ = new_super($2);
		    /*%
			$$ = dispatch1(super, $2);
		    %*/
		    }
		| kSUPER
		    {
		    /*%%%*/
			$$ = NEW_ZSUPER();
		    /*%
			$$ = dispatch0(zsuper);
		    %*/
		    }
		| tLPAREN compstmt ')' paren_args
		    {
		    /*%%%*/
			if (!$2) $2 = NEW_NIL();
			$$ = new_call($2, rb_intern("call"), $4);
		        fixpos($$, $2);
		    /*%
			$$ = dispatch3(call, dispatch1(paren, $2),
		                       ripper_id2sym('.'), rb_intern("call"));
			$$ = method_optarg($$, $4);
		    %*/
		    }
		;

brace_block	: '{'
		    {
		    /*%%%*/
		        $<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    /*% %*/
		    }
		  opt_block_var
		    {
		    /*%%%*/
			$<vars>$ = ruby_dyna_vars;
		    /*%
		    %*/
		    }
		  compstmt '}'
		    {
		    /*%%%*/
			$3->nd_body = block_append($3->nd_body,
						   dyna_init($5, $<vars>4));
			$$ = $3;
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    /*%
			$$ = dispatch2(brace_block, escape_Qundef($3), $5);
		    %*/
		    }
		| kDO
		    {
		    /*%%%*/
		        $<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    /*% %*/
		    }
		  opt_block_var
		    {
		    /*%%%*/
			$<vars>$ = ruby_dyna_vars;
		    /*%
		    %*/
		    }
		  compstmt kEND
		    {
		    /*%%%*/
			$3->nd_body = block_append($3->nd_body,
						   dyna_init($5, $<vars>4));
			$$ = $3;
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    /*%
			$$ = dispatch2(do_block, escape_Qundef($3), $5);
		    %*/
		    }
		;

case_body	: kWHEN when_args then
		  compstmt
		  cases
		    {
		    /*%%%*/
			$$ = NEW_WHEN($2, $4, $5);
		    /*%
			$$ = dispatch3(when, $2, $4, escape_Qundef($5));
		    %*/
		    }
		;
when_args	: args
		| args ',' tSTAR arg_value
		    {
		    /*%%%*/
			$$ = list_append($1, NEW_WHEN($4, 0, 0));
		    /*%
			$$ = arg_add_star($1, $4);
		    %*/
		    }
		| tSTAR arg_value
		    {
		    /*%%%*/
			$$ = NEW_LIST(NEW_WHEN($2, 0, 0));
		    /*%
			$$ = arg_add_star(arg_new(), $2);
		    %*/
		    }
		;

cases		: opt_else
		| case_body
		;

opt_rescue	: kRESCUE exc_list exc_var then
		  compstmt
		  opt_rescue
		    {
		    /*%%%*/
		        if ($3) {
		            $3 = node_assign($3, NEW_ERRINFO());
			    $5 = block_append($3, $5);
			}
			$$ = NEW_RESBODY($2, $5, $6);
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
			$$ = NEW_LIST($1);
		    /*%
		    	$$ = rb_ary_new3(1, $1);
		    %*/
		    }
		| mrhs
		| none
		;

exc_var		: tASSOC lhs
		    {
			$$ = $2;
		    }
		| none
		;

opt_ensure	: kENSURE compstmt
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
			$$ = NEW_LIT(ID2SYM($1));
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
			    node = NEW_STR(rb_str_new(0, 0));
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

string		: string1
		| string string1
		    {
		    /*%%%*/
			$$ = literal_concat($1, $2);
		    /*%
			$$ = dispatch2(string_concat, $1, $2);
		    %*/
		    }
		;

string1		: tSTRING_BEG string_contents tSTRING_END
		    {
		    /*%%%*/
			$$ = $2;
		    /*%
			$$ = dispatch1(string_literal, $2);
		    %*/
		    }
		;

xstring		: tXSTRING_BEG xstring_contents tSTRING_END
		    {
		    /*%%%*/
			NODE *node = $2;
			if (!node) {
			    node = NEW_XSTR(rb_str_new(0, 0));
			}
			else {
			    switch (nd_type(node)) {
			      case NODE_STR:
				nd_set_type(node, NODE_XSTR);
				break;
			      case NODE_DSTR:
				nd_set_type(node, NODE_DXSTR);
				break;
			      default:
				node = NEW_NODE(NODE_DXSTR, rb_str_new(0, 0), 1, NEW_LIST(node));
				break;
			    }
			}
			$$ = node;
		    /*%
			$$ = dispatch1(xstring_literal, $2);
		    %*/
		    }
		;

regexp		: tREGEXP_BEG xstring_contents tREGEXP_END
		    {
		    /*%%%*/
			int options = $3;
			NODE *node = $2;
			if (!node) {
			    node = NEW_LIT(rb_reg_compile("", 0, options & ~RE_OPTION_ONCE));
			}
			else switch (nd_type(node)) {
			  case NODE_STR:
			    {
				VALUE src = node->nd_lit;
				nd_set_type(node, NODE_LIT);
				node->nd_lit = rb_reg_compile(RSTRING(src)->ptr,
							      RSTRING(src)->len,
							      options & ~RE_OPTION_ONCE);
			    }
			    break;
			  default:
			    node = NEW_NODE(NODE_DSTR, rb_str_new(0, 0), 1, NEW_LIST(node));
			  case NODE_DSTR:
			    if (options & RE_OPTION_ONCE) {
				nd_set_type(node, NODE_DREGX_ONCE);
			    }
			    else {
				nd_set_type(node, NODE_DREGX);
			    }
			    node->nd_cflag = options & ~RE_OPTION_ONCE;
			    break;
			}
			$$ = node;
		    /*%
			$$ = dispatch2(regexp_literal, $2, $3);
		    %*/
		    }
		;

words		: tWORDS_BEG ' ' tSTRING_END
		    {
		    /*%%%*/
			$$ = NEW_ZARRAY();
		    /*%
			$$ = dispatch0(words_new);
		    %*/
		    }
		| tWORDS_BEG word_list tSTRING_END
		    {
			$$ = $2;
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
			$$ = literal_concat($1, $2);
		    /*%
			$$ = dispatch2(word_add, $1, $2);
		    %*/
		    }
		;

qwords		: tQWORDS_BEG ' ' tSTRING_END
		    {
		    /*%%%*/
			$$ = NEW_ZARRAY();
		    /*%
			$$ = dispatch0(qwords_new);
		    %*/
		    }
		| tQWORDS_BEG qword_list tSTRING_END
		    {
			$$ = $2;
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
			$$ = list_append($1, $2);
		    /*%
			$$ = dispatch2(qwords_add, $1, $2);
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
			$$ = literal_concat($1, $2);
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
			$$ = literal_concat($1, $2);
		    /*%
			$$ = dispatch2(xstring_add, $1, $2);
		    %*/
		    }
		;

string_content	: tSTRING_CONTENT
		| tSTRING_DVAR
		    {
			$<node>$ = lex_strterm;
			lex_strterm = 0;
			lex_state = EXPR_BEG;
		    }
		  string_dvar
		    {
		    /*%%%*/
			lex_strterm = $<node>2;
		        $$ = NEW_EVSTR($3);
		    /*%
			lex_strterm = $<node>2;
			$$ = dispatch1(string_dvar, $3);
		    %*/
		    }
		| tSTRING_DBEG
		    {
			$<node>$ = lex_strterm;
			lex_strterm = 0;
			lex_state = EXPR_BEG;
			COND_PUSH(0);
			CMDARG_PUSH(0);
		    }
		  compstmt '}'
		    {
			lex_strterm = $<node>2;
			COND_LEXPOP();
			CMDARG_LEXPOP();
		    /*%%%*/
		        if ($3) $3->flags &= ~NODE_NEWLINE;
			$$ = new_evstr($3);
		    /*%
			$$ = dispatch1(string_embexpr, $3);
		    %*/
		    }
		;

string_dvar	: tGVAR
		    {
		    /*%%%*/
			$$ = NEW_GVAR($1);
		    /*%
			$$ = dispatch1(var_ref, $1);
		    %*/
		    }
		| tIVAR
		    {
		    /*%%%*/
			$$ = NEW_IVAR($1);
		    /*%
			$$ = dispatch1(var_ref, $1);
		    %*/
		    }
		| tCVAR
		    {
		    /*%%%*/
			$$ = NEW_CVAR($1);
		    /*%
			$$ = dispatch1(var_ref, $1);
		    %*/
		    }
		| backref
		;

symbol		: tSYMBEG sym
		    {
		    /*%%%*/
		        lex_state = EXPR_END;
			$$ = $2;
		    /*%
		        lex_state = EXPR_END;
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
		    /*%%%*/
		        lex_state = EXPR_END;
			if (!($$ = $2)) {
			    yyerror("empty symbol literal");
			}
			else {
			    switch (nd_type($$)) {
			      case NODE_DSTR:
				nd_set_type($$, NODE_DSYM);
				break;
			      case NODE_STR:
				if (strlen(RSTRING($$->nd_lit)->ptr) == RSTRING($$->nd_lit)->len) {
				    $$->nd_lit = ID2SYM(rb_intern(RSTRING($$->nd_lit)->ptr));
				    nd_set_type($$, NODE_LIT);
				    break;
				}
				/* fall through */
			      default:
				$$ = NEW_NODE(NODE_DSYM, rb_str_new(0, 0), 1, NEW_LIST($$));
				break;
			    }
			}
		    /*%
		        lex_state = EXPR_END;
			$$ = dispatch1(dyna_symbol, $2);
		    %*/
		    }
		;

numeric         : tINTEGER
		| tFLOAT
		| tUMINUS_NUM tINTEGER	       %prec tLOWEST
		    {
		    /*%%%*/
			$$ = negate_lit($2);
		    /*%
			$$ = dispatch2(unary, ripper_intern("-@"), $2);
		    %*/
		    }
		| tUMINUS_NUM tFLOAT	       %prec tLOWEST
		    {
		    /*%%%*/
			$$ = negate_lit($2);
		    /*%
			$$ = dispatch2(unary, ripper_intern("-@"), $2);
		    %*/
		    }
		;

variable	: tIDENTIFIER
		| tIVAR
		| tGVAR
		| tCONSTANT
		| tCVAR
		| kNIL {ifndef_ripper($$ = kNIL);}
		| kSELF {ifndef_ripper($$ = kSELF);}
		| kTRUE {ifndef_ripper($$ = kTRUE);}
		| kFALSE {ifndef_ripper($$ = kFALSE);}
		| k__FILE__ {ifndef_ripper($$ = k__FILE__);}
		| k__LINE__ {ifndef_ripper($$ = k__LINE__);}
		;

var_ref		: variable
		    {
		    /*%%%*/
			$$ = gettable($1);
		    /*%
			$$ = dispatch1(var_ref, $1);
		    %*/
		    }
		;

var_lhs		: variable
		    {
		    /*%%%*/
			$$ = assignable($1, 0);
		    /*%
			$$ = dispatch1(var_field, $1);
		    %*/
		    }
		;

backref		: tNTH_REF
		| tBACK_REF
		;

superclass	: term
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
			$$ = Qnil;
		    %*/
		    }
		| '<'
		    {
			lex_state = EXPR_BEG;
		    }
		  expr_value term
		    {
			$$ = $3;
		    }
		| error term
		    {
		    /*%%%*/
			yyerrok;
			$$ = 0;
		    /*%
			yyerrok;
			$$ = Qnil;
		    %*/
		    }
		;

f_arglist	: '(' f_args rparen
		    {
		    /*%%%*/
			$$ = $2;
			lex_state = EXPR_BEG;
		    /*%
			$$ = dispatch1(paren, $2);
			lex_state = EXPR_BEG;
		    %*/
		    }
		| f_args term
		    {
			$$ = $1;
		    }
		;

f_args		: f_arg ',' f_optarg ',' f_rest_arg opt_f_block_arg
		    {
		    /*%%%*/
			$$ = block_append(NEW_ARGS($1, $3, $5), $6);
		    /*%
			$$ = dispatch4(params, $1, $3, $5, escape_Qundef($6));
		    %*/
		    }
		| f_arg ',' f_optarg opt_f_block_arg
		    {
		    /*%%%*/
			$$ = block_append(NEW_ARGS($1, $3, -1), $4);
		    /*%
			$$ = dispatch4(params, $1, $3, Qnil, escape_Qundef($4));
		    %*/
		    }
		| f_arg ',' f_rest_arg opt_f_block_arg
		    {
		    /*%%%*/
			$$ = block_append(NEW_ARGS($1, 0, $3), $4);
		    /*%
			$$ = dispatch4(params, $1, Qnil, $3, escape_Qundef($4));
		    %*/
		    }
		| f_arg opt_f_block_arg
		    {
		    /*%%%*/
			$$ = block_append(NEW_ARGS($1, 0, -1), $2);
		    /*%
			$$ = dispatch4(params, $1, Qnil, Qnil, escape_Qundef($2));
		    %*/
		    }
		| f_optarg ',' f_rest_arg opt_f_block_arg
		    {
		    /*%%%*/
			$$ = block_append(NEW_ARGS(0, $1, $3), $4);
		    /*%
			$$ = dispatch4(params, Qnil, $1, $3, escape_Qundef($4));
		    %*/
		    }
		| f_optarg opt_f_block_arg
		    {
		    /*%%%*/
			$$ = block_append(NEW_ARGS(0, $1, -1), $2);
		    /*%
			$$ = dispatch4(params, Qnil, $1, Qnil, escape_Qundef($2));
		    %*/
		    }
		| f_rest_arg opt_f_block_arg
		    {
		    /*%%%*/
			$$ = block_append(NEW_ARGS(0, 0, $1), $2);
		    /*%
			$$ = dispatch4(params, Qnil, Qnil, $1, escape_Qundef($2));
		    %*/
		    }
		| f_block_arg
		    {
		    /*%%%*/
			$$ = block_append(NEW_ARGS(0, 0, -1), $1);
		    /*%
			$$ = dispatch4(params, Qnil, Qnil, Qnil, $1);
		    %*/
		    }
		| /* none */
		    {
		    /*%%%*/
			$$ = NEW_ARGS(0, 0, -1);
		    /*%
			$$ = dispatch4(params, Qnil, Qnil, Qnil, Qnil);
		    %*/
		    }
		;

f_norm_arg	: tCONSTANT
		    {
		    /*%%%*/
			yyerror("formal argument cannot be a constant");
		    /*%
			$$ = dispatch1(param_error, $1);
		    %*/
		    }
                | tIVAR
		    {
		    /*%%%*/
                        yyerror("formal argument cannot be an instance variable");
		    /*%
			$$ = dispatch1(param_error, $1);
		    %*/
		    }
                | tGVAR
		    {
		    /*%%%*/
                        yyerror("formal argument cannot be a global variable");
		    /*%
			$$ = dispatch1(param_error, $1);
		    %*/
		    }
                | tCVAR
		    {
		    /*%%%*/
                        yyerror("formal argument cannot be a class variable");
		    /*%
			$$ = dispatch1(param_error, $1);
		    %*/
		    }
		| tIDENTIFIER
		    {
		    /*%%%*/
			if (!is_local_id($1))
			    yyerror("formal argument must be local variable");
			else if (local_id($1))
			    yyerror("duplicate argument name");
			local_cnt($1);
			$$ = 1;
		    /*%
			$$ = $1;
		    %*/
		    }
		;

f_arg		: f_norm_arg
		    /*%c%*/
		    /*%c
		    { $$ = rb_ary_new3(1, $1); }
		    %*/
		| f_arg ',' f_norm_arg
		    {
		    /*%%%*/
			$$ += 1;
		    /*%
			$$ = $1;
			rb_ary_push($$, $3);
		    %*/
		    }
		;

f_opt		: tIDENTIFIER '=' arg_value
		    {
		    /*%%%*/
			if (!is_local_id($1))
			    yyerror("formal argument must be local variable");
			else if (local_id($1))
			    yyerror("duplicate optional argument name");
			$$ = assignable($1, $3);
		    /*%
			$$ = rb_assoc_new($1, $3);
		    %*/
		    }
		;

f_optarg	: f_opt
		    {
		    /*%%%*/
			$$ = NEW_BLOCK($1);
			$$->nd_end = $$;
		    /*%
			$$ = rb_ary_new3(1, $1);
		    %*/
		    }
		| f_optarg ',' f_opt
		    {
		    /*%%%*/
			$$ = block_append($1, $3);
		    /*%
			$$ = rb_ary_push($1, $3);
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
			    yyerror("rest argument must be local variable");
			else if (local_id($2))
			    yyerror("duplicate rest argument name");
			$$ = local_cnt($2);
		    /*%
			$$ = dispatch1(restparam, $2);
		    %*/
		    }
		| restarg_mark
		    {
		    /*%%%*/
			$$ = local_append((ID)0);
		    /*%
			$$ = dispatch1(restparam, Qnil);
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
			    yyerror("block argument must be local variable");
			else if (local_id($2))
			    yyerror("duplicate block argument name");
			$$ = NEW_BLOCK_ARG($2);
		    /*%
			$$ = $2;
		    %*/
		    }
		;

opt_f_block_arg	: ',' f_block_arg
		    {
			$$ = $2;
		    }
		| none
		;

singleton	: var_ref
		    {
		    /*%%%*/
			if (nd_type($1) == NODE_SELF) {
			    $$ = NEW_SELF();
			}
			else {
			    $$ = $1;
		            value_expr($$);
			}
		    /*%
			$$ = $1;
		    %*/
		    }
		| '(' {lex_state = EXPR_BEG;} expr rparen
		    {
		    /*%%%*/
			if ($3 == 0) {
			    yyerror("can't define singleton method for ().");
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
				yyerror("can't define singleton method for literals");
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
			$$ = $1;
		    }
		| args trailer
		    {
		    /*%%%*/
			if ($1->nd_alen%2 != 0) {
			    yyerror("odd number list for Hash");
			}
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
			$$ = rb_ary_new3(1, $1);
		    }
		    %*/
		| assocs ',' assoc
		    {
		    /*%%%*/
			$$ = list_concat($1, $3);
		    /*%
			rb_ary_push($$, $3);
		    %*/
		    }
		;

assoc		: arg_value tASSOC arg_value
		    {
		    /*%%%*/
			$$ = list_append(NEW_LIST($1), $3);
		    /*%
			$$ = dispatch2(assoc_new, $1, $3);
		    %*/
		    }
		| tLABEL arg_value
		    {
		    /*%%%*/
			$$ = list_append(NEW_LIST(NEW_LIT(ID2SYM($1))), $2);
		    /*%
		    	$$ = dispatch2(assoc_new, $1, $2);
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
		    /*%c%*/
		    /*%c
		    { $$ = $<val>1; }
		    %*/
		| tCOLON2
		    /*%c%*/
		    /*%c
		    { $$ = $<val>1; }
		    %*/
		;

opt_terms	: /* none */
		| terms
		;

opt_nl		: /* none */
		| '\n'
		;

rparen		: opt_nl ')'
		;

trailer		: /* none */
		| '\n'
		| ','
		;

term		: ';' {yyerrok;}
		| '\n'
		;

terms		: term
		| terms ';' {yyerrok;}
		;

none		: /* none */
		    {
		    /*%%%*/
			$$ = 0;
		    /*%
		    	$$ = Qundef;
		    %*/
		    }
		;
%%

# undef parser
# undef yylex
# undef yylval
# define yylval  (*((YYSTYPE*)(parser->parser_yylval)))

#ifndef RIPPER
static VALUE rb_parser_s_new _((void));
#endif
static int parser_regx_options _((struct parser_params*));
static int parser_tokadd_string _((struct parser_params*,int,int,int,long*));
static int parser_parse_string _((struct parser_params*,NODE*));
static int parser_here_document _((struct parser_params*,NODE*));

# define nextc()                   parser_nextc(parser)
# define pushback(c)               parser_pushback(parser, c)
# define newtok()                  parser_newtok(parser)
# define tokadd(c)                 parser_tokadd(parser, c)
# define read_escape()             parser_read_escape(parser)
# define tokadd_escape(t)          parser_tokadd_escape(parser, t)
# define regx_options()            parser_regx_options(parser)
# define tokadd_string(f,t,p,n)    parser_tokadd_string(parser,f,t,p,n)
# define parse_string(n)           parser_parse_string(parser,n)
# define here_document(n)          parser_here_document(parser,n)
# define heredoc_identifier()      parser_heredoc_identifier(parser)
# define heredoc_restore(n)        parser_heredoc_restore(parser,n)
# define whole_match_p(e,l,i)      parser_whole_match_p(parser,e,l,i)

#ifdef RIPPER
/* FIXME */
# define local_cnt(x)      3
# define local_id(x)       1
# define dyna_in_block()   1
#endif /* RIPPER */

#ifndef RIPPER
# define set_yylval_str(x) yylval.node = NEW_STR(x)
# define set_yylval_num(x) yylval.num = x
# define set_yylval_id(x)  yylval.id = x
# define set_yylval_literal(x) yylval.node = NEW_LIT(x)
# define set_yylval_node(x) yylval.node = x
# define yylval_id() yylval.id
#else
# define set_yylval_str(x) x
# define set_yylval_num(x) x
# define set_yylval_id(x) x
# define set_yylval_literal(x) x
# define set_yylval_node(x) x
# define yylval_id() SYM2ID(yylval.val)
#endif

#ifdef RIPPER
#define ripper_flush(p) (p->tokp = p->parser_lex_p)

static void
ripper_dispatch_scan_event(parser, t)
    struct parser_params *parser;
    int t;
{
    VALUE str;

    if (lex_p < parser->tokp) rb_raise(rb_eRuntimeError, "lex_p < tokp");
    if (lex_p == parser->tokp) return;
    str = rb_str_new(parser->tokp, lex_p - parser->tokp);
    yylval.val = ripper_dispatch1(parser, ripper_token2eventid(t), str);
    ripper_flush(parser);
}

static void
ripper_dispatch_delayed_token(parser, t)
    struct parser_params *parser;
    int t;
{
    int saved_line = ruby_sourceline;
    char *saved_tokp = parser->tokp;

    ruby_sourceline = parser->delayed_line;
    parser->tokp = lex_pbeg + parser->delayed_col;
    yylval.val = ripper_dispatch1(parser, ripper_token2eventid(t), parser->delayed);
    parser->delayed = Qnil;
    ruby_sourceline = saved_line;
    parser->tokp = saved_tokp;
}
#endif /* RIPPER */

#include "regex.h"
#include "util.h"

/* We remove any previous definition of `SIGN_EXTEND_CHAR',
   since ours (we hope) works properly with all combinations of
   machines, compilers, `char' and `unsigned char' argument types.
   (Per Bothner suggested the basic approach.)  */
#undef SIGN_EXTEND_CHAR
#if __STDC__
# define SIGN_EXTEND_CHAR(c) ((signed char)(c))
#else  /* not __STDC__ */
/* As in Harbison and Steele.  */
# define SIGN_EXTEND_CHAR(c) ((((unsigned char)(c)) ^ 128) - 128)
#endif
#define is_identchar(c) (SIGN_EXTEND_CHAR(c)!=-1&&(ISALNUM(c) || (c) == '_' || ismbchar(c)))

static int
parser_yyerror(parser, msg)
    struct parser_params *parser;
    const char *msg;
{
#ifndef RIPPER
    char *p, *pe, *buf;
    int len, i;

    rb_compile_error("%s", msg);
    p = lex_p;
    while (lex_pbeg <= p) {
	if (*p == '\n') break;
	p--;
    }
    p++;

    pe = lex_p;
    while (pe < lex_pend) {
	if (*pe == '\n') break;
	pe++;
    }

    len = pe - p;
    if (len > 4) {
	buf = ALLOCA_N(char, len+2);
	MEMCPY(buf, p, char, len);
	buf[len] = '\0';
	rb_compile_error_append("%s", buf);

	i = lex_p - p;
	p = buf; pe = p + len;

	while (p < pe) {
	    if (*p != '\t') *p = ' ';
	    p++;
	}
	buf[i] = '^';
	buf[i+1] = '\0';
	rb_compile_error_append("%s", buf);
    }
#else
    dispatch1(parse_error, rb_str_new2(msg));
#endif /* !RIPPER */
    return 0;
}

static void parser_prepare _((struct parser_params *parser));

#ifndef RIPPER
int ruby__end__seen;
static VALUE ruby_debug_lines;

static NODE*
yycompile(parser, f, line)
    struct parser_params *parser;
    char *f;
    int line;
{
    int n;
    NODE *node = 0;
    struct RVarmap *vp, *vars = ruby_dyna_vars;
    const char *kcode_save;

    if (!compile_for_eval && rb_safe_level() == 0 &&
	rb_const_defined(rb_cObject, rb_intern("SCRIPT_LINES__"))) {
	VALUE hash, fname;

	hash = rb_const_get(rb_cObject, rb_intern("SCRIPT_LINES__"));
	if (TYPE(hash) == T_HASH) {
	    fname = rb_str_new2(f);
	    ruby_debug_lines = rb_hash_aref(hash, fname);
	    if (NIL_P(ruby_debug_lines)) {
		ruby_debug_lines = rb_ary_new();
		rb_hash_aset(hash, fname, ruby_debug_lines);
	    }
	}
	if (line > 1) {
	    VALUE str = rb_str_new(0,0);
	    n = line - 1;
	    do {
		rb_ary_push(ruby_debug_lines, str);
	    } while (--n);
	}
    }

    kcode_save = rb_get_kcode();
    ruby_current_node = 0;
    ruby_sourcefile = rb_source_filename(f);
    ruby_sourceline = line - 1;
    parser_prepare(parser);
    n = yyparse((void*)parser);
    ruby_debug_lines = 0;
    compile_for_eval = 0;
    rb_set_kcode(kcode_save);

    vp = ruby_dyna_vars;
    ruby_dyna_vars = vars;
    lex_strterm = 0;
    while (vp && vp != vars) {
	struct RVarmap *tmp = vp;
	vp = vp->next;
	rb_gc_force_recycle((VALUE)tmp);
    }
    if (ruby_eval_tree_begin) {
	return NEW_PRELUDE(ruby_eval_tree_begin, ruby_eval_tree);
    }
    else {
	return ruby_eval_tree;
    }

    if (n == 0) node = ruby_eval_tree;
    else ruby_eval_tree_begin = 0;
    return node;
}
#endif /* !RIPPER */

static VALUE lex_get_str _((struct parser_params *, VALUE));
static VALUE
lex_get_str(parser, s)
    struct parser_params *parser;
    VALUE s;
{
    char *beg, *end, *pend;

    beg = RSTRING(s)->ptr;
    if (lex_gets_ptr) {
	if (RSTRING(s)->len == lex_gets_ptr) return Qnil;
	beg += lex_gets_ptr;
    }
    pend = RSTRING(s)->ptr + RSTRING(s)->len;
    end = beg;
    while (end < pend) {
	if (*end++ == '\n') break;
    }
    lex_gets_ptr = end - RSTRING(s)->ptr;
    return rb_str_new(beg, end - beg);
}

static VALUE
lex_getline(parser)
    struct parser_params *parser;
{
    VALUE line = (*parser->parser_lex_gets)(parser, parser->parser_lex_input);
#ifndef RIPPER
    if (ruby_debug_lines && !NIL_P(line)) {
	rb_ary_push(ruby_debug_lines, line);
    }
#endif
    return line;
}

#ifndef RIPPER
NODE*
rb_compile_string(f, s, line)
    const char *f;
    VALUE s;
    int line;
{
    VALUE volatile vparser = rb_parser_s_new();
    struct parser_params *parser;

    Data_Get_Struct(vparser, struct parser_params, parser);
    lex_gets = lex_get_str;
    lex_gets_ptr = 0;
    lex_input = s;
    lex_pbeg = lex_p = lex_pend = 0;
    compile_for_eval = ruby_in_eval;

    return yycompile(parser, f, line);
}

NODE*
rb_compile_cstr(f, s, len, line)
    const char *f, *s;
    int len, line;
{
    return rb_compile_string(f, rb_str_new(s, len), line);
}

static VALUE lex_io_gets _((struct parser_params *, VALUE));
static VALUE
lex_io_gets(parser, io)
    struct parser_params *parser;
    VALUE io;
{
    return rb_io_gets(io);
}

NODE*
rb_compile_file(f, file, start)
    const char *f;
    VALUE file;
    int start;
{
    VALUE volatile vparser = rb_parser_s_new();
    struct parser_params *parser;
    
    Data_Get_Struct(vparser, struct parser_params, parser);
    lex_gets = lex_io_gets;
    lex_input = file;
    lex_pbeg = lex_p = lex_pend = 0;

    return yycompile(parser, f, start);
}
#endif  /* !RIPPER */

static inline int
parser_nextc(parser)
    struct parser_params *parser;
{
    int c;

    if (lex_p == lex_pend) {
        if (parser->eofp)
            return -1;
	if (lex_input) {
	    VALUE v = lex_getline(parser);

	    if (NIL_P(v)) {
                parser->eofp = Qtrue;
                return -1;
            }
#ifdef RIPPER
	    if (parser->tokp < lex_pend) {
		if (NIL_P(parser->delayed)) {
		    parser->delayed = rb_str_buf_new(1024);
		    rb_str_buf_cat(parser->delayed,
				   parser->tokp, lex_pend - parser->tokp);
		    parser->delayed_line = ruby_sourceline;
		    parser->delayed_col = parser->tokp - lex_pbeg;
		}
		else {
		    rb_str_buf_cat(parser->delayed,
				   parser->tokp, lex_pend - parser->tokp);
		}
	    }
#endif
	    if (heredoc_end > 0) {
		ruby_sourceline = heredoc_end;
		heredoc_end = 0;
	    }
	    ruby_sourceline++;
	    parser->line_count++;
	    lex_pbeg = lex_p = RSTRING(v)->ptr;
	    lex_pend = lex_p + RSTRING(v)->len;
#ifdef RIPPER
	    ripper_flush(parser);
#endif
	    lex_lastline = v;
	}
	else {
	    lex_lastline = 0;
	    return -1;
	}
    }
    c = (unsigned char)*lex_p++;
    if (c == '\r' && lex_p < lex_pend && *lex_p == '\n') {
	lex_p++;
	c = '\n';
    }

    return c;
}

static void
parser_pushback(parser, c)
    struct parser_params *parser;
    int c;
{
    if (c == -1) return;
    lex_p--;
    if (lex_p > lex_pbeg && lex_p[0] == '\n' && lex_p[-1] == '\r') {
	lex_p--;
    }
}

#define lex_goto_eol(parser) (parser->parser_lex_p = parser->parser_lex_pend)
#define was_bol() (lex_p == lex_pbeg + 1)
#define peek(c) (lex_p != lex_pend && (c) == *lex_p)

#define tokfix() (tokenbuf[tokidx]='\0')
#define tok() tokenbuf
#define toklen() tokidx
#define toklast() (tokidx>0?tokenbuf[tokidx-1]:0)

static char*
parser_newtok(parser)
    struct parser_params *parser;
{
    tokidx = 0;
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

static void
parser_tokadd(parser, c)
    struct parser_params *parser;
    char c;
{
    tokenbuf[tokidx++] = c;
    if (tokidx >= toksiz) {
	toksiz *= 2;
	REALLOC_N(tokenbuf, char, toksiz);
    }
}

static int
parser_read_escape(parser)
    struct parser_params *parser;
{
    int c;

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
	{
	    int numlen;

	    pushback(c);
	    c = scan_oct(lex_p, 3, &numlen);
	    lex_p += numlen;
	}
	return c;

      case 'x':	/* hex constant */
	{
	    int numlen;

	    c = scan_hex(lex_p, 2, &numlen);
	    if (numlen == 0) {
		yyerror("Invalid escape character syntax");
		return 0;
	    }
	    lex_p += numlen;
	}
	return c;

      case 'b':	/* backspace */
	return '\010';

      case 's':	/* space */
	return ' ';

      case 'M':
	if ((c = nextc()) != '-') {
	    yyerror("Invalid escape character syntax");
	    pushback(c);
	    return '\0';
	}
	if ((c = nextc()) == '\\') {
	    return read_escape() | 0x80;
	}
	else if (c == -1) goto eof;
	else {
	    return ((c & 0xff) | 0x80);
	}

      case 'C':
	if ((c = nextc()) != '-') {
	    yyerror("Invalid escape character syntax");
	    pushback(c);
	    return '\0';
	}
      case 'c':
	if ((c = nextc())== '\\') {
	    c = read_escape();
	}
	else if (c == '?')
	    return 0177;
	else if (c == -1) goto eof;
	return c & 0x9f;

      eof:
      case -1:
        yyerror("Invalid escape character syntax");
	return '\0';

      default:
	return c;
    }
}

static int
parser_tokadd_escape(parser, term)
    struct parser_params *parser;
    int term;
{
    int c;

    switch (c = nextc()) {
      case '\n':
	return 0;		/* just ignore */

      case '0': case '1': case '2': case '3': /* octal constant */
      case '4': case '5': case '6': case '7':
	{
	    int i;

	    tokadd('\\');
	    tokadd(c);
	    for (i=0; i<2; i++) {
		c = nextc();
		if (c == -1) goto eof;
		if (c < '0' || '7' < c) {
		    pushback(c);
		    break;
		}
		tokadd(c);
	    }
	}
	return 0;

      case 'x':	/* hex constant */
	{
	    int numlen;

	    tokadd('\\');
	    tokadd(c);
	    scan_hex(lex_p, 2, &numlen);
	    if (numlen == 0) {
		yyerror("Invalid escape character syntax");
		return -1;
	    }
	    while (numlen--)
		tokadd(nextc());
	}
	return 0;

      case 'M':
	if ((c = nextc()) != '-') {
	    yyerror("Invalid escape character syntax");
	    pushback(c);
	    return 0;
	}
	tokadd('\\'); tokadd('M'); tokadd('-');
	goto escaped;

      case 'C':
	if ((c = nextc()) != '-') {
	    yyerror("Invalid escape character syntax");
	    pushback(c);
	    return 0;
	}
	tokadd('\\'); tokadd('C'); tokadd('-');
	goto escaped;

      case 'c':
	tokadd('\\'); tokadd('c');
      escaped:
	if ((c = nextc()) == '\\') {
	    return tokadd_escape(term);
	}
	else if (c == -1) goto eof;
	tokadd(c);
	return 0;

      eof:
      case -1:
        yyerror("Invalid escape character syntax");
	return -1;

      default:
	if (c != '\\' || c != term)
	    tokadd('\\');
	tokadd(c);
    }
    return 0;
}

static int
parser_regx_options(parser)
    struct parser_params *parser;
{
    char kcode = 0;
    int options = 0;
    int c;

    newtok();
    while (c = nextc(), ISALPHA(c)) {
	switch (c) {
	  case 'i':
	    options |= ONIG_OPTION_IGNORECASE;
	    break;
	  case 'x':
	    options |= ONIG_OPTION_EXTEND;
	    break;
	  case 'm':
	    options |= ONIG_OPTION_MULTILINE;
	    break;
	  case 'o':
	    options |= RE_OPTION_ONCE;
	    break;
	  case 'n':
	    kcode = 16;
	    break;
	  case 'e':
	    kcode = 32;
	    break;
	  case 's':
	    kcode = 48;
	    break;
	  case 'u':
	    kcode = 64;
	    break;
	  default:
	    tokadd(c);
	    break;
	}
    }
    pushback(c);
    if (toklen()) {
	tokfix();
	compile_error(PARSER_ARG "unknown regexp option%s - %s",
		  toklen() > 1 ? "s" : "", tok());
    }
    return options | kcode;
}

#define STR_FUNC_ESCAPE 0x01
#define STR_FUNC_EXPAND 0x02
#define STR_FUNC_REGEXP 0x04
#define STR_FUNC_QWORDS 0x08
#define STR_FUNC_SYMBOL 0x10
#define STR_FUNC_INDENT 0x20

enum string_type {
    str_squote = (0),
    str_dquote = (STR_FUNC_EXPAND),
    str_xquote = (STR_FUNC_EXPAND),
    str_regexp = (STR_FUNC_REGEXP|STR_FUNC_ESCAPE|STR_FUNC_EXPAND),
    str_sword  = (STR_FUNC_QWORDS),
    str_dword  = (STR_FUNC_QWORDS|STR_FUNC_EXPAND),
    str_ssym   = (STR_FUNC_SYMBOL),
    str_dsym   = (STR_FUNC_SYMBOL|STR_FUNC_EXPAND),
};

static void
dispose_string(str)
    VALUE str;
{
    xfree(RSTRING(str)->ptr);
    rb_gc_force_recycle(str);
}

static int
parser_tokadd_string(parser, func, term, paren, nest)
    struct parser_params *parser;
    int func, term, paren;
    long *nest;
{
    int c;
    unsigned char uc;

    while ((c = nextc()) != -1) {
        uc = (unsigned char)c;
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

	      default:
		if (func & STR_FUNC_REGEXP) {
		    pushback(c);
		    if (tokadd_escape(term) < 0)
			return -1;
		    continue;
		}
		else if (func & STR_FUNC_EXPAND) {
		    pushback(c);
		    if (func & STR_FUNC_ESCAPE) tokadd('\\');
		    c = read_escape();
		}
		else if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
		    /* ignore backslashed spaces in %w */
		}
		else if (c != term && !(paren && c == paren)) {
		    tokadd('\\');
		}
	    }
	}
	else if (ismbchar(uc)) {
	    int i, len = mbclen(uc)-1;

	    for (i = 0; i < len; i++) {
		tokadd(c);
		c = nextc();
	    }
	}
	else if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
	    pushback(c);
	    break;
	}
	if (!c && (func & STR_FUNC_SYMBOL)) {
	    func &= ~STR_FUNC_SYMBOL;
	    rb_compile_error(PARSER_ARG  "symbol cannot contain '\\0'");
	    continue;
	}
	tokadd(c);
    }
    return c;
}

#define NEW_STRTERM0(func, term, paren) \
	rb_node_newnode(NODE_STRTERM, (func), (term) | ((paren) << (CHAR_BIT * 2)), 0)
#ifndef RIPPER
# define NEW_STRTERM(func, term, paren) NEW_STRTERM0(func, term, paren)
#else
# define NEW_STRTERM(func, term, paren) ripper_new_strterm(parser, func, term, paren)
static NODE *
ripper_new_strterm(parser, func, term, paren)
    struct parser_params *parser;
    VALUE func, term, paren;
{
    NODE *node = NEW_STRTERM0(func, term, paren);
    nd_set_line(node, ruby_sourceline);
    return node;
}
#endif

static int
parser_parse_string(parser, quote)
    struct parser_params *parser;
    NODE *quote;
{
    int func = quote->nd_func;
    int term = nd_term(quote);
    int paren = nd_paren(quote);
    int c, space = 0;

    if (func == -1) return tSTRING_END;
    c = nextc();
    if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
	do {c = nextc();} while (ISSPACE(c));
	space = 1;
    }
    if (c == term && !quote->nd_nest) {
	if (func & STR_FUNC_QWORDS) {
	    quote->nd_func = -1;
	    return ' ';
	}
	if (!(func & STR_FUNC_REGEXP)) return tSTRING_END;
        set_yylval_num(regx_options());
	return tREGEXP_END;
    }
    if (space) {
	pushback(c);
	return ' ';
    }
    newtok();
    if ((func & STR_FUNC_EXPAND) && c == '#') {
	switch (c = nextc()) {
	  case '$':
	  case '@':
	    pushback(c);
	    return tSTRING_DVAR;
	  case '{':
	    return tSTRING_DBEG;
	}
	tokadd('#');
    }
    pushback(c);
    if (tokadd_string(func, term, paren, &quote->nd_nest) == -1) {
	ruby_sourceline = nd_line(quote);
	rb_compile_error(PARSER_ARG  "unterminated string meets end of file");
	return tSTRING_END;
    }

    tokfix();
    set_yylval_str(rb_str_new(tok(), toklen()));
    return tSTRING_CONTENT;
}

static int
parser_heredoc_identifier(parser)
    struct parser_params *parser;
{
    int c = nextc(), term, func = 0, len;
    unsigned int uc;

    if (c == '-') {
	c = nextc();
	func = STR_FUNC_INDENT;
    }
    switch (c) {
      case '\'':
	func |= str_squote; goto quoted;
      case '"':
	func |= str_dquote; goto quoted;
      case '`':
	func |= str_xquote;
      quoted:
	newtok();
	tokadd(func);
	term = c;
	while ((c = nextc()) != -1 && c != term) {
            uc = (unsigned int)c;
	    len = mbclen(uc);
	    do {tokadd(c);} while (--len > 0 && (c = nextc()) != -1);
	}
	if (c == -1) {
	    rb_compile_error(PARSER_ARG  "unterminated here document identifier");
	    return 0;
	}
	break;

      default:
        uc = (unsigned int)c;
	if (!is_identchar(uc)) {
	    pushback(c);
	    if (func & STR_FUNC_INDENT) {
		pushback('-');
	    }
	    return 0;
	}
	newtok();
	term = '"';
	tokadd(func |= str_dquote);
	do {
            uc = (unsigned int)c;
	    len = mbclen(uc);
	    do {tokadd(c);} while (--len > 0 && (c = nextc()) != -1);
	} while ((c = nextc()) != -1 &&
		 (uc = (unsigned char)c, is_identchar(uc)));
	pushback(c);
	break;
    }

    tokfix();
#ifdef RIPPER
    ripper_dispatch_scan_event(parser, tHEREDOC_BEG);
#endif
    len = lex_p - lex_pbeg;
    lex_goto_eol(parser);
    lex_strterm = rb_node_newnode(NODE_HEREDOC,
				  rb_str_new(tok(), toklen()),	/* nd_lit */
				  len,				/* nd_nth */
				  lex_lastline);		/* nd_orig */
    nd_set_line(lex_strterm, ruby_sourceline);
#ifdef RIPPER
    ripper_flush(parser);
#endif
    return term == '`' ? tXSTRING_BEG : tSTRING_BEG;
}

static void
parser_heredoc_restore(parser, here)
    struct parser_params *parser;
    NODE *here;
{
    VALUE line;

#ifdef RIPPER
    if (!NIL_P(parser->delayed))
	ripper_dispatch_delayed_token(parser, tSTRING_CONTENT);
    lex_goto_eol(parser);
    ripper_dispatch_scan_event(parser, tHEREDOC_END);
#endif
    line = here->nd_orig;
    lex_lastline = line;
    lex_pbeg = RSTRING(line)->ptr;
    lex_pend = lex_pbeg + RSTRING(line)->len;
    lex_p = lex_pbeg + here->nd_nth;
    heredoc_end = ruby_sourceline;
    ruby_sourceline = nd_line(here);
    dispose_string(here->nd_lit);
    rb_gc_force_recycle((VALUE)here);
#ifdef RIPPER
    ripper_flush(parser);
#endif
}

static int
parser_whole_match_p(parser, eos, len, indent)
    struct parser_params *parser;
    char *eos;
    int len, indent;
{
    char *p = lex_pbeg;
    int n;

    if (indent) {
	while (*p && ISSPACE(*p)) p++;
    }
    n= lex_pend - (p + len);
    if (n < 0 || (n > 0 && p[len] != '\n' && p[len] != '\r')) return Qfalse;
    if (strncmp(eos, p, len) == 0) return Qtrue;
    return Qfalse;
}

static int
parser_here_document(parser, here)
    struct parser_params *parser;
    NODE *here;
{
    int c, func, indent = 0;
    char *eos, *p, *pend;
    long len;
    VALUE str = 0;

    eos = RSTRING(here->nd_lit)->ptr;
    len = RSTRING(here->nd_lit)->len - 1;
    indent = (func = *eos++) & STR_FUNC_INDENT;

    if ((c = nextc()) == -1) {
      error:
	rb_compile_error(PARSER_ARG  "can't find string \"%s\" anywhere before EOF", eos);
	heredoc_restore(lex_strterm);
	lex_strterm = 0;
	return 0;
    }
    if (was_bol() && whole_match_p(eos, len, indent)) {
	heredoc_restore(lex_strterm);
	return tSTRING_END;
    }

    if (!(func & STR_FUNC_EXPAND)) {
	do {
	    p = RSTRING(lex_lastline)->ptr;
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
	    if (str)
		rb_str_cat(str, p, pend - p);
	    else
		str = rb_str_new(p, pend - p);
	    if (pend < lex_pend) rb_str_cat(str, "\n", 1);
	    lex_goto_eol(parser);
	    if (nextc() == -1) {
		if (str) dispose_string(str);
		goto error;
	    }
	} while (!whole_match_p(eos, len, indent));
    }
    else {
	newtok();
	if (c == '#') {
	    switch (c = nextc()) {
	      case '$':
	      case '@':
		pushback(c);
		return tSTRING_DVAR;
	      case '{':
		return tSTRING_DBEG;
	    }
	    tokadd('#');
	}
	do {
	    pushback(c);
	    if ((c = tokadd_string(func, '\n', 0, NULL)) == -1) goto error;
	    if (c != '\n') {
                set_yylval_str(rb_str_new(tok(), toklen()));
		return tSTRING_CONTENT;
	    }
	    tokadd(nextc());
	    if ((c = nextc()) == -1) goto error;
	} while (!whole_match_p(eos, len, indent));
	str = rb_str_new(tok(), toklen());
    }
    heredoc_restore(lex_strterm);
    lex_strterm = NEW_STRTERM(-1, 0, 0);
    set_yylval_str(str);
    return tSTRING_CONTENT;
}

#include "lex.c"

#ifndef RIPPER
static void
arg_ambiguous()
{
    rb_warning("ambiguous first argument; put parentheses or even spaces");
}
#else
static void
ripper_arg_ambiguous(parser)
    struct parser_params *parser;
{
    dispatch0(arg_ambiguous);
}
#define arg_ambiguous() ripper_arg_ambiguous(parser)
#endif

static int
lvar_defined_gen(parser, id)
    struct parser_params *parser;
    ID id;
{
#ifndef RIPPER
    return (dyna_in_block() && rb_dvar_defined(id)) || local_id(id);
#else
    return 0;
#endif
}

/* emacsen -*- hack */
#ifndef RIPPER
typedef void (*rb_pragma_setter_t) _((struct parser_params *parser, const char *name, const char *val));

static void pragma_encoding _((struct parser_params *, const char *, const char *));
static void
pragma_encoding(parser, name, val)
    struct parser_params *parser;
    const char *name, *val;
{
    if (parser && parser->line_count != (parser->has_shebang ? 2 : 1))
	return;
    rb_set_kcode(val);
}

struct pragma {
    const char *name;
    rb_pragma_setter_t func;
};

static const struct pragma pragmas[] = {
    {"coding", pragma_encoding},
};
#endif

static const char *
pragma_marker(str, len)
    const char *str;
    int len;
{
    int i = 2;

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
parser_pragma(parser, str, len)
    struct parser_params *parser;
    const char *str;
    int len;
{
    VALUE name = 0, val = 0;
    const char *beg, *end, *vbeg, *vend;
#define str_copy(_s, _p, _n) ((_s) \
	? (rb_str_resize((_s), (_n)), \
	   MEMCPY(RSTRING(_s)->ptr, (_p), char, (_n)), (_s)) \
	: ((_s) = rb_str_new((_p), (_n))))

    if (len <= 7) return Qfalse;
    if (!(beg = pragma_marker(str, len))) return Qfalse;
    if (!(end = pragma_marker(beg, str + len - beg))) return Qfalse;
    str = beg;
    len = end - beg - 3;
    
    /* %r"([^\\s\'\":;]+)\\s*:\\s*(\"(?:\\\\.|[^\"])*\"|[^\"\\s;]+)[\\s;]*" */
    while (len > 0) {
#ifndef RIPPER
	const struct pragma *p = pragmas;
#endif
	int n = 0;

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
	if (*str != ':') continue;

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
	    for (vbeg = str; len > 0 && *str != '"' && !ISSPACE(*str); --len, str++);
	    vend = str;
	}
	while (len > 0 && (*str == ';' || ISSPACE(*str))) --len, str++;

	n = end - beg;
	str_copy(name, beg, n);
	rb_funcall(name, rb_intern("downcase!"), 0);
#ifndef RIPPER
	do {
	    if (strncmp(p->name, RSTRING(name)->ptr, n) == 0) {
		str_copy(val, vbeg, vend - vbeg);
		(*p->func)(parser, RSTRING(name)->ptr, RSTRING(val)->ptr);
		break;
	    }
	} while (++p < pragmas + sizeof(pragmas) / sizeof(*p));
#else
	dispatch2(pragma, name, val);
#endif
    }

    return Qtrue;
}

static void
parser_prepare(parser)
    struct parser_params *parser;
{
    int c = nextc();
    switch (c) {
      case '#':
	if (peek('!')) parser->has_shebang = 1;
	break;
      case 0xef:		/* UTF-8 BOM marker */
	if (lex_pend - lex_p >= 2 &&
	    (unsigned char)lex_p[0] == 0xbb &&
	    (unsigned char)lex_p[1] == 0xbf) {
	    rb_set_kcode("UTF-8");
	    lex_p += 2;
	    return;
	}
	break;
      case EOF:
	return;
    }
    pushback(c);
}

#define IS_ARG() (lex_state == EXPR_ARG || lex_state == EXPR_CMDARG)
#define IS_BEG() (lex_state == EXPR_BEG || lex_state == EXPR_MID || lex_state == EXPR_VALUE || lex_state == EXPR_CLASS)

static int
parser_yylex(parser)
    struct parser_params *parser;
{
    register int c;
    int space_seen = 0;
    int cmd_state;
    unsigned char uc;
#ifdef RIPPER
    int fallthru = Qfalse;
#endif

    if (lex_strterm) {
	int token;
	if (nd_type(lex_strterm) == NODE_HEREDOC) {
	    token = here_document(lex_strterm);
	    if (token == tSTRING_END) {
		lex_strterm = 0;
		lex_state = EXPR_END;
	    }
	}
	else {
	    token = parse_string(lex_strterm);
	    if (token == tSTRING_END || token == tREGEXP_END) {
		rb_gc_force_recycle((VALUE)lex_strterm);
		lex_strterm = 0;
		lex_state = EXPR_END;
	    }
	}
	return token;
    }
    cmd_state = command_start;
    command_start = Qfalse;
  retry:
#ifdef RIPPER
    while ((c = nextc())) {
        switch (c) {
          case ' ': case '\t': case '\f': case '\r':
          case '\13': /* '\v' */
            space_seen++;
            break;
          default:
            goto outofloop;
        }
    }
  outofloop:
    pushback(c);
    ripper_dispatch_scan_event(parser, tSP);
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
	space_seen++;
	goto retry;

      case '#':		/* it's a comment */
	if (!parser->has_shebang || parser->line_count != 1) {
	    /* no pragma in shebang line */
	    parser_pragma(parser, lex_p, lex_pend - lex_p);
	}
	lex_p = lex_pend;
#ifdef RIPPER
        ripper_dispatch_scan_event(parser, tCOMMENT);
        fallthru = Qtrue;
#endif
	/* fall through */
      case '\n':
	switch (lex_state) {
	  case EXPR_BEG:
	  case EXPR_FNAME:
	  case EXPR_DOT:
	  case EXPR_CLASS:
	  case EXPR_VALUE:
#ifdef RIPPER
            if (!fallthru) {
                ripper_dispatch_scan_event(parser, tIGNORED_NL);
            }
            fallthru = Qfalse;
#endif
	    goto retry;
	  default:
	    break;
	}
	command_start = Qtrue;
	lex_state = EXPR_BEG;
	return '\n';

      case '*':
	if ((c = nextc()) == '*') {
	    if ((c = nextc()) == '=') {
                set_yylval_id(tPOW);
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    c = tPOW;
	}
	else {
	    if (c == '=') {
                set_yylval_id('*');
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    if (IS_ARG() && space_seen && !ISSPACE(c)){
		rb_warning0("`*' interpreted as argument prefix");
		c = tSTAR;
	    }
	    else if (IS_BEG()) {
		c = tSTAR;
	    }
	    else {
		c = '*';
	    }
	}
	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG; break;
	}
	return c;

      case '!':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
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
#ifdef RIPPER
                int first_p = Qtrue;

                lex_goto_eol(parser);
                ripper_dispatch_scan_event(parser, tEMBDOC_BEG);
#endif
		for (;;) {
		    lex_goto_eol(parser);
#ifdef RIPPER
                    if (!first_p) {
                        ripper_dispatch_scan_event(parser, tEMBDOC);
                    }
                    first_p = Qfalse;
#endif
		    c = nextc();
		    if (c == -1) {
			rb_compile_error(PARSER_ARG  "embedded document meets end of file");
			return 0;
		    }
		    if (c != '=') continue;
		    if (strncmp(lex_p, "end", 3) == 0 &&
			(lex_p + 3 == lex_pend || ISSPACE(lex_p[3]))) {
			break;
		    }
		}
		lex_goto_eol(parser);
#ifdef RIPPER
                ripper_dispatch_scan_event(parser, tEMBDOC_END);
#endif
		goto retry;
	    }
	}

	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG; break;
	}
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
	c = nextc();
	if (c == '<' &&
	    lex_state != EXPR_END &&
	    lex_state != EXPR_DOT &&
	    lex_state != EXPR_ENDARG &&
	    lex_state != EXPR_CLASS &&
	    (!IS_ARG() || space_seen)) {
	    int token = heredoc_identifier();
	    if (token) return token;
	}
	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG; break;
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
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tLSHFT;
	}
	pushback(c);
	return '<';

      case '>':
	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG; break;
	}
	if ((c = nextc()) == '=') {
	    return tGEQ;
	}
	if (c == '>') {
	    if ((c = nextc()) == '=') {
                set_yylval_id(tRSHFT);
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tRSHFT;
	}
	pushback(c);
	return '>';

      case '"':
	lex_strterm = NEW_STRTERM(str_dquote, '"', 0);
	return tSTRING_BEG;

      case '`':
	if (lex_state == EXPR_FNAME) {
	    lex_state = EXPR_END;
	    return c;
	}
	if (lex_state == EXPR_DOT) {
	    if (cmd_state)
		lex_state = EXPR_CMDARG;
	    else
		lex_state = EXPR_ARG;
	    return c;
	}
	lex_strterm = NEW_STRTERM(str_xquote, '`', 0);
	return tXSTRING_BEG;

      case '\'':
	lex_strterm = NEW_STRTERM(str_squote, '\'', 0);
	return tSTRING_BEG;

      case '?':
	if (lex_state == EXPR_END || lex_state == EXPR_ENDARG) {
	    lex_state = EXPR_VALUE;
	    return '?';
	}
	c = nextc();
	if (c == -1) {
	    rb_compile_error(PARSER_ARG  "incomplete character syntax");
	    return 0;
	}
        uc = (unsigned char)c;
	if (ISSPACE(c)){
	    if (!IS_ARG()){
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
		    rb_warnI("invalid character syntax; use ?\\%c", c2);
		}
	    }
	  ternary:
	    pushback(c);
	    lex_state = EXPR_VALUE;
	    return '?';
	}
	else if (ismbchar(uc)) {
	    rb_warnI("multibyte character literal not supported yet; use ?\\%.3o", c);
	    goto ternary;
	}
	else if ((ISALNUM(c) || c == '_') && lex_p < lex_pend && is_identchar(*lex_p)) {
	    goto ternary;
	}
	else if (c == '\\') {
	    c = read_escape();
	}
	c &= 0xff;
	lex_state = EXPR_END;
        set_yylval_literal(INT2FIX(c));
	return tINTEGER;

      case '&':
	if ((c = nextc()) == '&') {
	    lex_state = EXPR_BEG;
	    if ((c = nextc()) == '=') {
                set_yylval_id(tANDOP);
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tANDOP;
	}
	else if (c == '=') {
            set_yylval_id('&');
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	pushback(c);
	if (IS_ARG() && space_seen && !ISSPACE(c)){
	    rb_warning0("`&' interpreted as argument prefix");
	    c = tAMPER;
	}
	else if (IS_BEG()) {
	    c = tAMPER;
	}
	else {
	    c = '&';
	}
	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG;
	}
	return c;

      case '|':
	if ((c = nextc()) == '|') {
	    lex_state = EXPR_BEG;
	    if ((c = nextc()) == '=') {
                set_yylval_id(tOROP);
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tOROP;
	}
	if (c == '=') {
            set_yylval_id('|');
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
	    lex_state = EXPR_ARG;
	}
	else {
	    lex_state = EXPR_BEG;
	}
	pushback(c);
	return '|';

      case '+':
	c = nextc();
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
	    lex_state = EXPR_ARG;
	    if (c == '@') {
		return tUPLUS;
	    }
	    pushback(c);
	    return '+';
	}
	if (c == '=') {
            set_yylval_id('+');
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	if (IS_BEG() ||
	    (IS_ARG() && space_seen && !ISSPACE(c))) {
	    if (IS_ARG()) arg_ambiguous();
	    lex_state = EXPR_BEG;
	    pushback(c);
	    if (ISDIGIT(c)) {
		c = '+';
		goto start_num;
	    }
	    return tUPLUS;
	}
	lex_state = EXPR_BEG;
	pushback(c);
	return '+';

      case '-':
	c = nextc();
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
	    lex_state = EXPR_ARG;
	    if (c == '@') {
		return tUMINUS;
	    }
	    pushback(c);
	    return '-';
	}
	if (c == '=') {
            set_yylval_id('-');
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	if (IS_BEG() ||
	    (IS_ARG() && space_seen && !ISSPACE(c))) {
	    if (IS_ARG()) arg_ambiguous();
	    lex_state = EXPR_BEG;
	    pushback(c);
	    if (ISDIGIT(c)) {
		return tUMINUS_NUM;
	    }
	    return tUMINUS;
	}
	lex_state = EXPR_BEG;
	pushback(c);
	return '-';

      case '.':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '.') {
	    if ((c = nextc()) == '.') {
		return tDOT3;
	    }
	    pushback(c);
	    return tDOT2;
	}
	pushback(c);
	if (ISDIGIT(c)) {
	    yyerror("no .<digit> floating literal anymore; put 0 before dot");
	}
	lex_state = EXPR_DOT;
	return '.';

      start_num:
      case '0': case '1': case '2': case '3': case '4':
      case '5': case '6': case '7': case '8': case '9':
	{
	    int is_float, seen_point, seen_e, nondigit;

	    is_float = seen_point = seen_e = nondigit = 0;
	    lex_state = EXPR_END;
	    newtok();
	    if (c == '-' || c == '+') {
		tokadd(c);
		c = nextc();
	    }
	    if (c == '0') {
		int start = toklen();
		c = nextc();
		if (c == 'x' || c == 'X') {
		    /* hexadecimal */
		    c = nextc();
		    if (ISXDIGIT(c)) {
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
			yyerror("numeric literal without digits");
		    }
		    else if (nondigit) goto trailing_uc;
                    set_yylval_literal(rb_cstr_to_inum(tok(), 16, Qfalse));
		    return tINTEGER;
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
			yyerror("numeric literal without digits");
		    }
		    else if (nondigit) goto trailing_uc;
                    set_yylval_literal(rb_cstr_to_inum(tok(), 2, Qfalse));
		    return tINTEGER;
		}
		if (c == 'd' || c == 'D') {
		    /* decimal */
		    c = nextc();
		    if (ISDIGIT(c)) {
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
			yyerror("numeric literal without digits");
		    }
		    else if (nondigit) goto trailing_uc;
                    set_yylval_literal(rb_cstr_to_inum(tok(), 10, Qfalse));
		    return tINTEGER;
		}
		if (c == '_') {
		    /* 0_0 */
		    goto octal_number;
		}
		if (c == 'o' || c == 'O') {
		    /* prefixed octal */
		    c = nextc();
		    if (c == '_') {
			yyerror("numeric literal without digits");
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
			if (c < '0' || c > '7') break;
			nondigit = 0;
			tokadd(c);
		    } while ((c = nextc()) != -1);
		    if (toklen() > start) {
			pushback(c);
			tokfix();
			if (nondigit) goto trailing_uc;
                        set_yylval_literal(rb_cstr_to_inum(tok(), 8, Qfalse));
			return tINTEGER;
		    }
		    if (nondigit) {
			pushback(c);
			goto trailing_uc;
		    }
		}
		if (c > '7' && c <= '9') {
		    yyerror("Illegal octal digit");
		}
		else if (c == '.' || c == 'e' || c == 'E') {
		    tokadd('0');
		}
		else {
		    pushback(c);
                    set_yylval_literal(INT2FIX(0));
		    return tINTEGER;
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
			if (!ISDIGIT(c0)) {
			    pushback(c0);
			    goto decode_num;
			}
			c = c0;
		    }
		    tokadd('.');
		    tokadd(c);
		    is_float++;
		    seen_point++;
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
		    tokadd(c);
		    seen_e++;
		    is_float++;
		    nondigit = c;
		    c = nextc();
		    if (c != '-' && c != '+') continue;
		    tokadd(c);
		    nondigit = c;
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
	    tokfix();
	    if (nondigit) {
		char tmp[30];
	      trailing_uc:
		sprintf(tmp, "trailing `%c' in number", nondigit);
		yyerror(tmp);
	    }
	    if (is_float) {
		double d = strtod(tok(), 0);
		if (errno == ERANGE) {
		    rb_warnS("Float %s out of range", tok());
		    errno = 0;
		}
                set_yylval_literal(rb_float_new(d));
		return tFLOAT;
	    }
            set_yylval_literal(rb_cstr_to_inum(tok(), 10, Qfalse));
	    return tINTEGER;
	}

      case ']':
      case '}':
      case ')':
	COND_LEXPOP();
	CMDARG_LEXPOP();
	lex_state = EXPR_END;
	return c;

      case ':':
	c = nextc();
	if (c == ':') {
	    if (IS_BEG() ||
		lex_state == EXPR_CLASS || (IS_ARG() && space_seen)) {
		lex_state = EXPR_BEG;
		return tCOLON3;
	    }
	    lex_state = EXPR_DOT;
	    return tCOLON2;
	}
	if (lex_state == EXPR_END || lex_state == EXPR_ENDARG || ISSPACE(c)) {
	    pushback(c);
	    lex_state = EXPR_BEG;
	    return ':';
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
	lex_state = EXPR_FNAME;
	return tSYMBEG;

      case '/':
	if (IS_BEG()) {
	    lex_strterm = NEW_STRTERM(str_regexp, '/', 0);
	    return tREGEXP_BEG;
	}
	if ((c = nextc()) == '=') {
            set_yylval_id('/');
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	pushback(c);
	if (IS_ARG() && space_seen) {
	    if (!ISSPACE(c)) {
		arg_ambiguous();
		lex_strterm = NEW_STRTERM(str_regexp, '/', 0);
		return tREGEXP_BEG;
	    }
	}
	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG; break;
	}
	return '/';

      case '^':
	if ((c = nextc()) == '=') {
            set_yylval_id('^');
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG; break;
	}
	pushback(c);
	return '^';

      case ';':
	if ((c = nextc()) == ';') {
	    lex_state = EXPR_END;
	    return kEND;
	}
	pushback(c);
	c = ';';
	command_start = Qtrue;
      case ',':
	lex_state = EXPR_BEG;
	return c;

      case '~':
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
	    if ((c = nextc()) != '@') {
		pushback(c);
	    }
	}
	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG; break;
	}
	return '~';

      case '(':
	if (IS_BEG()) {
	    c = tLPAREN;
	}
	else if (space_seen) {
	    if (lex_state == EXPR_CMDARG) {
		c = tLPAREN_ARG;
	    }
	    else if (lex_state == EXPR_ARG) {
		rb_warning0("don't put space before argument parentheses");
		c = '(';
	    }
	}
	COND_PUSH(0);
	CMDARG_PUSH(0);
	lex_state = EXPR_BEG;
	return c;

      case '[':
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
	    lex_state = EXPR_ARG;
	    if ((c = nextc()) == ']') {
		if ((c = nextc()) == '=') {
		    return tASET;
		}
		pushback(c);
		return tAREF;
	    }
	    pushback(c);
	    return '[';
	}
	else if (IS_BEG()) {
	    c = tLBRACK;
	}
	else if (IS_ARG() && space_seen) {
	    c = tLBRACK;
	}
	lex_state = EXPR_BEG;
	COND_PUSH(0);
	CMDARG_PUSH(0);
	return c;

      case '{':
	if (IS_ARG() || lex_state == EXPR_END)
	    c = '{';          /* block (primary) */
	else if (lex_state == EXPR_ENDARG)
	    c = tLBRACE_ARG;  /* block (expr) */
	else
	    c = tLBRACE;      /* hash */
	COND_PUSH(0);
	CMDARG_PUSH(0);
	lex_state = EXPR_BEG;
	return c;

      case '\\':
	c = nextc();
	if (c == '\n') {
	    space_seen = 1;
#ifdef RIPPER
	    ripper_dispatch_scan_event(parser, tSP);
#endif
	    goto retry; /* skip \\n */
	}
	pushback(c);
	return '\\';

      case '%':
	if (IS_BEG()) {
	    int term;
	    int paren;

	    c = nextc();
	  quotation:
	    if (!ISALNUM(c)) {
		term = c;
		c = 'Q';
	    }
	    else {
		term = nextc();
                uc = (unsigned char)c;
		if (ISALNUM(term) || ismbchar(uc)) {
		    yyerror("unknown type of %string");
		    return 0;
		}
	    }
	    if (c == -1 || term == -1) {
		rb_compile_error(PARSER_ARG  "unterminated quoted string meets end of file");
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
		lex_strterm = NEW_STRTERM(str_dquote | STR_FUNC_QWORDS, term, paren);
		do {c = nextc();} while (ISSPACE(c));
		pushback(c);
		return tWORDS_BEG;

	      case 'w':
		lex_strterm = NEW_STRTERM(str_squote | STR_FUNC_QWORDS, term, paren);
		do {c = nextc();} while (ISSPACE(c));
		pushback(c);
		return tQWORDS_BEG;

	      case 'x':
		lex_strterm = NEW_STRTERM(str_xquote, term, paren);
		return tXSTRING_BEG;

	      case 'r':
		lex_strterm = NEW_STRTERM(str_regexp, term, paren);
		return tREGEXP_BEG;

	      case 's':
		lex_strterm = NEW_STRTERM(str_ssym, term, paren);
		lex_state = EXPR_FNAME;
		return tSYMBEG;

	      default:
		yyerror("unknown type of %string");
		return 0;
	    }
	}
	if ((c = nextc()) == '=') {
            set_yylval_id('%');
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	if (IS_ARG() && space_seen && !ISSPACE(c)) {
	    goto quotation;
	}
	switch (lex_state) {
	  case EXPR_FNAME: case EXPR_DOT:
	    lex_state = EXPR_ARG; break;
	  default:
	    lex_state = EXPR_BEG; break;
	}
	pushback(c);
	return '%';

      case '$':
	lex_state = EXPR_END;
	newtok();
	c = nextc();
	switch (c) {
	  case '_':		/* $_: last read line string */
	    c = nextc();
            uc = (unsigned char)c;
	    if (is_identchar(uc)) {
		tokadd('$');
		tokadd('_');
		break;
	    }
	    pushback(c);
	    c = '_';
	    /* fall through */
	  case '~':		/* $~: match-data */
	    local_cnt(c);
	    /* fall through */
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
	    tokfix();
            set_yylval_id(rb_intern(tok()));
	    return tGVAR;

	  case '-':
	    tokadd('$');
	    tokadd(c);
	    c = nextc();
	    tokadd(c);
	    tokfix();
            set_yylval_id(rb_intern(tok()));
	    if (!is_global_id(yylval_id())) {
	    	rb_compile_error(PARSER_ARG  "invalid global variable `%s'", rb_id2name(yylval.id));
		return 0;
	    }
	    return tGVAR;

	  case '&':		/* $&: last match */
	  case '`':		/* $`: string before last match */
	  case '\'':		/* $': string after last match */
	  case '+':		/* $+: string matches last paren. */
	    set_yylval_node(NEW_BACK_REF(c));
	    return tBACK_REF;

	  case '1': case '2': case '3':
	  case '4': case '5': case '6':
	  case '7': case '8': case '9':
	    tokadd('$');
	    do {
		tokadd(c);
		c = nextc();
	    } while (ISDIGIT(c));
	    pushback(c);
	    tokfix();
	    set_yylval_node(NEW_NTH_REF(atoi(tok()+1)));
	    return tNTH_REF;

	  default:
            uc = (unsigned char)c;
	    if (!is_identchar(uc)) {
		pushback(c);
		return '$';
	    }
	  case '0':
	    tokadd('$');
	}
	break;

      case '@':
	c = nextc();
	newtok();
	tokadd('@');
	if (c == '@') {
	    tokadd('@');
	    c = nextc();
	}
	if (ISDIGIT(c)) {
	    if (tokidx == 1) {
		rb_compile_error(PARSER_ARG  "`@%c' is not allowed as an instance variable name", c);
	    }
	    else {
		rb_compile_error(PARSER_ARG  "`@@%c' is not allowed as a class variable name", c);
	    }
	}
        uc = (unsigned char)c;
	if (!is_identchar(uc)) {
	    pushback(c);
	    return '@';
	}
	break;

      case '_':
	if (was_bol() && whole_match_p("__END__", 7, 0)) {
	    ruby__end__seen = 1;
	    lex_lastline = 0;
#ifndef RIPPER
	    return -1;
#else
            lex_goto_eol(parser);
            ripper_dispatch_scan_event(parser, k__END__);
            return 0;
#endif
	}
	newtok();
	break;

      default:
	uc = (unsigned char)c;
	if (!is_identchar(uc)) {
	    rb_compile_error(PARSER_ARG  "Invalid char `\\%03o' in expression", c);
	    goto retry;
	}

	newtok();
	break;
    }

    uc = (unsigned char)c;
    do {
	tokadd(c);
	if (ismbchar(uc)) {
	    int i, len = mbclen(uc)-1;

	    for (i = 0; i < len; i++) {
		c = nextc();
		tokadd(c);
	    }
	}
	c = nextc();
        uc = (unsigned char)c;
    } while (is_identchar(uc));
    if ((c == '!' || c == '?') && is_identchar(tok()[0]) && !peek('=')) {
	tokadd(c);
    }
    else {
	pushback(c);
    }
    tokfix();

    {
	int result = 0;
	enum lex_state_e last_state = lex_state;

	switch (tok()[0]) {
	  case '$':
	    lex_state = EXPR_END;
	    result = tGVAR;
	    break;
	  case '@':
	    lex_state = EXPR_END;
	    if (tok()[1] == '@')
		result = tCVAR;
	    else
		result = tIVAR;
	    break;

	  default:
	    if (toklast() == '!' || toklast() == '?') {
		result = tFID;
	    }
	    else {
		if (lex_state == EXPR_FNAME) {
		    if ((c = nextc()) == '=' && !peek('~') && !peek('>') &&
			(!peek('=') || (lex_p + 1 < lex_pend && lex_p[1] == '>'))) {
			result = tIDENTIFIER;
			tokadd(c);
			tokfix();
		    }
		    else {
			pushback(c);
		    }
		}
		if (result == 0 && ISUPPER(tok()[0])) {
		    result = tCONSTANT;
		}
		else {
		    result = tIDENTIFIER;
		}
	    }

	    if (lex_state != EXPR_DOT) {
		struct kwtable *kw;

		/* See if it is a reserved word.  */
		kw = rb_reserved_word(tok(), toklen());
		if (kw) {
		    enum lex_state_e state = lex_state;
		    lex_state = kw->state;
		    if (state == EXPR_FNAME) {
                        set_yylval_id(rb_intern(kw->name));
		    }
		    if (kw->id[0] == kDO) {
			if (COND_P()) return kDO_COND;
			if (CMDARG_P() && state != EXPR_CMDARG)
			    return kDO_BLOCK;
			if (state == EXPR_ENDARG || state == EXPR_BEG)
			    return kDO_BLOCK;
			return kDO;
		    }
		    if (state == EXPR_BEG || state == EXPR_VALUE)
			return kw->id[0];
		    else {
			if (kw->id[0] != kw->id[1])
			    lex_state = EXPR_BEG;
			return kw->id[1];
		    }
		}
	    }

	    if ((lex_state == EXPR_BEG && !cmd_state) ||
		lex_state == EXPR_ARG ||
		lex_state == EXPR_CMDARG) {
		if (peek(':') && !(lex_p + 1 < lex_pend && lex_p[1] == ':')) {
		    lex_state = EXPR_BEG;
		    nextc();
		    set_yylval_id(rb_intern(tok()));
		    return tLABEL;
		}
	    }
	    if (IS_BEG() ||
		lex_state == EXPR_DOT ||
		IS_ARG()) {
		if (cmd_state) {
		    lex_state = EXPR_CMDARG;
		}
		else {
		    lex_state = EXPR_ARG;
		}
	    }
	    else {
		lex_state = EXPR_END;
	    }
	}
        {
            ID ident = rb_intern(tok());

            set_yylval_id(ident);
            if (last_state != EXPR_DOT && is_local_id(ident) && lvar_defined(ident)) {
                lex_state = EXPR_END;
            }
        }
	return result;
    }
}

#if YYPURE
static int
yylex(lval, p)
    void *lval, *p;
#else
yylex(p)
    void *p;
#endif
{
    struct parser_params *parser = (struct parser_params*)p;
    int t;

#if YYPURE
    parser->parser_yylval = (union tmpyystype*)lval;
    parser->parser_yylval->val = Qundef;
#endif
    t = parser_yylex(parser);
#ifdef RIPPER
    if (!NIL_P(parser->delayed)) {
	ripper_dispatch_delayed_token(parser, t);
	return t;
    }
    if (t != 0)
	ripper_dispatch_scan_event(parser, t);
#endif

    return t;
}

#ifndef RIPPER
NODE*
rb_node_newnode(type, a0, a1, a2)
    enum node_type type;
    VALUE a0, a1, a2;
{
    NODE *n = (NODE*)rb_newobj();

    n->flags |= T_NODE;
    nd_set_type(n, type);
    nd_set_line(n, ruby_sourceline);
    n->nd_file = ruby_sourcefile;

    n->u1.value = a0;
    n->u2.value = a1;
    n->u3.value = a2;

    return n;
}

static enum node_type
nodetype(node)			/* for debug */
    NODE *node;
{
    return (enum node_type)nd_type(node);
}

static int
nodeline(node)
    NODE *node;
{
    return nd_line(node);
}

static NODE*
newline_node(node)
    NODE *node;
{
    if (node) {
	node->flags |= NODE_NEWLINE;
    }
    return node;
}

static void
fixpos(node, orig)
    NODE *node, *orig;
{
    if (!node) return;
    if (!orig) return;
    if (orig == (NODE*)1) return;
    node->nd_file = orig->nd_file;
    nd_set_line(node, nd_line(orig));
}

static void
parser_warning(node, mesg)
    NODE *node;
    const char *mesg;
{
    int line = ruby_sourceline;
    ruby_sourceline = nd_line(node);
    rb_warning(mesg);
    ruby_sourceline = line;
}

static void
parser_warn(node, mesg)
    NODE *node;
    const char *mesg;
{
    int line = ruby_sourceline;
    ruby_sourceline = nd_line(node);
    rb_warn(mesg);
    ruby_sourceline = line;
}

static NODE*
block_append(head, tail)
    NODE *head, *tail;
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
	fixpos(end, head);
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
	    parser_warning(nd, "statement not reached");
	}
	break;

      default:
	break;
    }

    if (nd_type(tail) != NODE_BLOCK) {
	tail = NEW_BLOCK(tail);
	tail->nd_end = tail;
    }
    end->nd_next = tail;
    h->nd_end = tail->nd_end;
    return head;
}

/* append item to the list */
static NODE*
list_append(list, item)
    NODE *list, *item;
{
    NODE *last;

    if (list == 0) return NEW_LIST(item);
    if (list->nd_next) {
	last = list->nd_next->nd_end;
    }
    else {
	last = list;
    }

    list->nd_alen += 1;
    last->nd_next = NEW_LIST(item);
    list->nd_next->nd_end = last->nd_next;
    return list;
}

/* concat two lists */
static NODE*
list_concat(head, tail)
    NODE *head, *tail;
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

    return head;
}

/* concat two string literals */
static NODE *
literal_concat(head, tail)
    NODE *head, *tail;
{
    enum node_type htype;

    if (!head) return tail;
    if (!tail) return head;

    htype = nd_type(head);
    if (htype == NODE_EVSTR) {
	NODE *node = NEW_DSTR(rb_str_new(0, 0));
	head = list_append(node, head);
    }
    switch (nd_type(tail)) {
      case NODE_STR:
	if (htype == NODE_STR) {
	    rb_str_concat(head->nd_lit, tail->nd_lit);
	    rb_gc_force_recycle((VALUE)tail);
	}
	else {
	    list_append(head, tail);
	}
	break;

      case NODE_DSTR:
	if (htype == NODE_STR) {
	    rb_str_concat(head->nd_lit, tail->nd_lit);
	    tail->nd_lit = head->nd_lit;
	    rb_gc_force_recycle((VALUE)head);
	    head = tail;
	}
	else {
	    nd_set_type(tail, NODE_ARRAY);
	    tail->nd_head = NEW_STR(tail->nd_lit);
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
evstr2dstr(node)
    NODE *node;
{
    if (nd_type(node) == NODE_EVSTR) {
	node = list_append(NEW_DSTR(rb_str_new(0, 0)), node);
    }
    return node;
}

static NODE *
new_evstr(node)
    NODE *node;
{
    NODE *head = node;

    if (node) {
	switch (nd_type(node)) {
	  case NODE_STR: case NODE_DSTR: case NODE_EVSTR:
	    return node;
	}
    }
    return NEW_EVSTR(head);
}

static NODE *
call_op_gen(parser, recv, id, narg, arg1)
    struct parser_params *parser;
    NODE *recv;
    ID id;
    int narg;
    NODE *arg1;
{
    value_expr(arg1);
    if (narg == 1) {
	value_expr(arg1);
	arg1 = NEW_LIST(arg1);
    }
    else {
	arg1 = 0;
    }
    return NEW_CALL(recv, id, arg1);
}

static NODE*
match_op_gen(parser, node1, node2)
    struct parser_params *parser;
    NODE *node1;
    NODE *node2;
{
    local_cnt('~');

    value_expr(node1);
    value_expr(node2);
    if (node1) {
	switch (nd_type(node1)) {
	  case NODE_DREGX:
	  case NODE_DREGX_ONCE:
	    return NEW_MATCH2(node1, node2);

	  case NODE_LIT:
	    if (TYPE(node1->nd_lit) == T_REGEXP) {
		return NEW_MATCH2(node1, node2);
	    }
	}
    }

    if (node2) {
	switch (nd_type(node2)) {
	  case NODE_DREGX:
	  case NODE_DREGX_ONCE:
	    return NEW_MATCH3(node2, node1);

	  case NODE_LIT:
	    if (TYPE(node2->nd_lit) == T_REGEXP) {
		return NEW_MATCH3(node2, node1);
	    }
	}
    }

    return NEW_CALL(node1, tMATCH, NEW_LIST(node2));
}

static NODE*
gettable_gen(parser, id)
    struct parser_params *parser;
    ID id;
{
    if (id == kSELF) {
	return NEW_SELF();
    }
    else if (id == kNIL) {
	return NEW_NIL();
    }
    else if (id == kTRUE) {
	return NEW_TRUE();
    }
    else if (id == kFALSE) {
	return NEW_FALSE();
    }
    else if (id == k__FILE__) {
	return NEW_STR(rb_str_new2(ruby_sourcefile));
    }
    else if (id == k__LINE__) {
	return NEW_LIT(INT2FIX(ruby_sourceline));
    }
    else if (is_local_id(id)) {
	if (dyna_in_block() && rb_dvar_defined(id)) return NEW_DVAR(id);
	if (local_id(id)) return NEW_LVAR(id);
	/* method call without arguments */
        dyna_check(id);
	return NEW_VCALL(id);
    }
    else if (is_global_id(id)) {
	return NEW_GVAR(id);
    }
    else if (is_instance_id(id)) {
	return NEW_IVAR(id);
    }
    else if (is_const_id(id)) {
	return NEW_CONST(id);
    }
    else if (is_class_id(id)) {
	return NEW_CVAR(id);
    }
    rb_compile_error("identifier %s is not valid", rb_id2name(id));
    return 0;
}

static NODE*
assignable_gen(parser, id, val)
    struct parser_params *parser;
    ID id;
    NODE *val;
{
    value_expr(val);
    if (id == kSELF) {
	yyerror("Can't change the value of self");
    }
    else if (id == kNIL) {
	yyerror("Can't assign to nil");
    }
    else if (id == kTRUE) {
	yyerror("Can't assign to true");
    }
    else if (id == kFALSE) {
	yyerror("Can't assign to false");
    }
    else if (id == k__FILE__) {
	yyerror("Can't assign to __FILE__");
    }
    else if (id == k__LINE__) {
	yyerror("Can't assign to __LINE__");
    }
    else if (is_local_id(id)) {
	if (rb_dvar_curr(id)) {
	    return NEW_DASGN_CURR(id, val);
	}
	else if (rb_dvar_defined(id)) {
	    return NEW_DASGN(id, val);
	}
	else if (local_id(id) || !dyna_in_block()) {
	    return NEW_LASGN(id, val);
	}
	else{
	    dyna_var(id);
	    return NEW_DASGN_CURR(id, val);
	}
    }
    else if (is_global_id(id)) {
	return NEW_GASGN(id, val);
    }
    else if (is_instance_id(id)) {
	return NEW_IASGN(id, val);
    }
    else if (is_const_id(id)) {
	if (in_def || in_single)
	    yyerror("dynamic constant assignment");
	return NEW_CDECL(id, val, 0);
    }
    else if (is_class_id(id)) {
	if (in_def || in_single) return NEW_CVASGN(id, val);
	return NEW_CVDECL(id, val);
    }
    else {
	rb_compile_error("identifier %s is not valid", rb_id2name(id));
    }
    return 0;
}

static NODE*
new_bv_gen(parser, name, val)
    struct parser_params *parser;
    ID name;
    NODE *val;
{
    if (is_local_id(name) && !rb_dvar_defined(name) && !local_id(name)) {
	dyna_var(name);
	return NEW_DASGN_CURR(name, val);
    }
    else {
	compile_error(PARSER_ARG "local variable name conflict - %s",
		      rb_id2name(name));
	return 0;
    }
}
static NODE *
aryset_gen(parser, recv, idx)
    struct parser_params *parser;
    NODE *recv, *idx;
{
    if (recv && nd_type(recv) == NODE_SELF)
	recv = (NODE *)1;
    else
	value_expr(recv);
    return NEW_ATTRASGN(recv, tASET, idx);
}

ID
rb_id_attrset(id)
    ID id;
{
    id &= ~ID_SCOPE_MASK;
    id |= ID_ATTRSET;
    return id;
}

static NODE *
attrset_gen(parser, recv, id)
    struct parser_params *parser;
    NODE *recv;
    ID id;
{
    if (recv && nd_type(recv) == NODE_SELF)
	recv = (NODE *)1;
    else
	value_expr(recv);
    return NEW_ATTRASGN(recv, rb_id_attrset(id), 0);
}

static void
rb_backref_error(node)
    NODE *node;
{
    switch (nd_type(node)) {
      case NODE_NTH_REF:
	rb_compile_error("Can't set variable $%d", node->nd_nth);
	break;
      case NODE_BACK_REF:
	rb_compile_error("Can't set variable $%c", (int)node->nd_nth);
	break;
    }
}

static NODE *
arg_concat(node1, node2)
    NODE *node1;
    NODE *node2;
{
    if (!node2) return node1;
    return NEW_ARGSCAT(node1, node2);
}

static NODE *
arg_add(node1, node2)
    NODE *node1;
    NODE *node2;
{
    if (!node1) return NEW_LIST(node2);
    if (nd_type(node1) == NODE_ARRAY) {
	return list_append(node1, node2);
    }
    else {
	return NEW_ARGSPUSH(node1, node2);
    }
}

static NODE*
node_assign_gen(parser, lhs, rhs)
    struct parser_params *parser;
    NODE *lhs, *rhs;
{
    if (!lhs) return 0;

    value_expr(rhs);
    switch (nd_type(lhs)) {
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_DASGN_CURR:
      case NODE_MASGN:
      case NODE_CDECL:
      case NODE_CVDECL:
      case NODE_CVASGN:
	lhs->nd_value = rhs;
	break;

      case NODE_ATTRASGN:
      case NODE_CALL:
	lhs->nd_args = arg_add(lhs->nd_args, rhs);
	break;

      default:
	/* should not happen */
	break;
    }

    return lhs;
}

static int
value_expr_gen(parser, node)
    struct parser_params *parser;
    NODE *node;
{
    int cond = 0;

    while (node) {
	switch (nd_type(node)) {
	  case NODE_DEFN:
	  case NODE_DEFS:
	    parser_warning(node, "void value expression");
	    return Qfalse;

	  case NODE_RETURN:
	  case NODE_BREAK:
	  case NODE_NEXT:
	  case NODE_REDO:
	  case NODE_RETRY:
	    if (!cond) yyerror("void value expression");
	    /* or "control never reach"? */
	    return Qfalse;

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
	    if (!value_expr(node->nd_body)) return Qfalse;
	    node = node->nd_else;
	    break;

	  case NODE_AND:
	  case NODE_OR:
	    cond = 1;
	    node = node->nd_2nd;
	    break;

	  default:
	    return Qtrue;
	}
    }

    return Qtrue;
}

static void
void_expr_gen(parser, node)
    struct parser_params *parser;
    NODE *node;
{
    char *useless = 0;

    if (!RTEST(ruby_verbose)) return;

    if (!node) return;
    switch (nd_type(node)) {
      case NODE_CALL:
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
      case NODE_CREF:
	useless = "a constant";
	break;
      case NODE_LIT:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
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
	int line = ruby_sourceline;

	ruby_sourceline = nd_line(node);
	rb_warn("useless use of %s in void context", useless);
	ruby_sourceline = line;
    }
}

static void
void_stmts_gen(parser, node)
    struct parser_params *parser;
    NODE *node;
{
    if (!RTEST(ruby_verbose)) return;
    if (!node) return;
    if (nd_type(node) != NODE_BLOCK) return;

    for (;;) {
	if (!node->nd_next) return;
	void_expr(node->nd_head);
	node = node->nd_next;
    }
}

static NODE *
remove_begin(node)
    NODE *node;
{
    NODE **n = &node;
    while (*n) {
	if (nd_type(*n) != NODE_BEGIN) {
	    return node;
	}
	*n = (*n)->nd_body;
    }
    return node;
}

static void
reduce_nodes(body)
    NODE **body;
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
	switch (nd_type(node)) {
	  end:
	  case NODE_NIL:
	    *body = 0;
	    return;
	  case NODE_RETURN:
	    *body = node = node->nd_stts;
	    continue;
	  case NODE_BEGIN:
	    *body = node = node->nd_body;
	    continue;
	  case NODE_BLOCK:
	    body = &node->nd_end->nd_head;
	    break;
	  case NODE_IF:
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
	    if (!subnodes(nd_head, nd_resq)) goto end;
	    break;
	  default:
	    return;
	}
	node = *body;
    }

#undef subnodes
}

static int
assign_in_cond(parser, node)
    struct parser_params *parser;
    NODE *node;
{
    switch (nd_type(node)) {
      case NODE_MASGN:
	yyerror("multiple assignment in conditional");
	return 1;

      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_GASGN:
      case NODE_IASGN:
	break;

      default:
	return 0;
    }

    switch (nd_type(node->nd_value)) {
      case NODE_LIT:
      case NODE_STR:
      case NODE_NIL:
      case NODE_TRUE:
      case NODE_FALSE:
	/* reports always */
	parser_warn(node->nd_value, "found = in conditional, should be ==");
	return 1;

      case NODE_DSTR:
      case NODE_XSTR:
      case NODE_DXSTR:
      case NODE_EVSTR:
      case NODE_DREGX:
      default:
	break;
    }
    return 1;
}

static int
e_option_supplied()
{
    if (strcmp(ruby_sourcefile, "-e") == 0)
	return Qtrue;
    return Qfalse;
}

static void
warn_unless_e_option(node, str)
    NODE *node;
    const char *str;
{
    if (!e_option_supplied()) parser_warn(node, str);
}

static void
warning_unless_e_option(node, str)
    NODE *node;
    const char *str;
{
    if (!e_option_supplied()) parser_warning(node, str);
}

static NODE *cond0 _((struct parser_params*,NODE*));

static NODE*
range_op(parser, node)
    struct parser_params *parser;
    NODE *node;
{
    enum node_type type;

    if (!e_option_supplied()) return node;
    if (node == 0) return 0;

    value_expr(node);
    node = cond0(parser, node);
    type = nd_type(node);
    if (type == NODE_LIT && FIXNUM_P(node->nd_lit)) {
	warn_unless_e_option(node, "integer literal in conditional range");
	return call_op(node,tEQ,1,NEW_GVAR(rb_intern("$.")));
    }
    return node;
}

static int
literal_node(node)
    NODE *node;
{
    if (!node) return 1;	/* same as NODE_NIL */
    switch (nd_type(node)) {
      case NODE_LIT:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_EVSTR:
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
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
cond0(parser, node)
    struct parser_params *parser;
    NODE *node;
{
    if (node == 0) return 0;
    assign_in_cond(parser, node);

    switch (nd_type(node)) {
      case NODE_DSTR:
      case NODE_EVSTR:
      case NODE_STR:
	rb_warn("string literal in condition");
	break;

      case NODE_DREGX:
      case NODE_DREGX_ONCE:
	warning_unless_e_option(node, "regex literal in condition");
	local_cnt('_');
	local_cnt('~');
	return NEW_MATCH2(node, NEW_GVAR(rb_intern("$_")));

      case NODE_AND:
      case NODE_OR:
	node->nd_1st = cond0(parser, node->nd_1st);
	node->nd_2nd = cond0(parser, node->nd_2nd);
	break;

      case NODE_DOT2:
      case NODE_DOT3:
	node->nd_beg = range_op(parser, node->nd_beg);
	node->nd_end = range_op(parser, node->nd_end);
	if (nd_type(node) == NODE_DOT2) nd_set_type(node,NODE_FLIP2);
	else if (nd_type(node) == NODE_DOT3) nd_set_type(node, NODE_FLIP3);
	node->nd_cnt = local_append(internal_id());
	if (!e_option_supplied()) {
	    int b = literal_node(node->nd_beg);
	    int e = literal_node(node->nd_end);
	    if ((b == 1 && e == 1) || (b + e >= 2 && RTEST(ruby_verbose))) {
		parser_warn(node, "range literal in condition");
	    }
	}
	break;

      case NODE_DSYM:
	parser_warning(node, "literal in condition");
	break;

      case NODE_LIT:
	if (TYPE(node->nd_lit) == T_REGEXP) {
	    warn_unless_e_option(node, "regex literal in condition");
	    nd_set_type(node, NODE_MATCH);
	    local_cnt('_');
	    local_cnt('~');
	}
	else {
	    parser_warning(node, "literal in condition");
	}
      default:
	break;
    }
    return node;
}

static NODE*
cond_gen(parser, node)
    struct parser_params *parser;
    NODE *node;
{
    if (node == 0) return 0;
    value_expr(node);
    return cond0(parser, node);
}

static NODE*
logop_gen(parser, type, left, right)
    struct parser_params *parser;
    enum node_type type;
    NODE *left, *right;
{
    value_expr(left);
    if (left && nd_type(left) == type) {
	NODE *node = left, *second;
	while ((second = node->nd_2nd) != 0 && nd_type(second) == type) {
	    node = second;
	}
	node->nd_2nd = NEW_NODE(type, second, right, 0);
	return left;
    }
    return NEW_NODE(type, left, right, 0);
}

static int
cond_negative(nodep)
    NODE **nodep;
{
    NODE *c = *nodep;

    if (!c) return 0;
    switch (nd_type(c)) {
      case NODE_NOT:
	*nodep = c->nd_body;
	return 1;
    }
    return 0;
}

static void
no_blockarg(node)
    NODE *node;
{
    if (node && nd_type(node) == NODE_BLOCK_PASS) {
	rb_compile_error("block argument should not be given");
    }
}

static NODE *
ret_args(node)
    NODE *node;
{
    if (node) {
	no_blockarg(node);
	if (nd_type(node) == NODE_ARRAY) {
	    if (node->nd_next == 0) {
		node = node->nd_head;
	    }
	    else {
		nd_set_type(node, NODE_VALUES);
	    }
	}
	else if (nd_type(node) == NODE_SPLAT) {
	    node = NEW_SVALUE(node);
	}
    }
    return node;
}

static NODE *
new_yield(node)
    NODE *node;
{
    long state = Qtrue;

    if (node) {
        no_blockarg(node);
        if (nd_type(node) == NODE_ARRAY && node->nd_next == 0) {
            node = node->nd_head;
            state = Qfalse;
        }
        else if (node && nd_type(node) == NODE_SPLAT) {
            state = Qtrue;
        }
    }
    else {
        state = Qfalse;
    }
    return NEW_YIELD(node, state);
}

static NODE*
negate_lit(node)
    NODE *node;
{
    switch (TYPE(node->nd_lit)) {
      case T_FIXNUM:
	node->nd_lit = LONG2FIX(-FIX2LONG(node->nd_lit));
	break;
      case T_BIGNUM:
	node->nd_lit = rb_funcall(node->nd_lit,tUMINUS,0,0);
	break;
      case T_FLOAT:
	RFLOAT(node->nd_lit)->value = -RFLOAT(node->nd_lit)->value;
	break;
      default:
	break;
    }
    return node;
}

static NODE *
arg_blk_pass(node1, node2)
    NODE *node1;
    NODE *node2;
{
    if (node2) {
	node2->nd_head = node1;
	return node2;
    }
    return node1;
}

static NODE*
arg_prepend(node1, node2)
    NODE *node1, *node2;
{
    switch (nd_type(node2)) {
      case NODE_ARRAY:
	return list_concat(NEW_LIST(node1), node2);

      case NODE_SPLAT:
	return arg_concat(node1, node2->nd_head);

      case NODE_BLOCK_PASS:
	node2->nd_body = arg_prepend(node1, node2->nd_body);
	return node2;

      default:
	rb_bug("unknown nodetype(%d) for arg_prepend", nd_type(node2));
    }
    return 0;			/* not reached */
}

static NODE*
new_call(r,m,a)
    NODE *r;
    ID m;
    NODE *a;
{
    if (a && nd_type(a) == NODE_BLOCK_PASS) {
	a->nd_iter = NEW_CALL(r,m,a->nd_head);
	return a;
    }
    return NEW_CALL(r,m,a);
}

static NODE*
fcall_gen(parser, m, a)
    struct parser_params *parser;
    ID m;
    NODE *a;
{
    if (is_local_id(m)) {
	if ((dyna_in_block() && rb_dvar_defined(m)) || local_id(m)) {
	    return NEW_CALL(gettable(m), rb_intern("call"), a);
	}
    }
    return NEW_FCALL(m,a);
}

static NODE*
new_fcall_gen(parser, m, a)
    struct parser_params *parser;
    ID m;
    NODE *a;
{
    if (a && nd_type(a) == NODE_BLOCK_PASS) {
	a->nd_iter = NEW_FCALL(m,a->nd_head);
	return a;
    }
    return NEW_FCALL(m, a);
}

static NODE*
new_super(a)
    NODE *a;
{
    if (a && nd_type(a) == NODE_BLOCK_PASS) {
	a->nd_iter = NEW_SUPER(a->nd_head);
	return a;
    }
    return NEW_SUPER(a);
}

static void
local_push_gen(parser, top)
    struct parser_params *parser;
    int top;
{
    struct local_vars *local;

    local = ALLOC(struct local_vars);
    local->prev = lvtbl;
    local->nofree = 0;
    local->cnt = 0;
    local->tbl = 0;
    local->dlev = 0;
    local->dname_size = 0;
    local->dnames = 0;
    local->dyna_vars = ruby_dyna_vars;
    lvtbl = local;
    if (!top) {
	/* preserve reference for GC, but link should be cut. */
	rb_dvar_push(0, (VALUE)ruby_dyna_vars);
	ruby_dyna_vars->next = 0;
    }
}

static void
local_pop_gen(parser)
    struct parser_params *parser;
{
    struct local_vars *local = lvtbl->prev;

    if (lvtbl->tbl) {
	if (!lvtbl->nofree) xfree(lvtbl->tbl);
	else lvtbl->tbl[0] = lvtbl->cnt;
    }
    if (lvtbl->dnames) {
	xfree(lvtbl->dnames);
    }
    ruby_dyna_vars = lvtbl->dyna_vars;
    xfree(lvtbl);
    lvtbl = local;
}

static ID*
local_tbl_gen(parser)
    struct parser_params *parser;
{
    lvtbl->nofree = 1;
    return lvtbl->tbl;
}

static int
local_append_gen(parser, id)
    struct parser_params *parser;
    ID id;
{
    if (lvtbl->tbl == 0) {
	lvtbl->tbl = ALLOC_N(ID, 4);
	lvtbl->tbl[0] = 0;
	lvtbl->tbl[1] = '_';
	lvtbl->tbl[2] = '~';
	lvtbl->cnt = 2;
	if (id == '_') return 0;
	if (id == '~') return 1;
    }
    else {
	REALLOC_N(lvtbl->tbl, ID, lvtbl->cnt+2);
    }

    lvtbl->tbl[lvtbl->cnt+1] = id;
    return lvtbl->cnt++;
}

static int
local_cnt_gen(parser, id)
    struct parser_params *parser;
    ID id;
{
    int cnt, max;

    if (id == 0) return lvtbl->cnt;

    for (cnt=1, max=lvtbl->cnt+1; cnt<max;cnt++) {
	if (lvtbl->tbl[cnt] == id) return cnt-1;
    }
    return local_append(id);
}

static int
local_id_gen(parser, id)
    struct parser_params *parser;
    ID id;
{
    int i, max;

    if (lvtbl == 0) return Qfalse;
    for (i=3, max=lvtbl->cnt+1; i<max; i++) {
	if (lvtbl->tbl[i] == id) return Qtrue;
    }
    return Qfalse;
}

static void
top_local_init_gen(parser)
    struct parser_params *parser;
{
    local_push(1);
    lvtbl->cnt = ruby_scope->local_tbl?ruby_scope->local_tbl[0]:0;
    if (lvtbl->cnt > 0) {
	lvtbl->tbl = ALLOC_N(ID, lvtbl->cnt+3);
	MEMCPY(lvtbl->tbl, ruby_scope->local_tbl, ID, lvtbl->cnt+1);
    }
    else {
	lvtbl->tbl = 0;
    }
    if (ruby_dyna_vars)
	lvtbl->dlev = 1;
    else
	lvtbl->dlev = 0;
}

static void
top_local_setup_gen(parser)
    struct parser_params *parser;
{
    int len = lvtbl->cnt;
    int i;

    if (len > 0) {
	i = ruby_scope->local_tbl?ruby_scope->local_tbl[0]:0;

	if (i < len) {
	    if (i == 0 || (ruby_scope->flags & SCOPE_MALLOC) == 0) {
		VALUE *vars = ALLOC_N(VALUE, len+1);
		if (ruby_scope->local_vars) {
		    *vars++ = ruby_scope->local_vars[-1];
		    MEMCPY(vars, ruby_scope->local_vars, VALUE, i);
		    rb_mem_clear(vars+i, len-i);
		}
		else {
		    *vars++ = 0;
		    rb_mem_clear(vars, len);
		}
		ruby_scope->local_vars = vars;
		ruby_scope->flags |= SCOPE_MALLOC;
	    }
	    else {
		VALUE *vars = ruby_scope->local_vars-1;
		REALLOC_N(vars, VALUE, len+1);
		ruby_scope->local_vars = vars+1;
		rb_mem_clear(ruby_scope->local_vars+i, len-i);
	    }
	    if (ruby_scope->local_tbl && ruby_scope->local_vars[-1] == 0) {
		xfree(ruby_scope->local_tbl);
	    }
	    ruby_scope->local_vars[-1] = 0;
	    ruby_scope->local_tbl = local_tbl();
	}
    }
    local_pop();
}

static void
dyna_var_gen(parser, id)
    struct parser_params *parser;
    ID id;
{
    int i;

    rb_dvar_push(id, Qnil);
    for (i=0; i<lvtbl->dname_size; i++) {
	if (lvtbl->dnames[i] == id) return;
    }
    if (lvtbl->dname_size == 0) {
	lvtbl->dnames = ALLOC_N(ID, 1);
    }
    else {
	REALLOC_N(lvtbl->dnames, ID, lvtbl->dname_size+1);
    }
    lvtbl->dnames[lvtbl->dname_size++] = id;
}

static void
dyna_check_gen(parser, id)
    struct parser_params *parser;
    ID id;
{
    int i;

    if (in_defined) return;	/* no check needed */
    for (i=0; i<lvtbl->dname_size; i++) {
	if (lvtbl->dnames[i] == id) {
	    rb_warnS("out-of-scope variable - %s", rb_id2name(id));
	    return;
	}
    }
}

static struct RVarmap*
dyna_push_gen(parser)
    struct parser_params *parser;
{
    struct RVarmap* vars = ruby_dyna_vars;

    rb_dvar_push(0, 0);
    lvtbl->dlev++;
    return vars;
}

static void
dyna_pop_gen(parser, vars)
    struct parser_params *parser;
    struct RVarmap* vars;
{
    lvtbl->dlev--;
    ruby_dyna_vars = vars;
}

static int
dyna_in_block_gen(parser)
    struct parser_params *parser;
{
    return (lvtbl->dlev > 0);
}

static NODE *
dyna_init_gen(parser, node, pre)
    struct parser_params *parser;
    NODE *node;
    struct RVarmap *pre;
{
    struct RVarmap *post = ruby_dyna_vars;
    NODE *var;

    if (!node || !post || pre == post) return node;
    for (var = 0; post != pre && post->id; post = post->next) {
	var = NEW_DASGN_CURR(post->id, var);
    }
    return block_append(var, node);
}

void
rb_gc_mark_parser()
{
    rb_gc_mark(ruby_debug_lines);
}

NODE*
rb_parser_append_print(node)
    NODE *node;
{
    NODE *prelude = 0;

    if (node && (nd_type(node) == NODE_PRELUDE)) {
	prelude = node;
	node = node->nd_body;
    }
    node = block_append(node,
			NEW_FCALL(rb_intern("print"),
				  NEW_ARRAY(NEW_GVAR(rb_intern("$_")))));
    if (prelude) {
	prelude->nd_body = node;
	return prelude;
    }
    return node;
}

NODE *
rb_parser_while_loop(node, chop, split)
    NODE *node;
    int chop, split;
{
    NODE *prelude = 0;

    if (node && (nd_type(node) == NODE_PRELUDE)) {
	prelude = node;
	node = node->nd_body;
    }
    if (split) {
	node = block_append(NEW_GASGN(rb_intern("$F"),
				      NEW_CALL(NEW_GVAR(rb_intern("$_")),
					       rb_intern("split"), 0)),
			    node);
    }
    if (chop) {
	node = block_append(NEW_CALL(NEW_GVAR(rb_intern("$_")),
				     rb_intern("chop!"), 0), node);
    }
    node = NEW_OPT_N(node);
    if (prelude) {
	prelude->nd_body = node;
	return prelude;
    }
    return node;
}

static struct {
    ID token;
    char *name;
} op_tbl[] = {
    {tDOT2,	".."},
    {tDOT3,	"..."},
    {'+',	"+"},
    {'-',	"-"},
    {'+',	"+(binary)"},
    {'-',	"-(binary)"},
    {'*',	"*"},
    {'/',	"/"},
    {'%',	"%"},
    {tPOW,	"**"},
    {tUPLUS,	"+@"},
    {tUMINUS,	"-@"},
    {tUPLUS,	"+(unary)"},
    {tUMINUS,	"-(unary)"},
    {'|',	"|"},
    {'^',	"^"},
    {'&',	"&"},
    {tCMP,	"<=>"},
    {'>',	">"},
    {tGEQ,	">="},
    {'<',	"<"},
    {tLEQ,	"<="},
    {tEQ,	"=="},
    {tEQQ,	"==="},
    {tNEQ,	"!="},
    {tMATCH,	"=~"},
    {tNMATCH,	"!~"},
    {'!',	"!"},
    {'~',	"~"},
    {'!',	"!(unary)"},
    {'~',	"~(unary)"},
    {'!',	"!@"},
    {'~',	"~@"},
    {tAREF,	"[]"},
    {tASET,	"[]="},
    {tLSHFT,	"<<"},
    {tRSHFT,	">>"},
    {tCOLON2,	"::"},
    {'`',	"`"},
    {0,	0}
};

static st_table *sym_tbl;
static st_table *sym_rev_tbl;

void
Init_sym()
{
    sym_tbl = st_init_strtable_with_size(200);
    sym_rev_tbl = st_init_numtable_with_size(200);
}

static ID last_id = tLAST_TOKEN;

static ID
internal_id()
{
    return ID_INTERNAL | (++last_id << ID_SCOPE_SHIFT);
}

ID
rb_intern(name)
    const char *name;
{
    const char *m = name;
    ID id;
    int last;

    if (st_lookup(sym_tbl, (st_data_t)name, (st_data_t *)&id))
	return id;

    last = strlen(name)-1;
    id = 0;
    switch (*name) {
      case '$':
	id |= ID_GLOBAL;
	m++;
	if (!is_identchar(*m)) m++;
	break;
      case '@':
	if (name[1] == '@') {
	    m++;
	    id |= ID_CLASS;
	}
	else {
	    id |= ID_INSTANCE;
	}
	m++;
	break;
      default:
	if (name[0] != '_' && !ISALPHA(name[0]) && !ismbchar(name[0])) {
	    /* operators */
	    int i;

	    for (i=0; op_tbl[i].token; i++) {
		if (*op_tbl[i].name == *name &&
		    strcmp(op_tbl[i].name, name) == 0) {
		    id = op_tbl[i].token;
		    goto id_regist;
		}
	    }
	}

	if (name[last] == '=') {
	    /* attribute assignment */
	    char *buf = ALLOCA_N(char,last+1);

	    strncpy(buf, name, last);
	    buf[last] = '\0';
	    id = rb_intern(buf);
	    if (id > tLAST_TOKEN && !is_attrset_id(id)) {
		id = rb_id_attrset(id);
		goto id_regist;
	    }
	    id = ID_ATTRSET;
	}
	else if (ISUPPER(name[0])) {
	    id = ID_CONST;
        }
	else {
	    id = ID_LOCAL;
	}
	break;
    }
    while (m <= name + last && is_identchar(*m)) {
	m += mbclen(*m);
    }
    if (*m) id = ID_JUNK;
    id |= ++last_id << ID_SCOPE_SHIFT;
  id_regist:
    name = strdup(name);
    st_add_direct(sym_tbl, (st_data_t)name, id);
    st_add_direct(sym_rev_tbl, id, (st_data_t)name);
    return id;
}

char *
rb_id2name(id)
    ID id;
{
    char *name;

    if (id < tLAST_TOKEN) {
	int i = 0;

	for (i=0; op_tbl[i].token; i++) {
	    if (op_tbl[i].token == id)
		return op_tbl[i].name;
	}
    }

    if (st_lookup(sym_rev_tbl, id, (st_data_t *)&name))
	return name;

    if (is_attrset_id(id)) {
	ID id2 = (id & ~ID_SCOPE_MASK) | ID_LOCAL;

      again:
	name = rb_id2name(id2);
	if (name) {
	    char *buf = ALLOCA_N(char, strlen(name)+2);

	    strcpy(buf, name);
	    strcat(buf, "=");
	    rb_intern(buf);
	    return rb_id2name(id);
	}
	if (is_local_id(id2)) {
	    id2 = (id & ~ID_SCOPE_MASK) | ID_CONST;
	    goto again;
	}
    }
    return 0;
}

static int
symbols_i(key, value, ary)
    char *key;
    ID value;
    VALUE ary;
{
    rb_ary_push(ary, ID2SYM(value));
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     Symbol.all_symbols    => array
 *  
 *  Returns an array of all the symbols currently in Ruby's symbol
 *  table.
 *     
 *     Symbol.all_symbols.size    #=> 903
 *     Symbol.all_symbols[1,20]   #=> [:floor, :ARGV, :Binding, :symlink,
 *                                     :chown, :EOFError, :$;, :String, 
 *                                     :LOCK_SH, :"setuid?", :$<, 
 *                                     :default_proc, :compact, :extend, 
 *                                     :Tms, :getwd, :$=, :ThreadGroup,
 *                                     :wait2, :$>]
 */

VALUE
rb_sym_all_symbols()
{
    VALUE ary = rb_ary_new2(sym_tbl->num_entries);

    st_foreach(sym_tbl, symbols_i, ary);
    return ary;
}

int
rb_is_const_id(id)
    ID id;
{
    if (is_const_id(id)) return Qtrue;
    return Qfalse;
}

int
rb_is_class_id(id)
    ID id;
{
    if (is_class_id(id)) return Qtrue;
    return Qfalse;
}

int
rb_is_instance_id(id)
    ID id;
{
    if (is_instance_id(id)) return Qtrue;
    return Qfalse;
}

int
rb_is_local_id(id)
    ID id;
{
    if (is_local_id(id)) return Qtrue;
    return Qfalse;
}

int
rb_is_junk_id(id)
    ID id;
{
    if (is_junk_id(id)) return Qtrue;
    return Qfalse;
}

static void
special_local_set(c, val)
    char c;
    VALUE val;
{
    VALUE volatile vparser = rb_parser_s_new();
    struct parser_params *parser;
    int cnt;
    
    Data_Get_Struct(vparser, struct parser_params, parser);
    top_local_init();
    cnt = local_cnt(c);
    top_local_setup();
    ruby_scope->local_vars[cnt] = val;
}

VALUE
rb_backref_get()
{
    VALUE *var = rb_svar(1);
    if (var) {
	return *var;
    }
    return Qnil;
}

void
rb_backref_set(val)
    VALUE val;
{
    VALUE *var = rb_svar(1);
    if (var) {
	*var = val;
    }
    else {
	special_local_set('~', val);
    }
}

VALUE
rb_lastline_get()
{
    VALUE *var = rb_svar(0);
    if (var) {
	return *var;
    }
    return Qnil;
}

void
rb_lastline_set(val)
    VALUE val;
{
    VALUE *var = rb_svar(0);
    if (var) {
	*var = val;
    }
    else {
	special_local_set('_', val);
    }
}
#endif /* !RIPPER */

static void
parser_initialize(parser)
    struct parser_params *parser;
{
    parser->eofp = Qfalse;

    parser->parser_lex_strterm = 0;
    parser->parser_cond_stack = 0;
    parser->parser_cmdarg_stack = 0;
    parser->parser_class_nest = 0;
    parser->parser_in_single = 0;
    parser->parser_in_def = 0;
    parser->parser_in_defined = 0;
    parser->parser_compile_for_eval = 0;
    parser->parser_cur_mid = 0;
    parser->parser_tokenbuf = NULL;
    parser->parser_tokidx = 0;
    parser->parser_toksiz = 0;
    parser->parser_heredoc_end = 0;
    parser->parser_command_start = Qtrue;
    parser->parser_lex_pbeg = 0;
    parser->parser_lex_p = 0;
    parser->parser_lex_pend = 0;
    parser->parser_lvtbl = 0;
#ifndef RIPPER
    parser->parser_eval_tree_begin = 0;
    parser->parser_eval_tree = 0;
#else
    parser->parser_ruby_sourcefile = Qnil;
    parser->delayed = Qnil;

    parser->result = Qnil;
    parser->parsing_thread = Qnil;
    parser->toplevel_p = Qtrue;
#endif
}

static void
parser_mark(ptr)
    void *ptr;
{
    struct parser_params *p = (struct parser_params*)ptr;

    rb_gc_mark((VALUE)p->parser_lex_strterm);
    rb_gc_mark(p->parser_lex_input);
    rb_gc_mark(p->parser_lex_lastline);
#ifndef RIPPER
    rb_gc_mark((VALUE)p->parser_eval_tree_begin) ;
    rb_gc_mark((VALUE)p->parser_eval_tree) ;
#else
    rb_gc_mark(p->parser_ruby_sourcefile);
    rb_gc_mark(p->delayed);
    rb_gc_mark(p->result);
    rb_gc_mark(p->parsing_thread);
#endif
}

static void
parser_free(ptr)
    void *ptr;
{
    struct parser_params *p = (struct parser_params*)ptr;
    struct local_vars *local, *prev;

    if (p->parser_tokenbuf) {
        xfree(p->parser_tokenbuf);
    }
    for (local = p->parser_lvtbl; local; local = prev) {
	if (local->tbl && !local->nofree)
	    xfree(local->tbl);
	prev = local->prev;
	xfree(local);
    }
    xfree(p);
}

#ifndef RIPPER
static struct parser_params *
parser_new()
{
    struct parser_params *p;

    p = ALLOC_N(struct parser_params, 1);
    MEMZERO(p, struct parser_params, 1);
    parser_initialize(p);
    return p;
}

static VALUE
rb_parser_s_new()
{
    struct parser_params *p = parser_new();

    return Data_Wrap_Struct(0, parser_mark, parser_free, p);
}
#endif

#ifdef RIPPER
#ifdef RIPPER_DEBUG
extern int rb_is_pointer_to_heap _((VALUE));

/* :nodoc: */
static VALUE
ripper_validate_object(self, x)
    VALUE self, x;
{
    if (x == Qfalse) return x;
    if (x == Qtrue) return x;
    if (x == Qnil) return x;
    if (x == Qundef)
        rb_raise(rb_eArgError, "Qundef given");
    if (FIXNUM_P(x)) return x;
    if (SYMBOL_P(x)) return x;
    if (!rb_is_pointer_to_heap(x))
        rb_raise(rb_eArgError, "invalid pointer: 0x%x", x);
    switch (TYPE(x)) {
      case T_STRING:
      case T_OBJECT:
      case T_ARRAY:
      case T_BIGNUM:
      case T_FLOAT:
        return x;
      case T_NODE:
        rb_raise(rb_eArgError, "NODE given: 0x%x", x);
      default:
        rb_raise(rb_eArgError, "wrong type of ruby object: 0x%x (%s)",
                 x, rb_obj_classname(x));
    }
    return x;
}
#endif

#define validate(x)

static VALUE
ripper_dispatch0(parser, mid)
    struct parser_params *parser;
    ID mid;
{
    return rb_funcall(parser->value, mid, 0);
}

static VALUE
ripper_dispatch1(parser, mid, a)
    struct parser_params *parser;
    ID mid;
    VALUE a;
{
    validate(a);
    return rb_funcall(parser->value, mid, 1, a);
}

static VALUE
ripper_dispatch2(parser, mid, a, b)
    struct parser_params *parser;
    ID mid;
    VALUE a, b;
{
    validate(a);
    validate(b);
    return rb_funcall(parser->value, mid, 2, a, b);
}

static VALUE
ripper_dispatch3(parser, mid, a, b, c)
    struct parser_params *parser;
    ID mid;
    VALUE a, b, c;
{
    validate(a);
    validate(b);
    validate(c);
    return rb_funcall(parser->value, mid, 3, a, b, c);
}

static VALUE
ripper_dispatch4(parser, mid, a, b, c, d)
    struct parser_params *parser;
    ID mid;
    VALUE a, b, c, d;
{
    validate(a);
    validate(b);
    validate(c);
    validate(d);
    return rb_funcall(parser->value, mid, 4, a, b, c, d);
}

static VALUE
ripper_dispatch5(parser, mid, a, b, c, d, e)
    struct parser_params *parser;
    ID mid;
    VALUE a, b, c, d, e;
{
    validate(a);
    validate(b);
    validate(c);
    validate(d);
    validate(e);
    return rb_funcall(parser->value, mid, 5, a, b, c, d, e);
}

static struct kw_assoc {
    ID id;
    const char *name;
} keyword_to_name[] = {
    {kCLASS,	"class"},
    {kMODULE,	"module"},
    {kDEF,	"def"},
    {kUNDEF,	"undef"},
    {kBEGIN,	"begin"},
    {kRESCUE,	"rescue"},
    {kENSURE,	"ensure"},
    {kEND,	"end"},
    {kIF,	"if"},
    {kUNLESS,	"unless"},
    {kTHEN,	"then"},
    {kELSIF,	"elsif"},
    {kELSE,	"else"},
    {kCASE,	"case"},
    {kWHEN,	"when"},
    {kWHILE,	"while"},
    {kUNTIL,	"until"},
    {kFOR,	"for"},
    {kBREAK,	"break"},
    {kNEXT,	"next"},
    {kREDO,	"redo"},
    {kRETRY,	"retry"},
    {kIN,	"in"},
    {kDO,	"do"},
    {kDO_COND,	"do"},
    {kDO_BLOCK,	"do"},
    {kRETURN,	"return"},
    {kYIELD,	"yield"},
    {kSUPER,	"super"},
    {kSELF,	"self"},
    {kNIL,	"nil"},
    {kTRUE,	"true"},
    {kFALSE,	"false"},
    {kAND,	"and"},
    {kOR,	"or"},
    {kNOT,	"not"},
    {kIF_MOD,	"if"},
    {kUNLESS_MOD,	"unless"},
    {kWHILE_MOD,	"while"},
    {kUNTIL_MOD,	"until"},
    {kRESCUE_MOD,	"rescue"},
    {kALIAS,	"alias"},
    {kDEFINED,	"defined"},
    {klBEGIN,	"BEGIN"},
    {klEND,	"END"},
    {k__LINE__,	"__LINE__"},
    {k__FILE__,	"__FILE__"},
    {0, NULL}
};

static const char*
keyword_id_to_str(id)
    ID id;
{
    struct kw_assoc *a;

    for (a = keyword_to_name; a->id; a++) {
        if (a->id == id)
            return a->name;
    }
    return NULL;
}

static VALUE
ripper_id2sym(id)
    ID id;
{
    const char *name;
    char buf[8];

    if (id <= 256) {
        buf[0] = id;
        buf[1] = '\0';
        return ID2SYM(rb_intern(buf));
    }
    if ((name = keyword_id_to_str(id))) {
        return ID2SYM(rb_intern(name));
    }
    switch (id) {
    case tOROP:
        name = "||";
        break;
    case tANDOP:
        name = "&&";
        break;
    default:
        name = rb_id2name(id);
        if (!name) {
            rb_bug("cannot convert ID to string: %ld", (unsigned long)id);
        }
        break;
    }
    return ID2SYM(rb_intern(name));
}

static VALUE
ripper_intern(s)
    const char *s;
{
    return ID2SYM(rb_intern(s));
}

#ifdef HAVE_STDARG_PROTOTYPES
# include <stdarg.h>
# define va_init_list(a,b) va_start(a,b)
#else
# include <varargs.h>
# define va_init_list(a,b) va_start(a)
#endif

static void
#ifdef HAVE_STDARG_PROTOTYPES
ripper_compile_error(struct parser_params *parser, const char *fmt, ...)
#else
ripper_compile_error(parser, fmt, va_alist)
    struct parser_params *parser;
    const char *fmt;
    va_dcl
#endif
{
    char buf[BUFSIZ];
    va_list args;

    va_init_list(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);
    rb_funcall(parser->value, rb_intern("compile_error"), 1, rb_str_new2(buf));
}

static void
ripper_warn0(parser, fmt)
    struct parser_params *parser;
    const char *fmt;
{
    rb_funcall(parser->value, rb_intern("warn"), 1, rb_str_new2(fmt));
}

static void
ripper_warnI(parser, fmt, a)
    struct parser_params *parser;
    const char *fmt;
    int a;
{
    rb_funcall(parser->value, rb_intern("warn"), 2,
               rb_str_new2(fmt), INT2NUM(a));
}

static void
ripper_warnS(parser, fmt, str)
    struct parser_params *parser;
    const char *fmt;
    const char *str;
{
    rb_funcall(parser->value, rb_intern("warn"), 2,
    	       rb_str_new2(fmt), rb_str_new2(str));
}

static void
ripper_warning0(parser, fmt)
    struct parser_params *parser;
    const char *fmt;
{
    rb_funcall(parser->value, rb_intern("warning"), 1, rb_str_new2(fmt));
}

static VALUE ripper_lex_get_generic _((struct parser_params *, VALUE));

static VALUE
ripper_lex_get_generic(parser, src)
    struct parser_params *parser;
    VALUE src;
{
    return rb_funcall(src, ripper_id_gets, 0);
}

static VALUE ripper_s_allocate _((VALUE));

static VALUE
ripper_s_allocate(klass)
    VALUE klass;
{
    struct parser_params *p;
    VALUE self;

    p = ALLOC_N(struct parser_params, 1);
    MEMZERO(p, struct parser_params, 1);
    self = Data_Wrap_Struct(klass, parser_mark, parser_free, p);
    p->value = self;
    return self;
}

static int
obj_respond_to(obj, mid)
    VALUE obj, mid;
{
    VALUE st;

    st = rb_funcall(obj, rb_intern("respond_to?"), 2, mid, Qfalse);
    return RTEST(st);
}

#define ripper_initialized_p(r) ((r)->parser_lex_input != 0)

/*
 *  call-seq:
 *    Ripper.new(src, filename="(ripper)", lineno=1) -> ripper
 *
 *  Create a new Ripper object.
 *  _src_ must be a String, a IO, or an Object which has #gets method.
 *
 *  This method does not starts parsing.
 *  See also Ripper#parse and Ripper.parse.
 */
static VALUE
ripper_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    struct parser_params *parser;
    VALUE src, fname, lineno;

    Data_Get_Struct(self, struct parser_params, parser);
    rb_scan_args(argc, argv, "12", &src, &fname, &lineno);
    if (obj_respond_to(src, ID2SYM(ripper_id_gets))) {
        parser->parser_lex_gets = ripper_lex_get_generic;
    }
    else {
        StringValue(src);
        parser->parser_lex_gets = lex_get_str;
    }
    parser->parser_lex_input = src;
    parser->eofp = Qfalse;
    if (NIL_P(fname)) {
        fname = rb_str_new2("(ripper)");
    }
    else {
        StringValue(fname);
    }
    parser_initialize(parser);
    parser->parser_ruby_sourcefile = fname;
    parser->parser_ruby_sourceline = NIL_P(lineno) ? 0 : NUM2INT(lineno) - 1;
    parser->parser_ruby__end__seen = 0;

    return Qnil;
}

/*
 *  call-seq:
 *    Ripper.yydebug   -> true or false
 *
 *  Get yydebug.
 */
static VALUE
ripper_s_get_yydebug(self)
    VALUE self;
{
    return ripper_yydebug ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    Ripper.yydebug = flag
 *
 *  Set yydebug.
 */
static VALUE
ripper_s_set_yydebug(self, flag)
    VALUE self, flag;
{
    ripper_yydebug = RTEST(flag);
    return flag;
}

extern VALUE rb_thread_pass _((void));

struct ripper_args {
    struct parser_params *parser;
    int argc;
    VALUE *argv;
};

static VALUE
ripper_parse0(parser_v)
    VALUE parser_v;
{
    struct parser_params *parser;

    Data_Get_Struct(parser_v, struct parser_params, parser);
    parser_prepare(parser);
    ripper_yyparse((void*)parser);
    return parser->result;
}

static VALUE
ripper_ensure(parser_v)
    VALUE parser_v;
{
    struct parser_params *parser;

    Data_Get_Struct(parser_v, struct parser_params, parser);
    parser->parsing_thread = Qnil;
    return Qnil;
}

/*
 *  call-seq:
 *    ripper#parse
 *
 *  Start parsing and returns the value of the root action.
 */
static VALUE
ripper_parse(self)
    VALUE self;
{
    struct parser_params *parser;

    Data_Get_Struct(self, struct parser_params, parser);
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
 *    ripper#column   -> Integer
 *
 *  Return column number of current parsing line.
 *  This number starts from 0.
 */
static VALUE
ripper_column(self)
    VALUE self;
{
    struct parser_params *parser;
    long col;

    Data_Get_Struct(self, struct parser_params, parser);
    if (!ripper_initialized_p(parser)) {
        rb_raise(rb_eArgError, "method called for uninitialized object");
    }
    if (NIL_P(parser->parsing_thread)) return Qnil;
    col = parser->tokp - parser->parser_lex_pbeg;
    return LONG2NUM(col);
}

/*
 *  call-seq:
 *    ripper#lineno   -> Integer
 *
 *  Return line number of current parsing line.
 *  This number starts from 1.
 */
static VALUE
ripper_lineno(self)
    VALUE self;
{
    struct parser_params *parser;

    Data_Get_Struct(self, struct parser_params, parser);
    if (!ripper_initialized_p(parser)) {
        rb_raise(rb_eArgError, "method called for uninitialized object");
    }
    if (NIL_P(parser->parsing_thread)) return Qnil;
    return INT2NUM(parser->parser_ruby_sourceline);
}

#ifdef RIPPER_DEBUG
/* :nodoc: */
static VALUE
ripper_assert_Qundef(self, obj, msg)
    VALUE self, obj, msg;
{
    StringValue(msg);
    if (obj == Qundef) {
        rb_raise(rb_eArgError, RSTRING(msg)->ptr);
    }
    return Qnil;
}

/* :nodoc: */
static VALUE
ripper_value(self, obj)
    VALUE self, obj;
{
    return ULONG2NUM(obj);
}
#endif

void
Init_ripper()
{
    VALUE Ripper;

    Ripper = rb_define_class("Ripper", rb_cObject);
    rb_define_const(Ripper, "Version", rb_str_new2(RIPPER_VERSION));
    rb_define_singleton_method(Ripper, "yydebug", ripper_s_get_yydebug, 0);
    rb_define_singleton_method(Ripper, "yydebug=", ripper_s_set_yydebug, 1);
    rb_define_alloc_func(Ripper, ripper_s_allocate);
    rb_define_method(Ripper, "initialize", ripper_initialize, -1);
    rb_define_method(Ripper, "parse", ripper_parse, 0);
    rb_define_method(Ripper, "column", ripper_column, 0);
    rb_define_method(Ripper, "lineno", ripper_lineno, 0);
#ifdef RIPPER_DEBUG
    rb_define_method(rb_mKernel, "assert_Qundef", ripper_assert_Qundef, 2);
    rb_define_method(rb_mKernel, "rawVALUE", ripper_value, 1);
    rb_define_method(rb_mKernel, "validate_object", ripper_validate_object, 1);
#endif

    ripper_id_gets = rb_intern("gets");
    ripper_init_eventids1();
    ripper_init_eventids2();
    /* ensure existing in symbol table */
    rb_intern("||");
    rb_intern("&&");
}
#endif /* RIPPER */
