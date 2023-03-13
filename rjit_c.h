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
    send_iseq_complex,

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

    send_bmethod_not_iseq,
    send_bmethod_blockarg,

    invokesuper_me_changed,
    invokesuper_same_me,

    invokeblock_none,
    invokeblock_iseq,
    invokeblock_ifunc,
    invokeblock_symbol,
    invokeblock_proc,

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
