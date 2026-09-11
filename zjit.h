#ifndef ZJIT_H
#define ZJIT_H 1
//
// This file contains definitions ZJIT exposes to the CRuby codebase
//

#include "shape.h" // for shape_id_t

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

    // Number of stack map entries in stack[].
    uint32_t stack_size;
    // Flexible array of stack map entries, executed in order by
    // zjit_materialize_frames(). See the ZJIT_STACK_MAP_* opcodes above.
    VALUE stack[];
} zjit_jit_frame_t;

#if USE_ZJIT
// Stack map entries are opcodes for zjit_materialize_frames(), which walks them
// in order while moving a cursor down the VM stack. An untagged entry is an
// immediate Ruby VALUE to store; the tagged forms below copy from the native
// stack, skip slots, or move the cursor. Stack maps never contain heap VALUEs,
// so these tags are available: they are not Qfalse (0), and their low 3 bits
// are zero, so RB_SPECIAL_CONST_P is false. Tags must stay non-zero multiples
// of 8 for that to hold.
#define ZJIT_STACK_MAP_VREG_TAG 0x08
#define ZJIT_STACK_MAP_SKIP_TAG 0x10
#define ZJIT_STACK_MAP_BASE_PTR_TAG 0x18
#define ZJIT_STACK_MAP_TAG_MASK 0xff
#define ZJIT_STACK_MAP_SHIFT 8

// The BASE_PTR payload packs two fields above the tag byte: the slot index in
// bits 8..=31 and the operand stack size in bits 32..=63.
#define ZJIT_STACK_MAP_BASE_PTR_SIZE_SHIFT 32
#define ZJIT_STACK_MAP_BASE_PTR_INDEX_MASK 0xffffff

static inline bool
ZJIT_STACK_MAP_VREG_P(VALUE entry)
{
    return (entry & ZJIT_STACK_MAP_TAG_MASK) == ZJIT_STACK_MAP_VREG_TAG;
}

static inline size_t
ZJIT_STACK_MAP_VREG_INDEX(VALUE entry)
{
    return entry >> ZJIT_STACK_MAP_SHIFT;
}

static inline bool
ZJIT_STACK_MAP_SKIP_P(VALUE entry)
{
    return (entry & ZJIT_STACK_MAP_TAG_MASK) == ZJIT_STACK_MAP_SKIP_TAG;
}

static inline size_t
ZJIT_STACK_MAP_SKIP_SIZE(VALUE entry)
{
    return entry >> ZJIT_STACK_MAP_SHIFT;
}

// Anchor the write cursor using the SP register the JIT saved on its native
// stack, instead of cfp->sp. cfp->sp is not a reliable starting point for a
// frame that is in the middle of a non-leaf C call, as e.g. raising
// ArgumentError can push through and move cfp->sp, then use the stack map.
// gen_prepare_non_leaf_call() emits this opcode, always as stack[0], so the
// entries after decode to the right place.
static inline bool
ZJIT_STACK_MAP_BASE_PTR_P(VALUE entry)
{
    return (entry & ZJIT_STACK_MAP_TAG_MASK) == ZJIT_STACK_MAP_BASE_PTR_TAG;
}

// VALUE index from cfp->jit_return down to the native stack slot holding the
// saved SP register, i.e. base_ptr is `((VALUE **)cfp->jit_return)[-index]`.
// There is one such slot per compiled function, so the index depends on the
// frame's inlining depth.
static inline size_t
ZJIT_STACK_MAP_BASE_PTR_SLOT_INDEX(VALUE entry)
{
    return (entry >> ZJIT_STACK_MAP_SHIFT) & ZJIT_STACK_MAP_BASE_PTR_INDEX_MASK;
}

// Number of VM stack slots above base_ptr, i.e. the frame's operand stack
// depth. The cursor is set to `base_ptr + this`.
static inline size_t
ZJIT_STACK_MAP_BASE_PTR_STACK_SIZE(VALUE entry)
{
    return entry >> ZJIT_STACK_MAP_BASE_PTR_SIZE_SHIFT;
}

extern void *rb_zjit_entry;
extern bool rb_zjit_compiling_p;
extern const zjit_jit_frame_t rb_zjit_c_frame;
extern unsigned int rb_zjit_call_threshold;
extern unsigned int rb_zjit_profile_threshold;
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
void rb_zjit_mark_all_writable(void);
void rb_zjit_mark_all_executable(void);
void rb_zjit_iseq_free(const rb_iseq_t *iseq);
void rb_zjit_invalidate_single_ractor(void);
void rb_zjit_tracing_invalidate_all(void);
void rb_zjit_invalidate_newobj_hook(void);
void rb_zjit_invalidate_no_singleton_class(VALUE klass);
void rb_zjit_invalidate_root_box(void);
void rb_zjit_jit_frame_update_references(zjit_jit_frame_t *jit_frame);
void rb_zjit_materialize_frames(const rb_execution_context_t *ec, rb_control_frame_t *cfp);
void rb_zjit_materialize_frames_for_longjmp(const rb_execution_context_t *ec, rb_control_frame_t *cfp);
size_t rb_zjit_hash_new_size(VALUE *flags_out, size_t size);
VALUE rb_zjit_new_obj_shape(VALUE flags, size_t alloc_size);
bool rb_zjit_class_allocate_instance_fastpath(VALUE klass, size_t *size_out, VALUE *flags_out);
bool rb_zjit_str_resurrect_fastpath(VALUE str, bool chilled, size_t *size_out, VALUE *flags_out, long *len_out, size_t *byte_size_out);
bool rb_zjit_array_dup_can_fastpath(VALUE ary, size_t *alloc_size_out, VALUE *flags_out, long *len_out);
bool rb_zjit_array_new_can_fastpath(long len, size_t *alloc_size_out, VALUE *flags_out);
bool rb_zjit_hash_dup_can_fastpath(VALUE hash, size_t *alloc_size_out, VALUE *flags_out, VALUE *ifnone_out, long *bound_out);
void rb_zjit_range_new_fastpath(bool exclude_end, size_t *alloc_size_out, VALUE *flags_out);
void rb_zjit_array_new_fastpath(size_t *alloc_size_out, VALUE *flags_out);
bool rb_zjit_newobj_hook_enabled_p(void);

// Special value for cfp->jit_return that means "this is a C method frame, use
// rb_zjit_c_frame as the JITFrame". We don't control the native stack layout
// for C frames, so there's no per-call JITFrame storage; we set this sentinel
// instead of a heap-allocated JITFrame pointer.
#define ZJIT_JIT_RETURN_C_FRAME 0x1

static inline const zjit_jit_frame_t *
CFP_ZJIT_FRAME(const rb_control_frame_t *cfp)
{
    if ((VALUE)cfp->jit_return == ZJIT_JIT_RETURN_C_FRAME) {
        return &rb_zjit_c_frame;
    }
    else {
        // Read JITFrame from this frame's stack slot. cfp->jit_return points at
        // the slot reserved for this frame's inlining depth, so distinct frames in
        // the same JIT function read distinct slots. An initial frame describing
        // the entry PC + iseq is written by gen_entry_point() for the top-level
        // frame and by gen_push_inline_frame() for inlined frames. That entry
        // PC is correct only at the frame's start; because the PC this frame reports
        // must track where execution currently is, later gen_save_pc_for_gc() calls
        // rewrite the slot with the live PC as execution advances through the frame,
        // before any non-leaf C call.
        return (const zjit_jit_frame_t *)((VALUE *)cfp->jit_return)[-1];
    }
}
#else
#define rb_zjit_entry 0
#define rb_zjit_compiling_p false
static inline void rb_zjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception) {}
static inline void rb_zjit_profile_insn(uint32_t insn, rb_execution_context_t *ec) {}
static inline void rb_zjit_profile_enable(const rb_iseq_t *iseq) {}
static inline void rb_zjit_bop_redefined(int redefined_flag, enum ruby_basic_operators bop) {}
static inline void rb_zjit_cme_invalidate(const rb_callable_method_entry_t *cme) {}
static inline void rb_zjit_invalidate_no_ep_escape(const rb_iseq_t *iseq) {}
static inline void rb_zjit_constant_state_changed(ID id) {}
static inline void rb_zjit_invalidate_single_ractor(void) {}
static inline void rb_zjit_tracing_invalidate_all(void) {}
static inline void rb_zjit_invalidate_newobj_hook(void) {}
static inline void rb_zjit_invalidate_no_singleton_class(VALUE klass) {}
static inline void rb_zjit_invalidate_root_box(void) {}
static inline void rb_zjit_jit_frame_update_references(zjit_jit_frame_t *jit_frame) {}
static inline void rb_zjit_materialize_frames(const rb_execution_context_t *ec, rb_control_frame_t *cfp) {}
static inline void rb_zjit_materialize_frames_for_longjmp(const rb_execution_context_t *ec, rb_control_frame_t *cfp) {}
static inline const zjit_jit_frame_t *CFP_ZJIT_FRAME(const rb_control_frame_t *cfp) { return NULL; }
#endif // #if USE_ZJIT

#define rb_zjit_enabled_p (rb_zjit_entry != 0)

// Return true if a given CFP has ZJIT's JITFrame.
static inline bool
CFP_ZJIT_FRAME_P(const rb_control_frame_t *cfp)
{
    if (!rb_zjit_enabled_p) return false;
    return cfp->jit_return != NULL;
}

static inline const VALUE*
CFP_PC(const rb_control_frame_t *cfp)
{
    if (CFP_ZJIT_FRAME_P(cfp)) {
        return CFP_ZJIT_FRAME(cfp)->pc;
    }
    return cfp->pc;
}

static inline const rb_iseq_t*
CFP_ISEQ(const rb_control_frame_t *cfp)
{
    if (CFP_ZJIT_FRAME_P(cfp)) {
        return CFP_ZJIT_FRAME(cfp)->iseq;
    }
    return cfp->_iseq;
}

#endif // #ifndef ZJIT_H
