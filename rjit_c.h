// This file is parsed by tool/rjit/generate.rb to generate rjit_c.rb
#ifndef RJIT_C_H
#define RJIT_C_H

#include "ruby/internal/config.h"
#include "internal/string.h"
#include "internal/struct.h"
#include "internal/variable.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "ccan/list/list.h"
#include "rjit.h"
#include "shape.h"

// Macros to check if a position is already compiled using compile_status.stack_size_for_pos
#define NOT_COMPILED_STACK_SIZE -1
#define ALREADY_COMPILED_P(status, pos) (status->stack_size_for_pos[pos] != NOT_COMPILED_STACK_SIZE)

// Linked list of struct rb_rjit_unit.
struct rb_rjit_unit_list {
    struct ccan_list_head head;
    int length; // the list length
};

enum rb_rjit_unit_type {
    // Single-ISEQ unit for unit_queue
    RJIT_UNIT_ISEQ = 0,
    // Multi-ISEQ unit for rjit_batch
    RJIT_UNIT_BATCH = 1,
    // All-ISEQ unit for rjit_compact
    RJIT_UNIT_COMPACT = 2,
};

// The unit structure that holds metadata of ISeq for RJIT.
// TODO: Use different structs for ISEQ and BATCH/COMPACT
struct rb_rjit_unit {
    struct ccan_list_node unode;
    // Unique order number of unit.
    int id;
    // Type of this unit
    enum rb_rjit_unit_type type;

    /* RJIT_UNIT_ISEQ */
    // ISEQ for a non-batch unit
    rb_iseq_t *iseq;
    // Only used by unload_units. Flag to check this unit is currently on stack or not.
    bool used_code_p;
    // rjit_compile's optimization switches
    struct rb_rjit_compile_info compile_info;
    // captured CC values, they should be marked with iseq.
    const struct rb_callcache **cc_entries;
    // ISEQ_BODY(iseq)->ci_size + ones of inlined iseqs
    unsigned int cc_entries_size;

    /* RJIT_UNIT_BATCH, RJIT_UNIT_COMPACT */
    // Dlopen handle of the loaded object file.
    void *handle;
    // Units compacted by this batch
    struct rb_rjit_unit_list units; // RJIT_UNIT_BATCH only
};

// Storage to keep data which is consistent in each conditional branch.
// This is created and used for one `compile_insns` call and its values
// should be copied for extra `compile_insns` call.
struct compile_branch {
    unsigned int stack_size; // this simulates sp (stack pointer) of YARV
    bool finish_p; // if true, compilation in this branch should stop and let another branch to be compiled
};

// For propagating information needed for lazily pushing a frame.
struct inlined_call_context {
    int orig_argc; // ci->orig_argc
    VALUE me; // vm_cc_cme(cc)
    int param_size; // def_iseq_ptr(vm_cc_cme(cc)->def)->body->param.size
    int local_size; // def_iseq_ptr(vm_cc_cme(cc)->def)->body->local_table_size
};

// Storage to keep compiler's status.  This should have information
// which is global during one `rjit_compile` call.  Ones conditional
// in each branch should be stored in `compile_branch`.
struct compile_status {
    bool success; // has true if compilation has had no issue
    int *stack_size_for_pos; // stack_size_for_pos[pos] has stack size for the position (otherwise -1)
    // If true, JIT-ed code will use local variables to store pushed values instead of
    // using VM's stack and moving stack pointer.
    bool local_stack_p;
    // Index of call cache entries captured to compiled_iseq to be marked on GC
    int cc_entries_index;
    // A pointer to root (i.e. not inlined) iseq being compiled.
    const struct rb_iseq_constant_body *compiled_iseq;
    int compiled_id; // Just a copy of compiled_iseq->jit_unit->id
    // Mutated optimization levels
    struct rb_rjit_compile_info *compile_info;
    // If `inlined_iseqs[pos]` is not NULL, `rjit_compile_body` tries to inline ISeq there.
    const struct rb_iseq_constant_body **inlined_iseqs;
    struct inlined_call_context inline_context;
};

//================================================================================
//
// New stuff from here
//

extern uint8_t *rb_rjit_mem_block;

#define RJIT_RUNTIME_COUNTERS(...) struct rb_rjit_runtime_counters { size_t __VA_ARGS__; };
RJIT_RUNTIME_COUNTERS(
    vm_insns_count,
    rjit_insns_count,

    send_args_splat,
    send_klass_megamorphic,
    send_kw_splat,
    send_kwarg,
    send_missing_cme,
    send_private,
    send_protected_check_failed,
    send_tailcall,
    send_notimplemented,
    send_cfunc,
    send_attrset,
    send_missing,
    send_bmethod,
    send_alias,
    send_undef,
    send_zsuper,
    send_refined,
    send_unknown_type,
    send_stackoverflow,
    send_arity,
    send_c_tracing,

    send_blockarg_not_nil_or_proxy,
    send_blockiseq,
    send_block_handler,
    send_block_setup,
    send_block_not_nil,
    send_block_not_proxy,

    send_iseq_kwparam,
    send_iseq_kw_splat,

    send_cfunc_variadic,
    send_cfunc_too_many_args,
    send_cfunc_ruby_array_varg,

    send_ivar,
    send_ivar_splat,
    send_ivar_opt_send,
    send_ivar_blockarg,

    send_optimized_send_no_args,
    send_optimized_send_not_sym_or_str,
    send_optimized_send_mid_class_changed,
    send_optimized_send_mid_id_changed,
    send_optimized_send_null_mid,
    send_optimized_send_send,
    send_optimized_call_block,
    send_optimized_call_kwarg,
    send_optimized_call_splat,
    send_optimized_struct_aref_error,

    send_optimized_blockarg,
    send_optimized_block_call,
    send_optimized_struct_aset,
    send_optimized_unknown_type,

    send_bmethod_not_iseq,
    send_bmethod_blockarg,

    invokesuper_me_changed,
    invokesuper_same_me,

    getivar_megamorphic,
    getivar_not_heap,
    getivar_special_const,
    getivar_too_complex,

    optaref_arg_not_fixnum,
    optaref_argc_not_one,
    optaref_recv_not_array,
    optaref_recv_not_hash,
    optaref_send,

    optgetconst_not_cached,
    optgetconst_cref,
    optgetconst_cache_miss,

    setivar_frozen,
    setivar_not_heap,
    setivar_megamorphic,
    setivar_too_complex,

    expandarray_splat,
    expandarray_postarg,
    expandarray_not_array,
    expandarray_rhs_too_small,

    getblockpp_block_param_modified,
    getblockpp_block_handler_none,
    getblockpp_not_gc_guarded,
    getblockpp_not_iseq_block,

    compiled_block_count
)
#undef RJIT_RUNTIME_COUNTERS
extern struct rb_rjit_runtime_counters rb_rjit_counters;

#endif /* RJIT_C_H */
