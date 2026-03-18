#include "prism/internal/parser.h"

#include "prism/internal/encoding.h"

/**
 * Register a callback that will be called whenever prism changes the encoding
 * it is using to parse based on the magic comment.
 */
void
pm_parser_encoding_changed_callback_set(pm_parser_t *parser, pm_encoding_changed_callback_t callback) {
    parser->encoding_changed_callback = callback;
}

/**
 * Register a callback that will be called whenever a token is lexed.
 */
void
pm_parser_lex_callback_set(pm_parser_t *parser, pm_lex_callback_t callback, void *data) {
    parser->lex_callback.callback = callback;
    parser->lex_callback.data = data;
}

/**
 * Returns the opaque data that is passed to the lex callback when it is called.
 */
void *
pm_parser_lex_callback_data(pm_parser_t *parser) {
    return parser->lex_callback.data;
}

/**
 * Returns the raw pointer to the start of the source that is being parsed.
 */
const uint8_t *
pm_parser_start(const pm_parser_t *parser) {
    return parser->start;
}

/**
 * Returns the raw pointer to the end of the source that is being parsed.
 */
const uint8_t *
pm_parser_end(const pm_parser_t *parser) {
    return parser->end;
}

/**
 * Returns the line that the parser was considered to have started on.
 *
 * @param parser the parser whose start line we want to get
 * @return the line that the parser was considered to have started on
 */
int32_t
pm_parser_start_line(const pm_parser_t *parser) {
    return parser->start_line;
}

/**
 * Returns the name of the encoding that is being used to parse the source.
 */
const char *
pm_parser_encoding_name(const pm_parser_t *parser) {
    return parser->encoding->name;
}

/**
 * Returns the errors that are associated with the given parser.
 */
const pm_list_t *
pm_parser_errors(const pm_parser_t *parser) {
    return &parser->error_list;
}

/**
 * Returns the warnings that are associated with the given parser.
 */
const pm_list_t *
pm_parser_warnings(const pm_parser_t *parser) {
    return &parser->warning_list;
}

/**
 * Returns the comments that are associated with the given parser.
 */
const pm_list_t *
pm_parser_comments(const pm_parser_t *parser) {
    return &parser->comment_list;
}

/**
 * Returns the magic comments that are associated with the given parser.
 */
const pm_list_t *
pm_parser_magic_comments(const pm_parser_t *parser) {
    return &parser->magic_comment_list;
}

/**
 * Returns the line offsets that are associated with the given parser.
 *
 * @param parser the parser whose line offsets we want to get
 * @return the line offsets that are associated with the given parser
 */
const pm_line_offset_list_t *
pm_parser_line_offsets(const pm_parser_t *parser) {
    return &parser->line_offsets;
}

/**
 * Returns the constant pool associated with the given parser.
 */
const pm_constant_pool_t *
pm_parser_constant_pool(const pm_parser_t *parser) {
    return &parser->constant_pool;
}

/**
 * Returns the location of the __DATA__ section that is associated with the
 * given parser, if it exists.
 */
const pm_location_t *
pm_parser_data_loc(const pm_parser_t *parser) {
    return &parser->data_loc;
}

/**
 * Returns whether the given parser is continuable, meaning that it could become
 * valid if more input were appended, as opposed to being definitively invalid.
 */
bool
pm_parser_continuable(const pm_parser_t *parser) {
    return parser->continuable;
}

/**
 * Returns the lex state of the parser. Note that this is an internal detail,
 * and we are purposefully not returning an instance of the internal enum that
 * we use to track this. This is only exposed because we need it for some very
 * niche use cases. Most consumers should avoid this function.
 */
int
pm_parser_lex_state(const pm_parser_t *parser) {
    return (int) parser->lex_state;
}
