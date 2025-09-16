//! Counters and associated methods for events when ZJIT is run.

use std::time::Instant;
use std::sync::atomic::Ordering;

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
        $($counter_name:ident,)+
    ) => {
        /// Struct containing the counter values
        #[derive(Default, Debug)]
        pub struct Counters {
            $(pub $default_counter_name: u64,)+
            $(pub $exit_counter_name: u64,)+
            $(pub $counter_name: u64,)+
        }

        /// Enum to represent a counter
        #[allow(non_camel_case_types)]
        #[derive(Clone, Copy, PartialEq, Eq, Debug)]
        pub enum Counter {
            $($default_counter_name,)+
            $($exit_counter_name,)+
            $($counter_name,)+
        }

        impl Counter {
            pub fn name(&self) -> String {
                match self {
                    $( Counter::$default_counter_name => stringify!($default_counter_name).to_string(), )+
                    $( Counter::$exit_counter_name => stringify!($exit_counter_name).to_string(), )+
                    $( Counter::$counter_name => stringify!($counter_name).to_string(), )+
                }
            }
        }

        /// Map a counter to a pointer
        pub fn counter_ptr(counter: Counter) -> *mut u64 {
            let counters = $crate::state::ZJITState::get_counters();
            match counter {
                $( Counter::$default_counter_name => std::ptr::addr_of_mut!(counters.$default_counter_name), )+
                $( Counter::$exit_counter_name => std::ptr::addr_of_mut!(counters.$exit_counter_name), )+
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
        exit_unknown_newarray_send,
        exit_unhandled_tailcall,
        exit_unhandled_splat,
        exit_unhandled_kwarg,
        exit_unknown_special_variable,
        exit_unhandled_hir_insn,
        exit_unhandled_yarv_insn,
        exit_fixnum_add_overflow,
        exit_fixnum_sub_overflow,
        exit_fixnum_mult_overflow,
        exit_guard_type_failure,
        exit_guard_type_not_failure,
        exit_guard_bit_equals_failure,
        exit_guard_shape_failure,
        exit_patchpoint,
        exit_callee_side_exit,
        exit_obj_to_string_fallback,
        exit_interrupt,
        exit_stackoverflow,
        exit_optional_arguments,
        exit_block_param_proxy_modified,
        exit_block_param_proxy_not_iseq_or_ifunc,
    }

    // unhanded_call_: Unhandled call types
    unhandled_call_block_arg,
    unhandled_call_tailcall,

    // compile_error_: Compile error reasons
    compile_error_iseq_stack_too_large,
    compile_error_exception_handler,
    compile_error_out_of_memory,
    compile_error_register_spill_on_ccall,
    compile_error_register_spill_on_alloc,
    compile_error_parse_stack_underflow,
    compile_error_parse_malformed_iseq,
    compile_error_parse_validation,
    compile_error_parse_not_allowed,

    // The number of times YARV instructions are executed on JIT code
    zjit_insn_count,

    // The number of times we do a dynamic dispatch from JIT code
    dynamic_send_count,
    dynamic_send_type_send_without_block,
    dynamic_send_type_send,
    dynamic_send_type_invokeblock,
    dynamic_send_type_invokesuper,
}

/// Increase a counter by a specified amount
pub fn incr_counter_by(counter: Counter, amount: u64) {
    let ptr = counter_ptr(counter);
    unsafe { *ptr += amount; }
}

/// Increment a counter by its identifier
macro_rules! incr_counter {
    ($counter_name:ident) => {
        $crate::stats::incr_counter_by($crate::stats::Counter::$counter_name, 1)
    }
}
pub(crate) use incr_counter;

/// The number of side exits from each YARV instruction
pub type ExitCounters = [u64; VM_INSTRUCTION_SIZE as usize];

/// Return a raw pointer to the exit counter for a given YARV opcode
pub fn exit_counter_ptr_for_opcode(opcode: u32) -> *mut u64 {
    let exit_counters = ZJITState::get_exit_counters();
    unsafe { exit_counters.get_unchecked_mut(opcode as usize) }
}

/// Reason why ZJIT failed to produce any JIT code
#[derive(Clone, Debug, PartialEq)]
pub enum CompileError {
    IseqStackTooLarge,
    ExceptionHandler,
    OutOfMemory,
    RegisterSpillOnAlloc,
    RegisterSpillOnCCall,
    ParseError(ParseError),
}

/// Return a raw pointer to the exit counter for a given CompileError
pub fn exit_counter_for_compile_error(compile_error: &CompileError) -> Counter {
    use crate::hir::ParseError::*;
    use crate::stats::CompileError::*;
    use crate::stats::Counter::*;
    match compile_error {
        IseqStackTooLarge     => compile_error_iseq_stack_too_large,
        ExceptionHandler      => compile_error_exception_handler,
        OutOfMemory           => compile_error_out_of_memory,
        RegisterSpillOnAlloc  => compile_error_register_spill_on_alloc,
        RegisterSpillOnCCall  => compile_error_register_spill_on_ccall,
        ParseError(parse_error) => match parse_error {
            StackUnderflow(_) => compile_error_parse_stack_underflow,
            MalformedIseq(_)  => compile_error_parse_malformed_iseq,
            Validation(_)     => compile_error_parse_validation,
            NotAllowed        => compile_error_parse_not_allowed,
        }
    }
}

pub fn exit_counter_ptr(reason: crate::hir::SideExitReason) -> *mut u64 {
    use crate::hir::SideExitReason::*;
    use crate::hir::CallType::*;
    use crate::stats::Counter::*;
    let counter = match reason {
        UnknownNewarraySend(_)        => exit_unknown_newarray_send,
        UnhandledCallType(Tailcall)   => exit_unhandled_tailcall,
        UnhandledCallType(Splat)      => exit_unhandled_splat,
        UnhandledCallType(Kwarg)      => exit_unhandled_kwarg,
        UnknownSpecialVariable(_)     => exit_unknown_special_variable,
        UnhandledHIRInsn(_)           => exit_unhandled_hir_insn,
        UnhandledYARVInsn(_)          => exit_unhandled_yarv_insn,
        FixnumAddOverflow             => exit_fixnum_add_overflow,
        FixnumSubOverflow             => exit_fixnum_sub_overflow,
        FixnumMultOverflow            => exit_fixnum_mult_overflow,
        GuardType(_)                  => exit_guard_type_failure,
        GuardTypeNot(_)               => exit_guard_type_not_failure,
        GuardBitEquals(_)             => exit_guard_bit_equals_failure,
        GuardShape(_)                 => exit_guard_shape_failure,
        PatchPoint(_)                 => exit_patchpoint,
        CalleeSideExit                => exit_callee_side_exit,
        ObjToStringFallback           => exit_obj_to_string_fallback,
        Interrupt                     => exit_interrupt,
        StackOverflow                 => exit_stackoverflow,
        BlockParamProxyModified       => exit_block_param_proxy_modified,
        BlockParamProxyNotIseqOrIfunc => exit_block_param_proxy_not_iseq_or_ifunc,
    };
    counter_ptr(counter)
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
    set_stat_usize!(hash, "code_region_bytes", ZJITState::get_code_block().mapped_region_size());

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

    // Only ZJIT_STATS builds support rb_vm_insn_count
    if unsafe { rb_vm_insn_count } > 0 {
        let vm_insn_count = unsafe { rb_vm_insn_count };
        set_stat_usize!(hash, "vm_insn_count", vm_insn_count);

        let zjit_insn_count = ZJITState::get_counters().zjit_insn_count;
        let total_insn_count = vm_insn_count + zjit_insn_count;
        set_stat_usize!(hash, "total_insn_count", total_insn_count);

        set_stat_f64!(hash, "ratio_in_zjit", 100.0 * zjit_insn_count as f64 / total_insn_count as f64);
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
pub fn zjit_alloc_size() -> usize {
    jit::GLOBAL_ALLOCATOR.alloc_size.load(Ordering::SeqCst)
}
