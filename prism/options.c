#include "prism/options.h"

/**
 * Set the filepath option on the given options struct.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_filepath_set(pm_options_t *options, const char *filepath) {
    pm_string_constant_init(&options->filepath, filepath, strlen(filepath));
}

/**
 * Set the encoding option on the given options struct.
 */
PRISM_EXPORTED_FUNCTION void
pm_options_encoding_set(pm_options_t *options, const char *encoding) {
    pm_string_constant_init(&options->encoding, encoding, strlen(encoding));
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
    pm_string_free(&options->filepath);
    pm_string_free(&options->encoding);

    for (size_t scope_index = 0; scope_index < options->scopes_count; scope_index++) {
        pm_options_scope_t *scope = &options->scopes[scope_index];

        for (size_t local_index = 0; local_index < scope->locals_count; local_index++) {
            pm_string_free(&scope->locals[local_index]);
        }

        free(scope->locals);
    }

    free(options->scopes);
}

/**
 * Read a 32-bit unsigned integer from a pointer. This function is used to read
 * the options that are passed into the parser from the Ruby implementation. It
 * handles aligned and unaligned reads.
 */
static uint32_t
pm_options_read_u32(const char *data) {
    if (((uintptr_t) data) % sizeof(uint32_t) == 0) {
        return *((uint32_t *) data);
    } else {
        uint32_t value;
        memcpy(&value, data, sizeof(uint32_t));
        return value;
    }
}

/**
 * Deserialize an options struct from the given binary string. This is used to
 * pass options to the parser from an FFI call so that consumers of the library
 * from an FFI perspective don't have to worry about the structure of our
 * options structs. Since the source of these calls will be from Ruby
 * implementation internals we assume it is from a trusted source.
 */
void
pm_options_read(pm_options_t *options, const char *data) {
    uint32_t filepath_length = pm_options_read_u32(data);
    data += 4;

    if (filepath_length > 0) {
        pm_string_constant_init(&options->filepath, data, filepath_length);
        data += filepath_length;
    }

    options->line = pm_options_read_u32(data);
    data += 4;

    uint32_t encoding_length = pm_options_read_u32(data);
    data += 4;

    if (encoding_length > 0) {
        pm_string_constant_init(&options->encoding, data, encoding_length);
        data += encoding_length;
    }

    options->frozen_string_literal = *data++;
    options->suppress_warnings = *data++;

    uint32_t scopes_count = pm_options_read_u32(data);
    data += 4;

    if (scopes_count > 0) {
        pm_options_scopes_init(options, scopes_count);

        for (size_t scope_index = 0; scope_index < scopes_count; scope_index++) {
            uint32_t locals_count = pm_options_read_u32(data);
            data += 4;

            pm_options_scope_t *scope = &options->scopes[scope_index];
            pm_options_scope_init(scope, locals_count);

            for (size_t local_index = 0; local_index < locals_count; local_index++) {
                uint32_t local_length = pm_options_read_u32(data);
                data += 4;

                pm_string_constant_init(&scope->locals[local_index], data, local_length);
                data += local_length;
            }
        }
    }
}
