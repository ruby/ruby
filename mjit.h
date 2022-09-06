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
    bool on;
    // Save temporary files after MRI finish.  The temporary files
    // include the pre-compiled header, C code file generated for ISEQ,
    // and the corresponding object file.
    bool save_temps;
    // Print MJIT warnings to stderr.
    bool warnings;
    // Disable compiler optimization and add debug symbols. It can be
    // very slow.
    bool debug;
    // Add arbitrary cflags.
    char* debug_flags;
    // If true, all ISeqs are synchronously compiled. For testing.
    bool wait;
    // Number of calls to trigger JIT compilation. For testing.
    unsigned int min_calls;
    // Force printing info about MJIT work of level VERBOSE or
    // less. 0=silence, 1=medium, 2=verbose.
    int verbose;
    // Maximal permitted number of iseq JIT codes in a MJIT memory
    // cache.
    int max_cache_size;
    // [experimental] Do not start MJIT until MJIT.resume is called.
    bool pause;
    // [experimental] Call custom RubyVM::MJIT.compile instead of MJIT.
    bool custom;
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
extern void mjit_free_iseq(const rb_iseq_t *iseq);
extern void mjit_update_references(const rb_iseq_t *iseq);
extern void mjit_mark(void);
extern struct mjit_cont *mjit_cont_new(rb_execution_context_t *ec);
extern void mjit_cont_free(struct mjit_cont *cont);
extern void mjit_mark_cc_entries(const struct rb_iseq_constant_body *const body);
extern void mjit_notify_waitpid(int exit_code);

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
static inline void mjit_free_iseq(const rb_iseq_t *iseq){}
static inline void mjit_mark(void){}
static inline VALUE jit_exec(rb_execution_context_t *ec) { return Qundef; /* unreachable */ }
static inline void mjit_child_after_fork(void){}

#define mjit_enabled false
static inline VALUE mjit_pause(bool wait_p){ return Qnil; } // unreachable
static inline VALUE mjit_resume(void){ return Qnil; } // unreachable
static inline void mjit_finish(bool close_handle_p){}

# endif // USE_MJIT
#endif // RUBY_MJIT_H
