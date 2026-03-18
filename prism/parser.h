/**
 * @file parser.h
 *
 * The parser used to parse Ruby source.
 */
#ifndef PRISM_PARSER_H
#define PRISM_PARSER_H

#include "prism/ast.h"
#include "prism/line_offset_list.h"
#include "prism/list.h"

/**
 * The parser used to parse Ruby source.
 */
typedef struct pm_parser_t pm_parser_t;

/** This is the type of a comment that we've found while parsing. */
typedef enum {
    PM_COMMENT_INLINE,
    PM_COMMENT_EMBDOC
} pm_comment_type_t;

/**
 * This is a node in the linked list of comments that we've found while parsing.
 *
 * @extends pm_list_node_t
 */
typedef struct pm_comment {
    /** The embedded base node. */
    pm_list_node_t node;

    /** The location of the comment in the source. */
    pm_location_t location;

    /** The type of comment that we've found. */
    pm_comment_type_t type;
} pm_comment_t;

/**
 * This is a node in the linked list of magic comments that we've found while
 * parsing.
 *
 * @extends pm_list_node_t
 */
typedef struct {
    /** The embedded base node. */
    pm_list_node_t node;

    /** The key of the magic comment. */
    pm_location_t key;

    /** The value of the magic comment. */
    pm_location_t value;
} pm_magic_comment_t;

/**
 * When the encoding that is being used to parse the source is changed by prism,
 * we provide the ability here to call out to a user-defined function.
 */
typedef void (*pm_encoding_changed_callback_t)(pm_parser_t *parser);

/**
 * This is the callback that is called when a token is lexed. It is passed
 * the opaque data pointer, the parser, and the token that was lexed.
 */
typedef void (*pm_lex_callback_t)(pm_parser_t *parser, pm_token_t *token, void *data);

/**
 * Register a callback that will be called whenever prism changes the encoding
 * it is using to parse based on the magic comment.
 *
 * @param parser The parser to register the callback with.
 * @param callback The callback to register.
 *
 * \public \memberof pm_parser
 */
PRISM_EXPORTED_FUNCTION void pm_parser_encoding_changed_callback_set(pm_parser_t *parser, pm_encoding_changed_callback_t callback);

/**
 * Register a callback that will be called whenever a token is lexed.
 *
 * @param parser The parser to register the callback with.
 * @param data The opaque data to pass to the callback when it is called.
 * @param callback The callback to register.
 *
 * \public \memberof pm_parser
 */
PRISM_EXPORTED_FUNCTION void pm_parser_lex_callback_set(pm_parser_t *parser, pm_lex_callback_t callback, void *data);

/**
 * Returns the opaque data that is passed to the lex callback when it is called.
 *
 * @param parser The parser whose lex callback data we want to get.
 * @return The opaque data that is passed to the lex callback when it is called.
 */
PRISM_EXPORTED_FUNCTION void * pm_parser_lex_callback_data(pm_parser_t *parser);

/**
 * Returns the raw pointer to the start of the source that is being parsed.
 *
 * @param parser the parser whose start pointer we want to get
 * @return the raw pointer to the start of the source that is being parsed
 */
PRISM_EXPORTED_FUNCTION const uint8_t * pm_parser_start(const pm_parser_t *parser);

/**
 * Returns the raw pointer to the end of the source that is being parsed.
 *
 * @param parser the parser whose end pointer we want to get
 * @return the raw pointer to the end of the source that is being parsed
 */
PRISM_EXPORTED_FUNCTION const uint8_t * pm_parser_end(const pm_parser_t *parser);

/**
 * Returns the line that the parser was considered to have started on.
 *
 * @param parser the parser whose start line we want to get
 * @return the line that the parser was considered to have started on
 */
PRISM_EXPORTED_FUNCTION int32_t pm_parser_start_line(const pm_parser_t *parser);

/**
 * Returns the name of the encoding that is being used to parse the source.
 *
 * @param parser the parser whose encoding name we want to get
 * @return the name of the encoding that is being used to parse the source
 */
PRISM_EXPORTED_FUNCTION const char * pm_parser_encoding_name(const pm_parser_t *parser);

/**
 * Returns the errors that are associated with the given parser.
 *
 * @param parser the parser whose errors we want to get
 * @return the errors that are associated with the given parser
 */
PRISM_EXPORTED_FUNCTION const pm_list_t * pm_parser_errors(const pm_parser_t *parser);

/**
 * Returns the warnings that are associated with the given parser.
 *
 * @param parser the parser whose warnings we want to get
 * @return the warnings that are associated with the given parser
 */
PRISM_EXPORTED_FUNCTION const pm_list_t * pm_parser_warnings(const pm_parser_t *parser);

/**
 * Returns the comments that are associated with the given parser.
 *
 * @param parser the parser whose comments we want to get
 * @return the comments that are associated with the given parser
 */
PRISM_EXPORTED_FUNCTION const pm_list_t * pm_parser_comments(const pm_parser_t *parser);

/**
 * Returns the magic comments that are associated with the given parser.
 *
 * @param parser the parser whose magic comments we want to get
 * @return the magic comments that are associated with the given parser
 */
PRISM_EXPORTED_FUNCTION const pm_list_t * pm_parser_magic_comments(const pm_parser_t *parser);

/**
 * Returns the line offsets that are associated with the given parser.
 *
 * @param parser the parser whose line offsets we want to get
 * @return the line offsets that are associated with the given parser
 */
PRISM_EXPORTED_FUNCTION const pm_line_offset_list_t * pm_parser_line_offsets(const pm_parser_t *parser);

/**
 * Returns the constant pool associated with the given parser.
 *
 * @param parser the parser whose constant pool we want to get
 * @return the constant pool associated with the given parser
 */
PRISM_EXPORTED_FUNCTION const pm_constant_pool_t * pm_parser_constant_pool(const pm_parser_t *parser);

/**
 * Returns the location of the __DATA__ section that is associated with the
 * given parser.
 *
 * @param parser the parser whose data location we want to get
 * @return the location of the __DATA__ section that is associated with the
 *     given parser. If it is unset, then the length will be set to 0.
 */
PRISM_EXPORTED_FUNCTION const pm_location_t * pm_parser_data_loc(const pm_parser_t *parser);

/**
 * Returns whether the given parser is continuable, meaning that it could become
 * valid if more input were appended, as opposed to being definitively invalid.
 *
 * @param parser the parser whose continuable status we want to get
 * @return whether the given parser is continuable
 */
PRISM_EXPORTED_FUNCTION bool pm_parser_continuable(const pm_parser_t *parser);

/**
 * Returns the lex state of the parser. Note that this is an internal detail,
 * and we are purposefully not returning an instance of the internal enum that
 * we use to track this. This is only exposed because we need it for some very
 * niche use cases. Most consumers should avoid this function.
 *
 * @param parser the parser whose lex state we want to get
 * @return the lex state of the parser
 */
PRISM_EXPORTED_FUNCTION int pm_parser_lex_state(const pm_parser_t *parser);

#endif
