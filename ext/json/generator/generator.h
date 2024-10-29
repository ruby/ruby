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

/* ruby api and some helpers */

typedef struct JSON_Generator_StateStruct {
    VALUE indent;
    VALUE space;
    VALUE space_before;
    VALUE object_nl;
    VALUE array_nl;

    long max_nesting;
    long depth;
    long buffer_initial_length;

    bool allow_nan;
    bool ascii_only;
    bool script_safe;
    bool strict;
} JSON_Generator_State;

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

static const rb_data_type_t JSON_Generator_State_type;

#endif
