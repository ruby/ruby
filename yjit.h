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

// We generate x86 assembly and rely on mmap(2).
#if defined(__x86_64__) && !defined(_WIN32)
# define YJIT_SUPPORTED_P 1
#else
# define YJIT_SUPPORTED_P 0
#endif

struct rb_yjit_options {
    // Enable compilation with YJIT
    bool yjit_enabled;

    // Size of the executable memory block to allocate in MiB
    unsigned exec_mem_size;

    // Number of method calls after which to start generating code
    // Threshold==1 means compile on first execution
    unsigned call_threshold;

    // Generate versions greedily until the limit is hit
    bool greedy_versioning;

    // Disable the propagation of type information
    bool no_type_prop;

    // Maximum number of versions per block
    // 1 means always create generic versions
    unsigned max_versions;

    // Capture and print out stats
    bool gen_stats;

    // Run backend tests
    bool test_backend;
};

bool rb_yjit_enabled_p(void);
unsigned rb_yjit_call_threshold(void);

void rb_yjit_invalidate_all_method_lookup_assumptions(void);
void rb_yjit_method_lookup_change(VALUE klass, ID mid);
void rb_yjit_cme_invalidate(VALUE cme);
void rb_yjit_collect_vm_usage_insn(int insn);
void rb_yjit_collect_binding_alloc(void);
void rb_yjit_collect_binding_set(void);
bool rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec);
void rb_yjit_init(struct rb_yjit_options *options);
void rb_yjit_bop_redefined(VALUE klass, const rb_method_entry_t *me, enum ruby_basic_operators bop);
void rb_yjit_constant_state_changed(void);
void rb_yjit_iseq_mark(const struct rb_iseq_constant_body *body);
void rb_yjit_iseq_update_references(const struct rb_iseq_constant_body *body);
void rb_yjit_iseq_free(const struct rb_iseq_constant_body *body);
void rb_yjit_before_ractor_spawn(void);
void rb_yjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic);
void rb_yjit_tracing_invalidate_all(void);

#endif // #ifndef YJIT_H
