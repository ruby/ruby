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


/*
 *  call-seq:
 *   num.prec(klass)   => a_klass
 *
 *  Converts _self_ into an instance of _klass_. By default,
 *  +prec+ invokes 
 *
 *     klass.induced_from(num)
 *
 *  and returns its value. So, if <code>klass.induced_from</code>
 *  doesn't return an instance of _klass_, it will be necessary
 *  to reimplement +prec+.
 */

static VALUE
prec_prec(x, klass)
    VALUE x, klass;
{
    return rb_funcall(klass, prc_if, 1, x);
}

/*
 *  call-seq:
 *    num.prec_i  =>  Integer
 *
 *  Returns an +Integer+ converted from _num_. It is equivalent 
 *  to <code>prec(Integer)</code>.
 */

static VALUE
prec_prec_i(x)
    VALUE x;
{
    VALUE klass = rb_cInteger;

    return rb_funcall(x, prc_pr, 1, klass);
}

/*
 *  call-seq:
 *    num.prec_f  =>  Float
 *
 *  Returns a +Float+ converted from _num_. It is equivalent 
 *  to <code>prec(Float)</code>.
 */

static VALUE
prec_prec_f(x)
    VALUE x;
{
    VALUE klass = rb_cFloat;

    return rb_funcall(x, prc_pr, 1, klass);
}

/*
 * call-seq:
 *   Mod.induced_from(number)  =>  a_mod
 * 
 * Creates an instance of mod from. This method is overridden
 * by concrete +Numeric+ classes, so that (for example)
 *
 *   Fixnum.induced_from(9.9)   #=>  9
 *
 * Note that a use of +prec+ in a redefinition may cause
 * an infinite loop.
 */

static VALUE
prec_induced_from(module, x)
    VALUE module, x;
{
    rb_raise(rb_eTypeError, "undefined conversion from %s into %s",
            rb_obj_classname(x), rb_class2name(module));
    return Qnil;		/* not reached */
}

/*
 * call_seq:
 *   included
 *
 * When the +Precision+ module is mixed-in to a class, this +included+
 * method is used to add our default +induced_from+ implementation
 * to the host class.
 */

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

/*
 * Precision is a mixin for concrete numeric classes with
 * precision.  Here, `precision' means the fineness of approximation
 * of a real number, so, this module should not be included into
 * anything which is not a subset of Real (so it should not be
 * included in classes such as +Complex+ or +Matrix+).
*/

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
