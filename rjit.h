#ifndef RUBY_RJIT_H
#define RUBY_RJIT_H 1
/**********************************************************************

  rjit.h - Interface to RJIT

  Copyright (C) 2023 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "ruby/internal/config.h" // defines USE_RJIT
#include "ruby/internal/stdbool.h"
#include "vm_core.h"

# if USE_RJIT

#ifndef RJIT_STATS
# define RJIT_STATS RUBY_DEBUG
#endif

#include "ruby.h"
#include "vm_core.h"

// Special address values of a function generated from the
// corresponding iseq by RJIT:
enum rb_rjit_func_state {
    // ISEQ has not been compiled yet
    RJIT_FUNC_NOT_COMPILED = 0,
    // ISEQ is already queued for the machine code generation but the
    // code is not ready yet for the execution
    RJIT_FUNC_COMPILING = 1,
    // ISEQ included not compilable insn, some internal assertion failed
    // or the unit is unloaded
    RJIT_FUNC_FAILED = 2,
};
// Return true if jit_func is part of enum rb_rjit_func_state
#define RJIT_FUNC_STATE_P(jit_func) ((uintptr_t)(jit_func) <= (uintptr_t)RJIT_FUNC_FAILED)

// RJIT options which can be defined on the MRI command line.
struct rjit_options {
    // Converted from "jit" feature flag to tell the enablement
    // information to ruby_show_version().
    bool on;
    // Save temporary files after MRI finish.  The temporary files
    // include the pre-compiled header, C code file generated for ISEQ,
    // and the corresponding object file.
    bool save_temps;
    // Print RJIT warnings to stderr.
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
    // Collect RJIT statistics
    bool stats;
    // Force printing info about RJIT work of level VERBOSE or
    // less. 0=silence, 1=medium, 2=verbose.
    int verbose;
    // Maximal permitted number of iseq JIT codes in a RJIT memory
    // cache.
    int max_cache_size;
    // [experimental] Do not start RJIT until RJIT.resume is called.
    bool pause;
    // [experimental] Call custom RubyVM::RJIT.compile instead of RJIT.
    bool custom;
    // Enable disasm of all JIT code
    bool dump_disasm;
};

// State of optimization switches
struct rb_rjit_compile_info {
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

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN struct rjit_options rjit_opts;
RUBY_EXTERN bool rjit_call_p;

#define rb_rjit_call_threshold() rjit_opts.call_threshold

extern void rb_rjit_compile(const rb_iseq_t *iseq);
extern struct rb_rjit_compile_info* rb_rjit_iseq_compile_info(const struct rb_iseq_constant_body *body);
extern void rb_rjit_recompile_send(const rb_iseq_t *iseq);
extern void rb_rjit_recompile_ivar(const rb_iseq_t *iseq);
extern void rb_rjit_recompile_exivar(const rb_iseq_t *iseq);
extern void rb_rjit_recompile_inlining(const rb_iseq_t *iseq);
extern void rb_rjit_recompile_const(const rb_iseq_t *iseq);
RUBY_SYMBOL_EXPORT_END

extern void rjit_cancel_all(const char *reason);
extern bool rjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id);
extern void rjit_init(const struct rjit_options *opts);
extern void rjit_free_iseq(const rb_iseq_t *iseq);
extern void rb_rjit_iseq_update_references(struct rb_iseq_constant_body *const body);
extern void rjit_mark(void);
extern void rb_rjit_iseq_mark(VALUE rjit_blocks);
extern void rjit_notify_waitpid(int exit_code);

extern void rb_rjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop);
extern void rb_rjit_cme_invalidate(rb_callable_method_entry_t *cme);
extern void rb_rjit_before_ractor_spawn(void);
extern void rb_rjit_constant_state_changed(ID id);
extern void rb_rjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx);
extern void rb_rjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events);

void rjit_child_after_fork(void);

extern void rb_rjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop);
extern void rb_rjit_before_ractor_spawn(void);
extern void rb_rjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events);
extern void rb_rjit_collect_vm_usage_insn(int insn);

extern bool rjit_enabled;
extern bool rjit_stats_enabled;
VALUE rjit_pause(bool wait_p);
VALUE rjit_resume(void);
void rjit_finish(bool close_handle_p);

# else // USE_RJIT

static inline void rb_rjit_compile(const rb_iseq_t *iseq){}

static inline void rjit_cancel_all(const char *reason){}
static inline void rjit_free_iseq(const rb_iseq_t *iseq){}
static inline void rjit_mark(void){}
static inline void rjit_child_after_fork(void){}

static inline void rb_rjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop) {}
static inline void rb_rjit_cme_invalidate(rb_callable_method_entry_t *cme) {}
static inline void rb_rjit_before_ractor_spawn(void) {}
static inline void rb_rjit_constant_state_changed(ID id) {}
static inline void rb_rjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx) {}
static inline void rb_rjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events) {}

#define rjit_enabled false
#define rjit_call_p false
#define rjit_stats_enabled false

#define rb_rjit_call_threshold() UINT_MAX

static inline VALUE rjit_pause(bool wait_p){ return Qnil; } // unreachable
static inline VALUE rjit_resume(void){ return Qnil; } // unreachable
static inline void rjit_finish(bool close_handle_p){}

static inline void rb_rjit_collect_vm_usage_insn(int insn) {}

# endif // USE_RJIT
#endif // RUBY_RJIT_H
