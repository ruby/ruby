#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE object_spec_FL_ABLE(VALUE self, VALUE obj) {
  if (FL_ABLE(obj)) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static int object_spec_FL_TEST_flag(VALUE flag_string) {
  char *flag_cstr = StringValueCStr(flag_string);
  if (strcmp(flag_cstr, "FL_FREEZE") == 0) {
    return FL_FREEZE;
  }
  return 0;
}

static VALUE object_spec_FL_TEST(VALUE self, VALUE obj, VALUE flag) {
  return INT2FIX(FL_TEST(obj, object_spec_FL_TEST_flag(flag)));
}

static VALUE object_spec_rb_any_to_s(VALUE self, VALUE obj) {
  return rb_any_to_s(obj);
}

static VALUE so_attr_get(VALUE self, VALUE obj, VALUE attr) {
  return rb_attr_get(obj, SYM2ID(attr));
}

static VALUE object_spec_rb_obj_instance_variables(VALUE self, VALUE obj) {
  return rb_obj_instance_variables(obj);
}

static VALUE so_check_array_type(VALUE self, VALUE ary) {
  return rb_check_array_type(ary);
}

static VALUE so_check_convert_type(VALUE self, VALUE obj, VALUE klass, VALUE method) {
  return rb_check_convert_type(obj, T_ARRAY, RSTRING_PTR(klass), RSTRING_PTR(method));
}

static VALUE so_check_to_integer(VALUE self, VALUE obj, VALUE method) {
  return rb_check_to_integer(obj, RSTRING_PTR(method));
}

static VALUE object_spec_rb_check_frozen(VALUE self, VALUE obj) {
  rb_check_frozen(obj);
  return Qnil;
}

static VALUE so_check_string_type(VALUE self, VALUE str) {
  return rb_check_string_type(str);
}

static VALUE so_rbclassof(VALUE self, VALUE obj) {
  return rb_class_of(obj);
}

static VALUE so_convert_type(VALUE self, VALUE obj, VALUE klass, VALUE method) {
  return rb_convert_type(obj, T_ARRAY, RSTRING_PTR(klass), RSTRING_PTR(method));
}

static VALUE object_spec_rb_extend_object(VALUE self, VALUE obj, VALUE mod) {
  rb_extend_object(obj, mod);
  return obj;
}

static VALUE so_inspect(VALUE self, VALUE obj) {
  return rb_inspect(obj);
}

static VALUE so_rb_obj_alloc(VALUE self, VALUE klass) {
  return rb_obj_alloc(klass);
}

static VALUE so_rb_obj_dup(VALUE self, VALUE klass) {
  return rb_obj_dup(klass);
}

static VALUE so_rb_obj_call_init(VALUE self, VALUE object,
                                 VALUE nargs, VALUE args) {
  int c_nargs = FIX2INT(nargs);
  VALUE *c_args = (VALUE*) alloca(sizeof(VALUE) * c_nargs);
  int i;

  for (i = 0; i < c_nargs; i++)
    c_args[i] = rb_ary_entry(args, i);

  rb_obj_call_init(object, c_nargs, c_args);

  return Qnil;
}

static VALUE so_rb_obj_class(VALUE self, VALUE obj) {
  return rb_obj_class(obj);
}

static VALUE so_rbobjclassname(VALUE self, VALUE obj) {
  return rb_str_new2(rb_obj_classname(obj));
}

static VALUE object_spec_rb_obj_freeze(VALUE self, VALUE obj) {
  return rb_obj_freeze(obj);
}

static VALUE object_spec_rb_obj_frozen_p(VALUE self, VALUE obj) {
  return rb_obj_frozen_p(obj);
}

static VALUE object_spec_rb_obj_id(VALUE self, VALUE obj) {
  return rb_obj_id(obj);
}

static VALUE so_instance_of(VALUE self, VALUE obj, VALUE klass) {
  return rb_obj_is_instance_of(obj, klass);
}

static VALUE so_kind_of(VALUE self, VALUE obj, VALUE klass) {
  return rb_obj_is_kind_of(obj, klass);
}

static VALUE object_specs_rb_obj_method_arity(VALUE self, VALUE obj, VALUE mid) {
  return INT2FIX(rb_obj_method_arity(obj, SYM2ID(mid)));
}

static VALUE object_specs_rb_obj_method(VALUE self, VALUE obj, VALUE method) {
  return rb_obj_method(obj, method);
}

static VALUE so_require(VALUE self) {
  rb_require("fixtures/foo");
  return Qnil;
}

static VALUE so_respond_to(VALUE self, VALUE obj, VALUE sym) {
  return rb_respond_to(obj, SYM2ID(sym)) ? Qtrue : Qfalse;
}

static VALUE so_obj_respond_to(VALUE self, VALUE obj, VALUE sym, VALUE priv) {
  return rb_obj_respond_to(obj, SYM2ID(sym), priv == Qtrue ? 1 : 0) ? Qtrue : Qfalse;
}

static VALUE object_spec_rb_method_boundp(VALUE self, VALUE obj, VALUE method, VALUE exclude_private) {
  ID id = SYM2ID(method);
  return rb_method_boundp(obj, id, exclude_private == Qtrue ? 1 : 0) ? Qtrue : Qfalse;
}

static VALUE object_spec_rb_special_const_p(VALUE self, VALUE value) {
  return rb_special_const_p(value);
}

static VALUE so_to_id(VALUE self, VALUE obj) {
  return ID2SYM(rb_to_id(obj));
}

static VALUE object_spec_RTEST(VALUE self, VALUE value) {
  return RTEST(value) ? Qtrue : Qfalse;
}

static VALUE so_check_type(VALUE self, VALUE obj, VALUE other) {
  rb_check_type(obj, TYPE(other));
  return Qtrue;
}

static VALUE so_is_type_nil(VALUE self, VALUE obj) {
  if (TYPE(obj) == T_NIL) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_type_object(VALUE self, VALUE obj) {
  if (TYPE(obj) == T_OBJECT) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_type_array(VALUE self, VALUE obj) {
  if (TYPE(obj) == T_ARRAY) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_type_module(VALUE self, VALUE obj) {
  if (TYPE(obj) == T_MODULE) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_type_class(VALUE self, VALUE obj) {
  if (TYPE(obj) == T_CLASS) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_type_data(VALUE self, VALUE obj) {
  if (TYPE(obj) == T_DATA) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_rb_type_p_nil(VALUE self, VALUE obj) {
  if (rb_type_p(obj, T_NIL)) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_rb_type_p_object(VALUE self, VALUE obj) {
  if (rb_type_p(obj, T_OBJECT)) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_rb_type_p_array(VALUE self, VALUE obj) {
  if (rb_type_p(obj, T_ARRAY)) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_rb_type_p_module(VALUE self, VALUE obj) {
  if (rb_type_p(obj, T_MODULE)) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_rb_type_p_class(VALUE self, VALUE obj) {
  if (rb_type_p(obj, T_CLASS)) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_rb_type_p_data(VALUE self, VALUE obj) {
  if (rb_type_p(obj, T_DATA)) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_rb_type_p_file(VALUE self, VALUE obj) {
  if (rb_type_p(obj, T_FILE)) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_builtin_type_object(VALUE self, VALUE obj) {
  if (BUILTIN_TYPE(obj) == T_OBJECT) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_builtin_type_array(VALUE self, VALUE obj) {
  if (BUILTIN_TYPE(obj) == T_ARRAY) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_builtin_type_module(VALUE self, VALUE obj) {
  if (BUILTIN_TYPE(obj) == T_MODULE) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_builtin_type_class(VALUE self, VALUE obj) {
  if (BUILTIN_TYPE(obj) == T_CLASS) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE so_is_builtin_type_data(VALUE self, VALUE obj) {
  if (BUILTIN_TYPE(obj) == T_DATA) {
    return Qtrue;
  }
  return Qfalse;
}

static VALUE object_spec_rb_to_int(VALUE self, VALUE obj) {
  return rb_to_int(obj);
}

static VALUE object_spec_rb_obj_instance_eval(VALUE self, VALUE obj) {
  return rb_obj_instance_eval(0, NULL, obj);
}

static VALUE object_spec_rb_iv_get(VALUE self, VALUE obj, VALUE name) {
  return rb_iv_get(obj, RSTRING_PTR(name));
}

static VALUE object_spec_rb_iv_set(VALUE self, VALUE obj, VALUE name, VALUE value) {
  return rb_iv_set(obj, RSTRING_PTR(name), value);
}

static VALUE object_spec_rb_ivar_count(VALUE self, VALUE obj) {
  return ULONG2NUM(rb_ivar_count(obj));
}

static VALUE object_spec_rb_ivar_get(VALUE self, VALUE obj, VALUE sym_name) {
  return rb_ivar_get(obj, SYM2ID(sym_name));
}

static VALUE object_spec_rb_ivar_set(VALUE self, VALUE obj, VALUE sym_name, VALUE value) {
  return rb_ivar_set(obj, SYM2ID(sym_name), value);
}

static VALUE object_spec_rb_ivar_defined(VALUE self, VALUE obj, VALUE sym_name) {
  return rb_ivar_defined(obj, SYM2ID(sym_name));
}

static VALUE object_spec_rb_copy_generic_ivar(VALUE self, VALUE clone, VALUE obj) {
  rb_copy_generic_ivar(clone, obj);
  return self;
}

static VALUE object_spec_rb_free_generic_ivar(VALUE self, VALUE obj) {
  rb_free_generic_ivar(obj);
  return self;
}

static VALUE object_spec_rb_equal(VALUE self, VALUE a, VALUE b) {
  return rb_equal(a, b);
}

static VALUE object_spec_rb_class_inherited_p(VALUE self, VALUE mod, VALUE arg) {
  return rb_class_inherited_p(mod, arg);
}

static int foreach_f(ID key, VALUE val, VALUE ary) {
  rb_ary_push(ary, ID2SYM(key));
  rb_ary_push(ary, val);
  return ST_CONTINUE;
}

static VALUE object_spec_rb_ivar_foreach(VALUE self, VALUE obj) {
  VALUE ary = rb_ary_new();
  rb_ivar_foreach(obj, foreach_f, ary);
  return ary;
}

static VALUE speced_allocator(VALUE klass) {
  VALUE super = rb_class_get_superclass(klass);
  VALUE instance = rb_get_alloc_func(super)(klass);
  rb_iv_set(instance, "@from_custom_allocator", Qtrue);
  return instance;
}

static VALUE object_spec_rb_define_alloc_func(VALUE self, VALUE klass) {
  rb_define_alloc_func(klass, speced_allocator);
  return Qnil;
}

static VALUE object_spec_rb_undef_alloc_func(VALUE self, VALUE klass) {
  rb_undef_alloc_func(klass);
  return Qnil;
}

static VALUE object_spec_speced_allocator_p(VALUE self, VALUE klass) {
  rb_alloc_func_t allocator = rb_get_alloc_func(klass);
  return (allocator == speced_allocator) ? Qtrue : Qfalse;
}

static VALUE object_spec_custom_alloc_func_p(VALUE self, VALUE klass) {
  rb_alloc_func_t allocator = rb_get_alloc_func(klass);
  return allocator ? Qtrue : Qfalse;
}

static VALUE object_spec_redefine_frozen(VALUE self) {
    // The purpose of this spec is to verify that `frozen?`
    // and `RB_OBJ_FROZEN` do not mutually recurse infinitely.
    if (RB_OBJ_FROZEN(self)) {
        return Qtrue;
    }

    return Qfalse;
}

void Init_object_spec(void) {
  VALUE cls = rb_define_class("CApiObjectSpecs", rb_cObject);
  rb_define_method(cls, "FL_ABLE", object_spec_FL_ABLE, 1);
  rb_define_method(cls, "FL_TEST", object_spec_FL_TEST, 2);
  rb_define_method(cls, "rb_any_to_s", object_spec_rb_any_to_s, 1);
  rb_define_method(cls, "rb_attr_get", so_attr_get, 2);
  rb_define_method(cls, "rb_obj_instance_variables", object_spec_rb_obj_instance_variables, 1);
  rb_define_method(cls, "rb_check_array_type", so_check_array_type, 1);
  rb_define_method(cls, "rb_check_convert_type", so_check_convert_type, 3);
  rb_define_method(cls, "rb_check_to_integer", so_check_to_integer, 2);
  rb_define_method(cls, "rb_check_frozen", object_spec_rb_check_frozen, 1);
  rb_define_method(cls, "rb_check_string_type", so_check_string_type, 1);
  rb_define_method(cls, "rb_class_of", so_rbclassof, 1);
  rb_define_method(cls, "rb_convert_type", so_convert_type, 3);
  rb_define_method(cls, "rb_extend_object", object_spec_rb_extend_object, 2);
  rb_define_method(cls, "rb_inspect", so_inspect, 1);
  rb_define_method(cls, "rb_obj_alloc", so_rb_obj_alloc, 1);
  rb_define_method(cls, "rb_obj_dup", so_rb_obj_dup, 1);
  rb_define_method(cls, "rb_obj_call_init", so_rb_obj_call_init, 3);
  rb_define_method(cls, "rb_obj_class", so_rb_obj_class, 1);
  rb_define_method(cls, "rb_obj_classname", so_rbobjclassname, 1);
  rb_define_method(cls, "rb_obj_freeze", object_spec_rb_obj_freeze, 1);
  rb_define_method(cls, "rb_obj_frozen_p", object_spec_rb_obj_frozen_p, 1);
  rb_define_method(cls, "rb_obj_id", object_spec_rb_obj_id, 1);
  rb_define_method(cls, "rb_obj_is_instance_of", so_instance_of, 2);
  rb_define_method(cls, "rb_obj_is_kind_of", so_kind_of, 2);
  rb_define_method(cls, "rb_obj_method_arity", object_specs_rb_obj_method_arity, 2);
  rb_define_method(cls, "rb_obj_method", object_specs_rb_obj_method, 2);
  rb_define_method(cls, "rb_require", so_require, 0);
  rb_define_method(cls, "rb_respond_to", so_respond_to, 2);
  rb_define_method(cls, "rb_method_boundp", object_spec_rb_method_boundp, 3);
  rb_define_method(cls, "rb_obj_respond_to", so_obj_respond_to, 3);
  rb_define_method(cls, "rb_special_const_p", object_spec_rb_special_const_p, 1);
  rb_define_method(cls, "rb_to_id", so_to_id, 1);
  rb_define_method(cls, "RTEST", object_spec_RTEST, 1);
  rb_define_method(cls, "rb_check_type", so_check_type, 2);
  rb_define_method(cls, "rb_is_type_nil", so_is_type_nil, 1);
  rb_define_method(cls, "rb_is_type_object", so_is_type_object, 1);
  rb_define_method(cls, "rb_is_type_array", so_is_type_array, 1);
  rb_define_method(cls, "rb_is_type_module", so_is_type_module, 1);
  rb_define_method(cls, "rb_is_type_class", so_is_type_class, 1);
  rb_define_method(cls, "rb_is_type_data", so_is_type_data, 1);
  rb_define_method(cls, "rb_is_rb_type_p_nil", so_is_rb_type_p_nil, 1);
  rb_define_method(cls, "rb_is_rb_type_p_object", so_is_rb_type_p_object, 1);
  rb_define_method(cls, "rb_is_rb_type_p_array", so_is_rb_type_p_array, 1);
  rb_define_method(cls, "rb_is_rb_type_p_module", so_is_rb_type_p_module, 1);
  rb_define_method(cls, "rb_is_rb_type_p_class", so_is_rb_type_p_class, 1);
  rb_define_method(cls, "rb_is_rb_type_p_data", so_is_rb_type_p_data, 1);
  rb_define_method(cls, "rb_is_rb_type_p_file", so_is_rb_type_p_file, 1);
  rb_define_method(cls, "rb_is_builtin_type_object", so_is_builtin_type_object, 1);
  rb_define_method(cls, "rb_is_builtin_type_array", so_is_builtin_type_array, 1);
  rb_define_method(cls, "rb_is_builtin_type_module", so_is_builtin_type_module, 1);
  rb_define_method(cls, "rb_is_builtin_type_class", so_is_builtin_type_class, 1);
  rb_define_method(cls, "rb_is_builtin_type_data", so_is_builtin_type_data, 1);
  rb_define_method(cls, "rb_to_int", object_spec_rb_to_int, 1);
  rb_define_method(cls, "rb_equal", object_spec_rb_equal, 2);
  rb_define_method(cls, "rb_class_inherited_p", object_spec_rb_class_inherited_p, 2);
  rb_define_method(cls, "rb_obj_instance_eval", object_spec_rb_obj_instance_eval, 1);
  rb_define_method(cls, "rb_iv_get", object_spec_rb_iv_get, 2);
  rb_define_method(cls, "rb_iv_set", object_spec_rb_iv_set, 3);
  rb_define_method(cls, "rb_ivar_count", object_spec_rb_ivar_count, 1);
  rb_define_method(cls, "rb_ivar_get", object_spec_rb_ivar_get, 2);
  rb_define_method(cls, "rb_ivar_set", object_spec_rb_ivar_set, 3);
  rb_define_method(cls, "rb_ivar_defined", object_spec_rb_ivar_defined, 2);
  rb_define_method(cls, "rb_copy_generic_ivar", object_spec_rb_copy_generic_ivar, 2);
  rb_define_method(cls, "rb_free_generic_ivar", object_spec_rb_free_generic_ivar, 1);
  rb_define_method(cls, "rb_define_alloc_func", object_spec_rb_define_alloc_func, 1);
  rb_define_method(cls, "rb_undef_alloc_func", object_spec_rb_undef_alloc_func, 1);
  rb_define_method(cls, "speced_allocator?", object_spec_speced_allocator_p, 1);
  rb_define_method(cls, "custom_alloc_func?", object_spec_custom_alloc_func_p, 1);
  rb_define_method(cls, "not_implemented_method", rb_f_notimplement, -1);
  rb_define_method(cls, "rb_ivar_foreach", object_spec_rb_ivar_foreach, 1);

  cls = rb_define_class("CApiObjectRedefinitionSpecs", rb_cObject);
  rb_define_method(cls, "frozen?", object_spec_redefine_frozen, 0);
}

#ifdef __cplusplus
}
#endif
