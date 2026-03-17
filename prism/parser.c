#include "prism/parser.h"

#include "prism/internal/encoding.h"

/**
 * Returns the name of the encoding that is being used to parse the source.
 */
const char *
pm_parser_encoding_name(const pm_parser_t *parser) {
    return parser->encoding->name;
}
