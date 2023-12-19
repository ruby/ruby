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

extern uint8_t *rb_rjit_mem_block;

#define RJIT_RUNTIME_COUNTERS(...) struct rb_rjit_runtime_counters { size_t __VA_ARGS__; };
RJIT_RUNTIME_COUNTERS(
    rjit_insns_count,

    send_args_splat_kw_splat,
    send_args_splat,
    send_args_splat_not_array,
    send_args_splat_length_not_equal,
    send_args_splat_cfunc_var_args,
    send_args_splat_arity_error,
    send_args_splat_ruby2_hash,
    send_args_splat_cfunc_zuper,
    send_args_splat_cfunc_ruby2_keywords,
    send_kw_splat,
    send_kwarg,
    send_klass_megamorphic,
    send_missing_cme,
    send_private,
    send_protected_check_failed,
    send_tailcall,
    send_notimplemented,
    send_missing,
    send_bmethod,
    send_alias,
    send_undef,
    send_zsuper,
    send_refined,
    send_stackoverflow,
    send_arity,
    send_c_tracing,
    send_is_a_class_mismatch,
    send_instance_of_class_mismatch,
    send_keywords,

    send_blockiseq,
    send_block_handler,
    send_block_setup,
    send_block_not_nil,
    send_block_not_proxy,
    send_block_arg,

    send_iseq_kwparam,
    send_iseq_accepts_no_kwarg,
    send_iseq_has_opt,
    send_iseq_has_kwrest,
    send_iseq_ruby2_keywords,
    send_iseq_has_rest_and_captured,
    send_iseq_has_rest_and_kw_supplied,
    send_iseq_has_no_kw,
    send_iseq_zsuper,
    send_iseq_materialized_block,
    send_iseq_has_rest,
    send_iseq_block_arg0_splat,
    send_iseq_kw_call,
    send_iseq_splat,
    send_iseq_has_rest_and_optional,
    send_iseq_arity_error,
    send_iseq_missing_optional_kw,
    send_iseq_too_many_kwargs,
    send_iseq_kwargs_mismatch,
    send_iseq_splat_with_kw,
    send_iseq_splat_arity_error,
    send_iseq_has_rest_and_splat_not_equal,

    send_cfunc_variadic,
    send_cfunc_too_many_args,
    send_cfunc_ruby_array_varg,
    send_cfunc_splat_with_kw,
    send_cfunc_tracing,
    send_cfunc_argc_mismatch,
    send_cfunc_toomany_args,

    send_attrset_splat,
    send_attrset_kwarg,
    send_attrset_method,

    send_ivar_splat,
    send_ivar_opt_send,

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

    send_optimized_block_call,
    send_optimized_struct_aset,

    send_bmethod_not_iseq,
    send_bmethod_blockarg,

    invokesuper_me_changed,
    invokesuper_block,

    invokeblock_none,
    invokeblock_symbol,
    invokeblock_proc,
    invokeblock_tag_changed,
    invokeblock_iseq_block_changed,
    invokeblock_iseq_arity,
    invokeblock_iseq_arg0_splat,
    invokeblock_ifunc_args_splat,
    invokeblock_ifunc_kw_splat,
    invokeblock_iseq_arg0_args_splat,
    invokeblock_iseq_arg0_has_kw,

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
