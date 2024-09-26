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

    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(&input), pm_string_length(&input), &options);

    pm_node_t *node = pm_parse(&parser);
    int exit_status;

    if (parser.error_list.size > 0) {
        fprintf(stderr, "error parsing %s\n", filepath);
        for (const pm_diagnostic_t *diagnostic = (const pm_diagnostic_t *) parser.error_list.head; diagnostic != NULL; diagnostic = (const pm_diagnostic_t *) diagnostic->node.next) {
            const pm_line_column_t line_column = pm_newline_list_line_column(&parser.newline_list, diagnostic->location.start, parser.start_line);
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

    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);
    pm_string_free(&input);
    pm_options_free(&options);

    return exit_status;
}
