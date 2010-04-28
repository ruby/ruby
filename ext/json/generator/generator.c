#include "generator.h"

#ifdef HAVE_RUBY_ENCODING_H
static VALUE CEncoding_UTF_8;
static ID i_encoding, i_encode;
#endif

static VALUE mJSON, mExt, mGenerator, cState, mGeneratorMethods, mObject,
             mHash, mArray, mInteger, mFloat, mString, mString_Extend,
             mTrueClass, mFalseClass, mNilClass, eGeneratorError,
             eNestingError, CRegexp_MULTILINE, CJSON_SAFE_STATE_PROTOTYPE;

static ID i_to_s, i_to_json, i_new, i_indent, i_space, i_space_before,
          i_object_nl, i_array_nl, i_max_nesting, i_allow_nan, i_ascii_only,
          i_pack, i_unpack, i_create_id, i_extend, i_key_p, i_aref, i_send,
          i_respond_to_p, i_match;

/*
 * Copyright 2001-2004 Unicode, Inc.
 * 
 * Disclaimer
 * 
 * This source code is provided as is by Unicode, Inc. No claims are
 * made as to fitness for any particular purpose. No warranties of any
 * kind are expressed or implied. The recipient agrees to determine
 * applicability of information provided. If this file has been
 * purchased on magnetic or optical media from Unicode, Inc., the
 * sole remedy for any claim will be exchange of defective media
 * within 90 days of receipt.
 * 
 * Limitations on Rights to Redistribute This Code
 * 
 * Unicode, Inc. hereby grants the right to freely use the information
 * supplied in this file in the creation of products supporting the
 * Unicode Standard, and to make copies of this file in any form
 * for internal or external distribution as long as this notice
 * remains attached.
 */

/*
 * Index into the table below with the first byte of a UTF-8 sequence to
 * get the number of trailing bytes that are supposed to follow it.
 * Note that *legal* UTF-8 values can't have 4 or 5-bytes. The table is
 * left as-is for anyone who may want to do such conversion, which was
 * allowed in earlier algorithms.
 */
static const char trailingBytesForUTF8[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
};

/*
 * Magic values subtracted from a buffer value during UTF8 conversion.
 * This table contains as many values as there might be trailing bytes
 * in a UTF-8 sequence.
 */
static const UTF32 offsetsFromUTF8[6] = { 0x00000000UL, 0x00003080UL, 0x000E2080UL, 
		     0x03C82080UL, 0xFA082080UL, 0x82082080UL };

/*
 * Utility routine to tell whether a sequence of bytes is legal UTF-8.
 * This must be called with the length pre-determined by the first byte.
 * If not calling this from ConvertUTF8to*, then the length can be set by:
 *  length = trailingBytesForUTF8[*source]+1;
 * and the sequence is illegal right away if there aren't that many bytes
 * available.
 * If presented with a length > 4, this returns 0.  The Unicode
 * definition of UTF-8 goes up to 4-byte sequences.
 */
static unsigned char isLegalUTF8(const UTF8 *source, int length)
{
    UTF8 a;
    const UTF8 *srcptr = source+length;
    switch (length) {
        default: return 0;
                 /* Everything else falls through when "1"... */
        case 4: if ((a = (*--srcptr)) < 0x80 || a > 0xBF) return 0;
        case 3: if ((a = (*--srcptr)) < 0x80 || a > 0xBF) return 0;
        case 2: if ((a = (*--srcptr)) > 0xBF) return 0;

                    switch (*source) {
                        /* no fall-through in this inner switch */
                        case 0xE0: if (a < 0xA0) return 0; break;
                        case 0xED: if (a > 0x9F) return 0; break;
                        case 0xF0: if (a < 0x90) return 0; break;
                        case 0xF4: if (a > 0x8F) return 0; break;
                        default:   if (a < 0x80) return 0;
                    }

        case 1: if (*source >= 0x80 && *source < 0xC2) return 0;
    }
    if (*source > 0xF4) return 0;
    return 1;
}

/* Escapes the UTF16 character and stores the result in the buffer buf. */
static void unicode_escape(char *buf, UTF16 character)
{
    const char *digits = "0123456789abcdef";

    buf[2] = digits[character >> 12];
    buf[3] = digits[(character >> 8) & 0xf];
    buf[4] = digits[(character >> 4) & 0xf];
    buf[5] = digits[character & 0xf];
}

/* Escapes the UTF16 character and stores the result in the buffer buf, then
 * the buffer buf іs appended to the FBuffer buffer. */
static void unicode_escape_to_buffer(FBuffer *buffer, char buf[6], UTF16
        character)
{
    unicode_escape(buf, character);
    fbuffer_append(buffer, buf, 6);
}

/* Converts string to a JSON string in FBuffer buffer, where all but the ASCII
 * and control characters are JSON escaped. */
static void convert_UTF8_to_JSON_ASCII(FBuffer *buffer, VALUE string)
{
    const UTF8 *source = (UTF8 *) RSTRING_PTR(string);
    const UTF8 *sourceEnd = source + RSTRING_LEN(string);
    char buf[6] = { '\\', 'u' };

    while (source < sourceEnd) {
        UTF32 ch = 0;
        unsigned short extraBytesToRead = trailingBytesForUTF8[*source];
        if (source + extraBytesToRead >= sourceEnd) {
            rb_raise(rb_path2class("JSON::GeneratorError"),
                    "partial character in source, but hit end");
        }
        if (!isLegalUTF8(source, extraBytesToRead+1)) {
            rb_raise(rb_path2class("JSON::GeneratorError"),
                    "source sequence is illegal/malformed utf-8");
        }
        /*
         * The cases all fall through. See "Note A" below.
         */
        switch (extraBytesToRead) {
            case 5: ch += *source++; ch <<= 6; /* remember, illegal UTF-8 */
            case 4: ch += *source++; ch <<= 6; /* remember, illegal UTF-8 */
            case 3: ch += *source++; ch <<= 6;
            case 2: ch += *source++; ch <<= 6;
            case 1: ch += *source++; ch <<= 6;
            case 0: ch += *source++;
        }
        ch -= offsetsFromUTF8[extraBytesToRead];

        if (ch <= UNI_MAX_BMP) { /* Target is a character <= 0xFFFF */
            /* UTF-16 surrogate values are illegal in UTF-32 */
            if (ch >= UNI_SUR_HIGH_START && ch <= UNI_SUR_LOW_END) {
#if UNI_STRICT_CONVERSION
                source -= (extraBytesToRead+1); /* return to the illegal value itself */
                rb_raise(rb_path2class("JSON::GeneratorError"),
                        "source sequence is illegal/malformed utf-8");
#else
                unicode_escape_to_buffer(buffer, buf, UNI_REPLACEMENT_CHAR);
#endif
            } else {
                /* normal case */
                if (ch >= 0x20 && ch <= 0x7f) {
                    switch (ch) {
                        case '\\':
                            fbuffer_append(buffer, "\\\\", 2);
                            break;
                        case '"':
                            fbuffer_append(buffer, "\\\"", 2);
                            break;
                        default:
                            fbuffer_append_char(buffer, (char)ch);
                            break;
                    }
                } else {
                    switch (ch) {
                        case '\n':
                            fbuffer_append(buffer, "\\n", 2);
                            break;
                        case '\r':
                            fbuffer_append(buffer, "\\r", 2);
                            break;
                        case '\t':
                            fbuffer_append(buffer, "\\t", 2);
                            break;
                        case '\f':
                            fbuffer_append(buffer, "\\f", 2);
                            break;
                        case '\b':
                            fbuffer_append(buffer, "\\b", 2);
                            break;
                        default:
                            unicode_escape_to_buffer(buffer, buf, (UTF16) ch);
                            break;
                    }
                }
            }
        } else if (ch > UNI_MAX_UTF16) {
#if UNI_STRICT_CONVERSION
            source -= (extraBytesToRead+1); /* return to the start */
            rb_raise(rb_path2class("JSON::GeneratorError"),
                    "source sequence is illegal/malformed utf8");
#else
            unicode_escape_to_buffer(buffer, buf, UNI_REPLACEMENT_CHAR);
#endif
        } else {
            /* target is a character in range 0xFFFF - 0x10FFFF. */
            ch -= halfBase;
            unicode_escape_to_buffer(buffer, buf, (UTF16)((ch >> halfShift) + UNI_SUR_HIGH_START));
            unicode_escape_to_buffer(buffer, buf, (UTF16)((ch & halfMask) + UNI_SUR_LOW_START));
        }
    }
}

/* Converts string to a JSON string in FBuffer buffer, where only the
 * characters required by the JSON standard are JSON escaped. The remaining
 * characters (should be UTF8) are just passed through and appended to the
 * result. */
static void convert_UTF8_to_JSON(FBuffer *buffer, VALUE string)
{
    const char *ptr = RSTRING_PTR(string), *p;
    int len = RSTRING_LEN(string), start = 0, end = 0;
    const char *escape = NULL;
    int escape_len;
    unsigned char c;
    char buf[6] = { '\\', 'u' };

    for (start = 0, end = 0; end < len;) {
        p = ptr + end;
        c = (unsigned char) *p;
        if (c < 0x20) {
            switch (c) {
                case '\n':
                    escape = "\\n";
                    escape_len = 2;
                    break;
                case '\r':
                    escape = "\\r";
                    escape_len = 2;
                    break;
                case '\t':
                    escape = "\\t";
                    escape_len = 2;
                    break;
                case '\f':
                    escape = "\\f";
                    escape_len = 2;
                    break;
                case '\b':
                    escape = "\\b";
                    escape_len = 2;
                    break;
                default:
                    unicode_escape(buf, (UTF16) *p);
                    escape = buf;
                    escape_len = 6;
                    break;
            }
        } else {
            switch (c) {
                case '\\':
                    escape = "\\\\";
                    escape_len = 2;
                    break;
                case '"':
                    escape =  "\\\"";
                    escape_len = 2;
                    break;
                default:
                    end++;
                    continue;
                    break;
            }
        }
        fbuffer_append(buffer, ptr + start, end - start);
        fbuffer_append(buffer, escape, escape_len);
        start = ++end;
        escape = NULL;
    }
    fbuffer_append(buffer, ptr + start, end - start);
}

static char *fstrndup(const char *ptr, int len) {
  char *result;
  if (len <= 0) return NULL;
  result = ALLOC_N(char, len);
  memccpy(result, ptr, 0, len);
  return result;
}

/* fbuffer implementation */

static FBuffer *fbuffer_alloc()
{
    FBuffer *fb = ALLOC(FBuffer);
    memset((void *) fb, 0, sizeof(FBuffer));
    fb->initial_length = FBUFFER_INITIAL_LENGTH;
    return fb;
}

static FBuffer *fbuffer_alloc_with_length(unsigned int initial_length)
{
    FBuffer *fb;
    assert(initial_length > 0);
    fb = ALLOC(FBuffer);
    memset((void *) fb, 0, sizeof(FBuffer));
    fb->initial_length = initial_length;
    return fb;
}

static void fbuffer_free(FBuffer *fb)
{
    if (fb->ptr) ruby_xfree(fb->ptr);
    ruby_xfree(fb);
}

static void fbuffer_free_only_buffer(FBuffer *fb)
{
    ruby_xfree(fb);
}

static void fbuffer_clear(FBuffer *fb)
{
    fb->len = 0;
}

static void fbuffer_inc_capa(FBuffer *fb, unsigned int requested)
{
    unsigned int required;

    if (!fb->ptr) {
        fb->ptr = ALLOC_N(char, fb->initial_length);
        fb->capa = fb->initial_length;
    }

    for (required = fb->capa; requested > required - fb->len; required <<= 1);

    if (required > fb->capa) {
        fb->ptr = (char *) REALLOC_N((long*) fb->ptr, char, required);
        fb->capa = required;
    }
}

static void fbuffer_append(FBuffer *fb, const char *newstr, unsigned int len)
{
    if (len > 0) {
        fbuffer_inc_capa(fb, len);
        MEMCPY(fb->ptr + fb->len, newstr, char, len);
        fb->len += len;
    }
}

static void fbuffer_append_char(FBuffer *fb, char newchr)
{
    fbuffer_inc_capa(fb, 1);
    *(fb->ptr + fb->len) = newchr;
    fb->len++;
}

static void freverse(char *start, char *end)
{
	char c;

	while (end > start) {
		c = *end, *end-- = *start, *start++ = c;
    }
}

static int fltoa(long number, char *buf)
{
	static char digits[] = "0123456789";
	long sign = number;
	char* tmp = buf;

	if (sign < 0) number = -number;
    do *tmp++ = digits[number % 10]; while (number /= 10);
	if (sign < 0) *tmp++ = '-';
	freverse(buf, tmp - 1);
    return tmp - buf;
}

static void fbuffer_append_long(FBuffer *fb, long number)
{
    char buf[20];
    int len = fltoa(number, buf);
    fbuffer_append(fb, buf, len);
}

static FBuffer *fbuffer_dup(FBuffer *fb)
{
    int len = fb->len;
    FBuffer *result;

    if (len > 0) {
        result = fbuffer_alloc_with_length(len);
        fbuffer_append(result, FBUFFER_PAIR(fb));
    } else {
        result = fbuffer_alloc();
    }
    return result;
}

/* 
 * Document-module: JSON::Ext::Generator
 *
 * This is the JSON generator implemented as a C extension. It can be
 * configured to be used by setting
 *
 *  JSON.generator = JSON::Ext::Generator
 *
 * with the method generator= in JSON.
 *
 */

/*
 * call-seq: to_json(state = nil, depth = 0)
 *
 * Returns a JSON string containing a JSON object, that is generated from
 * this Hash instance.
 * _state_ is a JSON::State object, that can also be used to configure the
 * produced JSON string output further.
 * _depth_ is used to find out nesting depth, to indent accordingly.
 */
static VALUE mHash_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE state, depth;

    rb_scan_args(argc, argv, "02", &state, &depth);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, self, depth);
}

/*
 * call-seq: to_json(state = nil, depth = 0)
 *
 * Returns a JSON string containing a JSON array, that is generated from
 * this Array instance.
 * _state_ is a JSON::State object, that can also be used to configure the
 * produced JSON string output further.
 * _depth_ is used to find out nesting depth, to indent accordingly.
 */
static VALUE mArray_to_json(int argc, VALUE *argv, VALUE self) {
    VALUE state, depth;
    rb_scan_args(argc, argv, "02", &state, &depth);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, self, depth);
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string representation for this Integer number.
 */
static VALUE mInteger_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE state, depth;
    rb_scan_args(argc, argv, "02", &state, &depth);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, self, depth);
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string representation for this Float number.
 */
static VALUE mFloat_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE state, depth;
    rb_scan_args(argc, argv, "02", &state, &depth);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, self, depth);
}

/*
 * call-seq: String.included(modul)
 *
 * Extends _modul_ with the String::Extend module.
 */
static VALUE mString_included_s(VALUE self, VALUE modul) {
    VALUE result = rb_funcall(modul, i_extend, 1, mString_Extend);
    return result;
}

/*
 * call-seq: to_json(*)
 *
 * This string should be encoded with UTF-8 A call to this method
 * returns a JSON string encoded with UTF16 big endian characters as
 * \u????.
 */
static VALUE mString_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE state, depth;
    rb_scan_args(argc, argv, "02", &state, &depth);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, self, depth);
}

/*
 * call-seq: to_json_raw_object()
 *
 * This method creates a raw object hash, that can be nested into
 * other data structures and will be generated as a raw string. This
 * method should be used, if you want to convert raw strings to JSON
 * instead of UTF-8 strings, e. g. binary data.
 */
static VALUE mString_to_json_raw_object(VALUE self)
{
    VALUE ary;
    VALUE result = rb_hash_new();
    rb_hash_aset(result, rb_funcall(mJSON, i_create_id, 0), rb_class_name(rb_obj_class(self)));
    ary = rb_funcall(self, i_unpack, 1, rb_str_new2("C*"));
    rb_hash_aset(result, rb_str_new2("raw"), ary);
    return result;
}

/*
 * call-seq: to_json_raw(*args)
 *
 * This method creates a JSON text from the result of a call to
 * to_json_raw_object of this String.
 */
static VALUE mString_to_json_raw(int argc, VALUE *argv, VALUE self)
{
    VALUE obj = mString_to_json_raw_object(self);
    Check_Type(obj, T_HASH);
    return mHash_to_json(argc, argv, obj);
}

/*
 * call-seq: json_create(o)
 *
 * Raw Strings are JSON Objects (the raw bytes are stored in an array for the
 * key "raw"). The Ruby String can be created by this module method.
 */
static VALUE mString_Extend_json_create(VALUE self, VALUE o)
{
    VALUE ary;
    Check_Type(o, T_HASH);
    ary = rb_hash_aref(o, rb_str_new2("raw"));
    return rb_funcall(ary, i_pack, 1, rb_str_new2("C*"));
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string for true: 'true'.
 */
static VALUE mTrueClass_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE state, depth;
    rb_scan_args(argc, argv, "02", &state, &depth);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, self, depth);
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string for false: 'false'.
 */
static VALUE mFalseClass_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE state, depth;
    rb_scan_args(argc, argv, "02", &state, &depth);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, self, depth);
}

/*
 * call-seq: to_json(*)
 *
 */
static VALUE mNilClass_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE state, depth;
    rb_scan_args(argc, argv, "02", &state, &depth);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, self, depth);
}

/*
 * call-seq: to_json(*)
 *
 * Converts this object to a string (calling #to_s), converts
 * it to a JSON string, and returns the result. This is a fallback, if no
 * special method #to_json was defined for some object.
 */
static VALUE mObject_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE state, depth;
    VALUE string = rb_funcall(self, i_to_s, 0);
    rb_scan_args(argc, argv, "02", &state, &depth);
    Check_Type(string, T_STRING);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, string, depth);
}

static void State_free(JSON_Generator_State *state)
{
    if (state->indent) ruby_xfree(state->indent);
    if (state->space) ruby_xfree(state->space);
    if (state->space_before) ruby_xfree(state->space_before);
    if (state->object_nl) ruby_xfree(state->object_nl);
    if (state->array_nl) ruby_xfree(state->array_nl);
    if (state->array_delim) fbuffer_free(state->array_delim);
    if (state->object_delim) fbuffer_free(state->object_delim);
    if (state->object_delim2) fbuffer_free(state->object_delim2);
    ruby_xfree(state);
}

static JSON_Generator_State *State_allocate()
{
    JSON_Generator_State *state = ALLOC(JSON_Generator_State);
    return state;
}

static VALUE cState_s_allocate(VALUE klass)
{
    JSON_Generator_State *state = State_allocate();
    return Data_Wrap_Struct(klass, NULL, State_free, state);
}

/*
 * call-seq: configure(opts)
 *
 * Configure this State instance with the Hash _opts_, and return
 * itself.
 */
static VALUE cState_configure(VALUE self, VALUE opts)
{
    VALUE tmp;
    GET_STATE(self);
    tmp = rb_convert_type(opts, T_HASH, "Hash", "to_hash");
    if (NIL_P(tmp)) tmp = rb_convert_type(opts, T_HASH, "Hash", "to_h");
    if (NIL_P(tmp)) {
        rb_raise(rb_eArgError, "opts has to be hash like or convertable into a hash");
    }
    opts = tmp;
    tmp = rb_hash_aref(opts, ID2SYM(i_indent));
    if (RTEST(tmp)) {
        int len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->indent = fstrndup(RSTRING_PTR(tmp), len);
        state->indent_len = len;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_space));
    if (RTEST(tmp)) {
        int len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->space = fstrndup(RSTRING_PTR(tmp), len);
        state->space_len = len;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_space_before));
    if (RTEST(tmp)) {
        int len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->space_before = fstrndup(RSTRING_PTR(tmp), len);
        state->space_before_len = len;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_array_nl));
    if (RTEST(tmp)) {
        int len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->array_nl = fstrndup(RSTRING_PTR(tmp), len);
        state->array_nl_len = len;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_object_nl));
    if (RTEST(tmp)) {
        int len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->object_nl = fstrndup(RSTRING_PTR(tmp), len);
        state->object_nl_len = len;
    }
    tmp = ID2SYM(i_max_nesting);
    state->max_nesting = 19;
    if (option_given_p(opts, tmp)) {
        VALUE max_nesting = rb_hash_aref(opts, tmp);
        if (RTEST(max_nesting)) {
            Check_Type(max_nesting, T_FIXNUM);
            state->max_nesting = FIX2LONG(max_nesting);
        } else {
            state->max_nesting = 0;
        }
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_allow_nan));
    state->allow_nan = RTEST(tmp);
    tmp = rb_hash_aref(opts, ID2SYM(i_ascii_only));
    state->ascii_only = RTEST(tmp);
    return self;
}

/*
 * call-seq: to_h
 *
 * Returns the configuration instance variables as a hash, that can be
 * passed to the configure method.
 */
static VALUE cState_to_h(VALUE self)
{
    VALUE result = rb_hash_new();
    GET_STATE(self);
    rb_hash_aset(result, ID2SYM(i_indent), rb_str_new(state->indent, state->indent_len));
    rb_hash_aset(result, ID2SYM(i_space), rb_str_new(state->space, state->space_len));
    rb_hash_aset(result, ID2SYM(i_space_before), rb_str_new(state->space_before, state->space_before_len));
    rb_hash_aset(result, ID2SYM(i_object_nl), rb_str_new(state->object_nl, state->object_nl_len));
    rb_hash_aset(result, ID2SYM(i_array_nl), rb_str_new(state->array_nl, state->array_nl_len));
    rb_hash_aset(result, ID2SYM(i_allow_nan), state->allow_nan ? Qtrue : Qfalse);
    rb_hash_aset(result, ID2SYM(i_ascii_only), state->ascii_only ? Qtrue : Qfalse);
    rb_hash_aset(result, ID2SYM(i_max_nesting), LONG2FIX(state->max_nesting));
    return result;
}

/*
* call-seq: [](name)
*
* Return the value returned by method +name+.
*/
static VALUE cState_aref(VALUE self, VALUE name)
{
    GET_STATE(self);
    if (RTEST(rb_funcall(self, i_respond_to_p, 1, name))) {
        return rb_funcall(self, i_send, 1, name);
    } else {
        return Qnil;
    }
}

static void generate_json(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj, long depth)
{
    VALUE tmp;
    switch (TYPE(obj)) {
        case T_HASH:
            {
                char *object_nl = state->object_nl;
                long object_nl_len = state->object_nl_len;
                char *indent = state->indent;
                long indent_len = state->indent_len;
                long max_nesting = state->max_nesting;
                char *delim = FBUFFER_PTR(state->object_delim);
                long delim_len = FBUFFER_LEN(state->object_delim);
                char *delim2 = FBUFFER_PTR(state->object_delim2);
                long delim2_len = FBUFFER_LEN(state->object_delim2);
                int i, j;
                VALUE key, key_to_s, keys;
                depth++;
                if (max_nesting != 0 && depth > max_nesting) {
                    fbuffer_free(buffer);
                    rb_raise(eNestingError, "nesting of %ld is too deep", depth);
                }
                fbuffer_append_char(buffer, '{');
                keys = rb_funcall(obj, rb_intern("keys"), 0);
                for(i = 0; i < RARRAY_LEN(keys); i++) {
                    if (i > 0) fbuffer_append(buffer, delim, delim_len);
                    if (object_nl) {
                        fbuffer_append(buffer, object_nl, object_nl_len);
                    }
                    if (indent) {
                        for (j = 0; j < depth; j++) {
                            fbuffer_append(buffer, indent, indent_len);
                        }
                    }
                    key = rb_ary_entry(keys, i);
                    key_to_s = rb_funcall(key, i_to_s, 0);
                    Check_Type(key_to_s, T_STRING);
                    generate_json(buffer, Vstate, state, key_to_s, depth);
                    fbuffer_append(buffer, delim2, delim2_len);
                    generate_json(buffer, Vstate, state, rb_hash_aref(obj, key), depth);
                }
                depth--;
                if (object_nl) {
                    fbuffer_append(buffer, object_nl, object_nl_len);
                    if (indent) {
                        for (j = 0; j < depth; j++) {
                            fbuffer_append(buffer, indent, indent_len);
                        }
                    }
                }
                fbuffer_append_char(buffer, '}');
            }
            break;
        case T_ARRAY:
            {
                char *array_nl = state->array_nl;
                long array_nl_len = state->array_nl_len;
                char *indent = state->indent;
                long indent_len = state->indent_len;
                long max_nesting = state->max_nesting;
                char *delim = FBUFFER_PTR(state->array_delim);
                long delim_len = FBUFFER_LEN(state->array_delim);
                int i, j;
                depth++;
                if (max_nesting != 0 && depth > max_nesting) {
                    fbuffer_free(buffer);
                    rb_raise(eNestingError, "nesting of %ld is too deep", depth);
                }
                fbuffer_append_char(buffer, '[');
                if (array_nl) fbuffer_append(buffer, array_nl, array_nl_len);
                for(i = 0; i < RARRAY_LEN(obj); i++) {
                    if (i > 0) fbuffer_append(buffer, delim, delim_len);
                    if (indent) {
                        for (j = 0; j < depth; j++) {
                            fbuffer_append(buffer, indent, indent_len);
                        }
                    }
                    generate_json(buffer, Vstate, state, rb_ary_entry(obj, i), depth);
                }
                depth--;
                if (array_nl) {
                    fbuffer_append(buffer, array_nl, array_nl_len);
                    if (indent) {
                        for (j = 0; j < depth; j++) {
                            fbuffer_append(buffer, indent, indent_len);
                        }
                    }
                }
                fbuffer_append_char(buffer, ']');
            }
            break;
        case T_STRING:
            fbuffer_append_char(buffer, '"');
#ifdef HAVE_RUBY_ENCODING_H
            obj = rb_funcall(obj, i_encode, 1, CEncoding_UTF_8);
#endif
            if (state->ascii_only) {
                convert_UTF8_to_JSON_ASCII(buffer, obj);
            } else {
                convert_UTF8_to_JSON(buffer, obj);
            }
            fbuffer_append_char(buffer, '"');
            break;
        case T_NIL:
            fbuffer_append(buffer, "null", 4);
            break;
        case T_FALSE:
            fbuffer_append(buffer, "false", 5);
            break;
        case T_TRUE:
            fbuffer_append(buffer, "true", 4);
            break;
        case T_FIXNUM:
            fbuffer_append_long(buffer, FIX2LONG(obj));
            break;
        case T_BIGNUM:
            tmp = rb_funcall(obj, i_to_s, 0);
            fbuffer_append(buffer, RSTRING_PAIR(tmp));
            break;
        case T_FLOAT:
            {
                double value = RFLOAT_VALUE(obj);
                char allow_nan = state->allow_nan;
                tmp = rb_funcall(obj, i_to_s, 0);
                if (!allow_nan) {
                    if (isinf(value)) {
                        fbuffer_free(buffer);
                        rb_raise(eGeneratorError, "%u: %s not allowed in JSON", __LINE__, StringValueCStr(tmp));
                    } else if (isnan(value)) {
                        fbuffer_free(buffer);
                        rb_raise(eGeneratorError, "%u: %s not allowed in JSON", __LINE__, StringValueCStr(tmp));
                    }
                }
                fbuffer_append(buffer, RSTRING_PAIR(tmp));
            }
            break;
        default:
            if (rb_respond_to(obj, i_to_json)) {
                tmp = rb_funcall(obj, i_to_json, 2, Vstate, INT2FIX(depth + 1));
                Check_Type(tmp, T_STRING);
                fbuffer_append(buffer, RSTRING_PAIR(tmp));
            } else {
                tmp = rb_funcall(obj, i_to_s, 0);
                Check_Type(tmp, T_STRING);
                generate_json(buffer, Vstate, state, tmp, depth + 1);
            }
            break;
    }
}

/*
 * call-seq: partial_generate(obj)
 *
 * Generates a part of a JSON document from object +obj+ and returns the
 * result.
 */
static VALUE cState_partial_generate(VALUE self, VALUE obj, VALUE depth)
{
    VALUE result;
    FBuffer *buffer = fbuffer_alloc();
    GET_STATE(self);

    if (state->object_delim) {
        fbuffer_clear(state->object_delim);
    } else {
        state->object_delim = fbuffer_alloc_with_length(16);
    }
    fbuffer_append_char(state->object_delim, ',');
    if (state->object_delim2) {
        fbuffer_clear(state->object_delim2);
    } else {
        state->object_delim2 = fbuffer_alloc_with_length(16);
    }
    fbuffer_append_char(state->object_delim2, ':');
    if (state->space) fbuffer_append(state->object_delim2, state->space, state->space_len);

    if (state->array_delim) {
        fbuffer_clear(state->array_delim);
    } else {
        state->array_delim = fbuffer_alloc_with_length(16);
    }
    fbuffer_append_char(state->array_delim, ',');
    if (state->array_nl) fbuffer_append(state->array_delim, state->array_nl, state->array_nl_len);

    generate_json(buffer, self, state, obj, NIL_P(depth) ? 0 : FIX2INT(depth));
    result = rb_str_new(FBUFFER_PAIR(buffer));
    fbuffer_free(buffer);
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: generate(obj)
 *
 * Generates a valid JSON document from object +obj+ and returns the
 * result. If no valid JSON document can be created this method raises a
 * GeneratorError exception.
 */
static VALUE cState_generate(VALUE self, VALUE obj)
{
    VALUE result = cState_partial_generate(self, obj, Qnil);
    VALUE re, args[2];
    args[0] = rb_str_new2("\\A\\s*(?:\\[.*\\]|\\{.*\\})\\s*\\Z");
    args[1] = CRegexp_MULTILINE;
    re = rb_class_new_instance(2, args, rb_cRegexp);
    if (NIL_P(rb_funcall(re, i_match, 1, result))) {
        rb_raise(eGeneratorError, "only generation of JSON objects or arrays allowed");
    }
    return result;
}

/*
 * call-seq: new(opts = {})
 *
 * Instantiates a new State object, configured by _opts_.
 *
 * _opts_ can have the following keys:
 *
 * * *indent*: a string used to indent levels (default: ''),
 * * *space*: a string that is put after, a : or , delimiter (default: ''),
 * * *space_before*: a string that is put before a : pair delimiter (default: ''),
 * * *object_nl*: a string that is put at the end of a JSON object (default: ''), 
 * * *array_nl*: a string that is put at the end of a JSON array (default: ''),
 * * *allow_nan*: true if NaN, Infinity, and -Infinity should be
 *   generated, otherwise an exception is thrown, if these values are
 *   encountered. This options defaults to false.
 */
static VALUE cState_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;
    GET_STATE(self);
    MEMZERO(state, JSON_Generator_State, 1);
    state->max_nesting = 19;
    rb_scan_args(argc, argv, "01", &opts);
    if (!NIL_P(opts)) cState_configure(self, opts);
    return self;
}

/*
 * call-seq: initialize_copy(orig)
 *
 * Initializes this object from orig if it to be duplicated/cloned and returns
 * it.
*/
static VALUE cState_init_copy(VALUE obj, VALUE orig)
{
    JSON_Generator_State *objState, *origState;

    Data_Get_Struct(obj, JSON_Generator_State, objState);
    Data_Get_Struct(orig, JSON_Generator_State, origState);
    if (!objState) rb_raise(rb_eArgError, "unallocated JSON::State");

    MEMCPY(objState, origState, JSON_Generator_State, 1);
    objState->indent = fstrndup(origState->indent, origState->indent_len);
    objState->space = fstrndup(origState->space, origState->space_len);
    objState->space_before = fstrndup(origState->space_before, origState->space_before_len);
    objState->object_nl = fstrndup(origState->object_nl, origState->object_nl_len);
    objState->array_nl = fstrndup(origState->array_nl, origState->array_nl_len);
    if (origState->array_delim) objState->array_delim = fbuffer_dup(origState->array_delim);
    if (origState->object_delim) objState->object_delim = fbuffer_dup(origState->object_delim);
    if (origState->object_delim2) objState->object_delim2 = fbuffer_dup(origState->object_delim2);
    return obj;
}

/*
 * call-seq: from_state(opts)
 *
 * Creates a State object from _opts_, which ought to be Hash to create a
 * new State instance configured by _opts_, something else to create an
 * unconfigured instance. If _opts_ is a State object, it is just returned.
 */
static VALUE cState_from_state_s(VALUE self, VALUE opts)
{
    if (rb_obj_is_kind_of(opts, self)) {
        return opts;
    } else if (rb_obj_is_kind_of(opts, rb_cHash)) {
        return rb_funcall(self, i_new, 1, opts);
    } else {
        if (NIL_P(CJSON_SAFE_STATE_PROTOTYPE)) {
            CJSON_SAFE_STATE_PROTOTYPE = rb_const_get(mJSON, rb_intern("SAFE_STATE_PROTOTYPE"));
        }
        return CJSON_SAFE_STATE_PROTOTYPE;
    }
}

/*
 * call-seq: indent()
 *
 * This string is used to indent levels in the JSON text.
 */
static VALUE cState_indent(VALUE self)
{
    GET_STATE(self);
    return state->indent ? rb_str_new2(state->indent) : rb_str_new2("");
}

/*
 * call-seq: indent=(indent)
 *
 * This string is used to indent levels in the JSON text.
 */
static VALUE cState_indent_set(VALUE self, VALUE indent)
{
    GET_STATE(self);
    Check_Type(indent, T_STRING);
    if (RSTRING_LEN(indent) == 0) {
        if (state->indent) {
            ruby_xfree(state->indent);
            state->indent = NULL;
        }
    } else {
        if (state->indent) ruby_xfree(state->indent);
        state->indent = strdup(RSTRING_PTR(indent));
    }
    return Qnil;
}

/*
 * call-seq: space()
 *
 * This string is used to insert a space between the tokens in a JSON
 * string.
 */
static VALUE cState_space(VALUE self)
{
    GET_STATE(self);
    return state->space ? rb_str_new2(state->space) : rb_str_new2("");
}

/*
 * call-seq: space=(space)
 *
 * This string is used to insert a space between the tokens in a JSON
 * string.
 */
static VALUE cState_space_set(VALUE self, VALUE space)
{
    GET_STATE(self);
    Check_Type(space, T_STRING);
    if (RSTRING_LEN(space) == 0) {
        if (state->space) {
            ruby_xfree(state->space);
            state->space = NULL;
        }
    } else {
        if (state->space) ruby_xfree(state->space);
        state->space = strdup(RSTRING_PTR(space));
    }
    return Qnil;
}

/*
 * call-seq: space_before()
 *
 * This string is used to insert a space before the ':' in JSON objects.
 */
static VALUE cState_space_before(VALUE self)
{
    GET_STATE(self);
    return state->space_before ? rb_str_new2(state->space_before) : rb_str_new2("");
}

/*
 * call-seq: space_before=(space_before)
 *
 * This string is used to insert a space before the ':' in JSON objects.
 */
static VALUE cState_space_before_set(VALUE self, VALUE space_before)
{
    GET_STATE(self);
    Check_Type(space_before, T_STRING);
    if (RSTRING_LEN(space_before) == 0) {
        if (state->space_before) {
            ruby_xfree(state->space_before);
            state->space_before = NULL;
        }
    } else {
        if (state->space_before) ruby_xfree(state->space_before);
        state->space_before = strdup(RSTRING_PTR(space_before));
    }
    return Qnil;
}

/*
 * call-seq: object_nl()
 *
 * This string is put at the end of a line that holds a JSON object (or
 * Hash).
 */
static VALUE cState_object_nl(VALUE self)
{
    GET_STATE(self);
    return state->object_nl ? rb_str_new2(state->object_nl) : rb_str_new2("");
}

/*
 * call-seq: object_nl=(object_nl)
 *
 * This string is put at the end of a line that holds a JSON object (or
 * Hash).
 */
static VALUE cState_object_nl_set(VALUE self, VALUE object_nl)
{
    GET_STATE(self);
    Check_Type(object_nl, T_STRING);
    if (RSTRING_LEN(object_nl) == 0) {
        if (state->object_nl) {
            ruby_xfree(state->object_nl);
            state->object_nl = NULL;
        }
    } else {
        if (state->object_nl) ruby_xfree(state->object_nl);
        state->object_nl = strdup(RSTRING_PTR(object_nl));
    }
    return Qnil;
}

/*
 * call-seq: array_nl()
 *
 * This string is put at the end of a line that holds a JSON array.
 */
static VALUE cState_array_nl(VALUE self)
{
    GET_STATE(self);
    return state->array_nl ? rb_str_new2(state->array_nl) : rb_str_new2("");
}

/*
 * call-seq: array_nl=(array_nl)
 *
 * This string is put at the end of a line that holds a JSON array.
 */
static VALUE cState_array_nl_set(VALUE self, VALUE array_nl)
{
    GET_STATE(self);
    Check_Type(array_nl, T_STRING);
    if (RSTRING_LEN(array_nl) == 0) {
        if (state->array_nl) {
            ruby_xfree(state->array_nl);
            state->array_nl = NULL;
        }
    } else {
        if (state->array_nl) ruby_xfree(state->array_nl);
        state->array_nl = strdup(RSTRING_PTR(array_nl));
    }
    return Qnil;
}


/*
* call-seq: check_circular?
*
* Returns true, if circular data structures should be checked,
* otherwise returns false.
*/
static VALUE cState_check_circular_p(VALUE self)
{
    GET_STATE(self);
    return state->max_nesting ? Qtrue : Qfalse;
}

/*
 * call-seq: max_nesting
 *
 * This integer returns the maximum level of data structure nesting in
 * the generated JSON, max_nesting = 0 if no maximum is checked.
 */
static VALUE cState_max_nesting(VALUE self)
{
    GET_STATE(self);
    return LONG2FIX(state->max_nesting);
}

/*
 * call-seq: max_nesting=(depth)
 *
 * This sets the maximum level of data structure nesting in the generated JSON
 * to the integer depth, max_nesting = 0 if no maximum should be checked.
 */
static VALUE cState_max_nesting_set(VALUE self, VALUE depth)
{
    GET_STATE(self);
    Check_Type(depth, T_FIXNUM);
    return state->max_nesting = FIX2LONG(depth);
}

/*
 * call-seq: allow_nan?
 *
 * Returns true, if NaN, Infinity, and -Infinity should be generated, otherwise
 * returns false.
 */
static VALUE cState_allow_nan_p(VALUE self)
{
    GET_STATE(self);
    return state->allow_nan ? Qtrue : Qfalse;
}

/*
 * call-seq: ascii_only?
 *
 * Returns true, if NaN, Infinity, and -Infinity should be generated, otherwise
 * returns false.
 */
static VALUE cState_ascii_only_p(VALUE self)
{
    GET_STATE(self);
    return state->ascii_only ? Qtrue : Qfalse;
}

/*
 *
 */
void Init_generator()
{
    rb_require("json/common");

    mJSON = rb_define_module("JSON");
    mExt = rb_define_module_under(mJSON, "Ext");
    mGenerator = rb_define_module_under(mExt, "Generator");

    eGeneratorError = rb_path2class("JSON::GeneratorError");
    eNestingError = rb_path2class("JSON::NestingError");

    cState = rb_define_class_under(mGenerator, "State", rb_cObject);
    rb_define_alloc_func(cState, cState_s_allocate);
    rb_define_singleton_method(cState, "from_state", cState_from_state_s, 1);
    rb_define_method(cState, "initialize", cState_initialize, -1);
    rb_define_method(cState, "initialize_copy", cState_init_copy, 1);
    rb_define_method(cState, "indent", cState_indent, 0);
    rb_define_method(cState, "indent=", cState_indent_set, 1);
    rb_define_method(cState, "space", cState_space, 0);
    rb_define_method(cState, "space=", cState_space_set, 1);
    rb_define_method(cState, "space_before", cState_space_before, 0);
    rb_define_method(cState, "space_before=", cState_space_before_set, 1);
    rb_define_method(cState, "object_nl", cState_object_nl, 0);
    rb_define_method(cState, "object_nl=", cState_object_nl_set, 1);
    rb_define_method(cState, "array_nl", cState_array_nl, 0);
    rb_define_method(cState, "array_nl=", cState_array_nl_set, 1);
    rb_define_method(cState, "max_nesting", cState_max_nesting, 0);
    rb_define_method(cState, "max_nesting=", cState_max_nesting_set, 1);
    rb_define_method(cState, "check_circular?", cState_check_circular_p, 0);
    rb_define_method(cState, "allow_nan?", cState_allow_nan_p, 0);
    rb_define_method(cState, "ascii_only?", cState_ascii_only_p, 0);
    rb_define_method(cState, "configure", cState_configure, 1);
    rb_define_method(cState, "to_h", cState_to_h, 0);
    rb_define_method(cState, "[]", cState_aref, 1);
    rb_define_method(cState, "generate", cState_generate, 1);
    rb_define_method(cState, "partial_generate", cState_partial_generate, 1);

    mGeneratorMethods = rb_define_module_under(mGenerator, "GeneratorMethods");
    mObject = rb_define_module_under(mGeneratorMethods, "Object");
    rb_define_method(mObject, "to_json", mObject_to_json, -1);
    mHash = rb_define_module_under(mGeneratorMethods, "Hash");
    rb_define_method(mHash, "to_json", mHash_to_json, -1);
    mArray = rb_define_module_under(mGeneratorMethods, "Array");
    rb_define_method(mArray, "to_json", mArray_to_json, -1);
    mInteger = rb_define_module_under(mGeneratorMethods, "Integer");
    rb_define_method(mInteger, "to_json", mInteger_to_json, -1);
    mFloat = rb_define_module_under(mGeneratorMethods, "Float");
    rb_define_method(mFloat, "to_json", mFloat_to_json, -1);
    mString = rb_define_module_under(mGeneratorMethods, "String");
    rb_define_singleton_method(mString, "included", mString_included_s, 1);
    rb_define_method(mString, "to_json", mString_to_json, -1);
    rb_define_method(mString, "to_json_raw", mString_to_json_raw, -1);
    rb_define_method(mString, "to_json_raw_object", mString_to_json_raw_object, 0);
    mString_Extend = rb_define_module_under(mString, "Extend");
    rb_define_method(mString_Extend, "json_create", mString_Extend_json_create, 1);
    mTrueClass = rb_define_module_under(mGeneratorMethods, "TrueClass");
    rb_define_method(mTrueClass, "to_json", mTrueClass_to_json, -1);
    mFalseClass = rb_define_module_under(mGeneratorMethods, "FalseClass");
    rb_define_method(mFalseClass, "to_json", mFalseClass_to_json, -1);
    mNilClass = rb_define_module_under(mGeneratorMethods, "NilClass");
    rb_define_method(mNilClass, "to_json", mNilClass_to_json, -1);

    CRegexp_MULTILINE = rb_const_get(rb_cRegexp, rb_intern("MULTILINE"));
    i_to_s = rb_intern("to_s");
    i_to_json = rb_intern("to_json");
    i_new = rb_intern("new");
    i_indent = rb_intern("indent");
    i_space = rb_intern("space");
    i_space_before = rb_intern("space_before");
    i_object_nl = rb_intern("object_nl");
    i_array_nl = rb_intern("array_nl");
    i_max_nesting = rb_intern("max_nesting");
    i_allow_nan = rb_intern("allow_nan");
    i_ascii_only = rb_intern("ascii_only");
    i_pack = rb_intern("pack");
    i_unpack = rb_intern("unpack");
    i_create_id = rb_intern("create_id");
    i_extend = rb_intern("extend");
    i_key_p = rb_intern("key?");
    i_aref = rb_intern("[]");
    i_send = rb_intern("__send__");
    i_respond_to_p = rb_intern("respond_to?");
    i_match = rb_intern("match");
#ifdef HAVE_RUBY_ENCODING_H
    CEncoding_UTF_8 = rb_funcall(rb_path2class("Encoding"), rb_intern("find"), 1, rb_str_new2("utf-8"));
    i_encoding = rb_intern("encoding");
    i_encode = rb_intern("encode");
#endif
    CJSON_SAFE_STATE_PROTOTYPE = Qnil;
}
