#include "prism/static_literals.h"

/**
 * Insert a node into the given sorted list. This will return false if the node
 * was not already in the list, and true if it was.
 */
static pm_node_t *
pm_node_list_insert(const pm_parser_t *parser, pm_node_list_t *list, pm_node_t *node, int (*compare)(const pm_parser_t *parser, const pm_node_t *left, const pm_node_t *right)) {
    size_t low = 0;
    size_t high = list->size;

    while (low < high) {
        size_t mid = (low + high) / 2;
        int result = compare(parser, list->nodes[mid], node);

        // If we find a match, then replace the old node with the new one and
        // return the old one.
        if (result == 0) {
            pm_node_t *result = list->nodes[mid];
            list->nodes[mid] = node;
            return result;
        }

        if (result < 0) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    pm_node_list_grow(list);
    memmove(&list->nodes[low + 1], &list->nodes[low], (list->size - low) * sizeof(pm_node_t *));

    list->nodes[low] = node;
    list->size++;

    return NULL;
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
            if (integer->length > 0) return integer->negative ? INT64_MIN : INT64_MAX;

            int64_t value = (int64_t) integer->head.value;
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
            return pm_node_list_insert(parser, &literals->integer_nodes, node, pm_compare_integer_nodes);
        case PM_FLOAT_NODE:
            return pm_node_list_insert(parser, &literals->float_nodes, node, pm_compare_float_nodes);
        case PM_RATIONAL_NODE:
        case PM_IMAGINARY_NODE:
            return pm_node_list_insert(parser, &literals->rational_nodes, node, pm_compare_number_nodes);
        case PM_STRING_NODE:
        case PM_SOURCE_FILE_NODE:
            return pm_node_list_insert(parser, &literals->string_nodes, node, pm_compare_string_nodes);
        case PM_REGULAR_EXPRESSION_NODE:
            return pm_node_list_insert(parser, &literals->regexp_nodes, node, pm_compare_regular_expression_nodes);
        case PM_SYMBOL_NODE:
            return pm_node_list_insert(parser, &literals->symbol_nodes, node, pm_compare_string_nodes);
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
    pm_node_list_free(&literals->integer_nodes);
    pm_node_list_free(&literals->float_nodes);
    pm_node_list_free(&literals->rational_nodes);
    pm_node_list_free(&literals->imaginary_nodes);
    pm_node_list_free(&literals->string_nodes);
    pm_node_list_free(&literals->regexp_nodes);
    pm_node_list_free(&literals->symbol_nodes);
}
