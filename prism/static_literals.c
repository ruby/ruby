#include "prism/static_literals.h"

static inline uint32_t
murmur_scramble(uint32_t value) {
    value *= 0xcc9e2d51;
    value = (value << 15) | (value >> 17);
    value *= 0x1b873593;
    return value;
}

/**
 * Murmur hash (https://en.wikipedia.org/wiki/MurmurHash) is a non-cryptographic
 * general-purpose hash function. It is fast, which is what we care about in
 * this case.
 */
static uint32_t
murmur_hash(const uint8_t *key, size_t length) {
    uint32_t hash = 0x9747b28c;
    uint32_t segment;

    for (size_t index = length >> 2; index; index--) {
        memcpy(&segment, key, sizeof(uint32_t));
        key += sizeof(uint32_t);
        hash ^= murmur_scramble(segment);
        hash = (hash << 13) | (hash >> 19);
        hash = hash * 5 + 0xe6546b64;
    }

    segment = 0;
    for (size_t index = length & 3; index; index--) {
        segment <<= 8;
        segment |= key[index - 1];
    }

    hash ^= murmur_scramble(segment);
    hash ^= (uint32_t) length;
    hash ^= hash >> 16;
    hash *= 0x85ebca6b;
    hash ^= hash >> 13;
    hash *= 0xc2b2ae35;
    hash ^= hash >> 16;
    return hash;
}

/**
 * Return the hash of the given node. It is important that nodes that have
 * equivalent static literal values have the same hash. This is because we use
 * these hashes to look for duplicates.
 */
static uint32_t
node_hash(const pm_parser_t *parser, const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_INTEGER_NODE: {
            // Integers hash their value.
            const pm_integer_t *integer = &((const pm_integer_node_t *) node)->value;
            uint32_t hash;
            if (integer->values) {
                hash = murmur_hash((const uint8_t *) integer->values, sizeof(uint32_t) * integer->length);
            } else {
                hash = murmur_hash((const uint8_t *) &integer->value, sizeof(uint32_t));
            }

            if (integer->negative) {
                hash ^= murmur_scramble((uint32_t) 1);
            }

            return hash;
        }
        case PM_SOURCE_LINE_NODE: {
            // Source lines hash their line number.
            const pm_line_column_t line_column = pm_newline_list_line_column(&parser->newline_list, node->location.start, parser->start_line);
            const int32_t *value = &line_column.line;
            return murmur_hash((const uint8_t *) value, sizeof(int32_t));
        }
        case PM_FLOAT_NODE: {
            // Floats hash their value.
            const double *value = &((const pm_float_node_t *) node)->value;
            return murmur_hash((const uint8_t *) value, sizeof(double));
        }
        case PM_RATIONAL_NODE: {
            // Rationals hash their numeric value. Because their numeric value
            // is stored as a subnode, we hash that node and then mix in the
            // fact that this is a rational node.
            const pm_node_t *numeric = ((const pm_rational_node_t *) node)->numeric;
            return node_hash(parser, numeric) ^ murmur_scramble((uint32_t) node->type);
        }
        case PM_IMAGINARY_NODE: {
            // Imaginaries hash their numeric value. Because their numeric value
            // is stored as a subnode, we hash that node and then mix in the
            // fact that this is an imaginary node.
            const pm_node_t *numeric = ((const pm_imaginary_node_t *) node)->numeric;
            return node_hash(parser, numeric) ^ murmur_scramble((uint32_t) node->type);
        }
        case PM_STRING_NODE: {
            // Strings hash their value and mix in their flags so that different
            // encodings are not considered equal.
            const pm_string_t *value = &((const pm_string_node_t *) node)->unescaped;
            return murmur_hash(pm_string_source(value), pm_string_length(value) * sizeof(uint8_t)) ^ murmur_scramble((uint32_t) node->flags);
        }
        case PM_SOURCE_FILE_NODE: {
            // Source files hash their value and mix in their flags so that
            // different encodings are not considered equal.
            const pm_string_t *value = &((const pm_source_file_node_t *) node)->filepath;
            return murmur_hash(pm_string_source(value), pm_string_length(value) * sizeof(uint8_t)) ^ murmur_scramble((uint32_t) node->flags);
        }
        case PM_REGULAR_EXPRESSION_NODE: {
            // Regular expressions hash their value and mix in their flags so
            // that different encodings are not considered equal.
            const pm_string_t *value = &((const pm_regular_expression_node_t *) node)->unescaped;
            return murmur_hash(pm_string_source(value), pm_string_length(value) * sizeof(uint8_t)) ^ murmur_scramble((uint32_t) node->flags);
        }
        case PM_SYMBOL_NODE: {
            // Symbols hash their value and mix in their flags so that different
            // encodings are not considered equal.
            const pm_string_t *value = &((const pm_symbol_node_t *) node)->unescaped;
            return murmur_hash(pm_string_source(value), pm_string_length(value) * sizeof(uint8_t)) ^ murmur_scramble((uint32_t) node->flags);
        }
        default:
            assert(false && "unreachable");
            return 0;
    }
}

/**
 * Insert a node into the node hash. It accepts the hash that should hold the
 * new node, the parser that generated the node, the node to insert, and a
 * comparison function. The comparison function is used for collision detection,
 * and must be able to compare all node types that will be stored in this hash.
 */
static pm_node_t *
pm_node_hash_insert(pm_node_hash_t *hash, const pm_parser_t *parser, pm_node_t *node, int (*compare)(const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right)) {
    // If we are out of space, we need to resize the hash. This will cause all
    // of the nodes to be rehashed and reinserted into the new hash.
    if (hash->size * 2 >= hash->capacity) {
        // First, allocate space for the new node list.
        uint32_t new_capacity = hash->capacity == 0 ? 4 : hash->capacity * 2;
        pm_node_t **new_nodes = xcalloc(new_capacity, sizeof(pm_node_t *));
        if (new_nodes == NULL) return NULL;

        // It turns out to be more efficient to mask the hash value than to use
        // the modulo operator. Because our capacities are always powers of two,
        // we can use a bitwise AND to get the same result as the modulo
        // operator.
        uint32_t mask = new_capacity - 1;

        // Now, rehash all of the nodes into the new list.
        for (uint32_t index = 0; index < hash->capacity; index++) {
            pm_node_t *node = hash->nodes[index];

            if (node != NULL) {
                uint32_t index = node_hash(parser, node) & mask;
                new_nodes[index] = node;
            }
        }

        // Finally, free the old node list and update the hash.
        xfree(hash->nodes);
        hash->nodes = new_nodes;
        hash->capacity = new_capacity;
    }

    // Now, insert the node into the hash.
    uint32_t mask = hash->capacity - 1;
    uint32_t index = node_hash(parser, node) & mask;

    // We use linear probing to resolve collisions. This means that if the
    // current index is occupied, we will move to the next index and try again.
    // We are guaranteed that this will eventually find an empty slot because we
    // resize the hash when it gets too full.
    while (hash->nodes[index] != NULL) {
        if (compare(parser, hash->nodes[index], node) == 0) break;
        index = (index + 1) & mask;
    }

    // If the current index is occupied, we need to return the node that was
    // already in the hash. Otherwise, we can just increment the size and insert
    // the new node.
    pm_node_t *result = hash->nodes[index];
    if (result == NULL) hash->size++;

    hash->nodes[index] = node;
    return result;
}

/**
 * Free the internal memory associated with the given node hash.
 */
static void
pm_node_hash_free(pm_node_hash_t *hash) {
    if (hash->capacity > 0) xfree(hash->nodes);
}

/**
 * Compare two values that can be compared with a simple numeric comparison.
 */
#define PM_NUMERIC_COMPARISON(left, right) ((left < right) ? -1 : (left > right) ? 1 : 0)

/**
 * Return the integer value of the given node as an int64_t.
 */
static int64_t
pm_int64_value(const pm_parser_t *parser, const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
        case PM_INTEGER_NODE: {
            const pm_integer_t *integer = &((const pm_integer_node_t *) node)->value;
            if (integer->values) return integer->negative ? INT64_MIN : INT64_MAX;

            int64_t value = (int64_t) integer->value;
            return integer->negative ? -value : value;
        }
        case PM_SOURCE_LINE_NODE:
            return (int64_t) pm_newline_list_line_column(&parser->newline_list, node->location.start, parser->start_line).line;
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
pm_compare_integer_nodes(const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    if (PM_NODE_TYPE_P(left, PM_SOURCE_LINE_NODE) || PM_NODE_TYPE_P(right, PM_SOURCE_LINE_NODE)) {
        int64_t left_value = pm_int64_value(parser, left);
        int64_t right_value = pm_int64_value(parser, right);
        return PM_NUMERIC_COMPARISON(left_value, right_value);
    }

    const pm_integer_t *left_integer = &((const pm_integer_node_t *) left)->value;
    const pm_integer_t *right_integer = &((const pm_integer_node_t *) right)->value;
    return pm_integer_compare(left_integer, right_integer);
}

/**
 * A comparison function for comparing two FloatNode instances.
 */
static int
pm_compare_float_nodes(PRISM_ATTRIBUTE_UNUSED const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    const double left_value = ((const pm_float_node_t *) left)->value;
    const double right_value = ((const pm_float_node_t *) right)->value;
    return PM_NUMERIC_COMPARISON(left_value, right_value);
}

/**
 * A comparison function for comparing two nodes that have attached numbers.
 */
static int
pm_compare_number_nodes(const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    if (PM_NODE_TYPE(left) != PM_NODE_TYPE(right)) {
        return PM_NUMERIC_COMPARISON(PM_NODE_TYPE(left), PM_NODE_TYPE(right));
    }

    switch (PM_NODE_TYPE(left)) {
        case PM_IMAGINARY_NODE:
            return pm_compare_number_nodes(parser, ((const pm_imaginary_node_t *) left)->numeric, ((const pm_imaginary_node_t *) right)->numeric);
        case PM_RATIONAL_NODE:
            return pm_compare_number_nodes(parser, ((const pm_rational_node_t *) left)->numeric, ((const pm_rational_node_t *) right)->numeric);
        case PM_INTEGER_NODE:
            return pm_compare_integer_nodes(parser, left, right);
        case PM_FLOAT_NODE:
            return pm_compare_float_nodes(parser, left, right);
        default:
            assert(false && "unreachable");
            return 0;
    }
}

/**
 * Return a pointer to the string value of the given node.
 */
static const pm_string_t *
pm_string_value(const pm_node_t *node) {
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
 */
static int
pm_compare_string_nodes(PRISM_ATTRIBUTE_UNUSED const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    const pm_string_t *left_string = pm_string_value(left);
    const pm_string_t *right_string = pm_string_value(right);
    return pm_string_compare(left_string, right_string);
}

/**
 * A comparison function for comparing two RegularExpressionNode instances.
 */
static int
pm_compare_regular_expression_nodes(PRISM_ATTRIBUTE_UNUSED const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right) {
    const pm_regular_expression_node_t *left_regexp = (const pm_regular_expression_node_t *) left;
    const pm_regular_expression_node_t *right_regexp = (const pm_regular_expression_node_t *) right;

    int result = pm_string_compare(&left_regexp->unescaped, &right_regexp->unescaped);
    if (result != 0) return result;

    return PM_NUMERIC_COMPARISON(left_regexp->base.flags, right_regexp->base.flags);
}

#undef PM_NUMERIC_COMPARISON

/**
 * Add a node to the set of static literals.
 */
pm_node_t *
pm_static_literals_add(const pm_parser_t *parser, pm_static_literals_t *literals, pm_node_t *node) {
    if (!PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL)) return NULL;

    switch (PM_NODE_TYPE(node)) {
        case PM_INTEGER_NODE:
        case PM_SOURCE_LINE_NODE:
            return pm_node_hash_insert(&literals->integer_nodes, parser, node, pm_compare_integer_nodes);
        case PM_FLOAT_NODE:
            return pm_node_hash_insert(&literals->float_nodes, parser, node, pm_compare_float_nodes);
        case PM_RATIONAL_NODE:
        case PM_IMAGINARY_NODE:
            return pm_node_hash_insert(&literals->number_nodes, parser, node, pm_compare_number_nodes);
        case PM_STRING_NODE:
        case PM_SOURCE_FILE_NODE:
            return pm_node_hash_insert(&literals->string_nodes, parser, node, pm_compare_string_nodes);
        case PM_REGULAR_EXPRESSION_NODE:
            return pm_node_hash_insert(&literals->regexp_nodes, parser, node, pm_compare_regular_expression_nodes);
        case PM_SYMBOL_NODE:
            return pm_node_hash_insert(&literals->symbol_nodes, parser, node, pm_compare_string_nodes);
        case PM_TRUE_NODE: {
            pm_node_t *duplicated = literals->true_node;
            literals->true_node = node;
            return duplicated;
        }
        case PM_FALSE_NODE: {
            pm_node_t *duplicated = literals->false_node;
            literals->false_node = node;
            return duplicated;
        }
        case PM_NIL_NODE: {
            pm_node_t *duplicated = literals->nil_node;
            literals->nil_node = node;
            return duplicated;
        }
        case PM_SOURCE_ENCODING_NODE: {
            pm_node_t *duplicated = literals->source_encoding_node;
            literals->source_encoding_node = node;
            return duplicated;
        }
        default:
            return NULL;
    }
}

/**
 * Free the internal memory associated with the given static literals set.
 */
void
pm_static_literals_free(pm_static_literals_t *literals) {
    pm_node_hash_free(&literals->integer_nodes);
    pm_node_hash_free(&literals->float_nodes);
    pm_node_hash_free(&literals->number_nodes);
    pm_node_hash_free(&literals->string_nodes);
    pm_node_hash_free(&literals->regexp_nodes);
    pm_node_hash_free(&literals->symbol_nodes);
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
            return pm_static_literal_positive_p(((const pm_rational_node_t *) node)->numeric);
        case PM_IMAGINARY_NODE:
            return pm_static_literal_positive_p(((const pm_imaginary_node_t *) node)->numeric);
        default:
            assert(false && "unreachable");
            return false;
    }
}

/**
 * Inspect a rational node that wraps a float node. This is going to be a
 * poor-man's version of the Ruby `Rational#to_s` method, because we're not
 * going to try to reduce the rational by finding the GCD. We'll leave that for
 * a future improvement.
 */
static void
pm_rational_inspect(pm_buffer_t *buffer, pm_rational_node_t *node) {
    const uint8_t *start = node->base.location.start;
    const uint8_t *end = node->base.location.end - 1; // r

    while (start < end && *start == '0') start++; // 0.1 -> .1
    while (end > start && end[-1] == '0') end--; // 1.0 -> 1.
    size_t length = (size_t) (end - start);

    const uint8_t *point = memchr(start, '.', length);
    assert(point && "should have a decimal point");

    uint8_t *digits = malloc(length - 1);
    if (digits == NULL) return;

    memcpy(digits, start, (unsigned long) (point - start));
    memcpy(digits + (point - start), point + 1, (unsigned long) (end - point - 1));

    pm_integer_t numerator = { 0 };
    pm_integer_parse(&numerator, PM_INTEGER_BASE_DECIMAL, digits, digits + length - 1);

    pm_buffer_append_byte(buffer, '(');
    pm_integer_string(buffer, &numerator);
    pm_buffer_append_string(buffer, "/1", 2);
    for (size_t index = 0; index < (size_t) (end - point - 1); index++) pm_buffer_append_byte(buffer, '0');
    pm_buffer_append_byte(buffer, ')');

    pm_integer_free(&numerator);
    free(digits);
}

/**
 * Create a string-based representation of the given static literal.
 */
PRISM_EXPORTED_FUNCTION void
pm_static_literal_inspect(pm_buffer_t *buffer, const pm_parser_t *parser, const pm_node_t *node) {
    assert(PM_NODE_FLAG_P(node, PM_NODE_FLAG_STATIC_LITERAL));

    switch (PM_NODE_TYPE(node)) {
        case PM_FALSE_NODE:
            pm_buffer_append_string(buffer, "false", 5);
            break;
        case PM_FLOAT_NODE: {
            const double value = ((const pm_float_node_t *) node)->value;

            if (isinf(value)) {
                if (*node->location.start == '-') {
                    pm_buffer_append_byte(buffer, '-');
                }
                pm_buffer_append_string(buffer, "Infinity", 8);
            } else if (value == 0.0) {
                if (*node->location.start == '-') {
                    pm_buffer_append_byte(buffer, '-');
                }
                pm_buffer_append_string(buffer, "0.0", 3);
            } else {
                pm_buffer_append_format(buffer, "%g", value);

                // %g will not insert a .0 for 1e100 (we'll get back 1e+100). So
                // we check for the decimal point and add it in here if it's not
                // present.
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
            if (PM_NODE_TYPE_P(numeric, PM_RATIONAL_NODE)) pm_buffer_append_byte(buffer, '*');
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
            const pm_node_t *numeric = ((const pm_rational_node_t *) node)->numeric;

            switch (PM_NODE_TYPE(numeric)) {
                case PM_INTEGER_NODE:
                    pm_buffer_append_byte(buffer, '(');
                    pm_static_literal_inspect(buffer, parser, numeric);
                    pm_buffer_append_string(buffer, "/1)", 3);
                    break;
                case PM_FLOAT_NODE:
                    pm_rational_inspect(buffer, (pm_rational_node_t *) node);
                    break;
                default:
                    assert(false && "unreachable");
                    break;
            }

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
            pm_buffer_append_format(buffer, "%d", pm_newline_list_line_column(&parser->newline_list, node->location.start, parser->start_line).line);
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
