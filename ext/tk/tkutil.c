/************************************************

  tk.c -

  $Author$
  $Date$
  created at: Fri Nov  3 00:47:54 JST 1995

************************************************/

#include "ruby.h"

static VALUE
tk_eval_cmd(argc, argv)
    int argc;
    VALUE argv[];
{
    VALUE cmd, rest;

    rb_scan_args(argc, argv, "1*", &cmd, &rest);
    return rb_eval_cmd(cmd, rest);
}

static VALUE
tk_s_new(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE obj = rb_obj_alloc(class);

    rb_funcall2(obj, rb_intern("initialize"), argc, argv);
    if (rb_iterator_p()) rb_obj_instance_eval(0, 0, obj);
    return obj;
}

Init_tkutil()
{
    VALUE mTK = rb_define_module("TkUtil");
    VALUE cTK = rb_define_class("TkKernel", rb_cObject);

    rb_define_singleton_method(mTK, "eval_cmd", tk_eval_cmd, -1);

    rb_define_singleton_method(cTK, "new", tk_s_new, -1);
}
