#include <psych.h>

VALUE cPsychParser;
VALUE ePsychSyntaxError;

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

#define PSYCH_TRANSCODE(_str, _yaml_enc, _internal_enc) \
  do { \
    rb_enc_associate_index(_str, _yaml_enc); \
    if(_internal_enc) \
      _str = rb_str_export_to_enc(_str, _internal_enc); \
  } while (0)

static int io_reader(void * data, unsigned char *buf, size_t size, size_t *read)
{
    VALUE io = (VALUE)data;
    VALUE string = rb_funcall(io, id_read, 1, INT2NUM(size));

    *read = 0;

    if(! NIL_P(string)) {
	void * str = (void *)StringValuePtr(string);
	*read = (size_t)RSTRING_LEN(string);
	memcpy(buf, str, *read);
    }

    return 1;
}

/*
 * call-seq:
 *    parser.parse(yaml)
 *
 * Parse the YAML document contained in +yaml+.  Events will be called on
 * the handler set on the parser instance.
 *
 * See Psych::Parser and Psych::Parser#handler
 */
static VALUE parse(VALUE self, VALUE yaml)
{
    yaml_parser_t parser;
    yaml_event_t event;
    int done = 0;
#ifdef HAVE_RUBY_ENCODING_H
    int encoding = rb_enc_find_index("ASCII-8BIT");
    rb_encoding * internal_enc;
#endif
    VALUE handler = rb_iv_get(self, "@handler");


    yaml_parser_initialize(&parser);

    if(rb_respond_to(yaml, id_read)) {
	yaml_parser_set_input(&parser, io_reader, (void *)yaml);
    } else {
	StringValue(yaml);
	yaml_parser_set_input_string(
		&parser,
		(const unsigned char *)RSTRING_PTR(yaml),
		(size_t)RSTRING_LEN(yaml)
		);
    }

    while(!done) {
	if(!yaml_parser_parse(&parser, &event)) {
	    size_t line   = parser.mark.line;
	    size_t column = parser.mark.column;

	    yaml_parser_delete(&parser);
	    rb_raise(ePsychSyntaxError, "couldn't parse YAML at line %d column %d",
		    (int)line, (int)column);
	}

	switch(event.type) {
	  case YAML_STREAM_START_EVENT:

#ifdef HAVE_RUBY_ENCODING_H
	    switch(event.data.stream_start.encoding) {
	      case YAML_ANY_ENCODING:
		break;
	      case YAML_UTF8_ENCODING:
		encoding = rb_enc_find_index("UTF-8");
		break;
	      case YAML_UTF16LE_ENCODING:
		encoding = rb_enc_find_index("UTF-16LE");
		break;
	      case YAML_UTF16BE_ENCODING:
		encoding = rb_enc_find_index("UTF-16BE");
		break;
	      default:
		break;
	    }
	    internal_enc = rb_default_internal_encoding();
#endif

	    rb_funcall(handler, id_start_stream, 1,
		       INT2NUM((long)event.data.stream_start.encoding)
		);
	    break;
	  case YAML_DOCUMENT_START_EVENT:
	    {
		/* Get a list of tag directives (if any) */
		VALUE tag_directives = rb_ary_new();
		/* Grab the document version */
		VALUE version = event.data.document_start.version_directive ?
		    rb_ary_new3(
			(long)2,
			INT2NUM((long)event.data.document_start.version_directive->major),
			INT2NUM((long)event.data.document_start.version_directive->minor)
			) : rb_ary_new();

		if(event.data.document_start.tag_directives.start) {
		    yaml_tag_directive_t *start =
			event.data.document_start.tag_directives.start;
		    yaml_tag_directive_t *end =
			event.data.document_start.tag_directives.end;
		    for(; start != end; start++) {
			VALUE handle = Qnil;
			VALUE prefix = Qnil;
			if(start->handle) {
			    handle = rb_str_new2((const char *)start->handle);
#ifdef HAVE_RUBY_ENCODING_H
			    PSYCH_TRANSCODE(handle, encoding, internal_enc);
#endif
			}

			if(start->prefix) {
			    prefix = rb_str_new2((const char *)start->prefix);
#ifdef HAVE_RUBY_ENCODING_H
			    PSYCH_TRANSCODE(prefix, encoding, internal_enc);
#endif
			}

			rb_ary_push(tag_directives, rb_ary_new3((long)2, handle, prefix));
		    }
		}
		rb_funcall(handler, id_start_document, 3,
			   version, tag_directives,
			   event.data.document_start.implicit == 1 ? Qtrue : Qfalse
		    );
	    }
	    break;
	  case YAML_DOCUMENT_END_EVENT:
	    rb_funcall(handler, id_end_document, 1,
		       event.data.document_end.implicit == 1 ? Qtrue : Qfalse
		);
	    break;
	  case YAML_ALIAS_EVENT:
	    {
		VALUE alias = Qnil;
		if(event.data.alias.anchor) {
		    alias = rb_str_new2((const char *)event.data.alias.anchor);
#ifdef HAVE_RUBY_ENCODING_H
		    PSYCH_TRANSCODE(alias, encoding, internal_enc);
#endif
		}

		rb_funcall(handler, id_alias, 1, alias);
	    }
	    break;
	  case YAML_SCALAR_EVENT:
	    {
		VALUE anchor = Qnil;
		VALUE tag = Qnil;
		VALUE plain_implicit, quoted_implicit, style;
		VALUE val = rb_str_new(
		    (const char *)event.data.scalar.value,
		    (long)event.data.scalar.length
		    );

#ifdef HAVE_RUBY_ENCODING_H
		PSYCH_TRANSCODE(val, encoding, internal_enc);
#endif

		if(event.data.scalar.anchor) {
		    anchor = rb_str_new2((const char *)event.data.scalar.anchor);
#ifdef HAVE_RUBY_ENCODING_H
		    PSYCH_TRANSCODE(anchor, encoding, internal_enc);
#endif
		}

		if(event.data.scalar.tag) {
		    tag = rb_str_new2((const char *)event.data.scalar.tag);
#ifdef HAVE_RUBY_ENCODING_H
		    PSYCH_TRANSCODE(tag, encoding, internal_enc);
#endif
		}

		plain_implicit =
		    event.data.scalar.plain_implicit == 0 ? Qfalse : Qtrue;

		quoted_implicit =
		    event.data.scalar.quoted_implicit == 0 ? Qfalse : Qtrue;

		style = INT2NUM((long)event.data.scalar.style);

		rb_funcall(handler, id_scalar, 6,
			   val, anchor, tag, plain_implicit, quoted_implicit, style);
	    }
	    break;
	  case YAML_SEQUENCE_START_EVENT:
	    {
		VALUE anchor = Qnil;
		VALUE tag = Qnil;
		VALUE implicit, style;
		if(event.data.sequence_start.anchor) {
		    anchor = rb_str_new2((const char *)event.data.sequence_start.anchor);
#ifdef HAVE_RUBY_ENCODING_H
		    PSYCH_TRANSCODE(anchor, encoding, internal_enc);
#endif
		}

		tag = Qnil;
		if(event.data.sequence_start.tag) {
		    tag = rb_str_new2((const char *)event.data.sequence_start.tag);
#ifdef HAVE_RUBY_ENCODING_H
		    PSYCH_TRANSCODE(tag, encoding, internal_enc);
#endif
		}

		implicit =
		    event.data.sequence_start.implicit == 0 ? Qfalse : Qtrue;

		style = INT2NUM((long)event.data.sequence_start.style);

		rb_funcall(handler, id_start_sequence, 4,
			   anchor, tag, implicit, style);
	    }
	    break;
	  case YAML_SEQUENCE_END_EVENT:
	    rb_funcall(handler, id_end_sequence, 0);
	    break;
	  case YAML_MAPPING_START_EVENT:
	    {
		VALUE anchor = Qnil;
		VALUE tag = Qnil;
		VALUE implicit, style;
		if(event.data.mapping_start.anchor) {
		    anchor = rb_str_new2((const char *)event.data.mapping_start.anchor);
#ifdef HAVE_RUBY_ENCODING_H
		    PSYCH_TRANSCODE(anchor, encoding, internal_enc);
#endif
		}

		if(event.data.mapping_start.tag) {
		    tag = rb_str_new2((const char *)event.data.mapping_start.tag);
#ifdef HAVE_RUBY_ENCODING_H
		    PSYCH_TRANSCODE(tag, encoding, internal_enc);
#endif
		}

		implicit =
		    event.data.mapping_start.implicit == 0 ? Qfalse : Qtrue;

		style = INT2NUM((long)event.data.mapping_start.style);

		rb_funcall(handler, id_start_mapping, 4,
			   anchor, tag, implicit, style);
	    }
	    break;
	  case YAML_MAPPING_END_EVENT:
	    rb_funcall(handler, id_end_mapping, 0);
	    break;
	  case YAML_NO_EVENT:
	    rb_funcall(handler, id_empty, 0);
	    break;
	  case YAML_STREAM_END_EVENT:
	    rb_funcall(handler, id_end_stream, 0);
	    done = 1;
	    break;
	}
    }

    return self;
}

void Init_psych_parser()
{
#if 0
    mPsych = rb_define_module("Psych");
#endif

    cPsychParser = rb_define_class_under(mPsych, "Parser", rb_cObject);

    /* Any encoding: Let the parser choose the encoding */
    rb_define_const(cPsychParser, "ANY", INT2NUM(YAML_ANY_ENCODING));

    /* UTF-8 Encoding */
    rb_define_const(cPsychParser, "UTF8", INT2NUM(YAML_UTF8_ENCODING));

    /* UTF-16-LE Encoding with BOM */
    rb_define_const(cPsychParser, "UTF16LE", INT2NUM(YAML_UTF16LE_ENCODING));

    /* UTF-16-BE Encoding with BOM */
    rb_define_const(cPsychParser, "UTF16BE", INT2NUM(YAML_UTF16BE_ENCODING));

    ePsychSyntaxError = rb_define_class_under(mPsych, "SyntaxError", rb_eSyntaxError);

    rb_define_method(cPsychParser, "parse", parse, 1);

    id_read           = rb_intern("read");
    id_empty          = rb_intern("empty");
    id_start_stream   = rb_intern("start_stream");
    id_end_stream     = rb_intern("end_stream");
    id_start_document = rb_intern("start_document");
    id_end_document   = rb_intern("end_document");
    id_alias          = rb_intern("alias");
    id_scalar         = rb_intern("scalar");
    id_start_sequence = rb_intern("start_sequence");
    id_end_sequence   = rb_intern("end_sequence");
    id_start_mapping  = rb_intern("start_mapping");
    id_end_mapping    = rb_intern("end_mapping");
}
/* vim: set noet sws=4 sw=4: */
