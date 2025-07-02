#ifndef YJIT_H
#define YJIT_H 1
//
// This file contains definitions YJIT exposes to the CRuby codebase
//

#include "ruby/internal/config.h"
#include "ruby_assert.h" // for RUBY_DEBUG
#include "vm_core.h"
#include "method.h"

// YJIT_STATS controls whether to support runtime counters in generated code
// and in the interpreter.
#ifndef YJIT_STATS
# define YJIT_STATS RUBY_DEBUG
#endif

#if USE_YJIT

// We generate x86 or arm64 assembly
#if defined(_WIN32) ? defined(_M_AMD64) : (defined(__x86_64__) || defined(__aarch64__))
// x86_64 platforms without mingw/msys or x64-mswin
#else
# error YJIT unsupported platform
#endif

// Expose these as declarations since we are building YJIT.
extern uint64_t rb_yjit_call_threshold;
extern uint64_t rb_yjit_cold_threshold;
extern uint64_t rb_yjit_live_iseq_count;
extern uint64_t rb_yjit_iseq_alloc_count;
extern bool rb_yjit_enabled_p;
void rb_yjit_incr_counter(const char *counter_name);
void rb_yjit_invalidate_all_method_lookup_assumptions(void);
void rb_yjit_cme_invalidate(rb_callable_method_entry_t *cme);
void rb_yjit_collect_binding_alloc(void);
void rb_yjit_collect_binding_set(void);
void rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception);
void rb_yjit_init(bool yjit_enabled);
void rb_yjit_free_at_exit(void);
void rb_yjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop);
void rb_yjit_constant_state_changed(ID id);
void rb_yjit_iseq_mark(void *payload);
void rb_yjit_iseq_update_references(const rb_iseq_t *iseq);
void rb_yjit_iseq_free(const rb_iseq_t *iseq);
void rb_yjit_before_ractor_spawn(void);
void rb_yjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx);
void rb_yjit_tracing_invalidate_all(void);
void rb_yjit_show_usage(int help, int highlight, unsigned int width, int columns);
void rb_yjit_lazy_push_frame(const VALUE *pc);
void rb_yjit_invalidate_no_singleton_class(VALUE klass);
void rb_yjit_invalidate_ep_is_bp(const rb_iseq_t *iseq);

#else
// !USE_YJIT
// In these builds, YJIT could never be turned on. Provide dummy implementations.

#define rb_yjit_enabled_p false
static inline void rb_yjit_incr_counter(const char *counter_name) {}
static inline void rb_yjit_invalidate_all_method_lookup_assumptions(void) {}
static inline void rb_yjit_cme_invalidate(rb_callable_method_entry_t *cme) {}
static inline void rb_yjit_collect_binding_alloc(void) {}
static inline void rb_yjit_collect_binding_set(void) {}
static inline void rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception) {}
static inline void rb_yjit_init(bool yjit_enabled) {}
static inline void rb_yjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop) {}
static inline void rb_yjit_constant_state_changed(ID id) {}
static inline void rb_yjit_iseq_mark(void *payload) {}
static inline void rb_yjit_iseq_update_references(const rb_iseq_t *iseq) {}
static inline void rb_yjit_iseq_free(const rb_iseq_t *iseq) {}
static inline void rb_yjit_before_ractor_spawn(void) {}
static inline void rb_yjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic, unsigned insn_idx) {}
static inline void rb_yjit_tracing_invalidate_all(void) {}
static inline void rb_yjit_lazy_push_frame(const VALUE *pc) {}
static inline void rb_yjit_invalidate_no_singleton_class(VALUE klass) {}
static inline void rb_yjit_invalidate_ep_is_bp(const rb_iseq_t *iseq) {}

#endif // #if USE_YJIT

#endif // #ifndef YJIT_H
