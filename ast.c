/* indent-tabs-mode: nil */
#include "internal.h"
#include "internal/ruby_parser.h"
#include "internal/symbol.h"
#include "internal/warnings.h"
#include "iseq.h"
#include "node.h"
#include "symbol.h"
#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/util.h"
#include "vm_core.h"

#include "builtin.h"

static VALUE rb_mAST;
static VALUE rb_cNode;
static VALUE rb_cLocation;

/* Public nodes are lazy views of the generated tree.  Keep its owner alive for
 * every view, including synthetic nodes and slices of arena-owned node lists. */
struct ASTNodeData {
    VALUE ast_value;
    const rb_node_t *node;
    const rb_node_t *owner;
    const rb_node_list2_t *list;
    size_t index, count;
    enum node_type type;
    bool dynamic;
    rb_code_location_t location;
};

static void
node_gc_mark(void *ptr)
{
    struct ASTNodeData *data = (struct ASTNodeData *)ptr;
    rb_gc_mark(data->ast_value);
}

static size_t
node_memsize(const void *ptr)
{
    struct ASTNodeData *data = (struct ASTNodeData *)ptr;
    size_t size = sizeof(struct ASTNodeData);
    if (data->ast_value) {
        rb_ast_t *ast = rb_ruby_ast_data_get(data->ast_value);
        size += rb_ast_memsize(ast);
    }

    return size;
}

static const rb_data_type_t rb_node_type = {
    "AST/node",
    {node_gc_mark, RUBY_TYPED_DEFAULT_FREE, node_memsize,},
    0, 0,
    RUBY_TYPED_THREAD_SAFE_FREE,
};

struct ASTLocationData {
    int first_lineno;
    int first_column;
    int last_lineno;
    int last_column;
};

static void
location_gc_mark(void *ptr)
{
}

static size_t
location_memsize(const void *ptr)
{
    return sizeof(struct ASTLocationData);
}

static const rb_data_type_t rb_location_type = {
    "AST/location",
    {location_gc_mark, RUBY_TYPED_DEFAULT_FREE, location_memsize,},
    0, 0,
    RUBY_TYPED_THREAD_SAFE_FREE,
};


static VALUE rb_ast_node_alloc(VALUE klass);

static VALUE ast_new_internal(VALUE ast_value, const rb_node_t *node);
static VALUE ast_child(const struct ASTNodeData *parent, const rb_node_t *node);
static VALUE node_children(const struct ASTNodeData *data);
static VALUE ast_view(const struct ASTNodeData *parent, const rb_node_t *node, enum node_type type);
static VALUE owned_child(const struct ASTNodeData *, const rb_node_t *, const rb_node_t *);
static enum node_type call_type(const rb_call_node_t *);

static VALUE rb_ast_parse_str(VALUE str, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens);
static VALUE rb_ast_parse_file(VALUE path, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens);

static VALUE
ast_parse_new(void)
{
    return rb_parser_set_context(rb_parser_new(), NULL, 0);
}

static VALUE
ast_parse_done(VALUE ast_value)
{
    rb_ast_t *ast = rb_ruby_ast_data_get(ast_value);

    if (!ast->body.root) {
        rb_ast_dispose(ast);
        rb_exc_raise(GET_EC()->errinfo);
    }

    return ast_new_internal(ast_value, ast->body.root);
}

static VALUE
setup_vparser(VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    VALUE vparser = ast_parse_new();
    if (RTEST(keep_script_lines)) rb_parser_set_script_lines(vparser);
    if (RTEST(error_tolerant)) rb_parser_error_tolerant(vparser);
    if (RTEST(keep_tokens)) rb_parser_keep_tokens(vparser);
    return vparser;
}

static VALUE
ast_s_parse(rb_execution_context_t *ec, VALUE module, VALUE str, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    return rb_ast_parse_str(str, keep_script_lines, error_tolerant, keep_tokens);
}

static VALUE
rb_ast_parse_str(VALUE str, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    VALUE ast_value = Qnil;
    StringValue(str);
    VALUE vparser = setup_vparser(keep_script_lines, error_tolerant, keep_tokens);
    ast_value = rb_parser_compile_string_path(vparser, Qnil, str, 1);
    return ast_parse_done(ast_value);
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
    VALUE ast_value = Qnil;
    rb_encoding *enc = rb_utf8_encoding();

    f = rb_file_open_str(path, "r");
    rb_funcall(f, rb_intern("set_encoding"), 2, rb_enc_from_encoding(enc), rb_str_new_cstr("-"));
    VALUE vparser = setup_vparser(keep_script_lines, error_tolerant, keep_tokens);
    ast_value = rb_parser_compile_file_path(vparser, Qnil, f, 1);
    rb_io_close(f);
    return ast_parse_done(ast_value);
}

static VALUE
rb_ast_parse_array(VALUE array, VALUE keep_script_lines, VALUE error_tolerant, VALUE keep_tokens)
{
    VALUE ast_value = Qnil;

    array = rb_check_array_type(array);
    VALUE vparser = setup_vparser(keep_script_lines, error_tolerant, keep_tokens);
    ast_value = rb_parser_compile_array(vparser, Qnil, array, 1);
    return ast_parse_done(ast_value);
}

struct node_search {
    const rb_node_t *found;
    const rb_node_t *parent;
    int node_id;
    bool dynamic;
};

static bool
node_find_raw(const rb_node_t *node, void *opaque)
{
    struct node_search *search = opaque;
    if (node->node_id == search->node_id) {
        search->found = node;
        return true;
    }
    const rb_node_t *parent = search->parent;
    bool dynamic = search->dynamic;
    switch (RB_NODE_TYPE(node)) {
      case RB_BLOCK_NODE: case RB_LAMBDA_NODE: search->dynamic = true; break;
      case RB_PROGRAM_NODE: case RB_DEF_NODE: case RB_CLASS_NODE:
      case RB_MODULE_NODE: case RB_SINGLETON_CLASS_NODE: search->dynamic = false; break;
      default: break;
    }
    search->parent = node;
    if (rb_node_each_child(node, node_find_raw, search)) return true;
    search->parent = parent;
    search->dynamic = dynamic;
    return false;
}

static VALUE
node_find(VALUE self, int node_id)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);
    struct node_search search = {.node_id = node_id};
    if (!node_find_raw(data->node, &search)) return Qnil;
    struct ASTNodeData context = *data;
    context.dynamic = search.dynamic;
    if (search.found->type == RB_BLOCK_NODE && search.parent &&
        (search.parent->type == RB_CALL_NODE || search.parent->type == RB_SUPER_NODE ||
         search.parent->type == RB_FORWARDING_SUPER_NODE)) {
        return ast_child(&context, search.parent);
    }
    /* The call and its literal block have separate execution IDs, even though
     * the public tree nests both under an ITER view. */
    if (search.found->type == RB_CALL_NODE && RB_NODE_CALL(search.found)->block &&
        RB_NODE_CALL(search.found)->block->type == RB_BLOCK_NODE) {
        return ast_view(&context, search.found, call_type(RB_NODE_CALL(search.found)));
    }
    if (search.found->type == RB_SUPER_NODE && RB_NODE_SUPER(search.found)->block &&
        RB_NODE_SUPER(search.found)->block->type == RB_BLOCK_NODE) return ast_view(&context, search.found, NODE_SUPER);
    if (search.found->type == RB_FORWARDING_SUPER_NODE && RB_NODE_FORWARDING_SUPER(search.found)->block) return ast_view(&context, search.found, NODE_ZSUPER);
    return ast_child(&context, search.found);
}

bool
rb_ast_node_source_location(VALUE source, VALUE path, int first_lineno,
                            int node_id, bool block_iseq, int iseq_node_id,
                            rb_code_location_t *location)
{
    StringValue(source);
    VALUE vparser = setup_vparser(Qfalse, Qfalse, Qfalse);
    VALUE ast_value = rb_parser_compile_string_path(vparser, path, source, first_lineno);
    VALUE ast = ast_parse_done(ast_value);
    struct ASTNodeData *data;
    TypedData_Get_Struct(ast, struct ASTNodeData, &rb_node_type, data);
    struct node_search search = {.node_id = node_id};
    if (!node_find_raw(data->node, &search)) return false;
    *location = search.found->location;
    RB_GC_GUARD(ast);
    return true;
}

static VALUE
ast_node_find(rb_execution_context_t *ec, VALUE self, VALUE root, VALUE node_id)
{
    return node_find(root, NUM2INT(node_id));
}

static VALUE
ast_node_source_hash(rb_execution_context_t *ec, VALUE self, VALUE node)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(node, struct ASTNodeData, &rb_node_type, data);

    rb_ast_t *ast = rb_ruby_ast_data_get(data->ast_value);
    if (!ast->body.has_source_hash) return Qnil;
    return ULL2NUM(ast->body.source_hash);
}

extern VALUE rb_e_script;

static VALUE
iseq_compiled_by_prism_p(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(ISEQ_BODY(rb_iseqw_to_iseq(self))->prism);
}

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
iseq_of_backtrace_location(rb_execution_context_t *ec, VALUE module, VALUE location)
{
    if (!rb_frame_info_p(location)) {
        rb_raise(rb_eTypeError, "Thread::Backtrace::Location object expected");
    }

    const rb_iseq_t *iseq = rb_get_iseq_from_frame_info(location);
    if (!iseq) return Qnil;
    return rb_iseqw_new(iseq);
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

    lines = ISEQ_SCRIPT_LINES(iseq);

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

static VALUE
var_name(ID id)
{
    return id && rb_id2str(id) ? ID2SYM(id) : Qnil;
}

static VALUE
special_name(const char *name)
{
    return ID2SYM(rb_intern(name));
}

static VALUE
ast_view(const struct ASTNodeData *parent, const rb_node_t *node, enum node_type type)
{
    VALUE object = rb_ast_node_alloc(rb_cNode);
    struct ASTNodeData *data;
    TypedData_Get_Struct(object, struct ASTNodeData, &rb_node_type, data);
    *data = *parent;
    data->node = node;
    data->owner = parent->node == node ? parent->owner : node;
    data->list = NULL;
    data->index = data->count = 0;
    data->type = type;
    data->location = node->location;
    if (type == NODE_BEGIN && node->type == RB_BEGIN_NODE) data->location.end_pos = data->location.beg_pos;
    if (node->type == RB_CALL_NODE && type != NODE_ITER) {
        const rb_call_node_t *call = RB_NODE_CALL(node);
        if (type == NODE_BLOCK_PASS && call->block) {
            data->location = call->block->location;
            if (call->arguments) data->location.beg_pos = call->arguments->base.location.beg_pos;
        }
        if (call->block && call->block->type == RB_BLOCK_NODE) {
            if (!NULL_LOC_P(&call->closing_loc)) data->location.end_pos = call->closing_loc.end_pos;
            else if (call->arguments) data->location.end_pos = call->arguments->base.location.end_pos;
            else if (!NULL_LOC_P(&call->message_loc)) data->location.end_pos = call->message_loc.end_pos;
        }
    }
    switch (RB_NODE_TYPE(node)) {
      case RB_FORWARDING_ARGUMENTS_NODE:
        if (parent->node == node && (type == NODE_ARGSPUSH || type == NODE_ARGSCAT || type == NODE_BLOCK_PASS)) data->location = parent->location;
        break;
      case RB_INTERPOLATED_MATCH_LAST_LINE_NODE:
        if (type == NODE_MATCH2 || type == NODE_GVAR) data->location = RB_NODE_INTERPOLATED_MATCH_LAST_LINE(node)->implicit_call_loc;
        break;
      case RB_PRE_EXECUTION_NODE:
        data->location.beg_pos = RB_NODE_PRE_EXECUTION(node)->opening_loc.beg_pos;
        break;
      case RB_CONSTANT_PATH_TARGET_NODE:
        if (type == NODE_COLON2 || type == NODE_COLON3) {
            const rb_constant_path_target_node_t *target = RB_NODE_CONSTANT_PATH_TARGET(node);
            data->location.beg_pos = target->parent ? target->parent->location.beg_pos : target->delimiter_loc.beg_pos;
            data->location.end_pos = target->name_loc.end_pos;
        }
        break;
      case RB_INDEX_TARGET_NODE:
        if ((type == NODE_LIST || type == NODE_ARGSCAT) && RB_NODE_INDEX_TARGET(node)->arguments &&
            RB_NODE_INDEX_TARGET(node)->arguments->arguments.size) data->location.beg_pos = RB_NODE_INDEX_TARGET(node)->arguments->arguments.nodes[0]->location.beg_pos;
        break;
      case RB_FOR_NODE:
        if (type == NODE_ARGS || type == NODE_DVAR || type == NODE_FOR_MASGN || type == NODE_MASGN || type == NODE_LIST) data->location = RB_NODE_FOR(node)->index->location;
        break;
      case RB_BEGIN_NODE:
        if (type == NODE_BLOCK && RB_NODE_BEGIN(node)->statements) data->location.end_pos = RB_NODE_BEGIN(node)->statements->base.location.end_pos;
        if (type == NODE_RESCUE && RB_NODE_BEGIN(node)->ensure_clause) {
            const rb_begin_node_t *begin = RB_NODE_BEGIN(node);
            if (begin->else_clause && RB_NODE_ELSE(begin->else_clause)->statements) data->location.end_pos = RB_NODE_ELSE(begin->else_clause)->statements->base.location.end_pos;
            else if (begin->rescue_clause) data->location.end_pos = begin->rescue_clause->base.location.end_pos;
        }
        break;
      case RB_HASH_NODE: case RB_KEYWORD_HASH_NODE: case RB_HASH_PATTERN_NODE:
        if (type == NODE_LIST) {
            const rb_node_list2_t *elements = node->type == RB_HASH_NODE ? &RB_NODE_HASH(node)->elements :
                node->type == RB_KEYWORD_HASH_NODE ? &RB_NODE_KEYWORD_HASH(node)->elements : &RB_NODE_HASH_PATTERN(node)->elements;
            if (elements->size) {
                data->location.beg_pos = elements->nodes[0]->location.beg_pos;
                data->location.end_pos = elements->nodes[elements->size - 1]->location.end_pos;
            }
        }
        break;
      case RB_MATCH_REQUIRED_NODE: case RB_MATCH_PREDICATE_NODE:
        if (type != NODE_CASE3) data->location = RB_NODE_MATCH_REQUIRED(node)->pattern->location;
        break;
      case RB_RESCUE_MODIFIER_NODE:
        if (type == NODE_RESBODY) data->location.beg_pos = RB_NODE_RESCUE_MODIFIER(node)->keyword_loc.beg_pos;
        break;
      case RB_MULTI_TARGET_NODE: case RB_MULTI_WRITE_NODE:
        if (type == NODE_LVAR || type == NODE_DVAR) data->location.end_pos = data->location.beg_pos;
        if (type == NODE_POSTARG && RB_NODE_MULTI_TARGET(node)->rights.size) {
            const rb_node_list2_t *rights = &RB_NODE_MULTI_TARGET(node)->rights;
            data->location.end_pos = rights->nodes[rights->size - 1]->location.end_pos;
        }
        break;
      case RB_LOCAL_VARIABLE_AND_WRITE_NODE:
        if (type == NODE_LVAR || type == NODE_DVAR) data->location = RB_NODE_LOCAL_VARIABLE_AND_WRITE(node)->name_loc;
        break;
      case RB_LOCAL_VARIABLE_OR_WRITE_NODE:
        if (type == NODE_LVAR || type == NODE_DVAR) data->location = RB_NODE_LOCAL_VARIABLE_OR_WRITE(node)->name_loc;
        break;
      case RB_LOCAL_VARIABLE_OPERATOR_WRITE_NODE:
        if (type == NODE_LVAR || type == NODE_DVAR) data->location = RB_NODE_LOCAL_VARIABLE_OPERATOR_WRITE(node)->name_loc;
        if (type == NODE_LIST) data->location = RB_NODE_LOCAL_VARIABLE_OPERATOR_WRITE(node)->value->location;
        break;
      case RB_INSTANCE_VARIABLE_AND_WRITE_NODE:
        if (type == NODE_IVAR) data->location = RB_NODE_INSTANCE_VARIABLE_AND_WRITE(node)->name_loc;
        break;
      case RB_INSTANCE_VARIABLE_OR_WRITE_NODE:
        if (type == NODE_IVAR) data->location = RB_NODE_INSTANCE_VARIABLE_OR_WRITE(node)->name_loc;
        break;
      case RB_INSTANCE_VARIABLE_OPERATOR_WRITE_NODE:
        if (type == NODE_IVAR) data->location = RB_NODE_INSTANCE_VARIABLE_OPERATOR_WRITE(node)->name_loc;
        if (type == NODE_LIST) data->location = RB_NODE_INSTANCE_VARIABLE_OPERATOR_WRITE(node)->value->location;
        break;
      case RB_CLASS_VARIABLE_AND_WRITE_NODE:
        if (type == NODE_CVAR) data->location = RB_NODE_CLASS_VARIABLE_AND_WRITE(node)->name_loc;
        break;
      case RB_CLASS_VARIABLE_OR_WRITE_NODE:
        if (type == NODE_CVAR) data->location = RB_NODE_CLASS_VARIABLE_OR_WRITE(node)->name_loc;
        break;
      case RB_CLASS_VARIABLE_OPERATOR_WRITE_NODE:
        if (type == NODE_CVAR) data->location = RB_NODE_CLASS_VARIABLE_OPERATOR_WRITE(node)->name_loc;
        if (type == NODE_LIST) data->location = RB_NODE_CLASS_VARIABLE_OPERATOR_WRITE(node)->value->location;
        break;
      case RB_GLOBAL_VARIABLE_AND_WRITE_NODE:
        if (type == NODE_GVAR) data->location = RB_NODE_GLOBAL_VARIABLE_AND_WRITE(node)->name_loc;
        break;
      case RB_GLOBAL_VARIABLE_OR_WRITE_NODE:
        if (type == NODE_GVAR) data->location = RB_NODE_GLOBAL_VARIABLE_OR_WRITE(node)->name_loc;
        break;
      case RB_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE:
        if (type == NODE_GVAR) data->location = RB_NODE_GLOBAL_VARIABLE_OPERATOR_WRITE(node)->name_loc;
        if (type == NODE_LIST) data->location = RB_NODE_GLOBAL_VARIABLE_OPERATOR_WRITE(node)->value->location;
        break;
      case RB_CONSTANT_OPERATOR_WRITE_NODE:
        if (type == NODE_LIST) data->location = RB_NODE_CONSTANT_OPERATOR_WRITE(node)->value->location;
        break;
      default: break;
    }
    return object;
}

static VALUE
ast_list(const struct ASTNodeData *parent, const rb_node_t *owner, const rb_node_list2_t *list,
         size_t index, size_t count, enum node_type type)
{
    if (!count) return Qnil;
    VALUE object = ast_view(parent, owner, type);
    struct ASTNodeData *data;
    TypedData_Get_Struct(object, struct ASTNodeData, &rb_node_type, data);
    data->list = list;
    data->index = index;
    data->count = count;
    data->location.beg_pos = list->nodes[index]->location.beg_pos;
    if (list->nodes[index]->type == RB_MULTI_TARGET_NODE && !NULL_LOC_P(&RB_NODE_MULTI_TARGET(list->nodes[index])->lparen_loc)) {
        data->location.beg_pos = RB_NODE_MULTI_TARGET(list->nodes[index])->lparen_loc.beg_pos;
    }
    if (list->nodes[index]->type == RB_PRE_EXECUTION_NODE) data->location.beg_pos = RB_NODE_PRE_EXECUTION(list->nodes[index])->opening_loc.beg_pos;
    data->location.end_pos = list->nodes[index + count - 1]->location.end_pos;
    if (owner->type == RB_INTERPOLATED_STRING_NODE || owner->type == RB_INTERPOLATED_SYMBOL_NODE ||
        owner->type == RB_INTERPOLATED_X_STRING_NODE || owner->type == RB_INTERPOLATED_REGULAR_EXPRESSION_NODE ||
        owner->type == RB_INTERPOLATED_MATCH_LAST_LINE_NODE) {
        data->location.end_pos = list->nodes[index]->location.end_pos;
    }
    return object;
}

static VALUE
ast_arguments(const struct ASTNodeData *parent, const rb_node_t *owner, const rb_node_list2_t *list, size_t count)
{
    if (!count) return Qnil;
    if (list->nodes[count - 1]->type == RB_FORWARDING_ARGUMENTS_NODE) {
        VALUE child = ast_view(parent, list->nodes[count - 1], NODE_BLOCK_PASS);
        struct ASTNodeData *data;
        TypedData_Get_Struct(child, struct ASTNodeData, &rb_node_type, data);
        data->owner = owner;
        data->location = owner->location;
        const rb_code_location_t *opening = NULL, *closing = NULL;
        if (parent->node->type == RB_CALL_NODE) {
            opening = &RB_NODE_CALL(parent->node)->opening_loc;
            closing = &RB_NODE_CALL(parent->node)->closing_loc;
        }
        else if (parent->node->type == RB_SUPER_NODE) {
            opening = &RB_NODE_SUPER(parent->node)->lparen_loc;
            closing = &RB_NODE_SUPER(parent->node)->rparen_loc;
        }
        if (opening && !NULL_LOC_P(opening) && !NULL_LOC_P(closing)) {
            data->location.beg_pos = opening->beg_pos;
            data->location.end_pos = closing->end_pos;
        }
        return child;
    }
    size_t splat = count;
    while (splat && list->nodes[splat - 1]->type != RB_SPLAT_NODE) splat--;
    if (!splat) return ast_list(parent, owner, list, 0, count, NODE_LIST);
    if (splat < count) return ast_list(parent, owner, list, 0, count, count - splat == 1 ? NODE_ARGSPUSH : NODE_ARGSCAT);
    if (count == 1) return ast_child(parent, list->nodes[0]);
    return ast_list(parent, owner, list, 0, count, NODE_ARGSCAT);
}

static enum node_type
call_type(const rb_call_node_t *node)
{
    if (RB_NODE_FLAG_P(node, RB_CALL_NODE_FLAGS_ATTRIBUTE_WRITE)) return NODE_ATTRASGN;
    if (RB_NODE_FLAG_P(node, RB_CALL_NODE_FLAGS_SAFE_NAVIGATION)) return NODE_QCALL;
    if (RB_NODE_FLAG_P(node, RB_CALL_NODE_FLAGS_VARIABLE_CALL)) return NODE_VCALL;
    if (!node->receiver) return NODE_FCALL;
    if (NULL_LOC_P(&node->call_operator_loc) && !NULL_LOC_P(&node->message_loc) && !is_notop_id(node->name)) return NODE_OPCALL;
    return NODE_CALL;
}

static VALUE
ast_child(const struct ASTNodeData *parent, const rb_node_t *node)
{
    if (!node) return Qnil;
    enum node_type type;
    switch (RB_NODE_TYPE(node)) {
      case RB_STATEMENTS_NODE: {
        const rb_node_list2_t *list = &RB_NODE_STATEMENTS(node)->body;
        if (!list->size) return ast_view(parent, node, NODE_BEGIN);
        if (list->size == 1) return ast_child(parent, list->nodes[0]);
        return ast_list(parent, node, list, 0, list->size, NODE_BLOCK);
      }
      case RB_ELSE_NODE: return ast_child(parent, (const rb_node_t *)RB_NODE_ELSE(node)->statements);
      case RB_BLOCK_PARAMETERS_NODE: return ast_child(parent, (const rb_node_t *)RB_NODE_BLOCK_PARAMETERS(node)->parameters);
      case RB_PARENTHESES_NODE:
        if (RB_NODE_FLAG_P(node, RB_PARENTHESES_NODE_FLAGS_ARGUMENT)) return ast_child(parent, RB_NODE_PARENTHESES(node)->body);
        return ast_view(parent, node, NODE_BLOCK);
      case RB_IMPLICIT_NODE: return ast_child(parent, RB_NODE_IMPLICIT(node)->value);
      case RB_ASSOC_SPLAT_NODE: return ast_child(parent, RB_NODE_ASSOC_SPLAT(node)->value);
      case RB_PINNED_VARIABLE_NODE: return ast_child(parent, RB_NODE_PINNED_VARIABLE(node)->variable);
      case RB_SHAREABLE_CONSTANT_NODE: return ast_child(parent, RB_NODE_SHAREABLE_CONSTANT(node)->write);
      case RB_PROGRAM_NODE: case RB_BLOCK_NODE: type = NODE_SCOPE; break;
      case RB_DEF_NODE: type = RB_NODE_DEF(node)->receiver ? NODE_DEFS : NODE_DEFN; break;
      case RB_CALL_NODE: {
        const rb_call_node_t *call = RB_NODE_CALL(node);
        type = call->block && call->block->type == RB_BLOCK_NODE ? NODE_ITER : call_type(call);
        if (call->name == idEqTilde && call->receiver && !call->block &&
            NULL_LOC_P(&call->call_operator_loc) && call->arguments && RB_NODE_ARGUMENTS(call->arguments)->arguments.size == 1 &&
            (call->receiver->type == RB_REGULAR_EXPRESSION_NODE || call->receiver->type == RB_INTERPOLATED_REGULAR_EXPRESSION_NODE)) type = NODE_MATCH2;
        else if (call->name == idEqTilde && !call->block && NULL_LOC_P(&call->call_operator_loc) &&
                 call->arguments && RB_NODE_ARGUMENTS(call->arguments)->arguments.size == 1 &&
                 RB_NODE_ARGUMENTS(call->arguments)->arguments.nodes[0]->type == RB_REGULAR_EXPRESSION_NODE) type = NODE_MATCH3;
        break;
      }
      case RB_SUPER_NODE: type = RB_NODE_SUPER(node)->block && RB_NODE_SUPER(node)->block->type == RB_BLOCK_NODE ? NODE_ITER : NODE_SUPER; break;
      case RB_FORWARDING_SUPER_NODE: type = RB_NODE_FORWARDING_SUPER(node)->block ? NODE_ITER : NODE_ZSUPER; break;
      case RB_ARGUMENTS_NODE: return ast_arguments(parent, node, &RB_NODE_ARGUMENTS(node)->arguments, RB_NODE_ARGUMENTS(node)->arguments.size);
      case RB_ARRAY_NODE: {
        const rb_node_list2_t *list = &RB_NODE_ARRAY(node)->elements;
        if (!list->size) { type = NODE_ZLIST; break; }
        VALUE object = ast_arguments(parent, node, list, list->size);
        struct ASTNodeData *data;
        TypedData_Get_Struct(object, struct ASTNodeData, &rb_node_type, data);
        data->location = node->location;
        return object;
      }
      case RB_LOCAL_VARIABLE_READ_NODE: case RB_IT_LOCAL_VARIABLE_READ_NODE: type = parent->dynamic ? NODE_DVAR : NODE_LVAR; break;
      case RB_LOCAL_VARIABLE_WRITE_NODE: case RB_LOCAL_VARIABLE_TARGET_NODE:
      case RB_REQUIRED_PARAMETER_NODE: case RB_OPTIONAL_PARAMETER_NODE:
      case RB_REQUIRED_KEYWORD_PARAMETER_NODE: case RB_OPTIONAL_KEYWORD_PARAMETER_NODE:
        type = parent->dynamic ? NODE_DASGN : NODE_LASGN; break;
      case RB_KEYWORD_REST_PARAMETER_NODE: type = NODE_DVAR; break;
      case RB_CONSTANT_PATH_TARGET_NODE: type = NODE_CDECL; break;
      case RB_CONSTANT_PATH_NODE:
        type = RB_NODE_CONSTANT_PATH(node)->parent ? NODE_COLON2 : NODE_COLON3; break;
      case RB_CASE_NODE: type = RB_NODE_CASE(node)->predicate ? NODE_CASE : NODE_CASE2; break;
      case RB_RANGE_NODE: type = RB_NODE_FLAG_P(node, RB_RANGE_FLAGS_EXCLUDE_END) ? NODE_DOT3 : NODE_DOT2; break;
      case RB_FLIP_FLOP_NODE: type = RB_NODE_FLAG_P(node, RB_RANGE_FLAGS_EXCLUDE_END) ? NODE_FLIP3 : NODE_FLIP2; break;
      case RB_BEGIN_NODE: {
        const rb_begin_node_t *n = RB_NODE_BEGIN(node);
        if (n->ensure_clause) type = NODE_ENSURE;
        else if (n->rescue_clause) type = NODE_RESCUE;
        else {
            if (NULL_LOC_P(&n->begin_keyword_loc) && n->statements &&
                RB_NODE_STATEMENTS(n->statements)->body.size &&
                (node->location.beg_pos.lineno != n->statements->base.location.beg_pos.lineno ||
                 node->location.beg_pos.column != n->statements->base.location.beg_pos.column)) {
                type = NODE_BLOCK;
            }
            else return ast_child(parent, (const rb_node_t *)n->statements);
        }
        break;
      }
            case RB_ALIAS_GLOBAL_VARIABLE_NODE: type = NODE_VALIAS; break;
      case RB_ALIAS_METHOD_NODE: type = NODE_ALIAS; break;
      case RB_ALTERNATION_PATTERN_NODE: type = NODE_OR; break;
      case RB_AND_NODE: type = NODE_AND; break;
      case RB_ARRAY_PATTERN_NODE: type = NODE_ARYPTN; break;
      case RB_BACK_REFERENCE_READ_NODE: type = NODE_BACK_REF; break;
      case RB_BLOCK_ARGUMENT_NODE: type = NODE_BLOCK_PASS; break;
      case RB_BREAK_NODE: type = NODE_BREAK; break;
      case RB_CALL_AND_WRITE_NODE: type = NODE_OP_ASGN2; break;
      case RB_CALL_OPERATOR_WRITE_NODE: type = NODE_OP_ASGN2; break;
      case RB_CALL_OR_WRITE_NODE: type = NODE_OP_ASGN2; break;
      case RB_CALL_TARGET_NODE: type = NODE_ATTRASGN; break;
      case RB_CAPTURE_PATTERN_NODE: type = NODE_HASH; break;
      case RB_CASE_MATCH_NODE: type = NODE_CASE3; break;
      case RB_CLASS_NODE: type = NODE_CLASS; break;
      case RB_CONSTANT_PATH_WRITE_NODE: type = NODE_CDECL; break;
      case RB_DEFINED_NODE: type = NODE_DEFINED; break;
      case RB_EMBEDDED_STATEMENTS_NODE: type = NODE_EVSTR; break;
      case RB_EMBEDDED_VARIABLE_NODE: type = NODE_EVSTR; break;
      case RB_ENSURE_NODE: type = NODE_ENSURE; break;
      case RB_FALSE_NODE: type = NODE_FALSE; break;
      case RB_FIND_PATTERN_NODE: type = NODE_FNDPTN; break;
      case RB_FLOAT_NODE: type = NODE_FLOAT; break;
      case RB_FOR_NODE: type = NODE_FOR; break;
      case RB_FORWARDING_ARGUMENTS_NODE: type = NODE_BLOCK_PASS; break;
      case RB_FORWARDING_PARAMETER_NODE: type = NODE_DVAR; break;
      case RB_HASH_NODE: type = NODE_HASH; break;
      case RB_HASH_PATTERN_NODE: type = NODE_HSHPTN; break;
      case RB_IF_NODE: type = NODE_IF; break;
      case RB_IMAGINARY_NODE: type = NODE_IMAGINARY; break;
      case RB_IMPLICIT_REST_NODE: type = NODE_SPLAT; break;
      case RB_IN_NODE: type = NODE_IN; break;
      case RB_INDEX_AND_WRITE_NODE: type = NODE_OP_ASGN1; break;
      case RB_INDEX_OPERATOR_WRITE_NODE: type = NODE_OP_ASGN1; break;
      case RB_INDEX_OR_WRITE_NODE: type = NODE_OP_ASGN1; break;
      case RB_INDEX_TARGET_NODE: type = NODE_ATTRASGN; break;
      case RB_INTEGER_NODE: type = NODE_INTEGER; break;
      case RB_INTERPOLATED_MATCH_LAST_LINE_NODE: type = NODE_MATCH2; break;
      case RB_INTERPOLATED_REGULAR_EXPRESSION_NODE: type = RB_NODE_FLAG_P(node, RB_REGULAR_EXPRESSION_FLAGS_ONCE) ? NODE_ONCE : NODE_DREGX; break;
      case RB_INTERPOLATED_STRING_NODE: type = NODE_DSTR; break;
      case RB_INTERPOLATED_SYMBOL_NODE: type = NODE_DSYM; break;
      case RB_INTERPOLATED_X_STRING_NODE: type = NODE_DXSTR; break;
      case RB_IT_PARAMETERS_NODE: type = NODE_ARGS; break;
      case RB_KEYWORD_HASH_NODE: type = NODE_HASH; break;
      case RB_LAMBDA_NODE: type = NODE_LAMBDA; break;
      case RB_MATCH_LAST_LINE_NODE: type = NODE_MATCH; break;
      case RB_MATCH_PREDICATE_NODE: type = NODE_CASE3; break;
      case RB_MATCH_REQUIRED_NODE: type = NODE_CASE3; break;
      case RB_MATCH_WRITE_NODE: type = NODE_MATCH2; break;
      case RB_MISSING_NODE: type = NODE_ERROR; break;
      case RB_MODULE_NODE: type = NODE_MODULE; break;
      case RB_MULTI_TARGET_NODE: type = NODE_MASGN; break;
      case RB_MULTI_WRITE_NODE: type = NODE_MASGN; break;
      case RB_NEXT_NODE: type = NODE_NEXT; break;
      case RB_NIL_NODE: type = NODE_NIL; break;
      case RB_NO_KEYWORDS_PARAMETER_NODE: type = NODE_ARGS; break;
      case RB_NUMBERED_PARAMETERS_NODE: type = NODE_ARGS; break;
      case RB_NUMBERED_REFERENCE_READ_NODE: type = NODE_NTH_REF; break;
      case RB_OR_NODE: type = NODE_OR; break;
      case RB_PARAMETERS_NODE: type = NODE_ARGS; break;
      case RB_PINNED_EXPRESSION_NODE: type = NODE_BLOCK; break;

      case RB_POST_EXECUTION_NODE: type = NODE_POSTEXE; break;
      case RB_PRE_EXECUTION_NODE: type = NODE_BEGIN; break;
      case RB_RATIONAL_NODE: type = NODE_RATIONAL; break;
      case RB_REDO_NODE: type = NODE_REDO; break;
      case RB_REGULAR_EXPRESSION_NODE: type = NODE_REGX; break;
      case RB_RESCUE_MODIFIER_NODE: type = NODE_RESCUE; break;
      case RB_RESCUE_NODE: type = NODE_RESBODY; break;
      case RB_REST_PARAMETER_NODE: type = NODE_DVAR; break;
      case RB_RETRY_NODE: type = NODE_RETRY; break;
      case RB_RETURN_NODE: type = NODE_RETURN; break;
      case RB_SELF_NODE: type = NODE_SELF; break;
      case RB_SINGLETON_CLASS_NODE: type = NODE_SCLASS; break;
      case RB_SOURCE_ENCODING_NODE: type = NODE_ENCODING; break;
      case RB_SOURCE_FILE_NODE: type = NODE_FILE; break;
      case RB_SOURCE_LINE_NODE: type = NODE_LINE; break;
      case RB_SPLAT_NODE: type = NODE_SPLAT; break;
      case RB_STRING_NODE: type = NODE_STR; break;
      case RB_SYMBOL_NODE: type = NODE_SYM; break;
      case RB_TRUE_NODE: type = NODE_TRUE; break;
      case RB_UNDEF_NODE: type = NODE_UNDEF; break;
      case RB_UNLESS_NODE: type = NODE_UNLESS; break;
      case RB_UNTIL_NODE: type = NODE_UNTIL; break;
      case RB_WHEN_NODE: type = NODE_WHEN; break;
      case RB_WHILE_NODE: type = NODE_WHILE; break;
      case RB_X_STRING_NODE: type = NODE_XSTR; break;
      case RB_YIELD_NODE: type = NODE_YIELD; break;
      case RB_CLASS_VARIABLE_READ_NODE: type = NODE_CVAR; break;
      case RB_CLASS_VARIABLE_WRITE_NODE: type = NODE_CVASGN; break;
      case RB_CLASS_VARIABLE_TARGET_NODE: type = NODE_CVASGN; break;
      case RB_CLASS_VARIABLE_AND_WRITE_NODE: type = NODE_OP_ASGN_AND; break;
      case RB_CLASS_VARIABLE_OR_WRITE_NODE: type = NODE_OP_ASGN_OR; break;
      case RB_CLASS_VARIABLE_OPERATOR_WRITE_NODE: type = NODE_CVASGN; break;
      case RB_GLOBAL_VARIABLE_READ_NODE: type = NODE_GVAR; break;
      case RB_GLOBAL_VARIABLE_WRITE_NODE: type = NODE_GASGN; break;
      case RB_GLOBAL_VARIABLE_TARGET_NODE: type = NODE_GASGN; break;
      case RB_GLOBAL_VARIABLE_AND_WRITE_NODE: type = NODE_OP_ASGN_AND; break;
      case RB_GLOBAL_VARIABLE_OR_WRITE_NODE: type = NODE_OP_ASGN_OR; break;
      case RB_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE: type = NODE_GASGN; break;
      case RB_INSTANCE_VARIABLE_READ_NODE: type = NODE_IVAR; break;
      case RB_INSTANCE_VARIABLE_WRITE_NODE: type = NODE_IASGN; break;
      case RB_INSTANCE_VARIABLE_TARGET_NODE: type = NODE_IASGN; break;
      case RB_INSTANCE_VARIABLE_AND_WRITE_NODE: type = NODE_OP_ASGN_AND; break;
      case RB_INSTANCE_VARIABLE_OR_WRITE_NODE: type = NODE_OP_ASGN_OR; break;
      case RB_INSTANCE_VARIABLE_OPERATOR_WRITE_NODE: type = NODE_IASGN; break;
      case RB_CONSTANT_READ_NODE: type = NODE_CONST; break;
      case RB_CONSTANT_WRITE_NODE: type = NODE_CDECL; break;
      case RB_CONSTANT_TARGET_NODE: type = NODE_CDECL; break;
      case RB_CONSTANT_AND_WRITE_NODE: type = NODE_OP_ASGN_AND; break;
      case RB_CONSTANT_OR_WRITE_NODE: type = NODE_OP_ASGN_OR; break;
      case RB_CONSTANT_OPERATOR_WRITE_NODE: type = NODE_CDECL; break;
      case RB_LOCAL_VARIABLE_AND_WRITE_NODE: type = NODE_OP_ASGN_AND; break;
      case RB_LOCAL_VARIABLE_OR_WRITE_NODE: type = NODE_OP_ASGN_OR; break;
      case RB_LOCAL_VARIABLE_OPERATOR_WRITE_NODE: type = NODE_LASGN; break;
      case RB_CONSTANT_PATH_AND_WRITE_NODE: type = NODE_OP_CDECL; break;
      case RB_CONSTANT_PATH_OR_WRITE_NODE: type = NODE_OP_CDECL; break;
      case RB_CONSTANT_PATH_OPERATOR_WRITE_NODE: type = NODE_OP_CDECL; break;
      default: rb_raise(rb_eNotImpError, "AST projection for %s", rb_node_type_to_str(node->type));
    }
    return ast_view(parent, node, type);
}

static VALUE
ast_new_internal(VALUE ast_value, const rb_node_t *node)
{
    struct ASTNodeData parent = {.ast_value = ast_value};
    return ast_child(&parent, node);
}

static VALUE
ast_node_type(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);
    return rb_sym_intern_ascii_cstr(ruby_node_name(data->type) + rb_strlen_lit("NODE_"));
}

static VALUE
ast_node_node_id(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);
    const rb_node_t *node = data->node;
    if (data->type == NODE_ITER) {
        switch (node->type) {
          case RB_CALL_NODE: node = RB_NODE_CALL(node)->block; break;
          case RB_SUPER_NODE: node = RB_NODE_SUPER(node)->block; break;
          case RB_FORWARDING_SUPER_NODE: node = (const rb_node_t *)RB_NODE_FORWARDING_SUPER(node)->block; break;
          default: break;
        }
    }
    return INT2NUM(node->node_id);
}

#define CHILD(node) ast_child(data, (const rb_node_t *)(node))
#define VIEW(node, type) ast_view(data, (const rb_node_t *)(node), type)
#define CHILDREN(...) rb_ary_new_from_args(__VA_ARGS__)

static VALUE
scope_children(const struct ASTNodeData *data)
{
    if (data->node->type == RB_POST_EXECUTION_NODE) {
        return CHILDREN(3, rb_ary_new(), Qnil, CHILD(RB_NODE_POST_EXECUTION(data->node)->statements));
    }
    if (data->node->type == RB_FOR_NODE) {
        return CHILDREN(3, CHILDREN(1, Qnil), VIEW(data->node, NODE_ARGS), CHILD(RB_NODE_FOR(data->node)->statements));
    }
    rb_ast_id_table_t *table = NULL;
    const rb_node_t *parameters = NULL, *body = NULL;
    struct ASTNodeData context = *data;
    switch (RB_NODE_TYPE(data->node)) {
#define SCOPE(kind, dynamic_scope, args_field, body_field) \
      case RB_##kind##_NODE: { \
        table = RB_NODE_##kind(data->node)->locals; \
        parameters = (const rb_node_t *)args_field; \
        body = (const rb_node_t *)RB_NODE_##kind(data->node)->body_field; \
        context.dynamic = dynamic_scope; \
        break; \
      }
      SCOPE(PROGRAM, false, NULL, statements)
      SCOPE(DEF, false, RB_NODE_DEF(data->node)->parameters, body)
      SCOPE(BLOCK, true, RB_NODE_BLOCK(data->node)->parameters, body)
      SCOPE(LAMBDA, true, RB_NODE_LAMBDA(data->node)->parameters, body)
      SCOPE(CLASS, false, NULL, body)
      SCOPE(MODULE, false, NULL, body)
      SCOPE(SINGLETON_CLASS, false, NULL, body)
#undef SCOPE
      default: break;
    }
    VALUE locals = rb_ary_new_capa(table ? table->size : 0);
    if (table) for (int i = 0; i < table->size; i++) rb_ary_push(locals, var_name(table->ids[i]));
    VALUE args = ast_child(&context, parameters);
    if (NIL_P(args) && (data->node->type == RB_DEF_NODE || data->node->type == RB_LAMBDA_NODE)) {
        args = ast_view(&context, data->node, NODE_ARGS);
        struct ASTNodeData *args_data;
        TypedData_Get_Struct(args, struct ASTNodeData, &rb_node_type, args_data);
        args_data->location.beg_pos = args_data->location.end_pos =
            data->node->type == RB_DEF_NODE ? RB_NODE_DEF(data->node)->name_loc.end_pos : RB_NODE_LAMBDA(data->node)->operator_loc.end_pos;
    }
    if (data->node->type == RB_DEF_NODE && body && body->type == RB_BEGIN_NODE &&
        !RB_NODE_BEGIN(body)->rescue_clause && !RB_NODE_BEGIN(body)->ensure_clause &&
        (NULL_LOC_P(&RB_NODE_DEF(data->node)->lparen_loc) || !RB_NODE_BEGIN(body)->statements || !RB_NODE_STATEMENTS(RB_NODE_BEGIN(body)->statements)->body.size)) {
        body = (const rb_node_t *)RB_NODE_BEGIN(body)->statements;
        if (body && body->type == RB_STATEMENTS_NODE && !RB_NODE_STATEMENTS(body)->body.size) body = NULL;
    }
    if (data->node->type == RB_DEF_NODE && body) {
        if (body->type == RB_NIL_NODE && (!NULL_LOC_P(&RB_NODE_DEF(data->node)->equal_loc) || NULL_LOC_P(&body->location))) body = NULL;
        else if (body->type == RB_STATEMENTS_NODE && RB_NODE_STATEMENTS(body)->body.size == 1 &&
                 RB_NODE_STATEMENTS(body)->body.nodes[0]->type == RB_NIL_NODE &&
                 (!NULL_LOC_P(&RB_NODE_DEF(data->node)->equal_loc) || NULL_LOC_P(&RB_NODE_STATEMENTS(body)->body.nodes[0]->location))) body = NULL;
    }
    return CHILDREN(3, locals, args, ast_child(&context, body));
}

static ID
parameter_name(const rb_node_t *node)
{
    if (!node) return 0;
    switch (RB_NODE_TYPE(node)) {
      case RB_REQUIRED_PARAMETER_NODE: return RB_NODE_REQUIRED_PARAMETER(node)->name;
      case RB_REST_PARAMETER_NODE: return RB_NODE_REST_PARAMETER(node)->name;
      case RB_BLOCK_PARAMETER_NODE: return RB_NODE_BLOCK_PARAMETER(node)->name;
      case RB_KEYWORD_REST_PARAMETER_NODE: return RB_NODE_KEYWORD_REST_PARAMETER(node)->name;
      default: return 0;
    }
}

static VALUE
parameter_initializers(const struct ASTNodeData *data, const rb_node_list2_t *parameters)
{
    size_t first = parameters->size, last = 0, count = 0;
    for (size_t i = 0; i < parameters->size; i++) {
        if (parameters->nodes[i]->type != RB_MULTI_TARGET_NODE) continue;
        if (!count++) first = i;
        last = i;
    }
    if (!count) return Qnil;
    if (count == 1) return owned_child(data, parameters->nodes[first], data->node);
    return ast_list(data, data->node, parameters, first, last - first + 1, NODE_BLOCK);
}

static VALUE
parameters_children(const struct ASTNodeData *data)
{
    if (data->node->type == RB_FOR_NODE) {
        const rb_node_t *index = RB_NODE_FOR(data->node)->index;
        bool local = index->type == RB_LOCAL_VARIABLE_WRITE_NODE || index->type == RB_LOCAL_VARIABLE_TARGET_NODE;
        VALUE initializer = local || index->type == RB_MULTI_TARGET_NODE ? owned_child(data, index, data->node) : VIEW(data->node, NODE_MASGN);
        return CHILDREN(10, INT2FIX(local ? 1 : 0), initializer,
            Qnil, Qnil, INT2FIX(0), Qnil, Qnil, Qnil, Qnil, Qnil);
    }
    if (data->node->type != RB_PARAMETERS_NODE) {
        int count = data->node->type == RB_NUMBERED_PARAMETERS_NODE ? RB_NODE_NUMBERED_PARAMETERS(data->node)->maximum : data->node->type == RB_IT_PARAMETERS_NODE;
        return CHILDREN(10, INT2FIX(count), Qnil, Qnil, Qnil, INT2FIX(0), Qnil, Qnil, Qnil, Qnil, Qnil);
    }
    const rb_parameters_node_t *node = RB_NODE_PARAMETERS(data->node);
    VALUE rest = var_name(parameter_name(node->rest));
    VALUE kwrest = CHILD(node->keyword_rest);
    VALUE block = var_name(parameter_name((const rb_node_t *)node->block));
    if (node->rest && node->rest->type == RB_IMPLICIT_REST_NODE) rest = special_name("NODE_SPECIAL_EXCESSIVE_COMMA");
    if (node->keyword_rest && node->keyword_rest->type == RB_NO_KEYWORDS_PARAMETER_NODE) kwrest = Qfalse;
    if (node->keyword_rest && node->keyword_rest->type == RB_FORWARDING_PARAMETER_NODE) {
        rest = special_name("*");
        kwrest = VIEW(node->keyword_rest, NODE_DVAR);
        block = special_name("&");
    }
    if (node->block && parameter_name((const rb_node_t *)node->block) == idNil) block = Qfalse;
    VALUE keywords = ast_list(data, data->node, &node->keywords, 0, node->keywords.size, NODE_KW_ARG);
    return CHILDREN(10, SIZET2NUM(node->requireds.size), parameter_initializers(data, &node->requireds),
        ast_list(data, data->node, &node->optionals, 0, node->optionals.size, NODE_OPT_ARG),
        node->posts.size ? var_name(parameter_name(node->posts.nodes[0])) : Qnil,
        SIZET2NUM(node->posts.size), parameter_initializers(data, &node->posts), rest, kwrest == Qfalse ? Qfalse : keywords, kwrest, block);
}

static VALUE
owned_child(const struct ASTNodeData *data, const rb_node_t *node, const rb_node_t *owner)
{
    VALUE child = CHILD(node);
    if (!NIL_P(child)) {
        struct ASTNodeData *child_data;
        TypedData_Get_Struct(child, struct ASTNodeData, &rb_node_type, child_data);
        child_data->owner = owner;
        if (owner->type == RB_HASH_PATTERN_NODE) child_data->location = owner->location;
    }
    return child;
}

static VALUE
forwarding_variable(const struct ASTNodeData *data, size_t index)
{
    VALUE child = VIEW(data->node, data->dynamic ? NODE_DVAR : NODE_LVAR);
    struct ASTNodeData *child_data;
    TypedData_Get_Struct(child, struct ASTNodeData, &rb_node_type, child_data);
    child_data->index = index;
    return child;
}

static VALUE
case_clause(const struct ASTNodeData *data, const rb_node_t *owner, size_t index)
{
    const rb_node_list2_t *clauses;
    const rb_node_t *otherwise;
    if (owner->type == RB_CASE_NODE) {
        clauses = &RB_NODE_CASE(owner)->conditions;
        otherwise = (const rb_node_t *)RB_NODE_CASE(owner)->else_clause;
    }
    else {
        clauses = &RB_NODE_CASE_MATCH(owner)->conditions;
        otherwise = (const rb_node_t *)RB_NODE_CASE_MATCH(owner)->else_clause;
    }
    if (index >= clauses->size) return CHILD(otherwise);
    VALUE child = CHILD(clauses->nodes[index]);
    struct ASTNodeData *child_data;
    TypedData_Get_Struct(child, struct ASTNodeData, &rb_node_type, child_data);
    child_data->owner = owner;
    child_data->index = index;
    if (owner->type == RB_CASE_MATCH_NODE && clauses->size) {
        child_data->location.end_pos = otherwise ? otherwise->location.end_pos : clauses->nodes[clauses->size - 1]->location.end_pos;
    }
    return child;
}

static VALUE
pattern_rest(const struct ASTNodeData *data, const rb_node_t *rest)
{
    if (!rest) return Qnil;
    if (rest->type == RB_IMPLICIT_REST_NODE) return special_name("NODE_SPECIAL_NO_NAME_REST");
    if (rest->type == RB_SPLAT_NODE) {
        rest = RB_NODE_SPLAT(rest)->expression;
        if (!rest) return special_name("NODE_SPECIAL_NO_NAME_REST");
    }
    return CHILD(rest);
}

static VALUE
defined_original_child(const struct ASTNodeData *data, const rb_node_t *node)
{
    bool argument = false;
    while (node) {
        if (node->type == RB_PARENTHESES_NODE && RB_NODE_FLAG_P(node, RB_PARENTHESES_NODE_FLAGS_ARGUMENT)) {
            argument = true;
            node = RB_NODE_PARENTHESES(node)->body;
        }
        else if (argument && node->type == RB_STATEMENTS_NODE && RB_NODE_STATEMENTS(node)->body.size == 1) {
            node = RB_NODE_STATEMENTS(node)->body.nodes[0];
        }
        else if (argument && node->type == RB_BEGIN_NODE && !RB_NODE_BEGIN(node)->rescue_clause && !RB_NODE_BEGIN(node)->ensure_clause) {
            node = (const rb_node_t *)RB_NODE_BEGIN(node)->statements;
        }
        else break;
    }
    if (node && node->type == RB_BEGIN_NODE && !argument) {
        VALUE child = VIEW(node, NODE_BEGIN);
        struct ASTNodeData *child_data;
        TypedData_Get_Struct(child, struct ASTNodeData, &rb_node_type, child_data);
        child_data->owner = data->node;
        child_data->location.beg_pos = RB_NODE_BEGIN(node)->begin_keyword_loc.beg_pos;
        child_data->location.end_pos = RB_NODE_BEGIN(node)->end_keyword_loc.end_pos;
        return child;
    }
    return CHILD(node);
}

static VALUE
node_children(const struct ASTNodeData *data)
{
    const rb_node_t *node = data->node;
    if (data->type == NODE_SCOPE) return scope_children(data);
    if (data->type == NODE_ARGS) return parameters_children(data);
    if (data->list) {
        const rb_node_list2_t *list = data->list;
        size_t start = data->index, count = data->count;
        if (data->type == NODE_ARGSCAT) {
            if (list->nodes[count - 1]->type == RB_SPLAT_NODE) return CHILDREN(2,
                ast_arguments(data, node, list, count - 1), CHILD(RB_NODE_SPLAT(list->nodes[count - 1])->expression));
            size_t split = count;
            while (split && list->nodes[split - 1]->type != RB_SPLAT_NODE) split--;
            return CHILDREN(2, ast_arguments(data, node, list, split), ast_list(data, node, list, split, count - split, NODE_LIST));
        }
        if (data->type == NODE_ARGSPUSH) return CHILDREN(2,
            ast_arguments(data, node, list, count - 1), CHILD(list->nodes[count - 1]));
        if (data->type == NODE_OPT_ARG || data->type == NODE_KW_ARG) return CHILDREN(2,
            CHILD(list->nodes[start]), ast_list(data, node, list, start + 1, count - 1, data->type));
        VALUE array = rb_ary_new_capa(count + 1);
        for (size_t i = start; i < start + count; i++) {
            if (node->type == RB_PARAMETERS_NODE && data->type == NODE_BLOCK) {
                if (list->nodes[i]->type == RB_MULTI_TARGET_NODE) rb_ary_push(array, owned_child(data, list->nodes[i], node));
            }
            else rb_ary_push(array, node->type == RB_MATCH_WRITE_NODE ? owned_child(data, list->nodes[i], node) : CHILD(list->nodes[i]));
        }
        if (data->type == NODE_LIST) rb_ary_push(array, Qnil);
        return array;
    }
    if (data->type == NODE_ERRINFO || data->type == NODE_TRUE || data->type == NODE_FALSE) return rb_ary_new();
    switch (RB_NODE_TYPE(node)) {
      case RB_FORWARDING_ARGUMENTS_NODE: {
        static const char *names[] = {"*", "**", "&"};
        const rb_node_list2_t *args = data->owner->type == RB_ARGUMENTS_NODE ? &RB_NODE_ARGUMENTS(data->owner)->arguments : NULL;
        bool prefix = args && args->size > 1;
        switch (data->type) {
          case NODE_LVAR: case NODE_DVAR: return CHILDREN(1, special_name(names[data->index]));
          case NODE_BLOCK_PASS: return CHILDREN(2, VIEW(node, NODE_ARGSPUSH), forwarding_variable(data, 2));
          case NODE_ARGSPUSH: return CHILDREN(2, VIEW(node, prefix ? NODE_ARGSCAT : NODE_SPLAT), VIEW(node, NODE_HASH));
          case NODE_ARGSCAT: return CHILDREN(2, ast_arguments(data, data->owner, args, args->size - 1), forwarding_variable(data, 0));
          case NODE_SPLAT: return CHILDREN(1, forwarding_variable(data, 0));
          case NODE_HASH: return CHILDREN(1, VIEW(node, NODE_LIST));
          case NODE_LIST: return CHILDREN(3, Qnil, forwarding_variable(data, 1), Qnil);
          default: break;
        }
        break;
      }
      case RB_MATCH_WRITE_NODE: {
        const rb_match_write_node_t *n = RB_NODE_MATCH_WRITE(node);
        const rb_call_node_t *call = RB_NODE_CALL(n->call);
        return CHILDREN(3, CHILD(call->receiver), CHILD(RB_NODE_ARGUMENTS(call->arguments)->arguments.nodes[0]),
            ast_list(data, node, &n->targets, 0, n->targets.size, NODE_BLOCK));
      }
      case RB_CASE_NODE: return CHILDREN(2, CHILD(RB_NODE_CASE(node)->predicate), case_clause(data, node, 0));
      case RB_CASE_MATCH_NODE: return CHILDREN(2, CHILD(RB_NODE_CASE_MATCH(node)->predicate), case_clause(data, node, 0));
      case RB_WHEN_NODE: {
        const rb_when_node_t *n = RB_NODE_WHEN(node);
        return CHILDREN(3, ast_arguments(data, node, &n->conditions, n->conditions.size), CHILD(n->statements),
            data->owner != node ? case_clause(data, data->owner, data->index + 1) : Qnil);
      }
      case RB_IN_NODE: {
        const rb_in_node_t *n = RB_NODE_IN(node);
        return CHILDREN(3, CHILD(n->pattern), CHILD(n->statements),
            data->owner != node ? case_clause(data, data->owner, data->index + 1) : Qnil);
      }
      case RB_MATCH_REQUIRED_NODE: case RB_MATCH_PREDICATE_NODE: {
        const rb_match_required_node_t *n = RB_NODE_MATCH_REQUIRED(node);
        if (data->type == NODE_CASE3) return CHILDREN(2, CHILD(n->value), VIEW(node, NODE_IN));
        return CHILDREN(3, CHILD(n->pattern), node->type == RB_MATCH_PREDICATE_NODE ? VIEW(node, NODE_TRUE) : Qnil,
            node->type == RB_MATCH_PREDICATE_NODE ? VIEW(node, NODE_FALSE) : Qnil);
      }
      case RB_ARRAY_PATTERN_NODE: {
        const rb_array_pattern_node_t *n = RB_NODE_ARRAY_PATTERN(node);
        return CHILDREN(4, CHILD(n->constant), ast_list(data, node, &n->requireds, 0, n->requireds.size, NODE_LIST),
            pattern_rest(data, (const rb_node_t *)n->rest), ast_list(data, node, &n->posts, 0, n->posts.size, NODE_LIST));
      }
      case RB_FIND_PATTERN_NODE: {
        const rb_find_pattern_node_t *n = RB_NODE_FIND_PATTERN(node);
        return CHILDREN(4, CHILD(n->constant), pattern_rest(data, (const rb_node_t *)n->left),
            ast_list(data, node, &n->requireds, 0, n->requireds.size, NODE_LIST), pattern_rest(data, (const rb_node_t *)n->right));
      }
      case RB_HASH_PATTERN_NODE: {
        const rb_hash_pattern_node_t *n = RB_NODE_HASH_PATTERN(node);
        if (data->type == NODE_HSHPTN) return CHILDREN(3, CHILD(n->constant), (n->elements.size || n->rest) ? VIEW(node, NODE_HASH) : Qnil,
            n->rest && n->rest->type == RB_NO_KEYWORDS_PARAMETER_NODE ? special_name("NODE_SPECIAL_NO_REST_KEYWORD") : owned_child(data, n->rest, node));
        if (data->type == NODE_HASH) return CHILDREN(1, n->elements.size ? VIEW(node, NODE_LIST) : Qnil);
        VALUE children = rb_ary_new_capa(n->elements.size * 2 + 1);
        for (size_t i = 0; i < n->elements.size; i++) {
            const rb_assoc_node_t *assoc = RB_NODE_ASSOC(n->elements.nodes[i]);
            rb_ary_push(children, CHILD(assoc->key));
            rb_ary_push(children, CHILD(assoc->value));
        }
        rb_ary_push(children, Qnil);
        return children;
      }
      case RB_MULTI_WRITE_NODE: case RB_MULTI_TARGET_NODE: {
        const rb_multi_target_node_t *n = RB_NODE_MULTI_TARGET(node);
        if (data->type == NODE_LVAR || data->type == NODE_DVAR) return CHILDREN(1, Qnil);
        VALUE rest = Qnil;
        if (n->rights.size) rest = VIEW(node, NODE_POSTARG);
        else if (n->rest && n->rest->type != RB_IMPLICIT_REST_NODE) rest = pattern_rest(data, (const rb_node_t *)n->rest);
        if (data->type == NODE_POSTARG) return CHILDREN(2, pattern_rest(data, (const rb_node_t *)n->rest), ast_list(data, node, &n->rights, 0, n->rights.size, NODE_LIST));
        return CHILDREN(3, node->type == RB_MULTI_WRITE_NODE ? CHILD(RB_NODE_MULTI_WRITE(node)->value) :
            data->owner->type == RB_FOR_NODE ? VIEW(data->owner, NODE_FOR_MASGN) :
            data->owner->type == RB_PARAMETERS_NODE ? VIEW(node, data->dynamic ? NODE_DVAR : NODE_LVAR) : Qnil,
            ast_list(data, node, &n->lefts, 0, n->lefts.size, NODE_LIST), rest);
      }
      case RB_ALTERNATION_PATTERN_NODE: return CHILDREN(2, CHILD(RB_NODE_ALTERNATION_PATTERN(node)->left), CHILD(RB_NODE_ALTERNATION_PATTERN(node)->right));
      case RB_CAPTURE_PATTERN_NODE:
        if (data->type == NODE_HASH) return CHILDREN(1, VIEW(node, NODE_LIST));
        return CHILDREN(3, CHILD(RB_NODE_CAPTURE_PATTERN(node)->value), CHILD(RB_NODE_CAPTURE_PATTERN(node)->target), Qnil);
      case RB_CALL_TARGET_NODE:
        if (data->type == NODE_LIST) return CHILDREN(2, VIEW(node, NODE_ERRINFO), Qnil);
        return CHILDREN(3, CHILD(RB_NODE_CALL_TARGET(node)->receiver), var_name(RB_NODE_CALL_TARGET(node)->name),
            data->owner->type == RB_RESCUE_NODE ? VIEW(node, NODE_LIST) : Qnil);
      case RB_INDEX_TARGET_NODE: {
        const rb_arguments_node_t *args = RB_NODE_INDEX_TARGET(node)->arguments;
        const rb_node_list2_t *list = args ? &args->arguments : NULL;
        size_t count = list ? list->size : 0, split = count;
        while (split && list->nodes[split - 1]->type != RB_SPLAT_NODE) split--;
        if (data->type == NODE_ARGSPUSH) return CHILDREN(2, CHILD(args), VIEW(node, NODE_ERRINFO));
        if (data->type == NODE_ARGSCAT) {
            VALUE tail = VIEW(node, NODE_LIST);
            struct ASTNodeData *tail_data;
            TypedData_Get_Struct(tail, struct ASTNodeData, &rb_node_type, tail_data);
            tail_data->index = split;
            tail_data->location.beg_pos = list->nodes[split]->location.beg_pos;
            return CHILDREN(2, ast_arguments(data, (const rb_node_t *)args, list, split), tail);
        }
        if (data->type == NODE_LIST) {
            VALUE children = rb_ary_new_capa(count - data->index + 2);
            for (size_t i = data->index; i < count; i++) rb_ary_push(children, CHILD(list->nodes[i]));
            rb_ary_push(children, VIEW(node, NODE_ERRINFO));
            rb_ary_push(children, Qnil);
            return children;
        }
        return CHILDREN(3, CHILD(RB_NODE_INDEX_TARGET(node)->receiver), special_name("[]="),
            data->owner->type == RB_RESCUE_NODE ? VIEW(node, !split ? NODE_LIST : split < count ? NODE_ARGSCAT : NODE_ARGSPUSH) : CHILD(args));
      }
      case RB_LOCAL_VARIABLE_AND_WRITE_NODE: {
        const rb_local_variable_and_write_node_t *n = RB_NODE_LOCAL_VARIABLE_AND_WRITE(node);
        enum node_type read = data->dynamic ? NODE_DVAR : NODE_LVAR, write = data->dynamic ? NODE_DASGN : NODE_LASGN;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idANDOP), VIEW(node, write));
      }
      case RB_LOCAL_VARIABLE_OR_WRITE_NODE: {
        const rb_local_variable_or_write_node_t *n = RB_NODE_LOCAL_VARIABLE_OR_WRITE(node);
        enum node_type read = data->dynamic ? NODE_DVAR : NODE_LVAR, write = data->dynamic ? NODE_DASGN : NODE_LASGN;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idOROP), VIEW(node, write));
      }
      case RB_LOCAL_VARIABLE_OPERATOR_WRITE_NODE: {
        const rb_local_variable_operator_write_node_t *n = RB_NODE_LOCAL_VARIABLE_OPERATOR_WRITE(node);
        enum node_type read = data->dynamic ? NODE_DVAR : NODE_LVAR;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == NODE_CALL) return CHILDREN(3, VIEW(node, read), var_name(n->binary_operator), VIEW(node, NODE_LIST));
        if (data->type == NODE_LIST) return CHILDREN(2, CHILD(n->value), Qnil);
        return CHILDREN(2, var_name(n->name), VIEW(node, NODE_CALL));
      }
      case RB_INSTANCE_VARIABLE_AND_WRITE_NODE: {
        const rb_instance_variable_and_write_node_t *n = RB_NODE_INSTANCE_VARIABLE_AND_WRITE(node);
        enum node_type read = NODE_IVAR, write = NODE_IASGN;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idANDOP), VIEW(node, write));
      }
      case RB_INSTANCE_VARIABLE_OR_WRITE_NODE: {
        const rb_instance_variable_or_write_node_t *n = RB_NODE_INSTANCE_VARIABLE_OR_WRITE(node);
        enum node_type read = NODE_IVAR, write = NODE_IASGN;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idOROP), VIEW(node, write));
      }
      case RB_INSTANCE_VARIABLE_OPERATOR_WRITE_NODE: {
        const rb_instance_variable_operator_write_node_t *n = RB_NODE_INSTANCE_VARIABLE_OPERATOR_WRITE(node);
        enum node_type read = NODE_IVAR;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == NODE_CALL) return CHILDREN(3, VIEW(node, read), var_name(n->binary_operator), VIEW(node, NODE_LIST));
        if (data->type == NODE_LIST) return CHILDREN(2, CHILD(n->value), Qnil);
        return CHILDREN(2, var_name(n->name), VIEW(node, NODE_CALL));
      }
      case RB_CLASS_VARIABLE_AND_WRITE_NODE: {
        const rb_class_variable_and_write_node_t *n = RB_NODE_CLASS_VARIABLE_AND_WRITE(node);
        enum node_type read = NODE_CVAR, write = NODE_CVASGN;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idANDOP), VIEW(node, write));
      }
      case RB_CLASS_VARIABLE_OR_WRITE_NODE: {
        const rb_class_variable_or_write_node_t *n = RB_NODE_CLASS_VARIABLE_OR_WRITE(node);
        enum node_type read = NODE_CVAR, write = NODE_CVASGN;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idOROP), VIEW(node, write));
      }
      case RB_CLASS_VARIABLE_OPERATOR_WRITE_NODE: {
        const rb_class_variable_operator_write_node_t *n = RB_NODE_CLASS_VARIABLE_OPERATOR_WRITE(node);
        enum node_type read = NODE_CVAR;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == NODE_CALL) return CHILDREN(3, VIEW(node, read), var_name(n->binary_operator), VIEW(node, NODE_LIST));
        if (data->type == NODE_LIST) return CHILDREN(2, CHILD(n->value), Qnil);
        return CHILDREN(2, var_name(n->name), VIEW(node, NODE_CALL));
      }
      case RB_GLOBAL_VARIABLE_AND_WRITE_NODE: {
        const rb_global_variable_and_write_node_t *n = RB_NODE_GLOBAL_VARIABLE_AND_WRITE(node);
        enum node_type read = NODE_GVAR, write = NODE_GASGN;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idANDOP), VIEW(node, write));
      }
      case RB_GLOBAL_VARIABLE_OR_WRITE_NODE: {
        const rb_global_variable_or_write_node_t *n = RB_NODE_GLOBAL_VARIABLE_OR_WRITE(node);
        enum node_type read = NODE_GVAR, write = NODE_GASGN;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idOROP), VIEW(node, write));
      }
      case RB_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE: {
        const rb_global_variable_operator_write_node_t *n = RB_NODE_GLOBAL_VARIABLE_OPERATOR_WRITE(node);
        enum node_type read = NODE_GVAR;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == NODE_CALL) return CHILDREN(3, VIEW(node, read), var_name(n->binary_operator), VIEW(node, NODE_LIST));
        if (data->type == NODE_LIST) return CHILDREN(2, CHILD(n->value), Qnil);
        return CHILDREN(2, var_name(n->name), VIEW(node, NODE_CALL));
      }
      case RB_CONSTANT_AND_WRITE_NODE: {
        const rb_constant_and_write_node_t *n = RB_NODE_CONSTANT_AND_WRITE(node);
        enum node_type read = NODE_CONST, write = NODE_CDECL;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idANDOP), VIEW(node, write));
      }
      case RB_CONSTANT_OR_WRITE_NODE: {
        const rb_constant_or_write_node_t *n = RB_NODE_CONSTANT_OR_WRITE(node);
        enum node_type read = NODE_CONST, write = NODE_CDECL;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == write) return CHILDREN(2, var_name(n->name), CHILD(n->value));
        return CHILDREN(3, VIEW(node, read), ID2SYM(idOROP), VIEW(node, write));
      }
      case RB_CONSTANT_OPERATOR_WRITE_NODE: {
        const rb_constant_operator_write_node_t *n = RB_NODE_CONSTANT_OPERATOR_WRITE(node);
        enum node_type read = NODE_CONST;
        if (data->type == read) return CHILDREN(1, var_name(n->name));
        if (data->type == NODE_CALL) return CHILDREN(3, VIEW(node, read), var_name(n->binary_operator), VIEW(node, NODE_LIST));
        if (data->type == NODE_LIST) return CHILDREN(2, CHILD(n->value), Qnil);
        return CHILDREN(2, var_name(n->name), VIEW(node, NODE_CALL));
      }
      case RB_CONSTANT_PATH_AND_WRITE_NODE: return CHILDREN(3, CHILD(RB_NODE_CONSTANT_PATH_AND_WRITE(node)->target), ID2SYM(idANDOP), CHILD(RB_NODE_CONSTANT_PATH_AND_WRITE(node)->value));
      case RB_CONSTANT_PATH_OR_WRITE_NODE: return CHILDREN(3, CHILD(RB_NODE_CONSTANT_PATH_OR_WRITE(node)->target), ID2SYM(idOROP), CHILD(RB_NODE_CONSTANT_PATH_OR_WRITE(node)->value));
      case RB_CONSTANT_PATH_OPERATOR_WRITE_NODE: return CHILDREN(3, CHILD(RB_NODE_CONSTANT_PATH_OPERATOR_WRITE(node)->target), var_name(RB_NODE_CONSTANT_PATH_OPERATOR_WRITE(node)->binary_operator), CHILD(RB_NODE_CONSTANT_PATH_OPERATOR_WRITE(node)->value));
      case RB_FOR_NODE:
        if (data->type == NODE_DVAR) return CHILDREN(1, Qnil);
        if (data->type == NODE_FOR_MASGN) return CHILDREN(1, VIEW(node, NODE_DVAR));
        if (data->type == NODE_MASGN) return CHILDREN(3, VIEW(node, NODE_DVAR), VIEW(node, NODE_LIST), Qnil);
        if (data->type == NODE_LIST) return CHILDREN(2, CHILD(RB_NODE_FOR(node)->index), Qnil);
        return CHILDREN(2, CHILD(RB_NODE_FOR(node)->collection), VIEW(node, NODE_SCOPE));
      case RB_STATEMENTS_NODE: {
        if (data->type == NODE_BEGIN) return CHILDREN(1, Qnil);
        const rb_node_list2_t *body = &RB_NODE_STATEMENTS(node)->body;
        VALUE children = rb_ary_new_capa(body->size);
        for (size_t i = 0; i < body->size; i++) rb_ary_push(children, CHILD(body->nodes[i]));
        return children;
      }
      case RB_BEGIN_NODE: {
        const rb_begin_node_t *n = RB_NODE_BEGIN(node);
        if (data->type == NODE_BEGIN) {
            if (data->owner->type != RB_DEFINED_NODE) return CHILDREN(1, Qnil);
            return CHILDREN(1, n->ensure_clause ? VIEW(node, NODE_ENSURE) :
                n->rescue_clause ? VIEW(node, NODE_RESCUE) : CHILD(n->statements));
        }
        if (data->type == NODE_ENSURE) return CHILDREN(2,
            n->rescue_clause ? VIEW(node, NODE_RESCUE) : CHILD(n->statements), CHILD(RB_NODE_ENSURE(n->ensure_clause)->statements));
        if (data->type == NODE_RESCUE) return CHILDREN(3, CHILD(n->statements), CHILD(n->rescue_clause), CHILD(n->else_clause));
        VALUE children = CHILDREN(1, VIEW(node, NODE_BEGIN));
        VALUE body = CHILD(n->statements);
        if (!NIL_P(body)) {
            struct ASTNodeData *body_data;
            TypedData_Get_Struct(body, struct ASTNodeData, &rb_node_type, body_data);
            if (body_data->type == NODE_BLOCK) rb_ary_concat(children, node_children(body_data));
            else rb_ary_push(children, body);
        }
        return children;
      }
      case RB_RESCUE_MODIFIER_NODE:
        if (data->type == NODE_RESBODY) return CHILDREN(4, Qnil, Qnil, CHILD(RB_NODE_RESCUE_MODIFIER(node)->rescue_expression), Qnil);
        return CHILDREN(3, CHILD(RB_NODE_RESCUE_MODIFIER(node)->expression), VIEW(node, NODE_RESBODY), Qnil);
      case RB_RESCUE_NODE: {
        const rb_rescue_node_t *n = RB_NODE_RESCUE(node);
        return CHILDREN(4, ast_arguments(data, node, &n->exceptions, n->exceptions.size), owned_child(data, n->reference, node), CHILD(n->statements), CHILD(n->subsequent));
      }
      case RB_UNDEF_NODE: {
        const rb_node_list2_t *list = &RB_NODE_UNDEF(node)->names;
        VALUE children = rb_ary_new_capa(list->size);
        for (size_t i = 0; i < list->size; i++) rb_ary_push(children, CHILD(list->nodes[i]));
        return CHILDREN(1, children);
      }
      case RB_DEF_NODE: {
        const rb_def_node_t *n = RB_NODE_DEF(node);
        if (n->receiver) return CHILDREN(3, CHILD(n->receiver), var_name(n->name), VIEW(node, NODE_SCOPE));
        return CHILDREN(2, var_name(n->name), VIEW(node, NODE_SCOPE));
      }
      case RB_LAMBDA_NODE: return CHILDREN(1, VIEW(node, NODE_SCOPE));
      case RB_CALL_NODE: {
        const rb_call_node_t *n = RB_NODE_CALL(node);
        if (data->type == NODE_ITER) return CHILDREN(2, VIEW(node, call_type(n)), CHILD(n->block));
        if (data->type == NODE_MATCH2) return CHILDREN(2, CHILD(n->receiver), CHILD(RB_NODE_ARGUMENTS(n->arguments)->arguments.nodes[0]));
        if (data->type == NODE_MATCH3) return CHILDREN(2, CHILD(RB_NODE_ARGUMENTS(n->arguments)->arguments.nodes[0]), CHILD(n->receiver));
        VALUE args = CHILD(n->arguments);
        if (n->block && n->block->type == RB_BLOCK_ARGUMENT_NODE) args = VIEW(node, NODE_BLOCK_PASS);
        if (data->type == NODE_BLOCK_PASS) return CHILDREN(2, CHILD(n->arguments), CHILD(RB_NODE_BLOCK_ARGUMENT(n->block)->expression));
        if (data->type == NODE_VCALL) return CHILDREN(1, var_name(n->name));
        if (data->type == NODE_FCALL) return CHILDREN(2, var_name(n->name), args);
        return CHILDREN(3, CHILD(n->receiver), var_name(n->name), args);
      }
      case RB_SUPER_NODE: {
        const rb_super_node_t *n = RB_NODE_SUPER(node);
        if (data->type == NODE_ITER) return CHILDREN(2, VIEW(node, NODE_SUPER), CHILD(n->block));
        return CHILDREN(1, CHILD(n->arguments));
      }
      case RB_FORWARDING_SUPER_NODE:
        if (data->type == NODE_ITER) return CHILDREN(2, VIEW(node, NODE_ZSUPER), CHILD(RB_NODE_FORWARDING_SUPER(node)->block));
        return rb_ary_new();
      case RB_CLASS_NODE: return CHILDREN(3, (RB_NODE_CLASS(node)->constant_path->type == RB_CONSTANT_READ_NODE ? VIEW(RB_NODE_CLASS(node)->constant_path, NODE_COLON2) : CHILD(RB_NODE_CLASS(node)->constant_path)), CHILD(RB_NODE_CLASS(node)->superclass), VIEW(node, NODE_SCOPE));
      case RB_MODULE_NODE: return CHILDREN(2, (RB_NODE_MODULE(node)->constant_path->type == RB_CONSTANT_READ_NODE ? VIEW(RB_NODE_MODULE(node)->constant_path, NODE_COLON2) : CHILD(RB_NODE_MODULE(node)->constant_path)), VIEW(node, NODE_SCOPE));
      case RB_SINGLETON_CLASS_NODE: return CHILDREN(2, CHILD(RB_NODE_SINGLETON_CLASS(node)->expression), VIEW(node, NODE_SCOPE));
      case RB_CONSTANT_PATH_TARGET_NODE:
        if (data->type == NODE_CDECL) return CHILDREN(3, VIEW(node, RB_NODE_CONSTANT_PATH_TARGET(node)->parent ? NODE_COLON2 : NODE_COLON3),
            var_name(RB_NODE_CONSTANT_PATH_TARGET(node)->name), data->owner->type == RB_RESCUE_NODE ? VIEW(node, NODE_ERRINFO) : Qnil);
        /* fall through */
      case RB_CONSTANT_PATH_NODE:
        if (data->type == NODE_COLON3) return CHILDREN(1, var_name(RB_NODE_CONSTANT_PATH(node)->name));
        return CHILDREN(2, CHILD(RB_NODE_CONSTANT_PATH(node)->parent), var_name(RB_NODE_CONSTANT_PATH(node)->name));
      case RB_CONSTANT_PATH_WRITE_NODE: return CHILDREN(3, CHILD(RB_NODE_CONSTANT_PATH_WRITE(node)->target),
          var_name(RB_NODE_CONSTANT_PATH(RB_NODE_CONSTANT_PATH_WRITE(node)->target)->name), CHILD(RB_NODE_CONSTANT_PATH_WRITE(node)->value));
      case RB_AND_NODE: case RB_OR_NODE: {
        VALUE array = rb_ary_new();
        int type = node->type;
        while (node && node->type == type) {
            rb_ary_push(array, CHILD(RB_NODE_AND(node)->left));
            node = RB_NODE_AND(node)->right;
        }
        rb_ary_push(array, CHILD(node));
        return array;
      }
      case RB_HASH_NODE: case RB_KEYWORD_HASH_NODE: {
        const rb_node_list2_t *elements = node->type == RB_HASH_NODE ? &RB_NODE_HASH(node)->elements : &RB_NODE_KEYWORD_HASH(node)->elements;
        if (data->type == NODE_HASH) return CHILDREN(1, elements->size ? VIEW(node, NODE_LIST) : Qnil);
        VALUE children = rb_ary_new_capa(elements->size * 2 + 1);
        for (size_t i = 0; i < elements->size; i++) {
            const rb_node_t *element = elements->nodes[i];
            if (element->type == RB_ASSOC_NODE) {
                rb_ary_push(children, CHILD(RB_NODE_ASSOC(element)->key));
                rb_ary_push(children, CHILD(RB_NODE_ASSOC(element)->value));
            }
            else {
                rb_ary_push(children, Qnil);
                rb_ary_push(children, CHILD(RB_NODE_ASSOC_SPLAT(element)->value));
            }
        }
        rb_ary_push(children, Qnil);
        return children;
      }
            case RB_NIL_NODE: return rb_ary_new();
      case RB_TRUE_NODE: return rb_ary_new();
      case RB_FALSE_NODE: return rb_ary_new();
      case RB_SELF_NODE: return rb_ary_new();
      case RB_REDO_NODE: return rb_ary_new();
      case RB_RETRY_NODE: return rb_ary_new();
      case RB_MISSING_NODE: return rb_ary_new();
      case RB_ARRAY_NODE: return rb_ary_new();
      case RB_BREAK_NODE: {
        const rb_node_t *args = (const rb_node_t *)RB_NODE_BREAK(node)->arguments;
        if (args && args->type == RB_ARGUMENTS_NODE && RB_NODE_ARGUMENTS(args)->arguments.size == 1) args = RB_NODE_ARGUMENTS(args)->arguments.nodes[0];
        return CHILDREN(1, CHILD(args));
      }
      case RB_NEXT_NODE: {
        const rb_node_t *args = (const rb_node_t *)RB_NODE_NEXT(node)->arguments;
        if (args && args->type == RB_ARGUMENTS_NODE && RB_NODE_ARGUMENTS(args)->arguments.size == 1) args = RB_NODE_ARGUMENTS(args)->arguments.nodes[0];
        return CHILDREN(1, CHILD(args));
      }
      case RB_RETURN_NODE: {
        const rb_node_t *args = (const rb_node_t *)RB_NODE_RETURN(node)->arguments;
        if (args && args->type == RB_ARGUMENTS_NODE && RB_NODE_ARGUMENTS(args)->arguments.size == 1) args = RB_NODE_ARGUMENTS(args)->arguments.nodes[0];
        return CHILDREN(1, CHILD(args));
      }
      case RB_IF_NODE: {
        const rb_if_node_t *n = RB_NODE_IF(node);
        bool empty_error_body = n->predicate && n->predicate->type == RB_MISSING_NODE && n->statements && !n->statements->body.size;
        return CHILDREN(3, CHILD(n->predicate), empty_error_body ? Qnil : CHILD(n->statements), CHILD(n->subsequent));
      }
      case RB_UNLESS_NODE: return CHILDREN(3, CHILD(RB_NODE_UNLESS(node)->predicate), CHILD(RB_NODE_UNLESS(node)->statements), CHILD(RB_NODE_UNLESS(node)->else_clause));
      case RB_EMBEDDED_STATEMENTS_NODE: return CHILDREN(1, CHILD(RB_NODE_EMBEDDED_STATEMENTS(node)->statements));
      case RB_EMBEDDED_VARIABLE_NODE: return CHILDREN(1, CHILD(RB_NODE_EMBEDDED_VARIABLE(node)->variable));
      case RB_RANGE_NODE: return CHILDREN(2, CHILD(RB_NODE_RANGE(node)->left), CHILD(RB_NODE_RANGE(node)->right));
      case RB_FLIP_FLOP_NODE: return CHILDREN(2, CHILD(RB_NODE_FLIP_FLOP(node)->left), CHILD(RB_NODE_FLIP_FLOP(node)->right));
      case RB_SPLAT_NODE: return CHILDREN(1, CHILD(RB_NODE_SPLAT(node)->expression));
      case RB_BLOCK_ARGUMENT_NODE: return CHILDREN(2, Qnil, CHILD(RB_NODE_BLOCK_ARGUMENT(node)->expression));
      case RB_DEFINED_NODE: {
        if (data->type == NODE_BLOCK) return CHILDREN(1, defined_original_child(data, RB_NODE_DEFINED(node)->value));
        return CHILDREN(1, RB_NODE_FLAG_P(node, RB_DEFINED_NODE_FLAGS_FORCE_EXPRESSION) ? VIEW(node, NODE_BLOCK) :
            CHILD(rb_node_defined_value(RB_NODE_DEFINED(node))));
      }
      case RB_YIELD_NODE: return CHILDREN(1, CHILD(RB_NODE_YIELD(node)->arguments));
      case RB_POST_EXECUTION_NODE: return CHILDREN(1, VIEW(node, NODE_SCOPE));
      case RB_PRE_EXECUTION_NODE: return CHILDREN(1, CHILD(RB_NODE_PRE_EXECUTION(node)->statements));
      case RB_PARENTHESES_NODE: return CHILDREN(1, CHILD(RB_NODE_PARENTHESES(node)->body));
      case RB_PINNED_VARIABLE_NODE: return CHILDREN(1, CHILD(RB_NODE_PINNED_VARIABLE(node)->variable));
      case RB_PINNED_EXPRESSION_NODE: return CHILDREN(1, CHILD(RB_NODE_PINNED_EXPRESSION(node)->expression));
      case RB_ENSURE_NODE: return CHILDREN(2, Qnil, CHILD(RB_NODE_ENSURE(node)->statements));
      case RB_UNTIL_NODE: return CHILDREN(3, CHILD(RB_NODE_UNTIL(node)->predicate), CHILD(RB_NODE_UNTIL(node)->statements), RBOOL(!RB_NODE_FLAG_P(node, RB_LOOP_FLAGS_BEGIN_MODIFIER)));
      case RB_WHILE_NODE: return CHILDREN(3, CHILD(RB_NODE_WHILE(node)->predicate), CHILD(RB_NODE_WHILE(node)->statements), RBOOL(!RB_NODE_FLAG_P(node, RB_LOOP_FLAGS_BEGIN_MODIFIER)));
      case RB_LOCAL_VARIABLE_READ_NODE: return CHILDREN(1, var_name(RB_NODE_LOCAL_VARIABLE_READ(node)->name));
      case RB_LOCAL_VARIABLE_TARGET_NODE:
        if (data->type == NODE_SYM) return CHILDREN(1, var_name(RB_NODE_LOCAL_VARIABLE_TARGET(node)->name));
        return CHILDREN(2, var_name(RB_NODE_LOCAL_VARIABLE_TARGET(node)->name),
            data->owner->type == RB_FOR_NODE ? VIEW(data->owner, NODE_DVAR) :
            data->owner->type == RB_MATCH_WRITE_NODE ? VIEW(node, NODE_SYM) :
            data->owner->type == RB_RESCUE_NODE ? VIEW(node, NODE_ERRINFO) : Qnil);
      case RB_LOCAL_VARIABLE_WRITE_NODE: return CHILDREN(2, var_name(RB_NODE_LOCAL_VARIABLE_WRITE(node)->name),
          data->owner->type == RB_FOR_NODE ? VIEW(data->owner, NODE_DVAR) : CHILD(RB_NODE_LOCAL_VARIABLE_WRITE(node)->value));
      case RB_CLASS_VARIABLE_READ_NODE: return CHILDREN(1, var_name(RB_NODE_CLASS_VARIABLE_READ(node)->name));
      case RB_CLASS_VARIABLE_TARGET_NODE: return CHILDREN(2, var_name(RB_NODE_CLASS_VARIABLE_TARGET(node)->name), data->owner->type == RB_RESCUE_NODE ? VIEW(node, NODE_ERRINFO) : Qnil);
      case RB_CLASS_VARIABLE_WRITE_NODE: return CHILDREN(2, var_name(RB_NODE_CLASS_VARIABLE_WRITE(node)->name), CHILD(RB_NODE_CLASS_VARIABLE_WRITE(node)->value));
      case RB_INSTANCE_VARIABLE_READ_NODE: return CHILDREN(1, var_name(RB_NODE_INSTANCE_VARIABLE_READ(node)->name));
      case RB_INSTANCE_VARIABLE_TARGET_NODE: return CHILDREN(2, var_name(RB_NODE_INSTANCE_VARIABLE_TARGET(node)->name), data->owner->type == RB_RESCUE_NODE ? VIEW(node, NODE_ERRINFO) : Qnil);
      case RB_INSTANCE_VARIABLE_WRITE_NODE: return CHILDREN(2, var_name(RB_NODE_INSTANCE_VARIABLE_WRITE(node)->name), CHILD(RB_NODE_INSTANCE_VARIABLE_WRITE(node)->value));
      case RB_GLOBAL_VARIABLE_READ_NODE: return CHILDREN(1, var_name(RB_NODE_GLOBAL_VARIABLE_READ(node)->name));
      case RB_GLOBAL_VARIABLE_TARGET_NODE: return CHILDREN(2, var_name(RB_NODE_GLOBAL_VARIABLE_TARGET(node)->name), data->owner->type == RB_RESCUE_NODE ? VIEW(node, NODE_ERRINFO) : Qnil);
      case RB_GLOBAL_VARIABLE_WRITE_NODE: return CHILDREN(2, var_name(RB_NODE_GLOBAL_VARIABLE_WRITE(node)->name), CHILD(RB_NODE_GLOBAL_VARIABLE_WRITE(node)->value));
      case RB_CONSTANT_READ_NODE:
        if (data->type == NODE_COLON2) return CHILDREN(2, Qnil, var_name(RB_NODE_CONSTANT_READ(node)->name));
        return CHILDREN(1, var_name(RB_NODE_CONSTANT_READ(node)->name));
      case RB_CONSTANT_TARGET_NODE: return CHILDREN(2, var_name(RB_NODE_CONSTANT_TARGET(node)->name), data->owner->type == RB_RESCUE_NODE ? VIEW(node, NODE_ERRINFO) : Qnil);
      case RB_CONSTANT_WRITE_NODE: return CHILDREN(2, var_name(RB_NODE_CONSTANT_WRITE(node)->name), CHILD(RB_NODE_CONSTANT_WRITE(node)->value));
      case RB_REQUIRED_PARAMETER_NODE: return CHILDREN(2, var_name(RB_NODE_REQUIRED_PARAMETER(node)->name), Qnil);
      case RB_OPTIONAL_PARAMETER_NODE: return CHILDREN(2, var_name(RB_NODE_OPTIONAL_PARAMETER(node)->name), CHILD(RB_NODE_OPTIONAL_PARAMETER(node)->value));
      case RB_REQUIRED_KEYWORD_PARAMETER_NODE: return CHILDREN(2, var_name(RB_NODE_REQUIRED_KEYWORD_PARAMETER(node)->name), special_name("NODE_SPECIAL_REQUIRED_KEYWORD"));
      case RB_OPTIONAL_KEYWORD_PARAMETER_NODE: return CHILDREN(2, var_name(RB_NODE_OPTIONAL_KEYWORD_PARAMETER(node)->name), CHILD(RB_NODE_OPTIONAL_KEYWORD_PARAMETER(node)->value));
      case RB_KEYWORD_REST_PARAMETER_NODE: return CHILDREN(1, RB_NODE_KEYWORD_REST_PARAMETER(node)->name ? var_name(RB_NODE_KEYWORD_REST_PARAMETER(node)->name) : special_name("**"));
      case RB_REST_PARAMETER_NODE: return CHILDREN(1, var_name(RB_NODE_REST_PARAMETER(node)->name));
      case RB_FORWARDING_PARAMETER_NODE: return CHILDREN(1, special_name("**"));
      case RB_NO_KEYWORDS_PARAMETER_NODE: return rb_ary_new();
      case RB_IT_LOCAL_VARIABLE_READ_NODE: return CHILDREN(1, ID2SYM(idItImplicit));
      case RB_INTEGER_NODE: return CHILDREN(1, rb_node_integer_literal_val2(node));
      case RB_FLOAT_NODE: return CHILDREN(1, rb_node_float_literal_val2(node));
      case RB_RATIONAL_NODE: return CHILDREN(1, rb_node_rational_literal_val2(node));
      case RB_IMAGINARY_NODE: return CHILDREN(1, rb_node_imaginary_literal_val2(node));
      case RB_STRING_NODE: return CHILDREN(1, rb_node_str_string_val2(node));
      case RB_X_STRING_NODE: return CHILDREN(1, rb_node_str_string_val2(node));
      case RB_SYMBOL_NODE: return CHILDREN(1, rb_node_sym_string_val2(node));
      case RB_REGULAR_EXPRESSION_NODE: return CHILDREN(1, rb_node_regx_string_val2(node));
      case RB_MATCH_LAST_LINE_NODE: return CHILDREN(1, rb_node_regx_string_val2(node));
      case RB_SOURCE_LINE_NODE: return CHILDREN(1, rb_node_line_lineno_val2(node));
      case RB_SOURCE_FILE_NODE: return CHILDREN(1, rb_node_file_path_val2(node));
      case RB_SOURCE_ENCODING_NODE: return CHILDREN(1, rb_node_encoding_val2(node));
      case RB_ALIAS_METHOD_NODE: return CHILDREN(2, CHILD(RB_NODE_ALIAS_METHOD(node)->new_name), CHILD(RB_NODE_ALIAS_METHOD(node)->old_name));
      case RB_ALIAS_GLOBAL_VARIABLE_NODE: return CHILDREN(2, var_name(RB_NODE_GLOBAL_VARIABLE_READ(RB_NODE_ALIAS_GLOBAL_VARIABLE(node)->new_name)->name), var_name(RB_NODE_GLOBAL_VARIABLE_READ(RB_NODE_ALIAS_GLOBAL_VARIABLE(node)->old_name)->name));
      case RB_BACK_REFERENCE_READ_NODE: return CHILDREN(1, var_name(RB_NODE_BACK_REFERENCE_READ(node)->name));
      case RB_NUMBERED_REFERENCE_READ_NODE: {
        char name[32];
        snprintf(name, sizeof(name), "$%u", RB_NODE_NUMBERED_REFERENCE_READ(node)->number);
        return CHILDREN(1, special_name(name));
      }
      case RB_INTERPOLATED_STRING_NODE: {
        const rb_node_list2_t *parts = &RB_NODE_INTERPOLATED_STRING(node)->parts;
        size_t index = parts->size && parts->nodes[0]->type == RB_STRING_NODE ? 1 : 0;
        VALUE head = index ? rb_node_str_string_val2(parts->nodes[0]) : rb_enc_str_new("", 0, rb_ruby_ast_data_get(data->ast_value)->body.encoding);
        return CHILDREN(3, head, index < parts->size ? CHILD(parts->nodes[index]) : Qnil,
            ast_list(data, node, parts, index + 1, parts->size > index ? parts->size - index - 1 : 0, NODE_LIST));
      }
      case RB_INTERPOLATED_SYMBOL_NODE: {
        const rb_node_list2_t *parts = &RB_NODE_INTERPOLATED_SYMBOL(node)->parts;
        size_t index = parts->size && parts->nodes[0]->type == RB_STRING_NODE ? 1 : 0;
        VALUE head = index ? rb_node_str_string_val2(parts->nodes[0]) : rb_enc_str_new("", 0, rb_ruby_ast_data_get(data->ast_value)->body.encoding);
        return CHILDREN(3, head, index < parts->size ? CHILD(parts->nodes[index]) : Qnil,
            ast_list(data, node, parts, index + 1, parts->size > index ? parts->size - index - 1 : 0, NODE_LIST));
      }
      case RB_INTERPOLATED_X_STRING_NODE: {
        const rb_node_list2_t *parts = &RB_NODE_INTERPOLATED_X_STRING(node)->parts;
        size_t index = parts->size && parts->nodes[0]->type == RB_STRING_NODE ? 1 : 0;
        VALUE head = index ? rb_node_str_string_val2(parts->nodes[0]) : rb_enc_str_new("", 0, rb_ruby_ast_data_get(data->ast_value)->body.encoding);
        return CHILDREN(3, head, index < parts->size ? CHILD(parts->nodes[index]) : Qnil,
            ast_list(data, node, parts, index + 1, parts->size > index ? parts->size - index - 1 : 0, NODE_LIST));
      }
      case RB_INTERPOLATED_MATCH_LAST_LINE_NODE:
        if (data->type == NODE_MATCH2) return CHILDREN(2, VIEW(node, NODE_DREGX), VIEW(node, NODE_GVAR));
        if (data->type == NODE_GVAR) return CHILDREN(1, special_name("$_"));
        /* fall through */
      case RB_INTERPOLATED_REGULAR_EXPRESSION_NODE: {
        if (data->type == NODE_ONCE) return CHILDREN(1, VIEW(node, NODE_DREGX));
        const rb_node_list2_t *parts = &RB_NODE_INTERPOLATED_REGULAR_EXPRESSION(node)->parts;
        size_t index = parts->size && parts->nodes[0]->type == RB_STRING_NODE ? 1 : 0;
        VALUE head = index ? rb_node_str_string_val2(parts->nodes[0]) : rb_enc_str_new("", 0, rb_ruby_ast_data_get(data->ast_value)->body.encoding);
        return CHILDREN(3, head, index < parts->size ? CHILD(parts->nodes[index]) : Qnil,
            ast_list(data, node, parts, index + 1, parts->size > index ? parts->size - index - 1 : 0, NODE_LIST));
      }
      case RB_CALL_AND_WRITE_NODE: return CHILDREN(5, CHILD(RB_NODE_CALL_AND_WRITE(node)->receiver), RBOOL(RB_NODE_FLAG_P(node, RB_CALL_NODE_FLAGS_SAFE_NAVIGATION)), var_name(RB_NODE_CALL_AND_WRITE(node)->read_name), ID2SYM(idANDOP), CHILD(RB_NODE_CALL_AND_WRITE(node)->value));
      case RB_CALL_OR_WRITE_NODE: return CHILDREN(5, CHILD(RB_NODE_CALL_OR_WRITE(node)->receiver), RBOOL(RB_NODE_FLAG_P(node, RB_CALL_NODE_FLAGS_SAFE_NAVIGATION)), var_name(RB_NODE_CALL_OR_WRITE(node)->read_name), ID2SYM(idOROP), CHILD(RB_NODE_CALL_OR_WRITE(node)->value));
      case RB_CALL_OPERATOR_WRITE_NODE: return CHILDREN(5, CHILD(RB_NODE_CALL_OPERATOR_WRITE(node)->receiver), RBOOL(RB_NODE_FLAG_P(node, RB_CALL_NODE_FLAGS_SAFE_NAVIGATION)), var_name(RB_NODE_CALL_OPERATOR_WRITE(node)->read_name), var_name(RB_NODE_CALL_OPERATOR_WRITE(node)->binary_operator), CHILD(RB_NODE_CALL_OPERATOR_WRITE(node)->value));
      case RB_INDEX_AND_WRITE_NODE: return CHILDREN(4, CHILD(RB_NODE_INDEX_AND_WRITE(node)->receiver), ID2SYM(idANDOP), CHILD(RB_NODE_INDEX_AND_WRITE(node)->arguments), CHILD(RB_NODE_INDEX_AND_WRITE(node)->value));
      case RB_INDEX_OR_WRITE_NODE: return CHILDREN(4, CHILD(RB_NODE_INDEX_OR_WRITE(node)->receiver), ID2SYM(idOROP), CHILD(RB_NODE_INDEX_OR_WRITE(node)->arguments), CHILD(RB_NODE_INDEX_OR_WRITE(node)->value));
      case RB_INDEX_OPERATOR_WRITE_NODE: return CHILDREN(4, CHILD(RB_NODE_INDEX_OPERATOR_WRITE(node)->receiver), var_name(RB_NODE_INDEX_OPERATOR_WRITE(node)->binary_operator), CHILD(RB_NODE_INDEX_OPERATOR_WRITE(node)->arguments), CHILD(RB_NODE_INDEX_OPERATOR_WRITE(node)->value));
      default: rb_raise(rb_eNotImpError, "AST children for %s", rb_node_type_to_str(node->type));
    }
    rb_bug("unknown AST projection for %s", rb_node_type_to_str(node->type));
}

static VALUE
ast_node_children(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);
    return node_children(data);
}

static int
null_loc_p(const rb_code_location_t *loc)
{
    return (loc->beg_pos.lineno == 0 && loc->beg_pos.column == -1 && loc->end_pos.lineno == 0 && loc->end_pos.column == -1);
}

static VALUE
location_new(const rb_code_location_t *loc)
{
    VALUE obj;
    struct ASTLocationData *data;

    if (null_loc_p(loc)) return Qnil;

    obj = TypedData_Make_Struct(rb_cLocation, struct ASTLocationData, &rb_location_type, data);
    data->first_lineno = loc->beg_pos.lineno;
    data->first_column = loc->beg_pos.column;
    data->last_lineno = loc->end_pos.lineno;
    data->last_column = loc->end_pos.column;

    return obj;
}

static VALUE
node_locations(const struct ASTNodeData *data)
{
    const rb_node_t *node = data->node;
    VALUE result = rb_ary_new_from_args(1, location_new(&data->location));
    if (data->type == NODE_CASE3 && node->type != RB_CASE_MATCH_NODE) {
        rb_ary_push(result, Qnil);
        rb_ary_push(result, Qnil);
        return result;
    }
    if (node->type == RB_FORWARDING_ARGUMENTS_NODE || node->type == RB_IMPLICIT_REST_NODE) {
        if (data->type == NODE_SPLAT || data->type == NODE_BLOCK_PASS) rb_ary_push(result, location_new(&node->location));
        return result;
    }
    if (data->type == NODE_OP_ASGN1 && node->type != RB_INDEX_OPERATOR_WRITE_NODE) {
        const rb_index_and_write_node_t *n = RB_NODE_INDEX_AND_WRITE(node);
        rb_ary_push(result, location_new(&n->call_operator_loc));
        rb_ary_push(result, location_new(&n->opening_loc));
        rb_ary_push(result, location_new(&n->closing_loc));
        rb_ary_push(result, location_new(&n->operator_loc));
        return result;
    }
    if (data->type == NODE_OP_ASGN2 && node->type != RB_CALL_OPERATOR_WRITE_NODE) {
        const rb_call_and_write_node_t *n = RB_NODE_CALL_AND_WRITE(node);
        rb_ary_push(result, location_new(&n->call_operator_loc));
        rb_ary_push(result, location_new(&n->message_loc));
        rb_ary_push(result, location_new(&n->operator_loc));
        return result;
    }
    if (data->type == NODE_BLOCK_PASS && node->type == RB_CALL_NODE) {
        rb_ary_push(result, location_new(&RB_NODE_BLOCK_ARGUMENT(RB_NODE_CALL(node)->block)->operator_loc));
        return result;
    }
    if (data->type == NODE_EVSTR && node->type == RB_EMBEDDED_VARIABLE_NODE) {
        rb_ary_push(result, location_new(&RB_NODE_EMBEDDED_VARIABLE(node)->operator_loc));
        rb_ary_push(result, Qnil);
        return result;
    }
    if (data->type == NODE_COLON2 && node->type == RB_CONSTANT_READ_NODE) {
        rb_ary_push(result, Qnil);
        rb_ary_push(result, location_new(&node->location));
        return result;
    }
    if (data->type == NODE_IN && (node->type == RB_MATCH_REQUIRED_NODE || node->type == RB_MATCH_PREDICATE_NODE)) {
        const rb_code_location_t *operator_loc = &RB_NODE_MATCH_REQUIRED(node)->operator_loc;
        rb_ary_push(result, node->type == RB_MATCH_PREDICATE_NODE ? location_new(operator_loc) : Qnil);
        rb_ary_push(result, Qnil);
        rb_ary_push(result, node->type == RB_MATCH_REQUIRED_NODE ? location_new(operator_loc) : Qnil);
        return result;
    }
    if (data->type == NODE_REDO) {
        rb_ary_push(result, location_new(&node->location));
        return result;
    }
    switch (data->type) {
      case NODE_ALIAS:
        rb_ary_push(result, location_new(&RB_NODE_ALIAS_METHOD(node)->keyword_loc));
        break;
      case NODE_AND:
        rb_ary_push(result, location_new(&RB_NODE_AND(node)->operator_loc));
        break;
      case NODE_BLOCK_PASS:
        rb_ary_push(result, location_new(&RB_NODE_BLOCK_ARGUMENT(node)->operator_loc));
        break;
      case NODE_BREAK:
        rb_ary_push(result, location_new(&RB_NODE_BREAK(node)->keyword_loc));
        break;
      case NODE_CASE:
        rb_ary_push(result, location_new(&RB_NODE_CASE(node)->case_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_CASE(node)->end_keyword_loc));
        break;
      case NODE_CASE2:
        rb_ary_push(result, location_new(&RB_NODE_CASE(node)->case_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_CASE(node)->end_keyword_loc));
        break;
      case NODE_CASE3:
        rb_ary_push(result, location_new(&RB_NODE_CASE_MATCH(node)->case_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_CASE_MATCH(node)->end_keyword_loc));
        break;
      case NODE_CLASS:
        rb_ary_push(result, location_new(&RB_NODE_CLASS(node)->class_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_CLASS(node)->inheritance_operator_loc));
        rb_ary_push(result, location_new(&RB_NODE_CLASS(node)->end_keyword_loc));
        break;
      case NODE_COLON2:
        rb_ary_push(result, location_new(&RB_NODE_CONSTANT_PATH(node)->delimiter_loc));
        rb_ary_push(result, location_new(&RB_NODE_CONSTANT_PATH(node)->name_loc));
        break;
      case NODE_COLON3:
        rb_ary_push(result, location_new(&RB_NODE_CONSTANT_PATH(node)->delimiter_loc));
        rb_ary_push(result, location_new(&RB_NODE_CONSTANT_PATH(node)->name_loc));
        break;
      case NODE_DEFINED:
        rb_ary_push(result, location_new(&RB_NODE_DEFINED(node)->keyword_loc));
        break;
      case NODE_DOT2:
        rb_ary_push(result, location_new(&RB_NODE_RANGE(node)->operator_loc));
        break;
      case NODE_DOT3:
        rb_ary_push(result, location_new(&RB_NODE_RANGE(node)->operator_loc));
        break;
      case NODE_EVSTR:
        rb_ary_push(result, location_new(&RB_NODE_EMBEDDED_STATEMENTS(node)->opening_loc));
        rb_ary_push(result, location_new(&RB_NODE_EMBEDDED_STATEMENTS(node)->closing_loc));
        break;
      case NODE_FLIP2:
        rb_ary_push(result, location_new(&RB_NODE_FLIP_FLOP(node)->operator_loc));
        break;
      case NODE_FLIP3:
        rb_ary_push(result, location_new(&RB_NODE_FLIP_FLOP(node)->operator_loc));
        break;
      case NODE_FOR:
        rb_ary_push(result, location_new(&RB_NODE_FOR(node)->for_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_FOR(node)->in_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_FOR(node)->do_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_FOR(node)->end_keyword_loc));
        break;
      case NODE_LAMBDA:
        rb_ary_push(result, location_new(&RB_NODE_LAMBDA(node)->operator_loc));
        rb_ary_push(result, location_new(&RB_NODE_LAMBDA(node)->opening_loc));
        rb_ary_push(result, location_new(&RB_NODE_LAMBDA(node)->closing_loc));
        break;
      case NODE_IF:
        rb_ary_push(result, location_new(&RB_NODE_IF(node)->if_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_IF(node)->then_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_IF(node)->end_keyword_loc));
        break;
      case NODE_IN:
        rb_ary_push(result, location_new(&RB_NODE_IN(node)->in_loc));
        rb_ary_push(result, location_new(&RB_NODE_IN(node)->then_loc));
        rb_ary_push(result, Qnil);
        break;
      case NODE_MODULE:
        rb_ary_push(result, location_new(&RB_NODE_MODULE(node)->module_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_MODULE(node)->end_keyword_loc));
        break;
      case NODE_NEXT:
        rb_ary_push(result, location_new(&RB_NODE_NEXT(node)->keyword_loc));
        break;
      case NODE_OR:
        rb_ary_push(result, location_new(&RB_NODE_OR(node)->operator_loc));
        break;
      case NODE_OP_ASGN1:
        rb_ary_push(result, location_new(&RB_NODE_INDEX_OPERATOR_WRITE(node)->call_operator_loc));
        rb_ary_push(result, location_new(&RB_NODE_INDEX_OPERATOR_WRITE(node)->opening_loc));
        rb_ary_push(result, location_new(&RB_NODE_INDEX_OPERATOR_WRITE(node)->closing_loc));
        rb_ary_push(result, location_new(&RB_NODE_INDEX_OPERATOR_WRITE(node)->binary_operator_loc));
        break;
      case NODE_OP_ASGN2:
        rb_ary_push(result, location_new(&RB_NODE_CALL_OPERATOR_WRITE(node)->call_operator_loc));
        rb_ary_push(result, location_new(&RB_NODE_CALL_OPERATOR_WRITE(node)->message_loc));
        rb_ary_push(result, location_new(&RB_NODE_CALL_OPERATOR_WRITE(node)->binary_operator_loc));
        break;
      case NODE_POSTEXE:
        rb_ary_push(result, location_new(&RB_NODE_POST_EXECUTION(node)->keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_POST_EXECUTION(node)->opening_loc));
        rb_ary_push(result, location_new(&RB_NODE_POST_EXECUTION(node)->closing_loc));
        break;
      case NODE_REDO:
        rb_ary_push(result, Qnil);
        break;
      case NODE_REGX:
        rb_ary_push(result, location_new(&RB_NODE_REGULAR_EXPRESSION(node)->opening_loc));
        rb_ary_push(result, location_new(&RB_NODE_REGULAR_EXPRESSION(node)->content_loc));
        rb_ary_push(result, location_new(&RB_NODE_REGULAR_EXPRESSION(node)->closing_loc));
        break;
      case NODE_RETURN:
        rb_ary_push(result, location_new(&RB_NODE_RETURN(node)->keyword_loc));
        break;
      case NODE_SCLASS:
        rb_ary_push(result, location_new(&RB_NODE_SINGLETON_CLASS(node)->class_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_SINGLETON_CLASS(node)->operator_loc));
        rb_ary_push(result, location_new(&RB_NODE_SINGLETON_CLASS(node)->end_keyword_loc));
        break;
      case NODE_SPLAT:
        rb_ary_push(result, location_new(&RB_NODE_SPLAT(node)->operator_loc));
        break;
      case NODE_SUPER:
        rb_ary_push(result, location_new(&RB_NODE_SUPER(node)->keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_SUPER(node)->lparen_loc));
        rb_ary_push(result, location_new(&RB_NODE_SUPER(node)->rparen_loc));
        break;
      case NODE_UNDEF:
        rb_ary_push(result, location_new(&RB_NODE_UNDEF(node)->keyword_loc));
        break;
      case NODE_UNLESS:
        rb_ary_push(result, location_new(&RB_NODE_UNLESS(node)->keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_UNLESS(node)->then_keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_UNLESS(node)->end_keyword_loc));
        break;
      case NODE_VALIAS:
        rb_ary_push(result, location_new(&RB_NODE_ALIAS_GLOBAL_VARIABLE(node)->keyword_loc));
        break;
      case NODE_WHEN:
        rb_ary_push(result, location_new(&RB_NODE_WHEN(node)->keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_WHEN(node)->then_keyword_loc));
        break;
      case NODE_WHILE:
        rb_ary_push(result, location_new(&RB_NODE_WHILE(node)->keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_WHILE(node)->closing_loc));
        break;
      case NODE_UNTIL:
        rb_ary_push(result, location_new(&RB_NODE_UNTIL(node)->keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_UNTIL(node)->closing_loc));
        break;
      case NODE_YIELD:
        rb_ary_push(result, location_new(&RB_NODE_YIELD(node)->keyword_loc));
        rb_ary_push(result, location_new(&RB_NODE_YIELD(node)->lparen_loc));
        rb_ary_push(result, location_new(&RB_NODE_YIELD(node)->rparen_loc));
        break;
      default: break;
    }
    return result;
}
static VALUE
ast_node_locations(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return node_locations(data);
}

static VALUE
ast_node_first_lineno(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(data->location.beg_pos.lineno);
}

static VALUE
ast_node_first_column(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(data->location.beg_pos.column);
}

static VALUE
ast_node_last_lineno(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(data->location.end_pos.lineno);
}

static VALUE
ast_node_last_column(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);

    return INT2NUM(data->location.end_pos.column);
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
    ast = rb_ruby_ast_data_get(data->ast_value);

    parser_tokens = ast->rb_node_buffer->tokens;
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
    rb_ary_freeze(all_tokens);

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
                (ruby_node_name(data->type) + rb_strlen_lit("NODE_")),
                data->location.beg_pos.lineno, data->location.beg_pos.column,
                data->location.end_pos.lineno, data->location.end_pos.column);

    return str;
}

static VALUE
ast_node_script_lines(rb_execution_context_t *ec, VALUE self)
{
    struct ASTNodeData *data;
    rb_ast_t *ast;
    TypedData_Get_Struct(self, struct ASTNodeData, &rb_node_type, data);
    ast = rb_ruby_ast_data_get(data->ast_value);
    rb_parser_ary_t *ret = ast->body.script_lines;
    return rb_parser_build_script_lines_from(ret);
}

static VALUE
ast_location_first_lineno(rb_execution_context_t *ec, VALUE self)
{
    struct ASTLocationData *data;
    TypedData_Get_Struct(self, struct ASTLocationData, &rb_location_type, data);

    return INT2NUM(data->first_lineno);
}

static VALUE
ast_location_first_column(rb_execution_context_t *ec, VALUE self)
{
    struct ASTLocationData *data;
    TypedData_Get_Struct(self, struct ASTLocationData, &rb_location_type, data);

    return INT2NUM(data->first_column);
}

static VALUE
ast_location_last_lineno(rb_execution_context_t *ec, VALUE self)
{
    struct ASTLocationData *data;
    TypedData_Get_Struct(self, struct ASTLocationData, &rb_location_type, data);

    return INT2NUM(data->last_lineno);
}

static VALUE
ast_location_last_column(rb_execution_context_t *ec, VALUE self)
{
    struct ASTLocationData *data;
    TypedData_Get_Struct(self, struct ASTLocationData, &rb_location_type, data);

    return INT2NUM(data->last_column);
}

static VALUE
ast_location_inspect(rb_execution_context_t *ec, VALUE self)
{
    VALUE str;
    VALUE cname;
    struct ASTLocationData *data;
    TypedData_Get_Struct(self, struct ASTLocationData, &rb_location_type, data);

    cname = rb_class_path(rb_obj_class(self));
    str = rb_str_new2("#<");

    rb_str_append(str, cname);
    rb_str_catf(str, ":@%d:%d-%d:%d>",
                data->first_lineno, data->first_column,
                data->last_lineno, data->last_column);

    return str;
}

#include "ast.rbinc"

void
Init_ast(void)
{
    rb_mAST = rb_define_module_under(rb_cRubyVM, "AbstractSyntaxTree");
    rb_cNode = rb_define_class_under(rb_mAST, "Node", rb_cObject);
    rb_cLocation = rb_define_class_under(rb_mAST, "Location", rb_cObject);
    rb_undef_alloc_func(rb_cNode);
    rb_undef_alloc_func(rb_cLocation);
}
