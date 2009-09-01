#include "ruby.h"
#include "unicode.h"
#if HAVE_RE_H
#include "re.h"
#endif
#if HAVE_RUBY_ST_H
#include "ruby/st.h"
#endif
#if HAVE_ST_H
#include "st.h"
#endif

#define EVIL 0x666

#ifndef RHASH_TBL
#define RHASH_TBL(hsh) (RHASH(hsh)->tbl)
#endif

#ifdef HAVE_RUBY_ENCODING_H
#include "ruby/encoding.h"
#define FORCE_UTF8(obj) rb_enc_associate((obj), rb_utf8_encoding())
#else
#define FORCE_UTF8(obj)
#endif

static VALUE mJSON, mExt, cParser, eParserError, eNestingError;
static VALUE CNaN, CInfinity, CMinusInfinity;

static ID i_json_creatable_p, i_json_create, i_create_id, i_create_additions,
          i_chr, i_max_nesting, i_allow_nan, i_object_class, i_array_class; 

#define MinusInfinity "-Infinity"

typedef struct JSON_ParserStruct {
    VALUE Vsource;
    char *source;
    long len;
    char *memo;
    VALUE create_id;
    int max_nesting;
    int current_nesting;
    int allow_nan;
    VALUE object_class;
    VALUE array_class;
} JSON_Parser;

static char *JSON_parse_object(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_array(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_value(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_string(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_integer(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_float(JSON_Parser *json, char *p, char *pe, VALUE *result);

#define GET_STRUCT                          \
    JSON_Parser *json;                      \
    Data_Get_Struct(self, JSON_Parser, json);

%%{
    machine JSON_common;

    cr                  = '\n';
    cr_neg              = [^\n];
    ws                  = [ \t\r\n];
    c_comment           = '/*' ( any* - (any* '*/' any* ) ) '*/';
    cpp_comment         = '//' cr_neg* cr;
    comment             = c_comment | cpp_comment;
    ignore              = ws | comment;
    name_separator      = ':';
    value_separator     = ',';
    Vnull               = 'null';
    Vfalse              = 'false';
    Vtrue               = 'true';
    VNaN                = 'NaN';
    VInfinity           = 'Infinity';
    VMinusInfinity      = '-Infinity';
    begin_value         = [nft"\-[{NI] | digit;
    begin_object        = '{';
    end_object          = '}';
    begin_array         = '[';
    end_array           = ']';
    begin_string        = '"';
    begin_name          = begin_string;
    begin_number        = digit | '-';
}%%

%%{
    machine JSON_object;
    include JSON_common;

    write data;

    action parse_value {
        VALUE v = Qnil;
        char *np = JSON_parse_value(json, fpc, pe, &v); 
        if (np == NULL) {
            fhold; fbreak;
        } else {
            rb_hash_aset(*result, last_name, v);
            fexec np;
        }
    }

    action parse_name {
        char *np = JSON_parse_string(json, fpc, pe, &last_name);
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action exit { fhold; fbreak; }

    a_pair  = ignore* begin_name >parse_name
        ignore* name_separator ignore*
        begin_value >parse_value;

    main := begin_object
          (a_pair (ignore* value_separator a_pair)*)?
          ignore* end_object @exit;
}%%

static char *JSON_parse_object(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;
    VALUE last_name = Qnil;
    VALUE object_class = json->object_class;

    if (json->max_nesting && json->current_nesting > json->max_nesting) {
        rb_raise(eNestingError, "nesting of %d is too deep", json->current_nesting);
    }

    *result = NIL_P(object_class) ? rb_hash_new() : rb_class_new_instance(0, 0, object_class);

    %% write init;
    %% write exec;

    if (cs >= JSON_object_first_final) {
        if (RTEST(json->create_id)) {
            VALUE klassname = rb_hash_aref(*result, json->create_id);
            if (!NIL_P(klassname)) {
                VALUE klass = rb_path2class(StringValueCStr(klassname));
                if RTEST(rb_funcall(klass, i_json_creatable_p, 0)) {
                    *result = rb_funcall(klass, i_json_create, 1, *result);
                }
            }
        }
        return p + 1;
    } else {
        return NULL;
    }
}

%%{
    machine JSON_value;
    include JSON_common;

    write data;

    action parse_null {
        *result = Qnil;
    }
    action parse_false {
        *result = Qfalse;
    }
    action parse_true {
        *result = Qtrue;
    }
    action parse_nan {
        if (json->allow_nan) {
            *result = CNaN;
        } else {
            rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p - 2);
        }
    }
    action parse_infinity {
        if (json->allow_nan) {
            *result = CInfinity;
        } else {
            rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p - 8);
        }
    }
    action parse_string {
        char *np = JSON_parse_string(json, fpc, pe, result);
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_number {
        char *np;
        if(pe > fpc + 9 && !strncmp(MinusInfinity, fpc, 9)) {
            if (json->allow_nan) {
                *result = CMinusInfinity;
                fexec p + 10;
                fhold; fbreak;
            } else {
                rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p);
            }
        }
        np = JSON_parse_float(json, fpc, pe, result);
        if (np != NULL) fexec np;
        np = JSON_parse_integer(json, fpc, pe, result);
        if (np != NULL) fexec np;
        fhold; fbreak;
    }

    action parse_array { 
        char *np;
        json->current_nesting++;
        np = JSON_parse_array(json, fpc, pe, result);
        json->current_nesting--;
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_object { 
        char *np;
        json->current_nesting++;
        np =  JSON_parse_object(json, fpc, pe, result);
        json->current_nesting--;
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action exit { fhold; fbreak; }

main := (
              Vnull @parse_null |
              Vfalse @parse_false |
              Vtrue @parse_true |
              VNaN @parse_nan |
              VInfinity @parse_infinity |
              begin_number >parse_number |
              begin_string >parse_string |
              begin_array >parse_array |
              begin_object >parse_object
        ) %*exit;
}%%

static char *JSON_parse_value(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;

    %% write init;
    %% write exec;

    if (cs >= JSON_value_first_final) {
        return p;
    } else {
        return NULL;
    }
}

%%{
    machine JSON_integer;

    write data;

    action exit { fhold; fbreak; }

    main := '-'? ('0' | [1-9][0-9]*) (^[0-9] @exit);
}%%

static char *JSON_parse_integer(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;

    %% write init;
    json->memo = p;
    %% write exec;

    if (cs >= JSON_integer_first_final) {
        long len = p - json->memo;
        *result = rb_Integer(rb_str_new(json->memo, len));
        return p + 1;
    } else {
        return NULL;
    }
}

%%{
    machine JSON_float;
    include JSON_common;

    write data;

    action exit { fhold; fbreak; }

    main := '-'? (
              (('0' | [1-9][0-9]*) '.' [0-9]+ ([Ee] [+\-]?[0-9]+)?)
              | (('0' | [1-9][0-9]*) ([Ee] [+\-]?[0-9]+))
             )  (^[0-9Ee.\-] @exit );
}%%

static char *JSON_parse_float(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;

    %% write init;
    json->memo = p;
    %% write exec;

    if (cs >= JSON_float_first_final) {
        long len = p - json->memo;
        *result = rb_Float(rb_str_new(json->memo, len));
        return p + 1;
    } else {
        return NULL;
    }
}


%%{
    machine JSON_array;
    include JSON_common;

    write data;

    action parse_value {
        VALUE v = Qnil;
        char *np = JSON_parse_value(json, fpc, pe, &v); 
        if (np == NULL) {
            fhold; fbreak;
        } else {
            rb_ary_push(*result, v);
            fexec np;
        }
    }

    action exit { fhold; fbreak; }

    next_element  = value_separator ignore* begin_value >parse_value;

    main := begin_array ignore*
          ((begin_value >parse_value ignore*)
           (ignore* next_element ignore*)*)?
          end_array @exit;
}%%

static char *JSON_parse_array(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;
    VALUE array_class = json->array_class;

    if (json->max_nesting && json->current_nesting > json->max_nesting) {
        rb_raise(eNestingError, "nesting of %d is too deep", json->current_nesting);
    }
    *result = NIL_P(array_class) ? rb_ary_new() : rb_class_new_instance(0, 0, array_class);

    %% write init;
    %% write exec;

    if(cs >= JSON_array_first_final) {
        return p + 1;
    } else {
        rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p);
    }
}

static VALUE json_string_unescape(char *p, char *pe)
{
    VALUE result = rb_str_buf_new(pe - p + 1);

    while (p < pe) {
        if (*p == '\\') {
            p++;
            if (p >= pe) return Qnil; /* raise an exception later, \ at end */
            switch (*p) {
                case '"':
                case '\\':
                    rb_str_buf_cat(result, p, 1);
                    p++;
                    break;
                case 'b':
                    rb_str_buf_cat2(result, "\b");
                    p++;
                    break;
                case 'f':
                    rb_str_buf_cat2(result, "\f");
                    p++;
                    break;
                case 'n':
                    rb_str_buf_cat2(result, "\n");
                    p++;
                    break;
                case 'r':
                    rb_str_buf_cat2(result, "\r");
                    p++;
                    break;
                case 't':
                    rb_str_buf_cat2(result, "\t");
                    p++;
                    break;
                case 'u':
                    if (p > pe - 4) { 
                        return Qnil;
                    } else {
                        p = JSON_convert_UTF16_to_UTF8(result, p, pe, strictConversion);
                    }
                    break;
                default:
                    rb_str_buf_cat(result, p, 1);
                    p++;
                    break;
            }
        } else {
            char *q = p;
            while (*q != '\\' && q < pe) q++;
            rb_str_buf_cat(result, p, q - p);
            p = q;
        }
    }
    return result;
}

%%{
    machine JSON_string;
    include JSON_common;

    write data;

    action parse_string {
        *result = json_string_unescape(json->memo + 1, p);
        if (NIL_P(*result)) {
			fhold;
			fbreak;
		} else {
			FORCE_UTF8(*result);
			fexec p + 1;
		}
	}

    action exit { fhold; fbreak; }

    main := '"' ((^(["\\] | 0..0x1f) | '\\'["\\/bfnrt] | '\\u'[0-9a-fA-F]{4} | '\\'^(["\\/bfnrtu]|0..0x1f))* %parse_string) '"' @exit;
}%%

static char *JSON_parse_string(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;

    *result = rb_str_new("", 0);
    %% write init;
    json->memo = p;
    %% write exec;

    if (cs >= JSON_string_first_final) {
        return p + 1;
    } else {
        return NULL;
    }
}


%%{
    machine JSON;

    write data;

    include JSON_common;

    action parse_object {
        char *np;
        json->current_nesting = 1;
        np = JSON_parse_object(json, fpc, pe, &result);
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    action parse_array {
        char *np;
        json->current_nesting = 1;
        np = JSON_parse_array(json, fpc, pe, &result);
        if (np == NULL) { fhold; fbreak; } else fexec np;
    }

    main := ignore* (
            begin_object >parse_object |
            begin_array >parse_array
            ) ignore*;
}%%

/* 
 * Document-class: JSON::Ext::Parser
 *
 * This is the JSON parser implemented as a C extension. It can be configured
 * to be used by setting
 *
 *  JSON.parser = JSON::Ext::Parser
 *
 * with the method parser= in JSON.
 *
 */

/*
 * call-seq: new(source, opts => {})
 *
 * Creates a new JSON::Ext::Parser instance for the string _source_.
 *
 * Creates a new JSON::Ext::Parser instance for the string _source_.
 *
 * It will be configured by the _opts_ hash. _opts_ can have the following
 * keys:
 *
 * _opts_ can have the following keys:
 * * *max_nesting*: The maximum depth of nesting allowed in the parsed data
 *   structures. Disable depth checking with :max_nesting => false|nil|0, it
 *   defaults to 19.
 * * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
 *   defiance of RFC 4627 to be parsed by the Parser. This option defaults to
 *   false.
 * * *create_additions*: If set to false, the Parser doesn't create
 *   additions even if a matchin class and create_id was found. This option
 *   defaults to true.
 * * *object_class*: Defaults to Hash
 * * *array_class*: Defaults to Array
 */
static VALUE cParser_initialize(int argc, VALUE *argv, VALUE self)
{
    char *ptr;
    long len;
    VALUE source, opts;
    GET_STRUCT;
    rb_scan_args(argc, argv, "11", &source, &opts);
    source = StringValue(source);
    ptr = RSTRING_PTR(source);
    len = RSTRING_LEN(source);
    if (len < 2) {
        rb_raise(eParserError, "A JSON text must at least contain two octets!");
    }
    if (!NIL_P(opts)) {
        opts = rb_convert_type(opts, T_HASH, "Hash", "to_hash");
        if (NIL_P(opts)) {
            rb_raise(rb_eArgError, "opts needs to be like a hash");
        } else {
            VALUE tmp = ID2SYM(i_max_nesting);
            if (st_lookup(RHASH_TBL(opts), tmp, 0)) {
                VALUE max_nesting = rb_hash_aref(opts, tmp);
                if (RTEST(max_nesting)) {
                    Check_Type(max_nesting, T_FIXNUM);
                    json->max_nesting = FIX2INT(max_nesting);
                } else {
                    json->max_nesting = 0;
                }
            } else {
                json->max_nesting = 19;
            }
            tmp = ID2SYM(i_allow_nan);
            if (st_lookup(RHASH_TBL(opts), tmp, 0)) {
                VALUE allow_nan = rb_hash_aref(opts, tmp);
                json->allow_nan = RTEST(allow_nan) ? 1 : 0;
            } else {
                json->allow_nan = 0;
            }
            tmp = ID2SYM(i_create_additions);
            if (st_lookup(RHASH_TBL(opts), tmp, 0)) {
                VALUE create_additions = rb_hash_aref(opts, tmp);
                if (RTEST(create_additions)) {
                    json->create_id = rb_funcall(mJSON, i_create_id, 0);
                } else {
                    json->create_id = Qnil;
                }
            } else {
                json->create_id = rb_funcall(mJSON, i_create_id, 0);
            }
            tmp = ID2SYM(i_object_class);
            if (st_lookup(RHASH_TBL(opts), tmp, 0)) {
                json->object_class = rb_hash_aref(opts, tmp);
            } else {
                json->object_class = Qnil;
            }
            tmp = ID2SYM(i_array_class);
            if (st_lookup(RHASH_TBL(opts), tmp, 0)) {
                json->array_class = rb_hash_aref(opts, tmp);
            } else {
                json->array_class = Qnil;
            }
        }
    } else {
        json->max_nesting = 19;
        json->allow_nan = 0;
        json->create_id = rb_funcall(mJSON, i_create_id, 0);
        json->object_class = Qnil;
        json->array_class = Qnil;
    }
    json->current_nesting = 0;
    /*
       Convert these?
    if (len >= 4 &&  ptr[0] == 0 && ptr[1] == 0 && ptr[2] == 0) {
        rb_raise(eParserError, "Only UTF8 octet streams are supported atm!");
    } else if (len >= 4 && ptr[0] == 0 && ptr[2] == 0) {
        rb_raise(eParserError, "Only UTF8 octet streams are supported atm!");
    } else if (len >= 4 && ptr[1] == 0 && ptr[2] == 0 && ptr[3] == 0) {
        rb_raise(eParserError, "Only UTF8 octet streams are supported atm!");
    } else if (len >= 4 && ptr[1] == 0 && ptr[3] == 0) {
        rb_raise(eParserError, "Only UTF8 octet streams are supported atm!");
    }
    */
    json->len = len;
    json->source = ptr;
    json->Vsource = source;
    return self;
}

/*
 * call-seq: parse()
 *
 *  Parses the current JSON text _source_ and returns the complete data
 *  structure as a result.
 */
static VALUE cParser_parse(VALUE self)
{
    char *p, *pe;
    int cs = EVIL;
    VALUE result = Qnil;
    GET_STRUCT;

    %% write init;
    p = json->source;
    pe = p + json->len;
    %% write exec;

    if (cs >= JSON_first_final && p == pe) {
        return result;
    } else {
        rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p);
    }
}

inline static JSON_Parser *JSON_allocate()
{
    JSON_Parser *json = ALLOC(JSON_Parser);
    MEMZERO(json, JSON_Parser, 1);
    return json;
}

static void JSON_mark(JSON_Parser *json)
{
    rb_gc_mark_maybe(json->Vsource);
    rb_gc_mark_maybe(json->create_id);
    rb_gc_mark_maybe(json->object_class);
    rb_gc_mark_maybe(json->array_class);
}

static void JSON_free(JSON_Parser *json)
{
    ruby_xfree(json);
}

static VALUE cJSON_parser_s_allocate(VALUE klass)
{
    JSON_Parser *json = JSON_allocate();
    return Data_Wrap_Struct(klass, JSON_mark, JSON_free, json);
}

/*
 * call-seq: source()
 *
 * Returns a copy of the current _source_ string, that was used to construct
 * this Parser.
 */
static VALUE cParser_source(VALUE self)
{
    GET_STRUCT;
    return rb_str_dup(json->Vsource);
}

void Init_parser()
{
    rb_require("json/common");
    mJSON = rb_define_module("JSON");
    mExt = rb_define_module_under(mJSON, "Ext");
    cParser = rb_define_class_under(mExt, "Parser", rb_cObject);
    eParserError = rb_path2class("JSON::ParserError");
    eNestingError = rb_path2class("JSON::NestingError");
    rb_define_alloc_func(cParser, cJSON_parser_s_allocate);
    rb_define_method(cParser, "initialize", cParser_initialize, -1);
    rb_define_method(cParser, "parse", cParser_parse, 0);
    rb_define_method(cParser, "source", cParser_source, 0);

    CNaN = rb_const_get(mJSON, rb_intern("NaN"));
    CInfinity = rb_const_get(mJSON, rb_intern("Infinity"));
    CMinusInfinity = rb_const_get(mJSON, rb_intern("MinusInfinity"));

    i_json_creatable_p = rb_intern("json_creatable?");
    i_json_create = rb_intern("json_create");
    i_create_id = rb_intern("create_id");
    i_create_additions = rb_intern("create_additions");
    i_chr = rb_intern("chr");
    i_max_nesting = rb_intern("max_nesting");
    i_allow_nan = rb_intern("allow_nan");
    i_object_class = rb_intern("object_class");
    i_array_class = rb_intern("array_class");
}
