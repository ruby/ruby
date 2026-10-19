/**
 * @file parser.h
 *
 * The parser used to parse Ruby source.
 */
#ifndef PRISM_PARSER_H
#define PRISM_PARSER_H

#include "prism/compiler/nodiscard.h"
#include "prism/compiler/nonnull.h"

#include "prism/ast.h"
#include "prism/comments.h"
#include "prism/diagnostic.h"
#include "prism/line_offset_list.h"
#include "prism/magic_comments.h"
#include "prism/options.h"

/**
 * The parser used to parse Ruby source.
 */
typedef struct pm_parser_t pm_parser_t;

/**
 * Allocate and initialize a parser with the given start and end pointers.
 *
 * @param arena The arena to use for all AST-lifetime allocations. It is caller-
 *     owned and must outlive the parser.
 * @param source The source to parse.
 * @param size The size of the source.
 * @param options The optional options to use when parsing. These options must
 *     live for the whole lifetime of this parser.
 * @returns The initialized parser. It is the responsibility of the caller to
 *     free the parser with `pm_parser_free()`.
 */
PRISM_NODISCARD PRISM_EXPORTED_FUNCTION pm_parser_t * pm_parser_new(pm_arena_t *arena, const uint8_t *source, size_t size, const pm_options_t *options) PRISM_NONNULL(1);

/**
 * Free both the memory held by the given parser and the parser itself.
 *
 * @param parser The parser to free.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_free(pm_parser_t *parser) PRISM_NONNULL(1);

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
 */
PRISM_EXPORTED_FUNCTION void pm_parser_encoding_changed_callback_set(pm_parser_t *parser, pm_encoding_changed_callback_t callback) PRISM_NONNULL(1);

/**
 * Register a callback that will be called whenever a token is lexed.
 *
 * @param parser The parser to register the callback with.
 * @param data The opaque data to pass to the callback when it is called.
 * @param callback The callback to register.
 */
PRISM_EXPORTED_FUNCTION void pm_parser_lex_callback_set(pm_parser_t *parser, pm_lex_callback_t callback, void *data) PRISM_NONNULL(1);

/**
 * Returns the opaque data that is passed to the lex callback when it is called.
 *
 * @param parser The parser whose lex callback data we want to get.
 * @returns The opaque data that is passed to the lex callback when it is called.
 */
PRISM_EXPORTED_FUNCTION void * pm_parser_lex_callback_data(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the raw pointer to the start of the source that is being parsed.
 *
 * @param parser the parser whose start pointer we want to get
 * @returns the raw pointer to the start of the source that is being parsed
 */
PRISM_EXPORTED_FUNCTION const uint8_t * pm_parser_start(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the raw pointer to the end of the source that is being parsed.
 *
 * @param parser the parser whose end pointer we want to get
 * @returns the raw pointer to the end of the source that is being parsed
 */
PRISM_EXPORTED_FUNCTION const uint8_t * pm_parser_end(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the line that the parser was considered to have started on.
 *
 * @param parser the parser whose start line we want to get
 * @returns the line that the parser was considered to have started on
 */
PRISM_EXPORTED_FUNCTION int32_t pm_parser_start_line(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the name of the encoding that is being used to parse the source.
 *
 * @param parser the parser whose encoding name we want to get
 * @returns the name of the encoding that is being used to parse the source
 */
PRISM_EXPORTED_FUNCTION const char * pm_parser_encoding_name(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the width of the character at the given pointer in the encoding that
 * is being used to parse the source.
 *
 * @param parser the parser whose encoding we want to use
 * @param start a pointer to the start of the character
 * @param remaining the number of bytes remaining in the source
 * @returns the width of the character in bytes
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_encoding_char_width(const pm_parser_t *parser, const uint8_t *start, ptrdiff_t remaining) PRISM_NONNULL(1, 2);

/**
 * Returns whether or not the parser is using the US-ASCII encoding.
 *
 * @param parser the parser to check
 * @returns true if the parser is using US-ASCII encoding, false otherwise
 */
PRISM_EXPORTED_FUNCTION bool pm_parser_encoding_us_ascii(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the filepath that is being used to parse the source.
 *
 * @param parser the parser whose filepath we want to get
 * @returns a pointer to the filepath string
 */
PRISM_EXPORTED_FUNCTION const pm_string_t * pm_parser_filepath(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Find a constant in the parser's constant pool. Returns the id of the
 * constant, or 0 if the constant is not found.
 *
 * @param parser the parser whose constant pool we want to search
 * @param start a pointer to the start of the string to search for
 * @param length the length of the string to search for
 * @returns the id of the constant, or 0 if the constant is not found
 */
PRISM_EXPORTED_FUNCTION pm_constant_id_t pm_parser_constant_find(const pm_parser_t *parser, const uint8_t *start, size_t length) PRISM_NONNULL(1, 2);

/**
 * Returns the frozen string literal value of the parser, as determined by the
 * frozen_string_literal magic comment or the option set on the parser.
 *
 * @param parser the parser whose frozen string literal value we want to get
 * @returns -1 if disabled, 0 if unset, 1 if enabled
 */
PRISM_EXPORTED_FUNCTION int8_t pm_parser_frozen_string_literal(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the line offsets that are associated with the given parser.
 *
 * @param parser the parser whose line offsets we want to get
 * @returns the line offsets that are associated with the given parser
 */
PRISM_EXPORTED_FUNCTION const pm_line_offset_list_t * pm_parser_line_offsets(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the location of the __DATA__ section that is associated with the
 * given parser.
 *
 * @param parser the parser whose data location we want to get
 * @returns the location of the __DATA__ section that is associated with the
 *     given parser. If it is unset, then the length will be set to 0.
 */
PRISM_EXPORTED_FUNCTION const pm_location_t * pm_parser_data_loc(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the checksum of the source code that was parsed. The data section
 * after an __END__ marker is not code, so the hash covers the source only up to
 * and including the newline that ends the __END__ line. The __END__ marker is
 * only found by parsing, so this must be called after pm_parse.
 *
 * The hash is computed from the source on each call rather than during
 * parsing, so that parses that never ask for it do not pay for it. This
 * requires the source to still be alive, and callers that need the value more
 * than once should keep it.
 *
 * The hash is currently the 64-bit variant of XXH3 with a seed of 0. It is not
 * cryptographic, and the algorithm may change between versions of prism, so
 * hashes should only be compared against other hashes computed by the same
 * version of prism.
 *
 * @param parser the parser whose checksum we want to get
 * @returns the checksum of the source code that was parsed
 */
PRISM_EXPORTED_FUNCTION uint64_t pm_parser_checksum(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns whether the given parser is continuable, meaning that it could become
 * valid if more input were appended, as opposed to being definitively invalid.
 *
 * @param parser the parser whose continuable status we want to get
 * @returns whether the given parser is continuable
 */
PRISM_EXPORTED_FUNCTION bool pm_parser_continuable(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the lex state of the parser. Note that this is an internal detail,
 * and we are purposefully not returning an instance of the internal enum that
 * we use to track this. This is only exposed because we need it for some very
 * niche use cases. Most consumers should avoid this function.
 *
 * @param parser the parser whose lex state we want to get
 * @returns the lex state of the parser
 */
PRISM_EXPORTED_FUNCTION int pm_parser_lex_state(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the number of comments associated with the given parser.
 *
 * @param parser the parser whose comments we want to get the size of
 * @returns the number of comments associated with the given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_comments_size(const pm_parser_t *parser) PRISM_NONNULL(1);

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
PRISM_EXPORTED_FUNCTION void pm_parser_comments_each(const pm_parser_t *parser, pm_comment_callback_t callback, void *data) PRISM_NONNULL(1);

/**
 * Returns the number of comments owned by the given node. This is 0 if the
 * node owns no comments or if the attach_comments option was not set.
 *
 * @param parser the parser that produced the node
 * @param node the node whose comments we want to count
 * @returns the number of comments owned by the given node
 */
PRISM_EXPORTED_FUNCTION uint32_t pm_node_comments_size(const pm_parser_t *parser, const pm_node_t *node) PRISM_NONNULL(1, 2);

/**
 * Returns the comment at the given index among the comments owned by the given
 * node, which are ordered by start offset.
 *
 * @param parser the parser that produced the node
 * @param node the node whose comment we want to get
 * @param index the index of the comment among those owned by the node
 * @returns the comment at the given index, or NULL if the index is out of range
 */
PRISM_EXPORTED_FUNCTION const pm_comment_t * pm_node_comment(const pm_parser_t *parser, const pm_node_t *node, uint32_t index) PRISM_NONNULL(1, 2);

/**
 * Returns the index, among the comments associated with the given parser, of
 * the comment at the given index among the comment attachments. The attachments
 * are every comment, grouped by owning node in order of node id and ordered by
 * start offset within each node, so there are as many attachments as there are
 * comments when the attach_comments option is set.
 *
 * @param parser the parser whose comment attachments we want to read
 * @param index the index of the attachment
 * @returns the index of the comment, or UINT32_MAX if the index is out of range
 *     or the attach_comments option was not set
 */
PRISM_EXPORTED_FUNCTION uint32_t pm_parser_comment_attachment(const pm_parser_t *parser, uint32_t index) PRISM_NONNULL(1);

/**
 * Returns the number of node ids that have a comment range, which is one more
 * than the largest id of a node that owns a comment, or 0 if the
 * attach_comments option was not set or there are no comments.
 *
 * @param parser the parser whose comment ranges we want to count
 * @returns the number of comment ranges
 */
PRISM_EXPORTED_FUNCTION uint32_t pm_parser_comment_ranges_size(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the range of comment attachments owned by the node with the given id.
 *
 * @param parser the parser that produced the node
 * @param node_id the id of the node
 * @returns the range of attachments owned by the node, whose length is 0 if the
 *     node owns no comments, the node id is out of range, or the
 *     attach_comments option was not set
 */
PRISM_EXPORTED_FUNCTION pm_comment_range_t pm_parser_comment_range(const pm_parser_t *parser, uint32_t node_id) PRISM_NONNULL(1);

/**
 * Returns the number of magic comments associated with the given parser.
 *
 * @param parser the parser whose magic comments we want to get the size of
 * @returns the number of magic comments associated with the given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_magic_comments_size(const pm_parser_t *parser) PRISM_NONNULL(1);

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
PRISM_EXPORTED_FUNCTION void pm_parser_magic_comments_each(const pm_parser_t *parser, pm_magic_comment_callback_t callback, void *data) PRISM_NONNULL(1);

/**
 * Returns the number of errors associated with the given parser.
 *
 * @param parser the parser whose errors we want to get the size of
 * @returns the number of errors associated with the given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_errors_size(const pm_parser_t *parser) PRISM_NONNULL(1);

/**
 * Returns the number of warnings associated with the given parser.
 *
 * @param parser the parser whose warnings we want to get the size of
 * @returns the number of warnings associated with the given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_warnings_size(const pm_parser_t *parser) PRISM_NONNULL(1);

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
PRISM_EXPORTED_FUNCTION void pm_parser_errors_each(const pm_parser_t *parser, pm_diagnostic_callback_t callback, void *data) PRISM_NONNULL(1);

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
PRISM_EXPORTED_FUNCTION void pm_parser_warnings_each(const pm_parser_t *parser, pm_diagnostic_callback_t callback, void *data) PRISM_NONNULL(1);

/**
 * Returns the number of constants in the constant pool associated with the
 * given parser.
 *
 * @param parser the parser whose constant pool constants we want to get the
 *     size of
 * @returns the number of constants in the constant pool associated with the
 *     given parser
 */
PRISM_EXPORTED_FUNCTION size_t pm_parser_constants_size(const pm_parser_t *parser) PRISM_NONNULL(1);

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
PRISM_EXPORTED_FUNCTION void pm_parser_constants_each(const pm_parser_t *parser, pm_constant_callback_t callback, void *data) PRISM_NONNULL(1);

/**
 * Returns a pointer to the constant at the given id in the constant pool
 * associated with the given parser.
 *
 * @param parser the parser whose constant pool we want to look up from
 * @param constant_id the id of the constant to look up (1-based)
 * @returns a pointer to the constant at the given id
 */
PRISM_EXPORTED_FUNCTION const pm_constant_t * pm_parser_constant(const pm_parser_t *parser, pm_constant_id_t constant_id) PRISM_NONNULL(1);

/**
 * Initiate the parser with the given parser.
 *
 * @param parser The parser to use.
 * @returns The AST representing the source.
 */
PRISM_EXPORTED_FUNCTION pm_node_t * pm_parse(pm_parser_t *parser) PRISM_NONNULL(1);

#endif
