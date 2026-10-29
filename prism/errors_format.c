#include "prism/errors_format.h"

#include "prism/internal/allocator.h"
#include "prism/internal/buffer.h"
#include "prism/internal/diagnostic.h"
#include "prism/internal/encoding.h"
#include "prism/internal/line_offset_list.h"
#include "prism/internal/oom.h"
#include "prism/internal/parser.h"

#include <assert.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/**
 * Check if the source in the given range of lines is valid UTF-8. The indices
 * are zero-based indices into the line offsets list, and the range is
 * inclusive on both ends.
 */
static bool
lines_are_utf8(const pm_parser_t *parser, size_t start_index, size_t end_index) {
    const pm_line_offset_list_t *line_offsets = &parser->line_offsets;
    const uint8_t *cursor = parser->start + line_offsets->offsets[start_index];
    const uint8_t *end = (end_index + 1 == line_offsets->size) ? parser->end : (parser->start + line_offsets->offsets[end_index + 1]);

    while (cursor < end) {
        size_t width = pm_encoding_utf_8_char_width(cursor, end - cursor);
        if (width == 0) return false;

        cursor += width;
    }

    return true;
}

typedef struct {
    pm_diagnostic_t *diagnostic;
    int32_t line_start;
    uint32_t column_start;
    uint32_t column_end;
    size_t idx;
} pm_rich_error_t;

static int
pm_rich_error_compare(const void *a, const void *b) {
    const pm_rich_error_t *left = (const pm_rich_error_t *) a;
    const pm_rich_error_t *right = (const pm_rich_error_t *) b;

    if (left->line_start != right->line_start) {
        return (left->line_start < right->line_start) ? -1 : 1;
    }

    if (left->column_start != right->column_start) {
        return (left->column_start < right->column_start) ? -1 : 1;
    }

    if (left->idx != right->idx) {
        return (left->idx < right->idx) ? 1 : -1;
    }

    return 0;
}

/**
 * Return the number of the last line of the source that can be displayed. When
 * the source ends with a newline, the empty line after it is not displayed.
 */
static int32_t
pm_rich_errors_final_line(const pm_parser_t *parser) {
    const pm_line_offset_list_t *line_offsets = &parser->line_offsets;
    int32_t final_line = parser->start_line + ((int32_t) line_offsets->size) - 1;

    if ((parser->start + line_offsets->offsets[line_offsets->size - 1]) == parser->end) {
        final_line--;
    }

    return final_line;
}

/**
 * Find the range of lines that may be displayed around an error on the given
 * line: up to two lines of context on either side of it, limited to the lines
 * in the source. The error's own line is always included, even when it is the
 * empty line after a trailing newline.
 */
static void
pm_rich_error_context(int32_t line, int32_t start_line, int32_t final_line, int32_t *first, int32_t *last) {
    *first = (line - start_line > 2) ? (line - 2) : start_line;
    *last = (final_line - line > 2) ? (line + 2) : final_line;
    if (*last < line) *last = line;
}

/**
 * Check if the source that will be displayed for the given rich errors is
 * valid UTF-8. That is each error's line and the lines of context around it.
 * The errors must be sorted by their line. Each line is checked at most once,
 * so that many errors on the same long line cost time proportional to the
 * line, not to the line times the number of errors.
 */
static bool
rich_errors_are_utf8(const pm_parser_t *parser, size_t nerrors, const pm_rich_error_t *rich_errors) {
    int32_t final_line = pm_rich_errors_final_line(parser);

    /* Every line from the first line of context of the most recently visited
     * error up to (but not including) this index has already been checked.
     * Because the errors are sorted, the first line of context never
     * decreases, so any later error only needs the lines from this index
     * onward. */
    size_t checked_index = 0;

    for (size_t idx = 0; idx < nerrors; idx++) {
        int32_t first_line;
        int32_t last_line;
        pm_rich_error_context(rich_errors[idx].line_start, parser->start_line, final_line, &first_line, &last_line);

        size_t start_index = (size_t) (first_line - parser->start_line);
        size_t end_index = (size_t) (last_line - parser->start_line);

        if (start_index < checked_index) start_index = checked_index;
        if (start_index > end_index) continue;

        if (!lines_are_utf8(parser, start_index, end_index)) return false;
        checked_index = end_index + 1;
    }

    return true;
}

#define COLOR_BOLD "\033[1m"
#define COLOR_GRAY "\033[2m"
#define COLOR_RED "\033[1;31m"
#define COLOR_RESET "\033[m"
#define TRUNCATE 30

/* The maximum number of columns of a line that errors are displayed beneath
 * before the line is displayed again. This must be at least TRUNCATE so that
 * every window after the first on a line starts with a truncated line. Lines
 * of context are cut off at the same width. */
#define WINDOW 80

typedef struct {
    /** The type of formatting to use when formatting the errors. */
    pm_errors_format_type_t type;

    /**
     * The number of columns taken up by the widest line number that will be
     * displayed, including the sign of a negative line number. The widest
     * possible is the 11 columns of -2147483648.
     */
    uint8_t width;
} pm_error_line_format_t;

/**
 * Write the decimal digits of the given line number, including the sign if it
 * is negative, so that they end at the end of the given buffer. The buffer is
 * large enough for the widest possible line number, -2147483648. Returns the
 * number of characters written.
 */
static uint8_t
pm_error_line_digits(int32_t line, char digits[11]) {
    /* The magnitude is computed in unsigned arithmetic so that negating the
     * minimum value of a 32-bit integer is well-defined. */
    uint32_t magnitude = (line < 0) ? (0U - (uint32_t) line) : (uint32_t) line;
    uint8_t length = 0;

    do {
        digits[10 - length++] = (char) ('0' + (magnitude % 10));
        magnitude /= 10;
    } while (magnitude > 0);

    if (line < 0) digits[10 - length++] = '-';
    return length;
}

/**
 * Append the given line number to the buffer, right aligned within the given
 * width.
 */
static void
pm_error_append_line_number(pm_buffer_t *buffer, int32_t line, uint8_t width) {
    char digits[11];
    uint8_t length = pm_error_line_digits(line, digits);

    if (width > length) pm_buffer_append_repeated(buffer, ' ', (size_t) (width - length));
    pm_buffer_append_string(buffer, digits + sizeof(digits) - length, length);
}

/**
 * Initialize the given line format struct based on whether or not to highlight
 * the line and the first and last line numbers that will be displayed. Every
 * line number in between is no wider than one of these two.
 */
static void
pm_error_line_format_init(pm_error_line_format_t *format, pm_errors_format_type_t format_type, int32_t first_line, int32_t last_line) {
    char digits[11];
    uint8_t first_width = pm_error_line_digits(first_line, digits);
    uint8_t last_width = pm_error_line_digits(last_line, digits);

    *format = (pm_error_line_format_t) {
        .type = format_type,
        .width = (first_width > last_width) ? first_width : last_width
    };
}

/**
 * Append the prefix for a line of source, which displays the line number right
 * aligned within the width of the widest line number.
 */
static void
pm_error_line_format_number(const pm_error_line_format_t *format, pm_buffer_t *buffer, int32_t line) {
    if (format->type > PM_ERRORS_FORMAT_PLAIN) PM_BUFFER_APPEND_LITERAL(buffer, COLOR_GRAY);
    pm_error_append_line_number(buffer, line, format->width);
    PM_BUFFER_APPEND_LITERAL(buffer, " | ");
    if (format->type > PM_ERRORS_FORMAT_PLAIN) PM_BUFFER_APPEND_LITERAL(buffer, COLOR_RESET);
}

/**
 * Append the prefix for a line beneath the source that displays an error, which
 * is blank where the line number would be so that the columns line up.
 */
static void
pm_error_line_format_blank(const pm_error_line_format_t *format, pm_buffer_t *buffer) {
    if (format->type > PM_ERRORS_FORMAT_PLAIN) PM_BUFFER_APPEND_LITERAL(buffer, COLOR_GRAY);
    pm_buffer_append_repeated(buffer, ' ', (size_t) format->width + 1);
    PM_BUFFER_APPEND_LITERAL(buffer, "| ");
    if (format->type > PM_ERRORS_FORMAT_PLAIN) PM_BUFFER_APPEND_LITERAL(buffer, COLOR_RESET);
}

/**
 * Append the divider that marks lines of source that are skipped between two
 * displayed snippets. It extends just past the line number prefix.
 */
static void
pm_error_line_format_divider(const pm_error_line_format_t *format, pm_buffer_t *buffer) {
    if (format->type > PM_ERRORS_FORMAT_PLAIN) PM_BUFFER_APPEND_LITERAL(buffer, COLOR_GRAY);
    PM_BUFFER_APPEND_LITERAL(buffer, "  ");
    pm_buffer_append_repeated(buffer, '~', (size_t) format->width + 4);
    if (format->type > PM_ERRORS_FORMAT_PLAIN) PM_BUFFER_APPEND_LITERAL(buffer, COLOR_RESET);
    pm_buffer_append_byte(buffer, '\n');
}

static void
pm_error_format_line(const pm_parser_t *parser, pm_buffer_t *buffer, const pm_error_line_format_t *format, int32_t line, uint32_t column_start, uint32_t column_end) {
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

    pm_error_line_format_number(format, buffer, line);

    /* Here we determine if we should truncate the start of the line. The
     * column is the start of a diagnostic, so it is on a character boundary. */
    bool truncate_start = column_start >= TRUNCATE;
    const uint8_t *display_start = truncate_start ? (start + column_start) : start;

    /* Here we determine if we should truncate the end of the line. Note that
     * this is written to avoid computing start + column_end, which could be
     * more than one past the end of the source when the error is at the end
     * of the input. The walk to find a character boundary begins at the
     * displayed start so that its cost is bounded by the displayed width. */
    bool truncate_end = false;
    if ((column_end != 0) && ((end - start) - ((ptrdiff_t) column_end) >= TRUNCATE)) {
        const uint8_t *end_candidate = start + column_end + TRUNCATE;

        for (const uint8_t *cursor = display_start; cursor < end_candidate;) {
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

    if (truncate_start) pm_buffer_append_string(buffer, "... ", 4);
    pm_buffer_append_string(buffer, (const char *) display_start, (size_t) (end - display_start));

    if (truncate_end) {
        pm_buffer_append_string(buffer, " ...\n", 5);
    } else if (end == parser->end && end > parser->start && end[-1] != '\n') {
        pm_buffer_append_byte(buffer, '\n');
    }
}

/**
 * Display a line of context around an error, which is cut off at the same width
 * as a window so that a long line does not dominate the output.
 */
static void
pm_error_format_context_line(const pm_parser_t *parser, pm_buffer_t *buffer, const pm_error_line_format_t *format, int32_t line) {
    PM_BUFFER_APPEND_LITERAL(buffer, "  ");
    pm_error_format_line(parser, buffer, format, line, 0, WINDOW);
}

static void
pm_rich_errors_format(const pm_parser_t *parser, pm_buffer_t *buffer, pm_errors_format_type_t format_type, size_t nerrors, pm_rich_error_t *rich_errors, bool inline_messages) {
    int32_t final_line = pm_rich_errors_final_line(parser);

    /* The line numbers that are displayed range from the first line of context
     * of the first error to the last line of context of the last error. */
    int32_t first_displayed_line;
    int32_t last_displayed_line;
    int32_t unused_line;
    pm_rich_error_context(rich_errors[0].line_start, parser->start_line, final_line, &first_displayed_line, &unused_line);
    pm_rich_error_context(rich_errors[nerrors - 1].line_start, parser->start_line, final_line, &unused_line, &last_displayed_line);

    pm_error_line_format_t format;
    pm_error_line_format_init(&format, format_type, first_displayed_line, last_displayed_line);


    /* We are going to iterate through every error in our error list and display
     * it. While we are iterating, we will display some padding lines of the
     * source before the error to give some context. We will be careful not to
     * display the same line twice in case the errors are close enough in the
     * source.
     *
     * The errors on a line are split into windows of at most WINDOW columns.
     * Each window displays its own slice of the line, and the markers beneath
     * it are padded relative to the start of that slice and cut off at its
     * end. This bounds the length of every marker line, so the output grows
     * linearly with the number of errors no matter how long the line is. */
    int32_t last_line = parser->start_line - 1;
    uint32_t window_column_start = 0;
    uint32_t window_column_end = 0;
    size_t window_end_idx = 0;

    for (size_t idx = 0; idx < nerrors; idx++) {
        pm_rich_error_t *rich_error = rich_errors + idx;

        /* Here we determine how many lines of padding of the source to display,
         * based on the difference from the last line that was displayed. */
        if (rich_error->line_start - last_line > 1) {
            if (rich_error->line_start - last_line > 2) {
                if ((idx != 0) && (rich_error->line_start - last_line > 3)) {
                    pm_error_line_format_divider(&format, buffer);
                }

                pm_error_format_context_line(parser, buffer, &format, rich_error->line_start - 2);
            }

            pm_error_format_context_line(parser, buffer, &format, rich_error->line_start - 1);
        }

        /* If this error is not in the current window (because it is the first
         * error, it is on a new line, or it is too far to the right), then we
         * start a new window and display the line that has the error in it. */
        if (idx == window_end_idx) {
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

            /* The displayed slice of the line starts at this error, unless it
             * is close enough to the start of the line to show it all. */
            window_column_start = (rich_error->column_start >= TRUNCATE) ? rich_error->column_start : 0;
            uint32_t window_limit = window_column_start + WINDOW;

            /* Find the errors on this line that start within the window, and
             * the maximum column end of all of them, capped at the window. */
            window_column_end = rich_error->column_end;
            for (window_end_idx = idx + 1; window_end_idx < nerrors; window_end_idx++) {
                const pm_rich_error_t *next_error = &rich_errors[window_end_idx];
                if ((next_error->line_start != rich_error->line_start) || (next_error->column_start >= window_limit)) break;
                if (next_error->column_end > window_column_end) window_column_end = next_error->column_end;
            }

            if (window_column_end > window_limit) window_column_end = window_limit;
            pm_error_format_line(parser, buffer, &format, rich_error->line_start, rich_error->column_start, window_column_end);
        }

        const uint8_t *start = parser->start + parser->line_offsets.offsets[rich_error->line_start - parser->start_line];
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
        pm_error_line_format_blank(&format, buffer);

        size_t column = 0;
        if (window_column_start > 0) {
            pm_buffer_append_string(buffer, "    ", 4);
            column = window_column_start;
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

        while ((column < rich_error->column_end) && (column < window_column_end)) {
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
         * diagnostic, depending on where the next diagnostic is in source. The
         * line after the last error is one past the last line that can be
         * displayed. */
        last_line = rich_error->line_start;
        int32_t next_line = (idx == nerrors - 1) ? (final_line + 1) : rich_errors[idx + 1].line_start;

        if (next_line - last_line > 1) {
            pm_error_format_context_line(parser, buffer, &format, ++last_line);
        }

        if (next_line - last_line > 1) {
            pm_error_format_context_line(parser, buffer, &format, ++last_line);
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
        .line_start = start_line_column.line,
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
    if (rich_errors == NULL) PRISM_OOM();

    size_t rich_errors_idx = 0;

    for (pm_diagnostic_t *diagnostic = (pm_diagnostic_t *) parser->error_list.head; diagnostic != NULL; diagnostic = (pm_diagnostic_t *) diagnostic->node.next) {
        pm_location_t location = pm_diagnostic_location(diagnostic);

        switch (pm_diagnostic_error_level(diagnostic)) {
          case PM_ERROR_LEVEL_SYNTAX: {
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

            pm_rich_error_init(parser, rich_errors, diagnostic, &location);

            if (rich_errors_are_utf8(parser, 1, rich_errors)) {
                pm_buffer_append_byte(buffer, '\n');
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
        rich_errors[0].line_start,
        (nerrors > 1) ? "s" : ""
    );

    /* Sort the errors so that they are in the order that they appear in the
     * source. This is the order they are displayed in, and it also lets the
     * UTF-8 check visit each line only once. */
    qsort(rich_errors, nerrors, sizeof(pm_rich_error_t), pm_rich_error_compare);

    if (rich_errors_are_utf8(parser, nerrors, rich_errors)) {
        /* In here, we have all of the rich diagnostic information and we know
         * the snippets are valid UTF-8, so we format them all together with
         * the source code snippets. */
        pm_rich_errors_format(parser, buffer, format_type, nerrors, rich_errors, true);
    } else {
        /* In here, we have content in the source that is not valid UTF-8. In
         * that case, we do not want to attempt to format the source code
         * snippets because we do not know how the terminal will handle it. The
         * diagnostics are displayed in the order that they appear in the
         * source, as they are when the snippets are displayed. */
        for (size_t idx = 0; idx < nerrors; idx++) {
            pm_rich_error_t *rich_error = &rich_errors[idx];

            if (idx > 0) pm_buffer_append_byte(buffer, '\n');
            pm_buffer_append_format(
                buffer,
                "%.*s:%" PRIi32 ": %s",
                filepath_length,
                filepath,
                rich_error->line_start,
                pm_diagnostic_message(rich_error->diagnostic)
            );
        }
    }

    xfree_sized(rich_errors, rich_errors_size);
    return PM_ERROR_LEVEL_SYNTAX;
}
