#include "prism.h"

/******************************************************************************/
/* These macros operate on pm_line_column_t structs as opposed to NODE*s.     */
/******************************************************************************/

#define PUSH_ADJUST(seq, location, label) \
    ADD_ELEM((seq), (LINK_ELEMENT *) new_adjust_body(iseq, (label), (int) (location).line))

#define PUSH_ADJUST_RESTORE(seq, label) \
    ADD_ELEM((seq), (LINK_ELEMENT *) new_adjust_body(iseq, (label), -1))

#define PUSH_INSN(seq, location, insn) \
    ADD_ELEM((seq), (LINK_ELEMENT *) new_insn_body(iseq, (int) (location).line, (int) (location).column, BIN(insn), 0))

#define PUSH_INSN1(seq, location, insn, op1) \
    ADD_ELEM((seq), (LINK_ELEMENT *) new_insn_body(iseq, (int) (location).line, (int) (location).column, BIN(insn), 1, (VALUE)(op1)))

#define PUSH_INSNL(seq, location, insn, label) \
    (PUSH_INSN1(seq, location, insn, label), LABEL_REF(label))

#define PUSH_INSN2(seq, location, insn, op1, op2) \
    ADD_ELEM((seq), (LINK_ELEMENT *) new_insn_body(iseq, (int) (location).line, (int) (location).column, BIN(insn), 2, (VALUE)(op1), (VALUE)(op2)))

#define PUSH_INSN3(seq, location, insn, op1, op2, op3) \
    ADD_ELEM((seq), (LINK_ELEMENT *) new_insn_body(iseq, (int) (location).line, (int) (location).column, BIN(insn), 3, (VALUE)(op1), (VALUE)(op2), (VALUE)(op3)))

#define PUSH_LABEL(seq, label) \
    ADD_ELEM((seq), (LINK_ELEMENT *) (label))

#define PUSH_SEND_R(seq, location, id, argc, block, flag, keywords) \
    ADD_ELEM((seq), (LINK_ELEMENT *) new_insn_send(iseq, (int) (location).line, (int) (location).column, (id), (VALUE)(argc), (block), (VALUE)(flag), (keywords)))

#define PUSH_SEND(seq, location, id, argc) \
    PUSH_SEND_R((seq), location, (id), (argc), NULL, (VALUE)INT2FIX(0), NULL)

#define PUSH_SEND_WITH_FLAG(seq, location, id, argc, flag) \
    PUSH_SEND_R((seq), location, (id), (argc), NULL, (VALUE)(flag), NULL)

#define PUSH_TRACE(seq, event) \
  ADD_ELEM((seq), (LINK_ELEMENT *) new_trace_body(iseq, (event), 0))

/******************************************************************************/
/* These are helper macros for the compiler.                                  */
/******************************************************************************/

#define OLD_ISEQ NEW_ISEQ
#undef NEW_ISEQ

#define NEW_ISEQ(node, name, type, line_no) \
    pm_new_child_iseq(iseq, (node), rb_fstring(name), 0, (type), (line_no))

#define OLD_CHILD_ISEQ NEW_CHILD_ISEQ
#undef NEW_CHILD_ISEQ

#define NEW_CHILD_ISEQ(node, name, type, line_no) \
    pm_new_child_iseq(iseq, (node), rb_fstring(name), iseq, (type), (line_no))

#define PM_COMPILE(node) \
    pm_compile_node(iseq, (node), ret, popped, scope_node)

#define PM_COMPILE_INTO_ANCHOR(_ret, node) \
    pm_compile_node(iseq, (node), _ret, popped, scope_node)

#define PM_COMPILE_POPPED(node) \
    pm_compile_node(iseq, (node), ret, true, scope_node)

#define PM_COMPILE_NOT_POPPED(node) \
    pm_compile_node(iseq, (node), ret, false, scope_node)

#define PM_POP \
    ADD_INSN(ret, &dummy_line_node, pop)

#define PM_POP_IF_POPPED \
    if (popped) PM_POP

#define PM_POP_UNLESS_POPPED \
    if (!popped) PM_POP

#define PM_DUP \
    ADD_INSN(ret, &dummy_line_node, dup)

#define PM_DUP_UNLESS_POPPED \
    if (!popped) PM_DUP

#define PM_PUTSELF \
    ADD_INSN(ret, &dummy_line_node, putself)

#define PM_PUTNIL \
    ADD_INSN(ret, &dummy_line_node, putnil)

#define PM_PUTNIL_UNLESS_POPPED \
    if (!popped) PM_PUTNIL

#define PM_SWAP \
    ADD_INSN(ret, &dummy_line_node, swap)

#define PM_SWAP_UNLESS_POPPED \
    if (!popped) PM_SWAP

#define PM_NOP \
    ADD_INSN(ret, &dummy_line_node, nop)

#define PM_SPECIAL_CONSTANT_FLAG ((pm_constant_id_t)(1 << 31))
#define PM_CONSTANT_AND ((pm_constant_id_t)(idAnd | PM_SPECIAL_CONSTANT_FLAG))
#define PM_CONSTANT_DOT3 ((pm_constant_id_t)(idDot3 | PM_SPECIAL_CONSTANT_FLAG))
#define PM_CONSTANT_MULT ((pm_constant_id_t)(idMULT | PM_SPECIAL_CONSTANT_FLAG))
#define PM_CONSTANT_POW ((pm_constant_id_t)(idPow | PM_SPECIAL_CONSTANT_FLAG))

static int
pm_location_line_number(const pm_parser_t *parser, const pm_location_t *location) {
    return (int) pm_newline_list_line_column(&parser->newline_list, location->start, parser->start_line).line;
}

static int
pm_node_line_number(const pm_parser_t *parser, const pm_node_t *node)
{
    return (int) pm_newline_list_line_column(&parser->newline_list, node->location.start, parser->start_line).line;
}

/**
 * Convert the value of an integer node into a Ruby Integer.
 */
static VALUE
parse_integer(const pm_integer_node_t *node)
{
    const pm_integer_t *integer = &node->value;
    VALUE result;

    if (integer->values == NULL) {
        result = UINT2NUM(integer->value);
    }
    else {
        VALUE string = rb_str_new(NULL, integer->length * 8);
        unsigned char *bytes = (unsigned char *) RSTRING_PTR(string);

        size_t offset = integer->length * 8;
        for (size_t value_index = 0; value_index < integer->length; value_index++) {
            uint32_t value = integer->values[value_index];

            for (int index = 0; index < 8; index++) {
                int byte = (value >> (4 * index)) & 0xf;
                bytes[--offset] = byte < 10 ? byte + '0' : byte - 10 + 'a';
            }
        }

        result = rb_funcall(string, rb_intern("to_i"), 1, UINT2NUM(16));
    }

    if (integer->negative) {
        result = rb_funcall(result, rb_intern("-@"), 0);
    }

    return result;
}

/**
 * Convert the value of a float node into a Ruby Float.
 */
static VALUE
parse_float(const pm_float_node_t *node)
{
    return DBL2NUM(node->value);
}

/**
 * Convert the value of a rational node into a Ruby Rational. Rational nodes can
 * either be wrapping an integer node or a float node. If it's an integer node,
 * we can reuse our parsing. If it's not, then we'll parse the numerator and
 * then parse the denominator and create the rational from those two values.
 */
static VALUE
parse_rational(const pm_rational_node_t *node)
{
    VALUE result;

    if (PM_NODE_TYPE_P(node->numeric, PM_FLOAT_NODE)) {
        const uint8_t *start = node->base.location.start;
        const uint8_t *end = node->base.location.end - 1;
        size_t length = end - start;

        char *buffer = malloc(length + 1);
        memcpy(buffer, start, length);

        buffer[length] = '\0';

        char *decimal = memchr(buffer, '.', length);
        RUBY_ASSERT(decimal);
        size_t seen_decimal = decimal - buffer;
        size_t fraclen = length - seen_decimal - 1;
        memmove(decimal, decimal + 1, fraclen + 1);

        VALUE numerator = rb_cstr_to_inum(buffer, 10, false);
        result = rb_rational_new(numerator, rb_int_positive_pow(10, fraclen));

        free(buffer);
    }
    else {
        RUBY_ASSERT(PM_NODE_TYPE_P(node->numeric, PM_INTEGER_NODE));
        VALUE numerator = parse_integer((const pm_integer_node_t *) node->numeric);
        result = rb_rational_raw(numerator, INT2FIX(1));
    }

    return result;
}

/**
 * Convert the value of an imaginary node into a Ruby Complex. Imaginary nodes
 * can be wrapping an integer node, a float node, or a rational node. In all
 * cases we will reuse parsing functions seen above to get the inner value, and
 * then convert into an imaginary with rb_complex_raw.
 */
static VALUE
parse_imaginary(pm_imaginary_node_t *node)
{
    VALUE imaginary_part;
    switch (PM_NODE_TYPE(node->numeric)) {
      case PM_FLOAT_NODE: {
        imaginary_part = parse_float((const pm_float_node_t *) node->numeric);
        break;
      }
      case PM_INTEGER_NODE: {
        imaginary_part = parse_integer((const pm_integer_node_t *) node->numeric);
        break;
      }
      case PM_RATIONAL_NODE: {
        imaginary_part = parse_rational((const pm_rational_node_t *) node->numeric);
        break;
      }
      default:
        rb_bug("Unexpected numeric type on imaginary number %s\n", pm_node_type_to_str(PM_NODE_TYPE(node->numeric)));
    }

    return rb_complex_raw(INT2FIX(0), imaginary_part);
}

static inline VALUE
parse_string(const pm_scope_node_t *scope_node, const pm_string_t *string)
{
    return rb_enc_str_new((const char *) pm_string_source(string), pm_string_length(string), scope_node->encoding);
}

/**
 * Certain strings can have their encoding differ from the parser's encoding due
 * to bytes or escape sequences that have the top bit set. This function handles
 * creating those strings based on the flags set on the owning node.
 */
static inline VALUE
parse_string_encoded(const pm_scope_node_t *scope_node, const pm_node_t *node, const pm_string_t *string)
{
    rb_encoding *encoding;

    if (node->flags & PM_ENCODING_FLAGS_FORCED_BINARY_ENCODING) {
        encoding = rb_ascii8bit_encoding();
    }
    else if (node->flags & PM_ENCODING_FLAGS_FORCED_UTF8_ENCODING) {
        encoding = rb_utf8_encoding();
    }
    else {
        encoding = scope_node->encoding;
    }

    return rb_enc_str_new((const char *) pm_string_source(string), pm_string_length(string), encoding);
}

static inline ID
parse_string_symbol(const pm_scope_node_t *scope_node, const pm_symbol_node_t *symbol)
{
    rb_encoding *encoding;
    if (symbol->base.flags & PM_SYMBOL_FLAGS_FORCED_UTF8_ENCODING) {
        encoding = rb_utf8_encoding();
    }
    else if (symbol->base.flags & PM_SYMBOL_FLAGS_FORCED_BINARY_ENCODING) {
        encoding = rb_ascii8bit_encoding();
    }
    else if (symbol->base.flags & PM_SYMBOL_FLAGS_FORCED_US_ASCII_ENCODING) {
        encoding = rb_usascii_encoding();
    }
    else {
        encoding = scope_node->encoding;
    }

    return rb_intern3((const char *) pm_string_source(&symbol->unescaped), pm_string_length(&symbol->unescaped), encoding);
}

static int
pm_optimizable_range_item_p(pm_node_t *node)
{
    return (!node || PM_NODE_TYPE_P(node, PM_INTEGER_NODE) || PM_NODE_TYPE_P(node, PM_NIL_NODE));
}

static void pm_compile_node(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node);

static int
pm_interpolated_node_compile(const pm_node_list_t *parts, rb_iseq_t *iseq, NODE dummy_line_node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node)
{
    int number_of_items_pushed = 0;
    size_t parts_size = parts->size;

    if (parts_size > 0) {
        VALUE current_string = Qnil;

        for (size_t index = 0; index < parts_size; index++) {
            const pm_node_t *part = parts->nodes[index];

            if (PM_NODE_TYPE_P(part, PM_STRING_NODE)) {
                const pm_string_node_t *string_node = (const pm_string_node_t *)part;
                VALUE string_value = parse_string_encoded(scope_node, (pm_node_t *)string_node, &string_node->unescaped);

                if (RTEST(current_string)) {
                    current_string = rb_str_concat(current_string, string_value);
                }
                else {
                    current_string = string_value;
                }
            }
            else if (PM_NODE_TYPE_P(part, PM_EMBEDDED_STATEMENTS_NODE) &&
                    ((const pm_embedded_statements_node_t *) part)->statements != NULL &&
                    ((const pm_embedded_statements_node_t *) part)->statements->body.size == 1 &&
                    PM_NODE_TYPE_P(((const pm_embedded_statements_node_t *) part)->statements->body.nodes[0], PM_STRING_NODE)) {
                const pm_string_node_t *string_node = (const pm_string_node_t *) ((const pm_embedded_statements_node_t *) part)->statements->body.nodes[0];
                VALUE string_value = parse_string_encoded(scope_node, (pm_node_t *)string_node, &string_node->unescaped);

                if (RTEST(current_string)) {
                    current_string = rb_str_concat(current_string, string_value);
                }
                else {
                    current_string = string_value;
                }
            }
            else {
                if (!RTEST(current_string)) {
                    current_string = rb_enc_str_new(NULL, 0, scope_node->encoding);
                }

                ADD_INSN1(ret, &dummy_line_node, putobject, rb_fstring(current_string));

                current_string = Qnil;
                number_of_items_pushed++;

                PM_COMPILE_NOT_POPPED(part);
                PM_DUP;
                ADD_INSN1(ret, &dummy_line_node, objtostring, new_callinfo(iseq, idTo_s, 0, VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE , NULL, FALSE));
                ADD_INSN(ret, &dummy_line_node, anytostring);

                number_of_items_pushed++;
            }
        }

        if (RTEST(current_string)) {
            current_string = rb_fstring(current_string);
            ADD_INSN1(ret, &dummy_line_node, putobject, current_string);
            current_string = Qnil;
            number_of_items_pushed++;
        }
    }
    else {
        PM_PUTNIL;
    }

    return number_of_items_pushed;
}

static VALUE
pm_static_literal_concat(const pm_node_list_t *nodes, const pm_scope_node_t *scope_node, bool top)
{
    VALUE current = Qnil;

    for (size_t index = 0; index < nodes->size; index++) {
        const pm_node_t *part = nodes->nodes[index];
        VALUE string;

        switch (PM_NODE_TYPE(part)) {
          case PM_STRING_NODE:
            string = parse_string_encoded(scope_node, part, &((const pm_string_node_t *) part)->unescaped);
            break;
          case PM_INTERPOLATED_STRING_NODE:
            string = pm_static_literal_concat(&((const pm_interpolated_string_node_t *) part)->parts, scope_node, false);
            break;
          default:
            RUBY_ASSERT(false && "unexpected node type in pm_static_literal_concat");
            return Qnil;
        }

        if (current != Qnil) {
            current = rb_str_concat(current, string);
        }
        else {
            current = string;
        }
    }

    return top ? rb_fstring(current) : current;
}

#define RE_OPTION_ENCODING_SHIFT 8
#define RE_OPTION_ENCODING(encoding) (((encoding) & 0xFF) << RE_OPTION_ENCODING_SHIFT)
#define ARG_ENCODING_NONE    32
#define ARG_ENCODING_FIXED   16
#define ENC_ASCII8BIT        1
#define ENC_EUC_JP           2
#define ENC_Windows_31J      3
#define ENC_UTF8             4

/**
 * Check the prism flags of a regular expression-like node and return the flags
 * that are expected by the CRuby VM.
 */
static int
parse_regexp_flags(const pm_node_t *node)
{
    int flags = 0;

    // Check "no encoding" first so that flags don't get clobbered
    // We're calling `rb_char_to_option_kcode` in this case so that
    // we don't need to have access to `ARG_ENCODING_NONE`
    if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT)) {
        flags |= ARG_ENCODING_NONE;
    }

    if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_EUC_JP)) {
        flags |= (ARG_ENCODING_FIXED | RE_OPTION_ENCODING(ENC_EUC_JP));
    }

    if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J)) {
        flags |= (ARG_ENCODING_FIXED | RE_OPTION_ENCODING(ENC_Windows_31J));
    }

    if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_UTF_8)) {
        flags |= (ARG_ENCODING_FIXED | RE_OPTION_ENCODING(ENC_UTF8));
    }

    if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE)) {
        flags |= ONIG_OPTION_IGNORECASE;
    }

    if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_MULTI_LINE)) {
        flags |= ONIG_OPTION_MULTILINE;
    }

    if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_EXTENDED)) {
        flags |= ONIG_OPTION_EXTEND;
    }

    return flags;
}

#undef RE_OPTION_ENCODING_SHIFT
#undef RE_OPTION_ENCODING
#undef ARG_ENCODING_FIXED
#undef ARG_ENCODING_NONE
#undef ENC_ASCII8BIT
#undef ENC_EUC_JP
#undef ENC_Windows_31J
#undef ENC_UTF8

static rb_encoding *
parse_regexp_encoding(const pm_scope_node_t *scope_node, const pm_node_t *node)
{
    if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT)) {
        return rb_ascii8bit_encoding();
    }
    else if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_UTF_8)) {
        return rb_utf8_encoding();
    }
    else if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_EUC_JP)) {
        return rb_enc_get_from_index(ENCINDEX_EUC_JP);
    }
    else if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J)) {
        return rb_enc_get_from_index(ENCINDEX_Windows_31J);
    }
    else {
        return scope_node->encoding;
    }
}

/** Raise an error corresponding to the invalid regular expression. */
static VALUE
parse_regexp_error(rb_iseq_t *iseq, int32_t line_number, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    VALUE error = rb_syntax_error_append(Qnil, rb_iseq_path(iseq), line_number, -1, NULL, "%" PRIsVALUE, args);
    va_end(args);
    rb_exc_raise(error);
}

static VALUE
parse_regexp(rb_iseq_t *iseq, const pm_scope_node_t *scope_node, const pm_node_t *node, VALUE string)
{
    VALUE errinfo = rb_errinfo();

    int32_t line_number = pm_node_line_number(scope_node->parser, node);
    VALUE regexp = rb_reg_compile(string, parse_regexp_flags(node), (const char *) pm_string_source(&scope_node->parser->filepath), line_number);

    if (NIL_P(regexp)) {
        VALUE message = rb_attr_get(rb_errinfo(), idMesg);
        rb_set_errinfo(errinfo);

        parse_regexp_error(iseq, line_number, "%" PRIsVALUE, message);
        return Qnil;
    }

    rb_obj_freeze(regexp);
    return regexp;
}

static inline VALUE
parse_regexp_literal(rb_iseq_t *iseq, const pm_scope_node_t *scope_node, const pm_node_t *node, const pm_string_t *unescaped)
{
    VALUE string = rb_enc_str_new((const char *) pm_string_source(unescaped), pm_string_length(unescaped), parse_regexp_encoding(scope_node, node));
    return parse_regexp(iseq, scope_node, node, string);
}

static inline VALUE
parse_regexp_concat(rb_iseq_t *iseq, const pm_scope_node_t *scope_node, const pm_node_t *node, const pm_node_list_t *parts)
{
    VALUE string = pm_static_literal_concat(parts, scope_node, false);
    rb_enc_associate(string, parse_regexp_encoding(scope_node, node));
    return parse_regexp(iseq, scope_node, node, string);
}

static void
pm_compile_regexp_dynamic(rb_iseq_t *iseq, const pm_node_t *node, const pm_node_list_t *parts, const pm_line_column_t *node_location, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(node_location->line, node_location->column);
    int length = pm_interpolated_node_compile(parts, iseq, dummy_line_node, ret, popped, scope_node);
    PUSH_INSN2(ret, *node_location, toregexp, INT2FIX(parse_regexp_flags(node) & 0xFF), INT2FIX(length));
}

/**
 * Certain nodes can be compiled literally. This function returns the literal
 * value described by the given node. For example, an array node with all static
 * literal values can be compiled into a literal array.
 */
static VALUE
pm_static_literal_value(rb_iseq_t *iseq, const pm_node_t *node, const pm_scope_node_t *scope_node)
{
    // Every node that comes into this function should already be marked as
    // static literal. If it's not, then we have a bug somewhere.
    RUBY_ASSERT(PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL));

    switch (PM_NODE_TYPE(node)) {
      case PM_ARRAY_NODE: {
        pm_array_node_t *cast = (pm_array_node_t *) node;
        pm_node_list_t *elements = &cast->elements;

        VALUE value = rb_ary_hidden_new(elements->size);
        for (size_t index = 0; index < elements->size; index++) {
            rb_ary_push(value, pm_static_literal_value(iseq, elements->nodes[index], scope_node));
        }

        OBJ_FREEZE(value);
        return value;
      }
      case PM_FALSE_NODE:
        return Qfalse;
      case PM_FLOAT_NODE:
        return parse_float((const pm_float_node_t *) node);
      case PM_HASH_NODE: {
        pm_hash_node_t *cast = (pm_hash_node_t *) node;
        pm_node_list_t *elements = &cast->elements;

        VALUE array = rb_ary_hidden_new(elements->size * 2);
        for (size_t index = 0; index < elements->size; index++) {
            RUBY_ASSERT(PM_NODE_TYPE_P(elements->nodes[index], PM_ASSOC_NODE));
            pm_assoc_node_t *cast = (pm_assoc_node_t *) elements->nodes[index];
            VALUE pair[2] = { pm_static_literal_value(iseq, cast->key, scope_node), pm_static_literal_value(iseq, cast->value, scope_node) };
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
        return parse_integer((const pm_integer_node_t *) node);
      case PM_INTERPOLATED_MATCH_LAST_LINE_NODE: {
        const pm_interpolated_match_last_line_node_t *cast = (const pm_interpolated_match_last_line_node_t *) node;
        return parse_regexp_concat(iseq, scope_node, (const pm_node_t *) cast, &cast->parts);
      }
      case PM_INTERPOLATED_REGULAR_EXPRESSION_NODE: {
        const pm_interpolated_regular_expression_node_t *cast = (const pm_interpolated_regular_expression_node_t *) node;
        return parse_regexp_concat(iseq, scope_node, (const pm_node_t *) cast, &cast->parts);
      }
      case PM_INTERPOLATED_STRING_NODE:
        return pm_static_literal_concat(&((const pm_interpolated_string_node_t *) node)->parts, scope_node, true);
      case PM_INTERPOLATED_SYMBOL_NODE: {
        const pm_interpolated_symbol_node_t *cast = (const pm_interpolated_symbol_node_t *) node;
        VALUE string = pm_static_literal_concat(&cast->parts, scope_node, true);

        return ID2SYM(rb_intern_str(string));
      }
      case PM_MATCH_LAST_LINE_NODE: {
        const pm_match_last_line_node_t *cast = (const pm_match_last_line_node_t *) node;
        return parse_regexp_literal(iseq, scope_node, (const pm_node_t *) cast, &cast->unescaped);
      }
      case PM_NIL_NODE:
        return Qnil;
      case PM_RATIONAL_NODE:
        return parse_rational((const pm_rational_node_t *) node);
      case PM_REGULAR_EXPRESSION_NODE: {
        const pm_regular_expression_node_t *cast = (const pm_regular_expression_node_t *) node;
        return parse_regexp_literal(iseq, scope_node, (const pm_node_t *) cast, &cast->unescaped);
      }
      case PM_SOURCE_ENCODING_NODE:
        return rb_enc_from_encoding(scope_node->encoding);
      case PM_SOURCE_FILE_NODE: {
        const pm_source_file_node_t *cast = (const pm_source_file_node_t *) node;
        size_t length = pm_string_length(&cast->filepath);

        if (length > 0) {
            return rb_enc_str_new((const char *) pm_string_source(&cast->filepath), length, scope_node->encoding);
        }
        else {
            return rb_fstring_lit("<compiled>");
        }
      }
      case PM_SOURCE_LINE_NODE:
        return INT2FIX(pm_node_line_number(scope_node->parser, node));
      case PM_STRING_NODE:
        return rb_fstring(parse_string_encoded(scope_node, node, &((pm_string_node_t *)node)->unescaped));
      case PM_SYMBOL_NODE:
        return ID2SYM(parse_string_symbol(scope_node, (const pm_symbol_node_t *) node));
      case PM_TRUE_NODE:
        return Qtrue;
      default:
        rb_bug("Don't have a literal value for node type %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
        return Qfalse;
    }
}

/**
 * Currently, the ADD_INSN family of macros expects a NODE as the second
 * parameter. It uses this node to determine the line number and the node ID for
 * the instruction.
 *
 * Because prism does not use the NODE struct (or have node IDs for that matter)
 * we need to generate a dummy node to pass to these macros. We also need to use
 * the line number from the node to generate labels.
 *
 * We use this struct to store the dummy node and the line number together so
 * that we can use it while we're compiling code.
 *
 * In the future, we'll need to eventually remove this dependency and figure out
 * a more permanent solution. For the line numbers, this shouldn't be too much
 * of a problem, we can redefine the ADD_INSN family of macros. For the node ID,
 * we can probably replace it directly with the column information since we have
 * that at the time that we're generating instructions. In theory this could
 * make node ID unnecessary.
 */
typedef struct {
    NODE node;
    int lineno;
} pm_line_node_t;

/**
 * The function generates a dummy node and stores the line number after it looks
 * it up for the given scope and node. (The scope in this case is just used
 * because it holds a reference to the parser, which holds a reference to the
 * newline list that we need to look up the line numbers.)
 */
static void
pm_line_node(pm_line_node_t *line_node, const pm_scope_node_t *scope_node, const pm_node_t *node)
{
    // First, clear out the pointer.
    memset(line_node, 0, sizeof(pm_line_node_t));

    // Next, use the line number for the dummy node.
    int lineno = pm_node_line_number(scope_node->parser, node);

    nd_set_line(&line_node->node, lineno);
    nd_set_node_id(&line_node->node, lineno);
    line_node->lineno = lineno;
}

static void
pm_compile_branch_condition(rb_iseq_t *iseq, LINK_ANCHOR *const ret, const pm_node_t *cond,
                         LABEL *then_label, LABEL *else_label, bool popped, pm_scope_node_t *scope_node);

static void
pm_compile_logical(rb_iseq_t *iseq, LINK_ANCHOR *const ret, pm_node_t *cond, LABEL *then_label, LABEL *else_label, bool popped, pm_scope_node_t *scope_node)
{
    int lineno = pm_node_line_number(scope_node->parser, cond);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    DECL_ANCHOR(seq);
    INIT_ANCHOR(seq);
    LABEL *label = NEW_LABEL(lineno);
    if (!then_label) then_label = label;
    else if (!else_label) else_label = label;

    pm_compile_branch_condition(iseq, seq, cond, then_label, else_label, popped, scope_node);

    if (LIST_INSN_SIZE_ONE(seq)) {
        INSN *insn = (INSN *)ELEM_FIRST_INSN(FIRST_ELEMENT(seq));
        if (insn->insn_id == BIN(jump) && (LABEL *)(insn->operands[0]) == label)
            return;
    }
    if (!label->refcnt) {
        if (popped) {
            PM_PUTNIL;
        }
    }
    else {
        ADD_LABEL(seq, label);
    }
    ADD_SEQ(ret, seq);
    return;
}

static void
pm_compile_flip_flop_bound(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(ISEQ_BODY(iseq)->location.first_lineno, -1);

    if (PM_NODE_TYPE_P(node, PM_INTEGER_NODE)) {
        PM_COMPILE_NOT_POPPED(node);
        ADD_INSN1(ret, &dummy_line_node, getglobal, ID2SYM(rb_intern("$.")));
        ADD_SEND(ret, &dummy_line_node, idEq, INT2FIX(1));
        PM_POP_IF_POPPED;
    }
    else {
        PM_COMPILE(node);
    }
}

static void
pm_compile_flip_flop(const pm_flip_flop_node_t *flip_flop_node, LABEL *else_label, LABEL *then_label, rb_iseq_t *iseq, const int lineno, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(ISEQ_BODY(iseq)->location.first_lineno, -1);
    LABEL *lend = NEW_LABEL(lineno);

    int again = !(flip_flop_node->base.flags & PM_RANGE_FLAGS_EXCLUDE_END);

    rb_num_t count = ISEQ_FLIP_CNT_INCREMENT(ISEQ_BODY(iseq)->local_iseq) + VM_SVAR_FLIPFLOP_START;
    VALUE key = INT2FIX(count);

    ADD_INSN2(ret, &dummy_line_node, getspecial, key, INT2FIX(0));
    ADD_INSNL(ret, &dummy_line_node, branchif, lend);

    if (flip_flop_node->left) {
        pm_compile_flip_flop_bound(iseq, flip_flop_node->left, ret, popped, scope_node);
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
        pm_compile_flip_flop_bound(iseq, flip_flop_node->right, ret, popped, scope_node);
    }
    else {
        PM_PUTNIL;
    }

    ADD_INSNL(ret, &dummy_line_node, branchunless, then_label);
    ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse);
    ADD_INSN1(ret, &dummy_line_node, setspecial, key);
    ADD_INSNL(ret, &dummy_line_node, jump, then_label);
}

void pm_compile_defined_expr(rb_iseq_t *iseq, const pm_node_t *defined_node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node, NODE dummy_line_node, int lineno, bool in_condition);

static void
pm_compile_branch_condition(rb_iseq_t *iseq, LINK_ANCHOR *const ret, const pm_node_t *cond,
                         LABEL *then_label, LABEL *else_label, bool popped, pm_scope_node_t *scope_node)
{
    int lineno = pm_node_line_number(scope_node->parser, cond);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

again:
    switch (PM_NODE_TYPE(cond)) {
      case PM_AND_NODE: {
        pm_and_node_t *and_node = (pm_and_node_t *)cond;
        pm_compile_logical(iseq, ret, and_node->left, NULL, else_label, popped, scope_node);
        cond = and_node->right;
        goto again;
      }
      case PM_OR_NODE: {
        pm_or_node_t *or_node = (pm_or_node_t *)cond;
        pm_compile_logical(iseq, ret, or_node->left, then_label, NULL, popped, scope_node);
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
        pm_compile_flip_flop((const pm_flip_flop_node_t *) cond, else_label, then_label, iseq, lineno, ret, popped, scope_node);
        return;
      case PM_DEFINED_NODE: {
        pm_defined_node_t *defined_node = (pm_defined_node_t *)cond;
        pm_compile_defined_expr(iseq, defined_node->value, ret, popped, scope_node, dummy_line_node, lineno, true);
        break;
      }
      default: {
        pm_compile_node(iseq, cond, ret, false, scope_node);
        break;
      }
    }
    ADD_INSNL(ret, &dummy_line_node, branchunless, else_label);
    ADD_INSNL(ret, &dummy_line_node, jump, then_label);
    return;
}

/**
 * Compile an if or unless node.
 */
static void
pm_compile_conditional(rb_iseq_t *iseq, const pm_line_column_t *line_column, const pm_statements_node_t *statements, const pm_node_t *consequent, const pm_node_t *predicate, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node)
{
    const pm_line_column_t location = *line_column;
    LABEL *then_label = NEW_LABEL(location.line);
    LABEL *else_label = NEW_LABEL(location.line);
    LABEL *end_label = NULL;

    pm_compile_branch_condition(iseq, ret, predicate, then_label, else_label, false, scope_node);

    if (then_label->refcnt) {
        PUSH_LABEL(ret, then_label);

        DECL_ANCHOR(then_seq);
        INIT_ANCHOR(then_seq);

        if (statements) {
            pm_compile_node(iseq, (const pm_node_t *) statements, then_seq, popped, scope_node);
        }
        else if (!popped) {
            PUSH_INSN(then_seq, location, putnil);
        }

        if (else_label->refcnt) {
            end_label = NEW_LABEL(location.line);
            PUSH_INSNL(then_seq, location, jump, end_label);
            if (!popped) PUSH_INSN(then_seq, location, pop);
        }

        ADD_SEQ(ret, then_seq);
    }

    if (else_label->refcnt) {
        PUSH_LABEL(ret, else_label);

        DECL_ANCHOR(else_seq);
        INIT_ANCHOR(else_seq);

        if (consequent) {
            pm_compile_node(iseq, (const pm_node_t *) consequent, else_seq, popped, scope_node);
        }
        else if (!popped) {
            PUSH_INSN(else_seq, location, putnil);
        }

        ADD_SEQ(ret, else_seq);
    }

    if (end_label) {
        PUSH_LABEL(ret, end_label);
    }

    return;
}

/**
 * Compile a while or until loop.
 */
static void
pm_compile_loop(rb_iseq_t *iseq, const pm_line_column_t *line_column, pm_node_flags_t flags, enum pm_node_type type, const pm_statements_node_t *statements, const pm_node_t *predicate, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node)
{
    const pm_line_column_t location = *line_column;

    LABEL *prev_start_label = ISEQ_COMPILE_DATA(iseq)->start_label;
    LABEL *prev_end_label = ISEQ_COMPILE_DATA(iseq)->end_label;
    LABEL *prev_redo_label = ISEQ_COMPILE_DATA(iseq)->redo_label;

    // TODO: Deal with ensures in here
    LABEL *next_label = ISEQ_COMPILE_DATA(iseq)->start_label = NEW_LABEL(location.line); /* next  */
    LABEL *redo_label = ISEQ_COMPILE_DATA(iseq)->redo_label = NEW_LABEL(location.line);  /* redo  */
    LABEL *break_label = ISEQ_COMPILE_DATA(iseq)->end_label = NEW_LABEL(location.line);  /* break */
    LABEL *end_label = NEW_LABEL(location.line);
    LABEL *adjust_label = NEW_LABEL(location.line);

    LABEL *next_catch_label = NEW_LABEL(location.line);
    LABEL *tmp_label = NULL;

    // begin; end while true
    if (flags & PM_LOOP_FLAGS_BEGIN_MODIFIER) {
        tmp_label = NEW_LABEL(location.line);
        PUSH_INSNL(ret, location, jump, tmp_label);
    }
    else {
        // while true; end
        PUSH_INSNL(ret, location, jump, next_label);
    }

    PUSH_LABEL(ret, adjust_label);
    PUSH_INSN(ret, location, putnil);
    PUSH_LABEL(ret, next_catch_label);
    PUSH_INSN(ret, location, pop);
    PUSH_INSNL(ret, location, jump, next_label);
    if (tmp_label) PUSH_LABEL(ret, tmp_label);

    PUSH_LABEL(ret, redo_label);
    if (statements != NULL) PM_COMPILE_POPPED((const pm_node_t *) statements);

    PUSH_LABEL(ret, next_label);
    if (type == PM_WHILE_NODE) {
        pm_compile_branch_condition(iseq, ret, predicate, redo_label, end_label, popped, scope_node);
    }
    else if (type == PM_UNTIL_NODE) {
        pm_compile_branch_condition(iseq, ret, predicate, end_label, redo_label, popped, scope_node);
    }

    PUSH_LABEL(ret, end_label);
    PUSH_ADJUST_RESTORE(ret, adjust_label);
    PUSH_INSN(ret, location, putnil);

    PUSH_LABEL(ret, break_label);
    if (popped) PUSH_INSN(ret, location, pop);

    ADD_CATCH_ENTRY(CATCH_TYPE_BREAK, redo_label, break_label, NULL, break_label);
    ADD_CATCH_ENTRY(CATCH_TYPE_NEXT, redo_label, break_label, NULL, next_catch_label);
    ADD_CATCH_ENTRY(CATCH_TYPE_REDO, redo_label, break_label, NULL, ISEQ_COMPILE_DATA(iseq)->redo_label);

    ISEQ_COMPILE_DATA(iseq)->start_label = prev_start_label;
    ISEQ_COMPILE_DATA(iseq)->end_label = prev_end_label;
    ISEQ_COMPILE_DATA(iseq)->redo_label = prev_redo_label;
    return;
}

// This recurses through scopes and finds the local index at any scope level
// It also takes a pointer to depth, and increments depth appropriately
// according to the depth of the local.
static pm_local_index_t
pm_lookup_local_index(rb_iseq_t *iseq, const pm_scope_node_t *scope_node, pm_constant_id_t constant_id, int start_depth)
{
    pm_local_index_t lindex = { 0 };
    st_data_t local_index;

    int level;
    for (level = 0; level < start_depth; level++) {
        scope_node = scope_node->previous;
    }

    while (!st_lookup(scope_node->index_lookup_table, constant_id, &local_index)) {
        level++;

        if (scope_node->previous) {
            scope_node = scope_node->previous;
        }
        else {
            // We have recursed up all scope nodes
            // and have not found the local yet
            rb_bug("Local with constant_id %u does not exist", (unsigned int) constant_id);
        }
    }

    lindex.level = level;
    lindex.index = scope_node->local_table_for_iseq_size - (int) local_index;
    return lindex;
}

// This returns the CRuby ID which maps to the pm_constant_id_t
//
// Constant_ids in prism are indexes of the constants in prism's constant pool.
// We add a constants mapping on the scope_node which is a mapping from
// these constant_id indexes to the CRuby IDs that they represent.
// This helper method allows easy access to those IDs
static ID
pm_constant_id_lookup(const pm_scope_node_t *scope_node, pm_constant_id_t constant_id)
{
    if (constant_id < 1 || constant_id > scope_node->parser->constant_pool.size) {
        rb_bug("constant_id out of range: %u", (unsigned int)constant_id);
    }
    return scope_node->constants[constant_id - 1];
}

static rb_iseq_t *
pm_new_child_iseq(rb_iseq_t *iseq, pm_scope_node_t *node, VALUE name, const rb_iseq_t *parent, enum rb_iseq_type type, int line_no)
{
    debugs("[new_child_iseq]> ---------------------------------------\n");
    int isolated_depth = ISEQ_COMPILE_DATA(iseq)->isolated_depth;
    rb_iseq_t *ret_iseq = pm_iseq_new_with_opt(node, name,
            rb_iseq_path(iseq), rb_iseq_realpath(iseq),
            line_no, parent,
            isolated_depth ? isolated_depth + 1 : 0,
            type, ISEQ_COMPILE_DATA(iseq)->option);
    debugs("[new_child_iseq]< ---------------------------------------\n");
    return ret_iseq;
}

static int
pm_compile_class_path(LINK_ANCHOR *const ret, rb_iseq_t *iseq, const pm_node_t *constant_path_node, const NODE *line_node, bool popped, pm_scope_node_t *scope_node)
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

/**
 * Compile either a call and write node or a call or write node. These look like
 * method calls that are followed by a ||= or &&= operator.
 */
static void
pm_compile_call_and_or_write_node(bool and_node, pm_node_t *receiver, pm_node_t *value, pm_constant_id_t write_name, pm_constant_id_t read_name, bool safe_nav, LINK_ANCHOR *const ret, rb_iseq_t *iseq, int lineno, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    LABEL *lfin = NEW_LABEL(lineno);
    LABEL *lcfin = NEW_LABEL(lineno);
    LABEL *lskip = NULL;

    int flag = PM_NODE_TYPE_P(receiver, PM_SELF_NODE) ? VM_CALL_FCALL : 0;
    ID id_read_name = pm_constant_id_lookup(scope_node, read_name);

    PM_COMPILE_NOT_POPPED(receiver);
    if (safe_nav) {
        lskip = NEW_LABEL(lineno);
        PM_DUP;
        ADD_INSNL(ret, &dummy_line_node, branchnil, lskip);
    }

    PM_DUP;
    ADD_SEND_WITH_FLAG(ret, &dummy_line_node, id_read_name, INT2FIX(0), INT2FIX(flag));
    PM_DUP_UNLESS_POPPED;

    if (and_node) {
        ADD_INSNL(ret, &dummy_line_node, branchunless, lcfin);
    }
    else {
        ADD_INSNL(ret, &dummy_line_node, branchif, lcfin);
    }

    PM_POP_UNLESS_POPPED;
    PM_COMPILE_NOT_POPPED(value);

    if (!popped) {
        PM_SWAP;
        ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
    }

    ID id_write_name = pm_constant_id_lookup(scope_node, write_name);
    ADD_SEND_WITH_FLAG(ret, &dummy_line_node, id_write_name, INT2FIX(1), INT2FIX(flag));
    ADD_INSNL(ret, &dummy_line_node, jump, lfin);

    ADD_LABEL(ret, lcfin);
    if (!popped) PM_SWAP;

    ADD_LABEL(ret, lfin);

    if (lskip && popped) ADD_LABEL(ret, lskip);
    PM_POP;
    if (lskip && !popped) ADD_LABEL(ret, lskip);
}

/**
 * This function compiles a hash onto the stack. It is used to compile hash
 * literals and keyword arguments. It is assumed that if we get here that the
 * contents of the hash are not popped.
 */
static void
pm_compile_hash_elements(const pm_node_list_t *elements, int lineno, rb_iseq_t *iseq, LINK_ANCHOR *const ret, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    // If this element is not popped, then we need to create the
    // hash on the stack. Neighboring plain assoc nodes should be
    // grouped together (either by newhash or hash merge). Double
    // splat nodes should be merged using the mege_kwd method call.
    int assoc_length = 0;
    bool made_hash = false;

    for (size_t index = 0; index < elements->size; index++) {
        const pm_node_t *element = elements->nodes[index];

        switch (PM_NODE_TYPE(element)) {
          case PM_ASSOC_NODE: {
            // If this is a plain assoc node, then we can compile it directly
            // and then add to the number of assoc nodes we've seen so far.
            PM_COMPILE_NOT_POPPED(element);
            assoc_length++;
            break;
          }
          case PM_ASSOC_SPLAT_NODE: {
            // If we are at a splat and we have already compiled some elements
            // of the hash, then we need to either create the first hash or
            // merge the current elements into the existing hash.
            if (assoc_length > 0) {
                if (!made_hash) {
                    ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(assoc_length * 2));
                    ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                    PM_SWAP;
                    made_hash = true;
                }
                else {
                    // Here we are merging plain assoc nodes into the hash on
                    // the stack.
                    ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_ptr, INT2FIX(assoc_length * 2 + 1));

                    // Since we already have a hash on the stack, we need to set
                    // up the method call for the next merge that will occur.
                    ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                    PM_SWAP;
                }

                assoc_length = 0;
            }

            // If this is the first time we've seen a splat, then we need to
            // create a hash that we can merge into.
            if (!made_hash) {
                ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(0));
                made_hash = true;
            }

            // Now compile the splat node itself and merge it into the hash.
            PM_COMPILE_NOT_POPPED(element);
            ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_kwd, INT2FIX(2));

            // We know that any subsequent elements will need to be merged in
            // using one of the special core methods. So here we will put the
            // receiver of the merge and then swap it with the hash that is
            // going to be the first argument.
            if (index != elements->size - 1) {
                ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                PM_SWAP;
            }

            break;
          }
          default:
            RUBY_ASSERT("Invalid node type for hash" && false);
            break;
        }
    }

    if (!made_hash) {
        // If we haven't already made the hash, then this means we only saw
        // plain assoc nodes. In this case, we can just create the hash
        // directly.
        ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(assoc_length * 2));
    }
    else if (assoc_length > 0) {
        // If we have already made the hash, then we need to merge the remaining
        // assoc nodes into the hash on the stack.
        ADD_SEND(ret, &dummy_line_node, id_core_hash_merge_ptr, INT2FIX(assoc_length * 2 + 1));
    }
}

// This is details. Users should call pm_setup_args() instead.
static int
pm_setup_args_core(const pm_arguments_node_t *arguments_node, const pm_node_t *block, int *flags, const bool has_regular_blockarg, struct rb_callinfo_kwarg **kw_arg, rb_iseq_t *iseq, LINK_ANCHOR *const ret, pm_scope_node_t *scope_node, NODE dummy_line_node)
{
    int orig_argc = 0;
    bool has_splat = false;
    bool has_keyword_splat = false;

    if (arguments_node == NULL) {
        if (*flags & VM_CALL_FCALL) {
            *flags |= VM_CALL_VCALL;
        }
    }
    else {
        pm_node_list_t arguments_node_list = arguments_node->arguments;

        has_keyword_splat = (arguments_node->base.flags & PM_ARGUMENTS_NODE_FLAGS_CONTAINS_KEYWORD_SPLAT);

        // We count the number of elements post the splat node that are not keyword elements to
        // eventually pass as an argument to newarray
        int post_splat_counter = 0;

        for (size_t index = 0; index < arguments_node_list.size; index++) {
            const pm_node_t *argument = arguments_node_list.nodes[index];

            switch (PM_NODE_TYPE(argument)) {
              // A keyword hash node contains all keyword arguments as AssocNodes and AssocSplatNodes
              case PM_KEYWORD_HASH_NODE: {
                const pm_keyword_hash_node_t *keyword_arg = (const pm_keyword_hash_node_t *) argument;
                const pm_node_list_t *elements = &keyword_arg->elements;

                if (has_keyword_splat || has_splat) {
                    *flags |= VM_CALL_KW_SPLAT;
                    has_keyword_splat = true;
                    pm_compile_hash_elements(elements, nd_line(&dummy_line_node), iseq, ret, scope_node);
                }
                else {
                    // We need to first figure out if all elements of the
                    // KeywordHashNode are AssocNodes with symbol keys.
                    if (PM_NODE_FLAG_P(keyword_arg, PM_KEYWORD_HASH_NODE_FLAGS_SYMBOL_KEYS)) {
                        // If they are all symbol keys then we can pass them as
                        // keyword arguments. The first thing we need to do is
                        // deduplicate. We'll do this using the combination of a
                        // Ruby hash and a Ruby array.
                        VALUE stored_indices = rb_hash_new();
                        VALUE keyword_indices = rb_ary_new_capa(elements->size);

                        size_t size = 0;
                        for (size_t element_index = 0; element_index < elements->size; element_index++) {
                            const pm_assoc_node_t *assoc = (const pm_assoc_node_t *) elements->nodes[element_index];

                            // Retrieve the stored index from the hash for this
                            // keyword.
                            VALUE keyword = pm_static_literal_value(iseq, assoc->key, scope_node);
                            VALUE stored_index = rb_hash_aref(stored_indices, keyword);

                            // If this keyword was already seen in the hash,
                            // then mark the array at that index as false and
                            // decrement the keyword size.
                            if (!NIL_P(stored_index)) {
                                rb_ary_store(keyword_indices, NUM2LONG(stored_index), Qfalse);
                                size--;
                            }

                            // Store (and possibly overwrite) the index for this
                            // keyword in the hash, mark the array at that index
                            // as true, and increment the keyword size.
                            rb_hash_aset(stored_indices, keyword, ULONG2NUM(element_index));
                            rb_ary_store(keyword_indices, (long) element_index, Qtrue);
                            size++;
                        }

                        *kw_arg = rb_xmalloc_mul_add(size, sizeof(VALUE), sizeof(struct rb_callinfo_kwarg));
                        *flags |= VM_CALL_KWARG;

                        VALUE *keywords = (*kw_arg)->keywords;
                        (*kw_arg)->references = 0;
                        (*kw_arg)->keyword_len = (int) size;

                        size_t keyword_index = 0;
                        for (size_t element_index = 0; element_index < elements->size; element_index++) {
                            const pm_assoc_node_t *assoc = (const pm_assoc_node_t *) elements->nodes[element_index];
                            bool popped = true;

                            if (rb_ary_entry(keyword_indices, (long) element_index) == Qtrue) {
                                keywords[keyword_index++] = pm_static_literal_value(iseq, assoc->key, scope_node);
                                popped = false;
                            }

                            PM_COMPILE(assoc->value);
                        }

                        RUBY_ASSERT(keyword_index == size);
                    }
                    else {
                        // If they aren't all symbol keys then we need to
                        // construct a new hash and pass that as an argument.
                        orig_argc++;
                        *flags |= VM_CALL_KW_SPLAT;

                        size_t size = elements->size;
                        if (size > 1) {
                            // A new hash will be created for the keyword
                            // arguments in this case, so mark the method as
                            // passing mutable keyword splat.
                            *flags |= VM_CALL_KW_SPLAT_MUT;
                        }

                        for (size_t element_index = 0; element_index < size; element_index++) {
                            pm_assoc_node_t *assoc = (pm_assoc_node_t *) elements->nodes[element_index];
                            PM_COMPILE_NOT_POPPED(assoc->key);
                            PM_COMPILE_NOT_POPPED(assoc->value);
                        }

                        ADD_INSN1(ret, &dummy_line_node, newhash, INT2FIX(size * 2));
                    }
                }
                break;
              }
              case PM_SPLAT_NODE: {
                *flags |= VM_CALL_ARGS_SPLAT;
                pm_splat_node_t *splat_node = (pm_splat_node_t *)argument;

                if (splat_node->expression) {
                    PM_COMPILE_NOT_POPPED(splat_node->expression);
                }
                else {
                    pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, PM_CONSTANT_MULT, 0);
                    ADD_GETLOCAL(ret, &dummy_line_node, index.index, index.level);
                }

                bool first_splat = !has_splat;

                if (first_splat) {
                    // If this is the first splat array seen and it's not the
                    // last parameter, we want splatarray to dup it.
                    //
                    // foo(a, *b, c)
                    //        ^^
                    if (index + 1 < arguments_node_list.size || has_regular_blockarg) {
                        ADD_INSN1(ret, &dummy_line_node, splatarray, Qtrue);
                        *flags |= VM_CALL_ARGS_SPLAT_MUT;
                    }
                    // If this is the first spalt array seen and it's the last
                    // parameter, we don't want splatarray to dup it.
                    //
                    // foo(a, *b)
                    //        ^^
                    else {
                        ADD_INSN1(ret, &dummy_line_node, splatarray, Qfalse);
                    }
                }
                else {
                    // If this is not the first splat array seen and it is also
                    // the last parameter, we don't want splatarray to dup it
                    // and we need to concat the array.
                    //
                    // foo(a, *b, *c)
                    //            ^^
                    ADD_INSN1(ret, &dummy_line_node, splatarray, Qfalse);
                    ADD_INSN(ret, &dummy_line_node, concatarray);
                }

                has_splat = true;
                post_splat_counter = 0;

                break;
              }
              case PM_FORWARDING_ARGUMENTS_NODE: {
                orig_argc += 2;
                *flags |= VM_CALL_ARGS_SPLAT | VM_CALL_ARGS_SPLAT_MUT | VM_CALL_ARGS_BLOCKARG | VM_CALL_KW_SPLAT;

                // Forwarding arguments nodes are treated as foo(*, **, &)
                // So foo(...) equals foo(*, **, &) and as such the local
                // table for this method is known in advance
                //
                // Push the *
                pm_local_index_t mult_local = pm_lookup_local_index(iseq, scope_node, PM_CONSTANT_MULT, 0);
                ADD_GETLOCAL(ret, &dummy_line_node, mult_local.index, mult_local.level);
                ADD_INSN1(ret, &dummy_line_node, splatarray, Qtrue);

                // Push the **
                pm_local_index_t pow_local = pm_lookup_local_index(iseq, scope_node, PM_CONSTANT_POW, 0);
                ADD_GETLOCAL(ret, &dummy_line_node, pow_local.index, pow_local.level);

                // Push the &
                pm_local_index_t and_local = pm_lookup_local_index(iseq, scope_node, PM_CONSTANT_AND, 0);
                ADD_INSN2(ret, &dummy_line_node, getblockparamproxy, INT2FIX(and_local.index + VM_ENV_DATA_SIZE - 1), INT2FIX(and_local.level));
                ADD_INSN(ret, &dummy_line_node, splatkw);

                break;
              }
              default: {
                post_splat_counter++;
                PM_COMPILE_NOT_POPPED(argument);

                // If we have a splat and we've seen a splat, we need to process
                // everything after the splat.
                if (has_splat) {
                    // Stack items are turned into an array and concatenated in
                    // the following cases:
                    //
                    // If the next node is a splat:
                    //
                    //   foo(*a, b, *c)
                    //
                    // If the next node is a kwarg or kwarg splat:
                    //
                    //   foo(*a, b, c: :d)
                    //   foo(*a, b, **c)
                    //
                    // If the next node is NULL (we have hit the end):
                    //
                    //   foo(*a, b)
                    if (index == arguments_node_list.size - 1) {
                        RUBY_ASSERT(post_splat_counter > 0);
                        ADD_INSN1(ret, &dummy_line_node, pushtoarray, INT2FIX(post_splat_counter));
                    }
                    else {
                        pm_node_t *next_arg = arguments_node_list.nodes[index + 1];

                        switch (PM_NODE_TYPE(next_arg)) {
                          // A keyword hash node contains all keyword arguments as AssocNodes and AssocSplatNodes
                          case PM_KEYWORD_HASH_NODE: {
                            ADD_INSN1(ret, &dummy_line_node, newarray, INT2FIX(post_splat_counter));
                            ADD_INSN(ret, &dummy_line_node, concatarray);
                            break;
                          }
                          case PM_SPLAT_NODE: {
                            ADD_INSN1(ret, &dummy_line_node, newarray, INT2FIX(post_splat_counter));
                            ADD_INSN(ret, &dummy_line_node, concatarray);
                            break;
                          }
                          default:
                            break;
                        }
                    }
                }
                else {
                    orig_argc++;
                }
              }
            }
        }
    }

    if (has_splat) {
        orig_argc++;
    }

    if (has_keyword_splat) {
        orig_argc++;
    }

    return orig_argc;
}

// Compile the argument parts of a call
static int
pm_setup_args(const pm_arguments_node_t *arguments_node, const pm_node_t *block, int *flags, struct rb_callinfo_kwarg **kw_arg, rb_iseq_t *iseq, LINK_ANCHOR *const ret, pm_scope_node_t *scope_node, NODE dummy_line_node)
{
    if (block && PM_NODE_TYPE_P(block, PM_BLOCK_ARGUMENT_NODE)) {
        // We compile the `&block_arg` expression first and stitch it later
        // since the nature of the expression influences whether splat should
        // duplicate the array.
        bool regular_block_arg = true;
        DECL_ANCHOR(block_arg);
        INIT_ANCHOR(block_arg);
        pm_compile_node(iseq, block, block_arg, false, scope_node);

        *flags |= VM_CALL_ARGS_BLOCKARG;

        if (LIST_INSN_SIZE_ONE(block_arg)) {
            LINK_ELEMENT *elem = FIRST_ELEMENT(block_arg);
            if (IS_INSN(elem)) {
                INSN *iobj = (INSN *)elem;
                if (iobj->insn_id == BIN(getblockparam)) {
                    iobj->insn_id = BIN(getblockparamproxy);
                }
                // Allow splat without duplication for simple one-instruction
                // block arguments like `&arg`. It is known that this optimization
                // can be too aggressive in some cases. See [Bug #16504].
                regular_block_arg = false;
            }
        }

        int argc = pm_setup_args_core(arguments_node, block, flags, regular_block_arg, kw_arg, iseq, ret, scope_node, dummy_line_node);
        ADD_SEQ(ret, block_arg);
        return argc;
    }
    return pm_setup_args_core(arguments_node, block, flags, false, kw_arg, iseq, ret, scope_node, dummy_line_node);
}

/**
 * Compile an index operator write node, which is a node that is writing a value
 * using the [] and []= methods. It looks like:
 *
 *     foo[bar] += baz
 *
 * This breaks down to caching the receiver and arguments on the stack, calling
 * the [] method, calling the operator method with the result of the [] method,
 * and then calling the []= method with the result of the operator method.
 */
static void
pm_compile_index_operator_write_node(pm_scope_node_t *scope_node, const pm_index_operator_write_node_t *node, rb_iseq_t *iseq, LINK_ANCHOR *const ret, bool popped)
{
    int lineno = pm_node_line_number(scope_node->parser, (const pm_node_t *) node);
    const NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    if (!popped) {
        PM_PUTNIL;
    }

    PM_COMPILE_NOT_POPPED(node->receiver);

    int boff = (node->block == NULL ? 0 : 1);
    int flag = PM_NODE_TYPE_P(node->receiver, PM_SELF_NODE) ? VM_CALL_FCALL : 0;
    struct rb_callinfo_kwarg *keywords = NULL;
    int argc = pm_setup_args(node->arguments, node->block, &flag, &keywords, iseq, ret, scope_node, dummy_line_node);

    if ((argc > 0 || boff) && (flag & VM_CALL_KW_SPLAT)) {
        if (boff) {
            ADD_INSN(ret, &dummy_line_node, splatkw);
        }
        else {
            ADD_INSN(ret, &dummy_line_node, dup);
            ADD_INSN(ret, &dummy_line_node, splatkw);
            ADD_INSN(ret, &dummy_line_node, pop);
        }
    }

    int dup_argn = argc + 1 + boff;
    int keyword_len = 0;

    if (keywords) {
        keyword_len = keywords->keyword_len;
        dup_argn += keyword_len;
    }

    ADD_INSN1(ret, &dummy_line_node, dupn, INT2FIX(dup_argn));
    ADD_SEND_R(ret, &dummy_line_node, idAREF, INT2FIX(argc), NULL, INT2FIX(flag & ~(VM_CALL_ARGS_SPLAT_MUT | VM_CALL_KW_SPLAT_MUT)), keywords);

    PM_COMPILE_NOT_POPPED(node->value);

    ID id_operator = pm_constant_id_lookup(scope_node, node->operator);
    ADD_SEND(ret, &dummy_line_node, id_operator, INT2FIX(1));

    if (!popped) {
        ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(dup_argn + 1));
    }
    if (flag & VM_CALL_ARGS_SPLAT) {
        if (flag & VM_CALL_KW_SPLAT) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(2 + boff));

            if (!(flag & VM_CALL_ARGS_SPLAT_MUT)) {
                ADD_INSN1(ret, &dummy_line_node, splatarray, Qtrue);
                flag |= VM_CALL_ARGS_SPLAT_MUT;
            }

            ADD_INSN(ret, &dummy_line_node, swap);
            ADD_INSN1(ret, &dummy_line_node, pushtoarray, INT2FIX(1));
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(2 + boff));
            ADD_INSN(ret, &dummy_line_node, pop);
        }
        else {
            if (boff > 0) {
                ADD_INSN1(ret, &dummy_line_node, dupn, INT2FIX(3));
                ADD_INSN(ret, &dummy_line_node, swap);
                ADD_INSN(ret, &dummy_line_node, pop);
            }
            if (!(flag & VM_CALL_ARGS_SPLAT_MUT)) {
                ADD_INSN(ret, &dummy_line_node, swap);
                ADD_INSN1(ret, &dummy_line_node, splatarray, Qtrue);
                ADD_INSN(ret, &dummy_line_node, swap);
                flag |= VM_CALL_ARGS_SPLAT_MUT;
            }
            ADD_INSN1(ret, &dummy_line_node, pushtoarray, INT2FIX(1));
            if (boff > 0) {
                ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(3));
                PM_POP;
                PM_POP;
            }
        }
        ADD_SEND_R(ret, &dummy_line_node, idASET, INT2FIX(argc), NULL, INT2FIX(flag), keywords);
    }
    else if (flag & VM_CALL_KW_SPLAT) {
        if (boff > 0) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(2));
            ADD_INSN(ret, &dummy_line_node, swap);
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(3));
            PM_POP;
        }
        ADD_INSN(ret, &dummy_line_node, swap);
        ADD_SEND_R(ret, &dummy_line_node, idASET, INT2FIX(argc + 1), NULL, INT2FIX(flag), keywords);
    }
    else if (keyword_len) {
        ADD_INSN(ret, &dummy_line_node, dup);
        ADD_INSN1(ret, &dummy_line_node, opt_reverse, INT2FIX(keyword_len + boff + 2));
        ADD_INSN1(ret, &dummy_line_node, opt_reverse, INT2FIX(keyword_len + boff + 1));
        ADD_INSN(ret, &dummy_line_node, pop);
        ADD_SEND_R(ret, &dummy_line_node, idASET, INT2FIX(argc + 1), NULL, INT2FIX(flag), keywords);
    }
    else {
        if (boff > 0) {
            PM_SWAP;
        }
        ADD_SEND_R(ret, &dummy_line_node, idASET, INT2FIX(argc + 1), NULL, INT2FIX(flag), keywords);
    }
    PM_POP;
}

/**
 * Compile an index control flow write node, which is a node that is writing a
 * value using the [] and []= methods and the &&= and ||= operators. It looks
 * like:
 *
 *     foo[bar] ||= baz
 *
 * This breaks down to caching the receiver and arguments on the stack, calling
 * the [] method, checking the result and then changing control flow based on
 * it. If the value would result in a write, then the value is written using the
 * []= method.
 */
static void
pm_compile_index_control_flow_write_node(pm_scope_node_t *scope_node, const pm_node_t *node, const pm_node_t *receiver, const pm_arguments_node_t *arguments, const pm_node_t *block, const pm_node_t *value, rb_iseq_t *iseq, LINK_ANCHOR *const ret, bool popped)
{
    int lineno = pm_node_line_number(scope_node->parser, node);
    const NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    if (!popped) {
        PM_PUTNIL;
    }

    PM_COMPILE_NOT_POPPED(receiver);

    int boff = (block == NULL ? 0 : 1);
    int flag = PM_NODE_TYPE_P(receiver, PM_SELF_NODE) ? VM_CALL_FCALL : 0;
    struct rb_callinfo_kwarg *keywords = NULL;
    int argc = pm_setup_args(arguments, block, &flag, &keywords, iseq, ret, scope_node, dummy_line_node);

    if ((argc > 0 || boff) && (flag & VM_CALL_KW_SPLAT)) {
        if (boff) {
            ADD_INSN(ret, &dummy_line_node, splatkw);
        }
        else {
            ADD_INSN(ret, &dummy_line_node, dup);
            ADD_INSN(ret, &dummy_line_node, splatkw);
            ADD_INSN(ret, &dummy_line_node, pop);
        }
    }

    int dup_argn = argc + 1 + boff;
    int keyword_len = 0;

    if (keywords) {
        keyword_len = keywords->keyword_len;
        dup_argn += keyword_len;
    }

    ADD_INSN1(ret, &dummy_line_node, dupn, INT2FIX(dup_argn));
    ADD_SEND_R(ret, &dummy_line_node, idAREF, INT2FIX(argc), NULL, INT2FIX(flag & ~(VM_CALL_ARGS_SPLAT_MUT | VM_CALL_KW_SPLAT_MUT)), keywords);

    LABEL *label = NEW_LABEL(lineno);
    LABEL *lfin = NEW_LABEL(lineno);

    ADD_INSN(ret, &dummy_line_node, dup);
    if (PM_NODE_TYPE_P(node, PM_INDEX_AND_WRITE_NODE)) {
        ADD_INSNL(ret, &dummy_line_node, branchunless, label);
    }
    else {
        ADD_INSNL(ret, &dummy_line_node, branchif, label);
    }

    PM_POP;
    PM_COMPILE_NOT_POPPED(value);

    if (!popped) {
        ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(dup_argn + 1));
    }

    if (flag & VM_CALL_ARGS_SPLAT) {
        if (flag & VM_CALL_KW_SPLAT) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(2 + boff));
            if (!(flag & VM_CALL_ARGS_SPLAT_MUT)) {
                ADD_INSN1(ret, &dummy_line_node, splatarray, Qtrue);
                flag |= VM_CALL_ARGS_SPLAT_MUT;
            }

            ADD_INSN(ret, &dummy_line_node, swap);
            ADD_INSN1(ret, &dummy_line_node, pushtoarray, INT2FIX(1));
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(2 + boff));
            ADD_INSN(ret, &dummy_line_node, pop);
        }
        else {
            if (boff > 0) {
                ADD_INSN1(ret, &dummy_line_node, dupn, INT2FIX(3));
                ADD_INSN(ret, &dummy_line_node, swap);
                ADD_INSN(ret, &dummy_line_node, pop);
            }
            if (!(flag & VM_CALL_ARGS_SPLAT_MUT)) {
                ADD_INSN(ret, &dummy_line_node, swap);
                ADD_INSN1(ret, &dummy_line_node, splatarray, Qtrue);
                ADD_INSN(ret, &dummy_line_node, swap);
                flag |= VM_CALL_ARGS_SPLAT_MUT;
            }
            ADD_INSN1(ret, &dummy_line_node, pushtoarray, INT2FIX(1));
            if (boff > 0) {
                ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(3));
                PM_POP;
                PM_POP;
            }
        }
        ADD_SEND_R(ret, &dummy_line_node, idASET, INT2FIX(argc), NULL, INT2FIX(flag), keywords);
    }
    else if (flag & VM_CALL_KW_SPLAT) {
        if (boff > 0) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(2));
            ADD_INSN(ret, &dummy_line_node, swap);
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(3));
            PM_POP;
        }

        ADD_INSN(ret, &dummy_line_node, swap);
        ADD_SEND_R(ret, &dummy_line_node, idASET, INT2FIX(argc + 1), NULL, INT2FIX(flag), keywords);
    }
    else if (keyword_len) {
        ADD_INSN1(ret, &dummy_line_node, opt_reverse, INT2FIX(keyword_len + boff + 1));
        ADD_INSN1(ret, &dummy_line_node, opt_reverse, INT2FIX(keyword_len + boff + 0));
        ADD_SEND_R(ret, &dummy_line_node, idASET, INT2FIX(argc + 1), NULL, INT2FIX(flag), keywords);
    }
    else {
        if (boff > 0) {
            PM_SWAP;
        }
        ADD_SEND_R(ret, &dummy_line_node, idASET, INT2FIX(argc + 1), NULL, INT2FIX(flag), keywords);
    }
    PM_POP;
    ADD_INSNL(ret, &dummy_line_node, jump, lfin);
    ADD_LABEL(ret, label);
    if (!popped) {
        ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(dup_argn + 1));
    }
    ADD_INSN1(ret, &dummy_line_node, adjuststack, INT2FIX(dup_argn + 1));
    ADD_LABEL(ret, lfin);
}

// When we compile a pattern matching expression, we use the stack as a scratch
// space to store lots of different values (consider it like we have a pattern
// matching function and we need space for a bunch of different local
// variables). The "base index" refers to the index on the stack where we
// started compiling the pattern matching expression. These offsets from that
// base index indicate the location of the various locals we need.
#define PM_PATTERN_BASE_INDEX_OFFSET_DECONSTRUCTED_CACHE 0
#define PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING 1
#define PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P 2
#define PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_MATCHEE 3
#define PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_KEY 4

// A forward declaration because this is the recursive function that handles
// compiling a pattern. It can be reentered by nesting patterns, as in the case
// of arrays or hashes.
static int pm_compile_pattern(rb_iseq_t *iseq, pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, LABEL *matched_label, LABEL *unmatched_label, bool in_single_pattern, bool in_alternation_pattern, bool use_deconstructed_cache, unsigned int base_index);

/**
 * This function generates the code to set up the error string and error_p
 * locals depending on whether or not the pattern matched.
 */
static int
pm_compile_pattern_generic_error(rb_iseq_t *iseq, pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, VALUE message, unsigned int base_index)
{
    pm_line_node_t line;
    pm_line_node(&line, scope_node, node);

    LABEL *match_succeeded_label = NEW_LABEL(line.lineno);

    ADD_INSN(ret, &line.node, dup);
    ADD_INSNL(ret, &line.node, branchif, match_succeeded_label);

    ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
    ADD_INSN1(ret, &line.node, putobject, message);
    ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
    ADD_SEND(ret, &line.node, id_core_sprintf, INT2FIX(2));
    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING + 1));

    ADD_INSN1(ret, &line.node, putobject, Qfalse);
    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P + 2));

    ADD_INSN(ret, &line.node, pop);
    ADD_INSN(ret, &line.node, pop);
    ADD_LABEL(ret, match_succeeded_label);

    return COMPILE_OK;
}

/**
 * This function generates the code to set up the error string and error_p
 * locals depending on whether or not the pattern matched when the value needs
 * to match a specific deconstructed length.
 */
static int
pm_compile_pattern_length_error(rb_iseq_t *iseq, pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, VALUE message, VALUE length, unsigned int base_index)
{
    pm_line_node_t line;
    pm_line_node(&line, scope_node, node);

    LABEL *match_succeeded_label = NEW_LABEL(line.lineno);

    ADD_INSN(ret, &line.node, dup);
    ADD_INSNL(ret, &line.node, branchif, match_succeeded_label);

    ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
    ADD_INSN1(ret, &line.node, putobject, message);
    ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
    ADD_INSN(ret, &line.node, dup);
    ADD_SEND(ret, &line.node, idLength, INT2FIX(0));
    ADD_INSN1(ret, &line.node, putobject, length);
    ADD_SEND(ret, &line.node, id_core_sprintf, INT2FIX(4));
    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING + 1));

    ADD_INSN1(ret, &line.node, putobject, Qfalse);
    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P + 2));

    ADD_INSN(ret, &line.node, pop);
    ADD_INSN(ret, &line.node, pop);
    ADD_LABEL(ret, match_succeeded_label);

    return COMPILE_OK;
}

/**
 * This function generates the code to set up the error string and error_p
 * locals depending on whether or not the pattern matched when the value needs
 * to pass a specific #=== method call.
 */
static int
pm_compile_pattern_eqq_error(rb_iseq_t *iseq, pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, unsigned int base_index)
{
    pm_line_node_t line;
    pm_line_node(&line, scope_node, node);

    LABEL *match_succeeded_label = NEW_LABEL(line.lineno);

    ADD_INSN(ret, &line.node, dup);
    ADD_INSNL(ret, &line.node, branchif, match_succeeded_label);

    ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
    ADD_INSN1(ret, &line.node, putobject, rb_fstring_lit("%p === %p does not return true"));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(5));
    ADD_SEND(ret, &line.node, id_core_sprintf, INT2FIX(3));
    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING + 1));
    ADD_INSN1(ret, &line.node, putobject, Qfalse);
    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P + 2));
    ADD_INSN(ret, &line.node, pop);
    ADD_INSN(ret, &line.node, pop);

    ADD_LABEL(ret, match_succeeded_label);
    ADD_INSN1(ret, &line.node, setn, INT2FIX(2));
    ADD_INSN(ret, &line.node, pop);
    ADD_INSN(ret, &line.node, pop);

    return COMPILE_OK;
}

/**
 * This is a variation on compiling a pattern matching expression that is used
 * to have the pattern matching instructions fall through to immediately after
 * the pattern if it passes. Otherwise it jumps to the given unmatched_label
 * label.
 */
static int
pm_compile_pattern_match(rb_iseq_t *iseq, pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, LABEL *unmatched_label, bool in_single_pattern, bool in_alternation_pattern, bool use_deconstructed_cache, unsigned int base_index)
{
    LABEL *matched_label = NEW_LABEL(nd_line(node));
    CHECK(pm_compile_pattern(iseq, scope_node, node, ret, matched_label, unmatched_label, in_single_pattern, in_alternation_pattern, use_deconstructed_cache, base_index));
    ADD_LABEL(ret, matched_label);
    return COMPILE_OK;
}

/**
 * This function compiles in the code necessary to call #deconstruct on the
 * value to match against. It raises appropriate errors if the method does not
 * exist or if it returns the wrong type.
 */
static int
pm_compile_pattern_deconstruct(rb_iseq_t *iseq, pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, LABEL *deconstruct_label, LABEL *match_failed_label, LABEL *deconstructed_label, LABEL *type_error_label, bool in_single_pattern, bool use_deconstructed_cache, unsigned int base_index)
{
    pm_line_node_t line;
    pm_line_node(&line, scope_node, node);

    if (use_deconstructed_cache) {
        ADD_INSN1(ret, &line.node, topn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_DECONSTRUCTED_CACHE));
        ADD_INSNL(ret, &line.node, branchnil, deconstruct_label);

        ADD_INSN1(ret, &line.node, topn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_DECONSTRUCTED_CACHE));
        ADD_INSNL(ret, &line.node, branchunless, match_failed_label);

        ADD_INSN(ret, &line.node, pop);
        ADD_INSN1(ret, &line.node, topn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_DECONSTRUCTED_CACHE - 1));
        ADD_INSNL(ret, &line.node, jump, deconstructed_label);
    }
    else {
        ADD_INSNL(ret, &line.node, jump, deconstruct_label);
    }

    ADD_LABEL(ret, deconstruct_label);
    ADD_INSN(ret, &line.node, dup);
    ADD_INSN1(ret, &line.node, putobject, ID2SYM(rb_intern("deconstruct")));
    ADD_SEND(ret, &line.node, idRespond_to, INT2FIX(1));

    if (use_deconstructed_cache) {
        ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_DECONSTRUCTED_CACHE + 1));
    }

    if (in_single_pattern) {
        CHECK(pm_compile_pattern_generic_error(iseq, scope_node, node, ret, rb_fstring_lit("%p does not respond to #deconstruct"), base_index + 1));
    }

    ADD_INSNL(ret, &line.node, branchunless, match_failed_label);
    ADD_SEND(ret, &line.node, rb_intern("deconstruct"), INT2FIX(0));

    if (use_deconstructed_cache) {
        ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_DECONSTRUCTED_CACHE));
    }

    ADD_INSN(ret, &line.node, dup);
    ADD_INSN1(ret, &line.node, checktype, INT2FIX(T_ARRAY));
    ADD_INSNL(ret, &line.node, branchunless, type_error_label);
    ADD_LABEL(ret, deconstructed_label);

    return COMPILE_OK;
}

/**
 * This function compiles in the code necessary to match against the optional
 * constant path that is attached to an array, find, or hash pattern.
 */
static int
pm_compile_pattern_constant(rb_iseq_t *iseq, pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, LABEL *match_failed_label, bool in_single_pattern, unsigned int base_index)
{
    pm_line_node_t line;
    pm_line_node(&line, scope_node, node);

    ADD_INSN(ret, &line.node, dup);
    PM_COMPILE_NOT_POPPED(node);

    if (in_single_pattern) {
        ADD_INSN1(ret, &line.node, dupn, INT2FIX(2));
    }
    ADD_INSN1(ret, &line.node, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_CASE));
    if (in_single_pattern) {
        CHECK(pm_compile_pattern_eqq_error(iseq, scope_node, node, ret, base_index + 3));
    }
    ADD_INSNL(ret, &line.node, branchunless, match_failed_label);
    return COMPILE_OK;
}

/**
 * When matching fails, an appropriate error must be raised. This function is
 * responsible for compiling in those error raising instructions.
 */
static void
pm_compile_pattern_error_handler(rb_iseq_t *iseq, const pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, LABEL *done_label, bool popped)
{
    pm_line_node_t line;
    pm_line_node(&line, scope_node, node);

    LABEL *key_error_label = NEW_LABEL(line.lineno);
    LABEL *cleanup_label = NEW_LABEL(line.lineno);

    struct rb_callinfo_kwarg *kw_arg = rb_xmalloc_mul_add(2, sizeof(VALUE), sizeof(struct rb_callinfo_kwarg));
    kw_arg->references = 0;
    kw_arg->keyword_len = 2;
    kw_arg->keywords[0] = ID2SYM(rb_intern("matchee"));
    kw_arg->keywords[1] = ID2SYM(rb_intern("key"));

    ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P + 2));
    ADD_INSNL(ret, &line.node, branchif, key_error_label);

    ADD_INSN1(ret, &line.node, putobject, rb_eNoMatchingPatternError);
    ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
    ADD_INSN1(ret, &line.node, putobject, rb_fstring_lit("%p: %s"));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(4));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING + 6));
    ADD_SEND(ret, &line.node, id_core_sprintf, INT2FIX(3));
    ADD_SEND(ret, &line.node, id_core_raise, INT2FIX(2));
    ADD_INSNL(ret, &line.node, jump, cleanup_label);

    ADD_LABEL(ret, key_error_label);
    ADD_INSN1(ret, &line.node, putobject, rb_eNoMatchingPatternKeyError);
    ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
    ADD_INSN1(ret, &line.node, putobject, rb_fstring_lit("%p: %s"));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(4));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING + 6));
    ADD_SEND(ret, &line.node, id_core_sprintf, INT2FIX(3));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_MATCHEE + 4));
    ADD_INSN1(ret, &line.node, topn, INT2FIX(PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_KEY + 5));
    ADD_SEND_R(ret, &line.node, rb_intern("new"), INT2FIX(1), NULL, INT2FIX(VM_CALL_KWARG), kw_arg);
    ADD_SEND(ret, &line.node, id_core_raise, INT2FIX(1));
    ADD_LABEL(ret, cleanup_label);

    ADD_INSN1(ret, &line.node, adjuststack, INT2FIX(7));
    if (!popped) ADD_INSN(ret, &line.node, putnil);
    ADD_INSNL(ret, &line.node, jump, done_label);
    ADD_INSN1(ret, &line.node, dupn, INT2FIX(5));
    if (popped) ADD_INSN(ret, &line.node, putnil);
}

/**
 * Compile a pattern matching expression.
 */
static int
pm_compile_pattern(rb_iseq_t *iseq, pm_scope_node_t *scope_node, const pm_node_t *node, LINK_ANCHOR *const ret, LABEL *matched_label, LABEL *unmatched_label, bool in_single_pattern, bool in_alternation_pattern, bool use_deconstructed_cache, unsigned int base_index)
{
    pm_line_node_t line;
    pm_line_node(&line, scope_node, node);

    switch (PM_NODE_TYPE(node)) {
      case PM_ARRAY_PATTERN_NODE: {
        // Array patterns in pattern matching are triggered by using commas in
        // a pattern or wrapping it in braces. They are represented by a
        // ArrayPatternNode. This looks like:
        //
        //     foo => [1, 2, 3]
        //
        // It can optionally have a splat in the middle of it, which can
        // optionally have a name attached.
        const pm_array_pattern_node_t *cast = (const pm_array_pattern_node_t *) node;

        const size_t requireds_size = cast->requireds.size;
        const size_t posts_size = cast->posts.size;
        const size_t minimum_size = requireds_size + posts_size;

        bool rest_named = false;
        bool use_rest_size = false;

        if (cast->rest != NULL) {
            rest_named = (PM_NODE_TYPE_P(cast->rest, PM_SPLAT_NODE) && ((const pm_splat_node_t *) cast->rest)->expression != NULL);
            use_rest_size = (rest_named || (!rest_named && posts_size > 0));
        }

        LABEL *match_failed_label = NEW_LABEL(line.lineno);
        LABEL *type_error_label = NEW_LABEL(line.lineno);
        LABEL *deconstruct_label = NEW_LABEL(line.lineno);
        LABEL *deconstructed_label = NEW_LABEL(line.lineno);

        if (use_rest_size) {
            ADD_INSN1(ret, &line.node, putobject, INT2FIX(0));
            ADD_INSN(ret, &line.node, swap);
            base_index++;
        }

        if (cast->constant != NULL) {
            CHECK(pm_compile_pattern_constant(iseq, scope_node, cast->constant, ret, match_failed_label, in_single_pattern, base_index));
        }

        CHECK(pm_compile_pattern_deconstruct(iseq, scope_node, node, ret, deconstruct_label, match_failed_label, deconstructed_label, type_error_label, in_single_pattern, use_deconstructed_cache, base_index));

        ADD_INSN(ret, &line.node, dup);
        ADD_SEND(ret, &line.node, idLength, INT2FIX(0));
        ADD_INSN1(ret, &line.node, putobject, INT2FIX(minimum_size));
        ADD_SEND(ret, &line.node, cast->rest == NULL ? idEq : idGE, INT2FIX(1));
        if (in_single_pattern) {
            VALUE message = cast->rest == NULL ? rb_fstring_lit("%p length mismatch (given %p, expected %p)") : rb_fstring_lit("%p length mismatch (given %p, expected %p+)");
            CHECK(pm_compile_pattern_length_error(iseq, scope_node, node, ret, message, INT2FIX(minimum_size), base_index + 1));
        }
        ADD_INSNL(ret, &line.node, branchunless, match_failed_label);

        for (size_t index = 0; index < requireds_size; index++) {
            const pm_node_t *required = cast->requireds.nodes[index];
            ADD_INSN(ret, &line.node, dup);
            ADD_INSN1(ret, &line.node, putobject, INT2FIX(index));
            ADD_SEND(ret, &line.node, idAREF, INT2FIX(1));
            CHECK(pm_compile_pattern_match(iseq, scope_node, required, ret, match_failed_label, in_single_pattern, in_alternation_pattern, false, base_index + 1));
        }

        if (cast->rest != NULL) {
            if (rest_named) {
                ADD_INSN(ret, &line.node, dup);
                ADD_INSN1(ret, &line.node, putobject, INT2FIX(requireds_size));
                ADD_INSN1(ret, &line.node, topn, INT2FIX(1));
                ADD_SEND(ret, &line.node, idLength, INT2FIX(0));
                ADD_INSN1(ret, &line.node, putobject, INT2FIX(minimum_size));
                ADD_SEND(ret, &line.node, idMINUS, INT2FIX(1));
                ADD_INSN1(ret, &line.node, setn, INT2FIX(4));
                ADD_SEND(ret, &line.node, idAREF, INT2FIX(2));
                CHECK(pm_compile_pattern_match(iseq, scope_node, ((const pm_splat_node_t *) cast->rest)->expression, ret, match_failed_label, in_single_pattern, in_alternation_pattern, false, base_index + 1));
            }
            else if (posts_size > 0) {
                ADD_INSN(ret, &line.node, dup);
                ADD_SEND(ret, &line.node, idLength, INT2FIX(0));
                ADD_INSN1(ret, &line.node, putobject, INT2FIX(minimum_size));
                ADD_SEND(ret, &line.node, idMINUS, INT2FIX(1));
                ADD_INSN1(ret, &line.node, setn, INT2FIX(2));
                ADD_INSN(ret, &line.node, pop);
            }
        }

        for (size_t index = 0; index < posts_size; index++) {
            const pm_node_t *post = cast->posts.nodes[index];
            ADD_INSN(ret, &line.node, dup);

            ADD_INSN1(ret, &line.node, putobject, INT2FIX(requireds_size + index));
            ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
            ADD_SEND(ret, &line.node, idPLUS, INT2FIX(1));
            ADD_SEND(ret, &line.node, idAREF, INT2FIX(1));
            CHECK(pm_compile_pattern_match(iseq, scope_node, post, ret, match_failed_label, in_single_pattern, in_alternation_pattern, false, base_index + 1));
        }

        ADD_INSN(ret, &line.node, pop);
        if (use_rest_size) {
            ADD_INSN(ret, &line.node, pop);
        }

        ADD_INSNL(ret, &line.node, jump, matched_label);
        ADD_INSN(ret, &line.node, putnil);
        if (use_rest_size) {
            ADD_INSN(ret, &line.node, putnil);
        }

        ADD_LABEL(ret, type_error_label);
        ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
        ADD_INSN1(ret, &line.node, putobject, rb_eTypeError);
        ADD_INSN1(ret, &line.node, putobject, rb_fstring_lit("deconstruct must return Array"));
        ADD_SEND(ret, &line.node, id_core_raise, INT2FIX(2));
        ADD_INSN(ret, &line.node, pop);

        ADD_LABEL(ret, match_failed_label);
        ADD_INSN(ret, &line.node, pop);
        if (use_rest_size) {
            ADD_INSN(ret, &line.node, pop);
        }

        ADD_INSNL(ret, &line.node, jump, unmatched_label);
        break;
      }
      case PM_FIND_PATTERN_NODE: {
        // Find patterns in pattern matching are triggered by using commas in
        // a pattern or wrapping it in braces and using a splat on both the left
        // and right side of the pattern. This looks like:
        //
        //     foo => [*, 1, 2, 3, *]
        //
        // There can be any number of requireds in the middle. The splats on
        // both sides can optionally have names attached.
        const pm_find_pattern_node_t *cast = (const pm_find_pattern_node_t *) node;
        const size_t size = cast->requireds.size;

        LABEL *match_failed_label = NEW_LABEL(line.lineno);
        LABEL *type_error_label = NEW_LABEL(line.lineno);
        LABEL *deconstruct_label = NEW_LABEL(line.lineno);
        LABEL *deconstructed_label = NEW_LABEL(line.lineno);

        if (cast->constant) {
            CHECK(pm_compile_pattern_constant(iseq, scope_node, cast->constant, ret, match_failed_label, in_single_pattern, base_index));
        }

        CHECK(pm_compile_pattern_deconstruct(iseq, scope_node, node, ret, deconstruct_label, match_failed_label, deconstructed_label, type_error_label, in_single_pattern, use_deconstructed_cache, base_index));

        ADD_INSN(ret, &line.node, dup);
        ADD_SEND(ret, &line.node, idLength, INT2FIX(0));
        ADD_INSN1(ret, &line.node, putobject, INT2FIX(size));
        ADD_SEND(ret, &line.node, idGE, INT2FIX(1));
        if (in_single_pattern) {
            CHECK(pm_compile_pattern_length_error(iseq, scope_node, node, ret, rb_fstring_lit("%p length mismatch (given %p, expected %p+)"), INT2FIX(size), base_index + 1));
        }
        ADD_INSNL(ret, &line.node, branchunless, match_failed_label);

        {
            LABEL *while_begin_label = NEW_LABEL(line.lineno);
            LABEL *next_loop_label = NEW_LABEL(line.lineno);
            LABEL *find_succeeded_label = NEW_LABEL(line.lineno);
            LABEL *find_failed_label = NEW_LABEL(line.lineno);

            ADD_INSN(ret, &line.node, dup);
            ADD_SEND(ret, &line.node, idLength, INT2FIX(0));

            ADD_INSN(ret, &line.node, dup);
            ADD_INSN1(ret, &line.node, putobject, INT2FIX(size));
            ADD_SEND(ret, &line.node, idMINUS, INT2FIX(1));
            ADD_INSN1(ret, &line.node, putobject, INT2FIX(0));
            ADD_LABEL(ret, while_begin_label);

            ADD_INSN(ret, &line.node, dup);
            ADD_INSN1(ret, &line.node, topn, INT2FIX(2));
            ADD_SEND(ret, &line.node, idLE, INT2FIX(1));
            ADD_INSNL(ret, &line.node, branchunless, find_failed_label);

            for (size_t index = 0; index < size; index++) {
                ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
                ADD_INSN1(ret, &line.node, topn, INT2FIX(1));

                if (index != 0) {
                    ADD_INSN1(ret, &line.node, putobject, INT2FIX(index));
                    ADD_SEND(ret, &line.node, idPLUS, INT2FIX(1));
                }

                ADD_SEND(ret, &line.node, idAREF, INT2FIX(1));
                CHECK(pm_compile_pattern_match(iseq, scope_node, cast->requireds.nodes[index], ret, next_loop_label, in_single_pattern, in_alternation_pattern, false, base_index + 4));
            }

            RUBY_ASSERT(PM_NODE_TYPE_P(cast->left, PM_SPLAT_NODE));
            const pm_splat_node_t *left = (const pm_splat_node_t *) cast->left;

            if (left->expression != NULL) {
                ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
                ADD_INSN1(ret, &line.node, putobject, INT2FIX(0));
                ADD_INSN1(ret, &line.node, topn, INT2FIX(2));
                ADD_SEND(ret, &line.node, idAREF, INT2FIX(2));
                CHECK(pm_compile_pattern_match(iseq, scope_node, left->expression, ret, find_failed_label, in_single_pattern, in_alternation_pattern, false, base_index + 4));
            }

            RUBY_ASSERT(PM_NODE_TYPE_P(cast->right, PM_SPLAT_NODE));
            const pm_splat_node_t *right = (const pm_splat_node_t *) cast->right;

            if (right->expression != NULL) {
                ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
                ADD_INSN1(ret, &line.node, topn, INT2FIX(1));
                ADD_INSN1(ret, &line.node, putobject, INT2FIX(size));
                ADD_SEND(ret, &line.node, idPLUS, INT2FIX(1));
                ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
                ADD_SEND(ret, &line.node, idAREF, INT2FIX(2));
                pm_compile_pattern_match(iseq, scope_node, right->expression, ret, find_failed_label, in_single_pattern, in_alternation_pattern, false, base_index + 4);
            }

            ADD_INSNL(ret, &line.node, jump, find_succeeded_label);

            ADD_LABEL(ret, next_loop_label);
            ADD_INSN1(ret, &line.node, putobject, INT2FIX(1));
            ADD_SEND(ret, &line.node, idPLUS, INT2FIX(1));
            ADD_INSNL(ret, &line.node, jump, while_begin_label);

            ADD_LABEL(ret, find_failed_label);
            ADD_INSN1(ret, &line.node, adjuststack, INT2FIX(3));
            if (in_single_pattern) {
                ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                ADD_INSN1(ret, &line.node, putobject, rb_fstring_lit("%p does not match to find pattern"));
                ADD_INSN1(ret, &line.node, topn, INT2FIX(2));
                ADD_SEND(ret, &line.node, id_core_sprintf, INT2FIX(2));
                ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING + 1));

                ADD_INSN1(ret, &line.node, putobject, Qfalse);
                ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P + 2));

                ADD_INSN(ret, &line.node, pop);
                ADD_INSN(ret, &line.node, pop);
            }
            ADD_INSNL(ret, &line.node, jump, match_failed_label);
            ADD_INSN1(ret, &line.node, dupn, INT2FIX(3));

            ADD_LABEL(ret, find_succeeded_label);
            ADD_INSN1(ret, &line.node, adjuststack, INT2FIX(3));
        }

        ADD_INSN(ret, &line.node, pop);
        ADD_INSNL(ret, &line.node, jump, matched_label);
        ADD_INSN(ret, &line.node, putnil);

        ADD_LABEL(ret, type_error_label);
        ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
        ADD_INSN1(ret, &line.node, putobject, rb_eTypeError);
        ADD_INSN1(ret, &line.node, putobject, rb_fstring_lit("deconstruct must return Array"));
        ADD_SEND(ret, &line.node, id_core_raise, INT2FIX(2));
        ADD_INSN(ret, &line.node, pop);

        ADD_LABEL(ret, match_failed_label);
        ADD_INSN(ret, &line.node, pop);
        ADD_INSNL(ret, &line.node, jump, unmatched_label);

        break;
      }
      case PM_HASH_PATTERN_NODE: {
        // Hash patterns in pattern matching are triggered by using labels and
        // values in a pattern or by using the ** operator. They are represented
        // by the HashPatternNode. This looks like:
        //
        //     foo => { a: 1, b: 2, **bar }
        //
        // It can optionally have an assoc splat in the middle of it, which can
        // optionally have a name.
        const pm_hash_pattern_node_t *cast = (const pm_hash_pattern_node_t *) node;

        // We don't consider it a "rest" parameter if it's a ** that is unnamed.
        bool has_rest = cast->rest != NULL && !(PM_NODE_TYPE_P(cast->rest, PM_ASSOC_SPLAT_NODE) && ((const pm_assoc_splat_node_t *) cast->rest)->value == NULL);
        bool has_keys = cast->elements.size > 0 || cast->rest != NULL;

        LABEL *match_failed_label = NEW_LABEL(line.lineno);
        LABEL *type_error_label = NEW_LABEL(line.lineno);
        VALUE keys = Qnil;

        if (has_keys && !has_rest) {
            keys = rb_ary_new_capa(cast->elements.size);

            for (size_t index = 0; index < cast->elements.size; index++) {
                const pm_node_t *element = cast->elements.nodes[index];
                RUBY_ASSERT(PM_NODE_TYPE_P(element, PM_ASSOC_NODE));

                const pm_node_t *key = ((const pm_assoc_node_t *) element)->key;
                RUBY_ASSERT(PM_NODE_TYPE_P(key, PM_SYMBOL_NODE));

                VALUE symbol = ID2SYM(parse_string_symbol(scope_node, (const pm_symbol_node_t *) key));
                rb_ary_push(keys, symbol);
            }
        }

        if (cast->constant) {
            CHECK(pm_compile_pattern_constant(iseq, scope_node, cast->constant, ret, match_failed_label, in_single_pattern, base_index));
        }

        ADD_INSN(ret, &line.node, dup);
        ADD_INSN1(ret, &line.node, putobject, ID2SYM(rb_intern("deconstruct_keys")));
        ADD_SEND(ret, &line.node, idRespond_to, INT2FIX(1));
        if (in_single_pattern) {
            CHECK(pm_compile_pattern_generic_error(iseq, scope_node, node, ret, rb_fstring_lit("%p does not respond to #deconstruct_keys"), base_index + 1));
        }
        ADD_INSNL(ret, &line.node, branchunless, match_failed_label);

        if (NIL_P(keys)) {
            ADD_INSN(ret, &line.node, putnil);
        }
        else {
            ADD_INSN1(ret, &line.node, duparray, keys);
            RB_OBJ_WRITTEN(iseq, Qundef, rb_obj_hide(keys));
        }
        ADD_SEND(ret, &line.node, rb_intern("deconstruct_keys"), INT2FIX(1));

        ADD_INSN(ret, &line.node, dup);
        ADD_INSN1(ret, &line.node, checktype, INT2FIX(T_HASH));
        ADD_INSNL(ret, &line.node, branchunless, type_error_label);

        if (has_rest) {
            ADD_SEND(ret, &line.node, rb_intern("dup"), INT2FIX(0));
        }

        if (has_keys) {
            DECL_ANCHOR(match_values);
            INIT_ANCHOR(match_values);

            for (size_t index = 0; index < cast->elements.size; index++) {
                const pm_node_t *element = cast->elements.nodes[index];
                RUBY_ASSERT(PM_NODE_TYPE_P(element, PM_ASSOC_NODE));

                const pm_assoc_node_t *assoc = (const pm_assoc_node_t *) element;
                const pm_node_t *key = assoc->key;
                RUBY_ASSERT(PM_NODE_TYPE_P(key, PM_SYMBOL_NODE));

                VALUE symbol = ID2SYM(parse_string_symbol(scope_node, (const pm_symbol_node_t *) key));
                ADD_INSN(ret, &line.node, dup);
                ADD_INSN1(ret, &line.node, putobject, symbol);
                ADD_SEND(ret, &line.node, rb_intern("key?"), INT2FIX(1));

                if (in_single_pattern) {
                    LABEL *match_succeeded_label = NEW_LABEL(line.lineno);

                    ADD_INSN(ret, &line.node, dup);
                    ADD_INSNL(ret, &line.node, branchif, match_succeeded_label);

                    ADD_INSN1(ret, &line.node, putobject, rb_str_freeze(rb_sprintf("key not found: %+"PRIsVALUE, symbol)));
                    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING + 2));
                    ADD_INSN1(ret, &line.node, putobject, Qtrue);
                    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P + 3));
                    ADD_INSN1(ret, &line.node, topn, INT2FIX(3));
                    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_MATCHEE + 4));
                    ADD_INSN1(ret, &line.node, putobject, symbol);
                    ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_KEY + 5));

                    ADD_INSN1(ret, &line.node, adjuststack, INT2FIX(4));
                    ADD_LABEL(ret, match_succeeded_label);
                }

                ADD_INSNL(ret, &line.node, branchunless, match_failed_label);
                ADD_INSN(match_values, &line.node, dup);
                ADD_INSN1(match_values, &line.node, putobject, symbol);
                ADD_SEND(match_values, &line.node, has_rest ? rb_intern("delete") : idAREF, INT2FIX(1));

                const pm_node_t *value = assoc->value;
                if (PM_NODE_TYPE_P(value, PM_IMPLICIT_NODE)) {
                    value = ((const pm_implicit_node_t *) value)->value;
                }

                CHECK(pm_compile_pattern_match(iseq, scope_node, value, match_values, match_failed_label, in_single_pattern, in_alternation_pattern, false, base_index + 1));
            }

            ADD_SEQ(ret, match_values);
        }
        else {
            ADD_INSN(ret, &line.node, dup);
            ADD_SEND(ret, &line.node, idEmptyP, INT2FIX(0));
            if (in_single_pattern) {
                CHECK(pm_compile_pattern_generic_error(iseq, scope_node, node, ret, rb_fstring_lit("%p is not empty"), base_index + 1));
            }
            ADD_INSNL(ret, &line.node, branchunless, match_failed_label);
        }

        if (has_rest) {
            switch (PM_NODE_TYPE(cast->rest)) {
              case PM_NO_KEYWORDS_PARAMETER_NODE: {
                ADD_INSN(ret, &line.node, dup);
                ADD_SEND(ret, &line.node, idEmptyP, INT2FIX(0));
                if (in_single_pattern) {
                    pm_compile_pattern_generic_error(iseq, scope_node, node, ret, rb_fstring_lit("rest of %p is not empty"), base_index + 1);
                }
                ADD_INSNL(ret, &line.node, branchunless, match_failed_label);
                break;
              }
              case PM_ASSOC_SPLAT_NODE: {
                const pm_assoc_splat_node_t *splat = (const pm_assoc_splat_node_t *) cast->rest;
                ADD_INSN(ret, &line.node, dup);
                pm_compile_pattern_match(iseq, scope_node, splat->value, ret, match_failed_label, in_single_pattern, in_alternation_pattern, false, base_index + 1);
                break;
              }
              default:
                rb_bug("unreachable");
                break;
            }
        }

        ADD_INSN(ret, &line.node, pop);
        ADD_INSNL(ret, &line.node, jump, matched_label);
        ADD_INSN(ret, &line.node, putnil);

        ADD_LABEL(ret, type_error_label);
        ADD_INSN1(ret, &line.node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
        ADD_INSN1(ret, &line.node, putobject, rb_eTypeError);
        ADD_INSN1(ret, &line.node, putobject, rb_fstring_lit("deconstruct_keys must return Hash"));
        ADD_SEND(ret, &line.node, id_core_raise, INT2FIX(2));
        ADD_INSN(ret, &line.node, pop);

        ADD_LABEL(ret, match_failed_label);
        ADD_INSN(ret, &line.node, pop);
        ADD_INSNL(ret, &line.node, jump, unmatched_label);
        break;
      }
      case PM_CAPTURE_PATTERN_NODE: {
        // Capture patterns allow you to pattern match against an element in a
        // pattern and also capture the value into a local variable. This looks
        // like:
        //
        //     [1] => [Integer => foo]
        //
        // In this case the `Integer => foo` will be represented by a
        // CapturePatternNode, which has both a value (the pattern to match
        // against) and a target (the place to write the variable into).
        const pm_capture_pattern_node_t *cast = (const pm_capture_pattern_node_t *) node;

        LABEL *match_failed_label = NEW_LABEL(line.lineno);

        ADD_INSN(ret, &line.node, dup);
        CHECK(pm_compile_pattern_match(iseq, scope_node, cast->value, ret, match_failed_label, in_single_pattern, in_alternation_pattern, use_deconstructed_cache, base_index + 1));
        CHECK(pm_compile_pattern(iseq, scope_node, cast->target, ret, matched_label, match_failed_label, in_single_pattern, in_alternation_pattern, false, base_index));
        ADD_INSN(ret, &line.node, putnil);

        ADD_LABEL(ret, match_failed_label);
        ADD_INSN(ret, &line.node, pop);
        ADD_INSNL(ret, &line.node, jump, unmatched_label);

        break;
      }
      case PM_LOCAL_VARIABLE_TARGET_NODE: {
        // Local variables can be targeted by placing identifiers in the place
        // of a pattern. For example, foo in bar. This results in the value
        // being matched being written to that local variable.
        pm_local_variable_target_node_t *cast = (pm_local_variable_target_node_t *) node;
        pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, cast->name, cast->depth);

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

        ADD_SETLOCAL(ret, &line.node, index.index, index.level);
        ADD_INSNL(ret, &line.node, jump, matched_label);
        break;
      }
      case PM_ALTERNATION_PATTERN_NODE: {
        // Alternation patterns allow you to specify multiple patterns in a
        // single expression using the | operator.
        pm_alternation_pattern_node_t *cast = (pm_alternation_pattern_node_t *) node;

        LABEL *matched_left_label = NEW_LABEL(line.lineno);
        LABEL *unmatched_left_label = NEW_LABEL(line.lineno);

        // First, we're going to attempt to match against the left pattern. If
        // that pattern matches, then we'll skip matching the right pattern.
        ADD_INSN(ret, &line.node, dup);
        CHECK(pm_compile_pattern(iseq, scope_node, cast->left, ret, matched_left_label, unmatched_left_label, in_single_pattern, true, true, base_index + 1));

        // If we get here, then we matched on the left pattern. In this case we
        // should pop out the duplicate value that we preemptively added to
        // match against the right pattern and then jump to the match label.
        ADD_LABEL(ret, matched_left_label);
        ADD_INSN(ret, &line.node, pop);
        ADD_INSNL(ret, &line.node, jump, matched_label);
        ADD_INSN(ret, &line.node, putnil);

        // If we get here, then we didn't match on the left pattern. In this
        // case we attempt to match against the right pattern.
        ADD_LABEL(ret, unmatched_left_label);
        CHECK(pm_compile_pattern(iseq, scope_node, cast->right, ret, matched_label, unmatched_label, in_single_pattern, true, true, base_index));
        break;
      }
      case PM_PARENTHESES_NODE:
        // Parentheses are allowed to wrap expressions in pattern matching and
        // they do nothing since they can only wrap individual expressions and
        // not groups. In this case we'll recurse back into this same function
        // with the body of the parentheses.
        return pm_compile_pattern(iseq, scope_node, ((pm_parentheses_node_t *) node)->body, ret, matched_label, unmatched_label, in_single_pattern, in_alternation_pattern, use_deconstructed_cache, base_index);
      case PM_PINNED_EXPRESSION_NODE:
        // Pinned expressions are a way to match against the value of an
        // expression that should be evaluated at runtime. This looks like:
        // foo in ^(bar). To compile these, we compile the expression as if it
        // were a literal value by falling through to the literal case.
        node = ((pm_pinned_expression_node_t *) node)->expression;
        /* fallthrough */
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
      case PM_SOURCE_ENCODING_NODE:
      case PM_SOURCE_FILE_NODE:
      case PM_SOURCE_LINE_NODE:
      case PM_RANGE_NODE:
      case PM_RATIONAL_NODE:
      case PM_REGULAR_EXPRESSION_NODE:
      case PM_SELF_NODE:
      case PM_STRING_NODE:
      case PM_SYMBOL_NODE:
      case PM_TRUE_NODE:
      case PM_X_STRING_NODE: {
        // These nodes are all simple patterns, which means we'll use the
        // checkmatch instruction to match against them, which is effectively a
        // VM-level === operator.
        PM_COMPILE_NOT_POPPED(node);
        if (in_single_pattern) {
            ADD_INSN1(ret, &line.node, dupn, INT2FIX(2));
        }

        ADD_INSN1(ret, &line.node, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_CASE));

        if (in_single_pattern) {
            pm_compile_pattern_eqq_error(iseq, scope_node, node, ret, base_index + 2);
        }

        ADD_INSNL(ret, &line.node, branchif, matched_label);
        ADD_INSNL(ret, &line.node, jump, unmatched_label);
        break;
      }
      case PM_PINNED_VARIABLE_NODE: {
        // Pinned variables are a way to match against the value of a variable
        // without it looking like you're trying to write to the variable. This
        // looks like: foo in ^@bar. To compile these, we compile the variable
        // that they hold.
        pm_pinned_variable_node_t *cast = (pm_pinned_variable_node_t *) node;
        CHECK(pm_compile_pattern(iseq, scope_node, cast->variable, ret, matched_label, unmatched_label, in_single_pattern, in_alternation_pattern, true, base_index));
        break;
      }
      case PM_IF_NODE:
      case PM_UNLESS_NODE: {
        // If and unless nodes can show up here as guards on `in` clauses. This
        // looks like:
        //
        //     case foo
        //     in bar if baz?
        //       qux
        //     end
        //
        // Because we know they're in the modifier form and they can't have any
        // variation on this pattern, we compile them differently (more simply)
        // here than we would in the normal compilation path.
        const pm_node_t *predicate;
        const pm_node_t *statement;

        if (PM_NODE_TYPE_P(node, PM_IF_NODE)) {
            const pm_if_node_t *cast = (const pm_if_node_t *) node;
            predicate = cast->predicate;

            RUBY_ASSERT(cast->statements != NULL && cast->statements->body.size == 1);
            statement = cast->statements->body.nodes[0];
        }
        else {
            const pm_unless_node_t *cast = (const pm_unless_node_t *) node;
            predicate = cast->predicate;

            RUBY_ASSERT(cast->statements != NULL && cast->statements->body.size == 1);
            statement = cast->statements->body.nodes[0];
        }

        CHECK(pm_compile_pattern_match(iseq, scope_node, statement, ret, unmatched_label, in_single_pattern, in_alternation_pattern, use_deconstructed_cache, base_index));
        PM_COMPILE_NOT_POPPED(predicate);

        if (in_single_pattern) {
            LABEL *match_succeeded_label = NEW_LABEL(line.lineno);

            ADD_INSN(ret, &line.node, dup);
            if (PM_NODE_TYPE_P(node, PM_IF_NODE)) {
                ADD_INSNL(ret, &line.node, branchif, match_succeeded_label);
            }
            else {
                ADD_INSNL(ret, &line.node, branchunless, match_succeeded_label);
            }

            ADD_INSN1(ret, &line.node, putobject, rb_fstring_lit("guard clause does not return true"));
            ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING + 1));
            ADD_INSN1(ret, &line.node, putobject, Qfalse);
            ADD_INSN1(ret, &line.node, setn, INT2FIX(base_index + PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P + 2));

            ADD_INSN(ret, &line.node, pop);
            ADD_INSN(ret, &line.node, pop);

            ADD_LABEL(ret, match_succeeded_label);
        }

        if (PM_NODE_TYPE_P(node, PM_IF_NODE)) {
            ADD_INSNL(ret, &line.node, branchunless, unmatched_label);
        }
        else {
            ADD_INSNL(ret, &line.node, branchif, unmatched_label);
        }

        ADD_INSNL(ret, &line.node, jump, matched_label);
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

#undef PM_PATTERN_BASE_INDEX_OFFSET_DECONSTRUCTED_CACHE
#undef PM_PATTERN_BASE_INDEX_OFFSET_ERROR_STRING
#undef PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_P
#undef PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_MATCHEE
#undef PM_PATTERN_BASE_INDEX_OFFSET_KEY_ERROR_KEY

// Generate a scope node from the given node.
void
pm_scope_node_init(const pm_node_t *node, pm_scope_node_t *scope, pm_scope_node_t *previous)
{
    // This is very important, otherwise the scope node could be seen as having
    // certain flags set that _should not_ be set.
    memset(scope, 0, sizeof(pm_scope_node_t));

    scope->base.type = PM_SCOPE_NODE;
    scope->base.location.start = node->location.start;
    scope->base.location.end = node->location.end;

    scope->previous = previous;
    scope->ast_node = (pm_node_t *)node;

    if (previous) {
        scope->parser = previous->parser;
        scope->encoding = previous->encoding;
        scope->constants = previous->constants;
    }

    switch (PM_NODE_TYPE(node)) {
      case PM_BLOCK_NODE: {
        pm_block_node_t *cast = (pm_block_node_t *) node;
        scope->body = cast->body;
        scope->locals = cast->locals;
        scope->parameters = cast->parameters;
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
        scope->parameters = (pm_node_t *)cast->parameters;
        scope->body = cast->body;
        scope->locals = cast->locals;
        break;
      }
      case PM_ENSURE_NODE: {
        scope->body = (pm_node_t *)node;
        break;
      }
      case PM_FOR_NODE: {
        pm_for_node_t *cast = (pm_for_node_t *)node;
        scope->body = (pm_node_t *)cast->statements;
        break;
      }
      case PM_INTERPOLATED_REGULAR_EXPRESSION_NODE: {
        RUBY_ASSERT(node->flags & PM_REGULAR_EXPRESSION_FLAGS_ONCE);
        scope->body = (pm_node_t *)node;
        break;
      }
      case PM_LAMBDA_NODE: {
        pm_lambda_node_t *cast = (pm_lambda_node_t *) node;
        scope->parameters = cast->parameters;
        scope->body = cast->body;
        scope->locals = cast->locals;

        if (cast->parameters != NULL) {
            scope->base.location.start = cast->parameters->location.start;
        }
        else {
            scope->base.location.start = cast->operator_loc.end;
        }
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
      case PM_RESCUE_NODE: {
        pm_rescue_node_t *cast = (pm_rescue_node_t *)node;
        scope->body = (pm_node_t *)cast->statements;
        break;
      }
      case PM_RESCUE_MODIFIER_NODE: {
        pm_rescue_modifier_node_t *cast = (pm_rescue_modifier_node_t *)node;
        scope->body = (pm_node_t *)cast->rescue_expression;
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
        rb_bug("unreachable");
        break;
    }
}

void
pm_scope_node_destroy(pm_scope_node_t *scope_node)
{
    if (scope_node->index_lookup_table) {
        st_free_table(scope_node->index_lookup_table);
    }
}

static void pm_compile_call(rb_iseq_t *iseq, const pm_call_node_t *call_node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node, ID method_id, LABEL *start);

void
pm_compile_defined_expr0(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node, NODE dummy_line_node, int lineno, bool in_condition, LABEL **lfinish, bool explicit_receiver)
{
    // in_condition is the same as compile.c's needstr
    enum defined_type dtype = DEFINED_NOT_DEFINED;

    switch (PM_NODE_TYPE(node)) {
      case PM_ARGUMENTS_NODE: {
        const pm_arguments_node_t *cast = (pm_arguments_node_t *) node;
        const pm_node_list_t *arguments = &cast->arguments;
        for (size_t idx = 0; idx < arguments->size; idx++) {
            const pm_node_t *argument = arguments->nodes[idx];
            pm_compile_defined_expr0(iseq, argument, ret, popped, scope_node, dummy_line_node, lineno, in_condition, lfinish, explicit_receiver);

            if (!lfinish[1]) {
                lfinish[1] = NEW_LABEL(lineno);
            }
            ADD_INSNL(ret, &dummy_line_node, branchunless, lfinish[1]);
        }
        dtype = DEFINED_TRUE;
        break;
      }
      case PM_NIL_NODE:
        dtype = DEFINED_NIL;
        break;
      case PM_PARENTHESES_NODE: {
        const pm_parentheses_node_t *cast = (const pm_parentheses_node_t *) node;

        if (cast->body == NULL) {
            // If we have empty parentheses, then we want to return "nil".
            dtype = DEFINED_NIL;
        }
        else if (PM_NODE_TYPE_P(cast->body, PM_STATEMENTS_NODE) && ((const pm_statements_node_t *) cast->body)->body.size == 1) {
            // If we have a parentheses node that is wrapping a single statement
            // then we want to recurse down to that statement and compile it.
            pm_compile_defined_expr0(iseq, ((const pm_statements_node_t *) cast->body)->body.nodes[0], ret, popped, scope_node, dummy_line_node, lineno, in_condition, lfinish, explicit_receiver);
            return;
        }
        else {
            // Otherwise, we have parentheses wrapping multiple statements, in
            // which case this is defined as "expression".
            dtype = DEFINED_EXPR;
        }

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
          pm_array_node_t *cast = (pm_array_node_t *) node;

          if (!PM_NODE_FLAG_P(cast, PM_ARRAY_NODE_FLAGS_CONTAINS_SPLAT)) {
              for (size_t index = 0; index < cast->elements.size; index++) {
                  pm_compile_defined_expr0(iseq, cast->elements.nodes[index], ret, popped, scope_node, dummy_line_node, lineno, true, lfinish, false);

                  if (!lfinish[1]) {
                      lfinish[1] = NEW_LABEL(lineno);
                  }

                  ADD_INSNL(ret, &dummy_line_node, branchunless, lfinish[1]);
              }
          }
      }
      case PM_AND_NODE:
      case PM_BEGIN_NODE:
      case PM_BREAK_NODE:
      case PM_CASE_NODE:
      case PM_CASE_MATCH_NODE:
      case PM_CLASS_NODE:
      case PM_DEF_NODE:
      case PM_DEFINED_NODE:
      case PM_FLOAT_NODE:
      case PM_FOR_NODE:
      case PM_HASH_NODE:
      case PM_IF_NODE:
      case PM_IMAGINARY_NODE:
      case PM_INTEGER_NODE:
      case PM_INTERPOLATED_REGULAR_EXPRESSION_NODE:
      case PM_INTERPOLATED_STRING_NODE:
      case PM_INTERPOLATED_SYMBOL_NODE:
      case PM_INTERPOLATED_X_STRING_NODE:
      case PM_KEYWORD_HASH_NODE:
      case PM_LAMBDA_NODE:
      case PM_MATCH_PREDICATE_NODE:
      case PM_MATCH_REQUIRED_NODE:
      case PM_MATCH_WRITE_NODE:
      case PM_MODULE_NODE:
      case PM_NEXT_NODE:
      case PM_OR_NODE:
      case PM_RANGE_NODE:
      case PM_RATIONAL_NODE:
      case PM_REDO_NODE:
      case PM_REGULAR_EXPRESSION_NODE:
      case PM_RETRY_NODE:
      case PM_RETURN_NODE:
      case PM_SINGLETON_CLASS_NODE:
      case PM_SOURCE_ENCODING_NODE:
      case PM_SOURCE_FILE_NODE:
      case PM_SOURCE_LINE_NODE:
      case PM_STRING_NODE:
      case PM_SYMBOL_NODE:
      case PM_UNLESS_NODE:
      case PM_UNTIL_NODE:
      case PM_WHILE_NODE:
      case PM_X_STRING_NODE:
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
      case PM_BACK_REFERENCE_READ_NODE: {
        char *char_ptr = (char *)(node->location.start) + 1;
        ID backref_val = INT2FIX(rb_intern2(char_ptr, 1)) << 1 | 1;

        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_REF),
                  backref_val,
                  PUSH_VAL(DEFINED_GVAR));

        return;
      }
      case PM_NUMBERED_REFERENCE_READ_NODE: {
        uint32_t reference_number = ((pm_numbered_reference_read_node_t *)node)->number;

        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_REF),
                  INT2FIX(reference_number << 1),
                  PUSH_VAL(DEFINED_GVAR));

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
          pm_compile_defined_expr0(iseq, constant_path_node->parent, ret, popped, scope_node, dummy_line_node, lineno, true, lfinish, false);
          ADD_INSNL(ret, &dummy_line_node, branchunless, lfinish[1]);
          PM_COMPILE(constant_path_node->parent);
        }
        else {
          ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CONST_FROM),
                  ID2SYM(pm_constant_id_lookup(scope_node, ((pm_constant_read_node_t *)constant_path_node->child)->name)), PUSH_VAL(DEFINED_CONST));
        return;
      }

      case PM_CALL_NODE: {
        pm_call_node_t *call_node = ((pm_call_node_t *)node);
        ID method_id = pm_constant_id_lookup(scope_node, call_node->name);

        if (call_node->receiver || call_node->arguments) {
            if (!lfinish[1]) {
                lfinish[1] = NEW_LABEL(lineno);
            }
            if (!lfinish[2]) {
                lfinish[2] = NEW_LABEL(lineno);
            }
        }

        if (call_node->arguments) {
            pm_compile_defined_expr0(iseq, (const pm_node_t *)call_node->arguments, ret, popped, scope_node, dummy_line_node, lineno, true, lfinish, false);
            ADD_INSNL(ret, &dummy_line_node, branchunless, lfinish[1]);
        }

        if (call_node->receiver) {
            pm_compile_defined_expr0(iseq, call_node->receiver, ret, popped, scope_node, dummy_line_node, lineno, true, lfinish, true);
            if (PM_NODE_TYPE_P(call_node->receiver, PM_CALL_NODE)) {
                ADD_INSNL(ret, &dummy_line_node, branchunless, lfinish[2]);

                const pm_call_node_t *receiver = (const pm_call_node_t *)call_node->receiver;
                ID method_id = pm_constant_id_lookup(scope_node, receiver->name);
                pm_compile_call(iseq, receiver, ret, popped, scope_node, method_id, NULL);
            }
            else {
                ADD_INSNL(ret, &dummy_line_node, branchunless, lfinish[1]);
                PM_COMPILE(call_node->receiver);
            }

            if (explicit_receiver) {
                PM_DUP;
            }

            ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_METHOD), rb_id2sym(method_id), PUSH_VAL(DEFINED_METHOD));
        }
        else {
            PM_PUTSELF;
            if (explicit_receiver) {
                PM_DUP;
            }
            ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_FUNC), rb_id2sym(method_id), PUSH_VAL(DEFINED_METHOD));
        }
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
      case PM_CALL_AND_WRITE_NODE:
      case PM_CALL_OPERATOR_WRITE_NODE:
      case PM_CALL_OR_WRITE_NODE:

      case PM_CONSTANT_WRITE_NODE:
      case PM_CONSTANT_OPERATOR_WRITE_NODE:
      case PM_CONSTANT_AND_WRITE_NODE:
      case PM_CONSTANT_OR_WRITE_NODE:

      case PM_CONSTANT_PATH_AND_WRITE_NODE:
      case PM_CONSTANT_PATH_OPERATOR_WRITE_NODE:
      case PM_CONSTANT_PATH_OR_WRITE_NODE:
      case PM_CONSTANT_PATH_WRITE_NODE:

      case PM_GLOBAL_VARIABLE_WRITE_NODE:
      case PM_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE:
      case PM_GLOBAL_VARIABLE_AND_WRITE_NODE:
      case PM_GLOBAL_VARIABLE_OR_WRITE_NODE:

      case PM_CLASS_VARIABLE_WRITE_NODE:
      case PM_CLASS_VARIABLE_OPERATOR_WRITE_NODE:
      case PM_CLASS_VARIABLE_AND_WRITE_NODE:
      case PM_CLASS_VARIABLE_OR_WRITE_NODE:

      case PM_INDEX_AND_WRITE_NODE:
      case PM_INDEX_OPERATOR_WRITE_NODE:
      case PM_INDEX_OR_WRITE_NODE:

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
        rb_bug("Unsupported node %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
    }

    RUBY_ASSERT(dtype != DEFINED_NOT_DEFINED);

    ADD_INSN1(ret, &dummy_line_node, putobject, PUSH_VAL(dtype));
#undef PUSH_VAL
}

static void
pm_defined_expr(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node,  NODE dummy_line_node, int lineno, bool in_condition, LABEL **lfinish, bool explicit_receiver)
{
    LINK_ELEMENT *lcur = ret->last;

    pm_compile_defined_expr0(iseq, node, ret, popped, scope_node, dummy_line_node, lineno, in_condition, lfinish, false);

    if (lfinish[1]) {
        LABEL *lstart = NEW_LABEL(lineno);
        LABEL *lend = NEW_LABEL(lineno);

        struct rb_iseq_new_with_callback_callback_func *ifunc =
            rb_iseq_new_with_callback_new_callback(build_defined_rescue_iseq, NULL);

        const rb_iseq_t *rescue = new_child_iseq_with_callback(iseq, ifunc,
                                              rb_str_concat(rb_str_new2("defined guard in "),
                                                            ISEQ_BODY(iseq)->location.label),
                                              iseq, ISEQ_TYPE_RESCUE, 0);

        lstart->rescued = LABEL_RESCUE_BEG;
        lend->rescued = LABEL_RESCUE_END;

        APPEND_LABEL(ret, lcur, lstart);
        ADD_LABEL(ret, lend);
        ADD_CATCH_ENTRY(CATCH_TYPE_RESCUE, lstart, lend, rescue, lfinish[1]);
    }
}

void
pm_compile_defined_expr(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node, NODE dummy_line_node, int lineno, bool in_condition)
{
    LABEL *lfinish[3];
    LINK_ELEMENT *last = ret->last;

    lfinish[0] = NEW_LABEL(lineno);
    lfinish[1] = 0;
    lfinish[2] = 0;

    if (!popped) {
        pm_defined_expr(iseq, node, ret, popped, scope_node, dummy_line_node, lineno, in_condition, lfinish, false);
    }

    if (lfinish[1]) {
        ELEM_INSERT_NEXT(last, &new_insn_body(iseq, nd_line(&dummy_line_node), nd_node_id(&dummy_line_node), BIN(putnil), 0)->link);
        PM_SWAP;
        if (lfinish[2]) {
            ADD_LABEL(ret, lfinish[2]);
        }
        PM_POP;
        ADD_LABEL(ret, lfinish[1]);

    }
    ADD_LABEL(ret, lfinish[0]);
}

static void
pm_compile_call(rb_iseq_t *iseq, const pm_call_node_t *call_node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node, ID method_id, LABEL *start)
{
    const pm_location_t *message_loc = &call_node->message_loc;
    if (message_loc->start == NULL) message_loc = &call_node->base.location;

    int lineno = pm_location_line_number(scope_node->parser, message_loc);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    LABEL *else_label = NEW_LABEL(lineno);
    LABEL *end_label = NEW_LABEL(lineno);

    if (PM_NODE_FLAG_P(call_node, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION)) {
        PM_DUP;
        ADD_INSNL(ret, &dummy_line_node, branchnil, else_label);
    }

    int flags = 0;
    struct rb_callinfo_kwarg *kw_arg = NULL;

    int orig_argc = pm_setup_args(call_node->arguments, call_node->block, &flags, &kw_arg, iseq, ret, scope_node, dummy_line_node);
    const rb_iseq_t *block_iseq = NULL;

    if (call_node->block != NULL && PM_NODE_TYPE_P(call_node->block, PM_BLOCK_NODE)) {
        // Scope associated with the block
        pm_scope_node_t next_scope_node;
        pm_scope_node_init(call_node->block, &next_scope_node, scope_node);

        block_iseq = NEW_CHILD_ISEQ(&next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, pm_node_line_number(scope_node->parser, call_node->block));
        pm_scope_node_destroy(&next_scope_node);

        if (ISEQ_BODY(block_iseq)->catch_table) {
            ADD_CATCH_ENTRY(CATCH_TYPE_BREAK, start, end_label, block_iseq, end_label);
        }
        ISEQ_COMPILE_DATA(iseq)->current_block = block_iseq;
    }
    else {
        if (PM_NODE_FLAG_P(call_node, PM_CALL_NODE_FLAGS_VARIABLE_CALL)) {
            flags |= VM_CALL_VCALL;
        }

        if (!flags) {
            flags |= VM_CALL_ARGS_SIMPLE;
        }
    }

    if (PM_NODE_FLAG_P(call_node, PM_CALL_NODE_FLAGS_IGNORE_VISIBILITY)) {
        flags |= VM_CALL_FCALL;
    }

    if (!popped && PM_NODE_FLAG_P(call_node, PM_CALL_NODE_FLAGS_ATTRIBUTE_WRITE)) {
        if (flags & VM_CALL_ARGS_BLOCKARG) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
            if (flags & VM_CALL_ARGS_SPLAT) {
                ADD_INSN1(ret, &dummy_line_node, putobject, INT2FIX(-1));
                ADD_SEND_WITH_FLAG(ret, &dummy_line_node, idAREF, INT2FIX(1), INT2FIX(0));
            }
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(orig_argc + 3));
            PM_POP;
        }
        else if (flags & VM_CALL_ARGS_SPLAT) {
            ADD_INSN(ret, &dummy_line_node, dup);
            ADD_INSN1(ret, &dummy_line_node, putobject, INT2FIX(-1));
            ADD_SEND_WITH_FLAG(ret, &dummy_line_node, idAREF, INT2FIX(1), INT2FIX(0));
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(orig_argc + 2));
            PM_POP;
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(orig_argc + 1));
        }
    }

    if ((flags & VM_CALL_KW_SPLAT) && (flags & VM_CALL_ARGS_BLOCKARG) && !(flags & VM_CALL_KW_SPLAT_MUT)) {
        ADD_INSN(ret, &dummy_line_node, splatkw);
    }

    ADD_SEND_R(ret, &dummy_line_node, method_id, INT2FIX(orig_argc), block_iseq, INT2FIX(flags), kw_arg);

    if (PM_NODE_FLAG_P(call_node, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION)) {
        ADD_INSNL(ret, &dummy_line_node, jump, end_label);
        ADD_LABEL(ret, else_label);
    }

    if (PM_NODE_FLAG_P(call_node, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION) || (block_iseq && ISEQ_BODY(block_iseq)->catch_table)) {
        ADD_LABEL(ret, end_label);
    }

    if (PM_NODE_FLAG_P(call_node, PM_CALL_NODE_FLAGS_ATTRIBUTE_WRITE)) {
        PM_POP_UNLESS_POPPED;
    }

    PM_POP_IF_POPPED;
}

// This is exactly the same as add_ensure_iseq, except it compiled
// the node as a Prism node, and not a CRuby node
static void
pm_add_ensure_iseq(LINK_ANCHOR *const ret, rb_iseq_t *iseq, int is_return, pm_scope_node_t *scope_node)
{
    RUBY_ASSERT(can_add_ensure_iseq(iseq));

    struct iseq_compile_data_ensure_node_stack *enlp =
        ISEQ_COMPILE_DATA(iseq)->ensure_node_stack;
    struct iseq_compile_data_ensure_node_stack *prev_enlp = enlp;
    DECL_ANCHOR(ensure);

    INIT_ANCHOR(ensure);
    while (enlp) {
        if (enlp->erange != NULL) {
            DECL_ANCHOR(ensure_part);
            LABEL *lstart = NEW_LABEL(0);
            LABEL *lend = NEW_LABEL(0);
            INIT_ANCHOR(ensure_part);

            add_ensure_range(iseq, enlp->erange, lstart, lend);

            ISEQ_COMPILE_DATA(iseq)->ensure_node_stack = enlp->prev;
            ADD_LABEL(ensure_part, lstart);
            bool popped = true;
            PM_COMPILE_INTO_ANCHOR(ensure_part, (pm_node_t *)enlp->ensure_node);
            ADD_LABEL(ensure_part, lend);
            ADD_SEQ(ensure, ensure_part);
        }
        else {
            if (!is_return) {
                break;
            }
        }
        enlp = enlp->prev;
    }
    ISEQ_COMPILE_DATA(iseq)->ensure_node_stack = prev_enlp;
    ADD_SEQ(ret, ensure);
}

struct pm_local_table_insert_ctx {
    pm_scope_node_t *scope_node;
    rb_ast_id_table_t *local_table_for_iseq;
    int local_index;
};

static int
pm_local_table_insert_func(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    if (!existing) {
        pm_constant_id_t constant_id = (pm_constant_id_t)*key;
        struct pm_local_table_insert_ctx * ctx = (struct pm_local_table_insert_ctx *)arg;

        pm_scope_node_t *scope_node = ctx->scope_node;
        rb_ast_id_table_t *local_table_for_iseq = ctx->local_table_for_iseq;
        int local_index = ctx->local_index;

        ID local = pm_constant_id_lookup(scope_node, constant_id);
        local_table_for_iseq->ids[local_index] = local;

        *value = (st_data_t)local_index;

        ctx->local_index++;
    }

    return ST_CONTINUE;
}

/**
 * Insert a local into the local table for the iseq. This is used to create the
 * local table in the correct order while compiling the scope. The locals being
 * inserted are regular named locals, as opposed to special forwarding locals.
 */
static void
pm_insert_local_index(pm_constant_id_t constant_id, int local_index, st_table *index_lookup_table, rb_ast_id_table_t *local_table_for_iseq, pm_scope_node_t *scope_node)
{
    RUBY_ASSERT((constant_id & PM_SPECIAL_CONSTANT_FLAG) == 0);

    ID local = pm_constant_id_lookup(scope_node, constant_id);
    local_table_for_iseq->ids[local_index] = local;
    st_insert(index_lookup_table, (st_data_t) constant_id, (st_data_t) local_index);
}

/**
 * Insert a local into the local table for the iseq that is a special forwarding
 * local variable.
 */
static void
pm_insert_local_special(ID local_name, int local_index, st_table *index_lookup_table, rb_ast_id_table_t *local_table_for_iseq)
{
    local_table_for_iseq->ids[local_index] = local_name;
    st_insert(index_lookup_table, (st_data_t) (local_name | PM_SPECIAL_CONSTANT_FLAG), (st_data_t) local_index);
}

/**
 * Compile the locals of a multi target node that is used as a positional
 * parameter in a method, block, or lambda definition. Note that this doesn't
 * actually add any instructions to the iseq. Instead, it adds locals to the
 * local and index lookup tables and increments the local index as necessary.
 */
static int
pm_compile_destructured_param_locals(const pm_multi_target_node_t *node, st_table *index_lookup_table, rb_ast_id_table_t *local_table_for_iseq, pm_scope_node_t *scope_node, int local_index)
{
    for (size_t index = 0; index < node->lefts.size; index++) {
        const pm_node_t *left = node->lefts.nodes[index];

        if (PM_NODE_TYPE_P(left, PM_REQUIRED_PARAMETER_NODE)) {
            if (!PM_NODE_FLAG_P(left, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                pm_insert_local_index(((const pm_required_parameter_node_t *) left)->name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                local_index++;
            }
        }
        else {
            RUBY_ASSERT(PM_NODE_TYPE_P(left, PM_MULTI_TARGET_NODE));
            local_index = pm_compile_destructured_param_locals((const pm_multi_target_node_t *) left, index_lookup_table, local_table_for_iseq, scope_node, local_index);
        }
    }

    if (node->rest != NULL && PM_NODE_TYPE_P(node->rest, PM_SPLAT_NODE)) {
        const pm_splat_node_t *rest = (const pm_splat_node_t *) node->rest;

        if (rest->expression != NULL) {
            RUBY_ASSERT(PM_NODE_TYPE_P(rest->expression, PM_REQUIRED_PARAMETER_NODE));
            pm_insert_local_index(((const pm_required_parameter_node_t *) rest->expression)->name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
            local_index++;
        }
    }

    for (size_t index = 0; index < node->rights.size; index++) {
        const pm_node_t *right = node->rights.nodes[index];

        if (PM_NODE_TYPE_P(right, PM_REQUIRED_PARAMETER_NODE)) {
            pm_insert_local_index(((const pm_required_parameter_node_t *) right)->name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
            local_index++;
        }
        else {
            RUBY_ASSERT(PM_NODE_TYPE_P(right, PM_MULTI_TARGET_NODE));
            local_index = pm_compile_destructured_param_locals((const pm_multi_target_node_t *) right, index_lookup_table, local_table_for_iseq, scope_node, local_index);
        }
    }

    return local_index;
}

/**
 * Compile a required parameter node that is part of a destructure that is used
 * as a positional parameter in a method, block, or lambda definition.
 */
static inline void
pm_compile_destructured_param_write(rb_iseq_t *iseq, const pm_required_parameter_node_t *node, LINK_ANCHOR *const ret, const pm_scope_node_t *scope_node)
{
    int lineno = pm_node_line_number(scope_node->parser, (const pm_node_t *) node);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, node->name, 0);
    ADD_SETLOCAL(ret, &dummy_line_node, index.index, index.level);
}

/**
 * Compile a multi target node that is used as a positional parameter in a
 * method, block, or lambda definition. Note that this is effectively the same
 * as a multi write, but with the added context that all of the targets
 * contained in the write are required parameter nodes. With this context, we
 * know they won't have any parent expressions so we build a separate code path
 * for this simplified case.
 */
static void
pm_compile_destructured_param_writes(rb_iseq_t *iseq, const pm_multi_target_node_t *node, LINK_ANCHOR *const ret, const pm_scope_node_t *scope_node)
{
    int lineno = pm_node_line_number(scope_node->parser, (const pm_node_t *) node);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    bool has_rest = (node->rest && PM_NODE_TYPE_P(node->rest, PM_SPLAT_NODE) && (((pm_splat_node_t *) node->rest)->expression) != NULL);
    bool has_rights = node->rights.size > 0;

    int flag = (has_rest || has_rights) ? 1 : 0;
    ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(node->lefts.size), INT2FIX(flag));

    for (size_t index = 0; index < node->lefts.size; index++) {
        const pm_node_t *left = node->lefts.nodes[index];

        if (PM_NODE_TYPE_P(left, PM_REQUIRED_PARAMETER_NODE)) {
            pm_compile_destructured_param_write(iseq, (const pm_required_parameter_node_t *) left, ret, scope_node);
        }
        else {
            RUBY_ASSERT(PM_NODE_TYPE_P(left, PM_MULTI_TARGET_NODE));
            pm_compile_destructured_param_writes(iseq, (const pm_multi_target_node_t *) left, ret, scope_node);
        }
    }

    if (has_rest) {
        if (has_rights) {
            ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(node->rights.size), INT2FIX(3));
        }

        const pm_node_t *rest = ((pm_splat_node_t *) node->rest)->expression;
        RUBY_ASSERT(PM_NODE_TYPE_P(rest, PM_REQUIRED_PARAMETER_NODE));

        pm_compile_destructured_param_write(iseq, (const pm_required_parameter_node_t *) rest, ret, scope_node);
    }

    if (has_rights) {
        if (!has_rest) {
            ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(node->rights.size), INT2FIX(2));
        }

        for (size_t index = 0; index < node->rights.size; index++) {
            const pm_node_t *right = node->rights.nodes[index];

            if (PM_NODE_TYPE_P(right, PM_REQUIRED_PARAMETER_NODE)) {
                pm_compile_destructured_param_write(iseq, (const pm_required_parameter_node_t *) right, ret, scope_node);
            }
            else {
                RUBY_ASSERT(PM_NODE_TYPE_P(right, PM_MULTI_TARGET_NODE));
                pm_compile_destructured_param_writes(iseq, (const pm_multi_target_node_t *) right, ret, scope_node);
            }
        }
    }
}

/**
 * This is a node in the multi target state linked list. It tracks the
 * information for a particular target that necessarily has a parent expression.
 */
typedef struct pm_multi_target_state_node {
    // The pointer to the topn instruction that will need to be modified after
    // we know the total stack size of all of the targets.
    INSN *topn;

    // The index of the stack from the base of the entire multi target at which
    // the parent expression is located.
    size_t stack_index;

    // The number of slots in the stack that this node occupies.
    size_t stack_size;

    // The position of the node in the list of targets.
    size_t position;

    // A pointer to the next node in this linked list.
    struct pm_multi_target_state_node *next;
} pm_multi_target_state_node_t;

/**
 * As we're compiling a multi target, we need to track additional information
 * whenever there is a parent expression on the left hand side of the target.
 * This is because we need to go back and tell the expression where to fetch its
 * parent expression from the stack. We use a linked list of nodes to track this
 * information.
 */
typedef struct {
    // The total number of slots in the stack that this multi target occupies.
    size_t stack_size;

    // The position of the current node being compiled. This is forwarded to
    // nodes when they are allocated.
    size_t position;

    // A pointer to the head of this linked list.
    pm_multi_target_state_node_t *head;

    // A pointer to the tail of this linked list.
    pm_multi_target_state_node_t *tail;
} pm_multi_target_state_t;

/**
 * Push a new state node onto the multi target state.
 */
static void
pm_multi_target_state_push(pm_multi_target_state_t *state, INSN *topn, size_t stack_size)
{
    pm_multi_target_state_node_t *node = ALLOC(pm_multi_target_state_node_t);
    node->topn = topn;
    node->stack_index = state->stack_size + 1;
    node->stack_size = stack_size;
    node->position = state->position;
    node->next = NULL;

    if (state->head == NULL) {
        state->head = node;
        state->tail = node;
    }
    else {
        state->tail->next = node;
        state->tail = node;
    }

    state->stack_size += stack_size;
}

/**
 * Walk through a multi target state's linked list and update the topn
 * instructions that were inserted into the write sequence to make sure they can
 * correctly retrieve their parent expressions.
 */
static void
pm_multi_target_state_update(pm_multi_target_state_t *state)
{
    // If nothing was ever pushed onto the stack, then we don't need to do any
    // kind of updates.
    if (state->stack_size == 0) return;

    pm_multi_target_state_node_t *current = state->head;
    pm_multi_target_state_node_t *previous;

    while (current != NULL) {
        VALUE offset = INT2FIX(state->stack_size - current->stack_index + current->position);
        current->topn->operands[0] = offset;

        // stack_size will be > 1 in the case that we compiled an index target
        // and it had arguments. In this case, we use multiple topn instructions
        // to grab up all of the arguments as well, so those offsets need to be
        // updated as well.
        if (current->stack_size > 1) {
            INSN *insn = current->topn;

            for (size_t index = 1; index < current->stack_size; index += 1) {
                LINK_ELEMENT *element = get_next_insn(insn);
                RUBY_ASSERT(IS_INSN(element));

                insn = (INSN *) element;
                RUBY_ASSERT(insn->insn_id == BIN(topn));

                insn->operands[0] = offset;
            }
        }

        previous = current;
        current = current->next;

        free(previous);
    }
}

static size_t
pm_compile_multi_target_node(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const parents, LINK_ANCHOR *const writes, LINK_ANCHOR *const cleanup, pm_scope_node_t *scope_node, pm_multi_target_state_t *state);

/**
 * A target node represents an indirect write to a variable or a method call to
 * a method ending in =. Compiling one of these nodes requires three sequences:
 *
 * * The first is to compile retrieving the parent expression if there is one.
 *   This could be the object that owns a constant or the receiver of a method
 *   call.
 * * The second is to compile the writes to the targets. This could be writing
 *   to variables, or it could be performing method calls.
 * * The third is to compile any cleanup that needs to happen, i.e., popping the
 *   appropriate number of values off the stack.
 *
 * When there is a parent expression and this target is part of a multi write, a
 * topn instruction will be inserted into the write sequence. This is to move
 * the parent expression to the top of the stack so that it can be used as the
 * receiver of the method call or the owner of the constant. To facilitate this,
 * we return a pointer to the topn instruction that was used to be later
 * modified with the correct offset.
 *
 * These nodes can appear in a couple of places, but most commonly:
 *
 * * For loops - the index variable is a target node
 * * Rescue clauses - the exception reference variable is a target node
 * * Multi writes - the left hand side contains a list of target nodes
 *
 * For the comments with examples within this function, we'll use for loops as
 * the containing node.
 */
static void
pm_compile_target_node(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const parents, LINK_ANCHOR *const writes, LINK_ANCHOR *const cleanup, pm_scope_node_t *scope_node, pm_multi_target_state_t *state)
{
    int lineno = pm_node_line_number(scope_node->parser, node);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    switch (PM_NODE_TYPE(node)) {
      case PM_LOCAL_VARIABLE_TARGET_NODE: {
        // Local variable targets have no parent expression, so they only need
        // to compile the write.
        //
        //     for i in []; end
        //
        pm_local_variable_target_node_t *cast = (pm_local_variable_target_node_t *) node;
        pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, cast->name, cast->depth);

        ADD_SETLOCAL(writes, &dummy_line_node, index.index, index.level);
        break;
      }
      case PM_CLASS_VARIABLE_TARGET_NODE: {
        // Class variable targets have no parent expression, so they only need
        // to compile the write.
        //
        //     for @@i in []; end
        //
        pm_class_variable_target_node_t *cast = (pm_class_variable_target_node_t *) node;
        ID name = pm_constant_id_lookup(scope_node, cast->name);

        ADD_INSN2(writes, &dummy_line_node, setclassvariable, ID2SYM(name), get_cvar_ic_value(iseq, name));
        break;
      }
      case PM_CONSTANT_TARGET_NODE: {
        // Constant targets have no parent expression, so they only need to
        // compile the write.
        //
        //     for I in []; end
        //
        pm_constant_target_node_t *cast = (pm_constant_target_node_t *) node;
        ID name = pm_constant_id_lookup(scope_node, cast->name);

        ADD_INSN1(writes, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(writes, &dummy_line_node, setconstant, ID2SYM(name));
        break;
      }
      case PM_GLOBAL_VARIABLE_TARGET_NODE: {
        // Global variable targets have no parent expression, so they only need
        // to compile the write.
        //
        //     for $i in []; end
        //
        pm_global_variable_target_node_t *cast = (pm_global_variable_target_node_t *) node;
        ID name = pm_constant_id_lookup(scope_node, cast->name);

        ADD_INSN1(writes, &dummy_line_node, setglobal, ID2SYM(name));
        break;
      }
      case PM_INSTANCE_VARIABLE_TARGET_NODE: {
        // Instance variable targets have no parent expression, so they only
        // need to compile the write.
        //
        //     for @i in []; end
        //
        pm_instance_variable_target_node_t *cast = (pm_instance_variable_target_node_t *) node;
        ID name = pm_constant_id_lookup(scope_node, cast->name);

        ADD_INSN2(writes, &dummy_line_node, setinstancevariable, ID2SYM(name), get_ivar_ic_value(iseq, name));
        break;
      }
      case PM_CONSTANT_PATH_TARGET_NODE: {
        // Constant path targets have a parent expression that is the object
        // that owns the constant. This needs to be compiled first into the
        // parents sequence. If no parent is found, then it represents using the
        // unary :: operator to indicate a top-level constant. In that case we
        // need to push Object onto the stack.
        //
        //     for I::J in []; end
        //
        const pm_constant_path_target_node_t *cast = (const pm_constant_path_target_node_t *) node;
        ID name = pm_constant_id_lookup(scope_node, ((const pm_constant_read_node_t *) cast->child)->name);

        if (cast->parent != NULL) {
            pm_compile_node(iseq, cast->parent, parents, false, scope_node);
        }
        else {
            ADD_INSN1(parents, &dummy_line_node, putobject, rb_cObject);
        }

        if (state == NULL) {
            ADD_INSN(writes, &dummy_line_node, swap);
        }
        else {
            ADD_INSN1(writes, &dummy_line_node, topn, INT2FIX(1));
            pm_multi_target_state_push(state, (INSN *) LAST_ELEMENT(writes), 1);
        }

        ADD_INSN1(writes, &dummy_line_node, setconstant, ID2SYM(name));

        if (state != NULL) {
            ADD_INSN(cleanup, &dummy_line_node, pop);
        }

        break;
      }
      case PM_CALL_TARGET_NODE: {
        // Call targets have a parent expression that is the receiver of the
        // method being called. This needs to be compiled first into the parents
        // sequence. These nodes cannot have arguments, so the method call is
        // compiled with a single argument which represents the value being
        // written.
        //
        //     for i.j in []; end
        //
        const pm_call_target_node_t *cast = (const pm_call_target_node_t *) node;
        ID method_id = pm_constant_id_lookup(scope_node, cast->name);

        pm_compile_node(iseq, cast->receiver, parents, false, scope_node);

        if (state != NULL) {
            ADD_INSN1(writes, &dummy_line_node, topn, INT2FIX(1));
            pm_multi_target_state_push(state, (INSN *) LAST_ELEMENT(writes), 1);
            ADD_INSN(writes, &dummy_line_node, swap);
        }

        int flags = VM_CALL_ARGS_SIMPLE;
        if (PM_NODE_FLAG_P(cast, PM_CALL_NODE_FLAGS_IGNORE_VISIBILITY)) flags |= VM_CALL_FCALL;

        ADD_SEND_WITH_FLAG(writes, &dummy_line_node, method_id, INT2FIX(1), INT2FIX(flags));
        ADD_INSN(writes, &dummy_line_node, pop);

        if (state != NULL) {
            ADD_INSN(cleanup, &dummy_line_node, pop);
        }

        break;
      }
      case PM_INDEX_TARGET_NODE: {
        // Index targets have a parent expression that is the receiver of the
        // method being called and any additional arguments that are being
        // passed along with the value being written. The receiver and arguments
        // both need to be on the stack. Note that this is even more complicated
        // by the fact that these nodes can hold a block using the unary &
        // operator.
        //
        //     for i[:j] in []; end
        //
        const pm_index_target_node_t *cast = (const pm_index_target_node_t *) node;

        pm_compile_node(iseq, cast->receiver, parents, false, scope_node);

        int flags = 0;
        struct rb_callinfo_kwarg *kwargs = NULL;
        int argc = pm_setup_args(cast->arguments, cast->block, &flags, &kwargs, iseq, parents, scope_node, dummy_line_node);

        if (state != NULL) {
            ADD_INSN1(writes, &dummy_line_node, topn, INT2FIX(argc + 1));
            pm_multi_target_state_push(state, (INSN *) LAST_ELEMENT(writes), argc + 1);

            if (argc == 0) {
                ADD_INSN(writes, &dummy_line_node, swap);
            }
            else {
                for (int index = 0; index < argc; index++) {
                    ADD_INSN1(writes, &dummy_line_node, topn, INT2FIX(argc + 1));
                }
                ADD_INSN1(writes, &dummy_line_node, topn, INT2FIX(argc + 1));
            }
        }

        // The argc that we're going to pass to the send instruction is the
        // number of arguments + 1 for the value being written. If there's a
        // splat, then we need to insert newarray and concatarray instructions
        // after the arguments have been written.
        int ci_argc = argc + 1;
        if (flags & VM_CALL_ARGS_SPLAT) {
            ci_argc--;
            ADD_INSN1(writes, &dummy_line_node, newarray, INT2FIX(1));
            ADD_INSN(writes, &dummy_line_node, concatarray);
        }

        ADD_SEND_R(writes, &dummy_line_node, idASET, INT2NUM(ci_argc), NULL, INT2FIX(flags), kwargs);
        ADD_INSN(writes, &dummy_line_node, pop);

        if (state != NULL) {
            if (argc != 0) {
                ADD_INSN(writes, &dummy_line_node, pop);
            }

            for (int index = 0; index < argc + 1; index++) {
                ADD_INSN(cleanup, &dummy_line_node, pop);
            }
        }

        break;
      }
      case PM_MULTI_TARGET_NODE: {
        // Multi target nodes represent a set of writes to multiple variables.
        // The parent expressions are the combined set of the parent expressions
        // of its inner target nodes.
        //
        //     for i, j in []; end
        //
        if (state != NULL) state->position--;
        pm_compile_multi_target_node(iseq, node, parents, writes, cleanup, scope_node, state);
        if (state != NULL) state->position++;
        break;
      }
      default:
        rb_bug("Unexpected node type: %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
        break;
    }
}

/**
 * Compile a multi target or multi write node. It returns the number of values
 * on the stack that correspond to the parent expressions of the various
 * targets.
 */
static size_t
pm_compile_multi_target_node(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const parents, LINK_ANCHOR *const writes, LINK_ANCHOR *const cleanup, pm_scope_node_t *scope_node, pm_multi_target_state_t *state)
{
    int lineno = pm_node_line_number(scope_node->parser, node);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    const pm_node_list_t *lefts;
    const pm_node_t *rest;
    const pm_node_list_t *rights;

    switch (PM_NODE_TYPE(node)) {
      case PM_MULTI_TARGET_NODE: {
        pm_multi_target_node_t *cast = (pm_multi_target_node_t *) node;
        lefts = &cast->lefts;
        rest = cast->rest;
        rights = &cast->rights;
        break;
      }
      case PM_MULTI_WRITE_NODE: {
        pm_multi_write_node_t *cast = (pm_multi_write_node_t *) node;
        lefts = &cast->lefts;
        rest = cast->rest;
        rights = &cast->rights;
        break;
      }
      default:
        rb_bug("Unsupported node %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
        break;
    }

    bool has_rest = (rest != NULL) && PM_NODE_TYPE_P(rest, PM_SPLAT_NODE) && ((pm_splat_node_t *) rest)->expression != NULL;
    bool has_posts = rights->size > 0;

    // The first instruction in the writes sequence is going to spread the
    // top value of the stack onto the number of values that we're going to
    // write.
    ADD_INSN2(writes, &dummy_line_node, expandarray, INT2FIX(lefts->size), INT2FIX((has_rest || has_posts) ? 1 : 0));

    // We need to keep track of some additional state information as we're
    // going through the targets because we will need to revisit them once
    // we know how many values are being pushed onto the stack.
    pm_multi_target_state_t target_state = { 0 };
    size_t base_position = state == NULL ? 0 : state->position;
    size_t splat_position = has_rest ? 1 : 0;

    // Next, we'll iterate through all of the leading targets.
    for (size_t index = 0; index < lefts->size; index++) {
        const pm_node_t *target = lefts->nodes[index];
        target_state.position = lefts->size - index + splat_position + base_position;
        pm_compile_target_node(iseq, target, parents, writes, cleanup, scope_node, &target_state);
    }

    // Next, we'll compile the rest target if there is one.
    if (has_rest) {
        const pm_node_t *target = ((pm_splat_node_t *) rest)->expression;
        target_state.position = 1 + rights->size + base_position;

        if (has_posts) {
            ADD_INSN2(writes, &dummy_line_node, expandarray, INT2FIX(rights->size), INT2FIX(3));
        }

        pm_compile_target_node(iseq, target, parents, writes, cleanup, scope_node, &target_state);
    }

    // Finally, we'll compile the trailing targets.
    if (has_posts) {
        if (!has_rest && rest != NULL) {
            ADD_INSN2(writes, &dummy_line_node, expandarray, INT2FIX(rights->size), INT2FIX(2));
        }

        for (size_t index = 0; index < rights->size; index++) {
            const pm_node_t *target = rights->nodes[index];
            target_state.position = rights->size - index + base_position;
            pm_compile_target_node(iseq, target, parents, writes, cleanup, scope_node, &target_state);
        }
    }

    // Now, we need to go back and modify the topn instructions in order to
    // ensure they can correctly retrieve the parent expressions.
    pm_multi_target_state_update(&target_state);

    if (state != NULL) state->stack_size += target_state.stack_size;

    return target_state.stack_size;
}

/**
 * When compiling a for loop, we need to write the iteration variable to
 * whatever expression exists in the index slot. This function performs that
 * compilation.
 */
static void
pm_compile_for_node_index(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, pm_scope_node_t *scope_node)
{
    int lineno = pm_node_line_number(scope_node->parser, node);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    switch (PM_NODE_TYPE(node)) {
      case PM_LOCAL_VARIABLE_TARGET_NODE: {
        // For local variables, all we have to do is retrieve the value and then
        // compile the index node.
        ADD_GETLOCAL(ret, &dummy_line_node, 1, 0);
        pm_compile_target_node(iseq, node, ret, ret, ret, scope_node, NULL);
        break;
      }
      case PM_CLASS_VARIABLE_TARGET_NODE:
      case PM_CONSTANT_TARGET_NODE:
      case PM_GLOBAL_VARIABLE_TARGET_NODE:
      case PM_INSTANCE_VARIABLE_TARGET_NODE:
      case PM_CONSTANT_PATH_TARGET_NODE:
      case PM_CALL_TARGET_NODE:
      case PM_INDEX_TARGET_NODE: {
        // For other targets, we need to potentially compile the parent or
        // owning expression of this target, then retrieve the value, expand it,
        // and then compile the necessary writes.
        DECL_ANCHOR(writes);
        INIT_ANCHOR(writes);

        DECL_ANCHOR(cleanup);
        INIT_ANCHOR(cleanup);

        pm_multi_target_state_t state = { 0 };
        state.position = 1;
        pm_compile_target_node(iseq, node, ret, writes, cleanup, scope_node, &state);

        ADD_GETLOCAL(ret, &dummy_line_node, 1, 0);
        ADD_INSN2(ret, &dummy_line_node, expandarray, INT2FIX(1), INT2FIX(0));

        ADD_SEQ(ret, writes);
        ADD_SEQ(ret, cleanup);

        pm_multi_target_state_update(&state);
        break;
      }
      case PM_MULTI_TARGET_NODE: {
        DECL_ANCHOR(writes);
        INIT_ANCHOR(writes);

        DECL_ANCHOR(cleanup);
        INIT_ANCHOR(cleanup);

        pm_compile_target_node(iseq, node, ret, writes, cleanup, scope_node, NULL);

        LABEL *not_single = NEW_LABEL(lineno);
        LABEL *not_ary = NEW_LABEL(lineno);

        // When there are multiple targets, we'll do a bunch of work to convert
        // the value into an array before we expand it. Effectively we're trying
        // to accomplish:
        //
        //     (args.length == 1 && Array.try_convert(args[0])) || args
        //
        ADD_GETLOCAL(ret, &dummy_line_node, 1, 0);
        ADD_INSN(ret, &dummy_line_node, dup);
        ADD_CALL(ret, &dummy_line_node, idLength, INT2FIX(0));
        ADD_INSN1(ret, &dummy_line_node, putobject, INT2FIX(1));
        ADD_CALL(ret, &dummy_line_node, idEq, INT2FIX(1));
        ADD_INSNL(ret, &dummy_line_node, branchunless, not_single);
        ADD_INSN(ret, &dummy_line_node, dup);
        ADD_INSN1(ret, &dummy_line_node, putobject, INT2FIX(0));
        ADD_CALL(ret, &dummy_line_node, idAREF, INT2FIX(1));
        ADD_INSN1(ret, &dummy_line_node, putobject, rb_cArray);
        PM_SWAP;
        ADD_CALL(ret, &dummy_line_node, rb_intern("try_convert"), INT2FIX(1));
        ADD_INSN(ret, &dummy_line_node, dup);
        ADD_INSNL(ret, &dummy_line_node, branchunless, not_ary);
        PM_SWAP;

        ADD_LABEL(ret, not_ary);
        PM_POP;

        ADD_LABEL(ret, not_single);
        ADD_SEQ(ret, writes);
        ADD_SEQ(ret, cleanup);
        break;
      }
      default:
        rb_bug("Unexpected node type for index in for node: %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
        break;
    }
}

static void
pm_compile_rescue(rb_iseq_t *iseq, pm_begin_node_t *begin_node, LINK_ANCHOR *const ret, int lineno, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);
    const pm_parser_t *parser = scope_node->parser;
    LABEL *lstart = NEW_LABEL(lineno);
    LABEL *lend = NEW_LABEL(lineno);
    LABEL *lcont = NEW_LABEL(lineno);

    pm_scope_node_t rescue_scope_node;
    pm_scope_node_init((pm_node_t *) begin_node->rescue_clause, &rescue_scope_node, scope_node);

    rb_iseq_t *rescue_iseq = NEW_CHILD_ISEQ(
        &rescue_scope_node,
        rb_str_concat(rb_str_new2("rescue in "), ISEQ_BODY(iseq)->location.label),
        ISEQ_TYPE_RESCUE,
        pm_node_line_number(parser, (const pm_node_t *) begin_node->rescue_clause)
    );

    pm_scope_node_destroy(&rescue_scope_node);

    lstart->rescued = LABEL_RESCUE_BEG;
    lend->rescued = LABEL_RESCUE_END;
    ADD_LABEL(ret, lstart);
    bool prev_in_rescue = ISEQ_COMPILE_DATA(iseq)->in_rescue;
    ISEQ_COMPILE_DATA(iseq)->in_rescue = true;
    if (begin_node->statements) {
        PM_COMPILE_NOT_POPPED((pm_node_t *)begin_node->statements);
    }
    else {
        PM_PUTNIL;
    }
    ISEQ_COMPILE_DATA(iseq)->in_rescue = prev_in_rescue;

    ADD_LABEL(ret, lend);

    if (begin_node->else_clause) {
        PM_POP_UNLESS_POPPED;
        PM_COMPILE((pm_node_t *)begin_node->else_clause);
    }

    PM_NOP;
    ADD_LABEL(ret, lcont);

    PM_POP_IF_POPPED;
    ADD_CATCH_ENTRY(CATCH_TYPE_RESCUE, lstart, lend, rescue_iseq, lcont);
    ADD_CATCH_ENTRY(CATCH_TYPE_RETRY, lend, lcont, NULL, lstart);
}

static void
pm_compile_ensure(rb_iseq_t *iseq, pm_begin_node_t *begin_node, LINK_ANCHOR *const ret, int lineno, bool popped, pm_scope_node_t *scope_node)
{
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);
    const pm_parser_t *parser = scope_node->parser;

    LABEL *estart = NEW_LABEL(lineno);
    LABEL *eend = NEW_LABEL(lineno);
    LABEL *econt = NEW_LABEL(lineno);

    struct ensure_range er;
    struct iseq_compile_data_ensure_node_stack enl;
    struct ensure_range *erange;

    er.begin = estart;
    er.end = eend;
    er.next = 0;
    push_ensure_entry(iseq, &enl, &er, (void *)begin_node->ensure_clause);

    ADD_LABEL(ret, estart);
    if (begin_node->rescue_clause) {
        pm_compile_rescue(iseq, begin_node, ret, lineno, popped, scope_node);
    }
    else {
        if (begin_node->statements) {
            PM_COMPILE((pm_node_t *)begin_node->statements);
        }
        else {
            PM_PUTNIL_UNLESS_POPPED;
        }
    }

    ADD_LABEL(ret, eend);
    ADD_LABEL(ret, econt);

    pm_scope_node_t next_scope_node;
    pm_scope_node_init((pm_node_t *)begin_node->ensure_clause, &next_scope_node, scope_node);

    rb_iseq_t *child_iseq = NEW_CHILD_ISEQ(
        &next_scope_node,
        rb_str_concat(rb_str_new2("ensure in "), ISEQ_BODY(iseq)->location.label),
        ISEQ_TYPE_ENSURE,
        pm_node_line_number(parser, (const pm_node_t *) begin_node->ensure_clause)
    );

    pm_scope_node_destroy(&next_scope_node);

    ISEQ_COMPILE_DATA(iseq)->current_block = child_iseq;

    erange = ISEQ_COMPILE_DATA(iseq)->ensure_node_stack->erange;
    if (estart->link.next != &eend->link) {
        while (erange) {
            ADD_CATCH_ENTRY(CATCH_TYPE_ENSURE, erange->begin, erange->end, child_iseq, econt);
            erange = erange->next;
        }
    }
    ISEQ_COMPILE_DATA(iseq)->ensure_node_stack = enl.prev;

    // Compile the ensure entry
    pm_statements_node_t *statements = begin_node->ensure_clause->statements;
    if (statements) {
        PM_COMPILE((pm_node_t *)statements);
        PM_POP_UNLESS_POPPED;
    }
}

/**
 * Returns true if the given call node can use the opt_str_uminus or
 * opt_str_freeze instructions as an optimization with the current iseq options.
 */
static inline bool
pm_opt_str_freeze_p(const rb_iseq_t *iseq, const pm_call_node_t *node)
{
    return (
        !PM_NODE_FLAG_P(node, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION) &&
        node->receiver != NULL &&
        PM_NODE_TYPE_P(node->receiver, PM_STRING_NODE) &&
        node->arguments == NULL &&
        node->block == NULL &&
        ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction
    );
}

/**
 * Returns true if the given call node can use the opt_aref_with optimization
 * with the current iseq options.
 */
static inline bool
pm_opt_aref_with_p(const rb_iseq_t *iseq, const pm_call_node_t *node)
{
    return (
        !PM_NODE_FLAG_P(node, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION) &&
        node->arguments != NULL &&
        PM_NODE_TYPE_P((const pm_node_t *) node->arguments, PM_ARGUMENTS_NODE) &&
        ((const pm_arguments_node_t *) node->arguments)->arguments.size == 1 &&
        PM_NODE_TYPE_P(((const pm_arguments_node_t *) node->arguments)->arguments.nodes[0], PM_STRING_NODE) &&
        node->block == NULL &&
        !PM_NODE_FLAG_P(((const pm_arguments_node_t *) node->arguments)->arguments.nodes[0], PM_STRING_FLAGS_FROZEN) &&
        ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction
    );
}

/**
 * Returns true if the given call node can use the opt_aset_with optimization
 * with the current iseq options.
 */
static inline bool
pm_opt_aset_with_p(const rb_iseq_t *iseq, const pm_call_node_t *node)
{
    return (
        !PM_NODE_FLAG_P(node, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION) &&
        node->arguments != NULL &&
        PM_NODE_TYPE_P((const pm_node_t *) node->arguments, PM_ARGUMENTS_NODE) &&
        ((const pm_arguments_node_t *) node->arguments)->arguments.size == 2 &&
        PM_NODE_TYPE_P(((const pm_arguments_node_t *) node->arguments)->arguments.nodes[0], PM_STRING_NODE) &&
        node->block == NULL &&
        !PM_NODE_FLAG_P(((const pm_arguments_node_t *) node->arguments)->arguments.nodes[0], PM_STRING_FLAGS_FROZEN) &&
        ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction
    );
}

/**
 * Compile the instructions necessary to read a constant, based on the options
 * of the current iseq.
 */
static void
pm_compile_constant_read(rb_iseq_t *iseq, VALUE name, const pm_location_t *name_loc, LINK_ANCHOR *const ret, const pm_scope_node_t *scope_node)
{
    int lineno = pm_location_line_number(scope_node->parser, name_loc);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    if (ISEQ_COMPILE_DATA(iseq)->option->inline_const_cache) {
        ISEQ_BODY(iseq)->ic_size++;
        VALUE segments = rb_ary_new_from_args(1, name);
        ADD_INSN1(ret, &dummy_line_node, opt_getconstant_path, segments);
    }
    else {
        PM_PUTNIL;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, name);
    }
}

/**
 * Returns a Ruby array of the parts of the constant path node if it is constant
 * reads all of the way down. If it isn't, then Qnil is returned.
 */
static VALUE
pm_constant_path_parts(const pm_node_t *node, const pm_scope_node_t *scope_node)
{
    VALUE parts = rb_ary_new();

    while (true) {
        switch (PM_NODE_TYPE(node)) {
          case PM_CONSTANT_READ_NODE: {
            const pm_constant_read_node_t *cast = (const pm_constant_read_node_t *) node;
            VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, cast->name));

            rb_ary_unshift(parts, name);
            return parts;
          }
          case PM_CONSTANT_PATH_NODE: {
            const pm_constant_path_node_t *cast = (const pm_constant_path_node_t *) node;
            VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, ((const pm_constant_read_node_t *) cast->child)->name));

            rb_ary_unshift(parts, name);
            if (cast->parent == NULL) {
                rb_ary_unshift(parts, ID2SYM(idNULL));
                return parts;
            }

            node = cast->parent;
            break;
          }
          default:
            return Qnil;
        }
    }
}

/**
 * Compile a constant path into two sequences of instructions, one for the
 * owning expression if there is one (prefix) and one for the constant reads
 * (body).
 */
static void
pm_compile_constant_path(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const prefix, LINK_ANCHOR *const body, bool popped, pm_scope_node_t *scope_node)
{
    int lineno = pm_node_line_number(scope_node->parser, node);
    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    switch (PM_NODE_TYPE(node)) {
      case PM_CONSTANT_READ_NODE: {
        const pm_constant_read_node_t *cast = (const pm_constant_read_node_t *) node;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, cast->name));

        ADD_INSN1(body, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(body, &dummy_line_node, getconstant, name);
        break;
      }
      case PM_CONSTANT_PATH_NODE: {
        const pm_constant_path_node_t *cast = (const pm_constant_path_node_t *) node;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, ((const pm_constant_read_node_t *) cast->child)->name));

        if (cast->parent == NULL) {
            ADD_INSN(body, &dummy_line_node, pop);
            ADD_INSN1(body, &dummy_line_node, putobject, rb_cObject);
            ADD_INSN1(body, &dummy_line_node, putobject, Qtrue);
            ADD_INSN1(body, &dummy_line_node, getconstant, name);
        }
        else {
            pm_compile_constant_path(iseq, cast->parent, prefix, body, popped, scope_node);
            ADD_INSN1(body, &dummy_line_node, putobject, Qfalse);
            ADD_INSN1(body, &dummy_line_node, getconstant, name);
        }
        break;
      }
      default:
        PM_COMPILE_INTO_ANCHOR(prefix, node);
        break;
    }
}

/**
 * When we're compiling a case node, it's possible that we can speed it up using
 * a dispatch hash, which will allow us to jump directly to the correct when
 * clause body based on a hash lookup of the value. This can only happen when
 * the conditions are literals that can be compiled into a hash key.
 *
 * This function accepts a dispatch hash and the condition of a when clause. It
 * is responsible for compiling the condition into a hash key and then adding it
 * to the dispatch hash.
 *
 * If the value can be successfully compiled into the hash, then this function
 * returns the dispatch hash with the new key added. If the value cannot be
 * compiled into the hash, then this function returns Qundef. In the case of
 * Qundef, this function is signaling that the caller should abandon the
 * optimization entirely.
 */
static VALUE
pm_compile_case_node_dispatch(rb_iseq_t *iseq, VALUE dispatch, const pm_node_t *node, LABEL *label, const pm_scope_node_t *scope_node)
{
    VALUE key = Qundef;

    switch (PM_NODE_TYPE(node)) {
      case PM_FLOAT_NODE: {
        key = pm_static_literal_value(iseq, node, scope_node);
        double intptr;

        if (modf(RFLOAT_VALUE(key), &intptr) == 0.0) {
            key = (FIXABLE(intptr) ? LONG2FIX((long) intptr) : rb_dbl2big(intptr));
        }

        break;
      }
      case PM_FALSE_NODE:
      case PM_INTEGER_NODE:
      case PM_NIL_NODE:
      case PM_SOURCE_FILE_NODE:
      case PM_SOURCE_LINE_NODE:
      case PM_SYMBOL_NODE:
      case PM_TRUE_NODE:
        key = pm_static_literal_value(iseq, node, scope_node);
        break;
      case PM_STRING_NODE: {
        const pm_string_node_t *cast = (const pm_string_node_t *) node;
        key = rb_fstring(parse_string_encoded(scope_node, node, &cast->unescaped));
        break;
      }
      default:
        return Qundef;
    }

    if (NIL_P(rb_hash_lookup(dispatch, key))) {
        rb_hash_aset(dispatch, key, ((VALUE) label) | 1);
    }

    return dispatch;
}

/*
 * Compiles a prism node into instruction sequences.
 *
 * iseq -            The current instruction sequence object (used for locals)
 * node -            The prism node to compile
 * ret -             The linked list of instructions to append instructions onto
 * popped -          True if compiling something with no side effects, so instructions don't
 *                   need to be added
 * scope_node - Stores parser and local information
 */
static void
pm_compile_node(rb_iseq_t *iseq, const pm_node_t *node, LINK_ANCHOR *const ret, bool popped, pm_scope_node_t *scope_node)
{
    const pm_parser_t *parser = scope_node->parser;
    const pm_line_column_t location = pm_newline_list_line_column(&parser->newline_list, node->location.start, parser->start_line);
    int lineno = (int) location.line;

    if (PM_NODE_FLAG_P(node, PM_NODE_FLAG_NEWLINE) && ISEQ_COMPILE_DATA(iseq)->last_line != lineno) {
        int event = RUBY_EVENT_LINE;

        ISEQ_COMPILE_DATA(iseq)->last_line = lineno;
        if (ISEQ_COVERAGE(iseq) && ISEQ_LINE_COVERAGE(iseq)) {
            event |= RUBY_EVENT_COVERAGE_LINE;
        }
        PUSH_TRACE(ret, event);
    }

    NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

    switch (PM_NODE_TYPE(node)) {
      case PM_ALIAS_GLOBAL_VARIABLE_NODE: {
        // alias $foo $bar
        // ^^^^^^^^^^^^^^^
        const pm_alias_global_variable_node_t *cast = (const pm_alias_global_variable_node_t *) node;
        PUSH_INSN1(ret, location, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));

        const pm_location_t *new_name_loc = &cast->new_name->location;
        PUSH_INSN1(ret, location, putobject, ID2SYM(rb_intern3((const char *) new_name_loc->start, new_name_loc->end - new_name_loc->start, scope_node->encoding)));

        const pm_location_t *old_name_loc = &cast->old_name->location;
        PUSH_INSN1(ret, location, putobject, ID2SYM(rb_intern3((const char *) old_name_loc->start, old_name_loc->end - old_name_loc->start, scope_node->encoding)));

        PUSH_SEND(ret, location, id_core_set_variable_alias, INT2FIX(2));
        if (popped) PUSH_INSN(ret, location, pop);

        return;
      }
      case PM_ALIAS_METHOD_NODE: {
        // alias foo bar
        // ^^^^^^^^^^^^^
        const pm_alias_method_node_t *cast = (const pm_alias_method_node_t *) node;

        PUSH_INSN1(ret, location, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
        PUSH_INSN1(ret, location, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CBASE));
        PM_COMPILE_NOT_POPPED(cast->new_name);
        PM_COMPILE_NOT_POPPED(cast->old_name);

        PUSH_SEND(ret, location, id_core_set_method_alias, INT2FIX(3));
        if (popped) PUSH_INSN(ret, location, pop);

        return;
      }
      case PM_AND_NODE: {
        // a and b
        // ^^^^^^^
        const pm_and_node_t *cast = (const pm_and_node_t *) node;
        LABEL *end_label = NEW_LABEL(lineno);

        PM_COMPILE_NOT_POPPED(cast->left);
        if (!popped) PUSH_INSN(ret, location, dup);
        PUSH_INSNL(ret, location, branchunless, end_label);

        if (!popped) PUSH_INSN(ret, location, pop);
        PM_COMPILE(cast->right);
        PUSH_LABEL(ret, end_label);

        return;
      }
      case PM_ARGUMENTS_NODE:
        // These are ArgumentsNodes that are not compiled directly by their
        // parent call nodes, used in the cases of NextNodes, ReturnNodes, and
        // BreakNodes. They can create an array like ArrayNode.
      case PM_ARRAY_NODE: {
        const pm_node_list_t *elements;

        if (PM_NODE_TYPE(node) == PM_ARGUMENTS_NODE) {
            // break foo
            //       ^^^
            const pm_arguments_node_t *cast = (const pm_arguments_node_t *)node;
            elements = &cast->arguments;

            // If we are only returning a single element through one of the jump
            // nodes, then we will only compile that node directly.
            if (elements->size == 1) {
                PM_COMPILE(elements->nodes[0]);
                return;
            }
        }
        else {
            // [foo, bar, baz]
            // ^^^^^^^^^^^^^^^
            const pm_array_node_t *cast = (const pm_array_node_t *) node;
            elements = &cast->elements;
        }

        // If every node in the array is static, then we can compile the entire
        // array now instead of later.
        if (PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL)) {
            // We're only going to compile this node if it's not popped. If it
            // is popped, then we know we don't need to do anything since it's
            // statically known.
            if (!popped) {
                if (elements->size) {
                    VALUE value = pm_static_literal_value(iseq, node, scope_node);
                    PUSH_INSN1(ret, location, duparray, value);
                }
                else {
                    PUSH_INSN1(ret, location, newarray, INT2FIX(0));
                }
            }
        }
        else {
            // Here since we know there are possible side-effects inside the
            // array contents, we're going to build it entirely at runtime.
            // We'll do this by pushing all of the elements onto the stack and
            // then combining them with newarray.
            //
            // If this array is popped, then this serves only to ensure we enact
            // all side-effects (like method calls) that are contained within
            // the array contents.
            //
            // We treat all sequences of non-splat elements as their
            // own arrays, followed by a newarray, and then continually
            // concat the arrays with the SplatNode nodes.
            int new_array_size = 0;

            bool need_to_concat_array = false;
            bool has_kw_splat = false;

            for (size_t index = 0; index < elements->size; index++) {
                const pm_node_t *element = elements->nodes[index];

                if (PM_NODE_TYPE_P(element, PM_SPLAT_NODE)) {
                    const pm_splat_node_t *splat_element = (const pm_splat_node_t *) element;

                    // If we already have non-splat elements, we need to emit a
                    // newarray instruction.
                    if (new_array_size > 0) {
                        PUSH_INSN1(ret, location, newarray, INT2FIX(new_array_size));
                        new_array_size = 0;

                        // We don't want to emit a concat array in the case
                        // where we're seeing our first splat, and already have
                        // elements.
                        if (need_to_concat_array) PUSH_INSN(ret, location, concatarray);
                    }

                    if (splat_element->expression) {
                        PM_COMPILE_NOT_POPPED(splat_element->expression);
                    }
                    else {
                        pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, PM_CONSTANT_MULT, 0);
                        ADD_GETLOCAL(ret, &dummy_line_node, index.index, index.level);
                    }

                    if (index > 0) {
                        PUSH_INSN(ret, location, concatarray);
                    }
                    else {
                        // If this is the first element of the array then we
                        // need to splatarray the elements into the list.
                        PUSH_INSN1(ret, location, splatarray, Qtrue);
                    }

                    // Since we have now seen a splat and are concat-ing arrays,
                    // all subsequent splats will need to concat as well.
                    need_to_concat_array = true;
                }
                else if (PM_NODE_TYPE_P(element, PM_KEYWORD_HASH_NODE)) {
                    new_array_size++;
                    has_kw_splat = true;
                    pm_compile_hash_elements(&((const pm_keyword_hash_node_t *) element)->elements, lineno, iseq, ret, scope_node);
                }
                else {
                    new_array_size++;
                    PM_COMPILE_NOT_POPPED(element);
                }
            }

            if (new_array_size) {
                if (has_kw_splat) {
                    PUSH_INSN1(ret, location, newarraykwsplat, INT2FIX(new_array_size));
                }
                else {
                    PUSH_INSN1(ret, location, newarray, INT2FIX(new_array_size));
                }

                if (need_to_concat_array) PUSH_INSN(ret, location, concatarray);
            }

            if (popped) PUSH_INSN(ret, location, pop);
        }
        return;
      }
      case PM_ASSOC_NODE: {
        // { foo: 1 }
        //   ^^^^^^
        //
        // foo(bar: 1)
        //     ^^^^^^
        const pm_assoc_node_t *cast = (const pm_assoc_node_t *) node;

        PM_COMPILE(cast->key);
        PM_COMPILE(cast->value);

        return;
      }
      case PM_ASSOC_SPLAT_NODE: {
        // { **foo }
        //   ^^^^^
        //
        // def foo(**); bar(**); end
        //                  ^^
        const pm_assoc_splat_node_t *cast = (const pm_assoc_splat_node_t *) node;

        if (cast->value != NULL) {
            PM_COMPILE(cast->value);
        }
        else if (!popped) {
            pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, PM_CONSTANT_POW, 0);
            ADD_GETLOCAL(ret, &dummy_line_node, index.index, index.level);
        }

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

        if (begin_node->ensure_clause) {
            // Compiling the ensure clause will compile the rescue clause (if
            // there is one), which will compile the begin statements
            pm_compile_ensure(iseq, begin_node, ret, lineno, popped, scope_node);
        }
        else if (begin_node->rescue_clause) {
            // Compiling rescue will compile begin statements (if applicable)
            pm_compile_rescue(iseq, begin_node, ret, lineno, popped, scope_node);
        }
        else {
            // If there is neither ensure or rescue, the just compile statements
            if (begin_node->statements) {
                PM_COMPILE((pm_node_t *)begin_node->statements);
            }
            else {
                PM_PUTNIL_UNLESS_POPPED;
            }
        }
        return;
      }
      case PM_BLOCK_ARGUMENT_NODE: {
        pm_block_argument_node_t *cast = (pm_block_argument_node_t *) node;

        if (cast->expression) {
            PM_COMPILE(cast->expression);
        }
        else {
            // If there's no expression, this must be block forwarding.
            pm_local_index_t local_index = pm_lookup_local_index(iseq, scope_node, PM_CONSTANT_AND, 0);
            ADD_INSN2(ret, &dummy_line_node, getblockparamproxy, INT2FIX(local_index.index + VM_ENV_DATA_SIZE - 1), INT2FIX(local_index.level));
        }
        return;
      }
      case PM_BREAK_NODE: {
        pm_break_node_t *break_node = (pm_break_node_t *) node;
        unsigned long throw_flag = 0;
        if (ISEQ_COMPILE_DATA(iseq)->redo_label != 0 && can_add_ensure_iseq(iseq)) {
            /* while/until */
            LABEL *splabel = NEW_LABEL(0);
            ADD_LABEL(ret, splabel);
            ADD_ADJUST(ret, &dummy_line_node, ISEQ_COMPILE_DATA(iseq)->redo_label);
            if (break_node->arguments) {
                PM_COMPILE_NOT_POPPED((pm_node_t *)break_node->arguments);
            }
            else {
                PM_PUTNIL;
            }

            pm_add_ensure_iseq(ret, iseq, 0, scope_node);
            ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->end_label);
            ADD_ADJUST_RESTORE(ret, splabel);

            PM_PUTNIL_UNLESS_POPPED;
        }
        else {
            const rb_iseq_t *ip = iseq;

            while (ip) {
                if (!ISEQ_COMPILE_DATA(ip)) {
                    ip = 0;
                    break;
                }

                if (ISEQ_COMPILE_DATA(ip)->redo_label != 0) {
                    throw_flag = VM_THROW_NO_ESCAPE_FLAG;
                }
                else if (ISEQ_BODY(ip)->type == ISEQ_TYPE_BLOCK) {
                    throw_flag = 0;
                }
                else if (ISEQ_BODY(ip)->type == ISEQ_TYPE_EVAL) {
                    COMPILE_ERROR(ERROR_ARGS "Can't escape from eval with break");
                    return;
                }
                else {
                    ip = ISEQ_BODY(ip)->parent_iseq;
                    continue;
                }

                /* escape from block */
                if (break_node->arguments) {
                    PM_COMPILE_NOT_POPPED((pm_node_t *)break_node->arguments);
                }
                else {
                    PM_PUTNIL;
                }

                ADD_INSN1(ret, &dummy_line_node, throw, INT2FIX(throw_flag | TAG_BREAK));
                PM_POP_IF_POPPED;

                return;
            }
            COMPILE_ERROR(ERROR_ARGS "Invalid break");
            rb_bug("Invalid break");
        }
        return;
      }
      case PM_CALL_NODE: {
        const pm_call_node_t *call_node = (const pm_call_node_t *) node;
        LABEL *start = NEW_LABEL(lineno);

        if (call_node->block) {
            ADD_LABEL(ret, start);
        }

        ID method_id = pm_constant_id_lookup(scope_node, call_node->name);

        switch (method_id) {
          case idUMinus: {
            if (pm_opt_str_freeze_p(iseq, call_node)) {
                VALUE value = rb_fstring(parse_string_encoded(scope_node, call_node->receiver, &((const pm_string_node_t * )call_node->receiver)->unescaped));
                ADD_INSN2(ret, &dummy_line_node, opt_str_uminus, value, new_callinfo(iseq, idUMinus, 0, 0, NULL, FALSE));
                return;
            }
            break;
          }
          case idFreeze: {
            if (pm_opt_str_freeze_p(iseq, call_node)) {
                VALUE value = rb_fstring(parse_string_encoded(scope_node, call_node->receiver, &((const pm_string_node_t * )call_node->receiver)->unescaped));
                ADD_INSN2(ret, &dummy_line_node, opt_str_freeze, value, new_callinfo(iseq, idFreeze, 0, 0, NULL, FALSE));
                return;
            }
            break;
          }
          case idAREF: {
            if (pm_opt_aref_with_p(iseq, call_node)) {
                const pm_string_node_t *string = (const pm_string_node_t *) ((const pm_arguments_node_t *) call_node->arguments)->arguments.nodes[0];
                VALUE value = rb_fstring(parse_string_encoded(scope_node, (const pm_node_t *) string, &string->unescaped));

                PM_COMPILE_NOT_POPPED(call_node->receiver);
                ADD_INSN2(ret, &dummy_line_node, opt_aref_with, value, new_callinfo(iseq, idAREF, 1, 0, NULL, FALSE));

                if (popped) {
                    ADD_INSN(ret, &dummy_line_node, pop);
                }
                return;
            }
            break;
          }
          case idASET: {
            if (pm_opt_aset_with_p(iseq, call_node)) {
                const pm_string_node_t *string = (const pm_string_node_t *) ((const pm_arguments_node_t *) call_node->arguments)->arguments.nodes[0];
                VALUE value = rb_fstring(parse_string_encoded(scope_node, (const pm_node_t *) string, &string->unescaped));

                PM_COMPILE_NOT_POPPED(call_node->receiver);
                PM_COMPILE_NOT_POPPED(((const pm_arguments_node_t *) call_node->arguments)->arguments.nodes[1]);

                if (!popped) {
                    ADD_INSN(ret, &dummy_line_node, swap);
                    ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
                }

                ADD_INSN2(ret, &dummy_line_node, opt_aset_with, value, new_callinfo(iseq, idASET, 2, 0, NULL, FALSE));
                ADD_INSN(ret, &dummy_line_node, pop);
                return;
            }
            break;
          }
        }

        if (PM_NODE_FLAG_P(call_node, PM_CALL_NODE_FLAGS_ATTRIBUTE_WRITE) && !popped) {
            PM_PUTNIL;
        }

        if (call_node->receiver == NULL) {
            PM_PUTSELF;
        }
        else {
            PM_COMPILE_NOT_POPPED(call_node->receiver);
        }

        pm_compile_call(iseq, call_node, ret, popped, scope_node, method_id, start);
        return;
      }
      case PM_CALL_AND_WRITE_NODE: {
        pm_call_and_write_node_t *cast = (pm_call_and_write_node_t*) node;
        pm_compile_call_and_or_write_node(true, cast->receiver, cast->value, cast->write_name, cast->read_name, PM_NODE_FLAG_P(cast, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION), ret, iseq, lineno, popped, scope_node);
        return;
      }
      case PM_CALL_OR_WRITE_NODE: {
        pm_call_or_write_node_t *cast = (pm_call_or_write_node_t*) node;
        pm_compile_call_and_or_write_node(false, cast->receiver, cast->value, cast->write_name, cast->read_name, PM_NODE_FLAG_P(cast, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION), ret, iseq, lineno, popped, scope_node);
        return;
      }
      case PM_CALL_OPERATOR_WRITE_NODE: {
        // Call operator writes occur when you have a call node on the left-hand
        // side of a write operator that is not `=`. As an example,
        // `foo.bar *= 1`. This breaks down to caching the receiver on the
        // stack and then performing three method calls, one to read the value,
        // one to compute the result, and one to write the result back to the
        // receiver.
        const pm_call_operator_write_node_t *cast = (const pm_call_operator_write_node_t *) node;
        int flag = 0;

        if (PM_NODE_FLAG_P(cast, PM_CALL_NODE_FLAGS_IGNORE_VISIBILITY)) {
            flag = VM_CALL_FCALL;
        }

        PM_COMPILE_NOT_POPPED(cast->receiver);

        LABEL *safe_label = NULL;
        if (PM_NODE_FLAG_P(cast, PM_CALL_NODE_FLAGS_SAFE_NAVIGATION)) {
            safe_label = NEW_LABEL(lineno);
            PM_DUP;
            ADD_INSNL(ret, &dummy_line_node, branchnil, safe_label);
        }

        PM_DUP;

        ID id_read_name = pm_constant_id_lookup(scope_node, cast->read_name);
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, id_read_name, INT2FIX(0), INT2FIX(flag));

        PM_COMPILE_NOT_POPPED(cast->value);
        ID id_operator = pm_constant_id_lookup(scope_node, cast->operator);
        ADD_SEND(ret, &dummy_line_node, id_operator, INT2FIX(1));

        if (!popped) {
            PM_SWAP;
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
        }

        ID id_write_name = pm_constant_id_lookup(scope_node, cast->write_name);
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, id_write_name, INT2FIX(1), INT2FIX(flag));

        if (safe_label != NULL && popped) ADD_LABEL(ret, safe_label);
        PM_POP;
        if (safe_label != NULL && !popped) ADD_LABEL(ret, safe_label);

        return;
      }
      case PM_CASE_NODE: {
        // case foo; when bar; end
        // ^^^^^^^^^^^^^^^^^^^^^^^
        const pm_case_node_t *cast = (const pm_case_node_t *) node;
        const pm_node_list_t *conditions = &cast->conditions;

        // This is the anchor that we will compile the conditions of the various
        // `when` nodes into. If a match is found, they will need to jump into
        // the body_seq anchor to the correct spot.
        DECL_ANCHOR(cond_seq);
        INIT_ANCHOR(cond_seq);

        // This is the anchor that we will compile the bodies of the various
        // `when` nodes into. We'll make sure that the clauses that are compiled
        // jump into the correct spots within this anchor.
        DECL_ANCHOR(body_seq);
        INIT_ANCHOR(body_seq);

        // This is the label where all of the when clauses will jump to if they
        // have matched and are done executing their bodies.
        LABEL *end_label = NEW_LABEL(lineno);

        // If we have a predicate on this case statement, then it's going to
        // compare all of the various when clauses to the predicate. If we
        // don't, then it's basically an if-elsif-else chain.
        if (cast->predicate == NULL) {
            // Loop through each clauses in the case node and compile each of
            // the conditions within them into cond_seq. If they match, they
            // should jump into their respective bodies in body_seq.
            for (size_t clause_index = 0; clause_index < conditions->size; clause_index++) {
                const pm_when_node_t *clause = (const pm_when_node_t *) conditions->nodes[clause_index];
                const pm_node_list_t *conditions = &clause->conditions;

                int clause_lineno = pm_node_line_number(parser, (const pm_node_t *) clause);
                LABEL *label = NEW_LABEL(clause_lineno);

                ADD_LABEL(body_seq, label);
                if (clause->statements != NULL) {
                    pm_compile_node(iseq, (const pm_node_t *) clause->statements, body_seq, popped, scope_node);
                }
                else if (!popped) {
                    ADD_INSN(body_seq, &dummy_line_node, putnil);
                }

                ADD_INSNL(body_seq, &dummy_line_node, jump, end_label);

                // Compile each of the conditions for the when clause into the
                // cond_seq. Each one should have a unique condition and should
                // jump to the subsequent one if it doesn't match.
                for (size_t condition_index = 0; condition_index < conditions->size; condition_index++) {
                    const pm_node_t *condition = conditions->nodes[condition_index];

                    if (PM_NODE_TYPE_P(condition, PM_SPLAT_NODE)) {
                        ADD_INSN(cond_seq, &dummy_line_node, putnil);
                        pm_compile_node(iseq, condition, cond_seq, false, scope_node);
                        ADD_INSN1(cond_seq, &dummy_line_node, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_WHEN | VM_CHECKMATCH_ARRAY));
                        ADD_INSNL(cond_seq, &dummy_line_node, branchif, label);
                    }
                    else {
                        LABEL *next_label = NEW_LABEL(pm_node_line_number(parser, condition));
                        pm_compile_branch_condition(iseq, cond_seq, condition, label, next_label, false, scope_node);
                        ADD_LABEL(cond_seq, next_label);
                    }
                }
            }

            // Compile the consequent else clause if there is one.
            if (cast->consequent) {
                pm_compile_node(iseq, (const pm_node_t *) cast->consequent, cond_seq, popped, scope_node);
            }
            else if (!popped) {
                ADD_INSN(cond_seq, &dummy_line_node, putnil);
            }

            // Finally, jump to the end label if none of the other conditions
            // have matched.
            ADD_INSNL(cond_seq, &dummy_line_node, jump, end_label);
            ADD_SEQ(ret, cond_seq);
        }
        else {
            // This is the label where everything will fall into if none of the
            // conditions matched.
            LABEL *else_label = NEW_LABEL(lineno);

            // It's possible for us to speed up the case node by using a
            // dispatch hash. This is a hash that maps the conditions of the
            // various when clauses to the labels of their bodies. If we can
            // compile the conditions into a hash key, then we can use a hash
            // lookup to jump directly to the correct when clause body.
            VALUE dispatch = Qundef;
            if (ISEQ_COMPILE_DATA(iseq)->option->specialized_instruction) {
                dispatch = rb_hash_new();
                RHASH_TBL_RAW(dispatch)->type = &cdhash_type;
            }

            // We're going to loop through each of the conditions in the case
            // node and compile each of their contents into both the cond_seq
            // and the body_seq. Each condition will use its own label to jump
            // from its conditions into its body.
            //
            // Note that none of the code in the loop below should be adding
            // anything to ret, as we're going to be laying out the entire case
            // node instructions later.
            for (size_t clause_index = 0; clause_index < conditions->size; clause_index++) {
                const pm_when_node_t *clause = (const pm_when_node_t *) conditions->nodes[clause_index];
                const pm_node_list_t *conditions = &clause->conditions;

                LABEL *label = NEW_LABEL(lineno);

                // Compile each of the conditions for the when clause into the
                // cond_seq. Each one should have a unique comparison that then
                // jumps into the body if it matches.
                for (size_t condition_index = 0; condition_index < conditions->size; condition_index++) {
                    const pm_node_t *condition = conditions->nodes[condition_index];

                    // If we haven't already abandoned the optimization, then
                    // we're going to try to compile the condition into the
                    // dispatch hash.
                    if (dispatch != Qundef) {
                        dispatch = pm_compile_case_node_dispatch(iseq, dispatch, condition, label, scope_node);
                    }

                    if (PM_NODE_TYPE_P(condition, PM_SPLAT_NODE)) {
                        ADD_INSN(cond_seq, &dummy_line_node, dup);
                        pm_compile_node(iseq, condition, cond_seq, false, scope_node);
                        ADD_INSN1(cond_seq, &dummy_line_node, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_CASE | VM_CHECKMATCH_ARRAY));
                    }
                    else {
                        if (PM_NODE_TYPE_P(condition, PM_STRING_NODE)) {
                            const pm_string_node_t *string = (const pm_string_node_t *) condition;
                            VALUE value = rb_fstring(parse_string_encoded(scope_node, (const pm_node_t *) string, &string->unescaped));
                            ADD_INSN1(cond_seq, &dummy_line_node, putobject, value);
                        }
                        else {
                            pm_compile_node(iseq, condition, cond_seq, false, scope_node);
                        }

                        ADD_INSN1(cond_seq, &dummy_line_node, topn, INT2FIX(1));
                        ADD_SEND_WITH_FLAG(cond_seq, &dummy_line_node, idEqq, INT2NUM(1), INT2FIX(VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE));
                    }

                    ADD_INSNL(cond_seq, &dummy_line_node, branchif, label);
                }

                // Now, add the label to the body and compile the body of the
                // when clause. This involves popping the predicate, compiling
                // the statements to be executed, and then compiling a jump to
                // the end of the case node.
                ADD_LABEL(body_seq, label);
                ADD_INSN(body_seq, &dummy_line_node, pop);

                if (clause->statements != NULL) {
                    pm_compile_node(iseq, (const pm_node_t *) clause->statements, body_seq, popped, scope_node);
                }
                else if (!popped) {
                    ADD_INSN(body_seq, &dummy_line_node, putnil);
                }

                ADD_INSNL(body_seq, &dummy_line_node, jump, end_label);
            }

            // Now that we have compiled the conditions and the bodies of the
            // various when clauses, we can compile the predicate, lay out the
            // conditions, compile the fallback consequent if there is one, and
            // finally put in the bodies of the when clauses.
            PM_COMPILE_NOT_POPPED(cast->predicate);

            // If we have a dispatch hash, then we'll use it here to create the
            // optimization.
            if (dispatch != Qundef) {
                PM_DUP;
                ADD_INSN2(ret, &dummy_line_node, opt_case_dispatch, dispatch, else_label);
                LABEL_REF(else_label);
            }

            ADD_SEQ(ret, cond_seq);

            // Compile either the explicit else clause or an implicit else
            // clause.
            ADD_LABEL(ret, else_label);
            PM_POP;

            if (cast->consequent != NULL) {
                PM_COMPILE((const pm_node_t *) cast->consequent);
            }
            else if (!popped) {
                PM_PUTNIL;
            }

            ADD_INSNL(ret, &dummy_line_node, jump, end_label);
        }

        ADD_SEQ(ret, body_seq);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_CASE_MATCH_NODE: {
        // If you use the `case` keyword to create a case match node, it will
        // match against all of the `in` clauses until it finds one that
        // matches. If it doesn't find one, it can optionally fall back to an
        // `else` clause. If none is present and a match wasn't found, it will
        // raise an appropriate error.
        const pm_case_match_node_t *cast = (const pm_case_match_node_t *) node;

        // This is the anchor that we will compile the bodies of the various
        // `in` nodes into. We'll make sure that the patterns that are compiled
        // jump into the correct spots within this anchor.
        DECL_ANCHOR(body_seq);
        INIT_ANCHOR(body_seq);

        // This is the anchor that we will compile the patterns of the various
        // `in` nodes into. If a match is found, they will need to jump into the
        // body_seq anchor to the correct spot.
        DECL_ANCHOR(cond_seq);
        INIT_ANCHOR(cond_seq);

        // This label is used to indicate the end of the entire node. It is
        // jumped to after the entire stack is cleaned up.
        LABEL *end_label = NEW_LABEL(lineno);

        // This label is used as the fallback for the case match. If no match is
        // found, then we jump to this label. This is either an `else` clause or
        // an error handler.
        LABEL *else_label = NEW_LABEL(lineno);

        // We're going to use this to uniquely identify each branch so that we
        // can track coverage information.
        int branch_id = 0;
        // VALUE branches = 0;

        // If there is only one pattern, then the behavior changes a bit. It
        // effectively gets treated as a match required node (this is how it is
        // represented in the other parser).
        bool in_single_pattern = cast->consequent == NULL && cast->conditions.size == 1;

        // First, we're going to push a bunch of stuff onto the stack that is
        // going to serve as our scratch space.
        if (in_single_pattern) {
            ADD_INSN(ret, &dummy_line_node, putnil); // key error key
            ADD_INSN(ret, &dummy_line_node, putnil); // key error matchee
            ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse); // key error?
            ADD_INSN(ret, &dummy_line_node, putnil); // error string
        }

        // Now we're going to compile the value to match against.
        ADD_INSN(ret, &dummy_line_node, putnil); // deconstruct cache
        PM_COMPILE_NOT_POPPED(cast->predicate);

        // Next, we'll loop through every in clause and compile its body into
        // the body_seq anchor and its pattern into the cond_seq anchor. We'll
        // make sure the pattern knows how to jump correctly into the body if it
        // finds a match.
        for (size_t index = 0; index < cast->conditions.size; index++) {
            const pm_node_t *condition = cast->conditions.nodes[index];
            RUBY_ASSERT(PM_NODE_TYPE_P(condition, PM_IN_NODE));

            const pm_in_node_t *in_node = (const pm_in_node_t *) condition;

            pm_line_node_t in_line;
            pm_line_node(&in_line, scope_node, (const pm_node_t *) in_node);

            pm_line_node_t pattern_line;
            pm_line_node(&pattern_line, scope_node, (const pm_node_t *) in_node->pattern);

            if (branch_id) {
                ADD_INSN(body_seq, &in_line.node, putnil);
            }

            LABEL *body_label = NEW_LABEL(in_line.lineno);
            ADD_LABEL(body_seq, body_label);
            ADD_INSN1(body_seq, &in_line.node, adjuststack, INT2FIX(in_single_pattern ? 6 : 2));

            // TODO: We need to come back to this and enable trace branch
            // coverage. At the moment we can't call this function because it
            // accepts a NODE* and not a pm_node_t*.
            // add_trace_branch_coverage(iseq, body_seq, in_node->statements || in, branch_id++, "in", branches);

            branch_id++;
            if (in_node->statements != NULL) {
                PM_COMPILE_INTO_ANCHOR(body_seq, (const pm_node_t *) in_node->statements);
            }
            else if (!popped) {
                ADD_INSN(body_seq, &in_line.node, putnil);
            }

            ADD_INSNL(body_seq, &in_line.node, jump, end_label);
            LABEL *next_pattern_label = NEW_LABEL(pattern_line.lineno);

            ADD_INSN(cond_seq, &pattern_line.node, dup);
            pm_compile_pattern(iseq, scope_node, in_node->pattern, cond_seq, body_label, next_pattern_label, in_single_pattern, false, true, 2);
            ADD_LABEL(cond_seq, next_pattern_label);
            LABEL_UNREMOVABLE(next_pattern_label);
        }

        if (cast->consequent != NULL) {
            // If we have an `else` clause, then this becomes our fallback (and
            // there is no need to compile in code to potentially raise an
            // error).
            const pm_else_node_t *else_node = (const pm_else_node_t *) cast->consequent;

            ADD_LABEL(cond_seq, else_label);
            ADD_INSN(cond_seq, &dummy_line_node, pop);
            ADD_INSN(cond_seq, &dummy_line_node, pop);

            // TODO: trace branch coverage
            // add_trace_branch_coverage(iseq, cond_seq, cast->consequent, branch_id, "else", branches);

            if (else_node->statements != NULL) {
                PM_COMPILE_INTO_ANCHOR(cond_seq, (const pm_node_t *) else_node->statements);
            }
            else if (!popped) {
                ADD_INSN(cond_seq, &dummy_line_node, putnil);
            }

            ADD_INSNL(cond_seq, &dummy_line_node, jump, end_label);
            ADD_INSN(cond_seq, &dummy_line_node, putnil);
            if (popped) {
                ADD_INSN(cond_seq, &dummy_line_node, putnil);
            }
        }
        else {
            // Otherwise, if we do not have an `else` clause, we will compile in
            // the code to handle raising an appropriate error.
            ADD_LABEL(cond_seq, else_label);

            // TODO: trace branch coverage
            // add_trace_branch_coverage(iseq, cond_seq, orig_node, branch_id, "else", branches);

            if (in_single_pattern) {
                pm_compile_pattern_error_handler(iseq, scope_node, node, cond_seq, end_label, popped);
            }
            else {
                ADD_INSN1(cond_seq, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
                ADD_INSN1(cond_seq, &dummy_line_node, putobject, rb_eNoMatchingPatternError);
                ADD_INSN1(cond_seq, &dummy_line_node, topn, INT2FIX(2));
                ADD_SEND(cond_seq, &dummy_line_node, id_core_raise, INT2FIX(2));

                ADD_INSN1(cond_seq, &dummy_line_node, adjuststack, INT2FIX(3));
                if (!popped) ADD_INSN(cond_seq, &dummy_line_node, putnil);
                ADD_INSNL(cond_seq, &dummy_line_node, jump, end_label);
                ADD_INSN1(cond_seq, &dummy_line_node, dupn, INT2FIX(1));
                if (popped) ADD_INSN(cond_seq, &dummy_line_node, putnil);
            }
        }

        // At the end of all of this compilation, we will add the code for the
        // conditions first, then the various bodies, then mark the end of the
        // entire sequence with the end label.
        ADD_SEQ(ret, cond_seq);
        ADD_SEQ(ret, body_seq);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_CLASS_NODE: {
        pm_class_node_t *class_node = (pm_class_node_t *)node;

        ID class_id = pm_constant_id_lookup(scope_node, class_node->name);

        VALUE class_name = rb_str_freeze(rb_sprintf("<class:%"PRIsVALUE">", rb_id2str(class_id)));

        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *)class_node, &next_scope_node, scope_node);
        const rb_iseq_t *class_iseq = NEW_CHILD_ISEQ(&next_scope_node, class_name, ISEQ_TYPE_CLASS, lineno);
        pm_scope_node_destroy(&next_scope_node);

        // TODO: Once we merge constant path nodes correctly, fix this flag
        const int flags = VM_DEFINECLASS_TYPE_CLASS |
            (class_node->superclass ? VM_DEFINECLASS_FLAG_HAS_SUPERCLASS : 0) |
            pm_compile_class_path(ret, iseq, class_node->constant_path, &dummy_line_node, false, scope_node);

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
        LABEL *start_label = NEW_LABEL(lineno);

        ADD_INSN(ret, &dummy_line_node, putnil);
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CVAR),
                ID2SYM(pm_constant_id_lookup(scope_node, class_variable_or_write_node->name)), Qtrue);

        ADD_INSNL(ret, &dummy_line_node, branchunless, start_label);

        ID class_variable_name_id = pm_constant_id_lookup(scope_node, class_variable_or_write_node->name);
        VALUE class_variable_name_val = ID2SYM(class_variable_name_id);

        ADD_INSN2(ret, &dummy_line_node, getclassvariable,
                class_variable_name_val,
                get_cvar_ic_value(iseq, class_variable_name_id));

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

        PM_POP_UNLESS_POPPED;
        ADD_LABEL(ret, start_label);

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
      case PM_CLASS_VARIABLE_WRITE_NODE: {
        pm_class_variable_write_node_t *write_node = (pm_class_variable_write_node_t *) node;
        PM_COMPILE_NOT_POPPED(write_node->value);
        PM_DUP_UNLESS_POPPED;

        ID cvar_name = pm_constant_id_lookup(scope_node, write_node->name);
        ADD_INSN2(ret, &dummy_line_node, setclassvariable, ID2SYM(cvar_name), get_cvar_ic_value(iseq, cvar_name));
        return;
      }
      case PM_CONSTANT_PATH_NODE: {
        // Foo::Bar
        // ^^^^^^^^
        VALUE parts;

        if (ISEQ_COMPILE_DATA(iseq)->option->inline_const_cache && ((parts = pm_constant_path_parts(node, scope_node)) != Qnil)) {
            ISEQ_BODY(iseq)->ic_size++;
            ADD_INSN1(ret, &dummy_line_node, opt_getconstant_path, parts);
        }
        else {
            int lineno = pm_node_line_number(parser, node);
            NODE dummy_line_node = generate_dummy_line_node(lineno, lineno);

            DECL_ANCHOR(prefix);
            INIT_ANCHOR(prefix);

            DECL_ANCHOR(body);
            INIT_ANCHOR(body);

            pm_compile_constant_path(iseq, node, prefix, body, popped, scope_node);
            if (LIST_INSN_SIZE_ZERO(prefix)) {
                ADD_INSN(ret, &dummy_line_node, putnil);
            }
            else {
                ADD_SEQ(ret, prefix);
            }

            ADD_SEQ(ret, body);
        }

        PM_POP_IF_POPPED;
        return;
      }
      case PM_CONSTANT_PATH_AND_WRITE_NODE: {
        // Foo::Bar &&= baz
        // ^^^^^^^^^^^^^^^^
        const pm_constant_path_and_write_node_t *cast = (const pm_constant_path_and_write_node_t*) node;
        const pm_constant_path_node_t *target = cast->target;

        const pm_constant_read_node_t *child = (const pm_constant_read_node_t *) target->child;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, child->name));

        LABEL *lfin = NEW_LABEL(lineno);

        if (target->parent) {
            PM_COMPILE_NOT_POPPED(target->parent);
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }

        PM_DUP;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, name);

        PM_DUP_UNLESS_POPPED;
        ADD_INSNL(ret, &dummy_line_node, branchunless, lfin);

        PM_POP_UNLESS_POPPED;
        PM_COMPILE_NOT_POPPED(cast->value);

        if (popped) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, dupn, INT2FIX(2));
            PM_SWAP;
        }

        ADD_INSN1(ret, &dummy_line_node, setconstant, name);
        ADD_LABEL(ret, lfin);

        PM_SWAP_UNLESS_POPPED;
        PM_POP;

        return;
      }
      case PM_CONSTANT_PATH_OR_WRITE_NODE: {
        // Foo::Bar ||= baz
        // ^^^^^^^^^^^^^^^^
        const pm_constant_path_or_write_node_t *cast = (const pm_constant_path_or_write_node_t *) node;
        const pm_constant_path_node_t *target = cast->target;

        const pm_constant_read_node_t *child = (const pm_constant_read_node_t *) target->child;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, child->name));

        LABEL *lassign = NEW_LABEL(lineno);
        LABEL *lfin = NEW_LABEL(lineno);

        if (target->parent) {
            PM_COMPILE_NOT_POPPED(target->parent);
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }

        PM_DUP;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CONST_FROM), name, Qtrue);
        ADD_INSNL(ret, &dummy_line_node, branchunless, lassign);

        PM_DUP;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, name);

        PM_DUP_UNLESS_POPPED;
        ADD_INSNL(ret, &dummy_line_node, branchif, lfin);

        PM_POP_UNLESS_POPPED;
        ADD_LABEL(ret, lassign);
        PM_COMPILE_NOT_POPPED(cast->value);

        if (popped) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, dupn, INT2FIX(2));
            PM_SWAP;
        }

        ADD_INSN1(ret, &dummy_line_node, setconstant, name);
        ADD_LABEL(ret, lfin);

        PM_SWAP_UNLESS_POPPED;
        PM_POP;

        return;
      }
      case PM_CONSTANT_PATH_OPERATOR_WRITE_NODE: {
        // Foo::Bar += baz
        // ^^^^^^^^^^^^^^^
        const pm_constant_path_operator_write_node_t *cast = (const pm_constant_path_operator_write_node_t *) node;
        const pm_constant_path_node_t *target = cast->target;
        ID method_id = pm_constant_id_lookup(scope_node, cast->operator);

        const pm_constant_read_node_t *child = (const pm_constant_read_node_t *) target->child;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, child->name));

        if (target->parent) {
            PM_COMPILE_NOT_POPPED(target->parent);
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }

        PM_DUP;
        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSN1(ret, &dummy_line_node, getconstant, name);

        PM_COMPILE_NOT_POPPED(cast->value);
        ADD_CALL(ret, &dummy_line_node, method_id, INT2FIX(1));
        PM_SWAP;

        if (!popped) {
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
            PM_SWAP;
        }

        ADD_INSN1(ret, &dummy_line_node, setconstant, name);
        return;
      }
      case PM_CONSTANT_PATH_WRITE_NODE: {
        // Foo::Bar = 1
        // ^^^^^^^^^^^^
        const pm_constant_path_write_node_t *cast = (const pm_constant_path_write_node_t *) node;
        const pm_constant_path_node_t *target = cast->target;

        const pm_constant_read_node_t *child = (const pm_constant_read_node_t *) target->child;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, child->name));

        if (target->parent) {
            PM_COMPILE_NOT_POPPED((pm_node_t *) target->parent);
        }
        else {
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_cObject);
        }

        PM_COMPILE_NOT_POPPED(cast->value);

        if (!popped) {
            PM_SWAP;
            ADD_INSN1(ret, &dummy_line_node, topn, INT2FIX(1));
        }

        PM_SWAP;
        ADD_INSN1(ret, &dummy_line_node, setconstant, name);
        return;
      }
      case PM_CONSTANT_READ_NODE: {
        // Foo
        // ^^^
        const pm_constant_read_node_t *cast = (const pm_constant_read_node_t *) node;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, cast->name));

        pm_compile_constant_read(iseq, name, &cast->base.location, ret, scope_node);

        PM_POP_IF_POPPED;
        return;
      }
      case PM_CONSTANT_AND_WRITE_NODE: {
        // Foo &&= bar
        // ^^^^^^^^^^^
        const pm_constant_and_write_node_t *cast = (const pm_constant_and_write_node_t *) node;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, cast->name));
        LABEL *end_label = NEW_LABEL(lineno);

        pm_compile_constant_read(iseq, name, &cast->name_loc, ret, scope_node);

        PM_DUP_UNLESS_POPPED;
        ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);
        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(cast->value);
        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, name);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_CONSTANT_OR_WRITE_NODE: {
        // Foo ||= bar
        // ^^^^^^^^^^^
        const pm_constant_or_write_node_t *cast = (const pm_constant_or_write_node_t *) node;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, cast->name));
        LABEL *set_label = NEW_LABEL(lineno);
        LABEL *end_label = NEW_LABEL(lineno);

        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defined, INT2FIX(DEFINED_CONST), name, Qtrue);
        ADD_INSNL(ret, &dummy_line_node, branchunless, set_label);

        pm_compile_constant_read(iseq, name, &cast->name_loc, ret, scope_node);

        PM_DUP_UNLESS_POPPED;
        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);
        PM_POP_UNLESS_POPPED;

        ADD_LABEL(ret, set_label);
        PM_COMPILE_NOT_POPPED(cast->value);

        PM_DUP_UNLESS_POPPED;
        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, name);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_CONSTANT_OPERATOR_WRITE_NODE: {
        // Foo += bar
        // ^^^^^^^^^^
        const pm_constant_operator_write_node_t *cast = (const pm_constant_operator_write_node_t *) node;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, cast->name));
        ID method_id = pm_constant_id_lookup(scope_node, cast->operator);

        pm_compile_constant_read(iseq, name, &cast->name_loc, ret, scope_node);

        PM_COMPILE_NOT_POPPED(cast->value);
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(VM_CALL_ARGS_SIMPLE));
        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, name);

        return;
      }
      case PM_CONSTANT_WRITE_NODE: {
        // Foo = 1
        // ^^^^^^^
        const pm_constant_write_node_t *cast = (const pm_constant_write_node_t *) node;
        VALUE name = ID2SYM(pm_constant_id_lookup(scope_node, cast->name));

        PM_COMPILE_NOT_POPPED(cast->value);
        PM_DUP_UNLESS_POPPED;

        ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CONST_BASE));
        ADD_INSN1(ret, &dummy_line_node, setconstant, name);

        return;
      }
      case PM_DEF_NODE: {
        pm_def_node_t *def_node = (pm_def_node_t *) node;
        ID method_name = pm_constant_id_lookup(scope_node, def_node->name);

        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *)def_node, &next_scope_node, scope_node);
        rb_iseq_t *method_iseq = NEW_ISEQ(&next_scope_node, rb_id2str(method_name), ISEQ_TYPE_METHOD, lineno);
        pm_scope_node_destroy(&next_scope_node);

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
        pm_compile_defined_expr(iseq, defined_node->value, ret, popped, scope_node, dummy_line_node, lineno, false);
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
      case PM_ENSURE_NODE: {
        pm_ensure_node_t *ensure_node = (pm_ensure_node_t *)node;

        LABEL *start = NEW_LABEL(lineno);
        LABEL *end = NEW_LABEL(lineno);
        ADD_LABEL(ret, start);
        if (ensure_node->statements) {
            LABEL *prev_end_label = ISEQ_COMPILE_DATA(iseq)->end_label;
            ISEQ_COMPILE_DATA(iseq)->end_label = end;
            PM_COMPILE((pm_node_t *)ensure_node->statements);
            ISEQ_COMPILE_DATA(iseq)->end_label = prev_end_label;
        }
        ADD_LABEL(ret, end);
        return;
      }
      case PM_ELSE_NODE: {
          pm_else_node_t *cast = (pm_else_node_t *)node;
          if (cast->statements) {
              PM_COMPILE((pm_node_t *)cast->statements);
          }
          else {
              PM_PUTNIL_UNLESS_POPPED;
          }
          return;
      }
      case PM_FLIP_FLOP_NODE: {
        pm_flip_flop_node_t *flip_flop_node = (pm_flip_flop_node_t *)node;

        LABEL *final_label = NEW_LABEL(lineno);
        LABEL *then_label = NEW_LABEL(lineno);
        LABEL *else_label = NEW_LABEL(lineno);

        pm_compile_flip_flop(flip_flop_node, else_label, then_label, iseq, lineno, ret, popped, scope_node);

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
            ADD_INSN1(ret, &dummy_line_node, putobject, parse_float((const pm_float_node_t *) node));
        }
        return;
      }
      case PM_FOR_NODE: {
        pm_for_node_t *cast = (pm_for_node_t *) node;

        LABEL *retry_label = NEW_LABEL(lineno);
        LABEL *retry_end_l = NEW_LABEL(lineno);

        // First, compile the collection that we're going to be iterating over.
        ADD_LABEL(ret, retry_label);
        PM_COMPILE_NOT_POPPED(cast->collection);

        // Next, create the new scope that is going to contain the block that
        // will be passed to the each method.
        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *) cast, &next_scope_node, scope_node);

        const rb_iseq_t *child_iseq = NEW_CHILD_ISEQ(&next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
        pm_scope_node_destroy(&next_scope_node);

        const rb_iseq_t *prev_block = ISEQ_COMPILE_DATA(iseq)->current_block;
        ISEQ_COMPILE_DATA(iseq)->current_block = child_iseq;

        // Now, create the method call to each that will be used to iterate over
        // the collection, and pass the newly created iseq as the block.
        ADD_SEND_WITH_BLOCK(ret, &dummy_line_node, idEach, INT2FIX(0), child_iseq);

        // We need to put the label "retry_end_l" immediately after the last
        // "send" instruction. This because vm_throw checks if the break cont is
        // equal to the index of next insn of the "send". (Otherwise, it is
        // considered "break from proc-closure". See "TAG_BREAK" handling in
        // "vm_throw_start".)
        //
        // Normally, "send" instruction is at the last. However, qcall under
        // branch coverage measurement adds some instructions after the "send".
        //
        // Note that "invokesuper" appears instead of "send".
        {
            INSN *iobj;
            LINK_ELEMENT *last_elem = LAST_ELEMENT(ret);
            iobj = IS_INSN(last_elem) ? (INSN*) last_elem : (INSN*) get_prev_insn((INSN*) last_elem);
            while (INSN_OF(iobj) != BIN(send) && INSN_OF(iobj) != BIN(invokesuper)) {
                iobj = (INSN*) get_prev_insn(iobj);
            }
            ELEM_INSERT_NEXT(&iobj->link, (LINK_ELEMENT*) retry_end_l);

            // LINK_ANCHOR has a pointer to the last element, but
            // ELEM_INSERT_NEXT does not update it even if we add an insn to the
            // last of LINK_ANCHOR. So this updates it manually.
            if (&iobj->link == LAST_ELEMENT(ret)) {
                ret->last = (LINK_ELEMENT*) retry_end_l;
            }
        }

        PM_POP_IF_POPPED;
        ISEQ_COMPILE_DATA(iseq)->current_block = prev_block;
        ADD_CATCH_ENTRY(CATCH_TYPE_BREAK, retry_label, retry_end_l, child_iseq, retry_end_l);
        return;
      }
      case PM_FORWARDING_ARGUMENTS_NODE: {
        rb_bug("Cannot compile a ForwardingArgumentsNode directly\n");
        return;
      }
      case PM_FORWARDING_SUPER_NODE: {
        pm_forwarding_super_node_t *forwarding_super_node = (pm_forwarding_super_node_t *) node;
        const rb_iseq_t *block = NULL;
        PM_PUTSELF;
        int flag = VM_CALL_ZSUPER | VM_CALL_SUPER | VM_CALL_FCALL;

        if (forwarding_super_node->block) {
            pm_scope_node_t next_scope_node;
            pm_scope_node_init((pm_node_t *)forwarding_super_node->block, &next_scope_node, scope_node);
            block = NEW_CHILD_ISEQ(&next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
            pm_scope_node_destroy(&next_scope_node);

            RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)block);
        }

        DECL_ANCHOR(args);
        INIT_ANCHOR(args);

        struct rb_iseq_constant_body *const body = ISEQ_BODY(iseq);

        const rb_iseq_t *local_iseq = body->local_iseq;
        const struct rb_iseq_constant_body *const local_body = ISEQ_BODY(local_iseq);

        int argc = 0;
        int depth = get_lvar_level(iseq);

        if (local_body->param.flags.has_lead) {
            /* required arguments */
            for (int i = 0; i < local_body->param.lead_num; i++) {
                int idx = local_body->local_table_size - i;
                ADD_GETLOCAL(args, &dummy_line_node, idx, depth);
            }
            argc += local_body->param.lead_num;
        }

        if (local_body->param.flags.has_opt) {
            /* optional arguments */
            for (int j = 0; j < local_body->param.opt_num; j++) {
                int idx = local_body->local_table_size - (argc + j);
                ADD_GETLOCAL(args, &dummy_line_node, idx, depth);
            }
            argc += local_body->param.opt_num;
        }

        if (local_body->param.flags.has_rest) {
            /* rest argument */
            int idx = local_body->local_table_size - local_body->param.rest_start;
            ADD_GETLOCAL(args, &dummy_line_node, idx, depth);
            ADD_INSN1(args, &dummy_line_node, splatarray, Qfalse);

            argc = local_body->param.rest_start + 1;
            flag |= VM_CALL_ARGS_SPLAT;
        }

        if (local_body->param.flags.has_post) {
            /* post arguments */
            int post_len = local_body->param.post_num;
            int post_start = local_body->param.post_start;

            int j = 0;
            for (; j < post_len; j++) {
                int idx = local_body->local_table_size - (post_start + j);
                ADD_GETLOCAL(args, &dummy_line_node, idx, depth);
            }

            if (local_body->param.flags.has_rest) {
                // argc remains unchanged from rest branch
                ADD_INSN1(args, &dummy_line_node, newarray, INT2FIX(j));
                ADD_INSN (args, &dummy_line_node, concatarray);
            }
            else {
                argc = post_len + post_start;
            }
        }

        const struct rb_iseq_param_keyword *const local_keyword = local_body->param.keyword;
        if (local_body->param.flags.has_kw) {
            int local_size = local_body->local_table_size;
            argc++;

            ADD_INSN1(args, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));

            if (local_body->param.flags.has_kwrest) {
                int idx = local_body->local_table_size - local_keyword->rest_start;
                ADD_GETLOCAL(args, &dummy_line_node, idx, depth);
                RUBY_ASSERT(local_keyword->num > 0);
                ADD_SEND(args, &dummy_line_node, rb_intern("dup"), INT2FIX(0));
            }
            else {
                ADD_INSN1(args, &dummy_line_node, newhash, INT2FIX(0));
            }
            int i = 0;
            for (; i < local_keyword->num; ++i) {
                ID id = local_keyword->table[i];
                int idx = local_size - get_local_var_idx(local_iseq, id);
                ADD_INSN1(args, &dummy_line_node, putobject, ID2SYM(id));
                ADD_GETLOCAL(args, &dummy_line_node, idx, depth);
            }
            ADD_SEND(args, &dummy_line_node, id_core_hash_merge_ptr, INT2FIX(i * 2 + 1));
            flag |= VM_CALL_KW_SPLAT| VM_CALL_KW_SPLAT_MUT;
        }
        else if (local_body->param.flags.has_kwrest) {
            int idx = local_body->local_table_size - local_keyword->rest_start;
            ADD_GETLOCAL(args, &dummy_line_node, idx, depth);
            argc++;
            flag |= VM_CALL_KW_SPLAT;
        }

        ADD_SEQ(ret, args);
        ADD_INSN2(ret, &dummy_line_node, invokesuper, new_callinfo(iseq, 0, argc, flag, NULL, block != NULL), block);
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
        if (PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL)) {
            // We're only going to compile this node if it's not popped. If it
            // is popped, then we know we don't need to do anything since it's
            // statically known.
            if (!popped) {
                VALUE value = pm_static_literal_value(iseq, node, scope_node);
                ADD_INSN1(ret, &dummy_line_node, duphash, value);
                RB_OBJ_WRITTEN(iseq, Qundef, value);
            }
        }
        else {
            // Here since we know there are possible side-effects inside the
            // hash contents, we're going to build it entirely at runtime. We'll
            // do this by pushing all of the key-value pairs onto the stack and
            // then combining them with newhash.
            //
            // If this hash is popped, then this serves only to ensure we enact
            // all side-effects (like method calls) that are contained within
            // the hash contents.
            const pm_hash_node_t *cast = (const pm_hash_node_t *) node;
            const pm_node_list_t *elements = &cast->elements;

            if (popped) {
                // If this hash is popped, then we can iterate through each
                // element and compile it. The result of each compilation will
                // only include the side effects of the element itself.
                for (size_t index = 0; index < elements->size; index++) {
                    PM_COMPILE_POPPED(elements->nodes[index]);
                }
            }
            else {
                pm_compile_hash_elements(elements, lineno, iseq, ret, scope_node);
            }
        }

        return;
      }
      case PM_IF_NODE: {
        // if foo then bar end
        // ^^^^^^^^^^^^^^^^^^^
        //
        // bar if foo
        // ^^^^^^^^^^
        //
        // foo ? bar : baz
        // ^^^^^^^^^^^^^^^
        const pm_if_node_t *cast = (const pm_if_node_t *) node;
        pm_compile_conditional(iseq, &location, cast->statements, cast->consequent, cast->predicate, ret, popped, scope_node);
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
      case PM_IN_NODE: {
        // In nodes are handled by the case match node directly, so we should
        // never end up hitting them through this path.
        rb_bug("Should not ever enter an in node directly");
        return;
      }
      case PM_INDEX_OPERATOR_WRITE_NODE:
        pm_compile_index_operator_write_node(scope_node, (const pm_index_operator_write_node_t *) node, iseq, ret, popped);
        return;
      case PM_INDEX_AND_WRITE_NODE: {
        const pm_index_and_write_node_t *cast = (const pm_index_and_write_node_t *) node;
        pm_compile_index_control_flow_write_node(scope_node, node, cast->receiver, cast->arguments, cast->block, cast->value, iseq, ret, popped);
        return;
      }
      case PM_INDEX_OR_WRITE_NODE: {
        const pm_index_or_write_node_t *cast = (const pm_index_or_write_node_t *) node;
        pm_compile_index_control_flow_write_node(scope_node, node, cast->receiver, cast->arguments, cast->block, cast->value, iseq, ret, popped);
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
            ADD_INSN1(ret, &dummy_line_node, putobject, parse_integer((const pm_integer_node_t *) node));
        }
        return;
      }
      case PM_INTERPOLATED_MATCH_LAST_LINE_NODE: {
        // if /foo #{bar}/ then end
        //    ^^^^^^^^^^^^
        if (PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL)) {
            if (!popped) {
                VALUE regexp = pm_static_literal_value(iseq, node, scope_node);
                PUSH_INSN1(ret, location, putobject, regexp);
            }
        }
        else {
            pm_compile_regexp_dynamic(iseq, node, &((const pm_interpolated_match_last_line_node_t *) node)->parts, &location, ret, popped, scope_node);
        }

        PUSH_INSN1(ret, location, getglobal, rb_id2sym(idLASTLINE));
        PUSH_SEND(ret, location, idEqTilde, INT2NUM(1));
        if (popped) PUSH_INSN(ret, location, pop);

        return;
      }
      case PM_INTERPOLATED_REGULAR_EXPRESSION_NODE: {
        // /foo #{bar}/
        // ^^^^^^^^^^^^
        if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_ONCE)) {
            const rb_iseq_t *prevblock = ISEQ_COMPILE_DATA(iseq)->current_block;
            const rb_iseq_t *block_iseq = NULL;
            int ise_index = ISEQ_BODY(iseq)->ise_size++;

            pm_scope_node_t next_scope_node;
            pm_scope_node_init(node, &next_scope_node, scope_node);

            block_iseq = NEW_CHILD_ISEQ(&next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, location.line);
            pm_scope_node_destroy(&next_scope_node);

            ISEQ_COMPILE_DATA(iseq)->current_block = block_iseq;
            PUSH_INSN2(ret, location, once, block_iseq, INT2FIX(ise_index));
            ISEQ_COMPILE_DATA(iseq)->current_block = prevblock;

            if (popped) PUSH_INSN(ret, location, pop);
            return;
        }

        if (PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL)) {
            if (!popped) {
                VALUE regexp = pm_static_literal_value(iseq, node, scope_node);
                PUSH_INSN1(ret, location, putobject, regexp);
            }
        }
        else {
            pm_compile_regexp_dynamic(iseq, node, &((const pm_interpolated_regular_expression_node_t *) node)->parts, &location, ret, popped, scope_node);
            if (popped) PUSH_INSN(ret, location, pop);
        }

        return;
      }
      case PM_INTERPOLATED_STRING_NODE: {
        // "foo #{bar}"
        // ^^^^^^^^^^^^
        if (PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL)) {
            if (!popped) {
                VALUE string = pm_static_literal_value(iseq, node, scope_node);

                if (PM_NODE_FLAG_P(node, PM_INTERPOLATED_STRING_NODE_FLAGS_FROZEN)) {
                    PUSH_INSN1(ret, location, putobject, string);
                }
                else if (PM_NODE_FLAG_P(node, PM_INTERPOLATED_STRING_NODE_FLAGS_MUTABLE)) {
                    PUSH_INSN1(ret, location, putstring, string);
                }
                else {
                    PUSH_INSN1(ret, location, putchilledstring, string);
                }
            }
        }
        else {
            const pm_interpolated_string_node_t *cast = (const pm_interpolated_string_node_t *) node;
            int length = pm_interpolated_node_compile(&cast->parts, iseq, dummy_line_node, ret, popped, scope_node);

            if (length > 1) PUSH_INSN1(ret, location, concatstrings, INT2FIX(length));
            if (popped) PUSH_INSN(ret, location, pop);
        }

        return;
      }
      case PM_INTERPOLATED_SYMBOL_NODE: {
        // :"foo #{bar}"
        // ^^^^^^^^^^^^^
        const pm_interpolated_symbol_node_t *cast = (const pm_interpolated_symbol_node_t *) node;
        int length;

        if (PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL)) {
            if (!popped) {
                VALUE symbol = pm_static_literal_value(iseq, node, scope_node);
                PUSH_INSN1(ret, location, putobject, symbol);
            }
        }
        else {
            if ((length = pm_interpolated_node_compile(&cast->parts, iseq, dummy_line_node, ret, popped, scope_node)) > 1) {
                PUSH_INSN1(ret, location, concatstrings, INT2FIX(length));
            }

            if (!popped) {
                PUSH_INSN(ret, location, intern);
            }
            else {
                PUSH_INSN(ret, location, pop);
            }
        }

        return;
      }
      case PM_INTERPOLATED_X_STRING_NODE: {
        pm_interpolated_x_string_node_t *interp_x_string_node = (pm_interpolated_x_string_node_t *) node;
        PM_PUTSELF;
        int number_of_items_pushed = pm_interpolated_node_compile(&interp_x_string_node->parts, iseq, dummy_line_node, ret, false, scope_node);

        if (number_of_items_pushed > 1) {
            ADD_INSN1(ret, &dummy_line_node, concatstrings, INT2FIX(number_of_items_pushed));
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
        const pm_lambda_node_t *cast = (const pm_lambda_node_t *) node;

        pm_scope_node_t next_scope_node;
        pm_scope_node_init(node, &next_scope_node, scope_node);

        int opening_lineno = pm_location_line_number(parser, &cast->opening_loc);
        const rb_iseq_t *block = NEW_CHILD_ISEQ(&next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, opening_lineno);
        pm_scope_node_destroy(&next_scope_node);

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
        pm_local_index_t local_index = pm_lookup_local_index(iseq, scope_node, constant_id, local_variable_and_write_node->depth);
        ADD_GETLOCAL(ret, &dummy_line_node, local_index.index, local_index.level);

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchunless, end_label);

        PM_POP_UNLESS_POPPED;

        PM_COMPILE_NOT_POPPED(local_variable_and_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_SETLOCAL(ret, &dummy_line_node, local_index.index, local_index.level);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_LOCAL_VARIABLE_OPERATOR_WRITE_NODE: {
        pm_local_variable_operator_write_node_t *local_variable_operator_write_node = (pm_local_variable_operator_write_node_t*) node;

        pm_constant_id_t constant_id = local_variable_operator_write_node->name;
        pm_local_index_t local_index = pm_lookup_local_index(iseq, scope_node, constant_id, local_variable_operator_write_node->depth);

        ADD_GETLOCAL(ret, &dummy_line_node, local_index.index, local_index.level);

        PM_COMPILE_NOT_POPPED(local_variable_operator_write_node->value);
        ID method_id = pm_constant_id_lookup(scope_node, local_variable_operator_write_node->operator);

        int flags = VM_CALL_ARGS_SIMPLE | VM_CALL_FCALL | VM_CALL_VCALL;
        ADD_SEND_WITH_FLAG(ret, &dummy_line_node, method_id, INT2NUM(1), INT2FIX(flags));

        PM_DUP_UNLESS_POPPED;

        ADD_SETLOCAL(ret, &dummy_line_node, local_index.index, local_index.level);

        return;
      }
      case PM_LOCAL_VARIABLE_OR_WRITE_NODE: {
        pm_local_variable_or_write_node_t *local_variable_or_write_node = (pm_local_variable_or_write_node_t*) node;

        LABEL *set_label= NEW_LABEL(lineno);
        LABEL *end_label = NEW_LABEL(lineno);

        ADD_INSN1(ret, &dummy_line_node, putobject, Qtrue);
        ADD_INSNL(ret, &dummy_line_node, branchunless, set_label);

        pm_constant_id_t constant_id = local_variable_or_write_node->name;
        pm_local_index_t local_index = pm_lookup_local_index(iseq, scope_node, constant_id, local_variable_or_write_node->depth);
        ADD_GETLOCAL(ret, &dummy_line_node, local_index.index, local_index.level);

        PM_DUP_UNLESS_POPPED;

        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);

        PM_POP_UNLESS_POPPED;

        ADD_LABEL(ret, set_label);
        PM_COMPILE_NOT_POPPED(local_variable_or_write_node->value);

        PM_DUP_UNLESS_POPPED;

        ADD_SETLOCAL(ret, &dummy_line_node, local_index.index, local_index.level);
        ADD_LABEL(ret, end_label);

        return;
      }
      case PM_LOCAL_VARIABLE_READ_NODE: {
        pm_local_variable_read_node_t *local_read_node = (pm_local_variable_read_node_t *) node;

        if (!popped) {
            pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, local_read_node->name, local_read_node->depth);
            ADD_GETLOCAL(ret, &dummy_line_node, index.index, index.level);
        }
        return;
      }
      case PM_LOCAL_VARIABLE_WRITE_NODE: {
        pm_local_variable_write_node_t *local_write_node = (pm_local_variable_write_node_t *) node;
        PM_COMPILE_NOT_POPPED(local_write_node->value);

        PM_DUP_UNLESS_POPPED;

        pm_constant_id_t constant_id = local_write_node->name;

        pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, constant_id, local_write_node->depth);

        ADD_SETLOCAL(ret, &dummy_line_node, index.index, index.level);
        return;
      }
      case PM_MATCH_LAST_LINE_NODE: {
        // if /foo/ then end
        //    ^^^^^
        VALUE regexp = pm_static_literal_value(iseq, node, scope_node);

        PUSH_INSN1(ret, location, putobject, regexp);
        PUSH_INSN2(ret, location, getspecial, INT2FIX(0), INT2FIX(0));
        PUSH_SEND(ret, location, idEqTilde, INT2NUM(1));
        if (popped) PUSH_INSN(ret, location, pop);

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
        pm_compile_pattern(iseq, scope_node, cast->pattern, ret, matched_label, unmatched_label, false, false, true, 2);

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
      case PM_MATCH_REQUIRED_NODE: {
        // A match required node represents pattern matching against a single
        // pattern using the => operator. For example,
        //
        //     foo => bar
        //
        // This is somewhat analogous to compiling a case match statement with a
        // single pattern. In both cases, if the pattern fails it should
        // immediately raise an error.
        const pm_match_required_node_t *cast = (const pm_match_required_node_t *) node;

        LABEL *matched_label = NEW_LABEL(lineno);
        LABEL *unmatched_label = NEW_LABEL(lineno);
        LABEL *done_label = NEW_LABEL(lineno);

        // First, we're going to push a bunch of stuff onto the stack that is
        // going to serve as our scratch space.
        ADD_INSN(ret, &dummy_line_node, putnil); // key error key
        ADD_INSN(ret, &dummy_line_node, putnil); // key error matchee
        ADD_INSN1(ret, &dummy_line_node, putobject, Qfalse); // key error?
        ADD_INSN(ret, &dummy_line_node, putnil); // error string
        ADD_INSN(ret, &dummy_line_node, putnil); // deconstruct cache

        // Next we're going to compile the value expression such that it's on
        // the stack.
        PM_COMPILE_NOT_POPPED(cast->value);

        // Here we'll dup it so that it can be used for comparison, but also be
        // used for error handling.
        ADD_INSN(ret, &dummy_line_node, dup);

        // Next we'll compile the pattern. We indicate to the pm_compile_pattern
        // function that this is the only pattern that will be matched against
        // through the in_single_pattern parameter. We also indicate that the
        // value to compare against is 2 slots from the top of the stack (the
        // base_index parameter).
        pm_compile_pattern(iseq, scope_node, cast->pattern, ret, matched_label, unmatched_label, true, false, true, 2);

        // If the pattern did not match the value, then we're going to compile
        // in our error handler code. This will determine which error to raise
        // and raise it.
        ADD_LABEL(ret, unmatched_label);
        pm_compile_pattern_error_handler(iseq, scope_node, node, ret, done_label, popped);

        // If the pattern did match, we'll clean up the values we've pushed onto
        // the stack and then push nil onto the stack if it's not popped.
        ADD_LABEL(ret, matched_label);
        ADD_INSN1(ret, &dummy_line_node, adjuststack, INT2FIX(6));
        if (!popped) ADD_INSN(ret, &dummy_line_node, putnil);
        ADD_INSNL(ret, &dummy_line_node, jump, done_label);

        ADD_LABEL(ret, done_label);
        return;
      }
      case PM_MATCH_WRITE_NODE: {
        // Match write nodes are specialized call nodes that have a regular
        // expression with valid named capture groups on the left, the =~
        // operator, and some value on the right. The nodes themselves simply
        // wrap the call with the local variable targets that will be written
        // when the call is executed.
        pm_match_write_node_t *cast = (pm_match_write_node_t *) node;
        LABEL *fail_label = NEW_LABEL(lineno);
        LABEL *end_label = NEW_LABEL(lineno);

        // First, we'll compile the call so that all of its instructions are
        // present. Then we'll compile all of the local variable targets.
        PM_COMPILE_NOT_POPPED((pm_node_t *) cast->call);

        // Now, check if the match was successful. If it was, then we'll
        // continue on and assign local variables. Otherwise we'll skip over the
        // assignment code.
        ADD_INSN1(ret, &dummy_line_node, getglobal, rb_id2sym(idBACKREF));
        PM_DUP;
        ADD_INSNL(ret, &dummy_line_node, branchunless, fail_label);

        // If there's only a single local variable target, we can skip some of
        // the bookkeeping, so we'll put a special branch here.
        size_t targets_count = cast->targets.size;

        if (targets_count == 1) {
            pm_node_t *target = cast->targets.nodes[0];
            RUBY_ASSERT(PM_NODE_TYPE_P(target, PM_LOCAL_VARIABLE_TARGET_NODE));

            pm_local_variable_target_node_t *local_target = (pm_local_variable_target_node_t *) target;
            pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, local_target->name, local_target->depth);

            ADD_INSN1(ret, &dummy_line_node, putobject, rb_id2sym(pm_constant_id_lookup(scope_node, local_target->name)));
            ADD_SEND(ret, &dummy_line_node, idAREF, INT2FIX(1));
            ADD_LABEL(ret, fail_label);
            ADD_SETLOCAL(ret, &dummy_line_node, index.index, index.level);
            PM_POP_IF_POPPED;
            return;
        }

        // Otherwise there is more than one local variable target, so we'll need
        // to do some bookkeeping.
        for (size_t targets_index = 0; targets_index < targets_count; targets_index++) {
            pm_node_t *target = cast->targets.nodes[targets_index];
            RUBY_ASSERT(PM_NODE_TYPE_P(target, PM_LOCAL_VARIABLE_TARGET_NODE));

            pm_local_variable_target_node_t *local_target = (pm_local_variable_target_node_t *) target;
            pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, local_target->name, local_target->depth);

            if (((size_t) targets_index) < (targets_count - 1)) {
                PM_DUP;
            }
            ADD_INSN1(ret, &dummy_line_node, putobject, rb_id2sym(pm_constant_id_lookup(scope_node, local_target->name)));
            ADD_SEND(ret, &dummy_line_node, idAREF, INT2FIX(1));
            ADD_SETLOCAL(ret, &dummy_line_node, index.index, index.level);
        }

        // Since we matched successfully, now we'll jump to the end.
        ADD_INSNL(ret, &dummy_line_node, jump, end_label);

        // In the case that the match failed, we'll loop through each local
        // variable target and set all of them to `nil`.
        ADD_LABEL(ret, fail_label);
        PM_POP;

        for (size_t targets_index = 0; targets_index < targets_count; targets_index++) {
            pm_node_t *target = cast->targets.nodes[targets_index];
            RUBY_ASSERT(PM_NODE_TYPE_P(target, PM_LOCAL_VARIABLE_TARGET_NODE));

            pm_local_variable_target_node_t *local_target = (pm_local_variable_target_node_t *) target;
            pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, local_target->name, local_target->depth);

            PM_PUTNIL;
            ADD_SETLOCAL(ret, &dummy_line_node, index.index, index.level);
        }

        // Finally, we can push the end label for either case.
        ADD_LABEL(ret, end_label);
        PM_POP_IF_POPPED;
        return;
      }
      case PM_MISSING_NODE: {
        rb_bug("A pm_missing_node_t should not exist in prism's AST.");
        return;
      }
      case PM_MODULE_NODE: {
        pm_module_node_t *module_node = (pm_module_node_t *)node;

        ID module_id = pm_constant_id_lookup(scope_node, module_node->name);
        VALUE module_name = rb_str_freeze(rb_sprintf("<module:%"PRIsVALUE">", rb_id2str(module_id)));

        pm_scope_node_t next_scope_node;
        pm_scope_node_init((pm_node_t *)module_node, &next_scope_node, scope_node);
        const rb_iseq_t *module_iseq = NEW_CHILD_ISEQ(&next_scope_node, module_name, ISEQ_TYPE_CLASS, lineno);
        pm_scope_node_destroy(&next_scope_node);

        const int flags = VM_DEFINECLASS_TYPE_MODULE |
            pm_compile_class_path(ret, iseq, module_node->constant_path, &dummy_line_node, false, scope_node);

        PM_PUTNIL;
        ADD_INSN3(ret, &dummy_line_node, defineclass, ID2SYM(module_id), module_iseq, INT2FIX(flags));
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE)module_iseq);

        PM_POP_IF_POPPED;
        return;
      }
      case PM_REQUIRED_PARAMETER_NODE: {
        pm_required_parameter_node_t *required_parameter_node = (pm_required_parameter_node_t *)node;
        pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, required_parameter_node->name, 0);

        ADD_SETLOCAL(ret, &dummy_line_node, index.index, index.level);
        return;
      }
      case PM_MULTI_WRITE_NODE: {
        // A multi write node represents writing to multiple values using an =
        // operator. Importantly these nodes are only parsed when the left-hand
        // side of the operator has multiple targets. The right-hand side of the
        // operator having multiple targets represents an implicit array
        // instead.
        const pm_multi_write_node_t *cast = (const pm_multi_write_node_t *) node;

        DECL_ANCHOR(writes);
        INIT_ANCHOR(writes);

        DECL_ANCHOR(cleanup);
        INIT_ANCHOR(cleanup);

        pm_multi_target_state_t state = { 0 };
        state.position = popped ? 0 : 1;
        size_t stack_size = pm_compile_multi_target_node(iseq, node, ret, writes, cleanup, scope_node, &state);

        PM_COMPILE_NOT_POPPED(cast->value);
        PM_DUP_UNLESS_POPPED;

        ADD_SEQ(ret, writes);
        if (!popped && stack_size >= 1) {
            // Make sure the value on the right-hand side of the = operator is
            // being returned before we pop the parent expressions.
            ADD_INSN1(ret, &dummy_line_node, setn, INT2FIX(stack_size));
        }

        ADD_SEQ(ret, cleanup);

        return;
      }
      case PM_NEXT_NODE: {
        pm_next_node_t *next_node = (pm_next_node_t *) node;

        if (ISEQ_COMPILE_DATA(iseq)->redo_label != 0 && can_add_ensure_iseq(iseq)) {
            LABEL *splabel = NEW_LABEL(0);

            ADD_LABEL(ret, splabel);

            if (next_node->arguments) {
                PM_COMPILE_NOT_POPPED((pm_node_t *)next_node->arguments);
            }
            else {
                PM_PUTNIL;
            }
            pm_add_ensure_iseq(ret, iseq, 0, scope_node);

            ADD_ADJUST(ret, &dummy_line_node, ISEQ_COMPILE_DATA(iseq)->redo_label);
            ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->start_label);

            ADD_ADJUST_RESTORE(ret, splabel);
            PM_PUTNIL_UNLESS_POPPED;
        }
        else if (ISEQ_COMPILE_DATA(iseq)->end_label && can_add_ensure_iseq(iseq)) {
            LABEL *splabel = NEW_LABEL(0);

            ADD_LABEL(ret, splabel);
            ADD_ADJUST(ret, &dummy_line_node, ISEQ_COMPILE_DATA(iseq)->start_label);

            if (next_node->arguments) {
                PM_COMPILE_NOT_POPPED((pm_node_t *)next_node->arguments);
            }
            else {
                PM_PUTNIL;
            }

            pm_add_ensure_iseq(ret, iseq, 0, scope_node);
            ADD_INSNL(ret, &dummy_line_node, jump, ISEQ_COMPILE_DATA(iseq)->end_label);
            ADD_ADJUST_RESTORE(ret, splabel);
            splabel->unremovable = FALSE;

            PM_PUTNIL_UNLESS_POPPED;
        }
        else {
            const rb_iseq_t *ip = iseq;

            unsigned long throw_flag = 0;
            while (ip) {
                if (!ISEQ_COMPILE_DATA(ip)) {
                    ip = 0;
                    break;
                }

                throw_flag = VM_THROW_NO_ESCAPE_FLAG;
                if (ISEQ_COMPILE_DATA(ip)->redo_label != 0) {
                    /* while loop */
                    break;
                }
                else if (ISEQ_BODY(ip)->type == ISEQ_TYPE_BLOCK) {
                    break;
                }
                else if (ISEQ_BODY(ip)->type == ISEQ_TYPE_EVAL) {
                    COMPILE_ERROR(ERROR_ARGS "Can't escape from eval with next");
                    return;
                }

                ip = ISEQ_BODY(ip)->parent_iseq;
            }
            if (ip != 0) {
                if (next_node->arguments) {
                    PM_COMPILE_NOT_POPPED((pm_node_t *)next_node->arguments);
                }
                else {
                    PM_PUTNIL;
                }
                ADD_INSN1(ret, &dummy_line_node, throw, INT2FIX(throw_flag | TAG_NEXT));

                PM_POP_IF_POPPED;
            }
            else {
                rb_raise(rb_eArgError, "Invalid next");
                return;
            }
        }

        return;
      }
      case PM_NIL_NODE: {
        // nil
        // ^^^
        if (!popped) {
            PUSH_INSN(ret, location, putnil);
        }

        return;
      }
      case PM_NO_KEYWORDS_PARAMETER_NODE: {
        // def foo(**nil); end
        //         ^^^^^
        ISEQ_BODY(iseq)->param.flags.accepts_no_kwarg = TRUE;
        return;
      }
      case PM_NUMBERED_REFERENCE_READ_NODE: {
        // $1
        // ^^
        if (!popped) {
            uint32_t reference_number = ((const pm_numbered_reference_read_node_t *) node)->number;

            if (reference_number > 0) {
                PUSH_INSN2(ret, location, getspecial, INT2FIX(1), INT2FIX(reference_number << 1));
            }
            else {
                PUSH_INSN(ret, location, putnil);
            }
        }

        return;
      }
      case PM_OR_NODE: {
        // a or b
        // ^^^^^^
        const pm_or_node_t *cast = (const pm_or_node_t *) node;

        LABEL *end_label = NEW_LABEL(location.line);
        PM_COMPILE_NOT_POPPED(cast->left);

        if (!popped) PUSH_INSN(ret, location, dup);
        PUSH_INSNL(ret, location, branchif, end_label);

        if (!popped) PUSH_INSN(ret, location, pop);
        PM_COMPILE(cast->right);
        PUSH_LABEL(ret, end_label);

        return;
      }
      case PM_OPTIONAL_PARAMETER_NODE: {
        // def foo(bar = 1); end
        //         ^^^^^^^
        const pm_optional_parameter_node_t *cast = (const pm_optional_parameter_node_t *) node;
        PM_COMPILE_NOT_POPPED(cast->value);

        pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, cast->name, 0);
        ADD_SETLOCAL(ret, &dummy_line_node, index.index, index.level);

        return;
      }
      case PM_PARENTHESES_NODE: {
        // ()
        // ^^
        //
        // (1)
        // ^^^
        const pm_parentheses_node_t *cast = (const pm_parentheses_node_t *) node;

        if (cast->body != NULL) {
            PM_COMPILE(cast->body);
        }
        else if (!popped) {
            PUSH_INSN(ret, location, putnil);
        }

        return;
      }
      case PM_PRE_EXECUTION_NODE: {
        // BEGIN {}
        // ^^^^^^^^
        const pm_pre_execution_node_t *cast = (const pm_pre_execution_node_t *) node;

        DECL_ANCHOR(pre_ex);
        INIT_ANCHOR(pre_ex);

        if (cast->statements != NULL) {
            const pm_node_list_t *body = &cast->statements->body;
            for (size_t index = 0; index < body->size; index++) {
                pm_compile_node(iseq, body->nodes[index], pre_ex, true, scope_node);
            }
        }

        if (!popped) {
            PUSH_INSN(pre_ex, location, putnil);
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
        // END {}
        // ^^^^^^
        const rb_iseq_t *child_iseq;
        const rb_iseq_t *prevblock = ISEQ_COMPILE_DATA(iseq)->current_block;

        pm_scope_node_t next_scope_node;
        pm_scope_node_init(node, &next_scope_node, scope_node);
        child_iseq = NEW_CHILD_ISEQ(&next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
        pm_scope_node_destroy(&next_scope_node);

        ISEQ_COMPILE_DATA(iseq)->current_block = child_iseq;

        int is_index = ISEQ_BODY(iseq)->ise_size++;
        PUSH_INSN2(ret, location, once, child_iseq, INT2FIX(is_index));
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE) child_iseq);
        if (popped) PUSH_INSN(ret, location, pop);

        ISEQ_COMPILE_DATA(iseq)->current_block = prevblock;

        return;
      }
      case PM_RANGE_NODE: {
        // 0..5
        // ^^^^
        const pm_range_node_t *cast = (const pm_range_node_t *) node;
        bool exclude_end = PM_NODE_FLAG_P(cast, PM_RANGE_FLAGS_EXCLUDE_END);

        if (pm_optimizable_range_item_p(cast->left) && pm_optimizable_range_item_p(cast->right))  {
            if (!popped) {
                const pm_node_t *left = cast->left;
                const pm_node_t *right = cast->right;

                VALUE val = rb_range_new(
                    (left && PM_NODE_TYPE_P(left, PM_INTEGER_NODE)) ? parse_integer((const pm_integer_node_t *) left) : Qnil,
                    (right && PM_NODE_TYPE_P(right, PM_INTEGER_NODE)) ? parse_integer((const pm_integer_node_t *) right) : Qnil,
                    exclude_end
                );

                PUSH_INSN1(ret, location, putobject, val);
            }
        }
        else {
            if (cast->left == NULL) {
                PUSH_INSN(ret, location, putnil);
            }
            else {
                PM_COMPILE(cast->left);
            }

            if (cast->right == NULL) {
                PUSH_INSN(ret, location, putnil);
            }
            else {
                PM_COMPILE(cast->right);
            }

            if (!popped) {
                PUSH_INSN1(ret, location, newrange, INT2FIX(exclude_end ? 1 : 0));
            }
        }
        return;
      }
      case PM_RATIONAL_NODE: {
        // 1r
        // ^^
        if (!popped) {
            PUSH_INSN1(ret, location, putobject, parse_rational((const pm_rational_node_t *) node));
        }
        return;
      }
      case PM_REDO_NODE: {
        // redo
        // ^^^^
        if (ISEQ_COMPILE_DATA(iseq)->redo_label && can_add_ensure_iseq(iseq)) {
            LABEL *splabel = NEW_LABEL(0);

            PUSH_LABEL(ret, splabel);
            PUSH_ADJUST(ret, location, ISEQ_COMPILE_DATA(iseq)->redo_label);
            pm_add_ensure_iseq(ret, iseq, 0, scope_node);

            PUSH_INSNL(ret, location, jump, ISEQ_COMPILE_DATA(iseq)->redo_label);
            PUSH_ADJUST_RESTORE(ret, splabel);
            if (!popped) PUSH_INSN(ret, location, putnil);
        }
        else if (ISEQ_BODY(iseq)->type != ISEQ_TYPE_EVAL && ISEQ_COMPILE_DATA(iseq)->start_label && can_add_ensure_iseq(iseq)) {
            LABEL *splabel = NEW_LABEL(0);

            PUSH_LABEL(ret, splabel);
            pm_add_ensure_iseq(ret, iseq, 0, scope_node);
            PUSH_ADJUST(ret, location, ISEQ_COMPILE_DATA(iseq)->start_label);

            PUSH_INSNL(ret, location, jump, ISEQ_COMPILE_DATA(iseq)->start_label);
            PUSH_ADJUST_RESTORE(ret, splabel);
            if (!popped) PUSH_INSN(ret, location, putnil);
        }
        else {
            const rb_iseq_t *ip = iseq;

            while (ip) {
                if (!ISEQ_COMPILE_DATA(ip)) {
                    ip = 0;
                    break;
                }

                if (ISEQ_COMPILE_DATA(ip)->redo_label != 0) {
                    break;
                }
                else if (ISEQ_BODY(ip)->type == ISEQ_TYPE_BLOCK) {
                    break;
                }
                else if (ISEQ_BODY(ip)->type == ISEQ_TYPE_EVAL) {
                    COMPILE_ERROR(ERROR_ARGS "Can't escape from eval with redo");
                    return;
                }

                ip = ISEQ_BODY(ip)->parent_iseq;
            }

            if (ip != 0) {
                PUSH_INSN(ret, location, putnil);
                PUSH_INSN1(ret, location, throw, INT2FIX(VM_THROW_NO_ESCAPE_FLAG | TAG_REDO));
                if (popped) PUSH_INSN(ret, location, pop);
            }
            else {
                COMPILE_ERROR(ERROR_ARGS "Invalid redo");
                return;
            }
        }
        return;
      }
      case PM_REGULAR_EXPRESSION_NODE: {
        // /foo/
        // ^^^^^
        if (!popped) {
            VALUE regexp = pm_static_literal_value(iseq, node, scope_node);
            PUSH_INSN1(ret, location, putobject, regexp);
        }
        return;
      }
      case PM_RESCUE_NODE: {
        // begin; rescue; end
        //        ^^^^^^^
        const pm_rescue_node_t *cast = (const pm_rescue_node_t *) node;
        iseq_set_exception_local_table(iseq);

        // First, establish the labels that we need to be able to jump to within
        // this compilation block.
        LABEL *exception_match_label = NEW_LABEL(location.line);
        LABEL *rescue_end_label = NEW_LABEL(location.line);

        // Next, compile each of the exceptions that we're going to be
        // handling. For each one, we'll add instructions to check if the
        // exception matches the raised one, and if it does then jump to the
        // exception_match_label label. Otherwise it will fall through to the
        // subsequent check. If there are no exceptions, we'll only check
        // StandardError.
        const pm_node_list_t *exceptions = &cast->exceptions;

        if (exceptions->size > 0) {
            for (size_t index = 0; index < exceptions->size; index++) {
                ADD_GETLOCAL(ret, &dummy_line_node, LVAR_ERRINFO, 0);
                PM_COMPILE(exceptions->nodes[index]);
                int checkmatch_flags = VM_CHECKMATCH_TYPE_RESCUE;
                if (PM_NODE_TYPE_P(exceptions->nodes[index], PM_SPLAT_NODE)) {
                    checkmatch_flags |= VM_CHECKMATCH_ARRAY;
                }
                PUSH_INSN1(ret, location, checkmatch, INT2FIX(checkmatch_flags));
                PUSH_INSNL(ret, location, branchif, exception_match_label);
            }
        }
        else {
            ADD_GETLOCAL(ret, &dummy_line_node, LVAR_ERRINFO, 0);
            PUSH_INSN1(ret, location, putobject, rb_eStandardError);
            PUSH_INSN1(ret, location, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_RESCUE));
            PUSH_INSNL(ret, location, branchif, exception_match_label);
        }

        // If none of the exceptions that we are matching against matched, then
        // we'll jump straight to the rescue_end_label label.
        PUSH_INSNL(ret, location, jump, rescue_end_label);

        // Here we have the exception_match_label, which is where the
        // control-flow goes in the case that one of the exceptions matched.
        // Here we will compile the instructions to handle the exception.
        PUSH_LABEL(ret, exception_match_label);
        PUSH_TRACE(ret, RUBY_EVENT_RESCUE);

        // If we have a reference to the exception, then we'll compile the write
        // into the instruction sequence. This can look quite different
        // depending on the kind of write being performed.
        if (cast->reference) {
            DECL_ANCHOR(writes);
            INIT_ANCHOR(writes);

            DECL_ANCHOR(cleanup);
            INIT_ANCHOR(cleanup);

            pm_compile_target_node(iseq, cast->reference, ret, writes, cleanup, scope_node, NULL);
            ADD_GETLOCAL(ret, &dummy_line_node, LVAR_ERRINFO, 0);

            ADD_SEQ(ret, writes);
            ADD_SEQ(ret, cleanup);
        }

        // If we have statements to execute, we'll compile them here. Otherwise
        // we'll push nil onto the stack.
        if (cast->statements) {
            // We'll temporarily remove the end_label location from the iseq
            // when compiling the statements so that next/redo statements
            // inside the body will throw to the correct place instead of
            // jumping straight to the end of this iseq
            LABEL *prev_end = ISEQ_COMPILE_DATA(iseq)->end_label;
            ISEQ_COMPILE_DATA(iseq)->end_label = NULL;

            PM_COMPILE((pm_node_t *) cast->statements);

            // Now restore the end_label
            ISEQ_COMPILE_DATA(iseq)->end_label = prev_end;
        }
        else {
            PUSH_INSN(ret, location, putnil);
        }

        PUSH_INSN(ret, location, leave);

        // Here we'll insert the rescue_end_label label, which is jumped to if
        // none of the exceptions matched. It will cause the control-flow to
        // either jump to the next rescue clause or it will fall through to the
        // subsequent instruction returning the raised error.
        PUSH_LABEL(ret, rescue_end_label);
        if (cast->consequent) {
            PM_COMPILE((pm_node_t *) cast->consequent);
        }
        else {
            ADD_GETLOCAL(ret, &dummy_line_node, 1, 0);
        }

        return;
      }
      case PM_RESCUE_MODIFIER_NODE: {
        // foo rescue bar
        // ^^^^^^^^^^^^^^
        const pm_rescue_modifier_node_t *cast = (const pm_rescue_modifier_node_t *) node;

        pm_scope_node_t rescue_scope_node;
        pm_scope_node_init((const pm_node_t *) cast, &rescue_scope_node, scope_node);

        rb_iseq_t *rescue_iseq = NEW_CHILD_ISEQ(
            &rescue_scope_node,
            rb_str_concat(rb_str_new2("rescue in "), ISEQ_BODY(iseq)->location.label),
            ISEQ_TYPE_RESCUE,
            pm_node_line_number(parser, cast->rescue_expression)
        );

        pm_scope_node_destroy(&rescue_scope_node);

        LABEL *lstart = NEW_LABEL(location.line);
        LABEL *lend = NEW_LABEL(location.line);
        LABEL *lcont = NEW_LABEL(location.line);

        lstart->rescued = LABEL_RESCUE_BEG;
        lend->rescued = LABEL_RESCUE_END;
        PUSH_LABEL(ret, lstart);
        PM_COMPILE_NOT_POPPED(cast->expression);
        PUSH_LABEL(ret, lend);
        PUSH_INSN(ret, location, nop);
        PUSH_LABEL(ret, lcont);
        if (popped) PUSH_INSN(ret, location, pop);

        ADD_CATCH_ENTRY(CATCH_TYPE_RESCUE, lstart, lend, rescue_iseq, lcont);
        ADD_CATCH_ENTRY(CATCH_TYPE_RETRY, lend, lcont, NULL, lstart);
        return;
      }
      case PM_RETURN_NODE: {
        // return
        // ^^^^^^
        //
        // return 1
        // ^^^^^^^^
        const pm_return_node_t *cast = (const pm_return_node_t *) node;
        const pm_arguments_node_t *arguments = cast->arguments;

        enum rb_iseq_type type = ISEQ_BODY(iseq)->type;
        LABEL *splabel = 0;

        const rb_iseq_t *parent_iseq = iseq;
        enum rb_iseq_type parent_type = ISEQ_BODY(parent_iseq)->type;
        while (parent_type == ISEQ_TYPE_RESCUE || parent_type == ISEQ_TYPE_ENSURE) {
            if (!(parent_iseq = ISEQ_BODY(parent_iseq)->parent_iseq)) break;
            parent_type = ISEQ_BODY(parent_iseq)->type;
        }

        switch (parent_type) {
          case ISEQ_TYPE_TOP:
          case ISEQ_TYPE_MAIN:
            if (arguments) {
                rb_warn("argument of top-level return is ignored");
            }
            if (parent_iseq == iseq) {
                type = ISEQ_TYPE_METHOD;
            }
            break;
          default:
            break;
        }

        if (type == ISEQ_TYPE_METHOD) {
            splabel = NEW_LABEL(0);
            PUSH_LABEL(ret, splabel);
            PUSH_ADJUST(ret, location, 0);
        }

        if (arguments) {
            PM_COMPILE_NOT_POPPED((const pm_node_t *) arguments);
        }
        else {
            PUSH_INSN(ret, location, putnil);
        }

        if (type == ISEQ_TYPE_METHOD && can_add_ensure_iseq(iseq)) {
            pm_add_ensure_iseq(ret, iseq, 1, scope_node);
            PUSH_TRACE(ret, RUBY_EVENT_RETURN);
            PUSH_INSN(ret, location, leave);
            PUSH_ADJUST_RESTORE(ret, splabel);
            if (!popped) PUSH_INSN(ret, location, putnil);
        }
        else {
            PUSH_INSN1(ret, location, throw, INT2FIX(TAG_RETURN));
            if (popped) PUSH_INSN(ret, location, pop);
        }

        return;
      }
      case PM_RETRY_NODE: {
        // retry
        // ^^^^^
        if (ISEQ_BODY(iseq)->type == ISEQ_TYPE_RESCUE) {
            PUSH_INSN(ret, location, putnil);
            PUSH_INSN1(ret, location, throw, INT2FIX(TAG_RETRY));
            if (popped) PUSH_INSN(ret, location, pop);
        }
        else {
            COMPILE_ERROR(ERROR_ARGS "Invalid retry");
            return;
        }
        return;
      }
      case PM_SCOPE_NODE: {
        pm_scope_node_t *scope_node = (pm_scope_node_t *)node;
        pm_constant_id_list_t *locals = &scope_node->locals;

        pm_parameters_node_t *parameters_node = NULL;
        pm_node_list_t *keywords_list = NULL;
        pm_node_list_t *optionals_list = NULL;
        pm_node_list_t *posts_list = NULL;
        pm_node_list_t *requireds_list = NULL;
        pm_node_list_t *block_locals = NULL;
        bool trailing_comma = false;

        struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);

        if (scope_node->parameters) {
            switch (PM_NODE_TYPE(scope_node->parameters)) {
              case PM_BLOCK_PARAMETERS_NODE: {
                pm_block_parameters_node_t *block_parameters_node = (pm_block_parameters_node_t *)scope_node->parameters;
                parameters_node = block_parameters_node->parameters;
                block_locals = &block_parameters_node->locals;
                if (parameters_node) {
                    if (parameters_node->rest && PM_NODE_TYPE_P(parameters_node->rest, PM_IMPLICIT_REST_NODE)) {
                        trailing_comma = true;
                    }
                }
                break;
              }
              case PM_PARAMETERS_NODE: {
                parameters_node = (pm_parameters_node_t *) scope_node->parameters;
                break;
              }
              case PM_NUMBERED_PARAMETERS_NODE: {
                uint32_t maximum = ((pm_numbered_parameters_node_t *) scope_node->parameters)->maximum;
                body->param.lead_num = maximum;
                body->param.flags.ambiguous_param0 = maximum == 1;
                break;
              }
              case PM_IT_PARAMETERS_NODE:
                body->param.lead_num = 1;
                body->param.flags.ambiguous_param0 = true;
                break;
              default:
                rb_bug("Unexpected node type for parameters: %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
            }
        }

        struct rb_iseq_param_keyword *keyword = NULL;

        if (parameters_node) {
            optionals_list = &parameters_node->optionals;
            requireds_list = &parameters_node->requireds;
            keywords_list = &parameters_node->keywords;
            posts_list = &parameters_node->posts;
        }
        else if (scope_node->parameters && (PM_NODE_TYPE_P(scope_node->parameters, PM_NUMBERED_PARAMETERS_NODE) || PM_NODE_TYPE_P(scope_node->parameters, PM_IT_PARAMETERS_NODE))) {
            body->param.opt_num = 0;
        }
        else {
            body->param.lead_num = 0;
            body->param.opt_num = 0;
        }

        //********STEP 1**********
        // Goal: calculate the table size for the locals, accounting for
        // hidden variables and multi target nodes
        size_t locals_size = locals->size;

        // Index lookup table buffer size is only the number of the locals
        st_table *index_lookup_table = st_init_numtable();

        int table_size = (int) locals_size;

        // For nodes have a hidden iteration variable. We add that to the local
        // table size here.
        if (PM_NODE_TYPE_P(scope_node->ast_node, PM_FOR_NODE)) table_size++;

        if (keywords_list && keywords_list->size) {
            table_size++;
        }

        if (requireds_list) {
            for (size_t i = 0; i < requireds_list->size; i++) {
                // For each MultiTargetNode, we're going to have one
                // additional anonymous local not represented in the locals table
                // We want to account for this in our table size
                pm_node_t *required = requireds_list->nodes[i];
                if (PM_NODE_TYPE_P(required, PM_MULTI_TARGET_NODE)) {
                    table_size++;
                }
                else if (PM_NODE_TYPE_P(required, PM_REQUIRED_PARAMETER_NODE)) {
                    if (PM_NODE_FLAG_P(required, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        table_size++;
                    }
                }
            }
        }

        // Ensure there is enough room in the local table for any
        // parameters that have been repeated
        // ex: def underscore_parameters(_, _ = 1, _ = 2); _; end
        //                                  ^^^^^^^^^^^^
        if (optionals_list && optionals_list->size) {
            for (size_t i = 0; i < optionals_list->size; i++) {
                pm_node_t * node = optionals_list->nodes[i];
                if (PM_NODE_FLAG_P(node, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                    table_size++;
                }
            }
        }

        // If we have an anonymous "rest" node, we'll need to increase the local
        // table size to take it in to account.
        // def m(foo, *, bar)
        //            ^
        if (parameters_node) {
            if (parameters_node->rest) {
                if (!(PM_NODE_TYPE_P(parameters_node->rest, PM_IMPLICIT_REST_NODE))) {
                    if (!((pm_rest_parameter_node_t *)parameters_node->rest)->name || PM_NODE_FLAG_P(parameters_node->rest, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        table_size++;
                    }
                }
            }

            // def foo(_, **_); _; end
            //            ^^^
            if (parameters_node->keyword_rest) {
                // def foo(...); end
                //         ^^^
                // When we have a `...` as the keyword_rest, it's a forwarding_parameter_node and
                // we need to leave space for 4 locals: *, **, &, ...
                if (PM_NODE_TYPE_P(parameters_node->keyword_rest, PM_FORWARDING_PARAMETER_NODE)) {
                    table_size += 4;
                }
                else {
                    pm_keyword_rest_parameter_node_t * kw_rest = (pm_keyword_rest_parameter_node_t *)parameters_node->keyword_rest;

                    // If it's anonymous or repeated, then we need to allocate stack space
                    if (!kw_rest->name || PM_NODE_FLAG_P(kw_rest, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        table_size++;
                    }
                }
            }
        }

        if (posts_list) {
            for (size_t i = 0; i < posts_list->size; i++) {
                // For each MultiTargetNode, we're going to have one
                // additional anonymous local not represented in the locals table
                // We want to account for this in our table size
                pm_node_t *required = posts_list->nodes[i];
                if (PM_NODE_TYPE_P(required, PM_MULTI_TARGET_NODE) || PM_NODE_FLAG_P(required, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                    table_size++;
                }
            }
        }

        if (keywords_list && keywords_list->size) {
            for (size_t i = 0; i < keywords_list->size; i++) {
                pm_node_t *keyword_parameter_node = keywords_list->nodes[i];
                if (PM_NODE_FLAG_P(keyword_parameter_node, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                    table_size++;
                }
            }
        }

        if (parameters_node && parameters_node->block) {
            pm_block_parameter_node_t * block_node = (pm_block_parameter_node_t *)parameters_node->block;

            if (PM_NODE_FLAG_P(block_node, PM_PARAMETER_FLAGS_REPEATED_PARAMETER) || !block_node->name) {
                table_size++;
            }
        }

        // We can create local_table_for_iseq with the correct size
        VALUE idtmp = 0;
        rb_ast_id_table_t *local_table_for_iseq = ALLOCV(idtmp, sizeof(rb_ast_id_table_t) + table_size * sizeof(ID));
        local_table_for_iseq->size = table_size;

        //********END OF STEP 1**********

        //********STEP 2**********
        // Goal: populate iv index table as well as local table, keeping the
        // layout of the local table consistent with the layout of the
        // stack when calling the method
        //
        // Do a first pass on all of the parameters, setting their values in
        // the local_table_for_iseq, _except_ for Multis who get a hidden
        // variable in this step, and will get their names inserted in step 3

        // local_index is a cursor that keeps track of the current
        // index into local_table_for_iseq. The local table is actually a list,
        // and the order of that list must match the order of the items pushed
        // on the stack.  We need to take in to account things pushed on the
        // stack that _might not have a name_ (for example array destructuring).
        // This index helps us know which item we're dealing with and also give
        // those anonymous items temporary names (as below)
        int local_index = 0;

        // Here we figure out local table indices and insert them in to the
        // index lookup table and local tables.
        //
        // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
        //         ^^^^^^^^^^^^^
        if (requireds_list && requireds_list->size) {
            for (size_t i = 0; i < requireds_list->size; i++, local_index++) {
                ID local;

                // For each MultiTargetNode, we're going to have one additional
                // anonymous local not represented in the locals table. We want
                // to account for this in our table size.
                pm_node_t *required = requireds_list->nodes[i];

                switch (PM_NODE_TYPE(required)) {
                  // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                  //            ^^^^^^^^^^
                  case PM_MULTI_TARGET_NODE: {
                    local = rb_make_temporary_id(local_index);
                    local_table_for_iseq->ids[local_index] = local;
                    break;
                  }
                  // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                  //         ^
                  case PM_REQUIRED_PARAMETER_NODE: {
                    pm_required_parameter_node_t * param = (pm_required_parameter_node_t *)required;

                    if (PM_NODE_FLAG_P(required, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        ID local = pm_constant_id_lookup(scope_node, param->name);
                        local_table_for_iseq->ids[local_index] = local;
                    }
                    else {
                        pm_insert_local_index(param->name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                    }

                    break;
                  }
                  default: {
                    rb_bug("Unsupported node in requireds in parameters %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
                  }
                }
            }

            body->param.lead_num = (int) requireds_list->size;
            body->param.flags.has_lead = true;
        }

        // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
        //                        ^^^^^
        if (optionals_list && optionals_list->size) {
            body->param.opt_num = (int) optionals_list->size;
            body->param.flags.has_opt = true;

            for (size_t i = 0; i < optionals_list->size; i++, local_index++) {
                pm_node_t * node = optionals_list->nodes[i];
                pm_constant_id_t name = ((pm_optional_parameter_node_t *)node)->name;

                if (PM_NODE_FLAG_P(node, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                    ID local = pm_constant_id_lookup(scope_node, name);
                    local_table_for_iseq->ids[local_index] = local;
                }
                else {
                    pm_insert_local_index(name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                }
            }
        }

        // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
        //                               ^^
        if (parameters_node && parameters_node->rest) {
            body->param.rest_start = local_index;

            // If there's a trailing comma, we'll have an implicit rest node,
            // and we don't want it to impact the rest variables on param
            if (!(PM_NODE_TYPE_P(parameters_node->rest, PM_IMPLICIT_REST_NODE))) {
                body->param.flags.has_rest = true;
                RUBY_ASSERT(body->param.rest_start != -1);

                pm_constant_id_t name = ((pm_rest_parameter_node_t *) parameters_node->rest)->name;

                if (name) {
                    // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                    //                               ^^
                    if (PM_NODE_FLAG_P(parameters_node->rest, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        ID local = pm_constant_id_lookup(scope_node, name);
                        local_table_for_iseq->ids[local_index] = local;
                    }
                    else {
                        pm_insert_local_index(name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                    }
                }
                else {
                    // def foo(a, (b, *c, d), e = 1, *, g, (h, *i, j), k:, l: 1, **m, &n)
                    //                               ^
                    pm_insert_local_special(idMULT, local_index, index_lookup_table, local_table_for_iseq);
                }

                local_index++;
            }
        }

        // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
        //                                   ^^^^^^^^^^^^^
        if (posts_list && posts_list->size) {
            body->param.post_num = (int) posts_list->size;
            body->param.post_start = local_index;
            body->param.flags.has_post = true;

            for (size_t i = 0; i < posts_list->size; i++, local_index++) {
                ID local;

                // For each MultiTargetNode, we're going to have one additional
                // anonymous local not represented in the locals table. We want
                // to account for this in our table size.
                const pm_node_t *post_node = posts_list->nodes[i];

                switch (PM_NODE_TYPE(post_node)) {
                  // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                  //                                      ^^^^^^^^^^
                  case PM_MULTI_TARGET_NODE: {
                    local = rb_make_temporary_id(local_index);
                    local_table_for_iseq->ids[local_index] = local;
                    break;
                  }
                  // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                  //                                   ^
                  case PM_REQUIRED_PARAMETER_NODE: {
                    const pm_required_parameter_node_t *param = (const pm_required_parameter_node_t *) post_node;

                    if (PM_NODE_FLAG_P(param, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        ID local = pm_constant_id_lookup(scope_node, param->name);
                        local_table_for_iseq->ids[local_index] = local;
                    }
                    else {
                        pm_insert_local_index(param->name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                    }
                    break;
                  }
                  default: {
                    rb_bug("Unsupported node in posts in parameters %s", pm_node_type_to_str(PM_NODE_TYPE(node)));
                  }
                }
            }
        }

        // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
        //                                                   ^^^^^^^^
        // Keywords create an internal variable on the parse tree
        if (keywords_list && keywords_list->size) {
            body->param.keyword = keyword = ZALLOC_N(struct rb_iseq_param_keyword, 1);
            keyword->num = (int) keywords_list->size;

            body->param.flags.has_kw = true;
            const VALUE default_values = rb_ary_hidden_new(1);
            const VALUE complex_mark = rb_str_tmp_new(0);

            ID *ids = xcalloc(keywords_list->size, sizeof(ID));

            size_t kw_index = 0;

            for (size_t i = 0; i < keywords_list->size; i++) {
                pm_node_t *keyword_parameter_node = keywords_list->nodes[i];
                pm_constant_id_t name;

                // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                //                                                   ^^
                if (PM_NODE_TYPE_P(keyword_parameter_node, PM_REQUIRED_KEYWORD_PARAMETER_NODE)) {
                    name = ((pm_required_keyword_parameter_node_t *)keyword_parameter_node)->name;
                    keyword->required_num++;
                    ID local = pm_constant_id_lookup(scope_node, name);

                    if (PM_NODE_FLAG_P(keyword_parameter_node, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        local_table_for_iseq->ids[local_index] = local;
                    }
                    else {
                        pm_insert_local_index(name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                    }
                    local_index++;
                    ids[kw_index++] = local;
                }
            }

            for (size_t i = 0; i < keywords_list->size; i++) {
                pm_node_t *keyword_parameter_node = keywords_list->nodes[i];
                pm_constant_id_t name;

                // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                //                                                       ^^^^
                if (PM_NODE_TYPE_P(keyword_parameter_node, PM_OPTIONAL_KEYWORD_PARAMETER_NODE)) {
                    pm_optional_keyword_parameter_node_t *cast = ((pm_optional_keyword_parameter_node_t *)keyword_parameter_node);

                    pm_node_t *value = cast->value;
                    name = cast->name;

                    if (PM_NODE_FLAG_P(value, PM_NODE_FLAG_STATIC_LITERAL) && !(PM_NODE_TYPE_P(value, PM_ARRAY_NODE) || PM_NODE_TYPE_P(value, PM_HASH_NODE) || PM_NODE_TYPE_P(value, PM_RANGE_NODE))) {
                       rb_ary_push(default_values, pm_static_literal_value(iseq, value, scope_node));
                    }
                    else {
                        rb_ary_push(default_values, complex_mark);
                    }

                    ID local = pm_constant_id_lookup(scope_node, name);
                    if (PM_NODE_FLAG_P(keyword_parameter_node, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        local_table_for_iseq->ids[local_index] = local;
                    }
                    else {
                        pm_insert_local_index(name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                    }
                    ids[kw_index++] = local;
                    local_index++;
                }

            }

            keyword->bits_start = local_index;
            keyword->table = ids;

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

            // Hidden local for keyword arguments
            ID local = rb_make_temporary_id(local_index);
            local_table_for_iseq->ids[local_index] = local;
            local_index++;
        }

        if (body->type == ISEQ_TYPE_BLOCK && local_index == 1 && requireds_list && requireds_list->size == 1 && !trailing_comma) {
            body->param.flags.ambiguous_param0 = true;
        }

        if (parameters_node) {
            // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
            //                                                             ^^^
            if (parameters_node->keyword_rest) {
                switch (PM_NODE_TYPE(parameters_node->keyword_rest)) {
                  // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **nil, &n)
                  //                                                             ^^^^^
                  case PM_NO_KEYWORDS_PARAMETER_NODE: {
                    body->param.flags.accepts_no_kwarg = true;
                    break;
                  }
                  // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                  //                                                             ^^^
                  case PM_KEYWORD_REST_PARAMETER_NODE: {
                    const pm_keyword_rest_parameter_node_t *kw_rest_node = (const pm_keyword_rest_parameter_node_t *) parameters_node->keyword_rest;
                    if (!body->param.flags.has_kw) {
                        body->param.keyword = keyword = ZALLOC_N(struct rb_iseq_param_keyword, 1);
                    }

                    keyword->rest_start = local_index;
                    body->param.flags.has_kwrest = true;

                    pm_constant_id_t constant_id = kw_rest_node->name;
                    if (constant_id) {
                        if (PM_NODE_FLAG_P(kw_rest_node, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                            ID local = pm_constant_id_lookup(scope_node, constant_id);
                            local_table_for_iseq->ids[local_index] = local;
                        }
                        else {
                            pm_insert_local_index(constant_id, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                        }
                    }
                    else {
                        pm_insert_local_special(idPow, local_index, index_lookup_table, local_table_for_iseq);
                    }

                    local_index++;
                    break;
                  }
                  // def foo(...)
                  //         ^^^
                  case PM_FORWARDING_PARAMETER_NODE: {
                    body->param.rest_start = local_index;
                    body->param.flags.has_rest = true;

                    // Add the leading *
                    pm_insert_local_special(idMULT, local_index++, index_lookup_table, local_table_for_iseq);

                    // Add the kwrest **
                    RUBY_ASSERT(!body->param.flags.has_kw);

                    // There are no keywords declared (in the text of the program)
                    // but the forwarding node implies we support kwrest (**)
                    body->param.flags.has_kw = false;
                    body->param.flags.has_kwrest = true;
                    body->param.keyword = keyword = ZALLOC_N(struct rb_iseq_param_keyword, 1);

                    keyword->rest_start = local_index;

                    pm_insert_local_special(idPow, local_index++, index_lookup_table, local_table_for_iseq);

                    body->param.block_start = local_index;
                    body->param.flags.has_block = true;

                    pm_insert_local_special(idAnd, local_index++, index_lookup_table, local_table_for_iseq);
                    pm_insert_local_special(idDot3, local_index++, index_lookup_table, local_table_for_iseq);
                    break;
                  }
                  default: {
                    rb_bug("node type %s not expected as keyword_rest", pm_node_type_to_str(PM_NODE_TYPE(parameters_node->keyword_rest)));
                  }
                }
            }

            // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
            //                                                                  ^^
            if (parameters_node->block) {
                body->param.block_start = local_index;
                body->param.flags.has_block = true;

                pm_constant_id_t name = ((pm_block_parameter_node_t *) parameters_node->block)->name;

                if (name) {
                    if (PM_NODE_FLAG_P(parameters_node->block, PM_PARAMETER_FLAGS_REPEATED_PARAMETER)) {
                        ID local = pm_constant_id_lookup(scope_node, name);
                        local_table_for_iseq->ids[local_index] = local;
                    }
                    else {
                        pm_insert_local_index(name, local_index, index_lookup_table, local_table_for_iseq, scope_node);
                    }
                }
                else {
                    pm_insert_local_special(idAnd, local_index, index_lookup_table, local_table_for_iseq);
                }

                local_index++;
            }
        }

        //********END OF STEP 2**********
        // The local table is now consistent with expected
        // stack layout

        // If there's only one required element in the parameters
        // CRuby needs to recognize it as an ambiguous parameter

        //********STEP 3**********
        // Goal: fill in the names of the parameters in MultiTargetNodes
        //
        // Go through requireds again to set the multis

        if (requireds_list && requireds_list->size) {
            for (size_t i = 0; i < requireds_list->size; i++) {
                // For each MultiTargetNode, we're going to have one
                // additional anonymous local not represented in the locals table
                // We want to account for this in our table size
                const pm_node_t *required = requireds_list->nodes[i];

                if (PM_NODE_TYPE_P(required, PM_MULTI_TARGET_NODE)) {
                    local_index = pm_compile_destructured_param_locals((const pm_multi_target_node_t *) required, index_lookup_table, local_table_for_iseq, scope_node, local_index);
                }
            }
        }

        // Go through posts again to set the multis
        if (posts_list && posts_list->size) {
            for (size_t i = 0; i < posts_list->size; i++) {
                // For each MultiTargetNode, we're going to have one
                // additional anonymous local not represented in the locals table
                // We want to account for this in our table size
                const pm_node_t *post = posts_list->nodes[i];

                if (PM_NODE_TYPE_P(post, PM_MULTI_TARGET_NODE)) {
                    local_index = pm_compile_destructured_param_locals((const pm_multi_target_node_t *) post, index_lookup_table, local_table_for_iseq, scope_node, local_index);
                }
            }
        }

        // Set any anonymous locals for the for node
        if (PM_NODE_TYPE_P(scope_node->ast_node, PM_FOR_NODE)) {
            if (PM_NODE_TYPE_P(((const pm_for_node_t *) scope_node->ast_node)->index, PM_LOCAL_VARIABLE_TARGET_NODE)) {
                body->param.lead_num++;
            }
            else {
                body->param.rest_start = local_index;
                body->param.flags.has_rest = true;
            }

            ID local = rb_make_temporary_id(local_index);
            local_table_for_iseq->ids[local_index] = local;
            local_index++;
        }

        // Fill in any NumberedParameters, if they exist
        if (scope_node->parameters && PM_NODE_TYPE_P(scope_node->parameters, PM_NUMBERED_PARAMETERS_NODE)) {
            int maximum = ((pm_numbered_parameters_node_t *)scope_node->parameters)->maximum;
            RUBY_ASSERT(0 < maximum && maximum <= 9);
            for (int i = 0; i < maximum; i++, local_index++) {
                const uint8_t param_name[] = { '_', '1' + i };
                pm_constant_id_t constant_id = pm_constant_pool_find(&parser->constant_pool, param_name, 2);
                RUBY_ASSERT(constant_id && "parser should fill in any gaps in numbered parameters");
                pm_insert_local_index(constant_id, local_index, index_lookup_table, local_table_for_iseq, scope_node);
            }
            body->param.lead_num = maximum;
            body->param.flags.has_lead = true;
        }

        // Fill in the it variable, if it exists
        if (scope_node->parameters && PM_NODE_TYPE_P(scope_node->parameters, PM_IT_PARAMETERS_NODE)) {
            const uint8_t param_name[] = { '0', 'i', 't' };
            pm_constant_id_t constant_id = pm_constant_pool_find(&parser->constant_pool, param_name, 3);
            RUBY_ASSERT(constant_id && "parser should have inserted 0it for 'it' local");

            ID local = rb_make_temporary_id(local_index);
            local_table_for_iseq->ids[local_index] = local;
            st_insert(index_lookup_table, (st_data_t) constant_id, (st_data_t) local_index);
            local_index++;
        }

        //********END OF STEP 3**********

        //********STEP 4**********
        // Goal: fill in the method body locals
        // To be explicit, these are the non-parameter locals
        // We fill in the block_locals, if they exist
        // lambda { |x; y| y }
        //              ^
        if (block_locals && block_locals->size) {
            for (size_t i = 0; i < block_locals->size; i++, local_index++) {
                pm_constant_id_t constant_id = ((pm_block_local_variable_node_t *)block_locals->nodes[i])->name;
                pm_insert_local_index(constant_id, local_index, index_lookup_table, local_table_for_iseq, scope_node);
            }
        }

        // Fill in any locals we missed
        if (scope_node->locals.size) {
            for (size_t i = 0; i < scope_node->locals.size; i++) {
                pm_constant_id_t constant_id = locals->ids[i];
                if (constant_id) {
                    struct pm_local_table_insert_ctx ctx;
                    ctx.scope_node = scope_node;
                    ctx.local_table_for_iseq = local_table_for_iseq;
                    ctx.local_index = local_index;

                    st_update(index_lookup_table, (st_data_t)constant_id, pm_local_table_insert_func, (st_data_t)&ctx);

                    local_index = ctx.local_index;
                }
            }
        }

        //********END OF STEP 4**********

        // We set the index_lookup_table on the scope node so we can
        // refer to the parameters correctly
        if (scope_node->index_lookup_table) {
            st_free_table(scope_node->index_lookup_table);
        }
        scope_node->index_lookup_table = index_lookup_table;
        iseq_calc_param_size(iseq);
        iseq_set_local_table(iseq, local_table_for_iseq);
        scope_node->local_table_for_iseq_size = local_table_for_iseq->size;

        //********STEP 5************
        // Goal: compile anything that needed to be compiled
        if (optionals_list && optionals_list->size) {
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

            body->param.opt_table = (const VALUE *)opt_table;
        }

        if (keywords_list && keywords_list->size) {
            size_t optional_index = 0;
            for (size_t i = 0; i < keywords_list->size; i++) {
                pm_node_t *keyword_parameter_node = keywords_list->nodes[i];
                pm_constant_id_t name;

                switch (PM_NODE_TYPE(keyword_parameter_node)) {
                  // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                  //                                                       ^^^^
                  case PM_OPTIONAL_KEYWORD_PARAMETER_NODE: {
                    pm_optional_keyword_parameter_node_t *cast = ((pm_optional_keyword_parameter_node_t *)keyword_parameter_node);

                    pm_node_t *value = cast->value;
                    name = cast->name;

                    if (!PM_NODE_FLAG_P(value, PM_NODE_FLAG_STATIC_LITERAL) || PM_NODE_TYPE_P(value, PM_ARRAY_NODE) || PM_NODE_TYPE_P(value, PM_HASH_NODE) || PM_NODE_TYPE_P(value, PM_RANGE_NODE)) {
                        LABEL *end_label = NEW_LABEL(nd_line(&dummy_line_node));

                        pm_local_index_t index = pm_lookup_local_index(iseq, scope_node, name, 0);
                        int kw_bits_idx = table_size - body->param.keyword->bits_start;
                        ADD_INSN2(ret, &dummy_line_node, checkkeyword, INT2FIX(kw_bits_idx + VM_ENV_DATA_SIZE - 1), INT2FIX(optional_index));
                        ADD_INSNL(ret, &dummy_line_node, branchif, end_label);
                        PM_COMPILE(value);
                        ADD_SETLOCAL(ret, &dummy_line_node, index.index, index.level);

                        ADD_LABEL(ret, end_label);
                    }
                    optional_index++;
                    break;
                  }
                  // def foo(a, (b, *c, d), e = 1, *f, g, (h, *i, j), k:, l: 1, **m, &n)
                  //                                                   ^^
                  case PM_REQUIRED_KEYWORD_PARAMETER_NODE: {
                    break;
                  }
                  default: {
                    rb_bug("Unexpected keyword parameter node type %s", pm_node_type_to_str(PM_NODE_TYPE(keyword_parameter_node)));
                  }
                }
            }
        }

        if (requireds_list && requireds_list->size) {
            for (size_t i = 0; i < requireds_list->size; i++) {
                // For each MultiTargetNode, we're going to have one additional
                // anonymous local not represented in the locals table. We want
                // to account for this in our table size.
                const pm_node_t *required = requireds_list->nodes[i];

                if (PM_NODE_TYPE_P(required, PM_MULTI_TARGET_NODE)) {
                    ADD_GETLOCAL(ret, &dummy_line_node, table_size - (int)i, 0);
                    pm_compile_destructured_param_writes(iseq, (const pm_multi_target_node_t *) required, ret, scope_node);
                }
            }
        }

        if (posts_list && posts_list->size) {
            for (size_t i = 0; i < posts_list->size; i++) {
                // For each MultiTargetNode, we're going to have one additional
                // anonymous local not represented in the locals table. We want
                // to account for this in our table size.
                const pm_node_t *post = posts_list->nodes[i];

                if (PM_NODE_TYPE_P(post, PM_MULTI_TARGET_NODE)) {
                    ADD_GETLOCAL(ret, &dummy_line_node, table_size - body->param.post_start - (int) i, 0);
                    pm_compile_destructured_param_writes(iseq, (const pm_multi_target_node_t *) post, ret, scope_node);
                }
            }
        }

        switch (body->type) {
          case ISEQ_TYPE_BLOCK: {
            LABEL *start = ISEQ_COMPILE_DATA(iseq)->start_label = NEW_LABEL(0);
            LABEL *end = ISEQ_COMPILE_DATA(iseq)->end_label = NEW_LABEL(0);
            NODE dummy_line_node = generate_dummy_line_node(body->location.first_lineno, -1);

            start->rescued = LABEL_RESCUE_BEG;
            end->rescued = LABEL_RESCUE_END;

            // For nodes automatically assign the iteration variable to whatever
            // index variable. We need to handle that write here because it has
            // to happen in the context of the block. Note that this happens
            // before the B_CALL tracepoint event.
            if (PM_NODE_TYPE_P(scope_node->ast_node, PM_FOR_NODE)) {
                pm_compile_for_node_index(iseq, ((const pm_for_node_t *) scope_node->ast_node)->index, ret, scope_node);
            }

            ADD_TRACE(ret, RUBY_EVENT_B_CALL);
            PM_NOP;
            ADD_LABEL(ret, start);

            if (scope_node->body != NULL) {
                switch (PM_NODE_TYPE(scope_node->ast_node)) {
                  case PM_POST_EXECUTION_NODE: {
                    pm_post_execution_node_t *post_execution_node = (pm_post_execution_node_t *)scope_node->ast_node;

                    ADD_INSN1(ret, &dummy_line_node, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));

                    // We create another ScopeNode from the statements within the PostExecutionNode
                    pm_scope_node_t next_scope_node;
                    pm_scope_node_init((pm_node_t *)post_execution_node->statements, &next_scope_node, scope_node);
                    const rb_iseq_t *block = NEW_CHILD_ISEQ(&next_scope_node, make_name_for_block(body->parent_iseq), ISEQ_TYPE_BLOCK, lineno);
                    pm_scope_node_destroy(&next_scope_node);

                    ADD_CALL_WITH_BLOCK(ret, &dummy_line_node, id_core_set_postexe, INT2FIX(0), block);
                    break;
                  }
                  case PM_INTERPOLATED_REGULAR_EXPRESSION_NODE: {
                    const pm_interpolated_regular_expression_node_t *cast = (const pm_interpolated_regular_expression_node_t *) scope_node->ast_node;
                    pm_compile_regexp_dynamic(iseq, (const pm_node_t *) cast, &cast->parts, &location, ret, popped, scope_node);
                    break;
                  }
                  default:
                    pm_compile_node(iseq, scope_node->body, ret, popped, scope_node);
                    break;
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

            if (scope_node->body) {
                PM_COMPILE_POPPED((pm_node_t *)scope_node->body);
            }

            ADD_GETLOCAL(ret, &dummy_line_node, 1, 0);
            ADD_INSN1(ret, &dummy_line_node, throw, INT2FIX(0));
            return;
          }
          case ISEQ_TYPE_METHOD: {
            ADD_TRACE(ret, RUBY_EVENT_CALL);
            if (scope_node->body) {
                PM_COMPILE((pm_node_t *)scope_node->body);
            }
            else {
                PM_PUTNIL;
            }

            ADD_TRACE(ret, RUBY_EVENT_RETURN);
            ISEQ_COMPILE_DATA(iseq)->last_line = body->location.code_location.end_pos.lineno;

            break;
          }
          case ISEQ_TYPE_RESCUE: {
            iseq_set_exception_local_table(iseq);
            if (PM_NODE_TYPE_P(scope_node->ast_node, PM_RESCUE_MODIFIER_NODE)) {
                LABEL *lab = NEW_LABEL(lineno);
                LABEL *rescue_end = NEW_LABEL(lineno);
                ADD_GETLOCAL(ret, &dummy_line_node, LVAR_ERRINFO, 0);
                ADD_INSN1(ret, &dummy_line_node, putobject, rb_eStandardError);
                ADD_INSN1(ret, &dummy_line_node, checkmatch, INT2FIX(VM_CHECKMATCH_TYPE_RESCUE));
                ADD_INSNL(ret, &dummy_line_node, branchif, lab);
                ADD_INSNL(ret, &dummy_line_node, jump, rescue_end);
                ADD_LABEL(ret, lab);
                PM_COMPILE((pm_node_t *)scope_node->body);
                ADD_INSN(ret, &dummy_line_node, leave);
                ADD_LABEL(ret, rescue_end);
                ADD_GETLOCAL(ret, &dummy_line_node, LVAR_ERRINFO, 0);
            }
            else {
                PM_COMPILE((pm_node_t *)scope_node->ast_node);
            }
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
            break;
        }

        if (!PM_NODE_TYPE_P(scope_node->ast_node, PM_ENSURE_NODE)) {
            NODE dummy_line_node = generate_dummy_line_node(ISEQ_COMPILE_DATA(iseq)->last_line, -1);
            ADD_INSN(ret, &dummy_line_node, leave);
        }
        return;
      }
      case PM_SELF_NODE:
        // self
        // ^^^^
        if (!popped) {
            PUSH_INSN(ret, location, putself);
        }
        return;
      case PM_SHAREABLE_CONSTANT_NODE:
        // A value that is being written to a constant that is being marked as
        // shared depending on the current lexical context.
        PM_COMPILE(((const pm_shareable_constant_node_t *) node)->write);
        return;
      case PM_SINGLETON_CLASS_NODE: {
        // class << self; end
        // ^^^^^^^^^^^^^^^^^^
        const pm_singleton_class_node_t *cast = (const pm_singleton_class_node_t *) node;

        pm_scope_node_t next_scope_node;
        pm_scope_node_init((const pm_node_t *) cast, &next_scope_node, scope_node);
        const rb_iseq_t *child_iseq = NEW_ISEQ(&next_scope_node, rb_fstring_lit("singleton class"), ISEQ_TYPE_CLASS, location.line);
        pm_scope_node_destroy(&next_scope_node);

        PM_COMPILE_NOT_POPPED(cast->expression);
        PUSH_INSN(ret, location, putnil);

        ID singletonclass;
        CONST_ID(singletonclass, "singletonclass");
        PUSH_INSN3(ret, location, defineclass, ID2SYM(singletonclass), child_iseq, INT2FIX(VM_DEFINECLASS_TYPE_SINGLETON_CLASS));

        if (popped) PUSH_INSN(ret, location, pop);
        RB_OBJ_WRITTEN(iseq, Qundef, (VALUE) child_iseq);

        return;
      }
      case PM_SOURCE_ENCODING_NODE: {
        // __ENCODING__
        // ^^^^^^^^^^^^
        if (!popped) {
            VALUE value = pm_static_literal_value(iseq, node, scope_node);
            PUSH_INSN1(ret, location, putobject, value);
        }
        return;
      }
      case PM_SOURCE_FILE_NODE: {
        // __FILE__
        // ^^^^^^^^
        if (!popped) {
            const pm_source_file_node_t *cast = (const pm_source_file_node_t *) node;
            VALUE string = rb_fstring(parse_string(scope_node, &cast->filepath));

            if (PM_NODE_FLAG_P(cast, PM_STRING_FLAGS_FROZEN)) {
                PUSH_INSN1(ret, location, putobject, string);
            }
            else if (PM_NODE_FLAG_P(cast, PM_STRING_FLAGS_MUTABLE)) {
                PUSH_INSN1(ret, location, putstring, string);
            }
            else {
                PUSH_INSN1(ret, location, putchilledstring, string);
            }
        }
        return;
      }
      case PM_SOURCE_LINE_NODE: {
        // __LINE__
        // ^^^^^^^^
        if (!popped) {
            VALUE value = pm_static_literal_value(iseq, node, scope_node);
            PUSH_INSN1(ret, location, putobject, value);
        }
        return;
      }
      case PM_SPLAT_NODE: {
        // foo(*bar)
        //     ^^^^
        const pm_splat_node_t *cast = (const pm_splat_node_t *) node;
        if (cast->expression) {
            PM_COMPILE(cast->expression);
        }

        if (!popped) {
            PUSH_INSN1(ret, location, splatarray, Qtrue);
        }
        return;
      }
      case PM_STATEMENTS_NODE: {
        // A list of statements.
        const pm_statements_node_t *cast = (const pm_statements_node_t *) node;
        const pm_node_list_t *body = &cast->body;

        if (body->size > 0) {
            for (size_t index = 0; index < body->size - 1; index++) {
                PM_COMPILE_POPPED(body->nodes[index]);
            }
            PM_COMPILE(body->nodes[body->size - 1]);
        }
        else {
            PUSH_INSN(ret, location, putnil);
        }
        return;
      }
      case PM_STRING_NODE: {
        // "foo"
        // ^^^^^
        if (!popped) {
            const pm_string_node_t *cast = (const pm_string_node_t *) node;
            VALUE value = rb_fstring(parse_string_encoded(scope_node, node, &cast->unescaped));

            if (PM_NODE_FLAG_P(node, PM_STRING_FLAGS_FROZEN)) {
                PUSH_INSN1(ret, location, putobject, value);
            }
            else if (PM_NODE_FLAG_P(node, PM_STRING_FLAGS_MUTABLE)) {
                PUSH_INSN1(ret, location, putstring, value);
            }
            else {
                PUSH_INSN1(ret, location, putchilledstring, value);
            }
        }
        return;
      }
      case PM_SUPER_NODE: {
        // super(foo)
        // ^^^^^^^^^^
        const pm_super_node_t *cast = (const pm_super_node_t *) node;

        DECL_ANCHOR(args);
        INIT_ANCHOR(args);
        ISEQ_COMPILE_DATA(iseq)->current_block = NULL;

        PUSH_INSN(ret, location, putself);

        int flags = 0;
        struct rb_callinfo_kwarg *keywords = NULL;
        int argc = pm_setup_args(cast->arguments, cast->block, &flags, &keywords, iseq, ret, scope_node, dummy_line_node);
        flags |= VM_CALL_SUPER | VM_CALL_FCALL;

        const rb_iseq_t *parent_block = ISEQ_COMPILE_DATA(iseq)->current_block;
        if (cast->block && PM_NODE_TYPE_P(cast->block, PM_BLOCK_NODE)) {
            pm_scope_node_t next_scope_node;
            pm_scope_node_init(cast->block, &next_scope_node, scope_node);
            parent_block = NEW_CHILD_ISEQ(&next_scope_node, make_name_for_block(iseq), ISEQ_TYPE_BLOCK, lineno);
            pm_scope_node_destroy(&next_scope_node);
        }

        if ((flags & VM_CALL_ARGS_BLOCKARG) && (flags & VM_CALL_KW_SPLAT) && !(flags & VM_CALL_KW_SPLAT_MUT)) {
            PUSH_INSN(args, location, splatkw);
        }

        ADD_SEQ(ret, args);
        PUSH_INSN2(ret, location, invokesuper, new_callinfo(iseq, 0, argc, flags, keywords, parent_block != NULL), parent_block);

        if (popped) PUSH_INSN(ret, location, pop);
        return;
      }
      case PM_SYMBOL_NODE: {
        // :foo
        // ^^^^
        if (!popped) {
            VALUE value = pm_static_literal_value(iseq, node, scope_node);
            PUSH_INSN1(ret, location, putobject, value);
        }
        return;
      }
      case PM_TRUE_NODE:
        // true
        // ^^^^
        if (!popped) {
            PUSH_INSN1(ret, location, putobject, Qtrue);
        }
        return;
      case PM_UNDEF_NODE: {
        // undef foo
        // ^^^^^^^^^
        const pm_undef_node_t *cast = (const pm_undef_node_t *) node;
        const pm_node_list_t *names = &cast->names;

        for (size_t index = 0; index < names->size; index++) {
            PUSH_INSN1(ret, location, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_VMCORE));
            PUSH_INSN1(ret, location, putspecialobject, INT2FIX(VM_SPECIAL_OBJECT_CBASE));

            PM_COMPILE_NOT_POPPED(names->nodes[index]);
            PUSH_SEND(ret, location, id_core_undef_method, INT2NUM(2));

            if (index < names->size - 1) {
                PUSH_INSN(ret, location, pop);
            }
        }

        if (popped) PUSH_INSN(ret, location, pop);
        return;
      }
      case PM_UNLESS_NODE: {
        // unless foo; bar end
        // ^^^^^^^^^^^^^^^^^^^
        //
        // bar unless foo
        // ^^^^^^^^^^^^^^
        const pm_unless_node_t *cast = (const pm_unless_node_t *) node;
        const pm_statements_node_t *consequent = NULL;
        if (cast->consequent != NULL) {
            consequent = ((const pm_else_node_t *) cast->consequent)->statements;
        }

        pm_compile_conditional(iseq, &location, consequent, (const pm_node_t *) cast->statements, cast->predicate, ret, popped, scope_node);
        return;
      }
      case PM_UNTIL_NODE: {
        // until foo; bar end
        // ^^^^^^^^^^^^^^^^^
        //
        // bar until foo
        // ^^^^^^^^^^^^^
        const pm_until_node_t *cast = (const pm_until_node_t *) node;
        pm_compile_loop(iseq, &location, cast->base.flags, PM_UNTIL_NODE, cast->statements, cast->predicate, ret, popped, scope_node);
        return;
      }
      case PM_WHILE_NODE: {
        // while foo; bar end
        // ^^^^^^^^^^^^^^^^^^
        //
        // bar while foo
        // ^^^^^^^^^^^^^
        const pm_while_node_t *cast = (const pm_while_node_t *) node;
        pm_compile_loop(iseq, &location, cast->base.flags, PM_WHILE_NODE, cast->statements, cast->predicate, ret, popped, scope_node);
        return;
      }
      case PM_X_STRING_NODE: {
        // `foo`
        // ^^^^^
        const pm_x_string_node_t *cast = (const pm_x_string_node_t *) node;
        VALUE value = parse_string_encoded(scope_node, node, &cast->unescaped);

        PUSH_INSN(ret, location, putself);
        PUSH_INSN1(ret, location, putobject, value);
        PUSH_SEND_WITH_FLAG(ret, location, idBackquote, INT2NUM(1), INT2FIX(VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE));
        if (popped) PUSH_INSN(ret, location, pop);

        return;
      }
      case PM_YIELD_NODE: {
        // yield
        // ^^^^^
        //
        // yield 1
        // ^^^^^^^
        const pm_yield_node_t *cast = (const pm_yield_node_t *) node;

        switch (ISEQ_BODY(ISEQ_BODY(iseq)->local_iseq)->type) {
          case ISEQ_TYPE_TOP:
          case ISEQ_TYPE_MAIN:
          case ISEQ_TYPE_CLASS:
            COMPILE_ERROR(ERROR_ARGS "Invalid yield");
            return;
          default: /* valid */;
        }

        int argc = 0;
        int flags = 0;
        struct rb_callinfo_kwarg *keywords = NULL;

        if (cast->arguments) {
            argc = pm_setup_args(cast->arguments, NULL, &flags, &keywords, iseq, ret, scope_node, dummy_line_node);
        }

        PUSH_INSN1(ret, location, invokeblock, new_callinfo(iseq, 0, argc, flags, keywords, FALSE));
        if (popped) PUSH_INSN(ret, location, pop);

        int level = 0;
        for (const rb_iseq_t *tmp_iseq = iseq; tmp_iseq != ISEQ_BODY(iseq)->local_iseq; level++) {
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

/**
 * This is the main entry-point into the prism compiler. It accepts the iseq
 * that it should be compiling instruction into and a pointer to the scope node
 * that it should be compiling. It returns the established instruction sequence.
 * Note that this function could raise Ruby errors if it encounters compilation
 * errors or if there is a bug in the compiler.
 */
VALUE
pm_iseq_compile_node(rb_iseq_t *iseq, pm_scope_node_t *node)
{
    DECL_ANCHOR(ret);
    INIT_ANCHOR(ret);

    pm_compile_node(iseq, (const pm_node_t *) node, ret, false, node);

    CHECK(iseq_setup_insn(iseq, ret));
    return iseq_setup(iseq, ret);
}

/**
 * Free the internal memory associated with a pm_parse_result_t struct.
 * Importantly this does not free the struct itself.
 */
void
pm_parse_result_free(pm_parse_result_t *result)
{
    if (result->parsed) {
        pm_node_destroy(&result->parser, result->node.ast_node);
        pm_scope_node_destroy(&result->node);
    }

    pm_parser_free(&result->parser);
    pm_string_free(&result->input);
    pm_options_free(&result->options);
}

/**
 * Check if the given source slice is valid UTF-8. The location represents the
 * location of the error, but the slice of the source will include the content
 * of all of the lines that the error touches, so we need to check those parts
 * as well.
 */
static bool
pm_parse_process_error_utf8_p(const pm_parser_t *parser, const pm_location_t *location)
{
    const size_t start_line = pm_newline_list_line_column(&parser->newline_list, location->start, 1).line;
    const size_t end_line = pm_newline_list_line_column(&parser->newline_list, location->end, 1).line;

    const uint8_t *start = parser->start + parser->newline_list.offsets[start_line - 1];
    const uint8_t *end = ((end_line == parser->newline_list.size) ? parser->end : (parser->start + parser->newline_list.offsets[end_line]));
    size_t width;

    while (start < end) {
        if ((width = pm_encoding_utf_8_char_width(start, end - start)) == 0) return false;
        start += width;
    }

    return true;
}

/**
 * Generate an error object from the given parser that contains as much
 * information as possible about the errors that were encountered.
 */
static VALUE
pm_parse_process_error(const pm_parse_result_t *result)
{
    const pm_parser_t *parser = &result->parser;
    const pm_diagnostic_t *head = (const pm_diagnostic_t *) parser->error_list.head;
    bool valid_utf8 = true;

    pm_buffer_t buffer = { 0 };
    const pm_string_t *filepath = &parser->filepath;

    for (const pm_diagnostic_t *error = head; error != NULL; error = (const pm_diagnostic_t *) error->node.next) {
        // Any errors with the level PM_ERROR_LEVEL_ARGUMENT effectively take
        // over as the only argument that gets raised. This is to allow priority
        // messages that should be handled before anything else.
        if (error->level == PM_ERROR_LEVEL_ARGUMENT) {
            int32_t line_number = (int32_t) pm_location_line_number(parser, &error->location);

            pm_buffer_append_format(
                &buffer,
                "%.*s:%" PRIi32 ": %s",
                (int) pm_string_length(filepath),
                pm_string_source(filepath),
                line_number,
                error->message
            );

            if (pm_parse_process_error_utf8_p(parser, &error->location)) {
                pm_buffer_append_byte(&buffer, '\n');

                pm_list_node_t *list_node = (pm_list_node_t *) error;
                pm_list_t error_list = { .size = 1, .head = list_node, .tail = list_node };

                pm_parser_errors_format(parser, &error_list, &buffer, rb_stderr_tty_p(), false);
            }

            VALUE arg_error = rb_exc_new(rb_eArgError, pm_buffer_value(&buffer), pm_buffer_length(&buffer));
            pm_buffer_free(&buffer);

            return arg_error;
        }

        // It is implicitly assumed that the error messages will be encodeable
        // as UTF-8. Because of this, we can't include source examples that
        // contain invalid byte sequences. So if any source examples include
        // invalid UTF-8 byte sequences, we will skip showing source examples
        // entirely.
        if (valid_utf8 && !pm_parse_process_error_utf8_p(parser, &error->location)) {
            valid_utf8 = false;
        }
    }

    pm_buffer_append_format(
        &buffer,
        "%.*s:%" PRIi32 ": syntax error%s found\n",
        (int) pm_string_length(filepath),
        pm_string_source(filepath),
        (int32_t) pm_location_line_number(parser, &head->location),
        (parser->error_list.size > 1) ? "s" : ""
    );

    if (valid_utf8) {
        pm_parser_errors_format(parser, &parser->error_list, &buffer, rb_stderr_tty_p(), true);
    }
    else {
        for (const pm_diagnostic_t *error = head; error != NULL; error = (pm_diagnostic_t *) error->node.next) {
            if (error != head) pm_buffer_append_byte(&buffer, '\n');
            pm_buffer_append_format(&buffer, "%.*s:%" PRIi32 ": %s", (int) pm_string_length(filepath), pm_string_source(filepath), (int32_t) pm_location_line_number(parser, &error->location), error->message);
        }
    }

    VALUE error = rb_exc_new(rb_eSyntaxError, pm_buffer_value(&buffer), pm_buffer_length(&buffer));
    pm_buffer_free(&buffer);

    return error;
}

/**
 * Parse the parse result and raise a Ruby error if there are any syntax errors.
 * It returns an error if one should be raised. It is assumed that the parse
 * result object is zeroed out.
 */
static VALUE
pm_parse_process(pm_parse_result_t *result, pm_node_t *node)
{
    pm_parser_t *parser = &result->parser;

    // First, set up the scope node so that the AST node is attached and can be
    // freed regardless of whether or we return an error.
    pm_scope_node_t *scope_node = &result->node;
    pm_scope_node_init(node, scope_node, NULL);

    // If there are errors, raise an appropriate error and free the result.
    if (parser->error_list.size > 0) {
        VALUE error = pm_parse_process_error(result);

        // TODO: We need to set the backtrace.
        // rb_funcallv(error, rb_intern("set_backtrace"), 1, &path);
        return error;
    }

    // Emit all of the various warnings from the parse.
    const pm_diagnostic_t *warning;
    const char *warning_filepath = (const char *) pm_string_source(&parser->filepath);

    for (warning = (pm_diagnostic_t *) parser->warning_list.head; warning != NULL; warning = (pm_diagnostic_t *) warning->node.next) {
        int line = pm_location_line_number(parser, &warning->location);

        if (warning->level == PM_WARNING_LEVEL_VERBOSE) {
            rb_compile_warning(warning_filepath, line, "%s", warning->message);
        }
        else {
            rb_compile_warn(warning_filepath, line, "%s", warning->message);
        }
    }

    // Now set up the constant pool and intern all of the various constants into
    // their corresponding IDs.
    scope_node->encoding = rb_enc_find(parser->encoding->name);
    if (!scope_node->encoding) rb_bug("Encoding not found %s!", parser->encoding->name);

    scope_node->parser = parser;
    scope_node->constants = calloc(parser->constant_pool.size, sizeof(ID));

    for (uint32_t index = 0; index < parser->constant_pool.size; index++) {
        pm_constant_t *constant = &parser->constant_pool.constants[index];
        scope_node->constants[index] = rb_intern3((const char *) constant->start, constant->length, scope_node->encoding);
    }

    scope_node->index_lookup_table = st_init_numtable();
    pm_constant_id_list_t *locals = &scope_node->locals;
    for (size_t index = 0; index < locals->size; index++) {
        st_insert(scope_node->index_lookup_table, locals->ids[index], index);
    }

    // If we got here, this is a success and we can return Qnil to indicate that
    // no error should be raised.
    result->parsed = true;
    return Qnil;
}

/**
 * Set the frozen_string_literal option based on the default value used by the
 * CRuby compiler.
 */
static void
pm_options_frozen_string_literal_init(pm_options_t *options)
{
    int frozen_string_literal = rb_iseq_opt_frozen_string_literal();

    switch (frozen_string_literal) {
      case ISEQ_FROZEN_STRING_LITERAL_UNSET:
        break;
      case ISEQ_FROZEN_STRING_LITERAL_DISABLED:
        pm_options_frozen_string_literal_set(options, false);
        break;
      case ISEQ_FROZEN_STRING_LITERAL_ENABLED:
        pm_options_frozen_string_literal_set(options, true);
        break;
      default:
        rb_bug("pm_options_frozen_string_literal_init: invalid frozen_string_literal=%d", frozen_string_literal);
        break;
    }
}

/**
 * Returns an array of ruby String objects that represent the lines of the
 * source file that the given parser parsed.
 */
static inline VALUE
pm_parse_file_script_lines(const pm_scope_node_t *scope_node, const pm_parser_t *parser)
{
    const pm_newline_list_t *newline_list = &parser->newline_list;
    const char *start = (const char *) parser->start;
    const char *end = (const char *) parser->end;

    // If we end exactly on a newline, then there's no need to push on a final
    // segment. If we don't, then we need to push on the last offset up to the
    // end of the string.
    size_t last_offset = newline_list->offsets[newline_list->size - 1];
    bool last_push = start + last_offset != end;

    // Create the ruby strings that represent the lines of the source.
    VALUE lines = rb_ary_new_capa(newline_list->size - (last_push ? 0 : 1));

    for (size_t index = 0; index < newline_list->size - 1; index++) {
        size_t offset = newline_list->offsets[index];
        size_t length = newline_list->offsets[index + 1] - offset;

        rb_ary_push(lines, rb_enc_str_new(start + offset, length, scope_node->encoding));
    }

    // Push on the last line if we need to.
    if (last_push) {
        rb_ary_push(lines, rb_enc_str_new(start + last_offset, end - (start + last_offset), scope_node->encoding));
    }

    return lines;
}

/**
 * Attempt to load the file into memory. Return a Ruby error if the file cannot
 * be read.
 */
VALUE
pm_load_file(pm_parse_result_t *result, VALUE filepath)
{
    if (!pm_string_mapped_init(&result->input, RSTRING_PTR(filepath))) {
#ifdef _WIN32
        int e = rb_w32_map_errno(GetLastError());
#else
        int e = errno;
#endif

        VALUE err = rb_syserr_new(e, RSTRING_PTR(filepath));
        RB_GC_GUARD(filepath);
        return err;
    }

    pm_options_frozen_string_literal_init(&result->options);
    return Qnil;
}

/**
 * Parse the given filepath and store the resulting scope node in the given
 * parse result struct. It returns a Ruby error if the file cannot be read or
 * if it cannot be parsed properly. It is assumed that the parse result object
 * is zeroed out.
 */
VALUE
pm_parse_file(pm_parse_result_t *result, VALUE filepath)
{
    pm_options_filepath_set(&result->options, RSTRING_PTR(filepath));
    RB_GC_GUARD(filepath);

    pm_parser_init(&result->parser, pm_string_source(&result->input), pm_string_length(&result->input), &result->options);
    pm_node_t *node = pm_parse(&result->parser);

    VALUE error = pm_parse_process(result, node);

    // If we're parsing a filepath, then we need to potentially support the
    // SCRIPT_LINES__ constant, which can be a hash that has an array of lines
    // of every read file.
    ID id_script_lines = rb_intern("SCRIPT_LINES__");

    if (rb_const_defined_at(rb_cObject, id_script_lines)) {
        VALUE script_lines = rb_const_get_at(rb_cObject, id_script_lines);

        if (RB_TYPE_P(script_lines, T_HASH)) {
            rb_hash_aset(script_lines, filepath, pm_parse_file_script_lines(&result->node, &result->parser));
        }
    }

    return error;
}

/**
 * Load and then parse the given filepath. It returns a Ruby error if the file
 * cannot be read or if it cannot be parsed properly.
 */
VALUE
pm_load_parse_file(pm_parse_result_t *result, VALUE filepath)
{
    VALUE error = pm_load_file(result, filepath);
    if (NIL_P(error)) {
        error = pm_parse_file(result, filepath);
    }

    return error;
}

/**
 * Parse the given source that corresponds to the given filepath and store the
 * resulting scope node in the given parse result struct. It is assumed that the
 * parse result object is zeroed out. If the string fails to parse, then a Ruby
 * error is returned.
 */
VALUE
pm_parse_string(pm_parse_result_t *result, VALUE source, VALUE filepath)
{
    rb_encoding *encoding = rb_enc_get(source);
    if (!rb_enc_asciicompat(encoding)) {
        return rb_exc_new_cstr(rb_eArgError, "invalid source encoding");
    }

    pm_options_frozen_string_literal_init(&result->options);
    pm_string_constant_init(&result->input, RSTRING_PTR(source), RSTRING_LEN(source));
    pm_options_encoding_set(&result->options, rb_enc_name(encoding));

    pm_options_filepath_set(&result->options, RSTRING_PTR(filepath));
    RB_GC_GUARD(filepath);

    pm_parser_init(&result->parser, pm_string_source(&result->input), pm_string_length(&result->input), &result->options);
    pm_node_t *node = pm_parse(&result->parser);

    return pm_parse_process(result, node);
}

/**
 * An implementation of fgets that is suitable for use with Ruby IO objects.
 */
static char *
pm_parse_stdin_fgets(char *string, int size, void *stream)
{
    RUBY_ASSERT(size > 0);

    VALUE line = rb_funcall((VALUE) stream, rb_intern("gets"), 1, INT2FIX(size - 1));
    if (NIL_P(line)) {
        return NULL;
    }

    const char *cstr = StringValueCStr(line);
    size_t length = strlen(cstr);

    memcpy(string, cstr, length);
    string[length] = '\0';

    return string;
}

/**
 * Parse the source off STDIN and store the resulting scope node in the given
 * parse result struct. It is assumed that the parse result object is zeroed
 * out. If the stream fails to parse, then a Ruby error is returned.
 */
VALUE
pm_parse_stdin(pm_parse_result_t *result)
{
    pm_options_frozen_string_literal_init(&result->options);

    pm_buffer_t buffer;
    pm_node_t *node = pm_parse_stream(&result->parser, &buffer, (void *) rb_stdin, pm_parse_stdin_fgets, &result->options);

    // Copy the allocated buffer contents into the input string so that it gets
    // freed. At this point we've handed over ownership, so we don't need to
    // free the buffer itself.
    pm_string_owned_init(&result->input, (uint8_t *) pm_buffer_value(&buffer), pm_buffer_length(&buffer));

    return pm_parse_process(result, node);
}

#undef NEW_ISEQ
#define NEW_ISEQ OLD_ISEQ

#undef NEW_CHILD_ISEQ
#define NEW_CHILD_ISEQ OLD_CHILD_ISEQ
