/************************************************

  parse.y -

  $Author: matz $
  $Date: 1995/01/12 08:54:50 $
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

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
#define ID_LOCAL    0x00
#define ID_INSTANCE 0x01
#define ID_GLOBAL   0x02
#define ID_ATTRSET  0x03
#define ID_CONST    0x04

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

NODE *eval_tree = 0;

char *sourcefile;		/* current source file */
int   sourceline;		/* current line no. */

static int yylex();

static enum lex_state {
    EXPR_BEG,			/* ignore newline, +/- is a sign. */
    EXPR_MID,			/* newline significant, +/- is a sign. */
    EXPR_END,			/* newline significant, +/- is a operator. */
    EXPR_ARG,			/* newline significant, +/- is a sign(meybe). */
    EXPR_FNAME,			/* ignore newline, +/- is a operator. */
} lex_state;

static int class_nest = 0;
static int in_single = 0;
static ID cur_mid = 0;

static int value_expr();
static NODE *cond();

static NODE *block_append();
static NODE *list_append();
static NODE *list_concat();
static NODE *list_copy();
static NODE *expand_op();
static NODE *call_op();
static int in_defined = 0;

static NODE *gettable();
static NODE *asignable();
static NODE *aryset();
static NODE *attrset();
static void backref_error();

static void local_push();
static void local_pop();
static int  local_cnt();
static int  local_id();
static ID  *local_tbl();

static struct RVarmap *dyna_push();
static void dyna_pop();
static int dyna_in_block();

VALUE dyna_var_ref();
#define dyna_id(id) dyna_var_ref(id)

#define cref_push() NEW_CREF(0)
static void cref_pop();
static NODE *cref_list;

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

%token  CLASS
	MODULE
	DEF
	UNDEF
	BEGIN
	RESCUE
	ENSURE
	END
	IF
	THEN
	ELSIF
	ELSE
	CASE
	WHEN
	WHILE
	FOR
	IN
	REDO
	BREAK
	CONTINUE
	RETURN
	FAIL
	YIELD
	SUPER
	RETRY
	SELF
	NIL
	AND
	OR
	NOT
	_FILE_
	_LINE_
	IF_MOD
	WHILE_MOD
	ALIAS
	DEFINED

%token <id>   IDENTIFIER FID GVAR IVAR CONSTANT
%token <val>  INTEGER FLOAT STRING XSTRING REGEXP
%token <node> STRING2 XSTRING2 DREGEXP NTH_REF BACK_REF

%type <node> singleton
%type <val>  literal numeric
%type <node> compexpr exprs expr arg primary var_ref
%type <node> if_tail opt_else case_body cases rescue ensure
%type <node> call_args call_args0 args args2 opt_args
%type <node> superclass f_arglist f_args f_optarg f_opt
%type <node> array assoc_list assocs assoc undef_list
%type <node> mlhs mlhs_head mlhs_tail lhs iter_var opt_iter_var backref
%type <id>   variable symbol operation
%type <id>   cname fname op rest_arg
%type <num>  f_arg
%token UPLUS 		/* unary+ */
%token UMINUS 		/* unary- */
%token POW		/* ** */
%token CMP  		/* <=> */
%token EQ  		/* == */
%token NEQ  		/* != <> */
%token GEQ  		/* >= */
%token LEQ  		/* <= */
%token ANDOP OROP	/* && and || */
%token MATCH NMATCH	/* =~ and !~ */
%token DOT2 DOT3	/* .. and ... */
%token AREF ASET        /* [] and []= */
%token LSHFT RSHFT      /* << and >> */
%token COLON2           /* :: */
%token <id> OP_ASGN     /* +=, -=  etc. */
%token ASSOC            /* => */
%token LPAREN           /* ( */
%token LBRACK           /* [ */
%token LBRACE           /* { */
%token STAR             /* * */
%token SYMBEG

/*
 *	precedence table
 */

%left  IF_MOD WHILE_MOD
%right NOT
%left  OR AND
%right '=' OP_ASGN
%nonassoc DOT2 DOT3
%left  OROP
%left  ANDOP
%nonassoc  CMP EQ NEQ MATCH NMATCH
%left  '>' GEQ '<' LEQ
%left  '|' '^'
%left  '&'
%left  LSHFT RSHFT
%left  '+' '-'
%left  '*' '/' '%'
%right '!' '~' UPLUS UMINUS
%right POW
%left  COLON2

%token LAST_TOKEN

%%
program		:  {
			lex_state = EXPR_BEG;
                        top_local_init();
		    }
		  compexpr
		    {
			eval_tree = block_append(eval_tree, $2);
                        top_local_setup();
		    }

compexpr	: exprs opt_term

exprs		: /* none */
		    {
			$$ = Qnil;
		    }
		| expr
		| exprs term expr
		    {
			$$ = block_append($1, $3);
		    }
		| exprs error
		    {
			lex_state = EXPR_BEG;
		    }
		  expr
		    {
			yyerrok;
			$$ = block_append($1, $4);
		    }

expr		: mlhs '=' args2
		    {
			value_expr($3);
			$1->nd_value = $3;
			$$ = $1;
		    }
		| assocs
		    {
			$$ = NEW_HASH($1);
		    }
		| RETURN args2
		    {
			value_expr($2);
			if (!cur_mid && !in_single)
			    Error("return appeared outside of method");
			$$ = NEW_RET($2);
		    }
		| FAIL args2
		    {
			value_expr($2);
			$$ = NEW_FAIL($2);
		    }
		| YIELD args2
		    {
			value_expr($2);
			$$ = NEW_YIELD($2);
		    }
		| DEFINED {in_defined = 1;} arg
		    {
		        in_defined = 0;
			$$ = NEW_DEFINED($3);
		    }
		| operation call_args0
		    {
			$$ = NEW_FCALL($1, $2);
		    }
		| primary '.' operation call_args0
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $4);
		    }
		| SUPER call_args0
		    {
			if (!cur_mid && !in_single && !in_defined)
			    Error("super called outside of method");
			$$ = NEW_SUPER($2);
		    }
		| UNDEF undef_list
		    {
			$$ = $2;
		    }
		| ALIAS fname {lex_state = EXPR_FNAME;} fname
		    {
		        $$ = NEW_ALIAS($2, $4);
		    }
		| expr IF_MOD expr
		    {
			value_expr($3);
			$$ = NEW_IF(cond($3), $1, Qnil);
		    }
		| expr WHILE_MOD expr
		    {
			value_expr($3);
			if (nd_type($1) == NODE_BEGIN) {
			    $$ = NEW_WHILE2(cond($3), $1);
			}
			else {
			    $$ = NEW_WHILE(cond($3), $1);
			}
		    }
		| expr AND expr
		    {
			value_expr($1);
			$$ = NEW_AND(cond($1), cond($3));
		    }
		| expr OR expr
		    {
			value_expr($1);
			$$ = NEW_OR(cond($1), cond($3));
		    }
		| NOT expr
		    {
			value_expr($2);
			$$ = NEW_NOT(cond($2));
		    }
		| arg

mlhs		: mlhs_head
		    {
			$$ = NEW_MASGN(NEW_LIST($1), Qnil);
		    }
		| mlhs_head STAR lhs
		    {
			$$ = NEW_MASGN(NEW_LIST($1), $3);
		    }
		| mlhs_head mlhs_tail
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2),Qnil);
		    }
		| mlhs_head mlhs_tail comma STAR lhs
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2),$5);
		    }

mlhs_head	: lhs comma

mlhs_tail	: lhs
		    {
			$$ = NEW_LIST($1);
		    }
		| mlhs_tail comma lhs
		    {
			$$ = list_append($1, $3);
		    }

lhs		: variable
		    {
			$$ = asignable($1, Qnil);
		    }
		| primary '[' opt_args opt_nl rbracket
		    {
			$$ = aryset($1, $3, Qnil);
		    }
		| primary '.' IDENTIFIER
		    {
			$$ = attrset($1, $3, Qnil);
		    }
		| backref
		    {
		        backref_error($1);
			$$ = Qnil;
		    }

cname		: IDENTIFIER
		    {
			Error("class/module name must be CONSTANT");
		    }
		| CONSTANT

fname		: IDENTIFIER
		| FID
		| CONSTANT
		| op
		    {
			lex_state = EXPR_END;
			$$ = $1;
		    }

undef_list	: fname
		    {
			$$ = NEW_UNDEF($1);
		    }
		| undef_list ',' fname
		    {
			$$ = block_append($1, NEW_UNDEF($3));
		    }

op		: DOT2		{ $$ = DOT2; }
		| '|'		{ $$ = '|'; }
		| '^'		{ $$ = '^'; }
		| '&'		{ $$ = '&'; }
		| CMP		{ $$ = CMP; }
		| EQ		{ $$ = EQ; }
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

arg		: variable '=' arg
		    {
			value_expr($3);
			$$ = asignable($1, $3);
		    }
		| primary '[' opt_args opt_nl rbracket '=' arg
		    {
			$$ = aryset($1, $3, $7);
		    }
		| primary '.' IDENTIFIER '=' arg
		    {
			$$ = attrset($1, $3, $5);
		    }
		| backref '=' arg
		    {
			value_expr($3);
		        backref_error($1);
			$$ = Qnil;
		    }
		| variable OP_ASGN arg
		    {
		  	NODE *val;

			value_expr($3);
			if (is_local_id($1)) {
			    if (local_id($1)) val = NEW_LVAR($1);
			    else val = NEW_DVAR($1);
			}
			else if (is_global_id($1)) {
			    val = NEW_GVAR($1);
			}
			else if (is_instance_id($1)) {
			    val = NEW_IVAR($1);
			}
			else {
			    val = NEW_CVAR($1);
			}
		  	$$ = asignable($1, call_op(val, $2, 1, $3));
		    }
		| primary '[' opt_args opt_nl rbracket OP_ASGN arg
		    {
			NODE *args = NEW_LIST($7);

			if ($3) list_concat(args, $3);
			$$ = NEW_OP_ASGN1($1, $6, args);
		    }
		| primary '.' IDENTIFIER OP_ASGN arg
		    {
			$$ = NEW_OP_ASGN2($1, $4, $5);
		    }
		| backref OP_ASGN arg
		    {
		        backref_error($1);
			$$ = Qnil;
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
		| arg NEQ arg
		    {
			$$ = NEW_NOT(call_op($1, EQ, 1, $3));
		    }
		| arg MATCH arg
		    {
			$$ = NEW_CALL($1, MATCH, NEW_LIST($3));
		    }
		| arg NMATCH arg
		    {
			$$ = NEW_NOT(NEW_CALL($1, MATCH, NEW_LIST($3)));
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
		| arg COLON2 cname
		    {
			$$ = NEW_COLON2($1, $3);
		    }
		| arg ANDOP arg
		    {
			value_expr($1);
			$$ = NEW_AND(cond($1), cond($3));
		    }
		| arg OROP arg
		    {
			value_expr($1);
			$$ = NEW_OR(cond($1), cond($3));
		    }
		| primary
		    {
			$$ = $1;
		    }

call_args	: /* none */
		    {
			$$ = Qnil;
		    }
		| call_args0 opt_nl

call_args0	: args
		| assocs
		    {
			$$ = NEW_LIST(NEW_HASH($1));
		    }
		| args comma assocs
		    {
			$$ = list_append($1, NEW_HASH($3));
		    }
		| args comma assocs comma STAR arg
		    {
			$$ = list_append($1, NEW_HASH($3));
			$$ = call_op($$, '+', 1, $6);
		    }
		| args comma STAR arg
		    {
			$$ = call_op($1, '+', 1, $4);
		    }
		| STAR arg
		    {
			$$ = $2;
		    }

opt_args	: /* none */
		    {
			$$ = Qnil;
		    }
		| args

args 		: arg
		    {
			value_expr($1);
			$$ = NEW_LIST($1);
		    }
		| args comma arg
		    {
			value_expr($3);
			$$ = list_append($1, $3);
		    }

args2		: args
		    {
			if ($1 && $1->nd_next == Qnil) {
			    $$ = $1->nd_head;
			}
			else {
			    $$ = $1;
			}
		    }

array		: /* none */
		    {
			$$ = Qnil;
		    }
		| args trailer

primary		: literal
		    {
			$$ = NEW_LIT($1);
		    }
		| STRING
		    {
			$$ = NEW_STR($1);
		    }
		| STRING2
		| XSTRING
		    {
			$$ = NEW_XSTR($1);
		    }
		| XSTRING2
		| DREGEXP
		| var_ref
		| backref
		| SUPER '(' call_args rparen
		    {
			if (!cur_mid && !in_single && !in_defined)
			    Error("super called outside of method");
			$$ = NEW_SUPER($3);
		    }
		| SUPER
		    {
			if (!cur_mid && !in_single && !in_defined)
			    Error("super called outside of method");
			$$ = NEW_ZSUPER();
		    }
		| primary '[' opt_args opt_nl rbracket
		    {
			value_expr($1);
			$$ = NEW_CALL($1, AREF, $3);
		    }
		| LBRACK array rbracket
		    {
			if ($2 == Qnil)
			    $$ = NEW_ZARRAY(); /* zero length array*/
			else {
			    $$ = $2;
			}
		    }
		| LBRACE assoc_list rbrace
		    {
			$$ = NEW_HASH($2);
		    }
		| REDO
		    {
			$$ = NEW_REDO();
		    }
		| BREAK
		    {
			$$ = NEW_BREAK();
		    }
		| CONTINUE
		    {
			$$ = NEW_CONT();
		    }
		| RETRY
		    {
			$$ = NEW_RETRY();
		    }
		| RETURN
		    {
			if (!cur_mid && !in_single)
			    Error("return appeared outside of method");
			$$ = NEW_RET(Qnil);
		    }
		| FAIL '(' args2 ')'
		    {
			if (nd_type($3) == NODE_ARRAY) {
			    Error("wrong number of argument to fail(0 or 1)");
			}
			value_expr($3);
			$$ = NEW_FAIL($3);
		    }
		| FAIL '(' ')'
		    {
			$$ = NEW_FAIL(Qnil);
		    }
		| FAIL
		    {
			$$ = NEW_FAIL(Qnil);
		    }
		| YIELD '(' args2 ')'
		    {
			value_expr($3);
			$$ = NEW_YIELD($3);
		    }
		| YIELD '(' ')'
		    {
			$$ = NEW_YIELD(Qnil);
		    }
		| YIELD
		    {
			$$ = NEW_YIELD(Qnil);
		    }
		| DEFINED '(' {in_defined = 1;} arg ')'
		    {
		        in_defined = 0;
			$$ = NEW_DEFINED($4);
		    }
		| primary '{' 
		    {
		        $<vars>$ = dyna_push();
		    }
		  opt_iter_var
		  compexpr rbrace
		    {
			if (nd_type($1) == NODE_LVAR
		            || nd_type($1) == NODE_CVAR) {
			    $1 = NEW_FCALL($1->nd_vid, Qnil);
			}
			$$ = NEW_ITER($4, $1, $5);
			dyna_pop($<vars>3);
		    }
		| FID
		    {
			$$ = NEW_FCALL($1, Qnil);
		    }
		| operation '(' call_args rparen
		    {
			$$ = NEW_FCALL($1, $3);
		    }
		| primary '.' operation '(' call_args rparen
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $5);
		    }
		| primary '.' operation
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, Qnil);
		    }
		| IF expr then
		  compexpr
		  if_tail
		  END
		    {
			value_expr($2);
			$$ = NEW_IF(cond($2), $4, $5);
		    }
		| WHILE expr term compexpr END
		    {
			value_expr($2);
			$$ = NEW_WHILE(cond($2), $4);
		    }
		| CASE compexpr
		  case_body
		  END
		    {
			value_expr($2);
			$$ = NEW_CASE($2, $3);
		    }
		| FOR iter_var IN expr term compexpr END
		    {
			value_expr($2);
			$$ = NEW_FOR($2, $4, $6);
		    }
		| BEGIN
		  compexpr
		  rescue
		  ensure
		  END
		    {
			$$ = NEW_BEGIN($2, $3, $4);
		    }
		| LPAREN exprs opt_nl rparen
		    {
			$$ = $2;
		    }
		| CLASS cname superclass
		    {
			if (cur_mid || in_single)
			    Error("class definition in method body");

			class_nest++;
			cref_push();
			local_push();
		    }
		  compexpr
		  END
		    {
		        $$ = NEW_CLASS($2, $5, $3);
		        local_pop();
			cref_pop();
			class_nest--;
		    }
		| MODULE cname
		    {
			if (cur_mid || in_single)
			    Error("module definition in method body");
			class_nest++;
			cref_push();
			local_push();
		    }
		  compexpr
		  END
		    {
		        $$ = NEW_MODULE($2, $4);
		        local_pop();
			cref_pop();
			class_nest--;
		    }
		| DEF fname
		    {
			if (cur_mid || in_single)
			    Error("nested method definition");
			cur_mid = $2;
			local_push();
		    }
		  f_arglist
		  compexpr
		  END
		    {
			$$ = NEW_DEFN($2, $4, $5, class_nest?0:1);
		        local_pop();
			cur_mid = 0;
		    }
		| DEF singleton '.' fname
		    {
			value_expr($2);
			in_single++;
			local_push();
		        lex_state = EXPR_END; /* force for args */
		    }
		  f_arglist
		  compexpr
		  END
		    {
			$$ = NEW_DEFS($2, $4, $6, $7);
		        local_pop();
			in_single--;
		    }

then		: term
		| THEN
		| term THEN

if_tail		: opt_else
		| ELSIF expr then
		  compexpr
		  if_tail
		    {
			value_expr($2);
			$$ = NEW_IF(cond($2), $4, $5);
		    }

opt_else	: /* none */
		    {
			$$ = Qnil;
		    }
		| ELSE compexpr
		    {
			$$ = $2;
		    }

iter_var	: lhs
		| mlhs

opt_iter_var	: /* node */
		    {
			$$ = Qnil;
		    }
		| '|' /* none */  '|'
		    {
			$$ = Qnil;
		    }
		| OROP
		    {
			$$ = Qnil;
		    }
		| '|' iter_var '|'
		    {
			$$ = $2;
		    }

case_body	: WHEN args then
		  compexpr
		  cases
		    {
			$$ = NEW_WHEN($2, $4, $5);
		    }

cases		: opt_else
		| case_body

rescue		: /* none */
		    {
			$$ = Qnil;
		    }
		| RESCUE compexpr
		    {
			if ($2 == Qnil)
			    $$ = (NODE*)1;
			else
			    $$ = $2;
		    }

ensure		: /* none */
		    {
			$$ = Qnil;
		    }
		| ENSURE compexpr
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
		| NIL
		    {
			$$ = NIL;
		    }
		| SELF
		    {
			$$ = SELF;
		    }

var_ref		: variable
		    {
			$$ = gettable($1);
		    }

backref		: NTH_REF
		| BACK_REF

superclass	: term
		    {
			$$ = Qnil;
		    }
		| colon
		    {
			lex_state = EXPR_BEG;
		    }
		  expr term
		    {
			$$ = $3;
		    }

f_arglist	: '(' f_args rparen
		    {
			$$ = $2;
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
		| f_arg comma rest_arg
		    {
			$$ = NEW_ARGS($1, 0, $3);
		    }
		| f_arg comma f_optarg
		    {
			$$ = NEW_ARGS($1, $3, -1);
		    }
		| f_arg comma f_optarg comma rest_arg
		    {
			$$ = NEW_ARGS($1, $3, $5);
		    }
		| f_optarg
		    {
			$$ = NEW_ARGS(0, $1, -1);
		    }
		| f_optarg comma rest_arg
		    {
			$$ = NEW_ARGS(0, $1, $3);
		    }
		| rest_arg
		    {
			$$ = NEW_ARGS(0, 0, $1);
		    }
		| error
		    {
			lex_state = EXPR_BEG;
			$$ = NEW_ARGS(0, 0, -1);
		    }

f_arg		: IDENTIFIER
		    {
			if (!is_local_id($1))
			    Error("formal argument must be local variable");
			local_cnt($1);
			$$ = 1;
		    }
		| f_arg comma IDENTIFIER
		    {
			if (!is_local_id($3))
			    Error("formal argument must be local variable");
			local_cnt($3);
			$$ += 1;
		    }

f_opt		: IDENTIFIER '=' arg
		    {
			if (!is_local_id($1))
			    Error("formal argument must be local variable");
			$$ = asignable($1, $3);
		    }

f_optarg	: f_opt
		    {
			$$ = NEW_BLOCK($1);
		    }
		| f_optarg comma f_opt
		    {
			$$ = block_append($1, $3);
		    }

rest_arg	: STAR IDENTIFIER
		    {
			if (!is_local_id($2))
			    Error("rest argument must be local variable");
			$$ = local_cnt($2);
		    }

singleton	: var_ref
		    {
			if (nd_type($1) == NODE_SELF) {
			    $$ = NEW_SELF();
			}
			else if (nd_type($1) == NODE_NIL) {
			    Error("Can't define single method for nil.");
			    $$ = Qnil;
			}
			else {
			    $$ = $1;
			}
		    }
		| LPAREN expr opt_nl rparen
		    {
			switch (nd_type($2)) {
			  case NODE_STR:
			  case NODE_STR2:
			  case NODE_XSTR:
			  case NODE_XSTR2:
			  case NODE_DREGX:
			  case NODE_LIT:
			  case NODE_ARRAY:
			  case NODE_ZARRAY:
			    Error("Can't define single method for literals.");
			  default:
			    break;
			}
			$$ = $2;
		    }

assoc_list	: /* none */
		    {
			$$ = Qnil;
		    }
		| assocs trailer
		    {
			$$ = $1;
		    }
		| args trailer
		    {
			if ($1->nd_alen%2 != 0) {
			    Error("odd number list for Hash");
			}
			$$ = $1;
		    }

assocs		: assoc
		| assocs comma assoc
		    {
			$$ = list_concat($1, $3);
		    }

assoc		: arg ASSOC arg
		    {
			$$ = list_append(NEW_LIST($1), $3);
		    }

operation	: IDENTIFIER
		| FID

opt_term	: /* none */
		| term

opt_nl		: /* none */
		| nl

trailer		: /* none */
		| nl
		| comma

term		: sc
		| nl

sc		: ';'		{ yyerrok; }
nl		: '\n'		{ yyerrok; }

colon		: ':'
		| SYMBEG

rparen		: ')' 		{ yyerrok; }
rbracket	: ']'		{ yyerrok; }
rbrace		: '}'		{ yyerrok; }
comma		: ',' 		{ yyerrok; }

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

static NODE *var_extend();

#define LEAVE_BS 1

static char *lex_p;
static int lex_len;

void
lex_setsrc(src, ptr, len)
    char *src;
    char *ptr;
    int len;
{
    sourcefile = strdup(src);

    sourceline = 1;
    lex_p = ptr;
    lex_len = len;
}

#define nextc() ((--lex_len>=0)?(*lex_p++):-1)
#define pushback() (lex_len++, lex_p--)

#define SCAN_HEX(i) 			\
do {					\
    int numlen;				\
    i=scan_hex(lex_p, 2, &numlen);	\
    lex_p += numlen;			\
    lex_len -= numlen;			\
} while (0)

#define SCAN_OCT(i) 			\
do {					\
    int numlen;				\
    i=scan_oct(lex_p, 3, &numlen);	\
    lex_p += numlen;			\
    lex_len -= numlen;			\
} while (0)

#define tokfix() (tokenbuf[tokidx]='\0')
#define tok() tokenbuf
#define toklen() tokidx
#define toklast() (tokidx>0?tokenbuf[tokidx-1]:0)

char *
newtok()
{
    tokidx = 0;
    if (!tokenbuf) {
	toksiz = 60;
	tokenbuf = ALLOC_N(char, 60);
    }
    if (toksiz > 1024) {
	REALLOC_N(tokenbuf, char, 60);
    }
    return tokenbuf;
}

void
tokadd(c)
    char c;
{
    if (tokidx >= toksiz) {
	toksiz *= 2;
	REALLOC_N(tokenbuf, char, toksiz);
    }
    tokenbuf[tokidx++] = c;
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
	pushback();
	SCAN_OCT(c);
	return c;

      case 'x':	/* hex constant */
	SCAN_HEX(c);
	return c;

      case 'b':	/* backspace */
	return '\b';

      case 'M':
	if ((c = nextc()) != '-') {
	    Error("Invalid escape character syntax");
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
	    Error("Invalid escape character syntax");
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
        Error("Invalid escape character syntax");
	pushback();
	return '\0';

      default:
	return c;
    }
}

static int
parse_regx()
{
    register int c;
    int casefold = 0;
    int in_brack = 0;
    int re_start = sourceline;
    NODE *list = Qnil;

    newtok();
    while ((c = nextc()) != -1) {
	switch (c) {
	  case '[':
	    in_brack = 1;
	    break;
	  case ']':
	    in_brack = 0;
	    break;

	  case '#':
	    list = var_extend(list, '/');
	    if (list == (NODE*)-1) return 0;
		continue;

	  case '\\':
	    switch (c = nextc()) {
	      case -1:
		sourceline = re_start;
		Error("unterminated regexp meets end of file");
		return 0;

	      case '\n':
		sourceline++;
		break;

	      case '\\':
		tokadd('\\');
		tokadd('\\');
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
		pushback();
		tokadd('\\');
		tokadd(read_escape());
	    }
	    continue;

	  case '/':		/* end of the regexp */
	    if (in_brack)
		break;

	    if ('i' == nextc()) {
		casefold = 1;
	    }
	    else {
		casefold = 0;
		pushback();
	    }

	    tokfix();
	    lex_state = EXPR_END;
	    if (list) {
		if (toklen() > 0) {
		    VALUE ss = str_new(tok(), toklen());
		    list_append(list, NEW_STR(ss));
		}
		nd_set_type(list, NODE_DREGX);
		if (casefold) list->nd_cflag = 1;
		yylval.node = list;
		return DREGEXP;
	    }
	    else {
		yylval.val = reg_new(tok(), toklen(), casefold);
		return REGEXP;
	    }
	  case -1:
	    Error("unterminated regexp");
	    return 0;

	  default:
	    if (ismbchar(c)) {
		tokadd(c);
		c = nextc();
	    }
	    break;
	}
	tokadd(c);
    }
    Error("unterminated regexp");
    return 0;
}

static int
parse_string(term)
    int term;
{
    int c;
    NODE *list = Qnil;
    int strstart;

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
	    list = var_extend(list, term);
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
                pushback();
                if (term != '"') tokadd('\\');
                tokadd(read_escape());
  	    }
	    continue;
	}
	tokadd(c);
    }
    tokfix();
    lex_state = EXPR_END;
    if (list == Qnil) {
	yylval.val = str_new(tok(), toklen());
	return (term == '`') ? XSTRING : STRING;
    }
    else {
	if (toklen() > 0) {
	    VALUE ss = str_new(tok(), toklen());
	    list_append(list, NEW_STR(ss));
	}
	yylval.node = list;
	if (term == '`') {
	    nd_set_type(list, NODE_XSTR2);
	    return XSTRING2;
	}
	else {
	    return STRING2;
	}
    }
}

#define LAST(v) ((v)-1 + sizeof(v)/sizeof(v[0]))

static struct kwtable {
    char *name;
    int id;
    enum lex_state state;
} kwtable [] = {
    "__END__",  0,              EXPR_BEG,
    "__FILE__", _FILE_,         EXPR_END,
    "__LINE__", _LINE_,         EXPR_END,
    "alias",	ALIAS,		EXPR_FNAME,
    "and",	AND,		EXPR_BEG,
    "begin",	BEGIN,		EXPR_BEG,
    "break",	BREAK,		EXPR_END,
    "case",	CASE,		EXPR_BEG,
    "class",	CLASS,		EXPR_BEG,
    "continue", CONTINUE,	EXPR_END,
    "def",	DEF,		EXPR_FNAME,
    "defined?",	DEFINED,	EXPR_END,
    "else",	ELSE,		EXPR_BEG,
    "elsif",	ELSIF,		EXPR_BEG,
    "end",	END,		EXPR_END,
    "ensure",	ENSURE,		EXPR_BEG,
    "fail", 	FAIL,		EXPR_END,
    "for", 	FOR,		EXPR_BEG,
    "if",	IF,		EXPR_BEG,
    "in",	IN,		EXPR_BEG,
    "module",	MODULE,		EXPR_BEG,
    "nil",	NIL,		EXPR_END,
    "not",	NOT,		EXPR_BEG,
    "or",	OR,		EXPR_BEG,
    "redo",	REDO,		EXPR_END,
    "rescue",	RESCUE,		EXPR_BEG,
    "retry",	RETRY,		EXPR_END,
    "return",	RETURN,		EXPR_MID,
    "self",	SELF,		EXPR_END,
    "super",	SUPER,		EXPR_END,
    "then",     THEN,           EXPR_BEG,
    "undef",	UNDEF,		EXPR_FNAME,
    "when",	WHEN,		EXPR_BEG,
    "while",	WHILE,		EXPR_BEG,
    "yield",	YIELD,		EXPR_END,
};

static void
arg_ambiguous()
{
    Warning("ambiguous first argument; make sure");
}

static int
yylex()
{
    register int c;
    int space_seen = 0;
    struct kwtable *low = kwtable, *mid, *high = LAST(kwtable);

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
	}
	/* fall through */
      case '\n':
	sourceline++;
	if (lex_state == EXPR_BEG
	    || lex_state == EXPR_FNAME)
	    goto retry;
	lex_state = EXPR_BEG;
	return '\n';

      case '*':
	if ((c = nextc()) == '*') {
	    lex_state = EXPR_BEG;
	    if (nextc() == '=') {
		yylval.id = POW;
		return OP_ASGN;
	    }
	    pushback();
	    return POW;
	}
	if (c == '=') {
	    yylval.id = '*';
	    lex_state = EXPR_BEG;
	    return OP_ASGN;
	}
	pushback();
	if (lex_state == EXPR_ARG && space_seen && !isspace(c)){
	    arg_ambiguous();
	    lex_state = EXPR_BEG;
	    return STAR;
	}
	if (lex_state == EXPR_BEG) {
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
	pushback();
	return '!';

      case '=':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    return EQ;
	}
	if (c == '~') {
	    return MATCH;
	}
	else if (c == '>') {
	    return ASSOC;
	}
	pushback();
	return '=';

      case '<':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    if ((c = nextc()) == '>') {
		return CMP;
	    }
	    pushback();
	    return LEQ;
	}
	if (c == '<') {
	    if (nextc() == '=') {
		yylval.id = LSHFT;
		return OP_ASGN;
	    }
	    pushback();
	    return LSHFT;
	}
	pushback();
	return '<';

      case '>':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    return GEQ;
	}
	if (c == '>') {
	    if (nextc() == '=') {
		yylval.id = RSHFT;
		return OP_ASGN;
	    }
	    pushback();
	    return RSHFT;
	}
	pushback();
	return '>';

      case '"':
      case '`':
	return parse_string(c);

      case '\'':
	{
	    int strstart;

	    strstart = sourceline;
	    newtok();
	    while ((c = nextc()) != '\'') {
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

		      case '\'':
			c = '\'';
			break;
		      case '\\':
			c = '\\';
			break;

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

      case '?':
	if ((c = nextc()) == '\\') {
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
	pushback();
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
	pushback();
	return '|';

      case '+':
	c = nextc();
	if (lex_state == EXPR_FNAME) {
	    if (c == '@') {
		return UPLUS;
	    }
	    pushback();
	    return '+';
	}
	if (lex_state == EXPR_ARG) {
	    if (!space_seen || c == '=' || isspace(c)) {
		arg_ambiguous();
		lex_state = EXPR_END;
	    }
	}
	if (lex_state != EXPR_END) {
	    pushback();
	    if (isdigit(c)) {
		goto start_num;
	    }
	    lex_state = EXPR_BEG;
	    return UPLUS;
	}
	lex_state = EXPR_BEG;
	if (c == '=') {
	    yylval.id = '+';
	    return OP_ASGN;
	}
	pushback();
	return '+';

      case '-':
	c = nextc();
	if (lex_state == EXPR_FNAME) {
	    if (c == '@') {
		return UMINUS;
	    }
	    pushback();
	    return '-';
	}
	if (lex_state == EXPR_ARG) {
	    if (!space_seen || c == '=' || isspace(c)) {
		arg_ambiguous();
		lex_state = EXPR_END;
	    }
	}
	if (lex_state != EXPR_END) {
	    if (isdigit(c)) {
		pushback();
		c = '-';
		goto start_num;
	    }
	    lex_state = EXPR_BEG;
	    pushback();
	    return UMINUS;
	}
	lex_state = EXPR_BEG;
	if (c == '=') {
	    yylval.id = '-';
	    return OP_ASGN;
	}
	pushback();
	return '-';

      case '.':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '.') {
	    if ((c = nextc()) == '.') {
		return DOT3;
	    }
	    pushback();
	    return DOT2;
	}
	pushback();
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

	    lex_state = EXPR_END;
	    newtok();
	    if (c == '0') {
		c = nextc();
		if (c == 'x' || c == 'X') {
		    /* hexadecimal */
		    while (c = nextc()) {
			if (!isxdigit(c)) break;
			tokadd(c);
		    }
		    pushback();
		    tokfix();
		    yylval.val = str2inum(tok(), 16);
		    return INTEGER;
		}
		else if (c >= '0' && c <= '9') {
		    /* octal */
		    do {
			tokadd(c);
			c = nextc();
		    } while (c >= '0' && c <= '9');
		    pushback();
		    tokfix();
		    yylval.val = str2inum(tok(), 8);
		    return INTEGER;
		}
	    }
	    if (c == '-' || c == '+') {
		tokadd(c);
		c = nextc();
	    }

	    is_float = seen_point = seen_e = 0;

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
		    c = nextc();
		    if (!isdigit(c)) {
			pushback();
			goto decode_num;
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
	    pushback();
	    tokfix();
	    if (is_float) {
		double atof();

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
	    lex_state = EXPR_BEG;
	    return COLON2;
	}
	pushback();
	if (isspace(c))
	    return ':';
	return SYMBEG;

      case '/':
	if (lex_state == EXPR_BEG
	    || lex_state == EXPR_MID) {
	    return parse_regx();
	}
	c = nextc();
	if (lex_state == EXPR_ARG) {
	    if (space_seen && c != '=' && !isspace(c)) {
		pushback();
		arg_ambiguous();
		return parse_regx();
	    }
	}
	lex_state = EXPR_BEG;
	if (c == '=') {
	    yylval.id = '/';
	    return OP_ASGN;
	}
	pushback();
	return '/';

      case '^':
	lex_state = EXPR_BEG;
	if (nextc() == '=') {
	    yylval.id = '^';
	    return OP_ASGN;
	}
	pushback();
	return c;

      case ',':
	lex_state = EXPR_BEG;
	return c;

      case ';':
	lex_state = EXPR_BEG;
	return c;

      case '~':
	if (lex_state == EXPR_FNAME) {
	    if ((c = nextc()) != '@') {
		pushback();
	    }
	}
	lex_state = EXPR_BEG;
	return c;

      case '(':
	if (lex_state == EXPR_BEG
	    || lex_state == EXPR_MID) {
	    c = LPAREN;
	    lex_state = EXPR_BEG;
	}
	else if (lex_state == EXPR_ARG && space_seen) {
	    arg_ambiguous();
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
		pushback();
		return AREF;
	    }
	    pushback();
	    return '[';
	}
	else if (lex_state == EXPR_BEG
		 || lex_state == EXPR_MID) {
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
	pushback();
	return '\\';

      case '%':
	lex_state = EXPR_BEG;
	if (nextc() == '=') {
	    yylval.id = '%';
	    return OP_ASGN;
	}
	pushback();
	return c;

      case '$':
	lex_state = EXPR_END;
	newtok();
	c = nextc();
	switch (c) {
	  case '~':		/* $~: match-data */
	    local_cnt('~');
	    /* fall through */
	  case '*':		/* $*: argv */
	  case '$':		/* $$: pid */
	  case '?':		/* $?: last status */
	  case '!':		/* $!: error string */
	  case '@':		/* $@: error position */
	  case '/':		/* $/: input record separator */
	  case '\\':		/* $\: output record separator */
	  case ',':		/* $,: output field separator */
	  case '.':		/* $.: last read line number */
	  case '_':		/* $_: last read line string */
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
	    pushback();
	    tokfix();
	    yylval.node = NEW_NTH_REF(atoi(tok()));
	    return NTH_REF;

	  default:
	    if (!is_identchar(c)) {
		pushback();
		return '$';
	    }
	  case '0':
	    tokadd('$');
	}
	break;

      case '@':
	c = nextc();
	if (!is_identchar(c)) {
	    pushback();
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
	pushback();
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
	    while (low <= high) {
		mid = low + (high - low)/2;
		if (( c = strcmp(mid->name, tok())) == 0) {
		    enum lex_state state = lex_state;
		    lex_state = mid->state;
		    if (state != EXPR_BEG
			&& state != EXPR_BEG) {
			if (mid->id == IF) return IF_MOD;
			if (mid->id == WHILE) return WHILE_MOD;
		    }
		    return mid->id;
		}
		else if (c < 0) {
		    low = mid + 1;
		}
		else {
		    high = mid - 1;
		}
	    }

	    if (lex_state == EXPR_FNAME) {
		lex_state = EXPR_END;
		if ((c = nextc()) == '=') {
		    tokadd(c);
		}
		else {
		    pushback();
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
	yylval.id = rb_intern(tok());
	return result;
    }
}

static NODE*
var_extend(list, term)
    NODE *list;
    char term;
{
    int c, t, brace;
    VALUE ss;
    NODE *node;
    ID id;

    c = nextc();
    switch (c) {
      case '$':
      case '{':
	break;
      case '@':
	t = nextc();
	pushback();
	if (!is_identchar(t)) {
	    tokadd('#');
	    tokadd(c);
	    return list;
	}
      default:
	tokadd('#');
	pushback();
	return list;
    }

    ss = str_new(tok(), toklen());
    if (list == Qnil) {
	list = NEW_STR2(ss);
    }
    else if (toklen() > 0) {
	list_append(list, NEW_STR(ss));
    }
    newtok();
    if (c == '{') {
	brace = 1;
	c = nextc();
    }
    else {
	brace = 0;
    }

    switch (c) {
      case '$':
	c = nextc();
	if (c == -1) return (NODE*)-1;
	switch (c) {
	  case '&':
	  case '`':
	  case '\'':
	  case '+':
	    node = NEW_BACK_REF(c);
	    c = nextc();
	    goto append_node;

	  case '~':
	    local_cnt('~');
	    id = '~';
	    goto id_node;

	  case '1': case '2': case '3':
	  case '4': case '5': case '6':
	  case '7': case '8': case '9':
	    while (isdigit(c)) {
		tokadd(c);
		c = nextc();
	    }
	    tokfix();
	    node = NEW_NTH_REF(atoi(tok()));
	    goto append_node;
	}

	tokadd('$');
	if (!is_identchar(c)) {
	    tokadd(c);
	    goto fetch_id;
	}
	/* through */
      case '@':
	tokadd(c);
	c = nextc();
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

  fetch_id:
    tokfix();
    if (strcmp("__LINE__", tok()) == 0)
	id = _LINE_;
    else if (strcmp("__FILE__", tok()) == 0)
	id = _FILE_;
    else
	id = rb_intern(tok());
  id_node:
    node = gettable(id);

  append_node:
    if (brace) {
	if (c != '}')
	    Error("Invalid variable name in string");
    }
    else pushback();

    list_append(list, node);
    newtok();
    return list;
}


NODE*
newnode(type, a0, a1, a2)
    enum node_type type;
    NODE *a0, *a1, *a2;
{
    NODE *n = (NODE*)newobj();

    n->flags |= T_NODE;
    nd_set_type(n, type);
    n->line = sourceline;
    n->file = sourcefile;

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

static NODE*
block_append(head, tail)
    NODE *head, *tail;
{
    extern int verbose;
    NODE *last;

    if (tail == Qnil) return head;
    if (head == Qnil) return tail;

    if (nd_type(head) != NODE_BLOCK)
	head = last = NEW_BLOCK(head);
    else {
	last = head;
	while (last->nd_next) {
	    last = last->nd_next;
	}
    }

    if (verbose) {
	switch (nd_type(last->nd_head)) {
	  case NODE_BREAK:
	  case NODE_CONTINUE:
	  case NODE_REDO:
	  case NODE_RETURN:
	  case NODE_RETRY:
	    Warning("statement not reached");
	    break;

	  default:
	    break;
	}
    }
    
    if (nd_type(tail) != NODE_BLOCK) {
	tail = NEW_BLOCK(tail);
    }
    last->nd_next = tail;
    head->nd_alen += tail->nd_alen;
    return head;
}

static NODE*
list_append(head, tail)
    NODE *head, *tail;
{
    NODE *last;

    if (head == Qnil) return NEW_LIST(tail);

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

#if 0
    if (nd_type(head) != NODE_ARRAY || nd_type(tail) != NODE_ARRAY)
	Bug("list_concat() called with non-list");
#endif

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

    return NEW_CALL(recv, id, narg==1?NEW_LIST(arg1):Qnil);
}

static NODE*
gettable(id)
    ID id;
{
    if (id == SELF) {
	return NEW_SELF();
    }
    else if (id == NIL) {
	return NEW_NIL();
    }
    else if (id == _LINE_) {
	return NEW_LIT(INT2FIX(sourceline));
    }
    else if (id == _FILE_) {
	VALUE s = str_new2(sourcefile);

	return NEW_STR(s);
    }
    else if (is_local_id(id)) {
	if (local_id(id)) return NEW_LVAR(id);
	if (dyna_id(id)) return NEW_DVAR(id);
	/* method call without arguments */
	return NEW_FCALL(id, Qnil);
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
    return Qnil;
}

static NODE*
asignable(id, val)
    ID id;
    NODE *val;
{
    extern VALUE dyna_var_asgn();
    NODE *lhs = Qnil;

    if (id == SELF) {
	Error("Can't change the value of self");
    }
    else if (id == NIL) {
	Error("Can't asign to nil");
    }
    else if (id == _LINE_ || id == _FILE_) {
	Error("Can't asign to special identifier");
    }
    else if (is_local_id(id)) {
	if (local_id(id) || !dyna_in_block())
	    lhs = NEW_LASGN(id, val);
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
	    Error("class constant asigned in method body");
	lhs = NEW_CASGN(id, val);
    }
    else {
	Bug("bad id for variable");
    }
    return lhs;
}

static NODE *
aryset(recv, idx, val)
    NODE *recv, *idx, *val;
{
    value_expr(recv);
    value_expr(val);
    return NEW_CALL(recv, ASET, list_append(idx, val));
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
    if (node == Qnil) return TRUE;

    switch (nd_type(node)) {
      case NODE_RETURN:
      case NODE_CONTINUE:
      case NODE_BREAK:
      case NODE_REDO:
      case NODE_RETRY:
      case NODE_FAIL:
      case NODE_WHILE:
      case NODE_WHILE2:
      case NODE_CLASS:
      case NODE_MODULE:
      case NODE_DEFN:
      case NODE_DEFS:
	Error("void value expression");
	return FALSE;
	break;

      case NODE_BLOCK:
	while (node->nd_next) {
	    node = node->nd_next;
	}
	return value_expr(node->nd_head);

      case NODE_IF:
	return value_expr(node->nd_body) && value_expr(node->nd_else);

      default:
	return TRUE;
    }
}

static NODE *cond2();

static NODE*
cond0(node)
    NODE *node;
{
    enum node_type type = nd_type(node);

    if (type == NODE_STR || type == NODE_STR2 || type == NODE_DREGX) {
	return call_op(NEW_GVAR(rb_intern("$_")),MATCH,1,node);
    }
    else if (type == NODE_LIT && TYPE(node->nd_lit) == T_REGEXP) {
	return call_op(node,MATCH,1,NEW_GVAR(rb_intern("$_")));
    }
    else if (type == NODE_DOT2 || type == NODE_DOT3) {
	node->nd_beg = cond2(node->nd_beg);
	node->nd_end = cond2(node->nd_end);
	if (type == NODE_DOT2) nd_set_type(node,NODE_FLIP2);
	else if (type == NODE_DOT3) nd_set_type(node, NODE_FLIP3);
    }
    return node;
}

static NODE*
cond(node)
    NODE *node;
{
    enum node_type type = nd_type(node);

    switch (type) {
      case NODE_MASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_CASGN:
	Warning("asignment in condition");
	break;
    }

    node = cond0(node);
    if (type == NODE_CALL && node->nd_mid == '!') {
	if (node->nd_args || node->nd_recv == Qnil) {
	    Bug("method `!' called with wrong # of operand");
	}
	node->nd_recv = cond0(node->nd_recv);
    }
    return node;
}

static NODE*
cond2(node)
    NODE *node;
{
    node = cond(node);
    if (nd_type(node) == NODE_LIT && FIXNUM_P(node->nd_lit)) {
	return call_op(node,EQ,1,NEW_GVAR(rb_intern("$.")));
    }
    return node;
}

st_table *new_idhash();

static struct local_vars {
    ID *tbl;
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
    if (local->tbl) local->tbl[0] = local->cnt;
    free(local);
}

static ID*
local_tbl()
{
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
    if (lvtbl == 0) {
	local_push();
    }
    else if (the_scope->local_tbl) {
	lvtbl->cnt = the_scope->local_tbl[0];
    }
    else {
	lvtbl->cnt = 0;
    }
    if (lvtbl->cnt > 0) {
	lvtbl->tbl = ALLOC_N(ID, lvtbl->cnt+1);
	MEMCPY(lvtbl->tbl, the_scope->local_tbl, ID, lvtbl->cnt+1);
    }
    else {
	lvtbl->tbl = 0;
    }
    NEW_CREF0();		/* initialize constant c-ref */
    lvtbl->dlev = (the_dyna_vars?1:0);
}

static void
top_local_setup()
{
    int len = lvtbl->cnt;
    int i;

    if (len > 0) {
	i = lvtbl->tbl[0];

	if (i < len) {
	    if (the_scope->flag == SCOPE_ALLOCA) {
		VALUE *vars = the_scope->local_vars;
		the_scope->local_vars = ALLOC_N(VALUE, len);
		if (vars) {
		    MEMCPY(the_scope->local_vars, vars, VALUE, i);
		    MEMZERO(the_scope->local_vars+i, VALUE, len-i);
		}
		else {
		    MEMZERO(the_scope->local_vars, VALUE, len);
		}
		the_scope->flag = SCOPE_MALLOC;
	    }
	    else {
		REALLOC_N(the_scope->local_vars, VALUE, len);
		MEMZERO(the_scope->local_vars+i, VALUE, len-i);
		free(the_scope->local_tbl);
	    }
	    lvtbl->tbl[0] = len;
	    the_scope->local_tbl = lvtbl->tbl;
	}
	else if (lvtbl->tbl) {
	    free(lvtbl->tbl);
	}
    }
    cref_list = Qnil;
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
    NODE *cref = cref_list;

    cref_list = cref_list->nd_next;
    cref->nd_next = Qnil;
}

void
yyappend_print()
{
    eval_tree =
	block_append(eval_tree, NEW_FCALL(rb_intern("print"),
					  NEW_ARRAY(NEW_GVAR(rb_intern("$_")))));
}

void
yywhole_loop(chop, split)
    int chop, split;
{
    if (split) {
	eval_tree =
	    block_append(NEW_GASGN(rb_intern("$F"),
				   NEW_CALL(NEW_GVAR(rb_intern("$_")),
					    rb_intern("split"), Qnil)),
				   eval_tree);
    }
    if (chop) {
	eval_tree =
	    block_append(NEW_CALL(NEW_GVAR(rb_intern("$_")),
				  rb_intern("chop!"), Qnil), eval_tree);
    }
    eval_tree = NEW_WHILE(NEW_FCALL(rb_intern("gets"),0),eval_tree);
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
    UPLUS,	"+(unary)",
    UMINUS,	"-(unary)",
    UPLUS,	"+@",
    UMINUS,	"-@",
    '|',	"|",
    '^',	"^",
    '&',	"&",
    CMP,	"<=>",
    '>',	">",
    GEQ,	">=",
    '<',	"<",
    LEQ,	"<=",
    EQ,		"==",
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
    Qnil,	Qnil,
};

char *rb_id2name();
char *rb_class2name();

st_table *rb_symbol_tbl;

#define sym_tbl rb_symbol_tbl

void
Init_sym()
{
    int strcmp();

    sym_tbl = st_init_table(strcmp, st_strhash);
    rb_global_variable(&cref_list);
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
		if (strcmp(rb_op_tbl[i].name, name) == 0) {
		    id = rb_op_tbl[i].token;
		    break;
		}
	    }
	    if (id == 0) Bug("Unknown operator `%s'", name);
	    break;
	}
	
	last = strlen(name)-1;
	if (name[last] == '=') {
	    /* attribute asignment */
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

static char *find_ok;

static int
id_find(name, id1, id2)
    char *name;
    ID id1, id2;
{
    if (id1 == id2) {
	find_ok = name;
	return ST_STOP;
    }
    return ST_CONTINUE;
}

char *
rb_id2name(id)
    ID id;
{
    find_ok = 0;

    if (id < LAST_TOKEN) {
	int i = 0;

	for (i=0; rb_op_tbl[i].token; i++) {
	    if (rb_op_tbl[i].token == id)
		return rb_op_tbl[i].name;
	}
    }

    st_foreach(sym_tbl, id_find, id);
    if (!find_ok && is_attrset_id(id)) {
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
    return find_ok;
}

static int
const_check(id, val, class)
    ID id;
    VALUE val;
    struct RClass *class;
{
    if (is_const_id(id) && rb_const_defined(class, id)) {
	Warning("constant redefined for %s", rb_class2name(class));
        return ST_STOP;
    }
    return ST_CONTINUE;
}

void
rb_const_check(class, module)
    struct RClass *class, *module;
{
    st_foreach(module->iv_tbl, const_check, class);
}
