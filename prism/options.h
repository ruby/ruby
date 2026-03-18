/**
 * @file options.h
 *
 * The options that can be passed to parsing.
 */
#ifndef PRISM_OPTIONS_H
#define PRISM_OPTIONS_H

#include "prism/strings.h"

#include <stdbool.h>
#include <stddef.h>

/**
 * A scope of locals surrounding the code that is being parsed.
 */
typedef struct pm_options_scope_t pm_options_scope_t;

/**
 * The options that can be passed to the parser.
 */
typedef struct pm_options_t pm_options_t;

/**
 * String literals should be made frozen.
 */
#define PM_OPTIONS_FROZEN_STRING_LITERAL_DISABLED   ((int8_t) -1)

/**
 * String literals may be frozen or mutable depending on the implementation
 * default.
 */
#define PM_OPTIONS_FROZEN_STRING_LITERAL_UNSET      ((int8_t)  0)

/**
 * String literals should be made mutable.
 */
#define PM_OPTIONS_FROZEN_STRING_LITERAL_ENABLED    ((int8_t)  1)

/** The default value for parameters. */
static const uint8_t PM_OPTIONS_SCOPE_FORWARDING_NONE = 0x0;

/** When the scope is fowarding with the * parameter. */
static const uint8_t PM_OPTIONS_SCOPE_FORWARDING_POSITIONALS = 0x1;

/** When the scope is fowarding with the ** parameter. */
static const uint8_t PM_OPTIONS_SCOPE_FORWARDING_KEYWORDS = 0x2;

/** When the scope is fowarding with the & parameter. */
static const uint8_t PM_OPTIONS_SCOPE_FORWARDING_BLOCK = 0x4;

/** When the scope is fowarding with the ... parameter. */
static const uint8_t PM_OPTIONS_SCOPE_FORWARDING_ALL = 0x8;

/**
 * The callback called when additional switches are found in a shebang comment
 * that need to be processed by the runtime.
 *
 * @param options The options struct that may be updated by this callback.
 *   Certain fields will be checked for changes, specifically encoding,
 *   command_line, and frozen_string_literal.
 * @param source The source of the shebang comment.
 * @param length The length of the source.
 * @param shebang_callback_data Any additional data that should be passed along
 *   to the callback.
 */
typedef void (*pm_options_shebang_callback_t)(pm_options_t *options, const uint8_t *source, size_t length, void *shebang_callback_data);

/**
 * A bit representing whether or not the command line -a option was set. -a
 * splits the input line $_ into $F.
 */
static const uint8_t PM_OPTIONS_COMMAND_LINE_A = 0x1;

/**
 * A bit representing whether or not the command line -e option was set. -e
 * allow the user to specify a script to be executed. This is necessary for
 * prism to know because certain warnings are not generated when -e is used.
 */
static const uint8_t PM_OPTIONS_COMMAND_LINE_E = 0x2;

/**
 * A bit representing whether or not the command line -l option was set. -l
 * chomps the input line by default.
 */
static const uint8_t PM_OPTIONS_COMMAND_LINE_L = 0x4;

/**
 * A bit representing whether or not the command line -n option was set. -n
 * wraps the script in a while gets loop.
 */
static const uint8_t PM_OPTIONS_COMMAND_LINE_N = 0x8;

/**
 * A bit representing whether or not the command line -p option was set. -p
 * prints the value of $_ at the end of each loop.
 */
static const uint8_t PM_OPTIONS_COMMAND_LINE_P = 0x10;

/**
 * A bit representing whether or not the command line -x option was set. -x
 * searches the input file for a shebang that matches the current Ruby engine.
 */
static const uint8_t PM_OPTIONS_COMMAND_LINE_X = 0x20;

/**
 * Allocate a new options struct. If the options struct cannot be allocated,
 * this function aborts the process.
 *
 * @return A new options struct with default values. It is the responsibility of
 *     the caller to free this struct using pm_options_free().
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION pm_options_t * pm_options_new(void);

/**
 * Free both the held memory of the given options struct and the struct itself.
 *
 * @param options The options struct to free.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_free(pm_options_t *options);

/**
 * Set the shebang callback option on the given options struct.
 *
 * @param options The options struct to set the shebang callback on.
 * @param shebang_callback The shebang callback to set.
 * @param shebang_callback_data Any additional data that should be passed along
 *   to the callback.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_shebang_callback_set(pm_options_t *options, pm_options_shebang_callback_t shebang_callback, void *shebang_callback_data);

/**
 * Get the filepath option on the given options struct.
 *
 * @param options The options struct to get the filepath from.
 * @return The filepath.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION pm_string_t * pm_options_filepath_get(pm_options_t *options);

/**
 * Set the filepath option on the given options struct.
 *
 * @param options The options struct to set the filepath on.
 * @param filepath The filepath to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_filepath_set(pm_options_t *options, const char *filepath);

/**
 * Set the line option on the given options struct.
 *
 * @param options The options struct to set the line on.
 * @param line The line to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_line_set(pm_options_t *options, int32_t line);

/**
 * Set the encoding option on the given options struct.
 *
 * @param options The options struct to set the encoding on.
 * @param encoding The encoding to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_encoding_set(pm_options_t *options, const char *encoding);

/**
 * Set the encoding_locked option on the given options struct.
 *
 * @param options The options struct to set the encoding_locked value on.
 * @param encoding_locked The encoding_locked value to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_encoding_locked_set(pm_options_t *options, bool encoding_locked);

/**
 * Set the frozen string literal option on the given options struct.
 *
 * @param options The options struct to set the frozen string literal value on.
 * @param frozen_string_literal The frozen string literal value to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_frozen_string_literal_set(pm_options_t *options, bool frozen_string_literal);

/**
 * Sets the command line option on the given options struct.
 *
 * @param options The options struct to set the command line option on.
 * @param command_line The command_line value to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_command_line_set(pm_options_t *options, uint8_t command_line);

/**
 * Set the version option on the given options struct by parsing the given
 * string. If the string contains an invalid option, this returns false.
 * Otherwise, it returns true.
 *
 * @param options The options struct to set the version on.
 * @param version The version to set.
 * @param length The length of the version string.
 * @return Whether or not the version was parsed successfully.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION bool pm_options_version_set(pm_options_t *options, const char *version, size_t length);

/**
 * Set the version option on the given options struct to the lowest version of
 * Ruby that prism supports.
 *
 * @param options The options struct to set the version on.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_version_set_lowest(pm_options_t *options);

/**
 * Set the version option on the given options struct to the highest version of
 * Ruby that prism supports.
 *
 * @param options The options struct to set the version on.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_version_set_highest(pm_options_t *options);

/**
 * Set the main script option on the given options struct.
 *
 * @param options The options struct to set the main script value on.
 * @param main_script The main script value to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_main_script_set(pm_options_t *options, bool main_script);

/**
 * Set the partial script option on the given options struct.
 *
 * @param options The options struct to set the partial script value on.
 * @param partial_script The partial script value to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_partial_script_set(pm_options_t *options, bool partial_script);

/**
 * Get the freeze option on the given options struct.
 *
 * @param options The options struct to get the freeze value from.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION bool pm_options_freeze_get(const pm_options_t *options);

/**
 * Set the freeze option on the given options struct.
 *
 * @param options The options struct to set the freeze value on.
 * @param freeze The freeze value to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_freeze_set(pm_options_t *options, bool freeze);

/**
 * Allocate and zero out the scopes array on the given options struct.
 *
 * @param options The options struct to initialize the scopes array on.
 * @param scopes_count The number of scopes to allocate.
 * @return Whether or not the scopes array was initialized successfully.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION bool pm_options_scopes_init(pm_options_t *options, size_t scopes_count);

/**
 * Return a constant pointer to the scope at the given index within the given
 * options.
 *
 * @param options The options struct to get the scope from.
 * @param index The index of the scope to get.
 * @return A constant pointer to the scope at the given index.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION const pm_options_scope_t * pm_options_scope_get(const pm_options_t *options, size_t index);

/**
 * Return a mutable pointer to the scope at the given index within the given
 * options.
 *
 * @param options The options struct to get the scope from.
 * @param index The index of the scope to get.
 * @return A mutable pointer to the scope at the given index.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION pm_options_scope_t * pm_options_scope_get_mut(pm_options_t *options, size_t index);

/**
 * Create a new options scope struct. This will hold a set of locals that are in
 * scope surrounding the code that is being parsed. If the scope was unable to
 * allocate its locals, this function will abort the process.
 *
 * @param scope The scope struct to initialize.
 * @param locals_count The number of locals to allocate.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_scope_init(pm_options_scope_t *scope, size_t locals_count);

/**
 * Return a constant pointer to the local at the given index within the given
 * scope.
 *
 * @param scope The scope struct to get the local from.
 * @param index The index of the local to get.
 * @return A constant pointer to the local at the given index.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION const pm_string_t * pm_options_scope_local_get(const pm_options_scope_t *scope, size_t index);

/**
 * Return a mutable pointer to the local at the given index within the given
 * scope.
 *
 * @param scope The scope struct to get the local from.
 * @param index The index of the local to get.
 * @return A mutable pointer to the local at the given index.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION pm_string_t * pm_options_scope_local_get_mut(pm_options_scope_t *scope, size_t index);

/**
 * Set the forwarding option on the given scope struct.
 *
 * @param scope The scope struct to set the forwarding on.
 * @param forwarding The forwarding value to set.
 *
 * \public \memberof pm_options
 */
PRISM_EXPORTED_FUNCTION void pm_options_scope_forwarding_set(pm_options_scope_t *scope, uint8_t forwarding);

#endif
