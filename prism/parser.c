#include "prism/internal/parser.h"

#include "prism/internal/allocator.h"
#include "prism/internal/comments.h"
#include "prism/internal/diagnostic.h"
#include "prism/internal/encoding.h"
#include "prism/internal/magic_comments.h"
#include "prism/internal/xxh3.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>

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
 * Returns the width of the character at the given pointer in the encoding that
 * is being used to parse the source.
 */
size_t
pm_parser_encoding_char_width(const pm_parser_t *parser, const uint8_t *start, ptrdiff_t remaining) {
    return parser->encoding->char_width(start, remaining);
}

/**
 * Returns whether or not the parser is using the US-ASCII encoding.
 */
bool
pm_parser_encoding_us_ascii(const pm_parser_t *parser) {
    return parser->encoding == PM_ENCODING_US_ASCII_ENTRY;
}

/**
 * Returns the filepath that is being used to parse the source.
 */
const pm_string_t *
pm_parser_filepath(const pm_parser_t *parser) {
    return &parser->filepath;
}

/**
 * Find a constant in the parser's constant pool. Returns the id of the
 * constant, or 0 if the constant is not found.
 */
pm_constant_id_t
pm_parser_constant_find(const pm_parser_t *parser, const uint8_t *start, size_t length) {
    return pm_constant_pool_find(&parser->constant_pool, start, length);
}

/**
 * Add a constant to the parser's constant pool, copying its bytes into the
 * parser's arena only if the constant is not already there.
 */
pm_constant_id_t
pm_parser_constant_insert(pm_parser_t *parser, const uint8_t *start, size_t length) {
    pm_constant_id_t id = pm_constant_pool_find(&parser->constant_pool, start, length);
    if (id != PM_CONSTANT_ID_UNSET) return id;

    const uint8_t *copy = (const uint8_t *) pm_arena_memdup(&parser->metadata_arena, start, length, PRISM_ALIGNOF(uint8_t));
    return pm_constant_pool_insert_constant(&parser->metadata_arena, &parser->constant_pool, copy, length);
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
 * Returns the checksum of the source code that was parsed.
 */
uint64_t
pm_parser_checksum(const pm_parser_t *parser) {
    const uint8_t *end = parser->end;

    if (parser->data_loc.length != 0) {
        const uint8_t *cursor = parser->start + parser->data_loc.start;
        const uint8_t *newline = memchr(cursor, '\n', (size_t) (end - cursor));
        if (newline != NULL) end = newline + 1;
    }

    return pm_xxh3(parser->start, (size_t) (end - parser->start));
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
 * Returns the comment that follows the given comment.
 */
const pm_comment_t *
pm_comment_next(const pm_comment_t *comment) {
    return (const pm_comment_t *) comment->node.next;
}

/**
 * Returns the number of comments associated with the given parser.
 */
size_t
pm_parser_comments_size(const pm_parser_t *parser) {
    return parser->comment_list.size;
}

/**
 * Returns the first comment associated with the given parser.
 */
const pm_comment_t *
pm_parser_comments_first(const pm_parser_t *parser) {
    return (const pm_comment_t *) parser->comment_list.head;
}

/**
 * Returns the number of comments owned by the given node.
 */
uint32_t
pm_node_comments_size(const pm_parser_t *parser, const pm_node_t *node) {
    return pm_parser_comment_range(parser, node->node_id).length;
}

/**
 * Returns the comment at the given index among the comments owned by the given
 * node.
 */
const pm_comment_t *
pm_node_comment(const pm_parser_t *parser, const pm_node_t *node, uint32_t index) {
    pm_comment_range_t range = pm_parser_comment_range(parser, node->node_id);
    if (index >= range.length) return NULL;

    return parser->comment_attachments.comments[parser->comment_attachments.attachments[range.index + index]];
}

/**
 * Returns the index, among the comments associated with the given parser, of
 * the comment at the given index among the comment attachments.
 */
uint32_t
pm_parser_comment_attachment(const pm_parser_t *parser, uint32_t index) {
    if (parser->comment_attachments.attachments == NULL || index >= parser->comment_list.size) return UINT32_MAX;
    return parser->comment_attachments.attachments[index];
}

/**
 * Returns the number of node ids that have a comment range.
 */
uint32_t
pm_parser_comment_ranges_size(const pm_parser_t *parser) {
    return parser->comment_attachments.ranges_size;
}

/**
 * Returns the range of comment attachments owned by the node with the given id.
 */
pm_comment_range_t
pm_parser_comment_range(const pm_parser_t *parser, uint32_t node_id) {
    if (node_id >= parser->comment_attachments.ranges_size) return (pm_comment_range_t) { .index = 0, .length = 0 };
    return parser->comment_attachments.ranges[node_id];
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
 * Returns the magic comment that follows the given magic comment.
 */
const pm_magic_comment_t *
pm_magic_comment_next(const pm_magic_comment_t *magic_comment) {
    return (const pm_magic_comment_t *) magic_comment->node.next;
}

/**
 * Returns the number of magic comments associated with the given parser.
 */
size_t
pm_parser_magic_comments_size(const pm_parser_t *parser) {
    return parser->magic_comment_list.size;
}

/**
 * Returns the first magic comment associated with the given parser.
 */
const pm_magic_comment_t *
pm_parser_magic_comments_first(const pm_parser_t *parser) {
    return (const pm_magic_comment_t *) parser->magic_comment_list.head;
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

/**
 * Returns the first error associated with the given parser.
 */
const pm_diagnostic_t *
pm_parser_errors_first(const pm_parser_t *parser) {
    return (const pm_diagnostic_t *) parser->error_list.head;
}

/**
 * Returns the first warning associated with the given parser.
 */
const pm_diagnostic_t *
pm_parser_warnings_first(const pm_parser_t *parser) {
    return (const pm_diagnostic_t *) parser->warning_list.head;
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
 * Returns the constant at the given index in the constant pool associated with
 * the given parser.
 */
const pm_constant_t *
pm_parser_constant_at(const pm_parser_t *parser, size_t index) {
    assert(index < parser->constant_pool.size);
    return &parser->constant_pool.constants[index];
}

/**
 * Returns a pointer to the constant at the given id in the constant pool
 * associated with the given parser.
 */
const pm_constant_t *
pm_parser_constant(const pm_parser_t *parser, pm_constant_id_t constant_id) {
    return pm_constant_pool_id_to_constant(&parser->constant_pool, constant_id);
}
