/* indent-tabs-mode: nil */
#include "internal.h"
#include "internal/ruby_parser.h"
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
    VALUE vast;
    const NODE *node;
};

static void
node_gc_mark(void *ptr)
{
    struct ASTNodeData *data = (struct ASTNodeData *)ptr;
    rb_gc_mark(data->vast);
}

static size_t
node_memsize(const void *ptr)
{
    struct ASTNodeData *data = (struct ASTNodeData *)ptr;
    rb_ast_t *ast = rb_ruby_ast_data_get(data->vast);

    return sizeof(struct ASTNodeData) + rb_ast_memsize(ast);
}

static const rb_data_type_t rb_node_type = {
    "AST/node",
    {node_gc_mark, RUBY_TYPED_DEFAULT_FREE, node_memsize,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE rb_ast_node_alloc(VALUE klass);

static void
setup_node(VALUE obj, VALUE vast, const NODE *node)
{
    struct ASTNodeData *data;

    TypedData_Get_Struct(obj, struct ASTNodeData, &rb_node_type, data);
    data->vast = vast;
    data->node = node;
}

static VALUE
ast_new_internal(VALUE vast, const NODE *node)
{
    VALUE obj;

    obj = rb_ast_node_alloc(rb_cNode);
    setup_node(obj, vast, node);

    return obj;
}

static VALUE rb_ast_parse_str(VALUE str, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens);
static VALUE rb_ast_parse_file(VALUE path, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens);

static VALUE
ast_parse_new(void)
{
    return rb_parser_set_context(rb_parser_new(), NULL, 0);
}

static VALUE
ast_parse_done(VALUE vast)
{
    rb_ast_t *ast = rb_ruby_ast_data_get(vast);

    if (!ast->body.root) {
        rb_ast_dispose(ast);
        rb_exc_raise(GET_EC()->errinfo);
    }

    return ast_new_internal(vast, (NODE *)ast->body.root);
}

static VALUE
ast_s_parse(rb_execution_context_t *ec, VALUE module, VALUE str, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    return rb_ast_parse_str(str, keep_script_lines, error_tolerant, keep_tokens);
}

static VALUE
rb_ast_parse_str(VALUE str, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    VALUE vast;

    StringValue(str);
    VALUE vparser = ast_parse_new();
    if (RTEST(keep_script_lines)) rb_parser_set_script_lines(vparser);
    if (RTEST(error_tolerant)) rb_parser_error_tolerant(vparser);
    if (RTEST(keep_tokens)) rb_parser_keep_tokens(vparser);
    vast = rb_parser_compile_string_path(vparser, Qnil, str, 1);
    return ast_parse_done(vast);
}

static VALUE
ast_s_parse_file(rb_execution_context_t *ec, VALUE module, VALUE path, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    return rb_ast_parse_file(path, keep_script_lines, error_tolerant, keep_tokens);
}

static VALUE
rb_ast_parse_file(VALUE path, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    VALUE f;
    VALUE vast = Qnil;
    rb_encoding *enc = rb_utf8_encoding();

    f = rb_file_open_str(path, "r");
    rb_funcall(f, rb_intern("set_encoding"), 2, rb_enc_from_encoding(enc), rb_str_new_cstr("-"));
    VALUE vparser = ast_parse_new();
    if (RTEST(keep_script_lines)) rb_parser_set_script_lines(vparser);
    if (RTEST(error_tolerant))  rb_parser_error_tolerant(vparser);
    if (RTEST(keep_tokens))  rb_parser_keep_tokens(vparser);
    vast = rb_parser_compile_file_path(vparser, Qnil, f, 1);
    rb_io_close(f);
    return ast_parse_done(vast);
}

static VALUE
rb_ast_parse_array(VALUE array, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    VALUE vast = Qnil;

    array = rb_check_array_type(array);
    VALUE vparser = ast_parse_new();
    if (RTEST(keep_script_lines)) rb_parser_set_script_lines(vparser);
    if (RTEST(error_tolerant)) rb_parser_error_tolerant(vparser);
    if (RTEST(keep_tokens)) rb_parser_keep_tokens(vparser);
    vast = rb_parser_compile_array(vparser, Qnil, array, 1);
    return ast_parse_done(vast);
}

static VALUE node_children(VALUE, const NODE*);

static VALUE
node_find(VALUE self, const int node_id)
{
    VALUE ary;
    long i;
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    if (nd_node_id(data->node) == node_id) return self;

    ary = node_children(data->vast, data->node);

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
node_id_for_backtrace_location(rb_execution_context_t *ec, VALUE module, VALUE location)
{
    int node_id;

    if (!rb_frame_info_p(location)) {
        rb_raise(rb_eTypeError, "Thread::Backtrace::Location object expected");
    }

    node_id = rb_get_node_id_from_frame_info(location);
    if (node_id == -1) {
        return Qnil;
    }

    return INT2NUM(node_id);
}

static VALUE
ast_s_of(rb_execution_context_t *ec, VALUE module, VALUE body, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
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
            node_id = ISEQ_BODY(iseq)->location.node_id;
        }
    }

    if (!iseq) {
        return Qnil;
    }

    if (ISEQ_BODY(iseq)->prism) {
        rb_raise(rb_eRuntimeError, "cannot get AST for ISEQ compiled by prism");
    }

    lines = ISEQ_BODY(iseq)->variable.script_lines;

    VALUE path = rb_iseq_path(iseq);
    int e_option = RSTRING_LEN(path) == 2 && memcmp(RSTRING_PTR(path), "-e", 2) == 0;

    if (NIL_P(lines) && rb_iseq_from_eval_p(iseq) && !e_option) {
        rb_raise(rb_eArgError, "cannot get AST for method defined in eval");
    }

    if (!NIL_P(lines)) {
        node = rb_ast_parse_array(lines, keep_script_lines, error_tolerant, keep_tokens);
    }
    else if (e_option) {
        node = rb_ast_parse_str(rb_e_script, keep_script_lines, error_tolerant, keep_tokens);
    }
    else {
        node = rb_ast_parse_file(path, keep_script_lines, error_tolerant, keep_tokens);
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

#define NEW_CHILD(vast, node) (node ? ast_new_internal(vast, node) : Qnil)

static VALUE
rb_ary_new_from_node_args(VALUE vast, long n, ...)
{
    va_list ar;
    VALUE ary;
    long i;

    ary = rb_ary_new2(n);

    va_start(ar, n);
    for (i=0; i<n; i++) {
        NODE *node;
        node = va_arg(ar, NODE *);
        rb_ary_push(ary, NEW_CHILD(vast, node));
    }
    va_end(ar);
    return ary;
}

static VALUE
dump_block(VALUE vast, const struct RNode_BLOCK *node)
{
    VALUE ary = rb_ary_new();
    do {
        rb_ary_push(ary, NEW_CHILD(vast, node->nd_head));
    } while (node->nd_next &&
        nd_type_p(node->nd_next, NODE_BLOCK) &&
        (node = RNODE_BLOCK(node->nd_next), 1));
    if (node->nd_next) {
        rb_ary_push(ary, NEW_CHILD(vast, node->nd_next));
    }

    return ary;
}

static VALUE
dump_array(VALUE vast, const struct RNode_LIST *node)
{
    VALUE ary = rb_ary_new();
    rb_ary_push(ary, NEW_CHILD(vast, node->nd_head));

    while (node->nd_next && nd_type_p(node->nd_next, NODE_LIST)) {
        node = RNODE_LIST(node->nd_next);
        rb_ary_push(ary, NEW_CHILD(vast, node->nd_head));
    }
    rb_ary_push(ary, NEW_CHILD(vast, node->nd_next));

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
rest_arg(VALUE vast, const NODE *rest_arg)
{
    return NODE_NAMED_REST_P(rest_arg) ? NEW_CHILD(vast, rest_arg) : no_name_rest();
}

static VALUE
node_children(VALUE vast, const NODE *node)
{
    char name[sizeof("$") + DECIMAL_SIZE_OF(long)];

    enum node_type type = nd_type(node);
    switch (type) {
      case NODE_BLOCK:
        return dump_block(vast, RNODE_BLOCK(node));
      case NODE_IF:
        return rb_ary_new_from_node_args(vast, 3, RNODE_IF(node)->nd_cond, RNODE_IF(node)->nd_body, RNODE_IF(node)->nd_else);
      case NODE_UNLESS:
        return rb_ary_new_from_node_args(vast, 3, RNODE_UNLESS(node)->nd_cond, RNODE_UNLESS(node)->nd_body, RNODE_UNLESS(node)->nd_else);
      case NODE_CASE:
        return rb_ary_new_from_node_args(vast, 2, RNODE_CASE(node)->nd_head, RNODE_CASE(node)->nd_body);
      case NODE_CASE2:
        return rb_ary_new_from_node_args(vast, 2, RNODE_CASE2(node)->nd_head, RNODE_CASE2(node)->nd_body);
      case NODE_CASE3:
        return rb_ary_new_from_node_args(vast, 2, RNODE_CASE3(node)->nd_head, RNODE_CASE3(node)->nd_body);
      case NODE_WHEN:
        return rb_ary_new_from_node_args(vast, 3, RNODE_WHEN(node)->nd_head, RNODE_WHEN(node)->nd_body, RNODE_WHEN(node)->nd_next);
      case NODE_IN:
        return rb_ary_new_from_node_args(vast, 3, RNODE_IN(node)->nd_head, RNODE_IN(node)->nd_body, RNODE_IN(node)->nd_next);
      case NODE_WHILE:
      case NODE_UNTIL:
        return rb_ary_push(rb_ary_new_from_node_args(vast, 2, RNODE_WHILE(node)->nd_cond, RNODE_WHILE(node)->nd_body),
                           RBOOL(RNODE_WHILE(node)->nd_state));
      case NODE_ITER:
      case NODE_FOR:
        return rb_ary_new_from_node_args(vast, 2, RNODE_ITER(node)->nd_iter, RNODE_ITER(node)->nd_body);
      case NODE_FOR_MASGN:
        return rb_ary_new_from_node_args(vast, 1, RNODE_FOR_MASGN(node)->nd_var);
      case NODE_BREAK:
        return rb_ary_new_from_node_args(vast, 1, RNODE_BREAK(node)->nd_stts);
      case NODE_NEXT:
        return rb_ary_new_from_node_args(vast, 1, RNODE_NEXT(node)->nd_stts);
      case NODE_RETURN:
        return rb_ary_new_from_node_args(vast, 1, RNODE_RETURN(node)->nd_stts);
      case NODE_REDO:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_RETRY:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_BEGIN:
        return rb_ary_new_from_node_args(vast, 1, RNODE_BEGIN(node)->nd_body);
      case NODE_RESCUE:
        return rb_ary_new_from_node_args(vast, 3, RNODE_RESCUE(node)->nd_head, RNODE_RESCUE(node)->nd_resq, RNODE_RESCUE(node)->nd_else);
      case NODE_RESBODY:
        return rb_ary_new_from_node_args(vast, 3, RNODE_RESBODY(node)->nd_args, RNODE_RESBODY(node)->nd_body, RNODE_RESBODY(node)->nd_next);
      case NODE_ENSURE:
        return rb_ary_new_from_node_args(vast, 2, RNODE_ENSURE(node)->nd_head, RNODE_ENSURE(node)->nd_ensr);
      case NODE_AND:
      case NODE_OR:
        {
            VALUE ary = rb_ary_new();

            while (1) {
                rb_ary_push(ary, NEW_CHILD(vast, RNODE_AND(node)->nd_1st));
                if (!RNODE_AND(node)->nd_2nd || !nd_type_p(RNODE_AND(node)->nd_2nd, type))
                    break;
                node = RNODE_AND(node)->nd_2nd;
            }
            rb_ary_push(ary, NEW_CHILD(vast, RNODE_AND(node)->nd_2nd));
            return ary;
        }
      case NODE_MASGN:
        if (NODE_NAMED_REST_P(RNODE_MASGN(node)->nd_args)) {
            return rb_ary_new_from_node_args(vast, 3, RNODE_MASGN(node)->nd_value, RNODE_MASGN(node)->nd_head, RNODE_MASGN(node)->nd_args);
        }
        else {
            return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_MASGN(node)->nd_value),
                                        NEW_CHILD(vast, RNODE_MASGN(node)->nd_head),
                                        no_name_rest());
        }
      case NODE_LASGN:
        if (NODE_REQUIRED_KEYWORD_P(RNODE_LASGN(node)->nd_value)) {
            return rb_ary_new_from_args(2, var_name(RNODE_LASGN(node)->nd_vid), ID2SYM(rb_intern("NODE_SPECIAL_REQUIRED_KEYWORD")));
        }
        return rb_ary_new_from_args(2, var_name(RNODE_LASGN(node)->nd_vid), NEW_CHILD(vast, RNODE_LASGN(node)->nd_value));
      case NODE_DASGN:
        if (NODE_REQUIRED_KEYWORD_P(RNODE_DASGN(node)->nd_value)) {
            return rb_ary_new_from_args(2, var_name(RNODE_DASGN(node)->nd_vid), ID2SYM(rb_intern("NODE_SPECIAL_REQUIRED_KEYWORD")));
        }
        return rb_ary_new_from_args(2, var_name(RNODE_DASGN(node)->nd_vid), NEW_CHILD(vast, RNODE_DASGN(node)->nd_value));
      case NODE_IASGN:
        return rb_ary_new_from_args(2, var_name(RNODE_IASGN(node)->nd_vid), NEW_CHILD(vast, RNODE_IASGN(node)->nd_value));
      case NODE_CVASGN:
        return rb_ary_new_from_args(2, var_name(RNODE_CVASGN(node)->nd_vid), NEW_CHILD(vast, RNODE_CVASGN(node)->nd_value));
      case NODE_GASGN:
        return rb_ary_new_from_args(2, var_name(RNODE_GASGN(node)->nd_vid), NEW_CHILD(vast, RNODE_GASGN(node)->nd_value));
      case NODE_CDECL:
        if (RNODE_CDECL(node)->nd_vid) {
            return rb_ary_new_from_args(2, ID2SYM(RNODE_CDECL(node)->nd_vid), NEW_CHILD(vast, RNODE_CDECL(node)->nd_value));
        }
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_CDECL(node)->nd_else), ID2SYM(RNODE_COLON2(RNODE_CDECL(node)->nd_else)->nd_mid), NEW_CHILD(vast, RNODE_CDECL(node)->nd_value));
      case NODE_OP_ASGN1:
        return rb_ary_new_from_args(4, NEW_CHILD(vast, RNODE_OP_ASGN1(node)->nd_recv),
                                    ID2SYM(RNODE_OP_ASGN1(node)->nd_mid),
                                    NEW_CHILD(vast, RNODE_OP_ASGN1(node)->nd_index),
                                    NEW_CHILD(vast, RNODE_OP_ASGN1(node)->nd_rvalue));
      case NODE_OP_ASGN2:
        return rb_ary_new_from_args(5, NEW_CHILD(vast, RNODE_OP_ASGN2(node)->nd_recv),
                                    RBOOL(RNODE_OP_ASGN2(node)->nd_aid),
                                    ID2SYM(RNODE_OP_ASGN2(node)->nd_vid),
                                    ID2SYM(RNODE_OP_ASGN2(node)->nd_mid),
                                    NEW_CHILD(vast, RNODE_OP_ASGN2(node)->nd_value));
      case NODE_OP_ASGN_AND:
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_OP_ASGN_AND(node)->nd_head), ID2SYM(idANDOP),
                                    NEW_CHILD(vast, RNODE_OP_ASGN_AND(node)->nd_value));
      case NODE_OP_ASGN_OR:
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_OP_ASGN_OR(node)->nd_head), ID2SYM(idOROP),
                                    NEW_CHILD(vast, RNODE_OP_ASGN_OR(node)->nd_value));
      case NODE_OP_CDECL:
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_OP_CDECL(node)->nd_head),
                                    ID2SYM(RNODE_OP_CDECL(node)->nd_aid),
                                    NEW_CHILD(vast, RNODE_OP_CDECL(node)->nd_value));
      case NODE_CALL:
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_CALL(node)->nd_recv),
                                    ID2SYM(RNODE_CALL(node)->nd_mid),
                                    NEW_CHILD(vast, RNODE_CALL(node)->nd_args));
      case NODE_OPCALL:
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_OPCALL(node)->nd_recv),
                                    ID2SYM(RNODE_OPCALL(node)->nd_mid),
                                    NEW_CHILD(vast, RNODE_OPCALL(node)->nd_args));
      case NODE_QCALL:
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_QCALL(node)->nd_recv),
                                    ID2SYM(RNODE_QCALL(node)->nd_mid),
                                    NEW_CHILD(vast, RNODE_QCALL(node)->nd_args));
      case NODE_FCALL:
        return rb_ary_new_from_args(2, ID2SYM(RNODE_FCALL(node)->nd_mid),
                                    NEW_CHILD(vast, RNODE_FCALL(node)->nd_args));
      case NODE_VCALL:
        return rb_ary_new_from_args(1, ID2SYM(RNODE_VCALL(node)->nd_mid));
      case NODE_SUPER:
        return rb_ary_new_from_node_args(vast, 1, RNODE_SUPER(node)->nd_args);
      case NODE_ZSUPER:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_LIST:
        return dump_array(vast, RNODE_LIST(node));
      case NODE_ZLIST:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_HASH:
        return rb_ary_new_from_node_args(vast, 1, RNODE_HASH(node)->nd_head);
      case NODE_YIELD:
        return rb_ary_new_from_node_args(vast, 1, RNODE_YIELD(node)->nd_head);
      case NODE_LVAR:
        return rb_ary_new_from_args(1, var_name(RNODE_LVAR(node)->nd_vid));
      case NODE_DVAR:
        return rb_ary_new_from_args(1, var_name(RNODE_DVAR(node)->nd_vid));
      case NODE_IVAR:
        return rb_ary_new_from_args(1, ID2SYM(RNODE_IVAR(node)->nd_vid));
      case NODE_CONST:
        return rb_ary_new_from_args(1, ID2SYM(RNODE_CONST(node)->nd_vid));
      case NODE_CVAR:
        return rb_ary_new_from_args(1, ID2SYM(RNODE_CVAR(node)->nd_vid));
      case NODE_GVAR:
        return rb_ary_new_from_args(1, ID2SYM(RNODE_GVAR(node)->nd_vid));
      case NODE_NTH_REF:
        snprintf(name, sizeof(name), "$%ld", RNODE_NTH_REF(node)->nd_nth);
        return rb_ary_new_from_args(1, ID2SYM(rb_intern(name)));
      case NODE_BACK_REF:
        name[0] = '$';
        name[1] = (char)RNODE_BACK_REF(node)->nd_nth;
        name[2] = '\0';
        return rb_ary_new_from_args(1, ID2SYM(rb_intern(name)));
      case NODE_MATCH:
        return rb_ary_new_from_args(1, rb_node_regx_string_val(node));
      case NODE_MATCH2:
        if (RNODE_MATCH2(node)->nd_args) {
            return rb_ary_new_from_node_args(vast, 3, RNODE_MATCH2(node)->nd_recv, RNODE_MATCH2(node)->nd_value, RNODE_MATCH2(node)->nd_args);
        }
        return rb_ary_new_from_node_args(vast, 2, RNODE_MATCH2(node)->nd_recv, RNODE_MATCH2(node)->nd_value);
      case NODE_MATCH3:
        return rb_ary_new_from_node_args(vast, 2, RNODE_MATCH3(node)->nd_recv, RNODE_MATCH3(node)->nd_value);
      case NODE_STR:
      case NODE_XSTR:
        return rb_ary_new_from_args(1, rb_node_str_string_val(node));
      case NODE_INTEGER:
        return rb_ary_new_from_args(1, rb_node_integer_literal_val(node));
      case NODE_FLOAT:
        return rb_ary_new_from_args(1, rb_node_float_literal_val(node));
      case NODE_RATIONAL:
        return rb_ary_new_from_args(1, rb_node_rational_literal_val(node));
      case NODE_IMAGINARY:
        return rb_ary_new_from_args(1, rb_node_imaginary_literal_val(node));
      case NODE_REGX:
        return rb_ary_new_from_args(1, rb_node_regx_string_val(node));
      case NODE_ONCE:
        return rb_ary_new_from_node_args(vast, 1, RNODE_ONCE(node)->nd_body);
      case NODE_DSTR:
      case NODE_DXSTR:
      case NODE_DREGX:
      case NODE_DSYM:
        {
            struct RNode_LIST *n = RNODE_DSTR(node)->nd_next;
            VALUE head = Qnil, next = Qnil;
            if (n) {
                head = NEW_CHILD(vast, n->nd_head);
                next = NEW_CHILD(vast, n->nd_next);
            }
            return rb_ary_new_from_args(3, rb_node_dstr_string_val(node), head, next);
        }
      case NODE_SYM:
        return rb_ary_new_from_args(1, rb_node_sym_string_val(node));
      case NODE_EVSTR:
        return rb_ary_new_from_node_args(vast, 1, RNODE_EVSTR(node)->nd_body);
      case NODE_ARGSCAT:
        return rb_ary_new_from_node_args(vast, 2, RNODE_ARGSCAT(node)->nd_head, RNODE_ARGSCAT(node)->nd_body);
      case NODE_ARGSPUSH:
        return rb_ary_new_from_node_args(vast, 2, RNODE_ARGSPUSH(node)->nd_head, RNODE_ARGSPUSH(node)->nd_body);
      case NODE_SPLAT:
        return rb_ary_new_from_node_args(vast, 1, RNODE_SPLAT(node)->nd_head);
      case NODE_BLOCK_PASS:
        return rb_ary_new_from_node_args(vast, 2, RNODE_BLOCK_PASS(node)->nd_head, RNODE_BLOCK_PASS(node)->nd_body);
      case NODE_DEFN:
        return rb_ary_new_from_args(2, ID2SYM(RNODE_DEFN(node)->nd_mid), NEW_CHILD(vast, RNODE_DEFN(node)->nd_defn));
      case NODE_DEFS:
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_DEFS(node)->nd_recv), ID2SYM(RNODE_DEFS(node)->nd_mid), NEW_CHILD(vast, RNODE_DEFS(node)->nd_defn));
      case NODE_ALIAS:
        return rb_ary_new_from_node_args(vast, 2, RNODE_ALIAS(node)->nd_1st, RNODE_ALIAS(node)->nd_2nd);
      case NODE_VALIAS:
        return rb_ary_new_from_args(2, ID2SYM(RNODE_VALIAS(node)->nd_alias), ID2SYM(RNODE_VALIAS(node)->nd_orig));
      case NODE_UNDEF:
        return rb_ary_new_from_node_args(vast, 1, RNODE_UNDEF(node)->nd_undef);
      case NODE_CLASS:
        return rb_ary_new_from_node_args(vast, 3, RNODE_CLASS(node)->nd_cpath, RNODE_CLASS(node)->nd_super, RNODE_CLASS(node)->nd_body);
      case NODE_MODULE:
        return rb_ary_new_from_node_args(vast, 2, RNODE_MODULE(node)->nd_cpath, RNODE_MODULE(node)->nd_body);
      case NODE_SCLASS:
        return rb_ary_new_from_node_args(vast, 2, RNODE_SCLASS(node)->nd_recv, RNODE_SCLASS(node)->nd_body);
      case NODE_COLON2:
        return rb_ary_new_from_args(2, NEW_CHILD(vast, RNODE_COLON2(node)->nd_head), ID2SYM(RNODE_COLON2(node)->nd_mid));
      case NODE_COLON3:
        return rb_ary_new_from_args(1, ID2SYM(RNODE_COLON3(node)->nd_mid));
      case NODE_DOT2:
      case NODE_DOT3:
      case NODE_FLIP2:
      case NODE_FLIP3:
        return rb_ary_new_from_node_args(vast, 2, RNODE_DOT2(node)->nd_beg, RNODE_DOT2(node)->nd_end);
      case NODE_SELF:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_NIL:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_TRUE:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_FALSE:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_ERRINFO:
        return rb_ary_new_from_node_args(vast, 0);
      case NODE_DEFINED:
        return rb_ary_new_from_node_args(vast, 1, RNODE_DEFINED(node)->nd_head);
      case NODE_POSTEXE:
        return rb_ary_new_from_node_args(vast, 1, RNODE_POSTEXE(node)->nd_body);
      case NODE_ATTRASGN:
        return rb_ary_new_from_args(3, NEW_CHILD(vast, RNODE_ATTRASGN(node)->nd_recv), ID2SYM(RNODE_ATTRASGN(node)->nd_mid), NEW_CHILD(vast, RNODE_ATTRASGN(node)->nd_args));
      case NODE_LAMBDA:
        return rb_ary_new_from_node_args(vast, 1, RNODE_LAMBDA(node)->nd_body);
      case NODE_OPT_ARG:
        return rb_ary_new_from_node_args(vast, 2, RNODE_OPT_ARG(node)->nd_body, RNODE_OPT_ARG(node)->nd_next);
      case NODE_KW_ARG:
        return rb_ary_new_from_node_args(vast, 2, RNODE_KW_ARG(node)->nd_body, RNODE_KW_ARG(node)->nd_next);
      case NODE_POSTARG:
        if (NODE_NAMED_REST_P(RNODE_POSTARG(node)->nd_1st)) {
            return rb_ary_new_from_node_args(vast, 2, RNODE_POSTARG(node)->nd_1st, RNODE_POSTARG(node)->nd_2nd);
        }
        return rb_ary_new_from_args(2, no_name_rest(),
                                    NEW_CHILD(vast, RNODE_POSTARG(node)->nd_2nd));
      case NODE_ARGS:
        {
            struct rb_args_info *ainfo = &RNODE_ARGS(node)->nd_ainfo;
            return rb_ary_new_from_args(10,
                                        INT2NUM(ainfo->pre_args_num),
                                        NEW_CHILD(vast, ainfo->pre_init),
                                        NEW_CHILD(vast, (NODE *)ainfo->opt_args),
                                        var_name(ainfo->first_post_arg),
                                        INT2NUM(ainfo->post_args_num),
                                        NEW_CHILD(vast, ainfo->post_init),
                                        (ainfo->rest_arg == NODE_SPECIAL_EXCESSIVE_COMMA
                                            ? ID2SYM(rb_intern("NODE_SPECIAL_EXCESSIVE_COMMA"))
                                            : var_name(ainfo->rest_arg)),
                                        (ainfo->no_kwarg ? Qfalse : NEW_CHILD(vast, (NODE *)ainfo->kw_args)),
                                        (ainfo->no_kwarg ? Qfalse : NEW_CHILD(vast, ainfo->kw_rest_arg)),
                                        var_name(ainfo->block_arg));
        }
      case NODE_SCOPE:
        {
            rb_ast_id_table_t *tbl = RNODE_SCOPE(node)->nd_tbl;
            int i, size = tbl ? tbl->size : 0;
            VALUE locals = rb_ary_new_capa(size);
            for (i = 0; i < size; i++) {
                rb_ary_push(locals, var_name(tbl->ids[i]));
            }
            return rb_ary_new_from_args(3, locals, NEW_CHILD(vast, (NODE *)RNODE_SCOPE(node)->nd_args), NEW_CHILD(vast, RNODE_SCOPE(node)->nd_body));
        }
      case NODE_ARYPTN:
        {
            VALUE rest = rest_arg(vast, RNODE_ARYPTN(node)->rest_arg);
            return rb_ary_new_from_args(4,
                                        NEW_CHILD(vast, RNODE_ARYPTN(node)->nd_pconst),
                                        NEW_CHILD(vast, RNODE_ARYPTN(node)->pre_args),
                                        rest,
                                        NEW_CHILD(vast, RNODE_ARYPTN(node)->post_args));
        }
      case NODE_FNDPTN:
        {
            VALUE pre_rest = rest_arg(vast, RNODE_FNDPTN(node)->pre_rest_arg);
            VALUE post_rest = rest_arg(vast, RNODE_FNDPTN(node)->post_rest_arg);
            return rb_ary_new_from_args(4,
                                        NEW_CHILD(vast, RNODE_FNDPTN(node)->nd_pconst),
                                        pre_rest,
                                        NEW_CHILD(vast, RNODE_FNDPTN(node)->args),
                                        post_rest);
        }
      case NODE_HSHPTN:
        {
            VALUE kwrest = RNODE_HSHPTN(node)->nd_pkwrestarg == NODE_SPECIAL_NO_REST_KEYWORD ? ID2SYM(rb_intern("NODE_SPECIAL_NO_REST_KEYWORD")) :
                                                                                 NEW_CHILD(vast, RNODE_HSHPTN(node)->nd_pkwrestarg);

            return rb_ary_new_from_args(3,
                                        NEW_CHILD(vast, RNODE_HSHPTN(node)->nd_pconst),
                                        NEW_CHILD(vast, RNODE_HSHPTN(node)->nd_pkwargs),
                                        kwrest);
        }
      case NODE_LINE:
        return rb_ary_new_from_args(1, rb_node_line_lineno_val(node));
      case NODE_FILE:
        return rb_ary_new_from_args(1, rb_node_file_path_val(node));
      case NODE_ENCODING:
        return rb_ary_new_from_args(1, rb_node_encoding_val(node));
      case NODE_ERROR:
        return rb_ary_new_from_node_args(vast, 0);
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

    return node_children(data->vast, data->node);
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
ast_node_all_tokens(rb_execution_context_t *ec, VALUE self)
{
    long i;
    struct ASTNodeData *data;
    rb_ast_t *ast;
    rb_parser_ary_t *parser_tokens;
    rb_parser_ast_token_t *parser_token;
    VALUE str, loc, token, all_tokens;

    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);
    ast = rb_ruby_ast_data_get(data->vast);

    parser_tokens = ast->node_buffer->tokens;
    if (parser_tokens == NULL) {
        return Qnil;
    }

    all_tokens = rb_ary_new2(parser_tokens->len);
    for (i = 0; i < parser_tokens->len; i++) {
        parser_token = parser_tokens->data[i];
        str = rb_str_new(parser_token->str->ptr, parser_token->str->len);
        loc = rb_ary_new_from_args(4,
            INT2FIX(parser_token->loc.beg_pos.lineno),
            INT2FIX(parser_token->loc.beg_pos.column),
            INT2FIX(parser_token->loc.end_pos.lineno),
            INT2FIX(parser_token->loc.end_pos.column)
        );
        token = rb_ary_new_from_args(4, INT2FIX(parser_token->id), ID2SYM(rb_intern(parser_token->type_name)), str, loc);
        rb_ary_push(all_tokens, token);
    }
    rb_obj_freeze(all_tokens);

    return all_tokens;
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
    rb_ast_t *ast;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);
    ast = rb_ruby_ast_data_get(data->vast);
    rb_parser_ary_t *ret = ast->body.script_lines;
    return rb_parser_build_script_lines_from(ret);
}

#include "ast.rbinc"

void
Init_ast(void)
{
    rb_mAST = rb_define_module_under(rb_cRubyVM, "AbstractSyntaxTree");
    rb_cNode = rb_define_class_under(rb_mAST, "Node", rb_cObject);
    rb_undef_alloc_func(rb_cNode);
}
