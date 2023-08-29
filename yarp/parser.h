#ifndef YARP_PARSER_H
#define YARP_PARSER_H

#include "yarp/ast.h"
#include "yarp/defines.h"
#include "yarp/enc/yp_encoding.h"
#include "yarp/util/yp_constant_pool.h"
#include "yarp/util/yp_list.h"
#include "yarp/util/yp_newline_list.h"
#include "yarp/util/yp_state_stack.h"

#include <stdbool.h>

// This enum provides various bits that represent different kinds of states that
// the lexer can track. This is used to determine which kind of token to return
// based on the context of the parser.
typedef enum {
    YP_LEX_STATE_BIT_BEG,
    YP_LEX_STATE_BIT_END,
    YP_LEX_STATE_BIT_ENDARG,
    YP_LEX_STATE_BIT_ENDFN,
    YP_LEX_STATE_BIT_ARG,
    YP_LEX_STATE_BIT_CMDARG,
    YP_LEX_STATE_BIT_MID,
    YP_LEX_STATE_BIT_FNAME,
    YP_LEX_STATE_BIT_DOT,
    YP_LEX_STATE_BIT_CLASS,
    YP_LEX_STATE_BIT_LABEL,
    YP_LEX_STATE_BIT_LABELED,
    YP_LEX_STATE_BIT_FITEM
} yp_lex_state_bit_t;

// This enum combines the various bits from the above enum into individual
// values that represent the various states of the lexer.
typedef enum {
    YP_LEX_STATE_NONE = 0,
    YP_LEX_STATE_BEG = (1 << YP_LEX_STATE_BIT_BEG),
    YP_LEX_STATE_END = (1 << YP_LEX_STATE_BIT_END),
    YP_LEX_STATE_ENDARG = (1 << YP_LEX_STATE_BIT_ENDARG),
    YP_LEX_STATE_ENDFN = (1 << YP_LEX_STATE_BIT_ENDFN),
    YP_LEX_STATE_ARG = (1 << YP_LEX_STATE_BIT_ARG),
    YP_LEX_STATE_CMDARG = (1 << YP_LEX_STATE_BIT_CMDARG),
    YP_LEX_STATE_MID = (1 << YP_LEX_STATE_BIT_MID),
    YP_LEX_STATE_FNAME = (1 << YP_LEX_STATE_BIT_FNAME),
    YP_LEX_STATE_DOT = (1 << YP_LEX_STATE_BIT_DOT),
    YP_LEX_STATE_CLASS = (1 << YP_LEX_STATE_BIT_CLASS),
    YP_LEX_STATE_LABEL = (1 << YP_LEX_STATE_BIT_LABEL),
    YP_LEX_STATE_LABELED = (1 << YP_LEX_STATE_BIT_LABELED),
    YP_LEX_STATE_FITEM = (1 << YP_LEX_STATE_BIT_FITEM),
    YP_LEX_STATE_BEG_ANY = YP_LEX_STATE_BEG | YP_LEX_STATE_MID | YP_LEX_STATE_CLASS,
    YP_LEX_STATE_ARG_ANY = YP_LEX_STATE_ARG | YP_LEX_STATE_CMDARG,
    YP_LEX_STATE_END_ANY = YP_LEX_STATE_END | YP_LEX_STATE_ENDARG | YP_LEX_STATE_ENDFN
} yp_lex_state_t;

typedef enum {
    YP_HEREDOC_QUOTE_NONE,
    YP_HEREDOC_QUOTE_SINGLE = '\'',
    YP_HEREDOC_QUOTE_DOUBLE = '"',
    YP_HEREDOC_QUOTE_BACKTICK = '`',
} yp_heredoc_quote_t;

typedef enum {
    YP_HEREDOC_INDENT_NONE,
    YP_HEREDOC_INDENT_DASH,
    YP_HEREDOC_INDENT_TILDE,
} yp_heredoc_indent_t;

// When lexing Ruby source, the lexer has a small amount of state to tell which
// kind of token it is currently lexing. For example, when we find the start of
// a string, the first token that we return is a TOKEN_STRING_BEGIN token. After
// that the lexer is now in the YP_LEX_STRING mode, and will return tokens that
// are found as part of a string.
typedef struct yp_lex_mode {
    enum {
        // This state is used when any given token is being lexed.
        YP_LEX_DEFAULT,

        // This state is used when we're lexing as normal but inside an embedded
        // expression of a string.
        YP_LEX_EMBEXPR,

        // This state is used when we're lexing a variable that is embedded
        // directly inside of a string with the # shorthand.
        YP_LEX_EMBVAR,

        // This state is used when you are inside the content of a heredoc.
        YP_LEX_HEREDOC,

        // This state is used when we are lexing a list of tokens, as in a %w
        // word list literal or a %i symbol list literal.
        YP_LEX_LIST,

        // This state is used when a regular expression has been begun and we
        // are looking for the terminator.
        YP_LEX_REGEXP,

        // This state is used when we are lexing a string or a string-like
        // token, as in string content with either quote or an xstring.
        YP_LEX_STRING
    } mode;

    union {
        struct {
            // This keeps track of the nesting level of the list.
            size_t nesting;

            // Whether or not interpolation is allowed in this list.
            bool interpolation;

            // When lexing a list, it takes into account balancing the
            // terminator if the terminator is one of (), [], {}, or <>.
            uint8_t incrementor;

            // This is the terminator of the list literal.
            uint8_t terminator;

            // This is the character set that should be used to delimit the
            // tokens within the list.
            uint8_t breakpoints[11];
        } list;

        struct {
            // This keeps track of the nesting level of the regular expression.
            size_t nesting;

            // When lexing a regular expression, it takes into account balancing
            // the terminator if the terminator is one of (), [], {}, or <>.
            uint8_t incrementor;

            // This is the terminator of the regular expression.
            uint8_t terminator;

            // This is the character set that should be used to delimit the
            // tokens within the regular expression.
            uint8_t breakpoints[6];
        } regexp;

        struct {
            // This keeps track of the nesting level of the string.
            size_t nesting;

            // Whether or not interpolation is allowed in this string.
            bool interpolation;

            // Whether or not at the end of the string we should allow a :,
            // which would indicate this was a dynamic symbol instead of a
            // string.
            bool label_allowed;

            // When lexing a string, it takes into account balancing the
            // terminator if the terminator is one of (), [], {}, or <>.
            uint8_t incrementor;

            // This is the terminator of the string. It is typically either a
            // single or double quote.
            uint8_t terminator;

            // This is the character set that should be used to delimit the
            // tokens within the string.
            uint8_t breakpoints[6];
        } string;

        struct {
            // These pointers point to the beginning and end of the heredoc
            // identifier.
            const uint8_t *ident_start;
            size_t ident_length;

            yp_heredoc_quote_t quote;
            yp_heredoc_indent_t indent;

            // This is the pointer to the character where lexing should resume
            // once the heredoc has been completely processed.
            const uint8_t *next_start;
        } heredoc;
    } as;

    // The previous lex state so that it knows how to pop.
    struct yp_lex_mode *prev;
} yp_lex_mode_t;

// We pre-allocate a certain number of lex states in order to avoid having to
// call malloc too many times while parsing. You really shouldn't need more than
// this because you only really nest deeply when doing string interpolation.
#define YP_LEX_STACK_SIZE 4

// A forward declaration since our error handler struct accepts a parser for
// each of its function calls.
typedef struct yp_parser yp_parser_t;

// While parsing, we keep track of a stack of contexts. This is helpful for
// error recovery so that we can pop back to a previous context when we hit a
// token that is understood by a parent context but not by the current context.
typedef enum {
    YP_CONTEXT_BEGIN,          // a begin statement
    YP_CONTEXT_BLOCK_BRACES,   // expressions in block arguments using braces
    YP_CONTEXT_BLOCK_KEYWORDS, // expressions in block arguments using do..end
    YP_CONTEXT_CASE_WHEN,      // a case when statements
    YP_CONTEXT_CASE_IN,        // a case in statements
    YP_CONTEXT_CLASS,          // a class declaration
    YP_CONTEXT_DEF,            // a method definition
    YP_CONTEXT_DEF_PARAMS,     // a method definition's parameters
    YP_CONTEXT_DEFAULT_PARAMS, // a method definition's default parameter
    YP_CONTEXT_ELSE,           // an else clause
    YP_CONTEXT_ELSIF,          // an elsif clause
    YP_CONTEXT_EMBEXPR,        // an interpolated expression
    YP_CONTEXT_ENSURE,         // an ensure statement
    YP_CONTEXT_FOR,            // a for loop
    YP_CONTEXT_IF,             // an if statement
    YP_CONTEXT_LAMBDA_BRACES,  // a lambda expression with braces
    YP_CONTEXT_LAMBDA_DO_END,  // a lambda expression with do..end
    YP_CONTEXT_MAIN,           // the top level context
    YP_CONTEXT_MODULE,         // a module declaration
    YP_CONTEXT_PARENS,         // a parenthesized expression
    YP_CONTEXT_POSTEXE,        // an END block
    YP_CONTEXT_PREDICATE,      // a predicate inside an if/elsif/unless statement
    YP_CONTEXT_PREEXE,         // a BEGIN block
    YP_CONTEXT_RESCUE_ELSE,    // a rescue else statement
    YP_CONTEXT_RESCUE,         // a rescue statement
    YP_CONTEXT_SCLASS,         // a singleton class definition
    YP_CONTEXT_UNLESS,         // an unless statement
    YP_CONTEXT_UNTIL,          // an until statement
    YP_CONTEXT_WHILE,          // a while statement
} yp_context_t;

// This is a node in a linked list of contexts.
typedef struct yp_context_node {
    yp_context_t context;
    struct yp_context_node *prev;
} yp_context_node_t;

// This is the type of a comment that we've found while parsing.
typedef enum {
    YP_COMMENT_INLINE,
    YP_COMMENT_EMBDOC,
    YP_COMMENT___END__
} yp_comment_type_t;

// This is a node in the linked list of comments that we've found while parsing.
typedef struct yp_comment {
    yp_list_node_t node;
    const uint8_t *start;
    const uint8_t *end;
    yp_comment_type_t type;
} yp_comment_t;

// When the encoding that is being used to parse the source is changed by YARP,
// we provide the ability here to call out to a user-defined function.
typedef void (*yp_encoding_changed_callback_t)(yp_parser_t *parser);

// When an encoding is encountered that isn't understood by YARP, we provide
// the ability here to call out to a user-defined function to get an encoding
// struct. If the function returns something that isn't NULL, we set that to
// our encoding and use it to parse identifiers.
typedef yp_encoding_t *(*yp_encoding_decode_callback_t)(yp_parser_t *parser, const uint8_t *name, size_t width);

// When you are lexing through a file, the lexer needs all of the information
// that the parser additionally provides (for example, the local table). So if
// you want to properly lex Ruby, you need to actually lex it in the context of
// the parser. In order to provide this functionality, we optionally allow a
// struct to be attached to the parser that calls back out to a user-provided
// callback when each token is lexed.
typedef struct {
    // This opaque pointer is used to provide whatever information the user
    // deemed necessary to the callback. In our case we use it to pass the array
    // that the tokens get appended into.
    void *data;

    // This is the callback that is called when a token is lexed. It is passed
    // the opaque data pointer, the parser, and the token that was lexed.
    void (*callback)(void *data, yp_parser_t *parser, yp_token_t *token);
} yp_lex_callback_t;

// This struct represents a node in a linked list of scopes. Some scopes can see
// into their parent scopes, while others cannot.
typedef struct yp_scope {
    // The IDs of the locals in the given scope.
    yp_constant_id_list_t locals;

    // A boolean indicating whether or not this scope can see into its parent.
    // If closed is true, then the scope cannot see into its parent.
    bool closed;

    // A pointer to the previous scope in the linked list.
    struct yp_scope *previous;
} yp_scope_t;

// This struct represents the overall parser. It contains a reference to the
// source file, as well as pointers that indicate where in the source it's
// currently parsing. It also contains the most recent and current token that
// it's considering.
struct yp_parser {
    yp_lex_state_t lex_state; // the current state of the lexer
    bool command_start;       // whether or not we're at the beginning of a command
    int enclosure_nesting;    // tracks the current nesting of (), [], and {}

    // Used to temporarily track the nesting of enclosures to determine if a {
    // is the beginning of a lambda following the parameters of a lambda.
    int lambda_enclosure_nesting;

    // Used to track the nesting of braces to ensure we get the correct value
    // when we are interpolating blocks with braces.
    int brace_nesting;

    // the stack used to determine if a do keyword belongs to the predicate of a
    // while, until, or for loop
    yp_state_stack_t do_loop_stack;

    // the stack used to determine if a do keyword belongs to the beginning of a
    // block
    yp_state_stack_t accepts_block_stack;

    struct {
        yp_lex_mode_t *current;                 // the current mode of the lexer
        yp_lex_mode_t stack[YP_LEX_STACK_SIZE]; // the stack of lexer modes
        size_t index;                           // the current index into the lexer mode stack
    } lex_modes;

    const uint8_t *start;   // the pointer to the start of the source
    const uint8_t *end;     // the pointer to the end of the source
    yp_token_t previous; // the previous token we were considering
    yp_token_t current;  // the current token we're considering

    // This is a special field set on the parser when we need the parser to jump
    // to a specific location when lexing the next token, as opposed to just
    // using the end of the previous token. Normally this is NULL.
    const uint8_t *next_start;

    // This field indicates the end of a heredoc whose identifier was found on
    // the current line. If another heredoc is found on the same line, then this
    // will be moved forward to the end of that heredoc. If no heredocs are
    // found on a line then this is NULL.
    const uint8_t *heredoc_end;

    yp_list_t comment_list;             // the list of comments that have been found while parsing
    yp_list_t warning_list;             // the list of warnings that have been found while parsing
    yp_list_t error_list;               // the list of errors that have been found while parsing
    yp_scope_t *current_scope;          // the current local scope

    yp_context_node_t *current_context; // the current parsing context
    bool recovering; // whether or not we're currently recovering from a syntax error

    // The encoding functions for the current file is attached to the parser as
    // it's parsing so that it can change with a magic comment.
    yp_encoding_t encoding;

    // Whether or not the encoding has been changed by a magic comment. We use
    // this to provide a fast path for the lexer instead of going through the
    // function pointer.
    bool encoding_changed;

    // When the encoding that is being used to parse the source is changed by
    // YARP, we provide the ability here to call out to a user-defined function.
    yp_encoding_changed_callback_t encoding_changed_callback;

    // When an encoding is encountered that isn't understood by YARP, we provide
    // the ability here to call out to a user-defined function to get an
    // encoding struct. If the function returns something that isn't NULL, we
    // set that to our encoding and use it to parse identifiers.
    yp_encoding_decode_callback_t encoding_decode_callback;

    // This pointer indicates where a comment must start if it is to be
    // considered an encoding comment.
    const uint8_t *encoding_comment_start;

    // This is an optional callback that can be attached to the parser that will
    // be called whenever a new token is lexed by the parser.
    yp_lex_callback_t *lex_callback;

    // This flag indicates that we are currently parsing a pattern matching
    // expression and impacts that calculation of newlines.
    bool pattern_matching_newlines;

    // This flag indicates that we are currently parsing a keyword argument.
    bool in_keyword_arg;

    // This is the path of the file being parsed
    // We use the filepath when constructing SourceFileNodes
    yp_string_t filepath_string;

    // This constant pool keeps all of the constants defined throughout the file
    // so that we can reference them later.
    yp_constant_pool_t constant_pool;

    // This is the list of newline offsets in the source file.
    yp_newline_list_t newline_list;
};

#endif // YARP_PARSER_H
