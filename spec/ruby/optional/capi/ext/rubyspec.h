#ifndef RUBYSPEC_H
#define RUBYSPEC_H

/* Define convenience macros similar to the mspec
 * guards to assist with version incompatibilities. */

#include <ruby.h>
#ifdef HAVE_RUBY_VERSION_H
# include <ruby/version.h>
#else
# include <version.h>
#endif

#ifndef RUBY_VERSION_MAJOR
#define RUBY_VERSION_MAJOR RUBY_API_VERSION_MAJOR
#define RUBY_VERSION_MINOR RUBY_API_VERSION_MINOR
#define RUBY_VERSION_TEENY RUBY_API_VERSION_TEENY
#endif

#define RUBY_VERSION_BEFORE(major,minor,teeny) \
  ((RUBY_VERSION_MAJOR < (major)) || \
   (RUBY_VERSION_MAJOR == (major) && RUBY_VERSION_MINOR < (minor)) || \
   (RUBY_VERSION_MAJOR == (major) && RUBY_VERSION_MINOR == (minor) && RUBY_VERSION_TEENY < (teeny)))

#if RUBY_VERSION_MAJOR > 3 || (RUBY_VERSION_MAJOR == 3 && RUBY_VERSION_MINOR >= 1)
#define RUBY_VERSION_IS_3_1
#endif

#if RUBY_VERSION_MAJOR > 3 || (RUBY_VERSION_MAJOR == 3 && RUBY_VERSION_MINOR >= 0)
#define RUBY_VERSION_IS_3_0
#endif

#if RUBY_VERSION_MAJOR > 2 || (RUBY_VERSION_MAJOR == 2 && RUBY_VERSION_MINOR >= 7)
#define RUBY_VERSION_IS_2_7
#endif

#if RUBY_VERSION_MAJOR > 2 || (RUBY_VERSION_MAJOR == 2 && RUBY_VERSION_MINOR >= 6)
#define RUBY_VERSION_IS_2_6
#endif

#if defined(__cplusplus) && !defined(RUBY_VERSION_IS_2_7)
/* Ruby < 2.7 needs this to let these function with callbacks and compile in C++ code */
#define rb_define_method(mod, name, func, argc) rb_define_method(mod, name, RUBY_METHOD_FUNC(func), argc)
#define rb_define_protected_method(mod, name, func, argc) rb_define_protected_method(mod, name, RUBY_METHOD_FUNC(func), argc)
#define rb_define_private_method(mod, name, func, argc) rb_define_private_method(mod, name, RUBY_METHOD_FUNC(func), argc)
#define rb_define_singleton_method(mod, name, func, argc) rb_define_singleton_method(mod, name, RUBY_METHOD_FUNC(func), argc)
#define rb_define_module_function(mod, name, func, argc) rb_define_module_function(mod, name, RUBY_METHOD_FUNC(func), argc)
#define rb_define_global_function(name, func, argc) rb_define_global_function(name, RUBY_METHOD_FUNC(func), argc)
#define rb_hash_foreach(hash, func, farg) rb_hash_foreach(hash, (int (*)(...))func, farg)
#define st_foreach(tab, func, arg) st_foreach(tab, (int (*)(...))func, arg)
#define rb_block_call(object, name, args_count, args, block_call_func, data) rb_block_call(object, name, args_count, args, RUBY_METHOD_FUNC(block_call_func), data)
#define rb_ensure(b_proc, data1, e_proc, data2) rb_ensure(RUBY_METHOD_FUNC(b_proc), data1, RUBY_METHOD_FUNC(e_proc), data2)
#define rb_rescue(b_proc, data1, e_proc, data2) rb_rescue(RUBY_METHOD_FUNC(b_proc), data1, RUBY_METHOD_FUNC(e_proc), data2)
#define rb_rescue2(b_proc, data1, e_proc, data2, ...) rb_rescue2(RUBY_METHOD_FUNC(b_proc), data1, RUBY_METHOD_FUNC(e_proc), data2, __VA_ARGS__)
#define rb_catch(tag, func, data) rb_catch(tag, RUBY_METHOD_FUNC(func), data)
#define rb_catch_obj(tag, func, data) rb_catch_obj(tag, RUBY_METHOD_FUNC(func), data)
#define rb_proc_new(fn, arg) rb_proc_new(RUBY_METHOD_FUNC(fn), arg)
#define rb_fiber_new(fn, arg) rb_fiber_new(RUBY_METHOD_FUNC(fn), arg)
#define rb_thread_create(fn, arg) rb_thread_create(RUBY_METHOD_FUNC(fn), arg)
#define rb_define_hooked_variable(name, var, getter, setter) rb_define_hooked_variable(name, var, RUBY_METHOD_FUNC(getter), (void (*)(...))setter)
#endif

#endif
