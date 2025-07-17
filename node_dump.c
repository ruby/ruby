/**********************************************************************

  node_dump.c - dump ruby node tree

  $Author: mame $
  created at: 09/12/06 21:23:44 JST

  Copyright (C) 2009 Yusuke Endoh

**********************************************************************/

#include "internal.h"
#include "internal/class.h"
#include "internal/hash.h"
#include "internal/ruby_parser.h"
#include "internal/variable.h"
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
#define A_LIT(lit) AR(rb_dump_literal(lit))
#define A_LOC(loc) \
    rb_str_catf(buf, "(%d,%d)-(%d,%d)", \
                loc.beg_pos.lineno, loc.beg_pos.column, \
                loc.end_pos.lineno, loc.end_pos.column)
#define A_NODE_HEADER(node, term) \
    rb_str_catf(buf, "@ %s (id: %d, line: %d, location: (%d,%d)-(%d,%d))%s"term, \
                ruby_node_name(nd_type(node)), nd_node_id(node), nd_line(node), \
                nd_first_lineno(node), nd_first_column(node), \
                nd_last_lineno(node), nd_last_column(node), \
                (nd_fl_newline(node) ? "*" : ""))
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

#define A_SHAREABILITY(shareability) \
    switch (shareability) { \
      case rb_parser_shareable_none: \
        rb_str_cat_cstr(buf, "none"); \
        break; \
      case rb_parser_shareable_literal: \
        rb_str_cat_cstr(buf, "literal"); \
        break; \
      case rb_parser_shareable_copy: \
        rb_str_cat_cstr(buf, "experimental_copy"); \
        break; \
      case rb_parser_shareable_everything: \
        rb_str_cat_cstr(buf, "experimental_everything"); \
        break; \
    }

#define SIMPLE_FIELD1(name, ann)    SIMPLE_FIELD(FIELD_NAME_LEN(name, ann), FIELD_NAME_DESC(name, ann))
#define F_CUSTOM1(name, ann)	    SIMPLE_FIELD1(#name, ann)
#define F_ID(name, type, ann) 	    SIMPLE_FIELD1(#name, ann) A_ID(type(node)->name)
#define F_INT(name, type, ann)	    SIMPLE_FIELD1(#name, ann) A_INT(type(node)->name)
#define F_LONG(name, type, ann)	    SIMPLE_FIELD1(#name, ann) A_LONG(type(node)->name)
#define F_LIT(name, type, ann)	    SIMPLE_FIELD1(#name, ann) A_LIT(type(node)->name)
#define F_VALUE(name, val, ann)     SIMPLE_FIELD1(#name, ann) A_LIT(val)
#define F_MSG(name, ann, desc)	    SIMPLE_FIELD1(#name, ann) A(desc)
#define F_LOC(name, type)           SIMPLE_FIELD1(#name, "")  A_LOC(type(node)->name)
#define F_SHAREABILITY(name, type, ann) SIMPLE_FIELD1(#name, ann) A_SHAREABILITY(type(node)->name)

#define F_NODE(name, type, ann) \
    COMPOUND_FIELD1(#name, ann) {dump_node(buf, indent, comment, RNODE(type(node)->name));}

#define F_NODE2(name, n, ann) \
    COMPOUND_FIELD1(#name, ann) {dump_node(buf, indent, comment, n);}

#define F_ARRAY(name, type, ann) \
    COMPOUND_FIELD1(#name, ann) {dump_parser_array(buf, indent, comment, type(node)->name);}

#define ANN(ann) \
    if (comment) { \
        A_INDENT; A("| # " ann "\n"); \
    }

#define LAST_NODE (next_indent = "    ")

VALUE
rb_dump_literal(VALUE lit)
{
    if (!RB_SPECIAL_CONST_P(lit)) {
        VALUE str;
        switch (RB_BUILTIN_TYPE(lit)) {
          case T_CLASS: case T_MODULE: case T_ICLASS:
            str = rb_class_path(lit);
            if (RCLASS_SINGLETON_P(lit)) {
                str = rb_sprintf("<%"PRIsVALUE">", str);
            }
            return str;
          default:
            break;
        }
    }
    return rb_inspect(lit);
}

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
            rb_str_catf(buf, "(internal variable: 0x%"PRIsVALUE")", id);
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
    F_LONG(as.nd_alen, RNODE_LIST, "length");
    F_NODE(nd_head, RNODE_LIST, "element");
    while (RNODE_LIST(node)->nd_next && nd_type_p(RNODE_LIST(node)->nd_next, NODE_LIST)) {
        node = RNODE_LIST(node)->nd_next;
        F_NODE(nd_head, RNODE_LIST, "element");
    }
    LAST_NODE;
    F_NODE(nd_next, RNODE_LIST, "next element");
}

static void
dump_parser_array(VALUE buf, VALUE indent, int comment, const rb_parser_ary_t *ary)
{
    int field_flag;
    const char *next_indent = default_indent;

    if (ary->data_type != PARSER_ARY_DATA_NODE) {
        rb_bug("unexpected rb_parser_ary_data_type: %d", ary->data_type);
    }

    F_CUSTOM1(length, "length") { A_LONG(ary->len); }
    for (long i = 0; i < ary->len; i++) {
        if (i == ary->len - 1) LAST_NODE;
        A_INDENT;
        rb_str_catf(buf, "+- element (%s%ld):\n",
                    comment ? "statement #" : "", i);
        D_INDENT;
        dump_node(buf, indent, comment, ary->data[i]);
        D_DEDENT;
    }
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
            if (!RNODE_BLOCK(node)->nd_next) LAST_NODE;
            D_INDENT;
            dump_node(buf, indent, comment, RNODE_BLOCK(node)->nd_head);
            D_DEDENT;
        } while (RNODE_BLOCK(node)->nd_next &&
                 nd_type_p(RNODE_BLOCK(node)->nd_next, NODE_BLOCK) &&
                 (node = RNODE_BLOCK(node)->nd_next, 1));
        if (RNODE_BLOCK(node)->nd_next) {
            LAST_NODE;
            F_NODE(nd_next, RNODE_BLOCK, "next block");
        }
        return;

      case NODE_IF:
        ANN("if statement");
        ANN("format: if [nd_cond] then [nd_body] else [nd_else] end");
        ANN("example: if x == 1 then foo else bar end");
        F_NODE(nd_cond, RNODE_IF, "condition expr");
        F_NODE(nd_body, RNODE_IF, "then clause");
        F_NODE(nd_else, RNODE_IF, "else clause");
        F_LOC(if_keyword_loc, RNODE_IF);
        F_LOC(then_keyword_loc, RNODE_IF);
        LAST_NODE;
        F_LOC(end_keyword_loc, RNODE_IF);
        return;

      case NODE_UNLESS:
        ANN("unless statement");
        ANN("format: unless [nd_cond] then [nd_body] else [nd_else] end");
        ANN("example: unless x == 1 then foo else bar end");
        F_NODE(nd_cond, RNODE_UNLESS, "condition expr");
        F_NODE(nd_body, RNODE_UNLESS, "then clause");
        F_NODE(nd_else, RNODE_UNLESS, "else clause");
        F_LOC(keyword_loc, RNODE_UNLESS);
        F_LOC(then_keyword_loc, RNODE_UNLESS);
        LAST_NODE;
        F_LOC(end_keyword_loc, RNODE_UNLESS);
        return;

      case NODE_CASE:
        ANN("case statement");
        ANN("format: case [nd_head]; [nd_body]; end");
        ANN("example: case x; when 1; foo; when 2; bar; else baz; end");
        F_NODE(nd_head, RNODE_CASE, "case expr");
        F_NODE(nd_body, RNODE_CASE, "when clauses");
        F_LOC(case_keyword_loc, RNODE_CASE);
        LAST_NODE;
        F_LOC(end_keyword_loc, RNODE_CASE);
        return;
      case NODE_CASE2:
        ANN("case statement with no head");
        ANN("format: case; [nd_body]; end");
        ANN("example: case; when 1; foo; when 2; bar; else baz; end");
        F_NODE(nd_head, RNODE_CASE2, "case expr");
        F_NODE(nd_body, RNODE_CASE2, "when clauses");
        F_LOC(case_keyword_loc, RNODE_CASE2);
        LAST_NODE;
        F_LOC(end_keyword_loc, RNODE_CASE2);
        return;
      case NODE_CASE3:
        ANN("case statement (pattern matching)");
        ANN("format: case [nd_head]; [nd_body]; end");
        ANN("example: case x; in 1; foo; in 2; bar; else baz; end");
        F_NODE(nd_head, RNODE_CASE3, "case expr");
        F_NODE(nd_body, RNODE_CASE3, "in clauses");
        F_LOC(case_keyword_loc, RNODE_CASE3);
        LAST_NODE;
        F_LOC(end_keyword_loc, RNODE_CASE3);
        return;

      case NODE_WHEN:
        ANN("when clause");
        ANN("format: when [nd_head]; [nd_body]; (when or else) [nd_next]");
        ANN("example: case x; when 1; foo; when 2; bar; else baz; end");
        F_NODE(nd_head, RNODE_WHEN, "when value");
        F_NODE(nd_body, RNODE_WHEN, "when body");
        LAST_NODE;
        F_NODE(nd_next, RNODE_WHEN, "next when clause");
        F_LOC(keyword_loc, RNODE_WHEN);
        LAST_NODE;
        F_LOC(then_keyword_loc, RNODE_WHEN);
        return;

      case NODE_IN:
        ANN("in clause");
        ANN("format: in [nd_head]; [nd_body]; (in or else) [nd_next]");
        ANN("example: case x; in 1; foo; in 2; bar; else baz; end");
        F_NODE(nd_head, RNODE_IN, "in pattern");
        F_NODE(nd_body, RNODE_IN, "in body");
        LAST_NODE;
        F_NODE(nd_next, RNODE_IN, "next in clause");
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
            A_INT((int)RNODE_WHILE(node)->nd_state);
            A((RNODE_WHILE(node)->nd_state == 1) ? " (while-end)" : " (begin-end-while)");
        }
        F_NODE(nd_cond, RNODE_WHILE, "condition");
        F_NODE(nd_body, RNODE_WHILE, "body");
        F_LOC(keyword_loc, RNODE_WHILE);
        LAST_NODE;
        F_LOC(closing_loc, RNODE_WHILE);
        return;

      case NODE_ITER:
        ANN("method call with block");
        ANN("format: [nd_iter] { [nd_body] }");
        ANN("example: 3.times { foo }");
        F_NODE(nd_iter, RNODE_ITER, "iteration receiver");
        LAST_NODE;
        F_NODE(nd_body, RNODE_ITER, "body");
        return;

      case NODE_FOR:
        ANN("for statement");
        ANN("format: for * in [nd_iter] do [nd_body] end");
        ANN("example: for i in 1..3 do foo end");
        F_NODE(nd_iter, RNODE_FOR, "iteration receiver");
        F_NODE(nd_body, RNODE_FOR, "body");
        F_LOC(for_keyword_loc, RNODE_FOR);
        F_LOC(in_keyword_loc, RNODE_FOR);
        F_LOC(do_keyword_loc, RNODE_FOR);
        LAST_NODE;
        F_LOC(end_keyword_loc, RNODE_FOR);
        return;

      case NODE_FOR_MASGN:
        ANN("vars of for statement with masgn");
        ANN("format: for [nd_var] in ... do ... end");
        ANN("example: for x, y in 1..3 do foo end");
        LAST_NODE;
        F_NODE(nd_var, RNODE_FOR_MASGN, "var");
        return;

      case NODE_BREAK:
        ANN("break statement");
        ANN("format: break [nd_stts]");
        ANN("example: break 1");
        F_NODE(nd_stts, RNODE_BREAK, "value");
        LAST_NODE;
        F_LOC(keyword_loc, RNODE_BREAK);
        return;
      case NODE_NEXT:
        ANN("next statement");
        ANN("format: next [nd_stts]");
        ANN("example: next 1");
        F_NODE(nd_stts, RNODE_NEXT, "value");
        LAST_NODE;
        F_LOC(keyword_loc, RNODE_NEXT);
        return;
      case NODE_RETURN:
        ANN("return statement");
        ANN("format: return [nd_stts]");
        ANN("example: return 1");
        F_NODE(nd_stts, RNODE_RETURN, "value");
        LAST_NODE;
        F_LOC(keyword_loc, RNODE_RETURN);
        return;

      case NODE_REDO:
        ANN("redo statement");
        ANN("format: redo");
        ANN("example: redo");
        F_LOC(keyword_loc, RNODE_REDO);
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
        F_NODE(nd_body, RNODE_BEGIN, "body");
        return;

      case NODE_RESCUE:
        ANN("rescue clause");
        ANN("format: begin; [nd_body]; (rescue) [nd_resq]; else [nd_else]; end");
        ANN("example: begin; foo; rescue; bar; else; baz; end");
        F_NODE(nd_head, RNODE_RESCUE, "body");
        F_NODE(nd_resq, RNODE_RESCUE, "rescue clause list");
        LAST_NODE;
        F_NODE(nd_else, RNODE_RESCUE, "rescue else clause");
        return;

      case NODE_RESBODY:
        ANN("rescue clause (cont'd)");
        ANN("format: rescue [nd_args] (=> [nd_exc_var]); [nd_body]; (rescue) [nd_next]");
        ANN("example: begin; foo; rescue; bar; else; baz; end");
        F_NODE(nd_args, RNODE_RESBODY, "rescue exceptions");
        F_NODE(nd_exc_var, RNODE_RESBODY, "exception variable");
        F_NODE(nd_body, RNODE_RESBODY, "rescue clause");
        LAST_NODE;
        F_NODE(nd_next, RNODE_RESBODY, "next rescue clause");
        return;

      case NODE_ENSURE:
        ANN("ensure clause");
        ANN("format: begin; [nd_head]; ensure; [nd_ensr]; end");
        ANN("example: begin; foo; ensure; bar; end");
        F_NODE(nd_head, RNODE_ENSURE, "body");
        LAST_NODE;
        F_NODE(nd_ensr, RNODE_ENSURE, "ensure clause");
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
            F_NODE(nd_1st, RNODE_AND, "left expr");
            if (!RNODE_AND(node)->nd_2nd || !nd_type_p(RNODE_AND(node)->nd_2nd, type))
                break;
            node = RNODE_AND(node)->nd_2nd;
        }
        F_NODE(nd_2nd, RNODE_AND, "right expr");
        LAST_NODE;
        F_LOC(operator_loc, RNODE_AND);
        return;

      case NODE_MASGN:
        ANN("multiple assignment");
        ANN("format: [nd_head], [nd_args] = [nd_value]");
        ANN("example: a, b = foo");
        F_NODE(nd_value, RNODE_MASGN, "rhsn");
        F_NODE(nd_head, RNODE_MASGN, "lhsn");
        if (NODE_NAMED_REST_P(RNODE_MASGN(node)->nd_args)) {
            LAST_NODE;
            F_NODE(nd_args, RNODE_MASGN, "splatn");
        }
        else {
            F_MSG(nd_args, "splatn", "NODE_SPECIAL_NO_NAME_REST (rest argument without name)");
        }
        return;

      case NODE_LASGN:
        ANN("local variable assignment");
        ANN("format: [nd_vid](lvar) = [nd_value]");
        ANN("example: x = foo");
        F_ID(nd_vid, RNODE_LASGN, "local variable");
        if (NODE_REQUIRED_KEYWORD_P(RNODE_LASGN(node)->nd_value)) {
            F_MSG(nd_value, "rvalue", "NODE_SPECIAL_REQUIRED_KEYWORD (required keyword argument)");
        }
        else {
            LAST_NODE;
            F_NODE(nd_value, RNODE_LASGN, "rvalue");
        }
        return;
      case NODE_DASGN:
        ANN("dynamic variable assignment");
        ANN("format: [nd_vid](dvar) = [nd_value]");
        ANN("example: x = nil; 1.times { x = foo }");
        ANN("example: 1.times { x = foo }");
        F_ID(nd_vid, RNODE_DASGN, "local variable");
        if (NODE_REQUIRED_KEYWORD_P(RNODE_DASGN(node)->nd_value)) {
            F_MSG(nd_value, "rvalue", "NODE_SPECIAL_REQUIRED_KEYWORD (required keyword argument)");
        }
        else {
            LAST_NODE;
            F_NODE(nd_value, RNODE_DASGN, "rvalue");
        }
        return;
      case NODE_IASGN:
        ANN("instance variable assignment");
        ANN("format: [nd_vid](ivar) = [nd_value]");
        ANN("example: @x = foo");
        F_ID(nd_vid, RNODE_IASGN, "instance variable");
        LAST_NODE;
        F_NODE(nd_value, RNODE_IASGN, "rvalue");
        return;
      case NODE_CVASGN:
        ANN("class variable assignment");
        ANN("format: [nd_vid](cvar) = [nd_value]");
        ANN("example: @@x = foo");
        F_ID(nd_vid, RNODE_CVASGN, "class variable");
        LAST_NODE;
        F_NODE(nd_value, RNODE_CVASGN, "rvalue");
        return;
      case NODE_GASGN:
        ANN("global variable assignment");
        ANN("format: [nd_vid](gvar) = [nd_value]");
        ANN("example: $x = foo");
        F_ID(nd_vid, RNODE_GASGN, "global variable");
        LAST_NODE;
        F_NODE(nd_value, RNODE_GASGN, "rvalue");
        return;

      case NODE_CDECL:
        ANN("constant declaration");
        ANN("format: [nd_else]::[nd_vid](constant) = [nd_value]");
        ANN("example: X = foo");
        if (RNODE_CDECL(node)->nd_vid) {
            F_ID(nd_vid, RNODE_CDECL, "constant");
            F_MSG(nd_else, "extension", "not used");
        }
        else {
            F_MSG(nd_vid, "constant", "0 (see extension field)");
            F_NODE(nd_else, RNODE_CDECL, "extension");
        }
        F_SHAREABILITY(shareability, RNODE_CDECL, "shareability");
        LAST_NODE;
        F_NODE(nd_value, RNODE_CDECL, "rvalue");
        return;

      case NODE_OP_ASGN1:
        ANN("array assignment with operator");
        ANN("format: [nd_recv] [ [nd_index] ] [nd_mid]= [nd_rvalue]");
        ANN("example: ary[1] += foo");
        F_NODE(nd_recv, RNODE_OP_ASGN1, "receiver");
        F_ID(nd_mid, RNODE_OP_ASGN1, "operator");
        F_NODE(nd_index, RNODE_OP_ASGN1, "index");
        F_NODE(nd_rvalue, RNODE_OP_ASGN1, "rvalue");
        F_LOC(call_operator_loc, RNODE_OP_ASGN1);
        F_LOC(opening_loc, RNODE_OP_ASGN1);
        F_LOC(closing_loc, RNODE_OP_ASGN1);
        LAST_NODE;
        F_LOC(binary_operator_loc, RNODE_OP_ASGN1);
        return;

      case NODE_OP_ASGN2:
        ANN("attr assignment with operator");
        ANN("format: [nd_recv].[nd_vid] [nd_mid]= [nd_value]");
        ANN("example: struct.field += foo");
        F_NODE(nd_recv, RNODE_OP_ASGN2, "receiver");
        F_CUSTOM1(nd_vid, "attr") {
            if (RNODE_OP_ASGN2(node)->nd_aid) A("? ");
            A_ID(RNODE_OP_ASGN2(node)->nd_vid);
        }
        F_ID(nd_mid, RNODE_OP_ASGN2, "operator");
        F_NODE(nd_value, RNODE_OP_ASGN2, "rvalue");
        F_LOC(call_operator_loc, RNODE_OP_ASGN2);
        F_LOC(message_loc, RNODE_OP_ASGN2);
        LAST_NODE;
        F_LOC(binary_operator_loc, RNODE_OP_ASGN2);
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
        F_NODE(nd_head, RNODE_OP_ASGN_AND, "variable");
        LAST_NODE;
        F_NODE(nd_value, RNODE_OP_ASGN_AND, "rvalue");
        return;

      case NODE_OP_CDECL:
        ANN("constant declaration with operator");
        ANN("format: [nd_head](constant) [nd_aid]= [nd_value]");
        ANN("example: A::B ||= 1");
        F_NODE(nd_head, RNODE_OP_CDECL, "constant");
        F_ID(nd_aid, RNODE_OP_CDECL, "operator");
        F_SHAREABILITY(shareability, RNODE_OP_CDECL, "shareability");
        LAST_NODE;
        F_NODE(nd_value, RNODE_OP_CDECL, "rvalue");
        return;

      case NODE_CALL:
        ANN("method invocation");
        ANN("format: [nd_recv].[nd_mid]([nd_args])");
        ANN("example: obj.foo(1)");
        F_ID(nd_mid, RNODE_CALL, "method id");
        F_NODE(nd_recv, RNODE_CALL, "receiver");
        LAST_NODE;
        F_NODE(nd_args, RNODE_CALL, "arguments");
        return;

      case NODE_OPCALL:
        ANN("method invocation");
        ANN("format: [nd_recv] [nd_mid] [nd_args]");
        ANN("example: foo + bar");
        F_ID(nd_mid, RNODE_OPCALL, "method id");
        F_NODE(nd_recv, RNODE_OPCALL, "receiver");
        LAST_NODE;
        F_NODE(nd_args, RNODE_OPCALL, "arguments");
        return;

      case NODE_FCALL:
        ANN("function call");
        ANN("format: [nd_mid]([nd_args])");
        ANN("example: foo(1)");
        F_ID(nd_mid, RNODE_FCALL, "method id");
        LAST_NODE;
        F_NODE(nd_args, RNODE_FCALL, "arguments");
        return;

      case NODE_VCALL:
        ANN("function call with no argument");
        ANN("format: [nd_mid]");
        ANN("example: foo");
        F_ID(nd_mid, RNODE_VCALL, "method id");
        return;

      case NODE_QCALL:
        ANN("safe method invocation");
        ANN("format: [nd_recv]&.[nd_mid]([nd_args])");
        ANN("example: obj&.foo(1)");
        F_ID(nd_mid, RNODE_QCALL, "method id");
        F_NODE(nd_recv, RNODE_QCALL, "receiver");
        LAST_NODE;
        F_NODE(nd_args, RNODE_QCALL, "arguments");
        return;

      case NODE_SUPER:
        ANN("super invocation");
        ANN("format: super [nd_args]");
        ANN("example: super 1");
        F_NODE(nd_args, RNODE_SUPER, "arguments");
        F_LOC(keyword_loc, RNODE_SUPER);
        F_LOC(lparen_loc, RNODE_SUPER);
        LAST_NODE;
        F_LOC(rparen_loc, RNODE_SUPER);
        return;

      case NODE_ZSUPER:
        ANN("super invocation with no argument");
        ANN("format: super");
        ANN("example: super");
        return;

      case NODE_LIST:
        ANN("list constructor");
        ANN("format: [ [nd_head], [nd_next].. ] (length: [nd_alen])");
        ANN("example: [1, 2, 3]");
        dump_array(buf, indent, comment, node);
        return;

      case NODE_ZLIST:
        ANN("empty list constructor");
        ANN("format: []");
        ANN("example: []");
        return;

      case NODE_HASH:
        if (!RNODE_HASH(node)->nd_brace) {
            ANN("keyword arguments");
            ANN("format: [nd_head]");
            ANN("example: a: 1, b: 2");
        }
        else {
            ANN("hash constructor");
            ANN("format: { [nd_head] }");
            ANN("example: { 1 => 2, 3 => 4 }");
        }
        F_CUSTOM1(nd_brace, "keyword arguments or hash literal") {
            switch (RNODE_HASH(node)->nd_brace) {
              case 0: A("0 (keyword argument)"); break;
              case 1: A("1 (hash literal)"); break;
            }
        }
        LAST_NODE;
        F_NODE(nd_head, RNODE_HASH, "contents");
        return;

      case NODE_YIELD:
        ANN("yield invocation");
        ANN("format: yield [nd_head]");
        ANN("example: yield 1");
        F_NODE(nd_head, RNODE_YIELD, "arguments");
        F_LOC(keyword_loc, RNODE_YIELD);
        F_LOC(lparen_loc, RNODE_YIELD);
        LAST_NODE;
        F_LOC(rparen_loc, RNODE_YIELD);
        return;

      case NODE_LVAR:
        ANN("local variable reference");
        ANN("format: [nd_vid](lvar)");
        ANN("example: x");
        F_ID(nd_vid, RNODE_LVAR, "local variable");
        return;
      case NODE_DVAR:
        ANN("dynamic variable reference");
        ANN("format: [nd_vid](dvar)");
        ANN("example: 1.times { x = 1; x }");
        F_ID(nd_vid, RNODE_DVAR, "local variable");
        return;
      case NODE_IVAR:
        ANN("instance variable reference");
        ANN("format: [nd_vid](ivar)");
        ANN("example: @x");
        F_ID(nd_vid, RNODE_IVAR, "instance variable");
        return;
      case NODE_CONST:
        ANN("constant reference");
        ANN("format: [nd_vid](constant)");
        ANN("example: X");
        F_ID(nd_vid, RNODE_CONST, "constant");
        return;
      case NODE_CVAR:
        ANN("class variable reference");
        ANN("format: [nd_vid](cvar)");
        ANN("example: @@x");
        F_ID(nd_vid, RNODE_CVAR, "class variable");
        return;

      case NODE_GVAR:
        ANN("global variable reference");
        ANN("format: [nd_vid](gvar)");
        ANN("example: $x");
        F_ID(nd_vid, RNODE_GVAR, "global variable");
        return;

      case NODE_NTH_REF:
        ANN("nth special variable reference");
        ANN("format: $[nd_nth]");
        ANN("example: $1, $2, ..");
        F_CUSTOM1(nd_nth, "variable") { A("$"); A_LONG(RNODE_NTH_REF(node)->nd_nth); }
        return;

      case NODE_BACK_REF:
        ANN("back special variable reference");
        ANN("format: $[nd_nth]");
        ANN("example: $&, $`, $', $+");
        F_CUSTOM1(nd_nth, "variable") {
            char name[3] = "$ ";
            name[1] = (char)RNODE_BACK_REF(node)->nd_nth;
            A(name);
        }
        return;

      case NODE_MATCH:
        ANN("match expression (against $_ implicitly)");
        ANN("format: [nd_lit] (in condition)");
        ANN("example: if /foo/; foo; end");
        LAST_NODE;
        F_VALUE(string, rb_node_regx_string_val(node), "string");
        return;

      case NODE_MATCH2:
        ANN("match expression (regexp first)");
        ANN("format: [nd_recv] =~ [nd_value]");
        ANN("example: /foo/ =~ 'foo'");
        F_NODE(nd_recv, RNODE_MATCH2, "regexp (receiver)");
        if (!RNODE_MATCH2(node)->nd_args) LAST_NODE;
        F_NODE(nd_value, RNODE_MATCH2, "string (argument)");
        if (RNODE_MATCH2(node)->nd_args) {
            LAST_NODE;
            F_NODE(nd_args, RNODE_MATCH2, "named captures");
        }
        return;

      case NODE_MATCH3:
        ANN("match expression (regexp second)");
        ANN("format: [nd_recv] =~ [nd_value]");
        ANN("example: 'foo' =~ /foo/");
        F_NODE(nd_recv, RNODE_MATCH3, "string (receiver)");
        LAST_NODE;
        F_NODE(nd_value, RNODE_MATCH3, "regexp (argument)");
        return;

      case NODE_STR:
        ANN("string literal");
        ANN("format: [nd_lit]");
        ANN("example: 'foo'");
        goto str;
      case NODE_XSTR:
        ANN("xstring literal");
        ANN("format: [nd_lit]");
        ANN("example: `foo`");
      str:
        F_VALUE(string, rb_node_str_string_val(node), "literal");
        return;

      case NODE_INTEGER:
        ANN("integer literal");
        ANN("format: [val]");
        ANN("example: 1");
        F_VALUE(val, rb_node_integer_literal_val(node), "val");
        return;

      case NODE_FLOAT:
        ANN("float literal");
        ANN("format: [val]");
        ANN("example: 1.2");
        F_VALUE(val, rb_node_float_literal_val(node), "val");
        return;

      case NODE_RATIONAL:
        ANN("rational number literal");
        ANN("format: [val]");
        ANN("example: 1r");
        F_VALUE(val, rb_node_rational_literal_val(node), "val");
        return;

      case NODE_IMAGINARY:
        ANN("complex number literal");
        ANN("format: [val]");
        ANN("example: 1i");
        F_VALUE(val, rb_node_imaginary_literal_val(node), "val");
        return;

      case NODE_REGX:
        ANN("regexp literal");
        ANN("format: [string]");
        ANN("example: /foo/");
        F_VALUE(string, rb_node_regx_string_val(node), "string");
        F_LOC(opening_loc, RNODE_REGX);
        F_LOC(content_loc, RNODE_REGX);
        LAST_NODE;
        F_LOC(closing_loc, RNODE_REGX);
        return;

      case NODE_ONCE:
        ANN("once evaluation");
        ANN("format: [nd_body]");
        ANN("example: /foo#{ bar }baz/o");
        LAST_NODE;
        F_NODE(nd_body, RNODE_ONCE, "body");
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
        F_VALUE(string, rb_node_dstr_string_val(node), "preceding string");
        if (!RNODE_DSTR(node)->nd_next) return;
        F_NODE(nd_next->nd_head, RNODE_DSTR, "interpolation");
        LAST_NODE;
        F_NODE(nd_next->nd_next, RNODE_DSTR, "tailing strings");
        return;

      case NODE_SYM:
        ANN("symbol literal");
        ANN("format: [string]");
        ANN("example: :foo");
        F_VALUE(string, rb_node_sym_string_val(node), "string");
        return;

      case NODE_EVSTR:
        ANN("interpolation expression");
        ANN("format: \"..#{ [nd_body] }..\"");
        ANN("example: \"foo#{ bar }baz\"");
        F_NODE(nd_body, RNODE_EVSTR, "body");
        F_LOC(opening_loc, RNODE_EVSTR);
        LAST_NODE;
        F_LOC(closing_loc, RNODE_EVSTR);
        return;

      case NODE_ARGSCAT:
        ANN("splat argument following arguments");
        ANN("format: ..(*[nd_head], [nd_body..])");
        ANN("example: foo(*ary, post_arg1, post_arg2)");
        F_NODE(nd_head, RNODE_ARGSCAT, "preceding array");
        LAST_NODE;
        F_NODE(nd_body, RNODE_ARGSCAT, "following array");
        return;

      case NODE_ARGSPUSH:
        ANN("splat argument following one argument");
        ANN("format: ..(*[nd_head], [nd_body])");
        ANN("example: foo(*ary, post_arg)");
        F_NODE(nd_head, RNODE_ARGSPUSH, "preceding array");
        LAST_NODE;
        F_NODE(nd_body, RNODE_ARGSPUSH, "following element");
        return;

      case NODE_SPLAT:
        ANN("splat argument");
        ANN("format: *[nd_head]");
        ANN("example: foo(*ary)");
        F_NODE(nd_head, RNODE_SPLAT, "splat'ed array");
        LAST_NODE;
        F_LOC(operator_loc, RNODE_SPLAT);
        return;

      case NODE_BLOCK_PASS:
        ANN("arguments with block argument");
        ANN("format: ..([nd_head], &[nd_body])");
        ANN("example: foo(x, &blk)");
        F_CUSTOM1(forwarding, "arguments forwarding or not") {
            switch (RNODE_BLOCK_PASS(node)->forwarding) {
              case 0: A("0 (no forwarding)"); break;
              case 1: A("1 (forwarding)"); break;
            }
        }
        F_NODE(nd_head, RNODE_BLOCK_PASS, "other arguments");
        F_NODE(nd_body, RNODE_BLOCK_PASS, "block argument");
        LAST_NODE;
        F_LOC(operator_loc, RNODE_BLOCK_PASS);
        return;

      case NODE_DEFN:
        ANN("method definition");
        ANN("format: def [nd_mid] [nd_defn]; end");
        ANN("example: def foo; bar; end");
        F_ID(nd_mid, RNODE_DEFN, "method name");
        LAST_NODE;
        F_NODE(nd_defn, RNODE_DEFN, "method definition");
        return;

      case NODE_DEFS:
        ANN("singleton method definition");
        ANN("format: def [nd_recv].[nd_mid] [nd_defn]; end");
        ANN("example: def obj.foo; bar; end");
        F_NODE(nd_recv, RNODE_DEFS, "receiver");
        F_ID(nd_mid, RNODE_DEFS, "method name");
        LAST_NODE;
        F_NODE(nd_defn, RNODE_DEFS, "method definition");
        return;

      case NODE_ALIAS:
        ANN("method alias statement");
        ANN("format: alias [nd_1st] [nd_2nd]");
        ANN("example: alias bar foo");
        F_NODE(nd_1st, RNODE_ALIAS, "new name");
        F_NODE(nd_2nd, RNODE_ALIAS, "old name");
        LAST_NODE;
        F_LOC(keyword_loc, RNODE_ALIAS);
        return;

      case NODE_VALIAS:
        ANN("global variable alias statement");
        ANN("format: alias [nd_alias](gvar) [nd_orig](gvar)");
        ANN("example: alias $y $x");
        F_ID(nd_alias, RNODE_VALIAS, "new name");
        F_ID(nd_orig, RNODE_VALIAS, "old name");
        F_LOC(keyword_loc, RNODE_VALIAS);
        return;

      case NODE_UNDEF:
        ANN("method undef statement");
        ANN("format: undef [nd_undefs]");
        ANN("example: undef foo");
        LAST_NODE;
        F_ARRAY(nd_undefs, RNODE_UNDEF, "nd_undefs");
        F_LOC(keyword_loc, RNODE_UNDEF);
        return;

      case NODE_CLASS:
        ANN("class definition");
        ANN("format: class [nd_cpath] < [nd_super]; [nd_body]; end");
        ANN("example: class C2 < C; ..; end");
        F_NODE(nd_cpath, RNODE_CLASS, "class path");
        F_NODE(nd_super, RNODE_CLASS, "superclass");
        F_NODE(nd_body, RNODE_CLASS, "class definition");
        F_LOC(class_keyword_loc, RNODE_CLASS);
        F_LOC(inheritance_operator_loc, RNODE_CLASS);
        LAST_NODE;
        F_LOC(end_keyword_loc, RNODE_CLASS);
        return;

      case NODE_MODULE:
        ANN("module definition");
        ANN("format: module [nd_cpath]; [nd_body]; end");
        ANN("example: module M; ..; end");
        F_NODE(nd_cpath, RNODE_MODULE, "module path");
        LAST_NODE;
        F_NODE(nd_body, RNODE_MODULE, "module definition");
        return;

      case NODE_SCLASS:
        ANN("singleton class definition");
        ANN("format: class << [nd_recv]; [nd_body]; end");
        ANN("example: class << obj; ..; end");
        F_NODE(nd_recv, RNODE_SCLASS, "receiver");
        LAST_NODE;
        F_NODE(nd_body, RNODE_SCLASS, "singleton class definition");
        return;

      case NODE_COLON2:
        ANN("scoped constant reference");
        ANN("format: [nd_head]::[nd_mid]");
        ANN("example: M::C");
        F_ID(nd_mid, RNODE_COLON2, "constant name");
        F_NODE(nd_head, RNODE_COLON2, "receiver");
        F_LOC(delimiter_loc, RNODE_COLON2);
        LAST_NODE;
        F_LOC(name_loc, RNODE_COLON2);
        return;

      case NODE_COLON3:
        ANN("top-level constant reference");
        ANN("format: ::[nd_mid]");
        ANN("example: ::Object");
        F_ID(nd_mid, RNODE_COLON3, "constant name");
        F_LOC(delimiter_loc, RNODE_COLON3);
        F_LOC(name_loc, RNODE_COLON3);
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
        F_NODE(nd_beg, RNODE_DOT2, "begin");
        F_NODE(nd_end, RNODE_DOT2, "end");
        LAST_NODE;
        F_LOC(operator_loc, RNODE_DOT2);
        return;

      case NODE_SELF:
        ANN("self");
        ANN("format: self");
        ANN("example: self");
        F_CUSTOM1(nd_state, "nd_state") {
            A_INT((int)RNODE_SELF(node)->nd_state);
        }
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
        LAST_NODE;
        F_NODE(nd_head, RNODE_DEFINED, "expr");
        return;

      case NODE_POSTEXE:
        ANN("post-execution");
        ANN("format: END { [nd_body] }");
        ANN("example: END { foo }");
        F_NODE(nd_body, RNODE_POSTEXE, "END clause");
        F_LOC(keyword_loc, RNODE_POSTEXE);
        F_LOC(opening_loc, RNODE_POSTEXE);
        LAST_NODE;
        F_LOC(closing_loc, RNODE_POSTEXE);
        return;

      case NODE_ATTRASGN:
        ANN("attr assignment");
        ANN("format: [nd_recv].[nd_mid] = [nd_args]");
        ANN("example: struct.field = foo");
        F_NODE(nd_recv, RNODE_ATTRASGN, "receiver");
        F_ID(nd_mid, RNODE_ATTRASGN, "method name");
        LAST_NODE;
        F_NODE(nd_args, RNODE_ATTRASGN, "arguments");
        return;

      case NODE_LAMBDA:
        ANN("lambda expression");
        ANN("format: -> [nd_body]");
        ANN("example: -> { foo }");
        F_NODE(nd_body, RNODE_LAMBDA, "lambda clause");
        F_LOC(operator_loc, RNODE_LAMBDA);
        F_LOC(opening_loc, RNODE_LAMBDA);
        LAST_NODE;
        F_LOC(closing_loc, RNODE_LAMBDA);
        return;

      case NODE_OPT_ARG:
        ANN("optional arguments");
        ANN("format: def method_name([nd_body=some], [nd_next..])");
        ANN("example: def foo(a, b=1, c); end");
        F_NODE(nd_body, RNODE_OPT_ARG, "body");
        LAST_NODE;
        F_NODE(nd_next, RNODE_OPT_ARG, "next");
        return;

      case NODE_KW_ARG:
        ANN("keyword arguments");
        ANN("format: def method_name([nd_body=some], [nd_next..])");
        ANN("example: def foo(a:1, b:2); end");
        F_NODE(nd_body, RNODE_KW_ARG, "body");
        LAST_NODE;
        F_NODE(nd_next, RNODE_KW_ARG, "next");
        return;

      case NODE_POSTARG:
        ANN("post arguments");
        ANN("format: *[nd_1st], [nd_2nd..] = ..");
        ANN("example: a, *rest, z = foo");
        if (NODE_NAMED_REST_P(RNODE_POSTARG(node)->nd_1st)) {
            F_NODE(nd_1st, RNODE_POSTARG, "rest argument");
        }
        else {
            F_MSG(nd_1st, "rest argument", "NODE_SPECIAL_NO_NAME_REST (rest argument without name)");
        }
        LAST_NODE;
        F_NODE(nd_2nd, RNODE_POSTARG, "post arguments");
        return;

      case NODE_ARGS:
        ANN("method parameters");
        ANN("format: def method_name(.., [nd_ainfo.nd_optargs], *[nd_ainfo.rest_arg], [nd_ainfo.first_post_arg], .., [nd_ainfo.kw_args], **[nd_ainfo.kw_rest_arg], &[nd_ainfo.block_arg])");
        ANN("example: def foo(a, b, opt1=1, opt2=2, *rest, y, z, kw: 1, **kwrest, &blk); end");
        F_CUSTOM1(nd_ainfo.forwarding, "arguments forwarding or not") {
            switch (RNODE_ARGS(node)->nd_ainfo.forwarding) {
              case 0: A("0 (no forwarding)"); break;
              case 1: A("1 (forwarding)"); break;
            }
        }
        F_INT(nd_ainfo.pre_args_num, RNODE_ARGS, "count of mandatory (pre-)arguments");
        F_NODE(nd_ainfo.pre_init, RNODE_ARGS, "initialization of (pre-)arguments");
        F_INT(nd_ainfo.post_args_num, RNODE_ARGS, "count of mandatory post-arguments");
        F_NODE(nd_ainfo.post_init, RNODE_ARGS, "initialization of post-arguments");
        F_ID(nd_ainfo.first_post_arg, RNODE_ARGS, "first post argument");
        F_CUSTOM1(nd_ainfo.rest_arg, "rest argument") {
            if (RNODE_ARGS(node)->nd_ainfo.rest_arg == NODE_SPECIAL_EXCESSIVE_COMMA) {
                A("1 (excessed comma)");
            }
            else {
                A_ID(RNODE_ARGS(node)->nd_ainfo.rest_arg);
            }
        }
        F_ID(nd_ainfo.block_arg, RNODE_ARGS, "block argument");
        F_NODE(nd_ainfo.opt_args, RNODE_ARGS, "optional arguments");
        F_NODE(nd_ainfo.kw_args, RNODE_ARGS, "keyword arguments");
        LAST_NODE;
        F_NODE(nd_ainfo.kw_rest_arg, RNODE_ARGS, "keyword rest argument");
        return;

      case NODE_SCOPE:
        ANN("new scope");
        ANN("format: [nd_tbl]: local table, [nd_args]: arguments, [nd_body]: body");
        F_CUSTOM1(nd_tbl, "local table") {
            rb_ast_id_table_t *tbl = RNODE_SCOPE(node)->nd_tbl;
            int i;
            int size = tbl ? tbl->size : 0;
            if (size == 0) A("(empty)");
            for (i = 0; i < size; i++) {
                A_ID(tbl->ids[i]); if (i < size - 1) A(",");
            }
        }
        F_NODE(nd_args, RNODE_SCOPE, "arguments");
        LAST_NODE;
        F_NODE(nd_body, RNODE_SCOPE, "body");
        return;

      case NODE_ARYPTN:
        ANN("array pattern");
        ANN("format: [nd_pconst]([pre_args], ..., *[rest_arg], [post_args], ...)");
        F_NODE(nd_pconst, RNODE_ARYPTN, "constant");
        F_NODE(pre_args, RNODE_ARYPTN, "pre arguments");
        if (NODE_NAMED_REST_P(RNODE_ARYPTN(node)->rest_arg)) {
            F_NODE(rest_arg, RNODE_ARYPTN, "rest argument");
        }
        else {
            F_MSG(rest_arg, "rest argument", "NODE_SPECIAL_NO_NAME_REST (rest argument without name)");
        }
        LAST_NODE;
        F_NODE(post_args, RNODE_ARYPTN, "post arguments");
        return;

      case NODE_FNDPTN:
        ANN("find pattern");
        ANN("format: [nd_pconst](*[pre_rest_arg], args, ..., *[post_rest_arg])");
        F_NODE(nd_pconst, RNODE_FNDPTN, "constant");
        if (NODE_NAMED_REST_P(RNODE_FNDPTN(node)->pre_rest_arg)) {
            F_NODE(pre_rest_arg, RNODE_FNDPTN, "pre rest argument");
        }
        else {
            F_MSG(pre_rest_arg, "pre rest argument", "NODE_SPECIAL_NO_NAME_REST (rest argument without name)");
        }
        F_NODE(args, RNODE_FNDPTN, "arguments");

        LAST_NODE;
        if (NODE_NAMED_REST_P(RNODE_FNDPTN(node)->post_rest_arg)) {
            F_NODE(post_rest_arg, RNODE_FNDPTN, "post rest argument");
        }
        else {
            F_MSG(post_rest_arg, "post rest argument", "NODE_SPECIAL_NO_NAME_REST (rest argument without name)");
        }
        return;

      case NODE_HSHPTN:
        ANN("hash pattern");
        ANN("format: [nd_pconst]([nd_pkwargs], ..., **[nd_pkwrestarg])");
        F_NODE(nd_pconst, RNODE_HSHPTN, "constant");
        F_NODE(nd_pkwargs, RNODE_HSHPTN, "keyword arguments");
        LAST_NODE;
        if (RNODE_HSHPTN(node)->nd_pkwrestarg == NODE_SPECIAL_NO_REST_KEYWORD) {
            F_MSG(nd_pkwrestarg, "keyword rest argument", "NODE_SPECIAL_NO_REST_KEYWORD (**nil)");
        }
        else {
            F_NODE(nd_pkwrestarg, RNODE_HSHPTN, "keyword rest argument");
        }
        return;

      case NODE_LINE:
        ANN("line");
        ANN("format: [lineno]");
        ANN("example: __LINE__");
        return;

      case NODE_FILE:
        ANN("line");
        ANN("format: [path]");
        ANN("example: __FILE__");
        F_VALUE(path, rb_node_file_path_val(node), "path");
        return;

      case NODE_ENCODING:
        ANN("encoding");
        ANN("format: [enc]");
        ANN("example: __ENCODING__");
        F_VALUE(enc, rb_node_encoding_val(node), "enc");
        return;

      case NODE_ERROR:
        ANN("Broken input recovered by Error Tolerant mode");
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
