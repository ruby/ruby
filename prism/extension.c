#include "prism/extension.h"

// NOTE: this file should contain only bindings. All non-trivial logic should be
// in librubyparser so it can be shared its the various callers.

VALUE rb_cPrism;
VALUE rb_cPrismNode;
VALUE rb_cPrismSource;
VALUE rb_cPrismToken;
VALUE rb_cPrismLocation;

VALUE rb_cPrismComment;
VALUE rb_cPrismInlineComment;
VALUE rb_cPrismEmbDocComment;
VALUE rb_cPrismDATAComment;
VALUE rb_cPrismMagicComment;
VALUE rb_cPrismParseError;
VALUE rb_cPrismParseWarning;
VALUE rb_cPrismParseResult;

ID rb_option_id_filepath;
ID rb_option_id_encoding;
ID rb_option_id_line;
ID rb_option_id_frozen_string_literal;
ID rb_option_id_verbose;
ID rb_option_id_scopes;

/******************************************************************************/
/* IO of Ruby code                                                            */
/******************************************************************************/

/**
 * Check if the given VALUE is a string. If it's nil, then return NULL. If it's
 * not a string, then raise a type error. Otherwise return the VALUE as a C
 * string.
 */
static const char *
check_string(VALUE value) {
    // If the value is nil, then we don't need to do anything.
    if (NIL_P(value)) {
        return NULL;
    }

    // Check if the value is a string. If it's not, then raise a type error.
    if (!RB_TYPE_P(value, T_STRING)) {
        rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected String)", rb_obj_class(value));
    }

    // Otherwise, return the value as a C string.
    return RSTRING_PTR(value);
}

/**
 * Load the contents and size of the given string into the given pm_string_t.
 */
static void
input_load_string(pm_string_t *input, VALUE string) {
    // Check if the string is a string. If it's not, then raise a type error.
    if (!RB_TYPE_P(string, T_STRING)) {
        rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected String)", rb_obj_class(string));
    }

    pm_string_constant_init(input, RSTRING_PTR(string), RSTRING_LEN(string));
}

/******************************************************************************/
/* Building C options from Ruby options                                       */
/******************************************************************************/

/**
 * Build the scopes associated with the provided Ruby keyword value.
 */
static void
build_options_scopes(pm_options_t *options, VALUE scopes) {
    // Check if the value is an array. If it's not, then raise a type error.
    if (!RB_TYPE_P(scopes, T_ARRAY)) {
        rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected Array)", rb_obj_class(scopes));
    }

    // Initialize the scopes array.
    size_t scopes_count = RARRAY_LEN(scopes);
    pm_options_scopes_init(options, scopes_count);

    // Iterate over the scopes and add them to the options.
    for (size_t scope_index = 0; scope_index < scopes_count; scope_index++) {
        VALUE scope = rb_ary_entry(scopes, scope_index);

        // Check that the scope is an array. If it's not, then raise a type
        // error.
        if (!RB_TYPE_P(scope, T_ARRAY)) {
            rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected Array)", rb_obj_class(scope));
        }

        // Initialize the scope array.
        size_t locals_count = RARRAY_LEN(scope);
        pm_options_scope_t *options_scope = &options->scopes[scope_index];
        pm_options_scope_init(options_scope, locals_count);

        // Iterate over the locals and add them to the scope.
        for (size_t local_index = 0; local_index < locals_count; local_index++) {
            VALUE local = rb_ary_entry(scope, local_index);

            // Check that the local is a symbol. If it's not, then raise a
            // type error.
            if (!RB_TYPE_P(local, T_SYMBOL)) {
                rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected Symbol)", rb_obj_class(local));
            }

            // Add the local to the scope.
            pm_string_t *scope_local = &options_scope->locals[local_index];
            const char *name = rb_id2name(SYM2ID(local));
            pm_string_constant_init(scope_local, name, strlen(name));
        }
    }
}

/**
 * An iterator function that is called for each key-value in the keywords hash.
 */
static int
build_options_i(VALUE key, VALUE value, VALUE argument) {
    pm_options_t *options = (pm_options_t *) argument;
    ID key_id = SYM2ID(key);

    if (key_id == rb_option_id_filepath) {
        if (!NIL_P(value)) pm_options_filepath_set(options, check_string(value));
    } else if (key_id == rb_option_id_encoding) {
        if (!NIL_P(value)) pm_options_encoding_set(options, rb_enc_name(rb_to_encoding(value)));
    } else if (key_id == rb_option_id_line) {
        if (!NIL_P(value)) pm_options_line_set(options, NUM2UINT(value));
    } else if (key_id == rb_option_id_frozen_string_literal) {
        if (!NIL_P(value)) pm_options_frozen_string_literal_set(options, value == Qtrue);
    } else if (key_id == rb_option_id_verbose) {
        pm_options_suppress_warnings_set(options, value != Qtrue);
    } else if (key_id == rb_option_id_scopes) {
        if (!NIL_P(value)) build_options_scopes(options, value);
    } else {
        rb_raise(rb_eArgError, "unknown keyword: %"PRIsVALUE, key);
    }

    return ST_CONTINUE;
}

/**
 * We need a struct here to pass through rb_protect and it has to be a single
 * value. Because the sizeof(VALUE) == sizeof(void *), we're going to pass this
 * through as an opaque pointer and cast it on both sides.
 */
struct build_options_data {
    pm_options_t *options;
    VALUE keywords;
};

/**
 * Build the set of options from the given keywords. Note that this can raise a
 * Ruby error if the options are not valid.
 */
static VALUE
build_options(VALUE argument) {
    struct build_options_data *data = (struct build_options_data *) argument;
    rb_hash_foreach(data->keywords, build_options_i, (VALUE) data->options);
    return Qnil;
}

/**
 * Extract the options from the given keyword arguments.
 */
static void
extract_options(pm_options_t *options, VALUE filepath, VALUE keywords) {
    if (!NIL_P(keywords)) {
        struct build_options_data data = { .options = options, .keywords = keywords };
        struct build_options_data *argument = &data;

        int state = 0;
        rb_protect(build_options, (VALUE) argument, &state);

        if (state != 0) {
            pm_options_free(options);
            rb_jump_tag(state);
        }
    }

    if (!NIL_P(filepath)) {
        if (!RB_TYPE_P(filepath, T_STRING)) {
            pm_options_free(options);
            rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected String)", rb_obj_class(filepath));
        }

        pm_options_filepath_set(options, RSTRING_PTR(filepath));
    }
}

/**
 * Read options for methods that look like (source, **options).
 */
static void
string_options(int argc, VALUE *argv, pm_string_t *input, pm_options_t *options) {
    VALUE string;
    VALUE keywords;
    rb_scan_args(argc, argv, "1:", &string, &keywords);

    extract_options(options, Qnil, keywords);
    input_load_string(input, string);
}

/**
 * Read options for methods that look like (filepath, **options).
 */
static bool
file_options(int argc, VALUE *argv, pm_string_t *input, pm_options_t *options) {
    VALUE filepath;
    VALUE keywords;
    rb_scan_args(argc, argv, "1:", &filepath, &keywords);

    extract_options(options, filepath, keywords);

    if (!pm_string_mapped_init(input, (const char *) pm_string_source(&options->filepath))) {
        pm_options_free(options);
        return false;
    }

    return true;
}

/******************************************************************************/
/* Serializing the AST                                                        */
/******************************************************************************/

/**
 * Dump the AST corresponding to the given input to a string.
 */
static VALUE
dump_input(pm_string_t *input, const pm_options_t *options) {
    pm_buffer_t buffer;
    if (!pm_buffer_init(&buffer)) {
        rb_raise(rb_eNoMemError, "failed to allocate memory");
    }

    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(input), pm_string_length(input), options);

    pm_node_t *node = pm_parse(&parser);
    pm_serialize(&parser, node, &buffer);

    VALUE result = rb_str_new(pm_buffer_value(&buffer), pm_buffer_length(&buffer));
    pm_node_destroy(&parser, node);
    pm_buffer_free(&buffer);
    pm_parser_free(&parser);

    return result;
}

/**
 * call-seq:
 *   Prism::dump(source, **options) -> String
 *
 * Dump the AST corresponding to the given string to a string. For supported
 * options, see Prism::parse.
 */
static VALUE
dump(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    string_options(argc, argv, &input, &options);

#ifdef PRISM_DEBUG_MODE_BUILD
    size_t length = pm_string_length(&input);
    char* dup = malloc(length);
    memcpy(dup, pm_string_source(&input), length);
    pm_string_constant_init(&input, dup, length);
#endif

    VALUE value = dump_input(&input, &options);

#ifdef PRISM_DEBUG_MODE_BUILD
    free(dup);
#endif

    pm_string_free(&input);
    pm_options_free(&options);

    return value;
}

/**
 * call-seq:
 *   Prism::dump_file(filepath, **options) -> String
 *
 * Dump the AST corresponding to the given file to a string. For supported
 * options, see Prism::parse.
 */
static VALUE
dump_file(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    if (!file_options(argc, argv, &input, &options)) return Qnil;

    VALUE value = dump_input(&input, &options);
    pm_string_free(&input);
    pm_options_free(&options);

    return value;
}

/******************************************************************************/
/* Extracting values for the parse result                                     */
/******************************************************************************/

/**
 * Extract the comments out of the parser into an array.
 */
static VALUE
parser_comments(pm_parser_t *parser, VALUE source) {
    VALUE comments = rb_ary_new();

    for (pm_comment_t *comment = (pm_comment_t *) parser->comment_list.head; comment != NULL; comment = (pm_comment_t *) comment->node.next) {
        VALUE location_argv[] = {
            source,
            LONG2FIX(comment->start - parser->start),
            LONG2FIX(comment->end - comment->start)
        };

        VALUE type;
        switch (comment->type) {
            case PM_COMMENT_INLINE:
                type = rb_cPrismInlineComment;
                break;
            case PM_COMMENT_EMBDOC:
                type = rb_cPrismEmbDocComment;
                break;
            case PM_COMMENT___END__:
                type = rb_cPrismDATAComment;
                break;
            default:
                type = rb_cPrismInlineComment;
                break;
        }

        VALUE comment_argv[] = { rb_class_new_instance(3, location_argv, rb_cPrismLocation) };
        rb_ary_push(comments, rb_class_new_instance(1, comment_argv, type));
    }

    return comments;
}

/**
 * Extract the magic comments out of the parser into an array.
 */
static VALUE
parser_magic_comments(pm_parser_t *parser, VALUE source) {
    VALUE magic_comments = rb_ary_new();

    for (pm_magic_comment_t *magic_comment = (pm_magic_comment_t *) parser->magic_comment_list.head; magic_comment != NULL; magic_comment = (pm_magic_comment_t *) magic_comment->node.next) {
        VALUE key_loc_argv[] = {
            source,
            LONG2FIX(magic_comment->key_start - parser->start),
            LONG2FIX(magic_comment->key_length)
        };

        VALUE value_loc_argv[] = {
            source,
            LONG2FIX(magic_comment->value_start - parser->start),
            LONG2FIX(magic_comment->value_length)
        };

        VALUE magic_comment_argv[] = {
            rb_class_new_instance(3, key_loc_argv, rb_cPrismLocation),
            rb_class_new_instance(3, value_loc_argv, rb_cPrismLocation)
        };

        rb_ary_push(magic_comments, rb_class_new_instance(2, magic_comment_argv, rb_cPrismMagicComment));
    }

    return magic_comments;
}

/**
 * Extract the errors out of the parser into an array.
 */
static VALUE
parser_errors(pm_parser_t *parser, rb_encoding *encoding, VALUE source) {
    VALUE errors = rb_ary_new();
    pm_diagnostic_t *error;

    for (error = (pm_diagnostic_t *) parser->error_list.head; error != NULL; error = (pm_diagnostic_t *) error->node.next) {
        VALUE location_argv[] = {
            source,
            LONG2FIX(error->start - parser->start),
            LONG2FIX(error->end - error->start)
        };

        VALUE error_argv[] = {
            rb_enc_str_new_cstr(error->message, encoding),
            rb_class_new_instance(3, location_argv, rb_cPrismLocation)
        };

        rb_ary_push(errors, rb_class_new_instance(2, error_argv, rb_cPrismParseError));
    }

    return errors;
}

/**
 * Extract the warnings out of the parser into an array.
 */
static VALUE
parser_warnings(pm_parser_t *parser, rb_encoding *encoding, VALUE source) {
    VALUE warnings = rb_ary_new();
    pm_diagnostic_t *warning;

    for (warning = (pm_diagnostic_t *) parser->warning_list.head; warning != NULL; warning = (pm_diagnostic_t *) warning->node.next) {
        VALUE location_argv[] = {
            source,
            LONG2FIX(warning->start - parser->start),
            LONG2FIX(warning->end - warning->start)
        };

        VALUE warning_argv[] = {
            rb_enc_str_new_cstr(warning->message, encoding),
            rb_class_new_instance(3, location_argv, rb_cPrismLocation)
        };

        rb_ary_push(warnings, rb_class_new_instance(2, warning_argv, rb_cPrismParseWarning));
    }

    return warnings;
}

/******************************************************************************/
/* Lexing Ruby code                                                           */
/******************************************************************************/

/**
 * This struct gets stored in the parser and passed in to the lex callback any
 * time a new token is found. We use it to store the necessary information to
 * initialize a Token instance.
 */
typedef struct {
    VALUE source;
    VALUE tokens;
    rb_encoding *encoding;
} parse_lex_data_t;

/**
 * This is passed as a callback to the parser. It gets called every time a new
 * token is found. Once found, we initialize a new instance of Token and push it
 * onto the tokens array.
 */
static void
parse_lex_token(void *data, pm_parser_t *parser, pm_token_t *token) {
    parse_lex_data_t *parse_lex_data = (parse_lex_data_t *) parser->lex_callback->data;

    VALUE yields = rb_ary_new_capa(2);
    rb_ary_push(yields, pm_token_new(parser, token, parse_lex_data->encoding, parse_lex_data->source));
    rb_ary_push(yields, INT2FIX(parser->lex_state));

    rb_ary_push(parse_lex_data->tokens, yields);
}

/**
 * This is called whenever the encoding changes based on the magic comment at
 * the top of the file. We use it to update the encoding that we are using to
 * create tokens.
 */
static void
parse_lex_encoding_changed_callback(pm_parser_t *parser) {
    parse_lex_data_t *parse_lex_data = (parse_lex_data_t *) parser->lex_callback->data;
    parse_lex_data->encoding = rb_enc_find(parser->encoding.name);

    // Since the encoding changed, we need to go back and change the encoding of
    // the tokens that were already lexed. This is only going to end up being
    // one or two tokens, since the encoding can only change at the top of the
    // file.
    VALUE tokens = parse_lex_data->tokens;
    for (long index = 0; index < RARRAY_LEN(tokens); index++) {
        VALUE yields = rb_ary_entry(tokens, index);
        VALUE token = rb_ary_entry(yields, 0);

        VALUE value = rb_ivar_get(token, rb_intern("@value"));
        rb_enc_associate(value, parse_lex_data->encoding);
        ENC_CODERANGE_CLEAR(value);
    }
}

/**
 * Parse the given input and return a ParseResult containing just the tokens or
 * the nodes and tokens.
 */
static VALUE
parse_lex_input(pm_string_t *input, const pm_options_t *options, bool return_nodes) {
    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(input), pm_string_length(input), options);
    pm_parser_register_encoding_changed_callback(&parser, parse_lex_encoding_changed_callback);

    VALUE offsets = rb_ary_new();
    VALUE source_argv[] = { rb_str_new((const char *) pm_string_source(input), pm_string_length(input)), ULONG2NUM(parser.start_line), offsets };
    VALUE source = rb_class_new_instance(3, source_argv, rb_cPrismSource);

    parse_lex_data_t parse_lex_data = {
        .source = source,
        .tokens = rb_ary_new(),
        .encoding = rb_utf8_encoding()
    };

    parse_lex_data_t *data = &parse_lex_data;
    pm_lex_callback_t lex_callback = (pm_lex_callback_t) {
        .data = (void *) data,
        .callback = parse_lex_token,
    };

    parser.lex_callback = &lex_callback;
    pm_node_t *node = pm_parse(&parser);

    // Here we need to update the source range to have the correct newline
    // offsets. We do it here because we've already created the object and given
    // it over to all of the tokens.
    for (size_t index = 0; index < parser.newline_list.size; index++) {
        rb_ary_push(offsets, INT2FIX(parser.newline_list.offsets[index]));
    }

    VALUE value;
    if (return_nodes) {
        value = rb_ary_new_capa(2);
        rb_ary_push(value, pm_ast_new(&parser, node, parse_lex_data.encoding));
        rb_ary_push(value, parse_lex_data.tokens);
    } else {
        value = parse_lex_data.tokens;
    }

    VALUE result_argv[] = {
        value,
        parser_comments(&parser, source),
        parser_magic_comments(&parser, source),
        parser_errors(&parser, parse_lex_data.encoding, source),
        parser_warnings(&parser, parse_lex_data.encoding, source),
        source
    };

    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);
    return rb_class_new_instance(6, result_argv, rb_cPrismParseResult);
}

/**
 * call-seq:
 *   Prism::lex(source, **options) -> Array
 *
 * Return an array of Token instances corresponding to the given string. For
 * supported options, see Prism::parse.
 */
static VALUE
lex(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    string_options(argc, argv, &input, &options);

    VALUE result = parse_lex_input(&input, &options, false);
    pm_string_free(&input);
    pm_options_free(&options);

    return result;
}

/**
 * call-seq:
 *   Prism::lex_file(filepath, **options) -> Array
 *
 * Return an array of Token instances corresponding to the given file. For
 * supported options, see Prism::parse.
 */
static VALUE
lex_file(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    if (!file_options(argc, argv, &input, &options)) return Qnil;

    VALUE value = parse_lex_input(&input, &options, false);
    pm_string_free(&input);
    pm_options_free(&options);

    return value;
}

/******************************************************************************/
/* Parsing Ruby code                                                          */
/******************************************************************************/

/**
 * Parse the given input and return a ParseResult instance.
 */
static VALUE
parse_input(pm_string_t *input, const pm_options_t *options) {
    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(input), pm_string_length(input), options);

    pm_node_t *node = pm_parse(&parser);
    rb_encoding *encoding = rb_enc_find(parser.encoding.name);

    VALUE source = pm_source_new(&parser, encoding);
    VALUE result_argv[] = {
        pm_ast_new(&parser, node, encoding),
        parser_comments(&parser, source),
        parser_magic_comments(&parser, source),
        parser_errors(&parser, encoding, source),
        parser_warnings(&parser, encoding, source),
        source
    };

    VALUE result = rb_class_new_instance(6, result_argv, rb_cPrismParseResult);

    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);

    return result;
}

/**
 * call-seq:
 *   Prism::parse(source, **options) -> ParseResult
 *
 * Parse the given string and return a ParseResult instance. The options that
 * are supported are:
 *
 * * `filepath` - the filepath of the source being parsed. This should be a
 *       string or nil
 * * `encoding` - the encoding of the source being parsed. This should be an
 *       encoding or nil
 * * `line` - the line number that the parse starts on. This should be an
 *       integer or nil. Note that this is 1-indexed.
 * * `frozen_string_literal` - whether or not the frozen string literal pragma
 *       has been set. This should be a boolean or nil.
 * * `verbose` - the current level of verbosity. This controls whether or not
 *       the parser emits warnings. This should be a boolean or nil.
 * * `scopes` - the locals that are in scope surrounding the code that is being
 *       parsed. This should be an array of arrays of symbols or nil.
 */
static VALUE
parse(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    string_options(argc, argv, &input, &options);

#ifdef PRISM_DEBUG_MODE_BUILD
    size_t length = pm_string_length(&input);
    char* dup = malloc(length);
    memcpy(dup, pm_string_source(&input), length);
    pm_string_constant_init(&input, dup, length);
#endif

    VALUE value = parse_input(&input, &options);

#ifdef PRISM_DEBUG_MODE_BUILD
    free(dup);
#endif

    pm_string_free(&input);
    pm_options_free(&options);
    return value;
}

/**
 * call-seq:
 *   Prism::parse_file(filepath, **options) -> ParseResult
 *
 * Parse the given file and return a ParseResult instance. For supported
 * options, see Prism::parse.
 */
static VALUE
parse_file(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    if (!file_options(argc, argv, &input, &options)) return Qnil;

    VALUE value = parse_input(&input, &options);
    pm_string_free(&input);
    pm_options_free(&options);

    return value;
}

/**
 * Parse the given input and return an array of Comment objects.
 */
static VALUE
parse_input_comments(pm_string_t *input, const pm_options_t *options) {
    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(input), pm_string_length(input), options);

    pm_node_t *node = pm_parse(&parser);
    rb_encoding *encoding = rb_enc_find(parser.encoding.name);

    VALUE source = pm_source_new(&parser, encoding);
    VALUE comments = parser_comments(&parser, source);

    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);

    return comments;
}

/**
 * call-seq:
 *   Prism::parse_comments(source, **options) -> Array
 *
 * Parse the given string and return an array of Comment objects. For supported
 * options, see Prism::parse.
 */
static VALUE
parse_comments(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    string_options(argc, argv, &input, &options);

    VALUE result = parse_input_comments(&input, &options);
    pm_string_free(&input);
    pm_options_free(&options);

    return result;
}

/**
 * call-seq:
 *   Prism::parse_file_comments(filepath, **options) -> Array
 *
 * Parse the given file and return an array of Comment objects. For supported
 * options, see Prism::parse.
 */
static VALUE
parse_file_comments(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    if (!file_options(argc, argv, &input, &options)) return Qnil;

    VALUE value = parse_input_comments(&input, &options);
    pm_string_free(&input);
    pm_options_free(&options);

    return value;
}

/**
 * call-seq:
 *   Prism::parse_lex(source, **options) -> ParseResult
 *
 * Parse the given string and return a ParseResult instance that contains a
 * 2-element array, where the first element is the AST and the second element is
 * an array of Token instances.
 *
 * This API is only meant to be used in the case where you need both the AST and
 * the tokens. If you only need one or the other, use either Prism::parse or
 * Prism::lex.
 *
 * For supported options, see Prism::parse.
 */
static VALUE
parse_lex(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    string_options(argc, argv, &input, &options);

    VALUE value = parse_lex_input(&input, &options, true);
    pm_string_free(&input);
    pm_options_free(&options);

    return value;
}

/**
 * call-seq:
 *   Prism::parse_lex_file(filepath, **options) -> ParseResult
 *
 * Parse the given file and return a ParseResult instance that contains a
 * 2-element array, where the first element is the AST and the second element is
 * an array of Token instances.
 *
 * This API is only meant to be used in the case where you need both the AST and
 * the tokens. If you only need one or the other, use either Prism::parse_file
 * or Prism::lex_file.
 *
 * For supported options, see Prism::parse.
 */
static VALUE
parse_lex_file(int argc, VALUE *argv, VALUE self) {
    pm_string_t input;
    pm_options_t options = { 0 };
    if (!file_options(argc, argv, &input, &options)) return Qnil;

    VALUE value = parse_lex_input(&input, &options, true);
    pm_string_free(&input);
    pm_options_free(&options);

    return value;
}

/******************************************************************************/
/* Utility functions exposed to make testing easier                           */
/******************************************************************************/

/**
 * call-seq:
 *   Debug::named_captures(source) -> Array
 *
 * Returns an array of strings corresponding to the named capture groups in the
 * given source string. If prism was unable to parse the regular expression,
 * this function returns nil.
 */
static VALUE
named_captures(VALUE self, VALUE source) {
    pm_string_list_t string_list = { 0 };

    if (!pm_regexp_named_capture_group_names((const uint8_t *) RSTRING_PTR(source), RSTRING_LEN(source), &string_list, false, &pm_encoding_utf_8)) {
        pm_string_list_free(&string_list);
        return Qnil;
    }

    VALUE names = rb_ary_new();
    for (size_t index = 0; index < string_list.length; index++) {
        const pm_string_t *string = &string_list.strings[index];
        rb_ary_push(names, rb_str_new((const char *) pm_string_source(string), pm_string_length(string)));
    }

    pm_string_list_free(&string_list);
    return names;
}

/**
 * call-seq:
 *   Debug::memsize(source) -> { length: xx, memsize: xx, node_count: xx }
 *
 * Return a hash of information about the given source string's memory usage.
 */
static VALUE
memsize(VALUE self, VALUE string) {
    pm_parser_t parser;
    size_t length = RSTRING_LEN(string);
    pm_parser_init(&parser, (const uint8_t *) RSTRING_PTR(string), length, NULL);

    pm_node_t *node = pm_parse(&parser);
    pm_memsize_t memsize;
    pm_node_memsize(node, &memsize);

    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("length")), INT2FIX(length));
    rb_hash_aset(result, ID2SYM(rb_intern("memsize")), INT2FIX(memsize.memsize));
    rb_hash_aset(result, ID2SYM(rb_intern("node_count")), INT2FIX(memsize.node_count));
    return result;
}

/**
 * call-seq:
 *   Debug::profile_file(filepath) -> nil
 *
 * Parse the file, but do nothing with the result. This is used to profile the
 * parser for memory and speed.
 */
static VALUE
profile_file(VALUE self, VALUE filepath) {
    pm_string_t input;

    const char *checked = check_string(filepath);
    if (!pm_string_mapped_init(&input, checked)) return Qnil;

    pm_options_t options = { 0 };
    pm_options_filepath_set(&options, checked);

    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(&input), pm_string_length(&input), &options);

    pm_node_t *node = pm_parse(&parser);
    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);
    pm_options_free(&options);
    pm_string_free(&input);

    return Qnil;
}

/**
 * call-seq:
 *   Debug::inspect_node(source) -> inspected
 *
 * Inspect the AST that represents the given source using the prism pretty print
 * as opposed to the Ruby implementation.
 */
static VALUE
inspect_node(VALUE self, VALUE source) {
    pm_string_t input;
    input_load_string(&input, source);

    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(&input), pm_string_length(&input), NULL);

    pm_node_t *node = pm_parse(&parser);
    pm_buffer_t buffer = { 0 };

    pm_prettyprint(&buffer, &parser, node);

    rb_encoding *encoding = rb_enc_find(parser.encoding.name);
    VALUE string = rb_enc_str_new(pm_buffer_value(&buffer), pm_buffer_length(&buffer), encoding);

    pm_buffer_free(&buffer);
    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);

    return string;
}

/******************************************************************************/
/* Initialization of the extension                                            */
/******************************************************************************/

/**
 * The init function that Ruby calls when loading this extension.
 */
RUBY_FUNC_EXPORTED void
Init_prism(void) {
    // Make sure that the prism library version matches the expected version.
    // Otherwise something was compiled incorrectly.
    if (strcmp(pm_version(), EXPECTED_PRISM_VERSION) != 0) {
        rb_raise(
            rb_eRuntimeError,
            "The prism library version (%s) does not match the expected version (%s)",
            pm_version(),
            EXPECTED_PRISM_VERSION
        );
    }

    // Grab up references to all of the constants that we're going to need to
    // reference throughout this extension.
    rb_cPrism = rb_define_module("Prism");
    rb_cPrismNode = rb_define_class_under(rb_cPrism, "Node", rb_cObject);
    rb_cPrismSource = rb_define_class_under(rb_cPrism, "Source", rb_cObject);
    rb_cPrismToken = rb_define_class_under(rb_cPrism, "Token", rb_cObject);
    rb_cPrismLocation = rb_define_class_under(rb_cPrism, "Location", rb_cObject);
    rb_cPrismComment = rb_define_class_under(rb_cPrism, "Comment", rb_cObject);
    rb_cPrismInlineComment = rb_define_class_under(rb_cPrism, "InlineComment", rb_cPrismComment);
    rb_cPrismEmbDocComment = rb_define_class_under(rb_cPrism, "EmbDocComment", rb_cPrismComment);
    rb_cPrismDATAComment = rb_define_class_under(rb_cPrism, "DATAComment", rb_cPrismComment);
    rb_cPrismMagicComment = rb_define_class_under(rb_cPrism, "MagicComment", rb_cObject);
    rb_cPrismParseError = rb_define_class_under(rb_cPrism, "ParseError", rb_cObject);
    rb_cPrismParseWarning = rb_define_class_under(rb_cPrism, "ParseWarning", rb_cObject);
    rb_cPrismParseResult = rb_define_class_under(rb_cPrism, "ParseResult", rb_cObject);

    // Intern all of the options that we support so that we don't have to do it
    // every time we parse.
    rb_option_id_filepath = rb_intern_const("filepath");
    rb_option_id_encoding = rb_intern_const("encoding");
    rb_option_id_line = rb_intern_const("line");
    rb_option_id_frozen_string_literal = rb_intern_const("frozen_string_literal");
    rb_option_id_verbose = rb_intern_const("verbose");
    rb_option_id_scopes = rb_intern_const("scopes");

    /**
     * The version of the prism library.
     */
    rb_define_const(rb_cPrism, "VERSION", rb_str_new2(EXPECTED_PRISM_VERSION));

    /**
     * The backend of the parser that prism is using to parse Ruby code. This
     * can be either :CEXT or :FFI. On runtimes that support C extensions, we
     * default to :CEXT. Otherwise we use :FFI.
     */
    rb_define_const(rb_cPrism, "BACKEND", ID2SYM(rb_intern("CEXT")));

    // First, the functions that have to do with lexing and parsing.
    rb_define_singleton_method(rb_cPrism, "dump", dump, -1);
    rb_define_singleton_method(rb_cPrism, "dump_file", dump_file, -1);
    rb_define_singleton_method(rb_cPrism, "lex", lex, -1);
    rb_define_singleton_method(rb_cPrism, "lex_file", lex_file, -1);
    rb_define_singleton_method(rb_cPrism, "parse", parse, -1);
    rb_define_singleton_method(rb_cPrism, "parse_file", parse_file, -1);
    rb_define_singleton_method(rb_cPrism, "parse_comments", parse_comments, -1);
    rb_define_singleton_method(rb_cPrism, "parse_file_comments", parse_file_comments, -1);
    rb_define_singleton_method(rb_cPrism, "parse_lex", parse_lex, -1);
    rb_define_singleton_method(rb_cPrism, "parse_lex_file", parse_lex_file, -1);

    // Next, the functions that will be called by the parser to perform various
    // internal tasks. We expose these to make them easier to test.
    VALUE rb_cPrismDebug = rb_define_module_under(rb_cPrism, "Debug");
    rb_define_singleton_method(rb_cPrismDebug, "named_captures", named_captures, 1);
    rb_define_singleton_method(rb_cPrismDebug, "memsize", memsize, 1);
    rb_define_singleton_method(rb_cPrismDebug, "profile_file", profile_file, 1);
    rb_define_singleton_method(rb_cPrismDebug, "inspect_node", inspect_node, 1);

    // Next, initialize the other APIs.
    Init_prism_api_node();
    Init_prism_pack();
}
