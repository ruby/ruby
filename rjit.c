/**********************************************************************

  rjit.c - Ruby JIT compiler functions

  Copyright (C) 2023 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "rjit.h" // defines USE_RJIT

#if USE_RJIT

#include "constant.h"
#include "id_table.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/cmdlineopt.h"
#include "internal/cont.h"
#include "internal/file.h"
#include "internal/hash.h"
#include "internal/process.h"
#include "internal/warnings.h"
#include "vm_sync.h"
#include "ractor_core.h"

#ifdef __sun
#define __EXTENSIONS__ 1
#endif

#include "vm_core.h"
#include "vm_callinfo.h"
#include "rjit_c.h"
#include "ruby_assert.h"
#include "ruby/debug.h"
#include "ruby/thread.h"
#include "ruby/version.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "internal/compile.h"
#include "internal/gc.h"

#include <sys/wait.h>
#include <sys/time.h>
#include <dlfcn.h>
#include <errno.h>
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif
#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#endif
#include "dln.h"

// For mmapp(), sysconf()
#ifndef _WIN32
#include <unistd.h>
#include <sys/mman.h>
#endif

#include "ruby/util.h"

// A copy of RJIT portion of MRI options since RJIT initialization.  We
// need them as RJIT threads still can work when the most MRI data were
// freed.
struct rb_rjit_options rb_rjit_opts;

// true if RJIT is enabled.
bool rb_rjit_enabled = false;
// true if --rjit-stats (used before rb_rjit_opts is set)
bool rb_rjit_stats_enabled = false;
// true if --rjit-trace-exits (used before rb_rjit_opts is set)
bool rb_rjit_trace_exits_enabled = false;
// true if JIT-ed code should be called. When `ruby_vm_event_enabled_global_flags & ISEQ_TRACE_EVENTS`
// and `rb_rjit_call_p == false`, any JIT-ed code execution is cancelled as soon as possible.
bool rb_rjit_call_p = false;
// A flag to communicate that rb_rjit_call_p should be disabled while it's temporarily false.
static bool rjit_cancel_p = false;

// `rb_ec_ractor_hooks(ec)->events` is moved to this variable during compilation.
rb_event_flag_t rb_rjit_global_events = 0;

// Basically rb_rjit_opts.stats, but this becomes false during RJIT compilation.
static bool rjit_stats_p = false;

// RubyVM::RJIT
static VALUE rb_mRJIT = 0;
// RubyVM::RJIT::C
static VALUE rb_mRJITC = 0;
// RubyVM::RJIT::Compiler
static VALUE rb_RJITCompiler = 0;
// RubyVM::RJIT::CPointer::Struct_rb_iseq_t
static VALUE rb_cRJITIseqPtr = 0;
// RubyVM::RJIT::CPointer::Struct_rb_control_frame_t
static VALUE rb_cRJITCfpPtr = 0;
// RubyVM::RJIT::Hooks
static VALUE rb_mRJITHooks = 0;

// Frames for --rjit-trace-exits
VALUE rb_rjit_raw_samples = 0;
// Line numbers for --rjit-trace-exits
VALUE rb_rjit_line_samples = 0;

// Postponed job handle for triggering rjit_iseq_update_references
static rb_postponed_job_handle_t rjit_iseq_update_references_pjob;

// A default threshold used to add iseq to JIT.
#define DEFAULT_CALL_THRESHOLD 10
// Size of executable memory block in MiB.
#define DEFAULT_EXEC_MEM_SIZE 64

#define opt_match_noarg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? (rb_warn("argument to --rjit-" name " is ignored"), 1) : 1)
#define opt_match_arg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? 1 : (rb_raise(rb_eRuntimeError, "--rjit-" name " needs an argument"), 0))

void
rb_rjit_setup_options(const char *s, struct rb_rjit_options *rjit_opt)
{
    const size_t l = strlen(s);
    if (l == 0) {
        return;
    }
    else if (opt_match_arg(s, l, "exec-mem-size")) {
        rjit_opt->exec_mem_size = atoi(s + 1);
    }
    else if (opt_match_arg(s, l, "call-threshold")) {
        rjit_opt->call_threshold = atoi(s + 1);
    }
    else if (opt_match_noarg(s, l, "stats")) {
        rjit_opt->stats = true;
    }
    else if (opt_match_noarg(s, l, "disable")) {
        rjit_opt->disable = true;
    }
    else if (opt_match_noarg(s, l, "trace")) {
        rjit_opt->trace = true;
    }
    else if (opt_match_noarg(s, l, "trace-exits")) {
        rjit_opt->trace_exits = true;
    }
    else if (opt_match_noarg(s, l, "dump-disasm")) {
        rjit_opt->dump_disasm = true;
    }
    else if (opt_match_noarg(s, l, "verify-ctx")) {
        rjit_opt->verify_ctx = true;
    }
    else {
        rb_raise(rb_eRuntimeError,
                 "invalid RJIT option '%s' (--help will show valid RJIT options)", s);
    }
}

#define M(shortopt, longopt, desc) RUBY_OPT_MESSAGE(shortopt, longopt, desc)
const struct ruby_opt_message rb_rjit_option_messages[] = {
    M("--rjit-exec-mem-size=num",  "", "Size of executable memory block in MiB (default: " STRINGIZE(DEFAULT_EXEC_MEM_SIZE) ")"),
    M("--rjit-call-threshold=num", "", "Number of calls to trigger JIT (default: " STRINGIZE(DEFAULT_CALL_THRESHOLD) ")"),
    M("--rjit-stats",              "", "Enable collecting RJIT statistics"),
    M("--rjit-disable",            "", "Disable RJIT for lazily enabling it with RubyVM::RJIT.enable"),
    M("--rjit-trace",              "", "Allow TracePoint during JIT compilation"),
    M("--rjit-trace-exits",        "", "Trace side exit locations"),
#ifdef HAVE_LIBCAPSTONE
    M("--rjit-dump-disasm",        "", "Dump all JIT code"),
#endif
    {0}
};
#undef M

struct rb_rjit_runtime_counters rb_rjit_counters = { 0 };

extern VALUE rb_gc_enable(void);
extern VALUE rb_gc_disable(void);
extern uint64_t rb_vm_insns_count;

// Disable GC, TracePoint, JIT, stats, and $!
#define WITH_RJIT_ISOLATED_USING_PC(using_pc, stmt) do { \
    VALUE was_disabled = rb_gc_disable(); \
    \
    rb_hook_list_t *global_hooks = rb_ec_ractor_hooks(GET_EC()); \
    rb_rjit_global_events = global_hooks->events; \
    \
    const VALUE *pc = NULL; \
    if (rb_rjit_opts.trace) { \
        pc = GET_EC()->cfp->pc; \
        if (!using_pc) GET_EC()->cfp->pc = 0; /* avoid crashing on calc_lineno */ \
    } \
    else global_hooks->events = 0; \
    \
    bool original_call_p = rb_rjit_call_p; \
    rb_rjit_call_p = false; \
    \
    rjit_stats_p = false; \
    uint64_t insns_count = rb_vm_insns_count; \
    \
    VALUE err = rb_errinfo(); \
    \
    stmt; \
    \
    rb_set_errinfo(err); \
    \
    rb_vm_insns_count = insns_count; \
    rjit_stats_p = rb_rjit_opts.stats; \
    \
    rb_rjit_call_p = (rjit_cancel_p ? false : original_call_p); \
    \
    if (rb_rjit_opts.trace) GET_EC()->cfp->pc = pc; \
    else global_hooks->events = rb_rjit_global_events; \
    \
    if (!was_disabled) rb_gc_enable(); \
} while (0);
#define WITH_RJIT_ISOLATED(stmt) WITH_RJIT_ISOLATED_USING_PC(false, stmt)

void
rb_rjit_cancel_all(const char *reason)
{
    if (!rb_rjit_enabled)
        return;

    rb_rjit_call_p = false;
    rjit_cancel_p = true;
}

void
rb_rjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop)
{
    if (!rb_rjit_call_p) return;
    rb_rjit_call_p = false;
}

static void
rjit_cme_invalidate(void *data)
{
    if (!rb_rjit_enabled || !rb_rjit_call_p || !rb_mRJITHooks) return;
    WITH_RJIT_ISOLATED({
        rb_funcall(rb_mRJITHooks, rb_intern("on_cme_invalidate"), 1, SIZET2NUM((size_t)data));
    });
}

extern int rb_workqueue_register(unsigned flags, rb_postponed_job_func_t func, void *data);

void
rb_rjit_cme_invalidate(rb_callable_method_entry_t *cme)
{
    if (!rb_rjit_enabled || !rb_rjit_call_p || !rb_mRJITHooks) return;
    // Asynchronously hook the Ruby code since running Ruby in the middle of cme invalidation is dangerous.
    rb_workqueue_register(0, rjit_cme_invalidate, (void *)cme);
}

void
rb_rjit_before_ractor_spawn(void)
{
    if (!rb_rjit_call_p) return;
    rb_rjit_call_p = false;
}

static void
rjit_constant_state_changed(void *data)
{
    if (!rb_rjit_enabled || !rb_rjit_call_p || !rb_mRJITHooks) return;
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    WITH_RJIT_ISOLATED({
        rb_funcall(rb_mRJITHooks, rb_intern("on_constant_state_changed"), 1, SIZET2NUM((size_t)data));
    });

    RB_VM_LOCK_LEAVE();
}

void
rb_rjit_constant_state_changed(ID id)
{
    if (!rb_rjit_enabled || !rb_rjit_call_p || !rb_mRJITHooks) return;
    // Asynchronously hook the Ruby code since this is hooked during a "Ruby critical section".
    rb_workqueue_register(0, rjit_constant_state_changed, (void *)id);
}

void
rb_rjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx)
{
    if (!rb_rjit_enabled || !rb_rjit_call_p || !rb_mRJITHooks) return;

    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    WITH_RJIT_ISOLATED({
        rb_funcall(rb_mRJITHooks, rb_intern("on_constant_ic_update"), 3,
                   SIZET2NUM((size_t)iseq), SIZET2NUM((size_t)ic), UINT2NUM(insn_idx));
    });

    RB_VM_LOCK_LEAVE();
}

void
rb_rjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events)
{
    if (!rb_rjit_enabled || !rb_rjit_call_p || !rb_mRJITHooks) return;
    WITH_RJIT_ISOLATED({
        rb_funcall(rb_mRJITHooks, rb_intern("on_tracing_invalidate_all"), 1, UINT2NUM(new_iseq_events));
    });
}

static void
rjit_iseq_update_references(void *data)
{
    if (!rb_rjit_enabled || !rb_rjit_call_p || !rb_mRJITHooks) return;
    WITH_RJIT_ISOLATED({
        rb_funcall(rb_mRJITHooks, rb_intern("on_update_references"), 0);
    });
}

void
rb_rjit_iseq_update_references(struct rb_iseq_constant_body *const body)
{
    if (!rb_rjit_enabled) return;

    if (body->rjit_blocks) {
        body->rjit_blocks = rb_gc_location(body->rjit_blocks);
    }

    // Asynchronously hook the Ruby code to avoid allocation during GC.compact.
    // Using _one because it's too slow to invalidate all for each ISEQ. Thus
    // not giving an ISEQ pointer.
    rb_postponed_job_trigger(rjit_iseq_update_references_pjob);
}

void
rb_rjit_iseq_mark(VALUE rjit_blocks)
{
    if (!rb_rjit_enabled) return;

    // Note: This wasn't enough for some reason.
    // We actually rely on RubyVM::RJIT::GC_REFS to mark this.
    if (rjit_blocks) {
        rb_gc_mark_movable(rjit_blocks);
    }
}

// Called by rb_vm_mark()
void
rb_rjit_mark(void)
{
    if (!rb_rjit_enabled)
        return;
    RUBY_MARK_ENTER("rjit");

    // Pin object pointers used in this file
    rb_gc_mark(rb_RJITCompiler);
    rb_gc_mark(rb_cRJITIseqPtr);
    rb_gc_mark(rb_cRJITCfpPtr);
    rb_gc_mark(rb_mRJITHooks);
    rb_gc_mark(rb_rjit_raw_samples);
    rb_gc_mark(rb_rjit_line_samples);

    RUBY_MARK_LEAVE("rjit");
}

void
rb_rjit_free_iseq(const rb_iseq_t *iseq)
{
    // TODO: implement this. GC_REFS should remove this iseq's mjit_blocks
}

// TODO: Use this in more places
VALUE
rb_rjit_iseq_new(rb_iseq_t *iseq)
{
    return rb_funcall(rb_cRJITIseqPtr, rb_intern("new"), 1, SIZET2NUM((size_t)iseq));
}

void
rb_rjit_compile(const rb_iseq_t *iseq)
{
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    WITH_RJIT_ISOLATED_USING_PC(true, {
        VALUE iseq_ptr = rb_funcall(rb_cRJITIseqPtr, rb_intern("new"), 1, SIZET2NUM((size_t)iseq));
        VALUE cfp_ptr = rb_funcall(rb_cRJITCfpPtr, rb_intern("new"), 1, SIZET2NUM((size_t)GET_EC()->cfp));
        rb_funcall(rb_RJITCompiler, rb_intern("compile"), 2, iseq_ptr, cfp_ptr);
    });

    RB_VM_LOCK_LEAVE();
}

void *
rb_rjit_entry_stub_hit(VALUE branch_stub)
{
    VALUE result;

    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    rb_control_frame_t *cfp = GET_EC()->cfp;

    WITH_RJIT_ISOLATED_USING_PC(true, {
        VALUE cfp_ptr = rb_funcall(rb_cRJITCfpPtr, rb_intern("new"), 1, SIZET2NUM((size_t)cfp));
        result = rb_funcall(rb_RJITCompiler, rb_intern("entry_stub_hit"), 2, branch_stub, cfp_ptr);
    });

    RB_VM_LOCK_LEAVE();

    return (void *)NUM2SIZET(result);
}

void *
rb_rjit_branch_stub_hit(VALUE branch_stub, int sp_offset, int target0_p)
{
    VALUE result;

    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    rb_control_frame_t *cfp = GET_EC()->cfp;
    cfp->sp += sp_offset; // preserve stack values, also using the actual sp_offset to make jit.peek_at_stack work

    WITH_RJIT_ISOLATED({
        VALUE cfp_ptr = rb_funcall(rb_cRJITCfpPtr, rb_intern("new"), 1, SIZET2NUM((size_t)cfp));
        result = rb_funcall(rb_RJITCompiler, rb_intern("branch_stub_hit"), 3, branch_stub, cfp_ptr, RBOOL(target0_p));
    });

    cfp->sp -= sp_offset; // reset for consistency with the code without the stub

    RB_VM_LOCK_LEAVE();

    return (void *)NUM2SIZET(result);
}

void
rb_rjit_init(const struct rb_rjit_options *opts)
{
    VM_ASSERT(rb_rjit_enabled);

    // Normalize options
    rb_rjit_opts = *opts;
    if (rb_rjit_opts.exec_mem_size == 0)
        rb_rjit_opts.exec_mem_size = DEFAULT_EXEC_MEM_SIZE;
    if (rb_rjit_opts.call_threshold == 0)
        rb_rjit_opts.call_threshold = DEFAULT_CALL_THRESHOLD;
#ifndef HAVE_LIBCAPSTONE
    if (rb_rjit_opts.dump_disasm)
        rb_warn("libcapstone has not been linked. Ignoring --rjit-dump-disasm.");
#endif

    // RJIT doesn't support miniruby, but it might reach here by RJIT_FORCE_ENABLE.
    rb_mRJIT = rb_const_get(rb_cRubyVM, rb_intern("RJIT"));
    if (!rb_const_defined(rb_mRJIT, rb_intern("Compiler"))) {
        rb_warn("Disabling RJIT because RubyVM::RJIT::Compiler is not defined");
        rb_rjit_enabled = false;
        return;
    }
    rjit_iseq_update_references_pjob = rb_postponed_job_preregister(0, rjit_iseq_update_references, NULL);
    if (rjit_iseq_update_references_pjob == POSTPONED_JOB_HANDLE_INVALID) {
        rb_bug("Could not preregister postponed job for RJIT");
    }
    rb_mRJITC = rb_const_get(rb_mRJIT, rb_intern("C"));
    VALUE rb_cRJITCompiler = rb_const_get(rb_mRJIT, rb_intern("Compiler"));
    rb_RJITCompiler = rb_funcall(rb_cRJITCompiler, rb_intern("new"), 0);
    rb_cRJITIseqPtr = rb_funcall(rb_mRJITC, rb_intern("rb_iseq_t"), 0);
    rb_cRJITCfpPtr = rb_funcall(rb_mRJITC, rb_intern("rb_control_frame_t"), 0);
    rb_mRJITHooks = rb_const_get(rb_mRJIT, rb_intern("Hooks"));
    if (rb_rjit_opts.trace_exits) {
        rb_rjit_raw_samples = rb_ary_new();
        rb_rjit_line_samples = rb_ary_new();
    }

    // Enable RJIT and stats from here
    rb_rjit_call_p = !rb_rjit_opts.disable;
    rjit_stats_p = rb_rjit_opts.stats;
}

//
// Primitive for rjit.rb
//

// Same as `rb_rjit_opts.stats`, but this is used before rb_rjit_opts is set.
static VALUE
rjit_stats_enabled_p(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(rb_rjit_stats_enabled);
}

// Same as `rb_rjit_opts.trace_exits`, but this is used before rb_rjit_opts is set.
static VALUE
rjit_trace_exits_enabled_p(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(rb_rjit_trace_exits_enabled);
}

// Disable anything that could impact stats. It ends up disabling JIT calls as well.
static VALUE
rjit_stop_stats(rb_execution_context_t *ec, VALUE self)
{
    rb_rjit_call_p = false;
    rjit_stats_p = false;
    return Qnil;
}

#include "rjit.rbinc"

#endif // USE_RJIT
