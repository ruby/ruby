#include "ruby/ruby.h"

static VALUE
arith_seq_s_beg_len_step(VALUE mod, VALUE obj, VALUE len, VALUE err)
{
  VALUE r;
  rb_len_t beg, len2, step;

  r = rb_arithmetic_sequence_beg_len_step(obj, &beg, &len2, &step, NUM2LEN(len), NUM2INT(err));

  return rb_ary_new_from_args(4, r, LEN2NUM(beg), LEN2NUM(len2), LEN2NUM(step));
}

void
Init_beg_len_step(void)
{
    VALUE cArithSeq = rb_path2class("Enumerator::ArithmeticSequence");
    rb_define_singleton_method(cArithSeq, "__beg_len_step__", arith_seq_s_beg_len_step, 3);
}
