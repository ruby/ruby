//! Counters and associated methods for events when ZJIT is run.

use std::time::Instant;
use std::sync::atomic::Ordering;
use crate::options::OPTIONS;

#[cfg(feature = "stats_allocator")]
#[path = "../../jit/src/lib.rs"]
mod jit;

use crate::{cruby::*, hir::ParseError, options::get_option, state::{zjit_enabled_p, ZJITState}};

macro_rules! make_counters {
    (
        default {
            $($default_counter_name:ident,)+
        }
        exit {
            $($exit_counter_name:ident,)+
        }
        dynamic_send {
            $($dynamic_send_counter_name:ident,)+
        }
        optimized_send {
            $($optimized_send_counter_name:ident,)+
        }
        dynamic_setivar {
            $($dynamic_setivar_counter_name:ident,)+
        }
        dynamic_getivar {
            $($dynamic_getivar_counter_name:ident,)+
        }
        dynamic_definedivar {
            $($dynamic_definedivar_counter_name:ident,)+
        }
        $($counter_name:ident,)+
    ) => {
        /// Struct containing the counter values
        #[derive(Default, Debug)]
        pub struct Counters {
            $(pub $default_counter_name: u64,)+
            $(pub $exit_counter_name: u64,)+
            $(pub $dynamic_send_counter_name: u64,)+
            $(pub $optimized_send_counter_name: u64,)+
            $(pub $dynamic_setivar_counter_name: u64,)+
            $(pub $dynamic_getivar_counter_name: u64,)+
            $(pub $dynamic_definedivar_counter_name: u64,)+
            $(pub $counter_name: u64,)+
        }

        /// Enum to represent a counter
        #[allow(non_camel_case_types)]
        #[derive(Clone, Copy, PartialEq, Eq, Debug)]
        pub enum Counter {
            $($default_counter_name,)+
            $($exit_counter_name,)+
            $($dynamic_send_counter_name,)+
            $($optimized_send_counter_name,)+
            $($dynamic_setivar_counter_name,)+
            $($dynamic_getivar_counter_name,)+
            $($dynamic_definedivar_counter_name,)+
            $($counter_name,)+
        }

        impl Counter {
            pub fn name(&self) -> &'static str {
                match self {
                    $( Counter::$default_counter_name => stringify!($default_counter_name), )+
                    $( Counter::$exit_counter_name => stringify!($exit_counter_name), )+
                    $( Counter::$dynamic_send_counter_name => stringify!($dynamic_send_counter_name), )+
                    $( Counter::$optimized_send_counter_name => stringify!($optimized_send_counter_name), )+
                    $( Counter::$dynamic_setivar_counter_name => stringify!($dynamic_setivar_counter_name), )+
                    $( Counter::$dynamic_getivar_counter_name => stringify!($dynamic_getivar_counter_name), )+
                    $( Counter::$dynamic_definedivar_counter_name => stringify!($dynamic_definedivar_counter_name), )+
                    $( Counter::$counter_name => stringify!($counter_name), )+
                }
            }

            pub fn get(name: &str) -> Option<Counter> {
                match name {
                    $( stringify!($default_counter_name) => Some(Counter::$default_counter_name), )+
                    $( stringify!($exit_counter_name) => Some(Counter::$exit_counter_name), )+
                    $( stringify!($dynamic_send_counter_name) => Some(Counter::$dynamic_send_counter_name), )+
                    $( stringify!($optimized_send_counter_name) => Some(Counter::$optimized_send_counter_name), )+
                    $( stringify!($dynamic_setivar_counter_name) => Some(Counter::$dynamic_setivar_counter_name), )+
                    $( stringify!($dynamic_getivar_counter_name) => Some(Counter::$dynamic_getivar_counter_name), )+
                    $( stringify!($dynamic_definedivar_counter_name) => Some(Counter::$dynamic_definedivar_counter_name), )+
                    $( stringify!($counter_name) => Some(Counter::$counter_name), )+
                    _ => None,
                }
            }
        }

        /// Map a counter to a pointer
        pub fn counter_ptr(counter: Counter) -> *mut u64 {
            let counters = $crate::state::ZJITState::get_counters();
            match counter {
                $( Counter::$default_counter_name => std::ptr::addr_of_mut!(counters.$default_counter_name), )+
                $( Counter::$exit_counter_name => std::ptr::addr_of_mut!(counters.$exit_counter_name), )+
                $( Counter::$dynamic_send_counter_name => std::ptr::addr_of_mut!(counters.$dynamic_send_counter_name), )+
                $( Counter::$dynamic_setivar_counter_name => std::ptr::addr_of_mut!(counters.$dynamic_setivar_counter_name), )+
                $( Counter::$dynamic_getivar_counter_name => std::ptr::addr_of_mut!(counters.$dynamic_getivar_counter_name), )+
                $( Counter::$dynamic_definedivar_counter_name => std::ptr::addr_of_mut!(counters.$dynamic_definedivar_counter_name), )+
                $( Counter::$optimized_send_counter_name => std::ptr::addr_of_mut!(counters.$optimized_send_counter_name), )+
                $( Counter::$counter_name => std::ptr::addr_of_mut!(counters.$counter_name), )+
            }
        }

        /// List of counters that are available without --zjit-stats.
        /// They are incremented only by `incr_counter()` and don't use `gen_incr_counter()`.
        pub const DEFAULT_COUNTERS: &'static [Counter] = &[
            $( Counter::$default_counter_name, )+
        ];

        /// List of other counters that are summed as side_exit_count.
        pub const EXIT_COUNTERS: &'static [Counter] = &[
            $( Counter::$exit_counter_name, )+
        ];

        /// List of other counters that are summed as dynamic_send_count.
        pub const DYNAMIC_SEND_COUNTERS: &'static [Counter] = &[
            $( Counter::$dynamic_send_counter_name, )+
        ];

        /// List of other counters that are summed as optimized_send_count.
        pub const OPTIMIZED_SEND_COUNTERS: &'static [Counter] = &[
            $( Counter::$optimized_send_counter_name, )+
        ];

        /// List of other counters that are summed as dynamic_setivar_count.
        pub const DYNAMIC_SETIVAR_COUNTERS: &'static [Counter] = &[
            $( Counter::$dynamic_setivar_counter_name, )+
        ];

        /// List of other counters that are summed as dynamic_getivar_count.
        pub const DYNAMIC_GETIVAR_COUNTERS: &'static [Counter] = &[
            $( Counter::$dynamic_getivar_counter_name, )+
        ];

        /// List of other counters that are summed as dynamic_definedivar_count.
        pub const DYNAMIC_DEFINEDIVAR_COUNTERS: &'static [Counter] = &[
            $( Counter::$dynamic_definedivar_counter_name, )+
        ];

        /// List of other counters that are available only for --zjit-stats.
        pub const OTHER_COUNTERS: &'static [Counter] = &[
            $( Counter::$counter_name, )+
        ];
    }
}

// Declare all the counters we track
make_counters! {
    // Default counters that are available without --zjit-stats
    default {
        compiled_iseq_count,
        failed_iseq_count,

        compile_time_ns,
        profile_time_ns,
        gc_time_ns,
        invalidation_time_ns,
    }

    // Exit counters that are summed as side_exit_count
    exit {
        // exit_: Side exits reasons
        exit_compile_error,
        exit_unhandled_newarray_send_min,
        exit_unhandled_newarray_send_hash,
        exit_unhandled_newarray_send_pack,
        exit_unhandled_newarray_send_pack_buffer,
        exit_unhandled_newarray_send_unknown,
        exit_unhandled_duparray_send,
        exit_unhandled_tailcall,
        exit_unhandled_splat,
        exit_unhandled_kwarg,
        exit_unknown_special_variable,
        exit_unhandled_hir_insn,
        exit_unhandled_yarv_insn,
        exit_fixnum_add_overflow,
        exit_fixnum_sub_overflow,
        exit_fixnum_mult_overflow,
        exit_fixnum_lshift_overflow,
        exit_fixnum_mod_by_zero,
        exit_fixnum_div_by_zero,
        exit_box_fixnum_overflow,
        exit_guard_type_failure,
        exit_guard_type_not_failure,
        exit_guard_bit_equals_failure,
        exit_guard_int_equals_failure,
        exit_guard_shape_failure,
        exit_guard_not_frozen_failure,
        exit_guard_less_failure,
        exit_guard_greater_eq_failure,
        exit_patchpoint_bop_redefined,
        exit_patchpoint_method_redefined,
        exit_patchpoint_stable_constant_names,
        exit_patchpoint_no_tracepoint,
        exit_patchpoint_no_ep_escape,
        exit_patchpoint_single_ractor_mode,
        exit_patchpoint_no_singleton_class,
        exit_callee_side_exit,
        exit_obj_to_string_fallback,
        exit_interrupt,
        exit_stackoverflow,
        exit_block_param_proxy_modified,
        exit_block_param_proxy_not_iseq_or_ifunc,
        exit_too_many_keyword_parameters,
    }

    // Send fallback counters that are summed as dynamic_send_count
    dynamic_send {
        // send_fallback_: Fallback reasons for send-ish instructions
        send_fallback_send_without_block_polymorphic,
        send_fallback_send_without_block_megamorphic,
        send_fallback_send_without_block_no_profiles,
        send_fallback_send_without_block_cfunc_not_variadic,
        send_fallback_send_without_block_cfunc_array_variadic,
        send_fallback_send_without_block_not_optimized_method_type,
        send_fallback_send_without_block_not_optimized_method_type_optimized,
        send_fallback_send_without_block_not_optimized_need_permission,
        send_fallback_too_many_args_for_lir,
        send_fallback_send_without_block_bop_redefined,
        send_fallback_send_without_block_operands_not_fixnum,
        send_fallback_send_without_block_direct_keyword_mismatch,
        send_fallback_send_without_block_direct_optional_keywords,
        send_fallback_send_without_block_direct_keyword_count_mismatch,
        send_fallback_send_without_block_direct_missing_keyword,
        send_fallback_send_polymorphic,
        send_fallback_send_megamorphic,
        send_fallback_send_no_profiles,
        send_fallback_send_not_optimized_method_type,
        send_fallback_send_not_optimized_need_permission,
        send_fallback_ccall_with_frame_too_many_args,
        send_fallback_argc_param_mismatch,
        // The call has at least one feature on the caller or callee side
        // that the optimizer does not support.
        send_fallback_one_or_more_complex_arg_pass,
        // Caller has keyword arguments but callee doesn't expect them.
        send_fallback_unexpected_keyword_args,
        send_fallback_bmethod_non_iseq_proc,
        send_fallback_obj_to_string_not_string,
        send_fallback_send_cfunc_variadic,
        send_fallback_send_cfunc_array_variadic,
        send_fallback_uncategorized,
    }

    // Optimized send counters that are summed as optimized_send_count
    optimized_send {
        iseq_optimized_send_count,
        inline_cfunc_optimized_send_count,
        inline_iseq_optimized_send_count,
        non_variadic_cfunc_optimized_send_count,
        variadic_cfunc_optimized_send_count,
    }

    // Ivar fallback counters that are summed as dynamic_setivar_count
    dynamic_setivar {
        // setivar_fallback_: Fallback reasons for dynamic setivar instructions
        setivar_fallback_not_monomorphic,
        setivar_fallback_immediate,
        setivar_fallback_not_t_object,
        setivar_fallback_too_complex,
        setivar_fallback_frozen,
        setivar_fallback_shape_transition,
        setivar_fallback_new_shape_too_complex,
        setivar_fallback_new_shape_needs_extension,
    }

    // Ivar fallback counters that are summed as dynamic_getivar_count
    dynamic_getivar {
        // getivar_fallback_: Fallback reasons for dynamic getivar instructions
        getivar_fallback_not_monomorphic,
        getivar_fallback_immediate,
        getivar_fallback_not_t_object,
        getivar_fallback_too_complex,
    }

    // Ivar fallback counters that are summed as dynamic_definedivar_count
    dynamic_definedivar {
        // definedivar_fallback_: Fallback reasons for dynamic definedivar instructions
        definedivar_fallback_not_monomorphic,
        definedivar_fallback_immediate,
        definedivar_fallback_not_t_object,
        definedivar_fallback_too_complex,
    }

    // compile_error_: Compile error reasons
    compile_error_iseq_version_limit_reached,
    compile_error_iseq_stack_too_large,
    compile_error_exception_handler,
    compile_error_out_of_memory,
    compile_error_jit_to_jit_optional,
    compile_error_register_spill_on_ccall,
    compile_error_register_spill_on_alloc,
    compile_error_parse_stack_underflow,
    compile_error_parse_malformed_iseq,
    compile_error_parse_not_allowed,
    compile_error_validation_block_has_no_terminator,
    compile_error_validation_terminator_not_at_end,
    compile_error_validation_mismatched_block_arity,
    compile_error_validation_jump_target_not_in_rpo,
    compile_error_validation_operand_not_defined,
    compile_error_validation_duplicate_instruction,
    compile_error_validation_type_check_failure,
    compile_error_validation_misc_validation_error,

    // unhandled_hir_insn_: Unhandled HIR instructions
    unhandled_hir_insn_array_max,
    unhandled_hir_insn_fixnum_div,
    unhandled_hir_insn_throw,
    unhandled_hir_insn_invokebuiltin,
    unhandled_hir_insn_unknown,

    // The number of times YARV instructions are executed on JIT code
    zjit_insn_count,

    // Method call def_type related to send without block fallback to dynamic dispatch
    unspecialized_send_without_block_def_type_iseq,
    unspecialized_send_without_block_def_type_cfunc,
    unspecialized_send_without_block_def_type_attrset,
    unspecialized_send_without_block_def_type_ivar,
    unspecialized_send_without_block_def_type_bmethod,
    unspecialized_send_without_block_def_type_zsuper,
    unspecialized_send_without_block_def_type_alias,
    unspecialized_send_without_block_def_type_undef,
    unspecialized_send_without_block_def_type_not_implemented,
    unspecialized_send_without_block_def_type_optimized,
    unspecialized_send_without_block_def_type_missing,
    unspecialized_send_without_block_def_type_refined,
    unspecialized_send_without_block_def_type_null,

    // Method call optimized_type related to send without block fallback to dynamic dispatch
    unspecialized_send_without_block_def_type_optimized_send,
    unspecialized_send_without_block_def_type_optimized_call,
    unspecialized_send_without_block_def_type_optimized_block_call,
    unspecialized_send_without_block_def_type_optimized_struct_aref,
    unspecialized_send_without_block_def_type_optimized_struct_aset,

    // Method call def_type related to send fallback to dynamic dispatch
    unspecialized_send_def_type_iseq,
    unspecialized_send_def_type_cfunc,
    unspecialized_send_def_type_attrset,
    unspecialized_send_def_type_ivar,
    unspecialized_send_def_type_bmethod,
    unspecialized_send_def_type_zsuper,
    unspecialized_send_def_type_alias,
    unspecialized_send_def_type_undef,
    unspecialized_send_def_type_not_implemented,
    unspecialized_send_def_type_optimized,
    unspecialized_send_def_type_missing,
    unspecialized_send_def_type_refined,
    unspecialized_send_def_type_null,

    // Unsupported parameter features
    complex_arg_pass_param_rest,
    complex_arg_pass_param_post,
    complex_arg_pass_param_kw_opt,
    complex_arg_pass_param_kwrest,
    complex_arg_pass_param_block,
    complex_arg_pass_param_forwardable,

    // Unsupported caller side features
    complex_arg_pass_caller_splat,
    complex_arg_pass_caller_blockarg,
    complex_arg_pass_caller_kwarg,
    complex_arg_pass_caller_kw_splat,
    complex_arg_pass_caller_tailcall,
    complex_arg_pass_caller_super,
    complex_arg_pass_caller_zsuper,
    complex_arg_pass_caller_forwarding,

    // Writes to the VM frame
    vm_write_pc_count,
    vm_write_sp_count,
    vm_write_locals_count,
    vm_write_stack_count,
    vm_write_to_parent_iseq_local_count,
    vm_read_from_parent_iseq_local_count,
    // TODO(max): Implement
    // vm_reify_stack_count,

    // The number of times we ran a dynamic check
    guard_type_count,
    guard_shape_count,

    invokeblock_handler_monomorphic_iseq,
    invokeblock_handler_monomorphic_ifunc,
    invokeblock_handler_monomorphic_other,
    invokeblock_handler_polymorphic,
    invokeblock_handler_megamorphic,
    invokeblock_handler_no_profiles,
}

/// Increase a counter by a specified amount
pub fn incr_counter_by(counter: Counter, amount: u64) {
    let ptr = counter_ptr(counter);
    unsafe { *ptr += amount; }
}

/// Decrease a counter by a specified amount
pub fn decr_counter_by(counter: Counter, amount: u64) {
    let ptr = counter_ptr(counter);
    unsafe { *ptr -= amount; }
}

/// Increment a counter by its identifier
macro_rules! incr_counter {
    ($counter_name:ident) => {
        $crate::stats::incr_counter_by($crate::stats::Counter::$counter_name, 1)
    }
}
pub(crate) use incr_counter;

/// The number of side exits from each YARV instruction
pub type InsnCounters = [u64; VM_INSTRUCTION_SIZE as usize];

/// Return a raw pointer to the exit counter for a given YARV opcode
pub fn exit_counter_ptr_for_opcode(opcode: u32) -> *mut u64 {
    let exit_counters = ZJITState::get_exit_counters();
    unsafe { exit_counters.get_unchecked_mut(opcode as usize) }
}

/// Return a raw pointer to the fallback counter for a given YARV opcode
pub fn send_fallback_counter_ptr_for_opcode(opcode: u32) -> *mut u64 {
    let fallback_counters = ZJITState::get_send_fallback_counters();
    unsafe { fallback_counters.get_unchecked_mut(opcode as usize) }
}

/// Reason why ZJIT failed to produce any JIT code
#[derive(Clone, Debug, PartialEq)]
pub enum CompileError {
    IseqVersionLimitReached,
    IseqStackTooLarge,
    ExceptionHandler,
    OutOfMemory,
    ParseError(ParseError),
}

/// Return a raw pointer to the exit counter for a given CompileError
pub fn exit_counter_for_compile_error(compile_error: &CompileError) -> Counter {
    use crate::hir::ParseError::*;
    use crate::hir::ValidationError::*;
    use crate::stats::CompileError::*;
    use crate::stats::Counter::*;
    match compile_error {
        IseqVersionLimitReached => compile_error_iseq_version_limit_reached,
        IseqStackTooLarge       => compile_error_iseq_stack_too_large,
        ExceptionHandler        => compile_error_exception_handler,
        OutOfMemory             => compile_error_out_of_memory,
        ParseError(parse_error) => match parse_error {
            StackUnderflow(_)       => compile_error_parse_stack_underflow,
            MalformedIseq(_)        => compile_error_parse_malformed_iseq,
            NotAllowed              => compile_error_parse_not_allowed,
            Validation(validation) => match validation {
                BlockHasNoTerminator(_)       => compile_error_validation_block_has_no_terminator,
                TerminatorNotAtEnd(_, _, _)   => compile_error_validation_terminator_not_at_end,
                MismatchedBlockArity(_, _, _) => compile_error_validation_mismatched_block_arity,
                JumpTargetNotInRPO(_)         => compile_error_validation_jump_target_not_in_rpo,
                OperandNotDefined(_, _, _)    => compile_error_validation_operand_not_defined,
                DuplicateInstruction(_, _)    => compile_error_validation_duplicate_instruction,
                MismatchedOperandType(..)     => compile_error_validation_type_check_failure,
                MiscValidationError(..)       => compile_error_validation_misc_validation_error,
            },
        }
    }
}

pub fn exit_counter_for_unhandled_hir_insn(insn: &crate::hir::Insn) -> Counter {
    use crate::hir::Insn::*;
    use crate::stats::Counter::*;
    match insn {
        ArrayMax { .. }      => unhandled_hir_insn_array_max,
        FixnumDiv { .. }     => unhandled_hir_insn_fixnum_div,
        Throw { .. }         => unhandled_hir_insn_throw,
        InvokeBuiltin { .. } => unhandled_hir_insn_invokebuiltin,
        _                    => unhandled_hir_insn_unknown,
    }
}

pub fn side_exit_counter(reason: crate::hir::SideExitReason) -> Counter {
    use crate::hir::SideExitReason::*;
    use crate::hir::CallType::*;
    use crate::hir::Invariant;
    use crate::stats::Counter::*;
    match reason {
        UnhandledNewarraySend(send_type) => match send_type {
            VM_OPT_NEWARRAY_SEND_MIN  => exit_unhandled_newarray_send_min,
            VM_OPT_NEWARRAY_SEND_HASH => exit_unhandled_newarray_send_hash,
            VM_OPT_NEWARRAY_SEND_PACK => exit_unhandled_newarray_send_pack,
            VM_OPT_NEWARRAY_SEND_PACK_BUFFER => exit_unhandled_newarray_send_pack_buffer,
            _                         => exit_unhandled_newarray_send_unknown,
        }
        UnhandledDuparraySend(_)      => exit_unhandled_duparray_send,
        UnhandledCallType(Tailcall)   => exit_unhandled_tailcall,
        UnhandledCallType(Splat)      => exit_unhandled_splat,
        UnhandledCallType(Kwarg)      => exit_unhandled_kwarg,
        UnknownSpecialVariable(_)     => exit_unknown_special_variable,
        UnhandledHIRInsn(_)           => exit_unhandled_hir_insn,
        UnhandledYARVInsn(_)          => exit_unhandled_yarv_insn,
        FixnumAddOverflow             => exit_fixnum_add_overflow,
        FixnumSubOverflow             => exit_fixnum_sub_overflow,
        FixnumMultOverflow            => exit_fixnum_mult_overflow,
        FixnumLShiftOverflow          => exit_fixnum_lshift_overflow,
        FixnumModByZero               => exit_fixnum_mod_by_zero,
        FixnumDivByZero               => exit_fixnum_div_by_zero,
        BoxFixnumOverflow             => exit_box_fixnum_overflow,
        GuardType(_)                  => exit_guard_type_failure,
        GuardTypeNot(_)               => exit_guard_type_not_failure,
        GuardBitEquals(_)             => exit_guard_bit_equals_failure,
        GuardShape(_)                 => exit_guard_shape_failure,
        GuardNotFrozen                => exit_guard_not_frozen_failure,
        GuardLess                     => exit_guard_less_failure,
        GuardGreaterEq                => exit_guard_greater_eq_failure,
        CalleeSideExit                => exit_callee_side_exit,
        ObjToStringFallback           => exit_obj_to_string_fallback,
        Interrupt                     => exit_interrupt,
        StackOverflow                 => exit_stackoverflow,
        BlockParamProxyModified       => exit_block_param_proxy_modified,
        BlockParamProxyNotIseqOrIfunc => exit_block_param_proxy_not_iseq_or_ifunc,
        TooManyKeywordParameters      => exit_too_many_keyword_parameters,
        PatchPoint(Invariant::BOPRedefined { .. })
                                      => exit_patchpoint_bop_redefined,
        PatchPoint(Invariant::MethodRedefined { .. })
                                      => exit_patchpoint_method_redefined,
        PatchPoint(Invariant::StableConstantNames { .. })
                                      => exit_patchpoint_stable_constant_names,
        PatchPoint(Invariant::NoTracePoint)
                                      => exit_patchpoint_no_tracepoint,
        PatchPoint(Invariant::NoEPEscape(_))
                                      => exit_patchpoint_no_ep_escape,
        PatchPoint(Invariant::SingleRactorMode)
                                      => exit_patchpoint_single_ractor_mode,
        PatchPoint(Invariant::NoSingletonClass { .. })
                                      => exit_patchpoint_no_singleton_class,
    }
}

pub fn exit_counter_ptr(reason: crate::hir::SideExitReason) -> *mut u64 {
    let counter = side_exit_counter(reason);
    counter_ptr(counter)
}

pub fn send_fallback_counter(reason: crate::hir::SendFallbackReason) -> Counter {
    use crate::hir::SendFallbackReason::*;
    use crate::stats::Counter::*;
    match reason {
        SendWithoutBlockPolymorphic               => send_fallback_send_without_block_polymorphic,
        SendWithoutBlockMegamorphic               => send_fallback_send_without_block_megamorphic,
        SendWithoutBlockNoProfiles                => send_fallback_send_without_block_no_profiles,
        SendWithoutBlockCfuncNotVariadic          => send_fallback_send_without_block_cfunc_not_variadic,
        SendWithoutBlockCfuncArrayVariadic        => send_fallback_send_without_block_cfunc_array_variadic,
        SendWithoutBlockNotOptimizedMethodType(_) => send_fallback_send_without_block_not_optimized_method_type,
        SendWithoutBlockNotOptimizedMethodTypeOptimized(_)
                                                  => send_fallback_send_without_block_not_optimized_method_type_optimized,
        SendWithoutBlockNotOptimizedNeedPermission
                                                  => send_fallback_send_without_block_not_optimized_need_permission,
        TooManyArgsForLir                         => send_fallback_too_many_args_for_lir,
        SendWithoutBlockBopRedefined              => send_fallback_send_without_block_bop_redefined,
        SendWithoutBlockOperandsNotFixnum         => send_fallback_send_without_block_operands_not_fixnum,
        SendWithoutBlockDirectKeywordMismatch     => send_fallback_send_without_block_direct_keyword_mismatch,
        SendWithoutBlockDirectOptionalKeywords    => send_fallback_send_without_block_direct_optional_keywords,
        SendWithoutBlockDirectKeywordCountMismatch=> send_fallback_send_without_block_direct_keyword_count_mismatch,
        SendWithoutBlockDirectMissingKeyword       => send_fallback_send_without_block_direct_missing_keyword,
        SendPolymorphic                           => send_fallback_send_polymorphic,
        SendMegamorphic                           => send_fallback_send_megamorphic,
        SendNoProfiles                            => send_fallback_send_no_profiles,
        SendCfuncVariadic                         => send_fallback_send_cfunc_variadic,
        SendCfuncArrayVariadic                    => send_fallback_send_cfunc_array_variadic,
        ComplexArgPass                            => send_fallback_one_or_more_complex_arg_pass,
        UnexpectedKeywordArgs                     => send_fallback_unexpected_keyword_args,
        ArgcParamMismatch                         => send_fallback_argc_param_mismatch,
        BmethodNonIseqProc                        => send_fallback_bmethod_non_iseq_proc,
        SendNotOptimizedMethodType(_)             => send_fallback_send_not_optimized_method_type,
        SendNotOptimizedNeedPermission            => send_fallback_send_not_optimized_need_permission,
        CCallWithFrameTooManyArgs                 => send_fallback_ccall_with_frame_too_many_args,
        ObjToStringNotString                      => send_fallback_obj_to_string_not_string,
        Uncategorized(_)                          => send_fallback_uncategorized,
    }
}

pub fn send_without_block_fallback_counter_for_method_type(method_type: crate::hir::MethodType) -> Counter {
    use crate::hir::MethodType::*;
    use crate::stats::Counter::*;

    match method_type {
        Iseq => unspecialized_send_without_block_def_type_iseq,
        Cfunc => unspecialized_send_without_block_def_type_cfunc,
        Attrset => unspecialized_send_without_block_def_type_attrset,
        Ivar => unspecialized_send_without_block_def_type_ivar,
        Bmethod => unspecialized_send_without_block_def_type_bmethod,
        Zsuper => unspecialized_send_without_block_def_type_zsuper,
        Alias => unspecialized_send_without_block_def_type_alias,
        Undefined => unspecialized_send_without_block_def_type_undef,
        NotImplemented => unspecialized_send_without_block_def_type_not_implemented,
        Optimized => unspecialized_send_without_block_def_type_optimized,
        Missing => unspecialized_send_without_block_def_type_missing,
        Refined => unspecialized_send_without_block_def_type_refined,
        Null => unspecialized_send_without_block_def_type_null,
    }
}

pub fn send_without_block_fallback_counter_for_optimized_method_type(method_type: crate::hir::OptimizedMethodType) -> Counter {
    use crate::hir::OptimizedMethodType::*;
    use crate::stats::Counter::*;

    match method_type {
        Send => unspecialized_send_without_block_def_type_optimized_send,
        Call => unspecialized_send_without_block_def_type_optimized_call,
        BlockCall => unspecialized_send_without_block_def_type_optimized_block_call,
        StructAref => unspecialized_send_without_block_def_type_optimized_struct_aref,
        StructAset => unspecialized_send_without_block_def_type_optimized_struct_aset,
    }
}

pub fn send_fallback_counter_for_method_type(method_type: crate::hir::MethodType) -> Counter {
    use crate::hir::MethodType::*;
    use crate::stats::Counter::*;

    match method_type {
        Iseq => unspecialized_send_def_type_iseq,
        Cfunc => unspecialized_send_def_type_cfunc,
        Attrset => unspecialized_send_def_type_attrset,
        Ivar => unspecialized_send_def_type_ivar,
        Bmethod => unspecialized_send_def_type_bmethod,
        Zsuper => unspecialized_send_def_type_zsuper,
        Alias => unspecialized_send_def_type_alias,
        Undefined => unspecialized_send_def_type_undef,
        NotImplemented => unspecialized_send_def_type_not_implemented,
        Optimized => unspecialized_send_def_type_optimized,
        Missing => unspecialized_send_def_type_missing,
        Refined => unspecialized_send_def_type_refined,
        Null => unspecialized_send_def_type_null,
    }
}

/// Primitive called in zjit.rb. Zero out all the counters.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_reset_stats_bang(_ec: EcPtr, _self: VALUE) -> VALUE {
    let counters = ZJITState::get_counters();
    let exit_counters = ZJITState::get_exit_counters();

    // Reset all counters to zero
    *counters = Counters::default();

    // Reset exit counters for YARV instructions
    exit_counters.as_mut_slice().fill(0);

    Qnil
}

/// Return a Hash object that contains ZJIT statistics
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_stats(_ec: EcPtr, _self: VALUE, target_key: VALUE) -> VALUE {
    if !zjit_enabled_p() {
        return Qnil;
    }

    macro_rules! set_stat {
        ($hash:ident, $key:expr, $value:expr) => {
            let key = rust_str_to_sym($key);
            if key == target_key {
                return $value;
            } else if $hash != Qnil {
                #[allow(unused_unsafe)]
                unsafe { rb_hash_aset($hash, key, $value); }
            }
        };
    }

    macro_rules! set_stat_usize {
        ($hash:ident, $key:expr, $value:expr) => {
            set_stat!($hash, $key, VALUE::fixnum_from_usize($value as usize))
        }
    }

    macro_rules! set_stat_f64 {
        ($hash:ident, $key:expr, $value:expr) => {
            set_stat!($hash, $key, unsafe { rb_float_new($value) })
        }
    }

    let hash = if target_key.nil_p() {
        unsafe { rb_hash_new() }
    } else {
        Qnil
    };

    // Set default counters
    for &counter in DEFAULT_COUNTERS {
        set_stat_usize!(hash, &counter.name(), unsafe { *counter_ptr(counter) });
    }

    // Memory usage stats
    let code_region_bytes = ZJITState::get_code_block().mapped_region_size();
    set_stat_usize!(hash, "code_region_bytes", code_region_bytes);
    set_stat_usize!(hash, "zjit_alloc_bytes", zjit_alloc_bytes());
    set_stat_usize!(hash, "total_mem_bytes", code_region_bytes + zjit_alloc_bytes());

    // End of default stats. Every counter beyond this is provided only for --zjit-stats.
    if !get_option!(stats) {
        return hash;
    }

    // Set other stats-only counters
    for &counter in OTHER_COUNTERS {
        set_stat_usize!(hash, &counter.name(), unsafe { *counter_ptr(counter) });
    }

    // Set side-exit counters for each SideExitReason
    let mut side_exit_count = 0;
    for &counter in EXIT_COUNTERS {
        let count = unsafe { *counter_ptr(counter) };
        side_exit_count += count;
        set_stat_usize!(hash, &counter.name(), count);
    }
    set_stat_usize!(hash, "side_exit_count", side_exit_count);

    // Set side-exit counters for UnhandledYARVInsn
    let exit_counters = ZJITState::get_exit_counters();
    for (op_idx, count) in exit_counters.iter().enumerate().take(VM_INSTRUCTION_SIZE as usize) {
        let op_name = insn_name(op_idx);
        let key_string = "unhandled_yarv_insn_".to_owned() + &op_name;
        set_stat_usize!(hash, &key_string, *count);
    }

    // Set send fallback counters for each DynamicSendReason
    let mut dynamic_send_count = 0;
    for &counter in DYNAMIC_SEND_COUNTERS {
        let count = unsafe { *counter_ptr(counter) };
        dynamic_send_count += count;
        set_stat_usize!(hash, &counter.name(), count);
    }
    set_stat_usize!(hash, "dynamic_send_count", dynamic_send_count);

    // Set optimized send counters
    let mut optimized_send_count = 0;
    for &counter in OPTIMIZED_SEND_COUNTERS {
        let count = unsafe { *counter_ptr(counter) };
        optimized_send_count += count;
        set_stat_usize!(hash, &counter.name(), count);
    }
    set_stat_usize!(hash, "optimized_send_count", optimized_send_count);
    set_stat_usize!(hash, "send_count", dynamic_send_count + optimized_send_count);

    // Set send fallback counters for each setivar fallback reason
    let mut dynamic_setivar_count = 0;
    for &counter in DYNAMIC_SETIVAR_COUNTERS {
        let count = unsafe { *counter_ptr(counter) };
        dynamic_setivar_count += count;
        set_stat_usize!(hash, &counter.name(), count);
    }
    set_stat_usize!(hash, "dynamic_setivar_count", dynamic_setivar_count);

    // Set send fallback counters for each getivar fallback reason
    let mut dynamic_getivar_count = 0;
    for &counter in DYNAMIC_GETIVAR_COUNTERS {
        let count = unsafe { *counter_ptr(counter) };
        dynamic_getivar_count += count;
        set_stat_usize!(hash, &counter.name(), count);
    }
    set_stat_usize!(hash, "dynamic_getivar_count", dynamic_getivar_count);

    // Set send fallback counters for each definedivar fallback reason
    let mut dynamic_definedivar_count = 0;
    for &counter in DYNAMIC_DEFINEDIVAR_COUNTERS {
        let count = unsafe { *counter_ptr(counter) };
        dynamic_definedivar_count += count;
        set_stat_usize!(hash, &counter.name(), count);
    }
    set_stat_usize!(hash, "dynamic_definedivar_count", dynamic_definedivar_count);

    // Set send fallback counters for Uncategorized
    let send_fallback_counters = ZJITState::get_send_fallback_counters();
    for (op_idx, count) in send_fallback_counters.iter().enumerate().take(VM_INSTRUCTION_SIZE as usize) {
        let op_name = insn_name(op_idx);
        let key_string = "uncategorized_fallback_yarv_insn_".to_owned() + &op_name;
        set_stat_usize!(hash, &key_string, *count);
    }

    // Only ZJIT_STATS builds support rb_vm_insn_count
    if unsafe { rb_vm_insn_count } > 0 {
        let vm_insn_count = unsafe { rb_vm_insn_count };
        set_stat_usize!(hash, "vm_insn_count", vm_insn_count);

        let zjit_insn_count = ZJITState::get_counters().zjit_insn_count;
        let total_insn_count = vm_insn_count + zjit_insn_count;
        set_stat_usize!(hash, "total_insn_count", total_insn_count);

        set_stat_f64!(hash, "ratio_in_zjit", 100.0 * zjit_insn_count as f64 / total_insn_count as f64);
    }

    // Set not inlined cfunc counters
    let not_inlined_cfuncs = ZJITState::get_not_inlined_cfunc_counter_pointers();
    for (signature, counter) in not_inlined_cfuncs.iter() {
        let key_string = format!("not_inlined_cfuncs_{signature}");
        set_stat_usize!(hash, &key_string, **counter);
    }

    // Set not annotated cfunc counters
    let not_annotated_cfuncs = ZJITState::get_not_annotated_cfunc_counter_pointers();
    for (signature, counter) in not_annotated_cfuncs.iter() {
        let key_string = format!("not_annotated_cfuncs_{signature}");
        set_stat_usize!(hash, &key_string, **counter);
    }

    // Set ccall counters
    let ccall = ZJITState::get_ccall_counter_pointers();
    for (signature, counter) in ccall.iter() {
        let key_string = format!("ccall_{signature}");
        set_stat_usize!(hash, &key_string, **counter);
    }

    hash
}

/// Measure the time taken by func() and add that to zjit_compile_time.
pub fn with_time_stat<F, R>(counter: Counter, func: F) -> R where F: FnOnce() -> R {
    let start = Instant::now();
    let ret = func();
    let nanos = Instant::now().duration_since(start).as_nanos();
    incr_counter_by(counter, nanos as u64);
    ret
}

/// The number of bytes ZJIT has allocated on the Rust heap.
pub fn zjit_alloc_bytes() -> usize {
    jit::GLOBAL_ALLOCATOR.alloc_size.load(Ordering::SeqCst)
}

/// Struct of arrays for --zjit-trace-exits.
#[derive(Default)]
pub struct SideExitLocations {
    /// Control frames of method entries.
    pub raw_samples: Vec<VALUE>,
    /// Line numbers of the iseq caller.
    pub line_samples: Vec<i32>,
    /// Skipped samples
    pub skipped_samples: usize
}

/// Primitive called in zjit.rb
///
/// Check if trace_exits generation is enabled.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_trace_exit_locations_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    // Builtin zjit.rb calls this even if ZJIT is disabled, so OPTIONS may not be set.
    if unsafe { OPTIONS.as_ref() }.is_some_and(|opts| opts.trace_side_exits.is_some()) {
        Qtrue
    } else {
        Qfalse
    }
}

/// Call the C function to parse the raw_samples and line_samples
/// into raw, lines, and frames hash for RubyVM::YJIT.exit_locations.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_get_exit_locations(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if !zjit_enabled_p() || get_option!(trace_side_exits).is_none() {
        return Qnil;
    }

    // Can safely unwrap since `trace_side_exits` must be true at this point
    let zjit_raw_samples = ZJITState::get_raw_samples().unwrap();
    let zjit_line_samples = ZJITState::get_line_samples().unwrap();

    assert_eq!(zjit_raw_samples.len(), zjit_line_samples.len());

    // zjit_raw_samples and zjit_line_samples are the same length so
    // pass only one of the lengths in the C function.
    let samples_len = zjit_raw_samples.len() as i32;

    unsafe {
        rb_zjit_exit_locations_dict(
            zjit_raw_samples.as_mut_ptr(),
            zjit_line_samples.as_mut_ptr(),
            samples_len
        )
    }
}
