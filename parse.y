/************************************************

  parse.y -

  $Author$
  $Date$
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

%{

#define YYDEBUG 1
#include "ruby.h"
#include "env.h"
#include "node.h"
#include "st.h"
#include <stdio.h>
#include <errno.h>

#define ID_SCOPE_SHIFT 3
#define ID_SCOPE_MASK 0x07
#define ID_LOCAL    0x01
#define ID_INSTANCE 0x02
#define ID_GLOBAL   0x03
#define ID_ATTRSET  0x04
#define ID_CONST    0x05

#define is_id_notop(id) ((id)>LAST_TOKEN)
#define is_local_id(id) (is_id_notop(id)&&((id)&ID_SCOPE_MASK)==ID_LOCAL)
#define is_global_id(id) (is_id_notop(id)&&((id)&ID_SCOPE_MASK)==ID_GLOBAL)
#define is_instance_id(id) (is_id_notop(id)&&((id)&ID_SCOPE_MASK)==ID_INSTANCE)
#define is_attrset_id(id) (is_id_notop(id)&&((id)&ID_SCOPE_MASK)==ID_ATTRSET)
#define is_const_id(id) (is_id_notop(id)&&((id)&ID_SCOPE_MASK)==ID_CONST)

NODE *ruby_eval_tree_begin = 0;
NODE *ruby_eval_tree = 0;

char *ruby_sourcefile;		/* current source file */
int   ruby_sourceline;		/* current line no. */

static int yylex();
static int yyerror();

static enum lex_state {
    EXPR_BEG,			/* ignore newline, +/- is a sign. */
    EXPR_MID,			/* newline significant, +/- is a sign. */
    EXPR_END,			/* newline significant, +/- is a operator. */
    EXPR_PAREN,			/* almost like EXPR_END, `do' works as `{'. */
    EXPR_ARG,			/* newline significant, +/- is a operator. */
    EXPR_FNAME,			/* ignore newline, no reserved words. */
    EXPR_DOT,			/* right after `.' or `::', no reserved words. */
    EXPR_CLASS,			/* immediate after `class', no here document. */
} lex_state;

static int class_nest = 0;
static int in_single = 0;
static int compile_for_eval = 0;
static ID cur_mid = 0;

static NODE *cond();
static NODE *logop();

static NODE *newline_node();
static void fixpos();

static int value_expr();
static void void_expr();
static void void_stmts();

static NODE *block_append();
static NODE *list_append();
static NODE *list_concat();
static NODE *arg_concat();
static NODE *call_op();
static int in_defined = 0;

static NODE *arg_blk_pass();
static NODE *new_call();
static NODE *new_fcall();

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

static struct RVarmap *dyna_push();
static void dyna_pop();
static int dyna_in_block();

#define cref_push() NEW_CREF()
static void cref_pop();
static NODE *cur_cref;

static void top_local_init();
static void top_local_setup();
%}

%union {
    NODE *node;
    VALUE val;
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
	kDO2
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
	kALIAS
	kDEFINED
	klBEGIN
	klEND
	k__LINE__
	k__FILE__

%token <id>   tIDENTIFIER tFID tGVAR tIVAR tCONSTANT
%token <val>  tINTEGER tFLOAT tSTRING tXSTRING tREGEXP
%token <node> tDSTRING tDXSTRING tDREGEXP tNTH_REF tBACK_REF

%type <node> singleton
%type <val>  literal numeric
%type <node> compstmt stmts stmt expr arg primary command_call method_call
%type <node> if_tail opt_else case_body cases rescue ensure
%type <node> opt_call_args call_args ret_args args when_args
%type <node> aref_args opt_block_arg block_arg stmt_rhs
%type <node> mrhs opt_list superclass generic_call block_call var_ref
%type <node> f_arglist f_args f_optarg f_opt f_block_arg opt_f_block_arg
%type <node> array assoc_list assocs assoc undef_list backref
%type <node> block_var opt_block_var brace_block do_block lhs none
%type <node> mlhs mlhs_head mlhs_tail mlhs_basic mlhs_entry mlhs_item mlhs_node
%type <id>   variable symbol operation operation2 operation3
%type <id>   cname fname op f_rest_arg
%type <num>  f_arg
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
%token tLBRACK		/* [ */
%token tLBRACE		/* { */
%token tSTAR		/* * */
%token tAMPER		/* & */
%token tSYMBEG

/*
 *	precedence table
 */

%left  kIF_MOD kUNLESS_MOD kWHILE_MOD kUNTIL_MOD
%left  kOR kAND
%right kNOT
%nonassoc kDEFINED
%right '=' tOP_ASGN
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
%right '!' '~' tUPLUS tUMINUS
%right tPOW

%token LAST_TOKEN

%%
program		:  {
		        $<vars>$ = ruby_dyna_vars;
			lex_state = EXPR_BEG;
                        top_local_init();
			NEW_CREF0(); /* initialize constant c-ref */
			if ((VALUE)ruby_class == rb_cObject) class_nest = 0;
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
			cur_cref = 0;
			class_nest = 0;
		        ruby_dyna_vars = $<vars>1;
		    }

compstmt	: stmts opt_terms
		    {
			void_stmts($1);
			$$ = $1;
		    }

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
			$$ = $2;
		    }

stmt		: block_call
		| kALIAS fname {lex_state = EXPR_FNAME;} fname
		    {
			if (cur_mid || in_single)
			    yyerror("alias within method");
		        $$ = NEW_ALIAS($2, $4);
		    }
		| kALIAS tGVAR tGVAR
		    {
			if (cur_mid || in_single)
			    yyerror("alias within method");
		        $$ = NEW_VALIAS($2, $3);
		    }
		| kALIAS tGVAR tBACK_REF
		    {
			char buf[3];

			if (cur_mid || in_single)
			    yyerror("alias within method");
			sprintf(buf, "$%c", $3->nd_nth);
		        $$ = NEW_VALIAS($2, rb_intern(buf));
		    }
		| kALIAS tGVAR tNTH_REF
		    {
		        yyerror("can't make alias for the number variables");
		        $$ = 0;
		    }
		| kUNDEF undef_list
		    {
			if (cur_mid || in_single)
			    yyerror("undef within method");
			$$ = $2;
		    }
		| stmt kIF_MOD expr
		    {
			value_expr($3);
			$$ = NEW_IF(cond($3), $1, 0);
		        fixpos($$, $3);
		    }
		| stmt kUNLESS_MOD expr
		    {
			value_expr($3);
			$$ = NEW_UNLESS(cond($3), $1, 0);
		        fixpos($$, $3);
		    }
		| stmt kWHILE_MOD expr
		    {
			value_expr($3);
			if (nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_WHILE(cond($3), $1->nd_body, 0);
			}
			else {
			    $$ = NEW_WHILE(cond($3), $1, 1);
			}
		    }
		| stmt kUNTIL_MOD expr
		    {
			value_expr($3);
			if (nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_UNTIL(cond($3), $1->nd_body, 0);
			}
			else {
			    $$ = NEW_UNTIL(cond($3), $1, 1);
			}
		    }
		| klBEGIN
		    {
			if (cur_mid || in_single) {
			    yyerror("BEGIN in method");
			}
			local_push();
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
			if (compile_for_eval && (cur_mid || in_single)) {
			    yyerror("END in method; use at_exit");
			}

			$$ = NEW_ITER(0, NEW_POSTEXE(), $3);
		    }
		| lhs '=' stmt_rhs
		    {
			value_expr($3);
			$$ = node_assign($1, $3);
		    }
		| expr

expr		: mlhs '=' mrhs
		    {
			value_expr($3);
			$1->nd_value = $3;
			$$ = $1;
		    }
		| kRETURN ret_args
		    {
			value_expr($2);
			if (!compile_for_eval && !cur_mid && !in_single)
			    yyerror("return appeared outside of method");
			$$ = NEW_RETURN($2);
		    }
		| kYIELD ret_args
		    {
			value_expr($2);
			$$ = NEW_YIELD($2);
		    }
		| command_call
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
			value_expr($2);
			$$ = NEW_NOT(cond($2));
		    }
		| '!' command_call
		    {
			value_expr($2);
			$$ = NEW_NOT(cond($2));
		    }
		| arg

command_call	: operation call_args
		    {
			$$ = new_fcall($1, $2);
		        fixpos($$, $2);
		   }
		| primary '.' operation2 call_args
		    {
			value_expr($1);
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    }
		| primary tCOLON2 operation2 call_args
		    {
			value_expr($1);
			$$ = new_call($1, $3, $4);
		        fixpos($$, $1);
		    }
		| kSUPER call_args
		    {
			if (!compile_for_eval && !cur_mid && !in_single)
			    yyerror("super called outside of method");
			$$ = NEW_SUPER($2);
		        fixpos($$, $2);
		    }

mlhs		: mlhs_basic
		| tLPAREN mlhs_entry ')'
		    {
			$$ = $2;
		    }

mlhs_entry	: mlhs_basic
		| tLPAREN mlhs_entry ')'
		    {
			$$ = NEW_MASGN(NEW_LIST($2), 0);
		    }

mlhs_basic	: mlhs_head
		    {
			$$ = NEW_MASGN(NEW_LIST($1), 0);
		    }
		| mlhs_head tSTAR lhs
		    {
			$$ = NEW_MASGN(NEW_LIST($1), $3);
		    }
		| mlhs_head tSTAR
		    {
			$$ = NEW_MASGN(NEW_LIST($1), -1);
		    }
		| mlhs_head mlhs_tail
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2), 0);
		    }
		| mlhs_head mlhs_tail ',' tSTAR lhs
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2),$5);
		    }
		| mlhs_head mlhs_tail ',' tSTAR
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2),-1);
		    }
		| tSTAR mlhs_node
		    {
			$$ = NEW_MASGN(0, $2);
		    }
		| tSTAR
		    {
			$$ = NEW_MASGN(0, -1);
		    }

mlhs_item	: mlhs_node
		| tLPAREN mlhs_entry ')'
		    {
			$$ = $2;
		    }

mlhs_head	: mlhs_item ','
		    {
			$$ = $1;
		    }

mlhs_tail	: mlhs_item
		    {
			$$ = NEW_LIST($1);
		    }
		| mlhs_tail ',' mlhs_item
		    {
			$$ = list_append($1, $3);
		    }

mlhs_node	: variable
		    {
			$$ = assignable($1, 0);
		    }
		| primary '[' aref_args ']'
		    {
			$$ = aryset($1, $3);
		    }
		| primary '.' tIDENTIFIER
		    {
			$$ = attrset($1, $3);
		    }
		| backref
		    {
		        rb_backref_error($1);
			$$ = 0;
		    }

lhs		: variable
		    {
			$$ = assignable($1, 0);
		    }
		| primary '[' aref_args ']'
		    {
			$$ = aryset($1, $3);
		    }
		| primary '.' tIDENTIFIER
		    {
			$$ = attrset($1, $3);
		    }
		| backref
		    {
		        rb_backref_error($1);
			$$ = 0;
		    }

cname		: tIDENTIFIER
		    {
			yyerror("class/module name must be CONSTANT");
		    }
		| tCONSTANT

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

undef_list	: fname
		    {
			$$ = NEW_UNDEF($1);
		    }
		| undef_list ',' {lex_state = EXPR_FNAME;} fname
		    {
			$$ = block_append($1, NEW_UNDEF($4));
		    }

op		: tDOT2		{ $$ = tDOT2; }
		| '|'		{ $$ = '|'; }
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

reswords	: k__LINE__ | k__FILE__ | klBEGIN | klEND
		| kALIAS | kAND | kBEGIN | kBREAK | kCASE | kCLASS | kDEF
		| kDEFINED | kDO | kELSE | kELSIF | kEND | kENSURE | kFALSE
		| kFOR | kIF_MOD | kIN | kMODULE | kNEXT | kNIL | kNOT
		| kOR | kREDO | kRESCUE | kRETRY | kRETURN | kSELF | kSUPER
		| kTHEN | kTRUE | kUNDEF | kUNLESS_MOD | kUNTIL_MOD | kWHEN
		| kWHILE_MOD | kYIELD

arg		: lhs '=' arg
		    {
			value_expr($3);
			$$ = node_assign($1, $3);
		    }
		| variable tOP_ASGN {$$ = assignable($1, 0);} arg
		    {
			if ($2 == tOROP) {
			    $<node>3->nd_value = $4;
			    $$ = NEW_OP_ASGN_OR(gettable($1), $<node>3);
			}
			else if ($2 == tANDOP) {
			    $<node>3->nd_value = $4;
			    $$ = NEW_OP_ASGN_AND(gettable($1), $<node>3);
			}
			else {
			    $$ = $<node>3;
			    $$->nd_value = call_op(gettable($1), $2, 1, $4);
			}
			fixpos($$, $4);
		    }
		| primary '[' aref_args ']' tOP_ASGN arg
		    {
			NODE *args = NEW_LIST($6);

			list_append($3, NEW_NIL());
			list_concat(args, $3);
			if ($5 == tOROP) {
			    $5 = 0;
			}
			else if ($5 == tANDOP) {
			    $5 = 1;
			}
			$$ = NEW_OP_ASGN1($1, $5, args);
		        fixpos($$, $1);
		    }
		| primary '.' tIDENTIFIER tOP_ASGN arg
		    {
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| primary '.' tCONSTANT tOP_ASGN arg
		    {
			if ($4 == tOROP) {
			    $4 = 0;
			}
			else if ($4 == tANDOP) {
			    $4 = 1;
			}
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| backref tOP_ASGN arg
		    {
		        rb_backref_error($1);
			$$ = 0;
		    }
		| arg tDOT2 arg
		    {
			$$ = NEW_DOT2($1, $3);
		    }
		| arg tDOT3 arg
		    {
			$$ = NEW_DOT3($1, $3);
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
		| tUPLUS arg
		    {
			$$ = call_op($2, tUPLUS, 0);
		    }
		| tUMINUS arg
		    {
		        $$ = call_op($2, tUMINUS, 0);
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
			value_expr($2);
			$$ = NEW_NOT(cond($2));
		    }
		| '~' arg
		    {
			$$ = call_op($2, '~', 0);
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
			value_expr($1);
			$$ = NEW_IF(cond($1), $3, $5);
		        fixpos($$, $1);
		    }
		| primary
		    {
			$$ = $1;
		    }

aref_args	: opt_call_args
		    {
			if ($1 && nd_type($1) == NODE_BLOCK_PASS) {
			    rb_compile_error("block argument should not be given");
			}
			$$ = $1;
		    }

opt_call_args	: none
		| call_args opt_nl

call_args	: command_call
		    {
			value_expr($1);
			$$ = NEW_LIST($1);
		    }
		| args ','
		    {
			$$ = $1;
		    }
		| args opt_block_arg
		    {
			$$ = arg_blk_pass($1, $2);
		    }
		| args ',' tSTAR arg opt_block_arg
		    {
			$$ = arg_concat($1, $4);
			$$ = arg_blk_pass($$, $5);
		    }
		| assocs ','
		    {
			$$ = NEW_LIST(NEW_HASH($1));
		    }
		| assocs opt_block_arg
		    {
			$$ = NEW_LIST(NEW_HASH($1));
			$$ = arg_blk_pass($$, $2);
		    }
		| assocs ',' tSTAR arg opt_block_arg
		    {
			$$ = arg_concat(NEW_LIST(NEW_HASH($1)), $4);
			$$ = arg_blk_pass($$, $5);
		    }
		| args ',' assocs opt_block_arg
		    {
			$$ = list_append($1, NEW_HASH($3));
			$$ = arg_blk_pass($$, $4);
		    }
		| args ',' assocs ','
		    {
			$$ = list_append($1, NEW_HASH($3));
		    }
		| args ',' assocs ',' tSTAR arg opt_block_arg
		    {
			$$ = arg_concat(list_append($1, NEW_HASH($3)), $6);
			$$ = arg_blk_pass($$, $7);
		    }
		| tSTAR arg opt_block_arg
		    {
			value_expr($2);
			$$ = arg_blk_pass(NEW_RESTARGS($2), $3);
		    }
		| block_arg

block_arg	: tAMPER arg
		    {
			value_expr($2);
			$$ = NEW_BLOCK_PASS($2);
		    }

opt_block_arg	: ',' block_arg
		    {
			$$ = $2;
		    }
		| none

opt_list	: args
		| none

args 		: arg
		    {
			value_expr($1);
			$$ = NEW_LIST($1);
		    }
		| args ',' arg
		    {
			value_expr($3);
			$$ = list_append($1, $3);
		    }

mrhs		: args
		    {
			if ($1 &&
		            nd_type($1) == NODE_ARRAY &&
		            $1->nd_next == 0)
			{
			    $$ = $1->nd_head;
			}
			else {
			    $$ = $1;
			}
		    }
		| args ',' tSTAR arg
		    {
			value_expr($4);
			$$ = arg_concat($1, $4);
		    }
		| tSTAR arg
		    {
			value_expr($2);
			$$ = $2;
		    }

ret_args	: call_args
		    {
			$$ = $1;
			if ($1) {
			    if (nd_type($1) == NODE_ARRAY &&
				$1->nd_next == 0) {
				$$ = $1->nd_head;
			    }
			    else if (nd_type($1) == NODE_BLOCK_PASS) {
				rb_compile_error("block argument should not be given");
			    }
			}
		    }

array		: none
		| args trailer

primary		: literal
		    {
			$$ = NEW_LIT($1);
		    }
		| primary tCOLON2 tCONSTANT
		    {
			value_expr($1);
			$$ = NEW_COLON2($1, $3);
		    }
		| tCOLON3 cname
		    {
			$$ = NEW_COLON3($2);
		    }
		| tSTRING
		    {
			$$ = NEW_STR($1);
		    }
		| tDSTRING
		| tXSTRING
		    {
			$$ = NEW_XSTR($1);
		    }
		| tDXSTRING
		| tDREGEXP
		| var_ref
		| backref
		| primary '[' aref_args ']'
		    {
			value_expr($1);
			$$ = NEW_CALL($1, tAREF, $3);
		    }
		| tLBRACK array ']'
		    {
			if ($2 == 0)
			    $$ = NEW_ZARRAY(); /* zero length array*/
			else {
			    $$ = $2;
			}
		    }
		| tLBRACE assoc_list '}'
		    {
			$$ = NEW_HASH($2);
		    }
		| kRETURN '(' ret_args ')'
		    {
			if (!compile_for_eval && !cur_mid && !in_single)
			    yyerror("return appeared outside of method");
			value_expr($3);
			$$ = NEW_RETURN($3);
		    }
		| kRETURN '(' ')'
		    {
			if (!compile_for_eval && !cur_mid && !in_single)
			    yyerror("return appeared outside of method");
			$$ = NEW_RETURN(0);
		    }
		| kRETURN
		    {
			if (!compile_for_eval && !cur_mid && !in_single)
			    yyerror("return appeared outside of method");
			$$ = NEW_RETURN(0);
		    }
		| kYIELD '(' ret_args ')'
		    {
			value_expr($3);
			$$ = NEW_YIELD($3);
		    }
		| kYIELD '(' ')'
		    {
			$$ = NEW_YIELD(0);
		    }
		| kYIELD
		    {
			$$ = NEW_YIELD(0);
		    }
		| kDEFINED opt_nl '(' {in_defined = 1;} expr ')'
		    {
		        in_defined = 0;
			$$ = NEW_DEFINED($5);
		    }
		| tFID
		    {
			$$ = NEW_VCALL($1);
		    }
		| operation brace_block
		    {
			$2->nd_iter = NEW_FCALL($1, 0);
			$$ = $2;
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
		| kIF expr then
		  compstmt
		  if_tail
		  kEND
		    {
			value_expr($2);
			$$ = NEW_IF(cond($2), $4, $5);
		        fixpos($$, $2);
		    }
		| kUNLESS expr then
		  compstmt
		  opt_else
		  kEND
		    {
			value_expr($2);
			$$ = NEW_UNLESS(cond($2), $4, $5);
		        fixpos($$, $2);
		    }
		| kWHILE expr do
		  compstmt
		  kEND
		    {
			value_expr($2);
			$$ = NEW_WHILE(cond($2), $4, 1);
		        fixpos($$, $2);
		    }
		| kUNTIL expr do
		  compstmt
		  kEND
		    {
			value_expr($2);
			$$ = NEW_UNTIL(cond($2), $4, 1);
		        fixpos($$, $2);
		    }
		| kCASE compstmt
		  case_body
		  kEND
		    {
			value_expr($2);
			$$ = NEW_CASE($2, $3);
		        fixpos($$, $2);
		    }
		| kFOR block_var kIN expr do
		  compstmt
		  kEND
		    {
			value_expr($2);
			$$ = NEW_FOR($2, $4, $6);
		        fixpos($$, $2);
		    }
		| kBEGIN
		  compstmt
		  rescue
		  opt_else
		  ensure
		  kEND
		    {
			if (!$3 && !$4 && !$5)
			    $$ = NEW_BEGIN($2);
			else {
			    if ($3) $2 = NEW_RESCUE($2, $3, $4);
			    else if ($4) {
				rb_warn("else without rescue is useless");
				$2 = block_append($2, $4);
			    }
			    if ($5) $2 = NEW_ENSURE($2, $5);
			    $$ = $2;
			}
		        fixpos($$, $2);
		    }
		| tLPAREN compstmt ')'
		    {
			$$ = $2;
		    }
		| kCLASS cname superclass
		    {
			if (cur_mid || in_single)
			    yyerror("class definition in method body");

			class_nest++;
			cref_push();
			local_push();
		    }
		  compstmt
		  kEND
		    {
		        $$ = NEW_CLASS($2, $5, $3);
		        fixpos($$, $3);
		        local_pop();
			cref_pop();
			class_nest--;
		    }
		| kCLASS tLSHFT expr term
		    {
			class_nest++;
			cref_push();
			local_push();
		    }
		  compstmt
		  kEND
		    {
		        $$ = NEW_SCLASS($3, $6);
		        fixpos($$, $3);
		        local_pop();
			cref_pop();
			class_nest--;
		    }
		| kMODULE cname
		    {
			if (cur_mid || in_single)
			    yyerror("module definition in method body");
			class_nest++;
			cref_push();
			local_push();
		    }
		  compstmt
		  kEND
		    {
		        $$ = NEW_MODULE($2, $4);
		        fixpos($$, $4);
		        local_pop();
			cref_pop();
			class_nest--;
		    }
		| kDEF fname
		    {
			if (cur_mid || in_single)
			    yyerror("nested method definition");
			cur_mid = $2;
			local_push();
		    }
		  f_arglist
		  compstmt
		  kEND
		    {
		        /* NOEX_PRIVATE for toplevel */
			$$ = NEW_DEFN($2, $4, $5, class_nest?0:1);
		        fixpos($$, $4);
		        local_pop();
			cur_mid = 0;
		    }
		| kDEF singleton dot_or_colon {lex_state = EXPR_FNAME;} fname
		    {
			value_expr($2);
			in_single++;
			local_push();
		        lex_state = EXPR_END; /* force for args */
		    }
		  f_arglist
		  compstmt
		  kEND
		    {
			$$ = NEW_DEFS($2, $5, $7, $8);
		        fixpos($$, $2);
		        local_pop();
			in_single--;
		    }
		| kBREAK
		    {
			$$ = NEW_BREAK();
		    }
		| kNEXT
		    {
			$$ = NEW_NEXT();
		    }
		| kREDO
		    {
			$$ = NEW_REDO();
		    }
		| kRETRY
		    {
			$$ = NEW_RETRY();
		    }

then		: term
		| kTHEN
		| term kTHEN

do		: term
		| kDO

if_tail		: opt_else
		| kELSIF expr then
		  compstmt
		  if_tail
		    {
			value_expr($2);
			$$ = NEW_IF(cond($2), $4, $5);
		        fixpos($$, $2);
		    }

opt_else	: none
		| kELSE compstmt
		    {
			$$ = $2;
		    }

block_var	: lhs
		| mlhs

opt_block_var	: none
		| '|' /* none */ '|'
		    {
			$$ = 0;
		    }
		| tOROP
		    {
			$$ = 0;
		    }
		| '|' block_var '|'
		    {
			$$ = $2;
		    }

do_block	: kDO
		    {
		        $<vars>$ = dyna_push();
		    }
		  opt_block_var
		  compstmt
		  kEND
		    {
			$$ = NEW_ITER($3, 0, $4);
		        fixpos($$, $3?$3:$4);
			dyna_pop($<vars>2);
		    }

brace_block	: '{'
		    {
		        $<vars>$ = dyna_push();
		    }
		  opt_block_var
		  compstmt '}'
		    {
			$$ = NEW_ITER($3, 0, $4);
		        fixpos($$, $3?$3:$4);
			dyna_pop($<vars>2);
		    }
		| kDO2
		    {
		        $<vars>$ = dyna_push();
		    }
		  opt_block_var
		  compstmt
		  kEND
		    {
			$$ = NEW_ITER($3, 0, $4);
		        fixpos($$, $3?$3:$4);
			dyna_pop($<vars>2);
		    }


generic_call	: tIDENTIFIER
		    {
			$$ = NEW_VCALL($1);
		    }
		| tCONSTANT
		    {
			$$ = NEW_VCALL($1);
		    }
		| tFID
		    {
			$$ = NEW_VCALL($1);
		    }
		| method_call
		| command_call

block_call	: generic_call do_block
		    {
			if ($1 && nd_type($1) == NODE_BLOCK_PASS) {
			    rb_compile_error("both block arg and actual block given");
			}
			$2->nd_iter = $1;
			$$ = $2;
		        fixpos($$, $2);
		    }

method_call	: operation '(' opt_call_args close_paren
		    {
			$$ = new_fcall($1, $3);
		        fixpos($$, $3);
		    }
		| primary '.' operation2 '(' opt_call_args close_paren
		    {
			value_expr($1);
			$$ = new_call($1, $3, $5);
		        fixpos($$, $1);
		    }
		| primary '.' operation2
		    {
			value_expr($1);
			$$ = new_call($1, $3, 0);
		        fixpos($$, $1);
		    }
		| primary tCOLON2 operation2 '(' opt_call_args close_paren
		    {
			value_expr($1);
			$$ = new_call($1, $3, $5);
		        fixpos($$, $1);
		    }
		| primary tCOLON2 operation3
		    {
			value_expr($1);
			$$ = new_call($1, $3, 0);
		    }
		| kSUPER '(' opt_call_args close_paren
		    {
			if (!compile_for_eval && !cur_mid &&
		            !in_single && !in_defined)
			    yyerror("super called outside of method");
			$$ = NEW_SUPER($3);
		    }
		| kSUPER
		    {
			if (!compile_for_eval && !cur_mid &&
		            !in_single && !in_defined)
			    yyerror("super called outside of method");
			$$ = NEW_ZSUPER();
		    }

close_paren	: ')'
		    {
			lex_state = EXPR_PAREN;
		    }

stmt_rhs	: block_call
		| command_call

case_body	: kWHEN when_args then
		  compstmt
		  cases
		    {
			$$ = NEW_WHEN($2, $4, $5);
		    }

when_args	: args
		| args ',' tSTAR arg
		    {
			value_expr($4);
			$$ = list_append($1, NEW_WHEN($4, 0, 0));
		    }
		| tSTAR arg
		    {
			value_expr($2);
			$$ = NEW_LIST(NEW_WHEN($2, 0, 0));
		    }

cases		: opt_else
		| case_body

rescue		: kRESCUE opt_list do
		  compstmt
		  rescue
		    {
			$$ = NEW_RESBODY($2, $4, $5);
		        fixpos($$, $2?$2:$4);
		    }
		| none

ensure		: none
		| kENSURE compstmt
		    {
			$$ = $2;
		    }

literal		: numeric
		| tSYMBEG symbol
		    {
		        lex_state = EXPR_END;
			$$ = INT2FIX($2);
		    }
		| tREGEXP

symbol		: fname
		| tIVAR
		| tGVAR

numeric		: tINTEGER
		| tFLOAT

variable	: tIDENTIFIER
		| tIVAR
		| tGVAR
		| tCONSTANT
		| kNIL {$$ = kNIL;}
		| kSELF {$$ = kSELF;}
		| kTRUE {$$ = kTRUE;}
		| kFALSE {$$ = kFALSE;}
		| k__FILE__ {$$ = k__FILE__;}
		| k__LINE__ {$$ = k__LINE__;}

var_ref		: variable
		    {
			$$ = gettable($1);
		    }

backref		: tNTH_REF
		| tBACK_REF

superclass	: term
		    {
			$$ = 0;
		    }
		| '<'
		    {
			lex_state = EXPR_BEG;
		    }
		  expr term
		    {
			$$ = $3;
		    }
		| error term {yyerrok; $$ = 0;}

f_arglist	: '(' f_args opt_nl ')'
		    {
			$$ = $2;
			lex_state = EXPR_BEG;
		    }
		| f_args term
		    {
			$$ = $1;
		    }

f_args		: f_arg ',' f_optarg ',' f_rest_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS($1, $3, $5), $6);
		    }
		| f_arg ',' f_optarg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS($1, $3, -1), $4);
		    }
		| f_arg ',' f_rest_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS($1, 0, $3), $4);
		    }
		| f_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS($1, 0, -1), $2);
		    }
		| f_optarg ',' f_rest_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS(0, $1, $3), $4);
		    }
		| f_optarg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS(0, $1, -1), $2);
		    }
		| f_rest_arg opt_f_block_arg
		    {
			$$ = block_append(NEW_ARGS(0, 0, $1), $2);
		    }
		| f_block_arg
		    {
			$$ = block_append(NEW_ARGS(0, 0, -1), $1);
		    }
		| /* none */
		    {
			$$ = NEW_ARGS(0, 0, -1);
		    }

f_arg		: tIDENTIFIER
		    {
			if (!is_local_id($1))
			    yyerror("formal argument must be local variable");
			local_cnt($1);
			$$ = 1;
		    }
		| f_arg ',' tIDENTIFIER
		    {
			if (!is_local_id($3))
			    yyerror("formal argument must be local variable");
			local_cnt($3);
			$$ += 1;
		    }

f_opt		: tIDENTIFIER '=' arg
		    {
			if (!is_local_id($1))
			    yyerror("formal argument must be local variable");
			$$ = assignable($1, $3);
		    }

f_optarg	: f_opt
		    {
			$$ = NEW_BLOCK($1);
			$$->nd_end = $$;
		    }
		| f_optarg ',' f_opt
		    {
			$$ = block_append($1, $3);
		    }

f_rest_arg	: tSTAR tIDENTIFIER
		    {
			if (!is_local_id($2))
			    yyerror("rest argument must be local variable");
			$$ = local_cnt($2);
		    }
		| tSTAR
		    {
			$$ = -2;
		    }

f_block_arg	: tAMPER tIDENTIFIER
		    {
			$$ = NEW_BLOCK_ARG($2);
		    }

opt_f_block_arg	: ',' f_block_arg
		    {
			$$ = $2;
		    }
		| none

singleton	: var_ref
		    {
			if (nd_type($1) == NODE_SELF) {
			    $$ = NEW_SELF();
			}
			else if (nd_type($1) == NODE_NIL) {
			    yyerror("Can't define single method for nil.");
			    $$ = 0;
			}
			else {
			    $$ = $1;
			}
		    }
		| '(' {lex_state = EXPR_BEG;} expr opt_nl ')'
		    {
			switch (nd_type($3)) {
			  case NODE_STR:
			  case NODE_DSTR:
			  case NODE_XSTR:
			  case NODE_DXSTR:
			  case NODE_DREGX:
			  case NODE_LIT:
			  case NODE_ARRAY:
			  case NODE_ZARRAY:
			    yyerror("can't define single method for literals.");
			  default:
			    break;
			}
			$$ = $3;
		    }

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

assocs		: assoc
		| assocs ',' assoc
		    {
			$$ = list_concat($1, $3);
		    }

assoc		: arg tASSOC arg
		    {
			$$ = list_append(NEW_LIST($1), $3);
		    }

operation	: tIDENTIFIER
		| tCONSTANT
		| tFID

operation2	: tIDENTIFIER
		| tCONSTANT
		| tFID
		| op

operation3	: tIDENTIFIER
		| tFID
		| op

dot_or_colon	: '.'
		| tCOLON2

opt_terms	: /* none */
		| terms

opt_nl		: /* none */
		| '\n'

trailer		: /* none */
		| '\n'
		| ','

term		: ';' {yyerrok;}
		| '\n'

terms		: term
		| terms ';' {yyerrok;}

none		: /* none */
		    {
			$$ = 0;
		    }
%%
#include <ctype.h>
#include <sys/types.h>
#include "regex.h"
#include "util.h"
#ifndef strdup
char *strdup();
#endif

#define is_identchar(c) (((int)(c))!=-1&&(ISALNUM(c) || (c) == '_' || ismbchar(c)))

static char *tokenbuf = NULL;
static int   tokidx, toksiz = 0;

static NODE *rb_str_extend();

#define LEAVE_BS 1

static VALUE (*lex_gets)();	/* gets function */
static VALUE lex_input;		/* non-nil if File */
static VALUE lex_lastline;	/* gc protect */
static char *lex_pbeg;
static char *lex_p;
static char *lex_pend;

static int
yyerror(msg)
    char *msg;
{
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

    return 0;
}

static int heredoc_end;

int ruby_in_compile = 0;
int ruby__end__seen;

static NODE*
yycompile(f)
    char *f;
{
    int n;

    ruby__end__seen = 0;
    ruby_eval_tree = 0;
    heredoc_end = 0;
    ruby_sourcefile = f;
    ruby_in_compile = 1;
    n = yyparse();
    compile_for_eval = 0;
    ruby_in_compile = 0;
    class_nest = 0;
    in_single = 0;
    cur_mid = 0;
    if (n == 0) return ruby_eval_tree;

    return 0;
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
    compile_for_eval = 1;

    return yycompile(f);
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

    return yycompile(strdup(f));
}

static int
nextc()
{
    int c;

    if (lex_p == lex_pend) {
	if (lex_input) {
	    VALUE v = (*lex_gets)(lex_input);

	    if (NIL_P(v)) return -1;
	    if (heredoc_end > 0) {
		ruby_sourceline = heredoc_end;
		heredoc_end = 0;
	    }
	    ruby_sourceline++;
	    lex_pbeg = lex_p = RSTRING(v)->ptr;
	    lex_pend = lex_p + RSTRING(v)->len;
	    if (strncmp(lex_pbeg, "__END__", 7) == 0 && lex_pbeg[7] == '\n') {
		ruby__end__seen = 1;
		lex_lastline = 0;
		return -1;
	    }
	    lex_lastline = v;
	}
	else {
	    lex_lastline = 0;
	    return -1;
	}
    }
    c = (unsigned char)*lex_p++;

    return c;
}

static void
pushback(c)
    int c;
{
    if (c == -1) return;
    lex_p--;
}

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
	    char buf[3];
	    int i;

	    pushback(c);
	    for (i=0; i<3; i++) {
		c = nextc();
		if (c == -1) goto eof;
		if (c < '0' || '7' < c) {
		    pushback(c);
		    break;
		}
		buf[i] = c;
	    }
	    c = scan_oct(buf, i, &i);
	}
	return c;

      case 'x':	/* hex constant */
	{
	    char buf[2];
	    int i;

	    for (i=0; i<2; i++) {
		int cc = nextc();

		if (cc == -1) goto eof;
		buf[i] = cc;
		if (!ISXDIGIT(buf[i])) {
		    pushback(buf[i]);
		    break;
		}
	    }
	    c = scan_hex(buf, i, &i);
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
parse_regx(term, paren)
    int term;
{
    register int c;
    char kcode = 0;
    int once = 0;
    int nest = 0;
    int options = 0;
    int in_brack = 0;
    int re_start = ruby_sourceline;
    NODE *list = 0;

    newtok();
    while ((c = nextc()) != -1) {
	if ((!in_brack && c == term) || nest > 0) {
	    goto regx_end;
	}

	switch (c) {
	  case '[':
	    in_brack = 1;
	    break;
	  case ']':
	    in_brack = 0;
	    break;

	  case '#':
	    list = rb_str_extend(list, term);
	    if (list == (NODE*)-1) return 0;
	    continue;

	  case '\\':
	    switch (c = nextc()) {
	      case -1:
		ruby_sourceline = re_start;
		rb_compile_error("unterminated regexp meets end of file");
		return 0;

	      case '\n':
		break;

	      case '\\':
	      case '^':
	      case 's':
		tokadd('\\');
		tokadd(c);
		break;

	      case '1': case '2': case '3':
	      case '4': case '5': case '6':
	      case '7': case '8': case '9':
	      case '0': case 'x':
		tokadd('\\');
		tokadd(c);
		break;

	      case 'b':
		if (!in_brack) {
		    tokadd('\\');
		    tokadd('b');
		    break;
		}
		/* fall through */
	      default:
		if (paren)  {
		    if (c == paren) nest++;
		    if (c == term) nest--;
		}
		if (c == term) {
		    tokadd(c);
		}
		else {
#if 0
		    int c1;
		    pushback(c);
		    c1 = read_escape();
		    if (c1 != c) {
			tokadd(c1);
		    }
		    else {
			tokadd('\\');
			tokadd(c);
		    }
#else
		    tokadd('\\');
		    tokadd(c);
#endif
		}
	    }
	    continue;

	  case -1:
	    rb_compile_error("unterminated regexp");
	    return 0;

	  default:
	    if (ismbchar(c)) {
		int i, len = mbclen(c)-1;

		for (i = 0; i < len; i++) {
		    tokadd(c);
		    c = nextc();
		}
	    }
	    break;

	  regx_end:
	    for (;;) {
		switch (c = nextc()) {
		  case 'i':
		    options |= RE_OPTION_IGNORECASE;
		    break;
		  case 'x':
		    options |= RE_OPTION_EXTENDED;
		    break;
		  case 'p':
		    options |= RE_OPTION_POSIXLINE;
		    break;
		  case 'o':
		    once = 1;
		    break;
		  case 'n':
		    kcode = 8;
		    break;
		  case 'e':
		    kcode = 16;
		    break;
		  case 's':
		    kcode = 24;
		    break;
		  case 'u':
		    kcode = 32;
		    break;
		  default:
		    pushback(c);
		    goto end_options;
		}
	    }

	  end_options:
	    tokfix();
	    lex_state = EXPR_END;
	    if (list) {
		nd_set_line(list, re_start);
		if (toklen() > 0) {
		    VALUE ss = rb_str_new(tok(), toklen());
		    list_append(list, NEW_STR(ss));
		}
		nd_set_type(list, once?NODE_DREGX_ONCE:NODE_DREGX);
		list->nd_cflag = options | kcode;
		yylval.node = list;
		return tDREGEXP;
	    }
	    else {
		yylval.val = rb_reg_new(tok(), toklen(), options | kcode);
		return tREGEXP;
	    }
	}
	tokadd(c);
    }
    rb_compile_error("unterminated regexp");
    return 0;
}

static int parse_qstring _((int,int));

static int
parse_string(func, term, paren)
    int func, term, paren;
{
    int c;
    NODE *list = 0;
    int strstart;
    int nest = 0;

    if (func == '\'') {
	return parse_qstring(term, paren);
    }
    if (func == 0) {		/* read 1 line for heredoc */
				/* -1 for chomp */
	yylval.val = rb_str_new(lex_pbeg, lex_pend - lex_pbeg - 1);
	lex_p = lex_pend;
	return tSTRING;
    }
    strstart = ruby_sourceline;
    newtok();
    while ((c = nextc()) != term || nest > 0) {
	if (c == -1) {
	  unterm_str:
	    ruby_sourceline = strstart;
	    rb_compile_error("unterminated string meets end of file");
	    return 0;
	}
	if (ismbchar(c)) {
	    int i, len = mbclen(c)-1;

	    for (i = 0; i < len; i++) {
		tokadd(c);
		c = nextc();
	    }
	}
	else if (c == '#') {
	    list = rb_str_extend(list, term);
	    if (list == (NODE*)-1) goto unterm_str;
	    continue;
	}
	else if (c == '\\') {
	    c = nextc();
	    if (c == '\n')
		continue;
	    if (c == term) {
		tokadd(c);
	    }
	    else {
                pushback(c);
                if (func != '"') tokadd('\\');
                tokadd(read_escape());
  	    }
	    continue;
	}
	if (paren) {
	    if (c == paren) nest++;
	    if (c == term) {
		nest--;
		if (nest == 0) break;
	    }
	}
	tokadd(c);
    }

    tokfix();
    lex_state = EXPR_END;

    if (list) {
	nd_set_line(list, strstart);
	if (toklen() > 0) {
	    VALUE ss = rb_str_new(tok(), toklen());
	    list_append(list, NEW_STR(ss));
	}
	yylval.node = list;
	if (func == '`') {
	    nd_set_type(list, NODE_DXSTR);
	    return tDXSTRING;
	}
	else {
	    return tDSTRING;
	}
    }
    else {
	yylval.val = rb_str_new(tok(), toklen());
	return (func == '`') ? tXSTRING : tSTRING;
    }
}

static int
parse_qstring(term, paren)
    int term, paren;
{
    int strstart;
    int c;
    int nest = 0;

    strstart = ruby_sourceline;
    newtok();
    while ((c = nextc()) != term || nest > 0) {
	if (c == -1) {
	    ruby_sourceline = strstart;
	    rb_compile_error("unterminated string meets end of file");
	    return 0;
	}
	if (ismbchar(c)) {
	    int i, len = mbclen(c)-1;

	    for (i = 0; i < len; i++) {
		tokadd(c);
		c = nextc();
	    }
	}
	else if (c == '\\') {
	    c = nextc();
	    switch (c) {
	      case '\n':
		continue;

	      case '\\':
		c = '\\';
		break;

	      case '\'':
		if (term == '\'') {
		    c = '\'';
		    break;
		}
		/* fall through */
	      default:
		tokadd('\\');
	    }
	}
	if (paren) {
	    if (c == paren) nest++;
	    if (c == term) {
		nest--;
		if (nest == 0) break;
	    }
	}
	tokadd(c);
    }

    tokfix();
    yylval.val = rb_str_new(tok(), toklen());
    lex_state = EXPR_END;
    return tSTRING;
}

static int
parse_quotedword(term, paren)
    int term, paren;
{
    if (parse_qstring(term, paren) == 0) return 0;
    yylval.node = NEW_CALL(NEW_STR(yylval.val), rb_intern("split"), 0);
    return tDSTRING;
}

static int
here_document(term, indent)
    char term;
    int indent;
{
    int c;
    char *eos, *p;
    int len;
    VALUE str;
    volatile VALUE line = 0;
    VALUE lastline_save;
    int offset_save;
    NODE *list = 0;
    int linesave = ruby_sourceline;

    newtok();
    switch (term) {
      case '\'':
      case '"':
      case '`':
	while ((c = nextc()) != term) {
	    tokadd(c);
	}
	if (term == '\'') term = 0;
	break;

      default:
	c = term;
	term = '"';
	if (!is_identchar(c)) {
	    rb_warn("use of bare << to mean <<\"\" is deprecated");
	    break;
	}
	while (is_identchar(c)) {
	    tokadd(c);
	    c = nextc();
	}
	pushback(c);
	break;
    }
    tokfix();
    lastline_save = lex_lastline;
    offset_save = lex_p - lex_pbeg;
    eos = strdup(tok());
    len = strlen(eos);

    str = rb_str_new(0,0);
    for (;;) {
	lex_lastline = line = (*lex_gets)(lex_input);
	if (NIL_P(line)) {
	  error:
	    ruby_sourceline = linesave;
	    rb_compile_error("can't find string \"%s\" anywhere before EOF", eos);
		free(eos);
		return 0;
	}
	ruby_sourceline++;
	p = RSTRING(line)->ptr;
	if (indent) {
	    while (*p && (*p == ' ' || *p == '\t')) {
		p++;
	    }
	}
	if (strncmp(eos, p, len) == 0 && p[len] == '\n') {
	    break;
	}

	lex_pbeg = lex_p = RSTRING(line)->ptr;
	lex_pend = lex_p + RSTRING(line)->len;
#if 0
	if (indent) {
	    while (*lex_p && *lex_p == '\t') {
		lex_p++;
	    }
	}
#endif
      retry:
	switch (parse_string(term, '\n', '\n')) {
	  case tSTRING:
	  case tXSTRING:
	    rb_str_cat(yylval.val, "\n", 1);
	    if (!list) {
	        rb_str_cat(str, RSTRING(yylval.val)->ptr, RSTRING(yylval.val)->len);
	    }
	    else {
		list_append(list, NEW_STR(yylval.val));
	    }
	    break;
	  case tDSTRING:
	  case tDXSTRING:
	    list_append(yylval.node, NEW_STR(rb_str_new2("\n")));
	    nd_set_type(yylval.node, NODE_STR);
	    if (!list) list = NEW_DSTR(str);
	    yylval.node = NEW_LIST(yylval.node);
	    yylval.node->nd_next = yylval.node->nd_head->nd_next;
	    list_concat(list, yylval.node);
	    break;

	  case 0:
	    goto error;
	}
	if (lex_p != lex_pend) {
	    goto retry;
	}
    }
    free(eos);
    lex_lastline = lastline_save;
    lex_pbeg = RSTRING(lex_lastline)->ptr;
    lex_pend = lex_pbeg + RSTRING(lex_lastline)->len;
    lex_p = lex_pbeg + offset_save;

    lex_state = EXPR_END;
    heredoc_end = ruby_sourceline;
    ruby_sourceline = linesave;

    if (list) {
	nd_set_line(list, linesave+1);
	yylval.node = list;
    }
    switch (term) {
      case '\0':
      case '\'':
      case '"':
	if (list) return tDSTRING;
	yylval.val = str;
	return tSTRING;
      case '`':
	if (list) return tDXSTRING;
	return tXSTRING;
    }
    return 0;
}

#include "lex.c"

static void
arg_ambiguous()
{
    rb_warning("ambiguous first argument; make sure");
}

#ifndef strtod
double strtod ();
#endif

static int
yylex()
{
    register int c;
    int space_seen = 0;
    struct kwtable *kw;

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
	space_seen = 1;
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
	    goto retry;
	  default:
	    break;
	}
	lex_state = EXPR_BEG;
	return '\n';

      case '*':
	if ((c = nextc()) == '*') {
	    lex_state = EXPR_BEG;
	    if (nextc() == '=') {
		yylval.id = tPOW;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tPOW;
	}
	if (c == '=') {
	    yylval.id = '*';
	    lex_state = EXPR_BEG;
	    return tOP_ASGN;
	}
	pushback(c);
	if (lex_state == EXPR_ARG && space_seen && !ISSPACE(c)){
	    lex_state = EXPR_BEG;
	    return tSTAR;
	}
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    lex_state = EXPR_BEG;
	    return tSTAR;
	}
	lex_state = EXPR_BEG;
	return '*';

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
	if (lex_p == lex_pbeg + 1) {
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
		    if (strncmp(lex_p, "end", 3) == 0 && ISSPACE(lex_p[3])) {
			break;
		    }
		}
		lex_p = lex_pend;
		goto retry;
	    }
	}

	lex_state = EXPR_BEG;
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
	    lex_state != EXPR_END && lex_state != EXPR_PAREN && 
	    lex_state != EXPR_CLASS &&
	    (lex_state != EXPR_ARG || space_seen)) {
 	    int c2 = nextc();
	    int indent = 0;
	    if (c2 == '-') {
		indent = 1;
		c2 = nextc();
	    }
	    if (!ISSPACE(c2) && (strchr("\"'`", c2) || is_identchar(c2))) {
		return here_document(c2, indent);
	    }
	    pushback(c2);
	}
	lex_state = EXPR_BEG;
	if (c == '=') {
	    if ((c = nextc()) == '>') {
		return tCMP;
	    }
	    pushback(c);
	    return tLEQ;
	}
	if (c == '<') {
	    if (nextc() == '=') {
		yylval.id = tLSHFT;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tLSHFT;
	}
	pushback(c);
	return '<';

      case '>':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    return tGEQ;
	}
	if (c == '>') {
	    if ((c = nextc()) == '=') {
		yylval.id = tRSHFT;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tRSHFT;
	}
	pushback(c);
	return '>';

      case '"':
	return parse_string(c,c,c);
      case '`':
	if (lex_state == EXPR_FNAME) return c;
	if (lex_state == EXPR_DOT) return c;
	return parse_string(c,c,c);

      case '\'':
	return parse_qstring(c,0);

      case '?':
	if (lex_state == EXPR_END || lex_state == EXPR_PAREN) {
	    lex_state = EXPR_BEG;
	    return '?';
	}
	c = nextc();
	if (lex_state == EXPR_ARG && ISSPACE(c)){
	    pushback(c);
	    lex_state = EXPR_BEG;
	    return '?';
	}
	if (c == '\\') {
	    c = read_escape();
	}
	c &= 0xff;
	yylval.val = INT2FIX(c);
	lex_state = EXPR_END;
	return tINTEGER;

      case '&':
	if ((c = nextc()) == '&') {
	    lex_state = EXPR_BEG;
	    if ((c = nextc()) == '=') {
		yylval.id = tANDOP;
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
	if (lex_state == EXPR_ARG && space_seen && !ISSPACE(c)){
	    lex_state = EXPR_BEG;
	    return tAMPER;
	}
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    lex_state = EXPR_BEG;
	    return tAMPER;
	}
	lex_state = EXPR_BEG;
	return '&';

      case '|':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '|') {
	    if ((c = nextc()) == '=') {
		yylval.id = tOROP;
		return tOP_ASGN;
	    }
	    pushback(c);
	    return tOROP;
	}
	else if (c == '=') {
	    yylval.id = '|';
	    return tOP_ASGN;
	}
	pushback(c);
	return '|';

      case '+':
	c = nextc();
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
	    if (c == '@') {
		return tUPLUS;
	    }
	    pushback(c);
	    return '+';
	}
	if (c == '=') {
	    lex_state = EXPR_BEG;
	    yylval.id = '+';
	    return tOP_ASGN;
	}
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID ||
	    (lex_state == EXPR_ARG && space_seen && !ISSPACE(c))) {
 	    if (ISDIGIT(c)) {
		goto start_num;
	    }
	    pushback(c);
	    lex_state = EXPR_BEG;
	    return tUPLUS;
	}
	lex_state = EXPR_BEG;
	pushback(c);
	return '+';

      case '-':
	c = nextc();
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
	    if (c == '@') {
		return tUMINUS;
	    }
	    pushback(c);
	    return '-';
	}
	if (c == '=') {
	    lex_state = EXPR_BEG;
	    yylval.id = '-';
	    return tOP_ASGN;
	}
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID ||
	    (lex_state == EXPR_ARG && space_seen && !ISSPACE(c))) {
	    if (ISDIGIT(c)) {
		pushback(c);
		c = '-';
		goto start_num;
	    }
	    lex_state = EXPR_BEG;
	    pushback(c);
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
	if (!ISDIGIT(c)) {
	    lex_state = EXPR_DOT;
	    return '.';
	}
	c = '.';
	/* fall through */

      start_num:
      case '0': case '1': case '2': case '3': case '4':
      case '5': case '6': case '7': case '8': case '9':
	{
	    int is_float, seen_point, seen_e;

	    is_float = seen_point = seen_e = 0;
	    lex_state = EXPR_END;
	    newtok();
	    if (c == '-' || c == '+') {
		tokadd(c);
		c = nextc();
	    }
	    if (c == '0') {
		c = nextc();
		if (c == 'x' || c == 'X') {
		    /* hexadecimal */
		    c = nextc();
		    if (!ISXDIGIT(c)) {
			yyerror("hexadecimal number without hex-digits");
		    }
		    do {
			if (c == '_') continue;
			if (!ISXDIGIT(c)) break;
			tokadd(c);
		    } while (c = nextc());
		    pushback(c);
		    tokfix();
		    yylval.val = rb_str2inum(tok(), 16);
		    return tINTEGER;
		}
		if (c == 'b' || c == 'B') {
		    /* binary */
		    c = nextc();
		    if (c != '0' && c != '1') {
			yyerror("numeric constant with no digits");
		    }
		    do {
			if (c == '_') continue;
			if (c != '0'&& c != '1') break;
			tokadd(c);
		    } while (c = nextc());
		    pushback(c);
		    tokfix();
		    yylval.val = rb_str2inum(tok(), 2);
		    return tINTEGER;
		}
		if (c >= '0' && c <= '7' || c == '_') {
		    /* octal */
	            do {
			if (c  == '_') continue;
			if (c < '0' || c > '7') break;
			tokadd(c);
		    } while (c = nextc());
		    pushback(c);
		    tokfix();
		    yylval.val = rb_str2inum(tok(), 8);
		    return tINTEGER;
		}
		if (c > '7' && c <= '9') {
		    yyerror("Illegal octal digit");
		}
		else if (c == '.') {
		    tokadd('0');
		}
		else {
		    pushback(c);
		    yylval.val = INT2FIX(0);
		    return tINTEGER;
		}
	    }

	    for (;;) {
		switch (c) {
		  case '0': case '1': case '2': case '3': case '4':
		  case '5': case '6': case '7': case '8': case '9':
		    tokadd(c);
		    break;

		  case '.':
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
		    break;

		  case 'e':
		  case 'E':
		    if (seen_e) {
			goto decode_num;
		    }
		    tokadd(c);
		    seen_e++;
		    is_float++;
		    if ((c = nextc()) == '-' || c == '+')
			tokadd(c);
		    else
			continue;
		    break;

		  case '_':	/* `_' in decimal just ignored */
		    break;

		  default:
		    goto decode_num;
		}
		c = nextc();
	    }

	  decode_num:
	    pushback(c);
	    tokfix();
	    if (is_float) {
		double d = strtod(tok(), 0);
		if (errno == ERANGE) {
		    rb_warn("Float %s out of range", tok());
		    errno = 0;
		}
		yylval.val = rb_float_new(d);
		return tFLOAT;
	    }
	    yylval.val = rb_str2inum(tok(), 10);
	    return tINTEGER;
	}

      case ']':
      case '}':
      case ')':
	lex_state = EXPR_END;
	return c;

      case ':':
	c = nextc();
	if (c == ':') {
	    if (lex_state == EXPR_BEG) {
		lex_state = EXPR_BEG;
		return tCOLON3;
	    }
	    if (lex_state == EXPR_ARG && space_seen) {
		lex_state = EXPR_BEG;
		return tCOLON3;
	    }
	    lex_state = EXPR_DOT;
	    return tCOLON2;
	}
	pushback(c);
	if (lex_state == EXPR_END || lex_state == EXPR_PAREN || ISSPACE(c)) {
	    lex_state = EXPR_BEG;
	    return ':';
	}
	lex_state = EXPR_FNAME;
	return tSYMBEG;

      case '/':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    return parse_regx('/', '/');
	}
	if ((c = nextc()) == '=') {
	    lex_state = EXPR_BEG;
	    yylval.id = '/';
	    return tOP_ASGN;
	}
	if (lex_state == EXPR_ARG) {
	    if (space_seen && !ISSPACE(c)) {
		pushback(c);
		arg_ambiguous();
		return parse_regx('/', '/');
	    }
	}
	lex_state = EXPR_BEG;
	pushback(c);
	return '/';

      case '^':
	lex_state = EXPR_BEG;
	if (nextc() == '=') {
	    yylval.id = '^';
	    return tOP_ASGN;
	}
	pushback(c);
	return c;

      case ',':
      case ';':
	lex_state = EXPR_BEG;
	return c;

      case '~':
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
	    if ((c = nextc()) != '@') {
		pushback(c);
	    }
	}
	lex_state = EXPR_BEG;
	return '~';

      case '(':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    c = tLPAREN;
	    lex_state = EXPR_BEG;
	}
	else {
	    lex_state = EXPR_BEG;
	}
	return c;

      case '[':
	if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
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
	else if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    c = tLBRACK;
	}
	else if (lex_state == EXPR_ARG && space_seen) {
	    c = tLBRACK;
	}
	lex_state = EXPR_BEG;
	return c;

      case '{':
	if (lex_state != EXPR_END &&
	    lex_state != EXPR_PAREN &&
	    lex_state != EXPR_ARG)
	    c = tLBRACE;
	lex_state = EXPR_BEG;
	return c;

      case '\\':
	c = nextc();
	if (c == '\r') {
	    c = nextc();
	    if (c != '\n') pushback(c);
	}
	if (c == '\n') {
	    space_seen = 1;
	    goto retry; /* skip \\n */
	}
	pushback(c);
	return '\\';

      case '%':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
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
	    }
	    if (c == -1 || term == -1) {
		rb_compile_error("unterminated quoted string meets end of file");
		return 0;
	    }
	    paren = 0;
	    if (term == '(') term = ')';
	    else if (term == '[') term = ']';
	    else if (term == '{') term = '}';
	    else if (term == '<') term = '>';

	    switch (c) {
	      case 'Q':
		return parse_string('"', term, paren);

	      case 'q':
		return parse_qstring(term, paren);

	      case 'w':
		return parse_quotedword(term, paren);

	      case 'x':
		return parse_string('`', term, paren);

	      case 'r':
		return parse_regx(term, paren);

	      default:
		yyerror("unknown type of %string");
		return 0;
	    }
	}
	if ((c = nextc()) == '=') {
	    yylval.id = '%';
	    return tOP_ASGN;
	}
	if (lex_state == EXPR_ARG && space_seen && !ISSPACE(c)) {
	    goto quotation;
	}
	lex_state = EXPR_BEG;
	pushback(c);
	return '%';

      case '$':
	lex_state = EXPR_END;
	newtok();
	c = nextc();
	switch (c) {
	  case '~':		/* $~: match-data */
            /* fall through */
	  case '_':		/* $_: last read line string */
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
	    tokadd(c);
	    tokfix();
	    yylval.id = rb_intern(tok());
	    return tGVAR;

	  case '&':		/* $&: last match */
	  case '`':		/* $`: string before last match */
	  case '\'':		/* $': string after last match */
	  case '+':		/* $+: string matches last paren. */
	    yylval.node = NEW_BACK_REF(c);
	    return tBACK_REF;

	  case '1': case '2': case '3':
	  case '4': case '5': case '6':
	  case '7': case '8': case '9':
	    while (ISDIGIT(c)) {
		tokadd(c);
		c = nextc();
	    }
	    pushback(c);
	    tokfix();
	    yylval.node = NEW_NTH_REF(atoi(tok()));
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
	if (!is_identchar(c)) {
	    pushback(c);
	    return '@';
	}
	newtok();
	tokadd('@');
	break;

      default:
	if (c != '_' && !ISALPHA(c) && !ismbchar(c)) {
	    rb_compile_error("Invalid char '%c' in expression", c);
	    goto retry;
	}

	newtok();
	break;
    }

    while (is_identchar(c)) {
	tokadd(c);
	if (ismbchar(c)) {
	    int i, len = mbclen(c)-1;

	    tokadd(c);
	    for (i = 0; i < len; i++) {
		c = nextc();
		tokadd(c);
	    }
	}
	c = nextc();
    }
    if ((c == '!' || c == '?') && is_identchar(tok()[0])) {
	tokadd(c);
	if (c == '!') {
	    c = nextc();
	    if (c == '=') {
		rb_warn("identifier! immediately followed by `='");
	    }
	    pushback(c);
	}
    }
    else {
	pushback(c);
    }
    tokfix();

    {
	int result;

	switch (tok()[0]) {
	  case '$':
	    lex_state = EXPR_END;
	    result = tGVAR;
	    break;
	  case '@':
	    lex_state = EXPR_END;
	    result = tIVAR;
	    break;
	  default:
	    if (lex_state != EXPR_DOT) {
		/* See if it is a reserved word.  */
		kw = rb_reserved_word(tok(), toklen());
		if (kw) {
		    enum lex_state state = lex_state;
		    lex_state = kw->state;
		    if (state == EXPR_FNAME) {
			yylval.id = rb_intern(kw->name);
		    }
		    if (state == EXPR_PAREN && kw->id[0] == kDO) {
			return kDO2;
		    }
		    return kw->id[state != EXPR_BEG];
		}
	    }

	    if (ISUPPER(tok()[0])) {
		result = tCONSTANT;
	    }
	    else if (toklast() == '!' || toklast() == '?') {
		result = tFID;
	    } else {
		result = tIDENTIFIER;
		if (lex_state == EXPR_FNAME || lex_state == EXPR_DOT) {
		    if ((c = nextc()) == '=') {
			tokadd(c);
		    }
		    else {
			pushback(c);
		    }
		}
	    }
	    if (lex_state == EXPR_BEG ||
		lex_state == EXPR_DOT ||
		lex_state == EXPR_ARG){
		lex_state = EXPR_ARG;
	    }
	    else {
		lex_state = EXPR_END;
	    }
	}
	tokfix();
	yylval.id = rb_intern(tok());
	return result;
    }
}

static NODE*
rb_str_extend(list, term)
    NODE *list;
    char term;
{
    int c;
    int brace = -1;
    VALUE ss;
    NODE *node;
    int nest;

    c = nextc();
    switch (c) {
      case '$':
      case '@':
      case '{':
	break;
      default:
	tokadd('#');
	pushback(c);
	return list;
    }

    ss = rb_str_new(tok(), toklen());
    if (list == 0) {
	list = NEW_DSTR(ss);
    }
    else if (toklen() > 0) {
	list_append(list, NEW_STR(ss));
    }
    newtok();

    switch (c) {
      case '$':
	tokadd('$');
	c = nextc();
	if (c == -1) return (NODE*)-1;
	switch (c) {
	  case '1': case '2': case '3':
	  case '4': case '5': case '6':
	  case '7': case '8': case '9':
	    while (ISDIGIT(c)) {
		tokadd(c);
		c = nextc();
	    }
	    pushback(c);
	    goto fetch_id;

	  case '&': case '+':
	  case '_': case '~':
	  case '*': case '$': case '?':
	  case '!': case '@': case ',':
	  case '.': case '=': case ':':
	  case '<': case '>': case '\\':
	  refetch:
	    tokadd(c);
	    goto fetch_id;

          default:
	    if (c == term) {
		list_append(list, NEW_STR(rb_str_new2("#$")));
		pushback(c);
		newtok();
		return list;
	    }
	    switch (c) {
	      case '\"':
	      case '/':
	      case '\'':
	      case '`':
		goto refetch;
	    }
	    if (!is_identchar(c)) {
		yyerror("bad global variable in string");
		newtok();
		return list;
	    }
	}
	/* through */

      case '@':
	tokadd(c);
	c = nextc();
	while (is_identchar(c)) {
	    tokadd(c);
	    if (ismbchar(c)) {
		int i, len = mbclen(c)-1;

		tokadd(c);
		for (i = 0; i < len; i++) {
		    c = nextc();
		    tokadd(c);
		}
	    }
	    c = nextc();
	}
	pushback(c);
	break;

      case '{':
	if (c == '{') brace = '}';
	nest = 0;
	do {
	  loop_again:
	    c = nextc();
	    switch (c) {
	      case -1:
		if (nest > 0) {
		    yyerror("bad substitution in string");
		    newtok();
		    return list;
		}
		return (NODE*)-1;
	      case '}':
		if (c == brace) {
		    if (nest == 0) break;
		    nest--;
		}
		tokadd(c);
		goto loop_again;
	      case '\\':
		c = read_escape();
		tokadd(c);
		goto loop_again;
	      case '{':
		if (brace != -1) nest++;
	      case '\"':
	      case '/':
	      case '`':
		if (c == term) {
		    pushback(c);
		    list_append(list, NEW_STR(rb_str_new2("#")));
		    rb_warning("bad substitution in string");
		    tokfix();
		    list_append(list, NEW_STR(rb_str_new(tok(), toklen())));
		    newtok();
		    return list;
		}
	      default:
		tokadd(c);
		break;
	    }
	} while (c != brace);
    }

  fetch_id:
    tokfix();
    node = NEW_EVSTR(tok(),toklen());
    list_append(list, node);
    newtok();

    return list;
}

NODE*
rb_node_newnode(type, a0, a1, a2)
    enum node_type type;
    NODE *a0, *a1, *a2;
{
    NODE *n = (NODE*)rb_newobj();

    n->flags |= T_NODE;
    nd_set_type(n, type);
    nd_set_line(n, ruby_sourceline);
    n->nd_file = ruby_sourcefile;

    n->u1.node = a0;
    n->u2.node = a1;
    n->u3.node = a2;

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
        nl = NEW_NEWLINE(node);
        fixpos(nl, node);
        nl->nd_nth = nd_line(node);
    }
    return nl;
}

static void
fixpos(node, orig)
    NODE *node, *orig;
{
    if (!node) return;
    if (!orig) return;
    node->nd_file = orig->nd_file;
    nd_set_line(node, nd_line(orig));
}

static NODE*
block_append(head, tail)
    NODE *head, *tail;
{
    NODE *end;

    if (tail == 0) return head;
    if (head == 0) return tail;

    if (nd_type(head) != NODE_BLOCK) {
	end = NEW_BLOCK(head);
	end->nd_end = end;
	fixpos(end, head);
	head = end;
    }
    else {
	end = head->nd_end;
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
	    rb_warning("statement not reached");
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
    head->nd_end = tail->nd_end;
    return head;
}

static NODE*
list_append(head, tail)
    NODE *head, *tail;
{
    NODE *last;

    if (head == 0) return NEW_LIST(tail);

    last = head;
    while (last->nd_next) {
	last = last->nd_next;
    }

    last->nd_next = NEW_LIST(tail);
    head->nd_alen += 1;
    return head;
}

static NODE*
list_concat(head, tail)
    NODE *head, *tail;
{
    NODE *last;

    last = head;
    while (last->nd_next) {
	last = last->nd_next;
    }

    last->nd_next = tail;
    head->nd_alen += tail->nd_alen;

    return head;
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
    }

    return NEW_CALL(recv, id, narg==1?NEW_LIST(arg1):0);
}

static NODE*
match_gen(node1, node2)
    NODE *node1;
    NODE *node2;
{
    local_cnt('~');

    switch (nd_type(node1)) {
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
	return NEW_MATCH2(node1, node2);

      case NODE_LIT:
	if (TYPE(node1->nd_lit) == T_REGEXP) {
	    return NEW_MATCH2(node1, node2);
	}
    }

    switch (nd_type(node2)) {
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
	return NEW_MATCH3(node2, node1);

      case NODE_LIT:
	if (TYPE(node2->nd_lit) == T_REGEXP) {
	    return NEW_MATCH3(node2, node1);
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
	return NEW_VCALL(id);
    }
    else if (is_global_id(id)) {
	return NEW_GVAR(id);
    }
    else if (is_instance_id(id)) {
	return NEW_IVAR(id);
    }
    else if (is_const_id(id)) {
	return NEW_CVAR(id);
    }
    rb_bug("invalid id for gettable");
    return 0;
}

static NODE*
assignable(id, val)
    ID id;
    NODE *val;
{
    NODE *lhs = 0;

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
	if (rb_dvar_defined(id)) {
	    lhs = NEW_DASGN(id, val);
	}
	else if (local_id(id) || !dyna_in_block()) {
	    lhs = NEW_LASGN(id, val);
	}
	else{
	    rb_dvar_push(id, 0);
	    lhs = NEW_DASGN_PUSH(id, val);
	}
    }
    else if (is_global_id(id)) {
	lhs = NEW_GASGN(id, val);
    }
    else if (is_instance_id(id)) {
	lhs = NEW_IASGN(id, val);
    }
    else if (is_const_id(id)) {
	if (cur_mid || in_single)
	    yyerror("dynamic constant assignment");
	lhs = NEW_CASGN(id, val);
    }
    else {
	rb_bug("bad id for variable");
    }
    return lhs;
}

static NODE *
aryset(recv, idx)
    NODE *recv, *idx;
{
    value_expr(recv);

    return NEW_CALL(recv, tASET, idx);
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
    value_expr(recv);

    return NEW_CALL(recv, rb_id_attrset(id), 0);
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
	rb_compile_error("Can't set variable $%c", node->nd_nth);
	break;
    }
}

static NODE *
arg_concat(node1, node2)
    NODE *node1;
    NODE *node2;
{
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
	return NEW_ARGSCAT(node1, node2);
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
      case NODE_DASGN_PUSH:
      case NODE_CASGN:
      case NODE_MASGN:
	lhs->nd_value = rhs;
	break;

      case NODE_CALL:
	lhs->nd_args = arg_add(lhs->nd_args, rhs);
	break;

      default:
	/* should not happen */
	break;
    }

    if (rhs) fixpos(lhs, rhs);
    return lhs;
}

static int
value_expr(node)
    NODE *node;
{
    if (node == 0) return Qtrue;

    switch (nd_type(node)) {
      case NODE_RETURN:
      case NODE_BREAK:
      case NODE_NEXT:
      case NODE_REDO:
      case NODE_RETRY:
      case NODE_WHILE:
      case NODE_UNTIL:
      case NODE_CLASS:
      case NODE_MODULE:
      case NODE_DEFN:
      case NODE_DEFS:
	yyerror("void value expression");
	return Qfalse;
	break;

      case NODE_BLOCK:
	while (node->nd_next) {
	    node = node->nd_next;
	}
	return value_expr(node->nd_head);

      case NODE_IF:
	return value_expr(node->nd_body) && value_expr(node->nd_else);

      case NODE_NEWLINE:
	return value_expr(node->nd_next);

      default:
	return Qtrue;
    }
}

static void
void_expr(node)
    NODE *node;
{
    char *useless = 0;

    if (!ruby_verbose) return;
    if (!node) return;

  again:
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
	  case tAREF:
	  case tRSHFT:
	  case tCOLON2:
	  case tCOLON3:
	    useless = rb_id2name(node->nd_mid);
	    break;
	}
	break;

      case NODE_LVAR:
      case NODE_DVAR:
      case NODE_GVAR:
      case NODE_IVAR:
      case NODE_NTH_REF:
      case NODE_BACK_REF:
	useless = "a variable";
	break;
      case NODE_CVAR:
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
    if (!ruby_verbose) return;
    if (!node) return;
    if (nd_type(node) != NODE_BLOCK) return;

    for (;;) {
	if (!node->nd_next) return;
	void_expr(node->nd_head);
	node = node->nd_next;
    }
}

static NODE *cond2();

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
      case NODE_CASGN:
	break;

      case NODE_NEWLINE:
      default:
	return 0;
    }

    switch (nd_type(node->nd_value)) {
      case NODE_LIT:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_XSTR:
      case NODE_DXSTR:
      case NODE_EVSTR:
      case NODE_DREGX:
      case NODE_NIL:
      case NODE_TRUE:
      case NODE_FALSE:
	/* reports always */
	rb_warn("found = in conditional, should be ==");
	return 1;

      default:
	break;
    }
    if (assign_in_cond(node->nd_value) == 0) {
	rb_warning("assignment in condition");
    }
    return 1;
}

static NODE*
cond0(node)
    NODE *node;
{
    enum node_type type = nd_type(node);

    assign_in_cond(node);
    switch (type) {
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
	local_cnt('_');
	local_cnt('~');
	return NEW_MATCH2(node, NEW_GVAR(rb_intern("$_")));

      case NODE_DOT2:
      case NODE_DOT3:
	node->nd_beg = cond2(node->nd_beg);
	node->nd_end = cond2(node->nd_end);
	if (type == NODE_DOT2) nd_set_type(node,NODE_FLIP2);
	else if (type == NODE_DOT3) nd_set_type(node, NODE_FLIP3);
	node->nd_cnt = local_append(0);
	return node;

      case NODE_LIT:
	if (TYPE(node->nd_lit) == T_REGEXP) {
	    local_cnt('_');
	    local_cnt('~');
	    return NEW_MATCH(node);
	}
	if (TYPE(node->nd_lit) == T_STRING) {
	    local_cnt('_');
	    local_cnt('~');
	    return NEW_MATCH(rb_reg_new(RSTRING(node)->ptr,RSTRING(node)->len,0));
	}
      default:
	return node;
    }
}

static NODE*
cond(node)
    NODE *node;
{
    if (node == 0) return 0;
    if (nd_type(node) == NODE_NEWLINE){
	node->nd_next = cond0(node->nd_next);
	return node;
    }
    return cond0(node);
}

static NODE*
cond2(node)
    NODE *node;
{
    enum node_type type;

    node = cond(node);
    type = nd_type(node);
    if (type == NODE_NEWLINE) node = node->nd_next;
    if (type == NODE_LIT && FIXNUM_P(node->nd_lit)) {
	return call_op(node,tEQ,1,NEW_GVAR(rb_intern("$.")));
    }
    return node;
}

static NODE*
logop(type, left, right)
    enum node_type type;
    NODE *left, *right;
{
    value_expr(left);
    return rb_node_newnode(type, cond(left), cond(right), 0);
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

static struct local_vars {
    ID *tbl;
    int nofree;
    int cnt;
    int dlev;
    struct local_vars *prev;
} *lvtbl;

static void
local_push()
{
    struct local_vars *local;

    local = ALLOC(struct local_vars);
    local->prev = lvtbl;
    local->nofree = 0;
    local->cnt = 0;
    local->tbl = 0;
    local->dlev = 0;
    lvtbl = local;
}

static void
local_pop()
{
    struct local_vars *local = lvtbl->prev;

    if (lvtbl->tbl) {
	if (!lvtbl->nofree) free(lvtbl->tbl);
	else lvtbl->tbl[0] = lvtbl->cnt;
    }
    free(lvtbl);
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

    for (cnt=1, max=lvtbl->cnt+1; cnt<max ;cnt++) {
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
    local_push();
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
	    if (i == 0 || ruby_scope->flag == SCOPE_ALLOCA) {
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
		ruby_scope->flag |= SCOPE_MALLOC;
	    }
	    else {
		VALUE *vars = ruby_scope->local_vars-1;
		REALLOC_N(vars, VALUE, len+1);
		ruby_scope->local_vars = vars+1;
		rb_mem_clear(ruby_scope->local_vars+i, len-i);
	    }
	    if (ruby_scope->local_tbl && ruby_scope->local_vars[-1] == 0) {
		free(ruby_scope->local_tbl);
	    }
	    ruby_scope->local_vars[-1] = 0;
	    ruby_scope->local_tbl = local_tbl();
	}
    }
    local_pop();
}

static struct RVarmap*
dyna_push()
{
    lvtbl->dlev++;
    return ruby_dyna_vars;
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

static void
cref_pop()
{
    cur_cref = cur_cref->nd_next;
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
    char *name;
} op_tbl[] = {
    tDOT2,	"..",
    tDOT3,	"...",
    '+',	"+",
    '-',	"-",
    '+',	"+(binary)",
    '-',	"-(binary)",
    '*',	"*",
    '/',	"/",
    '%',	"%",
    tPOW,	"**",
    tUPLUS,	"+@",
    tUMINUS,	"-@",
    tUPLUS,	"+(unary)",
    tUMINUS,	"-(unary)",
    '|',	"|",
    '^',	"^",
    '&',	"&",
    tCMP,	"<=>",
    '>',	">",
    tGEQ,	">=",
    '<',	"<",
    tLEQ,	"<=",
    tEQ,	"==",
    tEQQ,	"===",
    tNEQ,	"!=",
    tMATCH,	"=~",
    tNMATCH,	"!~",
    '!',	"!",
    '~',	"~",
    '!',	"!(unary)",
    '~',	"~(unary)",
    '!',	"!@",
    '~',	"~@",
    tAREF,	"[]",
    tASET,	"[]=",
    tLSHFT,	"<<",
    tRSHFT,	">>",
    tCOLON2,	"::",
    tCOLON3,	"::",
    '`',	"`",
    0,		0,
};

static st_table *sym_tbl;
static st_table *sym_rev_tbl;

void
Init_sym()
{
    sym_tbl = st_init_strtable_with_size(200);
    sym_rev_tbl = st_init_numtable_with_size(200);
    rb_global_variable((VALUE*)&cur_cref);
    rb_global_variable((VALUE*)&lex_lastline);
}

ID
rb_intern(name)
    const char *name;
{
    static ID last_id = LAST_TOKEN;
    int id;
    int last;

    if (st_lookup(sym_tbl, name, &id))
	return id;

    id = 0;
    switch (name[0]) {
      case '$':
	id |= ID_GLOBAL;
	break;
      case '@':
	id |= ID_INSTANCE;
	break;
      default:
	if (name[0] != '_' && !ISALPHA(name[0]) && !ismbchar(name[0])) {
	    /* operator */
	    int i;

	    for (i=0; op_tbl[i].token; i++) {
		if (*op_tbl[i].name == *name &&
		    strcmp(op_tbl[i].name, name) == 0) {
		    id = op_tbl[i].token;
		    goto id_regist;
		}
	    }
	}

	last = strlen(name)-1;
	if (name[last] == '=') {
	    /* attribute assignment */
	    char *buf = ALLOCA_N(char,last+1);

	    strncpy(buf, name, last);
	    buf[last] = '\0';
	    id = rb_intern(buf);
	    if (id > LAST_TOKEN) {
		id = rb_id_attrset(id);
		goto id_regist;
	    }
	    id |= ID_ATTRSET;
	}
	else if (ISUPPER(name[0])) {
	    id = ID_CONST;
        }
	else {
	    id = ID_LOCAL;
	}
	break;
    }
    id |= ++last_id << ID_SCOPE_SHIFT;
  id_regist:
    name = strdup(name);
    st_add_direct(sym_tbl, name, id);
    st_add_direct(sym_rev_tbl, id, name);
    return id;
}

char *
rb_id2name(id)
    ID id;
{
    char *name;

    if (id < LAST_TOKEN) {
	int i = 0;

	for (i=0; op_tbl[i].token; i++) {
	    if (op_tbl[i].token == id)
		return op_tbl[i].name;
	}
    }

    if (st_lookup(sym_rev_tbl, id, &name))
	return name;

    if (is_attrset_id(id)) {
	char *res;
	ID id2;

	id2 = (id & ~ID_SCOPE_MASK) | ID_LOCAL;
	res = rb_id2name(id2);

	if (res) {
	    char *buf = ALLOCA_N(char, strlen(res)+2);

	    strcpy(buf, res);
	    strcat(buf, "=");
	    rb_intern(buf);
	    return rb_id2name(id);
	}
    }
    return 0;
}

int
rb_is_const_id(id)
    ID id;
{
    if (is_const_id(id)) return Qtrue;
    return Qfalse;
}

int
rb_is_instance_id(id)
    ID id;
{
    if (is_instance_id(id)) return Qtrue;
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
    if (ruby_scope->local_vars) {
	return ruby_scope->local_vars[1];
    }
    return Qnil;
}

void
rb_backref_set(val)
    VALUE val;
{
    if (ruby_scope->local_vars) {
	ruby_scope->local_vars[1] = val;
    }
    else {
	special_local_set('~', val);
    }
}

VALUE
rb_lastline_get()
{
    if (ruby_scope->local_vars) {
	return ruby_scope->local_vars[0];
    }
    return Qnil;
}

void
rb_lastline_set(val)
    VALUE val;
{
    if (ruby_scope->local_vars) {
	ruby_scope->local_vars[0] = val;
    }
    else {
	special_local_set('_', val);
    }
}
