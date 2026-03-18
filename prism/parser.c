#include "prism/internal/parser.h"

#include "prism/internal/allocator.h"
#include "prism/internal/comments.h"
#include "prism/internal/diagnostic.h"
#include "prism/internal/encoding.h"
#include "prism/internal/magic_comments.h"

#include <stdlib.h>

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
pm_parser_lex_callback_data(const pm_parser_t *parser) {
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
 * Returns the frozen string literal value of the parser.
 */
int8_t
pm_parser_frozen_string_literal(const pm_parser_t *parser) {
    return parser->frozen_string_literal;
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

/**
 * Returns the location associated with the given comment.
 */
pm_location_t
pm_comment_location(const pm_comment_t *comment) {
    return comment->location;
}

/**
 * Returns the type associated with the given comment.
 */
pm_comment_type_t
pm_comment_type(const pm_comment_t *comment) {
    return comment->type;
}

/**
 * Returns the number of comments associated with the given parser.
 */
size_t
pm_parser_comments_size(const pm_parser_t *parser) {
    return parser->comment_list.size;
}

/**
 * Iterates over the comments associated with the given parser and calls the
 * given callback for each comment.
 */
void
pm_parser_comments_each(const pm_parser_t *parser, pm_comment_callback_t callback, void *data) {
    const pm_list_node_t *current = parser->comment_list.head;
    while (current != NULL) {
        const pm_comment_t *comment = (const pm_comment_t *) current;
        callback(comment, data);
        current = current->next;
    }
}

/**
 * Returns the location associated with the given magic comment key.
 */
pm_location_t
pm_magic_comment_key(const pm_magic_comment_t *magic_comment) {
    return magic_comment->key;
}

/**
 * Returns the location associated with the given magic comment value.
 */
pm_location_t
pm_magic_comment_value(const pm_magic_comment_t *magic_comment) {
    return magic_comment->value;
}

/**
 * Returns the number of magic comments associated with the given parser.
 */
size_t
pm_parser_magic_comments_size(const pm_parser_t *parser) {
    return parser->magic_comment_list.size;
}

/**
 * Iterates over the magic comments associated with the given parser and calls
 * the given callback for each magic comment.
 */
void
pm_parser_magic_comments_each(const pm_parser_t *parser, pm_magic_comment_callback_t callback, void *data) {
    const pm_list_node_t *current = parser->magic_comment_list.head;
    while (current != NULL) {
        const pm_magic_comment_t *magic_comment = (const pm_magic_comment_t *) current;
        callback(magic_comment, data);
        current = current->next;
    }
}

/**
 * Returns the number of errors associated with the given parser.
 */
size_t
pm_parser_errors_size(const pm_parser_t *parser) {
    return parser->error_list.size;
}

/**
 * Returns the number of warnings associated with the given parser.
 */
size_t
pm_parser_warnings_size(const pm_parser_t *parser) {
    return parser->warning_list.size;
}

static inline void
pm_parser_diagnostics_each(const pm_list_t *list, pm_diagnostic_callback_t callback, void *data) {
    const pm_list_node_t *current = list->head;
    while (current != NULL) {
        const pm_diagnostic_t *diagnostic = (const pm_diagnostic_t *) current;
        callback(diagnostic, data);
        current = current->next;
    }
}

/**
 * Iterates over the errors associated with the given parser and calls the
 * given callback for each error.
 */
void
pm_parser_errors_each(const pm_parser_t *parser, pm_diagnostic_callback_t callback, void *data) {
    pm_parser_diagnostics_each(&parser->error_list, callback, data);
}

/**
 * Iterates over the warnings associated with the given parser and calls the
 * given callback for each warning.
 */
void
pm_parser_warnings_each(const pm_parser_t *parser, pm_diagnostic_callback_t callback, void *data) {
    pm_parser_diagnostics_each(&parser->warning_list, callback, data);
}

/**
 * Returns the number of constants in the constant pool associated with the
 * given parser.
 */
size_t
pm_parser_constants_size(const pm_parser_t *parser) {
    return parser->constant_pool.size;
}

/**
 * Iterates over the constants in the constant pool associated with the given
 * parser and calls the given callback for each constant.
 */
void
pm_parser_constants_each(const pm_parser_t *parser, pm_constant_callback_t callback, void *data) {
    for (uint32_t index = 0; index < parser->constant_pool.size; index++) {
        const pm_constant_t *constant = &parser->constant_pool.constants[index];
        callback(constant, data);
    }
}

/**
 * Returns a pointer to the constant at the given id in the constant pool
 * associated with the given parser.
 */
const pm_constant_t *
pm_parser_constant(const pm_parser_t *parser, pm_constant_id_t constant_id) {
    return pm_constant_pool_id_to_constant(&parser->constant_pool, constant_id);
}
