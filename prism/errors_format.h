/**
 * @file errors_format.h
 *
 * A function for formatting the errors in a parser into a buffer.
 */
#ifndef PRISM_ERRORS_FORMAT_H
#define PRISM_ERRORS_FORMAT_H

#include "prism/compiler/exported.h"
#include "prism/compiler/nodiscard.h"
#include "prism/compiler/nonnull.h"

#include "prism/buffer.h"
#include "prism/diagnostic.h"
#include "prism/parser.h"

/** The type of formatting to use when formatting errors. */
typedef enum {
    /** Format errors in a plain format with no colors or styles. Typically
     * used when outputting to a file or when the output is not a terminal.
     */
    PM_ERRORS_FORMAT_PLAIN = 1,

    /** Format errors in a style format with bold only. Typically used when
     * outputting to a terminal where you do not want colors.
     */
    PM_ERRORS_FORMAT_STYLE = 2,

    /** Format errors in a color format with bold and colors. The default case
     * when outputting on the terminal.
     */
    PM_ERRORS_FORMAT_COLOR = 3
} pm_errors_format_type_t;

/**
 * Format the errors in a parser into a buffer. After return, the buffer will
 * contain the formatted errors and any relevant source snippets if available
 * and possible.
 *
 * @param parser The parser containing the errors to format. Note that the
 *   parser does not need to be fully initialized, but it will need to have
 *   start, end, start_line, encoding, line_offsets, filepath, and error_list
 *   initialized.
 * @param buffer The buffer to format the errors into.
 * @param format_type The type of formatting to use when formatting the errors.
 * @returns The error level of the error with the highest precedence that was
 *   formatted. In practice this means it will be the argument or load error
 *   level if any were found, otherwise it will be the syntax error level.
 *   Callers should raise appropriate error types based on the returned level.
 */
PRISM_EXPORTED_FUNCTION pm_error_level_t pm_errors_format(const pm_parser_t *parser, pm_buffer_t *buffer, pm_errors_format_type_t format_type) PRISM_NONNULL(1, 2);

#endif
