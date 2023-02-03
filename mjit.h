#ifndef RUBY_MJIT_H
#define RUBY_MJIT_H 1
/**********************************************************************

  mjit.h - Interface to MRI method JIT compiler

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.
  Copyright (C) 2017 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "ruby/internal/config.h" // defines USE_MJIT
#include "ruby/internal/stdbool.h"
#include "vm_core.h"

# if USE_MJIT

#include "ruby.h"
#include "vm_core.h"

// Special address values of a function generated from the
// corresponding iseq by MJIT:
enum rb_mjit_func_state {
    // ISEQ has not been compiled yet
    MJIT_FUNC_NOT_COMPILED = 0,
    // ISEQ is already queued for the machine code generation but the
    // code is not ready yet for the execution
    MJIT_FUNC_COMPILING = 1,
    // ISEQ included not compilable insn, some internal assertion failed
    // or the unit is unloaded
    MJIT_FUNC_FAILED = 2,
};
// Return true if jit_func is part of enum rb_mjit_func_state
#define MJIT_FUNC_STATE_P(jit_func) ((uintptr_t)(jit_func) <= (uintptr_t)MJIT_FUNC_FAILED)

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
    unsigned int call_threshold;
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

typedef VALUE (*jit_func_t)(rb_execution_context_t *, rb_control_frame_t *);

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN struct mjit_options mjit_opts;
RUBY_EXTERN bool mjit_call_p;

extern void rb_mjit_add_iseq_to_process(const rb_iseq_t *iseq);
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
extern void mjit_mark_cc_entries(const struct rb_iseq_constant_body *const body);
extern void mjit_notify_waitpid(int exit_code);

extern void rb_mjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop);
extern void rb_mjit_cme_invalidate(rb_callable_method_entry_t *cme);
extern void rb_mjit_before_ractor_spawn(void);
extern void rb_mjit_constant_state_changed(ID id);
extern void rb_mjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx);
extern void rb_mjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events);

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
static inline void mjit_free_iseq(const rb_iseq_t *iseq){}
static inline void mjit_mark(void){}
static inline VALUE jit_exec(rb_execution_context_t *ec) { return Qundef; /* unreachable */ }
static inline void mjit_child_after_fork(void){}

static inline void rb_mjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop) {}
static inline void rb_mjit_cme_invalidate(rb_callable_method_entry_t *cme) {}
static inline void rb_mjit_before_ractor_spawn(void) {}
static inline void rb_mjit_constant_state_changed(ID id) {}
static inline void rb_mjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx) {}
static inline void rb_mjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events) {}

#define mjit_enabled false
static inline VALUE mjit_pause(bool wait_p){ return Qnil; } // unreachable
static inline VALUE mjit_resume(void){ return Qnil; } // unreachable
static inline void mjit_finish(bool close_handle_p){}

# endif // USE_MJIT
#endif // RUBY_MJIT_H
