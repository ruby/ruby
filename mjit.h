/**********************************************************************

  mjit.h - Interface to MRI method JIT compiler for Ruby's main thread

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

#ifndef RUBY_MJIT_H
#define RUBY_MJIT_H 1

#include "ruby.h"
#include "debug_counter.h"

#if USE_MJIT

// Special address values of a function generated from the
// corresponding iseq by MJIT:
enum rb_mjit_iseq_func {
    // ISEQ was not queued yet for the machine code generation
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
    // Disable getinstancevariable/setinstancevariable optimizations based on inline cache
    bool disable_ivar_cache;
    // Disable send/opt_send_without_block optimizations based on inline cache
    bool disable_send_cache;
    // Disable method inlining
    bool disable_inlining;
};

typedef VALUE (*mjit_func_t)(rb_execution_context_t *, rb_control_frame_t *);

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN struct mjit_options mjit_opts;
RUBY_EXTERN bool mjit_call_p;

extern void rb_mjit_add_iseq_to_process(const rb_iseq_t *iseq);
extern VALUE rb_mjit_wait_call(rb_execution_context_t *ec, struct rb_iseq_constant_body *body);
extern struct rb_mjit_compile_info* rb_mjit_iseq_compile_info(const struct rb_iseq_constant_body *body);
extern void rb_mjit_recompile_iseq(const rb_iseq_t *iseq);
RUBY_SYMBOL_EXPORT_END

extern bool mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname);
extern void mjit_init(struct mjit_options *opts);
extern void mjit_gc_start_hook(void);
extern void mjit_gc_exit_hook(void);
extern void mjit_free_iseq(const rb_iseq_t *iseq);
extern void mjit_update_references(const rb_iseq_t *iseq);
extern void mjit_mark(void);
extern struct mjit_cont *mjit_cont_new(rb_execution_context_t *ec);
extern void mjit_cont_free(struct mjit_cont *cont);
extern void mjit_add_class_serial(rb_serial_t class_serial);
extern void mjit_remove_class_serial(rb_serial_t class_serial);

// A threshold used to reject long iseqs from JITting as such iseqs
// takes too much time to be compiled.
#define JIT_ISEQ_SIZE_THRESHOLD 1000

// Return TRUE if given ISeq body should be compiled by MJIT
static inline int
mjit_target_iseq_p(struct rb_iseq_constant_body *body)
{
    return (body->type == ISEQ_TYPE_METHOD || body->type == ISEQ_TYPE_BLOCK)
        && body->iseq_size < JIT_ISEQ_SIZE_THRESHOLD;
}

// Try to execute the current iseq in ec.  Use JIT code if it is ready.
// If it is not, add ISEQ to the compilation queue and return Qundef.
static inline VALUE
mjit_exec(rb_execution_context_t *ec)
{
    const rb_iseq_t *iseq;
    struct rb_iseq_constant_body *body;
    long unsigned total_calls;
    mjit_func_t func;

    if (!mjit_call_p)
        return Qundef;
    RB_DEBUG_COUNTER_INC(mjit_exec);

    iseq = ec->cfp->iseq;
    body = iseq->body;
    total_calls = ++body->total_calls;

    func = body->jit_func;
    if (UNLIKELY((uintptr_t)func <= (uintptr_t)LAST_JIT_ISEQ_FUNC)) {
#     ifdef MJIT_HEADER
        RB_DEBUG_COUNTER_INC(mjit_frame_JT2VM);
#     else
        RB_DEBUG_COUNTER_INC(mjit_frame_VM2VM);
#     endif
        switch ((enum rb_mjit_iseq_func)func) {
          case NOT_ADDED_JIT_ISEQ_FUNC:
            RB_DEBUG_COUNTER_INC(mjit_exec_not_added);
            if (total_calls == mjit_opts.min_calls && mjit_target_iseq_p(body)) {
                RB_DEBUG_COUNTER_INC(mjit_exec_not_added_add_iseq);
                rb_mjit_add_iseq_to_process(iseq);
                if (UNLIKELY(mjit_opts.wait)) {
                    return rb_mjit_wait_call(ec, body);
                }
            }
            return Qundef;
          case NOT_READY_JIT_ISEQ_FUNC:
            RB_DEBUG_COUNTER_INC(mjit_exec_not_ready);
            return Qundef;
          case NOT_COMPILED_JIT_ISEQ_FUNC:
            RB_DEBUG_COUNTER_INC(mjit_exec_not_compiled);
            return Qundef;
          default: // to avoid warning with LAST_JIT_ISEQ_FUNC
            break;
        }
    }

#   ifdef MJIT_HEADER
      RB_DEBUG_COUNTER_INC(mjit_frame_JT2JT);
#   else
      RB_DEBUG_COUNTER_INC(mjit_frame_VM2JT);
#   endif
    RB_DEBUG_COUNTER_INC(mjit_exec_call_func);
    return func(ec, ec->cfp);
}

void mjit_child_after_fork(void);

#else // USE_MJIT
static inline struct mjit_cont *mjit_cont_new(rb_execution_context_t *ec){return NULL;}
static inline void mjit_cont_free(struct mjit_cont *cont){}
static inline void mjit_gc_start_hook(void){}
static inline void mjit_gc_exit_hook(void){}
static inline void mjit_free_iseq(const rb_iseq_t *iseq){}
static inline void mjit_mark(void){}
static inline void mjit_add_class_serial(rb_serial_t class_serial){}
static inline void mjit_remove_class_serial(rb_serial_t class_serial){}
static inline VALUE mjit_exec(rb_execution_context_t *ec) { return Qundef; /* unreachable */ }
static inline void mjit_child_after_fork(void){}

#endif // USE_MJIT
#endif // RUBY_MJIT_H
