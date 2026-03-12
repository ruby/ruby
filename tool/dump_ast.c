#include <stdlib.h>
#include <string.h>

/*
 * When prism is compiled as part of CRuby, the xmalloc/xfree/etc. macros are
 * redirected to ruby_xmalloc/ruby_xfree/etc. Since this is a standalone
 * program that links against those same object files, we need to provide
 * implementations of these functions.
 */
void *ruby_xmalloc(size_t size) { return malloc(size); }
void *ruby_xcalloc(size_t nelems, size_t elemsiz) { return calloc(nelems, elemsiz); }
void *ruby_xrealloc(void *ptr, size_t newsiz) { return realloc(ptr, newsiz); }
void ruby_xfree(void *ptr) { free(ptr); }

#include "prism.h"

int
main(int argc, const char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *filepath = argv[1];
    pm_string_t input;

    if (pm_string_mapped_init(&input, filepath) != PM_STRING_INIT_SUCCESS) {
        fprintf(stderr, "unable to map file: %s\n", filepath);
        return EXIT_FAILURE;
    }

    pm_options_t options = { 0 };
    pm_options_line_set(&options, 1);
    pm_options_filepath_set(&options, filepath);

    pm_arena_t arena = { 0 };
    pm_parser_t parser;
    pm_parser_init(&arena, &parser, pm_string_source(&input), pm_string_length(&input), &options);

    pm_node_t *node = pm_parse(&parser);
    int exit_status;

    if (parser.error_list.size > 0) {
        fprintf(stderr, "error parsing %s\n", filepath);
        for (const pm_diagnostic_t *diagnostic = (const pm_diagnostic_t *) parser.error_list.head; diagnostic != NULL; diagnostic = (const pm_diagnostic_t *) diagnostic->node.next) {
            const pm_line_column_t line_column = pm_line_offset_list_line_column(&parser.line_offsets, diagnostic->location.start, parser.start_line);
            fprintf(stderr, "%" PRIi32 ":%" PRIu32 ":%s\n", line_column.line, line_column.column, diagnostic->message);
        }
        exit_status = EXIT_FAILURE;
    } else {
        pm_buffer_t json = { 0 };
        pm_dump_json(&json, &parser, node);
        printf("%.*s\n", (int) pm_buffer_length(&json), pm_buffer_value(&json));
        pm_buffer_free(&json);
        exit_status = EXIT_SUCCESS;
    }

    pm_parser_free(&parser);
    pm_arena_free(&arena);
    pm_string_free(&input);
    pm_options_free(&options);

    return exit_status;
}
