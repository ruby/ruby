/**
 * @file diagnostic.h
 *
 * A list of diagnostics generated during parsing.
 */
#ifndef PRISM_DIAGNOSTIC_H
#define PRISM_DIAGNOSTIC_H

#include "prism/defines.h"
#include "prism/util/pm_list.h"

#include <stdbool.h>
#include <stdlib.h>
#include <assert.h>

/**
 * This struct represents a diagnostic generated during parsing.
 *
 * @extends pm_list_node_t
 */
typedef struct {
    /** The embedded base node. */
    pm_list_node_t node;

    /** A pointer to the start of the source that generated the diagnostic. */
    const uint8_t *start;

    /** A pointer to the end of the source that generated the diagnostic. */
    const uint8_t *end;

    /** The message associated with the diagnostic. */
    const char *message;

    /**
     * Whether or not the memory related to the message of this diagnostic is
     * owned by this diagnostic. If it is, it needs to be freed when the
     * diagnostic is freed.
     */
    bool owned;
} pm_diagnostic_t;

/**
 * The diagnostic IDs of all of the diagnostics, used to communicate the types
 * of errors between the parser and the user.
 */
typedef enum {
    PM_ERR_ALIAS_ARGUMENT,
    PM_ERR_AMPAMPEQ_MULTI_ASSIGN,
    PM_ERR_ARGUMENT_AFTER_BLOCK,
    PM_ERR_ARGUMENT_AFTER_FORWARDING_ELLIPSES,
    PM_ERR_ARGUMENT_BARE_HASH,
    PM_ERR_ARGUMENT_BLOCK_MULTI,
    PM_ERR_ARGUMENT_FORMAL_CLASS,
    PM_ERR_ARGUMENT_FORMAL_CONSTANT,
    PM_ERR_ARGUMENT_FORMAL_GLOBAL,
    PM_ERR_ARGUMENT_FORMAL_IVAR,
    PM_ERR_ARGUMENT_FORWARDING_UNBOUND,
    PM_ERR_ARGUMENT_NO_FORWARDING_AMP,
    PM_ERR_ARGUMENT_NO_FORWARDING_ELLIPSES,
    PM_ERR_ARGUMENT_NO_FORWARDING_STAR,
    PM_ERR_ARGUMENT_SPLAT_AFTER_ASSOC_SPLAT,
    PM_ERR_ARGUMENT_SPLAT_AFTER_SPLAT,
    PM_ERR_ARGUMENT_TERM_PAREN,
    PM_ERR_ARGUMENT_UNEXPECTED_BLOCK,
    PM_ERR_ARRAY_ELEMENT,
    PM_ERR_ARRAY_EXPRESSION,
    PM_ERR_ARRAY_EXPRESSION_AFTER_STAR,
    PM_ERR_ARRAY_SEPARATOR,
    PM_ERR_ARRAY_TERM,
    PM_ERR_BEGIN_LONELY_ELSE,
    PM_ERR_BEGIN_TERM,
    PM_ERR_BEGIN_UPCASE_BRACE,
    PM_ERR_BEGIN_UPCASE_TERM,
    PM_ERR_BEGIN_UPCASE_TOPLEVEL,
    PM_ERR_BLOCK_PARAM_LOCAL_VARIABLE,
    PM_ERR_BLOCK_PARAM_PIPE_TERM,
    PM_ERR_BLOCK_TERM_BRACE,
    PM_ERR_BLOCK_TERM_END,
    PM_ERR_CANNOT_PARSE_EXPRESSION,
    PM_ERR_CANNOT_PARSE_STRING_PART,
    PM_ERR_CASE_EXPRESSION_AFTER_CASE,
    PM_ERR_CASE_EXPRESSION_AFTER_WHEN,
    PM_ERR_CASE_MATCH_MISSING_PREDICATE,
    PM_ERR_CASE_MISSING_CONDITIONS,
    PM_ERR_CASE_TERM,
    PM_ERR_CLASS_IN_METHOD,
    PM_ERR_CLASS_NAME,
    PM_ERR_CLASS_SUPERCLASS,
    PM_ERR_CLASS_TERM,
    PM_ERR_CLASS_UNEXPECTED_END,
    PM_ERR_CONDITIONAL_ELSIF_PREDICATE,
    PM_ERR_CONDITIONAL_IF_PREDICATE,
    PM_ERR_CONDITIONAL_PREDICATE_TERM,
    PM_ERR_CONDITIONAL_TERM,
    PM_ERR_CONDITIONAL_TERM_ELSE,
    PM_ERR_CONDITIONAL_UNLESS_PREDICATE,
    PM_ERR_CONDITIONAL_UNTIL_PREDICATE,
    PM_ERR_CONDITIONAL_WHILE_PREDICATE,
    PM_ERR_CONSTANT_PATH_COLON_COLON_CONSTANT,
    PM_ERR_DEF_ENDLESS,
    PM_ERR_DEF_ENDLESS_SETTER,
    PM_ERR_DEF_NAME,
    PM_ERR_DEF_NAME_AFTER_RECEIVER,
    PM_ERR_DEF_PARAMS_TERM,
    PM_ERR_DEF_PARAMS_TERM_PAREN,
    PM_ERR_DEF_RECEIVER,
    PM_ERR_DEF_RECEIVER_TERM,
    PM_ERR_DEF_TERM,
    PM_ERR_DEFINED_EXPRESSION,
    PM_ERR_EMBDOC_TERM,
    PM_ERR_EMBEXPR_END,
    PM_ERR_EMBVAR_INVALID,
    PM_ERR_END_UPCASE_BRACE,
    PM_ERR_END_UPCASE_TERM,
    PM_ERR_ESCAPE_INVALID_CONTROL,
    PM_ERR_ESCAPE_INVALID_CONTROL_REPEAT,
    PM_ERR_ESCAPE_INVALID_HEXADECIMAL,
    PM_ERR_ESCAPE_INVALID_META,
    PM_ERR_ESCAPE_INVALID_META_REPEAT,
    PM_ERR_ESCAPE_INVALID_UNICODE,
    PM_ERR_ESCAPE_INVALID_UNICODE_CM_FLAGS,
    PM_ERR_ESCAPE_INVALID_UNICODE_LITERAL,
    PM_ERR_ESCAPE_INVALID_UNICODE_LONG,
    PM_ERR_ESCAPE_INVALID_UNICODE_TERM,
    PM_ERR_EXPECT_ARGUMENT,
    PM_ERR_EXPECT_EOL_AFTER_STATEMENT,
    PM_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ,
    PM_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ,
    PM_ERR_EXPECT_EXPRESSION_AFTER_COMMA,
    PM_ERR_EXPECT_EXPRESSION_AFTER_EQUAL,
    PM_ERR_EXPECT_EXPRESSION_AFTER_LESS_LESS,
    PM_ERR_EXPECT_EXPRESSION_AFTER_LPAREN,
    PM_ERR_EXPECT_EXPRESSION_AFTER_QUESTION,
    PM_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR,
    PM_ERR_EXPECT_EXPRESSION_AFTER_SPLAT,
    PM_ERR_EXPECT_EXPRESSION_AFTER_SPLAT_HASH,
    PM_ERR_EXPECT_EXPRESSION_AFTER_STAR,
    PM_ERR_EXPECT_IDENT_REQ_PARAMETER,
    PM_ERR_EXPECT_LPAREN_REQ_PARAMETER,
    PM_ERR_EXPECT_RBRACKET,
    PM_ERR_EXPECT_RPAREN,
    PM_ERR_EXPECT_RPAREN_AFTER_MULTI,
    PM_ERR_EXPECT_RPAREN_REQ_PARAMETER,
    PM_ERR_EXPECT_STRING_CONTENT,
    PM_ERR_EXPECT_WHEN_DELIMITER,
    PM_ERR_EXPRESSION_BARE_HASH,
    PM_ERR_FOR_COLLECTION,
    PM_ERR_FOR_IN,
    PM_ERR_FOR_INDEX,
    PM_ERR_FOR_TERM,
    PM_ERR_HASH_EXPRESSION_AFTER_LABEL,
    PM_ERR_HASH_KEY,
    PM_ERR_HASH_ROCKET,
    PM_ERR_HASH_TERM,
    PM_ERR_HASH_VALUE,
    PM_ERR_HEREDOC_TERM,
    PM_ERR_INCOMPLETE_QUESTION_MARK,
    PM_ERR_INCOMPLETE_VARIABLE_CLASS,
    PM_ERR_INCOMPLETE_VARIABLE_INSTANCE,
    PM_ERR_INVALID_ENCODING_MAGIC_COMMENT,
    PM_ERR_INVALID_FLOAT_EXPONENT,
    PM_ERR_INVALID_NUMBER_BINARY,
    PM_ERR_INVALID_NUMBER_DECIMAL,
    PM_ERR_INVALID_NUMBER_HEXADECIMAL,
    PM_ERR_INVALID_NUMBER_OCTAL,
    PM_ERR_INVALID_NUMBER_UNDERSCORE,
    PM_ERR_INVALID_PERCENT,
    PM_ERR_INVALID_TOKEN,
    PM_ERR_INVALID_VARIABLE_GLOBAL,
    PM_ERR_LAMBDA_OPEN,
    PM_ERR_LAMBDA_TERM_BRACE,
    PM_ERR_LAMBDA_TERM_END,
    PM_ERR_LIST_I_LOWER_ELEMENT,
    PM_ERR_LIST_I_LOWER_TERM,
    PM_ERR_LIST_I_UPPER_ELEMENT,
    PM_ERR_LIST_I_UPPER_TERM,
    PM_ERR_LIST_W_LOWER_ELEMENT,
    PM_ERR_LIST_W_LOWER_TERM,
    PM_ERR_LIST_W_UPPER_ELEMENT,
    PM_ERR_LIST_W_UPPER_TERM,
    PM_ERR_MALLOC_FAILED,
    PM_ERR_MODULE_IN_METHOD,
    PM_ERR_MODULE_NAME,
    PM_ERR_MODULE_TERM,
    PM_ERR_MULTI_ASSIGN_MULTI_SPLATS,
    PM_ERR_NOT_EXPRESSION,
    PM_ERR_NUMBER_LITERAL_UNDERSCORE,
    PM_ERR_NUMBERED_PARAMETER_NOT_ALLOWED,
    PM_ERR_NUMBERED_PARAMETER_OUTER_SCOPE,
    PM_ERR_OPERATOR_MULTI_ASSIGN,
    PM_ERR_OPERATOR_WRITE_ARGUMENTS,
    PM_ERR_OPERATOR_WRITE_BLOCK,
    PM_ERR_PARAMETER_ASSOC_SPLAT_MULTI,
    PM_ERR_PARAMETER_BLOCK_MULTI,
    PM_ERR_PARAMETER_CIRCULAR,
    PM_ERR_PARAMETER_METHOD_NAME,
    PM_ERR_PARAMETER_NAME_REPEAT,
    PM_ERR_PARAMETER_NO_DEFAULT,
    PM_ERR_PARAMETER_NO_DEFAULT_KW,
    PM_ERR_PARAMETER_NUMBERED_RESERVED,
    PM_ERR_PARAMETER_ORDER,
    PM_ERR_PARAMETER_SPLAT_MULTI,
    PM_ERR_PARAMETER_STAR,
    PM_ERR_PARAMETER_UNEXPECTED_FWD,
    PM_ERR_PARAMETER_WILD_LOOSE_COMMA,
    PM_ERR_PATTERN_EXPRESSION_AFTER_BRACKET,
    PM_ERR_PATTERN_EXPRESSION_AFTER_HROCKET,
    PM_ERR_PATTERN_EXPRESSION_AFTER_COMMA,
    PM_ERR_PATTERN_EXPRESSION_AFTER_IN,
    PM_ERR_PATTERN_EXPRESSION_AFTER_KEY,
    PM_ERR_PATTERN_EXPRESSION_AFTER_PAREN,
    PM_ERR_PATTERN_EXPRESSION_AFTER_PIN,
    PM_ERR_PATTERN_EXPRESSION_AFTER_PIPE,
    PM_ERR_PATTERN_EXPRESSION_AFTER_RANGE,
    PM_ERR_PATTERN_HASH_KEY,
    PM_ERR_PATTERN_HASH_KEY_LABEL,
    PM_ERR_PATTERN_IDENT_AFTER_HROCKET,
    PM_ERR_PATTERN_LABEL_AFTER_COMMA,
    PM_ERR_PATTERN_REST,
    PM_ERR_PATTERN_TERM_BRACE,
    PM_ERR_PATTERN_TERM_BRACKET,
    PM_ERR_PATTERN_TERM_PAREN,
    PM_ERR_PIPEPIPEEQ_MULTI_ASSIGN,
    PM_ERR_REGEXP_TERM,
    PM_ERR_RESCUE_EXPRESSION,
    PM_ERR_RESCUE_MODIFIER_VALUE,
    PM_ERR_RESCUE_TERM,
    PM_ERR_RESCUE_VARIABLE,
    PM_ERR_RETURN_INVALID,
    PM_ERR_STATEMENT_ALIAS,
    PM_ERR_STATEMENT_POSTEXE_END,
    PM_ERR_STATEMENT_PREEXE_BEGIN,
    PM_ERR_STATEMENT_UNDEF,
    PM_ERR_STRING_CONCATENATION,
    PM_ERR_STRING_INTERPOLATED_TERM,
    PM_ERR_STRING_LITERAL_TERM,
    PM_ERR_SYMBOL_INVALID,
    PM_ERR_SYMBOL_TERM_DYNAMIC,
    PM_ERR_SYMBOL_TERM_INTERPOLATED,
    PM_ERR_TERNARY_COLON,
    PM_ERR_TERNARY_EXPRESSION_FALSE,
    PM_ERR_TERNARY_EXPRESSION_TRUE,
    PM_ERR_UNARY_RECEIVER_BANG,
    PM_ERR_UNARY_RECEIVER_MINUS,
    PM_ERR_UNARY_RECEIVER_PLUS,
    PM_ERR_UNARY_RECEIVER_TILDE,
    PM_ERR_UNDEF_ARGUMENT,
    PM_ERR_UNTIL_TERM,
    PM_ERR_VOID_EXPRESSION,
    PM_ERR_WHILE_TERM,
    PM_ERR_WRITE_TARGET_READONLY,
    PM_ERR_WRITE_TARGET_UNEXPECTED,
    PM_ERR_XSTRING_TERM,
    PM_WARN_AMBIGUOUS_FIRST_ARGUMENT_MINUS,
    PM_WARN_AMBIGUOUS_FIRST_ARGUMENT_PLUS,
    PM_WARN_AMBIGUOUS_PREFIX_STAR,
    PM_WARN_AMBIGUOUS_SLASH,
    PM_WARN_END_IN_METHOD,

    /* This must be the last member. */
    PM_DIAGNOSTIC_ID_LEN,
} pm_diagnostic_id_t;

/**
 * Append a diagnostic to the given list of diagnostics that is using shared
 * memory for its message.
 *
 * @param list The list to append to.
 * @param start The start of the diagnostic.
 * @param end The end of the diagnostic.
 * @param diag_id The diagnostic ID.
 * @return Whether the diagnostic was successfully appended.
 */
bool pm_diagnostic_list_append(pm_list_t *list, const uint8_t *start, const uint8_t *end, pm_diagnostic_id_t diag_id);

/**
 * Append a diagnostic to the given list of diagnostics that is using a format
 * string for its message.
 *
 * @param list The list to append to.
 * @param start The start of the diagnostic.
 * @param end The end of the diagnostic.
 * @param diag_id The diagnostic ID.
 * @param ... The arguments to the format string for the message.
 * @return Whether the diagnostic was successfully appended.
 */
bool pm_diagnostic_list_append_format(pm_list_t *list, const uint8_t *start, const uint8_t *end, pm_diagnostic_id_t diag_id, ...);

/**
 * Deallocate the internal state of the given diagnostic list.
 *
 * @param list The list to deallocate.
 */
void pm_diagnostic_list_free(pm_list_t *list);

#endif
