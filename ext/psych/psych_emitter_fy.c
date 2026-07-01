#include <psych.h>

#ifdef PSYCH_USE_LIBFYAML
/*
 * Experimental libfyaml-backed emitter.  Only compiled when psych is built
 * with --enable-libfyaml.  Mirrors ext/psych/psych_emitter.c.
 */

#if !defined(RARRAY_CONST_PTR)
#define RARRAY_CONST_PTR(s) (const VALUE *)RARRAY_PTR(s)
#endif
#if !defined(RARRAY_AREF)
#define RARRAY_AREF(a, i) RARRAY_CONST_PTR(a)[i]
#endif

VALUE cPsychEmitter;
static ID id_io;
static ID id_write;
static ID id_line_width;
static ID id_indentation;
static ID id_canonical;

typedef struct {
    struct fy_emitter *emit;
    struct fy_emitter_cfg cfg;
    int indent;
    int width;
    int canonical;
} psych_fy_emitter_t;

static int emitter_output(struct fy_emitter *emit, enum fy_emitter_write_type type,
        const char *str, int len, void *userdata)
{
    VALUE self = (VALUE)userdata;
    VALUE io = rb_attr_get(self, id_io);
    VALUE s = rb_enc_str_new(str, (long)len, rb_utf8_encoding());
    rb_funcall(io, id_write, 1, s);
    return len;
}

static void dealloc(void *ptr)
{
    psych_fy_emitter_t *e = (psych_fy_emitter_t *)ptr;
    if (e->emit) {
        fy_emitter_destroy(e->emit);
    }
    xfree(e);
}

static const rb_data_type_t psych_emitter_type = {
    "Psych/emitter",
    {0, dealloc, 0,},
    0, 0,
#ifdef RUBY_TYPED_FREE_IMMEDIATELY
    RUBY_TYPED_FREE_IMMEDIATELY,
#endif
};

static VALUE allocate(VALUE klass)
{
    psych_fy_emitter_t *e;
    VALUE obj = TypedData_Make_Struct(klass, psych_fy_emitter_t, &psych_emitter_type, e);

    e->emit = NULL;
    e->indent = 2;
    e->width = -1;
    e->canonical = 0;

    return obj;
}

static unsigned int build_flags(psych_fy_emitter_t *e)
{
    unsigned int flags = FYECF_MODE_ORIGINAL |
                         FYECF_DOC_START_MARK_AUTO | FYECF_DOC_END_MARK_AUTO;
    int indent = (e->indent >= 1 && e->indent <= 9) ? e->indent : 2;
    flags |= FYECF_INDENT(indent);
    if (e->width <= 0) {
        flags |= FYECF_WIDTH_INF;
    } else {
        flags |= FYECF_WIDTH(e->width > 255 ? 255 : e->width);
    }
    return flags;
}

/* (Re)create the underlying fy_emitter from the current option state.  Safe to
 * call before any event has been emitted. */
static void rebuild_emitter(VALUE self, psych_fy_emitter_t *e)
{
    if (e->emit) {
        fy_emitter_destroy(e->emit);
        e->emit = NULL;
    }
    e->cfg.flags = build_flags(e);
    e->cfg.output = emitter_output;
    e->cfg.userdata = (void *)self;
    e->cfg.diag = NULL;
    e->emit = fy_emitter_create(&e->cfg);
    if (!e->emit) {
        rb_raise(rb_eNoMemError, "could not create libfyaml emitter");
    }
}

static void do_emit(psych_fy_emitter_t *e, struct fy_event *event)
{
    if (!event) {
        rb_raise(rb_eRuntimeError, "libfyaml: could not create event");
    }
    if (fy_emit_event(e->emit, event) != 0) {
        rb_raise(rb_eRuntimeError, "libfyaml: emit failed");
    }
}

/* call-seq: Psych::Emitter.new(io, options = Psych::Emitter::OPTIONS) */
static VALUE initialize(int argc, VALUE *argv, VALUE self)
{
    psych_fy_emitter_t *e;
    VALUE io, options;

    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);

    if (rb_scan_args(argc, argv, "11", &io, &options) == 2) {
        e->width     = NUM2INT(rb_funcall(options, id_line_width, 0));
        e->indent    = NUM2INT(rb_funcall(options, id_indentation, 0));
        e->canonical = (Qtrue == rb_funcall(options, id_canonical, 0)) ? 1 : 0;
    }

    rb_ivar_set(self, id_io, io);
    rebuild_emitter(self, e);

    return self;
}

static VALUE start_stream(VALUE self, VALUE encoding)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);
    Check_Type(encoding, T_FIXNUM);

    do_emit(e, fy_emit_event_create(e->emit, FYET_STREAM_START));
    return self;
}

static VALUE end_stream(VALUE self)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);

    do_emit(e, fy_emit_event_create(e->emit, FYET_STREAM_END));
    return self;
}

struct start_document_data {
    VALUE self;
    VALUE version;
    VALUE tags;
    VALUE imp;
    struct fy_tag *tag_storage;
    const struct fy_tag **tag_ptrs;
};

static VALUE start_document_try(VALUE d)
{
    struct start_document_data *data = (struct start_document_data *)d;
    VALUE version = data->version;
    VALUE tags = data->tags;
    psych_fy_emitter_t *e;
    struct fy_version ver;
    const struct fy_version *verp = NULL;
    VALUE guard = Qnil;
    struct fy_event *event;

    TypedData_Get_Struct(data->self, psych_fy_emitter_t, &psych_emitter_type, e);
    Check_Type(version, T_ARRAY);

    if (RARRAY_LEN(version) >= 2) {
        ver.major = NUM2INT(rb_ary_entry(version, 0));
        ver.minor = NUM2INT(rb_ary_entry(version, 1));
        verp = &ver;
    }

    if (RTEST(tags)) {
        rb_encoding *encoding = rb_utf8_encoding();
        long i, len;
        Check_Type(tags, T_ARRAY);
        len = RARRAY_LEN(tags);
        if (len > 0) {
            /* Ruby array keeps the exported strings reachable for the GC while
             * their C pointers live in tag_storage. */
            guard = rb_ary_new_capa(len * 2);
            data->tag_storage = xcalloc((size_t)len, sizeof(struct fy_tag));
            data->tag_ptrs = xcalloc((size_t)len + 1, sizeof(struct fy_tag *));
            for (i = 0; i < len; i++) {
                VALUE tuple = RARRAY_AREF(tags, i);
                VALUE name, value;
                Check_Type(tuple, T_ARRAY);
                if (RARRAY_LEN(tuple) < 2) {
                    rb_raise(rb_eRuntimeError, "tag tuple must be of length 2");
                }
                name  = RARRAY_AREF(tuple, 0);
                value = RARRAY_AREF(tuple, 1);
                StringValue(name);
                StringValue(value);
                name  = rb_str_export_to_enc(name, encoding);
                value = rb_str_export_to_enc(value, encoding);
                rb_ary_push(guard, name);
                rb_ary_push(guard, value);
                data->tag_storage[i].handle = StringValueCStr(name);
                data->tag_storage[i].prefix = StringValueCStr(value);
                data->tag_ptrs[i] = &data->tag_storage[i];
            }
            data->tag_ptrs[len] = NULL;
        }
    }

    event = fy_emit_event_create(e->emit, FYET_DOCUMENT_START,
            data->imp ? 1 : 0, verp, data->tag_ptrs);

    do_emit(e, event);
    RB_GC_GUARD(guard);

    return data->self;
}

static VALUE start_document_ensure(VALUE d)
{
    struct start_document_data *data = (struct start_document_data *)d;

    xfree(data->tag_storage);
    xfree(data->tag_ptrs);

    return Qnil;
}

static VALUE start_document(VALUE self, VALUE version, VALUE tags, VALUE imp)
{
    struct start_document_data data = {
        .self = self,
        .version = version,
        .tags = tags,
        .imp = imp,
        .tag_storage = NULL,
        .tag_ptrs = NULL,
    };

    return rb_ensure(start_document_try, (VALUE)&data,
                     start_document_ensure, (VALUE)&data);
}

static VALUE end_document(VALUE self, VALUE imp)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);

    do_emit(e, fy_emit_event_create(e->emit, FYET_DOCUMENT_END, imp ? 1 : 0));
    return self;
}

static enum fy_scalar_style psych_to_fyss(int style, int plain, int quoted)
{
    switch (style) {
        case 1: return FYSS_PLAIN;
        case 2: return FYSS_SINGLE_QUOTED;
        case 3: return FYSS_DOUBLE_QUOTED;
        case 4: return FYSS_LITERAL;
        case 5: return FYSS_FOLDED;
        default:
            /* style ANY: honour psych's plain/quoted hints.  Forcing a plain
             * scalar plain keeps libfyaml from tagging empty scalars (nil) as
             * explicit nulls; the quoted hint keeps number-like strings from
             * being re-typed on reload. */
            if (quoted) return FYSS_DOUBLE_QUOTED;
            if (plain)  return FYSS_PLAIN;
            return FYSS_ANY;
    }
}

static enum fy_node_style psych_to_fyns(int style)
{
    switch (style) {
        case 1:  return FYNS_BLOCK;
        case 2:  return FYNS_FLOW;
        default: return FYNS_ANY;
    }
}

static VALUE scalar(VALUE self, VALUE value, VALUE anchor, VALUE tag,
        VALUE plain, VALUE quoted, VALUE style)
{
    psych_fy_emitter_t *e;
    rb_encoding *encoding = rb_utf8_encoding();

    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);
    Check_Type(value, T_STRING);

    value = rb_str_export_to_enc(value, encoding);
    if (!NIL_P(anchor)) { Check_Type(anchor, T_STRING); anchor = rb_str_export_to_enc(anchor, encoding); }
    if (!NIL_P(tag))    { Check_Type(tag, T_STRING);    tag    = rb_str_export_to_enc(tag, encoding); }

    enum fy_scalar_style fyss = psych_to_fyss(NUM2INT(style), RTEST(plain), RTEST(quoted));

    /* libyaml omits the tag when plain_implicit (or quoted_implicit) is set,
     * since the value resolves to that tag on reload.  fy_emit_event_create()
     * has no implicit flag and would always print the tag (e.g. nil as
     * "!<tag:yaml.org,2002:null>"), so drop it here to match. */
    int emit_tag = !NIL_P(tag) && !RTEST(plain) && !RTEST(quoted);

    struct fy_event *event = fy_emit_event_create(e->emit, FYET_SCALAR,
            fyss,
            RSTRING_PTR(value), (size_t)RSTRING_LEN(value),
            NIL_P(anchor) ? NULL : StringValueCStr(anchor),
            emit_tag ? StringValueCStr(tag) : NULL);

    do_emit(e, event);
    RB_GC_GUARD(value);
    RB_GC_GUARD(anchor);
    RB_GC_GUARD(tag);
    return self;
}

static VALUE start_sequence(VALUE self, VALUE anchor, VALUE tag,
        VALUE implicit, VALUE style)
{
    psych_fy_emitter_t *e;
    rb_encoding *encoding = rb_utf8_encoding();

    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);

    if (!NIL_P(anchor)) { Check_Type(anchor, T_STRING); anchor = rb_str_export_to_enc(anchor, encoding); }
    if (!NIL_P(tag))    { Check_Type(tag, T_STRING);    tag    = rb_str_export_to_enc(tag, encoding); }

    struct fy_event *event = fy_emit_event_create(e->emit, FYET_SEQUENCE_START,
            psych_to_fyns(NUM2INT(style)),
            NIL_P(anchor) ? NULL : StringValueCStr(anchor),
            NIL_P(tag) ? NULL : StringValueCStr(tag));

    do_emit(e, event);
    RB_GC_GUARD(anchor);
    RB_GC_GUARD(tag);
    return self;
}

static VALUE end_sequence(VALUE self)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);

    do_emit(e, fy_emit_event_create(e->emit, FYET_SEQUENCE_END));
    return self;
}

static VALUE start_mapping(VALUE self, VALUE anchor, VALUE tag,
        VALUE implicit, VALUE style)
{
    psych_fy_emitter_t *e;
    rb_encoding *encoding = rb_utf8_encoding();

    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);

    if (!NIL_P(anchor)) { Check_Type(anchor, T_STRING); anchor = rb_str_export_to_enc(anchor, encoding); }
    if (!NIL_P(tag))    { Check_Type(tag, T_STRING);    tag    = rb_str_export_to_enc(tag, encoding); }

    struct fy_event *event = fy_emit_event_create(e->emit, FYET_MAPPING_START,
            psych_to_fyns(NUM2INT(style)),
            NIL_P(anchor) ? NULL : StringValueCStr(anchor),
            NIL_P(tag) ? NULL : StringValueCStr(tag));

    do_emit(e, event);
    RB_GC_GUARD(anchor);
    RB_GC_GUARD(tag);
    return self;
}

static VALUE end_mapping(VALUE self)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);

    do_emit(e, fy_emit_event_create(e->emit, FYET_MAPPING_END));
    return self;
}

static VALUE alias(VALUE self, VALUE anchor)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);

    if (!NIL_P(anchor)) { Check_Type(anchor, T_STRING); anchor = rb_str_export_to_enc(anchor, rb_utf8_encoding()); }

    do_emit(e, fy_emit_event_create(e->emit, FYET_ALIAS,
            NIL_P(anchor) ? NULL : StringValueCStr(anchor)));
    RB_GC_GUARD(anchor);
    return self;
}

static VALUE set_canonical(VALUE self, VALUE style)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);
    e->canonical = (Qtrue == style) ? 1 : 0;
    rebuild_emitter(self, e);
    return style;
}

static VALUE canonical(VALUE self)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);
    return e->canonical ? Qtrue : Qfalse;
}

static VALUE set_indentation(VALUE self, VALUE level)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);
    e->indent = NUM2INT(level);
    rebuild_emitter(self, e);
    return level;
}

static VALUE indentation(VALUE self)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);
    return INT2NUM(e->indent);
}

static VALUE line_width(VALUE self)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);
    return INT2NUM(e->width);
}

static VALUE set_line_width(VALUE self, VALUE width)
{
    psych_fy_emitter_t *e;
    TypedData_Get_Struct(self, psych_fy_emitter_t, &psych_emitter_type, e);
    e->width = NUM2INT(width);
    rebuild_emitter(self, e);
    return width;
}

void Init_psych_emitter(void)
{
#undef rb_intern
    VALUE psych     = rb_define_module("Psych");
    VALUE handler   = rb_define_class_under(psych, "Handler", rb_cObject);
    cPsychEmitter   = rb_define_class_under(psych, "Emitter", handler);

    rb_define_alloc_func(cPsychEmitter, allocate);

    rb_define_method(cPsychEmitter, "initialize", initialize, -1);
    rb_define_method(cPsychEmitter, "start_stream", start_stream, 1);
    rb_define_method(cPsychEmitter, "end_stream", end_stream, 0);
    rb_define_method(cPsychEmitter, "start_document", start_document, 3);
    rb_define_method(cPsychEmitter, "end_document", end_document, 1);
    rb_define_method(cPsychEmitter, "scalar", scalar, 6);
    rb_define_method(cPsychEmitter, "start_sequence", start_sequence, 4);
    rb_define_method(cPsychEmitter, "end_sequence", end_sequence, 0);
    rb_define_method(cPsychEmitter, "start_mapping", start_mapping, 4);
    rb_define_method(cPsychEmitter, "end_mapping", end_mapping, 0);
    rb_define_method(cPsychEmitter, "alias", alias, 1);
    rb_define_method(cPsychEmitter, "canonical", canonical, 0);
    rb_define_method(cPsychEmitter, "canonical=", set_canonical, 1);
    rb_define_method(cPsychEmitter, "indentation", indentation, 0);
    rb_define_method(cPsychEmitter, "indentation=", set_indentation, 1);
    rb_define_method(cPsychEmitter, "line_width", line_width, 0);
    rb_define_method(cPsychEmitter, "line_width=", set_line_width, 1);

    id_io          = rb_intern("io");
    id_write       = rb_intern("write");
    id_line_width  = rb_intern("line_width");
    id_indentation = rb_intern("indentation");
    id_canonical   = rb_intern("canonical");
}

#endif /* PSYCH_USE_LIBFYAML */
