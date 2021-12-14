// YJIT combined compilation unit. This setup allows spreading functions
// across different files without having to worry about putting things
// in headers and prefixing function names.
#include "internal.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "vm_sync.h"
#include "yjit.h"

#ifndef YJIT_CHECK_MODE
# define YJIT_CHECK_MODE 0
#endif

// >= 1: print when output code invalidation happens
// >= 2: dump list of instructions when regions compile
#ifndef YJIT_DUMP_MODE
# define YJIT_DUMP_MODE 0
#endif

// USE_MJIT comes from configure options
#define JIT_ENABLED USE_MJIT

// Check if we need to include YJIT in the build
#if JIT_ENABLED && YJIT_SUPPORTED_P

#include "yjit_asm.c"

// Code block into which we write machine code
static codeblock_t block;
static codeblock_t *cb = NULL;

// Code block into which we write out-of-line machine code
static codeblock_t outline_block;
static codeblock_t *ocb = NULL;

#if YJIT_STATS
// Comments for generated code
struct yjit_comment {
    uint32_t offset;
    const char *comment;
};

typedef rb_darray(struct yjit_comment) yjit_comment_array_t;
static yjit_comment_array_t yjit_code_comments;

// Counters for generated code
#define YJIT_DECLARE_COUNTERS(...) struct rb_yjit_runtime_counters { \
    int64_t __VA_ARGS__; \
}; \
static char yjit_counter_names[] = #__VA_ARGS__;

YJIT_DECLARE_COUNTERS(
    exec_instruction,

    send_keywords,
    send_kw_splat,
    send_args_splat,
    send_block_arg,
    send_ivar_set_method,
    send_zsuper_method,
    send_undef_method,
    send_optimized_method,
    send_optimized_method_send,
    send_optimized_method_call,
    send_optimized_method_block_call,
    send_missing_method,
    send_bmethod,
    send_refined_method,
    send_cfunc_ruby_array_varg,
    send_cfunc_argc_mismatch,
    send_cfunc_toomany_args,
    send_cfunc_tracing,
    send_cfunc_kwargs,
    send_attrset_kwargs,
    send_iseq_tailcall,
    send_iseq_arity_error,
    send_iseq_only_keywords,
    send_iseq_kwargs_req_and_opt_missing,
    send_iseq_kwargs_mismatch,
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
    getivar_megamorphic,

    setivar_se_self_not_heap,
    setivar_idx_out_of_range,
    setivar_val_heapobject,
    setivar_name_not_mapped,
    setivar_not_object,
    setivar_frozen,

    oaref_argc_not_one,
    oaref_arg_not_fixnum,

    opt_getinlinecache_miss,

    binding_allocations,
    binding_set,

    vm_insns_count,
    compiled_iseq_count,
    compiled_block_count,
    compilation_failure,

    exit_from_branch_stub,

    invalidation_count,
    invalidate_method_lookup,
    invalidate_bop_redefined,
    invalidate_ractor_spawn,
    invalidate_constant_state_bump,
    invalidate_constant_ic_fill,

    constant_state_bumps,

    expandarray_splat,
    expandarray_postarg,
    expandarray_not_array,
    expandarray_rhs_too_small,

    gbpp_block_param_modified,
    gbpp_block_handler_not_iseq,

    // Member with known name for iterating over counters
    last_member
)

static struct rb_yjit_runtime_counters yjit_runtime_counters = { 0 };
#undef YJIT_DECLARE_COUNTERS

#endif // YJIT_STATS

// The number of bytes counting from the beginning of the inline code block
// that should not be changed. After patching for global invalidation, no one
// should make changes to the invalidated code region anymore. This is used to
// break out of invalidation race when there are multiple ractors.
static uint32_t yjit_codepage_frozen_bytes = 0;

#include "yjit_utils.c"
#include "yjit_core.c"
#include "yjit_iface.c"
#include "yjit_codegen.c"

#else
// !JIT_ENABLED || !YJIT_SUPPORTED_P
// In these builds, YJIT could never be turned on. Provide dummy
// implementations for YJIT functions exposed to the rest of the code base.
// See yjit.h.

void Init_builtin_yjit(void) {}
bool rb_yjit_enabled_p(void) { return false; }
unsigned rb_yjit_call_threshold(void) { return UINT_MAX; }
void rb_yjit_invalidate_all_method_lookup_assumptions(void) {};
void rb_yjit_method_lookup_change(VALUE klass, ID mid) {};
void rb_yjit_cme_invalidate(VALUE cme) {}
void rb_yjit_collect_vm_usage_insn(int insn) {}
void rb_yjit_collect_binding_alloc(void) {}
void rb_yjit_collect_binding_set(void) {}
bool rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec) { return false; }
void rb_yjit_init(struct rb_yjit_options *options) {}
void rb_yjit_bop_redefined(VALUE klass, const rb_method_entry_t *me, enum ruby_basic_operators bop) {}
void rb_yjit_constant_state_changed(void) {}
void rb_yjit_iseq_mark(const struct rb_iseq_constant_body *body) {}
void rb_yjit_iseq_update_references(const struct rb_iseq_constant_body *body) {}
void rb_yjit_iseq_free(const struct rb_iseq_constant_body *body) {}
void rb_yjit_before_ractor_spawn(void) {}
void rb_yjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic) {}
void rb_yjit_tracing_invalidate_all(void) {}

#endif // if JIT_ENABLED && YJIT_SUPPORTED_P
