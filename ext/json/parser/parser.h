#ifndef _PARSER_H_
#define _PARSER_H_

#include "ruby.h"

#ifndef MAYBE_UNUSED
# define MAYBE_UNUSED(x) x
#endif

#define option_given_p(opts, key) (rb_hash_lookup2(opts, key, Qundef) != Qundef)

typedef struct JSON_ParserStruct {
    VALUE Vsource;
    char *source;
    long len;
    char *memo;
    VALUE create_id;
    int max_nesting;
    int allow_nan;
    int parsing_name;
    int symbolize_names;
    int freeze;
    VALUE object_class;
    VALUE array_class;
    VALUE decimal_class;
    int create_additions;
    VALUE match_string;
    FBuffer *fbuffer;
} JSON_Parser;

#define GET_PARSER                          \
    GET_PARSER_INIT;                        \
    if (!json->Vsource) rb_raise(rb_eTypeError, "uninitialized instance")
#define GET_PARSER_INIT                     \
    JSON_Parser *json;                      \
    TypedData_Get_Struct(self, JSON_Parser, &JSON_Parser_type, json)

#define MinusInfinity "-Infinity"
#define EVIL 0x666

static uint32_t unescape_unicode(const unsigned char *p);
static int convert_UTF32_to_UTF8(char *buf, uint32_t ch);
static char *JSON_parse_object(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting);
static char *JSON_parse_value(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting);
static char *JSON_parse_integer(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_float(JSON_Parser *json, char *p, char *pe, VALUE *result);
static char *JSON_parse_array(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting);
static VALUE json_string_unescape(char *string, char *stringEnd, int intern, int symbolize);
static char *JSON_parse_string(JSON_Parser *json, char *p, char *pe, VALUE *result);
static VALUE convert_encoding(VALUE source);
static VALUE cParser_initialize(int argc, VALUE *argv, VALUE self);
static VALUE cParser_parse(VALUE self);
static void JSON_mark(void *json);
static void JSON_free(void *json);
static VALUE cJSON_parser_s_allocate(VALUE klass);
static VALUE cParser_source(VALUE self);

static const rb_data_type_t JSON_Parser_type;

#endif
