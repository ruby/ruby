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

// Represents an input of Ruby code. It can either be coming from a file or a
// string. If it's a file, we'll use demand paging to read the contents of the
// file into a string. If it's already a string, we'll reference it directly.
typedef struct {
    const char *source;
    size_t size;
} input_t;

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

// Read the file indicated by the filepath parameter into source and load its
// contents and size into the given input_t.
//
// We want to use demand paging as much as possible in order to avoid having to
// read the entire file into memory (which could be detrimental to performance
// for large files). This means that if we're on windows we'll use
// `MapViewOfFile`, on POSIX systems that have access to `mmap` we'll use
// `mmap`, and on other POSIX systems we'll use `read`.
static int
input_load_filepath(input_t *input, const char *filepath) {
#ifdef _WIN32
    // Open the file for reading.
    HANDLE file = CreateFile(filepath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

    if (file == INVALID_HANDLE_VALUE) {
        perror("CreateFile failed");
        return 1;
    }

    // Get the file size.
    DWORD file_size = GetFileSize(file, NULL);
    if (file_size == INVALID_FILE_SIZE) {
        CloseHandle(file);
        perror("GetFileSize failed");
        return 1;
    }

    // If the file is empty, then we don't need to do anything else, we'll set
    // the source to a constant empty string and return.
    if (!file_size) {
        CloseHandle(file);
        input->size = 0;
        input->source = "";
        return 0;
    }

    // Create a mapping of the file.
    HANDLE mapping = CreateFileMapping(file, NULL, PAGE_READONLY, 0, 0, NULL);
    if (mapping == NULL) {
        CloseHandle(file);
        perror("CreateFileMapping failed");
        return 1;
    }

    // Map the file into memory.
    input->source = (const char *) MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
    CloseHandle(mapping);
    CloseHandle(file);

    if (input->source == NULL) {
        perror("MapViewOfFile failed");
        return 1;
    }

    // Set the size of the source.
    input->size = (size_t) file_size;
    return 0;
#else
    // Open the file for reading
    int fd = open(filepath, O_RDONLY);
    if (fd == -1) {
        perror("open");
        return 1;
    }

    // Stat the file to get the file size
    struct stat sb;
    if (fstat(fd, &sb) == -1) {
        close(fd);
        perror("fstat");
        return 1;
    }

    // mmap the file descriptor to virtually get the contents
    input->size = sb.st_size;

#ifdef HAVE_MMAP
    if (!input->size) {
        close(fd);
        input->source = "";
        return 0;
    }

    const char *result = mmap(NULL, input->size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (result == MAP_FAILED) {
        perror("Map failed");
        return 1;
    } else {
        input->source = result;
    }
#else
    input->source = malloc(input->size);
    if (input->source == NULL) return 1;

    ssize_t read_size = read(fd, (void *) input->source, input->size);
    if (read_size < 0 || (size_t)read_size != input->size) {
        perror("Read size is incorrect");
        free((void *) input->source);
        return 1;
    }
#endif

    close(fd);
    return 0;
#endif
}

// Load the contents and size of the given string into the given input_t.
static void
input_load_string(input_t *input, VALUE string) {
    // Check if the string is a string. If it's not, then raise a type error.
    if (!RB_TYPE_P(string, T_STRING)) {
        rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected String)", rb_obj_class(string));
    }

    input->source = RSTRING_PTR(string);
    input->size = RSTRING_LEN(string);
}

// Free any resources associated with the given input_t. This is the corollary
// function to source_file_load. It will unmap the file if it was mapped, or
// free the memory if it was allocated.
static void
input_unload_filepath(input_t *input) {
    // We don't need to free anything with 0 sized files because we handle that
    // with a constant string instead.
    if (!input->size) return;
    void *memory = (void *) input->source;

#if defined(_WIN32)
    UnmapViewOfFile(memory);
#elif defined(HAVE_MMAP)
    munmap(memory, input->size);
#else
    free(memory);
#endif
}

/******************************************************************************/
/* Serializing the AST                                                        */
/******************************************************************************/

// Dump the AST corresponding to the given input to a string.
static VALUE
dump_input(input_t *input, const char *filepath) {
    yp_buffer_t buffer;
    if (!yp_buffer_init(&buffer)) {
        rb_raise(rb_eNoMemError, "failed to allocate memory");
    }

    yp_parser_t parser;
    yp_parser_init(&parser, input->source, input->size, filepath);

    yp_node_t *node = yp_parse(&parser);
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

    input_t input;
    input_load_string(&input, string);
    return dump_input(&input, check_filepath(filepath));
}

// Dump the AST corresponding to the given file to a string.
static VALUE
dump_file(VALUE self, VALUE filepath) {
    input_t input;

    const char *checked = check_filepath(filepath);
    if (input_load_filepath(&input, checked) != 0) return Qnil;

    VALUE value = dump_input(&input, checked);
    input_unload_filepath(&input);

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
            LONG2FIX(comment->end - parser->start)
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
            LONG2FIX(error->end - parser->start)
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
            LONG2FIX(warning->end - parser->start)
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
lex_input(input_t *input, const char *filepath) {
    yp_parser_t parser;
    yp_parser_init(&parser, input->source, input->size, filepath);
    yp_parser_register_encoding_changed_callback(&parser, lex_encoding_changed_callback);

    VALUE offsets = rb_ary_new();
    VALUE source_argv[] = { rb_str_new(input->source, input->size), offsets };
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
    yp_node_t *node = yp_parse(&parser);

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
        parser_warnings(&parser, lex_data.encoding, source)
    };

    VALUE result = rb_class_new_instance(4, result_argv, rb_cYARPParseResult);

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

    input_t input;
    input_load_string(&input, string);
    return lex_input(&input, check_filepath(filepath));
}

// Return an array of tokens corresponding to the given file.
static VALUE
lex_file(VALUE self, VALUE filepath) {
    input_t input;

    const char *checked = check_filepath(filepath);
    if (input_load_filepath(&input, checked) != 0) return Qnil;

    VALUE value = lex_input(&input, checked);
    input_unload_filepath(&input);

    return value;
}

/******************************************************************************/
/* Parsing Ruby code                                                          */
/******************************************************************************/

// Parse the given input and return a ParseResult instance.
static VALUE
parse_input(input_t *input, const char *filepath) {
    yp_parser_t parser;
    yp_parser_init(&parser, input->source, input->size, filepath);

    yp_node_t *node = yp_parse(&parser);
    rb_encoding *encoding = rb_enc_find(parser.encoding.name);

    VALUE source = yp_source_new(&parser);
    VALUE result_argv[] = {
        yp_ast_new(&parser, node, encoding),
        parser_comments(&parser, source),
        parser_errors(&parser, encoding, source),
        parser_warnings(&parser, encoding, source)
    };

    VALUE result = rb_class_new_instance(4, result_argv, rb_cYARPParseResult);

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

    input_t input;
    input_load_string(&input, string);

#ifdef YARP_DEBUG_MODE_BUILD
    char* dup = malloc(input.size);
    memcpy(dup, input.source, input.size);
    input.source = dup;
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
    input_t input;

    const char *checked = check_filepath(filepath);
    if (input_load_filepath(&input, checked) != 0) return Qnil;

    VALUE value = parse_input(&input, checked);
    input_unload_filepath(&input);

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
    yp_string_t string;
    VALUE result;

    yp_list_t error_list;
    yp_list_init(&error_list);

    const char *start = RSTRING_PTR(source);
    size_t length = RSTRING_LEN(source);

    yp_parser_t parser;
    yp_parser_init(&parser, start, length, "");

    yp_unescape_manipulate_string(&parser, start, length, &string, unescape_type, &error_list);
    if (yp_list_empty_p(&error_list)) {
        result = rb_str_new(yp_string_source(&string), yp_string_length(&string));
    } else {
        result = Qnil;
    }

    yp_string_free(&string);
    yp_list_free(&error_list);
    yp_parser_free(&parser);

    return result;
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

    yp_node_t *node = yp_parse(&parser);
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
    input_t input;

    const char *checked = check_filepath(filepath);
    if (input_load_filepath(&input, checked) != 0) return Qnil;

    yp_parser_t parser;
    yp_parser_init(&parser, input.source, input.size, checked);

    yp_node_t *node = yp_parse(&parser);
    yp_node_destroy(&parser, node);
    yp_parser_free(&parser);

    return Qnil;
}

// The function takes a source string and returns a Ruby array containing the
// offsets of every newline in the string. (It also includes a 0 at the
// beginning to indicate the position of the first line.) It accepts a string as
// its only argument and returns an array of integers.
static VALUE
newlines(VALUE self, VALUE string) {
    yp_parser_t parser;
    size_t length = RSTRING_LEN(string);
    yp_parser_init(&parser, RSTRING_PTR(string), length, NULL);

    yp_node_t *node = yp_parse(&parser);
    yp_node_destroy(&parser, node);

    VALUE result = rb_ary_new_capa(parser.newline_list.size);
    for (size_t index = 0; index < parser.newline_list.size; index++) {
        rb_ary_push(result, INT2FIX(parser.newline_list.offsets[index]));
    }

    yp_parser_free(&parser);
    return result;
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
    rb_define_singleton_method(rb_cYARP, "newlines", newlines, 1);

    // Next, initialize the pack API.
    Init_yarp_pack();
}
