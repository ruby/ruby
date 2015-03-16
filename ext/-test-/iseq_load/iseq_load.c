#include <ruby.h>

VALUE rb_iseq_load(VALUE data, VALUE parent, VALUE opt);

static VALUE
iseq_load(int argc, VALUE *argv, VALUE self)
{
    VALUE data, opt = Qnil;

    rb_scan_args(argc, argv, "11", &data, &opt);

    return rb_iseq_load(data, 0, opt);
}

void
Init_iseq_load(void)
{
    VALUE rb_cISeq = rb_path2class("RubyVM::InstructionSequence");

    rb_define_singleton_method(rb_cISeq, "iseq_load", iseq_load, -1);
}
