#include "internal/mmtk_support.h"

#if USE_MMTK

/*
 *  call-seq:
 *      GC::MMTk.plan_name -> String
 *
 *  Returns the name of the current MMTk plan.
 */
static VALUE
rb_mmtk_plan_name(VALUE _)
{
    if (!rb_mmtk_enabled_p()) {
        rb_raise(rb_eRuntimeError, "Debug harness can only be used when MMTk is enabled, re-run with --mmtk.");
    }
    const char* plan_name = mmtk_plan_name();
    return rb_str_new(plan_name, strlen(plan_name));
}

/*
 *  call-seq:
 *      GC::MMTk.enabled? -> true or false
 *
 *  Returns true if using MMTk as garbage collector, false otherwise.
 *
 *  Note: If the Ruby interpreter is not compiled with MMTk support, the
 *  <code>GC::MMTk</code> module will not exist in the first place.
 *  You can check if the module exists by
 *
 *    defined? GC::MMTk
 */
static VALUE
rb_mmtk_enabled(VALUE _)
{
    return RBOOL(rb_mmtk_enabled_p());
}

/*
 *  call-seq:
 *      GC::MMTk.harness_begin
 *
 *  A hook to be called before a benchmark begins.
 *
 *  MMTk will do necessary preparations (such as triggering a full-heap GC)
 *  and start collecting statistic data, such as the number of GC triggered,
 *  time spent in GC, time spent in mutator, etc.
 */
static VALUE
rb_mmtk_harness_begin(VALUE _)
{
    if (!rb_mmtk_enabled_p()) {
        rb_raise(rb_eRuntimeError, "Debug harness can only be used when MMTk is enabled, re-run with --mmtk.");
    }
    mmtk_harness_begin((MMTk_VMMutatorThread)GET_THREAD());
    return Qnil;
}

/*
 *  call-seq:
 *      GC::MMTk.harness_end
 *
 *  A hook to be called after a benchmark ends.
 *
 *  When this method is called, MMTk will stop collecting statistic data and
 *  print out the data already collected.
 */
static VALUE
rb_mmtk_harness_end(VALUE _)
{
    if (!rb_mmtk_enabled_p()) {
        rb_raise(rb_eRuntimeError, "Debug harness can only be used when MMTk is enabled, re-run with --mmtk.");
    }
    mmtk_harness_end((MMTk_VMMutatorThread)GET_THREAD());
    return Qnil;
}

#endif // USE_MMTK
