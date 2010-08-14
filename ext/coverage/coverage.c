/************************************************

  coverage.c -

  $Author: $

  Copyright (c) 2008 Yusuke Endoh

************************************************/

#include "ruby.h"
#include "vm_core.h"

/*
 * call-seq:
 *    Coverage.start  => nil
 *
 * Enables coverage measurement.
 */
static VALUE
rb_coverage_start(VALUE klass)
{
    if (!RTEST(rb_get_coverages())) {
	VALUE coverages = rb_hash_new();
	RBASIC(coverages)->klass = 0;
	rb_set_coverages(coverages);
    }
    return Qnil;
}

static int
coverage_result_i(st_data_t key, st_data_t val, st_data_t dummy)
{
    VALUE coverage = (VALUE)val;
    RBASIC(coverage)->klass = rb_cArray;
    rb_ary_freeze(coverage);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     Coverage.result  => hash
 *
 * Returns a hash that contains filename as key and coverage array as value
 * and disables coverage measurement.
 */
static VALUE
rb_coverage_result(VALUE klass)
{
    VALUE coverages = rb_get_coverages();
    if (!RTEST(coverages)) {
	rb_raise(rb_eRuntimeError, "coverage measurement is not enabled");
    }
    RBASIC(coverages)->klass = rb_cHash;
    st_foreach(RHASH_TBL(coverages), coverage_result_i, 0);
    rb_hash_freeze(coverages);
    rb_reset_coverages();
    return coverages;
}

/* Coverage provides coverage measurement feature for Ruby.
 * This feature is experimental, so these APIs may be changed in future.
 *
 * = Usage
 *
 * (1) require "coverage.so"
 * (2) do Coverage.start
 * (3) require or load Ruby source file
 * (4) Coverage.result will return a hash that contains filename as key and
 *     coverage array as value.
 *
 * = Example
 *
 *   [foo.rb]
 *   s = 0
 *   10.times do |x|
 *     s += x
 *   end
 *
 *   if s == 45
 *     p :ok
 *   else
 *     p :ng
 *   end
 *   [EOF]
 *
 *   require "coverage.so"
 *   Coverage.start
 *   require "foo.rb"
 *   p Coverage.result  #=> {"foo.rb"=>[1, 1, 10, nil, nil, 1, 1, nil, 0, nil]}
 */
void
Init_coverage(void)
{
    VALUE rb_mCoverage = rb_define_module("Coverage");
    rb_define_module_function(rb_mCoverage, "start", rb_coverage_start, 0);
    rb_define_module_function(rb_mCoverage, "result", rb_coverage_result, 0);
}
