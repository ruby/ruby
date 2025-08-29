use std::time::Instant;

use crate::{cruby::*, options::get_option, state::{zjit_enabled_p, ZJITState}};

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
        compilation_failure,

        compile_time_ns,
        profile_time_ns,
        gc_time_ns,
        invalidation_time_ns,
    }

    // Exit counters that are summed as side_exit_count
    exit {
        // exit_: Side exits reasons
        exit_compilation_failure,
        exit_unknown_newarray_send,
        exit_unknown_call_type,
        exit_unknown_special_variable,
        exit_unhandled_hir_insn,
        exit_unhandled_yarv_insn,
        exit_fixnum_add_overflow,
        exit_fixnum_sub_overflow,
        exit_fixnum_mult_overflow,
        exit_guard_type_failure,
        exit_guard_bit_equals_failure,
        exit_guard_shape_failure,
        exit_patchpoint,
        exit_callee_side_exit,
        exit_obj_to_string_fallback,
        exit_interrupt,
    }

    // failed_: Compilation failure reasons
    failed_iseq_stack_too_large,
    failed_hir_compile,
    failed_hir_compile_validate,
    failed_hir_optimize,
    failed_asm_compile,

    // The number of times YARV instructions are executed on JIT code
    zjit_insn_count,

    // The number of times we do a dynamic dispatch from JIT code
    dynamic_send_count,
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

pub fn exit_counter_ptr(reason: crate::hir::SideExitReason) -> *mut u64 {
    use crate::hir::SideExitReason::*;
    use crate::stats::Counter::*;
    let counter = match reason {
        UnknownNewarraySend(_)    => exit_unknown_newarray_send,
        UnknownCallType           => exit_unknown_call_type,
        UnknownSpecialVariable(_) => exit_unknown_special_variable,
        UnhandledHIRInsn(_)       => exit_unhandled_hir_insn,
        UnhandledYARVInsn(_)      => exit_unhandled_yarv_insn,
        FixnumAddOverflow         => exit_fixnum_add_overflow,
        FixnumSubOverflow         => exit_fixnum_sub_overflow,
        FixnumMultOverflow        => exit_fixnum_mult_overflow,
        GuardType(_)              => exit_guard_type_failure,
        GuardBitEquals(_)         => exit_guard_bit_equals_failure,
        GuardShape(_)             => exit_guard_shape_failure,
        PatchPoint(_)             => exit_patchpoint,
        CalleeSideExit            => exit_callee_side_exit,
        ObjToStringFallback       => exit_obj_to_string_fallback,
        Interrupt                 => exit_interrupt,
    };
    counter_ptr(counter)
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
    for op_idx in 0..VM_INSTRUCTION_SIZE as usize {
        let op_name = insn_name(op_idx);
        let key_string = "unhandled_yarv_insn_".to_owned() + &op_name;
        let count = exit_counters[op_idx];
        set_stat_usize!(hash, &key_string, count);
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
    0 // TODO: report the actual memory usage to support --zjit-mem-size (Shopify/ruby#686)
}
