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

#include "ruby.h"
#include "vm_core.h"

// RJIT options which can be defined on the MRI command line.
struct rb_rjit_options {
    // Converted from "rjit" feature flag to tell the enablement
    // information to ruby_show_version().
    bool on;
    // Size of executable memory block in MiB
    unsigned int exec_mem_size;
    // Number of calls to trigger JIT compilation
    unsigned int call_threshold;
    // Collect RJIT statistics
    bool stats;
    // Do not start RJIT until RJIT.enable is called
    bool disable;
    // Allow TracePoint during JIT compilation
    bool trace;
    // Trace side exit locations
    bool trace_exits;
    // Enable disasm of all JIT code
    bool dump_disasm;
    // Verify context objects
    bool verify_ctx;
};

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN struct rb_rjit_options rb_rjit_opts;
RUBY_EXTERN bool rb_rjit_call_p;

#define rb_rjit_call_threshold() rb_rjit_opts.call_threshold

extern void rb_rjit_compile(const rb_iseq_t *iseq);
RUBY_SYMBOL_EXPORT_END

extern void rb_rjit_cancel_all(const char *reason);
extern void rb_rjit_init(const struct rb_rjit_options *opts);
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
extern bool rb_rjit_trace_exits_enabled;

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
#define rb_rjit_trace_exits_enabled false

#define rb_rjit_call_threshold() UINT_MAX

static inline void rb_rjit_collect_vm_usage_insn(int insn) {}

# endif // USE_RJIT
#endif // RUBY_RJIT_H
