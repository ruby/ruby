#include "prism/internal/static_literals.h"

#include "prism/compiler/inline.h"

#include "prism/internal/allocator.h"
#include "prism/internal/assert.h"
#include "prism/internal/buffer.h"
#include "prism/internal/char.h"
#include "prism/internal/double.h"
#include "prism/internal/integer.h"
#include "prism/internal/line_offset_list.h"
#include "prism/internal/memequal.h"
#include "prism/internal/oom.h"
#include "prism/internal/parser.h"
#include "prism/internal/stringy.h"
#include "prism/internal/xxh3.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/**
 * Hash the key built from the given values. Nodes that compare as equal must
 * produce identical keys, so each value is either held directly or is the
 * digest of a variable-length value. The key is an array so that its values are
 * contiguous with no padding between them, which makes every hashed byte
 * defined.
 */
static PRISM_INLINE uint64_t
key_hash(uint64_t type, uint64_t a, uint64_t b) {
    const uint64_t key[3] = { type, a, b };
    return pm_xxh3((const uint8_t *) key, sizeof(key));
}

/**
 * Return the hash of the value of an integer. An integer whose words are stored
 * inline keys on its value directly, and a larger one keys on the digest of its
 * words.
 */
static uint64_t
integer_hash(const pm_integer_t *integer) {
    uint64_t magnitude = (integer->length > 2)
        ? pm_xxh3((const uint8_t *) integer->words.values, sizeof(uint32_t) * integer->length)
        : pm_integer_uint64_value(integer);
    return key_hash(PM_INTEGER_NODE, integer->negative, magnitude);
}

/**
 * Return the hash of the key of the given node. It is important that nodes that
 * have equivalent static literal values have the same key. This is because we
 * hash these keys to look for duplicates.
 */
static uint64_t
node_hash(const pm_parser_t *parser, const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_INTEGER_NODE:
            return integer_hash(&((const pm_integer_node_t *) node)->value);
        case PM_SOURCE_LINE_NODE: {
            int64_t line = (int64_t) pm_line_offset_list_line_column(&parser->line_offsets, node->location.start, parser->start_line).line;
            return key_hash(PM_INTEGER_NODE, line < 0, (uint64_t) (line < 0 ? -line : line));
        }
        case PM_FLOAT_NODE: {
            const pm_float_node_t *cast = (const pm_float_node_t *) node;
            double value = cast->value;
            if (value == 0.0) value = 0.0; /* Normalize -0.0 to 0.0. */

            return key_hash(PM_FLOAT_NODE, pm_binary64_bits(value), 0);
        }
        case PM_RATIONAL_NODE: {
            const pm_rational_node_t *cast = (const pm_rational_node_t *) node;
            return key_hash(PM_RATIONAL_NODE, integer_hash(&cast->numerator), integer_hash(&cast->denominator));
        }
        case PM_IMAGINARY_NODE: {
            const pm_imaginary_node_t *cast = (const pm_imaginary_node_t *) node;
            return key_hash(PM_IMAGINARY_NODE, node_hash(parser, cast->numeric), 0);
        }
        case PM_STRING_NODE: {
            const pm_string_node_t *cast = (const pm_string_node_t *) node;

            pm_node_flags_t mask = PM_STRING_FLAGS_FORCED_BINARY_ENCODING;
            if (parser->encoding != PM_ENCODING_UTF_8_ENTRY) mask |= PM_STRING_FLAGS_FORCED_UTF8_ENCODING;

            return key_hash(PM_STRING_NODE, pm_xxh3(pm_string_source(&cast->unescaped), pm_string_length(&cast->unescaped)), node->flags & mask);
        }
        case PM_SOURCE_FILE_NODE: {
            const pm_source_file_node_t *cast = (const pm_source_file_node_t *) node;
            return key_hash(PM_STRING_NODE, pm_xxh3(pm_string_source(&cast->filepath), pm_string_length(&cast->filepath)), 0);
        }
        case PM_REGULAR_EXPRESSION_NODE: {
            const pm_regular_expression_node_t *cast = (const pm_regular_expression_node_t *) node;
            return key_hash(PM_REGULAR_EXPRESSION_NODE, pm_xxh3(pm_string_source(&cast->unescaped), pm_string_length(&cast->unescaped)), node->flags & (pm_node_flags_t) ~PM_REGULAR_EXPRESSION_FLAGS_ONCE);
        }
        case PM_SYMBOL_NODE: {
            const pm_symbol_node_t *cast = (const pm_symbol_node_t *) node;

            pm_node_flags_t mask = PM_SYMBOL_FLAGS_FORCED_BINARY_ENCODING | PM_SYMBOL_FLAGS_FORCED_US_ASCII_ENCODING;
            if (parser->encoding != PM_ENCODING_UTF_8_ENTRY) mask |= PM_SYMBOL_FLAGS_FORCED_UTF8_ENCODING;

            return key_hash(PM_SYMBOL_NODE, pm_xxh3(pm_string_source(&cast->unescaped), pm_string_length(&cast->unescaped)), node->flags & mask);
        }
        case PM_FALSE_NODE:
        case PM_NIL_NODE:
        case PM_SOURCE_ENCODING_NODE:
        case PM_TRUE_NODE:
            return key_hash(PM_NODE_TYPE(node), 0, 0);
        default:
            PRISM_ASSERT(false && "unreachable");
            return 0;
    }
}

/**
 * Return the integer value of the given node as an int64_t.
 */
static int64_t
int64_value(const pm_parser_t *parser, const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_INTEGER_NODE: {
            const pm_integer_t *integer = &((const pm_integer_node_t *) node)->value;
            if (integer->length > 1) return integer->negative ? INT64_MIN : INT64_MAX;

            int64_t value = (int64_t) pm_integer_uint64_value(integer);
            return integer->negative ? -value : value;
        }
        case PM_SOURCE_LINE_NODE:
            return (int64_t) pm_line_offset_list_line_column(&parser->line_offsets, node->location.start, parser->start_line).line;
        default:
            PRISM_ASSERT(false && "unreachable");
            return 0;
    }
}

/**
 * Return whether two IntegerNode or SourceLineNode instances have equal values.
 */
static bool
integer_nodes_equal(const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    if (PM_NODE_TYPE_P(left, PM_SOURCE_LINE_NODE) || PM_NODE_TYPE_P(right, PM_SOURCE_LINE_NODE)) {
        return int64_value(parser, left) == int64_value(parser, right);
    }

    const pm_integer_t *left_integer = &((const pm_integer_node_t *) left)->value;
    const pm_integer_t *right_integer = &((const pm_integer_node_t *) right)->value;
    return !pm_integer_compare(left_integer, right_integer);
}

/**
 * Return a pointer to the string value of the given node.
 */
static const pm_string_t *
string_value(const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_REGULAR_EXPRESSION_NODE:
            return &((const pm_regular_expression_node_t *) node)->unescaped;
        case PM_STRING_NODE:
            return &((const pm_string_node_t *) node)->unescaped;
        case PM_SOURCE_FILE_NODE:
            return &((const pm_source_file_node_t *) node)->filepath;
        case PM_SYMBOL_NODE:
            return &((const pm_symbol_node_t *) node)->unescaped;
        default:
            PRISM_ASSERT(false && "unreachable");
            return NULL;
    }
}

/**
 * Return whether two nodes have equal string bytes and flags under the mask.
 *
 * The FORCED_* flags record how a literal was written. An escape that locks the
 * encoding to UTF-8 (a `\u` escape above U+007F, or any `\u` in a character
 * literal) sets FORCED_UTF8 whether or not the file is already UTF-8. So in a
 * UTF-8 file a `\u00E9` escape and a literal e-acute carry different flags
 * while being the same string, and the flag is left out of the mask for them
 * to compare equally. A source file node never carries a FORCED_* flag, because
 * every instance of __FILE__ in a parse resolves to the same encoding.
 */
static bool
string_nodes_equal(const pm_node_t *left, const pm_node_t *right, pm_node_flags_t mask) {
    if ((left->flags & mask) != (right->flags & mask)) return false;

    const pm_string_t *left_string = string_value(left);
    const pm_string_t *right_string = string_value(right);
    return left_string->length == right_string->length && pm_memequal(left_string->source, right_string->source, left_string->length);
}

/**
 * Return the type that the given node is compared as. A source line node can
 * equal an integer node and a source file node can equal a string node, so
 * each takes the type of the node it can equal.
 */
static enum pm_node_type
static_literal_type(const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_SOURCE_LINE_NODE:
            return PM_INTEGER_NODE;
        case PM_SOURCE_FILE_NODE:
            return PM_STRING_NODE;
        default:
            return PM_NODE_TYPE(node);
    }
}

/**
 * Return whether two nodes represent the same static literal.
 */
static bool
nodes_equal(const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    enum pm_node_type left_type = static_literal_type(left);
    enum pm_node_type right_type = static_literal_type(right);
    if (left_type != right_type) return false;

    switch (left_type) {
        case PM_INTEGER_NODE:
            return integer_nodes_equal(parser, left, right);
        case PM_FLOAT_NODE:
            return ((const pm_float_node_t *) left)->value == ((const pm_float_node_t *) right)->value;
        case PM_IMAGINARY_NODE:
            return nodes_equal(parser, ((const pm_imaginary_node_t *) left)->numeric, ((const pm_imaginary_node_t *) right)->numeric);
        case PM_RATIONAL_NODE: {
            const pm_rational_node_t *left_rational = (const pm_rational_node_t *) left;
            const pm_rational_node_t *right_rational = (const pm_rational_node_t *) right;

            return !pm_integer_compare(&left_rational->denominator, &right_rational->denominator) &&
                   !pm_integer_compare(&left_rational->numerator, &right_rational->numerator);
        }
        case PM_STRING_NODE: {
            pm_node_flags_t mask = PM_STRING_FLAGS_FORCED_BINARY_ENCODING;
            if (parser->encoding != PM_ENCODING_UTF_8_ENTRY) mask |= PM_STRING_FLAGS_FORCED_UTF8_ENCODING;
            return string_nodes_equal(left, right, mask);
        }
        case PM_SYMBOL_NODE: {
            pm_node_flags_t mask = PM_SYMBOL_FLAGS_FORCED_BINARY_ENCODING | PM_SYMBOL_FLAGS_FORCED_US_ASCII_ENCODING;
            if (parser->encoding != PM_ENCODING_UTF_8_ENTRY) mask |= PM_SYMBOL_FLAGS_FORCED_UTF8_ENCODING;
            return string_nodes_equal(left, right, mask);
        }
        case PM_REGULAR_EXPRESSION_NODE:
            /* The once flag only controls how often the regexp is compiled. */
            return string_nodes_equal(left, right, (pm_node_flags_t) ~PM_REGULAR_EXPRESSION_FLAGS_ONCE);
        case PM_FALSE_NODE:
        case PM_NIL_NODE:
        case PM_SOURCE_ENCODING_NODE:
        case PM_TRUE_NODE:
            return true;
        default:
            PRISM_ASSERT(false && "unreachable");
            return false;
    }
}

/**
 * Place an entry into a hash table that is known not to hold an equal node, so
 * no comparisons are needed to find its slot.
 */
static void
pm_static_literals_place(pm_static_literals_entry_t *entries, uint32_t mask, pm_static_literals_entry_t entry) {
    uint32_t index = (uint32_t) (entry.hash & mask);
    while (entries[index].node != NULL) {
        index = (index + 1) & mask;
    }
    entries[index] = entry;
}

/**
 * Move the nodes of the set into a new hash table with the given capacity. A
 * set that has no hash table yet hashes its inline nodes. A set that already
 * has one moves its entries, which keep their hashes.
 */
static void
pm_static_literals_resize(const pm_parser_t *parser, pm_static_literals_t *literals, uint32_t capacity) {
    pm_static_literals_entry_t *entries = xcalloc(capacity, sizeof(pm_static_literals_entry_t));
    if (entries == NULL) PRISM_OOM();

    /* It turns out to be more efficient to mask the hash value than to use the
     * modulo operator. Because our capacities are always powers of two, we can
     * use a bitwise AND to get the same result as the modulo operator. */
    uint32_t mask = capacity - 1;

    if (literals->capacity == 0) {
        for (uint32_t index = 0; index < literals->size; index++) {
            pm_node_t *node = literals->nodes[index];
            pm_static_literals_place(entries, mask, (pm_static_literals_entry_t) { .node = node, .hash = node_hash(parser, node) });
        }
    } else {
        for (uint32_t index = 0; index < literals->capacity; index++) {
            if (literals->entries[index].node != NULL) {
                pm_static_literals_place(entries, mask, literals->entries[index]);
            }
        }

        xfree_sized(literals->entries, literals->capacity * sizeof(pm_static_literals_entry_t));
    }

    literals->entries = entries;
    literals->capacity = capacity;
}

/**
 * Add a node to the set of static literals. If an equal node is already in the
 * set, it is returned (and replaced by the new node if replace is set).
 * Otherwise the new node is inserted and NULL is returned. Nodes that are not
 * static literals are ignored.
 */
pm_node_t *
pm_static_literals_add(const pm_parser_t *parser, pm_static_literals_t *literals, pm_node_t *node, bool replace) {
    switch (PM_NODE_TYPE(node)) {
        case PM_FALSE_NODE:
        case PM_FLOAT_NODE:
        case PM_IMAGINARY_NODE:
        case PM_INTEGER_NODE:
        case PM_NIL_NODE:
        case PM_RATIONAL_NODE:
        case PM_REGULAR_EXPRESSION_NODE:
        case PM_SOURCE_ENCODING_NODE:
        case PM_SOURCE_FILE_NODE:
        case PM_SOURCE_LINE_NODE:
        case PM_STRING_NODE:
        case PM_SYMBOL_NODE:
        case PM_TRUE_NODE:
            break;
        default:
            return NULL;
    }

    if (literals->capacity == 0) {
        /* A set without a hash table compares the new node against each of
         * its nodes directly. Comparing nodes of different types returns
         * early, so this costs about as much as hashing the new node. */
        for (uint32_t index = 0; index < literals->size; index++) {
            pm_node_t *existing = literals->nodes[index];

            if (nodes_equal(parser, existing, node)) {
                if (replace) literals->nodes[index] = node;
                return existing;
            }
        }

        if (literals->size < PM_STATIC_LITERALS_INLINE_CAPACITY) {
            literals->nodes[literals->size++] = node;
            return NULL;
        }

        /* The set is full, so its nodes move into a hash table. The table is
         * sized to stay at most half full after this node is added, with room
         * to spare before its first resize. */
        pm_static_literals_resize(parser, literals, PM_STATIC_LITERALS_INLINE_CAPACITY * 4);
    } else if (literals->size * 2 >= literals->capacity) {
        /* If we are out of space, we need to resize the hash. */
        pm_static_literals_resize(parser, literals, literals->capacity * 2);
    }

    uint64_t hash = node_hash(parser, node);
    uint32_t mask = literals->capacity - 1;
    uint32_t index = (uint32_t) (hash & mask);

    /* We use linear probing to resolve collisions. This means that if the
     * current index is occupied, we will move to the next index and try again.
     * We are guaranteed that this will eventually find an empty slot because we
     * resize the hash when it gets too full. Entries whose hash differs cannot
     * be equal, so only entries with a matching hash are compared. */
    while (literals->entries[index].node != NULL) {
        const pm_static_literals_entry_t *entry = &literals->entries[index];
        if (entry->hash == hash && nodes_equal(parser, entry->node, node)) break;
        index = (index + 1) & mask;
    }

    /* If the current index is occupied, we need to return the node that was
     * already in the hash. Otherwise, we can just increment the size and insert
     * the new node. */
    pm_node_t *result = literals->entries[index].node;

    if (result == NULL) {
        literals->size++;
        literals->entries[index] = (pm_static_literals_entry_t) { .node = node, .hash = hash };
    } else if (replace) {
        literals->entries[index].node = node;
    }

    return result;
}

/**
 * Free the internal memory associated with the given static literals set.
 */
void
pm_static_literals_free(pm_static_literals_t *literals) {
    if (literals->capacity > 0) xfree_sized(literals->entries, literals->capacity * sizeof(pm_static_literals_entry_t));
}

/**
 * A helper to determine if the given node is a static literal that is positive.
 * This is used for formatting imaginary nodes.
 */
static bool
pm_static_literal_positive_p(const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_FLOAT_NODE:
            return !pm_double_negative_p(((const pm_float_node_t *) node)->value);
        case PM_INTEGER_NODE:
            return !((const pm_integer_node_t *) node)->value.negative;
        case PM_RATIONAL_NODE:
            return !((const pm_rational_node_t *) node)->numerator.negative;
        case PM_IMAGINARY_NODE:
            return pm_static_literal_positive_p(((const pm_imaginary_node_t *) node)->numeric);
        default:
            PRISM_ASSERT(false && "unreachable");
            return false;
    }
}

/**
 * Create a string-based representation of the given static literal.
 */
void
pm_static_literal_inspect(pm_buffer_t *buffer, const pm_parser_t *parser, const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_FALSE_NODE:
            PM_BUFFER_APPEND_LITERAL(buffer, "false");
            break;
        case PM_FLOAT_NODE:
            pm_double_string(buffer, ((const pm_float_node_t *) node)->value);
            break;
        case PM_IMAGINARY_NODE: {
            const pm_node_t *numeric = ((const pm_imaginary_node_t *) node)->numeric;
            PM_BUFFER_APPEND_LITERAL(buffer, "(0");
            if (pm_static_literal_positive_p(numeric)) pm_buffer_append_byte(buffer, '+');
            pm_static_literal_inspect(buffer, parser, numeric);
            /* Rational and non-finite coefficients end in a non-digit. */
            if (!pm_char_is_decimal_digit((uint8_t) buffer->value[buffer->length - 1])) {
                pm_buffer_append_byte(buffer, '*');
            }
            PM_BUFFER_APPEND_LITERAL(buffer, "i)");
            break;
        }
        case PM_INTEGER_NODE:
            pm_integer_string(buffer, &((const pm_integer_node_t *) node)->value);
            break;
        case PM_NIL_NODE:
            PM_BUFFER_APPEND_LITERAL(buffer, "nil");
            break;
        case PM_RATIONAL_NODE: {
            const pm_rational_node_t *rational = (const pm_rational_node_t *) node;
            pm_buffer_append_byte(buffer, '(');
            pm_integer_string(buffer, &rational->numerator);
            pm_buffer_append_byte(buffer, '/');
            pm_integer_string(buffer, &rational->denominator);
            pm_buffer_append_byte(buffer, ')');
            break;
        }
        case PM_REGULAR_EXPRESSION_NODE: {
            const pm_string_t *unescaped = &((const pm_regular_expression_node_t *) node)->unescaped;
            pm_buffer_append_byte(buffer, '/');
            pm_buffer_append_source(buffer, pm_string_source(unescaped), pm_string_length(unescaped), PM_BUFFER_ESCAPING_RUBY);
            pm_buffer_append_byte(buffer, '/');

            if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_MULTI_LINE)) pm_buffer_append_byte(buffer, 'm');
            if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE)) pm_buffer_append_byte(buffer, 'i');
            if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_EXTENDED)) pm_buffer_append_byte(buffer, 'x');
            if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT)) pm_buffer_append_byte(buffer, 'n');

            break;
        }
        case PM_SOURCE_ENCODING_NODE: {
            const char *name = parser->encoding->name;
            PM_BUFFER_APPEND_LITERAL(buffer, "#<Encoding:");
            pm_buffer_append_string(buffer, name, strlen(name));
            pm_buffer_append_byte(buffer, '>');
            break;
        }
        case PM_SOURCE_FILE_NODE: {
            const pm_string_t *filepath = &((const pm_source_file_node_t *) node)->filepath;
            pm_buffer_append_byte(buffer, '"');
            pm_buffer_append_source(buffer, pm_string_source(filepath), pm_string_length(filepath), PM_BUFFER_ESCAPING_RUBY);
            pm_buffer_append_byte(buffer, '"');
            break;
        }
        case PM_SOURCE_LINE_NODE:
            pm_buffer_append_line_number(buffer, pm_line_offset_list_line(&parser->line_offsets, node->location.start, parser->start_line), 0);
            break;
        case PM_STRING_NODE: {
            const pm_string_t *unescaped = &((const pm_string_node_t *) node)->unescaped;
            pm_buffer_append_byte(buffer, '"');
            pm_buffer_append_source(buffer, pm_string_source(unescaped), pm_string_length(unescaped), PM_BUFFER_ESCAPING_RUBY);
            pm_buffer_append_byte(buffer, '"');
            break;
        }
        case PM_SYMBOL_NODE: {
            const pm_string_t *unescaped = &((const pm_symbol_node_t *) node)->unescaped;
            pm_buffer_append_byte(buffer, ':');
            pm_buffer_append_source(buffer, pm_string_source(unescaped), pm_string_length(unescaped), PM_BUFFER_ESCAPING_RUBY);
            break;
        }
        case PM_TRUE_NODE:
            PM_BUFFER_APPEND_LITERAL(buffer, "true");
            break;
        default:
            PRISM_ASSERT(false && "unreachable");
            break;
    }
}
