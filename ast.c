/* indent-tabs-mode: nil */
#include "internal.h"
#include "internal/parse.h"
#include "internal/symbol.h"
#include "internal/warnings.h"
#include "iseq.h"
#include "node.h"
#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/util.h"
#include "vm_core.h"

#include "builtin.h"

static VALUE rb_mAST;
static VALUE rb_cNode;

struct ASTNodeData {
    rb_ast_t *ast;
    const NODE *node;
};

static void
node_gc_mark(void *ptr)
{
    struct ASTNodeData *data = (struct ASTNodeData *)ptr;
    rb_gc_mark((VALUE)data->ast);
}

static size_t
node_memsize(const void *ptr)
{
    struct ASTNodeData *data = (struct ASTNodeData *)ptr;
    return rb_ast_memsize(data->ast);
}

static const rb_data_type_t rb_node_type = {
    "AST/node",
    {node_gc_mark, RUBY_TYPED_DEFAULT_FREE, node_memsize,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE rb_ast_node_alloc(VALUE klass);

static void
setup_node(VALUE obj, rb_ast_t *ast, const NODE *node)
{
    struct ASTNodeData *data;

    TypedData_Get_Struct(obj, struct ASTNodeData, &rb_node_type, data);
    data->ast = ast;
    data->node = node;
}

static VALUE
ast_new_internal(rb_ast_t *ast, const NODE *node)
{
    VALUE obj;

    obj = rb_ast_node_alloc(rb_cNode);
    setup_node(obj, ast, node);

    return obj;
}

static VALUE rb_ast_parse_str(VALUE str, VALUE keep_script_lines);
static VALUE rb_ast_parse_file(VALUE path, VALUE keep_script_lines);

static VALUE
ast_parse_new(void)
{
    return rb_parser_set_context(rb_parser_new(), NULL, 0);
}

static VALUE
ast_parse_done(rb_ast_t *ast)
{
    if (!ast->body.root) {
        rb_ast_dispose(ast);
        rb_exc_raise(GET_EC()->errinfo);
    }

    return ast_new_internal(ast, (NODE *)ast->body.root);
}

static VALUE
ast_s_parse(rb_execution_context_t *ec, VALUE module, VALUE str, VALUE keep_script_lines)
{
    return rb_ast_parse_str(str, keep_script_lines);
}

static VALUE
rb_ast_parse_str(VALUE str, VALUE keep_script_lines)
{
    rb_ast_t *ast = 0;

    StringValue(str);
    VALUE vparser = ast_parse_new();
    if (RTEST(keep_script_lines)) rb_parser_keep_script_lines(vparser);
    ast = rb_parser_compile_string_path(vparser, Qnil, str, 1);
    return ast_parse_done(ast);
}

static VALUE
ast_s_parse_file(rb_execution_context_t *ec, VALUE module, VALUE path, VALUE keep_script_lines)
{
    return rb_ast_parse_file(path, keep_script_lines);
}

static VALUE
rb_ast_parse_file(VALUE path, VALUE keep_script_lines)
{
    VALUE f;
    rb_ast_t *ast = 0;
    rb_encoding *enc = rb_utf8_encoding();

    FilePathValue(path);
    f = rb_file_open_str(path, "r");
    rb_funcall(f, rb_intern("set_encoding"), 2, rb_enc_from_encoding(enc), rb_str_new_cstr("-"));
    VALUE vparser = ast_parse_new();
    if (RTEST(keep_script_lines)) rb_parser_keep_script_lines(vparser);
    ast = rb_parser_compile_file_path(vparser, Qnil, f, 1);
    rb_io_close(f);
    return ast_parse_done(ast);
}

static VALUE
lex_array(VALUE array, int index)
{
    VALUE str = rb_ary_entry(array, index);
    if (!NIL_P(str)) {
        StringValue(str);
        if (!rb_enc_asciicompat(rb_enc_get(str))) {
            rb_raise(rb_eArgError, "invalid source encoding");
        }
    }
    return str;
}

static VALUE
rb_ast_parse_array(VALUE array, VALUE keep_script_lines)
{
    rb_ast_t *ast = 0;

    array = rb_check_array_type(array);
    VALUE vparser = ast_parse_new();
    if (RTEST(keep_script_lines)) rb_parser_keep_script_lines(vparser);
    ast = rb_parser_compile_generic(vparser, lex_array, Qnil, array, 1);
    return ast_parse_done(ast);
}

static VALUE node_children(rb_ast_t*, const NODE*);

static VALUE
node_find(VALUE self, const int node_id)
{
    VALUE ary;
    long i;
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    if (nd_node_id(data->node) == node_id) return self;

    ary = node_children(data->ast, data->node);

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        VALUE child = RARRAY_AREF(ary, i);

        if (CLASS_OF(child) == rb_cNode) {
            VALUE result = node_find(child, node_id);
            if (RTEST(result)) return result;
        }
    }

    return Qnil;
}

extern VALUE rb_e_script;

static VALUE
script_lines(VALUE path)
{
    VALUE hash, lines;
    ID script_lines;
    CONST_ID(script_lines, "SCRIPT_LINES__");
    if (!rb_const_defined_at(rb_cObject, script_lines)) return Qnil;
    hash = rb_const_get_at(rb_cObject, script_lines);
    if (!RB_TYPE_P(hash, T_HASH)) return Qnil;
    lines = rb_hash_lookup(hash, path);
    if (!RB_TYPE_P(lines, T_ARRAY)) return Qnil;
    return lines;
}

static VALUE
ast_s_of(rb_execution_context_t *ec, VALUE module, VALUE body, VALUE keep_script_lines)
{
    VALUE node, lines = Qnil;
    const rb_iseq_t *iseq;
    int node_id;

    if (rb_frame_info_p(body)) {
        iseq = rb_get_iseq_from_frame_info(body);
        node_id = rb_get_node_id_from_frame_info(body);
    }
    else {
        iseq = NULL;

        if (rb_obj_is_proc(body)) {
            iseq = vm_proc_iseq(body);

            if (!rb_obj_is_iseq((VALUE)iseq)) return Qnil;
        }
        else {
            iseq = rb_method_iseq(body);
        }
        if (iseq) {
            node_id = iseq->body->location.node_id;
        }
    }

    if (!iseq) {
        return Qnil;
    }
    lines = iseq->body->variable.script_lines;

    VALUE path = rb_iseq_path(iseq);
    int e_option = RSTRING_LEN(path) == 2 && memcmp(RSTRING_PTR(path), "-e", 2) == 0;

    if (NIL_P(lines) && rb_iseq_from_eval_p(iseq) && !e_option) {
        rb_raise(rb_eArgError, "cannot get AST for method defined in eval");
    }

    if (!NIL_P(lines) || !NIL_P(lines = script_lines(path))) {
        node = rb_ast_parse_array(lines, keep_script_lines);
    }
    else if (e_option) {
        node = rb_ast_parse_str(rb_e_script, keep_script_lines);
    }
    else {
        node = rb_ast_parse_file(path, keep_script_lines);
    }

    return node_find(node, node_id);
}

static VALUE
rb_ast_node_alloc(VALUE klass)
{
    struct ASTNodeData *data;
    VALUE obj = TypedData_Make_Struct(klass, struct ASTNodeData, &rb_node_type, data);

    return obj;
}

static const char*
node_type_to_str(const NODE *node)
{
    return (ruby_node_name(nd_type(node)) + rb_strlen_lit("NODE_"));
}

static VALUE
ast_node_type(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return rb_sym_intern_ascii_cstr(node_type_to_str(data->node));
}

static VALUE
ast_node_node_id(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2FIX(nd_node_id(data->node));
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
dump_block(rb_ast_t *ast, const NODE *node)
{
    VALUE ary = rb_ary_new();
    do {
        rb_ary_push(ary, NEW_CHILD(ast, node->nd_head));
    } while (node->nd_next &&
        nd_type_p(node->nd_next, NODE_BLOCK) &&
        (node = node->nd_next, 1));
    if (node->nd_next) {
        rb_ary_push(ary, NEW_CHILD(ast, node->nd_next));
    }

    return ary;
}

static VALUE
dump_array(rb_ast_t *ast, const NODE *node)
{
    VALUE ary = rb_ary_new();
    rb_ary_push(ary, NEW_CHILD(ast, node->nd_head));

    while (node->nd_next && nd_type_p(node->nd_next, NODE_LIST)) {
        node = node->nd_next;
        rb_ary_push(ary, NEW_CHILD(ast, node->nd_head));
    }
    rb_ary_push(ary, NEW_CHILD(ast, node->nd_next));

    return ary;
}

static VALUE
var_name(ID id)
{
    if (!id) return Qnil;
    if (!rb_id2str(id)) return Qnil;
    return ID2SYM(id);
}

static VALUE
no_name_rest(void)
{
    ID rest;
    CONST_ID(rest, "NODE_SPECIAL_NO_NAME_REST");
    return ID2SYM(rest);
}

static VALUE
rest_arg(rb_ast_t *ast, const NODE *rest_arg)
{
    return NODE_NAMED_REST_P(rest_arg) ? NEW_CHILD(ast, rest_arg) : no_name_rest();
}

static VALUE
node_children(rb_ast_t *ast, const NODE *node)
{
    char name[DECIMAL_SIZE_OF_BITS(sizeof(long) * CHAR_BIT) + 2]; /* including '$' */

    enum node_type type = nd_type(node);
    switch (type) {
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
      case NODE_CASE3:
        return rb_ary_new_from_node_args(ast, 2, node->nd_head, node->nd_body);
      case NODE_WHEN:
        return rb_ary_new_from_node_args(ast, 3, node->nd_head, node->nd_body, node->nd_next);
      case NODE_IN:
        return rb_ary_new_from_node_args(ast, 3, node->nd_head, node->nd_body, node->nd_next);
      case NODE_WHILE:
      case NODE_UNTIL:
        return rb_ary_push(rb_ary_new_from_node_args(ast, 2, node->nd_cond, node->nd_body),
                           RBOOL(node->nd_state));
      case NODE_ITER:
      case NODE_FOR:
        return rb_ary_new_from_node_args(ast, 2, node->nd_iter, node->nd_body);
      case NODE_FOR_MASGN:
        return rb_ary_new_from_node_args(ast, 1, node->nd_var);
      case NODE_BREAK:
      case NODE_NEXT:
      case NODE_RETURN:
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
      case NODE_OR:
        {
            VALUE ary = rb_ary_new();

            while (1) {
                rb_ary_push(ary, NEW_CHILD(ast, node->nd_1st));
                if (!node->nd_2nd || !nd_type_p(node->nd_2nd, type))
                    break;
                node = node->nd_2nd;
            }
            rb_ary_push(ary, NEW_CHILD(ast, node->nd_2nd));
            return ary;
        }
      case NODE_MASGN:
        if (NODE_NAMED_REST_P(node->nd_args)) {
            return rb_ary_new_from_node_args(ast, 3, node->nd_value, node->nd_head, node->nd_args);
        }
        else {
            return rb_ary_new_from_args(3, NEW_CHILD(ast, node->nd_value),
                                        NEW_CHILD(ast, node->nd_head),
                                        no_name_rest());
        }
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_IASGN:
      case NODE_CVASGN:
      case NODE_GASGN:
        if (NODE_REQUIRED_KEYWORD_P(node)) {
            return rb_ary_new_from_args(2, var_name(node->nd_vid), ID2SYM(rb_intern("NODE_SPECIAL_REQUIRED_KEYWORD")));
        }
        return rb_ary_new_from_args(2, var_name(node->nd_vid), NEW_CHILD(ast, node->nd_value));
      case NODE_CDECL:
        if (node->nd_vid) {
            return rb_ary_new_from_args(2, ID2SYM(node->nd_vid), NEW_CHILD(ast, node->nd_value));
        }
        return rb_ary_new_from_args(3, NEW_CHILD(ast, node->nd_else), ID2SYM(node->nd_else->nd_mid), NEW_CHILD(ast, node->nd_value));
      case NODE_OP_ASGN1:
        return rb_ary_new_from_args(4, NEW_CHILD(ast, node->nd_recv),
                                    ID2SYM(node->nd_mid),
                                    NEW_CHILD(ast, node->nd_args->nd_head),
                                    NEW_CHILD(ast, node->nd_args->nd_body));
      case NODE_OP_ASGN2:
        return rb_ary_new_from_args(5, NEW_CHILD(ast, node->nd_recv),
                                    RBOOL(node->nd_next->nd_aid),
                                    ID2SYM(node->nd_next->nd_vid),
                                    ID2SYM(node->nd_next->nd_mid),
                                    NEW_CHILD(ast, node->nd_value));
      case NODE_OP_ASGN_AND:
        return rb_ary_new_from_args(3, NEW_CHILD(ast, node->nd_head), ID2SYM(idANDOP),
                                    NEW_CHILD(ast, node->nd_value));
      case NODE_OP_ASGN_OR:
        return rb_ary_new_from_args(3, NEW_CHILD(ast, node->nd_head), ID2SYM(idOROP),
                                    NEW_CHILD(ast, node->nd_value));
      case NODE_OP_CDECL:
        return rb_ary_new_from_args(3, NEW_CHILD(ast, node->nd_head),
                                    ID2SYM(node->nd_aid),
                                    NEW_CHILD(ast, node->nd_value));
      case NODE_CALL:
      case NODE_OPCALL:
      case NODE_QCALL:
        return rb_ary_new_from_args(3, NEW_CHILD(ast, node->nd_recv),
                                    ID2SYM(node->nd_mid),
                                    NEW_CHILD(ast, node->nd_args));
      case NODE_FCALL:
        return rb_ary_new_from_args(2, ID2SYM(node->nd_mid),
                                    NEW_CHILD(ast, node->nd_args));
      case NODE_VCALL:
        return rb_ary_new_from_args(1, ID2SYM(node->nd_mid));
      case NODE_SUPER:
        return rb_ary_new_from_node_args(ast, 1, node->nd_args);
      case NODE_ZSUPER:
        return rb_ary_new_from_node_args(ast, 0);
      case NODE_LIST:
      case NODE_VALUES:
        return dump_array(ast, node);
      case NODE_ZLIST:
        return rb_ary_new_from_node_args(ast, 0);
      case NODE_HASH:
        return rb_ary_new_from_node_args(ast, 1, node->nd_head);
      case NODE_YIELD:
        return rb_ary_new_from_node_args(ast, 1, node->nd_head);
      case NODE_LVAR:
      case NODE_DVAR:
        return rb_ary_new_from_args(1, var_name(node->nd_vid));
      case NODE_IVAR:
      case NODE_CONST:
      case NODE_CVAR:
      case NODE_GVAR:
        return rb_ary_new_from_args(1, ID2SYM(node->nd_vid));
      case NODE_NTH_REF:
        snprintf(name, sizeof(name), "$%ld", node->nd_nth);
        return rb_ary_new_from_args(1, ID2SYM(rb_intern(name)));
      case NODE_BACK_REF:
        name[0] = '$';
        name[1] = (char)node->nd_nth;
        name[2] = '\0';
        return rb_ary_new_from_args(1, ID2SYM(rb_intern(name)));
      case NODE_MATCH2:
        if (node->nd_args) {
            return rb_ary_new_from_node_args(ast, 3, node->nd_recv, node->nd_value, node->nd_args);
        }
        return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_value);
      case NODE_MATCH3:
        return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_value);
      case NODE_MATCH:
      case NODE_LIT:
      case NODE_STR:
      case NODE_XSTR:
        return rb_ary_new_from_args(1, node->nd_lit);
      case NODE_ONCE:
        return rb_ary_new_from_node_args(ast, 1, node->nd_body);
      case NODE_DSTR:
      case NODE_DXSTR:
      case NODE_DREGX:
      case NODE_DSYM:
        {
            NODE *n = node->nd_next;
            VALUE head = Qnil, next = Qnil;
            if (n) {
                head = NEW_CHILD(ast, n->nd_head);
                next = NEW_CHILD(ast, n->nd_next);
            }
            return rb_ary_new_from_args(3, node->nd_lit, head, next);
        }
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
        return rb_ary_new_from_args(2, ID2SYM(node->nd_mid), NEW_CHILD(ast, node->nd_defn));
      case NODE_DEFS:
        return rb_ary_new_from_args(3, NEW_CHILD(ast, node->nd_recv), ID2SYM(node->nd_mid), NEW_CHILD(ast, node->nd_defn));
      case NODE_ALIAS:
        return rb_ary_new_from_node_args(ast, 2, node->nd_1st, node->nd_2nd);
      case NODE_VALIAS:
        return rb_ary_new_from_args(2, ID2SYM(node->nd_alias), ID2SYM(node->nd_orig));
      case NODE_UNDEF:
        return rb_ary_new_from_node_args(ast, 1, node->nd_undef);
      case NODE_CLASS:
        return rb_ary_new_from_node_args(ast, 3, node->nd_cpath, node->nd_super, node->nd_body);
      case NODE_MODULE:
        return rb_ary_new_from_node_args(ast, 2, node->nd_cpath, node->nd_body);
      case NODE_SCLASS:
        return rb_ary_new_from_node_args(ast, 2, node->nd_recv, node->nd_body);
      case NODE_COLON2:
        return rb_ary_new_from_args(2, NEW_CHILD(ast, node->nd_head), ID2SYM(node->nd_mid));
      case NODE_COLON3:
        return rb_ary_new_from_args(1, ID2SYM(node->nd_mid));
      case NODE_DOT2:
      case NODE_DOT3:
      case NODE_FLIP2:
      case NODE_FLIP3:
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
        return rb_ary_new_from_args(3, NEW_CHILD(ast, node->nd_recv), ID2SYM(node->nd_mid), NEW_CHILD(ast, node->nd_args));
      case NODE_LAMBDA:
        return rb_ary_new_from_node_args(ast, 1, node->nd_body);
      case NODE_OPT_ARG:
        return rb_ary_new_from_node_args(ast, 2, node->nd_body, node->nd_next);
      case NODE_KW_ARG:
        return rb_ary_new_from_node_args(ast, 2, node->nd_body, node->nd_next);
      case NODE_POSTARG:
        if (NODE_NAMED_REST_P(node->nd_1st)) {
            return rb_ary_new_from_node_args(ast, 2, node->nd_1st, node->nd_2nd);
        }
        return rb_ary_new_from_args(2, no_name_rest(),
                                    NEW_CHILD(ast, node->nd_2nd));
      case NODE_ARGS:
        {
            struct rb_args_info *ainfo = node->nd_ainfo;
            return rb_ary_new_from_args(10,
                                        INT2NUM(ainfo->pre_args_num),
                                        NEW_CHILD(ast, ainfo->pre_init),
                                        NEW_CHILD(ast, ainfo->opt_args),
                                        var_name(ainfo->first_post_arg),
                                        INT2NUM(ainfo->post_args_num),
                                        NEW_CHILD(ast, ainfo->post_init),
                                        (ainfo->rest_arg == NODE_SPECIAL_EXCESSIVE_COMMA
                                            ? ID2SYM(rb_intern("NODE_SPECIAL_EXCESSIVE_COMMA"))
                                            : var_name(ainfo->rest_arg)),
                                        (ainfo->no_kwarg ? Qfalse : NEW_CHILD(ast, ainfo->kw_args)),
                                        (ainfo->no_kwarg ? Qfalse : NEW_CHILD(ast, ainfo->kw_rest_arg)),
                                        var_name(ainfo->block_arg));
        }
      case NODE_SCOPE:
        {
            rb_ast_id_table_t *tbl = node->nd_tbl;
            int i, size = tbl ? tbl->size : 0;
            VALUE locals = rb_ary_new_capa(size);
            for (i = 0; i < size; i++) {
                rb_ary_push(locals, var_name(tbl->ids[i]));
            }
            return rb_ary_new_from_args(3, locals, NEW_CHILD(ast, node->nd_args), NEW_CHILD(ast, node->nd_body));
        }
      case NODE_ARYPTN:
        {
            struct rb_ary_pattern_info *apinfo = node->nd_apinfo;
            VALUE rest = rest_arg(ast, apinfo->rest_arg);
            return rb_ary_new_from_args(4,
                                        NEW_CHILD(ast, node->nd_pconst),
                                        NEW_CHILD(ast, apinfo->pre_args),
                                        rest,
                                        NEW_CHILD(ast, apinfo->post_args));
        }
      case NODE_FNDPTN:
        {
            struct rb_fnd_pattern_info *fpinfo = node->nd_fpinfo;
            VALUE pre_rest = rest_arg(ast, fpinfo->pre_rest_arg);
            VALUE post_rest = rest_arg(ast, fpinfo->post_rest_arg);
            return rb_ary_new_from_args(4,
                                        NEW_CHILD(ast, node->nd_pconst),
                                        pre_rest,
                                        NEW_CHILD(ast, fpinfo->args),
                                        post_rest);
        }
      case NODE_HSHPTN:
        {
            VALUE kwrest = node->nd_pkwrestarg == NODE_SPECIAL_NO_REST_KEYWORD ? ID2SYM(rb_intern("NODE_SPECIAL_NO_REST_KEYWORD")) :
                                                                                 NEW_CHILD(ast, node->nd_pkwrestarg);

            return rb_ary_new_from_args(3,
                                        NEW_CHILD(ast, node->nd_pconst),
                                        NEW_CHILD(ast, node->nd_pkwargs),
                                        kwrest);
        }
      case NODE_ARGS_AUX:
      case NODE_LAST:
        break;
    }

    rb_bug("node_children: unknown node: %s", ruby_node_name(type));
}

static VALUE
ast_node_children(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return node_children(data->ast, data->node);
}

static VALUE
ast_node_first_lineno(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(nd_first_lineno(data->node));
}

static VALUE
ast_node_first_column(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(nd_first_column(data->node));
}

static VALUE
ast_node_last_lineno(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(nd_last_lineno(data->node));
}

static VALUE
ast_node_last_column(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(nd_last_column(data->node));
}

static VALUE
ast_node_inspect(rb_execution_context_t *ec, VALUE self)
{
    VALUE str;
    VALUE cname;
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    cname = rb_class_path(rb_obj_class(self));
    str = rb_str_new2("#<");

    rb_str_append(str, cname);
    rb_str_catf(str, ":%s@%d:%d-%d:%d>",
                node_type_to_str(data->node),
                nd_first_lineno(data->node), nd_first_column(data->node),
                nd_last_lineno(data->node), nd_last_column(data->node));

    return str;
}

static VALUE
ast_node_script_lines(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);
    VALUE ret = data->ast->body.script_lines;
    if (!RB_TYPE_P(ret, T_ARRAY)) return Qnil;
    return ret;
}

#include "ast.rbinc"

void
Init_ast(void)
{
    rb_mAST = rb_define_module_under(rb_cRubyVM, "AbstractSyntaxTree");
    rb_cNode = rb_define_class_under(rb_mAST, "Node", rb_cObject);
    rb_undef_alloc_func(rb_cNode);
}
