/**********************************************************************

  prec.c -

  $Author$
  $Date$
  created at: Tue Jan 26 02:40:41 2000

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

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
    VALUE module, x;
{
    rb_raise(rb_eTypeError, "undefined conversion from %s into %s",
            rb_obj_classname(x), rb_class2name(module));
    return Qnil;		/* not reached */
}

static VALUE
prec_included(module, include)
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
    rb_define_singleton_method(include, "induced_from", prec_induced_from, 1);
    return module;
}


void
Init_Precision()
{
    rb_mPrecision = rb_define_module("Precision");
    rb_define_singleton_method(rb_mPrecision, "included", prec_included, 1);
    rb_define_method(rb_mPrecision, "prec", prec_prec, 1);
    rb_define_method(rb_mPrecision, "prec_i", prec_prec_i, 0);
    rb_define_method(rb_mPrecision, "prec_f", prec_prec_f, 0);

    prc_pr = rb_intern("prec");
    prc_if = rb_intern("induced_from");
}
