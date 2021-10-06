#ifndef RUBY_MJIT_H
#define RUBY_MJIT_H 1
/**********************************************************************

  mjit.h - Interface to MRI method JIT compiler for Ruby's main thread

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

#include "ruby/internal/config.h" // defines USE_MJIT
#include "ruby/internal/stdbool.h"
#include "vm_core.h"

# if USE_MJIT

#include "debug_counter.h"
#include "ruby.h"
#include "vm_core.h"
#include "yjit.h"

// Special address values of a function generated from the
// corresponding iseq by MJIT:
enum rb_mjit_iseq_func {
    // ISEQ has never been enqueued to unit_queue yet
    NOT_ADDED_JIT_ISEQ_FUNC = 0,
    // ISEQ is already queued for the machine code generation but the
    // code is not ready yet for the execution
    NOT_READY_JIT_ISEQ_FUNC = 1,
    // ISEQ included not compilable insn, some internal assertion failed
    // or the unit is unloaded
    NOT_COMPILED_JIT_ISEQ_FUNC = 2,
    // End mark
    LAST_JIT_ISEQ_FUNC = 3
};

// MJIT options which can be defined on the MRI command line.
struct mjit_options {
    // Converted from "jit" feature flag to tell the enablement
    // information to ruby_show_version().
    char on;
    // Save temporary files after MRI finish.  The temporary files
    // include the pre-compiled header, C code file generated for ISEQ,
    // and the corresponding object file.
    char save_temps;
    // Print MJIT warnings to stderr.
    char warnings;
    // Disable compiler optimization and add debug symbols. It can be
    // very slow.
    char debug;
    // Add arbitrary cflags.
    char* debug_flags;
    // If not 0, all ISeqs are synchronously compiled. For testing.
    unsigned int wait;
    // Number of calls to trigger JIT compilation. For testing.
    unsigned int min_calls;
    // Force printing info about MJIT work of level VERBOSE or
    // less. 0=silence, 1=medium, 2=verbose.
    int verbose;
    // Maximal permitted number of iseq JIT codes in a MJIT memory
    // cache.
    int max_cache_size;
};

// State of optimization switches
struct rb_mjit_compile_info {
    // Disable getinstancevariable/setinstancevariable optimizations based on inline cache (T_OBJECT)
    bool disable_ivar_cache;
    // Disable getinstancevariable/setinstancevariable optimizations based on inline cache (FL_EXIVAR)
    bool disable_exivar_cache;
    // Disable send/opt_send_without_block optimizations based on inline cache
    bool disable_send_cache;
    // Disable method inlining
    bool disable_inlining;
    // Disable opt_getinlinecache inlining
    bool disable_const_cache;
};

typedef VALUE (*mjit_func_t)(rb_execution_context_t *, rb_control_frame_t *);

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN struct mjit_options mjit_opts;
RUBY_EXTERN bool mjit_call_p;

extern void rb_mjit_add_iseq_to_process(const rb_iseq_t *iseq);
extern VALUE rb_mjit_wait_call(rb_execution_context_t *ec, struct rb_iseq_constant_body *body);
extern struct rb_mjit_compile_info* rb_mjit_iseq_compile_info(const struct rb_iseq_constant_body *body);
extern void rb_mjit_recompile_send(const rb_iseq_t *iseq);
extern void rb_mjit_recompile_ivar(const rb_iseq_t *iseq);
extern void rb_mjit_recompile_exivar(const rb_iseq_t *iseq);
extern void rb_mjit_recompile_inlining(const rb_iseq_t *iseq);
extern void rb_mjit_recompile_const(const rb_iseq_t *iseq);
RUBY_SYMBOL_EXPORT_END

extern void mjit_cancel_all(const char *reason);
extern bool mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id);
extern void mjit_init(const struct mjit_options *opts);
extern void mjit_gc_start_hook(void);
extern void mjit_gc_exit_hook(void);
extern void mjit_free_iseq(const rb_iseq_t *iseq);
extern void mjit_update_references(const rb_iseq_t *iseq);
extern void mjit_mark(void);
extern struct mjit_cont *mjit_cont_new(rb_execution_context_t *ec);
extern void mjit_cont_free(struct mjit_cont *cont);
extern void mjit_mark_cc_entries(const struct rb_iseq_constant_body *const body);

#  ifdef MJIT_HEADER
NOINLINE(static COLDFUNC VALUE mjit_exec_slowpath(rb_execution_context_t *ec, const rb_iseq_t *iseq, struct rb_iseq_constant_body *body));
#  else
static inline VALUE mjit_exec_slowpath(rb_execution_context_t *ec, const rb_iseq_t *iseq, struct rb_iseq_constant_body *body);
#  endif
static VALUE
mjit_exec_slowpath(rb_execution_context_t *ec, const rb_iseq_t *iseq, struct rb_iseq_constant_body *body)
{
    uintptr_t func_i = (uintptr_t)(body->jit_func);
    ASSUME(func_i <= LAST_JIT_ISEQ_FUNC);
    switch ((enum rb_mjit_iseq_func)func_i) {
      case NOT_ADDED_JIT_ISEQ_FUNC:
        RB_DEBUG_COUNTER_INC(mjit_exec_not_added);
        if (body->total_calls == mjit_opts.min_calls) {
            rb_mjit_add_iseq_to_process(iseq);
            if (UNLIKELY(mjit_opts.wait)) {
                return rb_mjit_wait_call(ec, body);
            }
        }
        break;
      case NOT_READY_JIT_ISEQ_FUNC:
        RB_DEBUG_COUNTER_INC(mjit_exec_not_ready);
        break;
      case NOT_COMPILED_JIT_ISEQ_FUNC:
        RB_DEBUG_COUNTER_INC(mjit_exec_not_compiled);
        break;
      default: // to avoid warning with LAST_JIT_ISEQ_FUNC
        break;
    }
    return Qundef;
}

// Try to execute the current iseq in ec.  Use JIT code if it is ready.
// If it is not, add ISEQ to the compilation queue and return Qundef for MJIT.
// YJIT compiles on the thread running the iseq.
static inline VALUE
mjit_exec(rb_execution_context_t *ec)
{
    const rb_iseq_t *iseq = ec->cfp->iseq;
    struct rb_iseq_constant_body *body = iseq->body;
    bool yjit_enabled = false;
#ifndef MJIT_HEADER
    // Don't want to compile with YJIT or use code generated by YJIT
    // when running inside code generated by MJIT.
    yjit_enabled = rb_yjit_enabled_p();
#endif

    if (mjit_call_p || yjit_enabled) {
        body->total_calls++;
    }

#ifndef MJIT_HEADER
    if (yjit_enabled && !mjit_call_p && body->total_calls == rb_yjit_call_threshold())  {
        // If we couldn't generate any code for this iseq, then return
        // Qundef so the interpreter will handle the call.
        if (!rb_yjit_compile_iseq(iseq, ec)) {
            return Qundef;
        }
    }
#endif

    if (!(mjit_call_p || yjit_enabled))
        return Qundef;

    RB_DEBUG_COUNTER_INC(mjit_exec);

    mjit_func_t func = body->jit_func;

    // YJIT tried compiling this function once before and couldn't do
    // it, so return Qundef so the interpreter handles it.
    if (yjit_enabled && func == 0) {
        return Qundef;
    }

    if (UNLIKELY((uintptr_t)func <= LAST_JIT_ISEQ_FUNC)) {
#  ifdef MJIT_HEADER
        RB_DEBUG_COUNTER_INC(mjit_frame_JT2VM);
#  else
        RB_DEBUG_COUNTER_INC(mjit_frame_VM2VM);
#  endif
        return mjit_exec_slowpath(ec, iseq, body);
    }

#  ifdef MJIT_HEADER
    RB_DEBUG_COUNTER_INC(mjit_frame_JT2JT);
#  else
    RB_DEBUG_COUNTER_INC(mjit_frame_VM2JT);
#  endif
    RB_DEBUG_COUNTER_INC(mjit_exec_call_func);
    // Under SystemV x64 calling convention
    // ec -> RDI
    // cfp -> RSI
    return func(ec, ec->cfp);
}

void mjit_child_after_fork(void);

#  ifdef MJIT_HEADER
#define mjit_enabled true
#  else // MJIT_HEADER
extern bool mjit_enabled;
#  endif // MJIT_HEADER
VALUE mjit_pause(bool wait_p);
VALUE mjit_resume(void);
void mjit_finish(bool close_handle_p);

# else // USE_MJIT

static inline void mjit_cancel_all(const char *reason){}
static inline struct mjit_cont *mjit_cont_new(rb_execution_context_t *ec){return NULL;}
static inline void mjit_cont_free(struct mjit_cont *cont){}
static inline void mjit_gc_start_hook(void){}
static inline void mjit_gc_exit_hook(void){}
static inline void mjit_free_iseq(const rb_iseq_t *iseq){}
static inline void mjit_mark(void){}
static inline VALUE mjit_exec(rb_execution_context_t *ec) { return Qundef; /* unreachable */ }
static inline void mjit_child_after_fork(void){}

#define mjit_enabled false
static inline VALUE mjit_pause(bool wait_p){ return Qnil; } // unreachable
static inline VALUE mjit_resume(void){ return Qnil; } // unreachable
static inline void mjit_finish(bool close_handle_p){}

# endif // USE_MJIT
#endif // RUBY_MJIT_H
