/************************************************

  parse.y -

  $Author: matz $
  $Date: 1994/06/27 15:48:34 $
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

%{

#define YYDEBUG 1
#include "ruby.h"
#include "env.h"
#include "node.h"
#include "st.h"

#include "ident.h"
#define is_id_nonop(id) ((id)>LAST_TOKEN)
#define is_local_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_LOCAL)
#define is_global_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_GLOBAL)
#define is_instance_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_INSTANCE)
#define is_variable_id(id) (is_id_nonop(id)&&((id)&ID_VARMASK))
#define is_attrset_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_ATTRSET)
#define is_const_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_CONST)

struct op_tbl {
    ID tok;
    char *name;
};

NODE *eval_tree = Qnil;
static int in_regexp;

enum {
    KEEP_STATE = 0,             /* don't change lex_state. */
    EXPR_BEG,			/* ignore newline, +/- is a sign. */
    EXPR_MID,			/* newline significant, +/- is a sign. */
    EXPR_END,			/* +/- is a operator. newline significant */
};

static int lex_state;

static ID cur_class = Qnil, cur_mid = Qnil;
static int in_module, in_single;

static void value_expr();
static NODE *cond();
static NODE *cond2();

static NODE *block_append();
static NODE *list_append();
static NODE *list_concat();
static NODE *list_copy();
static NODE *call_op();

static NODE *asignable();
static NODE *aryset();
static NODE *attrset();

static void push_local();
static void pop_local();
static int local_cnt();
static int local_id();
static ID *local_tbl();

struct global_entry* rb_global_entry();

static void init_top_local();
static void setup_top_local();
%}

%union {
    struct node *node;
    VALUE val;
    ID id;
}

%token  CLASS
	MODULE
	DEF
	FUNC
	UNDEF
	INCLUDE
	IF
	THEN
	ELSIF
	ELSE
	CASE
	WHEN
	UNLESS
	UNTIL
	WHILE
	FOR
	IN
	DO
	USING
	PROTECT
	RESQUE
	ENSURE
	END
	REDO
	BREAK
	CONTINUE
	RETURN
	YIELD
	SUPER
	RETRY
	SELF
	NIL

%token <id>  IDENTIFIER GVAR IVAR CONSTANT
%token <val> INTEGER FLOAT STRING REGEXP

%type <node> singleton inc_list
%type <val>  literal numeric
%type <node> compexpr exprs expr expr2 primary var_ref
%type <node> if_tail opt_else cases resque ensure opt_using
%type <node> call_args opt_args args f_arglist f_args f_arg
%type <node> assoc_list assocs assoc
%type <node> mlhs mlhs_head mlhs_tail lhs
%type <id>   superclass variable symbol
%type <id>   fname fname0 op rest_arg end_mark

%token UPLUS 		/* unary+ */
%token UMINUS 		/* unary- */
%token POW		/* ** */
%token CMP  		/* <=> */
%token EQ  		/* == */
%token NEQ  		/* != <> */
%token GEQ  		/* >= */
%token LEQ  		/* <= */
%token AND OR		/* && and || */
%token MATCH NMATCH	/* =~ and !~ */
%token DOT2 DOT3	/* .. and ... */
%token AREF ASET        /* [] and []= */
%token LSHFT RSHFT      /* << and >> */
%token COLON2           /* :: */
%token <id> SELF_ASGN   /* +=, -=  etc. */
%token ASSOC            /* => */

/*
 *	precedence table
 */

%left  YIELD RETURN
%right '=' SELF_ASGN
%right COLON2
%nonassoc DOT2 DOT3
%left  OR
%left  AND
%left  '|' '^'
%left  '&'
%nonassoc  CMP EQ NEQ MATCH NMATCH
%left  '>' GEQ '<' LEQ
%left  LSHFT RSHFT
%left  '+' '-'
%left  '*' '/' '%'
%right POW
%right '!' '~' UPLUS UMINUS

%token LAST_TOKEN

%%
program		:  {
			lex_state = EXPR_BEG;
                        init_top_local();
		    }
		  compexpr
		    {
			eval_tree = block_append(eval_tree, $2);
                        setup_top_local();
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
		| exprs error expr
		    {
			yyerrok;
			$$ = $1;
		    }

expr		: CLASS IDENTIFIER superclass
		    {
			if (cur_class || cur_mid || in_single)
			    Error("nested class definition");
			cur_class = $2;
			push_local();
		    }
		  compexpr
		  END end_mark
		    {
			if ($7 && $7 != CLASS) {
			    Error("unmatched end keyword(expected `class')");
			}
		        $$ = NEW_CLASS($2, $5, $3);
		        pop_local();
		        cur_class = Qnil;
		    }
		| MODULE IDENTIFIER
		    {
			if (cur_class != Qnil)
			    Error("nested module definition");
			cur_class = $2;
			in_module = 1;
			push_local();
		    }
		  compexpr
		  END end_mark
		    {
			if ($6 && $6 != MODULE) {
			    Error("unmatched end keyword(expected `module')");
			}
		        $$ = NEW_MODULE($2, $4);
		        pop_local();
		        cur_class = Qnil;
			in_module = 0;
		    }
		| DEF fname
		    {
			if (cur_mid || in_single)
			    Error("nested method definition");
			cur_mid = $2;
			push_local();
		    }
		  f_arglist compexpr
		  END end_mark
		    {
			if ($7 && $7 != DEF) {
			    Error("unmatched end keyword(expected `def')");
			}
			$$ = NEW_DEFN($2, NEW_RFUNC($4, $5), MTH_METHOD);
		        pop_local();
			cur_mid = Qnil;
		    }
		| DEF FUNC fname
		    {
			if (cur_mid || in_single)
			    Error("nested method definition");
			cur_mid = $3;
			push_local();
		    }
		  f_arglist compexpr
		  END end_mark
		    {
			if ($8 && $8 != DEF) {
			    Error("unmatched end keyword(expected `def')");
			}
			$$ = NEW_DEFN($3, NEW_RFUNC($5, $6), MTH_FUNC);
		        pop_local();
			cur_mid = Qnil;
		    }
		| DEF singleton '.' fname
		    {
			value_expr($2);
			in_single++;
			push_local();
		    }
		  f_arglist
		  compexpr
		  END end_mark
		    {
			if ($9 && $9 != DEF) {
			    Error("unmatched end keyword(expected `def')");
			}
			$$ = NEW_DEFS($2, $4, NEW_RFUNC($6, $7));
		        pop_local();
			in_single--;
		    }
		| UNDEF fname
		    {
			$$ = NEW_UNDEF($2);
		    }
		| DEF fname fname
		    {
			$$ = NEW_ALIAS($2, $3);
		    }
		| INCLUDE inc_list
		    {
			if (cur_mid || in_single)
			    Error("include appeared in method definition");
			$$ = $2;
		    }
		| mlhs '=' args
		    {
			NODE *rhs;

			if ($3->nd_next == Qnil) {
			    rhs = $3->nd_head;
			    free($3);
			}
			else {
			    rhs = $3;
			}

			$$ = NEW_MASGN($1, rhs);
		    }
		| expr2


mlhs		: mlhs_head
		| mlhs_head mlhs_tail
		    {
			$$ = list_concat($1, $2);
		    }

mlhs_head	: variable comma
		    {
			$$ = NEW_LIST(asignable($1, Qnil));
		    }
		| primary '[' args rbracket comma
		    {
			$$ = NEW_LIST(aryset($1, $3, Qnil));
		    }
		| primary '.' IDENTIFIER comma
		    {
			$$ = NEW_LIST(attrset($1, $3, Qnil));
		    }

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
		| primary '[' args rbracket
		    {
			$$ = aryset($1, $3, Qnil);
		    }
		| primary '.' IDENTIFIER 
		    {
			$$ = attrset($1, $3, Qnil);
		    }

superclass	: /* none */
		    {
			$$ = Qnil;
		    }
		| ':' IDENTIFIER
		    {
			$$ = $2;
		    }

inc_list	: IDENTIFIER
		    {
			$$ = NEW_INC($1);
		    }
		| inc_list comma IDENTIFIER
		    {
			$$ = block_append($1, NEW_INC($3));
		    }
		| error
		    {
			$$ = Qnil;
		    }
		| inc_list comma error

fname		: fname0
		| IVAR

fname0		: IDENTIFIER
		| IDENTIFIER '='
		    {
			ID id = $1;

			id &= ~ID_SCOPE_MASK;
			id |= ID_ATTRSET;
			$$ = id;
		    }
		| op

op		: COLON2	{ $$ = COLON2; }
		| DOT2		{ $$ = DOT2; }
		| '|'		{ $$ = '|'; }
		| '^'		{ $$ = '^'; }
		| '&'		{ $$ = '&'; }
		| CMP		{ $$ = CMP; }
		| EQ		{ $$ = EQ; }
		| NEQ		{ $$ = NEQ; }
		| MATCH		{ $$ = MATCH; }
		| NMATCH	{ $$ = NMATCH; }
		| '>'		{ $$ = '>'; }
		| GEQ		{ $$ = GEQ; }
		| '<'		{ $$ = '<'; }
		| LEQ		{ $$ = LEQ; }
		| LSHFT		{ $$ = LSHFT; }
		| RSHFT		{ $$ = RSHFT; }
		| '+'		{ $$ = '+'; }
		| '-'		{ $$ = '-'; }
		| '*'		{ $$ = '*'; }
		| '/'		{ $$ = '/'; }
		| '%'		{ $$ = '%'; }
		| POW		{ $$ = POW; }
		| '!'		{ $$ = '!'; }
		| '~'		{ $$ = '~'; }
		| '!' '@'	{ $$ = '!'; }
		| '~' '@'	{ $$ = '~'; }
		| '-' '@'	{ $$ = UMINUS; }
		| '+' '@'	{ $$ = UPLUS; }
		| '[' ']'	{ $$ = AREF; }
		| '[' ']' '='	{ $$ = ASET; }

f_arglist	: '(' f_args rparen
		    {
			$$ = $2;
		    }
		| term
		    {
			$$ = Qnil;
		    }

f_args		: /* no arg */
		    {
			$$ = Qnil;
		    }
		| f_arg
		    {
			$$ = NEW_ARGS($1, -1);
		    }
		| f_arg comma rest_arg
		    {
			$$ = NEW_ARGS($1, $3);
		    }
		| rest_arg
		    {
			$$ = NEW_ARGS(Qnil, $1);
		    }
		| f_arg error
		    {
			$$ = NEW_ARGS($1, -1);
		    }
		| error
		    {
			$$ = Qnil;
		    }

f_arg		: IDENTIFIER
		    {
			if (!is_local_id($1))
			    Error("formal argument must be local variable");
			$$ = NEW_LIST(local_cnt($1));
		    }
		| f_arg comma IDENTIFIER
		    {
			if (!is_local_id($3))
			    Error("formal argument must be local variable");
			$$ = list_append($1, local_cnt($3));
		    }

rest_arg	: '*' IDENTIFIER
		    {
			if (!is_local_id($2))
			    Error("rest argument must be local variable");
			$$ = local_cnt($2);
		    }

singleton	: var_ref
		    {
			if ($1->type == NODE_SELF) {
			    $$ = NEW_SELF();
			}
			else if ($1->type == NODE_NIL) {
			    Error("Can't define single method for nil.");
			    freenode($1);
			    $$ = Qnil;
			}
			else {
			    $$ = $1;
			}
		    }
		| '(' compexpr rparen
		    {
			switch ($2->type) {
			  case NODE_STR:
			  case NODE_LIT:
			  case NODE_ARRAY:
			  case NODE_ZARRAY:
			    Error("Can't define single method for literals.");
			  default:
			    break;
			}
			$$ = $2;
		    }

expr2		: IF expr2 then
		  compexpr
		  if_tail
		  END end_mark
		    {
			if ($7 && $7 != IF) {
			    Error("unmatched end keyword(expected `if')");
			}
			$$ = NEW_IF(cond($2), $4, $5);
		    }
		| UNLESS expr2 then 
		  compexpr opt_else END end_mark
		    {
			if ($7 && $7 != UNLESS) {
			    Error("unmatched end keyword(expected `if')");
			}
		        $$ = NEW_UNLESS(cond($2), $4, $5);
		    }
		| CASE expr2 opt_term
		  cases
		  END end_mark
		    {
			if ($6 && $6 != CASE) {
			    Error("unmatched end keyword(expected `case')");
			}
			value_expr($2);
			$$ = NEW_CASE($2, $4);
		    }
		| WHILE expr2 term compexpr END end_mark
		    {
			if ($6 && $6 != WHILE) {
			    Error("unmatched end keyword(expected `while')");
			}
			$$ = NEW_WHILE(cond($2), $4);
		    }
		| UNTIL expr2 term compexpr END end_mark
		    {
			if ($6 && $6 != UNTIL) {
			    Error("unmatched end keyword(expected `until')");
			}
			$$ = NEW_UNTIL(cond($2), $4);
		    }
		| FOR lhs IN expr2 term
		  compexpr
		  END end_mark
		    {
			if ($8 && $8 != FOR) {
			    Error("unmatched end keyword(expected `for')");
			}
			value_expr($4);
			$$ = NEW_FOR($2, $4, $6);
		    }
		| DO expr2 opt_using
		  compexpr
		  END end_mark
		    {
			if ($6 && $6 != DO) {
			    Error("unmatched end keyword(expected `do')");
			}
			value_expr($2);
			$$ = NEW_DO($3, $2, $4);
		    }
		| PROTECT
		  compexpr
		  resque
		  ensure
		  END end_mark
		    {
			if ($6 && $6 != PROTECT) {
			    Error("unmatched end keyword(expected `protect')");
			}
			if ($3 == Qnil && $4 == Qnil) {
			    Warning("useless protect clause");
			    $$ = $2;
			}
			else {
			    $$ = NEW_PROT($2, $3, $4);
			}
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
		| RETURN expr2
		    {
			value_expr($2);
			if (!cur_mid && !in_single)
			    Error("return appeared outside of method");
			$$ = NEW_RET($2);
		    }
		| RETURN
		    {
			if (!cur_mid && !in_single)
			    Error("return appeared outside of method");
			$$ = NEW_RET(Qnil);
		    }
		| variable '=' expr2
		    {
			value_expr($3);
			$$ = asignable($1, $3);
		    }
		| primary '[' args rbracket '=' expr2
		    {
			value_expr($6);
			$$ = aryset($1, $3, $6);
		    }
		| primary '.' IDENTIFIER '=' expr2
		    {
			value_expr($5);
			$$ = attrset($1, $3, $5);
		    }
		| variable SELF_ASGN expr2
		    {
		  	NODE *val;

			value_expr($3);
			if (is_local_id($1)) {
			    val = NEW_LVAR($1);
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
		| primary '[' args rbracket SELF_ASGN expr2
		    {
			NODE *rval, *args;
			value_expr($1);
			value_expr($6);

			args = list_copy($3);
			rval = NEW_CALL2($1, AREF, args);

			args = list_append($3, call_op(rval, $5, 1, $6));
			$$ = NEW_CALL($1, ASET, args);
		    }
		| primary '.' IDENTIFIER SELF_ASGN expr2
		    {
			ID id = $3;
			NODE *rval;

			value_expr($1);
			value_expr($5);

			id &= ~ID_SCOPE_MASK;
			id |= ID_ATTRSET;

			rval = call_op(NEW_CALL2($1, $3, Qnil), $4, 1, $5);
			$$ = NEW_CALL($1, id, NEW_LIST(rval));
		    }
		| YIELD expr2
		    {
			value_expr($2);
			$$ = NEW_YIELD($2);
		    }
		| expr2 DOT2 expr2
		    {
			$$ = call_op($1, DOT2, 1, $3);
		    }
		| expr2 DOT3 expr2
		    {
			$$ = NEW_DOT3(cond2($1), cond2($3));
		    }
		| expr2 '+' expr2
		    {
		        $$ = call_op($1, '+', 1, $3);
		    }
		| expr2 '-' expr2
		    {
		        $$ = call_op($1, '-', 1, $3);
		    }
		| expr2 '*' expr2
		    {
		        $$ = call_op($1, '*', 1, $3);
		    }
		| expr2 '/' expr2
		    {
			$$ = call_op($1, '/', 1, $3);
		    }
		| expr2 '%' expr2
		    {
			$$ = call_op($1, '%', 1, $3);
		    }
		| expr2 POW expr2
		    {
			$$ = call_op($1, POW, 1, $3);
		    }
		| '+' expr2		       %prec UPLUS
		    {
			$$ = call_op($2, UPLUS, 0);

		    }
		| '-' expr2	       	       %prec UMINUS
		    {
		        $$ = call_op($2, UMINUS, 0);
		    }
		| expr2 '|' expr2
		    {
		        $$ = call_op($1, '|', 1, $3);
		    }
		| expr2 '^' expr2
		    {
			$$ = call_op($1, '^', 1, $3);
		    }
		| expr2 '&' expr2
		    {
			$$ = call_op($1, '&', 1, $3);
		    }
		| expr2 CMP expr2
		    {
			$$ = call_op($1, CMP, 1, $3);
		    }
		| expr2 '>' expr2
		    {
			$$ = call_op($1, '>', 1, $3);
		    }
		| expr2 GEQ expr2
		    {
			$$ = call_op($1, GEQ, 1, $3);
		    }
		| expr2 '<' expr2
		    {
			$$ = call_op($1, '<', 1, $3);
		    }
		| expr2 LEQ expr2
		    {
			$$ = call_op($1, LEQ, 1, $3);
		    }
		| expr2 EQ expr2
		    {
			$$ = call_op($1, EQ, 1, $3);
		    }
		| expr2 NEQ expr2
		    {
			$$ = call_op($1, NEQ, 1, $3);
		    }
		| expr2 MATCH expr2
		    {
			$$ = call_op($1, MATCH, 1, $3);
		    }
		| expr2 NMATCH expr2
		    {
			$$ = call_op($1, NMATCH, 1, $3);
		    }
		| '!' expr2
		    {
			$$ = call_op(cond($2), '!', 0);
		    }
		| '~' expr2
		    {
			$$ = call_op($2, '~', 0);
		    }
		| expr2 LSHFT expr2
		    {
			$$ = call_op($1, LSHFT, 1, $3);
		    }
		| expr2 RSHFT expr2
		    {
			$$ = call_op($1, RSHFT, 1, $3);
		    }
		| expr2 COLON2 expr2
		    {
			$$ = call_op($1, COLON2, 1, $3);
		    }
		| expr2 AND expr2
		    {
			$$ = NEW_AND(cond($1), cond($3));
		    }
		| expr2 OR expr2
		    {
			$$ = NEW_OR(cond($1), cond($3));
		    }
		|primary
		    {
			$$ = $1;
		    }

then		: term
		| THEN
		| term THEN

if_tail		: opt_else
		| ELSIF expr2 then
		  compexpr
		  if_tail
		    {
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

opt_using	: term
		    {
			$$ = Qnil;
		    }
		| opt_term USING lhs term
		    {
			$$ = $3;
		    }

cases		: opt_else
		| WHEN args term
		  compexpr
		  cases
		    {
			$$ = NEW_WHEN($2, $4, $5);
		    }

resque		: /* none */
		    {
			$$ = Qnil;
		    }
		| RESQUE compexpr
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

call_args	: /* none */
		    {
			$$ = Qnil;
		    }
		| args
		| '*' exprs
		    {
			$$ = $2;
		    }
		| args comma '*' exprs
		    {
			$$ = call_op($1, '+', 1, $4);
		    }

opt_args	: /* none */
		    {
			$$ = Qnil;
		    }
		| args

args 		: expr2
		    {
			value_expr($1);
			$$ = NEW_LIST($1);
		    }
		| args comma expr2
		    {
			value_expr($3);
			$$ = list_append($1, $3);
		    }

primary		: var_ref
		| '(' compexpr rparen
		    {
			$$ = $2;
		    }

		| STRING
		    {
			literalize($1);
			$$ = NEW_STR($1);
		    }
		| primary '[' args rbracket
		    {
			value_expr($1);
			$$ = NEW_CALL($1, AREF, $3);
		    }
		| literal
		    {
			literalize($1);
			$$ = NEW_LIT($1);
		    }
		| '[' opt_args rbracket
		    {
			if ($2 == Qnil)
			    $$ = NEW_ZARRAY(); /* zero length array*/
			else {
			    $$ = $2;
			}
		    }
		| lbrace assoc_list rbrace
		    {
			$$ = NEW_HASH($2);
		    }
		| primary '.' IDENTIFIER '(' call_args rparen
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $5);
		    }
		| primary '.' IDENTIFIER
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, Qnil);
		    }
		| IDENTIFIER '(' call_args rparen
		    {
			$$ = NEW_CALL(Qnil, $1, $3);
		    }
		| IVAR '(' call_args rparen
		    {
			$$ = NEW_CALL(Qnil, $1, $3);
		    }
		| SUPER '(' call_args rparen
		    {
			if (!cur_mid && !in_single)
			    Error("super called outside of method");
			$$ = NEW_SUPER($3);
		    }
		| SUPER
		    {
			if (!cur_mid && !in_single)
			    Error("super called outside of method");
			$$ = NEW_ZSUPER();
		    }

literal		: numeric
		| '\\' symbol
		    {
			$$ = INT2FIX($2);
		    }
		| '/' {in_regexp = 1;} REGEXP
		    {
			$$ = $3;
		    }

symbol		: fname0
		| IVAR
		| GVAR
		| CONSTANT

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
			if ($1 == SELF) {
			    $$ = NEW_SELF();
			}
			else if ($1 == NIL) {
			    $$ = NEW_NIL();
			}
			else if (is_local_id($1)) {
			    if (local_id($1))
				$$ = NEW_LVAR($1);
			    else
				$$ = NEW_MVAR($1);
			}
			else if (is_global_id($1)) {
			    $$ = NEW_GVAR($1);
			}
			else if (is_instance_id($1)) {
			    $$ = NEW_IVAR($1);
			}
			else if (is_const_id($1)) {
			    $$ = NEW_CVAR($1);
			}
		    }

assoc_list	: /* none */
		    {
			$$ = Qnil;
		    }
		| assocs

assocs		: assoc
		| assocs comma assoc
		    {
			$$ = list_concat($1, $3);
		    }

assoc		: expr2 ASSOC expr2
		    {
			$$ = NEW_LIST($1);
			$$ = list_append($$, $3);
		    }

end_mark	: CLASS		{ $$ = CLASS; }
		| MODULE	{ $$ = MODULE; }
		| DEF		{ $$ = DEF; }
		| FUNC		{ $$ = FUNC; }
		| IF		{ $$ = IF; }
		| UNLESS	{ $$ = UNLESS; }
		| CASE		{ $$ = CASE; }
		| WHILE		{ $$ = WHILE; }
		| UNTIL		{ $$ = UNTIL; }
		| FOR		{ $$ = FOR; }
		| DO		{ $$ = DO; }
		| PROTECT	{ $$ = PROTECT; }
		| 		{ $$ = Qnil;}

opt_term	: /* none */
		| term

term		: sc
		| nl

sc		: ';'		{ yyerrok; }
nl		: '\n'		{ yyerrok; }

rparen		: ')' 		{ yyerrok; }
rbracket	: ']'		{ yyerrok; }
lbrace		: '{'		{ yyerrok; }
rbrace		: '}'		{ yyerrok; }
comma		: ',' 		{ yyerrok; }
%%

#include <stdio.h>
#include <ctype.h>
#include <sys/types.h>
#include "regex.h"

#define is_identchar(c) ((c)!=-1&&(isalnum(c) || (c) == '_' || ismbchar(c)))

static char *tokenbuf = NULL;
static int   tokidx, toksiz = 0;

char *xmalloc();
char *xrealloc();
VALUE newregexp();
VALUE newstring();
VALUE newfloat();
VALUE newinteger();
char *strdup();

#define EXPAND_B 1
#define LEAVE_BS 2

static void read_escape();

char *sourcefile;		/* current source file */
int   sourceline;		/* current line no. */

static char *lex_p;
static int lex_len;

lex_setsrc(src, ptr, len)
    char *src;
    char *ptr;
    int len;
{
    sourcefile = (char*)strdup(src);

    sourceline = 1;
    lex_p = ptr;
    lex_len = len;
}

#define nextc() ((--lex_len>=0)?(*lex_p++):-1)
#define pushback() (lex_len++, lex_p--)

#define tokfix() (tokenbuf[tokidx]='\0')
#define tok() tokenbuf
#define toklen() tokidx
#define toknow() &toknbuf[tokidx]

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

#define LAST(v) ((v)-1 + sizeof(v)/sizeof(v[0]))

static struct kwtable {
    char *name;
    int id;
    int state;
} kwtable [] = {
    "__END__",  0,             KEEP_STATE,
    "break",	BREAK,		EXPR_END,
    "case",	CASE,		KEEP_STATE,
    "class",	CLASS,		KEEP_STATE,
    "continue", CONTINUE,	EXPR_END,
    "def",	DEF,		KEEP_STATE,
    "do",	DO,		KEEP_STATE,
    "else",	ELSE,		EXPR_BEG,
    "elsif",	ELSIF,		EXPR_BEG,
    "end",	END,		EXPR_END,
    "ensure",	ENSURE,		EXPR_BEG,
    "for", 	FOR,		KEEP_STATE,
    "func", 	FUNC,		KEEP_STATE,
    "if",	IF,		KEEP_STATE,
    "in",	IN,		EXPR_BEG,
    "include",	INCLUDE,	EXPR_BEG,
    "module",	MODULE,		KEEP_STATE,
    "nil",	NIL,		EXPR_END,
    "protect",	PROTECT,	KEEP_STATE,
    "redo",	REDO,		EXPR_END,
    "resque",	RESQUE,		EXPR_BEG,
    "retry",	RETRY,		EXPR_END,
    "return",	RETURN,		EXPR_MID,
    "self",	SELF,		EXPR_END,
    "super",	SUPER,		EXPR_END,
    "then",     THEN,           EXPR_BEG,
    "undef",	UNDEF,		EXPR_BEG,
    "unless",	UNLESS,		EXPR_BEG,
    "until",	UNTIL,		EXPR_BEG,
    "using",	USING,		KEEP_STATE,
    "when",	WHEN,		EXPR_BEG,
    "while",	WHILE,		KEEP_STATE,
    "yield",	YIELD,		EXPR_BEG,
};

yylex()
{
    register int c;
    struct kwtable *low = kwtable, *mid, *high = LAST(kwtable);
    int last;

    if (in_regexp) {
	int in_brack = 0;
	int re_start = sourceline;

	in_regexp = 0;
	newtok();
	while (c = nextc()) {
	    switch (c) {
	      case '[':
		in_brack = 1;
		break;
	      case ']':
		in_brack = 0;
		break;
	      case '\\':
		if ((c = nextc()) == -1) {
		    sourceline = re_start;
		    Error("unterminated regexp meets end of file");
		    return 0;
		}
		else if (c == '\n') {
		    sourceline++;
		}
		else if (in_brack && c == 'b') {
		    tokadd('\b');
		}
		else {
		    pushback();
		    read_escape(LEAVE_BS);
		}
		continue;

	      case '/':		/* end of the regexp */
		if (in_brack)
		    break;

		tokfix();
		yylval.val = regexp_new(tok(), toklen());
		lex_state = EXPR_END;
		return REGEXP;

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
    }

retry:
    switch (c = nextc()) {
      case '\0':
      case '\004':
      case '\032':
      case -1:			/* end of script. */
	return 0;

	/* white spaces */
      case ' ': case '\t': case '\f': case '\r':
	goto retry;

      case '#':		/* it's a comment */
	while ((c = nextc()) != '\n') {
	    if (c == -1)
		return 0;
	}
	/* fall through */
      case '\n':
	sourceline++;
	if (lex_state == EXPR_BEG) goto retry;
	lex_state = EXPR_BEG;
	return '\n';

      case '*':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '*') {
	    if (nextc() == '=') {
		yylval.id = POW;
		return SELF_ASGN;
	    }
	    pushback();
	    return POW;
	}
	else if (c == '=') {
	    yylval.id = '*';
	    return SELF_ASGN;
	}
	pushback();
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
		return SELF_ASGN;
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
		return SELF_ASGN;
	    }
	    pushback();
	    return RSHFT;
	}
	pushback();
	return '>';

      case '"':
	{
	    int strstart = sourceline;

	    newtok();
	    while ((c = nextc()) != '"') {
		if (c  == -1) {
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
		    if (c == '\n') {
			sourceline++;
		    }
		    else if (c == '"') {
			tokadd(c);
		    }
		    else {
			pushback();
			read_escape(LEAVE_BS | EXPAND_B);
		    }
		    continue;
		}
		tokadd(c);
	    }
	    tokfix();
	    yylval.val = str_new(tok(), toklen());
	    lex_state = EXPR_END;
	    return STRING;
	}

      case '\'':
	{
	    int strstart = sourceline;

	newtok();
	    while ((c = nextc()) != '\'') {
		if (c  == -1) {
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
	    newtok();
	    read_escape(EXPAND_B);
	    c = tok()[0];
	}
	c &= 0xff;
	yylval.val = INT2FIX(c);
	lex_state = EXPR_END;
	return INTEGER;

      case '&':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '&') {
	    return AND;
	}
	else if (c == '=') {
	    yylval.id = '&';
	    return SELF_ASGN;
	}
	pushback();
	return '&';

      case '|':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '|') {
	    return OR;
	}
	else if (c == '=') {
	    yylval.id = '|';
	    return SELF_ASGN;
	}
	pushback();
	return '|';

      case '+':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    c = nextc();
	    pushback();
	    if (isdigit(c)) {
		goto start_num;
	    }
	}
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    yylval.id = '+';
	    return SELF_ASGN;
	}
	pushback();
	return '+';

      case '-':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    c = nextc();
	    pushback();
	    if (isdigit(c)) {
		c = '-';
		goto start_num;
	    }
	}
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    yylval.id = '-';
	    return SELF_ASGN;
	}
	pushback();
	return '-';

      case '.':
	if ((c = nextc()) == '.') {
	    if ((c = nextc()) == '.') {
		return DOT3;
	    }
	    pushback();
	    lex_state = EXPR_BEG;
	    return DOT2;
	}
	pushback();
	if (!isdigit(c)) {
	    lex_state = EXPR_BEG;
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
#if 0
		    yylval.val = INT2FIX(strtoul(tok(), Qnil, 8));
#else
		    yylval.val = str2inum(tok(), 8);
#endif
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
	lex_state = EXPR_BEG;
	if (nextc() == ':') {
	    return COLON2;
	}
	pushback();
	return ':';

      case '/':
	lex_state = EXPR_BEG;
	if (nextc() == '=') {
	    yylval.id = '/';
	    return SELF_ASGN;
	}
	pushback();
	return c;

      case '^':
	lex_state = EXPR_BEG;
	if (nextc() == '=') {
	    yylval.id = '^';
	    return SELF_ASGN;
	}
	pushback();
	return c;

      case ',':
      case ';':
      case '`':
      case '[':
      case '(':
      case '{':
      case '~':
	lex_state = EXPR_BEG;
	return c;

      case '\\':
	c = nextc();
	if (c == '\n') goto retry; /* skip \\n */
	lex_state = EXPR_BEG;
	pushback();
	return '\\';

      case '%':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    /* class constant */
	    newtok();
	    tokadd('%');
	    c = nextc();
	    break;
	}
	else {
	    lex_state = EXPR_BEG;
	    if (nextc() == '=') {
		yylval.id = '%';
		return SELF_ASGN;
	    }
	    pushback();
	    return c;
	}

      case '$':
	newtok();
	tokadd(c);
	c = nextc();
	switch (c) {
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
	  case '&':		/* $&: last match */
	  case '~':		/* $~: match-data */
	  case '=':		/* $=: ignorecase */
	    tokadd(c);
	    tokadd('\0');
	    goto id_fetch;

	  default:
	    if (is_identchar(c))
		break;
	    pushback();
	    return tok()[0];
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
    pushback();
    tokfix();

    /* See if it is a reserved word.  */
    while (low <= high) {
	mid = low + (high - low)/2;
	if (( c = strcmp(mid->name, tok())) == 0) {
	    if (mid->state != KEEP_STATE) {
		lex_state = mid->state;
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

  id_fetch:
    lex_state = EXPR_END;
    yylval.id = rb_intern(tok());
    switch (tok()[0]) {
      case '%':
	return CONSTANT;
      case '$':
	return GVAR;
      case '@':
	return IVAR;
      default:
	return IDENTIFIER;
    }
}

static void
read_escape(flag)
    int flag;
{
    char c;

    switch (c = nextc()) {
      case '\\':	/* Backslash */
	tokadd('\\');
	break;

      case 'n':	/* newline */
	tokadd('\n');
	break;

      case 't':	/* horizontal tab */
	tokadd('\t');
	break;

      case 'r':	/* carriage-return */
	tokadd('\r');
	break;

      case 'f':	/* form-feed */
	tokadd('\r');
	break;

      case 'v':	/* vertical tab */
	tokadd('\13');
	break;

      case 'a':
	tokadd('\a');
	break;

      case 'e':	/* escape */
	tokadd(033);
	break;

      case 'M':
	if ((c = nextc()) != '-') {
	    Error("Invalid escape character syntax");
	    tokadd('\0');
	    return;
	}
	if ((c = nextc()) == '\\') {
	    read_escape(flag);
	    tokenbuf[tokidx-1] |= 0200; /* kludge */
	}
	else {
	    tokadd((c & 0xff) | 0200);
	}
	break;

      case 'C':
	if ((c = nextc()) != '-') {
	    Error("Invalid escape character syntax");
	    tokadd('\0');
	    return;
	}
    case '^':
	if ((c = nextc())== '\\') {
	    read_escape (flag);
	    tokenbuf[tokidx-1] &= 0237; /* kludge */
	}
	else if (c == '?')
	    tokadd(0177);
	else
	    tokadd(c & 0237);
	break;

      case '0': case '1': case '2': case '3':
      case '4': case '5': case '6': case '7':
	{	/* octal constant */
	    register int i = c - '0';
	    register int count = 0;

	    while (++count < 3) {
		if ((c = nextc()) >= '0' && c <= '7') {
		    i *= 8;
		    i += c - '0';
		}
		else {
		    pushback();
		    break;
		}
	    }
	    tokadd(i&0xff);
	}
	break;

      case 'x':	/* hex constant */
	{
	    register int i = c - '0';
	    register int count = 0;

	    while (++count < 2) {
		c = nextc();
		if ((c = nextc()) >= '0' && c <= '9') {
		    i *= 16;
		    i += c - '0';
		}
		else if ((int)index("abcdefABCDEF", (c = nextc()))) {
		    i *= 16;
		    i += toupper(c) - 'A' + 10;
		}
		else {
		    pushback();
		    break;
		}
	    }
	    tokadd(i&0xff);
	}
	break;

      case 'b':	/* backspace */
	if (flag & EXPAND_B) {
	    tokadd('\b');
	    return;
	}
	/* go turough */
      default:
	if (flag & LEAVE_BS) {
	    tokadd('\\');
	}
	tokadd(c);
	break;
    }
}

NODE*
newnode(type, a0, a1, a2)
    enum node_type type;
    NODE *a0, *a1, *a2;
{
    NODE *n = ALLOC(NODE);

    n->type = type;
    n->line = sourceline;
    n->src  = sourcefile;

    n->u1.node = a0;
    n->u2.node = a1;
    n->u3.node = a2;

    return n;
}

static NODE*
block_append(head, tail)
    NODE *head, *tail;
{
    extern int verbose;

    if (tail == Qnil) return head;
    if (head == Qnil) return tail;

    if (head->type != NODE_BLOCK)
	head = NEW_BLOCK(head);

    if (head->nd_last == Qnil) head->nd_last = head;

    if (verbose) {
	switch (head->nd_last->nd_head->type) {
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
    
    if (tail->type == NODE_BLOCK) {
	head->nd_last->nd_next = tail;
	head->nd_last = tail->nd_last;
    }
    else {
	head->nd_last->nd_next = NEW_BLOCK(tail);
	head->nd_last = head->nd_last->nd_next;
    }
    return head;
}

static NODE*
list_append(head, tail)
    NODE *head, *tail;
{
    if (head == Qnil) return NEW_ARRAY(tail);

    if (head->nd_last == Qnil) head->nd_last = head;

    head->nd_last->nd_next = NEW_ARRAY(tail);
    head->nd_last = head->nd_last->nd_next;
    return head;
}

static NODE*
list_concat(head, tail)
    NODE *head, *tail;
{
    NODE *last;

    if (head->type != NODE_ARRAY || tail->type != NODE_ARRAY)
	Bug("list_concat() called with non-list");

    last = (head->nd_last)?head->nd_last:head;
    last->nd_next = tail;
    head->nd_last = tail->nd_last;

    return head;
}

static NODE*
list_copy(list)
    NODE *list;
{
    NODE *tmp;

    if (list == Qnil) return Qnil;

    tmp = Qnil;
    while(list) {
	tmp = list_append(tmp, list->nd_head);
	list = list->nd_next;
    }
    return tmp;
}

void freenode(node)
    NODE *node;
{
    if (node == Qnil) return;

    switch (node->type) {
      case NODE_BLOCK:
      case NODE_ARRAY:
	freenode(node->nd_head);
	freenode(node->nd_next);
	break;
      case NODE_IF:
      case NODE_WHEN:
      case NODE_PROT:
	freenode(node->nd_cond);
	freenode(node->nd_body);
	freenode(node->nd_else);
	break;
      case NODE_CASE:
      case NODE_WHILE:
      case NODE_UNTIL:
      case NODE_AND:
      case NODE_OR:
	freenode(node->nd_head);
	freenode(node->nd_body);
	break;
      case NODE_DO:
      case NODE_FOR:
	freenode(node->nd_ibdy);
	freenode(node->nd_iter);
	break;
      case NODE_LASGN:
      case NODE_GASGN:
      case NODE_IASGN:
	freenode(node->nd_value);
	break;
      case NODE_CALL:
      case NODE_SUPER:
	freenode(node->nd_recv);
      case NODE_CALL2:
	freenode(node->nd_args);
	break;
      case NODE_DEFS:
	freenode(node->nd_recv);
	break;
      case NODE_RETURN:
      case NODE_YIELD:
	freenode(node->nd_stts);
	break;
      case NODE_STR:
      case NODE_LIT:
	unliteralize(node->nd_lit);
	break;
      case NODE_CONST:
	unliteralize(node->nd_cval);
	break;
      case NODE_ARGS:
	freenode(node->nd_frml);
	break;
      case NODE_SCOPE:
	free(node->nd_tbl);
	freenode(node->nd_body);
	break;
      case NODE_DEFN:
      case NODE_ZARRAY:
      case NODE_CFUNC:
      case NODE_BREAK:
      case NODE_CONTINUE:
      case NODE_RETRY:
      case NODE_LVAR:
      case NODE_GVAR:
      case NODE_IVAR:
      case NODE_MVAR:
      case NODE_CLASS:
      case NODE_MODULE:
      case NODE_INC:
      case NODE_NIL:
	break;
      default:
	Bug("freenode: unknown node type %d", node->type);
	break;
    }
    free(node);
}

struct call_arg {
    ID id;
    VALUE recv;
    int narg;
    VALUE arg;
};

static VALUE
call_lit(arg)
    struct call_arg *arg;
{
    return rb_funcall(arg->recv, arg->id, arg->narg, arg->arg);
}

static VALUE
except_lit()
{
    extern VALUE errstr;

    Error("%s", RSTRING(errstr)->ptr);
    return Qnil;
}

static NODE *
call_op(recv, id, narg, arg1)
    NODE *recv;
    ID id;
    int narg;
    NODE *arg1;
{
    NODE *args;

    value_expr(recv);
    if (narg == 1)
	value_expr(arg1);

    if (recv->type != NODE_LIT || recv->type != NODE_STR
	|| (narg == 0 && id == '~'
	    && (TYPE(recv->nd_lit)==T_REGEXP || TYPE(recv->nd_lit)==T_STRING))
	|| arg1->type == NODE_LIT || arg1->type == NODE_STR) {
	if (narg > 0) {
	    args = NEW_ARRAY(arg1);
	    args->nd_argc = 1;
	}
	else {
	    args = Qnil;
	}
	return NEW_CALL(recv, id, args);
    }
    else {
	struct call_arg arg_data;
	NODE *result;

	arg_data.recv = recv->nd_lit;
	arg_data.id = id;
	arg_data.narg = narg;
	if (narg == 1) arg_data.arg = arg1->nd_lit;
	result = NEW_LIT(rb_resque(call_lit, &arg_data, except_lit, Qnil));
	freenode(recv);
	if (narg == 1) freenode(arg1);
	return result;
    }
}

static NODE*
asignable(id, val)
    ID id;
    NODE *val;
{
    NODE *lhs;

    if (id == SELF) {
	lhs = Qnil;
	Error("Can't change the value of self");
    }
    else if (id == NIL) {
	lhs = Qnil;
	Error("Can't asign to nil");
    }
    else if (is_local_id(id)) {
	lhs = NEW_LASGN(id, val);
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
    NODE *args;

    value_expr(recv);
    return NEW_CALL(recv, ASET, list_append(idx, val));
}

static NODE *
attrset(recv, id, val)
    NODE *recv, *val;
    ID id;
{
    value_expr(recv);

    id &= ~ID_SCOPE_MASK;
    id |= ID_ATTRSET;

    return NEW_CALL(recv, id, NEW_ARRAY(val));
}

static void
value_expr(node)
    NODE *node;
{
    switch (node->type) {
      case NODE_RETURN:
      case NODE_CONTINUE:
      case NODE_BREAK:
      case NODE_REDO:
      case NODE_RETRY:
	Error("void value expression");
	break;

      case NODE_BLOCK:
	if (node->nd_last)
	    return value_expr(node->nd_last->nd_head);
	break;

      default:
	break;
    }
}

static NODE*
cond(node)
    NODE *node;
{
    value_expr(node);
    if (node->type == NODE_STR) {
	return call_op(NEW_GVAR(rb_intern("$_")),MATCH,1,node);
    }
    else if (node->type == NODE_LIT && TYPE(node->nd_lit) == T_REGEXP) {
	return call_op(node,MATCH,1,NEW_GVAR(rb_intern("$_")));
    }
    return node;
}

static NODE*
cond2(node)
    NODE *node;
{
    node = cond(node);
    if (node->type == NODE_LIT) {
	if (FIXNUM_P(node->nd_lit)) {
	    return call_op(node,EQ,1,NEW_GVAR(rb_intern("$.")));
	}
    }
    return node;
}

st_table *new_idhash();

static struct local_vars {
    ID *tbl;
    int cnt;
    struct local_vars *next;
} *lvtbl;

static void
push_local()
{
    struct local_vars *local;

    local = ALLOC(struct local_vars);
    local->next = lvtbl;
    local->cnt = 0;
    local->tbl = Qnil;
    lvtbl = local;
}

void
pop_local()
{
    struct local_vars *local = lvtbl;

    lvtbl = local->next;
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

    for (cnt=0, max=lvtbl->cnt; cnt<max ;cnt++) {
	if (lvtbl->tbl[cnt+1] == id) return cnt;
    }

    if (lvtbl->tbl == Qnil)
	lvtbl->tbl = ALLOC_N(ID, 2);
    else
	REALLOC_N(lvtbl->tbl, ID, lvtbl->cnt+2);

    lvtbl->tbl[lvtbl->cnt+1] = id;
    return lvtbl->cnt++;
}

static int
local_id(id)
    ID id;
{
    int i, max;

    if (lvtbl == Qnil) return FALSE;
    for (i=1, max=lvtbl->cnt+1; i<max; i++) {
	if (lvtbl->tbl[i] == id) return TRUE;
    }
    return FALSE;
}

static void
init_top_local()
{
    if (lvtbl == Qnil) {
	push_local();
    }
    else if (the_env->local_tbl) {
	lvtbl->cnt = the_env->local_tbl[0];
    }
    else {
	lvtbl->cnt = 0;
    }
    lvtbl->tbl = the_env->local_tbl;
}

static void
setup_top_local()
{
    if (lvtbl->cnt > 0) {
	if (the_env->local_vars == Qnil) {
	    the_env->local_vars = ALLOC_N(VALUE, lvtbl->cnt);
	    bzero(the_env->local_vars, lvtbl->cnt * sizeof(VALUE));
	}
	else {
	    int i;

	    REALLOC_N(the_env->local_vars, VALUE, lvtbl->cnt);
	    for (i=lvtbl->tbl[0]; i<lvtbl->cnt; i++) {
		the_env->local_vars[i] = Qnil;
	    }
	}
	lvtbl->tbl[0] = lvtbl->cnt;
	the_env->local_tbl = lvtbl->tbl;
    }
    else {
	the_env->local_vars = Qnil;
    }
}

void
yyappend_print()
{
    eval_tree =
	block_append(eval_tree, NEW_CALL(Qnil, rb_intern("print"),
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
				  rb_intern("chop"), Qnil), eval_tree);
    }
    eval_tree = NEW_WHILE(NEW_CALL(0,rb_intern("gets"),0),eval_tree);
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
    id <<= 3;
    switch (name[0]) {
      case '$':
	id |= ID_GLOBAL;
	break;
      case '@':
	id |= ID_INSTANCE;
	break;
      case '%':
	if (name[1] != '\0') {
	    id |= ID_CONST;
	    break;
	}
	/* fall through */
      default:
	if (name[0] != '_' && !isalpha(name[0]) && !ismbchar(name[0])) {
	    /* operator */
	    int i;

	    id = Qnil;
	    for (i=0; rb_op_tbl[i].tok; i++) {
		if (strcmp(rb_op_tbl[i].name, name) == 0) {
		    id = rb_op_tbl[i].tok;
		    break;
		}
	    }
	    if (id == Qnil) Bug("Unknown operator `%s'", name);
	    break;
	}
	last = strlen(name)-1;
	if (name[last] == '=') {
	    /* attribute asignment */
	    char *buf = (char*)alloca(last+1);

	    strncpy(buf, name, last);
	    buf[last] = '\0';
	    id = rb_intern(buf);
	    id &= ~ID_SCOPE_MASK;
	    id |= ID_ATTRSET;
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

static
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
    find_ok = Qnil;

    if (id < LAST_TOKEN) {
	int i = 0;

	for (i=0; rb_op_tbl[i].tok; i++) {
	    if (rb_op_tbl[i].tok == id)
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
	    char *buf = (char*)alloca(strlen(res)+2);

	    strcpy(buf, res);
	    strcat(buf, "=");
	    rb_intern(buf);
	    return rb_id2name(id);
	}
    }
    return find_ok;
}

char *
rb_class2name(class)
    struct RClass *class;
{
    extern st_table *rb_class_tbl;

    find_ok = Qnil;

    switch (TYPE(class)) {
      case T_CLASS:
      case T_MODULE:
      case T_ICLASS:
	break;
      default:
	Fail("0x%x is not a class/module", class);
    }

    while (FL_TEST(class, FL_SINGLE)) {
	class = (struct RClass*)class->super;
    }

    st_foreach(rb_class_tbl, id_find, class);
    if (find_ok) {
	return rb_id2name((ID)find_ok);
    }
    Bug("class 0x%x not named", class);
}
