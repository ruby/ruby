/************************************************

  parse.y -

  $Author: matz $
  $Date: 1994/12/19 08:30:08 $
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

%{

#define YYDEBUG 1
#include "ruby.h"
#include "env.h"
#include "node.h"
#include "st.h"
#include <stdio.h>

#include "ident.h"
#define is_id_nonop(id) ((id)>LAST_TOKEN)
#define is_local_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_LOCAL)
#define is_global_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_GLOBAL)
#define is_instance_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_INSTANCE)
#define is_variable_id(id) (is_id_nonop(id)&&((id)&ID_VARMASK))
#define is_attrset_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_ATTRSET)
#define is_const_id(id) (is_id_nonop(id)&&((id)&ID_SCOPE_MASK)==ID_CONST)

struct op_tbl {
    ID token;
    char *name;
};

NODE *eval_tree = Qnil;

char *sourcefile;		/* current source file */
int   sourceline;		/* current line no. */

static int yylex();

static enum lex_state {
    EXPR_BEG,			/* ignore newline, +/- is a sign. */
    EXPR_MID,			/* newline significant, +/- is a sign. */
    EXPR_END,			/* newline significant, +/- is a operator. */
    EXPR_FNAME,			/* ignore newline, +/- is a operator. */
} lex_state;

static ID cur_class = Qnil, cur_mid = Qnil;
static int in_module, in_single;

static void value_expr();
static NODE *cond();
static NODE *cond2();

static NODE *block_append();
static NODE *list_append();
static NODE *list_concat();
static NODE *list_copy();
static NODE *expand_op();
static NODE *call_op();

static NODE *gettable();
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
    NODE *node;
    VALUE val;
    ID id;
    int num;
}

%token  CLASS
	MODULE
	DEF
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
	PROTECT
	RESQUE
	ENSURE
	END
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
	_FILE_
	_LINE_
	IF_MOD
	UNLESS_MOD
	WHILE_MOD
	UNTIL_MOD

%token <id>   IDENTIFIER GVAR IVAR CONSTANT
%token <val>  INTEGER FLOAT STRING XSTRING REGEXP GLOB
%token <node> STRING2 XSTRING2 DREGEXP DGLOB

%type <node> singleton inc_list
%type <val>  literal numeric
%type <node> compstmts stmts stmt stmt0 expr expr0 var_ref
%type <node> if_tail opt_else cases resque ensure
%type <node> call_args call_args0 opt_args args args2
%type <node> f_arglist f_args assoc_list assocs assoc
%type <node> mlhs mlhs_head mlhs_tail lhs iter_var opt_iter_var
%type <id>   superclass variable symbol
%type <id>   fname op rest_arg
%type <num>  f_arg 
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
%token <id> OP_ASGN     /* +=, -=  etc. */
%token ASSOC            /* => */
%token LPAREN LBRACK LBRACE

/*
 *	precedence table
 */

%left  YIELD RETURN FAIL
%right '=' OP_ASGN
%right COLON2
%nonassoc DOT2 DOT3
%left  OR
%left  AND
%nonassoc  CMP EQ NEQ MATCH NMATCH
%left  '>' GEQ '<' LEQ
%left  '|' '^'
%left  '&'
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
		  compstmts
		    {
			eval_tree = block_append(eval_tree, $2);
                        setup_top_local();
		    }

compstmts	: stmts opt_term

stmts		: /* none */
		    {
			$$ = Qnil;
		    }
		| stmt
		| stmts term stmt
		    {
			$$ = block_append($1, $3);
		    }
		| stmts error
		    {
			lex_state = EXPR_BEG;
		    }
		  stmt
		    {
			yyerrok;
			$$ = block_append($1, $4);
		    }

stmt		: CLASS IDENTIFIER superclass
		    {
			if (cur_class || cur_mid || in_single)
			    Error("nested class definition");
			cur_class = $2;
			push_local();
		    }
		  compstmts
		  END
		    {
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
		  compstmts
		  END
		    {
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
		  f_arglist
		  compstmts
		  END
		    {
			$$ = NEW_DEFN($2, NEW_RFUNC($4, $5), cur_class?0:1);
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
		  compstmts
		  END
		    {
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
		| stmt0 IF_MOD stmt0
		    {
			$$ = NEW_IF(cond($3), $1, Qnil);
		    }
		| stmt0 UNLESS_MOD stmt0
		    {
			$$ = NEW_UNLESS(cond($3), $1, Qnil);
		    }
		| stmt0 WHILE_MOD stmt0
		    {
			$$ = NEW_WHILE2(cond($3), $1);
		    }
		| stmt0 UNTIL_MOD stmt0
		    {
			$$ = NEW_UNTIL2(cond($3), $1);
		    }
		| stmt0

stmt0		: mlhs '=' args2
		    {
			$1->nd_value = $3;
			$$ = $1;
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
		| RETURN args2
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
		| IDENTIFIER call_args0
		    {
			$$ = NEW_CALL(Qnil, $1, $2);
		    }
		| expr0 '.' IDENTIFIER call_args0
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $4);
		    }
		| SUPER call_args0
		    {
			if (!cur_mid && !in_single)
			    Error("super called outside of method");
			$$ = NEW_SUPER($2);
		    }
		| expr

mlhs		: mlhs_head
		    {
			$$ = NEW_MASGN(NEW_LIST($1),Qnil);
		    }
		| mlhs_head '*' lhs
		    {
			$$ = NEW_MASGN(NEW_LIST($1),$3);
		    }
		| mlhs_head mlhs_tail
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2),Qnil);
		    }
		| mlhs_head mlhs_tail comma '*' lhs
		    {
			$$ = NEW_MASGN(list_concat(NEW_LIST($1),$2),$5);
		    }

mlhs_head	: variable comma
		    {
			$$ = asignable($1, Qnil);
		    }
		| expr0 '[' args rbracket comma
		    {
			$$ = aryset($1, $3, Qnil);
		    }
		| expr0 '.' IDENTIFIER comma
		    {
			$$ = attrset($1, $3, Qnil);
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
		| expr0 '[' args rbracket
		    {
			$$ = aryset($1, $3, Qnil);
		    }
		| expr0 '.' IDENTIFIER 
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
			lex_state = EXPR_BEG;
			$$ = Qnil;
		    }
		| inc_list comma error
		    {
			lex_state = EXPR_BEG;
			$$ = $1;
		    }

fname		: IDENTIFIER
		| op
		    {
			lex_state = EXPR_END;
			$$ = $1;
		    }

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
		| UPLUS		{ $$ = UMINUS; }
		| UMINUS	{ $$ = UPLUS; }
		| AREF		{ $$ = AREF; }
		| ASET		{ $$ = ASET; }

f_arglist	: '(' f_args rparen
		    {
			$$ = $2;
		    }
		| term
		    {
			$$ = NEW_ARGS(0, -1);
		    }

f_args		: /* no arg */
		    {
			$$ = NEW_ARGS(0, -1);
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
			lex_state = EXPR_BEG;
			$$ = NEW_ARGS($1, -1);
		    }
		| error
		    {
			lex_state = EXPR_BEG;
			$$ = NEW_ARGS(0, -1);
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

rest_arg	: '*' IDENTIFIER
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
		| LPAREN compstmts rparen
		    {
			switch (nd_type($2)) {
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

expr		: variable '=' expr
		    {
			value_expr($3);
			$$ = asignable($1, $3);
		    }
		| expr0 '[' args rbracket '=' expr
		    {
			value_expr($6);
			$$ = aryset($1, $3, $6);
		    }
		| expr0 '.' IDENTIFIER '=' expr
		    {
			value_expr($5);
			$$ = attrset($1, $3, $5);
		    }
		| variable OP_ASGN expr
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
		| expr0 '[' args rbracket OP_ASGN expr
		    {
			NODE *rval, *args;
			value_expr($1);
			value_expr($6);

			args = list_copy($3);
			rval = NEW_CALL($1, AREF, args);

			args = list_append($3, call_op(rval, $5, 1, $6));
			$$ = NEW_CALL($1, ASET, args);
		    }
		| expr0 '.' IDENTIFIER OP_ASGN expr
		    {
			ID id = $3;
			NODE *rval;

			value_expr($1);
			value_expr($5);

			id &= ~ID_SCOPE_MASK;
			id |= ID_ATTRSET;

			rval = call_op(NEW_CALL($1, $3, Qnil), $4, 1, $5);
			$$ = NEW_CALL($1, id, NEW_LIST(rval));
		    }
		| expr DOT2 expr
		    {
			$$ = call_op($1, DOT2, 1, $3);
		    }
		| expr DOT3 expr
		    {
			$$ = NEW_DOT3(cond2($1), cond2($3));
		    }
		| expr '+' expr
		    {
			$$ = Qnil;
			if ($1 && $3
			    && (nd_type($3) == NODE_LIT || nd_type($3) == NODE_STR)
			    && nd_type($1) == NODE_CALL && $1->nd_mid == '+') {
			    if ($1->nd_args->nd_head == Qnil)
				Bug("bad operand for `+'");
			    if (nd_type($1->nd_args->nd_head) == NODE_LIT
				|| nd_type($1->nd_args->nd_head) == NODE_STR) {
				$1->nd_args->nd_head =
				    expand_op($1->nd_args->nd_head, '+', $3);
		                    $$ = $1;
			    }
			}
			if ($$ == Qnil) {
			    $$ = call_op($1, '+', 1, $3);
			}
		    }
		| expr '-' expr
		    {
		        $$ = call_op($1, '-', 1, $3);
		    }
		| expr '*' expr
		    {
		        $$ = call_op($1, '*', 1, $3);
		    }
		| expr '/' expr
		    {
			$$ = call_op($1, '/', 1, $3);
		    }
		| expr '%' expr
		    {
			$$ = call_op($1, '%', 1, $3);
		    }
		| expr POW expr
		    {
			$$ = call_op($1, POW, 1, $3);
		    }
		| UPLUS expr
		    {
			$$ = call_op($2, UPLUS, 0);
		    }
		| UMINUS expr
		    {
		        $$ = call_op($2, UMINUS, 0);
		    }
		| expr '|' expr
		    {
		        $$ = call_op($1, '|', 1, $3);
		    }
		| expr '^' expr
		    {
			$$ = call_op($1, '^', 1, $3);
		    }
		| expr '&' expr
		    {
			$$ = call_op($1, '&', 1, $3);
		    }
		| expr CMP expr
		    {
			$$ = call_op($1, CMP, 1, $3);
		    }
		| expr '>' expr
		    {
			$$ = call_op($1, '>', 1, $3);
		    }
		| expr GEQ expr
		    {
			$$ = call_op($1, GEQ, 1, $3);
		    }
		| expr '<' expr
		    {
			$$ = call_op($1, '<', 1, $3);
		    }
		| expr LEQ expr
		    {
			$$ = call_op($1, LEQ, 1, $3);
		    }
		| expr EQ expr
		    {
			$$ = call_op($1, EQ, 1, $3);
		    }
		| expr NEQ expr
		    {
			$$ = call_op($1, NEQ, 1, $3);
		    }
		| expr MATCH expr
		    {
			$$ = call_op($1, MATCH, 1, $3);
		    }
		| expr NMATCH expr
		    {
			$$ = call_op($1, NMATCH, 1, $3);
		    }
		| '!' expr
		    {
			$$ = call_op($2, '!', 0);
		    }
		| '~' expr
		    {
			if ($2
			    && (nd_type($2) == NODE_STR
				|| (nd_type($2) == NODE_LIT
				    && (TYPE($2->nd_lit) == T_REGEXP
					|| TYPE($2->nd_lit) == T_STRING)))) {
			    $$ = NEW_CALL($2, '~', Qnil);
			}
			else {
			    $$ = call_op($2, '~', 0);
			}
		    }
		| expr LSHFT expr
		    {
			$$ = call_op($1, LSHFT, 1, $3);
		    }
		| expr RSHFT expr
		    {
			$$ = call_op($1, RSHFT, 1, $3);
		    }
		| expr COLON2 expr
		    {
			$$ = call_op($1, COLON2, 1, $3);
		    }
		| expr AND expr
		    {
			$$ = NEW_AND(cond($1), cond($3));
		    }
		| expr OR expr
		    {
			$$ = NEW_OR(cond($1), cond($3));
		    }
		|expr0
		    {
			$$ = $1;
		    }

call_args	: /* none */
		    {
			$$ = Qnil;
		    }
		| call_args0
		| '*' expr
		    {
			$$ = $2;
		    }

call_args0	: args
		| args comma '*' expr
		    {
			$$ = call_op($1, '+', 1, $4);
		    }

opt_args	: /* none */
		    {
			$$ = Qnil;
		    }
		| args

args 		: expr
		    {
			value_expr($1);
			$$ = NEW_LIST($1);
		    }
		| args comma expr
		    {
			value_expr($3);
			$$ = list_append($1, $3);
		    }

args2		: args
		    {
			NODE *rhs;

			if ($1 && $1->nd_next == Qnil) {
			    $$ = $1->nd_head;
			}
			else {
			    $$ = $1;
			}
		    }

expr0		: literal
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
		| DGLOB
		| var_ref
		| IDENTIFIER '(' call_args rparen
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

		| expr0 '[' args rbracket
		    {
			value_expr($1);
			$$ = NEW_CALL($1, AREF, $3);
		    }
		| LBRACK opt_args rbracket
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
		| FAIL '(' args2 ')'
		    {
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
		| expr0 lbrace opt_iter_var '|' compstmts rbrace
		    {
			switch (nd_type($1)) {
			  case NODE_CALL:
			    nd_set_type($1, NODE_ICALL);
			    break;
			  case NODE_YIELD:
			    nd_set_type($1, NODE_IYIELD);
			    break;
			  case NODE_BLOCK:
			    {
				NODE *tmp = $1;
				while (tmp) {
				    if (nd_type(tmp->nd_head) == NODE_YIELD) {
					nd_set_type(tmp->nd_head, NODE_IYIELD);
				    }
				    else if (nd_type(tmp->nd_head) == NODE_CALL) {
					nd_set_type(tmp->nd_head, NODE_ICALL);
				    }
				    tmp = tmp->nd_next;
				}
			    }
			    break;
			}
			$$ = NEW_ITER($3, $1, $5);
		    }
		| expr0 '.' IDENTIFIER '(' call_args rparen
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, $5);
		    }
		| expr0 '.' IDENTIFIER
		    {
			value_expr($1);
			$$ = NEW_CALL($1, $3, Qnil);
		    }
		| IF stmt0 then
		  compstmts
		  if_tail
		  END
		    {
			$$ = NEW_IF(cond($2), $4, $5);
		    }
		| UNLESS stmt0 then 
		  compstmts opt_else END
		    {
		        $$ = NEW_UNLESS(cond($2), $4, $5);
		    }
		| WHILE stmt0 term compstmts END
		    {
			$$ = NEW_WHILE(cond($2), $4);
		    }
		| UNTIL stmt0 term compstmts END
		    {
			$$ = NEW_UNTIL(cond($2), $4);
		    }
		| CASE stmt0 opt_term
		  cases
		  END
		    {
			value_expr($2);
			$$ = NEW_CASE($2, $4);
		    }
		| FOR iter_var IN stmt0 term
		  compstmts
		  END
		    {
			value_expr($4);
			$$ = NEW_FOR($2, $4, $6);
		    }
		| PROTECT
		  compstmts
		  resque
		  ensure
		  END
		    {
			if ($3 == Qnil && $4 == Qnil) {
			    Warning("useless protect clause");
			    $$ = $2;
			}
			else {
			    $$ = NEW_PROT($2, $3, $4);
			}
		    }
		| LPAREN compstmts rparen
		    {
			$$ = $2;
		    }

then		: term
		| THEN
		| term THEN

if_tail		: opt_else
		| ELSIF stmt0 then
		  compstmts
		  if_tail
		    {
			$$ = NEW_IF(cond($2), $4, $5);
		    }

opt_else	: /* none */
		    {
			$$ = Qnil;
		    }
		| ELSE compstmts
		    {
			$$ = $2;
		    }

iter_var	: lhs
		| mlhs

opt_iter_var	: /* none */
		    {
			$$ = Qnil;
		    }
		| iter_var

cases		: opt_else
		| WHEN args then
		  compstmts
		  cases
		    {
			$$ = NEW_WHEN($2, $4, $5);
		    }

resque		: /* none */
		    {
			$$ = Qnil;
		    }
		| RESQUE compstmts
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
		| ENSURE compstmts
		    {
			$$ = $2;
		    }

literal		: numeric
		| '\\' symbol
		    {
			$$ = INT2FIX($2);
		    }
		| REGEXP
		| GLOB


symbol		: fname
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
			$$ = gettable($1);
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

assoc		: expr ASSOC expr
		    {
			$$ = NEW_LIST($1);
			$$ = list_append($$, $3);
		    }


opt_term	: /* none */
		| term

term		: sc
		| nl

sc		: ';'		{ yyerrok; }
nl		: '\n'		{ yyerrok; }

rparen		: ')' 		{ yyerrok; }
rbracket	: ']'		{ yyerrok; }
lbrace		: '{'
rbrace		: '}'		{ yyerrok; }
comma		: ',' 		{ yyerrok; }
%%

#include <ctype.h>
#include <sys/types.h>
#include "regex.h"

#define is_identchar(c) ((c)!=-1&&(isalnum(c) || (c) == '_' || ismbchar(c)))

static char *tokenbuf = NULL;
static int   tokidx, toksiz = 0;

VALUE newregexp();
VALUE newstring();
VALUE newfloat();
VALUE newinteger();
char *strdup();

#define EXPAND_B 1
#define LEAVE_BS 2

static NODE *var_extend();
static void read_escape();

static char *lex_p;
static int lex_len;

void
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

static int
parse_regx()
{
    register int c;
    int in_brack = 0;
    int re_start = sourceline;
    NODE *list = Qnil;

    newtok();
    while (c = nextc()) {
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
	    else if (isdigit(c)) {
		tokadd('\\');
		tokadd(c);
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
	    lex_state = EXPR_END;
	    if (list) {
		if (toklen() > 0) {
		    VALUE ss = str_new(tok(), toklen());
		    list_append(list, NEW_STR(ss));
		}
		nd_set_type(list, NODE_DREGX);
		yylval.node = list;
		return DREGEXP;
	    }
	    else {
		yylval.val = regexp_new(tok(), toklen());
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
}

static int
parse_string(term)
    int term;
{
    int c;
    NODE *list = Qnil;
    ID id;
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
		int flags = EXPAND_B;
		if (term != '"') flags |= LEAVE_BS;
		pushback();
		read_escape(flags);
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
    "break",	BREAK,		EXPR_END,
    "case",	CASE,		EXPR_BEG,
    "class",	CLASS,		EXPR_BEG,
    "continue", CONTINUE,	EXPR_END,
    "def",	DEF,		EXPR_FNAME,
    "else",	ELSE,		EXPR_BEG,
    "elsif",	ELSIF,		EXPR_BEG,
    "end",	END,		EXPR_END,
    "ensure",	ENSURE,		EXPR_BEG,
    "fail", 	FAIL,		EXPR_END,
    "for", 	FOR,		EXPR_BEG,
    "if",	IF,		EXPR_BEG,
    "in",	IN,		EXPR_BEG,
    "include",	INCLUDE,	EXPR_BEG,
    "module",	MODULE,		EXPR_BEG,
    "nil",	NIL,		EXPR_END,
    "protect",	PROTECT,	EXPR_BEG,
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
    "when",	WHEN,		EXPR_BEG,
    "while",	WHILE,		EXPR_BEG,
    "yield",	YIELD,		EXPR_END,
};

static int
yylex()
{
    register int c;
    struct kwtable *low = kwtable, *mid, *high = LAST(kwtable);
    int last;

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
	goto retry;

      case '#':		/* it's a comment */
	while ((c = nextc()) != '\n') {
	    if (c == -1)
		return 0;
	}
	/* fall through */
      case '\n':
	sourceline++;
	if (lex_state == EXPR_BEG || lex_state == EXPR_FNAME)
	    goto retry;
	lex_state = EXPR_BEG;
	return '\n';

      case '*':
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '*') {
	    if (nextc() == '=') {
		yylval.id = POW;
		return OP_ASGN;
	    }
	    pushback();
	    return POW;
	}
	else if (c == '=') {
	    yylval.id = '*';
	    return OP_ASGN;
	}
	pushback();
	return '*';

      case '!':
	if (lex_state == EXPR_FNAME) {
	    if ((c = nextc()) == '@') {
		lex_state = EXPR_BEG;
		return '!';
	    }
	    pushback();
	}
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
	if (lex_state == EXPR_BEG) {
	    if (parse_string('>') == STRING) {
		yylval.val = glob_new(yylval.val);
		return GLOB;
	    }
	    nd_set_type(yylval.node, NODE_DGLOB);
	    return DGLOB;
	}
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
	    return OP_ASGN;
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
	    return OP_ASGN;
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
	    lex_state = EXPR_BEG;
	    return UPLUS;
	}
	else if (lex_state == EXPR_FNAME) {
	    if ((c = nextc()) == '@') {
		return UPLUS;
	    }
	    pushback();
	    return '+';
	}
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
	    yylval.id = '+';
	    return OP_ASGN;
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
	    lex_state = EXPR_BEG;
	    return UMINUS;
	}
	else if (lex_state == EXPR_FNAME) {
	    if ((c = nextc()) == '@') {
		return UMINUS;
	    }
	    pushback();
	    return '-';
	}
	lex_state = EXPR_BEG;
	if ((c = nextc()) == '=') {
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
	lex_state = EXPR_BEG;
	if (nextc() == ':') {
	    return COLON2;
	}
	pushback();
	return ':';

      case '/':
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID) {
	    return parse_regx();
	}
	lex_state = EXPR_BEG;
	if (nextc() == '=') {
	    yylval.id = '/';
	    return OP_ASGN;
	}
	pushback();
	return c;

      case '^':
	lex_state = EXPR_BEG;
	if (nextc() == '=') {
	    yylval.id = '^';
	    return OP_ASGN;
	}
	pushback();
	return c;

      case ',':
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
	if (lex_state != EXPR_END)
	    c = LPAREN;
	lex_state = EXPR_BEG;
	return c;

      case '[':
	
	if (lex_state == EXPR_BEG || lex_state == EXPR_MID)
	    c = LBRACK;
	else if (lex_state == EXPR_FNAME) {
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
	lex_state = EXPR_BEG;
	return c;

      case '{':
	if (lex_state != EXPR_END)
	    c = LBRACE;
	lex_state = EXPR_BEG;
	return c;

      case '\\':
	c = nextc();
	if (c == '\n') goto retry; /* skip \\n */
	lex_state = EXPR_FNAME;
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
		return OP_ASGN;
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
	  case '`':		/* $&: string before last match */
	  case '\'':		/* $&: string after last match */
	  case '+':		/* $&: string matches last paren. */
	  case '~':		/* $~: match-data */
	  case '=':		/* $=: ignorecase */
	  case ':':		/* $:: load path */
	  case '<':		/* $<: reading filename */
	  case '>':		/* $>: default output handle */
	  case '"':		/* $": already loaded files */
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
	    enum lex_state state = lex_state;
	    lex_state = mid->state;
	    if (state != EXPR_BEG) {
		if (mid->id == IF) return IF_MOD;
		if (mid->id == UNLESS) return UNLESS_MOD;
		if (mid->id == WHILE) return WHILE_MOD;
		if (mid->id == UNTIL) return UNTIL_MOD;
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
    {
	enum lex_state state = lex_state;

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
	    if (state == EXPR_FNAME) {
		if ((c = nextc()) == '=') {
		    yylval.id &= ~ID_SCOPE_MASK;
		    yylval.id |= ID_ATTRSET;
		}
		else {
		    pushback();
		}
	    }
	    return IDENTIFIER;
	}
    }
}

static NODE*
var_extend(list, term)
    NODE *list;
    char term;
{
    int c, t;
    VALUE ss;
    ID id;

    c = nextc();
    switch (c) {
      default:
	tokadd('#');
	pushback();
	return list;
      case '@': case '%':
	t = nextc();
	pushback();
	if (!is_identchar(t)) {
	    tokadd('#');
	    tokadd(c);
	    return list;
	}
      case '$':
      case '{':
	break;
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
	while ((c = nextc()) != '}') {
	    if (c == -1) {
		return (NODE*)-1;
	    }
	    if (isspace(c)) {
		Error("Invalid variable name in string");
		break;
	    }
	    if (c == term) {
		Error("Inmature variable name in string");
		pushback();
		return list;
	    }
	    tokadd(c);
	}
    }
    else {
	switch (c) {
	  case '$':
	    tokadd(c);
	    c = nextc();
	    if (c == -1) return (NODE*)-1;
	    if (!is_identchar(c)) {
		tokadd(c);
		goto fetch_id;
	    }
	    /* through */
	  case '@': case '%':
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
	pushback();
    }
  fetch_id:
    tokfix();
    if (strcmp("__LINE__", tok()) == 0)
	id = _LINE_;
    else if (strcmp("__FILE__", tok()) == 0)
	id = _FILE_;
    else
	id = rb_intern(tok());
    list_append(list, gettable(id));
    newtok();
    return list;
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

      case 'a':	/* alarm(bell) */
	tokadd('\1');
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
		else if ((int)strchr("abcdefABCDEF", (c = nextc()))) {
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
      case '#':
	tokadd(c);
	break;
    }
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

    if (nd_type(head) != NODE_ARRAY || nd_type(tail) != NODE_ARRAY)
	Bug("list_concat() called with non-list");

    last = head;
    while (last->nd_next) {
	last = last->nd_next;
    }

    last->nd_next = tail;
    head->nd_alen += tail->nd_alen;

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
expand_op(recv, id, arg)
    NODE *recv, *arg;
    ID id;
{
    struct call_arg arg_data;
    VALUE val;
    NODE *result;

    arg_data.recv = recv->nd_lit;
    arg_data.id = id;
    arg_data.narg = arg?1:0;
    arg_data.arg = arg->nd_lit;

    val = rb_resque(call_lit, &arg_data, except_lit, Qnil);
    if (TYPE(val) == T_STRING) {
	result = NEW_STR(val);
    }
    else {
	result = NEW_LIT(val);
    }

    return result;
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

    if ((nd_type(recv) == NODE_LIT || nd_type(recv) == NODE_STR)
	&& (narg == 0 || (nd_type(arg1) == NODE_LIT || nd_type(arg1) == NODE_STR))) {
	return expand_op(recv, id, (narg == 1)?arg1:Qnil);
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
	if (local_id(id))
	    return NEW_LVAR(id);
	else
	    return NEW_MVAR(id);
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
    else if (id == _LINE_ || id == _FILE_) {
	Error("Can't asign to special identifier");
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
    if (node == Qnil) return;

    switch (nd_type(node)) {
      case NODE_RETURN:
      case NODE_CONTINUE:
      case NODE_BREAK:
      case NODE_REDO:
      case NODE_RETRY:
      case NODE_WHILE:
      case NODE_WHILE2:
      case NODE_INC:
      case NODE_CLASS:
      case NODE_MODULE:
	Error("void value expression");
	break;

      case NODE_BLOCK:
	while (node->nd_next) {
	    node = node->nd_next;
	}
	if (node) {
	    value_expr(node->nd_head);
	}
	break;

      default:
	break;
    }
}

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
    return node;
}

static NODE*
cond(node)
    NODE *node;
{
    enum node_type type = nd_type(node);

    value_expr(node);

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
    struct local_vars *prev;
} *lvtbl;

static void
push_local()
{
    struct local_vars *local;

    local = ALLOC(struct local_vars);
    local->prev = lvtbl;
    local->cnt = 0;
    local->tbl = Qnil;
    lvtbl = local;
}

static void
pop_local()
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
    else if (the_scope->local_tbl) {
	lvtbl->cnt = the_scope->local_tbl[0];
    }
    else {
	lvtbl->cnt = 0;
    }
    lvtbl->tbl = the_scope->local_tbl;
}

static void
setup_top_local()
{
    if (lvtbl->cnt > 0) {
	if (the_scope->local_vars == Qnil) {
	    the_scope->var_ary = ary_new2(lvtbl->cnt);
	    the_scope->local_vars = RARRAY(the_scope->var_ary)->ptr;
	    memset(the_scope->local_vars, 0, lvtbl->cnt * sizeof(VALUE));
	    RARRAY(the_scope->var_ary)->len = lvtbl->cnt;
	}
	else if (lvtbl->tbl[0] < lvtbl->cnt) {
	    int i, len;

	    if (the_scope->var_ary) {
		for (i=0, len=lvtbl->cnt-lvtbl->tbl[0];i<len;i++) {
		    ary_push(the_scope->var_ary, Qnil);
		}
	    }
	    else {
		VALUE *vars = the_scope->local_vars;

		the_scope->var_ary = ary_new2(lvtbl->cnt);
		the_scope->local_vars = RARRAY(the_scope->var_ary)->ptr;
		memcpy(the_scope->local_vars, vars, sizeof(VALUE)*lvtbl->cnt);
		memset(the_scope->local_vars+i, 0, lvtbl->cnt-i);
		RARRAY(the_scope->var_ary)->len = lvtbl->cnt;
	    }
	}
	lvtbl->tbl[0] = lvtbl->cnt;
	the_scope->local_tbl = lvtbl->tbl;
    }
    else {
	the_scope->local_vars = Qnil;
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
	    for (i=0; rb_op_tbl[i].token; i++) {
		if (strcmp(rb_op_tbl[i].name, name) == 0) {
		    id = rb_op_tbl[i].token;
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
      case T_ICLASS:
        class = (struct RClass*)RBASIC(class)->class;
	break;
      case T_CLASS:
      case T_MODULE:
	break;
      default:
	Fail("0x%x is not a class/module", class);
    }

    if (FL_TEST(class, FL_SINGLE)) {
	class = (struct RClass*)class->super;
    }

    while (TYPE(class) == T_ICLASS) {
        class = (struct RClass*)class->super;
    }

    st_foreach(rb_class_tbl, id_find, class);
    if (find_ok) {
	return rb_id2name((ID)find_ok);
    }
    Bug("class 0x%x not named", class);
}

