#include "prism/options.h"

/**
 * Set the filepath option on the given options struct.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_filepath_set(pm_options_t *options, const char *filepath) {
    options->filepath = filepath;
}

/**
 * Set the encoding option on the given options struct.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_encoding_set(pm_options_t *options, const char *encoding) {
    options->encoding = encoding;
}

/**
 * Set the line option on the given options struct.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_line_set(pm_options_t *options, uint32_t line) {
    options->line = line;
}

/**
 * Set the frozen string literal option on the given options struct.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_frozen_string_literal_set(pm_options_t *options, bool frozen_string_literal) {
    options->frozen_string_literal = frozen_string_literal;
}

/**
 * Set the suppress warnings option on the given options struct.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_suppress_warnings_set(pm_options_t *options, bool suppress_warnings) {
    options->suppress_warnings = suppress_warnings;
}

/**
 * Allocate and zero out the scopes array on the given options struct.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_scopes_init(pm_options_t *options, size_t scopes_count) {
    options->scopes_count = scopes_count;
    options->scopes = calloc(scopes_count, sizeof(pm_options_scope_t));
    if (options->scopes == NULL) abort();
}

/**
 * Return a pointer to the scope at the given index within the given options.
 */
PRISM_EXPORTED_FUNCTION const pm_options_scope_t *
pm_options_scope_get(const pm_options_t *options, size_t index) {
    return &options->scopes[index];
}

/**
 * Create a new options scope struct. This will hold a set of locals that are in
 * scope surrounding the code that is being parsed.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_scope_init(pm_options_scope_t *scope, size_t locals_count) {
    scope->locals_count = locals_count;
    scope->locals = calloc(locals_count, sizeof(pm_string_t));
    if (scope->locals == NULL) abort();
}

/**
 * Return a pointer to the local at the given index within the given scope.
 */
PRISM_EXPORTED_FUNCTION const pm_string_t *
pm_options_scope_local_get(const pm_options_scope_t *scope, size_t index) {
    return &scope->locals[index];
}

/**
 * Free the internal memory associated with the options.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_free(pm_options_t *options) {
    for (size_t scope_index = 0; scope_index < options->scopes_count; scope_index++) {
        pm_options_scope_t *scope = &options->scopes[scope_index];

        for (size_t local_index = 0; local_index < scope->locals_count; local_index++) {
            pm_string_free(&scope->locals[local_index]);
        }

        free(scope->locals);
    }

    free(options->scopes);
}
