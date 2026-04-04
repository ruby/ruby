#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

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
void ruby_xfree_sized(void *ptr, size_t _oldsize) { free(ptr); }
void *ruby_xrealloc_sized(void *ptr, size_t newsiz, size_t _oldsiz) { return realloc(ptr, newsiz); }

#include "prism.h"

static void
print_error(const pm_diagnostic_t *diagnostic, void *data)
{
    const pm_parser_t *parser = (const pm_parser_t *) data;
    pm_location_t loc = pm_diagnostic_location(diagnostic);
    const pm_line_column_t line_column = pm_line_offset_list_line_column(pm_parser_line_offsets(parser), loc.start, pm_parser_start_line(parser));
    fprintf(stderr, "%" PRIi32 ":%" PRIu32 ":%s\n", line_column.line, line_column.column, pm_diagnostic_message(diagnostic));
}

int
main(int argc, const char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *filepath = argv[1];
    pm_source_init_result_t init_result;
    pm_source_t *source = pm_source_mapped_new(filepath, 0, &init_result);

    if (init_result != PM_SOURCE_INIT_SUCCESS)
    {
        fprintf(stderr, "unable to map file: %s\n", filepath);
        return EXIT_FAILURE;
    }

    pm_options_t *options = pm_options_new();
    pm_options_line_set(options, 1);
    pm_options_filepath_set(options, filepath);

    pm_arena_t *arena = pm_arena_new();
    pm_parser_t *parser = pm_parser_new(arena, pm_source_source(source), pm_source_length(source), options);

    pm_node_t *node = pm_parse(parser);
    int exit_status;

    if (pm_parser_errors_size(parser) > 0)
    {
        fprintf(stderr, "error parsing %s\n", filepath);
        pm_parser_errors_each(parser, print_error, parser);
        exit_status = EXIT_FAILURE;
    }
    else {
        pm_buffer_t *json = pm_buffer_new();
        pm_dump_json(json, parser, node);
        printf("%.*s\n", (int) pm_buffer_length(json), pm_buffer_value(json));
        pm_buffer_free(json);
        exit_status = EXIT_SUCCESS;
    }

    pm_parser_free(parser);
    pm_arena_free(arena);
    pm_source_free(source);
    pm_options_free(options);

    return exit_status;
}
