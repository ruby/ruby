/**********************************************************************

  rjit.c - Ruby JIT compiler functions

  Copyright (C) 2023 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "ruby/internal/config.h" // defines USE_RJIT

// ISO C requires a translation unit to contain at least one declaration
void rb_rjit(void) {}

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
#include "rjit.h"
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
struct rjit_options rjit_opts;

// true if RJIT is enabled.
bool rjit_enabled = false;
bool rjit_stats_enabled = false;
// true if JIT-ed code should be called. When `ruby_vm_event_enabled_global_flags & ISEQ_TRACE_EVENTS`
// and `rjit_call_p == false`, any JIT-ed code execution is cancelled as soon as possible.
bool rjit_call_p = false;
// A flag to communicate that rjit_call_p should be disabled while it's temporarily false.
bool rjit_cancel_p = false;

// Print the arguments according to FORMAT to stderr only if RJIT
// verbose option value is more or equal to LEVEL.
PRINTF_ARGS(static void, 2, 3)
verbose(int level, const char *format, ...)
{
    if (rjit_opts.verbose >= level) {
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
rjit_capture_cc_entries(const struct rb_iseq_constant_body *compiled_iseq, const struct rb_iseq_constant_body *captured_iseq)
{
    // TODO: remove this
    return 0;
}

void
rjit_cancel_all(const char *reason)
{
    if (!rjit_enabled)
        return;

    rjit_call_p = false;
    rjit_cancel_p = true;
    if (rjit_opts.warnings || rjit_opts.verbose) {
        fprintf(stderr, "JIT cancel: Disabled JIT-ed code because %s\n", reason);
    }
}

void
rjit_free_iseq(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rjit_notify_waitpid(int exit_code)
{
    // TODO: remove this function
}

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

void
rb_rjit_add_iseq_to_process(const rb_iseq_t *iseq)
{
    // TODO: implement
}

struct rb_rjit_compile_info*
rb_rjit_iseq_compile_info(const struct rb_iseq_constant_body *body)
{
    // TODO: remove this
    return NULL;
}

void
rb_rjit_recompile_send(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rb_rjit_recompile_ivar(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rb_rjit_recompile_exivar(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rb_rjit_recompile_inlining(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

void
rb_rjit_recompile_const(const rb_iseq_t *iseq)
{
    // TODO: remove this
}

// Default permitted number of units with a JIT code kept in memory.
#define DEFAULT_MAX_CACHE_SIZE 100
// A default threshold used to add iseq to JIT.
#define DEFAULT_CALL_THRESHOLD 30

#define opt_match_noarg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? (rb_warn("argument to --rjit-" name " is ignored"), 1) : 1)
#define opt_match_arg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? 1 : (rb_raise(rb_eRuntimeError, "--rjit-" name " needs an argument"), 0))

void
rjit_setup_options(const char *s, struct rjit_options *rjit_opt)
{
    const size_t l = strlen(s);
    if (l == 0) {
        return;
    }
    else if (opt_match_noarg(s, l, "stats")) {
        rjit_opt->stats = true;
    }
    else if (opt_match_arg(s, l, "call-threshold")) {
        rjit_opt->call_threshold = atoi(s + 1);
    }
    // --rjit=pause is an undocumented feature for experiments
    else if (opt_match_noarg(s, l, "pause")) {
        rjit_opt->pause = true;
    }
    else if (opt_match_noarg(s, l, "dump-disasm")) {
        rjit_opt->dump_disasm = true;
    }
    else {
        rb_raise(rb_eRuntimeError,
                 "invalid RJIT option `%s' (--help will show valid RJIT options)", s);
    }
}

#define M(shortopt, longopt, desc) RUBY_OPT_MESSAGE(shortopt, longopt, desc)
const struct ruby_opt_message rjit_option_messages[] = {
    M("--rjit-stats",              "", "Enable collecting RJIT statistics"),
    M("--rjit-call-threshold=num", "", "Number of calls to trigger JIT (default: " STRINGIZE(DEFAULT_CALL_THRESHOLD) ")"),
#if RUBY_DEBUG
    M("--rjit-dump-disasm",        "", "Dump all JIT code"),
#endif
    {0}
};
#undef M

VALUE
rjit_pause(bool wait_p)
{
    // TODO: remove this
    return Qtrue;
}

VALUE
rjit_resume(void)
{
    // TODO: remove this
    return Qnil;
}

void
rjit_child_after_fork(void)
{
    // TODO: remove this
}

// Compile ISeq to C code in `f`. It returns true if it succeeds to compile.
bool
rjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id)
{
    // TODO: implement
    return false;
}

//================================================================================
//
// New stuff from here
//

#if defined(MAP_FIXED_NOREPLACE) && defined(_SC_PAGESIZE)
// Align the current write position to a multiple of bytes
static uint8_t *
align_ptr(uint8_t *ptr, uint32_t multiple)
{
    // Compute the pointer modulo the given alignment boundary
    uint32_t rem = ((uint32_t)(uintptr_t)ptr) % multiple;

    // If the pointer is already aligned, stop
    if (rem == 0)
        return ptr;

    // Pad the pointer by the necessary amount to align it
    uint32_t pad = multiple - rem;

    return ptr + pad;
}
#endif

// Address space reservation. Memory pages are mapped on an as needed basis.
// See the Rust mm module for details.
static uint8_t *
rb_rjit_reserve_addr_space(uint32_t mem_size)
{
#ifndef _WIN32
    uint8_t *mem_block;

    // On Linux
    #if defined(MAP_FIXED_NOREPLACE) && defined(_SC_PAGESIZE)
        uint32_t const page_size = (uint32_t)sysconf(_SC_PAGESIZE);
        uint8_t *const cfunc_sample_addr = (void *)&rb_rjit_reserve_addr_space;
        uint8_t *const probe_region_end = cfunc_sample_addr + INT32_MAX;
        // Align the requested address to page size
        uint8_t *req_addr = align_ptr(cfunc_sample_addr, page_size);

        // Probe for addresses close to this function using MAP_FIXED_NOREPLACE
        // to improve odds of being in range for 32-bit relative call instructions.
        do {
            mem_block = mmap(
                req_addr,
                mem_size,
                PROT_NONE,
                MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE,
                -1,
                0
            );

            // If we succeeded, stop
            if (mem_block != MAP_FAILED) {
                break;
            }

            // +4MB
            req_addr += 4 * 1024 * 1024;
        } while (req_addr < probe_region_end);

    // On MacOS and other platforms
    #else
        // Try to map a chunk of memory as executable
        mem_block = mmap(
            (void *)rb_rjit_reserve_addr_space,
            mem_size,
            PROT_NONE,
            MAP_PRIVATE | MAP_ANONYMOUS,
            -1,
            0
        );
    #endif

    // Fallback
    if (mem_block == MAP_FAILED) {
        // Try again without the address hint (e.g., valgrind)
        mem_block = mmap(
            NULL,
            mem_size,
            PROT_NONE,
            MAP_PRIVATE | MAP_ANONYMOUS,
            -1,
            0
        );
    }

    // Check that the memory mapping was successful
    if (mem_block == MAP_FAILED) {
        perror("ruby: yjit: mmap:");
        if(errno == ENOMEM) {
            // No crash report if it's only insufficient memory
            exit(EXIT_FAILURE);
        }
        rb_bug("mmap failed");
    }

    return mem_block;
#else
    // Windows not supported for now
    return NULL;
#endif
}

// JIT buffer
uint8_t *rb_rjit_mem_block = NULL;

// `rb_ec_ractor_hooks(ec)->events` is moved to this variable during compilation.
rb_event_flag_t rb_rjit_global_events = 0;

// Basically rjit_opts.stats, but this becomes false during RJIT compilation.
static bool rjit_stats_p = false;

#if RJIT_STATS

struct rb_rjit_runtime_counters rb_rjit_counters = { 0 };

void
rb_rjit_collect_vm_usage_insn(int insn)
{
    if (!rjit_stats_p) return;
    rb_rjit_counters.vm_insns_count++;
}

#endif // YJIT_STATS

extern VALUE rb_gc_enable(void);
extern VALUE rb_gc_disable(void);

#define WITH_RJIT_ISOLATED(stmt) do { \
    VALUE was_disabled = rb_gc_disable(); \
    rb_hook_list_t *global_hooks = rb_ec_ractor_hooks(GET_EC()); \
    rb_rjit_global_events = global_hooks->events; \
    global_hooks->events = 0; \
    bool original_call_p = rjit_call_p; \
    rjit_stats_p = false; \
    rjit_call_p = false; \
    stmt; \
    rjit_call_p = (rjit_cancel_p ? false : original_call_p); \
    rjit_stats_p = rjit_opts.stats; \
    global_hooks->events = rb_rjit_global_events; \
    if (!was_disabled) rb_gc_enable(); \
} while (0);

void
rb_rjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop)
{
    if (!rjit_call_p) return;
    rjit_call_p = false;
}

static void
rjit_cme_invalidate(void *data)
{
    if (!rjit_enabled || !rjit_call_p || !rb_mRJITHooks) return;
    WITH_RJIT_ISOLATED({
        rb_funcall(rb_mRJITHooks, rb_intern("on_cme_invalidate"), 1, SIZET2NUM((size_t)data));
    });
}

extern int rb_workqueue_register(unsigned flags, rb_postponed_job_func_t func, void *data);

void
rb_rjit_cme_invalidate(rb_callable_method_entry_t *cme)
{
    if (!rjit_enabled || !rjit_call_p || !rb_mRJITHooks) return;
    // Asynchronously hook the Ruby code since running Ruby in the middle of cme invalidation is dangerous.
    rb_workqueue_register(0, rjit_cme_invalidate, (void *)cme);
}

void
rb_rjit_before_ractor_spawn(void)
{
    if (!rjit_call_p) return;
    rjit_call_p = false;
}

static void
rjit_constant_state_changed(void *data)
{
    if (!rjit_enabled || !rjit_call_p || !rb_mRJITHooks) return;
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
    if (!rjit_enabled || !rjit_call_p || !rb_mRJITHooks) return;
    // Asynchronously hook the Ruby code since this is hooked during a "Ruby critical section".
    rb_workqueue_register(0, rjit_constant_state_changed, (void *)id);
}

void
rb_rjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx)
{
    if (!rjit_enabled || !rjit_call_p || !rb_mRJITHooks) return;

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
    if (!rjit_enabled || !rjit_call_p || !rb_mRJITHooks) return;
    WITH_RJIT_ISOLATED({
        rb_funcall(rb_mRJITHooks, rb_intern("on_tracing_invalidate_all"), 1, UINT2NUM(new_iseq_events));
    });
}

static void
rjit_iseq_update_references(void *data)
{
    if (!rjit_enabled || !rjit_call_p || !rb_mRJITHooks) return;
    WITH_RJIT_ISOLATED({
        rb_funcall(rb_mRJITHooks, rb_intern("on_update_references"), 0);
    });
}

void
rb_rjit_iseq_update_references(struct rb_iseq_constant_body *const body)
{
    if (!rjit_enabled) return;

    if (body->rjit_blocks) {
        body->rjit_blocks = rb_gc_location(body->rjit_blocks);
    }

    // Asynchronously hook the Ruby code to avoid allocation during GC.compact.
    // Using _one because it's too slow to invalidate all for each ISEQ. Thus
    // not giving an ISEQ pointer.
    rb_postponed_job_register_one(0, rjit_iseq_update_references, NULL);
}

void
rb_rjit_iseq_mark(VALUE rjit_blocks)
{
    if (!rjit_enabled) return;

    // Note: This wasn't enough for some reason.
    // We actually rely on RubyVM::RJIT::GC_REFS to mark this.
    if (rjit_blocks) {
        rb_gc_mark_movable(rjit_blocks);
    }
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

    WITH_RJIT_ISOLATED({
        VALUE iseq_ptr = rb_funcall(rb_cRJITIseqPtr, rb_intern("new"), 1, SIZET2NUM((size_t)iseq));
        VALUE cfp_ptr = rb_funcall(rb_cRJITCfpPtr, rb_intern("new"), 1, SIZET2NUM((size_t)GET_EC()->cfp));
        rb_funcall(rb_RJITCompiler, rb_intern("compile"), 2, iseq_ptr, cfp_ptr);
    });

    RB_VM_LOCK_LEAVE();
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

// Called by rb_vm_mark()
void
rjit_mark(void)
{
    if (!rjit_enabled)
        return;
    RUBY_MARK_ENTER("rjit");

    // Pin object pointers used in this file
    rb_gc_mark(rb_RJITCompiler);
    rb_gc_mark(rb_cRJITIseqPtr);
    rb_gc_mark(rb_cRJITCfpPtr);
    rb_gc_mark(rb_mRJITHooks);

    RUBY_MARK_LEAVE("rjit");
}

void
rjit_init(const struct rjit_options *opts)
{
    VM_ASSERT(rjit_enabled);
    rjit_opts = *opts;

    rb_rjit_mem_block = rb_rjit_reserve_addr_space(RJIT_CODE_SIZE);

    // RJIT doesn't support miniruby, but it might reach here by RJIT_FORCE_ENABLE.
    rb_mRJIT = rb_const_get(rb_cRubyVM, rb_intern("RJIT"));
    if (!rb_const_defined(rb_mRJIT, rb_intern("Compiler"))) {
        verbose(1, "Disabling RJIT because RubyVM::RJIT::Compiler is not defined");
        rjit_enabled = false;
        return;
    }
    rb_mRJITC = rb_const_get(rb_mRJIT, rb_intern("C"));
    VALUE rb_cRJITCompiler = rb_const_get(rb_mRJIT, rb_intern("Compiler"));
    rb_RJITCompiler = rb_funcall(rb_cRJITCompiler, rb_intern("new"), 2,
                                 SIZET2NUM((size_t)rb_rjit_mem_block), UINT2NUM(RJIT_CODE_SIZE));
    rb_cRJITIseqPtr = rb_funcall(rb_mRJITC, rb_intern("rb_iseq_t"), 0);
    rb_cRJITCfpPtr = rb_funcall(rb_mRJITC, rb_intern("rb_control_frame_t"), 0);
    rb_mRJITHooks = rb_const_get(rb_mRJIT, rb_intern("Hooks"));

    rjit_call_p = true;
    rjit_stats_p = rjit_opts.stats;

    // Normalize options
    if (rjit_opts.call_threshold == 0)
        rjit_opts.call_threshold = DEFAULT_CALL_THRESHOLD;
#ifndef HAVE_LIBCAPSTONE
    if (rjit_opts.dump_disasm)
        verbose(1, "libcapstone has not been linked. Ignoring --rjit-dump-disasm.");
#endif
}

void
rjit_finish(bool close_handle_p)
{
    // TODO: implement
}

// Same as `RubyVM::RJIT::C.enabled?`, but this is used before rjit_init.
static VALUE
rjit_stats_enabled_p(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(rjit_stats_enabled);
}

// Disable anything that could impact stats. It ends up disabling JIT calls as well.
static VALUE
rjit_stop_stats(rb_execution_context_t *ec, VALUE self)
{
    rjit_call_p = false;
    rjit_stats_p = false;
    return Qnil;
}

#include "rjit.rbinc"

#endif // USE_RJIT
