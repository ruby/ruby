/**********************************************************************

  mjit.c - MRI method JIT compiler functions

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.
  Copyright (C) 2017 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "ruby/internal/config.h" // defines USE_MJIT

// ISO C requires a translation unit to contain at least one declaration
void rb_mjit(void) {}

#if USE_MJIT

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
#include "mjit.h"
#include "mjit_c.h"
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

#include "ruby/util.h"

// A copy of MJIT portion of MRI options since MJIT initialization.  We
// need them as MJIT threads still can work when the most MRI data were
// freed.
struct mjit_options mjit_opts;

// true if MJIT is enabled.
bool mjit_enabled = false;
bool mjit_stats_enabled = false;
// true if JIT-ed code should be called. When `ruby_vm_event_enabled_global_flags & ISEQ_TRACE_EVENTS`
// and `mjit_call_p == false`, any JIT-ed code execution is cancelled as soon as possible.
bool mjit_call_p = false;
// A flag to communicate that mjit_call_p should be disabled while it's temporarily false.
bool mjit_cancel_p = false;

#include "mjit_config.h"

// Print the arguments according to FORMAT to stderr only if MJIT
// verbose option value is more or equal to LEVEL.
PRINTF_ARGS(static void, 2, 3)
verbose(int level, const char *format, ...)
{
    if (mjit_opts.verbose >= level) {
        va_list args;
        size_t len = strlen(format);
        char *full_format = alloca(sizeof(char) * (len + 2));

        // Creating `format + '\n'` to atomically print format and '\n'.
        memcpy(full_format, format, len);
        full_format[len] = '\n';
        full_format[len+1] = '\0';

        va_start(args, format);
        vfprintf(stderr, full_format, args);
        va_end(args);
    }
}

int
mjit_capture_cc_entries(const struct rb_iseq_constant_body *compiled_iseq, const struct rb_iseq_constant_body *captured_iseq)
{
    // TODO: remove this
    return 0;
}

void
mjit_cancel_all(const char *reason)
{
    if (!mjit_enabled)
        return;

    mjit_call_p = false;
    mjit_cancel_p = true;
    if (mjit_opts.warnings || mjit_opts.verbose) {
        fprintf(stderr, "JIT cancel: Disabled JIT-ed code because %s\n", reason);
    }
}

void
mjit_free_iseq(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
mjit_notify_waitpid(int exit_code)
{
    // TODO: remove this function
}

// RubyVM::MJIT
static VALUE rb_mMJIT = 0;
// RubyVM::MJIT::C
static VALUE rb_mMJITC = 0;
// RubyVM::MJIT::Compiler
static VALUE rb_MJITCompiler = 0;
// RubyVM::MJIT::CPointer::Struct_rb_iseq_t
static VALUE rb_cMJITIseqPtr = 0;
// RubyVM::MJIT::CPointer::Struct_rb_control_frame_t
static VALUE rb_cMJITCfpPtr = 0;
// RubyVM::MJIT::Hooks
static VALUE rb_mMJITHooks = 0;

void
rb_mjit_add_iseq_to_process(const rb_iseq_t *iseq)
{
    // TODO: implement
}

struct rb_mjit_compile_info*
rb_mjit_iseq_compile_info(const struct rb_iseq_constant_body *body)
{
    // TODO: remove this
    return NULL;
}

void
rb_mjit_recompile_send(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rb_mjit_recompile_ivar(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rb_mjit_recompile_exivar(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rb_mjit_recompile_inlining(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rb_mjit_recompile_const(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

// Default permitted number of units with a JIT code kept in memory.
#define DEFAULT_MAX_CACHE_SIZE 100
// A default threshold used to add iseq to JIT.
#define DEFAULT_CALL_THRESHOLD 30

#define opt_match_noarg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? (rb_warn("argument to --mjit-" name " is ignored"), 1) : 1)
#define opt_match_arg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? 1 : (rb_raise(rb_eRuntimeError, "--mjit-" name " needs an argument"), 0))

void
mjit_setup_options(const char *s, struct mjit_options *mjit_opt)
{
    const size_t l = strlen(s);
    if (l == 0) {
        return;
    }
    else if (opt_match_noarg(s, l, "warnings")) {
        mjit_opt->warnings = true;
    }
    else if (opt_match(s, l, "debug")) {
        if (*s)
            mjit_opt->debug_flags = strdup(s + 1);
        else
            mjit_opt->debug = true;
    }
    else if (opt_match_noarg(s, l, "wait")) {
        mjit_opt->wait = true;
    }
    else if (opt_match_noarg(s, l, "save-temps")) {
        mjit_opt->save_temps = true;
    }
    else if (opt_match(s, l, "verbose")) {
        mjit_opt->verbose = *s ? atoi(s + 1) : 1;
    }
    else if (opt_match_arg(s, l, "max-cache")) {
        mjit_opt->max_cache_size = atoi(s + 1);
    }
    else if (opt_match_arg(s, l, "call-threshold")) {
        mjit_opt->call_threshold = atoi(s + 1);
    }
    else if (opt_match_noarg(s, l, "stats")) {
        mjit_opt->stats = true;
    }
    // --mjit=pause is an undocumented feature for experiments
    else if (opt_match_noarg(s, l, "pause")) {
        mjit_opt->pause = true;
    }
    else if (opt_match_noarg(s, l, "dump-disasm")) {
        mjit_opt->dump_disasm = true;
    }
    else {
        rb_raise(rb_eRuntimeError,
                 "invalid MJIT option `%s' (--help will show valid MJIT options)", s);
    }
}

#define M(shortopt, longopt, desc) RUBY_OPT_MESSAGE(shortopt, longopt, desc)
const struct ruby_opt_message mjit_option_messages[] = {
    M("--mjit-warnings",           "", "Enable printing JIT warnings"),
    M("--mjit-debug",              "", "Enable JIT debugging (very slow), or add cflags if specified"),
    M("--mjit-wait",               "", "Wait until JIT compilation finishes every time (for testing)"),
    M("--mjit-save-temps",         "", "Save JIT temporary files in $TMP or /tmp (for testing)"),
    M("--mjit-verbose=num",        "", "Print JIT logs of level num or less to stderr (default: 0)"),
    M("--mjit-max-cache=num",      "", "Max number of methods to be JIT-ed in a cache (default: " STRINGIZE(DEFAULT_MAX_CACHE_SIZE) ")"),
    M("--mjit-call-threshold=num", "", "Number of calls to trigger JIT (for testing, default: " STRINGIZE(DEFAULT_CALL_THRESHOLD) ")"),
    M("--mjit-stats",              "", "Enable collecting MJIT statistics"),
    {0}
};
#undef M

VALUE
mjit_pause(bool wait_p)
{
    // TODO: remove this
    return Qtrue;
}

VALUE
mjit_resume(void)
{
    // TODO: remove this
    return Qnil;
}

void
mjit_child_after_fork(void)
{
    // TODO: remove this
}

// Compile ISeq to C code in `f`. It returns true if it succeeds to compile.
bool
mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id)
{
    // TODO: implement
    return false;
}

//================================================================================
//
// New stuff from here
//

// JIT buffer
uint8_t *rb_mjit_mem_block = NULL;

// `rb_ec_ractor_hooks(ec)->events` is moved to this variable during compilation.
rb_event_flag_t rb_mjit_global_events = 0;

// Basically mjit_opts.stats, but this becomes false during MJIT compilation.
static bool mjit_stats_p = false;

#if MJIT_STATS

struct rb_mjit_runtime_counters rb_mjit_counters = { 0 };

void
rb_mjit_collect_vm_usage_insn(int insn)
{
    if (!mjit_stats_p) return;
    rb_mjit_counters.vm_insns_count++;
}

#endif // YJIT_STATS

extern VALUE rb_gc_enable(void);
extern VALUE rb_gc_disable(void);

#define WITH_MJIT_ISOLATED(stmt) do { \
    VALUE was_disabled = rb_gc_disable(); \
    rb_hook_list_t *global_hooks = rb_ec_ractor_hooks(GET_EC()); \
    rb_mjit_global_events = global_hooks->events; \
    global_hooks->events = 0; \
    bool original_call_p = mjit_call_p; \
    mjit_stats_p = false; \
    mjit_call_p = false; \
    stmt; \
    mjit_call_p = (mjit_cancel_p ? false : original_call_p); \
    mjit_stats_p = mjit_opts.stats; \
    global_hooks->events = rb_mjit_global_events; \
    if (!was_disabled) rb_gc_enable(); \
} while (0);

void
rb_mjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop)
{
    if (!mjit_call_p) return;
    mjit_call_p = false;
}

static void
mjit_cme_invalidate(void *data)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    WITH_MJIT_ISOLATED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_cme_invalidate"), 1, SIZET2NUM((size_t)data));
    });
}

extern int rb_workqueue_register(unsigned flags, rb_postponed_job_func_t func, void *data);

void
rb_mjit_cme_invalidate(rb_callable_method_entry_t *cme)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    // Asynchronously hook the Ruby code since running Ruby in the middle of cme invalidation is dangerous.
    rb_workqueue_register(0, mjit_cme_invalidate, (void *)cme);
}

void
rb_mjit_before_ractor_spawn(void)
{
    if (!mjit_call_p) return;
    mjit_call_p = false;
}

static void
mjit_constant_state_changed(void *data)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    WITH_MJIT_ISOLATED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_constant_state_changed"), 1, SIZET2NUM((size_t)data));
    });

    RB_VM_LOCK_LEAVE();
}

void
rb_mjit_constant_state_changed(ID id)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    // Asynchronously hook the Ruby code since this is hooked during a "Ruby critical section".
    rb_workqueue_register(0, mjit_constant_state_changed, (void *)id);
}

void
rb_mjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;

    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    WITH_MJIT_ISOLATED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_constant_ic_update"), 3,
                   SIZET2NUM((size_t)iseq), SIZET2NUM((size_t)ic), UINT2NUM(insn_idx));
    });

    RB_VM_LOCK_LEAVE();
}

void
rb_mjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    WITH_MJIT_ISOLATED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_tracing_invalidate_all"), 1, UINT2NUM(new_iseq_events));
    });
}

static void
mjit_iseq_update_references(void *data)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    WITH_MJIT_ISOLATED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_update_references"), 0);
    });
}

void
rb_mjit_iseq_update_references(struct rb_iseq_constant_body *const body)
{
    if (!mjit_enabled) return;

    if (body->mjit_blocks) {
        body->mjit_blocks = rb_gc_location(body->mjit_blocks);
    }

    // Asynchronously hook the Ruby code to avoid allocation during GC.compact.
    // Using _one because it's too slow to invalidate all for each ISEQ. Thus
    // not giving an ISEQ pointer.
    rb_postponed_job_register_one(0, mjit_iseq_update_references, NULL);
}

void
rb_mjit_iseq_mark(VALUE mjit_blocks)
{
    if (!mjit_enabled) return;

    // Note: This wasn't enough for some reason.
    // We actually rely on RubyVM::MJIT::GC_REFS to mark this.
    if (mjit_blocks) {
        rb_gc_mark_movable(mjit_blocks);
    }
}

// TODO: Use this in more places
VALUE
rb_mjit_iseq_new(rb_iseq_t *iseq)
{
    return rb_funcall(rb_cMJITIseqPtr, rb_intern("new"), 1, SIZET2NUM((size_t)iseq));
}

void
rb_mjit_compile(const rb_iseq_t *iseq)
{
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    WITH_MJIT_ISOLATED({
        VALUE iseq_ptr = rb_funcall(rb_cMJITIseqPtr, rb_intern("new"), 1, SIZET2NUM((size_t)iseq));
        VALUE cfp_ptr = rb_funcall(rb_cMJITCfpPtr, rb_intern("new"), 1, SIZET2NUM((size_t)GET_EC()->cfp));
        rb_funcall(rb_MJITCompiler, rb_intern("compile"), 2, iseq_ptr, cfp_ptr);
    });

    RB_VM_LOCK_LEAVE();
}

void *
rb_mjit_branch_stub_hit(VALUE branch_stub, int sp_offset, int target0_p)
{
    VALUE result;

    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    rb_control_frame_t *cfp = GET_EC()->cfp;
    cfp->sp += sp_offset; // preserve stack values, also using the actual sp_offset to make jit.peek_at_stack work

    WITH_MJIT_ISOLATED({
        VALUE cfp_ptr = rb_funcall(rb_cMJITCfpPtr, rb_intern("new"), 1, SIZET2NUM((size_t)cfp));
        result = rb_funcall(rb_MJITCompiler, rb_intern("branch_stub_hit"), 3, branch_stub, cfp_ptr, RBOOL(target0_p));
    });

    cfp->sp -= sp_offset; // reset for consistency with the code without the stub

    RB_VM_LOCK_LEAVE();

    return (void *)NUM2SIZET(result);
}

// Called by rb_vm_mark()
void
mjit_mark(void)
{
    if (!mjit_enabled)
        return;
    RUBY_MARK_ENTER("mjit");

    // Pin object pointers used in this file
    rb_gc_mark(rb_MJITCompiler);
    rb_gc_mark(rb_cMJITIseqPtr);
    rb_gc_mark(rb_cMJITCfpPtr);
    rb_gc_mark(rb_mMJITHooks);

    RUBY_MARK_LEAVE("mjit");
}

void
mjit_init(const struct mjit_options *opts)
{
    VM_ASSERT(mjit_enabled);
    mjit_opts = *opts;

    extern uint8_t* rb_yjit_reserve_addr_space(uint32_t mem_size);
    rb_mjit_mem_block = rb_yjit_reserve_addr_space(MJIT_CODE_SIZE);

    // MJIT doesn't support miniruby, but it might reach here by MJIT_FORCE_ENABLE.
    rb_mMJIT = rb_const_get(rb_cRubyVM, rb_intern("MJIT"));
    if (!rb_const_defined(rb_mMJIT, rb_intern("Compiler"))) {
        verbose(1, "Disabling MJIT because RubyVM::MJIT::Compiler is not defined");
        mjit_enabled = false;
        return;
    }
    rb_mMJITC = rb_const_get(rb_mMJIT, rb_intern("C"));
    VALUE rb_cMJITCompiler = rb_const_get(rb_mMJIT, rb_intern("Compiler"));
    rb_MJITCompiler = rb_funcall(rb_cMJITCompiler, rb_intern("new"), 2,
                                 SIZET2NUM((size_t)rb_mjit_mem_block), UINT2NUM(MJIT_CODE_SIZE));
    rb_cMJITIseqPtr = rb_funcall(rb_mMJITC, rb_intern("rb_iseq_t"), 0);
    rb_cMJITCfpPtr = rb_funcall(rb_mMJITC, rb_intern("rb_control_frame_t"), 0);
    rb_mMJITHooks = rb_const_get(rb_mMJIT, rb_intern("Hooks"));

    mjit_call_p = true;
    mjit_stats_p = mjit_opts.stats;

    // Normalize options
    if (mjit_opts.call_threshold == 0)
        mjit_opts.call_threshold = DEFAULT_CALL_THRESHOLD;
#ifndef HAVE_LIBCAPSTONE
    if (mjit_opts.dump_disasm)
        verbose(1, "libcapstone has not been linked. Ignoring --mjit-dump-disasm.");
#endif
}

void
mjit_finish(bool close_handle_p)
{
    // TODO: implement
}

// Same as `RubyVM::MJIT::C.enabled?`, but this is used before mjit_init.
static VALUE
mjit_stats_enabled_p(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(mjit_stats_enabled);
}

// Disable anything that could impact stats. It ends up disabling JIT calls as well.
static VALUE
mjit_stop_stats(rb_execution_context_t *ec, VALUE self)
{
    mjit_call_p = false;
    mjit_stats_p = false;
    return Qnil;
}

#include "mjit.rbinc"

#endif // USE_MJIT
