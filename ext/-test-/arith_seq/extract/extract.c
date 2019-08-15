#include "ruby/ruby.h"

static VALUE
arith_seq_s_extract(VALUE mod, VALUE obj)
{
  rb_arithmetic_sequence_components_t x;
  VALUE ret;
  int r;

  r = rb_arithmetic_sequence_extract(obj, &x);

  ret = rb_ary_new2(5);
  rb_ary_store(ret, 0, r ? x.begin : Qnil);
  rb_ary_store(ret, 1, r ? x.end   : Qnil);
  rb_ary_store(ret, 2, r ? x.step  : Qnil);
  rb_ary_store(ret, 3, r ? INT2FIX(x.exclude_end) : Qnil);
  rb_ary_store(ret, 4, INT2FIX(r));

  return ret;
}

void
Init_extract(void)
{
    VALUE cArithSeq = rb_path2class("Enumerator::ArithmeticSequence");
    rb_define_singleton_method(cArithSeq, "__extract__", arith_seq_s_extract, 1);
}
