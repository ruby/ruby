#include "ruby.h"

static VALUE
with_funcall2(int argc, VALUE *argv, VALUE self)
{
    return rb_funcallv(self, rb_intern("target"), argc, argv);
}

static VALUE
with_funcall_passing_block(int argc, VALUE *argv, VALUE self)
{
    return rb_funcall_passing_block(self, rb_intern("target"), argc, argv);
}

static VALUE
with_funcall_passing_block_kw(int argc, VALUE *argv, VALUE self)
{
    return rb_funcall_passing_block_kw(self, rb_intern("target"), argc-1, argv+1, FIX2INT(argv[0]));
}

static VALUE
with_funcallv_public_kw(int argc, VALUE *argv, VALUE self)
{
    return rb_funcallv_public_kw(argv[0], SYM2ID(argv[1]), argc-3, argv+3, FIX2INT(argv[2]));
}

static VALUE
with_yield_splat_kw(int argc, VALUE *argv, VALUE self)
{
    return rb_yield_splat_kw(argv[1], FIX2INT(argv[0]));
}

static VALUE
extra_args_name(VALUE self)
{
    /*
     * at least clang 5.x gets tripped by the extra 0 arg
     * [ruby-core:85266] [Bug #14425]
     */
    return rb_funcall(self, rb_intern("name"), 0, 0);
}

void
Init_funcall(void)
{
    VALUE cTestFuncall = rb_path2class("TestFuncall");
    VALUE cRelay = rb_define_module_under(cTestFuncall, "Relay");

    rb_define_singleton_method(cRelay,
			       "with_funcall2",
			       with_funcall2,
			       -1);
    rb_define_singleton_method(cRelay,
                               "with_funcall_passing_block_kw",
                               with_funcall_passing_block_kw,
                               -1);
    rb_define_singleton_method(cRelay,
			       "with_funcall_passing_block",
			       with_funcall_passing_block,
			       -1);
    rb_define_singleton_method(cRelay,
                               "with_funcallv_public_kw",
                               with_funcallv_public_kw,
                               -1);
    rb_define_singleton_method(cRelay,
                               "with_yield_splat_kw",
                               with_yield_splat_kw,
                               -1);
    rb_define_singleton_method(cTestFuncall, "extra_args_name",
                                extra_args_name,
                                0);
}
