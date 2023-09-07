#include "yarp.h"

// The YARP version and the serialization format.
const char *
yp_version(void) {
    return YP_VERSION;
}

// In heredocs, tabs automatically complete up to the next 8 spaces. This is
// defined in CRuby as TAB_WIDTH.
#define YP_TAB_WHITESPACE_SIZE 8

// Debugging logging will provide you will additional debugging functions as
// well as automatically replace some functions with their debugging
// counterparts.
#ifndef YP_DEBUG_LOGGING
#define YP_DEBUG_LOGGING 0
#endif

#if YP_DEBUG_LOGGING

/******************************************************************************/
/* Debugging                                                                  */
/******************************************************************************/

YP_ATTRIBUTE_UNUSED static const char *
debug_context(yp_context_t context) {
    switch (context) {
        case YP_CONTEXT_BEGIN: return "BEGIN";
        case YP_CONTEXT_CLASS: return "CLASS";
        case YP_CONTEXT_CASE_IN: return "CASE_IN";
        case YP_CONTEXT_CASE_WHEN: return "CASE_WHEN";
        case YP_CONTEXT_DEF: return "DEF";
        case YP_CONTEXT_DEF_PARAMS: return "DEF_PARAMS";
        case YP_CONTEXT_DEFAULT_PARAMS: return "DEFAULT_PARAMS";
        case YP_CONTEXT_ENSURE: return "ENSURE";
        case YP_CONTEXT_ELSE: return "ELSE";
        case YP_CONTEXT_ELSIF: return "ELSIF";
        case YP_CONTEXT_EMBEXPR: return "EMBEXPR";
        case YP_CONTEXT_BLOCK_BRACES: return "BLOCK_BRACES";
        case YP_CONTEXT_BLOCK_KEYWORDS: return "BLOCK_KEYWORDS";
        case YP_CONTEXT_FOR: return "FOR";
        case YP_CONTEXT_IF: return "IF";
        case YP_CONTEXT_MAIN: return "MAIN";
        case YP_CONTEXT_MODULE: return "MODULE";
        case YP_CONTEXT_PARENS: return "PARENS";
        case YP_CONTEXT_POSTEXE: return "POSTEXE";
        case YP_CONTEXT_PREDICATE: return "PREDICATE";
        case YP_CONTEXT_PREEXE: return "PREEXE";
        case YP_CONTEXT_RESCUE: return "RESCUE";
        case YP_CONTEXT_RESCUE_ELSE: return "RESCUE_ELSE";
        case YP_CONTEXT_SCLASS: return "SCLASS";
        case YP_CONTEXT_UNLESS: return "UNLESS";
        case YP_CONTEXT_UNTIL: return "UNTIL";
        case YP_CONTEXT_WHILE: return "WHILE";
        case YP_CONTEXT_LAMBDA_BRACES: return "LAMBDA_BRACES";
        case YP_CONTEXT_LAMBDA_DO_END: return "LAMBDA_DO_END";
    }
    return NULL;
}

YP_ATTRIBUTE_UNUSED static void
debug_contexts(yp_parser_t *parser) {
    yp_context_node_t *context_node = parser->current_context;
    fprintf(stderr, "CONTEXTS: ");

    if (context_node != NULL) {
        while (context_node != NULL) {
            fprintf(stderr, "%s", debug_context(context_node->context));
            context_node = context_node->prev;
            if (context_node != NULL) {
                fprintf(stderr, " <- ");
            }
        }
    } else {
        fprintf(stderr, "NONE");
    }

    fprintf(stderr, "\n");
}

YP_ATTRIBUTE_UNUSED static void
debug_node(const char *message, yp_parser_t *parser, yp_node_t *node) {
    yp_buffer_t buffer;
    if (!yp_buffer_init(&buffer)) return;

    yp_prettyprint(parser, node, &buffer);

    fprintf(stderr, "%s\n%.*s\n", message, (int) buffer.length, buffer.value);
    yp_buffer_free(&buffer);
}

YP_ATTRIBUTE_UNUSED static void
debug_lex_mode(yp_parser_t *parser) {
    yp_lex_mode_t *lex_mode = parser->lex_modes.current;
    bool first = true;

    while (lex_mode != NULL) {
        if (first) {
            first = false;
        } else {
            fprintf(stderr, " <- ");
        }

        switch (lex_mode->mode) {
            case YP_LEX_DEFAULT: fprintf(stderr, "DEFAULT"); break;
            case YP_LEX_EMBEXPR: fprintf(stderr, "EMBEXPR"); break;
            case YP_LEX_EMBVAR: fprintf(stderr, "EMBVAR"); break;
            case YP_LEX_HEREDOC: fprintf(stderr, "HEREDOC"); break;
            case YP_LEX_LIST: fprintf(stderr, "LIST (terminator=%c, interpolation=%d)", lex_mode->as.list.terminator, lex_mode->as.list.interpolation); break;
            case YP_LEX_REGEXP: fprintf(stderr, "REGEXP (terminator=%c)", lex_mode->as.regexp.terminator); break;
            case YP_LEX_STRING: fprintf(stderr, "STRING (terminator=%c, interpolation=%d)", lex_mode->as.string.terminator, lex_mode->as.string.interpolation); break;
        }

        lex_mode = lex_mode->prev;
    }

    fprintf(stderr, "\n");
}

YP_ATTRIBUTE_UNUSED static void
debug_state(yp_parser_t *parser) {
    fprintf(stderr, "STATE: ");
    bool first = true;

    if (parser->lex_state == YP_LEX_STATE_NONE) {
        fprintf(stderr, "NONE\n");
        return;
    }

#define CHECK_STATE(state) \
    if (parser->lex_state & state) { \
        if (!first) fprintf(stderr, "|"); \
        fprintf(stderr, "%s", #state); \
        first = false; \
    }

    CHECK_STATE(YP_LEX_STATE_BEG)
    CHECK_STATE(YP_LEX_STATE_END)
    CHECK_STATE(YP_LEX_STATE_ENDARG)
    CHECK_STATE(YP_LEX_STATE_ENDFN)
    CHECK_STATE(YP_LEX_STATE_ARG)
    CHECK_STATE(YP_LEX_STATE_CMDARG)
    CHECK_STATE(YP_LEX_STATE_MID)
    CHECK_STATE(YP_LEX_STATE_FNAME)
    CHECK_STATE(YP_LEX_STATE_DOT)
    CHECK_STATE(YP_LEX_STATE_CLASS)
    CHECK_STATE(YP_LEX_STATE_LABEL)
    CHECK_STATE(YP_LEX_STATE_LABELED)
    CHECK_STATE(YP_LEX_STATE_FITEM)

#undef CHECK_STATE

    fprintf(stderr, "\n");
}

YP_ATTRIBUTE_UNUSED static void
debug_token(yp_token_t * token) {
    fprintf(stderr, "%s: \"%.*s\"\n", yp_token_type_to_str(token->type), (int) (token->end - token->start), token->start);
}

#endif

/* Macros for min/max.  */
#define MIN(a,b) (((a)<(b))?(a):(b))
#define MAX(a,b) (((a)>(b))?(a):(b))

/******************************************************************************/
/* Lex mode manipulations                                                     */
/******************************************************************************/

// Returns the incrementor character that should be used to increment the
// nesting count if one is possible.
static inline uint8_t
lex_mode_incrementor(const uint8_t start) {
    switch (start) {
        case '(':
        case '[':
        case '{':
        case '<':
            return start;
        default:
            return '\0';
    }
}

// Returns the matching character that should be used to terminate a list
// beginning with the given character.
static inline uint8_t
lex_mode_terminator(const uint8_t start) {
    switch (start) {
        case '(':
            return ')';
        case '[':
            return ']';
        case '{':
            return '}';
        case '<':
            return '>';
        default:
            return start;
    }
}

// Push a new lex state onto the stack. If we're still within the pre-allocated
// space of the lex state stack, then we'll just use a new slot. Otherwise we'll
// allocate a new pointer and use that.
static bool
lex_mode_push(yp_parser_t *parser, yp_lex_mode_t lex_mode) {
    lex_mode.prev = parser->lex_modes.current;
    parser->lex_modes.index++;

    if (parser->lex_modes.index > YP_LEX_STACK_SIZE - 1) {
        parser->lex_modes.current = (yp_lex_mode_t *) malloc(sizeof(yp_lex_mode_t));
        if (parser->lex_modes.current == NULL) return false;

        *parser->lex_modes.current = lex_mode;
    } else {
        parser->lex_modes.stack[parser->lex_modes.index] = lex_mode;
        parser->lex_modes.current = &parser->lex_modes.stack[parser->lex_modes.index];
    }

    return true;
}

// Push on a new list lex mode.
static inline bool
lex_mode_push_list(yp_parser_t *parser, bool interpolation, uint8_t delimiter) {
    uint8_t incrementor = lex_mode_incrementor(delimiter);
    uint8_t terminator = lex_mode_terminator(delimiter);

    yp_lex_mode_t lex_mode = {
        .mode = YP_LEX_LIST,
        .as.list = {
            .nesting = 0,
            .interpolation = interpolation,
            .incrementor = incrementor,
            .terminator = terminator
        }
    };

    // These are the places where we need to split up the content of the list.
    // We'll use strpbrk to find the first of these characters.
    uint8_t *breakpoints = lex_mode.as.list.breakpoints;
    memcpy(breakpoints, "\\ \t\f\r\v\n\0\0\0", sizeof(lex_mode.as.list.breakpoints));

    // Now we'll add the terminator to the list of breakpoints.
    size_t index = 7;
    breakpoints[index++] = terminator;

    // If interpolation is allowed, then we're going to check for the #
    // character. Otherwise we'll only look for escapes and the terminator.
    if (interpolation) {
        breakpoints[index++] = '#';
    }

    // If there is an incrementor, then we'll check for that as well.
    if (incrementor != '\0') {
        breakpoints[index++] = incrementor;
    }

    return lex_mode_push(parser, lex_mode);
}

// Push on a new regexp lex mode.
static inline bool
lex_mode_push_regexp(yp_parser_t *parser, uint8_t incrementor, uint8_t terminator) {
    yp_lex_mode_t lex_mode = {
        .mode = YP_LEX_REGEXP,
        .as.regexp = {
            .nesting = 0,
            .incrementor = incrementor,
            .terminator = terminator
        }
    };

    // These are the places where we need to split up the content of the
    // regular expression. We'll use strpbrk to find the first of these
    // characters.
    uint8_t *breakpoints = lex_mode.as.regexp.breakpoints;
    memcpy(breakpoints, "\n\\#\0\0", sizeof(lex_mode.as.regexp.breakpoints));

    // First we'll add the terminator.
    breakpoints[3] = terminator;

    // Next, if there is an incrementor, then we'll check for that as well.
    if (incrementor != '\0') {
        breakpoints[4] = incrementor;
    }

    return lex_mode_push(parser, lex_mode);
}

// Push on a new string lex mode.
static inline bool
lex_mode_push_string(yp_parser_t *parser, bool interpolation, bool label_allowed, uint8_t incrementor, uint8_t terminator) {
    yp_lex_mode_t lex_mode = {
        .mode = YP_LEX_STRING,
        .as.string = {
            .nesting = 0,
            .interpolation = interpolation,
            .label_allowed = label_allowed,
            .incrementor = incrementor,
            .terminator = terminator
        }
    };

    // These are the places where we need to split up the content of the
    // string. We'll use strpbrk to find the first of these characters.
    uint8_t *breakpoints = lex_mode.as.string.breakpoints;
    memcpy(breakpoints, "\n\\\0\0\0", sizeof(lex_mode.as.string.breakpoints));

    // Now add in the terminator.
    size_t index = 2;
    breakpoints[index++] = terminator;

    // If interpolation is allowed, then we're going to check for the #
    // character. Otherwise we'll only look for escapes and the terminator.
    if (interpolation) {
        breakpoints[index++] = '#';
    }

    // If we have an incrementor, then we'll add that in as a breakpoint as
    // well.
    if (incrementor != '\0') {
        breakpoints[index++] = incrementor;
    }

    return lex_mode_push(parser, lex_mode);
}

// Pop the current lex state off the stack. If we're within the pre-allocated
// space of the lex state stack, then we'll just decrement the index. Otherwise
// we'll free the current pointer and use the previous pointer.
static void
lex_mode_pop(yp_parser_t *parser) {
    if (parser->lex_modes.index == 0) {
        parser->lex_modes.current->mode = YP_LEX_DEFAULT;
    } else if (parser->lex_modes.index < YP_LEX_STACK_SIZE) {
        parser->lex_modes.index--;
        parser->lex_modes.current = &parser->lex_modes.stack[parser->lex_modes.index];
    } else {
        parser->lex_modes.index--;
        yp_lex_mode_t *prev = parser->lex_modes.current->prev;
        free(parser->lex_modes.current);
        parser->lex_modes.current = prev;
    }
}

// This is the equivalent of IS_lex_state is CRuby.
static inline bool
lex_state_p(yp_parser_t *parser, yp_lex_state_t state) {
    return parser->lex_state & state;
}

typedef enum {
    YP_IGNORED_NEWLINE_NONE = 0,
    YP_IGNORED_NEWLINE_ALL,
    YP_IGNORED_NEWLINE_PATTERN
} yp_ignored_newline_type_t;

static inline yp_ignored_newline_type_t
lex_state_ignored_p(yp_parser_t *parser) {
    bool ignored = lex_state_p(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_CLASS | YP_LEX_STATE_FNAME | YP_LEX_STATE_DOT) && !lex_state_p(parser, YP_LEX_STATE_LABELED);

    if (ignored) {
        return YP_IGNORED_NEWLINE_ALL;
    } else if ((parser->lex_state & ~((unsigned int) YP_LEX_STATE_LABEL)) == (YP_LEX_STATE_ARG | YP_LEX_STATE_LABELED)) {
        return YP_IGNORED_NEWLINE_PATTERN;
    } else {
        return YP_IGNORED_NEWLINE_NONE;
    }
}

static inline bool
lex_state_beg_p(yp_parser_t *parser) {
    return lex_state_p(parser, YP_LEX_STATE_BEG_ANY) || (parser->lex_state == (YP_LEX_STATE_ARG | YP_LEX_STATE_LABELED));
}

static inline bool
lex_state_arg_p(yp_parser_t *parser) {
    return lex_state_p(parser, YP_LEX_STATE_ARG_ANY);
}

static inline bool
lex_state_spcarg_p(yp_parser_t *parser, bool space_seen) {
    if (parser->current.end >= parser->end) {
        return false;
    }
    return lex_state_arg_p(parser) && space_seen && !yp_char_is_whitespace(*parser->current.end);
}

static inline bool
lex_state_end_p(yp_parser_t *parser) {
    return lex_state_p(parser, YP_LEX_STATE_END_ANY);
}

// This is the equivalent of IS_AFTER_OPERATOR in CRuby.
static inline bool
lex_state_operator_p(yp_parser_t *parser) {
    return lex_state_p(parser, YP_LEX_STATE_FNAME | YP_LEX_STATE_DOT);
}

// Set the state of the lexer. This is defined as a function to be able to put a breakpoint in it.
static inline void
lex_state_set(yp_parser_t *parser, yp_lex_state_t state) {
    parser->lex_state = state;
}

#if YP_DEBUG_LOGGING
static inline void
debug_lex_state_set(yp_parser_t *parser, yp_lex_state_t state, char const * caller_name, int line_number) {
    fprintf(stderr, "Caller: %s:%d\nPrevious: ", caller_name, line_number);
    debug_state(parser);
    lex_state_set(parser, state);
    fprintf(stderr, "Now: ");
    debug_state(parser);
    fprintf(stderr, "\n");
}

#define lex_state_set(parser, state) debug_lex_state_set(parser, state, __func__, __LINE__)
#endif

/******************************************************************************/
/* Node-related functions                                                     */
/******************************************************************************/

// Retrieve the constant pool id for the given location.
static inline yp_constant_id_t
yp_parser_constant_id_location(yp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    return yp_constant_pool_insert_shared(&parser->constant_pool, start, (size_t) (end - start));
}

// Retrieve the constant pool id for the given string.
static inline yp_constant_id_t
yp_parser_constant_id_owned(yp_parser_t *parser, const uint8_t *start, size_t length) {
    return yp_constant_pool_insert_owned(&parser->constant_pool, start, length);
}

// Retrieve the constant pool id for the given token.
static inline yp_constant_id_t
yp_parser_constant_id_token(yp_parser_t *parser, const yp_token_t *token) {
    return yp_parser_constant_id_location(parser, token->start, token->end);
}

// Retrieve the constant pool id for the given token. If the token is not
// provided, then return 0.
static inline yp_constant_id_t
yp_parser_optional_constant_id_token(yp_parser_t *parser, const yp_token_t *token) {
    return token->type == YP_TOKEN_NOT_PROVIDED ? 0 : yp_parser_constant_id_token(parser, token);
}

// Mark any range nodes in this subtree as flipflops.
static void
yp_flip_flop(yp_node_t *node) {
    switch (YP_NODE_TYPE(node)) {
        case YP_AND_NODE: {
            yp_and_node_t *cast = (yp_and_node_t *) node;
            yp_flip_flop(cast->left);
            yp_flip_flop(cast->right);
            break;
        }
        case YP_OR_NODE: {
            yp_or_node_t *cast = (yp_or_node_t *) node;
            yp_flip_flop(cast->left);
            yp_flip_flop(cast->right);
            break;
        }
        case YP_PARENTHESES_NODE: {
            yp_parentheses_node_t *cast = (yp_parentheses_node_t *) node;

            if ((cast->body != NULL) && YP_NODE_TYPE_P(cast->body, YP_STATEMENTS_NODE)) {
                yp_statements_node_t *statements = (yp_statements_node_t *) cast->body;
                if (statements->body.size == 1) yp_flip_flop(statements->body.nodes[0]);
            }

            break;
        }
        case YP_RANGE_NODE: {
            yp_range_node_t *cast = (yp_range_node_t *) node;
            if (cast->left) {
                yp_flip_flop(cast->left);
            }
            if (cast->right) {
                yp_flip_flop(cast->right);
            }

            // Here we change the range node into a flip flop node. We can do
            // this since the nodes are exactly the same except for the type.
            assert(sizeof(yp_range_node_t) == sizeof(yp_flip_flop_node_t));
            node->type = YP_FLIP_FLOP_NODE;

            break;
        }
        default:
            break;
    }
}

// In a lot of places in the tree you can have tokens that are not provided but
// that do not cause an error. For example, in a method call without
// parentheses. In these cases we set the token to the "not provided" type. For
// example:
//
//     yp_token_t token;
//     not_provided(&token, parser->previous.end);
//
static inline yp_token_t
not_provided(yp_parser_t *parser) {
    return (yp_token_t) { .type = YP_TOKEN_NOT_PROVIDED, .start = parser->start, .end = parser->start };
}

#define YP_LOCATION_NULL_VALUE(parser) ((yp_location_t) { .start = parser->start, .end = parser->start })
#define YP_LOCATION_TOKEN_VALUE(token) ((yp_location_t) { .start = (token)->start, .end = (token)->end })
#define YP_LOCATION_NODE_VALUE(node) ((yp_location_t) { .start = (node)->location.start, .end = (node)->location.end })
#define YP_LOCATION_NODE_BASE_VALUE(node) ((yp_location_t) { .start = (node)->base.location.start, .end = (node)->base.location.end })
#define YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE ((yp_location_t) { .start = NULL, .end = NULL })
#define YP_OPTIONAL_LOCATION_TOKEN_VALUE(token) ((token)->type == YP_TOKEN_NOT_PROVIDED ? YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE : YP_LOCATION_TOKEN_VALUE(token))

// This is a special out parameter to the parse_arguments_list function that
// includes opening and closing parentheses in addition to the arguments since
// it's so common. It is handy to use when passing argument information to one
// of the call node creation functions.
typedef struct {
    yp_location_t opening_loc;
    yp_arguments_node_t *arguments;
    yp_location_t closing_loc;
    yp_block_node_t *block;

    // This boolean is used to tell if there is an implicit block (i.e., an
    // argument passed with an & operator).
    bool implicit_block;
} yp_arguments_t;

#define YP_EMPTY_ARGUMENTS ((yp_arguments_t) {              \
    .opening_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE, \
    .arguments = NULL,                                      \
    .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE, \
    .block = NULL,                                          \
    .implicit_block = false                                 \
})

// Check that the set of arguments parsed for a given node is valid. This means
// checking that we don't have both an implicit and explicit block.
static void
yp_arguments_validate(yp_parser_t *parser, yp_arguments_t *arguments) {
    if (arguments->block != NULL && arguments->implicit_block) {
        yp_diagnostic_list_append(
            &parser->error_list,
            arguments->block->base.location.start,
            arguments->block->base.location.end,
            YP_ERR_ARGUMENT_BLOCK_MULTI
        );
    }
}

/******************************************************************************/
/* Scope node functions                                                       */
/******************************************************************************/

// Generate a scope node from the given node.
void
yp_scope_node_init(yp_node_t *node, yp_scope_node_t *scope) {
    scope->base.type = YP_SCOPE_NODE;
    scope->base.location.start = node->location.start;
    scope->base.location.end = node->location.end;

    scope->parameters = NULL;
    scope->body = NULL;
    yp_constant_id_list_init(&scope->locals);

    switch (YP_NODE_TYPE(node)) {
        case YP_BLOCK_NODE: {
            yp_block_node_t *cast = (yp_block_node_t *) node;
            if (cast->parameters) scope->parameters = cast->parameters->parameters;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case YP_CLASS_NODE: {
            yp_class_node_t *cast = (yp_class_node_t *) node;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case YP_DEF_NODE: {
            yp_def_node_t *cast = (yp_def_node_t *) node;
            scope->parameters = cast->parameters;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case YP_LAMBDA_NODE: {
            yp_lambda_node_t *cast = (yp_lambda_node_t *) node;
            if (cast->parameters) scope->parameters = cast->parameters->parameters;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case YP_MODULE_NODE: {
            yp_module_node_t *cast = (yp_module_node_t *) node;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        case YP_PROGRAM_NODE: {
            yp_program_node_t *cast = (yp_program_node_t *) node;
            scope->body = (yp_node_t *) cast->statements;
            scope->locals = cast->locals;
            break;
        }
        case YP_SINGLETON_CLASS_NODE: {
            yp_singleton_class_node_t *cast = (yp_singleton_class_node_t *) node;
            scope->body = cast->body;
            scope->locals = cast->locals;
            break;
        }
        default:
            assert(false && "unreachable");
            break;
    }
}

/******************************************************************************/
/* Node creation functions                                                    */
/******************************************************************************/

// Parse the decimal number represented by the range of bytes. returns
// UINT32_MAX if the number fails to parse. This function assumes that the range
// of bytes has already been validated to contain only decimal digits.
static uint32_t
parse_decimal_number(yp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    ptrdiff_t diff = end - start;
    assert(diff > 0 && ((unsigned long) diff < SIZE_MAX));
    size_t length = (size_t) diff;

    char *digits = calloc(length + 1, sizeof(char));
    memcpy(digits, start, length);
    digits[length] = '\0';

    char *endptr;
    errno = 0;
    unsigned long value = strtoul(digits, &endptr, 10);

    if ((digits == endptr) || (*endptr != '\0') || (errno == ERANGE)) {
        yp_diagnostic_list_append(&parser->error_list, start, end, YP_ERR_INVALID_NUMBER_DECIMAL);
        value = UINT32_MAX;
    }

    free(digits);

    if (value > UINT32_MAX) {
        yp_diagnostic_list_append(&parser->error_list, start, end, YP_ERR_INVALID_NUMBER_DECIMAL);
        value = UINT32_MAX;
    }

    return (uint32_t) value;
}

// Parse out the options for a regular expression.
static inline yp_node_flags_t
yp_regular_expression_flags_create(const yp_token_t *closing) {
    yp_node_flags_t flags = 0;

    if (closing->type == YP_TOKEN_REGEXP_END) {
        for (const uint8_t *flag = closing->start + 1; flag < closing->end; flag++) {
            switch (*flag) {
                case 'i': flags |= YP_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE; break;
                case 'm': flags |= YP_REGULAR_EXPRESSION_FLAGS_MULTI_LINE; break;
                case 'x': flags |= YP_REGULAR_EXPRESSION_FLAGS_EXTENDED; break;
                case 'e': flags |= YP_REGULAR_EXPRESSION_FLAGS_EUC_JP; break;
                case 'n': flags |= YP_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT; break;
                case 's': flags |= YP_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J; break;
                case 'u': flags |= YP_REGULAR_EXPRESSION_FLAGS_UTF_8; break;
                case 'o': flags |= YP_REGULAR_EXPRESSION_FLAGS_ONCE; break;
                default: assert(false && "unreachable");
            }
        }
    }

    return flags;
}

// Allocate and initialize a new StatementsNode node.
static yp_statements_node_t *
yp_statements_node_create(yp_parser_t *parser);

// Append a new node to the given StatementsNode node's body.
static void
yp_statements_node_body_append(yp_statements_node_t *node, yp_node_t *statement);

// This function is here to allow us a place to extend in the future when we
// implement our own arena allocation.
static inline void *
yp_alloc_node(YP_ATTRIBUTE_UNUSED yp_parser_t *parser, size_t size) {
    void *memory = calloc(1, size);
    if (memory == NULL) {
        fprintf(stderr, "Failed to allocate %zu bytes\n", size);
        abort();
    }
    return memory;
}

#define YP_ALLOC_NODE(parser, type) (type *) yp_alloc_node(parser, sizeof(type))

// Allocate a new MissingNode node.
static yp_missing_node_t *
yp_missing_node_create(yp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    yp_missing_node_t *node = YP_ALLOC_NODE(parser, yp_missing_node_t);
    *node = (yp_missing_node_t) {{ .type = YP_MISSING_NODE, .location = { .start = start, .end = end } }};
    return node;
}

// Allocate and initialize a new alias node.
static yp_alias_node_t *
yp_alias_node_create(yp_parser_t *parser, const yp_token_t *keyword, yp_node_t *new_name, yp_node_t *old_name) {
    assert(keyword->type == YP_TOKEN_KEYWORD_ALIAS);
    yp_alias_node_t *node = YP_ALLOC_NODE(parser, yp_alias_node_t);

    *node = (yp_alias_node_t) {
        {
            .type = YP_ALIAS_NODE,
            .location = {
                .start = keyword->start,
                .end = old_name->location.end
            },
        },
        .new_name = new_name,
        .old_name = old_name,
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword)
    };

    return node;
}

// Allocate a new AlternationPatternNode node.
static yp_alternation_pattern_node_t *
yp_alternation_pattern_node_create(yp_parser_t *parser, yp_node_t *left, yp_node_t *right, const yp_token_t *operator) {
    yp_alternation_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_alternation_pattern_node_t);

    *node = (yp_alternation_pattern_node_t) {
        {
            .type = YP_ALTERNATION_PATTERN_NODE,
            .location = {
                .start = left->location.start,
                .end = right->location.end
            },
        },
        .left = left,
        .right = right,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new and node.
static yp_and_node_t *
yp_and_node_create(yp_parser_t *parser, yp_node_t *left, const yp_token_t *operator, yp_node_t *right) {
    yp_and_node_t *node = YP_ALLOC_NODE(parser, yp_and_node_t);

    *node = (yp_and_node_t) {
        {
            .type = YP_AND_NODE,
            .location = {
                .start = left->location.start,
                .end = right->location.end
            },
        },
        .left = left,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .right = right
    };

    return node;
}

// Allocate an initialize a new arguments node.
static yp_arguments_node_t *
yp_arguments_node_create(yp_parser_t *parser) {
    yp_arguments_node_t *node = YP_ALLOC_NODE(parser, yp_arguments_node_t);

    *node = (yp_arguments_node_t) {
        {
            .type = YP_ARGUMENTS_NODE,
            .location = YP_LOCATION_NULL_VALUE(parser)
        },
        .arguments = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Return the size of the given arguments node.
static size_t
yp_arguments_node_size(yp_arguments_node_t *node) {
    return node->arguments.size;
}

// Append an argument to an arguments node.
static void
yp_arguments_node_arguments_append(yp_arguments_node_t *node, yp_node_t *argument) {
    if (yp_arguments_node_size(node) == 0) {
        node->base.location.start = argument->location.start;
    }

    node->base.location.end = argument->location.end;
    yp_node_list_append(&node->arguments, argument);
}

// Allocate and initialize a new ArrayNode node.
static yp_array_node_t *
yp_array_node_create(yp_parser_t *parser, const yp_token_t *opening) {
    yp_array_node_t *node = YP_ALLOC_NODE(parser, yp_array_node_t);

    *node = (yp_array_node_t) {
        {
            .type = YP_ARRAY_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(opening)
        },
        .opening_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .elements = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Return the size of the given array node.
static inline size_t
yp_array_node_size(yp_array_node_t *node) {
    return node->elements.size;
}

// Append an argument to an array node.
static inline void
yp_array_node_elements_append(yp_array_node_t *node, yp_node_t *element) {
    if (!node->elements.size && !node->opening_loc.start) {
        node->base.location.start = element->location.start;
    }
    yp_node_list_append(&node->elements, element);
    node->base.location.end = element->location.end;
}

// Set the closing token and end location of an array node.
static void
yp_array_node_close_set(yp_array_node_t *node, const yp_token_t *closing) {
    assert(closing->type == YP_TOKEN_BRACKET_RIGHT || closing->type == YP_TOKEN_STRING_END || closing->type == YP_TOKEN_MISSING || closing->type == YP_TOKEN_NOT_PROVIDED);
    node->base.location.end = closing->end;
    node->closing_loc = YP_LOCATION_TOKEN_VALUE(closing);
}

// Allocate and initialize a new array pattern node. The node list given in the
// nodes parameter is guaranteed to have at least two nodes.
static yp_array_pattern_node_t *
yp_array_pattern_node_node_list_create(yp_parser_t *parser, yp_node_list_t *nodes) {
    yp_array_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_array_pattern_node_t);

    *node = (yp_array_pattern_node_t) {
        {
            .type = YP_ARRAY_PATTERN_NODE,
            .location = {
                .start = nodes->nodes[0]->location.start,
                .end = nodes->nodes[nodes->size - 1]->location.end
            },
        },
        .constant = NULL,
        .rest = NULL,
        .requireds = YP_EMPTY_NODE_LIST,
        .posts = YP_EMPTY_NODE_LIST,
        .opening_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    // For now we're going to just copy over each pointer manually. This could be
    // much more efficient, as we could instead resize the node list.
    bool found_rest = false;
    for (size_t index = 0; index < nodes->size; index++) {
        yp_node_t *child = nodes->nodes[index];

        if (!found_rest && YP_NODE_TYPE_P(child, YP_SPLAT_NODE)) {
            node->rest = child;
            found_rest = true;
        } else if (found_rest) {
            yp_node_list_append(&node->posts, child);
        } else {
            yp_node_list_append(&node->requireds, child);
        }
    }

    return node;
}

// Allocate and initialize a new array pattern node from a single rest node.
static yp_array_pattern_node_t *
yp_array_pattern_node_rest_create(yp_parser_t *parser, yp_node_t *rest) {
    yp_array_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_array_pattern_node_t);

    *node = (yp_array_pattern_node_t) {
        {
            .type = YP_ARRAY_PATTERN_NODE,
            .location = rest->location,
        },
        .constant = NULL,
        .rest = rest,
        .requireds = YP_EMPTY_NODE_LIST,
        .posts = YP_EMPTY_NODE_LIST,
        .opening_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    return node;
}

// Allocate and initialize a new array pattern node from a constant and opening
// and closing tokens.
static yp_array_pattern_node_t *
yp_array_pattern_node_constant_create(yp_parser_t *parser, yp_node_t *constant, const yp_token_t *opening, const yp_token_t *closing) {
    yp_array_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_array_pattern_node_t);

    *node = (yp_array_pattern_node_t) {
        {
            .type = YP_ARRAY_PATTERN_NODE,
            .location = {
                .start = constant->location.start,
                .end = closing->end
            },
        },
        .constant = constant,
        .rest = NULL,
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing),
        .requireds = YP_EMPTY_NODE_LIST,
        .posts = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Allocate and initialize a new array pattern node from an opening and closing
// token.
static yp_array_pattern_node_t *
yp_array_pattern_node_empty_create(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *closing) {
    yp_array_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_array_pattern_node_t);

    *node = (yp_array_pattern_node_t) {
        {
            .type = YP_ARRAY_PATTERN_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end
            },
        },
        .constant = NULL,
        .rest = NULL,
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing),
        .requireds = YP_EMPTY_NODE_LIST,
        .posts = YP_EMPTY_NODE_LIST
    };

    return node;
}

static inline void
yp_array_pattern_node_requireds_append(yp_array_pattern_node_t *node, yp_node_t *inner) {
    yp_node_list_append(&node->requireds, inner);
}

// Allocate and initialize a new assoc node.
static yp_assoc_node_t *
yp_assoc_node_create(yp_parser_t *parser, yp_node_t *key, const yp_token_t *operator, yp_node_t *value) {
    yp_assoc_node_t *node = YP_ALLOC_NODE(parser, yp_assoc_node_t);
    const uint8_t *end;

    if (value != NULL) {
        end = value->location.end;
    } else if (operator->type != YP_TOKEN_NOT_PROVIDED) {
        end = operator->end;
    } else {
        end = key->location.end;
    }

    *node = (yp_assoc_node_t) {
        {
            .type = YP_ASSOC_NODE,
            .location = {
                .start = key->location.start,
                .end = end
            },
        },
        .key = key,
        .operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new assoc splat node.
static yp_assoc_splat_node_t *
yp_assoc_splat_node_create(yp_parser_t *parser, yp_node_t *value, const yp_token_t *operator) {
    assert(operator->type == YP_TOKEN_USTAR_STAR);
    yp_assoc_splat_node_t *node = YP_ALLOC_NODE(parser, yp_assoc_splat_node_t);

    *node = (yp_assoc_splat_node_t) {
        {
            .type = YP_ASSOC_SPLAT_NODE,
            .location = {
                .start = operator->start,
                .end = value == NULL ? operator->end : value->location.end
            },
        },
        .value = value,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate a new BackReferenceReadNode node.
static yp_back_reference_read_node_t *
yp_back_reference_read_node_create(yp_parser_t *parser, const yp_token_t *name) {
    assert(name->type == YP_TOKEN_BACK_REFERENCE);
    yp_back_reference_read_node_t *node = YP_ALLOC_NODE(parser, yp_back_reference_read_node_t);

    *node = (yp_back_reference_read_node_t) {
        {
            .type = YP_BACK_REFERENCE_READ_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(name),
        }
    };

    return node;
}

// Allocate and initialize new a begin node.
static yp_begin_node_t *
yp_begin_node_create(yp_parser_t *parser, const yp_token_t *begin_keyword, yp_statements_node_t *statements) {
    yp_begin_node_t *node = YP_ALLOC_NODE(parser, yp_begin_node_t);

    *node = (yp_begin_node_t) {
        {
            .type = YP_BEGIN_NODE,
            .location = {
                .start = begin_keyword->start,
                .end = statements == NULL ? begin_keyword->end : statements->base.location.end
            },
        },
        .begin_keyword_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(begin_keyword),
        .statements = statements,
        .end_keyword_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    return node;
}

// Set the rescue clause, optionally start, and end location of a begin node.
static void
yp_begin_node_rescue_clause_set(yp_begin_node_t *node, yp_rescue_node_t *rescue_clause) {
    // If the begin keyword doesn't exist, we set the start on the begin_node
    if (!node->begin_keyword_loc.start) {
        node->base.location.start = rescue_clause->base.location.start;
    }
    node->base.location.end = rescue_clause->base.location.end;
    node->rescue_clause = rescue_clause;
}

// Set the else clause and end location of a begin node.
static void
yp_begin_node_else_clause_set(yp_begin_node_t *node, yp_else_node_t *else_clause) {
    node->base.location.end = else_clause->base.location.end;
    node->else_clause = else_clause;
}

// Set the ensure clause and end location of a begin node.
static void
yp_begin_node_ensure_clause_set(yp_begin_node_t *node, yp_ensure_node_t *ensure_clause) {
    node->base.location.end = ensure_clause->base.location.end;
    node->ensure_clause = ensure_clause;
}

// Set the end keyword and end location of a begin node.
static void
yp_begin_node_end_keyword_set(yp_begin_node_t *node, const yp_token_t *end_keyword) {
    assert(end_keyword->type == YP_TOKEN_KEYWORD_END || end_keyword->type == YP_TOKEN_MISSING);

    node->base.location.end = end_keyword->end;
    node->end_keyword_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(end_keyword);
}

// Allocate and initialize a new BlockArgumentNode node.
static yp_block_argument_node_t *
yp_block_argument_node_create(yp_parser_t *parser, const yp_token_t *operator, yp_node_t *expression) {
    yp_block_argument_node_t *node = YP_ALLOC_NODE(parser, yp_block_argument_node_t);

    *node = (yp_block_argument_node_t) {
        {
            .type = YP_BLOCK_ARGUMENT_NODE,
            .location = {
                .start = operator->start,
                .end = expression == NULL ? operator->end : expression->location.end
            },
        },
        .expression = expression,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new BlockNode node.
static yp_block_node_t *
yp_block_node_create(yp_parser_t *parser, yp_constant_id_list_t *locals, const yp_token_t *opening, yp_block_parameters_node_t *parameters, yp_node_t *body, const yp_token_t *closing) {
    yp_block_node_t *node = YP_ALLOC_NODE(parser, yp_block_node_t);

    *node = (yp_block_node_t) {
        {
            .type = YP_BLOCK_NODE,
            .location = { .start = opening->start, .end = closing->end },
        },
        .locals = *locals,
        .parameters = parameters,
        .body = body,
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing)
    };

    return node;
}

// Allocate and initialize a new BlockParameterNode node.
static yp_block_parameter_node_t *
yp_block_parameter_node_create(yp_parser_t *parser, const yp_token_t *name, const yp_token_t *operator) {
    assert(operator->type == YP_TOKEN_NOT_PROVIDED || operator->type == YP_TOKEN_UAMPERSAND || operator->type == YP_TOKEN_AMPERSAND);
    yp_block_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_block_parameter_node_t);

    *node = (yp_block_parameter_node_t) {
        {
            .type = YP_BLOCK_PARAMETER_NODE,
            .location = {
                .start = operator->start,
                .end = (name->type == YP_TOKEN_NOT_PROVIDED ? operator->end : name->end)
            },
        },
        .name = yp_parser_optional_constant_id_token(parser, name),
        .name_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(name),
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new BlockParametersNode node.
static yp_block_parameters_node_t *
yp_block_parameters_node_create(yp_parser_t *parser, yp_parameters_node_t *parameters, const yp_token_t *opening) {
    yp_block_parameters_node_t *node = YP_ALLOC_NODE(parser, yp_block_parameters_node_t);

    const uint8_t *start;
    if (opening->type != YP_TOKEN_NOT_PROVIDED) {
        start = opening->start;
    } else if (parameters != NULL) {
        start = parameters->base.location.start;
    } else {
        start = NULL;
    }

    const uint8_t *end;
    if (parameters != NULL) {
        end = parameters->base.location.end;
    } else if (opening->type != YP_TOKEN_NOT_PROVIDED) {
        end = opening->end;
    } else {
        end = NULL;
    }

    *node = (yp_block_parameters_node_t) {
        {
            .type = YP_BLOCK_PARAMETERS_NODE,
            .location = {
                .start = start,
                .end = end
            }
        },
        .parameters = parameters,
        .opening_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .locals = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Set the closing location of a BlockParametersNode node.
static void
yp_block_parameters_node_closing_set(yp_block_parameters_node_t *node, const yp_token_t *closing) {
    assert(closing->type == YP_TOKEN_PIPE || closing->type == YP_TOKEN_PARENTHESIS_RIGHT || closing->type == YP_TOKEN_MISSING);

    node->base.location.end = closing->end;
    node->closing_loc = YP_LOCATION_TOKEN_VALUE(closing);
}

// Allocate and initialize a new BlockLocalVariableNode node.
static yp_block_local_variable_node_t *
yp_block_local_variable_node_create(yp_parser_t *parser, const yp_token_t *name) {
    assert(name->type == YP_TOKEN_IDENTIFIER || name->type == YP_TOKEN_MISSING);
    yp_block_local_variable_node_t *node = YP_ALLOC_NODE(parser, yp_block_local_variable_node_t);

    *node = (yp_block_local_variable_node_t) {
        {
            .type = YP_BLOCK_LOCAL_VARIABLE_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(name),
        },
        .name = yp_parser_constant_id_token(parser, name)
    };

    return node;
}

// Append a new block-local variable to a BlockParametersNode node.
static void
yp_block_parameters_node_append_local(yp_block_parameters_node_t *node, const yp_block_local_variable_node_t *local) {
    yp_node_list_append(&node->locals, (yp_node_t *) local);

    if (node->base.location.start == NULL) node->base.location.start = local->base.location.start;
    node->base.location.end = local->base.location.end;
}

// Allocate and initialize a new BreakNode node.
static yp_break_node_t *
yp_break_node_create(yp_parser_t *parser, const yp_token_t *keyword, yp_arguments_node_t *arguments) {
    assert(keyword->type == YP_TOKEN_KEYWORD_BREAK);
    yp_break_node_t *node = YP_ALLOC_NODE(parser, yp_break_node_t);

    *node = (yp_break_node_t) {
        {
            .type = YP_BREAK_NODE,
            .location = {
                .start = keyword->start,
                .end = (arguments == NULL ? keyword->end : arguments->base.location.end)
            },
        },
        .arguments = arguments,
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword)
    };

    return node;
}

// Allocate and initialize a new CallNode node. This sets everything to NULL or
// YP_TOKEN_NOT_PROVIDED as appropriate such that its values can be overridden
// in the various specializations of this function.
static yp_call_node_t *
yp_call_node_create(yp_parser_t *parser) {
    yp_call_node_t *node = YP_ALLOC_NODE(parser, yp_call_node_t);

    *node = (yp_call_node_t) {
        {
            .type = YP_CALL_NODE,
            .location = YP_LOCATION_NULL_VALUE(parser),
        },
        .receiver = NULL,
        .call_operator_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .message_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .opening_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .arguments = NULL,
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .block = NULL
    };

    return node;
}

// Allocate and initialize a new CallNode node from an aref or an aset
// expression.
static yp_call_node_t *
yp_call_node_aref_create(yp_parser_t *parser, yp_node_t *receiver, yp_arguments_t *arguments) {
    yp_call_node_t *node = yp_call_node_create(parser);

    node->base.location.start = receiver->location.start;
    if (arguments->block != NULL) {
        node->base.location.end = arguments->block->base.location.end;
    } else {
        node->base.location.end = arguments->closing_loc.end;
    }

    node->receiver = receiver;
    node->message_loc.start = arguments->opening_loc.start;
    node->message_loc.end = arguments->closing_loc.end;

    node->opening_loc = arguments->opening_loc;
    node->arguments = arguments->arguments;
    node->closing_loc = arguments->closing_loc;
    node->block = arguments->block;

    yp_string_constant_init(&node->name, "[]", 2);
    return node;
}

// Allocate and initialize a new CallNode node from a binary expression.
static yp_call_node_t *
yp_call_node_binary_create(yp_parser_t *parser, yp_node_t *receiver, yp_token_t *operator, yp_node_t *argument) {
    yp_call_node_t *node = yp_call_node_create(parser);

    node->base.location.start = MIN(receiver->location.start, argument->location.start);
    node->base.location.end = MAX(receiver->location.end, argument->location.end);

    node->receiver = receiver;
    node->message_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator);

    yp_arguments_node_t *arguments = yp_arguments_node_create(parser);
    yp_arguments_node_arguments_append(arguments, argument);
    node->arguments = arguments;

    yp_string_shared_init(&node->name, operator->start, operator->end);
    return node;
}

// Allocate and initialize a new CallNode node from a call expression.
static yp_call_node_t *
yp_call_node_call_create(yp_parser_t *parser, yp_node_t *receiver, yp_token_t *operator, yp_token_t *message, yp_arguments_t *arguments) {
    yp_call_node_t *node = yp_call_node_create(parser);

    node->base.location.start = receiver->location.start;
    if (arguments->block != NULL) {
        node->base.location.end = arguments->block->base.location.end;
    } else if (arguments->closing_loc.start != NULL) {
        node->base.location.end = arguments->closing_loc.end;
    } else if (arguments->arguments != NULL) {
        node->base.location.end = arguments->arguments->base.location.end;
    } else {
        node->base.location.end = message->end;
    }

    node->receiver = receiver;
    node->call_operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator);
    node->message_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(message);
    node->opening_loc = arguments->opening_loc;
    node->arguments = arguments->arguments;
    node->closing_loc = arguments->closing_loc;
    node->block = arguments->block;

    if (operator->type == YP_TOKEN_AMPERSAND_DOT) {
        node->base.flags |= YP_CALL_NODE_FLAGS_SAFE_NAVIGATION;
    }

    yp_string_shared_init(&node->name, message->start, message->end);
    return node;
}

// Allocate and initialize a new CallNode node from a call to a method name
// without a receiver that could not have been a local variable read.
static yp_call_node_t *
yp_call_node_fcall_create(yp_parser_t *parser, yp_token_t *message, yp_arguments_t *arguments) {
    yp_call_node_t *node = yp_call_node_create(parser);

    node->base.location.start = message->start;
    if (arguments->block != NULL) {
        node->base.location.end = arguments->block->base.location.end;
    } else if (arguments->closing_loc.start != NULL) {
        node->base.location.end = arguments->closing_loc.end;
    } else if (arguments->arguments != NULL) {
        node->base.location.end = arguments->arguments->base.location.end;
    } else {
        node->base.location.end = arguments->closing_loc.end;
    }

    node->message_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(message);
    node->opening_loc = arguments->opening_loc;
    node->arguments = arguments->arguments;
    node->closing_loc = arguments->closing_loc;
    node->block = arguments->block;

    yp_string_shared_init(&node->name, message->start, message->end);
    return node;
}

// Allocate and initialize a new CallNode node from a not expression.
static yp_call_node_t *
yp_call_node_not_create(yp_parser_t *parser, yp_node_t *receiver, yp_token_t *message, yp_arguments_t *arguments) {
    yp_call_node_t *node = yp_call_node_create(parser);

    node->base.location.start = message->start;
    if (arguments->closing_loc.start != NULL) {
        node->base.location.end = arguments->closing_loc.end;
    } else {
        node->base.location.end = receiver->location.end;
    }

    node->receiver = receiver;
    node->message_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(message);
    node->opening_loc = arguments->opening_loc;
    node->arguments = arguments->arguments;
    node->closing_loc = arguments->closing_loc;

    yp_string_constant_init(&node->name, "!", 1);
    return node;
}

// Allocate and initialize a new CallNode node from a call shorthand expression.
static yp_call_node_t *
yp_call_node_shorthand_create(yp_parser_t *parser, yp_node_t *receiver, yp_token_t *operator, yp_arguments_t *arguments) {
    yp_call_node_t *node = yp_call_node_create(parser);

    node->base.location.start = receiver->location.start;
    if (arguments->block != NULL) {
        node->base.location.end = arguments->block->base.location.end;
    } else {
        node->base.location.end = arguments->closing_loc.end;
    }

    node->receiver = receiver;
    node->call_operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator);
    node->opening_loc = arguments->opening_loc;
    node->arguments = arguments->arguments;
    node->closing_loc = arguments->closing_loc;
    node->block = arguments->block;

    if (operator->type == YP_TOKEN_AMPERSAND_DOT) {
        node->base.flags |= YP_CALL_NODE_FLAGS_SAFE_NAVIGATION;
    }

    yp_string_constant_init(&node->name, "call", 4);
    return node;
}

// Allocate and initialize a new CallNode node from a unary operator expression.
static yp_call_node_t *
yp_call_node_unary_create(yp_parser_t *parser, yp_token_t *operator, yp_node_t *receiver, const char *name) {
    yp_call_node_t *node = yp_call_node_create(parser);

    node->base.location.start = operator->start;
    node->base.location.end = receiver->location.end;

    node->receiver = receiver;
    node->message_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator);

    yp_string_constant_init(&node->name, name, strlen(name));
    return node;
}

// Allocate and initialize a new CallNode node from a call to a method name
// without a receiver that could also have been a local variable read.
static yp_call_node_t *
yp_call_node_variable_call_create(yp_parser_t *parser, yp_token_t *message) {
    yp_call_node_t *node = yp_call_node_create(parser);

    node->base.location = YP_LOCATION_TOKEN_VALUE(message);
    node->message_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(message);

    yp_string_shared_init(&node->name, message->start, message->end);
    return node;
}

// Returns whether or not this call node is a "vcall" (a call to a method name
// without a receiver that could also have been a local variable read).
static inline bool
yp_call_node_variable_call_p(yp_call_node_t *node) {
    return node->base.flags & YP_CALL_NODE_FLAGS_VARIABLE_CALL;
}

// Initialize the read name by reading the write name and chopping off the '='.
static void
yp_call_write_read_name_init(yp_string_t *read_name, yp_string_t *write_name) {
    size_t length = write_name->length - 1;

    void *memory = malloc(length);
    memcpy(memory, write_name->source, length);

    yp_string_owned_init(read_name, (uint8_t *) memory, length);
}

// Allocate and initialize a new CallAndWriteNode node.
static yp_call_and_write_node_t *
yp_call_and_write_node_create(yp_parser_t *parser, yp_call_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(target->block == NULL);
    assert(operator->type == YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL);
    yp_call_and_write_node_t *node = YP_ALLOC_NODE(parser, yp_call_and_write_node_t);

    *node = (yp_call_and_write_node_t) {
        {
            .type = YP_CALL_AND_WRITE_NODE,
            .flags = target->base.flags,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .receiver = target->receiver,
        .call_operator_loc = target->call_operator_loc,
        .message_loc = target->message_loc,
        .opening_loc = target->opening_loc,
        .arguments = target->arguments,
        .closing_loc = target->closing_loc,
        .read_name = YP_EMPTY_STRING,
        .write_name = target->name,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    yp_call_write_read_name_init(&node->read_name, &node->write_name);

    // Here we're going to free the target, since it is no longer necessary.
    // However, we don't want to call `yp_node_destroy` because we want to keep
    // around all of its children since we just reused them.
    free(target);

    return node;
}

// Allocate a new CallOperatorWriteNode node.
static yp_call_operator_write_node_t *
yp_call_operator_write_node_create(yp_parser_t *parser, yp_call_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(target->block == NULL);
    yp_call_operator_write_node_t *node = YP_ALLOC_NODE(parser, yp_call_operator_write_node_t);

    *node = (yp_call_operator_write_node_t) {
        {
            .type = YP_CALL_OPERATOR_WRITE_NODE,
            .flags = target->base.flags,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .receiver = target->receiver,
        .call_operator_loc = target->call_operator_loc,
        .message_loc = target->message_loc,
        .opening_loc = target->opening_loc,
        .arguments = target->arguments,
        .closing_loc = target->closing_loc,
        .read_name = YP_EMPTY_STRING,
        .write_name = target->name,
        .operator = yp_parser_constant_id_location(parser, operator->start, operator->end - 1),
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    yp_call_write_read_name_init(&node->read_name, &node->write_name);

    // Here we're going to free the target, since it is no longer necessary.
    // However, we don't want to call `yp_node_destroy` because we want to keep
    // around all of its children since we just reused them.
    free(target);

    return node;
}

// Allocate and initialize a new CallOperatorOrWriteNode node.
static yp_call_or_write_node_t *
yp_call_or_write_node_create(yp_parser_t *parser, yp_call_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(target->block == NULL);
    assert(operator->type == YP_TOKEN_PIPE_PIPE_EQUAL);
    yp_call_or_write_node_t *node = YP_ALLOC_NODE(parser, yp_call_or_write_node_t);

    *node = (yp_call_or_write_node_t) {
        {
            .type = YP_CALL_OR_WRITE_NODE,
            .flags = target->base.flags,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .receiver = target->receiver,
        .call_operator_loc = target->call_operator_loc,
        .message_loc = target->message_loc,
        .opening_loc = target->opening_loc,
        .arguments = target->arguments,
        .closing_loc = target->closing_loc,
        .read_name = YP_EMPTY_STRING,
        .write_name = target->name,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    yp_call_write_read_name_init(&node->read_name, &node->write_name);

    // Here we're going to free the target, since it is no longer necessary.
    // However, we don't want to call `yp_node_destroy` because we want to keep
    // around all of its children since we just reused them.
    free(target);

    return node;
}

// Allocate and initialize a new CapturePatternNode node.
static yp_capture_pattern_node_t *
yp_capture_pattern_node_create(yp_parser_t *parser, yp_node_t *value, yp_node_t *target, const yp_token_t *operator) {
    yp_capture_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_capture_pattern_node_t);

    *node = (yp_capture_pattern_node_t) {
        {
            .type = YP_CAPTURE_PATTERN_NODE,
            .location = {
                .start = value->location.start,
                .end = target->location.end
            },
        },
        .value = value,
        .target = target,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new CaseNode node.
static yp_case_node_t *
yp_case_node_create(yp_parser_t *parser, const yp_token_t *case_keyword, yp_node_t *predicate, yp_else_node_t *consequent, const yp_token_t *end_keyword) {
    yp_case_node_t *node = YP_ALLOC_NODE(parser, yp_case_node_t);

    *node = (yp_case_node_t) {
        {
            .type = YP_CASE_NODE,
            .location = {
                .start = case_keyword->start,
                .end = end_keyword->end
            },
        },
        .predicate = predicate,
        .consequent = consequent,
        .case_keyword_loc = YP_LOCATION_TOKEN_VALUE(case_keyword),
        .end_keyword_loc = YP_LOCATION_TOKEN_VALUE(end_keyword),
        .conditions = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Append a new condition to a CaseNode node.
static void
yp_case_node_condition_append(yp_case_node_t *node, yp_node_t *condition) {
    assert(YP_NODE_TYPE_P(condition, YP_WHEN_NODE) || YP_NODE_TYPE_P(condition, YP_IN_NODE));

    yp_node_list_append(&node->conditions, condition);
    node->base.location.end = condition->location.end;
}

// Set the consequent of a CaseNode node.
static void
yp_case_node_consequent_set(yp_case_node_t *node, yp_else_node_t *consequent) {
    node->consequent = consequent;
    node->base.location.end = consequent->base.location.end;
}

// Set the end location for a CaseNode node.
static void
yp_case_node_end_keyword_loc_set(yp_case_node_t *node, const yp_token_t *end_keyword) {
    node->base.location.end = end_keyword->end;
    node->end_keyword_loc = YP_LOCATION_TOKEN_VALUE(end_keyword);
}

// Allocate a new ClassNode node.
static yp_class_node_t *
yp_class_node_create(yp_parser_t *parser, yp_constant_id_list_t *locals, const yp_token_t *class_keyword, yp_node_t *constant_path, const yp_token_t *name, const yp_token_t *inheritance_operator, yp_node_t *superclass, yp_node_t *body, const yp_token_t *end_keyword) {
    yp_class_node_t *node = YP_ALLOC_NODE(parser, yp_class_node_t);

    *node = (yp_class_node_t) {
        {
            .type = YP_CLASS_NODE,
            .location = { .start = class_keyword->start, .end = end_keyword->end },
        },
        .locals = *locals,
        .class_keyword_loc = YP_LOCATION_TOKEN_VALUE(class_keyword),
        .constant_path = constant_path,
        .inheritance_operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(inheritance_operator),
        .superclass = superclass,
        .body = body,
        .end_keyword_loc = YP_LOCATION_TOKEN_VALUE(end_keyword),
        .name = yp_parser_constant_id_token(parser, name)
    };

    return node;
}

// Allocate and initialize a new ClassVariableAndWriteNode node.
static yp_class_variable_and_write_node_t *
yp_class_variable_and_write_node_create(yp_parser_t *parser, yp_class_variable_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL);
    yp_class_variable_and_write_node_t *node = YP_ALLOC_NODE(parser, yp_class_variable_and_write_node_t);

    *node = (yp_class_variable_and_write_node_t) {
        {
            .type = YP_CLASS_VARIABLE_AND_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new ClassVariableOperatorWriteNode node.
static yp_class_variable_operator_write_node_t *
yp_class_variable_operator_write_node_create(yp_parser_t *parser, yp_class_variable_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_class_variable_operator_write_node_t *node = YP_ALLOC_NODE(parser, yp_class_variable_operator_write_node_t);

    *node = (yp_class_variable_operator_write_node_t) {
        {
            .type = YP_CLASS_VARIABLE_OPERATOR_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value,
        .operator = yp_parser_constant_id_location(parser, operator->start, operator->end - 1)
    };

    return node;
}

// Allocate and initialize a new ClassVariableOrWriteNode node.
static yp_class_variable_or_write_node_t *
yp_class_variable_or_write_node_create(yp_parser_t *parser, yp_class_variable_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_PIPE_PIPE_EQUAL);
    yp_class_variable_or_write_node_t *node = YP_ALLOC_NODE(parser, yp_class_variable_or_write_node_t);

    *node = (yp_class_variable_or_write_node_t) {
        {
            .type = YP_CLASS_VARIABLE_OR_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new ClassVariableReadNode node.
static yp_class_variable_read_node_t *
yp_class_variable_read_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_CLASS_VARIABLE);
    yp_class_variable_read_node_t *node = YP_ALLOC_NODE(parser, yp_class_variable_read_node_t);

    *node = (yp_class_variable_read_node_t) {
        {
            .type = YP_CLASS_VARIABLE_READ_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .name = yp_parser_constant_id_token(parser, token)
    };

    return node;
}

// Initialize a new ClassVariableWriteNode node from a ClassVariableRead node.
static yp_class_variable_write_node_t *
yp_class_variable_write_node_create(yp_parser_t *parser, yp_class_variable_read_node_t *read_node, yp_token_t *operator, yp_node_t *value) {
    yp_class_variable_write_node_t *node = YP_ALLOC_NODE(parser, yp_class_variable_write_node_t);

    *node = (yp_class_variable_write_node_t) {
        {
            .type = YP_CLASS_VARIABLE_WRITE_NODE,
            .location = {
                .start = read_node->base.location.start,
                .end = value->location.end
            },
        },
        .name = read_node->name,
        .name_loc = YP_LOCATION_NODE_VALUE((yp_node_t *) read_node),
        .operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new ConstantPathAndWriteNode node.
static yp_constant_path_and_write_node_t *
yp_constant_path_and_write_node_create(yp_parser_t *parser, yp_constant_path_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL);
    yp_constant_path_and_write_node_t *node = YP_ALLOC_NODE(parser, yp_constant_path_and_write_node_t);

    *node = (yp_constant_path_and_write_node_t) {
        {
            .type = YP_CONSTANT_PATH_AND_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .target = target,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new ConstantPathOperatorWriteNode node.
static yp_constant_path_operator_write_node_t *
yp_constant_path_operator_write_node_create(yp_parser_t *parser, yp_constant_path_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_constant_path_operator_write_node_t *node = YP_ALLOC_NODE(parser, yp_constant_path_operator_write_node_t);

    *node = (yp_constant_path_operator_write_node_t) {
        {
            .type = YP_CONSTANT_PATH_OPERATOR_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .target = target,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value,
        .operator = yp_parser_constant_id_location(parser, operator->start, operator->end - 1)
    };

    return node;
}

// Allocate and initialize a new ConstantPathOrWriteNode node.
static yp_constant_path_or_write_node_t *
yp_constant_path_or_write_node_create(yp_parser_t *parser, yp_constant_path_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_PIPE_PIPE_EQUAL);
    yp_constant_path_or_write_node_t *node = YP_ALLOC_NODE(parser, yp_constant_path_or_write_node_t);

    *node = (yp_constant_path_or_write_node_t) {
        {
            .type = YP_CONSTANT_PATH_OR_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .target = target,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new ConstantPathNode node.
static yp_constant_path_node_t *
yp_constant_path_node_create(yp_parser_t *parser, yp_node_t *parent, const yp_token_t *delimiter, yp_node_t *child) {
    yp_constant_path_node_t *node = YP_ALLOC_NODE(parser, yp_constant_path_node_t);

    *node = (yp_constant_path_node_t) {
        {
            .type = YP_CONSTANT_PATH_NODE,
            .location = {
                .start = parent == NULL ? delimiter->start : parent->location.start,
                .end = child->location.end
            },
        },
        .parent = parent,
        .child = child,
        .delimiter_loc = YP_LOCATION_TOKEN_VALUE(delimiter)
    };

    return node;
}

// Allocate a new ConstantPathWriteNode node.
static yp_constant_path_write_node_t *
yp_constant_path_write_node_create(yp_parser_t *parser, yp_constant_path_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_constant_path_write_node_t *node = YP_ALLOC_NODE(parser, yp_constant_path_write_node_t);

    *node = (yp_constant_path_write_node_t) {
        {
            .type = YP_CONSTANT_PATH_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            },
        },
        .target = target,
        .operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new ConstantAndWriteNode node.
static yp_constant_and_write_node_t *
yp_constant_and_write_node_create(yp_parser_t *parser, yp_constant_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL);
    yp_constant_and_write_node_t *node = YP_ALLOC_NODE(parser, yp_constant_and_write_node_t);

    *node = (yp_constant_and_write_node_t) {
        {
            .type = YP_CONSTANT_AND_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new ConstantOperatorWriteNode node.
static yp_constant_operator_write_node_t *
yp_constant_operator_write_node_create(yp_parser_t *parser, yp_constant_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_constant_operator_write_node_t *node = YP_ALLOC_NODE(parser, yp_constant_operator_write_node_t);

    *node = (yp_constant_operator_write_node_t) {
        {
            .type = YP_CONSTANT_OPERATOR_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value,
        .operator = yp_parser_constant_id_location(parser, operator->start, operator->end - 1)
    };

    return node;
}

// Allocate and initialize a new ConstantOrWriteNode node.
static yp_constant_or_write_node_t *
yp_constant_or_write_node_create(yp_parser_t *parser, yp_constant_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_PIPE_PIPE_EQUAL);
    yp_constant_or_write_node_t *node = YP_ALLOC_NODE(parser, yp_constant_or_write_node_t);

    *node = (yp_constant_or_write_node_t) {
        {
            .type = YP_CONSTANT_OR_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new ConstantReadNode node.
static yp_constant_read_node_t *
yp_constant_read_node_create(yp_parser_t *parser, const yp_token_t *name) {
    assert(name->type == YP_TOKEN_CONSTANT || name->type == YP_TOKEN_MISSING);
    yp_constant_read_node_t *node = YP_ALLOC_NODE(parser, yp_constant_read_node_t);

    *node = (yp_constant_read_node_t) {
        {
            .type = YP_CONSTANT_READ_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(name)
        },
        .name = yp_parser_constant_id_token(parser, name)
    };

    return node;
}

// Allocate a new ConstantWriteNode node.
static yp_constant_write_node_t *
yp_constant_write_node_create(yp_parser_t *parser, yp_constant_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_constant_write_node_t *node = YP_ALLOC_NODE(parser, yp_constant_write_node_t);

    *node = (yp_constant_write_node_t) {
        {
            .type = YP_CONSTANT_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new DefNode node.
static yp_def_node_t *
yp_def_node_create(
    yp_parser_t *parser,
    const yp_token_t *name,
    yp_node_t *receiver,
    yp_parameters_node_t *parameters,
    yp_node_t *body,
    yp_constant_id_list_t *locals,
    const yp_token_t *def_keyword,
    const yp_token_t *operator,
    const yp_token_t *lparen,
    const yp_token_t *rparen,
    const yp_token_t *equal,
    const yp_token_t *end_keyword
) {
    yp_def_node_t *node = YP_ALLOC_NODE(parser, yp_def_node_t);
    const uint8_t *end;

    if (end_keyword->type == YP_TOKEN_NOT_PROVIDED) {
        end = body->location.end;
    } else {
        end = end_keyword->end;
    }

    *node = (yp_def_node_t) {
        {
            .type = YP_DEF_NODE,
            .location = { .start = def_keyword->start, .end = end },
        },
        .name = yp_parser_constant_id_token(parser, name),
        .name_loc = YP_LOCATION_TOKEN_VALUE(name),
        .receiver = receiver,
        .parameters = parameters,
        .body = body,
        .locals = *locals,
        .def_keyword_loc = YP_LOCATION_TOKEN_VALUE(def_keyword),
        .operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator),
        .lparen_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(lparen),
        .rparen_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(rparen),
        .equal_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(equal),
        .end_keyword_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(end_keyword)
    };

    return node;
}

// Allocate a new DefinedNode node.
static yp_defined_node_t *
yp_defined_node_create(yp_parser_t *parser, const yp_token_t *lparen, yp_node_t *value, const yp_token_t *rparen, const yp_location_t *keyword_loc) {
    yp_defined_node_t *node = YP_ALLOC_NODE(parser, yp_defined_node_t);

    *node = (yp_defined_node_t) {
        {
            .type = YP_DEFINED_NODE,
            .location = {
                .start = keyword_loc->start,
                .end = (rparen->type == YP_TOKEN_NOT_PROVIDED ? value->location.end : rparen->end)
            },
        },
        .lparen_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(lparen),
        .value = value,
        .rparen_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(rparen),
        .keyword_loc = *keyword_loc
    };

    return node;
}

// Allocate and initialize a new ElseNode node.
static yp_else_node_t *
yp_else_node_create(yp_parser_t *parser, const yp_token_t *else_keyword, yp_statements_node_t *statements, const yp_token_t *end_keyword) {
    yp_else_node_t *node = YP_ALLOC_NODE(parser, yp_else_node_t);
    const uint8_t *end = NULL;
    if ((end_keyword->type == YP_TOKEN_NOT_PROVIDED) && (statements != NULL)) {
        end = statements->base.location.end;
    } else {
        end = end_keyword->end;
    }

    *node = (yp_else_node_t) {
        {
            .type = YP_ELSE_NODE,
            .location = {
                .start = else_keyword->start,
                .end = end,
            },
        },
        .else_keyword_loc = YP_LOCATION_TOKEN_VALUE(else_keyword),
        .statements = statements,
        .end_keyword_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(end_keyword)
    };

    return node;
}

// Allocate and initialize a new EmbeddedStatementsNode node.
static yp_embedded_statements_node_t *
yp_embedded_statements_node_create(yp_parser_t *parser, const yp_token_t *opening, yp_statements_node_t *statements, const yp_token_t *closing) {
    yp_embedded_statements_node_t *node = YP_ALLOC_NODE(parser, yp_embedded_statements_node_t);

    *node = (yp_embedded_statements_node_t) {
        {
            .type = YP_EMBEDDED_STATEMENTS_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end
            }
        },
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .statements = statements,
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing)
    };

    return node;
}

// Allocate and initialize a new EmbeddedVariableNode node.
static yp_embedded_variable_node_t *
yp_embedded_variable_node_create(yp_parser_t *parser, const yp_token_t *operator, yp_node_t *variable) {
    yp_embedded_variable_node_t *node = YP_ALLOC_NODE(parser, yp_embedded_variable_node_t);

    *node = (yp_embedded_variable_node_t) {
        {
            .type = YP_EMBEDDED_VARIABLE_NODE,
            .location = {
                .start = operator->start,
                .end = variable->location.end
            }
        },
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .variable = variable
    };

    return node;
}

// Allocate a new EnsureNode node.
static yp_ensure_node_t *
yp_ensure_node_create(yp_parser_t *parser, const yp_token_t *ensure_keyword, yp_statements_node_t *statements, const yp_token_t *end_keyword) {
    yp_ensure_node_t *node = YP_ALLOC_NODE(parser, yp_ensure_node_t);

    *node = (yp_ensure_node_t) {
        {
            .type = YP_ENSURE_NODE,
            .location = {
                .start = ensure_keyword->start,
                .end = end_keyword->end
            },
        },
        .ensure_keyword_loc = YP_LOCATION_TOKEN_VALUE(ensure_keyword),
        .statements = statements,
        .end_keyword_loc = YP_LOCATION_TOKEN_VALUE(end_keyword)
    };

    return node;
}

// Allocate and initialize a new FalseNode node.
static yp_false_node_t *
yp_false_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD_FALSE);
    yp_false_node_t *node = YP_ALLOC_NODE(parser, yp_false_node_t);
    *node = (yp_false_node_t) {{ .type = YP_FALSE_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate and initialize a new find pattern node. The node list given in the
// nodes parameter is guaranteed to have at least two nodes.
static yp_find_pattern_node_t *
yp_find_pattern_node_create(yp_parser_t *parser, yp_node_list_t *nodes) {
    yp_find_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_find_pattern_node_t);

    yp_node_t *left = nodes->nodes[0];
    yp_node_t *right;

    if (nodes->size == 1) {
        right = (yp_node_t *) yp_missing_node_create(parser, left->location.end, left->location.end);
    } else {
        right = nodes->nodes[nodes->size - 1];
    }

    *node = (yp_find_pattern_node_t) {
        {
            .type = YP_FIND_PATTERN_NODE,
            .location = {
                .start = left->location.start,
                .end = right->location.end,
            },
        },
        .constant = NULL,
        .left = left,
        .right = right,
        .requireds = YP_EMPTY_NODE_LIST,
        .opening_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    // For now we're going to just copy over each pointer manually. This could be
    // much more efficient, as we could instead resize the node list to only point
    // to 1...-1.
    for (size_t index = 1; index < nodes->size - 1; index++) {
        yp_node_list_append(&node->requireds, nodes->nodes[index]);
    }

    return node;
}

// Allocate and initialize a new FloatNode node.
static yp_float_node_t *
yp_float_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_FLOAT);
    yp_float_node_t *node = YP_ALLOC_NODE(parser, yp_float_node_t);
    *node = (yp_float_node_t) {{ .type = YP_FLOAT_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate and initialize a new FloatNode node from a FLOAT_IMAGINARY token.
static yp_imaginary_node_t *
yp_float_node_imaginary_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_FLOAT_IMAGINARY);

    yp_imaginary_node_t *node = YP_ALLOC_NODE(parser, yp_imaginary_node_t);
    *node = (yp_imaginary_node_t) {
        {
            .type = YP_IMAGINARY_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .numeric = (yp_node_t *) yp_float_node_create(parser, &((yp_token_t) {
            .type = YP_TOKEN_FLOAT,
            .start = token->start,
            .end = token->end - 1
        }))
    };

    return node;
}

// Allocate and initialize a new FloatNode node from a FLOAT_RATIONAL token.
static yp_rational_node_t *
yp_float_node_rational_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_FLOAT_RATIONAL);

    yp_rational_node_t *node = YP_ALLOC_NODE(parser, yp_rational_node_t);
    *node = (yp_rational_node_t) {
        {
            .type = YP_RATIONAL_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .numeric = (yp_node_t *) yp_float_node_create(parser, &((yp_token_t) {
            .type = YP_TOKEN_FLOAT,
            .start = token->start,
            .end = token->end - 1
        }))
    };

    return node;
}

// Allocate and initialize a new FloatNode node from a FLOAT_RATIONAL_IMAGINARY token.
static yp_imaginary_node_t *
yp_float_node_rational_imaginary_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_FLOAT_RATIONAL_IMAGINARY);

    yp_imaginary_node_t *node = YP_ALLOC_NODE(parser, yp_imaginary_node_t);
    *node = (yp_imaginary_node_t) {
        {
            .type = YP_IMAGINARY_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .numeric = (yp_node_t *) yp_float_node_rational_create(parser, &((yp_token_t) {
            .type = YP_TOKEN_FLOAT_RATIONAL,
            .start = token->start,
            .end = token->end - 1
        }))
    };

    return node;
}

// Allocate and initialize a new ForNode node.
static yp_for_node_t *
yp_for_node_create(
    yp_parser_t *parser,
    yp_node_t *index,
    yp_node_t *collection,
    yp_statements_node_t *statements,
    const yp_token_t *for_keyword,
    const yp_token_t *in_keyword,
    const yp_token_t *do_keyword,
    const yp_token_t *end_keyword
) {
    yp_for_node_t *node = YP_ALLOC_NODE(parser, yp_for_node_t);

    *node = (yp_for_node_t) {
        {
            .type = YP_FOR_NODE,
            .location = {
                .start = for_keyword->start,
                .end = end_keyword->end
            },
        },
        .index = index,
        .collection = collection,
        .statements = statements,
        .for_keyword_loc = YP_LOCATION_TOKEN_VALUE(for_keyword),
        .in_keyword_loc = YP_LOCATION_TOKEN_VALUE(in_keyword),
        .do_keyword_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(do_keyword),
        .end_keyword_loc = YP_LOCATION_TOKEN_VALUE(end_keyword)
    };

    return node;
}

// Allocate and initialize a new ForwardingArgumentsNode node.
static yp_forwarding_arguments_node_t *
yp_forwarding_arguments_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_UDOT_DOT_DOT);
    yp_forwarding_arguments_node_t *node = YP_ALLOC_NODE(parser, yp_forwarding_arguments_node_t);
    *node = (yp_forwarding_arguments_node_t) {{ .type = YP_FORWARDING_ARGUMENTS_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate and initialize a new ForwardingParameterNode node.
static yp_forwarding_parameter_node_t *
yp_forwarding_parameter_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_UDOT_DOT_DOT);
    yp_forwarding_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_forwarding_parameter_node_t);
    *node = (yp_forwarding_parameter_node_t) {{ .type = YP_FORWARDING_PARAMETER_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate and initialize a new ForwardingSuper node.
static yp_forwarding_super_node_t *
yp_forwarding_super_node_create(yp_parser_t *parser, const yp_token_t *token, yp_arguments_t *arguments) {
    assert(token->type == YP_TOKEN_KEYWORD_SUPER);
    yp_forwarding_super_node_t *node = YP_ALLOC_NODE(parser, yp_forwarding_super_node_t);

    *node = (yp_forwarding_super_node_t) {
        {
            .type = YP_FORWARDING_SUPER_NODE,
            .location = {
                .start = token->start,
                .end = arguments->block != NULL ? arguments->block->base.location.end : token->end
            },
        },
        .block = arguments->block
    };

    return node;
}

// Allocate and initialize a new hash pattern node from an opening and closing
// token.
static yp_hash_pattern_node_t *
yp_hash_pattern_node_empty_create(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *closing) {
    yp_hash_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_hash_pattern_node_t);

    *node = (yp_hash_pattern_node_t) {
        {
            .type = YP_HASH_PATTERN_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end
            },
        },
        .constant = NULL,
        .kwrest = NULL,
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing),
        .assocs = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Allocate and initialize a new hash pattern node.
static yp_hash_pattern_node_t *
yp_hash_pattern_node_node_list_create(yp_parser_t *parser, yp_node_list_t *assocs) {
    yp_hash_pattern_node_t *node = YP_ALLOC_NODE(parser, yp_hash_pattern_node_t);

    *node = (yp_hash_pattern_node_t) {
        {
            .type = YP_HASH_PATTERN_NODE,
            .location = {
                .start = assocs->nodes[0]->location.start,
                .end = assocs->nodes[assocs->size - 1]->location.end
            },
        },
        .constant = NULL,
        .kwrest = NULL,
        .assocs = YP_EMPTY_NODE_LIST,
        .opening_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    for (size_t index = 0; index < assocs->size; index++) {
        yp_node_t *assoc = assocs->nodes[index];
        yp_node_list_append(&node->assocs, assoc);
    }

    return node;
}

// Retrieve the name from a node that will become a global variable write node.
static yp_constant_id_t
yp_global_variable_write_name(yp_parser_t *parser, yp_node_t *target) {
    if (YP_NODE_TYPE_P(target, YP_GLOBAL_VARIABLE_READ_NODE)) {
        return ((yp_global_variable_read_node_t *) target)->name;
    }

    assert(YP_NODE_TYPE_P(target, YP_BACK_REFERENCE_READ_NODE) || YP_NODE_TYPE_P(target, YP_NUMBERED_REFERENCE_READ_NODE));

    // This will only ever happen in the event of a syntax error, but we
    // still need to provide something for the node.
    return yp_parser_constant_id_location(parser, target->location.start, target->location.end);
}

// Allocate and initialize a new GlobalVariableAndWriteNode node.
static yp_global_variable_and_write_node_t *
yp_global_variable_and_write_node_create(yp_parser_t *parser, yp_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL);
    yp_global_variable_and_write_node_t *node = YP_ALLOC_NODE(parser, yp_global_variable_and_write_node_t);

    *node = (yp_global_variable_and_write_node_t) {
        {
            .type = YP_GLOBAL_VARIABLE_AND_WRITE_NODE,
            .location = {
                .start = target->location.start,
                .end = value->location.end
            }
        },
        .name = yp_global_variable_write_name(parser, target),
        .name_loc = target->location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new GlobalVariableOperatorWriteNode node.
static yp_global_variable_operator_write_node_t *
yp_global_variable_operator_write_node_create(yp_parser_t *parser, yp_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_global_variable_operator_write_node_t *node = YP_ALLOC_NODE(parser, yp_global_variable_operator_write_node_t);

    *node = (yp_global_variable_operator_write_node_t) {
        {
            .type = YP_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE,
            .location = {
                .start = target->location.start,
                .end = value->location.end
            }
        },
        .name = yp_global_variable_write_name(parser, target),
        .name_loc = target->location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value,
        .operator = yp_parser_constant_id_location(parser, operator->start, operator->end - 1)
    };

    return node;
}

// Allocate and initialize a new GlobalVariableOrWriteNode node.
static yp_global_variable_or_write_node_t *
yp_global_variable_or_write_node_create(yp_parser_t *parser, yp_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_PIPE_PIPE_EQUAL);
    yp_global_variable_or_write_node_t *node = YP_ALLOC_NODE(parser, yp_global_variable_or_write_node_t);

    *node = (yp_global_variable_or_write_node_t) {
        {
            .type = YP_GLOBAL_VARIABLE_OR_WRITE_NODE,
            .location = {
                .start = target->location.start,
                .end = value->location.end
            }
        },
        .name = yp_global_variable_write_name(parser, target),
        .name_loc = target->location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate a new GlobalVariableReadNode node.
static yp_global_variable_read_node_t *
yp_global_variable_read_node_create(yp_parser_t *parser, const yp_token_t *name) {
    yp_global_variable_read_node_t *node = YP_ALLOC_NODE(parser, yp_global_variable_read_node_t);

    *node = (yp_global_variable_read_node_t) {
        {
            .type = YP_GLOBAL_VARIABLE_READ_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(name),
        },
        .name = yp_parser_constant_id_token(parser, name)
    };

    return node;
}

// Allocate a new GlobalVariableWriteNode node.
static yp_global_variable_write_node_t *
yp_global_variable_write_node_create(yp_parser_t *parser, yp_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_global_variable_write_node_t *node = YP_ALLOC_NODE(parser, yp_global_variable_write_node_t);

    *node = (yp_global_variable_write_node_t) {
        {
            .type = YP_GLOBAL_VARIABLE_WRITE_NODE,
            .location = {
                .start = target->location.start,
                .end = value->location.end
            },
        },
        .name = yp_global_variable_write_name(parser, target),
        .name_loc = YP_LOCATION_NODE_VALUE(target),
        .operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate a new HashNode node.
static yp_hash_node_t *
yp_hash_node_create(yp_parser_t *parser, const yp_token_t *opening) {
    assert(opening != NULL);
    yp_hash_node_t *node = YP_ALLOC_NODE(parser, yp_hash_node_t);

    *node = (yp_hash_node_t) {
        {
            .type = YP_HASH_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(opening)
        },
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_NULL_VALUE(parser),
        .elements = YP_EMPTY_NODE_LIST
    };

    return node;
}

static inline void
yp_hash_node_elements_append(yp_hash_node_t *hash, yp_node_t *element) {
    yp_node_list_append(&hash->elements, element);
}

static inline void
yp_hash_node_closing_loc_set(yp_hash_node_t *hash, yp_token_t *token) {
    hash->base.location.end = token->end;
    hash->closing_loc = YP_LOCATION_TOKEN_VALUE(token);
}

// Allocate a new IfNode node.
static yp_if_node_t *
yp_if_node_create(yp_parser_t *parser,
    const yp_token_t *if_keyword,
    yp_node_t *predicate,
    yp_statements_node_t *statements,
    yp_node_t *consequent,
    const yp_token_t *end_keyword
) {
    yp_flip_flop(predicate);
    yp_if_node_t *node = YP_ALLOC_NODE(parser, yp_if_node_t);

    const uint8_t *end;
    if (end_keyword->type != YP_TOKEN_NOT_PROVIDED) {
        end = end_keyword->end;
    } else if (consequent != NULL) {
        end = consequent->location.end;
    } else if ((statements != NULL) && (statements->body.size != 0)) {
        end = statements->base.location.end;
    } else {
        end = predicate->location.end;
    }

    *node = (yp_if_node_t) {
        {
            .type = YP_IF_NODE,
            .flags = YP_NODE_FLAG_NEWLINE,
            .location = {
                .start = if_keyword->start,
                .end = end
            },
        },
        .if_keyword_loc = YP_LOCATION_TOKEN_VALUE(if_keyword),
        .predicate = predicate,
        .statements = statements,
        .consequent = consequent,
        .end_keyword_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(end_keyword)
    };

    return node;
}

// Allocate and initialize new IfNode node in the modifier form.
static yp_if_node_t *
yp_if_node_modifier_create(yp_parser_t *parser, yp_node_t *statement, const yp_token_t *if_keyword, yp_node_t *predicate) {
    yp_flip_flop(predicate);
    yp_if_node_t *node = YP_ALLOC_NODE(parser, yp_if_node_t);

    yp_statements_node_t *statements = yp_statements_node_create(parser);
    yp_statements_node_body_append(statements, statement);

    *node = (yp_if_node_t) {
        {
            .type = YP_IF_NODE,
            .flags = YP_NODE_FLAG_NEWLINE,
            .location = {
                .start = statement->location.start,
                .end = predicate->location.end
            },
        },
        .if_keyword_loc = YP_LOCATION_TOKEN_VALUE(if_keyword),
        .predicate = predicate,
        .statements = statements,
        .consequent = NULL,
        .end_keyword_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    return node;
}

// Allocate and initialize an if node from a ternary expression.
static yp_if_node_t *
yp_if_node_ternary_create(yp_parser_t *parser, yp_node_t *predicate, yp_node_t *true_expression, const yp_token_t *colon, yp_node_t *false_expression) {
    yp_flip_flop(predicate);

    yp_statements_node_t *if_statements = yp_statements_node_create(parser);
    yp_statements_node_body_append(if_statements, true_expression);

    yp_statements_node_t *else_statements = yp_statements_node_create(parser);
    yp_statements_node_body_append(else_statements, false_expression);

    yp_token_t end_keyword = not_provided(parser);
    yp_else_node_t *else_node = yp_else_node_create(parser, colon, else_statements, &end_keyword);

    yp_if_node_t *node = YP_ALLOC_NODE(parser, yp_if_node_t);

    *node = (yp_if_node_t) {
        {
            .type = YP_IF_NODE,
            .flags = YP_NODE_FLAG_NEWLINE,
            .location = {
                .start = predicate->location.start,
                .end = false_expression->location.end,
            },
        },
        .if_keyword_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .predicate = predicate,
        .statements = if_statements,
        .consequent = (yp_node_t *)else_node,
        .end_keyword_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    return node;

}

static inline void
yp_if_node_end_keyword_loc_set(yp_if_node_t *node, const yp_token_t *keyword) {
    node->base.location.end = keyword->end;
    node->end_keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword);
}

static inline void
yp_else_node_end_keyword_loc_set(yp_else_node_t *node, const yp_token_t *keyword) {
    node->base.location.end = keyword->end;
    node->end_keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword);
}

// Allocate and initialize a new IntegerNode node.
static yp_integer_node_t *
yp_integer_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_INTEGER);
    yp_integer_node_t *node = YP_ALLOC_NODE(parser, yp_integer_node_t);
    *node = (yp_integer_node_t) {{ .type = YP_INTEGER_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate and initialize a new IntegerNode node from an INTEGER_IMAGINARY token.
static yp_imaginary_node_t *
yp_integer_node_imaginary_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_INTEGER_IMAGINARY);

    yp_imaginary_node_t *node = YP_ALLOC_NODE(parser, yp_imaginary_node_t);
    *node = (yp_imaginary_node_t) {
        {
            .type = YP_IMAGINARY_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .numeric = (yp_node_t *) yp_integer_node_create(parser, &((yp_token_t) {
            .type = YP_TOKEN_INTEGER,
            .start = token->start,
            .end = token->end - 1
        }))
    };

    return node;
}

// Allocate and initialize a new IntegerNode node from an INTEGER_RATIONAL token.
static yp_rational_node_t *
yp_integer_node_rational_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_INTEGER_RATIONAL);

    yp_rational_node_t *node = YP_ALLOC_NODE(parser, yp_rational_node_t);
    *node = (yp_rational_node_t) {
        {
            .type = YP_RATIONAL_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .numeric = (yp_node_t *) yp_integer_node_create(parser, &((yp_token_t) {
            .type = YP_TOKEN_INTEGER,
            .start = token->start,
            .end = token->end - 1
        }))
    };

    return node;
}

// Allocate and initialize a new IntegerNode node from an INTEGER_RATIONAL_IMAGINARY token.
static yp_imaginary_node_t *
yp_integer_node_rational_imaginary_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_INTEGER_RATIONAL_IMAGINARY);

    yp_imaginary_node_t *node = YP_ALLOC_NODE(parser, yp_imaginary_node_t);
    *node = (yp_imaginary_node_t) {
        {
            .type = YP_IMAGINARY_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .numeric = (yp_node_t *) yp_integer_node_rational_create(parser, &((yp_token_t) {
            .type = YP_TOKEN_INTEGER_RATIONAL,
            .start = token->start,
            .end = token->end - 1
        }))
    };

    return node;
}

// Allocate and initialize a new InNode node.
static yp_in_node_t *
yp_in_node_create(yp_parser_t *parser, yp_node_t *pattern, yp_statements_node_t *statements, const yp_token_t *in_keyword, const yp_token_t *then_keyword) {
    yp_in_node_t *node = YP_ALLOC_NODE(parser, yp_in_node_t);

    const uint8_t *end;
    if (statements != NULL) {
        end = statements->base.location.end;
    } else if (then_keyword->type != YP_TOKEN_NOT_PROVIDED) {
        end = then_keyword->end;
    } else {
        end = pattern->location.end;
    }

    *node = (yp_in_node_t) {
        {
            .type = YP_IN_NODE,
            .location = {
                .start = in_keyword->start,
                .end = end
            },
        },
        .pattern = pattern,
        .statements = statements,
        .in_loc = YP_LOCATION_TOKEN_VALUE(in_keyword),
        .then_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(then_keyword)
    };

    return node;
}

// Allocate and initialize a new InstanceVariableAndWriteNode node.
static yp_instance_variable_and_write_node_t *
yp_instance_variable_and_write_node_create(yp_parser_t *parser, yp_instance_variable_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL);
    yp_instance_variable_and_write_node_t *node = YP_ALLOC_NODE(parser, yp_instance_variable_and_write_node_t);

    *node = (yp_instance_variable_and_write_node_t) {
        {
            .type = YP_INSTANCE_VARIABLE_AND_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new InstanceVariableOperatorWriteNode node.
static yp_instance_variable_operator_write_node_t *
yp_instance_variable_operator_write_node_create(yp_parser_t *parser, yp_instance_variable_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_instance_variable_operator_write_node_t *node = YP_ALLOC_NODE(parser, yp_instance_variable_operator_write_node_t);

    *node = (yp_instance_variable_operator_write_node_t) {
        {
            .type = YP_INSTANCE_VARIABLE_OPERATOR_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value,
        .operator = yp_parser_constant_id_location(parser, operator->start, operator->end - 1)
    };

    return node;
}

// Allocate and initialize a new InstanceVariableOrWriteNode node.
static yp_instance_variable_or_write_node_t *
yp_instance_variable_or_write_node_create(yp_parser_t *parser, yp_instance_variable_read_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    assert(operator->type == YP_TOKEN_PIPE_PIPE_EQUAL);
    yp_instance_variable_or_write_node_t *node = YP_ALLOC_NODE(parser, yp_instance_variable_or_write_node_t);

    *node = (yp_instance_variable_or_write_node_t) {
        {
            .type = YP_INSTANCE_VARIABLE_OR_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .name = target->name,
        .name_loc = target->base.location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new InstanceVariableReadNode node.
static yp_instance_variable_read_node_t *
yp_instance_variable_read_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_INSTANCE_VARIABLE);
    yp_instance_variable_read_node_t *node = YP_ALLOC_NODE(parser, yp_instance_variable_read_node_t);

    *node = (yp_instance_variable_read_node_t) {
        {
            .type = YP_INSTANCE_VARIABLE_READ_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .name = yp_parser_constant_id_token(parser, token)
    };

    return node;
}

// Initialize a new InstanceVariableWriteNode node from an InstanceVariableRead node.
static yp_instance_variable_write_node_t *
yp_instance_variable_write_node_create(yp_parser_t *parser, yp_instance_variable_read_node_t *read_node, yp_token_t *operator, yp_node_t *value) {
    yp_instance_variable_write_node_t *node = YP_ALLOC_NODE(parser, yp_instance_variable_write_node_t);
    *node = (yp_instance_variable_write_node_t) {
        {
            .type = YP_INSTANCE_VARIABLE_WRITE_NODE,
            .location = {
                .start = read_node->base.location.start,
                .end = value->location.end
            }
        },
        .name = read_node->name,
        .name_loc = YP_LOCATION_NODE_BASE_VALUE(read_node),
        .operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate a new InterpolatedRegularExpressionNode node.
static yp_interpolated_regular_expression_node_t *
yp_interpolated_regular_expression_node_create(yp_parser_t *parser, const yp_token_t *opening) {
    yp_interpolated_regular_expression_node_t *node = YP_ALLOC_NODE(parser, yp_interpolated_regular_expression_node_t);

    *node = (yp_interpolated_regular_expression_node_t) {
        {
            .type = YP_INTERPOLATED_REGULAR_EXPRESSION_NODE,
            .location = {
                .start = opening->start,
                .end = NULL,
            },
        },
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .parts = YP_EMPTY_NODE_LIST
    };

    return node;
}

static inline void
yp_interpolated_regular_expression_node_append(yp_interpolated_regular_expression_node_t *node, yp_node_t *part) {
    if (node->base.location.start > part->location.start) {
        node->base.location.start = part->location.start;
    }
    if (node->base.location.end < part->location.end) {
        node->base.location.end = part->location.end;
    }
    yp_node_list_append(&node->parts, part);
}

static inline void
yp_interpolated_regular_expression_node_closing_set(yp_interpolated_regular_expression_node_t *node, const yp_token_t *closing) {
    node->closing_loc = YP_LOCATION_TOKEN_VALUE(closing);
    node->base.location.end = closing->end;
    node->base.flags |= yp_regular_expression_flags_create(closing);
}

// Allocate and initialize a new InterpolatedStringNode node.
static yp_interpolated_string_node_t *
yp_interpolated_string_node_create(yp_parser_t *parser, const yp_token_t *opening, const yp_node_list_t *parts, const yp_token_t *closing) {
    yp_interpolated_string_node_t *node = YP_ALLOC_NODE(parser, yp_interpolated_string_node_t);

    *node = (yp_interpolated_string_node_t) {
        {
            .type = YP_INTERPOLATED_STRING_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end,
            },
        },
        .opening_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing),
        .parts = parts == NULL ? YP_EMPTY_NODE_LIST : *parts
    };

    return node;
}

// Append a part to an InterpolatedStringNode node.
static inline void
yp_interpolated_string_node_append(yp_interpolated_string_node_t *node, yp_node_t *part) {
    if (node->parts.size == 0 && node->opening_loc.start == NULL) {
        node->base.location.start = part->location.start;
    }

    yp_node_list_append(&node->parts, part);
    node->base.location.end = part->location.end;
}

// Set the closing token of the given InterpolatedStringNode node.
static void
yp_interpolated_string_node_closing_set(yp_interpolated_string_node_t *node, const yp_token_t *closing) {
    node->closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing);
    node->base.location.end = closing->end;
}

// Allocate and initialize a new InterpolatedSymbolNode node.
static yp_interpolated_symbol_node_t *
yp_interpolated_symbol_node_create(yp_parser_t *parser, const yp_token_t *opening, const yp_node_list_t *parts, const yp_token_t *closing) {
    yp_interpolated_symbol_node_t *node = YP_ALLOC_NODE(parser, yp_interpolated_symbol_node_t);

    *node = (yp_interpolated_symbol_node_t) {
        {
            .type = YP_INTERPOLATED_SYMBOL_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end,
            },
        },
        .opening_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing),
        .parts = parts == NULL ? YP_EMPTY_NODE_LIST : *parts
    };

    return node;
}

static inline void
yp_interpolated_symbol_node_append(yp_interpolated_symbol_node_t *node, yp_node_t *part) {
    if (node->parts.size == 0 && node->opening_loc.start == NULL) {
        node->base.location.start = part->location.start;
    }

    yp_node_list_append(&node->parts, part);
    node->base.location.end = part->location.end;
}

// Allocate a new InterpolatedXStringNode node.
static yp_interpolated_x_string_node_t *
yp_interpolated_xstring_node_create(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *closing) {
    yp_interpolated_x_string_node_t *node = YP_ALLOC_NODE(parser, yp_interpolated_x_string_node_t);

    *node = (yp_interpolated_x_string_node_t) {
        {
            .type = YP_INTERPOLATED_X_STRING_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end
            },
        },
        .opening_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing),
        .parts = YP_EMPTY_NODE_LIST
    };

    return node;
}

static inline void
yp_interpolated_xstring_node_append(yp_interpolated_x_string_node_t *node, yp_node_t *part) {
    yp_node_list_append(&node->parts, part);
    node->base.location.end = part->location.end;
}

static inline void
yp_interpolated_xstring_node_closing_set(yp_interpolated_x_string_node_t *node, const yp_token_t *closing) {
    node->closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing);
    node->base.location.end = closing->end;
}

// Allocate a new KeywordHashNode node.
static yp_keyword_hash_node_t *
yp_keyword_hash_node_create(yp_parser_t *parser) {
    yp_keyword_hash_node_t *node = YP_ALLOC_NODE(parser, yp_keyword_hash_node_t);

    *node = (yp_keyword_hash_node_t) {
        .base = {
            .type = YP_KEYWORD_HASH_NODE,
            .location = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
        },
        .elements = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Append an element to a KeywordHashNode node.
static void
yp_keyword_hash_node_elements_append(yp_keyword_hash_node_t *hash, yp_node_t *element) {
    yp_node_list_append(&hash->elements, element);
    if (hash->base.location.start == NULL) {
        hash->base.location.start = element->location.start;
    }
    hash->base.location.end = element->location.end;
}

// Allocate a new KeywordParameterNode node.
static yp_keyword_parameter_node_t *
yp_keyword_parameter_node_create(yp_parser_t *parser, const yp_token_t *name, yp_node_t *value) {
    yp_keyword_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_keyword_parameter_node_t);

    *node = (yp_keyword_parameter_node_t) {
        {
            .type = YP_KEYWORD_PARAMETER_NODE,
            .location = {
                .start = name->start,
                .end = value == NULL ? name->end : value->location.end
            },
        },
        .name = yp_parser_constant_id_location(parser, name->start, name->end - 1),
        .name_loc = YP_LOCATION_TOKEN_VALUE(name),
        .value = value
    };

    return node;
}

// Allocate a new KeywordRestParameterNode node.
static yp_keyword_rest_parameter_node_t *
yp_keyword_rest_parameter_node_create(yp_parser_t *parser, const yp_token_t *operator, const yp_token_t *name) {
    yp_keyword_rest_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_keyword_rest_parameter_node_t);

    *node = (yp_keyword_rest_parameter_node_t) {
        {
            .type = YP_KEYWORD_REST_PARAMETER_NODE,
            .location = {
                .start = operator->start,
                .end = (name->type == YP_TOKEN_NOT_PROVIDED ? operator->end : name->end)
            },
        },
        .name = yp_parser_optional_constant_id_token(parser, name),
        .name_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(name),
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate a new LambdaNode node.
static yp_lambda_node_t *
yp_lambda_node_create(
    yp_parser_t *parser,
    yp_constant_id_list_t *locals,
    const yp_token_t *operator,
    const yp_token_t *opening,
    const yp_token_t *closing,
    yp_block_parameters_node_t *parameters,
    yp_node_t *body
) {
    yp_lambda_node_t *node = YP_ALLOC_NODE(parser, yp_lambda_node_t);

    *node = (yp_lambda_node_t) {
        {
            .type = YP_LAMBDA_NODE,
            .location = {
                .start = operator->start,
                .end = closing->end
            },
        },
        .locals = *locals,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing),
        .parameters = parameters,
        .body = body
    };

    return node;
}

// Allocate and initialize a new LocalVariableAndWriteNode node.
static yp_local_variable_and_write_node_t *
yp_local_variable_and_write_node_create(yp_parser_t *parser, yp_node_t *target, const yp_token_t *operator, yp_node_t *value, yp_constant_id_t name, uint32_t depth) {
    assert(YP_NODE_TYPE_P(target, YP_LOCAL_VARIABLE_READ_NODE) || YP_NODE_TYPE_P(target, YP_CALL_NODE));
    assert(operator->type == YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL);
    yp_local_variable_and_write_node_t *node = YP_ALLOC_NODE(parser, yp_local_variable_and_write_node_t);

    *node = (yp_local_variable_and_write_node_t) {
        {
            .type = YP_LOCAL_VARIABLE_AND_WRITE_NODE,
            .location = {
                .start = target->location.start,
                .end = value->location.end
            }
        },
        .name_loc = target->location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value,
        .name = name,
        .depth = depth
    };

    return node;
}

// Allocate and initialize a new LocalVariableOperatorWriteNode node.
static yp_local_variable_operator_write_node_t *
yp_local_variable_operator_write_node_create(yp_parser_t *parser, yp_node_t *target, const yp_token_t *operator, yp_node_t *value, yp_constant_id_t name, uint32_t depth) {
    yp_local_variable_operator_write_node_t *node = YP_ALLOC_NODE(parser, yp_local_variable_operator_write_node_t);

    *node = (yp_local_variable_operator_write_node_t) {
        {
            .type = YP_LOCAL_VARIABLE_OPERATOR_WRITE_NODE,
            .location = {
                .start = target->location.start,
                .end = value->location.end
            }
        },
        .name_loc = target->location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value,
        .name = name,
        .operator = yp_parser_constant_id_location(parser, operator->start, operator->end - 1),
        .depth = depth
    };

    return node;
}

// Allocate and initialize a new LocalVariableOrWriteNode node.
static yp_local_variable_or_write_node_t *
yp_local_variable_or_write_node_create(yp_parser_t *parser, yp_node_t *target, const yp_token_t *operator, yp_node_t *value, yp_constant_id_t name, uint32_t depth) {
    assert(YP_NODE_TYPE_P(target, YP_LOCAL_VARIABLE_READ_NODE) || YP_NODE_TYPE_P(target, YP_CALL_NODE));
    assert(operator->type == YP_TOKEN_PIPE_PIPE_EQUAL);
    yp_local_variable_or_write_node_t *node = YP_ALLOC_NODE(parser, yp_local_variable_or_write_node_t);

    *node = (yp_local_variable_or_write_node_t) {
        {
            .type = YP_LOCAL_VARIABLE_OR_WRITE_NODE,
            .location = {
                .start = target->location.start,
                .end = value->location.end
            }
        },
        .name_loc = target->location,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value,
        .name = name,
        .depth = depth
    };

    return node;
}

// Allocate a new LocalVariableReadNode node.
static yp_local_variable_read_node_t *
yp_local_variable_read_node_create(yp_parser_t *parser, const yp_token_t *name, uint32_t depth) {
    yp_local_variable_read_node_t *node = YP_ALLOC_NODE(parser, yp_local_variable_read_node_t);

    *node = (yp_local_variable_read_node_t) {
        {
            .type = YP_LOCAL_VARIABLE_READ_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(name)
        },
        .name = yp_parser_constant_id_token(parser, name),
        .depth = depth
    };

    return node;
}

// Allocate and initialize a new LocalVariableWriteNode node.
static yp_local_variable_write_node_t *
yp_local_variable_write_node_create(yp_parser_t *parser, yp_constant_id_t name, uint32_t depth, yp_node_t *value, const yp_location_t *name_loc, const yp_token_t *operator) {
    yp_local_variable_write_node_t *node = YP_ALLOC_NODE(parser, yp_local_variable_write_node_t);

    *node = (yp_local_variable_write_node_t) {
        {
            .type = YP_LOCAL_VARIABLE_WRITE_NODE,
            .location = {
                .start = name_loc->start,
                .end = value->location.end
            }
        },
        .name = name,
        .depth = depth,
        .value = value,
        .name_loc = *name_loc,
        .operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new LocalVariableTargetNode node.
static yp_local_variable_target_node_t *
yp_local_variable_target_node_create(yp_parser_t *parser, const yp_token_t *name) {
    yp_local_variable_target_node_t *node = YP_ALLOC_NODE(parser, yp_local_variable_target_node_t);

    *node = (yp_local_variable_target_node_t) {
        {
            .type = YP_LOCAL_VARIABLE_TARGET_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(name)
        },
        .name = yp_parser_constant_id_token(parser, name),
        .depth = 0
    };

    return node;
}

// Allocate and initialize a new MatchPredicateNode node.
static yp_match_predicate_node_t *
yp_match_predicate_node_create(yp_parser_t *parser, yp_node_t *value, yp_node_t *pattern, const yp_token_t *operator) {
    yp_match_predicate_node_t *node = YP_ALLOC_NODE(parser, yp_match_predicate_node_t);

    *node = (yp_match_predicate_node_t) {
        {
            .type = YP_MATCH_PREDICATE_NODE,
            .location = {
                .start = value->location.start,
                .end = pattern->location.end
            }
        },
        .value = value,
        .pattern = pattern,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new MatchRequiredNode node.
static yp_match_required_node_t *
yp_match_required_node_create(yp_parser_t *parser, yp_node_t *value, yp_node_t *pattern, const yp_token_t *operator) {
    yp_match_required_node_t *node = YP_ALLOC_NODE(parser, yp_match_required_node_t);

    *node = (yp_match_required_node_t) {
        {
            .type = YP_MATCH_REQUIRED_NODE,
            .location = {
                .start = value->location.start,
                .end = pattern->location.end
            }
        },
        .value = value,
        .pattern = pattern,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate a new ModuleNode node.
static yp_module_node_t *
yp_module_node_create(yp_parser_t *parser, yp_constant_id_list_t *locals, const yp_token_t *module_keyword, yp_node_t *constant_path, const yp_token_t *name, yp_node_t *body, const yp_token_t *end_keyword) {
    yp_module_node_t *node = YP_ALLOC_NODE(parser, yp_module_node_t);

    *node = (yp_module_node_t) {
        {
            .type = YP_MODULE_NODE,
            .location = {
                .start = module_keyword->start,
                .end = end_keyword->end
            }
        },
        .locals = (locals == NULL ? ((yp_constant_id_list_t) { .ids = NULL, .size = 0, .capacity = 0 }) : *locals),
        .module_keyword_loc = YP_LOCATION_TOKEN_VALUE(module_keyword),
        .constant_path = constant_path,
        .body = body,
        .end_keyword_loc = YP_LOCATION_TOKEN_VALUE(end_keyword),
        .name = yp_parser_constant_id_token(parser, name)
    };

    return node;
}

// Allocate and initialize new MultiTargetNode node.
static yp_multi_target_node_t *
yp_multi_target_node_create(yp_parser_t *parser) {
    yp_multi_target_node_t *node = YP_ALLOC_NODE(parser, yp_multi_target_node_t);

    *node = (yp_multi_target_node_t) {
        {
            .type = YP_MULTI_TARGET_NODE,
            .location = { .start = NULL, .end = NULL }
        },
        .targets = YP_EMPTY_NODE_LIST,
        .lparen_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .rparen_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    return node;
}

// Append a target to a MultiTargetNode node.
static void
yp_multi_target_node_targets_append(yp_multi_target_node_t *node, yp_node_t *target) {
    yp_node_list_append(&node->targets, target);

    if (node->base.location.start == NULL || (node->base.location.start > target->location.start)) {
        node->base.location.start = target->location.start;
    }

    if (node->base.location.end == NULL || (node->base.location.end < target->location.end)) {
        node->base.location.end = target->location.end;
    }
}

// Allocate a new MultiWriteNode node.
static yp_multi_write_node_t *
yp_multi_write_node_create(yp_parser_t *parser, yp_multi_target_node_t *target, const yp_token_t *operator, yp_node_t *value) {
    yp_multi_write_node_t *node = YP_ALLOC_NODE(parser, yp_multi_write_node_t);

    *node = (yp_multi_write_node_t) {
        {
            .type = YP_MULTI_WRITE_NODE,
            .location = {
                .start = target->base.location.start,
                .end = value->location.end
            }
        },
        .targets = target->targets,
        .lparen_loc = target->lparen_loc,
        .rparen_loc = target->rparen_loc,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    // Explicitly do not call yp_node_destroy here because we want to keep
    // around all of the information within the MultiWriteNode node.
    free(target);

    return node;
}

// Allocate and initialize a new NextNode node.
static yp_next_node_t *
yp_next_node_create(yp_parser_t *parser, const yp_token_t *keyword, yp_arguments_node_t *arguments) {
    assert(keyword->type == YP_TOKEN_KEYWORD_NEXT);
    yp_next_node_t *node = YP_ALLOC_NODE(parser, yp_next_node_t);

    *node = (yp_next_node_t) {
        {
            .type = YP_NEXT_NODE,
            .location = {
                .start = keyword->start,
                .end = (arguments == NULL ? keyword->end : arguments->base.location.end)
            }
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .arguments = arguments
    };

    return node;
}

// Allocate and initialize a new NilNode node.
static yp_nil_node_t *
yp_nil_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD_NIL);
    yp_nil_node_t *node = YP_ALLOC_NODE(parser, yp_nil_node_t);

    *node = (yp_nil_node_t) {{ .type = YP_NIL_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate and initialize a new NoKeywordsParameterNode node.
static yp_no_keywords_parameter_node_t *
yp_no_keywords_parameter_node_create(yp_parser_t *parser, const yp_token_t *operator, const yp_token_t *keyword) {
    assert(operator->type == YP_TOKEN_USTAR_STAR || operator->type == YP_TOKEN_STAR_STAR);
    assert(keyword->type == YP_TOKEN_KEYWORD_NIL);
    yp_no_keywords_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_no_keywords_parameter_node_t);

    *node = (yp_no_keywords_parameter_node_t) {
        {
            .type = YP_NO_KEYWORDS_PARAMETER_NODE,
            .location = {
                .start = operator->start,
                .end = keyword->end
            }
        },
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword)
    };

    return node;
}

// Allocate a new NthReferenceReadNode node.
static yp_numbered_reference_read_node_t *
yp_numbered_reference_read_node_create(yp_parser_t *parser, const yp_token_t *name) {
    assert(name->type == YP_TOKEN_NUMBERED_REFERENCE);
    yp_numbered_reference_read_node_t *node = YP_ALLOC_NODE(parser, yp_numbered_reference_read_node_t);

    *node = (yp_numbered_reference_read_node_t) {
        {
            .type = YP_NUMBERED_REFERENCE_READ_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(name),
        },
        .number = parse_decimal_number(parser, name->start + 1, name->end)
    };

    return node;
}

// Allocate a new OptionalParameterNode node.
static yp_optional_parameter_node_t *
yp_optional_parameter_node_create(yp_parser_t *parser, const yp_token_t *name, const yp_token_t *operator, yp_node_t *value) {
    yp_optional_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_optional_parameter_node_t);

    *node = (yp_optional_parameter_node_t) {
        {
            .type = YP_OPTIONAL_PARAMETER_NODE,
            .location = {
                .start = name->start,
                .end = value->location.end
            }
        },
        .name = yp_parser_constant_id_token(parser, name),
        .name_loc = YP_LOCATION_TOKEN_VALUE(name),
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .value = value
    };

    return node;
}

// Allocate and initialize a new OrNode node.
static yp_or_node_t *
yp_or_node_create(yp_parser_t *parser, yp_node_t *left, const yp_token_t *operator, yp_node_t *right) {
    yp_or_node_t *node = YP_ALLOC_NODE(parser, yp_or_node_t);

    *node = (yp_or_node_t) {
        {
            .type = YP_OR_NODE,
            .location = {
                .start = left->location.start,
                .end = right->location.end
            }
        },
        .left = left,
        .right = right,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new ParametersNode node.
static yp_parameters_node_t *
yp_parameters_node_create(yp_parser_t *parser) {
    yp_parameters_node_t *node = YP_ALLOC_NODE(parser, yp_parameters_node_t);

    *node = (yp_parameters_node_t) {
        {
            .type = YP_PARAMETERS_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(&parser->current)
        },
        .rest = NULL,
        .keyword_rest = NULL,
        .block = NULL,
        .requireds = YP_EMPTY_NODE_LIST,
        .optionals = YP_EMPTY_NODE_LIST,
        .posts = YP_EMPTY_NODE_LIST,
        .keywords = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Set the location properly for the parameters node.
static void
yp_parameters_node_location_set(yp_parameters_node_t *params, yp_node_t *param) {
    if (params->base.location.start == NULL) {
        params->base.location.start = param->location.start;
    } else {
        params->base.location.start = params->base.location.start < param->location.start ? params->base.location.start : param->location.start;
    }

    if (params->base.location.end == NULL) {
        params->base.location.end = param->location.end;
    } else {
        params->base.location.end = params->base.location.end > param->location.end ? params->base.location.end : param->location.end;
    }
}

// Append a required parameter to a ParametersNode node.
static void
yp_parameters_node_requireds_append(yp_parameters_node_t *params, yp_node_t *param) {
    yp_parameters_node_location_set(params, param);
    yp_node_list_append(&params->requireds, param);
}

// Append an optional parameter to a ParametersNode node.
static void
yp_parameters_node_optionals_append(yp_parameters_node_t *params, yp_optional_parameter_node_t *param) {
    yp_parameters_node_location_set(params, (yp_node_t *) param);
    yp_node_list_append(&params->optionals, (yp_node_t *) param);
}

// Append a post optional arguments parameter to a ParametersNode node.
static void
yp_parameters_node_posts_append(yp_parameters_node_t *params, yp_node_t *param) {
    yp_parameters_node_location_set(params, param);
    yp_node_list_append(&params->posts, param);
}

// Set the rest parameter on a ParametersNode node.
static void
yp_parameters_node_rest_set(yp_parameters_node_t *params, yp_rest_parameter_node_t *param) {
    assert(params->rest == NULL);
    yp_parameters_node_location_set(params, (yp_node_t *) param);
    params->rest = param;
}

// Append a keyword parameter to a ParametersNode node.
static void
yp_parameters_node_keywords_append(yp_parameters_node_t *params, yp_node_t *param) {
    yp_parameters_node_location_set(params, param);
    yp_node_list_append(&params->keywords, param);
}

// Set the keyword rest parameter on a ParametersNode node.
static void
yp_parameters_node_keyword_rest_set(yp_parameters_node_t *params, yp_node_t *param) {
    assert(params->keyword_rest == NULL);
    yp_parameters_node_location_set(params, param);
    params->keyword_rest = param;
}

// Set the block parameter on a ParametersNode node.
static void
yp_parameters_node_block_set(yp_parameters_node_t *params, yp_block_parameter_node_t *param) {
    assert(params->block == NULL);
    yp_parameters_node_location_set(params, (yp_node_t *) param);
    params->block = param;
}

// Allocate a new ProgramNode node.
static yp_program_node_t *
yp_program_node_create(yp_parser_t *parser, yp_constant_id_list_t *locals, yp_statements_node_t *statements) {
    yp_program_node_t *node = YP_ALLOC_NODE(parser, yp_program_node_t);

    *node = (yp_program_node_t) {
        {
            .type = YP_PROGRAM_NODE,
            .location = {
                .start = statements == NULL ? parser->start : statements->base.location.start,
                .end = statements == NULL ? parser->end : statements->base.location.end
            }
        },
        .locals = *locals,
        .statements = statements
    };

    return node;
}

// Allocate and initialize new ParenthesesNode node.
static yp_parentheses_node_t *
yp_parentheses_node_create(yp_parser_t *parser, const yp_token_t *opening, yp_node_t *body, const yp_token_t *closing) {
    yp_parentheses_node_t *node = YP_ALLOC_NODE(parser, yp_parentheses_node_t);

    *node = (yp_parentheses_node_t) {
        {
            .type = YP_PARENTHESES_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end
            }
        },
        .body = body,
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing)
    };

    return node;
}

// Allocate and initialize a new PinnedExpressionNode node.
static yp_pinned_expression_node_t *
yp_pinned_expression_node_create(yp_parser_t *parser, yp_node_t *expression, const yp_token_t *operator, const yp_token_t *lparen, const yp_token_t *rparen) {
    yp_pinned_expression_node_t *node = YP_ALLOC_NODE(parser, yp_pinned_expression_node_t);

    *node = (yp_pinned_expression_node_t) {
        {
            .type = YP_PINNED_EXPRESSION_NODE,
            .location = {
                .start = operator->start,
                .end = rparen->end
            }
        },
        .expression = expression,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .lparen_loc = YP_LOCATION_TOKEN_VALUE(lparen),
        .rparen_loc = YP_LOCATION_TOKEN_VALUE(rparen)
    };

    return node;
}

// Allocate and initialize a new PinnedVariableNode node.
static yp_pinned_variable_node_t *
yp_pinned_variable_node_create(yp_parser_t *parser, const yp_token_t *operator, yp_node_t *variable) {
    yp_pinned_variable_node_t *node = YP_ALLOC_NODE(parser, yp_pinned_variable_node_t);

    *node = (yp_pinned_variable_node_t) {
        {
            .type = YP_PINNED_VARIABLE_NODE,
            .location = {
                .start = operator->start,
                .end = variable->location.end
            }
        },
        .variable = variable,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new PostExecutionNode node.
static yp_post_execution_node_t *
yp_post_execution_node_create(yp_parser_t *parser, const yp_token_t *keyword, const yp_token_t *opening, yp_statements_node_t *statements, const yp_token_t *closing) {
    yp_post_execution_node_t *node = YP_ALLOC_NODE(parser, yp_post_execution_node_t);

    *node = (yp_post_execution_node_t) {
        {
            .type = YP_POST_EXECUTION_NODE,
            .location = {
                .start = keyword->start,
                .end = closing->end
            }
        },
        .statements = statements,
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing)
    };

    return node;
}

// Allocate and initialize a new PreExecutionNode node.
static yp_pre_execution_node_t *
yp_pre_execution_node_create(yp_parser_t *parser, const yp_token_t *keyword, const yp_token_t *opening, yp_statements_node_t *statements, const yp_token_t *closing) {
    yp_pre_execution_node_t *node = YP_ALLOC_NODE(parser, yp_pre_execution_node_t);

    *node = (yp_pre_execution_node_t) {
        {
            .type = YP_PRE_EXECUTION_NODE,
            .location = {
                .start = keyword->start,
                .end = closing->end
            }
        },
        .statements = statements,
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing)
    };

    return node;
}

// Allocate and initialize new RangeNode node.
static yp_range_node_t *
yp_range_node_create(yp_parser_t *parser, yp_node_t *left, const yp_token_t *operator, yp_node_t *right) {
    yp_range_node_t *node = YP_ALLOC_NODE(parser, yp_range_node_t);

    *node = (yp_range_node_t) {
        {
            .type = YP_RANGE_NODE,
            .location = {
                .start = (left == NULL ? operator->start : left->location.start),
                .end = (right == NULL ? operator->end : right->location.end)
            }
        },
        .left = left,
        .right = right,
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    switch (operator->type) {
        case YP_TOKEN_DOT_DOT_DOT:
        case YP_TOKEN_UDOT_DOT_DOT:
            node->base.flags |= YP_RANGE_FLAGS_EXCLUDE_END;
            break;
        default:
            break;
    }

    return node;
}

// Allocate and initialize a new RedoNode node.
static yp_redo_node_t *
yp_redo_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD_REDO);
    yp_redo_node_t *node = YP_ALLOC_NODE(parser, yp_redo_node_t);

    *node = (yp_redo_node_t) {{ .type = YP_REDO_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate a new RegularExpressionNode node.
static yp_regular_expression_node_t *
yp_regular_expression_node_create(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *content, const yp_token_t *closing) {
    yp_regular_expression_node_t *node = YP_ALLOC_NODE(parser, yp_regular_expression_node_t);

    *node = (yp_regular_expression_node_t) {
        {
            .type = YP_REGULAR_EXPRESSION_NODE,
            .flags = yp_regular_expression_flags_create(closing),
            .location = {
                .start = MIN(opening->start, closing->start),
                .end = MAX(opening->end, closing->end)
            }
        },
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .content_loc = YP_LOCATION_TOKEN_VALUE(content),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing),
        .unescaped = YP_EMPTY_STRING
    };

    return node;
}

// Allocate a new RequiredDestructuredParameterNode node.
static yp_required_destructured_parameter_node_t *
yp_required_destructured_parameter_node_create(yp_parser_t *parser, const yp_token_t *opening) {
    yp_required_destructured_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_required_destructured_parameter_node_t);

    *node = (yp_required_destructured_parameter_node_t) {
        {
            .type = YP_REQUIRED_DESTRUCTURED_PARAMETER_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(opening)
        },
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .parameters = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Append a new parameter to the given RequiredDestructuredParameterNode node.
static void
yp_required_destructured_parameter_node_append_parameter(yp_required_destructured_parameter_node_t *node, yp_node_t *parameter) {
    yp_node_list_append(&node->parameters, parameter);
}

// Set the closing token of the given RequiredDestructuredParameterNode node.
static void
yp_required_destructured_parameter_node_closing_set(yp_required_destructured_parameter_node_t *node, const yp_token_t *closing) {
    node->closing_loc = YP_LOCATION_TOKEN_VALUE(closing);
    node->base.location.end = closing->end;
}

// Allocate a new RequiredParameterNode node.
static yp_required_parameter_node_t *
yp_required_parameter_node_create(yp_parser_t *parser, const yp_token_t *token) {
    yp_required_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_required_parameter_node_t);

    *node = (yp_required_parameter_node_t) {
        {
            .type = YP_REQUIRED_PARAMETER_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token)
        },
        .name = yp_parser_constant_id_token(parser, token)
    };

    return node;
}

// Allocate a new RescueModifierNode node.
static yp_rescue_modifier_node_t *
yp_rescue_modifier_node_create(yp_parser_t *parser, yp_node_t *expression, const yp_token_t *keyword, yp_node_t *rescue_expression) {
    yp_rescue_modifier_node_t *node = YP_ALLOC_NODE(parser, yp_rescue_modifier_node_t);

    *node = (yp_rescue_modifier_node_t) {
        {
            .type = YP_RESCUE_MODIFIER_NODE,
            .location = {
                .start = expression->location.start,
                .end = rescue_expression->location.end
            }
        },
        .expression = expression,
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .rescue_expression = rescue_expression
    };

    return node;
}

// Allocate and initiliaze a new RescueNode node.
static yp_rescue_node_t *
yp_rescue_node_create(yp_parser_t *parser, const yp_token_t *keyword) {
    yp_rescue_node_t *node = YP_ALLOC_NODE(parser, yp_rescue_node_t);

    *node = (yp_rescue_node_t) {
        {
            .type = YP_RESCUE_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(keyword)
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .operator_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .reference = NULL,
        .statements = NULL,
        .consequent = NULL,
        .exceptions = YP_EMPTY_NODE_LIST
    };

    return node;
}

static inline void
yp_rescue_node_operator_set(yp_rescue_node_t *node, const yp_token_t *operator) {
    node->operator_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(operator);
}

// Set the reference of a rescue node, and update the location of the node.
static void
yp_rescue_node_reference_set(yp_rescue_node_t *node, yp_node_t *reference) {
    node->reference = reference;
    node->base.location.end = reference->location.end;
}

// Set the statements of a rescue node, and update the location of the node.
static void
yp_rescue_node_statements_set(yp_rescue_node_t *node, yp_statements_node_t *statements) {
    node->statements = statements;
    if ((statements != NULL) && (statements->body.size > 0)) {
        node->base.location.end = statements->base.location.end;
    }
}

// Set the consequent of a rescue node, and update the location.
static void
yp_rescue_node_consequent_set(yp_rescue_node_t *node, yp_rescue_node_t *consequent) {
    node->consequent = consequent;
    node->base.location.end = consequent->base.location.end;
}

// Append an exception node to a rescue node, and update the location.
static void
yp_rescue_node_exceptions_append(yp_rescue_node_t *node, yp_node_t *exception) {
    yp_node_list_append(&node->exceptions, exception);
    node->base.location.end = exception->location.end;
}

// Allocate a new RestParameterNode node.
static yp_rest_parameter_node_t *
yp_rest_parameter_node_create(yp_parser_t *parser, const yp_token_t *operator, const yp_token_t *name) {
    yp_rest_parameter_node_t *node = YP_ALLOC_NODE(parser, yp_rest_parameter_node_t);

    *node = (yp_rest_parameter_node_t) {
        {
            .type = YP_REST_PARAMETER_NODE,
            .location = {
                .start = operator->start,
                .end = (name->type == YP_TOKEN_NOT_PROVIDED ? operator->end : name->end)
            }
        },
        .name = yp_parser_optional_constant_id_token(parser, name),
        .name_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(name),
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator)
    };

    return node;
}

// Allocate and initialize a new RetryNode node.
static yp_retry_node_t *
yp_retry_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD_RETRY);
    yp_retry_node_t *node = YP_ALLOC_NODE(parser, yp_retry_node_t);

    *node = (yp_retry_node_t) {{ .type = YP_RETRY_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate a new ReturnNode node.
static yp_return_node_t *
yp_return_node_create(yp_parser_t *parser, const yp_token_t *keyword, yp_arguments_node_t *arguments) {
    yp_return_node_t *node = YP_ALLOC_NODE(parser, yp_return_node_t);

    *node = (yp_return_node_t) {
        {
            .type = YP_RETURN_NODE,
            .location = {
                .start = keyword->start,
                .end = (arguments == NULL ? keyword->end : arguments->base.location.end)
            }
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .arguments = arguments
    };

    return node;
}

// Allocate and initialize a new SelfNode node.
static yp_self_node_t *
yp_self_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD_SELF);
    yp_self_node_t *node = YP_ALLOC_NODE(parser, yp_self_node_t);

    *node = (yp_self_node_t) {{ .type = YP_SELF_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate a new SingletonClassNode node.
static yp_singleton_class_node_t *
yp_singleton_class_node_create(yp_parser_t *parser, yp_constant_id_list_t *locals, const yp_token_t *class_keyword, const yp_token_t *operator, yp_node_t *expression, yp_node_t *body, const yp_token_t *end_keyword) {
    yp_singleton_class_node_t *node = YP_ALLOC_NODE(parser, yp_singleton_class_node_t);

    *node = (yp_singleton_class_node_t) {
        {
            .type = YP_SINGLETON_CLASS_NODE,
            .location = {
                .start = class_keyword->start,
                .end = end_keyword->end
            }
        },
        .locals = *locals,
        .class_keyword_loc = YP_LOCATION_TOKEN_VALUE(class_keyword),
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .expression = expression,
        .body = body,
        .end_keyword_loc = YP_LOCATION_TOKEN_VALUE(end_keyword)
    };

    return node;
}

// Allocate and initialize a new SourceEncodingNode node.
static yp_source_encoding_node_t *
yp_source_encoding_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD___ENCODING__);
    yp_source_encoding_node_t *node = YP_ALLOC_NODE(parser, yp_source_encoding_node_t);

    *node = (yp_source_encoding_node_t) {{ .type = YP_SOURCE_ENCODING_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate and initialize a new SourceFileNode node.
static yp_source_file_node_t*
yp_source_file_node_create(yp_parser_t *parser, const yp_token_t *file_keyword) {
    yp_source_file_node_t *node = YP_ALLOC_NODE(parser, yp_source_file_node_t);
    assert(file_keyword->type == YP_TOKEN_KEYWORD___FILE__);

    *node = (yp_source_file_node_t) {
        {
            .type = YP_SOURCE_FILE_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(file_keyword),
        },
        .filepath = parser->filepath_string,
    };

    return node;
}

// Allocate and initialize a new SourceLineNode node.
static yp_source_line_node_t *
yp_source_line_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD___LINE__);
    yp_source_line_node_t *node = YP_ALLOC_NODE(parser, yp_source_line_node_t);

    *node = (yp_source_line_node_t) {{ .type = YP_SOURCE_LINE_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate a new SplatNode node.
static yp_splat_node_t *
yp_splat_node_create(yp_parser_t *parser, const yp_token_t *operator, yp_node_t *expression) {
    yp_splat_node_t *node = YP_ALLOC_NODE(parser, yp_splat_node_t);

    *node = (yp_splat_node_t) {
        {
            .type = YP_SPLAT_NODE,
            .location = {
                .start = operator->start,
                .end = (expression == NULL ? operator->end : expression->location.end)
            }
        },
        .operator_loc = YP_LOCATION_TOKEN_VALUE(operator),
        .expression = expression
    };

    return node;
}

// Allocate and initialize a new StatementsNode node.
static yp_statements_node_t *
yp_statements_node_create(yp_parser_t *parser) {
    yp_statements_node_t *node = YP_ALLOC_NODE(parser, yp_statements_node_t);

    *node = (yp_statements_node_t) {
        {
            .type = YP_STATEMENTS_NODE,
            .location = YP_LOCATION_NULL_VALUE(parser)
        },
        .body = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Get the length of the given StatementsNode node's body.
static size_t
yp_statements_node_body_length(yp_statements_node_t *node) {
    return node && node->body.size;
}

// Set the location of the given StatementsNode.
static void
yp_statements_node_location_set(yp_statements_node_t *node, const uint8_t *start, const uint8_t *end) {
    node->base.location = (yp_location_t) { .start = start, .end = end };
}

// Append a new node to the given StatementsNode node's body.
static void
yp_statements_node_body_append(yp_statements_node_t *node, yp_node_t *statement) {
    if (yp_statements_node_body_length(node) == 0 || statement->location.start < node->base.location.start) {
        node->base.location.start = statement->location.start;
    }
    if (statement->location.end > node->base.location.end) {
        node->base.location.end = statement->location.end;
    }

    yp_node_list_append(&node->body, statement);

    // Every statement gets marked as a place where a newline can occur.
    statement->flags |= YP_NODE_FLAG_NEWLINE;
}

// Allocate a new StringConcatNode node.
static yp_string_concat_node_t *
yp_string_concat_node_create(yp_parser_t *parser, yp_node_t *left, yp_node_t *right) {
    yp_string_concat_node_t *node = YP_ALLOC_NODE(parser, yp_string_concat_node_t);

    *node = (yp_string_concat_node_t) {
        {
            .type = YP_STRING_CONCAT_NODE,
            .location = {
                .start = left->location.start,
                .end = right->location.end
            }
        },
        .left = left,
        .right = right
    };

    return node;
}

// Allocate a new StringNode node.
static yp_string_node_t *
yp_string_node_create(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *content, const yp_token_t *closing) {
    yp_string_node_t *node = YP_ALLOC_NODE(parser, yp_string_node_t);

    *node = (yp_string_node_t) {
        {
            .type = YP_STRING_NODE,
            .location = {
                .start = (opening->type == YP_TOKEN_NOT_PROVIDED ? content->start : opening->start),
                .end = (closing->type == YP_TOKEN_NOT_PROVIDED ? content->end : closing->end)
            }
        },
        .opening_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .content_loc = YP_LOCATION_TOKEN_VALUE(content),
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing),
        .unescaped = YP_EMPTY_STRING
    };

    return node;
}

// Allocate and initialize a new SuperNode node.
static yp_super_node_t *
yp_super_node_create(yp_parser_t *parser, const yp_token_t *keyword, yp_arguments_t *arguments) {
    assert(keyword->type == YP_TOKEN_KEYWORD_SUPER);
    yp_super_node_t *node = YP_ALLOC_NODE(parser, yp_super_node_t);

    const uint8_t *end;
    if (arguments->block != NULL) {
        end = arguments->block->base.location.end;
    } else if (arguments->closing_loc.start != NULL) {
        end = arguments->closing_loc.end;
    } else if (arguments->arguments != NULL) {
        end = arguments->arguments->base.location.end;
    } else {
        assert(false && "unreachable");
        end = NULL;
    }

    *node = (yp_super_node_t) {
        {
            .type = YP_SUPER_NODE,
            .location = {
                .start = keyword->start,
                .end = end,
            }
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .lparen_loc = arguments->opening_loc,
        .arguments = arguments->arguments,
        .rparen_loc = arguments->closing_loc,
        .block = arguments->block
    };

    return node;
}

// Allocate a new SymbolNode node.
static yp_symbol_node_t *
yp_symbol_node_create(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *value, const yp_token_t *closing) {
    yp_symbol_node_t *node = YP_ALLOC_NODE(parser, yp_symbol_node_t);

    *node = (yp_symbol_node_t) {
        {
            .type = YP_SYMBOL_NODE,
            .location = {
                .start = (opening->type == YP_TOKEN_NOT_PROVIDED ? value->start : opening->start),
                .end = (closing->type == YP_TOKEN_NOT_PROVIDED ? value->end : closing->end)
            }
        },
        .opening_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .value_loc = YP_LOCATION_TOKEN_VALUE(value),
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing),
        .unescaped = YP_EMPTY_STRING
    };

    return node;
}

// Allocate and initialize a new SymbolNode node from a label.
static yp_symbol_node_t *
yp_symbol_node_label_create(yp_parser_t *parser, const yp_token_t *token) {
    yp_symbol_node_t *node;

    switch (token->type) {
        case YP_TOKEN_LABEL: {
            yp_token_t opening = not_provided(parser);
            yp_token_t closing = { .type = YP_TOKEN_LABEL_END, .start = token->end - 1, .end = token->end };

            yp_token_t label = { .type = YP_TOKEN_LABEL, .start = token->start, .end = token->end - 1 };
            node = yp_symbol_node_create(parser, &opening, &label, &closing);

            assert((label.end - label.start) >= 0);
            yp_string_shared_init(&node->unescaped, label.start, label.end);

            yp_unescape_manipulate_string(parser, &node->unescaped, YP_UNESCAPE_ALL);
            break;
        }
        case YP_TOKEN_MISSING: {
            yp_token_t opening = not_provided(parser);
            yp_token_t closing = not_provided(parser);

            yp_token_t label = { .type = YP_TOKEN_LABEL, .start = token->start, .end = token->end };
            node = yp_symbol_node_create(parser, &opening, &label, &closing);
            break;
        }
        default:
            assert(false && "unreachable");
            node = NULL;
            break;
    }

    return node;
}

// Check if the given node is a label in a hash.
static bool
yp_symbol_node_label_p(yp_node_t *node) {
    const uint8_t *end = NULL;

    switch (YP_NODE_TYPE(node)) {
        case YP_SYMBOL_NODE:
            end = ((yp_symbol_node_t *) node)->closing_loc.end;
            break;
        case YP_INTERPOLATED_SYMBOL_NODE:
            end = ((yp_interpolated_symbol_node_t *) node)->closing_loc.end;
            break;
        default:
            return false;
    }

    return (end != NULL) && (end[-1] == ':');
}

// Convert the given StringNode node to a SymbolNode node.
static yp_symbol_node_t *
yp_string_node_to_symbol_node(yp_parser_t *parser, yp_string_node_t *node, const yp_token_t *opening, const yp_token_t *closing) {
    yp_symbol_node_t *new_node = YP_ALLOC_NODE(parser, yp_symbol_node_t);

    *new_node = (yp_symbol_node_t) {
        {
            .type = YP_SYMBOL_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end
            }
        },
        .opening_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(opening),
        .value_loc = node->content_loc,
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing),
        .unescaped = node->unescaped
    };

    // We are explicitly _not_ using yp_node_destroy here because we don't want
    // to trash the unescaped string. We could instead copy the string if we
    // know that it is owned, but we're taking the fast path for now.
    free(node);

    return new_node;
}

// Convert the given SymbolNode node to a StringNode node.
static yp_string_node_t *
yp_symbol_node_to_string_node(yp_parser_t *parser, yp_symbol_node_t *node) {
    yp_string_node_t *new_node = YP_ALLOC_NODE(parser, yp_string_node_t);

    *new_node = (yp_string_node_t) {
        {
            .type = YP_STRING_NODE,
            .location = node->base.location
        },
        .opening_loc = node->opening_loc,
        .content_loc = node->value_loc,
        .closing_loc = node->closing_loc,
        .unescaped = node->unescaped
    };

    // We are explicitly _not_ using yp_node_destroy here because we don't want
    // to trash the unescaped string. We could instead copy the string if we
    // know that it is owned, but we're taking the fast path for now.
    free(node);

    return new_node;
}

// Allocate and initialize a new TrueNode node.
static yp_true_node_t *
yp_true_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD_TRUE);
    yp_true_node_t *node = YP_ALLOC_NODE(parser, yp_true_node_t);

    *node = (yp_true_node_t) {{ .type = YP_TRUE_NODE, .location = YP_LOCATION_TOKEN_VALUE(token) }};
    return node;
}

// Allocate and initialize a new UndefNode node.
static yp_undef_node_t *
yp_undef_node_create(yp_parser_t *parser, const yp_token_t *token) {
    assert(token->type == YP_TOKEN_KEYWORD_UNDEF);
    yp_undef_node_t *node = YP_ALLOC_NODE(parser, yp_undef_node_t);

    *node = (yp_undef_node_t) {
        {
            .type = YP_UNDEF_NODE,
            .location = YP_LOCATION_TOKEN_VALUE(token),
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(token),
        .names = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Append a name to an undef node.
static void
yp_undef_node_append(yp_undef_node_t *node, yp_node_t *name) {
    node->base.location.end = name->location.end;
    yp_node_list_append(&node->names, name);
}

// Allocate a new UnlessNode node.
static yp_unless_node_t *
yp_unless_node_create(yp_parser_t *parser, const yp_token_t *keyword, yp_node_t *predicate, yp_statements_node_t *statements) {
    yp_flip_flop(predicate);
    yp_unless_node_t *node = YP_ALLOC_NODE(parser, yp_unless_node_t);

    const uint8_t *end;
    if (statements != NULL) {
        end = statements->base.location.end;
    } else {
        end = predicate->location.end;
    }

    *node = (yp_unless_node_t) {
        {
            .type = YP_UNLESS_NODE,
            .flags = YP_NODE_FLAG_NEWLINE,
            .location = {
                .start = keyword->start,
                .end = end
            },
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .predicate = predicate,
        .statements = statements,
        .consequent = NULL,
        .end_keyword_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    return node;
}

// Allocate and initialize new UnlessNode node in the modifier form.
static yp_unless_node_t *
yp_unless_node_modifier_create(yp_parser_t *parser, yp_node_t *statement, const yp_token_t *unless_keyword, yp_node_t *predicate) {
    yp_flip_flop(predicate);
    yp_unless_node_t *node = YP_ALLOC_NODE(parser, yp_unless_node_t);

    yp_statements_node_t *statements = yp_statements_node_create(parser);
    yp_statements_node_body_append(statements, statement);

    *node = (yp_unless_node_t) {
        {
            .type = YP_UNLESS_NODE,
            .flags = YP_NODE_FLAG_NEWLINE,
            .location = {
                .start = statement->location.start,
                .end = predicate->location.end
            },
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(unless_keyword),
        .predicate = predicate,
        .statements = statements,
        .consequent = NULL,
        .end_keyword_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE
    };

    return node;
}

static inline void
yp_unless_node_end_keyword_loc_set(yp_unless_node_t *node, const yp_token_t *end_keyword) {
    node->end_keyword_loc = YP_LOCATION_TOKEN_VALUE(end_keyword);
    node->base.location.end = end_keyword->end;
}

// Allocate a new UntilNode node.
static yp_until_node_t *
yp_until_node_create(yp_parser_t *parser, const yp_token_t *keyword, const yp_token_t *closing, yp_node_t *predicate, yp_statements_node_t *statements, yp_node_flags_t flags) {
    yp_until_node_t *node = YP_ALLOC_NODE(parser, yp_until_node_t);

    *node = (yp_until_node_t) {
        {
            .type = YP_UNTIL_NODE,
            .flags = flags,
            .location = {
                .start = keyword->start,
                .end = closing->end,
            },
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing),
        .predicate = predicate,
        .statements = statements
    };

    return node;
}

// Allocate a new UntilNode node.
static yp_until_node_t *
yp_until_node_modifier_create(yp_parser_t *parser, const yp_token_t *keyword, yp_node_t *predicate, yp_statements_node_t *statements, yp_node_flags_t flags) {
    yp_until_node_t *node = YP_ALLOC_NODE(parser, yp_until_node_t);

    *node = (yp_until_node_t) {
        {
            .type = YP_UNTIL_NODE,
            .flags = flags,
            .location = {
                .start = statements->base.location.start,
                .end = predicate->location.end,
            },
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .predicate = predicate,
        .statements = statements
    };

    return node;
}

// Allocate and initialize a new WhenNode node.
static yp_when_node_t *
yp_when_node_create(yp_parser_t *parser, const yp_token_t *keyword) {
    yp_when_node_t *node = YP_ALLOC_NODE(parser, yp_when_node_t);

    *node = (yp_when_node_t) {
        {
            .type = YP_WHEN_NODE,
            .location = {
                .start = keyword->start,
                .end = NULL
            }
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .statements = NULL,
        .conditions = YP_EMPTY_NODE_LIST
    };

    return node;
}

// Append a new condition to a when node.
static void
yp_when_node_conditions_append(yp_when_node_t *node, yp_node_t *condition) {
    node->base.location.end = condition->location.end;
    yp_node_list_append(&node->conditions, condition);
}

// Set the statements list of a when node.
static void
yp_when_node_statements_set(yp_when_node_t *node, yp_statements_node_t *statements) {
    if (statements->base.location.end > node->base.location.end) {
        node->base.location.end = statements->base.location.end;
    }

    node->statements = statements;
}

// Allocate a new WhileNode node.
static yp_while_node_t *
yp_while_node_create(yp_parser_t *parser, const yp_token_t *keyword, const yp_token_t *closing, yp_node_t *predicate, yp_statements_node_t *statements, yp_node_flags_t flags) {
    yp_while_node_t *node = YP_ALLOC_NODE(parser, yp_while_node_t);

    *node = (yp_while_node_t) {
        {
            .type = YP_WHILE_NODE,
            .flags = flags,
            .location = {
                .start = keyword->start,
                .end = closing->end
            },
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .closing_loc = YP_OPTIONAL_LOCATION_TOKEN_VALUE(closing),
        .predicate = predicate,
        .statements = statements
    };

    return node;
}

// Allocate a new WhileNode node.
static yp_while_node_t *
yp_while_node_modifier_create(yp_parser_t *parser, const yp_token_t *keyword, yp_node_t *predicate, yp_statements_node_t *statements, yp_node_flags_t flags) {
    yp_while_node_t *node = YP_ALLOC_NODE(parser, yp_while_node_t);

    *node = (yp_while_node_t) {
        {
            .type = YP_WHILE_NODE,
            .flags = flags,
            .location = {
                .start = statements->base.location.start,
                .end = predicate->location.end
            },
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .closing_loc = YP_OPTIONAL_LOCATION_NOT_PROVIDED_VALUE,
        .predicate = predicate,
        .statements = statements
    };

    return node;
}

// Allocate and initialize a new XStringNode node.
static yp_x_string_node_t *
yp_xstring_node_create(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *content, const yp_token_t *closing) {
    yp_x_string_node_t *node = YP_ALLOC_NODE(parser, yp_x_string_node_t);

    *node = (yp_x_string_node_t) {
        {
            .type = YP_X_STRING_NODE,
            .location = {
                .start = opening->start,
                .end = closing->end
            },
        },
        .opening_loc = YP_LOCATION_TOKEN_VALUE(opening),
        .content_loc = YP_LOCATION_TOKEN_VALUE(content),
        .closing_loc = YP_LOCATION_TOKEN_VALUE(closing),
        .unescaped = YP_EMPTY_STRING
    };

    return node;
}

// Allocate a new YieldNode node.
static yp_yield_node_t *
yp_yield_node_create(yp_parser_t *parser, const yp_token_t *keyword, const yp_location_t *lparen_loc, yp_arguments_node_t *arguments, const yp_location_t *rparen_loc) {
    yp_yield_node_t *node = YP_ALLOC_NODE(parser, yp_yield_node_t);

    const uint8_t *end;
    if (rparen_loc->start != NULL) {
        end = rparen_loc->end;
    } else if (arguments != NULL) {
        end = arguments->base.location.end;
    } else if (lparen_loc->start != NULL) {
        end = lparen_loc->end;
    } else {
        end = keyword->end;
    }

    *node = (yp_yield_node_t) {
        {
            .type = YP_YIELD_NODE,
            .location = {
                .start = keyword->start,
                .end = end
            },
        },
        .keyword_loc = YP_LOCATION_TOKEN_VALUE(keyword),
        .lparen_loc = *lparen_loc,
        .arguments = arguments,
        .rparen_loc = *rparen_loc
    };

    return node;
}


#undef YP_EMPTY_STRING
#undef YP_ALLOC_NODE

/******************************************************************************/
/* Scope-related functions                                                    */
/******************************************************************************/

// Allocate and initialize a new scope. Push it onto the scope stack.
static bool
yp_parser_scope_push(yp_parser_t *parser, bool closed) {
    yp_scope_t *scope = (yp_scope_t *) malloc(sizeof(yp_scope_t));
    if (scope == NULL) return false;

    *scope = (yp_scope_t) { .closed = closed, .previous = parser->current_scope };
    yp_constant_id_list_init(&scope->locals);

    parser->current_scope = scope;
    return true;
}

// Check if the current scope has a given local variables.
static int
yp_parser_local_depth(yp_parser_t *parser, yp_token_t *token) {
    yp_constant_id_t constant_id = yp_parser_constant_id_token(parser, token);
    yp_scope_t *scope = parser->current_scope;
    int depth = 0;

    while (scope != NULL) {
        if (yp_constant_id_list_includes(&scope->locals, constant_id)) return depth;
        if (scope->closed) break;

        scope = scope->previous;
        depth++;
    }

    return -1;
}

// Add a constant id to the local table of the current scope.
static inline void
yp_parser_local_add(yp_parser_t *parser, yp_constant_id_t constant_id) {
    if (!yp_constant_id_list_includes(&parser->current_scope->locals, constant_id)) {
        yp_constant_id_list_append(&parser->current_scope->locals, constant_id);
    }
}

// Add a local variable from a location to the current scope.
static yp_constant_id_t
yp_parser_local_add_location(yp_parser_t *parser, const uint8_t *start, const uint8_t *end) {
    yp_constant_id_t constant_id = yp_parser_constant_id_location(parser, start, end);
    if (constant_id != 0) yp_parser_local_add(parser, constant_id);
    return constant_id;
}

// Add a local variable from a token to the current scope.
static inline void
yp_parser_local_add_token(yp_parser_t *parser, yp_token_t *token) {
    yp_parser_local_add_location(parser, token->start, token->end);
}

// Add a local variable from an owned string to the current scope.
static inline void
yp_parser_local_add_owned(yp_parser_t *parser, const uint8_t *start, size_t length) {
    yp_constant_id_t constant_id = yp_parser_constant_id_owned(parser, start, length);
    if (constant_id != 0) yp_parser_local_add(parser, constant_id);
}

// Add a parameter name to the current scope and check whether the name of the
// parameter is unique or not.
static void
yp_parser_parameter_name_check(yp_parser_t *parser, yp_token_t *name) {
    // We want to ignore any parameter name that starts with an underscore.
    if ((*name->start == '_')) return;

    // Otherwise we'll fetch the constant id for the parameter name and check
    // whether it's already in the current scope.
    yp_constant_id_t constant_id = yp_parser_constant_id_token(parser, name);

    if (yp_constant_id_list_includes(&parser->current_scope->locals, constant_id)) {
        yp_diagnostic_list_append(&parser->error_list, name->start, name->end, YP_ERR_PARAMETER_NAME_REPEAT);
    }
}

// Pop the current scope off the scope stack. Note that we specifically do not
// free the associated constant list because we assume that we have already
// transferred ownership of the list to the AST somewhere.
static void
yp_parser_scope_pop(yp_parser_t *parser) {
    yp_scope_t *scope = parser->current_scope;
    parser->current_scope = scope->previous;
    free(scope);
}

/******************************************************************************/
/* Basic character checks                                                     */
/******************************************************************************/

// This function is used extremely frequently to lex all of the identifiers in a
// source file, so it's important that it be as fast as possible. For this
// reason we have the encoding_changed boolean to check if we need to go through
// the function pointer or can just directly use the UTF-8 functions.
static inline size_t
char_is_identifier_start(yp_parser_t *parser, const uint8_t *b) {
    if (parser->encoding_changed) {
        return parser->encoding.alpha_char(b, parser->end - b) || (*b == '_') || (*b >= 0x80);
    } else if (*b < 0x80) {
        return (yp_encoding_unicode_table[*b] & YP_ENCODING_ALPHABETIC_BIT ? 1 : 0) || (*b == '_');
    } else {
        return (size_t) (yp_encoding_utf_8_alpha_char(b, parser->end - b) || 1u);
    }
}

// Like the above, this function is also used extremely frequently to lex all of
// the identifiers in a source file once the first character has been found. So
// it's important that it be as fast as possible.
static inline size_t
char_is_identifier(yp_parser_t *parser, const uint8_t *b) {
    if (parser->encoding_changed) {
        return parser->encoding.alnum_char(b, parser->end - b) || (*b == '_') || (*b >= 0x80);
    } else if (*b < 0x80) {
        return (yp_encoding_unicode_table[*b] & YP_ENCODING_ALPHANUMERIC_BIT ? 1 : 0) || (*b == '_');
    } else {
        return (size_t) (yp_encoding_utf_8_alnum_char(b, parser->end - b) || 1u);
    }
}

// Here we're defining a perfect hash for the characters that are allowed in
// global names. This is used to quickly check the next character after a $ to
// see if it's a valid character for a global name.
#define BIT(c, idx) (((c) / 32 - 1 == idx) ? (1U << ((c) % 32)) : 0)
#define PUNCT(idx) ( \
                BIT('~', idx) | BIT('*', idx) | BIT('$', idx) | BIT('?', idx) | \
                BIT('!', idx) | BIT('@', idx) | BIT('/', idx) | BIT('\\', idx) | \
                BIT(';', idx) | BIT(',', idx) | BIT('.', idx) | BIT('=', idx) | \
                BIT(':', idx) | BIT('<', idx) | BIT('>', idx) | BIT('\"', idx) | \
                BIT('&', idx) | BIT('`', idx) | BIT('\'', idx) | BIT('+', idx) | \
                BIT('0', idx))

const unsigned int yp_global_name_punctuation_hash[(0x7e - 0x20 + 31) / 32] = { PUNCT(0), PUNCT(1), PUNCT(2) };

#undef BIT
#undef PUNCT

static inline bool
char_is_global_name_punctuation(const uint8_t b) {
    const unsigned int i = (const unsigned int) b;
    if (i <= 0x20 || 0x7e < i) return false;

    return (yp_global_name_punctuation_hash[(i - 0x20) / 32] >> (i % 32)) & 1;
}

static inline bool
token_is_numbered_parameter(const uint8_t *start, const uint8_t *end) {
    return (end - start == 2) && (start[0] == '_') && (start[1] != '0') && (yp_char_is_decimal_digit(start[1]));
}

static inline bool
token_is_setter_name(yp_token_t *token) {
    return (
        (token->type == YP_TOKEN_IDENTIFIER) &&
        (token->end - token->start >= 2) &&
        (token->end[-1] == '=')
    );
}

/******************************************************************************/
/* Stack helpers                                                              */
/******************************************************************************/

static inline void
yp_accepts_block_stack_push(yp_parser_t *parser, bool value) {
    // Use the negation of the value to prevent stack overflow.
    yp_state_stack_push(&parser->accepts_block_stack, !value);
}

static inline void
yp_accepts_block_stack_pop(yp_parser_t *parser) {
    yp_state_stack_pop(&parser->accepts_block_stack);
}

static inline bool
yp_accepts_block_stack_p(yp_parser_t *parser) {
    return !yp_state_stack_p(&parser->accepts_block_stack);
}

static inline void
yp_do_loop_stack_push(yp_parser_t *parser, bool value) {
    yp_state_stack_push(&parser->do_loop_stack, value);
}

static inline void
yp_do_loop_stack_pop(yp_parser_t *parser) {
    yp_state_stack_pop(&parser->do_loop_stack);
}

static inline bool
yp_do_loop_stack_p(yp_parser_t *parser) {
    return yp_state_stack_p(&parser->do_loop_stack);
}

/******************************************************************************/
/* Lexer check helpers                                                        */
/******************************************************************************/

// Get the next character in the source starting from +cursor+. If that position
// is beyond the end of the source then return '\0'.
static inline uint8_t
peek_at(yp_parser_t *parser, const uint8_t *cursor) {
    if (cursor < parser->end) {
        return *cursor;
    } else {
        return '\0';
    }
}

// Get the next character in the source starting from parser->current.end and
// adding the given offset. If that position is beyond the end of the source
// then return '\0'.
static inline uint8_t
peek_offset(yp_parser_t *parser, ptrdiff_t offset) {
    return peek_at(parser, parser->current.end + offset);
}

// Get the next character in the source starting from parser->current.end. If
// that position is beyond the end of the source then return '\0'.
static inline uint8_t
peek(yp_parser_t *parser) {
    return peek_at(parser, parser->current.end);
}

// Get the next string of length len in the source starting from parser->current.end.
// If the string extends beyond the end of the source, return the empty string ""
static inline const uint8_t *
peek_string(yp_parser_t *parser, size_t len) {
    if (parser->current.end + len <= parser->end) {
        return parser->current.end;
    } else {
        return (const uint8_t *) "";
    }
}

// If the character to be read matches the given value, then returns true and
// advanced the current pointer.
static inline bool
match(yp_parser_t *parser, uint8_t value) {
    if (peek(parser) == value) {
        parser->current.end++;
        return true;
    }
    return false;
}

// Return the length of the line ending string starting at +cursor+, or 0 if it
// is not a line ending. This function is intended to be CRLF/LF agnostic.
static inline size_t
match_eol_at(yp_parser_t *parser, const uint8_t *cursor) {
    if (peek_at(parser, cursor) == '\n') {
        return 1;
    }
    if (peek_at(parser, cursor) == '\r' && peek_at(parser, cursor + 1) == '\n') {
        return 2;
    }
    return 0;
}

// Return the length of the line ending string starting at
// parser->current.end + offset, or 0 if it is not a line ending. This function
// is intended to be CRLF/LF agnostic.
static inline size_t
match_eol_offset(yp_parser_t *parser, ptrdiff_t offset) {
    return match_eol_at(parser, parser->current.end + offset);
}

// Return the length of the line ending string starting at parser->current.end,
// or 0 if it is not a line ending. This function is intended to be CRLF/LF
// agnostic.
static inline size_t
match_eol(yp_parser_t *parser) {
    return match_eol_at(parser, parser->current.end);
}

// Skip to the next newline character or NUL byte.
static inline const uint8_t *
next_newline(const uint8_t *cursor, ptrdiff_t length) {
    assert(length >= 0);

    // Note that it's okay for us to use memchr here to look for \n because none
    // of the encodings that we support have \n as a component of a multi-byte
    // character.
    return memchr(cursor, '\n', (size_t) length);
}

// Find the start of the encoding comment. This is effectively an inlined
// version of strnstr with some modifications.
static inline const uint8_t *
parser_lex_encoding_comment_start(yp_parser_t *parser, const uint8_t *cursor, ptrdiff_t remaining) {
    assert(remaining >= 0);
    size_t length = (size_t) remaining;

    size_t key_length = strlen("coding:");
    if (key_length > length) return NULL;

    const uint8_t *cursor_limit = cursor + length - key_length + 1;
    while ((cursor = yp_memchr(cursor, 'c', (size_t) (cursor_limit - cursor), parser->encoding_changed, &parser->encoding)) != NULL) {
        if (memcmp(cursor, "coding", key_length - 1) == 0) {
            size_t whitespace_after_coding = yp_strspn_inline_whitespace(cursor + key_length - 1, parser->end - (cursor + key_length - 1));
            size_t cur_pos = key_length + whitespace_after_coding;

            if (cursor[cur_pos - 1] == ':' || cursor[cur_pos - 1] == '=') {
                return cursor + cur_pos;
            }
        }

        cursor++;
    }

    return NULL;
}

// Here we're going to check if this is a "magic" comment, and perform whatever
// actions are necessary for it here.
static void
parser_lex_encoding_comment(yp_parser_t *parser) {
    const uint8_t *start = parser->current.start + 1;
    const uint8_t *end = next_newline(start, parser->end - start);
    if (end == NULL) end = parser->end;

    // These are the patterns we're going to match to find the encoding comment.
    // This is definitely not complete or even really correct.
    const uint8_t *encoding_start = parser_lex_encoding_comment_start(parser, start, end - start);

    // If we didn't find anything that matched our patterns, then return. Note
    // that this does a _very_ poor job of actually finding the encoding, and
    // there is a lot of work to do here to better reflect actual magic comment
    // parsing from CRuby, but this at least gets us part of the way there.
    if (encoding_start == NULL) return;

    // Skip any non-newline whitespace after the "coding:" or "coding=".
    encoding_start += yp_strspn_inline_whitespace(encoding_start, end - encoding_start);

    // Now determine the end of the encoding string. This is either the end of
    // the line, the first whitespace character, or a punctuation mark.
    const uint8_t *encoding_end = yp_strpbrk(parser, encoding_start, (const uint8_t *) " \t\f\r\v\n;,", end - encoding_start);
    encoding_end = encoding_end == NULL ? end : encoding_end;

    // Finally, we can determine the width of the encoding string.
    size_t width = (size_t) (encoding_end - encoding_start);

    // First, we're going to call out to a user-defined callback if one was
    // provided. If they return an encoding struct that we can use, then we'll
    // use that here.
    if (parser->encoding_decode_callback != NULL) {
        yp_encoding_t *encoding = parser->encoding_decode_callback(parser, encoding_start, width);

        if (encoding != NULL) {
            parser->encoding = *encoding;
            return;
        }
    }

    // Next, we're going to check for UTF-8. This is the most common encoding.
    // Extensions like utf-8 can contain extra encoding details like,
    // utf-8-dos, utf-8-linux, utf-8-mac. We treat these all as utf-8 should
    // treat any encoding starting utf-8 as utf-8.
    if ((encoding_start + 5 <= parser->end) && (yp_strncasecmp(encoding_start, (const uint8_t *) "utf-8", 5) == 0)) {
        // We don't need to do anything here because the default encoding is
        // already UTF-8. We'll just return.
        return;
    }

    // Next, we're going to loop through each of the encodings that we handle
    // explicitly. If we found one that we understand, we'll use that value.
#define ENCODING(value, prebuilt) \
    if (width == sizeof(value) - 1 && encoding_start + width <= parser->end && yp_strncasecmp(encoding_start, (const uint8_t *) value, width) == 0) { \
        parser->encoding = prebuilt; \
        parser->encoding_changed |= true; \
        if (parser->encoding_changed_callback != NULL) parser->encoding_changed_callback(parser); \
        return; \
    }

    // Check most common first. (This is pretty arbitrary.)
    ENCODING("ascii", yp_encoding_ascii);
    ENCODING("ascii-8bit", yp_encoding_ascii_8bit);
    ENCODING("us-ascii", yp_encoding_ascii);
    ENCODING("binary", yp_encoding_ascii_8bit);
    ENCODING("shift_jis", yp_encoding_shift_jis);
    ENCODING("euc-jp", yp_encoding_euc_jp);

    // Then check all the others.
    ENCODING("big5", yp_encoding_big5);
    ENCODING("gbk", yp_encoding_gbk);
    ENCODING("iso-8859-1", yp_encoding_iso_8859_1);
    ENCODING("iso-8859-2", yp_encoding_iso_8859_2);
    ENCODING("iso-8859-3", yp_encoding_iso_8859_3);
    ENCODING("iso-8859-4", yp_encoding_iso_8859_4);
    ENCODING("iso-8859-5", yp_encoding_iso_8859_5);
    ENCODING("iso-8859-6", yp_encoding_iso_8859_6);
    ENCODING("iso-8859-7", yp_encoding_iso_8859_7);
    ENCODING("iso-8859-8", yp_encoding_iso_8859_8);
    ENCODING("iso-8859-9", yp_encoding_iso_8859_9);
    ENCODING("iso-8859-10", yp_encoding_iso_8859_10);
    ENCODING("iso-8859-11", yp_encoding_iso_8859_11);
    ENCODING("iso-8859-13", yp_encoding_iso_8859_13);
    ENCODING("iso-8859-14", yp_encoding_iso_8859_14);
    ENCODING("iso-8859-15", yp_encoding_iso_8859_15);
    ENCODING("iso-8859-16", yp_encoding_iso_8859_16);
    ENCODING("koi8-r", yp_encoding_koi8_r);
    ENCODING("windows-31j", yp_encoding_windows_31j);
    ENCODING("windows-1251", yp_encoding_windows_1251);
    ENCODING("windows-1252", yp_encoding_windows_1252);
    ENCODING("cp1251", yp_encoding_windows_1251);
    ENCODING("cp1252", yp_encoding_windows_1252);
    ENCODING("cp932", yp_encoding_windows_31j);
    ENCODING("sjis", yp_encoding_windows_31j);
    ENCODING("utf8-mac", yp_encoding_utf8_mac);

#undef ENCODING

    // If nothing was returned by this point, then we've got an issue because we
    // didn't understand the encoding that the user was trying to use. In this
    // case we'll keep using the default encoding but add an error to the
    // parser to indicate an unsuccessful parse.
    yp_diagnostic_list_append(&parser->error_list, encoding_start, encoding_end, YP_ERR_INVALID_ENCODING_MAGIC_COMMENT);
}

/******************************************************************************/
/* Context manipulations                                                      */
/******************************************************************************/

static bool
context_terminator(yp_context_t context, yp_token_t *token) {
    switch (context) {
        case YP_CONTEXT_MAIN:
        case YP_CONTEXT_DEF_PARAMS:
            return token->type == YP_TOKEN_EOF;
        case YP_CONTEXT_DEFAULT_PARAMS:
            return token->type == YP_TOKEN_COMMA || token->type == YP_TOKEN_PARENTHESIS_RIGHT;
        case YP_CONTEXT_PREEXE:
        case YP_CONTEXT_POSTEXE:
            return token->type == YP_TOKEN_BRACE_RIGHT;
        case YP_CONTEXT_MODULE:
        case YP_CONTEXT_CLASS:
        case YP_CONTEXT_SCLASS:
        case YP_CONTEXT_LAMBDA_DO_END:
        case YP_CONTEXT_DEF:
        case YP_CONTEXT_BLOCK_KEYWORDS:
            return token->type == YP_TOKEN_KEYWORD_END || token->type == YP_TOKEN_KEYWORD_RESCUE || token->type == YP_TOKEN_KEYWORD_ENSURE;
        case YP_CONTEXT_WHILE:
        case YP_CONTEXT_UNTIL:
        case YP_CONTEXT_ELSE:
        case YP_CONTEXT_FOR:
        case YP_CONTEXT_ENSURE:
            return token->type == YP_TOKEN_KEYWORD_END;
        case YP_CONTEXT_CASE_WHEN:
            return token->type == YP_TOKEN_KEYWORD_WHEN || token->type == YP_TOKEN_KEYWORD_END || token->type == YP_TOKEN_KEYWORD_ELSE;
        case YP_CONTEXT_CASE_IN:
            return token->type == YP_TOKEN_KEYWORD_IN || token->type == YP_TOKEN_KEYWORD_END || token->type == YP_TOKEN_KEYWORD_ELSE;
        case YP_CONTEXT_IF:
        case YP_CONTEXT_ELSIF:
            return token->type == YP_TOKEN_KEYWORD_ELSE || token->type == YP_TOKEN_KEYWORD_ELSIF || token->type == YP_TOKEN_KEYWORD_END;
        case YP_CONTEXT_UNLESS:
            return token->type == YP_TOKEN_KEYWORD_ELSE || token->type == YP_TOKEN_KEYWORD_END;
        case YP_CONTEXT_EMBEXPR:
            return token->type == YP_TOKEN_EMBEXPR_END;
        case YP_CONTEXT_BLOCK_BRACES:
            return token->type == YP_TOKEN_BRACE_RIGHT;
        case YP_CONTEXT_PARENS:
            return token->type == YP_TOKEN_PARENTHESIS_RIGHT;
        case YP_CONTEXT_BEGIN:
        case YP_CONTEXT_RESCUE:
            return token->type == YP_TOKEN_KEYWORD_ENSURE || token->type == YP_TOKEN_KEYWORD_RESCUE || token->type == YP_TOKEN_KEYWORD_ELSE || token->type == YP_TOKEN_KEYWORD_END;
        case YP_CONTEXT_RESCUE_ELSE:
            return token->type == YP_TOKEN_KEYWORD_ENSURE || token->type == YP_TOKEN_KEYWORD_END;
        case YP_CONTEXT_LAMBDA_BRACES:
            return token->type == YP_TOKEN_BRACE_RIGHT;
        case YP_CONTEXT_PREDICATE:
            return token->type == YP_TOKEN_KEYWORD_THEN || token->type == YP_TOKEN_NEWLINE || token->type == YP_TOKEN_SEMICOLON;
    }

    return false;
}

static bool
context_recoverable(yp_parser_t *parser, yp_token_t *token) {
    yp_context_node_t *context_node = parser->current_context;

    while (context_node != NULL) {
        if (context_terminator(context_node->context, token)) return true;
        context_node = context_node->prev;
    }

    return false;
}

static bool
context_push(yp_parser_t *parser, yp_context_t context) {
    yp_context_node_t *context_node = (yp_context_node_t *) malloc(sizeof(yp_context_node_t));
    if (context_node == NULL) return false;

    *context_node = (yp_context_node_t) { .context = context, .prev = NULL };

    if (parser->current_context == NULL) {
        parser->current_context = context_node;
    } else {
        context_node->prev = parser->current_context;
        parser->current_context = context_node;
    }

    return true;
}

static void
context_pop(yp_parser_t *parser) {
    yp_context_node_t *prev = parser->current_context->prev;
    free(parser->current_context);
    parser->current_context = prev;
}

static bool
context_p(yp_parser_t *parser, yp_context_t context) {
    yp_context_node_t *context_node = parser->current_context;

    while (context_node != NULL) {
        if (context_node->context == context) return true;
        context_node = context_node->prev;
    }

    return false;
}

static bool
context_def_p(yp_parser_t *parser) {
    yp_context_node_t *context_node = parser->current_context;

    while (context_node != NULL) {
        switch (context_node->context) {
            case YP_CONTEXT_DEF:
                return true;
            case YP_CONTEXT_CLASS:
            case YP_CONTEXT_MODULE:
            case YP_CONTEXT_SCLASS:
                return false;
            default:
                context_node = context_node->prev;
        }
    }

    return false;
}

/******************************************************************************/
/* Specific token lexers                                                      */
/******************************************************************************/

static yp_token_type_t
lex_optional_float_suffix(yp_parser_t *parser) {
    yp_token_type_t type = YP_TOKEN_INTEGER;

    // Here we're going to attempt to parse the optional decimal portion of a
    // float. If it's not there, then it's okay and we'll just continue on.
    if (peek(parser) == '.') {
        if (yp_char_is_decimal_digit(peek_offset(parser, 1))) {
            parser->current.end += 2;
            parser->current.end += yp_strspn_decimal_number(parser->current.end, parser->end - parser->current.end);
            type = YP_TOKEN_FLOAT;
        } else {
            // If we had a . and then something else, then it's not a float suffix on
            // a number it's a method call or something else.
            return type;
        }
    }

    // Here we're going to attempt to parse the optional exponent portion of a
    // float. If it's not there, it's okay and we'll just continue on.
    if (match(parser, 'e') || match(parser, 'E')) {
        (void) (match(parser, '+') || match(parser, '-'));

        if (yp_char_is_decimal_digit(*parser->current.end)) {
            parser->current.end++;
            parser->current.end += yp_strspn_decimal_number(parser->current.end, parser->end - parser->current.end);
            type = YP_TOKEN_FLOAT;
        } else {
            yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_FLOAT_EXPONENT);
            type = YP_TOKEN_FLOAT;
        }
    }

    return type;
}

static yp_token_type_t
lex_numeric_prefix(yp_parser_t *parser) {
    yp_token_type_t type = YP_TOKEN_INTEGER;

    if (peek_offset(parser, -1) == '0') {
        switch (*parser->current.end) {
            // 0d1111 is a decimal number
            case 'd':
            case 'D':
                parser->current.end++;
                if (yp_char_is_decimal_digit(peek(parser))) {
                    parser->current.end += yp_strspn_decimal_number(parser->current.end, parser->end - parser->current.end);
                } else {
                    yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_NUMBER_DECIMAL);
                }

                break;

            // 0b1111 is a binary number
            case 'b':
            case 'B':
                parser->current.end++;
                if (yp_char_is_binary_digit(peek(parser))) {
                    parser->current.end += yp_strspn_binary_number(parser->current.end, parser->end - parser->current.end);
                } else {
                    yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_NUMBER_BINARY);
                }

                break;

            // 0o1111 is an octal number
            case 'o':
            case 'O':
                parser->current.end++;
                if (yp_char_is_octal_digit(peek(parser))) {
                    parser->current.end += yp_strspn_octal_number(parser->current.end, parser->end - parser->current.end);
                } else {
                    yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_NUMBER_OCTAL);
                }

                break;

            // 01111 is an octal number
            case '_':
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
                parser->current.end += yp_strspn_octal_number(parser->current.end, parser->end - parser->current.end);
                break;

            // 0x1111 is a hexadecimal number
            case 'x':
            case 'X':
                parser->current.end++;
                if (yp_char_is_hexadecimal_digit(peek(parser))) {
                    parser->current.end += yp_strspn_hexadecimal_number(parser->current.end, parser->end - parser->current.end);
                } else {
                    yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_NUMBER_HEXADECIMAL);
                }

                break;

            // 0.xxx is a float
            case '.': {
                type = lex_optional_float_suffix(parser);
                break;
            }

            // 0exxx is a float
            case 'e':
            case 'E': {
                type = lex_optional_float_suffix(parser);
                break;
            }
        }
    } else {
        // If it didn't start with a 0, then we'll lex as far as we can into a
        // decimal number.
        parser->current.end += yp_strspn_decimal_number(parser->current.end, parser->end - parser->current.end);

        // Afterward, we'll lex as far as we can into an optional float suffix.
        type = lex_optional_float_suffix(parser);
    }

    // If the last character that we consumed was an underscore, then this is
    // actually an invalid integer value, and we should return an invalid token.
    if (peek_offset(parser, -1) == '_') {
        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_NUMBER_LITERAL_UNDERSCORE);
    }

    return type;
}

static yp_token_type_t
lex_numeric(yp_parser_t *parser) {
    yp_token_type_t type = YP_TOKEN_INTEGER;

    if (parser->current.end < parser->end) {
        type = lex_numeric_prefix(parser);

        const uint8_t *end = parser->current.end;
        yp_token_type_t suffix_type = type;

        if (type == YP_TOKEN_INTEGER) {
            if (match(parser, 'r')) {
                suffix_type = YP_TOKEN_INTEGER_RATIONAL;

                if (match(parser, 'i')) {
                    suffix_type = YP_TOKEN_INTEGER_RATIONAL_IMAGINARY;
                }
            } else if (match(parser, 'i')) {
                suffix_type = YP_TOKEN_INTEGER_IMAGINARY;
            }
        } else {
            if (match(parser, 'r')) {
                suffix_type = YP_TOKEN_FLOAT_RATIONAL;

                if (match(parser, 'i')) {
                    suffix_type = YP_TOKEN_FLOAT_RATIONAL_IMAGINARY;
                }
            } else if (match(parser, 'i')) {
                suffix_type = YP_TOKEN_FLOAT_IMAGINARY;
            }
        }

        const uint8_t b = peek(parser);
        if (b != '\0' && (b >= 0x80 || ((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')) || b == '_')) {
            parser->current.end = end;
        } else {
            type = suffix_type;
        }
    }

    return type;
}

static yp_token_type_t
lex_global_variable(yp_parser_t *parser) {
    if (parser->current.end >= parser->end) {
        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_VARIABLE_GLOBAL);
        return YP_TOKEN_GLOBAL_VARIABLE;
    }

    switch (*parser->current.end) {
        case '~':  // $~: match-data
        case '*':  // $*: argv
        case '$':  // $$: pid
        case '?':  // $?: last status
        case '!':  // $!: error string
        case '@':  // $@: error position
        case '/':  // $/: input record separator
        case '\\': // $\: output record separator
        case ';':  // $;: field separator
        case ',':  // $,: output field separator
        case '.':  // $.: last read line number
        case '=':  // $=: ignorecase
        case ':':  // $:: load path
        case '<':  // $<: reading filename
        case '>':  // $>: default output handle
        case '\"': // $": already loaded files
            parser->current.end++;
            return YP_TOKEN_GLOBAL_VARIABLE;

        case '&':  // $&: last match
        case '`':  // $`: string before last match
        case '\'': // $': string after last match
        case '+':  // $+: string matches last paren.
            parser->current.end++;
            return lex_state_p(parser, YP_LEX_STATE_FNAME) ? YP_TOKEN_GLOBAL_VARIABLE : YP_TOKEN_BACK_REFERENCE;

        case '0': {
            parser->current.end++;
            size_t width;

            if (parser->current.end < parser->end && (width = char_is_identifier(parser, parser->current.end)) > 0) {
                do {
                    parser->current.end += width;
                } while (parser->current.end < parser->end && (width = char_is_identifier(parser, parser->current.end)) > 0);

                // $0 isn't allowed to be followed by anything.
                yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_VARIABLE_GLOBAL);
            }

            return YP_TOKEN_GLOBAL_VARIABLE;
        }

        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
            parser->current.end += yp_strspn_decimal_digit(parser->current.end, parser->end - parser->current.end);
            return lex_state_p(parser, YP_LEX_STATE_FNAME) ? YP_TOKEN_GLOBAL_VARIABLE : YP_TOKEN_NUMBERED_REFERENCE;

        case '-':
            parser->current.end++;
            /* fallthrough */
        default: {
            size_t width;

            if ((width = char_is_identifier(parser, parser->current.end)) > 0) {
                do {
                    parser->current.end += width;
                } while (parser->current.end < parser->end && (width = char_is_identifier(parser, parser->current.end)) > 0);
            } else {
                // If we get here, then we have a $ followed by something that isn't
                // recognized as a global variable.
                yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_VARIABLE_GLOBAL);
            }

            return YP_TOKEN_GLOBAL_VARIABLE;
        }
    }
}

// This function checks if the current token matches a keyword. If it does, it
// returns true. Otherwise, it returns false. The arguments are as follows:
//
// * `value` - the literal string that we're checking for
// * `width` - the length of the token
// * `state` - the state that we should transition to if the token matches
//
static yp_token_type_t
lex_keyword(yp_parser_t *parser, const char *value, yp_lex_state_t state, yp_token_type_t type, yp_token_type_t modifier_type) {
    yp_lex_state_t last_state = parser->lex_state;

    const size_t vlen = strlen(value);
    if (parser->current.start + vlen <= parser->end && memcmp(parser->current.start, value, vlen) == 0) {
        if (parser->lex_state & YP_LEX_STATE_FNAME) {
            lex_state_set(parser, YP_LEX_STATE_ENDFN);
        } else {
            lex_state_set(parser, state);
            if (state == YP_LEX_STATE_BEG) {
                parser->command_start = true;
            }

            if ((modifier_type != YP_TOKEN_EOF) && !(last_state & (YP_LEX_STATE_BEG | YP_LEX_STATE_LABELED | YP_LEX_STATE_CLASS))) {
                lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);
                return modifier_type;
            }
        }

        return type;
    }

    return YP_TOKEN_EOF;
}

static yp_token_type_t
lex_identifier(yp_parser_t *parser, bool previous_command_start) {
    // Lex as far as we can into the current identifier.
    size_t width;
    while (parser->current.end < parser->end && (width = char_is_identifier(parser, parser->current.end)) > 0) {
        parser->current.end += width;
    }

    // Now cache the length of the identifier so that we can quickly compare it
    // against known keywords.
    width = (size_t) (parser->current.end - parser->current.start);

    if (parser->current.end < parser->end) {
        if (((parser->current.end + 1 >= parser->end) || (parser->current.end[1] != '=')) && (match(parser, '!') || match(parser, '?'))) {
            // First we'll attempt to extend the identifier by a ! or ?. Then we'll
            // check if we're returning the defined? keyword or just an identifier.
            width++;

            if (
                ((lex_state_p(parser, YP_LEX_STATE_LABEL | YP_LEX_STATE_ENDFN) && !previous_command_start) || lex_state_arg_p(parser)) &&
                (peek(parser) == ':') && (peek_offset(parser, 1) != ':')
            ) {
                // If we're in a position where we can accept a : at the end of an
                // identifier, then we'll optionally accept it.
                lex_state_set(parser, YP_LEX_STATE_ARG | YP_LEX_STATE_LABELED);
                (void) match(parser, ':');
                return YP_TOKEN_LABEL;
            }

            if (parser->lex_state != YP_LEX_STATE_DOT) {
                if (width == 8 && (lex_keyword(parser, "defined?", YP_LEX_STATE_ARG, YP_TOKEN_KEYWORD_DEFINED, YP_TOKEN_EOF) != YP_TOKEN_EOF)) {
                    return YP_TOKEN_KEYWORD_DEFINED;
                }
            }

            return YP_TOKEN_IDENTIFIER;
        } else if (lex_state_p(parser, YP_LEX_STATE_FNAME) && peek_offset(parser, 1) != '~' && peek_offset(parser, 1) != '>' && (peek_offset(parser, 1) != '=' || peek_offset(parser, 2) == '>') && match(parser, '=')) {
            // If we're in a position where we can accept a = at the end of an
            // identifier, then we'll optionally accept it.
            return YP_TOKEN_IDENTIFIER;
        }

        if (
            ((lex_state_p(parser, YP_LEX_STATE_LABEL | YP_LEX_STATE_ENDFN) && !previous_command_start) || lex_state_arg_p(parser)) &&
            peek(parser) == ':' && peek_offset(parser, 1) != ':'
        ) {
            // If we're in a position where we can accept a : at the end of an
            // identifier, then we'll optionally accept it.
            lex_state_set(parser, YP_LEX_STATE_ARG | YP_LEX_STATE_LABELED);
            (void) match(parser, ':');
            return YP_TOKEN_LABEL;
        }
    }

    if (parser->lex_state != YP_LEX_STATE_DOT) {
        yp_token_type_t type;

        switch (width) {
            case 2:
                if (lex_keyword(parser, "do", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_DO, YP_TOKEN_EOF) != YP_TOKEN_EOF) {
                    if (yp_do_loop_stack_p(parser)) {
                        return YP_TOKEN_KEYWORD_DO_LOOP;
                    }
                    return YP_TOKEN_KEYWORD_DO;
                }

                if ((type = lex_keyword(parser, "if", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_IF, YP_TOKEN_KEYWORD_IF_MODIFIER)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "in", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_IN, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "or", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_OR, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                break;
            case 3:
                if ((type = lex_keyword(parser, "and", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_AND, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "def", YP_LEX_STATE_FNAME, YP_TOKEN_KEYWORD_DEF, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "end", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_END, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "END", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_END_UPCASE, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "for", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_FOR, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "nil", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_NIL, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "not", YP_LEX_STATE_ARG, YP_TOKEN_KEYWORD_NOT, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                break;
            case 4:
                if ((type = lex_keyword(parser, "case", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_CASE, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "else", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_ELSE, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "next", YP_LEX_STATE_MID, YP_TOKEN_KEYWORD_NEXT, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "redo", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_REDO, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "self", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_SELF, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "then", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_THEN, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "true", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_TRUE, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "when", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_WHEN, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                break;
            case 5:
                if ((type = lex_keyword(parser, "alias", YP_LEX_STATE_FNAME | YP_LEX_STATE_FITEM, YP_TOKEN_KEYWORD_ALIAS, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "begin", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_BEGIN, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "BEGIN", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_BEGIN_UPCASE, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "break", YP_LEX_STATE_MID, YP_TOKEN_KEYWORD_BREAK, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "class", YP_LEX_STATE_CLASS, YP_TOKEN_KEYWORD_CLASS, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "elsif", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_ELSIF, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "false", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_FALSE, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "retry", YP_LEX_STATE_END, YP_TOKEN_KEYWORD_RETRY, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "super", YP_LEX_STATE_ARG, YP_TOKEN_KEYWORD_SUPER, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "undef", YP_LEX_STATE_FNAME | YP_LEX_STATE_FITEM, YP_TOKEN_KEYWORD_UNDEF, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "until", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_UNTIL, YP_TOKEN_KEYWORD_UNTIL_MODIFIER)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "while", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_WHILE, YP_TOKEN_KEYWORD_WHILE_MODIFIER)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "yield", YP_LEX_STATE_ARG, YP_TOKEN_KEYWORD_YIELD, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                break;
            case 6:
                if ((type = lex_keyword(parser, "ensure", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_ENSURE, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "module", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_MODULE, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "rescue", YP_LEX_STATE_MID, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_RESCUE_MODIFIER)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "return", YP_LEX_STATE_MID, YP_TOKEN_KEYWORD_RETURN, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "unless", YP_LEX_STATE_BEG, YP_TOKEN_KEYWORD_UNLESS, YP_TOKEN_KEYWORD_UNLESS_MODIFIER)) != YP_TOKEN_EOF) return type;
                break;
            case 8:
                if ((type = lex_keyword(parser, "__LINE__", YP_LEX_STATE_END, YP_TOKEN_KEYWORD___LINE__, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                if ((type = lex_keyword(parser, "__FILE__", YP_LEX_STATE_END, YP_TOKEN_KEYWORD___FILE__, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                break;
            case 12:
                if ((type = lex_keyword(parser, "__ENCODING__", YP_LEX_STATE_END, YP_TOKEN_KEYWORD___ENCODING__, YP_TOKEN_EOF)) != YP_TOKEN_EOF) return type;
                break;
        }
    }

    return parser->encoding.isupper_char(parser->current.start, parser->end - parser->current.start) ? YP_TOKEN_CONSTANT : YP_TOKEN_IDENTIFIER;
}

// Returns true if the current token that the parser is considering is at the
// beginning of a line or the beginning of the source.
static bool
current_token_starts_line(yp_parser_t *parser) {
    return (parser->current.start == parser->start) || (parser->current.start[-1] == '\n');
}

// When we hit a # while lexing something like a string, we need to potentially
// handle interpolation. This function performs that check. It returns a token
// type representing what it found. Those cases are:
//
// * YP_TOKEN_NOT_PROVIDED - No interpolation was found at this point. The
//     caller should keep lexing.
// * YP_TOKEN_STRING_CONTENT - No interpolation was found at this point. The
//     caller should return this token type.
// * YP_TOKEN_EMBEXPR_BEGIN - An embedded expression was found. The caller
//     should return this token type.
// * YP_TOKEN_EMBVAR - An embedded variable was found. The caller should return
//     this token type.
//
static yp_token_type_t
lex_interpolation(yp_parser_t *parser, const uint8_t *pound) {
    // If there is no content following this #, then we're at the end of
    // the string and we can safely return string content.
    if (pound + 1 >= parser->end) {
        parser->current.end = pound + 1;
        return YP_TOKEN_STRING_CONTENT;
    }

    // Now we'll check against the character the follows the #. If it constitutes
    // valid interplation, we'll handle that, otherwise we'll return
    // YP_TOKEN_NOT_PROVIDED.
    switch (pound[1]) {
        case '@': {
            // In this case we may have hit an embedded instance or class variable.
            if (pound + 2 >= parser->end) {
                parser->current.end = pound + 1;
                return YP_TOKEN_STRING_CONTENT;
            }

            // If we're looking at a @ and there's another @, then we'll skip past the
            // second @.
            const uint8_t *variable = pound + 2;
            if (*variable == '@' && pound + 3 < parser->end) variable++;

            if (char_is_identifier_start(parser, variable)) {
                // At this point we're sure that we've either hit an embedded instance
                // or class variable. In this case we'll first need to check if we've
                // already consumed content.
                if (pound > parser->current.start) {
                    parser->current.end = pound;
                    return YP_TOKEN_STRING_CONTENT;
                }

                // Otherwise we need to return the embedded variable token
                // and then switch to the embedded variable lex mode.
                lex_mode_push(parser, (yp_lex_mode_t) { .mode = YP_LEX_EMBVAR });
                parser->current.end = pound + 1;
                return YP_TOKEN_EMBVAR;
            }

            // If we didn't get an valid interpolation, then this is just regular
            // string content. This is like if we get "#@-". In this case the caller
            // should keep lexing.
            parser->current.end = variable;
            return YP_TOKEN_NOT_PROVIDED;
        }
        case '$':
            // In this case we may have hit an embedded global variable. If there's
            // not enough room, then we'll just return string content.
            if (pound + 2 >= parser->end) {
                parser->current.end = pound + 1;
                return YP_TOKEN_STRING_CONTENT;
            }

            // This is the character that we're going to check to see if it is the
            // start of an identifier that would indicate that this is a global
            // variable.
            const uint8_t *check = pound + 2;

            if (pound[2] == '-') {
                if (pound + 3 >= parser->end) {
                    parser->current.end = pound + 2;
                    return YP_TOKEN_STRING_CONTENT;
                }

                check++;
            }

            // If the character that we're going to check is the start of an
            // identifier, or we don't have a - and the character is a decimal number
            // or a global name punctuation character, then we've hit an embedded
            // global variable.
            if (
                char_is_identifier_start(parser, check) ||
                (pound[2] != '-' && (yp_char_is_decimal_digit(pound[2]) || char_is_global_name_punctuation(pound[2])))
            ) {
                // In this case we've hit an embedded global variable. First check to
                // see if we've already consumed content. If we have, then we need to
                // return that content as string content first.
                if (pound > parser->current.start) {
                    parser->current.end = pound;
                    return YP_TOKEN_STRING_CONTENT;
                }

                // Otherwise, we need to return the embedded variable token and switch
                // to the embedded variable lex mode.
                lex_mode_push(parser, (yp_lex_mode_t) { .mode = YP_LEX_EMBVAR });
                parser->current.end = pound + 1;
                return YP_TOKEN_EMBVAR;
            }

            // In this case we've hit a #$ that does not indicate a global variable.
            // In this case we'll continue lexing past it.
            parser->current.end = pound + 1;
            return YP_TOKEN_NOT_PROVIDED;
        case '{':
            // In this case it's the start of an embedded expression. If we have
            // already consumed content, then we need to return that content as string
            // content first.
            if (pound > parser->current.start) {
                parser->current.end = pound;
                return YP_TOKEN_STRING_CONTENT;
            }

            parser->enclosure_nesting++;

            // Otherwise we'll skip past the #{ and begin lexing the embedded
            // expression.
            lex_mode_push(parser, (yp_lex_mode_t) { .mode = YP_LEX_EMBEXPR });
            parser->current.end = pound + 2;
            parser->command_start = true;
            yp_do_loop_stack_push(parser, false);
            return YP_TOKEN_EMBEXPR_BEGIN;
        default:
            // In this case we've hit a # that doesn't constitute interpolation. We'll
            // mark that by returning the not provided token type. This tells the
            // consumer to keep lexing forward.
            parser->current.end = pound + 1;
            return YP_TOKEN_NOT_PROVIDED;
    }
}

// This function is responsible for lexing either a character literal or the ?
// operator. The supported character literals are described below.
//
// \a             bell, ASCII 07h (BEL)
// \b             backspace, ASCII 08h (BS)
// \t             horizontal tab, ASCII 09h (TAB)
// \n             newline (line feed), ASCII 0Ah (LF)
// \v             vertical tab, ASCII 0Bh (VT)
// \f             form feed, ASCII 0Ch (FF)
// \r             carriage return, ASCII 0Dh (CR)
// \e             escape, ASCII 1Bh (ESC)
// \s             space, ASCII 20h (SPC)
// \\             backslash
// \nnn           octal bit pattern, where nnn is 1-3 octal digits ([0-7])
// \xnn           hexadecimal bit pattern, where nn is 1-2 hexadecimal digits ([0-9a-fA-F])
// \unnnn         Unicode character, where nnnn is exactly 4 hexadecimal digits ([0-9a-fA-F])
// \u{nnnn ...}   Unicode character(s), where each nnnn is 1-6 hexadecimal digits ([0-9a-fA-F])
// \cx or \C-x    control character, where x is an ASCII printable character
// \M-x           meta character, where x is an ASCII printable character
// \M-\C-x        meta control character, where x is an ASCII printable character
// \M-\cx         same as above
// \c\M-x         same as above
// \c? or \C-?    delete, ASCII 7Fh (DEL)
//
static yp_token_type_t
lex_question_mark(yp_parser_t *parser) {
    if (lex_state_end_p(parser)) {
        lex_state_set(parser, YP_LEX_STATE_BEG);
        return YP_TOKEN_QUESTION_MARK;
    }

    if (parser->current.end >= parser->end) {
        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INCOMPLETE_QUESTION_MARK);
        return YP_TOKEN_CHARACTER_LITERAL;
    }

    if (yp_char_is_whitespace(*parser->current.end)) {
        lex_state_set(parser, YP_LEX_STATE_BEG);
        return YP_TOKEN_QUESTION_MARK;
    }

    lex_state_set(parser, YP_LEX_STATE_BEG);

    if (parser->current.start[1] == '\\') {
        lex_state_set(parser, YP_LEX_STATE_END);
        parser->current.end += yp_unescape_calculate_difference(parser, parser->current.start + 1, YP_UNESCAPE_ALL, true);
        return YP_TOKEN_CHARACTER_LITERAL;
    } else {
        size_t encoding_width = parser->encoding.char_width(parser->current.end, parser->end - parser->current.end);

        // Ternary operators can have a ? immediately followed by an identifier which starts with
        // an underscore. We check for this case
        if (
            !(parser->encoding.alnum_char(parser->current.end, parser->end - parser->current.end) ||
              peek(parser) == '_') ||
            (
                (parser->current.end + encoding_width >= parser->end) ||
                !char_is_identifier(parser, parser->current.end + encoding_width)
            )
        ) {
            lex_state_set(parser, YP_LEX_STATE_END);
            parser->current.end += encoding_width;
            return YP_TOKEN_CHARACTER_LITERAL;
        }
    }

    return YP_TOKEN_QUESTION_MARK;
}

// Lex a variable that starts with an @ sign (either an instance or class
// variable).
static yp_token_type_t
lex_at_variable(yp_parser_t *parser) {
    yp_token_type_t type = match(parser, '@') ? YP_TOKEN_CLASS_VARIABLE : YP_TOKEN_INSTANCE_VARIABLE;
    size_t width;

    if (parser->current.end < parser->end && (width = char_is_identifier_start(parser, parser->current.end)) > 0) {
        parser->current.end += width;

        while (parser->current.end < parser->end && (width = char_is_identifier(parser, parser->current.end)) > 0) {
            parser->current.end += width;
        }
    } else if (type == YP_TOKEN_CLASS_VARIABLE) {
        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INCOMPLETE_VARIABLE_CLASS);
    } else {
        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INCOMPLETE_VARIABLE_INSTANCE);
    }

    // If we're lexing an embedded variable, then we need to pop back into the
    // parent lex context.
    if (parser->lex_modes.current->mode == YP_LEX_EMBVAR) {
        lex_mode_pop(parser);
    }

    return type;
}

// Optionally call out to the lex callback if one is provided.
static inline void
parser_lex_callback(yp_parser_t *parser) {
    if (parser->lex_callback) {
        parser->lex_callback->callback(parser->lex_callback->data, parser, &parser->current);
    }
}

// Return a new comment node of the specified type.
static inline yp_comment_t *
parser_comment(yp_parser_t *parser, yp_comment_type_t type) {
    yp_comment_t *comment = (yp_comment_t *) malloc(sizeof(yp_comment_t));
    if (comment == NULL) return NULL;

    *comment = (yp_comment_t) {
        .type = type,
        .start = parser->current.start,
        .end = parser->current.end
    };

    return comment;
}

// Lex out embedded documentation, and return when we have either hit the end of
// the file or the end of the embedded documentation. This calls the callback
// manually because only the lexer should see these tokens, not the parser.
static yp_token_type_t
lex_embdoc(yp_parser_t *parser) {
    // First, lex out the EMBDOC_BEGIN token.
    const uint8_t *newline = next_newline(parser->current.end, parser->end - parser->current.end);

    if (newline == NULL) {
        parser->current.end = parser->end;
    } else {
        yp_newline_list_append(&parser->newline_list, newline);
        parser->current.end = newline + 1;
    }

    parser->current.type = YP_TOKEN_EMBDOC_BEGIN;
    parser_lex_callback(parser);

    // Now, create a comment that is going to be attached to the parser.
    yp_comment_t *comment = parser_comment(parser, YP_COMMENT_EMBDOC);
    if (comment == NULL) return YP_TOKEN_EOF;

    // Now, loop until we find the end of the embedded documentation or the end of
    // the file.
    while (parser->current.end + 4 <= parser->end) {
        parser->current.start = parser->current.end;

        // If we've hit the end of the embedded documentation then we'll return that
        // token here.
        if (memcmp(parser->current.end, "=end", 4) == 0 &&
                (parser->current.end + 4 == parser->end || yp_char_is_whitespace(parser->current.end[4]))) {
            const uint8_t *newline = next_newline(parser->current.end, parser->end - parser->current.end);

            if (newline == NULL) {
                parser->current.end = parser->end;
            } else {
                yp_newline_list_append(&parser->newline_list, newline);
                parser->current.end = newline + 1;
            }

            parser->current.type = YP_TOKEN_EMBDOC_END;
            parser_lex_callback(parser);

            comment->end = parser->current.end;
            yp_list_append(&parser->comment_list, (yp_list_node_t *) comment);

            return YP_TOKEN_EMBDOC_END;
        }

        // Otherwise, we'll parse until the end of the line and return a line of
        // embedded documentation.
        const uint8_t *newline = next_newline(parser->current.end, parser->end - parser->current.end);

        if (newline == NULL) {
            parser->current.end = parser->end;
        } else {
            yp_newline_list_append(&parser->newline_list, newline);
            parser->current.end = newline + 1;
        }

        parser->current.type = YP_TOKEN_EMBDOC_LINE;
        parser_lex_callback(parser);
    }

    yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_EMBDOC_TERM);

    comment->end = parser->current.end;
    yp_list_append(&parser->comment_list, (yp_list_node_t *) comment);

    return YP_TOKEN_EOF;
}

// Set the current type to an ignored newline and then call the lex callback.
// This happens in a couple places depending on whether or not we have already
// lexed a comment.
static inline void
parser_lex_ignored_newline(yp_parser_t *parser) {
    parser->current.type = YP_TOKEN_IGNORED_NEWLINE;
    parser_lex_callback(parser);
}

// This function will be called when a newline is encountered. In some newlines,
// we need to check if there is a heredoc or heredocs that we have already lexed
// the body of that we need to now skip past. That will be indicated by the
// heredoc_end field on the parser.
//
// If it is set, then we need to skip past the heredoc body and then clear the
// heredoc_end field.
static inline void
parser_flush_heredoc_end(yp_parser_t *parser) {
    assert(parser->heredoc_end <= parser->end);
    parser->next_start = parser->heredoc_end;
    parser->heredoc_end = NULL;
}

// This is a convenience macro that will set the current token type, call the
// lex callback, and then return from the parser_lex function.
#define LEX(token_type) parser->current.type = token_type; parser_lex_callback(parser); return

// Called when the parser requires a new token. The parser maintains a moving
// window of two tokens at a time: parser.previous and parser.current. This
// function will move the current token into the previous token and then
// lex a new token into the current token.
static void
parser_lex(yp_parser_t *parser) {
    assert(parser->current.end <= parser->end);
    parser->previous = parser->current;

    // This value mirrors cmd_state from CRuby.
    bool previous_command_start = parser->command_start;
    parser->command_start = false;

    // This is used to communicate to the newline lexing function that we've
    // already seen a comment.
    bool lexed_comment = false;

    switch (parser->lex_modes.current->mode) {
        case YP_LEX_DEFAULT:
        case YP_LEX_EMBEXPR:
        case YP_LEX_EMBVAR:

        // We have a specific named label here because we are going to jump back to
        // this location in the event that we have lexed a token that should not be
        // returned to the parser. This includes comments, ignored newlines, and
        // invalid tokens of some form.
        lex_next_token: {
            // If we have the special next_start pointer set, then we're going to jump
            // to that location and start lexing from there.
            if (parser->next_start != NULL) {
                parser->current.end = parser->next_start;
                parser->next_start = NULL;
            }

            // This value mirrors space_seen from CRuby. It tracks whether or not
            // space has been eaten before the start of the next token.
            bool space_seen = false;

            // First, we're going to skip past any whitespace at the front of the next
            // token.
            bool chomping = true;
            while (parser->current.end < parser->end && chomping) {
                switch (*parser->current.end) {
                    case ' ':
                    case '\t':
                    case '\f':
                    case '\v':
                        parser->current.end++;
                        space_seen = true;
                        break;
                    case '\r':
                        if (match_eol_offset(parser, 1)) {
                            chomping = false;
                        } else {
                            parser->current.end++;
                            space_seen = true;
                        }
                        break;
                    case '\\': {
                        size_t eol_length = match_eol_offset(parser, 1);
                        if (eol_length) {
                            if (parser->heredoc_end) {
                                parser->current.end = parser->heredoc_end;
                                parser->heredoc_end = NULL;
                            } else {
                                parser->current.end += eol_length + 1;
                                yp_newline_list_append(&parser->newline_list, parser->current.end - 1);
                                space_seen = true;
                            }
                        } else if (yp_char_is_inline_whitespace(*parser->current.end)) {
                            parser->current.end += 2;
                        } else {
                            chomping = false;
                        }

                        break;
                    }
                    default:
                        chomping = false;
                        break;
                }
            }

            // Next, we'll set to start of this token to be the current end.
            parser->current.start = parser->current.end;

            // We'll check if we're at the end of the file. If we are, then we
            // need to return the EOF token.
            if (parser->current.end >= parser->end) {
                LEX(YP_TOKEN_EOF);
            }

            // Finally, we'll check the current character to determine the next
            // token.
            switch (*parser->current.end++) {
                case '\0':   // NUL or end of script
                case '\004': // ^D
                case '\032': // ^Z
                    parser->current.end--;
                    LEX(YP_TOKEN_EOF);

                case '#': { // comments
                    const uint8_t *ending = next_newline(parser->current.end, parser->end - parser->current.end);

                    parser->current.end = ending == NULL ? parser->end : ending + 1;
                    parser->current.type = YP_TOKEN_COMMENT;
                    parser_lex_callback(parser);

                    // If we found a comment while lexing, then we're going to
                    // add it to the list of comments in the file and keep
                    // lexing.
                    yp_comment_t *comment = parser_comment(parser, YP_COMMENT_INLINE);
                    yp_list_append(&parser->comment_list, (yp_list_node_t *) comment);

                    if (parser->current.start == parser->encoding_comment_start) {
                        parser_lex_encoding_comment(parser);
                    }

                    lexed_comment = true;
                }
                /* fallthrough */
                case '\r':
                case '\n': {
                    size_t eol_length = match_eol_at(parser, parser->current.end - 1);
                    if (eol_length) {
                        // The only way you can have carriage returns in this
                        // particular loop is if you have a carriage return
                        // followed by a newline. In that case we'll just skip
                        // over the carriage return and continue lexing, in
                        // order to make it so that the newline token
                        // encapsulates both the carriage return and the
                        // newline. Note that we need to check that we haven't
                        // already lexed a comment here because that falls
                        // through into here as well.
                        if (!lexed_comment) {
                            parser->current.end += eol_length - 1; // skip CR
                        }

                        if (parser->heredoc_end == NULL) {
                            yp_newline_list_append(&parser->newline_list, parser->current.end - 1);
                        }
                    }

                    if (parser->heredoc_end) {
                        parser_flush_heredoc_end(parser);
                    }

                    // If this is an ignored newline, then we can continue lexing after
                    // calling the callback with the ignored newline token.
                    switch (lex_state_ignored_p(parser)) {
                        case YP_IGNORED_NEWLINE_NONE:
                            break;
                        case YP_IGNORED_NEWLINE_PATTERN:
                            if (parser->pattern_matching_newlines || parser->in_keyword_arg) {
                                if (!lexed_comment) parser_lex_ignored_newline(parser);
                                lex_state_set(parser, YP_LEX_STATE_BEG);
                                parser->command_start = true;
                                parser->current.type = YP_TOKEN_NEWLINE;
                                return;
                            }
                            /* fallthrough */
                        case YP_IGNORED_NEWLINE_ALL:
                            if (!lexed_comment) parser_lex_ignored_newline(parser);
                            lexed_comment = false;
                            goto lex_next_token;
                    }

                    // Here we need to look ahead and see if there is a call operator
                    // (either . or &.) that starts the next line. If there is, then this
                    // is going to become an ignored newline and we're going to instead
                    // return the call operator.
                    const uint8_t *next_content = parser->next_start == NULL ? parser->current.end : parser->next_start;
                    next_content += yp_strspn_inline_whitespace(next_content, parser->end - next_content);

                    if (next_content < parser->end) {
                        // If we hit a comment after a newline, then we're going to check
                        // if it's ignored or if it's followed by a method call ('.').
                        // If it is, then we're going to call the
                        // callback with an ignored newline and then continue lexing.
                        // Otherwise we'll return a regular newline.
                        if (next_content[0] == '#') {
                            // Here we look for a "." or "&." following a "\n".
                            const uint8_t *following = next_newline(next_content, parser->end - next_content);

                            while (following && (following + 1 < parser->end)) {
                                following++;
                                following += yp_strspn_inline_whitespace(following, parser->end - following);

                                // If this is not followed by a comment, then we can break out
                                // of this loop.
                                if (peek_at(parser, following) != '#') break;

                                // If there is a comment, then we need to find the end of the
                                // comment and continue searching from there.
                                following = next_newline(following, parser->end - following);
                            }

                            // If the lex state was ignored, or we hit a '.' or a '&.',
                            // we will lex the ignored newline
                            if (
                                lex_state_ignored_p(parser) ||
                                (following && (
                                    (peek_at(parser, following) == '.') ||
                                    (peek_at(parser, following) == '&' && peek_at(parser, following + 1) == '.')
                                ))
                            ) {
                                if (!lexed_comment) parser_lex_ignored_newline(parser);
                                lexed_comment = false;
                                goto lex_next_token;
                            }
                        }

                        // If we hit a . after a newline, then we're in a call chain and
                        // we need to return the call operator.
                        if (next_content[0] == '.') {
                            // To match ripper, we need to emit an ignored newline even though
                            // its a real newline in the case that we have a beginless range
                            // on a subsequent line.
                            if (peek_at(parser, next_content + 1) == '.') {
                                if (!lexed_comment) parser_lex_ignored_newline(parser);
                                lex_state_set(parser, YP_LEX_STATE_BEG);
                                parser->command_start = true;
                                parser->current.type = YP_TOKEN_NEWLINE;
                                return;
                            }

                            if (!lexed_comment) parser_lex_ignored_newline(parser);
                            lex_state_set(parser, YP_LEX_STATE_DOT);
                            parser->current.start = next_content;
                            parser->current.end = next_content + 1;
                            parser->next_start = NULL;
                            LEX(YP_TOKEN_DOT);
                        }

                        // If we hit a &. after a newline, then we're in a call chain and
                        // we need to return the call operator.
                        if (peek_at(parser, next_content) == '&' && peek_at(parser, next_content + 1) == '.') {
                            if (!lexed_comment) parser_lex_ignored_newline(parser);
                            lex_state_set(parser, YP_LEX_STATE_DOT);
                            parser->current.start = next_content;
                            parser->current.end = next_content + 2;
                            parser->next_start = NULL;
                            LEX(YP_TOKEN_AMPERSAND_DOT);
                        }
                    }

                    // At this point we know this is a regular newline, and we can set the
                    // necessary state and return the token.
                    lex_state_set(parser, YP_LEX_STATE_BEG);
                    parser->command_start = true;
                    parser->current.type = YP_TOKEN_NEWLINE;
                    if (!lexed_comment) parser_lex_callback(parser);
                    return;
                }

                // ,
                case ',':
                    lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);
                    LEX(YP_TOKEN_COMMA);

                // (
                case '(': {
                    yp_token_type_t type = YP_TOKEN_PARENTHESIS_LEFT;

                    if (space_seen && (lex_state_arg_p(parser) || parser->lex_state == (YP_LEX_STATE_END | YP_LEX_STATE_LABEL))) {
                        type = YP_TOKEN_PARENTHESIS_LEFT_PARENTHESES;
                    }

                    parser->enclosure_nesting++;
                    lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);
                    yp_do_loop_stack_push(parser, false);
                    LEX(type);
                }

                // )
                case ')':
                    parser->enclosure_nesting--;
                    lex_state_set(parser, YP_LEX_STATE_ENDFN);
                    yp_do_loop_stack_pop(parser);
                    LEX(YP_TOKEN_PARENTHESIS_RIGHT);

                // ;
                case ';':
                    lex_state_set(parser, YP_LEX_STATE_BEG);
                    parser->command_start = true;
                    LEX(YP_TOKEN_SEMICOLON);

                // [ [] []=
                case '[':
                    parser->enclosure_nesting++;
                    yp_token_type_t type = YP_TOKEN_BRACKET_LEFT;

                    if (lex_state_operator_p(parser)) {
                        if (match(parser, ']')) {
                            parser->enclosure_nesting--;
                            lex_state_set(parser, YP_LEX_STATE_ARG);
                            LEX(match(parser, '=') ? YP_TOKEN_BRACKET_LEFT_RIGHT_EQUAL : YP_TOKEN_BRACKET_LEFT_RIGHT);
                        }

                        lex_state_set(parser, YP_LEX_STATE_ARG | YP_LEX_STATE_LABEL);
                        LEX(type);
                    }

                    if (lex_state_beg_p(parser) || (lex_state_arg_p(parser) && (space_seen || lex_state_p(parser, YP_LEX_STATE_LABELED)))) {
                        type = YP_TOKEN_BRACKET_LEFT_ARRAY;
                    }

                    lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);
                    yp_do_loop_stack_push(parser, false);
                    LEX(type);

                // ]
                case ']':
                    parser->enclosure_nesting--;
                    lex_state_set(parser, YP_LEX_STATE_END);
                    yp_do_loop_stack_pop(parser);
                    LEX(YP_TOKEN_BRACKET_RIGHT);

                // {
                case '{': {
                    yp_token_type_t type = YP_TOKEN_BRACE_LEFT;

                    if (parser->enclosure_nesting == parser->lambda_enclosure_nesting) {
                        // This { begins a lambda
                        parser->command_start = true;
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        type = YP_TOKEN_LAMBDA_BEGIN;
                    } else if (lex_state_p(parser, YP_LEX_STATE_LABELED)) {
                        // This { begins a hash literal
                        lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);
                    } else if (lex_state_p(parser, YP_LEX_STATE_ARG_ANY | YP_LEX_STATE_END | YP_LEX_STATE_ENDFN)) {
                        // This { begins a block
                        parser->command_start = true;
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    } else if (lex_state_p(parser, YP_LEX_STATE_ENDARG)) {
                        // This { begins a block on a command
                        parser->command_start = true;
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    } else {
                        // This { begins a hash literal
                        lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);
                    }

                    parser->enclosure_nesting++;
                    parser->brace_nesting++;
                    yp_do_loop_stack_push(parser, false);

                    LEX(type);
                }

                // }
                case '}':
                    parser->enclosure_nesting--;
                    yp_do_loop_stack_pop(parser);

                    if ((parser->lex_modes.current->mode == YP_LEX_EMBEXPR) && (parser->brace_nesting == 0)) {
                        lex_mode_pop(parser);
                        LEX(YP_TOKEN_EMBEXPR_END);
                    }

                    parser->brace_nesting--;
                    lex_state_set(parser, YP_LEX_STATE_END);
                    LEX(YP_TOKEN_BRACE_RIGHT);

                // * ** **= *=
                case '*': {
                    if (match(parser, '*')) {
                        if (match(parser, '=')) {
                            lex_state_set(parser, YP_LEX_STATE_BEG);
                            LEX(YP_TOKEN_STAR_STAR_EQUAL);
                        }

                        yp_token_type_t type = YP_TOKEN_STAR_STAR;

                        if (lex_state_spcarg_p(parser, space_seen) || lex_state_beg_p(parser)) {
                            type = YP_TOKEN_USTAR_STAR;
                        }

                        if (lex_state_operator_p(parser)) {
                            lex_state_set(parser, YP_LEX_STATE_ARG);
                        } else {
                            lex_state_set(parser, YP_LEX_STATE_BEG);
                        }

                        LEX(type);
                    }

                    if (match(parser, '=')) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_STAR_EQUAL);
                    }

                    yp_token_type_t type = YP_TOKEN_STAR;

                    if (lex_state_spcarg_p(parser, space_seen)) {
                        yp_diagnostic_list_append(&parser->warning_list, parser->current.start, parser->current.end, YP_WARN_AMBIGUOUS_PREFIX_STAR);
                        type = YP_TOKEN_USTAR;
                    } else if (lex_state_beg_p(parser)) {
                        type = YP_TOKEN_USTAR;
                    }

                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }

                    LEX(type);
                }

                // ! != !~ !@
                case '!':
                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                        if (match(parser, '@')) {
                            LEX(YP_TOKEN_BANG);
                        }
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }

                    if (match(parser, '=')) {
                        LEX(YP_TOKEN_BANG_EQUAL);
                    }

                    if (match(parser, '~')) {
                        LEX(YP_TOKEN_BANG_TILDE);
                    }

                    LEX(YP_TOKEN_BANG);

                // = => =~ == === =begin
                case '=':
                    if (current_token_starts_line(parser) && memcmp(peek_string(parser, 5), "begin", 5) == 0 && yp_char_is_whitespace(peek_offset(parser, 5))) {
                        yp_token_type_t type = lex_embdoc(parser);

                        if (type == YP_TOKEN_EOF) {
                            LEX(type);
                        }

                        goto lex_next_token;
                    }

                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }

                    if (match(parser, '>')) {
                        LEX(YP_TOKEN_EQUAL_GREATER);
                    }

                    if (match(parser, '~')) {
                        LEX(YP_TOKEN_EQUAL_TILDE);
                    }

                    if (match(parser, '=')) {
                        LEX(match(parser, '=') ? YP_TOKEN_EQUAL_EQUAL_EQUAL : YP_TOKEN_EQUAL_EQUAL);
                    }

                    LEX(YP_TOKEN_EQUAL);

                // < << <<= <= <=>
                case '<':
                    if (match(parser, '<')) {
                        if (
                            !lex_state_p(parser, YP_LEX_STATE_DOT | YP_LEX_STATE_CLASS) &&
                            !lex_state_end_p(parser) &&
                            (!lex_state_p(parser, YP_LEX_STATE_ARG_ANY) || lex_state_p(parser, YP_LEX_STATE_LABELED) || space_seen)
                        ) {
                            const uint8_t *end = parser->current.end;

                            yp_heredoc_quote_t quote = YP_HEREDOC_QUOTE_NONE;
                            yp_heredoc_indent_t indent = YP_HEREDOC_INDENT_NONE;

                            if (match(parser, '-')) {
                                indent = YP_HEREDOC_INDENT_DASH;
                            }
                            else if (match(parser, '~')) {
                                indent = YP_HEREDOC_INDENT_TILDE;
                            }

                            if (match(parser, '`')) {
                                quote = YP_HEREDOC_QUOTE_BACKTICK;
                            }
                            else if (match(parser, '"')) {
                                quote = YP_HEREDOC_QUOTE_DOUBLE;
                            }
                            else if (match(parser, '\'')) {
                                quote = YP_HEREDOC_QUOTE_SINGLE;
                            }

                            const uint8_t *ident_start = parser->current.end;
                            size_t width = 0;

                            if (parser->current.end >= parser->end) {
                                parser->current.end = end;
                            } else if (quote == YP_HEREDOC_QUOTE_NONE && (width = char_is_identifier(parser, parser->current.end)) == 0) {
                                parser->current.end = end;
                            } else {
                                if (quote == YP_HEREDOC_QUOTE_NONE) {
                                    parser->current.end += width;

                                    while ((parser->current.end < parser->end) && (width = char_is_identifier(parser, parser->current.end))) {
                                        parser->current.end += width;
                                    }
                                } else {
                                    // If we have quotes, then we're going to go until we find the
                                    // end quote.
                                    while ((parser->current.end < parser->end) && quote != (yp_heredoc_quote_t) (*parser->current.end)) {
                                        parser->current.end++;
                                    }
                                }

                                size_t ident_length = (size_t) (parser->current.end - ident_start);
                                if (quote != YP_HEREDOC_QUOTE_NONE && !match(parser, (uint8_t) quote)) {
                                    // TODO: handle unterminated heredoc
                                }

                                lex_mode_push(parser, (yp_lex_mode_t) {
                                    .mode = YP_LEX_HEREDOC,
                                    .as.heredoc = {
                                        .ident_start = ident_start,
                                        .ident_length = ident_length,
                                        .next_start = parser->current.end,
                                        .quote = quote,
                                        .indent = indent
                                    }
                                });

                                if (parser->heredoc_end == NULL) {
                                    const uint8_t *body_start = next_newline(parser->current.end, parser->end - parser->current.end);

                                    if (body_start == NULL) {
                                        // If there is no newline after the heredoc identifier, then
                                        // this is not a valid heredoc declaration. In this case we
                                        // will add an error, but we will still return a heredoc
                                        // start.
                                        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_EMBDOC_TERM);
                                        body_start = parser->end;
                                    } else {
                                        // Otherwise, we want to indicate that the body of the
                                        // heredoc starts on the character after the next newline.
                                        yp_newline_list_append(&parser->newline_list, body_start);
                                        body_start++;
                                    }

                                    parser->next_start = body_start;
                                } else {
                                    parser->next_start = parser->heredoc_end;
                                }

                                LEX(YP_TOKEN_HEREDOC_START);
                            }
                        }

                        if (match(parser, '=')) {
                            lex_state_set(parser, YP_LEX_STATE_BEG);
                            LEX(YP_TOKEN_LESS_LESS_EQUAL);
                        }

                        if (lex_state_operator_p(parser)) {
                            lex_state_set(parser, YP_LEX_STATE_ARG);
                        } else {
                            if (lex_state_p(parser, YP_LEX_STATE_CLASS)) parser->command_start = true;
                            lex_state_set(parser, YP_LEX_STATE_BEG);
                        }

                        LEX(YP_TOKEN_LESS_LESS);
                    }

                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        if (lex_state_p(parser, YP_LEX_STATE_CLASS)) parser->command_start = true;
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }

                    if (match(parser, '=')) {
                        if (match(parser, '>')) {
                            LEX(YP_TOKEN_LESS_EQUAL_GREATER);
                        }

                        LEX(YP_TOKEN_LESS_EQUAL);
                    }

                    LEX(YP_TOKEN_LESS);

                // > >> >>= >=
                case '>':
                    if (match(parser, '>')) {
                        if (lex_state_operator_p(parser)) {
                            lex_state_set(parser, YP_LEX_STATE_ARG);
                        } else {
                            lex_state_set(parser, YP_LEX_STATE_BEG);
                        }
                        LEX(match(parser, '=') ? YP_TOKEN_GREATER_GREATER_EQUAL : YP_TOKEN_GREATER_GREATER);
                    }

                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }

                    LEX(match(parser, '=') ? YP_TOKEN_GREATER_EQUAL : YP_TOKEN_GREATER);

                // double-quoted string literal
                case '"': {
                    bool label_allowed = (lex_state_p(parser, YP_LEX_STATE_LABEL | YP_LEX_STATE_ENDFN) && !previous_command_start) || lex_state_arg_p(parser);
                    lex_mode_push_string(parser, true, label_allowed, '\0', '"');
                    LEX(YP_TOKEN_STRING_BEGIN);
                }

                // xstring literal
                case '`': {
                    if (lex_state_p(parser, YP_LEX_STATE_FNAME)) {
                        lex_state_set(parser, YP_LEX_STATE_ENDFN);
                        LEX(YP_TOKEN_BACKTICK);
                    }

                    if (lex_state_p(parser, YP_LEX_STATE_DOT)) {
                        if (previous_command_start) {
                            lex_state_set(parser, YP_LEX_STATE_CMDARG);
                        } else {
                            lex_state_set(parser, YP_LEX_STATE_ARG);
                        }

                        LEX(YP_TOKEN_BACKTICK);
                    }

                    lex_mode_push_string(parser, true, false, '\0', '`');
                    LEX(YP_TOKEN_BACKTICK);
                }

                // single-quoted string literal
                case '\'': {
                    bool label_allowed = (lex_state_p(parser, YP_LEX_STATE_LABEL | YP_LEX_STATE_ENDFN) && !previous_command_start) || lex_state_arg_p(parser);
                    lex_mode_push_string(parser, false, label_allowed, '\0', '\'');
                    LEX(YP_TOKEN_STRING_BEGIN);
                }

                // ? character literal
                case '?':
                    LEX(lex_question_mark(parser));

                // & && &&= &=
                case '&': {
                    if (match(parser, '&')) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);

                        if (match(parser, '=')) {
                            LEX(YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL);
                        }

                        LEX(YP_TOKEN_AMPERSAND_AMPERSAND);
                    }

                    if (match(parser, '=')) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_AMPERSAND_EQUAL);
                    }

                    if (match(parser, '.')) {
                        lex_state_set(parser, YP_LEX_STATE_DOT);
                        LEX(YP_TOKEN_AMPERSAND_DOT);
                    }

                    yp_token_type_t type = YP_TOKEN_AMPERSAND;
                    if (lex_state_spcarg_p(parser, space_seen) || lex_state_beg_p(parser)) {
                        type = YP_TOKEN_UAMPERSAND;
                    }

                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }

                    LEX(type);
                }

                // | || ||= |=
                case '|':
                    if (match(parser, '|')) {
                        if (match(parser, '=')) {
                            lex_state_set(parser, YP_LEX_STATE_BEG);
                            LEX(YP_TOKEN_PIPE_PIPE_EQUAL);
                        }

                        if (lex_state_p(parser, YP_LEX_STATE_BEG)) {
                            parser->current.end--;
                            LEX(YP_TOKEN_PIPE);
                        }

                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_PIPE_PIPE);
                    }

                    if (match(parser, '=')) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_PIPE_EQUAL);
                    }

                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);
                    }

                    LEX(YP_TOKEN_PIPE);

                // + += +@
                case '+': {
                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);

                        if (match(parser, '@')) {
                            LEX(YP_TOKEN_UPLUS);
                        }

                        LEX(YP_TOKEN_PLUS);
                    }

                    if (match(parser, '=')) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_PLUS_EQUAL);
                    }

                    bool spcarg = lex_state_spcarg_p(parser, space_seen);
                    if (spcarg) {
                        yp_diagnostic_list_append(
                            &parser->warning_list,
                            parser->current.start,
                            parser->current.end,
                            YP_WARN_AMBIGUOUS_FIRST_ARGUMENT_PLUS
                        );
                    }

                    if (lex_state_beg_p(parser) || spcarg) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);

                        if (yp_char_is_decimal_digit(peek(parser))) {
                            parser->current.end++;
                            yp_token_type_t type = lex_numeric(parser);
                            lex_state_set(parser, YP_LEX_STATE_END);
                            LEX(type);
                        }

                        LEX(YP_TOKEN_UPLUS);
                    }

                    lex_state_set(parser, YP_LEX_STATE_BEG);
                    LEX(YP_TOKEN_PLUS);
                }

                // - -= -@
                case '-': {
                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);

                        if (match(parser, '@')) {
                            LEX(YP_TOKEN_UMINUS);
                        }

                        LEX(YP_TOKEN_MINUS);
                    }

                    if (match(parser, '=')) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_MINUS_EQUAL);
                    }

                    if (match(parser, '>')) {
                        lex_state_set(parser, YP_LEX_STATE_ENDFN);
                        LEX(YP_TOKEN_MINUS_GREATER);
                    }

                    bool spcarg = lex_state_spcarg_p(parser, space_seen);
                    if (spcarg) {
                        yp_diagnostic_list_append(
                            &parser->warning_list,
                            parser->current.start,
                            parser->current.end,
                            YP_WARN_AMBIGUOUS_FIRST_ARGUMENT_MINUS
                        );
                    }

                    if (lex_state_beg_p(parser) || spcarg) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(yp_char_is_decimal_digit(peek(parser)) ? YP_TOKEN_UMINUS_NUM : YP_TOKEN_UMINUS);
                    }

                    lex_state_set(parser, YP_LEX_STATE_BEG);
                    LEX(YP_TOKEN_MINUS);
                }

                // . .. ...
                case '.': {
                    bool beg_p = lex_state_beg_p(parser);

                    if (match(parser, '.')) {
                        if (match(parser, '.')) {
                            // If we're _not_ inside a range within default parameters
                            if (
                                !context_p(parser, YP_CONTEXT_DEFAULT_PARAMS) &&
                                context_p(parser, YP_CONTEXT_DEF_PARAMS)
                            ) {
                                if (lex_state_p(parser, YP_LEX_STATE_END)) {
                                    lex_state_set(parser, YP_LEX_STATE_BEG);
                                } else {
                                    lex_state_set(parser, YP_LEX_STATE_ENDARG);
                                }
                                LEX(YP_TOKEN_UDOT_DOT_DOT);
                            }

                            lex_state_set(parser, YP_LEX_STATE_BEG);
                            LEX(beg_p ? YP_TOKEN_UDOT_DOT_DOT : YP_TOKEN_DOT_DOT_DOT);
                        }

                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(beg_p ? YP_TOKEN_UDOT_DOT : YP_TOKEN_DOT_DOT);
                    }

                    lex_state_set(parser, YP_LEX_STATE_DOT);
                    LEX(YP_TOKEN_DOT);
                }

                // integer
                case '0':
                case '1':
                case '2':
                case '3':
                case '4':
                case '5':
                case '6':
                case '7':
                case '8':
                case '9': {
                    yp_token_type_t type = lex_numeric(parser);
                    lex_state_set(parser, YP_LEX_STATE_END);
                    LEX(type);
                }

                // :: symbol
                case ':':
                    if (match(parser, ':')) {
                        if (lex_state_beg_p(parser) || lex_state_p(parser, YP_LEX_STATE_CLASS) || (lex_state_p(parser, YP_LEX_STATE_ARG_ANY) && space_seen)) {
                            lex_state_set(parser, YP_LEX_STATE_BEG);
                            LEX(YP_TOKEN_UCOLON_COLON);
                        }

                        lex_state_set(parser, YP_LEX_STATE_DOT);
                        LEX(YP_TOKEN_COLON_COLON);
                    }

                    if (lex_state_end_p(parser) || yp_char_is_whitespace(peek(parser)) || peek(parser) == '#') {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_COLON);
                    }

                    if (peek(parser) == '"' || peek(parser) == '\'') {
                        lex_mode_push_string(parser, peek(parser) == '"', false, '\0', *parser->current.end);
                        parser->current.end++;
                    }

                    lex_state_set(parser, YP_LEX_STATE_FNAME);
                    LEX(YP_TOKEN_SYMBOL_BEGIN);

                // / /=
                case '/':
                    if (lex_state_beg_p(parser)) {
                        lex_mode_push_regexp(parser, '\0', '/');
                        LEX(YP_TOKEN_REGEXP_BEGIN);
                    }

                    if (match(parser, '=')) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_SLASH_EQUAL);
                    }

                    if (lex_state_spcarg_p(parser, space_seen)) {
                        yp_diagnostic_list_append(&parser->warning_list, parser->current.start, parser->current.end, YP_WARN_AMBIGUOUS_SLASH);
                        lex_mode_push_regexp(parser, '\0', '/');
                        LEX(YP_TOKEN_REGEXP_BEGIN);
                    }

                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }

                    LEX(YP_TOKEN_SLASH);

                // ^ ^=
                case '^':
                    if (lex_state_operator_p(parser)) {
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }
                    LEX(match(parser, '=') ? YP_TOKEN_CARET_EQUAL : YP_TOKEN_CARET);

                // ~ ~@
                case '~':
                    if (lex_state_operator_p(parser)) {
                        (void) match(parser, '@');
                        lex_state_set(parser, YP_LEX_STATE_ARG);
                    } else {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                    }

                    LEX(YP_TOKEN_TILDE);

                // % %= %i %I %q %Q %w %W
                case '%': {
                    // If there is no subsequent character then we have an invalid token. We're
                    // going to say it's the percent operator because we don't want to move into the
                    // string lex mode unnecessarily.
                    if ((lex_state_beg_p(parser) || lex_state_arg_p(parser)) && (parser->current.end >= parser->end)) {
                        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_PERCENT);
                        LEX(YP_TOKEN_PERCENT);
                    }

                    if (!lex_state_beg_p(parser) && match(parser, '=')) {
                        lex_state_set(parser, YP_LEX_STATE_BEG);
                        LEX(YP_TOKEN_PERCENT_EQUAL);
                    }
                    else if(
                        lex_state_beg_p(parser) ||
                        (lex_state_p(parser, YP_LEX_STATE_FITEM) && (peek(parser) == 's')) ||
                        lex_state_spcarg_p(parser, space_seen)
                    ) {
                        if (!parser->encoding.alnum_char(parser->current.end, parser->end - parser->current.end)) {
                            lex_mode_push_string(parser, true, false, lex_mode_incrementor(*parser->current.end), lex_mode_terminator(*parser->current.end));

                            size_t eol_length = match_eol(parser);
                            if (eol_length) {
                                parser->current.end += eol_length;
                                yp_newline_list_append(&parser->newline_list, parser->current.end - 1);
                            } else {
                                parser->current.end++;
                            }

                            if (parser->current.end < parser->end) {
                                LEX(YP_TOKEN_STRING_BEGIN);
                            }
                        }

                        switch (peek(parser)) {
                            case 'i': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_list(parser, false, *parser->current.end++);
                                }

                                LEX(YP_TOKEN_PERCENT_LOWER_I);
                            }
                            case 'I': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_list(parser, true, *parser->current.end++);
                                }

                                LEX(YP_TOKEN_PERCENT_UPPER_I);
                            }
                            case 'r': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_regexp(parser, lex_mode_incrementor(*parser->current.end), lex_mode_terminator(*parser->current.end));
                                    yp_newline_list_check_append(&parser->newline_list, parser->current.end);
                                    parser->current.end++;
                                }

                                LEX(YP_TOKEN_REGEXP_BEGIN);
                            }
                            case 'q': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_string(parser, false, false, lex_mode_incrementor(*parser->current.end), lex_mode_terminator(*parser->current.end));
                                    yp_newline_list_check_append(&parser->newline_list, parser->current.end);
                                    parser->current.end++;
                                }

                                LEX(YP_TOKEN_STRING_BEGIN);
                            }
                            case 'Q': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_string(parser, true, false, lex_mode_incrementor(*parser->current.end), lex_mode_terminator(*parser->current.end));
                                    yp_newline_list_check_append(&parser->newline_list, parser->current.end);
                                    parser->current.end++;
                                }

                                LEX(YP_TOKEN_STRING_BEGIN);
                            }
                            case 's': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_string(parser, false, false, lex_mode_incrementor(*parser->current.end), lex_mode_terminator(*parser->current.end));
                                    lex_state_set(parser, YP_LEX_STATE_FNAME | YP_LEX_STATE_FITEM);
                                    parser->current.end++;
                                }

                                LEX(YP_TOKEN_SYMBOL_BEGIN);
                            }
                            case 'w': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_list(parser, false, *parser->current.end++);
                                }

                                LEX(YP_TOKEN_PERCENT_LOWER_W);
                            }
                            case 'W': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_list(parser, true, *parser->current.end++);
                                }

                                LEX(YP_TOKEN_PERCENT_UPPER_W);
                            }
                            case 'x': {
                                parser->current.end++;

                                if (parser->current.end < parser->end) {
                                    lex_mode_push_string(parser, true, false, lex_mode_incrementor(*parser->current.end), lex_mode_terminator(*parser->current.end));
                                    parser->current.end++;
                                }

                                LEX(YP_TOKEN_PERCENT_LOWER_X);
                            }
                            default:
                                // If we get to this point, then we have a % that is completely
                                // unparseable. In this case we'll just drop it from the parser
                                // and skip past it and hope that the next token is something
                                // that we can parse.
                                yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_PERCENT);
                                goto lex_next_token;
                        }
                    }

                    lex_state_set(parser, lex_state_operator_p(parser) ? YP_LEX_STATE_ARG : YP_LEX_STATE_BEG);
                    LEX(YP_TOKEN_PERCENT);
                }

                // global variable
                case '$': {
                    yp_token_type_t type = lex_global_variable(parser);

                    // If we're lexing an embedded variable, then we need to pop back into
                    // the parent lex context.
                    if (parser->lex_modes.current->mode == YP_LEX_EMBVAR) {
                        lex_mode_pop(parser);
                    }

                    lex_state_set(parser, YP_LEX_STATE_END);
                    LEX(type);
                }

                // instance variable, class variable
                case '@':
                    lex_state_set(parser, parser->lex_state & YP_LEX_STATE_FNAME ? YP_LEX_STATE_ENDFN : YP_LEX_STATE_END);
                    LEX(lex_at_variable(parser));

                default: {
                    if (*parser->current.start != '_') {
                        size_t width = char_is_identifier_start(parser, parser->current.start);

                        // If this isn't the beginning of an identifier, then it's an invalid
                        // token as we've exhausted all of the other options. We'll skip past
                        // it and return the next token.
                        if (!width) {
                            yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_INVALID_TOKEN);
                            goto lex_next_token;
                        }

                        parser->current.end = parser->current.start + width;
                    }

                    yp_token_type_t type = lex_identifier(parser, previous_command_start);

                    // If we've hit a __END__ and it was at the start of the line or the
                    // start of the file and it is followed by either a \n or a \r\n, then
                    // this is the last token of the file.
                    if (
                        ((parser->current.end - parser->current.start) == 7) &&
                        current_token_starts_line(parser) &&
                        (memcmp(parser->current.start, "__END__", 7) == 0) &&
                        (parser->current.end == parser->end || match_eol(parser))
                        )
                    {
                        parser->current.end = parser->end;
                        parser->current.type = YP_TOKEN___END__;
                        parser_lex_callback(parser);

                        yp_comment_t *comment = parser_comment(parser, YP_COMMENT___END__);
                        yp_list_append(&parser->comment_list, (yp_list_node_t *) comment);

                        LEX(YP_TOKEN_EOF);
                    }

                    yp_lex_state_t last_state = parser->lex_state;

                    if (type == YP_TOKEN_IDENTIFIER || type == YP_TOKEN_CONSTANT) {
                        if (lex_state_p(parser, YP_LEX_STATE_BEG_ANY | YP_LEX_STATE_ARG_ANY | YP_LEX_STATE_DOT)) {
                            if (previous_command_start) {
                                lex_state_set(parser, YP_LEX_STATE_CMDARG);
                            } else {
                                lex_state_set(parser, YP_LEX_STATE_ARG);
                            }
                        } else if (parser->lex_state == YP_LEX_STATE_FNAME) {
                            lex_state_set(parser, YP_LEX_STATE_ENDFN);
                        } else {
                            lex_state_set(parser, YP_LEX_STATE_END);
                        }
                    }

                    if (
                        !(last_state & (YP_LEX_STATE_DOT | YP_LEX_STATE_FNAME)) &&
                        (type == YP_TOKEN_IDENTIFIER) &&
                        ((yp_parser_local_depth(parser, &parser->current) != -1) ||
                         token_is_numbered_parameter(parser->current.start, parser->current.end))
                    ) {
                        lex_state_set(parser, YP_LEX_STATE_END | YP_LEX_STATE_LABEL);
                    }

                    LEX(type);
                }
            }
        }
        case YP_LEX_LIST:
            if (parser->next_start != NULL) {
                parser->current.end = parser->next_start;
                parser->next_start = NULL;
            }

            // First we'll set the beginning of the token.
            parser->current.start = parser->current.end;

            // If there's any whitespace at the start of the list, then we're
            // going to trim it off the beginning and create a new token.
            size_t whitespace;

            if (parser->heredoc_end) {
                whitespace = yp_strspn_inline_whitespace(parser->current.end, parser->end - parser->current.end);
                if (peek_offset(parser, (ptrdiff_t)whitespace) == '\n') {
                    whitespace += 1;
                }
            } else {
                whitespace = yp_strspn_whitespace_newlines(parser->current.end, parser->end - parser->current.end, &parser->newline_list);
            }

            if (whitespace > 0) {
                parser->current.end += whitespace;
                if (peek_offset(parser, -1) == '\n') {
                    // mutates next_start
                    parser_flush_heredoc_end(parser);
                }
                LEX(YP_TOKEN_WORDS_SEP);
            }

            // We'll check if we're at the end of the file. If we are, then we
            // need to return the EOF token.
            if (parser->current.end >= parser->end) {
                LEX(YP_TOKEN_EOF);
            }

            // Here we'll get a list of the places where strpbrk should break,
            // and then find the first one.
            yp_lex_mode_t *lex_mode = parser->lex_modes.current;
            const uint8_t *breakpoints = lex_mode->as.list.breakpoints;
            const uint8_t *breakpoint = yp_strpbrk(parser, parser->current.end, breakpoints, parser->end - parser->current.end);

            while (breakpoint != NULL) {
                // If we hit a null byte, skip directly past it.
                if (*breakpoint == '\0') {
                    breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                    continue;
                }

                // If we hit whitespace, then we must have received content by
                // now, so we can return an element of the list.
                if (yp_char_is_whitespace(*breakpoint)) {
                    parser->current.end = breakpoint;
                    LEX(YP_TOKEN_STRING_CONTENT);
                }

                //If we hit the terminator, we need to check which token to
                // return.
                if (*breakpoint == lex_mode->as.list.terminator) {
                    // If this terminator doesn't actually close the list, then
                    // we need to continue on past it.
                    if (lex_mode->as.list.nesting > 0) {
                        breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                        lex_mode->as.list.nesting--;
                        continue;
                    }

                    // If we've hit the terminator and we've already skipped
                    // past content, then we can return a list node.
                    if (breakpoint > parser->current.start) {
                        parser->current.end = breakpoint;
                        LEX(YP_TOKEN_STRING_CONTENT);
                    }

                    // Otherwise, switch back to the default state and return
                    // the end of the list.
                    parser->current.end = breakpoint + 1;
                    lex_mode_pop(parser);
                    lex_state_set(parser, YP_LEX_STATE_END);
                    LEX(YP_TOKEN_STRING_END);
                }

                // If we hit escapes, then we need to treat the next token
                // literally. In this case we'll skip past the next character
                // and find the next breakpoint.
                if (*breakpoint == '\\') {
                    yp_unescape_type_t unescape_type = lex_mode->as.list.interpolation ? YP_UNESCAPE_ALL : YP_UNESCAPE_MINIMAL;
                    size_t difference = yp_unescape_calculate_difference(parser, breakpoint, unescape_type, false);
                    if (difference == 0) {
                        // we're at the end of the file
                        breakpoint = NULL;
                        continue;
                    }

                    // If the result is an escaped newline ...
                    if (breakpoint[difference - 1] == '\n') {
                        if (parser->heredoc_end) {
                            // ... if we are on the same line as a heredoc, flush the heredoc and
                            // continue parsing after heredoc_end.
                            parser->current.end = breakpoint + difference;
                            parser_flush_heredoc_end(parser);
                            LEX(YP_TOKEN_STRING_CONTENT);
                        } else {
                            // ... else track the newline.
                            yp_newline_list_append(&parser->newline_list, breakpoint + difference - 1);
                        }
                    }

                    breakpoint = yp_strpbrk(parser, breakpoint + difference, breakpoints, parser->end - (breakpoint + difference));
                    continue;
                }

                // If we hit a #, then we will attempt to lex interpolation.
                if (*breakpoint == '#') {
                    yp_token_type_t type = lex_interpolation(parser, breakpoint);
                    if (type != YP_TOKEN_NOT_PROVIDED) {
                        LEX(type);
                    }

                    // If we haven't returned at this point then we had something
                    // that looked like an interpolated class or instance variable
                    // like "#@" but wasn't actually. In this case we'll just skip
                    // to the next breakpoint.
                    breakpoint = yp_strpbrk(parser, parser->current.end, breakpoints, parser->end - parser->current.end);
                    continue;
                }

                // If we've hit the incrementor, then we need to skip past it
                // and find the next breakpoint.
                assert(*breakpoint == lex_mode->as.list.incrementor);
                breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                lex_mode->as.list.nesting++;
                continue;
            }

            // If we were unable to find a breakpoint, then this token hits the end of
            // the file.
            LEX(YP_TOKEN_EOF);

        case YP_LEX_REGEXP: {
            // First, we'll set to start of this token to be the current end.
            if (parser->next_start == NULL) {
                parser->current.start = parser->current.end;
            } else {
                parser->current.start = parser->next_start;
                parser->current.end = parser->next_start;
                parser->next_start = NULL;
            }

            // We'll check if we're at the end of the file. If we are, then we need to
            // return the EOF token.
            if (parser->current.end >= parser->end) {
                LEX(YP_TOKEN_EOF);
            }

            // Get a reference to the current mode.
            yp_lex_mode_t *lex_mode = parser->lex_modes.current;

            // These are the places where we need to split up the content of the
            // regular expression. We'll use strpbrk to find the first of these
            // characters.
            const uint8_t *breakpoints = lex_mode->as.regexp.breakpoints;
            const uint8_t *breakpoint = yp_strpbrk(parser, parser->current.end, breakpoints, parser->end - parser->current.end);

            while (breakpoint != NULL) {
                // If we hit a null byte, skip directly past it.
                if (*breakpoint == '\0') {
                    breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                    continue;
                }

                // If we've hit a newline, then we need to track that in the
                // list of newlines.
                if (*breakpoint == '\n') {
                    // For the special case of a newline-terminated regular expression, we will pass
                    // through this branch twice -- once with YP_TOKEN_REGEXP_BEGIN and then again
                    // with YP_TOKEN_STRING_CONTENT. Let's avoid tracking the newline twice, by
                    // tracking it only in the REGEXP_BEGIN case.
                    if (
                        !(lex_mode->as.regexp.terminator == '\n' && parser->current.type != YP_TOKEN_REGEXP_BEGIN)
                        && parser->heredoc_end == NULL
                    ) {
                        yp_newline_list_append(&parser->newline_list, breakpoint);
                    }

                    if (lex_mode->as.regexp.terminator != '\n') {
                        // If the terminator is not a newline, then we can set
                        // the next breakpoint and continue.
                        breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                        continue;
                    }
                }

                // If we hit the terminator, we need to determine what kind of
                // token to return.
                if (*breakpoint == lex_mode->as.regexp.terminator) {
                    if (lex_mode->as.regexp.nesting > 0) {
                        breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                        lex_mode->as.regexp.nesting--;
                        continue;
                    }

                    // Here we've hit the terminator. If we have already consumed
                    // content then we need to return that content as string content
                    // first.
                    if (breakpoint > parser->current.start) {
                        parser->current.end = breakpoint;
                        LEX(YP_TOKEN_STRING_CONTENT);
                    }

                    // Since we've hit the terminator of the regular expression, we now
                    // need to parse the options.
                    parser->current.end = breakpoint + 1;
                    parser->current.end += yp_strspn_regexp_option(parser->current.end, parser->end - parser->current.end);

                    lex_mode_pop(parser);
                    lex_state_set(parser, YP_LEX_STATE_END);
                    LEX(YP_TOKEN_REGEXP_END);
                }

                // If we hit escapes, then we need to treat the next token
                // literally. In this case we'll skip past the next character
                // and find the next breakpoint.
                if (*breakpoint == '\\') {
                    size_t difference = yp_unescape_calculate_difference(parser, breakpoint, YP_UNESCAPE_ALL, false);
                    if (difference == 0) {
                        // we're at the end of the file
                        breakpoint = NULL;
                        continue;
                    }

                    // If the result is an escaped newline ...
                    if (breakpoint[difference - 1] == '\n') {
                        if (parser->heredoc_end) {
                            // ... if we are on the same line as a heredoc, flush the heredoc and
                            // continue parsing after heredoc_end.
                            parser->current.end = breakpoint + difference;
                            parser_flush_heredoc_end(parser);
                            LEX(YP_TOKEN_STRING_CONTENT);
                        } else {
                            // ... else track the newline.
                            yp_newline_list_append(&parser->newline_list, breakpoint + difference - 1);
                        }
                    }

                    breakpoint = yp_strpbrk(parser, breakpoint + difference, breakpoints, parser->end - (breakpoint + difference));
                    continue;
                }

                // If we hit a #, then we will attempt to lex interpolation.
                if (*breakpoint == '#') {
                    yp_token_type_t type = lex_interpolation(parser, breakpoint);
                    if (type != YP_TOKEN_NOT_PROVIDED) {
                        LEX(type);
                    }

                    // If we haven't returned at this point then we had
                    // something that looked like an interpolated class or
                    // instance variable like "#@" but wasn't actually. In this
                    // case we'll just skip to the next breakpoint.
                    breakpoint = yp_strpbrk(parser, parser->current.end, breakpoints, parser->end - parser->current.end);
                    continue;
                }

                // If we've hit the incrementor, then we need to skip past it
                // and find the next breakpoint.
                assert(*breakpoint == lex_mode->as.regexp.incrementor);
                breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                lex_mode->as.regexp.nesting++;
                continue;
            }

            // At this point, the breakpoint is NULL which means we were unable to
            // find anything before the end of the file.
            LEX(YP_TOKEN_EOF);
        }
        case YP_LEX_STRING: {
            // First, we'll set to start of this token to be the current end.
            if (parser->next_start == NULL) {
                parser->current.start = parser->current.end;
            } else {
                parser->current.start = parser->next_start;
                parser->current.end = parser->next_start;
                parser->next_start = NULL;
            }

            // We'll check if we're at the end of the file. If we are, then we need to
            // return the EOF token.
            if (parser->current.end >= parser->end) {
                LEX(YP_TOKEN_EOF);
            }

            // These are the places where we need to split up the content of the
            // string. We'll use strpbrk to find the first of these characters.
            const uint8_t *breakpoints = parser->lex_modes.current->as.string.breakpoints;
            const uint8_t *breakpoint = yp_strpbrk(parser, parser->current.end, breakpoints, parser->end - parser->current.end);

            while (breakpoint != NULL) {
                // If we hit the incrementor, then we'll increment then nesting and
                // continue lexing.
                if (
                    parser->lex_modes.current->as.string.incrementor != '\0' &&
                    *breakpoint == parser->lex_modes.current->as.string.incrementor
                ) {
                    parser->lex_modes.current->as.string.nesting++;
                    breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                    continue;
                }

                // Note that we have to check the terminator here first because we could
                // potentially be parsing a % string that has a # character as the
                // terminator.
                if (*breakpoint == parser->lex_modes.current->as.string.terminator) {
                    // If this terminator doesn't actually close the string, then we need
                    // to continue on past it.
                    if (parser->lex_modes.current->as.string.nesting > 0) {
                        breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                        parser->lex_modes.current->as.string.nesting--;
                        continue;
                    }

                    // Here we've hit the terminator. If we have already consumed content
                    // then we need to return that content as string content first.
                    if (breakpoint > parser->current.start) {
                        parser->current.end = breakpoint;
                        LEX(YP_TOKEN_STRING_CONTENT);
                    }

                    // Otherwise we need to switch back to the parent lex mode and
                    // return the end of the string.
                    size_t eol_length = match_eol_at(parser, breakpoint);
                    if (eol_length) {
                        parser->current.end = breakpoint + eol_length;
                        yp_newline_list_append(&parser->newline_list, parser->current.end - 1);
                    } else {
                        parser->current.end = breakpoint + 1;
                    }

                    if (
                        parser->lex_modes.current->as.string.label_allowed &&
                        (peek(parser) == ':') &&
                        (peek_offset(parser, 1) != ':')
                    ) {
                        parser->current.end++;
                        lex_state_set(parser, YP_LEX_STATE_ARG | YP_LEX_STATE_LABELED);
                        lex_mode_pop(parser);
                        LEX(YP_TOKEN_LABEL_END);
                    }

                    lex_state_set(parser, YP_LEX_STATE_END);
                    lex_mode_pop(parser);
                    LEX(YP_TOKEN_STRING_END);
                }

                // When we hit a newline, we need to flush any potential heredocs. Note
                // that this has to happen after we check for the terminator in case the
                // terminator is a newline character.
                if (*breakpoint == '\n') {
                    if (parser->heredoc_end == NULL) {
                        yp_newline_list_append(&parser->newline_list, breakpoint);
                        breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                        continue;
                    } else {
                        parser->current.end = breakpoint + 1;
                        parser_flush_heredoc_end(parser);
                        LEX(YP_TOKEN_STRING_CONTENT);
                    }
                }

                switch (*breakpoint) {
                    case '\0':
                        // Skip directly past the null character.
                        breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                        break;
                    case '\\': {
                        // If we hit escapes, then we need to treat the next token
                        // literally. In this case we'll skip past the next character and
                        // find the next breakpoint.
                        yp_unescape_type_t unescape_type = parser->lex_modes.current->as.string.interpolation ? YP_UNESCAPE_ALL : YP_UNESCAPE_MINIMAL;
                        size_t difference = yp_unescape_calculate_difference(parser, breakpoint, unescape_type, false);
                        if (difference == 0) {
                            // we're at the end of the file
                            breakpoint = NULL;
                            break;
                        }

                        // If the result is an escaped newline ...
                        if (breakpoint[difference - 1] == '\n') {
                            if (parser->heredoc_end) {
                                // ... if we are on the same line as a heredoc, flush the heredoc and
                                // continue parsing after heredoc_end.
                                parser->current.end = breakpoint + difference;
                                parser_flush_heredoc_end(parser);
                                LEX(YP_TOKEN_STRING_CONTENT);
                            } else {
                                // ... else track the newline.
                                yp_newline_list_append(&parser->newline_list, breakpoint + difference - 1);
                            }
                        }

                        breakpoint = yp_strpbrk(parser, breakpoint + difference, breakpoints, parser->end - (breakpoint + difference));
                        break;
                    }
                    case '#': {
                        yp_token_type_t type = lex_interpolation(parser, breakpoint);
                        if (type != YP_TOKEN_NOT_PROVIDED) {
                            LEX(type);
                        }

                        // If we haven't returned at this point then we had something that
                        // looked like an interpolated class or instance variable like "#@"
                        // but wasn't actually. In this case we'll just skip to the next
                        // breakpoint.
                        breakpoint = yp_strpbrk(parser, parser->current.end, breakpoints, parser->end - parser->current.end);
                        break;
                    }
                    default:
                        assert(false && "unreachable");
                }
            }

            // If we've hit the end of the string, then this is an unterminated
            // string. In that case we'll return the EOF token.
            parser->current.end = parser->end;
            LEX(YP_TOKEN_EOF);
        }
        case YP_LEX_HEREDOC: {
            // First, we'll set to start of this token.
            if (parser->next_start == NULL) {
                parser->current.start = parser->current.end;
            } else {
                parser->current.start = parser->next_start;
                parser->current.end = parser->next_start;
                parser->heredoc_end = NULL;
                parser->next_start = NULL;
            }

            // We'll check if we're at the end of the file. If we are, then we need to
            // return the EOF token.
            if (parser->current.end >= parser->end) {
                LEX(YP_TOKEN_EOF);
            }

            // Now let's grab the information about the identifier off of the current
            // lex mode.
            const uint8_t *ident_start = parser->lex_modes.current->as.heredoc.ident_start;
            size_t ident_length = parser->lex_modes.current->as.heredoc.ident_length;

            // If we are immediately following a newline and we have hit the
            // terminator, then we need to return the ending of the heredoc.
            if (current_token_starts_line(parser)) {
                const uint8_t *start = parser->current.start;
                if (parser->lex_modes.current->as.heredoc.indent != YP_HEREDOC_INDENT_NONE) {
                    start += yp_strspn_inline_whitespace(start, parser->end - start);
                }

                if ((start + ident_length <= parser->end) && (memcmp(start, ident_start, ident_length) == 0)) {
                    bool matched = true;
                    bool at_end = false;

                    size_t eol_length = match_eol_at(parser, start + ident_length);
                    if (eol_length) {
                        parser->current.end = start + ident_length + eol_length;
                        yp_newline_list_append(&parser->newline_list, parser->current.end - 1);
                    } else if (parser->end == (start + ident_length)) {
                        parser->current.end = start + ident_length;
                        at_end = true;
                    } else {
                        matched = false;
                    }

                    if (matched) {
                        if (*parser->lex_modes.current->as.heredoc.next_start == '\\') {
                            parser->next_start = NULL;
                        } else {
                            parser->next_start = parser->lex_modes.current->as.heredoc.next_start;
                            parser->heredoc_end = parser->current.end;
                        }

                        lex_mode_pop(parser);
                        if (!at_end) {
                            lex_state_set(parser, YP_LEX_STATE_END);
                        }
                        LEX(YP_TOKEN_HEREDOC_END);
                    }
                }
            }

            // Otherwise we'll be parsing string content. These are the places where
            // we need to split up the content of the heredoc. We'll use strpbrk to
            // find the first of these characters.
            uint8_t breakpoints[] = "\n\\#";

            yp_heredoc_quote_t quote = parser->lex_modes.current->as.heredoc.quote;
            if (quote == YP_HEREDOC_QUOTE_SINGLE) {
                breakpoints[2] = '\0';
            }

            const uint8_t *breakpoint = yp_strpbrk(parser, parser->current.end, breakpoints, parser->end - parser->current.end);

            while (breakpoint != NULL) {
                switch (*breakpoint) {
                    case '\0':
                        // Skip directly past the null character.
                        breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                        break;
                    case '\n': {
                        if (parser->heredoc_end != NULL && (parser->heredoc_end > breakpoint)) {
                            parser_flush_heredoc_end(parser);
                            parser->current.end = breakpoint + 1;
                            LEX(YP_TOKEN_STRING_CONTENT);
                        }

                        yp_newline_list_append(&parser->newline_list, breakpoint);

                        const uint8_t *start = breakpoint + 1;
                        if (parser->lex_modes.current->as.heredoc.indent != YP_HEREDOC_INDENT_NONE) {
                            start += yp_strspn_inline_whitespace(start, parser->end - start);
                        }

                        // If we have hit a newline that is followed by a valid terminator,
                        // then we need to return the content of the heredoc here as string
                        // content. Then, the next time a token is lexed, it will match
                        // again and return the end of the heredoc.
                        if (
                            (start + ident_length <= parser->end) &&
                            (memcmp(start, ident_start, ident_length) == 0)
                        ) {
                            // Heredoc terminators must be followed by a newline, CRLF, or EOF to be valid.
                            if (
                                start + ident_length == parser->end ||
                                match_eol_at(parser, start + ident_length)
                            ) {
                                parser->current.end = breakpoint + 1;
                                LEX(YP_TOKEN_STRING_CONTENT);
                            }
                        }

                        // Otherwise we hit a newline and it wasn't followed by a
                        // terminator, so we can continue parsing.
                        breakpoint = yp_strpbrk(parser, breakpoint + 1, breakpoints, parser->end - (breakpoint + 1));
                        break;
                    }
                    case '\\': {
                        // If we hit an escape, then we need to skip past
                        // however many characters the escape takes up. However
                        // it's important that if \n or \r\n are escaped that we
                        // stop looping before the newline and not after the
                        // newline so that we can still potentially find the
                        // terminator of the heredoc.
                        size_t eol_length = match_eol_at(parser, breakpoint + 1);
                        if (eol_length) {
                            breakpoint += eol_length;
                        } else {
                            yp_unescape_type_t unescape_type = (quote == YP_HEREDOC_QUOTE_SINGLE) ? YP_UNESCAPE_MINIMAL : YP_UNESCAPE_ALL;
                            size_t difference = yp_unescape_calculate_difference(parser, breakpoint, unescape_type, false);
                            if (difference == 0) {
                                // we're at the end of the file
                                breakpoint = NULL;
                                break;
                            }

                            yp_newline_list_check_append(&parser->newline_list, breakpoint + difference - 1);

                            breakpoint = yp_strpbrk(parser, breakpoint + difference, breakpoints, parser->end - (breakpoint + difference));
                        }

                        break;
                    }
                    case '#': {
                        yp_token_type_t type = lex_interpolation(parser, breakpoint);
                        if (type != YP_TOKEN_NOT_PROVIDED) {
                            LEX(type);
                        }

                        // If we haven't returned at this point then we had something
                        // that looked like an interpolated class or instance variable
                        // like "#@" but wasn't actually. In this case we'll just skip
                        // to the next breakpoint.
                        breakpoint = yp_strpbrk(parser, parser->current.end, breakpoints, parser->end - parser->current.end);
                        break;
                    }
                    default:
                        assert(false && "unreachable");
                }
            }

            // If we've hit the end of the string, then this is an unterminated
            // heredoc. In that case we'll return the EOF token.
            parser->current.end = parser->end;
            LEX(YP_TOKEN_EOF);
        }
    }

    assert(false && "unreachable");
}

#undef LEX

/******************************************************************************/
/* Parse functions                                                            */
/******************************************************************************/

// When we are parsing certain content, we need to unescape the content to
// provide to the consumers of the parser. The following functions accept a range
// of characters from the source and unescapes into the provided type.
//
// We have functions for unescaping regular expression nodes, string nodes,
// symbol nodes, and xstring nodes
static yp_regular_expression_node_t *
yp_regular_expression_node_create_and_unescape(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *content, const yp_token_t *closing, yp_unescape_type_t unescape_type) {
    yp_regular_expression_node_t *node = yp_regular_expression_node_create(parser, opening, content, closing);

    assert((content->end - content->start) >= 0);
    yp_string_shared_init(&node->unescaped, content->start, content->end);

    yp_unescape_manipulate_string(parser, &node->unescaped, unescape_type);
    return node;
}

static yp_symbol_node_t *
yp_symbol_node_create_and_unescape(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *content, const yp_token_t *closing, yp_unescape_type_t unescape_type) {
    yp_symbol_node_t *node = yp_symbol_node_create(parser, opening, content, closing);

    assert((content->end - content->start) >= 0);
    yp_string_shared_init(&node->unescaped, content->start, content->end);

    yp_unescape_manipulate_string(parser, &node->unescaped, unescape_type);
    return node;
}

static yp_string_node_t *
yp_char_literal_node_create_and_unescape(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *content, const yp_token_t *closing, yp_unescape_type_t unescape_type) {
    yp_string_node_t *node = yp_string_node_create(parser, opening, content, closing);

    assert((content->end - content->start) >= 0);
    yp_string_shared_init(&node->unescaped, content->start, content->end);

    yp_unescape_manipulate_char_literal(parser, &node->unescaped, unescape_type);
    return node;
}

static yp_string_node_t *
yp_string_node_create_and_unescape(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *content, const yp_token_t *closing, yp_unescape_type_t unescape_type) {
    yp_string_node_t *node = yp_string_node_create(parser, opening, content, closing);

    assert((content->end - content->start) >= 0);
    yp_string_shared_init(&node->unescaped, content->start, content->end);

    yp_unescape_manipulate_string(parser, &node->unescaped, unescape_type);
    return node;
}

static yp_x_string_node_t *
yp_xstring_node_create_and_unescape(yp_parser_t *parser, const yp_token_t *opening, const yp_token_t *content, const yp_token_t *closing) {
    yp_x_string_node_t *node = yp_xstring_node_create(parser, opening, content, closing);

    assert((content->end - content->start) >= 0);
    yp_string_shared_init(&node->unescaped, content->start, content->end);

    yp_unescape_manipulate_string(parser, &node->unescaped, YP_UNESCAPE_ALL);
    return node;
}

// Returns true if the current token is of the specified type.
static inline bool
match_type_p(yp_parser_t *parser, yp_token_type_t type) {
    return parser->current.type == type;
}

// Returns true if the current token is of any of the specified types.
static bool
match_any_type_p(yp_parser_t *parser, size_t count, ...) {
    va_list types;
    va_start(types, count);

    for (size_t index = 0; index < count; index++) {
        if (match_type_p(parser, va_arg(types, yp_token_type_t))) {
            va_end(types);
            return true;
        }
    }

    va_end(types);
    return false;
}

// These are the various precedence rules. Because we are using a Pratt parser,
// they are named binding power to represent the manner in which nodes are bound
// together in the stack.
//
// We increment by 2 because we want to leave room for the infix operators to
// specify their associativity by adding or subtracting one.
typedef enum {
    YP_BINDING_POWER_UNSET =            0, // used to indicate this token cannot be used as an infix operator
    YP_BINDING_POWER_STATEMENT =        2,
    YP_BINDING_POWER_MODIFIER =         4, // if unless until while in
    YP_BINDING_POWER_MODIFIER_RESCUE =  6, // rescue
    YP_BINDING_POWER_COMPOSITION =      8, // and or
    YP_BINDING_POWER_NOT =             10, // not
    YP_BINDING_POWER_MATCH =           12, // =>
    YP_BINDING_POWER_DEFINED =         14, // defined?
    YP_BINDING_POWER_ASSIGNMENT =      16, // = += -= *= /= %= &= |= ^= &&= ||= <<= >>= **=
    YP_BINDING_POWER_TERNARY =         18, // ?:
    YP_BINDING_POWER_RANGE =           20, // .. ...
    YP_BINDING_POWER_LOGICAL_OR =      22, // ||
    YP_BINDING_POWER_LOGICAL_AND =     24, // &&
    YP_BINDING_POWER_EQUALITY =        26, // <=> == === != =~ !~
    YP_BINDING_POWER_COMPARISON =      28, // > >= < <=
    YP_BINDING_POWER_BITWISE_OR =      30, // | ^
    YP_BINDING_POWER_BITWISE_AND =     32, // &
    YP_BINDING_POWER_SHIFT =           34, // << >>
    YP_BINDING_POWER_TERM =            36, // + -
    YP_BINDING_POWER_FACTOR =          38, // * / %
    YP_BINDING_POWER_UMINUS =          40, // -@
    YP_BINDING_POWER_EXPONENT =        42, // **
    YP_BINDING_POWER_UNARY =           44, // ! ~ +@
    YP_BINDING_POWER_INDEX =           46, // [] []=
    YP_BINDING_POWER_CALL =            48, // :: .
    YP_BINDING_POWER_MAX =             50
} yp_binding_power_t;

// This struct represents a set of binding powers used for a given token. They
// are combined in this way to make it easier to represent associativity.
typedef struct {
    yp_binding_power_t left;
    yp_binding_power_t right;
    bool binary;
} yp_binding_powers_t;

#define BINDING_POWER_ASSIGNMENT { YP_BINDING_POWER_UNARY, YP_BINDING_POWER_ASSIGNMENT, true }
#define LEFT_ASSOCIATIVE(precedence) { precedence, precedence + 1, true }
#define RIGHT_ASSOCIATIVE(precedence) { precedence, precedence, true }
#define RIGHT_ASSOCIATIVE_UNARY(precedence) { precedence, precedence, false }

yp_binding_powers_t yp_binding_powers[YP_TOKEN_MAXIMUM] = {
    // if unless until while in rescue
    [YP_TOKEN_KEYWORD_IF_MODIFIER] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_MODIFIER),
    [YP_TOKEN_KEYWORD_UNLESS_MODIFIER] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_MODIFIER),
    [YP_TOKEN_KEYWORD_UNTIL_MODIFIER] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_MODIFIER),
    [YP_TOKEN_KEYWORD_WHILE_MODIFIER] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_MODIFIER),
    [YP_TOKEN_KEYWORD_IN] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_MODIFIER),

    // rescue modifier
    [YP_TOKEN_KEYWORD_RESCUE_MODIFIER] = {
        YP_BINDING_POWER_ASSIGNMENT,
        YP_BINDING_POWER_MODIFIER_RESCUE + 1,
        true
    },

    // and or
    [YP_TOKEN_KEYWORD_AND] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_COMPOSITION),
    [YP_TOKEN_KEYWORD_OR] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_COMPOSITION),

    // =>
    [YP_TOKEN_EQUAL_GREATER] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_MATCH),

    // &&= &= ^= = >>= <<= -= %= |= += /= *= **=
    [YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_AMPERSAND_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_CARET_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_GREATER_GREATER_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_LESS_LESS_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_MINUS_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_PERCENT_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_PIPE_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_PIPE_PIPE_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_PLUS_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_SLASH_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_STAR_EQUAL] = BINDING_POWER_ASSIGNMENT,
    [YP_TOKEN_STAR_STAR_EQUAL] = BINDING_POWER_ASSIGNMENT,

    // ?:
    [YP_TOKEN_QUESTION_MARK] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_TERNARY),

    // .. ...
    [YP_TOKEN_DOT_DOT] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_RANGE),
    [YP_TOKEN_DOT_DOT_DOT] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_RANGE),

    // ||
    [YP_TOKEN_PIPE_PIPE] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_LOGICAL_OR),

    // &&
    [YP_TOKEN_AMPERSAND_AMPERSAND] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_LOGICAL_AND),

    // != !~ == === =~ <=>
    [YP_TOKEN_BANG_EQUAL] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_EQUALITY),
    [YP_TOKEN_BANG_TILDE] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_EQUALITY),
    [YP_TOKEN_EQUAL_EQUAL] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_EQUALITY),
    [YP_TOKEN_EQUAL_EQUAL_EQUAL] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_EQUALITY),
    [YP_TOKEN_EQUAL_TILDE] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_EQUALITY),
    [YP_TOKEN_LESS_EQUAL_GREATER] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_EQUALITY),

    // > >= < <=
    [YP_TOKEN_GREATER] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_COMPARISON),
    [YP_TOKEN_GREATER_EQUAL] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_COMPARISON),
    [YP_TOKEN_LESS] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_COMPARISON),
    [YP_TOKEN_LESS_EQUAL] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_COMPARISON),

    // ^ |
    [YP_TOKEN_CARET] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_BITWISE_OR),
    [YP_TOKEN_PIPE] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_BITWISE_OR),

    // &
    [YP_TOKEN_AMPERSAND] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_BITWISE_AND),

    // >> <<
    [YP_TOKEN_GREATER_GREATER] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_SHIFT),
    [YP_TOKEN_LESS_LESS] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_SHIFT),

    // - +
    [YP_TOKEN_MINUS] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_TERM),
    [YP_TOKEN_PLUS] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_TERM),

    // % / *
    [YP_TOKEN_PERCENT] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_FACTOR),
    [YP_TOKEN_SLASH] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_FACTOR),
    [YP_TOKEN_STAR] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_FACTOR),
    [YP_TOKEN_USTAR] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_FACTOR),

    // -@
    [YP_TOKEN_UMINUS] = RIGHT_ASSOCIATIVE_UNARY(YP_BINDING_POWER_UMINUS),
    [YP_TOKEN_UMINUS_NUM] = RIGHT_ASSOCIATIVE_UNARY(YP_BINDING_POWER_UMINUS),

    // **
    [YP_TOKEN_STAR_STAR] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_EXPONENT),
    [YP_TOKEN_USTAR_STAR] = RIGHT_ASSOCIATIVE_UNARY(YP_BINDING_POWER_UNARY),

    // ! ~ +@
    [YP_TOKEN_BANG] = RIGHT_ASSOCIATIVE_UNARY(YP_BINDING_POWER_UNARY),
    [YP_TOKEN_TILDE] = RIGHT_ASSOCIATIVE_UNARY(YP_BINDING_POWER_UNARY),
    [YP_TOKEN_UPLUS] = RIGHT_ASSOCIATIVE_UNARY(YP_BINDING_POWER_UNARY),

    // [
    [YP_TOKEN_BRACKET_LEFT] = LEFT_ASSOCIATIVE(YP_BINDING_POWER_INDEX),

    // :: . &.
    [YP_TOKEN_COLON_COLON] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_CALL),
    [YP_TOKEN_DOT] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_CALL),
    [YP_TOKEN_AMPERSAND_DOT] = RIGHT_ASSOCIATIVE(YP_BINDING_POWER_CALL)
};

#undef BINDING_POWER_ASSIGNMENT
#undef LEFT_ASSOCIATIVE
#undef RIGHT_ASSOCIATIVE
#undef RIGHT_ASSOCIATIVE_UNARY

// If the current token is of the specified type, lex forward by one token and
// return true. Otherwise, return false. For example:
//
//     if (accept(parser, YP_TOKEN_COLON)) { ... }
//
static bool
accept(yp_parser_t *parser, yp_token_type_t type) {
    if (match_type_p(parser, type)) {
        parser_lex(parser);
        return true;
    }
    return false;
}

// If the current token is of any of the specified types, lex forward by one
// token and return true. Otherwise, return false. For example:
//
//     if (accept_any(parser, 2, YP_TOKEN_COLON, YP_TOKEN_SEMICOLON)) { ... }
//
static bool
accept_any(yp_parser_t *parser, size_t count, ...) {
    va_list types;
    va_start(types, count);

    for (size_t index = 0; index < count; index++) {
        if (match_type_p(parser, va_arg(types, yp_token_type_t))) {
            parser_lex(parser);
            va_end(types);
            return true;
        }
    }

    va_end(types);
    return false;
}

// This function indicates that the parser expects a token in a specific
// position. For example, if you're parsing a BEGIN block, you know that a { is
// expected immediately after the keyword. In that case you would call this
// function to indicate that that token should be found.
//
// If we didn't find the token that we were expecting, then we're going to add
// an error to the parser's list of errors (to indicate that the tree is not
// valid) and create an artificial token instead. This allows us to recover from
// the fact that the token isn't present and continue parsing.
static void
expect(yp_parser_t *parser, yp_token_type_t type, yp_diagnostic_id_t diag_id) {
    if (accept(parser, type)) return;

    yp_diagnostic_list_append(&parser->error_list, parser->previous.end, parser->previous.end, diag_id);

    parser->previous =
        (yp_token_t) { .type = YP_TOKEN_MISSING, .start = parser->previous.end, .end = parser->previous.end };
}

static void
expect_any(yp_parser_t *parser, yp_diagnostic_id_t diag_id, size_t count, ...) {
    va_list types;
    va_start(types, count);

    for (size_t index = 0; index < count; index++) {
        if (accept(parser, va_arg(types, yp_token_type_t))) {
            va_end(types);
            return;
        }
    }

    va_end(types);

    yp_diagnostic_list_append(&parser->error_list, parser->previous.end, parser->previous.end, diag_id);
    parser->previous =
        (yp_token_t) { .type = YP_TOKEN_MISSING, .start = parser->previous.end, .end = parser->previous.end };
}

static yp_node_t *
parse_expression(yp_parser_t *parser, yp_binding_power_t binding_power, yp_diagnostic_id_t diag_id);

// This function controls whether or not we will attempt to parse an expression
// beginning at the subsequent token. It is used when we are in a context where
// an expression is optional.
//
// For example, looking at a range object when we've already lexed the operator,
// we need to know if we should attempt to parse an expression on the right.
//
// For another example, if we've parsed an identifier or a method call and we do
// not have parentheses, then the next token may be the start of an argument or
// it may not.
//
// CRuby parsers that are generated would resolve this by using a lookahead and
// potentially backtracking. We attempt to do this by just looking at the next
// token and making a decision based on that. I am not sure if this is going to
// work in all cases, it may need to be refactored later. But it appears to work
// for now.
static inline bool
token_begins_expression_p(yp_token_type_t type) {
    switch (type) {
        case YP_TOKEN_EQUAL_GREATER:
        case YP_TOKEN_KEYWORD_IN:
            // We need to special case this because it is a binary operator that
            // should not be marked as beginning an expression.
            return false;
        case YP_TOKEN_BRACE_RIGHT:
        case YP_TOKEN_BRACKET_RIGHT:
        case YP_TOKEN_COLON:
        case YP_TOKEN_COMMA:
        case YP_TOKEN_EMBEXPR_END:
        case YP_TOKEN_EOF:
        case YP_TOKEN_LAMBDA_BEGIN:
        case YP_TOKEN_KEYWORD_DO:
        case YP_TOKEN_KEYWORD_DO_LOOP:
        case YP_TOKEN_KEYWORD_END:
        case YP_TOKEN_KEYWORD_ELSE:
        case YP_TOKEN_KEYWORD_ELSIF:
        case YP_TOKEN_KEYWORD_ENSURE:
        case YP_TOKEN_KEYWORD_THEN:
        case YP_TOKEN_KEYWORD_RESCUE:
        case YP_TOKEN_KEYWORD_WHEN:
        case YP_TOKEN_NEWLINE:
        case YP_TOKEN_PARENTHESIS_RIGHT:
        case YP_TOKEN_SEMICOLON:
            // The reason we need this short-circuit is because we're using the
            // binding powers table to tell us if the subsequent token could
            // potentially be the start of an expression . If there _is_ a binding
            // power for one of these tokens, then we should remove it from this list
            // and let it be handled by the default case below.
            assert(yp_binding_powers[type].left == YP_BINDING_POWER_UNSET);
            return false;
        case YP_TOKEN_UAMPERSAND:
            // This is a special case because this unary operator cannot appear
            // as a general operator, it only appears in certain circumstances.
            return false;
        case YP_TOKEN_UCOLON_COLON:
        case YP_TOKEN_UMINUS:
        case YP_TOKEN_UMINUS_NUM:
        case YP_TOKEN_UPLUS:
        case YP_TOKEN_BANG:
        case YP_TOKEN_TILDE:
        case YP_TOKEN_UDOT_DOT:
        case YP_TOKEN_UDOT_DOT_DOT:
            // These unary tokens actually do have binding power associated with them
            // so that we can correctly place them into the precedence order. But we
            // want them to be marked as beginning an expression, so we need to
            // special case them here.
            return true;
        default:
            return yp_binding_powers[type].left == YP_BINDING_POWER_UNSET;
    }
}

// Parse an expression with the given binding power that may be optionally
// prefixed by the * operator.
static yp_node_t *
parse_starred_expression(yp_parser_t *parser, yp_binding_power_t binding_power, yp_diagnostic_id_t diag_id) {
    if (accept(parser, YP_TOKEN_USTAR)) {
        yp_token_t operator = parser->previous;
        yp_node_t *expression = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_STAR);
        return (yp_node_t *) yp_splat_node_create(parser, &operator, expression);
    }

    return parse_expression(parser, binding_power, diag_id);
}

// Convert the given node into a valid target node.
static yp_node_t *
parse_target(yp_parser_t *parser, yp_node_t *target) {
    switch (YP_NODE_TYPE(target)) {
        case YP_MISSING_NODE:
            return target;
        case YP_CLASS_VARIABLE_READ_NODE:
            assert(sizeof(yp_class_variable_target_node_t) == sizeof(yp_class_variable_read_node_t));
            target->type = YP_CLASS_VARIABLE_TARGET_NODE;
            return target;
        case YP_CONSTANT_PATH_NODE:
            assert(sizeof(yp_constant_path_target_node_t) == sizeof(yp_constant_path_node_t));
            target->type = YP_CONSTANT_PATH_TARGET_NODE;
            return target;
        case YP_CONSTANT_READ_NODE:
            assert(sizeof(yp_constant_target_node_t) == sizeof(yp_constant_read_node_t));
            target->type = YP_CONSTANT_TARGET_NODE;
            return target;
        case YP_BACK_REFERENCE_READ_NODE:
            assert(sizeof(yp_global_variable_target_node_t) == sizeof(yp_back_reference_read_node_t));
            /* fallthrough */
        case YP_NUMBERED_REFERENCE_READ_NODE:
            assert(sizeof(yp_global_variable_target_node_t) == sizeof(yp_numbered_reference_read_node_t));
            yp_diagnostic_list_append(&parser->error_list, target->location.start, target->location.end, YP_ERR_WRITE_TARGET_READONLY);
            /* fallthrough */
        case YP_GLOBAL_VARIABLE_READ_NODE:
            assert(sizeof(yp_global_variable_target_node_t) == sizeof(yp_global_variable_read_node_t));
            target->type = YP_GLOBAL_VARIABLE_TARGET_NODE;
            return target;
        case YP_LOCAL_VARIABLE_READ_NODE:
            assert(sizeof(yp_local_variable_target_node_t) == sizeof(yp_local_variable_read_node_t));
            target->type = YP_LOCAL_VARIABLE_TARGET_NODE;
            return target;
        case YP_INSTANCE_VARIABLE_READ_NODE:
            assert(sizeof(yp_instance_variable_target_node_t) == sizeof(yp_instance_variable_read_node_t));
            target->type = YP_INSTANCE_VARIABLE_TARGET_NODE;
            return target;
        case YP_MULTI_TARGET_NODE:
            return target;
        case YP_SPLAT_NODE: {
            yp_splat_node_t *splat = (yp_splat_node_t *) target;

            if (splat->expression != NULL) {
                splat->expression = parse_target(parser, splat->expression);
            }

            yp_multi_target_node_t *multi_target = yp_multi_target_node_create(parser);
            yp_multi_target_node_targets_append(multi_target, (yp_node_t *) splat);

            return (yp_node_t *) multi_target;
        }
        case YP_CALL_NODE: {
            yp_call_node_t *call = (yp_call_node_t *) target;

            // If we have no arguments to the call node and we need this to be a
            // target then this is either a method call or a local variable write.
            if (
                (call->opening_loc.start == NULL) &&
                (call->arguments == NULL) &&
                (call->block == NULL)
            ) {
                if (call->receiver == NULL) {
                    // When we get here, we have a local variable write, because it
                    // was previously marked as a method call but now we have an =.
                    // This looks like:
                    //
                    //     foo = 1
                    //
                    // When it was parsed in the prefix position, foo was seen as a
                    // method call with no receiver and no arguments. Now we have an
                    // =, so we know it's a local variable write.
                    const yp_location_t message = call->message_loc;

                    yp_parser_local_add_location(parser, message.start, message.end);
                    yp_node_destroy(parser, target);

                    const yp_token_t name = { .type = YP_TOKEN_IDENTIFIER, .start = message.start, .end = message.end };
                    target = (yp_node_t *) yp_local_variable_read_node_create(parser, &name, 0);

                    assert(sizeof(yp_local_variable_target_node_t) == sizeof(yp_local_variable_read_node_t));
                    target->type = YP_LOCAL_VARIABLE_TARGET_NODE;

                    if (token_is_numbered_parameter(message.start, message.end)) {
                        yp_diagnostic_list_append(&parser->error_list, message.start, message.end, YP_ERR_PARAMETER_NUMBERED_RESERVED);
                    }

                    return target;
                }

                // The method name needs to change. If we previously had foo, we now
                // need foo=. In this case we'll allocate a new owned string, copy
                // the previous method name in, and append an =.
                size_t length = yp_string_length(&call->name);

                uint8_t *name = calloc(length + 1, sizeof(uint8_t));
                if (name == NULL) return NULL;

                memcpy(name, yp_string_source(&call->name), length);
                name[length] = '=';

                // Now switch the name to the new string.
                yp_string_free(&call->name);
                yp_string_owned_init(&call->name, name, length + 1);

                return target;
            }

            // If there is no call operator and the message is "[]" then this is
            // an aref expression, and we can transform it into an aset
            // expression.
            if (
                (call->call_operator_loc.start == NULL) &&
                (call->message_loc.start[0] == '[') &&
                (call->message_loc.end[-1] == ']') &&
                (call->block == NULL)
            ) {
                // Free the previous name and replace it with "[]=".
                yp_string_free(&call->name);
                yp_string_constant_init(&call->name, "[]=", 3);
                return target;
            }
        }
        /* fallthrough */
        default:
            // In this case we have a node that we don't know how to convert
            // into a target. We need to treat it as an error. For now, we'll
            // mark it as an error and just skip right past it.
            yp_diagnostic_list_append(&parser->error_list, target->location.start, target->location.end, YP_ERR_WRITE_TARGET_UNEXPECTED);
            return target;
    }
}

// Convert the given node into a valid write node.
static yp_node_t *
parse_write(yp_parser_t *parser, yp_node_t *target, yp_token_t *operator, yp_node_t *value) {
    switch (YP_NODE_TYPE(target)) {
        case YP_MISSING_NODE:
            return target;
        case YP_CLASS_VARIABLE_READ_NODE: {
            yp_class_variable_write_node_t *node = yp_class_variable_write_node_create(parser, (yp_class_variable_read_node_t *) target, operator, value);
            yp_node_destroy(parser, target);
            return (yp_node_t *) node;
        }
        case YP_CONSTANT_PATH_NODE:
            return (yp_node_t *) yp_constant_path_write_node_create(parser, (yp_constant_path_node_t *) target, operator, value);
        case YP_CONSTANT_READ_NODE: {
            yp_constant_write_node_t *node = yp_constant_write_node_create(parser, (yp_constant_read_node_t *) target, operator, value);
            yp_node_destroy(parser, target);
            return (yp_node_t *) node;
        }
        case YP_BACK_REFERENCE_READ_NODE:
        case YP_NUMBERED_REFERENCE_READ_NODE:
            yp_diagnostic_list_append(&parser->error_list, target->location.start, target->location.end, YP_ERR_WRITE_TARGET_READONLY);
            /* fallthrough */
        case YP_GLOBAL_VARIABLE_READ_NODE: {
            yp_global_variable_write_node_t *node = yp_global_variable_write_node_create(parser, target, operator, value);
            yp_node_destroy(parser, target);
            return (yp_node_t *) node;
        }
        case YP_LOCAL_VARIABLE_READ_NODE: {
            yp_local_variable_read_node_t *local_read = (yp_local_variable_read_node_t *) target;

            yp_constant_id_t constant_id = local_read->name;
            uint32_t depth = local_read->depth;

            yp_location_t name_loc = target->location;
            yp_node_destroy(parser, target);

            return (yp_node_t *) yp_local_variable_write_node_create(parser, constant_id, depth, value, &name_loc, operator);
        }
        case YP_INSTANCE_VARIABLE_READ_NODE: {
            yp_node_t *write_node = (yp_node_t *) yp_instance_variable_write_node_create(parser, (yp_instance_variable_read_node_t *) target, operator, value);
            yp_node_destroy(parser, target);
            return write_node;
        }
        case YP_MULTI_TARGET_NODE:
            return (yp_node_t *) yp_multi_write_node_create(parser, (yp_multi_target_node_t *) target, operator, value);
        case YP_SPLAT_NODE: {
            yp_splat_node_t *splat = (yp_splat_node_t *) target;

            if (splat->expression != NULL) {
                splat->expression = parse_write(parser, splat->expression, operator, value);
            }

            yp_multi_target_node_t *multi_target = yp_multi_target_node_create(parser);
            yp_multi_target_node_targets_append(multi_target, (yp_node_t *) splat);

            return (yp_node_t *) yp_multi_write_node_create(parser, multi_target, operator, value);
        }
        case YP_CALL_NODE: {
            yp_call_node_t *call = (yp_call_node_t *) target;
            // If we have no arguments to the call node and we need this to be a
            // target then this is either a method call or a local variable write.
            if (
                (call->opening_loc.start == NULL) &&
                (call->arguments == NULL) &&
                (call->block == NULL)
            ) {
                if (call->receiver == NULL) {
                    // When we get here, we have a local variable write, because it
                    // was previously marked as a method call but now we have an =.
                    // This looks like:
                    //
                    //     foo = 1
                    //
                    // When it was parsed in the prefix position, foo was seen as a
                    // method call with no receiver and no arguments. Now we have an
                    // =, so we know it's a local variable write.
                    const yp_location_t message = call->message_loc;

                    yp_parser_local_add_location(parser, message.start, message.end);
                    yp_node_destroy(parser, target);

                    yp_constant_id_t constant_id = yp_parser_constant_id_location(parser, message.start, message.end);
                    target = (yp_node_t *) yp_local_variable_write_node_create(parser, constant_id, 0, value, &message, operator);

                    if (token_is_numbered_parameter(message.start, message.end)) {
                        yp_diagnostic_list_append(&parser->error_list, message.start, message.end, YP_ERR_PARAMETER_NUMBERED_RESERVED);
                    }

                    return target;
                }

                // When we get here, we have a method call, because it was
                // previously marked as a method call but now we have an =. This
                // looks like:
                //
                //     foo.bar = 1
                //
                // When it was parsed in the prefix position, foo.bar was seen as a
                // method call with no arguments. Now we have an =, so we know it's
                // a method call with an argument. In this case we will create the
                // arguments node, parse the argument, and add it to the list.
                yp_arguments_node_t *arguments = yp_arguments_node_create(parser);
                call->arguments = arguments;
                yp_arguments_node_arguments_append(arguments, value);
                target->location.end = arguments->base.location.end;

                // The method name needs to change. If we previously had foo, we now
                // need foo=. In this case we'll allocate a new owned string, copy
                // the previous method name in, and append an =.
                size_t length = yp_string_length(&call->name);

                uint8_t *name = calloc(length + 1, sizeof(uint8_t));
                if (name == NULL) return NULL;

                memcpy(name, yp_string_source(&call->name), length);
                name[length] = '=';

                // Now switch the name to the new string.
                yp_string_free(&call->name);
                yp_string_owned_init(&call->name, name, length + 1);

                return target;
            }

            // If there is no call operator and the message is "[]" then this is
            // an aref expression, and we can transform it into an aset
            // expression.
            if (
                (call->call_operator_loc.start == NULL) &&
                (call->message_loc.start[0] == '[') &&
                (call->message_loc.end[-1] == ']') &&
                (call->block == NULL)
            ) {
                if (call->arguments == NULL) {
                    call->arguments = yp_arguments_node_create(parser);
                }

                yp_arguments_node_arguments_append(call->arguments, value);
                target->location.end = value->location.end;

                // Free the previous name and replace it with "[]=".
                yp_string_free(&call->name);
                yp_string_constant_init(&call->name, "[]=", 3);
                return target;
            }

            // If there are arguments on the call node, then it can't be a method
            // call ending with = or a local variable write, so it must be a
            // syntax error. In this case we'll fall through to our default
            // handling. We need to free the value that we parsed because there
            // is no way for us to attach it to the tree at this point.
            yp_node_destroy(parser, value);
        }
        /* fallthrough */
        default:
            // In this case we have a node that we don't know how to convert into a
            // target. We need to treat it as an error. For now, we'll mark it as an
            // error and just skip right past it.
            yp_diagnostic_list_append(&parser->error_list, operator->start, operator->end, YP_ERR_EXPECT_EXPRESSION_AFTER_EQUAL);
            return target;
    }
}

// Parse a list of targets for assignment. This is used in the case of a for
// loop or a multi-assignment. For example, in the following code:
//
//     for foo, bar in baz
//         ^^^^^^^^
//
// The targets are `foo` and `bar`. This function will either return a single
// target node or a multi-target node.
static yp_node_t *
parse_targets(yp_parser_t *parser, yp_node_t *first_target, yp_binding_power_t binding_power) {
    yp_token_t operator = not_provided(parser);

    // The first_target parameter can be NULL in the case that we're parsing a
    // location that we know requires a multi write, as in the case of a for loop.
    // In this case we will set up the parsing loop slightly differently.
    if (first_target != NULL) {
        first_target = parse_target(parser, first_target);

        if (!match_type_p(parser, YP_TOKEN_COMMA)) {
            return first_target;
        }
    }

    yp_multi_target_node_t *result = yp_multi_target_node_create(parser);
    if (first_target != NULL) {
        yp_multi_target_node_targets_append(result, first_target);
    }

    bool has_splat = false;

    if (first_target == NULL || accept(parser, YP_TOKEN_COMMA)) {
        do {
            if (accept(parser, YP_TOKEN_USTAR)) {
                // Here we have a splat operator. It can have a name or be anonymous. It
                // can be the final target or be in the middle if there haven't been any
                // others yet.

                if (has_splat) {
                    yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_MULTI_ASSIGN_MULTI_SPLATS);
                }

                yp_token_t star_operator = parser->previous;
                yp_node_t *name = NULL;

                if (token_begins_expression_p(parser->current.type)) {
                    name = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_STAR);
                    name = parse_target(parser, name);
                }

                yp_node_t *splat = (yp_node_t *) yp_splat_node_create(parser, &star_operator, name);
                yp_multi_target_node_targets_append(result, splat);
                has_splat = true;
            } else if (accept(parser, YP_TOKEN_PARENTHESIS_LEFT)) {
                // Here we have a parenthesized list of targets. We'll recurse down into
                // the parentheses by calling parse_targets again and then finish out
                // the node when it returns.

                yp_token_t lparen = parser->previous;
                yp_node_t *first_child_target = parse_expression(parser, YP_BINDING_POWER_STATEMENT, YP_ERR_EXPECT_EXPRESSION_AFTER_LPAREN);
                yp_node_t *child_target = parse_targets(parser, first_child_target, YP_BINDING_POWER_STATEMENT);

                expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_EXPECT_RPAREN_AFTER_MULTI);
                yp_token_t rparen = parser->previous;

                if (YP_NODE_TYPE_P(child_target, YP_MULTI_TARGET_NODE) && first_target == NULL && result->targets.size == 0) {
                    yp_node_destroy(parser, (yp_node_t *) result);
                    result = (yp_multi_target_node_t *) child_target;
                    result->base.location.start = lparen.start;
                    result->base.location.end = rparen.end;
                    result->lparen_loc = YP_LOCATION_TOKEN_VALUE(&lparen);
                    result->rparen_loc = YP_LOCATION_TOKEN_VALUE(&rparen);
                } else {
                    yp_multi_target_node_t *target;

                    if (YP_NODE_TYPE_P(child_target, YP_MULTI_TARGET_NODE)) {
                        target = (yp_multi_target_node_t *) child_target;
                    } else {
                        target = yp_multi_target_node_create(parser);
                        yp_multi_target_node_targets_append(target, child_target);
                    }

                    target->base.location.start = lparen.start;
                    target->base.location.end = rparen.end;
                    target->lparen_loc = YP_LOCATION_TOKEN_VALUE(&lparen);
                    target->rparen_loc = YP_LOCATION_TOKEN_VALUE(&rparen);

                    yp_multi_target_node_targets_append(result, (yp_node_t *) target);
                }
            } else {
                if (!token_begins_expression_p(parser->current.type) && !match_type_p(parser, YP_TOKEN_USTAR)) {
                    if (first_target == NULL && result->targets.size == 0) {
                        // If we get here, then we weren't able to parse anything at all, so
                        // we need to return a missing node.
                        yp_node_destroy(parser, (yp_node_t *) result);
                        yp_diagnostic_list_append(&parser->error_list, operator.start, operator.end, YP_ERR_FOR_INDEX);
                        return (yp_node_t *) yp_missing_node_create(parser, operator.start, operator.end);
                    }

                    // If we get here, then we have a trailing , in a multi write node.
                    // We need to indicate this somehow in the tree, so we'll add an
                    // anonymous splat.
                    yp_node_t *splat = (yp_node_t *) yp_splat_node_create(parser, &parser->previous, NULL);
                    yp_multi_target_node_targets_append(result, splat);
                    return (yp_node_t *) result;
                }

                yp_node_t *target = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_COMMA);
                target = parse_target(parser, target);

                yp_multi_target_node_targets_append(result, target);
            }
        } while (accept(parser, YP_TOKEN_COMMA));
    }

    return (yp_node_t *) result;
}

// Parse a list of statements separated by newlines or semicolons.
static yp_statements_node_t *
parse_statements(yp_parser_t *parser, yp_context_t context) {
    // First, skip past any optional terminators that might be at the beginning of
    // the statements.
    while (accept_any(parser, 2, YP_TOKEN_SEMICOLON, YP_TOKEN_NEWLINE));

    // If we have a terminator, then we can just return NULL.
    if (context_terminator(context, &parser->current)) return NULL;

    yp_statements_node_t *statements = yp_statements_node_create(parser);

    // At this point we know we have at least one statement, and that it
    // immediately follows the current token.
    context_push(parser, context);

    while (true) {
        yp_node_t *node = parse_expression(parser, YP_BINDING_POWER_STATEMENT, YP_ERR_CANNOT_PARSE_EXPRESSION);
        yp_statements_node_body_append(statements, node);

        // If we're recovering from a syntax error, then we need to stop parsing the
        // statements now.
        if (parser->recovering) {
            // If this is the level of context where the recovery has happened, then
            // we can mark the parser as done recovering.
            if (context_terminator(context, &parser->current)) parser->recovering = false;
            break;
        }

        // If we have a terminator, then we will parse all consequtive terminators
        // and then continue parsing the statements list.
        if (accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) {
            // If we have a terminator, then we will continue parsing the statements
            // list.
            while (accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON));
            if (context_terminator(context, &parser->current)) break;

            // Now we can continue parsing the list of statements.
            continue;
        }

        // At this point we have a list of statements that are not terminated by a
        // newline or semicolon. At this point we need to check if we're at the end
        // of the statements list. If we are, then we should break out of the loop.
        if (context_terminator(context, &parser->current)) break;

        // At this point, we have a syntax error, because the statement was not
        // terminated by a newline or semicolon, and we're not at the end of the
        // statements list. Ideally we should scan forward to determine if we should
        // insert a missing terminator or break out of parsing the statements list
        // at this point.
        //
        // We don't have that yet, so instead we'll do a more naive approach. If we
        // were unable to parse an expression, then we will skip past this token and
        // continue parsing the statements list. Otherwise we'll add an error and
        // continue parsing the statements list.
        if (YP_NODE_TYPE_P(node, YP_MISSING_NODE)) {
            parser_lex(parser);

            while (accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON));
            if (context_terminator(context, &parser->current)) break;
        } else {
            expect(parser, YP_TOKEN_NEWLINE, YP_ERR_EXPECT_EOL_AFTER_STATEMENT);
        }
    }

    context_pop(parser);
    return statements;
}

// Parse all of the elements of a hash.
static void
parse_assocs(yp_parser_t *parser, yp_node_t *node) {
    assert(YP_NODE_TYPE_P(node, YP_HASH_NODE) || YP_NODE_TYPE_P(node, YP_KEYWORD_HASH_NODE));

    while (true) {
        yp_node_t *element;

        switch (parser->current.type) {
            case YP_TOKEN_USTAR_STAR: {
                parser_lex(parser);
                yp_token_t operator = parser->previous;
                yp_node_t *value = NULL;

                if (token_begins_expression_p(parser->current.type)) {
                    value = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_EXPECT_EXPRESSION_AFTER_SPLAT_HASH);
                } else if (yp_parser_local_depth(parser, &operator) == -1) {
                    yp_diagnostic_list_append(&parser->error_list, operator.start, operator.end, YP_ERR_EXPECT_EXPRESSION_AFTER_SPLAT_HASH);
                }

                element = (yp_node_t *) yp_assoc_splat_node_create(parser, value, &operator);
                break;
            }
            case YP_TOKEN_LABEL: {
                parser_lex(parser);

                yp_node_t *key = (yp_node_t *) yp_symbol_node_label_create(parser, &parser->previous);
                yp_token_t operator = not_provided(parser);
                yp_node_t *value = NULL;

                if (token_begins_expression_p(parser->current.type)) {
                    value = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_HASH_EXPRESSION_AFTER_LABEL);
                }

                element = (yp_node_t *) yp_assoc_node_create(parser, key, &operator, value);
                break;
            }
            default: {
                yp_node_t *key = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_HASH_KEY);
                yp_token_t operator;

                if (yp_symbol_node_label_p(key)) {
                    operator = not_provided(parser);
                } else {
                    expect(parser, YP_TOKEN_EQUAL_GREATER, YP_ERR_HASH_ROCKET);
                    operator = parser->previous;
                }

                yp_node_t *value = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_HASH_VALUE);
                element = (yp_node_t *) yp_assoc_node_create(parser, key, &operator, value);
                break;
            }
        }

        if (YP_NODE_TYPE_P(node, YP_HASH_NODE)) {
            yp_hash_node_elements_append((yp_hash_node_t *) node, element);
        } else {
            yp_keyword_hash_node_elements_append((yp_keyword_hash_node_t *) node, element);
        }

        // If there's no comma after the element, then we're done.
        if (!accept(parser, YP_TOKEN_COMMA)) return;

        // If the next element starts with a label or a **, then we know we have
        // another element in the hash, so we'll continue parsing.
        if (match_any_type_p(parser, 2, YP_TOKEN_USTAR_STAR, YP_TOKEN_LABEL)) continue;

        // Otherwise we need to check if the subsequent token begins an expression.
        // If it does, then we'll continue parsing.
        if (token_begins_expression_p(parser->current.type)) continue;

        // Otherwise by default we will exit out of this loop.
        return;
    }
}

// Parse a list of arguments.
static void
parse_arguments(yp_parser_t *parser, yp_arguments_t *arguments, bool accepts_forwarding, yp_token_type_t terminator) {
    yp_binding_power_t binding_power = yp_binding_powers[parser->current.type].left;

    // First we need to check if the next token is one that could be the start of
    // an argument. If it's not, then we can just return.
    if (
        match_any_type_p(parser, 2, terminator, YP_TOKEN_EOF) ||
        (binding_power != YP_BINDING_POWER_UNSET && binding_power < YP_BINDING_POWER_RANGE) ||
        context_terminator(parser->current_context->context, &parser->current)
    ) {
        return;
    }

    bool parsed_bare_hash = false;
    bool parsed_block_argument = false;

    while (!match_type_p(parser, YP_TOKEN_EOF)) {
        if (parsed_block_argument) {
            yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_ARGUMENT_AFTER_BLOCK);
        }

        yp_node_t *argument = NULL;

        switch (parser->current.type) {
            case YP_TOKEN_USTAR_STAR:
            case YP_TOKEN_LABEL: {
                if (parsed_bare_hash) {
                    yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_ARGUMENT_BARE_HASH);
                }

                yp_keyword_hash_node_t *hash = yp_keyword_hash_node_create(parser);
                argument = (yp_node_t *)hash;

                if (!match_any_type_p(parser, 7, terminator, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON, YP_TOKEN_EOF, YP_TOKEN_BRACE_RIGHT, YP_TOKEN_KEYWORD_DO, YP_TOKEN_PARENTHESIS_RIGHT)) {
                    parse_assocs(parser, (yp_node_t *) hash);
                }

                parsed_bare_hash = true;
                break;
            }
            case YP_TOKEN_UAMPERSAND: {
                parser_lex(parser);
                yp_token_t operator = parser->previous;
                yp_node_t *expression = NULL;

                if (token_begins_expression_p(parser->current.type)) {
                    expression = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_EXPECT_ARGUMENT);
                } else if (yp_parser_local_depth(parser, &operator) == -1) {
                    yp_diagnostic_list_append(&parser->error_list, operator.start, operator.end, YP_ERR_ARGUMENT_NO_FORWARDING_AMP);
                }

                argument = (yp_node_t *)yp_block_argument_node_create(parser, &operator, expression);
                parsed_block_argument = true;
                arguments->implicit_block = true;
                break;
            }
            case YP_TOKEN_USTAR: {
                parser_lex(parser);
                yp_token_t operator = parser->previous;

                if (match_any_type_p(parser, 2, YP_TOKEN_PARENTHESIS_RIGHT, YP_TOKEN_COMMA)) {
                    if (yp_parser_local_depth(parser, &parser->previous) == -1) {
                        yp_diagnostic_list_append(&parser->error_list, operator.start, operator.end, YP_ERR_ARGUMENT_NO_FORWARDING_STAR);
                    }

                    argument = (yp_node_t *) yp_splat_node_create(parser, &operator, NULL);
                } else {
                    yp_node_t *expression = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_EXPECT_EXPRESSION_AFTER_SPLAT);

                    if (parsed_bare_hash) {
                        yp_diagnostic_list_append(&parser->error_list, operator.start, expression->location.end, YP_ERR_ARGUMENT_SPLAT_AFTER_ASSOC_SPLAT);
                    }

                    argument = (yp_node_t *) yp_splat_node_create(parser, &operator, expression);
                }

                break;
            }
            case YP_TOKEN_UDOT_DOT_DOT: {
                if (accepts_forwarding) {
                    parser_lex(parser);

                    if (token_begins_expression_p(parser->current.type)) {
                        // If the token begins an expression then this ... was not actually
                        // argument forwarding but was instead a range.
                        yp_token_t operator = parser->previous;
                        yp_node_t *right = parse_expression(parser, YP_BINDING_POWER_RANGE, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                        argument = (yp_node_t *) yp_range_node_create(parser, NULL, &operator, right);
                    } else {
                        if (yp_parser_local_depth(parser, &parser->previous) == -1) {
                            yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_ARGUMENT_NO_FORWARDING_ELLIPSES);
                        }

                        argument = (yp_node_t *)yp_forwarding_arguments_node_create(parser, &parser->previous);
                        break;
                    }
                }
            }
            /* fallthrough */
            default: {
                if (argument == NULL) {
                    argument = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_EXPECT_ARGUMENT);
                }

                if (yp_symbol_node_label_p(argument) || accept(parser, YP_TOKEN_EQUAL_GREATER)) {
                    if (parsed_bare_hash) {
                        yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_ARGUMENT_BARE_HASH);
                    }

                    yp_token_t operator;
                    if (parser->previous.type == YP_TOKEN_EQUAL_GREATER) {
                        operator = parser->previous;
                    } else {
                        operator = not_provided(parser);
                    }

                    yp_keyword_hash_node_t *bare_hash = yp_keyword_hash_node_create(parser);

                    // Finish parsing the one we are part way through
                    yp_node_t *value = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_HASH_VALUE);

                    argument = (yp_node_t *) yp_assoc_node_create(parser, argument, &operator, value);
                    yp_keyword_hash_node_elements_append(bare_hash, argument);
                    argument = (yp_node_t *) bare_hash;

                    // Then parse more if we have a comma
                    if (accept(parser, YP_TOKEN_COMMA) && (
                        token_begins_expression_p(parser->current.type) ||
                        match_any_type_p(parser, 2, YP_TOKEN_USTAR_STAR, YP_TOKEN_LABEL)
                    )) {
                        parse_assocs(parser, (yp_node_t *) bare_hash);
                    }

                    parsed_bare_hash = true;
                }

                break;
            }
        }

        yp_arguments_node_arguments_append(arguments->arguments, argument);

        // If parsing the argument failed, we need to stop parsing arguments.
        if (YP_NODE_TYPE_P(argument, YP_MISSING_NODE) || parser->recovering) break;

        // If the terminator of these arguments is not EOF, then we have a specific
        // token we're looking for. In that case we can accept a newline here
        // because it is not functioning as a statement terminator.
        if (terminator != YP_TOKEN_EOF) accept(parser, YP_TOKEN_NEWLINE);

        if (parser->previous.type == YP_TOKEN_COMMA && parsed_bare_hash) {
            // If we previously were on a comma and we just parsed a bare hash, then
            // we want to continue parsing arguments. This is because the comma was
            // grabbed up by the hash parser.
        } else {
            // If there is no comma at the end of the argument list then we're done
            // parsing arguments and can break out of this loop.
            if (!accept(parser, YP_TOKEN_COMMA)) break;
        }

        // If we hit the terminator, then that means we have a trailing comma so we
        // can accept that output as well.
        if (match_type_p(parser, terminator)) break;
    }
}

// Required parameters on method, block, and lambda declarations can be
// destructured using parentheses. This looks like:
//
//     def foo((bar, baz))
//     end
//
// It can recurse infinitely down, and splats are allowed to group arguments.
static yp_required_destructured_parameter_node_t *
parse_required_destructured_parameter(yp_parser_t *parser) {
    expect(parser, YP_TOKEN_PARENTHESIS_LEFT, YP_ERR_EXPECT_LPAREN_REQ_PARAMETER);

    yp_token_t opening = parser->previous;
    yp_required_destructured_parameter_node_t *node = yp_required_destructured_parameter_node_create(parser, &opening);
    bool parsed_splat = false;

    do {
        yp_node_t *param;

        if (node->parameters.size > 0 && match_type_p(parser, YP_TOKEN_PARENTHESIS_RIGHT)) {
            if (parsed_splat) {
                yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_ARGUMENT_SPLAT_AFTER_SPLAT);
            }

            param = (yp_node_t *) yp_splat_node_create(parser, &parser->previous, NULL);
            yp_required_destructured_parameter_node_append_parameter(node, param);
            break;
        }

        if (match_type_p(parser, YP_TOKEN_PARENTHESIS_LEFT)) {
            param = (yp_node_t *) parse_required_destructured_parameter(parser);
        } else if (accept(parser, YP_TOKEN_USTAR)) {
            if (parsed_splat) {
                yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_ARGUMENT_SPLAT_AFTER_SPLAT);
            }

            yp_token_t star = parser->previous;
            yp_node_t *value = NULL;

            if (accept(parser, YP_TOKEN_IDENTIFIER)) {
                yp_token_t name = parser->previous;
                value = (yp_node_t *) yp_required_parameter_node_create(parser, &name);
                yp_parser_local_add_token(parser, &name);
            }

            param = (yp_node_t *) yp_splat_node_create(parser, &star, value);
            parsed_splat = true;
        } else {
            expect(parser, YP_TOKEN_IDENTIFIER, YP_ERR_EXPECT_IDENT_REQ_PARAMETER);
            yp_token_t name = parser->previous;

            param = (yp_node_t *) yp_required_parameter_node_create(parser, &name);
            yp_parser_local_add_token(parser, &name);
        }

        yp_required_destructured_parameter_node_append_parameter(node, param);
    } while (accept(parser, YP_TOKEN_COMMA));

    expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_EXPECT_RPAREN_REQ_PARAMETER);
    yp_required_destructured_parameter_node_closing_set(node, &parser->previous);

    return node;
}

// This represents the different order states we can be in when parsing
// method parameters.
typedef enum {
    YP_PARAMETERS_NO_CHANGE = 0, // Extra state for tokens that should not change the state
    YP_PARAMETERS_ORDER_NOTHING_AFTER = 1,
    YP_PARAMETERS_ORDER_KEYWORDS_REST,
    YP_PARAMETERS_ORDER_KEYWORDS,
    YP_PARAMETERS_ORDER_REST,
    YP_PARAMETERS_ORDER_AFTER_OPTIONAL,
    YP_PARAMETERS_ORDER_OPTIONAL,
    YP_PARAMETERS_ORDER_NAMED,
    YP_PARAMETERS_ORDER_NONE,

} yp_parameters_order_t;

// This matches parameters tokens with parameters state.
static yp_parameters_order_t parameters_ordering[YP_TOKEN_MAXIMUM] = {
    [0] = YP_PARAMETERS_NO_CHANGE,
    [YP_TOKEN_UAMPERSAND] = YP_PARAMETERS_ORDER_NOTHING_AFTER,
    [YP_TOKEN_AMPERSAND] = YP_PARAMETERS_ORDER_NOTHING_AFTER,
    [YP_TOKEN_UDOT_DOT_DOT] = YP_PARAMETERS_ORDER_NOTHING_AFTER,
    [YP_TOKEN_IDENTIFIER] = YP_PARAMETERS_ORDER_NAMED,
    [YP_TOKEN_PARENTHESIS_LEFT] = YP_PARAMETERS_ORDER_NAMED,
    [YP_TOKEN_EQUAL] = YP_PARAMETERS_ORDER_OPTIONAL,
    [YP_TOKEN_LABEL] = YP_PARAMETERS_ORDER_KEYWORDS,
    [YP_TOKEN_USTAR] = YP_PARAMETERS_ORDER_AFTER_OPTIONAL,
    [YP_TOKEN_STAR] = YP_PARAMETERS_ORDER_AFTER_OPTIONAL,
    [YP_TOKEN_USTAR_STAR] = YP_PARAMETERS_ORDER_KEYWORDS_REST,
    [YP_TOKEN_STAR_STAR] = YP_PARAMETERS_ORDER_KEYWORDS_REST
};

// Check if current parameter follows valid parameters ordering. If not it adds an
// error to the list without stopping the parsing, otherwise sets the parameters state
// to the one corresponding to the current parameter.
static void
update_parameter_state(yp_parser_t *parser, yp_token_t *token, yp_parameters_order_t *current) {
    yp_parameters_order_t state = parameters_ordering[token->type];
    if (state == YP_PARAMETERS_NO_CHANGE) return;

    // If we see another ordered argument after a optional argument
    // we only continue parsing ordered arguments until we stop seeing ordered arguments
    if (*current == YP_PARAMETERS_ORDER_OPTIONAL && state == YP_PARAMETERS_ORDER_NAMED) {
        *current = YP_PARAMETERS_ORDER_AFTER_OPTIONAL;
        return;
    } else if (*current == YP_PARAMETERS_ORDER_AFTER_OPTIONAL && state == YP_PARAMETERS_ORDER_NAMED) {
        return;
    }

    if (token->type == YP_TOKEN_USTAR && *current == YP_PARAMETERS_ORDER_AFTER_OPTIONAL) {
        yp_diagnostic_list_append(&parser->error_list, token->start, token->end, YP_ERR_PARAMETER_STAR);
    }

    if (*current == YP_PARAMETERS_ORDER_NOTHING_AFTER || state > *current) {
        // We know what transition we failed on, so we can provide a better error here.
        yp_diagnostic_list_append(&parser->error_list, token->start, token->end, YP_ERR_PARAMETER_ORDER);
    } else if (state < *current) {
        *current = state;
    }
}

// Parse a list of parameters on a method definition.
static yp_parameters_node_t *
parse_parameters(
    yp_parser_t *parser,
    yp_binding_power_t binding_power,
    bool uses_parentheses,
    bool allows_trailing_comma,
    bool allows_forwarding_parameter
) {
    yp_parameters_node_t *params = yp_parameters_node_create(parser);
    bool looping = true;

    yp_do_loop_stack_push(parser, false);
    yp_parameters_order_t order = YP_PARAMETERS_ORDER_NONE;

    do {
        switch (parser->current.type) {
            case YP_TOKEN_PARENTHESIS_LEFT: {
                update_parameter_state(parser, &parser->current, &order);
                yp_node_t *param = (yp_node_t *) parse_required_destructured_parameter(parser);

                if (order > YP_PARAMETERS_ORDER_AFTER_OPTIONAL) {
                    yp_parameters_node_requireds_append(params, param);
                } else {
                    yp_parameters_node_posts_append(params, param);
                }
                break;
            }
            case YP_TOKEN_UAMPERSAND:
            case YP_TOKEN_AMPERSAND: {
                update_parameter_state(parser, &parser->current, &order);
                parser_lex(parser);

                yp_token_t operator = parser->previous;
                yp_token_t name;

                if (accept(parser, YP_TOKEN_IDENTIFIER)) {
                    name = parser->previous;
                    yp_parser_parameter_name_check(parser, &name);
                    yp_parser_local_add_token(parser, &name);
                } else {
                    name = not_provided(parser);
                    yp_parser_local_add_token(parser, &operator);
                }

                yp_block_parameter_node_t *param = yp_block_parameter_node_create(parser, &name, &operator);
                if (params->block == NULL) {
                    yp_parameters_node_block_set(params, param);
                } else {
                    yp_diagnostic_list_append(&parser->error_list, param->base.location.start, param->base.location.end, YP_ERR_PARAMETER_BLOCK_MULTI);
                    yp_parameters_node_posts_append(params, (yp_node_t *) param);
                }

                break;
            }
            case YP_TOKEN_UDOT_DOT_DOT: {
                if (!allows_forwarding_parameter) {
                    yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_ARGUMENT_NO_FORWARDING_ELLIPSES);
                }
                if (order > YP_PARAMETERS_ORDER_NOTHING_AFTER) {
                    update_parameter_state(parser, &parser->current, &order);
                    parser_lex(parser);

                    yp_parser_local_add_token(parser, &parser->previous);
                    yp_forwarding_parameter_node_t *param = yp_forwarding_parameter_node_create(parser, &parser->previous);
                    yp_parameters_node_keyword_rest_set(params, (yp_node_t *)param);
                } else {
                    update_parameter_state(parser, &parser->current, &order);
                    parser_lex(parser);
                }
                break;
            }
            case YP_TOKEN_CLASS_VARIABLE:
            case YP_TOKEN_IDENTIFIER:
            case YP_TOKEN_CONSTANT:
            case YP_TOKEN_INSTANCE_VARIABLE:
            case YP_TOKEN_GLOBAL_VARIABLE: {
                parser_lex(parser);
                switch (parser->previous.type) {
                    case YP_TOKEN_CONSTANT:
                        yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_ARGUMENT_FORMAL_CONSTANT);
                        break;
                    case YP_TOKEN_INSTANCE_VARIABLE:
                        yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_ARGUMENT_FORMAL_IVAR);
                        break;
                    case YP_TOKEN_GLOBAL_VARIABLE:
                        yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_ARGUMENT_FORMAL_GLOBAL);
                        break;
                    case YP_TOKEN_CLASS_VARIABLE:
                        yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_ARGUMENT_FORMAL_CLASS);
                        break;
                    default: break;
                }

                if (parser->current.type == YP_TOKEN_EQUAL) {
                    update_parameter_state(parser, &parser->current, &order);
                } else {
                    update_parameter_state(parser, &parser->previous, &order);
                }

                yp_token_t name = parser->previous;
                yp_parser_parameter_name_check(parser, &name);
                yp_parser_local_add_token(parser, &name);

                if (accept(parser, YP_TOKEN_EQUAL)) {
                    yp_token_t operator = parser->previous;
                    context_push(parser, YP_CONTEXT_DEFAULT_PARAMS);
                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_PARAMETER_NO_DEFAULT);

                    yp_optional_parameter_node_t *param = yp_optional_parameter_node_create(parser, &name, &operator, value);
                    yp_parameters_node_optionals_append(params, param);
                    context_pop(parser);

                    // If parsing the value of the parameter resulted in error recovery,
                    // then we can put a missing node in its place and stop parsing the
                    // parameters entirely now.
                    if (parser->recovering) {
                        looping = false;
                        break;
                    }
                } else if (order > YP_PARAMETERS_ORDER_AFTER_OPTIONAL) {
                    yp_required_parameter_node_t *param = yp_required_parameter_node_create(parser, &name);
                    yp_parameters_node_requireds_append(params, (yp_node_t *) param);
                } else {
                    yp_required_parameter_node_t *param = yp_required_parameter_node_create(parser, &name);
                    yp_parameters_node_posts_append(params, (yp_node_t *) param);
                }

                break;
            }
            case YP_TOKEN_LABEL: {
                if (!uses_parentheses) parser->in_keyword_arg = true;
                update_parameter_state(parser, &parser->current, &order);
                parser_lex(parser);

                yp_token_t name = parser->previous;
                yp_token_t local = name;
                local.end -= 1;

                yp_parser_parameter_name_check(parser, &local);
                yp_parser_local_add_token(parser, &local);

                switch (parser->current.type) {
                    case YP_TOKEN_COMMA:
                    case YP_TOKEN_PARENTHESIS_RIGHT:
                    case YP_TOKEN_PIPE: {
                        yp_node_t *param = (yp_node_t *) yp_keyword_parameter_node_create(parser, &name, NULL);
                        yp_parameters_node_keywords_append(params, param);
                        break;
                    }
                    case YP_TOKEN_SEMICOLON:
                    case YP_TOKEN_NEWLINE: {
                        if (uses_parentheses) {
                            looping = false;
                            break;
                        }

                        yp_node_t *param = (yp_node_t *) yp_keyword_parameter_node_create(parser, &name, NULL);
                        yp_parameters_node_keywords_append(params, param);
                        break;
                    }
                    default: {
                        yp_node_t *value = NULL;
                        if (token_begins_expression_p(parser->current.type)) {
                            context_push(parser, YP_CONTEXT_DEFAULT_PARAMS);
                            value = parse_expression(parser, binding_power, YP_ERR_PARAMETER_NO_DEFAULT_KW);
                            context_pop(parser);
                        }

                        yp_node_t *param = (yp_node_t *) yp_keyword_parameter_node_create(parser, &name, value);
                        yp_parameters_node_keywords_append(params, param);

                        // If parsing the value of the parameter resulted in error recovery,
                        // then we can put a missing node in its place and stop parsing the
                        // parameters entirely now.
                        if (parser->recovering) {
                            looping = false;
                            break;
                        }
                    }
                }

                parser->in_keyword_arg = false;
                break;
            }
            case YP_TOKEN_USTAR:
            case YP_TOKEN_STAR: {
                update_parameter_state(parser, &parser->current, &order);
                parser_lex(parser);

                yp_token_t operator = parser->previous;
                yp_token_t name;

                if (accept(parser, YP_TOKEN_IDENTIFIER)) {
                    name = parser->previous;
                    yp_parser_parameter_name_check(parser, &name);
                    yp_parser_local_add_token(parser, &name);
                } else {
                    name = not_provided(parser);
                    yp_parser_local_add_token(parser, &operator);
                }

                yp_rest_parameter_node_t *param = yp_rest_parameter_node_create(parser, &operator, &name);
                if (params->rest == NULL) {
                    yp_parameters_node_rest_set(params, param);
                } else {
                    yp_diagnostic_list_append(&parser->error_list, param->base.location.start, param->base.location.end, YP_ERR_PARAMETER_SPLAT_MULTI);
                    yp_parameters_node_posts_append(params, (yp_node_t *) param);
                }

                break;
            }
            case YP_TOKEN_STAR_STAR:
            case YP_TOKEN_USTAR_STAR: {
                update_parameter_state(parser, &parser->current, &order);
                parser_lex(parser);

                yp_token_t operator = parser->previous;
                yp_node_t *param;

                if (accept(parser, YP_TOKEN_KEYWORD_NIL)) {
                    param = (yp_node_t *) yp_no_keywords_parameter_node_create(parser, &operator, &parser->previous);
                } else {
                    yp_token_t name;

                    if (accept(parser, YP_TOKEN_IDENTIFIER)) {
                        name = parser->previous;
                        yp_parser_parameter_name_check(parser, &name);
                        yp_parser_local_add_token(parser, &name);
                    } else {
                        name = not_provided(parser);
                        yp_parser_local_add_token(parser, &operator);
                    }

                    param = (yp_node_t *) yp_keyword_rest_parameter_node_create(parser, &operator, &name);
                }

                if (params->keyword_rest == NULL) {
                    yp_parameters_node_keyword_rest_set(params, param);
                } else {
                    yp_diagnostic_list_append(&parser->error_list, param->location.start, param->location.end, YP_ERR_PARAMETER_ASSOC_SPLAT_MULTI);
                    yp_parameters_node_posts_append(params, param);
                }

                break;
            }
            default:
                if (parser->previous.type == YP_TOKEN_COMMA) {
                    if (allows_trailing_comma) {
                        // If we get here, then we have a trailing comma in a block
                        // parameter list. We need to create an anonymous rest parameter to
                        // represent it.
                        yp_token_t name = not_provided(parser);
                        yp_rest_parameter_node_t *param = yp_rest_parameter_node_create(parser, &parser->previous, &name);

                        if (params->rest == NULL) {
                            yp_parameters_node_rest_set(params, param);
                        } else {
                            yp_diagnostic_list_append(&parser->error_list, param->base.location.start, param->base.location.end, YP_ERR_PARAMETER_SPLAT_MULTI);
                            yp_parameters_node_posts_append(params, (yp_node_t *) param);
                        }
                    } else {
                        yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_PARAMETER_WILD_LOOSE_COMMA);
                    }
                }

                looping = false;
                break;
        }

        if (looping && uses_parentheses) {
            accept(parser, YP_TOKEN_NEWLINE);
        }
    } while (looping && accept(parser, YP_TOKEN_COMMA));

    yp_do_loop_stack_pop(parser);

    // If we don't have any parameters, return `NULL` instead of an empty `ParametersNode`.
    if (params->base.location.start == params->base.location.end) {
        yp_node_destroy(parser, (yp_node_t *) params);
        return NULL;
    }

    return params;
}

// Parse any number of rescue clauses. This will form a linked list of if
// nodes pointing to each other from the top.
static inline void
parse_rescues(yp_parser_t *parser, yp_begin_node_t *parent_node) {
    yp_rescue_node_t *current = NULL;

    while (accept(parser, YP_TOKEN_KEYWORD_RESCUE)) {
        yp_rescue_node_t *rescue = yp_rescue_node_create(parser, &parser->previous);

        switch (parser->current.type) {
            case YP_TOKEN_EQUAL_GREATER: {
                // Here we have an immediate => after the rescue keyword, in which case
                // we're going to have an empty list of exceptions to rescue (which
                // implies StandardError).
                parser_lex(parser);
                yp_rescue_node_operator_set(rescue, &parser->previous);

                yp_node_t *reference = parse_expression(parser, YP_BINDING_POWER_INDEX, YP_ERR_RESCUE_VARIABLE);
                reference = parse_target(parser, reference);

                yp_rescue_node_reference_set(rescue, reference);
                break;
            }
            case YP_TOKEN_NEWLINE:
            case YP_TOKEN_SEMICOLON:
            case YP_TOKEN_KEYWORD_THEN:
                // Here we have a terminator for the rescue keyword, in which case we're
                // going to just continue on.
                break;
            default: {
                if (token_begins_expression_p(parser->current.type) || match_type_p(parser, YP_TOKEN_USTAR)) {
                    // Here we have something that could be an exception expression, so
                    // we'll attempt to parse it here and any others delimited by commas.

                    do {
                        yp_node_t *expression = parse_starred_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_RESCUE_EXPRESSION);
                        yp_rescue_node_exceptions_append(rescue, expression);

                        // If we hit a newline, then this is the end of the rescue expression. We
                        // can continue on to parse the statements.
                        if (match_any_type_p(parser, 3, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON, YP_TOKEN_KEYWORD_THEN)) break;

                        // If we hit a `=>` then we're going to parse the exception variable. Once
                        // we've done that, we'll break out of the loop and parse the statements.
                        if (accept(parser, YP_TOKEN_EQUAL_GREATER)) {
                            yp_rescue_node_operator_set(rescue, &parser->previous);

                            yp_node_t *reference = parse_expression(parser, YP_BINDING_POWER_INDEX, YP_ERR_RESCUE_VARIABLE);
                            reference = parse_target(parser, reference);

                            yp_rescue_node_reference_set(rescue, reference);
                            break;
                        }
                    } while (accept(parser, YP_TOKEN_COMMA));
                }
            }
        }

        if (accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) {
            accept(parser, YP_TOKEN_KEYWORD_THEN);
        } else {
            expect(parser, YP_TOKEN_KEYWORD_THEN, YP_ERR_RESCUE_TERM);
        }

        if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_ELSE, YP_TOKEN_KEYWORD_ENSURE, YP_TOKEN_KEYWORD_END)) {
            yp_accepts_block_stack_push(parser, true);
            yp_statements_node_t *statements = parse_statements(parser, YP_CONTEXT_RESCUE);
            if (statements) {
                yp_rescue_node_statements_set(rescue, statements);
            }
            yp_accepts_block_stack_pop(parser);
            accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
        }

        if (current == NULL) {
            yp_begin_node_rescue_clause_set(parent_node, rescue);
        } else {
            yp_rescue_node_consequent_set(current, rescue);
        }

        current = rescue;
    }

    // The end node locations on rescue nodes will not be set correctly
    // since we won't know the end until we've found all consequent
    // clauses. This sets the end location on all rescues once we know it
    if (current) {
        const uint8_t *end_to_set = current->base.location.end;
        current = parent_node->rescue_clause;
        while (current) {
            current->base.location.end = end_to_set;
            current = current->consequent;
        }
    }

    if (accept(parser, YP_TOKEN_KEYWORD_ELSE)) {
        yp_token_t else_keyword = parser->previous;
        accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);

        yp_statements_node_t *else_statements = NULL;
        if (!match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_END, YP_TOKEN_KEYWORD_ENSURE)) {
            yp_accepts_block_stack_push(parser, true);
            else_statements = parse_statements(parser, YP_CONTEXT_RESCUE_ELSE);
            yp_accepts_block_stack_pop(parser);
            accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
        }

        yp_else_node_t *else_clause = yp_else_node_create(parser, &else_keyword, else_statements, &parser->current);
        yp_begin_node_else_clause_set(parent_node, else_clause);
    }

    if (accept(parser, YP_TOKEN_KEYWORD_ENSURE)) {
        yp_token_t ensure_keyword = parser->previous;
        accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);

        yp_statements_node_t *ensure_statements = NULL;
        if (!match_type_p(parser, YP_TOKEN_KEYWORD_END)) {
            yp_accepts_block_stack_push(parser, true);
            ensure_statements = parse_statements(parser, YP_CONTEXT_ENSURE);
            yp_accepts_block_stack_pop(parser);
            accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
        }

        yp_ensure_node_t *ensure_clause = yp_ensure_node_create(parser, &ensure_keyword, ensure_statements, &parser->current);
        yp_begin_node_ensure_clause_set(parent_node, ensure_clause);
    }

    if (parser->current.type == YP_TOKEN_KEYWORD_END) {
        yp_begin_node_end_keyword_set(parent_node, &parser->current);
    } else {
        yp_token_t end_keyword = (yp_token_t) { .type = YP_TOKEN_MISSING, .start = parser->previous.end, .end = parser->previous.end };
        yp_begin_node_end_keyword_set(parent_node, &end_keyword);
    }
}

static inline yp_begin_node_t *
parse_rescues_as_begin(yp_parser_t *parser, yp_statements_node_t *statements) {
    yp_token_t no_begin_token = not_provided(parser);
    yp_begin_node_t *begin_node = yp_begin_node_create(parser, &no_begin_token, statements);
    parse_rescues(parser, begin_node);

    // All nodes within a begin node are optional, so we look
    // for the earliest possible node that we can use to set
    // the BeginNode's start location
    const uint8_t *start = begin_node->base.location.start;
    if (begin_node->statements) {
        start = begin_node->statements->base.location.start;
    } else if (begin_node->rescue_clause) {
        start = begin_node->rescue_clause->base.location.start;
    } else if (begin_node->else_clause) {
        start = begin_node->else_clause->base.location.start;
    } else if (begin_node->ensure_clause) {
        start = begin_node->ensure_clause->base.location.start;
    }

    begin_node->base.location.start = start;
    return begin_node;
}

// Parse a list of parameters and local on a block definition.
static yp_block_parameters_node_t *
parse_block_parameters(
    yp_parser_t *parser,
    bool allows_trailing_comma,
    const yp_token_t *opening,
    bool is_lambda_literal
) {
    yp_parameters_node_t *parameters = NULL;
    if (!match_type_p(parser, YP_TOKEN_SEMICOLON)) {
        parameters = parse_parameters(
            parser,
            is_lambda_literal ? YP_BINDING_POWER_DEFINED : YP_BINDING_POWER_INDEX,
            false,
            allows_trailing_comma,
            false
        );
    }

    yp_block_parameters_node_t *block_parameters = yp_block_parameters_node_create(parser, parameters, opening);
    if (accept(parser, YP_TOKEN_SEMICOLON)) {
        do {
            expect(parser, YP_TOKEN_IDENTIFIER, YP_ERR_BLOCK_PARAM_LOCAL_VARIABLE);
            yp_parser_local_add_token(parser, &parser->previous);

            yp_block_local_variable_node_t *local = yp_block_local_variable_node_create(parser, &parser->previous);
            yp_block_parameters_node_append_local(block_parameters, local);
        } while (accept(parser, YP_TOKEN_COMMA));
    }

    return block_parameters;
}

// Parse a block.
static yp_block_node_t *
parse_block(yp_parser_t *parser) {
    yp_token_t opening = parser->previous;
    accept(parser, YP_TOKEN_NEWLINE);

    yp_accepts_block_stack_push(parser, true);
    yp_parser_scope_push(parser, false);
    yp_block_parameters_node_t *parameters = NULL;

    if (accept(parser, YP_TOKEN_PIPE)) {
        yp_token_t block_parameters_opening = parser->previous;

        if (match_type_p(parser, YP_TOKEN_PIPE)) {
            parameters = yp_block_parameters_node_create(parser, NULL, &block_parameters_opening);
            parser->command_start = true;
            parser_lex(parser);
        } else {
            parameters = parse_block_parameters(parser, true, &block_parameters_opening, false);
            accept(parser, YP_TOKEN_NEWLINE);
            parser->command_start = true;
            expect(parser, YP_TOKEN_PIPE, YP_ERR_BLOCK_PARAM_PIPE_TERM);
        }

        yp_block_parameters_node_closing_set(parameters, &parser->previous);
    }

    accept(parser, YP_TOKEN_NEWLINE);
    yp_node_t *statements = NULL;

    if (opening.type == YP_TOKEN_BRACE_LEFT) {
        if (!match_type_p(parser, YP_TOKEN_BRACE_RIGHT)) {
            statements = (yp_node_t *) parse_statements(parser, YP_CONTEXT_BLOCK_BRACES);
        }

        expect(parser, YP_TOKEN_BRACE_RIGHT, YP_ERR_BLOCK_TERM_BRACE);
    } else {
        if (!match_type_p(parser, YP_TOKEN_KEYWORD_END)) {
            if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ELSE, YP_TOKEN_KEYWORD_ENSURE)) {
                yp_accepts_block_stack_push(parser, true);
                statements = (yp_node_t *) parse_statements(parser, YP_CONTEXT_BLOCK_KEYWORDS);
                yp_accepts_block_stack_pop(parser);
            }

            if (match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE)) {
                assert(statements == NULL || YP_NODE_TYPE_P(statements, YP_STATEMENTS_NODE));
                statements = (yp_node_t *) parse_rescues_as_begin(parser, (yp_statements_node_t *) statements);
            }
        }

        expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_BLOCK_TERM_END);
    }

    yp_constant_id_list_t locals = parser->current_scope->locals;
    yp_parser_scope_pop(parser);
    yp_accepts_block_stack_pop(parser);
    return yp_block_node_create(parser, &locals, &opening, parameters, statements, &parser->previous);
}

// Parse a list of arguments and their surrounding parentheses if they are
// present. It returns true if it found any pieces of arguments (parentheses,
// arguments, or blocks).
static bool
parse_arguments_list(yp_parser_t *parser, yp_arguments_t *arguments, bool accepts_block) {
    bool found = false;

    if (accept(parser, YP_TOKEN_PARENTHESIS_LEFT)) {
        found |= true;
        arguments->opening_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);

        if (accept(parser, YP_TOKEN_PARENTHESIS_RIGHT)) {
            arguments->closing_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);
        } else {
            arguments->arguments = yp_arguments_node_create(parser);

            yp_accepts_block_stack_push(parser, true);
            parse_arguments(parser, arguments, true, YP_TOKEN_PARENTHESIS_RIGHT);
            expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_ARGUMENT_TERM_PAREN);
            yp_accepts_block_stack_pop(parser);

            arguments->closing_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);
        }
    } else if ((token_begins_expression_p(parser->current.type) || match_any_type_p(parser, 3, YP_TOKEN_USTAR, YP_TOKEN_USTAR_STAR, YP_TOKEN_UAMPERSAND)) && !match_type_p(parser, YP_TOKEN_BRACE_LEFT)) {
        found |= true;
        yp_accepts_block_stack_push(parser, false);

        // If we get here, then the subsequent token cannot be used as an infix
        // operator. In this case we assume the subsequent token is part of an
        // argument to this method call.
        arguments->arguments = yp_arguments_node_create(parser);
        parse_arguments(parser, arguments, true, YP_TOKEN_EOF);

        yp_accepts_block_stack_pop(parser);
    }

    // If we're at the end of the arguments, we can now check if there is a block
    // node that starts with a {. If there is, then we can parse it and add it to
    // the arguments.
    if (accepts_block) {
        if (accept(parser, YP_TOKEN_BRACE_LEFT)) {
            found |= true;
            arguments->block = parse_block(parser);
        } else if (yp_accepts_block_stack_p(parser) && accept(parser, YP_TOKEN_KEYWORD_DO)) {
            found |= true;
            arguments->block = parse_block(parser);
        }
    }

    yp_arguments_validate(parser, arguments);
    return found;
}

static inline yp_node_t *
parse_conditional(yp_parser_t *parser, yp_context_t context) {
    yp_token_t keyword = parser->previous;

    context_push(parser, YP_CONTEXT_PREDICATE);
    yp_diagnostic_id_t error_id = context == YP_CONTEXT_IF ? YP_ERR_CONDITIONAL_IF_PREDICATE : YP_ERR_CONDITIONAL_UNLESS_PREDICATE;
    yp_node_t *predicate = parse_expression(parser, YP_BINDING_POWER_MODIFIER, error_id);

    // Predicates are closed by a term, a "then", or a term and then a "then".
    accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
    accept(parser, YP_TOKEN_KEYWORD_THEN);

    context_pop(parser);
    yp_statements_node_t *statements = NULL;

    if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_ELSIF, YP_TOKEN_KEYWORD_ELSE, YP_TOKEN_KEYWORD_END)) {
        yp_accepts_block_stack_push(parser, true);
        statements = parse_statements(parser, context);
        yp_accepts_block_stack_pop(parser);
        accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
    }

    yp_token_t end_keyword = not_provided(parser);
    yp_node_t *parent = NULL;

    switch (context) {
        case YP_CONTEXT_IF:
            parent = (yp_node_t *) yp_if_node_create(parser, &keyword, predicate, statements, NULL, &end_keyword);
            break;
        case YP_CONTEXT_UNLESS:
            parent = (yp_node_t *) yp_unless_node_create(parser, &keyword, predicate, statements);
            break;
        default:
            assert(false && "unreachable");
            break;
    }

    yp_node_t *current = parent;

    // Parse any number of elsif clauses. This will form a linked list of if
    // nodes pointing to each other from the top.
    if (context == YP_CONTEXT_IF) {
        while (accept(parser, YP_TOKEN_KEYWORD_ELSIF)) {
            yp_token_t elsif_keyword = parser->previous;
            yp_node_t *predicate = parse_expression(parser, YP_BINDING_POWER_MODIFIER, YP_ERR_CONDITIONAL_ELSIF_PREDICATE);

            // Predicates are closed by a term, a "then", or a term and then a "then".
            accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
            accept(parser, YP_TOKEN_KEYWORD_THEN);

            yp_accepts_block_stack_push(parser, true);
            yp_statements_node_t *statements = parse_statements(parser, YP_CONTEXT_ELSIF);
            yp_accepts_block_stack_pop(parser);

            accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);

            yp_node_t *elsif = (yp_node_t *) yp_if_node_create(parser, &elsif_keyword, predicate, statements, NULL, &end_keyword);
            ((yp_if_node_t *) current)->consequent = elsif;
            current = elsif;
        }
    }

    if (match_type_p(parser, YP_TOKEN_KEYWORD_ELSE)) {
        parser_lex(parser);
        yp_token_t else_keyword = parser->previous;

        yp_accepts_block_stack_push(parser, true);
        yp_statements_node_t *else_statements = parse_statements(parser, YP_CONTEXT_ELSE);
        yp_accepts_block_stack_pop(parser);

        accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
        expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_CONDITIONAL_TERM_ELSE);

        yp_else_node_t *else_node = yp_else_node_create(parser, &else_keyword, else_statements, &parser->previous);

        switch (context) {
            case YP_CONTEXT_IF:
                ((yp_if_node_t *) current)->consequent = (yp_node_t *) else_node;
                break;
            case YP_CONTEXT_UNLESS:
                ((yp_unless_node_t *) parent)->consequent = else_node;
                break;
            default:
                assert(false && "unreachable");
                break;
        }
    } else {
        // We should specialize this error message to refer to 'if' or 'unless' explicitly.
        expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_CONDITIONAL_TERM);
    }

    // Set the appropriate end location for all of the nodes in the subtree.
    switch (context) {
        case YP_CONTEXT_IF: {
            yp_node_t *current = parent;
            bool recursing = true;

            while (recursing) {
                switch (YP_NODE_TYPE(current)) {
                    case YP_IF_NODE:
                        yp_if_node_end_keyword_loc_set((yp_if_node_t *) current, &parser->previous);
                        current = ((yp_if_node_t *) current)->consequent;
                        recursing = current != NULL;
                        break;
                    case YP_ELSE_NODE:
                        yp_else_node_end_keyword_loc_set((yp_else_node_t *) current, &parser->previous);
                        recursing = false;
                        break;
                    default: {
                        recursing = false;
                        break;
                    }
                }
            }
            break;
        }
        case YP_CONTEXT_UNLESS:
            yp_unless_node_end_keyword_loc_set((yp_unless_node_t *) parent, &parser->previous);
            break;
        default:
            assert(false && "unreachable");
            break;
    }

    return parent;
}

// This macro allows you to define a case statement for all of the keywords.
// It's meant to be used in a switch statement.
#define YP_CASE_KEYWORD YP_TOKEN_KEYWORD___ENCODING__: case YP_TOKEN_KEYWORD___FILE__: case YP_TOKEN_KEYWORD___LINE__: \
    case YP_TOKEN_KEYWORD_ALIAS: case YP_TOKEN_KEYWORD_AND: case YP_TOKEN_KEYWORD_BEGIN: case YP_TOKEN_KEYWORD_BEGIN_UPCASE: \
    case YP_TOKEN_KEYWORD_BREAK: case YP_TOKEN_KEYWORD_CASE: case YP_TOKEN_KEYWORD_CLASS: case YP_TOKEN_KEYWORD_DEF: \
    case YP_TOKEN_KEYWORD_DEFINED: case YP_TOKEN_KEYWORD_DO: case YP_TOKEN_KEYWORD_DO_LOOP: case YP_TOKEN_KEYWORD_ELSE: \
    case YP_TOKEN_KEYWORD_ELSIF: case YP_TOKEN_KEYWORD_END: case YP_TOKEN_KEYWORD_END_UPCASE: case YP_TOKEN_KEYWORD_ENSURE: \
    case YP_TOKEN_KEYWORD_FALSE: case YP_TOKEN_KEYWORD_FOR: case YP_TOKEN_KEYWORD_IF: case YP_TOKEN_KEYWORD_IN: \
    case YP_TOKEN_KEYWORD_MODULE: case YP_TOKEN_KEYWORD_NEXT: case YP_TOKEN_KEYWORD_NIL: case YP_TOKEN_KEYWORD_NOT: \
    case YP_TOKEN_KEYWORD_OR: case YP_TOKEN_KEYWORD_REDO: case YP_TOKEN_KEYWORD_RESCUE: case YP_TOKEN_KEYWORD_RETRY: \
    case YP_TOKEN_KEYWORD_RETURN: case YP_TOKEN_KEYWORD_SELF: case YP_TOKEN_KEYWORD_SUPER: case YP_TOKEN_KEYWORD_THEN: \
    case YP_TOKEN_KEYWORD_TRUE: case YP_TOKEN_KEYWORD_UNDEF: case YP_TOKEN_KEYWORD_UNLESS: case YP_TOKEN_KEYWORD_UNTIL: \
    case YP_TOKEN_KEYWORD_WHEN: case YP_TOKEN_KEYWORD_WHILE: case YP_TOKEN_KEYWORD_YIELD


// This macro allows you to define a case statement for all of the operators.
// It's meant to be used in a switch statement.
#define YP_CASE_OPERATOR YP_TOKEN_AMPERSAND: case YP_TOKEN_BACKTICK: case YP_TOKEN_BANG_EQUAL: \
    case YP_TOKEN_BANG_TILDE: case YP_TOKEN_BANG: case YP_TOKEN_BRACKET_LEFT_RIGHT_EQUAL: \
    case YP_TOKEN_BRACKET_LEFT_RIGHT: case YP_TOKEN_CARET: case YP_TOKEN_EQUAL_EQUAL_EQUAL: case YP_TOKEN_EQUAL_EQUAL: \
    case YP_TOKEN_EQUAL_TILDE: case YP_TOKEN_GREATER_EQUAL: case YP_TOKEN_GREATER_GREATER: case YP_TOKEN_GREATER: \
    case YP_TOKEN_LESS_EQUAL_GREATER: case YP_TOKEN_LESS_EQUAL: case YP_TOKEN_LESS_LESS: case YP_TOKEN_LESS: \
    case YP_TOKEN_MINUS: case YP_TOKEN_PERCENT: case YP_TOKEN_PIPE: case YP_TOKEN_PLUS: case YP_TOKEN_SLASH: \
    case YP_TOKEN_STAR_STAR: case YP_TOKEN_STAR: case YP_TOKEN_TILDE: case YP_TOKEN_UAMPERSAND: case YP_TOKEN_UMINUS: \
    case YP_TOKEN_UMINUS_NUM: case YP_TOKEN_UPLUS: case YP_TOKEN_USTAR: case YP_TOKEN_USTAR_STAR

// This macro allows you to define a case statement for all of the token types
// that represent the beginning of nodes that are "primitives" in a pattern
// matching expression.
#define YP_CASE_PRIMITIVE YP_TOKEN_INTEGER: case YP_TOKEN_INTEGER_IMAGINARY: case YP_TOKEN_INTEGER_RATIONAL: \
    case YP_TOKEN_INTEGER_RATIONAL_IMAGINARY: case YP_TOKEN_FLOAT: case YP_TOKEN_FLOAT_IMAGINARY: \
    case YP_TOKEN_FLOAT_RATIONAL: case YP_TOKEN_FLOAT_RATIONAL_IMAGINARY: case YP_TOKEN_SYMBOL_BEGIN: \
    case YP_TOKEN_REGEXP_BEGIN: case YP_TOKEN_BACKTICK: case YP_TOKEN_PERCENT_LOWER_X: case YP_TOKEN_PERCENT_LOWER_I: \
    case YP_TOKEN_PERCENT_LOWER_W: case YP_TOKEN_PERCENT_UPPER_I: case YP_TOKEN_PERCENT_UPPER_W: \
    case YP_TOKEN_STRING_BEGIN: case YP_TOKEN_KEYWORD_NIL: case YP_TOKEN_KEYWORD_SELF: case YP_TOKEN_KEYWORD_TRUE: \
    case YP_TOKEN_KEYWORD_FALSE: case YP_TOKEN_KEYWORD___FILE__: case YP_TOKEN_KEYWORD___LINE__: \
    case YP_TOKEN_KEYWORD___ENCODING__: case YP_TOKEN_MINUS_GREATER: case YP_TOKEN_HEREDOC_START: \
    case YP_TOKEN_UMINUS_NUM: case YP_TOKEN_CHARACTER_LITERAL

// This macro allows you to define a case statement for all of the token types
// that could begin a parameter.
#define YP_CASE_PARAMETER YP_TOKEN_UAMPERSAND: case YP_TOKEN_AMPERSAND: case YP_TOKEN_UDOT_DOT_DOT: \
    case YP_TOKEN_IDENTIFIER: case YP_TOKEN_LABEL: case YP_TOKEN_USTAR: case YP_TOKEN_STAR: case YP_TOKEN_STAR_STAR: \
    case YP_TOKEN_USTAR_STAR: case YP_TOKEN_CONSTANT: case YP_TOKEN_INSTANCE_VARIABLE: case YP_TOKEN_GLOBAL_VARIABLE: \
    case YP_TOKEN_CLASS_VARIABLE

// This macro allows you to define a case statement for all of the nodes that
// can be transformed into write targets.
#define YP_CASE_WRITABLE YP_CLASS_VARIABLE_READ_NODE: case YP_CONSTANT_PATH_NODE: \
    case YP_CONSTANT_READ_NODE: case YP_GLOBAL_VARIABLE_READ_NODE: case YP_LOCAL_VARIABLE_READ_NODE: \
    case YP_INSTANCE_VARIABLE_READ_NODE: case YP_MULTI_TARGET_NODE: case YP_BACK_REFERENCE_READ_NODE: \
    case YP_NUMBERED_REFERENCE_READ_NODE

// Parse a node that is part of a string. If the subsequent tokens cannot be
// parsed as a string part, then NULL is returned.
static yp_node_t *
parse_string_part(yp_parser_t *parser) {
    switch (parser->current.type) {
        // Here the lexer has returned to us plain string content. In this case
        // we'll create a string node that has no opening or closing and return that
        // as the part. These kinds of parts look like:
        //
        //     "aaa #{bbb} #@ccc ddd"
        //      ^^^^      ^     ^^^^
        case YP_TOKEN_STRING_CONTENT: {
            yp_unescape_type_t unescape_type = YP_UNESCAPE_ALL;

            if (parser->lex_modes.current->mode == YP_LEX_HEREDOC) {
                if (parser->lex_modes.current->as.heredoc.indent == YP_HEREDOC_INDENT_TILDE) {
                    // If we're in a tilde heredoc, we want to unescape it later
                    // because we don't want unescaped newlines to disappear
                    // before we handle them in the dedent.
                    unescape_type = YP_UNESCAPE_NONE;
                } else if (parser->lex_modes.current->as.heredoc.quote == YP_HEREDOC_QUOTE_SINGLE) {
                    unescape_type = YP_UNESCAPE_MINIMAL;
                }
            }

            parser_lex(parser);

            yp_token_t opening = not_provided(parser);
            yp_token_t closing = not_provided(parser);

            return (yp_node_t *) yp_string_node_create_and_unescape(parser, &opening, &parser->previous, &closing, unescape_type);
        }
        // Here the lexer has returned the beginning of an embedded expression. In
        // that case we'll parse the inner statements and return that as the part.
        // These kinds of parts look like:
        //
        //     "aaa #{bbb} #@ccc ddd"
        //          ^^^^^^
        case YP_TOKEN_EMBEXPR_BEGIN: {
            yp_lex_state_t state = parser->lex_state;
            int brace_nesting = parser->brace_nesting;

            parser->brace_nesting = 0;
            lex_state_set(parser, YP_LEX_STATE_BEG);
            parser_lex(parser);

            yp_token_t opening = parser->previous;
            yp_statements_node_t *statements = NULL;

            if (!match_type_p(parser, YP_TOKEN_EMBEXPR_END)) {
                yp_accepts_block_stack_push(parser, true);
                statements = parse_statements(parser, YP_CONTEXT_EMBEXPR);
                yp_accepts_block_stack_pop(parser);
            }

            parser->brace_nesting = brace_nesting;
            lex_state_set(parser, state);

            expect(parser, YP_TOKEN_EMBEXPR_END, YP_ERR_EMBEXPR_END);
            yp_token_t closing = parser->previous;

            return (yp_node_t *) yp_embedded_statements_node_create(parser, &opening, statements, &closing);
        }

        // Here the lexer has returned the beginning of an embedded variable.
        // In that case we'll parse the variable and create an appropriate node
        // for it and then return that node. These kinds of parts look like:
        //
        //     "aaa #{bbb} #@ccc ddd"
        //                 ^^^^^
        case YP_TOKEN_EMBVAR: {
            lex_state_set(parser, YP_LEX_STATE_BEG);
            parser_lex(parser);

            yp_token_t operator = parser->previous;
            yp_node_t *variable;

            switch (parser->current.type) {
                // In this case a back reference is being interpolated. We'll
                // create a global variable read node.
                case YP_TOKEN_BACK_REFERENCE:
                    parser_lex(parser);
                    variable = (yp_node_t *) yp_back_reference_read_node_create(parser, &parser->previous);
                    break;
                // In this case an nth reference is being interpolated. We'll
                // create a global variable read node.
                case YP_TOKEN_NUMBERED_REFERENCE:
                    parser_lex(parser);
                    variable = (yp_node_t *) yp_numbered_reference_read_node_create(parser, &parser->previous);
                    break;
                // In this case a global variable is being interpolated. We'll
                // create a global variable read node.
                case YP_TOKEN_GLOBAL_VARIABLE:
                    parser_lex(parser);
                    variable = (yp_node_t *) yp_global_variable_read_node_create(parser, &parser->previous);
                    break;
                // In this case an instance variable is being interpolated.
                // We'll create an instance variable read node.
                case YP_TOKEN_INSTANCE_VARIABLE:
                    parser_lex(parser);
                    variable = (yp_node_t *) yp_instance_variable_read_node_create(parser, &parser->previous);
                    break;
                // In this case a class variable is being interpolated. We'll
                // create a class variable read node.
                case YP_TOKEN_CLASS_VARIABLE:
                    parser_lex(parser);
                    variable = (yp_node_t *) yp_class_variable_read_node_create(parser, &parser->previous);
                    break;
                // We can hit here if we got an invalid token. In that case
                // we'll not attempt to lex this token and instead just return a
                // missing node.
                default:
                    expect(parser, YP_TOKEN_IDENTIFIER, YP_ERR_EMBVAR_INVALID);
                    variable = (yp_node_t *) yp_missing_node_create(parser, parser->current.start, parser->current.end);
                    break;
            }

            return (yp_node_t *) yp_embedded_variable_node_create(parser, &operator, variable);
        }
        default:
            parser_lex(parser);
            yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_CANNOT_PARSE_STRING_PART);
            return NULL;
    }
}

static yp_node_t *
parse_symbol(yp_parser_t *parser, yp_lex_mode_t *lex_mode, yp_lex_state_t next_state) {
    yp_token_t opening = parser->previous;

    if (lex_mode->mode != YP_LEX_STRING) {
        if (next_state != YP_LEX_STATE_NONE) lex_state_set(parser, next_state);
        yp_token_t symbol;

        switch (parser->current.type) {
            case YP_TOKEN_IDENTIFIER:
            case YP_TOKEN_CONSTANT:
            case YP_TOKEN_INSTANCE_VARIABLE:
            case YP_TOKEN_CLASS_VARIABLE:
            case YP_TOKEN_GLOBAL_VARIABLE:
            case YP_TOKEN_NUMBERED_REFERENCE:
            case YP_TOKEN_BACK_REFERENCE:
            case YP_CASE_KEYWORD:
                parser_lex(parser);
                symbol = parser->previous;
                break;
            case YP_CASE_OPERATOR:
                lex_state_set(parser, next_state == YP_LEX_STATE_NONE ? YP_LEX_STATE_ENDFN : next_state);
                parser_lex(parser);
                symbol = parser->previous;
                break;
            default:
                expect(parser, YP_TOKEN_IDENTIFIER, YP_ERR_SYMBOL_INVALID);
                symbol = parser->previous;
                break;
        }

        yp_token_t closing = not_provided(parser);
        return (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &symbol, &closing, YP_UNESCAPE_ALL);
    }

    if (lex_mode->as.string.interpolation) {
        // If we have the end of the symbol, then we can return an empty symbol.
        if (match_type_p(parser, YP_TOKEN_STRING_END)) {
            if (next_state != YP_LEX_STATE_NONE) lex_state_set(parser, next_state);
            parser_lex(parser);

            yp_token_t content = not_provided(parser);
            yp_token_t closing = parser->previous;
            return (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &content, &closing, YP_UNESCAPE_NONE);
        }

        // Now we can parse the first part of the symbol.
        yp_node_t *part = parse_string_part(parser);

        // If we got a string part, then it's possible that we could transform
        // what looks like an interpolated symbol into a regular symbol.
        if (part && YP_NODE_TYPE_P(part, YP_STRING_NODE) && match_any_type_p(parser, 2, YP_TOKEN_STRING_END, YP_TOKEN_EOF)) {
            if (next_state != YP_LEX_STATE_NONE) lex_state_set(parser, next_state);
            parser_lex(parser);

            return (yp_node_t *) yp_string_node_to_symbol_node(parser, (yp_string_node_t *) part, &opening, &parser->previous);
        }

        // Create a node_list first. We'll use this to check if it should be an
        // InterpolatedSymbolNode or a SymbolNode.
        yp_node_list_t node_list = YP_EMPTY_NODE_LIST;
        if (part) yp_node_list_append(&node_list, part);

        while (!match_any_type_p(parser, 2, YP_TOKEN_STRING_END, YP_TOKEN_EOF)) {
            if ((part = parse_string_part(parser)) != NULL) {
                yp_node_list_append(&node_list, part);
            }
        }

        if (next_state != YP_LEX_STATE_NONE) lex_state_set(parser, next_state);
        expect(parser, YP_TOKEN_STRING_END, YP_ERR_SYMBOL_TERM_INTERPOLATED);

        return (yp_node_t *) yp_interpolated_symbol_node_create(parser, &opening, &node_list, &parser->previous);
    }

    yp_token_t content;
    if (accept(parser, YP_TOKEN_STRING_CONTENT)) {
        content = parser->previous;
    } else {
        content = (yp_token_t) { .type = YP_TOKEN_STRING_CONTENT, .start = parser->previous.end, .end = parser->previous.end };
    }

    if (next_state != YP_LEX_STATE_NONE) {
        lex_state_set(parser, next_state);
    }
    expect(parser, YP_TOKEN_STRING_END, YP_ERR_SYMBOL_TERM_DYNAMIC);

    return (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &content, &parser->previous, YP_UNESCAPE_ALL);
}

// Parse an argument to undef which can either be a bare word, a
// symbol, a constant, or an interpolated symbol.
static inline yp_node_t *
parse_undef_argument(yp_parser_t *parser) {
    switch (parser->current.type) {
        case YP_CASE_KEYWORD:
        case YP_CASE_OPERATOR:
        case YP_TOKEN_CONSTANT:
        case YP_TOKEN_IDENTIFIER: {
            parser_lex(parser);

            yp_token_t opening = not_provided(parser);
            yp_token_t closing = not_provided(parser);

            return (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &parser->previous, &closing, YP_UNESCAPE_ALL);
        }
        case YP_TOKEN_SYMBOL_BEGIN: {
            yp_lex_mode_t lex_mode = *parser->lex_modes.current;
            parser_lex(parser);

            return parse_symbol(parser, &lex_mode, YP_LEX_STATE_NONE);
        }
        default:
            yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_UNDEF_ARGUMENT);
            return (yp_node_t *) yp_missing_node_create(parser, parser->current.start, parser->current.end);
    }
}

// Parse an argument to alias which can either be a bare word, a symbol, an
// interpolated symbol or a global variable. If this is the first argument, then
// we need to set the lex state to YP_LEX_STATE_FNAME | YP_LEX_STATE_FITEM
// between the first and second arguments.
static inline yp_node_t *
parse_alias_argument(yp_parser_t *parser, bool first) {
    switch (parser->current.type) {
        case YP_CASE_OPERATOR:
        case YP_CASE_KEYWORD:
        case YP_TOKEN_CONSTANT:
        case YP_TOKEN_IDENTIFIER: {
            if (first) {
                lex_state_set(parser, YP_LEX_STATE_FNAME | YP_LEX_STATE_FITEM);
            }

            parser_lex(parser);
            yp_token_t opening = not_provided(parser);
            yp_token_t closing = not_provided(parser);

            return (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &parser->previous, &closing, YP_UNESCAPE_ALL);
        }
        case YP_TOKEN_SYMBOL_BEGIN: {
            yp_lex_mode_t lex_mode = *parser->lex_modes.current;
            parser_lex(parser);

            return parse_symbol(parser, &lex_mode, first ? YP_LEX_STATE_FNAME | YP_LEX_STATE_FITEM : YP_LEX_STATE_NONE);
        }
        case YP_TOKEN_BACK_REFERENCE:
            parser_lex(parser);
            return (yp_node_t *) yp_back_reference_read_node_create(parser, &parser->previous);
        case YP_TOKEN_NUMBERED_REFERENCE:
            parser_lex(parser);
            return (yp_node_t *) yp_numbered_reference_read_node_create(parser, &parser->previous);
        case YP_TOKEN_GLOBAL_VARIABLE:
            parser_lex(parser);
            return (yp_node_t *) yp_global_variable_read_node_create(parser, &parser->previous);
        default:
            yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_ALIAS_ARGUMENT);
            return (yp_node_t *) yp_missing_node_create(parser, parser->current.start, parser->current.end);
    }
}

// Parse an identifier into either a local variable read or a call.
static yp_node_t *
parse_variable_call(yp_parser_t *parser) {
    yp_node_flags_t flags = 0;

    if (!match_type_p(parser, YP_TOKEN_PARENTHESIS_LEFT) && (parser->previous.end[-1] != '!') && (parser->previous.end[-1] != '?')) {
        int depth;
        if ((depth = yp_parser_local_depth(parser, &parser->previous)) != -1) {
            return (yp_node_t *) yp_local_variable_read_node_create(parser, &parser->previous, (uint32_t) depth);
        }

        flags |= YP_CALL_NODE_FLAGS_VARIABLE_CALL;
    }

    yp_call_node_t *node = yp_call_node_variable_call_create(parser, &parser->previous);
    node->base.flags |= flags;

    return (yp_node_t *) node;
}

static inline yp_token_t
parse_method_definition_name(yp_parser_t *parser) {
    switch (parser->current.type) {
        case YP_CASE_KEYWORD:
        case YP_TOKEN_CONSTANT:
        case YP_TOKEN_IDENTIFIER:
            parser_lex(parser);
            return parser->previous;
        case YP_CASE_OPERATOR:
            lex_state_set(parser, YP_LEX_STATE_ENDFN);
            parser_lex(parser);
            return parser->previous;
        default:
            return not_provided(parser);
    }
}

// Calculate the common leading whitespace for each line in a heredoc.
static int
parse_heredoc_common_whitespace(yp_parser_t *parser, yp_node_list_t *nodes) {
    int common_whitespace = -1;

    for (size_t index = 0; index < nodes->size; index++) {
        yp_node_t *node = nodes->nodes[index];

        if (!YP_NODE_TYPE_P(node, YP_STRING_NODE)) continue;
        const yp_location_t *content_loc = &((yp_string_node_t *) node)->content_loc;

        // If the previous node wasn't a string node, we don't want to trim
        // whitespace. This could happen after an interpolated expression or
        // variable.
        if (index == 0 || YP_NODE_TYPE_P(nodes->nodes[index - 1], YP_STRING_NODE)) {
            int cur_whitespace;
            const uint8_t *cur_char = content_loc->start;

            while (cur_char && cur_char < content_loc->end) {
                // Any empty newlines aren't included in the minimum whitespace
                // calculation.
                size_t eol_length;
                while ((eol_length = match_eol_at(parser, cur_char))) {
                    cur_char += eol_length;
                }

                if (cur_char == content_loc->end) break;

                cur_whitespace = 0;

                while (yp_char_is_inline_whitespace(*cur_char) && cur_char < content_loc->end) {
                    if (cur_char[0] == '\t') {
                        cur_whitespace = (cur_whitespace / YP_TAB_WHITESPACE_SIZE + 1) * YP_TAB_WHITESPACE_SIZE;
                    } else {
                        cur_whitespace++;
                    }
                    cur_char++;
                }

                // If we hit a newline, then we have encountered a line that
                // contains only whitespace, and it shouldn't be considered in
                // the calculation of common leading whitespace.
                eol_length = match_eol_at(parser, cur_char);
                if (eol_length) {
                    cur_char += eol_length;
                    continue;
                }

                if (cur_whitespace < common_whitespace || common_whitespace == -1) {
                    common_whitespace = cur_whitespace;
                }

                cur_char = next_newline(cur_char + 1, parser->end - (cur_char + 1));
                if (cur_char) cur_char++;
            }
        }
    }

    return common_whitespace;
}

// Take a heredoc node that is indented by a ~ and trim the leading whitespace.
static void
parse_heredoc_dedent(yp_parser_t *parser, yp_node_t *node, yp_heredoc_quote_t quote) {
    yp_node_list_t *nodes;

    if (quote == YP_HEREDOC_QUOTE_BACKTICK) {
        nodes = &((yp_interpolated_x_string_node_t *) node)->parts;
    } else {
        nodes = &((yp_interpolated_string_node_t *) node)->parts;
    }

    // First, calculate how much common whitespace we need to trim. If there is
    // none or it's 0, then we can return early.
    int common_whitespace;
    if ((common_whitespace = parse_heredoc_common_whitespace(parser, nodes)) <= 0) return;

    // The next node should be dedented if it's the first node in the list or if
    // if follows a string node.
    bool dedent_next = true;

    // Iterate over all nodes, and trim whitespace accordingly. We're going to
    // keep around two indices: a read and a write. If we end up trimming all of
    // the whitespace from a node, then we'll drop it from the list entirely.
    size_t write_index = 0;

    for (size_t read_index = 0; read_index < nodes->size; read_index++) {
        yp_node_t *node = nodes->nodes[read_index];

        // We're not manipulating child nodes that aren't strings. In this case
        // we'll skip past it and indicate that the subsequent node should not
        // be dedented.
        if (!YP_NODE_TYPE_P(node, YP_STRING_NODE)) {
            nodes->nodes[write_index++] = node;
            dedent_next = false;
            continue;
        }

        // Get a reference to the string struct that is being held by the string
        // node. This is the value we're going to actual manipulate.
        yp_string_t *string = &(((yp_string_node_t *) node)->unescaped);
        yp_string_ensure_owned(string);

        // Now get the bounds of the existing string. We'll use this as a
        // destination to move bytes into. We'll also use it for bounds checking
        // since we don't require that these strings be null terminated.
        size_t dest_length = yp_string_length(string);
        uint8_t *source_start = (uint8_t *) string->source;

        const uint8_t *source_cursor = source_start;
        const uint8_t *source_end = source_cursor + dest_length;

        // We're going to move bytes backward in the string when we get leading
        // whitespace, so we'll maintain a pointer to the current position in the
        // string that we're writing to.
        uint8_t *dest_cursor = source_start;

        while (source_cursor < source_end) {
            // If we need to dedent the next element within the heredoc or the next
            // line within the string node, then we'll do it here.
            if (dedent_next) {
                int trimmed_whitespace = 0;

                // While we haven't reached the amount of common whitespace that we need
                // to trim and we haven't reached the end of the string, we'll keep
                // trimming whitespace. Trimming in this context means skipping over
                // these bytes such that they aren't copied into the new string.
                while ((source_cursor < source_end) && yp_char_is_inline_whitespace(*source_cursor) && trimmed_whitespace < common_whitespace) {
                    if (*source_cursor == '\t') {
                        trimmed_whitespace = (trimmed_whitespace / YP_TAB_WHITESPACE_SIZE + 1) * YP_TAB_WHITESPACE_SIZE;
                        if (trimmed_whitespace > common_whitespace) break;
                    } else {
                        trimmed_whitespace++;
                    }

                    source_cursor++;
                    dest_length--;
                }
            }

            // At this point we have dedented all that we need to, so we need to find
            // the next newline.
            const uint8_t *breakpoint = next_newline(source_cursor, source_end - source_cursor);

            if (breakpoint == NULL) {
                // If there isn't another newline, then we can just move the rest of the
                // string and break from the loop.
                memmove(dest_cursor, source_cursor, (size_t) (source_end - source_cursor));
                break;
            }

            // Otherwise, we need to move everything including the newline, and
            // then set the dedent_next flag to true.
            if (breakpoint < source_end) breakpoint++;
            memmove(dest_cursor, source_cursor, (size_t) (breakpoint - source_cursor));
            dest_cursor += (breakpoint - source_cursor);
            source_cursor = breakpoint;
            dedent_next = true;
        }

        // We only want to write this node into the list if it has any content.
        if (dest_length == 0) {
            yp_node_destroy(parser, node);
        } else {
            string->length = dest_length;
            yp_unescape_manipulate_string(parser, string, (quote == YP_HEREDOC_QUOTE_SINGLE) ? YP_UNESCAPE_MINIMAL : YP_UNESCAPE_ALL);
            nodes->nodes[write_index++] = node;
        }

        // We always dedent the next node if it follows a string node.
        dedent_next = true;
    }

    nodes->size = write_index;
}

static yp_node_t *
parse_pattern(yp_parser_t *parser, bool top_pattern, yp_diagnostic_id_t diag_id);

// Accept any number of constants joined by :: delimiters.
static yp_node_t *
parse_pattern_constant_path(yp_parser_t *parser, yp_node_t *node) {
    // Now, if there are any :: operators that follow, parse them as constant
    // path nodes.
    while (accept(parser, YP_TOKEN_COLON_COLON)) {
        yp_token_t delimiter = parser->previous;
        expect(parser, YP_TOKEN_CONSTANT, YP_ERR_CONSTANT_PATH_COLON_COLON_CONSTANT);

        yp_node_t *child = (yp_node_t *) yp_constant_read_node_create(parser, &parser->previous);
        node = (yp_node_t *)yp_constant_path_node_create(parser, node, &delimiter, child);
    }

    // If there is a [ or ( that follows, then this is part of a larger pattern
    // expression. We'll parse the inner pattern here, then modify the returned
    // inner pattern with our constant path attached.
    if (!match_any_type_p(parser, 2, YP_TOKEN_BRACKET_LEFT, YP_TOKEN_PARENTHESIS_LEFT)) {
        return node;
    }

    yp_token_t opening;
    yp_token_t closing;
    yp_node_t *inner = NULL;

    if (accept(parser, YP_TOKEN_BRACKET_LEFT)) {
        opening = parser->previous;
        accept(parser, YP_TOKEN_NEWLINE);

        if (!accept(parser, YP_TOKEN_BRACKET_RIGHT)) {
            inner = parse_pattern(parser, true, YP_ERR_PATTERN_EXPRESSION_AFTER_BRACKET);
            accept(parser, YP_TOKEN_NEWLINE);
            expect(parser, YP_TOKEN_BRACKET_RIGHT, YP_ERR_PATTERN_TERM_BRACKET);
        }

        closing = parser->previous;
    } else {
        parser_lex(parser);
        opening = parser->previous;

        if (!accept(parser, YP_TOKEN_PARENTHESIS_RIGHT)) {
            inner = parse_pattern(parser, true, YP_ERR_PATTERN_EXPRESSION_AFTER_PAREN);
            expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_PATTERN_TERM_PAREN);
        }

        closing = parser->previous;
    }

    if (!inner) {
        // If there was no inner pattern, then we have something like Foo() or
        // Foo[]. In that case we'll create an array pattern with no requireds.
        return (yp_node_t *) yp_array_pattern_node_constant_create(parser, node, &opening, &closing);
    }

    // Now that we have the inner pattern, check to see if it's an array, find,
    // or hash pattern. If it is, then we'll attach our constant path to it if
    // it doesn't already have a constant. If it's not one of those node types
    // or it does have a constant, then we'll create an array pattern.
    switch (YP_NODE_TYPE(inner)) {
        case YP_ARRAY_PATTERN_NODE: {
            yp_array_pattern_node_t *pattern_node = (yp_array_pattern_node_t *) inner;

            if (pattern_node->constant == NULL) {
                pattern_node->base.location.start = node->location.start;
                pattern_node->base.location.end = closing.end;

                pattern_node->constant = node;
                pattern_node->opening_loc = YP_LOCATION_TOKEN_VALUE(&opening);
                pattern_node->closing_loc = YP_LOCATION_TOKEN_VALUE(&closing);

                return (yp_node_t *) pattern_node;
            }

            break;
        }
        case YP_FIND_PATTERN_NODE: {
            yp_find_pattern_node_t *pattern_node = (yp_find_pattern_node_t *) inner;

            if (pattern_node->constant == NULL) {
                pattern_node->base.location.start = node->location.start;
                pattern_node->base.location.end = closing.end;

                pattern_node->constant = node;
                pattern_node->opening_loc = YP_LOCATION_TOKEN_VALUE(&opening);
                pattern_node->closing_loc = YP_LOCATION_TOKEN_VALUE(&closing);

                return (yp_node_t *) pattern_node;
            }

            break;
        }
        case YP_HASH_PATTERN_NODE: {
            yp_hash_pattern_node_t *pattern_node = (yp_hash_pattern_node_t *) inner;

            if (pattern_node->constant == NULL) {
                pattern_node->base.location.start = node->location.start;
                pattern_node->base.location.end = closing.end;

                pattern_node->constant = node;
                pattern_node->opening_loc = YP_LOCATION_TOKEN_VALUE(&opening);
                pattern_node->closing_loc = YP_LOCATION_TOKEN_VALUE(&closing);

                return (yp_node_t *) pattern_node;
            }

            break;
        }
        default:
            break;
    }

    // If we got here, then we didn't return one of the inner patterns by
    // attaching its constant. In this case we'll create an array pattern and
    // attach our constant to it.
    yp_array_pattern_node_t *pattern_node = yp_array_pattern_node_constant_create(parser, node, &opening, &closing);
    yp_array_pattern_node_requireds_append(pattern_node, inner);
    return (yp_node_t *) pattern_node;
}

// Parse a rest pattern.
static yp_splat_node_t *
parse_pattern_rest(yp_parser_t *parser) {
    assert(parser->previous.type == YP_TOKEN_USTAR);
    yp_token_t operator = parser->previous;
    yp_node_t *name = NULL;

    // Rest patterns don't necessarily have a name associated with them. So we
    // will check for that here. If they do, then we'll add it to the local table
    // since this pattern will cause it to become a local variable.
    if (accept(parser, YP_TOKEN_IDENTIFIER)) {
        yp_token_t identifier = parser->previous;
        yp_parser_local_add_token(parser, &identifier);
        name = (yp_node_t *) yp_local_variable_target_node_create(parser, &identifier);
    }

    // Finally we can return the created node.
    return yp_splat_node_create(parser, &operator, name);
}

// Parse a keyword rest node.
static yp_node_t *
parse_pattern_keyword_rest(yp_parser_t *parser) {
    assert(parser->current.type == YP_TOKEN_USTAR_STAR);
    parser_lex(parser);

    yp_token_t operator = parser->previous;
    yp_node_t *value = NULL;

    if (accept(parser, YP_TOKEN_KEYWORD_NIL)) {
        return (yp_node_t *) yp_no_keywords_parameter_node_create(parser, &operator, &parser->previous);
    }

    if (accept(parser, YP_TOKEN_IDENTIFIER)) {
        yp_parser_local_add_token(parser, &parser->previous);
        value = (yp_node_t *) yp_local_variable_target_node_create(parser, &parser->previous);
    }

    return (yp_node_t *) yp_assoc_splat_node_create(parser, value, &operator);
}

// Parse a hash pattern.
static yp_hash_pattern_node_t *
parse_pattern_hash(yp_parser_t *parser, yp_node_t *first_assoc) {
    if (YP_NODE_TYPE_P(first_assoc, YP_ASSOC_NODE)) {
        if (!match_any_type_p(parser, 7, YP_TOKEN_COMMA, YP_TOKEN_KEYWORD_THEN, YP_TOKEN_BRACE_RIGHT, YP_TOKEN_BRACKET_RIGHT, YP_TOKEN_PARENTHESIS_RIGHT, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) {
            // Here we have a value for the first assoc in the list, so we will parse it
            // now and update the first assoc.
            yp_node_t *value = parse_pattern(parser, false, YP_ERR_PATTERN_EXPRESSION_AFTER_KEY);

            yp_assoc_node_t *assoc = (yp_assoc_node_t *) first_assoc;
            assoc->base.location.end = value->location.end;
            assoc->value = value;
        } else {
            yp_node_t *key = ((yp_assoc_node_t *) first_assoc)->key;

            if (YP_NODE_TYPE_P(key, YP_SYMBOL_NODE)) {
                const yp_location_t *value_loc = &((yp_symbol_node_t *) key)->value_loc;
                yp_parser_local_add_location(parser, value_loc->start, value_loc->end);
            }
        }
    }

    yp_node_list_t assocs = YP_EMPTY_NODE_LIST;
    yp_node_list_append(&assocs, first_assoc);

    // If there are any other assocs, then we'll parse them now.
    while (accept(parser, YP_TOKEN_COMMA)) {
        // Here we need to break to support trailing commas.
        if (match_any_type_p(parser, 6, YP_TOKEN_KEYWORD_THEN, YP_TOKEN_BRACE_RIGHT, YP_TOKEN_BRACKET_RIGHT, YP_TOKEN_PARENTHESIS_RIGHT, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) {
            break;
        }

        yp_node_t *assoc;

        if (match_type_p(parser, YP_TOKEN_USTAR_STAR)) {
            assoc = parse_pattern_keyword_rest(parser);
        } else {
            expect(parser, YP_TOKEN_LABEL, YP_ERR_PATTERN_LABEL_AFTER_COMMA);
            yp_node_t *key = (yp_node_t *) yp_symbol_node_label_create(parser, &parser->previous);
            yp_node_t *value = NULL;

            if (!match_any_type_p(parser, 7, YP_TOKEN_COMMA, YP_TOKEN_KEYWORD_THEN, YP_TOKEN_BRACE_RIGHT, YP_TOKEN_BRACKET_RIGHT, YP_TOKEN_PARENTHESIS_RIGHT, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) {
                value = parse_pattern(parser, false, YP_ERR_PATTERN_EXPRESSION_AFTER_KEY);
            } else {
                const yp_location_t *value_loc = &((yp_symbol_node_t *) key)->value_loc;
                yp_parser_local_add_location(parser, value_loc->start, value_loc->end);
            }

            yp_token_t operator = not_provided(parser);
            assoc = (yp_node_t *) yp_assoc_node_create(parser, key, &operator, value);
        }

        yp_node_list_append(&assocs, assoc);
    }

    yp_hash_pattern_node_t *node = yp_hash_pattern_node_node_list_create(parser, &assocs);
    free(assocs.nodes);

    return node;
}

// Parse a pattern expression primitive.
static yp_node_t *
parse_pattern_primitive(yp_parser_t *parser, yp_diagnostic_id_t diag_id) {
    switch (parser->current.type) {
        case YP_TOKEN_IDENTIFIER: {
            parser_lex(parser);
            yp_parser_local_add_token(parser, &parser->previous);
            return (yp_node_t *) yp_local_variable_target_node_create(parser, &parser->previous);
        }
        case YP_TOKEN_BRACKET_LEFT_ARRAY: {
            yp_token_t opening = parser->current;
            parser_lex(parser);

            if (accept(parser, YP_TOKEN_BRACKET_RIGHT)) {
                // If we have an empty array pattern, then we'll just return a new
                // array pattern node.
                return (yp_node_t *)yp_array_pattern_node_empty_create(parser, &opening, &parser->previous);
            }

            // Otherwise, we'll parse the inner pattern, then deal with it depending
            // on the type it returns.
            yp_node_t *inner = parse_pattern(parser, true, YP_ERR_PATTERN_EXPRESSION_AFTER_BRACKET);

            accept(parser, YP_TOKEN_NEWLINE);

            expect(parser, YP_TOKEN_BRACKET_RIGHT, YP_ERR_PATTERN_TERM_BRACKET);
            yp_token_t closing = parser->previous;

            switch (YP_NODE_TYPE(inner)) {
                case YP_ARRAY_PATTERN_NODE: {
                    yp_array_pattern_node_t *pattern_node = (yp_array_pattern_node_t *) inner;
                    if (pattern_node->opening_loc.start == NULL) {
                        pattern_node->base.location.start = opening.start;
                        pattern_node->base.location.end = closing.end;

                        pattern_node->opening_loc = YP_LOCATION_TOKEN_VALUE(&opening);
                        pattern_node->closing_loc = YP_LOCATION_TOKEN_VALUE(&closing);

                        return (yp_node_t *) pattern_node;
                    }

                    break;
                }
                case YP_FIND_PATTERN_NODE: {
                    yp_find_pattern_node_t *pattern_node = (yp_find_pattern_node_t *) inner;
                    if (pattern_node->opening_loc.start == NULL) {
                        pattern_node->base.location.start = opening.start;
                        pattern_node->base.location.end = closing.end;

                        pattern_node->opening_loc = YP_LOCATION_TOKEN_VALUE(&opening);
                        pattern_node->closing_loc = YP_LOCATION_TOKEN_VALUE(&closing);

                        return (yp_node_t *) pattern_node;
                    }

                    break;
                }
                default:
                    break;
            }

            yp_array_pattern_node_t *node = yp_array_pattern_node_empty_create(parser, &opening, &closing);
            yp_array_pattern_node_requireds_append(node, inner);
            return (yp_node_t *) node;
        }
        case YP_TOKEN_BRACE_LEFT: {
            bool previous_pattern_matching_newlines = parser->pattern_matching_newlines;
            parser->pattern_matching_newlines = false;

            yp_hash_pattern_node_t *node;
            yp_token_t opening = parser->current;
            parser_lex(parser);

            if (accept(parser, YP_TOKEN_BRACE_RIGHT)) {
                // If we have an empty hash pattern, then we'll just return a new hash
                // pattern node.
                node = yp_hash_pattern_node_empty_create(parser, &opening, &parser->previous);
            } else {
                yp_node_t *key;

                switch (parser->current.type) {
                    case YP_TOKEN_LABEL:
                        parser_lex(parser);
                        key = (yp_node_t *) yp_symbol_node_label_create(parser, &parser->previous);
                        break;
                    case YP_TOKEN_USTAR_STAR:
                        key = parse_pattern_keyword_rest(parser);
                        break;
                    case YP_TOKEN_STRING_BEGIN:
                        key = parse_expression(parser, YP_BINDING_POWER_MAX, YP_ERR_PATTERN_HASH_KEY);
                        if (!yp_symbol_node_label_p(key)) {
                            yp_diagnostic_list_append(&parser->error_list, key->location.start, key->location.end, YP_ERR_PATTERN_HASH_KEY_LABEL);
                        }

                        break;
                    default:
                        parser_lex(parser);
                        yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_PATTERN_HASH_KEY);
                        key = (yp_node_t *) yp_missing_node_create(parser, parser->previous.start, parser->previous.end);
                        break;
                }

                yp_token_t operator = not_provided(parser);
                node = parse_pattern_hash(parser, (yp_node_t *) yp_assoc_node_create(parser, key, &operator, NULL));

                accept(parser, YP_TOKEN_NEWLINE);
                expect(parser, YP_TOKEN_BRACE_RIGHT, YP_ERR_PATTERN_TERM_BRACE);
                yp_token_t closing = parser->previous;

                node->base.location.start = opening.start;
                node->base.location.end = closing.end;

                node->opening_loc = YP_LOCATION_TOKEN_VALUE(&opening);
                node->closing_loc = YP_LOCATION_TOKEN_VALUE(&closing);
            }

            parser->pattern_matching_newlines = previous_pattern_matching_newlines;
            return (yp_node_t *) node;
        }
        case YP_TOKEN_UDOT_DOT:
        case YP_TOKEN_UDOT_DOT_DOT: {
            yp_token_t operator = parser->current;
            parser_lex(parser);

            // Since we have a unary range operator, we need to parse the subsequent
            // expression as the right side of the range.
            switch (parser->current.type) {
                case YP_CASE_PRIMITIVE: {
                    yp_node_t *right = parse_expression(parser, YP_BINDING_POWER_MAX, YP_ERR_PATTERN_EXPRESSION_AFTER_RANGE);
                    return (yp_node_t *) yp_range_node_create(parser, NULL, &operator, right);
                }
                default: {
                    yp_diagnostic_list_append(&parser->error_list, operator.start, operator.end, YP_ERR_PATTERN_EXPRESSION_AFTER_RANGE);
                    yp_node_t *right = (yp_node_t *) yp_missing_node_create(parser, operator.start, operator.end);
                    return (yp_node_t *) yp_range_node_create(parser, NULL, &operator, right);
                }
            }
        }
        case YP_CASE_PRIMITIVE: {
            yp_node_t *node = parse_expression(parser, YP_BINDING_POWER_MAX, diag_id);

            // Now that we have a primitive, we need to check if it's part of a range.
            if (accept_any(parser, 2, YP_TOKEN_DOT_DOT, YP_TOKEN_DOT_DOT_DOT)) {
                yp_token_t operator = parser->previous;

                // Now that we have the operator, we need to check if this is followed
                // by another expression. If it is, then we will create a full range
                // node. Otherwise, we'll create an endless range.
                switch (parser->current.type) {
                    case YP_CASE_PRIMITIVE: {
                        yp_node_t *right = parse_expression(parser, YP_BINDING_POWER_MAX, YP_ERR_PATTERN_EXPRESSION_AFTER_RANGE);
                        return (yp_node_t *) yp_range_node_create(parser, node, &operator, right);
                    }
                    default:
                        return (yp_node_t *) yp_range_node_create(parser, node, &operator, NULL);
                }
            }

            return node;
        }
        case YP_TOKEN_CARET: {
            parser_lex(parser);
            yp_token_t operator = parser->previous;

            // At this point we have a pin operator. We need to check the subsequent
            // expression to determine if it's a variable or an expression.
            switch (parser->current.type) {
                case YP_TOKEN_IDENTIFIER: {
                    parser_lex(parser);
                    yp_node_t *variable = (yp_node_t *) yp_local_variable_read_node_create(parser, &parser->previous, 0);

                    return (yp_node_t *) yp_pinned_variable_node_create(parser, &operator, variable);
                }
                case YP_TOKEN_INSTANCE_VARIABLE: {
                    parser_lex(parser);
                    yp_node_t *variable = (yp_node_t *) yp_instance_variable_read_node_create(parser, &parser->previous);

                    return (yp_node_t *) yp_pinned_variable_node_create(parser, &operator, variable);
                }
                case YP_TOKEN_CLASS_VARIABLE: {
                    parser_lex(parser);
                    yp_node_t *variable = (yp_node_t *) yp_class_variable_read_node_create(parser, &parser->previous);

                    return (yp_node_t *) yp_pinned_variable_node_create(parser, &operator, variable);
                }
                case YP_TOKEN_GLOBAL_VARIABLE: {
                    parser_lex(parser);
                    yp_node_t *variable = (yp_node_t *) yp_global_variable_read_node_create(parser, &parser->previous);

                    return (yp_node_t *) yp_pinned_variable_node_create(parser, &operator, variable);
                }
                case YP_TOKEN_NUMBERED_REFERENCE: {
                    parser_lex(parser);
                    yp_node_t *variable = (yp_node_t *) yp_numbered_reference_read_node_create(parser, &parser->previous);

                    return (yp_node_t *) yp_pinned_variable_node_create(parser, &operator, variable);
                }
                case YP_TOKEN_BACK_REFERENCE: {
                    parser_lex(parser);
                    yp_node_t *variable = (yp_node_t *) yp_back_reference_read_node_create(parser, &parser->previous);

                    return (yp_node_t *) yp_pinned_variable_node_create(parser, &operator, variable);
                }
                case YP_TOKEN_PARENTHESIS_LEFT: {
                    bool previous_pattern_matching_newlines = parser->pattern_matching_newlines;
                    parser->pattern_matching_newlines = false;

                    yp_token_t lparen = parser->current;
                    parser_lex(parser);

                    yp_node_t *expression = parse_expression(parser, YP_BINDING_POWER_STATEMENT, YP_ERR_PATTERN_EXPRESSION_AFTER_PIN);
                    parser->pattern_matching_newlines = previous_pattern_matching_newlines;

                    accept(parser, YP_TOKEN_NEWLINE);
                    expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_PATTERN_TERM_PAREN);
                    return (yp_node_t *) yp_pinned_expression_node_create(parser, expression, &operator, &lparen, &parser->previous);
                }
                default: {
                    // If we get here, then we have a pin operator followed by something
                    // not understood. We'll create a missing node and return that.
                    yp_diagnostic_list_append(&parser->error_list, operator.start, operator.end, YP_ERR_PATTERN_EXPRESSION_AFTER_PIN);
                    yp_node_t *variable = (yp_node_t *) yp_missing_node_create(parser, operator.start, operator.end);
                    return (yp_node_t *) yp_pinned_variable_node_create(parser, &operator, variable);
                }
            }
        }
        case YP_TOKEN_UCOLON_COLON: {
            yp_token_t delimiter = parser->current;
            parser_lex(parser);

            expect(parser, YP_TOKEN_CONSTANT, YP_ERR_CONSTANT_PATH_COLON_COLON_CONSTANT);
            yp_node_t *child = (yp_node_t *) yp_constant_read_node_create(parser, &parser->previous);
            yp_constant_path_node_t *node = yp_constant_path_node_create(parser, NULL, &delimiter, child);

            return parse_pattern_constant_path(parser, (yp_node_t *)node);
        }
        case YP_TOKEN_CONSTANT: {
            yp_token_t constant = parser->current;
            parser_lex(parser);

            yp_node_t *node = (yp_node_t *) yp_constant_read_node_create(parser, &constant);
            return parse_pattern_constant_path(parser, node);
        }
        default:
            yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, diag_id);
            return (yp_node_t *) yp_missing_node_create(parser, parser->current.start, parser->current.end);
    }
}

// Parse any number of primitives joined by alternation and ended optionally by
// assignment.
static yp_node_t *
parse_pattern_primitives(yp_parser_t *parser, yp_diagnostic_id_t diag_id) {
    yp_node_t *node = NULL;

    do {
        yp_token_t operator = parser->previous;

        switch (parser->current.type) {
            case YP_TOKEN_IDENTIFIER:
            case YP_TOKEN_BRACKET_LEFT_ARRAY:
            case YP_TOKEN_BRACE_LEFT:
            case YP_TOKEN_CARET:
            case YP_TOKEN_CONSTANT:
            case YP_TOKEN_UCOLON_COLON:
            case YP_TOKEN_UDOT_DOT:
            case YP_TOKEN_UDOT_DOT_DOT:
            case YP_CASE_PRIMITIVE: {
                if (node == NULL) {
                    node = parse_pattern_primitive(parser, diag_id);
                } else {
                    yp_node_t *right = parse_pattern_primitive(parser, YP_ERR_PATTERN_EXPRESSION_AFTER_PIPE);
                    node = (yp_node_t *) yp_alternation_pattern_node_create(parser, node, right, &operator);
                }

                break;
            }
            case YP_TOKEN_PARENTHESIS_LEFT: {
                parser_lex(parser);
                if (node != NULL) {
                    yp_node_destroy(parser, node);
                }
                node = parse_pattern(parser, false, YP_ERR_PATTERN_EXPRESSION_AFTER_PAREN);

                expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_PATTERN_TERM_PAREN);
                break;
            }
            default: {
                yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, diag_id);
                yp_node_t *right = (yp_node_t *) yp_missing_node_create(parser, parser->current.start, parser->current.end);

                if (node == NULL) {
                    node = right;
                } else {
                    node = (yp_node_t *) yp_alternation_pattern_node_create(parser, node, right, &operator);
                }

                break;
            }
        }
    } while (accept(parser, YP_TOKEN_PIPE));

    // If we have an =>, then we are assigning this pattern to a variable.
    // In this case we should create an assignment node.
    while (accept(parser, YP_TOKEN_EQUAL_GREATER)) {
        yp_token_t operator = parser->previous;

        expect(parser, YP_TOKEN_IDENTIFIER, YP_ERR_PATTERN_IDENT_AFTER_HROCKET);
        yp_token_t identifier = parser->previous;
        yp_parser_local_add_token(parser, &identifier);

        yp_node_t *target = (yp_node_t *) yp_local_variable_target_node_create(parser, &identifier);
        node = (yp_node_t *) yp_capture_pattern_node_create(parser, node, target, &operator);
    }

    return node;
}

// Parse a pattern matching expression.
static yp_node_t *
parse_pattern(yp_parser_t *parser, bool top_pattern, yp_diagnostic_id_t diag_id) {
    yp_node_t *node = NULL;

    bool leading_rest = false;
    bool trailing_rest = false;

    switch (parser->current.type) {
        case YP_TOKEN_LABEL: {
            parser_lex(parser);
            yp_node_t *key = (yp_node_t *) yp_symbol_node_label_create(parser, &parser->previous);
            yp_token_t operator = not_provided(parser);

            return (yp_node_t *) parse_pattern_hash(parser, (yp_node_t *) yp_assoc_node_create(parser, key, &operator, NULL));
        }
        case YP_TOKEN_USTAR_STAR: {
            node = parse_pattern_keyword_rest(parser);
            return (yp_node_t *) parse_pattern_hash(parser, node);
        }
        case YP_TOKEN_USTAR: {
            if (top_pattern) {
                parser_lex(parser);
                node = (yp_node_t *) parse_pattern_rest(parser);
                leading_rest = true;
                break;
            }
        }
        /* fallthrough */
        default:
            node = parse_pattern_primitives(parser, diag_id);
            break;
    }

    // If we got a dynamic label symbol, then we need to treat it like the
    // beginning of a hash pattern.
    if (yp_symbol_node_label_p(node)) {
        yp_token_t operator = not_provided(parser);
        return (yp_node_t *) parse_pattern_hash(parser, (yp_node_t *) yp_assoc_node_create(parser, node, &operator, NULL));
    }

    if (top_pattern && match_type_p(parser, YP_TOKEN_COMMA)) {
        // If we have a comma, then we are now parsing either an array pattern or a
        // find pattern. We need to parse all of the patterns, put them into a big
        // list, and then determine which type of node we have.
        yp_node_list_t nodes = YP_EMPTY_NODE_LIST;
        yp_node_list_append(&nodes, node);

        // Gather up all of the patterns into the list.
        while (accept(parser, YP_TOKEN_COMMA)) {
            // Break early here in case we have a trailing comma.
            if (match_any_type_p(parser, 5, YP_TOKEN_KEYWORD_THEN, YP_TOKEN_BRACE_RIGHT, YP_TOKEN_BRACKET_RIGHT, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) {
                break;
            }

            if (accept(parser, YP_TOKEN_USTAR)) {
                node = (yp_node_t *) parse_pattern_rest(parser);

                // If we have already parsed a splat pattern, then this is an error. We
                // will continue to parse the rest of the patterns, but we will indicate
                // it as an error.
                if (trailing_rest) {
                    yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_PATTERN_REST);
                }

                trailing_rest = true;
            } else {
                node = parse_pattern_primitives(parser, YP_ERR_PATTERN_EXPRESSION_AFTER_COMMA);
            }

            yp_node_list_append(&nodes, node);
        }

        // If the first pattern and the last pattern are rest patterns, then we will
        // call this a find pattern, regardless of how many rest patterns are in
        // between because we know we already added the appropriate errors.
        // Otherwise we will create an array pattern.
        if (YP_NODE_TYPE_P(nodes.nodes[0], YP_SPLAT_NODE) && YP_NODE_TYPE_P(nodes.nodes[nodes.size - 1], YP_SPLAT_NODE)) {
            node = (yp_node_t *) yp_find_pattern_node_create(parser, &nodes);
        } else {
            node = (yp_node_t *) yp_array_pattern_node_node_list_create(parser, &nodes);
        }

        free(nodes.nodes);
    } else if (leading_rest) {
        // Otherwise, if we parsed a single splat pattern, then we know we have an
        // array pattern, so we can go ahead and create that node.
        node = (yp_node_t *) yp_array_pattern_node_rest_create(parser, node);
    }

    return node;
}

// Incorporate a negative sign into a numeric node by subtracting 1 character
// from its start bounds. If it's a compound node, then we will recursively
// apply this function to its value.
static inline void
parse_negative_numeric(yp_node_t *node) {
    switch (YP_NODE_TYPE(node)) {
        case YP_INTEGER_NODE:
        case YP_FLOAT_NODE:
            node->location.start--;
            break;
        case YP_RATIONAL_NODE:
            node->location.start--;
            parse_negative_numeric(((yp_rational_node_t *) node)->numeric);
            break;
        case YP_IMAGINARY_NODE:
            node->location.start--;
            parse_negative_numeric(((yp_imaginary_node_t *) node)->numeric);
            break;
        default:
            assert(false && "unreachable");
            break;
    }
}

// Parse an expression that begins with the previous node that we just lexed.
static inline yp_node_t *
parse_expression_prefix(yp_parser_t *parser, yp_binding_power_t binding_power) {
    switch (parser->current.type) {
        case YP_TOKEN_BRACKET_LEFT_ARRAY: {
            parser_lex(parser);

            yp_array_node_t *array = yp_array_node_create(parser, &parser->previous);
            yp_accepts_block_stack_push(parser, true);
            bool parsed_bare_hash = false;

            while (!match_any_type_p(parser, 2, YP_TOKEN_BRACKET_RIGHT, YP_TOKEN_EOF)) {
                // Handle the case where we don't have a comma and we have a newline followed by a right bracket.
                if (accept(parser, YP_TOKEN_NEWLINE) && match_type_p(parser, YP_TOKEN_BRACKET_RIGHT)) {
                    break;
                }

                if (yp_array_node_size(array) != 0) {
                    expect(parser, YP_TOKEN_COMMA, YP_ERR_ARRAY_SEPARATOR);
                }

                // If we have a right bracket immediately following a comma, this is
                // allowed since it's a trailing comma. In this case we can break out of
                // the loop.
                if (match_type_p(parser, YP_TOKEN_BRACKET_RIGHT)) break;

                yp_node_t *element;

                if (accept(parser, YP_TOKEN_USTAR)) {
                    yp_token_t operator = parser->previous;
                    yp_node_t *expression = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_ARRAY_EXPRESSION_AFTER_STAR);
                    element = (yp_node_t *) yp_splat_node_create(parser, &operator, expression);
                } else if (match_any_type_p(parser, 2, YP_TOKEN_LABEL, YP_TOKEN_USTAR_STAR)) {
                    if (parsed_bare_hash) {
                        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_EXPRESSION_BARE_HASH);
                    }

                    yp_keyword_hash_node_t *hash = yp_keyword_hash_node_create(parser);
                    element = (yp_node_t *)hash;

                    if (!match_any_type_p(parser, 8, YP_TOKEN_EOF, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON, YP_TOKEN_EOF, YP_TOKEN_BRACE_RIGHT, YP_TOKEN_BRACKET_RIGHT, YP_TOKEN_KEYWORD_DO, YP_TOKEN_PARENTHESIS_RIGHT)) {
                        parse_assocs(parser, (yp_node_t *) hash);
                    }

                    parsed_bare_hash = true;
                } else {
                    element = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_ARRAY_EXPRESSION);

                    if (yp_symbol_node_label_p(element) || accept(parser, YP_TOKEN_EQUAL_GREATER)) {
                        if (parsed_bare_hash) {
                            yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_EXPRESSION_BARE_HASH);
                        }

                        yp_keyword_hash_node_t *hash = yp_keyword_hash_node_create(parser);

                        yp_token_t operator;
                        if (parser->previous.type == YP_TOKEN_EQUAL_GREATER) {
                            operator = parser->previous;
                        } else {
                            operator = not_provided(parser);
                        }

                        yp_node_t *value = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_HASH_VALUE);
                        yp_node_t *assoc = (yp_node_t *) yp_assoc_node_create(parser, element, &operator, value);
                        yp_keyword_hash_node_elements_append(hash, assoc);

                        element = (yp_node_t *)hash;
                        if (accept(parser, YP_TOKEN_COMMA) && !match_type_p(parser, YP_TOKEN_BRACKET_RIGHT)) {
                            parse_assocs(parser, (yp_node_t *) hash);
                        }

                        parsed_bare_hash = true;
                    }
                }

                yp_array_node_elements_append(array, element);
                if (YP_NODE_TYPE_P(element, YP_MISSING_NODE)) break;
            }

            accept(parser, YP_TOKEN_NEWLINE);
            expect(parser, YP_TOKEN_BRACKET_RIGHT, YP_ERR_ARRAY_TERM);
            yp_array_node_close_set(array, &parser->previous);
            yp_accepts_block_stack_pop(parser);

            return (yp_node_t *) array;
        }
        case YP_TOKEN_PARENTHESIS_LEFT:
        case YP_TOKEN_PARENTHESIS_LEFT_PARENTHESES: {
            yp_token_t opening = parser->current;
            parser_lex(parser);
            while (accept_any(parser, 2, YP_TOKEN_SEMICOLON, YP_TOKEN_NEWLINE));

            // If this is the end of the file or we match a right parenthesis, then
            // we have an empty parentheses node, and we can immediately return.
            if (match_any_type_p(parser, 2, YP_TOKEN_PARENTHESIS_RIGHT, YP_TOKEN_EOF)) {
                expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_EXPECT_RPAREN);
                return (yp_node_t *) yp_parentheses_node_create(parser, &opening, NULL, &parser->previous);
            }

            // Otherwise, we're going to parse the first statement in the list of
            // statements within the parentheses.
            yp_accepts_block_stack_push(parser, true);
            yp_node_t *statement = parse_expression(parser, YP_BINDING_POWER_STATEMENT, YP_ERR_CANNOT_PARSE_EXPRESSION);
            while (accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON));

            // If we hit a right parenthesis, then we're done parsing the parentheses
            // node, and we can check which kind of node we should return.
            if (match_type_p(parser, YP_TOKEN_PARENTHESIS_RIGHT)) {
                if (opening.type == YP_TOKEN_PARENTHESIS_LEFT_PARENTHESES) {
                    lex_state_set(parser, YP_LEX_STATE_ENDARG);
                }
                parser_lex(parser);
                yp_accepts_block_stack_pop(parser);

                // If we have a single statement and are ending on a right parenthesis,
                // then we need to check if this is possibly a multiple target node.
                if (binding_power == YP_BINDING_POWER_STATEMENT && YP_NODE_TYPE_P(statement, YP_MULTI_TARGET_NODE)) {
                    yp_node_t *target;
                    yp_multi_target_node_t *multi_target = (yp_multi_target_node_t *) statement;

                    yp_location_t lparen_loc = YP_LOCATION_TOKEN_VALUE(&opening);
                    yp_location_t rparen_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);

                    if (multi_target->lparen_loc.start == NULL) {
                        multi_target->base.location.start = lparen_loc.start;
                        multi_target->base.location.end = rparen_loc.end;
                        multi_target->lparen_loc = lparen_loc;
                        multi_target->rparen_loc = rparen_loc;
                        target = (yp_node_t *) multi_target;
                    } else {
                        yp_multi_target_node_t *parent_target = yp_multi_target_node_create(parser);
                        yp_multi_target_node_targets_append(parent_target, (yp_node_t *) multi_target);
                        target = (yp_node_t *) parent_target;
                    }

                    return parse_targets(parser, target, YP_BINDING_POWER_INDEX);
                }

                // If we have a single statement and are ending on a right parenthesis
                // and we didn't return a multiple assignment node, then we can return a
                // regular parentheses node now.
                yp_statements_node_t *statements = yp_statements_node_create(parser);
                yp_statements_node_body_append(statements, statement);

                return (yp_node_t *) yp_parentheses_node_create(parser, &opening, (yp_node_t *) statements, &parser->previous);
            }

            // If we have more than one statement in the set of parentheses, then we
            // are going to parse all of them as a list of statements. We'll do that
            // here.
            context_push(parser, YP_CONTEXT_PARENS);
            yp_statements_node_t *statements = yp_statements_node_create(parser);
            yp_statements_node_body_append(statements, statement);

            while (!match_type_p(parser, YP_TOKEN_PARENTHESIS_RIGHT)) {
                // Ignore semicolon without statements before them
                if (accept_any(parser, 2, YP_TOKEN_SEMICOLON, YP_TOKEN_NEWLINE)) continue;

                yp_node_t *node = parse_expression(parser, YP_BINDING_POWER_STATEMENT, YP_ERR_CANNOT_PARSE_EXPRESSION);
                yp_statements_node_body_append(statements, node);

                // If we're recovering from a syntax error, then we need to stop parsing the
                // statements now.
                if (parser->recovering) {
                    // If this is the level of context where the recovery has happened, then
                    // we can mark the parser as done recovering.
                    if (match_type_p(parser, YP_TOKEN_PARENTHESIS_RIGHT)) parser->recovering = false;
                    break;
                }

                if (!accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) break;
            }

            context_pop(parser);
            yp_accepts_block_stack_pop(parser);
            expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_EXPECT_RPAREN);

            return (yp_node_t *) yp_parentheses_node_create(parser, &opening, (yp_node_t *) statements, &parser->previous);
        }
        case YP_TOKEN_BRACE_LEFT: {
            yp_accepts_block_stack_push(parser, true);
            parser_lex(parser);
            yp_hash_node_t *node = yp_hash_node_create(parser, &parser->previous);

            if (!match_any_type_p(parser, 2, YP_TOKEN_BRACE_RIGHT, YP_TOKEN_EOF)) {
                parse_assocs(parser, (yp_node_t *) node);
                accept(parser, YP_TOKEN_NEWLINE);
            }

            yp_accepts_block_stack_pop(parser);
            expect(parser, YP_TOKEN_BRACE_RIGHT, YP_ERR_HASH_TERM);
            yp_hash_node_closing_loc_set(node, &parser->previous);

            return (yp_node_t *) node;
        }
        case YP_TOKEN_CHARACTER_LITERAL: {
            parser_lex(parser);

            yp_token_t opening = parser->previous;
            opening.type = YP_TOKEN_STRING_BEGIN;
            opening.end = opening.start + 1;

            yp_token_t content = parser->previous;
            content.type = YP_TOKEN_STRING_CONTENT;
            content.start = content.start + 1;

            yp_token_t closing = not_provided(parser);

            return (yp_node_t *) yp_char_literal_node_create_and_unescape(parser, &opening, &content, &closing, YP_UNESCAPE_ALL);
        }
        case YP_TOKEN_CLASS_VARIABLE: {
            parser_lex(parser);
            yp_node_t *node = (yp_node_t *) yp_class_variable_read_node_create(parser, &parser->previous);

            if (binding_power == YP_BINDING_POWER_STATEMENT && match_type_p(parser, YP_TOKEN_COMMA)) {
                node = parse_targets(parser, node, YP_BINDING_POWER_INDEX);
            }

            return node;
        }
        case YP_TOKEN_CONSTANT: {
            parser_lex(parser);
            yp_token_t constant = parser->previous;

            // If a constant is immediately followed by parentheses, then this is in
            // fact a method call, not a constant read.
            if (
                match_type_p(parser, YP_TOKEN_PARENTHESIS_LEFT) ||
                (binding_power <= YP_BINDING_POWER_ASSIGNMENT && (token_begins_expression_p(parser->current.type) || match_any_type_p(parser, 3, YP_TOKEN_UAMPERSAND, YP_TOKEN_USTAR, YP_TOKEN_USTAR_STAR))) ||
                (yp_accepts_block_stack_p(parser) && match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_DO, YP_TOKEN_BRACE_LEFT))
            ) {
                yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;
                parse_arguments_list(parser, &arguments, true);
                return (yp_node_t *) yp_call_node_fcall_create(parser, &constant, &arguments);
            }

            yp_node_t *node = (yp_node_t *) yp_constant_read_node_create(parser, &parser->previous);

            if ((binding_power == YP_BINDING_POWER_STATEMENT) && match_type_p(parser, YP_TOKEN_COMMA)) {
                // If we get here, then we have a comma immediately following a
                // constant, so we're going to parse this as a multiple assignment.
                node = parse_targets(parser, node, YP_BINDING_POWER_INDEX);
            }

            return node;
        }
        case YP_TOKEN_UCOLON_COLON: {
            parser_lex(parser);

            yp_token_t delimiter = parser->previous;
            expect(parser, YP_TOKEN_CONSTANT, YP_ERR_CONSTANT_PATH_COLON_COLON_CONSTANT);

            yp_node_t *constant = (yp_node_t *) yp_constant_read_node_create(parser, &parser->previous);
            yp_node_t *node = (yp_node_t *)yp_constant_path_node_create(parser, NULL, &delimiter, constant);

            if ((binding_power == YP_BINDING_POWER_STATEMENT) && match_type_p(parser, YP_TOKEN_COMMA)) {
                node = parse_targets(parser, node, YP_BINDING_POWER_INDEX);
            }

            return node;
        }
        case YP_TOKEN_UDOT_DOT:
        case YP_TOKEN_UDOT_DOT_DOT: {
            yp_token_t operator = parser->current;
            parser_lex(parser);

            yp_node_t *right = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
            return (yp_node_t *) yp_range_node_create(parser, NULL, &operator, right);
        }
        case YP_TOKEN_FLOAT:
            parser_lex(parser);
            return (yp_node_t *) yp_float_node_create(parser, &parser->previous);
        case YP_TOKEN_FLOAT_IMAGINARY:
            parser_lex(parser);
            return (yp_node_t *) yp_float_node_imaginary_create(parser, &parser->previous);
        case YP_TOKEN_FLOAT_RATIONAL:
            parser_lex(parser);
            return (yp_node_t *) yp_float_node_rational_create(parser, &parser->previous);
        case YP_TOKEN_FLOAT_RATIONAL_IMAGINARY:
            parser_lex(parser);
            return (yp_node_t *) yp_float_node_rational_imaginary_create(parser, &parser->previous);
        case YP_TOKEN_NUMBERED_REFERENCE: {
            parser_lex(parser);
            yp_node_t *node = (yp_node_t *) yp_numbered_reference_read_node_create(parser, &parser->previous);

            if (binding_power == YP_BINDING_POWER_STATEMENT && match_type_p(parser, YP_TOKEN_COMMA)) {
                node = parse_targets(parser, node, YP_BINDING_POWER_INDEX);
            }

            return node;
        }
        case YP_TOKEN_GLOBAL_VARIABLE: {
            parser_lex(parser);
            yp_node_t *node = (yp_node_t *) yp_global_variable_read_node_create(parser, &parser->previous);

            if (binding_power == YP_BINDING_POWER_STATEMENT && match_type_p(parser, YP_TOKEN_COMMA)) {
                node = parse_targets(parser, node, YP_BINDING_POWER_INDEX);
            }

            return node;
        }
        case YP_TOKEN_BACK_REFERENCE: {
            parser_lex(parser);
            yp_node_t *node = (yp_node_t *) yp_back_reference_read_node_create(parser, &parser->previous);

            if (binding_power == YP_BINDING_POWER_STATEMENT && match_type_p(parser, YP_TOKEN_COMMA)) {
                node = parse_targets(parser, node, YP_BINDING_POWER_INDEX);
            }

            return node;
        }
        case YP_TOKEN_IDENTIFIER: {
            parser_lex(parser);
            yp_token_t identifier = parser->previous;
            yp_node_t *node = parse_variable_call(parser);

            if (YP_NODE_TYPE_P(node, YP_CALL_NODE)) {
                // If parse_variable_call returned with a call node, then we
                // know the identifier is not in the local table. In that case
                // we need to check if there are arguments following the
                // identifier.
                yp_call_node_t *call = (yp_call_node_t *) node;
                yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;

                if (parse_arguments_list(parser, &arguments, true)) {
                    // Since we found arguments, we need to turn off the
                    // variable call bit in the flags.
                    call->base.flags &= (yp_node_flags_t) ~YP_CALL_NODE_FLAGS_VARIABLE_CALL;

                    call->opening_loc = arguments.opening_loc;
                    call->arguments = arguments.arguments;
                    call->closing_loc = arguments.closing_loc;
                    call->block = arguments.block;

                    if (arguments.block != NULL) {
                        call->base.location.end = arguments.block->base.location.end;
                    } else if (arguments.closing_loc.start == NULL) {
                        if (arguments.arguments != NULL) {
                            call->base.location.end = arguments.arguments->base.location.end;
                        } else {
                            call->base.location.end = call->message_loc.end;
                        }
                    } else {
                        call->base.location.end = arguments.closing_loc.end;
                    }
                }
            } else {
                // Otherwise, we know the identifier is in the local table. This
                // can still be a method call if it is followed by arguments or
                // a block, so we need to check for that here.
                if (
                    (binding_power <= YP_BINDING_POWER_ASSIGNMENT && (token_begins_expression_p(parser->current.type) || match_any_type_p(parser, 3, YP_TOKEN_UAMPERSAND, YP_TOKEN_USTAR, YP_TOKEN_USTAR_STAR))) ||
                    (yp_accepts_block_stack_p(parser) && match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_DO, YP_TOKEN_BRACE_LEFT))
                ) {
                    yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;
                    parse_arguments_list(parser, &arguments, true);

                    yp_call_node_t *fcall = yp_call_node_fcall_create(parser, &identifier, &arguments);
                    yp_node_destroy(parser, node);
                    return (yp_node_t *) fcall;
                }
            }

            if ((binding_power == YP_BINDING_POWER_STATEMENT) && match_type_p(parser, YP_TOKEN_COMMA)) {
                node = parse_targets(parser, node, YP_BINDING_POWER_INDEX);
            }

            return node;
        }
        case YP_TOKEN_HEREDOC_START: {
            assert(parser->lex_modes.current->mode == YP_LEX_HEREDOC);
            yp_heredoc_quote_t quote = parser->lex_modes.current->as.heredoc.quote;
            yp_heredoc_indent_t indent = parser->lex_modes.current->as.heredoc.indent;

            yp_node_t *node;
            if (quote == YP_HEREDOC_QUOTE_BACKTICK) {
                node = (yp_node_t *) yp_interpolated_xstring_node_create(parser, &parser->current, &parser->current);
            } else {
                node = (yp_node_t *) yp_interpolated_string_node_create(parser, &parser->current, NULL, &parser->current);
            }

            parser_lex(parser);
            yp_node_t *part;

            while (!match_any_type_p(parser, 2, YP_TOKEN_HEREDOC_END, YP_TOKEN_EOF)) {
                if ((part = parse_string_part(parser)) == NULL) continue;

                if (quote == YP_HEREDOC_QUOTE_BACKTICK) {
                    yp_interpolated_xstring_node_append((yp_interpolated_x_string_node_t *) node, part);
                } else {
                    yp_interpolated_string_node_append((yp_interpolated_string_node_t *) node, part);
                }
            }

            lex_state_set(parser, YP_LEX_STATE_END);
            expect(parser, YP_TOKEN_HEREDOC_END, YP_ERR_HEREDOC_TERM);

            if (quote == YP_HEREDOC_QUOTE_BACKTICK) {
                assert(YP_NODE_TYPE_P(node, YP_INTERPOLATED_X_STRING_NODE));
                yp_interpolated_xstring_node_closing_set(((yp_interpolated_x_string_node_t *) node), &parser->previous);
                node->location = ((yp_interpolated_x_string_node_t *) node)->opening_loc;
            } else {
                assert(YP_NODE_TYPE_P(node, YP_INTERPOLATED_STRING_NODE));
                yp_interpolated_string_node_closing_set((yp_interpolated_string_node_t *) node, &parser->previous);
                node->location = ((yp_interpolated_string_node_t *) node)->opening_loc;
            }

            // If this is a heredoc that is indented with a ~, then we need to dedent
            // each line by the common leading whitespace.
            if (indent == YP_HEREDOC_INDENT_TILDE) {
                parse_heredoc_dedent(parser, node, quote);
            }

            // If there's a string immediately following this heredoc, then it's a
            // concatenatation. In this case we'll parse the next string and create a
            // node in the tree that concatenates the two strings.
            if (parser->current.type == YP_TOKEN_STRING_BEGIN) {
                return (yp_node_t *) yp_string_concat_node_create(
                    parser,
                    node,
                    parse_expression(parser, YP_BINDING_POWER_CALL, YP_ERR_CANNOT_PARSE_EXPRESSION)
                );
            } else {
                return node;
            }
        }
        case YP_TOKEN_INSTANCE_VARIABLE: {
            parser_lex(parser);
            yp_node_t *node = (yp_node_t *) yp_instance_variable_read_node_create(parser, &parser->previous);

            if (binding_power == YP_BINDING_POWER_STATEMENT && match_type_p(parser, YP_TOKEN_COMMA)) {
                node = parse_targets(parser, node, YP_BINDING_POWER_INDEX);
            }

            return node;
        }
        case YP_TOKEN_INTEGER:
            parser_lex(parser);
            return (yp_node_t *) yp_integer_node_create(parser, &parser->previous);
        case YP_TOKEN_INTEGER_IMAGINARY:
            parser_lex(parser);
            return (yp_node_t *) yp_integer_node_imaginary_create(parser, &parser->previous);
        case YP_TOKEN_INTEGER_RATIONAL:
            parser_lex(parser);
            return (yp_node_t *) yp_integer_node_rational_create(parser, &parser->previous);
        case YP_TOKEN_INTEGER_RATIONAL_IMAGINARY:
            parser_lex(parser);
            return (yp_node_t *) yp_integer_node_rational_imaginary_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD___ENCODING__:
            parser_lex(parser);
            return (yp_node_t *) yp_source_encoding_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD___FILE__:
            parser_lex(parser);
            return (yp_node_t *) yp_source_file_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD___LINE__:
            parser_lex(parser);
            return (yp_node_t *) yp_source_line_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD_ALIAS: {
            parser_lex(parser);
            yp_token_t keyword = parser->previous;

            yp_node_t *new_name = parse_alias_argument(parser, true);
            yp_node_t *old_name = parse_alias_argument(parser, false);

            switch (YP_NODE_TYPE(new_name)) {
                case YP_SYMBOL_NODE:
                case YP_INTERPOLATED_SYMBOL_NODE: {
                    if (!YP_NODE_TYPE_P(old_name, YP_SYMBOL_NODE) && !YP_NODE_TYPE_P(old_name, YP_INTERPOLATED_SYMBOL_NODE)) {
                        yp_diagnostic_list_append(&parser->error_list, old_name->location.start, old_name->location.end, YP_ERR_ALIAS_ARGUMENT);
                    }
                    break;
                }
                case YP_BACK_REFERENCE_READ_NODE:
                case YP_NUMBERED_REFERENCE_READ_NODE:
                case YP_GLOBAL_VARIABLE_READ_NODE: {
                    if (YP_NODE_TYPE_P(old_name, YP_BACK_REFERENCE_READ_NODE) || YP_NODE_TYPE_P(old_name, YP_NUMBERED_REFERENCE_READ_NODE) || YP_NODE_TYPE_P(old_name, YP_GLOBAL_VARIABLE_READ_NODE)) {
                        if (YP_NODE_TYPE_P(old_name, YP_NUMBERED_REFERENCE_READ_NODE)) {
                            yp_diagnostic_list_append(&parser->error_list, old_name->location.start, old_name->location.end, YP_ERR_ALIAS_ARGUMENT);
                        }
                    } else {
                        yp_diagnostic_list_append(&parser->error_list, old_name->location.start, old_name->location.end, YP_ERR_ALIAS_ARGUMENT);
                    }
                    break;
                }
                default:
                    break;
            }

            return (yp_node_t *) yp_alias_node_create(parser, &keyword, new_name, old_name);
        }
        case YP_TOKEN_KEYWORD_CASE: {
            parser_lex(parser);
            yp_token_t case_keyword = parser->previous;
            yp_node_t *predicate = NULL;

            if (
                accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON) ||
                match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_WHEN, YP_TOKEN_KEYWORD_IN, YP_TOKEN_KEYWORD_END) ||
                !token_begins_expression_p(parser->current.type)
            ) {
                predicate = NULL;
            } else {
                predicate = parse_expression(parser, YP_BINDING_POWER_COMPOSITION, YP_ERR_CASE_EXPRESSION_AFTER_CASE);
                while (accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON));
            }

            if (accept(parser, YP_TOKEN_KEYWORD_END)) {
                return (yp_node_t *) yp_case_node_create(parser, &case_keyword, predicate, NULL, &parser->previous);
            }

            // At this point we can create a case node, though we don't yet know if it
            // is a case-in or case-when node.
            yp_token_t end_keyword = not_provided(parser);
            yp_case_node_t *case_node = yp_case_node_create(parser, &case_keyword, predicate, NULL, &end_keyword);

            if (match_type_p(parser, YP_TOKEN_KEYWORD_WHEN)) {
                // At this point we've seen a when keyword, so we know this is a
                // case-when node. We will continue to parse the when nodes until we hit
                // the end of the list.
                while (accept(parser, YP_TOKEN_KEYWORD_WHEN)) {
                    yp_token_t when_keyword = parser->previous;
                    yp_when_node_t *when_node = yp_when_node_create(parser, &when_keyword);

                    do {
                        if (accept(parser, YP_TOKEN_USTAR)) {
                            yp_token_t operator = parser->previous;
                            yp_node_t *expression = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_EXPECT_EXPRESSION_AFTER_STAR);

                            yp_splat_node_t *splat_node = yp_splat_node_create(parser, &operator, expression);
                            yp_when_node_conditions_append(when_node, (yp_node_t *) splat_node);

                            if (YP_NODE_TYPE_P(expression, YP_MISSING_NODE)) break;
                        } else {
                            yp_node_t *condition = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_CASE_EXPRESSION_AFTER_WHEN);
                            yp_when_node_conditions_append(when_node, condition);

                            if (YP_NODE_TYPE_P(condition, YP_MISSING_NODE)) break;
                        }
                    } while (accept(parser, YP_TOKEN_COMMA));

                    if (accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) {
                        accept(parser, YP_TOKEN_KEYWORD_THEN);
                    } else {
                        expect(parser, YP_TOKEN_KEYWORD_THEN, YP_ERR_EXPECT_WHEN_DELIMITER);
                    }

                    if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_WHEN, YP_TOKEN_KEYWORD_ELSE, YP_TOKEN_KEYWORD_END)) {
                        yp_statements_node_t *statements = parse_statements(parser, YP_CONTEXT_CASE_WHEN);
                        if (statements != NULL) {
                            yp_when_node_statements_set(when_node, statements);
                        }
                    }

                    yp_case_node_condition_append(case_node, (yp_node_t *) when_node);
                }
            } else {
                // At this point we expect that we're parsing a case-in node. We will
                // continue to parse the in nodes until we hit the end of the list.
                while (match_type_p(parser, YP_TOKEN_KEYWORD_IN)) {
                    bool previous_pattern_matching_newlines = parser->pattern_matching_newlines;
                    parser->pattern_matching_newlines = true;

                    lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);
                    parser->command_start = false;
                    parser_lex(parser);

                    yp_token_t in_keyword = parser->previous;
                    yp_node_t *pattern = parse_pattern(parser, true, YP_ERR_PATTERN_EXPRESSION_AFTER_IN);
                    parser->pattern_matching_newlines = previous_pattern_matching_newlines;

                    // Since we're in the top-level of the case-in node we need to check
                    // for guard clauses in the form of `if` or `unless` statements.
                    if (accept(parser, YP_TOKEN_KEYWORD_IF_MODIFIER)) {
                        yp_token_t keyword = parser->previous;
                        yp_node_t *predicate = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_CONDITIONAL_IF_PREDICATE);
                        pattern = (yp_node_t *) yp_if_node_modifier_create(parser, pattern, &keyword, predicate);
                    } else if (accept(parser, YP_TOKEN_KEYWORD_UNLESS_MODIFIER)) {
                        yp_token_t keyword = parser->previous;
                        yp_node_t *predicate = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_CONDITIONAL_UNLESS_PREDICATE);
                        pattern = (yp_node_t *) yp_unless_node_modifier_create(parser, pattern, &keyword, predicate);
                    }

                    // Now we need to check for the terminator of the in node's pattern.
                    // It can be a newline or semicolon optionally followed by a `then`
                    // keyword.
                    yp_token_t then_keyword;
                    if (accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON)) {
                        if (accept(parser, YP_TOKEN_KEYWORD_THEN)) {
                            then_keyword = parser->previous;
                        } else {
                            then_keyword = not_provided(parser);
                        }
                    } else {
                        expect(parser, YP_TOKEN_KEYWORD_THEN, YP_ERR_EXPECT_WHEN_DELIMITER);
                        then_keyword = parser->previous;
                    }

                    // Now we can actually parse the statements associated with the in
                    // node.
                    yp_statements_node_t *statements;
                    if (match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_IN, YP_TOKEN_KEYWORD_ELSE, YP_TOKEN_KEYWORD_END)) {
                        statements = NULL;
                    } else {
                        statements = parse_statements(parser, YP_CONTEXT_CASE_IN);
                    }

                    // Now that we have the full pattern and statements, we can create the
                    // node and attach it to the case node.
                    yp_node_t *condition = (yp_node_t *) yp_in_node_create(parser, pattern, statements, &in_keyword, &then_keyword);
                    yp_case_node_condition_append(case_node, condition);
                }
            }

            accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
            if (accept(parser, YP_TOKEN_KEYWORD_ELSE)) {
                if (case_node->conditions.size < 1) {
                    yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_CASE_LONELY_ELSE);
                }

                yp_token_t else_keyword = parser->previous;
                yp_else_node_t *else_node;

                if (!match_type_p(parser, YP_TOKEN_KEYWORD_END)) {
                    else_node = yp_else_node_create(parser, &else_keyword, parse_statements(parser, YP_CONTEXT_ELSE), &parser->current);
                } else {
                    else_node = yp_else_node_create(parser, &else_keyword, NULL, &parser->current);
                }

                yp_case_node_consequent_set(case_node, else_node);
            }

            expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_CASE_TERM);
            yp_case_node_end_keyword_loc_set(case_node, &parser->previous);
            return (yp_node_t *) case_node;
        }
        case YP_TOKEN_KEYWORD_BEGIN: {
            parser_lex(parser);

            yp_token_t begin_keyword = parser->previous;
            accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
            yp_statements_node_t *begin_statements = NULL;

            if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE, YP_TOKEN_KEYWORD_END)) {
                yp_accepts_block_stack_push(parser, true);
                begin_statements = parse_statements(parser, YP_CONTEXT_BEGIN);
                yp_accepts_block_stack_pop(parser);
                accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
            }

            yp_begin_node_t *begin_node = yp_begin_node_create(parser, &begin_keyword, begin_statements);
            parse_rescues(parser, begin_node);

            expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_BEGIN_TERM);
            begin_node->base.location.end = parser->previous.end;
            yp_begin_node_end_keyword_set(begin_node, &parser->previous);

            if ((begin_node->else_clause != NULL) && (begin_node->rescue_clause == NULL)) {
                yp_diagnostic_list_append(
                    &parser->error_list,
                    begin_node->else_clause->base.location.start,
                    begin_node->else_clause->base.location.end,
                    YP_ERR_BEGIN_LONELY_ELSE
                );
            }

            return (yp_node_t *) begin_node;
        }
        case YP_TOKEN_KEYWORD_BEGIN_UPCASE: {
            parser_lex(parser);
            yp_token_t keyword = parser->previous;

            expect(parser, YP_TOKEN_BRACE_LEFT, YP_ERR_BEGIN_UPCASE_BRACE);
            yp_token_t opening = parser->previous;
            yp_statements_node_t *statements = parse_statements(parser, YP_CONTEXT_PREEXE);

            expect(parser, YP_TOKEN_BRACE_RIGHT, YP_ERR_BEGIN_UPCASE_TERM);
            return (yp_node_t *) yp_pre_execution_node_create(parser, &keyword, &opening, statements, &parser->previous);
        }
        case YP_TOKEN_KEYWORD_BREAK:
        case YP_TOKEN_KEYWORD_NEXT:
        case YP_TOKEN_KEYWORD_RETURN: {
            parser_lex(parser);

            yp_token_t keyword = parser->previous;
            yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;

            if (
                token_begins_expression_p(parser->current.type) ||
                match_any_type_p(parser, 2, YP_TOKEN_USTAR, YP_TOKEN_USTAR_STAR)
            ) {
                yp_binding_power_t binding_power = yp_binding_powers[parser->current.type].left;

                if (binding_power == YP_BINDING_POWER_UNSET || binding_power >= YP_BINDING_POWER_RANGE) {
                    arguments.arguments = yp_arguments_node_create(parser);
                    parse_arguments(parser, &arguments, false, YP_TOKEN_EOF);
                }
            }

            switch (keyword.type) {
                case YP_TOKEN_KEYWORD_BREAK:
                    return (yp_node_t *) yp_break_node_create(parser, &keyword, arguments.arguments);
                case YP_TOKEN_KEYWORD_NEXT:
                    return (yp_node_t *) yp_next_node_create(parser, &keyword, arguments.arguments);
                case YP_TOKEN_KEYWORD_RETURN: {
                    if (
                        (parser->current_context->context == YP_CONTEXT_CLASS) ||
                        (parser->current_context->context == YP_CONTEXT_MODULE)
                    ) {
                        yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_RETURN_INVALID);
                    }
                    return (yp_node_t *) yp_return_node_create(parser, &keyword, arguments.arguments);
                }
                default:
                    assert(false && "unreachable");
                    return (yp_node_t *) yp_missing_node_create(parser, parser->previous.start, parser->previous.end);
            }
        }
        case YP_TOKEN_KEYWORD_SUPER: {
            parser_lex(parser);

            yp_token_t keyword = parser->previous;
            yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;
            parse_arguments_list(parser, &arguments, true);

            if (arguments.opening_loc.start == NULL && arguments.arguments == NULL) {
                return (yp_node_t *) yp_forwarding_super_node_create(parser, &keyword, &arguments);
            }

            return (yp_node_t *) yp_super_node_create(parser, &keyword, &arguments);
        }
        case YP_TOKEN_KEYWORD_YIELD: {
            parser_lex(parser);

            yp_token_t keyword = parser->previous;
            yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;
            parse_arguments_list(parser, &arguments, false);

            return (yp_node_t *) yp_yield_node_create(parser, &keyword, &arguments.opening_loc, arguments.arguments, &arguments.closing_loc);
        }
        case YP_TOKEN_KEYWORD_CLASS: {
            parser_lex(parser);
            yp_token_t class_keyword = parser->previous;
            yp_do_loop_stack_push(parser, false);

            if (accept(parser, YP_TOKEN_LESS_LESS)) {
                yp_token_t operator = parser->previous;
                yp_node_t *expression = parse_expression(parser, YP_BINDING_POWER_NOT, YP_ERR_EXPECT_EXPRESSION_AFTER_LESS_LESS);

                yp_parser_scope_push(parser, true);
                accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);

                yp_node_t *statements = NULL;
                if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE, YP_TOKEN_KEYWORD_END)) {
                    yp_accepts_block_stack_push(parser, true);
                    statements = (yp_node_t *) parse_statements(parser, YP_CONTEXT_SCLASS);
                    yp_accepts_block_stack_pop(parser);
                }

                if (match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE)) {
                    assert(statements == NULL || YP_NODE_TYPE_P(statements, YP_STATEMENTS_NODE));
                    statements = (yp_node_t *) parse_rescues_as_begin(parser, (yp_statements_node_t *) statements);
                }

                expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_CLASS_TERM);

                yp_constant_id_list_t locals = parser->current_scope->locals;
                yp_parser_scope_pop(parser);
                yp_do_loop_stack_pop(parser);
                return (yp_node_t *) yp_singleton_class_node_create(parser, &locals, &class_keyword, &operator, expression, statements, &parser->previous);
            }

            yp_node_t *constant_path = parse_expression(parser, YP_BINDING_POWER_INDEX, YP_ERR_CLASS_NAME);
            yp_token_t name = parser->previous;
            if (name.type != YP_TOKEN_CONSTANT) {
                yp_diagnostic_list_append(&parser->error_list, name.start, name.end, YP_ERR_CLASS_NAME);
            }

            yp_token_t inheritance_operator;
            yp_node_t *superclass;

            if (match_type_p(parser, YP_TOKEN_LESS)) {
                inheritance_operator = parser->current;
                lex_state_set(parser, YP_LEX_STATE_BEG);

                parser->command_start = true;
                parser_lex(parser);

                superclass = parse_expression(parser, YP_BINDING_POWER_COMPOSITION, YP_ERR_CLASS_SUPERCLASS);
            } else {
                inheritance_operator = not_provided(parser);
                superclass = NULL;
            }

            yp_parser_scope_push(parser, true);
            accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
            yp_node_t *statements = NULL;

            if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE, YP_TOKEN_KEYWORD_END)) {
                yp_accepts_block_stack_push(parser, true);
                statements = (yp_node_t *) parse_statements(parser, YP_CONTEXT_CLASS);
                yp_accepts_block_stack_pop(parser);
            }

            if (match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE)) {
                assert(statements == NULL || YP_NODE_TYPE_P(statements, YP_STATEMENTS_NODE));
                statements = (yp_node_t *) parse_rescues_as_begin(parser, (yp_statements_node_t *) statements);
            }

            expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_CLASS_TERM);

            if (context_def_p(parser)) {
                yp_diagnostic_list_append(&parser->error_list, class_keyword.start, class_keyword.end, YP_ERR_CLASS_IN_METHOD);
            }

            yp_constant_id_list_t locals = parser->current_scope->locals;
            yp_parser_scope_pop(parser);
            yp_do_loop_stack_pop(parser);
            return (yp_node_t *) yp_class_node_create(parser, &locals, &class_keyword, constant_path, &name, &inheritance_operator, superclass, statements, &parser->previous);
        }
        case YP_TOKEN_KEYWORD_DEF: {
            yp_token_t def_keyword = parser->current;

            yp_node_t *receiver = NULL;
            yp_token_t operator = not_provided(parser);
            yp_token_t name = not_provided(parser);

            context_push(parser, YP_CONTEXT_DEF_PARAMS);
            parser_lex(parser);

            switch (parser->current.type) {
                case YP_CASE_OPERATOR:
                    yp_parser_scope_push(parser, true);
                    lex_state_set(parser, YP_LEX_STATE_ENDFN);
                    parser_lex(parser);
                    name = parser->previous;
                    break;
                case YP_TOKEN_IDENTIFIER: {
                    yp_parser_scope_push(parser, true);
                    parser_lex(parser);

                    if (match_any_type_p(parser, 2, YP_TOKEN_DOT, YP_TOKEN_COLON_COLON)) {
                        receiver = parse_variable_call(parser);

                        lex_state_set(parser, YP_LEX_STATE_FNAME);
                        parser_lex(parser);

                        operator = parser->previous;
                        name = parse_method_definition_name(parser);

                        if (name.type == YP_TOKEN_MISSING) {
                            yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_DEF_NAME_AFTER_RECEIVER);
                        }
                    } else {
                        name = parser->previous;
                    }

                    break;
                }
                case YP_TOKEN_CONSTANT:
                case YP_TOKEN_INSTANCE_VARIABLE:
                case YP_TOKEN_CLASS_VARIABLE:
                case YP_TOKEN_GLOBAL_VARIABLE:
                case YP_TOKEN_KEYWORD_NIL:
                case YP_TOKEN_KEYWORD_SELF:
                case YP_TOKEN_KEYWORD_TRUE:
                case YP_TOKEN_KEYWORD_FALSE:
                case YP_TOKEN_KEYWORD___FILE__:
                case YP_TOKEN_KEYWORD___LINE__:
                case YP_TOKEN_KEYWORD___ENCODING__: {
                    yp_parser_scope_push(parser, true);
                    parser_lex(parser);
                    yp_token_t identifier = parser->previous;

                    if (match_any_type_p(parser, 2, YP_TOKEN_DOT, YP_TOKEN_COLON_COLON)) {
                        lex_state_set(parser, YP_LEX_STATE_FNAME);
                        parser_lex(parser);
                        operator = parser->previous;

                        switch (identifier.type) {
                            case YP_TOKEN_CONSTANT:
                                receiver = (yp_node_t *) yp_constant_read_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_INSTANCE_VARIABLE:
                                receiver = (yp_node_t *) yp_instance_variable_read_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_CLASS_VARIABLE:
                                receiver = (yp_node_t *) yp_class_variable_read_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_GLOBAL_VARIABLE:
                                receiver = (yp_node_t *) yp_global_variable_read_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_KEYWORD_NIL:
                                receiver = (yp_node_t *) yp_nil_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_KEYWORD_SELF:
                                receiver = (yp_node_t *) yp_self_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_KEYWORD_TRUE:
                                receiver = (yp_node_t *) yp_true_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_KEYWORD_FALSE:
                                receiver = (yp_node_t *)yp_false_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_KEYWORD___FILE__:
                                receiver = (yp_node_t *) yp_source_file_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_KEYWORD___LINE__:
                                receiver = (yp_node_t *) yp_source_line_node_create(parser, &identifier);
                                break;
                            case YP_TOKEN_KEYWORD___ENCODING__:
                                receiver = (yp_node_t *) yp_source_encoding_node_create(parser, &identifier);
                                break;
                            default:
                                break;
                        }

                        name = parse_method_definition_name(parser);
                        if (name.type == YP_TOKEN_MISSING) {
                            yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_DEF_NAME_AFTER_RECEIVER);
                        }
                    } else {
                        name = identifier;
                    }
                    break;
                }
                case YP_TOKEN_PARENTHESIS_LEFT: {
                    parser_lex(parser);
                    yp_token_t lparen = parser->previous;
                    yp_node_t *expression = parse_expression(parser, YP_BINDING_POWER_STATEMENT, YP_ERR_DEF_RECEIVER);

                    expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_EXPECT_RPAREN);
                    yp_token_t rparen = parser->previous;

                    lex_state_set(parser, YP_LEX_STATE_FNAME);
                    expect_any(parser, YP_ERR_DEF_RECEIVER_TERM, 2, YP_TOKEN_DOT, YP_TOKEN_COLON_COLON);

                    operator = parser->previous;
                    receiver = (yp_node_t *) yp_parentheses_node_create(parser, &lparen, expression, &rparen);

                    yp_parser_scope_push(parser, true);
                    name = parse_method_definition_name(parser);
                    break;
                }
                default:
                    yp_parser_scope_push(parser, true);
                    name = parse_method_definition_name(parser);

                    if (name.type == YP_TOKEN_MISSING) {
                        yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_DEF_NAME);
                    }
                    break;
            }

            yp_token_t lparen;
            yp_token_t rparen;
            yp_parameters_node_t *params;

            switch (parser->current.type) {
                case YP_TOKEN_PARENTHESIS_LEFT: {
                    parser_lex(parser);
                    lparen = parser->previous;

                    if (match_type_p(parser, YP_TOKEN_PARENTHESIS_RIGHT)) {
                        params = NULL;
                    } else {
                        params = parse_parameters(parser, YP_BINDING_POWER_DEFINED, true, false, true);
                    }

                    lex_state_set(parser, YP_LEX_STATE_BEG);
                    parser->command_start = true;

                    expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_DEF_PARAMS_TERM_PAREN);
                    rparen = parser->previous;
                    break;
                }
                case YP_CASE_PARAMETER: {
                    // If we're about to lex a label, we need to add the label
                    // state to make sure the next newline is ignored.
                    if (parser->current.type == YP_TOKEN_LABEL) {
                        lex_state_set(parser, parser->lex_state | YP_LEX_STATE_LABEL);
                    }

                    lparen = not_provided(parser);
                    rparen = not_provided(parser);
                    params = parse_parameters(parser, YP_BINDING_POWER_DEFINED, false, false, true);
                    break;
                }
                default: {
                    lparen = not_provided(parser);
                    rparen = not_provided(parser);
                    params = NULL;
                    break;
                }
            }

            context_pop(parser);
            yp_node_t *statements = NULL;
            yp_token_t equal;
            yp_token_t end_keyword;

            if (accept(parser, YP_TOKEN_EQUAL)) {
                if (token_is_setter_name(&name)) {
                    yp_diagnostic_list_append(&parser->error_list, name.start, name.end, YP_ERR_DEF_ENDLESS_SETTER);
                }
                equal = parser->previous;

                context_push(parser, YP_CONTEXT_DEF);
                statements = (yp_node_t *) yp_statements_node_create(parser);

                yp_node_t *statement = parse_expression(parser, YP_BINDING_POWER_DEFINED + 1, YP_ERR_DEF_ENDLESS);

                if (accept(parser, YP_TOKEN_KEYWORD_RESCUE_MODIFIER)) {
                    yp_token_t rescue_keyword = parser->previous;
                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_RESCUE_MODIFIER_VALUE);
                    yp_rescue_modifier_node_t *rescue_node = yp_rescue_modifier_node_create(parser, statement, &rescue_keyword, value);
                    statement = (yp_node_t *)rescue_node;
                }

                yp_statements_node_body_append((yp_statements_node_t *) statements, statement);
                context_pop(parser);
                end_keyword = not_provided(parser);
            } else {
                equal = not_provided(parser);

                if (lparen.type == YP_TOKEN_NOT_PROVIDED) {
                    lex_state_set(parser, YP_LEX_STATE_BEG);
                    parser->command_start = true;
                    expect_any(parser, YP_ERR_DEF_PARAMS_TERM, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
                } else {
                    accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
                }

                yp_accepts_block_stack_push(parser, true);
                yp_do_loop_stack_push(parser, false);

                if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE, YP_TOKEN_KEYWORD_END)) {
                    yp_accepts_block_stack_push(parser, true);
                    statements = (yp_node_t *) parse_statements(parser, YP_CONTEXT_DEF);
                    yp_accepts_block_stack_pop(parser);
                }

                if (match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE)) {
                    assert(statements == NULL || YP_NODE_TYPE_P(statements, YP_STATEMENTS_NODE));
                    statements = (yp_node_t *) parse_rescues_as_begin(parser, (yp_statements_node_t *) statements);
                }

                yp_accepts_block_stack_pop(parser);
                yp_do_loop_stack_pop(parser);
                expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_DEF_TERM);
                end_keyword = parser->previous;
            }

            yp_constant_id_list_t locals = parser->current_scope->locals;
            yp_parser_scope_pop(parser);

            return (yp_node_t *) yp_def_node_create(
                parser,
                &name,
                receiver,
                params,
                statements,
                &locals,
                &def_keyword,
                &operator,
                &lparen,
                &rparen,
                &equal,
                &end_keyword
            );
        }
        case YP_TOKEN_KEYWORD_DEFINED: {
            parser_lex(parser);
            yp_token_t keyword = parser->previous;

            yp_token_t lparen;
            yp_token_t rparen;
            yp_node_t *expression;

            if (accept(parser, YP_TOKEN_PARENTHESIS_LEFT)) {
                lparen = parser->previous;
                expression = parse_expression(parser, YP_BINDING_POWER_COMPOSITION, YP_ERR_DEFINED_EXPRESSION);

                if (parser->recovering) {
                    rparen = not_provided(parser);
                } else {
                    expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_EXPECT_RPAREN);
                    rparen = parser->previous;
                }
            } else {
                lparen = not_provided(parser);
                rparen = not_provided(parser);
                expression = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_DEFINED_EXPRESSION);
            }

            return (yp_node_t *) yp_defined_node_create(
                parser,
                &lparen,
                expression,
                &rparen,
                &YP_LOCATION_TOKEN_VALUE(&keyword)
            );
        }
        case YP_TOKEN_KEYWORD_END_UPCASE: {
            parser_lex(parser);
            yp_token_t keyword = parser->previous;

            expect(parser, YP_TOKEN_BRACE_LEFT, YP_ERR_END_UPCASE_BRACE);
            yp_token_t opening = parser->previous;
            yp_statements_node_t *statements = parse_statements(parser, YP_CONTEXT_POSTEXE);

            expect(parser, YP_TOKEN_BRACE_RIGHT, YP_ERR_END_UPCASE_TERM);
            return (yp_node_t *) yp_post_execution_node_create(parser, &keyword, &opening, statements, &parser->previous);
        }
        case YP_TOKEN_KEYWORD_FALSE:
            parser_lex(parser);
            return (yp_node_t *)yp_false_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD_FOR: {
            parser_lex(parser);
            yp_token_t for_keyword = parser->previous;

            yp_node_t *index = parse_targets(parser, NULL, YP_BINDING_POWER_INDEX);
            yp_do_loop_stack_push(parser, true);

            expect(parser, YP_TOKEN_KEYWORD_IN, YP_ERR_FOR_IN);
            yp_token_t in_keyword = parser->previous;

            yp_node_t *collection = parse_expression(parser, YP_BINDING_POWER_COMPOSITION, YP_ERR_FOR_COLLECTION);
            yp_do_loop_stack_pop(parser);

            yp_token_t do_keyword;
            if (accept(parser, YP_TOKEN_KEYWORD_DO_LOOP)) {
                do_keyword = parser->previous;
            } else {
                do_keyword = not_provided(parser);
            }

            accept_any(parser, 2, YP_TOKEN_SEMICOLON, YP_TOKEN_NEWLINE);
            yp_statements_node_t *statements = NULL;

            if (!accept(parser, YP_TOKEN_KEYWORD_END)) {
                statements = parse_statements(parser, YP_CONTEXT_FOR);
                expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_FOR_TERM);
            }

            return (yp_node_t *) yp_for_node_create(parser, index, collection, statements, &for_keyword, &in_keyword, &do_keyword, &parser->previous);
        }
        case YP_TOKEN_KEYWORD_IF:
            parser_lex(parser);
            return parse_conditional(parser, YP_CONTEXT_IF);
        case YP_TOKEN_KEYWORD_UNDEF: {
            parser_lex(parser);
            yp_undef_node_t *undef = yp_undef_node_create(parser, &parser->previous);
            yp_node_t *name = parse_undef_argument(parser);

            if (YP_NODE_TYPE_P(name, YP_MISSING_NODE)) {
                yp_node_destroy(parser, name);
            } else {
                yp_undef_node_append(undef, name);

                while (match_type_p(parser, YP_TOKEN_COMMA)) {
                    lex_state_set(parser, YP_LEX_STATE_FNAME | YP_LEX_STATE_FITEM);
                    parser_lex(parser);
                    name = parse_undef_argument(parser);

                    if (YP_NODE_TYPE_P(name, YP_MISSING_NODE)) {
                        yp_node_destroy(parser, name);
                        break;
                    }

                    yp_undef_node_append(undef, name);
                }
            }

            return (yp_node_t *) undef;
        }
        case YP_TOKEN_KEYWORD_NOT: {
            parser_lex(parser);

            yp_token_t message = parser->previous;
            yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;
            yp_node_t *receiver = NULL;

            accept(parser, YP_TOKEN_NEWLINE);

            if (accept(parser, YP_TOKEN_PARENTHESIS_LEFT)) {
                arguments.opening_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);

                if (accept(parser, YP_TOKEN_PARENTHESIS_RIGHT)) {
                    arguments.closing_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);
                } else {
                    receiver = parse_expression(parser, YP_BINDING_POWER_COMPOSITION, YP_ERR_NOT_EXPRESSION);
                    yp_flip_flop(receiver);

                    if (!parser->recovering) {
                        accept(parser, YP_TOKEN_NEWLINE);
                        expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_EXPECT_RPAREN);
                        arguments.closing_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);
                    }
                }
            } else {
                receiver = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_NOT_EXPRESSION);
                yp_flip_flop(receiver);
            }

            return (yp_node_t *) yp_call_node_not_create(parser, receiver, &message, &arguments);
        }
        case YP_TOKEN_KEYWORD_UNLESS:
            parser_lex(parser);
            return parse_conditional(parser, YP_CONTEXT_UNLESS);
        case YP_TOKEN_KEYWORD_MODULE: {
            parser_lex(parser);

            yp_token_t module_keyword = parser->previous;
            yp_node_t *constant_path = parse_expression(parser, YP_BINDING_POWER_INDEX, YP_ERR_MODULE_NAME);
            yp_token_t name;

            // If we can recover from a syntax error that occurred while parsing
            // the name of the module, then we'll handle that here.
            if (YP_NODE_TYPE_P(constant_path, YP_MISSING_NODE)) {
                yp_token_t missing = (yp_token_t) { .type = YP_TOKEN_MISSING, .start = parser->previous.end, .end = parser->previous.end };
                return (yp_node_t *) yp_module_node_create(parser, NULL, &module_keyword, constant_path, &missing, NULL, &missing);
            }

            while (accept(parser, YP_TOKEN_COLON_COLON)) {
                yp_token_t double_colon = parser->previous;

                expect(parser, YP_TOKEN_CONSTANT, YP_ERR_CONSTANT_PATH_COLON_COLON_CONSTANT);
                yp_node_t *constant = (yp_node_t *) yp_constant_read_node_create(parser, &parser->previous);

                constant_path = (yp_node_t *) yp_constant_path_node_create(parser, constant_path, &double_colon, constant);
            }

            // Here we retrieve the name of the module. If it wasn't a constant,
            // then it's possible that `module foo` was passed, which is a
            // syntax error. We handle that here as well.
            name = parser->previous;
            if (name.type != YP_TOKEN_CONSTANT) {
                yp_diagnostic_list_append(&parser->error_list, name.start, name.end, YP_ERR_MODULE_NAME);
            }

            yp_parser_scope_push(parser, true);
            accept_any(parser, 2, YP_TOKEN_SEMICOLON, YP_TOKEN_NEWLINE);
            yp_node_t *statements = NULL;

            if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE, YP_TOKEN_KEYWORD_END)) {
                yp_accepts_block_stack_push(parser, true);
                statements = (yp_node_t *) parse_statements(parser, YP_CONTEXT_MODULE);
                yp_accepts_block_stack_pop(parser);
            }

            if (match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE)) {
                assert(statements == NULL || YP_NODE_TYPE_P(statements, YP_STATEMENTS_NODE));
                statements = (yp_node_t *) parse_rescues_as_begin(parser, (yp_statements_node_t *) statements);
            }

            yp_constant_id_list_t locals = parser->current_scope->locals;
            yp_parser_scope_pop(parser);

            expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_MODULE_TERM);

            if (context_def_p(parser)) {
                yp_diagnostic_list_append(&parser->error_list, module_keyword.start, module_keyword.end, YP_ERR_MODULE_IN_METHOD);
            }

            return (yp_node_t *) yp_module_node_create(parser, &locals, &module_keyword, constant_path, &name, statements, &parser->previous);
        }
        case YP_TOKEN_KEYWORD_NIL:
            parser_lex(parser);
            return (yp_node_t *) yp_nil_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD_REDO:
            parser_lex(parser);
            return (yp_node_t *) yp_redo_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD_RETRY:
            parser_lex(parser);
            return (yp_node_t *) yp_retry_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD_SELF:
            parser_lex(parser);
            return (yp_node_t *) yp_self_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD_TRUE:
            parser_lex(parser);
            return (yp_node_t *) yp_true_node_create(parser, &parser->previous);
        case YP_TOKEN_KEYWORD_UNTIL: {
            yp_do_loop_stack_push(parser, true);
            parser_lex(parser);
            yp_token_t keyword = parser->previous;

            yp_node_t *predicate = parse_expression(parser, YP_BINDING_POWER_COMPOSITION, YP_ERR_CONDITIONAL_UNTIL_PREDICATE);
            yp_do_loop_stack_pop(parser);

            accept_any(parser, 3, YP_TOKEN_KEYWORD_DO_LOOP, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
            yp_statements_node_t *statements = NULL;

            if (!accept(parser, YP_TOKEN_KEYWORD_END)) {
                yp_accepts_block_stack_push(parser, true);
                statements = parse_statements(parser, YP_CONTEXT_UNTIL);
                yp_accepts_block_stack_pop(parser);
                accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
                expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_UNTIL_TERM);
            }

            return (yp_node_t *) yp_until_node_create(parser, &keyword, &parser->previous, predicate, statements, 0);
        }
        case YP_TOKEN_KEYWORD_WHILE: {
            yp_do_loop_stack_push(parser, true);
            parser_lex(parser);
            yp_token_t keyword = parser->previous;

            yp_node_t *predicate = parse_expression(parser, YP_BINDING_POWER_COMPOSITION, YP_ERR_CONDITIONAL_WHILE_PREDICATE);
            yp_do_loop_stack_pop(parser);

            accept_any(parser, 3, YP_TOKEN_KEYWORD_DO_LOOP, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
            yp_statements_node_t *statements = NULL;

            if (!accept(parser, YP_TOKEN_KEYWORD_END)) {
                yp_accepts_block_stack_push(parser, true);
                statements = parse_statements(parser, YP_CONTEXT_WHILE);
                yp_accepts_block_stack_pop(parser);
                accept_any(parser, 2, YP_TOKEN_NEWLINE, YP_TOKEN_SEMICOLON);
                expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_WHILE_TERM);
            }

            return (yp_node_t *) yp_while_node_create(parser, &keyword, &parser->previous, predicate, statements, 0);
        }
        case YP_TOKEN_PERCENT_LOWER_I: {
            parser_lex(parser);
            yp_array_node_t *array = yp_array_node_create(parser, &parser->previous);

            while (!match_any_type_p(parser, 2, YP_TOKEN_STRING_END, YP_TOKEN_EOF)) {
                accept(parser, YP_TOKEN_WORDS_SEP);
                if (match_type_p(parser, YP_TOKEN_STRING_END)) break;

                expect(parser, YP_TOKEN_STRING_CONTENT, YP_ERR_LIST_I_LOWER_ELEMENT);

                yp_token_t opening = not_provided(parser);
                yp_token_t closing = not_provided(parser);

                yp_node_t *symbol = (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &parser->previous, &closing, YP_UNESCAPE_MINIMAL);
                yp_array_node_elements_append(array, symbol);
            }

            expect(parser, YP_TOKEN_STRING_END, YP_ERR_LIST_I_LOWER_TERM);
            yp_array_node_close_set(array, &parser->previous);

            return (yp_node_t *) array;
        }
        case YP_TOKEN_PERCENT_UPPER_I: {
            parser_lex(parser);
            yp_array_node_t *array = yp_array_node_create(parser, &parser->previous);

            // This is the current node that we are parsing that will be added to the
            // list of elements.
            yp_node_t *current = NULL;

            while (!match_any_type_p(parser, 2, YP_TOKEN_STRING_END, YP_TOKEN_EOF)) {
                switch (parser->current.type) {
                    case YP_TOKEN_WORDS_SEP: {
                        if (current == NULL) {
                            // If we hit a separator before we have any content, then we don't
                            // need to do anything.
                        } else {
                            // If we hit a separator after we've hit content, then we need to
                            // append that content to the list and reset the current node.
                            yp_array_node_elements_append(array, current);
                            current = NULL;
                        }

                        parser_lex(parser);
                        break;
                    }
                    case YP_TOKEN_STRING_CONTENT: {
                        yp_token_t opening = not_provided(parser);
                        yp_token_t closing = not_provided(parser);

                        if (current == NULL) {
                            // If we hit content and the current node is NULL, then this is
                            // the first string content we've seen. In that case we're going
                            // to create a new string node and set that to the current.
                            parser_lex(parser);
                            current = (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &parser->previous, &closing, YP_UNESCAPE_ALL);
                        } else if (YP_NODE_TYPE_P(current, YP_INTERPOLATED_SYMBOL_NODE)) {
                            // If we hit string content and the current node is an
                            // interpolated string, then we need to append the string content
                            // to the list of child nodes.
                            yp_node_t *part = parse_string_part(parser);
                            yp_interpolated_symbol_node_append((yp_interpolated_symbol_node_t *) current, part);
                        } else if (YP_NODE_TYPE_P(current, YP_SYMBOL_NODE)) {
                            // If we hit string content and the current node is a string node,
                            // then we need to convert the current node into an interpolated
                            // string and add the string content to the list of child nodes.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            yp_interpolated_symbol_node_t *interpolated =
                                yp_interpolated_symbol_node_create(parser, &opening, NULL, &closing);
                            yp_interpolated_symbol_node_append(interpolated, current);

                            yp_node_t *part = parse_string_part(parser);
                            yp_interpolated_symbol_node_append(interpolated, part);
                            current = (yp_node_t *) interpolated;
                        } else {
                            assert(false && "unreachable");
                        }

                        break;
                    }
                    case YP_TOKEN_EMBVAR: {
                        bool start_location_set = false;
                        if (current == NULL) {
                            // If we hit an embedded variable and the current node is NULL,
                            // then this is the start of a new string. We'll set the current
                            // node to a new interpolated string.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            current = (yp_node_t *) yp_interpolated_symbol_node_create(parser, &opening, NULL, &closing);
                        } else if (YP_NODE_TYPE_P(current, YP_SYMBOL_NODE)) {
                            // If we hit an embedded variable and the current node is a string
                            // node, then we'll convert the current into an interpolated
                            // string and add the string node to the list of parts.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            yp_interpolated_symbol_node_t *interpolated = yp_interpolated_symbol_node_create(parser, &opening, NULL, &closing);

                            current = (yp_node_t *) yp_symbol_node_to_string_node(parser, (yp_symbol_node_t *) current);
                            yp_interpolated_symbol_node_append(interpolated, current);
                            interpolated->base.location.start = current->location.start;
                            start_location_set = true;
                            current = (yp_node_t *) interpolated;
                        } else {
                            // If we hit an embedded variable and the current node is an
                            // interpolated string, then we'll just add the embedded variable.
                        }

                        yp_node_t *part = parse_string_part(parser);
                        yp_interpolated_symbol_node_append((yp_interpolated_symbol_node_t *) current, part);
                        if (!start_location_set) {
                            current->location.start = part->location.start;
                        }
                        break;
                    }
                    case YP_TOKEN_EMBEXPR_BEGIN: {
                        bool start_location_set = false;
                        if (current == NULL) {
                            // If we hit an embedded expression and the current node is NULL,
                            // then this is the start of a new string. We'll set the current
                            // node to a new interpolated string.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            current = (yp_node_t *) yp_interpolated_symbol_node_create(parser, &opening, NULL, &closing);
                        } else if (YP_NODE_TYPE_P(current, YP_SYMBOL_NODE)) {
                            // If we hit an embedded expression and the current node is a
                            // string node, then we'll convert the current into an
                            // interpolated string and add the string node to the list of
                            // parts.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            yp_interpolated_symbol_node_t *interpolated = yp_interpolated_symbol_node_create(parser, &opening, NULL, &closing);

                            current = (yp_node_t *) yp_symbol_node_to_string_node(parser, (yp_symbol_node_t *) current);
                            yp_interpolated_symbol_node_append(interpolated, current);
                            interpolated->base.location.start = current->location.start;
                            start_location_set = true;
                            current = (yp_node_t *) interpolated;
                        } else if (YP_NODE_TYPE_P(current, YP_INTERPOLATED_SYMBOL_NODE)) {
                            // If we hit an embedded expression and the current node is an
                            // interpolated string, then we'll just continue on.
                        } else {
                            assert(false && "unreachable");
                        }

                        yp_node_t *part = parse_string_part(parser);
                        yp_interpolated_symbol_node_append((yp_interpolated_symbol_node_t *) current, part);
                        if (!start_location_set) {
                            current->location.start = part->location.start;
                        }
                        break;
                    }
                    default:
                        expect(parser, YP_TOKEN_STRING_CONTENT, YP_ERR_LIST_I_UPPER_ELEMENT);
                        parser_lex(parser);
                        break;
                }
            }

            // If we have a current node, then we need to append it to the list.
            if (current) {
                yp_array_node_elements_append(array, current);
            }

            expect(parser, YP_TOKEN_STRING_END, YP_ERR_LIST_I_UPPER_TERM);
            yp_array_node_close_set(array, &parser->previous);

            return (yp_node_t *) array;
        }
        case YP_TOKEN_PERCENT_LOWER_W: {
            parser_lex(parser);
            yp_array_node_t *array = yp_array_node_create(parser, &parser->previous);

            // skip all leading whitespaces
            accept(parser, YP_TOKEN_WORDS_SEP);

            while (!match_any_type_p(parser, 2, YP_TOKEN_STRING_END, YP_TOKEN_EOF)) {
                accept(parser, YP_TOKEN_WORDS_SEP);
                if (match_type_p(parser, YP_TOKEN_STRING_END)) break;

                expect(parser, YP_TOKEN_STRING_CONTENT, YP_ERR_LIST_W_LOWER_ELEMENT);

                yp_token_t opening = not_provided(parser);
                yp_token_t closing = not_provided(parser);
                yp_node_t *string = (yp_node_t *) yp_string_node_create_and_unescape(parser, &opening, &parser->previous, &closing, YP_UNESCAPE_MINIMAL);
                yp_array_node_elements_append(array, string);
            }

            expect(parser, YP_TOKEN_STRING_END, YP_ERR_LIST_W_LOWER_TERM);
            yp_array_node_close_set(array, &parser->previous);

            return (yp_node_t *) array;
        }
        case YP_TOKEN_PERCENT_UPPER_W: {
            parser_lex(parser);
            yp_array_node_t *array = yp_array_node_create(parser, &parser->previous);

            // This is the current node that we are parsing that will be added to the
            // list of elements.
            yp_node_t *current = NULL;

            while (!match_any_type_p(parser, 2, YP_TOKEN_STRING_END, YP_TOKEN_EOF)) {
                switch (parser->current.type) {
                    case YP_TOKEN_WORDS_SEP: {
                        if (current == NULL) {
                            // If we hit a separator before we have any content, then we don't
                            // need to do anything.
                        } else {
                            // If we hit a separator after we've hit content, then we need to
                            // append that content to the list and reset the current node.
                            yp_array_node_elements_append(array, current);
                            current = NULL;
                        }

                        parser_lex(parser);
                        break;
                    }
                    case YP_TOKEN_STRING_CONTENT: {
                        if (current == NULL) {
                            // If we hit content and the current node is NULL, then this is
                            // the first string content we've seen. In that case we're going
                            // to create a new string node and set that to the current.
                            current = parse_string_part(parser);
                        } else if (YP_NODE_TYPE_P(current, YP_INTERPOLATED_STRING_NODE)) {
                            // If we hit string content and the current node is an
                            // interpolated string, then we need to append the string content
                            // to the list of child nodes.
                            yp_node_t *part = parse_string_part(parser);
                            yp_interpolated_string_node_append((yp_interpolated_string_node_t *) current, part);
                        } else if (YP_NODE_TYPE_P(current, YP_STRING_NODE)) {
                            // If we hit string content and the current node is a string node,
                            // then we need to convert the current node into an interpolated
                            // string and add the string content to the list of child nodes.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            yp_interpolated_string_node_t *interpolated =
                                yp_interpolated_string_node_create(parser, &opening, NULL, &closing);
                            yp_interpolated_string_node_append(interpolated, current);

                            yp_node_t *part = parse_string_part(parser);
                            yp_interpolated_string_node_append(interpolated, part);
                            current = (yp_node_t *) interpolated;
                        } else {
                            assert(false && "unreachable");
                        }

                        break;
                    }
                    case YP_TOKEN_EMBVAR: {
                        if (current == NULL) {
                            // If we hit an embedded variable and the current node is NULL,
                            // then this is the start of a new string. We'll set the current
                            // node to a new interpolated string.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            current = (yp_node_t *) yp_interpolated_string_node_create(parser, &opening, NULL, &closing);
                        } else if (YP_NODE_TYPE_P(current, YP_STRING_NODE)) {
                            // If we hit an embedded variable and the current node is a string
                            // node, then we'll convert the current into an interpolated
                            // string and add the string node to the list of parts.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            yp_interpolated_string_node_t *interpolated = yp_interpolated_string_node_create(parser, &opening, NULL, &closing);
                            yp_interpolated_string_node_append(interpolated, current);
                            current = (yp_node_t *) interpolated;
                        } else {
                            // If we hit an embedded variable and the current node is an
                            // interpolated string, then we'll just add the embedded variable.
                        }

                        yp_node_t *part = parse_string_part(parser);
                        yp_interpolated_string_node_append((yp_interpolated_string_node_t *) current, part);
                        break;
                    }
                    case YP_TOKEN_EMBEXPR_BEGIN: {
                        if (current == NULL) {
                            // If we hit an embedded expression and the current node is NULL,
                            // then this is the start of a new string. We'll set the current
                            // node to a new interpolated string.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            current = (yp_node_t *) yp_interpolated_string_node_create(parser, &opening, NULL, &closing);
                        } else if (YP_NODE_TYPE_P(current, YP_STRING_NODE)) {
                            // If we hit an embedded expression and the current node is a
                            // string node, then we'll convert the current into an
                            // interpolated string and add the string node to the list of
                            // parts.
                            yp_token_t opening = not_provided(parser);
                            yp_token_t closing = not_provided(parser);
                            yp_interpolated_string_node_t *interpolated = yp_interpolated_string_node_create(parser, &opening, NULL, &closing);
                            yp_interpolated_string_node_append(interpolated, current);
                            current = (yp_node_t *) interpolated;
                        } else if (YP_NODE_TYPE_P(current, YP_INTERPOLATED_STRING_NODE)) {
                            // If we hit an embedded expression and the current node is an
                            // interpolated string, then we'll just continue on.
                        } else {
                            assert(false && "unreachable");
                        }

                        yp_node_t *part = parse_string_part(parser);
                        yp_interpolated_string_node_append((yp_interpolated_string_node_t *) current, part);
                        break;
                    }
                    default:
                        expect(parser, YP_TOKEN_STRING_CONTENT, YP_ERR_LIST_W_UPPER_ELEMENT);
                        parser_lex(parser);
                        break;
                }
            }

            // If we have a current node, then we need to append it to the list.
            if (current) {
                yp_array_node_elements_append(array, current);
            }

            expect(parser, YP_TOKEN_STRING_END, YP_ERR_LIST_W_UPPER_TERM);
            yp_array_node_close_set(array, &parser->previous);

            return (yp_node_t *) array;
        }
        case YP_TOKEN_REGEXP_BEGIN: {
            yp_token_t opening = parser->current;
            parser_lex(parser);

            if (match_type_p(parser, YP_TOKEN_REGEXP_END)) {
                // If we get here, then we have an end immediately after a start. In
                // that case we'll create an empty content token and return an
                // uninterpolated regular expression.
                yp_token_t content = (yp_token_t) {
                    .type = YP_TOKEN_STRING_CONTENT,
                    .start = parser->previous.end,
                    .end = parser->previous.end
                };

                parser_lex(parser);
                return (yp_node_t *) yp_regular_expression_node_create_and_unescape(parser, &opening, &content, &parser->previous, YP_UNESCAPE_ALL);
            }

            yp_interpolated_regular_expression_node_t *node;

            if (match_type_p(parser, YP_TOKEN_STRING_CONTENT)) {
                // In this case we've hit string content so we know the regular
                // expression at least has something in it. We'll need to check if the
                // following token is the end (in which case we can return a plain
                // regular expression) or if it's not then it has interpolation.
                yp_token_t content = parser->current;
                parser_lex(parser);

                // If we hit an end, then we can create a regular expression node
                // without interpolation, which can be represented more succinctly and
                // more easily compiled.
                if (accept(parser, YP_TOKEN_REGEXP_END)) {
                    return (yp_node_t *) yp_regular_expression_node_create_and_unescape(parser, &opening, &content, &parser->previous, YP_UNESCAPE_ALL);
                }

                // If we get here, then we have interpolation so we'll need to create
                // a regular expression node with interpolation.
                node = yp_interpolated_regular_expression_node_create(parser, &opening);

                yp_token_t opening = not_provided(parser);
                yp_token_t closing = not_provided(parser);
                yp_node_t *part = (yp_node_t *) yp_string_node_create_and_unescape(parser, &opening, &parser->previous, &closing, YP_UNESCAPE_ALL);
                yp_interpolated_regular_expression_node_append(node, part);
            } else {
                // If the first part of the body of the regular expression is not a
                // string content, then we have interpolation and we need to create an
                // interpolated regular expression node.
                node = yp_interpolated_regular_expression_node_create(parser, &opening);
            }

            // Now that we're here and we have interpolation, we'll parse all of the
            // parts into the list.
            while (!match_any_type_p(parser, 2, YP_TOKEN_REGEXP_END, YP_TOKEN_EOF)) {
                yp_node_t *part = parse_string_part(parser);
                if (part != NULL) {
                    yp_interpolated_regular_expression_node_append(node, part);
                }
            }

            expect(parser, YP_TOKEN_REGEXP_END, YP_ERR_REGEXP_TERM);
            yp_interpolated_regular_expression_node_closing_set(node, &parser->previous);

            return (yp_node_t *) node;
        }
        case YP_TOKEN_BACKTICK:
        case YP_TOKEN_PERCENT_LOWER_X: {
            parser_lex(parser);
            yp_token_t opening = parser->previous;

            // When we get here, we don't know if this string is going to have
            // interpolation or not, even though it is allowed. Still, we want to be
            // able to return a string node without interpolation if we can since
            // it'll be faster.
            if (match_type_p(parser, YP_TOKEN_STRING_END)) {
                // If we get here, then we have an end immediately after a start. In
                // that case we'll create an empty content token and return an
                // uninterpolated string.
                yp_token_t content = (yp_token_t) {
                    .type = YP_TOKEN_STRING_CONTENT,
                    .start = parser->previous.end,
                    .end = parser->previous.end
                };

                parser_lex(parser);
                return (yp_node_t *) yp_xstring_node_create(parser, &opening, &content, &parser->previous);
            }

            yp_interpolated_x_string_node_t *node;

            if (match_type_p(parser, YP_TOKEN_STRING_CONTENT)) {
                // In this case we've hit string content so we know the string at least
                // has something in it. We'll need to check if the following token is
                // the end (in which case we can return a plain string) or if it's not
                // then it has interpolation.
                yp_token_t content = parser->current;
                parser_lex(parser);

                if (accept(parser, YP_TOKEN_STRING_END)) {
                    return (yp_node_t *) yp_xstring_node_create_and_unescape(parser, &opening, &content, &parser->previous);
                }

                // If we get here, then we have interpolation so we'll need to create
                // a string node with interpolation.
                node = yp_interpolated_xstring_node_create(parser, &opening, &opening);

                yp_token_t opening = not_provided(parser);
                yp_token_t closing = not_provided(parser);
                yp_node_t *part = (yp_node_t *) yp_string_node_create_and_unescape(parser, &opening, &parser->previous, &closing, YP_UNESCAPE_ALL);
                yp_interpolated_xstring_node_append(node, part);
            } else {
                // If the first part of the body of the string is not a string content,
                // then we have interpolation and we need to create an interpolated
                // string node.
                node = yp_interpolated_xstring_node_create(parser, &opening, &opening);
            }

            while (!match_any_type_p(parser, 2, YP_TOKEN_STRING_END, YP_TOKEN_EOF)) {
                yp_node_t *part = parse_string_part(parser);
                if (part != NULL) {
                    yp_interpolated_xstring_node_append(node, part);
                }
            }

            expect(parser, YP_TOKEN_STRING_END, YP_ERR_XSTRING_TERM);
            yp_interpolated_xstring_node_closing_set(node, &parser->previous);
            return (yp_node_t *) node;
        }
        case YP_TOKEN_USTAR: {
            parser_lex(parser);

            // * operators at the beginning of expressions are only valid in the
            // context of a multiple assignment. We enforce that here. We'll still lex
            // past it though and create a missing node place.
            if (binding_power != YP_BINDING_POWER_STATEMENT) {
                return (yp_node_t *) yp_missing_node_create(parser, parser->previous.start, parser->previous.end);
            }

            yp_token_t operator = parser->previous;
            yp_node_t *name = NULL;

            if (token_begins_expression_p(parser->current.type)) {
                name = parse_expression(parser, YP_BINDING_POWER_INDEX, YP_ERR_EXPECT_EXPRESSION_AFTER_STAR);
            }

            yp_node_t *splat = (yp_node_t *) yp_splat_node_create(parser, &operator, name);
            return parse_targets(parser, splat, YP_BINDING_POWER_INDEX);
        }
        case YP_TOKEN_BANG: {
            parser_lex(parser);

            yp_token_t operator = parser->previous;
            yp_node_t *receiver = parse_expression(parser, yp_binding_powers[parser->previous.type].right, YP_ERR_UNARY_RECEIVER_BANG);
            yp_call_node_t *node = yp_call_node_unary_create(parser, &operator, receiver, "!");

            yp_flip_flop(receiver);
            return (yp_node_t *) node;
        }
        case YP_TOKEN_TILDE: {
            parser_lex(parser);

            yp_token_t operator = parser->previous;
            yp_node_t *receiver = parse_expression(parser, yp_binding_powers[parser->previous.type].right, YP_ERR_UNARY_RECEIVER_TILDE);
            yp_call_node_t *node = yp_call_node_unary_create(parser, &operator, receiver, "~");

            return (yp_node_t *) node;
        }
        case YP_TOKEN_UMINUS: {
            parser_lex(parser);

            yp_token_t operator = parser->previous;
            yp_node_t *receiver = parse_expression(parser, yp_binding_powers[parser->previous.type].right, YP_ERR_UNARY_RECEIVER_MINUS);
            yp_call_node_t *node = yp_call_node_unary_create(parser, &operator, receiver, "-@");

            return (yp_node_t *) node;
        }
        case YP_TOKEN_UMINUS_NUM: {
            parser_lex(parser);

            yp_token_t operator = parser->previous;
            yp_node_t *node = parse_expression(parser, yp_binding_powers[parser->previous.type].right, YP_ERR_UNARY_RECEIVER_MINUS);

            switch (YP_NODE_TYPE(node)) {
                case YP_INTEGER_NODE:
                case YP_FLOAT_NODE:
                case YP_RATIONAL_NODE:
                case YP_IMAGINARY_NODE:
                    parse_negative_numeric(node);
                    break;
                default:
                    node = (yp_node_t *) yp_call_node_unary_create(parser, &operator, node, "-@");
                    break;
            }

            return node;
        }
        case YP_TOKEN_MINUS_GREATER: {
            int previous_lambda_enclosure_nesting = parser->lambda_enclosure_nesting;
            parser->lambda_enclosure_nesting = parser->enclosure_nesting;

            yp_accepts_block_stack_push(parser, true);
            parser_lex(parser);

            yp_token_t operator = parser->previous;
            yp_parser_scope_push(parser, false);
            yp_block_parameters_node_t *params;

            switch (parser->current.type) {
                case YP_TOKEN_PARENTHESIS_LEFT: {
                    yp_token_t opening = parser->current;
                    parser_lex(parser);

                    if (match_type_p(parser, YP_TOKEN_PARENTHESIS_RIGHT)) {
                        params = yp_block_parameters_node_create(parser, NULL, &opening);
                    } else {
                        params = parse_block_parameters(parser, false, &opening, true);
                    }

                    accept(parser, YP_TOKEN_NEWLINE);
                    expect(parser, YP_TOKEN_PARENTHESIS_RIGHT, YP_ERR_EXPECT_RPAREN);

                    yp_block_parameters_node_closing_set(params, &parser->previous);
                    break;
                }
                case YP_CASE_PARAMETER: {
                    yp_accepts_block_stack_push(parser, false);
                    yp_token_t opening = not_provided(parser);
                    params = parse_block_parameters(parser, false, &opening, true);
                    yp_accepts_block_stack_pop(parser);
                    break;
                }
                default: {
                    params = NULL;
                    break;
                }
            }

            yp_token_t opening;
            yp_node_t *body = NULL;
            parser->lambda_enclosure_nesting = previous_lambda_enclosure_nesting;

            if (accept(parser, YP_TOKEN_LAMBDA_BEGIN)) {
                opening = parser->previous;

                if (!accept(parser, YP_TOKEN_BRACE_RIGHT)) {
                    body = (yp_node_t *) parse_statements(parser, YP_CONTEXT_LAMBDA_BRACES);
                    expect(parser, YP_TOKEN_BRACE_RIGHT, YP_ERR_LAMBDA_TERM_BRACE);
                }
            } else {
                expect(parser, YP_TOKEN_KEYWORD_DO, YP_ERR_LAMBDA_OPEN);
                opening = parser->previous;

                if (!match_any_type_p(parser, 3, YP_TOKEN_KEYWORD_END, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE)) {
                    yp_accepts_block_stack_push(parser, true);
                    body = (yp_node_t *) parse_statements(parser, YP_CONTEXT_LAMBDA_DO_END);
                    yp_accepts_block_stack_pop(parser);
                }

                if (match_any_type_p(parser, 2, YP_TOKEN_KEYWORD_RESCUE, YP_TOKEN_KEYWORD_ENSURE)) {
                    assert(body == NULL || YP_NODE_TYPE_P(body, YP_STATEMENTS_NODE));
                    body = (yp_node_t *) parse_rescues_as_begin(parser, (yp_statements_node_t *) body);
                }

                expect(parser, YP_TOKEN_KEYWORD_END, YP_ERR_LAMBDA_TERM_END);
            }

            yp_constant_id_list_t locals = parser->current_scope->locals;
            yp_parser_scope_pop(parser);
            yp_accepts_block_stack_pop(parser);
            return (yp_node_t *) yp_lambda_node_create(parser, &locals, &operator, &opening, &parser->previous, params, body);
        }
        case YP_TOKEN_UPLUS: {
            parser_lex(parser);

            yp_token_t operator = parser->previous;
            yp_node_t *receiver = parse_expression(parser, yp_binding_powers[parser->previous.type].right, YP_ERR_UNARY_RECEIVER_PLUS);
            yp_call_node_t *node = yp_call_node_unary_create(parser, &operator, receiver, "+@");

            return (yp_node_t *) node;
        }
        case YP_TOKEN_STRING_BEGIN: {
            yp_node_t *result = NULL;

            while (match_type_p(parser, YP_TOKEN_STRING_BEGIN)) {
                assert(parser->lex_modes.current->mode == YP_LEX_STRING);
                bool lex_interpolation = parser->lex_modes.current->as.string.interpolation;

                yp_node_t *node = NULL;
                yp_token_t opening = parser->current;
                parser_lex(parser);

                if (accept(parser, YP_TOKEN_STRING_END)) {
                    // If we get here, then we have an end immediately after a
                    // start. In that case we'll create an empty content token
                    // and return an uninterpolated string.
                    yp_token_t content = (yp_token_t) {
                        .type = YP_TOKEN_STRING_CONTENT,
                        .start = parser->previous.start,
                        .end = parser->previous.start
                    };

                    node = (yp_node_t *) yp_string_node_create_and_unescape(parser, &opening, &content, &parser->previous, YP_UNESCAPE_NONE);
                } else if (accept(parser, YP_TOKEN_LABEL_END)) {
                    // If we get here, then we have an end of a label
                    // immediately after a start. In that case we'll create an
                    // empty symbol node.
                    yp_token_t opening = not_provided(parser);
                    yp_token_t content = (yp_token_t) {
                        .type = YP_TOKEN_STRING_CONTENT,
                        .start = parser->previous.start,
                        .end = parser->previous.start
                    };

                    node = (yp_node_t *) yp_symbol_node_create(parser, &opening, &content, &parser->previous);
                } else if (!lex_interpolation) {
                    // If we don't accept interpolation then we expect the
                    // string to start with a single string content node.
                    expect(parser, YP_TOKEN_STRING_CONTENT, YP_ERR_EXPECT_STRING_CONTENT);
                    yp_token_t content = parser->previous;

                    // It is unfortunately possible to have multiple string
                    // content nodes in a row in the case that there's heredoc
                    // content in the middle of the string, like this cursed
                    // example:
                    //
                    // <<-END+'b
                    //  a
                    // END
                    //  c'+'d'
                    //
                    // In that case we need to switch to an interpolated string
                    // to be able to contain all of the parts.
                    if (match_type_p(parser, YP_TOKEN_STRING_CONTENT)) {
                        yp_node_list_t parts = YP_EMPTY_NODE_LIST;

                        yp_token_t delimiters = not_provided(parser);
                        yp_node_t *part = (yp_node_t *) yp_string_node_create_and_unescape(parser, &delimiters, &content, &delimiters, YP_UNESCAPE_MINIMAL);
                        yp_node_list_append(&parts, part);

                        while (accept(parser, YP_TOKEN_STRING_CONTENT)) {
                            part = (yp_node_t *) yp_string_node_create_and_unescape(parser, &delimiters, &parser->previous, &delimiters, YP_UNESCAPE_MINIMAL);
                            yp_node_list_append(&parts, part);
                        }

                        expect(parser, YP_TOKEN_STRING_END, YP_ERR_STRING_LITERAL_TERM);
                        node = (yp_node_t *) yp_interpolated_string_node_create(parser, &opening, &parts, &parser->previous);
                    } else if (accept(parser, YP_TOKEN_LABEL_END)) {
                        node = (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &content, &parser->previous, YP_UNESCAPE_ALL);
                    } else {
                        expect(parser, YP_TOKEN_STRING_END, YP_ERR_STRING_LITERAL_TERM);
                        node = (yp_node_t *) yp_string_node_create_and_unescape(parser, &opening, &content, &parser->previous, YP_UNESCAPE_MINIMAL);
                    }
                } else if (match_type_p(parser, YP_TOKEN_STRING_CONTENT)) {
                    // In this case we've hit string content so we know the string at
                    // least has something in it. We'll need to check if the following
                    // token is the end (in which case we can return a plain string) or if
                    // it's not then it has interpolation.
                    yp_token_t content = parser->current;
                    parser_lex(parser);

                    if (accept(parser, YP_TOKEN_STRING_END)) {
                        node = (yp_node_t *) yp_string_node_create_and_unescape(parser, &opening, &content, &parser->previous, YP_UNESCAPE_ALL);
                    } else if (accept(parser, YP_TOKEN_LABEL_END)) {
                        node = (yp_node_t *) yp_symbol_node_create_and_unescape(parser, &opening, &content, &parser->previous, YP_UNESCAPE_ALL);
                    } else {
                        // If we get here, then we have interpolation so we'll need to create
                        // a string or symbol node with interpolation.
                        yp_node_list_t parts = YP_EMPTY_NODE_LIST;
                        yp_token_t string_opening = not_provided(parser);
                        yp_token_t string_closing = not_provided(parser);
                        yp_node_t *part = (yp_node_t *) yp_string_node_create_and_unescape(parser, &string_opening, &parser->previous, &string_closing, YP_UNESCAPE_ALL);
                        yp_node_list_append(&parts, part);

                        while (!match_any_type_p(parser, 3, YP_TOKEN_STRING_END, YP_TOKEN_LABEL_END, YP_TOKEN_EOF)) {
                            yp_node_t *part = parse_string_part(parser);
                            if (part != NULL) yp_node_list_append(&parts, part);
                        }

                        if (accept(parser, YP_TOKEN_LABEL_END)) {
                            node = (yp_node_t *) yp_interpolated_symbol_node_create(parser, &opening, &parts, &parser->previous);
                        } else {
                            expect(parser, YP_TOKEN_STRING_END, YP_ERR_STRING_INTERPOLATED_TERM);
                            node = (yp_node_t *) yp_interpolated_string_node_create(parser, &opening, &parts, &parser->previous);
                        }
                    }
                } else {
                    // If we get here, then the first part of the string is not plain string
                    // content, in which case we need to parse the string as an interpolated
                    // string.
                    yp_node_list_t parts = YP_EMPTY_NODE_LIST;

                    while (!match_any_type_p(parser, 3, YP_TOKEN_STRING_END, YP_TOKEN_LABEL_END, YP_TOKEN_EOF)) {
                        yp_node_t *part = parse_string_part(parser);
                        if (part != NULL) yp_node_list_append(&parts, part);
                    }

                    if (accept(parser, YP_TOKEN_LABEL_END)) {
                        node = (yp_node_t *) yp_interpolated_symbol_node_create(parser, &opening, &parts, &parser->previous);
                    } else {
                        expect(parser, YP_TOKEN_STRING_END, YP_ERR_STRING_INTERPOLATED_TERM);
                        node = (yp_node_t *) yp_interpolated_string_node_create(parser, &opening, &parts, &parser->previous);
                    }
                }

                if (result == NULL) {
                    // If the node we just parsed is a symbol node, then we
                    // can't concatenate it with anything else, so we can now
                    // return that node.
                    if (YP_NODE_TYPE_P(node, YP_SYMBOL_NODE) || YP_NODE_TYPE_P(node, YP_INTERPOLATED_SYMBOL_NODE)) {
                        return node;
                    }

                    // If we don't already have a node, then it's fine and we
                    // can just set the result to be the node we just parsed.
                    result = node;
                } else {
                    // Otherwise we need to check the type of the node we just
                    // parsed. If it cannot be concatenated with the previous
                    // node, then we'll need to add a syntax error.
                    if (!YP_NODE_TYPE_P(node, YP_STRING_NODE) && !YP_NODE_TYPE_P(node, YP_INTERPOLATED_STRING_NODE)) {
                        yp_diagnostic_list_append(&parser->error_list, node->location.start, node->location.end, YP_ERR_STRING_CONCATENATION);
                    }

                    // Either way we will create a concat node to hold the
                    // strings together.
                    result = (yp_node_t *) yp_string_concat_node_create(parser, result, node);
                }
            }

            return result;
        }
        case YP_TOKEN_SYMBOL_BEGIN: {
            yp_lex_mode_t lex_mode = *parser->lex_modes.current;
            parser_lex(parser);

            return parse_symbol(parser, &lex_mode, YP_LEX_STATE_END);
        }
        default:
            if (context_recoverable(parser, &parser->current)) {
                parser->recovering = true;
            }

            return (yp_node_t *) yp_missing_node_create(parser, parser->previous.start, parser->previous.end);
    }
}

static inline yp_node_t *
parse_assignment_value(yp_parser_t *parser, yp_binding_power_t previous_binding_power, yp_binding_power_t binding_power, yp_diagnostic_id_t diag_id) {
    yp_node_t *value = parse_starred_expression(parser, binding_power, diag_id);

    if (previous_binding_power == YP_BINDING_POWER_STATEMENT && (YP_NODE_TYPE_P(value, YP_SPLAT_NODE) || match_type_p(parser, YP_TOKEN_COMMA))) {
        yp_token_t opening = not_provided(parser);
        yp_array_node_t *array = yp_array_node_create(parser, &opening);

        yp_array_node_elements_append(array, value);
        value = (yp_node_t *) array;

        while (accept(parser, YP_TOKEN_COMMA)) {
            yp_node_t *element = parse_starred_expression(parser, binding_power, YP_ERR_ARRAY_ELEMENT);
            yp_array_node_elements_append(array, element);
            if (YP_NODE_TYPE_P(element, YP_MISSING_NODE)) break;
        }
    }

    return value;
}

static inline yp_node_t *
parse_expression_infix(yp_parser_t *parser, yp_node_t *node, yp_binding_power_t previous_binding_power, yp_binding_power_t binding_power) {
    yp_token_t token = parser->current;

    switch (token.type) {
        case YP_TOKEN_EQUAL: {
            switch (YP_NODE_TYPE(node)) {
                case YP_CALL_NODE: {
                    // If we have no arguments to the call node and we need this
                    // to be a target then this is either a method call or a
                    // local variable write. This _must_ happen before the value
                    // is parsed because it could be referenced in the value.
                    yp_call_node_t *call_node = (yp_call_node_t *) node;
                    if (yp_call_node_variable_call_p(call_node)) {
                        yp_parser_local_add_location(parser, call_node->message_loc.start, call_node->message_loc.end);
                    }
                }
                /* fallthrough */
                case YP_CASE_WRITABLE: {
                    parser_lex(parser);
                    yp_node_t *value = parse_assignment_value(parser, previous_binding_power, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_EQUAL);
                    return parse_write(parser, node, &token, value);
                }
                case YP_SPLAT_NODE: {
                    yp_splat_node_t *splat_node = (yp_splat_node_t *) node;

                    switch (YP_NODE_TYPE(splat_node->expression)) {
                        case YP_CASE_WRITABLE:
                            parser_lex(parser);
                            yp_node_t *value = parse_assignment_value(parser, previous_binding_power, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_EQUAL);
                            return parse_write(parser, (yp_node_t *) splat_node, &token, value);
                        default:
                            break;
                    }
                }
                /* fallthrough */
                default:
                    parser_lex(parser);

                    // In this case we have an = sign, but we don't know what it's for. We
                    // need to treat it as an error. For now, we'll mark it as an error
                    // and just skip right past it.
                    yp_diagnostic_list_append(&parser->error_list, token.start, token.end, YP_ERR_EXPECT_EXPRESSION_AFTER_EQUAL);
                    return node;
            }
        }
        case YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL: {
            switch (YP_NODE_TYPE(node)) {
                case YP_BACK_REFERENCE_READ_NODE:
                case YP_NUMBERED_REFERENCE_READ_NODE:
                    yp_diagnostic_list_append(&parser->error_list, node->location.start, node->location.end, YP_ERR_WRITE_TARGET_READONLY);
                /* fallthrough */
                case YP_GLOBAL_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                    yp_node_t *result = (yp_node_t *) yp_global_variable_and_write_node_create(parser, node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CLASS_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                    yp_node_t *result = (yp_node_t *) yp_class_variable_and_write_node_create(parser, (yp_class_variable_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CONSTANT_PATH_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                    return (yp_node_t *) yp_constant_path_and_write_node_create(parser, (yp_constant_path_node_t *) node, &token, value);
                }
                case YP_CONSTANT_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                    yp_node_t *result = (yp_node_t *) yp_constant_and_write_node_create(parser, (yp_constant_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_INSTANCE_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                    yp_node_t *result = (yp_node_t *) yp_instance_variable_and_write_node_create(parser, (yp_instance_variable_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_LOCAL_VARIABLE_READ_NODE: {
                    yp_local_variable_read_node_t *cast = (yp_local_variable_read_node_t *) node;
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                    yp_node_t *result = (yp_node_t *) yp_local_variable_and_write_node_create(parser, node, &token, value, cast->name, cast->depth);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CALL_NODE: {
                    yp_call_node_t *call_node = (yp_call_node_t *) node;

                    // If we have a vcall (a method with no arguments and no
                    // receiver that could have been a local variable) then we
                    // will transform it into a local variable write.
                    if (yp_call_node_variable_call_p(call_node)) {
                        yp_location_t message_loc = call_node->message_loc;
                        yp_constant_id_t constant_id = yp_parser_local_add_location(parser, message_loc.start, message_loc.end);

                        if (token_is_numbered_parameter(message_loc.start, message_loc.end)) {
                            yp_diagnostic_list_append(&parser->error_list, message_loc.start, message_loc.end, YP_ERR_PARAMETER_NUMBERED_RESERVED);
                        }

                        parser_lex(parser);
                        yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                        yp_node_t *result = (yp_node_t *) yp_local_variable_and_write_node_create(parser, node, &token, value, constant_id, 0);

                        yp_node_destroy(parser, node);
                        return result;
                    }

                    parser_lex(parser);
                    node = parse_target(parser, node);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                    return (yp_node_t *) yp_call_and_write_node_create(parser, (yp_call_node_t *) node, &token, value);
                }
                case YP_MULTI_WRITE_NODE: {
                    parser_lex(parser);
                    yp_diagnostic_list_append(&parser->error_list, token.start, token.end, YP_ERR_AMPAMPEQ_MULTI_ASSIGN);
                    return node;
                }
                default:
                    parser_lex(parser);

                    // In this case we have an &&= sign, but we don't know what it's for.
                    // We need to treat it as an error. For now, we'll mark it as an error
                    // and just skip right past it.
                    yp_diagnostic_list_append(&parser->error_list, token.start, token.end, YP_ERR_EXPECT_EXPRESSION_AFTER_AMPAMPEQ);
                    return node;
            }
        }
        case YP_TOKEN_PIPE_PIPE_EQUAL: {
            switch (YP_NODE_TYPE(node)) {
                case YP_BACK_REFERENCE_READ_NODE:
                case YP_NUMBERED_REFERENCE_READ_NODE:
                    yp_diagnostic_list_append(&parser->error_list, node->location.start, node->location.end, YP_ERR_WRITE_TARGET_READONLY);
                /* fallthrough */
                case YP_GLOBAL_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                    yp_node_t *result = (yp_node_t *) yp_global_variable_or_write_node_create(parser, node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CLASS_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                    yp_node_t *result = (yp_node_t *) yp_class_variable_or_write_node_create(parser, (yp_class_variable_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CONSTANT_PATH_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                    return (yp_node_t *) yp_constant_path_or_write_node_create(parser, (yp_constant_path_node_t *) node, &token, value);
                }
                case YP_CONSTANT_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                    yp_node_t *result = (yp_node_t *) yp_constant_or_write_node_create(parser, (yp_constant_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_INSTANCE_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                    yp_node_t *result = (yp_node_t *) yp_instance_variable_or_write_node_create(parser, (yp_instance_variable_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_LOCAL_VARIABLE_READ_NODE: {
                    yp_local_variable_read_node_t *cast = (yp_local_variable_read_node_t *) node;
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                    yp_node_t *result = (yp_node_t *) yp_local_variable_or_write_node_create(parser, node, &token, value, cast->name, cast->depth);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CALL_NODE: {
                    yp_call_node_t *call_node = (yp_call_node_t *) node;

                    // If we have a vcall (a method with no arguments and no
                    // receiver that could have been a local variable) then we
                    // will transform it into a local variable write.
                    if (yp_call_node_variable_call_p(call_node)) {
                        yp_location_t message_loc = call_node->message_loc;
                        yp_constant_id_t constant_id = yp_parser_local_add_location(parser, message_loc.start, message_loc.end);

                        if (token_is_numbered_parameter(message_loc.start, message_loc.end)) {
                            yp_diagnostic_list_append(&parser->error_list, message_loc.start, message_loc.end, YP_ERR_PARAMETER_NUMBERED_RESERVED);
                        }

                        parser_lex(parser);
                        yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                        yp_node_t *result = (yp_node_t *) yp_local_variable_or_write_node_create(parser, node, &token, value, constant_id, 0);

                        yp_node_destroy(parser, node);
                        return result;
                    }

                    parser_lex(parser);
                    node = parse_target(parser, node);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                    return (yp_node_t *) yp_call_or_write_node_create(parser, (yp_call_node_t *) node, &token, value);
                }
                case YP_MULTI_WRITE_NODE: {
                    parser_lex(parser);
                    yp_diagnostic_list_append(&parser->error_list, token.start, token.end, YP_ERR_PIPEPIPEEQ_MULTI_ASSIGN);
                    return node;
                }
                default:
                    parser_lex(parser);

                    // In this case we have an ||= sign, but we don't know what it's for.
                    // We need to treat it as an error. For now, we'll mark it as an error
                    // and just skip right past it.
                    yp_diagnostic_list_append(&parser->error_list, token.start, token.end, YP_ERR_EXPECT_EXPRESSION_AFTER_PIPEPIPEEQ);
                    return node;
            }
        }
        case YP_TOKEN_AMPERSAND_EQUAL:
        case YP_TOKEN_CARET_EQUAL:
        case YP_TOKEN_GREATER_GREATER_EQUAL:
        case YP_TOKEN_LESS_LESS_EQUAL:
        case YP_TOKEN_MINUS_EQUAL:
        case YP_TOKEN_PERCENT_EQUAL:
        case YP_TOKEN_PIPE_EQUAL:
        case YP_TOKEN_PLUS_EQUAL:
        case YP_TOKEN_SLASH_EQUAL:
        case YP_TOKEN_STAR_EQUAL:
        case YP_TOKEN_STAR_STAR_EQUAL: {
            switch (YP_NODE_TYPE(node)) {
                case YP_BACK_REFERENCE_READ_NODE:
                case YP_NUMBERED_REFERENCE_READ_NODE:
                    yp_diagnostic_list_append(&parser->error_list, node->location.start, node->location.end, YP_ERR_WRITE_TARGET_READONLY);
                /* fallthrough */
                case YP_GLOBAL_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                    yp_node_t *result = (yp_node_t *) yp_global_variable_operator_write_node_create(parser, node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CLASS_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                    yp_node_t *result = (yp_node_t *) yp_class_variable_operator_write_node_create(parser, (yp_class_variable_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CONSTANT_PATH_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                    return (yp_node_t *) yp_constant_path_operator_write_node_create(parser, (yp_constant_path_node_t *) node, &token, value);
                }
                case YP_CONSTANT_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                    yp_node_t *result = (yp_node_t *) yp_constant_operator_write_node_create(parser, (yp_constant_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_INSTANCE_VARIABLE_READ_NODE: {
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                    yp_node_t *result = (yp_node_t *) yp_instance_variable_operator_write_node_create(parser, (yp_instance_variable_read_node_t *) node, &token, value);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_LOCAL_VARIABLE_READ_NODE: {
                    yp_local_variable_read_node_t *cast = (yp_local_variable_read_node_t *) node;
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                    yp_node_t *result = (yp_node_t *) yp_local_variable_operator_write_node_create(parser, node, &token, value, cast->name, cast->depth);

                    yp_node_destroy(parser, node);
                    return result;
                }
                case YP_CALL_NODE: {
                    yp_call_node_t *call_node = (yp_call_node_t *) node;

                    // If we have a vcall (a method with no arguments and no
                    // receiver that could have been a local variable) then we
                    // will transform it into a local variable write.
                    if (yp_call_node_variable_call_p(call_node)) {
                        yp_location_t message_loc = call_node->message_loc;
                        yp_constant_id_t constant_id = yp_parser_local_add_location(parser, message_loc.start, message_loc.end);

                        if (token_is_numbered_parameter(message_loc.start, message_loc.end)) {
                            yp_diagnostic_list_append(&parser->error_list, message_loc.start, message_loc.end, YP_ERR_PARAMETER_NUMBERED_RESERVED);
                        }

                        parser_lex(parser);
                        yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                        yp_node_t *result = (yp_node_t *) yp_local_variable_operator_write_node_create(parser, node, &token, value, constant_id, 0);

                        yp_node_destroy(parser, node);
                        return result;
                    }

                    node = parse_target(parser, node);
                    parser_lex(parser);

                    yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                    return (yp_node_t *) yp_call_operator_write_node_create(parser, (yp_call_node_t *) node, &token, value);
                }
                case YP_MULTI_WRITE_NODE: {
                    parser_lex(parser);
                    yp_diagnostic_list_append(&parser->error_list, token.start, token.end, YP_ERR_OPERATOR_MULTI_ASSIGN);
                    return node;
                }
                default:
                    parser_lex(parser);

                    // In this case we have an operator but we don't know what it's for.
                    // We need to treat it as an error. For now, we'll mark it as an error
                    // and just skip right past it.
                    yp_diagnostic_list_append(&parser->error_list, parser->previous.start, parser->previous.end, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
                    return node;
            }
        }
        case YP_TOKEN_AMPERSAND_AMPERSAND:
        case YP_TOKEN_KEYWORD_AND: {
            parser_lex(parser);

            yp_node_t *right = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
            return (yp_node_t *) yp_and_node_create(parser, node, &token, right);
        }
        case YP_TOKEN_KEYWORD_OR:
        case YP_TOKEN_PIPE_PIPE: {
            parser_lex(parser);

            yp_node_t *right = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
            return (yp_node_t *) yp_or_node_create(parser, node, &token, right);
        }
        case YP_TOKEN_EQUAL_TILDE: {
            // Note that we _must_ parse the value before adding the local variables
            // in order to properly mirror the behavior of Ruby. For example,
            //
            //     /(?<foo>bar)/ =~ foo
            //
            // In this case, `foo` should be a method call and not a local yet.
            parser_lex(parser);
            yp_node_t *argument = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);

            // If the receiver of this =~ is a regular expression node, then we need
            // to introduce local variables for it based on its named capture groups.
            if (YP_NODE_TYPE_P(node, YP_REGULAR_EXPRESSION_NODE)) {
                yp_string_list_t named_captures;
                yp_string_list_init(&named_captures);

                const yp_location_t *content_loc = &((yp_regular_expression_node_t *) node)->content_loc;

                if (yp_regexp_named_capture_group_names(content_loc->start, (size_t) (content_loc->end - content_loc->start), &named_captures, parser->encoding_changed, &parser->encoding)) {
                    for (size_t index = 0; index < named_captures.length; index++) {
                        yp_string_t *name = &named_captures.strings[index];
                        assert(name->type == YP_STRING_SHARED);

                        yp_parser_local_add_location(parser, name->source, name->source + name->length);
                    }
                }

                yp_string_list_free(&named_captures);
            }

            return (yp_node_t *) yp_call_node_binary_create(parser, node, &token, argument);
        }
        case YP_TOKEN_UAMPERSAND:
        case YP_TOKEN_USTAR:
        case YP_TOKEN_USTAR_STAR:
            // The only times this will occur are when we are in an error state,
            // but we'll put them in here so that errors can propagate.
        case YP_TOKEN_BANG_EQUAL:
        case YP_TOKEN_BANG_TILDE:
        case YP_TOKEN_EQUAL_EQUAL:
        case YP_TOKEN_EQUAL_EQUAL_EQUAL:
        case YP_TOKEN_LESS_EQUAL_GREATER:
        case YP_TOKEN_GREATER:
        case YP_TOKEN_GREATER_EQUAL:
        case YP_TOKEN_LESS:
        case YP_TOKEN_LESS_EQUAL:
        case YP_TOKEN_CARET:
        case YP_TOKEN_PIPE:
        case YP_TOKEN_AMPERSAND:
        case YP_TOKEN_GREATER_GREATER:
        case YP_TOKEN_LESS_LESS:
        case YP_TOKEN_MINUS:
        case YP_TOKEN_PLUS:
        case YP_TOKEN_PERCENT:
        case YP_TOKEN_SLASH:
        case YP_TOKEN_STAR:
        case YP_TOKEN_STAR_STAR: {
            parser_lex(parser);

            yp_node_t *argument = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
            return (yp_node_t *) yp_call_node_binary_create(parser, node, &token, argument);
        }
        case YP_TOKEN_AMPERSAND_DOT:
        case YP_TOKEN_DOT: {
            parser_lex(parser);
            yp_token_t operator = parser->previous;
            yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;

            // This if statement handles the foo.() syntax.
            if (match_type_p(parser, YP_TOKEN_PARENTHESIS_LEFT)) {
                parse_arguments_list(parser, &arguments, true);
                return (yp_node_t *) yp_call_node_shorthand_create(parser, node, &operator, &arguments);
            }

            yp_token_t message;

            switch (parser->current.type) {
                case YP_CASE_OPERATOR:
                case YP_CASE_KEYWORD:
                case YP_TOKEN_CONSTANT:
                case YP_TOKEN_IDENTIFIER: {
                    parser_lex(parser);
                    message = parser->previous;
                    break;
                }
                default: {
                    yp_diagnostic_list_append(&parser->error_list, parser->current.start, parser->current.end, YP_ERR_DEF_NAME);
                    message = (yp_token_t) { .type = YP_TOKEN_MISSING, .start = parser->previous.end, .end = parser->previous.end };
                }
            }

            parse_arguments_list(parser, &arguments, true);
            yp_call_node_t *call = yp_call_node_call_create(parser, node, &operator, &message, &arguments);

            if (
                (previous_binding_power == YP_BINDING_POWER_STATEMENT) &&
                arguments.arguments == NULL &&
                arguments.opening_loc.start == NULL &&
                match_type_p(parser, YP_TOKEN_COMMA)
            ) {
                return parse_targets(parser, (yp_node_t *) call, YP_BINDING_POWER_INDEX);
            } else {
                return (yp_node_t *) call;
            }
        }
        case YP_TOKEN_DOT_DOT:
        case YP_TOKEN_DOT_DOT_DOT: {
            parser_lex(parser);

            yp_node_t *right = NULL;
            if (token_begins_expression_p(parser->current.type)) {
                right = parse_expression(parser, binding_power, YP_ERR_EXPECT_EXPRESSION_AFTER_OPERATOR);
            }

            return (yp_node_t *) yp_range_node_create(parser, node, &token, right);
        }
        case YP_TOKEN_KEYWORD_IF_MODIFIER: {
            yp_token_t keyword = parser->current;
            parser_lex(parser);

            yp_node_t *predicate = parse_expression(parser, binding_power, YP_ERR_CONDITIONAL_IF_PREDICATE);
            return (yp_node_t *) yp_if_node_modifier_create(parser, node, &keyword, predicate);
        }
        case YP_TOKEN_KEYWORD_UNLESS_MODIFIER: {
            yp_token_t keyword = parser->current;
            parser_lex(parser);

            yp_node_t *predicate = parse_expression(parser, binding_power, YP_ERR_CONDITIONAL_UNLESS_PREDICATE);
            return (yp_node_t *) yp_unless_node_modifier_create(parser, node, &keyword, predicate);
        }
        case YP_TOKEN_KEYWORD_UNTIL_MODIFIER: {
            parser_lex(parser);
            yp_statements_node_t *statements = yp_statements_node_create(parser);
            yp_statements_node_body_append(statements, node);

            yp_node_t *predicate = parse_expression(parser, binding_power, YP_ERR_CONDITIONAL_UNTIL_PREDICATE);
            return (yp_node_t *) yp_until_node_modifier_create(parser, &token, predicate, statements, YP_NODE_TYPE_P(node, YP_BEGIN_NODE) ? YP_LOOP_FLAGS_BEGIN_MODIFIER : 0);
        }
        case YP_TOKEN_KEYWORD_WHILE_MODIFIER: {
            parser_lex(parser);
            yp_statements_node_t *statements = yp_statements_node_create(parser);
            yp_statements_node_body_append(statements, node);

            yp_node_t *predicate = parse_expression(parser, binding_power, YP_ERR_CONDITIONAL_WHILE_PREDICATE);
            return (yp_node_t *) yp_while_node_modifier_create(parser, &token, predicate, statements, YP_NODE_TYPE_P(node, YP_BEGIN_NODE) ? YP_LOOP_FLAGS_BEGIN_MODIFIER : 0);
        }
        case YP_TOKEN_QUESTION_MARK: {
            parser_lex(parser);
            yp_node_t *true_expression = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_TERNARY_EXPRESSION_TRUE);

            if (parser->recovering) {
                // If parsing the true expression of this ternary resulted in a syntax
                // error that we can recover from, then we're going to put missing nodes
                // and tokens into the remaining places. We want to be sure to do this
                // before the `expect` function call to make sure it doesn't
                // accidentally move past a ':' token that occurs after the syntax
                // error.
                yp_token_t colon = (yp_token_t) { .type = YP_TOKEN_MISSING, .start = parser->previous.end, .end = parser->previous.end };
                yp_node_t *false_expression = (yp_node_t *) yp_missing_node_create(parser, colon.start, colon.end);

                return (yp_node_t *) yp_if_node_ternary_create(parser, node, true_expression, &colon, false_expression);
            }

            accept(parser, YP_TOKEN_NEWLINE);
            expect(parser, YP_TOKEN_COLON, YP_ERR_TERNARY_COLON);

            yp_token_t colon = parser->previous;
            yp_node_t *false_expression = parse_expression(parser, YP_BINDING_POWER_DEFINED, YP_ERR_TERNARY_EXPRESSION_FALSE);

            return (yp_node_t *) yp_if_node_ternary_create(parser, node, true_expression, &colon, false_expression);
        }
        case YP_TOKEN_COLON_COLON: {
            parser_lex(parser);
            yp_token_t delimiter = parser->previous;

            switch (parser->current.type) {
                case YP_TOKEN_CONSTANT: {
                    parser_lex(parser);
                    yp_node_t *path;

                    if (
                        (parser->current.type == YP_TOKEN_PARENTHESIS_LEFT) ||
                        (token_begins_expression_p(parser->current.type) || match_any_type_p(parser, 3, YP_TOKEN_UAMPERSAND, YP_TOKEN_USTAR, YP_TOKEN_USTAR_STAR))
                    ) {
                        // If we have a constant immediately following a '::' operator, then
                        // this can either be a constant path or a method call, depending on
                        // what follows the constant.
                        //
                        // If we have parentheses, then this is a method call. That would
                        // look like Foo::Bar().
                        yp_token_t message = parser->previous;
                        yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;

                        parse_arguments_list(parser, &arguments, true);
                        path = (yp_node_t *) yp_call_node_call_create(parser, node, &delimiter, &message, &arguments);
                    } else {
                        // Otherwise, this is a constant path. That would look like Foo::Bar.
                        yp_node_t *child = (yp_node_t *) yp_constant_read_node_create(parser, &parser->previous);
                        path = (yp_node_t *)yp_constant_path_node_create(parser, node, &delimiter, child);
                    }

                    // If this is followed by a comma then it is a multiple assignment.
                    if (previous_binding_power == YP_BINDING_POWER_STATEMENT && match_type_p(parser, YP_TOKEN_COMMA)) {
                        return parse_targets(parser, path, YP_BINDING_POWER_INDEX);
                    }

                    return path;
                }
                case YP_CASE_OPERATOR:
                case YP_CASE_KEYWORD:
                case YP_TOKEN_IDENTIFIER: {
                    parser_lex(parser);
                    yp_token_t message = parser->previous;

                    // If we have an identifier following a '::' operator, then it is for
                    // sure a method call.
                    yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;
                    parse_arguments_list(parser, &arguments, true);
                    yp_call_node_t *call = yp_call_node_call_create(parser, node, &delimiter, &message, &arguments);

                    // If this is followed by a comma then it is a multiple assignment.
                    if (previous_binding_power == YP_BINDING_POWER_STATEMENT && match_type_p(parser, YP_TOKEN_COMMA)) {
                        return parse_targets(parser, (yp_node_t *) call, YP_BINDING_POWER_INDEX);
                    }

                    return (yp_node_t *) call;
                }
                case YP_TOKEN_PARENTHESIS_LEFT: {
                    // If we have a parenthesis following a '::' operator, then it is the
                    // method call shorthand. That would look like Foo::(bar).
                    yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;
                    parse_arguments_list(parser, &arguments, true);

                    return (yp_node_t *) yp_call_node_shorthand_create(parser, node, &delimiter, &arguments);
                }
                default: {
                    yp_diagnostic_list_append(&parser->error_list, delimiter.start, delimiter.end, YP_ERR_CONSTANT_PATH_COLON_COLON_CONSTANT);
                    yp_node_t *child = (yp_node_t *) yp_missing_node_create(parser, delimiter.start, delimiter.end);
                    return (yp_node_t *)yp_constant_path_node_create(parser, node, &delimiter, child);
                }
            }
        }
        case YP_TOKEN_KEYWORD_RESCUE_MODIFIER: {
            parser_lex(parser);
            accept(parser, YP_TOKEN_NEWLINE);
            yp_node_t *value = parse_expression(parser, binding_power, YP_ERR_RESCUE_MODIFIER_VALUE);

            return (yp_node_t *) yp_rescue_modifier_node_create(parser, node, &token, value);
        }
        case YP_TOKEN_BRACKET_LEFT: {
            parser_lex(parser);

            yp_arguments_t arguments = YP_EMPTY_ARGUMENTS;
            arguments.opening_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);

            if (!accept(parser, YP_TOKEN_BRACKET_RIGHT)) {
                yp_accepts_block_stack_push(parser, true);
                arguments.arguments = yp_arguments_node_create(parser);

                parse_arguments(parser, &arguments, false, YP_TOKEN_BRACKET_RIGHT);
                yp_accepts_block_stack_pop(parser);

                expect(parser, YP_TOKEN_BRACKET_RIGHT, YP_ERR_EXPECT_RBRACKET);
            }

            arguments.closing_loc = YP_LOCATION_TOKEN_VALUE(&parser->previous);

            // If we have a comma after the closing bracket then this is a multiple
            // assignment and we should parse the targets.
            if (previous_binding_power == YP_BINDING_POWER_STATEMENT && match_type_p(parser, YP_TOKEN_COMMA)) {
                yp_call_node_t *aref = yp_call_node_aref_create(parser, node, &arguments);
                return parse_targets(parser, (yp_node_t *) aref, YP_BINDING_POWER_INDEX);
            }

            // If we're at the end of the arguments, we can now check if there is a
            // block node that starts with a {. If there is, then we can parse it and
            // add it to the arguments.
            if (accept(parser, YP_TOKEN_BRACE_LEFT)) {
                arguments.block = parse_block(parser);
            } else if (yp_accepts_block_stack_p(parser) && accept(parser, YP_TOKEN_KEYWORD_DO)) {
                arguments.block = parse_block(parser);
            }

            yp_arguments_validate(parser, &arguments);
            return (yp_node_t *) yp_call_node_aref_create(parser, node, &arguments);
        }
        case YP_TOKEN_KEYWORD_IN: {
            bool previous_pattern_matching_newlines = parser->pattern_matching_newlines;
            parser->pattern_matching_newlines = true;

            yp_token_t operator = parser->current;
            parser->command_start = false;
            lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);

            parser_lex(parser);

            yp_node_t *pattern = parse_pattern(parser, true, YP_ERR_PATTERN_EXPRESSION_AFTER_IN);
            parser->pattern_matching_newlines = previous_pattern_matching_newlines;

            return (yp_node_t *) yp_match_predicate_node_create(parser, node, pattern, &operator);
        }
        case YP_TOKEN_EQUAL_GREATER: {
            bool previous_pattern_matching_newlines = parser->pattern_matching_newlines;
            parser->pattern_matching_newlines = true;

            yp_token_t operator = parser->current;
            parser->command_start = false;
            lex_state_set(parser, YP_LEX_STATE_BEG | YP_LEX_STATE_LABEL);

            parser_lex(parser);

            yp_node_t *pattern = parse_pattern(parser, true, YP_ERR_PATTERN_EXPRESSION_AFTER_HROCKET);
            parser->pattern_matching_newlines = previous_pattern_matching_newlines;

            return (yp_node_t *) yp_match_required_node_create(parser, node, pattern, &operator);
        }
        default:
            assert(false && "unreachable");
            return NULL;
    }
}

// Parse an expression at the given point of the parser using the given binding
// power to parse subsequent chains. If this function finds a syntax error, it
// will append the error message to the parser's error list.
//
// Consumers of this function should always check parser->recovering to
// determine if they need to perform additional cleanup.
static yp_node_t *
parse_expression(yp_parser_t *parser, yp_binding_power_t binding_power, yp_diagnostic_id_t diag_id) {
    yp_token_t recovery = parser->previous;
    yp_node_t *node = parse_expression_prefix(parser, binding_power);

    // If we found a syntax error, then the type of node returned by
    // parse_expression_prefix is going to be a missing node. In that case we need
    // to add the error message to the parser's error list.
    if (YP_NODE_TYPE_P(node, YP_MISSING_NODE)) {
        yp_diagnostic_list_append(&parser->error_list, recovery.end, recovery.end, diag_id);
        return node;
    }

    // Otherwise we'll look and see if the next token can be parsed as an infix
    // operator. If it can, then we'll parse it using parse_expression_infix.
    yp_binding_powers_t current_binding_powers;
    while (
        current_binding_powers = yp_binding_powers[parser->current.type],
        binding_power <= current_binding_powers.left &&
        current_binding_powers.binary
     ) {
        node = parse_expression_infix(parser, node, binding_power, current_binding_powers.right);
    }

    return node;
}

static yp_node_t *
parse_program(yp_parser_t *parser) {
    yp_parser_scope_push(parser, !parser->current_scope);
    parser_lex(parser);

    yp_statements_node_t *statements = parse_statements(parser, YP_CONTEXT_MAIN);
    if (!statements) {
        statements = yp_statements_node_create(parser);
    }
    yp_constant_id_list_t locals = parser->current_scope->locals;
    yp_parser_scope_pop(parser);

    // If this is an empty file, then we're still going to parse all of the
    // statements in order to gather up all of the comments and such. Here we'll
    // correct the location information.
    if (yp_statements_node_body_length(statements) == 0) {
        yp_statements_node_location_set(statements, parser->start, parser->start);
    }

    return (yp_node_t *) yp_program_node_create(parser, &locals, statements);
}

// Read a 32-bit unsigned integer from a pointer. This function is used to read
// the metadata that is passed into the parser from the Ruby implementation. It
// handles aligned and unaligned reads.
static uint32_t
yp_metadata_read_u32(const char *ptr) {
    if (((uintptr_t) ptr) % sizeof(uint32_t) == 0) {
        return *((uint32_t *) ptr);
    } else {
        uint32_t value;
        memcpy(&value, ptr, sizeof(uint32_t));
        return value;
    }
}

// Process any additional metadata being passed into a call to the parser via
// the yp_parse_serialize function. Since the source of these calls will be from
// Ruby implementation internals we assume it is from a trusted source.
//
// Currently, this is only passing in variable scoping surrounding an eval, but
// eventually it will be extended to hold any additional metadata.  This data
// is serialized to reduce the calling complexity for a foreign function call
// vs a foreign runtime making a bindable in-memory version of a C structure.
//
// metadata is assumed to be a valid pointer pointing to well-formed data. The
// format is described below:
//
// ```text
// [
//   filepath_size: uint32_t,
//   filepath: char*,
//   scopes_count: uint32_t,
//   [
//     locals_count: uint32_t,
//     [local_size: uint32_t, local: char*]*
//   ]*
// ]
// ```
void
yp_parser_metadata(yp_parser_t *parser, const char *metadata) {
    uint32_t filepath_size = yp_metadata_read_u32(metadata);
    metadata += 4;

    if (filepath_size) {
        yp_string_t filepath_string;
        yp_string_constant_init(&filepath_string, metadata, filepath_size);

        parser->filepath_string = filepath_string;
        metadata += filepath_size;
    }

    uint32_t scopes_count = yp_metadata_read_u32(metadata);
    metadata += 4;

    for (size_t scope_index = 0; scope_index < scopes_count; scope_index++) {
        uint32_t locals_count = yp_metadata_read_u32(metadata);
        metadata += 4;

        yp_parser_scope_push(parser, scope_index == 0);

        for (size_t local_index = 0; local_index < locals_count; local_index++) {
            uint32_t local_size = yp_metadata_read_u32(metadata);
            metadata += 4;

            uint8_t *constant = malloc(local_size);
            memcpy(constant, metadata, local_size);

            yp_parser_local_add_owned(parser, constant, (size_t) local_size);
            metadata += local_size;
        }
    }
}

/******************************************************************************/
/* External functions                                                         */
/******************************************************************************/

// Initialize a parser with the given start and end pointers.
YP_EXPORTED_FUNCTION void
yp_parser_init(yp_parser_t *parser, const uint8_t *source, size_t size, const char *filepath) {
    assert(source != NULL);

    // Set filepath to the file that was passed
    if (!filepath) filepath = "";
    yp_string_t filepath_string;
    yp_string_constant_init(&filepath_string, filepath, strlen(filepath));

    *parser = (yp_parser_t) {
        .lex_state = YP_LEX_STATE_BEG,
        .command_start = true,
        .enclosure_nesting = 0,
        .lambda_enclosure_nesting = -1,
        .brace_nesting = 0,
        .do_loop_stack = YP_STATE_STACK_EMPTY,
        .accepts_block_stack = YP_STATE_STACK_EMPTY,
        .lex_modes = {
            .index = 0,
            .stack = {{ .mode = YP_LEX_DEFAULT }},
            .current = &parser->lex_modes.stack[0],
        },
        .start = source,
        .end = source + size,
        .previous = { .type = YP_TOKEN_EOF, .start = source, .end = source },
        .current = { .type = YP_TOKEN_EOF, .start = source, .end = source },
        .next_start = NULL,
        .heredoc_end = NULL,
        .comment_list = YP_LIST_EMPTY,
        .warning_list = YP_LIST_EMPTY,
        .error_list = YP_LIST_EMPTY,
        .current_scope = NULL,
        .current_context = NULL,
        .recovering = false,
        .encoding = yp_encoding_utf_8,
        .encoding_changed = false,
        .encoding_changed_callback = NULL,
        .encoding_decode_callback = NULL,
        .encoding_comment_start = source,
        .lex_callback = NULL,
        .pattern_matching_newlines = false,
        .in_keyword_arg = false,
        .filepath_string = filepath_string,
        .constant_pool = YP_CONSTANT_POOL_EMPTY,
        .newline_list = YP_NEWLINE_LIST_EMPTY
    };

    yp_accepts_block_stack_push(parser, true);

    // Initialize the constant pool. We're going to completely guess as to the
    // number of constants that we'll need based on the size of the input. The
    // ratio we chose here is actually less arbitrary than you might think.
    //
    // We took ~50K Ruby files and measured the size of the file versus the
    // number of constants that were found in those files. Then we found the
    // average and standard deviation of the ratios of constants/bytesize. Then
    // we added 1.34 standard deviations to the average to get a ratio that
    // would fit 75% of the files (for a two-tailed distribution). This works
    // because there was about a 0.77 correlation and the distribution was
    // roughly normal.
    //
    // This ratio will need to change if we add more constants to the constant
    // pool for another node type.
    size_t constant_size = size / 95;
    yp_constant_pool_init(&parser->constant_pool, constant_size < 4 ? 4 : constant_size);

    // Initialize the newline list. Similar to the constant pool, we're going to
    // guess at the number of newlines that we'll need based on the size of the
    // input.
    size_t newline_size = size / 22;
    yp_newline_list_init(&parser->newline_list, source, newline_size < 4 ? 4 : newline_size);

    // Skip past the UTF-8 BOM if it exists.
    if (size >= 3 && source[0] == 0xef && source[1] == 0xbb && source[2] == 0xbf) {
        parser->current.end += 3;
        parser->encoding_comment_start += 3;
    }

    // If the first two bytes of the source are a shebang, then we'll indicate
    // that the encoding comment is at the end of the shebang.
    if (peek(parser) == '#' && peek_offset(parser, 1) == '!') {
        const uint8_t *encoding_comment_start = next_newline(source, (ptrdiff_t) size);
        if (encoding_comment_start) {
            parser->encoding_comment_start = encoding_comment_start + 1;
        }
    }
}

// Register a callback that will be called whenever YARP changes the encoding it
// is using to parse based on the magic comment.
YP_EXPORTED_FUNCTION void
yp_parser_register_encoding_changed_callback(yp_parser_t *parser, yp_encoding_changed_callback_t callback) {
    parser->encoding_changed_callback = callback;
}

// Register a callback that will be called when YARP encounters a magic comment
// with an encoding referenced that it doesn't understand. The callback should
// return NULL if it also doesn't understand the encoding or it should return a
// pointer to a yp_encoding_t struct that contains the functions necessary to
// parse identifiers.
YP_EXPORTED_FUNCTION void
yp_parser_register_encoding_decode_callback(yp_parser_t *parser, yp_encoding_decode_callback_t callback) {
    parser->encoding_decode_callback = callback;
}

// Free all of the memory associated with the comment list.
static inline void
yp_comment_list_free(yp_list_t *list) {
    yp_list_node_t *node, *next;

    for (node = list->head; node != NULL; node = next) {
        next = node->next;

        yp_comment_t *comment = (yp_comment_t *) node;
        free(comment);
    }
}

// Free any memory associated with the given parser.
YP_EXPORTED_FUNCTION void
yp_parser_free(yp_parser_t *parser) {
    yp_string_free(&parser->filepath_string);
    yp_diagnostic_list_free(&parser->error_list);
    yp_diagnostic_list_free(&parser->warning_list);
    yp_comment_list_free(&parser->comment_list);
    yp_constant_pool_free(&parser->constant_pool);
    yp_newline_list_free(&parser->newline_list);

    while (parser->current_scope != NULL) {
        // Normally, popping the scope doesn't free the locals since it is
        // assumed that ownership has transferred to the AST. However if we have
        // scopes while we're freeing the parser, it's likely they came from
        // eval scopes and we need to free them explicitly here.
        yp_constant_id_list_free(&parser->current_scope->locals);
        yp_parser_scope_pop(parser);
    }

    while (parser->lex_modes.index >= YP_LEX_STACK_SIZE) {
        lex_mode_pop(parser);
    }
}

// Parse the Ruby source associated with the given parser and return the tree.
YP_EXPORTED_FUNCTION yp_node_t *
yp_parse(yp_parser_t *parser) {
    return parse_program(parser);
}

YP_EXPORTED_FUNCTION void
yp_serialize(yp_parser_t *parser, yp_node_t *node, yp_buffer_t *buffer) {
    yp_buffer_append_str(buffer, "YARP", 4);
    yp_buffer_append_u8(buffer, YP_VERSION_MAJOR);
    yp_buffer_append_u8(buffer, YP_VERSION_MINOR);
    yp_buffer_append_u8(buffer, YP_VERSION_PATCH);

    yp_serialize_content(parser, node, buffer);
    yp_buffer_append_str(buffer, "\0", 1);
}

// Parse and serialize the AST represented by the given source to the given
// buffer.
YP_EXPORTED_FUNCTION void
yp_parse_serialize(const uint8_t *source, size_t size, yp_buffer_t *buffer, const char *metadata) {
    yp_parser_t parser;
    yp_parser_init(&parser, source, size, NULL);
    if (metadata) yp_parser_metadata(&parser, metadata);

    yp_node_t *node = yp_parse(&parser);
    yp_serialize(&parser, node, buffer);

    yp_node_destroy(&parser, node);
    yp_parser_free(&parser);
}

#undef YP_LOCATION_NULL_VALUE
#undef YP_LOCATION_TOKEN_VALUE
#undef YP_LOCATION_NODE_VALUE
#undef YP_LOCATION_NODE_BASE_VALUE
#undef YP_CASE_KEYWORD
#undef YP_CASE_OPERATOR
#undef YP_CASE_WRITABLE
