#include <psych.h>

#ifdef PSYCH_USE_LIBFYAML
/*
 * Experimental libfyaml-backed parser.  Only compiled when psych is built
 * with --enable-libfyaml.  Mirrors the event protocol of the libyaml backend
 * in ext/psych/psych_parser.c so the Ruby layer is unchanged.
 */

VALUE cPsychParser;

static ID id_read;
static ID id_empty;
static ID id_start_stream;
static ID id_end_stream;
static ID id_start_document;
static ID id_end_document;
static ID id_alias;
static ID id_scalar;
static ID id_start_sequence;
static ID id_end_sequence;
static ID id_start_mapping;
static ID id_end_mapping;
static ID id_event_location;

#define PSYCH_TRANSCODE(_str, _yaml_enc, _internal_enc) \
  do { \
    rb_enc_associate_index((_str), (_yaml_enc)); \
    if(_internal_enc) \
      (_str) = rb_str_export_to_enc((_str), (_internal_enc)); \
  } while (0)

/* libyaml-compatible encoding constants exposed to the Ruby layer. */
#define PSYCH_ANY_ENCODING     0
#define PSYCH_UTF8_ENCODING    1
#define PSYCH_UTF16LE_ENCODING 2
#define PSYCH_UTF16BE_ENCODING 3

typedef struct {
    struct fy_parser *fyp;
    size_t mark_line;
    size_t mark_column;
    size_t mark_index;
} psych_fy_parser_t;

static ssize_t io_reader(void *user, void *buf, size_t count)
{
    VALUE io = (VALUE)user;
    VALUE string = rb_funcall(io, id_read, 1, SIZET2NUM(count));

    if (NIL_P(string)) {
        return 0; /* EOF */
    }

    StringValue(string);
    size_t len = (size_t)RSTRING_LEN(string);
    if (len > count) {
        len = count;
    }
    memcpy(buf, RSTRING_PTR(string), len);
    return (ssize_t)len;
}

static void dealloc(void *ptr)
{
    psych_fy_parser_t *parser = (psych_fy_parser_t *)ptr;
    if (parser->fyp) {
        fy_parser_destroy(parser->fyp);
    }
    xfree(parser);
}

static const rb_data_type_t psych_parser_type = {
    "Psych/parser",
    {0, dealloc, 0,},
    0, 0,
#ifdef RUBY_TYPED_FREE_IMMEDIATELY
    RUBY_TYPED_FREE_IMMEDIATELY,
#endif
};

static VALUE allocate(VALUE klass)
{
    psych_fy_parser_t *parser;
    VALUE obj = TypedData_Make_Struct(klass, psych_fy_parser_t, &psych_parser_type, parser);

    static const struct fy_parse_cfg cfg = {
        .flags = FYPCF_QUIET | FYPCF_COLLECT_DIAG | FYPCF_DEFAULT_VERSION_AUTO,
    };
    parser->fyp = fy_parser_create(&cfg);
    if (!parser->fyp) {
        rb_raise(rb_eNoMemError, "could not create libfyaml parser");
    }

    return obj;
}

/* TODO: libfyaml's diagnostics are collected via fy_diag; reconstructing the
 * libyaml-style problem/context/offset is left for a later pass.  For now we
 * raise a Psych::SyntaxError with the best-effort mark we tracked. */
static VALUE make_exception(psych_fy_parser_t *parser, VALUE path)
{
    VALUE ePsychSyntaxError = rb_const_get(mPsych, rb_intern("SyntaxError"));

    return rb_funcall(ePsychSyntaxError, rb_intern("new"), 6,
            path,
            SIZET2NUM(parser->mark_line + 1),
            SIZET2NUM(parser->mark_column + 1),
            SIZET2NUM(parser->mark_index),
            rb_usascii_str_new2("could not parse YAML"),
            Qnil);
}

static VALUE transcode_string(VALUE src)
{
    int utf8 = rb_utf8_encindex();
    int source_encoding = rb_enc_get_index(src);

    if (source_encoding == utf8 || source_encoding == rb_usascii_encindex()) {
        return src;
    }

    src = rb_str_export_to_enc(src, rb_utf8_encoding());
    return src;
}

/* ---- protected handler trampolines (identical protocol to libyaml backend) */

static VALUE protected_start_stream(VALUE pointer)
{
    VALUE *args = (VALUE *)pointer;
    return rb_funcall(args[0], id_start_stream, 1, args[1]);
}

static VALUE protected_start_document(VALUE pointer)
{
    VALUE *args = (VALUE *)pointer;
    return rb_funcall3(args[0], id_start_document, 3, args + 1);
}

static VALUE protected_end_document(VALUE pointer)
{
    VALUE *args = (VALUE *)pointer;
    return rb_funcall(args[0], id_end_document, 1, args[1]);
}

static VALUE protected_alias(VALUE pointer)
{
    VALUE *args = (VALUE *)pointer;
    return rb_funcall(args[0], id_alias, 1, args[1]);
}

static VALUE protected_scalar(VALUE pointer)
{
    VALUE *args = (VALUE *)pointer;
    return rb_funcall3(args[0], id_scalar, 6, args + 1);
}

static VALUE protected_start_sequence(VALUE pointer)
{
    VALUE *args = (VALUE *)pointer;
    return rb_funcall3(args[0], id_start_sequence, 4, args + 1);
}

static VALUE protected_end_sequence(VALUE handler)
{
    return rb_funcall(handler, id_end_sequence, 0);
}

static VALUE protected_start_mapping(VALUE pointer)
{
    VALUE *args = (VALUE *)pointer;
    return rb_funcall3(args[0], id_start_mapping, 4, args + 1);
}

static VALUE protected_end_mapping(VALUE handler)
{
    return rb_funcall(handler, id_end_mapping, 0);
}

static VALUE protected_empty(VALUE handler)
{
    return rb_funcall(handler, id_empty, 0);
}

static VALUE protected_end_stream(VALUE handler)
{
    return rb_funcall(handler, id_end_stream, 0);
}

static VALUE protected_event_location(VALUE pointer)
{
    VALUE *args = (VALUE *)pointer;
    return rb_funcall3(args[0], id_event_location, 4, args + 1);
}

/* ---- enum translation: libfyaml -> psych/libyaml integer constants -------- */

static int fyss_to_psych(enum fy_scalar_style s)
{
    switch (s) {
        case FYSS_PLAIN:         return 1;
        case FYSS_SINGLE_QUOTED: return 2;
        case FYSS_DOUBLE_QUOTED: return 3;
        case FYSS_LITERAL:       return 4;
        case FYSS_FOLDED:        return 5;
        default:                 return 0; /* FYSS_ANY */
    }
}

static int fyns_to_psych(enum fy_node_style s)
{
    switch (s) {
        case FYNS_FLOW:  return 2;
        case FYNS_BLOCK: return 1;
        default:         return 0; /* FYNS_ANY */
    }
}

static VALUE token_to_str(struct fy_token *tok, int encoding, rb_encoding *internal_enc)
{
    size_t len = 0;
    const char *text;

    if (!tok) {
        return Qnil;
    }
    text = fy_token_get_text(tok, &len);
    if (!text) {
        return Qnil;
    }
    VALUE str = rb_str_new(text, (long)len);
    PSYCH_TRANSCODE(str, encoding, internal_enc);
    return str;
}

static VALUE parse(VALUE self, VALUE handler, VALUE yaml, VALUE path)
{
    psych_fy_parser_t *parser;
    struct fy_event *event;
    int done = 0;
    int state = 0;
    int encoding = rb_utf8_encindex();
    rb_encoding *internal_enc = rb_default_internal_encoding();

    TypedData_Get_Struct(self, psych_fy_parser_t, &psych_parser_type, parser);

    fy_parser_reset(parser->fyp);
    parser->mark_line = parser->mark_column = parser->mark_index = 0;

    if (rb_respond_to(yaml, id_read)) {
        if (fy_parser_set_input_callback(parser->fyp, (void *)yaml, io_reader) != 0) {
            rb_raise(rb_eRuntimeError, "could not set libfyaml input");
        }
    } else {
        StringValue(yaml);
        yaml = transcode_string(yaml);
        if (fy_parser_set_string(parser->fyp,
                    RSTRING_PTR(yaml), (size_t)RSTRING_LEN(yaml)) != 0) {
            rb_raise(rb_eRuntimeError, "could not set libfyaml input");
        }
    }

    while (!done) {
        VALUE event_args[5];
        const struct fy_mark *sm, *em;

        event = fy_parser_parse(parser->fyp);

        if (!event) {
            VALUE exception = make_exception(parser, path);
            rb_exc_raise(exception);
        }

        sm = fy_event_start_mark(event);
        em = fy_event_end_mark(event);
        if (sm) {
            parser->mark_line = (size_t)sm->line;
            parser->mark_column = (size_t)sm->column;
            parser->mark_index = sm->input_pos;
        }

        event_args[0] = handler;
        event_args[1] = SIZET2NUM(sm ? (size_t)sm->line : 0);
        event_args[2] = SIZET2NUM(sm ? (size_t)sm->column : 0);
        event_args[3] = SIZET2NUM(em ? (size_t)em->line : 0);
        event_args[4] = SIZET2NUM(em ? (size_t)em->column : 0);
        rb_protect(protected_event_location, (VALUE)event_args, &state);

        switch (event->type) {
            case FYET_STREAM_START:
            {
                VALUE args[2];
                args[0] = handler;
                args[1] = INT2NUM(PSYCH_UTF8_ENCODING);
                rb_protect(protected_start_stream, (VALUE)args, &state);
            }
            break;
            case FYET_DOCUMENT_START:
            {
                VALUE args[4];
                VALUE version = rb_ary_new();
                VALUE tag_directives = rb_ary_new();
                struct fy_document_state *ds = event->document_start.document_state;

                if (ds && fy_document_state_version_explicit(ds)) {
                    const struct fy_version *v = fy_document_state_version(ds);
                    if (v) {
                        version = rb_ary_new3((long)2,
                                INT2NUM(v->major), INT2NUM(v->minor));
                    }
                }

                if (ds && fy_document_state_tags_explicit(ds)) {
                    void *iter = NULL;
                    const struct fy_tag *tag;
                    while ((tag = fy_document_state_tag_directive_iterate(ds, &iter)) != NULL) {
                        /* skip the implicit defaults ("!" and "!!") */
                        if (tag->handle && tag->prefix) {
                            if ((strcmp(tag->handle, "!") == 0 && strcmp(tag->prefix, "!") == 0) ||
                                (strcmp(tag->handle, "!!") == 0 &&
                                 strcmp(tag->prefix, "tag:yaml.org,2002:") == 0)) {
                                continue;
                            }
                        }
                        VALUE handle = tag->handle ? rb_str_new2(tag->handle) : Qnil;
                        VALUE prefix = tag->prefix ? rb_str_new2(tag->prefix) : Qnil;
                        if (!NIL_P(handle)) PSYCH_TRANSCODE(handle, encoding, internal_enc);
                        if (!NIL_P(prefix)) PSYCH_TRANSCODE(prefix, encoding, internal_enc);
                        rb_ary_push(tag_directives, rb_ary_new3((long)2, handle, prefix));
                    }
                }

                args[0] = handler;
                args[1] = version;
                args[2] = tag_directives;
                args[3] = event->document_start.implicit ? Qtrue : Qfalse;
                rb_protect(protected_start_document, (VALUE)args, &state);
            }
            break;
            case FYET_DOCUMENT_END:
            {
                VALUE args[2];
                args[0] = handler;
                args[1] = event->document_end.implicit ? Qtrue : Qfalse;
                rb_protect(protected_end_document, (VALUE)args, &state);
            }
            break;
            case FYET_ALIAS:
            {
                VALUE args[2];
                args[0] = handler;
                args[1] = token_to_str(event->alias.anchor, encoding, internal_enc);
                rb_protect(protected_alias, (VALUE)args, &state);
            }
            break;
            case FYET_SCALAR:
            {
                VALUE args[7];
                enum fy_scalar_style fyss = fy_token_scalar_style(event->scalar.value);
                int has_tag = (event->scalar.tag != NULL);
                int plain_style = (fyss == FYSS_PLAIN);

                args[0] = handler;
                args[1] = token_to_str(event->scalar.value, encoding, internal_enc);
                if (NIL_P(args[1])) args[1] = rb_str_new2("");
                args[2] = token_to_str(event->scalar.anchor, encoding, internal_enc);
                args[3] = token_to_str(event->scalar.tag, encoding, internal_enc);
                /* libfyaml does not expose libyaml's plain_implicit /
                 * quoted_implicit pair, so reconstruct them from the explicit
                 * tag presence and the scalar style, matching libyaml:
                 *   plain, untagged   -> (plain=1, quoted=0)
                 *   quoted, untagged  -> (plain=0, quoted=1)
                 *   tagged            -> (plain=0, quoted=0) */
                args[4] = (!has_tag && plain_style) ? Qtrue : Qfalse;
                args[5] = (!has_tag && !plain_style) ? Qtrue : Qfalse;
                args[6] = INT2NUM(fyss_to_psych(fyss));
                rb_protect(protected_scalar, (VALUE)args, &state);
            }
            break;
            case FYET_SEQUENCE_START:
            {
                VALUE args[5];
                args[0] = handler;
                args[1] = token_to_str(event->sequence_start.anchor, encoding, internal_enc);
                args[2] = token_to_str(event->sequence_start.tag, encoding, internal_enc);
                args[3] = event->sequence_start.tag ? Qfalse : Qtrue;
                args[4] = INT2NUM(fyns_to_psych(fy_event_get_node_style(event)));
                rb_protect(protected_start_sequence, (VALUE)args, &state);
            }
            break;
            case FYET_SEQUENCE_END:
                rb_protect(protected_end_sequence, handler, &state);
            break;
            case FYET_MAPPING_START:
            {
                VALUE args[5];
                args[0] = handler;
                args[1] = token_to_str(event->mapping_start.anchor, encoding, internal_enc);
                args[2] = token_to_str(event->mapping_start.tag, encoding, internal_enc);
                args[3] = event->mapping_start.tag ? Qfalse : Qtrue;
                args[4] = INT2NUM(fyns_to_psych(fy_event_get_node_style(event)));
                rb_protect(protected_start_mapping, (VALUE)args, &state);
            }
            break;
            case FYET_MAPPING_END:
                rb_protect(protected_end_mapping, handler, &state);
            break;
            case FYET_NONE:
                rb_protect(protected_empty, handler, &state);
            break;
            case FYET_STREAM_END:
                rb_protect(protected_end_stream, handler, &state);
                done = 1;
            break;
        }

        fy_parser_event_free(parser->fyp, event);
        if (state) rb_jump_tag(state);
    }

    RB_GC_GUARD(yaml);
    return self;
}

/*
 * call-seq:
 *    parser.mark # => #<Psych::Parser::Mark>
 */
static VALUE mark(VALUE self)
{
    VALUE mark_klass;
    VALUE args[3];
    psych_fy_parser_t *parser;

    TypedData_Get_Struct(self, psych_fy_parser_t, &psych_parser_type, parser);
    mark_klass = rb_const_get_at(cPsychParser, rb_intern("Mark"));
    args[0] = SIZET2NUM(parser->mark_index);
    args[1] = SIZET2NUM(parser->mark_line);
    args[2] = SIZET2NUM(parser->mark_column);

    return rb_class_new_instance(3, args, mark_klass);
}

void Init_psych_parser(void)
{
#undef rb_intern
    cPsychParser = rb_define_class_under(mPsych, "Parser", rb_cObject);
    rb_define_alloc_func(cPsychParser, allocate);

    rb_define_const(cPsychParser, "ANY", INT2NUM(PSYCH_ANY_ENCODING));
    rb_define_const(cPsychParser, "UTF8", INT2NUM(PSYCH_UTF8_ENCODING));
    rb_define_const(cPsychParser, "UTF16LE", INT2NUM(PSYCH_UTF16LE_ENCODING));
    rb_define_const(cPsychParser, "UTF16BE", INT2NUM(PSYCH_UTF16BE_ENCODING));

    rb_require("psych/syntax_error");

    rb_define_private_method(cPsychParser, "_native_parse", parse, 3);
    rb_define_method(cPsychParser, "mark", mark, 0);

    id_read            = rb_intern("read");
    id_empty           = rb_intern("empty");
    id_start_stream    = rb_intern("start_stream");
    id_end_stream      = rb_intern("end_stream");
    id_start_document  = rb_intern("start_document");
    id_end_document    = rb_intern("end_document");
    id_alias           = rb_intern("alias");
    id_scalar          = rb_intern("scalar");
    id_start_sequence  = rb_intern("start_sequence");
    id_end_sequence    = rb_intern("end_sequence");
    id_start_mapping   = rb_intern("start_mapping");
    id_end_mapping     = rb_intern("end_mapping");
    id_event_location  = rb_intern("event_location");
}

#endif /* PSYCH_USE_LIBFYAML */
