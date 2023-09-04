#include "yarp/diagnostic.h"

/*
  ## Message composition

  When composing an error message, use sentence fragments.

  Try describing the property of the code that caused the error, rather than the rule that is being
  violated. It may help to use a fragment that completes a sentence beginning, "The parser
  encountered (a) ...". If appropriate, add a description of the rule violation (or other helpful
  context) after a semicolon.

  For example:, instead of "Control escape sequence cannot be doubled", prefer:

  > "Invalid control escape sequence; control cannot be repeated"

  In some cases, where the failure is more general or syntax expectations are violated, it may make
  more sense to use a fragment that completes a sentence beginning, "The parser ...".

  For example:

  > "Expected an expression after `(`"
  > "Cannot parse the expression"


  ## Message style guide

  - Use articles like "a", "an", and "the" when appropriate.
    - e.g., prefer "Cannot parse the expression" to "Cannot parse expression".
  - Use the common name for tokens and nodes.
    - e.g., prefer "keyword splat" to "assoc splat"
    - e.g., prefer "embedded document" to "embdoc"
  - Capitalize the initial word of the message.
  - Use back ticks around token literals
    - e.g., "Expected a `=>` between the hash key and value"
  - Do not use `.` or other punctuation at the end of the message.
  - Do not use contractions like "can't". Prefer "cannot" to "can not".
  - For tokens that can have multiple meanings, reference the token and its meaning.
    - e.g., "`*` splat argument" is clearer and more complete than "splat argument" or "`*` argument"


  ## Error names (YP_ERR_*)

  - When appropriate, prefer node name to token name.
    - e.g., prefer "SPLAT" to "STAR" in the context of argument parsing.
  - Prefer token name to common name.
    - e.g., prefer "STAR" to "ASTERISK".
  - Try to order the words in the name from more general to more specific,
    - e.g., "INVALID_NUMBER_DECIMAL" is better than "DECIMAL_INVALID_NUMBER".
    - When in doubt, look for similar patterns and name them so that they are grouped when lexically
      sorted. See YP_ERR_ARGUMENT_NO_FORWARDING_* for an example.
*/

static const char* const diagnostic_messages[YP_DIAGNOSTIC_ID_LEN] = {
    [YP_ERR_ALIAS_ARGUMENT]                     = "Invalid argument being passed to `alias`; expected a bare word, symbol, constant, or global variable",
    [YP_ERR_AMPAMPEQ_MULTI_ASSIGN]              = "Unexpected `&&=` in a multiple assignment",
    [YP_ERR_ARGUMENT_AFTER_BLOCK]               = "Unexpected argument after a block argument",
    [YP_ERR_ARGUMENT_BARE_HASH]                 = "Unexpected bare hash argument",
    [YP_ERR_ARGUMENT_BLOCK_MULTI]               = "Multiple block arguments; only one block is allowed",
    [YP_ERR_ARGUMENT_FORMAL_CLASS]              = "Invalid formal argument; formal argument cannot be a class variable",
    [YP_ERR_ARGUMENT_FORMAL_CONSTANT]           = "Invalid formal argument; formal argument cannot be a constant",
    [YP_ERR_ARGUMENT_FORMAL_GLOBAL]             = "Invalid formal argument; formal argument cannot be a global variable",
    [YP_ERR_ARGUMENT_FORMAL_IVAR]               = "Invalid formal argument; formal argument cannot be an instance variable",
    [YP_ERR_ARGUMENT_NO_FORWARDING_AMP]         = "Unexpected `&` when the parent method is not forwarding",
    [YP_ERR_ARGUMENT_NO_FORWARDING_ELLIPSES]    = "Unexpected `...` when the parent method is not forwarding",
    [YP_ERR_ARGUMENT_NO_FORWARDING_STAR]        = "Unexpected `*` when the parent method is not forwarding",
    [YP_ERR_ARGUMENT_SPLAT_AFTER_ASSOC_SPLAT]   = "Unexpected `*` splat argument after a `**` keyword splat argument",
    [YP_ERR_ARGUMENT_SPLAT_AFTER_SPLAT]         = "Unexpected `*` splat argument after a `*` splat argument",
    [YP_ERR_ARGUMENT_TERM_PAREN]                = "Expected a `)` to close the arguments",
    [YP_ERR_ARRAY_ELEMENT]                      = "Expected an element for the array",
    [YP_ERR_ARRAY_EXPRESSION]                   = "Expected an expression for the array element",
    [YP_ERR_ARRAY_EXPRESSION_AFTER_STAR]        = "Expected an expression after `*` in the array",
    [YP_ERR_ARRAY_SEPARATOR]                    = "Expected a `,` separator for the array elements",
    [YP_ERR_ARRAY_TERM]                         = "Expected a `]` to close the array",
    [YP_ERR_BEGIN_LONELY_ELSE]                  = "Unexpected `else` in `begin` block; a `rescue` clause must precede `else`",
    [YP_ERR_BEGIN_TERM]                         = "Expected an `end` to close the `begin` statement",
    [YP_ERR_BEGIN_UPCASE_BRACE]                 = "Expected a `{` after `BEGIN`",
    [YP_ERR_BEGIN_UPCASE_TERM]                  = "Expected a `}` to close the `BEGIN` statement",
    [YP_ERR_BLOCK_PARAM_LOCAL_VARIABLE]         = "Expected a local variable name in the block parameters",
    [YP_ERR_BLOCK_PARAM_PIPE_TERM]              = "Expected the block parameters to end with `|`",
    [YP_ERR_BLOCK_TERM_BRACE]                   = "Expected a block beginning with `{` to end with `}`",
    [YP_ERR_BLOCK_TERM_END]                     = "Expected a block beginning with `do` to end with `end`",
    [YP_ERR_CANNOT_PARSE_EXPRESSION]            = "Cannot parse the expression",
    [YP_ERR_CANNOT_PARSE_STRING_PART]           = "Cannot parse the string part",
    [YP_ERR_CASE_EXPRESSION_AFTER_CASE]         = "Expected an expression after `case`",
    [YP_ERR_CASE_EXPRESSION_AFTER_WHEN]         = "Expected an expression after `when`",
    [YP_ERR_CASE_LONELY_ELSE]                   = "Unexpected `else` in `case` statement; a `when` clause must precede `else`",
    [YP_ERR_CASE_TERM]                          = "Expected an `end` to close the `case` statement",
    [YP_ERR_CLASS_IN_METHOD]                    = "Unexpected class definition in a method body",
    [YP_ERR_CLASS_NAME]                         = "Expected a constant name after `class`",
    [YP_ERR_CLASS_SUPERCLASS]                   = "Expected a superclass after `<`",
    [YP_ERR_CLASS_TERM]                         = "Expected an `end` to close the `class` statement",
    [YP_ERR_CONDITIONAL_ELSIF_PREDICATE]        = "Expected a predicate expression for the `elsif` statement",
    [YP_ERR_CONDITIONAL_IF_PREDICATE]           = "Expected a predicate expression for the `if` statement",
    [YP_ERR_CONDITIONAL_TERM]                   = "Expected an `end` to close the conditional clause",
    [YP_ERR_CONDITIONAL_TERM_ELSE]              = "Expected an `end` to close the `else` clause",
    [YP_ERR_CONDITIONAL_UNLESS_PREDICATE]       = "Expected a predicate expression for the `unless` statement",
    [YP_ERR_CONDITIONAL_UNTIL_PREDICATE]        = "Expected a predicate expression for the `until` statement",
    [YP_ERR_CONDITIONAL_WHILE_PREDICATE]        = "Expected a predicate expression for the `while` statement",
    [YP_ERR_CONSTANT_PATH_COLON_COLON_CONSTANT] = "Expected a constant after the `::` operator",
    [YP_ERR_DEF_ENDLESS]                        = "Could not parse the endless method body",
    [YP_ERR_DEF_ENDLESS_SETTER]                 = "Invalid method name; a setter method cannot be defined in an endless method definition",
    [YP_ERR_DEF_NAME]                           = "Expected a method name",
    [YP_ERR_DEF_NAME_AFTER_RECEIVER]            = "Expected a method name after the receiver",
    [YP_ERR_DEF_PARAMS_TERM]                    = "Expected a delimiter to close the parameters",
    [YP_ERR_DEF_PARAMS_TERM_PAREN]              = "Expected a `)` to close the parameters",
    [YP_ERR_DEF_RECEIVER]                       = "Expected a receiver for the method definition",
    [YP_ERR_DEF_RECEIVER_TERM]                  = "Expected a `.` or `::` after the receiver in a method definition",
    [YP_ERR_DEF_TERM]                           = "Expected an `end` to close the `def` statement",
    [YP_ERR_DEFINED_EXPRESSION]                 = "Expected an expression after `defined?`",
    [YP_ERR_EMBDOC_TERM]                        = "Could not find a terminator for the embedded document",
    [YP_ERR_EMBEXPR_END]                        = "Expected a `}` to close the embedded expression",
    [YP_ERR_EMBVAR_INVALID]                     = "Invalid embedded variable",
    [YP_ERR_END_UPCASE_BRACE]                   = "Expected a `{` after `END`",
    [YP_ERR_END_UPCASE_TERM]                    = "Expected a `}` to close the `END` statement",
    [YP_ERR_ESCAPE_INVALID_CONTROL]             = "Invalid control escape sequence",
    [YP_ERR_ESCAPE_INVALID_CONTROL_REPEAT]      = "Invalid control escape sequence; control cannot be repeated",
    [YP_ERR_ESCAPE_INVALID_HEXADECIMAL]         = "Invalid hexadecimal escape sequence",
    [YP_ERR_ESCAPE_INVALID_META]                = "Invalid meta escape sequence",
    [YP_ERR_ESCAPE_INVALID_META_REPEAT]         = "Invalid meta escape sequence; meta cannot be repeated",
    [YP_ERR_ESCAPE_INVALID_UNICODE]             = "Invalid Unicode escape sequence",
    [YP_ERR_ESCAPE_INVALID_UNICODE_CM_FLAGS]    = "Invalid Unicode escape sequence; Unicode cannot be combined with control or meta flags",
    [YP_ERR_ESCAPE_INVALID_UNICODE_LITERAL]     = "Invalid Unicode escape sequence; multiple codepoints are not allowed in a character literal",
    [YP_ERR_ESCAPE_INVALID_UNICODE_LONG]        = "Invalid Unicode escape sequence; maximum length is 6 digits",
    [YP_ERR_ESCAPE_INVALID_UNICODE_TERM]        = "Invalid Unicode escape sequence; needs closing `}`",
    [YP_ERR_EXPECT_ARGUMENT]                    = "Expected an argument",
    [YP_ERR_EXPECT_EOL_AFTER_STATEMENT]         = "Expected a newline or semicolon after the statement",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ]   = "Expected an expression after `&&=`",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ] = "Expected an expression after `||=`",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_COMMA]      = "Expected an expression after `,`",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_EQUAL]      = "Expected an expression after `=`",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_LESS_LESS]  = "Expected an expression after `<<`",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_LPAREN]     = "Expected an expression after `(`",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR]   = "Expected an expression after the operator",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_SPLAT]      = "Expected an expression after `*` splat in an argument",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_SPLAT_HASH] = "Expected an expression after `**` in a hash",
    [YP_ERR_EXPECT_EXPRESSION_AFTER_STAR]       = "Expected an expression after `*`",
    [YP_ERR_EXPECT_IDENT_REQ_PARAMETER]         = "Expected an identifier for the required parameter",
    [YP_ERR_EXPECT_LPAREN_REQ_PARAMETER]        = "Expected a `(` to start a required parameter",
    [YP_ERR_EXPECT_RBRACKET]                    = "Expected a matching `]`",
    [YP_ERR_EXPECT_RPAREN]                      = "Expected a matching `)`",
    [YP_ERR_EXPECT_RPAREN_AFTER_MULTI]          = "Expected a `)` after multiple assignment",
    [YP_ERR_EXPECT_RPAREN_REQ_PARAMETER]        = "Expected a `)` to end a required parameter",
    [YP_ERR_EXPECT_STRING_CONTENT]              = "Expected string content after opening string delimiter",
    [YP_ERR_EXPECT_WHEN_DELIMITER]              = "Expected a delimiter after the predicates of a `when` clause",
    [YP_ERR_EXPRESSION_BARE_HASH]               = "Unexpected bare hash in expression",
    [YP_ERR_FOR_COLLECTION]                     = "Expected a collection after the `in` in a `for` statement",
    [YP_ERR_FOR_INDEX]                          = "Expected an index after `for`",
    [YP_ERR_FOR_IN]                             = "Expected an `in` after the index in a `for` statement",
    [YP_ERR_FOR_TERM]                           = "Expected an `end` to close the `for` loop",
    [YP_ERR_HASH_EXPRESSION_AFTER_LABEL]        = "Expected an expression after the label in a hash",
    [YP_ERR_HASH_KEY]                           = "Expected a key in the hash literal",
    [YP_ERR_HASH_ROCKET]                        = "Expected a `=>` between the hash key and value",
    [YP_ERR_HASH_TERM]                          = "Expected a `}` to close the hash literal",
    [YP_ERR_HASH_VALUE]                         = "Expected a value in the hash literal",
    [YP_ERR_HEREDOC_TERM]                       = "Could not find a terminator for the heredoc",
    [YP_ERR_INCOMPLETE_QUESTION_MARK]           = "Incomplete expression at `?`",
    [YP_ERR_INCOMPLETE_VARIABLE_CLASS]          = "Incomplete class variable",
    [YP_ERR_INCOMPLETE_VARIABLE_INSTANCE]       = "Incomplete instance variable",
    [YP_ERR_INVALID_ENCODING_MAGIC_COMMENT]     = "Unknown or invalid encoding in the magic comment",
    [YP_ERR_INVALID_FLOAT_EXPONENT]             = "Invalid exponent",
    [YP_ERR_INVALID_NUMBER_BINARY]              = "Invalid binary number",
    [YP_ERR_INVALID_NUMBER_DECIMAL]             = "Invalid decimal number",
    [YP_ERR_INVALID_NUMBER_HEXADECIMAL]         = "Invalid hexadecimal number",
    [YP_ERR_INVALID_NUMBER_OCTAL]               = "Invalid octal number",
    [YP_ERR_INVALID_PERCENT]                    = "Invalid `%` token", // TODO WHAT?
    [YP_ERR_INVALID_TOKEN]                      = "Invalid token", // TODO WHAT?
    [YP_ERR_INVALID_VARIABLE_GLOBAL]            = "Invalid global variable",
    [YP_ERR_LAMBDA_OPEN]                        = "Expected a `do` keyword or a `{` to open the lambda block",
    [YP_ERR_LAMBDA_TERM_BRACE]                  = "Expected a lambda block beginning with `{` to end with `}`",
    [YP_ERR_LAMBDA_TERM_END]                    = "Expected a lambda block beginning with `do` to end with `end`",
    [YP_ERR_LIST_I_LOWER_ELEMENT]               = "Expected a symbol in a `%i` list",
    [YP_ERR_LIST_I_LOWER_TERM]                  = "Expected a closing delimiter for the `%i` list",
    [YP_ERR_LIST_I_UPPER_ELEMENT]               = "Expected a symbol in a `%I` list",
    [YP_ERR_LIST_I_UPPER_TERM]                  = "Expected a closing delimiter for the `%I` list",
    [YP_ERR_LIST_W_LOWER_ELEMENT]               = "Expected a string in a `%w` list",
    [YP_ERR_LIST_W_LOWER_TERM]                  = "Expected a closing delimiter for the `%w` list",
    [YP_ERR_LIST_W_UPPER_ELEMENT]               = "Expected a string in a `%W` list",
    [YP_ERR_LIST_W_UPPER_TERM]                  = "Expected a closing delimiter for the `%W` list",
    [YP_ERR_MALLOC_FAILED]                      = "Failed to allocate memory",
    [YP_ERR_MODULE_IN_METHOD]                   = "Unexpected module definition in a method body",
    [YP_ERR_MODULE_NAME]                        = "Expected a constant name after `module`",
    [YP_ERR_MODULE_TERM]                        = "Expected an `end` to close the `module` statement",
    [YP_ERR_MULTI_ASSIGN_MULTI_SPLATS]          = "Multiple splats in multiple assignment",
    [YP_ERR_NOT_EXPRESSION]                     = "Expected an expression after `not`",
    [YP_ERR_NUMBER_LITERAL_UNDERSCORE]          = "Number literal ending with a `_`",
    [YP_ERR_OPERATOR_MULTI_ASSIGN]              = "Unexpected operator for a multiple assignment",
    [YP_ERR_PARAMETER_ASSOC_SPLAT_MULTI]        = "Unexpected multiple `**` splat parameters",
    [YP_ERR_PARAMETER_BLOCK_MULTI]              = "Multiple block parameters; only one block is allowed",
    [YP_ERR_PARAMETER_NAME_REPEAT]              = "Repeated parameter name",
    [YP_ERR_PARAMETER_NO_DEFAULT]               = "Expected a default value for the parameter",
    [YP_ERR_PARAMETER_NO_DEFAULT_KW]            = "Expected a default value for the keyword parameter",
    [YP_ERR_PARAMETER_NUMBERED_RESERVED]        = "Token reserved for a numbered parameter",
    [YP_ERR_PARAMETER_ORDER]                    = "Unexpected parameter order",
    [YP_ERR_PARAMETER_SPLAT_MULTI]              = "Unexpected multiple `*` splat parameters",
    [YP_ERR_PARAMETER_STAR]                     = "Unexpected parameter `*`",
    [YP_ERR_PARAMETER_WILD_LOOSE_COMMA]         = "Unexpected `,` in parameters",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_BRACKET]   = "Expected a pattern expression after the `[` operator",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_COMMA]     = "Expected a pattern expression after `,`",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_HROCKET]   = "Expected a pattern expression after `=>`",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_IN]        = "Expected a pattern expression after the `in` keyword",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_KEY]       = "Expected a pattern expression after the key",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_PAREN]     = "Expected a pattern expression after the `(` operator",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_PIN]       = "Expected a pattern expression after the `^` pin operator",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_PIPE]      = "Expected a pattern expression after the `|` operator",
    [YP_ERR_PATTERN_EXPRESSION_AFTER_RANGE]     = "Expected a pattern expression after the range operator",
    [YP_ERR_PATTERN_HASH_KEY]                   = "Expected a key in the hash pattern",
    [YP_ERR_PATTERN_HASH_KEY_LABEL]             = "Expected a label as the key in the hash pattern", // TODO // THIS // AND // ABOVE // IS WEIRD
    [YP_ERR_PATTERN_IDENT_AFTER_HROCKET]        = "Expected an identifier after the `=>` operator",
    [YP_ERR_PATTERN_LABEL_AFTER_COMMA]          = "Expected a label after the `,` in the hash pattern",
    [YP_ERR_PATTERN_REST]                       = "Unexpected rest pattern",
    [YP_ERR_PATTERN_TERM_BRACE]                 = "Expected a `}` to close the pattern expression",
    [YP_ERR_PATTERN_TERM_BRACKET]               = "Expected a `]` to close the pattern expression",
    [YP_ERR_PATTERN_TERM_PAREN]                 = "Expected a `)` to close the pattern expression",
    [YP_ERR_PIPEPIPEEQ_MULTI_ASSIGN]            = "Unexpected `||=` in a multiple assignment",
    [YP_ERR_REGEXP_TERM]                        = "Expected a closing delimiter for the regular expression",
    [YP_ERR_RESCUE_EXPRESSION]                  = "Expected a rescued expression",
    [YP_ERR_RESCUE_MODIFIER_VALUE]              = "Expected a value after the `rescue` modifier",
    [YP_ERR_RESCUE_TERM]                        = "Expected a closing delimiter for the `rescue` clause",
    [YP_ERR_RESCUE_VARIABLE]                    = "Expected an exception variable after `=>` in a rescue statement",
    [YP_ERR_RETURN_INVALID]                     = "Invalid `return` in a class or module body",
    [YP_ERR_STRING_CONCATENATION]               = "Expected a string for concatenation",
    [YP_ERR_STRING_INTERPOLATED_TERM]           = "Expected a closing delimiter for the interpolated string",
    [YP_ERR_STRING_LITERAL_TERM]                = "Expected a closing delimiter for the string literal",
    [YP_ERR_SYMBOL_INVALID]                     = "Invalid symbol", // TODO expected symbol? yarp.c ~9719
    [YP_ERR_SYMBOL_TERM_DYNAMIC]                = "Expected a closing delimiter for the dynamic symbol",
    [YP_ERR_SYMBOL_TERM_INTERPOLATED]           = "Expected a closing delimiter for the interpolated symbol",
    [YP_ERR_TERNARY_COLON]                      = "Expected a `:` after the true expression of a ternary operator",
    [YP_ERR_TERNARY_EXPRESSION_FALSE]           = "Expected an expression after `:` in the ternary operator",
    [YP_ERR_TERNARY_EXPRESSION_TRUE]            = "Expected an expression after `?` in the ternary operator",
    [YP_ERR_UNDEF_ARGUMENT]                     = "Invalid argument being passed to `undef`; expected a bare word, constant, or symbol argument",
    [YP_ERR_UNARY_RECEIVER_BANG]                = "Expected a receiver for unary `!`",
    [YP_ERR_UNARY_RECEIVER_MINUS]               = "Expected a receiver for unary `-`",
    [YP_ERR_UNARY_RECEIVER_PLUS]                = "Expected a receiver for unary `+`",
    [YP_ERR_UNARY_RECEIVER_TILDE]               = "Expected a receiver for unary `~`",
    [YP_ERR_UNTIL_TERM]                         = "Expected an `end` to close the `until` statement",
    [YP_ERR_WHILE_TERM]                         = "Expected an `end` to close the `while` statement",
    [YP_ERR_WRITE_TARGET_READONLY]              = "Immutable variable as a write target",
    [YP_ERR_WRITE_TARGET_UNEXPECTED]            = "Unexpected write target",
    [YP_ERR_XSTRING_TERM]                       = "Expected a closing delimiter for the `%x` or backtick string",
    [YP_WARN_AMBIGUOUS_FIRST_ARGUMENT_MINUS]    = "Ambiguous first argument; put parentheses or a space even after `-` operator",
    [YP_WARN_AMBIGUOUS_FIRST_ARGUMENT_PLUS]     = "Ambiguous first argument; put parentheses or a space even after `+` operator",
    [YP_WARN_AMBIGUOUS_PREFIX_STAR]             = "Ambiguous `*` has been interpreted as an argument prefix",
    [YP_WARN_AMBIGUOUS_SLASH]                   = "Ambiguous `/`; wrap regexp in parentheses or add a space after `/` operator",
};

static const char*
yp_diagnostic_message(yp_diagnostic_id_t diag_id) {
    assert(diag_id < YP_DIAGNOSTIC_ID_LEN);
    const char *message = diagnostic_messages[diag_id];
    assert(message);
    return message;
}

// Append an error to the given list of diagnostic.
bool
yp_diagnostic_list_append(yp_list_t *list, const uint8_t *start, const uint8_t *end, yp_diagnostic_id_t diag_id) {
    yp_diagnostic_t *diagnostic = (yp_diagnostic_t *) malloc(sizeof(yp_diagnostic_t));
    if (diagnostic == NULL) return false;

    *diagnostic = (yp_diagnostic_t) { .start = start, .end = end, .message = yp_diagnostic_message(diag_id) };
    yp_list_append(list, (yp_list_node_t *) diagnostic);
    return true;
}

// Deallocate the internal state of the given diagnostic list.
void
yp_diagnostic_list_free(yp_list_t *list) {
    yp_list_node_t *node, *next;

    for (node = list->head; node != NULL; node = next) {
        next = node->next;

        yp_diagnostic_t *diagnostic = (yp_diagnostic_t *) node;
        free(diagnostic);
    }
}
