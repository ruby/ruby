#ifndef PRISM_INTERNAL_REGEXP_H
#define PRISM_INTERNAL_REGEXP_H

#include "prism/ast.h"
#include "prism/compiler/inline.h"
#include "prism/internal/parser.h"

/* The name in the preprocessed pattern and its range in the original source. */
typedef struct {
    const uint8_t *name;
    size_t length;
    pm_location_t location;
} pm_regexp_capture_t;

/* Captures saved until the parser has read the right operand of =~. */
typedef struct pm_regexp_match {
    const pm_node_t *receiver;
    pm_regexp_capture_t *captures;
    size_t size;
} pm_regexp_match_t;

/*
 * Append a place to a list of places. When the list is full, it moves to a
 * larger array in the scratch arena, which releases the old one when parsing
 * finishes.
 */
void pm_regexp_offsets_append(pm_parser_t *parser, pm_regexp_offsets_t *offsets, pm_regexp_offset_t offset);

/*
 * Record that the given offset in the content is at the given offset in the
 * source, if the distance between them changed since the last place. The base
 * is the offset in the source of the start of the content, which gives the
 * distance before the first place.
 *
 * Text that is dropped, like a line continuation, leaves two places at the
 * same content offset. Only the second one is kept, so the places stay in
 * order with no two at the same offset.
 */
static PRISM_INLINE void
pm_regexp_offsets_record(pm_parser_t *parser, pm_regexp_offsets_t *offsets, uint32_t content, uint32_t source, uint32_t base) {
    pm_regexp_offset_t *last = offsets->size == 0 ? NULL : &offsets->values[offsets->size - 1];

    /* Each distance is a source offset minus a content offset. Both fit in 32
     * bits, so two distances differ by less than 2^32, and their subtractions,
     * which may wrap, are equal exactly when the distances are. */
    uint32_t previous = (last == NULL) ? base : (last->source - last->content);
    if (source - content == previous) return;

    if (last != NULL && last->content == content) {
        last->source = source;
    } else {
        pm_regexp_offsets_append(parser, offsets, (pm_regexp_offset_t) { .content = content, .source = source });
    }
}

/*
 * Parse a regular expression and validate its encoding. The offsets are where
 * the unescaped content of the node stops lining up with the source, as the
 * lexer recorded them. Returns the encoding flags to set on the node.
 */
PRISM_EXPORTED_FUNCTION pm_node_flags_t pm_regexp_parse(pm_parser_t *parser, pm_regular_expression_node_t *node, const pm_regexp_offsets_t *offsets);

/*
 * Validate a regular expression with interpolation. One that is a static
 * literal is validated as the regular expression that its parts join to, with
 * errors reported at the node.
 */
void pm_regexp_parse_interpolated(pm_parser_t *parser, const pm_interpolated_regular_expression_node_t *node);

#endif
