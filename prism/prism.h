/**
 * @file prism.h
 *
 * The main header file for the prism parser.
 */
#ifndef PRISM_H
#define PRISM_H

#ifdef __cplusplus
extern "C" {
#endif

#include "prism/arena.h"
#include "prism/ast.h"
#include "prism/diagnostic.h"
#include "prism/excludes.h"
#include "prism/json.h"
#include "prism/node.h"
#include "prism/options.h"
#include "prism/parser.h"
#include "prism/prettyprint.h"
#include "prism/serialize.h"
#include "prism/stream.h"
#include "prism/string_query.h"
#include "prism/version.h"

/**
 * The prism version and the serialization format.
 *
 * @returns The prism version as a constant string.
 */
PRISM_EXPORTED_FUNCTION const char * pm_version(void);

/**
 * Initiate the parser with the given parser.
 *
 * @param parser The parser to use.
 * @return The AST representing the source.
 *
 * \public \memberof pm_parser
 */
PRISM_EXPORTED_FUNCTION pm_node_t * pm_parse(pm_parser_t *parser);

/**
 * Parse the source and return true if it parses without errors or warnings.
 *
 * @param source The source to parse.
 * @param size The size of the source.
 * @param data The optional data to pass to the parser.
 * @return True if the source parses without errors or warnings.
 */
PRISM_EXPORTED_FUNCTION bool pm_parse_success_p(const uint8_t *source, size_t size, const char *data);

/**
 * @mainpage
 *
 * Prism is a parser for the Ruby programming language. It is designed to be
 * portable, error tolerant, and maintainable. It is written in C99 and has no
 * dependencies. It is currently being integrated into
 * [CRuby](https://github.com/ruby/ruby),
 * [JRuby](https://github.com/jruby/jruby),
 * [TruffleRuby](https://github.com/truffleruby/truffleruby),
 * [Sorbet](https://github.com/sorbet/sorbet), and
 * [Syntax Tree](https://github.com/ruby-syntax-tree/syntax_tree).
 *
 * @section getting-started Getting started
 *
 * If you're vendoring this project and compiling it statically then as long as
 * you have a C99 compiler you will be fine. If you're linking against it as
 * shared library, then you should compile with `-fvisibility=hidden` and
 * `-DPRISM_EXPORT_SYMBOLS` to tell prism to make only its public interface
 * visible.
 *
 * @section parsing Parsing
 *
 * In order to parse Ruby code, the functions that you are going to want to use
 * and be aware of are:
 *
 * * `pm_arena_new()` - create a new arena to hold all AST-lifetime allocations
 * * `pm_parser_new()` - allocate and initialize a new parser
 * * `pm_parse()` - parse and return the root node
 * * `pm_parser_free()` - free the parser and its internal memory
 * * `pm_arena_free()` - free all AST-lifetime memory
 *
 * Putting all of this together would look something like:
 *
 * ```c
 * void parse(const uint8_t *source, size_t length) {
 *     pm_arena_t *arena = pm_arena_new();
 *     pm_parser_t *parser = pm_parser_new(arena, source, length, NULL);
 *
 *     pm_node_t *root = pm_parse(parser);
 *     printf("PARSED!\n");
 *
 *     pm_parser_free(parser);
 *     pm_arena_free(arena);
 * }
 * ```
 *
 * All of the nodes "inherit" from `pm_node_t` by embedding those structures
 * as their first member. This means you can downcast and upcast any node in the
 * tree to a `pm_node_t`.
 *
 * @section serializing Serializing
 *
 * Prism provides the ability to serialize the AST and its related metadata into
 * a binary format. This format is designed to be portable to different
 * languages and runtimes so that you only need to make one FFI call in order to
 * parse Ruby code. The functions that you are going to want to use and be
 * aware of are:
 *
 * * `pm_buffer_new()` - create a new buffer
 * * `pm_buffer_free()` - free the buffer and its internal memory
 * * `pm_serialize_parse()` - parse and serialize the AST into a buffer
 *
 * Putting all of this together would look something like:
 *
 * ```c
 * void serialize(const uint8_t *source, size_t length) {
 *     pm_buffer_t *buffer = pm_buffer_new();
 *
 *     pm_serialize_parse(buffer, source, length, NULL);
 *     printf("SERIALIZED!\n");
 *
 *     pm_buffer_free(buffer);
 * }
 * ```
 *
 * @section inspecting Inspecting
 *
 * Prism provides the ability to inspect the AST by pretty-printing nodes. You
 * can do this with the `pm_prettyprint()` function, which you would use like:
 *
 * ```c
 * void prettyprint(const uint8_t *source, size_t length) {
 *     pm_arena_t *arena = pm_arena_new();
 *     pm_parser_t *parser = pm_parser_new(arena, source, length, NULL);
 *
 *     pm_node_t *root = pm_parse(parser);
 *     pm_buffer_t *buffer = pm_buffer_new();
 *
 *     pm_prettyprint(buffer, parser, root);
 *     printf("%*.s\n", (int) pm_buffer_length(buffer), pm_buffer_value(buffer));
 *
 *     pm_buffer_free(buffer);
 *     pm_parser_free(parser);
 *     pm_arena_free(arena);
 * }
 * ```
 */

#ifdef __cplusplus
}
#endif

#endif
