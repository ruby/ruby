/**
 * @file internal/options.h
 *
 * The options that can be passed to parsing.
 */
#ifndef PRISM_INTERNAL_OPTIONS_H
#define PRISM_INTERNAL_OPTIONS_H

#include "prism/options.h"

/**
 * A scope of locals surrounding the code that is being parsed.
 */
struct pm_options_scope_t {
    /** The number of locals in the scope. */
    size_t locals_count;

    /** The names of the locals in the scope. */
    pm_string_t *locals;

    /** Flags for the set of forwarding parameters in this scope. */
    uint8_t forwarding;
};

/**
 * The options that can be passed to the parser.
 */
struct pm_options_t {
    /**
     * The callback to call when additional switches are found in a shebang
     * comment.
     */
    pm_options_shebang_callback_t shebang_callback;

    /**
     * Any additional data that should be passed along to the shebang callback
     * if one was set.
     */
    void *shebang_callback_data;

    /** The name of the file that is currently being parsed. */
    pm_string_t filepath;

    /**
     * The line within the file that the parse starts on. This value is
     * 1-indexed.
     */
    int32_t line;

    /**
     * The name of the encoding that the source file is in. Note that this must
     * correspond to a name that can be found with Encoding.find in Ruby.
     */
    pm_string_t encoding;

    /**
     * The number of scopes surrounding the code that is being parsed.
     */
    size_t scopes_count;

    /**
     * The scopes surrounding the code that is being parsed. For most parses
     * this will be NULL, but for evals it will be the locals that are in scope
     * surrounding the eval. Scopes are ordered from the outermost scope to the
     * innermost one.
     */
    pm_options_scope_t *scopes;

    /**
     * The version of prism that we should be parsing with. This is used to
     * allow consumers to specify which behavior they want in case they need to
     * parse exactly as a specific version of CRuby.
     */
    pm_options_version_t version;

    /** A bitset of the various options that were set on the command line. */
    uint8_t command_line;

    /**
    * Whether or not the frozen string literal option has been set.
    * May be:
    *  - PM_OPTIONS_FROZEN_STRING_LITERAL_DISABLED
    *  - PM_OPTIONS_FROZEN_STRING_LITERAL_ENABLED
    *  - PM_OPTIONS_FROZEN_STRING_LITERAL_UNSET
    */
    int8_t frozen_string_literal;

    /**
     * Whether or not the encoding magic comments should be respected. This is a
     * niche use-case where you want to parse a file with a specific encoding
     * but ignore any encoding magic comments at the top of the file.
     */
    bool encoding_locked;

    /**
     * When the file being parsed is the main script, the shebang will be
     * considered for command-line flags (or for implicit -x). The caller needs
     * to pass this information to the parser so that it can behave correctly.
     */
    bool main_script;

    /**
     * When the file being parsed is considered a "partial" script, jumps will
     * not be marked as errors if they are not contained within loops/blocks.
     * This is used in the case that you're parsing a script that you know will
     * be embedded inside another script later, but you do not have that context
     * yet. For example, when parsing an ERB template that will be evaluated
     * inside another script.
     */
    bool partial_script;

    /**
     * Whether or not the parser should freeze the nodes that it creates. This
     * makes it possible to have a deeply frozen AST that is safe to share
     * between concurrency primitives.
     */
    bool freeze;
};

/**
 * Free the internal memory associated with the options.
 *
 * @param options The options struct whose internal memory should be freed.
 */
void pm_options_cleanup(pm_options_t *options);

/**
 * Deserialize an options struct from the given binary string. This is used to
 * pass options to the parser from an FFI call so that consumers of the library
 * from an FFI perspective don't have to worry about the structure of our
 * options structs. Since the source of these calls will be from Ruby
 * implementation internals we assume it is from a trusted source.
 *
 * `data` is assumed to be a valid pointer pointing to well-formed data. The
 * layout of this data should be the same every time, and is described below:
 *
 * | # bytes | field                      |
 * | ------- | -------------------------- |
 * | `4`     | the length of the filepath |
 * | ...     | the filepath bytes         |
 * | `4`     | the line number            |
 * | `4`     | the length the encoding    |
 * | ...     | the encoding bytes         |
 * | `1`     | frozen string literal      |
 * | `1`     | -p command line option     |
 * | `1`     | -n command line option     |
 * | `1`     | -l command line option     |
 * | `1`     | -a command line option     |
 * | `1`     | the version                |
 * | `1`     | encoding locked            |
 * | `1`     | main script                |
 * | `1`     | partial script             |
 * | `1`     | freeze                     |
 * | `4`     | the number of scopes       |
 * | ...     | the scopes                 |
 *
 * The version field is an enum, so it should be one of the following values:
 *
 * | value | version                   |
 * | ----- | ------------------------- |
 * | `0`   | use the latest version of prism |
 * | `1`   | use the version of prism that is vendored in CRuby 3.3.0 |
 * | `2`   | use the version of prism that is vendored in CRuby 3.4.0 |
 * | `3`   | use the version of prism that is vendored in CRuby 4.0.0 |
 * | `4`   | use the version of prism that is vendored in CRuby 4.1.0 |
 *
 * Each scope is laid out as follows:
 *
 * | # bytes | field                      |
 * | ------- | -------------------------- |
 * | `4`     | the number of locals       |
 * | `1`     | the forwarding flags       |
 * | ...     | the locals                 |
 *
 * Each local is laid out as follows:
 *
 * | # bytes | field                      |
 * | ------- | -------------------------- |
 * | `4`     | the length of the local    |
 * | ...     | the local bytes            |
 *
 * Some additional things to note about this layout:
 *
 * * The filepath can have a length of 0, in which case we'll consider it an
 *   empty string.
 * * The line number should be 0-indexed.
 * * The encoding can have a length of 0, in which case we'll use the default
 *   encoding (UTF-8). If it's not 0, it should correspond to a name of an
 *   encoding that can be passed to `Encoding.find` in Ruby.
 * * The frozen string literal, encoding locked, main script, and partial script
 *   fields are booleans, so their values should be either 0 or 1.
 * * The number of scopes can be 0.
 *
 * @param options The options struct to deserialize into.
 * @param data The binary string to deserialize from.
 */
void pm_options_read(pm_options_t *options, const char *data);

#endif
