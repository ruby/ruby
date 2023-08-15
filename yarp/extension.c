#include "yarp/extension.h"

VALUE rb_cYARP;
VALUE rb_cYARPSource;
VALUE rb_cYARPToken;
VALUE rb_cYARPLocation;

VALUE rb_cYARPComment;
VALUE rb_cYARPParseError;
VALUE rb_cYARPParseWarning;
VALUE rb_cYARPParseResult;

/******************************************************************************/
/* IO of Ruby code                                                            */
/******************************************************************************/

// Check if the given filepath is a string. If it's nil, then return NULL. If
// it's not a string, then raise a type error. Otherwise return the filepath as
// a C string.
static const char *
check_filepath(VALUE filepath) {
    // If the filepath is nil, then we don't need to do anything.
    if (NIL_P(filepath)) {
        return NULL;
    }

    // Check if the filepath is a string. If it's not, then raise a type error.
    if (!RB_TYPE_P(filepath, T_STRING)) {
        rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected String)", rb_obj_class(filepath));
    }

    // Otherwise, return the filepath as a C string.
    return StringValueCStr(filepath);
}

// Load the contents and size of the given string into the given yp_string_t.
static void
input_load_string(yp_string_t *input, VALUE string) {
    // Check if the string is a string. If it's not, then raise a type error.
    if (!RB_TYPE_P(string, T_STRING)) {
        rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected String)", rb_obj_class(string));
    }

    yp_string_constant_init(input, RSTRING_PTR(string), RSTRING_LEN(string));
}

/******************************************************************************/
/* Serializing the AST                                                        */
/******************************************************************************/

// Dump the AST corresponding to the given input to a string.
static VALUE
dump_input(yp_string_t *input, const char *filepath) {
    yp_buffer_t buffer;
    if (!yp_buffer_init(&buffer)) {
        rb_raise(rb_eNoMemError, "failed to allocate memory");
    }

    yp_parser_t parser;
    yp_parser_init(&parser, yp_string_source(input), yp_string_length(input), filepath);

    yp_node_t *node = yp_parse(&parser, false);
    yp_serialize(&parser, node, &buffer);

    VALUE result = rb_str_new(buffer.value, buffer.length);
    yp_node_destroy(&parser, node);
    yp_buffer_free(&buffer);
    yp_parser_free(&parser);

    return result;
}

// Dump the AST corresponding to the given string to a string.
static VALUE
dump(int argc, VALUE *argv, VALUE self) {
    VALUE string;
    VALUE filepath;
    rb_scan_args(argc, argv, "11", &string, &filepath);

    yp_string_t input;
    input_load_string(&input, string);
    return dump_input(&input, check_filepath(filepath));
}

// Dump the AST corresponding to the given file to a string.
static VALUE
dump_file(VALUE self, VALUE filepath) {
    yp_string_t input;

    const char *checked = check_filepath(filepath);
    if (!yp_string_mapped_init(&input, checked)) return Qnil;

    VALUE value = dump_input(&input, checked);
    yp_string_free(&input);

    return value;
}

/******************************************************************************/
/* Extracting values for the parse result                                     */
/******************************************************************************/

// Extract the comments out of the parser into an array.
static VALUE
parser_comments(yp_parser_t *parser, VALUE source) {
    VALUE comments = rb_ary_new();

    for (yp_comment_t *comment = (yp_comment_t *) parser->comment_list.head; comment != NULL; comment = (yp_comment_t *) comment->node.next) {
        VALUE location_argv[] = {
            source,
            LONG2FIX(comment->start - parser->start),
            LONG2FIX(comment->end - comment->start)
        };

        VALUE type;
        switch (comment->type) {
            case YP_COMMENT_INLINE:
                type = ID2SYM(rb_intern("inline"));
                break;
            case YP_COMMENT_EMBDOC:
                type = ID2SYM(rb_intern("embdoc"));
                break;
            case YP_COMMENT___END__:
                type = ID2SYM(rb_intern("__END__"));
                break;
            default:
                type = ID2SYM(rb_intern("inline"));
                break;
        }

        VALUE comment_argv[] = { type, rb_class_new_instance(3, location_argv, rb_cYARPLocation) };
        rb_ary_push(comments, rb_class_new_instance(2, comment_argv, rb_cYARPComment));
    }

    return comments;
}

// Extract the errors out of the parser into an array.
static VALUE
parser_errors(yp_parser_t *parser, rb_encoding *encoding, VALUE source) {
    VALUE errors = rb_ary_new();
    yp_diagnostic_t *error;

    for (error = (yp_diagnostic_t *) parser->error_list.head; error != NULL; error = (yp_diagnostic_t *) error->node.next) {
        VALUE location_argv[] = {
            source,
            LONG2FIX(error->start - parser->start),
            LONG2FIX(error->end - error->start)
        };

        VALUE error_argv[] = {
            rb_enc_str_new_cstr(error->message, encoding),
            rb_class_new_instance(3, location_argv, rb_cYARPLocation)
        };

        rb_ary_push(errors, rb_class_new_instance(2, error_argv, rb_cYARPParseError));
    }

    return errors;
}

// Extract the warnings out of the parser into an array.
static VALUE
parser_warnings(yp_parser_t *parser, rb_encoding *encoding, VALUE source) {
    VALUE warnings = rb_ary_new();
    yp_diagnostic_t *warning;

    for (warning = (yp_diagnostic_t *) parser->warning_list.head; warning != NULL; warning = (yp_diagnostic_t *) warning->node.next) {
        VALUE location_argv[] = {
            source,
            LONG2FIX(warning->start - parser->start),
            LONG2FIX(warning->end - warning->start)
        };

        VALUE warning_argv[] = {
            rb_enc_str_new_cstr(warning->message, encoding),
            rb_class_new_instance(3, location_argv, rb_cYARPLocation)
        };

        rb_ary_push(warnings, rb_class_new_instance(2, warning_argv, rb_cYARPParseWarning));
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
} lex_data_t;

// This is passed as a callback to the parser. It gets called every time a new
// token is found. Once found, we initialize a new instance of Token and push it
// onto the tokens array.
static void
lex_token(void *data, yp_parser_t *parser, yp_token_t *token) {
    lex_data_t *lex_data = (lex_data_t *) parser->lex_callback->data;

    VALUE yields = rb_ary_new_capa(2);
    rb_ary_push(yields, yp_token_new(parser, token, lex_data->encoding, lex_data->source));
    rb_ary_push(yields, INT2FIX(parser->lex_state));

    rb_ary_push(lex_data->tokens, yields);
}

// This is called whenever the encoding changes based on the magic comment at
// the top of the file. We use it to update the encoding that we are using to
// create tokens.
static void
lex_encoding_changed_callback(yp_parser_t *parser) {
    lex_data_t *lex_data = (lex_data_t *) parser->lex_callback->data;
    lex_data->encoding = rb_enc_find(parser->encoding.name);
}

// Return an array of tokens corresponding to the given source.
static VALUE
lex_input(yp_string_t *input, const char *filepath) {
    yp_parser_t parser;
    yp_parser_init(&parser, yp_string_source(input), yp_string_length(input), filepath);
    yp_parser_register_encoding_changed_callback(&parser, lex_encoding_changed_callback);

    VALUE offsets = rb_ary_new();
    VALUE source_argv[] = { rb_str_new(yp_string_source(input), yp_string_length(input)), offsets };
    VALUE source = rb_class_new_instance(2, source_argv, rb_cYARPSource);

    lex_data_t lex_data = {
        .source = source,
        .tokens = rb_ary_new(),
        .encoding = rb_utf8_encoding()
    };

    lex_data_t *data = &lex_data;
    yp_lex_callback_t lex_callback = (yp_lex_callback_t) {
        .data = (void *) data,
        .callback = lex_token,
    };

    parser.lex_callback = &lex_callback;
    yp_node_t *node = yp_parse(&parser, false);

    // Here we need to update the source range to have the correct newline
    // offsets. We do it here because we've already created the object and given
    // it over to all of the tokens.
    for (size_t index = 0; index < parser.newline_list.size; index++) {
        rb_ary_push(offsets, INT2FIX(parser.newline_list.offsets[index]));
    }

    VALUE result_argv[] = {
        lex_data.tokens,
        parser_comments(&parser, source),
        parser_errors(&parser, lex_data.encoding, source),
        parser_warnings(&parser, lex_data.encoding, source),
        source
    };

    VALUE result = rb_class_new_instance(5, result_argv, rb_cYARPParseResult);

    yp_node_destroy(&parser, node);
    yp_parser_free(&parser);

    return result;
}

// Return an array of tokens corresponding to the given string.
static VALUE
lex(int argc, VALUE *argv, VALUE self) {
    VALUE string;
    VALUE filepath;
    rb_scan_args(argc, argv, "11", &string, &filepath);

    yp_string_t input;
    input_load_string(&input, string);
    return lex_input(&input, check_filepath(filepath));
}

// Return an array of tokens corresponding to the given file.
static VALUE
lex_file(VALUE self, VALUE filepath) {
    yp_string_t input;

    const char *checked = check_filepath(filepath);
    if (!yp_string_mapped_init(&input, checked)) return Qnil;

    VALUE value = lex_input(&input, checked);
    yp_string_free(&input);

    return value;
}

/******************************************************************************/
/* Parsing Ruby code                                                          */
/******************************************************************************/

// Parse the given input and return a ParseResult instance.
static VALUE
parse_input(yp_string_t *input, const char *filepath) {
    yp_parser_t parser;
    yp_parser_init(&parser, yp_string_source(input), yp_string_length(input), filepath);

    yp_node_t *node = yp_parse(&parser, false);
    rb_encoding *encoding = rb_enc_find(parser.encoding.name);

    VALUE source = yp_source_new(&parser);
    VALUE result_argv[] = {
        yp_ast_new(&parser, node, encoding),
        parser_comments(&parser, source),
        parser_errors(&parser, encoding, source),
        parser_warnings(&parser, encoding, source),
        source
    };

    VALUE result = rb_class_new_instance(5, result_argv, rb_cYARPParseResult);

    yp_node_destroy(&parser, node);
    yp_parser_free(&parser);

    return result;
}

// Parse the given string and return a ParseResult instance.
static VALUE
parse(int argc, VALUE *argv, VALUE self) {
    VALUE string;
    VALUE filepath;
    rb_scan_args(argc, argv, "11", &string, &filepath);

    yp_string_t input;
    input_load_string(&input, string);

#ifdef YARP_DEBUG_MODE_BUILD
    size_t length = yp_string_length(&input);
    char* dup = malloc(length);
    memcpy(dup, yp_string_source(&input), length);
    yp_string_constant_init(&input, dup, length);
#endif

    VALUE value = parse_input(&input, check_filepath(filepath));

#ifdef YARP_DEBUG_MODE_BUILD
    free(dup);
#endif

    return value;
}

// Parse the given file and return a ParseResult instance.
static VALUE
parse_file(VALUE self, VALUE filepath) {
    yp_string_t input;

    const char *checked = check_filepath(filepath);
    if (!yp_string_mapped_init(&input, checked)) return Qnil;

    VALUE value = parse_input(&input, checked);
    yp_string_free(&input);

    return value;
}

/******************************************************************************/
/* Utility functions exposed to make testing easier                           */
/******************************************************************************/

// Returns an array of strings corresponding to the named capture groups in the
// given source string. If YARP was unable to parse the regular expression, this
// function returns nil.
static VALUE
named_captures(VALUE self, VALUE source) {
    yp_string_list_t string_list;
    yp_string_list_init(&string_list);

    if (!yp_regexp_named_capture_group_names(RSTRING_PTR(source), RSTRING_LEN(source), &string_list)) {
        yp_string_list_free(&string_list);
        return Qnil;
    }

    VALUE names = rb_ary_new();
    for (size_t index = 0; index < string_list.length; index++) {
        const yp_string_t *string = &string_list.strings[index];
        rb_ary_push(names, rb_str_new(yp_string_source(string), yp_string_length(string)));
    }

    yp_string_list_free(&string_list);
    return names;
}

// Accepts a source string and a type of unescaping and returns the unescaped
// version.
static VALUE
unescape(VALUE source, yp_unescape_type_t unescape_type) {
    yp_string_t result;

    if (yp_unescape_string(RSTRING_PTR(source), RSTRING_LEN(source), unescape_type, &result)) {
        VALUE str = rb_str_new(yp_string_source(&result), yp_string_length(&result));
        yp_string_free(&result);
        return str;
    } else {
        yp_string_free(&result);
        return Qnil;
    }
}

// Do not unescape anything in the given string. This is here to provide a
// consistent API.
static VALUE
unescape_none(VALUE self, VALUE source) {
    return unescape(source, YP_UNESCAPE_NONE);
}

// Minimally unescape the given string. This means effectively unescaping just
// the quotes of a string. Returns the unescaped string.
static VALUE
unescape_minimal(VALUE self, VALUE source) {
    return unescape(source, YP_UNESCAPE_MINIMAL);
}

// Unescape everything in the given string. Return the unescaped string.
static VALUE
unescape_all(VALUE self, VALUE source) {
    return unescape(source, YP_UNESCAPE_ALL);
}

// Return a hash of information about the given source string's memory usage.
static VALUE
memsize(VALUE self, VALUE string) {
    yp_parser_t parser;
    size_t length = RSTRING_LEN(string);
    yp_parser_init(&parser, RSTRING_PTR(string), length, NULL);

    yp_node_t *node = yp_parse(&parser, false);
    yp_memsize_t memsize;
    yp_node_memsize(node, &memsize);

    yp_node_destroy(&parser, node);
    yp_parser_free(&parser);

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
    yp_string_t input;

    const char *checked = check_filepath(filepath);
    if (!yp_string_mapped_init(&input, checked)) return Qnil;

    yp_parser_t parser;
    yp_parser_init(&parser, yp_string_source(&input), yp_string_length(&input), checked);

    yp_node_t *node = yp_parse(&parser, false);
    yp_node_destroy(&parser, node);
    yp_parser_free(&parser);

    return Qnil;
}

/******************************************************************************/
/* Initialization of the extension                                            */
/******************************************************************************/

RUBY_FUNC_EXPORTED void
Init_yarp(void) {
    // Make sure that the YARP library version matches the expected version.
    // Otherwise something was compiled incorrectly.
    if (strcmp(yp_version(), EXPECTED_YARP_VERSION) != 0) {
        rb_raise(
            rb_eRuntimeError,
            "The YARP library version (%s) does not match the expected version (%s)",
            yp_version(),
            EXPECTED_YARP_VERSION
        );
    }

    // Grab up references to all of the constants that we're going to need to
    // reference throughout this extension.
    rb_cYARP = rb_define_module("YARP");
    rb_cYARPSource = rb_define_class_under(rb_cYARP, "Source", rb_cObject);
    rb_cYARPToken = rb_define_class_under(rb_cYARP, "Token", rb_cObject);
    rb_cYARPLocation = rb_define_class_under(rb_cYARP, "Location", rb_cObject);
    rb_cYARPComment = rb_define_class_under(rb_cYARP, "Comment", rb_cObject);
    rb_cYARPParseError = rb_define_class_under(rb_cYARP, "ParseError", rb_cObject);
    rb_cYARPParseWarning = rb_define_class_under(rb_cYARP, "ParseWarning", rb_cObject);
    rb_cYARPParseResult = rb_define_class_under(rb_cYARP, "ParseResult", rb_cObject);

    // Define the version string here so that we can use the constants defined
    // in yarp.h.
    rb_define_const(rb_cYARP, "VERSION", rb_str_new2(EXPECTED_YARP_VERSION));

    // First, the functions that have to do with lexing and parsing.
    rb_define_singleton_method(rb_cYARP, "dump", dump, -1);
    rb_define_singleton_method(rb_cYARP, "dump_file", dump_file, 1);
    rb_define_singleton_method(rb_cYARP, "lex", lex, -1);
    rb_define_singleton_method(rb_cYARP, "lex_file", lex_file, 1);
    rb_define_singleton_method(rb_cYARP, "parse", parse, -1);
    rb_define_singleton_method(rb_cYARP, "parse_file", parse_file, 1);

    // Next, the functions that will be called by the parser to perform various
    // internal tasks. We expose these to make them easier to test.
    rb_define_singleton_method(rb_cYARP, "named_captures", named_captures, 1);
    rb_define_singleton_method(rb_cYARP, "unescape_none", unescape_none, 1);
    rb_define_singleton_method(rb_cYARP, "unescape_minimal", unescape_minimal, 1);
    rb_define_singleton_method(rb_cYARP, "unescape_all", unescape_all, 1);
    rb_define_singleton_method(rb_cYARP, "memsize", memsize, 1);
    rb_define_singleton_method(rb_cYARP, "profile_file", profile_file, 1);

    // Next, initialize the pack API.
    Init_yarp_pack();
}
