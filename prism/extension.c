#include "prism/extension.h"

// NOTE: this file should contain only bindings.
// All non-trivial logic should be in librubyparser so it can be shared its the various callers.

VALUE rb_cPrism;
VALUE rb_cPrismNode;
VALUE rb_cPrismSource;
VALUE rb_cPrismToken;
VALUE rb_cPrismLocation;

VALUE rb_cPrismComment;
VALUE rb_cPrismMagicComment;
VALUE rb_cPrismParseError;
VALUE rb_cPrismParseWarning;
VALUE rb_cPrismParseResult;

/******************************************************************************/
/* IO of Ruby code                                                            */
/******************************************************************************/

// Check if the given VALUE is a string. If it's nil, then return NULL. If it's
// not a string, then raise a type error. Otherwise return the VALUE as a C
// string.
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

// Load the contents and size of the given string into the given pm_string_t.
static void
input_load_string(pm_string_t *input, VALUE string) {
    // Check if the string is a string. If it's not, then raise a type error.
    if (!RB_TYPE_P(string, T_STRING)) {
        rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected String)", rb_obj_class(string));
    }

    pm_string_constant_init(input, RSTRING_PTR(string), RSTRING_LEN(string));
}

/******************************************************************************/
/* Serializing the AST                                                        */
/******************************************************************************/

// Dump the AST corresponding to the given input to a string.
static VALUE
dump_input(pm_string_t *input, const char *filepath) {
    pm_buffer_t buffer;
    if (!pm_buffer_init(&buffer)) {
        rb_raise(rb_eNoMemError, "failed to allocate memory");
    }

    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(input), pm_string_length(input), filepath);

    pm_node_t *node = pm_parse(&parser);
    pm_serialize(&parser, node, &buffer);

    VALUE result = rb_str_new(pm_buffer_value(&buffer), pm_buffer_length(&buffer));
    pm_node_destroy(&parser, node);
    pm_buffer_free(&buffer);
    pm_parser_free(&parser);

    return result;
}

// Dump the AST corresponding to the given string to a string.
static VALUE
dump(int argc, VALUE *argv, VALUE self) {
    VALUE string;
    VALUE filepath;
    rb_scan_args(argc, argv, "11", &string, &filepath);

    pm_string_t input;
    input_load_string(&input, string);

#ifdef PRISM_DEBUG_MODE_BUILD
    size_t length = pm_string_length(&input);
    char* dup = malloc(length);
    memcpy(dup, pm_string_source(&input), length);
    pm_string_constant_init(&input, dup, length);
#endif

    VALUE value = dump_input(&input, check_string(filepath));

#ifdef PRISM_DEBUG_MODE_BUILD
    free(dup);
#endif

    return value;
}

// Dump the AST corresponding to the given file to a string.
static VALUE
dump_file(VALUE self, VALUE filepath) {
    pm_string_t input;

    const char *checked = check_string(filepath);
    if (!pm_string_mapped_init(&input, checked)) return Qnil;

    VALUE value = dump_input(&input, checked);
    pm_string_free(&input);

    return value;
}

/******************************************************************************/
/* Extracting values for the parse result                                     */
/******************************************************************************/

// Extract the comments out of the parser into an array.
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
                type = ID2SYM(rb_intern("inline"));
                break;
            case PM_COMMENT_EMBDOC:
                type = ID2SYM(rb_intern("embdoc"));
                break;
            case PM_COMMENT___END__:
                type = ID2SYM(rb_intern("__END__"));
                break;
            default:
                type = ID2SYM(rb_intern("inline"));
                break;
        }

        VALUE comment_argv[] = { type, rb_class_new_instance(3, location_argv, rb_cPrismLocation) };
        rb_ary_push(comments, rb_class_new_instance(2, comment_argv, rb_cPrismComment));
    }

    return comments;
}

// Extract the magic comments out of the parser into an array.
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

// Extract the errors out of the parser into an array.
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

// Extract the warnings out of the parser into an array.
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

// This struct gets stored in the parser and passed in to the lex callback any
// time a new token is found. We use it to store the necessary information to
// initialize a Token instance.
typedef struct {
    VALUE source;
    VALUE tokens;
    rb_encoding *encoding;
} parse_lex_data_t;

// This is passed as a callback to the parser. It gets called every time a new
// token is found. Once found, we initialize a new instance of Token and push it
// onto the tokens array.
static void
parse_lex_token(void *data, pm_parser_t *parser, pm_token_t *token) {
    parse_lex_data_t *parse_lex_data = (parse_lex_data_t *) parser->lex_callback->data;

    VALUE yields = rb_ary_new_capa(2);
    rb_ary_push(yields, pm_token_new(parser, token, parse_lex_data->encoding, parse_lex_data->source));
    rb_ary_push(yields, INT2FIX(parser->lex_state));

    rb_ary_push(parse_lex_data->tokens, yields);
}

// This is called whenever the encoding changes based on the magic comment at
// the top of the file. We use it to update the encoding that we are using to
// create tokens.
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

// Parse the given input and return a ParseResult containing just the tokens or
// the nodes and tokens.
static VALUE
parse_lex_input(pm_string_t *input, const char *filepath, bool return_nodes) {
    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(input), pm_string_length(input), filepath);
    pm_parser_register_encoding_changed_callback(&parser, parse_lex_encoding_changed_callback);

    VALUE offsets = rb_ary_new();
    VALUE source_argv[] = { rb_str_new((const char *) pm_string_source(input), pm_string_length(input)), offsets };
    VALUE source = rb_class_new_instance(2, source_argv, rb_cPrismSource);

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

// Return an array of tokens corresponding to the given string.
static VALUE
lex(int argc, VALUE *argv, VALUE self) {
    VALUE string;
    VALUE filepath;
    rb_scan_args(argc, argv, "11", &string, &filepath);

    pm_string_t input;
    input_load_string(&input, string);

    return parse_lex_input(&input, check_string(filepath), false);
}

// Return an array of tokens corresponding to the given file.
static VALUE
lex_file(VALUE self, VALUE filepath) {
    pm_string_t input;

    const char *checked = check_string(filepath);
    if (!pm_string_mapped_init(&input, checked)) return Qnil;

    VALUE value = parse_lex_input(&input, checked, false);
    pm_string_free(&input);

    return value;
}

/******************************************************************************/
/* Parsing Ruby code                                                          */
/******************************************************************************/

// Parse the given input and return a ParseResult instance.
static VALUE
parse_input(pm_string_t *input, const char *filepath) {
    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(input), pm_string_length(input), filepath);

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

// Parse the given string and return a ParseResult instance.
static VALUE
parse(int argc, VALUE *argv, VALUE self) {
    VALUE string;
    VALUE filepath;
    rb_scan_args(argc, argv, "11", &string, &filepath);

    pm_string_t input;
    input_load_string(&input, string);

#ifdef PRISM_DEBUG_MODE_BUILD
    size_t length = pm_string_length(&input);
    char* dup = malloc(length);
    memcpy(dup, pm_string_source(&input), length);
    pm_string_constant_init(&input, dup, length);
#endif

    VALUE value = parse_input(&input, check_string(filepath));

#ifdef PRISM_DEBUG_MODE_BUILD
    free(dup);
#endif

    return value;
}

// Parse the given file and return a ParseResult instance.
static VALUE
parse_file(VALUE self, VALUE filepath) {
    pm_string_t input;

    const char *checked = check_string(filepath);
    if (!pm_string_mapped_init(&input, checked)) return Qnil;

    VALUE value = parse_input(&input, checked);
    pm_string_free(&input);

    return value;
}

// Parse the given string and return a ParseResult instance.
static VALUE
parse_lex(int argc, VALUE *argv, VALUE self) {
    VALUE string;
    VALUE filepath;
    rb_scan_args(argc, argv, "11", &string, &filepath);

    pm_string_t input;
    input_load_string(&input, string);

    VALUE value = parse_lex_input(&input, check_string(filepath), true);
    pm_string_free(&input);

    return value;
}

// Parse and lex the given file and return a ParseResult instance.
static VALUE
parse_lex_file(VALUE self, VALUE filepath) {
    pm_string_t input;

    const char *checked = check_string(filepath);
    if (!pm_string_mapped_init(&input, checked)) return Qnil;

    VALUE value = parse_lex_input(&input, checked, true);
    pm_string_free(&input);

    return value;
}

/******************************************************************************/
/* Utility functions exposed to make testing easier                           */
/******************************************************************************/

// Returns an array of strings corresponding to the named capture groups in the
// given source string. If prism was unable to parse the regular expression, this
// function returns nil.
static VALUE
named_captures(VALUE self, VALUE source) {
    pm_string_list_t string_list;
    pm_string_list_init(&string_list);

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

// Return a hash of information about the given source string's memory usage.
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

// Parse the file, but do nothing with the result. This is used to profile the
// parser for memory and speed.
static VALUE
profile_file(VALUE self, VALUE filepath) {
    pm_string_t input;

    const char *checked = check_string(filepath);
    if (!pm_string_mapped_init(&input, checked)) return Qnil;

    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(&input), pm_string_length(&input), checked);

    pm_node_t *node = pm_parse(&parser);
    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);

    pm_string_free(&input);

    return Qnil;
}

// Parse the file and serialize the result. This is mostly used to test this
// path since it is used by client libraries.
static VALUE
parse_serialize_file_metadata(VALUE self, VALUE filepath, VALUE metadata) {
    pm_string_t input;
    pm_buffer_t buffer;
    pm_buffer_init(&buffer);

    const char *checked = check_string(filepath);
    if (!pm_string_mapped_init(&input, checked)) return Qnil;

    pm_parse_serialize(pm_string_source(&input), pm_string_length(&input), &buffer, check_string(metadata));
    VALUE result = rb_str_new(pm_buffer_value(&buffer), pm_buffer_length(&buffer));

    pm_string_free(&input);
    pm_buffer_free(&buffer);
    return result;
}

/******************************************************************************/
/* Initialization of the extension                                            */
/******************************************************************************/

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
    rb_cPrismMagicComment = rb_define_class_under(rb_cPrism, "MagicComment", rb_cObject);
    rb_cPrismParseError = rb_define_class_under(rb_cPrism, "ParseError", rb_cObject);
    rb_cPrismParseWarning = rb_define_class_under(rb_cPrism, "ParseWarning", rb_cObject);
    rb_cPrismParseResult = rb_define_class_under(rb_cPrism, "ParseResult", rb_cObject);

    // Define the version string here so that we can use the constants defined
    // in prism.h.
    rb_define_const(rb_cPrism, "VERSION", rb_str_new2(EXPECTED_PRISM_VERSION));
    rb_define_const(rb_cPrism, "BACKEND", ID2SYM(rb_intern("CExtension")));

    // First, the functions that have to do with lexing and parsing.
    rb_define_singleton_method(rb_cPrism, "dump", dump, -1);
    rb_define_singleton_method(rb_cPrism, "dump_file", dump_file, 1);
    rb_define_singleton_method(rb_cPrism, "lex", lex, -1);
    rb_define_singleton_method(rb_cPrism, "lex_file", lex_file, 1);
    rb_define_singleton_method(rb_cPrism, "parse", parse, -1);
    rb_define_singleton_method(rb_cPrism, "parse_file", parse_file, 1);
    rb_define_singleton_method(rb_cPrism, "parse_lex", parse_lex, -1);
    rb_define_singleton_method(rb_cPrism, "parse_lex_file", parse_lex_file, 1);

    // Next, the functions that will be called by the parser to perform various
    // internal tasks. We expose these to make them easier to test.
    VALUE rb_cPrismDebug = rb_define_module_under(rb_cPrism, "Debug");
    rb_define_singleton_method(rb_cPrismDebug, "named_captures", named_captures, 1);
    rb_define_singleton_method(rb_cPrismDebug, "memsize", memsize, 1);
    rb_define_singleton_method(rb_cPrismDebug, "profile_file", profile_file, 1);
    rb_define_singleton_method(rb_cPrismDebug, "parse_serialize_file_metadata", parse_serialize_file_metadata, 2);

    // Next, initialize the other APIs.
    Init_prism_api_node();
    Init_prism_pack();
}
