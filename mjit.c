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
static VALUE rb_cMJITCompiler = 0;
// RubyVM::MJIT::CPointer::Struct_rb_iseq_t
static VALUE rb_cMJITIseqPtr = 0;
// RubyVM::MJIT::CPointer::Struct_IC
static VALUE rb_cMJITICPtr = 0;
// RubyVM::MJIT::Compiler
static VALUE rb_mMJITHooks = 0;

#define WITH_MJIT_DISABLED(stmt) do { \
    bool original_call_p = mjit_call_p; \
    mjit_call_p = false; \
    stmt; \
    mjit_call_p = original_call_p; \
    if (mjit_cancel_p) mjit_call_p = false; \
} while (0);

// Hook MJIT when BOP is redefined.
MJIT_FUNC_EXPORTED void
rb_mjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    WITH_MJIT_DISABLED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_bop_redefined"), 2, INT2NUM(redefined_flag), INT2NUM((int)bop));
    });
}

// Hook MJIT when CME is invalidated.
MJIT_FUNC_EXPORTED void
rb_mjit_cme_invalidate(rb_callable_method_entry_t *cme)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    WITH_MJIT_DISABLED({
        VALUE cme_klass = rb_funcall(rb_mMJITC, rb_intern("rb_callable_method_entry_struct"), 0);
        VALUE cme_ptr = rb_funcall(cme_klass, rb_intern("new"), 1, SIZET2NUM((size_t)cme));
        rb_funcall(rb_mMJITHooks, rb_intern("on_cme_invalidate"), 1, cme_ptr);
    });
}

// Hook MJIT when Ractor is spawned.
void
rb_mjit_before_ractor_spawn(void)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    WITH_MJIT_DISABLED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_ractor_spawn"), 0);
    });
}

static void
mjit_constant_state_changed(void *data)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    ID id = (ID)data;
    WITH_MJIT_DISABLED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_constant_state_changed"), 1, ID2SYM(id));
    });
}

// Hook MJIT when constant state is changed.
MJIT_FUNC_EXPORTED void
rb_mjit_constant_state_changed(ID id)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    // Asynchronously hook the Ruby code since this is hooked during a "Ruby critical section".
    extern int rb_workqueue_register(unsigned flags, rb_postponed_job_func_t func, void *data);
    rb_workqueue_register(0, mjit_constant_state_changed, (void *)id);
}

// Hook MJIT when constant IC is updated.
MJIT_FUNC_EXPORTED void
rb_mjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    WITH_MJIT_DISABLED({
        VALUE iseq_ptr = rb_funcall(rb_cMJITIseqPtr, rb_intern("new"), 1, SIZET2NUM((size_t)iseq));
        VALUE ic_ptr = rb_funcall(rb_cMJITICPtr, rb_intern("new"), 1, SIZET2NUM((size_t)ic));
        rb_funcall(rb_mMJITHooks, rb_intern("on_constant_ic_update"), 3, iseq_ptr, ic_ptr, UINT2NUM(insn_idx));
    });
}

// Hook MJIT when TracePoint is enabled.
MJIT_FUNC_EXPORTED void
rb_mjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events)
{
    if (!mjit_enabled || !mjit_call_p || !rb_mMJITHooks) return;
    WITH_MJIT_DISABLED({
        rb_funcall(rb_mMJITHooks, rb_intern("on_tracing_invalidate_all"), 1, UINT2NUM(new_iseq_events));
    });
}

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
    // --mjit=pause is an undocumented feature for experiments
    else if (opt_match_noarg(s, l, "pause")) {
        mjit_opt->pause = true;
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
    M("--mjit-max-cache=num",      "", "Max number of methods to be JIT-ed in a cache (default: "
      STRINGIZE(DEFAULT_MAX_CACHE_SIZE) ")"),
    M("--mjit-call-threshold=num", "", "Number of calls to trigger JIT (for testing, default: "
      STRINGIZE(DEFAULT_CALL_THRESHOLD) ")"),
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

// Called by rb_vm_mark()
void
mjit_mark(void)
{
    // TODO: implement
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

//
// New stuff from here
//

void
rb_mjit_compile(const rb_iseq_t *iseq)
{
    // TODO: implement
}

void
mjit_init(const struct mjit_options *opts)
{
    VM_ASSERT(mjit_enabled);
    mjit_opts = *opts;

    // MJIT doesn't support miniruby, but it might reach here by MJIT_FORCE_ENABLE.
    rb_mMJIT = rb_const_get(rb_cRubyVM, rb_intern("MJIT"));
    if (!rb_const_defined(rb_mMJIT, rb_intern("Compiler"))) {
        verbose(1, "Disabling MJIT because RubyVM::MJIT::Compiler is not defined");
        mjit_enabled = false;
        return;
    }
    rb_mMJITC = rb_const_get(rb_mMJIT, rb_intern("C"));
    rb_cMJITCompiler = rb_funcall(rb_const_get(rb_mMJIT, rb_intern("Compiler")), rb_intern("new"), 0);
    rb_cMJITIseqPtr = rb_funcall(rb_mMJITC, rb_intern("rb_iseq_t"), 0);

    mjit_call_p = true;

    // Normalize options
    if (mjit_opts.call_threshold == 0)
        mjit_opts.call_threshold = DEFAULT_CALL_THRESHOLD;
}

void
mjit_finish(bool close_handle_p)
{
    // TODO: implement
}

#include "mjit.rbinc"

#endif // USE_MJIT
