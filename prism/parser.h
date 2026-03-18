/**
 * @file parser.h
 *
 * The parser used to parse Ruby source.
 */
#ifndef PRISM_PARSER_H
#define PRISM_PARSER_H

#include "prism/ast.h"
#include "prism/comments.h"
#include "prism/diagnostic.h"
#include "prism/line_offset_list.h"
#include "prism/magic_comments.h"

/**
 * The parser used to parse Ruby source.
 */
typedef struct pm_parser_t pm_parser_t;

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
PRISM_EXPORTED_FUNCTION void * pm_parser_lex_callback_data(const pm_parser_t *parser);

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
 * Returns the line offsets that are associated with the given parser.
 *
 * @param parser the parser whose line offsets we want to get
 * @return the line offsets that are associated with the given parser
 */
PRISM_EXPORTED_FUNCTION const pm_line_offset_list_t * pm_parser_line_offsets(const pm_parser_t *parser);

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

/**
 * Returns the number of comments associated with the given parser.
 *
 * @param parser the parser whose comments we want to get the size of
 * @return the number of comments associated with the given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_comments_size(const pm_parser_t *parser);

/**
 * A callback function that can be used to process comments found while parsing.
 */
typedef void (*pm_comment_callback_t)(const pm_comment_t *comment, void *data);

/**
 * Iterates over the comments associated with the given parser and calls the
 * given callback for each comment.
 *
 * @param parser the parser whose comments we want to iterate over
 * @param callback the callback function to call for each comment. This function
 *     will be passed a pointer to the comment and the data parameter passed to
 *     this function.
 * @param data the data to pass to the callback function for each comment. This
 *     can be NULL if no data needs to be passed to the callback function.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_comments_each(const pm_parser_t *parser, pm_comment_callback_t callback, void *data);

/**
 * Returns the number of magic comments associated with the given parser.
 *
 * @param parser the parser whose magic comments we want to get the size of
 * @return the number of magic comments associated with the given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_magic_comments_size(const pm_parser_t *parser);

/**
 * A callback function that can be used to process magic comments found while parsing.
 */
typedef void (*pm_magic_comment_callback_t)(const pm_magic_comment_t *magic_comment, void *data);

/**
 * Iterates over the magic comments associated with the given parser and calls the
 * given callback for each magic comment.
 *
 * @param parser the parser whose magic comments we want to iterate over
 * @param callback the callback function to call for each magic comment. This
 *     function will be passed a pointer to the magic comment and the data
 *     parameter passed to this function.
 * @param data the data to pass to the callback function for each magic comment.
 *     This can be NULL if no data needs to be passed to the callback function.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_magic_comments_each(const pm_parser_t *parser, pm_magic_comment_callback_t callback, void *data);

/**
 * Returns the number of errors associated with the given parser.
 *
 * @param parser the parser whose errors we want to get the size of
 * @return the number of errors associated with the given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_errors_size(const pm_parser_t *parser);

/**
 * Returns the number of warnings associated with the given parser.
 *
 * @param parser the parser whose warnings we want to get the size of
 * @return the number of warnings associated with the given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_warnings_size(const pm_parser_t *parser);

/**
 * A callback function that can be used to process diagnostics found while
 * parsing.
 */
typedef void (*pm_diagnostic_callback_t)(const pm_diagnostic_t *diagnostic, void *data);

/**
 * Iterates over the errors associated with the given parser and calls the
 * given callback for each error.
 *
 * @param parser the parser whose errors we want to iterate over
 * @param callback the callback function to call for each error. This function
 *     will be passed a pointer to the error and the data parameter passed to
 *     this function.
 * @param data the data to pass to the callback function for each error. This
 *     can be NULL if no data needs to be passed to the callback function.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_errors_each(const pm_parser_t *parser, pm_diagnostic_callback_t callback, void *data);

/**
 * Iterates over the warnings associated with the given parser and calls the
 * given callback for each warning.
 *
 * @param parser the parser whose warnings we want to iterate over
 * @param callback the callback function to call for each warning. This function
 *     will be passed a pointer to the warning and the data parameter passed to
 *     this function.
 * @param data the data to pass to the callback function for each warning. This
 *     can be NULL if no data needs to be passed to the callback function.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_warnings_each(const pm_parser_t *parser, pm_diagnostic_callback_t callback, void *data);

/**
 * Returns the number of constants in the constant pool associated with the
 * given parser.
 *
 * @param parser the parser whose constant pool constants we want to get the
 *     size of
 * @return the number of constants in the constant pool associated with the
 *     given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_constants_size(const pm_parser_t *parser);

/**
 * A callback function that can be used to process constants found while
 * parsing.
 */
typedef void (*pm_constant_callback_t)(const pm_constant_t *constant, void *data);

/**
 * Iterates over the constants in the constant pool associated with the given
 * parser and calls the given callback for each constant.
 *
 * @param parser the parser whose constants we want to iterate over
 * @param callback the callback function to call for each constant. This function
 *     will be passed a pointer to the constant and the data parameter passed to
 *     this function.
 * @param data the data to pass to the callback function for each constant. This
 *     can be NULL if no data needs to be passed to the callback function.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_constants_each(const pm_parser_t *parser, pm_constant_callback_t callback, void *data);

#endif
