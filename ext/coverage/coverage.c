/************************************************

  coverage.c -

  $Author: $

  Copyright (c) 2008 Yusuke Endoh

************************************************/

#include "ruby.h"
#include "vm_core.h"

static int current_mode;

/*
 * call-seq:
 *    Coverage.start  => nil
 *
 * Enables coverage measurement.
 */
static VALUE
rb_coverage_start(int argc, VALUE *argv, VALUE klass)
{
    VALUE coverages, opt;
    int mode, experimental_mode_enabled = 1;

    {
        const char *e = getenv("COVERAGE_EXPERIMENTAL_MODE");
        if (!e || !*e) experimental_mode_enabled = 0;
    }

    if (!experimental_mode_enabled)
	rb_error_arity(argc, 0, 0);
    rb_scan_args(argc, argv, "01", &opt);

    if (argc == 0) {
	mode = 0; /* compatible mode */
    }
    else if (opt == ID2SYM(rb_intern("all"))) {
	mode = COVERAGE_TARGET_LINES | COVERAGE_TARGET_BRANCHES | COVERAGE_TARGET_METHODS;
    }
    else {
	mode = 0;
	if (RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("lines")))))
	    mode |= COVERAGE_TARGET_LINES;
	if (RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("branches")))))
	    mode |= COVERAGE_TARGET_BRANCHES;
	if (RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("methods")))))
	    mode |= COVERAGE_TARGET_METHODS;
	if (mode == 0) {
	    rb_raise(rb_eRuntimeError, "no measuring target is specified");
	}
    }

    coverages = rb_get_coverages();
    if (!RTEST(coverages)) {
	coverages = rb_hash_new();
	rb_obj_hide(coverages);
	current_mode = mode;
	if (mode == 0) mode = COVERAGE_TARGET_LINES;
	rb_set_coverages(coverages, mode);
    }
    else if (current_mode != mode) {
	rb_raise(rb_eRuntimeError, "cannot change the measuring target during coverage measurement");
    }
    return Qnil;
}

static int
coverage_peek_result_i(st_data_t key, st_data_t val, st_data_t h)
{
    VALUE path = (VALUE)key;
    VALUE coverage = (VALUE)val;
    VALUE coverages = (VALUE)h;
    if (current_mode == 0) {
	/* compatible mode */
	VALUE lines = rb_ary_dup(RARRAY_AREF(coverage, COVERAGE_INDEX_LINES));
	rb_ary_freeze(lines);
	coverage = lines;
    }
    else {
	VALUE h = rb_hash_new();
	VALUE lines = RARRAY_AREF(coverage, COVERAGE_INDEX_LINES);
	VALUE branches = RARRAY_AREF(coverage, COVERAGE_INDEX_BRANCHES);
	VALUE methods = RARRAY_AREF(coverage, COVERAGE_INDEX_METHODS);

	if (lines) {
	    lines = rb_ary_dup(lines);
	    rb_ary_freeze(lines);
	    rb_hash_aset(h, ID2SYM(rb_intern("lines")), lines);
	}

	if (branches) {
	    rb_hash_aset(h, ID2SYM(rb_intern("branches")), branches);
	}

	if (methods) {
	    rb_hash_aset(h, ID2SYM(rb_intern("methods")), methods);
	}

	rb_hash_freeze(h);
	coverage = h;
    }

    rb_hash_aset(coverages, path, coverage);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     Coverage.peek_result  => hash
 *
 * Returns a hash that contains filename as key and coverage array as value.
 *
 *   {
 *     "file.rb" => [1, 2, nil],
 *     ...
 *   }
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

/*
 *  call-seq:
 *     Coverage.running?  => bool
 *
 * Returns true if coverage stats are currently being collected (after
 * Coverage.start call, but before Coverage.result call)
 */
static VALUE
rb_coverage_running(VALUE klass)
{
    VALUE coverages = rb_get_coverages();
    return RTEST(coverages) ? Qtrue : Qfalse;
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
    rb_define_module_function(rb_mCoverage, "start", rb_coverage_start, -1);
    rb_define_module_function(rb_mCoverage, "result", rb_coverage_result, 0);
    rb_define_module_function(rb_mCoverage, "peek_result", rb_coverage_peek_result, 0);
    rb_define_module_function(rb_mCoverage, "running?", rb_coverage_running, 0);
}
