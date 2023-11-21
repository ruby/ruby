#include "prism/diagnostic.h"

/**
 * ## Message composition
 *
 * When composing an error message, use sentence fragments.
 *
 * Try describing the property of the code that caused the error, rather than the rule that is being
 * violated. It may help to use a fragment that completes a sentence beginning, "The parser
 * encountered (a) ...". If appropriate, add a description of the rule violation (or other helpful
 * context) after a semicolon.
 *
 * For example:, instead of "Control escape sequence cannot be doubled", prefer:
 *
 * > "Invalid control escape sequence; control cannot be repeated"
 *
 * In some cases, where the failure is more general or syntax expectations are violated, it may make
 * more sense to use a fragment that completes a sentence beginning, "The parser ...".
 *
 * For example:
 *
 * > "Expected an expression after `(`"
 * > "Cannot parse the expression"
 *
 *
 * ## Message style guide
 *
 * - Use articles like "a", "an", and "the" when appropriate.
 *   - e.g., prefer "Cannot parse the expression" to "Cannot parse expression".
 * - Use the common name for tokens and nodes.
 *   - e.g., prefer "keyword splat" to "assoc splat"
 *   - e.g., prefer "embedded document" to "embdoc"
 * - Capitalize the initial word of the message.
 * - Use back ticks around token literals
 *   - e.g., "Expected a `=>` between the hash key and value"
 * - Do not use `.` or other punctuation at the end of the message.
 * - Do not use contractions like "can't". Prefer "cannot" to "can not".
 * - For tokens that can have multiple meanings, reference the token and its meaning.
 *   - e.g., "`*` splat argument" is clearer and more complete than "splat argument" or "`*` argument"
 *
 *
 * ## Error names (PM_ERR_*)
 *
 * - When appropriate, prefer node name to token name.
 *   - e.g., prefer "SPLAT" to "STAR" in the context of argument parsing.
 * - Prefer token name to common name.
 *   - e.g., prefer "STAR" to "ASTERISK".
 * - Try to order the words in the name from more general to more specific,
 *   - e.g., "INVALID_NUMBER_DECIMAL" is better than "DECIMAL_INVALID_NUMBER".
 *   - When in doubt, look for similar patterns and name them so that they are grouped when lexically
 *     sorted. See PM_ERR_ARGUMENT_NO_FORWARDING_* for an example.
 */
static const char* const diagnostic_messages[PM_DIAGNOSTIC_ID_LEN] = {
    [PM_ERR_ALIAS_ARGUMENT]                     = "Invalid argument being passed to `alias`; expected a bare word, symbol, constant, or global variable",
    [PM_ERR_AMPAMPEQ_MULTI_ASSIGN]              = "Unexpected `&&=` in a multiple assignment",
    [PM_ERR_ARGUMENT_AFTER_BLOCK]               = "Unexpected argument after a block argument",
    [PM_ERR_ARGUMENT_AFTER_FORWARDING_ELLIPSES] = "Unexpected argument after `...`",
    [PM_ERR_ARGUMENT_BARE_HASH]                 = "Unexpected bare hash argument",
    [PM_ERR_ARGUMENT_BLOCK_MULTI]               = "Multiple block arguments; only one block is allowed",
    [PM_ERR_ARGUMENT_FORMAL_CLASS]              = "Invalid formal argument; formal argument cannot be a class variable",
    [PM_ERR_ARGUMENT_FORMAL_CONSTANT]           = "Invalid formal argument; formal argument cannot be a constant",
    [PM_ERR_ARGUMENT_FORMAL_GLOBAL]             = "Invalid formal argument; formal argument cannot be a global variable",
    [PM_ERR_ARGUMENT_FORMAL_IVAR]               = "Invalid formal argument; formal argument cannot be an instance variable",
    [PM_ERR_ARGUMENT_FORWARDING_UNBOUND]        = "Unexpected `...` in an non-parenthesized call",
    [PM_ERR_ARGUMENT_NO_FORWARDING_AMP]         = "Unexpected `&` when the parent method is not forwarding",
    [PM_ERR_ARGUMENT_NO_FORWARDING_ELLIPSES]    = "Unexpected `...` when the parent method is not forwarding",
    [PM_ERR_ARGUMENT_NO_FORWARDING_STAR]        = "Unexpected `*` when the parent method is not forwarding",
    [PM_ERR_ARGUMENT_SPLAT_AFTER_ASSOC_SPLAT]   = "Unexpected `*` splat argument after a `**` keyword splat argument",
    [PM_ERR_ARGUMENT_SPLAT_AFTER_SPLAT]         = "Unexpected `*` splat argument after a `*` splat argument",
    [PM_ERR_ARGUMENT_TERM_PAREN]                = "Expected a `)` to close the arguments",
    [PM_ERR_ARGUMENT_UNEXPECTED_BLOCK]          = "Unexpected `{` after a method call without parenthesis",
    [PM_ERR_ARRAY_ELEMENT]                      = "Expected an element for the array",
    [PM_ERR_ARRAY_EXPRESSION]                   = "Expected an expression for the array element",
    [PM_ERR_ARRAY_EXPRESSION_AFTER_STAR]        = "Expected an expression after `*` in the array",
    [PM_ERR_ARRAY_SEPARATOR]                    = "Expected a `,` separator for the array elements",
    [PM_ERR_ARRAY_TERM]                         = "Expected a `]` to close the array",
    [PM_ERR_BEGIN_LONELY_ELSE]                  = "Unexpected `else` in `begin` block; a `rescue` clause must precede `else`",
    [PM_ERR_BEGIN_TERM]                         = "Expected an `end` to close the `begin` statement",
    [PM_ERR_BEGIN_UPCASE_BRACE]                 = "Expected a `{` after `BEGIN`",
    [PM_ERR_BEGIN_UPCASE_TERM]                  = "Expected a `}` to close the `BEGIN` statement",
    [PM_ERR_BEGIN_UPCASE_TOPLEVEL]              = "BEGIN is permitted only at toplevel",
    [PM_ERR_BLOCK_PARAM_LOCAL_VARIABLE]         = "Expected a local variable name in the block parameters",
    [PM_ERR_BLOCK_PARAM_PIPE_TERM]              = "Expected the block parameters to end with `|`",
    [PM_ERR_BLOCK_TERM_BRACE]                   = "Expected a block beginning with `{` to end with `}`",
    [PM_ERR_BLOCK_TERM_END]                     = "Expected a block beginning with `do` to end with `end`",
    [PM_ERR_CANNOT_PARSE_EXPRESSION]            = "Cannot parse the expression",
    [PM_ERR_CANNOT_PARSE_STRING_PART]           = "Cannot parse the string part",
    [PM_ERR_CASE_EXPRESSION_AFTER_CASE]         = "Expected an expression after `case`",
    [PM_ERR_CASE_EXPRESSION_AFTER_WHEN]         = "Expected an expression after `when`",
    [PM_ERR_CASE_MATCH_MISSING_PREDICATE]       = "Expected a predicate for a case matching statement",
    [PM_ERR_CASE_MISSING_CONDITIONS]            = "Expected a `when` or `in` clause after `case`",
    [PM_ERR_CASE_TERM]                          = "Expected an `end` to close the `case` statement",
    [PM_ERR_CLASS_IN_METHOD]                    = "Unexpected class definition in a method body",
    [PM_ERR_CLASS_NAME]                         = "Expected a constant name after `class`",
    [PM_ERR_CLASS_SUPERCLASS]                   = "Expected a superclass after `<`",
    [PM_ERR_CLASS_TERM]                         = "Expected an `end` to close the `class` statement",
    [PM_ERR_CLASS_UNEXPECTED_END]               = "Unexpected `end`, expecting ';' or '\n'",
    [PM_ERR_CONDITIONAL_ELSIF_PREDICATE]        = "Expected a predicate expression for the `elsif` statement",
    [PM_ERR_CONDITIONAL_IF_PREDICATE]           = "Expected a predicate expression for the `if` statement",
    [PM_ERR_CONDITIONAL_PREDICATE_TERM]         = "Expected `then` or `;` or '\n'",
    [PM_ERR_CONDITIONAL_TERM]                   = "Expected an `end` to close the conditional clause",
    [PM_ERR_CONDITIONAL_TERM_ELSE]              = "Expected an `end` to close the `else` clause",
    [PM_ERR_CONDITIONAL_UNLESS_PREDICATE]       = "Expected a predicate expression for the `unless` statement",
    [PM_ERR_CONDITIONAL_UNTIL_PREDICATE]        = "Expected a predicate expression for the `until` statement",
    [PM_ERR_CONDITIONAL_WHILE_PREDICATE]        = "Expected a predicate expression for the `while` statement",
    [PM_ERR_CONSTANT_PATH_COLON_COLON_CONSTANT] = "Expected a constant after the `::` operator",
    [PM_ERR_DEF_ENDLESS]                        = "Could not parse the endless method body",
    [PM_ERR_DEF_ENDLESS_SETTER]                 = "Invalid method name; a setter method cannot be defined in an endless method definition",
    [PM_ERR_DEF_NAME]                           = "Expected a method name",
    [PM_ERR_DEF_NAME_AFTER_RECEIVER]            = "Expected a method name after the receiver",
    [PM_ERR_DEF_PARAMS_TERM]                    = "Expected a delimiter to close the parameters",
    [PM_ERR_DEF_PARAMS_TERM_PAREN]              = "Expected a `)` to close the parameters",
    [PM_ERR_DEF_RECEIVER]                       = "Expected a receiver for the method definition",
    [PM_ERR_DEF_RECEIVER_TERM]                  = "Expected a `.` or `::` after the receiver in a method definition",
    [PM_ERR_DEF_TERM]                           = "Expected an `end` to close the `def` statement",
    [PM_ERR_DEFINED_EXPRESSION]                 = "Expected an expression after `defined?`",
    [PM_ERR_EMBDOC_TERM]                        = "Could not find a terminator for the embedded document",
    [PM_ERR_EMBEXPR_END]                        = "Expected a `}` to close the embedded expression",
    [PM_ERR_EMBVAR_INVALID]                     = "Invalid embedded variable",
    [PM_ERR_END_UPCASE_BRACE]                   = "Expected a `{` after `END`",
    [PM_ERR_END_UPCASE_TERM]                    = "Expected a `}` to close the `END` statement",
    [PM_ERR_ESCAPE_INVALID_CONTROL]             = "Invalid control escape sequence",
    [PM_ERR_ESCAPE_INVALID_CONTROL_REPEAT]      = "Invalid control escape sequence; control cannot be repeated",
    [PM_ERR_ESCAPE_INVALID_HEXADECIMAL]         = "Invalid hexadecimal escape sequence",
    [PM_ERR_ESCAPE_INVALID_META]                = "Invalid meta escape sequence",
    [PM_ERR_ESCAPE_INVALID_META_REPEAT]         = "Invalid meta escape sequence; meta cannot be repeated",
    [PM_ERR_ESCAPE_INVALID_UNICODE]             = "Invalid Unicode escape sequence",
    [PM_ERR_ESCAPE_INVALID_UNICODE_CM_FLAGS]    = "Invalid Unicode escape sequence; Unicode cannot be combined with control or meta flags",
    [PM_ERR_ESCAPE_INVALID_UNICODE_LITERAL]     = "Invalid Unicode escape sequence; multiple codepoints are not allowed in a character literal",
    [PM_ERR_ESCAPE_INVALID_UNICODE_LONG]        = "Invalid Unicode escape sequence; maximum length is 6 digits",
    [PM_ERR_ESCAPE_INVALID_UNICODE_TERM]        = "Invalid Unicode escape sequence; needs closing `}`",
    [PM_ERR_EXPECT_ARGUMENT]                    = "Expected an argument",
    [PM_ERR_EXPECT_EOL_AFTER_STATEMENT]         = "Expected a newline or semicolon after the statement",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ]   = "Expected an expression after `&&=`",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ] = "Expected an expression after `||=`",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_COMMA]      = "Expected an expression after `,`",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_EQUAL]      = "Expected an expression after `=`",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_LESS_LESS]  = "Expected an expression after `<<`",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_LPAREN]     = "Expected an expression after `(`",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR]   = "Expected an expression after the operator",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_SPLAT]      = "Expected an expression after `*` splat in an argument",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_SPLAT_HASH] = "Expected an expression after `**` in a hash",
    [PM_ERR_EXPECT_EXPRESSION_AFTER_STAR]       = "Expected an expression after `*`",
    [PM_ERR_EXPECT_IDENT_REQ_PARAMETER]         = "Expected an identifier for the required parameter",
    [PM_ERR_EXPECT_LPAREN_REQ_PARAMETER]        = "Expected a `(` to start a required parameter",
    [PM_ERR_EXPECT_RBRACKET]                    = "Expected a matching `]`",
    [PM_ERR_EXPECT_RPAREN]                      = "Expected a matching `)`",
    [PM_ERR_EXPECT_RPAREN_AFTER_MULTI]          = "Expected a `)` after multiple assignment",
    [PM_ERR_EXPECT_RPAREN_REQ_PARAMETER]        = "Expected a `)` to end a required parameter",
    [PM_ERR_EXPECT_STRING_CONTENT]              = "Expected string content after opening string delimiter",
    [PM_ERR_EXPECT_WHEN_DELIMITER]              = "Expected a delimiter after the predicates of a `when` clause",
    [PM_ERR_EXPRESSION_BARE_HASH]               = "Unexpected bare hash in expression",
    [PM_ERR_FOR_COLLECTION]                     = "Expected a collection after the `in` in a `for` statement",
    [PM_ERR_FOR_INDEX]                          = "Expected an index after `for`",
    [PM_ERR_FOR_IN]                             = "Expected an `in` after the index in a `for` statement",
    [PM_ERR_FOR_TERM]                           = "Expected an `end` to close the `for` loop",
    [PM_ERR_HASH_EXPRESSION_AFTER_LABEL]        = "Expected an expression after the label in a hash",
    [PM_ERR_HASH_KEY]                           = "Expected a key in the hash literal",
    [PM_ERR_HASH_ROCKET]                        = "Expected a `=>` between the hash key and value",
    [PM_ERR_HASH_TERM]                          = "Expected a `}` to close the hash literal",
    [PM_ERR_HASH_VALUE]                         = "Expected a value in the hash literal",
    [PM_ERR_HEREDOC_TERM]                       = "Could not find a terminator for the heredoc",
    [PM_ERR_INCOMPLETE_QUESTION_MARK]           = "Incomplete expression at `?`",
    [PM_ERR_INCOMPLETE_VARIABLE_CLASS]          = "Incomplete class variable",
    [PM_ERR_INCOMPLETE_VARIABLE_INSTANCE]       = "Incomplete instance variable",
    [PM_ERR_INVALID_ENCODING_MAGIC_COMMENT]     = "Unknown or invalid encoding in the magic comment",
    [PM_ERR_INVALID_FLOAT_EXPONENT]             = "Invalid exponent",
    [PM_ERR_INVALID_NUMBER_BINARY]              = "Invalid binary number",
    [PM_ERR_INVALID_NUMBER_DECIMAL]             = "Invalid decimal number",
    [PM_ERR_INVALID_NUMBER_HEXADECIMAL]         = "Invalid hexadecimal number",
    [PM_ERR_INVALID_NUMBER_OCTAL]               = "Invalid octal number",
    [PM_ERR_INVALID_NUMBER_UNDERSCORE]          = "Invalid underscore placement in number",
    [PM_ERR_INVALID_PERCENT]                    = "Invalid `%` token", // TODO WHAT?
    [PM_ERR_INVALID_TOKEN]                      = "Invalid token", // TODO WHAT?
    [PM_ERR_INVALID_VARIABLE_GLOBAL]            = "Invalid global variable",
    [PM_ERR_LAMBDA_OPEN]                        = "Expected a `do` keyword or a `{` to open the lambda block",
    [PM_ERR_LAMBDA_TERM_BRACE]                  = "Expected a lambda block beginning with `{` to end with `}`",
    [PM_ERR_LAMBDA_TERM_END]                    = "Expected a lambda block beginning with `do` to end with `end`",
    [PM_ERR_LIST_I_LOWER_ELEMENT]               = "Expected a symbol in a `%i` list",
    [PM_ERR_LIST_I_LOWER_TERM]                  = "Expected a closing delimiter for the `%i` list",
    [PM_ERR_LIST_I_UPPER_ELEMENT]               = "Expected a symbol in a `%I` list",
    [PM_ERR_LIST_I_UPPER_TERM]                  = "Expected a closing delimiter for the `%I` list",
    [PM_ERR_LIST_W_LOWER_ELEMENT]               = "Expected a string in a `%w` list",
    [PM_ERR_LIST_W_LOWER_TERM]                  = "Expected a closing delimiter for the `%w` list",
    [PM_ERR_LIST_W_UPPER_ELEMENT]               = "Expected a string in a `%W` list",
    [PM_ERR_LIST_W_UPPER_TERM]                  = "Expected a closing delimiter for the `%W` list",
    [PM_ERR_MALLOC_FAILED]                      = "Failed to allocate memory",
    [PM_ERR_MODULE_IN_METHOD]                   = "Unexpected module definition in a method body",
    [PM_ERR_MODULE_NAME]                        = "Expected a constant name after `module`",
    [PM_ERR_MODULE_TERM]                        = "Expected an `end` to close the `module` statement",
    [PM_ERR_MULTI_ASSIGN_MULTI_SPLATS]          = "Multiple splats in multiple assignment",
    [PM_ERR_NOT_EXPRESSION]                     = "Expected an expression after `not`",
    [PM_ERR_NUMBER_LITERAL_UNDERSCORE]          = "Number literal ending with a `_`",
    [PM_ERR_NUMBERED_PARAMETER_NOT_ALLOWED]     = "Numbered parameters are not allowed alongside explicit parameters",
    [PM_ERR_NUMBERED_PARAMETER_OUTER_SCOPE]     = "Numbered parameter is already used in outer scope",
    [PM_ERR_OPERATOR_MULTI_ASSIGN]              = "Unexpected operator for a multiple assignment",
    [PM_ERR_OPERATOR_WRITE_ARGUMENTS]           = "Unexpected operator after a call with arguments",
    [PM_ERR_OPERATOR_WRITE_BLOCK]               = "Unexpected operator after a call with a block",
    [PM_ERR_PARAMETER_ASSOC_SPLAT_MULTI]        = "Unexpected multiple `**` splat parameters",
    [PM_ERR_PARAMETER_BLOCK_MULTI]              = "Multiple block parameters; only one block is allowed",
    [PM_ERR_PARAMETER_METHOD_NAME]              = "Unexpected name for a parameter",
    [PM_ERR_PARAMETER_NAME_REPEAT]              = "Repeated parameter name",
    [PM_ERR_PARAMETER_NO_DEFAULT]               = "Expected a default value for the parameter",
    [PM_ERR_PARAMETER_NO_DEFAULT_KW]            = "Expected a default value for the keyword parameter",
    [PM_ERR_PARAMETER_NUMBERED_RESERVED]        = "%.2s is reserved for a numbered parameter",
    [PM_ERR_PARAMETER_ORDER]                    = "Unexpected parameter order",
    [PM_ERR_PARAMETER_SPLAT_MULTI]              = "Unexpected multiple `*` splat parameters",
    [PM_ERR_PARAMETER_STAR]                     = "Unexpected parameter `*`",
    [PM_ERR_PARAMETER_UNEXPECTED_FWD]           = "Unexpected `...` in parameters",
    [PM_ERR_PARAMETER_WILD_LOOSE_COMMA]         = "Unexpected `,` in parameters",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_BRACKET]   = "Expected a pattern expression after the `[` operator",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_COMMA]     = "Expected a pattern expression after `,`",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_HROCKET]   = "Expected a pattern expression after `=>`",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_IN]        = "Expected a pattern expression after the `in` keyword",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_KEY]       = "Expected a pattern expression after the key",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_PAREN]     = "Expected a pattern expression after the `(` operator",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_PIN]       = "Expected a pattern expression after the `^` pin operator",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_PIPE]      = "Expected a pattern expression after the `|` operator",
    [PM_ERR_PATTERN_EXPRESSION_AFTER_RANGE]     = "Expected a pattern expression after the range operator",
    [PM_ERR_PATTERN_HASH_KEY]                   = "Expected a key in the hash pattern",
    [PM_ERR_PATTERN_HASH_KEY_LABEL]             = "Expected a label as the key in the hash pattern", // TODO // THIS // AND // ABOVE // IS WEIRD
    [PM_ERR_PATTERN_IDENT_AFTER_HROCKET]        = "Expected an identifier after the `=>` operator",
    [PM_ERR_PATTERN_LABEL_AFTER_COMMA]          = "Expected a label after the `,` in the hash pattern",
    [PM_ERR_PATTERN_REST]                       = "Unexpected rest pattern",
    [PM_ERR_PATTERN_TERM_BRACE]                 = "Expected a `}` to close the pattern expression",
    [PM_ERR_PATTERN_TERM_BRACKET]               = "Expected a `]` to close the pattern expression",
    [PM_ERR_PATTERN_TERM_PAREN]                 = "Expected a `)` to close the pattern expression",
    [PM_ERR_PIPEPIPEEQ_MULTI_ASSIGN]            = "Unexpected `||=` in a multiple assignment",
    [PM_ERR_REGEXP_TERM]                        = "Expected a closing delimiter for the regular expression",
    [PM_ERR_RESCUE_EXPRESSION]                  = "Expected a rescued expression",
    [PM_ERR_RESCUE_MODIFIER_VALUE]              = "Expected a value after the `rescue` modifier",
    [PM_ERR_RESCUE_TERM]                        = "Expected a closing delimiter for the `rescue` clause",
    [PM_ERR_RESCUE_VARIABLE]                    = "Expected an exception variable after `=>` in a rescue statement",
    [PM_ERR_RETURN_INVALID]                     = "Invalid `return` in a class or module body",
    [PM_ERR_STRING_CONCATENATION]               = "Expected a string for concatenation",
    [PM_ERR_STRING_INTERPOLATED_TERM]           = "Expected a closing delimiter for the interpolated string",
    [PM_ERR_STRING_LITERAL_TERM]                = "Expected a closing delimiter for the string literal",
    [PM_ERR_SYMBOL_INVALID]                     = "Invalid symbol", // TODO expected symbol? prism.c ~9719
    [PM_ERR_SYMBOL_TERM_DYNAMIC]                = "Expected a closing delimiter for the dynamic symbol",
    [PM_ERR_SYMBOL_TERM_INTERPOLATED]           = "Expected a closing delimiter for the interpolated symbol",
    [PM_ERR_TERNARY_COLON]                      = "Expected a `:` after the true expression of a ternary operator",
    [PM_ERR_TERNARY_EXPRESSION_FALSE]           = "Expected an expression after `:` in the ternary operator",
    [PM_ERR_TERNARY_EXPRESSION_TRUE]            = "Expected an expression after `?` in the ternary operator",
    [PM_ERR_UNDEF_ARGUMENT]                     = "Invalid argument being passed to `undef`; expected a bare word, constant, or symbol argument",
    [PM_ERR_UNARY_RECEIVER_BANG]                = "Expected a receiver for unary `!`",
    [PM_ERR_UNARY_RECEIVER_MINUS]               = "Expected a receiver for unary `-`",
    [PM_ERR_UNARY_RECEIVER_PLUS]                = "Expected a receiver for unary `+`",
    [PM_ERR_UNARY_RECEIVER_TILDE]               = "Expected a receiver for unary `~`",
    [PM_ERR_UNTIL_TERM]                         = "Expected an `end` to close the `until` statement",
    [PM_ERR_VOID_EXPRESSION]                    = "Unexpected void value expression",
    [PM_ERR_WHILE_TERM]                         = "Expected an `end` to close the `while` statement",
    [PM_ERR_WRITE_TARGET_READONLY]              = "Immutable variable as a write target",
    [PM_ERR_WRITE_TARGET_UNEXPECTED]            = "Unexpected write target",
    [PM_ERR_XSTRING_TERM]                       = "Expected a closing delimiter for the `%x` or backtick string",
    [PM_WARN_AMBIGUOUS_FIRST_ARGUMENT_MINUS]    = "Ambiguous first argument; put parentheses or a space even after `-` operator",
    [PM_WARN_AMBIGUOUS_FIRST_ARGUMENT_PLUS]     = "Ambiguous first argument; put parentheses or a space even after `+` operator",
    [PM_WARN_AMBIGUOUS_PREFIX_STAR]             = "Ambiguous `*` has been interpreted as an argument prefix",
    [PM_WARN_AMBIGUOUS_SLASH]                   = "Ambiguous `/`; wrap regexp in parentheses or add a space after `/` operator",
    [PM_WARN_END_IN_METHOD]                     = "END in method; use at_exit",
};

static const char*
pm_diagnostic_message(pm_diagnostic_id_t diag_id) {
    assert(diag_id < PM_DIAGNOSTIC_ID_LEN);

    const char *message = diagnostic_messages[diag_id];
    assert(message);

    return message;
}

/**
 * Append an error to the given list of diagnostic.
 */
bool
pm_diagnostic_list_append(pm_list_t *list, const uint8_t *start, const uint8_t *end, pm_diagnostic_id_t diag_id) {
    pm_diagnostic_t *diagnostic = (pm_diagnostic_t *) calloc(sizeof(pm_diagnostic_t), 1);
    if (diagnostic == NULL) return false;

    *diagnostic = (pm_diagnostic_t) {
        .start = start,
        .end = end,
        .message = pm_diagnostic_message(diag_id),
        .owned = false
    };

    pm_list_append(list, (pm_list_node_t *) diagnostic);
    return true;
}

/**
 * Append a diagnostic to the given list of diagnostics that is using a format
 * string for its message.
 */
bool
pm_diagnostic_list_append_format(pm_list_t *list, const uint8_t *start, const uint8_t *end, pm_diagnostic_id_t diag_id, ...) {
    va_list arguments;
    va_start(arguments, diag_id);

    const char *format = pm_diagnostic_message(diag_id);
    int result = vsnprintf(NULL, 0, format, arguments);
    va_end(arguments);

    if (result < 0) {
        return false;
    }

    pm_diagnostic_t *diagnostic = (pm_diagnostic_t *) calloc(sizeof(pm_diagnostic_t), 1);
    if (diagnostic == NULL) {
        return false;
    }

    size_t length = (size_t) (result + 1);
    char *message = (char *) malloc(length);
    if (message == NULL) {
        free(diagnostic);
        return false;
    }

    va_start(arguments, diag_id);
    vsnprintf(message, length, format, arguments);
    va_end(arguments);

    *diagnostic = (pm_diagnostic_t) {
        .start = start,
        .end = end,
        .message = message,
        .owned = true
    };

    pm_list_append(list, (pm_list_node_t *) diagnostic);
    return true;
}

/**
 * Deallocate the internal state of the given diagnostic list.
 */
void
pm_diagnostic_list_free(pm_list_t *list) {
    pm_list_node_t *node, *next;

    for (node = list->head; node != NULL; node = next) {
        next = node->next;
        pm_diagnostic_t *diagnostic = (pm_diagnostic_t *) node;

        if (diagnostic->owned) free((void *) diagnostic->message);
        free(diagnostic);
    }
}
