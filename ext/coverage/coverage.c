/************************************************

  coverage.c -

  $Author: $

  Copyright (c) 2008 Yusuke Endoh

************************************************/

#include "ruby.h"
#include "vm_core.h"
#include "gc.h"

static int current_mode;
static VALUE me2counter = Qnil;

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
    int mode;

    rb_scan_args(argc, argv, "01", &opt);

    if (argc == 0) {
	mode = 0; /* compatible mode */
    }
    else if (opt == ID2SYM(rb_intern("all"))) {
	mode = COVERAGE_TARGET_LINES | COVERAGE_TARGET_BRANCHES | COVERAGE_TARGET_METHODS;
    }
    else {
	mode = 0;
	opt = rb_convert_type(opt, T_HASH, "Hash", "to_hash");

	if (RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("lines")))))
	    mode |= COVERAGE_TARGET_LINES;
	if (RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("branches")))))
	    mode |= COVERAGE_TARGET_BRANCHES;
	if (RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("methods")))))
	    mode |= COVERAGE_TARGET_METHODS;
        if (RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("oneshot_lines"))))) {
            if (mode & COVERAGE_TARGET_LINES)
                rb_raise(rb_eRuntimeError, "cannot enable lines and oneshot_lines simultaneously");
            mode |= COVERAGE_TARGET_LINES;
            mode |= COVERAGE_TARGET_ONESHOT_LINES;
        }
    }

    if (mode & COVERAGE_TARGET_METHODS) {
        me2counter = rb_ident_hash_new();
    }
    else {
	me2counter = Qnil;
    }

    coverages = rb_get_coverages();
    if (!RTEST(coverages)) {
	coverages = rb_hash_new();
	rb_obj_hide(coverages);
	current_mode = mode;
	if (mode == 0) mode = COVERAGE_TARGET_LINES;
	rb_set_coverages(coverages, mode, me2counter);
    }
    else if (current_mode != mode) {
	rb_raise(rb_eRuntimeError, "cannot change the measuring target during coverage measurement");
    }
    return Qnil;
}

static VALUE
branch_coverage(VALUE branches)
{
    VALUE ret = rb_hash_new();
    VALUE structure = rb_ary_dup(RARRAY_AREF(branches, 0));
    VALUE counters = rb_ary_dup(RARRAY_AREF(branches, 1));
    int i, j;
    long id = 0;

    for (i = 0; i < RARRAY_LEN(structure); i++) {
	VALUE branches = RARRAY_AREF(structure, i);
	VALUE base_type = RARRAY_AREF(branches, 0);
	VALUE base_first_lineno = RARRAY_AREF(branches, 1);
	VALUE base_first_column = RARRAY_AREF(branches, 2);
	VALUE base_last_lineno = RARRAY_AREF(branches, 3);
	VALUE base_last_column = RARRAY_AREF(branches, 4);
	VALUE children = rb_hash_new();
	rb_hash_aset(ret, rb_ary_new_from_args(6, base_type, LONG2FIX(id++), base_first_lineno, base_first_column, base_last_lineno, base_last_column), children);
	for (j = 5; j < RARRAY_LEN(branches); j += 6) {
	    VALUE target_label = RARRAY_AREF(branches, j);
	    VALUE target_first_lineno = RARRAY_AREF(branches, j + 1);
	    VALUE target_first_column = RARRAY_AREF(branches, j + 2);
	    VALUE target_last_lineno = RARRAY_AREF(branches, j + 3);
	    VALUE target_last_column = RARRAY_AREF(branches, j + 4);
	    int idx = FIX2INT(RARRAY_AREF(branches, j + 5));
	    rb_hash_aset(children, rb_ary_new_from_args(6, target_label, LONG2FIX(id++), target_first_lineno, target_first_column, target_last_lineno, target_last_column), RARRAY_AREF(counters, idx));
	}
    }

    return ret;
}

static int
method_coverage_i(void *vstart, void *vend, size_t stride, void *data)
{
    /*
     * ObjectSpace.each_object(Module){|mod|
     *   mod.instance_methods.each{|mid|
     *     m = mod.instance_method(mid)
     *     if loc = m.source_location
     *       p [m.name, loc, $g_method_cov_counts[m]]
     *     end
     *   }
     * }
     */
    VALUE ncoverages = *(VALUE*)data, v;

    for (v = (VALUE)vstart; v != (VALUE)vend; v += stride) {
	if (RB_TYPE_P(v, T_IMEMO) && imemo_type(v) == imemo_ment) {
	    const rb_method_entry_t *me = (rb_method_entry_t *) v;
	    VALUE path, first_lineno, first_column, last_lineno, last_column;
	    VALUE data[5], ncoverage, methods;
	    VALUE methods_id = ID2SYM(rb_intern("methods"));
	    VALUE klass;
	    const rb_method_entry_t *me2 = rb_resolve_me_location(me, data);
	    if (me != me2) continue;
	    klass = me->owner;
	    if (RB_TYPE_P(klass, T_ICLASS)) {
		rb_bug("T_ICLASS");
	    }
	    path = data[0];
	    first_lineno = data[1];
	    first_column = data[2];
	    last_lineno = data[3];
	    last_column = data[4];
	    if (FIX2LONG(first_lineno) <= 0) continue;
	    ncoverage = rb_hash_aref(ncoverages, path);
	    if (NIL_P(ncoverage)) continue;
	    methods = rb_hash_aref(ncoverage, methods_id);

	    {
		VALUE method_id = ID2SYM(me->def->original_id);
		VALUE rcount = rb_hash_aref(me2counter, (VALUE) me);
		VALUE key = rb_ary_new_from_args(6, klass, method_id, first_lineno, first_column, last_lineno, last_column);
		VALUE rcount2 = rb_hash_aref(methods, key);

		if (NIL_P(rcount)) rcount = LONG2FIX(0);
		if (NIL_P(rcount2)) rcount2 = LONG2FIX(0);
		if (!POSFIXABLE(FIX2LONG(rcount) + FIX2LONG(rcount2))) {
		    rcount = LONG2FIX(FIXNUM_MAX);
		}
		else {
		    rcount = LONG2FIX(FIX2LONG(rcount) + FIX2LONG(rcount2));
		}
		rb_hash_aset(methods, key, rcount);
	    }
	}
    }
    return 0;
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

	if (current_mode & COVERAGE_TARGET_LINES) {
	    VALUE lines = RARRAY_AREF(coverage, COVERAGE_INDEX_LINES);
            const char *kw = (current_mode & COVERAGE_TARGET_ONESHOT_LINES) ? "oneshot_lines" : "lines";
	    lines = rb_ary_dup(lines);
	    rb_ary_freeze(lines);
            rb_hash_aset(h, ID2SYM(rb_intern(kw)), lines);
	}

	if (current_mode & COVERAGE_TARGET_BRANCHES) {
	    VALUE branches = RARRAY_AREF(coverage, COVERAGE_INDEX_BRANCHES);
	    rb_hash_aset(h, ID2SYM(rb_intern("branches")), branch_coverage(branches));
	}

	if (current_mode & COVERAGE_TARGET_METHODS) {
	    rb_hash_aset(h, ID2SYM(rb_intern("methods")), rb_hash_new());
	}

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
 * This is the same as `Coverage.result(stop: false, clear: false)`.
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

    if (current_mode & COVERAGE_TARGET_METHODS) {
	rb_objspace_each_objects(method_coverage_i, &ncoverages);
    }

    rb_hash_freeze(ncoverages);
    return ncoverages;
}


static int
clear_me2counter_i(VALUE key, VALUE value, VALUE unused)
{
    rb_hash_aset(me2counter, key, INT2FIX(0));
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     Coverage.result(stop: true, clear: true)  => hash
 *
 * Returns a hash that contains filename as key and coverage array as value.
 * If +clear+ is true, it clears the counters to zero.
 * If +stop+ is true, it disables coverage measurement.
 */
static VALUE
rb_coverage_result(int argc, VALUE *argv, VALUE klass)
{
    VALUE ncoverages;
    VALUE opt;
    int stop = 1, clear = 1;

    rb_scan_args(argc, argv, "01", &opt);

    if (argc == 1) {
        opt = rb_convert_type(opt, T_HASH, "Hash", "to_hash");
        stop = RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("stop"))));
        clear = RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("clear"))));
    }

    ncoverages = rb_coverage_peek_result(klass);
    if (stop && !clear) {
        rb_warn("stop implies clear");
        clear = 1;
    }
    if (clear) {
        rb_clear_coverages();
        if (!NIL_P(me2counter)) rb_hash_foreach(me2counter, clear_me2counter_i, Qnil);
    }
    if (stop) {
        rb_reset_coverages();
        me2counter = Qnil;
    }
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
    rb_define_module_function(rb_mCoverage, "result", rb_coverage_result, -1);
    rb_define_module_function(rb_mCoverage, "peek_result", rb_coverage_peek_result, 0);
    rb_define_module_function(rb_mCoverage, "running?", rb_coverage_running, 0);
    rb_global_variable(&me2counter);
}
