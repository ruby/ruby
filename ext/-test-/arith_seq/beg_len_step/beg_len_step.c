#include "ruby/ruby.h"

static VALUE
arith_seq_s_beg_len_step(VALUE mod, VALUE obj, VALUE len, VALUE err)
{
  VALUE r;
  long beg, len2, step;

  r = rb_arithmetic_sequence_beg_len_step(obj, &beg, &len2, &step, NUM2LONG(len), NUM2INT(err));

  return rb_ary_new_from_args(4, r, LONG2NUM(beg), LONG2NUM(len2), LONG2NUM(step));
}

void
Init_beg_len_step(void)
{
    VALUE cArithSeq = rb_path2class("Enumerator::ArithmeticSequence");
    rb_define_singleton_method(cArithSeq, "__beg_len_step__", arith_seq_s_beg_len_step, 3);
}
