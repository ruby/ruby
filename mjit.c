/**********************************************************************

  mjit.c - MRI method JIT compiler functions

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.
  Copyright (C) 2017 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "ruby/internal/config.h" // defines USE_MJIT

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
    // TODO: remove this
}

void
mjit_update_references(const rb_iseq_t *iseq)
{
    // TODO: remove this
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
#define DEFAULT_CALL_THRESHOLD 1

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

void
mjit_mark_cc_entries(const struct rb_iseq_constant_body *const body)
{
    // TODO: implement
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

#if MJIT_STATS

struct rb_mjit_runtime_counters rb_mjit_counters = { 0 };

// Basically mjit_opts.stats, but this becomes false during MJIT compilation.
static bool mjit_stats_p = false;

void
rb_mjit_collect_vm_usage_insn(int insn)
{
    if (!mjit_stats_p) return;
    rb_mjit_counters.vm_insns_count++;
}

#endif // YJIT_STATS

void
rb_mjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop)
{
    if (!mjit_call_p) return;
    mjit_call_p = false;
}

void
rb_mjit_before_ractor_spawn(void)
{
    if (!mjit_call_p) return;
    mjit_call_p = false;
}

void
rb_mjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events)
{
    if (!mjit_call_p) return;
    mjit_call_p = false;
}

void
rb_mjit_compile(const rb_iseq_t *iseq)
{
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();
    bool original_call_p = mjit_call_p;
    mjit_call_p = false; // Avoid impacting JIT metrics by itself
    mjit_stats_p = false; // Avoid impacting JIT stats by itself

    VALUE iseq_ptr = rb_funcall(rb_cMJITIseqPtr, rb_intern("new"), 1, SIZET2NUM((size_t)iseq));
    rb_funcall(rb_MJITCompiler, rb_intern("call"), 1, iseq_ptr);

    mjit_stats_p = mjit_opts.stats;
    mjit_call_p = original_call_p;
    RB_VM_LOCK_LEAVE();
}

// Called by rb_vm_mark()
void
mjit_mark(void)
{
    if (!mjit_enabled)
        return;
    RUBY_MARK_ENTER("mjit");

    // Mark objects used by the MJIT compiler
    rb_gc_mark(rb_MJITCompiler);
    rb_gc_mark(rb_cMJITIseqPtr);

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
    rb_MJITCompiler = rb_funcall(rb_cMJITCompiler, rb_intern("new"), 1, SIZET2NUM((size_t)rb_mjit_mem_block));
    rb_cMJITIseqPtr = rb_funcall(rb_mMJITC, rb_intern("rb_iseq_t"), 0);

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

#include "mjit.rbinc"

#endif // USE_MJIT
