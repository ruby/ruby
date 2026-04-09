#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include "revision.h"

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

#if defined(RUBY_RELEASE_DATETIME) && defined(RUBY_RELEASE_DATETIME)
# define SHOW_PROGRAM_VERSION 2
#elif defined(RUBY_RELEASE_DATETIME) || defined(RUBY_RELEASE_DATETIME)
# define SHOW_PROGRAM_VERSION 1
#else
# define SHOW_PROGRAM_VERSION 0
#endif
#if SHOW_PROGRAM_VERSION
# define usage_versions "and program versions"
#else
# define usage_versions "version"
#endif

static void
usage(const char *prog)
{
    fprintf(stderr, "Usage: %s [options]... <filename>\n"
            "Options:\n"
            "  -v, --version: show Prism " usage_versions "\n"
            "  -h, --help: show this message\n"
            "", prog);
}

int
main(int argc, const char *argv[])
{
    const char *filepath = 0;

    for (int i = 1; i < argc; ++i) {
        const char *arg = argv[i];
        if (arg[0] != '-') {
            if (filepath) {
                fprintf(stderr, "too many filename\n");
                goto usage;
            }
            filepath = arg;
        }
        else if (arg[1] == '-') {
            if (!arg[2]) break;
            if (strcmp(arg + 2, "version") == 0) {
              version:
                fputs("Prism " PRISM_VERSION
#if SHOW_PROGRAM_VERSION
                      " ["
# ifdef RUBY_RELEASE_DATETIME
                      RUBY_RELEASE_DATETIME
# endif
# if SHOW_PROGRAM_VERSION > 1
                      " "
# endif
# ifdef RUBY_REVISION
                      RUBY_REVISION
# endif
                      "]"
#endif
                      "\n", stdout);
                return EXIT_SUCCESS;
            }
            if (strcmp(arg + 2, "help") == 0) {
              help:
                usage(argv[0]);
                return EXIT_SUCCESS;
            }
            fprintf(stderr, "unknown option %s\n", arg);
            goto usage;
        }
        else {
            while (*++arg) {
                switch (*arg) {
                  case 'v':
                    goto version;
                  case 'h':
                    goto help;
                  default:
                    fprintf(stderr, "unknown option -%c\n", *arg);
                    goto usage;
                }
            }
        }
    }

    if (!filepath) {
      usage:
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    pm_source_init_result_t init_result;
    pm_source_t *source = pm_source_mapped_new(filepath, 0, &init_result);

    if (init_result != PM_SOURCE_INIT_SUCCESS) {
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
