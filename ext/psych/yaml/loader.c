
#include "yaml_private.h"

/*
 * API functions.
 */

YAML_DECLARE(int)
yaml_parser_load(yaml_parser_t *parser, yaml_document_t *document);

/*
 * Error handling.
 */

static int
yaml_parser_set_composer_error(yaml_parser_t *parser,
        const char *problem, yaml_mark_t problem_mark);

static int
yaml_parser_set_composer_error_context(yaml_parser_t *parser,
        const char *context, yaml_mark_t context_mark,
        const char *problem, yaml_mark_t problem_mark);


/*
 * Alias handling.
 */

static int
yaml_parser_register_anchor(yaml_parser_t *parser,
        int index, yaml_char_t *anchor);

/*
 * Clean up functions.
 */

static void
yaml_parser_delete_aliases(yaml_parser_t *parser);

/*
 * Composer functions.
 */

static int
yaml_parser_load_document(yaml_parser_t *parser, yaml_event_t *first_event);

static int
yaml_parser_load_node(yaml_parser_t *parser, yaml_event_t *first_event);

static int
yaml_parser_load_alias(yaml_parser_t *parser, yaml_event_t *first_event);

static int
yaml_parser_load_scalar(yaml_parser_t *parser, yaml_event_t *first_event);

static int
yaml_parser_load_sequence(yaml_parser_t *parser, yaml_event_t *first_event);

static int
yaml_parser_load_mapping(yaml_parser_t *parser, yaml_event_t *first_event);

/*
 * Load the next document of the stream.
 */

YAML_DECLARE(int)
yaml_parser_load(yaml_parser_t *parser, yaml_document_t *document)
{
    yaml_event_t event;

    assert(parser);     /* Non-NULL parser object is expected. */
    assert(document);   /* Non-NULL document object is expected. */

    memset(document, 0, sizeof(yaml_document_t));
    if (!STACK_INIT(parser, document->nodes, yaml_node_t*))
        goto error;

    if (!parser->stream_start_produced) {
        if (!yaml_parser_parse(parser, &event)) goto error;
        assert(event.type == YAML_STREAM_START_EVENT);
                        /* STREAM-START is expected. */
    }

    if (parser->stream_end_produced) {
        return 1;
    }

    if (!yaml_parser_parse(parser, &event)) goto error;
    if (event.type == YAML_STREAM_END_EVENT) {
        return 1;
    }

    if (!STACK_INIT(parser, parser->aliases, yaml_alias_data_t*))
        goto error;

    parser->document = document;

    if (!yaml_parser_load_document(parser, &event)) goto error;

    yaml_parser_delete_aliases(parser);
    parser->document = NULL;

    return 1;

error:

    yaml_parser_delete_aliases(parser);
    yaml_document_delete(document);
    parser->document = NULL;

    return 0;
}

/*
 * Set composer error.
 */

static int
yaml_parser_set_composer_error(yaml_parser_t *parser,
        const char *problem, yaml_mark_t problem_mark)
{
    parser->error = YAML_COMPOSER_ERROR;
    parser->problem = problem;
    parser->problem_mark = problem_mark;

    return 0;
}

/*
 * Set composer error with context.
 */

static int
yaml_parser_set_composer_error_context(yaml_parser_t *parser,
        const char *context, yaml_mark_t context_mark,
        const char *problem, yaml_mark_t problem_mark)
{
    parser->error = YAML_COMPOSER_ERROR;
    parser->context = context;
    parser->context_mark = context_mark;
    parser->problem = problem;
    parser->problem_mark = problem_mark;

    return 0;
}

/*
 * Delete the stack of aliases.
 */

static void
yaml_parser_delete_aliases(yaml_parser_t *parser)
{
    while (!STACK_EMPTY(parser, parser->aliases)) {
        yaml_free(POP(parser, parser->aliases).anchor);
    }
    STACK_DEL(parser, parser->aliases);
}

/*
 * Compose a document object.
 */

static int
yaml_parser_load_document(yaml_parser_t *parser, yaml_event_t *first_event)
{
    yaml_event_t event;

    assert(first_event->type == YAML_DOCUMENT_START_EVENT);
                        /* DOCUMENT-START is expected. */

    parser->document->version_directive
        = first_event->data.document_start.version_directive;
    parser->document->tag_directives.start
        = first_event->data.document_start.tag_directives.start;
    parser->document->tag_directives.end
        = first_event->data.document_start.tag_directives.end;
    parser->document->start_implicit
        = first_event->data.document_start.implicit;
    parser->document->start_mark = first_event->start_mark;

    if (!yaml_parser_parse(parser, &event)) return 0;

    if (!yaml_parser_load_node(parser, &event)) return 0;

    if (!yaml_parser_parse(parser, &event)) return 0;
    assert(event.type == YAML_DOCUMENT_END_EVENT);
                        /* DOCUMENT-END is expected. */

    parser->document->end_implicit = event.data.document_end.implicit;
    parser->document->end_mark = event.end_mark;

    return 1;
}

/*
 * Compose a node.
 */

static int
yaml_parser_load_node(yaml_parser_t *parser, yaml_event_t *first_event)
{
    switch (first_event->type) {
        case YAML_ALIAS_EVENT:
            return yaml_parser_load_alias(parser, first_event);
        case YAML_SCALAR_EVENT:
            return yaml_parser_load_scalar(parser, first_event);
        case YAML_SEQUENCE_START_EVENT:
            return yaml_parser_load_sequence(parser, first_event);
        case YAML_MAPPING_START_EVENT:
            return yaml_parser_load_mapping(parser, first_event);
        default:
            assert(0);  /* Could not happen. */
            return 0;
    }

    return 0;
}

/*
 * Add an anchor.
 */

static int
yaml_parser_register_anchor(yaml_parser_t *parser,
        int index, yaml_char_t *anchor)
{
    yaml_alias_data_t data;
    yaml_alias_data_t *alias_data;

    if (!anchor) return 1;

    data.anchor = anchor;
    data.index = index;
    data.mark = parser->document->nodes.start[index-1].start_mark;

    for (alias_data = parser->aliases.start;
            alias_data != parser->aliases.top; alias_data ++) {
        if (strcmp((char *)alias_data->anchor, (char *)anchor) == 0) {
            yaml_free(anchor);
            return yaml_parser_set_composer_error_context(parser,
                    "found duplicate anchor; first occurrence",
                    alias_data->mark, "second occurrence", data.mark);
        }
    }

    if (!PUSH(parser, parser->aliases, data)) {
        yaml_free(anchor);
        return 0;
    }

    return 1;
}

/*
 * Compose a node corresponding to an alias.
 */

static int
yaml_parser_load_alias(yaml_parser_t *parser, yaml_event_t *first_event)
{
    yaml_char_t *anchor = first_event->data.alias.anchor;
    yaml_alias_data_t *alias_data;

    for (alias_data = parser->aliases.start;
            alias_data != parser->aliases.top; alias_data ++) {
        if (strcmp((char *)alias_data->anchor, (char *)anchor) == 0) {
            yaml_free(anchor);
            return alias_data->index;
        }
    }

    yaml_free(anchor);
    return yaml_parser_set_composer_error(parser, "found undefined alias",
            first_event->start_mark);
}

/*
 * Compose a scalar node.
 */

static int
yaml_parser_load_scalar(yaml_parser_t *parser, yaml_event_t *first_event)
{
    yaml_node_t node;
    int index;
    yaml_char_t *tag = first_event->data.scalar.tag;

    if (!STACK_LIMIT(parser, parser->document->nodes, INT_MAX-1)) goto error;

    if (!tag || strcmp((char *)tag, "!") == 0) {
        yaml_free(tag);
        tag = yaml_strdup((yaml_char_t *)YAML_DEFAULT_SCALAR_TAG);
        if (!tag) goto error;
    }

    SCALAR_NODE_INIT(node, tag, first_event->data.scalar.value,
            first_event->data.scalar.length, first_event->data.scalar.style,
            first_event->start_mark, first_event->end_mark);

    if (!PUSH(parser, parser->document->nodes, node)) goto error;

    index = parser->document->nodes.top - parser->document->nodes.start;

    if (!yaml_parser_register_anchor(parser, index,
                first_event->data.scalar.anchor)) return 0;

    return index;

error:
    yaml_free(tag);
    yaml_free(first_event->data.scalar.anchor);
    yaml_free(first_event->data.scalar.value);
    return 0;
}

/*
 * Compose a sequence node.
 */

static int
yaml_parser_load_sequence(yaml_parser_t *parser, yaml_event_t *first_event)
{
    yaml_event_t event;
    yaml_node_t node;
    struct {
        yaml_node_item_t *start;
        yaml_node_item_t *end;
        yaml_node_item_t *top;
    } items = { NULL, NULL, NULL };
    int index, item_index;
    yaml_char_t *tag = first_event->data.sequence_start.tag;

    if (!STACK_LIMIT(parser, parser->document->nodes, INT_MAX-1)) goto error;

    if (!tag || strcmp((char *)tag, "!") == 0) {
        yaml_free(tag);
        tag = yaml_strdup((yaml_char_t *)YAML_DEFAULT_SEQUENCE_TAG);
        if (!tag) goto error;
    }

    if (!STACK_INIT(parser, items, yaml_node_item_t*)) goto error;

    SEQUENCE_NODE_INIT(node, tag, items.start, items.end,
            first_event->data.sequence_start.style,
            first_event->start_mark, first_event->end_mark);

    if (!PUSH(parser, parser->document->nodes, node)) goto error;

    index = parser->document->nodes.top - parser->document->nodes.start;

    if (!yaml_parser_register_anchor(parser, index,
                first_event->data.sequence_start.anchor)) return 0;

    if (!yaml_parser_parse(parser, &event)) return 0;

    while (event.type != YAML_SEQUENCE_END_EVENT) {
        if (!STACK_LIMIT(parser,
                    parser->document->nodes.start[index-1].data.sequence.items,
                    INT_MAX-1)) return 0;
        item_index = yaml_parser_load_node(parser, &event);
        if (!item_index) return 0;
        if (!PUSH(parser,
                    parser->document->nodes.start[index-1].data.sequence.items,
                    item_index)) return 0;
        if (!yaml_parser_parse(parser, &event)) return 0;
    }

    parser->document->nodes.start[index-1].end_mark = event.end_mark;

    return index;

error:
    yaml_free(tag);
    yaml_free(first_event->data.sequence_start.anchor);
    return 0;
}

/*
 * Compose a mapping node.
 */

static int
yaml_parser_load_mapping(yaml_parser_t *parser, yaml_event_t *first_event)
{
    yaml_event_t event;
    yaml_node_t node;
    struct {
        yaml_node_pair_t *start;
        yaml_node_pair_t *end;
        yaml_node_pair_t *top;
    } pairs = { NULL, NULL, NULL };
    int index;
    yaml_node_pair_t pair;
    yaml_char_t *tag = first_event->data.mapping_start.tag;

    if (!STACK_LIMIT(parser, parser->document->nodes, INT_MAX-1)) goto error;

    if (!tag || strcmp((char *)tag, "!") == 0) {
        yaml_free(tag);
        tag = yaml_strdup((yaml_char_t *)YAML_DEFAULT_MAPPING_TAG);
        if (!tag) goto error;
    }

    if (!STACK_INIT(parser, pairs, yaml_node_pair_t*)) goto error;

    MAPPING_NODE_INIT(node, tag, pairs.start, pairs.end,
            first_event->data.mapping_start.style,
            first_event->start_mark, first_event->end_mark);

    if (!PUSH(parser, parser->document->nodes, node)) goto error;

    index = parser->document->nodes.top - parser->document->nodes.start;

    if (!yaml_parser_register_anchor(parser, index,
                first_event->data.mapping_start.anchor)) return 0;

    if (!yaml_parser_parse(parser, &event)) return 0;

    while (event.type != YAML_MAPPING_END_EVENT) {
        if (!STACK_LIMIT(parser,
                    parser->document->nodes.start[index-1].data.mapping.pairs,
                    INT_MAX-1)) return 0;
        pair.key = yaml_parser_load_node(parser, &event);
        if (!pair.key) return 0;
        if (!yaml_parser_parse(parser, &event)) return 0;
        pair.value = yaml_parser_load_node(parser, &event);
        if (!pair.value) return 0;
        if (!PUSH(parser,
                    parser->document->nodes.start[index-1].data.mapping.pairs,
                    pair)) return 0;
        if (!yaml_parser_parse(parser, &event)) return 0;
    }

    parser->document->nodes.start[index-1].end_mark = event.end_mark;

    return index;

error:
    yaml_free(tag);
    yaml_free(first_event->data.mapping_start.anchor);
    return 0;
}

