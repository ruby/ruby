#ifndef ZJIT_H
#define ZJIT_H 1
//
// This file contains definitions ZJIT exposes to the CRuby codebase
//

// ZJIT_STATS controls whether to support runtime counters in the interpreter
#ifndef ZJIT_STATS
# define ZJIT_STATS (USE_ZJIT && RUBY_DEBUG)
#endif

// JITFrame is defined here as the single source of truth and imported into
// Rust via bindgen. C code reads fields directly; Rust uses an impl block.
typedef struct zjit_jit_frame {
    // Program counter for this frame, used for backtraces and GC.
    // NULL for C frames (they don't have a Ruby PC).
    const VALUE *pc;
    // The ISEQ this frame belongs to. Marked via rb_execution_context_mark.
    // NULL for C frames.
    const rb_iseq_t *iseq;
    // Whether to materialize block_code when this frame is materialized.
    // True when the ISEQ doesn't contain send/invokesuper/invokeblock
    // (which write block_code themselves), so we must restore it.
    // Always false for C frames.
    bool materialize_block_code;
} zjit_jit_frame_t;

#if USE_ZJIT
extern void *rb_zjit_entry;
extern uint64_t rb_zjit_call_threshold;
extern uint64_t rb_zjit_profile_threshold;
void rb_zjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception);
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
void rb_zjit_jit_frame_update_references(zjit_jit_frame_t *jit_frame);
#else
#define rb_zjit_entry 0
static inline void rb_zjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception) {}
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
static inline void rb_zjit_jit_frame_update_references(zjit_jit_frame_t *jit_frame) {}
#endif // #if USE_ZJIT

#define rb_zjit_enabled_p (rb_zjit_entry != 0)

enum zjit_poison_values {
    // Poison value used on frame push when runtime checks are enabled
    ZJIT_JIT_RETURN_POISON = 2,
};

// Check if cfp->jit_return holds a ZJIT lightweight frame (JITFrame pointer).
// YJIT also uses jit_return (as a return address), so this must only return
// true when ZJIT is enabled and has set jit_return to a JITFrame pointer.
static inline bool
CFP_HAS_JIT_RETURN(const rb_control_frame_t *cfp)
{
    if (!rb_zjit_enabled_p) return false;
#if USE_ZJIT
    RUBY_ASSERT_ALWAYS(cfp->jit_return != (void *)ZJIT_JIT_RETURN_POISON);
#endif
    return !!cfp->jit_return;
}

static inline const VALUE*
rb_cfp_pc(const rb_control_frame_t *cfp)
{
    if (CFP_HAS_JIT_RETURN(cfp)) {
        return ((const zjit_jit_frame_t *)cfp->jit_return)->pc;
    }
    return cfp->pc;
}

static inline const rb_iseq_t*
rb_cfp_iseq(const rb_control_frame_t *cfp)
{
    if (CFP_HAS_JIT_RETURN(cfp)) {
        return ((const zjit_jit_frame_t *)cfp->jit_return)->iseq;
    }
    return cfp->_iseq;
}

// Returns true if cfp has an ISEQ, either directly or via JITFrame.
// When JITFrame is present, it is authoritative (cfp->_iseq may be stale).
// C frames with JITFrame have iseq=NULL, so this returns false for them.
static inline bool
rb_cfp_has_iseq(const rb_control_frame_t *cfp)
{
    return !!rb_cfp_iseq(cfp);
}

// Returns true if cfp has a PC, either directly or via JITFrame.
// When JITFrame is present, it is authoritative (cfp->pc may be stale/poisoned).
// C frames with JITFrame have pc=NULL, so this returns false for them.
static inline bool
rb_cfp_has_pc(const rb_control_frame_t *cfp)
{
    return !!rb_cfp_pc(cfp);
}

#endif // #ifndef ZJIT_H
