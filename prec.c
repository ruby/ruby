/************************************************

  ruby.h -

  $Author$
  $Date$
  created at: Tue Jan 26 02:40:41 1999

  Copyright (C) 1993-1999 Yukihiro Matsumoto

*************************************************/

#include "ruby.h"

VALUE rb_mPrecision;

static ID prc_pr, prc_if;

static VALUE
prec_prec(x, klass)
    VALUE x, klass;
{
    return rb_funcall(klass, prc_if, 1, x);
}

static VALUE
prec_prec_i(x)
    VALUE x;
{
    VALUE klass = rb_cInteger;

    return rb_funcall(x, prc_pr, 1, klass);
}

static VALUE
prec_prec_f(x)
    VALUE x;
{
    VALUE klass = rb_cFloat;

    return rb_funcall(x, prc_pr, 1, klass);
}

static VALUE
prec_induced_from(module, x)
    
{
    rb_raise(rb_eTypeError, "undefined conversion from %s into %s",
            rb_class2name(CLASS_OF(x)), rb_class2name(module));
}

static VALUE
prec_append_features(module, include)
    VALUE module, include;
{
    switch (TYPE(include)) {
      case T_CLASS:
      case T_MODULE:
       break;
      default:
       Check_Type(include, T_CLASS);
       break;
    }
    rb_include_module(include, module);
    rb_define_singleton_method(include, "induced_from", prec_induced_from, 1);
    return module;
}


void
Init_Precision()
{
    rb_mPrecision = rb_define_module("Precision");
    rb_define_singleton_method(rb_mPrecision, "append_features", prec_append_features, 1);
    rb_define_method(rb_mPrecision, "prec", prec_prec, 1);
    rb_define_method(rb_mPrecision, "prec_i", prec_prec_i, 0);
    rb_define_method(rb_mPrecision, "prec_f", prec_prec_f, 0);

    prc_pr = rb_intern("prec");
    prc_if = rb_intern("induced_from");
}
