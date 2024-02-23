#include "../fbuffer/fbuffer.h"
#include "generator.h"

static VALUE mJSON, mExt, mGenerator, cState, mGeneratorMethods, mObject,
             mHash, mArray,
#ifdef RUBY_INTEGER_UNIFICATION
             mInteger,
#else
             mFixnum, mBignum,
#endif
             mFloat, mString, mString_Extend,
             mTrueClass, mFalseClass, mNilClass, eGeneratorError,
             eNestingError;

static ID i_to_s, i_to_json, i_new, i_indent, i_space, i_space_before,
          i_object_nl, i_array_nl, i_max_nesting, i_allow_nan, i_ascii_only,
          i_pack, i_unpack, i_create_id, i_extend, i_key_p,
          i_aref, i_send, i_respond_to_p, i_match, i_keys, i_depth,
          i_buffer_initial_length, i_dup, i_script_safe, i_escape_slash, i_strict;

/* Converts in_string to a JSON string (without the wrapping '"'
 * characters) in FBuffer out_buffer.
 *
 * Character are JSON-escaped according to:
 *
 * - Always: ASCII control characters (0x00-0x1F), dquote, and
 *   backslash.
 *
 * - If out_ascii_only: non-ASCII characters (>0x7F)
 *
 * - If out_script_safe: forwardslash, line separator (U+2028), and
 *   paragraph separator (U+2029)
 *
 * Everything else (should be UTF-8) is just passed through and
 * appended to the result.
 */
static void convert_UTF8_to_JSON(FBuffer *out_buffer, VALUE in_string, bool out_ascii_only, bool out_script_safe)
{
    const char *hexdig = "0123456789abcdef";
    char scratch[12] = { '\\', 'u', 0, 0, 0, 0, '\\', 'u' };

    const char *in_utf8_str = RSTRING_PTR(in_string);
    unsigned long in_utf8_len = RSTRING_LEN(in_string);
    bool in_is_ascii_only = rb_enc_str_asciionly_p(in_string);

    unsigned long beg = 0, pos;

    for (pos =  0; pos < in_utf8_len;) {
        uint32_t ch;
        unsigned long ch_len;
        bool should_escape;

        /* UTF-8 decoding */
        if (in_is_ascii_only) {
            ch = in_utf8_str[pos];
            ch_len = 1;
        } else {
            short i;
            if      ((in_utf8_str[pos] & 0x80) == 0x00) { ch_len = 1; ch = in_utf8_str[pos];        } /* leading 1 bit is   0b0     */
            else if ((in_utf8_str[pos] & 0xE0) == 0xC0) { ch_len = 2; ch = in_utf8_str[pos] & 0x1F; } /* leading 3 bits are 0b110   */
            else if ((in_utf8_str[pos] & 0xF0) == 0xE0) { ch_len = 3; ch = in_utf8_str[pos] & 0x0F; } /* leading 4 bits are 0b1110  */
            else if ((in_utf8_str[pos] & 0xF8) == 0xF0) { ch_len = 4; ch = in_utf8_str[pos] & 0x07; } /* leading 5 bits are 0b11110 */
            else
                rb_raise(rb_path2class("JSON::GeneratorError"),
                         "source sequence is illegal/malformed utf-8");
            if ((pos+ch_len) > in_utf8_len)
                rb_raise(rb_path2class("JSON::GeneratorError"),
                         "partial character in source, but hit end");
            for (i = 1; i < ch_len; i++) {
                if ((in_utf8_str[pos+i] & 0xC0) != 0x80) /* leading 2 bits should be 0b10 */
                    rb_raise(rb_path2class("JSON::GeneratorError"),
                             "source sequence is illegal/malformed utf-8");
                ch = (ch<<6) | (in_utf8_str[pos+i] & 0x3F);
            }
            if (ch > 0x10FFFF)
                rb_raise(rb_path2class("JSON::GeneratorError"),
                         "source sequence is illegal/malformed utf-8");
        }

        /* JSON policy */
        should_escape =
            (ch < 0x20) ||
            (ch == '"') ||
            (ch == '\\') ||
            (out_ascii_only && (ch > 0x7F)) ||
            (out_script_safe && (ch == '/')) ||
            (out_script_safe && (ch == 0x2028)) ||
            (out_script_safe && (ch == 0x2029));

        /* JSON encoding */
        if (should_escape) {
            if (pos > beg)
                fbuffer_append(out_buffer, &in_utf8_str[beg], pos - beg);
            beg = pos + ch_len;
            switch (ch) {
                case '"':  fbuffer_append(out_buffer, "\\\"", 2); break;
                case '\\': fbuffer_append(out_buffer, "\\\\", 2); break;
                case '/':  fbuffer_append(out_buffer, "\\/", 2); break;
                case '\b': fbuffer_append(out_buffer, "\\b", 2); break;
                case '\f': fbuffer_append(out_buffer, "\\f", 2); break;
                case '\n': fbuffer_append(out_buffer, "\\n", 2); break;
                case '\r': fbuffer_append(out_buffer, "\\r", 2); break;
                case '\t': fbuffer_append(out_buffer, "\\t", 2); break;
                default:
                    if (ch <= 0xFFFF) {
                        scratch[2] = hexdig[ch >> 12];
                        scratch[3] = hexdig[(ch >> 8) & 0xf];
                        scratch[4] = hexdig[(ch >> 4) & 0xf];
                        scratch[5] = hexdig[ch & 0xf];
                        fbuffer_append(out_buffer, scratch, 6);
                    } else {
			uint16_t hi, lo;
                        ch -= 0x10000;
                        hi = 0xD800 + (uint16_t)(ch >> 10);
                        lo = 0xDC00 + (uint16_t)(ch & 0x3FF);

                        scratch[2] = hexdig[hi >> 12];
                        scratch[3] = hexdig[(hi >> 8) & 0xf];
                        scratch[4] = hexdig[(hi >> 4) & 0xf];
                        scratch[5] = hexdig[hi & 0xf];

                        scratch[8] = hexdig[lo >> 12];
                        scratch[9] = hexdig[(lo >> 8) & 0xf];
                        scratch[10] = hexdig[(lo >> 4) & 0xf];
                        scratch[11] = hexdig[lo & 0xf];

                        fbuffer_append(out_buffer, scratch, 12);
                    }
            }
        }

        pos += ch_len;
    }
    if (beg < in_utf8_len)
        fbuffer_append(out_buffer, &in_utf8_str[beg], in_utf8_len - beg);
    RB_GC_GUARD(in_string);
}

static char *fstrndup(const char *ptr, unsigned long len) {
  char *result;
  if (len <= 0) return NULL;
  result = ALLOC_N(char, len);
  memcpy(result, ptr, len);
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

/* Explanation of the following: that's the only way to not pollute
 * standard library's docs with GeneratorMethods::<ClassName> which
 * are uninformative and take a large place in a list of classes
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::Array
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::Bignum
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::FalseClass
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::Fixnum
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::Float
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::Hash
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::Integer
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::NilClass
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::Object
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::String
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::String::Extend
 * :nodoc:
 */

/*
 * Document-module: JSON::Ext::Generator::GeneratorMethods::TrueClass
 * :nodoc:
 */

/*
 * call-seq: to_json(state = nil)
 *
 * Returns a JSON string containing a JSON object, that is generated from
 * this Hash instance.
 * _state_ is a JSON::State object, that can also be used to configure the
 * produced JSON string output further.
 */
static VALUE mHash_to_json(int argc, VALUE *argv, VALUE self)
{
    GENERATE_JSON(object);
}

/*
 * call-seq: to_json(state = nil)
 *
 * Returns a JSON string containing a JSON array, that is generated from
 * this Array instance.
 * _state_ is a JSON::State object, that can also be used to configure the
 * produced JSON string output further.
 */
static VALUE mArray_to_json(int argc, VALUE *argv, VALUE self) {
    GENERATE_JSON(array);
}

#ifdef RUBY_INTEGER_UNIFICATION
/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string representation for this Integer number.
 */
static VALUE mInteger_to_json(int argc, VALUE *argv, VALUE self)
{
    GENERATE_JSON(integer);
}

#else
/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string representation for this Integer number.
 */
static VALUE mFixnum_to_json(int argc, VALUE *argv, VALUE self)
{
    GENERATE_JSON(fixnum);
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string representation for this Integer number.
 */
static VALUE mBignum_to_json(int argc, VALUE *argv, VALUE self)
{
    GENERATE_JSON(bignum);
}
#endif

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string representation for this Float number.
 */
static VALUE mFloat_to_json(int argc, VALUE *argv, VALUE self)
{
    GENERATE_JSON(float);
}

/*
 * call-seq: String.included(modul)
 *
 * Extends _modul_ with the String::Extend module.
 */
static VALUE mString_included_s(VALUE self, VALUE modul) {
    VALUE result = rb_funcall(modul, i_extend, 1, mString_Extend);
    rb_call_super(1, &modul);
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
    GENERATE_JSON(string);
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
    GENERATE_JSON(true);
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string for false: 'false'.
 */
static VALUE mFalseClass_to_json(int argc, VALUE *argv, VALUE self)
{
    GENERATE_JSON(false);
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string for nil: 'null'.
 */
static VALUE mNilClass_to_json(int argc, VALUE *argv, VALUE self)
{
    GENERATE_JSON(null);
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
    VALUE state;
    VALUE string = rb_funcall(self, i_to_s, 0);
    rb_scan_args(argc, argv, "01", &state);
    Check_Type(string, T_STRING);
    state = cState_from_state_s(cState, state);
    return cState_partial_generate(state, string);
}

static void State_free(void *ptr)
{
    JSON_Generator_State *state = ptr;
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

static size_t State_memsize(const void *ptr)
{
    const JSON_Generator_State *state = ptr;
    size_t size = sizeof(*state);
    if (state->indent) size += state->indent_len + 1;
    if (state->space) size += state->space_len + 1;
    if (state->space_before) size += state->space_before_len + 1;
    if (state->object_nl) size += state->object_nl_len + 1;
    if (state->array_nl) size += state->array_nl_len + 1;
    if (state->array_delim) size += FBUFFER_CAPA(state->array_delim);
    if (state->object_delim) size += FBUFFER_CAPA(state->object_delim);
    if (state->object_delim2) size += FBUFFER_CAPA(state->object_delim2);
    return size;
}

#ifndef HAVE_RB_EXT_RACTOR_SAFE
#   undef RUBY_TYPED_FROZEN_SHAREABLE
#   define RUBY_TYPED_FROZEN_SHAREABLE 0
#endif

static const rb_data_type_t JSON_Generator_State_type = {
    "JSON/Generator/State",
    {NULL, State_free, State_memsize,},
    0, 0,
    RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_FROZEN_SHAREABLE,
};

static VALUE cState_s_allocate(VALUE klass)
{
    JSON_Generator_State *state;
    return TypedData_Make_Struct(klass, JSON_Generator_State,
				 &JSON_Generator_State_type, state);
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
    tmp = rb_check_convert_type(opts, T_HASH, "Hash", "to_hash");
    if (NIL_P(tmp)) tmp = rb_convert_type(opts, T_HASH, "Hash", "to_h");
    opts = tmp;
    tmp = rb_hash_aref(opts, ID2SYM(i_indent));
    if (RTEST(tmp)) {
        unsigned long len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->indent = fstrndup(RSTRING_PTR(tmp), len + 1);
        state->indent_len = len;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_space));
    if (RTEST(tmp)) {
        unsigned long len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->space = fstrndup(RSTRING_PTR(tmp), len + 1);
        state->space_len = len;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_space_before));
    if (RTEST(tmp)) {
        unsigned long len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->space_before = fstrndup(RSTRING_PTR(tmp), len + 1);
        state->space_before_len = len;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_array_nl));
    if (RTEST(tmp)) {
        unsigned long len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->array_nl = fstrndup(RSTRING_PTR(tmp), len + 1);
        state->array_nl_len = len;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_object_nl));
    if (RTEST(tmp)) {
        unsigned long len;
        Check_Type(tmp, T_STRING);
        len = RSTRING_LEN(tmp);
        state->object_nl = fstrndup(RSTRING_PTR(tmp), len + 1);
        state->object_nl_len = len;
    }
    tmp = ID2SYM(i_max_nesting);
    state->max_nesting = 100;
    if (option_given_p(opts, tmp)) {
        VALUE max_nesting = rb_hash_aref(opts, tmp);
        if (RTEST(max_nesting)) {
            Check_Type(max_nesting, T_FIXNUM);
            state->max_nesting = FIX2LONG(max_nesting);
        } else {
            state->max_nesting = 0;
        }
    }
    tmp = ID2SYM(i_depth);
    state->depth = 0;
    if (option_given_p(opts, tmp)) {
        VALUE depth = rb_hash_aref(opts, tmp);
        if (RTEST(depth)) {
            Check_Type(depth, T_FIXNUM);
            state->depth = FIX2LONG(depth);
        } else {
            state->depth = 0;
        }
    }
    tmp = ID2SYM(i_buffer_initial_length);
    if (option_given_p(opts, tmp)) {
        VALUE buffer_initial_length = rb_hash_aref(opts, tmp);
        if (RTEST(buffer_initial_length)) {
            long initial_length;
            Check_Type(buffer_initial_length, T_FIXNUM);
            initial_length = FIX2LONG(buffer_initial_length);
            if (initial_length > 0) state->buffer_initial_length = initial_length;
        }
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_allow_nan));
    state->allow_nan = RTEST(tmp);
    tmp = rb_hash_aref(opts, ID2SYM(i_ascii_only));
    state->ascii_only = RTEST(tmp);
    tmp = rb_hash_aref(opts, ID2SYM(i_script_safe));
    state->script_safe = RTEST(tmp);
    if (!state->script_safe) {
        tmp = rb_hash_aref(opts, ID2SYM(i_escape_slash));
        state->script_safe = RTEST(tmp);
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_strict));
    state->strict = RTEST(tmp);
    return self;
}

static void set_state_ivars(VALUE hash, VALUE state)
{
    VALUE ivars = rb_obj_instance_variables(state);
    int i = 0;
    for (i = 0; i < RARRAY_LEN(ivars); i++) {
        VALUE key = rb_funcall(rb_ary_entry(ivars, i), i_to_s, 0);
        long key_len = RSTRING_LEN(key);
        VALUE value = rb_iv_get(state, StringValueCStr(key));
        rb_hash_aset(hash, rb_str_intern(rb_str_substr(key, 1, key_len - 1)), value);
    }
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
    set_state_ivars(result, self);
    rb_hash_aset(result, ID2SYM(i_indent), rb_str_new(state->indent, state->indent_len));
    rb_hash_aset(result, ID2SYM(i_space), rb_str_new(state->space, state->space_len));
    rb_hash_aset(result, ID2SYM(i_space_before), rb_str_new(state->space_before, state->space_before_len));
    rb_hash_aset(result, ID2SYM(i_object_nl), rb_str_new(state->object_nl, state->object_nl_len));
    rb_hash_aset(result, ID2SYM(i_array_nl), rb_str_new(state->array_nl, state->array_nl_len));
    rb_hash_aset(result, ID2SYM(i_allow_nan), state->allow_nan ? Qtrue : Qfalse);
    rb_hash_aset(result, ID2SYM(i_ascii_only), state->ascii_only ? Qtrue : Qfalse);
    rb_hash_aset(result, ID2SYM(i_max_nesting), LONG2FIX(state->max_nesting));
    rb_hash_aset(result, ID2SYM(i_script_safe), state->script_safe ? Qtrue : Qfalse);
    rb_hash_aset(result, ID2SYM(i_strict), state->strict ? Qtrue : Qfalse);
    rb_hash_aset(result, ID2SYM(i_depth), LONG2FIX(state->depth));
    rb_hash_aset(result, ID2SYM(i_buffer_initial_length), LONG2FIX(state->buffer_initial_length));
    return result;
}

/*
* call-seq: [](name)
*
* Returns the value returned by method +name+.
*/
static VALUE cState_aref(VALUE self, VALUE name)
{
    name = rb_funcall(name, i_to_s, 0);
    if (RTEST(rb_funcall(self, i_respond_to_p, 1, name))) {
        return rb_funcall(self, i_send, 1, name);
    } else {
        return rb_attr_get(self, rb_intern_str(rb_str_concat(rb_str_new2("@"), name)));
    }
}

/*
* call-seq: []=(name, value)
*
* Sets the attribute name to value.
*/
static VALUE cState_aset(VALUE self, VALUE name, VALUE value)
{
    VALUE name_writer;

    name = rb_funcall(name, i_to_s, 0);
    name_writer = rb_str_cat2(rb_str_dup(name), "=");
    if (RTEST(rb_funcall(self, i_respond_to_p, 1, name_writer))) {
        return rb_funcall(self, i_send, 2, name_writer, value);
    } else {
        rb_ivar_set(self, rb_intern_str(rb_str_concat(rb_str_new2("@"), name)), value);
    }
    return Qnil;
}

struct hash_foreach_arg {
    FBuffer *buffer;
    JSON_Generator_State *state;
    VALUE Vstate;
    int iter;
};

static int
json_object_i(VALUE key, VALUE val, VALUE _arg)
{
    struct hash_foreach_arg *arg = (struct hash_foreach_arg *)_arg;
    FBuffer *buffer = arg->buffer;
    JSON_Generator_State *state = arg->state;
    VALUE Vstate = arg->Vstate;

    char *object_nl = state->object_nl;
    long object_nl_len = state->object_nl_len;
    char *indent = state->indent;
    long indent_len = state->indent_len;
    char *delim = FBUFFER_PTR(state->object_delim);
    long delim_len = FBUFFER_LEN(state->object_delim);
    char *delim2 = FBUFFER_PTR(state->object_delim2);
    long delim2_len = FBUFFER_LEN(state->object_delim2);
    long depth = state->depth;
    int j;

    if (arg->iter > 0) fbuffer_append(buffer, delim, delim_len);
    if (object_nl) {
        fbuffer_append(buffer, object_nl, object_nl_len);
    }
    if (indent) {
        for (j = 0; j < depth; j++) {
            fbuffer_append(buffer, indent, indent_len);
        }
    }

    VALUE key_to_s;
    switch(rb_type(key)) {
        case T_STRING:
            key_to_s = key;
            break;
        case T_SYMBOL:
            key_to_s = rb_sym2str(key);
            break;
        default:
            key_to_s = rb_convert_type(key, T_STRING, "String", "to_s");
            break;
    }

    generate_json(buffer, Vstate, state, key_to_s);
    fbuffer_append(buffer, delim2, delim2_len);
    generate_json(buffer, Vstate, state, val);

    arg->iter++;
    return ST_CONTINUE;
}

static void generate_json_object(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    char *object_nl = state->object_nl;
    long object_nl_len = state->object_nl_len;
    char *indent = state->indent;
    long indent_len = state->indent_len;
    long max_nesting = state->max_nesting;
    long depth = ++state->depth;
    int j;
    struct hash_foreach_arg arg;

    if (max_nesting != 0 && depth > max_nesting) {
        rb_raise(eNestingError, "nesting of %ld is too deep", --state->depth);
    }
    fbuffer_append_char(buffer, '{');

    arg.buffer = buffer;
    arg.state = state;
    arg.Vstate = Vstate;
    arg.iter = 0;
    rb_hash_foreach(obj, json_object_i, (VALUE)&arg);

    depth = --state->depth;
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

static void generate_json_array(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    char *array_nl = state->array_nl;
    long array_nl_len = state->array_nl_len;
    char *indent = state->indent;
    long indent_len = state->indent_len;
    long max_nesting = state->max_nesting;
    char *delim = FBUFFER_PTR(state->array_delim);
    long delim_len = FBUFFER_LEN(state->array_delim);
    long depth = ++state->depth;
    int i, j;
    if (max_nesting != 0 && depth > max_nesting) {
        rb_raise(eNestingError, "nesting of %ld is too deep", --state->depth);
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
        generate_json(buffer, Vstate, state, rb_ary_entry(obj, i));
    }
    state->depth = --depth;
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

static int enc_utf8_compatible_p(rb_encoding *enc)
{
    if (enc == rb_usascii_encoding()) return 1;
    if (enc == rb_utf8_encoding()) return 1;
    return 0;
}

static void generate_json_string(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    fbuffer_append_char(buffer, '"');
    if (!enc_utf8_compatible_p(rb_enc_get(obj))) {
        obj = rb_str_export_to_enc(obj, rb_utf8_encoding());
    }
    convert_UTF8_to_JSON(buffer, obj, state->ascii_only, state->script_safe);
    fbuffer_append_char(buffer, '"');
}

static void generate_json_null(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    fbuffer_append(buffer, "null", 4);
}

static void generate_json_false(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    fbuffer_append(buffer, "false", 5);
}

static void generate_json_true(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    fbuffer_append(buffer, "true", 4);
}

static void generate_json_fixnum(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    fbuffer_append_long(buffer, FIX2LONG(obj));
}

static void generate_json_bignum(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    VALUE tmp = rb_funcall(obj, i_to_s, 0);
    fbuffer_append_str(buffer, tmp);
}

#ifdef RUBY_INTEGER_UNIFICATION
static void generate_json_integer(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    if (FIXNUM_P(obj))
        generate_json_fixnum(buffer, Vstate, state, obj);
    else
        generate_json_bignum(buffer, Vstate, state, obj);
}
#endif
static void generate_json_float(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    double value = RFLOAT_VALUE(obj);
    char allow_nan = state->allow_nan;
    VALUE tmp = rb_funcall(obj, i_to_s, 0);
    if (!allow_nan) {
        if (isinf(value)) {
            rb_raise(eGeneratorError, "%"PRIsVALUE" not allowed in JSON", RB_OBJ_STRING(tmp));
        } else if (isnan(value)) {
            rb_raise(eGeneratorError, "%"PRIsVALUE" not allowed in JSON", RB_OBJ_STRING(tmp));
        }
    }
    fbuffer_append_str(buffer, tmp);
}

static void generate_json(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj)
{
    VALUE tmp;
    VALUE klass = CLASS_OF(obj);
    if (klass == rb_cHash) {
        generate_json_object(buffer, Vstate, state, obj);
    } else if (klass == rb_cArray) {
        generate_json_array(buffer, Vstate, state, obj);
    } else if (klass == rb_cString) {
        generate_json_string(buffer, Vstate, state, obj);
    } else if (obj == Qnil) {
        generate_json_null(buffer, Vstate, state, obj);
    } else if (obj == Qfalse) {
        generate_json_false(buffer, Vstate, state, obj);
    } else if (obj == Qtrue) {
        generate_json_true(buffer, Vstate, state, obj);
    } else if (FIXNUM_P(obj)) {
        generate_json_fixnum(buffer, Vstate, state, obj);
    } else if (RB_TYPE_P(obj, T_BIGNUM)) {
        generate_json_bignum(buffer, Vstate, state, obj);
    } else if (klass == rb_cFloat) {
        generate_json_float(buffer, Vstate, state, obj);
    } else if (state->strict) {
        rb_raise(eGeneratorError, "%"PRIsVALUE" not allowed in JSON", RB_OBJ_STRING(CLASS_OF(obj)));
    } else if (rb_respond_to(obj, i_to_json)) {
        tmp = rb_funcall(obj, i_to_json, 1, Vstate);
        Check_Type(tmp, T_STRING);
        fbuffer_append_str(buffer, tmp);
    } else {
        tmp = rb_funcall(obj, i_to_s, 0);
        Check_Type(tmp, T_STRING);
        generate_json_string(buffer, Vstate, state, tmp);
    }
}

static FBuffer *cState_prepare_buffer(VALUE self)
{
    FBuffer *buffer;
    GET_STATE(self);
    buffer = fbuffer_alloc(state->buffer_initial_length);

    if (state->object_delim) {
        fbuffer_clear(state->object_delim);
    } else {
        state->object_delim = fbuffer_alloc(16);
    }
    fbuffer_append_char(state->object_delim, ',');
    if (state->object_delim2) {
        fbuffer_clear(state->object_delim2);
    } else {
        state->object_delim2 = fbuffer_alloc(16);
    }
    if (state->space_before) fbuffer_append(state->object_delim2, state->space_before, state->space_before_len);
    fbuffer_append_char(state->object_delim2, ':');
    if (state->space) fbuffer_append(state->object_delim2, state->space, state->space_len);

    if (state->array_delim) {
        fbuffer_clear(state->array_delim);
    } else {
        state->array_delim = fbuffer_alloc(16);
    }
    fbuffer_append_char(state->array_delim, ',');
    if (state->array_nl) fbuffer_append(state->array_delim, state->array_nl, state->array_nl_len);
    return buffer;
}

struct generate_json_data {
    FBuffer *buffer;
    VALUE vstate;
    JSON_Generator_State *state;
    VALUE obj;
};

static VALUE generate_json_try(VALUE d)
{
    struct generate_json_data *data = (struct generate_json_data *)d;

    generate_json(data->buffer, data->vstate, data->state, data->obj);

    return Qnil;
}

static VALUE generate_json_rescue(VALUE d, VALUE exc)
{
    struct generate_json_data *data = (struct generate_json_data *)d;
    fbuffer_free(data->buffer);

    rb_exc_raise(exc);

    return Qundef;
}

static VALUE cState_partial_generate(VALUE self, VALUE obj)
{
    FBuffer *buffer = cState_prepare_buffer(self);
    GET_STATE(self);

    struct generate_json_data data = {
        .buffer = buffer,
        .vstate = self,
        .state = state,
        .obj = obj
    };
    rb_rescue(generate_json_try, (VALUE)&data, generate_json_rescue, (VALUE)&data);

    return fbuffer_to_s(buffer);
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
    VALUE result = cState_partial_generate(self, obj);
    GET_STATE(self);
    (void)state;
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
 * * *ascii_only*: true if only ASCII characters should be generated. This
 *   option defaults to false.
 * * *buffer_initial_length*: sets the initial length of the generator's
 *   internal buffer.
 */
static VALUE cState_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;
    GET_STATE(self);
    state->max_nesting = 100;
    state->buffer_initial_length = FBUFFER_INITIAL_LENGTH_DEFAULT;
    rb_scan_args(argc, argv, "01", &opts);
    if (!NIL_P(opts)) cState_configure(self, opts);
    return self;
}

/*
 * call-seq: initialize_copy(orig)
 *
 * Initializes this object from orig if it can be duplicated/cloned and returns
 * it.
*/
static VALUE cState_init_copy(VALUE obj, VALUE orig)
{
    JSON_Generator_State *objState, *origState;

    if (obj == orig) return obj;
    GET_STATE_TO(obj, objState);
    GET_STATE_TO(orig, origState);
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
        return rb_class_new_instance(0, NULL, cState);
    }
}

/*
 * call-seq: indent()
 *
 * Returns the string that is used to indent levels in the JSON text.
 */
static VALUE cState_indent(VALUE self)
{
    GET_STATE(self);
    return state->indent ? rb_str_new(state->indent, state->indent_len) : rb_str_new2("");
}

/*
 * call-seq: indent=(indent)
 *
 * Sets the string that is used to indent levels in the JSON text.
 */
static VALUE cState_indent_set(VALUE self, VALUE indent)
{
    unsigned long len;
    GET_STATE(self);
    Check_Type(indent, T_STRING);
    len = RSTRING_LEN(indent);
    if (len == 0) {
        if (state->indent) {
            ruby_xfree(state->indent);
            state->indent = NULL;
            state->indent_len = 0;
        }
    } else {
        if (state->indent) ruby_xfree(state->indent);
        state->indent = fstrndup(RSTRING_PTR(indent), len);
        state->indent_len = len;
    }
    return Qnil;
}

/*
 * call-seq: space()
 *
 * Returns the string that is used to insert a space between the tokens in a JSON
 * string.
 */
static VALUE cState_space(VALUE self)
{
    GET_STATE(self);
    return state->space ? rb_str_new(state->space, state->space_len) : rb_str_new2("");
}

/*
 * call-seq: space=(space)
 *
 * Sets _space_ to the string that is used to insert a space between the tokens in a JSON
 * string.
 */
static VALUE cState_space_set(VALUE self, VALUE space)
{
    unsigned long len;
    GET_STATE(self);
    Check_Type(space, T_STRING);
    len = RSTRING_LEN(space);
    if (len == 0) {
        if (state->space) {
            ruby_xfree(state->space);
            state->space = NULL;
            state->space_len = 0;
        }
    } else {
        if (state->space) ruby_xfree(state->space);
        state->space = fstrndup(RSTRING_PTR(space), len);
        state->space_len = len;
    }
    return Qnil;
}

/*
 * call-seq: space_before()
 *
 * Returns the string that is used to insert a space before the ':' in JSON objects.
 */
static VALUE cState_space_before(VALUE self)
{
    GET_STATE(self);
    return state->space_before ? rb_str_new(state->space_before, state->space_before_len) : rb_str_new2("");
}

/*
 * call-seq: space_before=(space_before)
 *
 * Sets the string that is used to insert a space before the ':' in JSON objects.
 */
static VALUE cState_space_before_set(VALUE self, VALUE space_before)
{
    unsigned long len;
    GET_STATE(self);
    Check_Type(space_before, T_STRING);
    len = RSTRING_LEN(space_before);
    if (len == 0) {
        if (state->space_before) {
            ruby_xfree(state->space_before);
            state->space_before = NULL;
            state->space_before_len = 0;
        }
    } else {
        if (state->space_before) ruby_xfree(state->space_before);
        state->space_before = fstrndup(RSTRING_PTR(space_before), len);
        state->space_before_len = len;
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
    return state->object_nl ? rb_str_new(state->object_nl, state->object_nl_len) : rb_str_new2("");
}

/*
 * call-seq: object_nl=(object_nl)
 *
 * This string is put at the end of a line that holds a JSON object (or
 * Hash).
 */
static VALUE cState_object_nl_set(VALUE self, VALUE object_nl)
{
    unsigned long len;
    GET_STATE(self);
    Check_Type(object_nl, T_STRING);
    len = RSTRING_LEN(object_nl);
    if (len == 0) {
        if (state->object_nl) {
            ruby_xfree(state->object_nl);
            state->object_nl = NULL;
        }
    } else {
        if (state->object_nl) ruby_xfree(state->object_nl);
        state->object_nl = fstrndup(RSTRING_PTR(object_nl), len);
        state->object_nl_len = len;
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
    return state->array_nl ? rb_str_new(state->array_nl, state->array_nl_len) : rb_str_new2("");
}

/*
 * call-seq: array_nl=(array_nl)
 *
 * This string is put at the end of a line that holds a JSON array.
 */
static VALUE cState_array_nl_set(VALUE self, VALUE array_nl)
{
    unsigned long len;
    GET_STATE(self);
    Check_Type(array_nl, T_STRING);
    len = RSTRING_LEN(array_nl);
    if (len == 0) {
        if (state->array_nl) {
            ruby_xfree(state->array_nl);
            state->array_nl = NULL;
        }
    } else {
        if (state->array_nl) ruby_xfree(state->array_nl);
        state->array_nl = fstrndup(RSTRING_PTR(array_nl), len);
        state->array_nl_len = len;
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
 * call-seq: script_safe
 *
 * If this boolean is true, the forward slashes will be escaped in
 * the json output.
 */
static VALUE cState_script_safe(VALUE self)
{
    GET_STATE(self);
    return state->script_safe ? Qtrue : Qfalse;
}

/*
 * call-seq: script_safe=(enable)
 *
 * This sets whether or not the forward slashes will be escaped in
 * the json output.
 */
static VALUE cState_script_safe_set(VALUE self, VALUE enable)
{
    GET_STATE(self);
    state->script_safe = RTEST(enable);
    return Qnil;
}

/*
 * call-seq: strict
 *
 * If this boolean is false, types unsupported by the JSON format will
 * be serialized as strings.
 * If this boolean is true, types unsupported by the JSON format will
 * raise a JSON::GeneratorError.
 */
static VALUE cState_strict(VALUE self)
{
    GET_STATE(self);
    return state->strict ? Qtrue : Qfalse;
}

/*
 * call-seq: strict=(enable)
 *
 * This sets whether or not to serialize types unsupported by the
 * JSON format as strings.
 * If this boolean is false, types unsupported by the JSON format will
 * be serialized as strings.
 * If this boolean is true, types unsupported by the JSON format will
 * raise a JSON::GeneratorError.
 */
static VALUE cState_strict_set(VALUE self, VALUE enable)
{
    GET_STATE(self);
    state->strict = RTEST(enable);
    return Qnil;
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
 * Returns true, if only ASCII characters should be generated. Otherwise
 * returns false.
 */
static VALUE cState_ascii_only_p(VALUE self)
{
    GET_STATE(self);
    return state->ascii_only ? Qtrue : Qfalse;
}

/*
 * call-seq: depth
 *
 * This integer returns the current depth of data structure nesting.
 */
static VALUE cState_depth(VALUE self)
{
    GET_STATE(self);
    return LONG2FIX(state->depth);
}

/*
 * call-seq: depth=(depth)
 *
 * This sets the maximum level of data structure nesting in the generated JSON
 * to the integer depth, max_nesting = 0 if no maximum should be checked.
 */
static VALUE cState_depth_set(VALUE self, VALUE depth)
{
    GET_STATE(self);
    Check_Type(depth, T_FIXNUM);
    state->depth = FIX2LONG(depth);
    return Qnil;
}

/*
 * call-seq: buffer_initial_length
 *
 * This integer returns the current initial length of the buffer.
 */
static VALUE cState_buffer_initial_length(VALUE self)
{
    GET_STATE(self);
    return LONG2FIX(state->buffer_initial_length);
}

/*
 * call-seq: buffer_initial_length=(length)
 *
 * This sets the initial length of the buffer to +length+, if +length+ > 0,
 * otherwise its value isn't changed.
 */
static VALUE cState_buffer_initial_length_set(VALUE self, VALUE buffer_initial_length)
{
    long initial_length;
    GET_STATE(self);
    Check_Type(buffer_initial_length, T_FIXNUM);
    initial_length = FIX2LONG(buffer_initial_length);
    if (initial_length > 0) {
        state->buffer_initial_length = initial_length;
    }
    return Qnil;
}

/*
 *
 */
void Init_generator(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

#undef rb_intern
    rb_require("json/common");

    mJSON = rb_define_module("JSON");
    mExt = rb_define_module_under(mJSON, "Ext");
    mGenerator = rb_define_module_under(mExt, "Generator");

    eGeneratorError = rb_path2class("JSON::GeneratorError");
    eNestingError = rb_path2class("JSON::NestingError");
    rb_gc_register_mark_object(eGeneratorError);
    rb_gc_register_mark_object(eNestingError);

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
    rb_define_method(cState, "script_safe", cState_script_safe, 0);
    rb_define_method(cState, "script_safe?", cState_script_safe, 0);
    rb_define_method(cState, "script_safe=", cState_script_safe_set, 1);
    rb_define_alias(cState, "escape_slash", "script_safe");
    rb_define_alias(cState, "escape_slash?", "script_safe?");
    rb_define_alias(cState, "escape_slash=", "script_safe=");
    rb_define_method(cState, "strict", cState_strict, 0);
    rb_define_method(cState, "strict?", cState_strict, 0);
    rb_define_method(cState, "strict=", cState_strict_set, 1);
    rb_define_method(cState, "check_circular?", cState_check_circular_p, 0);
    rb_define_method(cState, "allow_nan?", cState_allow_nan_p, 0);
    rb_define_method(cState, "ascii_only?", cState_ascii_only_p, 0);
    rb_define_method(cState, "depth", cState_depth, 0);
    rb_define_method(cState, "depth=", cState_depth_set, 1);
    rb_define_method(cState, "buffer_initial_length", cState_buffer_initial_length, 0);
    rb_define_method(cState, "buffer_initial_length=", cState_buffer_initial_length_set, 1);
    rb_define_method(cState, "configure", cState_configure, 1);
    rb_define_alias(cState, "merge", "configure");
    rb_define_method(cState, "to_h", cState_to_h, 0);
    rb_define_alias(cState, "to_hash", "to_h");
    rb_define_method(cState, "[]", cState_aref, 1);
    rb_define_method(cState, "[]=", cState_aset, 2);
    rb_define_method(cState, "generate", cState_generate, 1);

    mGeneratorMethods = rb_define_module_under(mGenerator, "GeneratorMethods");
    mObject = rb_define_module_under(mGeneratorMethods, "Object");
    rb_define_method(mObject, "to_json", mObject_to_json, -1);
    mHash = rb_define_module_under(mGeneratorMethods, "Hash");
    rb_define_method(mHash, "to_json", mHash_to_json, -1);
    mArray = rb_define_module_under(mGeneratorMethods, "Array");
    rb_define_method(mArray, "to_json", mArray_to_json, -1);
#ifdef RUBY_INTEGER_UNIFICATION
    mInteger = rb_define_module_under(mGeneratorMethods, "Integer");
    rb_define_method(mInteger, "to_json", mInteger_to_json, -1);
#else
    mFixnum = rb_define_module_under(mGeneratorMethods, "Fixnum");
    rb_define_method(mFixnum, "to_json", mFixnum_to_json, -1);
    mBignum = rb_define_module_under(mGeneratorMethods, "Bignum");
    rb_define_method(mBignum, "to_json", mBignum_to_json, -1);
#endif
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

    i_to_s = rb_intern("to_s");
    i_to_json = rb_intern("to_json");
    i_new = rb_intern("new");
    i_indent = rb_intern("indent");
    i_space = rb_intern("space");
    i_space_before = rb_intern("space_before");
    i_object_nl = rb_intern("object_nl");
    i_array_nl = rb_intern("array_nl");
    i_max_nesting = rb_intern("max_nesting");
    i_script_safe = rb_intern("script_safe");
    i_escape_slash = rb_intern("escape_slash");
    i_strict = rb_intern("strict");
    i_allow_nan = rb_intern("allow_nan");
    i_ascii_only = rb_intern("ascii_only");
    i_depth = rb_intern("depth");
    i_buffer_initial_length = rb_intern("buffer_initial_length");
    i_pack = rb_intern("pack");
    i_unpack = rb_intern("unpack");
    i_create_id = rb_intern("create_id");
    i_extend = rb_intern("extend");
    i_key_p = rb_intern("key?");
    i_aref = rb_intern("[]");
    i_send = rb_intern("__send__");
    i_respond_to_p = rb_intern("respond_to?");
    i_match = rb_intern("match");
    i_keys = rb_intern("keys");
    i_dup = rb_intern("dup");
}
