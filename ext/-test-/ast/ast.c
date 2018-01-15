#include "ruby.h"
#include "ruby/encoding.h"
#include "internal.h"
#include "node.h"
#include "vm_core.h"

static VALUE rb_mAST;
static VALUE rb_cNode;

struct ASTNodeData {
    rb_ast_t *ast;
    NODE *node;
};

static void
node_gc_mark(void *ptr)
{
    struct ASTNodeData *data = (struct ASTNodeData *)ptr;
    rb_gc_mark((VALUE)data->ast);
}

static const rb_data_type_t rb_node_type = {
    "AST/node",
    {node_gc_mark, RUBY_TYPED_DEFAULT_FREE, 0,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE rb_ast_node_alloc(VALUE klass);

static void
setup_node(VALUE obj, rb_ast_t *ast, NODE *node)
{
    struct ASTNodeData *data;

    TypedData_Get_Struct(obj, struct ASTNodeData, &rb_node_type, data);
    data->ast = ast;
    data->node = node;
}

static VALUE
ast_new_internal(rb_ast_t *ast, NODE *node)
{
    VALUE obj;

    obj = rb_ast_node_alloc(rb_cNode);
    setup_node(obj, ast, node);

    return obj;
}

static VALUE
rb_ast_s_parse(VALUE module, VALUE str)
{
    VALUE obj;
    rb_ast_t *ast = 0;
    rb_binding_t *toplevel_binding;

    const VALUE parser = rb_parser_new();

    GetBindingPtr(rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING")),
                  toplevel_binding);

    str = rb_check_string_type(str);
    rb_parser_set_context(parser, &toplevel_binding->block, 1);
    ast = rb_parser_compile_string_path(parser, rb_str_new_cstr("no file name"), str, 1);

    if (!ast->body.root) return Qnil;

    obj = ast_new_internal(ast, (NODE *)ast->body.root);

    return obj;
}

static VALUE
rb_ast_s_parse_file(VALUE module, VALUE path)
{
    VALUE obj, f;
    rb_ast_t *ast = 0;
    rb_binding_t *toplevel_binding;
    rb_encoding *enc = rb_utf8_encoding();

    const VALUE parser = rb_parser_new();

    GetBindingPtr(rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING")),
                  toplevel_binding);

    FilePathValue(path);
    f = rb_file_open_str(path, "r");
    rb_funcall(f, rb_intern("set_encoding"), 2, rb_enc_from_encoding(enc), rb_str_new_cstr("-"));
    rb_parser_set_context(parser, &toplevel_binding->block, 1);
    ast = rb_parser_compile_file_path(parser, path, f, 1);

    rb_io_close(f);

    if (!ast->body.root) return Qnil;

    obj = ast_new_internal(ast, (NODE *)ast->body.root);

    return obj;
}

static VALUE
rb_ast_node_alloc(VALUE klass)
{
    struct ASTNodeData *data;
    VALUE obj = TypedData_Make_Struct(klass, struct ASTNodeData, &rb_node_type, data);

    return obj;
}

static const char*
node_type_to_str(NODE *node)
{
    return ruby_node_name(nd_type(node));
}

static VALUE
rb_ast_node_type(VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return rb_str_new_cstr(node_type_to_str(data->node));
}

#define NEW_CHILD(ast, node) node ? ast_new_internal(ast, node) : Qnil

static VALUE
rb_ary_new_from_node_args(rb_ast_t *ast, long n, ...)
{
    va_list ar;
    VALUE ary;
    long i;

    ary = rb_ary_new2(n);

    va_start(ar, n);
    for (i=0; i<n; i++) {
	NODE *node;
	node = va_arg(ar, NODE *);
	rb_ary_push(ary, NEW_CHILD(ast, node));
    }
    va_end(ar);
    return ary;
}

static VALUE
dump_block(rb_ast_t *ast, NODE *node)
{
    VALUE ary = rb_ary_new();
    do {
	rb_ary_push(ary, NEW_CHILD(ast, node->nd_head));
    } while (node->nd_next &&
	nd_type(node->nd_next) == NODE_BLOCK &&
	(node = node->nd_next, 1));
    if (node->nd_next) {
	rb_ary_push(ary, NEW_CHILD(ast, node->nd_next));
    }

    return ary;
}

static VALUE
dump_array(rb_ast_t *ast, NODE *node)
{
    VALUE ary = rb_ary_new();
    rb_ary_push(ary, NEW_CHILD(ast, node->nd_head));

    while (node->nd_next && nd_type(node->nd_next) == NODE_ARRAY) {
	node = node->nd_next;
	rb_ary_push(ary, NEW_CHILD(ast, node->nd_head));
    }
    rb_ary_push(ary, NEW_CHILD(ast, node->nd_next));

    return ary;
}

static VALUE
node_children(rb_ast_t *ast, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_BLOCK:
	return dump_block(ast, node);
      case NODE_IF:
	return rb_ary_new_from_node_args(ast, 3, node->nd_cond, node->nd_body, node->nd_else);
      case NODE_UNLESS:
	return rb_ary_new_from_node_args(ast, 3, node->nd_cond, node->nd_body, node->nd_else);
      case NODE_CASE:
	return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_body);
      case NODE_CASE2:
	return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_body);
      case NODE_WHEN:
	return rb_ary_new_from_node_args(ast, 3, node->nd_head, node->nd_body, node->nd_next);
      case NODE_WHILE:
	goto loop;
      case NODE_UNTIL:
      loop:
	return rb_ary_new_from_node_args(ast, 2, node->nd_cond, node->nd_body);
      case NODE_ITER:
	goto iter;
      case NODE_FOR:
      iter:
	return rb_ary_new_from_node_args(ast, 2, node->nd_iter, node->nd_body);
      case NODE_BREAK:
	goto jump;
      case NODE_NEXT:
	goto jump;
      case NODE_RETURN:
      jump:
	return rb_ary_new_from_node_args(ast, 1, node->nd_stts);
      case NODE_REDO:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_RETRY:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_BEGIN:
	return rb_ary_new_from_node_args(ast, 1, node->nd_body);
      case NODE_RESCUE:
	return rb_ary_new_from_node_args(ast, 3, node->nd_head, node->nd_resq, node->nd_else);
      case NODE_RESBODY:
	return rb_ary_new_from_node_args(ast, 3, node->nd_args, node->nd_body, node->nd_head);
      case NODE_ENSURE:
	return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_ensr);
      case NODE_AND:
	goto andor;
      case NODE_OR:
      andor:
	{
	    VALUE ary = rb_ary_new();
	    enum node_type type = nd_type(node);

	    while (1) {
		rb_ary_push(ary, NEW_CHILD(ast, node->nd_1st));
		if (!node->nd_2nd || nd_type(node->nd_2nd) != (int)type)
		    break;
		node = node->nd_2nd;
	    }
	    rb_ary_push(ary, NEW_CHILD(ast, node->nd_2nd));
	    return ary;
	}
      case NODE_MASGN:
        if (node->nd_args != NODE_SPECIAL_NO_NAME_REST) {
	    return rb_ary_new_from_node_args(ast, 3, node->nd_value, node->nd_head, node->nd_args);
        }
	return rb_ary_new_from_node_args(ast, 2, node->nd_value, node->nd_head);
      case NODE_LASGN:
	goto asgn;
      case NODE_DASGN:
	goto asgn;
      case NODE_DASGN_CURR:
	goto asgn;
      case NODE_IASGN:
	goto asgn;
      case NODE_CVASGN:
      asgn:
        if (node->nd_value == NODE_SPECIAL_REQUIRED_KEYWORD) {
	    return rb_ary_new_from_node_args(ast, 0);
        }
	return rb_ary_new_from_node_args(ast, 1, node->nd_value);
      case NODE_GASGN:
	return rb_ary_new_from_node_args(ast, 1, node->nd_value);
      case NODE_CDECL:
        if (node->nd_vid) {
	    return rb_ary_new_from_node_args(ast, 1, node->nd_value);
        }
	return rb_ary_new_from_node_args(ast, 2, node->nd_else, node->nd_value);
      case NODE_OP_ASGN1:
	return rb_ary_new_from_node_args(ast, 3, node->nd_recv, node->nd_args->nd_head, node->nd_args->nd_body);
      case NODE_OP_ASGN2:
	return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_value);
      case NODE_OP_ASGN_AND:
	goto asgn_andor;
      case NODE_OP_ASGN_OR:
      asgn_andor:
	return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_value);
      case NODE_OP_CDECL:
	return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_value);
      case NODE_CALL:
      case NODE_OPCALL:
	return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_args);
      case NODE_FCALL:
	return rb_ary_new_from_node_args(ast, 1, node->nd_args);
      case NODE_VCALL:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_QCALL:
	return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_args);
      case NODE_SUPER:
	return rb_ary_new_from_node_args(ast, 1, node->nd_args);
      case NODE_ZSUPER:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_ARRAY:
	goto ary;
      case NODE_VALUES:
      ary:
	return dump_array(ast, node);
      case NODE_ZARRAY:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_HASH:
	return rb_ary_new_from_node_args(ast, 1, node->nd_head);
      case NODE_YIELD:
	return rb_ary_new_from_node_args(ast, 1, node->nd_head);
      case NODE_LVAR:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_DVAR:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_IVAR:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_CONST:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_CVAR:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_GVAR:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_NTH_REF:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_BACK_REF:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_MATCH:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_MATCH2:
	if (node->nd_args) {
	    return rb_ary_new_from_node_args(ast, 3, node->nd_recv, node->nd_value, node->nd_args);
	}
	return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_value);
      case NODE_MATCH3:
	return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_value);
      case NODE_LIT:
	goto lit;
      case NODE_STR:
	goto lit;
      case NODE_XSTR:
      lit:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_ONCE:
        return rb_ary_new_from_node_args(ast, 1, node->nd_body);
      case NODE_DSTR:
	goto dlit;
      case NODE_DXSTR:
	goto dlit;
      case NODE_DREGX:
	goto dlit;
      case NODE_DSYM:
      dlit:
	return rb_ary_new_from_node_args(ast, 2, node->nd_next->nd_head, node->nd_next->nd_next);
      case NODE_EVSTR:
	return rb_ary_new_from_node_args(ast, 1, node->nd_body);
      case NODE_ARGSCAT:
	return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_body);
      case NODE_ARGSPUSH:
	return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_body);
      case NODE_SPLAT:
	return rb_ary_new_from_node_args(ast, 1, node->nd_head);
      case NODE_BLOCK_PASS:
	return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_body);
      case NODE_DEFN:
	return rb_ary_new_from_node_args(ast, 1, node->nd_defn);
      case NODE_DEFS:
        return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_defn);
      case NODE_ALIAS:
	return rb_ary_new_from_node_args(ast, 2, node->nd_1st, node->nd_2nd);
      case NODE_VALIAS:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_UNDEF:
	return rb_ary_new_from_node_args(ast, 1, node->nd_undef);
      case NODE_CLASS:
	return rb_ary_new_from_node_args(ast, 3, node->nd_cpath, node->nd_super, node->nd_body);
      case NODE_MODULE:
	return rb_ary_new_from_node_args(ast, 2, node->nd_cpath, node->nd_body);
      case NODE_SCLASS:
	return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_body);
      case NODE_COLON2:
	return rb_ary_new_from_node_args(ast, 1, node->nd_head);
      case NODE_COLON3:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_DOT2:
	goto dot;
      case NODE_DOT3:
	goto dot;
      case NODE_FLIP2:
	goto dot;
      case NODE_FLIP3:
      dot:
	return rb_ary_new_from_node_args(ast, 2, node->nd_beg, node->nd_end);
      case NODE_SELF:
      return rb_ary_new_from_node_args(ast, 0);
      case NODE_NIL:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_TRUE:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_FALSE:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_ERRINFO:
	return rb_ary_new_from_node_args(ast, 0);
      case NODE_DEFINED:
	return rb_ary_new_from_node_args(ast, 1, node->nd_head);
      case NODE_POSTEXE:
	return rb_ary_new_from_node_args(ast, 1, node->nd_body);
      case NODE_ATTRASGN:
	return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_args);
      case NODE_LAMBDA:
	return rb_ary_new_from_node_args(ast, 1, node->nd_body);
      case NODE_OPT_ARG:
	return rb_ary_new_from_node_args(ast, 2, node->nd_body, node->nd_next);
      case NODE_KW_ARG:
	return rb_ary_new_from_node_args(ast, 2, node->nd_body, node->nd_next);
      case NODE_POSTARG:
	if (node->nd_1st != NODE_SPECIAL_NO_NAME_REST) {
	    return rb_ary_new_from_node_args(ast, 2, node->nd_1st, node->nd_2nd);
	}
	return rb_ary_new_from_node_args(ast, 1, node->nd_2nd);
      case NODE_ARGS:
	return rb_ary_new_from_node_args(ast, 5, node->nd_ainfo->pre_init, node->nd_ainfo->post_init, node->nd_ainfo->opt_args, node->nd_ainfo->kw_args, node->nd_ainfo->kw_rest_arg);
      case NODE_SCOPE:
	return rb_ary_new_from_node_args(ast, 2, node->nd_args, node->nd_body);
      case NODE_ARGS_AUX:
      case NODE_LAST:
	break;
    }

    rb_bug("dump_node: unknown node: %s", ruby_node_name(nd_type(node)));
}

static VALUE
rb_ast_node_children(VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return node_children(data->ast, data->node);
}

static VALUE
rb_ast_node_first_lineno(VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(nd_first_lineno(data->node));
}

static VALUE
rb_ast_node_first_column(VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(nd_first_column(data->node));
}

static VALUE
rb_ast_node_last_lineno(VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(nd_last_lineno(data->node));
}

static VALUE
rb_ast_node_last_column(VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(nd_last_column(data->node));
}

static VALUE
rb_ast_node_inspect(VALUE self)
{
    VALUE str;
    VALUE cname;
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    cname = rb_class_path(rb_obj_class(self));
    str = rb_str_new2("#<");

    rb_str_append(str, cname);
    rb_str_cat2(str, "(");
    rb_str_catf(str, "%s(%d) %d:%d, %d:%d", node_type_to_str(data->node), nd_type(data->node), nd_first_lineno(data->node), nd_first_column(data->node), nd_last_lineno(data->node), nd_last_column(data->node));
    rb_str_cat2(str, "): >");

    return str;
}

void
Init_ast(void)
{
    rb_mAST = rb_define_module("AST");
    rb_cNode = rb_define_class_under(rb_mAST, "Node", rb_cObject);

    rb_define_alloc_func(rb_cNode, rb_ast_node_alloc);
    rb_define_singleton_method(rb_mAST, "parse", rb_ast_s_parse, 1);
    rb_define_singleton_method(rb_mAST, "parse_file", rb_ast_s_parse_file, 1);
    rb_define_method(rb_cNode, "type", rb_ast_node_type, 0);
    rb_define_method(rb_cNode, "first_lineno", rb_ast_node_first_lineno, 0);
    rb_define_method(rb_cNode, "first_column", rb_ast_node_first_column, 0);
    rb_define_method(rb_cNode, "last_lineno", rb_ast_node_last_lineno, 0);
    rb_define_method(rb_cNode, "last_column", rb_ast_node_last_column, 0);
    rb_define_method(rb_cNode, "children", rb_ast_node_children, 0);
    rb_define_method(rb_cNode, "inspect", rb_ast_node_inspect, 0);
}
