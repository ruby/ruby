#include "prism.h"

/**
 * Effectively raise an error and exit. This leaks memory because it doesn't
 * unmap the file or free any of the allocated resources, but it doesn't matter
 * because everything will get freed when the process exits.
 */
static void
fail(const char *message, ...) {
    va_list args;
    va_start(args, message);
    vfprintf(stderr, message, args);
    va_end(args);
    exit(EXIT_FAILURE);
}

/** Various constants that we need to compare against. */
static pm_constant_id_t id_Primitive;
static pm_constant_id_t id___builtin;
static pm_constant_id_t id_require;
static pm_constant_id_t id_require_relative;

/** Various strings that we need to compare against. */
static pm_string_t str_leaf;
static pm_string_t str_inline_block;

/** The number of inlines that have been emitted. */
static int32_t inlines_size;

/**
 * The various methods that can be called on Primitive. We define an enum so
 * that we can switch on the various methods.
 */
typedef enum {
    PRIMITIVE_UNKNOWN,
    PRIMITIVE_ARG,
    PRIMITIVE_ATTR,
    PRIMITIVE_CSTMT,
    PRIMITIVE_CEXPR,
    PRIMITIVE_CCONST,
    PRIMITIVE_CINIT,
    PRIMITIVE_MANDATORY_ONLY
} primitive_t;

/**
 * Given the constant that represents the method name given to Primitive or
 * __builtin, return the corresponding primitive_t. If the method name
 * is not a known method, then PRIMITIVE_UNKNOWN is returned.
 */
static primitive_t
primitive_parse(const pm_buffer_t *primitive_name) {
    const char *name = pm_buffer_value(primitive_name);
    const size_t length = pm_buffer_length(primitive_name) - 1;
    if (name[length] != '!' && name[length] != '?') return PRIMITIVE_UNKNOWN;

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define CMP(s) memcmp(name, s, MIN(length, strlen(s))) == 0

    if      (CMP("arg"))            { return PRIMITIVE_ARG; }
    else if (CMP("attr"))           { return PRIMITIVE_ATTR; }
    else if (CMP("cstmt"))          { return PRIMITIVE_CSTMT; }
    else if (CMP("cexpr"))          { return PRIMITIVE_CEXPR; }
    else if (CMP("cconst"))         { return PRIMITIVE_CCONST; }
    else if (CMP("cinit"))          { return PRIMITIVE_CINIT; }
    else if (CMP("mandatory_only")) { return PRIMITIVE_MANDATORY_ONLY; }
    else                            { return PRIMITIVE_UNKNOWN; }

#undef MIN
#undef CMP
}

/**
 * This is an identifying key that can identify a set of locals from a method.
 * We use this to communicate the set of locals that should be used for a given
 * builtin.
 */
typedef struct {
    pm_constant_t name;
    int32_t lineno;
} locals_data_t;

/** This is the data being passed along as we visit the nodes. */
typedef struct {
    /** This is the parser that was used to parse the AST. */
    const pm_parser_t *parser;

    /**
     * This is a segment of the name that will become the names of the C
     * functions. It is determined by the shape of the AST.
     */
    const char *name;

    /** The locals data for the surrounding method, if there is one. */
    locals_data_t locals;
} visit_data_t;

/** True if the given call node is a call to a method on Primitive. */
static inline bool
call_node_primitive_p(const pm_call_node_t *node) {
    return (
      (node->receiver != NULL) &&
      PM_NODE_TYPE_P(node->receiver, PM_CONSTANT_READ_NODE) &&
      (((const pm_constant_read_node_t *) node->receiver)->name == id_Primitive)
    );
}

/** True if the given call node is a call to a method on __builtin. */
static inline bool
call_node_builtin_p(const pm_call_node_t *node) {
    return (
      (node->receiver != NULL) &&
      PM_NODE_TYPE_P(node->receiver, PM_CALL_NODE) &&
      PM_NODE_FLAG_P(node->receiver, PM_CALL_NODE_FLAGS_VARIABLE_CALL) &&
      (((const pm_call_node_t *) node->receiver)->name == id___builtin)
    );
}

/** Extract the contents of the given string node into the given buffer. */
static void
extract_string_literal(pm_buffer_t *buffer, const pm_node_t *node) {
    switch (PM_NODE_TYPE(node)) {
      case PM_STRING_NODE: {
        const pm_string_node_t *cast = (const pm_string_node_t *) node;
        pm_buffer_append_string(buffer, (const char *) pm_string_source(&cast->unescaped), pm_string_length(&cast->unescaped));
        break;
      }
      case PM_INTERPOLATED_STRING_NODE: {
        const pm_interpolated_string_node_t *cast = (const pm_interpolated_string_node_t *) node;
        for (size_t index = 0; index < cast->parts.size; index++) {
            extract_string_literal(buffer, cast->parts.nodes[index]);
        }
        break;
      }
      default:
        fail("unexpected %s\n", pm_node_type_to_str(node->type));
        break;
    }
}

/**
 * Parse out any calls to require, require_relative, or calls to methods on
 * Primitive or __builtin.
 */
static bool
visit_call_node(const pm_call_node_t *node, const visit_data_t *visit_data) {
    // If this is a call to require or require relative with a single string
    // node argument, then we will attempt to find the file that is being
    // required and add it to the files that should be processed.
    if ((node->name == id_require || node->name == id_require_relative) && (node->arguments != NULL) && PM_NODE_TYPE_P(node->arguments->arguments.nodes[0], PM_STRING_NODE)) {
        const pm_string_node_t *argument = (const pm_string_node_t *) node->arguments->arguments.nodes[0];
        printf("REQUIRE %.*s\n", (int) pm_string_length(&argument->unescaped), pm_string_source(&argument->unescaped));
        return true;
    }

    // This constant is going to hold the name of the method that is being
    // called on Primitive, on __builtin, or is being called on its own with
    // __builtin_*.
    pm_buffer_t primitive_name = { 0 };
    pm_constant_t *constant = pm_constant_pool_id_to_constant(&visit_data->parser->constant_pool, node->name);

    if (call_node_primitive_p(node) || call_node_builtin_p(node)) {
        pm_buffer_append_string(&primitive_name, (const char *) constant->start, constant->length);
    } else if (constant->length > 10 && memcmp(constant->start, "__builtin_", 10) == 0) {
        pm_buffer_append_string(&primitive_name, (const char *) constant->start + 10, constant->length - 10);
    } else {
        // If we get here, then this isn't a primitive function call and
        // we can continue the visit.
        return true;
    }

    // The name of the C function that we will be calling for this call node. It
    // may change later in this function depending on the type of primitive.
    pm_buffer_t cfunction_name = { 0 };
    pm_buffer_concat(&cfunction_name, &primitive_name);

    const pm_node_list_t *args = node->arguments != NULL ? &node->arguments->arguments : NULL;
    int32_t argc = (int32_t) (args != NULL ? args->size : 0);

    primitive_t primitive = primitive_parse(&primitive_name);
    switch (primitive) {
      case PRIMITIVE_UNKNOWN: {
        // This is a call to Primitive that is not a known method, so it
        // must be a regular C function. In this case we do not need any
        // special processing.
        break;
      }
      case PRIMITIVE_ARG: {
        // This is a call to Primitive.arg!, which expects a single symbol
        // argument detailing the name of the argument.
        if (argc != 1) {
            fail("unexpected argument number %" PRIi32 "\n", argc);
        }

        if (!PM_NODE_TYPE_P(args->nodes[0], PM_SYMBOL_NODE)) {
            fail("symbol literal expected, got %s\n", pm_node_type_to_str(args->nodes[0]->type));
        }

        return true;
      }
      case PRIMITIVE_ATTR: {
        // This is a call to Primitive.attr!, which expects a list of known
        // symbols. We will check that each of the arguments is a symbol
        // and that the symbol is one of the known symbols.
        if (argc == 0) fail("args was empty\n");

        for (size_t index = 0; index < args->size; index++) {
            const pm_node_t *arg = args->nodes[index];

            if (!PM_NODE_TYPE_P(arg, PM_SYMBOL_NODE)) {
                fail("%s was not a SymbolNode\n", pm_node_type_to_str(arg->type));
            }

            const pm_string_t *str = &((const pm_symbol_node_t *) arg)->unescaped;

            if (pm_string_compare(str, &str_leaf) == 0) {
                continue;
            } else if (pm_string_compare(str, &str_inline_block) == 0) {
                continue;
            } else {
                fail("attr (%.*s) was not in: leaf, inline_block\n", (int) pm_string_length(str), pm_string_source(str));
            }
        }

        return true;
      }
      case PRIMITIVE_MANDATORY_ONLY: {
        // This is a call to Primitive.mandatory_only?. This method does not
        // require any further processing.
        return true;
      }
      case PRIMITIVE_CSTMT:
      case PRIMITIVE_CEXPR:
      case PRIMITIVE_CCONST:
      case PRIMITIVE_CINIT: {
        // This is a call to Primitive.cstmt!, Primitive.cexpr!,
        // Primitive.cconst!, or Primitive.cinit!. These methods expect a
        // single string argument that is the C code that should be
        // executed. We will extract the string, emit an inline function,
        // and then continue the visit.
        if (argc != 1) fail("argc (%" PRIi32 ") of inline! should be 1\n", argc);

        // First, extract out the contents of the C code from the argument.
        pm_buffer_t text = { 0 };
        extract_string_literal(&text, args->nodes[0]);
        pm_buffer_rstrip(&text);

        // Next, set up the various data about the builtin that we will need
        // to emit the inline function.
        pm_buffer_t key = { 0 };
        locals_data_t locals = { 0 };
        int32_t lineno = pm_newline_list_line_column(&visit_data->parser->newline_list, node->base.location.start, visit_data->parser->start_line).line;

        switch (primitive) {
          case PRIMITIVE_CSTMT:
            pm_buffer_clear(&cfunction_name);
            pm_buffer_append_format(&cfunction_name, "builtin_inline_%s_%" PRIi32, visit_data->name, lineno);
            pm_buffer_concat(&key, &cfunction_name);

            locals = visit_data->locals;

            pm_buffer_clear(&primitive_name);
            pm_buffer_append_format(&primitive_name, "_bi%" PRIi32, lineno);

            break;
          case PRIMITIVE_CEXPR:
            locals = visit_data->locals;
            /* fallthrough */
          case PRIMITIVE_CCONST:
            pm_buffer_clear(&cfunction_name);
            pm_buffer_append_format(&cfunction_name, "builtin_inline_%s_%" PRIi32, visit_data->name, lineno);
            pm_buffer_concat(&key, &cfunction_name);

            pm_buffer_prepend_string(&text, "return ", 7);
            pm_buffer_append_byte(&text, ';');

            pm_buffer_clear(&primitive_name);
            pm_buffer_append_format(&primitive_name, "_bi%" PRIi32, lineno);

            break;
          case PRIMITIVE_CINIT:
            pm_buffer_append_format(&key, "%" PRIi32, inlines_size);
            pm_buffer_clear(&primitive_name);
            break;
          default:
            assert(false && "unreachable");
            break;
        }

        // Now we will emit the inline function and then continue the visit.
        printf(
            "INLINE key=%.*s lineno=%" PRIi32 " text=%.*s locals.name=%.*s locals.lineno=%" PRIi32 " primitive_name=%.*s\n",
            (int) pm_buffer_length(&key), pm_buffer_value(&key),
            lineno,
            (int) pm_buffer_length(&text), pm_buffer_value(&text),
            (int) locals.name.length, locals.name.start,
            locals.lineno,
            (int) pm_buffer_length(&primitive_name), pm_buffer_value(&primitive_name)
        );

        inlines_size++;
        argc--;
        pm_buffer_free(&text);

        if (primitive == PRIMITIVE_CINIT) return true;
        break;
      }
    }

    // Now we will emit the builtin and then continue the visit.
    printf(
        "BUILTIN primitive_name=%.*s argc=%" PRIi32 " cfunction_name=%.*s\n",
        (int) pm_buffer_length(&primitive_name), pm_buffer_value(&primitive_name),
        argc,
        (int) pm_buffer_length(&cfunction_name), pm_buffer_value(&cfunction_name)
    );

    return true;
}

/**
 * This is a callback that is called while walking down a subtree. It is
 * responsible for processing the current node given the data that is passed to
 * it. It returns true if the visit should continue, and false if it should not.
 */
static bool
visit(const pm_node_t *node, void *data) {
    const visit_data_t *visit_data = (const visit_data_t *) data;

    switch (PM_NODE_TYPE(node)) {
      // For call nodes we want to parse out any calls to require and any
      // calls to Primitive/__builtin.
      case PM_CALL_NODE:
        return visit_call_node((const pm_call_node_t *) node, visit_data);
      // For method definitions we want to change the locals to uniquely
      // identify this method and then continue walking down the tree.
      case PM_DEF_NODE: {
        const pm_def_node_t *cast = (const pm_def_node_t *) node;

        if (cast->body != NULL) {
            visit_data_t next_visit_data = {
                .parser = visit_data->parser,
                .name = visit_data->name,
                .locals = {
                    .name = *pm_constant_pool_id_to_constant(&visit_data->parser->constant_pool, cast->name),
                    .lineno = pm_newline_list_line_column(&visit_data->parser->newline_list, cast->base.location.start, visit_data->parser->start_line).line
                }
            };

            void *next_data = &next_visit_data;
            pm_node_visit(cast->body, visit, next_data);
        }

        return false;
      }
      // For these nodes we want to change the name to be "class" and then
      // continue walking down the tree.
      case PM_CLASS_NODE:
      case PM_MODULE_NODE:
      case PM_SINGLETON_CLASS_NODE: {
        const pm_node_t *body = NULL;
        switch (PM_NODE_TYPE(node)) {
          case PM_CLASS_NODE:
            body = ((const pm_class_node_t *) node)->body; break;
          case PM_MODULE_NODE:
            body = ((const pm_module_node_t *) node)->body; break;
          case PM_SINGLETON_CLASS_NODE:
            body = ((const pm_singleton_class_node_t *) node)->body; break;
          default:
            assert(false && "unreachable"); break;
        }

        if (body != NULL) {
            visit_data_t next_visit_data = { .parser = visit_data->parser, .name = "class", .locals = { 0 } };
            void *next_data = &next_visit_data;
            pm_node_visit(body, visit, next_data);
        }

        return false;
      }
      default:
        return true;
    }
}

int
main(int argc, const char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return 1;
    }

    const char *filepath = argv[1];
    pm_string_t input;

    if (!pm_string_mapped_init(&input, filepath)) {
        fail("unable to map file: %s\n", filepath);
        return EXIT_FAILURE;
    }

    pm_options_t options = { 0 };
    pm_options_line_set(&options, 1);
    pm_options_filepath_set(&options, filepath);

    // We are purposefully limiting the syntax that is allowed in core files so
    // that we don't use unreleased syntax that then needs to change in case
    // something gets reverted. Bumping this version later will allow newer
    // syntax in core files.
    pm_options_version_set(&options, "3.3.0", 5);

    pm_parser_t parser;
    pm_parser_init(&parser, pm_string_source(&input), pm_string_length(&input), &options);

    id_Primitive = pm_constant_pool_insert_constant(&parser.constant_pool, (const uint8_t *) "Primitive", 9);
    id___builtin = pm_constant_pool_insert_constant(&parser.constant_pool, (const uint8_t *) "__builtin", 9);
    id_require = pm_constant_pool_insert_constant(&parser.constant_pool, (const uint8_t *) "require", 7);
    id_require_relative = pm_constant_pool_insert_constant(&parser.constant_pool, (const uint8_t *) "require_relative", 16);

    pm_string_constant_init(&str_leaf, "leaf", 4);
    pm_string_constant_init(&str_inline_block, "inline_block", 12);

    pm_node_t *node = pm_parse(&parser);
    visit_data_t visit_data = { .parser = &parser, .name = "top", .locals = { 0 } };

    void *data = &visit_data;
    pm_node_visit(node, visit, data);

    pm_node_destroy(&parser, node);
    pm_parser_free(&parser);
    pm_string_free(&input);
    pm_options_free(&options);

    return EXIT_SUCCESS;
}
