/************************************************

  coverage.c -

  $Author: $

  Copyright (c) 2008 Yusuke Endoh

************************************************/

#include "gc.h"
#include "internal/hash.h"
#include "internal/thread.h"
#include "internal/sanitizers.h"
#include "ruby.h"
#include "vm_core.h"

static enum {
    IDLE,
    SUSPENDED,
    RUNNING
} current_state = IDLE;
static int current_mode;
static VALUE me2counter = Qnil;

/*
 *  call-seq: Coverage.supported?(mode) -> true or false
 *
 *  Returns true if coverage measurement is supported for the given mode.
 *
 *  The mode should be one of the following symbols:
 *  +:lines+, +:branches+, +:methods+, +:eval+.
 *
 *  Example:
 *
 *    Coverage.supported?(:lines)  #=> true
 *    Coverage.supported?(:all)    #=> false
 */
static VALUE
rb_coverage_supported(VALUE self, VALUE _mode)
{
    ID mode = RB_SYM2ID(_mode);

    return RBOOL(
        mode == rb_intern("lines") ||
        mode == rb_intern("branches") ||
        mode == rb_intern("methods") ||
        mode == rb_intern("eval")
    );
}

/*
 * call-seq:
 *    Coverage.setup                                                          => nil
 *    Coverage.setup(:all)                                                    => nil
 *    Coverage.setup(lines: bool, branches: bool, methods: bool, eval: bool)  => nil
 *    Coverage.setup(oneshot_lines: true)                                     => nil
 *
 * Set up the coverage measurement.
 *
 * Note that this method does not start the measurement itself.
 * Use Coverage.resume to start the measurement.
 *
 * You may want to use Coverage.start to setup and then start the measurement.
 */
static VALUE
rb_coverage_setup(int argc, VALUE *argv, VALUE klass)
{
    VALUE coverages, opt;
    int mode;

    if (current_state != IDLE) {
        rb_raise(rb_eRuntimeError, "coverage measurement is already setup");
    }

    rb_scan_args(argc, argv, "01", &opt);

    if (argc == 0) {
        mode = 0; /* compatible mode */
    }
    else if (opt == ID2SYM(rb_intern("all"))) {
        mode = COVERAGE_TARGET_LINES | COVERAGE_TARGET_BRANCHES | COVERAGE_TARGET_METHODS | COVERAGE_TARGET_EVAL;
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
        if (RTEST(rb_hash_lookup(opt, ID2SYM(rb_intern("eval")))))
            mode |= COVERAGE_TARGET_EVAL;
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
        current_state = SUSPENDED;
    }
    else if (current_mode != mode) {
        rb_raise(rb_eRuntimeError, "cannot change the measuring target during coverage measurement");
    }

    return Qnil;
}

/*
 * call-seq:
 *    Coverage.resume  => nil
 *
 * Start/resume the coverage measurement.
 *
 * Caveat: Currently, only process-global coverage measurement is supported.
 * You cannot measure per-thread coverage. If your process has multiple thread,
 * using Coverage.resume/suspend to capture code coverage executed from only
 * a limited code block, may yield misleading results.
 */
VALUE
rb_coverage_resume(VALUE klass)
{
    if (current_state == IDLE) {
        rb_raise(rb_eRuntimeError, "coverage measurement is not set up yet");
    }
    if (current_state == RUNNING) {
        rb_raise(rb_eRuntimeError, "coverage measurement is already running");
    }
    rb_resume_coverages();
    current_state = RUNNING;
    return Qnil;
}

/*
 * call-seq:
 *    Coverage.start                                                          => nil
 *    Coverage.start(:all)                                                    => nil
 *    Coverage.start(lines: bool, branches: bool, methods: bool, eval: bool)  => nil
 *    Coverage.start(oneshot_lines: true)                                     => nil
 *
 * Enables the coverage measurement.
 * See the documentation of Coverage class in detail.
 * This is equivalent to Coverage.setup and Coverage.resume.
 */
static VALUE
rb_coverage_start(int argc, VALUE *argv, VALUE klass)
{
    rb_coverage_setup(argc, argv, klass);
    rb_coverage_resume(klass);
    return Qnil;
}

struct branch_coverage_result_builder
{
    int id;
    VALUE result;
    VALUE children;
    VALUE counters;
};

static int
branch_coverage_ii(VALUE _key, VALUE branch, VALUE v)
{
    struct branch_coverage_result_builder *b = (struct branch_coverage_result_builder *) v;

    VALUE target_label = RARRAY_AREF(branch, 0);
    VALUE target_first_lineno = RARRAY_AREF(branch, 1);
    VALUE target_first_column = RARRAY_AREF(branch, 2);
    VALUE target_last_lineno = RARRAY_AREF(branch, 3);
    VALUE target_last_column = RARRAY_AREF(branch, 4);
    long counter_idx = FIX2LONG(RARRAY_AREF(branch, 5));
    rb_hash_aset(b->children, rb_ary_new_from_args(6, target_label, LONG2FIX(b->id++), target_first_lineno, target_first_column, target_last_lineno, target_last_column), RARRAY_AREF(b->counters, counter_idx));

    return ST_CONTINUE;
}

static int
branch_coverage_i(VALUE _key, VALUE branch_base, VALUE v)
{
    struct branch_coverage_result_builder *b = (struct branch_coverage_result_builder *) v;

    VALUE base_type = RARRAY_AREF(branch_base, 0);
    VALUE base_first_lineno = RARRAY_AREF(branch_base, 1);
    VALUE base_first_column = RARRAY_AREF(branch_base, 2);
    VALUE base_last_lineno = RARRAY_AREF(branch_base, 3);
    VALUE base_last_column = RARRAY_AREF(branch_base, 4);
    VALUE branches = RARRAY_AREF(branch_base, 5);
    VALUE children = rb_hash_new();
    rb_hash_aset(b->result, rb_ary_new_from_args(6, base_type, LONG2FIX(b->id++), base_first_lineno, base_first_column, base_last_lineno, base_last_column), children);
    b->children = children;
    rb_hash_foreach(branches, branch_coverage_ii, v);

    return ST_CONTINUE;
}

static VALUE
branch_coverage(VALUE branches)
{
    VALUE structure = RARRAY_AREF(branches, 0);

    struct branch_coverage_result_builder b;
    b.id = 0;
    b.result = rb_hash_new();
    b.counters = RARRAY_AREF(branches, 1);

    rb_hash_foreach(structure, branch_coverage_i, (VALUE)&b);

    return b.result;
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
        void *poisoned = asan_poisoned_object_p(v);
        asan_unpoison_object(v, false);

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

        if (poisoned) {
            asan_poison_object(v);
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
    OBJ_WB_UNPROTECT(coverages);
    st_foreach(RHASH_TBL_RAW(coverages), coverage_peek_result_i, ncoverages);

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
 * call-seq:
 *    Coverage.suspend  => nil
 *
 * Suspend the coverage measurement.
 * You can use Coverage.resume to restart the measurement.
 */
VALUE
rb_coverage_suspend(VALUE klass)
{
    if (current_state != RUNNING) {
        rb_raise(rb_eRuntimeError, "coverage measurement is not running");
    }
    rb_suspend_coverages();
    current_state = SUSPENDED;
    return Qnil;
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

    if (current_state == IDLE) {
        rb_raise(rb_eRuntimeError, "coverage measurement is not enabled");
    }

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
        if (current_state == RUNNING) {
            rb_coverage_suspend(klass);
        }
        rb_reset_coverages();
        me2counter = Qnil;
        current_state = IDLE;
    }
    return ncoverages;
}


/*
 *  call-seq:
 *     Coverage.state  => :idle, :suspended, :running
 *
 * Returns the state of the coverage measurement.
 */
static VALUE
rb_coverage_state(VALUE klass)
{
    switch (current_state) {
        case IDLE: return ID2SYM(rb_intern("idle"));
        case SUSPENDED: return ID2SYM(rb_intern("suspended"));
        case RUNNING: return ID2SYM(rb_intern("running"));
    }
    return Qnil;
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
    return current_state == RUNNING ? Qtrue : Qfalse;
}

/* Coverage provides coverage measurement feature for Ruby.
 * This feature is experimental, so these APIs may be changed in future.
 *
 * Caveat: Currently, only process-global coverage measurement is supported.
 * You cannot measure per-thread coverage.
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
 * = Examples
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
 *
 * == Lines Coverage
 *
 * If a coverage mode is not explicitly specified when starting coverage, lines
 * coverage is what will run. It reports the number of line executions for each
 * line.
 *
 *   require "coverage"
 *   Coverage.start(lines: true)
 *   require "foo.rb"
 *   p Coverage.result #=> {"foo.rb"=>{:lines=>[1, 1, 10, nil, nil, 1, 1, nil, 0, nil]}}
 *
 * The value of the lines coverage result is an array containing how many times
 * each line was executed. Order in this array is important. For example, the
 * first item in this array, at index 0, reports how many times line 1 of this
 * file was executed while coverage was run (which, in this example, is one
 * time).
 *
 * A +nil+ value means coverage is disabled for this line (lines like +else+
 * and +end+).
 *
 * == Oneshot Lines Coverage
 *
 * Oneshot lines coverage tracks and reports on the executed lines while
 * coverage is running. It will not report how many times a line was executed,
 * only that it was executed.
 *
 *   require "coverage"
 *   Coverage.start(oneshot_lines: true)
 *   require "foo.rb"
 *   p Coverage.result #=> {"foo.rb"=>{:oneshot_lines=>[1, 2, 3, 6, 7]}}
 *
 * The value of the oneshot lines coverage result is an array containing the
 * line numbers that were executed.
 *
 * == Branches Coverage
 *
 * Branches coverage reports how many times each branch within each conditional
 * was executed.
 *
 *   require "coverage"
 *   Coverage.start(branches: true)
 *   require "foo.rb"
 *   p Coverage.result #=> {"foo.rb"=>{:branches=>{[:if, 0, 6, 0, 10, 3]=>{[:then, 1, 7, 2, 7, 7]=>1, [:else, 2, 9, 2, 9, 7]=>0}}}}
 *
 * Each entry within the branches hash is a conditional, the value of which is
 * another hash where each entry is a branch in that conditional. The values
 * are the number of times the method was executed, and the keys are identifying
 * information about the branch.
 *
 * The information that makes up each key identifying branches or conditionals
 * is the following, from left to right:
 *
 * 1. A label for the type of branch or conditional.
 * 2. A unique identifier.
 * 3. The starting line number it appears on in the file.
 * 4. The starting column number it appears on in the file.
 * 5. The ending line number it appears on in the file.
 * 6. The ending column number it appears on in the file.
 *
 * == Methods Coverage
 *
 * Methods coverage reports how many times each method was executed.
 *
 *   [foo_method.rb]
 *   class Greeter
 *     def greet
 *       "welcome!"
 *     end
 *   end
 *
 *   def hello
 *     "Hi"
 *   end
 *
 *   hello()
 *   Greeter.new.greet()
 *   [EOF]
 *
 *   require "coverage"
 *   Coverage.start(methods: true)
 *   require "foo_method.rb"
 *   p Coverage.result #=> {"foo_method.rb"=>{:methods=>{[Object, :hello, 7, 0, 9, 3]=>1, [Greeter, :greet, 2, 2, 4, 5]=>1}}}
 *
 * Each entry within the methods hash represents a method. The values in this
 * hash are the number of times the method was executed, and the keys are
 * identifying information about the method.
 *
 * The information that makes up each key identifying a method is the following,
 * from left to right:
 *
 * 1. The class.
 * 2. The method name.
 * 3. The starting line number the method appears on in the file.
 * 4. The starting column number the method appears on in the file.
 * 5. The ending line number the method appears on in the file.
 * 6. The ending column number the method appears on in the file.
 *
 * == All Coverage Modes
 *
 * You can also run all modes of coverage simultaneously with this shortcut.
 * Note that running all coverage modes does not run both lines and oneshot
 * lines. Those modes cannot be run simultaneously. Lines coverage is run in
 * this case, because you can still use it to determine whether or not a line
 * was executed.
 *
 *   require "coverage"
 *   Coverage.start(:all)
 *   require "foo.rb"
 *   p Coverage.result #=> {"foo.rb"=>{:lines=>[1, 1, 10, nil, nil, 1, 1, nil, 0, nil], :branches=>{[:if, 0, 6, 0, 10, 3]=>{[:then, 1, 7, 2, 7, 7]=>1, [:else, 2, 9, 2, 9, 7]=>0}}, :methods=>{}}}
 */
void
Init_coverage(void)
{
    VALUE rb_mCoverage = rb_define_module("Coverage");

    rb_define_singleton_method(rb_mCoverage, "supported?", rb_coverage_supported, 1);

    rb_define_module_function(rb_mCoverage, "setup", rb_coverage_setup, -1);
    rb_define_module_function(rb_mCoverage, "start", rb_coverage_start, -1);
    rb_define_module_function(rb_mCoverage, "resume", rb_coverage_resume, 0);
    rb_define_module_function(rb_mCoverage, "suspend", rb_coverage_suspend, 0);
    rb_define_module_function(rb_mCoverage, "result", rb_coverage_result, -1);
    rb_define_module_function(rb_mCoverage, "peek_result", rb_coverage_peek_result, 0);
    rb_define_module_function(rb_mCoverage, "state", rb_coverage_state, 0);
    rb_define_module_function(rb_mCoverage, "running?", rb_coverage_running, 0);
    rb_global_variable(&me2counter);
}
