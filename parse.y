/**********************************************************************

  parse.y -

  $Author$
  $Date$
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

%{

#define YYDEBUG 1
#define YYERROR_VERBOSE 1
#ifndef YYSTACK_USE_ALLOCA
#define YYSTACK_USE_ALLOCA 0
#endif

#include "ruby.h"
#include "env.h"
#include "intern.h"
#include "node.h"
#include "st.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>

#define YYMALLOC	rb_parser_malloc
#define YYREALLOC	rb_parser_realloc
#define YYCALLOC	rb_parser_calloc
#define YYFREE 	rb_parser_free
#define malloc	YYMALLOC
#define realloc	YYREALLOC
#define calloc	YYCALLOC
#define free	YYFREE
static void *rb_parser_malloc _((size_t));
static void *rb_parser_realloc _((void *, size_t));
static void *rb_parser_calloc _((size_t, size_t));
static void rb_parser_free _((void *));

#define yyparse ruby_yyparse
#define yylex ruby_yylex
#define yyerror ruby_yyerror
#define yylval ruby_yylval
#define yychar ruby_yychar
#define yydebug ruby_yydebug

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

NODE *ruby_eval_tree_begin = 0;
NODE *ruby_eval_tree = 0;

char *ruby_sourcefile;		/* current source file */
int   ruby_sourceline;		/* current line no. */

static int yylex();
static int yyerror();

static enum lex_state {
    EXPR_BEG,			/* ignore newline, +/- is a sign. */
    EXPR_END,			/* newline significant, +/- is an operator. */
    EXPR_ARG,			/* newline significant, +/- is an operator. */
    EXPR_CMDARG,		/* newline significant, +/- is an operator. */
    EXPR_ENDARG,		/* newline significant, +/- is an operator. */
    EXPR_MID,			/* newline significant, +/- is an operator. */
    EXPR_FNAME,			/* ignore newline, no reserved words. */
    EXPR_DOT,			/* right after `.' or `::', no reserved words. */
    EXPR_CLASS,			/* immediate after `class', no here document. */
    EXPR_VALUE			/* alike EXPR_BEG but label is disallowed. */
} lex_state;
static NODE *lex_strterm;

#ifdef HAVE_LONG_LONG
typedef unsigned LONG_LONG stack_type;
#else
typedef unsigned long stack_type;
#endif

#define BITSTACK_PUSH(stack, n)	(stack = (stack<<1)|((n)&1))
#define BITSTACK_POP(stack)	(stack >>= 1)
#define BITSTACK_LEXPOP(stack)	(stack = (stack >> 1) | (stack & 1))
#define BITSTACK_SET_P(stack)	(stack&1)

static stack_type cond_stack = 0;
#define COND_PUSH(n)	BITSTACK_PUSH(cond_stack, n)
#define COND_POP()	BITSTACK_POP(cond_stack)
#define COND_LEXPOP()	BITSTACK_LEXPOP(cond_stack)
#define COND_P()	BITSTACK_SET_P(cond_stack)

static stack_type cmdarg_stack = 0;
#define CMDARG_PUSH(n)	BITSTACK_PUSH(cmdarg_stack, n)
#define CMDARG_POP()	BITSTACK_POP(cmdarg_stack)
#define CMDARG_LEXPOP()	BITSTACK_LEXPOP(cmdarg_stack)
#define CMDARG_P()	BITSTACK_SET_P(cmdarg_stack)

static int class_nest = 0;
static int in_single = 0;
static int in_def = 0;
static int compile_for_eval = 0;
static ID cur_mid = 0;
static int command_start = Qtrue;

static NODE *deferred_nodes;

static NODE *cond();
static NODE *logop();
static int cond_negative();

static NODE *newline_node();
static void fixpos();

static int value_expr0();
static void void_expr0();
static void void_stmts();
static NODE *remove_begin();
#define value_expr(node) value_expr0((node) = remove_begin(node))
#define void_expr(node) void_expr0((node) = remove_begin(node))

static NODE *block_append();
static NODE *list_append();
static NODE *list_concat();
static NODE *arg_concat();
static NODE *literal_concat();
static NODE *new_evstr();
static NODE *evstr2dstr();
static NODE *call_op();
static int in_defined = 0;

static NODE *negate_lit();
static NODE *ret_args();
static NODE *arg_blk_pass();
static NODE *new_call();
static NODE *new_fcall();
static NODE *new_super();
static NODE *new_yield();

static NODE *gettable();
static NODE *assignable();
static NODE *aryset();
static NODE *attrset();
static void rb_backref_error();
static NODE *node_assign();

static NODE *match_gen();
static void local_push();
static void local_pop();
static int  local_append();
static int  local_cnt();
static int  local_id();
static ID  *local_tbl();
static ID   internal_id();

static struct RVarmap *dyna_push();
static void dyna_pop();
static int dyna_in_block();
static NODE *dyna_init();

static void top_local_init();
static void top_local_setup();

static void fixup_nodes();

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
#define nd_nest u3.id

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

%union {
    NODE *node;
    ID id;
    int num;
    struct RVarmap *vars;
}

%token  kCLASS
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
%type <node> f_arglist f_args f_optarg f_opt f_rest_arg f_block_arg opt_f_block_arg
%type <node> assoc_list assocs assoc undef_list backref string_dvar
%type <node> for_var block_var opt_block_var block_par
%type <node> brace_block cmd_brace_block do_block lhs none fitem
%type <node> mlhs mlhs_head mlhs_basic mlhs_entry mlhs_item mlhs_node
%type <id>   fsym variable sym symbol operation operation2 operation3
%type <id>   cname fname op
%type <num>  f_norm_arg f_arg
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
			lex_state = EXPR_BEG;
                        top_local_init();
			if (ruby_class == rb_cObject) class_nest = 0;
			else class_nest = 1;
		    }
		  compstmt
		    {
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
		    }
		;

bodystmt	: compstmt
		  opt_rescue
		  opt_else
		  opt_ensure
		    {
		        $$ = $1;
			if ($2) {
			    $$ = NEW_RESCUE($1, $2, $3);
			}
			else if ($3) {
			    rb_warn("else without rescue is useless");
			    $$ = block_append($$, $3);
			}
			if ($4) {
			    $$ = NEW_ENSURE($$, $4);
			}
			fixpos($$, $1);
		    }
		;

compstmt	: stmts opt_terms
		    {
			void_stmts($1);
			fixup_nodes(&deferred_nodes);
		        $$ = $1;
		    }
		;

stmts		: none
		| stmt
		    {
			$$ = newline_node($1);
		    }
		| stmts terms stmt
		    {
			$$ = block_append($1, newline_node($3));
		    }
		| error stmt
		    {
			$$ = remove_begin($2);
		    }
		;

stmt		: kALIAS fitem {lex_state = EXPR_FNAME;} fitem
		    {
		        $$ = NEW_ALIAS($2, $4);
		    }
		| kALIAS tGVAR tGVAR
		    {
		        $$ = NEW_VALIAS($2, $3);
		    }
		| kALIAS tGVAR tBACK_REF
		    {
			char buf[3];

			sprintf(buf, "$%c", (char)$3->nd_nth);
		        $$ = NEW_VALIAS($2, rb_intern(buf));
		    }
		| kALIAS tGVAR tNTH_REF
		    {
		        yyerror("can't make alias for the number variables");
		        $$ = 0;
		    }
		| kUNDEF undef_list
		    {
			$$ = $2;
		    }
		| stmt kIF_MOD expr_value
		    {
			$$ = NEW_IF(cond($3), remove_begin($1), 0);
		        fixpos($$, $3);
			if (cond_negative(&$$->nd_cond)) {
		            $$->nd_else = $$->nd_body;
		            $$->nd_body = 0;
			}
		    }
		| stmt kUNLESS_MOD expr_value
		    {
			$$ = NEW_UNLESS(cond($3), remove_begin($1), 0);
		        fixpos($$, $3);
			if (cond_negative(&$$->nd_cond)) {
		            $$->nd_body = $$->nd_else;
		            $$->nd_else = 0;
			}
		    }
		| stmt kWHILE_MOD expr_value
		    {
			if ($1 && nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_WHILE(cond($3), $1->nd_body, 0);
			}
			else {
			    $$ = NEW_WHILE(cond($3), $1, 1);
			}
			if (cond_negative(&$$->nd_cond)) {
			    nd_set_type($$, NODE_UNTIL);
			}
		    }
		| stmt kUNTIL_MOD expr_value
		    {
			if ($1 && nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_UNTIL(cond($3), $1->nd_body, 0);
			}
			else {
			    $$ = NEW_UNTIL(cond($3), $1, 1);
			}
			if (cond_negative(&$$->nd_cond)) {
			    nd_set_type($$, NODE_WHILE);
			}
		    }
		| stmt kRESCUE_MOD stmt
		    {
			NODE *resq = NEW_RESBODY(0, remove_begin($3), 0);
			$$ = NEW_RESCUE(remove_begin($1), resq, 0);
		    }
		| klBEGIN
		    {
			if (in_def || in_single) {
			    yyerror("BEGIN in method");
			}
			local_push(0);
		    }
		  '{' compstmt '}'
		    {
			ruby_eval_tree_begin = block_append(ruby_eval_tree_begin,
						            NEW_PREEXE($4));
		        local_pop();
		        $$ = 0;
		    }
		| klEND '{' compstmt '}'
		    {
			if (in_def || in_single) {
			    rb_warn("END in method; use at_exit");
			}

			$$ = NEW_ITER(0, NEW_POSTEXE(), $3);
		    }
		| lhs '=' command_call
		    {
			$$ = node_assign($1, $3);
		    }
		| mlhs '=' command_call
		    {
			value_expr($3);
			$1->nd_value = ($1->nd_head) ? NEW_TO_ARY($3) : NEW_ARRAY($3);
			$$ = $1;
		    }
		| var_lhs tOP_ASGN command_call
		    {
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
		    }
		| primary_value '[' aref_args ']' tOP_ASGN command_call
		    {
                        NODE *args;

			value_expr($6);
			if (!$3) $3 = NEW_ZARRAY();
			args = arg_concat($6, $3);
			if ($5 == tOROP) {
			    $5 = 0;
			}
			else if ($5 == tANDOP) {
			    $5 = 1;
			}
			$$ = NEW_OP_ASGN1($1, $5, args);
		        fixpos($$, $1);
		    }
		| primary_value '.' tIDENTIFIER tOP_ASGN command_call
		    {
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| primary_value '.' tCONSTANT tOP_ASGN command_call
		    {
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| primary_value tCOLON2 tIDENTIFIER tOP_ASGN command_call
		    {
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| backref tOP_ASGN command_call
		    {
		        rb_backref_error($1);
			$$ = 0;
		    }
		| lhs '=' mrhs
		    {
			$$ = node_assign($1, NEW_SVALUE($3));
		    }
		| mlhs '=' arg_value
		    {
			$1->nd_value = ($1->nd_head) ? NEW_TO_ARY($3) : NEW_ARRAY($3);
			$$ = $1;
		    }
		| mlhs '=' mrhs
		    {
			$1->nd_value = $3;
			$$ = $1;
		    }
		| expr
		;

expr		: command_call
		| expr kAND expr
		    {
			$$ = logop(NODE_AND, $1, $3);
		    }
		| expr kOR expr
		    {
			$$ = logop(NODE_OR, $1, $3);
		    }
		| kNOT expr
		    {
			$$ = NEW_NOT(cond($2));
		    }
		| '!' command_call
		    {
			$$ = NEW_NOT(cond($2));
		    }
		| arg
		;

expr_value	: expr
		    {
			value_expr($$);
			$$ = $1;
		    }
		;

command_call	: command
		| block_command
		| kRETURN call_args
		    {
			$$ = NEW_RETURN(ret_args($2));
		    }
		| kBREAK call_args
		    {
			$$ = NEW_BREAK(ret_args($2));
		    }
		| kNEXT call_args
		    {
			$$ = NEW_NEXT(ret_args($2));
		    }
		;

block_command	: block_call
		| block_call '.' operation2 command_args
		    {
			$$ = new_call($1, $3, $4);
		    }
		| block_call tCOLON2 operation2 command_args
		    {
			$$ = new_call($1, $3, $4);
		    }
		;

cmd_brace_block	: tLBRACE_ARG
		    {
			$<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    }
		  opt_block_var {$<vars>$ = ruby_dyna_vars;}
		  compstmt
		  '}'
		    {
			$$ = NEW_ITER($3, 0, dyna_init($5, $<vars>4));
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    }
		;

command		: operation command_args       %prec tLOWEST
		    {
			$$ = new_fcall($1, $2);
		        fixpos($$, $2);
		   }
		| operation command_args cmd_brace_block
		    {
			$$ = new_fcall($1, $2);
			if ($3) {
			    if (nd_type($$) == NODE_BLOCK_PASS) {
				rb_compile_error("both block arg and actual block given");
			    }
			    $3->nd_iter = $$;
			    $$ = $3;
			}
		        fixpos($$, $2);
		   }
		| primary_value '.' operation2 command_args	%prec tLOWEST
		    {
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    }
		| primary_value '.' operation2 command_args cmd_brace_block
		    {
			$$ = new_call($1, $3, $4);
			if ($5) {
			    if (nd_type($$) == NODE_BLOCK_PASS) {
				rb_compile_error("both block arg and actual block given");
			    }
			    $5->nd_iter = $$;
			    $$ = $5;
			}
		        fixpos($$, $1);
		   }
		| primary_value tCOLON2 operation2 command_args	%prec tLOWEST
		    {
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    }
		| primary_value tCOLON2 operation2 command_args cmd_brace_block
		    {
			$$ = new_call($1, $3, $4);
			if ($5) {
			    if (nd_type($$) == NODE_BLOCK_PASS) {
				rb_compile_error("both block arg and actual block given");
			    }
			    $5->nd_iter = $$;
			    $$ = $5;
			}
		        fixpos($$, $1);
		   }
		| kSUPER command_args
		    {
			$$ = new_super($2);
		        fixpos($$, $2);
		    }
		| kYIELD command_args
		    {
			$$ = new_yield($2);
		        fixpos($$, $2);
		    }
		;

mlhs		: mlhs_basic
		| tLPAREN mlhs_entry ')'
		    {
			$$ = $2;
		    }
		;

mlhs_entry	: mlhs_basic
		| tLPAREN mlhs_entry ')'
		    {
			$$ = NEW_MASGN(NEW_LIST($2), 0);
		    }
		;

mlhs_basic	: mlhs_head
		    {
			$$ = NEW_MASGN($1, 0);
		    }
		| mlhs_head mlhs_item
		    {
			$$ = NEW_MASGN(list_append($1,$2), 0);
		    }
		| mlhs_head tSTAR mlhs_node
		    {
			$$ = NEW_MASGN($1, $3);
		    }
		| mlhs_head tSTAR
		    {
			$$ = NEW_MASGN($1, -1);
		    }
		| tSTAR mlhs_node
		    {
			$$ = NEW_MASGN(0, $2);
		    }
		| tSTAR
		    {
			$$ = NEW_MASGN(0, -1);
		    }
		;

mlhs_item	: mlhs_node
		| tLPAREN mlhs_entry ')'
		    {
			$$ = $2;
		    }
		;

mlhs_head	: mlhs_item ','
		    {
			$$ = NEW_LIST($1);
		    }
		| mlhs_head mlhs_item ','
		    {
			$$ = list_append($1, $2);
		    }
		;

mlhs_node	: variable
		    {
			$$ = assignable($1, 0);
		    }
		| primary_value '[' aref_args ']'
		    {
			$$ = aryset($1, $3);
		    }
		| primary_value '.' tIDENTIFIER
		    {
			$$ = attrset($1, $3);
		    }
		| primary_value tCOLON2 tIDENTIFIER
		    {
			$$ = attrset($1, $3);
		    }
		| primary_value '.' tCONSTANT
		    {
			$$ = attrset($1, $3);
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = NEW_CDECL(0, 0, NEW_COLON2($1, $3));
		    }
		| tCOLON3 tCONSTANT
		    {
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = NEW_CDECL(0, 0, NEW_COLON3($2));
		    }
		| backref
		    {
		        rb_backref_error($1);
			$$ = 0;
		    }
		;

lhs		: variable
		    {
			$$ = assignable($1, 0);
		    }
		| primary_value '[' aref_args ']'
		    {
			$$ = aryset($1, $3);
		    }
		| primary_value '.' tIDENTIFIER
		    {
			$$ = attrset($1, $3);
		    }
		| primary_value tCOLON2 tIDENTIFIER
		    {
			$$ = attrset($1, $3);
		    }
		| primary_value '.' tCONSTANT
		    {
			$$ = attrset($1, $3);
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = NEW_CDECL(0, 0, NEW_COLON2($1, $3));
		    }
		| tCOLON3 tCONSTANT
		    {
			if (in_def || in_single)
			    yyerror("dynamic constant assignment");
			$$ = NEW_CDECL(0, 0, NEW_COLON3($2));
		    }
		| backref
		    {
		        rb_backref_error($1);
			$$ = 0;
		    }
		;

cname		: tIDENTIFIER
		    {
			yyerror("class/module name must be CONSTANT");
		    }
		| tCONSTANT
		;

cpath		: tCOLON3 cname
		    {
			$$ = NEW_COLON3($2);
		    }
		| cname
		    {
			$$ = NEW_COLON2(0, $$);
		    }
		| primary_value tCOLON2 cname
		    {
			$$ = NEW_COLON2($1, $3);
		    }
		;

fname		: tIDENTIFIER
		| tCONSTANT
		| tFID
		| op
		    {
			lex_state = EXPR_END;
			$$ = $1;
		    }
		| reswords
		    {
			lex_state = EXPR_END;
			$$ = $<id>1;
		    }
		;

fsym		: fname
		| symbol
		;

fitem		: fsym
		    {
			$$ = NEW_LIT(ID2SYM($1));
		    }
		| dsym
		;

undef_list	: fitem
		    {
			$$ = NEW_UNDEF($1);
		    }
		| undef_list ',' {lex_state = EXPR_FNAME;} fitem
		    {
			$$ = block_append($1, NEW_UNDEF($4));
		    }
		;

op		: '|'		{ $$ = '|'; }
		| '^'		{ $$ = '^'; }
		| '&'		{ $$ = '&'; }
		| tCMP		{ $$ = tCMP; }
		| tEQ		{ $$ = tEQ; }
		| tEQQ		{ $$ = tEQQ; }
		| tMATCH	{ $$ = tMATCH; }
		| '>'		{ $$ = '>'; }
		| tGEQ		{ $$ = tGEQ; }
		| '<'		{ $$ = '<'; }
		| tLEQ		{ $$ = tLEQ; }
		| tLSHFT	{ $$ = tLSHFT; }
		| tRSHFT	{ $$ = tRSHFT; }
		| '+'		{ $$ = '+'; }
		| '-'		{ $$ = '-'; }
		| '*'		{ $$ = '*'; }
		| tSTAR		{ $$ = '*'; }
		| '/'		{ $$ = '/'; }
		| '%'		{ $$ = '%'; }
		| tPOW		{ $$ = tPOW; }
		| '~'		{ $$ = '~'; }
		| tUPLUS	{ $$ = tUPLUS; }
		| tUMINUS	{ $$ = tUMINUS; }
		| tAREF		{ $$ = tAREF; }
		| tASET		{ $$ = tASET; }
		| '`'		{ $$ = '`'; }
		;

reswords	: k__LINE__ | k__FILE__  | klBEGIN | klEND
		| kALIAS | kAND | kBEGIN | kBREAK | kCASE | kCLASS | kDEF
		| kDEFINED | kDO | kELSE | kELSIF | kEND | kENSURE | kFALSE
		| kFOR | kIN | kMODULE | kNEXT | kNIL | kNOT
		| kOR | kREDO | kRESCUE | kRETRY | kRETURN | kSELF | kSUPER
		| kTHEN | kTRUE | kUNDEF | kWHEN | kYIELD
		| kIF | kUNLESS | kWHILE | kUNTIL
		;

arg		: lhs '=' arg
		    {
			$$ = node_assign($1, $3);
		    }
		| lhs '=' arg kRESCUE_MOD arg
		    {
			$$ = node_assign($1, NEW_RESCUE($3, NEW_RESBODY(0,$5,0), 0));
		    }
		| var_lhs tOP_ASGN arg
		    {
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
		    }
		| primary_value '[' aref_args ']' tOP_ASGN arg
		    {
                        NODE *args;

			value_expr($6);
			if (!$3) $3 = NEW_ZARRAY();
			args = arg_concat($6, $3);
			if ($5 == tOROP) {
			    $5 = 0;
			}
			else if ($5 == tANDOP) {
			    $5 = 1;
			}
			$$ = NEW_OP_ASGN1($1, $5, args);
		        fixpos($$, $1);
		    }
		| primary_value '.' tIDENTIFIER tOP_ASGN arg
		    {
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| primary_value '.' tCONSTANT tOP_ASGN arg
		    {
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| primary_value tCOLON2 tIDENTIFIER tOP_ASGN arg
		    {
			value_expr($5);
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| primary_value tCOLON2 tCONSTANT tOP_ASGN arg
		    {
			yyerror("constant re-assignment");
			$$ = 0;
		    }
		| tCOLON3 tCONSTANT tOP_ASGN arg
		    {
			yyerror("constant re-assignment");
			$$ = 0;
		    }
		| backref tOP_ASGN arg
		    {
		        rb_backref_error($1);
			$$ = 0;
		    }
		| arg tDOT2 arg
		    {
			value_expr($1);
			value_expr($3);
			$$ = NEW_DOT2($1, $3);
			if (nd_type($1) == NODE_LIT && FIXNUM_P($1->nd_lit) &&
			    nd_type($3) == NODE_LIT && FIXNUM_P($3->nd_lit)) {
			    deferred_nodes = list_append(deferred_nodes, $$);
			}
		    }
		| arg tDOT3 arg
		    {
			value_expr($1);
			value_expr($3);
			$$ = NEW_DOT3($1, $3);
			if (nd_type($1) == NODE_LIT && FIXNUM_P($1->nd_lit) &&
			    nd_type($3) == NODE_LIT && FIXNUM_P($3->nd_lit)) {
			    deferred_nodes = list_append(deferred_nodes, $$);
			}
		    }
		| arg '+' arg
		    {
			$$ = call_op($1, '+', 1, $3);
		    }
		| arg '-' arg
		    {
		        $$ = call_op($1, '-', 1, $3);
		    }
		| arg '*' arg
		    {
		        $$ = call_op($1, '*', 1, $3);
		    }
		| arg '/' arg
		    {
			$$ = call_op($1, '/', 1, $3);
		    }
		| arg '%' arg
		    {
			$$ = call_op($1, '%', 1, $3);
		    }
		| arg tPOW arg
		    {
			$$ = call_op($1, tPOW, 1, $3);
		    }
		| tUMINUS_NUM tINTEGER tPOW arg
		    {
			$$ = call_op(call_op($2, tPOW, 1, $4), tUMINUS, 0, 0);
		    }
		| tUMINUS_NUM tFLOAT tPOW arg
		    {
			$$ = call_op(call_op($2, tPOW, 1, $4), tUMINUS, 0, 0);
		    }
		| tUPLUS arg
		    {
			if ($2 && nd_type($2) == NODE_LIT) {
			    $$ = $2;
			}
			else {
			    $$ = call_op($2, tUPLUS, 0, 0);
			}
		    }
		| tUMINUS arg
		    {
			$$ = call_op($2, tUMINUS, 0, 0);
		    }
		| arg '|' arg
		    {
		        $$ = call_op($1, '|', 1, $3);
		    }
		| arg '^' arg
		    {
			$$ = call_op($1, '^', 1, $3);
		    }
		| arg '&' arg
		    {
			$$ = call_op($1, '&', 1, $3);
		    }
		| arg tCMP arg
		    {
			$$ = call_op($1, tCMP, 1, $3);
		    }
		| arg '>' arg
		    {
			$$ = call_op($1, '>', 1, $3);
		    }
		| arg tGEQ arg
		    {
			$$ = call_op($1, tGEQ, 1, $3);
		    }
		| arg '<' arg
		    {
			$$ = call_op($1, '<', 1, $3);
		    }
		| arg tLEQ arg
		    {
			$$ = call_op($1, tLEQ, 1, $3);
		    }
		| arg tEQ arg
		    {
			$$ = call_op($1, tEQ, 1, $3);
		    }
		| arg tEQQ arg
		    {
			$$ = call_op($1, tEQQ, 1, $3);
		    }
		| arg tNEQ arg
		    {
			$$ = NEW_NOT(call_op($1, tEQ, 1, $3));
		    }
		| arg tMATCH arg
		    {
			$$ = match_gen($1, $3);
		    }
		| arg tNMATCH arg
		    {
			$$ = NEW_NOT(match_gen($1, $3));
		    }
		| '!' arg
		    {
			$$ = NEW_NOT(cond($2));
		    }
		| '~' arg
		    {
			$$ = call_op($2, '~', 0, 0);
		    }
		| arg tLSHFT arg
		    {
			$$ = call_op($1, tLSHFT, 1, $3);
		    }
		| arg tRSHFT arg
		    {
			$$ = call_op($1, tRSHFT, 1, $3);
		    }
		| arg tANDOP arg
		    {
			$$ = logop(NODE_AND, $1, $3);
		    }
		| arg tOROP arg
		    {
			$$ = logop(NODE_OR, $1, $3);
		    }
		| kDEFINED opt_nl {in_defined = 1;} arg
		    {
		        in_defined = 0;
			$$ = NEW_DEFINED($4);
		    }
		| arg '?' arg ':' arg
		    {
			$$ = NEW_IF(cond($1), $3, $5);
		        fixpos($$, $1);
		    }
		| primary
		    {
			$$ = $1;
		    }
		;

arg_value	: arg
		    {
			value_expr($1);
			$$ = $1;
		    }
		;

aref_args	: none
		| command opt_nl
		    {
			$$ = NEW_LIST($1);
		    }
		| args trailer
		    {
			$$ = $1;
		    }
		| args ',' tSTAR arg opt_nl
		    {
			value_expr($4);
			$$ = arg_concat($1, $4);
		    }
		| assocs trailer
		    {
			$$ = NEW_LIST(NEW_HASH($1));
		    }
		| tSTAR arg opt_nl
		    {
			value_expr($2);
			$$ = NEW_NEWLINE(NEW_SPLAT($2));
		    }
		;

paren_args	: '(' none ')'
		    {
			$$ = $2;
		    }
		| '(' call_args opt_nl ')'
		    {
			$$ = $2;
		    }
		| '(' block_call opt_nl ')'
		    {
			$$ = NEW_LIST($2);
		    }
		| '(' args ',' block_call opt_nl ')'
		    {
			$$ = list_append($2, $4);
		    }
		;

opt_paren_args	: none
		| paren_args
		;

call_args	: command
		    {
			$$ = NEW_LIST($1);
		    }
		| args opt_block_arg
		    {
			$$ = arg_blk_pass($1, $2);
		    }
		| args ',' tSTAR arg_value opt_block_arg
		    {
			$$ = arg_concat($1, $4);
			$$ = arg_blk_pass($$, $5);
		    }
		| assocs opt_block_arg
		    {
			$$ = NEW_LIST(NEW_HASH($1));
			$$ = arg_blk_pass($$, $2);
		    }
		| assocs ',' tSTAR arg_value opt_block_arg
		    {
			$$ = arg_concat(NEW_LIST(NEW_HASH($1)), $4);
			$$ = arg_blk_pass($$, $5);
		    }
		| args ',' assocs opt_block_arg
		    {
			$$ = list_append($1, NEW_HASH($3));
			$$ = arg_blk_pass($$, $4);
		    }
		| args ',' assocs ',' tSTAR arg opt_block_arg
		    {
			value_expr($6);
			$$ = arg_concat(list_append($1, NEW_HASH($3)), $6);
			$$ = arg_blk_pass($$, $7);
		    }
		| tSTAR arg_value opt_block_arg
		    {
			$$ = arg_blk_pass(NEW_SPLAT($2), $3);
		    }
		| block_arg
		;

call_args2	: arg_value ',' args opt_block_arg
		    {
			$$ = arg_blk_pass(list_concat(NEW_LIST($1),$3), $4);
		    }
		| arg_value ',' block_arg
		    {
                        $$ = arg_blk_pass($1, $3);
                    }
		| arg_value ',' tSTAR arg_value opt_block_arg
		    {
			$$ = arg_concat(NEW_LIST($1), $4);
			$$ = arg_blk_pass($$, $5);
		    }
		| arg_value ',' args ',' tSTAR arg_value opt_block_arg
		    {
                       $$ = arg_concat(list_concat(NEW_LIST($1),$3), $6);
			$$ = arg_blk_pass($$, $7);
		    }
		| assocs opt_block_arg
		    {
			$$ = NEW_LIST(NEW_HASH($1));
			$$ = arg_blk_pass($$, $2);
		    }
		| assocs ',' tSTAR arg_value opt_block_arg
		    {
			$$ = arg_concat(NEW_LIST(NEW_HASH($1)), $4);
			$$ = arg_blk_pass($$, $5);
		    }
		| arg_value ',' assocs opt_block_arg
		    {
			$$ = list_append(NEW_LIST($1), NEW_HASH($3));
			$$ = arg_blk_pass($$, $4);
		    }
		| arg_value ',' args ',' assocs opt_block_arg
		    {
			$$ = list_append(list_concat(NEW_LIST($1),$3), NEW_HASH($5));
			$$ = arg_blk_pass($$, $6);
		    }
		| arg_value ',' assocs ',' tSTAR arg_value opt_block_arg
		    {
			$$ = arg_concat(list_append(NEW_LIST($1), NEW_HASH($3)), $6);
			$$ = arg_blk_pass($$, $7);
		    }
		| arg_value ',' args ',' assocs ',' tSTAR arg_value opt_block_arg
		    {
			$$ = arg_concat(list_append(list_concat(NEW_LIST($1), $3), NEW_HASH($5)), $8);
			$$ = arg_blk_pass($$, $9);
		    }
		| tSTAR arg_value opt_block_arg
		    {
			$$ = arg_blk_pass(NEW_SPLAT($2), $3);
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
		| tLPAREN_ARG  {lex_state = EXPR_ENDARG;} ')'
		    {
		        rb_warn("don't put space before argument parentheses");
			$$ = 0;
		    }
		| tLPAREN_ARG call_args2 {lex_state = EXPR_ENDARG;} ')'
		    {
		        rb_warn("don't put space before argument parentheses");
			$$ = $2;
		    }
		;

block_arg	: tAMPER arg_value
		    {
			$$ = NEW_BLOCK_PASS($2);
		    }
		;

opt_block_arg	: ',' block_arg
		    {
			$$ = $2;
		    }
		| ','
		    {
			$$ = 0;
		    }
		| none
		;

args 		: arg_value
		    {
			$$ = NEW_LIST($1);
		    }
		| args ',' arg_value
		    {
			$$ = list_append($1, $3);
		    }
		;

mrhs		: args ',' arg_value
		    {
			$$ = list_append($1, $3);
		    }
		| args ',' tSTAR arg_value
		    {
			$$ = arg_concat($1, $4);
		    }
		| tSTAR arg_value
		    {
			$$ = NEW_SPLAT($2);
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
			$$ = NEW_FCALL($1, 0);
		    }
		| kBEGIN
		    {
			$<num>1 = ruby_sourceline;
		    }
		  bodystmt
		  kEND
		    {
			if ($3 == NULL)
			    $$ = NEW_NIL();
			else
			    $$ = NEW_BEGIN($3);
			nd_set_line($$, $<num>1);
		    }
		| tLPAREN_ARG expr {lex_state = EXPR_ENDARG;} opt_nl ')'
		    {
		        rb_warning("(...) interpreted as grouped expression");
			$$ = $2;
		    }
		| tLPAREN compstmt ')'
		    {
			if (!$2) $$ = NEW_NIL();
			else $$ = $2;
		    }
		| primary_value tCOLON2 tCONSTANT
		    {
			$$ = NEW_COLON2($1, $3);
		    }
		| tCOLON3 tCONSTANT
		    {
			$$ = NEW_COLON3($2);
		    }
		| primary_value '[' aref_args ']'
		    {
			if ($1 && nd_type($1) == NODE_SELF)
			    $$ = NEW_FCALL(tAREF, $3);
			else
			    $$ = NEW_CALL($1, tAREF, $3);
			fixpos($$, $1);
		    }
		| tLBRACK aref_args ']'
		    {
		        if ($2 == 0) {
			    $$ = NEW_ZARRAY(); /* zero length array*/
			}
			else {
			    $$ = $2;
			}
		    }
		| tLBRACE assoc_list '}'
		    {
			$$ = NEW_HASH($2);
		    }
		| kRETURN
		    {
			$$ = NEW_RETURN(0);
		    }
		| kYIELD '(' call_args ')'
		    {
			$$ = new_yield($3);
		    }
		| kYIELD '(' ')'
		    {
			$$ = NEW_YIELD(0, Qfalse);
		    }
		| kYIELD
		    {
			$$ = NEW_YIELD(0, Qfalse);
		    }
		| kDEFINED opt_nl '(' {in_defined = 1;} expr ')'
		    {
		        in_defined = 0;
			$$ = NEW_DEFINED($5);
		    }
		| operation brace_block
		    {
			$2->nd_iter = NEW_FCALL($1, 0);
			$$ = $2;
			fixpos($2->nd_iter, $2);
		    }
		| method_call
		| method_call brace_block
		    {
			if ($1 && nd_type($1) == NODE_BLOCK_PASS) {
			    rb_compile_error("both block arg and actual block given");
			}
			$2->nd_iter = $1;
			$$ = $2;
		        fixpos($$, $1);
		    }
		| kIF expr_value then
		  compstmt
		  if_tail
		  kEND
		    {
			$$ = NEW_IF(cond($2), $4, $5);
		        fixpos($$, $2);
			if (cond_negative(&$$->nd_cond)) {
		            NODE *tmp = $$->nd_body;
		            $$->nd_body = $$->nd_else;
		            $$->nd_else = tmp;
			}
		    }
		| kUNLESS expr_value then
		  compstmt
		  opt_else
		  kEND
		    {
			$$ = NEW_UNLESS(cond($2), $4, $5);
		        fixpos($$, $2);
			if (cond_negative(&$$->nd_cond)) {
		            NODE *tmp = $$->nd_body;
		            $$->nd_body = $$->nd_else;
		            $$->nd_else = tmp;
			}
		    }
		| kWHILE {COND_PUSH(1);} expr_value do {COND_POP();}
		  compstmt
		  kEND
		    {
			$$ = NEW_WHILE(cond($3), $6, 1);
		        fixpos($$, $3);
			if (cond_negative(&$$->nd_cond)) {
			    nd_set_type($$, NODE_UNTIL);
			}
		    }
		| kUNTIL {COND_PUSH(1);} expr_value do {COND_POP();}
		  compstmt
		  kEND
		    {
			$$ = NEW_UNTIL(cond($3), $6, 1);
		        fixpos($$, $3);
			if (cond_negative(&$$->nd_cond)) {
			    nd_set_type($$, NODE_WHILE);
			}
		    }
		| kCASE expr_value opt_terms
		  case_body
		  kEND
		    {
			$$ = NEW_CASE($2, $4);
		        fixpos($$, $2);
		    }
		| kCASE opt_terms case_body kEND
		    {
			$$ = $3;
		    }
		| kCASE opt_terms kELSE compstmt kEND
		    {
			$$ = $4;
		    }
		| kFOR for_var kIN {COND_PUSH(1);} expr_value do {COND_POP();}
		  compstmt
		  kEND
		    {
			$$ = NEW_FOR($2, $5, $8);
		        fixpos($$, $2);
		    }
		| kCLASS cpath superclass
		    {
			if (in_def || in_single)
			    yyerror("class definition in method body");
			class_nest++;
			local_push(0);
		        $<num>$ = ruby_sourceline;
		    }
		  bodystmt
		  kEND
		    {
		        $$ = NEW_CLASS($2, $5, $3);
		        nd_set_line($$, $<num>4);
		        local_pop();
			class_nest--;
		    }
		| kCLASS tLSHFT expr
		    {
			$<num>$ = in_def;
		        in_def = 0;
		    }
		  term
		    {
		        $<num>$ = in_single;
		        in_single = 0;
			class_nest++;
			local_push(0);
		    }
		  bodystmt
		  kEND
		    {
		        $$ = NEW_SCLASS($3, $7);
		        fixpos($$, $3);
		        local_pop();
			class_nest--;
		        in_def = $<num>4;
		        in_single = $<num>6;
		    }
		| kMODULE cpath
		    {
			if (in_def || in_single)
			    yyerror("module definition in method body");
			class_nest++;
			local_push(0);
		        $<num>$ = ruby_sourceline;
		    }
		  bodystmt
		  kEND
		    {
		        $$ = NEW_MODULE($2, $4);
		        nd_set_line($$, $<num>3);
		        local_pop();
			class_nest--;
		    }
		| kDEF fname
		    {
			$<id>$ = cur_mid;
			cur_mid = $2;
			in_def++;
			local_push(0);
		    }
		  f_arglist
		  bodystmt
		  kEND
		    {
			if (!$5) $5 = NEW_NIL();
			$$ = NEW_DEFN($2, $4, $5, NOEX_PRIVATE);
		        fixpos($$, $4);
		        local_pop();
			in_def--;
			cur_mid = $<id>3;
		    }
		| kDEF singleton dot_or_colon {lex_state = EXPR_FNAME;} fname
		    {
			in_single++;
			local_push(0);
		        lex_state = EXPR_END; /* force for args */
		    }
		  f_arglist
		  bodystmt
		  kEND
		    {
			$$ = NEW_DEFS($2, $5, $7, $8);
		        fixpos($$, $2);
		        local_pop();
			in_single--;
		    }
		| kBREAK
		    {
			$$ = NEW_BREAK(0);
		    }
		| kNEXT
		    {
			$$ = NEW_NEXT(0);
		    }
		| kREDO
		    {
			$$ = NEW_REDO();
		    }
		| kRETRY
		    {
			$$ = NEW_RETRY();
		    }
		;

primary_value 	: primary
		    {
			value_expr($1);
			$$ = $1;
		    }
		;

then		: term
		| ':'
		| kTHEN
		| term kTHEN
		;

do		: term
		| ':'
		| kDO_COND
		;

if_tail		: opt_else
		| kELSIF expr_value then
		  compstmt
		  if_tail
		    {
			$$ = NEW_IF(cond($2), $4, $5);
		        fixpos($$, $2);
		    }
		;

opt_else	: none
		| kELSE compstmt
		    {
			$$ = $2;
		    }
		;

for_var 	: lhs
		| mlhs
		;

block_par	: mlhs_item
		    {
			$$ = NEW_LIST($1);
		    }
		| block_par ',' mlhs_item
		    {
			$$ = list_append($1, $3);
		    }
		;

block_var	: block_par
		    {
			if ($1->nd_alen == 1) {
			    $$ = $1->nd_head;
			    rb_gc_force_recycle((VALUE)$1);
			}
			else {
			    $$ = NEW_MASGN($1, 0);
			}
		    }
		| block_par ','
		    {
			$$ = NEW_MASGN($1, 0);
		    }
		| block_par ',' tAMPER lhs
		    {
			$$ = NEW_BLOCK_VAR($4, NEW_MASGN($1, 0));
		    }
		| block_par ',' tSTAR lhs ',' tAMPER lhs
		    {
			$$ = NEW_BLOCK_VAR($7, NEW_MASGN($1, $4));
		    }
		| block_par ',' tSTAR ',' tAMPER lhs
		    {
			$$ = NEW_BLOCK_VAR($6, NEW_MASGN($1, -1));
		    }
		| block_par ',' tSTAR lhs
		    {
			$$ = NEW_MASGN($1, $4);
		    }
		| block_par ',' tSTAR
		    {
			$$ = NEW_MASGN($1, -1);
		    }
		| tSTAR lhs ',' tAMPER lhs
		    {
			$$ = NEW_BLOCK_VAR($5, NEW_MASGN(0, $2));
		    }
		| tSTAR ',' tAMPER lhs
		    {
			$$ = NEW_BLOCK_VAR($4, NEW_MASGN(0, -1));
		    }
		| tSTAR lhs
		    {
			$$ = NEW_MASGN(0, $2);
		    }
		| tSTAR
		    {
			$$ = NEW_MASGN(0, -1);
		    }
		| tAMPER lhs
		    {
			$$ = NEW_BLOCK_VAR($2, (NODE*)1);
		    }
		;

opt_block_var	: none
		| '|' /* none */ '|'
		    {
			$$ = (NODE*)1;
			command_start = Qtrue;
		    }
		| tOROP
		    {
			$$ = (NODE*)1;
			command_start = Qtrue;
		    }
		| '|' block_var '|'
		    {
			$$ = $2;
			command_start = Qtrue;
		    }
		;

do_block	: kDO_BLOCK
		    {
		        $<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    }
		  opt_block_var {$<vars>$ = ruby_dyna_vars;}
		  compstmt
		  kEND
		    {
			$$ = NEW_ITER($3, 0, dyna_init($5, $<vars>4));
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    }
		;

block_call	: command do_block
		    {
			if ($1 && nd_type($1) == NODE_BLOCK_PASS) {
			    rb_compile_error("both block arg and actual block given");
			}
			$2->nd_iter = $1;
			$$ = $2;
		        fixpos($$, $1);
		    }
		| block_call '.' operation2 opt_paren_args
		    {
			$$ = new_call($1, $3, $4);
		    }
		| block_call tCOLON2 operation2 opt_paren_args
		    {
			$$ = new_call($1, $3, $4);
		    }
		;

method_call	: operation paren_args
		    {
			$$ = new_fcall($1, $2);
		        fixpos($$, $2);
		    }
		| primary_value '.' operation2 opt_paren_args
		    {
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    }
		| primary_value tCOLON2 operation2 paren_args
		    {
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    }
		| primary_value tCOLON2 operation3
		    {
			$$ = new_call($1, $3, 0);
		    }
		| primary_value '.' paren_args
		    {
			$$ = new_call($1, rb_intern("call"), $3);
			fixpos($$, $1);
		    }
		| primary_value tCOLON2 paren_args
		    {
			$$ = new_call($1, rb_intern("call"), $3);
			fixpos($$, $1);
		    }
		| kSUPER paren_args
		    {
			$$ = new_super($2);
		    }
		| kSUPER
		    {
			$$ = NEW_ZSUPER();
		    }
		;

brace_block	: '{'
		    {
		        $<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    }
		  opt_block_var {$<vars>$ = ruby_dyna_vars;}
		  compstmt '}'
		    {
			$$ = NEW_ITER($3, 0, dyna_init($5, $<vars>4));
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    }
		| kDO
		    {
		        $<vars>$ = dyna_push();
			$<num>1 = ruby_sourceline;
		    }
		  opt_block_var {$<vars>$ = ruby_dyna_vars;}
		  compstmt kEND
		    {
			$$ = NEW_ITER($3, 0, dyna_init($5, $<vars>4));
			nd_set_line($$, $<num>1);
			dyna_pop($<vars>2);
		    }
		;

case_body	: kWHEN when_args then
		  compstmt
		  cases
		    {
			$$ = NEW_WHEN($2, $4, $5);
		    }
		;
when_args	: args
		| args ',' tSTAR arg_value
		    {
			$$ = list_append($1, NEW_WHEN($4, 0, 0));
		    }
		| tSTAR arg_value
		    {
			$$ = NEW_LIST(NEW_WHEN($2, 0, 0));
		    }
		;

cases		: opt_else
		| case_body
		;

opt_rescue	: kRESCUE exc_list exc_var then
		  compstmt
		  opt_rescue
		    {
		        if ($3) {
		            $3 = node_assign($3, NEW_GVAR(rb_intern("$!")));
			    $5 = block_append($3, $5);
			}
			$$ = NEW_RESBODY($2, $5, $6);
		        fixpos($$, $2?$2:$5);
		    }
		| none
		;

exc_list	: arg_value
		    {
			$$ = NEW_LIST($1);
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
			if ($2)
			    $$ = $2;
			else
			    /* place holder */
			    $$ = NEW_NIL();
		    }
		| none
		;

literal		: numeric
		| symbol
		    {
			$$ = NEW_LIT(ID2SYM($1));
		    }
		| dsym
		;

strings		: string
		    {
			NODE *node = $1;
			if (!node) {
			    node = NEW_STR(rb_str_new(0, 0));
			}
			else {
			    node = evstr2dstr(node);
			}
			$$ = node;
		    }
		;

string		: string1
		| string string1
		    {
			$$ = literal_concat($1, $2);
		    }
		;

string1		: tSTRING_BEG string_contents tSTRING_END
		    {
			$$ = $2;
		    }
		;

xstring		: tXSTRING_BEG xstring_contents tSTRING_END
		    {
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
		    }
		;

regexp		: tREGEXP_BEG xstring_contents tREGEXP_END
		    {
			int options = $3;
			NODE *node = $2;
			if (!node) {
			    node = NEW_LIT(rb_reg_new("", 0, options & ~RE_OPTION_ONCE));
			}
			else switch (nd_type(node)) {
			  case NODE_STR:
			    {
				VALUE src = node->nd_lit;
				nd_set_type(node, NODE_LIT);
				node->nd_lit = rb_reg_new(RSTRING(src)->ptr,
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
		    }
		;

words		: tWORDS_BEG ' ' tSTRING_END
		    {
			$$ = NEW_ZARRAY();
		    }
		| tWORDS_BEG word_list tSTRING_END
		    {
			$$ = $2;
		    }
		;

word_list	: /* none */
		    {
			$$ = 0;
		    }
		| word_list word ' '
		    {
			$$ = list_append($1, evstr2dstr($2));
		    }
		;

word		: string_content
		| word string_content
		    {
			$$ = literal_concat($1, $2);
		    }
		;

qwords		: tQWORDS_BEG ' ' tSTRING_END
		    {
			$$ = NEW_ZARRAY();
		    }
		| tQWORDS_BEG qword_list tSTRING_END
		    {
			$$ = $2;
		    }
		;

qword_list	: /* none */
		    {
			$$ = 0;
		    }
		| qword_list tSTRING_CONTENT ' '
		    {
			$$ = list_append($1, $2);
		    }
		;

string_contents : /* none */
		    {
			$$ = 0;
		    }
		| string_contents string_content
		    {
			$$ = literal_concat($1, $2);
		    }
		;

xstring_contents: /* none */
		    {
			$$ = 0;
		    }
		| xstring_contents string_content
		    {
			$$ = literal_concat($1, $2);
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
			lex_strterm = $<node>2;
		        $$ = NEW_EVSTR($3);
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
			if (($$ = $3) && nd_type($$) == NODE_NEWLINE) {
			    $$ = $$->nd_next;
			    rb_gc_force_recycle((VALUE)$3);
			}
			$$ = new_evstr($$);
		    }
		;

string_dvar	: tGVAR {$$ = NEW_GVAR($1);}
		| tIVAR {$$ = NEW_IVAR($1);}
		| tCVAR {$$ = NEW_CVAR($1);}
		| backref
		;

symbol		: tSYMBEG sym
		    {
		        lex_state = EXPR_END;
			$$ = $2;
		    }
		;

sym		: fname
		| tIVAR
		| tGVAR
		| tCVAR
		;

dsym		: tSYMBEG xstring_contents tSTRING_END
		    {
		        lex_state = EXPR_END;
			if (!($$ = $2)) {
			    $$ = NEW_LIT(ID2SYM(rb_intern("")));
			}
			else {
			    VALUE lit;

			    switch (nd_type($$)) {
			      case NODE_DSTR:
				nd_set_type($$, NODE_DSYM);
				break;
			      case NODE_STR:
				lit = $$->nd_lit;
				if (strlen(RSTRING(lit)->ptr) == RSTRING(lit)->len) {
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
		    }
		;

numeric		: tINTEGER
		| tFLOAT
		| tUMINUS_NUM tINTEGER	       %prec tLOWEST
		    {
			$$ = negate_lit($2);
		    }
		| tUMINUS_NUM tFLOAT	       %prec tLOWEST
		    {
			$$ = negate_lit($2);
		    }
		;

variable	: tIDENTIFIER
		| tIVAR
		| tGVAR
		| tCONSTANT
		| tCVAR
		| kNIL {$$ = kNIL;}
		| kSELF {$$ = kSELF;}
		| kTRUE {$$ = kTRUE;}
		| kFALSE {$$ = kFALSE;}
		| k__FILE__ {$$ = k__FILE__;}
		| k__LINE__ {$$ = k__LINE__;}
		;

var_ref		: variable
		    {
			$$ = gettable($1);
		    }
		;

var_lhs		: variable
		    {
			$$ = assignable($1, 0);
		    }
		;

backref		: tNTH_REF
		| tBACK_REF
		;

superclass	: term
		    {
			$$ = 0;
		    }
		| '<'
		    {
			lex_state = EXPR_BEG;
		    }
		  expr_value term
		    {
			$$ = $3;
		    }
		| error term {yyerrok; $$ = 0;}
		;

f_arglist	: '(' f_args opt_nl ')'
		    {
			$$ = $2;
			lex_state = EXPR_BEG;
		        command_start = Qtrue;
		    }
		| f_args term
		    {
			$$ = $1;
		    }
		;

f_args		: f_arg ',' f_optarg ',' f_rest_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS($1, $3, $5), $6);
		    }
		| f_arg ',' f_optarg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS($1, $3, 0), $4);
		    }
		| f_arg ',' f_rest_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS($1, 0, $3), $4);
		    }
		| f_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS($1, 0, 0), $2);
		    }
		| f_optarg ',' f_rest_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS(0, $1, $3), $4);
		    }
		| f_optarg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS(0, $1, 0), $2);
		    }
		| f_rest_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS(0, 0, $1), $2);
		    }
		| f_block_arg
		    {
			$$ = block_append(NEW_ARGS(0, 0, 0), $1);
		    }
		| /* none */
		    {
			$$ = NEW_ARGS(0, 0, 0);
		    }
		;

f_norm_arg	: tCONSTANT
		    {
			yyerror("formal argument cannot be a constant");
		    }
                | tIVAR
		    {
                        yyerror("formal argument cannot be an instance variable");
		    }
                | tGVAR
		    {
                        yyerror("formal argument cannot be a global variable");
		    }
                | tCVAR
		    {
                        yyerror("formal argument cannot be a class variable");
		    }
		| tIDENTIFIER
		    {
			if (!is_local_id($1))
			    yyerror("formal argument must be local variable");
			else if (local_id($1))
			    yyerror("duplicate argument name");
			local_cnt($1);
			$$ = 1;
		    }
		;

f_arg		: f_norm_arg
		| f_arg ',' f_norm_arg
		    {
			$$ += 1;
		    }
		;

f_opt		: tIDENTIFIER '=' arg_value
		    {
			if (!is_local_id($1))
			    yyerror("formal argument must be local variable");
			else if (local_id($1))
			    yyerror("duplicate optional argument name");
			$$ = assignable($1, $3);
		    }
		;

f_optarg	: f_opt
		    {
			$$ = NEW_BLOCK($1);
			$$->nd_end = $$;
		    }
		| f_optarg ',' f_opt
		    {
			$$ = block_append($1, $3);
		    }
		;

restarg_mark	: '*'
		| tSTAR
		;

f_rest_arg	: restarg_mark tIDENTIFIER
		    {
			if (!is_local_id($2))
			    yyerror("rest argument must be local variable");
			else if (local_id($2))
			    yyerror("duplicate rest argument name");
			if (dyna_in_block()) {
			    rb_dvar_push($2, Qnil);
			}
			$$ = assignable($2, 0);
		    }
		| restarg_mark
		    {
			if (dyna_in_block()) {
			    $$ = NEW_DASGN_CURR(internal_id(), 0);
			}
			else {
			    $$ = NEW_NODE(NODE_LASGN,0,0,local_append(0));
			}
		    }
		;

blkarg_mark	: '&'
		| tAMPER
		;

f_block_arg	: blkarg_mark tIDENTIFIER
		    {
			if (!is_local_id($2))
			    yyerror("block argument must be local variable");
			else if (local_id($2))
			    yyerror("duplicate block argument name");
			$$ = NEW_BLOCK_ARG($2);
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
			$$ = $1;
			value_expr($$);
		    }
		| '(' {lex_state = EXPR_BEG;} expr opt_nl ')'
		    {
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
		    }
		;

assoc_list	: none
		| assocs trailer
		    {
			$$ = $1;
		    }
		| args trailer
		    {
			if ($1->nd_alen%2 != 0) {
			    yyerror("odd number list for Hash");
			}
			$$ = $1;
		    }
		;

assocs		: assoc
		| assocs ',' assoc
		    {
			$$ = list_concat($1, $3);
		    }
		;

assoc		: arg_value tASSOC arg_value
		    {
			$$ = list_append(NEW_LIST($1), $3);
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
		| tCOLON2
		;

opt_terms	: /* none */
		| terms
		;

opt_nl		: /* none */
		| '\n'
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

none		: /* none */ {$$ = 0;}
		;
%%
#ifdef yystacksize
#undef YYMALLOC
#endif

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

static char *tokenbuf = NULL;
static int   tokidx, toksiz = 0;

#define LEAVE_BS 1

static VALUE (*lex_gets)();	/* gets function */
static VALUE lex_input;		/* non-nil if File */
static VALUE lex_lastline;	/* gc protect */
static char *lex_pbeg;
static char *lex_p;
static char *lex_pend;

static int
yyerror(msg)
    const char *msg;
{
    const int max_line_margin = 30;
    const char *p, *pe;
    char *buf;
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
	char *p2;
	const char *pre = "", *post = "";

	if (len > max_line_margin * 2 + 10) {
	    int re_mbc_startpos _((const char *, int, int, int));
	    if ((len = lex_p - p) > max_line_margin) {
		p = p + re_mbc_startpos(p, len, len - max_line_margin, 0);
		pre = "...";
	    }
	    if ((len = pe - lex_p) > max_line_margin) {
		pe = lex_p + re_mbc_startpos(lex_p, len, max_line_margin, 1);
		post = "...";
	    }
	    len = pe - p;
	}
	buf = ALLOCA_N(char, len+2);
	MEMCPY(buf, p, char, len);
	buf[len] = '\0';
	rb_compile_error_append("%s%s%s", pre, buf, post);

	i = lex_p - p;
	p2 = buf; pe = buf + len;

	while (p2 < pe) {
	    if (*p2 != '\t') *p2 = ' ';
	    p2++;
	}
	buf[i] = '^';
	buf[i+1] = '\0';
	rb_compile_error_append("%s", buf);
    }

    return 0;
}

static int heredoc_end;

int ruby_in_compile = 0;
int ruby__end__seen;

static VALUE ruby_debug_lines;
#ifdef YYMALLOC
static NODE *parser_heap;
#endif

static NODE*
yycompile(f, line)
    char *f;
    int line;
{
    int n;
    NODE *node = 0;
    struct RVarmap *vp, *vars = ruby_dyna_vars;

    ruby_in_compile = 1;
    if (!compile_for_eval && rb_safe_level() == 0 &&
	rb_const_defined(rb_cObject, rb_intern("SCRIPT_LINES__"))) {
	VALUE hash, fname;

	hash = rb_const_get(rb_cObject, rb_intern("SCRIPT_LINES__"));
	if (TYPE(hash) == T_HASH) {
	    fname = rb_str_new2(f);
	    ruby_debug_lines = rb_ary_new();
	    rb_hash_aset(hash, fname, ruby_debug_lines);
	}
	if (line > 1) {
	    VALUE str = rb_str_new(0,0);
	    while (line > 1) {
		rb_ary_push(ruby_debug_lines, str);
		line--;
	    }
	}
    }

    ruby__end__seen = 0;
    ruby_eval_tree = 0;
    ruby_eval_tree_begin = 0;
    heredoc_end = 0;
    lex_strterm = 0;
    ruby_current_node = 0;
    ruby_sourcefile = rb_source_filename(f);
    deferred_nodes = 0;
    n = yyparse();
    ruby_debug_lines = 0;
    compile_for_eval = 0;
    ruby_in_compile = 0;
    cond_stack = 0;
    cmdarg_stack = 0;
    command_start = 1;
    class_nest = 0;
    in_single = 0;
    in_def = 0;
    cur_mid = 0;
    deferred_nodes = 0;

    vp = ruby_dyna_vars;
    ruby_dyna_vars = vars;
    lex_strterm = 0;
    while (vp && vp != vars) {
	struct RVarmap *tmp = vp;
	vp = vp->next;
	rb_gc_force_recycle((VALUE)tmp);
    }
    if (n == 0) node = ruby_eval_tree;
    if (ruby_nerrs) ruby_eval_tree_begin = 0;
    return node;
}

static int lex_gets_ptr;

static VALUE
lex_get_str(s)
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
lex_getline()
{
    VALUE line = (*lex_gets)(lex_input);
    if (ruby_debug_lines && !NIL_P(line)) {
	rb_ary_push(ruby_debug_lines, line);
    }
    return line;
}

NODE*
rb_compile_string(f, s, line)
    const char *f;
    VALUE s;
    int line;
{
    lex_gets = lex_get_str;
    lex_gets_ptr = 0;
    lex_input = s;
    lex_pbeg = lex_p = lex_pend = 0;
    ruby_sourceline = line - 1;
    compile_for_eval = ruby_in_eval;

    return yycompile(f, line);
}

NODE*
rb_compile_cstr(f, s, len, line)
    const char *f, *s;
    int len, line;
{
    return rb_compile_string(f, rb_str_new(s, len), line);
}

NODE*
rb_compile_file(f, file, start)
    const char *f;
    VALUE file;
    int start;
{
    lex_gets = rb_io_gets;
    lex_input = file;
    lex_pbeg = lex_p = lex_pend = 0;
    ruby_sourceline = start - 1;

    return yycompile(f, start);
}

static inline int
nextc()
{
    int c;

    if (lex_p == lex_pend) {
	if (lex_input) {
	    VALUE v = lex_getline();

	    if (NIL_P(v)) return -1;
	    if (heredoc_end > 0) {
		ruby_sourceline = heredoc_end;
		heredoc_end = 0;
	    }
	    ruby_sourceline++;
	    lex_pbeg = lex_p = RSTRING(v)->ptr;
	    lex_pend = lex_p + RSTRING(v)->len;
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
pushback(c)
    int c;
{
    if (c == -1) return;
    lex_p--;
}

#define was_bol() (lex_p == lex_pbeg + 1)
#define peek(c) (lex_p != lex_pend && (c) == *lex_p)

#define tokfix() (tokenbuf[tokidx]='\0')
#define tok() tokenbuf
#define toklen() tokidx
#define toklast() (tokidx>0?tokenbuf[tokidx-1]:0)

static char*
newtok()
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
tokadd(c)
    char c;
{
    tokenbuf[tokidx++] = c;
    if (tokidx >= toksiz) {
	toksiz *= 2;
	REALLOC_N(tokenbuf, char, toksiz);
    }
}

static int
read_escape()
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
tokadd_escape()
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
	    return tokadd_escape();
	}
	else if (c == -1) goto eof;
	tokadd(c);
	return 0;

      eof:
      case -1:
        yyerror("Invalid escape character syntax");
	return -1;

      default:
        tokadd('\\');
	tokadd(c);
    }
    return 0;
}

static int
regx_options()
{
    char kcode = 0;
    int options = 0;
    int c;

    newtok();
    while (c = nextc(), ISALPHA(c)) {
	switch (c) {
	  case 'i':
	    options |= RE_OPTION_IGNORECASE;
	    break;
	  case 'x':
	    options |= RE_OPTION_EXTENDED;
	    break;
	  case 'm':
	    options |= RE_OPTION_MULTILINE;
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
	rb_compile_error("unknown regexp option%s - %s",
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
    str_dsym   = (STR_FUNC_SYMBOL|STR_FUNC_EXPAND)
};

static void
dispose_string(str)
    VALUE str;
{
    xfree(RSTRING(str)->ptr);
    rb_gc_force_recycle(str);
}

static int
tokadd_string(func, term, paren, nest)
    int func, term, paren, *nest;
{
    int c;

    while ((c = nextc()) != -1) {
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
		    if (tokadd_escape() < 0)
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
	else if (ismbchar(c)) {
	    int i, len = mbclen(c)-1;

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
	    rb_compile_error("symbol cannot contain '\\0'");
	    continue;
	}
	tokadd(c);
    }
    return c;
}

#define NEW_STRTERM(func, term, paren) \
	rb_node_newnode(NODE_STRTERM, (func), (term) | ((paren) << (CHAR_BIT * 2)), 0)

static int
parse_string(quote)
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
	yylval.num = regx_options();
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
	rb_compile_error("unterminated string meets end of file");
	return tSTRING_END;
    }

    tokfix();
    yylval.node = NEW_STR(rb_str_new(tok(), toklen()));
    return tSTRING_CONTENT;
}

static int
heredoc_identifier()
{
    int c = nextc(), term, func = 0, len;

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
	    len = mbclen(c);
	    do {tokadd(c);} while (--len > 0 && (c = nextc()) != -1);
	}
	if (c == -1) {
	    rb_compile_error("unterminated here document identifier");
	    return 0;
	}
	break;

      default:
	if (!is_identchar(c)) {
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
	    len = mbclen(c);
	    do {tokadd(c);} while (--len > 0 && (c = nextc()) != -1);
	} while ((c = nextc()) != -1 && is_identchar(c));
	pushback(c);
	break;
    }

    tokfix();
    len = lex_p - lex_pbeg;
    lex_p = lex_pend;
    lex_strterm = rb_node_newnode(NODE_HEREDOC,
				  rb_str_new(tok(), toklen()),	/* nd_lit */
				  len,				/* nd_nth */
				  lex_lastline);		/* nd_orig */
    return term == '`' ? tXSTRING_BEG : tSTRING_BEG;
}

static void
heredoc_restore(here)
    NODE *here;
{
    VALUE line = here->nd_orig;
    lex_lastline = line;
    lex_pbeg = RSTRING(line)->ptr;
    lex_pend = lex_pbeg + RSTRING(line)->len;
    lex_p = lex_pbeg + here->nd_nth;
    heredoc_end = ruby_sourceline;
    ruby_sourceline = nd_line(here);
    dispose_string(here->nd_lit);
    rb_gc_force_recycle((VALUE)here);
}

static int
whole_match_p(eos, len, indent)
    const char *eos;
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
here_document(here)
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
	rb_compile_error("can't find string \"%s\" anywhere before EOF", eos);
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
	    lex_p = lex_pend;
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
		yylval.node = NEW_STR(rb_str_new(tok(), toklen()));
		return tSTRING_CONTENT;
	    }
	    tokadd(nextc());
	    if ((c = nextc()) == -1) goto error;
	} while (!whole_match_p(eos, len, indent));
	str = rb_str_new(tok(), toklen());
    }
    heredoc_restore(lex_strterm);
    lex_strterm = NEW_STRTERM(-1, 0, 0);
    yylval.node = NEW_STR(str);
    return tSTRING_CONTENT;
}

#include "lex.c"

static void
arg_ambiguous()
{
    rb_warning("ambiguous first argument; put parentheses or even spaces");
}

#define IS_ARG() (lex_state == EXPR_ARG || lex_state == EXPR_CMDARG)
#define IS_BEG() (lex_state == EXPR_BEG || lex_state == EXPR_MID || \
                  lex_state == EXPR_VALUE || lex_state == EXPR_CLASS)

static int
yylex()
{
    register int c;
    int space_seen = 0;
    int cmd_state;
    enum lex_state last_state;

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
	while ((c = nextc()) != '\n') {
	    if (c == -1)
		return 0;
	}
	/* fall through */
      case '\n':
	switch (lex_state) {
	  case EXPR_BEG:
	  case EXPR_FNAME:
	  case EXPR_DOT:
	  case EXPR_CLASS:
	  case EXPR_VALUE:
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
		yylval.id = tPOW;
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    c = tPOW;
	}
	else {
	    if (c == '=') {
		yylval.id = '*';
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    if (IS_ARG() && space_seen && !ISSPACE(c)){
		rb_warning("`*' interpreted as argument prefix");
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
		for (;;) {
		    lex_p = lex_pend;
		    c = nextc();
		    if (c == -1) {
			rb_compile_error("embedded document meets end of file");
			return 0;
		    }
		    if (c != '=') continue;
		    if (strncmp(lex_p, "end", 3) == 0 &&
			(lex_p + 3 == lex_pend || ISSPACE(lex_p[3]))) {
			break;
		    }
		}
		lex_p = lex_pend;
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
		yylval.id = tLSHFT;
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
		yylval.id = tRSHFT;
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
	    rb_compile_error("incomplete character syntax");
	    return 0;
	}
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
		    rb_warn("invalid character syntax; use ?\\%c", c2);
		}
	    }
	  ternary:
	    pushback(c);
	    lex_state = EXPR_BEG;
	    return '?';
	}
	else if (ismbchar(c)) {
	    rb_warn("multibyte character literal not supported yet; use ?\\%.3o", c);
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
	yylval.node = NEW_LIT(INT2FIX(c));
	return tINTEGER;

      case '&':
	if ((c = nextc()) == '&') {
	    lex_state = EXPR_BEG;
	    if ((c = nextc()) == '=') {
		yylval.id = tANDOP;
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tANDOP;
	}
	else if (c == '=') {
	    yylval.id = '&';
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	pushback(c);
	if (IS_ARG() && space_seen && !ISSPACE(c)){
	    rb_warning("`&' interpreted as argument prefix");
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
		yylval.id = tOROP;
		lex_state = EXPR_BEG;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tOROP;
	}
	if (c == '=') {
	    yylval.id = '|';
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
	    yylval.id = '+';
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
	    yylval.id = '-';
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
		    yylval.node = NEW_LIT(rb_cstr_to_inum(tok(), 16, Qfalse));
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
		    yylval.node = NEW_LIT(rb_cstr_to_inum(tok(), 2, Qfalse));
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
		    yylval.node = NEW_LIT(rb_cstr_to_inum(tok(), 10, Qfalse));
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
			if (c < '0' || c > '9') break;
			if (c > '7') goto invalid_octal;
			nondigit = 0;
			tokadd(c);
		    } while ((c = nextc()) != -1);
		    if (toklen() > start) {
			pushback(c);
			tokfix();
			if (nondigit) goto trailing_uc;
			yylval.node = NEW_LIT(rb_cstr_to_inum(tok(), 8, Qfalse));
			return tINTEGER;
		    }
		    if (nondigit) {
			pushback(c);
			goto trailing_uc;
		    }
		}
		if (c > '7' && c <= '9') {
		  invalid_octal:
		    yyerror("Illegal octal digit");
		}
		else if (c == '.' || c == 'e' || c == 'E') {
		    tokadd('0');
		}
		else {
		    pushback(c);
		    yylval.node = NEW_LIT(INT2FIX(0));
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
		    rb_warn("Float %s out of range", tok());
		    errno = 0;
		}
		yylval.node = NEW_LIT(rb_float_new(d));
		return tFLOAT;
	    }
	    yylval.node = NEW_LIT(rb_cstr_to_inum(tok(), 10, Qfalse));
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
	    if (IS_BEG() || (IS_ARG() && space_seen)) {
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
	    yylval.id = '/';
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
	    yylval.id = '^';
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
	command_start = Qtrue;
	if (IS_BEG()) {
	    c = tLPAREN;
	}
	else if (space_seen) {
	    if (lex_state == EXPR_CMDARG) {
		c = tLPAREN_ARG;
	    }
	    else if (lex_state == EXPR_ARG) {
		rb_warn("don't put space before argument parentheses");
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
	if (c != tLBRACE) command_start = Qtrue;
	return c;

      case '\\':
	c = nextc();
	if (c == '\n') {
	    space_seen = 1;
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
		if (ISALNUM(term) || ismbchar(term)) {
		    yyerror("unknown type of %string");
		    return 0;
		}
	    }
	    if (c == -1 || term == -1) {
		rb_compile_error("unterminated quoted string meets end of file");
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
		do {c = nextc();} while (ISSPACE(c));
		pushback(c);
		return tWORDS_BEG;

	      case 'w':
		lex_strterm = NEW_STRTERM(str_sword, term, paren);
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
	    yylval.id = '%';
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
	last_state = lex_state;
	lex_state = EXPR_END;
	newtok();
	c = nextc();
	switch (c) {
	  case '_':		/* $_: last read line string */
	    c = nextc();
	    if (is_identchar(c)) {
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
	    yylval.id = rb_intern(tok());
	    return tGVAR;

	  case '-':
	    tokadd('$');
	    tokadd(c);
	    c = nextc();
	    if (is_identchar(c)) {
		tokadd(c);
	    }
	    else {
		pushback(c);
	    }
	  gvar:
	    tokfix();
	    yylval.id = rb_intern(tok());
	    /* xxx shouldn't check if valid option variable */
	    return tGVAR;

	  case '&':		/* $&: last match */
	  case '`':		/* $`: string before last match */
	  case '\'':		/* $': string after last match */
	  case '+':		/* $+: string matches last paren. */
	    if (last_state == EXPR_FNAME) {
		tokadd('$');
		tokadd(c);
		goto gvar;
	    }
	    yylval.node = NEW_BACK_REF(c);
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
	    if (last_state == EXPR_FNAME) goto gvar;
	    tokfix();
	    yylval.node = NEW_NTH_REF(atoi(tok()+1));
	    return tNTH_REF;

	  default:
	    if (!is_identchar(c)) {
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
		rb_compile_error("`@%c' is not allowed as an instance variable name", c);
	    }
	    else {
		rb_compile_error("`@@%c' is not allowed as a class variable name", c);
	    }
	    return 0;
	}
	if (!is_identchar(c)) {
	    pushback(c);
	    return '@';
	}
	break;

      case '_':
	if (was_bol() && whole_match_p("__END__", 7, 0)) {
	    ruby__end__seen = 1;
	    lex_lastline = 0;
	    return -1;
	}
	newtok();
	break;

      default:
	if (!is_identchar(c)) {
	    rb_compile_error("Invalid char `\\%03o' in expression", c);
	    goto retry;
	}

	newtok();
	break;
    }

    do {
	tokadd(c);
	if (ismbchar(c)) {
	    int i, len = mbclen(c)-1;

	    for (i = 0; i < len; i++) {
		c = nextc();
		tokadd(c);
	    }
	}
	c = nextc();
    } while (is_identchar(c));
    if ((c == '!' || c == '?') && is_identchar(tok()[0]) && !peek('=')) {
	tokadd(c);
    }
    else {
	pushback(c);
    }
    tokfix();

    {
	int result = 0;

	last_state = lex_state;
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

	    if ((lex_state == EXPR_BEG && !cmd_state) ||
		lex_state == EXPR_ARG ||
		lex_state == EXPR_CMDARG) {
		if (peek(':') && !(lex_p + 1 < lex_pend && lex_p[1] == ':')) {
		    lex_state = EXPR_BEG;
		    nextc();
		    yylval.id = rb_intern(tok());
		    return tLABEL;
		}
	    }
	    if (lex_state != EXPR_DOT) {
		const struct kwtable *kw;

		/* See if it is a reserved word.  */
		kw = rb_reserved_word(tok(), toklen());
		if (kw) {
		    enum lex_state state = lex_state;
		    lex_state = kw->state;
		    if (state == EXPR_FNAME) {
			yylval.id = rb_intern(kw->name);
			return kw->id[0];
		    }
		    if (kw->id[0] == kDO) {
			command_start = Qtrue;
			if (COND_P()) return kDO_COND;
			if (CMDARG_P() && state != EXPR_CMDARG)
			    return kDO_BLOCK;
			if (state == EXPR_ENDARG)
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

	    if (lex_state == EXPR_BEG ||
		lex_state == EXPR_MID ||
		lex_state == EXPR_DOT ||
		lex_state == EXPR_ARG ||
		lex_state == EXPR_CLASS ||
		lex_state == EXPR_VALUE ||
		lex_state == EXPR_CMDARG) {
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
	yylval.id = rb_intern(tok());
	if (is_local_id(yylval.id) &&
	    last_state != EXPR_DOT &&
	    ((dyna_in_block() && rb_dvar_defined(yylval.id)) || local_id(yylval.id))) {
	    lex_state = EXPR_END;
	}
	return result;
    }
}

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
    NODE *nl = 0;
    if (node) {
	int line;
	if (nd_type(node) == NODE_NEWLINE) return node;
	line = nd_line(node);
	node = remove_begin(node);
	nl = NEW_NEWLINE(node);
	nd_set_line(nl, line);
	nl->nd_nth = line;
    }
    return nl;
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
    rb_warning("%s", mesg);
    ruby_sourceline = line;
}

static void
parser_warn(node, mesg)
    NODE *node;
    const char *mesg;
{
    int line = ruby_sourceline;
    ruby_sourceline = nd_line(node);
    rb_warn("%s", mesg);
    ruby_sourceline = line;
}

static NODE*
block_append(head, tail)
    NODE *head, *tail;
{
    NODE *end, *h = head;

    if (tail == 0) return head;

  again:
    if (h == 0) return tail;
    switch (nd_type(h)) {
      case NODE_NEWLINE:
	h = h->nd_next;
	goto again;
      case NODE_LIT:
      case NODE_STR:
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

    if (RTEST(ruby_verbose)) {
	NODE *nd = end->nd_head;
      newline:
	switch (nd_type(nd)) {
	  case NODE_RETURN:
	  case NODE_BREAK:
	  case NODE_NEXT:
	  case NODE_REDO:
	  case NODE_RETRY:
	    parser_warning(nd, "statement not reached");
	    break;

	case NODE_NEWLINE:
	    nd = nd->nd_next;
	    goto newline;

	  default:
	    break;
	}
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

  again:
    if (node) {
	switch (nd_type(node)) {
	  case NODE_STR: case NODE_DSTR: case NODE_EVSTR:
	    return node;
	  case NODE_NEWLINE:
	    node = node->nd_next;
	    goto again;
	}
    }
    return NEW_EVSTR(head);
}

static NODE *
call_op(recv, id, narg, arg1)
    NODE *recv;
    ID id;
    int narg;
    NODE *arg1;
{
    value_expr(recv);
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
match_gen(node1, node2)
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
gettable(id)
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
#if 0
	/* Rite will warn this */
	rb_warn("ambiguous identifier; %s() or self.%s is better for method call",
		rb_id2name(id), rb_id2name(id));
#endif
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

static VALUE dyna_var_lookup _((ID id));

static NODE*
assignable(id, val)
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
	else if (dyna_var_lookup(id)) {
	    return NEW_DASGN(id, val);
	}
	else if (local_id(id) || !dyna_in_block()) {
	    return NEW_LASGN(id, val);
	}
	else{
	    rb_dvar_push(id, Qnil);
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

static NODE *
aryset(recv, idx)
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
attrset(recv, id)
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
node_assign(lhs, rhs)
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
value_expr0(node)
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

	  case NODE_NEWLINE:
	    node = node->nd_next;
	    break;

	  default:
	    return Qtrue;
	}
    }

    return Qtrue;
}

static void
void_expr0(node)
    NODE *node;
{
    const char *useless = 0;

    if (!RTEST(ruby_verbose)) return;

  again:
    if (!node) return;
    switch (nd_type(node)) {
      case NODE_NEWLINE:
	node = node->nd_next;
	goto again;

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
void_stmts(node)
    NODE *node;
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
remove_begin(node)
    NODE *node;
{
    NODE **n = &node;
    while (*n) {
	switch (nd_type(*n)) {
	  case NODE_NEWLINE:
	    n = &(*n)->nd_next;
	    continue;
	  case NODE_BEGIN:
	    *n = (*n)->nd_body;
	  default:
	    return node;
	}
    }
    return node;
}

static int
assign_in_cond(node)
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

      case NODE_NEWLINE:
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
#if 0
    if (assign_in_cond(node->nd_value) == 0) {
	parser_warning(node->nd_value, "assignment in condition");
    }
#endif
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

static void
fixup_nodes(rootnode)
    NODE **rootnode;
{
    NODE *node, *next, *head;

    for (node = *rootnode; node; node = next) {
	enum node_type type;
	VALUE val;

	next = node->nd_next;
	head = node->nd_head;
	rb_gc_force_recycle((VALUE)node);
	*rootnode = next;
	switch (type = nd_type(head)) {
	  case NODE_DOT2:
	  case NODE_DOT3:
	    val = rb_range_new(head->nd_beg->nd_lit, head->nd_end->nd_lit,
			       type == NODE_DOT3 ? Qtrue : Qfalse);
	    rb_gc_force_recycle((VALUE)head->nd_beg);
	    rb_gc_force_recycle((VALUE)head->nd_end);
	    nd_set_type(head, NODE_LIT);
	    head->nd_lit = val;
	    break;
	  default:
	    break;
	}
    }
}

static NODE *cond0();

static NODE*
range_op(node)
    NODE *node;
{
    enum node_type type;

    if (node == 0) return 0;

    type = nd_type(node);
    if (type == NODE_NEWLINE) {
	node = node->nd_next;
	type = nd_type(node);
    }
    value_expr(node);
    if (type == NODE_LIT && FIXNUM_P(node->nd_lit)) {
	warn_unless_e_option(node, "integer literal in conditional range");
	return call_op(node,tEQ,1,NEW_GVAR(rb_intern("$.")));
    }
    return cond0(node);
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
cond0(node)
    NODE *node;
{
    if (node == 0) return 0;
    assign_in_cond(node);

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
	node->nd_1st = cond0(node->nd_1st);
	node->nd_2nd = cond0(node->nd_2nd);
	break;

      case NODE_DOT2:
      case NODE_DOT3:
	node->nd_beg = range_op(node->nd_beg);
	node->nd_end = range_op(node->nd_end);
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
cond(node)
    NODE *node;
{
    if (node == 0) return 0;
    value_expr(node);
    if (nd_type(node) == NODE_NEWLINE){
	node->nd_next = cond0(node->nd_next);
	return node;
    }
    return cond0(node);
}

static NODE*
logop(type, left, right)
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
      case NODE_NEWLINE:
	if (c->nd_next && nd_type(c->nd_next) == NODE_NOT) {
	    c->nd_next = c->nd_next->nd_body;
	    return 1;
	}
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
	if (nd_type(node) == NODE_ARRAY && node->nd_next == 0) {
	    node = node->nd_head;
	}
	if (node && nd_type(node) == NODE_SPLAT) {
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
        if (node && nd_type(node) == NODE_SPLAT) {
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
new_fcall(m,a)
    ID m;
    NODE *a;
{
    if (a && nd_type(a) == NODE_BLOCK_PASS) {
	a->nd_iter = NEW_FCALL(m,a->nd_head);
	return a;
    }
    return NEW_FCALL(m,a);
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

static struct local_vars {
    ID *tbl;
    int nofree;
    int cnt;
    int dlev;
    struct RVarmap* dyna_vars;
    struct local_vars *prev;
} *lvtbl;

static void
local_push(top)
    int top;
{
    struct local_vars *local;

    local = ALLOC(struct local_vars);
    local->prev = lvtbl;
    local->nofree = 0;
    local->cnt = 0;
    local->tbl = 0;
    local->dlev = 0;
    local->dyna_vars = ruby_dyna_vars;
    lvtbl = local;
    if (!top) {
	/* preserve reference for GC, but link should be cut. */
	rb_dvar_push(0, (VALUE)ruby_dyna_vars);
	ruby_dyna_vars->next = 0;
    }
}

static void
local_pop()
{
    struct local_vars *local = lvtbl->prev;

    if (lvtbl->tbl) {
	if (!lvtbl->nofree) xfree(lvtbl->tbl);
	else lvtbl->tbl[0] = lvtbl->cnt;
    }
    ruby_dyna_vars = lvtbl->dyna_vars;
    xfree(lvtbl);
    lvtbl = local;
}

static ID*
local_tbl()
{
    lvtbl->nofree = 1;
    return lvtbl->tbl;
}

static int
local_append(id)
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
local_cnt(id)
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
local_id(id)
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
top_local_init()
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
top_local_setup()
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
		if (!(ruby_scope->flags & SCOPE_CLONE))
		    xfree(ruby_scope->local_tbl);
	    }
	    ruby_scope->local_vars[-1] = 0; /* no reference needed */
	    ruby_scope->local_tbl = local_tbl();
	}
    }
    local_pop();
}

#define DVAR_USED FL_USER6

static VALUE
dyna_var_lookup(id)
    ID id;
{
    struct RVarmap *vars = ruby_dyna_vars;

    while (vars) {
	if (vars->id == id) {
	    FL_SET(vars, DVAR_USED);
	    return Qtrue;
	}
	vars = vars->next;
    }
    return Qfalse;
}

static struct RVarmap*
dyna_push()
{
    struct RVarmap* vars = ruby_dyna_vars;

    rb_dvar_push(0, 0);
    lvtbl->dlev++;
    return vars;
}

static void
dyna_pop(vars)
    struct RVarmap* vars;
{
    lvtbl->dlev--;
    ruby_dyna_vars = vars;
}

static int
dyna_in_block()
{
    return (lvtbl->dlev > 0);
}

static NODE *
dyna_init(node, pre)
    NODE *node;
    struct RVarmap *pre;
{
    struct RVarmap *post = ruby_dyna_vars;
    NODE *var;

    if (!node || !post || pre == post) return node;
    for (var = 0; post != pre && post->id; post = post->next) {
	if (FL_TEST(post, DVAR_USED)) {
	    var = NEW_DASGN_CURR(post->id, var);
	}
    }
    return block_append(var, node);
}

int
ruby_parser_stack_on_heap()
{
#if defined(YYMALLOC)
    (void)rb_parser_realloc;
    (void)rb_parser_calloc;
    (void)nodetype;
    (void)nodeline;
    return Qfalse;
#else
    return Qtrue;
#endif
}

void
rb_gc_mark_parser()
{
#if defined YYMALLOC
    rb_gc_mark((VALUE)parser_heap);
#elif defined yystacksize
    if (yyvsp) rb_gc_mark_locations((VALUE *)yyvs, (VALUE *)yyvsp);
#endif

    if (!ruby_in_compile) return;

    rb_gc_mark_maybe((VALUE)yylval.node);
    rb_gc_mark(ruby_debug_lines);
    rb_gc_mark(lex_lastline);
    rb_gc_mark(lex_input);
    rb_gc_mark((VALUE)lex_strterm);
    rb_gc_mark((VALUE)deferred_nodes);
}

void
rb_parser_append_print()
{
    ruby_eval_tree =
	block_append(ruby_eval_tree,
		     NEW_FCALL(rb_intern("print"),
			       NEW_ARRAY(NEW_GVAR(rb_intern("$_")))));
}

void
rb_parser_while_loop(chop, split)
    int chop, split;
{
    if (split) {
	ruby_eval_tree =
	    block_append(NEW_GASGN(rb_intern("$F"),
				   NEW_CALL(NEW_GVAR(rb_intern("$_")),
					    rb_intern("split"), 0)),
				   ruby_eval_tree);
    }
    if (chop) {
	ruby_eval_tree =
	    block_append(NEW_CALL(NEW_GVAR(rb_intern("$_")),
				  rb_intern("chop!"), 0), ruby_eval_tree);
    }
    ruby_eval_tree = NEW_OPT_N(ruby_eval_tree);
}

static struct {
    ID token;
    const char *name;
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

static int
is_special_global_name(m)
    const char *m;
{
    switch (*m) {
      case '~': case '*': case '$': case '?': case '!': case '@':
      case '/': case '\\': case ';': case ',': case '.': case '=':
      case ':': case '<': case '>': case '\"':
      case '&': case '`': case '\'': case '+':
      case '0':
	++m;
	break;
      case '-':
	++m;
	if (is_identchar(*m)) m += mbclen(*m);
	break;
      default:
	if (!ISDIGIT(*m)) return 0;
	do ++m; while (ISDIGIT(*m));
    }
    return !*m;
}

int
rb_symname_p(name)
    const char *name;
{
    const char *m = name;
    int localid = Qfalse;

    if (!m) return Qfalse;
    switch (*m) {
      case '\0':
	return Qfalse;

      case '$':
	if (is_special_global_name(++m)) return Qtrue;
	goto id;

      case '@':
	if (*++m == '@') ++m;
	goto id;

      case '<':
	switch (*++m) {
	  case '<': ++m; break;
	  case '=': if (*++m == '>') ++m; break;
	  default: break;
	}
	break;

      case '>':
	switch (*++m) {
	  case '>': case '=': ++m; break;
	}
	break;

      case '=':
	switch (*++m) {
	  case '~': ++m; break;
	  case '=': if (*++m == '=') ++m; break;
	  default: return Qfalse;
	}
	break;

      case '*':
	if (*++m == '*') ++m;
	break;

      case '+': case '-':
	if (*++m == '@') ++m;
	break;

      case '|': case '^': case '&': case '/': case '%': case '~': case '`':
	++m;
	break;

      case '[':
	if (*++m != ']') return Qfalse;
	if (*++m == '=') ++m;
	break;

      default:
	localid = !ISUPPER(*m);
      id:
	if (*m != '_' && !ISALPHA(*m) && !ismbchar(*m)) return Qfalse;
	while (is_identchar(*m)) m += mbclen(*m);
	if (localid) {
	    switch (*m) {
	      case '!': case '?': case '=': ++m;
	    }
	}
	break;
    }
    return *m ? Qfalse : Qtrue;
}

int
rb_sym_interned_p(str)
    VALUE str;
{
    ID id;

    if (st_lookup(sym_tbl, (st_data_t)RSTRING(str)->ptr, (st_data_t *)&id))
	return Qtrue;
    return Qfalse;
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
	if (is_special_global_name(++m)) goto new_id;
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
	if (name[0] != '_' && ISASCII(name[0]) && !ISALNUM(name[0])) {
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
    if (!ISDIGIT(*m)) {
	while (m <= name + last && is_identchar(*m)) {
	    m += mbclen(*m);
	}
    }
    if (*m) id = ID_JUNK;
  new_id:
    if (last_id >= SYM2ID(~(VALUE)0) >> ID_SCOPE_SHIFT) {
	if (last > 20) {
	    rb_raise(rb_eRuntimeError, "symbol table overflow (symbol %.20s...)",
		     name);
	}
	else {
	    rb_raise(rb_eRuntimeError, "symbol table overflow (symbol %.*s)",
		     last, name);
	}
    }
    id |= ++last_id << ID_SCOPE_SHIFT;
  id_regist:
    name = strdup(name);
    st_add_direct(sym_tbl, (st_data_t)name, id);
    st_add_direct(sym_rev_tbl, id, (st_data_t)name);
    return id;
}

const char *
rb_id2name(id)
    ID id;
{
    const char *name;
    st_data_t data;

    if (id < tLAST_TOKEN) {
	int i;

	for (i=0; op_tbl[i].token; i++) {
	    if (op_tbl[i].token == id)
		return op_tbl[i].name;
	}
    }

    if (st_lookup(sym_rev_tbl, id, &data))
	return (char *)data;

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
    int cnt;

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

#ifdef YYMALLOC
#define HEAPCNT(n, size) ((n) * (size) / sizeof(YYSTYPE))
#define NEWHEAP() rb_node_newnode(NODE_ALLOCA, 0, (VALUE)parser_heap, 0)
#define ADD2HEAP(n, c, p) ((parser_heap = (n))->u1.node = (p), \
			   (n)->u3.cnt = (c), (p))

static void *
rb_parser_malloc(size)
    size_t size;
{
    size_t cnt = HEAPCNT(1, size);
    NODE *n = NEWHEAP();
    void *ptr = xmalloc(size);

    return ADD2HEAP(n, cnt, ptr);
}

static void *
rb_parser_calloc(nelem, size)
    size_t nelem, size;
{
    size_t cnt = HEAPCNT(nelem, size);
    NODE *n = NEWHEAP();
    void *ptr = xcalloc(nelem, size);

    return ADD2HEAP(n, cnt, ptr);
}

static void *
rb_parser_realloc(ptr, size)
    void *ptr;
    size_t size;
{
    NODE *n;
    size_t cnt = HEAPCNT(1, size);

    if (ptr && (n = parser_heap) != NULL) {
	do {
	    if (n->u1.node == ptr) {
		n->u1.node = ptr = xrealloc(ptr, size);
		if (n->u3.cnt) n->u3.cnt = cnt;
		return ptr;
	    }
	} while ((n = n->u2.node) != NULL);
    }
    n = NEWHEAP();
    ptr = xrealloc(ptr, size);
    return ADD2HEAP(n, cnt, ptr);
}

static void
rb_parser_free(ptr)
    void *ptr;
{
    NODE **prev = &parser_heap, *n;

    while ((n = *prev) != 0) {
	if (n->u1.node == ptr) {
	    *prev = n->u2.node;
	    rb_gc_force_recycle((VALUE)n);
	    break;
	}
	prev = &n->u2.node;
    }
    xfree(ptr);
}
#endif
