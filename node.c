/**********************************************************************

  node.c - ruby node tree

  $Author: mame $
  created at: 09/12/06 21:23:44 JST

  Copyright (C) 2009 Yusuke Endoh

**********************************************************************/

#include "ruby/ruby.h"
#include "vm_core.h"

#define A(str) rb_str_cat2(buf, (str))
#define AR(str) rb_str_concat(buf, (str))

#define A_INDENT add_indent(buf, indent)
#define D_INDENT rb_str_cat2(indent, next_indent)
#define D_DEDENT rb_str_resize(indent, RSTRING_LEN(indent) - 4)
#define A_ID(id) add_id(buf, (id))
#define A_INT(val) rb_str_catf(buf, "%d", (val))
#define A_LONG(val) rb_str_catf(buf, "%ld", (val))
#define A_LIT(lit) AR(rb_inspect(lit))
#define A_NODE_HEADER(node, term) \
    rb_str_catf(buf, "@ %s (line: %d, location: (%d,%d)-(%d,%d))%s"term, \
		ruby_node_name(nd_type(node)), nd_line(node), \
		nd_first_lineno(node), nd_first_column(node), \
		nd_last_lineno(node), nd_last_column(node), \
		(node->flags & NODE_FL_NEWLINE ? "*" : ""))
#define A_FIELD_HEADER(len, name, term) \
    rb_str_catf(buf, "+- %.*s:"term, (len), (name))
#define D_FIELD_HEADER(len, name, term) (A_INDENT, A_FIELD_HEADER(len, name, term))

#define D_NULL_NODE (A_INDENT, A("(null node)\n"))
#define D_NODE_HEADER(node) (A_INDENT, A_NODE_HEADER(node, "\n"))

#define COMPOUND_FIELD(len, name) \
    FIELD_BLOCK((D_FIELD_HEADER((len), (name), "\n"), D_INDENT), D_DEDENT)

#define COMPOUND_FIELD1(name, ann) \
    COMPOUND_FIELD(FIELD_NAME_LEN(name, ann), \
		   FIELD_NAME_DESC(name, ann))

#define FIELD_NAME_DESC(name, ann) name " (" ann ")"
#define FIELD_NAME_LEN(name, ann) (int)( \
	comment ? \
	rb_strlen_lit(FIELD_NAME_DESC(name, ann)) : \
	rb_strlen_lit(name))
#define SIMPLE_FIELD(len, name) \
    FIELD_BLOCK(D_FIELD_HEADER((len), (name), " "), A("\n"))

#define FIELD_BLOCK(init, reset) \
    for (init, field_flag = 1; \
	 field_flag; /* should be optimized away */ \
	 reset, field_flag = 0)

#define SIMPLE_FIELD1(name, ann)    SIMPLE_FIELD(FIELD_NAME_LEN(name, ann), FIELD_NAME_DESC(name, ann))
#define F_CUSTOM1(name, ann)	    SIMPLE_FIELD1(#name, ann)
#define F_ID(name, ann) 	    SIMPLE_FIELD1(#name, ann) A_ID(node->name)
#define F_GENTRY(name, ann)	    SIMPLE_FIELD1(#name, ann) A_ID((node->name)->id)
#define F_INT(name, ann)	    SIMPLE_FIELD1(#name, ann) A_INT(node->name)
#define F_LONG(name, ann)	    SIMPLE_FIELD1(#name, ann) A_LONG(node->name)
#define F_LIT(name, ann)	    SIMPLE_FIELD1(#name, ann) A_LIT(node->name)
#define F_MSG(name, ann, desc)	    SIMPLE_FIELD1(#name, ann) A(desc)

#define F_NODE(name, ann) \
    COMPOUND_FIELD1(#name, ann) {dump_node(buf, indent, comment, node->name);}

#define ANN(ann) \
    if (comment) { \
	A_INDENT; A("| # " ann "\n"); \
    }

#define LAST_NODE (next_indent = "    ")

static void
add_indent(VALUE buf, VALUE indent)
{
    AR(indent);
}

static void
add_id(VALUE buf, ID id)
{
    if (id == 0) {
	A("(null)");
    }
    else {
	VALUE str = rb_id2str(id);
	if (str) {
	    A(":"); AR(str);
	}
	else {
	    A("(internal variable)");
	}
    }
}

struct add_option_arg {
    VALUE buf, indent;
    st_index_t count;
};

static void dump_node(VALUE, VALUE, int, const NODE *);
static const char default_indent[] = "|   ";

static void
dump_array(VALUE buf, VALUE indent, int comment, const NODE *node)
{
    int field_flag;
    const char *next_indent = default_indent;
    F_LONG(nd_alen, "length");
    F_NODE(nd_head, "element");
    while (node->nd_next && nd_type(node->nd_next) == NODE_ARRAY) {
	node = node->nd_next;
	F_NODE(nd_head, "element");
    }
    LAST_NODE;
    F_NODE(nd_next, "next element");
}

static void
dump_node(VALUE buf, VALUE indent, int comment, const NODE * node)
{
    int field_flag;
    int i;
    const char *next_indent = default_indent;
    enum node_type type;

    if (!node) {
	D_NULL_NODE;
	return;
    }

    D_NODE_HEADER(node);

    type = nd_type(node);
    switch (type) {
      case NODE_BLOCK:
	ANN("statement sequence");
	ANN("format: [nd_head]; ...; [nd_next]");
	ANN("example: foo; bar");
	i = 0;
	do {
	    A_INDENT;
	    rb_str_catf(buf, "+- nd_head (%s%d):\n",
			comment ? "statement #" : "", ++i);
	    if (!node->nd_next) LAST_NODE;
	    D_INDENT;
	    dump_node(buf, indent, comment, node->nd_head);
	    D_DEDENT;
	} while (node->nd_next &&
		 nd_type(node->nd_next) == NODE_BLOCK &&
		 (node = node->nd_next, 1));
	if (node->nd_next) {
	    LAST_NODE;
	    F_NODE(nd_next, "next block");
	}
	return;

      case NODE_IF:
	ANN("if statement");
	ANN("format: if [nd_cond] then [nd_body] else [nd_else] end");
	ANN("example: if x == 1 then foo else bar end");
	F_NODE(nd_cond, "condition expr");
	F_NODE(nd_body, "then clause");
	LAST_NODE;
	F_NODE(nd_else, "else clause");
	return;

      case NODE_UNLESS:
	ANN("unless statement");
	ANN("format: unless [nd_cond] then [nd_body] else [nd_else] end");
	ANN("example: unless x == 1 then foo else bar end");
	F_NODE(nd_cond, "condition expr");
	F_NODE(nd_body, "then clause");
	LAST_NODE;
	F_NODE(nd_else, "else clause");
	return;

      case NODE_CASE:
	ANN("case statement");
	ANN("format: case [nd_head]; [nd_body]; end");
	ANN("example: case x; when 1; foo; when 2; bar; else baz; end");
	F_NODE(nd_head, "case expr");
	LAST_NODE;
	F_NODE(nd_body, "when clauses");
	return;
      case NODE_CASE2:
	ANN("case statement with no head");
	ANN("format: case; [nd_body]; end");
	ANN("example: case; when 1; foo; when 2; bar; else baz; end");
	F_NODE(nd_head, "case expr");
	LAST_NODE;
	F_NODE(nd_body, "when clauses");
	return;

      case NODE_WHEN:
	ANN("when clause");
	ANN("format: when [nd_head]; [nd_body]; (when or else) [nd_next]");
	ANN("example: case x; when 1; foo; when 2; bar; else baz; end");
	F_NODE(nd_head, "when value");
	F_NODE(nd_body, "when body");
	LAST_NODE;
	F_NODE(nd_next, "next when clause");
	return;

      case NODE_WHILE:
	ANN("while statement");
	ANN("format: while [nd_cond]; [nd_body]; end");
	ANN("example: while x == 1; foo; end");
	goto loop;
      case NODE_UNTIL:
	ANN("until statement");
	ANN("format: until [nd_cond]; [nd_body]; end");
	ANN("example: until x == 1; foo; end");
      loop:
	F_CUSTOM1(nd_state, "begin-end-while?") {
	    A_INT((int)node->nd_state);
	    A((node->nd_state == 1) ? " (while-end)" : " (begin-end-while)");
	}
	F_NODE(nd_cond, "condition");
	LAST_NODE;
	F_NODE(nd_body, "body");
	return;

      case NODE_ITER:
	ANN("method call with block");
	ANN("format: [nd_iter] { [nd_body] }");
	ANN("example: 3.times { foo }");
	goto iter;
      case NODE_FOR:
	ANN("for statement");
	ANN("format: for * in [nd_iter] do [nd_body] end");
	ANN("example: for i in 1..3 do foo end");
      iter:
	F_NODE(nd_iter, "iteration receiver");
	LAST_NODE;
	F_NODE(nd_body, "body");
	return;

      case NODE_FOR_MASGN:
	ANN("vars of for statement with masgn");
	ANN("format: for [nd_var] in ... do ... end");
	ANN("example: for x, y in 1..3 do foo end");
	LAST_NODE;
	F_NODE(nd_var, "var");
	return;

      case NODE_BREAK:
	ANN("break statement");
	ANN("format: break [nd_stts]");
	ANN("example: break 1");
	goto jump;
      case NODE_NEXT:
	ANN("next statement");
	ANN("format: next [nd_stts]");
	ANN("example: next 1");
	goto jump;
      case NODE_RETURN:
	ANN("return statement");
	ANN("format: return [nd_stts]");
	ANN("example: return 1");
      jump:
	LAST_NODE;
	F_NODE(nd_stts, "value");
	return;

      case NODE_REDO:
	ANN("redo statement");
	ANN("format: redo");
	ANN("example: redo");
	return;

      case NODE_RETRY:
	ANN("retry statement");
	ANN("format: retry");
	ANN("example: retry");
	return;

      case NODE_BEGIN:
	ANN("begin statement");
	ANN("format: begin; [nd_body]; end");
	ANN("example: begin; 1; end");
	LAST_NODE;
	F_NODE(nd_body, "body");
	return;

      case NODE_RESCUE:
	ANN("rescue clause");
	ANN("format: begin; [nd_body]; (rescue) [nd_resq]; else [nd_else]; end");
	ANN("example: begin; foo; rescue; bar; else; baz; end");
	F_NODE(nd_head, "body");
	F_NODE(nd_resq, "rescue clause list");
	LAST_NODE;
	F_NODE(nd_else, "rescue else clause");
	return;

      case NODE_RESBODY:
	ANN("rescue clause (cont'd)");
	ANN("format: rescue [nd_args]; [nd_body]; (rescue) [nd_head]");
	ANN("example: begin; foo; rescue; bar; else; baz; end");
	F_NODE(nd_args, "rescue exceptions");
	F_NODE(nd_body, "rescue clause");
	LAST_NODE;
	F_NODE(nd_head, "next rescue clause");
	return;

      case NODE_ENSURE:
	ANN("ensure clause");
	ANN("format: begin; [nd_head]; ensure; [nd_ensr]; end");
	ANN("example: begin; foo; ensure; bar; end");
	F_NODE(nd_head, "body");
	LAST_NODE;
	F_NODE(nd_ensr, "ensure clause");
	return;

      case NODE_AND:
	ANN("&& operator");
	ANN("format: [nd_1st] && [nd_2nd]");
	ANN("example: foo && bar");
	goto andor;
      case NODE_OR:
	ANN("|| operator");
	ANN("format: [nd_1st] || [nd_2nd]");
	ANN("example: foo || bar");
      andor:
	while (1) {
	    F_NODE(nd_1st, "left expr");
	    if (!node->nd_2nd || nd_type(node->nd_2nd) != (int)type)
		break;
	    node = node->nd_2nd;
	}
	LAST_NODE;
	F_NODE(nd_2nd, "right expr");
	return;

      case NODE_MASGN:
	ANN("multiple assignment");
	ANN("format: [nd_head], [nd_args] = [nd_value]");
	ANN("example: a, b = foo");
	F_NODE(nd_value, "rhsn");
	F_NODE(nd_head, "lhsn");
	if (NODE_NAMED_REST_P(node->nd_args)) {
	    LAST_NODE;
	    F_NODE(nd_args, "splatn");
	}
	else {
	    F_MSG(nd_args, "splatn", "NODE_SPECIAL_NO_NAME_REST (rest argument without name)");
	}
	return;

      case NODE_LASGN:
	ANN("local variable assignment");
	ANN("format: [nd_vid](lvar) = [nd_value]");
	ANN("example: x = foo");
	F_ID(nd_vid, "local variable");
	if (NODE_REQUIRED_KEYWORD_P(node)) {
	    F_MSG(nd_value, "rvalue", "NODE_SPECIAL_REQUIRED_KEYWORD (required keyword argument)");
	}
	else {
	    LAST_NODE;
	    F_NODE(nd_value, "rvalue");
	}
	return;
      case NODE_DASGN:
	ANN("dynamic variable assignment (out of current scope)");
	ANN("format: [nd_vid](dvar) = [nd_value]");
	ANN("example: x = nil; 1.times { x = foo }");
	F_ID(nd_vid, "local variable");
	LAST_NODE;
	F_NODE(nd_value, "rvalue");
	return;
      case NODE_DASGN_CURR:
	ANN("dynamic variable assignment (in current scope)");
	ANN("format: [nd_vid](current dvar) = [nd_value]");
	ANN("example: 1.times { x = foo }");
	F_ID(nd_vid, "local variable");
	if (NODE_REQUIRED_KEYWORD_P(node)) {
	    F_MSG(nd_value, "rvalue", "NODE_SPECIAL_REQUIRED_KEYWORD (required keyword argument)");
	}
	else {
	    LAST_NODE;
	    F_NODE(nd_value, "rvalue");
	}
	return;
      case NODE_IASGN:
	ANN("instance variable assignment");
	ANN("format: [nd_vid](ivar) = [nd_value]");
	ANN("example: @x = foo");
	F_ID(nd_vid, "instance variable");
	LAST_NODE;
	F_NODE(nd_value, "rvalue");
	return;
      case NODE_CVASGN:
	ANN("class variable assignment");
	ANN("format: [nd_vid](cvar) = [nd_value]");
	ANN("example: @@x = foo");
	F_ID(nd_vid, "class variable");
	LAST_NODE;
	F_NODE(nd_value, "rvalue");
	return;
      case NODE_GASGN:
	ANN("global variable assignment");
	ANN("format: [nd_entry](gvar) = [nd_value]");
	ANN("example: $x = foo");
	F_GENTRY(nd_entry, "global variable");
	LAST_NODE;
	F_NODE(nd_value, "rvalue");
	return;

      case NODE_CDECL:
	ANN("constant declaration");
	ANN("format: [nd_else]::[nd_vid](constant) = [nd_value]");
	ANN("example: X = foo");
	if (node->nd_vid) {
	    F_ID(nd_vid, "constant");
	    F_MSG(nd_else, "extension", "not used");
	}
	else {
	    F_MSG(nd_vid, "constant", "0 (see extension field)");
	    F_NODE(nd_else, "extension");
	}
	LAST_NODE;
	F_NODE(nd_value, "rvalue");
	return;

      case NODE_OP_ASGN1:
	ANN("array assignment with operator");
	ANN("format: [nd_recv] [ [nd_args->nd_head] ] [nd_mid]= [nd_args->nd_body]");
	ANN("example: ary[1] += foo");
	F_NODE(nd_recv, "receiver");
	F_ID(nd_mid, "operator");
	F_NODE(nd_args->nd_head, "index");
	LAST_NODE;
	F_NODE(nd_args->nd_body, "rvalue");
	return;

      case NODE_OP_ASGN2:
	ANN("attr assignment with operator");
	ANN("format: [nd_recv].[attr] [nd_next->nd_mid]= [nd_value]");
	ANN("          where [attr]: [nd_next->nd_vid]");
	ANN("example: struct.field += foo");
	F_NODE(nd_recv, "receiver");
	F_CUSTOM1(nd_next->nd_vid, "attr") {
	    if (node->nd_next->nd_aid) A("? ");
	    A_ID(node->nd_next->nd_vid);
	}
	F_ID(nd_next->nd_mid, "operator");
	LAST_NODE;
	F_NODE(nd_value, "rvalue");
	return;

      case NODE_OP_ASGN_AND:
	ANN("assignment with && operator");
	ANN("format: [nd_head] &&= [nd_value]");
	ANN("example: foo &&= bar");
	goto asgn_andor;
      case NODE_OP_ASGN_OR:
	ANN("assignment with || operator");
	ANN("format: [nd_head] ||= [nd_value]");
	ANN("example: foo ||= bar");
      asgn_andor:
	F_NODE(nd_head, "variable");
	LAST_NODE;
	F_NODE(nd_value, "rvalue");
	return;

      case NODE_OP_CDECL:
	ANN("constant declaration with operator");
	ANN("format: [nd_head](constant) [nd_aid]= [nd_value]");
	ANN("example: A::B ||= 1");
	F_NODE(nd_head, "constant");
	F_ID(nd_aid, "operator");
	LAST_NODE;
	F_NODE(nd_value, "rvalue");
	return;

      case NODE_CALL:
	ANN("method invocation");
	ANN("format: [nd_recv].[nd_mid]([nd_args])");
	ANN("example: obj.foo(1)");
	F_ID(nd_mid, "method id");
	F_NODE(nd_recv, "receiver");
	LAST_NODE;
	F_NODE(nd_args, "arguments");
	return;

      case NODE_OPCALL:
        ANN("method invocation");
        ANN("format: [nd_recv] [nd_mid] [nd_args]");
        ANN("example: foo + bar");
        F_ID(nd_mid, "method id");
        F_NODE(nd_recv, "receiver");
        LAST_NODE;
        F_NODE(nd_args, "arguments");
        return;

      case NODE_FCALL:
	ANN("function call");
	ANN("format: [nd_mid]([nd_args])");
	ANN("example: foo(1)");
	F_ID(nd_mid, "method id");
	LAST_NODE;
	F_NODE(nd_args, "arguments");
	return;

      case NODE_VCALL:
	ANN("function call with no argument");
	ANN("format: [nd_mid]");
	ANN("example: foo");
	F_ID(nd_mid, "method id");
	return;

      case NODE_QCALL:
	ANN("safe method invocation");
	ANN("format: [nd_recv]&.[nd_mid]([nd_args])");
	ANN("example: obj&.foo(1)");
	F_ID(nd_mid, "method id");
	F_NODE(nd_recv, "receiver");
	LAST_NODE;
	F_NODE(nd_args, "arguments");
	return;

      case NODE_SUPER:
	ANN("super invocation");
	ANN("format: super [nd_args]");
	ANN("example: super 1");
	LAST_NODE;
	F_NODE(nd_args, "arguments");
	return;

      case NODE_ZSUPER:
	ANN("super invocation with no argument");
	ANN("format: super");
	ANN("example: super");
	return;

      case NODE_ARRAY:
	ANN("array constructor");
	ANN("format: [ [nd_head], [nd_next].. ] (length: [nd_alen])");
	ANN("example: [1, 2, 3]");
	goto ary;
      case NODE_VALUES:
	ANN("return arguments");
	ANN("format: [ [nd_head], [nd_next].. ] (length: [nd_alen])");
	ANN("example: return 1, 2, 3");
      ary:
	dump_array(buf, indent, comment, node);
	return;

      case NODE_ZARRAY:
	ANN("empty array constructor");
	ANN("format: []");
	ANN("example: []");
	return;

      case NODE_HASH:
	if (!node->nd_alen) {
	    ANN("keyword arguments");
	    ANN("format: nd_head");
	    ANN("example: a: 1, b: 2");
	}
	else {
	    ANN("hash constructor");
	    ANN("format: { [nd_head] }");
	    ANN("example: { 1 => 2, 3 => 4 }");
	}
	F_CUSTOM1(nd_alen, "keyword arguments or hash literal") {
	    switch (node->nd_alen) {
	      case 0: A("0 (keyword argument)"); break;
	      case 1: A("1 (hash literal)"); break;
	    }
	}
	LAST_NODE;
	F_NODE(nd_head, "contents");
	return;

      case NODE_YIELD:
	ANN("yield invocation");
	ANN("format: yield [nd_head]");
	ANN("example: yield 1");
	LAST_NODE;
	F_NODE(nd_head, "arguments");
	return;

      case NODE_LVAR:
	ANN("local variable reference");
	ANN("format: [nd_vid](lvar)");
	ANN("example: x");
	F_ID(nd_vid, "local variable");
	return;
      case NODE_DVAR:
	ANN("dynamic variable reference");
	ANN("format: [nd_vid](dvar)");
	ANN("example: 1.times { x = 1; x }");
	F_ID(nd_vid, "local variable");
	return;
      case NODE_IVAR:
	ANN("instance variable reference");
	ANN("format: [nd_vid](ivar)");
	ANN("example: @x");
	F_ID(nd_vid, "instance variable");
	return;
      case NODE_CONST:
	ANN("constant reference");
	ANN("format: [nd_vid](constant)");
	ANN("example: X");
	F_ID(nd_vid, "constant");
	return;
      case NODE_CVAR:
	ANN("class variable reference");
	ANN("format: [nd_vid](cvar)");
	ANN("example: @@x");
	F_ID(nd_vid, "class variable");
	return;

      case NODE_GVAR:
	ANN("global variable reference");
	ANN("format: [nd_entry](gvar)");
	ANN("example: $x");
	F_GENTRY(nd_entry, "global variable");
	return;

      case NODE_NTH_REF:
	ANN("nth special variable reference");
	ANN("format: $[nd_nth]");
	ANN("example: $1, $2, ..");
	F_CUSTOM1(nd_nth, "variable") { A("$"); A_LONG(node->nd_nth); }
	return;

      case NODE_BACK_REF:
	ANN("back special variable reference");
	ANN("format: $[nd_nth]");
	ANN("example: $&, $`, $', $+");
	F_CUSTOM1(nd_nth, "variable") {
	    char name[3];
	    name[0] = '$';
	    name[1] = (char)node->nd_nth;
	    name[2] = '\0';
	    A(name);
	}
	return;

      case NODE_MATCH:
	ANN("match expression (against $_ implicitly)");
        ANN("format: [nd_lit] (in condition)");
	ANN("example: if /foo/; foo; end");
	F_LIT(nd_lit, "regexp");
	return;

      case NODE_MATCH2:
	ANN("match expression (regexp first)");
        ANN("format: [nd_recv] =~ [nd_value]");
	ANN("example: /foo/ =~ 'foo'");
	F_NODE(nd_recv, "regexp (receiver)");
	if (!node->nd_args) LAST_NODE;
	F_NODE(nd_value, "string (argument)");
	if (node->nd_args) {
	    LAST_NODE;
	    F_NODE(nd_args, "named captures");
	}
	return;

      case NODE_MATCH3:
	ANN("match expression (regexp second)");
        ANN("format: [nd_recv] =~ [nd_value]");
	ANN("example: 'foo' =~ /foo/");
	F_NODE(nd_recv, "string (receiver)");
	LAST_NODE;
	F_NODE(nd_value, "regexp (argument)");
	return;

      case NODE_LIT:
	ANN("literal");
	ANN("format: [nd_lit]");
	ANN("example: 1, /foo/");
	goto lit;
      case NODE_STR:
	ANN("string literal");
	ANN("format: [nd_lit]");
	ANN("example: 'foo'");
	goto lit;
      case NODE_XSTR:
	ANN("xstring literal");
	ANN("format: [nd_lit]");
	ANN("example: `foo`");
      lit:
	F_LIT(nd_lit, "literal");
	return;

      case NODE_ONCE:
	ANN("once evaluation");
	ANN("format: [nd_body]");
	ANN("example: /foo#{ bar }baz/o");
	LAST_NODE;
	F_NODE(nd_body, "body");
	return;
      case NODE_DSTR:
	ANN("string literal with interpolation");
	ANN("format: [nd_lit]");
	ANN("example: \"foo#{ bar }baz\"");
	goto dlit;
      case NODE_DXSTR:
	ANN("xstring literal with interpolation");
	ANN("format: [nd_lit]");
	ANN("example: `foo#{ bar }baz`");
	goto dlit;
      case NODE_DREGX:
	ANN("regexp literal with interpolation");
	ANN("format: [nd_lit]");
	ANN("example: /foo#{ bar }baz/");
	goto dlit;
      case NODE_DSYM:
	ANN("symbol literal with interpolation");
	ANN("format: [nd_lit]");
	ANN("example: :\"foo#{ bar }baz\"");
      dlit:
	F_LIT(nd_lit, "preceding string");
	F_NODE(nd_next->nd_head, "interpolation");
	LAST_NODE;
	F_NODE(nd_next->nd_next, "tailing strings");
	return;

      case NODE_EVSTR:
	ANN("interpolation expression");
	ANN("format: \"..#{ [nd_lit] }..\"");
	ANN("example: \"foo#{ bar }baz\"");
	LAST_NODE;
	F_NODE(nd_body, "body");
	return;

      case NODE_ARGSCAT:
	ANN("splat argument following arguments");
	ANN("format: ..(*[nd_head], [nd_body..])");
	ANN("example: foo(*ary, post_arg1, post_arg2)");
	F_NODE(nd_head, "preceding array");
	LAST_NODE;
	F_NODE(nd_body, "following array");
	return;

      case NODE_ARGSPUSH:
	ANN("splat argument following one argument");
	ANN("format: ..(*[nd_head], [nd_body])");
	ANN("example: foo(*ary, post_arg)");
	F_NODE(nd_head, "preceding array");
	LAST_NODE;
	F_NODE(nd_body, "following element");
	return;

      case NODE_SPLAT:
	ANN("splat argument");
	ANN("format: *[nd_head]");
	ANN("example: foo(*ary)");
	LAST_NODE;
	F_NODE(nd_head, "splat'ed array");
	return;

      case NODE_BLOCK_PASS:
	ANN("arguments with block argument");
	ANN("format: ..([nd_head], &[nd_body])");
	ANN("example: foo(x, &blk)");
	F_NODE(nd_head, "other arguments");
	LAST_NODE;
	F_NODE(nd_body, "block argument");
	return;

      case NODE_DEFN:
	ANN("method definition");
	ANN("format: def [nd_mid] [nd_defn]; end");
	ANN("example: def foo; bar; end");
	F_ID(nd_mid, "method name");
	LAST_NODE;
	F_NODE(nd_defn, "method definition");
	return;

      case NODE_DEFS:
	ANN("singleton method definition");
	ANN("format: def [nd_recv].[nd_mid] [nd_defn]; end");
	ANN("example: def obj.foo; bar; end");
	F_NODE(nd_recv, "receiver");
	F_ID(nd_mid, "method name");
	LAST_NODE;
	F_NODE(nd_defn, "method definition");
	return;

      case NODE_ALIAS:
	ANN("method alias statement");
	ANN("format: alias [nd_1st] [nd_2nd]");
	ANN("example: alias bar foo");
	F_NODE(nd_1st, "new name");
	LAST_NODE;
	F_NODE(nd_2nd, "old name");
	return;

      case NODE_VALIAS:
	ANN("global variable alias statement");
	ANN("format: alias [nd_alias](gvar) [nd_orig](gvar)");
	ANN("example: alias $y $x");
	F_ID(nd_alias, "new name");
	F_ID(nd_orig, "old name");
	return;

      case NODE_UNDEF:
	ANN("method undef statement");
	ANN("format: undef [nd_undef]");
	ANN("example: undef foo");
	LAST_NODE;
	F_NODE(nd_undef, "old name");
	return;

      case NODE_CLASS:
	ANN("class definition");
	ANN("format: class [nd_cpath] < [nd_super]; [nd_body]; end");
	ANN("example: class C2 < C; ..; end");
	F_NODE(nd_cpath, "class path");
	F_NODE(nd_super, "superclass");
	LAST_NODE;
	F_NODE(nd_body, "class definition");
	return;

      case NODE_MODULE:
	ANN("module definition");
	ANN("format: module [nd_cpath]; [nd_body]; end");
	ANN("example: module M; ..; end");
	F_NODE(nd_cpath, "module path");
	LAST_NODE;
	F_NODE(nd_body, "module definition");
	return;

      case NODE_SCLASS:
	ANN("singleton class definition");
	ANN("format: class << [nd_recv]; [nd_body]; end");
	ANN("example: class << obj; ..; end");
	F_NODE(nd_recv, "receiver");
	LAST_NODE;
	F_NODE(nd_body, "singleton class definition");
	return;

      case NODE_COLON2:
	ANN("scoped constant reference");
	ANN("format: [nd_head]::[nd_mid]");
	ANN("example: M::C");
	F_ID(nd_mid, "constant name");
	LAST_NODE;
	F_NODE(nd_head, "receiver");
	return;

      case NODE_COLON3:
	ANN("top-level constant reference");
	ANN("format: ::[nd_mid]");
	ANN("example: ::Object");
	F_ID(nd_mid, "constant name");
	return;

      case NODE_DOT2:
	ANN("range constructor (incl.)");
	ANN("format: [nd_beg]..[nd_end]");
	ANN("example: 1..5");
	goto dot;
      case NODE_DOT3:
	ANN("range constructor (excl.)");
	ANN("format: [nd_beg]...[nd_end]");
	ANN("example: 1...5");
	goto dot;
      case NODE_FLIP2:
	ANN("flip-flop condition (incl.)");
	ANN("format: [nd_beg]..[nd_end]");
	ANN("example: if (x==1)..(x==5); foo; end");
	goto dot;
      case NODE_FLIP3:
	ANN("flip-flop condition (excl.)");
	ANN("format: [nd_beg]...[nd_end]");
	ANN("example: if (x==1)...(x==5); foo; end");
      dot:
	F_NODE(nd_beg, "begin");
	LAST_NODE;
	F_NODE(nd_end, "end");
	return;

      case NODE_SELF:
	ANN("self");
	ANN("format: self");
	ANN("example: self");
	return;

      case NODE_NIL:
	ANN("nil");
	ANN("format: nil");
	ANN("example: nil");
	return;

      case NODE_TRUE:
	ANN("true");
	ANN("format: true");
	ANN("example: true");
	return;

      case NODE_FALSE:
	ANN("false");
	ANN("format: false");
	ANN("example: false");
	return;

      case NODE_ERRINFO:
	ANN("virtual reference to $!");
	ANN("format: rescue => id");
	ANN("example: rescue => id");
	return;

      case NODE_DEFINED:
	ANN("defined? expression");
	ANN("format: defined?([nd_head])");
	ANN("example: defined?(foo)");
	F_NODE(nd_head, "expr");
	return;

      case NODE_POSTEXE:
	ANN("post-execution");
	ANN("format: END { [nd_body] }");
	ANN("example: END { foo }");
	LAST_NODE;
	F_NODE(nd_body, "END clause");
	return;

      case NODE_ATTRASGN:
	ANN("attr assignment");
	ANN("format: [nd_recv].[nd_mid] = [nd_args]");
	ANN("example: struct.field = foo");
	F_NODE(nd_recv, "receiver");
	F_ID(nd_mid, "method name");
	LAST_NODE;
	F_NODE(nd_args, "arguments");
	return;

      case NODE_LAMBDA:
	ANN("lambda expression");
	ANN("format: -> [nd_body]");
	ANN("example: -> { foo }");
	LAST_NODE;
	F_NODE(nd_body, "lambda clause");
	return;

      case NODE_OPT_ARG:
	ANN("optional arguments");
	ANN("format: def method_name([nd_body=some], [nd_next..])");
	ANN("example: def foo(a, b=1, c); end");
	F_NODE(nd_body, "body");
	LAST_NODE;
	F_NODE(nd_next, "next");
	return;

      case NODE_KW_ARG:
	ANN("keyword arguments");
	ANN("format: def method_name([nd_body=some], [nd_next..])");
	ANN("example: def foo(a:1, b:2); end");
	F_NODE(nd_body, "body");
	LAST_NODE;
	F_NODE(nd_next, "next");
	return;

      case NODE_POSTARG:
	ANN("post arguments");
	ANN("format: *[nd_1st], [nd_2nd..] = ..");
	ANN("example: a, *rest, z = foo");
	if (NODE_NAMED_REST_P(node->nd_1st)) {
	    F_NODE(nd_1st, "rest argument");
	}
	else {
	    F_MSG(nd_1st, "rest argument", "NODE_SPECIAL_NO_NAME_REST (rest argument without name)");
	}
	LAST_NODE;
	F_NODE(nd_2nd, "post arguments");
	return;

      case NODE_ARGS:
	ANN("method parameters");
	ANN("format: def method_name(.., [nd_opt=some], *[nd_rest], [nd_pid], .., &[nd_body])");
	ANN("example: def foo(a, b, opt1=1, opt2=2, *rest, y, z, &blk); end");
	F_INT(nd_ainfo->pre_args_num, "count of mandatory (pre-)arguments");
	F_NODE(nd_ainfo->pre_init, "initialization of (pre-)arguments");
	F_INT(nd_ainfo->post_args_num, "count of mandatory post-arguments");
	F_NODE(nd_ainfo->post_init, "initialization of post-arguments");
	F_ID(nd_ainfo->first_post_arg, "first post argument");
	F_ID(nd_ainfo->rest_arg, "rest argument");
	F_ID(nd_ainfo->block_arg, "block argument");
	F_NODE(nd_ainfo->opt_args, "optional arguments");
	F_NODE(nd_ainfo->kw_args, "keyword arguments");
	LAST_NODE;
	F_NODE(nd_ainfo->kw_rest_arg, "keyword rest argument");
	return;

      case NODE_SCOPE:
	ANN("new scope");
	ANN("format: [nd_tbl]: local table, [nd_args]: arguments, [nd_body]: body");
	F_CUSTOM1(nd_tbl, "local table") {
	    ID *tbl = node->nd_tbl;
	    int i;
	    int size = tbl ? (int)*tbl++ : 0;
	    if (size == 0) A("(empty)");
	    for (i = 0; i < size; i++) {
		A_ID(tbl[i]); if (i < size - 1) A(",");
	    }
	}
	F_NODE(nd_args, "arguments");
	LAST_NODE;
	F_NODE(nd_body, "body");
	return;

      case NODE_ARGS_AUX:
      case NODE_LAST:
	break;
    }

    rb_bug("dump_node: unknown node: %s", ruby_node_name(nd_type(node)));
}

VALUE
rb_parser_dump_tree(const NODE *node, int comment)
{
    VALUE buf = rb_str_new_cstr(
	"###########################################################\n"
	"## Do NOT use this node dump for any purpose other than  ##\n"
	"## debug and research.  Compatibility is not guaranteed. ##\n"
	"###########################################################\n\n"
    );
    dump_node(buf, rb_str_new_cstr("# "), comment, node);
    return buf;
}

/* Setup NODE structure.
 * NODE is not an object managed by GC, but it imitates an object
 * so that it can work with `RB_TYPE_P(obj, T_NODE)`.
 * This dirty hack is needed because Ripper jumbles NODEs and other type
 * objects.
 */
void
rb_node_init(NODE *n, enum node_type type, VALUE a0, VALUE a1, VALUE a2)
{
    n->flags = T_NODE;
    nd_set_type(n, type);
    n->u1.value = a0;
    n->u2.value = a1;
    n->u3.value = a2;
    n->nd_loc.beg_pos.lineno = 0;
    n->nd_loc.beg_pos.column = 0;
    n->nd_loc.end_pos.lineno = 0;
    n->nd_loc.end_pos.column = 0;
}

typedef struct node_buffer_elem_struct {
    struct node_buffer_elem_struct *next;
    NODE buf[FLEX_ARY_LEN];
} node_buffer_elem_t;

struct node_buffer_struct {
    long idx, len;
    node_buffer_elem_t *head;
    node_buffer_elem_t *last;
    VALUE mark_ary;
};

static node_buffer_t *
rb_node_buffer_new(void)
{
    node_buffer_t *nb = xmalloc(sizeof(node_buffer_t) + offsetof(node_buffer_elem_t, buf) + 16 * sizeof(NODE));
    nb->idx = 0;
    nb->len = 16;
    nb->head = nb->last = (node_buffer_elem_t*) &nb[1];
    nb->head->next = NULL;
    nb->mark_ary = rb_ary_tmp_new(0);
    return nb;
}

static void
rb_node_buffer_free(node_buffer_t *nb)
{
    node_buffer_elem_t *nbe = nb->head;

    while (nbe != nb->last) {
	void *buf = nbe;
	nbe = nbe->next;
	xfree(buf);
    }
    xfree(nb);
}

NODE *
rb_ast_newnode(rb_ast_t *ast)
{
    node_buffer_t *nb = ast->node_buffer;
    if (nb->idx >= nb->len) {
	long n = nb->len * 2;
	node_buffer_elem_t *nbe;
	nbe = xmalloc(offsetof(node_buffer_elem_t, buf) + n * sizeof(NODE));
	nb->idx = 0;
	nb->len = n;
	nbe->next = nb->head;
	nb->head = nbe;
    }
    return &nb->head->buf[nb->idx++];
}

void
rb_ast_delete_node(rb_ast_t *ast, NODE *n)
{
    (void)ast;
    (void)n;
    /* should we implement freelist? */
}

rb_ast_t *
rb_ast_new(void)
{
    node_buffer_t *nb = rb_node_buffer_new();
    VALUE mark_ary = nb->mark_ary;
    rb_ast_t *ast = (rb_ast_t *)rb_imemo_new(imemo_ast, 0, 0, 0, (VALUE)nb);
    RB_OBJ_WRITTEN(ast, Qnil, mark_ary);
    return ast;
}

void
rb_ast_mark(rb_ast_t *ast)
{
    if (ast->node_buffer) rb_gc_mark(ast->node_buffer->mark_ary);
}

void
rb_ast_free(rb_ast_t *ast)
{
    if (ast->node_buffer) {
	rb_node_buffer_free(ast->node_buffer);
	ast->node_buffer = 0;
    }
}

void
rb_ast_dispose(rb_ast_t *ast)
{
    rb_ast_free(ast);
}

void
rb_ast_add_mark_object(rb_ast_t *ast, VALUE obj)
{
    rb_ary_push(ast->node_buffer->mark_ary, obj);
}
