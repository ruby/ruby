#include <string.h>
#include "ruby.h"
#if HAVE_RUBY_ST_H
#include "ruby/st.h"
#endif
#if HAVE_ST_H
#include "st.h"
#endif
#include "unicode.h"
#include <math.h>

#ifndef RHASH_TBL
#define RHASH_TBL(hsh) (RHASH(hsh)->tbl)
#endif

#ifndef RHASH_SIZE
#define RHASH_SIZE(hsh) (RHASH(hsh)->tbl->num_entries)
#endif

#ifndef RFLOAT_VALUE
#define RFLOAT_VALUE(val) (RFLOAT(val)->value)
#endif

#ifdef HAVE_RUBY_ENCODING_H
#include "ruby/encoding.h"
#define FORCE_UTF8(obj) rb_enc_associate((obj), rb_utf8_encoding())
#else
#define FORCE_UTF8(obj)
#endif

#define check_max_nesting(state, depth) do {                                   \
    long current_nesting = 1 + depth;                                          \
    if (state->max_nesting != 0 && current_nesting > state->max_nesting)       \
        rb_raise(eNestingError, "nesting of %ld is too deep", current_nesting); \
} while (0);

static VALUE mJSON, mExt, mGenerator, cState, mGeneratorMethods, mObject,
             mHash, mArray, mInteger, mFloat, mString, mString_Extend,
             mTrueClass, mFalseClass, mNilClass, eGeneratorError,
             eCircularDatastructure, eNestingError;

static ID i_to_s, i_to_json, i_new, i_indent, i_space, i_space_before,
          i_object_nl, i_array_nl, i_check_circular, i_max_nesting,
          i_allow_nan, i_pack, i_unpack, i_create_id, i_extend;

typedef struct JSON_Generator_StateStruct {
    VALUE indent;
    VALUE space;
    VALUE space_before;
    VALUE object_nl;
    VALUE array_nl;
    int check_circular;
    VALUE seen;
    VALUE memo;
    VALUE depth;
    long max_nesting;
    int flag;
    int allow_nan;
} JSON_Generator_State;

#define GET_STATE(self)                       \
    JSON_Generator_State *state;              \
    Data_Get_Struct(self, JSON_Generator_State, state);

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

static int hash_to_json_state_i(VALUE key, VALUE value, VALUE Vstate)
{
    VALUE json, buf, Vdepth;
    GET_STATE(Vstate);
    buf = state->memo;
    Vdepth = state->depth;

    if (key == Qundef) return ST_CONTINUE;
    if (state->flag) {
        state->flag = 0;
        rb_str_buf_cat2(buf, ",");
        if (RSTRING_LEN(state->object_nl)) rb_str_buf_append(buf, state->object_nl);
    }
    if (RSTRING_LEN(state->object_nl)) {
        rb_str_buf_append(buf, rb_str_times(state->indent, Vdepth));
    }
    json = rb_funcall(rb_funcall(key, i_to_s, 0), i_to_json, 2, Vstate, Vdepth);
    Check_Type(json, T_STRING);
    rb_str_buf_append(buf, json);
    OBJ_INFECT(buf, json);
    if (RSTRING_LEN(state->space_before)) {
        rb_str_buf_append(buf, state->space_before);
    }
    rb_str_buf_cat2(buf, ":");
    if (RSTRING_LEN(state->space)) rb_str_buf_append(buf, state->space);
    json = rb_funcall(value, i_to_json, 2, Vstate, Vdepth);
    Check_Type(json, T_STRING);
    state->flag = 1;
    rb_str_buf_append(buf, json);
    OBJ_INFECT(buf, json);
    state->depth = Vdepth;
    state->memo = buf;
    return ST_CONTINUE;
}

inline static VALUE mHash_json_transfrom(VALUE self, VALUE Vstate, VALUE Vdepth) {
    long depth, len = RHASH_SIZE(self);
    VALUE result;
    GET_STATE(Vstate);

    depth = 1 + FIX2LONG(Vdepth);
    result = rb_str_buf_new(len);
    state->memo = result;
    state->depth = LONG2FIX(depth);
    state->flag = 0;
    rb_str_buf_cat2(result, "{");
    if (RSTRING_LEN(state->object_nl)) rb_str_buf_append(result, state->object_nl);
    rb_hash_foreach(self, hash_to_json_state_i, Vstate);
    if (RSTRING_LEN(state->object_nl)) rb_str_buf_append(result, state->object_nl);
    if (RSTRING_LEN(state->object_nl)) {
        rb_str_buf_append(result, rb_str_times(state->indent, Vdepth));
    }
    rb_str_buf_cat2(result, "}");
    return result;
}

static int hash_to_json_i(VALUE key, VALUE value, VALUE buf)
{
    VALUE tmp;

    if (key == Qundef) return ST_CONTINUE;
    if (RSTRING_LEN(buf) > 1) rb_str_buf_cat2(buf, ",");
    tmp = rb_funcall(rb_funcall(key, i_to_s, 0), i_to_json, 0);
    Check_Type(tmp, T_STRING);
    rb_str_buf_append(buf, tmp);
    OBJ_INFECT(buf, tmp);
    rb_str_buf_cat2(buf, ":");
    tmp = rb_funcall(value, i_to_json, 0);
    Check_Type(tmp, T_STRING);
    rb_str_buf_append(buf, tmp);
    OBJ_INFECT(buf, tmp);

    return ST_CONTINUE;
}

/*
 * call-seq: to_json(state = nil, depth = 0)
 *
 * Returns a JSON string containing a JSON object, that is unparsed from
 * this Hash instance.
 * _state_ is a JSON::State object, that can also be used to configure the
 * produced JSON string output further.
 * _depth_ is used to find out nesting depth, to indent accordingly.
 */
static VALUE mHash_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE Vstate, Vdepth, result;
    long depth;

    rb_scan_args(argc, argv, "02", &Vstate, &Vdepth);
    depth = NIL_P(Vdepth) ? 0 : FIX2LONG(Vdepth);
    if (NIL_P(Vstate)) {
        long len = RHASH_SIZE(self);
        result = rb_str_buf_new(len);
        rb_str_buf_cat2(result, "{");
        rb_hash_foreach(self, hash_to_json_i, result);
        rb_str_buf_cat2(result, "}");
    } else {
        GET_STATE(Vstate);
        check_max_nesting(state, depth);
        if (state->check_circular) {
            VALUE self_id = rb_obj_id(self);
            if (RTEST(rb_hash_aref(state->seen, self_id))) {
                rb_raise(eCircularDatastructure,
                        "circular data structures not supported!");
            }
            rb_hash_aset(state->seen, self_id, Qtrue);
            result = mHash_json_transfrom(self, Vstate, LONG2FIX(depth));
            rb_hash_delete(state->seen, self_id);
        } else {
            result = mHash_json_transfrom(self, Vstate, LONG2FIX(depth));
        }
    }
    OBJ_INFECT(result, self);
    FORCE_UTF8(result);
    return result;
}

inline static VALUE mArray_json_transfrom(VALUE self, VALUE Vstate, VALUE Vdepth) {
    long i, len = RARRAY_LEN(self);
    VALUE shift, result;
    long depth = NIL_P(Vdepth) ? 0 : FIX2LONG(Vdepth);
    VALUE delim = rb_str_new2(",");
    GET_STATE(Vstate);

    check_max_nesting(state, depth);
    if (state->check_circular) {
        VALUE self_id = rb_obj_id(self);
        rb_hash_aset(state->seen, self_id, Qtrue);
        result = rb_str_buf_new(len);
        if (RSTRING_LEN(state->array_nl)) rb_str_append(delim, state->array_nl);
        shift = rb_str_times(state->indent, LONG2FIX(depth + 1));

        rb_str_buf_cat2(result, "[");
        OBJ_INFECT(result, self);
        rb_str_buf_append(result, state->array_nl);
        for (i = 0;  i < len; i++) {
            VALUE element = RARRAY_PTR(self)[i];
            if (RTEST(rb_hash_aref(state->seen, rb_obj_id(element)))) {
                rb_raise(eCircularDatastructure,
                        "circular data structures not supported!");
            }
            OBJ_INFECT(result, element);
            if (i > 0) rb_str_buf_append(result, delim);
            rb_str_buf_append(result, shift);
            element = rb_funcall(element, i_to_json, 2, Vstate, LONG2FIX(depth + 1));
            Check_Type(element, T_STRING);
            rb_str_buf_append(result, element);
        }
        if (RSTRING_LEN(state->array_nl)) {
            rb_str_buf_append(result, state->array_nl);
            rb_str_buf_append(result, rb_str_times(state->indent, LONG2FIX(depth)));
        }
        rb_str_buf_cat2(result, "]");
        rb_hash_delete(state->seen, self_id);
    } else {
        result = rb_str_buf_new(len);
        OBJ_INFECT(result, self);
        if (RSTRING_LEN(state->array_nl)) rb_str_append(delim, state->array_nl);
        shift = rb_str_times(state->indent, LONG2FIX(depth + 1));

        rb_str_buf_cat2(result, "[");
        rb_str_buf_append(result, state->array_nl);
        for (i = 0;  i < len; i++) {
            VALUE element = RARRAY_PTR(self)[i];
            OBJ_INFECT(result, element);
            if (i > 0) rb_str_buf_append(result, delim);
            rb_str_buf_append(result, shift);
            element = rb_funcall(element, i_to_json, 2, Vstate, LONG2FIX(depth + 1));
            Check_Type(element, T_STRING);
            rb_str_buf_append(result, element);
        }
        rb_str_buf_append(result, state->array_nl);
        if (RSTRING_LEN(state->array_nl)) {
            rb_str_buf_append(result, rb_str_times(state->indent, LONG2FIX(depth)));
        }
        rb_str_buf_cat2(result, "]");
    }
    return result;
}

/*
 * call-seq: to_json(state = nil, depth = 0)
 *
 * Returns a JSON string containing a JSON array, that is unparsed from
 * this Array instance.
 * _state_ is a JSON::State object, that can also be used to configure the
 * produced JSON string output further.
 * _depth_ is used to find out nesting depth, to indent accordingly.
 */
static VALUE mArray_to_json(int argc, VALUE *argv, VALUE self) {
    VALUE Vstate, Vdepth, result;

    rb_scan_args(argc, argv, "02", &Vstate, &Vdepth);
    if (NIL_P(Vstate)) {
        long i, len = RARRAY_LEN(self);
        result = rb_str_buf_new(2 + 2 * len);
        rb_str_buf_cat2(result, "[");
        OBJ_INFECT(result, self);
        for (i = 0;  i < len; i++) {
            VALUE element = RARRAY_PTR(self)[i];
            OBJ_INFECT(result, element);
            if (i > 0) rb_str_buf_cat2(result, ",");
            element = rb_funcall(element, i_to_json, 0);
            Check_Type(element, T_STRING);
            rb_str_buf_append(result, element);
        }
        rb_str_buf_cat2(result, "]");
    } else {
        result = mArray_json_transfrom(self, Vstate, Vdepth);
    }
    OBJ_INFECT(result, self);
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string representation for this Integer number.
 */
static VALUE mInteger_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE result = rb_funcall(self, i_to_s, 0);
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string representation for this Float number.
 */
static VALUE mFloat_to_json(int argc, VALUE *argv, VALUE self)
{
    JSON_Generator_State *state = NULL;
    VALUE Vstate, rest, tmp, result;
    double value = RFLOAT_VALUE(self);
    rb_scan_args(argc, argv, "01*", &Vstate, &rest);
    if (!NIL_P(Vstate)) Data_Get_Struct(Vstate, JSON_Generator_State, state);
    if (isinf(value)) {
        if (!state || state->allow_nan) {
            result = rb_funcall(self, i_to_s, 0);
        } else {
            tmp = rb_funcall(self, i_to_s, 0);
            rb_raise(eGeneratorError, "%u: %s not allowed in JSON", __LINE__, StringValueCStr(tmp));
        }
    } else if (isnan(value)) {
        if (!state || state->allow_nan) {
            result = rb_funcall(self, i_to_s, 0);
        } else {
            tmp = rb_funcall(self, i_to_s, 0);
            rb_raise(eGeneratorError, "%u: %s not allowed in JSON", __LINE__, StringValueCStr(tmp));
        }
    } else {
        result = rb_funcall(self, i_to_s, 0);
    }
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: String.included(modul)
 *
 * Extends _modul_ with the String::Extend module.
 */
static VALUE mString_included_s(VALUE self, VALUE modul) {
    VALUE result = rb_funcall(modul, i_extend, 1, mString_Extend);
    FORCE_UTF8(result);
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
    VALUE result = rb_str_buf_new(RSTRING_LEN(self));
    rb_str_buf_cat2(result, "\"");
    JSON_convert_UTF8_to_JSON(result, self, strictConversion);
    rb_str_buf_cat2(result, "\"");
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: to_json_raw_object()
 *
 * This method creates a raw object hash, that can be nested into
 * other data structures and will be unparsed as a raw string. This
 * method should be used, if you want to convert raw strings to JSON
 * instead of UTF-8 strings, e. g. binary data.
 */
static VALUE mString_to_json_raw_object(VALUE self) {
    VALUE ary;
    VALUE result = rb_hash_new();
    rb_hash_aset(result, rb_funcall(mJSON, i_create_id, 0), rb_class_name(rb_obj_class(self)));
    ary = rb_funcall(self, i_unpack, 1, rb_str_new2("C*"));
    rb_hash_aset(result, rb_str_new2("raw"), ary);
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: to_json_raw(*args)
 *
 * This method creates a JSON text from the result of a call to
 * to_json_raw_object of this String.
 */
static VALUE mString_to_json_raw(int argc, VALUE *argv, VALUE self) {
    VALUE result, obj = mString_to_json_raw_object(self);
    Check_Type(obj, T_HASH);
    result = mHash_to_json(argc, argv, obj);
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: json_create(o)
 *
 * Raw Strings are JSON Objects (the raw bytes are stored in an array for the
 * key "raw"). The Ruby String can be created by this module method.
 */
static VALUE mString_Extend_json_create(VALUE self, VALUE o) {
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
    VALUE result = rb_str_new2("true");
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: to_json(*)
 *
 * Returns a JSON string for false: 'false'.
 */
static VALUE mFalseClass_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE result = rb_str_new2("false");
    FORCE_UTF8(result);
    return result;
}

/*
 * call-seq: to_json(*)
 *
 */
static VALUE mNilClass_to_json(int argc, VALUE *argv, VALUE self)
{
    VALUE result = rb_str_new2("null");
    FORCE_UTF8(result);
    return result;
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
    VALUE result, string = rb_funcall(self, i_to_s, 0);
    Check_Type(string, T_STRING);
    result = mString_to_json(argc, argv, string);
    FORCE_UTF8(result);
    return result;
}

/*
 * Document-class: JSON::Ext::Generator::State
 *
 * This class is used to create State instances, that are use to hold data
 * while generating a JSON text from a a Ruby data structure.
 */

static void State_mark(JSON_Generator_State *state)
{
    rb_gc_mark_maybe(state->indent);
    rb_gc_mark_maybe(state->space);
    rb_gc_mark_maybe(state->space_before);
    rb_gc_mark_maybe(state->object_nl);
    rb_gc_mark_maybe(state->array_nl);
    rb_gc_mark_maybe(state->seen);
    rb_gc_mark_maybe(state->memo);
    rb_gc_mark_maybe(state->depth);
}

static JSON_Generator_State *State_allocate()
{
    JSON_Generator_State *state = ALLOC(JSON_Generator_State);
    return state;
}

static VALUE cState_s_allocate(VALUE klass)
{
    JSON_Generator_State *state = State_allocate();
    return Data_Wrap_Struct(klass, State_mark, -1, state);
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
        Check_Type(tmp, T_STRING);
        state->indent = tmp;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_space));
    if (RTEST(tmp)) {
        Check_Type(tmp, T_STRING);
        state->space = tmp;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_space_before));
    if (RTEST(tmp)) {
        Check_Type(tmp, T_STRING);
        state->space_before = tmp;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_array_nl));
    if (RTEST(tmp)) {
        Check_Type(tmp, T_STRING);
        state->array_nl = tmp;
    }
    tmp = rb_hash_aref(opts, ID2SYM(i_object_nl));
    if (RTEST(tmp)) {
        Check_Type(tmp, T_STRING);
        state->object_nl = tmp;
    }
    tmp = ID2SYM(i_check_circular);
    if (st_lookup(RHASH_TBL(opts), tmp, 0)) {
        tmp = rb_hash_aref(opts, ID2SYM(i_check_circular));
        state->check_circular = RTEST(tmp);
    } else {
        state->check_circular = 1;
    }
    tmp = ID2SYM(i_max_nesting);
    state->max_nesting = 19;
    if (st_lookup(RHASH_TBL(opts), tmp, 0)) {
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
    rb_hash_aset(result, ID2SYM(i_indent), state->indent);
    rb_hash_aset(result, ID2SYM(i_space), state->space);
    rb_hash_aset(result, ID2SYM(i_space_before), state->space_before);
    rb_hash_aset(result, ID2SYM(i_object_nl), state->object_nl);
    rb_hash_aset(result, ID2SYM(i_array_nl), state->array_nl);
    rb_hash_aset(result, ID2SYM(i_check_circular), state->check_circular ? Qtrue : Qfalse);
    rb_hash_aset(result, ID2SYM(i_allow_nan), state->allow_nan ? Qtrue : Qfalse);
    rb_hash_aset(result, ID2SYM(i_max_nesting), LONG2FIX(state->max_nesting));
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
 * * *check_circular*: true if checking for circular data structures
 *   should be done, false (the default) otherwise.
 * * *allow_nan*: true if NaN, Infinity, and -Infinity should be
 *   generated, otherwise an exception is thrown, if these values are
 *   encountered. This options defaults to false.
 */
static VALUE cState_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;
    GET_STATE(self);

    rb_scan_args(argc, argv, "01", &opts);
    state->indent = rb_str_new2("");
    state->space = rb_str_new2("");
    state->space_before = rb_str_new2("");
    state->array_nl = rb_str_new2("");
    state->object_nl = rb_str_new2("");
    if (NIL_P(opts)) {
        state->check_circular = 1;
        state->allow_nan = 0;
        state->max_nesting = 19;
    } else {
        cState_configure(self, opts);
    }
    state->seen = rb_hash_new();
    state->memo = Qnil;
    state->depth = INT2FIX(0);
    return self;
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
        return rb_funcall(self, i_new, 0);
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
    return state->indent;
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
    return state->indent = indent;
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
    return state->space;
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
    return state->space = space;
}

/*
 * call-seq: space_before()
 *
 * This string is used to insert a space before the ':' in JSON objects.
 */
static VALUE cState_space_before(VALUE self)
{
    GET_STATE(self);
    return state->space_before;
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
    return state->space_before = space_before;
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
    return state->object_nl;
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
    return state->object_nl = object_nl;
}

/*
 * call-seq: array_nl()
 *
 * This string is put at the end of a line that holds a JSON array.
 */
static VALUE cState_array_nl(VALUE self)
{
    GET_STATE(self);
    return state->array_nl;
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
    return state->array_nl = array_nl;
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
    return state->check_circular ? Qtrue : Qfalse;
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
    state->max_nesting = FIX2LONG(depth);
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
 * call-seq: seen?(object)
 *
 * Returns _true_, if _object_ was already seen during this generating run.
 */
static VALUE cState_seen_p(VALUE self, VALUE object)
{
    GET_STATE(self);
    return rb_hash_aref(state->seen, rb_obj_id(object));
}

/*
 * call-seq: remember(object)
 *
 * Remember _object_, to find out if it was already encountered (if a cyclic
 * data structure is rendered).
 */
static VALUE cState_remember(VALUE self, VALUE object)
{
    GET_STATE(self);
    return rb_hash_aset(state->seen, rb_obj_id(object), Qtrue);
}

/*
 * call-seq: forget(object)
 *
 * Forget _object_ for this generating run.
 */
static VALUE cState_forget(VALUE self, VALUE object)
{
    GET_STATE(self);
    return rb_hash_delete(state->seen, rb_obj_id(object));
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
    eCircularDatastructure = rb_path2class("JSON::CircularDatastructure");
    eNestingError = rb_path2class("JSON::NestingError");
    cState = rb_define_class_under(mGenerator, "State", rb_cObject);
    rb_define_alloc_func(cState, cState_s_allocate);
    rb_define_singleton_method(cState, "from_state", cState_from_state_s, 1);
    rb_define_method(cState, "initialize", cState_initialize, -1);

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
    rb_define_method(cState, "check_circular?", cState_check_circular_p, 0);
    rb_define_method(cState, "max_nesting", cState_max_nesting, 0);
    rb_define_method(cState, "max_nesting=", cState_max_nesting_set, 1);
    rb_define_method(cState, "allow_nan?", cState_allow_nan_p, 0);
    rb_define_method(cState, "seen?", cState_seen_p, 1);
    rb_define_method(cState, "remember", cState_remember, 1);
    rb_define_method(cState, "forget", cState_forget, 1);
    rb_define_method(cState, "configure", cState_configure, 1);
    rb_define_method(cState, "to_h", cState_to_h, 0);

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

    i_to_s = rb_intern("to_s");
    i_to_json = rb_intern("to_json");
    i_new = rb_intern("new");
    i_indent = rb_intern("indent");
    i_space = rb_intern("space");
    i_space_before = rb_intern("space_before");
    i_object_nl = rb_intern("object_nl");
    i_array_nl = rb_intern("array_nl");
    i_check_circular = rb_intern("check_circular");
    i_max_nesting = rb_intern("max_nesting");
    i_allow_nan = rb_intern("allow_nan");
    i_pack = rb_intern("pack");
    i_unpack = rb_intern("unpack");
    i_create_id = rb_intern("create_id");
    i_extend = rb_intern("extend");
}
