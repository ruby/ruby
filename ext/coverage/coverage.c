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
    VALUE coverages = rb_get_coverages();
    if (!RTEST(coverages)) {
	coverages = rb_hash_new();
	rb_obj_hide(coverages);
	rb_set_coverages(coverages);
    }
    return Qnil;
}

static int
coverage_peek_result_i(st_data_t key, st_data_t val, st_data_t h)
{
    VALUE path = (VALUE)key;
    VALUE coverage = (VALUE)val;
    VALUE coverages = (VALUE)h;
    coverage = rb_ary_dup(coverage);
    rb_ary_freeze(coverage);
    rb_hash_aset(coverages, path, coverage);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     Coverage.peek_result  => hash
 *
 * Returns a hash that contains filename as key and coverage array as value.
 */
static VALUE
rb_coverage_peek_result(VALUE klass)
{
    VALUE coverages = rb_get_coverages();
    VALUE ncoverages = rb_hash_new();
    if (!RTEST(coverages)) {
	rb_raise(rb_eRuntimeError, "coverage measurement is not enabled");
    }
    st_foreach(RHASH_TBL(coverages), coverage_peek_result_i, ncoverages);
    rb_hash_freeze(ncoverages);
    return ncoverages;
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
    VALUE ncoverages = rb_coverage_peek_result(klass);
    rb_reset_coverages();
    return ncoverages;
}

/* Coverage provides coverage measurement feature for Ruby.
 * This feature is experimental, so these APIs may be changed in future.
 *
 * = Usage
 *
 * 1. require "coverage"
 * 2. do Coverage.start
 * 3. require or load Ruby source file
 * 4. Coverage.result will return a hash that contains filename as key and
 *    coverage array as value. A coverage array gives, for each line, the
 *    number of line execution by the interpreter. A +nil+ value means
 *    coverage is disabled for this line (lines like +else+ and +end+).
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
 *   require "coverage"
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
    rb_define_module_function(rb_mCoverage, "peek_result", rb_coverage_peek_result, 0);
}
