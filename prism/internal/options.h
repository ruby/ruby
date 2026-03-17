/**
 * @file internal/options.h
 *
 * The options that can be passed to parsing.
 */
#ifndef PRISM_INTERNAL_OPTIONS_H
#define PRISM_INTERNAL_OPTIONS_H

#include "prism/options.h"

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
