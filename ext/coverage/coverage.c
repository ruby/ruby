#include "ruby.h"

VALUE rb_mCoverage;

void
Init_coverage(void)
{
    rb_enable_coverages();
    rb_mCoverage = rb_define_module("Coverage");
    rb_define_module_function(rb_mCoverage, "result", rb_get_coverages, 0);
}
