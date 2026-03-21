#ifndef ZJIT_H
#define ZJIT_H 1
//
// This file contains definitions ZJIT exposes to the CRuby codebase
//

// ZJIT_STATS controls whether to support runtime counters in the interpreter
#ifndef ZJIT_STATS
# define ZJIT_STATS (USE_ZJIT && RUBY_DEBUG)
#endif

#if USE_ZJIT
extern void *rb_zjit_entry;
extern uint64_t rb_zjit_call_threshold;
extern uint64_t rb_zjit_profile_threshold;
void rb_zjit_compile_iseq(const rb_iseq_t *iseq, bool jit_exception);
void rb_zjit_profile_insn(uint32_t insn, rb_execution_context_t *ec);
void rb_zjit_profile_enable(const rb_iseq_t *iseq);
void rb_zjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop);
void rb_zjit_cme_invalidate(const rb_callable_method_entry_t *cme);
void rb_zjit_cme_free(const rb_callable_method_entry_t *cme);
void rb_zjit_klass_free(VALUE klass);
void rb_zjit_invalidate_no_ep_escape(const rb_iseq_t *iseq);
void rb_zjit_constant_state_changed(ID id);
void rb_zjit_iseq_mark(void *payload);
void rb_zjit_iseq_update_references(void *payload);
void rb_zjit_iseq_free(const rb_iseq_t *iseq);
void rb_zjit_before_ractor_spawn(void);
void rb_zjit_tracing_invalidate_all(void);
void rb_zjit_invalidate_no_singleton_class(VALUE klass);
void rb_zjit_invalidate_root_box(void);
VALUE *rb_zjit_jit_return_pc(void *jit_return);
rb_iseq_t *rb_zjit_jit_return_iseq(void *jit_return);
void rb_zjit_jit_return_set_iseq(void *jit_return, rb_iseq_t *iseq);
bool rb_zjit_jit_return_materialize_block_code(const void *jit_return);
#else
#define rb_zjit_entry 0
static inline void rb_zjit_compile_iseq(const rb_iseq_t *iseq, bool jit_exception) {}
static inline void rb_zjit_profile_insn(uint32_t insn, rb_execution_context_t *ec) {}
static inline void rb_zjit_profile_enable(const rb_iseq_t *iseq) {}
static inline void rb_zjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop) {}
static inline void rb_zjit_cme_invalidate(const rb_callable_method_entry_t *cme) {}
static inline void rb_zjit_invalidate_no_ep_escape(const rb_iseq_t *iseq) {}
static inline void rb_zjit_constant_state_changed(ID id) {}
static inline void rb_zjit_before_ractor_spawn(void) {}
static inline void rb_zjit_tracing_invalidate_all(void) {}
static inline void rb_zjit_invalidate_no_singleton_class(VALUE klass) {}
static inline void rb_zjit_invalidate_root_box(void) {}
static inline VALUE *rb_zjit_jit_return_pc(void *jit_return) { UNREACHABLE_RETURN(0); }
static inline rb_iseq_t *rb_zjit_jit_return_iseq(void *jit_return) { UNREACHABLE_RETURN(0); }
static inline void rb_zjit_jit_return_set_iseq(void *jit_return, rb_iseq_t *iseq) { UNREACHABLE; }
static inline bool rb_zjit_jit_return_materialize_block_code(const void *jit_return) { UNREACHABLE_RETURN(false); }
#endif // #if USE_ZJIT

#define rb_zjit_enabled_p (rb_zjit_entry != 0)

// Check if cfp->jit_return holds a ZJIT lightweight frame (JITFrame pointer).
// YJIT also uses jit_return (as a return address), so this must only return
// true when ZJIT is enabled and has set jit_return to a JITFrame pointer.
static inline bool
CFP_JIT_RETURN(const rb_control_frame_t *cfp)
{
    if (!rb_zjit_enabled_p) return false;
#if USE_ZJIT
    RUBY_ASSERT_ALWAYS(cfp->jit_return != (void *)2);
#endif
    return !!cfp->jit_return;
}

static inline const VALUE*
rb_zjit_cfp_pc(const rb_control_frame_t *cfp)
{
    if (rb_zjit_enabled_p && CFP_JIT_RETURN(cfp)) {
        return rb_zjit_jit_return_pc(cfp->jit_return);
    }
    else {
        return cfp->pc;
    }
}

static inline const rb_iseq_t*
rb_zjit_cfp_iseq(const rb_control_frame_t *cfp)
{
    if (rb_zjit_enabled_p && CFP_JIT_RETURN(cfp)) {
        return rb_zjit_jit_return_iseq(cfp->jit_return);
    }
    else {
        return cfp->iseq;
    }
}

static inline const void*
rb_zjit_cfp_block_code(const rb_control_frame_t *cfp)
{
    if (rb_zjit_enabled_p && CFP_JIT_RETURN(cfp)) {
        return NULL;
    }
    else {
        return cfp->block_code;
    }
}

// Read block_code from a captured block that may live inside a cfp.
// In that case, jit_return is located one word after rb_captured_block.
static inline const void*
rb_zjit_captured_block_code(const struct rb_captured_block *captured)
{
    if (rb_zjit_enabled_p) {
        void *jit_return = *(void **)((VALUE *)captured + 3);
        if (jit_return) {
            return NULL;
        }
    }
    return (const void *)captured->code.val;
}

#endif // #ifndef ZJIT_H
