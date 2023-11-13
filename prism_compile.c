#include "prism.h"

#define OLD_ISEQ NEW_ISEQ
#undef NEW_ISEQ

#define NEW_ISEQ(node, name, type, line_no) \
    pm_new_child_iseq(iseq, (node), parser, rb_fstring(name), 0, (type), (line_no))

#define OLD_CHILD_ISEQ NEW_CHILD_ISEQ
#undef NEW_CHILD_ISEQ

#define NEW_CHILD_ISEQ(node, name, type, line_no) \
    pm_new_child_iseq(iseq, (node), parser, rb_fstring(name), iseq, (type), (line_no))

#define PM_COMPILE(node) \
    pm_compile_node(iseq, (node), ret, src, popped, scope_node)

#define PM_COMPILE_INTO_ANCHOR(_ret, node) \
    pm_compile_node(iseq, (node), _ret, src, popped, scope_node)

#define PM_COMPILE_POPPED(node) \
    pm_compile_node(iseq, (node), ret, src, true, scope_node)

#define PM_COMPILE_NOT_POPPED(node) \
    pm_compile_node(iseq, (node), ret, src, false, scope_node)

#define PM_POP \
    ADD_INSN(ret, &dummy_line_node, pop);

#define PM_POP_IF_POPPED \
    if (popped) PM_POP;

#define PM_POP_UNLESS_POPPED \
    if (!popped) PM_POP;

#define PM_DUP \
    ADD_INSN(ret, &dummy_line_node, dup);

#define PM_DUP_UNLESS_POPPED \
    if (!popped) PM_DUP;

#define PM_PUTSELF \
    ADD_INSN(ret, &dummy_line_node, putself);

#define PM_PUTNIL \
    ADD_INSN(ret, &dummy_line_node, putnil);

#define PM_PUTNIL_UNLESS_POPPED \
    if (!popped) PM_PUTNIL;

#define PM_SWAP \
    ADD_INSN(ret, &dummy_line_node, swap);

#define PM_SWAP_UNLESS_POPPED \
    if (!popped) PM_SWAP;

/**
 * We're using the top most bit of a pm_constant_id_t as a tag to represent an
 * anonymous local. When a child iseq is created and needs access to a value
 * that has yet to be defined, or is defined by the parent node's iseq. This can
 * be added to it's local table and then handled accordingly when compiling the
 * scope node associated with the child iseq.
 *
 * See the compilation process for PM_FOR_NODE: as an example, where the
 * variable referenced inside the StatementsNode is defined as part of the top
 * level ForLoop node.
*/
#define TEMP_CONSTANT_IDENTIFIER ((pm_constant_id_t)(1 << 31))

rb_iseq_t *
pm_iseq_new_with_opt(pm_scope_node_t *scope_node, pm_parser_t *parser, VALUE name, VALUE path, VALUE realpath,
                     int first_lineno, const rb_iseq_t *parent, int isolated_depth,
                     enum rb_iseq_type type, const rb_compile_option_t *option);

static VALUE
parse_integer(const pm_integer_node_t *node)
{
    const char *start = (const char *) node->base.location.start;
    const char *end = (const char *) node->base.location.end;

    size_t length = end - start;
    int base = -10;

    switch (node->base.flags & (PM_INTEGER_BASE_FLAGS_BINARY | PM_INTEGER_BASE_FLAGS_DECIMAL | PM_INTEGER_BASE_FLAGS_OCTAL | PM_INTEGER_BASE_FLAGS_HEXADECIMAL)) {
      case PM_INTEGER_BASE_FLAGS_BINARY:
        base = 2;
        break;
      case PM_INTEGER_BASE_FLAGS_DECIMAL:
        base = 10;
        break;
      case PM_INTEGER_BASE_FLAGS_OCTAL:
        base = 8;
        break;
      case PM_INTEGER_BASE_FLAGS_HEXADECIMAL:
        base = 16;
        break;
      default:
        rb_bug("Unexpected integer base");
    }

    return rb_int_parse_cstr(start, length, NULL, NULL, base, RB_INT_PARSE_DEFAULT);
}

static VALUE
parse_float(const pm_node_t *node)
{
    const uint8_t *start = node->location.start;
    const uint8_t *end = node->location.end;
    size_t length = end - start;

    char *buffer = malloc(length + 1);
    memcpy(buffer, start, length);

    buffer[length] = '\0';
    VALUE number = DBL2NUM(rb_cstr_to_dbl(buffer, 0));

    free(buffer);
    return number;
}

static VALUE
parse_rational(const pm_node_t *node)
{
    const uint8_t *start = node->location.start;
    const uint8_t *end = node->location.end - 1;
    size_t length = end - start;

    VALUE res;
    if (PM_NODE_TYPE_P(((pm_rational_node_t *)node)->numeric, PM_FLOAT_NODE)) {
        char *buffer = malloc(length + 1);
        memcpy(buffer, start, length);

        buffer[length] = '\0';

        char *decimal = memchr(buffer, '.', length);
        RUBY_ASSERT(decimal);
        size_t seen_decimal = decimal - buffer;
        size_t fraclen = length - seen_decimal - 1;
        memmove(decimal, decimal + 1, fraclen + 1);

        VALUE v = rb_cstr_to_inum(buffer, 10, false);
        res = rb_rational_new(v, rb_int_positive_pow(10, fraclen));

        free(buffer);
    }
    else {
        RUBY_ASSERT(PM_NODE_TYPE_P(((pm_rational_node_t *)node)->numeric, PM_INTEGER_NODE));
        VALUE number = rb_int_parse_cstr((const char *)start, length, NULL, NULL, -10, RB_INT_PARSE_DEFAULT);
        res = rb_rational_raw(number, INT2FIX(1));
    }

    return res;
}

static VALUE
parse_imaginary(pm_imaginary_node_t *node)
{
    VALUE imaginary_part;
    switch (PM_NODE_TYPE(node->numeric)) {
      case PM_FLOAT_NODE: {
        imaginary_part = parse_float(node->numeric);
        break;
      }
      case PM_INTEGER_NODE: {
        imaginary_part = parse_integer((pm_integer_node_t *) node->numeric);
        break;
      }
      case PM_RATIONAL_NODE: {
        imaginary_part = parse_rational(node->numeric);
        break;
      }
      default:
        rb_bug("Unexpected numeric type on imaginary number");
    }

    return rb_complex_raw(INT2FIX(0), imaginary_part);
}

static inline VALUE
parse_string(pm_string_t *string, const pm_parser_t *parser)
{
    rb_encoding *enc = rb_enc_from_index(rb_enc_find_index(parser->encoding.name));
    return rb_enc_str_new((const char *) pm_string_source(string), pm_string_length(string), enc);
}

static inline ID
parse_symbol(const uint8_t *start, const uint8_t *end, pm_parser_t *parser)
{
    rb_encoding *enc = rb_enc_from_index(rb_enc_find_index(parser->encoding.name));
    return rb_intern3((const char *) start, end - start, enc);
}

static inline ID
parse_string_symbol(pm_string_t *string, pm_parser_t *parser)
{
    const uint8_t *start = pm_string_source(string);
    return parse_symbol(start, start + pm_string_length(string), parser);
}

static inline ID
parse_location_symbol(pm_location_t *location, pm_parser_t *parser)
{
    return parse_symbol(location->start, location->end, parser);
}

static int
pm_optimizable_range_item_p(pm_node_t *node)
{
    return (!node || PM_NODE_TYPE_P(node, PM_INTEGER_NODE) || PM_NODE_TYPE_P(node, PM_NIL_NODE));
}

#define RE_OPTION_ENCODING_SHIFT 8

/**
 * Check the prism flags of a regular expression-like node and return the flags
 * that are expected by the CRuby VM.
 */
static int
pm_reg_flags(const pm_node_t *node) {
    int flags = 0;
    int dummy = 0;

    // Check "no encoding" first so that flags don't get clobbered
    // We're calling `rb_char_to_option_kcode` in this case so that
    // we don't need to have access to `ARG_ENCODING_NONE`
    if (node->flags & PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT) {
        rb_char_to_option_kcode('n', &flags, &dummy);
    }

    if (node->flags & PM_REGULAR_EXPRESSION_FLAGS_EUC_JP) {
        rb_char_to_option_kcode('e', &flags, &dummy);
        flags |= ('e' << RE_OPTION_ENCODING_SHIFT);
    }

    if (node->flags & PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J) {
        rb_char_to_option_kcode('s', &flags, &dummy);
        flags |= ('s' << RE_OPTION_ENCODING_SHIFT);
    }

    if (node->flags & PM_REGULAR_EXPRESSION_FLAGS_UTF_8) {
        rb_char_to_option_kcode('u', &flags, &dummy);
        flags |= ('u' << RE_OPTION_ENCODING_SHIFT);
    }

    if (node->flags & PM_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE) {
        flags |= ONIG_OPTION_IGNORECASE;
    }

    if (node->flags & PM_REGULAR_EXPRESSION_FLAGS_MULTI_LINE) {
        flags |= ONIG_OPTION_MULTILINE;
    }

    if (node->flags & PM_REGULAR_EXPRESSION_FLAGS_EXTENDED) {
        flags |= ONIG_OPTION_EXTEND;
    }

    return flags;
}

static rb_encoding *
pm_reg_enc(const pm_regular_expression_node_t *node, const pm_parser_t *parser) {
    if (node->base.flags & PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT) {
        return rb_ascii8bit_encoding();
    }

    if (node->base.flags & PM_REGULAR_EXPRESSION_FLAGS_EUC_JP) {
        return rb_enc_get_from_index(ENCINDEX_EUC_JP);
    }

    if (node->base.flags & PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J) {
        return rb_enc_get_from_index(ENCINDEX_Windows_31J);
    }

    if (node->base.flags & PM_REGULAR_EXPRESSION_FLAGS_UTF_8) {
        return rb_utf8_encoding();
    }

    return rb_enc_from_index(rb_enc_find_index(parser->encoding.name));
}

/**
 * Certain nodes can be compiled literally, which can lead to further
 * optimizations. These nodes will all have the PM_NODE_FLAG_STATIC_LITERAL flag
 * set.
 */
static inline bool
pm_static_literal_p(const pm_node_t *node)
{
    return node->flags & PM_NODE_FLAG_STATIC_LITERAL;
}

static VALUE
pm_new_regex(pm_regular_expression_node_t * cast, const pm_parser_t * parser) {
    VALUE regex_str = parse_string(&cast->unescaped, parser);
    rb_encoding * enc = pm_reg_enc(cast, parser);

    return rb_enc_reg_new(RSTRING_PTR(regex_str), RSTRING_LEN(regex_str), enc, pm_reg_flags((const pm_node_t *)cast));
}

/**
 * Certain nodes can be compiled literally. This function returns the literal
 * value described by the given node. For example, an array node with all static
 * literal values can be compiled into a literal array.
 */
static inline VALUE
pm_static_literal_value(const pm_node_t *node, pm_scope_node_t *scope_node, pm_parser_t *parser)
{
    // Every node that comes into this function should already be marked as
    // static literal. If it's not, then we have a bug somewhere.
    assert(pm_static_literal_p(node));

    switch (PM_NODE_TYPE(node)) {
      case PM_ARRAY_NODE: {
        pm_array_node_t *cast = (pm_array_node_t *) node;
        pm_node_list_t *elements = &cast->elements;

        VALUE value = rb_ary_hidden_new(elements->size);
        for (size_t index = 0; index < elements->size; index++) {
            rb_ary_push(value, pm_static_literal_value(elements->nodes[index], scope_node, parser));
        }

        OBJ_FREEZE(value);
        return value;
      }
      case PM_FALSE_NODE:
        return Qfalse;
      case PM_FLOAT_NODE:
        return parse_float(node);
      case PM_HASH_NODE: {
        pm_hash_node_t *cast = (pm_hash_node_t *) node;
        pm_node_list_t *elements = &cast->elements;

        VALUE array = rb_ary_hidden_new(elements->size * 2);
        for (size_t index = 0; index < elements->size; index++) {
            assert(PM_NODE_TYPE_P(elements->nodes[index], PM_ASSOC_NODE));
            pm_assoc_node_t *cast = (pm_assoc_node_t *) elements->nodes[index];
            VALUE pair[2] = { pm_static_literal_value(cast->key, scope_node, parser), pm_static_literal_value(cast->value, scope_node, parser) };
            rb_ary_cat(array, pair, 2);
        }

        VALUE value = rb_hash_new_with_size(elements->size);
        rb_hash_bulk_insert(RARRAY_LEN(array), RARRAY_CONST_PTR(array), value);

        value = rb_obj_hide(value);
        OBJ_FREEZE(value);
        return value;
      }
      case PM_IMAGINARY_NODE:
        return parse_imaginary((pm_imaginary_node_t *) node);
      case PM_INTEGER_NODE:
        return parse_integer((pm_integer_node_t *) node);
      case PM_NIL_NODE:
        return Qnil;
      case PM_RATIONAL_NODE:
        return parse_rational(node);
      case PM_REGULAR_EXPRESSION_NODE: {
        pm_regular_expression_node_t *cast = (pm_regular_expression_node_t *) node;

        return pm_new_regex(cast, parser);
      }
      case PM_SOURCE_ENCODING_NODE: {
        rb_encoding *encoding = rb_find_encoding(rb_str_new_cstr(scope_node->parser->encoding.name));
        if (!encoding) rb_bug("Encoding not found!");
        return rb_enc_from_encoding(encoding);
      }
      case PM_SOURCE_FILE_NODE: {
        pm_source_file_node_t *cast = (pm_source_file_node_t *)node;
        return cast->filepath.length ? parse_string(&cast->filepath, parser) : rb_fstring_lit("<compiled>");
      }
      case PM_SOURCE_LINE_NODE: {
        int source_line = (int) pm_newline_list_line_column(&scope_node->parser->newline_list, node->location.start).line;
        // Ruby treats file lines as 1-indexed
        // TODO: Incorporate options which allow for passing a line number
        source_line += 1;
        return INT2FIX(source_line);
      }
      case PM_STRING_NODE:
        return parse_string(&((pm_string_node_t *) node)->unescaped, parser);
      case PM_SYMBOL_NODE:
        return ID2SYM(parse_string_symbol(&((pm_symbol_node_t *) node)->unescaped, parser));
      case PM_TRUE_NODE:
        return Qtrue;
      default:
        rb_raise(rb_eArgError, "Don't have a literal value for this type");
        return Qfalse;
    }
}

static void
pm_compile_branch_condition(rb_iseq_t *iseq, LINK_ANCHOR *const ret, const pm_node_t *cond,
                         LABEL *then_label, LABEL *else_label, const uint8_t *src, bool popped, pm_scope_node_t *scope_node);

static void
pm_compile_logical(rb_iseq_t *iseq, LINK_ANCHOR *const ret, pm_node_t *cond,
                LABEL *then_label, LABEL *else_label, const uint8_t *src, bool popped, pm_scope_node_t *scope_node)
{
    pm_parser_t *parser = scope_node->parser;
    pm_newline_list_t newline_list = parser->newline_list;
    int lineno = (int)pm_newline_list_line_column(&newline_list, cond->location.start).line;
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    DECL_ANCHOR(seq);
    INIT_ANCHOR(seq);
    LABEL *label = NEW_LABEL(lineno);
    if (!then_label) then_label = label;
    else if (!else_label) else_label = label;

    pm_compile_branch_condition(iseq, seq, cond, then_label, else_label, src, popped, scope_node);

    if (LIST_INSN_SIZE_ONE(seq)) {
        INSN *insn = (INSN *)ELEM_FIRST_INSN(FIRST_ELEMENT(seq));
        if (insn->insn_id == BIN(jump) && (LABEL *)(insn->operands[0]) == label)
            return;
    }
    if (!label->refcnt) {
        PM_PUTNIL;
    }
    else {
        ADD_LABEL(seq, label);
    }
    ADD_SEQ(ret, seq);
    return;
}

static void pm_compile_node(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node);

static void
pm_compile_flip_flop(pm_flip_flop_node_t *flip_flop_node, LABEL *else_label, LABEL *then_label, rb_iseq_t *iseq, const int lineno, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(ISEQ_BODY(iseq)->location.first_lineno, -1);
    LABEL *lend = NEW_LABEL(lineno);

    int again = !(flip_flop_node->base.flags & PM_RANGE_FLAGS_EXCLUDE_END);

    rb_num_t count = ISEQ_FLIP_CNT_INCREMENT(ISEQ_BODY(iseq)->local_iseq) + VM_SVAR_FLIPFLOP_START;
    VALUE key = INT2FIX(count);

    ADD_INSN2(ret, &dummy_line_node, getspecial, key, INT2FIX(0));
    ADD_INSNL(ret, &dummy_line_node, branchif, lend);

    if (flip_flop_node->left) {
        PM_COMPILE(flip_flop_node->left);
    }
    else {
        PM_PUTNIL;
    }

    ADD_INSNL(ret, &dummy_line_node, branchunless, else_label);
    ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
    ADD_INSN1(ret, &dummy_line_node, setspecial, key);
    if (!again) {
        ADD_INSNL(ret, &dummy_line_node, jump, then_label);
    }

    ADD_LABEL(ret, lend);
    if (flip_flop_node->right) {
        PM_COMPILE(flip_flop_node->right);
    }
    else {
        PM_PUTNIL;
    }

    ADD_INSNL(ret, &dummy_line_node, branchunless, then_label);
    ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
    ADD_INSN1(ret, &dummy_line_node, setspecial, key);
    ADD_INSNL(ret, &dummy_line_node, jump, then_label);
}

void pm_compile_defined_expr(rb_iseq_t *iseq, const pm_node_t *defined_node, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node,  NODE dummy_line_node, int lineno, bool in_condition);
static void
pm_compile_branch_condition(rb_iseq_t *iseq, LINK_ANCHOR *const ret, const pm_node_t *cond,
                         LABEL *then_label, LABEL *else_label, const uint8_t *src, bool popped, pm_scope_node_t *scope_node)
{
    pm_parser_t *parser = scope_node->parser;
    pm_newline_list_t newline_list = parser->newline_list;
    int lineno = (int) pm_newline_list_line_column(&newline_list, cond->location.start).line;
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

again:
    switch (PM_NODE_TYPE(cond)) {
      case PM_AND_NODE: {
        pm_and_node_t *and_node = (pm_and_node_t *)cond;
        pm_compile_logical(iseq, ret, and_node->left, NULL, else_label, src, popped, scope_node);
        cond = and_node->right;
        goto again;
      }
      case PM_OR_NODE: {
        pm_or_node_t *or_node = (pm_or_node_t *)cond;
        pm_compile_logical(iseq, ret, or_node->left, then_label, NULL, src, popped, scope_node);
        cond = or_node->right;
        goto again;
      }
      case PM_FALSE_NODE:
      case PM_NIL_NODE:
        ADD_INSNL(ret, &dummy_line_node, jump, else_label);
        return;
      case PM_FLOAT_NODE:
      case PM_IMAGINARY_NODE:
      case PM_INTEGER_NODE:
      case PM_LAMBDA_NODE:
      case PM_RATIONAL_NODE:
      case PM_REGULAR_EXPRESSION_NODE:
      case PM_STRING_NODE:
      case PM_SYMBOL_NODE:
      case PM_TRUE_NODE:
        ADD_INSNL(ret, &dummy_line_node, jump, then_label);
        return;
      case PM_FLIP_FLOP_NODE:
        pm_compile_flip_flop((pm_flip_flop_node_t *)cond, else_label, then_label, iseq, lineno, ret, src, popped, scope_node);
        return;
        // TODO: Several more nodes in this case statement
      case PM_DEFINED_NODE: {
        pm_defined_node_t *defined_node = (pm_defined_node_t *)cond;
        pm_compile_defined_expr(iseq, defined_node->value, ret, src, popped, scope_node, dummy_line_node, lineno, true);
        break;
      }
      default: {
        DECL_ANCHOR(cond_seq);
        INIT_ANCHOR(cond_seq);

        pm_compile_node(iseq, cond, cond_seq, src, false, scope_node);
        ADD_SEQ(ret, cond_seq);
        break;
      }
    }
    ADD_INSNL(ret, &dummy_line_node, branchunless, else_label);
    ADD_INSNL(ret, &dummy_line_node, jump, then_label);
    return;
}

static void
pm_compile_if(rb_iseq_t *iseq, const int line, pm_statements_node_t *node_body, pm_node_t *node_else, pm_node_t *predicate, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(line, line);

    DECL_ANCHOR(cond_seq);

    LABEL *then_label, *else_label, *end_label;

    INIT_ANCHOR(cond_seq);
    then_label = NEW_LABEL(line);
    else_label = NEW_LABEL(line);
    end_label = 0;

    pm_compile_branch_condition(iseq, cond_seq, predicate, then_label, else_label, src, false, scope_node);
    ADD_SEQ(ret, cond_seq);

    if (then_label->refcnt) {
        ADD_LABEL(ret, then_label);

        DECL_ANCHOR(then_seq);
        INIT_ANCHOR(then_seq);
        if (node_body) {
            pm_compile_node(iseq, (pm_node_t *)node_body, then_seq, src, popped, scope_node);
        } else {
            PM_PUTNIL_UNLESS_POPPED;
        }

        if (else_label->refcnt) {
            end_label = NEW_LABEL(line);
            ADD_INSNL(then_seq, &dummy_line_node, jump, end_label);
            if (!popped) {
                ADD_INSN(then_seq, &dummy_line_node, pop);
            }
        }
        ADD_SEQ(ret, then_seq);
    }

    if (else_label->refcnt) {
        ADD_LABEL(ret, else_label);

        DECL_ANCHOR(else_seq);
        INIT_ANCHOR(else_seq);
        if (node_else) {
            pm_compile_node(iseq, (pm_node_t *)node_else, else_seq, src, popped, scope_node);
        }
        else {
            PM_PUTNIL_UNLESS_POPPED;
        }

        ADD_SEQ(ret, else_seq);
    }

    if (end_label) {
        ADD_LABEL(ret, end_label);
    }

    return;
}

static void
pm_compile_while(rb_iseq_t *iseq, int lineno, pm_node_flags_t flags, enum pm_node_type type, pm_statements_node_t *statements, pm_node_t *predicate, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    LABEL *prev_start_label = ISEQ_COMPILE_DATA(iseq)->start_label;
    LABEL *prev_end_label = ISEQ_COMPILE_DATA(iseq)->end_label;
    LABEL *prev_redo_label = ISEQ_COMPILE_DATA(iseq)->redo_label;

    // TODO: Deal with ensures in here
    LABEL *next_label = ISEQ_COMPILE_DATA(iseq)->start_label = NEW_LABEL(lineno); /* next  */
    LABEL *redo_label = ISEQ_COMPILE_DATA(iseq)->redo_label = NEW_LABEL(lineno);  /* redo  */
    LABEL *break_label = ISEQ_COMPILE_DATA(iseq)->end_label = NEW_LABEL(lineno);  /* break */
    LABEL *end_label = NEW_LABEL(lineno);
    LABEL *adjust_label = NEW_LABEL(lineno);

    LABEL *next_catch_label = NEW_LABEL(lineno);
    LABEL *tmp_label = NULL;

    // begin; end while true
    if (flags & PM_LOOP_FLAGS_BEGIN_MODIFIER) {
        tmp_label = NEW_LABEL(lineno);
        ADD_INSNL(ret, &dummy_line_node, jump, tmp_label);
    }
    else {
        // while true; end
        ADD_INSNL(ret, &dummy_line_node, jump, next_label);
    }

    ADD_LABEL(ret, adjust_label);
    PM_PUTNIL;
    ADD_LABEL(ret, next_catch_label);
    PM_POP;
    ADD_INSNL(ret, &dummy_line_node, jump, next_label);
    if (tmp_label) ADD_LABEL(ret, tmp_label);

    ADD_LABEL(ret, redo_label);
    if (statements) {
        PM_COMPILE_POPPED((pm_node_t *)statements);
    }

    ADD_LABEL(ret, next_label);

    if (type == PM_WHILE_NODE) {
        pm_compile_branch_condition(iseq, ret, predicate, redo_label, end_label, src, popped, scope_node);
    } else if (type == PM_UNTIL_NODE) {
        pm_compile_branch_condition(iseq, ret, predicate, end_label, redo_label, src, popped, scope_node);
    }

    ADD_LABEL(ret, end_label);
    ADD_ADJUST_RESTORE(ret, adjust_label);

    PM_PUTNIL;

    ADD_LABEL(ret, break_label);

    PM_POP_IF_POPPED;

    ADD_CATCH_ENTRY(CATCH_TYPE_BREAK, redo_label, break_label, NULL,
            break_label);
    ADD_CATCH_ENTRY(CATCH_TYPE_NEXT, redo_label, break_label, NULL,
            next_catch_label);
    ADD_CATCH_ENTRY(CATCH_TYPE_REDO, redo_label, break_label, NULL,
            ISEQ_COMPILE_DATA(iseq)->redo_label);

    ISEQ_COMPILE_DATA(iseq)->start_label = prev_start_label;
    ISEQ_COMPILE_DATA(iseq)->end_label = prev_end_label;
    ISEQ_COMPILE_DATA(iseq)->redo_label = prev_redo_label;
    return;
}

static void
pm_interpolated_node_compile(pm_node_list_t parts, rb_iseq_t *iseq, NODE dummy_line_node, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node, pm_parser_t *parser)
{
    size_t parts_size = parts.size;

    if (parts_size > 0) {
        for (size_t index = 0; index < parts_size; index++) {
            pm_node_t *part = parts.nodes[index];

            if (PM_NODE_TYPE_P(part, PM_STRING_NODE)) {
                pm_string_node_t *string_node = (pm_string_node_t *) part;
                ADD_INSN1(ret, &dummy_line_node, putobject, parse_string(&string_node->unescaped, parser));
            }
            else {
                PM_COMPILE_NOT_POPPED(part);
                PM_DUP;
                ADD_INSN1(ret, &dummy_line_node, objtostring, new_callinfo(iseq, idTo_s, 0, VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE , NULL, FALSE));
                ADD_INSN(ret, &dummy_line_node, anytostring);
            }
        }
    }
    else {
        PM_PUTNIL;
    }
}

static int
pm_lookup_local_index(rb_iseq_t *iseq, pm_scope_node_t *scope_node, pm_constant_id_t constant_id)
{
    st_data_t local_index;

    int num_params = ISEQ_BODY(iseq)->param.size;

    if (!st_lookup(scope_node->index_lookup_table, constant_id, &local_index)) {
        rb_bug("This local does not exist");
    }

    return num_params - (int)local_index;
}

static int
pm_lookup_local_index_with_depth(rb_iseq_t *iseq, pm_scope_node_t *scope_node, pm_constant_id_t constant_id, uint32_t depth)
{
    for(uint32_t i = 0; i < depth; i++) {
        scope_node = scope_node->previous;
        iseq = (rb_iseq_t *)ISEQ_BODY(iseq)->parent_iseq;
    }

    return pm_lookup_local_index(iseq, scope_node, constant_id);
}

// This returns the CRuby ID which maps to the pm_constant_id_t
//
// Constant_ids in prism are indexes of the constants in prism's constant pool.
// We add a constants mapping on the scope_node which is a mapping from
// these constant_id indexes to the CRuby IDs that they represent.
// This helper method allows easy access to those IDs
static ID
pm_constant_id_lookup(pm_scope_node_t *scope_node, pm_constant_id_t constant_id)
{
    if (constant_id < 1 || constant_id > scope_node->parser->constant_pool.size) {
        rb_raise(rb_eArgError, "[PRISM] constant_id out of range: %u", (unsigned int)constant_id);
    }
    return scope_node->constants[constant_id - 1];
}

static rb_iseq_t *
pm_new_child_iseq(rb_iseq_t *iseq, pm_scope_node_t node, pm_parser_t *parser,
               VALUE name, const rb_iseq_t *parent, enum rb_iseq_type type, int line_no)
{
    debugs("[new_child_iseq]> ---------------------------------------\n");
    int isolated_depth = ISEQ_COMPILE_DATA(iseq)->isolated_depth;
    rb_iseq_t * ret_iseq = pm_iseq_new_with_opt(&node, parser, name,
            rb_iseq_path(iseq), rb_iseq_realpath(iseq),
            line_no, parent,
            isolated_depth ? isolated_depth + 1 : 0,
            type, ISEQ_COMPILE_DATA(iseq)->option);
    debugs("[new_child_iseq]< ---------------------------------------\n");
    return ret_iseq;
}

static int
pm_compile_class_path(LINK_ANCHOR *const ret, rb_iseq_t *iseq, const pm_node_t *constant_path_node, const NODE *line_node, const uint8_t * src, bool popped, pm_scope_node_t *scope_node)
{
    if (PM_NODE_TYPE_P(constant_path_node, PM_CONSTANT_PATH_NODE)) {
        pm_node_t *parent = ((pm_constant_path_node_t *)constant_path_node)->parent;
        if (parent) {
            /* Bar::Foo */
            PM_COMPILE(parent);
            return VM_DEFINECLASS_FLAG_SCOPED;
        }
        else {
            /* toplevel class ::Foo */
            ADD_INSN1(ret, line_node, putobject, rb_cObject);
            return VM_DEFINECLASS_FLAG_SCOPED;
        }
    }
    else {
        /* class at cbase Foo */
        ADD_INSN1(ret, line_node, putspecialobject,
                INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        return 0;
    }
}

static void
pm_compile_call_and_or_write_node(bool and_node, pm_node_t *receiver, pm_node_t *value, pm_constant_id_t write_name, pm_constant_id_t read_name, LINK_ANCHOR *const ret, rb_iseq_t *iseq, int lineno, const uint8_t * src, bool popped, pm_scope_node_t *scope_node)
{
    LABEL *call_end_label = NEW_LABEL(lineno);
    LABEL *end_label = NEW_LABEL(lineno);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    int flag = 0;

    if (PM_NODE_TYPE_P(receiver, PM_SELF_NODE)) {
        flag = VM_CALL_FCALL;
    }

    PM_COMPILE_NOT_POPPED(receiver);

    ID write_name_id = pm_constant_id_lookup(scope_node, write_name);
    ID read_name_id = pm_constant_id_lookup(scope_node, read_name);
    PM_DUP;

    ADD_SEND_WITH_FLAG(ret, &dummy_line_node, read_name_id, INT2FIX(0), INT2FIX(flag));

    PM_DUP_UNLESS_POPPED;

    if (and_node) {
        ADD_INSNL(ret, &dummy_line_node, branchunless, call_end_label);
    }
    else {
        // or_node
        ADD_INSNL(ret, &dummy_line_node, branchif, call_end_label);
    }

    PM_POP_UNLESS_POPPED;

    PM_COMPILE_NOT_POPPED(value);
    if (!popped) {
        PM_SWAP;
        ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
    }
    ID aid = rb_id_attrset(write_name_id);
    ADD_SEND_WITH_FLAG(ret, &dummy_line_node, aid, INT2FIX(1), INT2FIX(flag));
    ADD_INSNL(ret, &dummy_line_node, jump, end_label);
    ADD_LABEL(ret, call_end_label);

    if (!popped) {
        PM_SWAP;
    }

    ADD_LABEL(ret, end_label);
    PM_POP;
    return;
}

/**
 * In order to properly compile multiple-assignment, some preprocessing needs to
 * be performed in the case of call or constant path targets. This is when they
 * are read, the "parent" of each of these nodes should only be read once (the
 * receiver in the case of a call, the parent constant in the case of a constant
 * path).
 */
static uint8_t
pm_compile_multi_write_lhs(rb_iseq_t *iseq, NODE dummy_line_node, const pm_node_t *node, LINK_ANCHOR *const ret, pm_scope_node_t *scope_node, uint8_t pushed, bool nested)
{
    switch (PM_NODE_TYPE(node)) {
      case PM_MULTI_TARGET_NODE: {
        pm_multi_target_node_t *cast = (pm_multi_target_node_t *) node;
        for (size_t index = 0; index < cast->lefts.size; index++) {
            pushed = pm_compile_multi_write_lhs(iseq, dummy_line_node, cast->lefts.nodes[index], ret, scope_node, pushed, false);
        }
        break;
      }
      case PM_CONSTANT_PATH_TARGET_NODE: {
        pm_constant_path_target_node_t *cast = (pm_constant_path_target_node_t *)node;
        if (cast->parent) {
            PM_PUTNIL;
            pushed = pm_compile_multi_write_lhs(iseq, dummy_line_node, cast->parent, ret, scope_node, pushed, false);
        } else {
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }
        break;
      }
      case PM_CONSTANT_PATH_NODE: {
        pm_constant_path_node_t *cast = (pm_constant_path_node_t *) node;
        if (cast->parent) {
            pushed = pm_compile_multi_write_lhs(iseq, dummy_line_node, cast->parent, ret, scope_node, pushed, false);
        } else {
            PM_POP;
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }
        pushed = pm_compile_multi_write_lhs(iseq, dummy_line_node, cast->child, ret, scope_node, pushed, cast->parent);
        break;
      }
      case PM_CONSTANT_READ_NODE: {
        pm_constant_read_node_t *cast = (pm_constant_read_node_t *) node;
        ADD_INSN1(ret, &dummy_line_node, putobject, RBOOL(!nested));
        ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(pm_constant_id_lookup(scope_node, cast->name)));
        pushed = pushed + 2;
        break;
      }
      default:
        break;
    }

    return pushed;
}

/**
 * Compile a pattern matching expression.
 */
static int
pm_compile_pattern(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, const uint8_t *src, pm_scope_node_t *scope_node, LABEL *matched_label, LABEL *unmatched_label, bool in_alternation_pattern)
{
    int lineno = (int) pm_newline_list_line_column(&scope_node->parser->newline_list, node->location.start).line;
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    switch (PM_NODE_TYPE(node)) {
      case PM_ARRAY_PATTERN_NODE:
        rb_bug("Array pattern matching not yet supported.");
        break;
      case PM_FIND_PATTERN_NODE:
        rb_bug("Find pattern matching not yet supported.");
        break;
      case PM_HASH_PATTERN_NODE:
        rb_bug("Hash pattern matching not yet supported.");
        break;
      case PM_CAPTURE_PATTERN_NODE:
        rb_bug("Capture pattern matching not yet supported.");
        break;
      case PM_IF_NODE: {
        // If guards can be placed on patterns to further limit matches based on
        // a dynamic predicate. This looks like:
        //
        //     case foo
        //     in bar if baz
        //     end
        //
        pm_if_node_t *cast = (pm_if_node_t *) node;

        pm_compile_pattern(iseq, cast->statements->body.nodes[0], ret, src, scope_node, matched_label, unmatched_label, in_alternation_pattern);
        PM_COMPILE_NOT_POPPED(cast->predicate);

        ADD_INSNL(ret, &dummy_line_node, branchunless, unmatched_label);
        ADD_INSNL(ret, &dummy_line_node, jump, matched_label);
        break;
      }
      case PM_UNLESS_NODE: {
        // Unless guards can be placed on patterns to further limit matches
        // based on a dynamic predicate. This looks like:
        //
        //     case foo
        //     in bar unless baz
        //     end
        //
        pm_unless_node_t *cast = (pm_unless_node_t *) node;

        pm_compile_pattern(iseq, cast->statements->body.nodes[0], ret, src, scope_node, matched_label, unmatched_label, in_alternation_pattern);
        PM_COMPILE_NOT_POPPED(cast->predicate);

        ADD_INSNL(ret, &dummy_line_node, branchif, unmatched_label);
        ADD_INSNL(ret, &dummy_line_node, jump, matched_label);
        break;
      }
      case PM_LOCAL_VARIABLE_TARGET_NODE: {
        // Local variables can be targetted by placing identifiers in the place
        // of a pattern. For example, foo in bar. This results in the value
        // being matched being written to that local variable.
        pm_local_variable_target_node_t *cast = (pm_local_variable_target_node_t *) node;
        int index = pm_lookup_local_index(iseq, scope_node, cast->name);

        // If this local variable is being written from within an alternation
        // pattern, then it cannot actually be added to the local table since
        // it's ambiguous which value should be used. So instead we indicate
        // this with a compile error.
        if (in_alternation_pattern) {
            ID id = pm_constant_id_lookup(scope_node, cast->name);
            const char *name = rb_id2name(id);

            if (name && strlen(name) > 0 && name[0] != '_') {
                COMPILE_ERROR(ERROR_ARGS "illegal variable in alternative pattern (%"PRIsVALUE")", rb_id2str(id));
                return COMPILE_NG;
            }
        }

        ADD_SETLOCAL(ret, &dummy_line_node, index, (int) cast->depth);
        ADD_INSNL(ret, &dummy_line_node, jump, matched_label);
        break;
      }
      case PM_ALTERNATION_PATTERN_NODE: {
        // Alternation patterns allow you to specify multiple patterns in a
        // single expression using the | operator.
        pm_alternation_pattern_node_t *cast = (pm_alternation_pattern_node_t *) node;

        LABEL *matched_left_label = NEW_LABEL(lineno);
        LABEL *unmatched_left_label = NEW_LABEL(lineno);

        // First, we're going to attempt to match against the left pattern. If
        // that pattern matches, then we'll skip matching the right pattern.
        PM_DUP;
        pm_compile_pattern(iseq, cast->left, ret, src, scope_node, matched_left_label, unmatched_left_label, true);

        // If we get here, then we matched on the left pattern. In this case we
        // should pop out the duplicate value that we preemptively added to
        // match against the right pattern and then jump to the match label.
        ADD_LABEL(ret, matched_left_label);
        PM_POP;
        ADD_INSNL(ret, &dummy_line_node, jump, matched_label);
        PM_PUTNIL;

        // If we get here, then we didn't match on the left pattern. In this
        // case we attempt to match against the right pattern.
        ADD_LABEL(ret, unmatched_left_label);
        pm_compile_pattern(iseq, cast->right, ret, src, scope_node, matched_label, unmatched_label, true);
        break;
      }
      case PM_ARRAY_NODE:
      case PM_CLASS_VARIABLE_READ_NODE:
      case PM_CONSTANT_PATH_NODE:
      case PM_CONSTANT_READ_NODE:
      case PM_FALSE_NODE:
      case PM_FLOAT_NODE:
      case PM_GLOBAL_VARIABLE_READ_NODE:
      case PM_IMAGINARY_NODE:
      case PM_INSTANCE_VARIABLE_READ_NODE:
      case PM_INTEGER_NODE:
      case PM_INTERPOLATED_REGULAR_EXPRESSION_NODE:
      case PM_INTERPOLATED_STRING_NODE:
      case PM_INTERPOLATED_SYMBOL_NODE:
      case PM_INTERPOLATED_X_STRING_NODE:
      case PM_LAMBDA_NODE:
      case PM_LOCAL_VARIABLE_READ_NODE:
      case PM_NIL_NODE:
      case PM_RANGE_NODE:
      case PM_RATIONAL_NODE:
      case PM_REGULAR_EXPRESSION_NODE:
      case PM_SELF_NODE:
      case PM_STRING_NODE:
      case PM_SYMBOL_NODE:
      case PM_TRUE_NODE:
      case PM_X_STRING_NODE:
        // These nodes are all simple patterns, which means we'll use the
        // checkmatch instruction to match against them, which is effectively a
        // VM-level === operator.
        PM_COMPILE_NOT_POPPED(node);
        ADD_INSN1(ret, &dummy_line_node, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_CASE));
        ADD_INSNL(ret, &dummy_line_node, branchif, matched_label);
        ADD_INSNL(ret, &dummy_line_node, jump, unmatched_label);
        break;
      case PM_PINNED_VARIABLE_NODE: {
        // Pinned variables are a way to match against the value of a variable
        // without it looking like you're trying to write to the variable. This
        // looks like: foo in ^@bar. To compile these, we compile the variable
        // that they hold.
        pm_pinned_variable_node_t *cast = (pm_pinned_variable_node_t *) node;
        pm_compile_pattern(iseq, cast->variable, ret, src, scope_node, matched_label, unmatched_label, false);
        break;
      }
      case PM_PINNED_EXPRESSION_NODE: {
        // Pinned expressions are a way to match against the value of an
        // expression that should be evaluated at runtime. This looks like:
        // foo in ^(bar). To compile these, we compile the expression that they
        // hold.
        pm_pinned_expression_node_t *cast = (pm_pinned_expression_node_t *) node;
        pm_compile_pattern(iseq, cast->expression, ret, src, scope_node, matched_label, unmatched_label, false);
        break;
      }
      default:
        // If we get here, then we have a node type that should not be in this
        // position. This would be a bug in the parser, because a different node
        // type should never have been created in this position in the tree.
        rb_bug("Unexpected node type in pattern matching expression: %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
        break;
    }

    return COMPILE_OK;
}

// Generate a scope node from the given node.
void
pm_scope_node_init(const pm_node_t *node, pm_scope_node_t *scope, pm_scope_node_t *previous, pm_parser_t *parser)
{
    scope->base.type = PM_SCOPE_NODE;
    scope->base.location.start = node->location.start;
    scope->base.location.end = node->location.end;

    scope->previous = previous;
    scope->parser = parser;
    scope->ast_node = (pm_node_t *)node;
    scope->parameters = NULL;
    scope->body = NULL;
    scope->constants = NULL;
    if (previous) {
        scope->constants = previous->constants;
    }
    scope->index_lookup_table = NULL;

    pm_constant_id_list_init(&scope->locals);

    switch (PM_NODE_TYPE(node)) {
        case PM_BLOCK_NODE: {
            pm_block_node_t *cast = (pm_block_node_t *) node;
            if (cast->parameters) scope->parameters = cast->parameters->parameters;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case PM_CLASS_NODE: {
            pm_class_node_t *cast = (pm_class_node_t *) node;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case PM_DEF_NODE: {
            pm_def_node_t *cast = (pm_def_node_t *) node;
            scope->parameters = cast->parameters;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case PM_ENSURE_NODE: {
            pm_ensure_node_t *cast = (pm_ensure_node_t *)node;
            scope->body = (pm_node_t *)cast->statements;
            break;
        }
        case PM_FOR_NODE: {
            pm_for_node_t *cast = (pm_for_node_t *)node;
            scope->body = (pm_node_t *)cast->statements;
            break;
        }
        case PM_LAMBDA_NODE: {
            pm_lambda_node_t *cast = (pm_lambda_node_t *) node;
            if (cast->parameters) scope->parameters = cast->parameters->parameters;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case PM_MODULE_NODE: {
            pm_module_node_t *cast = (pm_module_node_t *) node;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case PM_POST_EXECUTION_NODE: {
            pm_post_execution_node_t *cast = (pm_post_execution_node_t *) node;
            scope->body = (pm_node_t *) cast->statements;
            break;
        }
        case PM_PROGRAM_NODE: {
            pm_program_node_t *cast = (pm_program_node_t *) node;
            scope->body = (pm_node_t *) cast->statements;
            scope->locals = cast->locals;
            break;
        }
        case PM_SINGLETON_CLASS_NODE: {
            pm_singleton_class_node_t *cast = (pm_singleton_class_node_t *) node;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case PM_STATEMENTS_NODE: {
            pm_statements_node_t *cast = (pm_statements_node_t *) node;
            scope->body = (pm_node_t *)cast;
            break;
        }
        default:
            assert(false && "unreachable");
            break;
    }
}

void
pm_compile_defined_expr0(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node,  NODE dummy_line_node, int lineno, bool in_condition, LABEL **lfinish)
{
    // in_condition is the same as compile.c's needstr
    enum defined_type dtype = DEFINED_NOT_DEFINED;
    switch (PM_NODE_TYPE(node)) {
      case PM_NIL_NODE: {
        dtype = DEFINED_NIL;
        break;
      }
      case PM_SELF_NODE:
        dtype = DEFINED_SELF;
        break;
      case PM_TRUE_NODE:
        dtype = DEFINED_TRUE;
        break;
      case PM_FALSE_NODE:
        dtype = DEFINED_FALSE;
        break;
      case PM_ARRAY_NODE: {
        pm_array_node_t *array_node = (pm_array_node_t *) node;
        for (size_t index = 0; index < array_node->elements.size; index++) {
          pm_compile_defined_expr0(iseq, array_node->elements.nodes[index], ret, src, popped, scope_node, dummy_line_node, lineno, true, lfinish);
          if (!lfinish[1]) {
            lfinish[1] = NEW_LABEL(lineno);
          }
          ADD_INSNL(ret, &dummy_line_node, branchunless, lfinish[1]);
        }
      }
      case PM_STRING_NODE:
      case PM_AND_NODE:
      case PM_OR_NODE:
        dtype = DEFINED_EXPR;
        break;
      case PM_LOCAL_VARIABLE_READ_NODE:
        dtype = DEFINED_LVAR;
        break;
#define PUSH_VAL(type) (in_condition ? Qtrue : rb_iseq_defined_string(type))
      case PM_INSTANCE_VARIABLE_READ_NODE: {
        pm_instance_variable_read_node_t *instance_variable_read_node = (pm_instance_variable_read_node_t *)node;
        ID id = pm_constant_id_lookup(scope_node, instance_variable_read_node->name);
        ADD_INSN3(ret, &dummy_line_node, definedivar,
                  ID2SYM(id), get_ivar_ic_value(iseq, id), PUSH_VAL(DEFINED_IVAR));
        return;
      }
      case PM_GLOBAL_VARIABLE_READ_NODE: {
        pm_global_variable_read_node_t *glabal_variable_read_node = (pm_global_variable_read_node_t *)node;
        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_GVAR),
                  ID2SYM(pm_constant_id_lookup(scope_node, glabal_variable_read_node->name)), PUSH_VAL(DEFINED_GVAR));
        return;
      }
      case PM_CLASS_VARIABLE_READ_NODE: {
        pm_class_variable_read_node_t *class_variable_read_node = (pm_class_variable_read_node_t *)node;
        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CVAR),
                  ID2SYM(pm_constant_id_lookup(scope_node, class_variable_read_node->name)), PUSH_VAL(DEFINED_CVAR));

        return;
      }
      case PM_CONSTANT_READ_NODE: {
        pm_constant_read_node_t *constant_node = (pm_constant_read_node_t *)node;
        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CONST),
                  ID2SYM(pm_constant_id_lookup(scope_node, constant_node->name)), PUSH_VAL(DEFINED_CONST));
        return;
      }
      case PM_CONSTANT_PATH_NODE: {
        pm_constant_path_node_t *constant_path_node = ((pm_constant_path_node_t *)node);
        if (constant_path_node->parent) {
          if (!lfinish[1]) {
            lfinish[1] = NEW_LABEL(lineno);
          }
          pm_compile_defined_expr0(iseq, constant_path_node->parent, ret, src, popped, scope_node, dummy_line_node, lineno, true, lfinish);
          ADD_INSNL(ret, &dummy_line_node, branchunless, lfinish[1]);
          PM_COMPILE(constant_path_node->parent);
        } else {
          ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CONST_FROM),
                  ID2SYM(pm_constant_id_lookup(scope_node, ((pm_constant_read_node_t *)constant_path_node->child)->name)), PUSH_VAL(DEFINED_CONST));
        return;
      }

      case PM_YIELD_NODE:
        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_YIELD), 0,
                  PUSH_VAL(DEFINED_YIELD));
        return;
      case PM_SUPER_NODE:
      case PM_FORWARDING_SUPER_NODE:
        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_ZSUPER), 0,
                  PUSH_VAL(DEFINED_ZSUPER));
        return;
      case PM_CONSTANT_WRITE_NODE:
      case PM_CONSTANT_OPERATOR_WRITE_NODE:
      case PM_CONSTANT_AND_WRITE_NODE:
      case PM_CONSTANT_OR_WRITE_NODE:

      case PM_GLOBAL_VARIABLE_WRITE_NODE:
      case PM_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE:
      case PM_GLOBAL_VARIABLE_AND_WRITE_NODE:
      case PM_GLOBAL_VARIABLE_OR_WRITE_NODE:

      case PM_CLASS_VARIABLE_WRITE_NODE:
      case PM_CLASS_VARIABLE_OPERATOR_WRITE_NODE:
      case PM_CLASS_VARIABLE_AND_WRITE_NODE:
      case PM_CLASS_VARIABLE_OR_WRITE_NODE:

      case PM_INSTANCE_VARIABLE_WRITE_NODE:
      case PM_INSTANCE_VARIABLE_OPERATOR_WRITE_NODE:
      case PM_INSTANCE_VARIABLE_AND_WRITE_NODE:
      case PM_INSTANCE_VARIABLE_OR_WRITE_NODE:

      case PM_LOCAL_VARIABLE_WRITE_NODE:
      case PM_LOCAL_VARIABLE_OPERATOR_WRITE_NODE:
      case PM_LOCAL_VARIABLE_AND_WRITE_NODE:
      case PM_LOCAL_VARIABLE_OR_WRITE_NODE:

      case PM_MULTI_WRITE_NODE:
        dtype = DEFINED_ASGN;
        break;
      default:
        assert(0 && "TODO");
    }

    assert(dtype != DEFINED_NOT_DEFINED);

    ADD_INSN1(ret, &dummy_line_node, putobject, PUSH_VAL(dtype));
#undef PUSH_VAL
}

void
pm_compile_defined_expr(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node, NODE dummy_line_node, int lineno, bool in_condition)
{
    LABEL *lfinish[2];
    LINK_ELEMENT *last = ret->last;

    lfinish[0] = NEW_LABEL(lineno);
    lfinish[1] = 0;

    if (!popped) {
        pm_compile_defined_expr0(iseq, node, ret, src, popped, scope_node, dummy_line_node, lineno, in_condition, lfinish);
    }

    if (lfinish[1]) {
        ELEM_INSERT_NEXT(last, &new_insn_body(iseq, &dummy_line_node, BIN(putnil), 0)->link);
        ADD_INSN(ret, &dummy_line_node, swap);
        ADD_INSN(ret, &dummy_line_node, pop);
        ADD_LABEL(ret, lfinish[1]);
    }
    ADD_LABEL(ret, lfinish[0]);
}

static int
pm_setup_args(pm_arguments_node_t *arguments_node, int *flags, struct rb_callinfo_kwarg **kw_arg, rb_iseq_t *iseq, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node, NODE dummy_line_node, pm_parser_t *parser)
{
    int orig_argc = 0;
    if (arguments_node == NULL) {
        if (*flags & VM_CALL_FCALL) {
            *flags |= VM_CALL_VCALL;
        }
    }
    else {
        pm_node_list_t arguments_node_list = arguments_node->arguments;

        bool has_keyword_splat = (arguments_node->base.flags & PM_ARGUMENTS_NODE_FLAGS_KEYWORD_SPLAT);
        bool has_splat = false;

        // We count the number of elements post the splat node that are not keyword elements to
        // eventually pass as an argument to newarray
        int post_splat_counter = 0;

        for (size_t index = 0; index < arguments_node_list.size; index++) {
            pm_node_t *argument = arguments_node_list.nodes[index];

            switch (PM_NODE_TYPE(argument)) {
                // A keyword hash node contains all keyword arguments as AssocNodes and AssocSplatNodes
              case PM_KEYWORD_HASH_NODE: {
                  pm_keyword_hash_node_t *keyword_arg = (pm_keyword_hash_node_t *)argument;
                  size_t len = keyword_arg->elements.size;

                  if (has_keyword_splat) {
                      int cur_hash_size = 0;
                      orig_argc++;

                      bool new_hash_emitted = false;
                      for (size_t i = 0; i < len; i++) {
                          pm_node_t *cur_node = keyword_arg->elements.nodes[i];

                          pm_node_type_t cur_type = PM_NODE_TYPE(cur_node);

                          switch (PM_NODE_TYPE(cur_node)) {
                            case PM_ASSOC_NODE: {
                                pm_assoc_node_t *assoc = (pm_assoc_node_t *)cur_node;

                                PM_COMPILE(assoc->key);
                                PM_COMPILE(assoc->value);
                                cur_hash_size++;

                                // If we're at the last keyword arg, or the last assoc node of this "set",
                                // then we want to either construct a newhash or merge onto previous hashes
                                if (i == (len - 1) || !PM_NODE_TYPE_P(keyword_arg->elements.nodes[i + 1], cur_type)) {
                                    if (new_hash_emitted) {
                                        ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_ptr, INT2FIX(cur_hash_size * 2 + 1));
                                    }
                                    else {
                                        ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(cur_hash_size * 2));
                                        cur_hash_size = 0;
                                        new_hash_emitted = true;
                                    }
                                }

                                break;
                            }
                            case PM_ASSOC_SPLAT_NODE: {
                                if (len > 1) {
                                    ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                                    if (i == 0) {
                                        ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(0));
                                        new_hash_emitted = true;
                                    }
                                    else {
                                        PM_SWAP;
                                    }
                                }

                                pm_assoc_splat_node_t *assoc_splat = (pm_assoc_splat_node_t *)cur_node;
                                PM_COMPILE(assoc_splat->value);

                                *flags |= VM_CALL_KW_SPLAT | VM_CALL_KW_SPLAT_MUT;

                                if (len > 1) {
                                    ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_kwd, INT2FIX(2));
                                }

                                if ((i < len - 1) && !PM_NODE_TYPE_P(keyword_arg->elements.nodes[i + 1], cur_type)) {
                                    ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                                    PM_SWAP;
                                }

                                cur_hash_size = 0;
                                break;
                            }
                            default: {
                                rb_bug("Unknown type");
                            }
                          }
                      }
                      break;
                  }
                  else {
                      *kw_arg = rb_xmalloc_mul_add(len, sizeof(VALUE), sizeof(struct rb_callinfo_kwarg));
                      *flags |= VM_CALL_KWARG;
                      (*kw_arg)->keyword_len += len;

                      // TODO: Method callers like `foo(a => b)`
                      for (size_t i = 0; i < len; i++) {
                          pm_assoc_node_t *assoc = (pm_assoc_node_t *)keyword_arg->elements.nodes[i];
                          (*kw_arg)->keywords[i] = pm_static_literal_value(assoc->key, scope_node, parser);
                          PM_COMPILE(assoc->value);
                      }
                  }
                  break;
              }
              case PM_SPLAT_NODE: {
                  *flags |= VM_CALL_ARGS_SPLAT;
                  pm_splat_node_t *splat_node = (pm_splat_node_t *)argument;
                  if (splat_node->expression) {
                      orig_argc++;
                      PM_COMPILE_NOT_POPPED(splat_node->expression);
                  }

                  ADD_INSN1(ret, &dummy_line_node, splatarray, popped ? Qfalse : Qtrue);

                  has_splat = true;
                  post_splat_counter = 0;

                  break;
              }
              case PM_FORWARDING_ARGUMENTS_NODE: {
                  orig_argc++;
                  *flags |= VM_CALL_ARGS_BLOCKARG | VM_CALL_ARGS_SPLAT;
                  ADD_GETLOCAL(ret, &dummy_line_node, 3, 0);
                  ADD_INSN1(ret, &dummy_line_node, splatarray, RBOOL(arguments_node_list.size > 1));
                  ADD_INSN2(ret, &dummy_line_node, getblockparamproxy, INT2FIX(4), INT2FIX(0));
                  break;
              }
              default: {
                  orig_argc++;
                  post_splat_counter++;
                  PM_COMPILE_NOT_POPPED(argument);

                  if (has_splat) {
                      // If the next node starts the keyword section of parameters
                      if ((index < arguments_node_list.size - 1) && PM_NODE_TYPE_P(arguments_node_list.nodes[index + 1], PM_KEYWORD_HASH_NODE)) {

                          ADD_INSN1(ret, &dummy_line_node, newarray, INT2FIX(post_splat_counter));
                          ADD_INSN1(ret, &dummy_line_node, splatarray, Qfalse);
                          ADD_INSN(ret, &dummy_line_node, concatarray);
                      }
                      // If it's the final node
                      else if (index == arguments_node_list.size - 1) {
                          ADD_INSN1(ret, &dummy_line_node, newarray, INT2FIX(post_splat_counter));
                          ADD_INSN(ret, &dummy_line_node, concatarray);
                      }
                  }
              }
            }
        }
    }
    return orig_argc;
}

/*
 * Compiles a prism node into instruction sequences
 *
 * iseq -            The current instruction sequence object (used for locals)
 * node -            The prism node to compile
 * ret -             The linked list of instructions to append instructions onto
 * popped -          True if compiling something with no side effects, so instructions don't
 *                   need to be added
 * scope_node - Stores parser and local information
 */
static void
pm_compile_node(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, const uint8_t *src, bool popped, pm_scope_node_t *scope_node)
{
    pm_parser_t *parser = scope_node->parser;
    pm_newline_list_t newline_list = parser->newline_list;
    int lineno = (int)pm_newline_list_line_column(&newline_list, node->location.start).line;
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    switch (PM_NODE_TYPE(node)) {
      case PM_ALIAS_GLOBAL_VARIABLE_NODE: {
        pm_alias_global_variable_node_t *alias_node = (pm_alias_global_variable_node_t *) node;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));

        ADD_INSN1(ret, &dummy_line_node, putobject, ID2SYM(parse_location_symbol(&alias_node->new_name->location, parser)));
        ADD_INSN1(ret, &dummy_line_node, putobject, ID2SYM(parse_location_symbol(&alias_node->old_name->location, parser)));

        ADD_SEND(ret, &dummy_line_node, id_core_set_variable_alias, INT2FIX(2));

        PM_POP_IF_POPPED;
        return;
      }
      case PM_ALIAS_METHOD_NODE: {
        pm_alias_method_node_t *alias_node = (pm_alias_method_node_t *) node;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CBASE));

        PM_COMPILE_NOT_POPPED(alias_node->new_name);
        PM_COMPILE_NOT_POPPED(alias_node->old_name);

        ADD_SEND(ret, &dummy_line_node, id_core_set_method_alias, INT2FIX(3));

        PM_POP_IF_POPPED;

        return;
      }
      case PM_AND_NODE: {
        pm_and_node_t *and_node = (pm_and_node_t *) node;

        LABEL *end_label = NEW_LABEL(lineno);
        PM_COMPILE_NOT_POPPED(and_node->left);
        PM_DUP_UNLESS_POPPED;
        ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

        PM_POP_UNLESS_POPPED;
        PM_COMPILE(and_node->right);
        ADD_LABEL(ret, end_label);
        return;
      }
      case PM_ARGUMENTS_NODE: {
        pm_arguments_node_t *arguments_node = (pm_arguments_node_t *) node;
        pm_node_list_t node_list = arguments_node->arguments;
        for (size_t index = 0; index < node_list.size; index++) {
            PM_COMPILE(node_list.nodes[index]);
        }
        return;
      }
      case PM_ARRAY_NODE: {
        // If every node in the array is static, then we can compile the entire
        // array now instead of later.
        if (pm_static_literal_p(node)) {
            // We're only going to compile this node if it's not popped. If it
            // is popped, then we know we don't need to do anything since it's
            // statically known.
            if (!popped) {
                VALUE value = pm_static_literal_value(node, scope_node, parser);
                ADD_INSN1(ret, &dummy_line_node, duparray, value);
                RB_OBJ_WRITTEN(iseq, Qundef, value);
            }
        } else {
            // Here since we know there are possible side-effects inside the
            // array contents, we're going to build it entirely at runtime.
            // We'll do this by pushing all of the elements onto the stack and
            // then combining them with newarray.
            //
            // If this hash is popped, then this serves only to ensure we enact
            // all side-effects (like method calls) that are contained within
            // the hash contents.
            pm_array_node_t *cast = (pm_array_node_t *) node;
            pm_node_list_t *elements = &cast->elements;

            for (size_t index = 0; index < elements->size; index++) {
                PM_COMPILE(elements->nodes[index]);
            }

            if (!popped) {
                ADD_INSN1(ret, &dummy_line_node, newarray, INT2FIX(elements->size));
            }
        }

        return;
      }
      case PM_ASSOC_NODE: {
        pm_assoc_node_t *assoc_node = (pm_assoc_node_t *) node;
        PM_COMPILE(assoc_node->key);
        if (assoc_node->value) {
            PM_COMPILE(assoc_node->value);
        }
        return;
      }
      case PM_ASSOC_SPLAT_NODE: {
        pm_assoc_splat_node_t *assoc_splat_node = (pm_assoc_splat_node_t *)node;

        PM_COMPILE(assoc_splat_node->value);
        return;
      }
      case PM_BACK_REFERENCE_READ_NODE: {
        if (!popped) {
            // Since a back reference is `$<char>`, ruby represents the ID as the
            // an rb_intern on the value after the `$`.
            char *char_ptr = (char *)(node->location.start) + 1;
            ID backref_val = INT2FIX(rb_intern2(char_ptr, 1)) << 1 | 1;
            ADD_INSN2(ret, &dummy_line_node, getspecial, INT2FIX(1), backref_val);
        }
        return;
      }
      case PM_BEGIN_NODE: {
        pm_begin_node_t *begin_node = (pm_begin_node_t *) node;
        rb_iseq_t *child_iseq;
        LABEL *lstart = NEW_LABEL(lineno);
        LABEL *lend = NEW_LABEL(lineno);

        ADD_LABEL(ret, lstart);
        if (begin_node->statements) {
            PM_COMPILE((pm_node_t *)begin_node->statements);
        }
        else {
            PM_PUTNIL_UNLESS_POPPED;
        }
        ADD_LABEL(ret, lend);

        if (begin_node->ensure_clause) {
            DECL_ANCHOR(ensr);

            iseq_set_exception_local_table(iseq);
            pm_scope_node_t next_scope_node;
            pm_scope_node_init((pm_node_t *)begin_node->ensure_clause, &next_scope_node, scope_node, parser);

            child_iseq = NEW_CHILD_ISEQ(next_scope_node,
                    rb_str_new2("ensure in"),
                    ISEQ_TYPE_ENSURE, lineno);

            LABEL *lcont = NEW_LABEL(lineno);
            struct ensure_range er;
            struct iseq_compile_data_ensure_node_stack enl;
            struct ensure_range *erange;

            INIT_ANCHOR(ensr);
            PM_COMPILE_INTO_ANCHOR(ensr, (pm_node_t *)&next_scope_node);

            er.begin = lstart;
            er.end = lend;
            er.next = 0;
            push_ensure_entry(iseq, &enl, &er, (void *)&next_scope_node);

            ISEQ_COMPILE_DATA(iseq)->current_block = child_iseq;
            ADD_SEQ(ret, ensr);
            ADD_LABEL(ret, lcont);
            erange = ISEQ_COMPILE_DATA(iseq)->ensure_node_stack->erange;
            if (lstart->link.next != &lend->link) {
                while (erange) {
                    ADD_CATCH_ENTRY(CATCH_TYPE_ENSURE, erange->begin, erange->end, child_iseq, lcont);
                    erange = erange->next;
                }
            }
            PM_POP_UNLESS_POPPED;
        }
        return;
      }
      case PM_BLOCK_ARGUMENT_NODE: {
        pm_block_argument_node_t *block_argument_node = (pm_block_argument_node_t *) node;
        if (block_argument_node->expression) {
            PM_COMPILE(block_argument_node->expression);
        }
        return;
      }
      case PM_BREAK_NODE: {
        pm_break_node_t *break_node = (pm_break_node_t *) node;
        if (break_node->arguments) {
            PM_COMPILE_NOT_POPPED((pm_node_t *)break_node->arguments);
        }
        else {
            PM_PUTNIL;
        }

        ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->end_label);

        return;
      }
      case PM_CALL_NODE: {
        pm_call_node_t *call_node = (pm_call_node_t *) node;

        ID method_id = pm_constant_id_lookup(scope_node, call_node->name);
        int flags = 0;
        struct rb_callinfo_kwarg *kw_arg = NULL;

        if (call_node->receiver == NULL) {
            PM_PUTSELF;
        } else {
            PM_COMPILE_NOT_POPPED(call_node->receiver);
        }

        int orig_argc = pm_setup_args(call_node->arguments, &flags, &kw_arg, iseq, ret, src, popped, scope_node, dummy_line_node, parser);

        const rb_iseq_t *block_iseq = NULL;
        if (call_node->block != NULL && PM_NODE_TYPE_P(call_node->block, PM_BLOCK_NODE)) {
            // Scope associated with the block
            pm_scope_node_t next_scope_node;
            pm_scope_node_init(call_node->block, &next_scope_node, scope_node, parser);

            block_iseq = NEW_CHILD_ISEQ(next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
            ISEQ_COMPILE_DATA(iseq)->current_block = block_iseq;
        }
        else {
            if (node->flags & PM_CALL_NODE_FLAGS_VARIABLE_CALL) {
                flags |= VM_CALL_VCALL;
            }

            if (call_node->block != NULL) {
                PM_COMPILE_NOT_POPPED(call_node->block);
                flags |= VM_CALL_ARGS_BLOCKARG;
            }

            if (!flags) {
                flags |= VM_CALL_ARGS_SIMPLE;
            }
        }

        if (call_node->receiver == NULL) {
            flags |= VM_CALL_FCALL;
        }

        ADD_SEND_R(ret, &dummy_line_node, method_id, INT2FIX(orig_argc), block_iseq, INT2FIX(flags), kw_arg);
        PM_POP_IF_POPPED;
        return;
      }
      case PM_CALL_AND_WRITE_NODE: {
        pm_call_and_write_node_t *call_and_write_node = (pm_call_and_write_node_t*) node;

        pm_compile_call_and_or_write_node(true, call_and_write_node->receiver, call_and_write_node->value, call_and_write_node->write_name, call_and_write_node->read_name, ret, iseq, lineno, src, popped, scope_node);

        return;
      }
      case PM_CALL_OR_WRITE_NODE: {
        pm_call_or_write_node_t *call_or_write_node = (pm_call_or_write_node_t*) node;

        pm_compile_call_and_or_write_node(false, call_or_write_node->receiver, call_or_write_node->value, call_or_write_node->write_name, call_or_write_node->read_name, ret, iseq, lineno, src, popped, scope_node);

        return;
      }
      case PM_CALL_OPERATOR_WRITE_NODE: {
        pm_call_operator_write_node_t *call_operator_write_node = (pm_call_operator_write_node_t*) node;

        NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

        int flag = 0;

        if (PM_NODE_TYPE_P(call_operator_write_node->receiver, PM_SELF_NODE)) {
            flag = VM_CALL_FCALL;
        }

        PM_COMPILE_NOT_POPPED(call_operator_write_node->receiver);

        ID write_name_id = pm_constant_id_lookup(scope_node, call_operator_write_node->write_name);
        ID read_name_id = pm_constant_id_lookup(scope_node, call_operator_write_node->read_name);
        ID operator_id = pm_constant_id_lookup(scope_node, call_operator_write_node->operator);
        PM_DUP;

        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, read_name_id, INT2FIX(0), INT2FIX(flag));

        PM_COMPILE_NOT_POPPED(call_operator_write_node->value);
        ADD_SEND(ret, &dummy_line_node, operator_id, INT2FIX(1));

        if (!popped) {
            PM_SWAP;
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
        }

        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, write_name_id, INT2FIX(1), INT2FIX(flag));
        PM_POP;

        return;
      }
      case PM_CASE_NODE: {
        pm_case_node_t *case_node = (pm_case_node_t *)node;
        bool has_predicate = case_node->predicate;
        if (has_predicate) {
            PM_COMPILE_NOT_POPPED(case_node->predicate);
        }
        LABEL *end_label = NEW_LABEL(lineno);

        pm_node_list_t conditions = case_node->conditions;

        LABEL **conditions_labels = (LABEL **)ALLOC_N(VALUE, conditions.size + 1);
        LABEL *label;

        for (size_t i = 0; i < conditions.size; i++) {
            label = NEW_LABEL(lineno);
            conditions_labels[i] = label;
            if (has_predicate) {
                pm_when_node_t *when_node = (pm_when_node_t *)conditions.nodes[i];

                for (size_t i = 0; i < when_node->conditions.size; i++) {
                    PM_COMPILE_NOT_POPPED(when_node->conditions.nodes[i]);
                    ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
                    ADD_SEND_WITH_FLAG(ret, &dummy_line_node, idEqq, INT2NUM(1), INT2FIX(VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE));
                    ADD_INSNL(ret, &dummy_line_node, branchif, label);
                }
            }
            else {
                ADD_INSNL(ret, &dummy_line_node, jump, label);
                PM_PUTNIL;
            }
        }

        if (has_predicate) {
            PM_POP;

            if (case_node->consequent) {
                if (!popped || !PM_NODE_TYPE_P(((pm_node_t *)case_node->consequent), PM_ELSE_NODE)) {
                    PM_COMPILE_NOT_POPPED((pm_node_t *)case_node->consequent);
                }
            }
            else {
                PM_PUTNIL_UNLESS_POPPED;
            }
        }

        ADD_INSNL(ret, &dummy_line_node, jump, end_label);

        for (size_t i = 0; i < conditions.size; i++) {
            label = conditions_labels[i];
            ADD_LABEL(ret, label);
            if (has_predicate) {
                PM_POP;
            }

            pm_while_node_t *condition_node = (pm_while_node_t *)conditions.nodes[i];
            if (condition_node->statements) {
                PM_COMPILE((pm_node_t *)condition_node->statements);
            }
            else {
                PM_PUTNIL_UNLESS_POPPED;
            }

            ADD_INSNL(ret, &dummy_line_node, jump, end_label);
        }

        ADD_LABEL(ret, end_label);
        return;
      }
      case PM_CLASS_NODE: {
        pm_class_node_t *class_node = (pm_class_node_t *)node;
        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *)class_node, &next_scope_node, scope_node, parser);

        ID class_id = pm_constant_id_lookup(scope_node, class_node->name);

        VALUE class_name = rb_str_freeze(rb_sprintf("<class:%"PRIsVALUE">", rb_id2str(class_id)));

        const rb_iseq_t *class_iseq = NEW_CHILD_ISEQ(next_scope_node, class_name, ISEQ_TYPE_CLASS, lineno);

        // TODO: Once we merge constant path nodes correctly, fix this flag
        const int flags = VM_DEFINECLASS_TYPE_CLASS |
            (class_node->superclass ? VM_DEFINECLASS_FLAG_HAS_SUPERCLASS : 0) |
            pm_compile_class_path(ret, iseq, class_node->constant_path, &dummy_line_node, src, false, scope_node);

        if (class_node->superclass) {
            PM_COMPILE_NOT_POPPED(class_node->superclass);
        }
        else {
            PM_PUTNIL;
        }

        ADD_INSN3(ret, &dummy_line_node, defineclass, ID2SYM(class_id), class_iseq, INT2FIX(flags));
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)class_iseq);

        PM_POP_IF_POPPED;
        return;
      }
      case PM_CLASS_VARIABLE_AND_WRITE_NODE: {
        pm_class_variable_and_write_node_t *class_variable_and_write_node = (pm_class_variable_and_write_node_t*) node;

        LABEL *end_label = NEW_LABEL(lineno);

        ID class_variable_name_id = pm_constant_id_lookup(scope_node, class_variable_and_write_node->name);
        VALUE class_variable_name_val = ID2SYM(class_variable_name_id);

        ADD_INSN2(ret, &dummy_line_node, getclassvariable,
                class_variable_name_val,
                get_cvar_ic_value(iseq, class_variable_name_id));

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(class_variable_and_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_INSN2(ret, &dummy_line_node, setclassvariable,
                class_variable_name_val,
                get_cvar_ic_value(iseq, class_variable_name_id));
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_CLASS_VARIABLE_OPERATOR_WRITE_NODE: {
        pm_class_variable_operator_write_node_t *class_variable_operator_write_node = (pm_class_variable_operator_write_node_t*) node;

        ID class_variable_name_id = pm_constant_id_lookup(scope_node, class_variable_operator_write_node->name);
        VALUE class_variable_name_val = ID2SYM(class_variable_name_id);

        ADD_INSN2(ret, &dummy_line_node, getclassvariable,
                class_variable_name_val,
                get_cvar_ic_value(iseq, class_variable_name_id));

        PM_COMPILE_NOT_POPPED(class_variable_operator_write_node->value);
        ID method_id = pm_constant_id_lookup(scope_node, class_variable_operator_write_node->operator);

        int flags = VM_CALL_ARGS_SIMPLE;
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

        PM_DUP_UNLESS_POPPED;

        ADD_INSN2(ret, &dummy_line_node, setclassvariable,
                class_variable_name_val,
                get_cvar_ic_value(iseq, class_variable_name_id));

        return;
      }
      case PM_CLASS_VARIABLE_OR_WRITE_NODE: {
        pm_class_variable_or_write_node_t *class_variable_or_write_node = (pm_class_variable_or_write_node_t*) node;

        LABEL *end_label = NEW_LABEL(lineno);

        ID class_variable_name_id = pm_constant_id_lookup(scope_node, class_variable_or_write_node->name);
        VALUE class_variable_name_val = ID2SYM(class_variable_name_id);

        ADD_INSN2(ret, &dummy_line_node, getclassvariable,
                class_variable_name_val,
                get_cvar_ic_value(iseq, class_variable_name_id));

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(class_variable_or_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_INSN2(ret, &dummy_line_node, setclassvariable,
                class_variable_name_val,
                get_cvar_ic_value(iseq, class_variable_name_id));
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_CLASS_VARIABLE_READ_NODE: {
        if (!popped) {
            pm_class_variable_read_node_t *class_variable_read_node = (pm_class_variable_read_node_t *) node;
            ID cvar_name = pm_constant_id_lookup(scope_node, class_variable_read_node->name);
            ADD_INSN2(ret, &dummy_line_node, getclassvariable, ID2SYM(cvar_name), get_cvar_ic_value(iseq, cvar_name));
        }
        return;
      }
      case PM_CLASS_VARIABLE_TARGET_NODE: {
        pm_class_variable_target_node_t *write_node = (pm_class_variable_target_node_t *) node;
        ID cvar_name = pm_constant_id_lookup(scope_node, write_node->name);
        ADD_INSN2(ret, &dummy_line_node, setclassvariable, ID2SYM(cvar_name), get_cvar_ic_value(iseq, cvar_name));
        return;
      }
      case PM_CLASS_VARIABLE_WRITE_NODE: {
        pm_class_variable_write_node_t *write_node = (pm_class_variable_write_node_t *) node;
        PM_COMPILE_NOT_POPPED(write_node->value);
        PM_DUP_UNLESS_POPPED;

        ID cvar_name = pm_constant_id_lookup(scope_node, write_node->name);
        ADD_INSN2(ret, &dummy_line_node, setclassvariable, ID2SYM(cvar_name), get_cvar_ic_value(iseq, cvar_name));
        return;
      }
      case PM_CONSTANT_PATH_NODE: {
        pm_constant_path_node_t *constant_path_node = (pm_constant_path_node_t*) node;
        if (constant_path_node->parent) {
            PM_COMPILE_NOT_POPPED(constant_path_node->parent);
        } else {
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }
        ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);

        assert(PM_NODE_TYPE_P(constant_path_node->child, PM_CONSTANT_READ_NODE));
        pm_constant_read_node_t *child = (pm_constant_read_node_t *) constant_path_node->child;

        ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(pm_constant_id_lookup(scope_node, child->name)));
        PM_POP_IF_POPPED;
        return;
      }
      case PM_CONSTANT_PATH_AND_WRITE_NODE: {
        pm_constant_path_and_write_node_t *constant_path_and_write_node = (pm_constant_path_and_write_node_t*) node;

        LABEL *lfin = NEW_LABEL(lineno);

        pm_constant_path_node_t *target = constant_path_and_write_node->target;
        PM_COMPILE_NOT_POPPED(target->parent);

        pm_constant_read_node_t *child = (pm_constant_read_node_t *)target->child;
        VALUE child_name = ID2SYM(pm_constant_id_lookup(scope_node, child->name));

        PM_DUP;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, child_name);

        PM_DUP_UNLESS_POPPED;
        ADD_INSNL(ret, &dummy_line_node, branchunless, lfin);

        PM_POP_UNLESS_POPPED;
        PM_COMPILE_NOT_POPPED(constant_path_and_write_node->value);

        if (popped) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, dupn, INT2FIX(2));
            PM_SWAP;
        }

        ADD_INSN1(ret, &dummy_line_node, setconstant, child_name);
        ADD_LABEL(ret, lfin);

        PM_SWAP_UNLESS_POPPED;
        PM_POP;

        return;
      }
      case PM_CONSTANT_PATH_OR_WRITE_NODE: {
        pm_constant_path_or_write_node_t *constant_path_or_write_node = (pm_constant_path_or_write_node_t*) node;

        LABEL *lassign = NEW_LABEL(lineno);
        LABEL *lfin = NEW_LABEL(lineno);

        pm_constant_path_node_t *target = constant_path_or_write_node->target;
        PM_COMPILE_NOT_POPPED(target->parent);

        pm_constant_read_node_t *child = (pm_constant_read_node_t *)target->child;
        VALUE child_name = ID2SYM(pm_constant_id_lookup(scope_node, child->name));

        PM_DUP;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CONST_FROM), child_name, Qtrue);
        ADD_INSNL(ret, &dummy_line_node, branchunless, lassign);

        PM_DUP;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, child_name);

        PM_DUP_UNLESS_POPPED;
        ADD_INSNL(ret, &dummy_line_node, branchif, lfin);

        PM_POP_UNLESS_POPPED;
        ADD_LABEL(ret, lassign);
        PM_COMPILE_NOT_POPPED(constant_path_or_write_node->value);

        if (popped) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, dupn, INT2FIX(2));
            PM_SWAP;
        }

        ADD_INSN1(ret, &dummy_line_node, setconstant, child_name);
        ADD_LABEL(ret, lfin);

        PM_SWAP_UNLESS_POPPED;
        PM_POP;

        return;
      }
      case PM_CONSTANT_PATH_OPERATOR_WRITE_NODE: {
        pm_constant_path_operator_write_node_t *constant_path_operator_write_node = (pm_constant_path_operator_write_node_t*) node;

        pm_constant_path_node_t *target = constant_path_operator_write_node->target;
        PM_COMPILE_NOT_POPPED(target->parent);

        PM_DUP;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);

        pm_constant_read_node_t *child = (pm_constant_read_node_t *)target->child;
        VALUE child_name = ID2SYM(pm_constant_id_lookup(scope_node, child->name));
        ADD_INSN1(ret, &dummy_line_node, getconstant, child_name);

        PM_COMPILE_NOT_POPPED(constant_path_operator_write_node->value);
        ID method_id = pm_constant_id_lookup(scope_node, constant_path_operator_write_node->operator);
        ADD_CALL(ret, &dummy_line_node, method_id, INT2FIX(1));
        PM_SWAP;

        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
            PM_SWAP;
        }

        ADD_INSN1(ret, &dummy_line_node, setconstant, child_name);
        return ;
      }
      case PM_CONSTANT_PATH_TARGET_NODE: {
        pm_constant_path_target_node_t *cast = (pm_constant_path_target_node_t *)node;

        if (cast->parent) {
            PM_COMPILE(cast->parent);
        }

        return;
      }
      case PM_CONSTANT_PATH_WRITE_NODE: {
        pm_constant_path_write_node_t *constant_path_write_node = (pm_constant_path_write_node_t*) node;
        if (constant_path_write_node->target->parent) {
            PM_COMPILE_NOT_POPPED((pm_node_t *)constant_path_write_node->target->parent);
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }
        PM_COMPILE_NOT_POPPED(constant_path_write_node->value);
        if (!popped) {
            PM_SWAP;
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
        }
        PM_SWAP;
        VALUE constant_name = ID2SYM(pm_constant_id_lookup(scope_node,
                    ((pm_constant_read_node_t *)constant_path_write_node->target->child)->name));
        ADD_INSN1(ret, &dummy_line_node, setconstant, constant_name);
        return;
      }
      case PM_CONSTANT_READ_NODE: {
        pm_constant_read_node_t *constant_read_node = (pm_constant_read_node_t *) node;
        PM_PUTNIL;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(pm_constant_id_lookup(scope_node, constant_read_node->name)));
        PM_POP_IF_POPPED;
        return;
      }
      case PM_CONSTANT_AND_WRITE_NODE: {
        pm_constant_and_write_node_t *constant_and_write_node = (pm_constant_and_write_node_t*) node;

        LABEL *end_label = NEW_LABEL(lineno);

        VALUE constant_name = ID2SYM(pm_constant_id_lookup(scope_node, constant_and_write_node->name));

        PM_PUTNIL;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, constant_name);
        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(constant_and_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, constant_name);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_CONSTANT_OPERATOR_WRITE_NODE: {
        pm_constant_operator_write_node_t *constant_operator_write_node = (pm_constant_operator_write_node_t*) node;

        ID constant_name = pm_constant_id_lookup(scope_node, constant_operator_write_node->name);
        PM_PUTNIL;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, ID2SYM(constant_name));

        PM_COMPILE_NOT_POPPED(constant_operator_write_node->value);
        ID method_id = pm_constant_id_lookup(scope_node, constant_operator_write_node->operator);

        int flags = VM_CALL_ARGS_SIMPLE;
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, ID2SYM(constant_name));

        return;
      }
      case PM_CONSTANT_OR_WRITE_NODE: {
        pm_constant_or_write_node_t *constant_or_write_node = (pm_constant_or_write_node_t*) node;

        LABEL *set_label= NEW_LABEL(lineno);
        LABEL *end_label = NEW_LABEL(lineno);

        PM_PUTNIL;
        VALUE constant_name = ID2SYM(pm_constant_id_lookup(scope_node, constant_or_write_node->name));

        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CONST), constant_name, Qtrue);

        ADD_INSNL(ret, &dummy_line_node, branchunless, set_label);

        PM_PUTNIL;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, constant_name);

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

        PM_POP_UNLESS_POPPED;

        ADD_LABEL(ret, set_label);
        PM_COMPILE_NOT_POPPED(constant_or_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, constant_name);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_CONSTANT_TARGET_NODE: {
        pm_constant_target_node_t *constant_write_node = (pm_constant_target_node_t *) node;
        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, ID2SYM(pm_constant_id_lookup(scope_node, constant_write_node->name)));
        return;
      }
      case PM_CONSTANT_WRITE_NODE: {
        pm_constant_write_node_t *constant_write_node = (pm_constant_write_node_t *) node;
        PM_COMPILE_NOT_POPPED(constant_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, ID2SYM(pm_constant_id_lookup(scope_node, constant_write_node->name)));
        return;
      }
      case PM_DEF_NODE: {
        pm_def_node_t *def_node = (pm_def_node_t *) node;
        ID method_name = pm_constant_id_lookup(scope_node, def_node->name);
        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *)def_node, &next_scope_node, scope_node, parser);
        rb_iseq_t *method_iseq = NEW_ISEQ(next_scope_node, rb_id2str(method_name), ISEQ_TYPE_METHOD, lineno);

        if (def_node->receiver) {
            PM_COMPILE_NOT_POPPED(def_node->receiver);
            ADD_INSN2(ret, &dummy_line_node, definesmethod, ID2SYM(method_name), method_iseq);
        }
        else {
            ADD_INSN2(ret, &dummy_line_node, definemethod, ID2SYM(method_name), method_iseq);
        }
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)method_iseq);

        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, ID2SYM(method_name));
        }
        return;
      }
      case PM_DEFINED_NODE: {
        pm_defined_node_t *defined_node = (pm_defined_node_t *)node;
        pm_compile_defined_expr(iseq, defined_node->value, ret, src, popped, scope_node, dummy_line_node, lineno, false);
        return;
      }
      case PM_EMBEDDED_STATEMENTS_NODE: {
        pm_embedded_statements_node_t *embedded_statements_node = (pm_embedded_statements_node_t *)node;

        if (embedded_statements_node->statements) {
            PM_COMPILE((pm_node_t *) (embedded_statements_node->statements));
        }
        else {
            PM_PUTNIL;
        }

        PM_POP_IF_POPPED;
        // TODO: Concatenate the strings that exist here
        return;
      }
      case PM_EMBEDDED_VARIABLE_NODE: {
        pm_embedded_variable_node_t *embedded_node = (pm_embedded_variable_node_t *)node;
        PM_COMPILE(embedded_node->variable);
        return;
      }
      case PM_FALSE_NODE:
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
        }
        return;
      case PM_ELSE_NODE: {
          pm_else_node_t *cast = (pm_else_node_t *)node;
          if (cast->statements) {
              PM_COMPILE((pm_node_t *)cast->statements);
          }
          else {
              PM_PUTNIL;
          }
          return;
      }
      case PM_FLIP_FLOP_NODE: {
        pm_flip_flop_node_t *flip_flop_node = (pm_flip_flop_node_t *)node;

        LABEL *final_label = NEW_LABEL(lineno);
        LABEL *then_label = NEW_LABEL(lineno);
        LABEL *else_label = NEW_LABEL(lineno);

        pm_compile_flip_flop(flip_flop_node, else_label, then_label, iseq, lineno, ret, src, popped, scope_node);

        ADD_LABEL(ret, then_label);
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSNL(ret, &dummy_line_node, jump, final_label);
        ADD_LABEL(ret, else_label);
        ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
        ADD_LABEL(ret, final_label);
        return;
      }
      case PM_FLOAT_NODE: {
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, parse_float(node));
        }
        return;
      }
      case PM_FOR_NODE: {
        pm_for_node_t *for_node = (pm_for_node_t *)node;

        const rb_iseq_t *child_iseq;
        const rb_iseq_t *prevblock = ISEQ_COMPILE_DATA(iseq)->current_block;

        LABEL *retry_label = NEW_LABEL(lineno);
        LABEL *retry_end_l = NEW_LABEL(lineno);

        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *)for_node, &next_scope_node, scope_node, parser);

        pm_constant_id_list_t locals;
        pm_constant_id_list_init(&locals);
        pm_constant_id_list_append(&locals, TEMP_CONSTANT_IDENTIFIER);
        next_scope_node.locals = locals;

        ADD_LABEL(ret, retry_label);

        PM_COMPILE_NOT_POPPED(for_node->collection);

        child_iseq = NEW_CHILD_ISEQ(next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
        ISEQ_COMPILE_DATA(iseq)->current_block = child_iseq;
        ADD_SEND_WITH_BLOCK(ret, &dummy_line_node, idEach, INT2FIX(0), child_iseq);

        INSN *iobj;
        LINK_ELEMENT *last_elem = LAST_ELEMENT(ret);
        iobj = IS_INSN(last_elem) ? (INSN *)last_elem : (INSN *)get_prev_insn((INSN*)last_elem);
        while (INSN_OF(iobj) != BIN(send) &&
                INSN_OF(iobj) != BIN(invokesuper)) {
            iobj = (INSN *)get_prev_insn(iobj);
        }
        ELEM_INSERT_NEXT(&iobj->link, (LINK_ELEMENT*)retry_end_l);

        PM_POP_IF_POPPED;

        ISEQ_COMPILE_DATA(iseq)->current_block = prevblock;
        ADD_CATCH_ENTRY(CATCH_TYPE_BREAK, retry_label, retry_end_l, child_iseq, retry_end_l);
        return;
      }
      case PM_FORWARDING_ARGUMENTS_NODE: {
        rb_bug("Should never hit the forwarding arguments case directly\n");
        return;
      }
      case PM_FORWARDING_SUPER_NODE: {
        pm_forwarding_super_node_t *forwarding_super_node = (pm_forwarding_super_node_t *) node;
        const rb_iseq_t *block = NULL;
        PM_PUTSELF;
        int flag = VM_CALL_ZSUPER | VM_CALL_SUPER | VM_CALL_FCALL;

        if (forwarding_super_node->block) {
            pm_scope_node_t next_scope_node;
            pm_scope_node_init((pm_node_t *)forwarding_super_node->block, &next_scope_node, scope_node, parser);
            block = NEW_CHILD_ISEQ(next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
            RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)block);
        }

        ADD_INSN2(ret, &dummy_line_node, invokesuper, new_callinfo(iseq, 0, 0, flag, NULL, block != NULL), block);
        PM_POP_IF_POPPED;
        return;
      }
      case PM_GLOBAL_VARIABLE_AND_WRITE_NODE: {
        pm_global_variable_and_write_node_t *global_variable_and_write_node = (pm_global_variable_and_write_node_t*) node;

        LABEL *end_label = NEW_LABEL(lineno);

        VALUE global_variable_name = ID2SYM(pm_constant_id_lookup(scope_node, global_variable_and_write_node->name));

        ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(global_variable_and_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, setglobal, global_variable_name);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE: {
        pm_global_variable_operator_write_node_t *global_variable_operator_write_node = (pm_global_variable_operator_write_node_t*) node;

        VALUE global_variable_name = ID2SYM(pm_constant_id_lookup(scope_node, global_variable_operator_write_node->name));
        ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);

        PM_COMPILE_NOT_POPPED(global_variable_operator_write_node->value);
        ID method_id = pm_constant_id_lookup(scope_node, global_variable_operator_write_node->operator);

        int flags = VM_CALL_ARGS_SIMPLE;
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, setglobal, global_variable_name);

        return;
      }
      case PM_GLOBAL_VARIABLE_OR_WRITE_NODE: {
        pm_global_variable_or_write_node_t *global_variable_or_write_node = (pm_global_variable_or_write_node_t*) node;

        LABEL *set_label= NEW_LABEL(lineno);
        LABEL *end_label = NEW_LABEL(lineno);

        PM_PUTNIL;
        VALUE global_variable_name = ID2SYM(pm_constant_id_lookup(scope_node, global_variable_or_write_node->name));

        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_GVAR), global_variable_name, Qtrue);

        ADD_INSNL(ret, &dummy_line_node, branchunless, set_label);

        ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

        PM_POP_UNLESS_POPPED;

        ADD_LABEL(ret, set_label);
        PM_COMPILE_NOT_POPPED(global_variable_or_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, setglobal, global_variable_name);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_GLOBAL_VARIABLE_READ_NODE: {
        pm_global_variable_read_node_t *global_variable_read_node = (pm_global_variable_read_node_t *)node;
        VALUE global_variable_name = ID2SYM(pm_constant_id_lookup(scope_node, global_variable_read_node->name));
        ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);
        PM_POP_IF_POPPED;
        return;
      }
      case PM_GLOBAL_VARIABLE_TARGET_NODE: {
        pm_global_variable_target_node_t *write_node = (pm_global_variable_target_node_t *) node;

        ID ivar_name = pm_constant_id_lookup(scope_node, write_node->name);
        ADD_INSN1(ret, &dummy_line_node, setglobal, ID2SYM(ivar_name));
        return;
      }
      case PM_GLOBAL_VARIABLE_WRITE_NODE: {
        pm_global_variable_write_node_t *write_node = (pm_global_variable_write_node_t *) node;
        PM_COMPILE_NOT_POPPED(write_node->value);
        PM_DUP_UNLESS_POPPED;
        ID ivar_name = pm_constant_id_lookup(scope_node, write_node->name);
        ADD_INSN1(ret, &dummy_line_node, setglobal, ID2SYM(ivar_name));
        return;
      }
      case PM_HASH_NODE: {
        // If every node in the hash is static, then we can compile the entire
        // hash now instead of later.
        if (pm_static_literal_p(node)) {
            // We're only going to compile this node if it's not popped. If it
            // is popped, then we know we don't need to do anything since it's
            // statically known.
            if (!popped) {
                VALUE value = pm_static_literal_value(node, scope_node, parser);
                ADD_INSN1(ret, &dummy_line_node, duphash, value);
                RB_OBJ_WRITTEN(iseq, Qundef, value);
            }
        } else {
            // Here since we know there are possible side-effects inside the
            // hash contents, we're going to build it entirely at runtime. We'll
            // do this by pushing all of the key-value pairs onto the stack and
            // then combining them with newhash.
            //
            // If this hash is popped, then this serves only to ensure we enact
            // all side-effects (like method calls) that are contained within
            // the hash contents.
            pm_hash_node_t *cast = (pm_hash_node_t *) node;
            // Elements must be non-empty, otherwise it would be static literal
            pm_node_list_t *elements = &cast->elements;

            pm_node_t *cur_node = elements->nodes[0];
            pm_node_type_t cur_type = PM_NODE_TYPE(cur_node);
            int elements_of_cur_type = 0;
            int allocated_hashes = 0;

            if (!PM_NODE_TYPE_P(cur_node, PM_ASSOC_NODE) && !popped) {
                ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(0));
                allocated_hashes++;
            }

            for (size_t index = 0; index < elements->size; index++) {
                pm_node_t *cur_node = elements->nodes[index];
                if (!popped) {
                    if (!PM_NODE_TYPE_P(cur_node, cur_type)) {
                        if (!allocated_hashes) {
                            ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(elements_of_cur_type * 2));
                        }
                        else {
                            if (cur_type == PM_ASSOC_NODE) {
                                ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_ptr, INT2FIX(3));
                            }
                            else {
                                ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_kwd, INT2FIX(2));
                            }
                        }

                        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                        PM_SWAP;
                        PM_COMPILE(elements->nodes[index]);

                        allocated_hashes++;
                        elements_of_cur_type = 0;
                        cur_type = PM_NODE_TYPE(cur_node);
                    }
                    else {
                        elements_of_cur_type++;
                        PM_COMPILE(elements->nodes[index]);
                    }
                }
                else {
                    PM_COMPILE(elements->nodes[index]);
                }
            }

            if (!popped) {
                if (!allocated_hashes) {
                    ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(elements_of_cur_type * 2));
                }
                else {
                    if (cur_type == PM_ASSOC_NODE) {
                        ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_ptr, INT2FIX(3));
                    }
                    else {
                        ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_kwd, INT2FIX(2));
                    }
                }
            }
        }

        return;
      }
      case PM_IF_NODE: {
        const int line = (int)pm_newline_list_line_column(&(parser->newline_list), node->location.start).line;
        pm_if_node_t *if_node = (pm_if_node_t *)node;
        pm_statements_node_t *node_body = if_node->statements;
        pm_node_t *node_else = if_node->consequent;
        pm_node_t *predicate = if_node->predicate;

        pm_compile_if(iseq, line, node_body, node_else, predicate, ret, src, popped, scope_node);
        return;
      }
      case PM_IMAGINARY_NODE: {
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, parse_imaginary((pm_imaginary_node_t *)node));
        }
        return;
      }
      case PM_IMPLICIT_NODE: {
        // Implicit nodes mark places in the syntax tree where explicit syntax
        // was omitted, but implied. For example,
        //
        //     { foo: }
        //
        // In this case a method call/local variable read is implied by virtue
        // of the missing value. To compile these nodes, we simply compile the
        // value that is implied, which is helpfully supplied by the parser.
        pm_implicit_node_t *cast = (pm_implicit_node_t *)node;
        PM_COMPILE(cast->value);
        return;
      }
      case PM_INSTANCE_VARIABLE_AND_WRITE_NODE: {
        pm_instance_variable_and_write_node_t *instance_variable_and_write_node = (pm_instance_variable_and_write_node_t*) node;

        LABEL *end_label = NEW_LABEL(lineno);
        ID instance_variable_name_id = pm_constant_id_lookup(scope_node, instance_variable_and_write_node->name);
        VALUE instance_variable_name_val = ID2SYM(instance_variable_name_id);

        ADD_INSN2(ret, &dummy_line_node, getinstancevariable, instance_variable_name_val, get_ivar_ic_value(iseq, instance_variable_name_id));
        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);
        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(instance_variable_and_write_node->value);
        PM_DUP_UNLESS_POPPED;

        ADD_INSN2(ret, &dummy_line_node, setinstancevariable, instance_variable_name_val, get_ivar_ic_value(iseq, instance_variable_name_id));
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_INSTANCE_VARIABLE_OPERATOR_WRITE_NODE: {
        pm_instance_variable_operator_write_node_t *instance_variable_operator_write_node = (pm_instance_variable_operator_write_node_t*) node;

        ID instance_variable_name_id = pm_constant_id_lookup(scope_node, instance_variable_operator_write_node->name);
        VALUE instance_variable_name_val = ID2SYM(instance_variable_name_id);

        ADD_INSN2(ret, &dummy_line_node, getinstancevariable,
                instance_variable_name_val,
                get_ivar_ic_value(iseq, instance_variable_name_id));

        PM_COMPILE_NOT_POPPED(instance_variable_operator_write_node->value);
        ID method_id = pm_constant_id_lookup(scope_node, instance_variable_operator_write_node->operator);

        int flags = VM_CALL_ARGS_SIMPLE;
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

        PM_DUP_UNLESS_POPPED;

        ADD_INSN2(ret, &dummy_line_node, setinstancevariable,
                instance_variable_name_val,
                get_ivar_ic_value(iseq, instance_variable_name_id));

        return;
      }
      case PM_INSTANCE_VARIABLE_OR_WRITE_NODE: {
        pm_instance_variable_or_write_node_t *instance_variable_or_write_node = (pm_instance_variable_or_write_node_t*) node;

        LABEL *end_label = NEW_LABEL(lineno);

        ID instance_variable_name_id = pm_constant_id_lookup(scope_node, instance_variable_or_write_node->name);
        VALUE instance_variable_name_val = ID2SYM(instance_variable_name_id);

        ADD_INSN2(ret, &dummy_line_node, getinstancevariable, instance_variable_name_val, get_ivar_ic_value(iseq, instance_variable_name_id));
        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);
        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(instance_variable_or_write_node->value);
        PM_DUP_UNLESS_POPPED;

        ADD_INSN2(ret, &dummy_line_node, setinstancevariable, instance_variable_name_val, get_ivar_ic_value(iseq, instance_variable_name_id));
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_INSTANCE_VARIABLE_READ_NODE: {
        if (!popped) {
            pm_instance_variable_read_node_t *instance_variable_read_node = (pm_instance_variable_read_node_t *) node;
            ID ivar_name = pm_constant_id_lookup(scope_node, instance_variable_read_node->name);
            ADD_INSN2(ret, &dummy_line_node, getinstancevariable, ID2SYM(ivar_name), get_ivar_ic_value(iseq, ivar_name));
        }
        return;
      }
      case PM_INSTANCE_VARIABLE_TARGET_NODE: {
        pm_instance_variable_target_node_t *write_node = (pm_instance_variable_target_node_t *) node;

        ID ivar_name = pm_constant_id_lookup(scope_node, write_node->name);
        ADD_INSN2(ret, &dummy_line_node, setinstancevariable, ID2SYM(ivar_name), get_ivar_ic_value(iseq, ivar_name));
        return;
      }
      case PM_INSTANCE_VARIABLE_WRITE_NODE: {
        pm_instance_variable_write_node_t *write_node = (pm_instance_variable_write_node_t *) node;
        PM_COMPILE_NOT_POPPED(write_node->value);

        PM_DUP_UNLESS_POPPED;

        ID ivar_name = pm_constant_id_lookup(scope_node, write_node->name);
        ADD_INSN2(ret, &dummy_line_node, setinstancevariable,
                ID2SYM(ivar_name),
                get_ivar_ic_value(iseq, ivar_name));
        return;
      }
      case PM_INTEGER_NODE: {
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, parse_integer((pm_integer_node_t *) node));
        }
        return;
      }
      case PM_INTERPOLATED_MATCH_LAST_LINE_NODE: {
        pm_interpolated_match_last_line_node_t *cast = (pm_interpolated_match_last_line_node_t *) node;
        pm_interpolated_node_compile(cast->parts, iseq, dummy_line_node, ret, src, popped, scope_node, parser);

        ADD_INSN2(ret, &dummy_line_node, toregexp, INT2FIX(pm_reg_flags(node)), INT2FIX((int) (cast->parts.size)));

        ADD_INSN2(ret, &dummy_line_node, getspecial, INT2FIX(0), INT2FIX(0));
        ADD_SEND(ret, &dummy_line_node, idEqTilde, INT2NUM(1));
        PM_POP_IF_POPPED;

        return;
      }
      case PM_INTERPOLATED_REGULAR_EXPRESSION_NODE: {
        pm_interpolated_regular_expression_node_t *cast = (pm_interpolated_regular_expression_node_t *) node;
        pm_interpolated_node_compile(cast->parts, iseq, dummy_line_node, ret, src, popped, scope_node, parser);

        ADD_INSN2(ret, &dummy_line_node, toregexp, INT2FIX(pm_reg_flags(node)), INT2FIX((int) (cast->parts.size)));
        PM_POP_IF_POPPED;
        return;
      }
      case PM_INTERPOLATED_STRING_NODE: {
        pm_interpolated_string_node_t *interp_string_node = (pm_interpolated_string_node_t *) node;
        pm_interpolated_node_compile(interp_string_node->parts, iseq, dummy_line_node, ret, src, popped, scope_node, parser);

        size_t parts_size = interp_string_node->parts.size;
        if (parts_size > 1) {
            ADD_INSN1(ret, &dummy_line_node, concatstrings, INT2FIX((int)(parts_size)));
        }

        PM_POP_IF_POPPED;
        return;
      }
      case PM_INTERPOLATED_SYMBOL_NODE: {
        pm_interpolated_symbol_node_t *interp_symbol_node = (pm_interpolated_symbol_node_t *) node;
        pm_interpolated_node_compile(interp_symbol_node->parts, iseq, dummy_line_node, ret, src, popped, scope_node, parser);

        size_t parts_size = interp_symbol_node->parts.size;
        if (parts_size > 1) {
            ADD_INSN1(ret, &dummy_line_node, concatstrings, INT2FIX((int)(parts_size)));
        }

        if (!popped) {
            ADD_INSN(ret, &dummy_line_node, intern);
        }
        else {
            PM_POP;
        }

        return;
      }
      case PM_INTERPOLATED_X_STRING_NODE: {
        pm_interpolated_x_string_node_t *interp_x_string_node = (pm_interpolated_x_string_node_t *) node;
        PM_PUTSELF;
        pm_interpolated_node_compile(interp_x_string_node->parts, iseq, dummy_line_node, ret, src, false, scope_node, parser);

        size_t parts_size = interp_x_string_node->parts.size;
        if (parts_size > 1) {
            ADD_INSN1(ret, &dummy_line_node, concatstrings, INT2FIX((int)(parts_size)));
        }

        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, idBackquote, INT2NUM(1), INT2FIX(VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE));
        PM_POP_IF_POPPED;
        return;
      }
      case PM_KEYWORD_HASH_NODE: {
        pm_keyword_hash_node_t *keyword_hash_node = (pm_keyword_hash_node_t *) node;
        pm_node_list_t elements = keyword_hash_node->elements;

        for (size_t index = 0; index < elements.size; index++) {
            PM_COMPILE(elements.nodes[index]);
        }

        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(elements.size * 2));
        }
        return;
      }
      case PM_LAMBDA_NODE: {
        pm_scope_node_t next_scope_node;
        pm_scope_node_init(node, &next_scope_node, scope_node, parser);

        const rb_iseq_t *block = NEW_CHILD_ISEQ(next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
        VALUE argc = INT2FIX(0);

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
        ADD_CALL_WITH_BLOCK(ret, &dummy_line_node, idLambda, argc, block);
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)block);

        PM_POP_IF_POPPED;
        return;
      }
      case PM_LOCAL_VARIABLE_AND_WRITE_NODE: {
        pm_local_variable_and_write_node_t *local_variable_and_write_node = (pm_local_variable_and_write_node_t*) node;

        LABEL *end_label = NEW_LABEL(lineno);

        pm_constant_id_t constant_id = local_variable_and_write_node->name;
        int depth = local_variable_and_write_node->depth;
        int local_index = pm_lookup_local_index_with_depth(iseq, scope_node, constant_id, depth);
        ADD_GETLOCAL(ret, &dummy_line_node, local_index, depth);

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(local_variable_and_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_SETLOCAL(ret, &dummy_line_node, local_index, depth);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_LOCAL_VARIABLE_OPERATOR_WRITE_NODE: {
        pm_local_variable_operator_write_node_t *local_variable_operator_write_node = (pm_local_variable_operator_write_node_t*) node;

        pm_constant_id_t constant_id = local_variable_operator_write_node->name;

        int depth = local_variable_operator_write_node->depth;
        int local_index = pm_lookup_local_index_with_depth(iseq, scope_node, constant_id, depth);
        ADD_GETLOCAL(ret, &dummy_line_node, local_index, depth);

        PM_COMPILE_NOT_POPPED(local_variable_operator_write_node->value);
        ID method_id = pm_constant_id_lookup(scope_node, local_variable_operator_write_node->operator);

        int flags = VM_CALL_ARGS_SIMPLE | VM_CALL_FCALL | VM_CALL_VCALL;
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

        PM_DUP_UNLESS_POPPED;

        ADD_SETLOCAL(ret, &dummy_line_node, local_index, depth);

        return;
      }
      case PM_LOCAL_VARIABLE_OR_WRITE_NODE: {
        pm_local_variable_or_write_node_t *local_variable_or_write_node = (pm_local_variable_or_write_node_t*) node;

        LABEL *set_label= NEW_LABEL(lineno);
        LABEL *end_label = NEW_LABEL(lineno);

        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSNL(ret, &dummy_line_node, branchunless, set_label);

        pm_constant_id_t constant_id = local_variable_or_write_node->name;
        int depth = local_variable_or_write_node->depth;
        int local_index = pm_lookup_local_index_with_depth(iseq, scope_node, constant_id, depth);
        ADD_GETLOCAL(ret, &dummy_line_node, local_index, depth);

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

        PM_POP_UNLESS_POPPED;

        ADD_LABEL(ret, set_label);
        PM_COMPILE_NOT_POPPED(local_variable_or_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_SETLOCAL(ret, &dummy_line_node, local_index, depth);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_LOCAL_VARIABLE_READ_NODE: {
        pm_local_variable_read_node_t *local_read_node = (pm_local_variable_read_node_t *) node;

        if (!popped) {
            int index = pm_lookup_local_index_with_depth(iseq, scope_node, local_read_node->name, local_read_node->depth);
            ADD_GETLOCAL(ret, &dummy_line_node, index, local_read_node->depth);
        }
        return;
      }
      case PM_LOCAL_VARIABLE_TARGET_NODE: {
        pm_local_variable_target_node_t *local_write_node = (pm_local_variable_target_node_t *) node;

        pm_constant_id_t constant_id = local_write_node->name;
        for (size_t index = 0; index < local_write_node->depth; index++) scope_node = scope_node->previous;
        int index = pm_lookup_local_index(iseq, scope_node, constant_id);

        ADD_SETLOCAL(ret, &dummy_line_node, (int)index, local_write_node->depth);
        return;
      }
      case PM_LOCAL_VARIABLE_WRITE_NODE: {
        pm_local_variable_write_node_t *local_write_node = (pm_local_variable_write_node_t *) node;
        PM_COMPILE_NOT_POPPED(local_write_node->value);

        PM_DUP_UNLESS_POPPED;

        pm_constant_id_t constant_id = local_write_node->name;
        int index = pm_lookup_local_index(iseq, scope_node, constant_id);

        ADD_SETLOCAL(ret, &dummy_line_node, (int)index, local_write_node->depth);
        return;
      }
      case PM_MATCH_LAST_LINE_NODE: {
        if (!popped) {
            pm_match_last_line_node_t *cast = (pm_match_last_line_node_t *) node;

            VALUE regex_str = parse_string(&cast->unescaped, parser);
            VALUE regex = rb_reg_new(RSTRING_PTR(regex_str), RSTRING_LEN(regex_str), pm_reg_flags(node));

            ADD_INSN1(ret, &dummy_line_node, putobject, regex);
            ADD_INSN2(ret, &dummy_line_node, getspecial, INT2FIX(0), INT2FIX(0));
            ADD_SEND(ret, &dummy_line_node, idEqTilde, INT2NUM(1));
        }

        return;
      }
      case PM_MATCH_PREDICATE_NODE: {
        pm_match_predicate_node_t *cast = (pm_match_predicate_node_t *) node;

        // First, allocate some stack space for the cached return value of any
        // calls to #deconstruct.
        PM_PUTNIL;

        // Next, compile the expression that we're going to match against.
        PM_COMPILE_NOT_POPPED(cast->value);
        PM_DUP;

        // Now compile the pattern that is going to be used to match against the
        // expression.
        LABEL *matched_label = NEW_LABEL(lineno);
        LABEL *unmatched_label = NEW_LABEL(lineno);
        LABEL *done_label = NEW_LABEL(lineno);
        pm_compile_pattern(iseq, cast->pattern, ret, src, scope_node, matched_label, unmatched_label, false);

        // If the pattern did not match, then compile the necessary instructions
        // to handle pushing false onto the stack, then jump to the end.
        ADD_LABEL(ret, unmatched_label);
        PM_POP;
        PM_POP;

        if (!popped) ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
        ADD_INSNL(ret, &dummy_line_node, jump, done_label);
        PM_PUTNIL;

        // If the pattern did match, then compile the necessary instructions to
        // handle pushing true onto the stack, then jump to the end.
        ADD_LABEL(ret, matched_label);
        ADD_INSN1(ret, &dummy_line_node, adjuststack, INT2FIX(2));
        if (!popped) ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSNL(ret, &dummy_line_node, jump, done_label);

        ADD_LABEL(ret, done_label);
        return;
      }
      case PM_MATCH_WRITE_NODE: {
        pm_match_write_node_t *cast = (pm_match_write_node_t *)node;
        LABEL *fail_label = NEW_LABEL(lineno);
        LABEL *end_label = NEW_LABEL(lineno);
        size_t capture_count = cast->locals.size;
        VALUE r;

        pm_constant_id_t *locals = ALLOCV_N(pm_constant_id_t, r, capture_count);

        for (size_t i = 0; i < capture_count; i++) {
            locals[i] = cast->locals.ids[i];
        }

        PM_COMPILE_NOT_POPPED((pm_node_t *)cast->call);
        VALUE global_variable_name = rb_id2sym(idBACKREF);

        ADD_INSN1(ret, &dummy_line_node, getglobal, global_variable_name);
        PM_DUP;
        ADD_INSNL(ret, &dummy_line_node, branchunless, fail_label);

        if (capture_count == 1) {
            int local_index = pm_lookup_local_index(iseq, scope_node, *locals);

            DECL_ANCHOR(nom);
            INIT_ANCHOR(nom);

            ADD_INSNL(nom, &dummy_line_node, jump, end_label);
            ADD_LABEL(nom, fail_label);
            ADD_LABEL(nom, end_label);
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_id2sym(pm_constant_id_lookup(scope_node, *locals)));
            ADD_SEND(ret, &dummy_line_node, idAREF, INT2FIX(1));
            ADD_SETLOCAL(nom, &dummy_line_node, local_index, 0);
            PM_POP_IF_POPPED;

            ADD_SEQ(ret, nom);
            return;
        }

        for (size_t index = 0; index < capture_count; index++) {
            int local_index = pm_lookup_local_index(iseq, scope_node, locals[index]);

            if (index < (capture_count - 1)) {
                PM_DUP;
            }
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_id2sym(pm_constant_id_lookup(scope_node, locals[index])));
            ADD_SEND(ret, &dummy_line_node, idAREF, INT2FIX(1));
            ADD_SETLOCAL(ret, &dummy_line_node, local_index, 0);
        }

        ADD_INSNL(ret, &dummy_line_node, jump, end_label);
        ADD_LABEL(ret, fail_label);
        PM_POP_UNLESS_POPPED;

        for (size_t index = 0; index < capture_count; index++) {
            pm_constant_id_t constant = cast->locals.ids[index];
            int local_index = pm_lookup_local_index(iseq, scope_node, constant);

            PM_PUTNIL;
            ADD_SETLOCAL(ret, &dummy_line_node, local_index, 0);
            PM_POP_IF_POPPED;
        }
        ADD_LABEL(ret, end_label);
        return;
      }
      case PM_MISSING_NODE: {
        rb_bug("A pm_missing_node_t should not exist in prism's AST.");
        return;
      }
      case PM_MODULE_NODE: {
        pm_module_node_t *module_node = (pm_module_node_t *)node;
        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *)module_node, &next_scope_node, scope_node, parser);

        ID module_id = pm_constant_id_lookup(scope_node, module_node->name);
        VALUE module_name = rb_str_freeze(rb_sprintf("<module:%"PRIsVALUE">", rb_id2str(module_id)));

        const rb_iseq_t *module_iseq = NEW_CHILD_ISEQ(next_scope_node, module_name, ISEQ_TYPE_CLASS, lineno);

        const int flags = VM_DEFINECLASS_TYPE_MODULE |
            pm_compile_class_path(ret, iseq, module_node->constant_path, &dummy_line_node, src, false, scope_node);

        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defineclass, ID2SYM(module_id), module_iseq, INT2FIX(flags));
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)module_iseq);

        PM_POP_IF_POPPED;
        return;
      }
      case PM_MULTI_TARGET_NODE: {
        pm_multi_target_node_t *cast = (pm_multi_target_node_t *) node;

        if (cast->lefts.size) {
            int flag = (int) (bool) cast->rights.size;
            ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(cast->lefts.size), INT2FIX(flag));
            for (size_t index = 0; index < cast->lefts.size; index++) {
                PM_COMPILE_NOT_POPPED(cast->lefts.nodes[index]);
            }
        }

        if (cast->rights.size) {
            ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(cast->rights.size), INT2FIX(2));
            for (size_t index = 0; index < cast->rights.size; index++) {
                PM_COMPILE_NOT_POPPED(cast->rights.nodes[index]);
            }
        }
        return;
      }
      case PM_MULTI_WRITE_NODE: {
        pm_multi_write_node_t *multi_write_node = (pm_multi_write_node_t *)node;
        pm_node_list_t *lefts = &multi_write_node->lefts;
        pm_node_list_t *rights = &multi_write_node->rights;

        // pre-process the left hand side of multi-assignments.
        uint8_t pushed = 0;
        for (size_t index = 0; index < lefts->size; index++) {
            pushed = pm_compile_multi_write_lhs(iseq, dummy_line_node, lefts->nodes[index], ret, scope_node, pushed, false);
        }

        PM_COMPILE_NOT_POPPED(multi_write_node->value);
        PM_DUP_UNLESS_POPPED;

        if (lefts->size) {
            ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(lefts->size), INT2FIX((int) (bool) rights->size));
            for (size_t index = 0; index < lefts->size; index++) {
                pm_node_t *considered_node = lefts->nodes[index];

                if (PM_NODE_TYPE_P(considered_node, PM_CONSTANT_PATH_TARGET_NODE) && pushed > 0) {
                    pm_constant_path_target_node_t *cast = (pm_constant_path_target_node_t *) considered_node;
                    ID name = pm_constant_id_lookup(scope_node, ((pm_constant_read_node_t * ) cast->child)->name);

                    pushed -= 2;

                    ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(pushed));
                    ADD_INSN1(ret, &dummy_line_node, setconstant, ID2SYM(name));
                } else {
                    PM_COMPILE(lefts->nodes[index]);
                }
            }
        }

        if (pushed) {
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(pushed));
            for (uint8_t index = 0; index < pushed; index++) {
                PM_POP;
            }
        }

        if (multi_write_node->rest) {
            RUBY_ASSERT(PM_NODE_TYPE_P(multi_write_node->rest, PM_SPLAT_NODE));

            pm_splat_node_t *rest_splat = ((pm_splat_node_t *)multi_write_node->rest);
            if (rest_splat->expression) {
                ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(0), INT2FIX(1));
                PM_COMPILE(rest_splat->expression);
            }
        }

        if (rights->size) {
            ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(rights->size), INT2FIX(2));
            for (size_t index = 0; index < rights->size; index++) {
                PM_COMPILE(rights->nodes[index]);
            }
        }

        return;
      }
      case PM_NEXT_NODE: {
        pm_next_node_t *next_node = (pm_next_node_t *) node;
        if (next_node->arguments) {
            PM_COMPILE_NOT_POPPED((pm_node_t *)next_node->arguments);
        }
        else {
            PM_PUTNIL;
        }

        PM_POP;
        ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->start_label);

        return;
      }
      case PM_NIL_NODE:
        PM_PUTNIL_UNLESS_POPPED
        return;
      case PM_NO_KEYWORDS_PARAMETER_NODE: {
        ISEQ_BODY(iseq)->param.flags.accepts_no_kwarg = TRUE;
        return;
      }
      case PM_NUMBERED_REFERENCE_READ_NODE: {
        if (!popped) {
            uint32_t reference_number = ((pm_numbered_reference_read_node_t *)node)->number;
            ADD_INSN2(ret, &dummy_line_node, getspecial, INT2FIX(1), INT2FIX(reference_number << 1));
        }
        return;
      }
      case PM_OR_NODE: {
        pm_or_node_t *or_node = (pm_or_node_t *) node;

        LABEL *end_label = NEW_LABEL(lineno);
        PM_COMPILE_NOT_POPPED(or_node->left);

        PM_DUP_UNLESS_POPPED;
        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

        PM_POP_UNLESS_POPPED;
        PM_COMPILE(or_node->right);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_OPTIONAL_PARAMETER_NODE: {
        pm_optional_parameter_node_t *optional_parameter_node = (pm_optional_parameter_node_t *)node;
        PM_COMPILE_NOT_POPPED(optional_parameter_node->value);

        int index = pm_lookup_local_index(iseq, scope_node, optional_parameter_node->name);

        ADD_SETLOCAL(ret, &dummy_line_node, index, 0);

        return;
      }
      case PM_PARAMETERS_NODE: {
        rb_bug("Should not ever enter a parameters node directly");

        return;
      }
      case PM_PARENTHESES_NODE: {
        pm_parentheses_node_t *parentheses_node = (pm_parentheses_node_t *) node;

        if (parentheses_node->body == NULL) {
            PM_PUTNIL_UNLESS_POPPED;
        } else {
            PM_COMPILE(parentheses_node->body);
        }

        return;
      }
      case PM_PRE_EXECUTION_NODE: {
        pm_pre_execution_node_t *pre_execution_node = (pm_pre_execution_node_t *) node;

        DECL_ANCHOR(pre_ex);
        INIT_ANCHOR(pre_ex);

        if (pre_execution_node->statements) {
            pm_node_list_t node_list = pre_execution_node->statements->body;
            for (size_t index = 0; index < node_list.size; index++) {
                pm_compile_node(iseq, node_list.nodes[index], pre_ex, src, true, scope_node);
            }
        }

        if (!popped) {
            ADD_INSN(pre_ex, &dummy_line_node, putnil);
        }

        pre_ex->last->next = ret->anchor.next;
        ret->anchor.next = pre_ex->anchor.next;
        ret->anchor.next->prev = pre_ex->anchor.next;

        if (ret->last == (LINK_ELEMENT *)ret) {
            ret->last = pre_ex->last;
        }

        return;
      }
      case PM_POST_EXECUTION_NODE: {
        const rb_iseq_t *child_iseq;
        const rb_iseq_t *prevblock = ISEQ_COMPILE_DATA(iseq)->current_block;

        pm_scope_node_t next_scope_node;
        pm_scope_node_init(node, &next_scope_node, scope_node, parser);

        child_iseq = NEW_CHILD_ISEQ(next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
        ISEQ_COMPILE_DATA(iseq)->current_block = child_iseq;

        int is_index = ISEQ_BODY(iseq)->ise_size++;

        ADD_INSN2(ret, &dummy_line_node, once, child_iseq, INT2FIX(is_index));
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)child_iseq);

        PM_POP_IF_POPPED;

        ISEQ_COMPILE_DATA(iseq)->current_block = prevblock;

        return;
      }
      case PM_PROGRAM_NODE: {
        rb_bug("Should not ever enter a program node directly");

        return;
      }
      case PM_RANGE_NODE: {
        pm_range_node_t *range_node = (pm_range_node_t *) node;
        bool exclusive = (range_node->operator_loc.end - range_node->operator_loc.start) == 3;

        if (pm_optimizable_range_item_p(range_node->left) && pm_optimizable_range_item_p(range_node->right))  {
            if (!popped) {
                pm_node_t *left = range_node->left;
                pm_node_t *right = range_node->right;
                VALUE val = rb_range_new(
                        left && PM_NODE_TYPE_P(left, PM_INTEGER_NODE) ? parse_integer((pm_integer_node_t *) left) : Qnil,
                        right && PM_NODE_TYPE_P(right, PM_INTEGER_NODE) ? parse_integer((pm_integer_node_t *) right) : Qnil,
                        exclusive
                        );
                ADD_INSN1(ret, &dummy_line_node, putobject, val);
                RB_OBJ_WRITTEN(iseq, Qundef, val);
            }
        }
        else {
            if (range_node->left == NULL) {
                PM_PUTNIL;
            } else {
                PM_COMPILE(range_node->left);
            }

            if (range_node->right == NULL) {
                PM_PUTNIL;
            } else {
                PM_COMPILE(range_node->right);
            }

            if (!popped) {
                ADD_INSN1(ret, &dummy_line_node, newrange, INT2FIX(exclusive));
            }
        }
        return;
      }
      case PM_RATIONAL_NODE: {
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, parse_rational(node));
        }
        return;
      }
      case PM_REDO_NODE: {
        ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->redo_label);
        return;
      }
      case PM_REGULAR_EXPRESSION_NODE: {
        if (!popped) {
            pm_regular_expression_node_t *cast = (pm_regular_expression_node_t *) node;

            VALUE regex = pm_new_regex(cast, parser);

            ADD_INSN1(ret, &dummy_line_node, putobject, regex);
        }
        return;
      }
      case PM_RETURN_NODE: {
        pm_arguments_node_t *arguments = ((pm_return_node_t *)node)->arguments;

        if (arguments) {
            PM_COMPILE((pm_node_t *)arguments);
        }
        else {
            PM_PUTNIL;
        }

        ADD_TRACE(ret, RUBY_EVENT_RETURN);
        ADD_INSN(ret, &dummy_line_node, leave);

        if (!popped) {
            PM_PUTNIL;
        }
        return;
      }
      case PM_SCOPE_NODE: {
        pm_scope_node_t *scope_node = (pm_scope_node_t *)node;
        pm_constant_id_list_t *locals = &scope_node->locals;

        pm_parameters_node_t *parameters_node = (pm_parameters_node_t *) scope_node->parameters;
        pm_node_list_t *keywords_list = NULL;
        pm_node_list_t *optionals_list = NULL;
        pm_node_list_t *posts_list = NULL;
        pm_node_list_t *requireds_list = NULL;

        struct rb_iseq_param_keyword *keyword = NULL;

        struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);

        if (parameters_node) {
            optionals_list = &parameters_node->optionals;
            requireds_list = &parameters_node->requireds;
            keywords_list = &parameters_node->keywords;
            posts_list = &parameters_node->posts;
        } else if (PM_NODE_TYPE_P(scope_node->ast_node, PM_FOR_NODE)) {
            body->param.lead_num = 1;
            body->param.opt_num = 0;
        } else {
            body->param.lead_num = 0;
            body->param.opt_num = 0;
        }

        size_t locals_size = locals->size;

        // Index lookup table buffer size is only the number of the locals
        st_table *index_lookup_table = st_init_numtable();

        VALUE idtmp = 0;
        rb_ast_id_table_t *tbl = ALLOCV(idtmp, sizeof(rb_ast_id_table_t) + locals_size * sizeof(ID));
        tbl->size = (int) locals_size;
        body->param.size = (int) locals_size;

        for (size_t i = 0; i < locals_size; i++) {
            pm_constant_id_t constant_id = locals->ids[i];
            ID local;
            if (constant_id & TEMP_CONSTANT_IDENTIFIER) {
                local = rb_make_temporary_id(i);
            }
            else {
                local = pm_constant_id_lookup(scope_node, constant_id);
            }
            tbl->ids[i] = local;
            st_insert(index_lookup_table, constant_id, i);
        }

        scope_node->index_lookup_table = index_lookup_table;

        if (optionals_list && optionals_list->size) {
            body->param.opt_num = (int) optionals_list->size;
            LABEL **opt_table = (LABEL **)ALLOC_N(VALUE, optionals_list->size + 1);
            LABEL *label;

            // TODO: Should we make an api for NEW_LABEL where you can pass
            // a pointer to the label it should fill out?  We already
            // have a list of labels allocated above so it seems wasteful
            // to do the copies.
            for (size_t i = 0; i < optionals_list->size; i++) {
                label = NEW_LABEL(lineno);
                opt_table[i] = label;
                ADD_LABEL(ret, label);
                pm_node_t *optional_node = optionals_list->nodes[i];
                PM_COMPILE_NOT_POPPED(optional_node);
            }

            // Set the last label
            label = NEW_LABEL(lineno);
            opt_table[optionals_list->size] = label;
            ADD_LABEL(ret, label);

            body->param.flags.has_opt = TRUE;
            body->param.opt_table = (const VALUE *)opt_table;
        }

        if (requireds_list && requireds_list->size) {
            body->param.lead_num = (int) requireds_list->size;
            body->param.flags.has_lead = true;

            for (size_t i = 0; i < requireds_list->size; i++) {
                pm_node_t *required_param = requireds_list->nodes[i];
                // TODO: Fix MultiTargetNodes
                if (PM_NODE_TYPE_P(required_param, PM_MULTI_TARGET_NODE)) {
                    PM_COMPILE(required_param);
                }
            }
        }

        if (posts_list && posts_list->size) {
            body->param.post_num = (int) posts_list->size;
            body->param.post_start = body->param.lead_num + body->param.opt_num; // TODO
            body->param.flags.has_post = true;
        }

        // Keywords create an internal variable on the parse tree
        if (keywords_list && keywords_list->size) {
            body->param.keyword = keyword = ZALLOC_N(struct rb_iseq_param_keyword, 1);
            keyword->num = (int) keywords_list->size;

            body->param.flags.has_kw = true;
            const VALUE default_values = rb_ary_hidden_new(1);
            const VALUE complex_mark = rb_str_tmp_new(0);

            ID *ids = calloc(keywords_list->size, sizeof(ID));

            for (size_t i = 0; i < keywords_list->size; i++) {
                pm_node_t *keyword_parameter_node = keywords_list->nodes[i];

                switch PM_NODE_TYPE(keyword_parameter_node) {
                  case PM_OPTIONAL_KEYWORD_PARAMETER_NODE: {
                      pm_node_t *value = ((pm_optional_keyword_parameter_node_t *)keyword_parameter_node)->value;

                      if (pm_static_literal_p(value)) {
                          rb_ary_push(default_values, pm_static_literal_value(value, scope_node, parser));
                      }
                      else {
                          PM_COMPILE_POPPED(value);
                          rb_ary_push(default_values, complex_mark);
                      }

                      break;
                  }
                  case PM_REQUIRED_KEYWORD_PARAMETER_NODE: {
                      pm_required_keyword_parameter_node_t *cast = (pm_required_keyword_parameter_node_t *)keyword_parameter_node;
                      ids[keyword->required_num] = pm_constant_id_lookup(scope_node, cast->name);
                      keyword->required_num++;
                      break;
                  }
                  default: {
                      rb_bug("Unexpected keyword parameter node type");
                  }
                }
            }

            VALUE *dvs = ALLOC_N(VALUE, RARRAY_LEN(default_values));

            for (int i = 0; i < RARRAY_LEN(default_values); i++) {
                VALUE dv = RARRAY_AREF(default_values, i);
                if (dv == complex_mark) dv = Qundef;
                if (!SPECIAL_CONST_P(dv)) {
                    RB_OBJ_WRITTEN(iseq, Qundef, dv);
                }
                dvs[i] = dv;
            }

            keyword->default_values = dvs;
            keyword->table = ids;
        }

        if (parameters_node) {
            if (parameters_node->rest) {
                body->param.rest_start = body->param.lead_num + body->param.opt_num;
                body->param.flags.has_rest = true;
            }

            if (parameters_node->keyword_rest) {
                if (PM_NODE_TYPE_P(parameters_node->keyword_rest, PM_NO_KEYWORDS_PARAMETER_NODE)) {
                    body->param.flags.accepts_no_kwarg = true;
                }
                else {
                    if (!body->param.flags.has_kw) {
                        body->param.keyword = keyword = ZALLOC_N(struct rb_iseq_param_keyword, 1);
                    }
                    keyword->rest_start = (int) locals_size;
                    body->param.flags.has_kwrest = true;
                }
            }

            if (parameters_node->block) {
                body->param.block_start = (int) locals_size - 1;
                body->param.flags.has_block = true;
            }
        }

        iseq_set_local_table(iseq, tbl);

        switch (body->type) {
          case ISEQ_TYPE_BLOCK: {
            LABEL *start = ISEQ_COMPILE_DATA(iseq)->start_label = NEW_LABEL(0);
            LABEL *end = ISEQ_COMPILE_DATA(iseq)->end_label = NEW_LABEL(0);

            start->rescued = LABEL_RESCUE_BEG;
            end->rescued = LABEL_RESCUE_END;

            ADD_TRACE(ret, RUBY_EVENT_B_CALL);
            NODE dummy_line_node = generate_dummy_line_node(body->location.first_lineno, -1);
            ADD_INSN (ret, &dummy_line_node, nop);
            ADD_LABEL(ret, start);

            if (scope_node->body) {
                switch (PM_NODE_TYPE(scope_node->ast_node)) {
                  case PM_POST_EXECUTION_NODE: {
                    pm_post_execution_node_t *post_execution_node = (pm_post_execution_node_t *)scope_node->ast_node;

                    ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));

                    // We create another ScopeNode from the statements within the PostExecutionNode
                    pm_scope_node_t next_scope_node;
                    pm_scope_node_init((pm_node_t *)post_execution_node->statements, &next_scope_node, scope_node, parser);

                    const rb_iseq_t *block = NEW_CHILD_ISEQ(next_scope_node, make_name_for_block(body->parent_iseq), ISEQ_TYPE_BLOCK, lineno);

                    ADD_CALL_WITH_BLOCK(ret, &dummy_line_node, id_core_set_postexe, INT2FIX(0), block);
                    break;
                  }
                  case PM_FOR_NODE: {
                    pm_for_node_t *for_node = (pm_for_node_t *)scope_node->ast_node;

                    ADD_GETLOCAL(ret, &dummy_line_node, 1, 0);
                    PM_COMPILE(for_node->index);
                    ADD_INSN(ret, &dummy_line_node, nop);
                  }
                  default: {
                    pm_compile_node(iseq, (pm_node_t *)(scope_node->body), ret, src, popped, scope_node);
                  }
                }
            }
            else {
                PM_PUTNIL;
            }

            ADD_LABEL(ret, end);
            ADD_TRACE(ret, RUBY_EVENT_B_RETURN);
            ISEQ_COMPILE_DATA(iseq)->last_line = body->location.code_location.end_pos.lineno;

            /* wide range catch handler must put at last */
            ADD_CATCH_ENTRY(CATCH_TYPE_REDO, start, end, NULL, start);
            ADD_CATCH_ENTRY(CATCH_TYPE_NEXT, start, end, NULL, end);
            break;
        }
        case ISEQ_TYPE_ENSURE: {
            iseq_set_exception_local_table(iseq);
            PM_COMPILE((pm_node_t *)scope_node->body);
            PM_POP;

            ADD_GETLOCAL(ret, &dummy_line_node, 1, 0);
            ADD_INSN1(ret, &dummy_line_node, throw, INT2FIX(0));

            return;
        }
        default:
            if (scope_node->body) {
                PM_COMPILE((pm_node_t *)scope_node->body);
            }
            else {
                PM_PUTNIL;
            }
        }

        free(index_lookup_table);

        if (!PM_NODE_TYPE_P(scope_node->ast_node, PM_ENSURE_NODE)) {
            ADD_INSN(ret, &dummy_line_node, leave);
        }
        return;
      }
      case PM_SELF_NODE:
        if (!popped) {
            PM_PUTSELF;
        }
        return;
      case PM_SINGLETON_CLASS_NODE: {
        pm_singleton_class_node_t *singleton_class_node = (pm_singleton_class_node_t *)node;
        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *)singleton_class_node, &next_scope_node, scope_node, parser);

        const rb_iseq_t *singleton_class = NEW_ISEQ(next_scope_node, rb_fstring_lit("singleton class"), ISEQ_TYPE_CLASS, lineno);

        PM_COMPILE_NOT_POPPED(singleton_class_node->expression);
        PM_PUTNIL;
        ID singletonclass;
        CONST_ID(singletonclass, "singletonclass");

        ADD_INSN3(ret, &dummy_line_node, defineclass,
                ID2SYM(singletonclass), singleton_class,
                INT2FIX(VM_DEFINECLASS_TYPE_SINGLETON_CLASS));
        PM_POP_IF_POPPED;
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)singleton_class);

        return;
      }
      case PM_SOURCE_ENCODING_NODE: {
        // Source encoding nodes are generated by the __ENCODING__ syntax. They
        // reference the encoding object corresponding to the encoding of the
        // source file, and can be changed by a magic encoding comment.
        if (!popped) {
            VALUE value = pm_static_literal_value(node, scope_node, parser);
            ADD_INSN1(ret, &dummy_line_node, putobject, value);
            RB_OBJ_WRITTEN(iseq, Qundef, value);
        }
        return;
      }
      case PM_SOURCE_FILE_NODE: {
        // Source file nodes are generated by the __FILE__ syntax. They
        // reference the file name of the source file.
        if (!popped) {
            VALUE value = pm_static_literal_value(node, scope_node, parser);
            ADD_INSN1(ret, &dummy_line_node, putstring, value);
            RB_OBJ_WRITTEN(iseq, Qundef, value);
        }
        return;
      }
      case PM_SOURCE_LINE_NODE: {
        // Source line nodes are generated by the __LINE__ syntax. They
        // reference the line number where they occur in the source file.
        if (!popped) {
            VALUE value = pm_static_literal_value(node, scope_node, parser);
            ADD_INSN1(ret, &dummy_line_node, putobject, value);
            RB_OBJ_WRITTEN(iseq, Qundef, value);
        }
        return;
      }
      case PM_SPLAT_NODE: {
        pm_splat_node_t *splat_node = (pm_splat_node_t *)node;
        if (splat_node->expression) {
            PM_COMPILE(splat_node->expression);
        }

        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, splatarray, Qtrue);
        }
        return;
      }
      case PM_STATEMENTS_NODE: {
        pm_statements_node_t *statements_node = (pm_statements_node_t *) node;
        pm_node_list_t node_list = statements_node->body;
        if (node_list.size > 0) {
            for (size_t index = 0; index < node_list.size - 1; index++) {
                PM_COMPILE_POPPED(node_list.nodes[index]);
            }
            PM_COMPILE(node_list.nodes[node_list.size - 1]);
        }
        else {
            PM_PUTNIL;
        }
        return;
      }
      case PM_STRING_CONCAT_NODE: {
        pm_string_concat_node_t *str_concat_node = (pm_string_concat_node_t *)node;
        PM_COMPILE(str_concat_node->left);
        PM_COMPILE(str_concat_node->right);
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, concatstrings, INT2FIX(2));
        }
        return;
      }
      case PM_STRING_NODE: {
        if (!popped) {
            pm_string_node_t *string_node = (pm_string_node_t *) node;
            ADD_INSN1(ret, &dummy_line_node, putstring, parse_string(&string_node->unescaped, parser));
        }
        return;
      }
      case PM_SUPER_NODE: {
        pm_super_node_t *super_node = (pm_super_node_t *) node;

        DECL_ANCHOR(args);

        int flags = 0;
        struct rb_callinfo_kwarg *keywords = NULL;
        const rb_iseq_t *parent_block = ISEQ_COMPILE_DATA(iseq)->current_block;

        INIT_ANCHOR(args);
        ISEQ_COMPILE_DATA(iseq)->current_block = NULL;

        ADD_INSN(ret, &dummy_line_node, putself);

        int argc = pm_setup_args(super_node->arguments, &flags, &keywords, iseq, ret, src, popped, scope_node, dummy_line_node, parser);

        flags |= VM_CALL_SUPER | VM_CALL_FCALL;

        if (super_node->block) {
            switch (PM_NODE_TYPE(super_node->block)) {
              case PM_BLOCK_ARGUMENT_NODE: {
                PM_COMPILE_NOT_POPPED(super_node->block);
                flags |= VM_CALL_ARGS_BLOCKARG;
                break;
              }
              case PM_BLOCK_NODE: {
                pm_scope_node_t next_scope_node;
                pm_scope_node_init(super_node->block, &next_scope_node, scope_node, parser);
                parent_block = NEW_CHILD_ISEQ(next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
                break;
              }
              default: {
                rb_bug("This node type should never occur on a SuperNode's block");
              }
            }
        }

        ADD_SEQ(ret, args);
        ADD_INSN2(ret, &dummy_line_node, invokesuper,
                new_callinfo(iseq, 0, argc, flags, keywords, parent_block != NULL),
                parent_block);

        PM_POP_IF_POPPED;
        return;
      }
      case PM_SYMBOL_NODE: {
        // Symbols nodes are symbol literals with no interpolation. They are
        // always marked as static literals.
        if (!popped) {
            VALUE value = pm_static_literal_value(node, scope_node, parser);
            ADD_INSN1(ret, &dummy_line_node, putobject, value);
            RB_OBJ_WRITTEN(iseq, Qundef, value);
        }
        return;
      }
      case PM_TRUE_NODE:
        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        }
        return;
      case PM_UNDEF_NODE: {
        pm_undef_node_t *undef_node = (pm_undef_node_t *) node;

        for (size_t index = 0; index < undef_node->names.size; index++) {
            ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
            ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CBASE));

            PM_COMPILE_NOT_POPPED(undef_node->names.nodes[index]);

            ADD_SEND(ret, &dummy_line_node, id_core_undef_method, INT2NUM(2));

            if (index < undef_node->names.size - 1) {
                PM_POP;
            }
        }

        PM_POP_IF_POPPED;

        return;
      }
      case PM_UNLESS_NODE: {
        const int line = (int)pm_newline_list_line_column(&(parser->newline_list), node->location.start).line;
        pm_unless_node_t *unless_node = (pm_unless_node_t *)node;
        pm_node_t *node_body = (pm_node_t *)(unless_node->statements);
        pm_statements_node_t *node_else = NULL;
        if (unless_node->consequent != NULL) {
            node_else = ((pm_else_node_t *)unless_node->consequent)->statements;
        }
        pm_node_t *predicate = unless_node->predicate;

        pm_compile_if(iseq, line, node_else, node_body, predicate, ret, src, popped, scope_node);
        return;
      }
      case PM_UNTIL_NODE: {
        pm_until_node_t *until_node = (pm_until_node_t *)node;
        pm_statements_node_t *statements = until_node->statements;
        pm_node_t *predicate = until_node->predicate;
        pm_node_flags_t flags = node->flags;

        pm_compile_while(iseq, lineno, flags, node->type, statements, predicate, ret, src, popped, scope_node);
        return;
      }
      case PM_WHEN_NODE: {
        rb_bug("Should not ever enter a when node directly");

        return;
      }
      case PM_WHILE_NODE: {
        pm_while_node_t *while_node = (pm_while_node_t *)node;
        pm_statements_node_t *statements = while_node->statements;
        pm_node_t *predicate = while_node->predicate;
        pm_node_flags_t flags = node->flags;

        pm_compile_while(iseq, lineno, flags, node->type, statements, predicate, ret, src, popped, scope_node);
        return;
      }
      case PM_X_STRING_NODE: {
        pm_x_string_node_t *xstring_node = (pm_x_string_node_t *) node;
        PM_PUTSELF;
        ADD_INSN1(ret, &dummy_line_node, putobject, parse_string(&xstring_node->unescaped, parser));
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, idBackquote, INT2NUM(1), INT2FIX(VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE));

        PM_POP_IF_POPPED;
        return;
      }
      case PM_YIELD_NODE: {
        pm_yield_node_t *yield_node = (pm_yield_node_t *)node;

        unsigned int flag = 0;
        struct rb_callinfo_kwarg *keywords = NULL;

        int argc = 0;

        if (yield_node->arguments) {
            PM_COMPILE((pm_node_t *)yield_node->arguments);

            argc = (int) yield_node->arguments->arguments.size;
        }

        ADD_INSN1(ret, &dummy_line_node, invokeblock, new_callinfo(iseq, 0, argc, flag, keywords, FALSE));

        PM_POP_IF_POPPED;

        int level = 0;
        const rb_iseq_t *tmp_iseq = iseq;
        for (; tmp_iseq != ISEQ_BODY(iseq)->local_iseq; level++ ) {
            tmp_iseq = ISEQ_BODY(tmp_iseq)->parent_iseq;
        }

        if (level > 0) access_outer_variables(iseq, level, rb_intern("yield"), true);

        return;
      }
      default:
        rb_raise(rb_eNotImpError, "node type %s not implemented", pm_node_type_to_str(PM_NODE_TYPE(node)));
        return;
    }
}

static VALUE
rb_translate_prism(pm_parser_t *parser, rb_iseq_t *iseq, pm_scope_node_t *scope_node, LINK_ANCHOR *const ret)
{
    RUBY_ASSERT(ISEQ_COMPILE_DATA(iseq));

    ID *constants = calloc(parser->constant_pool.size, sizeof(ID));
    rb_encoding *encoding = rb_enc_find(parser->encoding.name);
    for (uint32_t index = 0; index < parser->constant_pool.size; index++) {
        pm_constant_t *constant = &parser->constant_pool.constants[index];
        constants[index] = rb_intern3((const char *) constant->start, constant->length, encoding);
    }

    st_table *index_lookup_table = st_init_numtable();
    pm_constant_id_list_t *locals = &scope_node->locals;
    for (size_t i = 0; i < locals->size; i++) {
        st_insert(index_lookup_table, locals->ids[i], i);
    }
    scope_node->constants = constants;
    scope_node->index_lookup_table = index_lookup_table;

    pm_compile_node(iseq, (pm_node_t *)scope_node, ret, scope_node->base.location.start, false, (pm_scope_node_t *)scope_node);
    iseq_set_sequence(iseq, ret);

    free(constants);
    return Qnil;
}

#undef NEW_ISEQ
#define NEW_ISEQ OLD_ISEQ

#undef NEW_CHILD_ISEQ
#define NEW_CHILD_ISEQ OLD_CHILD_ISEQ
