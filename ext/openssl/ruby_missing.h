/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2003  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_RUBY_MISSING_H_)
#define _OSS_RUBY_MISSING_H_

#if !defined(StringValue)
#  define StringValue(v) \
    if (TYPE(v) != T_STRING) v = rb_str_to_str(v)
#endif

#if !defined(StringValuePtr)
#  define StringValuePtr(v) \
    RSTRING((TYPE(v) == T_STRING) ? (v) : rb_str_to_str(v))->ptr
#endif

#if !defined(SafeStringValue)
#  define SafeStringValue(v) do {\
    StringValue(v);\
    rb_check_safe_str(v);\
} while (0)
#endif

#if RUBY_VERSION_CODE < 180
#  define rb_cstr_to_inum(a,b,c) \
    rb_cstr2inum(a,b)
#  define rb_check_frozen(obj) \
    if (OBJ_FROZEN(obj)) rb_error_frozen(rb_obj_classname(obj))
#  define rb_obj_classname(obj) \
    rb_class2name(CLASS_OF(obj))
#endif

#if HAVE_RB_DEFINE_ALLOC_FUNC
#  define DEFINE_ALLOC_WRAPPER(func)
#else
#  define DEFINE_ALLOC_WRAPPER(func)			\
    static VALUE					\
    func##_wrapper(int argc, VALUE *argv, VALUE klass)  \
    {							\
	VALUE obj;					\
							\
	obj = func(klass);				\
							\
	rb_obj_call_init(obj, argc, argv);		\
							\
	return obj;					\
    }
#  define rb_define_alloc_func(klass, func) \
    rb_define_singleton_method(klass, "new", func##_wrapper, -1)
#endif

#if RUBY_VERSION_CODE >= 180
#  if !defined(HAVE_RB_OBJ_INIT_COPY)
#    define rb_define_copy_func(klass, func) \
	rb_define_method(klass, "copy_object", func, 1)
#  else
#    define rb_define_copy_func(klass, func) \
	rb_define_method(klass, "initialize_copy", func, 1)
#  endif
#endif

#endif /* _OSS_RUBY_MISSING_H_ */

