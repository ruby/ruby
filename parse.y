/************************************************

  parse.y -

  $Author$
  $Date$
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

%{

#define YYDEBUG 1
#include "ruby.h"
#include "env.h"
#include "node.h"
#include "st.h"
#include <stdio.h>

/* hack for bison */
#ifdef const
# undef const
#endif

#define ID_SCOPE_SHIFT 3
#define ID_SCOPE_MASK 0x07
#define ID_LOCAL    0x01
#define ID_INSTANCE 0x02
#define ID_GLOBAL   0x03
#define ID_ATTRSET  0x04
#define ID_CONST    0x05

#define is_id_nonop(id) ((id)>LAST_TOKEN)
#define is_local_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_LOCAL)
#define is_global_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_GLOBAL)
#define is_instance_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_INSTANCE)
#define is_attrset_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_ATTRSET)
#define is_const_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_CONST)

struct op_tbl {
    ID token;
    char *name;
};

NODE *eval_tree0 = 0;
NODE *eval_tree = 0;

char *sourcefile;		/* current source file */
int   sourceline;		/* current line no. */

static int yylex();
static int yyerror();

static enum lex_state {
    EXPR_BEG,			/* ignore newline, +/- is a sign. */
    EXPR_MID,			/* newline significant, +/- is a sign. */
    EXPR_END,			/* newline significant, +/- is a operator. */
    EXPR_ARG,			/* newline significant, +/- may be a sign. */
    EXPR_FNAME,			/* ignore newline, +/- is a operator. */
    EXPR_CLASS,			/* immediate after `class' no here document. */
} lex_state;

static int class_nest = 0;
static int in_single = 0;
static ID cur_mid = 0;

static int value_expr();
static NODE *cond();
static NODE *logop();

static NODE *newline_node();
static void fixpos();

static NODE *block_append();
static NODE *list_append();
static NODE *list_concat();
static NODE *arg_add();
static NODE *call_op();
static int in_defined = 0;

static NODE *gettable();
static NODE *assignable();
static NODE *aryset();
static NODE *attrset();
static void backref_error();

static NODE *match_gen();
static void local_push();
static void local_pop();
static int  local_cnt();
static int  local_id();
static ID  *local_tbl();

static struct RVarmap *dyna_push();
static void dyna_pop();
static int dyna_in_block();

VALUE dyna_var_asgn();
VALUE dyna_var_defined();

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

%token <id>   IDENTIFIER FID GVAR IVAR CONSTANT
%token <val>  INTEGER FLOAT STRING XSTRING REGEXP
%token <node> DSTRING DXSTRING DREGEXP NTH_REF BACK_REF

%type <node> singleton
%type <val>  literal numeric
%type <node> compstmt stmts stmt expr arg primary command_call method_call
%type <node> if_tail opt_else case_body cases rescue ensure iterator
%type <node> call_args call_args0 ret_args args mrhs opt_list var_ref
%type <node> superclass f_arglist f_args f_optarg f_opt
%type <node> array assoc_list assocs assoc undef_list
%type <node> iter_var opt_iter_var iter_block iter_do_block
%type <node> mlhs mlhs_head mlhs_tail lhs backref
%type <id>   variable symbol operation assoc_kw
%type <id>   cname fname op rest_arg
%type <num>  f_arg
%token UPLUS 		/* unary+ */
%token UMINUS 		/* unary- */
%token POW		/* ** */
%token CMP  		/* <=> */
%token EQ  		/* == */
%token EQQ  		/* === */
%token NEQ  		/* != <> */
%token GEQ  		/* >= */
%token LEQ  		/* <= */
%token ANDOP OROP	/* && and || */
%token MATCH NMATCH	/* =~ and !~ */
%token DOT2 DOT3	/* .. and ... */
%token AREF ASET        /* [] and []= */
%token LSHFT RSHFT      /* << and >> */
%token COLON2           /* :: */
%token COLON3           /* :: at EXPR_BEG */
%token <id> OP_ASGN     /* +=, -=  etc. */
%token ASSOC            /* => */
%token KW_ASSOC         /* -> */
%token LPAREN           /* ( */
%token LBRACK           /* [ */
%token LBRACE           /* { */
%token STAR             /* * */
%token SYMBEG

/*
 *	precedence table
 */

%left  kIF_MOD kUNLESS_MOD kWHILE_MOD kUNTIL_MOD
%left  kOR kAND
%right kNOT
%nonassoc kDEFINED
%right '=' OP_ASGN
%right '?' ':'
%nonassoc DOT2 DOT3
%left  OROP
%left  ANDOP
%nonassoc  CMP EQ EQQ NEQ MATCH NMATCH
%left  '>' GEQ '<' LEQ
%left  '|' '^'
%left  '&'
%left  LSHFT RSHFT
%left  '+' '-'
%left  '*' '/' '%'
%right '!' '~' UPLUS UMINUS
%right POW

%token LAST_TOKEN

%%
program		:  {
			lex_state = EXPR_BEG;
                        top_local_init();
			NEW_CREF0(); /* initialize constant c-ref */
			if ((VALUE)the_class == cObject) class_nest = 0;
			else class_nest = 1;
		    }
		  compstmt
		    {
			eval_tree = block_append(eval_tree, $2);
                        top_local_setup();
			cur_cref = 0;
			class_nest = 0;
		    }

compstmt	: stmts opt_terms

stmts		: /* none */
		    {
			$$ = 0;
		    }
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

stmt		: iterator iter_do_block
		    {
			$2->nd_iter = $1;
			$$ = $2;
		        fixpos($$, $2);
		    }
		| kALIAS fname {lex_state = EXPR_FNAME;} fname
		    {
			if (cur_mid || in_single)
			    yyerror("alias within method");
		        $$ = NEW_ALIAS($2, $4);
		    }
		| kALIAS GVAR GVAR
		    {
			if (cur_mid || in_single)
			    yyerror("alias within method");
		        $$ = NEW_VALIAS($2, $3);
		    }
		| kALIAS GVAR BACK_REF
		    {
			char buf[3];

			if (cur_mid || in_single)
			    yyerror("alias within method");
			sprintf(buf, "$%c", $3->nd_nth);
		        $$ = NEW_VALIAS($2, rb_intern(buf));
		    }
		| kALIAS GVAR NTH_REF
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
		| expr kUNTIL_MOD expr
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
			eval_tree0 = block_append(eval_tree0,NEW_PREEXE($4));
		        local_pop();
		        $$ = 0;
		    }
		| klEND '{' compstmt '}'
		    {
			if (cur_mid || in_single) {
			    yyerror("END in method; use at_exit");
			}

			$$ = NEW_ITER(0, NEW_POSTEXE(), $3);
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
			if (!cur_mid && !in_single)
			    yyerror("return appeared outside of method");
			$$ = NEW_RET($2);
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

command_call	: operation call_args0
		    {
			$$ = NEW_FCALL($1, $2);
		        fixpos($$, $2);
		   }
		| primary '.' operation call_args0
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $4);
		        fixpos($$, $1);
		    }
		| primary COLON2 operation call_args0
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $4);
		        fixpos($$, $1);
		    }
		| kSUPER call_args0
		    {
			if (!cur_mid && !in_single && !in_defined)
			    yyerror("super called outside of method");
			$$ = NEW_SUPER($2);
		        fixpos($$, $2);
		    }

mlhs		: mlhs_head
		    {
			$$ = NEW_MASGN(NEW_LIST($1), 0);
		    }
		| mlhs_head STAR lhs
		    {
			$$ = NEW_MASGN(NEW_LIST($1), $3);
		    }
		| mlhs_head mlhs_tail
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2), 0);
		    }
		| mlhs_head mlhs_tail ',' STAR lhs
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2),$5);
		    }
		| STAR lhs
		    {
			$$ = NEW_MASGN(0, $2);
		    }

mlhs_head	: lhs ','

mlhs_tail	: lhs
		    {
			$$ = NEW_LIST($1);
		    }
		| mlhs_tail ',' lhs
		    {
			$$ = list_append($1, $3);
		    }

lhs		: variable
		    {
			$$ = assignable($1, 0);
		    }
		| primary '[' call_args ']'
		    {
			$$ = aryset($1, $3, 0);
		    }
		| primary '.' IDENTIFIER
		    {
			$$ = attrset($1, $3, 0);
		    }
		| backref
		    {
		        backref_error($1);
			$$ = 0;
		    }

cname		: IDENTIFIER
		    {
			yyerror("class/module name must be CONSTANT");
		    }
		| CONSTANT

fname		: IDENTIFIER
		| CONSTANT
		| FID
		| op
		    {
			lex_state = EXPR_END;
			$$ = $1;
		    }

undef_list	: fname
		    {
			$$ = NEW_UNDEF($1);
		    }
		| undef_list ',' {lex_state = EXPR_FNAME;} fname
		    {
			$$ = block_append($1, NEW_UNDEF($4));
		    }

op		: DOT2		{ $$ = DOT2; }
		| '|'		{ $$ = '|'; }
		| '^'		{ $$ = '^'; }
		| '&'		{ $$ = '&'; }
		| CMP		{ $$ = CMP; }
		| EQ		{ $$ = EQ; }
		| EQQ		{ $$ = EQQ; }
		| MATCH		{ $$ = MATCH; }
		| '>'		{ $$ = '>'; }
		| GEQ		{ $$ = GEQ; }
		| '<'		{ $$ = '<'; }
		| LEQ		{ $$ = LEQ; }
		| LSHFT		{ $$ = LSHFT; }
		| RSHFT		{ $$ = RSHFT; }
		| '+'		{ $$ = '+'; }
		| '-'		{ $$ = '-'; }
		| '*'		{ $$ = '*'; }
		| STAR		{ $$ = '*'; }
		| '/'		{ $$ = '/'; }
		| '%'		{ $$ = '%'; }
		| POW		{ $$ = POW; }
		| '~'		{ $$ = '~'; }
		| UPLUS		{ $$ = UMINUS; }
		| UMINUS	{ $$ = UPLUS; }
		| AREF		{ $$ = AREF; }
		| ASET		{ $$ = ASET; }
		| '`'		{ $$ = '`'; }

arg		: variable '=' arg
		    {
			value_expr($3);
			$$ = assignable($1, $3);
		        fixpos($$, $3);
		    }
		| primary '[' call_args ']' '=' arg
		    {
			$$ = aryset($1, $3, $6);
		        fixpos($$, $1);
		    }
		| primary '.' IDENTIFIER '=' arg
		    {
			$$ = attrset($1, $3, $5);
		        fixpos($$, $5);
		    }
		| backref '=' arg
		    {
			value_expr($3);
		        backref_error($1);
			$$ = 0;
		    }
		| variable OP_ASGN arg
		    {
			value_expr($3);
			if (is_local_id($1)&&!local_id($1)&&dyna_in_block())
			    dyna_var_asgn($1, TRUE);
		  	$$ = assignable($1, call_op(gettable($1), $2, 1, $3));
		        fixpos($$, $3);
		    }
		| primary '[' call_args ']' OP_ASGN arg
		    {
			NODE *args = NEW_LIST($6);

		        list_append($3, NEW_NIL());
			list_concat(args, $3);
			$$ = NEW_OP_ASGN1($1, $5, args);
		        fixpos($$, $1);
		    }
		| primary '.' IDENTIFIER OP_ASGN arg
		    {
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| primary '.' CONSTANT OP_ASGN arg
		    {
			$$ = NEW_OP_ASGN2($1, $3, $4, $5);
		        fixpos($$, $1);
		    }
		| backref OP_ASGN arg
		    {
		        backref_error($1);
			$$ = 0;
		    }
		| arg DOT2 arg
		    {
			$$ = NEW_DOT2($1, $3);
		    }
		| arg DOT3 arg
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
		| arg POW arg
		    {
			$$ = call_op($1, POW, 1, $3);
		    }
		| UPLUS arg
		    {
			$$ = call_op($2, UPLUS, 0);
		    }
		| UMINUS arg
		    {
		        $$ = call_op($2, UMINUS, 0);
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
		| arg CMP arg
		    {
			$$ = call_op($1, CMP, 1, $3);
		    }
		| arg '>' arg
		    {
			$$ = call_op($1, '>', 1, $3);
		    }
		| arg GEQ arg
		    {
			$$ = call_op($1, GEQ, 1, $3);
		    }
		| arg '<' arg
		    {
			$$ = call_op($1, '<', 1, $3);
		    }
		| arg LEQ arg
		    {
			$$ = call_op($1, LEQ, 1, $3);
		    }
		| arg EQ arg
		    {
			$$ = call_op($1, EQ, 1, $3);
		    }
		| arg EQQ arg
		    {
			$$ = call_op($1, EQQ, 1, $3);
		    }
		| arg NEQ arg
		    {
			$$ = NEW_NOT(call_op($1, EQ, 1, $3));
		    }
		| arg MATCH arg
		    {
			$$ = match_gen($1, $3);
		    }
		| arg NMATCH arg
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
		| arg LSHFT arg
		    {
			$$ = call_op($1, LSHFT, 1, $3);
		    }
		| arg RSHFT arg
		    {
			$$ = call_op($1, RSHFT, 1, $3);
		    }
		| arg ANDOP arg
		    {
			$$ = logop(NODE_AND, $1, $3);
		    }
		| arg OROP arg
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

call_args	: /* none */
		    {
			$$ = 0;
		    }
		| call_args0 opt_nl

call_args0	: command_call
		    {
			value_expr($1);
			$$ = NEW_LIST($1);
		    }
		| args
		| args ',' STAR arg
		    {
			$$ = arg_add($1, $4);
		    }
		| assocs
		    {
			$$ = NEW_LIST(NEW_HASH($1));
		    }
		| assocs ',' STAR arg
		    {
			$$ = NEW_LIST(NEW_HASH($1));
			$$ = arg_add($$, $4);
		    }
		| args ',' assocs
		    {
			$$ = list_append($1, NEW_HASH($3));
		    }
		| args ',' assocs ',' STAR arg
		    {
			$$ = list_append($1, NEW_HASH($3));
			$$ = arg_add($$, $6);
		    }
		| STAR arg
		    {
			value_expr($2);
			$$ = $2;
		    }

opt_list	: /* none */
		    {
			$$ = 0;
		    }
		| args

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
		            $1->nd_next == 0) {
			    $$ = $1->nd_head;
			}
			else {
			    $$ = $1;
			}
		    }
		| args ',' STAR arg
		    {
			$$ = arg_add($1, $4);
		    }
		| STAR arg
		    {
			value_expr($2);
			$$ = $2;
		    }

ret_args	: call_args0
		    {
			if ($1 &&
			    nd_type($1) == NODE_ARRAY &&
			    $1->nd_next == 0) {
			    $$ = $1->nd_head;
			}
			else {
			    $$ = $1;
			}
		    }

array		: /* none */
		    {
			$$ = 0;
		    }
		| args trailer

primary		: literal
		    {
			$$ = NEW_LIT($1);
		    }
		| primary COLON2 cname
		    {
			value_expr($1);
			$$ = NEW_COLON2($1, $3);
		    }
		| COLON3 cname
		    {
			$$ = NEW_COLON3($2);
		    }
		| STRING
		    {
			$$ = NEW_STR($1);
		    }
		| DSTRING
		| XSTRING
		    {
			$$ = NEW_XSTR($1);
		    }
		| DXSTRING
		| DREGEXP
		| var_ref
		| backref
		| primary '[' call_args ']'
		    {
			value_expr($1);
			$$ = NEW_CALL($1, AREF, $3);
		    }
		| LBRACK array ']'
		    {
			if ($2 == 0)
			    $$ = NEW_ZARRAY(); /* zero length array*/
			else {
			    $$ = $2;
			}
		    }
		| LBRACE assoc_list '}'
		    {
			$$ = NEW_HASH($2);
		    }
		| kRETURN '(' ret_args ')'
		    {
			if (!cur_mid && !in_single)
			    yyerror("return appeared outside of method");
			value_expr($3);
			$$ = NEW_RET($3);
		    }
		| kRETURN '(' ')'
		    {
			if (!cur_mid && !in_single)
			    yyerror("return appeared outside of method");
			$$ = NEW_RET(0);
		    }
		| kRETURN
		    {
			if (!cur_mid && !in_single)
			    yyerror("return appeared outside of method");
			$$ = NEW_RET(0);
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
		| FID
		    {
			$$ = NEW_FCALL($1, 0);
		    }
		| operation iter_block
		    {
			$2->nd_iter = NEW_FCALL($1, 0);
			$$ = $2;
		    }
		| method_call
		| method_call iter_block
		    {
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
		| kFOR iter_var kIN expr do
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
		  ensure
		  kEND
		    {
			if (!$3 && !$4)
			    $$ = NEW_BEGIN($2);
			else {
			    if ($3) $2 = NEW_RESCUE($2, $3); 
			    if ($4) $2 = NEW_ENSURE($2, $4);
			    $$ = $2;
			}
		        fixpos($$, $2);
		    }
		| LPAREN compstmt ')'
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
		| kCLASS LSHFT expr term
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
		| kDEF singleton '.' {lex_state = EXPR_FNAME;} fname
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
		| term kDO

if_tail		: opt_else
		| kELSIF expr then
		  compstmt
		  if_tail
		    {
			value_expr($2);
			$$ = NEW_IF(cond($2), $4, $5);
		        fixpos($$, $2);
		    }

opt_else	: /* none */
		    {
			$$ = 0;
		    }
		| kELSE compstmt
		    {
			$$ = $2;
		    }

iter_var	: lhs
		| mlhs

opt_iter_var	: /* node */
		    {
			$$ = 0;
		    }
		| '|' /* none */  '|'
		    {
			$$ = 0;
		    }
		| OROP
		    {
			$$ = 0;
		    }
		| '|' iter_var '|'
		    {
			$$ = $2;
		    }

iter_do_block	: kDO
		    {
		        $<vars>$ = dyna_push();
		    }
		  opt_iter_var
		  compstmt
		  kEND
		    {
			$$ = NEW_ITER($3, 0, $4);
		        fixpos($$, $3?$3:$4);
			dyna_pop($<vars>2);
		    }

iter_block	: '{' 
		    {
		        $<vars>$ = dyna_push();
		    }
		  opt_iter_var
		  compstmt '}'
		    {
			$$ = NEW_ITER($3, 0, $4);
		        fixpos($$, $3?$3:$4);
			dyna_pop($<vars>2);
		    }

iterator	: IDENTIFIER
		    {
			$$ = NEW_FCALL($1, 0);
		    }
		| CONSTANT
		    {
			$$ = NEW_FCALL($1, 0);
		    }
		| FID
		    {
			$$ = NEW_FCALL($1, 0);
		    }
		| method_call
		| command_call

method_call	: operation '(' call_args ')'
		    {
			$$ = NEW_FCALL($1, $3);
		        fixpos($$, $3);
		    }
		| primary '.' operation '(' call_args ')'
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $5);
		        fixpos($$, $1);
		    }
		| primary '.' operation
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, 0);
		    }
		| primary COLON2 operation '(' call_args ')'
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $5);
		        fixpos($$, $1);
		    }
		| kSUPER '(' call_args ')'
		    {
			if (!cur_mid && !in_single && !in_defined)
			    yyerror("super called outside of method");
			$$ = NEW_SUPER($3);
		    }
		| kSUPER
		    {
			if (!cur_mid && !in_single && !in_defined)
			    yyerror("super called outside of method");
			$$ = NEW_ZSUPER();
		    }


case_body	: kWHEN args then
		  compstmt
		  cases
		    {
			$$ = NEW_WHEN($2, $4, $5);
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
		| /* none */
		    {
			$$ = 0;
		    }

ensure		: /* none */
		    {
			$$ = 0;
		    }
		| kENSURE compstmt
		    {
			$$ = $2;
		    }

literal		: numeric
		| SYMBEG symbol
		    {
			$$ = INT2FIX($2);
		    }
		| REGEXP

symbol		: fname
		| IVAR
		| GVAR

numeric		: INTEGER
		| FLOAT

variable	: IDENTIFIER
		| IVAR
		| GVAR
		| CONSTANT
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

backref		: NTH_REF
		| BACK_REF

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

f_arglist	: '(' f_args ')'
		    {
			$$ = $2;
			lex_state = EXPR_BEG;
		    }
		| f_args term
		    {
			$$ = $1;
		    }

f_args		: /* no arg */
		    {
			$$ = NEW_ARGS(0, 0, -1);
		    }
		| f_arg
		    {
			$$ = NEW_ARGS($1, 0, -1);
		    }
		| f_arg ',' rest_arg
		    {
			$$ = NEW_ARGS($1, 0, $3);
		    }
		| f_arg ',' f_optarg
		    {
			$$ = NEW_ARGS($1, $3, -1);
		    }
		| f_arg ',' f_optarg ',' rest_arg
		    {
			$$ = NEW_ARGS($1, $3, $5);
		    }
		| f_optarg
		    {
			$$ = NEW_ARGS(0, $1, -1);
		    }
		| f_optarg ',' rest_arg
		    {
			$$ = NEW_ARGS(0, $1, $3);
		    }
		| rest_arg
		    {
			$$ = NEW_ARGS(0, 0, $1);
		    }

f_arg		: IDENTIFIER
		    {
			if (!is_local_id($1))
			    yyerror("formal argument must be local variable");
			local_cnt($1);
			$$ = 1;
		    }
		| f_arg ',' IDENTIFIER
		    {
			if (!is_local_id($3))
			    yyerror("formal argument must be local variable");
			local_cnt($3);
			$$ += 1;
		    }

f_opt		: IDENTIFIER '=' arg
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

rest_arg	: STAR IDENTIFIER
		    {
			if (!is_local_id($2))
			    yyerror("rest argument must be local variable");
			$$ = local_cnt($2);
		    }

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
		| LPAREN expr opt_nl ')'
		    {
			switch (nd_type($2)) {
			  case NODE_STR:
			  case NODE_DSTR:
			  case NODE_XSTR:
			  case NODE_DXSTR:
			  case NODE_DREGX:
			  case NODE_LIT:
			  case NODE_ARRAY:
			  case NODE_ZARRAY:
			    yyerror("Can't define single method for literals.");
			  default:
			    break;
			}
			$$ = $2;
		    }

assoc_list	: /* none */
		    {
			$$ = 0;
		    }
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

assoc		: arg ASSOC arg
		    {
			$$ = list_append(NEW_LIST($1), $3);
		    }
		| assoc_kw KW_ASSOC arg
		    {
			$$ = list_append(NEW_LIST(NEW_STR(str_new2(rb_id2name($1)))), $3);
		    }

assoc_kw	: IDENTIFIER
		| CONSTANT

operation	: IDENTIFIER
		| CONSTANT
		| FID

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
%%
#include <ctype.h>
#include <sys/types.h>
#include "regex.h"
#include "util.h"

#define is_identchar(c) ((c)!=-1&&(isalnum(c) || (c) == '_' || ismbchar(c)))

static char *tokenbuf = NULL;
static int   tokidx, toksiz = 0;

VALUE newregexp();
VALUE newstring();
VALUE newfloat();
VALUE newinteger();
char *strdup();

static NODE *str_extend();

#define LEAVE_BS 1

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

    Error("%s", msg);
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
	Error_Append("%s", buf);

	i = lex_p - p;
	p = buf; pe = p + len;

	while (p < pe) {
	    if (*p != '\t') *p = ' ';
	    p++;
	}
	buf[i] = '^';
	buf[i+1] = '\0';
	Error_Append("%s", buf);
    }

    return 0;
}

static int newline_seen;

int rb_in_compile = 0;

static NODE*
yycompile(f)
    char *f;
{
    int n;

    newline_seen = 0;
    sourcefile = strdup(f);
    rb_in_compile = 1;
    n = yyparse();
    rb_in_compile = 0;
    if (n == 0) return eval_tree;

    return 0;
}

NODE*
compile_string(f, s, len)
    char *f, *s;
    int len;
{
    lex_pbeg = lex_p = s;
    lex_pend = s + len;
    lex_input = 0;
    if (!sourcefile || strcmp(f, sourcefile))	/* not in eval() */
	sourceline = 1;

    return yycompile(f);
}

NODE*
compile_file(f, file, start)
    char *f;
    VALUE file;
    int start;
{
    lex_input = file;
    lex_pbeg = lex_p = lex_pend = 0;
    sourceline = start;

    return yycompile(f);
}

static int
nextc()
{
    int c;

    if (lex_p == lex_pend) {
	if (lex_input) {
	    VALUE v = io_gets(lex_input);

	    if (NIL_P(v)) return -1;
	    lex_pbeg = lex_p = RSTRING(v)->ptr;
	    lex_pend = lex_p + RSTRING(v)->len;
	    if (RSTRING(v)->len == 8 &&
		strncmp(lex_pbeg, "__END__", 7) == 0) {
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

void
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
	    c = scan_oct(buf, i+1, &i);
	}
	return c;

      case 'x':	/* hex constant */
	{
	    char buf[2];
	    int i;

	    for (i=0; i<2; i++) {
		buf[i] = nextc();
		if (buf[i] == -1) goto eof;
		if (!isxdigit(buf[i])) {
		    pushback(buf[i]);
		    break;
		}
	    }
	    c = scan_hex(buf, i+1, &i);
	}
	return c;

      case 'b':	/* backspace */
	return '\b';

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
      case '^':
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
parse_regx(term)
    int term;
{
    register int c;
    char kcode = 0;
    int once = 0;
    int casefold = 0;
    int in_brack = 0;
    int re_start = sourceline;
    NODE *list = 0;

    newtok();
    while ((c = nextc()) != -1) {
	if (!in_brack && c == term) {
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
	    list = str_extend(list, term);
	    if (list == (NODE*)-1) return 0;
	    continue;

	  case '\\':
	    switch (c = nextc()) {
	      case -1:
		sourceline = re_start;
		Error("unterminated regexp meets end of file"); /*  */
		return 0;

	      case '\n':
		sourceline++;
		break;

	      case '\\':
	      case '^':		/* no \^ escape in regexp */
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
		if (c == '\n') {
		    sourceline++;
		}
		else if (c == term) {
		    tokadd(c);
		}
		else {
		    pushback(c);
		    tokadd('\\');
		    tokadd(read_escape());
		}
	    }
	    continue;

	  case -1:
	    Error("unterminated regexp");
	    return 0;

	  default:
	    if (ismbchar(c)) {
		tokadd(c);
		c = nextc();
	    }
	    break;

	  regx_end:
	    for (;;) {
		switch (c = nextc()) {
		  case 'i':
		    casefold = 1;
		    break;
		  case 'o':
		    once = 1;
		    break;
		  case 'n':
		    kcode = 2;
		    break;
		  case 'e':
		    kcode = 4;
		    break;
		  case 's':
		    kcode = 6;
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
		if (toklen() > 0) {
		    VALUE ss = str_new(tok(), toklen());
		    list_append(list, NEW_STR(ss));
		}
		nd_set_type(list, once?NODE_DREGX_ONCE:NODE_DREGX);
		list->nd_cflag = kcode | casefold;
		yylval.node = list;
		return DREGEXP;
	    }
	    else {
		yylval.val = reg_new(tok(), toklen(), kcode | casefold);
		return REGEXP;
	    }
	}
	tokadd(c);
    }
    Error("unterminated regexp");
    return 0;
}

static int parse_qstring();

static int
parse_string(func,term)
    int func, term;
{
    int c;
    NODE *list = 0;
    int strstart;

    if (func == '\'') {
	return parse_qstring(term);
    }
    strstart = sourceline;
    newtok();

    while ((c = nextc()) != term) {
	if (c  == -1) {
	  unterm_str:
	    sourceline = strstart;
	    Error("unterminated string meets end of file");
	    return 0;
	}
	if (ismbchar(c)) {
	    tokadd(c);
	    c = nextc();
	}
	else if (c == '\n') {
	    sourceline++;
	}
	else if (c == '#') {
	    list = str_extend(list, term);
	    if (list == (NODE*)-1) goto unterm_str;
	    continue;
	}
	else if (c == '\\') {
	    c = nextc();
	    if (c == '\n') {
		sourceline++;
	    }
	    else if (c == term) {
		tokadd(c);
	    }
	    else {
                pushback(c);
                if (func != '"') tokadd('\\');
                tokadd(read_escape());
  	    }
	    continue;
	}
	tokadd(c);
    }

    tokfix();
    lex_state = EXPR_END;
    if (list) {
	if (toklen() > 0) {
	    VALUE ss = str_new(tok(), toklen());
	    list_append(list, NEW_STR(ss));
	}
	yylval.node = list;
	if (func == '`') {
	    nd_set_type(list, NODE_DXSTR);
	    return DXSTRING;
	}
	else {
	    return DSTRING;
	}
    }
    else {
	yylval.val = str_new(tok(), toklen());
	return (func == '`') ? XSTRING : STRING;
    }
}

static int
parse_qstring(term)
    int term;
{
    int strstart;
    int c;

    strstart = sourceline;
    newtok();
    while ((c = nextc()) != term) {
	if (c  == -1)  {
	    sourceline = strstart;
	    Error("unterminated string meets end of file");
	    return 0;
	}
	if (ismbchar(c)) {
	    tokadd(c);
	    c = nextc();
	}
	else if (c == '\n') {
	    sourceline++;
	}
	else if (c == '\\') {
	    c = nextc();
	    switch (c) {
	      case '\n':
		sourceline++;
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
	tokadd(c);
    }

    tokfix();
    yylval.val = str_new(tok(), toklen());
    lex_state = EXPR_END;
    return STRING;
}

static int
parse_quotedword(term)
    int term;
{
    if (parse_qstring(term) == 0) return 0;
    yylval.node = NEW_CALL(NEW_STR(yylval.val), rb_intern("split"), 0);
    return DSTRING;
}

char *strdup();

static int
here_document(term)
    char term;
{
    int c;
    char *eos;
    int len;
    VALUE str, line;
    char *save_beg, *save_end, *save_lexp;
    NODE *list = 0;

    newtok();
    switch (term) {
      case '\'':
      case '"':
      case '`':
	while ((c = nextc()) != term) {
	    tokadd(c);
	}
	break;

      default:
	c =  term;
	term = '"';
	if (!is_identchar(c)) {
	    yyerror("illegal here document");
	    return 0;
	}
	while (is_identchar(c)) {
	    tokadd(c);
	    c = nextc();
	}
	pushback(c);
	break;
    }
    tokfix();
    save_lexp = lex_p;
    save_beg = lex_pbeg;
    save_end = lex_pend;
    eos = strdup(tok());
    len = strlen(eos);

    str = str_new(0,0);
    for (;;) {
	line = io_gets(lex_input);
	if (NIL_P(line)) {
	  error:
	    Error("unterminated string meets end of file");
	    free(eos);
	    return 0;
	}
	sourceline++;
	if (strncmp(eos, RSTRING(line)->ptr, len) == 0 &&
	    (RSTRING(line)->ptr[len] == '\n' ||
	     RSTRING(line)->ptr[len] == '\r')) {
	    break;
	}

	lex_pbeg = lex_p = RSTRING(line)->ptr;
	lex_pend = lex_p + RSTRING(line)->len;
	switch (parse_string(term, '\n')) {
	  case STRING:
	  case XSTRING:
	    str_cat(yylval.val, "\n", 1);
	    if (!list) {
	        str_cat(str, RSTRING(yylval.val)->ptr, RSTRING(yylval.val)->len);
	    }
	    else {
		list_append(list, NEW_STR(yylval.val));
	    }
	    break;
	  case DSTRING:
	  case DXSTRING:
	    list_append(yylval.node, NEW_STR(str_new2("\n")));
	    nd_set_type(yylval.node, NODE_STR);
	    if (!list) list = NEW_DSTR(str);
	    yylval.node = NEW_LIST(yylval.node);
	    yylval.node->nd_next = yylval.node->nd_head->nd_next;
	    list_concat(list, yylval.node);
	    break;

	  case 0:
	    goto error;
	}
    }
    free(eos);
    lex_p = save_lexp;
    lex_pbeg = save_beg;
    lex_pend = save_end;

    if (list) {
	yylval.node = list;
    }
    switch (term) {
      case '\'':
      case '"':
	if (list) return DSTRING;
	yylval.val = str;	  
	return STRING;
      case '`':
	if (list) return DXSTRING;
	return XSTRING;
    }
    return 0;
}

#include "lex.c"

static void
arg_ambiguous()
{
    Warning("ambiguous first argument; make sure");
}

#ifndef atof
double atof();
#endif

static int
yylex()
{
    register int c;
    int space_seen = 0;
    struct kwtable *kw;

    if (newline_seen) {
	sourceline+=newline_seen;
	newline_seen = 0;
    }

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
	    if (c == '\\') {	/* skip a char */
		c = nextc();
		if (c == '\n') sourceline++;
	    }
	    if (ismbchar(c)) {
		c = nextc();
		if (c == '\n') {
		    sourceline++;
		    break;
		}
	    }
	}
	/* fall through */
      case '\n':
	if (lex_state == EXPR_BEG || lex_state == EXPR_FNAME) {
	    sourceline++;
	    goto retry;
	}
	newline_seen++;
	lex_state = EXPR_BEG;
	return '\n';

      case '*':
	if ((c = nextc()) == '*') {
	    lex_state = EXPR_BEG;
	    if (nextc() == '=') {
		yylval.id = POW;
		return OP_ASGN;
	    }
	    pushback(c);
	    return POW;
	}
	if (c == '=') {
	    yylval.id = '*';
	    lex_state = EXPR_BEG;
	    return OP_ASGN;
	}
	pushback(c);
	if (lex_state == EXPR_ARG && space_seen && !isspace(c)){
	    arg_ambiguous();
	    lex_state = EXPR_BEG;
	    return STAR;
	}
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    return STAR;
	}
	lex_state = EXPR_BEG;
	return '*';

      case '!':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    return NEQ;
	}
	if (c == '~') {
	    return NMATCH;
	}
	pushback(c);
	return '!';

      case '=':
	if (lex_p == lex_pbeg + 1) {
	    /* skip embedded rd document */
	    if (strncmp(lex_p, "begin", 5) == 0 && isspace(lex_p[5])) {
		for (;;) {
		    sourceline++;
		    lex_p = lex_pend;
		    c = nextc();
		    if (c == -1) {
			Error("embedded document meets end of file");
			return 0;
		    }
		    if (c != '=') continue;
		    if (strncmp(lex_p, "end", 3) == 0 && isspace(lex_p[3])) {
			break;
		    }
		}
		sourceline++;
		lex_p = lex_pend;
		goto retry;
	    }
	}

	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    if ((c = nextc()) == '=') {
		return EQQ;
	    }
	    pushback(c);
	    return EQ;
	}
	if (c == '~') {
	    return MATCH;
	}
	else if (c == '>') {
	    return ASSOC;
	}
	pushback(c);
	return '=';

      case '<':
	c = nextc();
	if (c == '<' &&
	    lex_state != EXPR_END
	    && lex_state != EXPR_CLASS &&
	    (lex_state != EXPR_ARG || space_seen)) {
 	    int c2 = nextc();
	    if (!isspace(c2) && (strchr("\"'`", c2) || is_identchar(c2))) {
		if (!lex_input) {
		    ArgError("here document not available");
		}
		return here_document(c2);
	    }
	    pushback(c2);
	}
	lex_state = EXPR_BEG;
	if (c == '=') {
	    if ((c = nextc()) == '>') {
		return CMP;
	    }
	    pushback(c);
	    return LEQ;
	}
	if (c == '<') {
	    if (nextc() == '=') {
		yylval.id = LSHFT;
		return OP_ASGN;
	    }
	    pushback(c);
	    return LSHFT;
	}
	pushback(c);
	return '<';

      case '>':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    return GEQ;
	}
	if (c == '>') {
	    if ((c = nextc()) == '=') {
		yylval.id = RSHFT;
		return OP_ASGN;
	    }
	    pushback(c);
	    return RSHFT;
	}
	pushback(c);
	return '>';

      case '"':
	return parse_string(c,c);
      case '`':
	if (lex_state == EXPR_FNAME) return c;
	return parse_string(c,c);

      case '\'':
	return parse_qstring(c);

      case '?':
	if (lex_state == EXPR_END) {
	    Warning("a?b:c is undocumented feature ^^;;;");
	    lex_state = EXPR_BEG;
	    return '?';
	}
	c = nextc();
	if (lex_state == EXPR_ARG && isspace(c)){
	    pushback(c);
	    arg_ambiguous();
	    lex_state = EXPR_BEG;
	    Warning("a?b:c is undocumented feature ^^;;;");
	    return '?';
	}
	if (c == '\\') {
	    c = read_escape();
	}
	c &= 0xff;
	yylval.val = INT2FIX(c);
	lex_state = EXPR_END;
	return INTEGER;

      case '&':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '&') {
	    return ANDOP;
	}
	else if (c == '=') {
	    yylval.id = '&';
	    return OP_ASGN;
	}
	pushback(c);
	return '&';

      case '|':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '|') {
	    return OROP;
	}
	else if (c == '=') {
	    yylval.id = '|';
	    return OP_ASGN;
	}
	pushback(c);
	return '|';

      case '+':
	c = nextc();
	if (lex_state == EXPR_FNAME) {
	    if (c == '@') {
		return UPLUS;
	    }
	    pushback(c);
	    return '+';
	}
	if (c == '=') {
	    lex_state = EXPR_BEG;
	    yylval.id = '+';
	    return OP_ASGN;
	}
	if (lex_state == EXPR_ARG) {
	    if (space_seen && !isspace(c)) {
		arg_ambiguous();
	    }
	    else {
		lex_state = EXPR_END;
	    }
	}
	if (lex_state != EXPR_END) {
 	    if (isdigit(c)) {
		goto start_num;
	    }
	    pushback(c);
	    lex_state = EXPR_BEG;
	    return UPLUS;
	}
	lex_state = EXPR_BEG;
	pushback(c);
	return '+';

      case '-':
	c = nextc();
	if (lex_state == EXPR_FNAME) {
	    if (c == '@') {
		return UMINUS;
	    }
	    pushback(c);
	    return '-';
	}
	if (c == '=') {
	    lex_state = EXPR_BEG;
	    yylval.id = '-';
	    return OP_ASGN;
	}
	if (c == '>') {
	    Warning("-> is undocumented feature ^^;;;");
	    lex_state = EXPR_BEG;
	    return KW_ASSOC;
	}
	if (lex_state == EXPR_ARG) {
	    if (space_seen && !isspace(c)) {
		arg_ambiguous();
	    }
	    else {
		lex_state = EXPR_END;
	    }
	}
	if (lex_state != EXPR_END) {
	    if (isdigit(c)) {
		pushback(c);
		c = '-';
		goto start_num;
	    }
	    lex_state = EXPR_BEG;
	    pushback(c);
	    return UMINUS;
	}
	lex_state = EXPR_BEG;
	pushback(c);
	return '-';

      case '.':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '.') {
	    if ((c = nextc()) == '.') {
		return DOT3;
	    }
	    pushback(c);
	    return DOT2;
	}
	pushback(c);
	if (!isdigit(c)) {
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
		    while (c = nextc()) {
			if (c == '_') continue;
			if (!isxdigit(c)) break;
			tokadd(c);
		    }
		    pushback(c);
		    tokfix();
		    yylval.val = str2inum(tok(), 16);
		    return INTEGER;
		}
		else if (c >= '0' && c <= '7') {
		    /* octal */
		    do {
			tokadd(c);
			while ((c = nextc()) == '_')
			    ;
		    } while (c >= '0' && c <= '9');
		    pushback(c);
		    tokfix();
		    yylval.val = str2inum(tok(), 8);
		    return INTEGER;
		}
		else if (c > '7' && c <= '9') {
		    yyerror("Illegal octal digit");
		}
		else if (c == '.') {
		    tokadd('0');
		}
		else {
		    pushback(c);
		    yylval.val = INT2FIX(0);
		    return INTEGER;
		}
	    }

	    for (;;) {
		switch (c) {
		  case '0': case '1': case '2': case '3': case '4':
		  case '5': case '6': case '7': case '8': case '9':
		    tokadd(c);
		    break;

		  case '.':
		    if (seen_point) {
			goto decode_num;
		    }
		    else {
			int c0 = nextc();
			if (!isdigit(c0)) {
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
		yylval.val = float_new(atof(tok()));
		return FLOAT;
	    }
	    yylval.val = str2inum(tok(), 10);
	    return INTEGER;
	}

      case ']':
      case '}':
      case ')':
	lex_state = EXPR_END;
	return c;

      case ':':
	c = nextc();
	if (c == ':') {
	    if (lex_state == EXPR_BEG ||
		(lex_state == EXPR_ARG && space_seen)) {
		lex_state = EXPR_BEG;
		return COLON3;
	    }
	    lex_state = EXPR_BEG;
	    return COLON2;
	}
	pushback(c);
	if (lex_state == EXPR_END || isspace(c)) {
	    lex_state = EXPR_BEG;
	    return ':';
	}
	lex_state = EXPR_FNAME;
	return SYMBEG;

      case '/':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    return parse_regx('/');
	}
	if ((c = nextc()) == '=') {
	    lex_state = EXPR_BEG;
	    yylval.id = '/';
	    return OP_ASGN;
	}
	if (lex_state == EXPR_ARG) {
	    if (space_seen && !isspace(c)) {
		pushback(c);
		arg_ambiguous();
		return parse_regx('/');
	    }
	}
	lex_state = EXPR_BEG;
	pushback(c);
	return '/';

      case '^':
	lex_state = EXPR_BEG;
	if (nextc() == '=') {
	    yylval.id = '^';
	    return OP_ASGN;
	}
	pushback(c);
	return c;

      case ',':
      case ';':
	lex_state = EXPR_BEG;
	return c;

      case '~':
	if (lex_state == EXPR_FNAME) {
	    if ((c = nextc()) != '@') {
		pushback(c);
	    }
	}
	lex_state = EXPR_BEG;
	return '~';

      case '(':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    c = LPAREN;
	    lex_state = EXPR_BEG;
	}
	else {
	    lex_state = EXPR_BEG;
	}
	return c;

      case '[':
	if (lex_state == EXPR_FNAME) {
	    if ((c = nextc()) == ']') {
		if ((c = nextc()) == '=') {
		    return ASET;
		}
		pushback(c);
		return AREF;
	    }
	    pushback(c);
	    return '[';
	}
	else if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    c = LBRACK;
	}
	else if (lex_state == EXPR_ARG && space_seen) {
	    arg_ambiguous();
	    c = LBRACK;
	}
	lex_state = EXPR_BEG;
	return c;

      case '{':
	if (lex_state != EXPR_END && lex_state != EXPR_ARG)
	    c = LBRACE;
	lex_state = EXPR_BEG;
	return c;

      case '\\':
	c = nextc();
	if (c == '\n') {
	    sourceline++;
	    space_seen = 1;
	    goto retry; /* skip \\n */
	}
	pushback(c);
	return '\\';

      case '%':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    int term;

	    c = nextc();
	  quotation:
	    if (!isalnum(c)) {
		term = c;
		switch (c) {
		  case '\'':
		    c = 'q'; break;
		  case '/':
		    c = 'r'; break;
		  case '`':
		    c = 'x'; break;
		  default:
		    c = 'Q';break;
		}
	    }
	    else {
		term = nextc();
	    }
	    if (c == -1 || term == -1) {
		Error("unterminated quoted string meets end of file");
		return 0;
	    }
	    if (term == '(') term = ')';
	    else if (term == '[') term = ']';
	    else if (term == '{') term = '}';
	    else if (term == '<') term = '>';

	    switch (c) {
	      case 'Q':
		return parse_string('"', term);

	      case 'q':
		return parse_qstring(term);

	      case 'w':
		return parse_quotedword(term);

	      case 'x':
		return parse_string('`', term);

	      case 'r':
		return parse_regx(term);

	      default:
		yyerror("unknown type of %string");
		return 0;
	    }
	}
	if ((c = nextc()) == '=') {
	    yylval.id = '%';
	    return OP_ASGN;
	}
	if (lex_state == EXPR_ARG) {
	    if (space_seen && !isspace(c)) {
		arg_ambiguous();
		goto quotation;
	    }
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
	    return GVAR;

	  case '-':
	    tokadd('$');
	    tokadd(c);
	    c = nextc();
	    tokadd(c);
	    tokfix();
	    yylval.id = rb_intern(tok());
	    return GVAR;

	  case '&':		/* $&: last match */
	  case '`':		/* $`: string before last match */
	  case '\'':		/* $': string after last match */
	  case '+':		/* $+: string matches last paren. */
	    yylval.node = NEW_BACK_REF(c);
	    return BACK_REF;

	  case '1': case '2': case '3':
	  case '4': case '5': case '6':
	  case '7': case '8': case '9':
	    while (isdigit(c)) {
		tokadd(c);
		c = nextc();
	    }
	    pushback(c);
	    tokfix();
	    yylval.node = NEW_NTH_REF(atoi(tok()));
	    return NTH_REF;

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
	if (c != '_' && !isalpha(c) && !ismbchar(c)) {
	    Error("Invalid char '%c' in expression", c);
	    goto retry;
	}

	newtok();
	break;
    }

    while (is_identchar(c)) {
	tokadd(c);
	if (ismbchar(c)) {
	    c = nextc();
	    tokadd(c);
	}
	c = nextc();
    }
    if (c == '!' || c == '?') {
	tokadd(c);
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
	    result = GVAR;
	    break;
	  case '@':
	    lex_state = EXPR_END;
	    result = IVAR;
	    break;
	  default:
	    /* See if it is a reserved word.  */
	    kw = rb_reserved_word(tok(), toklen());
	    if (kw) {
		enum lex_state state = lex_state;
		lex_state = kw->state;
		return kw->id[state != EXPR_BEG];
	    }

	    if (lex_state == EXPR_FNAME) {
		lex_state = EXPR_END;
		if ((c = nextc()) == '=') {
		    tokadd(c);
		}
		else {
		    pushback(c);
		}
	    }
	    else if (lex_state == EXPR_BEG){
		lex_state = EXPR_ARG;
	    }
	    else {
		lex_state = EXPR_END;
	    }
	    if (isupper(tok()[0])) {
		result = CONSTANT;
	    }
	    else if (toklast() == '!' || toklast() == '?') {
		result = FID;
	    } else {
		result = IDENTIFIER;
	    }
	}
	tokfix();
	yylval.id = rb_intern(tok());
	return result;
    }
}

static NODE*
str_extend(list, term)
    NODE *list;
    char term;
{
    int c, brace;
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

    ss = str_new(tok(), toklen());
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
	    while (isdigit(c)) {
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
		list_append(list, NEW_STR(str_new2("#$")));
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
		c = nextc();
		tokadd(c);
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
	      case ')':
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
		if (brace == c) nest++;
	      case '\"':
	      case '/':
	      case '`':
		if (c == term) {
		    pushback(c);
		    list_append(list, NEW_STR(str_new2("#")));
		    Warning("bad substitution in string");
		    tokfix();
		    list_append(list, NEW_STR(str_new(tok(), toklen())));
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
node_newnode(type, a0, a1, a2)
    enum node_type type;
    NODE *a0, *a1, *a2;
{
    NODE *n = (NODE*)rb_newobj();

    n->flags |= T_NODE;
    nd_set_type(n, type);
    nd_set_line(n, sourceline);
    n->nd_file = sourcefile;

    n->u1.node = a0;
    n->u2.node = a1;
    n->u3.node = a2;

    return n;
}

enum node_type
nodetype(node)			/* for debug */
    NODE *node;
{
    return (enum node_type)nd_type(node);
}

int
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

    if (RTEST(verbose)) {
	NODE *nd = end->nd_head;
      newline:
	switch (nd_type(nd)) {
	  case NODE_RETURN:
	  case NODE_BREAK:
	  case NODE_NEXT:
	  case NODE_REDO:
	  case NODE_RETRY:
	    Warning("statement not reached");
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

    return NEW_CALL(node1, MATCH, NEW_LIST(node2));
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
	return NEW_STR(str_new2(sourcefile));
    }
    else if (id == k__LINE__) {
	return NEW_LIT(INT2FIX(sourceline));
    }
    else if (is_local_id(id)) {
	if (local_id(id)) return NEW_LVAR(id);
	if (dyna_var_defined(id)) return NEW_DVAR(id);
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
    Bug("invalid id for gettable");
    return 0;
}

static NODE*
assignable(id, val)
    ID id;
    NODE *val;
{
    NODE *lhs = 0;

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
	if (local_id(id) || !dyna_in_block()) {
	    lhs = NEW_LASGN(id, val);
	}
	else{
	    dyna_var_asgn(id, TRUE);
	    lhs = NEW_DASGN(id, val);
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
	Bug("bad id for variable");
    }
    return lhs;
}

static NODE *
arg_add(node1, node2)
    NODE *node1;
    NODE *node2;
{
    return call_op(node1, rb_intern("concat"), 1, node2);
}

static NODE *
aryset(recv, idx, val)
    NODE *recv, *idx, *val;
{
    value_expr(recv);
    value_expr(val);
    if (idx) {
	if (nd_type(idx) == NODE_ARRAY) {
	    idx = list_append(idx, val);
	}
	else {
	    idx = arg_add(idx, val);
	}
    }
    return NEW_CALL(recv, ASET, idx);
}

ID
id_attrset(id)
    ID id;
{
    id &= ~ID_SCOPE_MASK;
    id |= ID_ATTRSET;
    return id;
}

static NODE *
attrset(recv, id, val)
    NODE *recv, *val;
    ID id;
{
    value_expr(recv);
    value_expr(val);
 
    id &= ~ID_SCOPE_MASK;
    id |= ID_ATTRSET;

    return NEW_CALL(recv, id, NEW_LIST(val));
}

static void
backref_error(node)
    NODE *node;
{
    switch (nd_type(node)) {
      case NODE_NTH_REF:
	Error("Can't set variable $%d", node->nd_nth);
	break;
      case NODE_BACK_REF:
	Error("Can't set variable $%c", node->nd_nth);
	break;
    }
}

static int
value_expr(node)
    NODE *node;
{
    if (node == 0) return TRUE;

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
	return FALSE;
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
	return TRUE;
    }
}

static NODE *cond2();

int
assign_in_cond(node)
    NODE *node;
{
    switch (nd_type(node)) {
      case NODE_MASGN:
	Error("multiple assignment in conditional");
	return 0;

      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_CASGN:
	break;
      case NODE_NEWLINE:

      default:
	return 1;
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
	Error("found = in conditional, should be ==");
	return 0;
	
      default:
	Warning("assignment in condition");
	break;
    }
    if (assign_in_cond(node->nd_value)) return 1;
}

static NODE*
cond0(node)
    NODE *node;
{
    enum node_type type = nd_type(node);

    if (assign_in_cond(node) == 0) return 0;
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
	    return NEW_MATCH(reg_new(RSTRING(node)->ptr,RSTRING(node)->len,0));
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
	return call_op(node,EQ,1,NEW_GVAR(rb_intern("$.")));
    }
    return node;
}

static NODE*
logop(type, left, right)
    enum node_type type;
    NODE *left, *right;
{
    value_expr(left);

    return node_newnode(type, cond(left), cond(right));
}

st_table *new_idhash();

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
    struct local_vars *local = lvtbl;

    lvtbl = local->prev;
    if (local->tbl) {
	local->tbl[0] = local->cnt;
	if (!local->nofree) free(local->tbl);
    }
    free(local);
}

static ID*
local_tbl()
{
    lvtbl->nofree = 1;
    return lvtbl->tbl;
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

    
    if (lvtbl->tbl == 0) {
	lvtbl->tbl = ALLOC_N(ID, 2);
	lvtbl->tbl[0] = 0;
    }
    else {
	REALLOC_N(lvtbl->tbl, ID, lvtbl->cnt+2);
    }

    lvtbl->tbl[lvtbl->cnt+1] = id;
    return lvtbl->cnt++;
}

static int
local_id(id)
    ID id;
{
    int i, max;

    if (lvtbl == 0) return FALSE;
    for (i=1, max=lvtbl->cnt+1; i<max; i++) {
	if (lvtbl->tbl[i] == id) return TRUE;
    }
    return FALSE;
}

static void
top_local_init()
{
    local_push();
    lvtbl->cnt = the_scope->local_tbl?the_scope->local_tbl[0]:0;
    if (lvtbl->cnt > 0) {
	lvtbl->tbl = ALLOC_N(ID, lvtbl->cnt+1);
	MEMCPY(lvtbl->tbl, the_scope->local_tbl, ID, lvtbl->cnt+1);
    }
    else {
	lvtbl->tbl = 0;
    }
    if (the_dyna_vars && the_dyna_vars->id)
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
	i = lvtbl->tbl[0];

	if (i < len) {
	    if (i == 0 || the_scope->flag == SCOPE_ALLOCA) {
		VALUE *vars = ALLOC_N(VALUE, len+1);
		if (the_scope->local_vars) {
		    *vars++ = the_scope->local_vars[-1];
		    MEMCPY(vars, the_scope->local_vars, VALUE, i);
		    memclear(vars+i, len-i);
		}
		else {
		    *vars++ = 0;
		    memclear(vars, len);
		}
		the_scope->local_vars = vars;
		the_scope->flag |= SCOPE_MALLOC;
	    }
	    else {
		VALUE *vars = the_scope->local_vars-1;
		REALLOC_N(vars, VALUE, len+1);
		the_scope->local_vars = vars+1;
		memclear(the_scope->local_vars+i, len-i);
	    }
	    lvtbl->tbl[0] = len;
	    if (the_scope->local_tbl && the_scope->local_vars[-1] == 0) {
		free(the_scope->local_tbl);
	    }
	    the_scope->local_vars[-1] = 0;
	    the_scope->local_tbl = lvtbl->tbl;
	    lvtbl->nofree = 1;
	}
    }
    local_pop();
}

static struct RVarmap*
dyna_push()
{
    lvtbl->dlev++;
    return the_dyna_vars;
}

static void
dyna_pop(vars)
    struct RVarmap* vars;
{
    lvtbl->dlev--;
    the_dyna_vars = vars;
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
yyappend_print()
{
    eval_tree =
	block_append(eval_tree,
		     NEW_FCALL(rb_intern("print"),
			       NEW_ARRAY(NEW_GVAR(rb_intern("$_")))));
}

void
yywhile_loop(chop, split)
    int chop, split;
{
    if (split) {
	eval_tree =
	    block_append(NEW_GASGN(rb_intern("$F"),
				   NEW_CALL(NEW_GVAR(rb_intern("$_")),
					    rb_intern("split"), 0)),
				   eval_tree);
    }
    if (chop) {
	eval_tree =
	    block_append(NEW_CALL(NEW_GVAR(rb_intern("$_")),
				  rb_intern("chop!"), 0), eval_tree);
    }
    eval_tree = NEW_OPT_N(eval_tree);
}

static struct op_tbl rb_op_tbl[] = {
    DOT2,	"..",
    '+',	"+",
    '-',	"-",
    '+',	"+(binary)",
    '-',	"-(binary)",
    '*',	"*",
    '/',	"/",
    '%',	"%",
    POW,	"**",
    UPLUS,	"+@",
    UMINUS,	"-@",
    UPLUS,	"+(unary)",
    UMINUS,	"-(unary)",
    '|',	"|",
    '^',	"^",
    '&',	"&",
    CMP,	"<=>",
    '>',	">",
    GEQ,	">=",
    '<',	"<",
    LEQ,	"<=",
    EQ,		"==",
    EQQ,	"===",
    NEQ,	"!=",
    MATCH,	"=~",
    NMATCH,	"!~",
    '!',	"!",
    '~',	"~",
    '!',	"!(unary)",
    '~',	"~(unary)",
    '!',	"!@",
    '~',	"~@",
    AREF,	"[]",
    ASET,	"[]=",
    LSHFT,	"<<",
    RSHFT,	">>",
    COLON2,	"::",
    '`',	"`",
    0,		0,
};

char *rb_id2name();
char *rb_class2name();

static st_table *rb_symbol_tbl;

#define sym_tbl rb_symbol_tbl

void
Init_sym()
{
    int strcmp();

    sym_tbl = st_init_strtable();
    rb_global_variable((VALUE*)&cur_cref);
    rb_global_variable((VALUE*)&lex_lastline);
}

ID
rb_intern(name)
    char *name;
{
    static ID last_id = LAST_TOKEN;
    int id;
    int last;

    if (st_lookup(sym_tbl, name, &id))
	return id;

    id = ++last_id;
    id <<= ID_SCOPE_SHIFT;
    switch (name[0]) {
      case '$':
	id |= ID_GLOBAL;
	break;
      case '@':
	id |= ID_INSTANCE;
	break;
	/* fall through */
      default:
	if (name[0] != '_' && !isalpha(name[0]) && !ismbchar(name[0])) {
	    /* operator */
	    int i;

	    id = 0;
	    for (i=0; rb_op_tbl[i].token; i++) {
		if (*rb_op_tbl[i].name == *name &&
		    strcmp(rb_op_tbl[i].name, name) == 0) {
		    id = rb_op_tbl[i].token;
		    break;
		}
	    }
	    if (id == 0) NameError("Unknown operator `%s'", name);
	    break;
	}
	
	last = strlen(name)-1;
	if (name[last] == '=') {
	    /* attribute assignment */
	    char *buf = ALLOCA_N(char,last+1);

	    strncpy(buf, name, last);
	    buf[last] = '\0';
	    id = rb_intern(buf);
	    id &= ~ID_SCOPE_MASK;
	    id |= ID_ATTRSET;
	}
	else if (isupper(name[0])) {
	    id |= ID_CONST;
        }
	else {
	    id |= ID_LOCAL;
	}
	break;
    }
    st_add_direct(sym_tbl, strdup(name), id);
    return id;
}

struct find_ok {
    ID id;
    char *name;
};

static int
id_find(name, id1, ok)
    char *name;
    ID id1;
    struct find_ok *ok;
{
    if (id1 == ok->id) {
	ok->name = name;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

char *
rb_id2name(id)
    ID id;
{
    struct find_ok ok;

    if (id < LAST_TOKEN) {
	int i = 0;

	for (i=0; rb_op_tbl[i].token; i++) {
	    if (rb_op_tbl[i].token == id)
		return rb_op_tbl[i].name;
	}
    }

    ok.name = 0;
    ok.id = id;
    st_foreach(sym_tbl, id_find, &ok);
    if (!ok.name && is_attrset_id(id)) {
	char *res;
	ID id2; 

	id2 = (id & ~ID_SCOPE_MASK) | ID_LOCAL;
	res = rb_id2name(id2);

	if (res) {
	    char *buf = ALLOCA_N(char,strlen(res)+2);

	    strcpy(buf, res);
	    strcat(buf, "=");
	    rb_intern(buf);
	    return rb_id2name(id);
	}
    }
    return ok.name;
}

int
rb_is_const_id(id)
    ID id;
{
    if (is_const_id(id)) return TRUE;
    return FALSE;
}

int
rb_is_instance_id(id)
    ID id;
{
    if (is_instance_id(id)) return TRUE;
    return FALSE;
}

void
local_var_append(id)
    ID id;
{
    struct local_vars tmp;
    struct local_vars *save = lvtbl;

    if (the_scope->local_tbl) {
	tmp.cnt = the_scope->local_tbl[0];
	tmp.tbl = the_scope->local_tbl;
	lvtbl->dlev = 0;
    }
    lvtbl = &tmp;
    local_cnt(id);
    lvtbl = save;
}

static VALUE
special_local_get(c)
    char c;
{
    int cnt, max;

    if (!the_scope->local_vars) return Qnil;
    for (cnt=1, max=the_scope->local_tbl[0]+1; cnt<max ;cnt++) {
	if (the_scope->local_tbl[cnt] == c) {
	    return the_scope->local_vars[cnt-1];
	}
    }
    return Qnil;
}

static void
special_local_set(c, val)
    char c;
    VALUE val;
{
    int cnt, max;

    if (the_scope->local_tbl) {
	for (cnt=1, max=the_scope->local_tbl[0]+1; cnt<max ;cnt++) {
	    if (the_scope->local_tbl[cnt] == c) {
		the_scope->local_vars[cnt-1] = val;
		return;
	    }
	}
    }
    top_local_init();
    cnt = local_cnt(c);
    top_local_setup();
    the_scope->local_vars[cnt] = val;
}

VALUE
backref_get()
{
    return special_local_get('~');
}

void
backref_set(val)
    VALUE val;
{
    special_local_set('~', val);
}

VALUE
lastline_get()
{
    VALUE v = special_local_get('_');
    if (v == 1) return Qnil;	/* $_ undefined */
    return v;
}

void
lastline_set(val)
    VALUE val;
{
    special_local_set('_', val);
}
