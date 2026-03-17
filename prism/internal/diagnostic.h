/**
 * @file internal/diagnostic.h
 *
 * A list of diagnostics generated during parsing.
 */
#ifndef PRISM_INTERNAL_DIAGNOSTIC_H
#define PRISM_INTERNAL_DIAGNOSTIC_H

#include "prism/diagnostic.h"
#include "prism/arena.h"

/**
 * Append a diagnostic to the given list of diagnostics that is using shared
 * memory for its message.
 *
 * @param arena The arena to allocate from.
 * @param list The list to append to.
 * @param start The source offset of the start of the diagnostic.
 * @param length The length of the diagnostic.
 * @param diag_id The diagnostic ID.
 */
void pm_diagnostic_list_append(pm_arena_t *arena, pm_list_t *list, uint32_t start, uint32_t length, pm_diagnostic_id_t diag_id);

/**
 * Append a diagnostic to the given list of diagnostics that is using a format
 * string for its message.
 *
 * @param arena The arena to allocate from.
 * @param list The list to append to.
 * @param start The source offset of the start of the diagnostic.
 * @param length The length of the diagnostic.
 * @param diag_id The diagnostic ID.
 * @param ... The arguments to the format string for the message.
 */
void pm_diagnostic_list_append_format(pm_arena_t *arena, pm_list_t *list, uint32_t start, uint32_t length, pm_diagnostic_id_t diag_id, ...);

#endif
