//
// These are definitions YJIT uses to interface with the CRuby codebase,
// but which are only used internally by YJIT.
//

#ifndef YJIT_IFACE_H
#define YJIT_IFACE_H 1

#include "ruby/internal/config.h"
#include "ruby_assert.h" // for RUBY_DEBUG
#include "yjit.h" // for YJIT_STATS
#include "vm_core.h"
#include "yjit_core.h"

#ifndef YJIT_DEFAULT_CALL_THRESHOLD
# define YJIT_DEFAULT_CALL_THRESHOLD 10
#endif

#if YJIT_STATS
struct yjit_comment {
    uint32_t offset;
    const char *comment;
};

typedef rb_darray(struct yjit_comment) yjit_comment_array_t;

extern yjit_comment_array_t yjit_code_comments;
#endif // if YJIT_STATS


#if YJIT_STATS

#define YJIT_DECLARE_COUNTERS(...) struct rb_yjit_runtime_counters { \
    int64_t __VA_ARGS__; \
}; \
static char yjit_counter_names[] = #__VA_ARGS__;

YJIT_DECLARE_COUNTERS(
    exec_instruction,

    send_callsite_not_simple,
    send_kw_splat,
    send_ivar_set_method,
    send_zsuper_method,
    send_undef_method,
    send_optimized_method,
    send_missing_method,
    send_bmethod,
    send_refined_method,
    send_cfunc_ruby_array_varg,
    send_cfunc_argc_mismatch,
    send_cfunc_toomany_args,
    send_cfunc_tracing,
    send_iseq_tailcall,
    send_iseq_arity_error,
    send_iseq_only_keywords,
    send_iseq_complex_callee,
    send_not_implemented_method,
    send_getter_arity,
    send_se_cf_overflow,
    send_se_protected_check_failed,

    traced_cfunc_return,

    invokesuper_me_changed,
    invokesuper_block,

    leave_se_interrupt,
    leave_interp_return,
    leave_start_pc_non_zero,

    getivar_se_self_not_heap,
    getivar_idx_out_of_range,

    setivar_se_self_not_heap,
    setivar_idx_out_of_range,
    setivar_val_heapobject,
    setivar_name_not_mapped,
    setivar_not_object,
    setivar_frozen,

    oaref_argc_not_one,
    oaref_arg_not_fixnum,

    binding_allocations,
    binding_set,

    vm_insns_count,
    compiled_iseq_count,

    expandarray_splat,
    expandarray_postarg,
    expandarray_not_array,
    expandarray_rhs_too_small,

    // Member with known name for iterating over counters
    last_member
)

#undef YJIT_DECLARE_COUNTERS

#endif // YJIT_STATS

RUBY_EXTERN struct rb_yjit_options rb_yjit_opts;
RUBY_EXTERN struct rb_yjit_runtime_counters yjit_runtime_counters;

void yjit_map_addr2insn(void *code_ptr, int insn);
VALUE *yjit_iseq_pc_at_idx(const rb_iseq_t *iseq, uint32_t insn_idx);
int yjit_opcode_at_pc(const rb_iseq_t *iseq, const VALUE *pc);
void yjit_print_iseq(const rb_iseq_t *iseq);

void check_cfunc_dispatch(VALUE receiver, struct rb_callinfo *ci, void *callee, rb_callable_method_entry_t *compile_time_cme);

RBIMPL_ATTR_NODISCARD() bool assume_bop_not_redefined(block_t *block, int redefined_flag, enum ruby_basic_operators bop);
void assume_method_lookup_stable(VALUE receiver_klass, const rb_callable_method_entry_t *cme, block_t *block);
RBIMPL_ATTR_NODISCARD() bool assume_single_ractor_mode(block_t *block);
void assume_stable_global_constant_state(block_t *block);

// this function *must* return passed exit_pc
const VALUE *rb_yjit_count_side_exit_op(const VALUE *exit_pc);

void yjit_unlink_method_lookup_dependency(block_t *block);
void yjit_block_assumptions_free(block_t *block);

#endif // #ifndef YJIT_IFACE_H
