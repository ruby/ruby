#ifndef _GENERATOR_H_
#define _GENERATOR_H_

#include <math.h>
#include <ctype.h>

#include "ruby.h"

/* This is the fallback definition from Ruby 3.4 */
#ifndef RBIMPL_STDBOOL_H
#if defined(__cplusplus)
# if defined(HAVE_STDBOOL_H) && (__cplusplus >= 201103L)
#  include <cstdbool>
# endif
#elif defined(HAVE_STDBOOL_H)
# include <stdbool.h>
#elif !defined(HAVE__BOOL)
typedef unsigned char _Bool;
# define bool  _Bool
# define true  ((_Bool)+1)
# define false ((_Bool)+0)
# define __bool_true_false_are_defined
#endif
#endif

static char *fstrndup(const char *ptr, unsigned long len);

/* ruby api and some helpers */

typedef struct JSON_Generator_StateStruct {
    char *indent;
    long indent_len;
    char *space;
    long space_len;
    char *space_before;
    long space_before_len;
    char *object_nl;
    long object_nl_len;
    char *array_nl;
    long array_nl_len;
    long max_nesting;
    char allow_nan;
    char ascii_only;
    char script_safe;
    char strict;
    long depth;
    long buffer_initial_length;
} JSON_Generator_State;

#define GET_STATE_TO(self, state) \
    TypedData_Get_Struct(self, JSON_Generator_State, &JSON_Generator_State_type, state)

#define GET_STATE(self)                       \
    JSON_Generator_State *state;              \
    GET_STATE_TO(self, state)

#define GENERATE_JSON(type)                                                                     \
    FBuffer *buffer;                                                                            \
    VALUE Vstate;                                                                               \
    JSON_Generator_State *state;                                                                \
                                                                                                \
    rb_scan_args(argc, argv, "01", &Vstate);                                                    \
    Vstate = cState_from_state_s(cState, Vstate);                                               \
    TypedData_Get_Struct(Vstate, JSON_Generator_State, &JSON_Generator_State_type, state);      \
    buffer = cState_prepare_buffer(Vstate);                                                     \
    generate_json_##type(buffer, Vstate, state, self);                                          \
    return fbuffer_to_s(buffer)

static VALUE mHash_to_json(int argc, VALUE *argv, VALUE self);
static VALUE mArray_to_json(int argc, VALUE *argv, VALUE self);
#ifdef RUBY_INTEGER_UNIFICATION
static VALUE mInteger_to_json(int argc, VALUE *argv, VALUE self);
#else
static VALUE mFixnum_to_json(int argc, VALUE *argv, VALUE self);
static VALUE mBignum_to_json(int argc, VALUE *argv, VALUE self);
#endif
static VALUE mFloat_to_json(int argc, VALUE *argv, VALUE self);
static VALUE mString_included_s(VALUE self, VALUE modul);
static VALUE mString_to_json(int argc, VALUE *argv, VALUE self);
static VALUE mString_to_json_raw_object(VALUE self);
static VALUE mString_to_json_raw(int argc, VALUE *argv, VALUE self);
static VALUE mString_Extend_json_create(VALUE self, VALUE o);
static VALUE mTrueClass_to_json(int argc, VALUE *argv, VALUE self);
static VALUE mFalseClass_to_json(int argc, VALUE *argv, VALUE self);
static VALUE mNilClass_to_json(int argc, VALUE *argv, VALUE self);
static VALUE mObject_to_json(int argc, VALUE *argv, VALUE self);
static void State_free(void *state);
static VALUE cState_s_allocate(VALUE klass);
static void generate_json(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static void generate_json_object(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static void generate_json_array(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static void generate_json_string(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static void generate_json_null(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static void generate_json_false(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static void generate_json_true(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
#ifdef RUBY_INTEGER_UNIFICATION
static void generate_json_integer(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
#endif
static void generate_json_fixnum(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static void generate_json_bignum(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static void generate_json_float(FBuffer *buffer, VALUE Vstate, JSON_Generator_State *state, VALUE obj);
static VALUE cState_partial_generate(VALUE self, VALUE obj);
static VALUE cState_generate(VALUE self, VALUE obj);
static VALUE cState_from_state_s(VALUE self, VALUE opts);
static VALUE cState_indent(VALUE self);
static VALUE cState_indent_set(VALUE self, VALUE indent);
static VALUE cState_space(VALUE self);
static VALUE cState_space_set(VALUE self, VALUE space);
static VALUE cState_space_before(VALUE self);
static VALUE cState_space_before_set(VALUE self, VALUE space_before);
static VALUE cState_object_nl(VALUE self);
static VALUE cState_object_nl_set(VALUE self, VALUE object_nl);
static VALUE cState_array_nl(VALUE self);
static VALUE cState_array_nl_set(VALUE self, VALUE array_nl);
static VALUE cState_max_nesting(VALUE self);
static VALUE cState_max_nesting_set(VALUE self, VALUE depth);
static VALUE cState_allow_nan_p(VALUE self);
static VALUE cState_ascii_only_p(VALUE self);
static VALUE cState_depth(VALUE self);
static VALUE cState_depth_set(VALUE self, VALUE depth);
static VALUE cState_script_safe(VALUE self);
static VALUE cState_script_safe_set(VALUE self, VALUE depth);
static VALUE cState_strict(VALUE self);
static VALUE cState_strict_set(VALUE self, VALUE strict);
static FBuffer *cState_prepare_buffer(VALUE self);

static const rb_data_type_t JSON_Generator_State_type;

#endif
