#include "prism/internal/static_literals.h"

#include "prism/compiler/inline.h"
#include "prism/compiler/unused.h"

#include "prism/internal/allocator.h"
#include "prism/internal/buffer.h"
#include "prism/internal/integer.h"
#include "prism/internal/isinf.h"
#include "prism/internal/oom.h"
#include "prism/internal/parser.h"
#include "prism/internal/stringy.h"
#include "prism/internal/xxh3.h"

#include <assert.h>
#include <inttypes.h>
#include <math.h>
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
 * Return the hash of the value of an integer. An integer that fits into a
 * uint32_t keys on its value directly, and a larger one keys on the digest of
 * its words.
 */
static uint64_t
integer_hash(const pm_integer_t *integer) {
    uint64_t magnitude = integer->values ? pm_xxh3((const uint8_t *) integer->values, sizeof(uint32_t) * integer->length) : integer->value;
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

            uint64_t bits;
            memcpy(&bits, &value, sizeof(bits));
            return key_hash(PM_FLOAT_NODE, bits, 0);
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
            assert(false && "unreachable");
            return 0;
    }
}

/**
 * Compare two values that can be compared with a simple numeric comparison.
 */
#define COMPARE(left_, right_) (((left_) < (right_)) ? -1 : ((left_) > (right_)) ? 1 : 0)

/**
 * Return the integer value of the given node as an int64_t.
 */
static int64_t
int64_value(const pm_parser_t *parser, const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_INTEGER_NODE: {
            const pm_integer_t *integer = &((const pm_integer_node_t *) node)->value;
            if (integer->values) return integer->negative ? INT64_MIN : INT64_MAX;

            int64_t value = (int64_t) integer->value;
            return integer->negative ? -value : value;
        }
        case PM_SOURCE_LINE_NODE:
            return (int64_t) pm_line_offset_list_line_column(&parser->line_offsets, node->location.start, parser->start_line).line;
        default:
            assert(false && "unreachable");
            return 0;
    }
}

/**
 * A comparison function for comparing two IntegerNode or SourceLineNode
 * instances.
 */
static int
compare_integer_nodes(const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    if (PM_NODE_TYPE_P(left, PM_SOURCE_LINE_NODE) || PM_NODE_TYPE_P(right, PM_SOURCE_LINE_NODE)) {
        return COMPARE(int64_value(parser, left), int64_value(parser, right));
    }

    const pm_integer_t *left_integer = &((const pm_integer_node_t *) left)->value;
    const pm_integer_t *right_integer = &((const pm_integer_node_t *) right)->value;
    return pm_integer_compare(left_integer, right_integer);
}

/**
 * A comparison function for comparing two FloatNode instances.
 */
static int
compare_float_nodes(PRISM_UNUSED const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    return COMPARE(((const pm_float_node_t *) left)->value, ((const pm_float_node_t *) right)->value);
}

/**
 * Return a pointer to the string value of the given node.
 */
static const pm_string_t *
string_value(const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_STRING_NODE:
            return &((const pm_string_node_t *) node)->unescaped;
        case PM_SOURCE_FILE_NODE:
            return &((const pm_source_file_node_t *) node)->filepath;
        case PM_SYMBOL_NODE:
            return &((const pm_symbol_node_t *) node)->unescaped;
        default:
            assert(false && "unreachable");
            return NULL;
    }
}

/**
 * A comparison function for comparing two nodes that have attached strings.
 * Only the flags in the given mask take part in the comparison.
 *
 * The FORCED_* flags record how a literal was written. An escape that locks the
 * encoding to UTF-8 (a `\u` escape above U+007F, or any `\u` in a character
 * literal) sets FORCED_UTF8 whether or not the file is already UTF-8. So in a
 * UTF-8 file a `\u00E9` escape and a literal e-acute carry different flags
 * while being the same string, and the flag is left out of the mask for them
 * to compare equally. A source file node never carries a FORCED_* flag, because
 * every instance of __FILE__ in a parse resolves to the same encoding.
 */
static int
compare_string_nodes(const pm_node_t *left, const pm_node_t *right, pm_node_flags_t mask) {
    const pm_string_t *left_string = string_value(left);
    const pm_string_t *right_string = string_value(right);

    int result = pm_string_compare(left_string, right_string);
    if (result != 0) return result;

    /*
     * Equal bytes are not enough. In a binary source file the two bytes written
     * as `"\xC3\xA9"` stay BINARY while a `"\u00E9"` escape is forced to UTF-8,
     * so those are distinct keys even though the bytes match.
     */
    return COMPARE(left->flags & mask, right->flags & mask);
}

/**
 * A comparison function for comparing two RegularExpressionNode instances. The
 * once flag is left out because it only controls how many times an
 * interpolated regular expression is compiled, not its value.
 */
static int
compare_regular_expression_nodes(PRISM_UNUSED const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    const pm_regular_expression_node_t *left_regexp = (const pm_regular_expression_node_t *) left;
    const pm_regular_expression_node_t *right_regexp = (const pm_regular_expression_node_t *) right;

    int result = pm_string_compare(&left_regexp->unescaped, &right_regexp->unescaped);
    if (result != 0) return result;

    pm_node_flags_t mask = (pm_node_flags_t) ~PM_REGULAR_EXPRESSION_FLAGS_ONCE;
    return COMPARE(left->flags & mask, right->flags & mask);
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
 * A comparison function for comparing any two static literal nodes. Nodes that
 * are compared as different types are never equal.
 */
static int
compare_nodes(const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    enum pm_node_type left_type = static_literal_type(left);
    enum pm_node_type right_type = static_literal_type(right);
    if (left_type != right_type) return COMPARE(left_type, right_type);

    switch (left_type) {
        case PM_INTEGER_NODE:
            return compare_integer_nodes(parser, left, right);
        case PM_FLOAT_NODE:
            return compare_float_nodes(parser, left, right);
        case PM_IMAGINARY_NODE:
            return compare_nodes(parser, ((const pm_imaginary_node_t *) left)->numeric, ((const pm_imaginary_node_t *) right)->numeric);
        case PM_RATIONAL_NODE: {
            const pm_rational_node_t *left_rational = (const pm_rational_node_t *) left;
            const pm_rational_node_t *right_rational = (const pm_rational_node_t *) right;

            int result = pm_integer_compare(&left_rational->denominator, &right_rational->denominator);
            if (result != 0) return result;

            return pm_integer_compare(&left_rational->numerator, &right_rational->numerator);
        }
        case PM_STRING_NODE: {
            pm_node_flags_t mask = PM_STRING_FLAGS_FORCED_BINARY_ENCODING;
            if (parser->encoding != PM_ENCODING_UTF_8_ENTRY) mask |= PM_STRING_FLAGS_FORCED_UTF8_ENCODING;
            return compare_string_nodes(left, right, mask);
        }
        case PM_SYMBOL_NODE: {
            pm_node_flags_t mask = PM_SYMBOL_FLAGS_FORCED_BINARY_ENCODING | PM_SYMBOL_FLAGS_FORCED_US_ASCII_ENCODING;
            if (parser->encoding != PM_ENCODING_UTF_8_ENTRY) mask |= PM_SYMBOL_FLAGS_FORCED_UTF8_ENCODING;
            return compare_string_nodes(left, right, mask);
        }
        case PM_REGULAR_EXPRESSION_NODE:
            return compare_regular_expression_nodes(parser, left, right);
        case PM_FALSE_NODE:
        case PM_NIL_NODE:
        case PM_SOURCE_ENCODING_NODE:
        case PM_TRUE_NODE:
            return 0;
        default:
            assert(false && "unreachable");
            return 0;
    }
}

#undef COMPARE

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

            if (compare_nodes(parser, existing, node) == 0) {
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
        if (entry->hash == hash && compare_nodes(parser, entry->node, node) == 0) break;
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
            return ((const pm_float_node_t *) node)->value > 0;
        case PM_INTEGER_NODE:
            return !((const pm_integer_node_t *) node)->value.negative;
        case PM_RATIONAL_NODE:
            return !((const pm_rational_node_t *) node)->numerator.negative;
        case PM_IMAGINARY_NODE:
            return pm_static_literal_positive_p(((const pm_imaginary_node_t *) node)->numeric);
        default:
            assert(false && "unreachable");
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
            pm_buffer_append_string(buffer, "false", 5);
            break;
        case PM_FLOAT_NODE: {
            const double value = ((const pm_float_node_t *) node)->value;

            if (PRISM_ISINF(value)) {
                if (parser->start[node->location.start] == '-') {
                    pm_buffer_append_byte(buffer, '-');
                }
                pm_buffer_append_string(buffer, "Infinity", 8);
            } else if (value == 0.0) {
                if (parser->start[node->location.start] == '-') {
                    pm_buffer_append_byte(buffer, '-');
                }
                pm_buffer_append_string(buffer, "0.0", 3);
            } else {
                pm_buffer_append_format(buffer, "%g", value);

                /* %g will not insert a .0 for 1e100 (we'll get back 1e+100). So
                 * we check for the decimal point and add it in here if it's not
                 * present. */
                if (pm_buffer_index(buffer, '.') == SIZE_MAX) {
                    size_t exponent_index = pm_buffer_index(buffer, 'e');
                    size_t index = exponent_index == SIZE_MAX ? pm_buffer_length(buffer) : exponent_index;
                    pm_buffer_insert(buffer, index, ".0", 2);
                }
            }

            break;
        }
        case PM_IMAGINARY_NODE: {
            const pm_node_t *numeric = ((const pm_imaginary_node_t *) node)->numeric;
            pm_buffer_append_string(buffer, "(0", 2);
            if (pm_static_literal_positive_p(numeric)) pm_buffer_append_byte(buffer, '+');
            pm_static_literal_inspect(buffer, parser, numeric);
            if (PM_NODE_TYPE_P(numeric, PM_RATIONAL_NODE)) {
                pm_buffer_append_byte(buffer, '*');
            }
            pm_buffer_append_string(buffer, "i)", 2);
            break;
        }
        case PM_INTEGER_NODE:
            pm_integer_string(buffer, &((const pm_integer_node_t *) node)->value);
            break;
        case PM_NIL_NODE:
            pm_buffer_append_string(buffer, "nil", 3);
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

            if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_MULTI_LINE)) pm_buffer_append_string(buffer, "m", 1);
            if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE)) pm_buffer_append_string(buffer, "i", 1);
            if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_EXTENDED)) pm_buffer_append_string(buffer, "x", 1);
            if (PM_NODE_FLAG_P(node, PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT)) pm_buffer_append_string(buffer, "n", 1);

            break;
        }
        case PM_SOURCE_ENCODING_NODE:
            pm_buffer_append_format(buffer, "#<Encoding:%s>", parser->encoding->name);
            break;
        case PM_SOURCE_FILE_NODE: {
            const pm_string_t *filepath = &((const pm_source_file_node_t *) node)->filepath;
            pm_buffer_append_byte(buffer, '"');
            pm_buffer_append_source(buffer, pm_string_source(filepath), pm_string_length(filepath), PM_BUFFER_ESCAPING_RUBY);
            pm_buffer_append_byte(buffer, '"');
            break;
        }
        case PM_SOURCE_LINE_NODE:
            pm_buffer_append_format(buffer, "%" PRIi32, pm_line_offset_list_line_column(&parser->line_offsets, node->location.start, parser->start_line).line);
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
            pm_buffer_append_string(buffer, "true", 4);
            break;
        default:
            assert(false && "unreachable");
            break;
    }
}
