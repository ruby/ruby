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
Init_tkutil()
{
    VALUE mTK = rb_define_module("TkUtil");
    rb_define_singleton_method(mTK, "eval_cmd", tk_eval_cmd, -1);
}
