#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE range_spec_rb_range_new(int argc, VALUE* argv, VALUE self) {
  int exclude_end = 0;
  if (argc == 3) {
    exclude_end = RTEST(argv[2]);
  }
  return rb_range_new(argv[0], argv[1], exclude_end);
}

VALUE range_spec_rb_range_values(VALUE self, VALUE range) {
  VALUE beg;
  VALUE end;
  int excl;
  VALUE ary = rb_ary_new();
  rb_range_values(range, &beg, &end, &excl);
  rb_ary_store(ary, 0, beg);
  rb_ary_store(ary, 1, end);
  rb_ary_store(ary, 2, excl ? Qtrue : Qfalse);
  return ary;
}

VALUE range_spec_rb_range_beg_len(VALUE self, VALUE range, VALUE begpv, VALUE lenpv, VALUE lenv, VALUE errv) {
  long begp = FIX2LONG(begpv);
  long lenp = FIX2LONG(lenpv);
  long len = FIX2LONG(lenv);
  int err = FIX2INT(errv);
  VALUE ary = rb_ary_new();
  VALUE res = rb_range_beg_len(range, &begp, &lenp, len, err);
  rb_ary_store(ary, 0, LONG2FIX(begp));
  rb_ary_store(ary, 1, LONG2FIX(lenp));
  rb_ary_store(ary, 2, res);
  return ary;
}

VALUE range_spec_rb_arithmetic_sequence_extract(VALUE self, VALUE object) {
  VALUE ary = rb_ary_new();
  rb_arithmetic_sequence_components_t components;

  int status = rb_arithmetic_sequence_extract(object, &components);

  if (!status) {
      rb_ary_store(ary, 0, LONG2FIX(status));
      return ary;
  }

  rb_ary_store(ary, 0, LONG2FIX(status));
  rb_ary_store(ary, 1, components.begin);
  rb_ary_store(ary, 2, components.end);
  rb_ary_store(ary, 3, components.step);
  rb_ary_store(ary, 4, components.exclude_end ? Qtrue : Qfalse);
  return ary;
}

VALUE range_spec_rb_arithmetic_sequence_beg_len_step(VALUE self, VALUE aseq, VALUE lenv, VALUE errv) {
  long begp, lenp, stepp;

  long len = FIX2LONG(lenv);
  int err = FIX2INT(errv);

  VALUE success = rb_arithmetic_sequence_beg_len_step(aseq, &begp, &lenp, &stepp, len, err);

  VALUE ary = rb_ary_new();
  rb_ary_store(ary, 0, success);
  rb_ary_store(ary, 1, LONG2FIX(begp));
  rb_ary_store(ary, 2, LONG2FIX(lenp));
  rb_ary_store(ary, 3, LONG2FIX(stepp));

  return ary;
}

void Init_range_spec(void) {
  VALUE cls = rb_define_class("CApiRangeSpecs", rb_cObject);
  rb_define_method(cls, "rb_range_new", range_spec_rb_range_new, -1);
  rb_define_method(cls, "rb_range_values", range_spec_rb_range_values, 1);
  rb_define_method(cls, "rb_range_beg_len", range_spec_rb_range_beg_len, 5);
  rb_define_method(cls, "rb_arithmetic_sequence_extract", range_spec_rb_arithmetic_sequence_extract, 1);
  rb_define_method(cls, "rb_arithmetic_sequence_beg_len_step", range_spec_rb_arithmetic_sequence_beg_len_step, 3);
}

#ifdef __cplusplus
}
#endif
