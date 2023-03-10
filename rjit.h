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
    // Number of calls to trigger JIT compilation.
    unsigned int call_threshold;
    // Size of executable memory block in MiB
    unsigned int exec_mem_size;
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
RUBY_EXTERN struct rjit_options rb_rjit_opts;
RUBY_EXTERN bool rb_rjit_call_p;

#define rb_rjit_call_threshold() rb_rjit_opts.call_threshold

extern void rb_rjit_compile(const rb_iseq_t *iseq);
RUBY_SYMBOL_EXPORT_END

extern void rb_rjit_cancel_all(const char *reason);
extern void rb_rjit_init(const struct rjit_options *opts);
extern void rb_rjit_free_iseq(const rb_iseq_t *iseq);
extern void rb_rjit_iseq_update_references(struct rb_iseq_constant_body *const body);
extern void rb_rjit_mark(void);
extern void rb_rjit_iseq_mark(VALUE rjit_blocks);
extern void rjit_notify_waitpid(int exit_code);

extern void rb_rjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop);
extern void rb_rjit_cme_invalidate(rb_callable_method_entry_t *cme);
extern void rb_rjit_before_ractor_spawn(void);
extern void rb_rjit_constant_state_changed(ID id);
extern void rb_rjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx);
extern void rb_rjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events);

extern void rb_rjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop);
extern void rb_rjit_before_ractor_spawn(void);
extern void rb_rjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events);
extern void rb_rjit_collect_vm_usage_insn(int insn);

extern bool rb_rjit_enabled;
extern bool rb_rjit_stats_enabled;

# else // USE_RJIT

static inline void rb_rjit_compile(const rb_iseq_t *iseq){}

static inline void rb_rjit_cancel_all(const char *reason){}
static inline void rb_rjit_free_iseq(const rb_iseq_t *iseq){}
static inline void rb_rjit_mark(void){}

static inline void rb_rjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop) {}
static inline void rb_rjit_cme_invalidate(rb_callable_method_entry_t *cme) {}
static inline void rb_rjit_before_ractor_spawn(void) {}
static inline void rb_rjit_constant_state_changed(ID id) {}
static inline void rb_rjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx) {}
static inline void rb_rjit_tracing_invalidate_all(rb_event_flag_t new_iseq_events) {}

#define rb_rjit_enabled false
#define rb_rjit_call_p false
#define rb_rjit_stats_enabled false

#define rb_rjit_call_threshold() UINT_MAX

static inline void rb_rjit_collect_vm_usage_insn(int insn) {}

# endif // USE_RJIT
#endif // RUBY_RJIT_H
