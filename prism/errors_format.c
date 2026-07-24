#include "prism/errors_format.h"

#include "prism/internal/allocator.h"
#include "prism/internal/buffer.h"
#include "prism/internal/diagnostic.h"
#include "prism/internal/encoding.h"
#include "prism/internal/line_offset_list.h"
#include "prism/internal/parser.h"

#include <assert.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/**
 * Check if the source touched by the given location is valid UTF-8. The
 * location represents the location of the error, but the slice of the source
 * that will be displayed includes the content of all of the lines that the
 * error touches, so we need to check those parts as well.
 */
static bool
location_is_utf8(const pm_parser_t *parser, const pm_location_t *location) {
    const pm_line_offset_list_t *line_offsets = &parser->line_offsets;
    const size_t start_line = (size_t) pm_line_offset_list_line_column(line_offsets, location->start, 1).line;
    const size_t end_line = (size_t) pm_line_offset_list_line_column(line_offsets, location->start + location->length, 1).line;

    const uint8_t *cursor = parser->start + line_offsets->offsets[start_line - 1];
    const uint8_t *end = (end_line == line_offsets->size) ? parser->end : (parser->start + line_offsets->offsets[end_line]);

    while (cursor < end) {
        size_t width = pm_encoding_utf_8_char_width(cursor, end - cursor);
        if (width == 0) return false;

        cursor += width;
    }

    return true;
}

typedef struct {
    pm_diagnostic_t *diagnostic;
    int32_t line;
    uint32_t column_start;
    uint32_t column_end;
    size_t idx;
} pm_rich_error_t;

static int
pm_rich_error_compare(const void *a, const void *b) {
    const pm_rich_error_t *left = (const pm_rich_error_t *) a;
    const pm_rich_error_t *right = (const pm_rich_error_t *) b;

    if (left->line != right->line) {
        return (left->line < right->line) ? -1 : 1;
    }

    if (left->column_start != right->column_start) {
        return (left->column_start < right->column_start) ? -1 : 1;
    }

    if (left->idx != right->idx) {
        return (left->idx < right->idx) ? 1 : -1;
    }

    return 0;
}

#define COLOR_BOLD "\033[1m"
#define COLOR_GRAY "\033[2m"
#define COLOR_RED "\033[1;31m"
#define COLOR_RESET "\033[m"
#define TRUNCATE 30

typedef struct {
    const char *number_prefix;
    const char *blank_prefix;
    const char *divider;
    size_t blank_prefix_length;
    size_t divider_length;
} pm_error_line_format_t;

/**
 * Initialize the given line format struct based on whether or not to highlight
 * the line and the first and last line numbers.
 */
static void
pm_error_line_format_init(pm_error_line_format_t *format, pm_errors_format_type_t format_type, int32_t first_line, int32_t last_line) {
    /* If we have a maximum line number that is negative, then we are going to
     * use the absolute value for comparison but multiply by 10 to additionally
     * have a column for the negative sign. */
    if (first_line < 0) first_line = (-first_line) * 10;
    if (last_line < 0) last_line = (-last_line) * 10;
    int32_t max_line = first_line > last_line ? first_line : last_line;

    if (max_line < 10) {
        if (format_type > PM_ERRORS_FORMAT_PLAIN) {
            *format = (pm_error_line_format_t) {
                .number_prefix = COLOR_GRAY "%1" PRIi32 " | " COLOR_RESET,
                .blank_prefix = COLOR_GRAY "  | " COLOR_RESET,
                .divider = COLOR_GRAY "  ~~~~~" COLOR_RESET "\n"
            };
        } else {
            *format = (pm_error_line_format_t) {
                .number_prefix = "%1" PRIi32 " | ",
                .blank_prefix = "  | ",
                .divider = "  ~~~~~\n"
            };
        }
    } else if (max_line < 100) {
        if (format_type > PM_ERRORS_FORMAT_PLAIN) {
            *format = (pm_error_line_format_t) {
                .number_prefix = COLOR_GRAY "%2" PRIi32 " | " COLOR_RESET,
                .blank_prefix = COLOR_GRAY "   | " COLOR_RESET,
                .divider = COLOR_GRAY "  ~~~~~~" COLOR_RESET "\n"
            };
        } else {
            *format = (pm_error_line_format_t) {
                .number_prefix = "%2" PRIi32 " | ",
                .blank_prefix = "   | ",
                .divider = "  ~~~~~~\n"
            };
        }
    } else if (max_line < 1000) {
        if (format_type > PM_ERRORS_FORMAT_PLAIN) {
            *format = (pm_error_line_format_t) {
                .number_prefix = COLOR_GRAY "%3" PRIi32 " | " COLOR_RESET,
                .blank_prefix = COLOR_GRAY "    | " COLOR_RESET,
                .divider = COLOR_GRAY "  ~~~~~~~" COLOR_RESET "\n"
            };
        } else {
            *format = (pm_error_line_format_t) {
                .number_prefix = "%3" PRIi32 " | ",
                .blank_prefix = "    | ",
                .divider = "  ~~~~~~~\n"
            };
        }
    } else if (max_line < 10000) {
        if (format_type > PM_ERRORS_FORMAT_PLAIN) {
            *format = (pm_error_line_format_t) {
                .number_prefix = COLOR_GRAY "%4" PRIi32 " | " COLOR_RESET,
                .blank_prefix = COLOR_GRAY "     | " COLOR_RESET,
                .divider = COLOR_GRAY "  ~~~~~~~~" COLOR_RESET "\n"
            };
        } else {
            *format = (pm_error_line_format_t) {
                .number_prefix = "%4" PRIi32 " | ",
                .blank_prefix = "     | ",
                .divider = "  ~~~~~~~~\n"
            };
        }
    } else {
        if (format_type > PM_ERRORS_FORMAT_PLAIN) {
            *format = (pm_error_line_format_t) {
                .number_prefix = COLOR_GRAY "%5" PRIi32 " | " COLOR_RESET,
                .blank_prefix = COLOR_GRAY "      | " COLOR_RESET,
                .divider = COLOR_GRAY "  ~~~~~~~~" COLOR_RESET "\n"
            };
        } else {
            *format = (pm_error_line_format_t) {
                .number_prefix = "%5" PRIi32 " | ",
                .blank_prefix = "      | ",
                .divider = "  ~~~~~~~~\n"
            };
        }
    }

    format->blank_prefix_length = strlen(format->blank_prefix);
    format->divider_length = strlen(format->divider);
}

static void
pm_error_format_line(const pm_parser_t *parser, pm_buffer_t *buffer, const char *number_prefix, int32_t line, uint32_t column_start, uint32_t column_end) {
    int32_t line_delta = line - parser->start_line;
    assert(line_delta >= 0);

    size_t index = (size_t) line_delta;
    assert(index < parser->line_offsets.size);

    const uint8_t *start = parser->start + parser->line_offsets.offsets[index];
    const uint8_t *end;

    if (index >= parser->line_offsets.size - 1) {
        end = parser->end;
    } else {
        end = parser->start + parser->line_offsets.offsets[index + 1];
    }

    pm_buffer_append_format(buffer, number_prefix, line);

    /* Here we determine if we should truncate the end of the line. Note that
     * this is written to avoid computing start + column_end, which could be
     * more than one past the end of the source when the error is at the end
     * of the input. */
    bool truncate_end = false;
    if ((column_end != 0) && ((end - start) - ((ptrdiff_t) column_end) >= TRUNCATE)) {
        const uint8_t *end_candidate = start + column_end + TRUNCATE;

        for (const uint8_t *cursor = start; cursor < end_candidate;) {
            size_t char_width = pm_parser_encoding_char_width(parser, cursor, parser->end - cursor);

            /* If we failed to decode a character, then just bail out and
             * truncate at the fixed width. */
            if (char_width == 0) break;

            /* If this next character would go past the end candidate,
             * then we need to truncate before it. */
            if (cursor + char_width > end_candidate) {
                end_candidate = cursor;
                break;
            }

            cursor += char_width;
        }

        end = end_candidate;
        truncate_end = true;
    }

    /* Here we determine if we should truncate the start of the line. */
    if (column_start >= TRUNCATE) {
        pm_buffer_append_string(buffer, "... ", 4);
        start += column_start;
    }

    pm_buffer_append_string(buffer, (const char *) start, (size_t) (end - start));

    if (truncate_end) {
        pm_buffer_append_string(buffer, " ...\n", 5);
    } else if (end == parser->end && end > parser->start && end[-1] != '\n') {
        pm_buffer_append_byte(buffer, '\n');
    }
}

static void
pm_rich_errors_format(const pm_parser_t *parser, pm_buffer_t *buffer, pm_errors_format_type_t format_type, size_t nerrors, pm_rich_error_t *rich_errors, bool inline_messages) {
    pm_error_line_format_t format;
    pm_error_line_format_init(&format, format_type, rich_errors[0].line, rich_errors[nerrors - 1].line);

    /* We are going to iterate through every error in our error list and display
     * it. While we are iterating, we will display some padding lines of the
     * source before the error to give some context. We will be careful not to
     * display the same line twice in case the errors are close enough in the
     * source. */
    int32_t last_line = parser->start_line - 1;
    uint32_t last_column_start = 0;

    for (size_t idx = 0; idx < nerrors; idx++) {
        pm_rich_error_t *rich_error = rich_errors + idx;

        /* Here we determine how many lines of padding of the source to display,
         * based on the difference from the last line that was displayed. */
        if (rich_error->line - last_line > 1) {
            if (rich_error->line - last_line > 2) {
                if ((idx != 0) && (rich_error->line - last_line > 3)) {
                    pm_buffer_append_string(buffer, format.divider, format.divider_length);
                }

                pm_buffer_append_string(buffer, "  ", 2);
                pm_error_format_line(parser, buffer, format.number_prefix, rich_error->line - 2, 0, 0);
            }

            pm_buffer_append_string(buffer, "  ", 2);
            pm_error_format_line(parser, buffer, format.number_prefix, rich_error->line - 1, 0, 0);
        }

        /* If this is the first error or we are on a new line, then we will
         * display the line that has the error in it. */
        if ((idx == 0) || (rich_error->line != last_line)) {
            switch (format_type) {
                case PM_ERRORS_FORMAT_PLAIN:
                    pm_buffer_append_string(buffer, "> ", 2);
                    break;
                case PM_ERRORS_FORMAT_STYLE:
                    pm_buffer_append_format(buffer, "%s", COLOR_BOLD "> " COLOR_RESET);
                    break;
                case PM_ERRORS_FORMAT_COLOR:
                    pm_buffer_append_format(buffer, "%s", COLOR_RED "> " COLOR_RESET);
                    break;
            }

            last_column_start = rich_error->column_start;

            /* Find the maximum column end of all the errors on this line. */
            uint32_t column_end = rich_error->column_end;
            for (size_t next_idx = idx + 1; next_idx < nerrors; next_idx++) {
                if (rich_errors[next_idx].line != rich_error->line) break;
                if (rich_errors[next_idx].column_end > column_end) column_end = rich_errors[next_idx].column_end;
            }

            pm_error_format_line(parser, buffer, format.number_prefix, rich_error->line, rich_error->column_start, column_end);
        }

        const uint8_t *start = parser->start + parser->line_offsets.offsets[rich_error->line - parser->start_line];
        if (start == parser->end) pm_buffer_append_byte(buffer, '\n');

        /* Now we will display the actual error message. We will do this by
         * first putting the prefix to the line, then a bunch of blank spaces
         * depending on the column, then as many tildes as we need to display
         * the width of the error, then the error message itself.
         *
         * Note that this doesn't take into account the width of the actual
         * character when displayed in the terminal. For some east-asian
         * languages or emoji, this means it can be thrown off pretty badly. We
         * will need to solve this eventually. */
        pm_buffer_append_string(buffer, "  ", 2);
        pm_buffer_append_string(buffer, format.blank_prefix, format.blank_prefix_length);

        size_t column = 0;
        if (last_column_start >= TRUNCATE) {
            pm_buffer_append_string(buffer, "    ", 4);
            column = last_column_start;
        }

        while (column < rich_error->column_start) {
            pm_buffer_append_byte(buffer, ' ');

            size_t char_width = pm_parser_encoding_char_width(parser, start + column, parser->end - (start + column));
            column += (char_width == 0 ? 1 : char_width);
        }

        switch (format_type) {
            case PM_ERRORS_FORMAT_PLAIN:
                pm_buffer_append_byte(buffer, '^');
                break;
            case PM_ERRORS_FORMAT_STYLE:
                pm_buffer_append_format(buffer, "%s^", COLOR_BOLD);
                break;
            case PM_ERRORS_FORMAT_COLOR:
                pm_buffer_append_format(buffer, "%s^", COLOR_RED);
                break;
        }

        size_t char_width = pm_parser_encoding_char_width(parser, start + column, parser->end - (start + column));
        column += (char_width == 0 ? 1 : char_width);

        while (column < rich_error->column_end) {
            pm_buffer_append_byte(buffer, '~');

            size_t char_width = pm_parser_encoding_char_width(parser, start + column, parser->end - (start + column));
            column += (char_width == 0 ? 1 : char_width);
        }

        if (format_type != PM_ERRORS_FORMAT_PLAIN) {
            pm_buffer_append_format(buffer, "%s", COLOR_RESET);
        }

        if (inline_messages) {
            const char *message = pm_diagnostic_message(rich_error->diagnostic);

            pm_buffer_append_byte(buffer, ' ');
            pm_buffer_append_string(buffer, message, strlen(message));
        }

        pm_buffer_append_byte(buffer, '\n');

        /* Here we determine how many lines of padding to display after the
         * diagnostic, depending on where the next diagnostic is in source. */
        last_line = rich_error->line;
        int32_t next_line;

        if (idx == nerrors - 1) {
            next_line = ((int32_t) parser->line_offsets.size) + parser->start_line;

            /* If the file ends with a newline, subtract one from our
             * "next_line" so that we do not output an extra line at the end of
             * the file. */
            if ((parser->start + parser->line_offsets.offsets[parser->line_offsets.size - 1]) == parser->end) {
                next_line--;
            }
        } else {
            next_line = rich_errors[idx + 1].line;
        }

        if (next_line - last_line > 1) {
            pm_buffer_append_string(buffer, "  ", 2);
            pm_error_format_line(parser, buffer, format.number_prefix, ++last_line, 0, 0);
        }

        if (next_line - last_line > 1) {
            pm_buffer_append_string(buffer, "  ", 2);
            pm_error_format_line(parser, buffer, format.number_prefix, ++last_line, 0, 0);
        }
    }
}

static void
pm_rich_error_init(const pm_parser_t *parser, pm_rich_error_t *rich_error, pm_diagnostic_t *diagnostic, pm_location_t *location) {
    const pm_line_offset_list_t *line_offsets = &parser->line_offsets;
    pm_line_column_t start_line_column = pm_line_offset_list_line_column(line_offsets, location->start, parser->start_line);
    pm_line_column_t end_line_column = pm_line_offset_list_line_column(line_offsets, location->start + location->length, parser->start_line);

    uint32_t column_end;
    if (start_line_column.line == end_line_column.line) {
        column_end = end_line_column.column;
    } else {
        column_end = (uint32_t) (line_offsets->offsets[start_line_column.line - parser->start_line + 1] - line_offsets->offsets[start_line_column.line - parser->start_line] - 1);
    }

    /* Ensure we have at least one column of error. */
    if (start_line_column.column == column_end) column_end++;

    *rich_error = (pm_rich_error_t) {
        .diagnostic = diagnostic,
        .line = start_line_column.line,
        .column_start = start_line_column.column,
        .column_end = column_end
    };
}

pm_error_level_t
pm_errors_format(const pm_parser_t *parser, pm_buffer_t *buffer, pm_errors_format_type_t format_type) {
    size_t nerrors = parser->error_list.size;
    assert(nerrors > 0);

    int filepath_length = (int) pm_string_length(&parser->filepath);
    const char *filepath = (const char *) pm_string_source(&parser->filepath);

    size_t rich_errors_size = nerrors * sizeof(pm_rich_error_t);
    if (rich_errors_size / sizeof(pm_rich_error_t) != nerrors) abort();

    pm_rich_error_t *rich_errors = xmalloc(rich_errors_size);
    if (rich_errors == NULL) abort();

    bool is_utf8 = true;
    size_t rich_errors_idx = 0;

    for (pm_diagnostic_t *diagnostic = (pm_diagnostic_t *) parser->error_list.head; diagnostic != NULL; diagnostic = (pm_diagnostic_t *) diagnostic->node.next) {
        pm_location_t location = pm_diagnostic_location(diagnostic);

        switch (pm_diagnostic_error_level(diagnostic)) {
          case PM_ERROR_LEVEL_SYNTAX: {
            if (is_utf8 && !location_is_utf8(parser, &location)) {
                is_utf8 = false;
            }

            pm_rich_error_init(parser, &rich_errors[rich_errors_idx], diagnostic, &location);
            rich_errors[rich_errors_idx].idx = rich_errors_idx;
            rich_errors_idx++;
            break;
          }
          case PM_ERROR_LEVEL_ARGUMENT: {
            /* If we get an argument error, we want to format it and return it
             * immediately. They should include a snippet of the source if
             * possible. */
            pm_buffer_append_format(
                buffer,
                "%.*s:%" PRIi32 ": %s",
                filepath_length,
                filepath,
                pm_line_offset_list_line(&parser->line_offsets, location.start, parser->start_line),
                pm_diagnostic_message(diagnostic)
            );

            if (location_is_utf8(parser, &location)) {
                pm_buffer_append_byte(buffer, '\n');
                pm_rich_error_init(parser, rich_errors, diagnostic, &location);
                pm_rich_errors_format(parser, buffer, format_type, 1, rich_errors, false);
            }

            xfree_sized(rich_errors, rich_errors_size);
            return PM_ERROR_LEVEL_ARGUMENT;
          }
          case PM_ERROR_LEVEL_LOAD: {
            /* If we get a load error, we want to format it and return it
             * immediately. It should only include the diagnostic message. */
            const char *message = pm_diagnostic_message(diagnostic);
            pm_buffer_append_string(buffer, message, strlen(message));

            xfree_sized(rich_errors, rich_errors_size);
            return PM_ERROR_LEVEL_LOAD;
          }
        }
    }

    assert(rich_errors_idx == nerrors);

    /* The header displays the line of the first error in parse order, which
     * is the first entry in the array because it has not been sorted yet. */
    pm_buffer_append_format(
        buffer,
        "%.*s:%" PRIi32 ": syntax error%s found\n",
        filepath_length,
        filepath,
        rich_errors[0].line,
        (nerrors > 1) ? "s" : ""
    );

    if (is_utf8) {
        /* In here, we have all of the rich diagnostic information and we know
         * the snippets are valid UTF-8. We will sort the errors so that they
         * are displayed in the order that they appear in the source, and then
         * format them all together with the source code snippets. */
        qsort(rich_errors, nerrors, sizeof(pm_rich_error_t), pm_rich_error_compare);
        pm_rich_errors_format(parser, buffer, format_type, nerrors, rich_errors, true);
    } else {
        /* In here, we have content in the source that is not valid UTF-8. In
         * that case, we do not want to attempt to format the source code
         * snippets because we do not know how the terminal will handle it. The
         * diagnostics are displayed in the order that they were generated,
         * which is the order of the array before it has been sorted. */
        for (size_t idx = 0; idx < nerrors; idx++) {
            pm_rich_error_t *rich_error = &rich_errors[idx];

            if (idx > 0) pm_buffer_append_byte(buffer, '\n');
            pm_buffer_append_format(
                buffer,
                "%.*s:%" PRIi32 ": %s",
                filepath_length,
                filepath,
                rich_error->line,
                pm_diagnostic_message(rich_error->diagnostic)
            );
        }
    }

    xfree_sized(rich_errors, rich_errors_size);
    return PM_ERROR_LEVEL_SYNTAX;
}
