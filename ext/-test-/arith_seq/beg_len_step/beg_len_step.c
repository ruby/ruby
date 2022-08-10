#include "ruby/ruby.h"

static VALUE
arith_seq_s_beg_len_step(VALUE mod, VALUE obj, VALUE len, VALUE err)
{
  VALUE r;
  long begp, lenp, stepp;

  r = rb_arithmetic_sequence_beg_len_step(obj, &begp, &lenp, &stepp, NUM2LONG(len), NUM2INT(err));

  return rb_ary_new_from_args(4, r, LONG2NUM(begp), LONG2NUM(lenp), LONG2NUM(stepp));
}

void
Init_beg_len_step(void)
{
    VALUE cArithSeq = rb_path2class("Enumerator::ArithmeticSequence");
    rb_define_singleton_method(cArithSeq, "__beg_len_step__", arith_seq_s_beg_len_step, 3);
}
